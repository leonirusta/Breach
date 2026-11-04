// LA LENTE Y EL SENSOR. Todo lo que le pasa a la imagen entre el mundo y la pantalla:
// curvatura de gran angular, separacion de color en el borde, obturador de barrido, grano, nitidez
// de camara barata, grado de color y vineta.
//
// TODO EN UNA SOLA PASADA, y eso es lo importante. Cada shader de pantalla cuesta una copia de la
// pantalla entera mas otra pasada a pantalla completa; en una integrada es de lo mas caro que hay.
// Los siete efectos parten del MISMO pixel y de la MISMA distancia al centro, asi que se hacen aqui
// de una vez. Como capas separadas costarian siete veces y se verian igual.
//
// EL NUCLEO DE LA CURVATURA NO ES MIO: es "2D Radial Distortion - Fisheye/Barrel" de Godot Shaders,
// licencia CC0. https://godotshaders.com/shader/2d-radial-distortion-fisheye-barrel/
// (que a su vez viene de un gist de aggregate1166877, citado en el original). De ahi sale lo que de
// verdad hace el efecto: convertir la distancia al centro en un ANGULO -`atan(d, sqrt(1 - d*d))`- y
// volver a pasarlo a distancia. Eso agranda el centro y mete los bordes hacia dentro.
//
// Lo demas esta reescrito. El motivo: el original mide la distancia en un cuadrado de -1 a 1, pero
// una pantalla 16:9 llega a 2,04 en las esquinas, muy fuera del rango donde su formula tiene
// sentido. Alli se satura y la esquina acaba enseniando lo que habia en mitad de la pantalla.
//
// El arreglo es normalizar la distancia hasta la ESQUINA, y escalar la curva para que alli no mueva
// nada. Eso deja los bordes comiendose unos pixeles -la imagen se sale un poco- y es a proposito:
// se probo la alternativa de clavar el borde entero, que no deja escapar ni un pixel, y la curva que
// queda dentro sale mucho mas cerrada. Se ve como un globo, no como una lente. Entre perder unos
// pixeles del filo y que la imagen entera parezca deformada, se pierden los pixeles.
//
// Tambien se anadio `fuerza` (el original solo sabe hacerlo entero, y entero marea) y se porto a
// Godot 4.
shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;
uniform float aspect = 1.7777;
uniform float distortion : hint_range(0.05, 1.0) = 1.0;
uniform float fuerza : hint_range(0.0, 1.0) = 0.10;      // la curvatura
uniform float aberra : hint_range(0.0, 1.0) = 0.0;       // separacion de color en el borde
uniform float grano : hint_range(0.0, 1.0) = 0.0;        // ruido de sensor
uniform float vineta : hint_range(0.0, 1.0) = 0.0;       // esquinas apagadas
uniform float obturador : hint_range(-1.0, 1.0) = 0.0;   // barrido: cizalla al girar
uniform float desatura : hint_range(0.0, 1.0) = 0.0;     // color lavado
uniform float negros : hint_range(0.0, 0.5) = 0.0;       // negros levantados y sucios
uniform float nitidez : hint_range(0.0, 2.0) = 0.0;      // realce de camara barata
// AFINADO DEL ANCLAJE. Corre el punto donde la curva no mueve nada: mas alto, mas plana queda la
// curva y mas se sale la imagen por los bordes; a 0 el anclaje es la esquina exacta.
uniform float margen : hint_range(0.0, 0.5) = 0.0;

