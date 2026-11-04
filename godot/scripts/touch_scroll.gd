extends Node
## ARRASTRE TÁCTIL PARA LISTAS. Se cuelga de un ScrollContainer y le da el "deslizar con el dedo"
## de toda la vida, con inercia.
##
## Por qué a mano y no confiando en el motor: el arrastre táctil propio de ScrollContainer sólo se
## activa cuando el motor declara que hay pantalla táctil, y el proyecto además tiene
## `emulate_mouse_from_touch = false`. Con esto la lista se desliza igual en un móvil, en una tablet
## y en PC con el ratón, sin depender de esa detección.

const FRICTION := 6.0        ## cuánto se frena la inercia (1/s)
const MIN_DRAG := 6.0        ## px antes de considerar que estás deslizando y no tocando un botón

var scroll: ScrollContainer = null
var _id := -1
var _last := 0.0
var _vel := 0.0
var _moved := 0.0


static func attach(sc: ScrollContainer) -> Node:
	var n = load("res://scripts/touch_scroll.gd").new()
	n.scroll = sc
	sc.add_child(n)
	return n


func _ready() -> void:
	set_process(true)
	set_process_input(true)


func _process(dt: float) -> void:
	if scroll == null or not is_instance_valid(scroll):
		return
	if _id < 0 and absf(_vel) > 1.0:
		scroll.scroll_vertical = int(scroll.scroll_vertical - _vel * dt)
		_vel = move_toward(_vel, 0.0, absf(_vel) * FRICTION * dt + 20.0 * dt)


## DESLIZAR NO ES TOCAR. "Cuando quiero hacer scroll para bajar me selecciona algo": el dedo se apoyaba
## encima de un boton de la lista, el boton recibia el toque en el acto, y al deslizar la lista se
## disparaba igual -medido con --scrollboton: una opcion de Ajustes cambiaba dos veces, y la tarjeta de
## mapa de encima se elegia-.
##
## Ahora el toque que cae dentro de la lista SE RETIENE: no llega a nadie hasta saber que es. Si el dedo
## se levanta sin haberse movido, se reenvia el toque entero (apoyar y soltar) y el boton funciona como
## siempre. Si se desliza, era un scroll y el boton no se entera de nada.
##
## Lo que se maneja ARRASTRANDO (deslizadores de volumen, sensibilidad, campos de texto) no se retiene:
## a esos el toque les llega directo, o no se podrian mover.
var _retenido: InputEventScreenTouch = null
var _en_arrastrable := false       ## el dedo empezo en un deslizador o un campo de texto: la lista no se mueve
var _reenviando := false


func _input(event: InputEvent) -> void:
	if _reenviando:
		return
	if scroll == null or not is_instance_valid(scroll) or not scroll.is_visible_in_tree():
		return
	var rect := scroll.get_global_rect()
	if event is InputEventScreenTouch:
		if event.pressed:
			if not rect.has_point(event.position) or _id >= 0:
				return
			_id = event.index
			_last = event.position.y
			_vel = 0.0
			_moved = 0.0
			_retenido = null
			_en_arrastrable = _se_arrastra(_control_en(scroll, event.position))
			if not _en_arrastrable:
				_retenido = event.duplicate()
				get_viewport().set_input_as_handled()
		elif event.index == _id:
			_id = -1
			if _retenido != null:
				# NO SE MOVIO: era un toque. Se entrega entero, apoyar y soltar, en su sitio.
				var apoyo := _retenido
				_retenido = null
				get_viewport().set_input_as_handled()
				_reenviando = true
				# EN COORDENADAS LOCALES (el `true`). El toque que llega a `_input` YA esta pasado a pixeles del
				# juego (1280x720); `push_input` sin ese true lo vuelve a escalar como si viniera de la
				# pantalla. En el PC la ventana es 1280x720 y no se nota; en un movil la pantalla se escala y
				# el toque caia desplazado: "tengo que apretar lejos del boton para que funcione".
				get_viewport().push_input(apoyo, true)   # en el acto, no a la cola: si no, lo volvia a retener yo
				_reenviando = false
				_soltar_luego(event.duplicate())
	elif event is InputEventScreenDrag and event.index == _id:
		# EL DEDO QUE EMPEZO EN UN DESLIZADOR ES DEL DESLIZADOR (2026-09-30, bug: "el volumen cuesta deslizarlo, no detecta
		# bien el dedo"): con que el dedo bajara 6 px mientras se arrastraba en horizontal, la lista se ponia a moverse y
		# se comia los arrastres (set_input_as_handled), y el deslizador se quedaba quieto
		if _en_arrastrable:
			return
		var d: float = event.position.y - _last
		_last = event.position.y
		_moved += absf(d)
		if _moved < MIN_DRAG:
			if _retenido != null:
				get_viewport().set_input_as_handled()
			return
		_retenido = null            # es un scroll: el toque retenido se tira
		scroll.scroll_vertical = int(scroll.scroll_vertical - d)
		_vel = d / maxf(0.001, get_process_delta_time())
		get_viewport().set_input_as_handled()


## El soltar va un cuadro despues del apoyar: si llegan juntos, un boton que se activa al soltar no
## llega a verse apretado y hay controles que no lo cuentan.
func _soltar_luego(ev: InputEventScreenTouch) -> void:
	await get_tree().process_frame
	_reenviando = true
	get_viewport().push_input(ev, true)
	_reenviando = false


static func _se_arrastra(c: Control) -> bool:
	while c != null:
		if c is Range or c is LineEdit or c is TextEdit:
			return true
		if c is ScrollContainer:
			return false
		c = c.get_parent() as Control
	return false


## El control de mas adentro que recibe toques en ese punto.
static func _control_en(raiz: Control, p: Vector2) -> Control:
	var mejor: Control = null
	for h in raiz.get_children():
		var c := h as Control
		if c == null or not c.is_visible_in_tree():
			continue
		if not c.get_global_rect().has_point(p):
			continue
		var dentro := _control_en(c, p)
		if dentro != null:
			mejor = dentro
		elif c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			mejor = c
	return mejor
