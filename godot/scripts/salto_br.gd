extends Node3D
## EL SALTO DEL BATTLE ROYALE, como en PUBG. Al empezar la partida en un mapa con botin, todos van en el
## AVION (avion_br.gd), que cruza la isla en linea recta a 170 m. Cada uno salta cuando quiere (ESPACIO, o
## SALTAR en el movil); al final de la ruta te echan.
##
##   AVION       vas en la bodega; la camara gira alrededor del avion con el raton. Nadie te puede dar.
##   CAIDA LIBRE bajas a 32 m/s y te diriges con el movimiento (hasta 16 m/s). Mirando abajo PICAS:
##               bajas a 50 m/s y avanzas menos. Es la parte que decide donde caes.
##   PARACAIDAS  se abre solo a 38 m del suelo (o antes, con SALTAR). Bajas a 5,5 m/s y planeas hacia
##               delante: abrirlo alto es llegar lejos, abrirlo bajo es llegar antes.
##   SUELO       al tocar suelo (o agua) vuelves a mandar tu. La camara vuelve a como la tenias.
##
## LA RUTA la saca cada maquina de la SEMILLA DE LA PARTIDA (Net.semilla_partida, la decide el anfitrion):
## todos ven el mismo avion en el mismo sitio sin mandar nada. Tu salto no viaja como mensaje: viaja tu
## posicion, como siempre. Los BOTS los tira quien los manda (el anfitrion, o tu jugando solo), repartidos
## a lo largo de la ruta; los demas los ven caer por la red como a cualquier jugador. Los paracaidas de los
## demas se dibujan aqui a partir de como bajan (ver _paracaidas_de_otros).

const AvionScript := preload("res://scripts/avion_br.gd")

var ALTURA := 170.0            ## m de altura de vuelo
var VELOCIDAD := 17.0          ## m/s del avion: ~30 s para cruzar la isla
var FUERA := 70.0              ## m fuera del mapa por donde entra y sale el avion
## s de aproximacion antes de la primera tierra: lo justo para ver la costa acercarse sin tragarse medio
## minuto de mar (ver `empezar`).
var APROXIMACION := 5.0
var CAIDA := 32.0                ## m/s cayendo en plancha ("caida" del br.json)
var CAIDA_PICADO := 50.0         ## m/s mirando abajo ("caida_picado")
var AVANCE_LIBRE := 16.0         ## m/s hacia donde empujes en caida libre ("avance_libre")
var GIRO_LIBRE := 2.5            ## lo rapido que responde al empujar ("giro_libre")
var ABRIR_SOLO := 38.0         ## m sobre el suelo: el paracaidas se abre solo
const ABRIR_MIN := 6.0           ## m: mas cerca que esto ya no da tiempo (se cae a plomo)
const BAJA_PARACAIDAS := 5.5     ## m/s
const BAJA_PICANDO := 8.5        ## m/s tirando de las bandas para bajar antes
const PLANEO := 5.0              ## m/s hacia delante sin tocar nada
const PLANEO_MAX := 10.5         ## m/s empujando hacia delante
const LADO_PARACAIDAS := 4.5     ## m/s hacia los lados
var DIST_CAMARA := 44.0
## DESDE ARRIBA TIENE QUE VERSE LA ISLA. El motor dibuja lo que esta a menos de su distancia de render del
## "jugador", y a 170 m de altura TODO queda mas lejos que eso: desde el avion se veia un suelo gris. Mientras
## se esta en el aire: el mundo se dibuja alrededor del suelo que hay debajo (punto_de_vista), la distancia
## de render sube al maximo, la niebla baja y el plano lejano de la camara se aleja. Al aterrizar, todo como
## estaba (lo guardado al subir).
const RENDER_EN_EL_AIRE := 2.0       ## escala de la distancia de render (el tope del motor)
const NIEBLA_EN_EL_AIRE := 0.0022    ## densidad: se ve a ~450 m
const LEJANO_EN_EL_AIRE := 900.0

enum { AVION, LIBRE, PARACAIDAS, FIN, ESPERA, HANGAR, CIERRE, DESPEGUE }
## EL AVION EN EL SUELO (2026-10-21, pedido: "el avion en un spawn, que sea el lobby del battle royale con la escotilla
## abierta; quien sube, se cierra la escotilla y anda, y despues la gente se tira"). Si el <mapa>.br.json trae "hangar":
##   HANGAR    el avion parado con la RAMPA bajada; andas libre. Subes por la rampa (o se acaba la espera y te suben).
##   CIERRE    la rampa se levanta (CIERRE_S).
##   DESPEGUE  rueda y sube hasta la altura de vuelo en DESPEGUE_S; de ahi, la ruta de siempre (AVION).
const CIERRE_S := 2.6
const DESPEGUE_S := 8.0
const SUBIDA_LARGO := 34.0       ## m que avanza mientras sube
const RAMPA_LARGO := 5.0
## ANTES DE DESPEGAR, UN MOMENTO EN EL SUELO con la pantalla tapada: la distancia de dibujo ya al maximo (las
## mallas lejanas se construyen ahi y no con el avion en marcha, que eran 2 s a 12-25 fps) y el avion y los
## paracaidas delante de la camara, para que sus materiales se estrenen tapados.
const ESPERA_T := 1.5

var main: Node = null
var world = null
var jugador: Node = null
var avion: Node3D = null
var cfg_br := {}
var _hangar := Vector3.ZERO      ## donde esta el avion en el suelo (con "hangar")
var _hangar_y := 0.0             ## la y del avion parado (las ruedas en el suelo)
var _hangar_t := 0.0             ## lo que queda de espera
var _fase_t := 0.0
var _rampa: Node3D = null
var _rampa_abierta := 0.6
var _escala_avion := 1.0          ## "escala_avion" del br.json (el cuarto: un avion de juguete)
var origen := Vector3.ZERO
var dir := Vector3.FORWARD
var largo := 0.0
var t := 0.0                     ## s desde que despego
var estado := FIN
var _t_dentro := Vector2(0, 0)   ## tramo de la ruta [s] en que el avion esta sobre el mapa jugable
var _cam: Camera3D = null
var _tp_antes := false
var _paracaidas: Node3D = null
var _ui: CanvasLayer = null
var _aviso: Label = null
var _bots: Array = []            ## [{"n": nodo, "t": s de salto, "fase": AVION/LIBRE/PARACAIDAS, "v": Vector3, "meta": Vector3, "pc": nodo}]
var _otros: Dictionary = {}      ## nodo -> {"y": ultima altura, "pc": paracaidas o null}
var _otros_t := 0.0
var _niebla_antes := -1.0
var _niebla_modo_antes := Environment.FOG_MODE_DEPTH
var _escala_render_antes := -1.0
var _bajo_t := 0
var _espera_t := 0.0
var _tapa: ColorRect = null
var _calentadores: Array = []
var _lejano_antes := -1.0
## Para las pruebas
var saltado_en := -1.0
var abierto_a := -1.0


## LA ESCALA DEL BATTLE ROYALE DE CADA MAPA (2026-10-21, el CUARTO de juguete): <mapa>.br.json con "altura",
## "velocidad", "fuera", "aproximacion", "abrir_solo", "zona" (zona_br.gd) y "hangar" (el avion en el suelo para subir).
## Sin el archivo, lo de la isla.
static func config_br(mapa: String) -> Dictionary:
	var ruta := "res://maps/%s.br.json" % mapa
	if not FileAccess.file_exists(ruta):
		return {}
	var j = JSON.parse_string(FileAccess.get_file_as_string(ruta))
	return j if j is Dictionary else {}


