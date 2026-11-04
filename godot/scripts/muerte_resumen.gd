extends CanvasLayer
## EL RESUMEN DE MUERTE (2026-09-28, pedido: "cuando alguien me elimina aparece una animacion hermosa, me
## visualiza al enemigo que me mato y la informacion de quien es"). Mientras la camara de muerte sigue a quien
## te ha matado (player._update_spectate), entra por la izquierda un panel con SU muñeco en 3D (su aspecto y su
## arma), su nombre y la vida que le has dejado, con que te ha matado, las bajas y el daño entre los dos
## (duelo.gd), arriba la CAUSA DE MUERTE y abajo a la derecha la cuenta atras para volver con el boton
## "IR A BATALLA" (o SALTAR/ESPACIO). Lo crea player.gd al morir y se borra solo.
##
## Todo se dibuja a 1920x1080 y se escala a la altura de la pantalla (vale igual en el movil).

signal ir_a_batalla

const AvatarScript := preload("res://scripts/avatar_animator.gd")
const IconScript := preload("res://scripts/weapon_icon.gd")

const MORADO_A := Color(0.47, 0.42, 0.93, 0.96)
const MORADO_B := Color(0.33, 0.27, 0.80, 0.96)
const LILA := Color(0.80, 0.78, 1.0)
const AZUL := Color(0.24, 0.55, 1.0)
const ROJO := Color(0.93, 0.22, 0.36)
const AMARILLO := Color(1.0, 0.84, 0.18)

var datos: Dictionary = {}
var dur := 5.0
var _t := 0.0
var _raiz: Control
var _panel: Control
var _banner: Control
var _abajo: Control
var _vp: SubViewport
var _vp_acum := 1.0
var _muneco: Node3D
var _cuenta: Label
var _boton: Button
var _numeros: Array = []          ## [Label, valor, formato]
var _cerrando := false


## datos: nombre, tipo ("JUGADOR"/"BOT"), vida, vida_max, aspecto ([alto, tinte, skin_id, receta]), arma_kind,
## arma_id, arma_nombre, causa, yo_mato, me_mata, hecho, recibido, reaparece (bool)
static func mostrar(padre: Node, d: Dictionary, segundos: float) -> CanvasLayer:
	var m = load("res://scripts/muerte_resumen.gd").new()
	m.datos = d
	m.dur = segundos
	padre.add_child(m)
	return m


func _ready() -> void:
	layer = 40
	_raiz = Control.new()
	_raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_raiz)
	_escalar()
	get_viewport().size_changed.connect(_escalar)
	_montar_panel()
	_montar_banner()
	_montar_abajo()
	_entrada()


func _escalar() -> void:
	var tam: Vector2 = get_viewport().get_visible_rect().size
	var k: float = tam.y / 1080.0
	_raiz.scale = Vector2(k, k)
	_raiz.size = Vector2(tam.x / k, 1080.0)


func _ancho() -> float:
	return _raiz.size.x


# ------------------------------------------------------------------------------------------------ piezas
func _label(t: String, tam: int, color: Color, padre: Node, pos: Vector2, sombra := true) -> Label:
	var l := Label.new()
	l.text = t
	l.position = pos
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	if sombra:
		l.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.3, 0.85))
		l.add_theme_constant_override("outline_size", maxi(4, tam / 6))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	padre.add_child(l)
	return l


## Un poligono inclinado relleno (las cajas de los numeros, el boton, el cartel)
func _sesgo(padre: Node, pos: Vector2, tam: Vector2, color: Color, inclina := 16.0) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([Vector2(inclina, 0), Vector2(tam.x, 0), Vector2(tam.x - inclina, tam.y), Vector2(0, tam.y)])
	p.color = color
	p.position = pos
	padre.add_child(p)
	return p


