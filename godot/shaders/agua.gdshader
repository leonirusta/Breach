shader_type spatial;
// AGUA DE VERDAD (scripts/agua.gd). Un plano por lamina: el mar entero hasta el horizonte y un
// rectangulo por cada rio o lago. Para el motor de voxels no existe: balas, rayos y explosiones lo
// atraviesan como aire, y lo que se ve debajo es el fondo de arena, que SI es voxel.
//
// BARATO A PROPOSITO. La maquina de referencia es una integrada Intel y el objetivo es un movil:
//   - nada de reflejos en pantalla (SSR) ni de refraccion (copiar la pantalla cuesta una pasada
//     entera). El reflejo es el del CIELO, que el entorno ya tiene calculado y sale gratis con una
//     rugosidad baja.
//   - las olas no mueven vertices: se pintan en la NORMAL (cuatro senos sumados). Con voxels de
//     15 cm y un plano de kilometros, desplazar vertices pediria teselar el plano y no se veria mas.
//   - la unica lectura extra es la PROFUNDIDAD de la escena (color segun el fondo, espuma en la
//     orilla y transparencia cerca de la costa). En gama baja (ajuste "Agua" en Simple) agua.gd
//     compila este mismo archivo con AGUA_SIMPLE y ni siquiera se declara la textura: Godot solo
//     copia la profundidad si algun material la pide, asi que el modo simple no paga esa copia.
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;

uniform vec3 color_somero : source_color = vec3(0.10, 0.52, 0.52);
uniform vec3 color_hondo : source_color = vec3(0.02, 0.14, 0.24);
uniform vec3 color_espuma : source_color = vec3(0.92, 0.96, 0.97);
uniform vec3 color_debajo : source_color = vec3(0.05, 0.22, 0.30);   // la superficie vista desde abajo
uniform float hondo_max = 7.0;        // m de agua a partir de los cuales ya es azul profundo
uniform float ancho_espuma = 0.55;    // m de agua por debajo de los cuales hay espuma
uniform float fuerza_olas = 0.10;
uniform float escala_olas = 1.0;

#ifndef AGUA_SIMPLE
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;
#endif

varying vec3 v_mundo;

void vertex() {
	v_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Una ola direccional: devuelve la derivada de su altura en x y z. Solo hace falta la pendiente,
// no la altura, porque el plano no se mueve.
vec2 ola(vec2 p, vec2 dir, float largo, float amp, float vel) {
	float k = 6.2831853 / largo;
	float f = k * dot(dir, p) + TIME * vel * k;
	return dir * (amp * k * cos(f));
}

void fragment() {
	vec2 p = v_mundo.xz * escala_olas;
	vec2 d = vec2(0.0);
	d += ola(p, normalize(vec2(1.0, 0.35)), 9.0, 0.10, 1.3);
	d += ola(p, normalize(vec2(-0.6, 1.0)), 5.3, 0.06, 1.0);
	d += ola(p, normalize(vec2(0.2, -1.0)), 2.7, 0.025, 0.8);
	d += ola(p, normalize(vec2(-1.0, -0.4)), 1.35, 0.012, 0.6);
	// LEJOS SE ALISA. Una ola de metro y medio a 200 m cabe en un pixel: sin esto el horizonte
	// parpadea (el seno se muestrea a saltos) en vez de verse como una lamina que brilla.
	float lejos = length(v_mundo - CAMERA_POSITION_WORLD);
	d *= fuerza_olas * 10.0 * (1.0 - smoothstep(35.0, 260.0, lejos));
	vec3 n_mundo = normalize(vec3(-d.x, 1.0, -d.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_mundo, 0.0)).xyz);

	// CUANTA AGUA HAY DEBAJO de este pixel, en metros a lo largo de la vista.
	float prof = hondo_max * 2.0;
#ifndef AGUA_SIMPLE
	float z = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	// Vulkan (Forward+ y Mobile, que es lo que usa el juego) con la Z invertida: el NDC es el uv y la
	// profundidad tal cual.
	vec4 fondo = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, z, 1.0);
	fondo.xyz /= fondo.w;
	prof = max(0.0, length(fondo.xyz) - length(VERTEX));
	// a lo largo de la vista rasante la capa parece mas gruesa de lo que es: se pasa a vertical
	prof *= clamp(abs(dot(normalize(-VERTEX), mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0))) * 1.4 + 0.15, 0.15, 1.0);
#endif
	float k = clamp(prof / hondo_max, 0.0, 1.0);
	vec3 col = mix(color_somero, color_hondo, sqrt(k));

	// ESPUMA EN LA ORILLA: donde casi no hay agua, con un borde que respira para que no sea una raya
	float espuma = 0.0;
#ifndef AGUA_SIMPLE
	float borde = ancho_espuma * (0.75 + 0.25 * sin(TIME * 1.7 + v_mundo.x * 0.9 + v_mundo.z * 0.7));
	espuma = 1.0 - smoothstep(0.0, borde, prof);
	espuma *= 0.55 + 0.45 * sin(v_mundo.x * 3.1 + TIME * 0.9) * sin(v_mundo.z * 2.7 - TIME * 1.1);
	espuma = clamp(espuma, 0.0, 1.0);
#endif

	// FRESNEL: de lado el agua refleja (cielo) y es opaca; mirando a plomo se ve el fondo.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);

	if (FRONT_FACING) {
		ALBEDO = mix(col, color_espuma, espuma * 0.85);
		// TRANSPARENTE CERCA DE LA COSTA: con poca agua se ve la arena; mar adentro, casi opaca
		float a = mix(0.28, 0.93, smoothstep(0.0, 3.0, prof));
		ALPHA = clamp(max(a + fres * 0.35, espuma * 0.9), 0.0, 1.0);
		ROUGHNESS = 0.1;
		SPECULAR = 0.55;
	} else {
		// DESDE ABAJO (buceando): un techo verdoso y casi opaco, sin espuma ni cielo
		ALBEDO = color_debajo;
		ALPHA = 0.85;
		ROUGHNESS = 0.4;
		SPECULAR = 0.1;
	}
	METALLIC = 0.0;
}
