// ONDA EXPANSIVA: el aire doblandose al reventar algo.
//
// NO es mio: es "Distortion/Shockwave Shader" de Godot Shaders, licencia CC0 (dominio publico).
//   https://godotshaders.com/shader/distortion/
//
// Es un anillo: dentro y fuera no toca nada, y justo en el filo empuja la imagen hacia fuera y
// separa el rojo del azul. Animando el radio de 0 hacia arriba, el anillo se expande desde el
// punto del estallido, que es exactamente lo que hace una onda de choque.
//
// Lo unico anadido al original: `fuerza_total`, que apaga el efecto entero de una vez. Sin eso, con
// el radio en reposo el anillo se quedaba clavado en pantalla.
shader_type canvas_item;

uniform float strength : hint_range(0.0, 0.1, 0.001) = 0.08;
uniform vec2 center = vec2(0.5, 0.5);
uniform float radius : hint_range(0.0, 1.0, 0.001) = 0.25;
uniform float aberration : hint_range(0.0, 1.0, 0.001) = 0.425;
uniform float width : hint_range(0.0, 0.1, 0.0001) = 0.04;
uniform float feather : hint_range(0.0, 1.0, 0.001) = 0.135;
uniform float fuerza_total : hint_range(0.0, 1.0) = 0.0;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;   // (sin mipmaps: solo se lee el nivel 0; 2026-10-10)

void fragment() {
	if (fuerza_total <= 0.001) {
		COLOR = texture(SCREEN_TEXTURE, SCREEN_UV);
	} else {
		vec2 st = SCREEN_UV;
		float aspect_ratio = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
		vec2 scaled_st = (st - vec2(0.0, 0.5)) / vec2(1.0, aspect_ratio) + vec2(0.0, 0.5);
		vec2 dist_center = scaled_st - center;
		float mask = (1.0 - smoothstep(radius - feather, radius, length(dist_center)))
			* smoothstep(radius - width - feather, radius - width, length(dist_center));
		mask *= fuerza_total;
		vec2 offset = normalize(dist_center) * strength * mask;
		vec2 biased_st = scaled_st - offset;
		vec2 abber_vec = offset * aberration * mask;
		vec2 final_st = st * (1.0 - mask) + biased_st * mask;
		vec4 red = texture(SCREEN_TEXTURE, final_st + abber_vec);
		vec4 blue = texture(SCREEN_TEXTURE, final_st - abber_vec);
		vec4 ori = texture(SCREEN_TEXTURE, final_st);
		COLOR = vec4(red.r, ori.g, blue.b, 1.0);
	}
}
