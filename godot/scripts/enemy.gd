extends BotBase
const RagdollScript := preload("res://scripts/ragdoll.gd")   # cargado siempre: con load() se recompilaba al morir
const DueloScript := preload("res://scripts/duelo.gd")
## El minimapa, para poder marcar los disparos. Por preload y no por nombre de clase: los nombres
## globales viven en una cache que hay que reconstruir, y un preload no depende de eso.
const MinimapCls := preload("res://scripts/minimap.gd")
## Bot con comportamiento de defensor tipo CS2: NO sabe dónde está el jugador. Vigila un sitio de bomba
## (puestos de guardia alrededor), patrulla entre puestos, se agacha, mira alrededor, y sólo reacciona a lo
## que percibe: ver al jugador (cono de visión + línea de visión por voxels + tiempo de reacción), oír
## disparos cercanos, recibir daño o el aviso de un compañero. Al perder el contacto va al último sitio
## donde lo vio, busca unos segundos y vuelve a su puesto.
##
## Estados: GUARD (en el puesto, quieto o agachado, barriendo con la mirada) -> PATROL (andando al siguiente
## puesto) -> INVESTIGATE (hacia un ruido / última posición conocida) -> COMBAT (lo ve: dispara, avanza o
## se cubre) -> SEARCH (lo perdió: busca alrededor).
## Usa la navegación dinámica de vxcore (find_path sobre la rejilla) y se mueve sobre los voxels.

## Al morir se dice DE QUE BANDO era (el punto es del contrario), QUIEN lo mato y COMO SE LLAMABA:
## con eso se lleva el marcador de bajas y la tabla de la pantalla de victoria.
signal died(pos: Vector3, equipo: String, asesino: Node, victima: String)

enum State { GUARD, PATROL, INVESTIGATE, COMBAT, SEARCH }

const WALK_SPEED := 1.9
const RUN_SPEED := 3.8
## ESPRINTAR. No es correr un poco mas: es lo que hace un jugador cuando tiene que CRUZAR -a cubierto
## para recargar, o a plantarse encima de alguien que esta lejos-. Antes los bots solo tenian dos
## marchas y siempre parecian ir a media gana.
const SPRINT_SPEED := 5.4

# --- MUNICION Y RECARGA -------------------------------------------------------------------------
# Los bots disparaban infinito y sin pausa. Eso no es solo poco realista: quita la ventana en la que
# un combate se decide, que es justo cuando el otro se queda sin balas.
const CARGADOR := 30
const RECARGA_S := 2.6
# (nativa, BotBase) var municion := CARGADOR
# (nativa, BotBase) var recarga_t := 0.0
# (nativa, BotBase) var cubierto_pos := Vector3.ZERO      ## a donde va a esconderse mientras recarga
# (nativa, BotBase) var _busca_cover := false

# --- ARMAS -------------------------------------------------------------------------------------
# Antes todos nacian con el mismo fusil y morian con el. Ahora cada bot lleva DOS y cambia segun la
# situacion, igual que un jugador: el fusil para lo normal y algo para cuando eso no sirve.
#
# El lanzacohetes no se saca por gusto: se saca cuando el objetivo esta LEJOS, que es donde un fusil
# ya no acierta. Y volver al fusil en cuanto se acerca, porque un cohete de cerca te mata a ti.
const ROCKET_SCENE := preload("res://scenes/rocket.tscn")
const CARGADOR_COHETE := 1
# (nativa, BotBase) var arma := "rifle"
# (nativa, BotBase) var arma_2 := "rocket"
## --botscohete=<m> (2026-10-02, banco de tirones demoliendo): TODOS llevan lanzacohetes y lo sacan a partir de <m> metros
## (de fabrica, 6 de cada 10 y a 18 m)
static var _cohete_m: float = _leer_cohete_m()


static func _leer_cohete_m() -> float:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--botscohete"):
			return float(String(a).substr(13)) if String(a).contains("=") else 6.0
	return 0.0
# (nativa, BotBase) var swap_t := 0.0                     ## mientras cambia de arma no dispara: sacarla tarda
const GRAVITY := 15.0
const VIEW_DIST := 45.0
const FOV_DEG := 110.0
const HEAR_ALERT_RADIUS := 20.0     # los compañeros a esta distancia se enteran cuando uno ve al jugador

# (nativa, BotBase) var world
# (nativa, BotBase) var player
## BANDO del bot ("t" / "ct"). Los de tu bando son ALIADOS: no te ven como enemigo, no te disparan
## y tú tampoco les haces daño. Su objetivo pasa a ser el bot enemigo más cercano.
# (nativa, BotBase) var team := ""
## Qué hace este bot en el equipo. Lo pone main.gd al repartir bandos (ver `_dar_rol`).
# (nativa, BotBase) var rol := ""
## Quien le hizo dano por ultima vez (bot o jugador). Lo apunta quien dispara justo antes de hacer el
## dano; al morir se avisa con el, y asi el marcador sabe a quien darle la baja.
var ultimo_atacante: Node = null
## Nombre para el marcador de fin de partida. Distinto de la etiqueta flotante, que a los rivales no
## se les pone: aqui todos necesitan uno para salir en la tabla y poder ser MVP.
var nombre_marcador := ""
# (nativa, BotBase) var compa: Node3D = null      ## para los terroristas: a quién le cubro la espalda
# (nativa, BotBase) var _mando_t := 0.0
# (nativa, BotBase) var target: Node3D = null      # a quién está atacando ahora mismo
var bot_name := ""             # "BOT 1"...: sólo lo llevan los aliados
var _tag: Label3D = null
# (nativa, BotBase) var id := 0
# (nativa, BotBase) var health := 100.0
var _last_push := Vector3.ZERO
var _quejido_t := -10.0     ## ultimo quejido de dolor (capa de Battlefield)
## Con que arma SUENA este bot (Audio.PERFIL_ARMA): cada uno la suya, no veinte fusiles iguales
var _arma_sonido: String = Audio.ARMAS_BOT[randi() % Audio.ARMAS_BOT.size()]
# (nativa, BotBase) var path: PackedVector3Array = PackedVector3Array()
# (nativa, BotBase) var path_i := 0
# (nativa, BotBase) var replan_t := 0.0
# (nativa, BotBase) var fire_t := 1.0
# (nativa, BotBase) var stuck_t := 0.0
# (nativa, BotBase) var _atasco_reps := 0          ## intentos seguidos sin moverse con camino por delante (ver _physics_inner)
# (nativa, BotBase) var last_los := false

# IA
# (nativa, BotBase) var state: int = State.GUARD
# (nativa, BotBase) var site_pos := Vector3.ZERO           # sitio de bomba que defiende
# (nativa, BotBase) var posts: Array = []                  # puestos de guardia (Vector3) alrededor del sitio
# (nativa, BotBase) var post_i := 0
# (nativa, BotBase) var move_target := Vector3.ZERO
# (nativa, BotBase) var guard_t := 0.0                     # tiempo restante en el puesto
# (nativa, BotBase) var partial_n := 0                    # tramos parciales seguidos sin acercarse al destino
# (nativa, BotBase) var best_remaining := 1e9             # mejor distancia al destino en este viaje
# (nativa, BotBase) var direct_t := 0                      # replanificaciones seguidas sin camino (andando recto)
# (nativa, BotBase) var rover := false                     # patrulla por todo el mapa (paradas cortas) en vez de vigilar un sitio
# (nativa, BotBase) var crouching := false
# (nativa, BotBase) var yaw_base := 0.0                    # orientación de referencia en el puesto
# (nativa, BotBase) var yaw_target := 0.0
# (nativa, BotBase) var look_t := 0.0
# (nativa, BotBase) var awareness := 0.0                   # 0..1: tiempo de reacción antes de disparar
# (nativa, BotBase) var last_known := Vector3.ZERO
# (nativa, BotBase) var last_known_t := -100.0             # instante en que se supo algo del jugador
# (nativa, BotBase) var search_t := 0.0
# (nativa, BotBase) var lost_t := 0.0
# (nativa, BotBase) var _time := 0.0
# (nativa, BotBase) var combat_strafe := 0.0
# (nativa, BotBase) var combat_strafe_t := 0.0
## s que le quedan de "me estan disparando": mientras corre, no se para ni se agacha. Ver take_damage.
# (nativa, BotBase) var bajo_fuego_t := 0.0

## El cohete de un bot rompe el mapa igual que el del jugador (ver `_lanzar_cohete`).
const COHETE_RADIO := 4.0
const COHETE_POTENCIA := 255

const AvatarScript := preload("res://scripts/avatar_animator.gd")
const RocketScene := preload("res://scenes/rocket.tscn")

# --- Bot de demostración (menú: BOT DEMO) ---
# Da vueltas alrededor de un punto alternando andar y correr, para poder ver las animaciones
# desde fuera, y lanza cohetes contra las paredes. NUNCA dispara al jugador ni lo persigue.
# --- Desactivar la bomba (son los policías) ---
# La mitad del escuadrón lleva pinzas: desactivan en la mitad de tiempo, como el kit de CS2.
var has_kit := false
var _defusing := false
# (nativa, BotBase) var demo := false
var demo_center := Vector3.ZERO
var demo_radius := 6.0
# --- modo PROMO (grabacion del video) ---
## Con `demo_target` puesto, el bot deja de dar vueltas: se planta y machaca ESE punto. Es lo que
## permite dirigir una escena (que todos disparen a la misma pared) en vez de que cada uno tire
## por su lado. `demo_gun` = fusil a rafagas; si no, lanzacohetes.
var demo_target := Vector3.ZERO
var demo_gun := false
var demo_rate := 3.5              ## segundos entre cohetes (o entre rafagas)
var demo_fx = null                ## nodo de efectos, para las trazas y el polvo de las balas
## Bot de escaparate: apunta y deja de apuntar en bucle, para poder ver de cerca el gesto del ojo y
## como sube el arma sin tener que pelearse con el en una partida.
var demo_apunta := false
var _apunta_t := 0.0
## Bot de escaparate del MAZO: da mazazos en bucle, sin moverse ni disparar, para ver el gesto
## entero desde fuera mientras se ajusta.
var demo_mazo := false
var _mazo_t := 0.0
## Bot de escaparate que se limpia la cara en bucle, para ver el gesto desde fuera.
var demo_limpia := false
var _limpia_t2 := 0.0
var _burst := 0
var _burst_t := 0.0
var _demo_a := 0.0
var _demo_fire := 2.0
var _demo_phase := 0.0

@onready var mesh: MeshInstance3D = $Mesh
# (nativa, BotBase) var avatar: Node3D

## `i` es el INDICE del bot dentro de su equipo: escalona el A*, reparte los botiquines y coloca. Se
## repite entre equipos y despues de una muerte, a proposito. Para la RED no vale: ahi hace falta un
## numero que no se repita nunca, y ese es `red_id`, que pone quien crea el bot.
## El color con el que se monta el muñeco en `setup`. main lo pone ANTES con el del bando (`_color_bando_bot`), y asi
## `_pintar_bot` ya no tiene que reconstruirlo: antes cada bot que reaparecia montaba su muñeco y su arma DOS veces.
var tinte_build := Color(1.0, 0.75, 0.7)

## EL CEREBRO EN C++ (2026-10-02, pedido: "pasa la IA de los bots a C++"): esta clase hereda de BotBase
## (godot/extension/src/bot_base.cpp), que lleva las variables del cerebro con los mismos nombres y el paso entero
## (`c_tick`, lo que hace `_physics_inner`). Lo que toca otras piezas del juego (disparar, cohete, armas, recarga, bomba,
## atraco, mazazos, daño, muerte) sigue aqui y el C++ lo llama. Los que heredan de este archivo con su propio cerebro
## (aliado_pve.gd) siguen con el GDScript, pero el movimiento (`_go_to`, `_voxel_move`...) va por el C++ en todos.
## --sinbotcerebro: todo el GDScript de siempre.
static var _CEREBRO_C: bool = ClassDB.class_has_method("BotBase", "c_tick") and not ("--sinbotcerebro" in OS.get_cmdline_user_args())
var _cerebro_c := false

## el cerebro de fuera (prop_hunt.gd): si esta puesto, `pensar_bot(self, dt)` manda en vez de la IA de siempre
var cerebro_ext: Object = null

func setup(w, p, i: int) -> void:
	_cerebro_c = _CEREBRO_C and (get_script() as Script).resource_path == "res://scripts/enemy.gd"
	world = w
	player = p
	id = i
	# LA VIDA DE UNA PERSONA (2026-10-13, pedido): 300 (100 en los modos zombi), como player.vida_max() sin cartas.
	# Antes 100. --botsvidaantes = antes.
	if not ("--botsvidaantes" in OS.get_cmdline_user_args()):
		health = preload("res://scripts/player.gd").VIDA_PVE if Settings.modo == "pve" else preload("res://scripts/player.gd").VIDA_NORMAL
	replan_t = 0.07 * (i % 12)   # escalona las planificaciones entre enemigos (1 A* por frame como máximo en la práctica)
	has_kit = (i % 2) == 0     # la mitad del escuadrón lleva pinzas
	add_to_group("enemies")
	add_to_group("bots")
	add_to_group("damageable")
	# skin: el avatar por defecto (mismo que el jugador), con un tinte rojizo para identificarlo
	mesh.visible = false
	$Head.visible = false
	if _nocol and has_node("Collision"):
		$Collision.disabled = true
	if "--botsnophys" in OS.get_cmdline_user_args():   # diagnóstico: bots sin lógica alguna
		set_physics_process(false)
	if "--botsnoavatar" in OS.get_cmdline_user_args():   # diagnóstico: cápsula roja en vez de avatar
		mesh.visible = true
	else:
		var _ts := Time.get_ticks_usec()
		avatar = AvatarScript.new()
		add_child(avatar)
		# sin sombras propias: 24 mallas por bot x N bots serían demasiados casters en móvil
		avatar.build(AvatarScript.ALTURA, false, tinte_build, false)
		Prof.add("bot.setup.avatar", Time.get_ticks_usec() - _ts)
		_ts = Time.get_ticks_usec()
		if not "--botsnoweapon" in OS.get_cmdline_user_args():
			_elegir_arma_propia()
			_montar_arma("rifle")
		Prof.add("bot.setup.arma", Time.get_ticks_usec() - _ts)
		_ts = Time.get_ticks_usec()
		avatar.play("idle_1")
		Prof.add("bot.setup.play", Time.get_ticks_usec() - _ts)
		if "--botsanim0" in OS.get_cmdline_user_args():   # diagnóstico: avatar estático
			avatar.set_process(false)
	# UNO DE CADA TRES LLEVA LANZACOHETES de secundaria. Si lo llevaran todos, cualquier pelea a
	# distancia se convertiria en una lluvia de cohetes y el mapa duraria dos minutos.
	# MAS COHETES. De uno de cada tres a SEIS de cada diez: la pelea se vuelve destructiva de verdad,
	# con paredes abriendose y coberturas que dejan de existir a mitad de tiroteo.
	arma_2 = "rocket" if randf() < 0.60 or _cohete_m > 0.0 else ""
	yaw_base = randf() * TAU
	yaw_target = yaw_base
	rotation.y = yaw_base

# --- PARECER UNA PERSONA ------------------------------------------------------------------------
# Un bot que camina recto, mira al frente y no hace nada raro se delata en dos segundos. Lo que hace
# que alguien parezca humano no es la punteria: son los TICS. Mirar alrededor sin motivo, agacharse
# por costumbre, adelantarse corriendo y volver, y sobre todo responder cuando lo miras.
#
# Nada de esto tiene funcion tactica. Es exactamente por eso que funciona.
# (nativa, BotBase) var sigue: Node3D = null           ## a quién acompaña, si a alguien
# (nativa, BotBase) var _sigue_visto := false          ## ya se decidió a quién seguir (una sola vez)
# (nativa, BotBase) var _sigue_t := 0.0                ## lo que le queda de acompañarte antes de irse a lo suyo
# (nativa, BotBase) var _quieto_t := 0.0               ## cuánto lleva sin moverse aquel a quien sigue
# (nativa, BotBase) var _sigue_pos := Vector3.ZERO     ## dónde estaba la última vez que se miró
# (nativa, BotBase) var _salto_t := 0.0                ## enfriamiento entre saltos
# (nativa, BotBase) var _gesto_pitch := 0.0            ## cabeceo de gesto, encima de la mirada normal
# (nativa, BotBase) var _gesto_t := 0.0
# (nativa, BotBase) var _mirado_t := 0.0               ## cuánto llevas mirándole
# (nativa, BotBase) var _saludo_t := 0.0               ## agachándose en bucle para saludar
# (nativa, BotBase) var _saludo_tic := 0.0
# (nativa, BotBase) var _adelanta_t := 0.0             ## se ha ido por delante corriendo


