extends CanvasLayer
const FinIntroFondo := preload("res://scripts/fin_intro.gd")
## MEJORES JUGADORES (2026-09-28, pedido con una foto): despues de la pantalla de nivel (fin_nivel.gd) y antes del
## resultado. Cinco TARJETAS inclinadas, el primero en el centro y los demas a los lados (4 2 1 3 5), que aparecen
## de una en una: una raya de luz dorada traza el contorno (como el rayo de fin_intro.gd), la tarjeta se llena con
## un golpe y sale su personaje. En cada una: el puesto (con laureles los tres primeros), MVP / TU, el personaje en
## 3D con su aspecto y su arma, el boton de ME GUSTA con la cuenta, el nombre, el rango, los PUNTOS y un titulo con
## su frase. Los me gusta viajan por red (Net.net_like) y al que se lo dan le sale el aviso "te dio like".
## Tocar otra vez el pulgar QUITA el me gusta (como mucho uno por jugador y partida); al cerrar, los que quedaron se
## apuntan en la cuenta de cada uno (POST /likes).
## LAS DOS RAYITAS (2026-09-30): en la tarjeta de cada persona (no en la tuya ni en la de un bot) abren el menu de
## opciones_jugador.gd: ENVIAR SOLICITUD de amistad (el boton pasa a un check) o REPORTAR (casillas y mensaje).
## RECLAMAR RECOMPENSA (o ESPACIO) sigue. Se dibuja a 1920x1080 y se escala a la altura de la pantalla.

signal terminado

const AvatarScript := preload("res://scripts/avatar_animator.gd")
const FinIntro := preload("res://scripts/fin_intro.gd")
const Opciones := preload("res://scripts/opciones_jugador.gd")
const ORO := Color(1.0, 0.8, 0.2)
const ANCHO_T := 318.0          ## ancho de una tarjeta
const ALTO_T := 700.0
const INCLINA := 70.0           ## lo que se desplaza el borde de arriba respecto al de abajo
const Y_T := 150.0              ## donde empiezan las tarjetas
const PASO := 344.0             ## de centro a centro
const ORDEN := [3, 1, 0, 2, 4]  ## de izquierda a derecha: el 4.º, el 2.º, el 1.º, el 3.º y el 5.º
const METROS_PX := 190.0        ## escala de los muñecos (camara ortogonal)

## Los titulos por puesto: [titulo, frase, color del titulo]
const TITULOS := [
	["MVP", "Jugador más valioso", Color(1.0, 0.86, 0.35)],
	["ASISTENTE DE ORO", "Irremplazable segundo al mando del éxito", Color(1.0, 0.62, 0.3)],
	["BASTIÓN DE ACERO", "Un pilar del equipo en la batalla", Color(0.55, 0.85, 1.0)],
	["AS DE LO OCULTO", "Desde las sombras, dio vuelta el juego", Color(1.0, 0.6, 0.35)],
	["TALISMÁN DE SUERTE", "Trajo suerte a todo el equipo", Color(1.0, 0.6, 0.35)],
]

var tema := ""                   ## "" o "zombi"
var jugadores: Array = []       ## [{nombre, puntos, es_yo, tipo, nivel, aspecto, arma}] ya ordenados
## Los me gusta de la partida, para la pantalla final (victoria_final.gd): nombre -> cuantos
static var likes_partida: Dictionary = {}
var _raiz: Control
var _w := 1920.0
var _tarjetas: Array = []       ## Node2D por puesto
var _munecos: Array = []        ## Node3D por puesto
var _likes: Dictionary = {}     ## nombre -> [cuenta, Label, _Pulgar]
var _dados: Dictionary = {}     ## nombres a los que YA he dado like
var _avisados: Dictionary = {}  ## quien ya me ha dado like (el aviso sale una vez aunque lo quite y lo vuelva a dar)
## La partida, para los reportes (main.secuencia_fin la pone): {clave, mapa, modo, sala, sala_nombre}
var info_partida: Dictionary = {}
var _estados: Dictionary = {}   ## nombre -> lo que recuerda el menu de ese jugador ({amistad, reportado})
var _rayas: Dictionary = {}     ## nombre -> el boton de las rayitas
var _menu: Control = null
var _vp: SubViewport
var _t := 0.0
var _cerrando := false
var _toast_y := 0.0


static func mostrar(padre: Node, p_jugadores: Array, p_tema := "") -> CanvasLayer:
	var f = load("res://scripts/mejores_jugadores.gd").new()
	f.jugadores = p_jugadores
	f.tema = p_tema
	padre.add_child(f)
	return f


