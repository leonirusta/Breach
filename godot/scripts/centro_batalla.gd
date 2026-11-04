extends Control
## CENTRO: BATALLA (2026-09-28, pedido con captura). Lo abre JUGAR en el lobby: ya no se entra a la partida de
## golpe, primero se elige.
##
##   arriba      "CENTRO: BATALLA" y la linea de ayuda; a la derecha EQUIPO (con candado), AMIGOS EN LINEA y la X.
##   izquierda   la tarjeta grande de "AUN MAS MODOS" (proximamente, con candado).
##   centro      los modos en tarjetas de dos en dos: cabecera violeta con icono, titulo y tipo, y la portada
##               debajo. La elegida lleva el filo amarillo.
##   derecha     el modo elegido: sus mapas (tocar uno lo elige), que va a pasar, PARTIDA RAPIDA (cualquier
##               modo, con gente de verdad; si no hay, monta una) e IR A BATALLA (el modo y el mapa elegidos).
##
## El lobby (lobby.gd, _abrir_centro) le pasa los modos y como sacar sus mapas, y escucha `jugar(mapa)`, `rapida` y `cerrado`.
## Todo en unidades de diseño de 720 de alto (el proyecto estira canvas_items desde 1280x720).

signal jugar(mapa: String)
signal rapida
signal cerrado

const IconoLobby := preload("res://scripts/icono_lobby.gd")

const FONDO_A := Color(0.235, 0.19, 0.46)
const FONDO_B := Color(0.16, 0.12, 0.34)
const TARJETA := Color(0.33, 0.28, 0.70)
const CABECERA := Color(0.42, 0.37, 0.82)
const AMARILLO := Color(1.0, 0.88, 0.16)
const AMARILLO_TXT := Color(1.0, 0.84, 0.22)
const MAGENTA := Color(0.56, 0.2, 0.52)

## que es cada modo, en una linea (la cabecera de la tarjeta) y en dos (el panel de la derecha)
const TIPO := {
	"royale": "Solo o escuadra", "zombis": "Modo cooperativo", "bomba": "Modo de equipo",
	"duelo": "Equipos o todos", "atraco": "Tres equipos", "libre": "Sin objetivo",
}
## LOS SUBMODOS (2026-09-30, pedido: "en battle royale elegir SOLO o EQUIPO, y en duelo EQUIPOS o TODOS CONTRA TODOS"):
## dos tarjetas de color encima de los mapas. La elegida se guarda (Settings.sub_br / sub_dm) y es la que llevara la sala
## que montes (Net.room_sub). En el duelo, SOLO seria lo mismo que TODOS CONTRA TODOS: por eso no hay tercera.
const SUBMODOS := {
	"royale": [
		{"id": "solo", "titulo": "SOLO", "linea": "Todos contra todos", "color": Color(0.96, 0.46, 0.14), "dibujo": "uno",
			"texto": "Treinta jugadores caen en la isla y cada uno va a lo suyo. Busca armas, aguanta dentro de la zona y sé el último en pie."},
		{"id": "escuadra", "titulo": "ESCUADRA", "linea": "Hasta 4 · sin fuego amigo", "color": Color(0.08, 0.68, 0.86), "dibujo": "cuatro",
			"texto": "Escuadras de hasta cuatro: tu equipo va junto y, si vas solo, el juego te junta con otros. Entre compañeros no hay daño. Gana la última escuadra en pie."},
	],
	"duelo": [
		{"id": "equipos", "titulo": "EQUIPOS", "linea": "Naranja contra azul", "color": Color(0.24, 0.42, 0.96), "dibujo": "bandos",
			"texto": "Dos equipos a muerte, sin fuego amigo: el primero que llegue a las bajas se lleva la partida."},
		{"id": "todos", "titulo": "TODOS CONTRA TODOS", "linea": "Cada baja es tuya", "color": Color(0.9, 0.18, 0.44), "dibujo": "todos",
			"texto": "Todos contra todos: nadie es tu compañero y cada baja cuenta para ti. El primero que llegue a las bajas gana."},
		{"id": "eliminacion", "titulo": "ELIMINACIÓN", "linea": "Sin reaparecer · RCP", "color": Color(0.12, 0.66, 0.42), "dibujo": "bandos",
			"texto": "Dos equipos y nadie reaparece. Si cae un compañero, levántalo con RCP. Gana la ronda el equipo que elimine a todos; la partida, el primero que gane dos.", "solo_mapa": "cafeteria"},
		{"id": "ultimo", "titulo": "ÚLTIMO EN PIE", "linea": "Todos contra todos", "color": Color(0.62, 0.3, 0.92), "dibujo": "uno",
			"texto": "Todos contra todos y nadie reaparece. El último que quede vivo gana la partida.", "solo_mapa": "cafeteria"},
	],
}
const DESCRIPCION := {
	"royale": "Treinta jugadores caen en la isla. Busca armas, aguanta dentro de la zona y sé el último en pie.",
	"zombis": "Aguanta las oleadas en el puesto militar o juega la campaña cooperativa, episodio a episodio.",
	"bomba": "Un equipo planta la C4 en uno de los sitios y el otro tiene que desactivarla a tiempo.",
	"duelo": "Dos bandos a muerte: el primero que llegue a las bajas se lleva la partida.",
	"atraco": "Tres equipos y una caja fuerte: ábrela, llévate el botín y que no te lo quiten.",
	"libre": "Sin objetivo ni reloj: explora el mapa y derriba todo lo que quieras.",
}
const PORTADA_MODO := {
	"bomba": "res://assets/portada_bomba.png", "zombis": "res://assets/portada_cuarentena.png",
	"atraco": "res://assets/portada_atraco.png",
}

