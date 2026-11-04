extends CanvasLayer
## EL PASE DE BATALLA, LA PANTALLA (2026-09-29, pedido: "haz un pase de batalla identico a la foto de referencia", la del
## PIXEL PASS). Los datos y las reglas son de pase_batalla.gd (PaseBatalla): aqui solo se enseña y se reclama.
##
##   arriba      el ticket, los dias que le quedan a la temporada, "PASE DE BATALLA / TEMPORADA 1", TAREAS (las misiones
##               del lobby) y la X.
##   izquierda   PASE PRÉMIUM: el Comando en 3D (la recompensa del nivel 20) entre CUBOS DE FUERZA (la moneda de subir
##               personajes: los de cofre_pantalla.gd), y DESBLOQUEAR (diamantes).
##   la pista    se desliza con el dedo (con inercia), arrastrando con el raton o con la rueda. Arriba las cartas PRÉMIUM
##               (doradas; azules las especiales), en medio la barra con los hexagonos de nivel y la EXP que pide cada
##               uno, y abajo las GRATIS. Lo alcanzado se RECLAMA tocandolo (late y dice RECLAMAR); lo reclamado lleva la
##               palomita; lo que aun no, el candado. Tocar una carta cerrada dice que es y que falta. Los niveles que no
##               dan nada llevan un hueco a trazos. Al reclamar un COFRE se ofrece abrirlo ya (cofre_pantalla.gd).
##   abajo       IR A BATALLA (lo mismo que JUGAR: CENTRO: BATALLA) con lo que llevas del nivel.
## Se dibuja en un lienzo de 904 de alto -el de la foto: las medidas salen de ella- y se escala a la pantalla.
## Lo abre el lobby (`_abrir_pase`), que le pasa `lobby`: de el salen los retratos 3D y la pantalla de recompensa.

signal cerrado

const IconoLobby := preload("res://scripts/icono_lobby.gd")
const HabilidadScript := preload("res://scripts/habilidad.gd")
const AvatarScript := preload("res://scripts/avatar_animator.gd")
const LobbyScript := preload("res://scripts/lobby.gd")
const RecompensaScript := preload("res://scripts/recompensa.gd")
const EscalaPantalla := preload("res://scripts/escala_pantalla.gd")
var _franjas: Array = []        ## las franjas de arriba y abajo en un plegable abierto (escala_pantalla.gd)
const CofreScript := preload("res://scripts/cofre_pantalla.gd")

const ALTO := 904.0
## LA PISTA (en el contenido que se desliza): donde cae el hexagono del nivel 1 y lo que hay de uno a otro
const X0 := 594.0
const PASO := 282.0
const BARRA_Y0 := 548.0
const BARRA_Y1 := 580.0
const NUMEROS_Y := 626.0
## las cartas: tamaño, lo que se inclinan (el borde de arriba va corrido a la derecha), altura y cuanto se apartan del
## hexagono de su nivel
const P_TAM := Vector2(278, 308)
const P_SESGO := 36.0
const P_Y := 162.0
const P_DX := 38.0
const G_TAM := Vector2(205, 176)
const G_SESGO := 28.0
const G_Y := 655.0
const G_DX := -23.0
## el panel PASE PRÉMIUM: el borde derecho inclinado, como las cartas
const PANEL_Y0 := 136.0
const PANEL_Y1 := 862.0
const PANEL_X_ARRIBA := 480.0
const PANEL_X_ABAJO := 398.0
## los retratos 3D se cocinan algo mas grandes que su hueco: en una pantalla de mas de 904 de alto no pixelan
const RESOLUCION := 1.3
## lo que se inclinan las armas en las cartas (el cañon hacia arriba a la derecha, como en la foto)
const INCLINACION := 30.0

## LOS COLORES, medidos en la foto
const FONDO_ABAJO := Color8(52, 42, 113)
const GRADIENTE_FONDO := [[0.0, Color8(85, 62, 167)], [125.0, Color8(143, 60, 189)], [200.0, Color8(196, 70, 216)],
	[250.0, Color8(236, 85, 238)], [292.0, Color8(252, 135, 232)], [330.0, Color8(238, 88, 239)],
	[375.0, Color8(200, 72, 219)], [425.0, Color8(166, 64, 200)], [475.0, Color8(131, 61, 185)],
	[BARRA_Y0, Color8(98, 60, 171)]]
const CREMA := Color8(250, 238, 216)
const ORO_A := Color8(253, 214, 95)
const ORO_B := Color8(236, 190, 78)
const ORO_BANDA := Color8(198, 157, 64)
const AZUL_A := Color8(96, 176, 252)
const AZUL_B := Color8(52, 118, 222)
const AZUL_BANDA := Color8(38, 90, 196)
const AZUL_BORDE := Color8(176, 218, 255)
const MARCO_GRATIS := Color8(255, 184, 8)
const GRATIS_A := Color8(84, 172, 254)
const GRATIS_B := Color8(46, 106, 206)
const BARRA_LLENA := Color8(254, 202, 67)
const BARRA_VACIA := Color8(214, 166, 128)
const HEX := Color8(254, 184, 0)
const HEX_BORDE := Color8(176, 96, 20)
const HEX_TXT := Color8(130, 45, 0)
const PANEL := Color8(140, 86, 250)
const MORADO_BOTON := Color8(83, 68, 197)
const AMARILLO_BOTON := Color8(245, 200, 59)
const TINTA := Color8(28, 38, 58)
const CIAN := Color8(158, 222, 255)
const ORO_TEXTO := Color8(255, 208, 64)
const VERDE := Color8(52, 196, 92)

## Sobre que arma se enseña cada pintura (vale para todas; en la carta se ve puesta en una)
const ARMA_DE_PINTURA := {
	"sk_bosque": "carabina_556", "sk_tropical": "smg_9mm", "sk_oxido": "pistola_45", "sk_cyber": "fusil_bullpup",
	"sk_neon": "escopeta_bomba", "sk_toxico": "fusil_762", "sk_glaciar": "revolver_44", "sk_calle": "rifle_precision",
	"sk_dorado": "pistola_9", "sk_dragon": "smg_compacta", "sk_ceniza": "pdw_57", "sk_arena": "escopeta_auto",
}
## Los CUBOS DE FUERZA alrededor del Comando: posicion y lado (m). Los de menos de 0,1 son chispas de energia sueltas.
const CUBOS := [
	[Vector3(-0.58, 1.46, 0.2), 0.2], [Vector3(-0.72, 1.0, 0.02), 0.25], [Vector3(-0.5, 0.52, 0.34), 0.19],
	[Vector3(0.52, 1.3, 0.16), 0.22], [Vector3(0.64, 0.84, -0.06), 0.26], [Vector3(0.44, 0.4, 0.36), 0.2],
	[Vector3(0.26, 1.74, -0.26), 0.13], [Vector3(-0.3, 1.8, -0.2), 0.12], [Vector3(0.74, 1.6, -0.3), 0.14],
	[Vector3(-0.8, 1.3, -0.34), 0.13], [Vector3(0.6, 0.6, 0.44), 0.12], [Vector3(-0.66, 0.2, -0.16), 0.15],
	[Vector3(-0.4, 1.16, 0.5), 0.06], [Vector3(0.34, 1.52, 0.46), 0.05], [Vector3(-0.2, 0.74, 0.56), 0.05],
	[Vector3(0.82, 1.08, 0.26), 0.05],
]

## el lobby que la abre (sin tipo: se le llaman sus funciones, que Node no tiene)
var lobby = null

var _raiz: Control
var _w := 1607.0
var _f: SystemFont           ## negrita gruesa y cursiva: la de los titulos de la foto
var _fb: SystemFont          ## negrita recta
var _fondo: Control
var _pista: Control
var _contenido: Control
var _cartas: Array = []      ## {n, fila, rect (en el contenido), carta, cuerpo, sobre, pildora, pildora_txt, tam, sesgo, estado}
var _etiqueta: Control
var _etiqueta_txt: Label
var _exp_txt: Label
var _exp_de: Label
var _dias_txt: Label
var _dias_chip: Control
var _boton_premium: Button
var _premium_txt: Label
var _premium_precio: Label
var _premium_gema: Control
var _premium_lema: Label
var _aviso: Label
var _aviso_t := 0.0
var _burbuja_nodo: Control = null
var _cerrando := false
# el arrastre de la pista
var _scroll := 0.0
var _scroll_pintado := -1.0
var _vel := 0.0
var _obj := -1.0
var _pulsado := false
var _toque := -1
var _p0 := Vector2.ZERO
var _p_ult := Vector2.ZERO
var _t_ult := 0
var _movido := 0.0
# lo que espera al servidor
var _en_vuelo: Array = []    ## [nivel, fila]
var _vuelo_t := 0.0
var _comprando := false
var _confirmar_t := 0.0
# el Comando
var _vp: SubViewport = null
var _foto_personaje: TextureRect = null
var _cubos: Array = []       ## [nodo, posicion, fase, giro]
var _t := 0.0


func _ready() -> void:
	layer = 62
	_f = _fuente(900, true)
	_fb = _fuente(800, false)
	_montar()
	_raiz.modulate.a = 0.0
	create_tween().tween_property(_raiz, "modulate:a", 1.0, 0.18)
	Audio.ui("submenu_abre", -8.0)
	Cuenta.sesion_cambiada.connect(_al_cambiar_cuenta)
	Cuenta.error_cuenta.connect(_al_error_cuenta)
	get_viewport().size_changed.connect(_al_redimensionar)
	# lo del lobby se aparta mientras tanto: debajo no se ve, y la lista de SOCIAL se quedaba con los toques de encima
	if is_instance_valid(lobby) and lobby.has_method("set_chrome_visible"):
		lobby.set_chrome_visible(false)
	_montar_personaje()


static func _fuente(peso: int, cursiva: bool) -> SystemFont:
	return preload("res://scripts/fuentes.gd").de(peso, cursiva)      # compartida: ver fuentes.gd


func _montar() -> void:
	var tam: Vector2 = get_viewport().get_visible_rect().size
	# EN UN PLEGABLE ABIERTO (casi cuadrado) el lienzo no se estrecha: se escala por el ancho y va centrado (escala_pantalla.gd)
	var m := EscalaPantalla.medir(tam, ALTO)
	var k: float = m["k"]
	_w = m["w"]
	_franjas = EscalaPantalla.franjas(self, tam, m["y0"], GRADIENTE_FONDO[0][1], FONDO_ABAJO)
	_raiz = Control.new()
	_raiz.mouse_filter = Control.MOUSE_FILTER_STOP
	_raiz.scale = Vector2(k, k)
	_raiz.position.y = m["y0"]
	_raiz.size = Vector2(_w, ALTO)
	add_child(_raiz)
	_montar_fondo()
	_montar_pista()
	_montar_panel()
	_montar_cabecera()
	_montar_batalla()
	_aviso = _texto("", 30, ORO_TEXTO, _f, 8, Color(0.16, 0.06, 0.3, 0.9))
	_aviso.position = Vector2(PANEL_X_ARRIBA, 118)
	_aviso.size = Vector2(_w - PANEL_X_ARRIBA, 40)
	_aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aviso.modulate.a = 0.0
	_raiz.add_child(_aviso)
	_refrescar()
	_ir_a(PaseBatalla.nivel(), false)


func _al_redimensionar() -> void:
	if _cerrando or not is_inside_tree():
		return
	var s := _scroll
	EscalaPantalla.quitar(_franjas)
	_raiz.queue_free()
	_cartas.clear()
	_burbuja_nodo = null
	_montar()
	_scroll = clampf(s, 0.0, _scroll_max())
	_aplicar_scroll()
	_poner_foto_personaje()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_cerrar()


func _cerrar() -> void:
	if _cerrando:
		return
	_cerrando = true
	Audio.ui("submenu_cierra", -8.0)
	if is_instance_valid(lobby):
		var cajon = lobby.get("drawer")
		if lobby.has_method("set_chrome_visible") and not (cajon is Control and (cajon as Control).visible):
			lobby.set_chrome_visible(true)
		if lobby.has_method("_refrescar_cuenta"):
			lobby._refrescar_cuenta()       # el oro de arriba y el globo del boton del pase, con lo reclamado
	cerrado.emit()
	var tw := create_tween()
	tw.tween_property(_raiz, "modulate:a", 0.0, 0.15)
	tw.tween_callback(queue_free)


# ================================================================== piezas
func _texto(t: String, tam: int, col: Color, f: Font = null, contorno := 0, col_contorno := Color(0, 0, 0, 0.5),
		sombra := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = t
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", f if f != null else _f)
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", col)
	if contorno > 0:
		l.add_theme_color_override("font_outline_color", col_contorno)
		l.add_theme_constant_override("outline_size", contorno)
	if sombra.a > 0.0:
		l.add_theme_color_override("font_shadow_color", sombra)
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 3)
		l.add_theme_constant_override("shadow_outline_size", 2)
	return l


