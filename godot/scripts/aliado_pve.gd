extends "res://scripts/enemy.gd"
## COMPAÑERO BOT DE LOS MODOS ZOMBI (2026-09-25, pedido: "en el modo zombie, que es para 4, si no hay gente
## pon los bots que faltan: que sigan a los jugadores reales, ayuden a matar zombis, si tienen botiquin os
## curen, y si el jugador se aleja mucho se teletransportan a su posicion"). Como los bots de Left 4 Dead.
##
## Es el bot de siempre (enemy.gd: cuerpo, arma, andar por el A* de voxels, disparar replicado) con OTRO
## CEREBRO. Lo pone y lo quita pve.gd (tambien en la campaña, que hereda de el) para que entre personas y
## bots sean siempre cuatro; solo piensa el anfitrion, y los invitados ven su copia como cualquier bot.
##
##   SEGUIR    al jugador real mas cercano, a 2,5-4 m, cada uno en su hueco (detras, a los lados)
##   DISPARAR  a la criatura mas cercana que vea (35 m), en rafagas cortas, sin dejar de seguir
##   CURAR     si lleva botiquin y un jugador baja de la mitad de vida: va, se para a su lado, la animacion de
##             vendar, y le deja la vida entera (el herido ve la barra "TE CURA BOT 2"). En la campaña, si
##             ya lo gasto, recoge otro botiquin del suelo si lo tiene cerca
##   SALTAR    si se queda a mas de 35 m del jugador (o 6 s atascado lejos), aparece detras de el
## LES ATACAN LAS CRIATURAS (2026-09-26): van a por ellos igual que a por vosotros y les hacen daño; tus balas
## y tus explosiones no. Si caen, mueren de verdad (cadaver con fisica): RCP o vuelven en el refugio.
## y si estan heridos y llevan botiquin, se curan ellos mismos cuando no hay nada a lo que disparar.

const SEGUIR_CERCA := 4.0
const TELEPORT_D := 35.0
const VISTA_D := 28.0
## MAS HUMANOS (2026-09-25, pedido: "no se quedan sin balas, apuntan muy bien, no recargan nunca: ellos ganan
## la partida"). Cargador y RECARGA de verdad, una reserva que se acaba (se rellena en las cajas de municion,
## al llegar al refugio y en cada oleada nueva), un tiempo de reaccion al ver a cada bicho, rafagas cortas con
## pausas, y la punteria abierta: apuntan a un punto al azar de hasta medio metro alrededor del bicho.
const RESERVA_MAX := 120
const REACCION := Vector2(0.45, 0.9)
const FALLO_M := 0.5
var reserva := RESERVA_MAX
var _reaccion_t := 0.0
var _ultimo_blanco: Node3D = null
var _aviso_sin_balas := false
const CURAR_BAJO := 0.5          ## fraccion de la vida maxima por debajo de la cual se cura
const CURAR_T := 5.0

var hueco := 0                   ## su sitio alrededor del jugador (0..2)
var tiene_botiquin := true
var campana: Node = null         ## el modo (pve.gd / campana.gd): los objetos del suelo y la ruta
var _lider: Node3D = null
var _curando: Node3D = null      ## a quien esta curando
var _cura_t := 0.0
var _cura_desde := Vector3.ZERO
var _ir_botiquin: Node3D = null
var _rafaga := 0
var _pausa_t := 0.0
var _lejos_t := 0.0
var _mira_t := 0.0


func setup(w, p, i: int) -> void:
	super.setup(w, p, i)
	remove_from_group("enemies")       # las criaturas llaman a "enemies" (hear_noise): no es de los suyos
	add_to_group("aliados_pve")
	remove_from_group("damageable")    # las granadas y explosiones de los jugadores no les hacen nada
	health = VIDA_MAX
	arma_2 = ""                         # nada de cohetes entre compañeros
	municion = _cargador()


## Reserva llena (cajas de municion, refugio, oleada nueva)
func recargar_reserva() -> void:
	reserva = RESERVA_MAX
	_aviso_sin_balas = false


