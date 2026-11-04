extends Node
## RESCATE DE COMPAÑEROS CAIDOS (2026-09-23, pedido). En todos los modos menos el duelo a muerte:
##   - el cuerpo de un compañero caido (persona o bot) se queda 30 s en el suelo
##   - acercandote aparecen RECOGER y REVIVIR ([E] y [F] en PC; dos botones en el movil)
##   - RECOGER: te lo cargas a hombros (REVIVIR se oculta y RECOGER pasa a SOLTAR); SOLTAR lo deja en el suelo
##   - REVIVIR (con el cuerpo en el suelo): lo pones boca arriba, RCP, se despierta y le ayudas a levantarse
##
## QUIEN VE QUE. Cada maquina ya tiene el cuerpo: el de una persona es el ragdoll de su copia (net_player) y el
## de un bot, su cadaver (enemy._make_corpse). Por red solo viajan las ordenes (Net.net_rescate): quien carga a
## quien, donde lo suelta y a quien revive. Cada maquina coloca el cuerpo sobre el hombro del portador.
##
## Las poses de cargar, soltar y RCP son PROVISIONALES, hechas en codigo (avatar_animator: cargando, cargado,
## rcp); las definitivas se hacen en Blender como el resto de clips.

const RagdollScript := preload("res://scripts/ragdoll.gd")
const TouchIcons := preload("res://scripts/touch_icons.gd")
const VIDA_CUERPO := 30.0        ## s que se puede recoger o revivir a un caido
const DIST := 2.3                ## m para que aparezcan los botones
const REVIVIR_S := 4.5           ## lo que dura la escena de revivir (RCP incluido)

var main: Node = null
var player: Node = null

## clave ("p<peer>" una persona, "b<red_id>" un bot) -> {"t0": instante en que cayo, "equipo": String}
var caidos := {}
## portador (peer id; el jugador local es mi_id()) -> clave que lleva a hombros
var cargas := {}
## la escena de revivir que estoy haciendo yo: clave y tiempo que queda
var _rev_clave := ""
var _rev_t := -1.0
var _rev_total := REVIVIR_S     ## lo que dura MI RCP (menos con la carta RESCATISTA)
var _rcp_dura := {}             ## clave -> lo que dura la RCP que le hacen (llega con "rcp|<s>")
var _escanear_t := 0.0

var _capa: CanvasLayer = null
var _b1: Button = null           ## RECOGER / SOLTAR
var _b2: Button = null           ## REVIVIR
var _pista: Label = null         ## PC: el texto de las teclas


func activo() -> bool:
	# en el duelo SIN REAPARECER por equipos si hay RCP (en el ultimo en pie no hay compañeros)
	# (en el PROP HUNT no hay levantar ni RCP: es de escondite, pedido 2026-10-22)
	if is_inside_tree() and get_tree().get_first_node_in_group("prop_hunt") != null:
		return false
	return main != null and (not bool(main.get("dm_mode")) or (Net.es_dm_elim() and not Net.todos_contra_todos()))


static func mi_id() -> int:
	return Net.multiplayer.get_unique_id() if Net.is_online() else 1


func _ready() -> void:
	add_to_group("rescate")
	_crear_botones()


# --------------------------------------------------------------------------------------------------
# LOS CUERPOS
# --------------------------------------------------------------------------------------------------

func _cuerpo(clave: String) -> Node3D:
	var n := int(clave.substr(1))
	if clave.begins_with("p"):
		var r = Net.remotes.get(n)
		return r if is_instance_valid(r) else null
	for c in get_tree().get_nodes_in_group("corpse"):
		if is_instance_valid(c) and int(c.get_meta("rescate_red_id", -1)) == n:
			return c
	return null


func _avatar(clave: String) -> Node3D:
	var c := _cuerpo(clave)
	if c == null:
		return null
	if "avatar" in c and c.avatar != null and is_instance_valid(c.avatar):
		return c.avatar
	for h in c.get_children():
		if h.has_method("play") and h.has_method("set_body_visible"):
			return h
	return null


func _quitar_ragdoll(clave: String) -> void:
	var c := _cuerpo(clave)
	if c == null:
		return
	if "_ragdoll" in c and c._ragdoll != null and is_instance_valid(c._ragdoll):
		c._ragdoll.queue_free()
		c._ragdoll = null
	if c.has_meta("ragdoll"):
		var rd = c.get_meta("ragdoll")
		if rd != null and is_instance_valid(rd):
			rd.queue_free()
		c.remove_meta("ragdoll")
	if c is RigidBody3D:
		(c as RigidBody3D).freeze = true
	if "rescate_fijo" in c:
		c.rescate_fijo = true


