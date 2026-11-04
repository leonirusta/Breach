// LA PANTALLA DE LAS TELES DE LA CASA (prop hunt, 2026-10-21; scripts/ph_tele.gd).
// Encendida: la imagen (foto, fotograma o video) o, si no hay, un PROGRAMA de dibujos hecho aqui; con lineas de
// barrido y un poco de curva. Apagada: vidrio negro con brillo. ROTA (0..1, sube con los golpes): grietas que salen
// del golpe, pixeles muertos de colores que parpadean y una mancha negra; rota del todo y apagada, negro con la grieta.
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

uniform sampler2D imagen : source_color, filter_linear, hint_default_black;
uniform float con_imagen = 0.0;
uniform float encendida = 1.0;
uniform float rota = 0.0;
uniform vec2 golpe = vec2(0.5, 0.5);
uniform float brillo = 1.6;
uniform float canal = 0.0;      // cambia el programa de fabrica (cada tele el suyo)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// un programa de dibujos: cielo, sol, colinas que pasan y una pelota que rebota; el logo del canal en la esquina
vec3 programa(vec2 uv, float t) {
	vec3 cielo = mix(vec3(0.35, 0.65, 1.0), vec3(0.85, 0.95, 1.0), uv.y);
	vec3 col = cielo;
	vec2 sol = vec2(0.78 + 0.05 * sin(t * 0.3 + canal), 0.78);
	float ds = length((uv - sol) * vec2(1.78, 1.0));
	col = mix(col, vec3(1.0, 0.86, 0.3), smoothstep(0.11, 0.1, ds));
	float h1 = 0.32 + 0.06 * sin(uv.x * 9.0 + t * 0.8 + canal);
	float h2 = 0.22 + 0.05 * sin(uv.x * 14.0 - t * 1.3);
	if (uv.y < h1) col = vec3(0.30, 0.68, 0.30);
	if (uv.y < h2) col = vec3(0.20, 0.52, 0.22);
	float bx = fract(t * 0.18 + canal * 0.3);
	float by = 0.22 + abs(sin(t * 3.0)) * 0.4;
	float db = length((uv - vec2(bx, by)) * vec2(1.78, 1.0));
	col = mix(col, vec3(0.95, 0.25, 0.2), smoothstep(0.065, 0.055, db));
	col = mix(col, vec3(1.0), smoothstep(0.02, 0.012, length((uv - vec2(bx - 0.012, by + 0.02)) * vec2(1.78, 1.0))));
	// el logo: un cuadrado blanco con borde
	vec2 l = uv - vec2(0.06, 0.86);
	if (l.x > 0.0 && l.x < 0.08 && l.y > 0.0 && l.y < 0.08) col = mix(col, vec3(1.0), 0.7);
	return col;
}

void fragment() {
	vec2 uv = UV;
	uv.y = 1.0 - uv.y;
	vec3 col = con_imagen > 0.5 ? texture(imagen, UV).rgb : programa(uv, TIME);
	// la televisión de verdad: barrido, un poco de viñeta y de brillo de fosforo
	col *= 0.93 + 0.07 * sin(UV.y * 700.0);
	vec2 cc = UV - 0.5;
	col *= 1.0 - dot(cc, cc) * 0.6;
	float roto_neg = 0.0;
	float grieta = 0.0;
	if (rota > 0.0) {
		vec2 d = (UV - golpe) * vec2(1.78, 1.0);
		float r = length(d);
		float ang = atan(d.y, d.x);
		// las grietas: rayos finos desde el golpe, cada vez mas largos
		float sector = floor(ang * 2.5 + 8.0);
		float desvio = (hash(vec2(sector, 3.0)) - 0.5) * 0.6;
		float rayo = abs(fract((ang + desvio * r) * 1.27) - 0.5);
		grieta = smoothstep(0.03, 0.0, rayo * r * 6.0) * step(r, 0.12 + rota * 1.1) * step(0.012, r);
		// la mancha negra del impacto y los pixeles muertos
		roto_neg = smoothstep(0.05 + rota * 0.12, 0.0, r);
		vec2 celda = floor(UV * vec2(120.0, 68.0));
		float muerto = step(1.0 - rota * 0.45 * smoothstep(0.9, 0.0, r), hash(celda));
		vec3 loco = vec3(hash(celda + 1.0), hash(celda + 7.0), hash(celda + 13.0));
		float parpadeo = step(0.5, fract(TIME * (3.0 + hash(celda) * 9.0)));
		col = mix(col, loco * parpadeo, muerto);
		// el color se corre en bandas
		col.r = mix(col.r, col.g, rota * 0.3 * step(0.5, fract(UV.y * 30.0 + TIME * 4.0)));
	}
	vec3 encendido = col * brillo * encendida * (1.0 - roto_neg);
	ALBEDO = vec3(0.012);
	ROUGHNESS = mix(0.12, 0.5, rota);
	METALLIC = 0.0;
	SPECULAR = 0.6;
	EMISSION = encendido + vec3(0.55) * grieta * (0.5 + 0.5 * encendida);
}
