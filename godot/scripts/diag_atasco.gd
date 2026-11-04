extends Node
## --botsatasco (con --map=dust2): LOS ATASCOS DE UNA PARTIDA REAL, REPETIDOS SIN NADIE. Pone bots sin enemigos a la vista en los puntos exactos donde se quedaron clavados jugando, con el
## mismo destino, y mide si llegan: distancia al principio, la minima alcanzada, la del final y el rato mas
## largo sin moverse. Tambien pregunta al A* directamente si hay camino desde ahi.
## Los casos salen de user://diag_bots_eventos.log de la partida del 2026-09-17 (--diagbots).

var main: Node
var world: Node
var player: Node3D

const CASOS := [
	# [nombre, desde, hasta, tanda]
	["A spawn poli, repisa", Vector3(85.4, 2.8, 43.9), Vector3(82.5, 1.5, 30.2), 0],
	["B spawn poli, repisa 2", Vector3(86.4, 2.8, 43.9), Vector3(91.4, 1.3, 35.6), 1],
	["C spawn poli, caja", Vector3(87.9, 1.0, 34.8), Vector3(101.9, 2.8, 34.0), 0],
	["D junto al sitio A", Vector3(58.3, 3.7, 29.4), Vector3(50.1, 2.8, 26.0), 0],
	["E spawn poli -> sitio A (vueltas)", Vector3(88.9, 1.4, 37.2), Vector3(49.4, 2.9, 26.1), 1],
	["F base T -> sitio B", Vector3(56.2, 2.5, 72.1), Vector3(93.2, 4.6, 28.8), 0],
	["G sitio B -> sitio A", Vector3(100.0, 4.2, 29.9), Vector3(49.5, 2.8, 26.9), 1],
	["H sitio B, bajar", Vector3(99.1, 4.8, 27.2), Vector3(95.0, 2.7, 36.9), 0],
	["I base T", Vector3(64.3, 5.4, 83.7), Vector3(54.1, 5.7, 75.1), 0],
	["J pasillo B", Vector3(97.2, 2.8, 35.3), Vector3(101.9, 2.8, 34.0), 1],
]
const DURA_S := 35.0


func _ready() -> void:
	_correr()