func _humano(dt: float) -> void:
	if state == State.COMBAT:
		_saludo_t = 0.0
		_adelanta_t = 0.0
		return
	# A QUIEN SIGO. 30 % de las veces a una persona de verdad; si no, otro 30 % a un compañero. El
	# resto va a lo suyo, porque un equipo entero pegado a alguien tampoco es humano.
	if not _sigue_visto:
		_sigue_visto = true
		_sigue_t = randf_range(18.0, 35.0)   # acompaña un rato, no la ronda entera
		# CON UN SITIO QUE ATACAR O DEFENDER NO SE QUEDA DE MASCOTA (2026-09-23, pedido): en el modo bomba
		# dos aliados se quedaban a tu lado sin ir a por los policias. Solo acompaña quien no tiene cometido.
		if not posts.is_empty():
			_sigue_t = 0.0
		elif randf() < 0.30 and is_instance_valid(player) and is_ally_of(String(player.team) if "team" in player else ""):
			sigue = player
		elif randf() < 0.30:
			var amigos: Array = []
			for b in get_tree().get_nodes_in_group("bots"):
				if b != self and is_instance_valid(b) and is_ally_of(String(b.team)):
					amigos.append(b)
			if not amigos.is_empty():
				sigue = amigos[randi() % amigos.size()]

	# EL SALUDO. Si te ha estado mirando dos segundos seguidos, se agacha y se levanta a toda prisa
	# durante uno o dos segundos. Es el saludo que se hacen los jugadores desde siempre, y es de las
	# cosas que mas gritan "aqui hay alguien" — ningun bot hace eso.
	if _saludo_t > 0.0:
		_saludo_t -= dt
		_saludo_tic -= dt
		if _saludo_tic <= 0.0:
			_saludo_tic = 0.12
			crouching = not crouching
		if _saludo_t <= 0.0:
			crouching = false
		return

	# ¿ME ESTA MIRANDO? Solo tiene sentido con una persona: se compara hacia donde apunta SU camara
	# con la direccion en la que estoy yo.
	if sigue != null and is_instance_valid(sigue) and sigue == player and "cam" in player and player.cam != null:
		var ojo: Vector3 = player.cam.global_position
		var hacia: Vector3 = (global_position + Vector3(0, 1.2, 0) - ojo)
		var d: float = hacia.length()
		if d < 22.0 and (-player.cam.global_transform.basis.z).dot(hacia / maxf(d, 0.01)) > 0.985:
			_mirado_t += dt
			if _mirado_t > 2.0:
				_mirado_t = 0.0
				_saludo_t = randf_range(1.0, 2.0)
				_saludo_tic = 0.0
				return
		else:
			_mirado_t = maxf(_mirado_t - dt * 2.0, 0.0)

	# LOS GESTOS. Barrer la mirada de lado y cabecear arriba y abajo, cada dos o tres segundos y sin
	# motivo. Un bot con la cabeza clavada al frente se ve muerto aunque camine.
	_gesto_t -= dt
	if _gesto_t <= 0.0:
		_gesto_t = randf_range(1.6, 3.4)
		yaw_base += randf_range(-0.9, 0.9)
		_gesto_pitch = randf_range(-0.28, 0.20)
		if randf() < 0.22:
			crouching = not crouching        # se agacha por costumbre, no por tactica
	_gesto_pitch = move_toward(_gesto_pitch, 0.0, dt * 0.35)

	if sigue == null or not is_instance_valid(sigue):
		return

	# ACOMPAÑAR TIENE FINAL. Antes se elegia a quien seguir UNA vez y ya no se soltaba nunca: si te
	# tocaba uno, lo tenias pegado la ronda entera, incluso parado a tu lado mientras la partida
	# pasaba en otro sitio. Eso no es un compañero, es una mascota.
	#
	# Se suelta por dos motivos:
	#   - se acaba el rato de acompañar (medio minuto largo)
	#   - o a quien sigue LLEVA UN RATO SIN MOVERSE. Si tu te quedas quieto, el se aburre y se va a
	#     hacer lo suyo, que es lo que haria alguien de verdad.
	_sigue_t -= dt
	var movido: float = _sigue_pos.distance_to(sigue.global_position)
	_sigue_pos = sigue.global_position
	if movido < 0.02:
		_quieto_t += dt
	else:
		_quieto_t = 0.0
	if _sigue_t <= 0.0 or _quieto_t > 5.0:
		sigue = null
		_quieto_t = 0.0
		# y a su puesto: el que le toque por su cometido, sin quedarse ahi plantado
		if not posts.is_empty():
			_enter_patrol()
		return

	# ACOMPAÑAR. Ni pegado ni perdido: entre tres y siete metros. Y de vez en cuando SE ADELANTA
	# corriendo, salta, encara un momento y vuelve — igual que alguien que va contigo y se emociona.
	var dd: float = global_position.distance_to(sigue.global_position)
	if _adelanta_t > 0.0:
		_adelanta_t -= dt
		var fwd: Vector3 = -sigue.global_transform.basis.z
		move_target = sigue.global_position + fwd * 9.0
		_go_to(move_target, SPRINT_SPEED, dt, 1.5)
		# UN SALTO DE VEZ EN CUANDO, no dos por segundo. Esto era `randf() < 0.03` sin mas, y como se
		# evalua CADA FOTOGRAMA, a 60 fps salian casi dos saltos por segundo: el bot cruzaba el mapa
		# botando como un conejo. Con el enfriamiento sale uno cada varios segundos, que era la idea.
		_salto_t -= dt
		if on_floor and _salto_t <= 0.0 and randf() < dt * 0.25:
			_salto_t = 2.5
			velocity.y = 5.2
		if avatar:
			avatar.aiming = randf() < 0.5
		if _adelanta_t <= 0.0 and avatar:
			avatar.aiming = false
		return
	if dd > 7.0:
		move_target = sigue.global_position
		_go_to(move_target, RUN_SPEED if dd > 12.0 else WALK_SPEED, dt, 2.5)
	elif dd < 3.0:
		_stop(dt)
	elif randf() < 0.004:
		_adelanta_t = randf_range(1.5, 3.0)


## ESCUCHAR AL MANDO. Cada medio segundo, un bot que no esté peleando mira el tablón (ver
## escuadra.gd) y decide si le toca ir. La decisión depende de SU PUESTO, y ahí está la diferencia
## entre un equipo y una manada:
##
##   - Los que guardan un sitio solo se mueven si el aviso es EN SU SITIO. Si abandonan el punto
##     porque se oyen tiros en la otra punta, los terroristas plantan la bomba tranquilos — que es
##     exactamente el error que comete un equipo malo.
##   - Los que campean caminos acuden si es cerca.
##   - El grupo de reacción acude siempre: para eso está.
##   - El compañero de una pareja no decide nada: va con su líder.
##
## Y quien va SE APUNTA en el tablón, así el siguiente que pregunte ve una plaza menos y se queda
## donde estaba. Sin eso, todos los avisos los atenderían todos.
func _mando(dt: float) -> void:
	_mando_t -= dt
	if _mando_t > 0.0:
		return
	_mando_t = 0.5
	if state == State.COMBAT:
		return                       # ya está ocupado, no hace falta mandarle a ningún sitio

	# EL COMPAÑERO CUBRE LA ESPALDA. Se coloca tres metros por detrás del líder y barre la mirada
	# hacia donde el líder NO mira: entre los dos cubren los dos sentidos del pasillo.
	if rol == "compa":
		if compa != null and is_instance_valid(compa) and compa.health > 0.0:
			move_target = compa.global_position + compa.global_transform.basis.z * 3.0
			if state == State.GUARD:
				state = State.PATROL
			yaw_base = compa.rotation.y + PI
		return

	var f: Vector3 = Escuadra.foco(team)
	if is_inf(f.x):
		return
	var d: float = global_position.distance_to(f)
	var voy := false
	match rol:
		"sitio_a", "sitio_b":
			voy = site_pos != Vector3.ZERO and f.distance_to(site_pos) < 18.0
		"camino":
			voy = d < 30.0
		"reaccion":
			voy = true
		"lider":
			voy = d < 45.0
		_:
			voy = d < 25.0
	if not voy:
		return
	Escuadra.apuntarse(team, f)
	last_known = f
	last_known_t = _time
	_enter_investigate()


## Sitio a defender y sus puestos (los calcula main.gd por mapa).
# --- SIN ARMA (battle royale) -----------------------------------------------------------------
## EN LA ISLA SE EMPIEZA CON LAS MANOS VACIAS, tambien los bots. Antes caian del avion con el fusil
## puesto y te cosian a tiros nada mas tocar el suelo, mientras tu ibas a buscar la primera pistola.
## Mientras `sin_arma` esta puesto el bot no dispara y va a por el botin (lo manda main.gd).
# (nativa, BotBase) var sin_arma := false

## Deja al bot con las manos vacias.
func desarmar() -> void:
	sin_arma = true
	arma_2 = ""
	arma = ""
	if avatar and avatar.has_method("equip_weapon"):
		avatar.equip_weapon("vacio")


## Ya ha llegado a un arma del suelo: la coge.
func armar() -> void:
	if not sin_arma:
		return
	sin_arma = false
	arma_2 = "rocket" if randf() < 0.25 else ""
	_montar_arma("rifle")


func assign_site(site: Vector3, site_posts: Array) -> void:
	site_pos = site
	posts = site_posts.duplicate()
	posts.shuffle()
	post_i = 0
	_enter_guard()

# (nativa, BotBase) var _inval_t := 0.0
## Enfriamiento: durante un derrumbe esto llegaba muchas veces por segundo y cada llamada forzaba
## un A* nuevo. Con 0,6 s de margen el bot sigue reaccionando al mundo sin replanificar en bucle.
func invalidate_path() -> void:
	if _time - _inval_t < 0.6:
		return
	_inval_t = _time
	_invalidate_path_now()

func _invalidate_path_now() -> void:
	path = PackedVector3Array()
	replan_t = 0.0
	partial_n = 0
	best_remaining = 1e9

# ---------------------------------------------------------------------------
# Percepción
# ---------------------------------------------------------------------------
## Un disparo / explosión del jugador en `pos` audible hasta `radius` m (lo llama player.gd por grupo).
## ¿A quién ataco? Al jugador si es del bando contrario; si es de mi bando (aliado), al bot rival
## vivo más cercano. Así los bots de tu equipo pelean contra los del otro y a ti te dejan en paz.
## LAS PERSONAS VALEN POR DOS.
##
## La eleccion era "el mas cercano del bando contrario", y con ocho bots pegandose entre ellos SIEMPRE
## hay un bot mas cerca que tu: el jugador humano se paseaba y nadie le hacia caso. Medido en el banco:
## de ocho bots, cero miraban a la persona.
##
## Contando su distancia a la mitad, una persona gana salvo que este el doble de lejos que el bot mas
## proximo. No es un numero fino, es la diferencia entre una partida que te hace caso y una en la que
## eres un mueble.
const VENTAJA_HUMANO := 0.5


## INVISIBLE (la habilidad, habilidad.gd): no se le busca salvo que se le tenga encima
func _no_se_ve(n: Node3D) -> bool:
	return bool(n.get("invisible")) and n.global_position.distance_to(global_position) > 1.5   # (era 3 m: ver BotBase::_no_se_ve)


func _pick_target() -> void:
	var best: Node3D = null
	var best_d := INF
	if is_instance_valid(player) and float(player.health) > 0.0 and not bool(player.get("spectating")) and not is_ally_of(String(player.team) if "team" in player else "") and not _no_se_ve(player):
		best = player
		best_d = global_position.distance_to(player.global_position) * VENTAJA_HUMANO
	# LOS JUGADORES DE LAS OTRAS MAQUINAS TAMBIEN CUENTAN.
	#
	# Aqui solo se miraba al jugador de ESTA maquina y a los demas bots, asi que para los bots un
	# invitado no existia: pasabas por delante y no te miraban siquiera. Como la IA corre solo en el
	# anfitrion, era el anfitrion el unico al que atacaban.
	#
	# El daño ya tiene camino: `net_player.take_damage` se lo manda a su dueño, que es quien lleva su
	# vida. No hace falta nada nuevo, solo mirarlos.
	for r in Net.remotes.values():
		if not is_instance_valid(r) or ("dead" in r and r.dead):
			continue
		if is_ally_of(Net.team_of(int(r.peer_id))) or _no_se_ve(r):
			continue
		var dr := global_position.distance_to(r.global_position) * VENTAJA_HUMANO
		if dr < best_d:
			best_d = dr
			best = r
	for b in get_tree().get_nodes_in_group("bots"):
		if b == self or not is_instance_valid(b) or b.health <= 0.0:
			continue
		if is_ally_of(String(b.team)):
			continue
		var d := global_position.distance_to(b.global_position)
		if d < best_d:
			best_d = d
			best = b
	target = best


## Pone el cartel con el nombre encima. Solo los ALIADOS lo llevan: a un rival no le ves la
## etiqueta, igual que en cualquier shooter por equipos.
func set_bot_name(n: String) -> void:
	bot_name = n
	# el nombre decide su arma y su pintura: se vuelve a montar con la que le toca
	if n != "" and avatar and not sin_arma and arma in ["", "rifle"] and not "--botsnoweapon" in OS.get_cmdline_user_args():
		_elegir_arma_propia()
		_montar_arma("rifle")
	if is_instance_valid(_tag):
		_tag.queue_free()
		_tag = null
	if n == "":
		return
	_tag = Label3D.new()
	_tag.text = n
	_tag.font_size = 40
	_tag.pixel_size = 0.0022
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.modulate = Color(0.55, 0.85, 1.0)
	_tag.outline_size = 12
	_tag.position = Vector3(0, 2.05, 0)
	_tag.visible = false          # los aliados con nombre: lo pinta etiquetas_equipo.gd, con su vida
	add_child(_tag)


## Mismo bando (y con bando asignado) = aliado.
func is_ally_of(other_team: String) -> bool:
	return team != "" and other_team != "" and other_team == team


## EL QUE DEFIENDE UN SITIO NO LO ABANDONA (2026-09-23): el policia de B oia tiros en el centro, se iba a
## mirar y B se quedaba vacio. Solo acude a lo que pase cerca de su sitio; lo lejano es de los demas.
const RADIO_DEFENSA := 22.0
func _lejos_de_mi_sitio(pos: Vector3) -> bool:
	return String(rol).begins_with("sitio_") and site_pos != Vector3.ZERO and pos.distance_to(site_pos) > RADIO_DEFENSA

func hear_noise(pos: Vector3, radius: float) -> void:
	if state == State.COMBAT or _lejos_de_mi_sitio(pos):
		return
	var d := global_position.distance_to(pos)
	if d > radius:
		return
	if has_meta("br_bot") and d > 16.0:
		return                      # battle royale (bots_br.gd): un tiro lejano no es razon para ir a buscarlo
	# el oído localiza a bulto: error proporcional a la distancia
	last_known = pos + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * (d * 0.12)
	last_known_t = _time
	if state != State.INVESTIGATE or randf() < 0.5:
		_enter_investigate()

## Aviso de un compañero que ha visto al jugador.
func alert(pos: Vector3) -> void:
	if state == State.COMBAT or _lejos_de_mi_sitio(pos) or has_meta("br_bot"):
		return
	last_known = pos
	last_known_t = _time
	_enter_investigate()

func _can_see_player(eye: Vector3, target_eye: Vector3) -> bool:
	var to := target_eye - eye
	var dist := to.length()
	if dist > VIEW_DIST:
		return false
	if has_meta("vigia"):        # los vigias de la cafeteria (main._vigias_tick): 45 m y 360 grados
		return world.has_line_of_sight(eye, target_eye)
	# cono de visión (salvo a bocajarro)
	if dist > 2.5:
		var fwd := -global_transform.basis.z
		var flat := Vector3(to.x, 0.0, to.z).normalized()
		if fwd.dot(flat) < cos(deg_to_rad(FOV_DEG * 0.5)):
			return false
	# agachado y quieto el jugador es más difícil de ver de lejos
	if player.crouching and dist > 25.0 and randf() < 0.5:
		return false
	return world.has_line_of_sight(eye, target_eye)

# ---------------------------------------------------------------------------
# Estados
# ---------------------------------------------------------------------------
func _enter_guard() -> void:
	if rover:
		state = State.GUARD
		crouching = false
		guard_t = randf_range(1.0, 3.0)
		yaw_base = rotation.y
		yaw_target = yaw_base
		look_t = 0.0
		return
	state = State.GUARD
	guard_t = randf_range(4.0, 10.0)
	crouching = randf() < 0.45
	yaw_base = rotation.y
	if site_pos != Vector3.ZERO:
		# de cara a la aproximación al sitio (hacia fuera del sitio), con algo de variación
		var away := global_position - site_pos
		if away.length() > 1.0:
			yaw_base = atan2(-away.x, -away.z) + PI + randf_range(-0.6, 0.6)
	yaw_target = yaw_base
	look_t = 0.0

## Recién aparecido en el spawn de policías: sale ya hacia su primer puesto (no vigila el spawn).
## CAMINO DE IDA POR OTRO LADO (2026-09-23, pedido): con la navegacion arreglada todos iban por el camino
## corto. `via` es un punto por el que pasa antes de su primer puesto (lo pone main.gd a la mitad de los
## bots): unos entran por el corto y otros dan la vuelta por el centro o los tuneles.
var via := Vector3.ZERO

func deploy() -> void:
	if posts.is_empty():
		return
	state = State.PATROL
	crouching = false
	post_i = randi() % posts.size()
	move_target = posts[post_i]
	if via != Vector3.ZERO:
		move_target = via
		post_i = (post_i - 1 + posts.size()) % posts.size()   # al llegar al desvio sigue a ese puesto
		via = Vector3.ZERO
	invalidate_path()

func _enter_patrol() -> void:
	if posts.is_empty():
		_enter_guard()
		return
	state = State.PATROL
	crouching = false
	post_i = (post_i + 1) % posts.size()
	move_target = posts[post_i]
	invalidate_path()

func _enter_investigate() -> void:
	state = State.INVESTIGATE
	crouching = false
	move_target = last_known
	invalidate_path()

func _enter_combat() -> void:
	if _pd_rompiendo_t > 0.0:   # estaba a mazazos con una pared: fuera el mazo, que hay pelea
		_pd_rompiendo_t = 0.0
		_montar_arma(arma if arma != "" else "rifle")
	state = State.COMBAT
	crouching = false
	lost_t = 0.0
	combat_strafe_t = 0.0
	# avisar a los compañeros cercanos
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != self and e.global_position.distance_to(global_position) < HEAR_ALERT_RADIUS:
			e.alert(last_known)

func _enter_search() -> void:
	state = State.SEARCH
	search_t = randf_range(4.0, 7.0)
	crouching = randf() < 0.3
	yaw_base = rotation.y
	look_t = 0.0

static var _prof := "--bench" in OS.get_cmdline_user_args() or "--posedbg" in OS.get_cmdline_user_args() or "--botsprof" in OS.get_cmdline_user_args()
static var _noshoot := "--botsnoshoot" in OS.get_cmdline_user_args()   # diagnóstico
static var _nocol := "--botsnocol" in OS.get_cmdline_user_args()       # diagnóstico: sin cuerpo físico
static var _prof_us := {"total": 0, "los": 0, "path": 0, "shoot": 0, "move": 0}
static var _prof_n := 0
static var _prof_paths := 0
var _pt := 0
## --botsprof: cuanto se lleva cada parte del tick (al Prof, con su peor tramo: para cazar los tirones)
func _pk(k: String) -> void:
	var ahora := Time.get_ticks_usec()
	Prof.add("bot." + k, ahora - _pt)
	_pt = ahora

# ---------------------------------------------------------------------------
# COPIA DE RED (invitados)
#
# Un bot marcado como `remoto` NO PIENSA: no busca camino, no dispara y no reparte daño. Solo se
# mueve hacia donde dice el anfitrion y reproduce el clip que le manda. Toda la inteligencia de este
# archivo se queda apagada, y eso es justo lo que garantiza que las dos pantallas vean lo mismo.
# ---------------------------------------------------------------------------

# (nativa, BotBase) var remoto := false          ## soy una copia: el que manda es el anfitrion
## MI NUMERO EN LA RED, el mismo en todas las maquinas. Lo pone quien me crea (el anfitrion) y no se
## repite nunca; `id` es otra cosa (el indice dentro del equipo) y ese si se repite.
# (nativa, BotBase) var red_id := 0
var _red_pos := Vector3.ZERO
var _red_giro := 0.0
var _red_hay := false


## Lo que manda el anfitrion, 15 veces por segundo.
func poner_estado_red(p: Vector3, giro: float, clip: String, vida: float) -> void:
	_red_pos = p
	_red_giro = giro
	_red_hay = true
	health = vida
	if clip != "" and avatar != null and avatar.current_clip != clip:
		avatar.play(clip)


