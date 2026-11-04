extends Control
## PANEL DE CUENTA DEL LOBBY. Lo abre el boton CUENTA de la barra de arriba.
##
## Solo ENSEÑA y permite salir de la sesion. Escribir usuario y clave se hace en la pantalla de
## entrada (`pantalla_login.gd`), que es la primera del juego: tener dos formularios de acceso en dos
## sitios distintos era la razon de que este panel acabara medio roto -se quedo a medias cuando la
## pantalla de entrada paso a ser la buena-.
##
## Aqui NO se enseña la direccion del servidor. El jugador no tiene por que saber que hay una URL de
## Cloud Run detras, y verla solo invita a tocarla.

signal cerrado

const FONDO := Color(0.03, 0.04, 0.05, 0.88)
const CAJA := Color(0.11, 0.12, 0.15)
const DORADO := Color(1.0, 0.83, 0.0)
const ROJO := Color(0.95, 0.35, 0.32)
const TENUE := Color(0.72, 0.76, 0.85)

var _titulo: Label = null
var _datos: Label = null
var _aviso: Label = null
var _boton_pruebas: Button = null
## EN QUE MODO ESTAS, dicho en claro encima del boton (pedido: "que te indique en que modo estas").
var _modo: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# el velo tambien CIERRA al tocarlo fuera de la caja, que es lo que todo el mundo intenta primero
	var velo := ColorRect.new()
	velo.color = FONDO
	velo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	velo.mouse_filter = Control.MOUSE_FILTER_STOP
	velo.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			_cerrar())
	add_child(velo)

	# CENTRADO DE VERDAD. Antes usaba PRESET_CENTER sobre el propio panel, que fija las anclas pero no
	# el tamano: la caja salia pequena y pegada arriba a la izquierda. Un CenterContainer centra lo que
	# tenga dentro mida lo que mida.
	var centro := CenterContainer.new()
	centro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centro)

	var caja := PanelContainer.new()
	caja.custom_minimum_size = Vector2(420, 0)
	caja.mouse_filter = Control.MOUSE_FILTER_STOP
	var e := StyleBoxFlat.new()
	e.bg_color = CAJA
	e.set_corner_radius_all(12)
	e.border_width_top = 2
	e.border_color = DORADO
	e.content_margin_left = 28
	e.content_margin_right = 28
	e.content_margin_top = 24
	e.content_margin_bottom = 24
	caja.add_theme_stylebox_override("panel", e)
	centro.add_child(caja)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	caja.add_child(col)

	_titulo = _texto("CUENTA", 28, DORADO)
	col.add_child(_titulo)
	_datos = _texto("", 15, TENUE)
	col.add_child(_datos)
	_aviso = _texto("", 13, TENUE)
	_aviso.custom_minimum_size = Vector2(0, 20)
	col.add_child(_aviso)

	# PROBAR OFFLINE. Es el interruptor de las herramientas del menu de partida (vida infinita,
	# municion infinita, noclip, demoler, cambiar mapa). Vive AQUI y no en la configuracion grafica
	# porque no es un ajuste de juego: es decir "esta partida es una prueba mia", y por eso tampoco da
	# EXP ni oro mientras esta puesto.
	_modo = Label.new()
	_modo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_modo.add_theme_font_size_override("font_size", 15)
	col.add_child(_modo)
	_boton_pruebas = _boton("", _alternar_pruebas, Color(0.55, 0.85, 1.0))
	col.add_child(_boton_pruebas)
	col.add_child(_boton("CERRAR", _cerrar, TENUE))
	col.add_child(_boton("CERRAR SESION", _salir, ROJO))

	Cuenta.sesion_cambiada.connect(_refrescar)
	Cuenta.error_cuenta.connect(func(m: String): _decir(m, ROJO))
	_refrescar()


func _texto(t: String, tam: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", c)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _boton(t: String, accion: Callable, c: Color) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(0, 42)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", c)
	b.pressed.connect(accion)
	return b


