extends Node3D
## MODO ATRACO (estilo The Finals) para el mapa de ciudad.
##
##   CAJA FUERTE  -> pulsas USAR UNA VEZ y la ganzúa trabaja sola; si te mueves, se cancela y pierdes
##                   el progreso. Al terminar suelta un CUBO DORADO.
##   CUBO         -> lo coges con telequinesis y flota delante de ti. Con el cubo en la mano no
##                   puedes disparar: el tiro EMPUJA el cubo en vez de salir del arma.
##   TERMINAL     -> aparece en otro punto del mapa al abrir la caja. Dejas el cubo dentro y otra
##                   cuenta atrás lo ingresa: eso son los puntos.
##
## Todo el modelado se hace por código con cajas, al mismo detalle que la C4, para que encaje con
## el aspecto de vóxeles del juego.

signal vault_opened(pos: Vector3)
## `equipo`: el que tenia el terminal cuando acabo el ingreso (puede no ser el que metio el cubo)
signal cash_deposited(points: int, equipo: String)

enum { VAULT_IDLE, VAULT_OPENING, VAULT_OPEN }
enum { OUT_HIDDEN, OUT_WAITING, OUT_DEPOSITING, OUT_DONE }

## TIEMPOS DEL ATRACO (los pidio el usuario): 20 s para sacar el cubo de la caja, 2 minutos de ingreso,
## y 7 s para que otro equipo le cambie el color al terminal y se quede con esa plata.
const OPEN_TIME := 20.0       ## s que tarda la ganzua sola tras pulsar USAR una vez
const CANCEL_MOVE := 0.8      ## m que puedes moverte antes de que se cancele la ganzua
const DEPOSIT_TIME := 120.0   ## s de ingreso en el terminal (sin necesidad de quedarte al lado)
## ROBAR EL INGRESO. Mientras el terminal ingresa, un equipo de OTRO color que se quede a su lado
## CAPTURE_TIME segundos le cambia el color: el ingreso SIGUE por donde iba, pero ahora es para ellos.
## Si hay gente de los dos colores al lado, esta disputado y la barra no avanza. Si se van, se cae.
const CAPTURE_TIME := 7.0
const CAPTURE_RANGE := 3.5
const USE_RANGE := 2.6        ## m para usar la caja o el terminal
const GRAB_RANGE := 3.2       ## m para coger el cubo
const POINTS := 1000
const RADIO_COLOCAR := 2.3    ## m (en el plano) a los que el cubo se mete solo en el terminal

var player: Node3D = null
var world = null
var hud = null

var vault: Node3D = null
var vault_state := VAULT_IDLE
var vault_t := 0.0
var _beep := 0.0

var cube: RigidBody3D = null
## ¿Lo llevo YO (el jugador de esta maquina)? Lo decide el anfitrion: ver `carrier`.
var carried: bool:
	get:
		return carrier != 0 and carrier == mi_id()
## Ultimo sitio donde el cubo estuvo QUIETO y apoyado: a donde vuelve si se cae al vacio (ver _rescatar_cubo)
var _cubo_apoyo := Vector3.ZERO

var cashout: Node3D = null
var out_state := OUT_HIDDEN
var out_t := 0.0
var score := 0
var out_equipo := ""          ## de que equipo es el ingreso en marcha (el color del terminal)
var captura_t := 0.0          ## progreso del robo
var captura_equipo := ""      ## quien lo esta robando
var _presentes := {}          ## equipo -> true: quien esta al lado del terminal este fotograma


func setup(p: Node3D, w, h) -> void:
	player = p
	world = w
	hud = h


# ---------------------------------------------------------------------------
# Colocación: caja fuerte dentro de un edificio, terminal lejos y a ras de calle
# ---------------------------------------------------------------------------
func place(vault_pos: Vector3, cashout_pos: Vector3) -> void:
	vault = _build_vault()
	add_child(vault)
	vault.global_position = vault_pos
	cashout = _build_cashout()
	add_child(cashout)
	cashout.global_position = cashout_pos
	cashout.visible = false
	out_state = OUT_HIDDEN