func _montar_panel() -> void:
	_panel = Control.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(_panel)
	var w := 820.0
	# el fondo: morado con degradado y el filo en diagonal. TODO lo del panel queda por dentro del filo
	var fondo := Polygon2D.new()
	fondo.polygon = PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w - 140, 1080), Vector2(0, 1080)])
	fondo.vertex_colors = PackedColorArray([MORADO_A, MORADO_B, MORADO_B.darkened(0.15), MORADO_A.darkened(0.1)])
	_panel.add_child(fondo)
	# EL MUÑECO: su aspecto y su arma, en un mundo propio, quieto y de tres cuartos
	_vp = SubViewport.new()
	_vp.size = Vector2i(520, 820)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X
	# el muñeco a 30 por segundo (en _process): a cada fotograma era lo que daba el tiron
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_panel.add_child(_vp)
	_montar_muneco()
	var tex := TextureRect.new()
	tex.texture = _vp.get_texture()
	tex.position = Vector2(-10, 250)
	tex.size = Vector2(520, 820)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(tex)
	# QUIEN: "ELIMINADO POR", el nombre, si es persona o bot y la vida que le queda
	_label("ELIMINADO POR", 34, LILA, _panel, Vector2(150, 150))
	var cara := _sesgo(_panel, Vector2(90, 205), Vector2(92, 92), Color(0.18, 0.13, 0.45), 0.0)
	# (un bot no enseña su nombre: "ENEMIGO")
	var visto := Net.nombre_para_ver(String(datos.get("nombre", "")), "ENEMIGO")
	var ini := visto.substr(0, 1).to_upper()
	_label(ini, 60, Color.WHITE, cara, Vector2(26, 6))
	_label(visto, 52, Color.WHITE, _panel, Vector2(200, 198))
	if String(datos.get("tipo", "JUGADOR")) != "BOT":       # a un bot no se le pone "BOT" (pedido)
		_label(String(datos.get("tipo", "JUGADOR")), 34, Color(0.98, 0.9, 0.5), _panel, Vector2(202, 256))
	var vida: float = float(datos.get("vida", 0.0))
	var vmax: float = maxf(1.0, float(datos.get("vida_max", 100.0)))
	var corazon := _label("♥", 50, ROJO, _panel, Vector2(95, 305))
	corazon.add_theme_color_override("font_outline_color", Color(0.3, 0.02, 0.08))
	var llenos := int(ceil(12.0 * clampf(vida / vmax, 0.0, 1.0)))
	for i in 12:
		_sesgo(_panel, Vector2(150 + i * 26, 322), Vector2(22, 34), ROJO if i < llenos else Color(1, 1, 1, 0.25), 5.0)
	# CON QUE: la tarjeta con el icono del arma (sacado del modelo 3D, como en la barra de armas)
	var x0 := 420.0
	_label("ELIMINADO CON", 34, Color.WHITE, _panel, Vector2(x0 + 10, 470))
	var dentro := Control.new()
	dentro.position = Vector2(x0, 520)
	dentro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(dentro)
	var kind := String(datos.get("arma_kind", ""))
	if kind == "" or kind == "grenade":
		var gr := IconoGranada.new()
		gr.position = Vector2(125, 70)
		gr.scale = Vector2(2.2, 2.2)
		dentro.add_child(gr)
	else:
		var ivp: SubViewport = IconScript.make(kind, String(datos.get("arma_id", "")), 110)
		_panel.add_child(ivp)
		var it := TextureRect.new()
		it.texture = ivp.get_texture()
		it.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		it.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		it.position = Vector2(0, 0)
		it.size = Vector2(250, 150)
		dentro.add_child(it)
	var an := _label(String(datos.get("arma_nombre", "")).to_upper(), 26, Color.WHITE, dentro, Vector2(0, 150))
	an.size = Vector2(250, 40)
	an.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	an.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# LAS CUENTAS ENTRE LOS DOS
	_label("BAJAS ENTRE VOSOTROS", 30, LILA, _panel, Vector2(x0 - 70, 770))
	_fila(Vector2(x0 - 90, 814), "TÚ", int(datos.get("yo_mato", 0)), int(datos.get("me_mata", 0)), "ÉL", "%d")
	_label("DAÑO ENTRE VOSOTROS", 30, LILA, _panel, Vector2(x0 - 70, 890))
	_fila(Vector2(x0 - 110, 934), "", float(datos.get("hecho", 0.0)), float(datos.get("recibido", 0.0)), "", "%d")


