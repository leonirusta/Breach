// LAS FAROLAS COCINADAS (2026-10-01, pedido: "cocina las luces de farolas y bombillas... es fija" y "que sea identico
// pero luz cocinada").
//
// Antes cada farol y cada bombilla era un OmniLight3D/SpotLight3D de Godot: cada pixel del mundo evaluaba los 3-4
// faroles que le llegaban (en la cafeteria, 74 faroles: ~2,6 ms de GPU de 14). Ahora las luces son FIJAS:
//   * LA LUZ LEJANA ESTA HORNEADA en un volumen de celdas de 1 m (CocinaLuces, en C++, al cargar el mapa): para cada
//     celda, la luz difusa que recibe una cara que mira a cada uno de los 6 ejes. Las caras de voxel miran siempre a un
//     eje, asi que para ellas es la misma luz, salvo la interpolacion entre celdas. Dos lecturas por pixel.
//   * JUNTO A CADA FAROL (a menos de lamp_r1 m) el brillo cambia demasiado deprisa para un volumen: esa parte se
//     calcula exacta aqui, con LA MISMA FORMULA que Godot (atenuacion de omni y de foco, difusa de Lambert y especular
//     GGX con Fresnel). El reparto entre las dos es suave (smoothstep(r0, r1, distancia)): no hay costura.
//   * MOJADO (lluvia) el reflejo de las farolas en los charcos importa y es de lejos: ahi se calcula TODO exacto,
//     farol a farol, como antes. Y el cristal, que es liso, tambien.
// Se suma por EMISSION, que es exactamente donde Godot suma la luz de cada farol (despues de la del sol). Las Light3D
// siguen existiendo para personajes, armas y objetos: el mundo esta en la capa 11 y ellas ya no la tocan.
//
// lamp_datos (RGBAF, N x 4): fila 0 = posicion, 1/alcance · 1 = color x energia, decaimiento · 2 = direccion del foco,
// cos del cono (-2 si es omni) · 3 = exponente del borde del cono, encendida (0/1), especular (light_specular x 2),
// radio de su parte cercana (la exacta; de ahi para fuera, el volumen; el reparto empieza al 24 % de ese radio).
// lamp_rejilla / lamp_cerca (RGBA8, (celdas_x * 4) x celdas_z): hasta 16 indices de farol por parcela (255 = no hay
// mas): todos los que la alcanzan / solo los que estan a menos de lamp_r1.
// lamp_vol_a (RGBE9995, 3D) = luz que llega a las caras +X +Y +Z; lamp_vol_b = -X -Y -Z; lamp_vol_c (RG8) = el croma
// (r, g; b = 1 - r - g). En coma flotante: la GPU interpola en lineal (con la raiz en 8 bits salia de menos).

uniform sampler2D lamp_datos : filter_nearest, repeat_disable;
uniform sampler2D lamp_rejilla : filter_nearest, repeat_disable;
uniform sampler2D lamp_cerca : filter_nearest, repeat_disable;
uniform sampler3D lamp_vol_a : filter_linear, repeat_disable;
uniform sampler3D lamp_vol_b : filter_linear, repeat_disable;
uniform sampler3D lamp_vol_c : filter_linear, repeat_disable;
// el especular de la luz lejana: xyz = suma de direcciones hacia los faroles pesadas por su luminancia, w = la suma
// (celdas del doble que las otras): una luz virtual de la direccion media
uniform sampler3D lamp_vol_d : filter_linear, repeat_disable;
uniform vec3 lamp_vol_tam_d = vec3(1.0);
uniform vec2 lamp_org = vec2(0.0);
uniform float lamp_celda = 4.0;
uniform ivec2 lamp_celdas = ivec2(0, 0);
uniform float lamp_celda_cerca = 1.0;      // la lista de la parte cercana va en parcelas mas finas
uniform ivec2 lamp_celdas_cerca = ivec2(0, 0);
uniform float lamp_on = 0.0;
uniform float lamp_fade_ini = 30.0;
uniform float lamp_fade_len = 18.0;
uniform float lamp_k = 1.0;
uniform float lamp_vol_on = 0.0;
uniform vec3 lamp_vol_org = vec3(0.0);
uniform vec3 lamp_vol_tam = vec3(1.0);     // tamaño del volumen en metros
uniform float lamp_vol_max = 1.0;
uniform float lamp_r0 = 0.6;
uniform float lamp_r1 = 2.5;
uniform float lamp_alcance_max = 1e6;      // el alcance del farol que mas llega (para el corte del camino exacto)
uniform int lamp_max = 16;          // (solo para medir: cuantos faroles como mucho por pixel)
uniform float lamp_con_esp = 1.0;   // (solo para medir: 0 = sin el especular)
uniform int lamp_dbg = 0;           // (solo para medir: 1 = sin la parte cercana, 2 = sin el volumen)

