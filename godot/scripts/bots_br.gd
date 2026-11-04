extends Node
## EL CEREBRO DE BATTLE ROYALE DE LOS BOTS (2026-10-22, pedido: "todos los bots van al mismo lugar y se matan entre
## ellos: que cada uno vaya en una direccion, que su objetivo sea sobrevivir, que se equipen bien, que peleen a
## distancia y si tienen poca vida se vayan a curar y se escondan"). Como los bots de un BR de verdad (PUBG/Fortnite:
## una maquina de estados por encima de la IA de pelea): ATERRIZAR lejos de los demas (salto_br._meta_bot) ->
## LOOTEAR 3-5 puntos de botin que no haya pedido otro bot -> POSICION: un escondite dentro de la zona que viene, lejos
## de los demas bots, y cambiarlo cada rato -> HUIR Y CURARSE con poca vida. La pelea cuerpo a cuerpo la sigue llevando
## la IA de siempre (C++), pero ya no van a por cada tiro que oyen (enemy.hear_noise / alert: solo de cerca).
## Solo piensa quien manda los bots (solo o el anfitrion). `--brbotsantes` = como antes (main._bots_a_por_armas).

const TICK := 1.0
const ALCANCE := 5.0              ## m: llegado a un punto de botin
const PLAZO_LOOT := 75.0          ## s: el que no ha terminado de lootear, se arma igual y va a posicion
const VIDA_HUIR := 0.4            ## por debajo de esta fraccion de la vida, huye a curarse
const VIDA_VUELVE := 0.85
const CURA_POR_S := 18.0
const POSICION_S := Vector2(25.0, 45.0)   ## cuanto aguanta en un escondite antes de cambiar

var main: Node = null
var world = null
var _t := 0.0
var _reloj := 0.0
var _diag := "--brbotsdiag" in OS.get_cmdline_user_args()
var _pedidos := {}                 ## indice de punto de botin -> bot que va a por el


func empezar(m: Node, w) -> void:
	main = m
	world = w


func _process(dt: float) -> void:
	if main == null or (Net.is_online() and not Net.hosting):
		return
	_reloj += dt
	_t -= dt
	if _t > 0.0:
		return
	_t = TICK
	var en = main.get("enemies")
	var bot = get_tree().get_first_node_in_group("botin")
	if en == null or bot == null or not ("puntos" in bot):
		return
	var pl = main.get("player")
	if pl != null and is_instance_valid(pl) and pl.get("br_control") != null:
		# mientras tu sigues en el avion, nada (como antes: el reloj de cada uno empieza al aterrizar tu)
		for e in en.get_children():
			if is_instance_valid(e) and "sin_arma" in e:
				_preparar(e)
				e.set_meta("brb_desde", _reloj)
		return
	var zona = main.get("zona_br")
	if _diag and int(_reloj) % 10 == 0:
		_censo(en)
	for e in en.get_children():
		if not is_instance_valid(e) or not ("sin_arma" in e) or e.process_mode == Node.PROCESS_MODE_DISABLED:
			continue
		if ("health" in e) and float(e.health) <= 0.0:
			continue
		_preparar(e)
		_pensar(e, bot.puntos, zona)


func _preparar(e) -> void:
	if e.has_meta("brb"):
		return
	e.set_meta("brb", "loot")
	e.set_meta("br_bot", true)            # enemy.hear_noise / alert: solo de cerca
	e.set_meta("brb_desde", _reloj)
	e.set_meta("brb_quiere", randi_range(3, 5))
	e.set_meta("brb_vistos", [])
	e.set_meta("vida_max", float(e.health))
	if e.has_method("desarmar"):
		e.desarmar()
	e.cerebro_ext = self


# --------------------------------------------------------------------------------------------------- lo de cada segundo

