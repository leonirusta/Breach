extends CanvasLayer
## LAS CARTAS, LA PANTALLA (2026-09-29, pedido con dos capturas del juego de referencia -la de "DESTREZAS ACTIVAS / SET DE
## DESTREZAS" y la misma con la ficha de una carta tocada-: "que se vea como la foto"; aqui se llaman CARTAS). Las reglas
## son de cartas.gd (Cartas): aqui solo se enseñan, se equipan y se mejoran.
##
##   izquierda  CARTAS ACTIVAS: las RANURAS (8), dos filas de cuatro sobre un panel mas claro. Debajo, "GANA MAS CARTAS..."
##              con IR A BATALLA (lo mismo que JUGAR: CENTRO: BATALLA, como en las tareas).
##   derecha    SET DE CARTAS y DISPONIBLE: n/total. La rejilla de tres columnas, que se desliza, con TODAS las de la
##              categoria: las tuyas sin equipar (con la cinta roja de NUEVO si no la has mirado), las equipadas (con la
##              marca verde) y las que te faltan (en gris, con candado y "0/1"); se rellena con huecos lavanda, como en la
##              foto. A la derecha del todo, la columna blanca de CATEGORIAS con el globo rojo de lo que hay por mirar o
##              mejorar (Cartas.avisos); tocar una filtra la rejilla.
##   la X       arriba a la derecha, la pestaña magenta.
##   la ficha   al tocar cualquier carta, a su lado: el hexagono, la rareza en su color, la categoria, lo que hace, el valor
##              de ahora y en verde el del nivel siguiente, la barra de copias, EQUIPAR (QUITAR si ya lo esta) y MEJORA con
##              su oro. Con las 8 ranuras llenas, EQUIPAR pasa al MODO CAMBIO: las activas se encienden y se menean, y la que
##              toques se cambia por la nueva (Cartas.cambiar). Abrirla la da por vista (se va el NUEVO) y arriba sale lo que
##              tienes (oro, cubos de fuerza y diamantes), como en la foto. Tocar fuera la cierra.
##   subir      la barra se llena, la carta y el hexagono saltan y se hinchan, fogonazo, chispas, el numero sube, "¡NIVEL N!"
##              y la barra baja a lo que queda. Con cuenta lo cobra el servidor: se anima cuando llega (Cuenta.sesion_cambiada).
## Se dibuja en un lienzo de 904 de alto -el de la foto: las medidas salen de ella- y se escala a la pantalla; si no cabe,
## lo de la izquierda se encoge. LA CARTA (`Carta`, al final) es publica: el premio del cofre (cofre_pantalla.gd) la pinta
## igual con `nueva_carta`. Los dibujos de cada carta son de icono_lobby.gd ("carta_*" y "glifo_*").
## La abre el lobby (`_abrir_cartas`), que le pasa `lobby`. Fotos con cartas de prueba en memoria: --cartasfoto=<carpeta>.

signal cerrado

const IconoLobby := preload("res://scripts/icono_lobby.gd")

const ALTO := 904.0
## LAS MEDIDAS, sacadas de la foto (2316x904)
const CARTA_TAM := Vector2(172, 236)
const IZQ_ANCHO := 756.0         ## el panel de las activas (y todo lo de ese lado)
const PANEL_Y := 148.0
const PANEL_ALTO := 512.0
const RANURA_X := 13.0
const RANURA_Y := 15.0
const RANURA_PASO := Vector2(186, 250)
const BARRA_Y := 750.0
const BARRA_ALTO := 127.0
const DER_ANCHO := 759.0         ## el panel del set, pegado a la derecha
const DER_Y := 25.0
const REJILLA_X := 12.0          ## (con 7 de margen dentro: lo que asoma el marco amarillo y la cinta de NUEVO)
const REJILLA_Y := 133.0
const REJILLA_PASO := Vector2(185, 250)
const COLUMNA_X := 584.0
const COLUMNA_Y := 139.0
const COLUMNA_ANCHO := 132.0
const CAT_PASO := 118.0
const FICHA := Vector2(452, 637)

## LOS COLORES, medidos en la foto
const FONDO_ARRIBA := Color8(121, 114, 209)
const FONDO_ABAJO := Color8(110, 115, 204)
const PANEL := Color8(159, 155, 238)
const PANEL_BORDE := Color8(178, 174, 247)
const BARRA := Color8(103, 112, 191)
const SUBTITULO := Color8(208, 205, 250)
const SET := Color8(227, 227, 253)
const SET_TITULO := Color8(35, 46, 66)
const SET_SUB := Color8(106, 104, 150)
const NAVY := Color8(64, 76, 140)
const CEREZA := Color8(214, 32, 74)
const X_ROSA := Color8(140, 55, 122)
const AMARILLO := Color8(240, 200, 78)
const TINTA := Color8(28, 38, 58)
const PASTILLA := Color8(52, 47, 103)
const ORO_TEXTO := Color8(255, 208, 64)
const FICHA_CANTO := Color8(204, 202, 224)
const FICHA_CARA := Color8(238, 237, 251)
const FICHA_PIE := Color8(222, 220, 241)
const FICHA_TEXTO := Color8(92, 92, 112)
const FICHA_TINTA := Color8(43, 48, 64)
const VERDE := Color8(64, 176, 24)
const MORADO := Color8(116, 89, 196)

## LOS HEXAGONOS TENUES DEL FONDO (en la foto, cada uno como un cubo en isometrica: la cara de arriba algo mas clara y la de
## la derecha algo mas oscura). Va en las coordenadas del lienzo (VERTEX), asi se mueve con lo que lo lleva, y aclara u
## oscurece el color con que se pinta: vale para el fondo, el panel del set y la ficha.
const SOMBREADO_HEX := """shader_type canvas_item;
uniform float radio = 100.0;
uniform float fuerza = 0.035;
varying vec2 lugar;
float azar(vec2 c) { return fract(sin(dot(c, vec2(12.9898, 78.233))) * 43758.5453); }
void vertex() { lugar = VERTEX; }
void fragment() {
	vec2 h = vec2(1.7320508, 3.0) * radio;
	vec2 a = h * (floor(lugar / h) + 0.5);
	vec2 b = h * (floor(lugar / h - 0.5) + 1.0);
	vec2 c = (length(lugar - a) < length(lugar - b)) ? a : b;
	vec2 d = lugar - c;
	float ang = atan(d.y, d.x);
	float cara = 0.0;
	if (ang > -2.618 && ang < -0.5236) { cara = 1.0; }
	else if (ang >= -0.5236 && ang < 1.5708) { cara = -1.0; }
	float n = azar(floor(c / radio + 0.5));
	float k = fuerza * (0.35 + 0.9 * n);
	COLOR.rgb *= 1.0 + cara * k + (n - 0.5) * fuerza * 0.5;
}
"""

## el lobby que la abre (sin tipo: se le llaman sus funciones, que Node no tiene)
var lobby = null

var _raiz: Control
var _w := 2009.0
var _k := 1.0
const EscalaPantalla := preload("res://scripts/escala_pantalla.gd")   ## plegable abierto: no se estrecha (ver alli)
var _franjas: Array = []
var _x0 := 0.0                   ## donde empieza el panel del set
var _f: SystemFont               ## negrita gruesa y cursiva: la de los titulos de la foto
var _fb: SystemFont              ## negrita gruesa recta (subtitulos, categorias)
var _fn: SystemFont              ## negrita (la ficha)
var _fr: SystemFont              ## la de leer (lo que hace la carta)
var _t := 0.0
var _cerrando := false
# la izquierda
var _izq: Control
var _panel_izq: Control
var _ranuras: Array = []         ## las RANURAS (Carta): siempre las mismas 8, cambia lo que enseñan
var _barra_txt: Label
var _boton_batalla: Button
var _boton_batalla_txt: Label
var _izq_pulsado := -1
var _izq_p0 := Vector2.ZERO
# la derecha
var _disp_txt: Label
var _rejilla: Control
var _cont: Control
var _cartas_set: Array = []      ## {id, carta, rect (en el contenido)}
var _cat := "todo"
var _columna: Control
var _cat_items: Array = []       ## {id, icono, texto, globo, globo_txt}
var _cat_sel_y := 8.0            ## donde esta el recuadro oscuro de la elegida (se desliza al cambiar)
var _pastilla: Control
var _pastilla_txt: Array = []
var _pastilla_ver := false
# el arrastre de la rejilla
var _scroll := 0.0
var _vel := 0.0
var _obj := -1.0
var _pulsado := false
var _toque := -1
var _p0 := Vector2.ZERO
var _p_ult := Vector2.ZERO
var _t_ult := 0
var _movido := 0.0
var _apretada: Control = null
# la ficha
var _capa_ficha: Control
var _ficha: Control = null
var _ficha_id := ""
var _ficha_desde: Control = null
var _ficha_hex: Control = null
var _ficha_barra: Control = null
var _ficha_valores: Control = null
var _ficha_fogonazo: Control = null
var _ficha_caja_y := 355.0       ## donde empieza la caja naranja (la ficha crece con lo que hace la carta)
var _ficha_pie_y := 505.0        ## donde empieza el pie de los botones
# la subida de nivel (lo que enseña la barra de la ficha mientras se anima)
var _subiendo := false
var _fb_nivel := 0
var _fb_frac := 0.0
var _fb_texto := ""
var _fb_brillo := 0.0
var _tw_subida: Tween = null     ## la barra bajando (se para si se cierra la ficha a mitad)
var _mejorando := ""             ## la que se esta mejorando en el servidor
var _mejora_antes: Dictionary = {}
var _mejora_t := 0.0
# el modo cambio
var _cambio := ""
# lo de encima de todo
var _fx: _Chispas
var _aviso: Control
var _aviso_txt: Label
var _aviso_t := 0.0


func _ready() -> void:
	layer = 63
	_f = _fuente(900, true)
	_fb = _fuente(800, false)
	_fn = _fuente(700, false)
	_fr = _fuente(500, false)
	Cartas.refrescar()
	_montar()
	_raiz.modulate.a = 0.0
	create_tween().tween_property(_raiz, "modulate:a", 1.0, 0.18)
	_entrada()
	Audio.ui("submenu_abre", -8.0)
	Cuenta.sesion_cambiada.connect(_al_cambiar_cuenta)
	Cuenta.error_cuenta.connect(_al_error_cuenta)
	get_viewport().size_changed.connect(_al_redimensionar)
	# lo del lobby se aparta mientras tanto (debajo no se ve, y se quedaba con los toques de encima)
	if is_instance_valid(lobby) and lobby.has_method("set_chrome_visible"):
		lobby.set_chrome_visible(false)


static func _fuente(peso: int, cursiva: bool) -> SystemFont:
	return preload("res://scripts/fuentes.gd").de(peso, cursiva)      # compartida: ver fuentes.gd


## Una carta suelta, dibujada como las de esta pantalla (el premio del cofre, la armeria...). `tam`: lo que mide (todo va a
## escala: a 344x472 sale nitida al doble); `modo`: "carta" o "reverso" (el dorso: morado con el hexagono de las cartas)
static func nueva_carta(id: String, tam := Vector2(172, 236), modo := "carta") -> Control:
	var c := Carta.new()
	c.id = id
	c.modo = modo
	c.size = tam
	return c


func _montar() -> void:
	var tam: Vector2 = get_viewport().get_visible_rect().size
	var m := EscalaPantalla.medir(tam, ALTO)
	_k = m["k"]
	_w = m["w"]
	_x0 = _w - DER_ANCHO
	EscalaPantalla.quitar(_franjas)
	_franjas = EscalaPantalla.franjas(self, tam, m["y0"], FONDO_ARRIBA, FONDO_ABAJO)
	_raiz = Control.new()
	_raiz.mouse_filter = Control.MOUSE_FILTER_STOP
	_raiz.scale = Vector2(_k, _k)
	_raiz.position.y = m["y0"]
	_raiz.size = Vector2(_w, ALTO)
	add_child(_raiz)
	var fondo := _dibujo(Vector2.ZERO, _raiz.size, _pintar_fondo, _raiz)
	fondo.material = _material_hex(0.034, 100.0)
	_montar_izquierda()
	_montar_derecha()
	_montar_x()
	_montar_pastilla()
	_capa_ficha = Control.new()
	_capa_ficha.mouse_filter = Control.MOUSE_FILTER_STOP
	_capa_ficha.size = _raiz.size
	_capa_ficha.visible = false
	_capa_ficha.gui_input.connect(_entrada_capa_ficha)
	_raiz.add_child(_capa_ficha)
	_fx = _Chispas.new()
	_fx.size = _raiz.size
	_raiz.add_child(_fx)
	_aviso = _dibujo(Vector2.ZERO, Vector2(600, 58), func(ci: Control):
		var s := ci.size
		ci.draw_colored_polygon(_forma_boton(s + Vector2(0, 4), 10.0, 10.0), Color(0.05, 0.02, 0.15, 0.3))
		ci.draw_colored_polygon(_forma_boton(s, 10.0, 10.0), PASTILLA)
		ci.draw_polyline(_cerrado(_forma_boton(s, 10.0, 10.0)), Color(1, 1, 1, 0.85), 2.5, true), _raiz)
	_aviso_txt = _texto("", 24, Color.WHITE, _fb)
	_aviso_txt.size = _aviso.size
	_aviso_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aviso_txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_aviso.add_child(_aviso_txt)
	_aviso.modulate.a = 0.0
	_refrescar()


func _al_redimensionar() -> void:
	if _cerrando or not is_inside_tree():
		return
	var s := _scroll
	var abierta := _ficha_id
	_raiz.queue_free()
	_ranuras.clear()
	_cartas_set.clear()
	_cat_items.clear()
	_ficha = null
	_ficha_id = ""
	_apretada = null
	_pastilla_ver = false
	_subiendo = false
	_montar()
	_scroll = clampf(s, 0.0, _scroll_max())
	_aplicar_scroll()
	if abierta != "":
		var desde := _carta_de(abierta)
		if desde != null:
			_abrir_ficha(abierta, desde, false)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _ficha_id != "":
			_cerrar_ficha()
		elif _cambio != "":
			_salir_cambio()
		else:
			_cerrar()


func _cerrar() -> void:
	if _cerrando:
		return
	_cerrando = true
	Audio.ui("submenu_cierra", -8.0)
	var l = lobby
	if is_instance_valid(l):
		var cajon = l.get("drawer")
		if l.has_method("set_chrome_visible") and not (cajon is Control and (cajon as Control).visible):
			l.set_chrome_visible(true)
		if l.has_method("_refrescar_cuenta"):
			l._refrescar_cuenta()        # el oro de arriba, con lo que se gasto mejorando
	cerrado.emit()
	var tw := create_tween()
	tw.tween_property(_raiz, "modulate:a", 0.0, 0.15)
	tw.tween_callback(queue_free)


## Al abrir: las cartas salen de una en una, con un saltito
func _entrada() -> void:
	var i := 0
	for r in _ranuras:
		_aparecer(r, 0.04 + 0.035 * i)
		i += 1
	var j := 0
	for e in _cartas_set:
		_aparecer(e["carta"], 0.1 + 0.03 * j)
		j += 1


