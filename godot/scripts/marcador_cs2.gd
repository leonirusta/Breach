extends Control
## EL MARCADOR DE BOMBA, COMO EL DE CS2 (2026-09-28, pedido: "hacelo como lo hace el juego de CS2, el mismo UI, solo
## en el modo bomba"). Arriba en el centro, compacto:
##
##   [retratos CT] [rondas CT] [ reloj ] [rondas T] [retratos T]
##
##   - el RELOJ es la cuenta atras de la ronda (Net.RONDA_S, 1:55 como en CS2); en los ultimos 10 s se pone rojo, y
##     con la C4 plantada el reloj desaparece y en su sitio late una C4 roja (en CS2 no se ve cuanto le queda);
##   - las RONDAS ganadas, en una caja azul (policias) y otra dorada (terroristas), siempre CT a la izquierda;
##   - un RETRATO por jugador de cada bando (personas y bots), que se apaga en gris al morir; el tuyo, con filo blanco;
##     el que lleva la C4, con la C4 en la esquina.
## Lo crea hud.build_match_hud en modo bomba (el de los demas modos es marcador_hud.gd) y se rellena solo.

const CT := Color(0.36, 0.56, 0.86)
const T := Color(0.9, 0.68, 0.24)
const TILE := Vector2(28, 36)
const HUECO := 3.0
const MAX_RETRATOS := 5
const ALTO := 36.0
const ANCHO_RELOJ := 84.0
const ANCHO_TANTEO := 46.0

var main_ref: Node = null
var _ct: Array = []          ## [[nombre, vivo, soy_yo, lleva_c4], ...]
var _t: Array = []
var _rondas := [0, 0]        ## [ct, t]
var _reloj := "1:55"
var _rojo := false
var _plantada := false
var _pulso := 0.0
var _mirar_t := 0.0
var _fuente: SystemFont
## LOS DE LA RONDA: un bot muerto desaparece de la escena, pero en CS2 su retrato se queda en gris hasta la ronda
## siguiente. Se recuerda a todos los que han salido en esta ronda, en el orden en que salieron (que no bailen).
var _conocidos: Dictionary = {}     ## nombre -> [equipo, soy_yo]
var _orden: Array = []
var _ronda_vista := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fuente = SystemFont.new()
	_fuente.font_names = PackedStringArray(["Segoe UI", "Roboto", "Arial", "sans-serif"])
	_fuente.font_weight = 700
	size = Vector2(_ancho(), ALTO + 4)


func _ancho() -> float:
	return ANCHO_RELOJ + 2.0 * (ANCHO_TANTEO + 2.0) + 2.0 * (6.0 + MAX_RETRATOS * (TILE.x + HUECO))


## (medicion de la auditoria, 2026-10-05: lo que cuesta este control por fotograma, clave Prof "ui.marcador")
func _process(dt: float) -> void:
	var _tp := Time.get_ticks_usec()
	_process_ui(dt)
	Prof.add("ui.marcador", Time.get_ticks_usec() - _tp)


func _process_ui(dt: float) -> void:
	_pulso += dt
	_mirar_t -= dt
	if _mirar_t <= 0.0:
		_mirar_t = 0.2
		_mirar()
		# Solo cambia lo que pinta al mirar (cada 0,2 s) o al latir la C4 plantada: quieto, la misma imagen.
		var f := [_rondas.duplicate(), _reloj, _rojo, _plantada, _ct.duplicate(true), _t.duplicate(true), size]
		if f != _firma:
			_firma = f
			queue_redraw()
	# --uisiempre = redibujar cada fotograma como antes.
	if _ui_siempre or _plantada:
		queue_redraw()


static var _ui_siempre: bool = "--uisiempre" in OS.get_cmdline_user_args()
var _firma: Array = []


