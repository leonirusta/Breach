extends CanvasLayer
## FORMAR EQUIPO (2026-09-30, pedido con captura de Pixel Gun). Lo abre la tecla EQUIPO del lobby (lobby_portada.gd, la
## "+" de arriba a la derecha; antes abria SALAS, que sigue aqui: el boton SALAS de arriba a la derecha de la lista).
##
##   el panel claro de la captura: FORMAR EQUIPO con su icono y la X; TU EQUIPO (si lo tienes: el lider, tu, y SALIR /
##   EXPULSAR); AMIGOS EN LÍNEA (n) con su retrato, su nivel, donde estan e INVITAR (que pasa a ENVIADA con la cuenta
##   atras); sin amigos conectados, "AGREGA AMIGOS PARA FORMAR EQUIPO CUANDO QUIERAS". Abajo la franja con el hexagono,
##   "Forma equipo y gana recompensas extra en cada combate" (sin INFO: se quito a peticion del usuario).
##
## Los amigos salen de GET /amigos (los que no estan desconectados); el equipo y las invitaciones, de `Grupo`. Se dibuja
## en un lienzo de 780 de alto (el de la captura: sus medidas valen tal cual) escalado a la altura de la pantalla.

signal cerrado

const ALTO := 780.0
const PW := 1005.0
const PH := 700.0
const PANEL := Color8(231, 229, 248)
const FRANJA := Color8(224, 221, 245)
const SEPARA := Color8(199, 195, 236)
const TINTA := Color8(31, 29, 58)
const TINTA2 := Color8(38, 36, 63)
const GRIS := Color8(184, 181, 208)
const FILA := Color8(246, 245, 253)
const FILA_BORDE := Color8(214, 210, 238)
const VIOLETA := Color8(111, 91, 220)
const VERDE := Color8(46, 168, 79)
const NARANJA := Color8(224, 138, 30)
const MAGENTA := Color8(196, 64, 118)
const ORO := Color8(236, 178, 40)
const IconoLobby := preload("res://scripts/icono_lobby.gd")

var lobby: Node = null
var datos_prueba: Dictionary = {}       ## --equipofoto: la respuesta de /amigos, sin red

var _raiz: Control
var _w := 1920.0
var _x0 := 0.0
var _y0 := 40.0
var _f: Font                            ## gruesa derecha (titulos, nombres)
var _fi: Font                           ## gruesa en cursiva (botones, estados)
var _amigos: Array = []
var _cargando := true
var _sin_sesion := false
var _lista: VBoxContainer
var _scroll: ScrollContainer
var _aviso: Label
var _aviso_t := 0.0
var _http: HTTPRequest
var _recargar_t := 12.0
var _reloj_t := 0.0
var _seguro := ""                       ## la clave del miembro al que se va a expulsar (segundo toque = si)


func _ready() -> void:
	layer = 62
	_f = preload("res://scripts/fuentes.gd").de(900, false)
	_fi = preload("res://scripts/fuentes.gd").de(800, true)
	var tam: Vector2 = get_viewport().get_visible_rect().size
	var k: float = tam.y / ALTO
	_w = tam.x / k
	_x0 = (_w - PW) * 0.5
	# el velo de detras: el lobby oscurecido (tocarlo cierra)
	var velo := ColorRect.new()
	velo.color = Color(0.05, 0.02, 0.12, 0.5)
	velo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	velo.mouse_filter = Control.MOUSE_FILTER_STOP
	velo.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed):
			_cerrar())
	add_child(velo)
	_raiz = Control.new()
	_raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.scale = Vector2(k, k)
	_raiz.size = Vector2(_w, ALTO)
	add_child(_raiz)
	_montar()
	_raiz.pivot_offset = Vector2(_w * 0.5, ALTO * 0.5)
	_raiz.modulate.a = 0.0
	_raiz.scale = Vector2(k, k) * 0.94
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_raiz, "modulate:a", 1.0, 0.16)
	tw.tween_property(_raiz, "scale", Vector2(k, k), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Audio.ui("submenu_abre", -4.0)
	Grupo.cambiado.connect(_rehacer_lista)
	Grupo.pedir_ya()
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_al_llegar_amigos)
	_pedir_amigos()


func _exit_tree() -> void:
	if Grupo.cambiado.is_connected(_rehacer_lista):
		Grupo.cambiado.disconnect(_rehacer_lista)