func _aparecer(c: Control, espera: float) -> void:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(0.86, 0.86)
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, 0.16).set_delay(espera)
	tw.tween_property(c, "scale", Vector2.ONE, 0.3).set_delay(espera).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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


## El tamaño de letra mas grande (de `tam` para abajo) con el que `t` cabe en `ancho`
static func _cabe(f: Font, t: String, tam: int, ancho: float, minimo := 12) -> int:
	var s := tam
	while s > minimo and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > ancho:
		s -= 1
	return s


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
	var d := _dibujo(Vector2.ZERO, r.size, pintar, b)
	d.name = "Dibujo"
	b.button_down.connect(func(): b.scale = Vector2(0.95, 0.95))
	b.button_up.connect(func(): b.scale = Vector2.ONE)
	b.pressed.connect(al_pulsar)
	return b


func _material_hex(fuerza: float, radio: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://scripts/sombreados.gd").de(SOMBREADO_HEX)      # compartido: ver sombreados.gd
	m.set_shader_parameter("fuerza", fuerza)
	m.set_shader_parameter("radio", radio)
	return m


## Paralelogramo de `tam` inclinado `s` (arriba corrido a la derecha): los botones de la foto
static func _para(tam: Vector2, s: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(s, 0), Vector2(tam.x, 0), Vector2(tam.x - s, tam.y), Vector2(0, tam.y)])


## Trozo horizontal del paralelogramo (de y0 a y1)
static func _franja(tam: Vector2, s: float, y0: float, y1: float) -> PackedVector2Array:
	var h := tam.y
	return PackedVector2Array([Vector2(s * (1.0 - y0 / h), y0), Vector2(tam.x - s * y0 / h, y0),
		Vector2(tam.x - s * y1 / h, y1), Vector2(s * (1.0 - y1 / h), y1)])


## Un rectangulo con la esquina de arriba a la izquierda y la de abajo a la derecha cortadas (la pastilla, el recuadro de la
## categoria elegida)
static func _forma_boton(tam: Vector2, a: float = 10.0, b: float = 12.0) -> PackedVector2Array:
	return PackedVector2Array([Vector2(a, 0), Vector2(tam.x, 0), Vector2(tam.x, tam.y - b), Vector2(tam.x - b, tam.y),
		Vector2(0, tam.y), Vector2(0, a)])


static func _cerrado(p: PackedVector2Array) -> PackedVector2Array:
	var b := p.duplicate()
	b.append(p[0])
	return b


static func _con_puntos(v: int) -> String:
	var t := str(absi(v))
	var out := ""
	while t.length() > 3:
		out = "." + t.substr(t.length() - 3) + out
		t = t.substr(0, t.length() - 3)
	return ("-" if v < 0 else "") + t + out


## Lo que ocupa un control en el lienzo (el de _raiz)
func _rect_en_raiz(c: Control) -> Rect2:
	var t := _raiz.get_global_transform().affine_inverse() * c.get_global_transform()
	return Rect2(t.origin, c.size * t.get_scale())


## EL BOTON AMARILLO (IR A BATALLA, EQUIPAR) y el MORADO (MEJORA, CANCELAR): paralelogramos con el canto de arriba claro,
## el de abajo oscuro y un destello en diagonal. `brillo`: por donde va el destello que cruza (0..1; <0 sin el)
func _pintar_boton(ci: Control, color: Color, brillo := -1.0) -> void:
	var tam := ci.size
	var s := 16.0
	var forma := _para(tam, s)
	var sombra := PackedVector2Array()
	for p in forma:
		sombra.append(p + Vector2(3, 5))
	ci.draw_colored_polygon(sombra, Color(0.08, 0.04, 0.28, 0.28))
	ci.draw_colored_polygon(forma, color)
	ci.draw_colored_polygon(_franja(tam, s, 0.0, 6.0), color.lightened(0.3))
	ci.draw_colored_polygon(_franja(tam, s, tam.y - 7.0, tam.y), color.darkened(0.2))
	var diag := PackedVector2Array([Vector2(tam.x * 0.14, 0), Vector2(tam.x * 0.3, 0), Vector2(tam.x * 0.3 - 42.0, tam.y),
		Vector2(tam.x * 0.14 - 42.0, tam.y)])
	for p in Geometry2D.intersect_polygons(diag, forma):
		ci.draw_colored_polygon(p, Color(1, 1, 1, 0.14))
	if brillo >= 0.0:
		var x := lerpf(-120.0, tam.x + 120.0, brillo)
		var raya := PackedVector2Array([Vector2(x, 0), Vector2(x + 38.0, 0), Vector2(x + 8.0, tam.y), Vector2(x - 30.0, tam.y)])
		for p in Geometry2D.intersect_polygons(raya, forma):
			ci.draw_colored_polygon(p, Color(1, 1, 1, 0.3))


# ================================================================== el fondo
func _pintar_fondo(ci: Control) -> void:
	var s := ci.size
	ci.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]),
		PackedColorArray([FONDO_ARRIBA, FONDO_ARRIBA.lerp(FONDO_ABAJO, 0.3), FONDO_ABAJO, FONDO_ABAJO]))


# ================================================================== la izquierda: CARTAS ACTIVAS
func _montar_izquierda() -> void:
	# centrado en lo que deja el set (como en la foto); si no cabe, se encoge
	var hueco := _x0
	var s := clampf((hueco - 60.0) / IZQ_ANCHO, 0.45, 1.0)
	_izq = Control.new()
	_izq.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_izq.scale = Vector2(s, s)
	_izq.size = Vector2(IZQ_ANCHO, ALTO)
	_izq.position = Vector2(maxf(20.0, (hueco - IZQ_ANCHO * s) * 0.5), (1.0 - s) * 120.0)
	_raiz.add_child(_izq)
	var t := _texto("CARTAS ACTIVAS", 42, Color.WHITE, _f, 0, Color.BLACK, Color(0.2, 0.14, 0.5, 0.35))
	t.position = Vector2(0, 30)
	t.size = Vector2(IZQ_ANCHO, 56)
	_izq.add_child(t)
	var st := _texto("CARTAS DENTRO DEL JUEGO", 26, SUBTITULO, _fb)
	st.position = Vector2(2, 84)
	st.size = Vector2(IZQ_ANCHO, 36)
	_izq.add_child(st)
	# EL PANEL con las ranuras
	_panel_izq = _dibujo(Vector2(0, PANEL_Y), Vector2(IZQ_ANCHO, PANEL_ALTO), func(ci: Control):
		var r := Rect2(Vector2.ZERO, ci.size)
		ci.draw_colored_polygon(Carta.forma(r.grow(3.0), 13.0), Color(0.3, 0.24, 0.66, 0.25))
		ci.draw_colored_polygon(Carta.forma(r, 11.0), PANEL_BORDE)
		ci.draw_colored_polygon(Carta.forma(r.grow(-2.5), 9.0), PANEL)
		ci.draw_rect(Rect2(10, 2.5, ci.size.x - 20, 2), Color(1, 1, 1, 0.18)), _izq)
	_panel_izq.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_izq.gui_input.connect(_entrada_izq)
	for i in Cartas.RANURAS:
		var c := Carta.new()
		c.position = Vector2(RANURA_X + (i % 4) * RANURA_PASO.x, RANURA_Y + (i / 4) * RANURA_PASO.y)
		c.size = CARTA_TAM
		c.pivot_offset = CARTA_TAM * 0.5
		_panel_izq.add_child(c)
		_ranuras.append(c)
	# LA BARRA DE ABAJO: "GANA MAS CARTAS..." e IR A BATALLA (en el modo cambio: lo que hay que hacer y CANCELAR)
	var barra := _dibujo(Vector2(0, BARRA_Y), Vector2(IZQ_ANCHO, BARRA_ALTO), _pintar_barra_izq, _izq)
	barra.animado = true
	_barra_txt = _texto("", 25, Color.WHITE, _fb)
	_barra_txt.position = Vector2(22, BARRA_Y)
	_barra_txt.size = Vector2(430, BARRA_ALTO)
	_barra_txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_barra_txt.add_theme_constant_override("line_spacing", -3)
	_izq.add_child(_barra_txt)
	var br := Rect2(457, BARRA_Y + 21.0, 276, 82)
	_boton_batalla = _boton(br, _pintar_boton_batalla, _pulsar_batalla, _izq)
	(_boton_batalla.get_node("Dibujo") as _Dibujo).animado = true
	_boton_batalla_txt = _texto("IR A BATALLA", 34, TINTA, _f)
	_boton_batalla_txt.size = br.size - Vector2(8, 4)
	_boton_batalla_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boton_batalla_txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_boton_batalla.add_child(_boton_batalla_txt)
	_poner_barra_izq()


func _pintar_barra_izq(ci: Control) -> void:
	var col := BARRA if _cambio == "" else Color8(88, 84, 184)
	ci.draw_colored_polygon(Carta.forma(Rect2(Vector2.ZERO, ci.size), 8.0), col)
	ci.draw_rect(Rect2(8, 0, ci.size.x - 16, 2), Color(1, 1, 1, 0.1))
	if _cambio != "":
		ci.draw_polyline(_cerrado(Carta.forma(Rect2(Vector2.ZERO, ci.size).grow(-1.5), 7.0)),
			Color(1.0, 0.92, 0.35, 0.55 + 0.35 * sin(_t * 6.5)), 3.0, true)


## IR A BATALLA en amarillo, con un destello que lo cruza cada poco (CANCELAR en el modo cambio, en morado)
func _pintar_boton_batalla(ci: Control) -> void:
	if _cambio != "":
		_pintar_boton(ci, MORADO)
		return
	var q := fmod(_t, 3.2) / 0.9
	_pintar_boton(ci, AMARILLO, q if q <= 1.0 else -1.0)


## Lo que dice la barra de abajo: lo de siempre, o en el modo cambio lo que hay que hacer
func _poner_barra_izq() -> void:
	if _cambio != "":
		var n := String(Cartas.datos(_cambio).get("nombre", ""))
		_barra_txt.text = "TOCA UNA CARTA ACTIVA PARA\nCAMBIARLA POR %s" % n
		_barra_txt.add_theme_color_override("font_color", Color8(255, 236, 140))
		_boton_batalla_txt.text = "CANCELAR"
		_boton_batalla_txt.add_theme_color_override("font_color", Color.WHITE)
		_boton_batalla_txt.add_theme_constant_override("outline_size", 6)
		_boton_batalla_txt.add_theme_color_override("font_outline_color", Color(0.2, 0.1, 0.45, 0.6))
	else:
		_barra_txt.text = "GANA MÁS CARTAS ABRIENDO COFRES\nY PARTICIPANDO EN BATALLAS"
		_barra_txt.add_theme_color_override("font_color", Color.WHITE)
		_boton_batalla_txt.text = "IR A BATALLA"
		_boton_batalla_txt.add_theme_color_override("font_color", TINTA)
		_boton_batalla_txt.add_theme_constant_override("outline_size", 0)
	var mas := 0.0
	for linea in _barra_txt.text.split("\n"):
		mas = maxf(mas, _fb.get_string_size(linea, HORIZONTAL_ALIGNMENT_LEFT, -1, 25).x)
	var tam := 25
	while tam > 15 and mas * tam / 25.0 > 425.0:
		tam -= 1
	_barra_txt.add_theme_font_size_override("font_size", tam)
	if is_instance_valid(_boton_batalla):
		_boton_batalla.get_node("Dibujo").queue_redraw()


func _pulsar_batalla() -> void:
	if _cambio != "":
		Audio.ui("atras", -8.0)
		_salir_cambio()
		return
	_ir_a_batalla()


## IR A BATALLA: lo mismo que JUGAR (CENTRO: BATALLA)
func _ir_a_batalla() -> void:
	Audio.ui("aceptar", -4.0)
	var l = lobby
	_cerrar()
	if is_instance_valid(l) and l.has_method("_abrir_centro"):
		l._abrir_centro()


func _refrescar_ranuras() -> void:
	var eq := Cartas.equipadas()
	for i in _ranuras.size():
		var c: Carta = _ranuras[i]
		var id := String(eq[i]) if i < eq.size() else ""
		c.id = id
		c.modo = "carta" if id != "" else "vacia"
		c.elegida = id != "" and id == _ficha_id
		c.resalte = _cambio != "" and id != ""
		c.refrescar()


# ================================================================== la derecha: SET DE CARTAS
func _montar_derecha() -> void:
	var fondo := _dibujo(Vector2(_x0, DER_Y), Vector2(DER_ANCHO, ALTO - DER_Y), func(ci: Control):
		var w := ci.size.x
		var h := ci.size.y
		ci.draw_colored_polygon(PackedVector2Array([Vector2(22, -4), Vector2(w, -4), Vector2(w, h), Vector2(-4, h),
			Vector2(-4, 22)]), Color(0.25, 0.2, 0.6, 0.25))
		ci.draw_colored_polygon(PackedVector2Array([Vector2(22, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h),
			Vector2(0, 22)]), SET)
		ci.draw_polyline(PackedVector2Array([Vector2(0, h), Vector2(0, 22), Vector2(22, 0), Vector2(w, 0)]),
			Color(1, 1, 1, 0.75), 2.0, true), _raiz)
	fondo.material = _material_hex(0.022, 100.0)
	var t := _texto("SET DE CARTAS", 40, SET_TITULO, _f)
	t.position = Vector2(_x0 + 20.0, 30)
	t.size = Vector2(560, 56)
	_raiz.add_child(t)
	_disp_txt = _texto("", 26, SET_SUB, _fb)
	_disp_txt.position = Vector2(_x0 + 21.0, 84)
	_disp_txt.size = Vector2(560, 36)
	_raiz.add_child(_disp_txt)
	# LA REJILLA, que se desliza
	_rejilla = Control.new()
	_rejilla.position = Vector2(_x0 + REJILLA_X, REJILLA_Y)
	_rejilla.size = Vector2(3.0 * CARTA_TAM.x + 2.0 * (REJILLA_PASO.x - CARTA_TAM.x) + 14.0, ALTO - REJILLA_Y)
	_rejilla.clip_contents = true
	_rejilla.mouse_filter = Control.MOUSE_FILTER_STOP
	_rejilla.gui_input.connect(_entrada_rejilla)
	_raiz.add_child(_rejilla)
	_cont = Control.new()
	_cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cont.size = _rejilla.size
	_rejilla.add_child(_cont)
	_montar_columna()


## Las del set, en este orden: las tuyas sin equipar, las equipadas y las que te faltan (dentro de cada grupo, el del
## catalogo)
func _ids_set() -> Array:
	var libres: Array = []
	var puestas: Array = []
	var faltan: Array = []
	for id in Cartas.de_categoria(_cat):
		if not Cartas.tiene(id):
			faltan.append(id)
		elif Cartas.equipada(id):
			puestas.append(id)
		else:
			libres.append(id)
	return libres + puestas + faltan