static func quiere_avion() -> bool:
	var args := OS.get_cmdline_user_args()
	for f in ["--sinavion", "--bancofps", "--pruebaisla", "--auditaflotadores", "--botinlan", "--puertas", "--pruebacuras"]:
		if f in args:
			return false
	return true


func empezar(m: Node, w, pl: Node) -> void:
	main = m
	world = w
	jugador = pl
	cfg_br = config_br(String(main.get("current_map")))
	ALTURA = float(cfg_br.get("altura", ALTURA))
	VELOCIDAD = float(cfg_br.get("velocidad", VELOCIDAD))
	FUERA = float(cfg_br.get("fuera", FUERA))
	APROXIMACION = float(cfg_br.get("aproximacion", APROXIMACION))
	ABRIR_SOLO = float(cfg_br.get("abrir_solo", ABRIR_SOLO))
	DIST_CAMARA = float(cfg_br.get("dist_camara", DIST_CAMARA))
	CAIDA = float(cfg_br.get("caida", CAIDA))
	CAIDA_PICADO = float(cfg_br.get("caida_picado", CAIDA_PICADO))
	AVANCE_LIBRE = float(cfg_br.get("avance_libre", AVANCE_LIBRE))
	GIRO_LIBRE = float(cfg_br.get("giro_libre", GIRO_LIBRE))
	_escala_avion = float(cfg_br.get("escala_avion", 1.0))
	var tam: Vector3 = world.get_world_size()
	# LA RUTA: un angulo y un desplazamiento lateral sacados de la semilla. Pasa a menos de 90 m del centro
	# para que cruce media isla, nunca rozando la costa.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Net.semilla_partida) if Net.is_online() else randi()
	var ang := rng.randf() * TAU
	var desv := rng.randf_range(-90.0, 90.0) * minf(1.0, tam.x / 500.0)   # (en un mapa chico, a su escala)
	dir = Vector3(cos(ang), 0.0, sin(ang))
	var centro := Vector3(tam.x * 0.5, ALTURA, tam.z * 0.5) + Vector3(-dir.z, 0.0, dir.x) * desv
	# de borde a borde del cuadrado del mapa, mas FUERA por cada lado
	var tmin := -INF
	var tmax := INF
	for eje in [0, 2]:
		var d: float = dir[eje]
		if absf(d) < 1e-4:
			continue
		var a: float = (-FUERA - centro[eje]) / d
		var b: float = (tam[eje] + FUERA - centro[eje]) / d
		tmin = maxf(tmin, minf(a, b))
		tmax = minf(tmax, maxf(a, b))
	origen = centro + dir * tmin
	largo = tmax - tmin
	# LA RUTA EMPIEZA EN LA COSTA, NO EN LA ESQUINA DEL MAPA. El mundo es un cuadrado pero la isla es
	# redonda, asi que entrando por una esquina el avion se pasaba un cuarto de minuto sobre el mar y lo
	# unico que veias al entrar a la partida era agua (medido: aparecia en 566,561 y tardaba 15 s en
	# llegar a tierra). Se busca la primera TIERRA de la ruta y se arranca unos segundos antes, con la
	# costa ya a la vista.
	var mar_y := float(cfg_br.get("mar", 3.0))
	if main != null and main.get("agua") != null and is_instance_valid(main.agua) and main.agua.get("mar_y") != null:
		mar_y = float(main.agua.get("mar_y"))
	var k_tierra := -1.0
	var k2 := 0.0
	while k2 <= largo:
		var q := origen + dir * k2
		var rr: Dictionary = world.raycast(Vector3(q.x, tam.y - 0.5, q.z), Vector3.DOWN, tam.y)
		if rr.get("hit", false) and float(rr.position.y) > mar_y + 0.4:
			k_tierra = k2
			break
		k2 += 8.0
	if k_tierra > 0.0:
		var recorte: float = maxf(0.0, k_tierra - APROXIMACION * VELOCIDAD)
		origen += dir * recorte
		largo -= recorte
	# cuando esta sobre lo jugable (6 m dentro del borde): solo ahi se puede saltar
	var t0 := INF
	var t1 := -INF
	var k := 0.0
	while k <= largo:
		var p := origen + dir * k
		if p.x > 8.0 and p.z > 8.0 and p.x < tam.x - 8.0 and p.z < tam.z - 8.0:
			t0 = minf(t0, k / VELOCIDAD)
			t1 = maxf(t1, k / VELOCIDAD)
		k += 2.0
	_t_dentro = Vector2(t0, t1)
	if cfg_br.has("hangar"):
		# LA RUTA SALE DEL HANGAR: rumbo fijo, empieza donde acaba la subida y llega hasta la pared de enfrente
		var hg: Dictionary = cfg_br["hangar"]
		var hp: Array = hg["pos"]
		_hangar = Vector3(float(hp[0]), float(hp[1]), float(hp[2]))
		var rb := deg_to_rad(float(hg.get("rumbo", 0.0)))
		dir = Vector3(sin(rb), 0.0, -cos(rb))
		origen = Vector3(_hangar.x, ALTURA, _hangar.z) + dir * SUBIDA_LARGO
		var tl := INF
		for eje in [0, 2]:
			var d2: float = dir[eje]
			if absf(d2) > 1e-4:
				tl = minf(tl, ((tam[eje] + FUERA if d2 > 0.0 else -FUERA) - origen[eje]) / d2)
		largo = maxf(10.0, tl)
		_t_dentro = Vector2(0.0, maxf(2.0, (largo - FUERA - 6.0) / VELOCIDAD))
	_rng_bots = rng
	_montar_ui()
	if cfg_br.has("hangar"):
		_empezar_hangar()
		for f in OS.get_cmdline_user_args():
			if String(f).begins_with("--brhangarfoto="):
				_fotos_hangar.call_deferred(String(f).substr(15))
	else:
		_empezar_espera()
	# los bots, quietos y escondidos hasta que suban (solo quien los manda: los demas los reciben por la red)
	if (not Net.is_online()) or Net.hosting:
		var en = main.get("enemies")
		if en:
			for e in en.get_children():
				if not (e is Node3D):
					continue
				_bots.append({"n": e, "t": rng.randf_range(_t_dentro.x + 2.0, lerpf(_t_dentro.x, _t_dentro.y, 0.92)),
					"fase": AVION, "v": Vector3.ZERO, "meta": Vector3.ZERO, "pc": null})
				e.process_mode = Node.PROCESS_MODE_DISABLED
				e.visible = false
	print("[salto] ruta de %.0f m a %.0f m de altura, sobre el mapa de %.1f a %.1f s · %d bots a bordo" % [
		largo, ALTURA, _t_dentro.x, _t_dentro.y, _bots.size()])


var _rng_bots: RandomNumberGenerator = null


## de momento, en el suelo y con la pantalla tapada (ver ESPERA_T)
func _empezar_espera() -> void:
	estado = ESPERA
	jugador.set("br_control", self)
	jugador.set("invulnerable", true)
	_tp_antes = bool(jugador.get("third_person"))
	_vista_aerea(true)
	# la tapa de la fase de ESPERA (1,5 s) va por dentro de la UI del salto; la cortina de main se
	# quita al despegar. Si el despegue no llegara, se quita igualmente a los 12 s (seguro).
	if main != null and main.has_method("cortina_br"):
		get_tree().create_timer(12.0).timeout.connect(func(): main.cortina_br(false))
	_tapa = ColorRect.new()
	_tapa.color = Color(0.02, 0.03, 0.05, 1.0)
	_tapa.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tapa.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_tapa)
	_ui.move_child(_tapa, 0)
	var cam_j: Camera3D = jugador.get("cam")
	if cam_j:
		var mi := MeshInstance3D.new()
		mi.mesh = AvionScript.malla()
		mi.scale = Vector3.ONE * 0.01
		mi.position = Vector3(0.0, 0.0, -3.0)
		cam_j.add_child(mi)
		_calentadores.append(mi)
		for i in COLORES_PARACAIDAS.size():
			var pc := hacer_paracaidas(i)
			pc.scale = Vector3.ONE * 0.02
			pc.position = Vector3(-0.3 + i * 0.2, -0.2, -4.0)
			cam_j.add_child(pc)
			_calentadores.append(pc)