func _dibujo(pos: Vector2, tam: Vector2, pintar: Callable, padre: Node) -> _Dibujo:
	var d := _Dibujo.new()
	d.position = pos
	d.size = tam
	d.pintar = pintar
	if padre != null:
		padre.add_child(d)
	return d


## Un boton que se dibuja a mano (`pintar`) y encoge un poco al apretarlo
func _boton(r: Rect2, pintar: Callable, al_pulsar: Callable, padre: Node) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.position = r.position
	b.size = r.size
	b.pivot_offset = r.size * 0.5
	for e in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(e, StyleBoxEmpty.new())
	padre.add_child(b)
	_dibujo(Vector2.ZERO, r.size, pintar, b)
	b.button_down.connect(func(): b.scale = Vector2(0.96, 0.96))
	b.button_up.connect(func(): b.scale = Vector2.ONE)
	b.pressed.connect(al_pulsar)
	return b


## Paralelogramo de `tam` inclinado `s` (arriba corrido a la derecha), metido `d` hacia dentro (o hacia fuera si es < 0)
static func _para(tam: Vector2, s: float, d: float = 0.0) -> PackedVector2Array:
	var h := tam.y
	var e := d * sqrt(h * h + s * s) / h
	return PackedVector2Array([
		Vector2(s * (1.0 - d / h) + e, d), Vector2(tam.x - s * d / h - e, d),
		Vector2(tam.x - s * (h - d) / h - e, h - d), Vector2(s * d / h + e, h - d)])


## Donde caen el borde izquierdo y el derecho (x, y) del paralelogramo a la altura `y`
static func _bordes(tam: Vector2, s: float, d: float, y: float) -> Vector2:
	var h := tam.y
	var e := d * sqrt(h * h + s * s) / h
	return Vector2(s * (1.0 - y / h) + e, tam.x - s * y / h - e)


## Trozo horizontal del paralelogramo (de y0 a y1), para las bandas de dentro
static func _franja(tam: Vector2, s: float, d: float, y0: float, y1: float) -> PackedVector2Array:
	var a := _bordes(tam, s, d, y0)
	var b := _bordes(tam, s, d, y1)
	return PackedVector2Array([Vector2(a.x, y0), Vector2(a.y, y0), Vector2(b.y, y1), Vector2(b.x, y1)])


static func _con_puntos(v: int) -> String:
	var t := str(absi(v))
	var out := ""
	while t.length() > 3:
		out = "." + t.substr(t.length() - 3) + out
		t = t.substr(0, t.length() - 3)
	return ("-" if v < 0 else "") + t + out


func _avisar(t: String) -> void:
	_aviso.text = t
	_aviso_t = 2.6
	_aviso.modulate.a = 1.0


# ================================================================== el fondo
func _montar_fondo() -> void:
	_fondo = _dibujo(Vector2.ZERO, _raiz.size, _pintar_fondo, _raiz)


func _pintar_fondo(ci: Control) -> void:
	var w := ci.size.x
	for i in GRADIENTE_FONDO.size() - 1:
		var a: Array = GRADIENTE_FONDO[i]
		var b: Array = GRADIENTE_FONDO[i + 1]
		ci.draw_polygon(PackedVector2Array([Vector2(0, a[0]), Vector2(w, a[0]), Vector2(w, b[0]), Vector2(0, b[0])]),
			PackedColorArray([a[1], a[1], b[1], b[1]]))
	ci.draw_rect(Rect2(0, BARRA_Y0, w, ALTO - BARRA_Y0), FONDO_ABAJO)
	# LOS ROMBOS de la franja de las cartas: una rejilla en diagonal, unos mas encendidos que otros, que se apagan hacia
	# arriba y hacia abajo. Se mueven un tercio de lo que se mueve la pista (profundidad).
	var paso := 60.0
	var desp := _scroll * 0.33
	var c0 := int(floor(desp / paso)) - 2
	for fila in 14:
		var y := 118.0 + fila * paso * 0.5
		var campana := clampf(1.0 - absf(y - 300.0) / 210.0, 0.0, 1.0)
		if campana <= 0.0:
			continue
		for col in range(c0, c0 + int(w / paso) + 5):
			var r := float(absi(hash(Vector2i(col, fila))) % 1000) / 1000.0
			if r < 0.3:
				continue
			var x := col * paso + (paso * 0.5 if fila % 2 == 1 else 0.0) - desp
			var lado := 7.0 + r * 6.0
			var alfa := (0.05 + r * 0.13) * campana
			ci.draw_colored_polygon(PackedVector2Array([Vector2(x, y - lado), Vector2(x + lado, y), Vector2(x, y + lado),
				Vector2(x - lado, y)]), Color(1.0, 0.86, 1.0, alfa))
	# un rayo de luz en diagonal, muy tenue, a la derecha
	var rx := w * 0.72
	ci.draw_colored_polygon(PackedVector2Array([Vector2(rx, 0), Vector2(rx + 150, 0), Vector2(rx - 60, BARRA_Y0),
		Vector2(rx - 210, BARRA_Y0)]), Color(1, 1, 1, 0.035))


# ================================================================== la pista
func _x_nivel(n: int) -> float:
	return X0 + float(n - 1) * PASO


func _largo() -> float:
	return _x_nivel(PaseBatalla.NIVELES) + 700.0


## Lo mas a la derecha que se puede ir: la ultima carta gratis tiene que poder quedar a la izquierda de IR A BATALLA
func _scroll_max() -> float:
	return maxf(0.0, _x_nivel(PaseBatalla.NIVELES) + 560.0 - _w)


func _montar_pista() -> void:
	_pista = Control.new()
	_pista.size = Vector2(_w, ALTO)
	_pista.clip_contents = true
	_pista.mouse_filter = Control.MOUSE_FILTER_STOP
	_pista.gui_input.connect(_entrada_pista)
	_raiz.add_child(_pista)
	_contenido = _dibujo(Vector2.ZERO, Vector2(_largo(), ALTO), _pintar_barra, _pista)
	_cartas.clear()
	for d in PaseBatalla.niveles():
		_carta(d, "p")
		_carta(d, "g")
	_carta_proxima()
	# LA ETIQUETA DE "ESTAS AQUI": en la punta de la barra, con la experiencia que llevas
	_etiqueta = _dibujo(Vector2.ZERO, Vector2(170, 44), _pintar_etiqueta, _contenido)
	_etiqueta_txt = _texto("", 24, Color.WHITE, _f)
	_etiqueta_txt.position = Vector2(46, 2)
	_etiqueta_txt.size = Vector2(118, 34)
	_etiqueta_txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_etiqueta.add_child(_etiqueta_txt)


## Donde acaba la barra: un trofeo pasado el ultimo nivel
func _fin_x() -> float:
	return _x_nivel(PaseBatalla.NIVELES) + PASO * 0.62


## Detras del nivel 20, la carta de la PROXIMA TEMPORADA (con su interrogacion): la pista no se acaba en un hueco vacio
func _carta_proxima() -> void:
	var tam := P_TAM
	var pos := Vector2(_x_nivel(PaseBatalla.NIVELES + 1) + P_DX - tam.x * 0.5, P_Y)
	var c := _dibujo(pos, tam, func(ci: Control):
		ci.draw_colored_polygon(_para(ci.size, P_SESGO), Color(0.2, 0.1, 0.46, 0.55))
		var b := _para(ci.size, P_SESGO, 2.0)
		for i in 4:
			# el filo a trazos
			var a: Vector2 = b[i]
			var z: Vector2 = b[(i + 1) % 4]
			var largo := a.distance_to(z)
			var k := 0.0
			while k < largo:
				ci.draw_line(a.lerp(z, k / largo), a.lerp(z, minf(k + 14.0, largo) / largo), Color(0.86, 0.8, 1.0, 0.7), 3.0)
				k += 24.0
		ci.draw_colored_polygon(_franja(ci.size, P_SESGO, 6.0, ci.size.y - 86.0, ci.size.y - 6.0), Color(0.1, 0.05, 0.3, 0.5)), _contenido)
	var q := _texto("?", 150, Color(0.9, 0.84, 1.0, 0.85), _f, 10, Color(0.2, 0.1, 0.45, 0.8))
	q.size = Vector2(tam.x, 222)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	c.add_child(q)
	var n := _texto("PRÓXIMA TEMPORADA", 24, Color.WHITE, _f, 5, Color(0.15, 0.08, 0.35, 0.8))
	n.position = Vector2(10, 222)
	n.size = Vector2(232, 80)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.add_theme_constant_override("line_spacing", -8)
	c.add_child(n)


## La punta de lo que llevas, en la barra: entre el hexagono de tu nivel y el siguiente, segun la EXP
func _punta() -> float:
	var nv := PaseBatalla.nivel()
	if nv >= PaseBatalla.NIVELES:
		return _fin_x()
	if nv < 1:
		return _x_nivel(1)
	var e := PaseBatalla.experiencia()
	var a := PaseBatalla.exp_de_nivel(nv)
	var b := PaseBatalla.exp_de_nivel(nv + 1)
	return _x_nivel(nv) + clampf(float(e - a) / float(maxi(1, b - a)), 0.0, 1.0) * PASO


func _pintar_barra(ci: Control) -> void:
	var largo := _fin_x()
	var y0 := BARRA_Y0
	var y1 := BARRA_Y1
	var punta := _punta()
	# la barra: filo oscuro, el relleno con sus dos brillos y una sombra debajo
	ci.draw_rect(Rect2(-20, y0, largo + 20, y1 - y0), Color8(105, 58, 38))
	ci.draw_rect(Rect2(-20, y0, largo + 20, 3), Color8(112, 56, 81))
	ci.draw_rect(Rect2(-20, y0 + 3, punta + 20, y1 - y0 - 7), BARRA_LLENA)
	ci.draw_rect(Rect2(punta, y0 + 3, maxf(0.0, largo - punta - 3.0), y1 - y0 - 7), BARRA_VACIA)
	ci.draw_rect(Rect2(-20, y0 + 4, punta + 20, 2), Color8(255, 236, 170, 200))
	ci.draw_rect(Rect2(punta, y0 + 4, maxf(0.0, largo - punta - 3.0), 2), Color8(236, 196, 160, 160))
	ci.draw_rect(Rect2(-20, y1 - 6, largo + 17, 2), Color8(238, 186, 129, 150))
	ci.draw_rect(Rect2(-20, y1, largo + 20, 4), Color8(40, 32, 88))
	# los hexagonos, con el nivel, y debajo la EXP que pide cada uno
	var nv := PaseBatalla.nivel()
	for n in range(1, PaseBatalla.NIVELES + 1):
		var x := _x_nivel(n)
		_pintar_hex(ci, Vector2(x, (y0 + y1) * 0.5), n, nv >= n, n == nv)
		var t := _con_puntos(PaseBatalla.exp_de_nivel(n))
		var ts := _f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 27)
		var col := Color.WHITE if nv >= n else Color(0.82, 0.8, 0.95)
		ci.draw_string_outline(_f, Vector2(x - ts.x * 0.5, NUMEROS_Y + 10), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 27, 5,
			Color(0.12, 0.08, 0.3, 0.55))
		ci.draw_string(_f, Vector2(x - ts.x * 0.5, NUMEROS_Y + 10), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 27, col)
	# el final: un hexagono grande con la corona
	var cf := Vector2(largo + 18.0, (y0 + y1) * 0.5)
	var hx := PackedVector2Array()
	for i in 6:
		var a := -PI * 0.5 + i * TAU / 6.0
		hx.append(cf + Vector2(cos(a) * 36.0 * 0.9, sin(a) * 36.0))
	var hb := hx.duplicate()
	hb.append(hx[0])
	var lleno := nv >= PaseBatalla.NIVELES
	ci.draw_colored_polygon(hx, HEX if lleno else Color8(152, 132, 206))
	ci.draw_polyline(hb, CREMA, 4.0, true)
	ci.draw_set_transform(cf + Vector2(-19, -16), 0.0, Vector2(0.62, 0.62))
	_pintar_corona(ci)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _pintar_hex(ci: Control, c: Vector2, n: int, alcanzado: bool, actual: bool) -> void:
	var r := 29.0 if actual else 26.0
	var pts := PackedVector2Array()
	for i in 6:
		var a := -PI * 0.5 + i * TAU / 6.0
		pts.append(c + Vector2(cos(a) * r * 0.9, sin(a) * r))
	if actual:
		# el tuyo: un aro blanco que late
		var k := 0.5 + 0.5 * sin(_t * 4.0)
		var aro := PackedVector2Array()
		for i in 7:
			var a := -PI * 0.5 + i * TAU / 6.0
			aro.append(c + Vector2(cos(a) * (r + 6.0) * 0.9, sin(a) * (r + 6.0)))
		ci.draw_polyline(aro, Color(1, 1, 1, 0.45 + 0.4 * k), 3.5, true)
	var relleno := HEX if alcanzado else Color8(152, 132, 206)
	var borde := HEX_BORDE if alcanzado else Color8(72, 54, 132)
	ci.draw_colored_polygon(pts, relleno)
	var cerrado := pts.duplicate()
	cerrado.append(pts[0])
	ci.draw_polyline(cerrado, borde, 3.0, true)
	var t := str(n)
	var tam := 30 if actual else 27
	var ts := _f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam)
	ci.draw_string(_f, c + Vector2(-ts.x * 0.5 - 1.0, tam * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam,
		HEX_TXT if alcanzado else Color8(60, 40, 120))


func _pintar_etiqueta(ci: Control) -> void:
	var w := ci.size.x
	var cuerpo := PackedVector2Array([Vector2(8, 0), Vector2(w, 0), Vector2(w - 8, 36), Vector2(w * 0.5 + 9, 36),
		Vector2(w * 0.5, 45), Vector2(w * 0.5 - 9, 36), Vector2(0, 36)])
	var borde := cuerpo.duplicate()
	borde.append(cuerpo[0])
	ci.draw_colored_polygon(cuerpo, Color8(78, 66, 202))
	ci.draw_polyline(borde, Color.WHITE, 3.0, true)
	_pintar_ticket_mini(ci, Vector2(24, 18), 1.0)


## Un ticket pequeño azul con la flecha hacia arriba (el de la foto, junto a los puntos)
func _pintar_ticket_mini(ci: CanvasItem, c: Vector2, k: float) -> void:
	var tk := _poli_ticket(Vector2(30, 22) * k, 4.0 * k, c)
	ci.draw_colored_polygon(tk, Color8(70, 170, 255))
	var b := tk.duplicate()
	b.append(tk[0])
	ci.draw_polyline(b, Color8(200, 235, 255), 2.0, true)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7) * k, c + Vector2(6, 0) * k, c + Vector2(2, 0) * k,
		c + Vector2(2, 6) * k, c + Vector2(-2, 6) * k, c + Vector2(-2, 0) * k, c + Vector2(-6, 0) * k]), Color.WHITE)


