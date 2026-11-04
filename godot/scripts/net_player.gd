extends CharacterBody3D
const RagdollScript := preload("res://scripts/ragdoll.gd")   # cargado siempre: con load() se recompilaba al morir
## El minimapa, para poder marcar los disparos. Por preload y no por nombre de clase: los nombres
## globales viven en una cache que hay que reconstruir, y un preload no depende de eso.
const MinimapCls := preload("res://scripts/minimap.gd")
## Un jugador REMOTO dentro de la partida: el avatar de otra persona de la sala.
##
## No simula nada. Recibe paquetes de estado (posición, giro, velocidad, agachado…) y los interpola
## para que se vea fluido aunque lleguen a 20 Hz. Lleva colisión para que las balas de este equipo le
## acierten; el daño no se aplica aquí, se le manda a su dueño (él es la autoridad de su vida).

const AvatarScript := preload("res://scripts/avatar_animator.gd")

## INVISIBLE (su habilidad, por Net.net_habilidad): los bots del anfitrion no le buscan
var invisible := false
var peer_id := 0
var player_name := ""
var avatar: Node3D
var tag: Label3D

## objetivo que llega por red; la posición real persigue a este objetivo
var target_pos := Vector3.ZERO
var target_yaw := 0.0
var target_pitch := 0.0
var net_vel := Vector3.ZERO
var crouching := false
var on_floor := true
var dead := false
var _avatar_xf0 := Transform3D.IDENTITY     ## la transformada de reposo del muñeco (la que tiene al crearlo)
var _avatar_xf0_ok := false
var rescate_fijo := false   ## lo coloca rescate.gd (cargado a hombros o en plena RCP)
var _caido_prev := false
var _trepa_prev := false
var _arma_vista := ""                ## el arma que le vimos la ultima vez (para el gesto de cambio)
## Lo que tarda la subida en player.gd (TREPA_DUR entre TREPA_VELOCIDAD). Aqui basta con que dure lo
## mismo: el sitio ya viene en el propio estado, cuadro a cuadro. Si no se escala igual que alla, el
## compañero trepa a camara lenta mientras tu ya estas arriba.
const TREPA_DUR_RED := 0.475
var shots_seen := 0        ## diagnóstico: disparos suyos que he visto

const LERP_POS := 14.0
const LERP_ROT := 12.0


func setup(id: int, pname: String, tint: Color) -> void:
	peer_id = id
	player_name = pname
	collision_layer = 4          # capa de "enemigos": las balas del jugador ya la miran
	collision_mask = 1           # sólo contra el mundo
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	# LA MISMA ALTURA QUE TODOS. Se quedo en 1,70 cuando el soldado paso a medir 1,60: la capsula
	# sobresalia 10 cm por encima de la cabeza, asi que en LAN se podia acertar por encima del pelo.
	# Y ahora ademas tiene que cuadrar con la capsula que usa el SERVIDOR para rebobinar (net.gd).
	cap.radius = Net.CAPSULA_RADIO
	cap.height = Net.CAPSULA_ALTO
	shape.shape = cap
	shape.position.y = Net.CAPSULA_ALTO * 0.5
	add_child(shape)

	# LA CABEZA, APARTE. La capsula es un cilindro alrededor del eje del cuerpo, y la cabeza de un
	# muñeco agachado, inclinado o trepando NO esta en ese eje: de cerca apuntabas a la cara y la bala
	# pasaba por al lado (o habia que tirar por encima). Esta bola va pegada al hueso de la cabeza
	# cuadro a cuadro, asi que dispararle a la cara es darle a la cara.
	_cabeza_col = CollisionShape3D.new()
	var bola := SphereShape3D.new()
	bola.radius = 0.17
	_cabeza_col.shape = bola
	_cabeza_col.position = Vector3(0, Net.CAPSULA_ALTO - 0.12, 0)
	add_child(_cabeza_col)

	avatar = AvatarScript.new()
	add_child(avatar)
	avatar.build(AvatarScript.ALTURA, false, tint, false)
	avatar.play("idle_1")
	_avatar_xf0 = avatar.transform
	_avatar_xf0_ok = true

	tag = Label3D.new()
	tag.text = pname
	tag.font_size = 44
	tag.pixel_size = 0.0022
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = false
	tag.modulate = Color(1.0, 0.86, 0.35)
	tag.outline_size = 12
	tag.position = Vector3(0, 2.05, 0)
	add_child(tag)
	target_pos = global_position
	_refresh_collision()