## EL AVION EN EL SUELO: parado con la rampa bajada; el jugador anda hasta subir
func _empezar_hangar() -> void:
	estado = HANGAR
	_hangar_t = float((cfg_br["hangar"] as Dictionary).get("espera", 40.0))
	avion = AvionScript.new()
	avion.name = "AvionBR"
	add_child(avion)
	avion.scale = Vector3.ONE * _escala_avion
	var ab: AABB = AvionScript.malla().get_aabb()
	_hangar_y = _hangar.y - ab.position.y * _escala_avion
	avion.global_position = Vector3(_hangar.x, _hangar_y, _hangar.z)
	avion.look_at(avion.global_position + dir, Vector3.UP)
	avion.set_volumen(-14.0)
	# la rampa: una placa con bisagra en la panza de la cola, bajada hasta tocar el suelo
	_rampa = Node3D.new()
	avion.add_child(_rampa)
	_rampa.position = Vector3(0.0, AvionScript.RAMPA.y + 0.5, AvionScript.RAMPA.z - RAMPA_LARGO)
	var placa := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.6, 0.3, RAMPA_LARGO)
	placa.mesh = bm
	var mt := StandardMaterial3D.new()
	mt.albedo_color = Color(0.42, 0.46, 0.4)
	mt.roughness = 0.7
	placa.material_override = mt
	placa.position = Vector3(0, 0, RAMPA_LARGO * 0.5)
	_rampa.add_child(placa)
	var h: float = _rampa.position.y - ab.position.y
	_rampa_abierta = asin(clampf(h / RAMPA_LARGO, 0.0, 1.0))
	_rampa.rotation.x = _rampa_abierta
	# SIN LA PLACA VERDE (2026-10-22, pedido: "el modelo del avion ya tiene la escotilla abierta"): se queda el nodo, que
	# solo marca donde estaba
	_rampa.visible = false
	# el jugador, de pie en la salida mirando al avion
	var sal: Array = (cfg_br["hangar"] as Dictionary).get("salida", [_hangar.x, _hangar.y, _hangar.z + 14.0])
	var ps := Vector3(float(sal[0]), float(sal[1]) + 0.2, float(sal[2]))
	(jugador as Node3D).global_position = ps
	var hacia := _hangar - ps
	(jugador as Node3D).rotation.y = atan2(-hacia.x, -hacia.z)
	jugador.set("invulnerable", true)
	_montar_corral((cfg_br["hangar"] as Dictionary).get("corral", []))
	if "--corraltest" in OS.get_cmdline_user_args():
		_corral_test.call_deferred()
	_montar_corral_muros((cfg_br["hangar"] as Dictionary).get("corral_muros", []), float((cfg_br["hangar"] as Dictionary).get("corral_y", 0.0)))
	if main != null and main.has_method("cortina_br"):
		main.cortina_br(false)


## EL CORRAL DE LA ESPERA (2026-10-21, pedido: "arriba de la estanteria; que no se puedan bajar hasta que empiece"):
## muros invisibles alrededor de [x0, z0, x1, z1] desde la y dada; se quitan cuando el avion despega
var _corral: StaticBody3D = null


