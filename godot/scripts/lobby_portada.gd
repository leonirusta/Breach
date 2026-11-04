extends Control
## LA PORTADA DEL LOBBY (2026-09-30, pedido con captura de Pixel Gun 3D: "hazme el lobby lo más parecido que puedas con esa
## interfaz"). Todo lo que va encima del patio y del personaje, en la letra gorda en cursiva con borde de las pantallas
## nuevas (armeria_pantalla.gd, tienda_pantalla.gd...). Se dibuja en un lienzo de 720 de alto escalado a la pantalla; el
## ancho es el que haya (lo de la izquierda pegado a la izquierda, lo de la derecha a la derecha y el personaje en medio).
##
##   arriba izq.   el PERFIL: la cara del personaje, la estrella con tu nivel, tu nombre, tu rango (NOVATO, RECLUTA... sale
##                 del nivel de la cuenta) con la barra de experiencia, y tu arma principal. Abre la cuenta (lobby.abrir_cuenta).
##   debajo        COFRES (lo que en la captura es "Game Hub": el cofre del color del mejor, con cuantos hay; apagado sin
##                 ninguno) y TAREAS (el calendario con el dia de hoy y lo que falta para las nuevas; globo con las que hay por
##                 reclamar).
##   el cartel     PASE PRÉMIUM (azul, con el Comando, la Civil y la Urbana): abre el pase. Si ya es tuyo, PASE DE BATALLA.
##                 Debajo, cinco rayitas con lo que llevas de pase.
##   izquierda     ZOMBIS (donde la captura tiene EVENTOS: la ventana de supervivencia y los episodios) y TIENDA (con la cinta
##                 verde de GRATIS si hay regalos o algo del pase por reclamar).
##   abajo izq.    ARMERÍA, el boton violeta grande, con el globo de las cartas y las armas nuevas.
##   arriba der.   el oro, los cubos de fuerza y los diamantes (tocarlos lleva a la tienda o al personaje) y el MENU (☰:
##                 los ajustes).
##   derecha       EQUIPO (el "EQUIPO +" de la captura: FORMAR EQUIPO, lobby_grupo.gd; SALAS va dentro), AMIGOS (con las
##                 invitaciones que llegan),
##                 BUZÓN (los regalos del panel), CONTACTO (hablar con nosotros: contacto_pantalla.gd) y ESTADÍSTICAS.
##   abajo der.    la tarjeta del PASE DE BATALLA (el ticket, los dias que quedan, tu nivel y lo que hay por reclamar), la de
##                 tu PERSONAJE (donde la captura tiene la clasificatoria: su nivel, su nombre y su poder; abre su pantalla),
##                 la tira con el modo y el mapa elegidos y si juegas ONLINE, y ¡A LA BATALLA! (JUGAR: CENTRO: BATALLA).
##
## La monta el lobby (`_build_ui`), que es quien sabe abrir cada cosa: aqui solo se dibuja y se llama a `lobby`. Lo que
## cambia (saldos, globos, el reloj) se repinta sin rehacer nada (`refrescar`); si cambia el arma, la skin o el nivel, se
## rehace entera (es un momento: las fotos ya estan cocinadas).

const IconoLobby := preload("res://scripts/icono_lobby.gd")
const LobbyScript := preload("res://scripts/lobby.gd")

const ALTO := 720.0
## El ancho minimo del lienzo (plegable abierto: ver _montar) y desde donde es "lo de abajo" (_bajar_lo_de_abajo)
const ANCHO_MIN := 1100.0
const BAJO_DESDE := 470.0
var _h := 720.0
const TEXTO_JUGAR := "¡A LA BATALLA!"

## LOS COLORES, sacados de la captura
const TINTA := Color8(22, 16, 46)
const CAJA := Color(0.09, 0.06, 0.15, 0.56)
const CAJA_BORDE := Color(1.0, 1.0, 1.0, 0.07)
const VIOLETA := Color8(116, 100, 238)
const VIOLETA_CLARO := Color8(146, 132, 255)
const VIOLETA_OSCURO := Color8(80, 62, 196)
const AZUL := Color8(52, 122, 246)
const AZUL_CLARO := Color8(104, 178, 255)
const ROSA := Color8(222, 62, 124)
const ORO := Color8(236, 198, 72)
const AMARILLO := Color8(255, 208, 58)
const AMARILLO_CLARO := Color8(255, 226, 110)
const AMARILLO_OSCURO := Color8(208, 150, 18)
const AZUL_TINTA := Color8(28, 36, 62)
const ROJO := Color8(236, 40, 72)
const VERDE := Color8(46, 190, 80)
const LILA := Color8(190, 180, 248)
const MORADO := Color8(142, 94, 228)
const NARANJA := Color8(246, 160, 30)

## LOS RANGOS por nivel de cuenta (lo que va en cursiva bajo el nombre)
const RANGOS := [[1, "NOVATO"], [5, "RECLUTA"], [10, "VETERANO"], [20, "SARGENTO"], [30, "TENIENTE"], [40, "CAPITÁN"],
	[55, "COMANDANTE"], [75, "CORONEL"], [100, "GENERAL"], [150, "LEYENDA"]]

var lobby = null
## El texto de JUGAR ("CARGANDO..." mientras entra en la partida: lobby._poner_texto_jugar)
var texto_jugar := TEXTO_JUGAR:
	set(v):
		texto_jugar = v if v != "" else TEXTO_JUGAR
		if is_instance_valid(_jugar_dibujo):
			_jugar_dibujo.queue_redraw()
## Las invitaciones de amistad que han llegado estando en el lobby (el globo de AMIGOS)
var invitaciones := 0
## El boton de JUGAR (el lobby lo usa como `play_button`)
var jugar: Button = null

var _raiz: Control
var _w := 1280.0
var _k := 1.0
var _m := 22.0
var _f: SystemFont           ## la gruesa en cursiva (titulos, numeros)
var _fn: SystemFont          ## la gruesa derecha (nombre, COFRES, el reloj)
var _t := 0.0
var _clave := ""
var _primera := true
var _seg_dia := -1.0
var _reloj_seg := -1
var _refresco_t := 0.0
var _dibujos: Array = []            ## todo lo que se repinta al refrescar
var _globos: Dictionary = {}        ## nombre -> [dibujo del globo, ultimo numero]
var _jugar_dibujo: Control = null
var _nombre: Label = null
var _rango: Label = null
var _reloj: Label = null
var _cofre_icono: Control = null
var _pase_titulo: Label = null
var _estado_icono: Control = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_f = _fuente(900, true)
	_fn = _fuente(800, false)
	resized.connect(_montar)
	_montar()


static func _fuente(peso: int, cursiva: bool) -> SystemFont:
	return preload("res://scripts/fuentes.gd").de(peso, cursiva)      # compartida: ver fuentes.gd


## Lo que decide si hay que rehacerla entera (lo que sale en fotos cocinadas o cambia el tamaño de algo)
func _firma() -> String:
	var pj := NivelPersonaje.equipado()
	return "%s|%d|%s|%d|%s|%s" % [_arma_principal(), Settings.avatar_skin, pj, NivelPersonaje.nivel(pj), str(PaseBatalla.premium()), str(CaminoProgreso.siguiente().get("nivel", 0))]


## El arma de la ranura principal (como lobby._slot_weapon)
static func _arma_principal() -> String:
	var id := String(Settings.loadout.get("primary", ""))
	if id == "" or not Weapons.catalog().has(id):
		return Weapons.default_for("primary")
	return id


## REHACERLA ENTERA (al montar, al cambiar el tamaño y si cambia la firma)
func montar() -> void:
	_montar()


func _montar() -> void:
	if not is_inside_tree() or size.y < 10.0:
		return
	_k = size.y / ALTO
	_w = size.x / _k
	# EN UN PLEGABLE ABIERTO (casi cuadrado; 2026-09-30, pedido con captura: "se superponen: el dinero encima del perfil, el
	# pase premium...") el lienzo no baja de ANCHO_MIN: se escala por el ancho y lo que sobra de alto se queda entre lo de
	# arriba y lo de abajo, que baja a su sitio (`_bajar_lo_de_abajo`). En un movil normal no cambia nada.
	_h = ALTO
	if _w < ANCHO_MIN:
		_k = size.x / ANCHO_MIN
		_w = ANCHO_MIN
		_h = size.y / _k
	# LOS MARGENES CRECEN EN LOS MOVILES ALARGADOS (20:9): ahi las esquinas van redondeadas y con la camara metida
	_m = clampf(22.0 + (_w - 1280.0) * 0.12, 22.0, 64.0)
	_clave = _firma()
	var jugar_bloqueado := is_instance_valid(jugar) and jugar.disabled
	if is_instance_valid(_raiz):
		remove_child(_raiz)
		_raiz.queue_free()
	_dibujos.clear()
	_globos.clear()
	_raiz = Control.new()
	_raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.scale = Vector2(_k, _k)
	_raiz.size = Vector2(_w, _h)
	add_child(_raiz)
	if _seg_dia < 0.0:
		var m := Cuenta.misiones()
		_seg_dia = float(m["segundos_dia"]) if m.has("segundos_dia") else _segundos_hasta_manana()
	var izq: Array = []
	var der: Array = []
	izq.append(_montar_perfil())
	# EL PASE APAGADO DESDE EL PANEL (PaseBatalla.activo, 2026-10-17): sin el cartel, la tarjeta ni las TAREAS
	var pase_ok := PaseBatalla.activo()
	_pase_visto = pase_ok
	var cofres_tareas: Array = _montar_cofres_tareas()
	izq.append_array(cofres_tareas)
	var cartel := _montar_pase()
	cartel.visible = pase_ok
	izq.append(cartel)
	# (la tecla ZOMBIS se quito el 2026-10-13, pedido; _montar_zombis sigue abajo por si vuelve)
	izq.append(_montar_tienda())
	izq.append(_montar_codigo())
	izq.append(_montar_armeria())
	der.append_array(_montar_arriba_der())
	der.append_array(_montar_columna())
	var tarjeta := _montar_tarjeta_pase()
	tarjeta.visible = pase_ok
	der.append(tarjeta)
	der.append(_montar_personaje())
	der.append(_montar_estado())
	der.append(_montar_jugar())
	_bajar_lo_de_abajo(izq + der)
	if is_instance_valid(jugar):
		jugar.disabled = jugar_bloqueado
	if is_instance_valid(lobby):
		lobby.play_button = jugar
	if _primera:
		_primera = false
		_entrada(izq, Vector2(-70, 0))
		_entrada(der, Vector2(70, 0))
	refrescar()


