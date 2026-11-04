extends Node
## --diagbots: LOS BOTS EN VIVO, mientras alguien juega. Cada segundo apunta en user://diag_bots.log una linea
## por bot (bando, rol, estado, donde esta, a donde va, camino, vida, a quien ataca) y en
## user://diag_bots_eventos.log lo que merece mirarse: bots que llevan tiempo sin moverse queriendo ir a algun
## sitio, bots fuera del mapa o por debajo del suelo, y cuanto hace que el jugador no ve a ningun enemigo.
## Pensado para leerlo desde fuera con la partida en marcha ("a veces no encuentro a los enemigos").

var main: Node
var world: Node
var player: Node3D

var _log: FileAccess
var _ev: FileAccess
var _t := 0.0
var _t0 := 0.0
## red_id -> {"pos": Vector3, "desde": s en que llego ahi, "avisado": bool}
var _quietos := {}
var _ultimo_enemigo_visto := 0.0

const ESTADOS := ["GUARD", "PATROL", "INVESTIGATE", "COMBAT", "SEARCH"]
const QUIETO_M := 0.6          ## menos que esto en QUIETO_S segundos = no se ha movido
const QUIETO_S := 8.0


func _ready() -> void:
	_log = FileAccess.open("user://diag_bots.log", FileAccess.WRITE)
	_ev = FileAccess.open("user://diag_bots_eventos.log", FileAccess.WRITE)
	_t0 = Time.get_ticks_msec() / 1000.0
	_evento("diagnostico de bots en marcha (mapa %s)" % str(main.get("current_map")))


func _ahora() -> float:
	return Time.get_ticks_msec() / 1000.0 - _t0


func _evento(texto: String) -> void:
	var linea := "[%6.1f s] %s" % [_ahora(), texto]
	print("[diagbots] " + linea)
	if _ev:
		_ev.store_line(linea)
		_ev.flush()


func _nombre(e) -> String:
	if e == null or not is_instance_valid(e):
		return "-"
	if e == player:
		return "JUGADOR"
	if "nombre_marcador" in e and String(e.nombre_marcador) != "":
		return String(e.nombre_marcador)
	if "bot_name" in e and String(e.bot_name) != "":
		return String(e.bot_name)
	if "red_id" in e:
		return "bot%d" % int(e.red_id)
	return str(e.name)


func _v(p: Vector3) -> String:
	return "(%.1f,%.1f,%.1f)" % [p.x, p.y, p.z]