## Un companero no te estorba el paso: se le quita la colision para que puedas atravesarlo. Los
## rivales siguen siendo solidos (y siguen recibiendo balas).
func _refresh_collision() -> void:
	var friendly := is_friendly()
	# el nombre de un compañero lo pinta etiquetas_equipo.gd (con su vida y a traves de las paredes)
	# (2026-10-18, pedido: "el nombre encima de un rival delata su posicion"): el de un RIVAL tampoco se ve
	if tag and is_instance_valid(tag):
		tag.visible = false
	collision_layer = 0 if friendly else 4
	for c in get_children():
		if c is CollisionShape3D:
			c.disabled = friendly


func apply_state(pos: Vector3, yaw: float, pitch: float, vel: Vector3, crouch: bool, floored: bool, is_dead: bool, is_reloading: bool, is_aiming: bool = false, is_caido: bool = false, is_trepando: bool = false, trepa_reloj: float = -1.0) -> void:
	# UN MUERTO SE QUEDA DONDE CAYO.
	#
	# Lo conto el usuario: "en modo zombi, mate a un compañero, me estaba espectando, y su avatar
	# aparecio". Y es literal: al morir se pasa a mirar desde un compañero, y la camara de espectador
	# NO mueve solo la camara, mueve EL CUERPO del jugador (`player.gd::_update_spectate`: pone
	# `global_position` detras y encima de a quien mira). Ese cuerpo sigue mandando su sitio, asi que
	# en la pantalla de los demas el cadaver del compañero se levantaba del suelo y se te pegaba a la
	# espalda, siguiendote a todos lados. De ahi el "aparece un soldado donde mate al zombi": no era
	# un soldado nuevo, era el compañero muerto viniendo a mirar.
	#
	# Se corta aqui y no en el emisor a proposito: la posicion de un muerto no le sirve a nadie mas,
	# y asi vale para cualquier motivo por el que un muerto se mueva (espectar, la camara del podio,
	# lo que venga). Al revivir, `is_dead` vuelve a false y las posturas siguen entrando.
	if dead and is_dead:
		return
	# Y TAMPOCO EL PRIMER PAQUETE DE MUERTO: ese ya sale con la posicion de su camara de espectador (muere y en
	# el mismo cuadro pasa a mirar), asi que el cadaver saltaba alli y no habia forma de recogerlo donde cayo.
	# Medido con --rescatelan: el cuerpo a 20-30 m de donde murio. Se queda con la ultima postura en vida.
	if not is_dead:
		target_pos = pos
	target_yaw = yaw
	target_pitch = pitch
	net_vel = vel
	crouching = crouch
	on_floor = floored
	# la recarga y el apuntado son poses de sujecion del avatar: con el bool basta, no hace falta
	# otro RPC. El apuntado ademas cierra el ojo, asi que en LAN se ve el gesto completo.
	if avatar:
		avatar.reloading = is_reloading
		avatar.aiming = is_aiming
		# derribado por una explosion: la caida se arranca UNA vez, al empezar
		if is_caido and not _caido_prev and not is_dead and avatar.has_method("caer"):
			avatar.caer()
		# SUBIENDO A UN BORDE: igual que la caida, se arranca UNA vez, al empezar. Sin esto, en LAN
		# el companero subia una pared deslizandose de pie, sin mover un brazo.
		# Con la subida de Blender llega ademas EN QUE SEGUNDO DEL CLIP va (en un muro bajo no empieza en
		# cero): se arranca desde ahi y dura lo que le queda. Y se corta cuando el deja de subir.
		if is_trepando and not _trepa_prev and not is_dead and avatar.has_method("trepar"):
			if trepa_reloj >= 0.0 and avatar.has_method("clip_dur"):
				avatar.trepar(maxf((avatar.clip_dur("trepar") - trepa_reloj) * 0.5, 0.1), trepa_reloj)
			else:
				avatar.trepar(TREPA_DUR_RED)
		elif not is_trepando and _trepa_prev and avatar.has_method("fin_trepar"):
			avatar.fin_trepar()
	_caido_prev = is_caido
	_trepa_prev = is_trepando
	if is_dead != dead:
		dead = is_dead
		if dead:
			_morir_con_ragdoll()
		else:
			_levantarse()


