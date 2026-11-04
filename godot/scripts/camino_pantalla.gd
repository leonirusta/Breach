extends CanvasLayer
## EL CAMINO DEL PROGRESO, LA PANTALLA (2026-10-04, pedido con dos capturas: la pista de niveles y la ficha que sale al
## tocar una carta). Los datos y las reglas son de camino_progreso.gd (CaminoProgreso): aqui solo se ENSEÑA (lo alcanzado
## se da solo, sin reclamar: lo hace el vestibulo).
##
##   arriba      la ESTRELLA con tu nivel ("Tu nivel") y debajo CUENTA (en linea con tu nombre / SIN CONEXION: abre
##               lobby.abrir_cuenta, lo que antes abria la tarjeta del perfil); en medio "CAMINO DEL PROGRESO" y la X.
##   la pista    una carta por nivel (2..50) encima de la BARRA AMARILLA, que va llena hasta lo que llevas. Debajo de la
##               barra, en cada nivel, una ESTRELLA con el numero (lo grande: armas, personajes, pinturas, mazos) o un
##               ROMBO blanco (lo pequeño: oro, cubos, cofres, cartas, diamantes) y la EXP que pide. Tu nivel, el
##               HEXAGONO AZUL. Las cartas de PERSONAJE van en azul con la cinta morada "NUEVO PERSONAJE" encima.
##               Lo ya dado lleva la palomita; lo que aun no, oscuro y con candado. Se desliza con el dedo (con inercia),
##               arrastrando con el raton o con la rueda.
##   derecha     NUEVO: lo siguiente que se desbloquea (CaminoProgreso.siguiente) con su nivel en la estrella.
##   abajo       la pastilla con la EXP que llevas ("345 XP").
## Tocar una carta (o la foto de NUEVO) abre su FICHA: nombre, tipo, nivel, rareza, poder, la foto grande, la tabla de
## datos, la descripcion, PROPIEDAD UNICA / ESPECIAL e HISTORIA (las de armeria_pantalla.gd y nivel_personaje.gd).
## Se dibuja en un lienzo de 904 de alto (el de la captura: las medidas salen de ella) y se escala a la pantalla
## (escala_pantalla.gd: en un plegable abierto no se estrecha). Lo abre el lobby (`_abrir_camino`), que le pasa `lobby`:
## de el salen los retratos 3D (`_retrato`) y la cuenta (`abrir_cuenta`). La capa es la 57: el panel de la cuenta (60)
## sale encima.

signal cerrado

const IconoLobby := preload("res://scripts/icono_lobby.gd")
const Pase := preload("res://scripts/pase_pantalla.gd")
const Armeria := preload("res://scripts/armeria_pantalla.gd")
const CofreScript := preload("res://scripts/cofre_pantalla.gd")
const HabilidadScript := preload("res://scripts/habilidad.gd")
const EscalaPantalla := preload("res://scripts/escala_pantalla.gd")
const Fuentes := preload("res://scripts/fuentes.gd")
const Sombreados := preload("res://scripts/sombreados.gd")

const ALTO := 904.0
## LA PISTA (en el contenido que se desliza): donde cae el nivel 1 y lo que hay de uno a otro
const X0 := 250.0
const PASO := 336.0
const BARRA_Y := 695.0
const BARRA_ALTO := 22.0
const NUM_Y := 752.0
## las cartas: ancho (con lo que se inclinan), inclinacion, donde acaban, donde empiezan (mas abajo si llevan cinta) y
## cuanto se corren a la derecha de su marca de la barra
const C_ANCHO := 316.0
const C_SESGO := 50.0
const C_ABAJO := 631.0
const C_ARRIBA := 257.0
const C_ARRIBA_CINTA := 290.0
const C_DX := 21.0
const CINTA_Y := 191.0
const BANDA := 88.0
## el panel NUEVO: su ancho arriba y abajo (el borde izquierdo inclinado)
const PANEL_ARRIBA := 446.0
const PANEL_ABAJO := 567.0
## los retratos 3D se cocinan algo mas grandes que su hueco: en una pantalla de mas de 904 de alto no pixelan
const RESOLUCION := 1.3
## La ficha
const FICHA := Vector2(1080, 812)
const FICHA_Y := 46.0
const COL_X := 498.0
const COL_W := 552.0
const COL_TOPE := 772.0

## LOS COLORES, medidos en las capturas
const FONDO_ARRIBA := Color8(86, 60, 150)
const FONDO_MEDIO := Color8(70, 50, 132)
const FONDO_ABAJO := Color8(56, 42, 110)
const MARCO := Color8(250, 182, 24)
const MARCO_CLARO := Color8(255, 222, 120)
const ARMA_A := Color8(158, 184, 214)
const ARMA_B := Color8(92, 118, 156)
const ARMA_BANDA := Color8(62, 80, 112)
const PJ_A := Color8(96, 184, 255)
const PJ_B := Color8(48, 116, 230)
const PJ_BANDA := Color8(36, 90, 204)
const BARRA_LLENA := Color8(253, 190, 28)
const BARRA_VACIA := Color8(120, 94, 170)
const AMARILLO := Color8(255, 210, 46)
const AMARILLO_TXT := Color8(255, 204, 40)
const ESTRELLA_BORDE := Color8(176, 112, 10)
const PANEL_A := Color8(130, 68, 200)
const PANEL_B := Color8(104, 52, 172)
const MAGENTA := Color8(142, 56, 126)
const CINTA_A := Color8(184, 120, 240)
const CINTA_B := Color8(142, 84, 214)
const LAVANDA := Color8(232, 214, 255)
const AZUL_HEX := Color8(40, 116, 236)
const VERDE_PODER := Color8(178, 238, 40)
const TINTA := Color8(28, 28, 44)
const CREMA := Color8(250, 238, 216)
const MORADO_OSCURO := Color8(42, 26, 92)

## EL HEXAGONO DEL FONDO: el de cartas_pantalla.gd (mismo codigo: el sombreado compartido se compila una vez)
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

## Los iconos de las propiedades de la armeria (armeria_pantalla._propiedad) en los de icono_lobby.gd
const ICONO_PROPIEDAD := {"dano": "glifo_dano", "municion": "glifo_municion", "destruccion": "glifo_destruccion",
	"explosion": "glifo_explosion", "escudo": "glifo_blindaje", "cadencia": "rayo", "recarga": "glifo_regeneracion",
	"sigilo": "invisible", "perdigones": "glifo_explosion", "mira": "mira"}

## el lobby que la abre (sin tipo: se le llaman sus funciones, que Node no tiene)
var lobby = null

var _raiz: Control
var _w := 1607.0
var _f: SystemFont           ## negrita gruesa y cursiva: la de los titulos de las capturas
var _fb: SystemFont          ## negrita recta
var _fm: SystemFont          ## seminegrita: los textos largos
var _franjas: Array = []
var _fondo: Control
var _pista: Control
var _contenido: Control
var _cartas: Array = []      ## {n, rect (en el contenido)}
var _ficha: Control = null
var _ficha_n := 0
var _cerrando := false
var _t := 0.0
# el arrastre de la pista
var _scroll := 0.0
var _vel := 0.0
var _obj := -1.0
var _pulsado := false
var _toque := -1
var _p0 := Vector2.ZERO
var _p_ult := Vector2.ZERO
var _t_ult := 0
var _movido := 0.0


func _ready() -> void:
	layer = 57
	_f = Fuentes.de(900, true)
	_fb = Fuentes.de(800, false)
	_fm = Fuentes.de(600, false)
	_montar()
	_ir_a(CaminoProgreso.nivel(), false)
	_raiz.modulate.a = 0.0
	create_tween().tween_property(_raiz, "modulate:a", 1.0, 0.18)
	Audio.ui("submenu_abre", -8.0)
	Cuenta.sesion_cambiada.connect(refrescar)
	if Cuenta.has_signal("camino_dado"):
		Cuenta.camino_dado.connect(func(_a, _b): refrescar())
	get_viewport().size_changed.connect(_rehacer)
	# lo del lobby se aparta mientras tanto (como el pase): debajo no se ve y se quedaba con los toques
	if is_instance_valid(lobby) and lobby.has_method("set_chrome_visible"):
		lobby.set_chrome_visible(false)


func _montar() -> void:
	var tam: Vector2 = get_viewport().get_visible_rect().size
	# EN UN PLEGABLE ABIERTO (casi cuadrado) el lienzo no se estrecha: se escala por el ancho y va centrado
	var m := EscalaPantalla.medir(tam, ALTO)
	var k: float = m["k"]
	_w = m["w"]
	_franjas = EscalaPantalla.franjas(self, tam, m["y0"], FONDO_ARRIBA, FONDO_ABAJO)
	_raiz = Control.new()
	_raiz.mouse_filter = Control.MOUSE_FILTER_STOP
	_raiz.scale = Vector2(k, k)
	_raiz.position.y = m["y0"]
	_raiz.size = Vector2(_w, ALTO)
	add_child(_raiz)
	_fondo = _dibujo(Vector2.ZERO, _raiz.size, _pintar_fondo, _raiz)
	_fondo.material = _material_hex(0.07, 64.0)
	_montar_pista()
	_montar_panel()
	_montar_cabecera()
	_montar_xp()
	_aplicar_scroll()


## LO VUELVE A MONTAR TODO (ha cambiado el nivel, lo dado o la cuenta), en el mismo sitio de la pista. Los retratos ya
## estan cocinados en el lobby: sale al momento.
func refrescar() -> void:
	if _cerrando or not is_inside_tree():
		return
	_rehacer()


func _rehacer() -> void:
	if _cerrando or not is_inside_tree():
		return
	var s := _scroll
	var abierta := _ficha_n
	EscalaPantalla.quitar(_franjas)
	if is_instance_valid(_raiz):
		_raiz.queue_free()
	_cartas.clear()
	_ficha = null
	_ficha_n = 0
	_montar()
	_scroll = clampf(s, 0.0, _scroll_max())
	_aplicar_scroll()
	if abierta > 0:
		_abrir_ficha(abierta, false)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _ficha != null and is_instance_valid(_ficha):
			_cerrar_ficha()
		else:
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
			lobby._refrescar_cuenta()
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


