extends Node3D
## LA ZONA DEL BATTLE ROYALE. Cada 2 minutos se elige una ZONA SEGURA nueva dentro de la actual; se ve en el
## minimapa y en el mapa grande (M, o MAPA en el movil), y durante el ultimo minuto de cada ciclo el MURO
## azul se cierra hasta ella. Fuera del muro se pierde vida poco a poco (cada fase mas), y ni el chaleco ni
## el casco la paran.
##
##   t = 0            despega el avion (salto_br.gd)
##   t = PRIMERA      se anuncia la zona 1 (circulo blanco)
##   +60 s            el muro empieza a cerrarse hacia ella
##   +120 s           ya es la zona; se anuncia la siguiente... y asi hasta cerrarse del todo
##
## LOS CIRCULOS SON LOS MISMOS EN TODAS LAS MAQUINAS: salen de la semilla de la partida (Net.semilla_partida)
## y del mapa, sin mandar nada. Lo unico que viaja es el RELOJ de zona del anfitrion, cada pocos segundos,
## para que quien cargo mas tarde (o entro a mitad) este en la misma fase que los demas. El daño lo calcula
## cada uno sobre si mismo (tu vida es tuya); el de los bots, quien los manda.

var PRIMERA := 90.0            ## s desde el despegue hasta que se anuncia la primera zona
var CICLO := 120.0             ## s entre una zona y la siguiente: "cada 2 minutos"
var CIERRE := 60.0             ## s que tarda el muro en cerrarse (el final de cada ciclo)
## s entre reintentos de mandar a un bot que YA esta fuera hacia el centro (su A* puede fallar o puede
## quedarse trabado: una sola orden por fase no basta).
const REINTENTO := 6.0
var RADIO_INICIAL := 380.0     ## m: el primer muro deja fuera solo el mar
var RADIOS := [230.0, 150.0, 95.0, 58.0, 32.0, 14.0, 0.0]
## vida por segundo fuera del muro en cada fase (sobre 300 de vida: la primera es un aviso, la ultima mata)
const DANO := [2.0, 3.0, 5.0, 8.0, 12.0, 18.0, 26.0, 26.0]
var ALTO_MURO := 260.0

var main: Node = null
var world = null
var jugador: Node = null
var salto = null
var t := 0.0                     ## reloj de zona (s desde el despegue)
var en_marcha := false
var escala_tiempo := 1.0         ## las pruebas lo aceleran
var circulos: Array = []         ## [Vector3(cx, 0, cz) con .y = radio]: 0 = el inicial, 1.. = las zonas
var _muro: MeshInstance3D = null
var _mat: ShaderMaterial = null
var _dano_t := 0.0
var _espera_caida := 0.0
var _bots_t := 0.0
var _red_t := 0.0
var _ui: CanvasLayer = null
var _aviso: Label = null
var _tinte: ColorRect = null
var _mapa: Control = null
var _tex_isla: Texture2D = null
## Para las pruebas
var dano_total := 0.0
## ULTIMO EN PIE. Morir en la isla es quedar eliminado: no se reaparece (player.gd, die) y los bots
## tampoco vuelven (main._on_enemy_died). Cada segundo se cuentan los vivos -tu, los de la sala y los bots,
## esten en el avion, cayendo o en tierra- y cuando queda uno se acaba: VICTORIA o el puesto en que caiste.
var terminada := false
var max_vivos := 0               ## los que llego a haber: solo se gana si hubo alguien contra quien jugar
var mi_puesto := 0               ## en que puesto caiste (0 = sigues vivo)
var _fin_t := 1.0
var _fin_vigia := 0.0
var _fin_pide := 0.0
var _pantalla: Control = null


func empezar(m: Node, w, pl: Node, s) -> void:
	main = m
	world = w
	jugador = pl
	salto = s
	# LA ESCALA DE CADA MAPA (2026-10-21, el CUARTO): <mapa>.br.json "zona" cambia los radios y los tiempos
	var cfg: Dictionary = (load("res://scripts/salto_br.gd")).config_br(String(main.get("current_map"))).get("zona", {})
	RADIO_INICIAL = float(cfg.get("radio_inicial", RADIO_INICIAL))
	if cfg.has("radios"):
		RADIOS = cfg["radios"]
	PRIMERA = float(cfg.get("primera", PRIMERA))
	CICLO = float(cfg.get("ciclo", CICLO))
	CIERRE = float(cfg.get("cierre", CIERRE))
	ALTO_MURO = float(cfg.get("alto_muro", ALTO_MURO))
	_calcular_circulos()
	_montar_muro()
	_montar_ui()
	var ruta := "res://ui/mapas/%s.png" % String(main.get("current_map"))
	if ResourceLoader.exists(ruta):
		_tex_isla = load(ruta)
	print("[zona] %d zonas: %s" % [circulos.size() - 1, str(circulos.map(func(c): return "(%.0f,%.0f r%.0f)" % [c.x, c.z, c.y]))])


# --------------------------------------------------------------------------------------------------
# LOS CIRCULOS
# --------------------------------------------------------------------------------------------------