const VIDA_MAX := 100.0

## Solo llega el daño de las criaturas: a los jugadores les para is_friendly / is_ally_of.
## AL MORIR, MUEREN DE VERDAD (2026-09-26, pedido): el cuerpo cae con fisica como el de cualquiera (el cadaver de
## enemy.gd), se les puede recoger y hacer la RCP (rescate.gd) y, si no, vuelven al llegar al refugio o en la
## oleada siguiente, como las personas. Antes se tumbaban y se levantaban solos a los 15 s.
func take_damage(d: float, _push: Vector3 = Vector3.ZERO) -> void:
	if health <= 0.0:
		return
	health -= d
	if randf() < 0.35:
		Audio.bf3d("soldado/herido_quejido", global_position + Vector3.UP * 1.4, -4.0, 25.0, Audio.PRI_LOW)
	if health > 0.0:
		return
	health = 0.0
	soltar_agarre()
	if campana != null and campana.has_method("aliado_muerto"):
		campana.aliado_muerto(hueco, bot_name)
	died.emit(global_position, team, null, bot_name)
	_make_corpse()
	# el cuerpo sabe que hueco era: al revivirle con la RCP vuelve el mismo compañero
	for c in get_tree().get_nodes_in_group("corpse"):
		if is_instance_valid(c) and int(c.get_meta("rescate_red_id", -1)) == int(red_id):
			c.set_meta("aliado_hueco", hueco)
	queue_free()


func is_friendly() -> bool:
	return true


func is_ally_of(_other_team: String) -> bool:
	return true


func _caido_tick(_dt: float) -> bool:
	return false


func hear_noise(_pos: Vector3, _radius: float) -> void:
	pass


func _pick_target() -> void:
	var mejor: Node3D = null
	var d_mejor := VISTA_D
	var ojo := global_position + Vector3(0, 1.25, 0)
	# PRIMERO EL QUE TIENE A UN COMPAÑERO (como los bots de Left 4 Dead): el cazador encima, el fumador tirando...
	for c in get_tree().get_nodes_in_group("criaturas"):
		if not is_instance_valid(c) or bool(c.get("muerta")) or c.get("_agarrando") == null or c.get("_agarrando") == self:
			continue
		var dd := global_position.distance_to((c as Node3D).global_position)
		if dd < VISTA_D and world.has_line_of_sight(ojo, (c as Node3D).global_position + Vector3(0, 1.0, 0)):
			target = c
			return
	for c in get_tree().get_nodes_in_group("criaturas"):
		if not is_instance_valid(c) or bool(c.get("muerta")) or bool(c.get("dormida")) and global_position.distance_to(c.global_position) > 12.0:
			continue
		var d := global_position.distance_to((c as Node3D).global_position)
		if d < d_mejor and world.has_line_of_sight(ojo, (c as Node3D).global_position + Vector3(0, 1.0, 0)):
			d_mejor = d
			mejor = c
	target = mejor


## El jugador real mas cercano (vivo)
func _buscar_lider() -> Node3D:
	var mejor: Node3D = null
	var d := INF
	var cand: Array = []
	if is_instance_valid(player) and not bool(player.get("spectating")) and float(player.get("health")) > 0.0:
		cand.append(player)
	for id in Net.remotes.keys():
		var r = Net.remotes[id]
		if is_instance_valid(r) and not bool(Net.dead_players.get(int(id), false)):
			cand.append(r)
	for c in cand:
		var dd := global_position.distance_to((c as Node3D).global_position)
		if dd < d:
			d = dd
			mejor = c
	return mejor