func _process(dt: float) -> void:
	if _aviso_t > 0.0:
		_aviso_t -= dt
		_aviso.modulate.a = clampf(_aviso_t * 2.0, 0.0, 1.0)
	# las cuentas atras de ENVIADA, una vez por segundo
	_reloj_t -= dt
	if _reloj_t <= 0.0:
		_reloj_t = 1.0
		if not Grupo.enviadas.is_empty():
			_rehacer_lista()
	_recargar_t -= dt
	if _recargar_t <= 0.0:
		_recargar_t = 12.0
		_pedir_amigos()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_cerrar()


func _cerrar() -> void:
	if is_queued_for_deletion():
		return
	Audio.ui("atras", -6.0)
	cerrado.emit()
	var tw := create_tween()
	tw.tween_property(_raiz, "modulate:a", 0.0, 0.12)
	tw.tween_callback(queue_free)


func avisar(t: String) -> void:
	_aviso.text = t
	_aviso_t = 3.0
	_aviso.modulate.a = 1.0


# ==================================================================================================================
# LOS AMIGOS (GET /amigos)
# ==================================================================================================================
func _pedir_amigos() -> void:
	if not datos_prueba.is_empty():
		_amigos = _en_linea(datos_prueba.get("amigos", []))
		_cargando = false
		_sin_sesion = false
		_rehacer_lista()
		return
	if not Cuenta.conectado():
		_sin_sesion = true
		_cargando = false
		_rehacer_lista()
		return
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED and _http.get_http_client_status() != HTTPClient.STATUS_CONNECTED:
		return
	var cab := PackedStringArray(["Authorization: Bearer " + Cuenta.token])
	_http.request(Cuenta.url + "/amigos", cab, HTTPClient.METHOD_GET)


func _al_llegar_amigos(_r: int, codigo: int, _c: PackedStringArray, cuerpo: PackedByteArray) -> void:
	_cargando = false
	if codigo == 200:
		var j = JSON.parse_string(cuerpo.get_string_from_utf8())
		if j is Dictionary:
			_amigos = _en_linea((j as Dictionary).get("amigos", []))
	elif codigo == 0:
		avisar("El servidor no responde")
	_rehacer_lista()


## Los conectados: primero los del lobby (a esos se les puede invitar), luego los que estan jugando
func _en_linea(lista: Array) -> Array:
	var out: Array = []
	for a in lista:
		if a is Dictionary and String(a.get("estado", "desconectado")) != "desconectado":
			out.append(a)
	out.sort_custom(func(a, b):
		var la := String(a.get("estado", "")) == "lobby"
		var lb := String(b.get("estado", "")) == "lobby"
		if la != lb:
			return la
		return String(a.get("nombre", "")).nocasecmp_to(String(b.get("nombre", ""))) < 0)
	return out


