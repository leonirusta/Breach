extends Control
## EL TORNEO SEMANAL EN EL VESTIBULO (2026-10-18, pedido: "un aviso en el lobby, y la tabla en tiempo real con el top 1,
## 2 y 3 de otros colores"). Una tarjeta arriba en el centro (lo monta lobby._build_ui): el modo y el mapa, cuando empieza
## o cuanto le queda, y tu puesto. Tocarla abre la pantalla del torneo: premios, como se suman los puntos, la TABLA EN VIVO
## (oro, plata y bronce para los tres primeros) y los ganadores del anterior. Todo de GET /torneo (servidor/torneos.js),
## cada 30 s (cada 8 s con la pantalla abierta y el torneo en marcha). Sin servidor, no se ve.
## Foto: `--torneofoto=<carpeta>` (datos de prueba en memoria).

const Fuentes := preload("res://scripts/fuentes.gd")
const ORO := Color(1.0, 0.80, 0.25)
const PLATA := Color(0.82, 0.86, 0.92)
const BRONCE := Color(0.86, 0.55, 0.30)
const FONDO := Color(0.07, 0.05, 0.16, 0.92)
const PREMIO_COLORES := [ORO, PLATA, BRONCE]
const RAREZAS := ["común", "raro", "épico", "legendario", "mítico", "ultra"]

var datos: Dictionary = {}          ## lo ultimo de /torneo: {torneo, anterior, ahora}
var _ahora_srv := 0.0               ## diferencia reloj del servidor - el nuestro (ms)
var _http: HTTPRequest
var _pidiendo := false
var _t := 0.0
var _tarjeta: Button
var _l1: Label
var _l2: Label
var _capa: CanvasLayer = null
var _lista: VBoxContainer = null
var _cuenta_atras: Label = null
var _yo: Label = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tarjeta = Button.new()
	_tarjeta.focus_mode = Control.FOCUS_NONE
	_tarjeta.custom_minimum_size = Vector2(380, 62)
	_tarjeta.size = Vector2(380, 62)
	_tarjeta.position = Vector2(-190, 74)
	_tarjeta.add_theme_stylebox_override("normal", _caja(Color(0.10, 0.06, 0.22, 0.88), ORO, 2))
	_tarjeta.add_theme_stylebox_override("hover", _caja(Color(0.16, 0.10, 0.30, 0.92), ORO, 2))
	_tarjeta.add_theme_stylebox_override("pressed", _caja(Color(0.22, 0.14, 0.36, 0.95), ORO, 3))
	_tarjeta.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_tarjeta.pressed.connect(abrir)
	_tarjeta.visible = false
	add_child(_tarjeta)
	var copa := _texto("🏆", 30, ORO)
	copa.position = Vector2(12, 10)
	_tarjeta.add_child(copa)
	_l1 = _texto("", 15, Color.WHITE, 800)
	_l1.position = Vector2(56, 9)
	_l1.clip_text = true
	_tarjeta.add_child(_l1)
	_l2 = _texto("", 13, ORO, 600)
	_l2.position = Vector2(56, 34)
	_l2.clip_text = true
	_tarjeta.add_child(_l2)
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_llego)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--torneofoto"):
			_datos_prueba()
			_fotos(a.get_slice("=", 1) if "=" in a else "user://")
			return
	_pedir()