float lamp_aten(float d, float inv_r, float decay) {
	float nd = d * inv_r;
	nd *= nd;
	nd *= nd;
	nd = max(1.0 - nd, 0.0);
	nd *= nd;
	return nd * pow(max(d, 0.0001), -decay);
}

float lamp_d_ggx(float c, float a) {
	float aa = c * a;
	float k = a / (1.0 - c * c + aa * aa);
	return k * k * (1.0 / 3.14159265);
}

float lamp_v_ggx(float nl, float nv, float a) {
	return 0.5 / mix(2.0 * nl * nv, nl + nv, a);
}

// Los faroles de la lista de la parcela (`cerca`: solo la parte cercana, la que no esta en el volumen)
void lamp_lista(sampler2D rej, bool cerca, vec3 wp, vec3 n, vec3 v, float rough, vec3 f0, float f90, float nv,
		vec3 cam, inout vec3 dif, inout vec3 esp) {
	float tam_c = cerca ? lamp_celda_cerca : lamp_celda;
	ivec2 dims_c = cerca ? lamp_celdas_cerca : lamp_celdas;
	ivec2 c = ivec2(floor((wp.xz - lamp_org) / tam_c));
	if (c.x < 0 || c.y < 0 || c.x >= dims_c.x || c.y >= dims_c.y) {
		return;
	}
	float alfa = rough * rough;
	for (int t = 0; t < 4; t++) {
		vec4 idx4 = texelFetch(rej, ivec2(c.x * 4 + t, c.y), 0) * 255.0;
		for (int k = 0; k < 4; k++) {
			int i = int(idx4[k] + 0.5);
			if (i >= 255 || t * 4 + k >= lamp_max) {
				return;
			}
			vec4 d0 = texelFetch(lamp_datos, ivec2(i, 0), 0);
			vec3 rel = d0.xyz - wp;
			float dist = length(rel);
			if (dist * d0.w >= 1.0) {
				continue;
			}
			vec4 d3 = texelFetch(lamp_datos, ivec2(i, 3), 0);
			// el radio de la parte cercana de ESTE farol (fila 3, w): mas grande en los fuertes y de mucho alcance
			if (cerca && dist >= d3.w) {
				continue;
			}
			if (d3.y < 0.5) {
				continue;
			}
			// el desvanecido por distancia de la camara (Light3D.distance_fade), lineal como en Godot
			float dc = distance(cam, d0.xyz);
			float fade = 1.0 - clamp((dc - lamp_fade_ini) / max(lamp_fade_len, 0.001), 0.0, 1.0);
			if (fade <= 0.0) {
				continue;
			}
			vec4 d1 = texelFetch(lamp_datos, ivec2(i, 1), 0);
			vec4 d2 = texelFetch(lamp_datos, ivec2(i, 2), 0);
			vec3 l = rel / max(dist, 0.0001);
			float aten = lamp_aten(dist, d0.w, d1.w);
			if (d2.w > -1.5) {
				float scos = max(dot(-l, d2.xyz), d2.w);
				float rim = max(0.0001, (1.0 - scos) / (1.0 - d2.w));
				aten *= 1.0 - pow(rim, d3.x);
			}
			if (cerca) {
				aten *= 1.0 - smoothstep(d3.w * 0.24, d3.w, dist);
			}
			float nl = dot(n, l);
			if (nl <= 0.0 || aten <= 0.0) {
				continue;
			}
			vec3 col = d1.rgb * (aten * fade * lamp_k);
			dif += col * nl * (1.0 / 3.14159265);
			if (rough > 0.0 && lamp_con_esp > 0.5) {
				vec3 h = normalize(v + l);
				float lh = clamp(dot(l, h), 0.0, 1.0);
				float nh = clamp(dot(n, h), 0.0, 1.0);
				float m = 1.0 - lh;
				float m2 = m * m;
				vec3 fr = f0 + (f90 - f0) * (m2 * m2 * m);
				esp += col * (nl * lamp_d_ggx(nh, alfa) * lamp_v_ggx(nl, nv, alfa) * d3.z) * fr;
			}
		}
	}
}

