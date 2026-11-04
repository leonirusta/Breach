extends CanvasLayer
## LA CARTA DE BIENVENIDA (2026-10-01, pedido: "la primera vez que abres el juego, un mensaje cinematografico muy lindo,
## para que lo lean con scroll hacia abajo: que el juego fue hecho con mucho amor para la gente que le encanta la
## destruccion y el caos, que lo hizo una persona cansada de los juegos malos de la Play Store, que si compran nos ayudan
## y prometemos actualizaciones frecuentes, que les haremos caso... y algo mas con tus palabras").
## Sale UNA vez por aparato (Settings.carta_vista), en cuanto se monta el vestibulo y ENCIMA de la pantalla de carga del
## arranque (capa 124; el aviso de version nueva va en la 125, por encima): se lee mientras las paginas se calientan
## detras. Fondo negro con brasas de voxel que suben y un resplandor de fuego abajo; entra BREACH abriendo las letras,
## luego "UNA CARTA PARA TI", y cada parrafo aparece al llegar a la vista. El boton espera al final.
## Pruebas: --carta (sale aunque ya se haya visto; no guarda) y --cartafoto=<carpeta> (fotos de la entrada, la mitad y el
## final).

const ORO := Color(0.93, 0.74, 0.25)
const ORO_HEX := "#eebd40"
const ROJO_HEX := "#ff4d6d"
const TEXTO := Color(0.88, 0.87, 0.92)

## La carta. [o]...[/o] = en oro, ♥ = corazon rojo. Cada elemento, un parrafo; los dos primeros van mas grandes.
const PARRAFOS := [
	"Hola, soldado.",
	"Antes de que empieces a romperlo todo, queremos contarte algo.",
	"Breach se hizo con muchísimo amor ♥ para la gente a la que le encanta [o]la destrucción y el caos[/o]. Para los que disfrutan viendo caer un edificio entero por una sola explosión. Para los que, en vez de buscar la puerta, se abren su propio camino a martillazos.",
	"Eso es lo que Breach intenta ser: un mundo donde [o]todo se puede romper[/o], donde cada pared cuenta y ninguna partida termina igual que la anterior.",
	"Este juego lo hizo [o]una sola persona[/o]. Una persona cansada de los juegos malos de la Play Store: los que están llenos de anuncios, los que no tienen alma, los que solo existen para sacarte el dinero. Breach nació para ser todo lo contrario.",
	"Si alguna vez haces una compra, nos ayudas a mantener el juego vivo: a pagar los servidores y a poder seguir dedicándole cada día. A cambio te hacemos una promesa: [o]actualizaciones frecuentes[/o], con mapas nuevos, armas, modos y mucha, mucha más destrucción.",
	"Y vamos a escucharte. De verdad. En el botón [o]CONTACTO[/o] del vestíbulo puedes contarnos qué te gusta, qué falla y qué te gustaría ver. Leemos cada mensaje, y [o]vamos a hacer caso a todo lo que nos pidan[/o] para mejorar el juego.",
	"Juntos podemos conseguir un juego perfecto. Pero no podemos solos: [o]necesitamos tu ayuda[/o].",
	"Trae a tus amigos, forma tu escuadra y demuéstrales quién manda entre los escombros. Cada partida que juegas, cada idea que nos mandas y cada edificio que tiras abajo hacen que Breach crezca un poco más.",
	"Gracias por estar aquí desde el principio. Esto recién empieza… y va a hacer mucho ruido.",
]
const FIRMA := "Con amor ♥ y mucho caos,\n[o]el creador de Breach[/o]"

var _fondo: _Fondo
var _titulo: Label
var _var_titulo: FontVariation
var _sub: Label
var _sc: ScrollContainer
var _col: VBoxContainer
var _parrafos: Array = []
var _boton: Button
var _pista: Label
var _t := 0.0
var _listo := false                  ## ya entro el texto (se puede deslizar)
var _visto_final := false
var _vel := 0.0                      ## la inercia al soltar el dedo (px/s)
var _arrastrando := false
static var _fuente_tit: SystemFont = null


static func quiere() -> bool:
	var args := OS.get_cmdline_user_args()
	if "--carta" in args:
		return true
	for a in args:
		if String(a).begins_with("--cartafoto="):
			return true
	return args.is_empty() and not Settings.carta_vista


