// Cristal: transparente, sin sombras, ligera reflexion Fresnel. Superficie aparte en cada chunk.
//
// Y SE RAJA. Antes un cristal aguantaba entero hasta que el disparo le quitaba los voxels de golpe:
// pasaba de intacto a agujero, sin nada en medio. Ahora cada impacto deja su estrella de grietas
// alrededor del agujero, que es como se rompe un cristal de verdad, y a base de tiros la luna se va
// llenando de estrellas hasta que no queda nada.
//
// COMO. Las grietas NO son calcomanias pegadas encima: no hay que colocar ningun quad ni acertar con
// su orientacion. Se le pasan al shader las ultimas posiciones donde le han dado, en coordenadas del
// mundo, y cada pixel de cristal mira si le cae cerca alguna. Asi la grieta se pega sola a la
// geometria, da igual como este puesta la luna, y no cuesta ni un dibujado de mas: son 16
// comparaciones de distancia en los pixeles de cristal, que son cuatro en pantalla.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, blend_mix, specular_schlick_ggx;
#include "res://shaders/lamparas.gdshaderinc"

uniform float alpha_value : hint_range(0.0, 1.0) = 0.42;

// xyz: donde le dieron, en el mundo.  w: el radio de la estrella (0 = hueco libre)
const int IMPACTOS = 16;
uniform vec4 impactos[IMPACTOS];

// CHURRETES (ajuste "Texturas de material", 2026-09-30): la capa "cristal" (11) de las texturas de detalle del mundo
// (voxel.gdshader), muy suave: marcas de trapo en diagonal. Una uniform y no una variante: el cristal son cuatro pixeles.
uniform sampler2DArray texturas_voxel : filter_linear_mipmap, repeat_enable, hint_default_white;
uniform float textura_on = 0.0;
uniform float textura_voxel = 0.1;

instance uniform float lod_capa : instance_index(0) = -1.0;
uniform float lod_fade_ini = 4.0;
uniform float lod_fade_fin = 8.0;
uniform float lod_fade2_ini = 16.0;
uniform float lod_fade2_fin = 24.0;
uniform float lod_fade_on = 0.0;   // 0 = transicion apagada: nada se descarta

varying vec3 v_wpos;
varying vec3 v_wnrm;

// TRANSICION DE DETALLE SUAVE (ajuste "Transicion de detalle"). En la franja [lod_fade_ini, lod_fade_fin] se
// dibujan la malla fina (lod_capa 0) y la LOD1 (lod_capa 1) -y mas lejos la LOD1 y la LOD2 (lod_capa 2)- y cada pixel se queda con UNA de las dos segun un
// tramado fijo en pantalla: cerca todo fino, lejos todo LOD1, y en medio el detalle se va afinando de a poco
// al ritmo al que te acercas. Las dos capas usan el mismo umbral al reves, asi que nunca hay huecos ni doble.
// lod_capa -1 (lo que no es mundo: escombros, piezas, sombras) no se toca. Pone la franja VoxelWorld.
bool lod_fade_fuera(float capa, float dist, vec2 frag) {
	if (capa < 0.0 || lod_fade_on < 0.5) {
		return false;
	}
	// LAS CAPAS SE APILAN, NO SE REPARTEN (2026-09-22). Repartiendo cada pixel entre una capa y otra salian
	// AGUJEROS por los que se veia el cielo: la malla fina y la LOD no estan en el mismo sitio -una pared de
	// voxels de 20 cm y la misma de 40 no coinciden en los bordes-, asi que donde el pixel le tocaba a la otra
	// capa y esa capa no tenia superficie ahi, no quedaba ninguna. Ahora la capa gruesa se dibuja ENTERA por
	// debajo y solo se cala la de encima: donde la fina se quita, asoma la gruesa, y nunca el fondo.
	// El vertex() empuja las capas de atras unos centimetros (ver lod_fade_empuje) para que la de delante gane
	// siempre la prueba de profundidad y dos paredes que caen en el mismo plano no parpadeen.
	float tA = clamp((dist - lod_fade_ini) / max(lod_fade_fin - lod_fade_ini, 0.01), 0.0, 1.0);
	float tB = clamp((dist - lod_fade2_ini) / max(lod_fade2_fin - lod_fade2_ini, 0.01), 0.0, 1.0);
	float h = fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));   // ruido de gradiente entrelazado
	if (capa < 0.5) {
		return h < tA;      // la fina: se va calando segun te alejas
	}
	if (capa < 1.5) {
		return h < tB;      // la LOD1: entera bajo la fina, y calada ya de lejos para dejar salir la LOD2
	}
	return false;           // la LOD2 siempre entera: es la de debajo del todo
}