func _icono(nombre: String, col: Color, pos: Vector2, lado: float, padre: Node) -> Control:
	var ic := IconoLobby.new()
	ic.icono = nombre
	ic.color = col
	ic.position = pos
	ic.size = Vector2(lado, lado)
	padre.add_child(ic)
	return ic


func _material_hex(fuerza: float, radio: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = Sombreados.de(SOMBREADO_HEX)      # compartido: ver sombreados.gd
	m.set_shader_parameter("fuerza", fuerza)
	m.set_shader_parameter("radio", radio)
	return m


static func _con_puntos(v: int) -> String:
	return Pase._con_puntos(v)


static func _cerrado(p: PackedVector2Array) -> PackedVector2Array:
	var b := p.duplicate()
	b.append(p[0])
	return b


## Una estrella de cinco puntas centrada en `c`
static func _estrella(c: Vector2, r: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + i * TAU / 10.0
		var rr := r if i % 2 == 0 else r * 0.5
		p.append(c + Vector2(cos(a), sin(a)) * rr)
	return p


static func _hexagono(c: Vector2, r: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in 6:
		var a := -PI * 0.5 + i * TAU / 6.0
		p.append(c + Vector2(cos(a) * r * 0.92, sin(a) * r))
	return p


## Un texto centrado en `x` (con contorno), pintado a mano
func _txt_c(ci: CanvasItem, t: String, x: float, y: float, tam: int, col: Color, contorno := 0, col_c := Color.BLACK,
		f: Font = null) -> void:
	var fu: Font = f if f != null else _f
	var ts := fu.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam)
	if contorno > 0:
		ci.draw_string_outline(fu, Vector2(x - ts.x * 0.5, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, contorno, col_c)
	ci.draw_string(fu, Vector2(x - ts.x * 0.5, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, col)


## La ESTRELLA amarilla con un numero (la de "Tu nivel", las de la barra y la de NUEVO)
func _pintar_estrella(ci: CanvasItem, c: Vector2, r: float, t: String, viva := true) -> void:
	var cuerpo := _estrella(c, r)
	ci.draw_colored_polygon(_estrella(c + Vector2(0, r * 0.08), r * 1.08), Color(0.12, 0.05, 0.25, 0.35))
	ci.draw_colored_polygon(cuerpo, AMARILLO if viva else Color8(196, 172, 120))
	# la mitad de arriba algo mas clara
	var luz := PackedVector2Array()
	for q in cuerpo:
		luz.append(Vector2(q.x, minf(q.y, c.y)))
	ci.draw_colored_polygon(luz, Color(1, 1, 1, 0.16))
	ci.draw_polyline(_cerrado(cuerpo), ESTRELLA_BORDE if viva else Color8(120, 100, 70), maxf(2.0, r * 0.07), true)
	if t != "":
		var tam := int(round(r * 0.78))
		_txt_c(ci, t, c.x - r * 0.02, c.y + tam * 0.4, tam, Color8(52, 34, 12), 0, Color.BLACK, _f)


# ================================================================== el fondo
func _pintar_fondo(ci: Control) -> void:
	var w := ci.size.x
	ci.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, 420), Vector2(0, 420)]),
		PackedColorArray([FONDO_ARRIBA, FONDO_ARRIBA, FONDO_MEDIO, FONDO_MEDIO]))
	ci.draw_polygon(PackedVector2Array([Vector2(0, 420), Vector2(w, 420), Vector2(w, ALTO), Vector2(0, ALTO)]),
		PackedColorArray([FONDO_MEDIO, FONDO_MEDIO, FONDO_ABAJO, FONDO_ABAJO]))
	# una luz suave detras de las cartas y dos rayos en diagonal, muy tenues
	for i in 6:
		ci.draw_rect(Rect2(0, 230 + i * 18, w, 380 - i * 36), Color(1, 0.9, 1, 0.012))
	for r in [[0.3, 160.0, 0.025], [0.52, 90.0, 0.02]]:
		var x := w * float(r[0])
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + float(r[1]), 0), Vector2(x - 180 + float(r[1]), ALTO),
			Vector2(x - 180, ALTO)]), Color(1, 1, 1, float(r[2])))


# ================================================================== la pista
func _x_nivel(n: int) -> float:
	return X0 + float(n - 1) * PASO


func _largo() -> float:
	return _x_nivel(CaminoProgreso.NIVEL_MAX) + PASO + 600.0


## Lo mas a la derecha que se puede ir: la ultima carta tiene que quedar a la izquierda del panel NUEVO
func _scroll_max() -> float:
	return maxf(0.0, _x_nivel(CaminoProgreso.NIVEL_MAX) + C_DX + C_ANCHO * 0.5 + 24.0 - (_w - PANEL_ARRIBA - 34.0))


func _montar_pista() -> void:
	_pista = Control.new()
	_pista.size = Vector2(_w, ALTO)
	_pista.clip_contents = true
	_pista.mouse_filter = Control.MOUSE_FILTER_STOP
	_pista.gui_input.connect(_entrada_pista)
	_raiz.add_child(_pista)
	_contenido = _dibujo(Vector2.ZERO, Vector2(_largo(), ALTO), _pintar_barra, _pista)
	(_contenido as _Dibujo).animado = true          # el aro de tu nivel late
	_cartas.clear()
	for d in CaminoProgreso.lista():
		_carta(d)


## Lo grande lleva estrella en la barra; lo pequeño, un rombo
static func _grande(c: Dictionary) -> bool:
	return String(c.get("t", "")) in ["arma", "modelo", "pintura", "mazo"]


## La punta de lo que llevas, en la barra: de tu nivel al siguiente, segun la EXP
func _punta() -> float:
	var nv := CaminoProgreso.nivel()
	if nv >= CaminoProgreso.NIVEL_MAX:
		return _x_nivel(CaminoProgreso.NIVEL_MAX) + PASO * 0.6
	if nv < 1:
		return _x_nivel(1)
	var e := Cuenta.experiencia()
	var a := PaseBatalla.exp_de_nivel(nv)
	var b := PaseBatalla.exp_de_nivel(nv + 1)
	return _x_nivel(nv) + clampf(float(e - a) / float(maxi(1, b - a)), 0.0, 1.0) * PASO


func _pintar_barra(ci: Control) -> void:
	var fin := _x_nivel(CaminoProgreso.NIVEL_MAX) + PASO * 0.6
	var y0 := BARRA_Y - BARRA_ALTO * 0.5
	var punta := _punta()
	# la barra: filo oscuro, lo lleno con su brillo y su sombra, y lo que falta en morado
	ci.draw_rect(Rect2(-40, y0 - 4, fin + 40, BARRA_ALTO + 8), Color8(36, 22, 76))
	ci.draw_rect(Rect2(punta, y0, fin - punta, BARRA_ALTO), BARRA_VACIA)
	ci.draw_rect(Rect2(punta, y0 + 2, fin - punta, 3), Color(1, 1, 1, 0.12))
	ci.draw_rect(Rect2(-40, y0, punta + 40, BARRA_ALTO), BARRA_LLENA)
	ci.draw_rect(Rect2(-40, y0 + 2, punta + 40, 5), Color8(255, 234, 140))
	ci.draw_rect(Rect2(-40, y0 + BARRA_ALTO - 5, punta + 40, 5), Color8(226, 142, 12))
	# el final: una punta de flecha
	ci.draw_colored_polygon(PackedVector2Array([Vector2(fin, y0 - 4), Vector2(fin + 22, BARRA_Y), Vector2(fin, y0 + BARRA_ALTO + 4)]),
		Color8(36, 22, 76))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(fin, y0), Vector2(fin + 14, BARRA_Y), Vector2(fin, y0 + BARRA_ALTO)]),
		BARRA_LLENA if punta >= fin else BARRA_VACIA)
	# las marcas: estrella con el nivel (lo grande) o rombo (lo pequeño), y la EXP debajo
	var nv := CaminoProgreso.nivel()
	var actual := clampi(nv, 1, CaminoProgreso.NIVEL_MAX)
	for n in range(1, CaminoProgreso.NIVEL_MAX + 1):
		var x := _x_nivel(n)
		var alcanzado := nv >= n
		if n != actual:
			if n == 1 or _grande(CaminoProgreso.cosa(n)):
				_pintar_estrella(ci, Vector2(x, BARRA_Y), 25.0, str(n), alcanzado)
			else:
				var r := 13.0
				var rombo := PackedVector2Array([Vector2(x, BARRA_Y - r), Vector2(x + r, BARRA_Y), Vector2(x, BARRA_Y + r),
					Vector2(x - r, BARRA_Y)])
				ci.draw_colored_polygon(rombo, Color.WHITE if alcanzado else Color8(220, 210, 236))
				ci.draw_polyline(_cerrado(rombo), Color8(214, 140, 10) if alcanzado else Color8(110, 86, 160), 3.0, true)
		var t := _con_puntos(PaseBatalla.exp_de_nivel(n))
		var y := NUM_Y + (34.0 if n == actual else 0.0)
		_txt_c(ci, t, x, y, 27, Color.WHITE if alcanzado else Color(0.86, 0.82, 0.96), 6, Color(0.14, 0.08, 0.32, 0.6))
	# TU NIVEL: el hexagono azul encima de su marca, con un aro que late
	var c := Vector2(_x_nivel(actual), BARRA_Y)
	var k := 0.5 + 0.5 * sin(_t * 3.5)
	ci.draw_polyline(_cerrado(_hexagono(c, 54.0 + k * 3.0)), Color(0.6, 0.85, 1.0, 0.25 + 0.3 * k), 4.0, true)
	ci.draw_colored_polygon(_hexagono(c + Vector2(0, 4), 48.0), Color(0.06, 0.03, 0.2, 0.5))
	ci.draw_colored_polygon(_hexagono(c, 48.0), Color8(16, 44, 132))
	ci.draw_colored_polygon(_hexagono(c, 44.0), Color8(126, 196, 255))
	var dentro := _hexagono(c, 37.0)
	var cols := PackedColorArray()
	for q in dentro:
		cols.append(Color8(70, 150, 250).lerp(Color8(26, 84, 206), clampf((q.y - c.y + 37.0) / 74.0, 0.0, 1.0)))
	ci.draw_polygon(dentro, cols)
	_txt_c(ci, str(nv), c.x - 1.0, c.y + 17.0, 46, Color.WHITE, 8, Color8(16, 44, 132))