func _calcular_circulos() -> void:
	var tam: Vector3 = world.get_world_size()
	var rng := RandomNumberGenerator.new()
	rng.seed = (int(Net.semilla_partida) if Net.is_online() else randi()) ^ 0x5A0A
	var c := Vector3(tam.x * 0.5, RADIO_INICIAL, tam.z * 0.5)
	circulos = [c]
	var mar: float = _nivel_mar()
	# PRIMERO EL FINAL: un punto al azar en tierra en cualquier parte de la isla (nieve, desierto, puerto...).
	# Antes cada zona se sorteaba dentro de la anterior y los pasos se anulaban: acababa siempre en el centro.
	var r_fin: float = RADIOS[-1]
	var alcance: float = maxf(0.0, RADIO_INICIAL - r_fin)
	var fin := Vector2(c.x, c.z)
	for intento in 80:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * alcance
		var q := Vector2(c.x + cos(a) * d, c.z + sin(a) * d)
		if q.x < 30.0 or q.y < 30.0 or q.x > tam.x - 30.0 or q.y > tam.z - 30.0:
			continue
		var g: Dictionary = world.raycast(Vector3(q.x, tam.y - 0.5, q.y), Vector3.DOWN, tam.y)
		if g.get("hit", false) and float(g.position.y) > mar + 0.4:
			fin = q
			break
	# luego cada zona avanza hacia el final todo lo que le deja caber ENTERA dentro de la anterior
	for r in RADIOS:
		var prev: Vector3 = circulos[-1]
		var holgura: float = maxf(0.0, prev.y - r)
		var p := Vector2(prev.x, prev.z)
		var falta := fin - p
		var paso: float = minf(falta.length(), holgura)
		var q: Vector2 = p + (falta.normalized() * paso if falta.length() > 0.001 else Vector2.ZERO)
		circulos.append(Vector3(q.x, r, q.y))


func _nivel_mar() -> float:
	var ag = main.get("agua")
	if ag != null and is_instance_valid(ag) and ag.get("mar_y") != null:
		return float(ag.get("mar_y"))
	if salto != null and salto.get("cfg_br") is Dictionary and (salto.cfg_br as Dictionary).has("mar"):
		return float(salto.cfg_br["mar"])
	return 3.0


## En que fase va (cuantas zonas se han anunciado; 0 = todavia ninguna).
func fase() -> int:
	if t < PRIMERA:
		return 0
	return mini(int((t - PRIMERA) / CICLO) + 1, circulos.size() - 1)


## El muro ahora mismo: Vector3(cx, radio, cz) en x, y (radio), z.
func muro() -> Vector3:
	var k := fase()
	if k == 0:
		return circulos[0]
	var ini: float = PRIMERA + (k - 1) * CICLO + (CICLO - CIERRE)
	var a: Vector3 = circulos[k - 1]
	var b: Vector3 = circulos[k]
	var f := clampf((t - ini) / CIERRE, 0.0, 1.0)
	if k == circulos.size() - 1 and t > PRIMERA + k * CICLO:
		f = 1.0
	return a.lerp(b, f)


## La zona que viene (la que se ve en blanco), o null si no hay ninguna anunciada.
func siguiente():
	var k := fase()
	if k == 0:
		return null
	return circulos[k]


## Segundos que faltan para el siguiente cambio y que es: ["anuncio" | "cierre" | "fin", s]
func proximo() -> Array:
	if t < PRIMERA:
		return ["anuncio", PRIMERA - t]
	var k := fase()
	var base: float = PRIMERA + (k - 1) * CICLO
	var cierre: float = base + (CICLO - CIERRE)
	if t < cierre:
		return ["cierre", cierre - t]
	if t < base + CICLO and k < circulos.size() - 1:
		return ["cerrando", base + CICLO - t]
	if k >= circulos.size() - 1:
		return ["fin", 0.0]
	return ["anuncio", base + CICLO - t]


func dentro(p: Vector3, margen: float = 0.0) -> bool:
	var m := muro()
	return Vector2(p.x - m.x, p.z - m.z).length() <= m.y - margen


# --------------------------------------------------------------------------------------------------
# CADA CUADRO
# --------------------------------------------------------------------------------------------------

func _physics_process_medido(dt: float) -> void:
	if not en_marcha:
		# EL RELOJ ARRANCA CUANDO TODOS HAN CAIDO (2026-10-22, pedido: "apenas me lanzo ya se achica"): antes, al
		# despegar el avion. Ahora cuando tu has aterrizado y no queda ningun bot en el aire (o a los 90 s del
		# despegue, por si alguien se queda colgado). Al invitado le llega el reloj del anfitrion (sincronizar).
		if salto == null or not is_instance_valid(salto):
			en_marcha = true
		elif int(salto.estado) != int(salto.ESPERA):
			_espera_caida += dt
			var todos: bool = int(salto.estado) == int(salto.FIN) and (not salto.has_method("_bots_en_el_aire") or int(salto._bots_en_el_aire()) == 0)
			if "--zonaantes" in OS.get_cmdline_user_args() or todos or _espera_caida > 90.0:
				en_marcha = true
				print("[zona] empieza el reloj a los %.1f s del despegue" % _espera_caida)
			else:
				return
		else:
			return
	t += dt * escala_tiempo
	var m := muro()
	if _muro:
		_muro.position = Vector3(m.x, ALTO_MURO * 0.5 - 30.0, m.z)
		var r: float = maxf(m.y, 0.5)
		_muro.scale = Vector3(r, ALTO_MURO, r)
		_mat.set_shader_parameter("radio", r)
	# QUIEN SIGUE VIVO, una vez por segundo
	_fin_t -= dt
	if _fin_t <= 0.0 and not terminada:
		_fin_t = 1.0
		_comprobar_fin()
	# EL DAÑO, una vez por segundo
	_dano_t -= dt
	if _dano_t <= 0.0:
		_dano_t = 1.0
		_hacer_dano()
	# los bots, cada dos segundos (solo quien los manda)
	_bots_t -= dt
	if _bots_t <= 0.0 and ((not Net.is_online()) or Net.hosting):
		_bots_t = 2.0
		_bots()
	# el reloj a los demas
	_red_t -= dt
	if _red_t <= 0.0 and Net.is_online() and Net.hosting:
		_red_t = 4.0
		if Net.has_method("net_zona_reloj"):
			Net.net_zona_reloj(t)
	_actualizar_ui()