## lo que pone el lobby antes de añadirla (lobby.gd, _abrir_centro)
const ALTO_MIN_MODO := 150.0
var modos: Array = []               ## MODOS_LOBBY
var zombis_opciones: Array = []     ## ZOMBIS_OPCIONES: el orden y el nombre de los episodios
var mapas_de: Callable              ## modo -> mapas
var modo_de: Callable               ## mapa -> modo
var titulo_de: Callable             ## modo -> titulo
var icono_de: Callable              ## modo -> icono
var recordado: Dictionary = {}      ## modo -> ultimo mapa usado en el
var _modo := ""
var _mapa := ""
var _tarjetas: Dictionary = {}      ## id de modo -> Button
var _miniaturas: Dictionary = {}    ## mapa -> Button
var _titulo_modo: Label
var _desc: Label
var _rejilla: GridContainer
var _scroll: ScrollContainer
var _panel_der: Control
var _aviso: Label
var _aviso_t := 0.0
var _fuente: SystemFont
var _fuente_normal: SystemFont
var _fotos: Dictionary = {}
## ZOMBIS: que mapas se ven, los de la supervivencia (PVE: Cuarentena) o los de la CAMPAÑA (los episodios)
var _filtro_zombi := "pve"
var _filtros: Control
var _chips: Array = []
## LOS SUBMODOS del modo elegido (battle royale y duelo): las dos tarjetas
var _subfila: Control
var _subtarjetas: Array = []        ## [id, _TarjetaSub]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_fuente = preload("res://scripts/fuentes.gd").de(800, true)      # compartida: ver fuentes.gd
	_fuente_normal = preload("res://scripts/fuentes.gd").de(500, false)      # compartida: ver fuentes.gd
	var W := get_viewport_rect().size.x
	var H := get_viewport_rect().size.y

	# el fondo: violeta de arriba abajo y un panal de hexagonos muy tenue a la derecha
	var fondo := _Fondo.new()
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fondo)

	# --- arriba ---
	var t := _texto("CENTRO: BATALLA", 32, Color.WHITE, true)
	t.position = Vector2(40, 12)
	add_child(t)
	var st := _texto("Selecciona un modo para continuar la batalla", 16, Color(1, 1, 1, 0.9), false)
	st.position = Vector2(42, 54)
	add_child(st)
	_arriba_derecha(W)

	# --- la tarjeta grande de "aun mas modos" ---
	var y0 := 100.0
	var alto := H - y0 - 18.0
	var x := 40.0
	var grande := _tarjeta_proximamente(Vector2(226, alto))
	grande.position = Vector2(x, y0)
	add_child(grande)
	x += 226 + 10

	# --- los modos, de dos en dos ---
	var lista: Array = []
	for m in modos:
		# LIBRE NO SALE AQUI (2026-09-28, pedido): sus mapas son de pruebas y se juegan creando una sala LAN
		if bool(m.get("proximo", false)) or String(m["id"]) == "libre":
			continue
		if not (mapas_de.call(String(m["id"])) as Array).is_empty():
			lista.append(m)
	var filas := int(ceil(lista.size() / 2.0))
	# CON MUCHOS MODOS SE DESLIZA (2026-10-22, pedido): las tarjetas no bajan de ALTO_MIN_MODO; si no caben, la columna
	# se arrastra arriba y abajo (con el dedo o la rueda)
	var ah := maxf(ALTO_MIN_MODO, (alto - 10.0 * (filas - 1)) / maxf(1.0, filas))
	var aw := 250.0
	var col_modos := ScrollContainer.new()
	col_modos.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col_modos.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	col_modos.position = Vector2(x, y0)
	col_modos.size = Vector2(2 * aw + 10, alto)
	col_modos.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(col_modos)
	load("res://scripts/touch_scroll.gd").attach(col_modos)
	var hoja := Control.new()
	hoja.custom_minimum_size = Vector2(2 * aw + 10, filas * (ah + 10) - 10)
	hoja.mouse_filter = Control.MOUSE_FILTER_PASS
	col_modos.add_child(hoja)
	for i in lista.size():
		var m: Dictionary = lista[i]
		var c := _tarjeta_modo(m, Vector2(aw, ah))
		c.position = Vector2((i % 2) * (aw + 10), (i / 2) * (ah + 10))
		# la que se queda sola en la ultima fila, centrada entre las dos columnas
		if i == lista.size() - 1 and lista.size() % 2 == 1:
			c.position.x = (aw + 10) * 0.5
		hoja.add_child(c)
		_tarjetas[String(m["id"])] = c
		_entrada(c, 0.05 + 0.06 * i)
	_entrada(grande, 0.02)
	var xd := x + 2 * aw + 10 + 14
	var linea := ColorRect.new()
	linea.color = Color(1, 1, 1, 0.12)
	linea.position = Vector2(xd - 7, y0)
	linea.size = Vector2(2, alto)
	linea.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(linea)

	# --- la derecha: el modo elegido ---
	_panel_der = Control.new()
	_panel_der.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_der.position = Vector2(xd, y0 - 6)
	_panel_der.size = Vector2(W - xd - 24, alto + 6)
	add_child(_panel_der)
	_montar_derecha()

	_aviso = _texto("", 18, AMARILLO_TXT, true)
	_aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aviso.size = Vector2(W, 30)
	_aviso.position = Vector2(0, H - 50)
	_aviso.modulate.a = 0.0
	add_child(_aviso)

	# el modo con que se abre: el del mapa que tienes elegido
	var actual: String = modo_de.call(Settings.map)
	if (not _tarjetas.has(actual) or not load("res://scripts/lobby.gd").modo_abierto(actual)) and not lista.is_empty():
		actual = String(lista[0]["id"])
		for mm in lista:
			if not mm.has("nivel_req"):
				actual = String(mm["id"])
				break
	_elegir_modo(actual, false)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)
	Audio.ui("submenu_abre", -8.0)


func _process(dt: float) -> void:
	_amigos_reloj += dt
	if _amigos_reloj >= 15.0:
		_amigos_reloj = 0.0
		_pedir_amigos()
	if _aviso_t > 0.0:
		_aviso_t -= dt
		_aviso.modulate.a = clampf(_aviso_t / 0.4, 0.0, 1.0)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		_cerrar()
		get_viewport().set_input_as_handled()


func avisar(txt: String) -> void:
	_aviso.text = txt
	_aviso_t = 2.2
	_aviso.modulate.a = 1.0


func _cerrar() -> void:
	Audio.ui("submenu_cierra", -8.0)
	cerrado.emit()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.14)
	tw.tween_callback(queue_free)


# ------------------------------------------------------------------ piezas
func _texto(txt: String, tam: int, col: Color, gorda: bool) -> Label:
	var l := Label.new()
	l.text = txt
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", _fuente if gorda else _fuente_normal)
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0.05, 0.02, 0.18, 0.45))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 4)
	return l


func _caja(col: Color, borde: Color = Color.TRANSPARENT, grosor: int = 0, brillo: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_border_width_all(grosor)
	s.border_color = borde
	s.set_corner_radius_all(3)
	if brillo > 0:
		s.shadow_color = Color(borde, 0.55)
		s.shadow_size = brillo
	return s


## Un boton sin nada: el dibujo lo ponen sus hijos. Suena al pasar.
func _boton(tam: Vector2) -> Button:
	var b := Button.new()
	b.custom_minimum_size = tam
	b.size = tam
	b.focus_mode = Control.FOCUS_NONE
	for e in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(e, StyleBoxEmpty.new())
	b.mouse_entered.connect(func(): Audio.ui("pasar", -14.0))
	return b


## La portada: una foto que cubre el hueco o, si no la hay, un degradado del color con el icono del modo.
func _portada(ruta: String, tam: Vector2, col: Color, icono: String, texto: String = "") -> Control:
	var c := Control.new()
	c.size = tam
	c.clip_contents = true
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex: Texture2D = null
	if ruta != "" and ResourceLoader.exists(ruta):
		if not _fotos.has(ruta):
			_fotos[ruta] = load(ruta)
		tex = _fotos[ruta]
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.size = tam
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(tr)
	else:
		var g := Gradient.new()
		g.colors = PackedColorArray([col.lightened(0.25), col.darkened(0.45)])
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.35)
		gt.fill_to = Vector2(1.1, 1.1)
		var tr2 := TextureRect.new()
		tr2.texture = gt
		tr2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr2.stretch_mode = TextureRect.STRETCH_SCALE
		tr2.size = tam
		tr2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(tr2)
		var ic = IconoLobby.new()
		ic.icono = icono
		ic.color = Color(1, 1, 1, 0.85)
		var lado := minf(tam.x, tam.y) * 0.46
		ic.size = Vector2(lado, lado)
		ic.position = Vector2((tam.x - lado) * 0.5, (tam.y - lado) * 0.5 - (8.0 if texto != "" else 0.0))
		c.add_child(ic)
	return c