## Con alto de sobra (plegable abierto), lo de la parte de abajo (TIENDA, ARMERÍA, la tarjeta del pase, el personaje, el
## modo y JUGAR: todo lo que empieza por debajo de BAJO_DESDE) baja a pegarse al borde de abajo, como en un movil normal.
func _bajar_lo_de_abajo(piezas: Array) -> void:
	var dy := _h - ALTO
	if dy <= 0.5:
		return
	for c in piezas:
		if c is Control and is_instance_valid(c) and (c as Control).position.y >= BAJO_DESDE:
			(c as Control).position.y += dy


## Lo que cambia sin rehacer nada: saldos, globos, el reloj, JUGAR. Si cambio la firma (arma, skin, nivel), se rehace.
func refrescar() -> void:
	if not is_instance_valid(_raiz):
		return
	if _firma() != _clave:
		_montar()
		return
	if is_instance_valid(_nombre):
		_nombre.text = _nombre_jugador()
	if is_instance_valid(_rango):
		_rango.text = rango(Cuenta.nivel())
	if is_instance_valid(_cofre_icono):
		var p := Cofres.pendientes()
		var mejor := 0
		for r in p:
			mejor = maxi(mejor, int(r))
		_cofre_icono.set("color", (Cofres.rareza(mejor)["color"] as Color) if not p.is_empty() else Color(0.72, 0.52, 0.3))
		_cofre_icono.modulate.a = 1.0 if not p.is_empty() else 0.55
	if is_instance_valid(_estado_icono):
		_estado_icono.set("icono", LobbyScript._icono_modo(LobbyScript._modo_de(Settings.map)))
	for d in _dibujos:
		if is_instance_valid(d):
			(d as CanvasItem).queue_redraw()
	# los globos: el numero, y un saltito si acaba de aparecer o de subir
	_globo_poner("cofres", Cofres.cuantos())
	_globo_poner("tareas", _tareas_por_reclamar())
	_globo_poner("armeria", _avisos_armeria())
	_globo_poner("amigos", invitaciones)
	_globo_poner("equipo", Grupo.tamano() if Grupo.en_grupo() else 0)      # cuantos sois en el equipo (verde)
	_globo_poner("buzon", Cuenta.regalos().size())
	_globo_poner("pase", PaseBatalla.pendientes())
	_globo_poner("personaje", 1 if NivelPersonaje.que_falta(NivelPersonaje.equipado()) == "" else 0)
	_globo_poner("tienda", 1 if _gratis() else 0)
	_poner_reloj()


func _process(dt: float) -> void:
	_t += dt
	if _seg_dia > 0.0:
		_seg_dia = maxf(0.0, _seg_dia - dt)
	if int(_seg_dia) != _reloj_seg:
		_poner_reloj()
	# de vez en cuando se miran los numeros (un cofre abierto, un regalo que llega, la cuenta que se refresca...)
	_refresco_t += dt
	if _refresco_t > 1.5 and is_visible_in_tree():
		_refresco_t = 0.0
		refrescar()


# ==================================================================================================================
# LOS DATOS
# ==================================================================================================================
static func rango(nivel: int) -> String:
	var r := String(RANGOS[0][1])
	for par in RANGOS:
		if nivel >= int(par[0]):
			r = String(par[1])
	return r


func _nombre_jugador() -> String:
	var n := Cuenta.nombre() if Cuenta.conectado() else String(Settings.player_name)
	return n if n != "" else "Jugador"


static func _segundos_hasta_manana() -> float:
	var t := Time.get_unix_time_from_system() - 3.0 * 3600.0
	return 86400.0 - fmod(t, 86400.0)


func _poner_reloj() -> void:
	_reloj_seg = int(_seg_dia)
	if not is_instance_valid(_reloj):
		return
	# la tecla del TORNEO: EN VIVO mientras dura (torneo_lobby.gd)
	var tl = lobby.get("torneo_lobby") if is_instance_valid(lobby) else null
	var vivo: bool = tl != null and is_instance_valid(tl) and tl.has_method("en_vivo") and tl.en_vivo()
	# SIN TORNEO, SIN COPA (2026-10-28, pedido): la tecla solo se ve mientras el torneo esta activo
	var bt := _reloj.get_parent() as Control
	if bt != null and bt.visible != vivo:
		bt.visible = vivo
	_reloj.text = "EN VIVO" if vivo else "TORNEO"
	_reloj.add_theme_color_override("font_color", Color8(255, 90, 90) if vivo else Color.WHITE)


## Las tareas hechas y sin cobrar (las de tareas_pantalla.gd: `hecha` y no `cobrada`)
func _tareas_por_reclamar() -> int:
	var m := Cuenta.misiones()
	var n := 0
	for clave in ["diarias", "semanales"]:
		var l = m.get(clave, [])
		if l is Array:
			for t in l:
				if t is Dictionary and bool(t.get("hecha", false)) and not bool(t.get("cobrada", true)):
					n += 1
	return n


## El globo de la ARMERÍA: las cartas por mirar o mejorar y las armas tuyas que aun no has visto (las NUEVO)
func _avisos_armeria() -> int:
	var n := Cartas.avisos()
	var vistas = Settings.presets_equipo.get("vistas", null)
	if vistas is Array:
		for id in Weapons.ids_equipables():
			if Settings.tengo_arma(id) and not (id in vistas):
				n += 1
	return n


## GRATIS en la TIENDA: lo mismo que su pestaña (tienda_pantalla._gratis): regalos o algo del pase por reclamar
func _gratis() -> bool:
	return not Cuenta.regalos().is_empty() or PaseBatalla.pendientes() > 0


# ==================================================================================================================
# LAS PIEZAS
# ==================================================================================================================
func _texto(t: String, tam: int, col: Color, contorno := 6, f: Font = null, borde := TINTA) -> Label:
	var l := Label.new()
	l.text = t
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", f if f != null else _f)
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", col)
	if contorno > 0:
		l.add_theme_color_override("font_outline_color", borde)
		l.add_theme_constant_override("outline_size", contorno)
		l.add_theme_color_override("font_shadow_color", Color(borde, 0.5))
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 3)
		l.add_theme_constant_override("shadow_outline_size", contorno)
	return l


## Un rotulo centrado en el ancho `ancho`, con la letra bajada si no cabe
func _rotulo(padre: Control, t: String, pos: Vector2, ancho: float, tam: int, col := Color.WHITE, f: Font = null,
		contorno := 6) -> Label:
	var l := _texto(t, _cabe(t, tam, ancho - 4.0, 11, f), col, contorno, f)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = pos
	l.size = Vector2(ancho, tam + 10)
	padre.add_child(l)
	return l