## EL ASPECTO DE ESTE JUGADOR: su avatar y sus accesorios. Rehacer el muneco no es gratis (hay que
## hornear su malla), asi que solo se hace cuando de verdad cambia algo.
var _aspecto_actual := ""

func aspecto(skin: String, accs: String) -> void:
	var clave := skin + "|" + accs
	if clave == _aspecto_actual or avatar == null:
		return
	_aspecto_actual = clave
	var L := preload("res://scripts/lobby.gd")
	var lista: Array = []
	for a in accs.split(";", false):
		lista.append(String(a))
	var receta := L.receta_por_nombre(skin, lista)
	var id_skin := L.id_por_nombre(skin, lista)
	var acab := L.acabado_por_nombre(skin)
	# el arma se la devuelve el propio build (se apunta lo que llevaba antes de reconstruirse)
	avatar.build(AvatarScript.ALTURA, false, Color.WHITE, false, false, id_skin, receta)
	if avatar.has_method("aplicar_acabado"):
		avatar.aplicar_acabado(acab.x, acab.y)


## El arma del companero: el TIPO dice como la sujeta y el ID cual es (res://armas/<id>.glb, con su
## mira ya soldada). Con esos dos datos la ve exactamente igual que su dueño.
func equip(kind: String, arma_id: String = "", skin: String = "") -> void:
	if avatar == null or not avatar.has_method("equip_weapon"):
		return
	# EL GESTO DE CAMBIAR DE ARMA. El equipo viaja cada dos segundos aunque no cambie nada, asi que
	# el gesto solo se hace cuando el arma es DISTINTA de la que llevaba: si no, el companero estaria
	# guardandose y sacando el fusil cada dos segundos para siempre.
	var nuevo := "%s|%s" % [kind, arma_id]
	if nuevo != _arma_vista and _arma_vista != "" and avatar.has_method("hold_swap"):
		avatar.hold_swap(0.35)
	_arma_vista = nuevo
	avatar.equip_weapon(kind, arma_id)
	# LA SKIN ES LA SUYA, NO LA MIA. El modelo de arma, si se le deja, mira la skin que TU llevas
	# equipada (`SkinsArmas.equipada`), asi que todos saldrian pintados como tu. Va forzada.
	var wm = avatar._wm if ("_wm" in avatar) else null
	if wm != null and is_instance_valid(wm) and String(wm.skin_forzada) != skin:
		wm.skin_forzada = skin
		wm.repintar_skin()


## Ha disparado: fogonazo, retroceso del avatar y sonido posicional. Lo dispara un RPC de su dueño.
var _arma_ultima := ""      ## con que dispara (para como suenan sus balas al pasarte: Audio.bullet_whiz)