# ==================================================================================================================
# EL PANEL
# ==================================================================================================================
func _montar() -> void:
	var p := Control.new()
	p.position = Vector2(_x0, _y0)
	p.size = Vector2(PW, PH)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	_raiz.add_child(p)
	_pintado(Vector2.ZERO, Vector2(PW, PH), func(ci: Control):
		ci.draw_rect(Rect2(6, 8, PW, PH), Color(0.05, 0.0, 0.15, 0.3))
		ci.draw_rect(Rect2(0, 0, PW, PH), PANEL)
		ci.draw_rect(Rect2(0, 572, PW, PH - 572), FRANJA)
		ci.draw_rect(Rect2(0, 572, PW, 8), SEPARA), p)
	# el titulo con su icono, centrado
	var titulo := "FORMAR EQUIPO"
	var an := _f.get_string_size(titulo, HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x
	var x := PW * 0.5 - (an + 60.0) * 0.5
	var ic := IconoLobby.new()
	ic.icono = "amigos"
	ic.color = TINTA
	ic.position = Vector2(x, 28)
	ic.size = Vector2(50, 50)
	p.add_child(ic)
	var t := _label(titulo, 46, TINTA, _f)
	t.position = Vector2(x + 60, 22)
	p.add_child(t)
	# la X
	var cerrar := _boton_llano(Rect2(PW - 64, 12, 52, 52), func(ci: Control):
		ci.draw_string(_fi, Vector2(0, 40), "X", HORIZONTAL_ALIGNMENT_CENTER, ci.size.x, 40, Color8(150, 146, 180)), p)
	cerrar.pressed.connect(_cerrar)
	# SALAS: las partidas de tu red y de internet (lo que abria antes este boton). Arriba a la izquierda, frente a la X:
	# encima de la lista se quedaba debajo de las filas al desplazarla
	var salas := _boton_llano(Rect2(26, 24, 150, 42), func(ci: Control):
		var f := _forma(Rect2(Vector2.ZERO, ci.size), 10.0)
		var cerr := f.duplicate()
		cerr.append(f[0])
		ci.draw_colored_polygon(f, Color(1, 1, 1, 0.55))
		ci.draw_polyline(cerr, VIOLETA, 2.5, true)
		ci.draw_string(_fi, Vector2(0, 29), "SALAS  ›", HORIZONTAL_ALIGNMENT_CENTER, ci.size.x, 21, VIOLETA), p)
	salas.pressed.connect(func():
		_cerrar()
		if is_instance_valid(lobby):
			lobby._show_tab(4))
	# la lista (con su arrastre de dedo)
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(30, 92)
	_scroll.size = Vector2(PW - 60, 572 - 92 - 6)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	p.add_child(_scroll)
	preload("res://scripts/touch_scroll.gd").attach(_scroll)
	_lista = VBoxContainer.new()
	_lista.custom_minimum_size = Vector2(PW - 60, 0)
	_lista.add_theme_constant_override("separation", 10)
	_scroll.add_child(_lista)
	# la franja de abajo: el hexagono y el texto
	_pintado(Vector2(30, 596), Vector2(76, 76), _pintar_hexagono, p)
	var txt := _label("Forma equipo y gana recompensas extra en cada combate", 25, TINTA2, _f)
	txt.position = Vector2(122, 598)
	txt.size = Vector2(PW - 122 - 40, 72)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	txt.add_theme_constant_override("line_spacing", -4)
	p.add_child(txt)
	# el aviso (lo que conteste el servidor), encima de la franja
	_aviso = _label("", 22, Color.WHITE, _fi)
	_aviso.position = Vector2(0, 520)
	_aviso.size = Vector2(PW, 40)
	_aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aviso.add_theme_color_override("font_outline_color", TINTA)
	_aviso.add_theme_constant_override("outline_size", 8)
	_aviso.modulate.a = 0.0
	p.add_child(_aviso)
	_rehacer_lista()


## La lista entera otra vez (es corta): TU EQUIPO, AMIGOS EN LÍNEA y el vacio. Se queda donde estaba el desplazamiento.
func _rehacer_lista() -> void:
	if not is_instance_valid(_lista):
		return
	var donde := _scroll.scroll_vertical
	for c in _lista.get_children():
		_lista.remove_child(c)
		c.queue_free()
	var ancho := PW - 60.0
	var mios: Dictionary = {}
	if Grupo.en_grupo():
		var ms := Grupo.miembros()
		var modo := _modo()
		var tope := Grupo.max_de_modo(modo)
		var sub := "%d/%d · %s" % [ms.size(), tope, _titulo_modo(modo)]
		_lista.add_child(_cabecera("TU EQUIPO", sub, ms.size() > tope))
		for m in ms:
			mios[Grupo.id_txt(m.get("id", ""))] = true
			_lista.add_child(_fila_miembro(m, ancho))
		_lista.add_child(_hueco(8))
	var amigos: Array = _amigos.filter(func(a): return not mios.has(Grupo.id_txt(a.get("id", ""))))
	_lista.add_child(_cabecera("AMIGOS EN LÍNEA (%d)" % amigos.size(), "", false))
	if _cargando:
		_lista.add_child(_vacio("BUSCANDO A TUS AMIGOS...", ancho, false))
	elif _sin_sesion:
		_lista.add_child(_vacio("INICIA SESIÓN PARA FORMAR EQUIPO CON TUS AMIGOS", ancho, true))
	elif amigos.is_empty():
		_lista.add_child(_vacio("AGREGA AMIGOS PARA FORMAR EQUIPO\nCUANDO QUIERAS", ancho, true))
	else:
		for a in amigos:
			_lista.add_child(_fila_amigo(a, ancho))
	_scroll.set_deferred("scroll_vertical", donde)


## El modo del equipo (el que tiene elegido el lider)
func _modo() -> String:
	return Grupo.modo_del_equipo()


func _titulo_modo(modo: String) -> String:
	return load("res://scripts/lobby.gd")._titulo_modo(modo)


func _cabecera(t: String, sub: String, sub_rojo: bool) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 48)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(t, 26, TINTA2, _f)
	l.position = Vector2(0, 6)
	c.add_child(l)
	if sub != "":
		var s := _label(sub, 20, Color8(210, 60, 80) if sub_rojo else VIOLETA, _fi)
		s.position = Vector2(_f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x + 16, 11)
		c.add_child(s)
	return c