func _fila(pos: Vector2, izq: String, a: float, b: float, der: String, fmt: String) -> void:
	var f := Control.new()
	f.position = pos
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(f)
	var g := Polygon2D.new()
	g.polygon = PackedVector2Array([Vector2(0, 0), Vector2(210, 0), Vector2(210, 58), Vector2(20, 58)])
	g.vertex_colors = PackedColorArray([Color(AZUL, 0.0), AZUL, AZUL, Color(AZUL, 0.0)])
	f.add_child(g)
	_sesgo(f, Vector2(210, 0), Vector2(150, 58), ROJO, 14.0)
	if izq != "":
		_label(izq, 34, Color(0.8, 0.88, 1.0), f, Vector2(30, 6))
	var la := _label("0", 44, Color.WHITE, f, Vector2(105, 0))
	la.size = Vector2(95, 58)
	la.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var lb := _label("0", 44, Color.WHITE, f, Vector2(222, 0))
	if der != "":
		_label(der, 34, Color(1.0, 0.85, 0.9), f, Vector2(292, 6))
	_numeros.append([la, a, fmt])
	_numeros.append([lb, b, fmt])


func _montar_muneco() -> void:
	var mundo := Node3D.new()
	_vp.add_child(mundo)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.72, 0.95)
	e.ambient_light_energy = 0.9
	env.environment = e
	mundo.add_child(env)
	var sol := DirectionalLight3D.new()
	sol.rotation = Vector3(-0.6, 0.5, 0.0)
	sol.light_energy = 1.4
	mundo.add_child(sol)
	var contra := DirectionalLight3D.new()
	contra.rotation = Vector3(-0.3, PI + 0.6, 0.0)
	contra.light_energy = 0.8
	contra.light_color = Color(0.7, 0.8, 1.0)
	mundo.add_child(contra)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 0.95, 4.3)
	mundo.add_child(cam)
	cam.look_at(Vector3(0, 0.82, 0))
	cam.current = true
	_muneco = AvatarScript.new()
	mundo.add_child(_muneco)
	var asp: Array = datos.get("aspecto", [])
	if asp.size() >= 4:
		_muneco.build(float(asp[0]), false, asp[1], false, false, String(asp[2]), asp[3])
	else:
		_muneco.build(AvatarScript.ALTURA, false, Color.WHITE, false)
	_muneco.rotation.y = PI - 0.3          # el muñeco mira a -Z: media vuelta para verle la cara, y de tres cuartos
	preload("res://scripts/lobby.gd").sin_arma_lobby(_muneco)   # de pie y sin arma (pedido)


