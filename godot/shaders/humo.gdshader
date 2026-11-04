// HUMO VOLUMETRICO de las explosiones.
//
// NO es mio: es "Industrial Smoke" de Godot Shaders, licencia CC0 (dominio publico, sin
// restricciones). https://godotshaders.com/shader/industrial-smoke/
//
// Es de tipo `fog`, no un cartel: el humo OCUPA UN VOLUMEN y la niebla volumetrica de Godot lo
// atraviesa. Por eso se mete entre las ruinas y los edificios en vez de quedarse como una calcomania
// delante de todo, que es lo que se ve en cuanto te acercas a una nube plana.
//
// Un arreglo respecto al original: su `rot2d` tenia `cos(2)` donde queria decir `cos(a)`, o sea que
// la rotacion no rotaba (la primera columna de la matriz salia constante). Corregido.
// Y dos anadidos para poder usarlo en explosiones, que aparecen y se van:
//   `vida`  : de 1 (recien reventado) a 0 (disuelto), para que el humo se apague solo
//   `subida`: cuanto ha subido ya la nube
shader_type fog;

uniform sampler2D noise00;
uniform sampler2D noise01;
uniform float density_multiplicator = 3.0;
uniform vec3 base_color : source_color = vec3(0.20, 0.20, 0.20);
uniform vec3 fade_out_color : source_color = vec3(0.80, 0.80, 0.80);
uniform float fade_out_level = 0.5;
uniform float speed = 0.25;
uniform float vida : hint_range(0.0, 1.0) = 1.0;

mat2 rot2d(float a) {
	return mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a)));
}

void fog() {
	vec3 uvw = UVW;
	uvw.y -= fract(TIME * speed) - 0.5;

	float n00 = texture(noise00, rot2d(abs(sin(TIME * 0.2))) * UVW.xz).r;
	float n01 = texture(noise01, rot2d(abs(sin(TIME * 0.2))) * UVW.xz).r * 1.4;
	float d = step(0.4 * n01, uvw.y) - step(0.50 * n01, uvw.y);

	d *= n00;
	d *= 3.0 * (1.0 - UVW.y);      // se deshilacha hacia arriba
	d *= density_multiplicator;
	// y se disuelve con el tiempo: una explosion no deja humo para siempre
	DENSITY = d * vida;

	// al enfriarse tira a gris claro; recien reventado, negro
	vec3 col = mix(base_color, fade_out_color, pow(fade_out_level, 1.0 / 2.2) * (1.0 - vida * 0.6));
	ALBEDO = col;
}