func _ready() -> void:
	layer = 124
	_fondo = _Fondo.new()
	_fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fondo.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_fondo)
	var tam := get_viewport().get_visible_rect().size
	var ancho := minf(820.0, tam.x - 80.0)
	# el titulo
	_var_titulo = FontVariation.new()
	_var_titulo.base_font = _titulos()
	_var_titulo.spacing_glyph = 2
	_titulo = _label("BREACH", 96, ORO, _var_titulo)
	_titulo.add_theme_constant_override("outline_size", 10)
	_titulo.add_theme_color_override("font_outline_color", Color(0.3, 0.08, 0.0, 0.55))
	_titulo.position = Vector2(tam.x * 0.5 - 400, tam.y * 0.30)
	_titulo.size = Vector2(800, 120)
	_titulo.modulate.a = 0.0
	add_child(_titulo)
	_sub = _label("UNA CARTA PARA TI", 24, Color(0.85, 0.82, 0.9), _titulos())
	_sub.position = Vector2(tam.x * 0.5 - 400, tam.y * 0.30 + 118)
	_sub.size = Vector2(800, 34)
	_sub.modulate.a = 0.0
	add_child(_sub)
	# el texto, que se desliza
	_sc = ScrollContainer.new()
	_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_sc.position = Vector2((tam.x - ancho) * 0.5, 150)
	_sc.size = Vector2(ancho, tam.y - 150)
	_sc.modulate.a = 0.0
	_sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sc.scroll_deadzone = 100000          # el arrastre con el dedo lo lleva _input (ver alli)
	add_child(_sc)
	_col = VBoxContainer.new()
	_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col.custom_minimum_size = Vector2(ancho, 0)
	_col.add_theme_constant_override("separation", 34)
	_sc.add_child(_col)
	_col.add_child(_hueco(tam.y * 0.08))
	for i in PARRAFOS.size():
		var tam_letra := 40 if i == 0 else (27 if i == 1 else 24)
		var r := _texto(String(PARRAFOS[i]), tam_letra, ancho, i == 0)
		_col.add_child(r)
		_parrafos.append(r)
	var linea := ColorRect.new()
	linea.color = Color(ORO, 0.5)
	linea.custom_minimum_size = Vector2(120, 2)
	linea.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_col.add_child(linea)
	_parrafos.append(linea)
	var firma := _texto(FIRMA, 26, ancho, false)
	firma.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(firma)
	_parrafos.append(firma)
	_boton = Button.new()
	_boton.text = "¡A ROMPERLO TODO!"
	_boton.focus_mode = Control.FOCUS_NONE
	_boton.custom_minimum_size = Vector2(420, 72)
	_boton.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_boton.add_theme_font_override("font", _titulos())
	_boton.add_theme_font_size_override("font_size", 30)
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		_boton.add_theme_color_override(k, Color(0.07, 0.04, 0.02))
	for par in [["normal", ORO], ["hover", ORO.lightened(0.12)], ["pressed", ORO.darkened(0.15)]]:
		var s := StyleBoxFlat.new()
		s.bg_color = par[1]
		s.set_corner_radius_all(14)
		s.shadow_color = Color(1.0, 0.5, 0.1, 0.35)
		s.shadow_size = 14
		_boton.add_theme_stylebox_override(par[0], s)
	_boton.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_boton.pressed.connect(_cerrar)
	_col.add_child(_boton)
	_parrafos.append(_boton)
	_col.add_child(_hueco(tam.y * 0.30))
	for p in _parrafos:
		(p as CanvasItem).modulate.a = 0.0
	# la pista de deslizar
	_pista = _label("▼   DESLIZA PARA LEER   ▼", 18, Color(1, 1, 1, 0.75), _titulos())
	_pista.position = Vector2(tam.x * 0.5 - 300, tam.y - 56)
	_pista.size = Vector2(600, 30)
	_pista.modulate.a = 0.0
	_pista.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pista)
	_entrada()
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--cartafoto="):
			_fotos(String(a).substr(12))