## El rango que se enseña debajo del nombre
static func rango(nivel: int) -> String:
	if nivel < 5:
		return "NOVATO"
	if nivel < 10:
		return "SOLDADO"
	if nivel < 20:
		return "VETERANO"
	if nivel < 35:
		return "ÉLITE"
	return "LEYENDA"


var _y0_lienzo := 0.0

func _ready() -> void:
	likes_partida.clear()
	Net.limpiar_likes()
	layer = 47
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_raiz = Control.new()
	_raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_raiz)
	var tam: Vector2 = get_viewport().get_visible_rect().size
	# EN UN PLEGABLE ABIERTO (2026-10-15, pedido: "no esta adaptada al Z Fold 4"): el lienzo nunca baja de
	# EscalaPantalla.ANCHO_MIN de ancho; si la pantalla es mas cuadrada se escala por el ancho y va centrado en vertical
	var k: float = minf(tam.y / 1080.0, tam.x / 1900.0)
	var m := {"k": k, "y0": maxf(0.0, (tam.y - 1080.0 * k) * 0.5)}
	_raiz.scale = Vector2(k, k)
	_raiz.position.y = float(m.y0)
	_w = tam.x / k
	_y0_lienzo = float(m.y0) / k
	var fondo := _Fondo.new()
	fondo.ancho = _w
	fondo.tema = tema
	_raiz.add_child(fondo)
	fondo.modulate.a = FinIntroFondo.ALFA      # semitransparente: detras pasa la camara de cine (camara_fin.gd)
	var titulo := _label("MEJORES JUGADORES", 84, Color.WHITE if tema != "zombi" else Color(0.95, 0.9, 0.82),
		Vector2(_w * 0.5 - 700, 20), Vector2(1400, 110))
	titulo.add_theme_color_override("font_outline_color", Color(0.25, 0.1, 0.5, 0.9) if tema != "zombi" else Color(0.35, 0.0, 0.02, 0.95))
	_montar_munecos()
	for puesto in mini(5, jugadores.size()):
		_tarjetas.append(_tarjeta(puesto))
	# encima de las tarjetas, la textura con los muñecos (van detras del texto de cada una: ver _tarjeta)
	_boton()
	if not Net.like_recibido.is_connected(_on_like):
		Net.like_recibido.connect(_on_like)
	if not Net.like_quitado.is_connected(_on_quitar_like):
		Net.like_quitado.connect(_on_quitar_like)
	_raiz.modulate.a = 0.0
	create_tween().tween_property(_raiz, "modulate:a", 1.0, 0.25)
	_entrada()


func _label(t: String, tam: int, color: Color, pos: Vector2, caja: Vector2, al := HORIZONTAL_ALIGNMENT_CENTER, padre: Node = null) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", FinIntro.fuente_cartel())
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.14, 0.06, 0.3, 0.9))
	l.add_theme_constant_override("outline_size", maxi(5, tam / 8))
	l.position = pos
	l.size = caja
	l.horizontal_alignment = al
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(padre if padre else _raiz).add_child(l)
	return l


## El tamaño mas grande (hasta `maximo`) al que `texto` cabe en `ancho` en una linea
func _cabe(texto: String, ancho: float, maximo: int, minimo: int) -> int:
	var tam := maximo
	while tam > minimo and FinIntro.fuente_cartel().get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x > ancho:
		tam -= 1
	return tam


func _centro_x(puesto: int) -> float:
	var col: int = ORDEN.find(puesto)
	return _w * 0.5 + (col - 2) * PASO


# ------------------------------------------------------------------------------------------------ los muñecos
## Los cinco en UN solo mundo con una camara ortogonal: cada muñeco cae justo en el hueco de su tarjeta
func _montar_munecos() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(int(_w), 460)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_raiz.add_child(_vp)
	var mundo := Node3D.new()
	_vp.add_child(mundo)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.78, 1.0)
	e.ambient_light_energy = 0.95
	env.environment = e
	mundo.add_child(env)
	var sol := DirectionalLight3D.new()
	sol.rotation = Vector3(-0.5, 0.35, 0.0)
	sol.light_energy = 1.35
	mundo.add_child(sol)
	var contra := DirectionalLight3D.new()
	contra.rotation = Vector3(-0.2, PI + 0.6, 0.0)
	contra.light_energy = 1.0
	contra.light_color = Color(1.0, 0.7, 0.9)
	mundo.add_child(contra)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 460.0 / METROS_PX
	cam.position = Vector3(0, 0.95, 10.0)
	mundo.add_child(cam)
	cam.current = true
	for puesto in mini(5, jugadores.size()):
		var j: Dictionary = jugadores[puesto]
		var m := AvatarScript.new()
		mundo.add_child(m)
		var asp: Array = j.get("aspecto", [])
		if asp.size() >= 4:
			m.build(float(asp[0]), false, asp[1], false, false, String(asp[2]), asp[3])
		else:
			m.build(AvatarScript.ALTURA, false, Color.WHITE, false)
		# SIN ARMA EN LA MANO: aqui se posa, no se combate
		if m.has_method("unequip_weapon"):
			m.unequip_weapon()
		m.play("idle_%d" % (1 + puesto % 3))
		m.position = Vector3((_centro_x(puesto) - _w * 0.5) / METROS_PX, 0.02, 0.0)
		m.rotation.y = PI - 0.18
		# el muñeco ya trae su escala (voxels -> metros): se multiplica, no se pisa
		m.set_meta("escala", m.scale * (1.08 if puesto == 0 else 1.0))
		m.scale = m.get_meta("escala")
		m.visible = false
		_munecos.append(m)
	var tex := TextureRect.new()
	tex.texture = _vp.get_texture()
	tex.position = Vector2(0, Y_T + 40.0)
	tex.size = Vector2(_w, 460)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.z_index = 1
	_raiz.add_child(tex)