void vertex() {
	// EMPUJE DE LAS CAPAS DE ATRAS, MEDIO METRO. No es contra el parpadeo de dos planos iguales: es que la malla
	// gruesa SOBRESALE de la fina -un voxel de 40 cm redondea hacia fuera- y, dibujada debajo, le ganaba la
	// profundidad y tapaba el detalle: con la transicion puesta se veia todo gordo y al acercarte no mejoraba.
	// Empujada medio voxel gordo por capa, la fina gana siempre; la gruesa solo asoma por donde la fina se cala,
	// y alli esta a 20-30 m, donde medio metro no se nota. Las mallas del mundo solo se trasladan (sin giro).
	if (lod_capa >= 0.5 && lod_fade_on >= 0.5) {
		vec3 wp_lod = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 d_lod = wp_lod - INV_VIEW_MATRIX[3].xyz;
		wp_lod += normalize(d_lod) * (0.45 * lod_capa);
		VERTEX = wp_lod - MODEL_MATRIX[3].xyz;
	}
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash1(float p) {
	return fract(sin(p * 127.1) * 43758.5453);
}

/// La estrella de un impacto. Devuelve cuanto de rajado esta este pixel por culpa de ese golpe.
float estrella(vec3 wp, vec3 nrm, vec4 im) {
	if (im.w <= 0.001) {
		return 0.0;
	}
	vec3 d = wp - im.xyz;
	float r = length(d);
	if (r > im.w) {
		return 0.0;
	}
	// LOS DOS EJES DE LA CARA. Las caras de un voxel miran siempre a un eje, asi que los otros dos
	// son el plano del cristal: con eso se saca el angulo alrededor del agujero sin inventarse una
	// base de coordenadas ni pasar por la UV, que en una malla fusionada no vale para esto.
	vec3 an = abs(nrm);
	vec2 pl = (an.x > 0.5) ? d.zy : ((an.y > 0.5) ? d.xz : d.xy);
	float ang = atan(pl.y, pl.x);
	float sem = hash1(floor(im.x * 7.3) + floor(im.z * 13.7) * 3.1);

	float k = 1.0 - r / im.w;                       // 1 en el agujero, 0 en la punta de la grieta
	// LAS RAJAS QUE SALEN DEL AGUJERO. Pocas y muy finas: subiendo el exponente se estrechan, y un
	// cristal rajado son lineas de pelo, no brochazos.
	float rajas = pow(abs(sin(ang * 3.5 + sem * 12.0)), 34.0);
	rajas = max(rajas, pow(abs(sin(ang * 2.5 - sem * 7.0)), 40.0));
	// y los anillos, que son los que hacen que se lea como cristal y no como una tela de arana
	float anillos = pow(abs(sin(r * 42.0 + sem * 3.0)), 26.0) * 0.55;
	// el borde del agujero, machacado
	float borde = smoothstep(0.10, 0.0, r - im.w * 0.10);
	return clamp(rajas * k + anillos * k * k + borde * 0.8, 0.0, 1.0);
}

void fragment() {
	if (lod_fade_fuera(lod_capa, length(VERTEX), FRAGCOORD.xy)) {
		discard;
	}
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = COLOR.rgb * 0.9 + vec3(0.1);
	// mas reflejo de canto y mas brillo (pedido 2026-09-21: "cristales que brillen y reflejen")
	ALPHA = clamp(alpha_value + fresnel * 0.55, 0.0, 0.92);
	ROUGHNESS = 0.08;
	METALLIC = 0.3;
	SPECULAR = 0.85;
	if (textura_on > 0.5) {
		vec3 an = abs(v_wnrm);
		vec3 p = v_wpos / textura_voxel;
		vec2 t = (an.x > 0.5 ? p.zy : (an.y > 0.5 ? p.xz : p.xy)) * 0.25;
		vec4 tx = texture(texturas_voxel, vec3(t, 11.0));
		float m = 0.7 + 0.6 * tx.r;
		ALBEDO *= m;
		ALPHA = clamp(ALPHA + (m - 1.0) * 0.45, 0.0, 0.95);
		ROUGHNESS = clamp(0.08 + (tx.a - 0.5) * 0.3, 0.02, 0.4);
	}

	float raja = 0.0;
	for (int i = 0; i < IMPACTOS; i++) {
		raja = max(raja, estrella(v_wpos, v_wnrm, impactos[i]));
	}
	if (raja > 0.001) {
		// el cristal roto se vuelve blanco y OPACO: deja de dejar ver, que es la mitad de la gracia
		ALBEDO = mix(ALBEDO, vec3(0.93, 0.96, 1.0), raja);
		ALPHA = clamp(ALPHA + raja * 0.62, 0.0, 0.97);
		ROUGHNESS = mix(ROUGHNESS, 0.55, raja);
		SPECULAR = mix(SPECULAR, 0.9, raja);
	}
	// LAS FAROLAS COCINADAS (lamparas.gdshaderinc), con el color, la normal y la rugosidad ya definitivos
	{
		vec3 l_wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 l_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 l_cam = INV_VIEW_MATRIX[3].xyz;
		vec3 l_dif = vec3(0.0);
		vec3 l_esp = vec3(0.0);
		lamparas(l_wp, l_n, normalize(l_cam - l_wp), ROUGHNESS, SPECULAR, METALLIC, ALBEDO, l_cam, 1.0, l_dif, l_esp);
		EMISSION += l_dif * ALBEDO * (1.0 - METALLIC) + l_esp;
	}
}
