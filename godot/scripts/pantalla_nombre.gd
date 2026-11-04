extends Control
## ELIGE TU NOMBRE DE JUGADOR. Sale entre el login y el lobby, solo en cuentas NUEVAS.
##
## Por que hace falta: entrando con Google la cuenta se crea sola y hereda el nombre de la cuenta de
## Google, que ni es unico ni tiene por que apetecerte llevarlo en una partida. Quien se registra con
## usuario y clave ya eligio uno (el suyo, que es unico por construccion) y a ese no se le pregunta.
##
## El nombre es UNICO en todo el juego y quien arbitra es el servidor: aqui no se comprueba nada por
## adelantado. Preguntar "¿esta libre?" y luego mandarlo deja un hueco entre las dos cosas por el que
## se cuela otro jugador, y acabarian los dos con el mismo nombre. Se manda, y si el servidor dice que
## esta cogido se pide otro.

const LOBBY := "res://scenes/lobby.tscn"

const FONDO := Color(0.05, 0.06, 0.08)
const CAJA := Color(0.11, 0.12, 0.15)
const DORADO := Color(1.0, 0.83, 0.0)
const ROJO := Color(0.95, 0.35, 0.32)
const TENUE := Color(0.72, 0.76, 0.85)

var _campo: LineEdit = null
var _aviso: Label = null
var _boton: Button = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fondo := ColorRect.new()
	fondo.color = FONDO
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fondo)

	var centro := CenterContainer.new()
	centro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centro)

	var caja := PanelContainer.new()
	caja.custom_minimum_size = Vector2(440, 0)
	var e := StyleBoxFlat.new()
	e.bg_color = CAJA
	e.set_corner_radius_all(12)
	e.content_margin_left = 30
	e.content_margin_right = 30
	e.content_margin_top = 26
	e.content_margin_bottom = 26
	caja.add_theme_stylebox_override("panel", e)
	centro.add_child(caja)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	caja.add_child(col)

	col.add_child(_texto("ELIGE TU NOMBRE", 30, DORADO))
	col.add_child(_texto("es con el que te veran los demas en la partida, y no se puede repetir", 13, TENUE))
	col.add_child(_hueco(8))

	_campo = LineEdit.new()
	_campo.placeholder_text = "nombre de jugador"
	_campo.max_length = 16
	_campo.custom_minimum_size = Vector2(0, 42)
	_campo.add_theme_font_size_override("font_size", 18)
	preload("res://scripts/campo_tactil.gd").attach(_campo)   # con el dedo, si no no coge foco ni sale teclado
	# se propone el que trae la cuenta (el de Google) ya limpio: la mayoria lo dejara tal cual
	_campo.text = _limpiar(Cuenta.nombre())
	_campo.text_submitted.connect(func(_t): _enviar())
	col.add_child(_campo)

	_aviso = _texto("de 3 a 16 caracteres", 13, TENUE)
	_aviso.custom_minimum_size = Vector2(0, 24)
	col.add_child(_aviso)

	_boton = Button.new()
	_boton.text = "CONTINUAR"
	_boton.custom_minimum_size = Vector2(0, 44)
	_boton.add_theme_font_size_override("font_size", 17)
	_boton.add_theme_color_override("font_color", DORADO)
	_boton.pressed.connect(_enviar)
	col.add_child(_boton)

	Cuenta.sesion_cambiada.connect(_al_cambiar)
	Cuenta.error_cuenta.connect(_al_error)
	_campo.grab_focus()
	_campo.select_all()


func _texto(t: String, tam: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", c)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _hueco(a: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, a)
	return c


## El nombre de Google puede traer puntos, apellidos largos o caracteres que el servidor no admite.
## Se propone ya recortado para que el jugador no reciba un error por algo que no ha escrito el.
func _limpiar(n: String) -> String:
	var salida := ""
	for c in n:
		if c.is_valid_identifier() or c == " " or c == "-" or c == "_" or c.to_lower() != c.to_upper() or c.is_valid_int():
			salida += c
	salida = salida.strip_edges()
	while salida.contains("  "):
		salida = salida.replace("  ", " ")
	return salida.substr(0, 16)


func _enviar() -> void:
	var n := _campo.text.strip_edges()
	if n.length() < 3:
		_decir("hacen falta al menos 3 caracteres", ROJO)
		return
	_decir("comprobando...", TENUE)
	_boton.disabled = true
	_enviado = true
	if not Cuenta.elegir_nombre(n):
		_enviado = false
		_boton.disabled = false


func _decir(t: String, c: Color) -> void:
	if is_instance_valid(_aviso):
		_aviso.text = t
		_aviso.add_theme_color_override("font_color", c)


## Solo despues de mandar el apodo: en una cuenta registrada `nombre_elegido` ya es verdad, y cualquier refresco del
## perfil se saltaba esta pantalla sin dejar escribir nada
var _enviado := false
func _al_cambiar() -> void:
	if _enviado and Cuenta.nombre_elegido():
		get_tree().change_scene_to_file(LOBBY)


## "ese nombre ya esta en uso, prueba otro" llega tal cual del servidor y se enseña sin adornar: es
## exactamente lo que el jugador necesita saber.
func _al_error(m: String) -> void:
	_enviado = false
	_boton.disabled = false
	_decir(m, ROJO)
	_campo.grab_focus()
	_campo.select_all()