func _physics_inner(dt: float) -> void:
	var _qt := 0
	_time += dt
	if _caido_tick(dt):
		return
	if agarre != null and _agarre_bot_tick(dt):
		return
	if not on_floor:
		velocity.y -= GRAVITY * dt
	_qt = Time.get_ticks_usec()
	_lider = _buscar_lider()
	Prof.add("bot.lider", Time.get_ticks_usec() - _qt)
	if _lider == null:
		_stop(dt)
		_qt = Time.get_ticks_usec()
		_moverse(dt, null)
		Prof.add("bot.mover", Time.get_ticks_usec() - _qt)
		return
	# SALTAR AL JUGADOR si se ha quedado muy atras (o atascado lejos un rato)
	var d_lider := global_position.distance_to(_lider.global_position)
	_lejos_t = _lejos_t + dt if (d_lider > 12.0 and Vector2(velocity.x, velocity.z).length() < 0.4) else 0.0
	if d_lider > TELEPORT_D or _lejos_t > 6.0 or global_position.y < -5.0:
		_qt = Time.get_ticks_usec()
		teletransportar_a(_lider)
		Prof.add("bot.teleport", Time.get_ticks_usec() - _qt)
		return
	# a quien disparar
	if (Engine.get_physics_frames() + id) % 10 == 0 or (is_instance_valid(target) and bool(target.get("muerta"))):
		_qt = Time.get_ticks_usec()
		_pick_target()
		Prof.add("bot.blanco", Time.get_ticks_usec() - _qt)
	if not is_instance_valid(target) or bool(target.get("muerta")):
		target = null
	# QUE HACER: curar > coger botiquin > seguir (disparando por el camino)
	var destino := _hueco_junto_a(_lider)
	var prisa := RUN_SPEED
	if _curando == null and tiene_botiquin and target == null:
		_curando = self if health < VIDA_MAX * 0.4 else _herido_cerca()
		if _curando != null:
			_cura_t = 0.0
	if _curando != null:
		if not _curar_tick(dt):
			_curando = null
		else:
			destino = Vector3.INF
	elif not tiene_botiquin and target == null:
		if _ir_botiquin == null or not is_instance_valid(_ir_botiquin):
			_ir_botiquin = _botiquin_cerca()
		if _ir_botiquin != null:
			destino = _ir_botiquin.global_position
			if global_position.distance_to(destino) < 1.6:
				_coger_botiquin(_ir_botiquin)
				_ir_botiquin = null
	if destino != Vector3.INF:
		var lejos := global_position.distance_to(destino)
		# ESPRINTAN como tu (2026-09-26, medido: con 14 m casi nunca pasaba y corrias tu solo mientras ellos
		# iban al trote): si se quedan atras o si el que siguen va esprintando
		var v_lider := Vector2(_lider.velocity.x, _lider.velocity.z).length() if "velocity" in _lider else 0.0
		if lejos > 7.0 or (v_lider > 4.2 and lejos > 3.0):
			prisa = SPRINT_SPEED
		elif lejos < 3.0:
			prisa = WALK_SPEED
		if global_position.distance_to(_lider.global_position) > SEGUIR_CERCA or _ir_botiquin != null:
			_qt = Time.get_ticks_usec()
			_go_to(destino, prisa, dt, 1.2)
			Prof.add("bot.ir", Time.get_ticks_usec() - _qt)
		else:
			_stop(dt)
	else:
		_stop(dt)
	# DISPARAR a la criatura que vea, en rafagas (mirandola aunque ande)
	var eye := global_position + Vector3(0, 0.9 if crouching else 1.25, 0)
	var t_eye := Vector3.ZERO
	_qt = Time.get_ticks_usec()
	_recarga_tick(dt)
	Prof.add("bot.recarga", Time.get_ticks_usec() - _qt)
	_qt = Time.get_ticks_usec()
	_municion_cerca()
	Prof.add("bot.municion", Time.get_ticks_usec() - _qt)
	if target != null:
		t_eye = target.global_position + Vector3(0, 1.0, 0)
		_face(target.global_position)
		if target != _ultimo_blanco:
			_ultimo_blanco = target
			_reaccion_t = randf_range(REACCION.x, REACCION.y)     # verlo no es dispararle ya
		_reaccion_t -= dt
		_visto_t = 1.0
		fire_t -= dt
		_pausa_t -= dt
		if fire_t <= 0.0 and _pausa_t <= 0.0 and _reaccion_t <= 0.0 and _curando == null and recarga_t <= 0.0 and municion > 0:
			var fallo := Vector3(randf_range(-1, 1), randf_range(-0.8, 0.6), randf_range(-1, 1)).normalized() * randf() * FALLO_M
			_qt = Time.get_ticks_usec()
			_shoot(eye, t_eye + fallo)
			Prof.add("bot.tiro", Time.get_ticks_usec() - _qt)
			municion -= 1
			_rafaga += 1
			_rafaga_i = _rafaga
			fire_t = 0.13
			if municion <= 0:
				_rafaga = 0
				_empezar_recarga_aliado()
			elif _rafaga >= randi_range(3, 5):
				_rafaga = 0
				_rafaga_i = 0
				_pausa_t = randf_range(0.5, 1.0)
	else:
		_rafaga = 0
		_rafaga_i = 0
		# sin nada a lo que disparar: mira hacia donde mira el jugador (cubriendo lo que el ve)
		_mira_t -= dt
		if _mira_t <= 0.0 and Vector2(velocity.x, velocity.z).length() < 0.5:
			_mira_t = randf_range(1.2, 2.6)
			var fr: Vector3 = -(_lider as Node3D).global_transform.basis.z
			_face(global_position + fr.rotated(Vector3.UP, randf_range(-0.9, 0.9)) * 5.0)
	_qt = Time.get_ticks_usec()
	_moverse(dt, t_eye if target != null else null)
	Prof.add("bot.mover", Time.get_ticks_usec() - _qt)


