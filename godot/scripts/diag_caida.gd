extends Node
## --diagcaida: DIAGNOSTICO EN VIVO de "estoy encima de un bloque y lo atravieso".
##
## Cada frame de fisica mira sobre que esta el jugador. Si es un BLOQUE (un cuerpo de world.info_cuerpo),
## apunta sus cambios de estado (dormido, parado, cuantas formas de colision tiene, modo del cuerpo) y
## donde esta. Si el jugador cae de repente por debajo de donde pisaba y en ese sitio SIGUE habiendo
## bloque (raycast_con_piezas lo ve) pero la fisica NO (el rayo de Jolt no toca nada), eso es el fallo:
## se vuelca todo lo que se sabe en ese instante.
##
## F9 vuelca el estado a mano (para marcar "ahora ha pasado"). Todo va a la consola y a
## user://diag_caida.log.

var player: CharacterBody3D
var world: Node

var _log: FileAccess
var _suelo_y := 0.0
var _suelo_pos := Vector3.ZERO
var _suelo_rid := RID()
var _suelo_ms := 0
var _ultimo_estado := ""
var _evento_ms := -100000
var _hist: Array[String] = []    ## los ultimos estados, para ver que paso justo antes


func _ready() -> void:
	_log = FileAccess.open("user://diag_caida.log", FileAccess.WRITE)
	_escribir("=== diagcaida arrancado %s ===" % Time.get_datetime_string_from_system())
	set_physics_process_priority(-100)


func _escribir(t: String) -> void:
	var linea := "[diagcaida %7.2f] %s" % [Time.get_ticks_msec() / 1000.0, t]
	print(linea)
	if _log:
		_log.store_line(linea)
		_log.flush()


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and (ev as InputEventKey).keycode == KEY_F9:
		_volcar("F9 PULSADO A MANO")


func _info_bloque(rid: RID) -> String:
	if not rid.is_valid():
		return "sin cuerpo"
	var inf: Dictionary = world.info_cuerpo(rid) if world.has_method("info_cuerpo") else {}
	var n: int = PhysicsServer3D.body_get_shape_count(rid)
	var xf: Transform3D = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM)
	var modos := ["STATIC", "KINEMATIC", "RIGID", "RIGID_LINEAR"]
	var modo: int = PhysicsServer3D.body_get_mode(rid)
	return "bloque id %s vox %s | congelado %s anclado %s parado %s | modo %s formas %d capa %d | en %s" % [
		str(inf.get("id", "-")), str(inf.get("voxels", "-")), str(inf.get("congelado", "-")), str(inf.get("anclado", "-")),
		str(inf.get("parado", "-")), modos[modo] if modo < modos.size() else str(modo), n,
		PhysicsServer3D.body_get_collision_layer(rid), str(xf.origin.snapped(Vector3.ONE * 0.01))]


func _es_bloque(rid: RID) -> bool:
	if not rid.is_valid() or not world.has_method("info_cuerpo"):
		return false
	return bool((world.info_cuerpo(rid) as Dictionary).get("existe", false))


