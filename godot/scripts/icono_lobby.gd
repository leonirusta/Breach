extends Control
## ICONOS DEL LOBBY, DIBUJADOS A MANO. La fuente del juego no trae simbolos raros (el "☻" de la cuenta salia
## invisible), y una imagen por icono pixela en cuanto la pantalla es mas grande que la de diseno. Asi son
## lineas y poligonos: se ven nitidos a cualquier tamano y cambiar el color es cambiar una variable.
##
## Todo se dibuja en un cuadrado de 100x100 que se escala al tamano del control.
##   icono   tienda | misiones | equipo | mochila | salas | ajustes | moneda | credito | biohazard | bomba |
##           caja | mira | bandera | chat | jugar | rayo | usuario | amigos | candado | martillo | ticket |
##           cubo_fuerza | cofre
##           (cubo_fuerza lleva SUS colores, cian y violeta, y de `color` solo coge la transparencia; cofre usa `color`
##           para la madera: el color de la rareza)
##           LAS CARTAS (cartas.gd): carta_dano | carta_municion | carta_vida | carta_regeneracion | carta_velocidad |
##           carta_salto | carta_destruccion | carta_explosion | carta_especial | carta_todo: el HEXAGONO BRILLANTE del
##           color de la carta (`color`: canto, bisel y cara) con su dibujo en blanco. glifo_<lo mismo>: el dibujo solo,
##           en `color` (la columna de categorias, la esquina de las cartas; los huecos del dibujo van en `hueco`, si no es
##           transparente). copias: dos cartas una encima de otra (las copias de una carta).
##   hexagono  si el icono va dentro de un hexagono (los modos, como en los shooters de movil)
##   relleno   hexagono relleno (seleccionado) o solo el borde
##   hueco     el color de los huecos de los glifo_ (el del fondo donde van): sin el, el dibujo va macizo

var icono := "tienda":
	set(v):
		icono = v
		queue_redraw()
var color := Color.WHITE:
	set(v):
		color = v
		queue_redraw()
var hexagono := false:
	set(v):
		hexagono = v
		queue_redraw()
var relleno := false:
	set(v):
		relleno = v
		queue_redraw()
var color_hex := Color(1.0, 0.80, 0.0):
	set(v):
		color_hex = v
		queue_redraw()
var grosor := 7.0
var hueco := Color(0, 0, 0, 0):
	set(v):
		hueco = v
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	resized.connect(queue_redraw)


func _p(x: float, y: float) -> Vector2:
	var lado := minf(size.x, size.y)
	var o := (size - Vector2(lado, lado)) * 0.5
	return o + Vector2(x, y) * lado / 100.0


func _k() -> float:
	return minf(size.x, size.y) / 100.0


func _poli(pts: Array, c: Color) -> void:
	var arr := PackedVector2Array()
	for q in pts:
		arr.append(_p(q[0], q[1]))
	draw_colored_polygon(arr, c)


func _linea(pts: Array, c: Color, w: float = -1.0, cerrada: bool = false) -> void:
	var arr := PackedVector2Array()
	for q in pts:
		arr.append(_p(q[0], q[1]))
	if cerrada:
		arr.append(arr[0])
	draw_polyline(arr, c, (grosor if w < 0.0 else w) * _k(), true)


func _arco(cx: float, cy: float, r: float, a0: float, a1: float, c: Color, w: float = -1.0) -> void:
	draw_arc(_p(cx, cy), r * _k(), a0, a1, 32, c, (grosor if w < 0.0 else w) * _k(), true)


func _circulo(cx: float, cy: float, r: float, c: Color) -> void:
	draw_circle(_p(cx, cy), r * _k(), c)


func _hex(r: float) -> Array:
	var out := []
	for i in 6:
		var a := deg_to_rad(60.0 * i - 90.0)
		out.append([50.0 + r * cos(a), 50.0 + r * sin(a)])
	return out


