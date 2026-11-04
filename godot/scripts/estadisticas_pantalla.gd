extends CanvasLayer
## TUS ESTADISTICAS, COMO EL LOBBY (2026-10-12, pedido: "mejora la pantalla de estadisticas como el lobby"). Pantalla
## completa: el cielo azul-violeta con cubos de la entrada, arriba ESTADISTICAS con tu apodo y la X; tres tarjetas grandes
## (K/D, % de victorias, precision) y debajo las demas en tarjetas. Los numeros: estadisticas.gd `valores()` (por cuenta;
## partidas y victorias, las del servidor). La abre la tecla ESTADISTICAS del vestibulo (lobby._abrir_estadisticas).
## Foto: --estadisticasfoto=ruta.png

const Estadisticas := preload("res://scripts/estadisticas.gd")
const TINTA := Color8(22, 16, 46)
const CAJA := Color(0.09, 0.06, 0.15, 0.78)
const VIOLETA := Color8(116, 100, 238)
const VIOLETA_OSC := Color8(80, 62, 196)
const AZUL := Color8(52, 122, 246)
const AMARILLO := Color8(255, 208, 58)
const ROSA := Color8(222, 62, 124)
const VERDE := Color8(46, 190, 80)
const NARANJA := Color8(246, 160, 30)
const LILA := Color8(190, 180, 248)
const CIAN := Color8(80, 210, 240)

signal cerrado


static func _letra(peso: int, cursiva: bool) -> Font:
	return preload("res://scripts/fuentes.gd").de(peso, cursiva)


func _ready() -> void:
	layer = 110
	var raiz := Control.new()
	raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	raiz.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(raiz)
	_cielo(raiz)
	var marco := MarginContainer.new()
	marco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for lado in ["left", "right"]:
		marco.add_theme_constant_override("margin_" + lado, 40)
	marco.add_theme_constant_override("margin_top", 22)
	marco.add_theme_constant_override("margin_bottom", 26)
	raiz.add_child(marco)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	marco.add_child(col)

	# --- la cabecera: ESTADISTICAS, quien eres, la X ---
	var cab := HBoxContainer.new()
	cab.add_theme_constant_override("separation", 16)
	col.add_child(cab)
	var tits := VBoxContainer.new()
	tits.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tits.add_theme_constant_override("separation", -4)
	cab.add_child(tits)
	tits.add_child(_rotulo("ESTADÍSTICAS", 46, AMARILLO, HORIZONTAL_ALIGNMENT_LEFT))
	var quien := "SIN CUENTA · LAS DE ESTE APARATO"
	if Cuenta.conectado():
		quien = "%s · NIVEL %d" % [Cuenta.nombre().to_upper(), Cuenta.nivel()]
	tits.add_child(_rotulo(quien, 18, LILA, HORIZONTAL_ALIGNMENT_LEFT))
	var x := _boton_x()
	cab.add_child(x)

	var v := Estadisticas.valores()
	var bajas_tot: int = int(v["bajas"]) + int(v["bajas_zombis"])
	var kd: float = float(bajas_tot) / maxf(1.0, float(v["muertes"]))
	var jugadas: int = int(v["victorias"]) + int(v["derrotas"])
	var pct_vic: float = 100.0 * float(v["victorias"]) / maxf(1.0, float(jugadas))
	var prec: float = 100.0 * float(v["aciertos"]) / maxf(1.0, float(v["disparos"]))
	var seg: int = int(v["segundos"])

	# --- las tres grandes ---
	var grandes := HBoxContainer.new()
	grandes.add_theme_constant_override("separation", 18)
	grandes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(grandes)
	grandes.add_child(_tarjeta_grande("K/D", "%.2f" % kd, "%d bajas · %d muertes" % [bajas_tot, int(v["muertes"])], ROSA))
	grandes.add_child(_tarjeta_grande("VICTORIAS", "%.0f%%" % pct_vic, "%d de %d partidas" % [int(v["victorias"]), jugadas], VERDE))
	grandes.add_child(_tarjeta_grande("PRECISIÓN", "%.0f%%" % prec, "%d aciertos de %d disparos" % [int(v["aciertos"]), int(v["disparos"])], CIAN))

	# --- las demas ---
	var rejilla := GridContainer.new()
	rejilla.columns = 4
	rejilla.add_theme_constant_override("h_separation", 14)
	rejilla.add_theme_constant_override("v_separation", 14)
	col.add_child(rejilla)
	var fav := String(v["mapa_favorito"])
	var fav_t := "-" if fav == "-" else Settings.map_title(fav).to_upper()
	for d in [["PARTIDAS", str(v["partidas"]), AMARILLO], ["BAJAS", str(v["bajas"]), ROSA],
			["BAJAS DE ZOMBI", str(v["bajas_zombis"]), VERDE], ["MUERTES", str(v["muertes"]), LILA],
			["MEJOR RACHA", "%d" % int(v["mejor_racha"]), NARANJA], ["OLEADA MÁS ALTA", str(v["oleada_max"]), VERDE],
			["TIEMPO JUGADO", "%dh %02dm" % [seg / 3600, (seg / 60) % 60], AZUL.lightened(0.25)],
			["MAPA FAVORITO", fav_t, VIOLETA.lightened(0.25)]]:
		rejilla.add_child(_tarjeta(String(d[0]), String(d[1]), d[2]))
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--estadisticasfoto="):
			_foto.call_deferred(String(a).substr(19))