func _foto_de_mapa(m: String) -> String:
	for ext in ["png", "webp", "jpg", "jpeg"]:
		var r := "res://assets/mapas/%s.%s" % [m, ext]
		if ResourceLoader.exists(r):
			return r
	return ""


func _foto_de_modo(id: String) -> String:
	if PORTADA_MODO.has(id):
		return String(PORTADA_MODO[id])
	for m in mapas_de.call(id):
		var r := _foto_de_mapa(String(m))
		if r != "":
			return r
	return ""


func _entrada(c: Control, retraso: float) -> void:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(0.9, 0.9)
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "scale", Vector2.ONE, 0.28).set_delay(retraso).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, 0.18).set_delay(retraso)


# ------------------------------------------------------------------ arriba a la derecha
func _arriba_derecha(W: float) -> void:
	# la X
	var x := _boton(Vector2(70, 58))
	x.position = Vector2(W - 70, 0)
	x.pressed.connect(_cerrar)
	var fx := Panel.new()
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.add_theme_stylebox_override("panel", _caja(MAGENTA))
	fx.size = x.size
	x.add_child(fx)
	var lx := _texto("X", 30, Color.WHITE, true)
	lx.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lx.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lx.size = x.size
	x.add_child(lx)
	x.mouse_entered.connect(func(): fx.add_theme_stylebox_override("panel", _caja(MAGENTA.lightened(0.15))))
	x.mouse_exited.connect(func(): fx.add_theme_stylebox_override("panel", _caja(MAGENTA)))
	add_child(x)
	# amigos en linea
	var am := Panel.new()
	am.mouse_filter = Control.MOUSE_FILTER_IGNORE
	am.add_theme_stylebox_override("panel", _caja(Color(0.19, 0.15, 0.38, 0.95)))
	am.position = Vector2(W - 70 - 286, 0)
	am.size = Vector2(286, 58)
	add_child(am)
	var a1 := _texto("AMIGOS EN LÍNEA (0)", 14, Color.WHITE, true)
	_amigos_t1 = a1
	a1.position = Vector2(14, 6)
	am.add_child(a1)
	var a2 := _texto("Agrega amigos para formar equipo\ncuando quieras", 11, Color(1, 1, 1, 0.85), true)
	a2.add_theme_constant_override("line_spacing", -3)
	a2.position = Vector2(14, 25)
	am.add_child(a2)
	_amigos_t2 = a2
	_pedir_amigos()
	# EQUIPO, con su candado
	var eq := _boton(Vector2(66, 58))
	eq.position = Vector2(W - 70 - 286 - 76, 10)
	var fe := Panel.new()
	fe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fe.add_theme_stylebox_override("panel", _caja(Color(0.40, 0.38, 0.56)))
	fe.size = eq.size
	eq.add_child(fe)
	var mas := _texto("+", 34, Color.WHITE, true)
	mas.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mas.size = Vector2(66, 36)
	mas.position = Vector2(0, -6)
	eq.add_child(mas)
	var le := _texto("EQUIPO", 12, Color.WHITE, true)
	le.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	le.size = Vector2(66, 18)
	le.position = Vector2(0, 36)
	eq.add_child(le)
	# FORMAR EQUIPO (2026-10-24, pedido: "en CENTRO: BATALLA dice proximamente y en el lobby si funciona"): la misma
	# ventana que la tecla EQUIPO del lobby (lobby_grupo.abrir), por encima de esta pantalla
	eq.pressed.connect(_abrir_equipo)
	add_child(eq)


# ------------------------------------------------------------------ equipo y amigos
var _amigos_t1: Label = null
var _amigos_t2: Label = null
var _http_amigos: HTTPRequest = null
var _amigos_reloj := 0.0

func _abrir_equipo() -> void:
	Audio.ui("click", -8.0)
	var lob = get_tree().get_first_node_in_group("lobby")
	if lob == null:
		lob = get_tree().current_scene
	var g = lob.get("_grupo") if lob != null else null
	if g == null or not is_instance_valid(g) or not g.has_method("abrir"):
		avisar("EQUIPO · ábrelo desde el vestíbulo")
		return
	var pop = g.abrir()
	if pop is CanvasLayer:
		(pop as CanvasLayer).layer = 70          # por encima de CENTRO: BATALLA (66)


## AMIGOS EN LINEA de verdad (GET /amigos; el servidor sabe quien esta conectado por el latido, cada 20 s), y se
## vuelve a pedir cada 15 s mientras esta pantalla siga abierta
func _pedir_amigos() -> void:
	if not Cuenta.conectado():
		return
	if _http_amigos == null:
		_http_amigos = HTTPRequest.new()
		_http_amigos.timeout = 8.0
		add_child(_http_amigos)
		_http_amigos.request_completed.connect(_al_llegar_amigos)
	if _http_amigos.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_http_amigos.request(Cuenta.url + "/amigos", PackedStringArray(["Authorization: Bearer " + Cuenta.token]), HTTPClient.METHOD_GET)


func _al_llegar_amigos(_r: int, codigo: int, _c: PackedStringArray, cuerpo: PackedByteArray) -> void:
	if codigo != 200 or not is_instance_valid(_amigos_t1):
		return
	var j = JSON.parse_string(cuerpo.get_string_from_utf8())
	if not (j is Dictionary):
		return
	var n := 0
	var nombres: Array = []
	for a in (j as Dictionary).get("amigos", []):
		if a is Dictionary and String(a.get("estado", "desconectado")) != "desconectado":
			n += 1
			if nombres.size() < 2:
				nombres.append(String(a.get("nombre", "")))
	_amigos_t1.text = "AMIGOS EN LÍNEA (%d)" % n
	if n > 0:
		_amigos_t2.text = ", ".join(nombres) + (" y %d más" % (n - nombres.size()) if n > nombres.size() else "") + "
toca EQUIPO para invitarlos"
	else:
		_amigos_t2.text = "Agrega amigos para formar equipo
cuando quieras"


