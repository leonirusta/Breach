// AGUA EN LA LENTE, LIGERA (2026-10-13, pedido: "las gotas en la lente las quiero, pero que no copie la pantalla cada
// fotograma"): las mismas gotas que lluvia_lente.gdshader, pero SIN LEER LA PANTALLA. No hay copia de la pantalla (su
// BackBufferCopy) ni refraccion: cada gota se pinta encima con su brillo (la luz por arriba a la izquierda), su borde algo
// mas oscuro y el cristal frio y con las esquinas apagadas, en alfa premultiplicado. Es la del movil (hud.gd).
shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

// SIN DESENFOQUE (2026-10-05, banco de la lluvia): el original leia `textureLod(pantalla, uv, focus)` para emborronar el
// cristal mojado, pero la copia de pantalla de la lente (su BackBufferCopy) NUNCA tuvo mipmaps: la tarjeta leia siempre el
// nivel 0 y en el juego el fondo salia NITIDO (foto contra foto en la cafeteria: --lluvialente y --lluvialente --lentemips).
// Asi que se lee la pantalla UNA vez, sin `focus`: la misma imagen que se ha visto siempre. Se probo emborronar de verdad
// (12 muestras en disco) y cambiaba el aspecto (todo borroso) y costaba mas. El de antes queda en lluvia_lente_mips.gdshader.
uniform float cantidad : hint_range(0.0, 1.0) = 0.0;   // cuanta agua hay ahora mismo
uniform float azul : hint_range(0.0, 1.0) = 0.6;       // cuanto tira a frio el cristal mojado
uniform float fuerza : hint_range(0.0, 4.0) = 1.0;     // cuanto dobla la imagen
uniform float velocidad : hint_range(0.05, 1.0) = 0.2;
uniform float desenfoque : hint_range(0.0, 8.0) = 4.0; // borroso maximo dentro del agua
// CUANTAS CAPAS DE GOTAS QUE CAEN (1 o 2). En movil, una.
uniform int capas : hint_range(1, 2) = 2;
// SOLO DIAGNOSTICO (banco de la lluvia, 2026-10-05): 1 = sin calcular las gotas (para medir la copia de pantalla sola)
uniform int diag_sin_gotas = 0;

vec3 N13(float p) {
	vec3 p3 = fract(vec3(p) * vec3(.1031, .11369, .13787));
	p3 += dot(p3, p3.yzx + 19.19);
	return fract(vec3((p3.x + p3.y) * p3.z, (p3.x + p3.z) * p3.y, (p3.y + p3.z) * p3.x));
}

float N(float t) {
	return fract(sin(t * 12345.564) * 7658.76);
}

float Saw(float b, float t) {
	return smoothstep(0.0, b, t) * smoothstep(1.0, b, t);
}

// La gota, como campo de distancia con forma de huevo: ancha abajo y afilada arriba, que es como
// se deforma una gota al resbalar.
float sdEgg(vec2 p, float ra, float rb) {
	const float k = sqrt(3.0);
	p.x = abs(p.x);
	float r = ra - rb;
	return ((p.y < 0.0) ? length(vec2(p.x, p.y)) - r
		: (k * (p.x + r) < p.y) ? length(vec2(p.x, p.y - k * r))
		: length(vec2(p.x + r, p.y)) - 2.0 * r) - rb;
}

// Una capa de gotas que caen. Devuelve (cuerpo de la gota, reguero).
vec2 DropLayer2(vec2 uv, float t) {
	vec2 a = vec2(6.0, 1.0);
	vec2 grid = a * 2.0;
	vec2 id = floor(uv * grid);
	float gridFall = N(id.x) / 3.0 + 0.5;
	uv.y -= t * gridFall / a.y;
	id = floor(uv * grid);
	uv.y += N(id.x);
	id = floor(uv * grid);
	vec2 st = fract(uv * grid) - vec2(0.5, 0.0);
	vec3 n = N13(id.x * 35.2 + id.y * 2376.1);
	float x = n.x - 0.5;
	x += sin(uv.y * 20.0 + sin(uv.y * 20.0)) * (0.5 - abs(x)) * (n.z - 0.5) * 0.3;
	x *= 0.6;
	float ti = fract(t * (gridFall + 0.1) + n.z);
	float y = 1.0 - ti;
	float dropShape = mix(0.0, -0.2, ti);
	float d = sdEgg((st - vec2(x, y)) * a.yx, 0.0, dropShape);
	float diameter = N(id.x + id.y) / 7.0 + 0.2;
	float mainDrop = smoothstep(diameter / 1.5, 0.0, d);
	float r2 = smoothstep(1.0, y, st.y);
	float trail = smoothstep(diameter * 0.75 * sqrt(r2), 0.0, abs(st.x - x));
	trail *= r2 * smoothstep(-0.05, 0.05, st.y - y) * 0.5;
	return vec2(mainDrop, trail);
}