func _poner_ragdoll(clave: String) -> void:
	var c := _cuerpo(clave)
	var av := _avatar(clave)
	if c == null or av == null or not ("skeleton" in av) or av.skeleton == null:
		return
	var rd = RagdollScript.crear(c.get_parent(), av.skeleton, Vector3.ZERO, Vector3.ZERO)
	if rd == null:
		return
	if "_ragdoll" in c:
		c._ragdoll = rd
	else:
		c.set_meta("ragdoll", rd)


## Los compañeros caidos de mi bando que siguen en el suelo (se revisa cada 0,25 s)
func _escanear() -> void:
	var yo := String(player.team) if player and "team" in player else ""
	# EN LOS MODOS ZOMBI TODOS SON DEL MISMO BANDO (2026-09-26): alli el jugador no tiene bando ("") y los bots
	# compañeros son "pve", asi que los botones no salian nunca, ni para personas ni para bots
	var zombis: bool = Settings.modo == "pve"
	var vistos := {}
	for id in Net.remotes.keys():
		var r = Net.remotes[id]
		if is_instance_valid(r) and bool(r.get("dead")) and (zombis or (Net.team_of(int(id)) == yo and yo != "")):
			vistos["p%d" % int(id)] = true
	for c in get_tree().get_nodes_in_group("corpse"):
		if is_instance_valid(c) and c.has_meta("rescate_red_id") and (String(c.get_meta("rescate_team", "")) == yo
				or (zombis and String(c.get_meta("rescate_team", "")) == "pve")):
			vistos["b%d" % int(c.get_meta("rescate_red_id"))] = true
	var ahora := Time.get_ticks_msec() * 0.001
	for k in vistos.keys():
		if not caidos.has(k):
			caidos[k] = {"t0": ahora}
	for k in caidos.keys():
		if not vistos.has(k) and not cargas.values().has(k):
			caidos.erase(k)


func _vigente(clave: String) -> bool:
	# en los modos zombi el cuerpo espera hasta el refugio (alli vuelven todos): sin prisa de 30 s
	return caidos.has(clave) and (Settings.modo == "pve" or Time.get_ticks_msec() * 0.001 - float(caidos[clave]["t0"]) < VIDA_CUERPO)


## El caido de mi bando mas cercano (en el suelo, no cargado por nadie), o ""
func _cercano() -> String:
	var mejor := ""
	var dmin := DIST
	for k in caidos.keys():
		if cargas.values().has(k) or not _vigente(k):
			continue
		var av := _avatar(k)
		if av == null:
			continue
		var d: float = _centro_cuerpo(av).distance_to(player.global_position)
		if d < dmin:
			dmin = d
			mejor = k
	return mejor


func _portador(id: int) -> Node3D:
	if id == mi_id():
		return player
	var r = Net.remotes.get(id)
	return r if is_instance_valid(r) else null


# --------------------------------------------------------------------------------------------------
# LAS ORDENES (llegan igual a todas las maquinas: Net.net_rescate -> aplicar)
# --------------------------------------------------------------------------------------------------

func pedir(accion: String, clave: String, pos: Vector3 = Vector3.ZERO) -> void:
	if Net.is_online():
		Net.net_rescate(accion, mi_id(), clave, pos)
	else:
		aplicar(accion, mi_id(), clave, pos)


const LEVANTAR_S := 1.5
const SOLTAR_S := 0.8
const SOLTAR_SUELTA := 0.45     ## en que momento del gesto de soltar se va el cuerpo al suelo
const LEVANTARSE_S := 2.4       ## rescate_ayudar / rescate_revivido

## portador -> {"fase", "t0", ...} mientras levanta o suelta
var _gesto := {}
var _rescatando := {}     ## clave -> desde cuando le hacen la RCP (hasta que se levanta o se corta)
var _rescatador := {}     ## clave -> peer de quien le hace la RCP (la camara del caido le sigue: player.gd)


func _clip(pt: Node3D, nombre: String, pausado := false) -> void:
	if pt and "avatar" in pt and pt.avatar and pt.avatar.has_method("poner_clip_rescate"):
		pt.avatar.poner_clip_rescate(nombre, pausado)