# ------------------------------------------------------------------ tarjetas
func _cabecera(tam_x: float, icono: String, titulo: String, sub: String) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = Vector2(tam_x, 50)
	var ic = IconoLobby.new()
	ic.icono = icono
	ic.color = Color.WHITE
	ic.size = Vector2(34, 34)
	ic.position = Vector2(10, 8)
	c.add_child(ic)
	var t := _texto(titulo, 19, Color.WHITE, true)
	t.position = Vector2(52, 2)
	t.size = Vector2(tam_x - 58, 26)
	t.clip_text = true
	c.add_child(t)
	# que quepa: se encoge si el titulo es largo
	var tt := 19
	while tt > 12 and _fuente.get_string_size(titulo, HORIZONTAL_ALIGNMENT_LEFT, -1, tt).x > tam_x - 60:
		tt -= 1
	t.add_theme_font_size_override("font_size", tt)
	var s := _texto(sub, 13, AMARILLO_TXT, true)
	s.position = Vector2(52, 26)
	c.add_child(s)
	return c


## LA IMAGEN DE CADA MODO (2026-09-28, del usuario: assets/modos/<id>.png, recortadas de su lamina de logos).
## Trae el nombre del modo dibujado abajo, asi que la tarjeta es la imagen entera; sin imagen (LIBRE), la de antes.
func _imagen_modo(id: String) -> String:
	var r := "res://assets/modos/%s.png" % id
	return r if ResourceLoader.exists(r) else ""


func _tarjeta_modo(m: Dictionary, tam: Vector2) -> Button:
	var b := _tarjeta_modo_base(m, tam)
	# CERRADO POR NIVEL (2026-10-18): velo oscuro, candado y el nivel; tocarla solo avisa
	if m.has("nivel_req"):
		var n := int(m["nivel_req"])
		for con in b.pressed.get_connections():
			b.pressed.disconnect(con["callable"])
		var velo := ColorRect.new()
		velo.color = Color(0.02, 0.01, 0.06, 0.68)
		velo.position = Vector2(4, 4)
		velo.size = tam - Vector2(8, 8)
		velo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(velo)
		var lt := _texto("🔒 NIVEL %d" % n, 24, AMARILLO_TXT, true)
		lt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lt.size = Vector2(tam.x, 34)
		lt.position = Vector2(0, tam.y * 0.5 - 17)
		b.add_child(lt)
		var titulo := String(m.get("titulo", m["id"]))
		b.pressed.connect(func():
			Audio.ui("aviso", -6.0)
			avisar("%s se desbloquea al nivel %d de la cuenta" % [titulo, n]))
	return b