## El anfitrion manda su reloj; aqui se adopta si se ha ido mas de medio segundo.
func sincronizar(t_anfitrion: float) -> void:
	en_marcha = true
	if absf(t_anfitrion - t) > 0.5:
		t = t_anfitrion


## ¿Va el jugador en el avion o en el paracaidas? (el vehiculo NO cuenta: ahi la zona te mata igual)
func _en_el_aire() -> bool:
	var c = jugador.get("br_control") if is_instance_valid(jugador) else null
	return c != null and is_instance_valid(c) and c.has_method("en_el_aire")


func _dano_ahora() -> float:
	return DANO[mini(fase(), DANO.size() - 1)]


func _hacer_dano() -> void:
	# EL COCHE NO TE SALVA DE LA ZONA. Se perdonaba a todo el que tuviera `br_control`, que era para el
	# avion y el paracaidas (ahi no puedes hacer nada); un vehiculo SI cuenta, que si no bastaba con
	# meterse en un coche y quedarse fuera del circulo tan tranquilo.
	if not is_instance_valid(jugador) or bool(jugador.get("spectating")) or _en_el_aire():
		return
	if dentro((jugador as Node3D).global_position):
		return
	var d := _dano_ahora()
	dano_total += d
	if jugador.has_method("dano_zona"):
		jugador.dano_zona(d)


func _bots() -> void:
	var en = main.get("enemies")
	if en == null:
		return
	var sig = siguiente()
	var objetivo: Vector3 = sig if sig != null else muro()
	var actual: Vector3 = muro()
	for e in en.get_children():
		if not (e is Node3D) or not is_instance_valid(e) or e.process_mode == Node.PROCESS_MODE_DISABLED:
			continue
		var p: Vector3 = (e as Node3D).global_position
		var fuera_ya: bool = not dentro(p)
		if fuera_ya and e.has_method("take_damage"):
			# el mismo daño que al jugador: con el doble, los que se quedaban fuera morian antes de
			# tener tiempo de llegar (medido: 15 bots muertos en 10 s con el circulo pequeño)
			e.take_damage(_dano_ahora() * 2.0)   # se mira cada 2 s: el doble = lo mismo por segundo que a ti
		# A DONDE VA. Si ya esta FUERA del circulo de ahora, al centro de ese, corriendo y reintentando
		# cada pocos segundos (su A* puede fallar, o puede quedarse trabado en un edificio); si esta
		# dentro pero fuera del que viene, al que viene, una vez por fase. Antes solo existia lo
		# segundo y una sola vez: el que se quedaba fuera se quedaba fuera hasta morir.
		var meta: Vector3 = actual if fuera_ya else objetivo
		var fuera_sig: bool = Vector2(p.x - objetivo.x, p.z - objetivo.z).length() > objetivo.y * 0.8
		var ultimo: float = float(e.get_meta("zona_dest_t")) if e.has_meta("zona_dest_t") else -999.0
		var ya_avisado: bool = e.has_meta("zona_fase") and int(e.get_meta("zona_fase")) == fase()
		var toca: bool = (fuera_ya and t - ultimo > REINTENTO) or (not fuera_ya and fuera_sig and not ya_avisado)
		if toca and e.has_method("assign_site"):
			var puestos: Array = []
			for i in 4:
				var a := i * TAU / 4.0 + randf() * 0.6
				var q := Vector3(meta.x + cos(a) * meta.y * 0.35, 0.0, meta.z + sin(a) * meta.y * 0.35)
				var g: Vector3 = world.find_ground(q) if world.has_method("find_ground") else q
				if g.y > 0.0:
					puestos.append(g)
			if puestos.is_empty():
				var g2: Vector3 = world.find_ground(Vector3(meta.x, 0.0, meta.z)) if world.has_method("find_ground") else Vector3(meta.x, 0.0, meta.z)
				if g2.y > 0.0:
					puestos.append(g2)
			if not puestos.is_empty():
				e.assign_site(puestos[0], puestos)
				e.set_meta("zona_fase", fase())
				e.set_meta("zona_dest_t", t)


# --------------------------------------------------------------------------------------------------
# ULTIMO EN PIE
# --------------------------------------------------------------------------------------------------

