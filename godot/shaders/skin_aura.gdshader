shader_type spatial;
// EL EFECTO DE LAS SKINS CARAS. Va como SEGUNDA PASADA (next_pass) encima del material normal de la
// skin: no sustituye la pintura, le añade luz por encima. Así una legendaria se distingue de una común
// en movimiento, que es donde de verdad se nota que una skin es cara.
//
// Tres cosas, todas con el reloj del juego, ninguna con partículas (en un móvil, partículas por arma
// es justo lo que no se puede pagar):
//   1. BORDE ENCENDIDO (fresnel): el contorno del arma brilla. Es lo que hace que se recorte contra el
//      fondo y se lea de lejos.
//   2. LATIDO: todo el brillo sube y baja despacio, como si el arma tuviera algo dentro.
//   3. ENERGIA QUE CORRE: bandas finas que recorren el arma a lo largo. Se calculan con la posicion en
//      el MODELO, así que van con el arma aunque te muevas.
//
// Es aditivo y sin luces (`unshaded`): cuesta una pasada y no entra en el calculo de iluminacion.

render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform vec3 color_borde : source_color = vec3(1.0, 0.45, 0.1);
uniform vec3 color_flujo : source_color = vec3(1.0, 0.8, 0.3);
uniform float fuerza_borde = 1.0;       // 0 = sin contorno encendido
uniform float fuerza_flujo = 0.6;       // 0 = sin bandas corriendo
uniform float latido = 0.35;            // cuanto sube y baja el brillo (0 = fijo)
uniform float velocidad = 1.0;          // a que ritmo va todo
uniform float bandas = 14.0;            // cuantas bandas caben a lo largo del arma

varying vec3 pos_modelo;

void vertex() {
	pos_modelo = VERTEX;
}

void fragment() {
	// 1) el contorno: cuanto mas de canto se ve la superficie, mas brilla
	float borde = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);

	// 2) el latido, con dos senos de distinto ritmo para que no parezca un parpadeo de bombilla
	float t = TIME * velocidad;
	float pulso = 1.0 + latido * (sin(t * 2.1) * 0.6 + sin(t * 3.7) * 0.4);

	// 3) las bandas que recorren el arma a lo largo (eje Z del modelo: las armas apuntan a -Z)
	float onda = sin((pos_modelo.z * bandas) + t * 4.0);
	float flujo = smoothstep(0.82, 1.0, onda);

	vec3 luz = color_borde * borde * fuerza_borde + color_flujo * flujo * fuerza_flujo;
	ALBEDO = vec3(0.0);
	EMISSION = luz * pulso;
	ALPHA = 1.0;
}