# ------------------------------------------------------------------------------------------------ las tarjetas
func _tarjeta(puesto: int) -> Node2D:
	var j: Dictionary = jugadores[puesto]
	j["puesto"] = puesto
	var n := Node2D.new()
	var cx := _centro_x(puesto)
	n.position = Vector2(cx, Y_T + ALTO_T * 0.5)
	_raiz.add_child(n)
	var hw := ANCHO_T * 0.5
	var hh := ALTO_T * 0.5
	var sesgo := INCLINA * 0.5
	var poly := PackedVector2Array([Vector2(-hw + sesgo, -hh), Vector2(hw + sesgo, -hh), Vector2(hw - sesgo, hh), Vector2(-hw - sesgo, hh)])
	n.set_meta("poly", poly)
	# EL FONDO DICE DE QUE LADO ESTA: tus compañeros en azul, los rivales en rojo, la tuya en oro rosado (y sin
	# equipos, morado). El del puesto 1.º, un poco mas claro.
	var mio := Net.my_team()
	var eq := String(j.get("equipo", ""))
	var arriba := Color(0.66, 0.42, 0.92, 0.8)
	var abajo := Color(0.86, 0.4, 0.72, 0.84)
	if bool(j.get("es_yo", false)):
		arriba = Color(1.0, 0.82, 0.55, 0.92)
		abajo = Color(0.98, 0.6, 0.72, 0.92)
	elif mio != "" and eq == mio:
		arriba = Color(0.46, 0.62, 1.0, 0.88)
		abajo = Color(0.32, 0.5, 0.95, 0.9)
	elif mio != "" and eq != "":
		arriba = Color(1.0, 0.45, 0.52, 0.88)
		abajo = Color(0.85, 0.24, 0.36, 0.9)
	if tema == "zombi":
		# en zombis sois todos del mismo lado: verde militar apagado; la tuya, hueso y sangre
		arriba = Color(0.36, 0.46, 0.34, 0.9)
		abajo = Color(0.2, 0.28, 0.2, 0.92)
		if bool(j.get("es_yo", false)):
			arriba = Color(0.86, 0.78, 0.66, 0.92)
			abajo = Color(0.6, 0.1, 0.1, 0.92)
	if puesto == 0:
		arriba = arriba.lightened(0.12)
		abajo = abajo.lightened(0.08)
	var fondo := Polygon2D.new()
	fondo.polygon = poly
	fondo.vertex_colors = PackedColorArray([arriba, arriba, abajo, abajo])
	n.add_child(fondo)
	# el faldon de abajo, mas oscuro, donde va el texto
	var f0 := -hh + 440.0
	var faldon := Polygon2D.new()
	faldon.polygon = PackedVector2Array([_en(poly, f0, -1.0), _en(poly, f0, 1.0), poly[2], poly[3]])
	faldon.color = Color(0.2, 0.08, 0.35, 0.28)
	n.add_child(faldon)
	# lo de encima del muñeco (el texto) va delante de la textura de los muñecos
	var sobre := Node2D.new()
	sobre.z_index = 2
	n.add_child(sobre)
	# el puesto, con laureles los tres primeros
	var num_x := hw - 20.0
	if puesto < 3:
		var lau := _Laurel.new()
		lau.position = Vector2(num_x - 36.0, -hh + 62.0)
		lau.color = [Color(1.0, 0.8, 0.3), Color(0.75, 0.82, 0.95), Color(1.0, 0.6, 0.45)][puesto]
		sobre.add_child(lau)
	var col_num: Color = [Color(1.0, 0.82, 0.3), Color(0.8, 0.88, 1.0), Color(1.0, 0.62, 0.5), Color(0.86, 0.84, 1.0), Color(0.86, 0.84, 1.0)][puesto]
	_label(str(puesto + 1), 70, col_num, Vector2(num_x - 80.0, -hh + 20.0), Vector2(90, 84), HORIZONTAL_ALIGNMENT_CENTER, sobre)
	# MVP y TU
	var ty := -hh + 30.0
	if bool(j.get("mvp", false)):
		_etiqueta(sobre, "MVP", Vector2(-hw + sesgo + 14.0, ty), Color(1.0, 0.82, 0.2))
		ty += 44.0
	if bool(j.get("es_yo", false)):
		_etiqueta(sobre, "TÚ", Vector2(-hw + sesgo + 14.0 - 10.0, ty), Color(1.0, 0.92, 0.3))
	# me gusta
	var nombre := String(j["nombre"])
	var boton := Button.new()
	boton.flat = true
	boton.focus_mode = Control.FOCUS_NONE
	boton.position = Vector2(hw - sesgo * 0.3 - 110.0, -hh + 392.0)
	boton.size = Vector2(96, 56)
	boton.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	boton.z_index = 3
	n.add_child(boton)
	var cuenta := _label("0", 38, Color.WHITE, Vector2(-6, 0), Vector2(44, 56), HORIZONTAL_ALIGNMENT_RIGHT, boton)
	var pulgar := _Pulgar.new()
	pulgar.position = Vector2(62, 28)
	boton.add_child(pulgar)
	_likes[nombre] = [0, cuenta, pulgar]
	if bool(j.get("es_yo", false)):
		boton.disabled = true            # a ti mismo no te puedes dar like
		boton.mouse_default_cursor_shape = Control.CURSOR_ARROW
	boton.pressed.connect(func(): _dar_like(nombre))
	# LAS DOS RAYITAS: solo en la tarjeta de otra PERSONA (tu no te invitas ni te reportas; un bot no tiene cuenta)
	var persona := not (j.get("cuenta", {}) as Dictionary).is_empty() or Net.es_nombre_de_persona(nombre)
	if not bool(j.get("es_yo", false)) and persona and String(j.get("tipo", "")) != "BOT":
		var rayas := _Rayas.new()
		rayas.position = Vector2(_en(poly, -hh + 420.0, -1.0).x + 16.0, -hh + 394.0)
		rayas.size = Vector2(52, 52)
		rayas.z_index = 3
		n.add_child(rayas)
		rayas.pressed.connect(func(): abrir_opciones(puesto))
		_rayas[nombre] = rayas
		_estados[nombre] = {}
	# el nombre con su recuadro
	var yb := -hh + 462.0
	var x_izq := _en(poly, yb + 20.0, -1.0).x + 18.0
	var cara := Polygon2D.new()
	cara.polygon = PackedVector2Array([Vector2(0, 0), Vector2(44, 0), Vector2(44, 44), Vector2(0, 44)])
	cara.color = Color(0.25, 0.15, 0.5)
	cara.position = Vector2(x_izq, yb)
	sobre.add_child(cara)
	# un bot no enseña nombre (el like sigue yendo a su clave); quien juega con cuenta es una persona
	var visto := nombre if not (j.get("cuenta", {}) as Dictionary).is_empty() else Net.nombre_para_ver(nombre)
	_label(visto.substr(0, 1).to_upper() if visto != "" else "-", 30, Color.WHITE, Vector2(0, 0), Vector2(44, 44), HORIZONTAL_ALIGNMENT_CENTER, cara)
	var ancho_nombre := ANCHO_T - 90.0
	_label(visto, _cabe(visto, ancho_nombre, 32, 18), Color.WHITE, Vector2(x_izq + 54.0, yb - 2.0), Vector2(ancho_nombre, 48),
		HORIZONTAL_ALIGNMENT_LEFT, sobre)
	# el rango, en una franja
	var yr := yb + 56.0
	var xr := _en(poly, yr + 16.0, -1.0).x + 10.0
	var franja := Polygon2D.new()
	franja.polygon = PackedVector2Array([Vector2(xr, yr), Vector2(xr + 230.0, yr), Vector2(xr + 224.0, yr + 32.0), Vector2(xr - 6.0, yr + 32.0)])
	franja.color = Color(0.35, 0.2, 0.6, 0.55)
	sobre.add_child(franja)
	var tipo := String(j.get("tipo", "JUGADOR"))
	_label(tipo, 22, Color(0.85, 0.82, 1.0), Vector2(xr + 10.0, yr), Vector2(210, 32), HORIZONTAL_ALIGNMENT_LEFT, sobre)
	# los puntos
	var yp := yr + 44.0
	var xp := _en(poly, yp + 22.0, -1.0).x + 12.0
	var franja2 := Polygon2D.new()
	franja2.polygon = PackedVector2Array([Vector2(xp, yp), Vector2(xp + ANCHO_T - 44.0, yp), Vector2(xp + ANCHO_T - 52.0, yp + 44.0), Vector2(xp - 8.0, yp + 44.0)])
	franja2.color = Color(1, 1, 1, 0.14)
	sobre.add_child(franja2)
	_label("PUNTOS", 28, Color.WHITE, Vector2(xp + 8.0, yp), Vector2(150, 44), HORIZONTAL_ALIGNMENT_LEFT, sobre)
	var lp := _label("0", 40, ORO, Vector2(xp + ANCHO_T - 200.0, yp - 4.0), Vector2(140, 52), HORIZONTAL_ALIGNMENT_RIGHT, sobre)
	lp.set_meta("valor", int(j.get("puntos", 0)))
	lp.set_meta("nombre", nombre)
	n.set_meta("puntos", lp)
	# el titulo y su frase
	# el titulo que se ha ganado de verdad (main._mejores_jugadores); si no trae, el del puesto
	var tt: Array = [String(j["titulo"]), String(j["frase"]), j.get("color_titulo", ORO)] if j.has("titulo") else TITULOS[puesto]
	var yt := yp + 56.0
	var xt := _en(poly, yt + 20.0, -1.0).x + 14.0
	var ancho_t := ANCHO_T - 50.0
	# el titulo, aclarado y con filo oscuro: se tiene que leer igual sobre la tarjeta azul, la roja o la dorada
	var col_t: Color = (tt[2] as Color).lightened(0.35)
	var lt := _label(String(tt[0]), _cabe(String(tt[0]), ancho_t, 30, 18), col_t, Vector2(xt, yt), Vector2(ancho_t, 38), HORIZONTAL_ALIGNMENT_LEFT, sobre)
	lt.add_theme_color_override("font_outline_color", Color(0.12, 0.03, 0.2, 0.95))
	lt.add_theme_constant_override("outline_size", 7)
	var frase := _label(String(tt[1]), 20, Color.WHITE, Vector2(xt - 6.0, yt + 36.0), Vector2(ancho_t - 10.0, 60), HORIZONTAL_ALIGNMENT_LEFT, sobre)
	frase.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	frase.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	frase.add_theme_constant_override("line_spacing", -4)
	# la raya de luz que traza el contorno al aparecer
	var traza := _Traza.new()
	traza.poly = poly
	traza.z_index = 4
	n.add_child(traza)
	n.set_meta("traza", traza)
	n.visible = false
	return n