func _process(dt: float) -> void:
	_t += dt
	if _t < 1.0 or not is_instance_valid(world) or world.is_loading() or not is_instance_valid(player):
		return
	_t = 0.0
	var ahora := _ahora()
	var mi_bando := String(player.get("team"))
	var enemies = main.get("enemies")
	if enemies == null:
		return
	var lineas: Array = []
	var aliados := 0
	var rivales := 0
	var rival_cerca := 1e9
	var alguno_visible := false
	var tam: Vector3 = world.get_world_size() if world.has_method("get_world_size") else Vector3(1e6, 1e6, 1e6)
	for e in enemies.get_children():
		if not is_instance_valid(e) or not ("team" in e) or not ("state" in e):
			continue
		var p: Vector3 = (e as Node3D).global_position
		var rid := int(e.get("red_id")) if "red_id" in e else 0
		var aliado: bool = String(e.team) == mi_bando and mi_bando != ""
		if aliado:
			aliados += 1
		else:
			rivales += 1
			var d := p.distance_to(player.global_position)
			rival_cerca = minf(rival_cerca, d)
			# ¿lo veria el jugador? rayo del ojo al pecho del bot contra el mapa
			if d < 80.0:
				var ojo: Vector3 = player.global_position + Vector3(0, 1.6, 0)
				var pecho: Vector3 = p + Vector3(0, 1.3, 0)
				var r: Dictionary = world.raycast(ojo, (pecho - ojo).normalized(), d)
				if not bool(r.get("hit", false)):
					alguno_visible = true
		var est: int = int(e.state)
		var destino: Vector3 = e.get("move_target") if "move_target" in e else Vector3.ZERO
		var camino: PackedVector3Array = e.get("path") if "path" in e else PackedVector3Array()
		var pi: int = int(e.get("path_i")) if "path_i" in e else 0
		var vel: Vector3 = e.get("velocity") if "velocity" in e else Vector3.ZERO
		var remoto: bool = bool(e.get("remoto")) if "remoto" in e else false
		lineas.append("%s %s %s rol=%s %s pos=%s vel=%.1f vida=%d obj=%s dest=%s a %.1f m camino %d/%d suelo=%s atasco=%.1f alerta=%.2f%s" % [
			"ALIADO" if aliado else "RIVAL ", _nombre(e), String(e.team), String(e.get("rol")) if "rol" in e else "",
			ESTADOS[est] if est >= 0 and est < ESTADOS.size() else str(est), _v(p), Vector2(vel.x, vel.z).length(),
			int(float(e.health)), _nombre(e.get("target")), _v(destino), p.distance_to(destino), pi, camino.size(),
			str((e as CharacterBody3D).is_on_floor()) if e is CharacterBody3D else "?", float(e.get("stuck_t")) if "stuck_t" in e else 0.0,
			float(e.get("awareness")) if "awareness" in e else 0.0, " (copia de red)" if remoto else ""])
		# ---- eventos ----
		# QUIEN DESACTIVA LA BOMBA: solo deberia salir la policia (ct)
		if bool(e.get("_defusing")) and not bool(_quietos.get(rid, {}).get("desactiva", false)):
			_quietos[rid] = _quietos.get(rid, {})
			_quietos[rid]["desactiva"] = true
			_evento("DESACTIVA LA BOMBA: %s (%s) en %s%s" % [_nombre(e), String(e.team), _v(p),
				"  <-- ¡ES DEL BANDO DE LA BOMBA!" if String(e.team) == Net.TEAM_T else ""])
		if p.y < -2.0 or p.x < -2.0 or p.z < -2.0 or p.x > tam.x + 2.0 or p.z > tam.z + 2.0:
			if not bool(_quietos.get(rid, {}).get("fuera", false)):
				_evento("FUERA DEL MAPA: %s (%s) en %s" % [_nombre(e), String(e.team), _v(p)])
				_quietos[rid] = _quietos.get(rid, {})
				_quietos[rid]["fuera"] = true
		var q: Dictionary = _quietos.get(rid, {})
		if q.is_empty() or (q["pos"] as Vector3).distance_to(p) > QUIETO_M:
			q = {"pos": p, "desde": ahora, "avisado": false, "fuera": q.get("fuera", false), "desactiva": q.get("desactiva", false)}
		elif not bool(q["avisado"]) and ahora - float(q["desde"]) >= QUIETO_S:
			# quieto mucho rato. En GUARD es su trabajo; en cualquier otro estado, o con camino pendiente, no.
			var quiere_ir: bool = p.distance_to(destino) > 2.0 and destino != Vector3.ZERO
			# en GUARD es su trabajo y en SEARCH se para a mirar 4-7 s a proposito: ahi solo molesta si se eterniza
			var vigila: bool = est == 0 or est == 4
			if (not vigila and (quiere_ir or pi < camino.size())) or (vigila and ahora - float(q["desde"]) >= 15.0):
				q["avisado"] = true
				_evento("QUIETO %.0f s: %s (%s, %s, rol %s) en %s · destino %s a %.1f m · camino %d/%d · objetivo %s" % [
					ahora - float(q["desde"]), _nombre(e), String(e.team), ESTADOS[est] if est < ESTADOS.size() else str(est),
					String(e.get("rol")) if "rol" in e else "", _v(p), _v(destino), p.distance_to(destino), pi, camino.size(), _nombre(e.get("target"))])
		_quietos[rid] = q
	if alguno_visible:
		_ultimo_enemigo_visto = ahora
	var cab := "t=%.0f ronda_viva=%s marcador=%d-%d jugador %s %s vida %d · aliados %d rivales %d · rival mas cerca %.0f m · sin ver rivales %.0f s" % [
		ahora, str(Net.round_live), Net.score_t, Net.score_ct, mi_bando, _v(player.global_position), int(float(player.get("health"))),
		aliados, rivales, rival_cerca if rival_cerca < 1e8 else -1.0, ahora - _ultimo_enemigo_visto]
	if _log:
		_log.store_line(cab)
		for l in lineas:
			_log.store_line("   " + l)
		_log.flush()