func _pensar(e, puntos: Array, zona) -> void:
	var p: Vector3 = (e as Node3D).global_position
	var vmax: float = float(e.get_meta("vida_max", 300.0))
	var fase: String = String(e.get_meta("brb"))
	# LA ZONA MANDA (pedido: "los de fuera que entren"): fuera del muro de ahora, lo primero es entrar, sin lootear ni
	# curarse. Antes el botin y la cura les mandaban a otro sitio cada pocos segundos y la orden de la zona se perdia.
	if zona != null and is_instance_valid(zona) and zona.has_method("dentro") and float(zona.t) >= float(zona.PRIMERA) 			and not zona.dentro(p, -2.0):
		if fase != "zona" or _reloj - float(e.get_meta("brb_ord", -999.0)) > 4.0:
			var m: Vector3 = zona.muro()
			var s = zona.siguiente()
			var c: Vector3 = s if s != null else m
			var meta: Vector3 = _suelo(Vector3(c.x, 0.0, c.z) + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * c.y * 0.4)
			if meta == Vector3.ZERO:
				meta = _suelo(Vector3(m.x, 0.0, m.z))
			if meta != Vector3.ZERO:
				e.set_meta("brb", "zona")
				e.set_meta("brb_ord", _reloj)
				e.assign_site(meta, [meta])
		return
	if fase == "zona":
		_a_posicion(e, zona)
		return
	# POCA VIDA: a curarse lejos de quien le pega
	if fase != "huir" and fase != "curar" and float(e.health) < vmax * VIDA_HUIR:
		e.set_meta("brb", "huir")
		e.set_meta("brb_huir", _escondite(e, zona, true))
		return
	match fase:
		"loot":
			var vistos: Array = e.get_meta("brb_vistos")
			var objetivo: int = int(e.get_meta("brb_obj", -1))
			if objetivo >= 0 and objetivo < puntos.size() and p.distance_to(puntos[objetivo]["pos"]) <= ALCANCE:
				vistos.append(objetivo)
				_pedidos.erase(objetivo)
				if String(puntos[objetivo].get("tipo", "")) == "arma" and bool(e.sin_arma):
					e.armar()
				objetivo = -1
			var hecho: bool = vistos.size() >= int(e.get_meta("brb_quiere")) and not bool(e.sin_arma)
			if hecho or _reloj - float(e.get_meta("brb_desde")) > PLAZO_LOOT:
				if bool(e.sin_arma):
					e.armar()
				_pedidos.erase(objetivo)
				_a_posicion(e, zona)
				return
			if objetivo < 0:
				objetivo = _siguiente_botin(e, p, puntos, vistos)
				e.set_meta("brb_obj", objetivo)
				e.set_meta("brb_ord", -999.0)
			if objetivo >= 0 and _reloj - float(e.get_meta("brb_ord", -999.0)) > 6.0:
				e.assign_site(puntos[objetivo]["pos"], [puntos[objetivo]["pos"]])
				e.set_meta("brb_ord", _reloj)
		"posicion":
			# la zona manda: si el escondite queda fuera del circulo que viene, otro
			var esc: Vector3 = e.get_meta("brb_esc")
			var fuera: bool = zona != null and is_instance_valid(zona) and zona.has_method("siguiente") \
				and zona.siguiente() != null and not _en_circulo(esc, zona.siguiente(), 0.85)
			if fuera or _reloj > float(e.get_meta("brb_hasta")):
				_a_posicion(e, zona)
		"curar":
			if float(e.health) >= vmax * VIDA_VUELVE:
				_a_posicion(e, zona)


func _a_posicion(e, zona) -> void:
	var esc: Vector3 = _escondite(e, zona, false)
	e.set_meta("brb", "posicion")
	e.set_meta("brb_esc", esc)
	e.set_meta("brb_hasta", _reloj + randf_range(POSICION_S.x, POSICION_S.y))
	var puestos: Array = [esc]
	for i in 2:
		var a := randf() * TAU
		var q: Vector3 = _suelo(esc + Vector3(cos(a), 0.0, sin(a)) * randf_range(2.0, 5.0))
		if q != Vector3.ZERO:
			puestos.append(q)
	e.assign_site(esc, puestos)


## El punto de botin mas cercano que no haya visitado ni haya pedido otro bot (primero un arma si no tiene).
func _siguiente_botin(e, p: Vector3, puntos: Array, vistos: Array) -> int:
	var mejor := -1
	var md := 1e9
	for i in puntos.size():
		if i in vistos or (_pedidos.has(i) and _pedidos[i] != e and is_instance_valid(_pedidos[i])):
			continue
		var zn = main.get("zona_br")
		if zn != null and is_instance_valid(zn) and float(zn.t) >= float(zn.PRIMERA) and not zn.dentro(puntos[i]["pos"], -3.0):
			continue
		var d: float = p.distance_to(puntos[i]["pos"])
		if bool(e.sin_arma) and String(puntos[i].get("tipo", "")) != "arma":
			d += 25.0
		if d < md:
			md = d
			mejor = i
	if mejor >= 0:
		_pedidos[mejor] = e
	return mejor


## Un sitio dentro de la zona que viene, lejos de los demas bots (y si huye, ademas lejos de su enemigo).
func _escondite(e, zona, huyendo: bool) -> Vector3:
	var c := Vector3.ZERO
	var r := 30.0
	if zona != null and is_instance_valid(zona) and zona.has_method("muro"):
		var s = zona.siguiente() if zona.has_method("siguiente") else null
		var m: Vector3 = s if s != null else zona.muro()
		c = Vector3(m.x, 0.0, m.z)
		r = maxf(m.y * 0.8, 3.0)
	else:
		var tam: Vector3 = world.get_world_size()
		c = Vector3(tam.x * 0.5, 0.0, tam.z * 0.5)
		r = minf(tam.x, tam.z) * 0.4
	var p: Vector3 = (e as Node3D).global_position
	var peligro: Vector3 = (e.target as Node3D).global_position if is_instance_valid(e.target) else Vector3.INF
	var otros: Array = []
	for o in e.get_parent().get_children():
		if o != e and is_instance_valid(o) and o is Node3D:
			otros.append((o as Node3D).global_position)
	var mejor := Vector3.ZERO
	var mejor_v := -1e9
	for i in 14:
		var a := randf() * TAU
		var q: Vector3 = c + Vector3(cos(a), 0.0, sin(a)) * sqrt(randf()) * r
		if huyendo:
			var q2: Vector3 = q.lerp(p, 0.5)    # no cruzar el mapa con poca vida, pero sin salirse de la zona
			if Vector2(q2.x - c.x, q2.z - c.z).length() <= r:
				q = q2
		var g: Vector3 = _suelo(q)
		if g == Vector3.ZERO:
			continue
		var v := 0.0
		var cerca := 1e9
		for o in otros:
			cerca = minf(cerca, g.distance_to(o))
		v += minf(cerca, 40.0)
		if peligro != Vector3.INF:
			v += g.distance_to(peligro) * 1.5
		v -= g.distance_to(p) * (0.6 if huyendo else 0.15)
		if v > mejor_v:
			mejor_v = v
			mejor = g
	return mejor if mejor != Vector3.ZERO else p