func _dibujo(pos: Vector2, tam: Vector2, pintar: Callable, padre: Node) -> _Dibujo:
	var d := _Dibujo.new()
	d.position = pos
	d.size = tam
	d.pintar = pintar
	padre.add_child(d)
	_dibujos.append(d)
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
	if pintar.is_valid():
		_dibujo(Vector2.ZERO, r.size, pintar, b)
	b.button_down.connect(func():
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2(0.93, 0.93), 0.06))
	b.button_up.connect(func():
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	b.mouse_entered.connect(func(): b.modulate = Color(1.08, 1.08, 1.08))
	b.mouse_exited.connect(func(): b.modulate = Color.WHITE)
	b.pressed.connect(func():
		if is_instance_valid(lobby):
			al_pulsar.call())
	return b


func _icono(nombre: String, col: Color, pos: Vector2, tam: float, padre: Node) -> Control:
	var ic := IconoLobby.new()
	ic.icono = nombre
	ic.color = col
	ic.position = pos
	ic.size = Vector2(tam, tam)
	padre.add_child(ic)
	return ic


## EL GLOBO ROJO de una esquina: un dibujo aparte (asi salta sin mover el boton) que se enseña con su numero
func _globo_en(nombre: String, padre: Control, centro: Vector2, r := 13.0, fondo := ROJO, texto_fijo := "") -> void:
	var d := _dibujo(centro - Vector2(r + 3, r + 3), Vector2(r + 3, r + 3) * 2.0, func(ci: Control):
		var n := int(_globos[nombre][1]) if _globos.has(nombre) else 0
		var t := texto_fijo if texto_fijo != "" else (str(n) if n < 100 else "99+")
		_globo(ci, ci.size * 0.5, r, t, fondo), padre)
	d.pivot_offset = d.size * 0.5
	d.visible = false
	_globos[nombre] = [d, -1]


func _globo_poner(nombre: String, n: int) -> void:
	if not _globos.has(nombre):
		return
	var d: Control = _globos[nombre][0]
	var antes := int(_globos[nombre][1])
	_globos[nombre][1] = n
	if not is_instance_valid(d):
		return
	d.visible = n > 0
	if n > 0 and n > antes:
		# el saltito: aparece desde cero y se pasa un poco
		d.scale = Vector2.ZERO
		var tw := d.create_tween()
		tw.tween_interval(0.35 if antes < 0 else 0.0)
		tw.tween_property(d, "scale", Vector2(1.25, 1.25), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(d, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## LA ENTRADA: cada bloque llega deslizandose desde su borde, uno detras de otro
func _entrada(piezas: Array, desde: Vector2) -> void:
	var i := 0
	for p in piezas:
		if not (p is Control) or not is_instance_valid(p):
			continue
		var c: Control = p
		var fin := c.position
		c.position = fin + desde
		c.modulate.a = 0.0
		var tw := c.create_tween().set_parallel(true)
		tw.tween_property(c, "position", fin, 0.38).set_delay(0.03 * i).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "modulate:a", 1.0, 0.25).set_delay(0.03 * i)
		i += 1


# ==================================================================================================================
# DIBUJAR
# ==================================================================================================================
func _txt(ci: CanvasItem, t: String, pos: Vector2, tam: int, col: Color, alin := HORIZONTAL_ALIGNMENT_LEFT,
		ancho := -1.0, contorno := 6, f: Font = null, borde := TINTA) -> void:
	var fuente: Font = f if f != null else _f
	if contorno > 0:
		ci.draw_string_outline(fuente, pos + Vector2(0, 3), t, alin, ancho, tam, contorno, Color(borde, 0.45))
		ci.draw_string_outline(fuente, pos, t, alin, ancho, tam, contorno, borde)
	ci.draw_string(fuente, pos, t, alin, ancho, tam, col)


func _base(cy: float, tam: int, f: Font = null) -> float:
	var fuente: Font = f if f != null else _f
	return cy + (fuente.get_ascent(tam) - fuente.get_descent(tam)) * 0.5


func _ancho(t: String, tam: int, f: Font = null) -> float:
	return (f if f != null else _f).get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x


func _cabe(t: String, tam: int, ancho: float, minimo: int, f: Font = null) -> int:
	var s := tam
	while s > minimo and _ancho(t, s, f) > ancho:
		s -= 1
	return s


static func _con_puntos(v: int) -> String:
	var t := str(absi(v))
	var out := ""
	while t.length() > 3:
		out = "." + t.substr(t.length() - 3) + out
		t = t.substr(0, t.length() - 3)
	return ("-" if v < 0 else "") + t + out


## LA FORMA DE TODO: un rectangulo con la esquina de abajo a la derecha cortada en diagonal (la de la captura)
static func _forma(r: Rect2, corte: float) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y - corte),
		Vector2(r.end.x - corte, r.end.y), Vector2(r.position.x, r.end.y)])


## Un poligono con degradado vertical (arriba -> abajo) o horizontal
static func _grad(ci: CanvasItem, pts: PackedVector2Array, a: Color, b: Color, vertical := true) -> void:
	var lo := INF
	var hi := -INF
	for p in pts:
		var v := p.y if vertical else p.x
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var cols := PackedColorArray()
	for p in pts:
		var v := p.y if vertical else p.x
		cols.append(a.lerp(b, (v - lo) / maxf(1.0, hi - lo)))
	ci.draw_polygon(pts, cols)


## Una caja oscura translucida (las de la captura) con su filo
func _caja_oscura(ci: Control, corte := 12.0) -> void:
	var r := Rect2(Vector2.ZERO, ci.size)
	var f := _forma(r, corte)
	ci.draw_colored_polygon(f, CAJA)
	var cerr := f.duplicate()
	cerr.append(f[0])
	ci.draw_polyline(cerr, CAJA_BORDE, 1.5, true)


## ¿Esta pasando ahora el brillo que cruza cada `cada` segundos? (asi solo se repinta mientras pasa)
func _pasando(cada: float, fase: float) -> bool:
	return fmod(_t + fase, cada) < 0.72


## EL BRILLO QUE CRUZA (ARMERÍA, los pases, JUGAR): una franja inclinada que pasa cada `cada` segundos, recortada a la forma
func _barrido(ci: Control, forma: PackedVector2Array, cada: float, fase: float, alfa := 0.3) -> void:
	var s := ci.size
	var u := fmod(_t + fase, cada) / 0.7
	if u > 1.0:
		return
	var x := lerpf(-s.y - 60.0, s.x + 40.0, u)
	var banda := PackedVector2Array([Vector2(x + s.y * 0.5, 0), Vector2(x + s.y * 0.5 + 34.0, 0), Vector2(x + 34.0, s.y),
		Vector2(x, s.y)])
	_recortado(ci, banda, forma, Color(1, 1, 1, alfa * sin(u * PI)))


## `banda` recortada a `forma` (sin los trozos de nada que deja el recorte en las esquinas: no se pueden triangular)
static func _recortado(ci: CanvasItem, banda: PackedVector2Array, forma: PackedVector2Array, col: Color) -> void:
	for p in Geometry2D.intersect_polygons(banda, forma):
		if p.size() < 3:
			continue
		# el recorte de dos convexos es convexo: un abanico desde el primer punto, sin pasar por el triangulador (que
		# se quejaba de los trozos casi planos de las esquinas)
		var idx := PackedInt32Array()
		for i in range(1, p.size() - 1):
			idx.append_array(PackedInt32Array([0, i, i + 1]))
		var cols := PackedColorArray()
		cols.resize(p.size())
		cols.fill(col)
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, p, cols)


## Un globo con un numero (el rojo de las esquinas)
func _globo(ci: CanvasItem, c: Vector2, r: float, t: String, fondo := ROJO) -> void:
	ci.draw_circle(c + Vector2(0, 2), r + 2.5, Color(0, 0.02, 0.15, 0.45))
	ci.draw_circle(c, r + 2.5, Color.WHITE)
	ci.draw_circle(c, r, fondo)
	if t == "":
		return
	var tam := int(r * 1.25) if t.length() < 3 else int(r * 0.95)
	_txt(ci, t, Vector2(c.x - r * 2.0, _base(c.y, tam, _fn)), tam, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r * 4.0, 3, _fn)


static func _estrella(c: Vector2, r: float, dentro := 0.48) -> PackedVector2Array:
	var p := PackedVector2Array()
	for k in 10:
		var a := deg_to_rad(-90.0 + 36.0 * k)
		p.append(c + Vector2(cos(a), sin(a)) * r * (1.0 if k % 2 == 0 else dentro))
	return p


static func _hex(c: Vector2, r: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	for k in 6:
		var a := deg_to_rad(60.0 * k - 90.0)
		p.append(c + Vector2(cos(a), sin(a)) * r)
	return p


static func _redondeada(r: Rect2, radio: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var rr := minf(radio, minf(r.size.x, r.size.y) * 0.5)
	var centros := [Vector2(r.end.x - rr, r.position.y + rr), Vector2(r.end.x - rr, r.end.y - rr),
		Vector2(r.position.x + rr, r.end.y - rr), Vector2(r.position.x + rr, r.position.y + rr)]
	for k in 4:
		for i in 5:
			var a := -PI * 0.5 + (k + i / 4.0) * PI * 0.5
			out.append(centros[k] + Vector2(cos(a), sin(a)) * rr)
	return out


## Cuadraditos de pixel (los de los carteles de la captura) sembrados en `r`
static func _pixeles(ci: CanvasItem, r: Rect2, n: int, semilla: int, col: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	for i in n:
		var lado := rng.randf_range(5.0, 13.0)
		var p := Vector2(rng.randf_range(r.position.x, r.end.x - lado), rng.randf_range(r.position.y, r.end.y - lado))
		ci.draw_rect(Rect2(p, Vector2(lado, lado)), Color(col, col.a * rng.randf_range(0.35, 1.0)))


func _moneda(ci: CanvasItem, c: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := PI / 8.0 + i * TAU / 8.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	var canto := PackedVector2Array()
	var dentro := PackedVector2Array()
	for p in pts:
		canto.append(p + Vector2(0, r * 0.2))
		dentro.append(c + (p - c) * 0.68)
	ci.draw_colored_polygon(canto, Color(0.70, 0.42, 0.02))
	ci.draw_colored_polygon(pts, Color(1.0, 0.80, 0.16))
	ci.draw_colored_polygon(dentro, Color(0.94, 0.64, 0.07))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.42), c + Vector2(r * 0.34, 0), c + Vector2(0, r * 0.42),
		c + Vector2(-r * 0.34, 0)]), Color(1.0, 0.94, 0.58))