## El punto del borde izquierdo (lado -1) o derecho (+1) de la tarjeta a una altura local `y`
func _en(poly: PackedVector2Array, y: float, lado: float) -> Vector2:
	var a: Vector2 = poly[0] if lado < 0.0 else poly[1]
	var b: Vector2 = poly[3] if lado < 0.0 else poly[2]
	var k := (y - a.y) / (b.y - a.y)
	return Vector2(lerpf(a.x, b.x, k), y)


func _etiqueta(padre: Node, texto: String, pos: Vector2, color: Color) -> void:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([Vector2(8, 0), Vector2(70, 0), Vector2(62, 36), Vector2(0, 36)])
	p.color = color
	p.position = pos
	padre.add_child(p)
	var l := _label(texto, 24, Color(0.2, 0.1, 0.3), Vector2(0, 0), Vector2(70, 36), HORIZONTAL_ALIGNMENT_CENTER, p)
	l.add_theme_constant_override("outline_size", 0)


func _boton() -> void:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.size = Vector2(420, 120)
	b.position = Vector2(_w * 0.5 - 210.0, Y_T + ALTO_T + 60.0)
	b.z_index = 5
	_raiz.add_child(b)
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([Vector2(26, 0), Vector2(420, 0), Vector2(394, 120), Vector2(0, 120)])
	p.color = ORO
	b.add_child(p)
	var s := Polygon2D.new()
	s.polygon = PackedVector2Array([Vector2(2, 108), Vector2(396, 108), Vector2(394, 120), Vector2(0, 120)])
	s.color = ORO.darkened(0.35)
	b.add_child(s)
	var l := _label("CONTINUAR", 56, Color(0.14, 0.08, 0.28), Vector2(0, 0), Vector2(420, 96), HORIZONTAL_ALIGNMENT_CENTER, b)
	l.add_theme_constant_override("outline_size", 0)
	var tecla := _label("[ESPACIO]", 18, Color(0.35, 0.26, 0.05), Vector2(0, 86), Vector2(420, 22), HORIZONTAL_ALIGNMENT_CENTER, b)
	tecla.add_theme_constant_override("outline_size", 0)
	b.pressed.connect(cerrar)


