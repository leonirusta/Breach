extends CanvasLayer
## LA ENTRADA DEL FINAL DE PARTIDA (2026-09-28, pedido con una foto): antes del podio, cuatro segundos sobre la
## partida congelada. Un RAYO dorado se dibuja deprisa de arriba abajo partiendo la pantalla; entran las dos
## BANDERAS (la tuya azul a la izquierda, la del rival roja a la derecha, la del que gana mas grande) con los
## puntos, y cae el titulo: VICTORIA en oro o DERROTA en rojo. Luego se funde y main.gd abre el podio.
## Se dibuja a 1920x1080 y se escala a la altura de la pantalla, como el resumen de muerte.
##
## EN TODOS LOS MODOS (2026-09-28): las etiquetas de las banderas y el titulo se pueden cambiar (`extra` en
## `mostrar`), y con tema "zombi" (oleadas y campaña) es mas siniestra: fondo negro con sangre, TRES ZARPAZOS
## rojos en vez del rayo, temblor al rasgar, SOBREVIVISTE / HAS CAIDO en hueso y sangre con gotas que chorrean.

signal terminado

const DUR := 4.0
const ALFA := 0.6     ## los fondos del final, semitransparentes (2026-10-28: detras va la camara de cine)
const ORO := Color(1.0, 0.84, 0.18)
const AZUL := Color(0.2, 0.5, 1.0)
const ROJO := Color(0.93, 0.24, 0.32)

var gane := true
var mios := 0
var rivales := 0
var tema := ""                       ## "" o "zombi"
var etiqueta_mia := "TU EQUIPO"
var etiqueta_rival := "EQUIPO RIVAL"
var sin_banderas := false           ## sin los puntos de cada lado (el duelo sin reaparecer: no van por bajas)
var texto := ""                      ## el titulo; vacio = VICTORIA / DERROTA (o SOBREVIVISTE / HAS CAIDO)
var _raiz: Control
var _fondo: _Fondo
var _rayo: _Rayo
var _titulo: Node2D
var _band_mia: Node2D
var _band_rival: Node2D


static func mostrar(padre: Node, p_gane: bool, p_mios: int, p_rivales: int, extra: Dictionary = {}) -> CanvasLayer:
	var f = load("res://scripts/fin_intro.gd").new()
	f.gane = p_gane
	f.mios = p_mios
	f.rivales = p_rivales
	for k in extra:
		f.set(k, extra[k])
	padre.add_child(f)
	return f