func _gema(ci: CanvasItem, c: Vector2, r: float) -> void:
	var arriba := c.y - r * 0.62
	var medio := c.y - r * 0.10
	var abajo := c.y + r * 0.95
	var borde := PackedVector2Array([Vector2(c.x - r * 0.55, arriba), Vector2(c.x + r * 0.55, arriba), Vector2(c.x + r, medio),
		Vector2(c.x, abajo), Vector2(c.x - r, medio)])
	var filo := PackedVector2Array()
	for p in borde:
		filo.append(p + (p - c).normalized() * 1.6)
	ci.draw_colored_polygon(filo, Color(0.03, 0.28, 0.14))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(c.x - r, medio), Vector2(c.x + r, medio), Vector2(c.x, abajo)]),
		Color(0.10, 0.60, 0.33))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(c.x - r * 0.25, medio), Vector2(c.x + r, medio), Vector2(c.x, abajo)]),
		Color(0.18, 0.74, 0.42))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(c.x - r * 0.55, arriba), Vector2(c.x + r * 0.55, arriba),
		Vector2(c.x + r, medio), Vector2(c.x - r, medio)]), Color(0.42, 0.93, 0.60))


## Un candado blanco (el globo morado de CLANES)
func _candado(ci: CanvasItem, c: Vector2, r: float, col := Color.WHITE) -> void:
	ci.draw_arc(c + Vector2(0, -r * 0.18), r * 0.46, PI, TAU, 12, col, r * 0.22, true)
	ci.draw_colored_polygon(_redondeada(Rect2(c + Vector2(-r * 0.66, -r * 0.2), Vector2(r * 1.32, r * 1.0)), r * 0.16), col)
	ci.draw_circle(c + Vector2(0, r * 0.28), r * 0.14, MORADO.darkened(0.3))


# ==================================================================================================================
# ARRIBA A LA IZQUIERDA: el perfil
# ==================================================================================================================
func _montar_perfil() -> Control:
	var r := Rect2(_m, 10, 404, 84)
	# (2026-10-04) abre el CAMINO DEL PROGRESO; la CUENTA (en linea / sin conexion, entrar) esta dentro, arriba a la izquierda
	var b := _boton(r, _pintar_perfil, func(): lobby._abrir_camino(), _raiz)
	b.tooltip_text = ""
	# la cara: cabeza y hombros del retrato horneado, sobre su fondo azul
	var marco := Control.new()
	marco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marco.clip_contents = true
	marco.position = Vector2(3, 5)
	marco.size = Vector2(70, 70)
	b.add_child(marco)
	var i := clampi(Settings.avatar_skin, 0, LobbyScript.SKINS.size() - 1)
	var ruta := "res://avatar/retratos/%s.png" % String(LobbyScript.SKINS[i]["n"]).to_lower().replace(" ", "_")
	if ResourceLoader.exists(ruta):
		var at := AtlasTexture.new()
		at.atlas = LobbyScript._foto_mapa(ruta)
		at.region = Rect2(98, 6, 128, 128)
		var cara := TextureRect.new()
		cara.texture = at
		cara.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cara.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		cara.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cara.position = Vector2(-2, 2)
		cara.size = Vector2(74, 74)
		marco.add_child(cara)
	# el nombre y el rango
	_nombre = _texto(_nombre_jugador(), _cabe(_nombre_jugador(), 22, 190, 14, _fn), Color.WHITE, 5, _fn)
	_nombre.position = Vector2(98, 10)
	_nombre.size = Vector2(200, 30)
	b.add_child(_nombre)
	_rango = _texto(rango(Cuenta.nivel()), 16, LILA, 4)
	_rango.position = Vector2(98, 36)
	b.add_child(_rango)
	# LO QUE GANAS AL SUBIR (2026-10-31, pedido: "tiene que aparecer el arma que voy a ganar al nivel siguiente, no la
	# que tengo puesta"): el premio del proximo nivel del CAMINO DEL PROGRESO, asomando por la punta de la barra.
	# Un arma, en diagonal y en 3D; lo demas, su icono.
	var prox: Dictionary = CaminoProgreso.siguiente().get("cosa", {})
	var t_prox := str(prox.get("t", ""))
	if t_prox != "" and t_prox != "arma":
		var iconos := {"oro": ["moneda", Color8(255, 200, 60)], "diamantes": ["credito", Color8(90, 230, 160)],
			"cubos": ["cubo_fuerza", Color8(170, 120, 255)], "cofre": ["cofre", Color(0.72, 0.52, 0.3)],
			"carta": ["ticket", Color8(120, 200, 255)], "modelo": ["usuario", Color8(255, 214, 50)],
			"pintura": ["mira", Color8(120, 220, 120)], "mazo": ["martillo", Color8(230, 230, 230)]}
		var par: Array = iconos.get(t_prox, ["caja", Color.WHITE])
		_icono(String(par[0]), par[1], Vector2(352, 10), 40, b)
	elif is_instance_valid(lobby):
		var arma: Control = lobby._mini_arma_3d(str(prox.get("v", _arma_principal())), Vector2(170, 72))
		if arma is TextureRect:
			(arma as TextureRect).expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		arma.custom_minimum_size = Vector2.ZERO
		arma.position = Vector2(274, 4)
		arma.size = Vector2(128, 54)
		arma.pivot_offset = arma.size * 0.5
		arma.rotation = deg_to_rad(-24.0)
		b.add_child(arma)
	# la estrella con el nivel, encima de todo
	_dibujo(Vector2(62, 52), Vector2(40, 40), func(ci: Control):
		var c := ci.size * 0.5
		ci.draw_colored_polygon(_estrella(c + Vector2(0, 2), 19.0), Color(0.3, 0.16, 0.0, 0.45))
		ci.draw_colored_polygon(_estrella(c, 19.0), TINTA)
		ci.draw_colored_polygon(_estrella(c, 16.0), Color8(255, 214, 50))
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -16), c + Vector2(4, -5), c, c + Vector2(-4, -5)]), Color(1, 1, 1, 0.4))
		var nv := str(Cuenta.nivel())
		var tam := 15 if nv.length() < 3 else 12
		_txt(ci, nv, Vector2(0, _base(c.y + 1.5, tam, _fn)), tam, TINTA, HORIZONTAL_ALIGNMENT_CENTER, ci.size.x, 0, _fn), b)
	return b


func _pintar_perfil(ci: Control) -> void:
	# la barra oscura con el nombre (y abajo, la experiencia)
	var barra := Rect2(80, 6, 322, 70)
	var f := _forma(barra, 14.0)
	ci.draw_colored_polygon(f, CAJA)
	var tira := Rect2(98, 62, 286, 7)
	ci.draw_rect(tira, Color(0.0, 0.0, 0.05, 0.45))
	ci.draw_rect(Rect2(tira.position, Vector2(tira.size.x * clampf(Cuenta.progreso_nivel(), 0.0, 1.0), tira.size.y)), ORO)
	# el fondo azul de la cara
	var cuadro := Rect2(0, 2, 76, 76)
	ci.draw_colored_polygon(_redondeada(cuadro.grow(2.0), 9.0), TINTA)
	_grad(ci, _redondeada(cuadro, 8.0), Color8(96, 196, 255), Color8(40, 104, 230))