// Las gotitas quietas que salpican el cristal y se van secando.
float StaticDrops(vec2 uv, float t) {
	uv *= 40.0;
	vec2 id = floor(uv);
	vec3 n = N13(id.x * 106.45 + id.y * 3543.654);
	vec2 center = (n.xy - 0.5) * 0.6;
	uv = fract(uv) - 0.5;
	float d = length(uv - center.xy);
	float drop = smoothstep(0.3, 0.0, d);
	float fade = Saw(0.10, fract(t + n.y));
	return drop * fade * fract(n.z * 27.0);
}

vec2 Drops(vec2 uv, float t, float l0, float l1, float l2) {
	float s = StaticDrops(uv, t) * l0;
	vec2 m1 = DropLayer2(uv, t) * l1;
	// LA SEGUNDA CAPA ES OPCIONAL. Es la mitad del coste del shader y en un movil se nota: con una
	// sola capa sigue habiendo gotas y regueros, solo que menos apretados.
	vec2 m2 = capas > 1 ? DropLayer2(uv * 1.85, t) * l2 : vec2(0.0);
	float c = smoothstep(0.3, 1.0, s + m1.x + m2.x);
	return vec2(c, m1.y + m2.y);
}

// EL RECORTE DEL ESCUDO (2026-10-28): con el escudo blindado en primera persona las gotas solo van en su cristal, que en
// pantalla es este cuadrilatero (q0..q3 en SCREEN_UV, lo pone hud.lente_recorte); fuera, seco.
uniform int con_recorte = 0;
uniform vec2 q0; uniform vec2 q1; uniform vec2 q2; uniform vec2 q3;
float _lado(vec2 a, vec2 b, vec2 p) { return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x); }
bool _en_recorte(vec2 p) {
	if (con_recorte == 0) return true;
	float d0 = _lado(q0, q1, p), d1 = _lado(q1, q2, p), d2 = _lado(q2, q3, p), d3 = _lado(q3, q0, p);
	return (d0 >= 0.0 && d1 >= 0.0 && d2 >= 0.0 && d3 >= 0.0) || (d0 <= 0.0 && d1 <= 0.0 && d2 <= 0.0 && d3 <= 0.0);
}

void fragment() {
	if (cantidad <= 0.002) {
		COLOR = vec4(0.0);
	} else {
		vec2 resolution = 1.0 / SCREEN_PIXEL_SIZE;
		vec2 aspect_uv = (FRAGCOORD.xy - 0.5 * resolution.xy) / resolution.y;
		float t = TIME * velocidad;
		float staticDrops = smoothstep(-0.5, 1.0, cantidad) * 2.0;
		float layer1 = smoothstep(0.25, 0.75, cantidad);
		float layer2 = smoothstep(0.0, 0.5, cantidad);
		vec2 c = diag_sin_gotas == 1 ? vec2(0.0) : Drops(aspect_uv, t, staticDrops, layer1, layer2);
		vec2 n = vec2(dFdx(c.x), dFdy(c.x)) * fuerza * 0.5;
		// el brillo de la gota (la luz entra por arriba a la izquierda) y su borde, que oscurece un poco
		float brillo = clamp(dot(n, vec2(-1.0, -1.0)) * 40.0, 0.0, 1.0) * 0.55;
		float borde = clamp(length(n) * 30.0, 0.0, 1.0) * 0.22;
		// el cristal frio y las esquinas apagadas, como en la de verdad
		vec2 vi = SCREEN_UV - 0.5;
		float oscuro = dot(vi, vi) * cantidad * 0.8 + borde;
		vec3 frio = vec3(0.10, 0.14, 0.22) * azul * cantidad * 0.25;
		float a = clamp(oscuro + brillo * 0.6, 0.0, 0.9);
		COLOR = vec4(vec3(brillo) + frio, a);
		if (!_en_recorte(SCREEN_UV)) {
			COLOR = vec4(0.0);
		}
	}
}