func _montar_corral(c: Array) -> void:
	if c.size() < 5:
		return
	_corral = StaticBody3D.new()
	_corral.name = "CorralEspera"
	add_child(_corral)
	var x0 := float(c[0])
	var z0 := float(c[1])
	var x1 := float(c[2])
	var z1 := float(c[3])
	var y := float(c[4])
	var alto := 8.0
	var g := 0.4
	for m in [[(x0 + x1) * 0.5, z0 - g * 0.5, x1 - x0 + g * 2.0, g], [(x0 + x1) * 0.5, z1 + g * 0.5, x1 - x0 + g * 2.0, g],
			[x0 - g * 0.5, (z0 + z1) * 0.5, g, z1 - z0], [x1 + g * 0.5, (z0 + z1) * 0.5, g, z1 - z0]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(float(m[2]), alto, float(m[3]))
		cs.shape = bs
		cs.position = Vector3(float(m[0]), y + alto * 0.5, float(m[1]))
		_corral.add_child(cs)


## el corral por tramos (siguen el canto de lo que se pisa; el rectangulo dejaba huecos donde no hay piso)
func _montar_corral_muros(muros: Array, y: float) -> void:
	if muros.is_empty():
		return
	if _corral == null or not is_instance_valid(_corral):
		_corral = StaticBody3D.new()
		_corral.name = "CorralEspera"
		add_child(_corral)
	var alto := 8.0
	var g := 0.5
	for m in muros:
		var a := Vector3(float(m[0]), y, float(m[1]))
		var b := Vector3(float(m[2]), y, float(m[3]))
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(maxf(absf(b.x - a.x) + g, g), alto, maxf(absf(b.z - a.z) + g, g))
		cs.shape = bs
		cs.position = (a + b) * 0.5 + Vector3(0, alto * 0.5 - 0.3, 0)
		_corral.add_child(cs)


## --corraltest: en la espera, empuja al jugador desde el centro de la estanteria hacia 12 rumbos (con choques de verdad,
## move_and_collide) y dice si alguno lo deja caer
func _corral_test() -> void:
	await get_tree().create_timer(6.0).timeout
	var pl: CharacterBody3D = jugador
	var sal: Array = (cfg_br["hangar"] as Dictionary).get("salida", [])
	var y0 := float((cfg_br["hangar"] as Dictionary).get("corral_y", 0.0))
	var caidas := 0
	for k in 12:
		var ang := TAU * k / 12.0
		var d := Vector3(sin(ang), 0, cos(ang))
		for inicio in [Vector3(float(sal[0]), float(sal[1]) + 0.3, float(sal[2])), Vector3(41.2, y0 + 0.4, 112.0)]:
			pl.global_position = inicio
			for _i in 120:
				pl.move_and_collide(d * 0.12)
				pl.move_and_collide(Vector3(0, -0.3, 0))
				await get_tree().physics_frame
			var cae: bool = pl.global_position.y < y0 - 1.0
			caidas += 1 if cae else 0
			print("[corraltest] rumbo %3d desde %s: acaba en %s %s" % [int(rad_to_deg(ang)), str(inicio), str(pl.global_position), "CAE" if cae else "ok"])
	print("[corraltest] %s (%d caidas)" % ["TODO BIEN" if caidas == 0 else "MAL", caidas])
	get_tree().quit()


func _quitar_corral() -> void:
	if is_instance_valid(_corral):
		_corral.queue_free()
	_corral = null


## el pie de la rampa y su bisagra, en el mundo
func _rampa_puntos() -> Array:
	return [_rampa.to_global(Vector3.ZERO), _rampa.to_global(Vector3(0, 0, RAMPA_LARGO))]


## sube: dentro del avion, la rampa se cierra y despega
func _subir() -> void:
	if estado != HANGAR:
		return
	estado = CIERRE
	_fase_t = 0.0
	_tp_antes = bool(jugador.get("third_person"))
	jugador.set("br_control", self)
	jugador.set("invulnerable", true)
	_vista_aerea(true)
	_mostrar_jugador(false)
	_cam = Camera3D.new()
	_cam.far = 900.0
	_cam.fov = 70.0
	add_child(_cam)
	_cam.make_current()
	if main.get("hud") and main.hud.has_method("set_combat_ui_visible"):
		main.hud.set_combat_ui_visible(false)
	Audio.ui("aceptar", -4.0)


## HANGAR, CIERRE y DESPEGUE: true si se ha encargado de este paso
func _paso_hangar(dt: float) -> bool:
	match estado:
		HANGAR:
			if not bool(main.get("loading")):
				_hangar_t -= dt          # (no mientras carga el mapa: el avion se iba antes de que lo vieras)
			# TODOS SUBEN SOLOS AL EMPEZAR (2026-10-22, pedido: "quita eso de subirse; se suben automaticamente"): ya no se
			# sube andando hasta el avion, solo cuando se acaba la espera
			if _hangar_t <= 0.0:
				_subir()
		CIERRE:
			_fase_t += dt
			var c := smoothstep(0.0, 1.0, _fase_t / CIERRE_S)
			_rampa.rotation.x = lerpf(_rampa_abierta, -1.35, c)
			if _fase_t >= CIERRE_S + 0.4:
				_quitar_corral()
				# la rampa, fuera (cerrada asomaba un cuadrado detras de la escotilla durante todo el vuelo)
				if is_instance_valid(_rampa):
					_rampa.visible = false
				estado = DESPEGUE
				_fase_t = 0.0
				avion.set_volumen(-4.0)
		DESPEGUE:
			_fase_t += dt
			var k := clampf(_fase_t / DESPEGUE_S, 0.0, 1.0)
			# rueda acelerando y luego sube (la subida, en la segunda mitad)
			var suelo := Vector3(_hangar.x, _hangar_y, _hangar.z)
			var p: Vector3 = suelo + dir * (SUBIDA_LARGO * k * k)
			p.y = lerpf(_hangar_y, ALTURA, smoothstep(0.35, 1.0, k))
			avion.global_position = p
			var cabeceo := 0.18 * sin(clampf((k - 0.3) / 0.7, 0.0, 1.0) * PI)
			avion.look_at(p + dir + Vector3(0, cabeceo, 0), Vector3.UP)
			if k >= 1.0:
				estado = AVION
				t = 0.0
		_:
			return false
	_actualizar_ui()
	return true



## Se acabo la espera: todos al avion.
func _despegar() -> void:
	for c in _calentadores:
		if is_instance_valid(c):
			c.queue_free()
	_calentadores.clear()
	if is_instance_valid(_tapa):
		_tapa.queue_free()
	_tapa = null
	avion = AvionScript.new()
	avion.name = "AvionBR"
	add_child(avion)
	t = 0.0
	_colocar_avion()
	estado = AVION
	_mostrar_jugador(false)
	_cam = Camera3D.new()
	_cam.far = 900.0
	_cam.fov = 70.0
	add_child(_cam)
	_cam.make_current()
	if main.get("hud") and main.hud.has_method("set_combat_ui_visible"):
		main.hud.set_combat_ui_visible(false)
	avion.set_volumen(-4.0)
	# ya hay algo que mirar: fuera la cortina de "preparando el salto"
	if main != null and main.has_method("cortina_br"):
		main.cortina_br(false)


## Mientras vas en el avion, cayendo o en paracaidas (main.gd dibuja el mundo alrededor de punto_de_vista()).
func en_el_aire() -> bool:
	return estado == AVION or estado == LIBRE or estado == PARACAIDAS or estado == ESPERA or estado == CIERRE or estado == DESPEGUE


func punto_de_vista() -> Vector3:
	var p: Vector3 = avion.global_position if ((estado == AVION or estado == CIERRE or estado == DESPEGUE) and avion) else (jugador as Node3D).global_position
	return Vector3(p.x, minf(p.y, 12.0), p.z)


func _vista_aerea(on: bool) -> void:
	var we = main.get("env")
	var e: Environment = we.environment if we is WorldEnvironment else null
	var cam_j: Camera3D = jugador.get("cam")
	if on:
		if world.has_method("set_render_distance_scale"):
			# no hay getter de la escala: se deduce de la distancia antes y despues (es proporcional)
			var r0: float = float(world.get_stats().get("render_distance", 0.0))
			world.set_render_distance_scale(RENDER_EN_EL_AIRE)
			var r1: float = float(world.get_stats().get("render_distance", 0.0))
			_escala_render_antes = RENDER_EN_EL_AIRE * r0 / r1 if r1 > 0.0 else 1.0
		if e:
			_niebla_antes = e.fog_density
			_niebla_modo_antes = e.fog_mode
			e.fog_mode = Environment.FOG_MODE_EXPONENTIAL   # la del suelo es por profundidad (main._ajustar_niebla)
			e.fog_density = NIEBLA_EN_EL_AIRE
		if cam_j:
			_lejano_antes = cam_j.far
			cam_j.far = LEJANO_EN_EL_AIRE
	else:
		# solo la distancia: main.apply_graphics() lo reaplicaba TODO (sombras, atlas...) y al abrir el
		# paracaidas se iban 3 s a 16 fps (medido con --pruebasalto)
		if _escala_render_antes > 0.0 and world.has_method("set_render_distance_scale"):
			world.set_render_distance_scale(_escala_render_antes)
			_escala_render_antes = -1.0
		if e and _niebla_antes > 0.0:
			e.fog_mode = _niebla_modo_antes
			e.fog_density = _niebla_antes
		if cam_j and _lejano_antes > 0.0:
			cam_j.far = _lejano_antes


func pos_avion() -> Vector3:
	return origen + dir * minf(t * VELOCIDAD, largo)


func _colocar_avion() -> void:
	var p := pos_avion()
	avion.global_position = p
	avion.look_at(p + dir, Vector3.UP)


var _t_cuadro := 0


func _physics_process_medido(dt: float) -> void:
	if _paso_hangar(dt):
		return
	if estado == ESPERA:
		if not bool(main.get("loading")):
			_espera_t += dt
		if _espera_t >= ESPERA_T:
			_despegar()
		_actualizar_ui()
		return
	if avion == null:
		return
	if "--pruebasalto" in OS.get_cmdline_user_args():
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		var ahora := Time.get_ticks_usec()
		if _t_cuadro > 0 and ahora - _t_cuadro > 120000:
			var vp := get_viewport().get_viewport_rid()
			print("[salto] CUADRO LENTO %.0f ms · estado %d · alt %.0f · proceso %.1f fisica %.1f · render cpu %.1f gpu %.1f · objetos %d · prims %d · compilando %d" % [
				(ahora - _t_cuadro) / 1000.0, estado, _altura_sobre_suelo(jugador.global_position),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				RenderingServer.viewport_get_measured_render_time_cpu(vp), RenderingServer.viewport_get_measured_render_time_gpu(vp),
				int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
				int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE) + Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW) + Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION))])
		_t_cuadro = ahora
	t += dt
	_colocar_avion()
	if t * VELOCIDAD > largo + 10.0 and estado != AVION and _bots_en_el_aire() == 0:
		# ya ha pasado todo: el avion se va y el gestor se retira
		avion.queue_free()
		avion = null
		_quitar_ui()
		set_physics_process(false)
		return
	# TE HAN BAJADO EN EL AIRE: se acaba el salto (reapareces ya en tierra, player.gd lo limpia)
	if (estado == LIBRE or estado == PARACAIDAS) and is_instance_valid(jugador) and (bool(jugador.get("spectating")) or float(jugador.get("health")) <= 0.0):
		estado = FIN
		if is_instance_valid(_paracaidas):
			_soltar_paracaidas(_paracaidas, jugador.global_position)
		_paracaidas = null
		_postura(jugador, 0.0, 1.0)
		_vista_aerea(false)
	# se acaba la ruta sobre el mapa: al que siga dentro lo echan
	if estado == AVION and t > _t_dentro.y:
		saltar()
	for b in _bots:
		_paso_bot(b, dt)
	_otros_t -= dt
	if _otros_t <= 0.0:
		_otros_t = 0.2
		_paracaidas_de_otros(0.2)
	_actualizar_ui()