# ==================================================================================================================
# COFRES Y TAREAS (el "Game Hub" y el calendario de la captura)
# ==================================================================================================================
func _montar_cofres_tareas() -> Array:
	var bc := _boton(Rect2(_m - 4, 102, 100, 104), Callable(), func(): lobby._abrir_cofres(), _raiz)
	_cofre_icono = _icono("cofre", Color(0.72, 0.52, 0.3), Vector2(20, 6), 58, bc)
	_rotulo(bc, "COFRES", Vector2(0, 64), 100, 19, Color.WHITE, _fn, 5)
	_globo_en("cofres", bc, Vector2(82, 10))
	# un saltito cada poco (solo si hay alguno: apagado no llama la atencion)
	var ic := _cofre_icono
	ic.pivot_offset = Vector2(29, 56)
	var tw := ic.create_tween().set_loops()
	tw.tween_interval(2.6)
	tw.tween_callback(func():
		if Cofres.cuantos() <= 0:
			return
		var s := ic.create_tween()
		s.tween_property(ic, "scale", Vector2(1.16, 0.84), 0.08)
		s.tween_property(ic, "position:y", -2.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		s.parallel().tween_property(ic, "scale", Vector2(0.92, 1.1), 0.14)
		s.tween_property(ic, "position:y", 6.0, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		s.parallel().tween_property(ic, "scale", Vector2.ONE, 0.13)
		s.tween_property(ic, "scale", Vector2(1.1, 0.9), 0.07)
		s.tween_property(ic, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	# EL TORNEO SEMANAL (2026-10-18, pedido: "ahi, en vez del 18 y la hora, el icono de la copa"): era TAREAS
	var bt := _boton(Rect2(_m + 102, 102, 104, 104), _pintar_copa, func(): lobby._abrir_torneo(), _raiz)
	_reloj = _rotulo(bt, "TORNEO", Vector2(0, 64), 104, 19, Color.WHITE, _fn, 5)
	return [bc, bt]


## La copa del torneo: oro con asas, pie y la estrella
func _pintar_copa(ci: Control) -> void:
	var c := Vector2(ci.size.x * 0.5, 32)
	var oro_a := Color8(255, 214, 90)
	var oro_b := Color8(214, 140, 30)
	# asas
	for lado in [-1.0, 1.0]:
		var p := c + Vector2(lado * 21, -8)
		ci.draw_arc(p, 9.0, 0, TAU, 20, TINTA, 7.0)
		ci.draw_arc(p, 9.0, 0, TAU, 20, oro_b, 4.0)
	# la copa
	var copa := PackedVector2Array([c + Vector2(-20, -22), c + Vector2(20, -22), c + Vector2(15, 4), c + Vector2(6, 12),
		c + Vector2(-6, 12), c + Vector2(-15, 4)])
	var borde := PackedVector2Array()
	for v in copa:
		borde.append(c + (v - c) * 1.12)
	ci.draw_colored_polygon(borde, TINTA)
	_grad(ci, copa, oro_a, oro_b)
	# pie
	ci.draw_rect(Rect2(c + Vector2(-5, 11), Vector2(10, 9)), TINTA)
	ci.draw_rect(Rect2(c + Vector2(-3, 11), Vector2(6, 8)), oro_b)
	ci.draw_rect(Rect2(c + Vector2(-16, 19), Vector2(32, 9)), TINTA)
	ci.draw_rect(Rect2(c + Vector2(-14, 20), Vector2(28, 6)), oro_a)
	# la estrella
	var e := PackedVector2Array()
	for i in 10:
		var r := 8.0 if i % 2 == 0 else 3.6
		var a := -PI / 2.0 + i * PI / 5.0
		e.append(c + Vector2(0, -7) + Vector2(cos(a), sin(a)) * r)
	ci.draw_colored_polygon(e, Color.WHITE)


func _pintar_calendario(ci: Control) -> void:
	var c := Vector2(ci.size.x * 0.5, 34)
	var hoja := Rect2(c + Vector2(-25, -22), Vector2(50, 50))
	ci.draw_colored_polygon(_redondeada(hoja.grow(3.0), 9.0), TINTA)
	_grad(ci, _redondeada(hoja, 7.0), Color(1, 1, 1), Color8(196, 214, 255))
	var cab := Rect2(hoja.position, Vector2(hoja.size.x, 14))
	_grad(ci, _redondeada(cab, 5.0), Color8(120, 150, 255), Color8(76, 96, 238))
	ci.draw_rect(Rect2(cab.position + Vector2(0, 8), Vector2(cab.size.x, 6)), Color8(76, 96, 238))
	# las anillas
	for dx in [-12.0, 12.0]:
		var a := c + Vector2(dx, -24)
		ci.draw_rect(Rect2(a - Vector2(4, 6), Vector2(8, 13)), TINTA)
		ci.draw_rect(Rect2(a - Vector2(2.5, 4.5), Vector2(5, 10)), Color8(255, 186, 40))
	var dia := str(int(Time.get_date_dict_from_system()["day"]))
	_txt(ci, dia, Vector2(hoja.position.x, _base(c.y + 10, 27)), 27, Color8(58, 64, 200), HORIZONTAL_ALIGNMENT_CENTER,
		hoja.size.x, 0)


# ==================================================================================================================
# EL CARTEL DEL PASE PRÉMIUM
# ==================================================================================================================
func _montar_pase() -> Control:
	var r := Rect2(_m, 216, 340, 130)
	var b := _boton(r, _pintar_pase, func(): lobby._abrir_pase(), _raiz)
	# los tres personajes: la Urbana, el Comando delante y la Civil, que asoman un poco por arriba
	var clip := Control.new()
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.clip_contents = true
	clip.position = Vector2(0, -26)
	clip.size = Vector2(206, r.size.y + 26 - 2)
	b.add_child(clip)
	for par in [["urbana", Vector2(-18, 18), 150.0], ["civil", Vector2(78, 20), 146.0], ["comando", Vector2(26, 6), 168.0]]:
		var ruta := "res://avatar/retratos/%s.png" % String(par[0])
		if not ResourceLoader.exists(ruta):
			continue
		var tr := TextureRect.new()
		tr.texture = LobbyScript._foto_mapa(ruta)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var alto: float = par[2]
		tr.size = Vector2(alto * 312.0 / 344.0, alto)
		tr.position = par[1]
		clip.add_child(tr)
	# cubos de fuerza flotando alrededor, como los de la captura
	for q in [[Vector2(8, 30), 20.0, 0.0], [Vector2(150, 8), 16.0, 1.3], [Vector2(174, 92), 22.0, 2.1], [Vector2(-4, 104), 14.0, 0.7]]:
		var cubo := _icono("cubo_fuerza", Color(1, 1, 1, 0.9), q[0], q[1], b)
		var base_y: float = (q[0] as Vector2).y
		var tw := cubo.create_tween().set_loops()
		tw.tween_property(cubo, "position:y", base_y - 5.0, 1.1 + float(q[2]) * 0.2).set_trans(Tween.TRANS_SINE)
		tw.tween_property(cubo, "position:y", base_y, 1.1 + float(q[2]) * 0.2).set_trans(Tween.TRANS_SINE)
	var prem := PaseBatalla.premium()
	_pase_titulo = _texto("PASE DE\nBATALLA" if prem else "PASE\nPRÉMIUM", 34, Color.WHITE, 7, _f, Color8(18, 40, 120))
	_pase_titulo.add_theme_constant_override("line_spacing", -12)
	_pase_titulo.position = Vector2(170, 18)
	_pase_titulo.size = Vector2(170, 90)
	_pase_titulo.add_theme_font_size_override("font_size", _cabe("PRÉMIUM" if not prem else "BATALLA", 34, 160, 20))
	b.add_child(_pase_titulo)
	# el brillo que cruza (va encima de los personajes)
	var barrido := _dibujo(Vector2.ZERO, r.size, func(ci: Control): _barrido(ci, _forma(Rect2(Vector2.ZERO, ci.size), 22.0), 4.2, 0.6), b)
	barrido.animado = true
	barrido.vivo = func() -> bool: return _pasando(4.2, 0.6)
	# las cinco rayas de debajo: lo que llevas de pase
	_dibujo(Vector2(r.position.x, r.end.y + 6), Vector2(r.size.x, 8), func(ci: Control):
		var hechos := int(floor(5.0 * clampf(float(PaseBatalla.nivel() - 1) / float(PaseBatalla.NIVELES - 1), 0.0, 1.0) + 0.001))
		var ancho := (ci.size.x - 8.0 * 4.0) / 5.0
		for k in 5:
			var x0 := k * (ancho + 8.0)
			var p := PackedVector2Array([Vector2(x0 + 4, 0), Vector2(x0 + ancho + 4, 0), Vector2(x0 + ancho - 4, 7), Vector2(x0 - 4, 7)])
			ci.draw_colored_polygon(p, Color(1, 1, 1, 0.92) if k < hechos or (k == 0 and hechos == 0) else Color(1, 1, 1, 0.32)), _raiz)
	return b


func _pintar_pase(ci: Control) -> void:
	var r := Rect2(Vector2.ZERO, ci.size)
	var f := _forma(r, 22.0)
	var sombra := PackedVector2Array()
	for p in f:
		sombra.append(p + Vector2(0, 4))
	ci.draw_colored_polygon(sombra, Color(0.05, 0.1, 0.4, 0.35))
	_grad(ci, f, AZUL, AZUL_CLARO, false)
	_grad(ci, PackedVector2Array([Vector2(0, 0), Vector2(r.size.x, 0), Vector2(r.size.x, r.size.y * 0.5), Vector2(0, r.size.y * 0.5)]),
		Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.0))
	_pixeles(ci, Rect2(170, 70, 150, 50), 16, 7, Color(0.8, 0.92, 1.0, 0.28))
	_pixeles(ci, Rect2(4, 4, 160, 110), 10, 11, Color(0.2, 0.4, 0.95, 0.4))
	var cerr := f.duplicate()
	cerr.append(f[0])
	ci.draw_polyline(cerr, Color(0.8, 0.92, 1.0, 0.7), 2.0, true)


# ==================================================================================================================
# ZOMBIS Y TIENDA (las teclas cuadradas de la izquierda)
# ==================================================================================================================
func _montar_tecla_izq(r: Rect2, nombre: String, pintar: Callable, al_pulsar: Callable) -> Control:
	var b := _boton(r, func(ci: Control):
		_caja_oscura(ci, 14.0)
		pintar.call(ci), al_pulsar, _raiz)
	_rotulo(b, nombre, Vector2(0, r.size.y - 32), r.size.x, 21)
	return b


func _montar_zombis() -> Control:
	var b := _montar_tecla_izq(Rect2(_m, 372, 124, 86), "ZOMBIS", _pintar_zombis, func(): lobby._ventana_zombis())
	var ic := _icono("biohazard", Color8(176, 255, 96), Vector2(42, 10), 40, b)
	b.move_child(ic, 1)
	return b


func _pintar_zombis(ci: Control) -> void:
	# el simbolo de biorriesgo en verde acido, con su sombra
	var c := Vector2(ci.size.x * 0.5, 30)
	ci.draw_circle(c + Vector2(0, 2), 25, Color(0.02, 0.1, 0.02, 0.5))
	ci.draw_circle(c, 25, Color8(30, 60, 24))
	ci.draw_circle(c, 22, Color8(56, 110, 34))


func _montar_tienda() -> Control:
	var r := Rect2(_m, 427, 124, 86)   # (en medio del hueco que dejo ZOMBIS, en 372, y del suyo, en 482)
	var b := _montar_tecla_izq(r, "TIENDA", func(ci: Control): pass, func(): lobby._abrir_tienda(""))
	var cofre := _icono("cofre", Color8(156, 92, 236), Vector2(35, 12), 52, b)
	b.move_child(cofre, 1)
	# el cofre rebosando de monedas (las de la captura)
	var oro := _dibujo(Vector2.ZERO, r.size, func(ci: Control):
		for q in [Vector2(46, 15), Vector2(78, 15), Vector2(56, 10), Vector2(68, 9), Vector2(62, 16)]:
			_moneda(ci, q, 7.5), b)
	b.move_child(oro, 2)
	# LA CINTA VERDE DE GRATIS (encima de la tecla, a la derecha, como en la captura)
	var d := _dibujo(Vector2(34, -14), Vector2(98, 28), func(ci: Control):
		var w := ci.size.x
		var p := PackedVector2Array([Vector2(8, 2), Vector2(w, 2), Vector2(w - 8, 26), Vector2(0, 26)])
		var borde := PackedVector2Array([Vector2(6, 0), Vector2(w + 3, 0), Vector2(w - 6, 28), Vector2(-3, 28)])
		ci.draw_colored_polygon(borde, Color.WHITE)
		ci.draw_colored_polygon(p, VERDE)
		_txt(ci, "GRATIS", Vector2(0, _base(14, 17)), 17, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, w, 4, _f, Color8(8, 70, 20)), b)
	d.pivot_offset = Vector2(49, 14)
	d.visible = false
	_globos["tienda"] = [d, -1]
	return b


## CANJEAR CODIGO (2026-10-15, pedido: "debajo de TIENDA, un boton para canjear codigos que hago desde el panel"):
## una llave dorada. Abre lobby._abrir_codigo.
func _montar_codigo() -> Control:
	var r := Rect2(_m, 522, 124, 80)
	var b := _montar_tecla_izq(r, "CÓDIGO", func(ci: Control):
		# la llave: anillo, tija y dos dientes, en oro con su sombra
		var c := Vector2(ci.size.x * 0.5 - 14, 26)
		for capa in [[Vector2(0, 2), Color(0, 0, 0, 0.45)], [Vector2.ZERO, Color8(255, 206, 60)]]:
			var o: Vector2 = capa[0]
			var col: Color = capa[1]
			ci.draw_arc(c + o, 10.0, 0.0, TAU, 20, col, 5.0, true)
			ci.draw_line(c + o + Vector2(10, 0), c + o + Vector2(36, 0), col, 5.0)
			ci.draw_line(c + o + Vector2(28, 0), c + o + Vector2(28, 9), col, 4.0)
			ci.draw_line(c + o + Vector2(34, 0), c + o + Vector2(34, 7), col, 4.0), func(): lobby._abrir_codigo())
	return b


# ==================================================================================================================
# ARMERÍA (el boton violeta de abajo)
# ==================================================================================================================
func _montar_armeria() -> Control:
	var r := Rect2(_m, 612, 290, 88)
	var b := _boton(r, _pintar_armeria, func(): lobby._show_tab(1), _raiz)
	var t := _texto("ARMERÍA", 46, Color.WHITE, 5, _f, Color8(60, 40, 160))
	t.position = Vector2(0, 8)
	t.size = Vector2(r.size.x - 10, 70)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_child(t)
	var barrido := _dibujo(Vector2.ZERO, r.size, func(ci: Control): _barrido(ci, _forma(Rect2(Vector2.ZERO, ci.size), 24.0), 3.6, 0.0, 0.26), b)
	barrido.animado = true
	barrido.vivo = func() -> bool: return _pasando(3.6, 0.0)
	_globo_en("armeria", b, Vector2(r.size.x - 6, 6), 15.0)
	return b


func _pintar_armeria(ci: Control) -> void:
	var r := Rect2(Vector2.ZERO, ci.size)
	var f := _forma(r, 24.0)
	var sombra := PackedVector2Array()
	for p in f:
		sombra.append(p + Vector2(0, 5))
	ci.draw_colored_polygon(sombra, Color(0.1, 0.05, 0.3, 0.4))
	ci.draw_colored_polygon(f, VIOLETA_OSCURO)
	var cara := _forma(Rect2(0, 0, r.size.x, r.size.y - 6), 21.0)
	_grad(ci, cara, VIOLETA_CLARO, VIOLETA)
	# las dos franjas claras en diagonal
	for x0 in [96.0, 150.0]:
		var banda := PackedVector2Array([Vector2(x0 + 30, 0), Vector2(x0 + 52, 0), Vector2(x0 + 22, r.size.y), Vector2(x0, r.size.y)])
		_recortado(ci, banda, cara, Color(1, 1, 1, 0.07))
	ci.draw_line(Vector2(2, 1.5), Vector2(r.size.x - 2, 1.5), Color(1, 1, 1, 0.45), 2.0)


# ==================================================================================================================
# ARRIBA A LA DERECHA: el saldo y el menu
# ==================================================================================================================
func _montar_arriba_der() -> Array:
	var der := _w - _m
	var menu := _boton(Rect2(der - 62, 12, 62, 52), func(ci: Control):
		_caja_oscura(ci, 10.0)
		for k in 3:
			var y := 15.0 + k * 10.0
			ci.draw_colored_polygon(_redondeada(Rect2(16, y, 30, 5.5), 2.5), Color.WHITE), func(): lobby._show_tab(3), _raiz)
	menu.tooltip_text = "Ajustes"
	var ancho := 420.0
	var x0 := der - 62 - 14 - ancho
	var barra := _dibujo(Vector2(x0, 12), Vector2(ancho, 52), func(ci: Control): _caja_oscura(ci, 12.0), _raiz)
	barra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# tres huecos que se pueden tocar: el oro y los diamantes llevan a la tienda; los cubos, a subir el personaje
	var huecos := [func(): lobby._abrir_tienda("diamantes"), func(): lobby._abrir_personaje(), func(): lobby._abrir_tienda("diamantes")]
	for k in 3:
		var hb := _boton(Rect2(k * ancho / 3.0, 0, ancho / 3.0, 52), _pintar_saldo.bind(k), huecos[k], barra)
		if k == 1:
			_icono("cubo_fuerza", Color.WHITE, Vector2(14, 7), 38, hb)
	return [menu, barra]


func _pintar_saldo(ci: Control, k: int) -> void:
	var c := Vector2(32, 26)
	if k == 0:
		_moneda(ci, c + Vector2(0, -2), 15.0)
	elif k == 2:
		_gema(ci, c + Vector2(0, -1), 15.0)
	var v: int = [Cuenta.monedas(), Settings.saldo_cubos(), Cuenta.creditos()][k]
	var t := _con_puntos(v)
	var tam := _cabe(t, 25, ci.size.x - 62.0, 14)
	_txt(ci, t, Vector2(56, _base(26, tam)), tam, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 5)


# ==================================================================================================================
# LA COLUMNA DE LA DERECHA: EQUIPO, AMIGOS, BUZÓN, CONTACTO y ESTADÍSTICAS
# ==================================================================================================================
func _montar_columna() -> Array:
	var der := _w - _m
	var out: Array = []
	var an := 120.0
	var al := 84.0
	# EQUIPO (el "+" de la captura): FORMAR EQUIPO con tus amigos conectados (lobby_grupo.gd). SALAS sigue dentro.
	var salas := _tecla_der(Rect2(der - an - 16 - 118, 76, 118, al), "EQUIPO", _glifo_mas, func():
		if is_instance_valid(lobby.get("_grupo")):
			lobby._grupo.abrir()
		else:
			lobby._show_tab(4))
	_globo_en("equipo", salas, Vector2(118 - 4, 6), 13.0, VERDE)
	out.append(salas)
	var amigos := _tecla_der(Rect2(der - an, 76, an, al), "AMIGOS", Callable(), func():
		invitaciones = 0
		lobby._abrir_amigos())
	_icono("amigos", Color.WHITE, Vector2(an * 0.5 - 22, 8), 44, amigos)
	_globo_en("amigos", amigos, Vector2(an - 4, 6))
	out.append(amigos)
	var buzon := _tecla_der(Rect2(der - an, 178, an, al), "BUZÓN", _glifo_sobre, func(): lobby._abrir_buzon())
	# GALERIA (2026-10-13, pedido): las fotos sacadas en partida (galeria_fotos.gd), a la izquierda del BUZON
	out.append(_tecla_der(Rect2(der - an - 16 - 118, 178, 118, al), "GALERÍA", _glifo_camara, func(): lobby._abrir_galeria()))
	_globo_en("buzon", buzon, Vector2(an - 4, 6))
	out.append(buzon)
	# CONTACTO (antes CLANES, 2026-10-01, pedido: "que los jugadores puedan enviar un reporte o hablar con nosotros para
	# mejorar el juego"): HABLAR CON NOSOTROS (contacto_pantalla.gd), con un corazon rojo en la esquina
	var contacto := _tecla_der(Rect2(der - an, 280, an, al), "CONTACTO", _glifo_charla, func(): lobby._abrir_contacto())
	_dibujo(Vector2(an - 22, -10), Vector2(34, 34), func(ci: Control):
		var c := ci.size * 0.5
		ci.draw_circle(c + Vector2(0, 2), 15.5, Color(0, 0.02, 0.15, 0.4))
		ci.draw_circle(c, 15.5, Color.WHITE)
		ci.draw_circle(c, 13.0, ROSA)
		_corazon(ci, c + Vector2(0, 1), 8.0, Color.WHITE), contacto)
	out.append(contacto)
	out.append(_tecla_der(Rect2(der - an, 382, an, al), "ESTADÍSTICAS", _glifo_lista, func(): lobby._show_tab(7)))
	return out


func _tecla_der(r: Rect2, nombre: String, glifo: Callable, al_pulsar: Callable) -> Button:
	var b := _boton(r, func(ci: Control):
		_caja_oscura(ci, 12.0)
		if glifo.is_valid():
			glifo.call(ci, Vector2(ci.size.x * 0.5, 30)), al_pulsar, _raiz)
	_rotulo(b, nombre, Vector2(0, r.size.y - 34), r.size.x, 20)
	return b


func _glifo_mas(ci: Control, c: Vector2) -> void:
	for s in [Vector2(7, 22), Vector2(22, 7)]:
		ci.draw_colored_polygon(_redondeada(Rect2(c - s + Vector2(0, 2), s * 2.0), 3.0), Color(0, 0, 0.1, 0.35))
		ci.draw_colored_polygon(_redondeada(Rect2(c - s, s * 2.0), 3.0), Color.WHITE)


func _glifo_sobre(ci: Control, c: Vector2) -> void:
	var r := Rect2(c - Vector2(22, 15), Vector2(44, 30))
	ci.draw_colored_polygon(_redondeada(r, 4.0), Color.WHITE)
	ci.draw_polyline(PackedVector2Array([r.position + Vector2(3, 3), c + Vector2(0, 3), Vector2(r.end.x - 3, r.position.y + 3)]),
		Color(0.2, 0.14, 0.34), 3.5, true)


## Una camara de fotos (GALERIA)
func _glifo_camara(ci: Control, c: Vector2) -> void:
	var cuerpo := Rect2(c - Vector2(22, 12), Vector2(44, 28))
	ci.draw_colored_polygon(_redondeada(Rect2(cuerpo.position + Vector2(0, 2), cuerpo.size), 5.0), Color(0, 0, 0.1, 0.35))
	ci.draw_colored_polygon(_redondeada(Rect2(c - Vector2(9, 17), Vector2(18, 8)), 2.0), Color.WHITE)
	ci.draw_colored_polygon(_redondeada(cuerpo, 5.0), Color.WHITE)
	ci.draw_circle(c + Vector2(0, 2), 9.5, Color(0.2, 0.14, 0.34))
	ci.draw_circle(c + Vector2(0, 2), 6.0, Color.WHITE)
	ci.draw_circle(c + Vector2(15, -7), 2.5, Color(0.2, 0.14, 0.34))


## Un globo de dialogo con tres puntos (CONTACTO)
func _glifo_charla(ci: Control, c: Vector2) -> void:
	var r := Rect2(c - Vector2(22, 17), Vector2(44, 28))
	ci.draw_colored_polygon(_redondeada(Rect2(r.position + Vector2(0, 2), r.size), 9.0), Color(0, 0, 0.1, 0.35))
	ci.draw_colored_polygon(_redondeada(r, 9.0), Color.WHITE)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-12, 9), c + Vector2(-2, 9), c + Vector2(-15, 20)]), Color.WHITE)
	for k in 3:
		ci.draw_circle(c + Vector2(-11 + k * 11, -3), 3.4, Color(0.2, 0.14, 0.34))


