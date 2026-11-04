extends CanvasLayer
## EL AVISO DE SOLICITUD DE AMISTAD EN EL LOBBY (2026-09-28, pedido con captura). Cuando alguien te invita y estas
## en el lobby (no en partida), baja arriba una tarjeta blanca con su retrato y su nivel, "<nombre> te envió
## SOLICITUD DE AMISTAD", X (rechazar) y ✓ (aceptar). Arriba, una barrita que se va gastando: si no contestas a
## tiempo, la tarjeta se va (la invitacion sigue en AMIGOS -> INVITACIONES). Si llegan varias, de una en una.
## La trae el latido de la cuenta (Cuenta.solicitud_amistad) y la pone lobby.gd.
##
## LAS INVITACIONES DE EQUIPO (2026-09-30, grupo.gd) salen en la misma tarjeta (`tipo: "equipo"`): "<nombre> te envió
## INVITACIÓN DE EQUIPO", la cuenta atras en un circulo (lo que le queda de verdad, el servidor la caduca a los 20 s) y
## RECHAZAR / ACEPTAR con su nombre debajo del signo. Pasan delante de las de amistad (esas no caducan).

const DURA := 12.0
const ANCHO := 900.0
const ALTO := 118.0
const IconoLobby := preload("res://scripts/icono_lobby.gd")

var _cola: Array = []
var _tarjeta: Control = null
var _barra: _Barra = null
var _t := 0.0
var _dura := DURA                 ## lo que dura la tarjeta de ahora (la de equipo, lo que le quede a la invitacion)
var _reloj: Label = null          ## la cuenta atras de la de equipo
var _f: SystemFont
var _fn: SystemFont
var _raiz: Control
var _w := 1920.0


func _ready() -> void:
	layer = 65
	_f = SystemFont.new()
	_f.font_names = PackedStringArray(["Segoe UI", "Roboto", "Arial", "sans-serif"])
	_f.font_weight = 800
	_f.font_italic = true
	_fn = SystemFont.new()
	_fn.font_names = PackedStringArray(["Segoe UI", "Roboto", "Arial", "sans-serif"])
	_fn.font_weight = 600
	_fn.font_italic = true
	_raiz = Control.new()
	_raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_raiz)
	var tam: Vector2 = get_viewport().get_visible_rect().size
	var k: float = tam.y / 1080.0
	_raiz.scale = Vector2(k, k)
	_w = tam.x / k


## Una invitacion nueva: {id, nombre, nivel, skin} (y las de equipo, ademas {tipo: "equipo", quedan})
func poner(ficha: Dictionary) -> void:
	for f in _cola:
		if str(f.get("id", "")) == str(ficha.get("id", "")):
			return
	if String(ficha.get("tipo", "")) == "equipo":
		ficha = ficha.duplicate()
		ficha["hasta_ms"] = Time.get_ticks_msec() + int(float(ficha.get("quedan", 20.0)) * 1000.0)
		_cola.push_front(ficha)
	else:
		_cola.append(ficha)
	if _tarjeta == null:
		_siguiente()


func _process(dt: float) -> void:
	if _tarjeta == null or not is_instance_valid(_tarjeta):
		return
	_t += dt
	if is_instance_valid(_barra):
		_barra.resto = clampf(1.0 - _t / _dura, 0.0, 1.0)
		_barra.queue_redraw()
	if is_instance_valid(_reloj):
		_reloj.text = str(int(ceil(maxf(0.0, _dura - _t))))
	if _t >= _dura:
		_quitar()