# ------------------------------------------------------------------ las cartas
func _carta(d: Dictionary) -> void:
	var n := int(d["nivel"])
	var c: Dictionary = d["cosa"]
	var pj := CaminoProgreso.es_personaje(c)
	var arriba := C_ARRIBA_CINTA if pj else C_ARRIBA
	var tam := Vector2(C_ANCHO, C_ABAJO - arriba)
	var pos := Vector2(_x_nivel(n) + C_DX - tam.x * 0.5, arriba)
	var info := _info(c)
	var alcanzado := CaminoProgreso.nivel() >= n
	var dado := CaminoProgreso.dado(n)
	var carta := Control.new()
	carta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carta.position = pos
	carta.size = tam
	_contenido.add_child(carta)
	var cuerpo := Control.new()
	cuerpo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cuerpo.size = tam
	carta.add_child(cuerpo)
	_dibujo(Vector2.ZERO, tam, func(ci: Control): _pintar_marco(ci, pj), cuerpo)
	var hueco := Rect2(30, 14, tam.x - 64, tam.y - BANDA - 16)
	var img := _imagen(c, hueco.size, "carta")
	img.position = hueco.position
	img.size = hueco.size
	cuerpo.add_child(img)
	# el nombre, en la franja de abajo
	var nombre: String = info["nombre"]
	var ln := _texto(nombre, 27 if nombre.length() <= 13 else (24 if nombre.length() <= 22 else 21), Color.WHITE, _f, 6,
		(PJ_BANDA if pj else ARMA_BANDA).darkened(0.45))
	ln.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ln.position = Vector2(10, tam.y - BANDA + 2)
	ln.size = Vector2(tam.x - 52, BANDA - 10)
	ln.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ln.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ln.add_theme_constant_override("line_spacing", -8)
	cuerpo.add_child(ln)
	if String(info["cantidad"]) != "":
		_pastilla_cantidad(cuerpo, info["cantidad"], Vector2(tam.x - 26.0 - C_SESGO * (BANDA + 4.0) / tam.y, tam.y - BANDA - 4.0), 30)
	if not alcanzado:
		cuerpo.modulate = Color(0.62, 0.58, 0.76)
	# encima: la palomita (ya es tuyo) o el candado (aun no llegas)
	_dibujo(Vector2.ZERO, tam, func(ci: Control):
		if dado:
			var dd := 7.0
			var p0 := Vector2(Pase._bordes(tam, C_SESGO, dd, dd).x, dd)
			var lado := 58.0
			var y1 := dd + lado * 0.9
			ci.draw_colored_polygon(PackedVector2Array([p0, p0 + Vector2(lado, 0), Vector2(Pase._bordes(tam, C_SESGO, dd, y1).x, y1)]),
				MARCO)
			var o := p0 + Vector2(3, 0)
			ci.draw_polyline(PackedVector2Array([o + Vector2(6, 17), o + Vector2(14, 25), o + Vector2(29, 8)]),
				Color8(36, 34, 48), 5.5, true)
		elif not alcanzado:
			_pintar_candado(ci, Vector2(tam.x - 42.0, 22.0), 1.0), carta)
	if pj:
		_cinta_personaje(Vector2(pos.x - 6.0, CINTA_Y), c)
	var r := Rect2(pos.x, CINTA_Y if pj else pos.y, tam.x, C_ABAJO - (CINTA_Y if pj else pos.y))
	_cartas.append({"n": n, "rect": r})


func _pintar_marco(ci: Control, pj: bool) -> void:
	var tam := ci.size
	var s := C_SESGO
	var a := PJ_A if pj else ARMA_A
	var b := PJ_B if pj else ARMA_B
	ci.draw_colored_polygon(Pase._para(tam + Vector2(0, 6), s, 0.0), Color(0.06, 0.03, 0.18, 0.35))
	ci.draw_colored_polygon(Pase._para(tam, s), MARCO)
	ci.draw_polyline(_cerrado(Pase._para(tam, s, 1.5)), MARCO_CLARO, 2.0, true)
	var dentro := Pase._para(tam, s, 8.0)
	ci.draw_polygon(dentro, PackedColorArray([a, a, b, b]))
	if pj:
		# los pixeles de la carta azul de la captura: cuadraditos mas claros sueltos
		for gy in range(0, int(tam.y / 14.0)):
			for gx in range(0, int(tam.x / 14.0) + 1):
				var rr := float(absi(hash(Vector2i(gx * 7 + 3, gy * 13 + 1))) % 100) / 100.0
				if rr < 0.6:
					continue
				var q := Vector2(gx * 14.0 + 2.0, gy * 14.0 + 2.0)
				if Geometry2D.is_point_in_polygon(q + Vector2(6, 6), dentro):
					ci.draw_rect(Rect2(q, Vector2(12, 12)), Color(1, 1, 1, 0.04 + (rr - 0.6) * 0.16))
	else:
		ci.draw_colored_polygon(Pase._franja(tam, s, 8.0, 8.0, 70.0), Color(1, 1, 1, 0.1))
	ci.draw_colored_polygon(Pase._franja(tam, s, 8.0, tam.y - BANDA, tam.y - 8.0), Color(PJ_BANDA if pj else ARMA_BANDA, 0.92))


## EL CANDADO DORADO del pase: arco, cuerpo redondeado con filo crema y el ojo de la cerradura. `c`: centro del cuerpo.
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


## "X3": la cantidad, en amarillo sobre una pastilla oscura. `der`: su esquina de abajo a la derecha
func _pastilla_cantidad(padre: Control, t: String, der: Vector2, tam: int) -> void:
	var ts := _f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam)
	var caja := Vector2(ts.x + 22.0, tam + 6.0)
	var p := _dibujo(der - caja, caja, func(ci: Control):
		ci.draw_colored_polygon(Pase._para(ci.size, 6.0), Color(0.08, 0.06, 0.2, 0.5)), padre)
	var l := _texto(t, tam, AMARILLO_TXT, _f, 5, Color(0.3, 0.16, 0.0, 0.8))
	l.size = caja
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)


## "NUEVO PERSONAJE": la cinta morada encima de la carta de un personaje (las "NUEVA FUNCION" de la captura), con el
## rombo de su habilidad a la izquierda
func _cinta_personaje(pos: Vector2, c: Dictionary) -> void:
	var pid := String(NivelPersonaje.SKIN_DE.get(String(c.get("v", "")), "soldado"))
	var hab: Dictionary = HabilidadScript.datos(String(NivelPersonaje.datos(pid).get("habilidad", "")))
	var tam := Vector2(326, 86)
	var cinta := _dibujo(pos, tam, func(ci: Control):
		var cuerpo := PackedVector2Array([Vector2(58, 4), Vector2(ci.size.x, 4), Vector2(ci.size.x - 14, ci.size.y - 4),
			Vector2(44, ci.size.y - 4)])
		ci.draw_colored_polygon(PackedVector2Array([Vector2(60, 8), Vector2(ci.size.x + 2, 8), Vector2(ci.size.x - 12, ci.size.y),
			Vector2(46, ci.size.y)]), Color(0.08, 0.03, 0.22, 0.4))
		ci.draw_polygon(cuerpo, PackedColorArray([CINTA_A, CINTA_A, CINTA_B, CINTA_B]))
		ci.draw_polyline(_cerrado(cuerpo), MARCO, 4.0, true)
		# el cuadradito de la esquina
		ci.draw_rect(Rect2(ci.size.x - 30, 16, 11, 11), Color(1, 1, 1, 0.3))
		# el rombo con la habilidad
		var cr := Vector2(44, ci.size.y * 0.5)
		var r := 40.0
		var rombo := PackedVector2Array([cr + Vector2(0, -r), cr + Vector2(r, 0), cr + Vector2(0, r), cr + Vector2(-r, 0)])
		ci.draw_colored_polygon(rombo, Color8(248, 236, 255))
		var r2 := r - 7.0
		var dentro := PackedVector2Array([cr + Vector2(0, -r2), cr + Vector2(r2, 0), cr + Vector2(0, r2), cr + Vector2(-r2, 0)])
		ci.draw_polygon(dentro, PackedColorArray([Color8(176, 120, 232), Color8(150, 90, 214), Color8(120, 70, 190),
			Color8(150, 90, 214)])), _contenido)
	_icono(String(hab.get("icono", "habilidades")), Color.WHITE, Vector2(24, 23), 40, cinta)
	var l1 := _texto("NUEVO PERSONAJE", 19, LAVANDA, _f)
	l1.position = Vector2(92, 8)
	l1.size = Vector2(220, 26)
	cinta.add_child(l1)
	var h := String(hab.get("nombre", ""))
	var l2 := _texto(h, 28 if h.length() <= 11 else 22, Color.WHITE, _f, 4, Color8(90, 40, 150))
	l2.position = Vector2(88, 30)
	l2.size = Vector2(224, 44)
	l2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cinta.add_child(l2)