## Rehace la rejilla con la categoria elegida (se rellena con huecos hasta completar la fila, y al menos tres filas)
func _rellenar_rejilla(animar := false) -> void:
	if not is_instance_valid(_cont):
		return
	for c in _cont.get_children():
		c.queue_free()
	_cartas_set.clear()
	_apretada = null
	var ids := _ids_set()
	var celdas := maxi(9, int(ceil(ids.size() / 3.0)) * 3)
	for i in celdas:
		var c := Carta.new()
		c.en_set = true
		c.size = CARTA_TAM
		c.position = Vector2(7.0 + (i % 3) * REJILLA_PASO.x, 7.0 + (i / 3) * REJILLA_PASO.y)
		c.pivot_offset = CARTA_TAM * 0.5
		if i < ids.size():
			c.id = String(ids[i])
			c.elegida = c.id == _ficha_id or c.id == _cambio
		else:
			c.modo = "hueco"
		_cont.add_child(c)
		_cartas_set.append({"id": c.id if i < ids.size() else "", "carta": c, "rect": Rect2(c.position, CARTA_TAM)})
		if animar:
			_aparecer(c, 0.025 * i)
	_scroll = clampf(_scroll, 0.0, _scroll_max())
	_aplicar_scroll()


func _alto_contenido() -> float:
	var filas := int(ceil(_cartas_set.size() / 3.0))
	return 14.0 + filas * REJILLA_PASO.y


func _scroll_max() -> float:
	if not is_instance_valid(_rejilla):
		return 0.0
	return maxf(0.0, _alto_contenido() - _rejilla.size.y)


func _aplicar_scroll() -> void:
	if not is_instance_valid(_cont):
		return
	var y := -roundf(_scroll)
	if _cont.position.y != y:
		_cont.position.y = y


# ================================================================== las categorias
func _montar_columna() -> void:
	var n := Cartas.CATEGORIAS.size() + 1
	var alto := 16.0 + n * CAT_PASO - 10.0
	_columna = _dibujo(Vector2(_x0 + COLUMNA_X, COLUMNA_Y), Vector2(COLUMNA_ANCHO, alto), _pintar_columna, _raiz)
	_columna.mouse_filter = Control.MOUSE_FILTER_STOP
	_columna.gui_input.connect(_entrada_columna)
	var lista: Array = [{"id": "todo", "nombre": "TODO", "icono": "carta_todo"}]
	lista.append_array(Cartas.CATEGORIAS)
	for i in lista.size():
		var c: Dictionary = lista[i]
		var y := 8.0 + i * CAT_PASO
		var ic := IconoLobby.new()
		ic.icono = "glifo_" + String(c["icono"]).trim_prefix("carta_")
		ic.position = Vector2(COLUMNA_ANCHO * 0.5 - 25.0, y + 13.0)
		ic.size = Vector2(50, 50)
		ic.pivot_offset = Vector2(25, 25)
		_columna.add_child(ic)
		var nombre := String(c["nombre"])
		var l := _texto(nombre, _cabe(_fb, nombre, 20, COLUMNA_ANCHO - 30.0, 12), NAVY, _fb)
		l.position = Vector2(4, y + 64.0)
		l.size = Vector2(COLUMNA_ANCHO - 8.0, 30)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_columna.add_child(l)
		# el globo rojo: lo que hay por mirar o mejorar
		var globo := _dibujo(Vector2(COLUMNA_ANCHO - 30.0, y - 6.0), Vector2(36, 36), func(ci: Control):
			var cc := ci.size * 0.5
			ci.draw_circle(cc + Vector2(0, 2), 16.5, Color(0.2, 0.05, 0.15, 0.3))
			ci.draw_circle(cc, 16.5, Color.WHITE)
			ci.draw_circle(cc, 14.0, CEREZA)
			ci.draw_arc(cc, 10.5, PI * 1.1, PI * 1.6, 8, Color(1, 1, 1, 0.3), 3.0), _columna)
		globo.pivot_offset = Vector2(18, 18)
		var gt := _texto("", 20, Color.WHITE, _f)
		gt.size = Vector2(36, 36)
		gt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		globo.add_child(gt)
		_cat_items.append({"id": String(c["id"]), "icono": ic, "texto": l, "globo": globo, "globo_txt": gt})
	_cat_sel_y = 8.0 + _indice_cat(_cat) * CAT_PASO


func _indice_cat(cat: String) -> int:
	for i in _cat_items.size():
		if String(_cat_items[i]["id"]) == cat:
			return i
	return 0


func _pintar_columna(ci: Control) -> void:
	var w := ci.size.x
	var h := ci.size.y
	ci.draw_colored_polygon(PackedVector2Array([Vector2(12, 4), Vector2(w + 3, 4), Vector2(w + 3, h - 8), Vector2(w - 9, h + 4),
		Vector2(0, h + 4), Vector2(0, 16)]), Color(0.3, 0.3, 0.6, 0.12))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(12, 0), Vector2(w, 0), Vector2(w, h - 12), Vector2(w - 12, h),
		Vector2(0, h), Vector2(0, 12)]), Color8(252, 252, 255))
	# el recuadro oscuro de la elegida (se desliza al cambiar)
	var r := Rect2(9, _cat_sel_y, w - 18.0, CAT_PASO - 12.0)
	var p := PackedVector2Array([Vector2(r.position.x + 12, r.position.y), Vector2(r.end.x, r.position.y),
		Vector2(r.end.x, r.end.y - 12), Vector2(r.end.x - 12, r.end.y), Vector2(r.position.x, r.end.y),
		Vector2(r.position.x, r.position.y + 12)])
	ci.draw_colored_polygon(p, NAVY)
	ci.draw_polyline(PackedVector2Array([p[5], p[0], p[1]]), Color(1, 1, 1, 0.18), 2.0, true)


func _refrescar_columna() -> void:
	for i in _cat_items.size():
		var e: Dictionary = _cat_items[i]
		var sel := String(e["id"]) == _cat
		var ic: Control = e["icono"]
		ic.set("color", Color.WHITE if sel else NAVY)
		ic.set("hueco", NAVY if sel else Color8(252, 252, 255))
		(e["texto"] as Label).add_theme_color_override("font_color", Color.WHITE if sel else NAVY)
		var n := Cartas.avisos("" if String(e["id"]) == "todo" else String(e["id"]))
		(e["globo"] as Control).visible = n > 0
		(e["globo_txt"] as Label).text = str(n) if n < 100 else "99+"
	if is_instance_valid(_columna):
		_columna.queue_redraw()


func _entrada_columna(e: InputEvent) -> void:
	var p := Vector2(-1, -1)
	if e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed:
		p = (e as InputEventScreenTouch).position
	elif e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
			and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		p = (e as InputEventMouseButton).position
	if p.y < 0.0:
		return
	var i := int(floor((p.y - 8.0) / CAT_PASO))
	if i >= 0 and i < _cat_items.size():
		_elegir_categoria(String(_cat_items[i]["id"]))


func _elegir_categoria(cat: String, animar := true) -> void:
	if cat == _cat:
		return
	Audio.ui("aceptar", -9.0)
	_cat = cat
	_scroll = 0.0
	_obj = -1.0
	_vel = 0.0
	var destino := 8.0 + _indice_cat(cat) * CAT_PASO
	if animar:
		var tw := create_tween()
		tw.tween_method(_mover_seleccion, _cat_sel_y, destino, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var ic: Control = _cat_items[_indice_cat(cat)]["icono"]
		ic.scale = Vector2(0.7, 0.7)
		ic.create_tween().tween_property(ic, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_cat_sel_y = destino
	_refrescar_columna()
	_rellenar_rejilla(animar)


func _mover_seleccion(v: float) -> void:
	_cat_sel_y = v
	if is_instance_valid(_columna):
		_columna.queue_redraw()


# ================================================================== la X y lo que tienes
func _montar_x() -> void:
	var bx := _boton(Rect2(_w - 185.0, 0, 185, 92), func(ci: Control):
		var w := ci.size.x
		var h := ci.size.y
		ci.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h + 3), Vector2(18, h + 3),
			Vector2(0, h - 15)]), Color8(92, 36, 84))
		ci.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(18, h),
			Vector2(0, h - 18)]), X_ROSA), _cerrar_x, _raiz)
	var xt := _texto("X", 52, Color.WHITE, _f)
	xt.size = Vector2(185, 86)
	xt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bx.add_child(xt)


func _cerrar_x() -> void:
	if _ficha_id != "":
		_cerrar_ficha()
	if _cambio != "":
		_salir_cambio()
	_cerrar()


## LO QUE TIENES (oro, cubos de fuerza y diamantes): la pastilla azul oscuro de la foto, que baja al abrir una ficha
func _montar_pastilla() -> void:
	_pastilla = _dibujo(Vector2(_x0 + 110.0, -70.0), Vector2(452, 58), func(ci: Control):
		var s := ci.size
		ci.draw_colored_polygon(_forma_boton(s + Vector2(0, 5), 12.0, 12.0), Color(0.05, 0.02, 0.2, 0.3))
		ci.draw_colored_polygon(_forma_boton(s, 12.0, 12.0), Color.WHITE)
		var dentro := PackedVector2Array()
		for p in _forma_boton(s - Vector2(6, 6), 10.0, 10.0):
			dentro.append(p + Vector2(3, 3))
		ci.draw_colored_polygon(dentro, PASTILLA), _raiz)
	_pastilla.modulate.a = 0.0
	var iconos := [["moneda", Color(1.0, 0.78, 0.05)], ["cubo_fuerza", Color.WHITE], ["credito", Color(0.45, 0.9, 0.5)]]
	_pastilla_txt.clear()
	for i in 3:
		var x := 16.0 + i * 146.0
		var ic := IconoLobby.new()
		ic.icono = String(iconos[i][0])
		ic.color = iconos[i][1]
		ic.position = Vector2(x, 10)
		ic.size = Vector2(38, 38)
		_pastilla.add_child(ic)
		var l := _texto("0", 28, Color.WHITE, _f)
		l.position = Vector2(x + 45.0, 0)
		l.size = Vector2(96, 58)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.pivot_offset = Vector2(20, 29)
		_pastilla.add_child(l)
		_pastilla_txt.append(l)


func _refrescar_pastilla(pop := false) -> void:
	var v := [Settings.saldo(), Settings.saldo_cubos(), Settings.saldo_creditos()]
	for i in 3:
		var l: Label = _pastilla_txt[i]
		var t := _con_puntos(int(v[i]))
		if pop and l.text != t:
			var tw := l.create_tween()
			tw.tween_property(l, "scale", Vector2(1.3, 1.3), 0.08)
			tw.tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		l.text = t
		l.add_theme_font_size_override("font_size", _cabe(_f, t, 28, 94.0, 16))


func _ver_pastilla(si: bool) -> void:
	if si == _pastilla_ver or not is_instance_valid(_pastilla):
		return
	_pastilla_ver = si
	var tw := _pastilla.create_tween().set_parallel(true)
	tw.tween_property(_pastilla, "position:y", 23.0 if si else -70.0, 0.26).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT if si else Tween.EASE_IN)
	tw.tween_property(_pastilla, "modulate:a", 1.0 if si else 0.0, 0.18)


# ================================================================== el estado
func _refrescar() -> void:
	_refrescar_ranuras()
	_rellenar_rejilla(false)
	_refrescar_columna()
	_disp_txt.text = "DISPONIBLE: %d/%d" % [Cartas.disponibles(), Cartas.LISTA.size()]
	_refrescar_pastilla()


## Las cartas (de las dos partes) que enseñan `id`
func _cartas_de(id: String) -> Array:
	var out: Array = []
	for r in _ranuras:
		if (r as Carta).id == id and (r as Carta).modo == "carta":
			out.append(r)
	for e in _cartas_set:
		if String(e["id"]) == id:
			out.append(e["carta"])
	return out


## La carta de `id` que se ve (la de la izquierda si esta equipada)
func _carta_de(id: String) -> Control:
	var l := _cartas_de(id)
	return l[0] if not l.is_empty() else null


# ================================================================== el dedo
func _entrada_izq(e: InputEvent) -> void:
	var p := Vector2.ZERO
	var apoya := false
	var suelta := false
	if e is InputEventScreenTouch:
		p = (e as InputEventScreenTouch).position
		apoya = (e as InputEventScreenTouch).pressed
		suelta = not apoya
	elif e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		p = (e as InputEventMouseButton).position
		apoya = (e as InputEventMouseButton).pressed
		suelta = not apoya
	else:
		return
	var i := _ranura_en(p)
	if apoya:
		_izq_pulsado = i
		_izq_p0 = p
		if i >= 0:
			(_ranuras[i] as Control).scale = Vector2(0.96, 0.96)
	elif suelta:
		var antes := _izq_pulsado
		_izq_pulsado = -1
		if antes >= 0:
			(_ranuras[antes] as Control).scale = Vector2.ONE
		if antes >= 0 and antes == i and p.distance_to(_izq_p0) < 18.0:
			_tocar_ranura(i)


func _ranura_en(p: Vector2) -> int:
	for i in _ranuras.size():
		var c: Control = _ranuras[i]
		if Rect2(c.position, c.size).has_point(p):
			return i
	return -1


func _tocar_ranura(i: int) -> void:
	var c: Carta = _ranuras[i]
	if _cambio != "":
		if c.id != "":
			_hacer_cambio(i)
		return
	if c.id == "":
		Audio.ui("atras", -10.0)
		_avisar("Toca una carta del set para equiparla")
		return
	_abrir_ficha(c.id, c)


func _entrada_rejilla(e: InputEvent) -> void:
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
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_rueda(1.0)
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_rueda(-1.0)
	elif e is InputEventMouseMotion and _pulsado and _toque < 0:
		_arrastrar((e as InputEventMouseMotion).position)
	elif e is InputEventPanGesture:
		_obj = -1.0
		_scroll = clampf(_scroll + (e as InputEventPanGesture).delta.y * 40.0, 0.0, _scroll_max())


func _en_set(p: Vector2) -> Dictionary:
	var q := p + Vector2(0.0, _scroll)
	for c in _cartas_set:
		if (c["rect"] as Rect2).has_point(q):
			return c
	return {}


func _apoyar(p: Vector2) -> void:
	_pulsado = true
	_p0 = p
	_p_ult = p
	_t_ult = Time.get_ticks_msec()
	_movido = 0.0
	_vel = 0.0
	_obj = -1.0
	var c := _en_set(p)
	if not c.is_empty() and String(c["id"]) != "":
		_apretada = c["carta"]
		_apretada.scale = Vector2(0.96, 0.96)


func _soltar_apretada() -> void:
	if is_instance_valid(_apretada):
		_apretada.scale = Vector2.ONE
	_apretada = null


func _arrastrar(p: Vector2) -> void:
	if not _pulsado:
		return
	var dy := p.y - _p_ult.y
	_movido = maxf(_movido, p.distance_to(_p0))
	if _movido >= 14.0:
		_soltar_apretada()
	_scroll = clampf(_scroll - dy, 0.0, _scroll_max())
	var ahora := Time.get_ticks_msec()
	var dt := float(ahora - _t_ult) / 1000.0
	if dt > 0.0:
		_vel = lerpf(_vel, -dy / dt, 0.4)
	_p_ult = p
	_t_ult = ahora