func _siguiente() -> void:
	if _cola.is_empty():
		return
	var f: Dictionary = _cola.pop_front()
	_t = 0.0
	_dura = DURA
	_reloj = null
	var equipo := String(f.get("tipo", "")) == "equipo"
	if equipo:
		# lo que le queda de verdad: si ya caduco mientras esperaba en la cola, ni se enseña
		_dura = (float(f.get("hasta_ms", 0)) - Time.get_ticks_msec()) * 0.001
		if _dura < 1.5:
			_siguiente()
			return
	var c := Control.new()
	c.size = Vector2(ANCHO, ALTO + 12)
	c.position = Vector2(_w * 0.5 - ANCHO * 0.5, -ALTO - 40)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	_raiz.add_child(c)
	_tarjeta = c
	var fondo := _Tarjeta.new()
	fondo.tam = Vector2(ANCHO, ALTO)
	fondo.position = Vector2(0, 12)
	c.add_child(fondo)
	_barra = _Barra.new()
	_barra.ancho = ANCHO - 40.0
	c.add_child(_barra)
	# el retrato con el nivel
	_retrato(int(f.get("skin", 0)), int(f.get("nivel", 1)), Vector2(96, 90), Vector2(14, 26), c)
	var nombre := String(f.get("nombre", ""))
	# la de equipo deja sitio a la cuenta atras (el circulo, antes de los botones)
	var ancho_txt := 346.0 if equipo else 460.0
	var l1 := _texto("%s te envió" % nombre, 28, Color(0.36, 0.36, 0.44), _fn, Vector2(128, 26), Vector2(ancho_txt, 40), c)
	l1.add_theme_font_size_override("font_size", _cabe(l1.text, ancho_txt, 28, 18, _fn))
	var titulo := "INVITACIÓN DE EQUIPO" if equipo else "SOLICITUD DE AMISTAD"
	var l2 := _texto(titulo, 36, Color(0.12, 0.12, 0.2), _f, Vector2(128, 62), Vector2(ancho_txt + 10, 50), c)
	l2.add_theme_font_size_override("font_size", _cabe(titulo, ancho_txt + 6.0, 36, 22, _f))
	var id := str(f.get("id", ""))
	if equipo:
		var circulo := _Reloj.new()
		circulo.position = Vector2(ANCHO - 392, 42)
		circulo.size = Vector2(56, 56)
		c.add_child(circulo)
		circulo.dura = _dura
		circulo.aviso = self
		_reloj = _texto(str(int(ceil(_dura))), 28, Color(0.3, 0.26, 0.62), _f, circulo.position + Vector2(0, 7), Vector2(56, 40), c)
		_reloj.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var no := _boton(Vector2(ANCHO - 330, 22), Vector2(150, 94), Color(0.55, 0.26, 0.5), "x", c, "RECHAZAR" if equipo else "")
	no.pressed.connect(func(): _responder(id, false, nombre, equipo))
	var si := _boton(Vector2(ANCHO - 170, 22), Vector2(150, 94), Color(0.1, 0.72, 0.32), "ok", c, "ACEPTAR" if equipo else "")
	si.pressed.connect(func(): _responder(id, true, nombre, equipo))
	# baja desde arriba con un pequeño rebote
	Audio.ui("submenu_abre", -4.0)
	var tw := create_tween()
	tw.tween_property(c, "position:y", 18.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _responder(id: String, aceptar: bool, nombre: String, equipo := false) -> void:
	Audio.ui("aceptar" if aceptar else "atras", -6.0)
	var al_acabar := func(ok: bool, err: String):
		var lobby := get_parent()
		if lobby and lobby.has_method("_flash"):
			if ok and equipo:
				lobby._flash("¡Ya estás en el equipo de %s!" % nombre if aceptar else "Invitación de %s rechazada" % nombre)
			elif ok:
				lobby._flash("¡%s y tú ya sois amigos!" % nombre if aceptar else "Invitación de %s rechazada" % nombre)
			else:
				lobby._flash("No se pudo: %s" % err)
	if equipo:
		Grupo.responder(id, aceptar, al_acabar)
	else:
		Cuenta.responder_amistad(id, aceptar, al_acabar)
	_quitar()


func _quitar() -> void:
	var c := _tarjeta
	_tarjeta = null
	if c == null or not is_instance_valid(c):
		_siguiente()
		return
	var tw := create_tween()
	tw.tween_property(c, "position:y", -ALTO - 40.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		c.queue_free()
		_siguiente())


func _texto(t: String, tam: int, col: Color, fuente: Font, pos: Vector2, caja: Vector2, padre: Node) -> Label:
	var l := Label.new()
	l.text = t
	l.position = pos
	l.size = caja
	l.add_theme_font_override("font", fuente)
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	padre.add_child(l)
	return l


func _cabe(t: String, ancho: float, maximo: int, minimo: int, f: Font) -> int:
	var s := maximo
	while s > minimo and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > ancho:
		s -= 1
	return s


func _boton(pos: Vector2, tam: Vector2, col: Color, signo: String, padre: Node, rotulo := "") -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.position = pos
	b.size = tam
	for e in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(e, StyleBoxEmpty.new())
	var d := _BotonSigno.new()
	d.tam = tam
	d.color = col
	d.signo = signo
	d.rotulo = rotulo
	d.fuente = _f
	b.add_child(d)
	b.mouse_entered.connect(func(): d.claro = true; d.queue_redraw())
	b.mouse_exited.connect(func(): d.claro = false; d.queue_redraw())
	padre.add_child(b)
	return b


func _retrato(skin: int, nivel: int, tam: Vector2, pos: Vector2, padre: Node) -> void:
	var marco := ColorRect.new()
	marco.color = Color(0.2, 0.6, 0.85)
	marco.position = pos
	marco.size = tam
	marco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	padre.add_child(marco)
	var skins: Array = load("res://scripts/lobby.gd").SKINS
	var sk: Dictionary = skins[clampi(skin, 0, skins.size() - 1)]
	var ruta := "res://avatar/retratos/%s.png" % String(sk["n"]).to_lower().replace(" ", "_")
	if ResourceLoader.exists(ruta):
		var recorte := Control.new()
		recorte.clip_contents = true
		recorte.position = pos + Vector2(3, 3)
		recorte.size = tam - Vector2(6, 6)
		recorte.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tr := TextureRect.new()
		tr.texture = load(ruta)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.size = Vector2(recorte.size.x, recorte.size.x * 1.25)
		tr.position = Vector2(0, -recorte.size.x * 0.06)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		recorte.add_child(tr)
		padre.add_child(recorte)
	var n := _texto(str(nivel), 40, Color(1.0, 0.82, 0.22), _f, pos + Vector2(4, tam.y * 0.45), Vector2(tam.x * 0.6, tam.y * 0.55), padre)
	n.add_theme_color_override("font_outline_color", Color(0.2, 0.08, 0.3))
	n.add_theme_constant_override("outline_size", 8)


## La tarjeta blanca con el lado derecho inclinado y su sombra
class _Tarjeta extends Control:
	var tam := Vector2(900, 118)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := 26.0
		draw_colored_polygon(PackedVector2Array([Vector2(4, 8), Vector2(tam.x + 4, 8), Vector2(tam.x - s + 4, tam.y + 8), Vector2(4, tam.y + 8)]),
			Color(0.1, 0.02, 0.2, 0.35))
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(tam.x, 0), Vector2(tam.x - s, tam.y), Vector2(0, tam.y)]),
			PackedColorArray([Color(1, 1, 1), Color(1, 1, 1), Color(0.9, 0.9, 0.95), Color(0.9, 0.9, 0.95)]))