func _ready() -> void:
	layer = 45
	_raiz = Control.new()
	_raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_raiz)
	var tam: Vector2 = get_viewport().get_visible_rect().size
	var k: float = tam.y / 1080.0
	_raiz.scale = Vector2(k, k)
	var w: float = tam.x / k
	var c := Vector2(w * 0.5, 540.0)
	# el velo: azul por tu lado y rojo por el suyo, mas fuerte en los bordes
	_fondo = _Fondo.new()
	_fondo.ancho = w
	_fondo.tema = tema
	_raiz.add_child(_fondo)
	var puntos := PackedVector2Array([c + Vector2(170, -560), c + Vector2(-40, 20), c + Vector2(25, 35), c + Vector2(-190, 560)])
	if tema == "zombi":
		# un zarpazo es recto: de arriba a la derecha abajo a la izquierda, sin el quiebro del rayo
		puntos = PackedVector2Array([c + Vector2(230, -560), c + Vector2(-230, 560)])
	# las banderas, RECORTADAS por el rayo: su filo interior sigue el tramo de abajo del rayo, con una rendija
	# por la que se ve (van antes que el rayo, que se pinta encima)
	var a: Vector2 = puntos[puntos.size() - 2]
	var b: Vector2 = puntos[puntos.size() - 1]
	var rayo_x := func(y: float) -> float:
		return a.x + (b.x - a.x) * (y - a.y) / (b.y - a.y)
	var zombi := tema == "zombi"
	if not sin_banderas:
		_band_mia = _bandera(c.y + 70.0, mios, etiqueta_mia, HUESO_BAND if zombi else AZUL, true, gane, rayo_x)
		_band_rival = _bandera(c.y + 70.0, rivales, etiqueta_rival, SANGRE if zombi else ROJO, false, not gane, rayo_x)
	# el rayo (o los tres zarpazos), que se dibuja de arriba abajo
	_rayo = _Rayo.new()
	_rayo.puntos = puntos
	_rayo.garras = zombi
	_raiz.add_child(_rayo)
	# EL TITULO: letra de cartel (negra y cursiva), oro con la mitad de abajo mas anaranjada, filo grueso
	# oscuro y sombra; inclinado como en un cartel de pelea
	_titulo = Node2D.new()
	_titulo.position = c + Vector2(0, -150)
	_titulo.skew = -0.12
	_raiz.add_child(_titulo)
	var titulo := texto
	if titulo == "":
		titulo = ("SOBREVIVISTE" if gane else "HAS CAÍDO") if zombi else ("VICTORIA" if gane else "DERROTA")
	var arriba := Color(1.0, 0.93, 0.36) if gane else Color(1.0, 0.5, 0.55)
	var abajo := Color(1.0, 0.62, 0.08) if gane else Color(0.86, 0.12, 0.22)
	var filo := Color(0.42, 0.14, 0.0) if gane else Color(0.25, 0.0, 0.06)
	if zombi:
		# hueso arriba y sangre abajo; al caer, todo sangre oscura
		arriba = Color(0.96, 0.92, 0.84) if gane else Color(0.9, 0.16, 0.14)
		abajo = Color(0.66, 0.03, 0.05) if gane else Color(0.4, 0.0, 0.02)
		filo = Color(0.1, 0.0, 0.0)
	var base := _letrero(titulo, abajo, filo, 30, true)
	_titulo.add_child(base)
	var recorte := Control.new()
	recorte.clip_contents = true
	recorte.position = base.position
	recorte.size = Vector2(base.size.x, base.size.y * 0.5)
	recorte.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_titulo.add_child(recorte)
	var luz := _letrero(titulo, arriba, Color(0, 0, 0, 0), 0, false)
	luz.position = Vector2.ZERO
	recorte.add_child(luz)
	if zombi:
		# GOTAS QUE CHORREAN del filo de abajo de las letras
		var ancho_t: float = fuente_cartel().get_string_size(titulo, HORIZONTAL_ALIGNMENT_LEFT, -1, 176).x
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(titulo)
		for i in 9:
			var g := _Gota.new()
			g.position = Vector2(rng.randf_range(-ancho_t * 0.45, ancho_t * 0.45), 50.0 + rng.randf_range(-6, 6))
			g.largo = rng.randf_range(40.0, 120.0)
			g.grosor = rng.randf_range(7.0, 14.0)
			g.color = abajo.darkened(0.2)
			g.retraso = 0.7 + rng.randf() * 0.8
			_titulo.add_child(g)
	_animar(w)


static var _fuente_cartel: SystemFont = null

## LA LETRA DEL CARTEL: la mas negra que haya en el sistema (Arial Black / Segoe UI Black en Windows, Roboto
## Black en Android), en cursiva. De sistema: no pesa en el APK.
static func fuente_cartel() -> Font:
	if _fuente_cartel == null:
		_fuente_cartel = SystemFont.new()
		_fuente_cartel.font_names = PackedStringArray(["Arial Black", "Segoe UI Black", "Roboto Black", "sans-serif-black", "Impact", "sans-serif"])
		_fuente_cartel.font_weight = 900
		_fuente_cartel.font_italic = true
	return _fuente_cartel


func _letrero(texto: String, color: Color, filo: Color, grosor: int, sombra: bool) -> Label:
	var t := Label.new()
	t.text = texto
	t.add_theme_font_override("font", fuente_cartel())
	t.add_theme_font_size_override("font_size", 176)
	t.add_theme_color_override("font_color", color)
	if grosor > 0:
		t.add_theme_color_override("font_outline_color", filo)
		t.add_theme_constant_override("outline_size", grosor)
	if sombra:
		t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		t.add_theme_constant_override("shadow_offset_x", 8)
		t.add_theme_constant_override("shadow_offset_y", 12)
		t.add_theme_constant_override("shadow_outline_size", grosor)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.size = Vector2(1300, 260)
	t.position = Vector2(-650, -130)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## Una bandera pegada al rayo: `rayo_x(y)` da donde pasa el rayo a esa altura; la bandera llega hasta una rendija
