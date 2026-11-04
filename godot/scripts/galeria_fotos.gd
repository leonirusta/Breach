extends CanvasLayer
## LA GALERIA DE FOTOS (2026-10-13, pedido: "en el lobby un boton para ver las fotos que has tomado, en pantalla completa
## y para eliminarlas"). Las fotos del menu de la partida (hud.sacar_foto) se guardan en user://fotos; aqui salen en una
## cuadricula de miniaturas (hechas en un hilo: abrir con muchas no da tirones), tocando una se ve en pantalla completa
## con < > para pasar y ELIMINAR (dos toques). La copia que va a Imagenes/Breach del telefono no se toca.
## La abre lobby._abrir_galeria (tecla GALERIA de la portada). Foto: --galeriafoto=<carpeta>.

const CARPETA := "user://fotos"
const MINI := Vector2i(320, 180)
const FONDO := Color(0.06, 0.05, 0.12, 0.97)
const LILA := Color(0.62, 0.52, 1.0)
const ROJO := Color(0.92, 0.22, 0.3)

var _f: Font
var _raiz: Control
var _rejilla: GridContainer
var _vacio: Label
var _cuenta: Label
var _fotos: PackedStringArray = []
var _completa: Control
var _img_grande: TextureRect
var _idx := -1
var _borrar: Button
var _borrar_armado := false
var _ocultar: Button
var _volver: Button
var _controles: Array = []
var _tareas: Array = []


func _ready() -> void:
	layer = 60
	_f = preload("res://scripts/fuentes.gd").de(800, true)
	_raiz = Control.new()
	_raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_raiz)
	var fondo := ColorRect.new()
	fondo.color = FONDO
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_raiz.add_child(fondo)
	var titulo := _label("GALERÍA", 46, Color.WHITE)
	titulo.position = Vector2(40, 22)
	_raiz.add_child(titulo)
	_cuenta = _label("", 24, LILA)
	_cuenta.position = Vector2(44, 84)
	_raiz.add_child(_cuenta)
	var x := _boton("✕", Color(0.25, 0.2, 0.42), func(): cerrar())
	x.custom_minimum_size = Vector2(76, 64)
	x.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	x.position = Vector2(-100, 24)
	_raiz.add_child(x)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 130
	scroll.offset_left = 40
	scroll.offset_right = -40
	scroll.offset_bottom = -20
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_raiz.add_child(scroll)
	_rejilla = GridContainer.new()
	_rejilla.add_theme_constant_override("h_separation", 16)
	_rejilla.add_theme_constant_override("v_separation", 16)
	scroll.add_child(_rejilla)
	_vacio = _label("Aún no has sacado fotos.\nEn la partida: MENÚ → SACAR FOTO.", 30, LILA)
	_vacio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vacio.set_anchors_preset(Control.PRESET_CENTER)
	_vacio.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_vacio.grow_vertical = Control.GROW_DIRECTION_BOTH
	_raiz.add_child(_vacio)
	_montar_completa()
	get_viewport().size_changed.connect(_columnas)
	_cargar()


func _label(t: String, tam: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", _f)
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", col)
	return l


func _boton(t: String, col: Color, al: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_override("font", _f)
	b.add_theme_font_size_override("font_size", 30)
	for estado in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.lightened(0.12 if estado == "hover" else 0.0).darkened(0.15 if estado == "pressed" else 0.0)
		sb.set_corner_radius_all(12)
		sb.content_margin_left = 22
		sb.content_margin_right = 22
		b.add_theme_stylebox_override(estado, sb)
	b.pressed.connect(al)
	return b


func _columnas() -> void:
	var an: float = get_viewport().get_visible_rect().size.x - 80.0
	_rejilla.columns = maxi(1, int((an + 16.0) / (MINI.x + 16.0)))


# ------------------------------------------------------------------------------------------------ la cuadricula
func _cargar() -> void:
	for c in _rejilla.get_children():
		c.queue_free()
	_fotos = PackedStringArray()
	var d := DirAccess.open(CARPETA)
	if d:
		for n in d.get_files():
			if n.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
				_fotos.append(CARPETA.path_join(n))
	_fotos.sort()
	_fotos.reverse()                     # la ultima, primero (el nombre lleva la fecha)
	_vacio.visible = _fotos.is_empty()
	_cuenta.text = "" if _fotos.is_empty() else ("%d FOTO%s" % [_fotos.size(), "" if _fotos.size() == 1 else "S"])
	_columnas()
	for i in _fotos.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(MINI)
		b.flat = true
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.16, 0.13, 0.28)
		sb.set_corner_radius_all(10)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		var tr := TextureRect.new()
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tr)
		b.pressed.connect(_ver.bind(i))
		_rejilla.add_child(b)
		_miniatura_en_hilo(_fotos[i], tr)


