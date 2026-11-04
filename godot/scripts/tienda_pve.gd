## La ventana de la tienda del PvE. Se abre al usar el puesto de la tienda que hay en el mapa.
##
## Es una pantalla, no un puesto por cada cosa: una sola caja con todo ordenado (nombre, para que
## sirve y precio) y un boton por articulo. Los botones son grandes a proposito para que se puedan
## tocar con el pulgar en el movil sin fallar.
extends Control

const ORO := Color(1.0, 0.83, 0.0)
const FONDO := Color(0.04, 0.05, 0.08, 0.97)
const TARJETA := Color(0.09, 0.115, 0.19, 0.96)
const APAGADO := Color(0.62, 0.66, 0.76)

var oro := 0
var articulos: Array = []           ## [{id, nombre, texto, precio, color}]

signal comprado(id: String)
signal cerrado

var _fila: Dictionary = {}          ## id -> {boton, precio_label, tarjeta}
var _oro_label: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# tapa el juego de detras: sin esto se dispara al tocar la tienda
	var tapa := ColorRect.new()
	tapa.set_anchors_preset(Control.PRESET_FULL_RECT)
	tapa.color = Color(0.01, 0.012, 0.02, 0.72)
	tapa.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(tapa)
	_construir()


func _construir() -> void:
	var caja := PanelContainer.new()
	caja.add_theme_stylebox_override("panel", _estilo(FONDO, 18, Color(ORO, 0.55), 2, 22))
	caja.set_anchors_preset(Control.PRESET_CENTER)
	caja.anchor_left = 0.5
	caja.anchor_right = 0.5
	caja.anchor_top = 0.5
	caja.anchor_bottom = 0.5
	caja.grow_horizontal = Control.GROW_DIRECTION_BOTH
	caja.grow_vertical = Control.GROW_DIRECTION_BOTH
	caja.custom_minimum_size = Vector2(760, 0)
	add_child(caja)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	caja.add_child(col)

	var cabecera := HBoxContainer.new()
	cabecera.add_theme_constant_override("separation", 18)
	col.add_child(cabecera)
	var titulo := _texto("TIENDA", 40, Color.WHITE)
	titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cabecera.add_child(titulo)
	_oro_label = _texto("◈ %d" % oro, 34, ORO)
	cabecera.add_child(_oro_label)

	var raya := ColorRect.new()
	raya.color = Color(ORO, 0.75)
	raya.custom_minimum_size = Vector2(0, 3)
	col.add_child(raya)
	col.add_child(_texto("El oro sale de matar bichos. Aprovecha el descanso entre oleadas.", 18, APAGADO))

	for a in articulos:
		col.add_child(_tarjeta(a))

	var pie := HBoxContainer.new()
	pie.add_theme_constant_override("separation", 12)
	col.add_child(pie)
	var hueco := Control.new()
	hueco.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pie.add_child(hueco)
	var cerrar := _boton("CERRAR", 22, Color(0.16, 0.18, 0.26), Color.WHITE, Vector2(220, 62))
	cerrar.pressed.connect(cerrar_ventana)
	pie.add_child(cerrar)
	_refrescar()


## Una linea de la tienda: cuadro de color, nombre, para que sirve y el boton de comprar.
func _tarjeta(a: Dictionary) -> Control:
	var marco := PanelContainer.new()
	marco.add_theme_stylebox_override("panel", _estilo(TARJETA, 12, Color.TRANSPARENT, 0, 14))
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 16)
	marco.add_child(fila)

	var icono := ColorRect.new()
	icono.color = a.get("color", ORO)
	icono.custom_minimum_size = Vector2(10, 66)
	fila.add_child(icono)

	var textos := VBoxContainer.new()
	textos.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	textos.add_theme_constant_override("separation", 2)
	textos.add_child(_texto(String(a["nombre"]), 26, Color.WHITE))
	textos.add_child(_texto(String(a.get("texto", "")), 17, APAGADO))
	fila.add_child(textos)

	var precio := _texto("◈ %d" % int(a["precio"]), 26, ORO)
	precio.custom_minimum_size = Vector2(120, 0)
	precio.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fila.add_child(precio)

	var id := String(a["id"])
	var b := _boton("COMPRAR", 22, Color(0.12, 0.42, 0.20), Color.WHITE, Vector2(190, 62))
	b.pressed.connect(func(): _pulsar(id))
	fila.add_child(b)
	_fila[id] = {"boton": b, "precio": precio}
	return marco


func _pulsar(id: String) -> void:
	for a in articulos:
		if String(a["id"]) == id and oro >= int(a["precio"]):
			comprado.emit(id)
			return


## Lo llama el PvE tras cobrar: el oro de la cabecera baja y se apagan los articulos que ya no llegan.
func poner_oro(v: int) -> void:
	oro = v
	_refrescar()


func _refrescar() -> void:
	if _oro_label:
		_oro_label.text = "◈ %d" % oro
	for a in articulos:
		var f: Dictionary = _fila.get(String(a["id"]), {})
		if f.is_empty():
			continue
		var puedo: bool = oro >= int(a["precio"])
		var b: Button = f["boton"]
		b.text = "COMPRAR" if puedo else "SIN ORO"
		var c := Color(0.12, 0.42, 0.20) if puedo else Color(0.17, 0.18, 0.22)
		b.add_theme_stylebox_override("normal", _estilo(c, 10, Color.TRANSPARENT, 0, 10))
		b.add_theme_stylebox_override("hover", _estilo(c.lightened(0.15), 10, Color.TRANSPARENT, 0, 10))
		b.add_theme_stylebox_override("pressed", _estilo(c.darkened(0.2), 10, Color.TRANSPARENT, 0, 10))
		for n in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(n, Color.WHITE if puedo else APAGADO)


func cerrar_ventana() -> void:
	cerrado.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	# con Esc se sale, como en cualquier menu; tambien vale el boton de usar
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		cerrar_ventana()


# --- ladrillos ---------------------------------------------------------------
func _estilo(bg: Color, radio: int, borde: Color, bw: int, pad: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radio)
	sb.set_border_width_all(bw)
	sb.border_color = borde
	sb.set_content_margin_all(pad)
	return sb


func _texto(t: String, tam: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", c)
	return l


func _boton(t: String, tam: int, bg: Color, fg: Color, minimo: Vector2) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = minimo
	b.add_theme_font_size_override("font_size", tam)
	for n in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(n, fg)
	b.add_theme_stylebox_override("normal", _estilo(bg, 10, Color.TRANSPARENT, 0, 10))
	b.add_theme_stylebox_override("hover", _estilo(bg.lightened(0.15), 10, Color.TRANSPARENT, 0, 10))
	b.add_theme_stylebox_override("pressed", _estilo(bg.darkened(0.2), 10, Color.TRANSPARENT, 0, 10))
	return b