## de el, con su filo inclinado igual. El que gana, mas alta y mas larga.
func _bandera(y0: float, puntos: int, texto: String, color: Color, izquierda: bool, grande: bool, rayo_x: Callable) -> Node2D:
	var n := Node2D.new()
	_raiz.add_child(n)
	var largo := 400.0 if grande else 320.0
	var alto := 176.0 if grande else 124.0
	var y1 := y0 + alto
	var rendija := 11.0 if tema != "zombi" else 88.0    # zombi: por fuera de los tres zarpazos
	var poly := Polygon2D.new()
	if izquierda:
		var xa: float = rayo_x.call(y0) - rendija
		var xb: float = rayo_x.call(y1) - rendija
		poly.polygon = PackedVector2Array([Vector2(xa - largo, y0), Vector2(xa, y0), Vector2(xb, y1), Vector2(xb - largo, y1)])
		poly.vertex_colors = PackedColorArray([Color(color, 0.0), color, color, Color(color, 0.0)])
	else:
		var xa: float = rayo_x.call(y0) + rendija
		var xb: float = rayo_x.call(y1) + rendija
		poly.polygon = PackedVector2Array([Vector2(xa, y0), Vector2(xa + largo, y0), Vector2(xb + largo, y1), Vector2(xb, y1)])
		poly.vertex_colors = PackedColorArray([color, Color(color, 0.0), Color(color, 0.0), color])
	n.add_child(poly)
	# el borde de arriba, un poco mas claro
	var brillo := Line2D.new()
	brillo.width = 4.0
	brillo.default_color = color.lightened(0.45)
	brillo.points = PackedVector2Array([poly.polygon[0], poly.polygon[1]])
	brillo.gradient = Gradient.new()
	brillo.gradient.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.7)] if izquierda else [Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.0)])
	n.add_child(brillo)
	var borde: float = rayo_x.call(y0 + alto * 0.5)
	var num := Label.new()
	num.text = str(puntos)
	num.add_theme_font_override("font", fuente_cartel())
	num.add_theme_font_size_override("font_size", 104 if grande else 68)
	num.add_theme_color_override("font_color", Color.WHITE)
	num.add_theme_color_override("font_outline_color", color.darkened(0.6))
	num.add_theme_constant_override("outline_size", 14)
	num.size = Vector2(largo - 60, alto - 50)
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if izquierda else HORIZONTAL_ALIGNMENT_LEFT
	num.position = Vector2(borde - rendija - 34 - num.size.x, y0 - 2) if izquierda else Vector2(borde + rendija + 30, y0 - 2)
	n.add_child(num)
	var et := Label.new()
	et.text = texto
	et.add_theme_font_override("font", fuente_cartel())
	et.add_theme_font_size_override("font_size", 28 if grande else 24)
	et.add_theme_color_override("font_color", Color.WHITE)
	et.add_theme_color_override("font_outline_color", color.darkened(0.6))
	et.add_theme_constant_override("outline_size", 8)
	et.size = Vector2(largo - 60, 40)
	et.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if izquierda else HORIZONTAL_ALIGNMENT_LEFT
	var borde_b: float = rayo_x.call(y1 - 24.0)
	et.position = Vector2(borde_b - rendija - 40 - et.size.x, y1 - 48) if izquierda else Vector2(borde_b + rendija + 24, y1 - 48)
	n.add_child(et)
	n.set_meta("ancla", Vector2.ZERO)
	n.set_meta("izquierda", izquierda)
	return n