func _process_medido(_dt: float) -> void:
	# la camara del avion: orbita alrededor con la vista del jugador (el raton sigue moviendo `look`)
	if (estado == AVION or estado == CIERRE or estado == DESPEGUE) and _cam and avion and is_instance_valid(jugador):
		var look: Vector2 = jugador.get("look")
		var pitch := clampf(-look.y * 0.8 + 0.25, -0.35, 1.2)
		var b := Basis(Vector3.UP, look.x) * Basis(Vector3.RIGHT, -pitch)
		# (el centro, a la escala del avion: con el de juguete del cuarto, 3 m por encima lo dejaba abajo del todo)
		var centro: Vector3 = avion.global_position + Vector3(0, 3.0 * _escala_avion, 0)
		var quiere: Vector3 = centro + b * Vector3(0, 0, DIST_CAMARA)
		# LA CAMARA NO ATRAVIESA EL TECHO NI LAS PAREDES (2026-10-22, pedido: en la habitacion el avion vuela cerca del
		# techo y al girar la camara se salia por encima): si hay voxels entre el avion y donde iria, se queda antes
		if world != null and world.has_method("raycast"):
			var hacia: Vector3 = quiere - centro
			var r: Dictionary = world.raycast(centro, hacia.normalized(), hacia.length())
			if r.get("hit", false):
				quiere = centro + hacia.normalized() * maxf(0.3, float(r.get("distance", hacia.length())) - 0.5)
		_cam.global_position = quiere
		_cam.look_at(centro, Vector3.UP)
		# EN EL AVION NO SE VE NADA DEL JUGADOR (pedido: "las manos de primera persona flotan arriba del avion"): los brazos
		# y el arma de primera persona los vuelve a enseñar el animador cada cuadro, asi que se esconden cada cuadro
		for n in ["fp_arms", "weapon_pivot"]:
			var nd = jugador.get(n)
			if nd is Node3D and (nd as Node3D).visible:
				(nd as Node3D).visible = false


# --------------------------------------------------------------------------------------------------
# EL JUGADOR (lo llama player.gd desde su _physics_process mientras br_control apunta aqui)
# --------------------------------------------------------------------------------------------------

func paso_jugador(pl: CharacterBody3D, dt: float) -> void:
	var pide_salto: bool = Input.is_action_just_pressed("jump") or bool(pl.get("touch_jump"))
	pl.set("touch_jump", false)
	match estado:
		ESPERA:
			pl.velocity = Vector3.ZERO
		CIERRE, DESPEGUE:
			pl.global_position = avion.to_global(AvionScript.ASIENTO)
			pl.velocity = Vector3.ZERO
		AVION:
			pl.global_position = avion.to_global(AvionScript.ASIENTO)
			pl.velocity = Vector3.ZERO
			if pide_salto:
				if t >= _t_dentro.x:
					saltar()
				elif main.get("hud"):
					main.hud.flash_message("TODAVIA NO ESTAMOS SOBRE LA ISLA")
		LIBRE:
			var alt := _altura_sobre_suelo(pl.global_position)
			var basis: Basis = pl.transform.basis
			var entrada := _entrada(pl)
			var quiere := (basis * Vector3(entrada.x, 0.0, entrada.y)) * AVANCE_LIBRE
			var look: Vector2 = pl.get("look")
			var picado := clampf((-look.y - 0.35) / 0.8, 0.0, 1.0)      # mirar abajo = picar
			quiere *= 1.0 - picado * 0.6
			pl.velocity.x = lerpf(pl.velocity.x, quiere.x, GIRO_LIBRE * dt)
			pl.velocity.z = lerpf(pl.velocity.z, quiere.z, GIRO_LIBRE * dt)
			pl.velocity.y = lerpf(pl.velocity.y, -lerpf(CAIDA, CAIDA_PICADO, picado), 3.0 * dt)
			_mover(pl)
			_postura(pl, lerpf(-1.1, -1.45, picado), dt)
			pl._update_third_person_cam(dt)
			# se abre solo con DOS lecturas seguidas por debajo (una lectura rara no te deja colgado a 120 m)
			_bajo_t = _bajo_t + 1 if alt < ABRIR_SOLO else 0
			if _en_suelo(pl):
				_aterrizar(pl)
			elif _bajo_t >= 2 or (pide_salto and alt > ABRIR_MIN):
				_abrir(pl)
		PARACAIDAS:
			var basis: Basis = pl.transform.basis
			var entrada := _entrada(pl)
			var adelante: float = PLANEO + maxf(0.0, -entrada.y) * (PLANEO_MAX - PLANEO) - maxf(0.0, entrada.y) * PLANEO * 0.7
			var quiere: Vector3 = basis * Vector3(entrada.x * LADO_PARACAIDAS, 0.0, -adelante)
			pl.velocity.x = lerpf(pl.velocity.x, quiere.x, 1.8 * dt)
			pl.velocity.z = lerpf(pl.velocity.z, quiere.z, 1.8 * dt)
			var baja: float = BAJA_PICANDO if entrada.y < -0.5 and float(pl.get("look").y) < -0.3 else BAJA_PARACAIDAS
			pl.velocity.y = lerpf(pl.velocity.y, -baja, 2.2 * dt)
			_mover(pl)
			_postura(pl, 0.0, dt)
			pl._update_third_person_cam(dt)
			if _paracaidas:
				# el paracaidas se inclina con el giro y el avance, como las bandas de verdad
				_paracaidas.rotation.x = lerpf(_paracaidas.rotation.x, -0.18 * (adelante - PLANEO) / PLANEO, 3.0 * dt)
				_paracaidas.rotation.z = lerpf(_paracaidas.rotation.z, -0.25 * entrada.x, 3.0 * dt)
			if _en_suelo(pl):
				_aterrizar(pl)
		_:
			pl.set("br_control", null)


func _entrada(pl) -> Vector2:
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var tm: Vector2 = pl.get("touch_move")
	if tm.length() > 0.02:
		v = tm
	return v.limit_length(1.0)


func _mover(pl: CharacterBody3D) -> void:
	pl.move_and_slide()
	# nadie se sale del mapa cayendo: el borde jugable es el mismo que el del agua
	var tam: Vector3 = world.get_world_size()
	var p := pl.global_position
	p.x = clampf(p.x, 8.0, tam.x - 8.0)
	p.z = clampf(p.z, 8.0, tam.z - 8.0)
	pl.global_position = p
	if world.has_method("set_player_position"):
		world.set_player_position(p)


func _en_suelo(pl: CharacterBody3D) -> bool:
	if pl.is_on_floor():
		return true
	var ag = main.get("agua")
	return ag != null and is_instance_valid(ag) and ag.has_method("profundidad") and float(ag.profundidad(pl.global_position)) > 0.8


