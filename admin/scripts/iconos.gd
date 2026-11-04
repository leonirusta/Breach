class_name Iconos
extends Control
## ICONOS DEL PANEL, DIBUJADOS A MANO (como `icono_lobby.gd` en el juego): lineas y poligonos en un cuadrado de
## 100x100, nitidos a cualquier tamaño. `Iconos.dibujar(lienzo, nombre, rect, color)` pinta uno dentro de cualquier
## control (los botones lo usan asi); un nodo `Iconos` es un icono suelto para meter en un contenedor.

var icono := "usuario":
	set(v):
		icono = v
		queue_redraw()
var color := Color.WHITE:
	set(v):
		color = v
		queue_redraw()
var grosor := 8.0


func _init(p_icono := "usuario", p_color := Color.WHITE, lado := 22.0) -> void:
	icono = p_icono
	color = p_color
	custom_minimum_size = Vector2(lado, lado)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var lado := minf(size.x, size.y)
	dibujar(self, icono, Rect2((size - Vector2(lado, lado)) * 0.5, Vector2(lado, lado)), color, grosor)


static func dibujar(ci: CanvasItem, nombre: String, r: Rect2, c: Color, g := 8.0) -> void:
	ci.draw_set_transform(r.position, 0.0, r.size / 100.0)
	var hueco := Color(0.06, 0.07, 0.09)
	match nombre:
		"buscar":
			ci.draw_arc(Vector2(42, 42), 27, 0, TAU, 40, c, g, true)
			ci.draw_line(Vector2(62, 62), Vector2(88, 88), c, g + 2, true)
		"atras":
			ci.draw_polyline(_v([[58, 16], [24, 50], [58, 84]]), c, g + 1, true)
			ci.draw_line(Vector2(26, 50), Vector2(86, 50), c, g + 1, true)
		"flecha":
			ci.draw_polyline(_v([[36, 16], [70, 50], [36, 84]]), c, g + 1, true)
		"salir":
			ci.draw_polyline(_v([[56, 14], [16, 14], [16, 86], [56, 86]]), c, g, true)
			ci.draw_line(Vector2(38, 50), Vector2(78, 50), c, g, true)
			ci.draw_colored_polygon(_v([[96, 50], [72, 30], [72, 70]]), c)
		"mas":
			ci.draw_line(Vector2(50, 14), Vector2(50, 86), c, g + 2, true)
			ci.draw_line(Vector2(14, 50), Vector2(86, 50), c, g + 2, true)
		"menos":
			ci.draw_line(Vector2(14, 50), Vector2(86, 50), c, g + 2, true)
		"cerrar":
			ci.draw_line(Vector2(20, 20), Vector2(80, 80), c, g + 1, true)
			ci.draw_line(Vector2(80, 20), Vector2(20, 80), c, g + 1, true)
		"check":
			ci.draw_polyline(_v([[14, 52], [38, 76], [86, 26]]), c, g + 3, true)
		"lapiz":
			ci.draw_colored_polygon(_v([[64, 14], [86, 36], [38, 84], [16, 84], [16, 62]]), c)
			ci.draw_line(Vector2(56, 22), Vector2(78, 44), hueco, 5, true)
		"regalo":
			ci.draw_colored_polygon(_v([[16, 46], [84, 46], [84, 90], [16, 90]]), c)
			ci.draw_colored_polygon(_v([[10, 30], [90, 30], [90, 44], [10, 44]]), c)
			ci.draw_line(Vector2(50, 30), Vector2(50, 90), hueco, 7)
			ci.draw_line(Vector2(16, 60), Vector2(84, 60), Color(hueco, 0.35), 4)
			ci.draw_arc(Vector2(38, 20), 11, PI * 0.1, PI * 1.9, 20, c, 6, true)
			ci.draw_arc(Vector2(62, 20), 11, -PI * 0.9, PI * 0.9, 20, c, 6, true)
		"llave":
			ci.draw_arc(Vector2(30, 50), 17, 0, TAU, 32, c, g, true)
			ci.draw_line(Vector2(47, 50), Vector2(92, 50), c, g, true)
			ci.draw_line(Vector2(74, 50), Vector2(74, 68), c, g, true)
			ci.draw_line(Vector2(88, 50), Vector2(88, 64), c, g, true)
		"candado", "candado_abierto":
			if nombre == "candado":
				ci.draw_arc(Vector2(50, 42), 20, PI, TAU, 24, c, 9, true)
				ci.draw_line(Vector2(30, 41), Vector2(30, 52), c, 9)
			else:
				ci.draw_arc(Vector2(70, 34), 20, PI, TAU, 24, c, 9, true)
				ci.draw_line(Vector2(50, 33), Vector2(50, 52), c, 9)
				ci.draw_line(Vector2(90, 33), Vector2(90, 42), c, 9)
			if nombre == "candado":
				ci.draw_line(Vector2(70, 41), Vector2(70, 52), c, 9)
			ci.draw_colored_polygon(_v([[16, 50], [84, 50], [84, 94], [16, 94]]), c)
			ci.draw_circle(Vector2(50, 68), 7, hueco)
			ci.draw_colored_polygon(_v([[47, 70], [53, 70], [55, 84], [45, 84]]), hueco)
		"bloqueo":
			ci.draw_arc(Vector2(50, 50), 36, 0, TAU, 48, c, g + 1, true)
			ci.draw_line(Vector2(25, 75), Vector2(75, 25), c, g + 1, true)
		"papelera":
			ci.draw_line(Vector2(12, 24), Vector2(88, 24), c, g, true)
			ci.draw_polyline(_v([[38, 22], [40, 10], [60, 10], [62, 22]]), c, g - 2, true)
			ci.draw_polyline(_v([[22, 32], [28, 90], [72, 90], [78, 32]]), c, g, true)
			ci.draw_line(Vector2(42, 42), Vector2(43, 78), c, g - 3, true)
			ci.draw_line(Vector2(58, 42), Vector2(57, 78), c, g - 3, true)
		"moneda", "oro":
			ci.draw_circle(Vector2(50, 50), 42, c)
			ci.draw_arc(Vector2(50, 50), 30, 0, TAU, 40, Color(0, 0, 0, 0.28), 6, true)
			ci.draw_colored_polygon(_v([[50, 30], [64, 50], [50, 70], [36, 50]]), c.lightened(0.4))
		"diamante":
			ci.draw_colored_polygon(_v([[28, 14], [72, 14], [94, 38], [50, 92], [6, 38]]), c)
			ci.draw_line(Vector2(6, 38), Vector2(94, 38), Color(0, 0, 0, 0.3), 4)
			ci.draw_polyline(_v([[28, 14], [38, 38], [50, 92], [62, 38], [72, 14]]), Color(0, 0, 0, 0.22), 3, true)
			ci.draw_colored_polygon(_v([[28, 14], [50, 14], [38, 38], [6, 38]]), Color(1, 1, 1, 0.25))
		"exp", "estrella":
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI * 0.5 + i * TAU / 10.0
				var rr := 46.0 if i % 2 == 0 else 19.0
				pts.append(Vector2(50, 53) + Vector2(cos(a), sin(a)) * rr)
			ci.draw_colored_polygon(pts, c)
		"nivel":
			ci.draw_polyline(_v([[16, 52], [50, 22], [84, 52]]), c, g + 3, true)
			ci.draw_polyline(_v([[16, 82], [50, 52], [84, 82]]), c, g + 3, true)
		"usuario":
			ci.draw_circle(Vector2(50, 32), 20, c)
			ci.draw_colored_polygon(_v([[14, 94], [18, 66], [34, 56], [66, 56], [82, 66], [86, 94]]), c)
		"grupo":
			var c2 := Color(c, c.a * 0.55)
			ci.draw_circle(Vector2(68, 30), 15, c2)
			ci.draw_colored_polygon(_v([[48, 88], [52, 64], [62, 56], [80, 56], [90, 64], [94, 88]]), c2)
			ci.draw_circle(Vector2(38, 36), 17, c)
			ci.draw_colored_polygon(_v([[6, 94], [10, 70], [24, 60], [52, 60], [66, 70], [70, 94]]), c)
		"senal":
			ci.draw_circle(Vector2(50, 50), 12, c)
			ci.draw_arc(Vector2(50, 50), 26, -PI * 0.3, PI * 0.3, 16, c, 7, true)
			ci.draw_arc(Vector2(50, 50), 26, PI * 0.7, PI * 1.3, 16, c, 7, true)
			ci.draw_arc(Vector2(50, 50), 42, -PI * 0.3, PI * 0.3, 16, c, 7, true)
			ci.draw_arc(Vector2(50, 50), 42, PI * 0.7, PI * 1.3, 16, c, 7, true)
		"mando":
			ci.draw_colored_polygon(_v([[18, 30], [82, 30], [94, 72], [84, 82], [68, 70], [32, 70], [16, 82], [6, 72]]), c)
			ci.draw_line(Vector2(22, 48), Vector2(38, 48), hueco, 6)
			ci.draw_line(Vector2(30, 40), Vector2(30, 56), hueco, 6)
			ci.draw_circle(Vector2(66, 44), 5, hueco)
			ci.draw_circle(Vector2(76, 54), 5, hueco)
		"servidor":
			for y in [10.0, 38.0, 66.0]:
				ci.draw_colored_polygon(_v([[10, y], [90, y], [90, y + 24], [10, y + 24]]), c)
				ci.draw_circle(Vector2(76, y + 12), 4.5, hueco)
				ci.draw_line(Vector2(20, y + 12), Vector2(46, y + 12), hueco, 4)
		"google":
			ci.draw_arc(Vector2(50, 50), 34, PI * 0.25, PI * 1.85, 40, c, 13, true)
			ci.draw_line(Vector2(50, 50), Vector2(86, 50), c, 13)
		"refrescar":
			ci.draw_arc(Vector2(50, 52), 32, -PI * 0.35, PI * 1.35, 40, c, g + 1, true)
			ci.draw_colored_polygon(_v([[70, 8], [90, 32], [62, 36]]), c)
		"reloj":
			ci.draw_arc(Vector2(50, 50), 38, 0, TAU, 48, c, g, true)
			ci.draw_polyline(_v([[50, 26], [50, 52], [68, 62]]), c, g, true)
		"caja":
			ci.draw_polyline(_v([[50, 8], [90, 28], [90, 72], [50, 92], [10, 72], [10, 28], [50, 8]]), c, g, true)
			ci.draw_polyline(_v([[10, 28], [50, 48], [90, 28]]), c, g, true)
			ci.draw_line(Vector2(50, 48), Vector2(50, 92), c, g, true)
		"escudo":
			ci.draw_colored_polygon(_v([[50, 4], [90, 18], [86, 58], [50, 96], [14, 58], [10, 18]]), c)
		"copiar":
			ci.draw_polyline(_v([[34, 30], [86, 30], [86, 92], [34, 92], [34, 30]]), c, g, true)
			ci.draw_polyline(_v([[20, 72], [14, 72], [14, 8], [66, 8], [66, 16]]), c, g, true)
		"ojo", "ojo_no":
			ci.draw_arc(Vector2(50, 92), 60, -PI * 0.78, -PI * 0.22, 30, c, g, true)
			ci.draw_arc(Vector2(50, 8), 60, PI * 0.22, PI * 0.78, 30, c, g, true)
			ci.draw_circle(Vector2(50, 50), 13, c)
			if nombre == "ojo_no":
				ci.draw_line(Vector2(16, 86), Vector2(84, 14), c, g, true)
		"correo":
			ci.draw_polyline(_v([[8, 20], [92, 20], [92, 80], [8, 80], [8, 20]]), c, g, true)
			ci.draw_polyline(_v([[10, 24], [50, 54], [90, 24]]), c, g, true)
		"trofeo":
			ci.draw_colored_polygon(_v([[26, 10], [74, 10], [70, 46], [58, 60], [42, 60], [30, 46]]), c)
			ci.draw_arc(Vector2(24, 26), 13, PI * 0.5, PI * 1.5, 16, c, 6, true)
			ci.draw_arc(Vector2(76, 26), 13, -PI * 0.5, PI * 0.5, 16, c, 6, true)
			ci.draw_line(Vector2(50, 58), Vector2(50, 80), c, 9)
			ci.draw_colored_polygon(_v([[30, 80], [70, 80], [74, 92], [26, 92]]), c)
		"mira":
			ci.draw_arc(Vector2(50, 50), 34, 0, TAU, 40, c, g, true)
			ci.draw_circle(Vector2(50, 50), 7, c)
			for d in [[50, 4, 50, 24], [50, 76, 50, 96], [4, 50, 24, 50], [76, 50, 96, 50]]:
				ci.draw_line(Vector2(d[0], d[1]), Vector2(d[2], d[3]), c, g, true)
		"megafono":
			ci.draw_colored_polygon(_v([[10, 38], [30, 38], [74, 12], [74, 88], [30, 62], [10, 62]]), c)
			ci.draw_colored_polygon(_v([[30, 62], [44, 62], [50, 88], [36, 88]]), c)
			ci.draw_arc(Vector2(78, 50), 16, -PI * 0.35, PI * 0.35, 12, c, 6, true)
		"dado":
			ci.draw_colored_polygon(_v([[12, 12], [88, 12], [88, 88], [12, 88]]), c)
			for p in [[32, 32], [68, 32], [50, 50], [32, 68], [68, 68]]:
				ci.draw_circle(Vector2(p[0], p[1]), 7, hueco)
		"id":
			ci.draw_polyline(_v([[6, 18], [94, 18], [94, 82], [6, 82], [6, 18]]), c, g, true)
			ci.draw_circle(Vector2(32, 42), 10, c)
			ci.draw_colored_polygon(_v([[16, 70], [20, 58], [44, 58], [48, 70]]), c)
			ci.draw_line(Vector2(58, 40), Vector2(82, 40), c, 6)
			ci.draw_line(Vector2(58, 58), Vector2(76, 58), c, 6)
		"alerta":
			ci.draw_colored_polygon(_v([[50, 6], [96, 90], [4, 90]]), c)
			ci.draw_line(Vector2(50, 36), Vector2(50, 62), hueco, 9)
			ci.draw_circle(Vector2(50, 76), 5.5, hueco)
		"tienda":
			ci.draw_polyline(_v([[8, 20], [22, 20], [32, 64], [80, 64], [90, 32], [26, 32]]), c, g, true)
			ci.draw_circle(Vector2(38, 80), 7, c)
			ci.draw_circle(Vector2(74, 80), 7, c)
		"inicio":
			ci.draw_colored_polygon(_v([[50, 8], [94, 46], [82, 46], [82, 92], [60, 92], [60, 64], [40, 64], [40, 92], [18, 92], [18, 46], [6, 46]]), c)
		"grafica":
			ci.draw_line(Vector2(8, 92), Vector2(92, 92), c, g, true)
			for b in [[18, 60], [42, 30], [66, 46]]:
				ci.draw_colored_polygon(_v([[b[0], b[1]], [b[0] + 16, b[1]], [b[0] + 16, 84], [b[0], 84]]), c)
		"vivo":
			# EN VIVO: una pantalla con el "play" dentro
			ci.draw_polyline(_v([[10, 16], [90, 16], [90, 72], [10, 72], [10, 16]]), c, g, true)
			ci.draw_colored_polygon(_v([[40, 30], [64, 44], [40, 58]]), c)
			ci.draw_line(Vector2(50, 74), Vector2(50, 88), c, g, true)
			ci.draw_line(Vector2(28, 90), Vector2(72, 90), c, g, true)
		"mapa":
			ci.draw_polyline(_v([[8, 22], [36, 12], [64, 24], [92, 14], [92, 78], [64, 88], [36, 76], [8, 86], [8, 22]]), c, g, true)
			ci.draw_line(Vector2(36, 14), Vector2(36, 76), c, g - 2, true)
			ci.draw_line(Vector2(64, 24), Vector2(64, 86), c, g - 2, true)
		"ajustes":
			# JUEGO: tres deslizadores
			for d in [[26.0, 34.0], [50.0, 68.0], [74.0, 42.0]]:
				ci.draw_line(Vector2(8, d[0]), Vector2(92, d[0]), c, g - 1, true)
				ci.draw_circle(Vector2(d[1], d[0]), 12, c)
				ci.draw_circle(Vector2(d[1], d[0]), 5, hueco)
		"cofre":
			ci.draw_colored_polygon(_v([[10, 46], [90, 46], [90, 90], [10, 90]]), c)
			ci.draw_colored_polygon(_v([[10, 40], [10, 30], [22, 14], [78, 14], [90, 30], [90, 40]]), c)
			ci.draw_line(Vector2(10, 43), Vector2(90, 43), hueco, 5)
			ci.draw_colored_polygon(_v([[42, 34], [58, 34], [58, 58], [42, 58]]), hueco)
			ci.draw_circle(Vector2(50, 44), 4, c)
		"cubo":
			# el cubo de fuerza
			ci.draw_colored_polygon(_v([[50, 6], [90, 27], [50, 48], [10, 27]]), c.lightened(0.35))
			ci.draw_colored_polygon(_v([[10, 27], [50, 48], [50, 94], [10, 73]]), c)
			ci.draw_colored_polygon(_v([[50, 48], [90, 27], [90, 73], [50, 94]]), c.darkened(0.3))
		"carta":
			ci.draw_colored_polygon(_v([[22, 8], [78, 8], [86, 16], [86, 84], [78, 92], [22, 92], [14, 84], [14, 16]]), c)
			ci.draw_colored_polygon(_v([[50, 28], [66, 50], [50, 72], [34, 50]]), hueco)
		"bandera":
			# REPORTES: el mastil y la bandera
			ci.draw_line(Vector2(20, 8), Vector2(20, 94), c, g + 1, true)
			ci.draw_colored_polygon(_v([[24, 12], [86, 12], [72, 34], [86, 56], [24, 56]]), c)
		"subir":
			ci.draw_polyline(_v([[16, 66], [50, 32], [84, 66]]), c, g + 3, true)
		"bajar":
			ci.draw_polyline(_v([[16, 34], [50, 68], [84, 34]]), c, g + 3, true)
		_:
			ci.draw_circle(Vector2(50, 50), 30, c)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _v(pts: Array) -> PackedVector2Array:
	var a := PackedVector2Array()
	for p in pts:
		a.append(Vector2(p[0], p[1]))
	return a