func _physics_process(_dt: float) -> void:
	if not is_instance_valid(player) or not is_instance_valid(world):
		return
	# sobre que pisa (lo que dejo el move_and_slide del frame anterior)
	var pisa := RID()
	if player.is_on_floor():
		for i in player.get_slide_collision_count():
			var c := player.get_slide_collision(i)
			if c.get_normal().y > 0.6:
				pisa = c.get_collider_rid()
				break
		_suelo_y = player.global_position.y
		_suelo_pos = player.global_position
		_suelo_rid = pisa
		_suelo_ms = Time.get_ticks_msec()
		if _es_bloque(pisa):
			var est := _info_bloque(pisa)
			# solo los cambios, sin la posicion (si no, cada frame seria distinto)
			var clave := est.substr(0, est.find(" | en "))
			if clave != _ultimo_estado:
				_ultimo_estado = clave
				_escribir("PISA " + est + " | jugador " + str(player.global_position.snapped(Vector3.ONE * 0.01)))
				_hist.append(est)
				if _hist.size() > 12:
					_hist.pop_front()
		elif _ultimo_estado != "suelo":
			_ultimo_estado = "suelo"
			_escribir("pisa el mapa (no un bloque) en %s" % str(player.global_position.snapped(Vector3.ONE * 0.01)))
		return
	# CAYENDO: por debajo de donde pisaba, rapido, poco despues de pisar un bloque
	var desde := Time.get_ticks_msec() - _suelo_ms
	if player.velocity.y < -2.5 and player.global_position.y < _suelo_y - 0.3 and desde < 1500 \
			and Time.get_ticks_msec() - _evento_ms > 3000:
		# ¿sigue habiendo bloque donde estaba? con los datos del mundo y con la fisica
		var o: Vector3 = _suelo_pos + Vector3(0.0, 0.4, 0.0)
		var datos: Dictionary = world.raycast_con_piezas(o, Vector3.DOWN, 1.2)
		var q := PhysicsRayQueryParameters3D.create(o, o + Vector3.DOWN * 1.2, 0xFFFFFFFF, [player.get_rid()])
		var fis: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
		var hay_bloque: bool = bool(datos.get("hit", false)) and bool(datos.get("pieza", false))
		if hay_bloque and fis.is_empty():
			_volcar("ATRAVESADO: el bloque sigue ahi (datos) y la fisica no lo toca")
		elif hay_bloque:
			_volcar("CAIDA con bloque debajo y la fisica SI lo toca (rid %s) · puede ser que te empujara" % str(fis.get("rid", "-")))
		elif _es_bloque(_suelo_rid):
			_volcar("caida donde ya no hay bloque (se movio, se rompio o caiste por el borde)")
		else:
			_evento_ms = Time.get_ticks_msec()     # una caida normal desde el mapa: nada que contar


func _volcar(motivo: String) -> void:
	_evento_ms = Time.get_ticks_msec()
	_escribir("########## " + motivo)
	_escribir("jugador %s vel %s en_suelo %s · pisaba en %s hace %d ms" % [
		str(player.global_position.snapped(Vector3.ONE * 0.01)), str(player.velocity.snapped(Vector3.ONE * 0.01)),
		str(player.is_on_floor()), str(_suelo_pos.snapped(Vector3.ONE * 0.01)), Time.get_ticks_msec() - _suelo_ms])
	_escribir("lo que pisaba AHORA: " + _info_bloque(_suelo_rid))
	for h in _hist:
		_escribir("   antes: " + h)
	var o: Vector3 = _suelo_pos + Vector3(0.0, 0.4, 0.0)
	var datos: Dictionary = world.raycast_con_piezas(o, Vector3.DOWN, 2.0)
	var q := PhysicsRayQueryParameters3D.create(o, o + Vector3.DOWN * 2.0, 0xFFFFFFFF, [player.get_rid()])
	var fis: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
	_escribir("rayo de datos (mundo+bloques): %s" % str({"hit": datos.get("hit"), "pieza": datos.get("pieza", false), "pos": datos.get("position"), "dist": datos.get("distance")}))
	_escribir("rayo de fisica (Jolt): %s" % ("NADA" if fis.is_empty() else str({"pos": fis.position, "rid": fis.rid, "bloque": _es_bloque(fis.rid)})))
	# los bloques cerca del sitio
	if world.has_method("get_bodies_debug"):
		var n := 0
		for b in world.get_bodies_debug():
			var p: Vector3 = b["pos"]
			if p.distance_to(_suelo_pos) < 3.0:
				n += 1
				_escribir("   cerca: id %s vox %s rigido %s solido %s tam %s en %s dist %.2f · %s" % [
					str(b["id"]), str(b["voxels"]), str(b["rigid"]), str(b["solid"]), str(b["size"]),
					str(p.snapped(Vector3.ONE * 0.01)), p.distance_to(_suelo_pos), _info_bloque(b["rid"]) if (b["rid"] as RID).is_valid() else "SIN CUERPO JOLT (barato)"])
		_escribir("bloques a menos de 3 m: %d" % n)
	var st: Dictionary = world.get_stats()
	var claves := {}
	for k in st.keys():
		var ks := String(k)
		if "congel" in ks or "rigid" in ks or "bod" in ks or "cajas" in ks or "apoyo" in ks or "dentro" in ks:
			claves[ks] = st[k]
	_escribir("contadores: %s" % str(claves))
	_escribir("red: online %s anfitrion %s" % [str(Net.is_online()), str(Net.hosting)])