## Los que siguen en la partida: [nodo, nombre]. El jugador local cuenta aunque vaya en el avion.
func vivos() -> Array:
	var out: Array = []
	if is_instance_valid(jugador) and float(jugador.get("health")) > 0.0 and not bool(jugador.get("spectating")):
		out.append([jugador, "TU"])
	for r in Net.remotes.values():
		if is_instance_valid(r) and not Net.is_dead(int(r.peer_id)):
			out.append([r, String(Net.players.get(int(r.peer_id), {}).get("name", "JUGADOR"))])
	var en = main.get("enemies")
	if en:
		for e in en.get_children():
			# solo bots (tienen bando y vida): en `enemies` tambien cuelgan los cadaveres, y contarlos como vivos
			# dejaba la partida sin final
			if e is Node3D and is_instance_valid(e) and ("team" in e) and ("health" in e) and float(e.health) > 0.0 and not e.is_queued_for_deletion():
				var bn: String = String(e.get("bot_name")) if e.get("bot_name") != null else ""
				out.append([e, "UN RIVAL"])         # un bot no enseña su nombre
	return out


## EL FINAL QUE MANDA EL ANFITRION (Net._br_fin), en todas las maquinas y tambien en la suya.
## `ganador` es el peer de quien gana (0 = un bot o nadie) y `nombre` como lo ve el anfitrion.
func fin_de_red(ganador: int, nombre: String, cuantos: int) -> void:
	if terminada:
		return
	terminada = true
	max_vivos = maxi(max_vivos, cuantos)
	if ganador != 0 and ganador == multiplayer.get_unique_id():
		mi_puesto = 1
		_victoria()
		Audio.play2d("grab", 2.0)
	else:
		var quien := nombre
		if ganador != 0 and Net.players.has(ganador):
			quien = String(Net.players[ganador].get("name", nombre))
		_mostrar_pantalla("FIN DE LA PARTIDA", "Ha ganado %s%s" % [quien, ("  ·  tú quedaste #%d" % mi_puesto) if mi_puesto > 0 else ""], false)
	print("[zona] fin (anfitrion): gana %s (peer %d) · puesto %d de %d" % [nombre, ganador, mi_puesto, max_vivos])


## ---------------------------------------------------------------------------------------------------------------
## POR ESCUADRAS (Net.es_escuadras, 2026-09-30): gana la ULTIMA ESCUADRA con alguien en pie, aunque tu ya hayas caido.
## Si cae la tuya entera, tu puesto es el de las escuadras que quedan mas una. Lo decide el anfitrion
## (Net.net_br_fin_escuadra) y en todas las maquinas acaba en `fin_escuadra_de_red`.
## ---------------------------------------------------------------------------------------------------------------
var max_escuadras := 0
var puesto_escuadra := 0
var _lista_escuadra: Control = null


## De que bando es cada uno de `vivos()`: tu, una persona de la sala o un bot
func equipo_de(n) -> String:
	if n == null or not is_instance_valid(n):
		return ""
	if n == jugador:
		return Net.my_team()
	if "peer_id" in n:
		return Net.team_of(int(n.peer_id))
	if "team" in n:
		return String(n.team)
	return ""


func _comprobar_fin_escuadras(v: Array) -> void:
	var quedan := {}
	for x in v:
		var eq := equipo_de(x[0])
		if eq != "":
			quedan[eq] = true
	max_escuadras = maxi(max_escuadras, quedan.size())
	if not terminada and puesto_escuadra == 0 and max_escuadras >= 2 and not quedan.has(Net.my_team()):
		_escuadra_caida(quedan.size())
	if max_escuadras < 2 or quedan.size() > 1:
		return
	var ganadora: String = String(quedan.keys()[0]) if quedan.size() == 1 else ""
	if Net.is_online():
		if not Net.hosting:
			# El anfitrion arbitra, pero si ya veo un unico superviviente no me
			# quedo esperando para siempre un aviso de final que se haya perdido.
			_fin_vigia += 1.0
			_fin_pide -= 1.0
			if _fin_vigia >= 3.0 and _fin_pide <= 0.0:
				_fin_pide = 2.0
				Net.pedir_fin_br()
			return
		Net.net_br_fin_escuadra(ganadora, max_vivos)
		return
	fin_escuadra_de_red(ganadora, max_vivos)


## Ha caido el ultimo de tu escuadra: tu puesto (las escuadras que quedan en pie, mas la tuya)
func _escuadra_caida(quedan: int) -> void:
	if puesto_escuadra > 0 or terminada:
		return
	puesto_escuadra = quedan + 1
	mi_puesto = puesto_escuadra
	_mostrar_pantalla("TU ESCUADRA HA CAÍDO", "Puesto #%d de %d escuadras" % [puesto_escuadra, maxi(max_escuadras, puesto_escuadra)], false)


## EL FINAL QUE MANDA EL ANFITRION (Net._br_fin_escuadra), en todas las maquinas y tambien en la suya.
func fin_escuadra_de_red(equipo: String, cuantos: int) -> void:
	if terminada:
		return
	terminada = true
	max_vivos = maxi(max_vivos, cuantos)
	print("[zona] fin por escuadras: gana la %s · la mia es la %s · %d jugadores" % [
		Net.nombre_equipo(equipo) if equipo != "" else "nadie", Net.nombre_equipo(Net.my_team()), max_vivos])
	if equipo != "" and equipo == Net.my_team():
		mi_puesto = 1
		_victoria()
		Audio.play2d("grab", 2.0)
	else:
		_mostrar_pantalla("FIN DE LA PARTIDA", "Ha ganado la %s%s" % [Net.nombre_equipo(equipo) if equipo != "" else "nadie",
			("  ·  tu escuadra quedó #%d" % puesto_escuadra) if puesto_escuadra > 0 else ""], false)