func _altura_sobre_suelo(p: Vector3) -> float:
	# EL RAYO SALE DESDE DENTRO DEL MUNDO. Lanzado desde 125 m (el mundo acaba en 57,6) una vez de cada varias
	# daba un impacto falso y el paracaidas se abria a 123 m: se arranca justo debajo del techo del mundo.
	var techo: float = world.get_world_size().y - 0.5
	var desde := Vector3(p.x, minf(p.y + 0.3, techo), p.z)
	var r: Dictionary = world.raycast(desde, Vector3.DOWN, desde.y + 1.0)
	var suelo: float = (desde.y - float(r.distance)) if r.get("hit", false) else 0.0
	# el agua cuenta como suelo (el paracaidas se abre igual sobre el mar)
	var ag = main.get("agua")
	if ag != null and is_instance_valid(ag) and ag.has_method("nivel_en"):
		var sup: float = ag.nivel_en(p)
		if sup > -INF:
			suelo = maxf(suelo, sup)
	return p.y - suelo


func saltar() -> void:
	if estado != AVION or not is_instance_valid(jugador):
		return
	estado = LIBRE
	saltado_en = t
	var pl: CharacterBody3D = jugador
	pl.global_position = avion.to_global(AvionScript.RAMPA)
	pl.velocity = dir * VELOCIDAD * 0.6 + Vector3(0, -4.0, 0)
	# mirando hacia donde va el avion, un poco abajo: se ve la isla nada mas salir
	var look: Vector2 = pl.get("look")
	look.x = atan2(-dir.x, -dir.z)
	look.y = -0.6
	pl.set("look", look)
	pl.rotation.y = look.x
	pl.set("invulnerable", false)
	_mostrar_jugador(true)
	if pl.has_method("set_third_person"):
		pl.set_third_person(true)
	var cam_j: Camera3D = pl.get("cam")
	if cam_j:
		cam_j.make_current()
	if main.get("hud") and main.hud.has_method("set_combat_ui_visible"):
		main.hud.set_combat_ui_visible(true)
	avion.set_volumen(4.0)
	Audio.play3d("grab", pl.global_position, 0.0, 0.1, 30.0, Audio.PRI_MID)
	# CAIDA LIBRE: el aire rugiendo en las orejas hasta abrir el paracaidas
	Audio.bucle("caida", "soldado/viento_caida", true, -4.0)


## la entrada a la sala se cierra en cuanto el avion cierra la escotilla (o despega, en los mapas sin espera en tierra)
func entrada_cerrada() -> bool:
	return not (estado == ESPERA or estado == HANGAR)


## V / el boton de vista mientras manda el salto: en el avion se apunta para cuando aterrices; cayendo, se cambia ya
func alternar_vista() -> void:
	_tp_antes = not _tp_antes
	if (estado == LIBRE or estado == PARACAIDAS) and jugador.has_method("set_third_person"):
		jugador.set_third_person(_tp_antes)
	if main.get("hud") and main.hud.has_method("flash_message"):
		main.hud.flash_message("TERCERA PERSONA" if _tp_antes else "PRIMERA PERSONA")


func _abrir(pl: CharacterBody3D) -> void:
	estado = PARACAIDAS
	abierto_a = _altura_sobre_suelo(pl.global_position)
	_paracaidas = hacer_paracaidas(0)
	pl.add_child(_paracaidas)
	# el tiron: de 32 m/s a 5 de golpe se nota
	pl.velocity.y = -9.0
	if pl.has_method("add_shake"):
		pl.add_shake(0.18)
	Audio.play3d("clickdown", pl.global_position + Vector3(0, 3, 0), 2.0, 0.05, 40.0, Audio.PRI_MID)
	Audio.bucle("caida", "", false)
	Audio.bf3d("soldado/paracaidas_abre", pl.global_position + Vector3(0, 2, 0), 2.0, 60.0, Audio.PRI_HIGH)
	Audio.bf2d("yo/paracaidas_esfuerzo", -4.0, Audio.PRI_MID)
	Audio.bucle("planeo", "soldado/paracaidas_planea", true, -10.0)


func _aterrizar(pl: CharacterBody3D) -> void:
	_vista_aerea(false)               # al tocar suelo, la distancia de dibujo vuelve a la de tus ajustes
	estado = FIN
	pl.set("br_control", null)
	pl.velocity = Vector3(pl.velocity.x * 0.3, 0.0, pl.velocity.z * 0.3)
	_postura(pl, 0.0, 1.0)
	if is_instance_valid(_paracaidas):
		_soltar_paracaidas(_paracaidas, pl.global_position)
	_paracaidas = null
	if pl.has_method("set_third_person"):
		pl.set_third_person(_tp_antes)
	if main.get("hud") and main.hud.has_method("flash_message"):
		main.hud.flash_message("¡EN TIERRA! BUSCA ARMAS")
	Audio.land(0, true)
	Audio.bucle("caida", "", false)
	Audio.bucle("planeo", "", false)
	Audio.bf3d("soldado/paracaidas_aterriza", pl.global_position, 0.0, 30.0, Audio.PRI_MID)
	print("[salto] en tierra en %s tras saltar a los %.1f s (paracaidas a %.0f m)" % [str(pl.global_position), saltado_en, abierto_a])


## El cuerpo en plancha (caida libre) o de pie. Se inclina el avatar entero, no los huesos: el animador
## sigue haciendo lo suyo por encima.
func _postura(pl, ang: float, dt: float) -> void:
	var av = pl.get("avatar")
	if av is Node3D:
		(av as Node3D).rotation.x = lerpf((av as Node3D).rotation.x, ang, clampf(4.0 * dt, 0.0, 1.0))


func _mostrar_jugador(on: bool) -> void:
	var av = jugador.get("avatar")
	if av is Node3D:
		(av as Node3D).visible = on
	var wp = jugador.get("weapon_pivot")
	if wp is Node3D:
		(wp as Node3D).visible = on and not bool(jugador.get("third_person"))


# --------------------------------------------------------------------------------------------------
# LOS BOTS: saltan a su hora, caen hacia un sitio de la isla y al tocar suelo vuelven a pensar
# --------------------------------------------------------------------------------------------------

func _paso_bot(b: Dictionary, dt: float) -> void:
	var e = b["n"]
	if not is_instance_valid(e):
		return
	match int(b["fase"]):
		AVION:
			e.global_position = avion.to_global(AvionScript.ASIENTO) if avion else e.global_position
			if t >= float(b["t"]):
				b["fase"] = LIBRE
				e.visible = true
				e.global_position = avion.to_global(AvionScript.RAMPA) if avion else e.global_position
				b["v"] = dir * VELOCIDAD * 0.6
				# donde quiere caer: un punto de salida a su alcance (se deja arrastrar por la inercia)
				b["meta"] = _meta_bot(e.global_position)
		LIBRE, PARACAIDAS:
			var p: Vector3 = e.global_position
			var alt := _altura_sobre_suelo(p)
			var hacia: Vector3 = b["meta"] - p
			hacia.y = 0.0
			var libre: bool = int(b["fase"]) == LIBRE
			var hv: Vector3 = hacia.limit_length(1.0) * (AVANCE_LIBRE if libre else PLANEO_MAX)
			var v: Vector3 = b["v"]
			v.x = lerpf(v.x, hv.x, 1.5 * dt)
			v.z = lerpf(v.z, hv.z, 1.5 * dt)
			v.y = lerpf(v.y, -(CAIDA if libre else BAJA_PARACAIDAS), 3.0 * dt)
			b["v"] = v
			var paso: Vector3 = v * dt
			if -paso.y >= alt - 0.05:
				# tocando suelo: se le deja justo encima y vuelve a mandar su IA
				e.global_position = p + Vector3(paso.x, -(alt - 0.05), paso.z)
				b["fase"] = FIN
				e.process_mode = Node.PROCESS_MODE_INHERIT
				if e is CharacterBody3D:
					(e as CharacterBody3D).velocity = Vector3.ZERO
				if is_instance_valid(b["pc"]):
					_soltar_paracaidas(b["pc"], e.global_position)
				b["pc"] = null
				return
			e.global_position = p + paso
			if libre and alt < ABRIR_SOLO:
				b["fase"] = PARACAIDAS
				b["v"] = Vector3(v.x, -9.0, v.z)
				var pc := hacer_paracaidas(_bots.find(b) % 4)
				e.add_child(pc)
				b["pc"] = pc