func _ahora() -> float:
	return Time.get_ticks_msec() * 0.001


func aplicar(accion: String, portador: int, clave: String, pos: Vector3) -> void:
	var pt := _portador(portador)
	# LA CARTA RESCATISTA viaja pegada a la accion: "rcp|<lo que dura>" y "revivido|<vida extra>"
	var dato := 0.0
	if "|" in accion:
		dato = accion.get_slice("|", 1).to_float()
		accion = accion.get_slice("|", 0)
	match accion:
		"coger":
			for p in cargas.keys():
				if cargas[p] == clave:
					return            # ya lo lleva otro
			_quitar_ragdoll(clave)
			cargas[portador] = clave
			var av := _avatar(clave)
			# el gesto va aunque aqui no haya cuerpo que mover (el que cargan soy yo, mirando de espectador):
			# si no, el que me carga se quedaba para siempre en el clip de levantar en mi pantalla
			_gesto[portador] = {"fase": "levantar", "t0": _ahora(), "xf0": av.global_transform if av else Transform3D()}
			if av:
				if av.has_method("pose_rescate"):
					av.pose_rescate("cargado")
			if pt and "avatar" in pt and pt.avatar and "cargando" in pt.avatar:
				pt.avatar.cargando = true
			_clip(pt, "rescate_levantar")
			if pt:
				# BF: agarrarlo del hombro y echarselo encima
				Audio.bf3d("soldado/agarrar_cuerpo", pt.global_position + Vector3(0, 1.2, 0), -2.0, 25.0, Audio.PRI_MID)
				Audio.bf3d("soldado/lucha", pt.global_position + Vector3(0, 1.2, 0), -8.0, 25.0, Audio.PRI_MID)
		"soltar":
			if not cargas.has(portador):
				return
			_gesto[portador] = {"fase": "soltar", "t0": _ahora(), "clave": clave, "pos": pos}
			_clip(pt, "rescate_soltar")
		"rcp":
			_rescatando[clave] = _ahora()
			_rcp_dura[clave] = dato if dato > 0.0 else REVIVIR_S
			_rescatador[clave] = portador
			# el cuerpo, tumbado donde lo espera el clip de levantarse (su primer fotograma), bajo tus manos
			_quitar_ragdoll(clave)
			var av3 := _avatar(clave)
			if av3 and pt:
				var f: Vector3 = -pt.global_transform.basis.z
				f.y = 0.0
				f = f.normalized() if f.length() > 0.1 else Vector3.FORWARD
				var donde: Vector3 = pt.global_position + f * 0.9
				var mira := Basis.looking_at(-f, Vector3.UP)          # su frente hacia el que le reanima
				if not av3.has_meta("rescate_xf0"):
					av3.set_meta("rescate_xf0", av3.transform)
				av3.global_transform = Transform3D(mira.scaled(av3.global_transform.basis.get_scale()), Vector3(donde.x, pt.global_position.y, donde.z))
				if av3.has_method("pose_rescate"):
					av3.pose_rescate("")
				if av3.has_method("poner_clip_rescate") and av3.has_clip("rescate_revivido"):
					av3.poner_clip_rescate("rescate_revivido", true)
				elif av3.has_method("pose_rescate"):
					av3.pose_rescate("tumbado")
			if pt and "avatar" in pt and pt.avatar and "rcp" in pt.avatar:
				pt.avatar.rcp = true
			_clip(pt, "rescate_rcp")
			# BF: quien reanima oye su propio esfuerzo; el reanimado, que le estan trayendo de vuelta
			if portador == mi_id():
				Audio.bucle("reanimando", "soldado/reanimando_bucle", true, -8.0)
			if clave == "p%d" % mi_id():
				Audio.bf2d("yo/me_reaniman", -2.0, Audio.PRI_HIGH)
				Audio.bucle("me_reaniman", "yo/me_reaniman_respira", true, -8.0)
			if pt:
				Audio.bf3d("soldado/jeringa_prepara", pt.global_position + Vector3(0, 0.8, 0), -4.0, 25.0, Audio.PRI_MID)
				Audio.bf3d("gadget/desfib_sacar", pt.global_position + Vector3(0, 0.8, 0), -2.0, 30.0, Audio.PRI_MID)
				Audio.bf3d("gadget/desfib_carga", pt.global_position + Vector3(0, 0.8, 0), -4.0, 30.0, Audio.PRI_MID)
		"rcp_fin":
			var avf := _avatar(clave)
			if avf != null and "ojos_rcp" in avf:
				avf.ojos_rcp = -1.0
				avf.ojos_k = 1.0
			_rescatando.erase(clave)
			_rescatador.erase(clave)
			if portador == mi_id():
				Audio.bucle("reanimando", "", false)
			if clave == "p%d" % mi_id():
				Audio.bucle("me_reaniman", "", false)
			if pt and "avatar" in pt and pt.avatar and "rcp" in pt.avatar:
				pt.avatar.rcp = false
			_clip(pt, "")
		"revivido":
			if pt and "avatar" in pt and pt.avatar and "rcp" in pt.avatar:
				pt.avatar.rcp = false
			_clip(pt, "rescate_ayudar")
			var av4 := _avatar(clave)
			if av4 and "pausa_clip" in av4:
				av4.pausa_clip = false          # se despierta: la mano, sentarse, de pie
			if av4 and av4.has_method("ojos_vivir"):
				av4.ojos_vivir()
			caidos.erase(clave)
			var de_pie: Vector3 = av4.global_position if av4 else pos
			Audio.bf3d("gadget/desfib_descarga", de_pie + Vector3(0, 0.5, 0), 0.0, 40.0, Audio.PRI_HIGH)
			Audio.bf3d("gadget/desfib_revive", de_pie + Vector3(0, 0.5, 0), -2.0, 40.0, Audio.PRI_HIGH)
			Audio.bf3d("soldado/reanimado_fin", de_pie + Vector3(0, 1.0, 0), -4.0, 30.0, Audio.PRI_MID)
			if portador == mi_id():
				Audio.bucle("reanimando", "", false)
			if clave == "p%d" % mi_id():
				Audio.bucle("me_reaniman", "", false)
				Audio.bf2d("yo/reanimado", -2.0, Audio.PRI_HIGH)
				# vuelves mareado unos segundos
				Audio.bucle("mareo", "yo/mareo", true, -12.0)
				get_tree().create_timer(5.0).timeout.connect(func(): Audio.bucle("mareo", "", false))
			get_tree().create_timer(LEVANTARSE_S).timeout.connect(func():
				_clip(_portador(portador), "")
				_revivir(clave, de_pie, dato))