# ------------------------------------------------------------------------------------------------ la entrada
## Una a una, del 1.º hacia fuera: la luz traza el contorno, se llena con un golpe y sale su personaje
func _entrada() -> void:
	await get_tree().create_timer(0.35).timeout
	for puesto in _tarjetas.size():
		if _cerrando or not is_inside_tree():
			return
		var n: Node2D = _tarjetas[puesto]
		n.visible = true
		var traza: Node2D = n.get_meta("traza")
		for c in n.get_children():
			if c != traza:
				(c as CanvasItem).modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(traza, "avance", 1.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await tw.finished
		Audio.ui("intro_golpe", -4.0)
		for c in n.get_children():
			if c != traza:
				create_tween().tween_property(c, "modulate:a", 1.0, 0.12)
		n.scale = Vector2(1.14, 1.14)
		var tp := create_tween()
		tp.tween_property(n, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tp.parallel().tween_property(traza, "fuera", 1.0, 0.4)
		var m: Node3D = _munecos[puesto]
		m.visible = true
		var base: Vector3 = m.get_meta("escala")
		m.scale = base * 0.2
		create_tween().tween_property(m, "scale", base, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		# los puntos suben de cero
		var lp: Label = n.get_meta("puntos")
		var total := int(lp.get_meta("valor"))
		create_tween().tween_method(func(v: float): lp.text = str(int(v)), 0.0, float(total), 0.6)
		await get_tree().create_timer(0.16).timeout


func _process(dt: float) -> void:
	_t += dt
	for m in _munecos:
		if is_instance_valid(m) and (m as Node3D).visible:
			m.drive_locomotion(Vector3.ZERO, false, true, 0, dt)
	# (con una ventana de opciones abierta ESPACIO es escribir en el reporte, no seguir)
	if not _cerrando and _t > 1.5 and Opciones.abiertas == 0 and Input.is_key_pressed(KEY_SPACE):
		cerrar()


# ------------------------------------------------------------------------------------------------ me gusta
## Tocar el pulgar: lo da, y tocarlo otra vez lo quita (el anfitrion lo arbitra: Net._like_host)
func _dar_like(a: String) -> void:
	if a == Net.nombre_propio() or _cerrando:
		return
	var dar := not _dados.has(a)
	if dar:
		_dados[a] = true
	else:
		_dados.erase(a)
	Net.net_like(Net.nombre_propio(), a, dar)


func _on_like(de: String, a: String) -> void:
	if not _likes.has(a):
		return
	var e: Array = _likes[a]
	e[0] = int(e[0]) + 1
	var l: Label = e[1]
	l.text = str(int(e[0]))
	likes_partida[a] = int(e[0])
	var pulgar: Node2D = e[2]
	_pintar_pulgar(a)
	pulgar.scale = Vector2(1.6, 1.6)
	create_tween().tween_property(pulgar, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Audio.ui("aceptar", -6.0)
	if a == Net.nombre_propio() and de != a and not _avisados.has(de):
		_avisados[de] = true
		_aviso_like(de)


func _on_quitar_like(_de: String, a: String) -> void:
	if not _likes.has(a):
		return
	var e: Array = _likes[a]
	e[0] = maxi(0, int(e[0]) - 1)
	(e[1] as Label).text = str(int(e[0]))
	likes_partida[a] = int(e[0])
	_pintar_pulgar(a)
	var pulgar: Node2D = e[2]
	pulgar.scale = Vector2(0.8, 0.8)
	create_tween().tween_property(pulgar, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Relleno naranja: el que le has dado TU (en tu tarjeta, los que te han dado)
func _pintar_pulgar(a: String) -> void:
	var e: Array = _likes[a]
	var pulgar: Node2D = e[2]
	pulgar.set("activo", _dados.has(a) or (a == Net.nombre_propio() and int(e[0]) > 0))
	pulgar.queue_redraw()


# ------------------------------------------------------------------------------------------------ las dos rayitas
## El menu del jugador del puesto `puesto` (opciones_jugador.gd), saliendo de su boton de rayitas
func abrir_opciones(puesto: int) -> Control:
	if _cerrando or puesto >= jugadores.size():
		return null
	if _menu != null and is_instance_valid(_menu):
		_menu.cerrar()
	var j: Dictionary = jugadores[puesto]
	var nombre := String(j["nombre"])
	var b: Control = _rayas.get(nombre)
	var n: Node2D = _tarjetas[puesto]
	var ancla := n.position + (b.position + Vector2(26, 0) if b else Vector2.ZERO)
	_menu = Opciones.abrir_menu(_raiz, _w, j, ancla, info_partida, _estados.get(nombre, {}))
	_menu.invitado.connect(func(nm: String):
		if _rayas.has(nm) and is_instance_valid(_rayas[nm]):
			_rayas[nm].invitado = true)
	return _menu


## "fulano te dio like · ¡TE DIO LIKE, DALE UNO DE VUELTA!", arriba a la izquierda
func _aviso_like(de: String) -> void:
	var caja := Node2D.new()
	caja.z_index = 6
	_raiz.add_child(caja)
	var ancho := 520.0
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([Vector2(0, 0), Vector2(ancho, 0), Vector2(ancho - 14, 78), Vector2(0, 78)])
	p.color = Color(1, 1, 1, 0.94)
	caja.add_child(p)
	var ic := Polygon2D.new()
	ic.polygon = PackedVector2Array([Vector2(6, 6), Vector2(70, 6), Vector2(70, 72), Vector2(6, 72)])
	ic.color = Color(0.5, 0.3, 0.85)
	caja.add_child(ic)
	var pul := _Pulgar.new()
	pul.position = Vector2(38, 40)
	pul.scale = Vector2(1.3, 1.3)
	pul.activo = false
	caja.add_child(pul)
	var t1 := _label("%s te dio like" % de, _cabe("%s te dio like" % de, ancho - 100.0, 28, 16), Color(0.75, 0.1, 0.2),
		Vector2(84, 4), Vector2(ancho - 100.0, 36), HORIZONTAL_ALIGNMENT_LEFT, caja)
	t1.add_theme_constant_override("outline_size", 0)
	var t2 := _label("¡TE DIO LIKE, DALE UNO DE VUELTA!", _cabe("¡TE DIO LIKE, DALE UNO DE VUELTA!", ancho - 110.0, 24, 14),
		Color(0.15, 0.08, 0.3), Vector2(84, 38), Vector2(ancho - 110.0, 34), HORIZONTAL_ALIGNMENT_LEFT, caja)
	t2.add_theme_constant_override("outline_size", 0)
	caja.position = Vector2(-ancho - 20.0, 24.0 + _toast_y)
	_toast_y += 90.0
	var tw := caja.create_tween()
	tw.tween_property(caja, "position:x", 40.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(3.2)
	tw.tween_property(caja, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func():
		_toast_y = maxf(0.0, _toast_y - 90.0)
		caja.queue_free())


func cerrar() -> void:
	if _cerrando:
		return
	_cerrando = true
	Audio.ui("aceptar", -4.0)
	_mandar_likes()
	var tw := create_tween()
	tw.tween_property(_raiz, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func():
		terminado.emit()
		queue_free())


## LOS ME GUSTA QUE QUEDARON, A LA CUENTA DE CADA UNO (servidor/reportes.js, POST /likes): solo a quien juega con
## cuenta, una vez por partida. Cuelga de Cuenta: esta pantalla se va antes de que conteste.
func _mandar_likes() -> void:
	if not Opciones.tiene_sesion() or _dados.is_empty():
		return
	var lista: Array = []
	for j in jugadores:
		if _dados.has(String(j["nombre"])):
			var d := Opciones.destino(j)
			if not d.is_empty():
				lista.append(d)
	if lista.is_empty():
		return
	Opciones.pedir(Cuenta, "/likes", {"a": lista, "partida": String(info_partida.get("clave", ""))},
		func(codigo: int, d: Dictionary): print("[likes] %d %s" % [codigo, JSON.stringify(d)]))


# ------------------------------------------------------------------------------------------------ piezas dibujadas
## El boton de las DOS RAYITAS de cada tarjeta; con la solicitud enviada, un check
class _Rayas extends Button:
	var invitado := false:
		set(v):
			invitado = v
			queue_redraw()
	var _encima := false

	func _ready() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func():
			_encima = true
			queue_redraw())
		mouse_exited.connect(func():
			_encima = false
			queue_redraw())

	func _draw() -> void:
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.3, 0.32, 0.72, 0.95) if invitado else Color(0.5, 0.46, 0.72, 0.95)
		if _encima:
			st.bg_color = st.bg_color.lightened(0.12)
		st.set_corner_radius_all(6)
		st.set_border_width_all(2)
		st.border_color = Color(1, 1, 1, 0.55)
		st.shadow_color = Color(0.1, 0.02, 0.25, 0.35)
		st.shadow_size = 4
		st.shadow_offset = Vector2(0, 3)
		draw_style_box(st, Rect2(Vector2.ZERO, size))
		load("res://scripts/opciones_jugador.gd").dibujar_icono(self, "check" if invitado else "rayas",
			Rect2(size * 0.18, size * 0.64), Color.WHITE)



class _Fondo extends Control:
	var ancho := 1920.0
	var tema := ""

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		if tema == "zombi":
			load("res://scripts/fin_intro.gd").pintar_fondo_zombi(self, ancho, 1.0)
			return
		draw_polygon(PackedVector2Array([Vector2(0, -700), Vector2(ancho, -700), Vector2(ancho, 1780), Vector2(0, 1780)]),
			PackedColorArray([Color(0.3, 0.2, 0.6), Color(0.36, 0.24, 0.68), Color(0.28, 0.18, 0.55), Color(0.24, 0.15, 0.48)]))
		# rayos de luz que salen del centro, muy tenues
		var c := Vector2(ancho * 0.5, 480)
		for i in 14:
			var a := TAU * i / 14.0 + 0.1
			var b := a + 0.07
			draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a), sin(a)) * 1600.0, c + Vector2(cos(b), sin(b)) * 1600.0]),
				Color(1, 1, 1, 0.035))
		# y un resplandor rosado detras de la tarjeta del centro
		for k in 6:
			draw_circle(c, 420.0 - k * 60.0, Color(1.0, 0.6, 0.9, 0.025))