func _draw() -> void:
	var c := color
	# LAS CARTAS: el hexagono brillante con el dibujo, o el dibujo solo
	if icono.begins_with("carta_"):
		_hex_carta(icono.substr(6))
		return
	if icono.begins_with("glifo_"):
		_pictograma(icono.substr(6), c, hueco)
		return
	if icono == "copias":
		_copias(c)
		return
	if hexagono:
		if relleno:
			_poli(_hex(49.0), color_hex)
			c = Color(0.06, 0.06, 0.07)
		else:
			_poli(_hex(47.0), Color(0.02, 0.025, 0.03, 0.72))
			_linea(_hex(46.0), color_hex, 4.0, true)
		# el icono, mas pequeno dentro del hexagono
		draw_set_transform(size * 0.5 * 0.42, 0.0, Vector2(0.58, 0.58))
	match icono:
		"tienda":
			_linea([[8, 20], [22, 20], [32, 64], [80, 64], [90, 32], [26, 32]], c)
			_circulo(38, 80, 7, c)
			_circulo(74, 80, 7, c)
		"misiones":
			_linea([[24, 14], [76, 14], [76, 90], [24, 90]], c, -1.0, true)
			_poli([[38, 6], [62, 6], [62, 22], [38, 22]], c)
			_linea([[34, 50], [46, 62], [68, 38]], c, 9.0)
		"equipo":
			_arco(50, 50, 32, 0.0, TAU, c)
			for d in [[50, 4, 50, 26], [50, 74, 50, 96], [4, 50, 26, 50], [74, 50, 96, 50]]:
				_linea([[d[0], d[1]], [d[2], d[3]]], c)
			_circulo(50, 50, 6, c)
		"mochila":
			_linea([[26, 30], [74, 30], [80, 90], [20, 90]], c, -1.0, true)
			_arco(50, 30, 16, PI, TAU, c)
			_linea([[34, 56], [66, 56], [66, 76], [34, 76]], c, 6.0, true)
		"salas":
			_circulo(50, 76, 7, c)
			_arco(50, 76, 22, deg_to_rad(-140), deg_to_rad(-40), c)
			_arco(50, 76, 40, deg_to_rad(-140), deg_to_rad(-40), c)
			_arco(50, 76, 58, deg_to_rad(-135), deg_to_rad(-45), c)
		"ajustes":
			for i in 8:
				var a := TAU * i / 8.0
				var d := Vector2(cos(a), sin(a))
				_poli([[50 + d.x * 30 - d.y * 8, 50 + d.y * 30 + d.x * 8], [50 + d.x * 44 - d.y * 7, 50 + d.y * 44 + d.x * 7],
					[50 + d.x * 44 + d.y * 7, 50 + d.y * 44 - d.x * 7], [50 + d.x * 30 + d.y * 8, 50 + d.y * 30 - d.x * 8]], c)
			_arco(50, 50, 26, 0.0, TAU, c, 12.0)
		"moneda":
			_poli(_hex(46.0), c)
			_poli(_hex(28.0), Color(0, 0, 0, 0.35))
			_poli([[50, 30], [66, 50], [50, 70], [34, 50]], c.lightened(0.35))
		"credito":
			_poli([[50, 6], [90, 40], [50, 94], [10, 40]], c)
			_linea([[10, 40], [90, 40]], Color(0, 0, 0, 0.35), 5.0)
			_linea([[30, 40], [50, 94], [70, 40]], Color(0, 0, 0, 0.25), 4.0)
		"paracaidas":
			# cupula, cuerdas y el que cuelga: el battle royale empieza saltando de un avion
			_arco(50, 46, 32, PI, TAU, c, 9.0)
			for k in [-1.0, -0.34, 0.34, 1.0]:
				_linea([[50 + k * 31, 47], [50 + k * 7, 70]], c, 4.0)
			_arco(50, 76, 7, 0.0, TAU, c, 6.0)
			_linea([[50, 82], [50, 92]], c, 5.0)
		"biohazard":
			for i in 3:
				var a := TAU * i / 3.0 - PI / 2.0
				var cx := 50.0 + cos(a) * 20.0
				var cy := 52.0 + sin(a) * 20.0
				_arco(cx, cy, 20, a + 0.9, a + TAU - 0.9, c, 9.0)
			_arco(50, 52, 13, 0.0, TAU, c, 7.0)
			_circulo(50, 52, 5, c)
		"bomba":
			_circulo(46, 58, 32, c)
			_linea([[64, 30], [78, 16]], c, 8.0)
			_poli([[80, 6], [88, 14], [84, 18], [94, 22], [84, 26], [80, 20]], Color(1.0, 0.55, 0.1))
			_circulo(36, 50, 7, Color(1, 1, 1, 0.45))
		"caja":
			_linea([[12, 18], [88, 18], [88, 86], [12, 86]], c, -1.0, true)
			_arco(50, 52, 20, 0.0, TAU, c)
			for i in 4:
				var a := TAU * i / 4.0 + PI / 4.0
				_linea([[50 + cos(a) * 6, 52 + sin(a) * 6], [50 + cos(a) * 18, 52 + sin(a) * 18]], c, 5.0)
			_poli([[80, 44], [88, 44], [88, 60], [80, 60]], c)
		"mira":
			_arco(50, 50, 38, 0.0, TAU, c)
			_arco(50, 50, 18, 0.0, TAU, c, 6.0)
			for d in [[50, 0, 50, 20], [50, 80, 50, 100], [0, 50, 20, 50], [80, 50, 100, 50]]:
				_linea([[d[0], d[1]], [d[2], d[3]]], c)
		"bandera":
			_linea([[22, 8], [22, 94]], c, 9.0)
			_poli([[26, 12], [84, 22], [66, 38], [84, 54], [26, 50]], c)
		"chat":
			_poli([[10, 16], [90, 16], [90, 70], [44, 70], [24, 88], [28, 70], [10, 70]], c)
			for x in [32, 50, 68]:
				_circulo(x, 43, 5, Color(0.05, 0.05, 0.06))
		"jugar":
			_poli([[26, 12], [86, 50], [26, 88]], c)
		"rayo":
			_poli([[58, 4], [18, 56], [46, 56], [38, 96], [82, 38], [54, 38]], c)
		"amigos":
			# dos personas: la de atras, a la derecha y mas tenue; la de delante, entera
			var c2 := Color(c, c.a * 0.55)
			_circulo(68, 30, 15, c2)
			_poli([[48, 88], [52, 64], [62, 56], [80, 56], [90, 64], [94, 88]], c2)
			_circulo(38, 36, 17, c)
			_poli([[6, 94], [10, 70], [24, 60], [52, 60], [66, 70], [70, 94]], c)
		"usuario":
			_circulo(50, 32, 20, c)
			_poli([[14, 94], [18, 66], [34, 56], [66, 56], [82, 66], [86, 94]], c)
		"candado":
			_arco(50, 42, 20, PI, TAU, c, 9.0)
			_linea([[30, 41], [30, 52]], c, 9.0)
			_linea([[70, 41], [70, 52]], c, 9.0)
			_poli([[16, 50], [84, 50], [84, 94], [16, 94]], c)
			_circulo(50, 68, 7, Color(0.05, 0.05, 0.06))
			_poli([[47, 70], [53, 70], [55, 84], [45, 84]], Color(0.05, 0.05, 0.06))
		"tactil":
			_linea([[28, 6], [72, 6], [72, 94], [28, 94]], c, 7.0, true)
			_circulo(50, 50, 10, c)
			_arco(50, 50, 21, 0.0, TAU, c, 5.0)
		"camara":
			_poli([[6, 30], [32, 30], [40, 16], [60, 16], [68, 30], [94, 30], [94, 86], [6, 86]], c)
			_circulo(50, 57, 21, Color(0.05, 0.05, 0.06))
			_circulo(50, 57, 13, c)
		"salir":
			_linea([[58, 12], [16, 12], [16, 88], [58, 88]], c)
			_linea([[38, 50], [80, 50]], c)
			_poli([[96, 50], [72, 30], [72, 70]], c)
		"martillo":
			# un mazo en diagonal: el mango de abajo a la izquierda y la cabeza atravesada arriba
			_linea([[14, 90], [60, 44]], c, 11.0)
			_poli([[55, 6], [94, 45], [74, 65], [35, 26]], c)
		# LAS HABILIDADES (habilidades.gd, 2026-09-28)
		"habilidades":
			# una estrella de energia de ocho puntas con dos chispas
			var pts: Array = []
			for i in 16:
				var a := -PI * 0.5 + i * TAU / 16.0
				var r := 44.0 if i % 4 == 0 else (30.0 if i % 2 == 0 else 15.0)
				pts.append([50.0 + cos(a) * r, 52.0 + sin(a) * r])
			_poli(pts, c)
			_circulo(84, 14, 6, c)
			_circulo(14, 86, 4, c)
		"invisible":
			# una persona a trazos: se le ve el contorno, a medias
			for i in 6:
				var a0 := i * TAU / 6.0
				_arco(50, 28, 16, a0, a0 + TAU / 12.0, c, 6.0)
			var cuerpo := [[16, 94], [20, 68], [36, 56], [64, 56], [80, 68], [84, 94]]
			for i in cuerpo.size() - 1:
				var p0: Array = cuerpo[i]
				var p1: Array = cuerpo[i + 1]
				_linea([p0, [lerpf(p0[0], p1[0], 0.55), lerpf(p0[1], p1[1], 0.55)]], c, 6.0)
			_linea([[4, 50], [16, 50]], Color(c, c.a * 0.5), 5.0)
			_linea([[84, 40], [96, 40]], Color(c, c.a * 0.5), 5.0)
		"puno":
			# un puño de frente, con los nudillos y el pulgar cruzado, y las rayas de velocidad
			_poli([[34, 26], [88, 26], [92, 34], [92, 74], [80, 86], [40, 86], [34, 78]], c)
			var hueco := Color(0.05, 0.05, 0.06)
			for x in [48, 62, 76]:
				_linea([[x, 28], [x, 46]], hueco, 4.0)
			_linea([[38, 58], [74, 58], [80, 66]], hueco, 4.5)
			_linea([[4, 36], [24, 36]], c, 6.0)
			_linea([[10, 52], [26, 52]], c, 6.0)
			_linea([[4, 68], [24, 68]], c, 6.0)
		"salto":
			# el arco del salto y el golpe al caer: el suelo y las rayas que salen del impacto
			_arco(46, 70, 36, PI * 1.05, PI * 1.85, c, 7.0)
			_poli([[70, 38], [84, 52], [68, 56]], c)
			_linea([[8, 92], [92, 92]], c, 6.0)
			_linea([[76, 80], [66, 66]], c, 5.0)
			_linea([[82, 76], [82, 60]], c, 5.0)
			_linea([[88, 80], [98, 66]], c, 5.0)
		"gancho":
			# un garfio de tres puntas colgando de su cuerda
			_linea([[50, 4], [50, 58]], Color(c, c.a * 0.6), 5.0)
			_linea([[50, 30], [50, 74]], c, 9.0)
			_arco(50, 60, 26, PI * 0.15, PI * 0.85, c, 8.0)
			_poli([[70, 72], [84, 60], [78, 78]], c)
			_poli([[30, 72], [16, 60], [22, 78]], c)
			_circulo(50, 26, 7, c)
		# EL PASE DE BATALLA (pase_pantalla.gd, 2026-09-29): un ticket con una muesca a cada lado y la estrella
		"ticket":
			var tk: Array = [[4, 20], [96, 20], [96, 38]]
			for i in 9:
				var a := -PI * 0.5 - PI * i / 8.0
				tk.append([96.0 + cos(a) * 11.0, 50.0 + sin(a) * 11.0])
			tk.append_array([[96, 80], [4, 80], [4, 62]])
			for i in 9:
				var a := PI * 0.5 - PI * i / 8.0
				tk.append([4.0 + cos(a) * 11.0, 50.0 + sin(a) * 11.0])
			_poli(tk, c)
			var est: Array = []
			for i in 10:
				var a := -PI * 0.5 + i * TAU / 10.0
				var r := 19.0 if i % 2 == 0 else 8.0
				est.append([50.0 + cos(a) * r, 52.0 + sin(a) * r])
			_poli(est, Color(0.05, 0.05, 0.06, 0.85))
		# LOS CUBOS DE FUERZA (cofres.gd, 2026-09-29): la moneda de subir de nivel a los personajes. Un cubo en
		# isometrica con el marco violeta, los paneles de energia cian y el rayo blanco (el mismo que el cubo 3D de
		# cofre_pantalla.gd). Lleva SUS colores: de `color` solo coge la transparencia.
		"cubo_fuerza":
			var al := c.a
			var arriba: Array = [[50, 3], [93, 27], [50, 51], [7, 27]]
			var izq: Array = [[7, 27], [50, 51], [50, 98], [7, 74]]
			var der: Array = [[50, 51], [93, 27], [93, 74], [50, 98]]
			_poli(arriba, Color(0.76, 0.58, 1.0, al))
			_poli(izq, Color(0.5, 0.28, 0.92, al))
			_poli(der, Color(0.32, 0.15, 0.68, al))
			_poli(_encoger(arriba, 0.56), Color(0.7, 1.0, 1.0, al))
			_poli(_encoger(izq, 0.58), Color(0.24, 0.86, 1.0, al))
			_poli(_encoger(der, 0.58), Color(0.1, 0.58, 0.95, al))
			_linea([[7, 27], [50, 51], [93, 27]], Color(1, 1, 1, 0.55 * al), 3.0)
			_linea([[50, 51], [50, 98]], Color(1, 1, 1, 0.3 * al), 3.0)
			var rayo: Array = [[54, 30], [68, 30], [57, 52], [68, 52], [42, 90], [49, 61], [37, 61]]
			_linea(rayo, Color(0.22, 0.06, 0.48, al), 7.0, true)
			_poli(rayo, Color(1, 1, 1, al))
		# LOS COFRES (cofre_pantalla.gd, 2026-09-29): la madera del color de `color` (la rareza), la tapa abombada a
		# escalones, bandas oscuras, la junta que brilla y la cerradura dorada
		"cofre":
			var al := c.a
			var oscuro := Color(c.darkened(0.62), al)
			var oro := Color(1.0, 0.82, 0.3, al)
			_poli([[22, 8], [78, 8], [78, 20], [22, 20]], Color(c.lightened(0.3), al))
			_poli([[12, 18], [88, 18], [88, 30], [12, 30]], Color(c.lightened(0.2), al))
			_poli([[5, 28], [95, 28], [95, 47], [5, 47]], Color(c.lightened(0.1), al))
			_poli([[7, 50], [93, 50], [93, 92], [7, 92]], c)
			_linea([[9, 66], [91, 66]], Color(c.darkened(0.4), al), 3.0)
			_linea([[9, 80], [91, 80]], Color(c.darkened(0.4), al), 3.0)
			for x in [18.0, 74.0]:
				_poli([[x, 18], [x + 9, 18], [x + 9, 94], [x, 94]], oscuro)
			_poli([[3, 87], [97, 87], [97, 97], [3, 97]], oscuro)
			_poli([[3, 45], [97, 45], [97, 52], [3, 52]], Color(c.lightened(0.75), al))
			_poli([[40, 38], [60, 38], [60, 68], [40, 68]], oro)
			_poli([[40, 64], [60, 64], [60, 68], [40, 68]], Color(0.75, 0.48, 0.1, al))
			_circulo(50, 50, 4.5, Color(0.1, 0.06, 0.04, al))
			_poli([[48, 51], [52, 51], [53, 60], [47, 60]], Color(0.1, 0.06, 0.04, al))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Los puntos de `pts` acercados a su centro (`k` = 1 los deja igual)