## REVIVIO POR OTRA VIA (reaparicion del modo libre, la oleada, el refugio) mientras lo llevaban o le hacian la
## RCP (2026-09-27): se le quita la postura de rescate y se le olvida. Antes se quedaba tumbado/torcido en las
## pantallas de los demas, moviendose asi, aunque en la suya ya estaba de pie. Lo llama net_player._levantarse.
func olvidar(clave: String) -> void:
	_rescatando.erase(clave)
	_rescatador.erase(clave)
	caidos.erase(clave)
	for k in cargas.keys():
		if cargas[k] == clave:
			cargas.erase(k)
	var av := _avatar(clave)
	if av and av.has_method("poner_clip_rescate"):
		av.poner_clip_rescate("")
	if av and av.has_meta("rescate_xf0"):
		av.transform = av.get_meta("rescate_xf0")
		av.remove_meta("rescate_xf0")
	var c := _cuerpo(clave)
	if c and "rescate_fijo" in c:
		c.rescate_fijo = false


func _revivir(clave: String, pos: Vector3, extra := 0.0) -> void:
	_rescatando.erase(clave)
	_rescatador.erase(clave)
	var n := int(clave.substr(1))
	var av := _avatar(clave)
	if av and av.has_method("poner_clip_rescate"):
		av.poner_clip_rescate("")
	if clave.begins_with("p"):
		Net.dead_players.erase(n)
		if n == mi_id() and player and player.has_method("revivir_aqui"):
			player.revivir_aqui(pos, extra)   # soy yo: vuelvo a la partida donde me han levantado
		var c := _cuerpo(clave)
		if c and "rescate_fijo" in c:
			c.rescate_fijo = false
		if av and av.has_meta("rescate_xf0"):
			av.transform = av.get_meta("rescate_xf0")
			av.remove_meta("rescate_xf0")
	else:
		# un bot no se levanta: el anfitrion crea otro igual donde ha quedado de pie, y el cuerpo se va
		var c2 := _cuerpo(clave)
		var team := String(c2.get_meta("rescate_team", "")) if c2 else ""
		var hueco := int(c2.get_meta("aliado_hueco", -1)) if c2 else -1
		var nombre_bot := String(c2.get_meta("rescate_nombre", "")) if c2 else ""
		if c2:
			c2.queue_free()
		# SIN CUERPO NO HAY A QUIEN REVIVIR: la RCP llego de otra maquina sobre un cuerpo que aqui ya no estaba. Antes salia
		# igual un bot "de nadie" (sin bando), quieto para siempre (bug LAN 2026-10-15)
		if team == "":
			print("[rescate] revivir %s: aqui no hay cuerpo, no se crea nada" % clave)
			return
		if not Net.is_online() or Net.hosting:
			# un COMPAÑERO BOT de los modos zombi: vuelve el mismo (su hueco y su nombre)
			var pv = main.get("pve") if main else null
			if team == "pve" and pv != null and pv.has_method("revivir_aliado"):
				pv.revivir_aliado(hueco, pos)
			elif main and main.has_method("revivir_bot"):
				main.revivir_bot(pos, team, nombre_bot)