## Un corazon de `tam` de radio aproximado
func _corazon(ci: Control, c: Vector2, tam: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 40:
		var t := TAU * float(i) / 40.0
		var x := 16.0 * pow(sin(t), 3)
		var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
		pts.append(c + Vector2(x, y) * (tam / 16.0))
	ci.draw_colored_polygon(pts, color)


func _glifo_escudo(ci: Control, c: Vector2) -> void:
	var p := PackedVector2Array([c + Vector2(-19, -19), c + Vector2(19, -19), c + Vector2(19, 4), c + Vector2(0, 20), c + Vector2(-19, 4)])
	ci.draw_colored_polygon(p, Color.WHITE)
	var q := PackedVector2Array([c + Vector2(-12, -12), c + Vector2(12, -12), c + Vector2(12, 1), c + Vector2(0, 11), c + Vector2(-12, 1)])
	ci.draw_colored_polygon(q, Color(0.2, 0.14, 0.34))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-12, -12), c + Vector2(0, -12), c + Vector2(0, 11), c + Vector2(-12, 1)]),
		Color(1, 1, 1, 0.22))


func _glifo_lista(ci: Control, c: Vector2) -> void:
	var r := Rect2(c - Vector2(17, 20), Vector2(34, 40))
	ci.draw_colored_polygon(_redondeada(r, 4.0), Color.WHITE)
	for k in 4:
		var y := r.position.y + 7.0 + k * 8.5
		ci.draw_rect(Rect2(r.position.x + 6, y, 5, 5), Color(0.2, 0.14, 0.34))
		ci.draw_rect(Rect2(r.position.x + 14, y + 1, 14, 3.5), Color(0.2, 0.14, 0.34))