func _encoger(pts: Array, k: float) -> Array:
	var cx := 0.0
	var cy := 0.0
	for q in pts:
		cx += float(q[0])
		cy += float(q[1])
	cx /= pts.size()
	cy /= pts.size()
	var out: Array = []
	for q in pts:
		out.append([cx + (float(q[0]) - cx) * k, cy + (float(q[1]) - cy) * k])
	return out


# ================================================================== LAS CARTAS (cartas.gd, 2026-09-29)
## Un hexagono con la punta arriba, de radio `r`, centrado en (cx, cy)
func _hex_en(cx: float, cy: float, r: float) -> Array:
	var out: Array = []
	for i in 6:
		var a := deg_to_rad(60.0 * i - 90.0)
		out.append([cx + r * cos(a), cy + r * sin(a)])
	return out


## Un poligono con un color por vertice (en el cuadrado de 100)
func _poli_grad(pts: Array, cols: Array) -> void:
	var arr := PackedVector2Array()
	var cc := PackedColorArray()
	for i in pts.size():
		arr.append(_p(pts[i][0], pts[i][1]))
		cc.append(cols[i])
	draw_polygon(arr, cc)


## Un trazo grueso con las puntas y los codos redondos (los muñecos de las cartas)
func _trazo(pts: Array, c: Color, w: float) -> void:
	_linea(pts, c, w)
	for q in pts:
		_circulo(q[0], q[1], w * 0.5, c)