## El cuerpo sobre el hombro del portador (su transformada de "cargado")
func _xf_hombro(pt: Node3D, av: Node3D) -> Transform3D:
	var b: Basis = pt.global_transform.basis.orthonormalized()
	var hombro: Vector3 = pt.global_position + Vector3.UP * 1.5 + b.x * -0.16
	var cruzado := Basis(b.x, PI * 0.5) * b
	var origen: Vector3 = hombro - cruzado.y.normalized() * 0.95 + Vector3.DOWN * 0.12
	return Transform3D(cruzado.orthonormalized().scaled(av.global_transform.basis.get_scale()), origen)


func _soltar_ya(portador: int, clave: String, pos: Vector3) -> void:
	cargas.erase(portador)
	# BF: EL CUERPO CONTRA EL SUELO. Si lo sueltas tu, el golpe seco en primera persona
	# (SoldierDown_Foley_OnGround); si lo suelta otro, el de dejarlo caer, donde cae.
	if portador == mi_id():
		Audio.bf2d("yo/soltar_cuerpo", -2.0, Audio.PRI_HIGH)
	else:
		Audio.bf3d("soldado/soltar_cuerpo", pos, -2.0, 30.0, Audio.PRI_MID)
	Audio.bf3d("soldado/cae_suelo", pos, -4.0, 30.0, Audio.PRI_MID)
	var pt2 := _portador(portador)
	if pt2 and "avatar" in pt2 and pt2.avatar and "cargando" in pt2.avatar:
		pt2.avatar.cargando = false
	var av2 := _avatar(clave)
	if av2:
		av2.global_position = pos + Vector3.UP * 0.9
		if av2.has_method("pose_rescate"):
			av2.pose_rescate("")
	_poner_ragdoll(clave)         # cae al suelo con su peso, como se deja caer un cuerpo
	if caidos.has(clave):
		caidos[clave]["t0"] = maxf(float(caidos[clave]["t0"]), _ahora() - VIDA_CUERPO + 10.0)
	get_tree().create_timer(SOLTAR_S - SOLTAR_SUELTA).timeout.connect(func(): _clip(_portador(portador), ""))


# --------------------------------------------------------------------------------------------------
# CADA CUADRO
# --------------------------------------------------------------------------------------------------

func _process(dt: float) -> void:
	var _pf0 := Time.get_ticks_usec()
	_process_sin_medir(dt)
	Prof.add("rescate", Time.get_ticks_usec() - _pf0)


