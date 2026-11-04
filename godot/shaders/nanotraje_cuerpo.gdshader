// EL BRILLO DEL NANOTRAJE SOBRE EL MUÑECO (2026-10-03): una pasada de mas (material_overlay, avatar_animator.set_blindaje
// / traje_barrido) que suma luz, sin tapar el muñeco. Lo ven todos.
//   fuerza   el BLINDAJE puesto: hexagonos que laten y el filo (fresnel) azul acero
//   barrido  0..1: una franja de luz que sube de los pies a la cabeza (encender el blindaje, la invisibilidad, el salto)
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(0.55, 0.76, 1.0, 1.0);
uniform float fuerza = 0.0;
uniform float barrido = -1.0;
uniform float base_y = 0.0;
uniform float alto = 1.8;

varying vec3 wpos;

const vec2 HEX_S = vec2(1.0, 1.7320508);

float hexdist(vec2 p) {
	p = abs(p);
	return max(dot(p, HEX_S * 0.5), p.x);
}

vec4 hexcoords(vec2 uv) {
	vec4 hc = floor(vec4(uv, uv - vec2(0.5, 1.0)) / HEX_S.xyxy) + 0.5;
	vec4 h = vec4(uv - hc.xy * HEX_S, uv - (hc.zw + 0.5) * HEX_S);
	return dot(h.xy, h.xy) < dot(h.zw, h.zw) ? vec4(h.xy, hc.xy) : vec4(h.zw, hc.zw + 0.5);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	vec4 h = hexcoords(vec2(wpos.x + wpos.z, wpos.y) * 16.0);
	float linea = 1.0 - smoothstep(0.0, 0.06, 0.5 - hexdist(h.xy));
	float rnd = fract(sin(dot(h.zw, vec2(127.1, 311.7))) * 43758.5453);
	float late = 0.5 + 0.5 * sin(TIME * 2.4 + rnd * 6.2831);
	float y = (wpos.y - base_y) / alto;
	float franja = barrido >= 0.0 ? exp(-pow((y - barrido * 1.15 + 0.05) * 9.0, 2.0)) : 0.0;
	// mas intenso (2026-10-03, pedido: "la estela azul celeste, con mas contraste"): el filo, los hexagonos y la franja
	float a = fuerza * (0.6 * fres + 0.38 * linea * late + 0.1) + franja * (0.85 + 1.2 * linea + 0.5 * fres);
	ALBEDO = color.rgb * a;
}