func _empezar_recarga_aliado() -> void:
	if reserva <= 0:
		if not _aviso_sin_balas:
			_aviso_sin_balas = true
			Audio.play3d("clickdown", global_position + Vector3.UP, -6.0, 0.1, 15.0, Audio.PRI_LOW)   # el clic en seco
		return
	_empezar_recarga()
	cubierto_pos = Vector3.ZERO           # el compañero recarga sin irse de tu lado


func _recarga_tick(dt: float) -> void:
	if recarga_t <= 0.0:
		if municion <= 0 and reserva > 0:
			_empezar_recarga_aliado()
		return
	recarga_t -= dt
	if recarga_t <= 0.0:
		if avatar and "reloading" in avatar:
			avatar.reloading = false
		var toma: int = mini(_cargador(), reserva)
		municion = toma
		reserva -= toma


## Pasar junto a una caja de municion de la campaña le llena la reserva (no la gasta: es para los jugadores)
func _municion_cerca() -> void:
	if reserva >= RESERVA_MAX or campana == null or not ("_objetos" in campana) or (Engine.get_physics_frames() + id) % 20 != 0:
		return
	for oid in campana._objetos:
		var o = campana._objetos[oid]
		if is_instance_valid(o) and String(o.get("tipo")) == "municion" and (o as Node3D).global_position.distance_to(global_position) < 2.5:
			recargar_reserva()
			return


func _moverse(dt: float, apunta) -> void:
	_voxel_move(dt)
	if avatar:
		var lvel: Vector3 = transform.basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
		avatar.drive_locomotion(lvel, crouching, on_floor, 0, dt)
		if apunta != null:
			var to: Vector3 = (apunta as Vector3) - (global_position + Vector3(0, 1.25, 0))
			avatar.look_pitch = atan2(to.y, Vector2(to.x, to.z).length())
		else:
			avatar.look_pitch = lerpf(avatar.look_pitch, 0.0, 4.0 * dt)
		var encara: bool = apunta != null
		if avatar.aiming != encara:
			avatar.aiming = encara


## Su sitio junto al jugador: detras y a un lado, cada bot en el suyo (no se amontonan)
func _hueco_junto_a(l: Node3D) -> Vector3:
	var fr: Vector3 = -l.global_transform.basis.z
	fr.y = 0.0
	fr = fr.normalized() if fr.length() > 0.01 else Vector3.FORWARD
	var lado := fr.cross(Vector3.UP)
	var offs := [[-2.2, 1.6], [-2.6, -1.6], [-3.6, 0.0]]
	var o: Array = offs[hueco % offs.size()]
	return l.global_position + fr * float(o[0]) + lado * float(o[1])