// Suma en `dif` (sin multiplicar por el albedo) y `esp` la luz de los faroles que tocan `wp`. `exacto` > 0,5: todo
// farol a farol (mojado, cristal).
void lamparas(vec3 wp, vec3 n, vec3 v, float rough, float spec, float metal, vec3 albedo, vec3 cam, float exacto,
		inout vec3 dif, inout vec3 esp) {
	if (lamp_on < 0.5 || lamp_celdas.x <= 0) {
		return;
	}
	vec3 f0 = mix(vec3(0.16 * spec * spec), albedo, metal);
	float f90 = clamp(dot(f0, vec3(50.0 * 0.33)), metal, 1.0);
	float nv = max(dot(n, v), 1e-4);
	float dpx = distance(cam, wp);
	if (lamp_vol_on < 0.5 || exacto > 0.5) {
		// EL MISMO CORTE PARA EL CAMINO EXACTO (2026-10-05, banco de la lluvia: con lluvia TODO lo mojado va por aqui y
		// cada pixel recorria hasta 16 faroles de su parcela aunque estuvieran todos apagados por distancia: 1,1 ms de
		// GPU en la cafeteria). Un farol solo alumbra a menos de su alcance y se apaga a lamp_fade_ini + lamp_fade_len
		// de la camara: si el pixel esta mas lejos que eso mas el alcance mayor, ninguno llega. Misma imagen.
		if (dpx > lamp_fade_ini + lamp_fade_len + lamp_alcance_max) {
			return;
		}
		lamp_lista(lamp_rejilla, false, wp, n, v, rough, f0, f90, nv, cam, dif, esp);
		return;
	}
	// MAS ALLA DEL DESVANECIDO NO HAY NADA QUE HACER: los faroles se apagan a lamp_fade_ini + lamp_fade_len de la camara,
	// y los de la parte cercana estan a menos de lamp_r1 de este pixel (misma imagen, y el resto de la pantalla gratis)
	if (dpx > lamp_fade_ini + lamp_fade_len + lamp_r1) {
		return;
	}
	// la parte cercana, exacta
	if (lamp_dbg != 1) {
		lamp_lista(lamp_cerca, true, wp, n, v, rough, f0, f90, nv, cam, dif, esp);
	}
	if (lamp_dbg == 2) {
		return;
	}
	// y la lejana, del volumen (con el desvanecido por la distancia de este pixel a la camara)
	vec3 uvw = (wp - lamp_vol_org) / lamp_vol_tam;
	if (any(lessThan(uvw, vec3(0.0))) || any(greaterThan(uvw, vec3(1.0)))) {
		return;
	}
	float fade = 1.0 - clamp((dpx - lamp_fade_ini) / max(lamp_fade_len, 0.001), 0.0, 1.0);
	if (fade <= 0.0) {
		return;
	}
	vec3 a = textureLod(lamp_vol_a, uvw, 0.0).rgb;
	vec3 b = textureLod(lamp_vol_b, uvw, 0.0).rgb;
	vec2 ch = textureLod(lamp_vol_c, uvw, 0.0).rg;
	vec3 n2 = n * n;
	float lum = n2.x * (n.x > 0.0 ? a.x : b.x) + n2.y * (n.y > 0.0 ? a.y : b.y) + n2.z * (n.z > 0.0 ? a.z : b.z);
	vec3 croma = vec3(ch.x, ch.y, max(1.0 - ch.x - ch.y, 0.0));
	float lc = max(dot(croma, vec3(0.2126, 0.7152, 0.0722)), 0.001);
	dif += croma * (lum / lc * fade);
	// EL BRILLO DEL ESPECULAR de esa luz lejana (mirando hacia una farola a lo largo del suelo es tanto como la difusa).
	// Solo donde se ve: mirando de lado (rasante) o en algo liso. En lo seco y rugoso mirado de frente es el 1-3 % de la
	// difusa (f0 = 0,01) y no se nota.
	if (rough > 0.0 && lamp_con_esp > 0.5 && (nv < 0.5 || rough < 0.8)) {
		vec4 sd = textureLod(lamp_vol_d, (wp - lamp_vol_org) / lamp_vol_tam_d, 0.0);
		float largo = length(sd.xyz);
		if (sd.w > 1e-6 && largo > 1e-6) {
			vec3 l = sd.xyz / largo;
			float nl = dot(n, l);
			if (nl > 0.0) {
				vec3 h = normalize(v + l);
				float lh = clamp(dot(l, h), 0.0, 1.0);
				float nh = clamp(dot(n, h), 0.0, 1.0);
				float m = 1.0 - lh;
				float m2 = m * m;
				vec3 fr = f0 + (f90 - f0) * (m2 * m2 * m);
				float alfa = rough * rough;
				// (sd.w lleva el 1/pi de la difusa de Lambert; el especular no: x pi)
				esp += croma * (sd.w * 3.14159265 / lc * fade * nl * lamp_d_ggx(nh, alfa) * lamp_v_ggx(nl, nv, alfa)) * fr;
			}
		}
	}
}