## LA ENTRADA DE CINE: el titulo se abre, sube y deja paso al texto
func _entrada() -> void:
	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_property(_titulo, "modulate:a", 1.0, 1.4).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_method(func(v: float): _var_titulo.spacing_glyph = int(v), 2.0, 26.0, 2.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_sub, "modulate:a", 1.0, 0.8)
	tw.tween_interval(1.3)
	# el titulo sube y se queda pequeño arriba; entra el texto
	tw.tween_property(_titulo, "position:y", 26.0, 1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(_titulo, "scale", Vector2(0.55, 0.55), 1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(_sub, "position:y", 92.0, 1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(_sub, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func():
		_listo = true
		_sc.mouse_filter = Control.MOUSE_FILTER_PASS)
	tw.tween_property(_sc, "modulate:a", 1.0, 0.8)
	tw.parallel().tween_property(_pista, "modulate:a", 1.0, 0.8)
	_titulo.pivot_offset = Vector2(400, 0)


## DESLIZAR CON EL DEDO (en el APK no se movia: la columna se quedaba el toque y el ScrollContainer no se enteraba):
## el arrastre se lleva aqui, con inercia al soltar. En el movil, el toque (ScreenDrag); en el PC, el raton apretado y la
## rueda (esa la sigue haciendo el ScrollContainer).
func _input(e: InputEvent) -> void:
	if not _listo:
		return
	var tactil := DisplayServer.is_touchscreen_available()
	if e is InputEventScreenTouch or (not tactil and e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
		_arrastrando = e.pressed
		if e.pressed:
			_vel = 0.0
	elif e is InputEventScreenDrag or (not tactil and e is InputEventMouseMotion and _arrastrando):
		var dy: float = e.relative.y
		_sc.scroll_vertical = int(_sc.scroll_vertical - dy)
		var dt := maxf(get_process_delta_time(), 0.001)
		_vel = lerpf(_vel, -dy / dt, 0.35)


func _process(dt: float) -> void:
	_t += dt
	if not _listo:
		return
	if not _arrastrando and absf(_vel) > 20.0:
		var antes := _sc.scroll_vertical
		_sc.scroll_vertical = int(_sc.scroll_vertical + _vel * dt)
		_vel *= pow(0.05, dt)
		if _sc.scroll_vertical == antes:
			_vel = 0.0
	# cada parrafo aparece (sube y se ilumina) al entrar en la vista; el boton, al final
	var abajo := _sc.global_position.y + _sc.size.y
	for p in _parrafos:
		var c := p as Control
		var dentro := clampf((abajo - c.global_position.y - 40.0) / 160.0, 0.0, 1.0)
		var a := smoothstep(0.0, 1.0, dentro)
		if a > c.modulate.a:
			c.modulate.a = move_toward(c.modulate.a, a, dt * 1.6)
	# la pista late mientras quede por leer
	var falta := _sc.get_v_scroll_bar().max_value - _sc.size.y - _sc.scroll_vertical
	if falta < 40.0:
		_visto_final = true
	_pista.modulate.a = move_toward(_pista.modulate.a, 0.0 if _visto_final else 0.55 + 0.45 * sin(_t * 3.0), dt * 3.0)
	_pista.position.y = get_viewport().get_visible_rect().size.y - 56 + sin(_t * 3.0) * 4.0


func _cerrar() -> void:
	if not ("--carta" in OS.get_cmdline_user_args()):
		Settings.carta_vista = true
		Settings.save()
	var tw := create_tween()
	for n in get_children():
		if n is CanvasItem:
			tw.parallel().tween_property(n, "modulate:a", 0.0, 0.6)
	tw.tween_callback(queue_free)


func _fotos(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var sacar := func(nombre: String):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join(nombre + ".png"))
		print("[cartafoto] " + nombre)
	await get_tree().create_timer(2.2).timeout
	await sacar.call("carta_1_titulo")
	await get_tree().create_timer(4.6).timeout
	await sacar.call("carta_2_texto")
	# un arrastre DE VERDAD (eventos de raton, como el dedo): sube 60 x 18 px y se suelta (sigue por inercia)
	var centro := get_viewport().get_visible_rect().size * 0.5
	var dedo := "--cartatactil" in OS.get_cmdline_user_args()      # con eventos de dedo (los del movil)
	var pulsa: InputEvent
	if dedo:
		pulsa = InputEventScreenTouch.new()
	else:
		pulsa = InputEventMouseButton.new()
		pulsa.button_index = MOUSE_BUTTON_LEFT
	pulsa.pressed = true
	pulsa.position = centro
	Input.parse_input_event(pulsa)
	for _i in 30:
		var mov: InputEvent
		if dedo:
			mov = InputEventScreenDrag.new()
		else:
			mov = InputEventMouseMotion.new()
			mov.button_mask = MOUSE_BUTTON_MASK_LEFT
		mov.position = centro
		mov.relative = Vector2(0, -18)
		Input.parse_input_event(mov)
		await get_tree().process_frame
	var suelta: InputEvent = pulsa.duplicate()
	suelta.pressed = false
	Input.parse_input_event(suelta)
	var tras := _sc.scroll_vertical
	await get_tree().create_timer(0.8).timeout
	print("[cartafoto] arrastre: %d px, con la inercia %d px" % [tras, _sc.scroll_vertical])
	await get_tree().create_timer(1.2).timeout
	await sacar.call("carta_3_mitad")
	for _i in 120:
		_sc.scroll_vertical += 30
		await get_tree().process_frame
	await get_tree().create_timer(1.5).timeout
	await sacar.call("carta_4_final")
	get_tree().quit()


# ---------------------------------------------------------------------------------------------------------- piezas
func _texto(t: String, tam: int, ancho: float, grande: bool) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.custom_minimum_size = Vector2(ancho, 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_size_override("normal_font_size", tam)
	r.add_theme_font_override("normal_font", _titulos() if grande else preload("res://scripts/fuentes.gd").de(500, false))
	r.add_theme_constant_override("line_separation", 6)
	r.add_theme_color_override("default_color", ORO if grande else TEXTO)
	var bb := t.replace("[o]", "[color=%s]" % ORO_HEX).replace("[/o]", "[/color]").replace("♥", "[color=%s]♥[/color]" % ROJO_HEX)
	r.text = "[center]%s[/center]" % bb
	return r


func _label(t: String, tam: int, color: Color, fuente: Font) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", fuente)
	return l


func _hueco(alto: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, alto)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func _titulos() -> Font:
	if _fuente_tit == null:
		_fuente_tit = SystemFont.new()
		_fuente_tit.font_names = PackedStringArray(["Bahnschrift", "Roboto Condensed", "sans-serif-condensed", "Arial Narrow", "sans-serif"])
		_fuente_tit.font_weight = 700
		_fuente_tit.font_stretch = 75
	return _fuente_tit


## EL FONDO: negro con un resplandor de fuego abajo y brasas de voxel que suben y parpadean
class _Fondo extends Control:
	var _brasas: Array = []
	var _t := 0.0

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 20261001
		for _i in 90:
			_brasas.append({"x": rng.randf(), "y": rng.randf(), "v": rng.randf_range(0.015, 0.06),
				"l": rng.randf_range(2.0, 7.0), "f": rng.randf() * TAU, "d": rng.randf_range(-0.01, 0.01),
				"c": Color(1.0, rng.randf_range(0.35, 0.75), rng.randf_range(0.05, 0.2))})

	func _process(dt: float) -> void:
		_t += dt
		for b in _brasas:
			b["y"] -= b["v"] * dt
			b["x"] += b["d"] * dt + sin(_t * 0.7 + b["f"]) * 0.0004
			if b["y"] < -0.02:
				b["y"] = 1.02
		queue_redraw()

	func _draw() -> void:
		var s := size
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.015, 0.03))
		# el resplandor de abajo: varios ovalos de fuego muy transparentes que respiran
		var resp := 0.85 + 0.15 * sin(_t * 0.8)
		for k in 7:
			var r := (0.95 - k * 0.11) * s.x * 0.6
			var col := Color(1.0, 0.35 + k * 0.04, 0.08, 0.045 * resp)
			draw_set_transform(Vector2(s.x * 0.5, s.y * 1.08), 0.0, Vector2(1.0, 0.42))
			draw_circle(Vector2.ZERO, r, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# las brasas: cuadraditos (voxels) con su halo
		for b in _brasas:
			var p := Vector2(b["x"] * s.x, b["y"] * s.y)
			var alto := 1.0 - clampf(b["y"], 0.0, 1.0)
			var a := (0.35 + 0.65 * (0.5 + 0.5 * sin(_t * 4.0 + b["f"]))) * (0.25 + 0.75 * (1.0 - alto))
			var l: float = b["l"]
			var c: Color = b["c"]
			draw_rect(Rect2(p - Vector2(l, l) * 1.6, Vector2(l, l) * 3.2), Color(c, a * 0.12))
			draw_rect(Rect2(p - Vector2(l, l) * 0.5, Vector2(l, l)), Color(c, a))
		# viñeta
		for k in 6:
			var g := 40.0 + k * 30.0
			draw_rect(Rect2(Vector2.ZERO, Vector2(s.x, g)), Color(0, 0, 0, 0.06))
			draw_rect(Rect2(Vector2(0, s.y - g), Vector2(s.x, g)), Color(0, 0, 0, 0.03))