## APARECER DETRAS DEL JUGADOR: en su hueco si hay suelo y sitio; si no, lo mas cerca que se pueda
func teletransportar_a(l: Node3D) -> void:
	for intento in 6:
		var q := _hueco_junto_a(l) + Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)) * float(intento)
		var h: Dictionary = world.raycast(q + Vector3.UP * 2.0, Vector3.DOWN, 5.0)
		if not h.get("hit", false):
			continue
		var s: Vector3 = h["position"]
		if absf(s.y - l.global_position.y) > 1.5:
			continue
		if world.box_solid(s + Vector3(-0.3, 0.2, -0.3), s + Vector3(0.3, 1.7, 0.3)):
			continue
		global_position = s + Vector3.UP * 0.1
		velocity = Vector3.ZERO
		invalidate_path()
		_lejos_t = 0.0
		return
	global_position = l.global_position + Vector3.UP * 0.2       # ultimo recurso: donde esta el
	velocity = Vector3.ZERO
	invalidate_path()
	_lejos_t = 0.0


# ------------------------------------------------------------------ CURAR
func _vida_de(p: Node3D) -> Array:
	if p == self:
		return [health, VIDA_MAX]
	if p == player:
		return [float(player.get("health")), float(player.vida_max()) if player.has_method("vida_max") else 100.0]
	if "peer_id" in p:
		var vv: Array = Net.vidas.get(int(p.peer_id), [])
		if vv.size() >= 2:
			return [float(vv[0]), float(vv[1])]
	return [1.0, 1.0]


func _herido_cerca() -> Node3D:
	var mejor: Node3D = null
	var peor := CURAR_BAJO
	var cand: Array = [player] + Net.remotes.values()
	for p in cand:
		if not is_instance_valid(p) or (p as Node3D).global_position.distance_to(global_position) > 25.0:
			continue
		if p == player and (bool(player.get("spectating")) or String(player.get("curando")) != "" or int(player.get("_curado_por")) != 0):
			continue
		var v := _vida_de(p)
		if float(v[0]) <= 0.0:
			continue
		var f: float = float(v[0]) / maxf(1.0, float(v[1]))
		if f < peor:
			peor = f
			mejor = p
	# que no le cure otro bot a la vez
	if mejor != null:
		for b in get_tree().get_nodes_in_group("aliados_pve"):
			if b != self and is_instance_valid(b) and b.get("_curando") == mejor:
				return null
	return mejor


## Devuelve false cuando ya ha acabado (o se ha cortado)
func _curar_tick(dt: float) -> bool:
	if not is_instance_valid(_curando):
		return false
	var p: Vector3 = _curando.global_position
	if _cura_t <= 0.0:
		# yendo hacia el
		if global_position.distance_to(p) > 1.8:
			_go_to(p, RUN_SPEED, dt, 1.4)
			if global_position.distance_to(p) > 30.0:
				return false
			return true
		# empieza a curarle
		_cura_t = 0.001
		_cura_desde = p
		_stop(dt)
		if avatar and avatar.has_method("play_vendar"):
			avatar.play_vendar(CURAR_T)
		_aviso_cura("empieza")
		return true
	_stop(dt)
	_face(p)
	_cura_t += dt
	if p.distance_to(_cura_desde) > 2.5:
		_aviso_cura("corta")
		if avatar and avatar.has_method("parar_vendar"):
			avatar.parar_vendar()
		return false
	if _cura_t >= CURAR_T:
		_aviso_cura("fin")
		tiene_botiquin = false
		if avatar and avatar.has_method("parar_vendar"):
			avatar.parar_vendar()
		Audio.bf3d("gadget/jeringa_pincha", global_position, -2.0, 15.0, Audio.PRI_MID)
		return false
	return true


func _aviso_cura(evento: String) -> void:
	if _curando == self:
		if evento == "fin":
			health = VIDA_MAX
		return
	if _curando == player and player.has_method("curado_evento"):
		player.curado_evento(-100 - id, "UN COMPAÑERO", evento)
	elif "peer_id" in _curando:
		Net.net_cura_otro(int(_curando.peer_id), evento, "UN COMPAÑERO")