# ------------------------------------------------------------------ lo que es cada cosa
## Lo que se enseña de una cosa del camino: tipo (y su icono), subtipo, rareza (y color), nombre, cantidad ("X3"),
## la linea de abajo del panel NUEVO [icono, texto] y el poder (0 = sin poder)
func _info(c: Dictionary) -> Dictionary:
	var t := String(c.get("t", ""))
	var v := str(c.get("v", ""))
	var r := {"tipo": "", "icono": "mochila", "sub": "", "rareza": "", "col": Color.WHITE,
		"nombre": CaminoProgreso.nombre_de(c), "cantidad": "", "prop": ["", ""], "poder": 0}
	match t:
		"arma":
			var d: Dictionary = Weapons.get_def(v)
			var rz: Dictionary = Armeria._rareza_arma(v)
			var kind := String(d.get("kind", ""))
			r["tipo"] = "ARMA"
			r["icono"] = "mira"
			r["sub"] = String(Weapons.KIND_NAMES.get(kind, kind)).to_upper()
			r["rareza"] = String(rz["nombre"])
			r["col"] = rz["color"]
			r["nombre"] = Armeria._nombre_arma(v).to_upper()
			r["prop"] = ["mira", r["sub"]]
			r["poder"] = Armeria._poder(d)
		"modelo":
			if CaminoProgreso.es_personaje(c):
				var pid := String(NivelPersonaje.SKIN_DE[v])
				var p: Dictionary = NivelPersonaje.datos(pid)
				var hab: Dictionary = HabilidadScript.datos(String(p.get("habilidad", "")))
				r["tipo"] = "PERSONAJE"
				r["icono"] = "usuario"
				r["sub"] = String(p.get("clase", ""))
				r["rareza"] = String(p.get("rareza", ""))
				r["col"] = _color_rareza(String(p.get("rareza", "")))
				r["nombre"] = String(p.get("nombre", v))
				r["prop"] = [String(hab.get("icono", "habilidades")), String(hab.get("nombre", ""))]
				r["poder"] = NivelPersonaje.poder(pid, 1)
			else:
				r["tipo"] = "ASPECTO"
				r["icono"] = "usuario"
				r["sub"] = "SKIN"
				r["rareza"] = "ASPECTO"
				r["col"] = Color(0.95, 0.55, 0.12)
				r["prop"] = ["usuario", "NUEVO ASPECTO"]
		"pintura":
			var rz: Dictionary = SkinsArmas.rareza_de(v)
			r["tipo"] = "PINTURA"
			r["icono"] = "rayo"
			r["sub"] = "PINTURA DE ARMA"
			r["rareza"] = String(rz["nombre"])
			r["col"] = rz["color"]
			r["nombre"] = SkinsArmas.nombre_de(v).to_upper()
			r["prop"] = ["rayo", "PARA TODAS LAS ARMAS"]
		"mazo":
			r["tipo"] = "MAZO"
			r["icono"] = "martillo"
			r["sub"] = "ASPECTO DE MAZO"
			r["rareza"] = "ESPECIAL"
			r["col"] = Color(0.95, 0.45, 0.75)
			r["prop"] = ["glifo_destruccion", "ROMPE HORMIGÓN"]
			r["poder"] = Armeria._poder(Weapons.get_def("sledge"))
		"carta":
			var d: Dictionary = Cartas.datos(v)
			var rz: Dictionary = SkinsArmas.RAREZAS[clampi(Cartas.rareza(v), 0, SkinsArmas.RAREZAS.size() - 1)]
			r["tipo"] = "CARTA"
			r["icono"] = "copias"
			r["sub"] = Cartas.nombre_categoria(String(d.get("cat", "")))
			r["rareza"] = String(rz["nombre"])
			r["col"] = rz["color"]
			r["nombre"] = String(d.get("nombre", v))
			r["cantidad"] = "X%d" % int(c.get("n", 1))
			r["prop"] = ["glifo_" + String(d.get("icono", "carta_todo")).substr(6), String(d.get("stat", ""))]
		"oro":
			r["tipo"] = "ORO"
			r["icono"] = "moneda"
			r["rareza"] = "RECURSO"
			r["col"] = Color(1.0, 0.8, 0.2)
			r["nombre"] = "ORO"
			r["cantidad"] = "X" + _con_puntos(int(c.get("v", 0)))
			r["prop"] = ["moneda", "+%s DE ORO" % _con_puntos(int(c.get("v", 0)))]
		"cubos":
			r["tipo"] = "CUBOS"
			r["icono"] = "cubo_fuerza"
			r["rareza"] = "RECURSO"
			r["col"] = Color(0.78, 0.52, 1.0)
			r["nombre"] = "CUBOS DE FUERZA"
			r["cantidad"] = "X" + _con_puntos(int(c.get("v", 0)))
			r["prop"] = ["cubo_fuerza", "SUBEN A TUS PERSONAJES"]
		"diamantes":
			r["tipo"] = "DIAMANTES"
			r["icono"] = "credito"
			r["rareza"] = "RECURSO"
			r["col"] = Color(0.4, 0.92, 0.55)
			r["nombre"] = "DIAMANTES"
			r["cantidad"] = "X" + _con_puntos(int(c.get("v", 0)))
			r["prop"] = ["credito", "SOLO CON CUENTA"]
		"cofre":
			var i := clampi(int(c.get("v", 0)), 0, SkinsArmas.RAREZAS.size() - 1)
			r["tipo"] = "COFRE"
			r["icono"] = "cofre"
			r["rareza"] = _masculino(String(SkinsArmas.RAREZAS[i]["nombre"]))
			r["col"] = SkinsArmas.RAREZAS[i]["color"]
			r["nombre"] = CofreScript.nombre_cofre(i)
			r["prop"] = ["cofre", "PUEDE SUBIR DE RAREZA"]
	return r


static func _color_rareza(nombre: String) -> Color:
	var i := 0
	match nombre:
		"POCO COMÚN":
			i = 1
		"RARO", "RARA":
			i = 2
		"ÉPICO", "ÉPICA":
			i = 3
		"LEGENDARIO", "LEGENDARIA":
			i = 4
		"MÍTICO", "MÍTICA":
			i = 5
	return SkinsArmas.RAREZAS[i]["color"]


static func _masculino(t: String) -> String:
	return {"RARA": "RARO", "ÉPICA": "ÉPICO", "LEGENDARIA": "LEGENDARIO", "MÍTICA": "MÍTICO"}.get(t, t)


# ------------------------------------------------------------------ las fotos de las cartas
## `uso`: "carta", "nuevo" o "ficha" (cambia el recorte del retrato y la clave de la foto cocinada)
func _imagen(c: Dictionary, tam: Vector2, uso: String) -> Control:
	var v := str(c.get("v", ""))
	match String(c.get("t", "")):
		"arma":
			return _foto_cocinada("pase:%s#" % v, tam, Pase._montar_arma(v, "", ""))
		"pintura":
			var arma := String(Pase.ARMA_DE_PINTURA.get(v, "carabina_556"))
			return _foto_cocinada("pase:%s#%s" % [arma, v], tam, Pase._montar_arma(arma, v, ""))
		"mazo":
			return _foto_cocinada("pase:%s#" % v, tam, Pase._montar_arma(v, "", "sledge"))
		"modelo":
			return _foto_retrato(v, uso)
		"oro":
			return _foto_cocinada("pase:monedas", tam, Pase._montar_monedas())
		"cubos":
			return _foto_cocinada("pase:cubos", tam, Pase._montar_cubos())
		"cofre":
			var r := clampi(int(c.get("v", 0)), 0, 5)
			return _foto_cocinada("pase:cofre%d" % r, tam, Pase._montar_cofre(r))
		"diamantes":
			return _foto_gemas(tam)
		"carta":
			return _foto_carta(v, tam)
	return _icono_suelto("mochila", Color.WHITE, tam)


func _icono_suelto(nombre: String, col: Color, tam: Vector2) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lado := minf(tam.x, tam.y) * 0.6
	_icono(nombre, col, (tam - Vector2(lado, lado)) * 0.5, lado, c)
	return c


## Un retrato 3D cocinado UNA vez por el lobby (`_retrato`) y guardado para la proxima vez (la misma clave que el pase:
## si el pase ya lo cocino a ese tamaño, sale al momento)
func _foto_cocinada(clave: String, tam: Vector2, montar: Callable) -> Control:
	if not is_instance_valid(lobby) or not lobby.has_method("_retrato"):
		return _icono_suelto("moneda", Color(1.0, 0.78, 0.05), tam)
	var px := (tam * RESOLUCION).round()
	var tr: TextureRect = lobby._retrato("%s@%dx%d" % [clave, int(px.x), int(px.y)], px, montar)
	tr.custom_minimum_size = Vector2.ZERO
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return tr


## El retrato del personaje (horneado con --retratos); en la carta, de la cabeza a la cintura
func _foto_retrato(nombre: String, uso: String) -> Control:
	var ruta := "res://avatar/retratos/%s.png" % nombre.to_lower().replace(" ", "_")
	if not ResourceLoader.exists(ruta):
		return _icono_suelto("usuario", Color.WHITE, Vector2(150, 150))
	var tr := TextureRect.new()
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	if uso == "carta":
		var at := AtlasTexture.new()
		at.atlas = load(ruta)
		at.region = Rect2(40, 2, 232, 236)
		tr.texture = at
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	else:
		tr.texture = load(ruta)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return tr


## LA CARTA: la carta morada de la pantalla de CARTAS, con el hexagono brillante de su dibujo (el de la captura: el
## corazon verde de SALUD MAX.)
func _foto_carta(id: String, tam: Vector2) -> Control:
	var d: Dictionary = Cartas.datos(id)
	var col: Color = d.get("color", Color.WHITE)
	var h := tam.y * 0.92
	var w := minf(h * 0.74, tam.x * 0.9)
	h = w / 0.74
	var r := Rect2((tam - Vector2(w, h)) * 0.5, Vector2(w, h))
	var c := _dibujo(Vector2.ZERO, tam, func(ci: Control):
		var marco := _esquinas_cortadas(r, w * 0.06)
		ci.draw_colored_polygon(_esquinas_cortadas(r.grow(3), w * 0.07), Color(0.06, 0.03, 0.18, 0.4))
		ci.draw_colored_polygon(marco, Color8(187, 176, 252))
		var cuerpo := _esquinas_cortadas(r.grow(-w * 0.04), w * 0.05)
		var cols := PackedColorArray()
		for q in cuerpo:
			cols.append(Color8(128, 112, 202).lerp(Color8(96, 82, 160), clampf((q.y - r.position.y) / r.size.y, 0.0, 1.0)))
		ci.draw_polygon(cuerpo, cols)
		ci.draw_polyline(_cerrado(cuerpo), Color8(89, 79, 142), 2.0, true), null)
	var lado := w * 0.78
	var ic := _icono(String(d.get("icono", "carta_todo")), col, Vector2(tam.x * 0.5 - lado * 0.5, r.position.y + h * 0.42 - lado * 0.5),
		lado, c)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func _esquinas_cortadas(r: Rect2, k: float) -> PackedVector2Array:
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x
	var y1 := r.end.y
	return PackedVector2Array([Vector2(x0 + k, y0), Vector2(x1 - k, y0), Vector2(x1, y0 + k), Vector2(x1, y1 - k),
		Vector2(x1 - k, y1), Vector2(x0 + k, y1), Vector2(x0, y1 - k), Vector2(x0, y0 + k)])