## La tabla de tu escuadra al ganar: tu, las personas de tu escuadra y sus bots (sin nombre de bot: "COMPAÑERO n")
func _filas_escuadra(mi_nombre: String, mis_bajas: int) -> Array:
	var mia := Net.my_team()
	var filas: Array = [{"nombre": mi_nombre, "equipo": mia, "bajas": mis_bajas, "muertes": 0 if float(jugador.get("health")) > 0.0 else 1, "es_yo": true}]
	for id in Net.players.keys():
		if Net.is_online() and int(id) == multiplayer.get_unique_id():
			continue
		if Net.team_of(int(id)) == mia:
			filas.append({"nombre": String(Net.players[id].get("name", "JUGADOR")), "equipo": mia, "bajas": 0,
				"muertes": 1 if Net.is_dead(int(id)) else 0, "es_yo": false})
	var en = main.get("enemies")
	if en:
		var k := 0
		for e in en.get_children():
			if is_instance_valid(e) and "team" in e and String(e.team) == mia:
				k += 1
				var nb := String(e.get("nombre_marcador")) if e.get("nombre_marcador") != null else ""
				filas.append({"nombre": nb if nb != "" else "COMPAÑERO %d" % k, "equipo": mia, "bajas": 0,
					"muertes": 0 if float(e.get("health")) > 0.0 else 1, "es_yo": false})
	return filas


## El jugador local ha caido: su puesto es el numero de vivos que quedan mas el.
## CAPA DE BATTLEFIELD: la zona suena. Nueva zona, el muro que empieza a cerrarse y el que para, y
## FUERA el locutor avisa y queda el zumbido de peligro hasta que vuelves a entrar.
var _snd_fase := ""
var _snd_fuera := false
func _sonidos_zona(fuera: bool, estado: String) -> void:
	if estado != _snd_fase:
		if _snd_fase != "":
			match estado:
				"cierre":
					Audio.bf2d("modo/zona_aparece", -4.0, Audio.PRI_HIGH)
					Audio.ui("objetivo_nuevo", -6.0)
				"cerrando":
					Audio.bf2d("modo/zona_cierra", -4.0, Audio.PRI_HIGH)
					Audio.ui("critico", -6.0)
				"fin":
					Audio.bf2d("modo/zona_para", -4.0, Audio.PRI_HIGH)
				"anuncio":
					Audio.bf2d("modo/zona_para", -4.0, Audio.PRI_HIGH)
		_snd_fase = estado
	if fuera != _snd_fuera:
		_snd_fuera = fuera
		if fuera:
			Audio.voz("fuera_limites", 1, 15.0)
			Audio.ui("fuera_cuenta", -6.0)
		else:
			Audio.ui("dentro_otra_vez", -8.0)
		if fuera:
			Audio.bf2d("yo/zona_empieza", -4.0, Audio.PRI_HIGH)
		Audio.bucle("zona_quema", "yo/zona_bucle", fuera, -10.0)
		Audio.bucle("zona_fuera", "ui/fuera_bucle", fuera, -12.0)
		Audio.bucle("zona_muerte", "modo/zona_aviso_muerte", fuera, -14.0)
	# EL MURO SUENA: acercandote (por dentro o por fuera) se oye el fuego de la tormenta cada vez mas
	if is_instance_valid(jugador) and not terminada and t >= PRIMERA:
		var m := muro()
		var p: Vector3 = (jugador as Node3D).global_position
		var al_muro: float = absf(Vector2(p.x - m.x, p.z - m.z).length() - m.y)
		var k: float = clampf(1.0 - al_muro / 30.0, 0.0, 1.0)
		Audio.bucle("muro_fuego", "modo/zona_fuego", k > 0.02, lerpf(-30.0, -8.0, k))
		Audio.bucle("muro_brasas", "modo/zona_brasas", k > 0.3, lerpf(-24.0, -12.0, k))
	else:
		Audio.bucle("muro_fuego", "", false)
		Audio.bucle("muro_brasas", "", false)


func jugador_eliminado() -> void:
	if terminada:
		return
	# POR ESCUADRAS no estas fuera del todo mientras quede alguien de la tuya: la miras hasta el final (y si gana, ganas)
	if Net.es_escuadras():
		var quedan := {}
		var siguen := false
		for x in vivos():
			var eq := equipo_de(x[0])
			quedan[eq] = true
			if x[0] != jugador and eq == Net.my_team():
				siguen = true
		if siguen:
			_mostrar_pantalla("ELIMINADO", "Tu escuadra sigue en pie · mírala hasta el final", false)
		else:
			_escuadra_caida(quedan.size())
		return
	mi_puesto = vivos().size() + 1
	_mostrar_pantalla("ELIMINADO", "Puesto #%d de %d" % [mi_puesto, maxi(max_vivos, mi_puesto)], false)


