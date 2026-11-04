// LOS MUEBLES DE LA CASA (prop hunt, scripts/ph_muebles.gd): el color de cada caja va en el color de vertice.
// La luz de las lamparas de la casa va COCINADA en el mundo (lamparas.gdshaderinc, en la emision) y a los objetos no les
// llega: dentro de la casa salian casi negros. `rebote` es la luz que rebota en un cuarto iluminado (un poco del propio
// color como emision), y `rebote_sol` lo que queda al sol.
shader_type spatial;
render_mode cull_back;

uniform float rebote = 0.22;

// los colores de ph_muebles.gd son sRGB (Color.html) y el color de vertice llega tal cual: sin pasarlo a lineal salian
// desteñidos
vec3 a_lineal(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec3 c = a_lineal(COLOR.rgb);
	ALBEDO = c;
	ROUGHNESS = 0.78;
	EMISSION = c * rebote;
}