func _decir(t: String, c: Color) -> void:
	if is_instance_valid(_aviso):
		_aviso.text = t
		_aviso.add_theme_color_override("font_color", c)


## Escape cierra. Es lo que espera cualquiera en un panel superpuesto, y ademas es la salida de
## emergencia si algun boton dejara de responder.
func _unhandled_input(evento: InputEvent) -> void:
	if evento is InputEventKey and evento.pressed and evento.keycode == KEY_ESCAPE:
		_cerrar()
		get_viewport().set_input_as_handled()


func _cerrar() -> void:
	cerrado.emit()
	queue_free()


## CERRAR SESION DEVUELVE A LA PANTALLA DE ENTRADA.
##
## Antes solo borraba el token y se quedaba en el lobby: parecia que no hacia nada, porque el lobby
## seguia igual. Sin sesion no hay nada que hacer en el lobby con cuenta, asi que se vuelve a la
## pantalla de entrada, que es donde se puede volver a entrar o crear otra.
func _salir() -> void:
	# cerrar sesion a mano: tambien se olvidan el usuario y la clave guardados (pantalla_login.gd)
	preload("res://scripts/pantalla_login.gd").olvidar_datos()
	Cuenta.salir()
	get_tree().change_scene_to_file("res://scenes/login.tscn")


## Enciende y apaga el modo pruebas. Se guarda en el acto: si el juego se cierra de golpe, el estado
## que vea el jugador la proxima vez es el que dejo puesto.
func _alternar_pruebas() -> void:
	Settings.modo_pruebas = not Settings.modo_pruebas
	Settings.offline_a_mano = Settings.modo_pruebas
	if not Settings.modo_pruebas:
		Settings.apagar_trucos()          # a online: fuera el perfilador y lo demas de pruebas
	Settings.save()
	_refrescar()
	if Settings.modo_pruebas:
		_decir("herramientas activadas · en esta partida no ganas EXP ni oro", Color(0.55, 0.85, 1.0))
	else:
		_decir("herramientas desactivadas · vuelves a ganar progreso", TENUE)


func _refrescar() -> void:
	if not is_instance_valid(_titulo):
		return
	# EL BOTON DICE A QUE CAMBIAS, Y LA LINEA DE ENCIMA DONDE ESTAS. Antes el boton decia "JUGAR OFFLINE"
	# estuviera o no puesto (solo cambiaba un ": ACTIVADO" al final), y con cuenta abierta nadie leia que
	# estaba jugando sin conexion: JUGAR iba directo al mapa, sin buscar sala.
	if is_instance_valid(_modo):
		if Settings.modo_pruebas:
			_modo.text = "MODO ACTUAL: SIN CONEXIÓN\njuegas solo, con herramientas · no se busca sala · no ganas EXP ni oro"
			_modo.add_theme_color_override("font_color", Color(1.0, 0.72, 0.3))
		else:
			_modo.text = "MODO ACTUAL: ONLINE\nJUGAR busca partida con gente · ganas EXP y oro"
			_modo.add_theme_color_override("font_color", Color(0.45, 0.9, 0.5))
	if is_instance_valid(_boton_pruebas):
		_boton_pruebas.text = ("CAMBIAR A ONLINE" if Settings.modo_pruebas else "CAMBIAR A SIN CONEXIÓN")
		_boton_pruebas.tooltip_text = ("Abre las herramientas del menú de partida (vida infinita, "
			+ "noclip, demoler, cambiar mapa). Solo sin conexión, y sin premios.")
	if Cuenta.conectado():
		_titulo.text = Cuenta.nombre().to_upper()
		_datos.text = "nivel %d  ·  %d EXP  ·  ◈ %d" % [Cuenta.nivel(), Cuenta.experiencia(), Cuenta.monedas()]
		_decir("tu progreso se guarda en el servidor", TENUE)
	else:
		_titulo.text = "SIN CUENTA"
		_datos.text = "tu progreso se guarda solo en este aparato"
		_decir("cierra y vuelve a abrir el juego para entrar", TENUE)