## El contorno de un ticket (con una muesca redonda a cada lado), centrado en `c`
static func _poli_ticket(tam: Vector2, r: float, c: Vector2) -> PackedVector2Array:
	var hx := tam.x * 0.5
	var hy := tam.y * 0.5
	var p := PackedVector2Array([c + Vector2(-hx, -hy), c + Vector2(hx, -hy)])
	for i in 9:
		var a := -PI * 0.5 - PI * i / 8.0
		p.append(c + Vector2(hx + cos(a) * r, sin(a) * r))
	p.append(c + Vector2(hx, hy))
	p.append(c + Vector2(-hx, hy))
	for i in 9:
		var a := PI * 0.5 - PI * i / 8.0
		p.append(c + Vector2(-hx + cos(a) * r, sin(a) * r))
	return p


# ------------------------------------------------------------------ las cartas
## Lo que se lee de una cosa del pase. El cofre, en masculino ("COFRE RARO"; PaseBatalla lo dice con la rareza de las
## pinturas: "COFRE RARA")
func _nombre_cosa(c: Dictionary) -> String:
	if String(c.get("t", "")) == "cofre":
		return CofreScript.nombre_cofre(int(c.get("v", 0)))
	return PaseBatalla.nombre_de(c)


## UN NIVEL QUE NO DA NADA en esa fila: el hueco de la carta, a trazos y casi transparente (que se vea que no falta nada)
func _carta_vacia(n: int, prem: bool) -> void:
	var tam: Vector2 = P_TAM if prem else G_TAM
	var s: float = P_SESGO if prem else G_SESGO
	var pos := Vector2(_x_nivel(n) + (P_DX if prem else G_DX) - tam.x * 0.5, P_Y if prem else G_Y)
	_dibujo(pos, tam, func(ci: Control):
		ci.draw_colored_polygon(_para(ci.size, s), Color(0.14, 0.06, 0.36, 0.16 if prem else 0.22))
		var b := _para(ci.size, s, 3.0)
		for i in 4:
			var a: Vector2 = b[i]
			var z: Vector2 = b[(i + 1) % 4]
			var largo := a.distance_to(z)
			var k := 0.0
			while k < largo:
				ci.draw_line(a.lerp(z, k / largo), a.lerp(z, minf(k + 12.0, largo) / largo), Color(1.0, 0.94, 1.0, 0.28), 2.5)
				k += 22.0
		# un rombo pequeño en medio
		var c := ci.size * 0.5 + Vector2(s * 0.0, 0.0)
		var r := 9.0
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]),
			Color(1.0, 0.94, 1.0, 0.18)), _contenido)


## "NUEVO ASPECTO", pequeño, arriba de la foto de una carta gratis (las skins del pase)
func _cinta_mini(padre: Control, t: String) -> void:
	var cinta := _dibujo(Vector2(30, 14), Vector2(142, 22), func(ci: Control):
		ci.draw_colored_polygon(_para(ci.size, 4.0), Color(0.02, 0.06, 0.24, 0.72)), padre)
	var l := _texto(t, 14, ORO_TEXTO, _f)
	l.size = cinta.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cinta.add_child(l)


## ¿Carta azul? Las especiales de la fila prémium: pinturas épicas o mejores, el personaje y los diamantes
func _especial(c: Dictionary) -> bool:
	match String(c.get("t", "")):
		"modelo", "diamantes":
			return true
		"pintura":
			return int(SkinsArmas.por_id(str(c.get("v", ""))).get("rareza", 0)) >= 3
	return false


func _carta(d: Dictionary, fila: String) -> void:
	var n := int(d["nivel"])
	var prem := fila == "p"
	var cosas: Array = d["premium"] if prem else d["gratis"]
	if cosas.is_empty():
		_carta_vacia(n, prem)
		return
	var tam: Vector2 = P_TAM if prem else G_TAM
	var s: float = P_SESGO if prem else G_SESGO
	var pos := Vector2(_x_nivel(n) + (P_DX if prem else G_DX) - tam.x * 0.5, P_Y if prem else G_Y)
	# lo principal va en grande; el oro de encima, en una pastilla
	var principal: Dictionary = cosas[0]
	var oro := 0
	for c in cosas:
		if String(c.get("t", "")) != "oro":
			principal = c
			break
	if String(principal.get("t", "")) != "oro":
		for c in cosas:
			if String(c.get("t", "")) == "oro":
				oro += int(c.get("v", 0))
	var tipo := String(principal.get("t", ""))
	var azul := prem and _especial(principal)
	var carta := Control.new()
	carta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carta.position = pos
	carta.size = tam
	carta.pivot_offset = tam * 0.5
	_contenido.add_child(carta)
	var cuerpo := Control.new()
	cuerpo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cuerpo.size = tam
	carta.add_child(cuerpo)
	_dibujo(Vector2.ZERO, tam, func(ci: Control): _pintar_marco(ci, prem, azul, s), cuerpo)
	var con_nombre := not prem and not tipo in ["oro", "cubos"]
	var hueco := Rect2(26, 14, 234, 206) if prem else (Rect2(28, 12, 150, 122) if con_nombre else Rect2(24, 14, 157, 146))
	var img := _imagen(principal, hueco.size, prem)
	img.position = hueco.position
	img.size = hueco.size
	cuerpo.add_child(img)
	var nombre := _nombre_cosa(principal)
	if prem:
		# el nombre, en la franja de abajo (y la cantidad del oro y los diamantes en su pastilla, como el X3 de la foto)
		match tipo:
			"oro":
				nombre = "ORO"
			"diamantes":
				nombre = "DIAMANTES"
			"cubos":
				nombre = "CUBOS DE FUERZA"
		var ln := _texto(nombre, 27 if nombre.length() <= 11 else 24, Color.WHITE, _f, 5,
			(AZUL_BANDA if azul else ORO_BANDA).darkened(0.35), Color(0.2, 0.1, 0.0, 0.35))
		ln.position = Vector2(10, 222)
		ln.size = Vector2(232, 80)
		ln.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ln.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ln.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ln.add_theme_constant_override("line_spacing", -8)
		cuerpo.add_child(ln)
		if tipo in ["oro", "diamantes", "cubos"]:
			_pastilla_cantidad(cuerpo, "X" + _con_puntos(int(principal.get("v", 0))), Vector2(246, 184), 30)
		elif azul:
			_cinta_nuevo(cuerpo, "NUEVO ASPECTO" if tipo in ["pintura", "modelo"] else "ESPECIAL")
	else:
		if con_nombre:
			var tag := _dibujo(Vector2(16, 136), Vector2(156, 26), func(ci: Control):
				ci.draw_colored_polygon(_para(ci.size, 4.0), Color(0.02, 0.06, 0.22, 0.5)), cuerpo)
			var lt := _texto(nombre, 17 if nombre.length() <= 13 else 14, ORO_TEXTO, _f)
			lt.size = tag.size
			lt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			tag.add_child(lt)
			if oro > 0:
				_pastilla_oro(cuerpo, oro, Vector2(174, 104))
			if tipo == "modelo":
				_cinta_mini(cuerpo, "NUEVO ASPECTO")
		else:
			_pastilla_cantidad(cuerpo, "X" + _con_puntos(int(principal.get("v", 0))), Vector2(172, 128), 25)
	# encima: el brillo de "se puede reclamar", la palomita y el candado (sin oscurecer con lo de debajo)
	var e := {"n": n, "fila": fila, "rect": Rect2(pos - Vector2(0, 10), tam + Vector2(0, 34)), "carta": carta,
		"cuerpo": cuerpo, "tam": tam, "sesgo": s, "estado": "", "azul": azul}
	e["sobre"] = _dibujo(Vector2.ZERO, tam, func(ci: Control): _pintar_sobre(ci, e), carta)
	# RECLAMAR: una pastilla verde colgando del borde de abajo
	var ancho_p := 156.0 if prem else 134.0
	var alto_p := 36.0 if prem else 32.0
	var pil := _dibujo(Vector2((tam.x - s) * 0.5 + s * 0.06 - ancho_p * 0.5, tam.y - alto_p * 0.5), Vector2(ancho_p, alto_p),
		func(ci: Control):
			var p := _para(ci.size, 9.0)
			ci.draw_colored_polygon(_para(ci.size, 9.0, -3.0), Color8(20, 90, 40))
			ci.draw_polygon(p, PackedColorArray([Color8(92, 226, 120), Color8(92, 226, 120), VERDE, VERDE])), carta)
	pil.pivot_offset = pil.size * 0.5
	var pt := _texto("RECLAMAR", 20 if prem else 18, Color.WHITE, _f, 5, Color8(20, 90, 40))
	pt.size = pil.size
	pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pil.add_child(pt)
	e["pildora"] = pil
	e["pildora_txt"] = pt
	_cartas.append(e)


func _pintar_marco(ci: Control, prem: bool, azul: bool, s: float) -> void:
	var tam := ci.size
	if prem:
		var a := AZUL_A if azul else ORO_A
		var b := AZUL_B if azul else ORO_B
		ci.draw_colored_polygon(_para(tam, s), AZUL_BORDE if azul else CREMA)
		var dentro := _para(tam, s, 6.0)
		ci.draw_polygon(dentro, PackedColorArray([a, a, b, b]))
		if azul:
			# los pixeles de la carta azul de la foto: cuadraditos mas claros sueltos
			for gy in range(0, int(tam.y / 12.0)):
				for gx in range(0, int(tam.x / 12.0) + 1):
					var r := float(absi(hash(Vector2i(gx * 7 + 3, gy * 13 + 1))) % 100) / 100.0
					if r < 0.55:
						continue
					var q := Vector2(gx * 12.0 + 2.0, gy * 12.0 + 2.0)
					if Geometry2D.is_point_in_polygon(q + Vector2(5, 5), dentro):
						ci.draw_rect(Rect2(q, Vector2(10, 10)), Color(1, 1, 1, 0.04 + (r - 0.55) * 0.18))
		else:
			# un brillo suave arriba a la izquierda
			ci.draw_colored_polygon(_franja(tam, s, 6.0, 6.0, 60.0), Color(1, 1, 1, 0.08))
		ci.draw_colored_polygon(_franja(tam, s, 6.0, tam.y - 86.0, tam.y - 6.0), AZUL_BANDA if azul else ORO_BANDA)
	else:
		ci.draw_colored_polygon(_para(tam, s), MARCO_GRATIS)
		ci.draw_polygon(_para(tam, s, 9.0), PackedColorArray([GRATIS_A, GRATIS_A, GRATIS_B, GRATIS_B]))
		ci.draw_colored_polygon(_franja(tam, s, 9.0, 9.0, 50.0), Color(1, 1, 1, 0.06))


