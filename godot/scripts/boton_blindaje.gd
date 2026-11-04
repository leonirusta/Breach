extends Control
## EL BOTON DEL BLINDAJE (2026-10-03, pedido: "al lado de la habilidad, otra habilidad: reduccion de daño"): a la
## izquierda del de la habilidad (boton_habilidad.gd), mas pequeño. Tocarlo -o [Z]- enciende y apaga el BLINDAJE
## (habilidad.gd: rebaja el daño y lo paga con la energia). Encendido, el hexagono se llena de azul acero y late. Solo
## con los personajes que van con energia (hoy el Specter).
const IconoLobby := preload("res://scripts/icono_lobby.gd")
const LADO := 76.0     # (era 64: 2026-10-05, pedido "un poquito mas grande")
const COLOR := Color(0.62, 0.78, 1.0)

var player: Node = null
var boton: Control = null          ## el de la habilidad: este va a su izquierda
var _icono: Control
var _fuente: Font
var _firma: Array = []
static var _ui_siempre: bool = "--uisiempre" in OS.get_cmdline_user_args()


func _ready() -> void:
	preload("res://scripts/teclas_pc.gd").marca(self, "Z")      # en el PC, su tecla (2026-10-20)
	size = Vector2(LADO, LADO + 18)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_fuente = preload("res://scripts/fuentes.gd").de(800, false)
	_icono = IconoLobby.new()
	_icono.icono = "glifo_blindaje"
	_icono.position = Vector2(LADO * 0.25, LADO * 0.25)
	_icono.size = Vector2(LADO * 0.5, LADO * 0.5)
	_icono.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icono)
	visible = false


func _hab():
	if player == null or not is_instance_valid(player):
		return null
	var h = player.get("_hab")
	return h if h != null and is_instance_valid(h) and h.has_method("usa_energia") and h.usa_energia() else null


func _gui_input(e: InputEvent) -> void:
	if (e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
			or (e is InputEventScreenTouch and e.pressed):
		accept_event()
		if player != null and is_instance_valid(player) and player.has_method("usar_blindaje"):
			player.usar_blindaje()


## (medicion de la auditoria, 2026-10-05: lo que cuesta este control por fotograma, clave Prof "ui.blindaje")
func _process(_dt: float) -> void:
	var _tp := Time.get_ticks_usec()
	_process_ui(_dt)
	Prof.add("ui.blindaje", Time.get_ticks_usec() - _tp)


func _process_ui(_dt: float) -> void:
	var h = _hab()
	var ver: bool = h != null and boton != null and is_instance_valid(boton) and boton.visible \
		and float(player.get("health")) > 0.0 and not bool(player.get("spectating"))
	if visible != ver:
		visible = ver
	if not ver:
		return
	# a la izquierda del de la habilidad, centrado con el
	position = boton.position + Vector2(-LADO - 14.0, (boton.size.y - size.y) * 0.5)
	var on: bool = bool(h.blindaje)
	_icono.color = Color.WHITE if on else (COLOR if float(h.energia) >= 1.0 else Color(0.75, 0.77, 0.8, 0.5))
	# SOLO SE REDIBUJA SI CAMBIA ALGO DE LO QUE PINTA (auditoria, 2026-10-05): antes, en cada fotograma. Lo que anima
	# (latidos, destellos, parpadeos) se sigue redibujando siempre; quieto, la imagen es la misma. --uisiempre = antes.
	var firma: Array = [on]
	if _ui_siempre or on or firma != _firma:
		_firma = firma
		queue_redraw()


func _draw() -> void:
	var _td := Time.get_ticks_usec()
	_draw_ui()
	Prof.add("ui.blindaje.draw", Time.get_ticks_usec() - _td)


func _draw_ui() -> void:
	var h = _hab()
	if h == null:
		return
	var on: bool = bool(h.blindaje)
	var c := Vector2(LADO * 0.5, LADO * 0.5)
	var r := LADO * 0.5 - 2.0
	var t := Time.get_ticks_msec() * 0.001
	var hexa := PackedVector2Array()
	for i in 6:
		var a := PI / 6.0 + i * TAU / 6.0
		hexa.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(hexa, Color(COLOR, 0.35 + 0.15 * sin(t * 6.0)) if on else Color(0.02, 0.025, 0.035, 0.78))
	var cerrado := hexa.duplicate()
	cerrado.append(hexa[0])
	draw_polyline(cerrado, Color(COLOR, 0.7 + 0.3 * sin(t * 6.0)) if on else Color(COLOR, 0.6), 3.0 if on else 2.0, true)
	# (SIN LETRAS DE TECLAS (2026-10-04, pedido: "el juego es para el movil: ninguna letra de W A S D ni apretar E, el simbolo"): sin la Z de la tecla en la esquina; la Z sigue funcionando en el PC)
	# el nombre, debajo
	var nombre := "BLINDAJE"
	var ns := _fuente.get_string_size(nombre, HORIZONTAL_ALIGNMENT_CENTER, -1, 11)
	var p := Vector2(LADO * 0.5 - ns.x * 0.5, LADO + 13.0)
	draw_string_outline(_fuente, p, nombre, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 4, Color(0, 0, 0, 0.85))
	draw_string(_fuente, p, nombre, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE if on else Color(0.85, 0.9, 1.0))