func _hueco(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## El vacio de la captura: el cuadro tachado y el texto gris en cursiva
func _vacio(t: String, ancho: float, con_icono: bool) -> Control:
	var alto := 300.0 if not Grupo.en_grupo() else 150.0
	var c := Control.new()
	c.custom_minimum_size = Vector2(ancho, alto)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cy := alto * 0.5 - 30.0
	if con_icono:
		_pintado(Vector2(ancho * 0.5 - 26, cy - 34), Vector2(52, 52), func(ci: Control):
			var r := Rect2(6, 6, 40, 40)
			var f := _redondeada(r, 8.0)
			var cerr := f.duplicate()
			cerr.append(f[0])
			ci.draw_polyline(cerr, Color8(207, 204, 227), 4.0, true)
			ci.draw_line(Vector2(2, 2), Vector2(50, 50), Color8(207, 204, 227), 4.0, true), c)
	var l := _label(t, 22, GRIS, _fi)
	l.position = Vector2(0, cy + 26)
	l.size = Vector2(ancho, 70)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(l)
	return c


# ==================================================================================================================
# LAS FILAS
# ==================================================================================================================
func _fila_base(ancho: float, borde: Color = FILA_BORDE) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(ancho, 84)
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	_pintado(Vector2.ZERO, Vector2(ancho, 84), func(ci: Control):
		var f := _redondeada(Rect2(0, 0, ancho, 84), 10.0)
		ci.draw_colored_polygon(f, FILA)
		var cerr := f.duplicate()
		cerr.append(f[0])
		ci.draw_polyline(cerr, borde, 2.0, true), c)
	return c


func _fila_amigo(a: Dictionary, ancho: float) -> Control:
	var c := _fila_base(ancho)
	_retrato(int(a.get("skin", 0)), int(a.get("nivel", 1)), Vector2(10, 8), c)
	var nombre := _label(String(a.get("nombre", "")), 26, TINTA, _f)
	nombre.position = Vector2(94, 8)
	nombre.size = Vector2(ancho - 94 - 230, 40)
	nombre.clip_text = true
	c.add_child(nombre)
	var jugando := String(a.get("estado", "")) == "partida"
	_estado_punto(c, Vector2(94, 50), "JUGANDO" if jugando else "EN EL LOBBY", NARANJA if jugando else VERDE)
	var id := Grupo.id_txt(a.get("id", ""))
	var quedan := Grupo.quedan_invitacion(id)
	var tope := Grupo.max_de_modo(_modo())
	var texto := "INVITAR"
	var activo := true
	if jugando:
		texto = "JUGANDO"
		activo = false
	elif quedan > 0.0:
		texto = "ENVIADA · %d" % int(ceil(quedan))
		activo = false
	elif Grupo.en_grupo() and not Grupo.soy_lider():
		texto = "SOLO EL LÍDER"
		activo = false
	elif Grupo.tamano() >= tope:
		texto = "COMPLETO"
		activo = false
	var b := _boton_fila(Rect2(ancho - 214, 14, 200, 56), texto, VIOLETA if activo else Color8(206, 202, 232),
		Color.WHITE if activo else Color8(120, 114, 170), c)
	b.disabled = not activo
	if activo:
		b.pressed.connect(func():
			Audio.ui("aceptar", -6.0)
			b.disabled = true
			Grupo.invitar(id, tope, func(ok: bool, err: String):
				if not is_inside_tree():
					return
				avisar(("Invitación enviada a %s" % String(a.get("nombre", ""))) if ok else ("No se pudo: %s" % err))
				_rehacer_lista()))
	return c


func _fila_miembro(m: Dictionary, ancho: float) -> Control:
	var yo := bool(m.get("yo", false))
	var c := _fila_base(ancho, ORO if bool(m.get("lider", false)) else FILA_BORDE)
	_retrato(int(m.get("skin", 0)), int(m.get("nivel", 1)), Vector2(10, 8), c)
	var nombre := _label(String(m.get("nombre", "")), 26, TINTA, _f)
	nombre.position = Vector2(94, 8)
	nombre.size = Vector2(ancho - 94 - 230, 40)
	nombre.clip_text = true
	c.add_child(nombre)
	var etiquetas: Array = []
	if bool(m.get("lider", false)):
		etiquetas.append(["LÍDER", ORO])
	if yo:
		etiquetas.append(["TÚ", VIOLETA])
	var jugando := String(m.get("donde", "")) == "partida"
	var x := 94.0
	for e in etiquetas:
		var an := _fi.get_string_size(String(e[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 18.0
		var col: Color = e[1]
		var t := String(e[0])
		_pintado(Vector2(x, 50), Vector2(an, 24), func(ci: Control):
			ci.draw_colored_polygon(_forma(Rect2(Vector2.ZERO, ci.size), 6.0), col)
			ci.draw_string(_fi, Vector2(0, 18), t, HORIZONTAL_ALIGNMENT_CENTER, ci.size.x, 17, Color.WHITE), c)
		x += an + 8.0
	if jugando:
		_estado_punto(c, Vector2(x + 4, 50), "JUGANDO", NARANJA)
	var k := String(m.get("k", ""))
	if yo:
		var b := _boton_fila(Rect2(ancho - 214, 14, 200, 56), "SALIR", MAGENTA, Color.WHITE, c)
		b.pressed.connect(func():
			Audio.ui("atras", -6.0)
			Grupo.salir(func(ok: bool, err: String):
				if is_inside_tree():
					avisar("Has salido del equipo" if ok else "No se pudo: %s" % err)))
	elif Grupo.soy_lider():
		var seguro := _seguro == k
		var b := _boton_fila(Rect2(ancho - 214, 14, 200, 56), "¿SEGURO?" if seguro else "EXPULSAR",
			Color8(214, 60, 84) if seguro else Color8(236, 118, 136), Color.WHITE, c)
		b.pressed.connect(func():
			if _seguro != k:
				_seguro = k
				_rehacer_lista()
				return
			_seguro = ""
			Audio.ui("atras", -6.0)
			Grupo.expulsar(k, func(ok: bool, err: String):
				if is_inside_tree():
					avisar(("%s ya no está en el equipo" % String(m.get("nombre", ""))) if ok else "No se pudo: %s" % err)))
	return c


func _estado_punto(padre: Control, pos: Vector2, t: String, col: Color) -> void:
	_pintado(pos, Vector2(20, 24), func(ci: Control): ci.draw_circle(Vector2(8, 12), 6.0, col), padre)
	var l := _label(t, 17, col, _fi)
	l.position = pos + Vector2(20, 0)
	padre.add_child(l)


## El retrato de la skin con el nivel encima (como en AMIGOS)
func _retrato(skin: int, nivel: int, pos: Vector2, padre: Control) -> void:
	var tam := Vector2(68, 68)
	_pintado(pos, tam, func(ci: Control):
		ci.draw_colored_polygon(_redondeada(Rect2(Vector2.ZERO, tam), 8.0), Color8(52, 122, 246))
		ci.draw_colored_polygon(_redondeada(Rect2(3, 3, tam.x - 6, tam.y - 6), 6.0), Color8(104, 178, 255)), padre)
	var skins: Array = load("res://scripts/lobby.gd").SKINS
	var sk: Dictionary = skins[clampi(skin, 0, skins.size() - 1)]
	var ruta := "res://avatar/retratos/%s.png" % String(sk["n"]).to_lower().replace(" ", "_")
	if ResourceLoader.exists(ruta):
		var recorte := Control.new()
		recorte.clip_contents = true
		recorte.position = pos + Vector2(3, 3)
		recorte.size = tam - Vector2(6, 6)
		recorte.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var at := AtlasTexture.new()
		at.atlas = load(ruta)
		at.region = Rect2(98, 6, 128, 128)
		var tr := TextureRect.new()
		tr.texture = at
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.size = recorte.size
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		recorte.add_child(tr)
		padre.add_child(recorte)
	var n := _label(str(nivel), 26, Color8(255, 210, 56), _fi)
	n.position = pos + Vector2(4, 34)
	n.add_theme_color_override("font_outline_color", Color8(40, 16, 70))
	n.add_theme_constant_override("outline_size", 7)
	padre.add_child(n)


# ==================================================================================================================
# PIEZAS
# ==================================================================================================================
func _label(t: String, tam: int, col: Color, f: Font) -> Label:
	var l := Label.new()
	l.text = t
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", col)
	return l


func _pintado(pos: Vector2, tam: Vector2, pintar: Callable, padre: Node) -> Control:
	var d := _Pintado.new()
	d.position = pos
	d.size = tam
	d.pintar = pintar
	padre.add_child(d)
	return d


func _boton_llano(r: Rect2, pintar: Callable, padre: Node) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.position = r.position
	b.size = r.size
	b.pivot_offset = r.size * 0.5
	for e in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(e, StyleBoxEmpty.new())
	padre.add_child(b)
	_pintado(Vector2.ZERO, r.size, pintar, b)
	b.button_down.connect(func(): b.scale = Vector2(0.95, 0.95))
	b.button_up.connect(func(): b.scale = Vector2.ONE)
	return b


## Los botones de las filas: inclinados, con su sombra (los de la captura)
func _boton_fila(r: Rect2, t: String, fondo: Color, col_txt: Color, padre: Node) -> Button:
	var b := _boton_llano(r, func(ci: Control):
		var rr := Rect2(Vector2.ZERO, ci.size)
		ci.draw_colored_polygon(_forma(rr.grow_individual(0, -4, 0, 4), 12.0), fondo.darkened(0.3))
		ci.draw_colored_polygon(_forma(Rect2(0, 0, rr.size.x, rr.size.y - 4), 12.0), fondo)
		ci.draw_colored_polygon(_forma(Rect2(3, 0, rr.size.x - 6, 9), 2.0), fondo.lightened(0.18))
		var tam := 24
		while tam > 14 and _fi.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x > rr.size.x - 34.0:
			tam -= 1
		var base := (rr.size.y - 4.0) * 0.5 + (_fi.get_ascent(tam) - _fi.get_descent(tam)) * 0.5
		if col_txt == Color.WHITE:
			ci.draw_string_outline(_fi, Vector2(0, base), t, HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, tam, 5, fondo.darkened(0.45))
		ci.draw_string(_fi, Vector2(0, base), t, HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, tam, col_txt), padre)
	return b


## EL HEXAGONO NARANJA de la franja (con la estrella del equipo)
func _pintar_hexagono(ci: Control) -> void:
	var c := ci.size * 0.5
	ci.draw_colored_polygon(_hex(c + Vector2(0, 3), 36.0), Color(0.5, 0.25, 0.0, 0.3))
	ci.draw_colored_polygon(_hex(c, 36.0), Color.WHITE)
	ci.draw_colored_polygon(_hex(c, 31.0), Color8(242, 150, 36))
	ci.draw_colored_polygon(_hex(c, 24.0), Color8(255, 190, 70))
	var est := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + i * PI / 5.0
		est.append(c + Vector2(cos(a), sin(a)) * (16.0 if i % 2 == 0 else 7.5))
	ci.draw_colored_polygon(est, Color.WHITE)


static func _hex(c: Vector2, r: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in 6:
		var a := PI / 6.0 + i * PI / 3.0
		p.append(c + Vector2(cos(a), sin(a)) * r)
	return p


static func _forma(r: Rect2, corte: float) -> PackedVector2Array:
	return PackedVector2Array([r.position + Vector2(corte, 0), Vector2(r.end.x, r.position.y), r.end - Vector2(corte, 0),
		Vector2(r.position.x, r.end.y)])


static func _redondeada(r: Rect2, radio: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	var esquinas := [[r.position + Vector2(radio, radio), PI], [Vector2(r.end.x - radio, r.position.y + radio), PI * 1.5],
		[r.end - Vector2(radio, radio), 0.0], [Vector2(r.position.x + radio, r.end.y - radio), PI * 0.5]]
	for e in esquinas:
		for i in 5:
			var a: float = float(e[1]) + i * PI * 0.5 / 4.0
			p.append((e[0] as Vector2) + Vector2(cos(a), sin(a)) * radio)
	return p


class _Pintado extends Control:
	var pintar: Callable

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if pintar.is_valid():
			pintar.call(self)