func _montar_banner() -> void:
	_banner = Control.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(_banner)
	var w := 640.0
	_banner.position = Vector2(_ancho() * 0.5 + 170, 300)
	_banner.pivot_offset = Vector2(0, 0)
	_sesgo(_banner, Vector2(-w * 0.5, -70), Vector2(w, 140), ROJO, 22.0)
	# el sello de la calavera, que entra girando y late
	var cal := _Calavera.new()
	cal.position = Vector2(-w * 0.5 + 40, 0)
	cal.rotation = -0.6
	cal.scale = Vector2(0.3, 0.3)
	_banner.add_child(cal)
	var tc := cal.create_tween()
	tc.tween_interval(0.3)
	tc.tween_property(cal, "rotation", 0.0, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tc.parallel().tween_property(cal, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var lat := func(k: float) -> void:
		if is_instance_valid(cal):
			cal.pulso = maxf(0.0, sin(k * TAU * 3.0))
			cal.queue_redraw()
	tc.tween_method(lat, 0.0, 1.0, 1.2)
	_label("CAUSA DE MUERTE", 32, Color.WHITE, _banner, Vector2(-w * 0.5 + 140, -58), false)
	_label(String(datos.get("causa", "DISPARO")), 64, Color.WHITE, _banner, Vector2(-w * 0.5 + 138, -24))


func _montar_abajo() -> void:
	_abajo = Control.new()
	_abajo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(_abajo)
	_abajo.position = Vector2(_ancho() - 560, 820)
	if not bool(datos.get("reaparece", false)):
		_cuenta = _label("", 40, Color.WHITE, _abajo, Vector2(40, 110))
		return
	_cuenta = _label("", 44, Color.WHITE, _abajo, Vector2(40, 0))
	_boton = Button.new()
	_boton.flat = true
	_boton.focus_mode = Control.FOCUS_NONE
	_boton.position = Vector2(20, 70)
	_boton.size = Vector2(500, 130)
	_abajo.add_child(_boton)
	_sesgo(_boton, Vector2.ZERO, Vector2(500, 130), AMARILLO, 0.0)
	_sesgo(_boton, Vector2(0, 118), Vector2(500, 12), AMARILLO.darkened(0.3), 0.0)
	var t := _label("IR A BATALLA", 62, Color(0.12, 0.1, 0.25), _boton, Vector2(0, 22), false)
	t.size = Vector2(500, 90)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var h := _label("[ESPACIO]", 22, Color(0.3, 0.26, 0.1), _boton, Vector2(0, 94), false)
	h.size = Vector2(500, 30)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boton.pressed.connect(func(): ir_a_batalla.emit())


# ------------------------------------------------------------------------------------------------ vida
func _entrada() -> void:
	_panel.position.x = -900.0
	var tw := create_tween()
	tw.tween_property(_panel, "position:x", 0.0, 0.45).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_banner.scale = Vector2(0.2, 0.2)
	_banner.modulate.a = 0.0
	var tb := create_tween()
	tb.tween_interval(0.25)
	tb.tween_property(_banner, "modulate:a", 1.0, 0.15)
	tb.parallel().tween_property(_banner, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_abajo.position.x += 600.0
	var ta := create_tween()
	ta.tween_interval(0.35)
	ta.tween_property(_abajo, "position:x", _abajo.position.x - 600.0, 0.4).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


func _process(dt: float) -> void:
	_t += dt
	_vp_acum += dt
	if is_instance_valid(_muneco) and _vp_acum >= 1.0 / 30.0:
		_muneco.drive_locomotion(Vector3.ZERO, false, true, 0, _vp_acum)
		_vp_acum = 0.0
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	# los numeros suben de cero a su valor
	var k := clampf((_t - 0.45) / 0.7, 0.0, 1.0)
	for n in _numeros:
		(n[0] as Label).text = String(n[2]) % int(round(float(n[1]) * k))
	var queda := maxf(0.0, dur - _t)
	if _cuenta:
		if bool(datos.get("reaparece", false)):
			_cuenta.text = "REAPARICIÓN EN %d S" % int(ceil(queda))
		else:
			_cuenta.text = ""
	if not _cerrando and _t >= dur:
		cerrar()


func cerrar() -> void:
	if _cerrando:
		return
	_cerrando = true
	var tw := create_tween()
	tw.tween_property(_panel, "position:x", -900.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_banner, "modulate:a", 0.0, 0.25)
	tw.parallel().tween_property(_abajo, "modulate:a", 0.0, 0.25)
	tw.tween_callback(queue_free)


## LA CALAVERA DEL CARTEL: craneo con pomulos y sienes, cuencas en angulo, la nariz, la fila de dientes y la
## mandibula, en blanco con un filo oscuro, dentro de un sello rojo con estallido. Dibujada con poligonos porque la
## fuente no tiene el simbolo. `pulso` la hace latir un poco al salir.
class _Calavera extends Node2D:
	var pulso := 0.0

	static func _elipse(c: Vector2, rx: float, ry: float, giro: float, n := 20) -> PackedVector2Array:
		var p := PackedVector2Array()
		for i in n:
			var a := TAU * i / n
			p.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(giro))
		return p

	func _draw() -> void:
		var rojo := Color(0.86, 0.13, 0.27)
		var hueso := Color(1.0, 0.97, 0.92)
		var filo := Color(0.35, 0.02, 0.1)
		# el sello: estallido blanco de puntas desiguales y un disco rojo dentro
		var est := PackedVector2Array()
		for i in 28:
			var a := TAU * i / 28.0 - PI / 2
			var r := (74.0 if i % 4 == 0 else 62.0) if i % 2 == 0 else 46.0
			est.append(Vector2(cos(a), sin(a)) * r * (1.0 + pulso * 0.08))
		draw_colored_polygon(est, Color.WHITE)
		draw_circle(Vector2.ZERO, 44.0, rojo)
		draw_arc(Vector2.ZERO, 44.0, 0.0, TAU, 40, filo, 3.0, true)
		# el craneo (un poco mas grande que el disco deja): la boveda, las sienes que se estrechan y los pomulos
		draw_set_transform(Vector2(0, -1), 0.0, Vector2(1.12, 1.12))
		var craneo := _elipse(Vector2(0, -8), 25.0, 23.0, 0.0, 28)
		var cara := PackedVector2Array([Vector2(-24, -6), Vector2(24, -6), Vector2(22, 6), Vector2(17, 13), Vector2(15, 20),
			Vector2(-15, 20), Vector2(-17, 13), Vector2(-22, 6)])
		draw_colored_polygon(craneo, hueso)
		draw_colored_polygon(cara, hueso)
		# la mandibula, un pelo separada, con los dientes
		var mand := PackedVector2Array([Vector2(-13, 22), Vector2(13, 22), Vector2(12, 31), Vector2(-12, 31)])
		draw_colored_polygon(mand, hueso)
		draw_line(Vector2(-14, 21), Vector2(14, 21), rojo, 2.0)
		for x in [-6.5, 0.0, 6.5]:
			draw_line(Vector2(x, 16), Vector2(x, 30), rojo, 2.2)
		# las cuencas, grandes y rasgadas hacia dentro (mirada dura), y la nariz en punta
		draw_colored_polygon(_elipse(Vector2(-10, -3), 8.5, 7.5, 0.3), rojo)
		draw_colored_polygon(_elipse(Vector2(10, -3), 8.5, 7.5, -0.3), rojo)
		draw_colored_polygon(PackedVector2Array([Vector2(0, 4), Vector2(-4.5, 12.5), Vector2(0, 10.5), Vector2(4.5, 12.5)]), rojo)
		# el filo oscuro alrededor de todo el hueso: la boveda de izquierda a derecha por arriba y la cara por abajo
		var contorno := PackedVector2Array()
		for i in 21:
			var a := PI - 0.26 + (PI + 0.52) * i / 20.0
			contorno.append(Vector2(0, -8) + Vector2(cos(a) * 25.0, sin(a) * 23.0))
		contorno.append_array(PackedVector2Array([Vector2(22, 6), Vector2(17, 13), Vector2(15, 20), Vector2(13, 22),
			Vector2(12, 31), Vector2(-12, 31), Vector2(-13, 22), Vector2(-15, 20), Vector2(-17, 13), Vector2(-22, 6)]))
		contorno.append(contorno[0])
		draw_polyline(contorno, filo, 2.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## LA GRANADA: cuerpo ovalado con las estrias, la cuchara y la anilla. Para cuando te mata una explosion que no
## es de un lanzacohetes (no hay modelo 3D de la granada). `color`: blanco en el registro de bajas.
class IconoGranada extends Node2D:
	var color := Color(0.35, 0.42, 0.22)

	func _draw() -> void:
		var cuerpo := PackedVector2Array()
		for i in 24:
			var a := TAU * i / 24.0
			cuerpo.append(Vector2(cos(a) * 15.0, sin(a) * 19.0 + 6.0))
		draw_colored_polygon(cuerpo, color)
		var raya := Color(0, 0, 0, 0.35) if color != Color.WHITE else Color(0.1, 0.1, 0.15, 0.6)
		for y in [-2.0, 6.0, 14.0]:
			draw_line(Vector2(-14, y), Vector2(14, y), raya, 2.0)
		draw_line(Vector2(0, -12), Vector2(0, 24), raya, 2.0)
		draw_rect(Rect2(-6, -19, 12, 7), color)
		draw_colored_polygon(PackedVector2Array([Vector2(4, -18), Vector2(20, -12), Vector2(19, 4), Vector2(15, 4), Vector2(15, -10), Vector2(4, -14)]), color)
		draw_arc(Vector2(-10, -20), 6.0, 0.0, TAU, 16, color, 2.5, true)