func _soltar(p: Vector2) -> void:
	_pulsado = false
	_soltar_apretada()
	if _movido < 14.0 and p.distance_to(_p0) < 14.0:
		_vel = 0.0
		var c := _en_set(p)
		if not c.is_empty() and String(c["id"]) != "":
			_tocar_set(String(c["id"]), c["carta"])
		return
	if Time.get_ticks_msec() - _t_ult > 90:
		_vel = 0.0                  # se paro antes de soltar: sin inercia
	_vel = clampf(_vel, -5000.0, 5000.0)


func _rueda(sentido: float) -> void:
	_vel = 0.0
	_obj = clampf((_obj if _obj >= 0.0 else _scroll) + sentido * REJILLA_PASO.y, 0.0, _scroll_max())


func _tocar_set(id: String, carta: Control) -> void:
	if _cambio != "":
		if id == _cambio:
			return
		# en el modo cambio, tocar otra del set cambia la que entra
		if Cartas.tiene(id) and not Cartas.equipada(id):
			_entrar_cambio(id)
		else:
			_salir_cambio()
			_abrir_ficha(id, carta)
		return
	_abrir_ficha(id, carta)


# ================================================================== LA FICHA
func _abrir_ficha(id: String, desde: Control, animar := true) -> void:
	if _ficha_id != "":
		_cerrar_ficha(false)
	_ficha_id = id
	_ficha_desde = desde
	_subiendo = false
	_aviso_t = minf(_aviso_t, 0.2)      # el aviso de antes se va (estaba puesto para otra ficha)
	Audio.ui("aceptar", -9.0)
	# abrirla la da por vista (el NUEVO se va al cerrarla: que no desaparezca debajo del dedo)
	if Cartas.nueva(id):
		Cartas.marcar_vista(id)
	for c in _cartas_de(id):
		(c as Carta).elegida = true
	_capa_ficha.visible = true
	_construir_ficha()
	# al lado de la carta tocada: las del set, a la izquierda del set (como en la foto); las activas, a su derecha
	var r := _rect_en_raiz(desde)
	var x: float
	var hacia_izq := true
	if _es_del_set(desde):
		x = _x0 - 29.0 - FICHA.x
	else:
		x = r.end.x + 18.0
		hacia_izq = false
		if x + FICHA.x > _w - 12.0:
			x = r.position.x - 18.0 - FICHA.x
			hacia_izq = true
	x = clampf(x, 12.0, _w - FICHA.x - 12.0)
	var alto := _ficha.size.y
	var y := clampf(r.position.y - 3.0, 12.0, ALTO - alto - 12.0)
	_ficha.position = Vector2(x, y)
	_ficha.pivot_offset = Vector2(FICHA.x if hacia_izq else 0.0, clampf(r.get_center().y - y, 40.0, alto - 40.0))
	if animar:
		_ficha.scale = Vector2(0.82, 0.82)
		_ficha.modulate.a = 0.0
		var tw := _ficha.create_tween().set_parallel(true)
		tw.tween_property(_ficha, "modulate:a", 1.0, 0.12)
		tw.tween_property(_ficha, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_refrescar_pastilla()
	_ver_pastilla(true)


func _es_del_set(c: Control) -> bool:
	for e in _cartas_set:
		if e["carta"] == c:
			return true
	return false


func _cerrar_ficha(con_sonido := true) -> void:
	if _ficha_id == "":
		return
	if con_sonido:
		Audio.ui("submenu_cierra", -12.0)
	if _subiendo:
		# cerrada a mitad de subir: las cartas vuelven a enseñar lo de verdad
		if _tw_subida != null and _tw_subida.is_valid():
			_tw_subida.kill()
		for c in _cartas_de(_ficha_id):
			(c as Carta).nivel_ver = -1
			(c as Carta).fraccion_ver = -1.0
			(c as Carta).destello = 0.0
	for c in _cartas_de(_ficha_id):
		(c as Carta).elegida = false
	_ficha_id = ""
	_ficha_desde = null
	_subiendo = false
	if is_instance_valid(_ficha):
		var f := _ficha
		var tw := f.create_tween().set_parallel(true)
		tw.tween_property(f, "modulate:a", 0.0, 0.12)
		tw.tween_property(f, "scale", Vector2(0.9, 0.9), 0.12)
		tw.chain().tween_callback(f.queue_free)
	_ficha = null
	_capa_ficha.visible = false
	_ver_pastilla(false)
	# lo que haya cambiado al mirarla (el NUEVO, los globos)
	for c in _ranuras:
		(c as Carta).refrescar()
	for e in _cartas_set:
		(e["carta"] as Carta).refrescar()
	_refrescar_columna()


## Tocar fuera de la ficha la cierra; si lo tocado es otra carta, se abre la suya
func _entrada_capa_ficha(e: InputEvent) -> void:
	var p := Vector2(-1, -1)
	if e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed:
		p = (e as InputEventScreenTouch).position
	elif e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
			and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		p = (e as InputEventMouseButton).position
	if p.x < 0.0:
		return
	_capa_ficha.accept_event()
	var antes := _ficha_id
	_cerrar_ficha()
	# ¿otra carta debajo? (las activas o las del set)
	for r in _ranuras:
		var c := r as Carta
		if c.id != "" and c.id != antes and _rect_en_raiz(c).has_point(p):
			_abrir_ficha(c.id, c)
			return
	var rr := _rect_en_raiz(_rejilla)
	if rr.has_point(p):
		for s in _cartas_set:
			var c := s["carta"] as Carta
			if String(s["id"]) != "" and String(s["id"]) != antes and _rect_en_raiz(c).has_point(p):
				_abrir_ficha(c.id, c)
				return


## Monta (o rehace) lo de dentro de la ficha con lo que hay ahora
func _construir_ficha() -> void:
	var pos := Vector2.ZERO
	var piv := Vector2.ZERO
	if is_instance_valid(_ficha):
		pos = _ficha.position
		piv = _ficha.pivot_offset
		_ficha.queue_free()
	var id := _ficha_id
	var d := Cartas.datos(id)
	var mia := Cartas.tiene(id)
	var n := Cartas.nivel(id)
	var maximo := mia and n >= Cartas.NIVEL_MAX
	var rar: Dictionary = SkinsArmas.RAREZAS[clampi(Cartas.rareza(id), 0, SkinsArmas.RAREZAS.size() - 1)]
	var col_rar: Color = rar["color"]
	_ficha = _dibujo(pos, FICHA, func(ci: Control): _pintar_ficha(ci, col_rar), _capa_ficha)
	_ficha.pivot_offset = piv
	_ficha.mouse_filter = Control.MOUSE_FILTER_STOP
	_ficha.material = _material_hex(0.03, 70.0)
	# el hexagono
	_ficha_hex = IconoLobby.new()
	_ficha_hex.icono = String(d.get("icono", "carta_todo"))
	_ficha_hex.color = (d.get("color", Color.WHITE) as Color) if mia else Color(0.6, 0.59, 0.7)
	_ficha_hex.position = Vector2(20, 22)
	_ficha_hex.size = Vector2(104, 104)
	_ficha_hex.pivot_offset = Vector2(52, 52)
	_ficha.add_child(_ficha_hex)
	# la rareza (en su color) y la categoria con su dibujo
	var tr := String(rar["nombre"])
	var chip := _texto(tr, 25, Color.WHITE, _fb, 5, col_rar.darkened(0.55))
	chip.position = Vector2(141, 31)
	chip.size = Vector2(_fb.get_string_size(tr, HORIZONTAL_ALIGNMENT_LEFT, -1, 25).x + 36.0, 43)
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ficha.add_child(chip)
	var cat := String(d.get("cat", ""))
	var gl := IconoLobby.new()
	gl.icono = "glifo_" + Carta.icono_categoria(cat).trim_prefix("carta_")
	gl.color = FICHA_TINTA
	gl.hueco = FICHA_CARA
	gl.position = Vector2(142, 88)
	gl.size = Vector2(32, 32)
	_ficha.add_child(gl)
	var tc := _texto(Cartas.nombre_categoria(cat), 27, FICHA_TINTA, _fb)
	tc.position = Vector2(180, 84)
	tc.size = Vector2(250, 40)
	tc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tc.add_theme_font_size_override("font_size", _cabe(_fb, tc.text, 27, 250.0, 16))
	_ficha.add_child(tc)
	# lo que hace (la ficha es tan alta como pida: con una linea no se queda un hueco en medio)
	var desc := _texto(String(d.get("desc", "")), 25, FICHA_TEXTO, _fr)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_constant_override("line_spacing", -1)
	var tam := 25
	var alto_desc := _fr.get_multiline_string_size(desc.text, HORIZONTAL_ALIGNMENT_LEFT, 404.0, tam).y
	while tam > 16 and alto_desc > 190.0:
		tam -= 1
		alto_desc = _fr.get_multiline_string_size(desc.text, HORIZONTAL_ALIGNMENT_LEFT, 404.0, tam).y
	desc.add_theme_font_size_override("font_size", tam)
	desc.position = Vector2(25, 152)
	desc.size = Vector2(404, alto_desc + 6.0)
	_ficha.add_child(desc)
	_ficha_caja_y = 152.0 + maxf(alto_desc, 66.0) + 22.0
	_ficha_pie_y = _ficha_caja_y + 150.0
	_ficha.size = Vector2(FICHA.x, _ficha_pie_y + 132.0)
	var cy := _ficha_caja_y
	var py := _ficha_pie_y
	# LA CAJA NARANJA: lo que mejora, el valor de ahora y el siguiente, y la barra de copias
	var st := _texto(String(d.get("stat", "")), 23, FICHA_TINTA, _fb)
	st.position = Vector2(40, cy + 9.0)
	st.size = Vector2(380, 32)
	st.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	st.add_theme_font_size_override("font_size", _cabe(_fb, st.text, 23, 376.0, 14))
	_ficha.add_child(st)
	_ficha_valores = HBoxContainer.new()
	_ficha_valores.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ficha_valores.position = Vector2(40, cy + 41.0)
	_ficha_valores.size = Vector2(380, 36)
	_ficha_valores.add_theme_constant_override("separation", 4)
	_ficha.add_child(_ficha_valores)
	_poner_valores(id)
	_ficha_barra = _dibujo(Vector2(40, cy + 81.0), Vector2(377, 40), _pintar_barra_ficha, _ficha)
	_ficha_barra.animado = true
	# los botones (sin la carta: donde sale)
	if not mia:
		var ic := IconoLobby.new()
		ic.icono = "cofre"
		ic.color = Color(0.3, 0.55, 0.95)
		ic.position = Vector2(34, py + 25.0)
		ic.size = Vector2(62, 62)
		_ficha.add_child(ic)
		var tl := _texto("CONSÍGUELA ABRIENDO\nCOFRES", 26, FICHA_TINTA, _f)
		tl.position = Vector2(110, py + 11.0)
		tl.size = Vector2(320, 92)
		tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tl.add_theme_constant_override("line_spacing", -4)
		_ficha.add_child(tl)
	else:
		var puesta := Cartas.equipada(id)
		var be := _boton(Rect2(25, py + 16.0, 200, 81), func(ci: Control):
			_pintar_boton(ci, AMARILLO if not puesta else Color8(236, 120, 110)), _pulsar_equipar, _ficha)
		var te := _texto("QUITAR" if puesta else "EQUIPAR", 32, TINTA if not puesta else Color.WHITE, _f,
			0 if not puesta else 6, Color(0.45, 0.1, 0.08, 0.5))
		te.size = Vector2(192, 78)
		te.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		te.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		be.add_child(te)
		var falta := Cartas.que_falta(id)
		var apagado := maximo or falta == "copias"
		var bm := _boton(Rect2(228, py + 16.0, 200, 81), func(ci: Control):
			_pintar_boton(ci, Color8(150, 146, 186) if apagado else MORADO), _pulsar_mejorar, _ficha)
		if maximo:
			var tx := _texto("MÁX.", 34, Color8(236, 234, 250), _f, 6, Color(0.2, 0.18, 0.4, 0.5))
			tx.size = Vector2(192, 78)
			tx.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tx.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			bm.add_child(tx)
		else:
			var tm := _texto("MEJORA", 26, Color8(214, 210, 255) if not apagado else Color8(236, 234, 250), _f)
			tm.position = Vector2(0, 4)
			tm.size = Vector2(192, 36)
			tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			bm.add_child(tm)
			# EL PRECIO: cubos de fuerza + oro (2026-09-30, pedido: "mejorar una carta cuesta cubos de fuerza y dinero, no
			# diamantes"), cada uno con su icono; lo que no te llega, en rojo
			if _mejorando == id:
				var tp := _texto("· · ·", 33, ORO_TEXTO, _f, 6, Color(0.25, 0.12, 0.45, 0.55))
				tp.position = Vector2(0, 34)
				tp.size = Vector2(192, 44)
				tp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				tp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				bm.add_child(tp)
			else:
				var partes := []
				if Cartas.cubos_para(id) > 0:
					partes.append(["cubo_fuerza", Color.WHITE, Cartas.cubos_para(id), falta == "cubos"])
				partes.append(["moneda", Color(1.0, 0.78, 0.05), Cartas.oro_para(id), falta == "oro"])
				var letra := 33 if partes.size() == 1 else 25
				var ico := 32.0 if partes.size() == 1 else 25.0
				var anchos := []
				var todo := 10.0 * (partes.size() - 1)
				for pa in partes:
					var w := _f.get_string_size(_con_puntos(int(pa[2])), HORIZONTAL_ALIGNMENT_LEFT, -1, letra).x
					anchos.append(w)
					todo += ico + 4.0 + w
				var x := (192.0 - todo) * 0.5
				for i in partes.size():
					var pa: Array = partes[i]
					var ic := IconoLobby.new()
					ic.icono = String(pa[0])
					ic.color = pa[1]
					ic.position = Vector2(x, 56.0 - ico * 0.5)
					ic.size = Vector2(ico, ico)
					bm.add_child(ic)
					x += ico + 4.0
					var tp := _texto(_con_puntos(int(pa[2])), letra, Color8(255, 150, 140) if bool(pa[3]) else ORO_TEXTO, _f, 6,
						Color(0.25, 0.12, 0.45, 0.55))
					tp.position = Vector2(x, 34)
					tp.size = Vector2(float(anchos[i]) + 12.0, 44)
					tp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
					bm.add_child(tp)
					x += float(anchos[i]) + 10.0
	# el fogonazo de subir de nivel (encima de todo lo de la ficha)
	_ficha_fogonazo = _dibujo(Vector2.ZERO, _ficha.size, func(ci: Control):
		ci.draw_colored_polygon(Carta.forma(Rect2(Vector2(10, 10), ci.size - Vector2(20, 20)), 10.0), Color(1, 1, 1, 0.9)), _ficha)
	_ficha_fogonazo.modulate.a = 0.0


## "+7% > +9%": el valor de ahora y, en verde, el del nivel siguiente (sin la carta: el que da al conseguirla)
func _poner_valores(id: String) -> void:
	for c in _ficha_valores.get_children():
		c.queue_free()
	var n := Cartas.nivel(id)
	var mia := Cartas.tiene(id)
	var ahora := _texto(Cartas.texto_valor(id, n if mia else 1), 21, FICHA_TINTA, _fb)
	ahora.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ahora.size_flags_vertical = Control.SIZE_FILL
	_ficha_valores.add_child(ahora)
	if not mia:
		var a := _texto("AL CONSEGUIRLA", 17, FICHA_TEXTO, _fb)
		a.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		a.size_flags_vertical = Control.SIZE_FILL
		_ficha_valores.add_child(a)
		return
	if n >= Cartas.NIVEL_MAX:
		var m := _texto("NIVEL MÁXIMO", 19, VERDE, _f, 4, Color8(20, 70, 0))
		m.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		m.size_flags_vertical = Control.SIZE_FILL
		_ficha_valores.add_child(m)
		return
	var flecha := _dibujo(Vector2.ZERO, Vector2(14, 36), func(ci: Control):
		var c := Vector2(6, 18)
		ci.draw_polyline(PackedVector2Array([c + Vector2(-4, -6), c + Vector2(3, 0), c + Vector2(-4, 6)]), VERDE, 3.5, true), null)
	flecha.custom_minimum_size = Vector2(14, 36)
	_ficha_valores.add_child(flecha)
	var sig := _texto(Cartas.texto_valor(id, n + 1), 26, Color8(96, 220, 40), _f, 6, Color8(24, 80, 4))
	sig.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sig.size_flags_vertical = Control.SIZE_FILL
	_ficha_valores.add_child(sig)


func _pintar_ficha(ci: Control, col_rar: Color) -> void:
	var w := ci.size.x
	var h := ci.size.y
	var todo := Rect2(Vector2.ZERO, ci.size)
	# la sombra, el canto con su bisel y la cara
	var sombra := PackedVector2Array()
	for p in Carta.forma(todo, 18.0):
		sombra.append(p + Vector2(5, 9))
	ci.draw_colored_polygon(sombra, Color(0.1, 0.05, 0.3, 0.32))
	ci.draw_colored_polygon(Carta.forma(todo, 18.0), FICHA_CANTO)
	ci.draw_polyline(PackedVector2Array([Vector2(1.5, h - 18), Vector2(1.5, 18), Vector2(18, 1.5), Vector2(w - 18, 1.5)]),
		Color(1, 1, 1, 0.85), 3.0, true)
	ci.draw_polyline(PackedVector2Array([Vector2(w - 18, 1.5), Vector2(w - 1.5, 18), Vector2(w - 1.5, h - 18),
		Vector2(w - 18, h - 1.5), Vector2(18, h - 1.5), Vector2(1.5, h - 18)]), Color8(172, 168, 204), 3.0, true)
	var cara := Carta.forma(todo.grow(-10.0), 10.0)
	ci.draw_colored_polygon(cara, FICHA_CARA)
	# el pie de los botones, algo mas oscuro
	var py := _ficha_pie_y
	for p in Geometry2D.intersect_polygons(cara, PackedVector2Array([Vector2(0, py), Vector2(w, py), Vector2(w, h),
			Vector2(0, h)])):
		ci.draw_colored_polygon(p, FICHA_PIE)
	ci.draw_rect(Rect2(10, py, w - 20, 2), Color8(208, 205, 232))
	# la raya de debajo de la cabecera
	ci.draw_rect(Rect2(25, 140, w - 50, 2), Color8(214, 212, 236))
	# la rareza: su recuadro, en su color
	var tr := String(SkinsArmas.RAREZAS[clampi(Cartas.rareza(_ficha_id), 0, SkinsArmas.RAREZAS.size() - 1)]["nombre"])
	var ancho := _fb.get_string_size(tr, HORIZONTAL_ALIGNMENT_LEFT, -1, 25).x + 36.0
	var chip := Rect2(141, 31, ancho, 43)
	ci.draw_colored_polygon(PackedVector2Array([chip.position, Vector2(chip.end.x, chip.position.y),
		Vector2(chip.end.x - 10.0, chip.end.y), Vector2(chip.position.x, chip.end.y)]), col_rar.darkened(0.12))
	ci.draw_rect(Rect2(chip.position, Vector2(ancho - 1.0, 3)), col_rar.lightened(0.35))
	# la caja naranja
	var caja := Rect2(23, _ficha_caja_y, w - 46, 133)
	ci.draw_polygon(PackedVector2Array([caja.position, Vector2(caja.end.x, caja.position.y), caja.end,
		Vector2(caja.position.x, caja.end.y)]), PackedColorArray([Color8(253, 222, 180), Color8(252, 218, 174),
		Color8(250, 204, 152), Color8(250, 206, 156)]))
	ci.draw_rect(Rect2(caja.position, Vector2(caja.size.x, 2)), Color(1, 1, 1, 0.5))


## La barra de la ficha: el nivel en su cuadro, las copias ("2/2") y, si hay de sobra, la flecha de mejorar. Mientras se
## sube de nivel enseña lo que diga la animacion (_fb_*)
func _pintar_barra_ficha(ci: Control) -> void:
	var id := _ficha_id
	if id == "":
		return
	var w := ci.size.x
	var h := ci.size.y - 3.0
	var mia := Cartas.tiene(id)
	var maximo := mia and Cartas.nivel(id) >= Cartas.NIVEL_MAX and not _subiendo
	var n := _fb_nivel if _subiendo else Cartas.nivel(id)
	var frac := _fb_frac if _subiendo else _fraccion(id)
	var txt := _fb_texto if _subiendo else ("MÁX." if maximo else ("%d/%d" % [Cartas.copias(id), Cartas.copias_para(id)] if mia else "0/1"))
	var xs := 66.0
	var x1 := w - 20.0
	ci.draw_rect(Rect2(3, 4, x1, h), Color(0.6, 0.3, 0.05, 0.18))
	ci.draw_rect(Rect2(xs, 0, x1 - xs, h), Color8(240, 196, 156))
	ci.draw_rect(Rect2(xs, 0, x1 - xs, 4), Color8(222, 170, 126))
	if frac > 0.0:
		var xf := xs + (x1 - xs) * clampf(frac, 0.0, 1.0)
		ci.draw_rect(Rect2(xs, 0, xf - xs, h), Color8(255, 200, 48))
		ci.draw_rect(Rect2(xs, 0, xf - xs, 4), Color8(255, 230, 140))
		ci.draw_rect(Rect2(xs, h - 4, xf - xs, 4), Color8(230, 162, 24))
		if _fb_brillo > 0.0:
			var x := lerpf(xs - 60.0, xf + 30.0, _fb_brillo)
			var raya := PackedVector2Array([Vector2(x, 0), Vector2(x + 30, 0), Vector2(x + 10, h), Vector2(x - 20, h)])
			for p in Geometry2D.intersect_polygons(raya, PackedVector2Array([Vector2(xs, 0), Vector2(xf, 0), Vector2(xf, h),
					Vector2(xs, h)])):
				ci.draw_colored_polygon(p, Color(1, 1, 1, 0.55))
	# el cuadro del nivel
	var cuadro := Color8(190, 100, 26) if mia else Color8(128, 120, 150)
	ci.draw_rect(Rect2(0, 0, xs, h), cuadro)
	ci.draw_rect(Rect2(0, 0, xs, 4), cuadro.lightened(0.25))
	var tn := str(n) if mia else "0"
	var ts := _f.get_string_size(tn, HORIZONTAL_ALIGNMENT_LEFT, -1, 30)
	ci.draw_string(_f, Vector2(xs * 0.5 - ts.x * 0.5 - 1.0, h * 0.5 + 11.0), tn, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)
	# las copias: las dos cartitas y el numero, en medio de la barra
	var tt := 25
	var tw := _f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tt).x
	var total := 26.0 + 5.0 + tw
	var cx0 := (xs + x1) * 0.5 - total * 0.5
	Carta.copitas(ci, Vector2(cx0 + 12.0, h * 0.5), 1.5, Color.WHITE)
	var base := h * 0.5 + tt * 0.36
	ci.draw_string_outline(_f, Vector2(cx0 + 31.0, base), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tt, 6, Color8(168, 88, 14))
	ci.draw_string(_f, Vector2(cx0 + 31.0, base), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tt, Color.WHITE)
	# la flecha de mejorar, al final (sube y baja)
	if mia and not maximo and frac >= 0.999:
		var c := Vector2(w - 18.0, h * 0.5 - 2.0 - absf(sin(_t * 3.2)) * 3.0)
		var fl := PackedVector2Array([c + Vector2(-15, 1), c + Vector2(0, -15), c + Vector2(15, 1), c + Vector2(7, 1),
			c + Vector2(7, 16), c + Vector2(-7, 16), c + Vector2(-7, 1)])
		ci.draw_colored_polygon(fl, Color8(255, 214, 96))
		ci.draw_polyline(_cerrado(fl), Color8(214, 108, 16), 3.0, true)