func _miniatura_en_hilo(ruta: String, tr: TextureRect) -> void:
	var id := WorkerThreadPool.add_task(func():
		var img := Image.load_from_file(ruta)
		if img == null or img.is_empty():
			return
		var k: float = maxf(float(MINI.x) / img.get_width(), float(MINI.y) / img.get_height())
		img.resize(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)), Image.INTERPOLATE_BILINEAR)
		_poner_mini.call_deferred(tr, img))
	_tareas.append(id)


func _poner_mini(tr: TextureRect, img: Image) -> void:
	if is_instance_valid(tr):
		tr.texture = ImageTexture.create_from_image(img)


# ------------------------------------------------------------------------------------------------ pantalla completa
func _montar_completa() -> void:
	_completa = Control.new()
	_completa.set_anchors_preset(Control.PRESET_FULL_RECT)
	_completa.visible = false
	_raiz.add_child(_completa)
	var negro := ColorRect.new()
	negro.color = Color.BLACK
	negro.set_anchors_preset(Control.PRESET_FULL_RECT)
	_completa.add_child(negro)
	_img_grande = TextureRect.new()
	_img_grande.set_anchors_preset(Control.PRESET_FULL_RECT)
	_img_grande.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img_grande.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_completa.add_child(_img_grande)
	var atras := _boton("✕", Color(0, 0, 0, 0.55), func(): _completa.visible = false)
	atras.position = Vector2(24, 20)
	_completa.add_child(atras)
	var izq := _boton("‹", Color(0, 0, 0, 0.45), func(): _pasar(-1))
	izq.add_theme_font_size_override("font_size", 64)
	izq.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	izq.position = Vector2(20, -50)
	_completa.add_child(izq)
	var der := _boton("›", Color(0, 0, 0, 0.45), func(): _pasar(1))
	der.add_theme_font_size_override("font_size", 64)
	der.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	der.position = Vector2(-90, -50)
	_completa.add_child(der)
	_borrar = _boton("ELIMINAR", ROJO, _eliminar)
	_borrar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_borrar.position = Vector2(-250, 20)
	_completa.add_child(_borrar)
	# OCULTAR (pedido: "para hacerle una captura a la imagen"): se van todos los botones; tocar la foto los devuelve
	_ocultar = _boton("OCULTAR", Color(0.25, 0.2, 0.42), func(): _botones(false))
	_ocultar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_ocultar.position = Vector2(-250, 92)
	_completa.add_child(_ocultar)
	_controles = [atras, izq, der, _borrar, _ocultar]
	var volver := Button.new()
	volver.flat = true
	volver.set_anchors_preset(Control.PRESET_FULL_RECT)
	volver.focus_mode = Control.FOCUS_NONE
	volver.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	volver.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	volver.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	volver.visible = false
	volver.pressed.connect(func(): _botones(true))
	_completa.add_child(volver)
	_volver = volver


func _botones(on: bool) -> void:
	for b in _controles:
		b.visible = on
	_volver.visible = not on


func _ver(i: int) -> void:
	if i < 0 or i >= _fotos.size():
		_completa.visible = false
		return
	_idx = i
	_borrar_armado = false
	_borrar.text = "ELIMINAR"
	var img := Image.load_from_file(_fotos[i])
	_img_grande.texture = ImageTexture.create_from_image(img) if img and not img.is_empty() else null
	_completa.visible = true
	_botones(true)


func _pasar(d: int) -> void:
	if _fotos.is_empty():
		return
	_ver(posmod(_idx + d, _fotos.size()))


## Dos toques: el primero pregunta, el segundo borra
func _eliminar() -> void:
	if _idx < 0 or _idx >= _fotos.size():
		return
	if not _borrar_armado:
		_borrar_armado = true
		_borrar.text = "¿SEGURO? TOCA OTRA VEZ"
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_fotos[_idx]))
	var era := _idx
	_cargar()
	if _fotos.is_empty():
		_completa.visible = false
	else:
		_ver(mini(era, _fotos.size() - 1))


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		if _completa.visible:
			_completa.visible = false
		else:
			cerrar()
		get_viewport().set_input_as_handled()
	elif _completa.visible and e is InputEventKey and e.pressed:
		if e.keycode == KEY_LEFT:
			_pasar(-1)
		elif e.keycode == KEY_RIGHT:
			_pasar(1)


func cerrar() -> void:
	queue_free()


func _exit_tree() -> void:
	for id in _tareas:
		WorkerThreadPool.wait_for_task_completion(id)
