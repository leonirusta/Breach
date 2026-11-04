// EL MURO DE LA ZONA del battle royale (zona_br.gd): un cilindro enorme, abierto, que marca el borde de la
// zona segura. Azul electrico y translucido, con franjas que suben despacio y una rejilla cuadrada suave,
// mas opaco abajo (donde se pisa) y deshaciendose hacia el cielo. Sin luz ni sombras: no cuesta mas que una
// capa de transparencia, y cuando estas pegado a el ocupa media pantalla, asi que no puede costar mas.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;   // sin niebla: se tiene que ver de lejos

uniform vec4 color : source_color = vec4(0.25, 0.45, 1.0, 1.0);
uniform float alto = 250.0;       // m del cilindro (para que las franjas no se estiren con la escala)
uniform float radio = 200.0;      // m del radio actual (idem)
uniform float intensidad = 1.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;           // cilindro de radio 1 y alto 1 centrado: y en -0.5..0.5
}

void fragment() {
	float y_m = (local_pos.y + 0.5) * alto;          // metros desde abajo
	float ang = atan(local_pos.z, local_pos.x);      // -PI..PI
	float arco_m = ang * radio;                      // metros a lo largo del muro
	// franjas que suben
	float franja = 0.5 + 0.5 * sin(y_m * 0.35 - TIME * 2.2 + sin(arco_m * 0.05) * 1.5);
	// rejilla: lineas finas cada 6 m en horizontal y en altura
	vec2 g = abs(fract(vec2(arco_m, y_m) / 6.0) - 0.5);
	float rejilla = smoothstep(0.47, 0.5, max(g.x, g.y));
	// de abajo arriba se desvanece
	float alto_k = 1.0 - smoothstep(10.0, alto * 0.75, y_m);
	// mas fuerte (2026-10-22, pedido: "es tan transparente que cuesta verla"; era 0,16 + 0,22 + 0,35 y 0,35 arriba)
	float a = (0.34 + 0.26 * franja + 0.4 * rejilla) * (0.55 + 0.45 * alto_k) * intensidad;
	ALBEDO = color.rgb * (1.0 + 0.6 * rejilla + 0.3 * franja);
	ALPHA = clamp(a, 0.0, 0.9);
}