# ==================================================================================================================
# ABAJO A LA DERECHA: el pase, el personaje, el modo y JUGAR
# ==================================================================================================================
var _pase_visto := true      ## como estaba el pase (activo) al montar: si el panel lo cambia, se rehace la portada


func _montar_tarjeta_pase() -> Control:
	var der := _w - _m
	var r := Rect2(der - 306, 484, 306, 74)
	var b := _boton(r, _pintar_tarjeta_pase, func(): lobby._abrir_pase(), _raiz)
	var titulo := "PASE DE BATALLA"
	var tt := _texto(titulo, _cabe(titulo, 26, 196, 16), Color.WHITE, 6)
	tt.position = Vector2(100, 4)
	b.add_child(tt)
	_dibujo(Vector2(-8, -12), Vector2(104, 80), _pintar_ticket, b)
	var barrido := _dibujo(Vector2.ZERO, r.size, func(ci: Control): _barrido(ci, _forma(Rect2(Vector2.ZERO, ci.size), 18.0), 5.0, 2.3, 0.28), b)
	barrido.animado = true
	barrido.vivo = func() -> bool: return _pasando(5.0, 2.3)
	_globo_en("pase", b, Vector2(r.size.x - 4, 4))
	return b


func _pintar_tarjeta_pase(ci: Control) -> void:
	var r := Rect2(Vector2.ZERO, ci.size)
	var f := _forma(r, 18.0)
	var sombra := PackedVector2Array()
	for p in f:
		sombra.append(p + Vector2(0, 4))
	ci.draw_colored_polygon(sombra, Color(0.3, 0.05, 0.2, 0.35))
	_grad(ci, f, ROSA, ORO, false)
	_grad(ci, PackedVector2Array([Vector2(0, 0), Vector2(r.size.x, 0), Vector2(r.size.x, r.size.y * 0.45), Vector2(0, r.size.y * 0.45)]),
		Color(1, 1, 1, 0.18), Color(1, 1, 1, 0.0))
	# la barra de lo que falta para el siguiente nivel del pase
	var tira := Rect2(62, r.size.y - 11, r.size.x - 84, 7)
	ci.draw_rect(tira, Color(0.3, 0.04, 0.16, 0.55))
	# (la barra es la EXP DEL PASE, no la del jugador: pase_batalla.gd)
	var par_p: Array = PaseBatalla.exp_en_nivel(PaseBatalla.experiencia())
	var fr := 1.0 if PaseBatalla.nivel() >= PaseBatalla.NIVELES else clampf(float(par_p[0]) / maxf(1.0, float(par_p[1])), 0.0, 1.0)
	ci.draw_rect(Rect2(tira.position, Vector2(tira.size.x * fr, tira.size.y)), Color(1.0, 0.94, 0.8))
	# (el reloj y los dias de la temporada se quitaron el 2026-10-13, como en la pantalla del pase)