static func _fraccion(id: String) -> float:
	if not Cartas.tiene(id):
		return 0.0
	if Cartas.nivel(id) >= Cartas.NIVEL_MAX:
		return 1.0
	return clampf(float(Cartas.copias(id)) / float(maxi(1, Cartas.copias_para(id))), 0.0, 1.0)


# ================================================================== EQUIPAR / QUITAR / EL MODO CAMBIO
func _pulsar_equipar() -> void:
	var id := _ficha_id
	if id == "" or _subiendo:
		return
	if Cartas.equipada(id):
		Cartas.quitar(id)
		Audio.ui("atras", -6.0)
		_cerrar_ficha(false)
		_refrescar()
		_avisar("%s ya no está activa" % String(Cartas.datos(id).get("nombre", "")))
		return
	if Cartas.equipar(id):
		Audio.ui("activar", -5.0)
		_cerrar_ficha(false)
		_refrescar()
		var i := Cartas.equipadas().find(id)
		if i >= 0:
			_celebrar_ranura(i)
		return
	if not Cartas.tiene(id):
		Audio.ui("atras", -8.0)
		_avisar("Aún no tienes esta carta")
		return
	# las ranuras estan llenas: se elige cual sale
	_entrar_cambio(id)


func _entrar_cambio(id: String) -> void:
	if _ficha_id != "":
		_cerrar_ficha(false)
	Audio.ui("aceptar", -6.0)
	_cambio = id
	for r in _ranuras:
		(r as Carta).resalte = (r as Carta).id != ""
	for e in _cartas_set:
		(e["carta"] as Carta).elegida = String(e["id"]) == id
	_poner_barra_izq()


func _salir_cambio() -> void:
	_cambio = ""
	for r in _ranuras:
		(r as Carta).resalte = false
		(r as Control).rotation = 0.0
	for e in _cartas_set:
		(e["carta"] as Carta).elegida = false
	_poner_barra_izq()