## donde van a caer los bots que ya saltaron (para que el siguiente caiga LEJOS: pedido, "que cada uno vaya en una
## direccion"; antes cada uno iba al punto mas cercano a donde saltaba y caian todos juntos bajo la ruta del avion)
var _metas_bots: Array = []

func _meta_bot(desde: Vector3) -> Vector3:
	if not ("--brbotsantes" in OS.get_cmdline_user_args()):
		var cand: Array = []
		var bt = get_tree().get_first_node_in_group("botin")
		if bt != null and "puntos" in bt:
			for q in bt.puntos:
				cand.append(q["pos"])
		if cand.is_empty() and world.has_method("get_spawn_points"):
			cand = world.get_spawn_points()
		if not cand.is_empty():
			var tam: Vector3 = world.get_world_size()
			var alcance: float = maxf(tam.x, tam.z) * 0.75
			var mejor_q: Vector3 = cand[randi() % cand.size()]
			var mejor_v := -1e9
			for i in 24:
				var q: Vector3 = cand[randi() % cand.size()]
				var d: float = Vector2(q.x - desde.x, q.z - desde.z).length()
				if d > alcance:
					continue
				var lejos := 1e6
				for m in _metas_bots:
					lejos = minf(lejos, Vector2(q.x - m.x, q.z - m.z).length())
				var v: float = minf(lejos, 60.0) - d * 0.05 + randf() * 3.0
				if v > mejor_v:
					mejor_v = v
					mejor_q = q
			_metas_bots.append(mejor_q)
			return mejor_q
	var pts: Array = world.get_spawn_points() if world.has_method("get_spawn_points") else []
	var mejor := Vector3(desde.x, 0, desde.z)
	var md := INF
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 6:
		if pts.is_empty():
			break
		var q: Vector3 = pts[rng.randi() % pts.size()]
		var d: float = Vector2(q.x - desde.x, q.z - desde.z).length()
		if d < md and d < 260.0:
			md = d
			mejor = q
	return mejor


func _bots_en_el_aire() -> int:
	var n := 0
	for b in _bots:
		if int(b["fase"]) != FIN and is_instance_valid(b["n"]):
			n += 1
	return n


# --------------------------------------------------------------------------------------------------
# PARACAIDAS DE LOS DEMAS. No se manda nada por la red: si alguien baja despacio muy por encima del suelo,
# lleva el paracaidas abierto. Vale para los jugadores remotos y para los bots que llegan por la red.
# --------------------------------------------------------------------------------------------------

func _paracaidas_de_otros(dt: float) -> void:
	var lista: Array = []
	for r in Net.remotes.values():
		if is_instance_valid(r) and r is Node3D:
			lista.append(r)
	if Net.is_online() and not Net.hosting:
		var en = main.get("enemies")
		if en:
			for e in en.get_children():
				if e is Node3D:
					lista.append(e)
	var vistos := {}
	for n in lista:
		vistos[n] = true
		var y: float = (n as Node3D).global_position.y
		var d: Dictionary = _otros.get(n, {"y": y, "pc": null})
		var baja: float = (float(d["y"]) - y) / dt
		d["y"] = y
		var alt := _altura_sobre_suelo((n as Node3D).global_position)
		var con: bool = alt > 2.5 and baja > 1.5 and baja < 14.0
		if con and d["pc"] == null:
			var pc := hacer_paracaidas(n.get_instance_id() % 4)
			n.add_child(pc)
			d["pc"] = pc
		elif not con and d["pc"] != null and (alt < 1.5 or baja > 20.0):
			if is_instance_valid(d["pc"]):
				_soltar_paracaidas(d["pc"], (n as Node3D).global_position)
			d["pc"] = null
		_otros[n] = d
	for n in _otros.keys():
		if not vistos.has(n):
			_otros.erase(n)


# --------------------------------------------------------------------------------------------------
# EL PARACAIDAS: casquete de franjas encima y cuatro cordones a los hombros, en voxels de 20 cm como el
# avion. Al aterrizar se suelta y se desploma a un lado en un par de segundos.
# --------------------------------------------------------------------------------------------------

const COLORES_PARACAIDAS := [[Color(0.86, 0.26, 0.18), Color(0.95, 0.92, 0.86)], [Color(0.18, 0.42, 0.78), Color(0.95, 0.92, 0.86)],
	[Color(0.92, 0.66, 0.12), Color(0.22, 0.22, 0.24)], [Color(0.25, 0.6, 0.3), Color(0.95, 0.92, 0.86)]]


## LOS MATERIALES SE COMPARTEN (y se estrenan en la ESPERA): uno por color para todos los paracaidas, en vez
## de un shader nuevo que compilar cada vez que se abria uno.
static var _mats_pc: Dictionary = {}


static func _mat_pc(c: Color) -> StandardMaterial3D:
	var k := c.to_html()
	if not _mats_pc.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.8
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats_pc[k] = m
	return _mats_pc[k]


func hacer_paracaidas(estilo: int) -> Node3D:
	var raiz := Node3D.new()
	raiz.name = "Paracaidas"
	var cols: Array = COLORES_PARACAIDAS[estilo % COLORES_PARACAIDAS.size()]
	var mats := []
	for c in cols:
		mats.append(_mat_pc(c))
	# casquete: 11 celdas en arco, cada una una caja de 0,6 x 0,2 x 3 m
	var n := 11
	var R := 3.4
	for i in n:
		var a := lerpf(-1.05, 1.05, float(i) / float(n - 1))
		var cel := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.66, 0.2, 3.0)
		cel.mesh = bm
		cel.material_override = mats[i % 2]
		cel.position = Vector3(sin(a) * R, 4.2 + cos(a) * R - R * 0.35, 0.0)
		cel.rotation.z = -a
		# SIN SOMBRA: su variante de sombras se compilaba al bajar de ~40 m (donde empiezan las sombras) y se
		# llevaba mas de un segundo entero justo al abrirse (medido con --pruebasalto)
		cel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		raiz.add_child(cel)
	# cordones de los bordes a los hombros
	var mc := _mat_pc(Color(0.9, 0.9, 0.9))
	for s in [-1.0, 1.0]:
		for zz in [-1.3, 1.3]:
			var a: float = 1.05 * s
			var arriba := Vector3(sin(a) * R, 4.2 + cos(a) * R - R * 0.35, zz)
			var abajo := Vector3(0.25 * s, 1.45, 0.0)
			var cord := MeshInstance3D.new()
			var cm := BoxMesh.new()
			var largo_c := arriba.distance_to(abajo)
			cm.size = Vector3(0.04, largo_c, 0.04)
			cord.mesh = cm
			cord.material_override = mc
			cord.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cord.position = (arriba + abajo) * 0.5
			var up := (arriba - abajo).normalized()
			var eje_x := up.cross(Vector3.FORWARD)
			if eje_x.length() < 1e-3:
				eje_x = Vector3.RIGHT
			eje_x = eje_x.normalized()
			cord.basis = Basis(eje_x, up, eje_x.cross(up).normalized())
			raiz.add_child(cord)
	return raiz


