class_name Boton
extends Button
## UN BOTON DEL PANEL: fondo segun el ESTILO, y el icono y el texto pintados a mano, centrados juntos.
## Se escucha `tocado`, no `pressed`: si el dedo estaba arrastrando una lista, soltar encima no cuenta.
##   estilo: "primario" (amarillo), "secundario" (gris), "fantasma" (solo el borde), "peligro" (rojo),
##           "texto" (sin fondo), "icono" (redondo, solo icono)

signal tocado

var texto := "":
	set(v):
		texto = v
		_medir()
		queue_redraw()
var icono := "":
	set(v):
		icono = v
		_medir()
		queue_redraw()
var estilo := "secundario":
	set(v):
		estilo = v
		_estilos()
		queue_redraw()
var tam := 16
var color_icono := Color.TRANSPARENT     ## si no, el del texto
var cargando := false:
	set(v):
		cargando = v
		disabled = v
		set_process(v)
		queue_redraw()
var _giro := 0.0


func _init(p_texto := "", p_icono := "", p_estilo := "secundario", alto := 50.0) -> void:
	texto = p_texto
	icono = p_icono
	custom_minimum_size.y = alto
	estilo = p_estilo
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_PASS
	action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	pressed.connect(func():
		if not Tema.arrastrando:
			tocado.emit())
	_medir()
	set_process(false)


func _estilos() -> void:
	var bg := Tema.SUP3
	var borde := Color.TRANSPARENT
	var r := 12.0
	match estilo:
		"primario":
			bg = Tema.ACENTO
		"peligro":
			bg = Color(Tema.PELIGRO, 0.16)
			borde = Color(Tema.PELIGRO, 0.5)
		"fantasma":
			bg = Color(0, 0, 0, 0)
			borde = Tema.BORDE
		"texto":
			bg = Color(0, 0, 0, 0)
		"icono":
			bg = Color(0, 0, 0, 0)
			r = 30.0
		"sel":
			bg = Color(Tema.ACENTO, 0.14)
			borde = Color(Tema.ACENTO, 0.8)
		"fila":
			bg = Tema.SUP
			borde = Tema.BORDE
			r = 16.0
	var ab := 1 if borde.a > 0.0 else 0
	add_theme_stylebox_override("normal", Tema.caja(bg, r, borde, ab))
	add_theme_stylebox_override("hover", Tema.caja(bg.lightened(0.08) if bg.a > 0.5 else Color(1, 1, 1, 0.05), r, borde, ab))
	add_theme_stylebox_override("pressed", Tema.caja(bg.darkened(0.18) if bg.a > 0.5 else Color(1, 1, 1, 0.10), r, borde, ab))
	add_theme_stylebox_override("disabled", Tema.caja(Color(bg, bg.a * 0.45), r, Color(borde, borde.a * 0.5), ab))
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _color_texto() -> Color:
	match estilo:
		"primario":
			return Color("16130a")
		"peligro":
			return Tema.PELIGRO
		"texto", "sel":
			return Tema.ACENTO
		"fantasma":
			return Tema.TEXTO2
	return Tema.TEXTO


func _medir() -> void:
	var f := Tema.fuente(600)
	var tw := f.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x if texto != "" else 0.0
	var iw := tam * 1.2 if icono != "" else 0.0
	var gap := 9.0 if icono != "" and texto != "" else 0.0
	custom_minimum_size.x = maxf(custom_minimum_size.y if texto == "" else 0.0, tw + iw + gap + (36.0 if texto != "" else 0.0))


func _process(dt: float) -> void:
	_giro += dt * 7.0
	queue_redraw()


func _draw() -> void:
	var col := _color_texto()
	if disabled and not cargando:
		col = Color(col, 0.4)
	if cargando:
		var c := size * 0.5
		draw_arc(c, 9, _giro, _giro + PI * 1.4, 24, col, 2.5, true)
		return
	var f := Tema.fuente(600)
	var tw := f.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x if texto != "" else 0.0
	var iw := tam * 1.2 if icono != "" else 0.0
	if estilo == "icono":
		iw = minf(size.x, size.y) * 0.44
	var gap := 9.0 if icono != "" and texto != "" else 0.0
	var x := (size.x - (iw + gap + tw)) * 0.5
	if icono != "":
		Iconos.dibujar(self, icono, Rect2(x, (size.y - iw) * 0.5, iw, iw), color_icono if color_icono.a > 0.0 else col)
	if texto != "":
		var y := (size.y + f.get_ascent(tam) - f.get_descent(tam)) * 0.5
		draw_string(f, Vector2(x + iw + gap, y), texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, col)