## La barrita de tiempo de arriba: se va gastando de derecha a izquierda
class _Barra extends Control:
	var ancho := 860.0
	var resto := 1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(20, 0, ancho, 10), Color(0.82, 0.8, 0.95, 0.9))
		draw_rect(Rect2(20, 0, ancho * resto, 10), Color(0.55, 0.52, 0.85))


## Los botones X y ✓: inclinados, con su sombra, y el signo blanco dibujado
class _BotonSigno extends Control:
	var tam := Vector2(150, 94)
	var color := Color.WHITE
	var signo := "ok"
	var claro := false
	var rotulo := ""               ## si lleva, el signo sube y el nombre va debajo (ACEPTAR / RECHAZAR)
	var fuente: Font = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := 16.0
		var col := color.lightened(0.12) if claro else color
		draw_colored_polygon(PackedVector2Array([Vector2(s + 3, 6), Vector2(tam.x + 3, 6), Vector2(tam.x - s + 3, tam.y + 5), Vector2(3, tam.y + 5)]), color.darkened(0.45))
		draw_polygon(PackedVector2Array([Vector2(s, 0), Vector2(tam.x, 0), Vector2(tam.x - s, tam.y), Vector2(0, tam.y)]),
			PackedColorArray([col.lightened(0.08), col.lightened(0.08), col.darkened(0.06), col.darkened(0.06)]))
		var c := tam * 0.5
		if rotulo != "" and fuente != null:
			c.y = 34.0
			var tam_f := 20
			while tam_f > 12 and fuente.get_string_size(rotulo, HORIZONTAL_ALIGNMENT_LEFT, -1, tam_f).x > tam.x - 30.0:
				tam_f -= 1
			var base := 80.0
			draw_string_outline(fuente, Vector2(0, base), rotulo, HORIZONTAL_ALIGNMENT_CENTER, tam.x, tam_f, 5, color.darkened(0.5))
			draw_string(fuente, Vector2(0, base), rotulo, HORIZONTAL_ALIGNMENT_CENTER, tam.x, tam_f, Color.WHITE)
		if signo == "x":
			draw_line(c + Vector2(-16, -16), c + Vector2(16, 16), Color.WHITE, 9.0, true)
			draw_line(c + Vector2(16, -16), c + Vector2(-16, 16), Color.WHITE, 9.0, true)
		else:
			draw_polyline(PackedVector2Array([c + Vector2(-18, 0), c + Vector2(-5, 13), c + Vector2(19, -13)]), Color.WHITE, 9.0, true)


## La cuenta atras de la invitacion de equipo: un circulo lila que se va vaciando (el numero lo pone `_reloj`)
class _Reloj extends Control:
	var dura := 20.0
	var aviso: Node = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_dt: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.5
		var t: float = float(aviso.get("_t")) if is_instance_valid(aviso) else 0.0
		var resto := clampf(1.0 - t / maxf(dura, 0.1), 0.0, 1.0)
		draw_circle(c + Vector2(0, 3), r, Color(0.1, 0.02, 0.2, 0.25))
		draw_circle(c, r, Color(0.86, 0.84, 0.97))
		draw_arc(c, r - 5.0, -PI * 0.5, -PI * 0.5 + TAU * resto, 40, Color(0.55, 0.52, 0.85) if resto > 0.25 else Color(0.9, 0.3, 0.4), 7.0, true)
		draw_circle(c, r - 10.0, Color(1, 1, 1))