func _pintar_sobre(ci: Control, e: Dictionary) -> void:
	var est := String(e["estado"])
	var tam: Vector2 = e["tam"]
	var s: float = e["sesgo"]
	var prem := String(e["fila"]) == "p"
	if est == "reclamable" or est == "vuelo":
		# el brillo que late alrededor
		var k := 0.5 + 0.5 * sin(_t * 5.0)
		for i in 5:
			var pts := _para(tam, s, -(3.0 + i * 3.5))
			pts.append(pts[0])
			ci.draw_polyline(pts, Color(1.0, 0.96, 0.6, (0.36 - i * 0.065) * (0.5 + 0.5 * k)), 4.0, true)
		var borde := _para(tam, s, 1.5)
		borde.append(borde[0])
		ci.draw_polyline(borde, Color(1.0, 1.0, 0.86, 0.7 + 0.3 * k), 3.5, true)
	elif est == "reclamado":
		# LA PALOMITA: una esquina del color del marco con la marca oscura, como en la foto
		var d := 6.0 if prem else 9.0
		var p0 := Vector2(_bordes(tam, s, d, d).x, d)
		var lado := 58.0 if prem else 52.0
		var y1 := d + lado * 0.9
		var tri := PackedVector2Array([p0, p0 + Vector2(lado, 0), Vector2(_bordes(tam, s, d, y1).x, y1)])
		ci.draw_colored_polygon(tri, (AZUL_BORDE if bool(e["azul"]) else CREMA) if prem else MARCO_GRATIS)
		var o := p0 + Vector2(4, 0)
		ci.draw_polyline(PackedVector2Array([o + Vector2(6, 17), o + Vector2(14, 25), o + Vector2(29, 8)]),
			Color8(40, 40, 56), 5.5, true)
	if est == "nivel" or est == "premium":
		var c := Vector2(tam.x - 31.0, 13.0) if prem else Vector2(tam.x - 24.0, 10.0)
		_pintar_candado(ci, c, 1.0 if prem else 0.82)


## EL CANDADO DORADO de la foto: arco, cuerpo redondeado con filo crema y el ojo de la cerradura. `c`: centro del cuerpo.
func _pintar_candado(ci: CanvasItem, c: Vector2, k: float) -> void:
	var arco := c + Vector2(0, -8) * k
	ci.draw_arc(arco, 11.0 * k, PI, TAU, 20, CREMA, 10.0 * k, true)
	ci.draw_line(arco + Vector2(-11, 0) * k, arco + Vector2(-11, 8) * k, CREMA, 10.0 * k)
	ci.draw_line(arco + Vector2(11, 0) * k, arco + Vector2(11, 8) * k, CREMA, 10.0 * k)
	ci.draw_arc(arco, 11.0 * k, PI, TAU, 20, Color8(236, 170, 30), 4.5 * k, true)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(252, 196, 46)
	sb.border_color = CREMA
	sb.set_border_width_all(int(round(3.0 * k)))
	sb.set_corner_radius_all(int(round(8.0 * k)))
	sb.anti_aliasing = true
	sb.draw(ci.get_canvas_item(), Rect2(c + Vector2(-20, -4) * k, Vector2(40, 32) * k))
	ci.draw_rect(Rect2(c + Vector2(-16, 20) * k, Vector2(32, 4) * k), Color8(214, 140, 20))
	ci.draw_circle(c + Vector2(0, 8) * k, 4.5 * k, Color8(92, 48, 12))
	ci.draw_rect(Rect2(c + Vector2(-2, 9) * k, Vector2(4, 9) * k), Color8(92, 48, 12))


## "X500": la cantidad, en oro sobre una pastilla oscura (como el X3 de la foto). `der`: su esquina de abajo a la derecha
func _pastilla_cantidad(padre: Control, t: String, der: Vector2, tam: int) -> void:
	var ts := _f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam)
	var caja := Vector2(ts.x + 22.0, tam + 6.0)
	var p := _dibujo(der - caja, caja, func(ci: Control):
		ci.draw_colored_polygon(_para(ci.size, 6.0), Color(0.1, 0.05, 0.0, 0.26)), padre)
	var l := _texto(t, tam, ORO_TEXTO, _f, 5, Color(0.35, 0.18, 0.0, 0.8))
	l.size = caja
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)


## "+250" con la moneda, para el oro que va con una habilidad o un personaje
func _pastilla_oro(padre: Control, oro: int, der: Vector2) -> void:
	var t := "+" + _con_puntos(oro)
	var ts := _f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 19)
	var caja := Vector2(ts.x + 40.0, 26.0)
	var p := _dibujo(der - caja, caja, func(ci: Control):
		ci.draw_colored_polygon(_para(ci.size, 5.0), Color(0.02, 0.06, 0.22, 0.55)), padre)
	var ic := IconoLobby.new()
	ic.icono = "moneda"
	ic.color = Color(1.0, 0.78, 0.05)
	ic.position = Vector2(6, 3)
	ic.size = Vector2(20, 20)
	p.add_child(ic)
	var l := _texto(t, 19, Color.WHITE, _f)
	l.position = Vector2(28, 0)
	l.size = Vector2(ts.x + 8.0, caja.y)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)


## "NUEVO ASPECTO", con el bote de pintura, encima del nombre (la carta azul de la foto)
func _cinta_nuevo(padre: Control, t: String) -> void:
	var cinta := _dibujo(Vector2(34, 188), Vector2(200, 30), func(ci: Control):
		ci.draw_colored_polygon(_para(ci.size, 5.0), Color(0.02, 0.08, 0.3, 0.5))
		# el bote de pintura
		ci.draw_rect(Rect2(12, 11, 11, 15), ORO_TEXTO)
		ci.draw_rect(Rect2(14, 7, 7, 4), ORO_TEXTO)
		ci.draw_rect(Rect2(20, 3, 5, 3), Color(1, 1, 1, 0.9))
		for q in [Vector2(28, 3), Vector2(31, 7), Vector2(28, 10)]:
			ci.draw_circle(q, 1.4, Color(1, 1, 1, 0.8)), padre)
	var l := _texto(t, 19, ORO_TEXTO, _f)
	l.position = Vector2(32, 0)
	l.size = Vector2(164, 30)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cinta.add_child(l)


# ------------------------------------------------------------------ las fotos de las cartas
func _imagen(c: Dictionary, tam: Vector2, prem: bool) -> Control:
	var v := str(c.get("v", ""))
	match String(c.get("t", "")):
		"pintura":
			return _foto_arma(String(ARMA_DE_PINTURA.get(v, "carabina_556")), v, "", tam)
		"mazo":
			return _foto_arma(v, "", "sledge", tam)
		"modelo":
			return _foto_retrato(v, prem)
		"habilidad":
			return _foto_habilidad(v, tam)
		"oro":
			return _foto_cocinada("pase:monedas", tam, _montar_monedas())
		"diamantes":
			return _foto_gemas(tam)
		"cubos":
			return _foto_cocinada("pase:cubos", tam, _montar_cubos())
		"cofre":
			var r := clampi(int(c.get("v", 0)), 0, 5)
			return _foto_cocinada("pase:cofre%d" % r, tam, _montar_cofre(r))
	return _icono_suelto("mochila", Color.WHITE, tam)


func _icono_suelto(nombre: String, col: Color, tam: Vector2) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := IconoLobby.new()
	ic.icono = nombre
	ic.color = col
	var lado := minf(tam.x, tam.y) * 0.6
	ic.position = (tam - Vector2(lado, lado)) * 0.5
	ic.size = Vector2(lado, lado)
	c.add_child(ic)
	return c


## Un retrato 3D cocinado UNA vez por el lobby (`_retrato`: se monta, se fotografia y se tira el 3D) y guardado para la
## proxima vez que se abra el pase
func _foto_cocinada(clave: String, tam: Vector2, montar: Callable) -> Control:
	if not is_instance_valid(lobby) or not lobby.has_method("_retrato"):
		return _icono_suelto("moneda", Color(1.0, 0.78, 0.05), tam)
	var px := (tam * RESOLUCION).round()
	var tr: TextureRect = lobby._retrato("%s@%dx%d" % [clave, int(px.x), int(px.y)], px, montar)
	tr.custom_minimum_size = Vector2.ZERO
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return tr


func _foto_arma(id: String, skin: String, kind: String, tam: Vector2) -> Control:
	return _foto_cocinada("pase:%s#%s" % [id, skin], tam, _montar_arma(id, skin, kind))


## LAS ARMAS, EN DIAGONAL (como en la foto: el cañon arriba a la derecha). El arma se gira sobre el eje que mira a la
## camara y se encuadra con las esquinas de verdad de sus mallas ya giradas, asi que llena la carta. Es estatica: el
## lobby la llama cuando le toca en su cola, y para entonces esta pantalla puede estar ya cerrada.
static func _montar_arma(id: String, skin: String, kind: String) -> Callable:
	return func(mundo: Node3D, cam: Camera3D, sv: SubViewport) -> void:
		var wm = AvatarScript.WeaponModelScript.new()
		if kind != "":
			wm.kind = kind
		else:
			var d: Dictionary = Weapons.get_def(id)
			wm.kind = String(d.get("model", d.get("kind", "rifle")))
		wm.arma_id = id
		wm.skin_forzada = skin
		mundo.add_child(wm)
		wm.rotation.x = deg_to_rad(INCLINACION)
		_encuadre(mundo, cam, sv, Vector3(1.0, 0.0, 0.0), 18.0)


static func _montar_monedas() -> Callable:
	return func(mundo: Node3D, cam: Camera3D, sv: SubViewport) -> void:
		_cielo_de_estudio(sv)
		# monedas hexagonales (como el icono del oro), en dos montones y una de pie delante
		var cm := CylinderMesh.new()
		cm.top_radius = 0.5
		cm.bottom_radius = 0.5
		cm.height = 0.14
		cm.radial_segments = 6
		cm.rings = 1
		var cara := CylinderMesh.new()
		cara.top_radius = 0.3
		cara.bottom_radius = 0.34
		cara.height = 0.03
		cara.radial_segments = 4
		cara.rings = 1
		var oro := StandardMaterial3D.new()
		oro.albedo_color = Color(1.0, 0.72, 0.12)
		oro.metallic = 0.55
		oro.roughness = 0.28
		var claro := StandardMaterial3D.new()
		claro.albedo_color = Color(1.0, 0.9, 0.45)
		claro.roughness = 0.25
		claro.emission_enabled = true
		claro.emission = Color(0.3, 0.2, 0.02)
		var poner := func(pos: Vector3, rot: Vector3) -> void:
			var m := Node3D.new()
			m.position = pos
			m.rotation = rot
			mundo.add_child(m)
			var mi := MeshInstance3D.new()
			mi.mesh = cm
			mi.material_override = oro
			m.add_child(mi)
			var mc := MeshInstance3D.new()
			mc.mesh = cara
			mc.material_override = claro
			mc.position.y = 0.08
			m.add_child(mc)
		for i in 5:
			poner.call(Vector3(-0.42 + sin(i * 1.7) * 0.03, i * 0.15, -0.1), Vector3(0, i * 0.4, 0))
		for i in 3:
			poner.call(Vector3(0.5 + sin(i * 2.3) * 0.03, i * 0.15, -0.35), Vector3(0, i * 0.7 + 0.3, 0))
		poner.call(Vector3(0.12, 0.42, 0.45), Vector3(deg_to_rad(72), 0.0, deg_to_rad(-12)))
		_encuadre(mundo, cam, sv, Vector3(0.0, 0.62, 1.0).normalized(), 26.0)


## LOS CUBOS DE FUERZA: tres, amontonados (los de cofre_pantalla.gd)
static func _montar_cubos() -> Callable:
	return func(mundo: Node3D, cam: Camera3D, sv: SubViewport) -> void:
		_cielo_de_estudio(sv)
		CofreScript.montar_cubos(mundo)
		_encuadre(mundo, cam, sv, Vector3(0.0, 0.3, 1.0).normalized(), 24.0)


## EL COFRE de su rareza, de tres cuartos y un poco desde arriba (el de la pantalla de abrirlos)
static func _montar_cofre(r: int) -> Callable:
	return func(mundo: Node3D, cam: Camera3D, sv: SubViewport) -> void:
		_cielo_de_estudio(sv)
		CofreScript.montar_cofre(mundo, r)
		_encuadre(mundo, cam, sv, Vector3(0.5, 0.5, 1.0).normalized(), 22.0)