## Los puntos de `pts` girados `a` radianes alrededor de (cx, cy)
func _girar(pts: Array, cx: float, cy: float, a: float) -> Array:
	var out: Array = []
	var ca := cos(a)
	var sa := sin(a)
	for q in pts:
		var dx := float(q[0]) - cx
		var dy := float(q[1]) - cy
		out.append([cx + dx * ca - dy * sa, cy + dx * sa + dy * ca])
	return out


## Un corazon (la curva de siempre) centrado en (cx, cy), `s` = lo que mide cada unidad
func _corazon(cx: float, cy: float, s: float) -> Array:
	var out: Array = []
	for i in 40:
		var t := TAU * i / 40.0
		var sn := sin(t)
		var x := 16.0 * sn * sn * sn
		var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		out.append([cx + x * s, cy - y * s])
	return out


## EL HEXAGONO DE UNA CARTA (como los de la foto): la sombra, el canto oscuro, el bisel -claro arriba, oscuro abajo-, la
## cara con su degradado y el brillo cortado en diagonal, y el dibujo en blanco con su sombra del color de la carta
func _hex_carta(nombre: String) -> void:
	var col := Color(color, 1.0)
	var al := color.a
	var con := func(c: Color) -> Color: return Color(c, c.a * al)
	_poli(_hex_en(50, 53, 49), con.call(Color(0.05, 0.02, 0.15, 0.35)))
	_poli(_hex_en(50, 50, 49), con.call(col.darkened(0.55)))
	_poli_grad(_hex_en(50, 50, 46.5), [con.call(col.lightened(0.55)), con.call(col.lightened(0.28)),
		con.call(col.darkened(0.2)), con.call(col.darkened(0.42)), con.call(col.darkened(0.2)), con.call(col.lightened(0.28))])
	var cara := _hex_en(50, 50, 39.0)
	_poli_grad(cara, [con.call(col.lightened(0.2)), con.call(col.lightened(0.08)), con.call(col.darkened(0.08)),
		con.call(col.darkened(0.2)), con.call(col.darkened(0.08)), con.call(col.lightened(0.08))])
	# el brillo: la mitad de arriba de la cara, algo mas clara, cortada en diagonal
	_poli([[50, 11], [83.8, 30.5], [83.8, 40], [16.2, 60], [16.2, 30.5]], con.call(Color(1, 1, 1, 0.12)))
	_linea([cara[5], cara[0], cara[1]], con.call(Color(1, 1, 1, 0.5)), 2.2)
	# el dibujo, mas pequeño y centrado: primero su sombra (el color de la carta, oscuro) y luego en blanco. Los huecos
	# del dibujo en blanco van del color de la cara.
	var s := 0.6
	var centro := _p(50, 50)
	var sombra: Color = con.call(Color(col.darkened(0.62), 0.6))
	draw_set_transform(centro * (1.0 - s) + Vector2(0, 2.6 * _k()), 0.0, Vector2(s, s))
	_pictograma(nombre, sombra, sombra, true)
	draw_set_transform(centro * (1.0 - s), 0.0, Vector2(s, s))
	_pictograma(nombre, con.call(Color.WHITE), con.call(col), true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## LOS DIBUJOS DE LAS CARTAS, en el cuadrado de 100. `h`: el color de los huecos (transparente: sin huecos). `en_hex`: el
## del hexagono, que en alguna lleva algo mas (el estallido detras del puño) o es otro (el cronometro en vez de la estrella)
func _pictograma(nombre: String, c: Color, h: Color, en_hex := false) -> void:
	var con_hueco := h.a > 0.001
	match nombre:
		"dano":
			if en_hex:
				var pts: Array = []
				for i in 16:
					var a := -PI * 0.5 + i * TAU / 16.0
					var r := 48.0 if i % 2 == 0 else 34.0
					pts.append([50.0 + cos(a) * r, 52.0 + sin(a) * r])
				_poli(pts, c)
				_puno(50, 55, 0.58, h, c)
			else:
				_puno(50, 50, 1.0, c, h)
		"municion":
			for i in 3:
				var x := 20.0 + i * 18.0
				_poli([[x - 7, 80], [x - 7, 40], [x - 6, 32], [x - 3.5, 25], [x, 20], [x + 3.5, 25], [x + 6, 32],
					[x + 7, 40], [x + 7, 80]], c)
				_poli([[x - 8.5, 83], [x + 8.5, 83], [x + 8.5, 90], [x - 8.5, 90]], c)
				if con_hueco:
					_linea([[x - 7, 44], [x + 7, 44]], h, 3.0)
			_poli([[70, 65], [92, 65], [92, 74], [70, 74]], c)
			_poli([[76.5, 58.5], [85.5, 58.5], [85.5, 80.5], [76.5, 80.5]], c)
		"vida":
			_poli(_corazon(50, 47, 2.55), c)
			if con_hueco and not en_hex:
				# (la columna de categorias: el corazon con la cruz, como SUPERVIVENCIA en la foto)
				_poli([[44, 31], [56, 31], [56, 43], [68, 43], [68, 55], [56, 55], [56, 67], [44, 67], [44, 55], [32, 55],
					[32, 43], [44, 43]], h)
		"regeneracion":
			_poli(_corazon(43, 42, 2.15), c)
			if con_hueco:
				_circulo(70, 70, 25, h)
			_circulo(70, 70, 19, c)
			if con_hueco:
				_linea([[70, 57], [70, 71], [80, 71]], h, 5.0)
		"velocidad":
			_circulo(64, 18, 9.5, c)
			_trazo([[60, 32], [50, 57]], c, 12.0)
			_trazo([[58, 37], [72, 46], [83, 38]], c, 8.5)
			_trazo([[57, 37], [44, 42], [37, 55]], c, 8.5)
			_trazo([[50, 57], [66, 66], [63, 86]], c, 9.5)
			_trazo([[50, 57], [42, 74], [25, 78]], c, 9.5)
			for l in [[[6, 33], [26, 33]], [[2, 49], [24, 49]], [[9, 65], [27, 65]]]:
				_trazo(l, c, 6.0)
		"salto":
			_circulo(50, 14, 9.5, c)
			_trazo([[50, 28], [50, 52]], c, 12.0)
			_trazo([[49, 31], [36, 21], [30, 8]], c, 8.5)
			_trazo([[51, 31], [64, 21], [70, 8]], c, 8.5)
			_trazo([[50, 52], [37, 60], [41, 73]], c, 9.5)
			_trazo([[50, 52], [63, 60], [59, 73]], c, 9.5)
			_trazo([[34, 83], [34, 95]], c, 6.0)
			_trazo([[50, 81], [50, 97]], c, 6.0)
			_trazo([[66, 83], [66, 95]], c, 6.0)
		"destruccion":
			_poli([[12, 40], [46, 40], [46, 53], [60, 53], [60, 90], [12, 90]], c)
			for q in [[64, 36, 11.0], [76, 22, 9.0], [79, 45, 8.0], [60, 20, 7.0], [89, 10, 6.0]]:
				var s: float = q[2]
				_poli([[q[0], q[1]], [q[0] + s, q[1]], [q[0] + s, q[1] + s], [q[0], q[1] + s]], c)
			if con_hueco and en_hex:
				_linea([[28, 40], [34, 56], [26, 67], [36, 90]], h, 4.0)
		"explosion":
			var fuera := [48.0, 36.0, 44.0, 38.0, 48.0, 35.0, 45.0, 39.0, 46.0, 37.0, 44.0]
			var pts: Array = []
			for i in 22:
				var a := -PI * 0.5 + i * TAU / 22.0
				var r: float = float(fuera[i >> 1]) if i % 2 == 0 else 24.0 + (i % 3) * 2.5
				pts.append([50.0 + cos(a) * r, 52.0 + sin(a) * r])
			_poli(pts, c)
			if con_hueco:
				var dentro: Array = []
				for i in 14:
					var a := -PI * 0.5 + 0.2 + i * TAU / 14.0
					var r := 21.0 if i % 2 == 0 else 12.0
					dentro.append([50.0 + cos(a) * r, 53.0 + sin(a) * r])
				_poli(dentro, h)
				_circulo(50, 53, 7, c)
		"especial":
			if en_hex:
				# el cronometro con el rayo: la recarga de la definitiva (la carta de la foto)
				_arco(50, 56, 31, 0.0, TAU, c, 9.0)
				_poli([[43, 8], [57, 8], [57, 17], [43, 17]], c)
				_poli([[47, 16], [53, 16], [53, 26], [47, 26]], c)
				_poli([[73, 21], [81, 28], [77, 32], [69, 25]], c)
				_poli([[56, 33], [37, 60], [49, 60], [43, 81], [64, 51], [52, 51]], c)
			else:
				# la estrella (ESPECIAL en la columna de categorias, como en la foto)
				var est: Array = []
				for i in 10:
					var a := -PI * 0.5 + i * TAU / 10.0
					var r := 48.0 if i % 2 == 0 else 20.0
					est.append([50.0 + cos(a) * r, 55.0 + sin(a) * r])
				_poli(est, c)
		"vampiro":
			# la gota de sangre con los dos colmillos
			_circulo(50, 62, 27, c)
			_poli([[50, 8], [74, 50], [26, 50]], c)
			if con_hueco:
				_poli([[36, 52], [46, 52], [41, 72]], h)
				_poli([[54, 52], [64, 52], [59, 72]], h)
		"rescatista":
			# la cruz de socorro con el pulso por encima
			_poli([[38, 14], [62, 14], [62, 38], [86, 38], [86, 62], [62, 62], [62, 86], [38, 86], [38, 62], [14, 62],
				[14, 38], [38, 38]], c)
			if con_hueco:
				_linea([[18, 50], [36, 50], [43, 36], [52, 66], [59, 44], [64, 50], [82, 50]], h, 5.0)
		"blindaje":
			# el escudo con la bala
			_poli([[50, 6], [86, 18], [82, 56], [50, 94], [18, 56], [14, 18]], c)
			if con_hueco:
				_poli([[50, 22], [62, 30], [62, 60], [38, 60], [38, 30]], h)
				_poli([[38, 64], [62, 64], [62, 72], [38, 72]], h)
		"piel_dura":
			# el escudo con el puño que choca
			_poli([[50, 6], [86, 18], [82, 56], [50, 94], [18, 56], [14, 18]], c)
			if con_hueco:
				_puno(50, 50, 0.5, h, c)
		"definitiva":
			# la barra que se llena (tres cuartos de anillo) con el rayo y la flecha de subir
			_arco(50, 54, 36, PI * 0.75, PI * 2.25, c, 9.0)
			_poli([[56, 22], [33, 58], [47, 58], [40, 86], [66, 48], [52, 48]], c)
			_poli([[80, 6], [94, 22], [86, 22], [86, 34], [74, 34], [74, 22], [66, 22]], c)
		"todo":
			# una carta algo torcida con la flecha de subir (TODO en la columna de categorias)
			var carta := _girar([[32, 10], [72, 10], [72, 86], [68, 90], [28, 90], [28, 14]], 50, 50, 0.2)
			var flecha := _girar([[50, 27], [67, 48], [57, 48], [57, 70], [43, 70], [43, 48], [33, 48]], 50, 50, 0.2)
			if con_hueco:
				_poli(carta, c)
				_poli(flecha, h)
			else:
				_linea(carta, c, 8.0, true)
				_poli(flecha, c)


## Un puño de frente: cuatro dedos separados, la palma, la muñeca y el pulgar cruzado (en `raya`, si se ve)
func _puno(cx: float, cy: float, k: float, col: Color, raya: Color) -> void:
	var q := func(x: float, y: float) -> Array: return [cx + x * k, cy + y * k]
	for i in 4:
		var x0 := -32.0 + i * 16.5
		_poli([q.call(x0, -22), q.call(x0 + 14.5, -22), q.call(x0 + 14.5, -8), q.call(x0, -8)], col)
		_circulo(cx + (x0 + 7.25) * k, cy - 22.0 * k, 7.25 * k, col)
	_poli([q.call(-32, -5), q.call(32, -5), q.call(32, 14), q.call(22, 27), q.call(-24, 27), q.call(-32, 17)], col)
	_poli([q.call(-19, 31), q.call(19, 31), q.call(19, 43), q.call(-19, 43)], col)
	if raya.a > 0.001:
		_linea([q.call(-31, 5), q.call(4, 5), q.call(11, 13)], raya, 4.5 * k)


## Dos cartas, una encima de otra (las copias de una carta): la de atras algo girada
func _copias(c: Color) -> void:
	var borde := Color(0.1, 0.06, 0.25, 0.6 * c.a)
	var atras := _girar([[36, 12], [82, 12], [82, 78], [36, 78]], 59, 45, 0.24)
	_poli(atras, Color(c.darkened(0.12), c.a))
	_linea(atras, borde, 4.0, true)
	var frente := _girar([[16, 22], [62, 22], [62, 88], [16, 88]], 39, 55, -0.14)
	_poli(frente, c)
	_linea(frente, borde, 4.0, true)