func _process_sin_medir(dt: float) -> void:
	if not activo() or player == null or not is_instance_valid(player):
		return
	# CON UN COMPAÑERO A HOMBROS: su respiracion de herido (SoldierDown_BreathMale de BF), bajita andando
	# y algo mas fuerte corriendo, que es cuando mas se le zarandea
	var llevo := cargando() and not bool(player.get("spectating"))
	Audio.bucle("cargado", "yo/derribado_respira", llevo, -14.0 if bool(player.get("sprinting")) else -20.0)
	_sonido_caido()
	_escanear_t -= dt
	if _escanear_t <= 0.0:
		_escanear_t = 0.25
		_escanear()
	# LOS OJOS DEL QUE REVIVEN (avatar_animator.ojos_rcp): cuanto lleva su RCP; al final empieza a abrirlos
	for c in _rescatando.keys():
		var avr := _avatar(String(c))
		if avr != null and "ojos_rcp" in avr:
			avr.ojos_rcp = clampf((_ahora() - float(_rescatando[c])) / maxf(float(_rcp_dura.get(c, REVIVIR_S)), 0.1), 0.0, 1.0)
	# los cuerpos cargados, sobre el hombro de su portador (en todas las maquinas)
	for p in cargas.keys():
		var pt := _portador(int(p))
		var av := _avatar(String(cargas[p]))
		if pt == null:
			continue
		var g: Dictionary = _gesto.get(p, {})
		var fase := String(g.get("fase", ""))
		if av == null:
			# sin cuerpo que colocar: solo los tiempos del gesto
			if fase == "levantar" and _ahora() - float(g["t0"]) >= LEVANTAR_S:
				_gesto.erase(p)
				_clip(pt, "rescate_cargar")
			elif fase == "soltar" and _ahora() - float(g["t0"]) >= SOLTAR_SUELTA:
				_gesto.erase(p)
				_soltar_ya(int(p), String(g["clave"]), g["pos"])
			continue
		var xf := _xf_hombro(pt, av)
		if fase == "levantar":
			# sube del suelo al hombro al ritmo del gesto: se queda en el suelo mientras te agachas y te lo subes
			var t: float = _ahora() - float(g["t0"])
			# EL CUERPO SUBE AL DOBLE DE RAPIDO (pedido): del 30 al 62 % del gesto -antes del 35 al 100 %-, o sea en
			# cuanto las manos lo cogen, y luego ya va en el hombro mientras te enderezas
			var k: float = smoothstep(0.30, 0.62, clampf(t / LEVANTAR_S, 0.0, 1.0))
			var x0: Transform3D = g["xf0"]
			var esc: Vector3 = av.global_transform.basis.get_scale()
			var bas: Basis = x0.basis.orthonormalized().slerp(xf.basis.orthonormalized(), k)
			xf = Transform3D(bas.scaled(esc), x0.origin.lerp(xf.origin, k))
			if t >= LEVANTAR_S:
				_gesto.erase(p)
				_clip(pt, "rescate_cargar")
		elif fase == "soltar":
			if _ahora() - float(g["t0"]) >= SOLTAR_SUELTA:
				_gesto.erase(p)
				_soltar_ya(int(p), String(g["clave"]), g["pos"])
				continue
		av.global_transform = xf
		if av.has_method("refrescar_pose_rescate"):
			av.refrescar_pose_rescate()
	_escena_revivir(dt)
	_ui()


func _escena_revivir(dt: float) -> void:
	if _rev_t < 0.0:
		return
	_rev_t -= dt
	var av := _avatar(_rev_clave)
	if av == null or player.global_position.distance_to(av.global_position) > DIST + 1.0 or float(player.health) <= 0.0:
		if "--rescatetest" in OS.get_cmdline_user_args():
			print("[rescate] RCP cortada: cuerpo %s · distancia %.2f · vida %.0f" % [str(av != null), player.global_position.distance_to(av.global_position) if av else -1.0, float(player.health)])
		pedir("rcp_fin", _rev_clave)          # se ha ido o le han dado: se corta
		_rev_t = -1.0
		_rev_clave = ""
		if player.get("hud"):
			player.hud.show_action("", 0.0)
		return
	if player.get("hud"):
		player.hud.show_action("REVIVIENDO...", 1.0 - _rev_t / _rev_total)
	if _rev_t <= 0.0:
		var extra: float = float(player.call("carta_rescatista")) if player.has_method("carta_rescatista") else 0.0
		pedir("revivido|%.3f" % extra if extra > 0.0 else "revivido", _rev_clave, av.global_position)
		_rev_t = -1.0
		_rev_clave = ""
		if player.get("hud"):
			player.hud.show_action("", 0.0)


## Lo que puedo hacer ahora: ["soltar"], ["recoger", "revivir"] o []
func opciones() -> Array:
	if not activo() or player == null or float(player.health) <= 0.0 or bool(player.get("spectating")):
		return []
	if cargas.has(mi_id()):
		return ["soltar"]
	if _rev_t >= 0.0:
		return []
	return ["recoger", "revivir"] if _cercano() != "" else []


## Tecla E / boton 1. Devuelve true si ha hecho algo (para cortar la cadena de interact del jugador).
func usar_recoger() -> bool:
	var op := opciones()
	if op.has("soltar"):
		var delante: Vector3 = player.global_position - player.global_transform.basis.z * 0.9
		pedir("soltar", String(cargas[mi_id()]), delante)
		return true
	if op.has("recoger"):
		pedir("coger", _cercano())
		return true
	return false