## LOS DIAMANTES: tres brillantes verdes tallados a caras (dibujados: la gema 3D es translucida y sobre la carta
## salia lavada)
func _foto_gemas(tam: Vector2) -> Control:
	var lado := minf(tam.x, tam.y)
	return _dibujo(Vector2.ZERO, tam, func(ci: Control):
		var c := ci.size * 0.5
		_pintar_gema(ci, c + Vector2(-lado * 0.3, -lado * 0.06), lado * 0.22)
		_pintar_gema(ci, c + Vector2(lado * 0.32, -lado * 0.02), lado * 0.2)
		_pintar_gema(ci, c + Vector2(0.0, lado * 0.06), lado * 0.34)
		var b := c + Vector2(-lado * 0.18, -lado * 0.2)
		ci.draw_colored_polygon(PackedVector2Array([b + Vector2(0, -12), b + Vector2(3, -3), b + Vector2(12, 0),
			b + Vector2(3, 3), b + Vector2(0, 12), b + Vector2(-3, 3), b + Vector2(-12, 0), b + Vector2(-3, -3)]),
			Color(1, 1, 1, 0.95)), null)


## Un brillante visto de lado: la corona con sus caras arriba, el cinto y el pabellon en punta abajo
func _pintar_gema(ci: CanvasItem, c: Vector2, r: float) -> void:
	var claro := Color(0.62, 1.0, 0.78)
	var medio := Color(0.18, 0.86, 0.5)
	var oscuro := Color(0.04, 0.52, 0.3)
	var filo := Color(0.02, 0.26, 0.14)
	var iz := c + Vector2(-r, -0.08 * r)
	var de := c + Vector2(r, -0.08 * r)
	var ti := c + Vector2(-0.52 * r, -0.62 * r)
	var td := c + Vector2(0.52 * r, -0.62 * r)
	var punta := c + Vector2(0.0, 0.98 * r)
	var todo := PackedVector2Array([iz, ti, td, de, punta])
	var borde := todo.duplicate()
	borde.append(iz)
	ci.draw_colored_polygon(todo, medio)
	# la corona: tres caras, la de en medio (la tabla) la mas clara
	var m1 := c + Vector2(-0.34 * r, -0.08 * r)
	var m2 := c + Vector2(0.34 * r, -0.08 * r)
	ci.draw_colored_polygon(PackedVector2Array([iz, ti, m1]), claro.lerp(medio, 0.35))
	ci.draw_colored_polygon(PackedVector2Array([ti, td, m2, m1]), claro)
	ci.draw_colored_polygon(PackedVector2Array([td, de, m2]), medio)
	# el pabellon: cuatro caras hacia la punta, de claro a oscuro
	ci.draw_colored_polygon(PackedVector2Array([iz, m1, punta]), medio)
	ci.draw_colored_polygon(PackedVector2Array([m1, c + Vector2(0, -0.08 * r), punta]), claro.lerp(medio, 0.5))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -0.08 * r), m2, punta]), medio.lerp(oscuro, 0.4))
	ci.draw_colored_polygon(PackedVector2Array([m2, de, punta]), oscuro)
	ci.draw_polyline(borde, filo, maxf(2.0, r * 0.07), true)
	ci.draw_line(iz, de, Color(filo, 0.5), maxf(1.5, r * 0.04), true)


## Un cielo para los reflejos (el fondo sigue transparente): sin el, las gemas y las monedas salian planas, sin brillos.
## Es el mismo de la pantalla de recompensa. Toca solo el entorno de la ventana que cocina este retrato.
static func _cielo_de_estudio(sv: SubViewport) -> void:
	for c in sv.get_children():
		if c is WorldEnvironment and (c as WorldEnvironment).environment != null:
			var env: Environment = (c as WorldEnvironment).environment
			var cielo := ProceduralSkyMaterial.new()
			cielo.sky_top_color = Color(0.55, 0.7, 1.0)
			cielo.sky_horizon_color = Color(0.95, 0.95, 1.0)
			cielo.ground_bottom_color = Color(0.08, 0.07, 0.12)
			cielo.ground_horizon_color = Color(0.5, 0.5, 0.6)
			env.sky = Sky.new()
			env.sky.sky_material = cielo
			env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
			env.tonemap_mode = Environment.TONE_MAPPER_FILMIC


## Encuadre justo: todas las esquinas de todas las mallas (ya giradas) dentro de la foto, mirando desde `dir`
static func _encuadre(mundo: Node3D, cam: Camera3D, sv: SubViewport, dir: Vector3, fov: float) -> void:
	var pts: Array = []
	_esquinas(mundo, pts)
	if pts.is_empty():
		return
	var lo: Vector3 = pts[0]
	var hi: Vector3 = pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var centro := (lo + hi) * 0.5
	mundo.position -= centro
	cam.fov = fov
	var ty := tan(deg_to_rad(fov) * 0.5)
	var tx := ty * float(sv.size.x) / maxf(1.0, float(sv.size.y))
	var adelante := -dir
	var der := Vector3.UP.cross(adelante).normalized()
	if der.length_squared() < 0.5:
		der = Vector3.RIGHT
	var arr := adelante.cross(der).normalized()
	var dist := 0.05
	for p in pts:
		var e: Vector3 = p - centro
		dist = maxf(dist, absf(e.dot(der)) / tx + e.dot(dir))
		dist = maxf(dist, absf(e.dot(arr)) / ty + e.dot(dir))
	cam.position = dir * dist * 1.05
	cam.near = 0.01
	cam.look_at(Vector3.ZERO, Vector3.UP)


static func _esquinas(n: Node, pts: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null and (c as MeshInstance3D).is_visible_in_tree():
			var mi := c as MeshInstance3D
			var a := mi.get_aabb()
			var t := mi.global_transform
			for i in 8:
				pts.append(t * (a.position + a.size * Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1)))
		_esquinas(c, pts)


## El retrato del personaje (horneado con --retratos), recortado de la cabeza a la cadera
func _foto_retrato(nombre: String, prem: bool) -> Control:
	var ruta := "res://avatar/retratos/%s.png" % nombre.to_lower().replace(" ", "_")
	if not ResourceLoader.exists(ruta):
		return _icono_suelto("usuario", Color.WHITE, Vector2(150, 150))
	var at := AtlasTexture.new()
	at.atlas = load(ruta)
	at.region = Rect2(52, 4, 216, 190) if prem else Rect2(62, 4, 196, 160)
	var tr := TextureRect.new()
	tr.texture = at
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	return tr


## Una habilidad: su icono en el hexagono, con un halo de su color
func _foto_habilidad(id: String, tam: Vector2) -> Control:
	var d: Dictionary = HabilidadScript.datos(id)
	var col: Color = d.get("color", Color.WHITE)
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lado := minf(tam.x, tam.y)
	_dibujo(Vector2.ZERO, tam, func(ci: Control):
		for i in 9:
			ci.draw_circle(ci.size * 0.5, lado * 0.55 * (1.0 - i / 9.0), Color(col, 0.035 + i * 0.012)), c)
	var ic := IconoLobby.new()
	ic.icono = String(d.get("icono", "habilidades"))
	ic.hexagono = true
	ic.color_hex = col
	ic.color = col
	ic.grosor = 8.0
	var l := lado * 0.84
	ic.position = (tam - Vector2(l, l)) * 0.5
	ic.size = Vector2(l, l)
	c.add_child(ic)
	return c


# ================================================================== el panel PASE PRÉMIUM
func _forma_panel() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, PANEL_Y0), Vector2(PANEL_X_ARRIBA - 28.0, PANEL_Y0),
		Vector2(PANEL_X_ARRIBA, PANEL_Y0 + 28.0), Vector2(PANEL_X_ABAJO, PANEL_Y1), Vector2(0, PANEL_Y1)])


func _montar_panel() -> void:
	var panel := _dibujo(Vector2.ZERO, Vector2(PANEL_X_ARRIBA + 24.0, ALTO), _pintar_panel, _raiz)
	panel.forma = _forma_panel()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP      # lo que se toca en el panel no llega a las cartas de debajo
	# la corona y PASE PRÉMIUM
	_dibujo(Vector2(50, 170), Vector2(62, 48), _pintar_corona, panel)
	var t := _texto("PASE PRÉMIUM", 41, ORO_TEXTO, _f, 9, Color8(168, 88, 10))
	t.position = Vector2(120, 166)
	panel.add_child(t)
	# el Comando (lo pone _montar_personaje cuando esta)
	_foto_personaje = TextureRect.new()
	_foto_personaje.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_foto_personaje.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_foto_personaje.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_foto_personaje.position = Vector2(0, 222)
	_foto_personaje.size = Vector2(440, 420)
	panel.add_child(_foto_personaje)
	_premium_lema = _texto("Accede a contenido exclusivo de temporada", 28, Color.WHITE, _fb, 0, Color.BLACK,
		Color(0.2, 0.08, 0.45, 0.6))
	_premium_lema.position = Vector2(44, 636)
	_premium_lema.size = Vector2(330, 110)
	_premium_lema.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_premium_lema.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_premium_lema.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_premium_lema.add_theme_constant_override("line_spacing", -4)
	panel.add_child(_premium_lema)
	# DESBLOQUEAR
	_boton_premium = _boton(Rect2(52, 752, 316, 80), _pintar_boton_premium, _pulsar_premium, panel)
	_premium_txt = _texto("DESBLOQUEAR", 27, Color.WHITE, _f, 4, Color(0.1, 0.05, 0.3, 0.5))
	_premium_txt.position = Vector2(80, 6)
	_premium_txt.size = Vector2(224, 42)
	_premium_txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_boton_premium.add_child(_premium_txt)
	var gema := IconoLobby.new()
	gema.icono = "credito"
	gema.color = Color(0.45, 0.9, 0.5)
	gema.position = Vector2(82, 48)
	gema.size = Vector2(20, 20)
	_boton_premium.add_child(gema)
	_premium_gema = gema
	_premium_precio = _texto("", 21, Color(0.86, 0.9, 1.0), _f)
	_premium_precio.position = Vector2(106, 43)
	_premium_precio.size = Vector2(200, 30)
	_premium_precio.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_boton_premium.add_child(_premium_precio)


func _pintar_panel(ci: Control) -> void:
	var forma := _forma_panel()
	# el resplandor del filo derecho, por fuera
	var filo := PackedVector2Array([Vector2(0, PANEL_Y0), forma[1], forma[2], forma[3]])
	for i in 4:
		ci.draw_polyline(filo, Color(0.62, 0.72, 1.0, 0.1 - i * 0.02), 10.0 + i * 8.0, true)
	var arriba := Color8(146, 96, 252)
	var abajo := Color8(136, 80, 248)
	ci.draw_polygon(forma, PackedColorArray([arriba, arriba, arriba, abajo, abajo]))
	# un rayo de luz en diagonal, recortado a la forma del panel
	var rayo := PackedVector2Array([Vector2(170, PANEL_Y0), Vector2(290, PANEL_Y0), Vector2(20, PANEL_Y1), Vector2(-100, PANEL_Y1)])
	for p in Geometry2D.intersect_polygons(rayo, forma):
		ci.draw_colored_polygon(p, Color(1, 1, 1, 0.07))
	var rayo2 := PackedVector2Array([Vector2(330, PANEL_Y0), Vector2(370, PANEL_Y0), Vector2(120, PANEL_Y1), Vector2(80, PANEL_Y1)])
	for p in Geometry2D.intersect_polygons(rayo2, forma):
		ci.draw_colored_polygon(p, Color(1, 1, 1, 0.05))
	# el filo de luz
	ci.draw_polyline(filo, Color8(236, 226, 255), 4.0, true)
	ci.draw_line(Vector2(0, PANEL_Y1), forma[3], Color(0.1, 0.05, 0.3, 0.35), 3.0)


func _pintar_corona(ci: Control) -> void:
	var p := PackedVector2Array([Vector2(3, 34), Vector2(3, 8), Vector2(17, 22), Vector2(31, 2), Vector2(45, 22),
		Vector2(59, 8), Vector2(59, 34)])
	var borde := p.duplicate()
	borde.append(p[0])
	ci.draw_polyline(borde, Color8(168, 88, 10), 6.0, true)
	ci.draw_colored_polygon(p, Color8(255, 212, 60))
	ci.draw_rect(Rect2(1, 34, 60, 13), Color8(168, 88, 10))
	ci.draw_rect(Rect2(3, 36, 56, 9), Color8(246, 178, 30))


func _pintar_boton_premium(ci: Control) -> void:
	var tam := ci.size
	var activo := PaseBatalla.premium()
	var base := Color8(255, 200, 60) if activo else (Color8(64, 150, 90) if _confirmar_t > 0.0 else MORADO_BOTON)
	ci.draw_colored_polygon(_para(tam, 14.0, -3.0), Color(0.08, 0.04, 0.28, 0.45))
	ci.draw_colored_polygon(_para(tam, 14.0), base)
	ci.draw_colored_polygon(_franja(tam, 14.0, 0.0, 0.0, 4.0), base.lightened(0.3))
	ci.draw_colored_polygon(_franja(tam, 14.0, 0.0, tam.y - 5.0, tam.y), base.darkened(0.3))
	if not activo:
		_pintar_ticket_oro(ci, Vector2(44, tam.y * 0.5))