func _comprobar_fin() -> void:
	if " --mapafotos=" in " " + " ".join(OS.get_cmdline_user_args()):
		return   # (fotos del mapa: que no salga el final encima)
	var v := vivos()
	max_vivos = maxi(max_vivos, v.size())
	if main.get("hud") and main.hud.has_method("set_bots_alive"):
		main.hud.set_bots_alive(maxi(0, v.size() - (1 if mi_puesto == 0 else 0)))
	if Net.es_escuadras():
		_comprobar_fin_escuadras(v)
		return
	if max_vivos < 2 or v.size() > 1:
		return
	# EN RED DECIDE EL ANFITRION. Cada maquina contaba los vivos por su cuenta, y el avatar de otro jugador no
	# existe hasta que llega su primer mensaje: medido, el INVITADO se dio por ganador (0 bajas) con el anfitrion
	# vivo. Ahora solo el anfitrion cierra la partida y dice a todos quien ha ganado (Net.net_br_fin).
	if Net.is_online():
		if not Net.hosting:
			return
		var g = v[0][0] if v.size() == 1 else null
		var peer := 0
		if g == jugador:
			peer = multiplayer.get_unique_id()
		elif g != null and ("peer_id" in g):
			peer = int(g.peer_id)
		Net.net_br_fin(peer, String(v[0][1]) if v.size() == 1 else "nadie", max_vivos)
		return
	terminada = true
	if v.size() == 1 and v[0][0] == jugador:
		mi_puesto = 1
		_victoria()
		Audio.play2d("grab", 2.0)
	else:
		var quien: String = String(v[0][1]) if v.size() == 1 else "nadie"
		_mostrar_pantalla("FIN DE LA PARTIDA", "Ha ganado %s%s" % [quien, ("  ·  tú quedaste #%d" % mi_puesto) if mi_puesto > 0 else ""], false)
	print("[zona] fin: %s · puesto %d de %d" % [("gana el jugador" if mi_puesto == 1 else "gana otro"), mi_puesto, max_vivos])


## GANAR ES LA PANTALLA DE VICTORIA DE VERDAD (hud.mostrar_victoria, la de los demas modos: podio, cartel y
## premio), no el panelito de eliminado. Y SE COBRA: el battle royale era el unico modo que no pasaba por
## `Settings.premiar`, asi que ganar no daba ni EXP ni oro (pedido: "al ganar no aparece la pestaña victoria,
## no da exp ni dinero"). Premio: 600 EXP y 400 de oro, mas 15 y 5 por baja.
func _victoria() -> void:
	var mis_bajas: int = int(main.get("kills")) if main.get("kills") != null else 0
	var nombre: String = main._mi_nombre() if main.has_method("_mi_nombre") else "TÚ"
	var premio: Dictionary = Settings.premiar(true, 600 + mis_bajas * 15, 400 + mis_bajas * 5,
		{"modo": "br", "segundos": int(main.segundos_partida()) if main.has_method("segundos_partida") else 0,
		"bajas": mis_bajas, "dano": int(Combat.partida_dano), "objetivos": 1, "mvp": true})
	print("[zona] VICTORIA · %d bajas · premio %s" % [mis_bajas, str(premio)])
	# LA SECUENCIA DEL FINAL, como en los demas modos (main.secuencia_fin): el rayo con tus bajas y los que habia,
	# los logros, el mejor jugador (tu) y la tabla con tu puesto
	# POR ESCUADRAS: la tabla es la de tu escuadra (tu, tus compañeros y los bots que la rellenaban), con su color
	if main.has_method("secuencia_fin") and Net.es_escuadras():
		var mia := Net.my_team()
		var col: Color = Net.color_equipo(mia)
		main.secuencia_fin({"gane": true, "mios": mis_bajas, "rivales": max_escuadras, "filas": _filas_escuadra(nombre, mis_bajas),
			"premio": premio, "logros": preload("res://scripts/logros.gd").lista(true, true), "marcador": [mis_bajas, 0],
			"intro": {"etiqueta_mia": "TUS BAJAS", "etiqueta_rival": "ESCUADRAS"},
			"equipos": [{"equipo": mia, "nombre": "%s · LA ÚLTIMA EN PIE" % Net.nombre_equipo(mia), "tanteo": "#1",
				"claro": col.darkened(0.15), "oscuro": col.darkened(0.45)}]})
		return
	if main.has_method("secuencia_fin"):
		var filas := [{"nombre": nombre, "equipo": "", "bajas": mis_bajas, "muertes": 0, "es_yo": true}]
		var mvp := true
		main.secuencia_fin({"gane": true, "mios": mis_bajas, "rivales": max_vivos, "filas": filas, "premio": premio,
			"logros": preload("res://scripts/logros.gd").lista(true, mvp), "marcador": [mis_bajas, 0],
			"intro": {"etiqueta_mia": "TUS BAJAS", "etiqueta_rival": "JUGADORES"},
			"equipos": [{"equipo": "", "nombre": "ÚLTIMO EN PIE DE %d" % max_vivos, "tanteo": "#1",
				"claro": Color(0.86, 0.62, 0.12), "oscuro": Color(0.6, 0.4, 0.06)}]})
	else:
		_mostrar_pantalla("¡VICTORIA!", "Último en pie de %d · ¡a cenar!" % max_vivos, true)