func play_shot(sound: String) -> void:
	# "familia@arma" (player.gd): el arma concreta decide el sonido del disparo (Audio.PERFIL_ARMA)
	var arma_disparo := ""
	if sound.contains("@"):
		arma_disparo = sound.get_slice("@", 1)
		sound = sound.get_slice("@", 0)
	_arma_ultima = arma_disparo if arma_disparo != "" else sound
	# LE HAN DADO EN EL ESCUDO: no es un disparo suyo. El brazo encaja el golpe y suena el metal.
	if sound == "escudo_golpe":
		if avatar and avatar.has_method("escudo_golpe"):
			avatar.escudo_golpe()
		Audio.play3d("metal/hit-m", global_position + Vector3(0.0, 1.25, 0.0), 0.0, 0.12, 50.0, Audio.PRI_MID)
		return
	MinimapCls.marcar_disparo(global_position, Net.team_of(peer_id))
	shots_seen += 1
	# MAZO: no es un disparo, es un mazazo. Ni fogonazo ni sonido de polvora.
	if sound == "sledge":
		if avatar and avatar.has_method("play_swing"):
			avatar.play_swing(AvatarScript.swing_dur_s)
		Audio.bf3d("soldado/mazo_swing", global_position + Vector3(0, 1.4, 0), -4.0, 25.0, Audio.PRI_MID)
		return
	# EL MAZAZO HA ACERTADO. Llega aparte porque su dueno no lo sabe hasta el instante del impacto,
	# ya empezado el gesto. Sin este aviso el mazo se veria pasar de largo aunque reventara la pared.
	# se esta limpiando la tierra de la cara (no es un disparo, viene por el mismo aviso)
	if sound == "limpiar":
		if avatar and avatar.has_method("play_limpiar"):
			avatar.play_limpiar(1.05)
		return
	# se esta vendando el brazo (el boton de curar de la campana)
	if sound.begins_with("vendar:"):
		if avatar and avatar.has_method("play_vendar"):
			avatar.play_vendar(float(sound.substr(7)))
		return
	if sound == "vendar_fin":
		if avatar and avatar.has_method("parar_vendar"):
			avatar.parar_vendar()
		return
	if sound == "sledgehit":
		if avatar and avatar.has_method("swing_result"):
			avatar.swing_result(true)
		Audio.bf3d("soldado/mazo_golpe", global_position + Vector3(0, 1.2, 0), 0.0, 40.0, Audio.PRI_HIGH)
		return
	# GRANADA: el brazo va arriba y suelta. No hay clip propio de lanzamiento, asi que se usa el
	# mismo gesto del mazo, corto: por fuera se lee como el tiron del brazo al tirarla.
	if sound == "granada":
		if avatar and avatar.has_method("lanzar_granada"):
			avatar.lanzar_granada()
		return
	if avatar:
		if avatar.has_method("kick"):
			avatar.kick()
		if avatar._wm and avatar._wm.has_method("fire_flash"):
			avatar._wm.fire_flash(true)
	Audio.gunshot(sound, global_position, false, arma_disparo)
	# el tiro de un compañero tambien despierta a los dormidos de la campaña (en el anfitrion, que los lleva)
	get_tree().call_group("enemies", "hear_noise", global_position, 14.0 if sound == "silenced" else 50.0)
	_disparo_visible()


## LO QUE SE VE CUANDO DISPARA OTRO JUGADOR: la traza de la bala saliendo del canon, el humillo del
## orificio y, si te pasa rozando, el aire rasgandose junto a la oreja.
## El disparo llega por red solo con el sonido, asi que el recorrido se reconstruye aqui: sale de la
## boca del arma de su avatar y va hacia donde mira (su guinada y su cabeceo, que si viajan).
func _disparo_visible() -> void:
	if avatar == null or avatar._wm == null or not is_instance_valid(avatar._wm):
		return
	var jug = Net.game.player if (Net.game != null and "player" in Net.game) else null
	var fx = jug.effects if (jug != null and is_instance_valid(jug) and "effects" in jug) else null
	var wm = avatar._wm
	var boca: Vector3 = wm.global_transform * wm.muzzle_pos
	var fwd: Vector3 = (Quaternion(Vector3.UP, rotation.y) * Quaternion(Vector3.RIGHT, target_pitch)) * Vector3.FORWARD
	var largo := 60.0
	# CONTRA LOS VOXELS, NO CONTRA JOLT: esto llega por red, fuera del paso de fisica, y con la fisica en su
	# propio hilo (project.godot, run_on_separate_thread) el espacio de Jolt no se puede consultar desde aqui
	var mundo = Net.game.world if (Net.game != null and "world" in Net.game) else null
	if mundo != null and mundo.has_method("raycast"):
		var h: Dictionary = mundo.raycast(boca, fwd, largo)
		if bool(h.get("hit", false)):
			largo = float(h.get("distance", largo))
	if fx != null:
		fx.tracer(boca + fwd * 0.30, boca + fwd * largo)
		fx.muzzle_smoke(boca, fwd, 0.55)
		fx.shell_ajena(wm, fwd)
	# la bala rozandote: se mide el punto del recorrido mas cercano a tu cabeza
	if jug != null and is_instance_valid(jug):
		var oreja: Vector3 = jug.global_position + Vector3(0.0, 1.55, 0.0)
		var t: float = clampf((oreja - boca).dot(fwd), 0.0, largo)
		if t >= 1.0:
			var cerca: Vector3 = boca + fwd * t
			var d: float = cerca.distance_to(oreja)
			if d < Audio.WHIZ_DIST:
				Audio.bullet_whiz(cerca, d, _arma_ultima, boca.distance_to(oreja))