## Lo que sale en el marcador: rondas, reloj, C4 y quien sigue vivo en cada bando.
func _mirar() -> void:
	_rondas = [Net.score_ct, Net.score_t]
	_plantada = is_instance_valid(Net.bomb_node)
	var elim: bool = Net.dm_mode and Net.es_dm_elim()
	_ffa = elim and Net.todos_contra_todos()
	if elim:
		# sin reloj de ronda: lo que lleva jugada
		var s0 := int((Time.get_ticks_msec() - Net.ronda_t0_ms) * 0.001) if Net.ronda_t0_ms > 0 else 0
		_reloj = "%d:%02d" % [s0 / 60, s0 % 60]
		_rojo = false
	elif Net.ronda_sin_tiempo:
		_reloj = "∞"        # sala sin limite de tiempo (Net.ronda_sin_tiempo)
		_rojo = false
	elif Net.ronda_t0_ms > 0:
		var pasado := (Time.get_ticks_msec() - Net.ronda_t0_ms) * 0.001
		var queda := maxf(0.0, Net.RONDA_S - pasado) if Net.round_live else Net.ronda_quedaba
		var s := int(ceil(queda))
		_reloj = "%d:%02d" % [s / 60, s % 60]
		_rojo = queda <= 10.0
	if Net.ronda_t0_ms != _ronda_vista:
		_ronda_vista = Net.ronda_t0_ms
		_conocidos.clear()
		_orden.clear()
	_ct.clear()
	_t.clear()
	_vivos_ahora.clear()
	# LAS PERSONAS (2026-10-15, pedido: "que los jugadores reales tengan un borde dorado"): yo y los de Net.players
	_personas = {Net.nombre_propio(): true}
	for idp in Net.players.keys():
		_personas[String(Net.players[idp].get("name", ""))] = true
	var vistos := {}
	var yo := Net.nombre_propio()
	var mi_eq := Net.my_team()
	var jugador = Net.local_player
	if mi_eq in [Net.TEAM_CT, Net.TEAM_T] or (_ffa and mi_eq != ""):
		var vivo := jugador == null or not is_instance_valid(jugador) or float(jugador.get("health")) > 0.0
		_meter(mi_eq, yo, vivo, true, Net.bomb_carrier != 0 and Net.bomb_carrier == multiplayer.get_unique_id())
		vistos[yo] = true
	for id in Net.players.keys():
		var p: Dictionary = Net.players[id]
		var n := String(p.get("name", ""))
		if n == "" or vistos.has(n) or int(id) == multiplayer.get_unique_id():
			continue
		vistos[n] = true
		_meter(Net.team_of(int(id)), n, not Net.is_dead(int(id)), false, Net.bomb_carrier == int(id))
	var enemigos = main_ref.get("enemies") if main_ref != null else null
	if enemigos != null and is_instance_valid(enemigos):
		for e in enemigos.get_children():
			if not is_instance_valid(e) or not ("team" in e):
				continue
			var n := String(e.get("nombre_marcador")) if e.get("nombre_marcador") != null else ""
			if n == "":
				n = String(e.get("bot_name")) if e.get("bot_name") != null else "BOT"
			if vistos.has(n):
				continue
			vistos[n] = true
			var c4 := bool(e.get("tiene_c4")) if e.get("tiene_c4") != null else false
			_meter(String(e.team), n, float(e.get("health")) > 0.0, false, c4)
	# los que ya no estan (bots muertos y borrados), en gris; y todo en el orden de siempre
	for n in _orden:
		if not _vivos_ahora.has(n):
			_vivos_ahora[n] = [false, false]
	if _ffa:
		# ULTIMO EN PIE: tu a la izquierda, los rivales a la derecha; el tanteo, cuantos siguen en pie
		var vivos_r := 0
		var yo_vivo := 0
		for n in _orden:
			var d: Array = _conocidos[n]
			var fila := [n, bool(_vivos_ahora[n][0]), bool(d[1]), false, _personas.has(n)]
			if bool(d[1]):
				_ct.append(fila)
				yo_vivo += 1 if fila[1] else 0
			else:
				_t.append(fila)
				vivos_r += 1 if fila[1] else 0
		# los vivos primero (con mas rivales que retratos, que se vea a los que quedan)
		_t.sort_custom(func(a, b): return bool(a[1]) and not bool(b[1]))
		_rondas = [yo_vivo, vivos_r]
		return
	for n in _orden:
		var d: Array = _conocidos[n]
		var fila := [n, bool(_vivos_ahora[n][0]), bool(d[1]), bool(_vivos_ahora[n][1]), _personas.has(n)]
		if String(d[0]) == Net.TEAM_CT:
			_ct.append(fila)
		elif String(d[0]) == Net.TEAM_T:
			_t.append(fila)


var _vivos_ahora: Dictionary = {}   ## nombre -> [vivo, lleva_c4] de esta pasada

var _ffa := false
var _personas: Dictionary = {}     ## nombre -> true: los jugadores de verdad (borde dorado)

func _meter(eq: String, nombre: String, vivo: bool, yo: bool, c4: bool) -> void:
	if not _ffa and not (eq in [Net.TEAM_CT, Net.TEAM_T]):
		return
	if not _conocidos.has(nombre) or String(_conocidos[nombre][0]) != eq:
		if not _conocidos.has(nombre):
			_orden.append(nombre)
		_conocidos[nombre] = [eq, yo]
	_vivos_ahora[nombre] = [vivo, c4]


func _draw() -> void:
	var _td := Time.get_ticks_usec()
	_draw_ui()
	Prof.add("ui.marcador.draw", Time.get_ticks_usec() - _td)