## La raya de luz que recorre el contorno de la tarjeta al aparecer, y luego se desvanece
class _Traza extends Node2D:
	var poly := PackedVector2Array()
	var avance := 0.0:
		set(v):
			avance = v
			queue_redraw()
	var fuera := 0.0:
		set(v):
			fuera = v
			queue_redraw()

	func _draw() -> void:
		if poly.size() < 4 or avance <= 0.0 or fuera >= 1.0:
			return
		var pts := PackedVector2Array([poly[0], poly[1], poly[2], poly[3], poly[0]])
		var total := 0.0
		for i in range(1, pts.size()):
			total += pts[i - 1].distance_to(pts[i])
		var queda := total * avance
		var trazo := PackedVector2Array([pts[0]])
		for i in range(1, pts.size()):
			var d := pts[i - 1].distance_to(pts[i])
			if queda >= d:
				trazo.append(pts[i])
				queda -= d
			else:
				trazo.append(pts[i - 1].lerp(pts[i], queda / maxf(d, 0.01)))
				break
		var a := 1.0 - fuera
		draw_polyline(trazo, Color(1.0, 0.75, 0.2, 0.25 * a), 22.0, true)
		draw_polyline(trazo, Color(1.0, 0.86, 0.35, 0.8 * a), 7.0, true)
		draw_polyline(trazo, Color(1.0, 1.0, 0.92, a), 2.5, true)