## Se ACERCA al sitio que dijo el anfitrion en vez de saltar: con 15 paquetes por segundo, saltar se
## ve a tirones. Es el mismo suavizado que usan las criaturas del PvE y los jugadores remotos.
func _mover_remoto(dt: float) -> void:
	if not _red_hay:
		return
	global_position = global_position.lerp(_red_pos, clampf(dt * 12.0, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, _red_giro, clampf(dt * 10.0, 0.0, 1.0))
	if avatar != null:
		avatar.move_amount = clampf(global_position.distance_to(_red_pos) * 4.0, 0.0, 1.0)


func _physics_process(dt: float) -> void:
	if remoto:
		_mover_remoto(dt)
		return

	if not world or not player:
		return
	# EL SEGUNDO PASO DE FISICA DEL MISMO CUADRO NO SE REPITE (2026-10-02, pedido: "cuando hay muchos bots juntos
	# disparandose se llena de lag"; medido con --botsjuntos: casi todos los cuadros lentos llevaban DOS pasos de fisica, y en
	# cada uno los bots pensaban y se movian otra vez: su coste se doblaba, el cuadro siguiente llegaba tarde otra vez y se
	# entraba en espiral). La pantalla solo se dibuja una vez por cuadro, asi que el segundo paso de un bot no se ve: se
	# guarda el tiempo y va todo junto en el paso del cuadro siguiente (como el medio ritmo de los de lejos). En el aire, a
	# todo ritmo (la ventana para posarse es de 0,6 m: ver abajo). A/B: --sinpasodoble.
	var cuadro := Engine.get_process_frames()
	if cuadro == _ultimo_cuadro and on_floor and not _sin_paso_doble:
		_ia_acum += dt
		return
	_ultimo_cuadro = cuadro
	# IA POR DISTANCIA. Con 29 bots (battle royale) la IA entera eran 6-11 ms por cuadro con picos de 60. Un
	# bot a mas de IA_LEJOS m de cualquier persona piensa y se mueve uno de cada IA_PASO ticks con el tiempo
	# acumulado: a esa distancia no se nota, y el paso sigue siendo corto (0,2 m a 6 m/s) para no colarse por
	# una pared de 0,3 m. Cerca de alguien, a todo ritmo.
	var fr := Engine.get_physics_frames() + id
	if fr % 30 == 0:
		_d_personas = _distancia_a_personas()
		_ia_lejos = _d_personas > IA_LEJOS
	# A MEDIO RITMO TAMBIEN LO QUE NO SE VE (2026-10-01): a mas de IA_MEDIO m de cualquier persona y fuera de la camara
	# de esta maquina (nadie lo esta mirando: su paso de 0,2 m no se nota, y quien lo ve en otra pantalla lo recibe por
	# red a 20 Hz igual). Con 9 bots en la cafeteria, la mitad suelen estar a tu espalda.
	if fr % 10 == 0:
		# (2026-10-14, banco de la CPU del movil): fuera de la camara desde IA_MEDIO 12 m (eran 25) y, a la vista, desde
		# IA_VISTA_LEJOS 45 m (antes solo desde 70). --medioritmoantes = los umbrales de antes
		var m_fuera: float = 25.0 if _medio_antes else IA_MEDIO
		var m_vista: float = IA_LEJOS if _medio_antes else IA_VISTA_LEJOS
		_ia_fuera = not _sin_medio_ritmo and ((_d_personas > m_fuera and _fuera_de_camara()) or _d_personas > m_vista)
	# EN EL AIRE, SIEMPRE A TODO RITMO: a medio ritmo un bot que cae a 20 m/s baja 0,66 m de una vez y la ventana para
	# posarse en el suelo es de 0,6 m (_voxel_move): se podia colar por el suelo al caer.
	if (_ia_lejos or _ia_fuera) and on_floor:
		_ia_acum += dt
		if fr % IA_PASO != 0:
			return
		dt = _ia_acum
		_ia_acum = 0.0
	elif _ia_acum > 0.0:
		dt += _ia_acum
		_ia_acum = 0.0
	var _t0 := Time.get_ticks_usec()
	# UN CEREBRO DE FUERA (2026-10-21, prop_hunt.gd): si lo hay y dice que lo ha movido el, solo se aplica el paso y la
	# animacion (como el atraco)
	if cerebro_ext != null and is_instance_valid(cerebro_ext) and cerebro_ext.pensar_bot(self, dt):
		if not on_floor:
			velocity.y -= GRAVITY * dt    # la gravedad la pone la IA de siempre (c_tick): sin ella, el que saltaba un escalon salia volando
		_voxel_move(dt)
		if avatar:
			var lv := transform.basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
			avatar.drive_locomotion(lv, crouching, on_floor, 0, dt)
		Prof.add("enemy", Time.get_ticks_usec() - _t0)
		return
	if _cerebro_c:
		if _diag:
			_diag_tick(dt)
		c_tick(dt)
	else:
		_physics_inner(dt)
	Prof.add("enemy", Time.get_ticks_usec() - _t0)   # suma de todos los bots, al CSV
	if _prof:
		_prof_us["total"] += Time.get_ticks_usec() - _t0
		_prof_n += 1
		if _prof_n >= 3000:
			print("[bots] por bot y tick: total %.3f ms | los %.3f | path %.3f (%d rutas) | shoot %.3f | move %.3f" % [
				_prof_us["total"] / 1000.0 / _prof_n, _prof_us["los"] / 1000.0 / _prof_n, _prof_us["path"] / 1000.0 / _prof_n, _prof_paths, _prof_us["shoot"] / 1000.0 / _prof_n, _prof_us["move"] / 1000.0 / _prof_n])
			for k in _prof_us.keys():
				_prof_us[k] = 0
			_prof_n = 0
			_prof_paths = 0

const IA_LEJOS := 70.0
const IA_MEDIO := 12.0
const IA_VISTA_LEJOS := 45.0
static var _medio_antes: bool = "--medioritmoantes" in OS.get_cmdline_user_args()
const IA_PASO := 2
var _ia_lejos := false
var _ia_acum := 0.0
var _ia_fuera := false
var _d_personas := 0.0
static var _sin_medio_ritmo: bool = "--sinmedioritmo" in OS.get_cmdline_user_args()   ## A/B
static var _sin_paso_doble: bool = "--sinpasodoble" in OS.get_cmdline_user_args()      ## A/B
var _ultimo_cuadro := -1


## Lo que hay hasta la persona mas cercana (el jugador de esta maquina y los de las demas)
func _distancia_a_personas() -> float:
	var p := global_position
	var d2 := INF
	if is_instance_valid(player):
		d2 = player.global_position.distance_squared_to(p)
	for r in Net.remotes.values():
		if is_instance_valid(r):
			d2 = minf(d2, r.global_position.distance_squared_to(p))
	return sqrt(d2) if d2 < INF else INF


func _fuera_de_camara() -> bool:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return false
	var p := global_position
	return not cam.is_position_in_frustum(p + Vector3(0, 0.9, 0)) and not cam.is_position_in_frustum(p + Vector3(0, 1.7, 0))


static var _diag := "--diagbots" in OS.get_cmdline_user_args()
var _diag_t := 0.0
var _diag_pos := Vector3.ZERO

func _diag_tick(dt: float) -> void:
	_diag_t -= dt
	if _diag_t <= 0.0:
		_diag_t = 3.0
		var mov := global_position.distance_to(_diag_pos)
		_diag_pos = global_position
		print("[diagbots] %s %s rol=%s estado=%s pos=%s destino=%s dist=%.1f camino=%d movido3s=%.1f%s" % [
			String(team), nombre_marcador if "nombre_marcador" in self else str(id), String(rol) if "rol" in self else "",
			State.keys()[state], str(global_position.snapped(Vector3(0.1, 0.1, 0.1))), str(move_target.snapped(Vector3(0.1, 0.1, 0.1))),
			global_position.distance_to(move_target), path.size(), mov, "  <<< ATASCADO" if mov < 0.5 and state == State.PATROL else ""])


func _physics_inner(dt: float) -> void:
	if _diag:
		_diag_tick(dt)
	_time += dt
	if caido_t > 0.0:
		caido_t -= dt
		return
	if demo:
		_demo(dt)
		return
	if _try_defuse(dt):
		return       # con la bomba plantada, desactivarla manda sobre todo lo demás
	if not on_floor:
		velocity.y -= GRAVITY * dt
	if team == "":
		return       # todavia no me han asignado bando: no disparo a nadie (antes, en los primeros
	                 # frames tras aparecer, un aliado te tomaba por enemigo y te pegaba un tiro)
	if _prof:
		_pt = Time.get_ticks_usec()
	if (Engine.get_physics_frames() + id) % 12 == 0 or not is_instance_valid(target) or _no_se_ve(target) or (target == player and float(player.health) <= 0.0):
		_pick_target()
	if _prof:
		_pk("pick")
	if not is_instance_valid(target):
		return       # no queda nadie del otro bando a quien atacar
	var eye := global_position + Vector3(0, 0.9 if crouching else 1.25, 0)
	var t_crouch: bool = bool(target.crouching) if "crouching" in target else false
	var target_eye: Vector3 = target.global_position + Vector3(0, 0.72 if t_crouch else 1.08, 0)
	var dist := global_position.distance_to(target.global_position)
	var _tl := Time.get_ticks_usec()
	# la línea de visión (rayo de hasta 45 m) se evalúa cada 3 ticks por bot, escalonado; entre medias se
	# mantiene el último valor
	var los := last_los
	if (Engine.get_physics_frames() + id) % 3 == 0:
		los = _can_see_player(eye, target_eye)
	if _prof:
		_prof_us["los"] += Time.get_ticks_usec() - _tl
	replan_t -= dt
	fire_t -= dt

	# reacción: hace falta verlo un rato (menos si está cerca) antes de disparar
	if los:
		awareness = minf(1.0, awareness + dt * (3.0 if dist < 8.0 else (1.6 if dist < 20.0 else 1.0)))
		last_known = target.global_position
		last_known_t = _time
		if awareness >= 1.0 and state != State.COMBAT:
			_enter_combat()
	else:
		awareness = maxf(0.0, awareness - dt * 0.7)
	last_los = los

	if _prof:
		_pk("los")
	_humano(dt)
	if _prof:
		_pk("humano")
	_mando(dt)
	if _prof:
		_pk("mando")
	# EL ATRACO TAMBIEN ES SUYO. Fuera de combate, en vez de patrullar sin rumbo, van a por la caja e
	# intentan abrirla igual que tu. Si te ven por el camino, mandan los disparos: esto solo corre
	# cuando NO esta en COMBAT, asi que verte siempre interrumpe el trabajo.
	if state != State.COMBAT and _atraco_tick(dt):
		_voxel_move(dt)
		# CON SU ANIMACION. Este `return` se saltaba el `drive_locomotion` de abajo, asi que mientras
		# iban a la caja fuerte o al terminal los bots se DESLIZABAN rigidos por la ciudad: "los bots no
		# caminan, no veo la animacion de caminata, caminan duros".
		if avatar:
			var lv_atraco: Vector3 = transform.basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
			avatar.drive_locomotion(lv_atraco, crouching, on_floor, 0, dt)
			avatar.look_pitch = lerpf(avatar.look_pitch, 0.0, 4.0 * dt)
			if avatar.aiming:
				avatar.aiming = false
		return
	match state:
		State.GUARD:
			_stop(dt)
			guard_t -= dt
			_look_around(dt, 0.9)
			if guard_t <= 0.0:
				_enter_patrol()
		State.PATROL:
			# QUE CORRAN. Patrullar era SIEMPRE andando, a 1,9 m/s, y como los bots se pasan casi toda
			# la ronda en este estado, practicamente nunca se les veia correr. Y en un mapa donde el
			# sitio A esta a cuarenta metros del spawn, andando no llegaban antes de que se acabara
			# todo.
			#
			# Ahora la prisa depende de lo lejos que este el destino: se esprinta si queda medio mapa,
			# se corre si queda un tramo, y se anda solo en los ultimos metros -que es cuando de
			# verdad quieres ir despacio, para no plantarte en el puesto sin mirar-.
			var lejos: float = global_position.distance_to(move_target)
			var v: float = WALK_SPEED
			if lejos > 22.0:
				v = SPRINT_SPEED
			elif lejos > 7.0:
				v = RUN_SPEED
			var _tpd := Time.get_ticks_usec()
			var _atascado := _pd_atasco(dt)
			if _prof:
				Prof.add("bot.patrol.atasco", Time.get_ticks_usec() - _tpd)
			if _atascado:
				pass     # rompiendo la pared o dando la vuelta: ya se mueve el
			elif _go_to(move_target, v, dt, 0.8):
				if _pd_rodeo_t > 0.0:
					_pd_rodeo_t = 0.0
					move_target = _pd_destino_real   # hecho el rodeo, vuelta a lo suyo
					invalidate_path()
				else:
					_enter_guard()
		State.INVESTIGATE:
			var arrived := _go_to(move_target, SPRINT_SPEED if global_position.distance_to(move_target) > 14.0 else RUN_SPEED, dt, 1.2)
			if arrived or _time - last_known_t > 14.0:
				_enter_search()
		State.SEARCH:
			_stop(dt)
			search_t -= dt
			_look_around(dt, 1.4)
			if search_t <= 0.0:
				_enter_patrol()
		State.COMBAT:
			_combat(dt, los, eye, target_eye, dist)
	if _prof:
		_pk("estado." + State.keys()[state])
	var _tm := Time.get_ticks_usec()
	_voxel_move(dt)
	if _prof:
		_prof_us["move"] += Time.get_ticks_usec() - _tm
		_pk("move")

	if avatar:
		# misma función que usa el jugador: direccion por octantes, cadencia atada a la velocidad
		# real, salto y variantes de reposo. Antes los bots solo usaban 4 clips y se notaba.
		var lvel: Vector3 = transform.basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
		avatar.drive_locomotion(lvel, crouching, on_floor, 0, dt)
		# mirar (y apuntar) hacia el jugador cuando lo ve
		var to := target_eye - eye
		avatar.look_pitch = (atan2(to.y, Vector2(to.x, to.z).length()) if los else lerpf(avatar.look_pitch, 0.0, 4.0 * dt)) + _gesto_pitch
		# ENCARAR DE VERDAD. Aqui solo se llamaba a hold_action(), que unicamente adelanta el reloj
		# de "acabo de disparar" para que suba el arma. Lo que dispara la animacion de apuntar (el
		# arma subiendo al ojo y el ojo cerrandose) es `aiming`, y NADIE se lo ponia a los bots: por
		# eso nunca se les veia encarar aunque te estuvieran disparando a la cara.
		var encara: bool = state == State.COMBAT and los
		if avatar.aiming != encara:
			avatar.aiming = encara
		if state == State.COMBAT:
			avatar.hold_action()

	# atascado -> replanificar
	if state in [State.PATROL, State.INVESTIGATE] and Vector2(velocity.x, velocity.z).length() < 0.25 and path_i < path.size():
		stuck_t += dt
		if stuck_t > 0.8:
			stuck_t = 0.0
			_atasco_reps += 1
			# NO INSISTIR ETERNAMENTE. Replanificar da el mismo camino, asi que si tras cuatro intentos sigue sin
			# moverse es que ahi no se llega andando -un puesto en una repisa a tres metros, por ejemplo- y se pasa
			# al siguiente en vez de quedarse mirandolo. Medido en dust2: pausas de 8-10 s en cada ronda.
			if _atasco_reps >= 4:
				_atasco_reps = 0
				if state == State.PATROL:
					_enter_guard()
				else:
					_enter_search()
			else:
				invalidate_path()
	else:
		stuck_t = 0.0
		if Vector2(velocity.x, velocity.z).length() > 0.5:
			_atasco_reps = 0

	pass
	# POR DEBAJO DE LA ALTURA MINIMA DEL MAPA TAMBIEN SE HA CAIDO. Para el motor de voxels bajo el mundo
	# hay suelo (vx_world: `if (mn.y < 0) return true`), asi que un bot que sale de hangar -recortado
	# al galpon- no llega nunca a -10: aterriza a 0 m, de pie, fuera, y el A* no le deja volver.
	if global_position.y < -10.0 or (Net.dm_mode and global_position.y < Net.dm_altura_minima):
		# CAER AL VACIO. Antes el bot se borraba sin mas, sin avisar de que habia muerto. En duelo a
		# muerte eso lo sacaba de la partida PARA SIEMPRE -nadie lo reponia, porque la reposicion
		# cuelga de `died`- y su bando se iba quedando corto. En hangar pasa si sale del galpon, donde
		# ya no hay suelo. Ahi cuenta como una muerte normal y vuelve a su base; en los demas modos,
		# como siempre.
		if Net.dm_mode:
			take_damage(health + 1.0)
		else:
			queue_free()

## Combate: dispara si lo ve; si no, va a la última posición conocida; tras 6 s sin verlo, busca.
## Si hay bomba plantada, el policía va a por ella y la desactiva quedándose encima. Devuelve
## true mientras esté ocupado en eso, para que no siga con su rutina normal.
func _try_defuse(dt: float) -> bool:
	# LA DESACTIVA LA POLICIA, Y NADIE MAS. Aqui no se miraba el bando: cualquier bot corria a la bomba y le
	# cortaba los cables, asi que los TERRORISTAS desactivaban su propia C4 en cuanto la plantabas (lo conto el
	# usuario). El jugador humano si lo comprobaba (`player.gd::_update_defuse`).
	if team != Net.TEAM_CT:
		_defusing = false
		return false
	# la bomba es la MISMA para todos (`Net.bomb_node`): la plantada por otro jugador o por un bot tambien cuenta,
	# no solo la que plantó el jugador de esta maquina
	var bomb = Net.bomb_node
	if not is_instance_valid(bomb) and player != null and not player.planted_c4.is_empty() and player.planted_c4[0].has("node"):
		bomb = player.planted_c4[0].get("node")
	if bomb == null or not is_instance_valid(bomb) or bomb.state != bomb.State.PLANTED:
		_defusing = false
		return false
	# PRIMERO LOS QUE LA DEFIENDEN (2026-10-31, bug: "plantan, esperan a que los bots vengan corriendo y los matan
	# desactivando"). Si ve a un enemigo, o le acaban de pegar, pelea con el cerebro de siempre y vuelve a la bomba
	# cuando lo mata o lo pierde 2,5 s. Solo se lo juega todo a cortar cables si ya no da tiempo a otra cosa.
	if not _bomba_ciega and _hay_que_pelear_bomba(bomb, dt):
		_defusing = false
		return false
	var d: float = global_position.distance_to(bomb.global_position)
	if d > bomb.DEFUSE_RANGE:
		# aún no ha llegado: se acerca corriendo
		_defusing = false
		if not on_floor:
			velocity.y -= GRAVITY * dt
		_go_to(bomb.global_position, 5.0, dt, bomb.DEFUSE_RANGE * 0.7)
		_voxel_move(dt)
		if avatar:
			var lv: Vector3 = transform.basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
			avatar.drive_locomotion(lv, false, on_floor, 0, dt)
		return true
	# encima de la bomba: agachado y quieto mientras corta los cables
	_defusing = true
	crouching = true
	_stop(dt)
	_voxel_move(dt)
	_face(bomb.global_position)
	bomb.defusing = true
	bomb.defuse_with_kit = has_kit
	if avatar:
		avatar.drive_locomotion(Vector3.ZERO, true, on_floor, 0, dt)
	return true

static var _bomba_ciega: bool = "--bombaciega" in OS.get_cmdline_user_args()   # = como antes
var _bomba_pelea_t := 0.0     # cuanto le queda peleando antes de volver a la bomba
var _bomba_mira_t := 0.0
var _golpe_bomba_t := -99.0   # cuando le pegaron por ultima vez (_time)

func _hay_que_pelear_bomba(bomb, dt: float) -> bool:
	var dur: float = bomb.DEFUSE_KIT_TIME if has_kit else bomb.DEFUSE_TIME
	var falta: float = dur * (1.0 - bomb.defuse_ratio())
	# a tope de tiempo: o corta ya o explota; pelear es perder seguro
	if bomb.time_left < falta + 1.5:
		return false
	_bomba_pelea_t -= dt
	_bomba_mira_t -= dt
	if _bomba_mira_t <= 0.0:
		_bomba_mira_t = 0.15
		_pick_target()
		var t := target as Node3D
		if t != null and is_instance_valid(t) and float(t.get("health") if t.get("health") != null else 1.0) > 0.0:
			var eye := global_position + Vector3(0, 0.9 if crouching else 1.25, 0)
			var te := t.global_position + Vector3(0, 1.08, 0)
			# el que viene a la bomba va mirando las esquinas: ve en todas direcciones a media distancia
			var cerca := eye.distance_to(te) < 30.0
			var ve: bool = world.has_line_of_sight(eye, te) if cerca else _can_see_player(eye, te)
			if ve or _time - _golpe_bomba_t < 1.0:
				last_known = t.global_position
				last_known_t = _time
				awareness = 1.0
				_bomba_pelea_t = 2.5
	return _bomba_pelea_t > 0.0

## Vueltas en círculo alternando andar/correr + un cohete a la pared cada pocos segundos.
func _demo(dt: float) -> void:
	if not on_floor:
		velocity.y -= GRAVITY * dt
	if demo_target != Vector3.ZERO:
		_demo_dirigido(dt)
		return
	_demo_phase += dt
	# 6 s andando, 6 s corriendo: así se ven los dos ciclos y la transición entre ellos
	var running: bool = fmod(_demo_phase, 12.0) >= 6.0
	var speed := 5.0 if running else 2.6
	_demo_a += (speed / maxf(demo_radius, 0.5)) * dt
	var tgt := demo_center + Vector3(cos(_demo_a), 0.0, sin(_demo_a)) * demo_radius
	_move_toward(tgt, speed, dt, true)
	_voxel_move(dt)
	if avatar:
		var lv: Vector3 = transform.basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
		avatar.drive_locomotion(lv, false, on_floor, 0, dt)
	# cohete contra la pared: se busca uno de los lados, nunca hacia el jugador
	_demo_fire -= dt
	if _demo_fire <= 0.0:
		_demo_fire = demo_rate
		_demo_rocket()

## Bot dirigido a un punto: se queda quieto, mirando al objetivo, y lo machaca. Para el video.
func _demo_dirigido(dt: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_voxel_move(dt)
	_face(demo_target)
	if avatar:
		avatar.drive_locomotion(Vector3.ZERO, false, on_floor, 0, dt)
		if demo_limpia:
			_limpia_t2 -= dt
			if _limpia_t2 <= 0.0:
				_limpia_t2 = 2.6
				if avatar.has_method("play_limpiar"):
					avatar.play_limpiar(1.30)   # da tiempo a ver los tres tiempos del gesto
		if demo_mazo:
			# un mazazo, medio segundo de guardia, y otra vez
			_mazo_t -= dt
			if _mazo_t <= 0.0:
				_mazo_t = AvatarScript.swing_dur_s + 0.55
				if avatar.has_method("play_swing"):
					avatar.play_swing(AvatarScript.swing_dur_s)
		if demo_apunta:
			# 2 s encarando y 2 s con el arma abajo, en bucle
			_apunta_t += dt
			if _apunta_t >= 2.0:
				_apunta_t = 0.0
				avatar.aiming = not avatar.aiming
	if demo_mazo or demo_limpia:
		return   # los de escaparate no disparan nada
	var eye := global_position + Vector3(0, 1.30, 0)
	if demo_gun:
		# rafagas: 6 balas seguidas y una pausa, que suena y se ve mejor que un goteo constante
		_burst_t -= dt
		if _burst > 0 and _burst_t <= 0.0:
			_burst -= 1
			_burst_t = 0.085
			_demo_bala(eye)
		elif _burst <= 0:
			_demo_fire -= dt
			if _demo_fire <= 0.0:
				_demo_fire = demo_rate
				_burst = 6
				_burst_t = 0.0
		return
	_demo_fire -= dt
	if _demo_fire <= 0.0:
		_demo_fire = demo_rate
		var d := (demo_target - eye).normalized()
		var rk := RocketScene.instantiate()
		get_parent().add_child(rk)
		rk.global_position = eye + d * 0.8
		rk.setup(world, d, self, 4.0, 255, 0.0)   # daño 0 a la gente: solo rompe el edificio
		Net.net_cohete(rk.global_position, d, 4.0, 255, 0.0)
		Audio.play3d("tools/launcher", eye, 0.0, 0.05, 60.0, Audio.PRI_MID)


## Una bala del bot dirigido: muerde la pared de verdad y deja traza y polvo. `world.shoot` ya
## excava con la potencia que se le pase, asi que no hace falta un carve aparte.
func _demo_bala(eye: Vector3) -> void:
	var d := (demo_target - eye).normalized()
	d = (d + Vector3(randf_range(-0.03, 0.03), randf_range(-0.02, 0.02), randf_range(-0.03, 0.03))).normalized()
	# replicado: la bala del bot rompe la pared en TODAS las maquinas, no solo en la que lo mueve
	var vox: Dictionary = Net.net_shoot(world, eye, d, 80.0, 255)
	var fin: Vector3 = (vox.position if vox.hit else eye + d * 80.0)
	Audio.gunshot("rifle", eye, false, _arma_sonido)
	if avatar:
		avatar.kick()
	if demo_fx and is_instance_valid(demo_fx):
		demo_fx.tracer(eye + d * 0.6, fin)
		if vox.hit:
			demo_fx.impact(vox.position, vox.get("normal", Vector3.UP), int(vox.get("material", 0)),
				world.get_material_color(int(vox.get("material", 0))))


func _demo_rocket() -> void:
	var eye := global_position + Vector3(0, 1.4, 0)
	# se prueban varias direcciones y se elige una pared a tiro que no apunte al jugador
	for i in range(8):
		var a := _demo_a + TAU * float(i) / 8.0
		var d := Vector3(cos(a), 0.05, sin(a)).normalized()
		if is_instance_valid(target) and d.dot((target.global_position - global_position).normalized()) > 0.5:
			continue   # esa dirección va hacia el jugador: se descarta
		var r: Dictionary = world.raycast(eye, d, 40.0)
		if not r.hit or eye.distance_to(r.position) < 6.0:
			continue
		_face(global_position + d)
		var rk := RocketScene.instantiate()
		get_parent().add_child(rk)
		rk.global_position = eye + d * 0.8
		rk.setup(world, d, self, 4.0, 255, 0.0)   # daño 0: es una demostración, no ataca a nadie
		Audio.play3d("tools/launcher", eye, 0.0, 0.05, 60.0, Audio.PRI_MID)
		return

func _combat(dt: float, los: bool, eye: Vector3, target_eye: Vector3, dist: float) -> void:
	bajo_fuego_t = maxf(bajo_fuego_t - dt, 0.0)
	_visto_t = _visto_t + dt if los else 0.0
	# RECARGANDO: no dispara, y no se queda ahi plantado como un pato. Corre a un sitio desde donde
	# no lo vean, y si no encuentra ninguno se agacha, que es lo que hace cualquiera.
	if recarga_t > 0.0:
		recarga_t -= dt
		if recarga_t <= 0.0:
			if avatar and "reloading" in avatar:
				avatar.reloading = false
			municion = _cargador()
			_busca_cover = false
			crouching = false
		else:
			if cubierto_pos != Vector3.ZERO:
				# ESPRINTA a cubrirse: si va andando le da tiempo a que lo maten dos veces
				if _go_to(cubierto_pos, SPRINT_SPEED, dt, 1.0):
					cubierto_pos = Vector3.ZERO
					crouching = true
			else:
				crouching = true
				_stop(dt)
			_face(target.global_position if is_instance_valid(target) else global_position)
			return
	if los:
		lost_t = 0.0
		_face(target.global_position)
		# ¿ES ESTA EL ARMA? Lejos y con el cohete en la mochila, se saca. Cerca, se guarda.
		swap_t = maxf(swap_t - dt, 0.0)
		# A QUE DISTANCIA SE SACA EL COHETE. Estaba en 28 m, y en un mapa como dust2 casi ningun
		# tiroteo llega a esa distancia: el cohete no salia NUNCA, ni en la policia ni en los
		# terroristas, aunque seis de cada diez bots lo llevan encima. A 18 m si entra en juego, y
		# sigue sin usarse en los cara a cara, donde un cohete te mata a ti tambien.
		if arma_2 == "rocket" and swap_t <= 0.0 and recarga_t <= 0.0:
			if dist > (_cohete_m if _cohete_m > 0.0 else 18.0) and arma != "rocket":
				_cambiar_arma("rocket")
			elif dist < (minf(_cohete_m * 0.6, 11.0) if _cohete_m > 0.0 else 11.0) and arma != "rifle":
				_cambiar_arma("rifle")
		if fire_t <= 0.0 and recarga_t <= 0.0 and swap_t <= 0.0:
			# RAFAGAS DE AUTOMATICA (2026-09-23, pedido): antes era un tiro cada 0,45-1,1 s, o sea, una pistola
			# aunque llevara metralleta. Ahora rafagas de 3-7 balas a la cadencia del arma y una pausa entre
			# rafagas (la escopeta y el cohete siguen tiro a tiro).
			if arma == "rifle":
				var tb: Array = TIRO_BOT.get(arma_tipo, TIRO_BOT["rifle"])
				if _rafaga_n <= 0:
					_rafaga_n = randi_range(int(tb[0]), int(tb[1]))
				_rafaga_n -= 1
				_rafaga_i += 1
				var cad: float = float(CADENCIA_BOT.get(arma_modelo, tb[2]))
				fire_t = cad * randf_range(0.9, 1.15) if _rafaga_n > 0 else float(tb[3]) * randf_range(0.7, 1.4)
				if _rafaga_n <= 0:
					_rafaga_i = 0
			else:
				fire_t = randf_range(0.45, 1.1)
			municion -= 1
			# PRIMERO SE DISPARA, LUEGO SE GUARDA EL ARMA. Estaba al reves, y como el lanzacohetes
			# lleva UN solo cohete, al restar municion se quedaba en cero, volvia al fusil, y solo
			# ENTONCES se llamaba a _shoot(), que mira `arma` para decidir que sale. Resultado: el
			# cohete no salia jamas, ni en la policia ni en los terroristas, aunque catorce de los
			# diecinueve bots lo llevaban a la espalda. Se disparaba un tiro de fusil en su lugar.
			var _ts := Time.get_ticks_usec()
			if not _noshoot:
				_shoot(eye, target_eye)
			Prof.add("bot.disparo", Time.get_ticks_usec() - _ts)
			if _prof:
				_prof_us["shoot"] += Time.get_ticks_usec() - _ts
			# ya ha salido el cohete: ahora si, se guarda y se vuelve al fusil
			if municion <= 0:
				if arma == "rocket":
					_cambiar_arma("rifle")
					municion = _cargador()
				else:
					_empezar_recarga()
		combat_strafe_t -= dt
		if combat_strafe_t <= 0.0:
			# NUNCA QUIETO EN UN TIROTEO. El sorteo era [-1, 0, 1]: una de cada tres veces salia 0 y
			# el bot se quedaba PLANTADO delante de ti disparando, que es lo que lo delataba como bot.
			# Ahora siempre se mueve a un lado o a otro; lo que cambia es cada cuanto y cuanto aguanta.
			# Solo se agacha lejos y si no le estan dando: agacharse cerca es quedarse quieto.
			combat_strafe_t = randf_range(0.55, 1.4)
			combat_strafe = [-1.0, 1.0][randi() % 2]
			crouching = dist > 18.0 and bajo_fuego_t <= 0.0 and randf() < 0.25
		if bajo_fuego_t > 0.0:
			crouching = false
		var apurado: bool = bajo_fuego_t > 0.0
		if dist > 14.0 and not crouching:
			# de lejos se cierra ESPRINTANDO; de cerca ya no hace falta y encima quita punteria.
			# Bajo fuego no se avanza en linea recta hacia quien te dispara: se entra abriendose.
			var destino: Vector3 = target.global_position
			if apurado:
				destino += global_transform.basis.x * combat_strafe * 6.0
			_move_toward(destino, SPRINT_SPEED if (dist > 26.0 or apurado) else RUN_SPEED, dt, false)
		elif not crouching:
			var right := global_transform.basis.x
			# bajo fuego el quiebro es mas largo y mas rapido: salir del punto donde le estan apuntando
			var largo: float = 5.0 if apurado else 3.0
			var vel: float = RUN_SPEED if apurado else RUN_SPEED * 0.6
			_move_toward(global_position + right * combat_strafe * largo, vel, dt, false)
		else:
			_stop(dt)
	else:
		lost_t += dt
		crouching = false
		if lost_t > 6.0:
			_enter_search()
		else:
			# TE HA PERDIDO PERO SABE DONDE ESTAS: si lleva cohete, le abre la pared. Esto es lo que
			# convierte una cobertura en algo temporal — esconderse deja de ser gratis.
			if arma_2 == "rocket" and lost_t > 0.9 and fire_t <= 0.0 and recarga_t <= 0.0 and swap_t <= 0.0:
				if arma != "rocket":
					_cambiar_arma("rocket")
				elif global_position.distance_to(last_known) > 5.0:
					fire_t = randf_range(1.6, 2.8)
					municion = 0
					MinimapCls.marcar_disparo(global_position, team)
					_lanzar_cohete(eye, (last_known + Vector3(0, 0.6, 0) - eye).normalized())
					_cambiar_arma("rifle")
			# y va a la ultima posicion conocida a todo lo que da
			_go_to(last_known, SPRINT_SPEED, dt, 1.2)

## CAMBIAR DE ARMA. Tarda: sacar un lanzacohetes no es instantaneo, y ese medio segundo en el que no
## puede disparar es lo que hace que la decision tenga precio. Sin eso, cambiar seria gratis y el bot
## estaria todo el rato alternando.
## Que arma saca el bot para cada papel. Son las mismas del catalogo que llevan los jugadores.
## CADA BOT CON SU ARMA Y SU PINTURA (2026-09-23, pedido): antes todos llevaban la carabina, y encima con
## TU skin, porque el modelo de arma mira la skin que tiene equipada el jugador de esta maquina. Se elige
## con un hash del nombre (o del id si aun no lo tiene): sale igual en todas las maquinas de la partida.
## ARMA AL AZAR DE TODA LA TIENDA, FIJA POR PARTIDA (2026-09-23, pedido): cada bot saca una de la tienda
## (fusiles, subfusiles, escopetas, francotirador, pistolas y el escudo blindado) y la lleva la partida
## entera; la siguiente partida, otra. La semilla es la de la partida (`Net.semilla_partida`, la misma en
## todas las maquinas) mas el nombre del bot, asi que en red todos le ven la misma.
const ARMAS_BOT := [
	["carabina_556", "rifle"], ["fusil_762", "rifle"], ["fusil_bullpup", "rifle"],
	["smg_9mm", "smg"], ["smg_compacta", "smg"], ["pdw_57", "smg"],
	["escopeta_bomba", "shotgun"], ["escopeta_auto", "shotgun"], ["rifle_precision", "sniper"],
	["pistola_9", "pistol"], ["pistola_45", "pistol"], ["revolver_44", "pistol"],
	["escudo_pistola", "escudo"]]
## Como dispara cada tipo: [balas por rafaga min, max, segundos entre balas, pausa entre rafagas, daño, error extra]
## EL DAÑO DE LOS BOTS, EL DE LAS PERSONAS (2026-10-13, pedido: "igual que las personas, pero que fallen un poquito
## mas"): cada bala del bot quita lo mismo que la misma arma en manos de una persona (weapons.gd; la escopeta, todos sus
## perdigones juntos, que el bot tira un solo rayo). Antes era la columna 4 de TIRO_BOT (fusil 8, subfusil 6...: un
## tercio). A cambio fallan un 25 % mas (FALLO_BOT). --botsdanoantes = el daño de antes.
const FALLO_BOT := 1.25
## LOS BOTS ENTRE ELLOS (2026-10-13, pedido: "con una sola persona en la sala siempre gana: a partir de nivel 5, que los
## bots enemigos tengan punteria perfecta contra los bots; con dos o mas personas, todos los bots perfectos entre bots").
## Solo entre bots: a las personas les apuntan igual. Con UNA persona: los bots del OTRO bando que el suyo, desde su
## nivel BOTS_NIVEL_DESDE, fallan cada nivel menos hasta 0 en BOTS_NIVEL_TOPE. Con dos o mas: todos, 0.
## --sinequilibriobots = como antes.
const BOTS_NIVEL_DESDE := 5
const BOTS_NIVEL_TOPE := 10
static var _eq_t := -10.0
static var _eq_personas := 1
static var _eq_nivel := 1
static var _eq_bando := ""
static var _eq_off := -1

func _fallo_contra_bot() -> float:
	if _eq_off < 0:
		_eq_off = 1 if "--sinequilibriobots" in OS.get_cmdline_user_args() else 0
	if _eq_off == 1:
		return 1.0
	var ahora := Time.get_ticks_msec() * 0.001
	if ahora - _eq_t > 1.0:
		_eq_t = ahora
		_eq_personas = maxi(1, Net.players.size()) if Net.is_online() else 1
		_eq_nivel = Cuenta.nivel() if Cuenta.conectado() else Settings.nivel()
		_eq_bando = String(Net.my_team())
	if _eq_personas >= 2:
		return 0.0
	if String(team) == _eq_bando or _eq_nivel < BOTS_NIVEL_DESDE:
		return 1.0
	# nivel 5 -> la mitad del error; nivel 10 o mas -> perfecto
	var k := clampf(float(_eq_nivel - BOTS_NIVEL_DESDE + 1) / float(BOTS_NIVEL_TOPE - BOTS_NIVEL_DESDE + 1), 0.0, 1.0)
	return 0.5 * (1.0 - k) if k < 1.0 else 0.0
static var _dano_antes := -1

func _dano_bala_bot() -> float:
	if _dano_antes < 0:
		_dano_antes = 1 if "--botsdanoantes" in OS.get_cmdline_user_args() else 0
	var viejo := float(TIRO_BOT.get(arma_tipo, TIRO_BOT["rifle"])[4])
	if _dano_antes == 1:
		return viejo
	var cat: Dictionary = Weapons.catalog()
	var d: Dictionary = cat.get(String(arma_modelo), {})
	if d.is_empty() or String(d.get("kind", "")) != String(arma_tipo):
		d = cat.get(String(arma_tipo), {})
	if d.is_empty():
		return viejo
	return float(d.get("damage", viejo)) * float(maxi(1, int(d.get("pellets", 1))))


const TIRO_BOT := {
	"rifle":   [3, 7, 0.10, 0.55, 8.0, 0.0],
	"smg":     [4, 9, 0.075, 0.5, 6.0, 0.006],
	"shotgun": [1, 1, 0.0, 0.95, 26.0, 0.02],
	"sniper":  [1, 1, 0.0, 1.8, 45.0, -0.015],
	"pistol":  [1, 3, 0.28, 0.5, 11.0, 0.004],
	"escudo":  [1, 3, 0.30, 0.55, 11.0, 0.01]}
## balas por cargador segun su arma (antes 30 para todas, tambien la escopeta y la pistola)
const CARGADOR_TIPO := {"rifle": 30, "smg": 30, "shotgun": 7, "sniper": 5, "pistol": 12, "escudo": 17}
func _cargador() -> int:
	return int(CARGADOR_TIPO.get(arma_tipo, CARGADOR))

static var semilla_local := 0     ## sin red, la pone main.gd al empezar cada partida
# (nativa, BotBase) var arma_modelo := "carabina_556"
# (nativa, BotBase) var arma_tipo := "rifle"          ## el tipo de su arma principal (en `arma` sigue valiendo "rifle")
var skin_arma := ""

static var SIN_PINTURA_BOTS: bool = not ("--botsconpintura" in OS.get_cmdline_user_args())

func _elegir_arma_propia() -> void:
	var sem: int = int(Net.semilla_partida) if ("semilla_partida" in Net and int(Net.semilla_partida) != 0) else semilla_local
	var h: int = absi(hash("%d|%s" % [sem, bot_name if bot_name != "" else "bot%d" % id]))
	var ele: Array = ARMAS_BOT[h % ARMAS_BOT.size()]
	arma_modelo = String(ele[0])
	arma_tipo = String(ele[1])
	if arma == "rifle":
		municion = _cargador()
	var cat: Array = SkinsArmas.catalogo()
	# un tercio sin pintura; el resto, una del catalogo (las caras salen menos)
	var r := (h / 7) % 100
	skin_arma = ""
	# (2026-10-13, pedido: "los bots sin pinturas, el arma de fabrica"): SIN_PINTURA_BOTS; --botsconpintura = antes
	if not SIN_PINTURA_BOTS and r >= 33 and not cat.is_empty() and arma_tipo != "escudo":
		var pool: Array = []
		for sk in cat:
			var peso: int = maxi(1, 6 - int(sk.get("rareza", 0)))
			for _k in peso:
				pool.append(String(sk["id"]))
		skin_arma = pool[(h / 701) % pool.size()]

## Monta en el muñeco el arma de este tipo, con SU skin (no la del jugador).
func _montar_arma(kind: String) -> void:
	if not avatar or not avatar.has_method("equip_weapon"):
		return
	var aid: String = arma_modelo if kind == "rifle" else String(ARMA_BOT.get(kind, "carabina_556"))
	var k2: String = arma_tipo if kind == "rifle" else kind
	if "skin_arma_forzada" in avatar:
		avatar.skin_arma_forzada = (skin_arma if skin_arma != "" else "-") if kind == "rifle" else "-"
	var _tq := Time.get_ticks_usec()
	avatar.equip_weapon(k2, aid)
	Prof.add("bot.arma.equipar", Time.get_ticks_usec() - _tq)
	_tq = Time.get_ticks_usec()
	var wm = avatar._wm if ("_wm" in avatar) else null
	if wm != null and is_instance_valid(wm):
		wm.skin_forzada = skin_arma if kind == "rifle" else ""
		if wm.skin_forzada == "":
			wm.skin_forzada = "-"   # "-" = sin pintura (no leer la del jugador)
		wm.repintar_skin()
	Prof.add("bot.arma.repintar", Time.get_ticks_usec() - _tq)

const CADENCIA_BOT := {"carabina_556": 0.10, "fusil_762": 0.13, "fusil_bullpup": 0.09, "smg_9mm": 0.075, "pdw_57": 0.07}
# (nativa, BotBase) var _rafaga_n := 0
# (nativa, BotBase) var _rafaga_i := 0
# (nativa, BotBase) var _visto_t := 0.0   ## cuanto lleva viendo a su objetivo seguido (la sorpresa)

const ARMA_BOT := {"rifle": "carabina_556", "rocket": "bazooka_rpg", "smg": "smg_9mm",
	"shotgun": "escopeta_bomba", "pistol": "pistola_9", "sniper": "rifle_precision", "sledge": ""}


func _cambiar_arma(kind: String) -> void:
	if arma == kind:
		return
	arma = kind
	swap_t = 0.55
	fire_t = maxf(fire_t, 0.55)
	municion = CARGADOR_COHETE if kind == "rocket" else _cargador()
	if avatar and avatar.has_method("equip_weapon"):
		# UN ARMA DE VERDAD, no solo un tipo: cada modelo vive en res://armas/<id>.glb. Sin id el bot
		# se quedaba con las manos vacias desde que las armas se modelan en Blender.
		var _tca := Time.get_ticks_usec()
		_montar_arma(kind)
		Prof.add("bot.cambiar_arma", Time.get_ticks_usec() - _tca)
	if avatar and avatar.has_method("hold_swap"):
		avatar.hold_swap(0.45)
	Audio.bf3d("soldado/coger_arma", global_position + Vector3(0, 1.2, 0), -6.0, 25.0, Audio.PRI_LOW)   # Teardown no trae "tools/equip"


## EL COHETE. Sale de la boca del arma como el del jugador y usa la misma escena, asi que estalla,
## hace su onda y revienta el mapa igual. Un bot con lanzacohetes puede abrirte la pared detras de la
## que te escondes, que es justo la gracia.
static var cohetes_lanzados := 0     # solo para las pruebas: cuantos cohetes ha tirado alguien

func _lanzar_cohete(eye: Vector3, dir: Vector3) -> void:
	cohetes_lanzados += 1
	var _tc := Time.get_ticks_usec()
	var r = ROCKET_SCENE.instantiate()
	get_parent().add_child(r)
	Prof.add("bot.c.crear", Time.get_ticks_usec() - _tc)
	_tc = Time.get_ticks_usec()
	r.global_position = eye + dir * 0.7
	var fx = _fx()
	if fx != null:
		r.effects = fx
	# ROMPE COMO EL DEL JUGADOR. Iba con radio 3,2 m y potencia 200, y la explosion PIERDE fuerza hacia fuera:
	# con 200 el hormigon del mapa (dureza 170) solo cae en el 15 % del radio y el metal (220) no cae nunca.
	# Medido en la misma pared de dust2: el cohete del bot quitaba 521 voxels y el del jugador 9.081, asi que
	# parecia que los misiles de los bots no rompian nada (lo conto el usuario). El daño a la gente se queda
	# mas bajo que el del jugador (90 contra 130): eso es equilibrio, no un fallo.
	r.setup(world, dir, self, COHETE_RADIO, COHETE_POTENCIA, 90.0)
	Prof.add("bot.c.setup", Time.get_ticks_usec() - _tc)
	_tc = Time.get_ticks_usec()
	# que los demas lo vean volar (el crater y el daño los pone este, que es el que lo lanza)
	Net.net_cohete(r.global_position, dir, COHETE_RADIO, COHETE_POTENCIA, 90.0)
	Prof.add("bot.c.red", Time.get_ticks_usec() - _tc)
	_tc = Time.get_ticks_usec()
	Audio.gunshot("rocket", eye, false, "bazooka_rpg")
	Prof.add("bot.c.sonido", Time.get_ticks_usec() - _tc)
	if avatar:
		avatar.kick()


## SE QUEDO SIN BALAS. Busca un sitio donde el objetivo NO lo vea y sale corriendo hacia alli.
## Se prueban ocho direcciones alrededor a seis metros y se elige la primera que rompa la linea de
## vision y tenga suelo; si ninguna vale, se recarga agachado donde este.
func _empezar_recarga() -> void:
	recarga_t = RECARGA_S
	municion = 0
	cubierto_pos = Vector3.ZERO
	# la recarga animada del avatar dura lo mismo que la de verdad (avatar_animator._aplicar_recarga)
	if avatar and "reloading" in avatar:
		avatar.reload_dur = RECARGA_S
		avatar.reloading = true
	Audio.bf3d("soldado/cargador_fusil", global_position + Vector3(0, 1.2, 0), -6.0, 25.0, Audio.PRI_LOW)
	if world == null or not is_instance_valid(target):
		return
	var ojo_obj: Vector3 = target.global_position + Vector3(0, 1.5, 0)
	for k in 8:
		var a: float = float(k) * TAU / 8.0 + randf() * 0.4
		var cand: Vector3 = global_position + Vector3(cos(a), 0.0, sin(a)) * 6.0
		var suelo: Vector3 = world.find_ground(cand)
		if suelo.y < 0.0:
			continue
		if not world.has_line_of_sight(suelo + Vector3(0, 1.5, 0), ojo_obj):
			cubierto_pos = suelo
			return


## Barrido de la mirada en el puesto: oscila alrededor de la orientación base y, de vez en cuando, gira a otro lado.
func _look_around(dt: float, amp: float) -> void:
	look_t -= dt
	if look_t <= 0.0:
		look_t = randf_range(1.5, 4.0)
		yaw_target = yaw_base + randf_range(-amp, amp)
	rotation.y = lerp_angle(rotation.y, yaw_target, 2.0 * dt)

func _stop(dt: float) -> void:
	if _CEREBRO_C:
		c_stop(dt)
		return
	velocity.x = move_toward(velocity.x, 0.0, 10.0 * dt)
	velocity.z = move_toward(velocity.z, 0.0, 10.0 * dt)

## Camina hacia `target` por el A* de voxels. Devuelve true al llegar.
## DIAGNOSTICO DE TIRONES (--diagfps): igual que en criatura.gd. Lo lee main.gd cada segundo.
static var diag_fps := false
# (nativa, BotBase) var dg_paths := 0
# (nativa, BotBase) var dg_vacios := 0
# (nativa, BotBase) var dg_us := 0
## ENFRIAMIENTO DEL A*, el mismo que en criatura.gd. Con un destino sin camino la ruta sale VACIA, y
## `path.is_empty()` pedia otra en el tick siguiente... y el siguiente: un A* por tick, y cuando sale
## vacia, ademas, un anillo de puntos intermedios con un A* cada uno. Medido en las criaturas: 44 rutas
## por segundo y 8 fps. Entre intento e intento pasa al menos esto, y si sigue sin haber camino la
## espera se dobla hasta el tope.
const PATH_ESPERA_MIN := 0.35
const PATH_ESPERA_MAX := 3.0
# (nativa, BotBase) var _path_cool_t := 0.0
# (nativa, BotBase) var _path_espera := PATH_ESPERA_MIN


const TRAMO_LEJOS := 24.0     ## m: mas lejos que esto, el A* se pide a tramos (ver _go_to)

## SEGUIR EL CAMINO QUE YA HAY. Se replanificaba cada 0,9-1,5 s aunque el destino no cambiara, y con el
## destino lejos cada vez se pedia camino a un punto intermedio distinto: medido en una partida de dust2,
## tres policias fueron y volvieron un minuto entero entre su spawn y la mitad del mapa sin llegar nunca al
## sitio A (--diagbots). Ahora solo se pide otro camino si no queda, si el destino se ha movido o cada
## CAMINO_CADUCA_S por si el mapa ha cambiado (lo que se rompe ya lo avisa `invalidate_path`).
const CAMINO_CADUCA_S := 8.0
const DESTINO_MOVIDO_M := 2.5
const CAMINO_ENTERO_M := 45.0   ## hasta aqui se pide el camino entero antes que a tramos
# (nativa, BotBase) var _path_para := Vector3.INF
# (nativa, BotBase) var _path_edad := 0.0

func _go_to(target: Vector3, speed: float, dt: float, arrive: float) -> bool:
	if _CEREBRO_C:
		return c_go_to(target, speed, dt, arrive)
	if not _prof:
		return _go_to_inner(target, speed, dt, arrive)
	var _tg := Time.get_ticks_usec()
	var r := _go_to_inner(target, speed, dt, arrive)
	Prof.add("bot.go_to", Time.get_ticks_usec() - _tg)
	return r

func _go_to_inner(target: Vector3, speed: float, dt: float, arrive: float) -> bool:
	if Vector2(target.x - global_position.x, target.z - global_position.z).length() < arrive:
		_stop(dt)
		return true
	_path_cool_t -= dt
	_path_edad += dt
	var planear: bool = path.is_empty() or _path_para == Vector3.INF or _path_para.distance_to(target) > DESTINO_MOVIDO_M \
		or _path_edad > CAMINO_CADUCA_S
	if planear and _path_cool_t <= 0.0 and AstarTurno.puedo():
		replan_t = randf_range(0.9, 1.5)
		_path_para = target
		_path_edad = 0.0
		# se da por hecho que no habra camino (espera doble para la proxima); abajo, si lo hay, se deshace
		_path_cool_t = _path_espera
		_path_espera = minf(_path_espera * 2.0, PATH_ESPERA_MAX)
		var _tp := Time.get_ticks_usec()
		# LEJOS, A TRAMOS. Un camino entero hasta la caja fuerte de la ciudad (100 m o mas) costaba 14 ms de
		# media y hasta 36 (--astarpartida), y una de cada cinco se rendia sin llegar. Si el destino esta
		# lejos se pide camino hasta un punto a TRAMO_LEJOS en su direccion, y al replanificar se sigue:
		# cada busqueda es corta y barata. Si ese tramo no tiene camino, se pide el entero como antes.
		# PRIMERO EL CAMINO ENTERO, y a tramos solo si no sale. Antes era al reves: con el destino a mas de
		# 30 m se pedia camino a un punto en linea recta, y `find_ground` busca desde el cielo, asi que el
		# punto caia en un TEJADO (se aceptaban hasta 8 m de diferencia de altura): el bot se iba a buscar la
		# escalera de esa azotea en direccion contraria. Y el punto de tramo va ahora a SU altura.
		var dplan: Vector3 = (target - global_position) * Vector3(1, 0, 1)
		path = PackedVector3Array()
		if dplan.length() <= CAMINO_ENTERO_M:
			path = AstarTurno.buscar(world, global_position, target, "bot")
		if path.is_empty() and dplan.length() > TRAMO_LEJOS + 6.0:
			var mid0: Vector3 = _suelo_a_mi_altura(global_position + dplan.normalized() * TRAMO_LEJOS)
			if mid0.y >= 0.0:
				path = AstarTurno.buscar(world, global_position, mid0, "bot_tramo")
		if diag_fps:
			dg_paths += 1
			dg_us += Time.get_ticks_usec() - _tp
			if path.is_empty():
				dg_vacios += 1
		if _prof:
			_prof_us["path"] += Time.get_ticks_usec() - _tp
			_prof_paths += 1
		path_i = 0
		if path.is_empty():
			# El A* tiene un tope de nodos (~55 m): un destino al otro lado del mapa no tiene camino "de una vez".
			# Se planifica hasta un punto intermedio a 18 m en su dirección y, si tampoco, se camina recto un rato
			# (el movimiento por voxels esquiva escalones y paredes bajas). Antes se daba por "inalcanzable" y el
			# bot volvía a vigilar sin moverse: las rondas por el mapa no llegaban a ninguna parte.
			var d := target - global_position
			d.y = 0.0
			if d.length() > 12.0:
				# PUNTO INTERMEDIO: antes se probaba UNO solo, recto a 18 m. En un mapa de pasillos
				# ese punto cae dentro de un edificio la mitad de las veces, no habia camino, y el
				# bot acababa andando recto contra la pared. El sitio B esta a 15 m del spawn de la
				# policia y se llegaba; el A esta a 45 m y no llegaba NADIE.
				#
				# Ahora se prueban tres distancias y tres desvios a cada lado -nueve tanteos- y se
				# coge el que de un camino de verdad. Un desvio lateral es justo lo que hace falta
				# para doblar una esquina, que es como se va del spawn al sitio A.
				var dir0: Vector3 = d.normalized()
				var a0: float = atan2(dir0.z, dir0.x)
				for dist in [22.0, 15.0, 9.0]:
					for desvio in [0.0, 0.6, -0.6, 1.2, -1.2]:
						if dist > d.length() + 4.0:
							continue
						var a: float = a0 + desvio
						var mid: Vector3 = _suelo_a_mi_altura(global_position + Vector3(cos(a), 0.0, sin(a)) * dist)
						if mid.y < 0.0:
							continue
						# Y QUE ACERQUE. Un desvio de 70 grados puede dejarte mas lejos que antes: sin
						# esta comprobacion habia bots que salian del spawn en direccion contraria a
						# su sitio y no volvian. Solo vale un punto intermedio que gane terreno.
						if mid.distance_to(target) > d.length() - 2.0:
							continue
						# los tanteos tambien piden turno: nueve busquedas seguidas eran un tiron seguro
						if not AstarTurno.puedo():
							break
						var _tp2 := Time.get_ticks_usec() if diag_fps else 0
						path = AstarTurno.buscar(world, global_position, mid, "bot_tanteo")
						if diag_fps:
							dg_paths += 1
							dg_us += Time.get_ticks_usec() - _tp2
							if path.is_empty():
								dg_vacios += 1
						if not path.is_empty():
							path_i = 0
							break
					if not path.is_empty():
						break
			if path.is_empty():
				direct_t += 1
				# NO DARLO POR LLEGADO ESTANDO LEJOS. Aqui se devolvia `true` -"he llegado"- tras
				# seis intentos, y quien llamaba pasaba a vigilar: el bot se plantaba en mitad de la
				# nada, mirando una pared, para el resto de la ronda. Solo se abandona si el destino
				# ya esta cerca; si esta lejos se sigue insistiendo, bordeando.
				if direct_t > 6:
					direct_t = 0
					if d.length() < 8.0:
						return true
				_move_toward(target, speed, dt, true)
				return false
		direct_t = 0
		_path_espera = PATH_ESPERA_MIN      # hay camino: la proxima vez, espera corta
	if path.is_empty():
		_move_toward(target, speed, dt, true)
		return false
	if path_i < path.size():
		var wp: Vector3 = path[path_i]
		if Vector2(wp.x - global_position.x, wp.z - global_position.z).length() < 0.55:
			path_i += 1
		else:
			_move_toward(wp, speed, dt, true)
			# SALTAR SOLO CUANDO HACE FALTA. Estaba en 25 cm para que se les viera saltar bordillos,
			# pero en un mapa de voxels el camino sube y baja de dos en dos centimetros todo el rato:
			# con ese umbral iban dando botes continuamente. A 45 cm se salta un escalon de verdad.
			#
			# Y ademas con enfriamiento: sin el, mientras el siguiente punto siga estando arriba se
			# vuelve a saltar EN CUANTO se toca el suelo, que es el bote en bucle que se veia.
			_salto_t -= dt
			# ...o si algo le corta el paso y el punto siguiente esta mas alto (un bordillo que la caja no deja pasar)
			var cortado: bool = wp.y > global_position.y + 0.2 and _blocked_at(global_position + (Vector3(wp.x, global_position.y, wp.z) - global_position).normalized() * 0.3)
			if (wp.y > global_position.y + 0.3 or cortado) and on_floor and _salto_t <= 0.0:
				_salto_t = 1.2
				velocity.y = 5.2
		return false
	# Camino agotado sin llegar: el A* devuelve rutas PARCIALES cuando se acaba su tope de nodos (~55 m). Antes
	# el bot se daba por llegado y se quedaba vigilando en un punto muerto. Ahora replanifica desde aquí y
	# sigue; sólo abandona si tras 10 tramos no se ha acercado nada.
	var remaining := Vector2(target.x - global_position.x, target.z - global_position.z).length()
	if remaining > arrive * 3.0:
		if remaining < best_remaining - 1.0:
			best_remaining = remaining
			partial_n = 0
		else:
			partial_n += 1
		if partial_n <= 10:
			replan_t = 0.0
			path = PackedVector3Array()
			return false
		partial_n = 0
		best_remaining = 1e9
	_stop(dt)
	return true

## Movimiento sobre la rejilla de voxels, sin pasar por el motor de físicas: 10 CharacterBody3D con
## move_and_slide contra mallas cóncavas costaban ~3,5 ms por tick en Jolt; esto son ~30 lecturas de voxel
## y un raycast voxel por bot. El cuerpo cinemático sigue existiendo para recibir los disparos del jugador.
# (nativa, BotBase) var on_floor := false
var _freeze: bool = "--botsfreeze" in OS.get_cmdline_user_args()   # diagnóstico: no mover el cuerpo
const BOT_RADIUS := 0.3

func _solid(p: Vector3) -> bool:
	return world.get_material_at(p) > 0

## EL PASO DE MOVIMIENTO EN C++ (2026-10-02, pedido: "pasa la IA de los bots a C++"): BotMotor (godot/extension/src/
## bot_motor.cpp) hace la caja del cuerpo, el paso X/Z con la caida y el suelo con los escombros, y el abanico de rodear,
## con las mismas cuentas que el GDScript de aqui (se comprueba con --botmotorprueba). Sin la clase (una extension vieja)
## o con --sinbotmotorc, el GDScript de siempre.
static var _motor = (ClassDB.instantiate("BotMotor") if ClassDB.class_exists("BotMotor") and not ("--sinbotmotorc" in OS.get_cmdline_user_args()) else null)

func _blocked_at(p: Vector3) -> bool:
	if _motor != null:
		return _motor.bloqueado(world, p, crouching)
	return _blocked_at_gd(p)

func _blocked_at_gd(p: Vector3) -> bool:
	# caja del cuerpo de 0,5 m (deja pasar escalones) a 1,6 m sobre los pies: una sola consulta al núcleo.
	# EL BAJO VA CON EL PIE: el suelo engancha escalones de hasta 0,6 m (`_voxel_move`), pero la caja empezaba a
	# 0,35 y el salto a 0,45: un escalon de 0,35-0,45 m no se subia andando NI saltando. Medido en dust2, un bot
	# clavado para siempre frente a un escalon de 0,40 m camino del sitio B (--botsatasco).
	return world.box_solid(p + Vector3(-BOT_RADIUS, 0.5, -BOT_RADIUS), p + Vector3(BOT_RADIUS, 1.6 if not crouching else 1.1, BOT_RADIUS))

# --- LO QUE HACE UN CUERPO AL MOVERSE -----------------------------------------------------------
# Los bots se movian en SILENCIO ABSOLUTO y sin dejar rastro: ni pasos, ni golpe al aterrizar, ni
# huellas en la nieve, ni salpicaduras en los charcos, ni vaho con frio. Todo eso lo tenia el
# jugador y a ellos no se les puso nunca.
#
# Y no es solo adorno: no oir venir a un enemigo es una desventaja de juego, no un detalle que falta.
# Un bot que se te echa encima sin hacer ruido no se comporta como un jugador, se comporta como un
# fantasma.
#
# Todo cuelga de detectar la pisada, que es una sola cuenta: la distancia recorrida por el suelo.
# (nativa, BotBase) var _paso_dist := 0.0
# (nativa, BotBase) var _aliento_t := 0.0


## El nodo principal, subiendo por el arbol. Los bots no lo conocen; se busca por lo que sabe hacer.
var _principal_vista: Node = null   ## el main de la partida, ya encontrado (el bot no cambia de padre)

func _principal():
	if _principal_vista != null and is_instance_valid(_principal_vista) and _principal_vista.is_ancestor_of(self):
		return _principal_vista
	var n: Node = self
	while n != null:
		if n.has_method("pisar"):
			_principal_vista = n
			return n
		n = n.get_parent()
	return null


func _pasos(dt: float, antes_suelo: bool, caida: float) -> void:
	if not on_floor:
		_paso_dist = 0.0
		return
	# el material del suelo solo cuando de verdad suena algo (antes se leia en cada tick estando de pie)
	var mat: int = -1
	# EL GOLPE AL CAER, primero: aterrizar suena distinto que andar, y es lo que delata a alguien que
	# acaba de bajar de un piso.
	if not antes_suelo and caida > 2.0:
		mat = world.get_material_at(global_position - Vector3(0, 0.12, 0)) if world else 0
		Audio.land(mat, caida > 7.0)
	var hs: float = Vector2(velocity.x, velocity.z).length()
	if hs <= 0.5:
		_paso_dist = 0.0
		return
	# UN PIE POR MEDIO CICLO DE ANIMACION, no cada tantos metros. Contarlo por metros -0,75 / 1,35 /
	# 1,9 segun el modo- no tiene nada que ver con lo que hacen las piernas en pantalla: en cuanto se
	# calibra la marcha, se oye la pisada con el pie en el aire. Mismo criterio que el jugador.
	_paso_dist += dt
	var corriendo: bool = hs > 2.8
	var zancada := 0.60
	if avatar != null and is_instance_valid(avatar):
		var d: float = avatar.clip_dur(avatar.current_clip)
		if d > 0.0:
			zancada = clampf(d / maxf(avatar.anim_speed, 0.05), 0.20, 2.0) * 0.5
	if _paso_dist < zancada:
		return
	_paso_dist = 0.0
	# EL SONIDO, SOLO SI SE PIDE. Todo lo demas de la pisada -huella en la nieve, salpicadura- se
	# queda: eso no molesta por muchos que sean, porque no compite por el oido.
	if Settings.pasos_bots:
		if mat < 0:
			mat = world.get_material_at(global_position - Vector3(0, 0.12, 0)) if world else 0
		Audio.footstep_otro(mat, corriendo, global_position)
	var mn = _principal()
	if mn != null:
		mn.pisar(global_position, corriendo)      # huella en la nieve
		# y salpicadura, con las mismas condiciones que el jugador: mojado y a cielo abierto
		var fx = _fx()
		if fx != null and fx.has_method("chapoteo") and ("_mojado" in mn) and ("_lluvia_suelo" in mn):
			var seco: bool = ("_bajo_techo" in mn) and bool(mn._bajo_techo)
			if bool(mn._lluvia_suelo) and not seco and float(mn._mojado) >= 0.10:
				fx.chapoteo(global_position + Vector3(0, 0.04, 0),
					(1.0 if corriendo else 0.62) * float(mn._mojado))


## El aliento con frio, igual que el del jugador: cada pocos segundos y mas seguido si viene
## corriendo. Sale de la boca, a la altura de la cabeza.
func _aliento(dt: float) -> void:
	var mn = _principal()
	if mn == null or not ("_nieve" in mn):
		return
	var frio: float = float(mn._nieve)
	if frio <= 0.06 or (("_aliento_on" in mn) and not bool(mn._aliento_on)):
		return
	var fx = _fx()
	if fx == null or not fx.has_method("vaho"):
		return
	_aliento_t -= dt
	if _aliento_t > 0.0:
		return
	var hs2: float = Vector2(velocity.x, velocity.z).length()
	_aliento_t = (1.9 if hs2 > 2.8 else 3.6) * randf_range(0.85, 1.15)
	var dir: Vector3 = -global_transform.basis.z
	fx.vaho(global_position + Vector3(0, 1.52, 0) + dir * 0.22, dir, frio)


## QUE NO SE APILEN. Dos bots pueden acabar en el mismo sitio -mismo puesto de guardia, misma
## esquina, o persiguiendo al mismo jugador- y, a diferencia de las personas, no se empujan: se
## mueven leyendo voxels, sin pasar por la fisica, asi que uno se queda DENTRO de otro y de fuera se
## ve un solo bot con una espalda de mas. Se aparta solo el del numero mas alto, igual que entre
## jugadores: si se apartan los dos, se persiguen y tiemblan.
##
## Barato a proposito: es una distancia en el plano contra los hermanos, sin consultar el mundo. Con
## diez bots son 45 restas por tick y ninguna lectura de voxel.
const SEPARAR_RADIO := 0.75
const SEPARAR_VELOCIDAD := 1.4

func _despegarse_de_los_otros(dt: float) -> void:
	if remoto or health <= 0.0:
		return
	var padre := get_parent()
	if padre == null:
		return
	var yo := global_position
	for o in padre.get_children():
		if o == self:
			continue
		var n3 := o as Node3D          # (los hijos de get_children() siempre son validos)
		if n3 == null:
			continue
		# primero la distancia, que es barata: casi siempre estan lejos y no hace falta mirar mas (las
		# comprobaciones `in` de propiedades son lo caro, y eran 9 x 9 por tick de fisica). La posicion global del
		# otro se lee UNA vez (cada lectura recalcula su transformada si se ha movido este tick).
		var op := n3.global_position
		var d := Vector2(yo.x - op.x, yo.z - op.z)
		var d2 := d.length_squared()
		if d2 > SEPARAR_RADIO * SEPARAR_RADIO:
			continue
		var dist := sqrt(d2)
		if "health" in o and float(o.health) <= 0.0:
			continue
		if "red_id" in o and int(red_id) < int(o.red_id):
			continue                     # se aparta el del numero mas alto; yo me quedo
		# si se han quedado EXACTAMENTE encima no hay direccion que valga: se empuja hacia un lado
		var dir := Vector3(d.x, 0.0, d.y).normalized() if dist > 0.01 else Vector3(1, 0, 0)
		var q := global_position + dir * SEPARAR_VELOCIDAD * dt
		if not _blocked_at(q):           # apartarse no puede meterte en una pared
			global_position = q
			yo = q


## El suelo en (x, z) a la altura de este bot (hasta 3 m por encima o por debajo), no el mas alto del mapa.
## (-1 en y si no hay: ahi no se puede ir andando).
func _suelo_a_mi_altura(q: Vector3) -> Vector3:
	var r: Dictionary = world.raycast(Vector3(q.x, global_position.y + 2.5, q.z), Vector3.DOWN, 5.5)
	if not bool(r.get("hit", false)):
		return Vector3(q.x, -1.0, q.z)
	var s: Vector3 = r["position"]
	if absf(s.y - global_position.y) > 3.0 or world.get_material_at(s + Vector3(0, 1.0, 0)) > 0:
		return Vector3(q.x, -1.0, q.z)      # debajo de un techo bajo o dentro de algo
	return s


## INCRUSTADO. Si la caja del cuerpo ya toca algo solido donde esta, `_blocked_at` da bloqueado en CUALQUIER
## direccion y el bot no se vuelve a mover en toda la ronda. Medido en dust2: dos policias quietos en el mismo
## punto junto al sitio A con un camino de 66 puntos por delante. Se busca el hueco libre mas cercano (hasta
## 1 m, con suelo debajo) y se le pone ahi.
# (nativa, BotBase) var _incrustado_t := 0.0

func _hueco_cerca(p: Vector3):
	for arriba in [0.0, 0.15, 0.3, 0.6]:
		for r in [0.12, 0.25, 0.4, 0.6, 0.8, 1.0]:
			for k in 8:
				var a: float = TAU * float(k) / 8.0
				var q: Vector3 = p + Vector3(cos(a) * r, arriba, sin(a) * r)
				if _blocked_at(q):
					continue
				if not bool(world.raycast(q + Vector3(0, 0.5, 0), Vector3.DOWN, 1.4).get("hit", false)):
					continue      # sin suelo: no se le saca a un borde
				return q
	return null


## El paso en GDScript (lo mismo que BotMotor.mover): [pos, vel, en_suelo]
func _mover_gd(p: Vector3, vel: Vector3, dt: float, k_agua: float) -> Array:
	var np := p + Vector3(vel.x * dt * k_agua, 0, 0)
	if _blocked_at_gd(np):
		vel.x = 0.0
	else:
		p = np
	np = p + Vector3(0, 0, vel.z * dt * k_agua)
	if _blocked_at_gd(np):
		vel.z = 0.0
	else:
		p = np
	p.y += vel.y * dt
	# Suelo bajo los pies (rayo desde la cadera hacia abajo), MIRANDO TAMBIEN LOS TROZOS QUE CAEN: el
	# bot anda sobre la rejilla de voxels, y la estructura que pisaba, al desprenderse, deja de ser
	# voxel. Con `raycast` a secas debajo ya no habia nada y se colaba al vacio al romperle el suelo.
	var ojo_pies: Vector3 = p + Vector3(0, 0.9, 0)
	var hit: Dictionary = world.raycast_con_piezas(ojo_pies, Vector3.DOWN, 3.5) if world.has_method("raycast_con_piezas") else world.raycast(ojo_pies, Vector3.DOWN, 3.5)
	var suelo := false
	if hit.get("hit", false):
		var gy: float = hit["position"].y
		if vel.y <= 0.0 and p.y <= gy + 0.03 and p.y >= gy - 0.6:
			p.y = gy   # apoyado (o subiendo un escalón de hasta 0,6 m)
			vel.y = 0.0
			suelo = true
	return [p, vel, suelo]


const AguaScript := preload("res://scripts/agua.gd")
const FLOTA_AGUA := 1.2        ## m de los pies bajo la superficie cuando nada (la cabeza queda fuera)
# (nativa, BotBase) var _en_agua := false

func _voxel_move(dt: float) -> void:
	if _CEREBRO_C:
		c_voxel_move(dt)
		return
	var _tvm := Time.get_ticks_usec() if _prof else 0
	_despegarse_de_los_otros(dt)
	if _prof:
		Prof.add("bot.mv.despegarse", Time.get_ticks_usec() - _tvm)
		_tvm = Time.get_ticks_usec()
	var _antes_suelo: bool = on_floor
	var _vy_antes: float = velocity.y
	var p := global_position
	if _blocked_at(p):
		_incrustado_t += dt
		if _incrustado_t >= 0.25:
			_incrustado_t = 0.0
			var libre = _hueco_cerca(p)
			if libre != null:
				p = libre
				_invalidate_path_now()
	else:
		_incrustado_t = 0.0
	# nadando avanzan a poco mas de la mitad, como el jugador
	var k_agua: float = 0.55 if _en_agua else 1.0
	var mv: Array = _motor.mover(world, p, velocity, dt, k_agua, crouching) if _motor != null else _mover_gd(p, velocity, dt, k_agua)
	p = mv[0]
	velocity = mv[1]
	on_floor = bool(mv[2])
	if _prof:
		Prof.add("bot.mv.cajas", Time.get_ticks_usec() - _tvm)
		_tvm = Time.get_ticks_usec()
	# EN EL AGUA FLOTAN (agua.gd). Para el motor el mar es aire y debajo hay arena, asi que un bot que se
	# metia en el mar se iba andando por el fondo con la cabeza a tres metros bajo la superficie. Ahora
	# se queda con la cabeza fuera, igual que el jugador, y cuenta como "apoyado" para que su animacion
	# y su IA no crean que va cayendo. Y fuera del rectangulo jugable no pasa, como nadie.
	_en_agua = false
	var ag = AguaScript.actual
	if ag != null:
		var sup: float = ag.nivel_en(p)
		if sup > -INF and sup - p.y > FLOTA_AGUA:
			p.y = sup - FLOTA_AGUA
			velocity.y = maxf(velocity.y, 0.0)
			on_floor = true
			_en_agua = true
		p = ag.limitar(p)
	if _prof:
		Prof.add("bot.mv.agua", Time.get_ticks_usec() - _tvm)
		_tvm = Time.get_ticks_usec()
	_pasos(dt, _antes_suelo, -_vy_antes)
	_aliento(dt)
	if _prof:
		Prof.add("bot.mv.pasos", Time.get_ticks_usec() - _tvm)
		_tvm = Time.get_ticks_usec()
	if not _freeze:
		global_position = p
	if _prof:
		Prof.add("bot.mv.colocar", Time.get_ticks_usec() - _tvm)

## Hacia donde EMPUJAR de verdad para ir a `target`. Si hay pared delante, se prueba a girar en
## abanico hasta 100 grados a un lado y a otro y se coge la primera direccion despejada: es bordear
## la pared, que es lo que hace cualquiera. Sin esto, un bot sin camino calculado empujaba en linea
## recta contra el muro indefinidamente -de ahi los que se quedaban clavados sin saber salir-.
##
## El lado por el que empieza a probar se mantiene unos segundos (`_rodeo_lado`): alternarlo cada
## frame lo dejaba temblando en el sitio, probando izquierda y derecha sin avanzar por ninguna.
# (nativa, BotBase) var _rodeo_lado := 1.0
# (nativa, BotBase) var _rodeo_t := 0.0

func _rodear(dir_plana: Vector3, dt: float) -> Vector3:
	var paso: float = BOT_RADIUS + 0.55
	if not _blocked_at(global_position + dir_plana * paso):
		return dir_plana
	_rodeo_t -= dt
	if _rodeo_t <= 0.0:
		_rodeo_t = randf_range(1.5, 3.0)
		_rodeo_lado = 1.0 if randf() < 0.5 else -1.0
	if _motor != null:
		return _motor.abanico(world, global_position, dir_plana, paso, _rodeo_lado, crouching)
	return _abanico_gd(global_position, dir_plana, paso, _rodeo_lado)


func _abanico_gd(desde: Vector3, dir_plana: Vector3, paso: float, lado_base: float) -> Vector3:
	var base_a: float = atan2(dir_plana.z, dir_plana.x)
	for k in 5:
		var giro: float = deg_to_rad(20.0 * float(k + 1))
		for lado in [lado_base, -lado_base]:
			var a: float = base_a + giro * lado
			var cand := Vector3(cos(a), 0.0, sin(a))
			if not _blocked_at_gd(desde + cand * paso):
				return cand
	return dir_plana        # rodeado por completo: que siga empujando, ya se despegara al replanificar

func _move_toward(target: Vector3, speed: float, dt: float, face: bool) -> void:
	if _CEREBRO_C:
		c_move_toward(target, speed, dt, face)
		return
	var d := target - global_position
	d.y = 0.0
	if d.length() < 0.01:
		return
	d = _rodear(d.normalized(), dt) * speed
	velocity.x = lerpf(velocity.x, d.x, 8.0 * dt)
	velocity.z = lerpf(velocity.z, d.z, 8.0 * dt)
	if face:
		_face(target)

func _face(target: Vector3) -> void:
	if _CEREBRO_C:
		c_face(target)
		return
	var d := target - global_position
	d.y = 0.0
	if d.length() > 0.05:
		look_at(global_position + d, Vector3.UP)

func _shoot(eye: Vector3, target_eye: Vector3) -> void:
	if sin_arma:
		return                       # con las manos vacias no se dispara (ver `desarmar`)
	MinimapCls.marcar_disparo(global_position, team)   # el fogonazo te delata un segundo en el mapa
	var dir := (target_eye - eye).normalized()
	if arma == "rocket":
		# con el cohete se apunta un poco por debajo del pecho: un cohete no hace falta que acierte,
		# le basta con caer cerca
		dir = (dir + Vector3(randf_range(-0.03, 0.03), -0.01, randf_range(-0.03, 0.03))).normalized()
		var _tco := Time.get_ticks_usec()
		_lanzar_cohete(eye, dir)
		Prof.add("bot.d.cohete", Time.get_ticks_usec() - _tco)
		return
	var _tdi := Time.get_ticks_usec()
	# puntería: peor a distancia y si el bot se mueve
	var moving := Vector2(velocity.x, velocity.z).length() > 0.5
	# PUNTERIA. Empezo en 0,04 rad de base -unos 2,3 grados, o fallar por dos metros a veinte- y se
	# bajo a la mitad. Ahora otro recorte: 0,011 de base, unos 0,6 grados, que es lo que acierta
	# alguien bueno. Y el castigo por moverse baja tambien, porque un jugador bueno dispara en
	# movimiento y sigue dando.
	#
	# Se deja error a proposito: un bot que no falla NUNCA no se siente duro, se siente tramposo.
	# PUNTERIA DE PERSONA (2026-09-23, pedido: "que fallen algunos, que se les pueda matar"). Con rafagas
	# automaticas la de antes (0,011) era un laser. Ahora:
	#   - base 0,030 (~1,7 grados): a 20 m falla por medio metro
	#   - moverse +0,035; de pie +0,008
	#   - el RETROCESO abre la rafaga: +0,010 por bala seguida
	#   - SORPRESA: los primeros 0,6 s tras verte apunta mucho peor (reaccion humana)
	var err := 0.030 + (0.035 if moving else 0.0) + (0.008 if not crouching else 0.0)
	if arma == "rifle":
		err = maxf(0.008, err + float(TIRO_BOT.get(arma_tipo, TIRO_BOT["rifle"])[5]))
	err += 0.010 * float(mini(_rafaga_i, 6))
	err *= FALLO_BOT
	if _visto_t < 0.6:
		err += 0.05 * (1.0 - _visto_t / 0.6)
	if eye.distance_to(target_eye) < 8.0:
		err *= 0.8
	# contra OTRO BOT (no contra personas): el equilibrio de _fallo_contra_bot()
	if is_instance_valid(target) and not ("peer_id" in target) and target != Net.local_player:
		err *= _fallo_contra_bot()
	dir = (dir + Vector3(randf_range(-err, err), randf_range(-err * 0.8, err * 0.8), randf_range(-err, err))).normalized()
	var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * 60.0)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	# las balas enemigas también rompen cristales y pladur (potencia de pistola), pero SE PARAN en lo
	# primero que tocan: si no, el bot dispara a un cascote y el agujero sale en la pared de detras
	# (ver el mismo arreglo en player.gd::fire)
	var tope: float = 60.0
	if hit:
		tope = minf(tope, eye.distance_to(hit.position) + 0.10)
	# REPLICADO. Con `world.shoot` a secas la bala del bot abria el agujero solo en la maquina que mueve
	# al bot (el anfitrion, casi siempre): medido en dust2 con dos maquinas, 3.946 voxels de diferencia
	# y 25 posturas de bloques que el invitado no tenia, en dos minutos y medio.
	if _prof:
		Prof.add("bot.d.rayo", Time.get_ticks_usec() - _tdi)
		_tdi = Time.get_ticks_usec()
	var vox: Dictionary = Net.net_shoot(world, eye, dir, tope, 40)
	var vdist: float = vox.distance if vox.hit else INF
	if _prof:
		Prof.add("bot.d.voxels", Time.get_ticks_usec() - _tdi)
		_tdi = Time.get_ticks_usec()
	Audio.gunshot("rifle", eye, false, _arma_sonido)
	if _prof:
		Prof.add("bot.d.sonido", Time.get_ticks_usec() - _tdi)
		_tdi = Time.get_ticks_usec()
	# QUIEN DISPARA, SE DELATA. El aviso va al bando CONTRARIO: son ellos los que oyen los tiros y
	# tienen que decidir si van a ver. Antes un tiroteo al otro lado del mapa no le constaba a nadie.
	Escuadra.avisar(global_position, Net.TEAM_CT if team == Net.TEAM_T else Net.TEAM_T, 1.0)
	if avatar:
		avatar.kick()
	# LO QUE SE VE DEL DISPARO AJENO: la traza saliendo del canon y el humillo del orificio. Antes
	# solo habia fogonazo, asi que de lejos un tiroteo no se leia: se oia pero no se veia nada.
	var largo: float = minf(vdist if vdist < INF else 60.0, 60.0)
	if hit and eye.distance_to(hit.position) < vdist:
		largo = eye.distance_to(hit.position)
	_disparo_visible(dir, largo)
	if _prof:
		Prof.add("bot.d.visible", Time.get_ticks_usec() - _tdi)
		_tdi = Time.get_ticks_usec()
	Net.net_bot_tiro(int(red_id), dir, largo)
	# ¿LE HE DADO?
	#
	# Lo normal es que el rayo choque justo con el objetivo. Pero un JUGADOR DE OTRA MAQUINA que sea
	# del mismo bando que el dueño de esta partida se queda SIN COLISION (`collision_layer = 0`, asi
	# se evita el fuego amigo entre personas), y entonces el rayo lo atraviesa como si no estuviera:
	# el bot le apuntaba, disparaba, y no le pasaba nada nunca.
	#
	# Asi que si el objetivo no puede ser tocado por el rayo, se mira si hay VIA LIBRE hasta el: que
	# lo primero que se cruce este mas lejos que el. Es la misma pregunta -"¿le veo?"- hecha al reves.
	var d_obj := eye.distance_to(target_eye)
	var le_doy := false
	if is_instance_valid(target):
		if hit and hit.collider == target:
			le_doy = eye.distance_to(hit.position) < vdist
		elif "peer_id" in target:          # jugador de otra maquina, puede no tener colision
			var d_estorbo: float = eye.distance_to(hit.position) if hit else INF
			le_doy = d_obj < vdist and d_obj < d_estorbo
	# UN VEHICULO EN MEDIO. Si el rayo del bot pega en un coche, el coche se lleva el balazo (y las
	# chispas): si no, dispararle a alguien que va dentro no hacia absolutamente nada.
	if hit and hit.collider and hit.collider.has_method("danar_bala") \
			and eye.distance_to(hit.position) < vdist:
		hit.collider.danar_bala(8.0, hit.position, dir)
		var fx2 = _fx()
		if fx2 and fx2.has_method("sparks"):
			fx2.sparks(hit.position, hit.get("normal", -dir))
	if le_doy and target.has_method("take_damage"):
		if "ultimo_atacante" in target:
			target.ultimo_atacante = self
		# con la direccion del tiro: el escudo balistico solo para lo que le llega por delante
		var dano: float = 8.0
		if arma == "rifle":
			dano = _dano_bala_bot()
			if arma_tipo == "shotgun":   # la escopeta pega de cerca; de lejos se abre y apenas hace nada
				dano *= clampf(1.4 - eye.distance_to(target_eye) / 14.0, 0.25, 1.2)
		if "golpe_tipo" in target:
			target.golpe_tipo = "bala"
		target.take_damage(dano, dir.normalized() * 1.5)
		preload("res://scripts/logros.gd").sumar_dano(String(nombre_marcador) if "nombre_marcador" in self else "", dano)
	else:
		_silbido(eye, dir, largo)
	if _prof:
		Prof.add("bot.d.dano", Time.get_ticks_usec() - _tdi)


## EL BOCADO DE HUMO Y LA TRAZA. Salen de la boca del arma del propio bot, no de su pecho: en
## tercera persona la diferencia se nota, el humo colgaba del hombro.
func _disparo_visible(dir: Vector3, largo: float) -> void:
	var fx = _fx()
	if fx == null or avatar == null or avatar._wm == null or not is_instance_valid(avatar._wm):
		return
	var wm = avatar._wm
	var boca: Vector3 = wm.global_transform * wm.muzzle_pos
	# EL FOGONAZO, QUE FALTABA. Los bots tenian traza, humo y casquillos, pero no el destello: la
	# llamada existia en los jugadores de red y aqui nunca se puso. Es de las cosas que mas se echan
	# de menos sin saber por que, porque el fogonazo es lo que te dice DESDE DONDE te disparan -de
	# noche o a contraluz, muchas veces es lo unico que ves del que esta tirando-.
	if wm.has_method("fire_flash"):
		wm.fire_flash(true)
	fx.tracer(boca + dir * 0.30, boca + dir * largo)
	fx.muzzle_smoke(boca, dir, 0.55)
	fx.shell_ajena(wm, dir)


## El nodo de efectos: los bots no lo reciben al nacer (solo en modo promo), asi que se toma del
## jugador, que siempre lo tiene.
func _fx():
	if demo_fx != null:
		return demo_fx
	if is_instance_valid(target) and "effects" in target and target.effects != null:
		return target.effects
	# LOS COMPAÑEROS BOT DISPARAN A ZOMBIS, que no tienen efectos: sin esto no se veia ni la bala, ni el
	# fogonazo, ni el humo de sus disparos (2026-09-26). El jugador de esta maquina siempre los tiene.
	if is_instance_valid(player) and "effects" in player:
		return player.effects
	return null


## LA BALA QUE TE PASA ROZANDO. Se busca el punto del recorrido de la bala mas cercano a tu cabeza:
## si pasa a menos de un par de metros, se oye ahi el aire rasgandose. Antes bastaba con fallar a
## menos de 30 m para oirlo, asi que sonaba igual una bala junto a la oreja que una perdida a 20 m.
func _silbido(eye: Vector3, dir: Vector3, largo: float) -> void:
	if not is_instance_valid(target):
		return
	var oreja: Vector3 = target.global_position + Vector3(0.0, 1.55, 0.0)
	var t: float = clampf((oreja - eye).dot(dir), 0.0, largo)
	if t < 1.0:
		return          # disparada a bocajarro: no le da tiempo a silbar
	var cerca: Vector3 = eye + dir * t
	var d: float = cerca.distance_to(oreja)
	if d < Audio.WHIZ_DIST:
		Audio.bullet_whiz(cerca, d, _arma_sonido, eye.distance_to(oreja))

## `push`: empujón del impacto en unidades de velocidad (dirección de la bala x su impulso).
## Se guarda para dárselo al cadáver, que cae hacia donde iba andando más ese empujón.
## DERRIBADO POR UNA EXPLOSION (como el jugador, ver player.gd): cae, se levanta, y mientras tanto
## ni se mueve ni dispara.
const CAIDA_DUR := 3.5
# (nativa, BotBase) var caido_t := 0.0

func derribar(_dir: Vector3 = Vector3.ZERO) -> void:
	if caido_t > 0.0 or health <= 0.0 or avatar == null or not avatar.has_method("caer"):
		return
	caido_t = CAIDA_DUR
	avatar.caer()

## EL ESCUDO BLINDADO DE LOS BOTS (2026-09-28, pedido: "a los bots con escudo les traspasan las balas, no veo
## chispas"). Solo el jugador lo tenia (player._escudo_para): el del bot era de adorno y las balas le entraban.
## Ahora igual: lo que llega por delante (EscudoScript.tapa, con el arco de cobertura) se lo come el escudo, con
## chispas y el golpe del metal, hasta gastar su vida (EscudoScript.VIDA) y romperse (lo suelta y sigue a pistola).
## En una copia de red se ve y suena aqui mismo, y el anfitrion (que lleva la vida) hace la cuenta.
const EscudoBot := preload("res://scripts/escudo.gd")
var escudo_vida := EscudoBot.VIDA
var escudo_roto := false


func _escudo_tapa(push: Vector3) -> bool:
	if escudo_roto or health <= 0.0 or push.length_squared() < 1e-6 or avatar == null or not is_instance_valid(avatar):
		return false
	if not avatar.has_method("escudo_activo") or not avatar.escudo_activo():
		return false
	var frente := -global_transform.basis.z
	return EscudoBot.tapa(frente, -push, bool(avatar.get("aiming")))


func _escudo_golpe_visto(push: Vector3) -> void:
	var frente := -global_transform.basis.z
	frente.y = 0.0
	var punto: Vector3 = global_position + Vector3(0.0, 1.25, 0.0) + frente.normalized() * 0.55
	Audio.play3d("metal/hit-m", punto, 0.0, 0.12, 50.0, Audio.PRI_MID)
	Audio.play3d("spark", punto, -4.0, 0.1, 40.0, Audio.PRI_LOW)
	Audio.bf3d("gadget/escudo_golpe", punto, -4.0, 40.0, Audio.PRI_MID)
	var fx = _fx()
	if fx and fx.has_method("sparks"):
		fx.sparks(punto, -push.normalized())
	if avatar.has_method("escudo_golpe"):
		avatar.escudo_golpe()


func _romper_escudo_bot() -> void:
	if escudo_roto:
		return
	escudo_roto = true
	var punto: Vector3 = global_position + Vector3(0.0, 1.2, 0.0)
	Audio.play3d("glass/break-s", punto, 2.0, 0.05, 70.0, Audio.PRI_HIGH)
	Audio.play3d("metal/hit-l", punto, 0.0, 0.05, 60.0, Audio.PRI_MID)
	Audio.bf3d("gadget/escudo_roto", punto, 0.0, 60.0, Audio.PRI_HIGH)
	if avatar and is_instance_valid(avatar) and avatar.has_method("escudo_romper"):
		avatar.escudo_romper()
	if not remoto:
		Net.net_bot_escudo_roto(red_id)      # que las copias de los demas lo suelten tambien


func take_damage(d: float, push: Vector3 = Vector3.ZERO) -> void:
	_golpe_bomba_t = _time
	# EL ESCUDO SE LO COME (por delante): chispas aqui; la vida del escudo la lleva el anfitrion. (Lo de 9.999 es la
	# muerte que manda el anfitrion a las copias: esa no la para nada.)
	if d < 9000.0 and _escudo_tapa(push):
		_escudo_golpe_visto(push)
		if remoto:
			Net.net_dano_bot(red_id, d, push)
			return
		escudo_vida = maxf(0.0, escudo_vida - d)
		if escudo_vida <= 0.0:
			_romper_escudo_bot()
		return
	# EL CUERPO ENCAJA EL GOLPE (avatar_animator.recibir_golpe), en todas las maquinas que lo ven
	if d < 9000.0 and avatar and avatar.has_method("recibir_golpe"):
		avatar.recibir_golpe(push, d)
	# lo que TU le haces, para el resumen de muerte (duelo.gd)
	if ultimo_atacante != null and is_instance_valid(ultimo_atacante) and ultimo_atacante == Net.local_player and health > 0.0:
		DueloScript.hecho(self, minf(d, health))
		if d >= health and not remoto:
			DueloScript.mate(self)
	# UNA COPIA NO SE MUERE POR SU CUENTA. Se lo cuenta al anfitrion, que lleva su vida, y espera a
	# que le diga si ha caido. Si cada invitado lo matara en su pantalla, dos personas disparando al
	# mismo bot lo mataria dos veces y en la del anfitrion seguiria vivo.
	if remoto:
		Net.net_dano_bot(red_id, d, push)
		return

	health -= d
	_last_push = push
	# BF: un quejido de vez en cuando al recibir (no en cada bala: una rafaga seria un coro)
	if health > 0.0 and _time - _quejido_t > 1.5 and randf() < 0.35:
		_quejido_t = _time
		Audio.bf3d("soldado/herido", global_position + Vector3(0, 1.5, 0), -6.0, 35.0, Audio.PRI_LOW)
	# Sin destello rojo al recibir daño: si el golpe lo mataba, el color no se restauraba nunca
	# (el temporizador vive en _physics_inner, que ya no corre) y el cadáver quedaba rojo fijo.
	# le han dado: sabe más o menos de dónde viene y reacciona
	if state != State.COMBAT:
		# hacia QUIEN LE DISPARA (2026-10-15, pedido: "si recibe daño de costado, que gire y mire"; antes iba hacia su
		# objetivo, que podia ser otro)
		var de: Vector3 = ultimo_atacante.global_position if is_instance_valid(ultimo_atacante) and ultimo_atacante is Node3D 			else (target.global_position if is_instance_valid(target) else global_position)
		last_known = de + Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
		var plano := Vector3(de.x - global_position.x, 0.0, de.z - global_position.z)
		if plano.length() > 0.5:
			rotation.y = atan2(-plano.x, -plano.z)      # se gira ya hacia el (y si lo ve, combate)
			yaw_target = rotation.y
		last_known_t = _time
		awareness = minf(1.0, awareness + 0.6)
		_enter_investigate()
	# LE ESTAN DANDO: se quita de en medio. Antes recibir un tiro no cambiaba NADA de como se movia,
	# asi que un bot al que le acertabas seguia plantado disparando hasta caer. Ahora entra en "bajo
	# fuego" unos segundos: no se agacha quieto, cambia de lado y se mueve de verdad (ver _combat).
	bajo_fuego_t = 2.2
	crouching = false
	if combat_strafe == 0.0:
		combat_strafe = [-1.0, 1.0][randi() % 2]
	else:
		combat_strafe = -combat_strafe    # el tiro venia a donde estaba: se rompe el ritmo
	combat_strafe_t = randf_range(0.5, 0.9)
	if health <= 0.0:
		# UN COMPAÑERO CAIDO PESA TRIPLE. Un tiro oído es "algo pasa"; un muerto es "id ya". Es lo que
		# hace que el grupo de reacción salga de verdad en vez de quedarse en su puesto.
		var _tmu := Time.get_ticks_usec()
		Escuadra.avisar(global_position, team, 3.0)
		var mata = ultimo_atacante if is_instance_valid(ultimo_atacante) else null
		if mata != null and mata != self:
			var ar: Array = Net.arma_de(mata, _last_push.length() > 4.5)
			var eq_a := String(mata.get("team")) if "team" in mata else ""
			if eq_a == "" and "peer_id" in mata:
				eq_a = Net.team_of(int(mata.get("peer_id")))
			Net.net_baja(DueloScript.nombre(mata), eq_a, String(ar[0]), String(ar[1]), DueloScript.nombre(self), team)
		else:
			Net.net_baja("", "", "", "", DueloScript.nombre(self), team)
		Prof.add("bot.muere.baja", Time.get_ticks_usec() - _tmu)
		_tmu = Time.get_ticks_usec()
		died.emit(global_position, team,
			ultimo_atacante if is_instance_valid(ultimo_atacante) else null, nombre_marcador)
		Prof.add("bot.muere.aviso", Time.get_ticks_usec() - _tmu)
		_tmu = Time.get_ticks_usec()
		_make_corpse()
		Prof.add("bot.muere.cadaver", Time.get_ticks_usec() - _tmu)
		queue_free()

## Cadáver con físicas: el avatar se queda en la pose en la que murió, colgado de un RigidBody3D
## que hereda la velocidad que llevaba (andando o corriendo) más el empujón del disparo, así cae
## hacia donde iba y rueda por el suelo o por un hueco. Sigue estando ahí y se puede empujar a
## tiros después (grupo "corpse").
static var _corpses: Array = []
## Lo fija el ajuste gráfico "Cuerpos en el suelo" (0 = no quedan cadáveres).
static var max_corpses := 14
## Segundos que un cadaver se queda en el suelo antes de disolverse (0 = hasta que lo eche el tope).
## Lo fija el ajuste grafico "Tiempo de los cuerpos".
static var cuerpo_vida := 3.0

func _make_corpse() -> void:
	var _tmc := Time.get_ticks_usec()
	Audio.muere_otro(global_position, _last_push, has_meta("muerte_mazo"))
	Prof.add("bot.mc.audio", Time.get_ticks_usec() - _tmc); _tmc = Time.get_ticks_usec()
	# LOS DE TU BANDO NO CUENTAN PARA EL TOPE (rescate.gd): con el tope bajo de la calidad Baja, el siguiente bot
	# que caia en la pelea disolvia el cuerpo de tu compañero antes de que llegaras a recogerlo o revivirlo.
	var aliado: bool = String(team) != "" and String(team) == Net.my_team() and not Net.dm_mode
	aliado = aliado or String(team) == "pve"      # compañero bot de los modos zombi: espera la RCP o el refugio
	if (max_corpses <= 0 and not aliado) or avatar == null or not is_instance_valid(avatar) or get_parent() == null:
		return
	var rb := RigidBody3D.new()
	rb.name = "Corpse"
	rb.add_to_group("corpse")
	rb.mass = 78.0
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"   # la busca por nombre el ragdoll para apagarla (mismo fallo que criatura.gd)
	var cap := CapsuleShape3D.new()
	cap.radius = 0.33
	cap.height = 1.38
	col.shape = cap
	col.position = Vector3(0, 0.71, 0)
	rb.add_child(col)
	# Fuera del nodo "Enemies": ahí dentro, cualquier recorrido de enemigos (replanificar rutas,
	# etc.) le hablaría al cadáver como si fuese un bot.
	var host: Node = get_parent().get_parent() if get_parent().get_parent() else get_parent()
	host.add_child(rb)
	rb.global_transform = global_transform
	Prof.add("bot.mc.cuerpo", Time.get_ticks_usec() - _tmc); _tmc = Time.get_ticks_usec()
	# el avatar pasa al cadáver conservando su pose y su orientación
	var xf := avatar.global_transform
	remove_child(avatar)
	rb.add_child(avatar)
	avatar.global_transform = xf
	Prof.add("bot.mc.mover", Time.get_ticks_usec() - _tmc); _tmc = Time.get_ticks_usec()
	avatar.unequip_weapon()            # suelta el arma: un muerto no la sujeta
	Prof.add("bot.mc.soltar", Time.get_ticks_usec() - _tmc); _tmc = Time.get_ticks_usec()

	# RAGDOLL DE VERDAD, si se puede. Se monta APARTE del avatar y a escala de metros (ver
	# ragdoll.gd): doce cuerpos con juntas que resuelve el motor de física, no una pose calculada.
	#
	# Y si el ragdoll entra, el cuerpo rígido de aquí se queda QUIETO y congelado desde el primer
	# cuadro. No es que sobre: sigue siendo quien pertenece al grupo "corpse", quien cuenta para el
	# tope de cadáveres y quien se disuelve al tocarle el turno. Pero si además se moviera, el avatar
	# viajaría con él MIENTRAS los huesos ya lo están colocando por su cuenta, y se vería el cuerpo
	# desplazado el doble. Uno manda o manda el otro.
	var rd = null
	if avatar.skeleton != null:
		rd = RagdollScript.crear(
			host, avatar.skeleton, Vector3(velocity.x, 0.0, velocity.z), _last_push)
	Prof.add("bot.mc.ragdoll", Time.get_ticks_usec() - _tmc); _tmc = Time.get_ticks_usec()
	if rd != null:
		# EL ANIMADOR SE CALLA. Aqui estaba el fallo que dejaba una figura congelada: el ragdoll
		# escribe las poses de los huesos en `_physics_process`, pero el `_process` del avatar
		# REESCRIBE todos los huesos cada cuadro con el clip que tuviera puesto -y corre despues-.
		# La animacion ganaba siempre, asi que el cuerpo se quedaba clavado en su ultima pose
		# mientras los cuerpos de fisica caian invisibles al lado.
		#
		# Dos que escriben lo mismo y el ultimo manda. Apagando el animador, manda la fisica.
		avatar.set_process(false)
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		rb.freeze = true
		var cs := rb.get_node_or_null("CollisionShape3D")
		if cs:
			(cs as CollisionShape3D).disabled = true
		rb.set_meta("ragdoll", rd)
	else:
		# PLAN B: el desplome de siempre. Si el rig no trae los huesos que el ragdoll necesita, más
		# vale un cadáver que se afloja a mano que ninguno.
		avatar.go_limp()
		rb.linear_velocity = Vector3(velocity.x, 0.6, velocity.z) + _last_push
		rb.angular_velocity = Vector3(randf_range(-2.5, 2.5), randf_range(-1.5, 1.5), randf_range(-2.5, 2.5))
		# Y NO SE CONGELA. Aqui se le ponia un temporizador que lo volvia estatico tras tres segundos
		# quieto; el motor ya lo duerme solo sin endurecerlo (ver ragdoll.gd).
	avatar = null
	if not aliado:
		_corpses.append(rb)     # (el de un compañero va aparte: no lo echa del tope el siguiente que caiga)
	# A LOS TRES SEGUNDOS, SE DISUELVE. Tiempo de sobra para verlo caer y quedarse tirado, y luego
	# el mismo efecto de disolucion que ya usaba el tope de cadaveres.
	# RESCATE (rescate.gd): el cuerpo sabe de quien era, para recogerlo o revivirlo. Los de TU bando se quedan
	# al menos 30 s en el suelo (y en el duelo a muerte no hay rescate: ahi siguen el ajuste de siempre).
	rb.set_meta("rescate_red_id", red_id)
	rb.set_meta("rescate_team", String(team))
	rb.set_meta("rescate_nombre", String(nombre_marcador) if "nombre_marcador" in self else "")
	var vida_cuerpo := cuerpo_vida
	if String(team) != "" and String(team) == Net.my_team() and not Net.dm_mode:
		vida_cuerpo = 30.0 if cuerpo_vida <= 0.0 or cuerpo_vida < 30.0 else cuerpo_vida
	if String(team) == "pve":
		vida_cuerpo = 0.0      # no se disuelve: se lo lleva pve._revivir_caidos al llegar al refugio
	if vida_cuerpo > 0.0:
		_disolver_en(rb, vida_cuerpo)
	# tope: los cadáveres se quedan, pero no infinitos (cada uno es un cuerpo físico + su malla)
	while _corpses.size() > max_corpses:
		var old = _corpses.pop_front()
		if is_instance_valid(old):
			_disolver_cuerpo(old)
	Prof.add("bot.mc.resto", Time.get_ticks_usec() - _tmc)


## AL CADAVER MAS VIEJO LE TOCA IRSE. Antes se borraba de golpe -estabas mirando y desaparecia
## delante de ti- que es de las cosas que mas cantan. Ahora se consume en poco mas de un segundo, y
## ademas queda claro que se va porque le toca y no porque el juego se haya roto.
## Programa la disolucion de un cadaver dentro de `seg` segundos.
##
## ES ESTATICA Y EL RELOJ CUELGA DEL PROPIO CADAVER, no del bot. El bot se borra en cuanto muere, asi
## que un temporizador suyo -o una funcion que dependiera de el- no llegaria a sonar. Colgando del
## cadaver, si este desaparece antes (por el tope de cuerpos), el reloj se va con el y no queda nada
## pendiente que falle.
static func _disolver_en(rb: Node, seg: float) -> void:
	var t := Timer.new()
	t.wait_time = seg
	t.one_shot = true
	t.autostart = true
	rb.add_child(t)
	t.timeout.connect(func() -> void:
		# si el tope de cadaveres ya lo esta disolviendo, ha salido del grupo: no se repite
		if not is_instance_valid(rb) or not rb.is_in_group("corpse"):
			return
		_corpses.erase(rb)
		_disolver_cuerpo(rb))


static func _disolver_cuerpo(rb: Node) -> void:
	var av: Node = null
	for c in rb.get_children():
		if c.has_method("disolucion"):
			av = c
			break
	var mn = rb.get_parent()
	var permitido: bool = not (mn and ("_disolver_on" in mn) and not bool(mn._disolver_on))
	if av == null or not rb.is_inside_tree() or not permitido:
		rb.queue_free()
		return
	rb.remove_from_group("corpse")   # mientras se va ya no recibe tiros: no hay a quien empujar
	# y sus cuerpos de fisica se van con el: doce por cadaver no se pueden quedar sueltos por el mapa
	var rdx = rb.get_meta("ragdoll") if rb.has_meta("ragdoll") else null   # (con null por defecto Godot da error igual)
	if rdx != null and is_instance_valid(rdx):
		(rdx as Node).queue_free()
	var tw := rb.create_tween()
	tw.tween_method(func(k: float) -> void:
			if is_instance_valid(av):
				av.disolucion(k), 0.0, 1.0, 1.3)
	tw.tween_callback(rb.queue_free)


# ---------------------------------------------------------------------------
# ATRACO: los bots van a la caja y la abren
# ---------------------------------------------------------------------------
## El nodo del atraco, buscado una vez (en los mapas sin atraco se queda en null y esto no hace nada).
var _heist = null
var _heist_buscado := false
## Sitio concreto donde se planta este bot para trabajar: alrededor de la caja y separado de los
## demas, o los seis del equipo se meterian en el mismo metro cuadrado empujandose.
var _puesto_caja := Vector3.ZERO
## s que lleva sin avanzar yendo a la caja: pasado un umbral, es que hay pared y hay que romperla.
var _atasco_t := 0.0
var _golpe_t := 0.0

# ---------------------------------------------------------------------------
# ATASCADO CONTRA UNA PARED (2026-09-23, pedido): el camino corto tenia un murete y el bot se quedaba
# empujandolo. Si en 1,5 s no avanza medio metro estando lejos de su destino, decide: la mitad de las veces
# SACA EL MAZO y rompe lo que tiene delante (hasta 6 golpes); si no, o si no hay nada que romper, DA UN
# RODEO por un punto a un lado y luego sigue. Tres atascos seguidos en el mismo sitio: siempre rodeo.
# ---------------------------------------------------------------------------
var _pd_atasco_t := 0.0
var _pd_atasco_pos := Vector3.ZERO
var _pd_atascos := 0
# (nativa, BotBase) var _pd_rompiendo_t := 0.0
var _pd_golpes := 0
# (nativa, BotBase) var _pd_rodeo_t := 0.0
# (nativa, BotBase) var _pd_destino_real := Vector3.ZERO

func _pd_atasco(dt: float) -> bool:
	if _pd_rompiendo_t > 0.0:
		_pd_rompiendo_t -= dt
		_stop(dt)
		var hacia: Vector3 = path[0] if path.size() > 0 else move_target
		var antes := _golpe_t
		_mazazo_hacia(hacia, dt)
		if _golpe_t > antes:
			_pd_golpes += 1
		# ¿ya hay hueco? (nada solido a la altura del pecho delante) o se acabo la paciencia
		var ojo := global_position + Vector3(0, 1.1, 0)
		var dirh := Vector3(hacia.x - ojo.x, 0.0, hacia.z - ojo.z).normalized()
		var libre: bool = not world.raycast(ojo, dirh, 1.6).get("hit", false) and not world.raycast(ojo - Vector3(0, 0.6, 0), dirh, 1.6).get("hit", false)
		if libre or _pd_golpes >= 6 or _pd_rompiendo_t <= 0.0:
			_pd_rompiendo_t = 0.0
			_montar_arma(arma if arma != "" else "rifle")
			invalidate_path()
			if not libre:
				_dar_rodeo()
		return true
	if global_position.distance_to(move_target) < 2.5:
		_pd_atasco_t = 0.0
		return false
	_pd_atasco_t += dt
	if _pd_atasco_t < 1.5:
		return false
	_pd_atasco_t = 0.0
	var movido := global_position.distance_to(_pd_atasco_pos)
	_pd_atasco_pos = global_position
	if movido > 0.5:
		_pd_atascos = 0
		return false
	_pd_atascos += 1
	var hacia2: Vector3 = path[0] if path.size() > 0 else move_target
	var ojo2 := global_position + Vector3(0, 1.1, 0)
	var hay_pared: bool = world.raycast(ojo2, Vector3(hacia2.x - ojo2.x, 0.0, hacia2.z - ojo2.z).normalized(), 2.0).get("hit", false)
	if hay_pared and _pd_atascos < 3 and randf() < 0.5:
		_pd_rompiendo_t = 5.0
		_pd_golpes = 0
		_golpe_t = 0.5         # lo que tarda en sacar el mazo
		if avatar and avatar.has_method("equip_weapon"):
			avatar.equip_weapon("sledge", "mazo_obra")
		return true
	_dar_rodeo()
	return false

func _dar_rodeo() -> void:
	var base: Vector3 = _pd_destino_real if _pd_rodeo_t > 0.0 else move_target
	var d := base - global_position
	d.y = 0.0
	var lado := Vector3(-d.z, 0.0, d.x).normalized() * (1.0 if randf() < 0.5 else -1.0)
	for _i in 4:
		# POR EL TURNO DEL A*, como todas (2026-10-01, medido: aqui iban cuatro busquedas seguidas SIN tope de nodos,
		# y una sin salida eran ~50 ms de tiron). La primera pasa siempre; las demas, si queda presupuesto.
		if _i > 0 and not AstarTurno.puedo():
			break
		var q: Vector3 = world.find_ground(global_position + lado * randf_range(6.0, 12.0) - d.normalized() * randf_range(2.0, 6.0))
		if q.y > -1.0 and AstarTurno.buscar(world, global_position, q, "bot_rodeo").size() >= 2:
			_pd_destino_real = base
			_pd_rodeo_t = 8.0
			move_target = q
			invalidate_path()
			return
		lado = -lado

## Devuelve true si este fotograma lo ha gobernado el atraco (y entonces no corre la maquina normal).
func _atraco_tick(dt: float) -> bool:
	if not _heist_buscado:
		_heist_buscado = true
		_heist = get_tree().get_first_node_in_group("heist")
	if _heist == null or not is_instance_valid(_heist):
		return false
	if _heist.vault == null or not is_instance_valid(_heist.vault):
		return false
	# EL TERMINAL INGRESANDO: los de otro color van a robarlo (quedarse 7 s al lado) y los del color del
	# terminal van a defenderlo. Es a donde se mueve la pelea durante los dos minutos del ingreso.
	if _heist.vault_state == 2 and _heist.out_state == 2 and _heist.cashout != null and team != "":
		var term: Vector3 = _heist.cashout.global_position
		var dt_term: float = global_position.distance_to(term)
		if dt_term > 2.6:
			var vel_t: float = SPRINT_SPEED if dt_term > 22.0 else RUN_SPEED
			var a2: float = TAU * float(get_instance_id() % 8) / 8.0
			_go_to(term + Vector3(cos(a2) * 1.8, 0.0, sin(a2) * 1.8), vel_t, dt, 1.0)
		else:
			_stop(dt)
			_face(term)
		if dt_term < float(_heist.CAPTURE_RANGE):
			_heist.bot_en_terminal(team)
		return true
	if _heist.vault_state == 2:      # VAULT_OPEN: ya esta abierta, a lo suyo
		return false
	var caja: Vector3 = _heist.vault.global_position
	if _puesto_caja == Vector3.ZERO:
		# en corro alrededor de la caja: el angulo sale del propio bot, asi que cada uno coge el suyo
		var a: float = TAU * float(get_instance_id() % 8) / 8.0
		_puesto_caja = caja + Vector3(cos(a) * 1.6, 0.0, sin(a) * 1.6)
	var d: float = global_position.distance_to(caja)
	if d > 2.4:
		var v: float = SPRINT_SPEED if d > 22.0 else RUN_SPEED
		var antes: Vector3 = global_position
		_go_to(_puesto_caja, v, dt, 1.0)
		# SI HAY UNA PARED DE POR MEDIO, SE ABRE A MAZAZOS. Antes el bot se quedaba empujando contra
		# el muro para siempre: el A* no tiene camino, asi que se plantaba a un metro de la caja y ahi
		# se quedaba. Esto es lo que hace el juego: lo que estorba se rompe.
		_atasco_t = (_atasco_t + dt) if global_position.distance_to(antes) < v * dt * 0.35 else 0.0
		if _atasco_t > 0.8 and d < 14.0:
			_mazazo_hacia(caja, dt)
		return true
	# YA ESTA EN LA CAJA: se queda trabajando en ella, mirandola, y suma a la barra de los bots
	_stop(dt)
	_face(caja)
	_heist.bot_abriendo(team, dt)
	return true


## UN MAZAZO CONTRA LO QUE TAPA LA CAJA. Se talla igual que el mazo del jugador (potencia 255, la
## dureza va en el radio), a la altura del pecho y solo si de verdad hay pared delante: si no, el bot
## estaria picando aire. No hace dano a la gente, solo abre el boquete.
const MAZO_RADIO := 0.85
const MAZO_CADENCIA := 0.75

func _mazazo_hacia(caja: Vector3, dt: float) -> void:
	_golpe_t -= dt
	if _golpe_t > 0.0:
		return
	var ojo: Vector3 = global_position + Vector3(0, 1.10, 0)
	var dir: Vector3 = (Vector3(caja.x, ojo.y, caja.z) - ojo).normalized()
	var r: Dictionary = world.raycast(ojo, dir, 2.2)
	if not r.get("hit", false):
		return                       # no hay pared ahi delante: el atasco es otra cosa
	_golpe_t = MAZO_CADENCIA
	_face(caja)
	# el gesto se ve, no es un agujero que aparece solo
	if avatar and avatar.has_method("play_swing"):
		avatar.play_swing(AvatarScript.swing_dur_s)
	Net.net_explode(world, r.position, MAZO_RADIO, 255)    # el mazazo del bot, en todas las pantallas
	Audio.play3d("clickdown", r.position, -1.0, 0.1, 30.0, Audio.PRI_MID)
	get_tree().call_group("enemies", "hear_noise", r.position, 18.0)
