extends Node
## --diagposte=x,z[,+|-]: UN POSTE DE LUZ EN LAN, VISTO DESDE CADA MAQUINA. `x,z` es la cabeza de la farola
## (pve_cuarentena.lights.json); el poste esta a 1,5 m, hacia uno de los cuatro lados, y se busca solo.
## Al entrar en el mapa pone al jugador a 3 m del poste (lado + o -) mirandolo. Despues, cada cuarto de
## segundo y solo cuando algo cambia, apunta cuantos voxels quedan en el poste (abajo, en medio, arriba y
## el brazo) y que bloques hay alrededor (id, tamaño, donde, si duermen). Cada instancia firma sus lineas
## (ANFITRION / INVITADO) para comparar las dos. F9 vuelca el estado a mano.

var world: Node
var player: CharacterBody3D

var _cabeza := Vector2.ZERO
var _lado := 1.0
var _base := Vector3.INF
var _hacia := Vector2.ZERO
var _log: FileAccess
var _t := 0.0
var _ultimo := ""
var _listo := false


func _ready() -> void:
	for f in OS.get_cmdline_user_args():
		if f.begins_with("--diagposte="):
			var p := f.substr(12).split(",")
			_cabeza = Vector2(float(p[0]), float(p[1]))
			if p.size() > 2 and p[2] == "-":
				_lado = -1.0
	_log = FileAccess.open("user://diag_poste_%s.log" % ("b" if _lado < 0.0 else "a"), FileAccess.WRITE)
	_arrancar()


func _quien() -> String:
	if not Net.is_online():
		return "SOLO"
	return "ANFITRION" if Net.hosting else "INVITADO"


func _escribir(t: String) -> void:
	var linea := "[diagposte %s %7.2f] %s" % [_quien(), Time.get_ticks_msec() / 1000.0, t]
	print(linea)
	if _log:
		_log.store_line(linea)
		_log.flush()


func _arrancar() -> void:
	# a que el mundo este cargado y el jugador en el mapa
	for i in 600:
		await get_tree().create_timer(0.5).timeout
		if is_instance_valid(world) and not world.is_loading() and is_instance_valid(player) and player.is_on_floor():
			break
	await get_tree().create_timer(1.0).timeout
	# EL POSTE: de los cuatro sitios posibles a 1,5 m de la cabeza, el que tiene metal entre 2,5 y 4,5 m
	var mejor := 0
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var c: Vector2 = _cabeza - d * 1.5
		var n: int = world.contar_voxels(Vector3(c.x - 0.35, 2.5, c.y - 0.35), Vector3(c.x + 0.35, 4.5, c.y + 0.35))
		if n > mejor:
			mejor = n
			_base = Vector3(c.x, 0.0, c.y)
			_hacia = d
	if _base == Vector3.INF:
		_escribir("NO ENCUENTRO EL POSTE junto a la cabeza %s" % str(_cabeza))
		return
	var suelo: Dictionary = world.raycast(Vector3(_base.x + _hacia.y * 1.2, 12.0, _base.z + _hacia.x * 1.2), Vector3.DOWN, 20.0)
	var y_suelo: float = (suelo.position as Vector3).y if suelo.get("hit", false) else 1.0
	_base.y = y_suelo
	# EL JUGADOR A 3 m, DE LADO (perpendicular al brazo, para que no le caiga encima), MIRANDO AL POSTE
	var lateral := Vector3(-_hacia.y, 0.0, _hacia.x) * _lado
	var sitio: Vector3 = _base + lateral * 3.0 + Vector3(0.0, 0.3, 0.0)
	player.global_position = sitio
	player.velocity = Vector3.ZERO
	var objetivo: Vector3 = _base + Vector3(0.0, 3.0, 0.0)
	var dir: Vector3 = objetivo - (sitio + Vector3(0.0, 1.6, 0.0))
	if "look" in player:
		player.look = Vector2(atan2(-dir.x, -dir.z), atan2(dir.y, Vector2(dir.x, dir.z).length()))
	_escribir("poste en %s (brazo hacia %s, %d voxels a media altura) · jugador puesto en %s" % [
		str(_base.snapped(Vector3.ONE * 0.01)), str(_hacia), mejor, str(sitio.snapped(Vector3.ONE * 0.01))])
	_listo = true


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and (ev as InputEventKey).keycode == KEY_F9:
		_ultimo = ""
		_escribir("F9 A MANO")


func _process(dt: float) -> void:
	if not _listo or not is_instance_valid(world):
		return
	_t += dt
	if _t < 0.25:
		return
	_t = 0.0
	var b := _base
	var tramos := []
	for tr in [[0.0, 2.0], [2.0, 4.0], [4.0, 6.6]]:
		tramos.append(int(world.contar_voxels(Vector3(b.x - 0.35, b.y + tr[0], b.z - 0.35), Vector3(b.x + 0.35, b.y + tr[1], b.z + 0.35))))
	var h := Vector3(_hacia.x, 0.0, _hacia.y)
	var c1: Vector3 = b + Vector3(0.0, 5.8, 0.0)
	var c2: Vector3 = b + h * 3.2 + Vector3(0.0, 7.4, 0.0)
	var brazo: int = world.contar_voxels(Vector3(minf(c1.x, c2.x) - 0.3, c1.y, minf(c1.z, c2.z) - 0.3), Vector3(maxf(c1.x, c2.x) + 0.3, c2.y, maxf(c1.z, c2.z) + 0.3))
	var bloques := []
	for bd in world.get_bodies_debug():
		var p: Vector3 = bd.pos
		if Vector2(p.x - b.x, p.z - b.z).length() > 6.0:
			continue
		var rid: RID = bd.rid
		var inf: Dictionary = world.info_cuerpo(rid) if rid.is_valid() else {}
		bloques.append("id %s %dvox en %s %s%s" % [str(bd.id), int(bd.voxels), str(p.snapped(Vector3.ONE * 0.1)),
			("congelado" if bool(inf.get("congelado", false)) else ("parado" if bool(inf.get("parado", false)) else "MOVIENDOSE")),
			("" if rid.is_valid() else " (barato)")])
	bloques.sort()
	var st: Dictionary = world.get_stats()
	var clave := "poste abajo %d · medio %d · arriba %d · brazo %d | bloques %d: %s | desconocidos %s pendientes %s" % [
		tramos[0], tramos[1], tramos[2], brazo, bloques.size(), "; ".join(bloques),
		str(st.get("congel_desconocidos", "-")), str(st.get("congel_pendientes", "-"))]
	if clave == _ultimo:
		return
	_ultimo = clave
	_escribir(clave)