func _suelo(q: Vector3) -> Vector3:
	if world.has_method("find_ground"):
		var g: Vector3 = world.find_ground(q)
		return g if g.y > 0.0 else Vector3.ZERO
	return q


func _en_circulo(p: Vector3, m: Vector3, k: float) -> bool:
	return Vector2(p.x - m.x, p.z - m.z).length() <= m.y * k


# --------------------------------------------------------------------------------------------------- enemy.cerebro_ext
## Cada paso de fisica del bot. Devuelve true solo cuando HUYE o SE CURA (los mueve este cerebro); en lo demas manda la
## IA de siempre, que es la que sabe pelear.
func pensar_bot(e, dt: float) -> bool:
	var fase: String = String(e.get_meta("brb", ""))
	if fase == "huir" or fase == "curar":
		# SIN HUNDIRSE (medido: el que huia se colaba por el suelo y caia miles de metros): la caida con tope, y si se
		# cuela igual, de vuelta al ultimo sitio donde piso
		var gp: Vector3 = (e as Node3D).global_position
		if bool(e.on_floor):
			e.set_meta("brb_suelo", gp)
			if e.velocity.y < 0.0:
				e.velocity.y = 0.0
		e.velocity.y = maxf(e.velocity.y, -15.0)
		if gp.y < -2.0 and e.has_meta("brb_suelo"):
			(e as Node3D).global_position = e.get_meta("brb_suelo") + Vector3(0, 0.3, 0)
			e.velocity = Vector3.ZERO
	if fase == "huir":
		var meta: Vector3 = e.get_meta("brb_huir")
		if e._go_to(meta, e.SPRINT_SPEED, dt, 1.5):
			e.set_meta("brb", "curar")
			e.set_meta("brb_vida", float(e.health))
		return true
	if fase == "curar":
		# si le siguen dando, deja de curarse y pelea
		if float(e.health) < float(e.get_meta("brb_vida", 0.0)) - 1.0:
			e.set_meta("brb", "posicion")
			e.set_meta("brb_esc", (e as Node3D).global_position)
			e.set_meta("brb_hasta", _reloj + 5.0)
			return false
		e.crouching = true
		e._stop(dt)
		e.health = minf(float(e.health) + CURA_POR_S * dt, float(e.get_meta("vida_max", 300.0)))
		e.set_meta("brb_vida", float(e.health))
		return true
	# En posicion, sin pelear: ni a buscar al que se le escapo (SEARCH) ni a investigar ruidos de lejos
	if fase == "posicion" and (int(e.state) == 4 or (int(e.state) == 2 and (e as Node3D).global_position.distance_to(e.last_known) > 18.0)):
		e._enter_guard()
	return false


## --brbotsdiag: cada 10 s cuantos hay en cada fase, armados, y a que distancia media esta cada bot del mas cercano
func _censo(en) -> void:
	var fases := {}
	var pos: Array = []
	var armados := 0
	var fuera := 0
	var zn = main.get("zona_br")
	for e in en.get_children():
		if not is_instance_valid(e) or not ("sin_arma" in e) or float(e.health) <= 0.0:
			continue
		var f := String(e.get_meta("brb", "?"))
		fases[f] = int(fases.get(f, 0)) + 1
		pos.append((e as Node3D).global_position)
		var gp: Vector3 = (e as Node3D).global_position
		if gp.y < -3.0 or gp.y > 60.0:
			print("[brbots] PERDIDO %s fase %s en %s estado %d" % [e.name, f, str(gp.snapped(Vector3.ONE * 0.1)), int(e.state)])
		if not bool(e.sin_arma):
			armados += 1
		if zn != null and is_instance_valid(zn) and not zn.dentro(gp):
			fuera += 1
	var suma := 0.0
	for i in pos.size():
		var m := 1e9
		for j in pos.size():
			if i != j:
				m = minf(m, pos[i].distance_to(pos[j]))
		suma += m if m < 1e8 else 0.0
	print("[brbots] fuera de la zona %d · t=%.0f vivos %d armados %d fases %s vecino medio %.1f m" % [fuera, _reloj, pos.size(), armados, str(fases), suma / maxf(pos.size(), 1)])