# ------------------------------------------------------------------ COGER BOTIQUINES (campaña)
func _botiquin_cerca() -> Node3D:
	if campana == null or not ("_objetos" in campana):
		return null
	var mejor: Node3D = null
	var d := 14.0
	for oid in campana._objetos:
		var o = campana._objetos[oid]
		if not is_instance_valid(o) or String(o.get("tipo")) != "botiquin":
			continue
		var dd := global_position.distance_to((o as Node3D).global_position)
		if dd < d:
			d = dd
			mejor = o
	return mejor


func _coger_botiquin(o: Node3D) -> void:
	if not is_instance_valid(o) or campana == null or not campana.has_method("_objeto_recogido"):
		return
	tiene_botiquin = true
	Audio.bf3d("soldado/coger", o.global_position, -4.0, 15.0, Audio.PRI_MID)
	campana._objeto_recogido(o)



# ------------------------------------------------------------------ AGARRADO POR UN ESPECIAL (2026-09-26, pedido:
# "que tambien agarren a los bots"). Igual que el jugador (player.agarrado_por): no dispara ni sigue a nadie, el
# cazador lo tiene en el suelo, el fumador lo arrastra, el jinete lo lleva, el cargador y el tanque lo cuelgan
# de la mano. Lo suelta la criatura (muerta, dañada, o al rato).
var agarre: Node3D = null
var agarre_modo := ""
var _devorado_t := -1.0          ## (el jefe no come bots: esto es para que criatura.gd pueda preguntar)
var _ag_t := 0.0
var _ag_dir := Vector3.FORWARD
var _ag_giro_t := 0.0

func agarrado_por(bicho: Node3D, modo: String) -> void:
	if modo == "":
		soltar_agarre()
		return
	agarre = bicho
	agarre_modo = modo
	_ag_t = 0.0
	target = null
	_curando = null
	velocity = Vector3.ZERO
	if avatar and avatar.has_method("parar_vendar"):
		avatar.parar_vendar()
	if avatar and "forcejeo" in avatar:
		avatar.forcejeo = true
	Audio.bf3d("soldado/grito", global_position + Vector3.UP * 1.5, -2.0, 30.0, Audio.PRI_MID)


func soltar_agarre() -> void:
	agarre = null
	agarre_modo = ""
	if avatar and "forcejeo" in avatar:
		avatar.forcejeo = false


func _agarre_bot_tick(dt: float) -> bool:
	if not is_instance_valid(agarre) or bool(agarre.get("muerta")):
		soltar_agarre()
		return false
	_ag_t += dt
	var bp: Vector3 = agarre.global_position
	var hacia := Vector3(bp.x - global_position.x, 0.0, bp.z - global_position.z)
	match agarre_modo:
		"lengua":
			var v := hacia.normalized() * 2.6 if hacia.length() > 1.6 else Vector3.ZERO
			velocity.x = v.x
			velocity.z = v.z
		"jinete":
			_ag_giro_t -= dt
			if _ag_giro_t <= 0.0:
				_ag_giro_t = randf_range(0.9, 1.8)
				_ag_dir = _ag_dir.rotated(Vector3.UP, randf_range(-1.6, 1.6))
			velocity.x = _ag_dir.x * 2.6
			velocity.z = _ag_dir.z * 2.6
		"cargado", "estrangulado":
			var mano: Vector3 = agarre.punto_mano() if agarre.has_method("punto_mano") else bp + Vector3.UP * 1.5
			global_position = mano + Vector3(0.0, -1.3 if agarre_modo == "estrangulado" else -0.9, 0.0)
			velocity = Vector3.ZERO
			_face(bp)
			return true
		_:
			velocity.x = 0.0
			velocity.z = 0.0
	if not on_floor:
		velocity.y -= GRAVITY * dt
	_face(bp)
	_moverse(dt, null)
	return true