func _correr() -> void:
	for i in 900:
		await get_tree().create_timer(0.2).timeout
		if world != null and not world.is_loading() and is_instance_valid(player):
			break
	await get_tree().create_timer(2.0).timeout
	# UN ENEMIGO QUE NADIE VE: sin nadie del otro bando la IA de un bot no corre (se queda sin objetivo). El
	# jugador va al otro bando, congelado bajo el suelo en una esquina.
	Net.choose_team(Net.TEAM_T)
	if player.has_method("apply_team"):
		player.apply_team(Net.TEAM_T)
	player.invulnerable = true
	player.global_position = Vector3(2.0, -4.0, 2.0)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var enemies: Node = main.get("enemies")
	if "--cohetemide" in OS.get_cmdline_user_args():
		# EL COHETE DEL BOT CONTRA EL DEL JUGADOR: mismo muro, dos puntos separados, y cuantos voxels quita cada uno
		for caso in [["bot (3,2 m / 200)", 3.2, 200], ["jugador (4 m / 255)", 4.0, 255]]:
			var desde := Vector3(53.0, 3.5, 40.0) + Vector3(0, 0, -8.0) * float(1 if String(caso[0]).begins_with("bot") else 0)
			var h: Dictionary = world.raycast(desde, Vector3(1, 0, 0), 40.0)
			if not bool(h.get("hit", false)):
				print("[cohetemide] %s: no encontre pared desde %s" % [String(caso[0]), str(desde)])
				continue
			var p: Vector3 = h["position"]
			var mat := int(world.get_material_at(p + Vector3(0.15, 0, 0)))
			var n := int(world.explode(p, float(caso[1]), int(caso[2])))
			print("[cohetemide] %-22s en %s (material %d): %d voxels" % [String(caso[0]), str(p.round()), mat, n])
		get_tree().quit(0)
		return
	if "--botsatasco_mapa" in OS.get_cmdline_user_args():
		for c in CASOS:
			_mapa_celdas(String(c[0]), c[1])
		get_tree().quit(0)
		return
	for tanda in 2:
		for e in enemies.get_children():
			e.queue_free()
		await get_tree().process_frame
		var bots: Array = []
		for c in CASOS:
			if int(c[3]) != tanda:
				continue
			var desde: Vector3 = c[1]
			var hasta: Vector3 = c[2]
			var camino: PackedVector3Array = world.find_path(desde, hasta)
			var fin := "vacio" if camino.is_empty() else "%d puntos, acaba a %.1f m del destino" % [camino.size(), camino[camino.size() - 1].distance_to(hasta)]
			var e = main.ENEMY_SCENE.instantiate()
			enemies.add_child(e)
			e.global_position = desde
			e.setup(world, player, 900 + bots.size())
			e.team = Net.TEAM_CT
			e.rol = ""
			e.rover = false
			e.posts = [hasta]
			e.site_pos = hasta
			e.move_target = hasta
			e.state = 1                 # PATROL
			e.guard_t = 999.0
			if e.has_method("invalidate_path"):
				e._invalidate_path_now()
			bots.append({"caso": c, "e": e, "d0": desde.distance_to(hasta), "min": desde.distance_to(hasta), "quieto": 0.0, "peor": 0.0,
				"ultima": desde, "vacios": 0, "a_star": fin, "llego_t": -1.0})
		var t := 0.0
		while t < DURA_S:
			await get_tree().create_timer(0.5).timeout
			t += 0.5
			if t <= 3.0 and "--botsatasco_d" in OS.get_cmdline_user_args():
				for b in bots:
					if String(b["caso"][0]).begins_with("D") and is_instance_valid(b["e"]):
						var e = b["e"]
						var pts := []
						for k in mini(6, e.path.size()):
							pts.append("(%.1f,%.1f,%.1f)" % [e.path[k].x, e.path[k].y, e.path[k].z])
						print("[botsatasco] D t=%.1f pos %s vel %s path_i %d/%d %s bloqueado_delante %s estado %d · INCRUSTADO %s" % [t, str(e.global_position), str(e.velocity),
							e.path_i, e.path.size(), str(pts), str(e._blocked_at(e.global_position + (e.path[mini(e.path_i, e.path.size() - 1)] - e.global_position).normalized() * 0.4) if e.path.size() > 0 else "-"), e.state, str(e._blocked_at(e.global_position))])
			for b in bots:
				var e = b["e"]
				if not is_instance_valid(e):
					continue
				var p: Vector3 = e.global_position
				var hasta: Vector3 = b["caso"][2]
				var d := Vector2(p.x - hasta.x, p.z - hasta.z).length()
				b["min"] = minf(float(b["min"]), d)
				if d < 1.5 and float(b["llego_t"]) < 0.0:
					b["llego_t"] = t
				if (b["ultima"] as Vector3).distance_to(p) < 0.25 and d >= 1.5:
					b["quieto"] = float(b["quieto"]) + 0.5
					b["peor"] = maxf(float(b["peor"]), float(b["quieto"]))
					if float(b["quieto"]) == 3.0:
						var pi: int = int(e.path_i)
						var wp_txt := "sin camino"
						if pi < e.path.size():
							var wp: Vector3 = e.path[pi]
							var hacia_wp: Vector3 = (wp - p) * Vector3(1, 0, 1)
							wp_txt = "punto %d/%d %s (a %.2f m, sube %.2f) · siguiente %s · bloqueado hacia el %s" % [pi, e.path.size(), _v3(wp),
								hacia_wp.length(), wp.y - p.y, _v3(e.path[pi + 1]) if pi + 1 < e.path.size() else "-",
								str(e._blocked_at(p + hacia_wp.normalized() * 0.3)) if hacia_wp.length() > 0.01 else "-"]
						print("[botsatasco]   PARADO 3 s: %s en %s · %s · incrustado %s · suelo %s · vel %s · estado %d · salto_t %.2f" % [
							String(b["caso"][0]).substr(0, 1), _v3(p), wp_txt, str(e._blocked_at(p)), str(e.on_floor), _v3(e.velocity), int(e.state), float(e._salto_t)])
				else:
					b["quieto"] = 0.0
				b["ultima"] = p
				if (e.path as PackedVector3Array).is_empty() and d >= 1.5:
					b["vacios"] = int(b["vacios"]) + 1
		for b in bots:
			var e = b["e"]
			var p: Vector3 = e.global_position if is_instance_valid(e) else Vector3.ZERO
			var hasta: Vector3 = b["caso"][2]
			print("[botsatasco] %-34s %s · empezo a %.1f m · minimo %.1f · final %.1f m en %s%s · parado seguido hasta %.1f s · sin camino %.0f%% · A* inicial: %s" % [
				String(b["caso"][0]), "LLEGA" if float(b["llego_t"]) >= 0.0 else "NO LLEGA", float(b["d0"]), float(b["min"]),
				Vector2(p.x - hasta.x, p.z - hasta.z).length(), "(%.1f,%.1f,%.1f)" % [p.x, p.y, p.z],
				(" a los %.1f s" % float(b["llego_t"])) if float(b["llego_t"]) >= 0.0 else "", float(b["peor"]),
				100.0 * float(b["vacios"]) / (DURA_S * 2.0), String(b["a_star"])])
			if is_instance_valid(e):
				print("[botsatasco]      estado %d · va a %s · camino %d/%d · objetivo %s · ultimo conocido %s · rol '%s' rover %s" % [int(e.state), _v3(e.move_target),
					int(e.path_i), e.path.size(), str(e.target.name) if is_instance_valid(e.target) else "-", _v3(e.last_known), String(e.rol), str(e.rover)])
	get_tree().quit(0)