## Tecla F / boton 2
func usar_revivir() -> bool:
	if not opciones().has("revivir"):
		return false
	_rev_clave = _cercano()
	# RESCATISTA (cartas.gd): la RCP dura menos
	var rapidez: float = float(player.call("carta_rescatista")) if player.has_method("carta_rescatista") else 0.0
	_rev_total = REVIVIR_S / (1.0 + maxf(rapidez, 0.0))
	_rev_t = _rev_total
	var av := _avatar(_rev_clave)
	pedir("rcp|%.3f" % _rev_total if rapidez > 0.0 else "rcp", _rev_clave, av.global_position if av else player.global_position)
	return true


func cargando() -> bool:
	return cargas.has(mi_id())


## TE ESTAN REVIVIENDO (2026-09-27, pedido): el que esta muerto mirando ve una barra con el progreso de la RCP
## que le hace un compañero, para enterarse de que le estan levantando.
var _rcp_panel: Control = null
var _rcp_barra: ColorRect = null

func _barra_rcp_propia() -> void:
	var clave := "p%d" % mi_id()
	var mirando: bool = player != null and bool(player.get("spectating"))
	var activo: bool = mirando and _rescatando.has(clave)
	if not activo:
		if _rcp_panel:
			_rcp_panel.visible = false
		return
	if _rcp_panel == null and _capa:
		_rcp_panel = Control.new()
		_rcp_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rcp_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_rcp_panel.custom_minimum_size = Vector2(360, 52)
		_rcp_panel.position = Vector2(-180, -170)
		var fondo := ColorRect.new()
		fondo.color = Color(0, 0, 0, 0.55)
		fondo.size = Vector2(360, 14)
		fondo.position = Vector2(0, 34)
		_rcp_panel.add_child(fondo)
		_rcp_barra = ColorRect.new()
		_rcp_barra.color = Color(0.35, 0.9, 0.45)
		_rcp_barra.size = Vector2(0, 14)
		_rcp_barra.position = Vector2(0, 34)
		_rcp_panel.add_child(_rcp_barra)
		var t := Label.new()
		t.text = "TE ESTÁN REVIVIENDO"
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.size = Vector2(360, 30)
		t.add_theme_font_size_override("font_size", 22)
		t.add_theme_color_override("font_outline_color", Color.BLACK)
		t.add_theme_constant_override("outline_size", 6)
		_rcp_panel.add_child(t)
		_capa.add_child(_rcp_panel)
	if _rcp_panel:
		_rcp_panel.visible = true
		var k: float = clampf((_ahora() - float(_rescatando[clave])) / float(_rcp_dura.get(clave, REVIVIR_S)), 0.0, 1.0)
		_rcp_barra.size.x = 360.0 * k


func _ui() -> void:
	_barra_rcp_propia()
	var op := opciones()
	if _b1 == null:
		return
	_b1.visible = not op.is_empty() and _rev_t < 0.0
	_b1.icon = TouchIcons.get_icon("rescate_soltar" if op.has("soltar") else "rescate_cargar")
	_b2.visible = op.has("revivir") and _rev_t < 0.0
	# ENCIMA DEL CUERPO, siguiendolo (pedido): se proyecta a la pantalla el punto sobre el caido; cargandolo, sobre
	# ti mismo. Si queda detras de la camara, abajo en el centro.
	var vp := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_3d()
	var sobre: Vector3 = player.global_position + Vector3.UP * 2.1
	if not op.has("soltar"):
		var av := _avatar(_cercano())
		if av:
			sobre = _centro_cuerpo(av)
	var centro := Vector2(vp.x * 0.5, vp.y * 0.72)
	if cam and not cam.is_position_behind(sobre):
		centro = cam.unproject_position(sobre)
	var ancho: float = 84.0 if not _b2.visible else 84.0 * 2.0 + 12.0
	var x0: float = clampf(centro.x - ancho * 0.5, 8.0, vp.x - ancho - 8.0)
	var y0: float = clampf(centro.y - 42.0, 8.0, vp.y - 92.0)     # centrados EN el cuerpo, no encima
	_b1.position = Vector2(x0, y0)
	_b2.position = Vector2(x0 + 96.0, y0)