void fragment() {
	if (fuerza <= 0.001 && aberra <= 0.001 && grano <= 0.001 && vineta <= 0.001
			&& abs(obturador) <= 0.0005 && desatura <= 0.001 && negros <= 0.001 && nitidez <= 0.001) {
		COLOR = texture(SCREEN_TEXTURE, SCREEN_UV);
	} else {
		vec2 xy = SCREEN_UV - 0.5;
		// la curva tiene que ser redonda EN PANTALLA, no en coordenadas de textura: sin esto, en una
		// pantalla ancha sale ovalada y se nota mas arriba y abajo que a los lados
		vec2 p = vec2(xy.x * aspect, xy.y);
		// LA DISTANCIA, MEDIDA HASTA LA ESQUINA. Se probo medirla hasta el borde que le toca a cada
		// pixel, que tiene la ventaja de que asi no se sale NADA de la pantalla nunca. Pero la curva
		// que queda dentro es mucho mas cerrada -el centro se hincha respecto al borde- y se ve
		// deformada, como un globo. Midiendo hasta la esquina la curva es mas plana y parece una
		// lente de verdad; el precio es que los bordes se comen unos pixeles, y ese precio se paga
		// con gusto porque lo otro se notaba mucho mas.
		float dmax = 0.5 * sqrt(aspect * aspect + 1.0);
		float d = length(p) / (dmax * (1.0 + margen));    // 0 en el centro, 1 en la esquina

		float k = 1.0;
		if (fuerza > 0.001) {
			// EL NUCLEO DEL ORIGINAL: la distancia, pasada por un angulo.
			float z = sqrt(max(distortion - d * d * distortion, 0.0001));
			float r = atan(d, z) / PI;                    // 0 en el centro, 0,5 en el borde
			// escalado para que el borde no se mueva: ahi r vale 0,5 y esto sale 1 exacto
			float curva = (d > 0.0005) ? (r * 2.0) / d : (2.0 / PI);
			k = mix(1.0, curva, fuerza);
		}

		// OBTURADOR DE BARRIDO. Un sensor barato no hace la foto de golpe: la lee linea a linea de
		// arriba abajo. Si giras mientras tanto, cada linea pilla la escena en un sitio distinto y la
		// imagen sale inclinada. Es por lo que un video de movil grabando desde un coche sale con los
		// postes torcidos. Aqui se imita corriendo cada fila un poco segun lo rapido que estes
		// girando: es una cizalla, y sale gratis porque solo mueve la coordenada de lectura.
		vec2 base = xy * k;
		base.x += obturador * (SCREEN_UV.y - 0.5);

		vec3 col;
		if (aberra > 0.001) {
			// LA SEPARACION DE COLOR crece con el CUADRADO de la distancia, no con la distancia: una
			// lente de verdad tiene el centro limpio y se descompone solo hacia fuera. Lineal deja el
			// centro sucio y se ve como un filtro puesto encima, no como un cristal.
			float sep = aberra * 0.0060 * d * d;
			col.r = texture(SCREEN_TEXTURE, clamp(0.5 + base * (1.0 + sep), 0.0, 1.0)).r;
			col.g = texture(SCREEN_TEXTURE, clamp(0.5 + base, 0.0, 1.0)).g;
			col.b = texture(SCREEN_TEXTURE, clamp(0.5 + base * (1.0 - sep), 0.0, 1.0)).b;
		} else {
			col = texture(SCREEN_TEXTURE, clamp(0.5 + base, 0.0, 1.0)).rgb;
		}

		if (nitidez > 0.001) {
			// REALCE. Las camaras baratas afilan la imagen por dentro para disimular lo blanda que
			// sale, y se les va la mano: quedan halos finos en los contornos. Eso, que en una foto es
			// un defecto, es justo lo que hace que algo se lea como "grabado con una camara" y no
			// como renderizado limpio.
			vec2 e = SCREEN_PIXEL_SIZE;
			vec3 blando = texture(SCREEN_TEXTURE, clamp(0.5 + base + vec2(e.x, 0.0), 0.0, 1.0)).rgb
				+ texture(SCREEN_TEXTURE, clamp(0.5 + base - vec2(e.x, 0.0), 0.0, 1.0)).rgb
				+ texture(SCREEN_TEXTURE, clamp(0.5 + base + vec2(0.0, e.y), 0.0, 1.0)).rgb
				+ texture(SCREEN_TEXTURE, clamp(0.5 + base - vec2(0.0, e.y), 0.0, 1.0)).rgb;
			col += (col - blando * 0.25) * nitidez;
		}

		if (desatura > 0.001 || negros > 0.001) {
			// EL GRADO. Menos color y los negros levantados y grises: una camara de cuerpo no tiene
			// rango para sacar la sombra limpia, asi que lo oscuro le queda lavado y sucio. Es de las
			// cosas que mas separan "video" de "videojuego", donde los negros son negros de verdad.
			float luz = dot(col, vec3(0.299, 0.587, 0.114));
			col = mix(col, vec3(luz), desatura);
			col = mix(col, vec3(0.055, 0.058, 0.070) + col * 0.92, negros * 2.0);
		}

		if (vineta > 0.001) {
			// esquinas apagadas: la lente deja pasar menos luz por el borde. Con la curvatura puesta
			// es lo que remata la sensacion de estar mirando POR una lente y no a una pantalla.
			//
			// MAS OSCURA. Antes empezaba a caer a 0,35 del centro y se comia como mucho el 85% de la
			// luz: quedaba un degradado suave que casi no se leia como vineta. Ahora arranca mas
			// afuera (0,28), cierra antes (0,98) y llega a apagar el 98%, asi que las esquinas se van
			// de verdad a negro y el centro queda igual de limpio. El cuadrado de la caida le da el
			// borde duro de una lente pequena en vez de un degradado de fotografia.
			float v = smoothstep(0.28, 0.98, d);
			col *= 1.0 - vineta * v * v * 0.98;
		}

		if (grano > 0.001) {
			// EL GRANO, en pixeles de pantalla y no en UV: si va en UV, cambia de tamano con la
			// resolucion y en el movil se ve como manchurrones. `fract(TIME)` lo mueve cada cuadro,
			// que es lo que lo hace grano y no suciedad pegada.
			float g = fract(sin(dot(FRAGCOORD.xy + fract(TIME) * 311.7, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
			// y MAS en las sombras: un sensor tiene ruido donde le falta luz, no donde le sobra
			float luz2 = dot(col, vec3(0.299, 0.587, 0.114));
			col += g * grano * 0.055 * (1.0 - luz2 * 0.65);
		}
		COLOR = vec4(col, 1.0);
	}
}