## ¿lleva arma en las manos? (para el diagnóstico de red)
func has_weapon() -> bool:
	return avatar != null and avatar.weapon_root != null and is_instance_valid(avatar.weapon_root)


## RESPIRAR CON FRIO. El aliento del de enfrente es el que de verdad se ve: el tuyo lo tienes
## pegado a la cara. Cuesta un temporizador por cuerpo y una llamada cada tres segundos largos.
var _vaho_t := 0.0

func _update_vaho(dt: float) -> void:
	var mn := get_parent()
	if mn == null or not ("_nieve" in mn):
		return
	var frio: float = float(mn._nieve)
	if frio <= 0.06:
		return
	var fx = mn.effects if ("effects" in mn) else null
	if fx == null or not fx.has_method("vaho"):
		return
	_vaho_t -= dt
	if _vaho_t > 0.0:
		return
	_vaho_t = randf_range(2.9, 4.3)
	var dir: Vector3 = -global_transform.basis.z
	fx.vaho(global_position + Vector3(0, 1.52, 0) + dir * 0.22, dir, frio)


## LA CAPSULA SIGUE AL MUÑECO. Era fija -1,70 m siempre- y el cuerpo de verdad cambia de alto: al
## agacharse, al trepar, al caer. Resultado: para darle en la cara habia que apuntar POR ENCIMA de su
## cabeza, porque ahi seguia estando la parte alta de la capsula. Ahora se mide donde tiene la cabeza
## el avatar en este momento y la capsula se ajusta a eso.
var _cabeza_col: CollisionShape3D = null

func _ajustar_capsula() -> void:
	if avatar == null or avatar.skeleton == null or not avatar.bone_idx.has("head"):
		return
	# la bola de la cabeza, donde este la cabeza ahora mismo (un poco por delante del hueso, que esta
	# en la nuca; el craneo va hacia donde mira)
	if is_instance_valid(_cabeza_col):
		var xf: Transform3D = avatar.skeleton.global_transform 			* avatar.skeleton.get_bone_global_pose(avatar.bone_idx["head"])
		_cabeza_col.global_position = xf.origin + (global_transform.basis.z * -0.04) + Vector3(0, 0.10, 0)
	var cabeza: float = (avatar.skeleton.global_transform
		* avatar.skeleton.get_bone_global_pose(avatar.bone_idx["head"])).origin.y - global_position.y
	# del hueso de la cabeza a la coronilla hay un palmo largo; por debajo de 0,9 m no se encoge mas
	var alto: float = clampf(cabeza + 0.28, 0.9, 2.1)
	for c in get_children():
		if not (c is CollisionShape3D):
			continue
		var cap := (c as CollisionShape3D).shape as CapsuleShape3D
		if cap == null:
			continue
		cap.height = alto
		(c as CollisionShape3D).position.y = alto * 0.5


## A que altura tiene la cabeza AHORA (metros sobre sus pies). La usa quien dispara para saber si el
## tiro fue a la cabeza, en vez de dar por hecho que esta a 1,45 m.
func altura_cabeza() -> float:
	if avatar and avatar.skeleton and avatar.bone_idx.has("head"):
		return (avatar.skeleton.global_transform
			* avatar.skeleton.get_bone_global_pose(avatar.bone_idx["head"])).origin.y - global_position.y
	return 1.45