## LOS DIAMANTES: tres brillantes verdes tallados a caras (dibujados, como en el pase)
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


## Un brillante visto de lado: la corona con sus caras arriba, el cinto y el pabellon en punta abajo (el del pase)
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
	ci.draw_colored_polygon(todo, medio)
	var m1 := c + Vector2(-0.34 * r, -0.08 * r)
	var m2 := c + Vector2(0.34 * r, -0.08 * r)
	ci.draw_colored_polygon(PackedVector2Array([iz, ti, m1]), claro.lerp(medio, 0.35))
	ci.draw_colored_polygon(PackedVector2Array([ti, td, m2, m1]), claro)
	ci.draw_colored_polygon(PackedVector2Array([td, de, m2]), medio)
	ci.draw_colored_polygon(PackedVector2Array([iz, m1, punta]), medio)
	ci.draw_colored_polygon(PackedVector2Array([m1, c + Vector2(0, -0.08 * r), punta]), claro.lerp(medio, 0.5))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -0.08 * r), m2, punta]), medio.lerp(oscuro, 0.4))
	ci.draw_colored_polygon(PackedVector2Array([m2, de, punta]), oscuro)
	ci.draw_polyline(_cerrado(todo), filo, maxf(2.0, r * 0.07), true)
	ci.draw_line(iz, de, Color(filo, 0.5), maxf(1.5, r * 0.04), true)


# ================================================================== el panel NUEVO
func _forma_panel() -> PackedVector2Array:
	return PackedVector2Array([Vector2(PANEL_ABAJO - PANEL_ARRIBA, 0), Vector2(PANEL_ABAJO, 0), Vector2(PANEL_ABAJO, ALTO),
		Vector2(0, ALTO)])


func _montar_panel() -> void:
	var panel := _dibujo(Vector2(_w - PANEL_ABAJO, 0), Vector2(PANEL_ABAJO, ALTO), _pintar_panel, _raiz)
	panel.forma = _forma_panel()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP      # lo que se toca en el panel no llega a las cartas de debajo
	panel.material = _material_hex(0.06, 64.0)
	var cx := PANEL_ABAJO - 286.0
	var sig: Dictionary = CaminoProgreso.siguiente()
	if sig.is_empty():
		var l := _texto("¡LO TIENES TODO!", 54, AMARILLO_TXT, _f, 0, Color.BLACK, Color(0.2, 0.05, 0.4, 0.6))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.position = Vector2(cx - 220, 330)
		l.size = Vector2(440, 160)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		panel.add_child(l)
		var s := _texto("Has llegado al final del camino", 26, LAVANDA, _fb)
		s.position = Vector2(cx - 220, 490)
		s.size = Vector2(440, 40)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(s)
		return
	var n := int(sig["nivel"])
	var c: Dictionary = sig["cosa"]
	var info := _info(c)
	var nuevo := _texto("NUEVO", 78, AMARILLO_TXT, _f, 0, Color.BLACK, Color(0.25, 0.06, 0.4, 0.55))
	nuevo.position = Vector2(cx - 230, 92)
	nuevo.size = Vector2(460, 90)
	nuevo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nuevo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(nuevo)
	# el tipo, con su icono
	var tipo := String(info["tipo"])
	var tt := _f.get_string_size(tipo, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	var x0 := cx - (tt + 44.0) * 0.5
	_icono(String(info["icono"]), AMARILLO_TXT, Vector2(x0, 182), 36, panel)
	var lt := _texto(tipo, 34, AMARILLO_TXT, _f, 0, Color.BLACK, Color(0.25, 0.06, 0.4, 0.55))
	lt.position = Vector2(x0 + 44, 176)
	lt.size = Vector2(tt + 10, 48)
	lt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(lt)
	# la foto (se toca: la ficha)
	var r := Rect2(cx - 190, 250, 380, 300)
	var b := _boton(r, func(_ci: Control): pass, func(): _abrir_ficha(n), panel)
	var img := _imagen(c, r.size, "nuevo")
	img.position = Vector2.ZERO
	img.size = r.size
	b.add_child(img)
	_dibujo(r.position + Vector2(r.size.x - 120, r.size.y - 100), Vector2(110, 110), func(ci: Control):
		_pintar_estrella(ci, ci.size * 0.5, 50.0, str(n)), panel)
	# la rareza y el nombre
	var lr := _texto(String(info["rareza"]), 34, info["col"], _f, 6, Color(0.16, 0.06, 0.32, 0.55))
	lr.position = Vector2(cx - 250, 552)
	lr.size = Vector2(440, 46)
	lr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(lr)
	var nombre := String(info["nombre"])
	var ln := _texto(nombre, 52 if nombre.length() <= 18 else 42, Color.WHITE, _f, 8, Color8(70, 30, 120),
		Color(0.15, 0.04, 0.3, 0.5))
	ln.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ln.position = Vector2(cx - 250, 594)
	ln.size = Vector2(440, 118)
	ln.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ln.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ln.add_theme_constant_override("line_spacing", -12)
	panel.add_child(ln)
	# la propiedad: icono en su cuadrado y el texto
	var prop: Array = info["prop"]
	if String(prop[1]) != "":
		var pt := String(prop[1])
		var pw := minf(400.0, _fb.get_string_size(pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 25).x + 70.0)
		var caja := _dibujo(Vector2(cx - 30 - pw * 0.5, 720), Vector2(pw, 50), func(ci: Control):
			ci.draw_rect(Rect2(Vector2(0, 0), ci.size), Color(0.1, 0.03, 0.25, 0.28))
			ci.draw_rect(Rect2(-30, -10, ci.size.x + 60, 2), Color(1, 1, 1, 0.14))
			ci.draw_rect(Rect2(4, 5, 40, 40), Color8(250, 196, 40))
			ci.draw_rect(Rect2(7, 8, 34, 34), Color8(44, 96, 210)), panel)
		_icono(String(prop[0]), Color.WHITE, Vector2(10, 11), 28, caja)
		var lp := _texto(pt, 25 if pt.length() <= 22 else 20, Color8(208, 196, 246), _fb)
		lp.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lp.position = Vector2(54, 0)
		lp.size = Vector2(pw - 58, 50)
		lp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		caja.add_child(lp)


func _pintar_panel(ci: Control) -> void:
	var forma := _forma_panel()
	# la sombra del filo, por fuera
	for i in 4:
		ci.draw_line(forma[3] + Vector2(-4 - i * 6, 0), forma[0] + Vector2(-4 - i * 6, 0), Color(0.05, 0.02, 0.15, 0.08), 8.0)
	ci.draw_polygon(forma, PackedColorArray([PANEL_A, PANEL_A, PANEL_B, PANEL_B]))
	# un rayo de luz en diagonal, recortado a la forma del panel
	var rayo := PackedVector2Array([Vector2(260, 0), Vector2(400, 0), Vector2(160, ALTO), Vector2(20, ALTO)])
	for p in Geometry2D.intersect_polygons(rayo, forma):
		ci.draw_colored_polygon(p, Color(1, 1, 1, 0.05))
	# el filo de luz
	ci.draw_line(forma[3], forma[0], Color8(196, 150, 255), 4.0, true)


# ================================================================== la cabecera
func _montar_cabecera() -> void:
	# TU NIVEL: la estrella grande
	_dibujo(Vector2(108, 14), Vector2(120, 116), func(ci: Control):
		_pintar_estrella(ci, ci.size * 0.5 + Vector2(0, 2), 54.0, str(CaminoProgreso.nivel())), _raiz)
	var tn := _texto("Tu nivel", 21, Color.WHITE, _f, 4, Color(0.12, 0.06, 0.3, 0.6))
	tn.position = Vector2(88, 124)
	tn.size = Vector2(160, 30)
	tn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_raiz.add_child(tn)
	# CUENTA: en linea (tu nombre) o sin conexion; abre el panel de la cuenta del lobby
	var en_linea := Cuenta.conectado()
	var quien := Cuenta.nombre() if en_linea else ""
	if en_linea and quien == "":
		quien = "EN LÍNEA"
	if not en_linea:
		quien = "SIN CONEXIÓN"
	var bc := _boton(Rect2(30, 160, 280, 56), func(ci: Control):
		var s := ci.size
		var forma := Pase._para(s, 10.0)
		ci.draw_colored_polygon(Pase._para(s + Vector2(0, 4), 10.0), Color(0.04, 0.02, 0.14, 0.4))
		ci.draw_polygon(forma, PackedColorArray([Color8(66, 46, 150), Color8(66, 46, 150), Color8(44, 30, 112), Color8(44, 30, 112)]))
		ci.draw_polyline(_cerrado(forma), Color8(196, 170, 255), 2.5, true)
		ci.draw_circle(Vector2(s.x - 26, s.y * 0.5), 8.0, Color8(30, 20, 70))
		ci.draw_circle(Vector2(s.x - 26, s.y * 0.5), 6.0, Color8(80, 230, 110) if en_linea else Color8(230, 80, 90)),
		_pulsar_cuenta, _raiz)
	_icono("usuario", Color.WHITE, Vector2(16, 12), 32, bc)
	var l1 := _texto("CUENTA", 16, AMARILLO_TXT, _f)
	l1.position = Vector2(56, 3)
	l1.size = Vector2(180, 22)
	bc.add_child(l1)
	var l2 := _texto(quien, 22 if quien.length() <= 14 else 18, Color.WHITE, _f)
	l2.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l2.position = Vector2(54, 22)
	l2.size = Vector2(186, 30)
	l2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bc.add_child(l2)
	# EL TITULO, entre la estrella y el panel (se achica si no cabe)
	var izq := 300.0
	var der := _w - PANEL_ARRIBA - 24.0
	var titulo := "CAMINO DEL PROGRESO"
	var ancho := _f.get_string_size(titulo, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
	var tam := 64 if ancho <= der - izq else maxi(30, int(floor(64.0 * (der - izq) / ancho)))
	var lt := _texto(titulo, tam, Color.WHITE, _f, 0, Color.BLACK, Color(0.14, 0.05, 0.3, 0.55))
	lt.position = Vector2(izq, 30)
	lt.size = Vector2(der - izq, 76)
	lt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_raiz.add_child(lt)
	var sub := _texto("Gana EXP y desbloquea nuevas recompensas", 28 if tam >= 52 else 22, Color8(232, 224, 246),
		Fuentes.de(700, true), 0, Color.BLACK, Color(0.12, 0.05, 0.3, 0.45))
	sub.position = Vector2(izq, 102)
	sub.size = Vector2(der - izq, 40)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_raiz.add_child(sub)
	# LA X: la pestaña magenta de arriba a la derecha
	var bx := _boton(Rect2(_w - 218, 0, 218, 88), func(ci: Control):
		var w := ci.size.x
		var h := ci.size.y
		ci.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(18, h),
			Vector2(0, h - 18)]), MAGENTA), _cerrar, _raiz)
	var xt := _texto("X", 52, Color.WHITE, _f)
	xt.size = Vector2(218, 82)
	xt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bx.add_child(xt)