func _animar(w: float) -> void:
	# 0,00-0,28 s: el rayo, de arriba abajo, con destello al llegar
	_fondo.modulate.a = 0.0
	var tf := create_tween()
	tf.tween_property(_fondo, "modulate:a", ALFA, 0.4)
	var tr := create_tween()
	tr.tween_property(_rayo, "avance", 1.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if tema == "zombi":
		# el zarpazo sacude la pantalla y se oye a la horda
		tr.tween_callback(func():
			Audio.play2d("zombi/muerte", 2.0, 0.0, Audio.PRI_MID, 0.62)
			var ts := create_tween()
			for i in 8:
				ts.tween_property(_raiz, "position", Vector2(randf_range(-14, 14), randf_range(-10, 10)), 0.035)
			ts.tween_property(_raiz, "position", Vector2.ZERO, 0.05))
	tr.tween_property(_rayo, "destello", 1.0, 0.05)
	tr.tween_property(_rayo, "destello", 0.0, 0.5)
	# 0,30 s: las banderas entran desde los lados
	for b in [_band_mia, _band_rival]:
		if b == null:
			continue
		var ancla: Vector2 = b.get_meta("ancla")
		b.position = ancla + Vector2(-w * 0.6 if bool(b.get_meta("izquierda")) else w * 0.6, 0)
		var tb := create_tween()
		tb.tween_interval(0.3)
		tb.tween_property(b, "position", ancla, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 0,45 s: el titulo cae y rebota
	_titulo.scale = Vector2(2.4, 2.4)
	_titulo.modulate.a = 0.0
	var tt := create_tween()
	tt.tween_interval(0.45)
	tt.tween_property(_titulo, "modulate:a", 1.0, 0.1)
	tt.parallel().tween_property(_titulo, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# y a los cuatro segundos se funde
	var fin := create_tween()
	fin.tween_interval(DUR - 0.35)
	fin.tween_property(_raiz, "modulate:a", 0.0, 0.35)
	fin.tween_callback(func():
		terminado.emit()
		queue_free())


class _Fondo extends Control:
	var ancho := 1920.0
	var tema := ""

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if tema == "zombi":
			load("res://scripts/fin_intro.gd").pintar_fondo_zombi(self, ancho, 0.8)
			return
		var h := 1080.0
		var m := ancho * 0.5
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(m + 170, 0), Vector2(m - 190, h), Vector2(0, h)]),
			PackedColorArray([Color(0.1, 0.35, 1.0, 0.5), Color(0.1, 0.35, 1.0, 0.0), Color(0.1, 0.35, 1.0, 0.0), Color(0.1, 0.35, 1.0, 0.5)]))
		draw_polygon(PackedVector2Array([Vector2(m + 170, 0), Vector2(ancho, 0), Vector2(ancho, h), Vector2(m - 190, h)]),
			PackedColorArray([Color(0.95, 0.2, 0.3, 0.0), Color(0.95, 0.2, 0.3, 0.4), Color(0.95, 0.2, 0.3, 0.4), Color(0.95, 0.2, 0.3, 0.0)]))
		draw_rect(Rect2(0, 0, ancho, h), Color(0, 0, 0, 0.25))


class _Rayo extends Node2D:
	var puntos := PackedVector2Array()
	var garras := false            ## tema zombi: tres zarpazos rojos en vez del rayo
	var avance := 0.0:
		set(v):
			avance = v
			queue_redraw()
	var destello := 0.0:
		set(v):
			destello = v
			queue_redraw()

	func _draw() -> void:
		if puntos.size() < 2 or avance <= 0.0:
			return
		# el trozo ya dibujado: por longitud a lo largo del zigzag
		var total := 0.0
		for i in range(1, puntos.size()):
			total += puntos[i - 1].distance_to(puntos[i])
		var queda := total * avance
		var trazo := PackedVector2Array([puntos[0]])
		for i in range(1, puntos.size()):
			var d := puntos[i - 1].distance_to(puntos[i])
			if queda >= d:
				trazo.append(puntos[i])
				queda -= d
			else:
				trazo.append(puntos[i - 1].lerp(puntos[i], queda / maxf(d, 0.01)))
				break
		if garras:
			# TRES ZARPAZOS, como tajos de uña: rectos, anchos en el medio y afilados en las dos puntas (un poligono,
			# no una linea de grosor fijo), el de en medio mas largo. Por fuera sangre oscura, dentro rojo y el corte
			# claro en el centro.
			var p0: Vector2 = puntos[0]
			var p1: Vector2 = trazo[trazo.size() - 1]
			var dir := (p1 - p0)
			var lado := Vector2(-dir.y, dir.x).normalized()
			for k in 3:
				var off := lado * (k - 1) * 44.0
				var recorte := 0.0 if k == 1 else 0.08
				var a0 := p0 + dir * recorte + off
				var a1 := p0 + dir * (1.0 - recorte) + off
				for capa in [[58.0, Color(0.25, 0.0, 0.01, 0.55)], [30.0, Color(0.6, 0.02, 0.04)], [9.0, Color(1.0, 0.45, 0.4)]]:
					_tajo(a0, a1, float(capa[0]) * (1.0 if k == 1 else 0.8), capa[1])
			if destello > 0.0:
				draw_circle(p0.lerp(puntos[puntos.size() - 1], 0.5), 130.0 * destello, Color(0.7, 0.0, 0.0, 0.35 * destello))
			return
		var oro := Color(1.0, 0.85, 0.25)
		draw_polyline(trazo, Color(1.0, 0.7, 0.1, 0.18 + 0.3 * destello), 46.0 + 30.0 * destello, true)
		draw_polyline(trazo, Color(1.0, 0.82, 0.3, 0.45), 20.0, true)
		draw_polyline(trazo, oro, 9.0, true)
		draw_polyline(trazo, Color(1.0, 1.0, 0.9), 3.5, true)
		var punta: Vector2 = trazo[trazo.size() - 1]
		if avance < 1.0:
			draw_circle(punta, 22.0, Color(1.0, 0.95, 0.7, 0.8))
		if destello > 0.0 and puntos.size() >= 3:
			draw_circle(puntos[1].lerp(puntos[2], 0.5), 90.0 * destello, Color(1.0, 0.95, 0.7, 0.5 * destello))

	## Un tajo: de `a` a `b`, ancho `ancho` en el medio y en punta en los extremos
	func _tajo(a: Vector2, b: Vector2, ancho: float, color: Color) -> void:
		var n := 16
		var lado := Vector2(-(b - a).y, (b - a).x).normalized()
		var izq := PackedVector2Array()
		var der := PackedVector2Array()
		for i in n + 1:
			var t := float(i) / n
			var w := ancho * 0.5 * pow(sin(PI * t), 0.7)
			var p := a.lerp(b, t)
			izq.append(p + lado * w)
			der.append(p - lado * w)
		der.reverse()
		izq.append_array(der)
		draw_colored_polygon(izq, color)


