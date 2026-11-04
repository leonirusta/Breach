// DISOLVER: el material se consume por manchas, con el filo encendido, hasta que no queda nada.
//
// NO es mio: es "3D burn dissolve" de Godot Shaders, licencia MIT.
// https://godotshaders.com/shader/3d-burn-dissolve/
// El nucleo -las dos lineas que de verdad hacen el efecto- esta tal cual: un ruido decide en que
// orden se va cada trozo, `ALPHA` borra lo que ya paso el umbral y `EMISSION` enciende justo la
// franja que lo esta cruzando ahora. Eso es lo que hace que parezca que se quema y no que se
// desvanece.
//
// Cuatro cambios, y los cuatro por el mismo motivo: aqui las mallas no son las de un modelo normal.
//
//   1. PORTADO A GODOT 4. `hint_color` -> `source_color`, `hint_albedo` -> `source_color`, y
//      `depth_draw_alpha_prepass` -> `depth_prepass_alpha`, que es como se llama ahora.
//   2. EL COLOR SALE DE LOS VERTICES, no de una textura. Los avatares de Breach se pintan por
//      vertice (voxels), no tienen mapa de color: buscar `texture_albedo` daria un muneco liso.
//   3. EL RUIDO SE LEE POR POSICION, no por UV. Son mallas fusionadas y con huesos: sus UV no son un
//      desplegado, asi que leer ahi da churros estirados. Leyendolo por la posicion dentro del
//      cuerpo, la mancha se pega a la geometria y ademas SE QUEDA QUIETA aunque el cadaver ruede,
//      que es lo que hace que se lea como que se consume y no como que le pasa algo por encima.
//   4. GUARDA EN CERO. Sin disolver, el original seguia encendiendo las zonas de ruido bajo: un
//      cuerpo entero salpicado de puntos naranjas. A cero no toca nada.
shader_type spatial;
render_mode depth_prepass_alpha, cull_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 emission_color : source_color = vec4(1.0, 0.42, 0.10, 1.0);
uniform float emission_amount = 2.6;
uniform sampler2D dissolve_texture : filter_linear, repeat_enable;
uniform float burn_size : hint_range(0.0, 2.0) = 0.14;
uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;
uniform float escala = 36.0;      // cada cuanto se repite el ruido, en unidades del modelo
uniform float roughness_value : hint_range(0.0, 1.0) = 0.95;

varying vec3 v_pos;
varying vec3 v_nrm;

void vertex() {
	// EN COORDENADAS DEL MODELO, no del mundo: asi la mancha viaja con el cuerpo en vez de que el
	// cuerpo pase por delante de una mancha clavada en el aire.
	v_pos = VERTEX;
	v_nrm = NORMAL;
}

void fragment() {
	ALBEDO = albedo.rgb * COLOR.rgb;
	ROUGHNESS = roughness_value;

	if (dissolve_amount <= 0.001) {
		ALPHA = 1.0;
	} else {
		// TRIPLANAR: la misma textura leida por los tres lados y mezclada segun hacia donde mira la
		// cara. Es la forma de vestir una malla sin UV sin que se vea estirada por ningun lado.
		vec3 an = abs(v_nrm);
		an /= max(an.x + an.y + an.z, 0.0001);
		vec3 uvw = v_pos / escala;
		float muestra = texture(dissolve_texture, uvw.zy).r * an.x
			+ texture(dissolve_texture, uvw.xz).r * an.y
			+ texture(dissolve_texture, uvw.xy).r * an.z;

		// --- el nucleo del original ---
		float emission_value = 1.0 - smoothstep(dissolve_amount, dissolve_amount + burn_size, muestra);
		EMISSION = vec3(emission_value * emission_amount * emission_color.rgb);
		ALPHA = smoothstep(dissolve_amount - burn_size, dissolve_amount, muestra);
	}
}