func _pulsar_cuenta() -> void:
	Audio.ui("aceptar", -6.0)
	if is_instance_valid(lobby) and lobby.has_method("abrir_cuenta"):
		lobby.abrir_cuenta()


# ================================================================== la EXP que llevas
func _montar_xp() -> void:
	var t1 := _con_puntos(Cuenta.experiencia())
	var t2 := " XP"
	var w1 := _f.get_string_size(t1, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	var w2 := _f.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	var tam := Vector2(w1 + w2 + 64.0, 54)
	var der := _w - PANEL_ABAJO + PANEL_ARRIBA * 0.0 + (PANEL_ABAJO - PANEL_ARRIBA) * (ALTO - 830.0) / ALTO - 70.0
	var p := _dibujo(Vector2(der - tam.x, 806), tam, func(ci: Control):
		var s := ci.size
		var forma := PackedVector2Array([Vector2(8, 0), Vector2(s.x - 14, 0), Vector2(s.x, s.y * 0.5), Vector2(s.x - 14, s.y),
			Vector2(0, s.y)])
		ci.draw_colored_polygon(PackedVector2Array([Vector2(10, 4), Vector2(s.x - 12, 4), Vector2(s.x + 2, s.y * 0.5 + 4),
			Vector2(s.x - 12, s.y + 4), Vector2(2, s.y + 4)]), Color(0.05, 0.02, 0.16, 0.35))
		ci.draw_polygon(forma, PackedColorArray([Color8(122, 96, 226), Color8(122, 96, 226), Color8(104, 80, 206),
			Color8(104, 80, 206), Color8(104, 80, 206)]))
		ci.draw_polyline(_cerrado(forma), Color8(186, 168, 255), 2.5, true), _raiz)
	var l1 := _texto(t1, 30, Color.WHITE, _f, 4, Color(0.2, 0.1, 0.45, 0.6))
	l1.position = Vector2(24, 0)
	l1.size = Vector2(w1 + 4, tam.y)
	l1.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l1)
	var l2 := _texto(t2, 30, AMARILLO_TXT, _f, 4, Color(0.2, 0.1, 0.45, 0.6))
	l2.position = Vector2(24 + w1, 0)
	l2.size = Vector2(w2 + 6, tam.y)
	l2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l2)


# ================================================================== la FICHA (la segunda captura)
## Los datos de la ficha de cada cosa: filas [icono, nombre, valor], descripcion, chip [icono, texto, color],
## unica [icono, nombre, valor], especial [icono, texto], el titulo de lo de abajo y su texto
func _ficha_datos(c: Dictionary) -> Dictionary:
	var t := String(c.get("t", ""))
	var v := str(c.get("v", ""))
	var r := {"filas": [], "desc": "", "chip": [], "unica": [], "especial": [], "titulo": "HISTORIA", "texto": ""}
	match t:
		"arma", "mazo":
			var id := v if t == "arma" else "sledge"
			var d: Dictionary = Weapons.get_def(id)
			var melee := bool(d.get("melee", false)) or String(d.get("kind", "")) == "sledge"
			var pel := int(d.get("pellets", 1))
			r["filas"] = [
				["glifo_dano", "DAÑO", ("%d×%d" % [int(d.get("damage", 0)), pel]) if pel > 1 else str(int(d.get("damage", 0)))],
				["rayo", "CADENCIA", "%s/s" % Armeria._num(float(d.get("rps", 0.0)))],
				["mira", "ALCANCE", "%s m" % Armeria._num(float(d.get("range", 0.0)))],
				["glifo_municion", "CARGADOR", "∞" if melee else str(int(d.get("mag", 0)))],
			]
			if t == "arma":
				r["desc"] = String(Armeria.DESCRIPCION.get(id, ""))
				r["chip"] = ["mira", String(Weapons.OPTICAS.get(String(d.get("optica", "")), "Miras de hierro")).to_upper(),
					AMARILLO_TXT]
				var pr: Array = Armeria._propiedad(id)
				r["unica"] = [String(ICONO_PROPIEDAD.get(String(pr[0]), "mira")), String(pr[1]), String(pr[2])]
				if bool(d.get("explosive", false)):
					r["especial"] = ["glifo_explosion", "Explosión: radio de %s m" % Armeria._num(float(d.get("radius", 0.0)))]
				else:
					r["especial"] = ["glifo_destruccion", "Destrucción %d contra muros y coberturas" % int(d.get("power", 0))]
				r["texto"] = String(Armeria.HISTORIA.get(id, Armeria.HISTORIA_TIPO.get(String(d.get("kind", "")), "")))
			else:
				var lema := String(Weapons.LEMA_SKIN.get(v, ""))
				r["desc"] = (lema.substr(0, 1).to_upper() + lema.substr(1) + ".") if lema != "" else "Un aspecto nuevo para tu mazo."
				r["chip"] = ["martillo", "ASPECTO DEL MAZO", AMARILLO_TXT]
				r["unica"] = ["glifo_destruccion", "ROMPE HORMIGÓN", "Sin munición: abre un hueco en el muro con cada golpe"]
				r["especial"] = ["martillo", "Cambia el modelo del mazo; los golpes son los mismos"]
				r["texto"] = String(Armeria.HISTORIA.get("sledge", ""))
		"modelo":
			if CaminoProgreso.es_personaje(c):
				var pid := String(NivelPersonaje.SKIN_DE[v])
				var p: Dictionary = NivelPersonaje.datos(pid)
				var hid := String(p.get("habilidad", ""))
				var hab: Dictionary = HabilidadScript.datos(hid)
				var filas: Array = [["glifo_vida", "SALUD", str(NivelPersonaje.salud(pid, 1))]]
				for m in HabilidadScript.MUESTRA.get(hid, []):
					filas.append([String(hab.get("icono", "habilidades")), String(m[1]),
						HabilidadScript.texto_valor(hid, String(m[0]), String(m[2]), 1)])
				filas.append(["usuario", "NIVEL MÁXIMO", str(NivelPersonaje.NIVEL_MAX)])
				r["filas"] = filas
				r["desc"] = String(p.get("desc", ""))
				r["chip"] = ["usuario", String(p.get("clase", "")), AMARILLO_TXT]
				r["unica"] = [String(hab.get("icono", "habilidades")), "DEFINITIVA: " + String(hab.get("nombre", "")),
					String(hab.get("texto", ""))]
				if p.has("habilidad_2"):
					r["especial"] = ["glifo_blindaje", "Segunda definitiva: " + String(p["habilidad_2"]) + " (gasta energía)"]
				else:
					var vs: Array = NivelPersonaje.ventajas(pid)
					if not vs.is_empty():
						var vv: Dictionary = vs[0]
						r["especial"] = ["glifo_especial", "NV.%d: %s %s" % [int(vv["nivel"]), NivelPersonaje.nombre_ventaja(vv),
							NivelPersonaje.texto_ventaja(vv)]]
				r["texto"] = NivelPersonaje.historia(pid)
			else:
				r["desc"] = "Un aspecto nuevo para tu personaje."
		"pintura":
			var s: Dictionary = SkinsArmas.por_id(v)
			var rz: Dictionary = SkinsArmas.rareza_de(v)
			var efecto := String(s.get("efecto", ""))
			r["filas"] = [["rayo", "RAREZA", String(rz["nombre"])], ["mira", "VALE PARA", "TODAS LAS ARMAS"],
				["glifo_especial", "EFECTO", efecto.to_upper() if efecto != "" else "—"]]
			var lema := String(s.get("lema", ""))
			r["desc"] = lema if lema != "" else "Un camuflaje para cualquiera de tus armas."
			r["chip"] = ["rayo", String(s.get("estilo", "camuflaje")).to_upper(), AMARILLO_TXT]
			r["unica"] = ["rayo", "PINTURA DE ARMA", "Se pone en la ARMERÍA, con el bote de pintura de cada arma"]
			r["especial"] = ["glifo_especial", ("Efecto animado: " + efecto) if efecto != "" else "Sin propiedades"]
			r["titulo"] = "CÓMO SE USA"
			r["texto"] = "Solo cambia cómo se ve el arma: el daño y la cadencia son los de siempre. Los demás la ven puesta en la partida."
		"carta":
			var d: Dictionary = Cartas.datos(v)
			var nc := int(c.get("n", 1))
			r["filas"] = [["copias", "CATEGORÍA", Cartas.nombre_categoria(String(d.get("cat", "")))],
				["glifo_" + String(d.get("icono", "carta_todo")).substr(6), "NIVEL 1", Cartas.texto_valor(v, 1)],
				["glifo_" + String(d.get("icono", "carta_todo")).substr(6), "NIVEL %d" % Cartas.NIVEL_MAX,
					Cartas.texto_valor(v, Cartas.NIVEL_MAX)],
				["copias", "COPIAS", "X%d" % nc]]
			r["desc"] = String(d.get("desc", ""))
			r["chip"] = ["copias", "CARTA DE " + Cartas.nombre_categoria(String(d.get("cat", ""))), AMARILLO_TXT]
			r["unica"] = ["glifo_" + String(d.get("icono", "carta_todo")).substr(6), String(d.get("stat", "")),
				"%s  >  %s" % [Cartas.texto_valor(v, 1), Cartas.texto_valor(v, Cartas.NIVEL_MAX)]]
			r["especial"] = ["copias", "Solo cuenta si la llevas en una de las 8 casillas"]
			r["titulo"] = "CÓMO SE USA"
			r["texto"] = "Las copias suben la carta de nivel en CARTAS (con oro y cubos de fuerza). Equípala en la ARMERÍA: solo cuentan las 8 que llevas puestas."
		"oro":
			r["filas"] = [["moneda", "CANTIDAD", _con_puntos(int(c.get("v", 0)))]]
			r["desc"] = "Oro para comprar armas y pinturas y para subir cartas y personajes."
			r["titulo"] = "CÓMO SE USA"
			r["texto"] = "Se suma a tu oro en cuanto llegas a este nivel. Las partidas también dan oro."
		"cubos":
			r["filas"] = [["cubo_fuerza", "CANTIDAD", _con_puntos(int(c.get("v", 0)))]]
			r["desc"] = "La energía que hace más fuertes a tus personajes y a tus cartas."
			r["titulo"] = "CÓMO SE USA"
			r["texto"] = "Con cubos de fuerza y oro se sube el nivel de un personaje (más salud y su definitiva más fuerte) y el de las cartas."
		"diamantes":
			r["filas"] = [["credito", "CANTIDAD", _con_puntos(int(c.get("v", 0)))]]
			r["desc"] = "La moneda de la tienda: personajes, cubos de fuerza, oro y el pase prémium."
			r["chip"] = ["candado", "Solo con cuenta", Color8(255, 150, 160)]
			r["titulo"] = "CÓMO SE USA"
			r["texto"] = "Los diamantes viven en tu cuenta: sin iniciar sesión este nivel no da nada."
		"cofre":
			var i := clampi(int(c.get("v", 0)), 0, SkinsArmas.RAREZAS.size() - 1)
			r["filas"] = [["cofre", "RAREZA DE SALIDA", _masculino(String(SkinsArmas.RAREZAS[i]["nombre"]))],
				["rayo", "TOQUES", "4"]]
			r["desc"] = "Ábrelo en COFRES: en cada toque puede subir de rareza."
			r["titulo"] = "QUÉ TRAE"
			r["texto"] = "Sobre todo cartas, y también oro y cubos de fuerza. De épico para arriba pueden salir aspectos."
	return r