func _soltar_paracaidas(pc: Node3D, donde: Vector3) -> void:
	var xf := pc.global_transform
	pc.get_parent().remove_child(pc)
	add_child(pc)
	pc.global_transform = xf
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(pc, "global_position", donde + Vector3(2.5, -2.5, 0.0), 1.6).set_ease(Tween.EASE_IN)
	tw.tween_property(pc, "rotation:z", -1.3, 1.6)
	tw.chain().tween_callback(pc.queue_free)


# --------------------------------------------------------------------------------------------------
# EL AVISO DE ARRIBA: cuanto queda y que tecla
# --------------------------------------------------------------------------------------------------

var _boton_salto: Button = null

func _montar_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)
	_aviso = Label.new()
	_aviso.add_theme_font_size_override("font_size", 26)
	_aviso.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_aviso.add_theme_constant_override("outline_size", 6)
	_aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aviso.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_aviso.position = Vector2(-400, 60)
	_aviso.size = Vector2(800, 80)
	_aviso.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_aviso)
	# EN EL MOVIL, UN BOTON DE VERDAD PARA SALTAR. El aviso decia "[SALTAR] SALTAR DEL AVION", pero en el
	# avion se esconden los mandos tactiles con el resto de la interfaz de combate (set_combat_ui_visible)
	# y no habia ningun SALTAR que pulsar (pedido: "en movil no me pusiste el boton para saltar del avion").
	if Settings.is_touch():
		_boton_salto = Button.new()
		_boton_salto.text = "SALTAR"
		_boton_salto.focus_mode = Control.FOCUS_NONE
		_boton_salto.add_theme_font_size_override("font_size", 34)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1.0, 0.75, 0.15, 0.85)
		sb.set_corner_radius_all(20)
		sb.set_content_margin_all(18)
		_boton_salto.add_theme_stylebox_override("normal", sb)
		_boton_salto.add_theme_stylebox_override("hover", sb)
		var sb2 := sb.duplicate()
		sb2.bg_color = Color(1.0, 0.55, 0.1, 0.95)
		_boton_salto.add_theme_stylebox_override("pressed", sb2)
		_boton_salto.add_theme_color_override("font_color", Color(0.08, 0.06, 0.02))
		_boton_salto.add_theme_color_override("font_pressed_color", Color(0.08, 0.06, 0.02))
		_boton_salto.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		_boton_salto.offset_left = -300
		_boton_salto.offset_top = -190
		_boton_salto.offset_right = -60
		_boton_salto.offset_bottom = -80
		_boton_salto.visible = false
		_boton_salto.pressed.connect(func():
			var pl = main.get("player") if main else null
			if pl != null and is_instance_valid(pl):
				pl.set("touch_jump", true))
		_ui.add_child(_boton_salto)


func _actualizar_ui() -> void:
	if _aviso == null:
		return
	if _boton_salto != null and is_instance_valid(_boton_salto):
		_boton_salto.visible = estado == AVION and t >= _t_dentro.x
	var tecla := "SALTAR" if Settings.is_touch() else "ESPACIO"
	match estado:
		ESPERA:
			_aviso.text = "PREPARANDO EL AVION..."
		HANGAR:
			_aviso.text = "EL AVIÓN DESPEGA EN %d s" % int(ceil(maxf(0.0, _hangar_t)))
		CIERRE:
			_aviso.text = "CERRANDO LA ESCOTILLA..."
		DESPEGUE:
			_aviso.text = "¡DESPEGANDO!"
		AVION:
			if t < _t_dentro.x:
				_aviso.text = "LLEGANDO A LA ISLA · %d s" % int(ceil(_t_dentro.x - t))
			else:
				_aviso.text = "[%s] SALTAR DEL AVION\nte echan en %d s" % [tecla, int(ceil(_t_dentro.y - t))]
		LIBRE:
			_aviso.text = "CAIDA LIBRE · %d m\n[%s] ABRIR PARACAIDAS · mira abajo para picar" % [
				int(_altura_sobre_suelo(jugador.global_position)), tecla]
		PARACAIDAS:
			_aviso.text = "PARACAIDAS · %d m" % int(_altura_sobre_suelo(jugador.global_position))
		_:
			_aviso.text = ""


func _quitar_ui() -> void:
	if is_instance_valid(_ui):
		_ui.queue_free()
	_ui = null
	_aviso = null
	_boton_salto = null

## (medida para los bancos: lo que cuesta este nodo por fotograma, en Prof)
func _process(dt: float) -> void:
	var _tm := Time.get_ticks_usec()
	_process_medido(dt)
	Prof.add("salto_br", Time.get_ticks_usec() - _tm)

## (medida para los bancos: lo que cuesta este nodo por fotograma, en Prof)
func _physics_process(dt: float) -> void:
	var _tm := Time.get_ticks_usec()
	_physics_process_medido(dt)
	Prof.add("salto_br.fis", Time.get_ticks_usec() - _tm)


## --brhangarfoto=<carpeta> (con un mapa con "hangar"): fotos del avion en el suelo, del cierre, del despegue y del vuelo;
## el jugador sube solo a los 3 s
func _fotos_hangar(carpeta: String) -> void:
	DirAccess.make_dir_recursive_absolute(carpeta)
	await get_tree().create_timer(4.0).timeout
	var cam := Camera3D.new()
	add_child(cam)
	cam.far = 900.0
	var foto := func(nombre: String, desde: Vector3, mira: Vector3):
		cam.global_position = desde
		cam.look_at(mira, Vector3.UP)
		cam.make_current()
		for _k in 3:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(carpeta.path_join("br_%s.png" % nombre))
	await foto.call("hangar", _hangar + Vector3(-22.0, 10.0, -14.0), _hangar + Vector3(0, 2.0, 0))
	await foto.call("salida", Vector3(42.0, 3.0, 114.0), Vector3(50.0, 4.0, 60.0))
	await foto.call("oso", Vector3(64.0, 6.0, 108.0), Vector3(71.0, 6.0, 87.0))
	await foto.call("arriba", Vector3(50.0, 40.0, 118.0), Vector3(50.0, 0.0, 50.0))
	await foto.call("cama", Vector3(40.0, 16.0, 70.0), Vector3(10.0, 6.0, 30.0))
	await foto.call("escritorio", Vector3(60.0, 18.0, 40.0), Vector3(92.0, 14.0, 24.0))
	await foto.call("castillo", Vector3(30.0, 8.0, 80.0), Vector3(41.0, 4.0, 62.0))
	await foto.call("ropero", Vector3(70.0, 10.0, 96.0), Vector3(95.0, 10.0, 104.0))
	await foto.call("ventana", Vector3(50.0, 12.0, 40.0), Vector3(50.0, 24.0, 1.0))
	await foto.call("rampa", _hangar + dir * -18.0 + Vector3(6.0, 4.0, 0.0), _hangar + dir * -8.0)
	(jugador as Node3D).global_position = _rampa_puntos()[1] + Vector3(0, 0.3, 0)
	await get_tree().create_timer(1.2).timeout
	await foto.call("cierre", _hangar + Vector3(16.0, 6.0, 18.0), _hangar)
	await get_tree().create_timer(CIERRE_S + 4.0).timeout
	await foto.call("despegue", avion.global_position + Vector3(25.0, 4.0, 12.0), avion.global_position)
	await get_tree().create_timer(5.0).timeout
	print("[brhangar] estado %d · avion en %s · jugador en %s" % [estado, str(avion.global_position), str((jugador as Node3D).global_position)])
	if _cam:
		_cam.make_current()
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(carpeta.path_join("br_vuelo.png"))
	saltar()
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(carpeta.path_join("br_caida.png"))
	await get_tree().create_timer(8.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(carpeta.path_join("br_suelo.png"))
	print("[brhangar] estado %d · jugador en %s" % [estado, str((jugador as Node3D).global_position)])
	get_tree().quit()
