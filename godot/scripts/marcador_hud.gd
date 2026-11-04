extends Control
## EL MARCADOR DE ARRIBA (2026-09-28, pedido con una foto: "en el medio, arriba de todo, ese mismo diseño").
## Una barra oscura con los lados en diagonal: a la izquierda TU equipo (bajas/objetivo y su MEDIDOR azul, que se
## llena hacia el reloj segun os acercais al objetivo), a la derecha el rival (medidor rojo), en medio el
## reloj de la partida en una caja inclinada, a la derecha el otro equipo, y debajo una cinta morada que dice como
## va ("EQUIPOS EMPATADOS", "VAIS GANANDO"...). Lo crea hud.build_match_hud y lo rellena hud._refresh_score.

const ANCHO := 540.0
const ALTO := 58.0
const NARANJA := Color(1.0, 0.52, 0.14)
const AZUL := Color(0.18, 0.56, 1.0)
const ROJO := Color(0.95, 0.26, 0.36)
const VERDE_MANZANA := Color(0.46, 0.84, 0.18)
const MORADO := Color(0.62, 0.36, 0.93)

var izq := 0              ## puntos de mi equipo (o del naranja si no tengo equipo)
var der := 0
var objetivo := 0         ## 0 = sin objetivo (se pinta el numero solo)
var color_izq := AZUL
var color_der := ROJO
var cinta := ""
var color_cinta := MORADO   ## violeta empatados, verde manzana ganando, rojo perdiendo
var _t0 := 0.0
var _seg := -1
var _l_izq: Label
var _l_der: Label
var _l_reloj: Label
var _l_cinta: Label
var _icono: Control
var _cinta: Control
var _cinta_tw: Tween
const CINTA_S := 3.0      ## lo que se queda la cinta a la vista tras cambiar


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(ANCHO, ALTO + 44)
	_t0 = Time.get_ticks_msec() * 0.001
	_l_izq = _texto(36, Vector2(18, 4), Vector2(150, ALTO - 8), HORIZONTAL_ALIGNMENT_LEFT)
	_l_der = _texto(36, Vector2(ANCHO - 168, 4), Vector2(150, ALTO - 8), HORIZONTAL_ALIGNMENT_RIGHT)
	_l_reloj = _texto(32, Vector2(ANCHO * 0.5 - 70, 6), Vector2(140, ALTO - 12), HORIZONTAL_ALIGNMENT_CENTER)
	_l_reloj.add_theme_color_override("font_color", Color(0.45, 0.04, 0.1))
	_l_reloj.add_theme_constant_override("outline_size", 0)
	# LA CINTA es una pieza aparte (con su centro de giro en el medio) para poder animarla al cambiar
	_cinta = _Cinta.new()
	_cinta.position = Vector2(ANCHO * 0.5, ALTO + 23)
	add_child(_cinta)
	_l_cinta = Label.new()
	_l_cinta.position = Vector2(-180, -17)
	_l_cinta.size = Vector2(372, 34)
	_l_cinta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_l_cinta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_l_cinta.add_theme_font_size_override("font_size", 24)
	_l_cinta.add_theme_color_override("font_color", Color.WHITE)
	_l_cinta.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.1, 0.9))
	_l_cinta.add_theme_constant_override("outline_size", 6)
	_l_cinta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cinta.add_child(_l_cinta)
	_icono = _Icono.new()
	_icono.position = Vector2(-176, 0)
	_cinta.add_child(_icono)