## Los laureles del puesto: dos ramas de hojas en arco
class _Laurel extends Node2D:
	var color := Color(1.0, 0.8, 0.3)

	func _draw() -> void:
		for lado in [-1.0, 1.0]:
			for i in 5:
				var a := deg_to_rad(110.0 + i * 24.0)
				var p := Vector2(cos(a) * 34.0 * lado, sin(a) * 34.0 + 6.0)
				var hoja := PackedVector2Array()
				for k in 8:
					var t := TAU * k / 8.0
					hoja.append(p + Vector2(cos(t) * 5.0, sin(t) * 10.0).rotated(a * lado + (0.4 if lado > 0 else -0.4)))
				draw_colored_polygon(hoja, color)


## El pulgar de ME GUSTA: contorno blanco; relleno naranja cuando ya tiene alguno
class _Pulgar extends Node2D:
	var activo := false

	func _draw() -> void:
		var relleno := Color(1.0, 0.62, 0.2) if activo else Color(1, 1, 1, 0.0)
		var borde := Color.WHITE
		var puno := PackedVector2Array([Vector2(-8, -4), Vector2(-2, -4), Vector2(3, -18), Vector2(9, -18), Vector2(9, -6),
			Vector2(18, -6), Vector2(20, -2), Vector2(17, 16), Vector2(-8, 16)])
		var manga := PackedVector2Array([Vector2(-18, -4), Vector2(-10, -4), Vector2(-10, 16), Vector2(-18, 16)])
		if activo:
			draw_colored_polygon(puno, relleno)
			draw_colored_polygon(manga, relleno)
		var p2 := puno.duplicate()
		p2.append(puno[0])
		var m2 := manga.duplicate()
		m2.append(manga[0])
		draw_polyline(p2, Color(0.2, 0.08, 0.35, 0.6), 6.0, true)
		draw_polyline(m2, Color(0.2, 0.08, 0.35, 0.6), 6.0, true)
		draw_polyline(p2, borde, 3.0, true)
		draw_polyline(m2, borde, 3.0, true)