func _caja(fondo: Color, borde: Color, ancho: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fondo
	sb.border_color = borde
	sb.set_border_width_all(ancho)
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 6
	return sb


func _texto(t: String, tam: int, col: Color, peso := 600) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", Fuentes.de(peso, false))
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


var _prueba := false

func _pedir() -> void:
	if _pidiendo or Cuenta.url == "" or _prueba:
		return
	_pidiendo = true
	var cab := PackedStringArray()
	if Cuenta.token != "":
		cab.append("Authorization: Bearer " + Cuenta.token)
	if _http.request(Cuenta.url.trim_suffix("/") + "/torneo", cab, HTTPClient.METHOD_GET) != OK:
		_pidiendo = false


func _llego(res: int, codigo: int, _cab: PackedStringArray, cuerpo: PackedByteArray) -> void:
	_pidiendo = false
	if res != HTTPRequest.RESULT_SUCCESS or codigo != 200:
		return
	var j = JSON.parse_string(cuerpo.get_string_from_utf8())
	if typeof(j) != TYPE_DICTIONARY:
		return
	datos = j
	_ahora_srv = float(j.get("ahora", 0.0)) - Time.get_unix_time_from_system() * 1000.0
	_pintar()


func _ahora_ms() -> float:
	return Time.get_unix_time_from_system() * 1000.0 + _ahora_srv


func _process(dt: float) -> void:
	# CENTRADA ARRIBA, entre las dos columnas del vestibulo (el ancho, el que deja la pantalla)
	var vp := get_viewport_rect().size
	var ancho := clampf(vp.x * 0.33, 300.0, 520.0)
	_tarjeta.size = Vector2(ancho, 62)
	_tarjeta.position = Vector2(vp.x * 0.5 - ancho * 0.5, 74.0) - global_position
	_l1.size = Vector2(ancho - 64, 22)
	_l2.size = Vector2(ancho - 64, 20)
	_t -= dt
	var t: Dictionary = datos.get("torneo", {}) if typeof(datos.get("torneo")) == TYPE_DICTIONARY else {}
	var vivo := String(t.get("estado", "")) == "activo"
	if _t <= 0.0:
		_t = 8.0 if (vivo and _capa != null) else 30.0
		_pedir()
	if not t.is_empty():
		_pintar_reloj(t)


## "en 2 d 4 h" / "1:23:45"
func _falta(ms: float) -> String:
	var s := maxi(0, int(ms / 1000.0))
	if s >= 86400:
		return "%d d %d h" % [s / 86400, (s % 86400) / 3600]
	if s >= 3600:
		return "%d h %02d min" % [s / 3600, (s % 3600) / 60]
	return "%d:%02d" % [s / 60, s % 60]


func _pintar_reloj(t: Dictionary) -> void:
	var ahora := _ahora_ms()
	var estado := String(t.get("estado", ""))
	var txt := ""
	if estado == "proximo":
		txt = "EMPIEZA EN " + _falta(float(t.get("inicio", 0)) - ahora)
	elif estado == "activo":
		txt = "🔴 EN VIVO · TERMINA EN " + _falta(float(t.get("fin", 0)) - ahora)
	else:
		txt = "TERMINADO"
	var yo = t.get("yo")
	var linea := txt + (("  ·  TU PUESTO: %d.º" % int(yo["pos"])) if typeof(yo) == TYPE_DICTIONARY else "")
	if _l2.text != linea:
		_l2.text = linea
	if _cuenta_atras and _cuenta_atras.text != txt:
		_cuenta_atras.text = txt


## true mientras el torneo esta en marcha (la tecla de la copa dice EN VIVO)
func en_vivo() -> bool:
	var t = datos.get("torneo")
	return typeof(t) == TYPE_DICTIONARY and String(t.get("estado", "")) == "activo"


func _pintar() -> void:
	var t = datos.get("torneo")
	# la tarjeta de arriba ya no sale: el torneo esta en la tecla de la copa (lobby_portada._pintar_copa)
	_tarjeta.visible = false
	if typeof(t) != TYPE_DICTIONARY or (t as Dictionary).is_empty():
		return
	_l1.text = "TORNEO #%d · %s" % [int(t.get("n", 0)), String(t.get("titulo", ""))]
	_pintar_reloj(t)
	if _capa != null:
		_pintar_tabla()


# ------------------------------------------------------------------------------------------------ la pantalla
## POSICIONES (2026-10-19, pedido con captura de Pixel Gun: "la tabla es muy mala, un diseño parecido"): fondo violeta a
## pantalla entera, POSICIONES arriba a la izquierda, la X magenta en la esquina; a la izquierda la tabla (PUESTO, LISTA DE
## JUGADORES, PUNTOS, PREMIO) con el 1.º en oro, el 2.º en azul y el 3.º en rosa, y TU fila con borde amarillo y la cinta
## TÚ; a la derecha la ficha del torneo (sin el dibujo del personaje: "no agregues eso todavia").

const VIOLETA_FONDO := Color8(62, 48, 120)
const VIOLETA_TABLA := Color8(96, 78, 196)
const VIOLETA_FILA := Color8(112, 92, 214)
const VIOLETA_FILA2 := Color8(104, 85, 205)
const VIOLETA_CAB := Color8(78, 62, 160)
const MAGENTA := Color8(150, 50, 140)
const AMARILLO_TU := Color8(255, 226, 60)
const PUESTO_COLORES := [[Color8(255, 214, 90), Color8(232, 150, 40)], [Color8(120, 196, 255), Color8(60, 120, 230)],
	[Color8(255, 150, 190), Color8(220, 80, 130)]]
const COFRE_RAREZA := [Color8(190, 140, 80), Color8(80, 170, 255), Color8(190, 90, 255), Color8(255, 190, 40),
	Color8(255, 80, 80), Color8(80, 255, 220)]
const IconoLobby := preload("res://scripts/icono_lobby.gd")

var _filas_caja: VBoxContainer = null
var _info_estado: Label = null
var _ancho_filas := 800.0


func _caja_plana(fondo: Color, radio := 0, borde := Color(0, 0, 0, 0), ancho := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fondo
	sb.set_corner_radius_all(radio)
	if ancho > 0:
		sb.border_color = borde
		sb.set_border_width_all(ancho)
	return sb


func _cursiva(t: String, tam: int, col: Color, peso := 900) -> Label:
	var l := _texto(t, tam, col, peso)
	l.add_theme_font_override("font", Fuentes.de(peso, true))
	return l


func abrir() -> void:
	if _capa != null:
		return
	Audio.ui("aceptar", -6.0)
	_capa = CanvasLayer.new()
	_capa.layer = 60
	add_child(_capa)
	var vp := get_viewport_rect().size
	var fondo := ColorRect.new()
	fondo.color = VIOLETA_FONDO
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fondo.mouse_filter = Control.MOUSE_FILTER_STOP
	_capa.add_child(fondo)
	# la X en la esquina de arriba a la derecha, como una pestaña magenta
	var x := Button.new()
	x.text = "X"
	x.focus_mode = Control.FOCUS_NONE
	x.add_theme_font_override("font", Fuentes.de(900, true))
	x.add_theme_font_size_override("font_size", 34)
	for st in ["normal", "hover", "pressed"]:
		var sb := _caja_plana(MAGENTA.lightened(0.12 if st == "hover" else 0.0).darkened(0.15 if st == "pressed" else 0.0))
		sb.corner_radius_bottom_left = 14
		x.add_theme_stylebox_override(st, sb)
	x.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	x.size = Vector2(110, 68)
	x.position = Vector2(vp.x - 110, 0)
	x.pressed.connect(cerrar)
	_capa.add_child(x)
	# el titulo
	var mx := maxf(24.0, vp.x * 0.12)
	var barras := Control.new()
	barras.position = Vector2(mx, 34)
	barras.size = Vector2(46, 34)
	barras.draw.connect(func():
		for i in 3:
			var h: float = [14.0, 30.0, 22.0][i]
			barras.draw_rect(Rect2(i * 15.0, 34.0 - h, 11.0, h), Color.WHITE))
	_capa.add_child(barras)
	var tit := _cursiva("POSICIONES", 40, Color.WHITE)
	tit.position = Vector2(mx + 54, 22)
	_capa.add_child(tit)
	# las dos columnas
	var arriba := 96.0
	var alto := vp.y - arriba - 18.0
	var ancho_der := clampf(vp.x * 0.26, 300.0, 520.0)
	var ancho_izq := vp.x - mx * 2.0 - ancho_der - 40.0
	var tabla := PanelContainer.new()
	tabla.add_theme_stylebox_override("panel", _caja_plana(VIOLETA_TABLA, 4))
	tabla.position = Vector2(mx, arriba)
	tabla.size = Vector2(ancho_izq, alto)
	_capa.add_child(tabla)
	_ancho_filas = ancho_izq - 10.0
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	tabla.add_child(col)
	col.add_child(_cabecera_tabla(ancho_izq))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(sc)
	_filas_caja = VBoxContainer.new()
	_filas_caja.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filas_caja.add_theme_constant_override("separation", 0)
	sc.add_child(_filas_caja)
	_capa.add_child(_ficha_derecha(Vector2(mx + ancho_izq + 40.0, arriba), Vector2(ancho_der, alto)))
	_pintar_tabla()
	_t = 0.0


func _cabecera_tabla(ancho: float) -> Control:
	var cab := PanelContainer.new()
	cab.add_theme_stylebox_override("panel", _caja_plana(VIOLETA_CAB))
	cab.custom_minimum_size = Vector2(0, 26)
	var h := HBoxContainer.new()
	cab.add_child(h)
	for c in [["PUESTO", 0.11], ["LISTA DE JUGADORES", 0.53], ["PUNTOS", 0.20], ["PREMIO", 0.16]]:
		var l := _cursiva(String(c[0]), 14, Color(0.78, 0.82, 1.0), 800)
		l.custom_minimum_size = Vector2(ancho * float(c[1]), 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if String(c[0]) != "LISTA DE JUGADORES" else HORIZONTAL_ALIGNMENT_LEFT
		h.add_child(l)
	return cab


func _ficha_derecha(pos: Vector2, tam: Vector2) -> Control:
	var t: Dictionary = datos.get("torneo", {})
	var p := PanelContainer.new()
	var sb := _caja_plana(Color8(132, 82, 214))
	sb.corner_radius_top_left = 26
	sb.corner_radius_bottom_right = 26
	p.add_theme_stylebox_override("panel", sb)
	p.position = pos
	p.size = tam
	var m := MarginContainer.new()
	for k in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + k, 20)
	p.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	v.add_child(_cursiva("TORNEO SEMANAL #%d" % int(t.get("n", 0)), 30, Color.WHITE))
	_info_estado = _texto("", 20, Color(0.82, 0.78, 1.0), 800)
	v.add_child(_info_estado)
	_cuenta_atras = _info_estado
	var modo := _cursiva(String(t.get("titulo", "")), 22, AMARILLO_TU, 900)
	modo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(modo)
	# los premios del podio, uno por fila con su color
	var premios: Dictionary = t.get("premios", {})
	for i in 3:
		var pr: Dictionary = premios.get(str(i + 1), {})
		var fila := HBoxContainer.new()
		fila.add_theme_constant_override("separation", 10)
		var num := _cursiva("%d" % (i + 1), 26, PUESTO_COLORES[i][0], 900)
		num.custom_minimum_size = Vector2(26, 0)
		fila.add_child(num)
		var l := _texto(_premio_texto(pr), 15, Color.WHITE, 700)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fila.add_child(l)
		v.add_child(fila)
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.18)
	sep.custom_minimum_size = Vector2(0, 2)
	v.add_child(sep)
	var d := _texto("Participa en las partidas del torneo, gana puntos y llega a lo más alto para obtener grandes recompensas. "
		+ String(t.get("puntos", "")), 15, Color.WHITE, 600)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	return p


func cerrar() -> void:
	if _capa:
		Audio.ui("atras", -6.0)
		_capa.queue_free()
	_capa = null
	_lista = null
	_filas_caja = null
	_cuenta_atras = null
	_info_estado = null
	_yo = null


func _premio_texto(p: Dictionary) -> String:
	var out: Array = []
	if int(p.get("cubos", 0)) > 0:
		out.append("%d cubos de fuerza" % int(p["cubos"]))
	if int(p.get("cofres", 0)) > 0:
		out.append("%d %s %s" % [int(p["cofres"]), "cofre" if int(p["cofres"]) == 1 else "cofres", RAREZAS[clampi(int(p.get("rareza", 0)), 0, 5)]])
	if int(p.get("oro", 0)) > 0:
		out.append("%d de oro" % int(p["oro"]))
	return " + ".join(out) if not out.is_empty() else "—"


func _mi_nombre() -> String:
	return String(Cuenta.perfil.get("nombre", "")) if Cuenta.conectado() else ""


func _pintar_tabla() -> void:
	if _filas_caja == null:
		return
	for c in _filas_caja.get_children():
		c.queue_free()
	var t: Dictionary = datos.get("torneo", {})
	var top: Array = t.get("top", [])
	var yo = t.get("yo")
	var mi_pos := int(yo["pos"]) if typeof(yo) == TYPE_DICTIONARY else -1
	var premios: Dictionary = t.get("premios", {})
	var ancho := _ancho_filas
	if top.is_empty():
		var ant = datos.get("anterior")
		var aviso := _cursiva("Todavía nadie sumó puntos. ¡Sé el primero!" if String(t.get("estado", "")) == "activo"
			else "La tabla se llena cuando empiece el torneo.", 20, Color(1, 1, 1, 0.85), 800)
		aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		aviso.custom_minimum_size = Vector2(0, 70)
		aviso.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_filas_caja.add_child(aviso)
		if typeof(ant) == TYPE_DICTIONARY and not (ant.get("top", []) as Array).is_empty():
			var at := _cursiva("GANADORES DEL TORNEO #%d" % int(ant.get("n", 0)), 18, AMARILLO_TU, 900)
			at.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_filas_caja.add_child(at)
			var i := 0
			for f in ant["top"]:
				_filas_caja.add_child(_fila(i, String(f.get("nombre", "")), int(f.get("puntos", 0)), -1, false, {}, ancho))
				i += 1
		return
	for i in top.size():
		var f: Dictionary = top[i]
		_filas_caja.add_child(_fila(i, String(f.get("nombre", "")), int(f.get("puntos", 0)), int(f.get("partidas", 0)),
			i + 1 == mi_pos, premios.get(str(i + 1), {}), ancho))
	# si estoy mas abajo de lo que se ve, mi fila al final
	if mi_pos > top.size():
		_filas_caja.add_child(_fila(mi_pos - 1, _mi_nombre() if _mi_nombre() != "" else "TÚ", int(yo["puntos"]), -1, true, {}, ancho))


func _fila(i: int, nombre: String, puntos: int, partidas: int, soy_yo: bool, premio: Dictionary, ancho: float) -> Control:
	var alto := 62.0
	var fila := Control.new()
	fila.custom_minimum_size = Vector2(0, alto)
	var fondo := ColorRect.new()
	fondo.color = VIOLETA_FILA if i % 2 == 0 else VIOLETA_FILA2
	if soy_yo:
		fondo.color = Color8(170, 70, 200)
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fila.add_child(fondo)
	# el puesto: 1, 2 y 3 en su color con degradado; el resto, el numero en blanco
	var w_pues := ancho * 0.11
	if i < 3:
		var g := Gradient.new()
		g.set_color(0, PUESTO_COLORES[i][1])
		g.set_color(1, Color(PUESTO_COLORES[i][0], 0.0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_from = Vector2(0, 0.5)
		gt.fill_to = Vector2(1, 0.5)
		var tr := TextureRect.new()
		tr.texture = gt
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.position = Vector2.ZERO
		tr.size = Vector2(w_pues * 1.5, alto)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fila.add_child(tr)
	var num := _cursiva(str(i + 1), 34 if i < 3 else 26, Color.WHITE if i >= 3 else Color(1, 1, 1), 900)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.position = Vector2(0, 0)
	num.size = Vector2(w_pues, alto)
	fila.add_child(num)
	# el retrato: un cuadrado con el icono de usuario
	var av := PanelContainer.new()
	av.add_theme_stylebox_override("panel", _caja_plana(Color8(70, 160, 220) if i % 2 == 0 else Color8(60, 130, 200), 4, Color(0, 0, 0, 0.35), 2))
	av.position = Vector2(w_pues + 8, 6)
	av.size = Vector2(alto - 12, alto - 12)
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fila.add_child(av)
	var ic = IconoLobby.new()
	ic.icono = "usuario"
	ic.color = Color.WHITE
	ic.position = Vector2(w_pues + 14, 12)
	ic.size = Vector2(alto - 24, alto - 24)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fila.add_child(ic)
	# el nombre y debajo, las partidas
	var xn := w_pues + alto + 10
	var n := _texto(nombre, 20, Color.WHITE, 700)
	n.position = Vector2(xn, 7)
	n.size = Vector2(ancho * 0.48, 26)
	n.clip_text = true
	fila.add_child(n)
	if partidas >= 0:
		var sub := _cursiva("%d %s" % [partidas, "PARTIDA" if partidas == 1 else "PARTIDAS"], 13, Color(0.12, 0.08, 0.3), 900)
		sub.position = Vector2(xn, 34)
		fila.add_child(sub)
	# los puntos con la copa
	var x_pts := ancho * 0.64
	var copa := Control.new()
	copa.position = Vector2(x_pts, alto * 0.5 - 15)
	copa.size = Vector2(30, 30)
	copa.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copa.draw.connect(func(): _dibujar_copa(copa))
	fila.add_child(copa)
	var pts := _cursiva(str(puntos), 30, Color8(255, 214, 90), 900)
	pts.position = Vector2(x_pts + 36, alto * 0.5 - 21)
	pts.add_theme_color_override("font_outline_color", Color8(120, 60, 10))
	pts.add_theme_constant_override("outline_size", 6)
	fila.add_child(pts)
	# el premio: el cofre del color de su rareza (solo el podio)
	var x_pre := ancho * 0.84
	if not premio.is_empty():
		var cof = IconoLobby.new()
		cof.icono = "cofre"
		cof.color = COFRE_RAREZA[clampi(int(premio.get("rareza", 0)), 0, 5)]
		cof.position = Vector2(x_pre + ancho * 0.03, 8)
		cof.size = Vector2(alto - 16, alto - 16)
		cof.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fila.add_child(cof)
	else:
		var guion := _texto("—", 22, Color(1, 1, 1, 0.35), 700)
		guion.position = Vector2(x_pre + ancho * 0.06, alto * 0.5 - 15)
		fila.add_child(guion)
	# TU fila: borde amarillo y la cinta TÚ a la izquierda
	if soy_yo:
		var borde := Panel.new()
		borde.add_theme_stylebox_override("panel", _caja_plana(Color(0, 0, 0, 0), 0, AMARILLO_TU, 4))
		borde.set_anchors_preset(Control.PRESET_FULL_RECT)
		borde.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fila.add_child(borde)
		var cinta := PanelContainer.new()
		cinta.add_theme_stylebox_override("panel", _caja_plana(AMARILLO_TU, 3))
		cinta.position = Vector2(6, 4)
		cinta.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lt := _cursiva("TÚ", 13, Color8(40, 30, 10), 900)
		cinta.add_child(lt)
		fila.add_child(cinta)
	return fila


func _dibujar_copa(ci: Control) -> void:
	var oro_a := Color8(255, 214, 90)
	var oro_b := Color8(214, 140, 30)
	var c := Vector2(15, 13)
	for lado in [-1.0, 1.0]:
		ci.draw_arc(c + Vector2(lado * 10, -3), 5.0, 0, TAU, 14, oro_b, 3.0)
	var copa := PackedVector2Array([c + Vector2(-10, -11), c + Vector2(10, -11), c + Vector2(7, 2), c + Vector2(3, 6),
		c + Vector2(-3, 6), c + Vector2(-7, 2)])
	ci.draw_colored_polygon(copa, oro_a)
	ci.draw_rect(Rect2(c + Vector2(-2, 5), Vector2(4, 5)), oro_b)
	ci.draw_rect(Rect2(c + Vector2(-8, 10), Vector2(16, 5)), oro_b)


func _datos_prueba() -> void:
	_prueba = true
	var ahora := Time.get_unix_time_from_system() * 1000.0
	datos = {"ahora": ahora, "anterior": {"n": 3, "titulo": "BOMBA · DUST", "top": [{"nombre": "Mati_22", "puntos": 188}]},
		"torneo": {"n": 4, "titulo": "DUELO todos contra todos · CAFETERÍA URBANA", "estado": "activo",
			"inicio": ahora - 1800000, "fin": ahora + 3900000, "puntos": "Jugar una partida 2 · ganarla 10 · cada baja 1 (hasta 15) · plantar o desactivar la C4 3 (hasta 2). Cuentan las partidas con al menos 2 personas.",
			"premios": {"1": {"cubos": 30, "cofres": 3, "rareza": 2, "oro": 1500}, "2": {"cubos": 15, "cofres": 2, "rareza": 1, "oro": 750}, "3": {"cubos": 8, "cofres": 1, "rareza": 0, "oro": 400}},
			"yo": {"pos": 4, "puntos": 61},
			"top": [{"nombre": "TomiGG", "puntos": 142, "partidas": 7}, {"nombre": "Nahuel.ff", "puntos": 120, "partidas": 6},
				{"nombre": "Lucas10", "puntos": 96, "partidas": 5}, {"nombre": "Tú", "puntos": 61, "partidas": 3},
				{"nombre": "Mati_22", "puntos": 40, "partidas": 2}, {"nombre": "Benja.gg", "puntos": 33, "partidas": 2},
				{"nombre": "Sofi.exe", "puntos": 21, "partidas": 1}, {"nombre": "Lola.exe", "puntos": 14, "partidas": 1}]}}
	_pintar()


func _fotos(carpeta: String) -> void:
	await get_tree().create_timer(7.0).timeout
	get_viewport().get_texture().get_image().save_png(carpeta.path_join("torneo_lobby.png"))
	abrir()
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(carpeta.path_join("torneo_tabla.png"))
	print("[torneofoto] hecho en ", carpeta)
	get_tree().quit()