## EL TICKET morado con la estrella (y debajo, el hexagono naranja con tu nivel de pase)
func _pintar_ticket(ci: Control) -> void:
	var c := Vector2(50, 36)
	ci.draw_set_transform(c, deg_to_rad(-7.0), Vector2.ONE)
	var r := Rect2(-42, -30, 84, 60)
	var borde := _redondeada(r.grow(3.0), 10.0)
	ci.draw_colored_polygon(borde, Color8(40, 30, 110))
	_grad(ci, _redondeada(r, 8.0), Color8(190, 150, 255), Color8(120, 84, 232))
	var dentro := Rect2(-32, -21, 64, 42)
	_grad(ci, _redondeada(dentro, 5.0), Color8(128, 96, 240), Color8(96, 66, 214))
	for s in [-1.0, 1.0]:
		ci.draw_circle(Vector2(s * 42.0, 0), 8.0, Color8(40, 30, 110))
		for k in 3:
			ci.draw_rect(Rect2(s * 36.5 - 2.0, -16 + k * 12.0, 4, 6), Color(1, 1, 1, 0.35))
	ci.draw_colored_polygon(_estrella(Vector2(0, 2), 19.0, 0.5), Color8(40, 30, 110))
	ci.draw_colored_polygon(_estrella(Vector2(0, 0), 17.0, 0.5), Color8(150, 236, 255))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(0, -17), Vector2(4, -6), Vector2(0, 0), Vector2(-4, -6)]), Color(1, 1, 1, 0.6))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# el nivel del pase en el hexagono
	var h := Vector2(18, 64)
	ci.draw_colored_polygon(_hex(h + Vector2(0, 2), 16.0), Color(0.2, 0.08, 0.0, 0.45))
	ci.draw_colored_polygon(_hex(h, 16.0), TINTA)
	ci.draw_colored_polygon(_hex(h, 13.5), NARANJA)
	ci.draw_colored_polygon(_hex(h + Vector2(0, -1), 10.5), Color8(255, 196, 64))
	var nv := str(clampi(PaseBatalla.nivel(), 1, PaseBatalla.NIVELES))
	_txt(ci, nv, Vector2(h.x - 20, _base(h.y, 15, _fn)), 15, TINTA, HORIZONTAL_ALIGNMENT_CENTER, 40, 0, _fn)


## LA TARJETA DEL PERSONAJE (donde la captura tiene la clasificatoria): su nivel en grande, su nombre y su poder
func _montar_personaje() -> Control:
	var der := _w - _m
	var r := Rect2(der - 306 - 14 - 154, 584, 154, 116)
	var b := _boton(r, _pintar_personaje, func(): lobby._abrir_personaje(), _raiz)
	var pj := NivelPersonaje.equipado()
	var nv := _texto("NV %d" % NivelPersonaje.nivel(pj), 40, Color.WHITE, 7)
	nv.position = Vector2(0, 2)
	nv.size = Vector2(r.size.x, 52)
	nv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_child(nv)
	var nombre := String(NivelPersonaje.datos(pj).get("nombre", "SOLDADO")).to_upper()
	_rotulo(b, nombre, Vector2(0, 52), r.size.x, 17, Color.WHITE, _f, 5)
	_globo_en("personaje", b, Vector2(r.size.x - 4, 4), 13.0, ROJO, "!")
	return b


func _pintar_personaje(ci: Control) -> void:
	var r := Rect2(Vector2.ZERO, ci.size)
	var f := _forma(r, 16.0)
	var sombra := PackedVector2Array()
	for p in f:
		sombra.append(p + Vector2(0, 4))
	ci.draw_colored_polygon(sombra, Color(0.2, 0.05, 0.3, 0.35))
	_grad(ci, f, Color8(150, 72, 236), Color8(214, 80, 196))
	_pixeles(ci, Rect2(4, 44, 60, 66), 18, 23, Color(0.36, 0.14, 0.66, 0.6))
	_pixeles(ci, Rect2(92, 4, 56, 30), 7, 31, Color(1, 1, 1, 0.16))
	var cerr := f.duplicate()
	cerr.append(f[0])
	ci.draw_polyline(cerr, Color(1, 1, 1, 0.35), 2.0, true)
	# el poder: el rayo y el numero
	var poder := _con_puntos(NivelPersonaje.poder(NivelPersonaje.equipado()))
	var tam := _cabe(poder, 21, r.size.x - 48.0, 13)
	var ancho := _ancho(poder, tam) + 24.0
	var x := r.size.x * 0.5 - ancho * 0.5
	var c := Vector2(x + 8, 92)
	var rayo := PackedVector2Array([c + Vector2(1, -11), c + Vector2(7, -11), c + Vector2(2, -2), c + Vector2(7, -2), c + Vector2(-5, 12),
		c + Vector2(-1, 2), c + Vector2(-6, 2)])
	var cerr_r := rayo.duplicate()
	cerr_r.append(rayo[0])
	ci.draw_polyline(cerr_r, TINTA, 4.0, true)
	ci.draw_colored_polygon(rayo, Color8(255, 220, 60))
	_txt(ci, poder, Vector2(x + 22, _base(92, tam)), tam, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 5)


## La tira de encima de JUGAR (donde la captura tiene la energia): el modo y el mapa elegidos y si se juega en linea
func _montar_estado() -> Control:
	var der := _w - _m
	var r := Rect2(der - 306, 584, 306, 30)
	var d := _dibujo(r.position, r.size, func(ci: Control):
		_caja_oscura(ci, 8.0)
		var modo := LobbyScript._modo_de(Settings.map)
		var t := "%s · %s" % [LobbyScript._titulo_modo(modo), Settings.map_title(Settings.map)]
		# EL SUBMODO, si el modo lo tiene (battle royale: SOLO / ESCUADRA; duelo: EQUIPOS / TODOS): net.gd "LOS SUBMODOS"
		var sub := Settings.submodo_de(Settings.map)
		if sub != "":
			var nombres := {"solo": "SOLO", "escuadra": "ESCUADRA", "equipos": "EQUIPOS", "todos": "TODOS CONTRA TODOS", "eliminacion": "ELIMINACIÓN", "ultimo": "ÚLTIMO EN PIE"}
			t = "%s · %s · %s" % [LobbyScript._titulo_modo(modo), String(nombres.get(sub, sub.to_upper())), Settings.map_title(Settings.map)]
		var linea := "SIN CONEXIÓN" if Settings.modo_pruebas else "ONLINE"
		var tam_l := 13
		var an_l := _ancho(linea, tam_l, _fn) + 24.0
		var tam := _cabe(t, 16, ci.size.x - 40.0 - an_l, 11)
		_txt(ci, t, Vector2(34, _base(15, tam)), tam, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, ci.size.x - 40.0 - an_l, 4)
		var col := Color8(255, 150, 60) if Settings.modo_pruebas else Color8(110, 236, 120)
		ci.draw_circle(Vector2(ci.size.x - an_l + 4, 15), 4.5, col)
		_txt(ci, linea, Vector2(ci.size.x - an_l + 13, _base(15, tam_l, _fn)), tam_l, col, HORIZONTAL_ALIGNMENT_LEFT, -1, 3, _fn), _raiz)
	_estado_icono = _icono(LobbyScript._icono_modo(LobbyScript._modo_de(Settings.map)), LILA, Vector2(9, 5), 20, d)
	return d


func _montar_jugar() -> Control:
	var der := _w - _m
	var r := Rect2(der - 306, 618, 306, 84)
	jugar = _boton(r, Callable(), func(): lobby._abrir_centro(), _raiz)
	_jugar_dibujo = _dibujo(Vector2.ZERO, r.size, _pintar_jugar, jugar)
	_jugar_dibujo.animado = true
	_jugar_dibujo.vivo = func() -> bool: return _pasando(3.0, 1.1)
	# late un poco, como el JUGAR de antes
	var lat := jugar.create_tween().set_loops()
	lat.tween_property(jugar, "scale", Vector2(1.03, 1.03), 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	lat.tween_property(jugar, "scale", Vector2.ONE, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return jugar


func _pintar_jugar(ci: Control) -> void:
	var r := Rect2(Vector2.ZERO, ci.size)
	var apagado := is_instance_valid(jugar) and jugar.disabled
	var f := _forma(r, 24.0)
	var sombra := PackedVector2Array()
	for p in f:
		sombra.append(p + Vector2(0, 5))
	ci.draw_colored_polygon(sombra, Color(0.35, 0.2, 0.0, 0.4))
	ci.draw_colored_polygon(f, AMARILLO_OSCURO if not apagado else Color8(120, 104, 70))
	var cara := _forma(Rect2(0, 0, r.size.x, r.size.y - 6), 21.0)
	_grad(ci, cara, AMARILLO_CLARO if not apagado else Color8(170, 160, 130), AMARILLO if not apagado else Color8(150, 138, 104))
	# las franjas claras (las de la captura) y el filo de arriba
	for x0 in [70.0, 118.0]:
		var banda := PackedVector2Array([Vector2(x0 + 40, 0), Vector2(x0 + 58, 0), Vector2(x0 + 18, r.size.y), Vector2(x0, r.size.y)])
		_recortado(ci, banda, cara, Color(1, 1, 1, 0.14))
	ci.draw_line(Vector2(2, 1.5), Vector2(r.size.x - 2, 1.5), Color(1, 1, 1, 0.6), 2.0)
	if not apagado:
		_barrido(ci, cara, 3.0, 1.1, 0.35)
	var t := texto_jugar
	var tam := _cabe(t, 42, r.size.x - 36.0, 18)
	_txt(ci, t, Vector2(0, _base((r.size.y - 6.0) * 0.5, tam)), tam, AZUL_TINTA, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 0)


# ==================================================================================================================
## Un Control que se pinta con una funcion (`pintar(self)`); `animado` lo repinta cada fotograma
class _Dibujo extends Control:
	var pintar: Callable
	var animado := false
	## si esta, solo se repinta mientras devuelva true (y una vez mas al acabar, para borrar lo ultimo)
	var vivo: Callable
	var _estaba := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_dt: float) -> void:
		if not animado or not is_visible_in_tree():
			return
		var ahora: bool = vivo.call() if vivo.is_valid() else true
		if ahora or _estaba:
			queue_redraw()
		_estaba = ahora

	func _draw() -> void:
		if pintar.is_valid():
			pintar.call(self)