## El ticket dorado con la corona del boton DESBLOQUEAR
func _pintar_ticket_oro(ci: CanvasItem, c: Vector2) -> void:
	var tk := _poli_ticket(Vector2(46, 34), 5.0, c)
	var b := tk.duplicate()
	b.append(tk[0])
	ci.draw_polyline(b, Color8(150, 80, 10), 5.0, true)
	ci.draw_colored_polygon(tk, Color8(255, 208, 70))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-11, 7), c + Vector2(-11, -6), c + Vector2(-5, 0), c + Vector2(0, -9),
		c + Vector2(5, 0), c + Vector2(11, -6), c + Vector2(11, 7)]), Color8(190, 110, 10))


# ================================================================== la cabecera
func _montar_cabecera() -> void:
	_dibujo(Vector2(58, 22), Vector2(100, 84), _pintar_ticket_grande, _raiz)
	# LOS DIAS QUE QUEDAN, en su pastilla con el reloj
	_dias_chip = _dibujo(Vector2(170, 22), Vector2(130, 44), func(ci: Control):
		ci.draw_rect(Rect2(Vector2.ZERO, ci.size), Color(0.14, 0.08, 0.34, 0.42))
		var c := Vector2(22, 22)
		ci.draw_circle(c, 11.0, Color.WHITE)
		ci.draw_line(c, c + Vector2(0, -7), Color8(70, 50, 150), 3.0)
		ci.draw_line(c, c + Vector2(5, 2), Color8(70, 50, 150), 3.0), _raiz)
	_dias_txt = _texto("", 28, Color.WHITE, _fuente(700, false))
	_dias_txt.position = Vector2(40, 0)
	_dias_txt.size = Vector2(90, 44)
	_dias_txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dias_chip.add_child(_dias_txt)
	# PASE DE BATALLA / TEMPORADA 1
	var fila := HBoxContainer.new()
	fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fila.position = Vector2(166, 62)
	fila.add_theme_constant_override("separation", 0)
	_raiz.add_child(fila)
	# en una pantalla estrecha (4:3) el titulo se achica para no meterse debajo de TAREAS
	var t1 := "PASE DE BATALLA"
	var t2 := " / " + PaseBatalla.nombre_temporada()
	var ancho := _f.get_string_size(t1 + t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x
	var cabe := _w - 520.0 - 166.0 - 24.0
	var tam := 44 if ancho <= cabe else maxi(24, int(floor(44.0 * cabe / ancho)))
	fila.add_child(_texto(t1, tam, CIAN, _f, 8, Color8(58, 44, 150)))
	fila.add_child(_texto(t2, tam, Color.WHITE, _f, 8, Color8(58, 44, 150)))
	# TAREAS (las misiones del lobby) y la X
	var bt := _boton(Rect2(_w - 520, 0, 306, 108), func(ci: Control):
		var w := ci.size.x
		var h := ci.size.y
		var cara := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(16, h), Vector2(0, h - 16)])
		ci.draw_polygon(cara, PackedColorArray([Color8(66, 46, 142), Color8(66, 46, 142), Color8(96, 54, 160),
			Color8(96, 54, 160), Color8(96, 54, 160)]))
		# el icono: una hoja con su tabla
		var o := Vector2(34, 36)
		ci.draw_rect(Rect2(o, Vector2(34, 42)), Color.WHITE)
		ci.draw_rect(Rect2(o + Vector2(0, 10), Vector2(34, 3)), Color8(80, 50, 150))
		for k in 3:
			ci.draw_rect(Rect2(o + Vector2(4, 17 + k * 8), Vector2(9, 5)), Color8(80, 50, 150))
			ci.draw_rect(Rect2(o + Vector2(16, 17 + k * 8), Vector2(14, 5)), Color8(80, 50, 150)), _ir_tareas, _raiz)
	var tt := _texto("TAREAS", 38, Color.WHITE, _f)
	tt.position = Vector2(84, 30)
	tt.size = Vector2(210, 50)
	tt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bt.add_child(tt)
	var bx := _boton(Rect2(_w - 212, 0, 212, 88), func(ci: Control):
		var w := ci.size.x
		var h := ci.size.y
		ci.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(16, h),
			Vector2(0, h - 16)]), Color8(140, 55, 122)), _cerrar, _raiz)
	var xt := _texto("X", 50, Color.WHITE, _f)
	xt.size = Vector2(212, 80)
	xt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bx.add_child(xt)


func _pintar_ticket_grande(ci: Control) -> void:
	ci.draw_set_transform(ci.size * 0.5, deg_to_rad(-9.0), Vector2.ONE)
	var tk := _poli_ticket(Vector2(84, 60), 9.0, Vector2.ZERO)
	var sombra := _poli_ticket(Vector2(84, 60), 9.0, Vector2(3, 5))
	ci.draw_colored_polygon(sombra, Color(0.1, 0.04, 0.3, 0.35))
	var b := tk.duplicate()
	b.append(tk[0])
	ci.draw_polyline(b, Color8(214, 226, 255), 7.0, true)
	var cols := PackedColorArray()
	for p in tk:
		cols.append(Color8(128, 132, 255).lerp(Color8(84, 70, 226), clampf((p.y + 30.0) / 60.0, 0.0, 1.0)))
	ci.draw_polygon(tk, cols)
	var dentro := _poli_ticket(Vector2(64, 42), 6.0, Vector2.ZERO)
	var bd := dentro.duplicate()
	bd.append(dentro[0])
	ci.draw_polyline(bd, Color(1, 1, 1, 0.3), 2.0, true)
	var est := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + i * TAU / 10.0
		var r := 17.0 if i % 2 == 0 else 7.5
		est.append(Vector2(cos(a) * r, sin(a) * r + 1.0))
	var eb := est.duplicate()
	eb.append(est[0])
	ci.draw_polyline(eb, Color.WHITE, 4.0, true)
	ci.draw_colored_polygon(est, Color8(120, 200, 255))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ================================================================== IR A BATALLA
func _montar_batalla() -> void:
	_dibujo(Vector2(_w - 478, 742), Vector2(478, ALTO - 742), func(ci: Control):
		ci.draw_colored_polygon(PackedVector2Array([Vector2(28, 0), Vector2(ci.size.x, 0), ci.size, Vector2(0, ci.size.y)]),
			Color8(41, 34, 86, 235)), _raiz)
	var pes := _dibujo(Vector2(_w - 432, 731), Vector2(356, 44), func(ci: Control):
		var w := ci.size.x
		ci.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w - 12, ci.size.y),
			Vector2(0, ci.size.y)]), Color8(55, 61, 149))
		_pintar_ticket_mini(ci, Vector2(26, 22), 1.05), _raiz)
	var fila := HBoxContainer.new()
	fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fila.position = Vector2(50, 0)
	fila.size = Vector2(300, 44)
	fila.add_theme_constant_override("separation", 0)
	pes.add_child(fila)
	_exp_txt = _texto("", 25, Color.WHITE, _f)
	_exp_txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_exp_txt.size_flags_vertical = Control.SIZE_FILL
	fila.add_child(_exp_txt)
	_exp_de = _texto("", 25, Color(0.72, 0.74, 0.88), _f)
	_exp_de.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_exp_de.size_flags_vertical = Control.SIZE_FILL
	fila.add_child(_exp_de)
	var b := _boton(Rect2(_w - 456, 775, 368, 104), func(ci: Control):
		var tam := ci.size
		var forma := _para(tam, 20.0)
		ci.draw_colored_polygon(_para(tam, 20.0, -3.0), Color(0.05, 0.04, 0.16, 0.5))
		ci.draw_colored_polygon(forma, AMARILLO_BOTON)
		# los destellos en diagonal de la foto
		for r in [[70.0, 150.0, 0.16], [190.0, 215.0, 0.12], [300.0, 320.0, 0.1]]:
			var brillo := PackedVector2Array([Vector2(r[0], 0), Vector2(r[1], 0), Vector2(r[1] - 60.0, tam.y),
				Vector2(r[0] - 60.0, tam.y)])
			for p in Geometry2D.intersect_polygons(brillo, forma):
				ci.draw_colored_polygon(p, Color(1, 1, 1, r[2]))
		ci.draw_colored_polygon(_franja(tam, 20.0, 0.0, tam.y - 6.0, tam.y), AMARILLO_BOTON.darkened(0.28)), _ir_a_batalla, _raiz)
	var bt := _texto("IR A BATALLA", 44, TINTA, _f)
	bt.size = Vector2(368, 100)
	bt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(bt)


# ================================================================== el Comando entre cubos de fuerza
func _montar_personaje() -> void:
	# primero que salga la pantalla: montar el muñeco cuesta ~0,7 s (sus voxels se mallan en GDScript)
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or _cerrando:
		return
	_vp = SubViewport.new()
	_vp.size = Vector2i(572, 546)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.74, 0.7, 0.95)
	env.ambient_light_energy = 0.78
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	for l in [[Vector3(-35, -30, 0), Color(1.0, 0.95, 0.9), 1.35], [Vector3(-10, 150, 0), Color(0.55, 0.85, 1.0), 1.1],
			[Vector3(-25, 200, 0), Color(0.9, 0.8, 1.0), 0.6]]:
		var dl := DirectionalLight3D.new()
		dl.rotation_degrees = l[0]
		dl.light_color = l[1]
		dl.light_energy = l[2]
		_vp.add_child(dl)
	var i := 0
	for k in LobbyScript.SKINS.size():
		if String(LobbyScript.SKINS[k]["n"]) == "Comando":
			i = k
	var sk: Dictionary = LobbyScript.SKINS[i]
	var av = AvatarScript.new()
	_vp.add_child(av)
	av.build(1.75, false, sk["c"], true, false, "" if i == 0 else String(sk["n"]), sk["r"])
	av.aplicar_acabado(float(sk["m"]), float(sk["g"]))
	# SIN ARMA (2026-09-29, pedido: "que no agarre el arma ni en el pase")
	av.unequip_weapon()
	av.play("idle_1")
	av.rotation.y = PI + 0.42          # el modelo mira a -Z: de tres cuartos hacia la camara
	var cam := Camera3D.new()
	cam.fov = 31.0
	cam.position = Vector3(0.0, 0.94, 3.3)
	_vp.add_child(cam)
	cam.look_at(Vector3(0.0, 0.93, 0.0), Vector3.UP)
	# LOS CUBOS DE FUERZA (cofre_pantalla.gd: marco violeta, energia cian y el rayo), y chispas de energia sueltas
	var caja := BoxMesh.new()
	var chispa := StandardMaterial3D.new()
	chispa.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	chispa.albedo_color = Color(0.6, 1.0, 1.0)
	chispa.emission_enabled = true
	chispa.emission = Color(0.45, 0.95, 1.0)
	chispa.emission_energy_multiplier = 3.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_cubos.clear()
	for c in CUBOS:
		var n := Node3D.new()
		n.position = c[0]
		n.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		_vp.add_child(n)
		if float(c[1]) >= 0.1:
			n.add_child(CofreScript.cubo_fuerza(float(c[1]) * 1.12))
		else:
			var m := MeshInstance3D.new()
			m.mesh = caja
			m.material_override = chispa
			m.scale = Vector3.ONE * float(c[1]) * 0.7
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.add_child(m)
		_cubos.append([n, c[0], rng.randf() * TAU, Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.8, 0.8), 0.3)])
	_poner_foto_personaje()
	_foto_personaje.modulate.a = 0.0
	create_tween().tween_property(_foto_personaje, "modulate:a", 1.0, 0.3)


func _poner_foto_personaje() -> void:
	if _vp != null and is_instance_valid(_foto_personaje):
		_foto_personaje.texture = _vp.get_texture()