func _draw_ui() -> void:
	var c := size.x * 0.5
	var h := ALTO
	# el RELOJ: caja oscura; con la C4 plantada, roja y latiendo
	var rx := c - ANCHO_RELOJ * 0.5
	if _plantada:
		var k := 0.5 + 0.5 * sin(_pulso * 7.0)
		_caja(Rect2(rx, 0, ANCHO_RELOJ, h), Color(0.35 + 0.25 * k, 0.03, 0.03, 0.88))
		_c4(Vector2(c, h * 0.5), 1.0 + 0.08 * k)
	else:
		_caja(Rect2(rx, 0, ANCHO_RELOJ, h), Color(0.05, 0.06, 0.08, 0.8))
		_texto(_reloj, Rect2(rx, 0, ANCHO_RELOJ, h), 24, Color(1.0, 0.32, 0.3) if _rojo else Color.WHITE)
	# las RONDAS: CT a la izquierda, T a la derecha
	var ct_r := Rect2(rx - 2.0 - ANCHO_TANTEO, 0, ANCHO_TANTEO, h)
	var t_r := Rect2(rx + ANCHO_RELOJ + 2.0, 0, ANCHO_TANTEO, h)
	_tanteo(ct_r, CT, int(_rondas[0]))
	_tanteo(t_r, T, int(_rondas[1]))
	# los RETRATOS, hacia fuera: el primero pegado al tanteo
	for i in mini(_ct.size(), MAX_RETRATOS):
		var x := ct_r.position.x - 6.0 - (i + 1) * (TILE.x + HUECO) + HUECO
		_retrato(Rect2(x, 0, TILE.x, TILE.y), CT, _ct[i])
	for i in mini(_t.size(), MAX_RETRATOS):
		var x := t_r.end.x + 6.0 + i * (TILE.x + HUECO)
		_retrato(Rect2(x, 0, TILE.x, TILE.y), T, _t[i])


func _caja(r: Rect2, col: Color) -> void:
	draw_rect(r, col)
	# brillo arriba y filo abajo: que no sea una placa plana
	draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.45)), Color(1, 1, 1, 0.06))
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), Color(0, 0, 0, 0.5), 2.0)


func _tanteo(r: Rect2, col: Color, n: int) -> void:
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([col.lightened(0.12), col.lightened(0.12), col.darkened(0.2), col.darkened(0.2)]))
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), col.darkened(0.5), 2.0)
	_texto(str(n), r, 24, Color.WHITE, true)


func _texto(t: String, r: Rect2, tam: int, col: Color, sombra := false) -> void:
	var ancho := _fuente.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
	var base := Vector2(r.position.x + (r.size.x - ancho) * 0.5, r.position.y + r.size.y * 0.5 + tam * 0.36)
	if sombra:
		draw_string(_fuente, base + Vector2(0, 1.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, Color(0, 0, 0, 0.45))
	draw_string(_fuente, base, t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, col)


## Un retrato: fondo del color del bando, la silueta (cabeza y hombros) y una franja del color arriba. Muerto, gris y
## apagado. El tuyo, con filo blanco; el que lleva la C4, con la C4 en la esquina.
func _retrato(r: Rect2, col: Color, fila: Array) -> void:
	var vivo := bool(fila[1])
	var fondo := Color(col.darkened(0.55), 0.85) if vivo else Color(0.1, 0.1, 0.11, 0.6)
	var sil := col.lightened(0.15) if vivo else Color(0.4, 0.4, 0.42, 0.55)
	draw_rect(r, fondo)
	var cx := r.get_center().x
	draw_circle(Vector2(cx, r.position.y + r.size.y * 0.36), r.size.x * 0.22, sil)
	draw_colored_polygon(PackedVector2Array([Vector2(r.position.x + 3, r.end.y), Vector2(r.position.x + 5, r.end.y - 9),
		Vector2(cx - 5, r.end.y - 13), Vector2(cx + 5, r.end.y - 13), Vector2(r.end.x - 5, r.end.y - 9), Vector2(r.end.x - 3, r.end.y)]), sil)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), col if vivo else Color(0.35, 0.35, 0.36, 0.6))
	if fila.size() > 4 and bool(fila[4]):
		draw_rect(r.grow(1.0), Color(1.0, 0.8, 0.2, 1.0 if vivo else 0.6), false, 2.5)     # una persona: borde dorado
	if bool(fila[2]):
		draw_rect(r, Color(1, 1, 1, 0.9), false, 1.5)
	if bool(fila[3]) and vivo:
		_c4(r.end - Vector2(7, 7), 0.42)


## La C4: el bloque rojo con su pantalla y los cables, como el icono de CS2.
func _c4(c: Vector2, k: float) -> void:
	var w := 30.0 * k
	var h := 18.0 * k
	var r := Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h))
	draw_rect(r.grow(1.5 * k), Color(0.1, 0.0, 0.0))
	draw_rect(r, Color(0.86, 0.14, 0.12))
	draw_rect(Rect2(r.position + Vector2(w * 0.12, h * 0.2), Vector2(w * 0.42, h * 0.38)), Color(0.12, 0.2, 0.12))
	for i in 3:
		draw_line(Vector2(r.position.x + w * (0.64 + 0.1 * i), r.position.y), Vector2(r.position.x + w * (0.64 + 0.1 * i), r.end.y),
			Color(0.25, 0.02, 0.02), maxf(1.0, 1.4 * k))