func _texto(tam: int, pos: Vector2, caja: Vector2, al: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = caja
	l.horizontal_alignment = al
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.1, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func poner(p_izq: int, p_der: int, p_obj: int, c_izq: Color, c_der: Color, p_cinta: String, c_cinta: Color = MORADO) -> void:
	color_cinta = c_cinta
	izq = p_izq
	der = p_der
	objetivo = p_obj
	color_izq = c_izq
	color_der = c_der
	var antes := cinta
	cinta = p_cinta
	var fmt := "%d/%d" if objetivo > 0 else "%d"
	_l_izq.text = (fmt % [izq, objetivo]) if objetivo > 0 else (fmt % izq)
	_l_der.text = (fmt % [der, objetivo]) if objetivo > 0 else (fmt % der)
	# LA CINTA AVISA Y SE VA (2026-09-30, pedido: "a 0-0 recien empezada no quiero EQUIPOS EMPATADOS; cuando cambia, que
	# aparezca, pero que despues se oculte: no que se quede todo el rato, molesta"). "" (el 0-0 del principio, lo pone
	# hud._refresh_score) = sin cinta; cada vez que cambia sale con su rebote y a los CINTA_S segundos se recoge.
	if cinta == "":
		if _cinta_tw and _cinta_tw.is_valid():
			_cinta_tw.kill()
		_cinta.visible = false
	elif antes != cinta:
		_cambiar_cinta()
	queue_redraw()


## CAMBIA COMO VA LA PARTIDA: la cinta vieja se cierra de golpe, destella en blanco y la nueva sale con un
## rebote, un poco mas grande, y se asienta con un temblor
func _cambiar_cinta() -> void:
	if _cinta_tw and _cinta_tw.is_valid():
		_cinta_tw.kill()
	var nuevo_color := color_cinta
	var nuevo_texto := cinta
	_cinta.visible = true
	_cinta_tw = create_tween()
	_cinta_tw.tween_property(_cinta, "scale", Vector2(1.08, 0.0), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_cinta_tw.tween_callback(func():
		_l_cinta.text = nuevo_texto
		_cinta.set("color", Color.WHITE)
		_cinta.set("flash", 1.0)
		_icono.visible = nuevo_texto == "EQUIPOS EMPATADOS"
		_cinta.queue_redraw())
	_cinta_tw.tween_property(_cinta, "scale", Vector2(1.25, 1.25), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_cinta_tw.tween_method(func(k: float):
		_cinta.set("color", Color.WHITE.lerp(nuevo_color, k))
		_cinta.set("flash", 1.0 - k)
		_cinta.queue_redraw(), 0.0, 1.0, 0.35)
	_cinta_tw.parallel().tween_property(_cinta, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	for i in 4:
		_cinta_tw.tween_property(_cinta, "position:x", ANCHO * 0.5 + (4.0 if i % 2 == 0 else -4.0), 0.04)
	_cinta_tw.tween_property(_cinta, "position:x", ANCHO * 0.5, 0.04)
	# y a los CINTA_S segundos se recoge (si antes no ha cambiado otra vez: el tween nuevo mata a este)
	_cinta_tw.tween_interval(CINTA_S)
	_cinta_tw.tween_property(_cinta, "scale", Vector2(1.0, 0.0), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_cinta_tw.tween_callback(func():
		_cinta.visible = false
		_cinta.scale = Vector2.ONE)


func _process(_dt: float) -> void:
	var s := int(Time.get_ticks_msec() * 0.001 - _t0)
	if s != _seg:
		_seg = s
		_l_reloj.text = "%d:%02d" % [s / 60, s % 60]


func _draw() -> void:
	var w := ANCHO
	var h := ALTO
	# la barra: oscura, con los lados en diagonal y un filo claro abajo
	draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w - 26, h), Vector2(26, h)]),
		Color(0.14, 0.13, 0.19, 0.88))
	draw_line(Vector2(26, h), Vector2(w - 26, h), Color(1, 1, 1, 0.18), 2.0)
	# LOS DOS MEDIDORES, inclinados hacia el reloj: el hueco oscuro y lo lleno, que crece HACIA el reloj con los
	# puntos (sin objetivo, lleno del todo)
	var c := w * 0.5
	var f_izq := clampf(float(izq) / float(objetivo), 0.0, 1.0) if objetivo > 0 else 1.0
	var f_der := clampf(float(der) / float(objetivo), 0.0, 1.0) if objetivo > 0 else 1.0
	var a := c - 164.0
	var b := c - 90.0
	draw_colored_polygon(PackedVector2Array([Vector2(a, 8), Vector2(b, 8), Vector2(b - 12, h - 8), Vector2(a - 12, h - 8)]), Color(0, 0, 0, 0.45))
	var xa := b - (b - a) * f_izq
	if b - xa > 1.5:          # (casi vacio: sin poligono de anchura cero, que no se puede triangular)
		draw_colored_polygon(PackedVector2Array([Vector2(xa, 8), Vector2(b, 8), Vector2(b - 12, h - 8), Vector2(xa - 12, h - 8)]), color_izq)
		draw_line(Vector2(xa, 9), Vector2(b, 9), color_izq.lightened(0.45), 2.0)
	a = c + 90.0
	b = c + 164.0
	draw_colored_polygon(PackedVector2Array([Vector2(a, 8), Vector2(b, 8), Vector2(b + 12, h - 8), Vector2(a + 12, h - 8)]), Color(0, 0, 0, 0.45))
	var xb := a + (b - a) * f_der
	if xb - a > 1.5:
		draw_colored_polygon(PackedVector2Array([Vector2(a, 8), Vector2(xb, 8), Vector2(xb + 12, h - 8), Vector2(a + 12, h - 8)]), color_der)
		draw_line(Vector2(a, 9), Vector2(xb, 9), color_der.lightened(0.45), 2.0)
	# la caja del reloj: del color del que va ganando (morado si vais iguales), con las esquinas cortadas
	var cr := MORADO.lightened(0.25)
	if izq > der:
		cr = color_izq.lightened(0.15)
	elif der > izq:
		cr = color_der.lightened(0.15)
	draw_colored_polygon(PackedVector2Array([Vector2(c - 80, 2), Vector2(c + 80, 2), Vector2(c + 92, h * 0.5), Vector2(c + 80, h - 2),
		Vector2(c - 80, h - 2), Vector2(c - 92, h * 0.5)]), cr)
	draw_polyline(PackedVector2Array([Vector2(c - 80, 2), Vector2(c + 80, 2), Vector2(c + 92, h * 0.5), Vector2(c + 80, h - 2),
		Vector2(c - 80, h - 2), Vector2(c - 92, h * 0.5), Vector2(c - 80, 2)]), Color(0.08, 0.06, 0.14), 3.0, true)


## La cinta de debajo: una franja inclinada de su color, con un barrido blanco al cambiar
class _Cinta extends Control:
	var color := Color(0.62, 0.36, 0.93)
	var flash := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var p := PackedVector2Array([Vector2(-190, -17), Vector2(196, -17), Vector2(184, 17), Vector2(-202, 17)])
		draw_colored_polygon(p, color)
		draw_line(Vector2(-190, -16), Vector2(196, -16), Color(1, 1, 1, 0.35), 2.0)
		if flash > 0.01:
			var x := lerpf(-200.0, 200.0, 1.0 - flash)
			draw_colored_polygon(PackedVector2Array([Vector2(x - 30, -17), Vector2(x + 10, -17), Vector2(x - 2, 17), Vector2(x - 42, 17)]),
				Color(1, 1, 1, 0.7 * flash))


## El simbolo de la cinta: un circulo partido en dos mitades que se abrazan (el yin y el yang del empate)
class _Icono extends Control:
	func _draw() -> void:
		var r := 11.0
		draw_circle(Vector2.ZERO, r + 1.5, Color(0.2, 0.1, 0.35))
		draw_circle(Vector2.ZERO, r, Color.WHITE)
		# media luna morada: la mitad derecha con dos bocados
		var p := PackedVector2Array()
		for i in 17:
			var a := -PI / 2 + PI * i / 16.0
			p.append(Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(p, Color(0.62, 0.36, 0.93))
		draw_circle(Vector2(0, -r * 0.5), r * 0.5, Color.WHITE)
		draw_circle(Vector2(0, r * 0.5), r * 0.5, Color(0.62, 0.36, 0.93))
		draw_circle(Vector2(0, -r * 0.5), r * 0.16, Color(0.62, 0.36, 0.93))
		draw_circle(Vector2(0, r * 0.5), r * 0.16, Color.WHITE)