var _y_prev := 0.0
var _vy_suave := 0.0


func _physics_process(dt: float) -> void:
	_update_vaho(dt)
	_ajustar_capsula()
	if Engine.get_physics_frames() % 30 == 0:
		_refresh_collision()   # el bando puede llegar despues que el avatar
	if dead:
		if rescate_fijo:
			return          # lo lleva alguien a hombros o lo estan reanimando: lo coloca rescate.gd
		# con ragdoll, cae la fisica y el nodo no pinta nada; sin el (plan B), cae el nodo entero
		if not is_instance_valid(_ragdoll):
			_caer_cadaver(dt)
		return
	# suavizado: a 20 Hz los saltos entre paquetes se notarían como teletransportes
	global_position = global_position.lerp(target_pos, clampf(LERP_POS * dt, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(LERP_ROT * dt, 0.0, 1.0))
	if avatar:
		avatar.look_pitch = target_pitch
	if _linterna != null:
		_linterna.rotation.x = target_pitch
		if _linterna.visible:
			_linterna_t -= dt
			if _linterna_t <= 0.0:
				_linterna_t = LinternaCorte.CADA_S
				LinternaCorte.ajustar(_linterna, Net.game.world if Net.game != null and "world" in Net.game else null, 28.0)
	# la animación se saca de la velocidad que nos manda su dueño, igual que en local.
	# (2026-09-27) ESTO ESTABA DENTRO DEL `if _linterna`: un compañero solo movia las piernas si alguna vez
	# habia encendido la linterna; si no, se deslizaba tieso, sin andar, saltar ni agacharse. Y la velocidad
	# iba en ejes del MUNDO: el animador la quiere relativa al cuerpo, asi que de lado o hacia atras ponia
	# siempre el clip de andar hacia delante.
	if avatar:
		var lv: Vector3 = global_transform.basis.inverse() * Vector3(net_vel.x, 0.0, net_vel.z)
		# LA ESCALERA DEL COMPAÑERO: sube o baja pisando y andando de frente (su maquina no manda el estado:
		# se saca de cuanto cambia su altura, suavizado para que un peldaño suelto no cuente)
		var vy := (global_position.y - _y_prev) / maxf(dt, 0.001)
		_y_prev = global_position.y
		_vy_suave = lerpf(_vy_suave, vy, clampf(6.0 * dt, 0.0, 1.0))
		var hs := Vector2(net_vel.x, net_vel.z).length()
		avatar.escalera = 0 if (not on_floor or hs < 0.5 or absf(_vy_suave) < 0.4 * hs) else (1 if _vy_suave > 0.0 else -1)
		avatar.drive_locomotion(lv, crouching, on_floor, 0, dt)
		# SOLO ENCARANDO. Esto se llamaba en CADA frame, asi que al compañero nunca le corria el reloj
		# de "tiempo sin disparar": ni bajaba el arma al andar ni se le notaba el gesto de tirar. El
		# tiro ya lo marca `kick()` (ver play_shot), que es quien pone ese reloj a cero.
		if avatar.aiming and avatar.has_method("hold_action"):
			avatar.hold_action()


## RAGDOLL DE VERDAD, COMO LOS BOTS. El usuario lo pidio asi: "los cuerpos no caen al piso con
## fisicas como los enemigos". Y se veia un segundo fallo, "se le borra la cabeza": el desplome a mano
## (`go_limp`) dobla cuello y pecho hacia delante y la cabeza se hundia dentro del torso. El ragdoll
## del soldado (`ragdoll.gd::crear`, el mismo que usan los bots) lleva la cabeza en su cadena como un
## cuerpo mas, asi que cuelga de su cuello en vez de meterse dentro.
##
## Se monta APARTE del avatar, en metros, y escribe las poses en el esqueleto. Por eso el animador
## tiene que CALLARSE: si no, reescribe todos los huesos cada cuadro con su clip y gana a la fisica
## (le paso a los bots: la figura se quedaba congelada mientras los cuerpos caian invisibles al lado).
var _ragdoll: Node3D = null
var _empuje_muerte := Vector3.ZERO     ## el golpe que lo mato (net._empuje_muerte): su ragdoll sale con el


## Llega del que muere (puede llegar antes o despues de verle muerto): se guarda y, si ya cayo, se empuja el ragdoll
func empujar_muerte(v: Vector3) -> void:
	_empuje_muerte = v
	if _ragdoll != null and is_instance_valid(_ragdoll) and _ragdoll.has_method("empujar"):
		_ragdoll.empujar(v)

func _morir_con_ragdoll() -> void:
	if avatar == null:
		return
	Audio.muere_otro(global_position, Vector3.ZERO, false)
	var rd = null
	# LEJOS NO HAY SUELO DE JOLT (solo tiene cuerpos a ~55 m del jugador): un ragdoll alli caia a traves del
	# mapa para siempre, y al llegar a por el compañero su cuerpo ya no estaba (medido con --rescatelan: el
	# cuerpo a 30 m bajo tierra). Lejos se desploma sin fisica y el nodo baja al suelo por los voxels.
	var yo = Net.game.player if Net.game != null and "player" in Net.game else null
	var lejos: bool = yo != null and is_instance_valid(yo) and yo.global_position.distance_to(global_position) > 45.0
	if avatar.skeleton != null and get_parent() != null and not lejos:
		rd = RagdollScript.crear(get_parent(), avatar.skeleton,
			Vector3(net_vel.x, 0.0, net_vel.z), _empuje_muerte)
		_empuje_muerte = Vector3.ZERO
	if rd != null:
		avatar.set_process(false)
		_ragdoll = rd
	elif avatar.has_method("go_limp"):
		avatar.go_limp()                  # plan B, igual que los bots: mejor desplomado que tieso


## EL RAGDOLL NO ES HIJO MIO -cuelga de la partida, en metros-, asi que si el jugador se va estando
## muerto hay que llevarselo: si no, su cadaver se quedaria tirado en el mapa para siempre.
func _exit_tree() -> void:
	if is_instance_valid(_ragdoll):
		_ragdoll.queue_free()
	_ragdoll = null


## Y DE VUELTA, al revivir: fuera el ragdoll, el animador vuelve a mandar y el nodo deja de caer.
func _levantarse() -> void:
	_caida = 0.0
	for rs in get_tree().get_nodes_in_group("rescate"):
		if rs.has_method("olvidar"):
			rs.olvidar("p%d" % peer_id)       # si le estaban haciendo la RCP o lo llevaban: fuera esa postura
	rescate_fijo = false
	# EL MUÑECO A SU SITIO (2026-09-27, "al revivir sus amigos lo ven hundido hasta las rodillas"): tumbado para
	# la RCP o en un hombro, el rescate lo mueve dentro de este nodo, y no siempre se deshacia. Al levantarse
	# vuelve SIEMPRE a su posicion y giro de reposo, y al suelo que tenga debajo.
	if avatar:
		if not _avatar_xf0_ok:
			_avatar_xf0 = Transform3D.IDENTITY
		avatar.transform = _avatar_xf0
	global_position = target_pos
	if is_instance_valid(_ragdoll):
		_ragdoll.queue_free()
	_ragdoll = null
	if avatar:
		avatar.set_process(true)
		if avatar.has_method("levantar"):
			avatar.levantar()


## EL CADAVER SE CAE. Muerto, este cuerpo ya no recibe postura -la suya es la de la camara de
## espectador, que no pinta nada aqui-, asi que se quedaba CLAVADO en el aire donde le pillo la
## muerte: saltando, en una escalera, o sobre un suelo que se acaba de volar. El usuario lo pidio
## asi: "que su cuerpo caiga con fisicas, que no quede flotando".
##
## Cae por su cuenta, sin red: no hay nada que sincronizar porque todas las maquinas parten del mismo
## sitio y usan la misma gravedad, y aunque acabe unos centimetros distinto da igual, es un cadaver.
## Se busca el suelo con un rayo contra los VOXELS (no contra la fisica de Jolt): el mundo es voxel y
## asi tambien vale para el suelo que aparece o desaparece al romperse el mapa.
const GRAVEDAD_CADAVER := 16.0
const CAIDA_MAX := 22.0
var _caida := 0.0

func _caer_cadaver(dt: float) -> void:
	var mundo = Net.game.world if Net.game != null and "world" in Net.game else null
	if mundo == null or not mundo.has_method("raycast"):
		return
	_caida = minf(_caida + GRAVEDAD_CADAVER * dt, CAIDA_MAX)
	var paso: float = _caida * dt
	if paso <= 0.0001:
		return
	# desde la cintura hacia abajo: desde los pies, un suelo pegado al talon no se ve
	var desde: Vector3 = global_position + Vector3(0, 0.9, 0)
	var r: Dictionary = mundo.raycast(desde, Vector3.DOWN, 0.9 + paso + 0.05)
	if bool(r.get("hit", false)):
		global_position.y = float((r["position"] as Vector3).y)
		_caida = 0.0
		return
	global_position.y -= paso


## MARCA DE QUE ESTO ES OTRO JUGADOR, no un bot ni un cadaver. El que dispara la mira para saber que
## este impacto NO lo resuelve el, sino el anfitrion (ver player.fire y net.resolver_disparo).
func es_jugador_remoto() -> bool:
	return true


## Le han dado un tiro. La vida la lleva su dueño: aquí sólo se le avisa.
##
## CAMINO VIEJO, que ahora solo usan las CRIATURAS del PvE (criatura.gd): ellas viven en la maquina
## del anfitrion, asi que su daño ya es autoritativo y no hace falta rebobinar nada. Los disparos
## entre jugadores ya no pasan por aqui: van por Net.pedir_disparo.
## "bala" o "cuerpo": lo pone quien da el golpe (las cartas BLINDAJE y PIEL DURA de su dueño, player.golpe_tipo)
var golpe_tipo := ""

func take_damage(d: float, push: Vector3 = Vector3.ZERO) -> void:
	var tipo := golpe_tipo
	golpe_tipo = ""
	if dead or is_friendly():
		return
	if avatar and avatar.has_method("recibir_golpe"):
		avatar.recibir_golpe(push, d)        # el cuerpo encaja el golpe (en la pantalla del que dispara)
	Net.report_hit(peer_id, d, push, tipo)


## ¿Es de mi bando? Entre compañeros no hay fuego amigo: ni daño, ni marca de acierto, ni reacción.
func is_friendly() -> bool:
	# TODOS CONTRA TODOS (el battle royale en SOLO, el duelo en TODOS): nadie es compañero de nadie. En el battle royale
	# por ESCUADRAS si: los de tu escuadra (net.gd, "LOS SUBMODOS")
	if Net.todos_contra_todos():
		return false
	var mine := Net.my_team()
	return mine != "" and Net.team_of(peer_id) == mine


## LA LINTERNA DE ESTE JUGADOR, vista desde aqui (Net._linterna_red). Un foco a la altura de los ojos, un
## palmo por delante, que gira con su yaw (el nodo) y su cabeceo (arriba, en el suavizado).
var _linterna: SpotLight3D = null
var _linterna_t := 0.0
const LinternaCorte := preload("res://scripts/linterna_corte.gd")

func set_linterna(on: bool) -> void:
	if _linterna == null:
		_linterna = SpotLight3D.new()
		_linterna.light_color = Color(1.0, 0.95, 0.85)
		# Las linternas de otros jugadores son detalle visual: no necesitan iluminar
		# media cuadra. Un radio contenido evita que varias en una horda excedan el
		# presupuesto de luces del renderizador móvil.
		_linterna.light_energy = 7.0
		_linterna.spot_range = 28.0
		_linterna.spot_angle = 24.0
		_linterna.spot_attenuation = 0.35
		_linterna.shadow_enabled = false
		add_child(_linterna)
		_linterna.position = Vector3(0.12, 1.55, -0.35)
	_linterna.visible = on