func _mat(c: Color, met: float, ro: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = met
	m.roughness = ro
	m.metallic_specular = 0.6
	return m


func _glow(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


## Caja de la geometría: un prisma con material, en metros y centrado en `pos`.
func _box(parent: Node3D, pos: Vector3, size: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


# ---------------------------------------------------------------------------
# CAJA FUERTE: armario acorazado con puerta, rueda, bisagras, panel y piloto
# ---------------------------------------------------------------------------
var _vault_led: MeshInstance3D = null
var _vault_door: Node3D = null

func _build_vault() -> Node3D:
	var r := Node3D.new()
	r.name = "Vault"
	var steel := _mat(Color(0.30, 0.32, 0.36), 0.85, 0.35)
	var dark := _mat(Color(0.15, 0.16, 0.18), 0.7, 0.45)
	var gold := _mat(Color(0.85, 0.66, 0.18), 0.9, 0.25)
	var rub := _mat(Color(0.06, 0.06, 0.07), 0.0, 0.9)

	_box(r, Vector3(0, 0.75, 0), Vector3(1.30, 1.50, 0.80), steel)            # cuerpo
	_box(r, Vector3(0, 0.04, 0), Vector3(1.40, 0.08, 0.90), dark)             # zócalo
	_box(r, Vector3(0, 1.48, 0), Vector3(1.36, 0.06, 0.86), dark)             # remate
	# puerta, un poco hundida, con marco
	_vault_door = Node3D.new()
	r.add_child(_vault_door)
	_box(_vault_door, Vector3(0, 0.75, 0.41), Vector3(1.10, 1.24, 0.06), dark)
	_box(_vault_door, Vector3(0, 0.75, 0.44), Vector3(1.00, 1.14, 0.03), steel)
	# rueda de apertura
	_box(_vault_door, Vector3(0, 0.75, 0.47), Vector3(0.34, 0.10, 0.06), gold)
	_box(_vault_door, Vector3(0, 0.75, 0.47), Vector3(0.10, 0.34, 0.06), gold)
	_box(_vault_door, Vector3(0, 0.75, 0.49), Vector3(0.12, 0.12, 0.05), dark)
	# bisagras
	for y in [0.30, 0.75, 1.20]:
		_box(r, Vector3(-0.60, y, 0.36), Vector3(0.10, 0.14, 0.14), dark)
	# tiradores y pies de goma
	for x in [-0.55, 0.55]:
		_box(r, Vector3(x, 0.02, 0.40), Vector3(0.14, 0.05, 0.14), rub)
	# panel de mando lateral
	_box(r, Vector3(0.68, 1.05, 0.10), Vector3(0.05, 0.34, 0.30), dark)
	for i in 3:
		_box(r, Vector3(0.71, 1.16 - i * 0.09, 0.10), Vector3(0.02, 0.05, 0.22), _mat(Color(0.4, 0.42, 0.45), 0.5, 0.4))
	# piloto: rojo cerrada, ámbar abriendo, verde abierta
	_vault_led = _box(r, Vector3(0.71, 0.72, 0.10), Vector3(0.03, 0.09, 0.09), _glow(Color(1.0, 0.2, 0.15), 6.0))
	var lamp := OmniLight3D.new()
	lamp.omni_range = 4.0
	lamp.light_energy = 1.2
	lamp.light_color = Color(1.0, 0.35, 0.2)
	lamp.position = Vector3(0.7, 0.9, 0.3)
	r.add_child(lamp)
	r.set_meta("lamp", lamp)
	return r


# ---------------------------------------------------------------------------
# TERMINAL DE INGRESO: pedestal con hueco para el cubo y aro luminoso
# ---------------------------------------------------------------------------
var _out_ring: MeshInstance3D = null

func _build_cashout() -> Node3D:
	var r := Node3D.new()
	r.name = "Cashout"
	var steel := _mat(Color(0.26, 0.28, 0.32), 0.8, 0.4)
	var dark := _mat(Color(0.12, 0.13, 0.15), 0.6, 0.5)
	_box(r, Vector3(0, 0.05, 0), Vector3(1.50, 0.10, 1.50), dark)             # base
	for x in [-0.6, 0.6]:
		for z in [-0.6, 0.6]:
			_box(r, Vector3(x, 0.35, z), Vector3(0.12, 0.60, 0.12), steel)    # patas
	_box(r, Vector3(0, 0.68, 0), Vector3(1.30, 0.10, 1.30), steel)            # bandeja
	_box(r, Vector3(0, 0.80, 0), Vector3(0.70, 0.14, 0.70), dark)             # hueco del cubo
	# aro luminoso alrededor del hueco
	var ring := Node3D.new()
	r.add_child(ring)
	var glow := _glow(Color(0.25, 0.85, 1.0), 5.0)
	for i in 16:
		var a := TAU * i / 16.0
		_box(ring, Vector3(cos(a) * 0.52, 0.76, sin(a) * 0.52), Vector3(0.10, 0.04, 0.10), glow)
	_out_ring = MeshInstance3D.new()
	ring.set_meta("glow", glow)
	# poste con pantalla
	_box(r, Vector3(0, 1.20, -0.62), Vector3(0.16, 1.00, 0.16), steel)
	_box(r, Vector3(0, 1.60, -0.54), Vector3(0.70, 0.44, 0.06), dark)
	_box(r, Vector3(0, 1.60, -0.50), Vector3(0.62, 0.36, 0.02), _glow(Color(0.20, 0.75, 1.0), 3.0))
	var lamp := OmniLight3D.new()
	lamp.omni_range = 6.0
	lamp.light_energy = 2.0
	lamp.light_color = Color(0.3, 0.8, 1.0)
	lamp.position = Vector3(0, 1.2, 0)
	r.add_child(lamp)
	r.set_meta("lamp", lamp)
	r.set_meta("ring", ring)
	return r


# ---------------------------------------------------------------------------
# CUBO DORADO
# ---------------------------------------------------------------------------
func _spawn_cube(at: Vector3) -> void:
	cube = RigidBody3D.new()
	cube.name = "CashBox"
	cube.mass = 40.0
	cube.collision_layer = 4
	cube.collision_mask = 1
	cube.continuous_cd = true
	add_child(cube)
	var sh := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.55, 0.55, 0.55)
	sh.shape = bs
	cube.add_child(sh)
	var gold := _mat(Color(0.92, 0.72, 0.20), 0.95, 0.20)
	var edge := _glow(Color(1.0, 0.85, 0.35), 3.0)
	_box(cube, Vector3.ZERO, Vector3(0.55, 0.55, 0.55), gold)
	for s in [Vector3(0.56, 0.06, 0.06), Vector3(0.06, 0.56, 0.06), Vector3(0.06, 0.06, 0.56)]:
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var off := Vector3(0.26 * sx, 0.26 * sy, 0.0)
				if s.x > 0.5: off = Vector3(0.0, 0.26 * sx, 0.26 * sy)
				elif s.y > 0.5: off = Vector3(0.26 * sx, 0.0, 0.26 * sy)
				_box(cube, off, s, edge)
	var lamp := OmniLight3D.new()
	lamp.omni_range = 5.0
	lamp.light_energy = 2.2
	lamp.light_color = Color(1.0, 0.82, 0.35)
	cube.add_child(lamp)
	cube.global_position = at
	_cubo_apoyo = at
	cube.add_to_group("cashbox")
	# ANCLA DE FISICA: el mundo solo genera colision alrededor de lo que esta en este grupo (y del
	# jugador). Lanzado lejos de ti, el cubo se quedaba sin suelo debajo y lo atravesaba.
	cube.add_to_group("phys_anchor")


# ---------------------------------------------------------------------------
# Bucle
# ---------------------------------------------------------------------------
# EL ATRACO EN RED: MANDA EL ANFITRION.
#
# Antes cada maquina tenia su propio atraco: su caja, su cubo, su ingreso y sus puntos. Dos jugadores en
# la misma sala jugaban dos atracos distintos que no se tocaban. Ahora:
#
#   - EL ANFITRION SIMULA TODO: la ganzua, el cubo (su fisica y quien lo lleva), el terminal, el robo del
#     terminal y los bots. Es la unica maquina que decide.
#   - LOS DEMAS PIDEN. Pulsar USAR junto a la caja, coger, soltar o empujar el cubo es una PETICION
#     (`Net.net_atraco_accion`); el anfitrion comprueba que estas al lado de verdad y la aplica.
#   - EL ANFITRION CUENTA COMO VA, diez veces por segundo (`Net.net_atraco_estado`): donde estan la caja,
#     el terminal y el cubo, quien lo lleva, las barras y de que color es el terminal. Los invitados solo
#     lo pintan (su cubo es un cuerpo congelado que se desliza a la postura que llega).
#   - LO QUE NO SE PUEDE PERDER VA APARTE, por el canal fiable (`Net.net_atraco_evento`): el ingreso
#     terminado (que da los puntos a todos a la vez) y los avisos a un jugador concreto.
#
# Jugando solo (o sin red) esta maquina es el anfitrion de si misma y todo va como siempre.
# ---------------------------------------------------------------------------
const ESTADO_HZ := 10.0
var heist_id := 0                   ## que atraco es: el anfitrion lo cuenta; si cambia, es caja nueva
var soy_copia := false              ## invitado en red: no simula, pinta lo que manda el anfitrion
var abre_peer := 0                  ## quien esta abriendo la caja (id de red), 0 nadie
var abre_equipo := ""
var carrier := 0                    ## quien lleva el cubo (id de red), 0 nadie
var _ultimo_equipo_cubo := ""       ## el color del ultimo que lo llevo: a quien es el ingreso si entra solo
var _grab_cd := {}                  ## id -> s antes de poder volver a cogerlo tras soltarlo
var _estado_t := 0.0
var _cubo_meta_pos := Vector3.ZERO  ## (copia) a donde se desliza el cubo
var _cubo_meta_rot := Quaternion.IDENTITY
var _use_prev := false
var _use_just := false
var _use_pulse := false             ## un toque del boton USAR del movil, que no pasa por la accion
var _vault_origen := Vector3.ZERO   ## donde estaba el que abre al empezar la ganzua


func _ready() -> void:
	if Net:
		Net.atraco_accion.connect(_accion)
		Net.atraco_estado.connect(_aplicar_estado)
		Net.atraco_evento.connect(_evento)


func _exit_tree() -> void:
	if player and is_instance_valid(player) and "carrying_cube" in player:
		player.carrying_cube = false


## Mi id de red (1 fuera de red: el anfitrion de mi propia partida).
func mi_id() -> int:
	return multiplayer.get_unique_id() if Net.is_online() else 1


func _mi_equipo() -> String:
	return String(Net.my_team()) if Net and Net.has_method("my_team") else ""


## Los jugadores de la partida, vistos desde el anfitrion: id, donde estan, equipo, si viven y hacia donde
## miran. El local lo sabe el mismo; los demas son los muñecos de red (Net.remotes).
func _actores() -> Array:
	var out: Array = []
	if player and is_instance_valid(player):
		var cam: Node3D = player.get_node_or_null("Head/Camera3D")
		out.append({"id": mi_id(), "pos": player.global_position, "equipo": _mi_equipo(),
			"vivo": float(player.get("health")) > 0.0 and not bool(player.get("spectating")),
			"fwd": -cam.global_transform.basis.z if cam else -player.global_transform.basis.z})
	if Net.is_online():
		for id in Net.remotes.keys():
			var r = Net.remotes[id]
			if not is_instance_valid(r):
				continue
			var yaw: float = float(r.get("target_yaw"))
			var pitch: float = float(r.get("target_pitch"))
			out.append({"id": int(id), "pos": (r as Node3D).global_position, "equipo": String(Net.team_of(int(id))),
				"vivo": not bool(r.get("dead")),
				"fwd": -(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)).z})
	return out


func _actor(id: int) -> Dictionary:
	for a in _actores():
		if int(a["id"]) == id:
			return a
	return {}


# --- entrada del jugador de ESTA maquina -------------------------------------
func _use_held() -> bool:
	if Input.is_action_pressed("interact"):
		return true
	# EN MOVIL "usar" tambien es el boton de disparo, PERO NO CON EL CUBO EN LAS MANOS. Ahi ese boton
	# es para empujarlo (player.fire -> push_cube), y si ademas contara como "usar", el mismo toque
	# soltaba el cubo.
	if carrier == mi_id():
		return false
	return player.touch_fire if "touch_fire" in player else false


## El boton USAR del movil no mueve la accion "interact" (es un boton de interfaz), asi que el
## jugador nos avisa por aqui. Sin esto, en el movil la caja solo se podia abrir con el de disparo.
func usar_desde_jugador() -> void:
	_use_pulse = true


## Pedir algo al atraco. En el anfitrion (o sin red) se aplica en el acto; en un invitado viaja.
func pedir(accion: String, datos: Dictionary = {}) -> void:
	Net.net_atraco_accion(accion, datos)


func _process(dt: float) -> void:
	if player == null or not is_instance_valid(player) or vault == null:
		return
	soy_copia = Net.is_online() and not Net.hosting
	var held := _use_held()
	_use_just = (held and not _use_prev) or _use_pulse
	_use_prev = held
	_use_pulse = false
	for k in _grab_cd.keys():
		_grab_cd[k] = maxf(float(_grab_cd[k]) - dt, 0.0)
	if soy_copia:
		if Net.ultimo_estado_atraco.size() > 0 and int(Net.ultimo_estado_atraco.get("id", -1)) != heist_id:
			_aplicar_estado(Net.ultimo_estado_atraco)
		_deslizar_cubo(dt)
	else:
		_caer(vault, Vector2(0.65, 0.40), dt, _caida_caja)
		_caer(cashout, Vector2(0.72, 0.72), dt, _caida_terminal)
		_tick_vault(dt)
		_tick_bots(dt)
		_tick_carry(dt)
		_rescatar_cubo()
		_tick_cashout(dt)
		if Net.is_online() and Net.hosting:
			_estado_t -= dt
			if _estado_t <= 0.0:
				_estado_t = 1.0 / ESTADO_HZ
				Net.net_atraco_estado(_estado())
	_entrada_local(dt)
	_tick_objective()


## Lo que el jugador de ESTA maquina puede hacer, con su aviso en pantalla. Pedir, no hacer.
func _entrada_local(dt: float) -> void:
	var yo := mi_id()
	var llevo: bool = carrier == yo
	if "carrying_cube" in player:
		player.carrying_cube = llevo
	# el pitido de la ganzua se oye en todas las maquinas
	# BF: mientras revientan la caja fuerte, la alarma del edificio y el teclear de la ganzua electronica
	if vault:
		Audio.bucle3d(vault, "alarma", "modo/alarma_cerca", vault_state == VAULT_OPENING, -6.0, 70.0)
		Audio.bucle3d(vault, "teclado", "modo/teclado", vault_state == VAULT_OPENING, -10.0, 15.0)
	if vault_state == VAULT_OPENING:
		_beep -= dt
		if _beep <= 0.0:
			_beep = lerpf(0.15, 0.8, 1.0 - vault_t / OPEN_TIME)
			Audio.play3d("clickdown", vault.global_position, -3.0, 0.1, 25.0, Audio.PRI_MID)
	var vivo: bool = float(player.get("health")) > 0.0 and not bool(player.get("spectating"))
	if not vivo:
		return
	if vault_state != VAULT_OPEN:
		var d := player.global_position.distance_to(vault.global_position + Vector3(0, 0.8, 0))
		if d <= USE_RANGE:
			if vault_state == VAULT_OPENING and abre_peer == yo:
				if hud:
					hud.show_action("ABRIENDO LA CAJA  %d %%  (no te muevas)" % int(100.0 * vault_t / OPEN_TIME), vault_t / OPEN_TIME)
			elif vault_state != VAULT_OPENING:
				if hud:
					hud.show_action(("PULSA USAR" if Settings.is_touch() else "PULSA [E]") + " PARA ABRIR LA CAJA", 0.0)
				if _use_just:
					pedir("abrir")
		return
	if cube == null or not is_instance_valid(cube):
		return
	if llevo:
		if _use_just:
			pedir("soltar")
			if hud:
				hud.flash_message("Cubo soltado")
		elif hud:
			hud.show_action("CUBO EN MANO · %s lo empuja y lo suelta" % ("DISPARO" if Settings.is_touch() else "click"), 0.0)
		return
	if carrier == 0 and out_state == OUT_WAITING:
		var dc := player.global_position.distance_to(cube.global_position)
		if dc < GRAB_RANGE:
			if hud:
				hud.show_action(("USAR" if Settings.is_touch() else "[E]") + " PARA COGER EL CUBO", 0.0)
			if _use_just:
				pedir("coger")


# --- las peticiones, en el anfitrion ---------------------------------------
func _accion(peer: int, accion: String, datos: Dictionary) -> void:
	if soy_copia or vault == null:
		return
	var a := _actor(peer)
	if a.is_empty() or not bool(a["vivo"]):
		return
	var pos: Vector3 = a["pos"]
	match accion:
		"abrir":
			if vault_state == VAULT_OPEN or (vault_state == VAULT_OPENING and abre_peer != 0):
				return
			if pos.distance_to(vault.global_position + Vector3(0, 0.8, 0)) > USE_RANGE + 0.6:
				return
			vault_state = VAULT_OPENING
			vault_t = 0.0
			abre_peer = peer
			abre_equipo = String(a["equipo"])
			_vault_origen = pos
			_set_vault_led(Color(1.0, 0.65, 0.1), 6.0)
			_avisar(peer, "Abriendo la caja: NO TE MUEVAS")
		"coger":
			if cube == null or not is_instance_valid(cube) or carrier != 0 or out_state != OUT_WAITING:
				return
			if float(_grab_cd.get(peer, 0.0)) > 0.0 or pos.distance_to(cube.global_position) > GRAB_RANGE + 0.6:
				return
			carrier = peer
			_ultimo_equipo_cubo = String(a["equipo"])
			cube.gravity_scale = 0.0
			_avisar(peer, "Cubo cogido: no puedes disparar mientras lo llevas")
		"soltar":
			if carrier == peer:
				_soltar()
		"empujar":
			if carrier == peer and cube and is_instance_valid(cube):
				_soltar()
				var dir: Vector3 = datos.get("d", Vector3.FORWARD)
				cube.apply_central_impulse(dir.normalized() * clampf(float(datos.get("f", 600.0)), 0.0, 900.0))
				Audio.play3d("clickdown", cube.global_position, -2.0, 0.1, 20.0, Audio.PRI_MID)


func _soltar() -> void:
	if carrier != 0:
		_grab_cd[carrier] = 0.7     # o el mismo toque que lo suelta lo vuelve a coger
	carrier = 0
	if cube and is_instance_valid(cube):
		cube.gravity_scale = 1.0


## Un aviso para UN jugador (el que abre, el que coge...). Si es el de esta maquina, se enseña aqui.
func _avisar(peer: int, texto: String) -> void:
	if peer == mi_id():
		if hud:
			hud.flash_message(texto)
	elif Net.is_online() and Net.hosting:
		Net.net_atraco_evento("aviso", {"peer": peer, "texto": texto})


## Compatibilidad con las pruebas y con player.gd: coger/soltar/empujar como el jugador local.
func grab() -> void:
	if soy_copia:
		pedir("coger")
		return
	if cube == null or not is_instance_valid(cube):
		return
	carrier = mi_id()
	_ultimo_equipo_cubo = _mi_equipo()
	cube.gravity_scale = 0.0


func drop() -> void:
	pedir("soltar")


## Un disparo con el cubo en la mano NO dispara: lo empuja.
func push_cube(dir: Vector3, force: float) -> void:
	pedir("empujar", {"d": dir, "f": force})


# ---------------------------------------------------------------------------
# LA CAJA Y EL TERMINAL SE CAEN SI LES QUITAS EL SUELO. Eran decorado colgado en el sitio: rompias el
# piso de debajo y se quedaban flotando ("la caja fuerte y lo otro no tienen fisicas"). No son cuerpos
# de fisica a proposito -una caja fuerte que rueda escaleras abajo o que un cohete manda a la otra punta
# rompe el atraco-: se comprueba si hay algo debajo (mundo o bloques caidos) y, si no, caen rectos con
# gravedad hasta apoyarse. Mirar cada 0,1 s basta: son cinco rayos cortos. Lo hace el anfitrion; los
# demas reciben la posicion.
# ---------------------------------------------------------------------------
const GRAVEDAD_OBJETOS := 18.0
var _caida_caja := {"vy": 0.0, "t": 0.0, "cayendo": false}
var _caida_terminal := {"vy": 0.0, "t": 0.0, "cayendo": false}

## Distancia hasta lo que haya debajo de la huella (el mas alto de cinco rayos), o INF si no hay nada.
func _hueco_debajo(n: Node3D, medio: Vector2, alcance: float) -> float:
	var b: Basis = n.global_transform.basis
	var mejor := INF
	for o in [Vector2.ZERO, Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var off: Vector3 = b.x * (o.x * medio.x * 0.85) + b.z * (o.y * medio.y * 0.85)
		var desde: Vector3 = n.global_position + off + Vector3.UP * 0.25
		var r: Dictionary = world.raycast_con_piezas(desde, Vector3.DOWN, alcance + 0.25)
		if not r.is_empty() and bool(r.get("hit", false)):
			mejor = minf(mejor, desde.y - (r.position as Vector3).y - 0.25)
	return mejor


func _caer(n: Node3D, medio: Vector2, dt: float, st: Dictionary) -> void:
	if n == null or not is_instance_valid(n) or world == null or not n.is_visible_in_tree() and n == cashout and out_state == OUT_HIDDEN:
		return
	if not bool(st["cayendo"]):
		st["t"] = float(st["t"]) - dt
		if float(st["t"]) > 0.0:
			return
		st["t"] = 0.1
		if _hueco_debajo(n, medio, 0.3) <= 0.2:
			return                      # apoyado
		st["cayendo"] = true
		st["vy"] = 0.0
	st["vy"] = float(st["vy"]) + GRAVEDAD_OBJETOS * dt
	var paso: float = float(st["vy"]) * dt
	var hueco := _hueco_debajo(n, medio, paso + 0.5)
	if hueco <= paso:
		n.global_position.y -= maxf(hueco, 0.0)     # toca: se apoya justo encima
		st["cayendo"] = false
		st["vy"] = 0.0
		Audio.play3d("clickdown", n.global_position, 2.0, 0.1, 40.0, Audio.PRI_MID)
		return
	n.global_position.y -= paso
	if n.global_position.y < -8.0:
		# se ha colado por el mundo: a la calle de ese punto
		n.global_position = world.find_ground(Vector3(n.global_position.x, 60.0, n.global_position.z))
		st["cayendo"] = false
		st["vy"] = 0.0


## Línea de objetivo del HUD: a dónde hay que ir ahora y cuánto queda. El mapa es enorme, sin esto
## la caja fuerte no hay quien la encuentre. Cada maquina la pinta con SU jugador y el estado comun.
func _tick_objective() -> void:
	if hud == null or vault == null or cashout == null:
		return
	# EL MARCADOR EN EL MUNDO sigue al objetivo del momento: caja, cubo, terminal (ver hud.gd)
	if out_state == OUT_DONE:
		hud.quitar_objetivo_mundo()
		hud.set_objective("ATRACO COMPLETADO · %d puntos" % score, true)
		return
	if vault_state != VAULT_OPEN:
		var d: float = player.global_position.distance_to(vault.global_position)
		var dy: float = vault.global_position.y - player.global_position.y
		var floors: int = int(round(dy / 3.5))
		var alt := ""
		if floors > 0:
			alt = " · %d plantas más arriba" % floors
		elif floors < 0:
			alt = " · %d plantas más abajo" % -floors
		# LA BARRA REDONDA DE LA CAJA: la de quien la este abriendo, con el COLOR DE SU EQUIPO.
		var prog := -1.0
		var col_carga := Color(1.0, 1.0, 0.85)
		var texto_caja := "CAJA FUERTE"
		if vault_state == VAULT_OPENING:
			prog = vault_t / OPEN_TIME
			col_carga = _color_de(abre_equipo)
			texto_caja = "ABRIENDO LA CAJA" if abre_equipo == _mi_equipo() else "%s ABRE LA CAJA" % Net.nombre_equipo(abre_equipo)
		elif bot_t > 0.05 and _ultimo_equipo_bots != "":
			prog = bot_t / BOT_OPEN_TIME
			col_carga = _color_de(_ultimo_equipo_bots)
			texto_caja = "%s ABRE LA CAJA" % Net.nombre_equipo(_ultimo_equipo_bots)
		hud.set_objetivo_mundo(vault.global_position + Vector3(0, 1.2, 0), texto_caja, prog,
			Color(1.0, 0.84, 0.1), col_carga)
		hud.set_objective("CAJA FUERTE a %d m%s" % [int(d), alt], d < USE_RANGE)
		return
	if out_state == OUT_DEPOSITING:
		var mio: bool = out_equipo == _mi_equipo() or out_equipo == ""
		var restan := int(ceil(DEPOSIT_TIME - out_t))
		var tiempo := "%d:%02d" % [restan / 60, restan % 60]
		hud.set_objetivo_mundo(cashout.global_position + Vector3(0, 1.5, 0),
			"DEFIENDE EL TERMINAL" if mio else "ROBA EL TERMINAL", out_t / DEPOSIT_TIME,
			Color(1.0, 0.84, 0.1), _color_de(out_equipo))
		if mio:
			hud.set_objective("INGRESANDO · %s · defiende el terminal" % tiempo, true)
		else:
			hud.set_objective("%s ESTA INGRESANDO · %s · quedate %d s al lado para robarlo" % [
				Net.nombre_equipo(out_equipo), tiempo, int(CAPTURE_TIME)], false)
		if captura_t > 0.0 and player.global_position.distance_to(cashout.global_position) < CAPTURE_RANGE * 3.0:
			hud.show_action("CAMBIANDO EL COLOR DEL TERMINAL  %d %%" % int(100.0 * captura_t / CAPTURE_TIME), captura_t / CAPTURE_TIME)
		return
	var dc: float = player.global_position.distance_to(cashout.global_position)
	if carrier == mi_id():
		hud.set_objetivo_mundo(cashout.global_position + Vector3(0, 1.5, 0), "TERMINAL")
		hud.set_objective("LLEVA EL CUBO AL TERMINAL · %d m" % int(dc), false)
	elif cube and is_instance_valid(cube):
		hud.set_objetivo_mundo(cube.global_position + Vector3(0, 0.6, 0), "CUBO")
		if carrier != 0:
			hud.set_objective("%s LLEVA EL CUBO al terminal (a %d m)" % [Net.nombre_equipo(_ultimo_equipo_cubo), int(dc)], false)
		else:
			hud.set_objective("COGE EL CUBO (a %d m) y llevalo al terminal" % int(player.global_position.distance_to(cube.global_position)), false)


# --- la ganzua (anfitrion) --------------------------------------------------
func _tick_vault(dt: float) -> void:
	if vault_state != VAULT_OPENING:
		return
	var a := _actor(abre_peer)
	# se corta si el que abre se va, se mueve, muere o se desconecta: y se pierde TODO el progreso
	if a.is_empty() or not bool(a["vivo"]):
		_cancelar_caja("te has ido")
		return
	var pos: Vector3 = a["pos"]
	if pos.distance_to(vault.global_position + Vector3(0, 0.8, 0)) > USE_RANGE + 0.6:
		_cancelar_caja("te has alejado")
		return
	if pos.distance_to(_vault_origen) > CANCEL_MOVE:
		_cancelar_caja("te has movido")
		return
	vault_t += dt
	if vault_t >= OPEN_TIME:
		_open_vault()


## LOS BOTS TAMBIEN ABREN LA CAJA, y van por su cuenta: barra propia, no la de los jugadores. Tardan un
## tercio mas, o no daria tiempo a cruzar el mapa despues de reaparecer. Solo en el anfitrion.
const BOT_OPEN_TIME := OPEN_TIME * 1.35

var bot_t := 0.0
var _bot_activo := false
var _bot_equipo := ""
var _ultimo_equipo_bots := ""     ## el color de la barra de los bots aunque ese fotograma no hayan avisado


## El color del equipo, o el blanco de siempre fuera de los modos por equipos.
func _color_de(equipo: String) -> Color:
	if equipo == "" or Net == null or Net.equipos.size() < 2:
		return Color(1.0, 1.0, 0.85)
	return Net.color_equipo(equipo)


func bot_abriendo(equipo: String, dt: float) -> void:
	if soy_copia or vault == null or vault_state == VAULT_OPEN:
		return
	_bot_activo = true
	_bot_equipo = equipo
	_ultimo_equipo_bots = equipo
	bot_t += dt
	if bot_t >= BOT_OPEN_TIME:
		_open_vault()


## Si se van (o los matas), la barra de ellos se cae sola: no vale con haber pasado por al lado.
func _tick_bots(dt: float) -> void:
	if vault_state == VAULT_OPEN:
		return
	if not _bot_activo:
		bot_t = maxf(bot_t - dt * 1.5, 0.0)
		_bot_equipo = ""
	_bot_activo = false


func _cancelar_caja(motivo: String) -> void:
	var quien := abre_peer
	vault_state = VAULT_IDLE
	vault_t = 0.0
	abre_peer = 0
	abre_equipo = ""
	_set_vault_led(Color(1.0, 0.2, 0.15), 4.0)
	_avisar(quien, "Ganzúa cancelada: %s" % motivo)


func _open_vault() -> void:
	vault_state = VAULT_OPEN
	abre_peer = 0
	_abrir_visual()
	if not soy_copia:
		_spawn_cube(vault.global_position + Vector3(0, 0.9, 0.9))
	out_state = OUT_WAITING
	vault_opened.emit(vault.global_position)


## Lo que se VE al abrirse la caja, igual en todas las maquinas.
func _abrir_visual() -> void:
	_set_vault_led(Color(0.3, 1.0, 0.4), 6.0)
	if _vault_door:
		_vault_door.rotation.y = -1.35        # puerta abierta de par en par
		_vault_door.position = Vector3(-0.55, 0.0, 0.30)
	cashout.visible = true
	Audio.play3d("clickup", vault.global_position, 0.0, 0.05, 30.0, Audio.PRI_HIGH)
	Audio.bf3d("modo/caja_abrir", vault.global_position, 2.0, 40.0, Audio.PRI_HIGH)
	Audio.voz("objetivo_localizado", 1)
	if hud:
		hud.flash_message("¡CAJA ABIERTA! Lleva el cubo al terminal")


func _set_vault_led(c: Color, e: float) -> void:
	if _vault_led:
		_vault_led.material_override = _glow(c, e)
	var l = vault.get_meta("lamp") if vault and vault.has_meta("lamp") else null
	if l and is_instance_valid(l):
		l.light_color = c


## EL CUBO NO SE PIERDE EN EL VACIO. Si se cuela por debajo del mapa, vuelve a la CALLE de ese mismo
## punto; y si ahi hay un hueco, al ultimo sitio donde estuvo quieto y apoyado.
func _rescatar_cubo() -> void:
	if cube == null or not is_instance_valid(cube):
		return
	var pos: Vector3 = cube.global_position
	if carrier == 0 and pos.y > 0.0 and cube.linear_velocity.length() < 0.4:
		_cubo_apoyo = pos
	if pos.y > -3.0:
		return
	var destino: Vector3 = _cubo_apoyo + Vector3(0, 0.8, 0)
	var r: Dictionary = world.raycast(Vector3(pos.x, 2.5, pos.z), Vector3.DOWN, 3.5)
	if r.hit and r.position.y >= 0.0:
		destino = r.position + Vector3(0, 0.8, 0)
	if _cubo_apoyo == Vector3.ZERO and not r.hit:
		destino = vault.global_position + Vector3(0, 1.2, 0)
	cube.global_position = destino
	cube.linear_velocity = Vector3.ZERO
	cube.angular_velocity = Vector3.ZERO


# --- telequinesis (anfitrion) ----------------------------------------------
func _tick_carry(_dt: float) -> void:
	if cube == null or not is_instance_valid(cube) or carrier == 0:
		return
	var a := _actor(carrier)
	if a.is_empty() or not bool(a["vivo"]):
		_soltar()                 # se muere o se va: el cubo cae donde estaba
		return
	# flotando delante de quien lo lleva, a la altura del pecho
	var fwd: Vector3 = a["fwd"]
	var want: Vector3 = (a["pos"] as Vector3) + Vector3(0, 1.1, 0) + fwd * 1.5
	# SE HA QUEDADO ATRAS (enganchado en una esquina, o el que lo lleva va con retraso por la red): en
	# vez de dejarlo clavado contra la pared mientras el otro sigue andando, vuelve a su mano.
	if cube.global_position.distance_to(want) > 6.0:
		cube.global_position = want
	cube.linear_velocity = (want - cube.global_position) * 12.0
	cube.angular_velocity = Vector3(0.0, 1.2, 0.0)


## Los bots avisan de que estan al lado del terminal (enemy.gd). Los jugadores se cuentan solos.
func bot_en_terminal(equipo: String) -> void:
	if equipo != "":
		_presentes[equipo] = true


func _color_terminal(c: Color) -> void:
	if cashout == null:
		return
	var ring = cashout.get_meta("ring") if cashout.has_meta("ring") else null
	if ring:
		var g := _glow(c, 5.0)
		for h in ring.get_children():
			if h is MeshInstance3D:
				(h as MeshInstance3D).material_override = g
	var l = cashout.get_meta("lamp") if cashout.has_meta("lamp") else null
	if l and is_instance_valid(l):
		l.light_color = c


## EL ROBO DEL TERMINAL (anfitrion): quien esta al lado, quien avanza, y el cambio de color.
func _tick_captura(dt: float) -> void:
	var slot: Vector3 = cashout.global_position
	for a in _actores():
		if bool(a["vivo"]) and (a["pos"] as Vector3).distance_to(slot) < CAPTURE_RANGE:
			_presentes[String(a["equipo"])] = true
	# los BOTS que haya al lado cuentan, esten peleando o no
	for e in get_tree().get_nodes_in_group("enemies"):
		if "team" in e and String(e.team) != "" and is_instance_valid(e) \
				and ("health" not in e or float(e.health) > 0.0) \
				and (e as Node3D).global_position.distance_to(slot) < CAPTURE_RANGE:
			_presentes[String(e.team)] = true
	var dueno_esta: bool = _presentes.has(out_equipo)
	var ladrones: Array = []
	for eq in _presentes.keys():
		if String(eq) != out_equipo and String(eq) != "":
			ladrones.append(String(eq))
	_presentes.clear()
	# un solo equipo ladron y sin el dueño al lado: avanza. Con el dueño, o con dos ladrones: disputado.
	if ladrones.size() == 1 and not dueno_esta:
		if captura_equipo != ladrones[0]:
			captura_equipo = ladrones[0]
			captura_t = 0.0
		captura_t += dt
		if captura_t >= CAPTURE_TIME:
			var antes := out_equipo
			out_equipo = captura_equipo
			captura_t = 0.0
			captura_equipo = ""
			_cambio_de_color(antes, out_equipo)
			if Net.is_online() and Net.hosting:
				Net.net_atraco_evento("robo", {"antes": antes, "ahora": out_equipo})
	elif ladrones.is_empty():
		captura_t = maxf(0.0, captura_t - dt * 2.0)      # se fueron: la barra se cae
		if captura_t <= 0.0:
			captura_equipo = ""


## El terminal cambia de dueño: color, sonido y el aviso que toque a cada uno.
func _cambio_de_color(antes: String, ahora: String) -> void:
	_color_terminal(_color_de(ahora))
	Audio.play3d("clickup", cashout.global_position, 1.0, 0.05, 40.0, Audio.PRI_HIGH)
	if ahora != "":
		Audio.voz("objetivo_capturado" if ahora == Net.my_team() else "objetivo_perdido", 1)
	if hud == null:
		return
	if ahora == _mi_equipo():
		hud.flash_message("¡TERMINAL ROBADO! El ingreso ahora es para tu equipo")
	elif antes == _mi_equipo():
		hud.flash_message("¡%s TE HA ROBADO EL INGRESO! Recuperalo" % Net.nombre_equipo(ahora))
	else:
		hud.flash_message("%s se ha quedado el ingreso" % Net.nombre_equipo(ahora))


# --- ingreso (anfitrion) ----------------------------------------------------
func _tick_cashout(dt: float) -> void:
	if out_state == OUT_HIDDEN or out_state == OUT_DONE or cashout == null:
		return
	var slot: Vector3 = cashout.global_position + Vector3(0, 0.9, 0)
	if out_state == OUT_WAITING:
		# SE COLOCA SOLO SI CAE CERCA. Antes habia que dejarlo a 1,1 m del hueco, casi encajado: si rodaba
		# y se quedaba al pie del terminal no entraba ("si el cubo cae cerca de la terminal no se coloca,
		# no seria mas facil?"). Ahora basta con que este al lado, lo lleve alguien o no.
		var dc: Vector3 = cube.global_position - slot if cube and is_instance_valid(cube) else Vector3(99, 99, 99)
		if Vector2(dc.x, dc.z).length() < RADIO_COLOCAR and dc.y > -2.0 and dc.y < 2.0:
			# ES DEL COLOR DE QUIEN LO HA TRAIDO (el ultimo que lo llevo, aunque lo haya empujado dentro)
			var equipo := _ultimo_equipo_cubo
			if equipo == "":
				# nadie lo ha llevado (entro rodando): del jugador vivo mas cercano al terminal
				var mejor := 1.0e9
				for a in _actores():
					var dd: float = (a["pos"] as Vector3).distance_to(slot)
					if bool(a["vivo"]) and dd < mejor:
						mejor = dd
						equipo = String(a["equipo"])
			_soltar()
			cube.freeze = true
			cube.global_position = slot
			out_state = OUT_DEPOSITING
			out_t = 0.0
			out_equipo = equipo
			captura_t = 0.0
			captura_equipo = ""
			if out_equipo != "":
				_color_terminal(_color_de(out_equipo))
		return
	out_t += dt
	if cube and is_instance_valid(cube):
		cube.global_position = slot          # el cubo va metido en el terminal: si este cae, cae con el
	var ring = cashout.get_meta("ring") if cashout.has_meta("ring") else null
	if ring:
		ring.rotation.y += dt * 2.0
	_tick_captura(dt)
	if out_t >= DEPOSIT_TIME:
		# EL INGRESO SE TERMINA EN TODAS LAS MAQUINAS A LA VEZ: evento fiable, y los puntos se suman al
		# recibirlo (incluido el propio anfitrion). Sin red, se aplica directamente.
		if Net.is_online() and Net.hosting:
			Net.net_atraco_evento("ingreso", {"id": heist_id, "pts": POINTS, "equipo": out_equipo})
		else:
			_ingreso_terminado(POINTS, out_equipo)


func _ingreso_terminado(pts: int, equipo: String) -> void:
	if out_state == OUT_DONE:
		return
	out_state = OUT_DONE
	score += pts
	carrier = 0
	if cube and is_instance_valid(cube):
		cube.queue_free()
	cube = null
	if cashout:
		Audio.play3d("clickup", cashout.global_position + Vector3(0, 0.9, 0), 2.0, 0.05, 40.0, Audio.PRI_HIGH)
		Audio.ui("botin_entregado", -4.0)
	cash_deposited.emit(pts, equipo)
	if hud:
		if equipo == _mi_equipo() or equipo == "":
			hud.flash_message("¡INGRESADO! +%d puntos" % pts)
		else:
			hud.flash_message("%s ha ingresado la plata: +%d para ellos" % [Net.nombre_equipo(equipo), pts])


# --- red: lo que manda el anfitrion y lo que pinta el invitado --------------
func _estado() -> Dictionary:
	var e := {"id": heist_id, "vp": vault.global_position, "cp": cashout.global_position,
		"vs": vault_state, "vt": vault_t, "ae": abre_equipo, "ap": abre_peer, "bt": bot_t, "be": _ultimo_equipo_bots,
		"ca": carrier, "ce3": _ultimo_equipo_cubo, "os": out_state, "ot": out_t, "oe": out_equipo,
		"kt": captura_t, "ke": captura_equipo, "sc": score, "cu": cube != null and is_instance_valid(cube)}
	if bool(e["cu"]):
		e["cx"] = cube.global_position
		e["cq"] = cube.global_transform.basis.get_rotation_quaternion()
	var mn := get_parent()
	if mn and "puntos_equipo" in mn:
		e["pts"] = mn.puntos_equipo
	return e


func _aplicar_estado(e: Dictionary) -> void:
	if not soy_copia and not (Net.is_online() and not Net.hosting):
		return
	if vault == null or cashout == null:
		return
	var id := int(e.get("id", 0))
	var mn0 := get_parent()
	if mn0 and "_atraco_ultimo_cobrado" in mn0 and id <= int(mn0._atraco_ultimo_cobrado):
		return          # estado del atraco que ya se cobro: llega tarde, se ignora
	if id != heist_id:
		# CAJA NUEVA: la que manda el anfitrion, en SU sitio. Se deja todo como recien puesto.
		heist_id = id
		vault_state = VAULT_IDLE
		out_state = OUT_HIDDEN
		cashout.visible = false
		if _vault_door:
			_vault_door.rotation.y = 0.0
			_vault_door.position = Vector3.ZERO
		_set_vault_led(Color(1.0, 0.2, 0.15), 4.0)
		if cube and is_instance_valid(cube):
			cube.queue_free()
		cube = null
	vault.global_position = e.get("vp", vault.global_position)
	cashout.global_position = e.get("cp", cashout.global_position)
	var vs := int(e.get("vs", VAULT_IDLE))
	if vs == VAULT_OPEN and vault_state != VAULT_OPEN:
		vault_state = VAULT_OPEN
		_abrir_visual()
	elif vs != VAULT_OPEN:
		if vs == VAULT_OPENING and vault_state != VAULT_OPENING:
			_set_vault_led(Color(1.0, 0.65, 0.1), 6.0)
		elif vs == VAULT_IDLE and vault_state == VAULT_OPENING:
			_set_vault_led(Color(1.0, 0.2, 0.15), 4.0)
		vault_state = vs
	vault_t = float(e.get("vt", 0.0))
	abre_equipo = String(e.get("ae", ""))
	abre_peer = int(e.get("ap", 0))
	bot_t = float(e.get("bt", 0.0))
	_ultimo_equipo_bots = String(e.get("be", ""))
	carrier = int(e.get("ca", 0))
	_ultimo_equipo_cubo = String(e.get("ce3", ""))
	var os := int(e.get("os", OUT_HIDDEN))
	if os != OUT_DONE:
		out_state = os
	out_t = float(e.get("ot", 0.0))
	var oe := String(e.get("oe", ""))
	if oe != out_equipo:
		var antes := out_equipo
		out_equipo = oe
		if os == OUT_DEPOSITING and antes != "" and oe != "":
			_color_terminal(_color_de(oe))
		elif oe != "":
			_color_terminal(_color_de(oe))
	captura_t = float(e.get("kt", 0.0))
	captura_equipo = String(e.get("ke", ""))
	score = int(e.get("sc", score))
	# el cubo: en el invitado es un cuerpo CONGELADO que se desliza a la postura del anfitrion
	if bool(e.get("cu", false)):
		if cube == null or not is_instance_valid(cube):
			_spawn_cube(e.get("cx", vault.global_position))
			cube.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			cube.freeze = true
		_cubo_meta_pos = e.get("cx", cube.global_position)
		_cubo_meta_rot = e.get("cq", Quaternion.IDENTITY)
	elif cube and is_instance_valid(cube) and out_state != OUT_DONE:
		cube.queue_free()
		cube = null
	# los puntos de los equipos, por si has entrado a mitad de partida
	var mn := get_parent()
	if e.has("pts") and mn and "puntos_equipo" in mn:
		var pts: Dictionary = e["pts"]
		if pts != mn.puntos_equipo:
			mn.puntos_equipo = pts.duplicate()
			if mn.hud and mn.hud.has_method("set_puntos_equipos"):
				mn.hud.set_puntos_equipos(mn.puntos_equipo, mn.PUNTOS_GANAR)


func _deslizar_cubo(dt: float) -> void:
	if cube == null or not is_instance_valid(cube):
		return
	var k := clampf(dt * 14.0, 0.0, 1.0)
	cube.global_position = cube.global_position.lerp(_cubo_meta_pos, k)
	var q := cube.global_transform.basis.get_rotation_quaternion().slerp(_cubo_meta_rot, k)
	cube.global_transform = Transform3D(Basis(q), cube.global_position)


## Los eventos fiables del anfitrion (llegan a todos, tambien a el mismo).
func _evento(tipo: String, datos: Dictionary) -> void:
	match tipo:
		"aviso":
			if int(datos.get("peer", 0)) == mi_id() and hud:
				hud.flash_message(String(datos.get("texto", "")))
		"robo":
			if soy_copia:
				out_equipo = String(datos.get("ahora", ""))
				_cambio_de_color(String(datos.get("antes", "")), out_equipo)
		"ingreso":
			var mn := get_parent()
			if mn and "_atraco_ultimo_cobrado" in mn:
				mn._atraco_ultimo_cobrado = maxi(int(mn._atraco_ultimo_cobrado), int(datos.get("id", 0)))
			_ingreso_terminado(int(datos.get("pts", POINTS)), String(datos.get("equipo", "")))