func _abrir_ficha(n: int, con_sonido := true) -> void:
	_cerrar_ficha()
	var c: Dictionary = CaminoProgreso.cosa(n)
	if c.is_empty():
		return
	_ficha_n = n
	if con_sonido:
		Audio.ui("pasar", -8.0)
	var info := _info(c)
	var dat := _ficha_datos(c)
	var capa := Control.new()
	capa.mouse_filter = Control.MOUSE_FILTER_STOP
	capa.size = Vector2(_w, ALTO)
	_raiz.add_child(capa)
	_ficha = capa
	capa.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
				or (e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed):
			_cerrar_ficha())
	_dibujo(Vector2.ZERO, capa.size, func(ci: Control): ci.draw_rect(Rect2(Vector2.ZERO, ci.size), Color(0.03, 0.01, 0.1, 0.55)), capa)
	var px := clampf((_w - FICHA.x) * 0.5, 16.0, maxf(16.0, _w - FICHA.x - 110.0))
	var caja := Control.new()
	caja.mouse_filter = Control.MOUSE_FILTER_STOP
	caja.position = Vector2(px, FICHA_Y)
	caja.size = FICHA
	caja.pivot_offset = FICHA * 0.5
	capa.add_child(caja)
	var fondo := _dibujo(Vector2.ZERO, FICHA, _pintar_ficha, caja)
	fondo.material = _material_hex(0.05, 64.0)
	# arriba: el nombre, el tipo, el nivel y la rareza
	var nombre := String(info["nombre"])
	var ln := _texto(nombre, 44 if nombre.length() <= 22 else 34, Color.WHITE, _f, 0, Color.BLACK, Color(0.15, 0.04, 0.3, 0.5))
	ln.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ln.position = Vector2(34, 10)
	ln.size = Vector2(760, 60)
	ln.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caja.add_child(ln)
	var sub := String(info["tipo"])
	if String(info["sub"]) != "" and String(info["sub"]) != sub:
		sub += " · " + String(info["sub"])
	_icono(String(info["icono"]), Color.WHITE, Vector2(36, 70), 28, caja)
	var ls := _texto(sub, 25, Color.WHITE, _fb)
	ls.position = Vector2(72, 66)
	ls.size = Vector2(720, 36)
	ls.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caja.add_child(ls)
	var lnv := _texto("NV. %d" % n, 44, Color.WHITE, _f, 0, Color.BLACK, Color(0.15, 0.04, 0.3, 0.5))
	lnv.position = Vector2(FICHA.x - 300, 10)
	lnv.size = Vector2(250, 60)
	lnv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lnv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caja.add_child(lnv)
	var lr := _texto(String(info["rareza"]), 25, (info["col"] as Color).lightened(0.15), _fb)
	lr.position = Vector2(FICHA.x - 300, 66)
	lr.size = Vector2(250, 36)
	lr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lr.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caja.add_child(lr)
	# la X: la pestaña magenta pegada a la esquina
	var bx := _boton(Rect2(FICHA.x - 26, 4, 102, 80), func(ci: Control):
		var s := ci.size
		var forma := PackedVector2Array([Vector2(14, 0), Vector2(s.x, 0), Vector2(s.x - 14, s.y), Vector2(0, s.y)])
		ci.draw_colored_polygon(PackedVector2Array([Vector2(16, 5), Vector2(s.x + 2, 5), Vector2(s.x - 12, s.y + 5),
			Vector2(2, s.y + 5)]), Color(0.05, 0.02, 0.15, 0.35))
		ci.draw_polygon(forma, PackedColorArray([Color8(226, 70, 168), Color8(226, 70, 168), Color8(186, 46, 140),
			Color8(186, 46, 140)])), _cerrar_ficha, caja)
	var xt := _texto("X", 50, Color.WHITE, _f, 6, Color8(120, 20, 90))
	xt.size = Vector2(102, 80)
	xt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bx.add_child(xt)
	# a la izquierda: el PODER (rayo verde) o la cantidad, y la foto grande
	var poder := int(info["poder"])
	if poder > 0:
		_dibujo(Vector2(42, 140), Vector2(46, 64), func(ci: Control):
			var rayo := PackedVector2Array([Vector2(28, 0), Vector2(6, 36), Vector2(20, 36), Vector2(12, 64), Vector2(40, 24),
				Vector2(25, 24), Vector2(36, 0)])
			ci.draw_colored_polygon(rayo, VERDE_PODER)
			ci.draw_polyline(_cerrado(rayo), Color8(60, 110, 10), 2.0, true), caja)
		var lp := _texto(str(poder), 60, VERDE_PODER, _f, 6, Color8(50, 96, 10))
		lp.position = Vector2(92, 132)
		lp.size = Vector2(220, 80)
		lp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		caja.add_child(lp)
	elif String(info["cantidad"]) != "":
		var lc := _texto(String(info["cantidad"]), 60, AMARILLO_TXT, _f, 6, Color8(110, 60, 0))
		lc.position = Vector2(46, 132)
		lc.size = Vector2(300, 80)
		lc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		caja.add_child(lc)
	var ri := Rect2(30, 214, 440, 400)
	var img := _imagen(c, ri.size, "ficha")
	img.position = ri.position
	img.size = ri.size
	caja.add_child(img)
	# a la derecha: la columna (se aprieta si no cabe)
	for apretar in 6:
		var col := Control.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.position = Vector2(COL_X, 0)
		col.size = Vector2(COL_W, FICHA.y)
		caja.add_child(col)
		var alto := _montar_columna(col, dat, apretar)
		if alto <= COL_TOPE or apretar == 5:
			break
		caja.remove_child(col)
		col.free()
	# entra de golpe
	caja.scale = Vector2(0.86, 0.86)
	caja.modulate.a = 0.0
	var tw := caja.create_tween().set_parallel(true)
	tw.tween_property(caja, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(caja, "modulate:a", 1.0, 0.12)


## Monta la columna de la derecha de la ficha y devuelve donde acaba. `apretar` (0..5) achica las letras de lo largo.
func _montar_columna(col: Control, dat: Dictionary, apretar: int) -> float:
	var y := 136.0
	var t_fila := 22
	var t_desc := maxi(16, 21 - apretar)
	var t_tit := maxi(22, 29 - apretar)
	var t_texto := maxi(16, 24 - apretar)
	var filas: Array = dat["filas"]
	var desc := String(dat["desc"])
	var fila_h := 38.0
	var desc_h := 0.0
	if desc != "":
		desc_h = _alto_texto(desc, _fm, t_desc, COL_W - 24.0) + 18.0
	var tabla_h := fila_h * filas.size() + desc_h
	if tabla_h > 0.0:
		var tabla := _dibujo(Vector2(0, y), Vector2(COL_W, tabla_h), func(ci: Control):
			for i in filas.size():
				var r := Rect2(0, i * fila_h, COL_W, fila_h)
				ci.draw_rect(r, Color8(250, 248, 252) if i % 2 == 0 else Color8(240, 236, 248))
				ci.draw_rect(Rect2(0, r.end.y - 1, COL_W, 1), Color8(200, 192, 220))
				var f: Array = filas[i]
				ci.draw_string(_fb, Vector2(40, r.position.y + 27), String(f[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, t_fila, TINTA)
				var vt := String(f[2])
				var vw := _fb.get_string_size(vt, HORIZONTAL_ALIGNMENT_LEFT, -1, t_fila + 1).x
				ci.draw_string(_fb, Vector2(COL_W - 12 - vw, r.position.y + 27), vt, HORIZONTAL_ALIGNMENT_LEFT, -1, t_fila + 1, TINTA)
			if desc_h > 0.0:
				ci.draw_rect(Rect2(0, filas.size() * fila_h, COL_W, desc_h), Color8(234, 230, 244)), col)
		for i in filas.size():
			_icono(String(filas[i][0]), TINTA, Vector2(8, i * fila_h + 6), 26, tabla)
		if desc_h > 0.0:
			var ld := _texto(desc, t_desc, TINTA, _fm)
			ld.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ld.position = Vector2(12, filas.size() * fila_h + 8)
			ld.size = Vector2(COL_W - 24, desc_h - 16)
			tabla.add_child(ld)
		y += tabla_h + 10.0
	# el chip (la mira del arma, la clase del personaje... o "Solo con cuenta")
	var chip: Array = dat["chip"]
	if not chip.is_empty():
		var ct := String(chip[1])
		var cw := _fb.get_string_size(ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x + 52.0
		var ch := _dibujo(Vector2(0, y), Vector2(cw, 34), func(ci: Control):
			ci.draw_rect(Rect2(Vector2.ZERO, ci.size), Color(0.18, 0.06, 0.32, 0.3)), col)
		_icono(String(chip[0]), chip[2], Vector2(9, 5), 24, ch)
		var lc := _texto(ct, 21, chip[2], _fb)
		lc.position = Vector2(40, 0)
		lc.size = Vector2(cw - 40, 34)
		lc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ch.add_child(lc)
		y += 44.0
	# PROPIEDAD UNICA
	var unica: Array = dat["unica"]
	if not unica.is_empty():
		y = _raya(col, y)
		y = _titulo(col, "PROPIEDAD ÚNICA", y, t_tit)
		var vt := String(unica[2])
		var vh := _alto_texto(vt, _fm, t_desc, COL_W - 90.0)
		var bh := maxf(66.0, 12.0 + 28.0 + vh + 8.0)
		var caja := _dibujo(Vector2(0, y), Vector2(COL_W, bh), func(ci: Control):
			ci.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(ci.size.x, 0), ci.size, Vector2(0, ci.size.y)]),
				PackedColorArray([Color(0.78, 0.6, 0.95, 0.35), Color(0.9, 0.7, 1.0, 0.18), Color(0.9, 0.7, 1.0, 0.18),
				Color(0.78, 0.6, 0.95, 0.35)]))
			# los pixeles sueltos de la captura
			for i in 14:
				var q := Vector2(ci.size.x * (0.55 + 0.43 * float(absi(hash(i * 7 + 1)) % 100) / 100.0),
					ci.size.y * float(absi(hash(i * 13 + 5)) % 100) / 100.0)
				ci.draw_rect(Rect2(q, Vector2(6, 6)), Color(1, 1, 1, 0.12))
			ci.draw_rect(Rect2(10, 8, 52, 52), Color8(250, 196, 40))
			ci.draw_rect(Rect2(13, 11, 46, 46), Color8(48, 104, 220)), col)
		_icono(String(unica[0]), Color.WHITE, Vector2(18, 16), 36, caja)
		var lu := _texto(String(unica[1]), 23, Color8(150, 226, 255), _fb)
		lu.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lu.position = Vector2(76, 6)
		lu.size = Vector2(COL_W - 86, 30)
		caja.add_child(lu)
		var lv := _texto(vt, t_desc, Color.WHITE, _fm)
		lv.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lv.position = Vector2(76, 36)
		lv.size = Vector2(COL_W - 90, vh + 4)
		caja.add_child(lv)
		y += bh + 10.0
	# PROPIEDAD ESPECIAL
	var esp: Array = dat["especial"]
	if not esp.is_empty():
		y = _titulo(col, "PROPIEDAD ESPECIAL", y, t_tit)
		var et := String(esp[1])
		var eh := _alto_texto(et, _fm, t_texto, COL_W - 44.0)
		_icono(String(esp[0]), Color.WHITE, Vector2(2, y + 4), 28, col)
		var le := _texto(et, t_texto, Color.WHITE, _fm)
		le.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		le.position = Vector2(40, y)
		le.size = Vector2(COL_W - 44, eh + 4)
		col.add_child(le)
		y += eh + 12.0
	# HISTORIA (o como se usa)
	var texto := String(dat["texto"])
	if texto != "":
		y = _raya(col, y)
		y = _titulo(col, String(dat["titulo"]), y, t_tit)
		var th := _alto_texto(texto, _fm, t_texto, COL_W)
		var lh := _texto(texto, t_texto, Color.WHITE, _fm)
		lh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lh.position = Vector2(0, y)
		lh.size = Vector2(COL_W, th + 4)
		col.add_child(lh)
		y += th
	return y


func _raya(col: Control, y: float) -> float:
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.color = Color(1, 1, 1, 0.4)
	r.position = Vector2(0, y)
	r.size = Vector2(COL_W, 3)
	col.add_child(r)
	return y + 10.0


func _titulo(col: Control, t: String, y: float, tam: int) -> float:
	var l := _texto(t, tam, Color.WHITE, _fb, 0, Color.BLACK, Color(0.15, 0.04, 0.3, 0.4))
	l.position = Vector2(0, y)
	l.size = Vector2(COL_W, tam + 8)
	col.add_child(l)
	return y + tam + 10.0


## Lo que ocupa de alto un texto partido en lineas de `ancho`
func _alto_texto(t: String, f: Font, tam: int, ancho: float) -> float:
	if t == "":
		return 0.0
	return f.get_multiline_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, ancho, tam, -1,
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND).y