## La pantalla del final (o de eliminado): titulo, puesto y dos botones. Encima de todo, con el raton suelto.
func _mostrar_pantalla(titulo: String, sub: String, gana: bool) -> void:
	if is_instance_valid(_pantalla):
		_pantalla.queue_free()
	# en su propia capa, por encima de todo (el HUD y los botones del movil van en capas mas altas que _ui)
	var capa := CanvasLayer.new()
	capa.layer = 60
	add_child(capa)
	_pantalla = Control.new()
	_pantalla.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pantalla.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capa.add_child(_pantalla)
	_pantalla.tree_exited.connect(capa.queue_free)
	var fondo := ColorRect.new()
	fondo.set_anchors_preset(Control.PRESET_CENTER)
	fondo.size = Vector2(620, 220)
	fondo.position = Vector2(-310, -150)
	fondo.color = Color(0.05, 0.06, 0.09, 0.82)
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pantalla.add_child(fondo)
	var t := Label.new()
	t.text = titulo
	t.add_theme_font_size_override("font_size", 52)
	t.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2) if gana else Color(1.0, 0.45, 0.4))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.position = Vector2(0, 18)
	t.size = Vector2(620, 70)
	fondo.add_child(t)
	var s2 := Label.new()
	s2.text = sub
	s2.add_theme_font_size_override("font_size", 22)
	s2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s2.position = Vector2(0, 92)
	s2.size = Vector2(620, 34)
	fondo.add_child(s2)
	var b1 := Button.new()
	b1.text = "VOLVER AL LOBBY"
	b1.position = Vector2(60, 150)
	b1.size = Vector2(230, 48)
	b1.pressed.connect(func(): main.go_to_lobby())
	fondo.add_child(b1)
	var b2 := Button.new()
	b2.text = "SEGUIR MIRANDO"
	b2.position = Vector2(330, 150)
	b2.size = Vector2(230, 48)
	b2.pressed.connect(func():
		if is_instance_valid(_pantalla):
			_pantalla.queue_free()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	fondo.add_child(b2)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --------------------------------------------------------------------------------------------------
# COMO SE VE
# --------------------------------------------------------------------------------------------------

func _montar_muro() -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 1.0
	cm.radial_segments = 128
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/zona_br.gdshader")
	_mat.set_shader_parameter("alto", ALTO_MURO)
	_muro = MeshInstance3D.new()
	_muro.mesh = cm
	_muro.material_override = _mat
	_muro.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# la caja de un cilindro de 380 m escalado: que no lo recorte el frustum por error
	_muro.extra_cull_margin = 50.0
	add_child(_muro)


func _montar_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 4
	add_child(_ui)
	_tinte = ColorRect.new()
	_tinte.color = Color(0.25, 0.3, 0.95, 0.16)
	_tinte.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tinte.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tinte.visible = false
	_ui.add_child(_tinte)
	_aviso = Label.new()
	_aviso.add_theme_font_size_override("font_size", 20)
	_aviso.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_aviso.add_theme_constant_override("outline_size", 5)
	_aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aviso.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_aviso.position = Vector2(-360, 130)
	_aviso.size = Vector2(720, 60)
	_aviso.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_aviso)
	_mapa = Control.new()
	_mapa.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mapa.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mapa.visible = false
	_mapa.draw.connect(_dibujar_mapa)
	_mapa.gui_input.connect(func(ev: InputEvent):
		if (ev is InputEventScreenTouch and ev.pressed) or (ev is InputEventMouseButton and ev.pressed):
			alternar_mapa())
	_ui.add_child(_mapa)
	# POR ESCUADRAS: la lista de tu escuadra con la vida de cada uno, a la izquierda (escuadra_hud.gd)
	if Net.es_escuadras():
		_lista_escuadra = preload("res://scripts/escuadra_hud.gd").new()
		_lista_escuadra.zona = self
		_ui.add_child(_lista_escuadra)


func _actualizar_ui() -> void:
	if _aviso == null or not is_instance_valid(jugador):
		return
	var fuera: bool = t >= PRIMERA and not dentro((jugador as Node3D).global_position) and not _en_el_aire()
	_tinte.visible = fuera
	if terminada:
		_aviso.text = ""
		_tinte.visible = false
		_sonidos_zona(false, "")
		return
	var p := proximo()
	_sonidos_zona(fuera, String(p[0]))
	var s := int(ceil(float(p[1])))
	var reloj := "%d:%02d" % [s / 60, s % 60]
	var texto := ""
	match String(p[0]):
		"anuncio":
			texto = ("PRIMERA ZONA EN %s" if fase() == 0 else "NUEVA ZONA EN %s") % reloj
		"cierre":
			texto = "ZONA %d · SE CIERRA EN %s" % [fase(), reloj]
		"cerrando":
			texto = "¡LA ZONA SE ESTA CERRANDO! · %s" % reloj
		"fin":
			texto = "ZONA FINAL"
	if fuera:
		texto += "\n¡FUERA DE LA ZONA!  -%d VIDA/s" % int(_dano_ahora())
		_aviso.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	else:
		_aviso.add_theme_color_override("font_color", Color(0.9, 0.93, 1.0))
	_aviso.text = texto
	if _mapa.visible:
		_mapa.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		alternar_mapa()