const HUESO_BAND := Color(0.36, 0.5, 0.44)     ## la bandera de los supervivientes (zombi): verde militar apagado
const SANGRE := Color(0.62, 0.03, 0.06)        ## la de la horda


## EL FONDO ZOMBI, para las cuatro pantallas del final (fin_intro, fin_nivel, mejores_jugadores, victoria_final):
## negro con un rojo de sangre subiendo desde abajo, viñeta, manchas y salpicaduras, y tres arañazos en la
## esquina. `opaco` = cuanto tapa la partida (la entrada deja ver algo detras; las demas, del todo).
static func pintar_fondo_zombi(ci: CanvasItem, ancho: float, opaco: float = 1.0) -> void:
	var h := 1080.0
	var negro := Color(0.03, 0.0, 0.01, opaco)
	var rojo := Color(0.28, 0.0, 0.02, opaco)
	ci.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(ancho, 0), Vector2(ancho, h), Vector2(0, h)]),
		PackedColorArray([negro, negro, rojo, rojo]))
	# viñeta roja por los bordes
	var borde := Color(0.45, 0.0, 0.02, 0.45 * opaco)
	var nada := Color(0.45, 0.0, 0.02, 0.0)
	ci.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(260, 0), Vector2(260, h), Vector2(0, h)]), PackedColorArray([borde, nada, nada, borde]))
	ci.draw_polygon(PackedVector2Array([Vector2(ancho - 260, 0), Vector2(ancho, 0), Vector2(ancho, h), Vector2(ancho - 260, h)]), PackedColorArray([nada, borde, borde, nada]))
	# manchas de sangre y salpicaduras (siempre las mismas: semilla fija)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1666
	for i in 26:
		var c := Vector2(rng.randf() * ancho, rng.randf() * h)
		var r := rng.randf_range(6.0, 38.0)
		var a := rng.randf_range(0.18, 0.5) * opaco
		ci.draw_circle(c, r, Color(0.42, 0.0, 0.02, a))
		for j in 5:
			var ang := rng.randf() * TAU
			ci.draw_circle(c + Vector2(cos(ang), sin(ang)) * r * rng.randf_range(1.2, 2.4), r * rng.randf_range(0.1, 0.3), Color(0.42, 0.0, 0.02, a))
	# tres arañazos en la esquina de arriba a la derecha
	for k in 3:
		var p0 := Vector2(ancho - 380.0 + k * 42.0, 40.0)
		var p1 := p0 + Vector2(-190.0, 330.0)
		ci.draw_line(p0, p1, Color(0.3, 0.0, 0.02, 0.7 * opaco), 16.0, true)
		ci.draw_line(p0, p1, Color(0.55, 0.05, 0.06, 0.8 * opaco), 6.0, true)


## Una gota de sangre que chorrea del titulo (zombi): crece hacia abajo despacio y acaba en bola.
class _Gota extends Node2D:
	var largo := 80.0
	var grosor := 10.0
	var color := Color(0.5, 0.0, 0.02)
	var retraso := 0.8
	var _t := 0.0

	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()

	func _draw() -> void:
		var k := clampf((_t - retraso) / 2.2, 0.0, 1.0)
		if k <= 0.0:
			return
		var l := largo * (1.0 - pow(1.0 - k, 2.0))
		draw_rect(Rect2(-grosor * 0.5, 0, grosor, l), color)
		draw_circle(Vector2(0, l), grosor * 0.75, color)
		draw_rect(Rect2(-grosor * 0.2, 0, grosor * 0.25, l * 0.8), Color(1, 0.5, 0.5, 0.25))