func _tarjeta_modo_base(m: Dictionary, tam: Vector2) -> Button:
	var id := String(m["id"])
	var b := _boton(tam)
	var fondo := Panel.new()
	fondo.name = "Fondo"
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fondo.size = tam
	b.add_child(fondo)
	var img := _imagen_modo(id)
	if img != "":
		# la imagen llena la tarjeta, pegada ABAJO (ahi esta el logo con el nombre): se recorta el cielo
		var marco := Control.new()
		marco.clip_contents = true
		marco.position = Vector2(4, 4)
		marco.size = tam - Vector2(8, 8)
		marco.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(marco)
		var tex: Texture2D = load(img)
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		# LA IMAGEN ESTIRADA A LA TARJETA (2026-10-13, pedido: "que se adapte al contenedor, que ocupe todo el espacio"):
		# entera y sin recortar, ocupando todo el hueco
		tr.size = marco.size
		tr.position = Vector2.ZERO
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marco.add_child(tr)
		# el tipo de modo, en una etiqueta arriba a la izquierda
		var tipo := String(TIPO.get(id, ""))
		if tipo != "":
			var chip := ColorRect.new()
			chip.color = Color(0.06, 0.03, 0.16, 0.72)
			var ancho_chip := _fuente.get_string_size(tipo, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 18.0
			chip.position = Vector2(4, 4)
			chip.size = Vector2(ancho_chip, 22)
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(chip)
			var lt := _texto(tipo, 13, AMARILLO_TXT, true)
			lt.position = Vector2(12, 5)
			b.add_child(lt)
		var velo_i := ColorRect.new()
		velo_i.name = "Velo"
		velo_i.color = Color(0.1, 0.05, 0.3, 0.28)
		velo_i.mouse_filter = Control.MOUSE_FILTER_IGNORE
		velo_i.position = Vector2(4, 4)
		velo_i.size = tam - Vector2(8, 8)
		b.add_child(velo_i)
		b.mouse_entered.connect(func(): velo_i.color.a = 0.0 if id == _modo else 0.08)
		b.mouse_exited.connect(func(): velo_i.color.a = 0.0 if id == _modo else 0.28)
		b.pressed.connect(func(): _elegir_modo(id, true))
		return b
	var cab_f := ColorRect.new()
	cab_f.name = "CabF"
	cab_f.color = CABECERA
	cab_f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cab_f.position = Vector2(4, 4)
	cab_f.size = Vector2(tam.x - 8, 50)
	b.add_child(cab_f)
	b.add_child(_cabecera(tam.x, String(m["icono"]), String(m["titulo"]), String(TIPO.get(id, ""))))
	var p := _portada(_foto_de_modo(id), Vector2(tam.x - 8, tam.y - 58), TARJETA, String(m["icono"]))
	p.position = Vector2(4, 54)
	b.add_child(p)
	# un velo que se levanta al pasar el raton
	var velo := ColorRect.new()
	velo.name = "Velo"
	velo.color = Color(0.1, 0.05, 0.3, 0.28)
	velo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	velo.position = p.position
	velo.size = p.size
	b.add_child(velo)
	b.mouse_entered.connect(func(): velo.color.a = 0.0 if id == _modo else 0.08)
	b.mouse_exited.connect(func(): velo.color.a = 0.0 if id == _modo else 0.28)
	b.pressed.connect(func(): _elegir_modo(id, true))
	return b


func _pintar_tarjetas() -> void:
	for id in _tarjetas:
		var b: Button = _tarjetas[id]
		var sel: bool = id == _modo
		(b.get_node("Fondo") as Panel).add_theme_stylebox_override("panel",
			_caja(TARJETA, AMARILLO, 4, 6) if sel else _caja(TARJETA))
		var cab := b.get_node_or_null("CabF") as ColorRect
		if cab:
			cab.color = CABECERA.lightened(0.12) if sel else CABECERA
		(b.get_node("Velo") as ColorRect).color.a = 0.0 if sel else 0.28
		b.z_index = 1 if sel else 0


func _tarjeta_proximamente(tam: Vector2) -> Control:
	var c := Control.new()
	c.size = tam
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fondo := Panel.new()
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fondo.add_theme_stylebox_override("panel", _caja(TARJETA))
	fondo.size = tam
	c.add_child(fondo)
	var cab_f := ColorRect.new()
	cab_f.color = CABECERA
	cab_f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cab_f.position = Vector2(4, 4)
	cab_f.size = Vector2(tam.x - 8, 50)
	c.add_child(cab_f)
	c.add_child(_cabecera(tam.x, "salas", "AÚN MÁS MODOS", "Próximamente"))
	var cuerpo := _Proximamente.new()
	cuerpo.position = Vector2(4, 54)
	cuerpo.size = Vector2(tam.x - 8, tam.y - 58)
	c.add_child(cuerpo)
	var cand := _Candado.new()
	cand.size = Vector2(40, 40)
	cand.position = Vector2(tam.x * 0.5 - 20, tam.y * 0.5 - 16)
	c.add_child(cand)
	var t := _texto("PRÓXIMAMENTE", 20, Color.WHITE, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size = Vector2(tam.x, 30)
	t.position = Vector2(0, tam.y * 0.5 + 30)
	c.add_child(t)
	return c


# ------------------------------------------------------------------ la derecha
func _montar_derecha() -> void:
	var w := _panel_der.size.x
	_titulo_modo = _texto("", 26, Color.WHITE, true)
	_titulo_modo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_titulo_modo.size = Vector2(w, 40)
	_titulo_modo.position = Vector2(0, 0)
	_panel_der.add_child(_titulo_modo)
	# LOS FILTROS DE ZOMBIS (solo se ven en ese modo): PVE y CAMPAÑA
	_filtros = Control.new()
	_filtros.position = Vector2(0, 44)
	_filtros.size = Vector2(w, 38)
	_filtros.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_der.add_child(_filtros)
	var ancho_chip := (w - 10.0) * 0.5
	for i in 2:
		var clave: String = ["pve", "campana"][i]
		var chip := _boton(Vector2(ancho_chip, 36))
		chip.position = Vector2(i * (ancho_chip + 10.0), 0)
		var f := Panel.new()
		f.name = "F"
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		f.size = chip.size
		chip.add_child(f)
		var l := _texto(["PVE", "CAMPAÑA"][i], 17, Color.WHITE, true)
		l.name = "L"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size = chip.size
		chip.add_child(l)
		chip.pressed.connect(func():
			if _filtro_zombi == clave:
				return
			Audio.ui("aceptar", -8.0)
			_filtro_zombi = clave
			_elegir_modo("zombis", false, false))
		_filtros.add_child(chip)
		_chips.append([clave, f, l])
	# LOS SUBMODOS (battle royale y duelo): dos tarjetas de color en el mismo hueco que los filtros de zombis
	_subfila = Control.new()
	_subfila.position = Vector2(0, 44)
	_subfila.size = Vector2(w, 74)
	_subfila.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subfila.visible = false
	_panel_der.add_child(_subfila)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.position = Vector2(0, 46)
	_scroll.size = Vector2(w, 262)
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel_der.add_child(_scroll)
	load("res://scripts/touch_scroll.gd").attach(_scroll)    # deslizar con el dedo no elige mapa
	_rejilla = GridContainer.new()
	_rejilla.columns = 2
	_rejilla.add_theme_constant_override("h_separation", 8)
	_rejilla.add_theme_constant_override("v_separation", 8)
	_scroll.add_child(_rejilla)
	_desc = _texto("", 15, Color(1, 1, 1, 0.92), false)
	_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.size = Vector2(w - 20, 70)
	_desc.position = Vector2(10, 318)
	_panel_der.add_child(_desc)
	# PARTIDA RAPIDA: cualquier modo, con gente de verdad (si no hay nadie, monta una)
	var r := _boton(Vector2(minf(300, w - 20), 44))
	r.position = Vector2((w - r.size.x) * 0.5, _panel_der.size.y - 134)
	var fr := Panel.new()
	fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fr.add_theme_stylebox_override("panel", _inclinado(Color(0.28, 0.22, 0.6, 0.9), Color(1, 1, 1, 0.55), 2))
	fr.size = r.size
	r.add_child(fr)
	var lr := _texto("PARTIDA RÁPIDA", 19, Color.WHITE, true)
	lr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lr.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lr.size = r.size
	r.add_child(lr)
	r.mouse_entered.connect(func(): fr.add_theme_stylebox_override("panel", _inclinado(Color(0.36, 0.3, 0.72, 0.95), Color(1, 1, 1, 0.9), 2)))
	r.mouse_exited.connect(func(): fr.add_theme_stylebox_override("panel", _inclinado(Color(0.28, 0.22, 0.6, 0.9), Color(1, 1, 1, 0.55), 2)))
	r.pressed.connect(func(): Audio.ui("aceptar", -5.0); rapida.emit())
	_panel_der.add_child(r)
	# IR A BATALLA: el modo y el mapa elegidos
	var ir := _boton(Vector2(minf(320, w - 20), 66))
	ir.position = Vector2((w - ir.size.x) * 0.5, _panel_der.size.y - 78)
	var fi := Panel.new()
	fi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fi.add_theme_stylebox_override("panel", _inclinado(AMARILLO, Color(0.75, 0.55, 0.0), 0, true))
	fi.size = ir.size
	ir.add_child(fi)
	var li := _texto("IR A BATALLA", 30, Color(0.1, 0.08, 0.2), true)
	li.remove_theme_color_override("font_shadow_color")
	li.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	li.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	li.size = ir.size
	ir.add_child(li)
	ir.pivot_offset = ir.size * 0.5
	ir.mouse_entered.connect(func(): fi.add_theme_stylebox_override("panel", _inclinado(AMARILLO.lightened(0.18), Color(0.75, 0.55, 0.0), 0, true)))
	ir.mouse_exited.connect(func(): fi.add_theme_stylebox_override("panel", _inclinado(AMARILLO, Color(0.75, 0.55, 0.0), 0, true)))
	ir.pressed.connect(_ir_a_batalla)
	var lat := ir.create_tween().set_loops()
	lat.tween_property(ir, "scale", Vector2(1.035, 1.035), 0.9).set_trans(Tween.TRANS_SINE)
	lat.tween_property(ir, "scale", Vector2.ONE, 0.9).set_trans(Tween.TRANS_SINE)
	_panel_der.add_child(ir)


## Caja inclinada como la letra (y con la sombra de abajo en el amarillo, como un boton de verdad).
func _inclinado(col: Color, borde: Color, grosor: int, sombra: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_border_width_all(grosor)
	s.border_color = borde
	s.set_corner_radius_all(3)
	s.skew = Vector2(-0.16, 0.0)
	if sombra:
		s.border_width_bottom = 5
		s.border_color = borde
		s.shadow_color = Color(0, 0, 0, 0.3)
		s.shadow_size = 4
		s.shadow_offset = Vector2(0, 3)
	return s


func _elegir_modo(id: String, con_sonido: bool, animar := true) -> void:
	if con_sonido:
		Audio.ui("aceptar", -6.0)
	var nuevo := id != _modo
	_modo = id
	_pintar_tarjetas()
	_titulo_modo.text = String(titulo_de.call(id))
	_desc.text = String(DESCRIPCION.get(id, ""))
	# ZOMBIS: la barra de filtros; al entrar al modo, el filtro del mapa que tengas elegido
	var zombi := id == "zombis"
	_filtros.visible = zombi
	_scroll.position.y = 88.0 if zombi else 46.0
	if zombi and nuevo:
		_filtro_zombi = "campana" if String(Settings.map).begins_with("campana_") else "pve"
	if zombi:
		for c in _chips:
			var activo: bool = c[0] == _filtro_zombi
			(c[1] as Panel).add_theme_stylebox_override("panel", _inclinado(AMARILLO if activo else Color(0.28, 0.22, 0.6, 0.9),
				Color(1, 1, 1, 0.0 if activo else 0.4), 0 if activo else 2))
			(c[2] as Label).add_theme_color_override("font_color", Color(0.12, 0.08, 0.24) if activo else Color.WHITE)
		_desc.text = "Aguanta las oleadas en el puesto militar: la supervivencia de siempre." if _filtro_zombi == "pve" \
			else "La campaña cooperativa, episodio a episodio: cada uno se abre al terminar el anterior."
	# BATTLE ROYALE Y DUELO: las dos tarjetas del submodo (SOLO / ESCUADRA, EQUIPOS / TODOS CONTRA TODOS)
	var subs: Array = SUBMODOS.get(id, [])
	_subfila.visible = not subs.is_empty()
	if not subs.is_empty():
		_montar_submodos(id)
		_scroll.position.y = 128.0
		_desc.text = _texto_submodo(id)
	# el mapa: el que tenias en este modo, el ultimo que usaste en el, o el primero que se pueda jugar
	var mapas := _mapas_ordenados(id)
	if zombi:
		mapas = mapas.filter(func(mm): return String(mm).begins_with("campana_") == (_filtro_zombi == "campana"))
	var m := ""
	if modo_de.call(Settings.map) == id and Settings.map in mapas:
		m = Settings.map
	elif recordado.has(id) and String(recordado[id]) in mapas:
		m = String(recordado[id])
	else:
		for mm in mapas:
			if Settings.campana_desbloqueada(String(mm)):
				m = String(mm)
				break
	_mapa = m
	_llenar_mapas(mapas)
	if not animar:
		return
	# el panel entra de nuevo, suave, para que se note el cambio
	_panel_der.modulate.a = 0.0
	_panel_der.position.x += 16
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel_der, "modulate:a", 1.0, 0.2)
	tw.tween_property(_panel_der, "position:x", _panel_der.position.x - 16, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## ------------------------------------------------------------------ los submodos
## El submodo que tienes elegido en `modo` (el de tus ajustes; el primero si no vale)
func submodo_de(modo: String) -> String:
	var subs: Array = SUBMODOS.get(modo, []).filter(func(x): return not TiendaAjustes.bloqueado("modos", "%s:%s" % [modo, String(x["id"])]))
	if subs.is_empty():
		return ""
	var mio: String = Settings.sub_br if modo == "royale" else Settings.sub_dm
	for s in subs:
		if String(s["id"]) == mio:
			return mio
	return String(subs[0]["id"])


func _texto_submodo(modo: String) -> String:
	var sub := submodo_de(modo)
	for s in SUBMODOS.get(modo, []):
		if String(s["id"]) == sub:
			return String(s["texto"])
	return String(DESCRIPCION.get(modo, ""))


## Las dos tarjetas del modo, una al lado de la otra. Se rehacen al cambiar de modo; al elegir solo se repintan.
func _montar_submodos(modo: String) -> void:
	for c in _subfila.get_children():
		c.queue_free()
	_subtarjetas.clear()
	var subs: Array = SUBMODOS.get(modo, []).filter(func(x): return not TiendaAjustes.bloqueado("modos", "%s:%s" % [modo, String(x["id"])]))
	var hueco := 10.0
	var ancho := (_subfila.size.x - hueco * (subs.size() - 1)) / maxf(1.0, subs.size())
	var elegido := submodo_de(modo)
	for i in subs.size():
		var s: Dictionary = subs[i]
		var sid := String(s["id"])
		var b := _boton(Vector2(ancho, _subfila.size.y))
		b.position = Vector2(i * (ancho + hueco), 0)
		var t := _TarjetaSub.new()
		t.size = b.size
		t.color = s["color"]
		t.titulo = String(s["titulo"])
		t.linea = String(s["linea"])
		t.dibujo = String(s["dibujo"])
		t.elegida = sid == elegido
		t.fuerte = _fuente
		t.normal = _fuente_normal
		b.add_child(t)
		b.mouse_entered.connect(func(): t.encima = true; t.queue_redraw())
		b.mouse_exited.connect(func(): t.encima = false; t.queue_redraw())
		b.pressed.connect(func(): _elegir_submodo(modo, sid))
		_subfila.add_child(b)
		_subtarjetas.append([sid, t])
		_entrada(b, 0.04 + 0.05 * i)


func _elegir_submodo(modo: String, sid: String) -> void:
	if submodo_de(modo) == sid:
		return
	Audio.ui("aceptar", -6.0)
	if modo == "royale":
		Settings.sub_br = sid
	else:
		Settings.sub_dm = sid
	Settings.save()
	for par in _subtarjetas:
		var t: _TarjetaSub = par[1]
		t.elegida = String(par[0]) == sid
		t.queue_redraw()
		if t.elegida:
			# un saltito de la elegida
			var b := t.get_parent() as Control
			b.pivot_offset = b.size * 0.5
			b.scale = Vector2(0.94, 0.94)
			b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_desc.text = _texto_submodo(modo)


## Los mapas del modo, y en zombis en el orden de la ventana de siempre: la supervivencia y los episodios.
func _mapas_ordenados(id: String) -> Array:
	var mapas: Array = mapas_de.call(id)
	if id != "zombis":
		return mapas
	var out: Array = []
	for op in zombis_opciones:
		if String(op["mapa"]) in mapas:
			out.append(String(op["mapa"]))
	for m in mapas:
		if not (m in out):
			out.append(m)
	return out


func _llenar_mapas(mapas: Array) -> void:
	for c in _rejilla.get_children():
		c.queue_free()
	_miniaturas.clear()
	var w := (_scroll.size.x - 8.0) * 0.5
	var tam := Vector2(w, 124)
	for i in mapas.size():
		var m := String(mapas[i])
		var b := _miniatura(m, tam)
		_rejilla.add_child(b)
		_miniaturas[m] = b
	_scroll.scroll_vertical = 0
	var filas := int(ceil(mapas.size() / 2.0))
	_scroll.size.y = minf(262.0, filas * 124.0 + maxf(0.0, filas - 1) * 8.0)
	_desc.position.y = _scroll.position.y + _scroll.size.y + 18.0
	_pintar_miniaturas()


func _episodio(m: String) -> String:
	for op in zombis_opciones:
		if String(op["mapa"]) == m:
			return String(op["titulo"])
	return ""


func _miniatura(m: String, tam: Vector2) -> Button:
	var b := _boton(tam)
	var cerrada := not Settings.campana_desbloqueada(m)
	var marco := Panel.new()
	marco.name = "Marco"
	marco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marco.size = tam
	b.add_child(marco)
	var p := _portada(_foto_de_mapa(m), tam - Vector2(6, 6), TARJETA.darkened(0.1), String(icono_de.call(_modo)), "x")
	p.position = Vector2(3, 3)
	b.add_child(p)
	# el nombre sobre una franja oscura abajo
	var franja := ColorRect.new()
	franja.color = Color(0.06, 0.03, 0.18, 0.72)
	franja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	franja.position = Vector2(3, tam.y - 31)
	franja.size = Vector2(tam.x - 6, 28)
	b.add_child(franja)
	var n := _texto(Settings.map_title(m).to_upper(), 15, Color.WHITE, true)
	n.position = Vector2(10, tam.y - 30)
	n.size = Vector2(tam.x - 18, 26)
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_child(n)
	var ep := _episodio(m)
	if ep != "":
		var e := _texto(ep, 11, AMARILLO_TXT, true)
		var fe := ColorRect.new()
		fe.color = Color(0.06, 0.03, 0.18, 0.72)
		fe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fe.position = Vector2(3, 3)
		fe.size = Vector2(_fuente.get_string_size(ep, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 14, 20)
		b.add_child(fe)
		e.position = Vector2(9, 3)
		b.add_child(e)
	if cerrada:
		var gris := ColorRect.new()
		gris.color = Color(0.08, 0.06, 0.16, 0.66)
		gris.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gris.position = Vector2(3, 3)
		gris.size = tam - Vector2(6, 6)
		b.add_child(gris)
		var cand := _Candado.new()
		cand.size = Vector2(30, 30)
		cand.position = Vector2(tam.x * 0.5 - 15, tam.y * 0.5 - 30)
		b.add_child(cand)
	b.pressed.connect(func():
		if cerrada:
			Audio.ui("atras", -6.0)
			avisar("Completa el episodio anterior para desbloquear este")
			return
		Audio.ui("aceptar", -8.0)
		_mapa = m
		_pintar_miniaturas())
	return b


func _pintar_miniaturas() -> void:
	for m in _miniaturas:
		var b: Button = _miniaturas[m]
		var sel: bool = m == _mapa
		(b.get_node("Marco") as Panel).add_theme_stylebox_override("panel",
			_caja(Color(0.2, 0.16, 0.42), AMARILLO, 3, 4) if sel else _caja(Color(0.2, 0.16, 0.42), Color(1, 1, 1, 0.18), 1))


func _ir_a_batalla() -> void:
	if _mapa == "":
		Audio.ui("atras", -6.0)
		avisar("Elige un mapa")
		return
	Audio.ui("aceptar", -3.0)
	jugar.emit(_mapa)


# ------------------------------------------------------------------ dibujos
## El fondo: degradado violeta y un panal tenue a la derecha, como en la captura.
class _Fondo extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var s := size
		var arriba := Color(0.235, 0.19, 0.46)
		var abajo := Color(0.15, 0.11, 0.32)
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]),
			PackedColorArray([arriba, arriba, abajo, abajo]))
		var r := 34.0
		var dx := r * 1.732
		var fila := 0
		var y := -r
		while y < s.y + r:
			var x := s.x * 0.55 + (dx * 0.5 if fila % 2 == 1 else 0.0)
			while x < s.x + dx:
				var a := clampf((x - s.x * 0.55) / (s.x * 0.45), 0.0, 1.0) * 0.06
				var pts := PackedVector2Array()
				for k in 7:
					var ang := deg_to_rad(60.0 * k + 30.0)
					pts.append(Vector2(x, y) + Vector2(cos(ang), sin(ang)) * r)
				draw_polyline(pts, Color(1, 1, 1, a), 2.0, true)
				x += dx
			y += r * 1.5
			fila += 1


## El cuerpo de "aun mas modos": violeta que vira a magenta y cuadraditos de pixel sueltos (sin figuras: pedido).
class _Proximamente extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
	func _draw() -> void:
		var s := size
		# degradado radial: un abanico con el centro claro y el borde oscuro
		var centro := Vector2(s.x * 0.5, s.y * 0.3)
		var claro := Color(0.58, 0.24, 0.78)
		var oscuro := Color(0.2, 0.11, 0.42)
		var bordes := PackedVector2Array([Vector2.ZERO, Vector2(s.x * 0.5, 0), Vector2(s.x, 0), Vector2(s.x, s.y * 0.5),
			s, Vector2(s.x * 0.5, s.y), Vector2(0, s.y), Vector2(0, s.y * 0.5), Vector2.ZERO])
		for i in bordes.size() - 1:
			draw_polygon(PackedVector2Array([centro, bordes[i], bordes[i + 1]]), PackedColorArray([claro, oscuro, oscuro]))
		# cuadraditos sueltos, como si se deshiciera en pixeles
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 40:
			var p := Vector2(rng.randf() * s.x, rng.randf() * s.y)
			var l := rng.randf_range(4.0, 11.0)
			draw_rect(Rect2(p, Vector2(l, l)), Color(0.14, 0.05, 0.28, rng.randf_range(0.25, 0.6)))


## Un candado blanco sobre un circulo violeta (el de EQUIPO) o suelto.
class _Candado extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var s := size
		var c := s * 0.5
		var r := minf(s.x, s.y) * 0.5
		draw_circle(c, r, Color(0.62, 0.3, 0.85))
		draw_circle(c, r - 1.5, Color(0.72, 0.4, 0.95))
		var w := r * 0.9
		var h := r * 0.7
		var cuerpo := Rect2(c + Vector2(-w * 0.5, -h * 0.15), Vector2(w, h))
		draw_arc(c + Vector2(0, -h * 0.15), w * 0.32, PI, TAU, 16, Color.WHITE, maxf(2.0, r * 0.16), true)
		draw_rect(cuerpo, Color.WHITE)
		draw_circle(cuerpo.get_center(), r * 0.1, Color(0.62, 0.3, 0.85))


## LA TARJETA DE UN SUBMODO: inclinada como la letra, en degradado de su color, con el dibujo a la izquierda (una persona,
## cuatro, dos bandos o todos contra todos), el titulo y una linea. La elegida va a todo color con el filo amarillo, su
## sello y un brillo que pasa; la otra, apagada.
class _TarjetaSub extends Control:
	var color := Color.WHITE
	var titulo := ""
	var linea := ""
	var dibujo := ""
	var elegida := false
	var encima := false
	var fuerte: Font
	var normal: Font
	var _t := 0.0
	const TINTA := Color(0.06, 0.03, 0.16, 0.95)
	const SESGO := 10.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(dt: float) -> void:
		if elegida:
			_t += dt
			queue_redraw()

	func _forma(r: Rect2) -> PackedVector2Array:
		return PackedVector2Array([r.position + Vector2(SESGO, 0), Vector2(r.end.x, r.position.y), r.end - Vector2(SESGO, 0),
			Vector2(r.position.x, r.end.y)])

	func _draw() -> void:
		var s := size
		var forma := _forma(Rect2(Vector2.ZERO, s))
		var arriba := color.lightened(0.18)
		var abajo := color.darkened(0.42)
		if not elegida:
			var apagado := Color(0.22, 0.17, 0.44) if not encima else Color(0.28, 0.22, 0.54)
			arriba = arriba.lerp(apagado, 0.62)
			abajo = abajo.lerp(apagado.darkened(0.3), 0.62)
		draw_polygon(forma, PackedColorArray([arriba, arriba, abajo, abajo]))
		# rayas diagonales muy tenues (textura de cartel)
		for i in range(-2, int(s.x / 18.0) + 2):
			var x := i * 18.0
			var a := Vector2(x + SESGO, 0)
			var b := Vector2(x, s.y)
			var dentro_a := Vector2(clampf(a.x, SESGO, s.x), a.y)
			var dentro_b := Vector2(clampf(b.x, 0.0, s.x - SESGO), b.y)
			draw_line(dentro_a, dentro_b, Color(1, 1, 1, 0.05 if elegida else 0.03), 5.0)
		# el brillo que pasa por la elegida (recortado a la forma: se dibuja solo la banda que cae dentro)
		if elegida:
			var fase := fmod(_t * 0.55, 1.8) - 0.4
			var bx := fase * s.x
			var banda := PackedVector2Array([Vector2(bx + SESGO, 0), Vector2(bx + 34 + SESGO, 0), Vector2(bx + 34, s.y), Vector2(bx, s.y)])
			var recorte := Geometry2D.intersect_polygons(banda, forma)
			for p in recorte:
				draw_colored_polygon(p, Color(1, 1, 1, 0.16))
		# el dibujo
		var h := s.y
		var cx := 18.0 + h * 0.42
		_figura(Vector2(cx, h * 0.54), h * 0.72)
		# titulo y linea (el titulo se encoge para caber; si ni asi, en dos lineas)
		var x0 := cx + h * 0.48
		var libre := s.x - x0 - 30.0         # (a la derecha va el sello de la elegida)
		var tam := 21
		while tam > 14 and fuerte.get_string_size(titulo, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x > libre:
			tam -= 1
		var lineas: Array = [titulo]
		if fuerte.get_string_size(titulo, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x > libre and titulo.contains(" "):
			var corte := titulo.rfind(" ")
			lineas = [titulo.substr(0, corte), titulo.substr(corte + 1)]
			tam = 16
			while tam > 12 and fuerte.get_string_size(String(lineas[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x > libre:
				tam -= 1
		var y := h * 0.5 - (8.0 if lineas.size() == 1 else 16.0)
		for l in lineas:
			draw_string_outline(fuerte, Vector2(x0, y + tam * 0.35), String(l), HORIZONTAL_ALIGNMENT_LEFT, -1, tam, 6, TINTA)
			draw_string(fuerte, Vector2(x0, y + tam * 0.35), String(l), HORIZONTAL_ALIGNMENT_LEFT, -1, tam, Color.WHITE)
			y += tam + 1.0
		var tl := 12
		while tl > 9 and normal.get_string_size(linea, HORIZONTAL_ALIGNMENT_LEFT, -1, tl).x > libre + 12.0:
			tl -= 1
		draw_string_outline(normal, Vector2(x0, y + 10), linea, HORIZONTAL_ALIGNMENT_LEFT, libre + 12.0, tl, 4, TINTA)
		draw_string(normal, Vector2(x0, y + 10), linea, HORIZONTAL_ALIGNMENT_LEFT, libre + 12.0, tl,
			Color(1.0, 0.9, 0.4) if elegida else Color(1, 1, 1, 0.75))
		# el filo
		var borde := forma.duplicate()
		borde.append(forma[0])
		if elegida:
			draw_polyline(borde, Color(1.0, 0.88, 0.16), 3.5, true)
			# el sello de elegida: circulo amarillo con la marca, arriba a la derecha
			var c := Vector2(s.x - 16.0, 12.0)
			draw_circle(c, 10.0, TINTA)
			draw_circle(c, 8.5, Color(1.0, 0.88, 0.16))
			draw_polyline(PackedVector2Array([c + Vector2(-4.5, 0.5), c + Vector2(-1.2, 3.8), c + Vector2(4.8, -3.6)]), TINTA, 2.6, true)
		else:
			draw_polyline(borde, Color(1, 1, 1, 0.5 if encima else 0.22), 2.0, true)

	## Una persona: cabeza y hombros, con contorno
	func _persona(c: Vector2, h: float, col: Color) -> void:
		var cuerpo := PackedVector2Array([c + Vector2(-h * 0.34, h * 0.5), c + Vector2(-h * 0.3, h * 0.05), c + Vector2(-h * 0.16, -h * 0.06),
			c + Vector2(h * 0.16, -h * 0.06), c + Vector2(h * 0.3, h * 0.05), c + Vector2(h * 0.34, h * 0.5)])
		var borde := cuerpo.duplicate()
		borde.append(cuerpo[0])
		draw_colored_polygon(cuerpo, col)
		draw_polyline(borde, TINTA, maxf(1.5, h * 0.06), true)
		draw_circle(c + Vector2(0, -h * 0.3), h * 0.2 + h * 0.03, TINTA)
		draw_circle(c + Vector2(0, -h * 0.3), h * 0.2, col)

	func _figura(c: Vector2, h: float) -> void:
		var blanco := Color(1, 1, 1, 0.96 if elegida else 0.7)
		match dibujo:
			"uno":
				_persona(c + Vector2(0, h * 0.04), h * 0.86, blanco)
			"cuatro":
				# tres detras y uno delante, del color de la escuadra
				_persona(c + Vector2(-h * 0.3, -h * 0.08), h * 0.5, blanco.darkened(0.25))
				_persona(c + Vector2(h * 0.3, -h * 0.08), h * 0.5, blanco.darkened(0.25))
				_persona(c + Vector2(0, -h * 0.16), h * 0.5, blanco.darkened(0.15))
				_persona(c + Vector2(0, h * 0.14), h * 0.6, blanco)
			"bandos":
				_persona(c + Vector2(-h * 0.24, h * 0.06), h * 0.6, Color(1.0, 0.56, 0.18) if elegida else Color(0.9, 0.6, 0.4, 0.8))
				_persona(c + Vector2(h * 0.24, h * 0.06), h * 0.6, Color(0.36, 0.62, 1.0) if elegida else Color(0.5, 0.65, 0.9, 0.8))
			"todos":
				# cuatro de colores alrededor de una mira
				var cols := [Color(1.0, 0.8, 0.2), Color(0.3, 0.88, 0.95), Color(0.6, 0.95, 0.35), Color(1.0, 0.45, 0.7)]
				for i in 4:
					var a := TAU * float(i) / 4.0 + PI * 0.25
					var col: Color = cols[i] if elegida else Color(cols[i], 0.7)
					_persona(c + Vector2(cos(a), sin(a)) * h * 0.3, h * 0.38, col)
				draw_arc(c, h * 0.12, 0.0, TAU, 20, TINTA, 4.0, true)
				draw_arc(c, h * 0.12, 0.0, TAU, 20, blanco, 2.0, true)
				for k in 4:
					var d := Vector2.from_angle(TAU * float(k) / 4.0)
					draw_line(c + d * h * 0.06, c + d * h * 0.18, blanco, 2.0)