func _pintar_ficha(ci: Control) -> void:
	var s := ci.size
	var forma := PackedVector2Array([Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(26, s.y), Vector2(0, s.y - 26)])
	ci.draw_colored_polygon(PackedVector2Array([Vector2(6, 8), Vector2(s.x + 6, 8), Vector2(s.x + 6, s.y + 8), Vector2(32, s.y + 8),
		Vector2(6, s.y - 18)]), Color(0.02, 0.0, 0.08, 0.4))
	ci.draw_polygon(forma, PackedColorArray([Color8(140, 84, 200), Color8(150, 92, 208), Color8(176, 112, 222),
		Color8(170, 106, 218), Color8(168, 104, 216)]))
	# la cabecera, algo mas oscura, con su filo de luz
	ci.draw_rect(Rect2(0, 0, s.x, 112), Color(0.32, 0.12, 0.52, 0.32))
	ci.draw_rect(Rect2(0, 110, s.x, 2), Color(1, 1, 1, 0.16))
	# el resplandor detras de la foto
	for i in 8:
		ci.draw_circle(Vector2(250, 420), 210.0 * (1.0 - i / 8.0), Color(1, 0.9, 1, 0.012 + i * 0.006))
	ci.draw_polyline(_cerrado(forma), Color(1, 1, 1, 0.18), 2.0, true)


func _cerrar_ficha() -> void:
	if _ficha != null and is_instance_valid(_ficha):
		_ficha.queue_free()
		Audio.ui("atras", -10.0)
	_ficha = null
	_ficha_n = 0


# ================================================================== el estado y la pista
func _process(dt: float) -> void:
	_t += dt
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


func _aplicar_scroll() -> void:
	if is_instance_valid(_contenido):
		_contenido.position.x = -roundf(_scroll)


## Deja el nivel `n` en medio de lo que se ve de la pista (a la izquierda del panel)
func _ir_a(n: int, animado: bool = true) -> void:
	var obj := clampf(_x_nivel(clampi(n, 1, CaminoProgreso.NIVEL_MAX)) + C_DX - (_w - PANEL_ARRIBA - 40.0) * 0.5, 0.0,
		_scroll_max())
	if animado:
		_obj = obj
		_vel = 0.0
	else:
		_scroll = obj
		_obj = -1.0
		_aplicar_scroll()


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
			_abrir_ficha(int(e["n"]))
			return


# ================================================================== las fotos de prueba
## --caminofoto=<carpeta> (lobby._camino_foto): tal cual se abre, al final, cerca del segundo personaje, la ficha de un
## arma y la de un personaje. No toca nada guardado.
func fotos(carpeta: String) -> void:
	DirAccess.make_dir_recursive_absolute(carpeta)
	var foto := func(nombre: String) -> void:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(carpeta.path_join(nombre + ".png"))
		print("[caminofoto] ", carpeta.path_join(nombre + ".png"))
	# que el lobby cocine los retratos de las cartas
	await get_tree().create_timer(6.0).timeout
	await foto.call("camino_1")
	_scroll = _scroll_max()
	_aplicar_scroll()
	await get_tree().create_timer(2.0).timeout
	await foto.call("camino_2")
	_ir_a(30, false)
	await get_tree().create_timer(1.5).timeout
	await foto.call("camino_5")
	var arma := 10
	for d in CaminoProgreso.lista():
		if String(d["cosa"].get("t", "")) == "arma" and int(d["nivel"]) >= 10:
			arma = int(d["nivel"])
			break
	_abrir_ficha(arma)
	await get_tree().create_timer(3.0).timeout
	await foto.call("camino_3")
	var pj := 15
	for d in CaminoProgreso.lista():
		if CaminoProgreso.es_personaje(d["cosa"]):
			pj = int(d["nivel"])
			break
	_abrir_ficha(pj)
	await get_tree().create_timer(1.5).timeout
	await foto.call("camino_4")
	# las demas fichas (carta, pintura, mazo, diamantes, cofre), por si acaso
	var vistos := {}
	for d in CaminoProgreso.lista():
		var t := String(d["cosa"].get("t", ""))
		if t in ["carta", "pintura", "mazo", "diamantes", "cofre", "oro"] and not vistos.has(t):
			vistos[t] = true
			_abrir_ficha(int(d["nivel"]))
			await get_tree().create_timer(2.5).timeout
			await foto.call("camino_ficha_" + t)
	_cerrar_ficha()


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