func alternar_mapa() -> void:
	if _mapa:
		_mapa.visible = not _mapa.visible
		Audio.ui("mapa_abre" if _mapa.visible else "mapa_cierra", -8.0)
		# abierto se come los toques: tocarlo en cualquier sitio lo cierra (en el movil no hay tecla M)
		_mapa.mouse_filter = Control.MOUSE_FILTER_STOP if _mapa.visible else Control.MOUSE_FILTER_IGNORE
		_mapa.queue_redraw()


## EL MAPA GRANDE: la isla entera (la vista del generador, res://ui/mapas/<mapa>.png), el muro (azul), la zona
## que viene (blanco), la ruta del avion y donde estas tu.
func _dibujar_mapa() -> void:
	var vs: Vector2 = _mapa.get_viewport_rect().size
	var lado: float = minf(vs.x, vs.y) * 0.86
	var org := (vs - Vector2(lado, lado)) * 0.5
	var tam: Vector3 = world.get_world_size()
	var k: float = lado / tam.x
	var a_mapa := func(p: Vector3) -> Vector2:
		return org + Vector2(p.x, p.z) * k
	_mapa.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.55))
	if _tex_isla:
		_mapa.draw_texture_rect(_tex_isla, Rect2(org, Vector2(lado, lado)), false)
	else:
		_mapa.draw_rect(Rect2(org, Vector2(lado, lado)), Color(0.12, 0.3, 0.42))
	_mapa.draw_rect(Rect2(org, Vector2(lado, lado)), Color(1, 1, 1, 0.6), false, 2.0)
	# la ruta del avion
	if salto != null and is_instance_valid(salto) and salto.get("largo") != null and float(salto.largo) > 0.0:
		var p0: Vector3 = salto.origen
		var p1: Vector3 = salto.origen + salto.dir * float(salto.largo)
		_mapa.draw_line(a_mapa.call(p0), a_mapa.call(p1), Color(1, 1, 1, 0.35), 2.0, true)
		if salto.get("avion") != null and is_instance_valid(salto.avion):
			_mapa.draw_circle(a_mapa.call(salto.avion.global_position), 6.0, Color(1, 1, 1, 0.9))
	# el muro y la siguiente
	var m := muro()
	if t >= PRIMERA or m.y < RADIO_INICIAL - 1.0:
		_mapa.draw_arc(a_mapa.call(m), m.y * k, 0.0, TAU, 128, Color(0.3, 0.5, 1.0, 0.95), 3.0, true)
	var sig = siguiente()
	if sig != null:
		_mapa.draw_arc(a_mapa.call(sig), maxf(sig.y, 1.0) * k, 0.0, TAU, 128, Color(1, 1, 1, 0.95), 2.0, true)
	# POR ESCUADRAS: tus compañeros vivos, con el color de la escuadra (a los rivales no se les ve)
	if Net.es_escuadras():
		var col_e: Color = Net.color_equipo(Net.my_team())
		for x in vivos():
			if x[0] != jugador and equipo_de(x[0]) == Net.my_team():
				var pc: Vector2 = a_mapa.call((x[0] as Node3D).global_position)
				_mapa.draw_circle(pc, 7.0, Color(0.05, 0.04, 0.12, 0.9))
				_mapa.draw_circle(pc, 5.0, col_e)
	# tu, con la flecha hacia donde miras
	var yo: Vector3 = (jugador as Node3D).global_position
	var c: Vector2 = a_mapa.call(yo)
	var fwd: Vector3 = -(jugador as Node3D).global_transform.basis.z
	var f2 := Vector2(fwd.x, fwd.z).normalized()
	var lat := Vector2(-f2.y, f2.x)
	_mapa.draw_colored_polygon(PackedVector2Array([c + f2 * 11.0, c - f2 * 6.0 + lat * 6.0, c - f2 * 3.0, c - f2 * 6.0 - lat * 6.0]),
		Color(1.0, 0.85, 0.15))
	var fuente := ThemeDB.fallback_font
	_mapa.draw_string(fuente, org + Vector2(0, -10), "MAPA  ·  azul: la zona ahora  ·  blanco: la siguiente  ·  %s" % ("toca para cerrar" if Settings.is_touch() else "[M] cerrar"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.9))

## (medida para los bancos: lo que cuesta este nodo por fotograma, en Prof)
func _physics_process(dt: float) -> void:
	var _tm := Time.get_ticks_usec()
	_physics_process_medido(dt)
	_quedan_tick()
	Prof.add("zona_br.fis", Time.get_ticks_usec() - _tm)


## QUEDAN N (2026-11-01): al bajar a 10, 5 y 2 con vida, el cartel de jugada (una vez cada uno)
const QUEDAN_AVISOS := [10, 5, 2]
var _quedan_dichos := {}

func _quedan_tick() -> void:
	if Engine.get_physics_frames() % 30 != 0:
		return
	var n := vivos().size()
	for q in QUEDAN_AVISOS:
		if n <= q and n > 1 and not _quedan_dichos.has(q):
			_quedan_dichos[q] = true
			var h = main.get("hud") if main else null
			if h and h.has_method("anuncio"):
				h.anuncio("QUEDAN %d" % n if q > 2 or Net.es_escuadras() else "¡MANO A MANO!")
			break