# ================================================================== el estado
func _refrescar() -> void:
	var nv := PaseBatalla.nivel()
	for e in _cartas:
		var n := int(e["n"])
		var fila := String(e["fila"])
		var est := ""
		if _en_vuelo.size() == 2 and int(_en_vuelo[0]) == n and String(_en_vuelo[1]) == fila:
			est = "vuelo"
		elif PaseBatalla.reclamado(n, fila):
			est = "reclamado"
		elif PaseBatalla.se_puede(n, fila):
			est = "reclamable"
		elif nv < n:
			est = "nivel"
		elif fila == "p" and not PaseBatalla.premium():
			est = "premium"
		e["estado"] = est
		(e["cuerpo"] as Control).modulate = Color(0.84, 0.8, 0.92) if est == "nivel" else Color.WHITE
		var sobre: _Dibujo = e["sobre"]
		sobre.animado = est == "reclamable" or est == "vuelo"
		sobre.queue_redraw()
		var pil: Control = e["pildora"]
		pil.visible = est == "reclamable" or est == "vuelo"
		(e["pildora_txt"] as Label).text = "· · ·" if est == "vuelo" else "RECLAMAR"
	_contenido.queue_redraw()
	(_contenido as _Dibujo).animado = true          # el aro de tu nivel late
	var punta := _punta()
	_etiqueta_txt.text = _con_puntos(PaseBatalla.experiencia())
	var ancho := _f.get_string_size(_etiqueta_txt.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x + 60.0
	_etiqueta.size = Vector2(maxf(120.0, ancho), 46)
	_etiqueta.position = Vector2(punta - _etiqueta.size.x * 0.5, BARRA_Y0 - 50.0)
	_etiqueta.queue_redraw()
	var par: Array = PaseBatalla.exp_en_nivel(PaseBatalla.experiencia())
	_exp_txt.text = "EXP " + _con_puntos(int(par[0]))
	_exp_de.text = "/" + _con_puntos(int(par[1]))
	_dias_txt.text = "%d d" % PaseBatalla.dias_restantes()
	_dias_chip.size.x = 52.0 + _dias_txt.get_theme_font("font").get_string_size(_dias_txt.text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, 28).x + 16.0
	_dias_chip.queue_redraw()
	_dias_chip.visible = false   # los dias de la temporada no se enseñan (pedido)
	_refrescar_premium()


func _refrescar_premium() -> void:
	var activo := PaseBatalla.premium()
	_premium_gema.visible = not activo and Cuenta.conectado()
	if activo:
		_premium_txt.text = "PREMIUM ACTIVO"
		_premium_txt.position = Vector2(0, 0)
		_premium_txt.size = Vector2(316, 80)
		_premium_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_premium_txt.add_theme_color_override("font_color", TINTA)
		_premium_txt.add_theme_constant_override("outline_size", 0)
		_premium_precio.text = ""
		_premium_lema.text = "Tienes todo el contenido exclusivo de la temporada"
	else:
		_premium_txt.text = "¿CONFIRMAR?" if _confirmar_t > 0.0 else ("COMPRANDO..." if _comprando else "DESBLOQUEAR")
		if Cuenta.conectado():
			_premium_precio.text = _con_puntos(PaseBatalla.precio_premium())
			_premium_precio.position.x = 106
		else:
			_premium_precio.text = "SOLO CON CUENTA"
			_premium_precio.position.x = 82
		_premium_lema.text = "Accede a contenido exclusivo de temporada"
	_boton_premium.queue_redraw()
	for c in _boton_premium.get_children():
		if c is CanvasItem:
			(c as CanvasItem).queue_redraw()


func _process(dt: float) -> void:
	_t += dt
	if _aviso_t > 0.0:
		_aviso_t -= dt
		_aviso.modulate.a = clampf(_aviso_t / 0.4, 0.0, 1.0)
	if _confirmar_t > 0.0:
		_confirmar_t -= dt
		if _confirmar_t <= 0.0:
			_refrescar_premium()
	if not _en_vuelo.is_empty():
		_vuelo_t += dt
		if _vuelo_t > 15.0:
			_en_vuelo = []
			_avisar("El servidor no contesta: vuelve a intentarlo")
			_refrescar()
	# la pista: la rueda va a su sitio con suavidad; soltada, sigue con la inercia y se va frenando
	if not _pulsado:
		if _obj >= 0.0:
			_scroll = lerpf(_scroll, _obj, 1.0 - exp(-11.0 * dt))
			if absf(_scroll - _obj) < 0.5:
				_scroll = _obj
				_obj = -1.0
		elif absf(_vel) > 6.0:
			_scroll += _vel * dt
			_vel *= exp(-3.4 * dt)
			if _scroll <= 0.0 or _scroll >= _scroll_max():
				_scroll = clampf(_scroll, 0.0, _scroll_max())
				_vel = 0.0
		else:
			_vel = 0.0
	_aplicar_scroll()
	# las pastillas de RECLAMAR laten
	var k := 1.0 + 0.05 * sin(_t * 5.0)
	for e in _cartas:
		var pil: Control = e["pildora"]
		if pil.visible:
			pil.scale = Vector2(k, k)
	for c in _cubos:
		var n: Node3D = c[0]
		if is_instance_valid(n):
			n.position = (c[1] as Vector3) + Vector3(0, sin(_t * 1.3 + float(c[2])) * 0.05, 0)
			n.rotation += (c[3] as Vector3) * dt


func _aplicar_scroll() -> void:
	if not is_instance_valid(_contenido):
		return
	_contenido.position.x = -roundf(_scroll)
	if absf(_scroll - _scroll_pintado) > 0.5:
		_scroll_pintado = _scroll
		_fondo.queue_redraw()


## Deja el nivel `n` en medio de lo que se ve de la pista
func _ir_a(n: int, animado: bool = true) -> void:
	var obj := clampf(_x_nivel(clampi(n, 1, PaseBatalla.NIVELES)) - (PANEL_X_ARRIBA + _w) * 0.5, 0.0, _scroll_max())
	if animado:
		_obj = obj
		_vel = 0.0
	else:
		_scroll = obj
		_obj = -1.0
		_aplicar_scroll()


# ================================================================== el dedo en la pista
func _entrada_pista(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		var st := e as InputEventScreenTouch
		if st.pressed and _toque < 0:
			_toque = st.index
			_apoyar(st.position)
		elif not st.pressed and st.index == _toque:
			_toque = -1
			_soltar(st.position)
	elif e is InputEventScreenDrag:
		var sd := e as InputEventScreenDrag
		if sd.index == _toque:
			_arrastrar(sd.position)
	elif e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_apoyar(mb.position)
				elif _pulsado:
					_soltar(mb.position)
			MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
				if mb.pressed:
					_rueda(1.0)
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
				if mb.pressed:
					_rueda(-1.0)
	elif e is InputEventMouseMotion and _pulsado and _toque < 0:
		_arrastrar((e as InputEventMouseMotion).position)
	elif e is InputEventPanGesture:
		_obj = -1.0
		_scroll = clampf(_scroll + (e as InputEventPanGesture).delta.x * 40.0, 0.0, _scroll_max())


func _apoyar(p: Vector2) -> void:
	_pulsado = true
	_p0 = p
	_p_ult = p
	_t_ult = Time.get_ticks_msec()
	_movido = 0.0
	_vel = 0.0
	_obj = -1.0
	_quitar_burbuja()


func _arrastrar(p: Vector2) -> void:
	if not _pulsado:
		return
	var dx := p.x - _p_ult.x
	_movido = maxf(_movido, p.distance_to(_p0))
	_scroll = clampf(_scroll - dx, 0.0, _scroll_max())
	var ahora := Time.get_ticks_msec()
	var dt := float(ahora - _t_ult) / 1000.0
	if dt > 0.0:
		_vel = lerpf(_vel, -dx / dt, 0.4)
	_p_ult = p
	_t_ult = ahora


func _soltar(p: Vector2) -> void:
	_pulsado = false
	if _movido < 14.0 and p.distance_to(_p0) < 14.0:
		_vel = 0.0
		_tocar(p)
		return
	if Time.get_ticks_msec() - _t_ult > 90:
		_vel = 0.0                  # se paro antes de soltar: sin inercia
	_vel = clampf(_vel, -7000.0, 7000.0)


func _rueda(sentido: float) -> void:
	_vel = 0.0
	_obj = clampf((_obj if _obj >= 0.0 else _scroll) + sentido * PASO, 0.0, _scroll_max())


func _tocar(p: Vector2) -> void:
	var q := p + Vector2(_scroll, 0.0)
	for e in _cartas:
		if (e["rect"] as Rect2).has_point(q):
			_tocar_carta(e)
			return


func _carta_de(n: int, fila: String) -> Dictionary:
	for e in _cartas:
		if int(e["n"]) == n and String(e["fila"]) == fila:
			return e
	return {}


# ================================================================== reclamar
func _tocar_carta(e: Dictionary) -> void:
	var n := int(e["n"])
	var fila := String(e["fila"])
	if PaseBatalla.se_puede(n, fila):
		if not _en_vuelo.is_empty():
			_avisar("Un momento: el servidor esta dando lo anterior")
			return
		match PaseBatalla.reclamar(n, fila):
			"hecho":
				_al_reclamar(n, fila)
			"enviado":
				_en_vuelo = [n, fila]
				_vuelo_t = 0.0
				Audio.ui("aceptar", -6.0)
				_refrescar()
			_:
				Audio.ui("atras", -8.0)
				_avisar("No se pudo reclamar")
		return
	Audio.ui("pasar", -10.0)
	var cosas: Array = PaseBatalla.niveles()[n - 1]["premium" if fila == "p" else "gratis"]
	var nombres: Array = []
	for c in cosas:
		nombres.append(_nombre_cosa(c))
	var estado := ""
	match String(e["estado"]):
		"reclamado":
			estado = "YA ES TUYO"
		"nivel":
			estado = "SE CONSIGUE EN EL NIVEL %d" % n
			if fila == "p" and not PaseBatalla.premium():
				estado += " · PRÉMIUM"
		"premium":
			estado = "NECESITAS EL PASE PRÉMIUM"
		"vuelo":
			estado = "RECLAMANDO..."
	_burbuja(e, " + ".join(nombres), estado)


func _al_reclamar(n: int, fila: String) -> void:
	Audio.ui("activar", -4.0)
	_refrescar()
	for e in _cartas:
		if int(e["n"]) == n and String(e["fila"]) == fila:
			var carta: Control = e["carta"]
			var tw := create_tween()
			tw.tween_property(carta, "scale", Vector2(1.08, 1.08), 0.09)
			tw.tween_property(carta, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var cosas: Array = PaseBatalla.niveles()[n - 1]["premium" if fila == "p" else "gratis"]
	var arts: Array = []
	var oro := 0
	var diamantes := 0
	var cubos := 0
	var cofres: Array = []
	for c in cosas:
		match String(c.get("t", "")):
			"oro":
				oro += int(c.get("v", 0))
			"diamantes":
				diamantes += int(c.get("v", 0))
			"cubos":
				cubos += int(c.get("v", 0))
			"cofre":
				cofres.append(int(c.get("v", 0)))
			_:
				var a := _articulo(c)
				if not a.is_empty():
					arts.append(a)
	if not cofres.is_empty():
		# UN COFRE: ¿abrirlo ya?
		Audio.ui("objetivo_tomado", -6.0)
		_ofrecer_cofre(int(cofres[0]))
		return
	if arts.is_empty():
		_premio_suelto(oro, diamantes, cubos)
		return
	# lo grande (habilidad, personaje, pintura, mazo) con la pantalla de recompensa del lobby; el oro, al cerrarla
	var r = RecompensaScript.mostrar(lobby if is_instance_valid(lobby) else self, arts)
	if oro > 0 or diamantes > 0 or cubos > 0:
		r.terminado.connect(_premio_suelto.bind(oro, diamantes, cubos))


## Lo que se enseña en la pantalla de recompensa (recompensa.gd) de cada cosa del pase
func _articulo(c: Dictionary) -> Dictionary:
	var v := str(c.get("v", ""))
	match String(c.get("t", "")):
		"habilidad":
			var d: Dictionary = HabilidadScript.datos(v)
			return {"nombre": String(d.get("nombre", v)), "rareza": "NUEVA HABILIDAD", "color": (d.get("color", Color.WHITE) as Color).darkened(0.35),
				"tipo": "HABILIDAD", "icono_tipo": "habilidades", "icono": String(d.get("icono", "habilidades")), "giro": 0.0,
				"descripcion": String(d.get("texto", "")), "datos": []}
		"modelo":
			if is_instance_valid(lobby) and lobby.has_method("_articulo_de"):
				return lobby._articulo_de("modelo:" + v)
		"mazo":
			if is_instance_valid(lobby) and lobby.has_method("_articulo_de"):
				return lobby._articulo_de(v)
		"pintura":
			if is_instance_valid(lobby) and lobby.has_method("_articulo_de"):
				var a: Dictionary = lobby._articulo_de(v)
				if not a.is_empty():
					# sobre la misma arma que en la carta (la pintura vale para todas)
					a["escena"] = lobby._escena_arma(String(ARMA_DE_PINTURA.get(v, "carabina_556")), "", v)
					var datos: Array = []
					for x in a.get("datos", []):
						if String(x[0]) != "ARMA":
							datos.append(x)
					datos.push_front(["VALE PARA", "TODAS LAS ARMAS"])
					a["datos"] = datos
				return a
	return {}


## El oro, los diamantes y los cubos de fuerza: salen volando del centro, sin pantalla aparte
func _premio_suelto(oro: int, diamantes: int, cubos: int = 0) -> void:
	if not is_inside_tree():
		return
	var lista: Array = []
	if oro > 0:
		lista.append(["moneda", Color(1.0, 0.78, 0.05), "+%s ORO" % _con_puntos(oro)])
	if diamantes > 0:
		lista.append(["credito", Color(0.45, 0.9, 0.5), "+%s DIAMANTES" % _con_puntos(diamantes)])
	if cubos > 0:
		lista.append(["cubo_fuerza", Color.WHITE, "+%s CUBOS" % _con_puntos(cubos)])
	for i in lista.size():
		var x: Array = lista[i]
		var caja := Control.new()
		caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caja.size = Vector2(520, 120)
		caja.position = Vector2(PANEL_X_ARRIBA + (_w - PANEL_X_ARRIBA) * 0.5 - 260.0, 330.0 + i * 120.0)
		caja.pivot_offset = caja.size * 0.5
		_raiz.add_child(caja)
		_dibujo(Vector2.ZERO, caja.size, func(ci: Control):
			ci.draw_colored_polygon(_para(ci.size, 22.0), Color(0.1, 0.05, 0.3, 0.86))
			var b := _para(ci.size, 22.0)
			b.append(b[0])
			ci.draw_polyline(b, x[1], 3.0, true), caja)
		var ic := IconoLobby.new()
		ic.icono = x[0]
		ic.color = x[1]
		ic.position = Vector2(44, 22)
		ic.size = Vector2(76, 76)
		caja.add_child(ic)
		var l := _texto(x[2], 50, Color.WHITE, _f, 8, Color(0.1, 0.05, 0.3))
		l.position = Vector2(136, 0)
		l.size = Vector2(370, 120)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		caja.add_child(l)
		caja.scale = Vector2(0.4, 0.4)
		caja.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(0.12 * i)
		tw.tween_property(caja, "scale", Vector2(1.08, 1.08), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(caja, "modulate:a", 1.0, 0.12)
		tw.tween_property(caja, "scale", Vector2.ONE, 0.1)
		tw.tween_interval(1.1)
		tw.tween_property(caja, "position:y", caja.position.y - 60.0, 0.4)
		tw.parallel().tween_property(caja, "modulate:a", 0.0, 0.4)
		tw.tween_callback(caja.queue_free)
	Audio.ui("objetivo_tomado", -6.0)


## ACABAS DE RECLAMAR UN COFRE: un cartel en medio con el cofre de su rareza, ABRIR AHORA (la pantalla de los cofres,
## encima del pase) y LUEGO (se queda en el boton COFRES del lobby). Tocar fuera es LUEGO.
var _oferta: Control = null

func _ofrecer_cofre(r: int) -> void:
	_quitar_oferta()
	var capa := Control.new()
	capa.mouse_filter = Control.MOUSE_FILTER_STOP
	capa.size = Vector2(_w, ALTO)
	_raiz.add_child(capa)
	_oferta = capa
	capa.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and (e as InputEventMouseButton).pressed) or (e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed):
			_quitar_oferta())
	_dibujo(Vector2.ZERO, capa.size, func(ci: Control): ci.draw_rect(Rect2(Vector2.ZERO, ci.size), Color(0.05, 0.02, 0.14, 0.6)), capa)
	var col: Color = Cofres.rareza(r)["color"]
	var tam := Vector2(640, 520)
	var caja := Control.new()
	caja.mouse_filter = Control.MOUSE_FILTER_STOP
	caja.size = tam
	caja.position = Vector2((PANEL_X_ARRIBA + _w) * 0.5 - tam.x * 0.5, 190)
	caja.pivot_offset = tam * 0.5
	capa.add_child(caja)
	_dibujo(Vector2.ZERO, tam, func(ci: Control):
		ci.draw_colored_polygon(_para(ci.size, 30.0, -4.0), Color(1, 1, 1, 0.85))
		ci.draw_polygon(_para(ci.size, 30.0), PackedColorArray([Color8(120, 70, 230), Color8(120, 70, 230), Color8(60, 36, 150), Color8(60, 36, 150)]))
		# el resplandor de la rareza detras del cofre
		for i in 8:
			ci.draw_circle(Vector2(ci.size.x * 0.5, 210), 190.0 * (1.0 - i / 8.0), Color(col, 0.05 + i * 0.012))
		ci.draw_colored_polygon(_franja(ci.size, 30.0, 0.0, 70.0, 74.0), Color(1, 1, 1, 0.12)), caja)
	var t := _texto("¡" + CofreScript.nombre_cofre(r) + "!", 42, ORO_TEXTO, _f, 9, Color8(120, 50, 10))
	t.size = Vector2(tam.x, 70)
	t.position = Vector2(0, 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caja.add_child(t)
	var img := _imagen({"t": "cofre", "v": r}, Vector2(330, 250), true)
	img.position = Vector2(tam.x * 0.5 - 165, 84)
	img.size = Vector2(330, 250)
	caja.add_child(img)
	var sub := _texto("Tócalo y a ver si sube de rareza", 25, Color.WHITE, _fb, 0, Color.BLACK, Color(0.1, 0.04, 0.3, 0.6))
	sub.size = Vector2(tam.x, 40)
	sub.position = Vector2(0, 336)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caja.add_child(sub)
	var abrir := _boton(Rect2(40, 396, 330, 92), func(ci: Control):
		ci.draw_colored_polygon(_para(ci.size, 16.0, -3.0), Color(0.05, 0.04, 0.16, 0.5))
		ci.draw_colored_polygon(_para(ci.size, 16.0), AMARILLO_BOTON)
		ci.draw_colored_polygon(_franja(ci.size, 16.0, 0.0, ci.size.y - 6.0, ci.size.y), AMARILLO_BOTON.darkened(0.28)), func():
			Audio.ui("aceptar", -4.0)
			_quitar_oferta()
			if is_instance_valid(lobby) and lobby.has_method("_abrir_cofres"):
				lobby._abrir_cofres(), caja)
	var ta := _texto("ABRIR AHORA", 34, TINTA, _f)
	ta.size = abrir.size
	ta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	abrir.add_child(ta)
	var luego := _boton(Rect2(392, 396, 210, 92), func(ci: Control):
		ci.draw_colored_polygon(_para(ci.size, 16.0), MORADO_BOTON.darkened(0.2))
		var b := _para(ci.size, 16.0)
		b.append(b[0])
		ci.draw_polyline(b, Color(1, 1, 1, 0.35), 2.0, true), func():
			Audio.ui("atras", -8.0)
			_quitar_oferta(), caja)
	var tl := _texto("LUEGO", 32, Color.WHITE, _f)
	tl.size = luego.size
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	luego.add_child(tl)
	# entra de golpe, como las recompensas
	caja.scale = Vector2(0.6, 0.6)
	caja.modulate.a = 0.0
	var tw := caja.create_tween().set_parallel(true)
	tw.tween_property(caja, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(caja, "modulate:a", 1.0, 0.14)


func _quitar_oferta() -> void:
	if _oferta != null and is_instance_valid(_oferta):
		_oferta.queue_free()
	_oferta = null


## Lo que es una carta cerrada (o ya tuya), en un globo encima de ella
func _burbuja(e: Dictionary, titulo: String, estado: String) -> void:
	_quitar_burbuja()
	var r: Rect2 = e["rect"]
	var ancho := 330.0
	var b := Control.new()
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.size = Vector2(ancho, 96)
	var cx := r.position.x - _scroll + r.size.x * 0.5
	b.position = Vector2(clampf(cx - ancho * 0.5, PANEL_X_ARRIBA - 20.0, _w - ancho - 10.0),
		r.position.y + (70.0 if String(e["fila"]) == "p" else 30.0))
	_raiz.add_child(b)
	_dibujo(Vector2.ZERO, b.size, func(ci: Control):
		ci.draw_colored_polygon(_para(ci.size, 12.0, -3.0), Color(1, 1, 1, 0.85))
		ci.draw_colored_polygon(_para(ci.size, 12.0), Color(0.09, 0.06, 0.26, 0.96)), b)
	var t := _texto(titulo, 26 if titulo.length() <= 20 else 20, Color.WHITE, _f)
	t.position = Vector2(14, 8)
	t.size = Vector2(ancho - 28, 44)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_child(t)
	var s := _texto(estado, 18, ORO_TEXTO, _f)
	s.position = Vector2(14, 50)
	s.size = Vector2(ancho - 28, 34)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(s)
	b.modulate.a = 0.0
	var tw := b.create_tween()
	tw.tween_property(b, "modulate:a", 1.0, 0.12)
	tw.tween_interval(2.2)
	tw.tween_property(b, "modulate:a", 0.0, 0.25)
	tw.tween_callback(b.queue_free)
	_burbuja_nodo = b


func _quitar_burbuja() -> void:
	if _burbuja_nodo != null and is_instance_valid(_burbuja_nodo):
		_burbuja_nodo.queue_free()
	_burbuja_nodo = null


func _al_cambiar_cuenta() -> void:
	if _cerrando:
		return
	if _en_vuelo.size() == 2:
		var n := int(_en_vuelo[0])
		var fila := String(_en_vuelo[1])
		if PaseBatalla.reclamado(n, fila):
			_en_vuelo = []
			_al_reclamar(n, fila)
			return
	if _comprando and PaseBatalla.premium():
		_comprando = false
		Audio.ui("activar", -4.0)
		_avisar("¡PASE PRÉMIUM ACTIVADO!")
	_refrescar()


func _al_error_cuenta(msg: String) -> void:
	if _cerrando or (_en_vuelo.is_empty() and not _comprando):
		return
	var que := "comprar" if _comprando else "reclamar"
	_en_vuelo = []
	_comprando = false
	Audio.ui("atras", -8.0)
	_avisar("No se pudo %s: %s" % [que, msg])
	_refrescar()


# ================================================================== los botones
## DESBLOQUEAR: con diamantes y solo con cuenta. Pide confirmar (el segundo toque en 3 s compra).
func _pulsar_premium() -> void:
	if PaseBatalla.premium() or _comprando:
		return
	if not Cuenta.conectado():
		Audio.ui("atras", -8.0)
		_avisar("El pase prémium va con tu cuenta: inicia sesión")
		return
	var precio := PaseBatalla.precio_premium()
	if _confirmar_t <= 0.0:
		if Cuenta.creditos() < precio:
			Audio.ui("atras", -8.0)
			_avisar("Te faltan %s diamantes" % _con_puntos(precio - Cuenta.creditos()))
			return
		Audio.ui("aceptar", -6.0)
		_confirmar_t = 3.0
		_refrescar_premium()
		return
	_confirmar_t = 0.0
	match PaseBatalla.comprar_premium():
		"hecho":
			Audio.ui("activar", -4.0)
			_avisar("¡PASE PRÉMIUM ACTIVADO!")
		"enviado":
			_comprando = true
		"sin_dinero":
			_avisar("Te faltan %s diamantes" % _con_puntos(precio - Cuenta.creditos()))
		"sin_cuenta":
			_avisar("El pase prémium va con tu cuenta: inicia sesión")
		_:
			_avisar("No se pudo comprar: sin conexión con la cuenta")
	_refrescar()


func _ir_tareas() -> void:
	Audio.ui("aceptar", -6.0)
	var l = lobby
	_cerrar_habilidades()
	_cerrar()
	if is_instance_valid(l) and l.has_method("_show_tab"):
		l._abrir_tareas(true)        # las TAREAS DEL PASE (tareas_pantalla.gd); al cerrarlas se vuelve aqui


func _ir_a_batalla() -> void:
	Audio.ui("aceptar", -4.0)
	var l = lobby
	_cerrar_habilidades()
	_cerrar()
	if is_instance_valid(l) and l.has_method("_abrir_centro"):
		l._abrir_centro()


## Si el pase se abrio desde HABILIDADES, al irse a otro sitio se cierra tambien (si no, se quedaba tapando)
func _cerrar_habilidades() -> void:
	if not is_instance_valid(lobby):
		return
	for c in lobby.get_children():
		if c != self and c is CanvasLayer and c.get_script() != null \
				and String((c.get_script() as Script).resource_path).ends_with("habilidades.gd"):
			c.queue_free()


# ================================================================== el lienzo de todo
## Un Control que se pinta con una funcion (`pintar(self)`); `animado` lo repinta cada fotograma; `forma`, si la hay,
## es por donde se le puede tocar (un panel inclinado no se queda con los toques de fuera de su borde)
class _Dibujo extends Control:
	var pintar: Callable
	var animado := false
	var forma := PackedVector2Array()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_dt: float) -> void:
		if animado:
			queue_redraw()

	func _draw() -> void:
		if pintar.is_valid():
			pintar.call(self)

	func _has_point(p: Vector2) -> bool:
		if forma.is_empty():
			return Rect2(Vector2.ZERO, size).has_point(p)
		return Geometry2D.is_point_in_polygon(p, forma)