var _ui_tenia := false


## DOS BOTONES CUADRADOS CON DIBUJO (pedido: sin texto y sin redondear). En el movil se pulsan; en el PC son el
## aviso de que hay algo que hacer, con la tecla en una esquina.
## Donde esta el cuerpo DE VERDAD: la cadera del esqueleto (tumbado, el ragdoll la lleva lejos del origen del
## muñeco, que se queda donde estaba de pie).
func _centro_cuerpo(av: Node3D) -> Vector3:
	if "skeleton" in av and av.skeleton != null:
		var sk: Skeleton3D = av.skeleton
		var i := sk.find_bone("pelvis")
		if i >= 0:
			return sk.global_transform * sk.get_bone_global_pose(i).origin
	return av.global_position + Vector3.UP * 0.3


func _crear_botones() -> void:
	_capa = CanvasLayer.new()
	_capa.layer = 20
	add_child(_capa)
	var tactil := Settings.is_touch()
	for i in 2:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_STOP if tactil else Control.MOUSE_FILTER_IGNORE
		b.custom_minimum_size = Vector2(84, 84)
		b.size = Vector2(84, 84)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_constant_override("icon_max_width", 60)
		var col := Color(0.45, 1.0, 0.55) if i == 1 else Color(1.0, 0.83, 0.0)
		b.add_theme_color_override("icon_normal_color", col)
		b.add_theme_color_override("icon_pressed_color", Color.WHITE)
		b.add_theme_color_override("icon_hover_color", col)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.055, 0.07, 0.72)
		sb.border_color = Color(col.r, col.g, col.b, 0.9)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(0)
		sb.set_content_margin_all(10)
		for st in ["normal", "hover", "focus", "pressed"]:
			b.add_theme_stylebox_override(st, sb)
		b.icon = TouchIcons.get_icon("rescate_revivir" if i == 1 else "rescate_cargar")
		b.visible = false
		# (SIN LETRAS DE TECLAS (2026-10-04, pedido: "el juego es para el movil: ninguna letra de W A S D ni apretar E, el simbolo"): el boton ya lleva su icono; sin la E / F de la esquina)
		_capa.add_child(b)
		preload("res://scripts/teclas_pc.gd").marca(b, "E" if i == 0 else "F")      # en el PC, su tecla
		if i == 0:
			b.pressed.connect(func(): usar_recoger())
			_b1 = b
		else:
			b.pressed.connect(func(): usar_revivir())
			_b2 = b


## ¿Me estan rescatando ahora mismo? (a hombros o en plena RCP): el reloj de reaparecer del atraco espera
## CAIDO ESPERANDO RESCATE (BF, SoldierDown): al caer, el golpe contra el suelo y la respiracion; mientras
## esperas, el zumbido sordo con el monitor cardiaco; si te llevan a hombros, el roce del cuerpo arrastrado.
var _caido_antes := false
func _sonido_caido() -> void:
	var yo := "p%d" % mi_id()
	var caido: bool = _vigente(yo) and bool(player.get("spectating"))
	if caido and not _caido_antes:
		Audio.bf2d("yo/caido_suelo", -4.0, Audio.PRI_HIGH)
		Audio.bf2d("yo/respira_caido", -6.0, Audio.PRI_MID)
	_caido_antes = caido
	var esperando: bool = caido and not _rescatando.has(yo)
	Audio.bucle("caido", "yo/caido_zumbido", esperando, -14.0)
	Audio.bucle("ekg", "yo/ekg", esperando, -16.0)
	Audio.bucle("arrastre", "yo/caido_arrastre", caido and cargas.values().has(yo), -10.0)


func me_rescatan() -> bool:
	var yo := "p%d" % mi_id()
	return cargas.values().has(yo) or _rescatando.has(yo)


## QUIEN me lleva a hombros o me hace la RCP ahora mismo (null si nadie): la camara del caido le sigue (player.gd).
func quien_me_rescata() -> Node3D:
	var yo := "p%d" % mi_id()
	for p in cargas.keys():
		if cargas[p] == yo:
			return _portador(int(p))
	if _rescatando.has(yo) and _rescatador.has(yo):
		return _portador(int(_rescatador[yo]))
	return null


## ¿Me llevan a hombros? (la camara va entonces encima del que me lleva: mi cuerpo va con el)
func me_cargan() -> bool:
	return cargas.values().has("p%d" % mi_id())