## Dibuja las celdas de navegacion (8 voxels = 0,8 m a 10 cm) alrededor de `p`, a la altura de sus pies, con el mismo
## criterio que el A* (vx_nav: suelo en la celda y NADA solido en toda la columna de 1,75 m encima):
##   @ la celda del bot · # transitable · x hay suelo pero algo estorba en la columna · . sin suelo
## y a la derecha lo mismo exigiendo el hueco solo en el centro (0,6 m), para comparar.
func _mapa_celdas(nombre: String, p: Vector3) -> void:
	var vs: float = world.get_voxel_size() if world.has_method("get_voxel_size") else 0.1
	var cel := 8 if vs < 0.15 else 4
	var alto := int(1.75 / vs + 0.5)
	var paso := int(0.75 / vs + 0.5)
	var caida := int(3.0 / vs + 0.5)
	var ccx := int(floor(p.x / (vs * cel)))
	var ccz := int(floor(p.z / (vs * cel)))
	var pies := int(floor(p.y / vs))
	print("[botsatasco] %s en %s · voxel %.2f m, celda %d voxels" % [nombre, str(p), vs, cel])
	for dz in range(-4, 5):
		var fila := ""
		var fila2 := ""
		for dx in range(-4, 5):
			var r := _celda(ccx + dx, ccz + dz, pies, cel, vs, alto, paso, caida, 0)
			var r2 := _celda(ccx + dx, ccz + dz, pies, cel, vs, alto, paso, caida, 1)
			var mio := dx == 0 and dz == 0
			fila += "@" if mio and r == "#" else ("O" if mio else r)
			fila2 += "@" if mio and r2 == "#" else ("O" if mio else r2)
		print("[botsatasco]    %s     %s" % [fila, fila2])
	_que_estorba(ccx, ccz, pies, cel, vs, alto, paso, caida)


## En la celda del bot: para cada suelo posible, la primera altura (h) y cuantos voxels de la celda estorban ahi.
func _que_estorba(cx: int, cz: int, pies: int, cel: int, vs: float, alto: int, paso: int, caida: int) -> void:
	for y in range(pies + paso, pies - caida - 1, -1):
		var suelo := 0
		for dz in cel:
			for dx in cel:
				if world.get_material_at(Vector3((cx * cel + dx + 0.5) * vs, (y + 0.5) * vs, (cz * cel + dz + 0.5) * vs)) > 0:
					suelo += 1
		if suelo == 0:
			continue
		var txt := ""
		for h in range(1, alto + 1):
			var n := 0
			var borde := 0
			for dz in cel:
				for dx in cel:
					if world.get_material_at(Vector3((cx * cel + dx + 0.5) * vs, (y + h + 0.5) * vs, (cz * cel + dz + 0.5) * vs)) > 0:
						n += 1
						if dx == 0 or dz == 0 or dx == cel - 1 or dz == cel - 1:
							borde += 1
			if n > 0:
				txt += " h%.1fm:%d(%d borde)" % [h * vs, n, borde]
		print("[botsatasco]      suelo a %.1f m (%d voxels de %d):%s" % [(y + 1) * vs, suelo, cel * cel, txt if txt != "" else " LIBRE"])


func _celda(cx: int, cz: int, pies: int, cel: int, vs: float, alto: int, paso: int, caida: int, margen: int) -> String:
	# el suelo mas alto en [pies - caida, pies + paso] con la columna libre encima
	var hubo_suelo := false
	for y in range(pies + paso, pies - caida - 1, -1):
		var suelo := false
		for dz in cel:
			for dx in cel:
				if world.get_material_at(Vector3((cx * cel + dx + 0.5) * vs, (y + 0.5) * vs, (cz * cel + dz + 0.5) * vs)) > 0:
					suelo = true
					break
			if suelo:
				break
		if not suelo:
			continue
		hubo_suelo = true
		var libre := true
		for h in range(1, alto + 1):
			for dz in range(margen, cel - margen):
				for dx in range(margen, cel - margen):
					if world.get_material_at(Vector3((cx * cel + dx + 0.5) * vs, (y + h + 0.5) * vs, (cz * cel + dz + 0.5) * vs)) > 0:
						libre = false
						break
				if not libre:
					break
			if not libre:
				break
		if libre:
			return "#"
	return "x" if hubo_suelo else "."


func _v3(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]