## El cambio: la de la ranura `i` sale y entra la elegida. La ranura se da la vuelta y sale la nueva, con chispas.
func _hacer_cambio(i: int) -> void:
	var r: Carta = _ranuras[i]
	var sale := r.id
	var entra := _cambio
	if not Cartas.cambiar(sale, entra):
		_salir_cambio()
		return
	_salir_cambio()
	Audio.ui("activar", -5.0)
	var tw := r.create_tween()
	tw.tween_property(r, "scale", Vector2(0.0, 1.05), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		r.id = entra
		r.modo = "carta"
		r.refrescar()
		r.destello = 1.0)
	tw.tween_property(r, "scale", Vector2(1.08, 1.08), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(r, "scale", Vector2.ONE, 0.14)
	tw.parallel().tween_property(r, "destello", 0.0, 0.4)
	await get_tree().create_timer(0.13).timeout
	if _cerrando or not is_instance_valid(r):
		return
	var c := _rect_en_raiz(r).get_center()
	_fx.chispas(c, (Cartas.datos(entra).get("color", Color.WHITE) as Color).lightened(0.3), 26, 520.0, 5.0)
	_fx.aro(c, 30.0, 190.0, 0.4, Color(1, 0.95, 0.6), 7.0)
	_refrescar()
	_avisar("ENTRA %s, SALE %s" % [String(Cartas.datos(entra).get("nombre", "")), String(Cartas.datos(sale).get("nombre", ""))])


## Una carta que acaba de entrar en su ranura: se hincha, fogonazo y chispas
func _celebrar_ranura(i: int) -> void:
	var r: Carta = _ranuras[i]
	r.scale = Vector2(0.4, 0.4)
	r.destello = 1.0
	var tw := r.create_tween()
	tw.tween_property(r, "scale", Vector2(1.1, 1.1), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(r, "scale", Vector2.ONE, 0.14)
	tw.parallel().tween_property(r, "destello", 0.0, 0.45)
	var c := _rect_en_raiz(r).get_center()
	var col := (Cartas.datos(r.id).get("color", Color.WHITE) as Color).lightened(0.3)
	_fx.chispas(c, col, 30, 560.0, 5.0)
	_fx.estrellas(c, Color(1, 0.96, 0.7), 8, 240.0)
	_fx.aro(c, 30.0, 200.0, 0.42, Color(1, 0.95, 0.6), 7.0)


# ================================================================== MEJORAR
func _pulsar_mejorar() -> void:
	var id := _ficha_id
	if id == "" or _subiendo or _mejorando != "":
		return
	var n0 := Cartas.nivel(id)
	var c0 := Cartas.copias(id)
	var p0 := Cartas.copias_para(id)
	var coste := Cartas.oro_para(id)
	match Cartas.mejorar(id):
		"hecho":
			_celebrar_subida(id, n0, c0, p0)
		"enviado":
			_mejorando = id
			_mejora_t = 0.0
			_mejora_antes = {"n": n0, "c": c0, "p": p0}
			Audio.ui("aceptar", -6.0)
			_construir_ficha()
		"copias":
			Audio.ui("atras", -8.0)
			var faltan := p0 - c0
			_avisar("Te falta%s %d copia%s: salen en los COFRES" % ["n" if faltan != 1 else "", faltan, "s" if faltan != 1 else ""])
		"cubos":
			Audio.ui("atras", -8.0)
			_avisar("Te faltan %s cubos de fuerza: salen en los COFRES y en el PASE" % _con_puntos(
				Cartas.cubos_para(id) - Settings.saldo_cubos()))
		"oro":
			Audio.ui("atras", -8.0)
			_avisar("Te faltan %s de oro" % _con_puntos(coste - Settings.saldo()))
		"maximo":
			Audio.ui("atras", -8.0)
			_avisar("Ya está al nivel máximo")
		"no_la_tienes":
			Audio.ui("atras", -8.0)
			_avisar("Aún no tienes esta carta")
		_:
			Audio.ui("atras", -8.0)
			_avisar("No se pudo mejorar: sin conexión con la cuenta")


## ¡SUBE DE NIVEL! La barra se llena, la carta y el hexagono se hinchan, fogonazo y chispas, el numero sube, sale
## "¡NIVEL N!" y la barra baja a lo que queda; al final los valores nuevos, con un saltito.
func _celebrar_subida(id: String, n0: int, c0: int, p0: int) -> void:
	if _ficha_id != id:
		_refrescar()
		return
	_subiendo = true
	var n1 := Cartas.nivel(id)
	_fb_nivel = n0
	_fb_frac = clampf(float(c0) / float(maxi(1, p0)), 0.0, 1.0)
	_fb_texto = "%d/%d" % [c0, p0]
	_fb_brillo = 0.0
	var cartas := _cartas_de(id)
	for c in cartas:
		(c as Carta).nivel_ver = n0
		(c as Carta).fraccion_ver = 1.0
		(c as Carta).refrescar()
	Audio.ui("aceptar", -4.0)
	# 1. la barra se llena del todo, con un brillo que la cruza
	var tw := create_tween()
	tw.tween_property(self, "_fb_frac", 1.0, 0.2)
	tw.parallel().tween_property(self, "_fb_brillo", 1.0, 0.34)
	if not await _esperar(0.3, id):
		return
	# 2. EL SALTO: fogonazo, el hexagono y la carta se hinchan, chispas, y el numero sube
	Audio.ui("subir_rango", -3.0)
	_fb_nivel = n1
	_fb_brillo = 0.0
	var col := (Cartas.datos(id).get("color", Color.WHITE) as Color)
	if is_instance_valid(_ficha_fogonazo):
		_ficha_fogonazo.modulate.a = 0.8
		_ficha_fogonazo.create_tween().tween_property(_ficha_fogonazo, "modulate:a", 0.0, 0.35)
	if is_instance_valid(_ficha_hex):
		var th := _ficha_hex.create_tween()
		th.tween_property(_ficha_hex, "scale", Vector2(1.45, 1.45), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		th.tween_property(_ficha_hex, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		var ch := _ficha.position + _ficha_hex.position + _ficha_hex.size * 0.5
		_fx.chispas(ch, Color8(255, 190, 40), 40, 780.0, 6.0)
		_fx.chispas(ch, col, 26, 600.0, 5.0)
		_fx.estrellas(ch, Color8(255, 214, 80), 14, 320.0)
		_fx.aro(ch, 40.0, 280.0, 0.45, Color8(255, 196, 60), 9.0)
		_nivel_texto(n1, _ficha.position + Vector2(FICHA.x * 0.5 + 30.0, 6.0))
	for c in cartas:
		var carta := c as Carta
		carta.nivel_ver = n1
		carta.destello = 1.0
		carta.pivot_offset = carta.size * 0.5
		var tc := carta.create_tween()
		tc.tween_property(carta, "scale", Vector2(1.16, 1.16), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tc.tween_property(carta, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tc.parallel().tween_property(carta, "destello", 0.0, 0.45)
		var cc := _rect_en_raiz(carta).get_center()
		_fx.chispas(cc, Color8(255, 190, 40), 18, 480.0, 4.5)
		_fx.chispas(cc, col.lightened(0.2), 12, 420.0, 4.0)
	if not await _esperar(0.42, id):
		return
	# 3. la barra baja a lo que queda
	var p1 := Cartas.copias_para(id)
	var fin := 1.0 if n1 >= Cartas.NIVEL_MAX else clampf(float(Cartas.copias(id)) / float(maxi(1, p1)), 0.0, 1.0)
	_fb_texto = "MÁX." if n1 >= Cartas.NIVEL_MAX else "%d/%d" % [Cartas.copias(id), p1]
	_tw_subida = create_tween().set_parallel(true)
	_tw_subida.tween_property(self, "_fb_frac", fin, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for c in cartas:
		_tw_subida.tween_property(c, "fraccion_ver", fin, 0.4)
	if not await _esperar(0.45, id):
		return
	# 4. lo nuevo: los valores y los botones, con un saltito
	_subiendo = false
	for c in cartas:
		(c as Carta).nivel_ver = -1
		(c as Carta).fraccion_ver = -1.0
		(c as Carta).refrescar()
	_construir_ficha()
	if is_instance_valid(_ficha_valores):
		_ficha_valores.pivot_offset = Vector2(0, 18)
		_ficha_valores.scale = Vector2(1.25, 1.25)
		_ficha_valores.create_tween().tween_property(_ficha_valores, "scale", Vector2.ONE, 0.3).set_trans(
			Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_refrescar_pastilla(true)
	_refrescar_columna()
	_disp_txt.text = "DISPONIBLE: %d/%d" % [Cartas.disponibles(), Cartas.LISTA.size()]


## Espera `s` segundos; false si mientras tanto se cerro la ficha (o la pantalla)
func _esperar(s: float, id: String) -> bool:
	await get_tree().create_timer(s).timeout
	if _cerrando or not is_inside_tree() or _ficha_id != id:
		_subiendo = false
		return false
	return true


## "¡NIVEL N!": sale de golpe encima del hexagono, sube y se va
func _nivel_texto(n: int, c: Vector2) -> void:
	var l := _texto("¡NIVEL %d!" % n, 46, Color8(255, 216, 64), _f, 11, Color8(130, 52, 8))
	var ancho := _f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x + 40.0
	l.size = Vector2(ancho, 64)
	l.position = c - l.size * 0.5
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2(0.3, 0.3)
	l.rotation = deg_to_rad(-6.0)
	_raiz.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2(1.2, 1.2), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2.ONE, 0.12)
	tw.tween_interval(0.55)
	tw.tween_property(l, "position:y", l.position.y - 60.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)


func _al_cambiar_cuenta() -> void:
	if _cerrando:
		return
	if _mejorando != "":
		var id := _mejorando
		_mejorando = ""
		if Cartas.nivel(id) > int(_mejora_antes.get("n", 0)):
			if _ficha_id == id:
				_celebrar_subida(id, int(_mejora_antes["n"]), int(_mejora_antes["c"]), int(_mejora_antes["p"]))
				return
		else:
			_avisar("No se pudo mejorar: vuelve a intentarlo")
	if _subiendo:
		return
	_refrescar()
	if _ficha_id != "":
		_construir_ficha()
		for c in _cartas_de(_ficha_id):
			(c as Carta).elegida = true


func _al_error_cuenta(msg: String) -> void:
	if _cerrando or _mejorando == "":
		return
	_mejorando = ""
	Audio.ui("atras", -8.0)
	_avisar("No se pudo mejorar: %s" % msg)
	if _ficha_id != "":
		_construir_ficha()


# ================================================================== el aviso
func _avisar(t: String) -> void:
	_aviso_txt.text = t
	var tam := _cabe(_fb, t, 24, 900.0, 14)
	_aviso_txt.add_theme_font_size_override("font_size", tam)
	var ancho := _fb.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x + 60.0
	_aviso.size = Vector2(ancho, 58)
	_aviso_txt.size = _aviso.size
	# debajo de la ficha si esta abierta (y cabe); si no, entre el panel de las activas y su barra
	var pos: Vector2
	if is_instance_valid(_ficha) and _ficha_id != "":
		var c := _ficha.position + Vector2(FICHA.x * 0.5, 0)
		var y := _ficha.position.y + _ficha.size.y + 14.0
		if y + 58.0 > ALTO - 6.0:
			y = _ficha.position.y - 72.0
		pos = Vector2(c.x - ancho * 0.5, y)
	else:
		var r := _rect_en_raiz(_panel_izq)
		pos = Vector2(r.get_center().x - ancho * 0.5, r.end.y + 16.0 * _izq.scale.y)
	pos.x = clampf(pos.x, 10.0, _w - ancho - 10.0)
	_aviso.position = pos
	_aviso.queue_redraw()
	_aviso_t = 2.4
	_aviso.modulate.a = 1.0
	_aviso.pivot_offset = _aviso.size * 0.5
	_aviso.scale = Vector2(0.85, 0.85)
	_aviso.create_tween().tween_property(_aviso, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ================================================================== el reloj
func _process(dt: float) -> void:
	_t += dt
	if _aviso_t > 0.0:
		_aviso_t -= dt
		_aviso.modulate.a = clampf(_aviso_t / 0.35, 0.0, 1.0)
	if _mejorando != "":
		_mejora_t += dt
		if _mejora_t > 15.0:
			_mejorando = ""
			_avisar("El servidor no contesta: vuelve a intentarlo")
			if _ficha_id != "":
				_construir_ficha()
	# la rejilla: la rueda va a su sitio con suavidad; soltada, sigue con la inercia y se va frenando
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
	# EL MODO CAMBIO: las activas se menean (cada una a su ritmo)
	if _cambio != "":
		for i in _ranuras.size():
			var r: Control = _ranuras[i]
			if (r as Carta).id != "":
				r.rotation = sin(_t * 13.0 + i * 1.7) * 0.022
	# los globos de las categorias laten
	var kg := 1.0 + 0.08 * maxf(0.0, sin(_t * 4.0))
	for e in _cat_items:
		var g: Control = e["globo"]
		if g.visible:
			g.scale = Vector2(kg, kg)


# ================================================================== --cartasfoto=<carpeta>
## Las fotos de la pantalla (las pide lobby.gd con --cartasfoto), con cartas de prueba en memoria y sin cuenta: la
## pantalla, cada categoria, la ficha (de una del set y de una activa), una subida de nivel en tira de fotogramas,
## equipar, una que no tienes, el modo cambio y el cambio hecho, el aviso de que faltan copias, una al maximo, y la carta que
## sale de un cofre (tira de fotogramas y el premio: nueva y repetida). Se usan las funciones de verdad (guardan), asi que
## settings.cfg y cuenta.cfg se copian al empezar y se devuelven como estaban al acabar.
func fotos(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var copias: Array = []
	for ruta in [Settings.PATH, Cuenta.ARCHIVO]:
		var absoluta := ProjectSettings.globalize_path(ruta)
		if FileAccess.file_exists(absoluta):
			DirAccess.copy_absolute(absoluta, absoluta + ".cartasfoto")
			copias.append(absoluta)
	Cuenta.url = ""
	Cuenta.token = ""
	Cuenta.perfil = {}
	var tiras: Array = []
	var foto := func(nombre: String) -> void:
		await RenderingServer.frame_post_draw
		var ruta := dir.path_join(nombre)
		get_viewport().get_texture().get_image().save_png(ruta)
		print("[cartasfoto] %s" % ruta)
	Settings.monedas = 465
	Settings.cubos = 120
	Settings.cartas = {
		"dano": {"n": 1, "c": 5}, "municion": {"n": 1, "c": 0}, "enfriamiento": {"n": 1, "c": 0},
		"vida": {"n": 1, "c": 5}, "velocidad": {"n": 1, "c": 5}, "destruccion": {"n": 1, "c": 0},
		"regeneracion": {"n": 1, "c": 5}, "explosion": {"n": 1, "c": 4},
		"vampiro": {"n": 3, "c": 2}, "rescatista": {"n": 1, "c": 1}, "definitiva": {"n": 5, "c": 0},
		"blindaje": {"n": 2, "c": 1}, "piel_dura": {"n": 1, "c": 0}}
	Settings.cartas_equipadas = ["dano", "municion", "enfriamiento", "vida", "velocidad", "destruccion", "regeneracion"]
	Settings.cartas_vistas = ["dano", "municion", "enfriamiento", "vida", "velocidad", "destruccion", "regeneracion"]
	Cartas.refrescar()
	_refrescar()
	await get_tree().create_timer(1.2).timeout
	await foto.call("cartas_a_pantalla.png")
	# cada categoria
	for cat in Cartas.CATEGORIAS:
		_elegir_categoria(String(cat["id"]))
		await get_tree().create_timer(0.8).timeout
		await foto.call("cartas_b_cat_%s.png" % String(cat["id"]))
	_elegir_categoria("todo")
	await get_tree().create_timer(0.8).timeout
	# la ficha de una del set (la nueva)
	_abrir_ficha("explosion", _carta_de_set("explosion"))
	await get_tree().create_timer(0.7).timeout
	await foto.call("cartas_c_ficha_set.png")
	_cerrar_ficha()
	# la ficha de una activa lista para mejorar, y la SUBIDA en tira
	_abrir_ficha("velocidad", _carta_de("velocidad"))
	await get_tree().create_timer(0.7).timeout
	await foto.call("cartas_d_ficha_activa.png")
	_pulsar_mejorar()
	for i in 22:
		await get_tree().create_timer(0.055).timeout
		await RenderingServer.frame_post_draw
		tiras.append(["cartas_e_subida_%02d.png" % i, get_viewport().get_texture().get_image()])
	await get_tree().create_timer(0.8).timeout
	await foto.call("cartas_f_subida_fin.png")
	# MEJORA sin copias: el aviso
	_cerrar_ficha()
	_abrir_ficha("municion", _carta_de("municion"))
	await get_tree().create_timer(0.5).timeout
	_pulsar_mejorar()
	await get_tree().create_timer(0.3).timeout
	await foto.call("cartas_g_faltan_copias.png")
	_cerrar_ficha()
	# una que no tienes
	_abrir_ficha("salto", _carta_de_set("salto"))
	await get_tree().create_timer(0.6).timeout
	await foto.call("cartas_h_bloqueada.png")
	_cerrar_ficha()
	# EQUIPAR la nueva: entra en la ranura libre
	_abrir_ficha("explosion", _carta_de_set("explosion"))
	await get_tree().create_timer(0.5).timeout
	_pulsar_equipar()
	await get_tree().create_timer(0.12).timeout
	await foto.call("cartas_i_equipar.png")
	await get_tree().create_timer(0.8).timeout
	await foto.call("cartas_j_ocho.png")
	# EL MODO CAMBIO: sale la de salto (en memoria) y con las 8 llenas, EQUIPAR pide cual sale
	Settings.cartas["salto"] = {"n": 1, "c": 1}
	Cartas.refrescar()
	_refrescar()
	await get_tree().create_timer(0.4).timeout
	_abrir_ficha("salto", _carta_de_set("salto"))
	await get_tree().create_timer(0.5).timeout
	await foto.call("cartas_k_ficha_salto.png")
	_pulsar_equipar()
	await get_tree().create_timer(0.7).timeout
	await foto.call("cartas_l_modo_cambio.png")
	_tocar_ranura(1)
	await get_tree().create_timer(0.2).timeout
	await foto.call("cartas_m_cambiando.png")
	await get_tree().create_timer(0.9).timeout
	await foto.call("cartas_n_cambiada.png")
	# una al maximo
	Settings.cartas["dano"] = {"n": Cartas.NIVEL_MAX, "c": 0}
	Cartas.refrescar()
	_refrescar()
	_abrir_ficha("dano", _carta_de("dano"))
	await get_tree().create_timer(0.6).timeout
	await foto.call("cartas_o_maximo.png")
	_cerrar_ficha()
	await get_tree().create_timer(0.3).timeout
	# EL COFRE: una carta nueva y una repetida (resultados hechos: no se abre ni se guarda nada)
	var cf = null
	if is_instance_valid(lobby) and lobby.has_method("_abrir_cofres"):
		cf = lobby._abrir_cofres([
			{"inicio": 1, "etapas": [1, 2, 3, 3], "rareza": 3, "premio": {"t": "carta", "v": "explosion", "n": 6, "nueva": true}},
			{"inicio": 0, "etapas": [0, 0, 0, 0], "rareza": 0, "premio": {"t": "carta", "v": "vida", "n": 2, "nueva": false}}])
	if cf != null:
		await get_tree().create_timer(1.8).timeout
		for i in 4:
			cf._tocar()
			await get_tree().create_timer(0.85).timeout
		for i in 16:
			await get_tree().create_timer(0.07).timeout
			await RenderingServer.frame_post_draw
			tiras.append(["cartas_p_cofre_%02d.png" % i, get_viewport().get_texture().get_image()])
		await get_tree().create_timer(1.8).timeout
		await foto.call("cartas_q_cofre_nueva.png")
		cf._siguiente_cofre()
		await get_tree().create_timer(1.3).timeout
		cf._saltar()
		await get_tree().create_timer(2.4).timeout
		await foto.call("cartas_r_cofre_repetida.png")
	for f in tiras:
		(f[1] as Image).save_png(dir.path_join(String(f[0])))
	print("[cartasfoto] %d fotos de tira en %s" % [tiras.size(), dir])
	for absoluta in copias:
		DirAccess.copy_absolute(String(absoluta) + ".cartasfoto", String(absoluta))
		DirAccess.remove_absolute(String(absoluta) + ".cartasfoto")
	print("[cartasfoto] ajustes y cuenta devueltos como estaban")
	get_tree().quit()


func _carta_de_set(id: String) -> Control:
	for e in _cartas_set:
		if String(e["id"]) == id:
			return e["carta"]
	return _carta_de(id)


# ================================================================== el lienzo de todo
## Un Control que se pinta con una funcion (`pintar(self)`); `animado` lo repinta cada fotograma
class _Dibujo extends Control:
	var pintar: Callable
	var animado := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_dt: float) -> void:
		if animado:
			queue_redraw()

	func _draw() -> void:
		if pintar.is_valid():
			pintar.call(self)


## LAS CHISPAS: particulas 2D (estelas y estrellas) y aros de onda, para subir de nivel y equipar
class _Chispas extends Control:
	var ps: Array = []
	var aros: Array = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func chispas(c: Vector2, col: Color, n: int, vel: float, tam: float) -> void:
		for i in n:
			var a := randf() * TAU
			var v := Vector2(cos(a), sin(a)) * vel * randf_range(0.3, 1.0)
			ps.append({"k": 0, "p": c + v * 0.02, "v": v, "t": randf_range(0.4, 0.8), "d": 0.8, "s": tam * randf_range(0.6, 1.2),
				"c": col.lerp(Color.WHITE, randf() * 0.4), "r": 0.0, "w": 0.0, "g": 700.0, "a": 2.6})

	func estrellas(c: Vector2, col: Color, n: int, radio: float) -> void:
		for i in n:
			var a := randf() * TAU
			var v := Vector2(cos(a), sin(a)) * radio * randf_range(0.4, 1.3)
			ps.append({"k": 1, "p": c, "v": v, "t": randf_range(0.5, 0.95), "d": 0.95, "s": randf_range(9.0, 18.0),
				"c": col, "r": randf() * TAU, "w": randf_range(-3.0, 3.0), "g": 0.0, "a": 3.0})

	func aro(c: Vector2, r0: float, r1: float, dur: float, col: Color, ancho: float) -> void:
		aros.append({"p": c, "r0": r0, "r1": r1, "t": dur, "d": dur, "c": col, "w": ancho})

	func _process(dt: float) -> void:
		dt = minf(dt, 1.0 / 20.0)
		var vivas: Array = []
		for p in ps:
			p["t"] -= dt
			if p["t"] <= 0.0:
				continue
			var v: Vector2 = p["v"]
			v.y += float(p["g"]) * dt
			v *= exp(-float(p["a"]) * dt)
			p["v"] = v
			p["p"] = (p["p"] as Vector2) + v * dt
			p["r"] = float(p["r"]) + float(p["w"]) * dt
			vivas.append(p)
		ps = vivas
		var quedan: Array = []
		for a in aros:
			a["t"] -= dt
			if a["t"] > 0.0:
				quedan.append(a)
		aros = quedan
		if not ps.is_empty() or not aros.is_empty():
			queue_redraw()
		elif get_meta("pintado", false):
			set_meta("pintado", false)
			queue_redraw()

	func _draw() -> void:
		set_meta("pintado", true)
		for a in aros:
			var q := 1.0 - float(a["t"]) / float(a["d"])
			var e := 1.0 - pow(1.0 - q, 3.0)
			var col: Color = a["c"]
			draw_arc(a["p"], lerpf(float(a["r0"]), float(a["r1"]), e), 0.0, TAU, 64, Color(col, col.a * (1.0 - q)),
				maxf(1.0, float(a["w"]) * (1.0 - q * 0.7)), true)
		for p in ps:
			var k := clampf(float(p["t"]) / float(p["d"]), 0.0, 1.0)
			var pos: Vector2 = p["p"]
			var col: Color = p["c"]
			var s := float(p["s"])
			if int(p["k"]) == 0:
				var v: Vector2 = p["v"]
				draw_line(pos, pos - v * 0.035, Color(col, col.a * k), s * (0.35 + 0.65 * k), true)
				draw_circle(pos, s * 0.5 * k, Color(1, 1, 1, 0.8 * k))
			else:
				var tw := s * k * (0.7 + 0.3 * sin(float(p["r"]) * 4.0))
				if tw < 1.5:
					continue
				var est := PackedVector2Array()
				for i in 8:
					var a := float(p["r"]) + i * TAU / 8.0
					est.append(pos + Vector2(cos(a), sin(a)) * (tw if i % 2 == 0 else tw * 0.24))
				draw_colored_polygon(est, Color(col, k))


# ================================================================== LA CARTA
## UNA CARTA, dibujada a mano como las de la foto: el marco con las esquinas cortadas (claro, una raya oscura y el cuerpo
## morado en degradado), un brillo en diagonal, las flechas de subir tenues, la esquina clara con el dibujo de su
## categoria, el hexagono brillante con su dibujo (icono_lobby.gd), el nombre en blanco y cursiva con su contorno, y abajo
## el nivel y la barra de copias ("5/2"). Con copias para mejorar, la mitad de abajo se enciende en naranja, las flechas se
## doran, la barra se pone amarilla y sale la flecha que sube y baja. Sin la carta, en gris, con candado y "0/1".
## Todo va a escala (`k` = lo que mide / 172): a cualquier tamaño sale nitida.
##   modo  "carta" (la de `id`), "vacia" (una ranura libre), "hueco" (el relleno lavanda del set) o "reverso" (el dorso)
class Carta extends Control:
	const _Icono := preload("res://scripts/icono_lobby.gd")
	const BASE := Vector2(172, 236)
	## los colores, medidos en la foto
	const CUERPO_ARRIBA := Color8(128, 112, 202)
	const CUERPO_ABAJO := Color8(100, 86, 163)
	const GRIS_ARRIBA := Color8(112, 108, 146)
	const GRIS_ABAJO := Color8(84, 80, 114)
	const MARCO := Color8(187, 176, 252)
	const MARCO_SET := Color8(112, 142, 218)
	const FILO := Color8(89, 79, 142)
	const NIVEL := Color8(129, 101, 211)
	const NIVEL_LISTA := Color8(198, 106, 28)
	const BARRA := Color8(56, 42, 101)
	const AMARILLO := Color8(247, 196, 48)
	const NARANJA := Color8(238, 148, 46)
	const CINTA := Color8(214, 28, 64)
	const ELEGIDA := Color8(250, 240, 85)
	static var _letra: SystemFont = null

	var id := ""
	var modo := "carta"
	var en_set := false              ## en el set: el marco azul, el NUEVO y la marca de equipada
	var elegida := false:            ## la de la ficha abierta: el marco amarillo
		set(v):
			elegida = v
			_repintar()
	var resalte := false:            ## el modo cambio: late en amarillo
		set(v):
			resalte = v
			_repintar()
	var destello := 0.0:             ## el fogonazo blanco al subir de nivel (0..1)
		set(v):
			destello = v
			if _encima != null:
				_encima.queue_redraw()
	var nivel_ver := -1:             ## el numero que enseña (-1: el de verdad); lo cambia la animacion de subir
		set(v):
			nivel_ver = v
			queue_redraw()
	var fraccion_ver := -1.0:        ## lo lleno de la barra (-1: el de verdad)
		set(v):
			fraccion_ver = v
			queue_redraw()
			if _encima != null:
				_encima.queue_redraw()
	# lo que se sabe de ella (lo pone refrescar)
	var _mia := false
	var _nivel := 0
	var _copias := 0
	var _necesita := 1
	var _listas := false
	var _nueva := false
	var _equipada := false
	var _t := 0.0
	var _hex: Control = null
	var _glifo: Control = null
	var _encima: Control = null
	var _clave := ""
	var _flechas: Array = []
	var _lineas := PackedStringArray()
	var _tam_nombre := 24

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = BASE
		_t = randf() * 10.0

	func _ready() -> void:
		_glifo = _Icono.new()
		add_child(_glifo)
		_hex = _Icono.new()
		add_child(_hex)
		_encima = Control.new()
		_encima.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_encima)
		_encima.draw.connect(_pintar_encima)
		resized.connect(_colocar)
		refrescar()

	static func letra() -> SystemFont:
		if _letra == null:
			_letra = SystemFont.new()
			_letra.font_names = PackedStringArray(["Segoe UI", "Roboto", "Arial", "sans-serif"])
			_letra.font_weight = 900
			_letra.font_italic = true
		return _letra

	## El dibujo de una categoria ("carta_vida"...)
	static func icono_categoria(cat: String) -> String:
		for c in Cartas.CATEGORIAS:
			if String(c["id"]) == cat:
				return String(c["icono"])
		return "carta_todo"

	## Un rectangulo con las cuatro esquinas cortadas `c`
	static func forma(r: Rect2, c: float) -> PackedVector2Array:
		var x0 := r.position.x
		var y0 := r.position.y
		var x1 := r.end.x
		var y1 := r.end.y
		return PackedVector2Array([Vector2(x0 + c, y0), Vector2(x1 - c, y0), Vector2(x1, y0 + c), Vector2(x1, y1 - c),
			Vector2(x1 - c, y1), Vector2(x0 + c, y1), Vector2(x0, y1 - c), Vector2(x0, y0 + c)])

	static func cerrar(p: PackedVector2Array) -> PackedVector2Array:
		var b := p.duplicate()
		b.append(p[0])
		return b

	## Las dos cartitas de las copias, centradas en `c` (a escala `k`)
	static func copitas(ci: CanvasItem, c: Vector2, k: float, col: Color) -> void:
		var borde := Color(0.1, 0.05, 0.25, 0.55 * col.a)
		var atras := _girado(c + Vector2(3.0, -1.0) * k, Vector2(10, 13) * k, 0.28)
		ci.draw_colored_polygon(atras, Color(col.darkened(0.15), col.a * 0.92))
		ci.draw_polyline(cerrar(atras), borde, 1.2 * k, true)
		var frente := _girado(c + Vector2(-2.0, 1.0) * k, Vector2(10, 13) * k, -0.14)
		ci.draw_colored_polygon(frente, col)
		ci.draw_polyline(cerrar(frente), borde, 1.2 * k, true)

	static func _girado(c: Vector2, tam: Vector2, a: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		for q in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			out.append(c + ((q as Vector2) * tam * 0.5).rotated(a))
		return out

	## Un texto en lineas de `ancho` como mucho; vacio si una palabra sola no cabe
	static func partir(texto: String, fuente: Font, tam: int, ancho: float) -> PackedStringArray:
		var out := PackedStringArray()
		var linea := ""
		for p in texto.split(" ", false):
			var prueba: String = p if linea == "" else linea + " " + p
			if fuente.get_string_size(prueba, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x <= ancho:
				linea = prueba
				continue
			if linea == "":
				return PackedStringArray()
			out.append(linea)
			linea = p
			if fuente.get_string_size(linea, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x > ancho:
				return PackedStringArray()
		if linea != "":
			out.append(linea)
		return out

	func _repintar() -> void:
		queue_redraw()
		if _encima != null:
			_encima.queue_redraw()

	func _colocar() -> void:
		if _hex == null:
			return
		var k := size.x / BASE.x
		_encima.size = size
		_hex.position = Vector2(32, 21 if modo != "reverso" else 64) * k
		_hex.size = Vector2(108, 108) * k
		_glifo.position = Vector2(7, 6) * k
		_glifo.size = Vector2(28, 28) * k
		_clave = ""
		_repintar()

	## Lee de Cartas lo que tiene que enseñar (se llama al cambiar algo)
	func refrescar() -> void:
		var d: Dictionary = Cartas.datos(id) if modo == "carta" else {}
		_mia = not d.is_empty() and Cartas.tiene(id)
		_nivel = Cartas.nivel(id) if _mia else 0
		_copias = Cartas.copias(id) if _mia else 0
		_necesita = Cartas.copias_para(id) if _mia else 1
		_listas = _mia and Cartas.copias_listas(id)
		_nueva = _mia and Cartas.nueva(id)
		_equipada = _mia and Cartas.equipada(id)
		_clave = ""
		if _hex != null:
			_hex.visible = not d.is_empty() or modo == "reverso"
			_glifo.visible = not d.is_empty()
			if modo == "reverso":
				_hex.set("icono", "carta_todo")
				_hex.set("color", Color8(150, 118, 250))
			elif not d.is_empty():
				_hex.set("icono", String(d["icono"]))
				_hex.set("color", (d["color"] as Color) if _mia else Color(0.62, 0.61, 0.72))
				_glifo.set("icono", "glifo_" + icono_categoria(String(d["cat"])).trim_prefix("carta_"))
				_glifo.set("color", Color(1, 1, 1, 0.92 if _mia else 0.6))
			_hex.modulate.a = 1.0 if (_mia or modo == "reverso") else 0.8
			_colocar()
		_repintar()

	func _process(dt: float) -> void:
		_t += dt
		if _encima != null and modo == "carta" and (resalte or elegida or (_listas and nivel_ver < 0) or (en_set and _nueva)):
			_encima.queue_redraw()

	## Lo que depende del tamaño y del nombre (las flechas recortadas y las lineas del nombre): se calcula una vez
	func _calcular() -> void:
		var clave := "%s|%s|%s" % [id, str(size), modo]
		if clave == _clave:
			return
		_clave = clave
		var k := size.x / BASE.x
		var cuerpo := forma(Rect2(Vector2(4, 4) * k, size - Vector2(8, 8) * k), 5.0 * k)
		_flechas.clear()
		var filas := 4 if modo == "carta" else 6
		var y_ini := 0.34 if modo == "carta" else 0.05
		for r in filas:
			var cy := size.y * (y_ini + r * 0.19)
			for c in 5:
				var cx := size.x * (-0.04 + c * 0.27 + (0.135 if r % 2 == 1 else 0.0))
				var f := PackedVector2Array([Vector2(cx - 19 * k, cy), Vector2(cx, cy - 17 * k), Vector2(cx + 19 * k, cy),
					Vector2(cx + 7.5 * k, cy), Vector2(cx + 7.5 * k, cy + 16 * k), Vector2(cx - 7.5 * k, cy + 16 * k),
					Vector2(cx - 7.5 * k, cy)])
				for p in Geometry2D.intersect_polygons(f, cuerpo):
					_flechas.append([p, cy / size.y])
		# el nombre: lo mas grande que quepa en dos lineas (o en tres, algo mas pequeño)
		var nombre := String(Cartas.datos(id).get("nombre", ""))
		var ancho := size.x - 16.0 * k
		_lineas = PackedStringArray()
		for tam in [27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17]:
			var l := partir(nombre, letra(), int(round(tam * k)), ancho)
			if l.size() > 0 and l.size() <= 2:
				_lineas = l
				_tam_nombre = int(round(tam * k))
				return
		for tam in [21, 20, 19, 18, 17, 16, 15, 14, 13]:
			var l := partir(nombre, letra(), int(round(tam * k)), ancho)
			if l.size() > 0 and l.size() <= 3:
				_lineas = l
				_tam_nombre = int(round(tam * k))
				return

	func _draw() -> void:
		var k := size.x / BASE.x
		var todo := Rect2(Vector2.ZERO, size)
		if modo == "vacia":
			var f := forma(todo, 8.0 * k)
			draw_colored_polygon(f, Color(0.32, 0.27, 0.64, 0.2))
			draw_polyline(cerrar(f), Color(1, 1, 1, 0.3), 2.0 * k, true)
			var c := size * 0.5
			draw_rect(Rect2(c - Vector2(14, 3) * k, Vector2(28, 6) * k), Color(1, 1, 1, 0.3))
			draw_rect(Rect2(c - Vector2(3, 14) * k, Vector2(6, 28) * k), Color(1, 1, 1, 0.3))
			return
		if modo == "hueco":
			var f := forma(todo, 8.0 * k)
			draw_colored_polygon(f, Color(0.8, 0.8, 1.0, 0.6))
			draw_polyline(cerrar(f), Color(0.88, 0.88, 1.0, 1.0), 2.0 * k, true)
			return
		if modo == "carta" and Cartas.datos(id).is_empty():
			return
		_calcular()
		var reverso := modo == "reverso"
		var gris := not _mia and not reverso
		var lista := _listas if fraccion_ver < 0.0 else fraccion_ver >= 0.999
		# EL MARCO: claro por fuera, una raya oscura y el cuerpo en degradado
		var marco := MARCO_SET if en_set else MARCO
		if gris:
			marco = Color8(150, 146, 184)
		draw_colored_polygon(forma(todo, 8.0 * k), marco)
		draw_colored_polygon(forma(todo.grow(-2.2 * k), 6.8 * k), marco.darkened(0.2))
		draw_colored_polygon(forma(todo.grow(-3.0 * k), 6.2 * k), FILO)
		var cuerpo := forma(todo.grow(-4.0 * k), 5.0 * k)
		var arriba := GRIS_ARRIBA if gris else CUERPO_ARRIBA
		var abajo := GRIS_ABAJO if gris else CUERPO_ABAJO
		if reverso:
			arriba = Color8(118, 92, 222)
			abajo = Color8(72, 54, 156)
		var cols := PackedColorArray()
		for p in cuerpo:
			cols.append(arriba.lerp(abajo, clampf(p.y / size.y, 0.0, 1.0)))
		draw_polygon(cuerpo, cols)
		# el brillo en diagonal, de arriba a la derecha
		var brillo := PackedVector2Array([Vector2(size.x * 0.52, 0), Vector2(size.x * 0.84, 0),
			Vector2(size.x * 0.08, size.y * 0.6), Vector2(-size.x * 0.24, size.y * 0.6)])
		for p in Geometry2D.intersect_polygons(brillo, cuerpo):
			draw_colored_polygon(p, Color(1, 1, 1, 0.045))
		# LISTA PARA MEJORAR: la mitad de abajo en naranja (en dos tramos: que suba suave)
		if lista:
			var y0 := size.y * 0.36
			var ym := size.y * 0.64
			for tramo in [[y0, ym, 0.0, 0.5], [ym, size.y, 0.5, 0.95]]:
				var a0: float = tramo[0]
				var a1: float = tramo[1]
				var zona := PackedVector2Array([Vector2(0, a0), Vector2(size.x, a0), Vector2(size.x, a1), Vector2(0, a1)])
				for p in Geometry2D.intersect_polygons(zona, cuerpo):
					var cc := PackedColorArray()
					for q in p:
						var f := clampf((q.y - a0) / maxf(1.0, a1 - a0), 0.0, 1.0)
						cc.append(Color(NARANJA, lerpf(float(tramo[2]), float(tramo[3]), f)))
					draw_polygon(p, cc)
		# las flechas de subir: tenues, o doradas si esta lista
		for fl in _flechas:
			var fy: float = fl[1]
			var col := Color.WHITE
			var a := 0.06 * clampf((fy - 0.26) / 0.4, 0.0, 1.0)
			if reverso:
				a = 0.07
			elif lista:
				col = Color8(255, 216, 128)
				a = 0.16 + 0.3 * clampf((fy - 0.34) / 0.5, 0.0, 1.0)
			draw_colored_polygon(fl[0], Color(col, a))
		if reverso:
			return
		# LA ESQUINA: un triangulo claro con el dibujo de la categoria (el dibujo es un hijo: va encima)
		var esquina := PackedVector2Array([Vector2(0, 0), Vector2(size.x * 0.5, 0), Vector2(0, size.y * 0.19)])
		for p in Geometry2D.intersect_polygons(esquina, cuerpo):
			var cc := PackedColorArray()
			for q in p:
				var f := clampf(q.x / (size.x * 0.5) + q.y / (size.y * 0.19), 0.0, 1.0)
				cc.append(Color(0.56, 0.64, 0.82, 0.45 if not gris else 0.3).lerp(
					Color(0.8, 0.86, 0.96, 0.82 if not gris else 0.5), f))
			draw_polygon(p, cc)
		draw_line(Vector2(size.x * 0.5 - 6.0 * k, 4.0 * k), Vector2(4.0 * k, size.y * 0.19 - 3.0 * k), Color(1, 1, 1, 0.3),
			1.5 * k, true)
		# EL NOMBRE, en blanco con su contorno
		var n := _lineas.size()
		var tam := _tam_nombre
		var lh := tam * 1.02
		var yc := (166.0 if n <= 2 else 160.0) * k
		var cap := tam * 0.72
		var blanco := Color.WHITE if _mia else Color8(218, 214, 236)
		for i in n:
			var base := yc - n * lh * 0.5 + i * lh + (lh + cap) * 0.5
			var pos := Vector2(8.0 * k, base)
			var ancho := size.x - 16.0 * k
			draw_string_outline(letra(), pos + Vector2(0, 2.5 * k), _lineas[i], HORIZONTAL_ALIGNMENT_CENTER, ancho, tam,
				int(round(7.0 * k)), Color(0.12, 0.05, 0.3, 0.5))
			draw_string_outline(letra(), pos, _lineas[i], HORIZONTAL_ALIGNMENT_CENTER, ancho, tam, int(round(5.5 * k)),
				Color(0.22, 0.12, 0.42, 0.95))
			draw_string(letra(), pos, _lineas[i], HORIZONTAL_ALIGNMENT_CENTER, ancho, tam, blanco)
		# LA BARRA DE ABAJO: el nivel en su cuadro y las copias
		var by := size.y - 33.0 * k
		var bh := 26.0 * k
		var x0 := 5.0 * k
		var xs := 37.0 * k
		var x1 := size.x - 5.0 * k
		var frac := fraccion_ver if fraccion_ver >= 0.0 else (1.0 if _listas else 0.0)
		var cuadro := NIVEL_LISTA if lista else (NIVEL if _mia else Color8(74, 70, 102))
		draw_rect(Rect2(x0, by, xs - x0, bh), cuadro)
		draw_rect(Rect2(x0, by, xs - x0, 2.5 * k), cuadro.lightened(0.25))
		draw_rect(Rect2(xs, by, x1 - xs, bh), BARRA if _mia else Color8(54, 50, 78))
		if frac > 0.0:
			var xf := xs + (x1 - xs) * clampf(frac, 0.0, 1.0)
			draw_rect(Rect2(xs, by, xf - xs, bh), AMARILLO)
			draw_rect(Rect2(xs, by, xf - xs, 3.0 * k), Color8(255, 228, 130))
			draw_rect(Rect2(xs, by + bh - 3.0 * k, xf - xs, 3.0 * k), Color8(224, 158, 24))
		var tn := int(round(21.0 * k))
		if _mia:
			var t_n := str(nivel_ver if nivel_ver >= 0 else _nivel)
			var ancho_n := letra().get_string_size(t_n, HORIZONTAL_ALIGNMENT_LEFT, -1, tn).x
			draw_string(letra(), Vector2((x0 + xs) * 0.5 - ancho_n * 0.5 - 1.0 * k, by + bh * 0.5 + tn * 0.36), t_n,
				HORIZONTAL_ALIGNMENT_LEFT, -1, tn, Color.WHITE)
		else:
			# el candado pequeño
			var c := Vector2((x0 + xs) * 0.5, by + bh * 0.5 + 1.5 * k)
			draw_arc(c + Vector2(0, -3) * k, 4.2 * k, PI, TAU, 10, Color(1, 1, 1, 0.85), 2.2 * k, true)
			draw_rect(Rect2(c + Vector2(-6, -3) * k, Vector2(12, 9) * k), Color(1, 1, 1, 0.85))
		var txt := ("MÁX." if _nivel >= Cartas.NIVEL_MAX else "%d/%d" % [_copias, _necesita]) if _mia else "0/1"
		var tt := int(round(19.0 * k))
		var tw := letra().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tt).x
		var iw := 17.0 * k
		var cx0 := (xs + x1) * 0.5 - (iw + 4.0 * k + tw) * 0.5
		copitas(self, Vector2(cx0 + iw * 0.5, by + bh * 0.5), k, Color(1, 1, 1, 1.0 if _mia else 0.7))
		var pt := Vector2(cx0 + iw + 4.0 * k, by + bh * 0.5 + tt * 0.36)
		if frac >= 0.999:
			draw_string_outline(letra(), pt, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tt, int(round(5.0 * k)), Color8(168, 88, 12))
		draw_string(letra(), pt, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tt, Color(1, 1, 1, 1.0 if _mia else 0.75))

	## Lo que va encima del hexagono y del dibujo: la flecha de mejorar, el candado, la cinta de NUEVO, la marca de
	## equipada, el fogonazo y los marcos amarillos
	func _pintar_encima() -> void:
		var ci := _encima
		var k := size.x / BASE.x
		var todo := Rect2(Vector2.ZERO, size)
		if modo == "carta" and not Cartas.datos(id).is_empty():
			var lista := _listas if fraccion_ver < 0.0 else fraccion_ver >= 0.999
			if lista and nivel_ver < 0 and _mia and _nivel < Cartas.NIVEL_MAX:
				var c := Vector2(size.x - 19.0 * k, size.y - 38.0 * k - absf(sin(_t * 3.2)) * 3.0 * k)
				var fl := PackedVector2Array([c + Vector2(-12, 0) * k, c + Vector2(0, -13) * k, c + Vector2(12, 0) * k,
					c + Vector2(5.5, 0) * k, c + Vector2(5.5, 13) * k, c + Vector2(-5.5, 13) * k, c + Vector2(-5.5, 0) * k])
				ci.draw_colored_polygon(fl, Color8(255, 216, 100))
				ci.draw_polyline(cerrar(fl), Color8(222, 118, 18), 2.6 * k, true)
			if not _mia:
				# el candado, encima del hexagono
				var c := Vector2(86, 80) * k
				ci.draw_circle(c, 22.0 * k, Color(0.1, 0.08, 0.2, 0.7))
				ci.draw_arc(c + Vector2(0, -4) * k, 7.5 * k, PI, TAU, 16, Color.WHITE, 3.6 * k, true)
				ci.draw_line(c + Vector2(-7.5, -4.5) * k, c + Vector2(-7.5, 1) * k, Color.WHITE, 3.6 * k)
				ci.draw_line(c + Vector2(7.5, -4.5) * k, c + Vector2(7.5, 1) * k, Color.WHITE, 3.6 * k)
				ci.draw_rect(Rect2(c + Vector2(-11, 0) * k, Vector2(22, 15) * k), Color.WHITE)
				ci.draw_circle(c + Vector2(0, 6) * k, 2.6 * k, Color8(60, 52, 96))
			if en_set and _nueva:
				# LA CINTA ROJA DE NUEVO, con un brillo que la cruza de vez en cuando
				var x0 := size.x * 0.46
				var cinta := PackedVector2Array([Vector2(x0, -3 * k), Vector2(size.x + 3 * k, -3 * k),
					Vector2(size.x + 3 * k, 21 * k), Vector2(x0 - 9 * k, 21 * k)])
				ci.draw_colored_polygon(cinta, CINTA)
				var q := fmod(_t, 2.6) / 0.7
				if q <= 1.0:
					var x := lerpf(x0 - 30.0 * k, size.x + 20.0 * k, q)
					var raya := PackedVector2Array([Vector2(x, -3 * k), Vector2(x + 12 * k, -3 * k), Vector2(x + 4 * k, 21 * k),
						Vector2(x - 8 * k, 21 * k)])
					for p in Geometry2D.intersect_polygons(raya, cinta):
						ci.draw_colored_polygon(p, Color(1, 1, 1, 0.35))
				ci.draw_polyline(cerrar(cinta), Color8(255, 150, 170), 1.4 * k, true)
				var tt := int(round(16.0 * k))
				ci.draw_string(letra(), Vector2(x0 - 4.0 * k, 15.5 * k), "NUEVO", HORIZONTAL_ALIGNMENT_CENTER,
					size.x - x0 + 6.0 * k, tt, Color.WHITE)
			if en_set and _equipada:
				# la marca de equipada: el circulo verde con la palomita
				var c := Vector2(size.x - 17.0 * k, (44.0 if _nueva else 18.0) * k)
				ci.draw_circle(c + Vector2(0, 1.5) * k, 13.0 * k, Color(0.1, 0.05, 0.25, 0.35))
				ci.draw_circle(c, 13.0 * k, Color.WHITE)
				ci.draw_circle(c, 10.5 * k, Color8(58, 184, 92))
				ci.draw_polyline(PackedVector2Array([c + Vector2(-5, 0) * k, c + Vector2(-1.5, 4) * k, c + Vector2(5.5, -4) * k]),
					Color.WHITE, 3.0 * k, true)
		if destello > 0.001:
			ci.draw_colored_polygon(forma(todo, 8.0 * k), Color(1, 1, 1, destello * 0.85))
		if elegida and modo == "carta":
			var f := cerrar(forma(todo.grow(-1.0 * k), 7.5 * k))
			ci.draw_polyline(f, Color(ELEGIDA, 0.3 + 0.1 * sin(_t * 5.0)), 9.0 * k, true)
			ci.draw_polyline(f, ELEGIDA, 4.0 * k, true)
		elif resalte and modo == "carta":
			var a := 0.5 + 0.5 * sin(_t * 6.5)
			var f := cerrar(forma(todo.grow(1.0 * k), 9.0 * k))
			ci.draw_polyline(f, Color(ELEGIDA, 0.2 + 0.3 * a), 11.0 * k, true)
			ci.draw_polyline(f, Color(ELEGIDA, 0.7 + 0.3 * a), 3.5 * k, true)