func _foto(ruta: String) -> void:
	for _i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ruta)
	print("[estadisticasfoto] %s" % ruta)
	get_tree().quit()


func cerrar() -> void:
	cerrado.emit()
	queue_free()


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cerrar()


# --- piezas -------------------------------------------------------------------------------------------------------
func _cielo(padre: Control) -> void:
	var g := Gradient.new()
	g.set_color(0, AZUL.darkened(0.15))
	g.set_color(1, VIOLETA_OSC.darkened(0.45))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	var cielo := TextureRect.new()
	cielo.texture = gt
	cielo.stretch_mode = TextureRect.STRETCH_SCALE
	cielo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	padre.add_child(cielo)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 18:
		var cubo := Panel.new()
		var ec := StyleBoxFlat.new()
		ec.bg_color = Color(1, 1, 1, rng.randf_range(0.04, 0.10))
		ec.border_color = Color(1, 1, 1, 0.16)
		ec.set_border_width_all(2)
		ec.set_corner_radius_all(4)
		cubo.add_theme_stylebox_override("panel", ec)
		var lado := rng.randf_range(26, 90)
		cubo.size = Vector2(lado, lado)
		cubo.anchor_left = rng.randf()
		cubo.anchor_top = rng.randf()
		cubo.anchor_right = cubo.anchor_left
		cubo.anchor_bottom = cubo.anchor_top
		cubo.rotation = rng.randf_range(-0.6, 0.6)
		cubo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		padre.add_child(cubo)


func _rotulo(t: String, tam: int, c: Color, al := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = al
	l.add_theme_font_override("font", _letra(900, true))
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	l.add_theme_constant_override("shadow_offset_y", 3)
	return l


func _caja(acento: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var e := StyleBoxFlat.new()
	e.bg_color = CAJA
	e.border_color = acento
	e.border_width_bottom = 6
	e.border_width_top = 2
	e.border_width_left = 2
	e.border_width_right = 2
	e.set_corner_radius_all(18)
	e.content_margin_left = 18
	e.content_margin_right = 18
	e.content_margin_top = 12
	e.content_margin_bottom = 14
	p.add_theme_stylebox_override("panel", e)
	return p


func _tarjeta_grande(titulo: String, valor: String, detalle: String, acento: Color) -> Control:
	var p := _caja(acento)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	v.add_child(_rotulo(titulo, 22, acento))
	v.add_child(_rotulo(valor, 72, Color.WHITE))
	var d := _rotulo(detalle, 15, LILA)
	d.add_theme_font_override("font", _letra(700, false))
	v.add_child(d)
	return p


func _tarjeta(titulo: String, valor: String, acento: Color) -> Control:
	var p := _caja(acento)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size = Vector2(0, 104)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	v.add_child(_rotulo(titulo, 15, acento))
	var n := _rotulo(valor, 34, Color.WHITE)
	n.clip_text = true
	v.add_child(n)
	return p


func _boton_x() -> Button:
	var b := Button.new()
	b.text = "✕"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(64, 64)
	b.add_theme_font_override("font", _letra(900, false))
	b.add_theme_font_size_override("font_size", 30)
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, Color.WHITE)
	for par in [["normal", ROSA, 6], ["hover", ROSA.lightened(0.1), 6], ["pressed", ROSA.darkened(0.08), 2]]:
		var e := StyleBoxFlat.new()
		e.bg_color = par[1]
		e.border_color = ROSA.darkened(0.4)
		e.border_width_bottom = int(par[2])
		e.set_corner_radius_all(16)
		b.add_theme_stylebox_override(String(par[0]), e)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cerrar)
	return b
