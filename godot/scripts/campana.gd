extends "res://scripts/pve.gd"
## CAMPAÑA COOPERATIVA (tipo Left 4 Dead): del tejado de los apartamentos al helicoptero de la azotea del
## hospital, a traves de la ciudad. Mapa: campana_huida (tools/generar_mapa_campana.py), que deja el recorrido
## y los puntos de la historia en res://maps/campana_huida.campana.json.
##
## Hereda del PvE todo lo que no es la historia: como salen las criaturas y viajan por red, reanimar a los
## caidos, la derrota cuando caen todos y la pantalla final. Lo que cambia es el CEREBRO: en vez de oleadas,
## un DIRECTOR como el de Left 4 Dead, que mira hasta donde habeis llegado y saca a los bichos DELANTE del
## grupo y fuera de vuestra vista:
##   * ambiente: unos cuantos infectados comunes siempre rondando por delante
##   * especiales cada cierto tiempo (saltador, arrastrado, gordo, escupidor, araña)
##   * hordas cada dos minutos y pico ("¡HORDA!"), por delante y por detras
##   * los EVENTOS del mapa: el coche con alarma, el refugio (punto de control: te curas, recargas y los
##     caidos vuelven), el PORTON (hay que abrirlo a mano y aguantar la horda hasta que sube) y el FINAL
##     (la radio, las oleadas con dos Tanks y el helicoptero)
##
## En red manda el anfitrion (como en el PvE): el lleva el director y la historia, y se la cuenta a todos
## (Net.net_campana). Los invitados ven los carteles, las puertas y el helicoptero, y lo que usan (el cuadro
## del porton, la radio) se lo piden al anfitrion (Net.net_campana_pide).

const RUTA_JSON := "res://maps/%s.campana.json"
const ObjetoCampana := preload("res://scripts/objeto_campana.gd")
## los mandos de verdad (palancas, botones, botoneras, volantes...): mandos.gd
const Mandos := preload("res://scripts/mandos.gd")
## EL HELICOPTERO DE VERDAD (2026-09-24, pedido: "el sonido del helicoptero es muy feo, parece generado"): los
## bucles del de No Mercy de Left 4 Dead 2 (sourcesounds/left4dead2, temporales como el resto) y las voces del
## piloto en la radio
const HELI_BUCLES := ["res://sounds/l4d2/heli/bucle1.ogg", "res://sounds/l4d2/heli/bucle_capa1.ogg"]

# el director
const AMBIENTE_VIVOS := 14          ## infectados de ambiente a la vez (DORMIDOS: esperan a que llegues)
const AMBIENTE_CADA := 1.6          ## s entre salidas de ambiente
const ESPECIAL_CADA := Vector2(35.0, 60.0)
const HORDA_CADA := Vector2(95.0, 150.0)
const HORDA_TAM := 16
const MAX_ESPECIALES := 2
const ESPECIALES := ["cazador", "fumador", "gordo", "escupidor", "jinete", "cargador", "cazador", "fumador"]
const PORTON_S := 55.0              ## lo que tarda el porton en abrirse con la horda encima
const HELI_ABORDAR := 7.0           ## m del centro del helipuerto para estar "dentro"
## EL FINAL: oleadas en orden. Cuando se limpia la ultima (la del segundo Tank) llega el helicoptero.
const FINAL := [
	[["zombi", 14], ["corredor", 4], ["gordo", 1]],
	[["zombi", 16], ["corredor", 6], ["cazador", 1], ["escupidor", 1]],
	[["tanque", 1], ["zombi", 8]],
	[["zombi", 18], ["corredor", 6], ["fumador", 1], ["jinete", 1]],
	[["zombi", 20], ["corredor", 8], ["cazador", 1], ["gordo", 1]],
	[["tanque", 1], ["bruto", 1], ["zombi", 10], ["corredor", 4]],
]

var cfg: Dictionary = {}
var ruta: Array = []                ## [Vector3]
var ruta_nombres: Array = []
var progreso := 0                   ## punto de la ruta mas avanzado del grupo
var fase := "inicio"                ## inicio, camino, refugio, porton, abriendo, camino_hospital, radio, final, helicoptero, fin
var _dir_t := 0.0
var _amb_t := 0.0
var _esp_t := 40.0
var _horda_t := 120.0
var _texto := ""
var _porton: StaticBody3D = null
var _puerta_refugio: StaticBody3D = null
var _abrir_t := 0.0
var _final_ola := -1
var _final_espera := 0.0
var _heli: Node3D = null
var _heli_t := 0.0
var _heli_rotor: Node3D = null
var _punto_control := Vector3.ZERO  ## donde se reaparece (el ultimo refugio)
var _alarma_coche_sono := false
var _usables: Array = []            ## [{id, pos, texto}] lo que se puede usar ahora
var _usable_mirado := ""
var _pista_idx: Array = []          ## por cada pista de salida, el punto de ruta mas cercano
var _sonido_porton: AudioStreamPlayer3D = null
var _alarma_nodo: AudioStreamPlayer3D = null
var _prueba := false
var _tanda_t := 12.0
var _bruja_cada := 100.0


func setup(p_jugador: Node3D, p_world, p_hud, p_contenedor: Node3D) -> void:
	_leer_mapa()
	super.setup(p_jugador, p_world, p_hud, p_contenedor)
	_prueba = "--campanatest" in OS.get_cmdline_user_args()
	_montar_escena()
	if not Net.campana_evento.is_connected(_on_evento):
		Net.campana_evento.connect(_on_evento)
	if _soy_host and not Net.campana_pide.is_connected(_on_pide):
		Net.campana_pide.connect(_on_pide)
	_punto_control = _v(cfg.get("salida", [0, 0, 0])) + Vector3(0, 0.3, 0)
	_mensaje(String(cfg.get("mensaje_inicio", "LA HUIDA · llegad a la azotea del hospital")))
	_texto = String(cfg.get("texto_inicio", "Baja del tejado y cruza la ciudad hasta el HOSPITAL"))
	_objetivo(_texto)
	_musica_montar()
	# UN BOTIQUIN POR CABEZA, como en Left 4 Dead; y quien te cure te lo dice por aqui
	jugador.set("max_botiquines", 1)
	CriaturaScript.sin_romper = true
	if not Net.cura_otro.is_connected(_on_cura_otro):
		Net.cura_otro.connect(_on_cura_otro)
	if "--curaotrotest" in OS.get_cmdline_user_args():
		_prueba_cura_otro()
	_montar_equipo()
	# LOS BOTIQUINES Y LA MUNICION: los reparte el anfitrion; el invitado los pide al llegar (si el anfitrion
	# los mando antes de que este cargara, se los habria perdido)
	if _soy_host:
		_repartir_objetos()
	else:
		Net.net_campana_pide("objetos")
	# el helicoptero de las noticias pasa por encima al empezar y os dice a donde ir (como en Left 4 Dead)
	get_tree().create_timer(4.0).timeout.connect(_al_empezar)
	# LA ENTRADA DE CINE (cinematica_campana.gd). Sin ella en las pruebas y sin pantalla
	var args := OS.get_cmdline_user_args()
	var hay_prueba := false
	for x in args:
		if x.ends_with("test") or x.begins_with("--campanafoto") or x == "--sinintro" or x.begins_with("--fototrepar"):
			hay_prueba = true
	if (DisplayServer.get_name() != "headless" and not hay_prueba) or "--intro" in args:
		var cin: Node = preload("res://scripts/cinematica_campana.gd").new()
		add_child(cin)
		cin.empezar.call_deferred(self)
	print("[campana] empieza: %d puntos de ruta, %d pistas de salida" % [ruta.size(), _pistas.size()])
	if _prueba:
		prueba_recorrido.call_deferred()
	if "--gordoportontest" in OS.get_cmdline_user_args():
		_prueba_gordo_porton.call_deferred()
	if "--dormidostest" in OS.get_cmdline_user_args():
		_prueba_dormidos.call_deferred()
	if "--finaltest" in OS.get_cmdline_user_args():
		_prueba_final.call_deferred()
	if "--objetostest" in OS.get_cmdline_user_args():
		_prueba_objetos.call_deferred()
	if "--tocausartest" in OS.get_cmdline_user_args():
		_toca_usar_test.call_deferred()
	for f in OS.get_cmdline_user_args():
		if String(f).begins_with("--campanafoto="):
			_foto(String(f).substr(14))


## --tocausartest (con --touch, en el 1: --map=campana_huida --pve "--ir=antes del porton"): planta al jugador delante
## del boton del porton, espera el aviso de USAR y lo TOCA con un toque de pantalla de verdad (InputEventScreenTouch:
## el proyecto no emula el raton desde el tacto). Tiene que empezar a abrirse el porton. Y una foto del aviso.
func _toca_usar_test() -> void:
	await get_tree().create_timer(12.0).timeout
	if _mando_porton == null or not is_instance_valid(_mando_porton):
		print("[tocausar] sin mando del porton")
		get_tree().quit()
		return
	if fase != "porton":
		_poner_fase("porton", "")
	var f: Vector3 = _mando_porton.global_transform.basis.z
	jugador.global_position = _mando_porton.global_position + Vector3(f.x, 0, f.z).normalized() * 1.4 - Vector3(0, 1.45, 0)
	var d: Vector3 = _mando_porton.global_position - (jugador.global_position + Vector3.UP * 1.6)
	var look: Vector2 = jugador.get("look")
	look.x = atan2(-d.x, -d.z)
	look.y = atan2(d.y, Vector2(d.x, d.z).length())
	jugador.set("look", look)
	jugador.rotation.y = look.x
	await get_tree().create_timer(1.5).timeout
	var vis: bool = _aviso != null and is_instance_valid(_aviso) and _aviso.visible
	print("[tocausar] tactil %s · aviso visible %s · mirado '%s' · fase %s" % [str(Settings.is_touch()), str(vis), _usable_mirado, fase])
	get_viewport().get_texture().get_image().save_png("user://tocausar.png")
	if not vis:
		get_tree().quit()
		return
	var c: Vector2 = _aviso.get_global_rect().position + Vector2(_aviso._radio(), _aviso._radio())
	for pr in [true, false]:
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.position = c
		t.pressed = pr
		Input.parse_input_event(t)
		await get_tree().process_frame
	await get_tree().create_timer(0.8).timeout
	print("[tocausar] tras el toque: fase %s (tiene que ser abriendo) · %s" % [fase, ProjectSettings.globalize_path("user://tocausar.png")])
	get_tree().quit()


## --campanafoto=ruta.png;x;y;z;mira_x;mira_y;mira_z[|otra;...]: planta la camara (el jugador) en cada punto
## mirando al otro, sin HUD, y guarda la captura. Para la tarjeta del lobby y para revisar el mapa sin jugar.
func _foto(arg: String) -> void:
	Settings.focus_mode = 0          # fotos nitidas (solo esta sesion: no se guarda en los ajustes)
	await get_tree().create_timer(9.0).timeout
	if hud and not ("--fotohud" in OS.get_cmdline_user_args()):
		hud.visible = false
		if _capa_equipo:
			_capa_equipo.visible = false
		for n in ["weapon_pivot", "fp_arms"]:
			var nd = jugador.get(n)
			if nd != null and is_instance_valid(nd):
				nd.visible = false
	for tramo in arg.split("|"):
		var p := tramo.split(";")
		if p.size() < 7:
			continue
		var desde := Vector3(float(p[1]), float(p[2]), float(p[3]))
		var hacia := Vector3(float(p[4]), float(p[5]), float(p[6]))
		jugador.global_position = desde
		jugador.set("invulnerable", true)
		var d := hacia - (desde + Vector3.UP * 1.6)
		var look: Vector2 = jugador.get("look")
		look.x = atan2(-d.x, -d.z)
		look.y = atan2(d.y, Vector2(d.x, d.z).length())
		jugador.set("look", look)
		jugador.rotation.y = look.x
		await get_tree().create_timer(3.0).timeout
		if "--fotovendar" in OS.get_cmdline_user_args() and String(jugador.get("curando")) == "":
			# a mitad de vendarse: herido, con un botiquin, y la foto a los 2,5 s del gesto
			jugador.coger_cura("botiquin", 1)
			jugador.health = 40.0
			jugador.health_changed.emit(jugador.health)
			jugador.usar_cura("botiquin")
			await get_tree().create_timer(2.5).timeout
		var mn = jugador.get_parent()
		if "--fotofrente" in OS.get_cmdline_user_args() and jugador.get("avatar"):
			# el personaje visto desde delante, como lo ve un companero (su cuerpo en tercera persona)
			jugador.set("third_person", true)
			jugador.avatar.set_body_visible(true)
			jugador.avatar.set("_first_person", false)
			jugador.avatar.play_vendar(3.0)
			var cf := Camera3D.new()
			add_child(cf)
			var fr: Vector3 = -jugador.global_basis.z
			cf.global_position = jugador.global_position + fr * 2.0 + Vector3(0.6, 1.5, 0)
			cf.look_at(jugador.global_position + Vector3(0, 1.2, 0))
			cf.make_current()
			await get_tree().create_timer(0.1).timeout
			var wr = jugador.avatar.get("weapon_root")
			print("[campanafoto] arma del muneco: %s visible %s" % [str(wr), str(wr.visible) if wr else "-"])
		print("[campanafoto] noche=%s sol=%.2f rot=%s" % [str(mn.get("night")), float(mn.sun.light_energy) if mn.get("sun") else -1.0, str(mn.sun.rotation_degrees) if mn.get("sun") else ""])
		var pool: Array = mn.get("_lamp_pool") if mn.get("_lamp_pool") != null else []
		var vis := 0
		var cerca := INF
		for lz in pool:
			if is_instance_valid(lz) and lz.visible:
				vis += 1
				cerca = minf(cerca, (lz as Node3D).global_position.distance_to(desde))
		var orden := pool.filter(func(q): return is_instance_valid(q))
		orden.sort_custom(func(a, b): return (a as Node3D).global_position.distance_to(desde) < (b as Node3D).global_position.distance_to(desde))
		for q in orden.slice(0, 3):
			var lq := q as Light3D
			print("[campanafoto]   %s en %s a %.1f m · energia %.2f · apunta %s · alcance %s · cono %s · fade %.0f" % [lq.get_class(), str(lq.global_position.snapped(Vector3.ONE * 0.1)),
				lq.global_position.distance_to(desde), lq.light_energy, str((-lq.global_transform.basis.z).snapped(Vector3.ONE * 0.01)),
				str(lq.get("spot_range")), str(lq.get("spot_angle")), lq.distance_fade_begin])
		print("[campanafoto] farolas: %d en el pool, %d visibles, la mas cercana a %.1f m, posiciones cargadas %d" % [pool.size(), vis, cerca, (mn.get("_lamp_pos") as Array).size() if mn.get("_lamp_pos") != null else -1])
		get_viewport().get_texture().get_image().save_png(p[0])
		print("[campanafoto] ", p[0])
	get_tree().quit()


func _mm(color: Color, metal: float, rugoso: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = rugoso
	return m


func _v(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() >= 3 else Vector3.ZERO


func _leer_mapa() -> void:
	var r := RUTA_JSON % _mapa()
	if not FileAccess.file_exists(r):
		push_warning("[campana] falta %s" % r)
		return
	var j = JSON.parse_string(FileAccess.get_file_as_string(r))
	if j is Dictionary:
		cfg = j
	for p in cfg.get("ruta", []):
		ruta.append(_v(p))
		ruta_nombres.append(String(p[3]) if p.size() > 3 else "")


# --- lo del PvE que la campaña NO tiene: los puestos de empezar oleada y la tienda -------------------------
func _montar_puestos() -> void:
	pass

func _mostrar_puestos(_on: bool) -> void:
	pass

func _mandar_puestos() -> void:
	pass

func _marcar_boton(_on: bool) -> void:
	pass


# ======================================================================================================
# LA ESCENA: el porton, la puerta del refugio, la alarma del coche
# ======================================================================================================
## LOS MANDOS DEL PORTON Y DE LA RADIO (mandos.gd, 2026-09-28): en el cuadro del mapa, atornillados a su cara.
## Cada episodio dice cual y donde: [tipo, punto de partida, hacia donde mira]; [] = ninguno (la radio del 1 ya es
## una radio). El aviso de USAR sale encima del mando.
var _mando_porton: Node3D = null
var _mando_radio: Node3D = null

func _mando_porton_def() -> Array:
	var b = (cfg.get("porton", {}) as Dictionary).get("boton", null)
	return [] if b == null else ["boton", _v(b) + Vector3(0, 1.5, -0.9), Vector3(0, 0, -1)]


func _mando_radio_def() -> Array:
	return []


func _montar_mandos_base() -> void:
	for cual in ["porton", "radio"]:
		var d: Array = _mando_porton_def() if cual == "porton" else _mando_radio_def()
		if d.is_empty():
			continue
		var m := Mandos.en_pared(world, String(d[0]), self, d[1], d[2])
		if cual == "porton":
			_mando_porton = m
		else:
			_mando_radio = m


## Donde sale el aviso de USAR de un mando (encima de el); si no hay mando, `si_no`
func _pos_mando(m: Node3D, si_no: Vector3) -> Vector3:
	return m.global_position + m.global_transform.basis.z * 0.15 if m != null and is_instance_valid(m) and m.is_inside_tree() else si_no


func _montar_escena() -> void:
	_montar_mandos_base()
	var por: Dictionary = cfg.get("porton", {})
	if not por.is_empty():
		var r: Array = por["rect"]
		var x0: float = float(r[0])
		var z0: float = float(r[1]) + 0.6
		var x1: float = float(r[2])
		var z1: float = float(r[3]) - 0.6
		var alto: float = float(por.get("alto", 5.6))
		_porton = _muro_objeto(Vector3((x0 + x1) / 2, 1.0 + alto / 2, (z0 + z1) / 2), Vector3(x1 - x0, alto, z1 - z0),
			Color(0.22, 0.24, 0.22), true)
		# LAS CRIATURAS TAMBIEN LO RESPETAN (se mueven por los voxels y el porton no lo es: lo cruzaban)
		CriaturaScript.barreras.clear()
		_barrera_porton = AABB(Vector3(x0 - 0.3, 0.0, float(r[1]) - 1.0), Vector3(x1 - x0 + 0.6, alto + 2.0, float(r[3]) - float(r[1]) + 2.0))
		CriaturaScript.barreras.append(_barrera_porton)
		_porton.name = "Porton"
		_sonido_porton = AudioStreamPlayer3D.new()
		_sonido_porton.unit_size = 8.0
		_sonido_porton.max_distance = 120.0
		_porton.add_child(_sonido_porton)
	var ref: Dictionary = cfg.get("refugio", {})
	if not ref.is_empty():
		var ps: Array = ref["puerta_salida"]
		_puerta_refugio = _muro_objeto(Vector3(float(ps[0]), 1.0 + 1.35, float(ps[1]) - 0.2), Vector3(1.8, 2.7, 0.12),
			Color(0.55, 0.06, 0.05), false)
		_puerta_refugio.name = "PuertaRefugio"
		# LA DE ENTRADA, abierta de par en par hasta que estais todos dentro: entonces SE CIERRA (como la del
		# refugio de Left 4 Dead) y ya no se vuelve atras. Gira sobre su bisagra; es solida y los bichos
		# tampoco la cruzan.
		var pe: Array = ref["puerta_entrada"]
		_bisagra_entrada = Node3D.new()
		_bisagra_entrada.name = "PuertaEntradaRefugio"
		add_child(_bisagra_entrada)
		_bisagra_entrada.global_position = Vector3(float(pe[0]) - 0.9, 1.0 + 1.35, float(pe[1]) + 0.2)
		var hoja := _muro_objeto(Vector3.ZERO, Vector3(1.8, 2.7, 0.12), Color(0.55, 0.06, 0.05), false)
		hoja.reparent(_bisagra_entrada, false)
		hoja.position = Vector3(0.9, 0, 0)
		var pomo := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = 0.05
		pm.height = 0.1
		pomo.mesh = pm
		pomo.material_override = _mm(Color(0.8, 0.7, 0.3), 0.3, 0.9)
		pomo.position = Vector3(0.7, -0.25, 0.09)
		hoja.add_child(pomo)
		_bisagra_entrada.rotation.y = -PI / 2          # abierta hacia dentro


## Un muro que pone el juego (porton, puerta): caja con colision y su malla. `rayas`: franjas de peligro.
func _muro_objeto(centro: Vector3, tam: Vector3, color: Color, rayas: bool) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = tam
	cs.shape = bs
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = tam
	mi.mesh = bm
	mi.material_override = _mm(color, 0.2, 0.8)
	sb.add_child(mi)
	if rayas:
		for i in 6:
			var r := MeshInstance3D.new()
			var rm := BoxMesh.new()
			rm.size = Vector3(tam.x + 0.04, 0.35, tam.z * 0.98)
			r.mesh = rm
			r.material_override = _mm(Color(0.85, 0.65, 0.05) if i % 2 == 0 else Color(0.05, 0.05, 0.05), 0.3, 0.4)
			r.position = Vector3(0, -tam.y / 2 + 0.4 + i * 0.35, 0)
			sb.add_child(r)
	add_child(sb)
	sb.global_position = centro
	return sb


# ======================================================================================================
# CADA CUADRO
# ======================================================================================================
func _process(dt: float) -> void:
	var _pf0 := Time.get_ticks_usec()
	_process_sin_medir(dt)
	Prof.add("campana", Time.get_ticks_usec() - _pf0)


func _process_sin_medir(dt: float) -> void:
	_aliados_tick(dt)
	_equipo_tick(dt)
	_heli_tick(dt)
	_usables_tick()
	_musica_tick(dt)
	if _en_red and not _soy_host:
		return
	if terminado:
		if _en_red:
			_red_t -= dt
			if _red_t <= 0.0:
				_red_t = 0.1
				_mandar_estados()
		return
	if world == null or not is_instance_valid(jugador):
		return
	_vivos = _vivos.filter(func(c): return is_instance_valid(c) and not c.muerta)
	if _en_red:
		_red_t -= dt
		if _red_t <= 0.0:
			_red_t = 0.1
			_mandar_estados()
		_estado_t -= dt
		if _estado_t <= 0.0:
			_estado_t = 0.5
			Net.net_estado_pve(0, _vivos.size(), 0, false, _texto, bajas)
	_rescatar_atascados(dt)
	_dir_t -= dt
	if _dir_t <= 0.0:
		_dir_t = 0.5
		_medir_progreso()
		_historia()
		_objetivo(_texto)
		_objetivo_tick()
		_tank_tick()
	_director(dt)
	# la cola (hordas, oleadas del final) sale poco a poco
	_salir_t -= dt
	if not _cola.is_empty() and _salir_t <= 0.0 and _vivos.size() < MAX_VIVOS + 6:
		_salir_t = 0.35
		var t: String = String(_cola.pop_front())
		var n_antes := _vivos.size()
		_trepa_desde = null
		var donde = _punto_para(t)
		_sacar(t, donde)
		# LOS DEL FINAL SUBEN TREPANDO por la fachada y saltan el peto
		if _trepa_desde != null and donde != null and _vivos.size() > n_antes and _vivos.back().has_method("trepar"):
			_vivos.back().trepar(_trepa_desde, donde)


# ======================================================================================================
# DONDE ESTA EL GRUPO
# ======================================================================================================
func _jugadores_vivos() -> Array:
	var out: Array = []
	if is_instance_valid(jugador) and not bool(jugador.get("spectating")) and float(jugador.get("health")) > 0.0:
		out.append(jugador)
	if _en_red:
		for id in Net.remotes.keys():
			var r = Net.remotes[id]
			if is_instance_valid(r) and not bool(Net.dead_players.get(int(id), false)):
				out.append(r)
	return out


func _indice_ruta(p: Vector3) -> int:
	var mejor := 0
	var d := INF
	for i in ruta.size():
		var q: Vector3 = ruta[i]
		# la altura pesa: en el edificio de la salida cada planta es otro punto de la ruta
		var dd := Vector2(p.x - q.x, p.z - q.z).length() + absf(p.y - q.y) * 3.0
		if dd < d:
			d = dd
			mejor = i
	return mejor


func _medir_progreso() -> void:
	for pl in _jugadores_vivos():
		progreso = maxi(progreso, _indice_ruta((pl as Node3D).global_position))


func _todos_dentro(rect: Array, y_min := -INF) -> bool:
	var vivos := _jugadores_vivos()
	if vivos.is_empty():
		return false
	for pl in vivos:
		var p: Vector3 = (pl as Node3D).global_position
		if p.x < float(rect[0]) or p.x > float(rect[2]) or p.z < float(rect[1]) or p.z > float(rect[3]) or p.y < y_min:
			return false
	return true


func _alguien_cerca(p: Vector3, radio: float) -> bool:
	for pl in _jugadores_vivos():
		if (pl as Node3D).global_position.distance_to(p) < radio:
			return true
	return false


# ======================================================================================================
# LA HISTORIA (solo el anfitrion)
# ======================================================================================================
func _historia() -> void:
	var nombre := String(ruta_nombres[progreso]) if progreso < ruta_nombres.size() else ""
	match fase:
		"inicio":
			if progreso >= 2:
				_poner_fase("camino", "Baja a la calle y llega al REFUGIO del metro")
		"camino":
			_alarma_coche()
			var ref: Dictionary = cfg.get("refugio", {})
			if not ref.is_empty() and _todos_dentro(ref["rect"]):
				_poner_fase("refugio", "")
				_llegar_al_refugio()
		"refugio":
			if nombre == "calle Segunda" or progreso >= _indice_de("calle Segunda"):
				_poner_fase("porton", "Sigue por la calle Segunda hacia el oeste")
		"porton":
			var bot: Vector3 = _v((cfg.get("porton", {}) as Dictionary).get("boton", [0, 0, 0]))
			if _alguien_cerca(bot, 22.0):
				_texto = "EL PORTÓN ESTÁ CERRADO · usa el cuadro de mando (rojo) para abrirlo"
		"abriendo":
			pass
		"camino_hospital":
			if progreso >= _indice_de("urgencias"):
				_texto = "Sube por la escalera hasta la AZOTEA del hospital"
			var az: Array = cfg.get("azotea_hospital", [])
			if az.size() >= 5 and _alguien_cerca(_v(cfg.get("radio", [0, 0, 0])), 30.0):
				for pl in _jugadores_vivos():
					if (pl as Node3D).global_position.y > float(az[1]) - 0.5:
						_poner_fase("radio", "Usa la RADIO de la caseta para pedir el rescate")
						break
		"final":
			_final_tick()
		"helicoptero":
			_trepar_a_la_azotea()
			_abordar_tick()


## ============================================================================================
## HACIA DONDE IR (2026-09-24, pedido: "no se donde ir, subi arriba y no encontraba la radio"). El
## anfitrion decide el objetivo de cada momento y lo manda a todos; cada uno lo pinta con la marca amarilla
## del HUD (circulo, nombre y metros; flecha en el borde si queda fuera de la vista) y un punto amarillo en
## el minimapa (flecha en su borde si esta lejos).
## ============================================================================================
const AMARILLO := Color(1.0, 0.84, 0.1)
var _obj_pos := Vector3.INF
var _obj_txt := ""

func _objetivo_punto() -> Array:
	var sig := func(tope: String) -> Vector3:
		var i := mini(progreso + 1, _indice_de(tope))
		return ruta[clampi(i, 0, ruta.size() - 1)]
	match fase:
		"inicio":
			return [ruta[1], "BAJA POR LA ESCALERA"]
		"camino":
			var r: Vector3 = sig.call("refugio")
			return [r, "REFUGIO" if progreso + 1 >= _indice_de("refugio") else "HACIA EL REFUGIO"]
		"refugio":
			var ps = (cfg.get("refugio", {}) as Dictionary).get("puerta_salida", null)
			return [_v([ps[0], 1.0, ps[1]]) if ps != null else ruta[progreso], "SALIDA DEL REFUGIO"]
		"porton":
			var bot: Vector3 = _v((cfg.get("porton", {}) as Dictionary).get("boton", [0, 0, 0]))
			if _alguien_cerca(bot, 45.0):
				return [bot, "CUADRO DEL PORTÓN"]
			return [sig.call("antes del porton"), "HACIA EL PORTÓN"]
		"abriendo":
			return [_porton.global_position if is_instance_valid(_porton) else ruta[progreso], "PORTÓN · AGUANTA"]
		"camino_hospital":
			var i_urg := _indice_de("urgencias")
			if progreso >= i_urg:
				return [sig.call("azotea del hospital"), "SUBE A LA AZOTEA"]
			return [sig.call("urgencias"), "HOSPITAL" if progreso + 1 >= i_urg else "HACIA EL HOSPITAL"]
		"radio":
			return [_v(cfg.get("radio", [0, 0, 0])), "RADIO"]
		"final":
			return [_v(cfg.get("helipuerto", [0, 0, 0])), "HELIPUERTO · AGUANTA"]
		"helicoptero":
			return [_v(cfg.get("helipuerto", [0, 0, 0])), "¡AL HELICÓPTERO!"]
	return [Vector3.INF, ""]


func _objetivo_tick() -> void:
	var o := _objetivo_punto()
	var p: Vector3 = o[0]
	var t: String = o[1]
	if p == Vector3.INF:
		return
	if t == _obj_txt and p.distance_to(_obj_pos) < 0.5:
		return
	_evento("objetivo", [p.x, p.y, p.z, t])


## LA LINEA DE ARRIBA, SIN ORDENES (2026-09-28, pedido: "no quiero que aparezca un mensaje diciendo destruye tal
## cosa, toca la palanca; que la gente imagine que es lo que tiene que hacer"). Los textos de cada fase siguen
## escritos como estaban ("La PERSIANA está cerrada · subid al BALCÓN y tirad de la PALANCA"), pero al ENSEÑARLOS se
## quita cada trozo (entre " · ") que da una orden: queda lo que pasa y las cuentas ("EL GENERADOR CALIENTA · 30 s",
## "1 de 2 a bordo"). Se filtra al pintar, en todas las maquinas: la logica que lee `_texto` no cambia.
const ORDENES := ["abrid", "accionad", "agarraos", "aguantad", "alejaos", "apartaos", "arrancad", "bajad", "bucead",
	"buscad", "cambiad", "cerrad", "coged", "conectad", "cruzad", "dad", "dejad", "derretid", "derribad", "disparad",
	"empujad", "encended", "esperad", "girad", "hundid", "id", "llegad", "pasad", "preparaos", "pulsad", "quedaos",
	"reconectad", "repetid", "reventad", "salid", "seguid", "soltad", "subid", "tensad", "tirad", "traed", "usad",
	"volad", "romped", "echad", "recoged", "poned", "apagad", "saltad", "trepad", "entrad", "corred", "llevad",
	"contad", "detonad", "escuchad", "tocad", "venid", "volved"]
## las de TU solo cuentan si ABREN la frase ("Baja a la calle...", "Sal por la puerta..."): en medio suelen ser de
## una descripcion ("La quitanieves llega", "EL AGUA APAGA EL FUEGO")
const ORDENES_TU := ["baja", "sube", "sal", "entra", "sigue", "cruza", "llega", "corre", "vuelve", "usa", "abre", "coge",
	"tira", "pulsa", "rompe", "dispara", "busca", "aguanta", "enciende", "apaga", "ve", "ven", "mira", "toca", "gira",
	"empuja", "salta", "trepa", "espera"]

func _objetivo(t: String) -> void:
	super._objetivo(sin_ordenes(t))


static func sin_ordenes(t: String) -> String:
	var re := RegEx.create_from_string("[a-záéíóúñü]+")
	var clitico := RegEx.create_from_string("^[a-záéíóúñü]{3,}(ad|ed|id)(la|lo|las|los|le|les)$")    # escoltadla, empujadlo
	# cada trozo (" · ") se mira FRASE A FRASE ("¡EL AZUFRE TE AHOGA! Coge una MÁSCARA..." -> se queda la primera)
	var frase := RegEx.create_from_string("[^!?…]+?(?:[!?…]+|\\.(?=\\s)|$)")
	var quedan: PackedStringArray = []
	for tr in t.split(" · "):
		var buenas: PackedStringArray = []
		for fm in frase.search_all(tr):
			var fr := fm.get_string().strip_edges()
			if fr == "":
				continue
			var bajo := fr.to_lower()
			var orden := bajo.begins_with("todos a") or bajo.begins_with("¡todos a") or bajo.begins_with("todos dentro")
			var primera := true
			if not orden:
				for m in re.search_all(bajo):
					var w := m.get_string()
					if w in ORDENES or clitico.search(w) != null or (primera and w in ORDENES_TU):
						orden = true
						break
					primera = false
			if not orden:
				buenas.append(fr)
		if not buenas.is_empty():
			quedan.append(" ".join(buenas))
	return " · ".join(quedan)


func _poner_objetivo(p: Vector3, t: String) -> void:
	_obj_pos = p
	_obj_txt = t
	# SOLO EL PUNTO (2026-09-28, pedido: "que no aparezca un mensaje diciendo destruye tal cosa, toca la palanca";
	# que la gente imagine que tiene que hacer): el texto del objetivo ya no va al HUD, solo la distancia
	if hud and hud.has_method("set_objetivo_mundo"):
		hud.set_objetivo_mundo(p + Vector3.UP * 1.3, "", -1.0, AMARILLO)
	Minimapa.marcar_sitio("campana_objetivo", p, AMARILLO, true)


func _quitar_objetivo() -> void:
	if hud and hud.has_method("quitar_objetivo_mundo"):
		hud.quitar_objetivo_mundo()
	Minimapa.quitar_sitio("campana_objetivo")


var _barrera_porton := AABB()
var _bisagra_entrada: Node3D = null

## LA PUERTA DE ENTRADA DEL REFUGIO SE CIERRA (todas las maquinas, con el evento "refugio"): 1,4 s girando
## sobre la bisagra, el golpe al cerrar, y barrera para los bichos. Si alguien se ha quedado en el hueco de
## la puerta, un paso hacia dentro para que la hoja no le atrape.
func _cerrar_entrada_refugio() -> void:
	if not is_instance_valid(_bisagra_entrada) or absf(_bisagra_entrada.rotation.y) < 0.01:
		return
	var ref: Dictionary = cfg.get("refugio", {})
	var pe: Array = ref.get("puerta_entrada", [0, 0])
	var hueco := Vector3(float(pe[0]), 1.0, float(pe[1]))
	if is_instance_valid(jugador):
		var jp: Vector3 = jugador.global_position
		if Vector2(jp.x - hueco.x, jp.z - hueco.z).length() < 1.6:
			jugador.global_position = Vector3(jp.x, jp.y, hueco.z + 1.8)
	var tw := create_tween()
	tw.tween_property(_bisagra_entrada, "rotation:y", 0.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		Audio.bf3d("destru/metal", hueco + Vector3.UP, 0.0, 40.0, Audio.PRI_MID))
	Audio.play3d("grab", hueco + Vector3.UP, -2.0, 0.05, 20.0, Audio.PRI_MID)
	CriaturaScript.barreras.append(AABB(Vector3(hueco.x - 1.2, 0.0, hueco.z - 0.8), Vector3(2.4, 4.5, 1.2)))


func _exit_tree() -> void:
	Minimapa.quitar_sitio("campana_objetivo")
	CriaturaScript.barreras.clear()
	CriaturaScript.sin_romper = false


func _indice_de(n: String) -> int:
	var i := ruta_nombres.find(n)
	return i if i >= 0 else 999


func _poner_fase(f: String, texto: String) -> void:
	fase = f
	if texto != "":
		_texto = texto
		_objetivo(texto)
	print("[campana] fase %s (ruta %d: %s)" % [f, progreso, String(ruta_nombres[progreso]) if progreso < ruta_nombres.size() else ""])


# ------------------------------------------------------------------ el coche con alarma
## GANCHOS PARA CADA EPISODIO (campana2.gd los cambia; aqui, lo del episodio 1)
func _al_empezar() -> void:
	_heli_de_paso()


func _tras_porton() -> void:
	_poner_fase("camino_hospital", "¡EL PORTÓN ESTÁ ABIERTO! Seguid hasta el HOSPITAL")
	_cola.push_front("tanque")          # y al otro lado espera el Tank
	_mensaje("¡UN TANK!")


func _usables_extra(_f: String) -> void:
	pass


func _pide_extra(_accion: String) -> void:
	pass


func _evento_extra(_e: String, _datos: Array) -> void:
	pass


## Hasta que punto de la ruta pueden salir bichos (nunca detras de lo que aun esta cerrado)
func _tope_ruta() -> int:
	if fase in ["inicio", "camino", "refugio", "porton", "abriendo"]:
		return _indice_de("antes del porton")
	return 999


## Las pruebas automaticas (--campanatest, --episodio2test...) no apuntan el episodio como hecho: se colaban en
## los ajustes de verdad y desbloqueaban el siguiente sin haberlo jugado
func _prueba_en_curso() -> bool:
	for a in OS.get_cmdline_user_args():
		if String(a).ends_with("test"):
			return true
	return false


func _vehiculo() -> String:
	return String(cfg.get("vehiculo", "HELICÓPTERO"))


func _alarma_coche() -> void:
	if _alarma_coche_sono:
		return
	var p: Vector3 = _v(cfg.get("alarma_coche", [0, 0, 0]))
	if p == Vector3.ZERO:
		return
	if _alguien_cerca(p, 2.2) or (Time.get_ticks_msec() * 0.001 - _ruido_t < 0.6 and _ruido_pos.distance_to(p) < 5.0):
		_alarma_coche_sono = true
		_evento("alarma_coche", [p.x, p.y, p.z])
		_horda(HORDA_TAM + 4, "¡LA ALARMA DEL COCHE! ¡VIENE LA HORDA!")


# ------------------------------------------------------------------ el refugio
func _llegar_al_refugio() -> void:
	var ref: Dictionary = cfg["refugio"]
	var r: Array = ref["rect"]
	_punto_control = Vector3((float(r[0]) + float(r[2])) / 2, float(ref.get("suelo", 1.0)) + 0.3, (float(r[1]) + float(r[3])) / 2)
	_cola.clear()
	_limpiar_atras_del_refugio()
	_evento("refugio", [_punto_control.x, _punto_control.y, _punto_control.z])
	get_tree().call_group("aliados_pve", "recargar_reserva")       # los compañeros bot tambien se reponen
	# los caidos vuelven AQUI (main pregunta punto_reaparicion_atraco -> punto_control)
	Net.net_revivir_caidos()
	_revivir_caidos()
	_horda_t = randf_range(HORDA_CADA.x, HORDA_CADA.y) + 30.0
	_texto = "REFUGIO · os habeis curado y recargado · la puerta sur se abre en 10 s"
	_objetivo(_texto)
	get_tree().create_timer(10.0).timeout.connect(func():
		_evento("abre_refugio", [])
		_texto = String(cfg.get("refugio_salida_texto", "Sal por la puerta roja del sur y sigue hacia el oeste"))
		_objetivo(_texto))


func punto_control() -> Vector3:
	return _punto_control


## AL ENTRAR EN EL REFUGIO SE VAN LOS DE ATRAS (pedido 2026-09-28). Los bichos que se quedaron por el camino seguian
## aporreando la puerta y sumando entidades al mundo, y eso daba lag. La primera vez que entrais (esto solo corre al
## pasar a la fase "refugio"), desaparece todo lo que queda del refugio hacia atras; lo de delante -las hordas
## dormidas de los puzzles que esperan- se queda. Dentro no sale nada (el director no trabaja en la fase "refugio")
## y al salir vuelve a empezar. Solo el anfitrion: los invitados lo ven por net_criatura_muerta.
func _limpiar_atras_del_refugio() -> void:
	var i_ref := _indice_de("refugio")
	if i_ref >= ruta.size():
		i_ref = progreso
	var n := 0
	for c in _vivos.duplicate():
		if not is_instance_valid(c):
			_vivos.erase(c)
			continue
		if bool(c.get("muerta")) or _indice_ruta((c as Node3D).global_position) > i_ref:
			continue
		_vivos.erase(c)
		Net.net_criatura_muerta(int(c.red_id), Vector3.ZERO)
		c.queue_free()
		n += 1
	print("[campana] refugio: %d criaturas de atras retiradas, quedan %d por delante" % [n, _vivos.size()])


# ------------------------------------------------------------------ el porton (el evento)
func _usar_porton() -> void:
	if fase != "porton":
		return
	_poner_fase("abriendo", "")
	_abrir_t = PORTON_S
	_evento("porton_empieza", [])
	_horda(HORDA_TAM, "¡LA ALARMA HA ATRAÍDO A LA HORDA! ¡AGUANTAD!")


func _porton_tick(dt: float) -> void:
	if fase != "abriendo":
		return
	_abrir_t -= dt
	_texto = "EL PORTÓN SE ABRE EN %d s · ¡AGUANTAD!" % ceili(maxf(_abrir_t, 0.0))
	# la horda no para mientras suena la alarma: cada 12 s llega otra tanda
	_tanda_t -= dt
	if _tanda_t <= 0.0:
		_tanda_t = 12.0
		if _cola.size() < 6:
			_horda(8, "")
	if _abrir_t <= 0.0:
		_evento("porton_abierto", [])
		_tras_porton()


# ------------------------------------------------------------------ el final
func _usar_radio() -> void:
	if fase != "radio":
		return
	_poner_fase("final", "")
	_final_ola = -1
	_final_espera = 6.0
	_evento("radio", [])
	_mensaje(String(cfg.get("radio_mensaje", "RADIO: «Os oímos. El helicóptero va para allá. ¡Aguantad en la azotea!»")))


func _final_tick() -> void:
	_trepar_a_la_azotea()
	if _final_espera > 0.0:
		_final_espera -= 0.5
		_texto = "EL %s ESTÁ EN CAMINO · preparaos (%d s)" % [_vehiculo(), ceili(maxf(_final_espera, 0.0))]
		return
	var hay := _cola.size() + _vivos.size()
	if _final_ola >= 0 and hay > 2:
		var tanque := false
		for c in _vivos:
			if String(c.tipo) in ["acorazado", "tanque"]:
				tanque = true
		_texto = "OLEADA %d de %d%s · quedan %d · aguantad hasta que llegue el %s" % [
			_final_ola + 1, FINAL.size(), " · ¡TANK!" if tanque else "", hay, _vehiculo().to_lower()]
		return
	_final_ola += 1
	if _final_ola >= FINAL.size():
		_poner_fase("helicoptero", String(cfg.get("llega_texto", "¡EL HELICÓPTERO HA LLEGADO! ¡SUBID TODOS AL HELIPUERTO!")))
		_evento("heli_llega", [])
		return
	_cola.clear()
	for g in FINAL[_final_ola]:
		for i in int(g[1]):
			_cola.append(String(g[0]))
	_cola.shuffle()
	for t in ["acorazado", "tanque"]:
		if t in _cola:
			_cola.erase(t)
			_cola.push_front(t)
	var hay_tank: bool = FINAL[_final_ola].any(func(g): return String(g[0]) in ["acorazado", "tanque"])
	_evento("horda", [_cola.size()])
	_mensaje(("OLEADA %d · ¡UN TANK!" if hay_tank else "OLEADA %d · ¡VIENEN!") % (_final_ola + 1))


func _abordar_tick() -> void:
	if _heli_t < 13.0:
		return                 # todavia bajando
	var hp: Vector3 = _v(cfg.get("helipuerto", [0, 0, 0]))
	var vivos := _jugadores_vivos()
	if vivos.is_empty():
		return
	var dentro := 0
	for pl in vivos:
		var p: Vector3 = (pl as Node3D).global_position
		if Vector2(p.x - hp.x, p.z - hp.z).length() < HELI_ABORDAR and p.y > hp.y - 1.5:
			dentro += 1
	_texto = "¡SUBID AL %s! · %d de %d a bordo" % [_vehiculo(), dentro, vivos.size()]
	if dentro == vivos.size():
		terminado = true
		_evento("escapan", [])
		_mensaje("¡HABÉIS ESCAPADO!")
		_objetivo("VICTORIA · %d bajas" % bajas)
		if _en_red:
			Net.net_fin_pve(true, FINAL.size(), bajas, puntos)
		get_tree().create_timer(3.0).timeout.connect(func(): _fin(true))


# ======================================================================================================
# EL DIRECTOR
# ======================================================================================================
func _director(dt: float) -> void:
	_porton_tick(dt)
	if fase in ["inicio", "refugio", "helicoptero", "fin"] or fase == "final":
		return
	# DENTRO DEL EDIFICIO DE SALIDA, SOLO LOS DORMIDOS: ni especiales ni hordas hasta pisar la calle (bajando
	# las escaleras te buscaban sin haberte visto)
	var en_la_calle: bool = progreso >= _indice_de(String(cfg.get("calle_desde", "callejon")))
	# ambiente: siempre hay unos cuantos rondando por delante
	_amb_t -= dt
	if _amb_t <= 0.0:
		_amb_t = AMBIENTE_CADA
		_retirar_dormidos_atras()
		var comunes := _vivos.filter(func(c): return String(c.tipo) in ["zombi", "corredor"]).size()
		if comunes < AMBIENTE_VIVOS and _cola.is_empty():
			var t := "corredor" if randf() < 0.18 else "zombi"
			var p = _punto_delante(false)
			if p != null:
				_sacar(t, p)
				# COMO EN EL ORIGINAL: el de ambiente sale DORMIDO y espera en su sitio (criatura.gd)
				var nuevo = _vivos.back()
				if nuevo != null and nuevo.has_method("dormir"):
					nuevo.dormir()
	# especiales
	if en_la_calle:
		_esp_t -= dt
	if _esp_t <= 0.0:
		_esp_t = randf_range(ESPECIAL_CADA.x, ESPECIAL_CADA.y)
		var esp := _vivos.filter(func(c): return String(c.tipo) in ESPECIALES).size()
		if esp < MAX_ESPECIALES:
			var t: String = ESPECIALES[randi() % ESPECIALES.size()]
			var p = _punto_delante(false)
			if p != null:
				_sacar(t, p)
	# hordas
	if en_la_calle:
		_horda_t -= dt
	if _horda_t <= 0.0:
		_horda_t = randf_range(HORDA_CADA.x, HORDA_CADA.y)
		_horda(HORDA_TAM, "¡HORDA!")
	# LA BRUJA (Left 4 Dead 2): de vez en cuando hay una llorando por delante, en el camino. Hay que pasar a
	# su lado sin molestarla (despacio y lejos) o matarla de golpe
	_bruja_cada -= dt
	if en_la_calle and _bruja_cada <= 0.0:
		_bruja_cada = randf_range(150.0, 240.0)
		if not _vivos.any(func(c): return String(c.tipo) == "bruja"):
			var pb = _punto_delante(false)
			if pb != null:
				_sacar("bruja", pb)


## Los dormidos que el grupo ha dejado ATRAS y lejos ya no pintan nada: se van (por red, como una muerte
## sin cadaver a la vista) y dejan sitio para los de delante.
func _retirar_dormidos_atras() -> void:
	var vivos := _jugadores_vivos()
	for c in _vivos.duplicate():
		if not is_instance_valid(c) or not bool(c.get("dormida")):
			continue
		if _indice_ruta(c.global_position) >= progreso - 1:
			continue
		var lejos := true
		for pl in vivos:
			if (pl as Node3D).global_position.distance_to(c.global_position) < 45.0:
				lejos = false
				break
		if lejos:
			_vivos.erase(c)
			Net.net_criatura_muerta(int(c.red_id), Vector3.ZERO)
			c.queue_free()


## Los especiales suenan con su musica CUANDO LOS VES, no al salir (pedido: "solo se escuchara cuando vea uno
## especial"). Lo mira cada maquina con su camara (_ver_especiales), una vez por bicho.
var _especiales_vistos: Dictionary = {}
var _ver_t := 0.0

func _ver_especiales(dt: float) -> void:
	_ver_t -= dt
	if _ver_t > 0.0:
		return
	_ver_t = 0.25
	var cam := get_viewport().get_camera_3d()
	if cam == null or not is_instance_valid(jugador) or bool(jugador.get("spectating")):
		return
	var ojo := cam.global_position
	var frente := -cam.global_transform.basis.z
	for c in get_tree().get_nodes_in_group("criaturas"):
		var t := str(c.get("tipo"))
		if not (t in ["gordo", "arrastrado", "escupidor", "fumador", "cazador", "jinete", "cargador"]) or bool(c.get("muerta")):
			continue
		var k: int = c.get_instance_id()
		if _especiales_vistos.has(k):
			continue
		var p: Vector3 = (c as Node3D).global_position + Vector3.UP * 1.2
		if ojo.distance_to(p) > 45.0 or (p - ojo).normalized().dot(frente) < 0.55:
			continue
		if not world.has_line_of_sight(ojo, p):
			continue
		_especiales_vistos[k] = true
		# (los de Left 4 Dead 2 con la musica de su primo: el fumador la del arrastrado)
		# SIN MUSICA DE ESPECIALES (2026-09-27, pedido: "quitame la musica de fondo cuando aparece un especial,
		# dejame solo los efectos"): sus voces ya avisan. Antes sonaba la pista de su primo (mas de 30 s).


var _hay_tank := false
func _tank_tick() -> void:
	var hay := false
	for c in _vivos:
		if is_instance_valid(c) and String(c.tipo) in ["acorazado", "goliat"]:
			hay = true
			break
	if hay != _hay_tank:
		_hay_tank = hay
		_evento("tank", [1 if hay else 0])


func _horda(n: int, aviso: String) -> void:
	for i in n:
		_cola.append("corredor" if randf() < 0.25 else "zombi")
	if aviso != "":
		_mensaje(aviso)
	_evento("horda", [n])


## Donde sale cada uno. Los del final, en la azotea del hospital (trepan por la fachada: se los ve asomar
## por el peto) y en la plaza; los demas, delante del grupo.
func _punto_para(t: String) -> Variant:
	if fase == "final" or fase == "helicoptero":
		# TODOS ARRIBA (pedido: "no voy a bajar a matarlos"): abajo no sabian subir y rompian los techos.
		# Si no hay hueco lejos de los jugadores, se espera al siguiente intento
		if not cfg.has("azotea_hospital"):
			return _punto_delante(randf() < 0.4)
		var p = _punto_azotea()
		if p == null:
			p = _punto_azotea(5.0)
		return p
	var q = _punto_delante(randf() < 0.3)
	if q != null:
		return q
	var r = _punto_salida()
	if r != null and fase in ["porton", "abriendo"] and CriaturaScript.barreras.size() > 0:
		var b: AABB = CriaturaScript.barreras[0]
		if (r as Vector3).x < b.position.x:
			return null                  # al otro lado del porton cerrado: que espere a otro sitio
	return r


## PUNTO DELANTE DEL GRUPO: una de las pistas de salida del mapa cuyo punto de ruta este entre el progreso y
## tres mas alla (o por DETRAS si `detras`), a 18-60 m del jugador mas cercano, y que ninguno la vea.
func _punto_delante(detras: bool) -> Variant:
	if _pista_idx.size() != _pistas.size():
		_pista_idx.clear()
		for q in _pistas:
			_pista_idx.append(_indice_ruta(q))
	var vivos := _jugadores_vivos()
	if vivos.is_empty():
		return null
	var cand: Array = []
	# CON EL PORTON CERRADO NO SE SACA A NADIE AL OTRO LADO: salian alli (lo de "delante" del grupo) y venian
	# hacia ti atravesandolo. Hasta que se abre, lo mas lejos es el propio porton.
	var tope := _tope_ruta()
	for i in _pistas.size():
		var k: int = _pista_idx[i]
		if k > tope:
			continue
		var ok: bool = (k >= progreso - 3 and k <= progreso) if detras else (k >= progreso and k <= progreso + 3)
		if not ok:
			continue
		var q: Vector3 = _pistas[i]
		var dmin := INF
		for pl in vivos:
			dmin = minf(dmin, (pl as Node3D).global_position.distance_to(q))
		if dmin < 18.0 or dmin > 60.0:
			continue
		cand.append(q)
	cand.shuffle()
	for q in cand.slice(0, 6):
		var visto := false
		for pl in vivos:
			var ojo: Vector3 = (pl as Node3D).global_position + Vector3.UP * 1.6
			if world.has_line_of_sight(q + Vector3.UP * 1.4, ojo):
				visto = true
				break
		if not visto:
			return q + Vector3(0, 0.2, 0)
	return cand[0] + Vector3(0, 0.2, 0) if not cand.is_empty() else null


## En la azotea del hospital, pegado al peto, lejos de los jugadores
var _trepa_desde = null        ## lo deja _punto_azotea: por donde sube el ultimo que ha colocado

func _punto_azotea(lejos: float = 10.0) -> Variant:
	_trepa_desde = null
	var az: Array = cfg.get("azotea_hospital", [])
	if az.size() < 5:
		return null
	var y: float = float(az[1])
	var x0: float = float(az[0]) + 1.6
	var z0: float = float(az[2]) + 1.6
	var x1: float = float(az[3]) - 1.6
	var z1: float = float(az[4]) - 1.6
	for intento in 10:
		var lado := randi() % 4
		var p := Vector3(randf_range(x0, x1), y + 4.0, randf_range(z0, z1))
		match lado:
			0: p.x = x0
			1: p.x = x1
			2: p.z = z0
			3: p.z = z1
		var h: Dictionary = world.raycast(p, Vector3.DOWN, 8.0)
		if not h.get("hit", false):
			continue
		var s: Vector3 = h["position"]
		if absf(s.y - y) > 1.5:
			continue
		if _alguien_cerca(s, lejos):
			continue
		# por donde trepa: por fuera de la fachada de ese lado, 3 m mas abajo
		# la fachada de verdad: hacia fuera, el primer sitio donde un rayo hacia abajo ya no da en la azotea
		var hacia_fuera: Vector3 = [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK][lado]
		var fuera = null
		for paso in 40:
			var q := s + hacia_fuera * (0.25 * paso)
			var hq: Dictionary = world.raycast(Vector3(q.x, y + 3.0, q.z), Vector3.DOWN, 12.0)
			if not hq.get("hit", false) or float((hq["position"] as Vector3).y) < y - 3.0:
				fuera = Vector3(q.x, y - 3.2, q.z) + hacia_fuera * 0.2
				break
		if fuera == null:
			continue
		_trepa_desde = fuera
		return s + Vector3(0, 0.2, 0)
	return null


# ======================================================================================================
# EVENTOS (los manda el anfitrion y los ven todos)
# ======================================================================================================
func _evento(e: String, datos: Array) -> void:
	if _en_red and _soy_host:
		Net.net_campana(e, datos)
	_on_evento(e, datos)


func _on_evento(e: String, datos: Array) -> void:
	match e:
		"objetos":
			for o in datos:
				_crear_objeto(int(o[0]), String(o[1]), Vector3(float(o[2]), float(o[3]), float(o[4])), o[5] if o.size() > 5 else null)
		"quita_objeto":
			var oid := int(datos[0])
			if _objetos.has(oid) and is_instance_valid(_objetos[oid]):
				_objetos[oid].queue_free()
			_objetos.erase(oid)
		"objetivo":
			_poner_objetivo(Vector3(float(datos[0]), float(datos[1]), float(datos[2])), String(datos[3]))
		"alarma_coche":
			var p := Vector3(float(datos[0]), float(datos[1]), float(datos[2]))
			_alarma_nodo = _bucle_en(p, "bf/amb/bucle_alarma_coche", 2.0, 70.0)
			get_tree().create_timer(25.0).timeout.connect(func():
				if is_instance_valid(_alarma_nodo):
					_alarma_nodo.queue_free())
		"horda":
			var n: int = int(datos[0]) if datos.size() > 0 else 12
			if n >= 10:
				Audio.voz_criatura("zombi", "alerta", _cam_pos() + Vector3(20, 0, 0), 4.0, 90.0)
			_musica_horda(n)
		"tank":
			_musica_tank(int(datos[0]) != 0)
		"especial":
			pass                        # sin musica de especiales (ver _ver_especiales)
		"refugio":
			_musica_capa("refugio", -2.0, true)
			_cerrar_entrada_refugio()
			_punto_control = Vector3(float(datos[0]), float(datos[1]), float(datos[2]))
			if is_instance_valid(jugador):
				if "health" in jugador and jugador.has_method("vida_max"):
					jugador.health = jugador.vida_max()
					jugador.health_changed.emit(jugador.health)
				if jugador.has_method("rellenar_municion"):
					jugador.rellenar_municion(6)
			Audio.ui("objetivo_tomado", -2.0)
			_mensaje_local("REFUGIO ALCANZADO · vida y munición repuestas")
		"abre_refugio":
			if is_instance_valid(_puerta_refugio):
				_abrir_puerta(_puerta_refugio)
		"porton_empieza":
			Mandos.accionar(_mando_porton)
			if is_instance_valid(_porton):
				_alarma_nodo = _bucle_en(_porton.global_position + Vector3(4, 0, 0), "bf/modo/bomba_alarma", 4.0, 120.0)
			Audio.voz("bomba_armada_nos_a", 2)
		"porton_abierto":
			CriaturaScript.barreras.erase(_barrera_porton)
			if is_instance_valid(_alarma_nodo):
				_alarma_nodo.queue_free()
			if is_instance_valid(_porton):
				var tw := _porton.create_tween()
				tw.tween_property(_porton, "position:y", _porton.position.y + 5.4, 4.0).set_trans(Tween.TRANS_SINE)
				tw.tween_callback(func():
					for c in _porton.get_children():
						if c is CollisionShape3D:
							(c as CollisionShape3D).disabled = true)
				Audio.bf3d("destru/metal", _porton.global_position, 4.0, 90.0, Audio.PRI_HIGH)
			Audio.ui("objetivo_tomado", -2.0)
		"radio":
			Mandos.accionar(_mando_radio)
			_musica_capa("final", -2.0, true)
			Audio.bf2d("amb/radio", 0.0, Audio.PRI_HIGH)
			Audio.voz("apoyo_aereo", 3)
			_mensaje_local(String(cfg.get("radio_mensaje", "RADIO: «Os oímos. El helicóptero va para allá. ¡Aguantad en la azotea!»")))
			if _vehiculo() == "HELICÓPTERO":
				get_tree().create_timer(1.5).timeout.connect(func(): Audio.play2d("l4d2/heli/piloto_en_camino", -2.0, 0.0, Audio.PRI_HIGH))
			else:
				Audio.bf3d("modo/bomba_alarma", _v(cfg.get("radio", [0, 0, 0])) + Vector3.UP * 3.0, 8.0, 200.0, Audio.PRI_HIGH)
		"heli_llega":
			_musica_capa("rescate", 0.0, true)
			_heli_al_rescate()
			Audio.voz("apoyo_aereo", 3, 0.0)
			if _vehiculo() == "HELICÓPTERO":
				Audio.play2d("l4d2/heli/pasa", -2.0, 0.0, Audio.PRI_HIGH)
				get_tree().create_timer(9.0).timeout.connect(func(): Audio.play2d("l4d2/heli/piloto_subid", -2.0, 0.0, Audio.PRI_HIGH))
		"escapan":
			_musica_capa("escapan", 0.0, true)
			if _vehiculo() == "HELICÓPTERO":
				Audio.play2d("l4d2/heli/piloto_despega", -2.0, 0.0, Audio.PRI_HIGH)
				Audio.play2d("l4d2/heli/se_va", -4.0, 0.0, Audio.PRI_HIGH)
			_quitar_objetivo()
			Audio.voz_fin_partida(true)
		_:
			_evento_extra(e, datos)


func _mensaje_local(t: String) -> void:
	var f := sin_ordenes(t)            # los avisos del centro, tambien sin ordenes
	if f != "" and hud and hud.has_method("flash_message"):
		hud.flash_message(f)


func _mensaje(t: String) -> void:
	var f := sin_ordenes(t)
	if f != "":
		super._mensaje(f)


func _cam_pos() -> Vector3:
	var c := get_viewport().get_camera_3d() if is_inside_tree() else null
	return c.global_position if c else Vector3.ZERO


func _bucle_en(p: Vector3, clave: String, db: float, alcance: float) -> AudioStreamPlayer3D:
	var st: AudioStream = Audio._pick(clave)
	if st == null:
		return null
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	var a := AudioStreamPlayer3D.new()
	a.stream = st
	a.unit_size = 10.0
	a.max_distance = alcance
	a.volume_db = db + Audio.master_db
	a.bus = "World"
	add_child(a)
	a.global_position = p
	a.play()
	return a


func _abrir_puerta(sb: StaticBody3D) -> void:
	for c in sb.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = true
	var tw := sb.create_tween()
	tw.tween_property(sb, "position:x", sb.position.x - 1.7, 1.2).set_trans(Tween.TRANS_QUAD)
	Audio.bf3d("destru/metal", sb.global_position, -2.0, 30.0, Audio.PRI_MID)


# ======================================================================================================
# COSAS QUE SE USAN (el cuadro del porton, la radio): todos las ven; el anfitrion decide
# ======================================================================================================
func _usables_tick() -> void:
	_usables.clear()
	var f := fase
	if _en_red and not _soy_host:
		f = _fase_invitado()
	if f == "porton":
		_usables.append({"id": "porton", "pos": _pos_mando(_mando_porton, _v((cfg.get("porton", {}) as Dictionary).get("boton", [0, 0, 0])) + Vector3(0, 1.2, -0.6)),
			"texto": String(cfg.get("porton_texto", "ABRIR EL PORTÓN (atraerá a la horda)"))})
	elif f == "radio":
		_usables.append({"id": "radio", "pos": _pos_mando(_mando_radio, _v(cfg.get("radio", [0, 0, 0])) + Vector3(0.8, 1.0, -1.0)),
			"texto": String(cfg.get("radio_texto", "USAR LA RADIO"))})
	_usables_extra(f)
	if not is_instance_valid(jugador) or bool(jugador.get("spectating")):
		_usable_mirado = ""
		_aviso_usar(false)
		return
	# LOS COMPANEROS HERIDOS: si llevas botiquin y no te estas curando, un boton en su cuerpo
	if _en_red and int(jugador.get("botiquines")) > 0 and String(jugador.get("curando")) == "":
		for id in Net.remotes.keys():
			var np = Net.remotes[id]
			if np == null or not is_instance_valid(np) or bool(Net.dead_players.get(id, false)):
				continue
			var vv: Array = Net.vidas.get(id, [100.0, 100.0])
			if float(vv[0]) <= 0.0 or float(vv[0]) >= float(vv[1]) - 0.5:
				continue
			var nom := String((Net.players.get(id, {}) as Dictionary).get("name", "compañero"))
			_usables.append({"id": "curar:%d" % int(id), "pos": (np as Node3D).global_position + Vector3(0, 1.0, 0),
				"texto": "CURAR A %s" % nom.to_upper(), "cerca": 2.2})
	# LOS BOTIQUINES Y LA MUNICION DEL SUELO: se cogen con el boton (E), no al pasar
	for oid in _objetos:
		var ob = _objetos[oid]
		if not is_instance_valid(ob) or (ob as Node3D).global_position.distance_to(jugador.global_position) > 2.2:
			continue
		if ob.puede_coger(jugador):
			_usables.append({"id": "objeto:%d" % int(oid), "pos": (ob as Node3D).global_position + Vector3(0, 0.5, 0),
				"texto": ob.texto(), "cerca": 2.2})
	var cam := jugador.get_viewport().get_camera_3d() if jugador.is_inside_tree() else null
	# EL QUE MIRAS: con varios a mano (los codos del panel de tuberias, los diales de la oficina...) gana el que
	# queda mas en el centro de la vista, no el ultimo de la lista
	var elegido := {}
	var mejor := -2.0
	for u in _usables:
		var p: Vector3 = u["pos"]
		if jugador.global_position.distance_to(p) > float(u.get("cerca", 4.5 if Settings.is_touch() else 3.0)):
			continue
		var dotp := 1.0
		if cam:
			dotp = (p - cam.global_position).normalized().dot(-cam.global_transform.basis.z)
		if cam and not u.has("cerca") and dotp < 0.5:
			continue
		if dotp > mejor:
			mejor = dotp
			elegido = u
	if elegido.is_empty():
		_aviso_usar(false)
		_usable_mirado = ""
		return
	_usable_mirado = String(elegido["id"])
	# EL AVISO DE USAR (aviso_usar.gd): el circulo con la E (la mano en el movil) pegado a la cosa, y la accion al
	# lado. El de curar y los objetos del suelo, chiquitos y con su icono.
	var chico := _usable_mirado.begins_with("curar:") or _usable_mirado.begins_with("objeto:")
	var ic := ""
	if chico:
		ic = "heal"
		if _usable_mirado.begins_with("objeto:"):
			ic = "heal" if String(_objetos.get(int(_usable_mirado.substr(7))).get("tipo")) == "botiquin" else "municion"
	_aviso_usar(true, _usable_mirado, String(elegido["texto"]), chico, ic, (elegido["pos"] as Vector3), cam)
	if Input.is_action_just_pressed("interact"):
		usar_desde_jugador()


var _aviso: Button = null

func _aviso_usar(on: bool, id := "", texto := "", chico := false, icono := "", donde := Vector3.ZERO, cam: Camera3D = null) -> void:
	if not on or hud == null or (cam != null and cam.is_position_behind(donde)):
		if _aviso and is_instance_valid(_aviso):
			_aviso.quitar()
		return
	if _aviso == null or not is_instance_valid(_aviso):
		_aviso = preload("res://scripts/aviso_usar.gd").new()
		_aviso.pressed.connect(usar_desde_jugador)
		hud.add_child(_aviso)
	_aviso.poner(id, texto, chico, icono)
	_aviso.colocar(cam.unproject_position(donde) if cam else get_viewport().get_visible_rect().size * 0.5)


## El invitado no lleva la fase, pero la deduce del cartel que le llega del anfitrion
func _fase_invitado() -> String:
	var t: String = _texto_red
	if t.begins_with("EL PORTÓN ESTÁ CERRADO"):
		return "porton"
	if t.begins_with("Usa la RADIO"):
		return "radio"
	return ""


var _texto_red := ""

func _red_estado_pve(n_oleada: int, quedan: int, p_oro: int, fuera: bool, texto: String, p_bajas: int = 0) -> void:
	_texto_red = texto
	if p_bajas != bajas:
		bajas = p_bajas
		_poner_bajas()
	if texto != "":
		_objetivo(texto)


func usar_desde_jugador() -> void:
	if _usable_mirado == "":
		return
	if _usable_mirado.begins_with("objeto:"):
		var ob = _objetos.get(int(_usable_mirado.substr(7)))
		if ob != null and is_instance_valid(ob):
			ob.coger(jugador)
		return
	if _usable_mirado.begins_with("curar:"):
		var pid := int(_usable_mirado.substr(6))
		jugador.curar_a(pid, String((Net.players.get(pid, {}) as Dictionary).get("name", "compañero")))
		return
	if _en_red and not _soy_host:
		Net.net_campana_pide(_usable_mirado)
		return
	_on_pide(_usable_mirado, 1)


func _on_pide(accion: String, _de: int) -> void:
	if accion == "objetos":
		_evento("objetos", _lista_objetos)
		return
	if accion.begins_with("coger:"):
		var oid := int(accion.substr(6))
		if _objetos.has(oid):
			_evento("quita_objeto", [oid])
		return
	match accion:
		"porton":
			_usar_porton()
		"radio":
			_usar_radio()
		_:
			_pide_extra(accion)


# ======================================================================================================
# EL HELICOPTERO
# ======================================================================================================
func _modelo_heli() -> Node3D:
	var h := Node3D.new()
	h.name = "Helicoptero"
	var blanco := _mm(Color(0.86, 0.87, 0.88), 0.3, 0.5)
	var rojo := _mm(Color(0.7, 0.08, 0.06), 0.3, 0.5)
	var negro := _mm(Color(0.06, 0.06, 0.07), 0.5, 0.4)
	var cristal := _mm(Color(0.2, 0.35, 0.45), 0.6, 0.1)
	var cuerpo := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 1.3
	cap.height = 6.0
	cuerpo.mesh = cap
	cuerpo.rotation.z = PI / 2
	cuerpo.material_override = blanco
	h.add_child(cuerpo)
	var franja := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(5.2, 0.35, 2.66)
	franja.mesh = fm
	franja.material_override = rojo
	h.add_child(franja)
	var cabina := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.1
	sm.height = 1.8
	cabina.mesh = sm
	cabina.position = Vector3(2.4, 0.3, 0)
	cabina.material_override = cristal
	h.add_child(cabina)
	var cola := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(5.5, 0.45, 0.45)
	cola.mesh = cm
	cola.position = Vector3(-5.2, 0.4, 0)
	cola.material_override = blanco
	h.add_child(cola)
	var aleta := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(0.9, 1.6, 0.12)
	aleta.mesh = am
	aleta.position = Vector3(-7.7, 1.1, 0)
	aleta.material_override = rojo
	h.add_child(aleta)
	for s in [-1.0, 1.0]:
		var patin := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(4.2, 0.12, 0.14)
		patin.mesh = pm
		patin.position = Vector3(0.2, -1.55, s * 1.1)
		patin.material_override = negro
		h.add_child(patin)
		for dx in [-1.0, 1.2]:
			var pata := MeshInstance3D.new()
			var tm := BoxMesh.new()
			tm.size = Vector3(0.1, 0.5, 0.1)
			pata.mesh = tm
			pata.position = Vector3(dx, -1.3, s * 1.0)
			pata.material_override = negro
			h.add_child(pata)
	var rotor := Node3D.new()
	rotor.position = Vector3(0.2, 1.55, 0)
	for i in 4:
		var pala := MeshInstance3D.new()
		var plm := BoxMesh.new()
		plm.size = Vector3(5.2, 0.05, 0.28)
		pala.mesh = plm
		pala.position = Vector3(2.6, 0, 0)
		pala.material_override = negro
		var brazo := Node3D.new()
		brazo.rotation.y = i * PI / 2
		brazo.add_child(pala)
		rotor.add_child(brazo)
	h.add_child(rotor)
	_heli_rotor = rotor
	# foco buscador y luces de posicion
	var foco := SpotLight3D.new()
	foco.light_energy = 6.0
	foco.spot_range = 45.0
	foco.spot_angle = 22.0
	foco.light_color = Color(1.0, 0.97, 0.9)
	foco.rotation.x = -PI / 2 + 0.2
	foco.position = Vector3(2.0, -1.0, 0)
	h.add_child(foco)
	var baliza := OmniLight3D.new()
	baliza.light_color = Color(1, 0.1, 0.05)
	baliza.light_energy = 2.0
	baliza.omni_range = 6.0
	baliza.position = Vector3(-7.7, 2.0, 0)
	h.add_child(baliza)
	for i in HELI_BUCLES.size():
		if not ResourceLoader.exists(HELI_BUCLES[i]):
			continue
		var st = load(HELI_BUCLES[i])
		if st is AudioStreamOggVorbis:
			(st as AudioStreamOggVorbis).loop = true
		var s := AudioStreamPlayer3D.new()
		s.stream = st
		s.unit_size = 30.0
		s.max_distance = 450.0
		s.volume_db = (2.0 if i == 0 else -3.0) + Audio.master_db
		s.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		s.bus = "World"
		s.autoplay = true
		h.add_child(s)
	return h


var _heli_desde := Vector3.ZERO
var _heli_hasta := Vector3.ZERO
var _heli_dur := 13.0
var _heli_modo := ""

## Al empezar pasa uno por encima de la azotea de salida camino del hospital (os dice a donde ir)
func _heli_de_paso() -> void:
	if not is_inside_tree() or cfg.is_empty():
		return
	var sal: Vector3 = _v(cfg.get("salida", [0, 0, 0]))
	var hp: Vector3 = _v(cfg.get("helipuerto", [0, 0, 0]))
	_heli = _modelo_heli()
	add_child(_heli)
	_heli_desde = sal + Vector3(-60, 22, -40)
	_heli_hasta = hp + Vector3(80, 30, 60)
	_heli_dur = 22.0
	_heli_t = 0.0
	_heli_modo = "paso"
	_mensaje_local("PILOTO: «¡Supervivientes! ¡Id al HOSPITAL! ¡Os recogeremos en la azotea!»")
	Audio.bf2d("amb/radio", -4.0, Audio.PRI_MID)
	Audio.play2d("l4d2/heli/piloto_intro", -2.0, 0.0, Audio.PRI_HIGH)


func _heli_al_rescate() -> void:
	if is_instance_valid(_heli):
		_heli.queue_free()
	var hp: Vector3 = _v(cfg.get("helipuerto", [0, 0, 0]))
	_heli = _modelo_heli()
	add_child(_heli)
	_heli_desde = hp + Vector3(90, 45, -70)
	_heli_hasta = hp + Vector3(0, 1.6, 0)
	_heli_dur = 13.0
	_heli_t = 0.0
	_heli_modo = "rescate"


func _heli_tick(dt: float) -> void:
	if not is_instance_valid(_heli):
		return
	_heli_t += dt
	if is_instance_valid(_heli_rotor):
		_heli_rotor.rotation.y += dt * 24.0
	var k: float = clampf(_heli_t / _heli_dur, 0.0, 1.0)
	var e: float = 1.0 - pow(1.0 - k, 2.0) if _heli_modo == "rescate" else k
	var p: Vector3 = _heli_desde.lerp(_heli_hasta, e)
	if _heli_modo == "rescate" and k < 1.0:
		p.y += sin(k * PI) * 6.0 * (1.0 - k)
	_heli.global_position = p
	var dir := _heli_hasta - _heli_desde
	_heli.rotation.y = atan2(-dir.z, dir.x)
	_heli.rotation.z = -0.12 * (1.0 - k) if _heli_modo == "rescate" else -0.1
	if _heli_modo == "rescate" and k >= 1.0:
		_heli.global_position.y = _heli_hasta.y + sin(_heli_t * 1.3) * 0.12
	if _heli_modo == "paso" and k >= 1.0:
		_heli.queue_free()
		_heli = null


# ======================================================================================================
# EL FINAL DE LA PARTIDA: premio de campaña
# ======================================================================================================
## MUERES: el lamento corto de Left 4 Dead (la derrota de todos lleva el largo, en _perder)
func jugador_caido() -> void:
	if not terminado:
		_musica_capa("muerte", 0.0, true)
	super.jugador_caido()


func _perder() -> void:
	if terminado:
		return
	_musica_capa("todos_muertos", 0.0, true)
	terminado = true
	_mensaje("DERROTA · os han alcanzado en %s" % (String(ruta_nombres[progreso]) if progreso < ruta_nombres.size() else "la ciudad"))
	_objetivo("DERROTA · %d bajas" % bajas)
	if _en_red and _soy_host:
		Net.net_fin_pve(false, progreso, bajas, puntos)
	_fin(false)


func _fin(gano: bool) -> void:
	Estadisticas.fin_partida(gano)
	if gano and not _prueba_en_curso():
		Settings.campana_completada(_mapa())
	var mn = jugador.get_parent() if is_instance_valid(jugador) else null
	var exp_ganada := 300 + progreso * 40 + bajas * 3
	var oro_ganado := 150 + progreso * 20 + bajas * 2
	if gano:
		exp_ganada += 1200
		oro_ganado += 800
	var segs: int = int(mn.segundos_partida()) if mn != null and mn.has_method("segundos_partida") else 0
	var mias: int = Combat.partida_bajas_pve
	var premio: Dictionary = Settings.premiar(gano, exp_ganada, oro_ganado,
		{"modo": "pve", "segundos": segs, "oleada": progreso, "bajas": mias, "puntos": puntos,
		"dano": int(Combat.partida_dano), "objetivos": 1 if gano else 0, "mvp": mias > 0 and float(mias) >= float(bajas) * 0.6})
	if mn != null and mn.has_method("fin_pve"):
		mn.fin_pve(gano, progreso, bajas, puntos, premio)


# ======================================================================================================
# PRUEBA: --campanatest recorre la historia sola (sin jugar) y dice si cada fase se alcanza
# ======================================================================================================
func prueba_recorrido() -> void:
	var pasos := [["porton", "calle Segunda"], ["radio", "azotea del hospital"]]
	await get_tree().create_timer(3.0).timeout
	print("[campanatest] fase %s, progreso %d" % [fase, progreso])
	# teletransporta al jugador por la ruta y comprueba que la historia avanza
	for i in ruta.size():
		jugador.global_position = ruta[i] + Vector3(0, 0.4, 0)
		await get_tree().create_timer(0.7).timeout
		if ruta_nombres[i] == "refugio":
			await get_tree().create_timer(1.0).timeout
		if ruta_nombres[i] == "antes del porton":
			jugador.global_position = _v((cfg["porton"] as Dictionary)["boton"]) + Vector3(0, 0.4, 0)
			await get_tree().create_timer(0.7).timeout
			_on_pide("porton", 1)
			print("[campanatest] porton: fase %s" % fase)
			_abrir_t = 1.0
			await get_tree().create_timer(1.6).timeout
			print("[campanatest] porton abierto: fase %s, colision %s" % [fase, str(not _porton.get_child(0).disabled) if is_instance_valid(_porton) else "?"])
		print("[campanatest] ruta %d %s -> progreso %d fase %s" % [i, ruta_nombres[i], progreso, fase])
	jugador.global_position = _v(cfg["radio"]) + Vector3(0, 0.4, 0)
	await get_tree().create_timer(1.2).timeout
	print("[campanatest] en la radio: fase %s" % fase)
	_on_pide("radio", 1)
	print("[campanatest] radio usada: fase %s · vivos %d cola %d" % [fase, _vivos.size(), _cola.size()])
	# el final, sin pelear: se matan las oleadas
	for n in 12:
		await get_tree().create_timer(1.5).timeout
		for c in _vivos:
			c.take_damage(1.0e7)
		_cola.clear()
		if fase == "helicoptero":
			break
	print("[campanatest] final: fase %s · oleada %d" % [fase, _final_ola])
	jugador.global_position = _v(cfg["helipuerto"]) + Vector3(0, 0.6, 0)
	await get_tree().create_timer(16.0).timeout
	print("[campanatest] helicoptero: terminado %s -> %s" % [str(terminado), "TODO BIEN" if terminado else "FALLO"])


## --dormidostest: un zombi dormido no se mueve, despierta al acercarte, y el ruido de un tiro despierta a otro
func _prueba_dormidos() -> void:
	await get_tree().create_timer(4.0).timeout
	fase = "inicio"                          # sin director: solo los de la prueba
	jugador.global_position = Vector3(60.0, 1.2, 41.0)        # calle Olmo, a 40 m del bicho
	await get_tree().create_timer(1.0).timeout
	_sacar("zombi", Vector3(100.0, 1.2, 41.0))
	var z1 = _vivos.back()
	z1.dormir()
	var p0: Vector3 = z1.global_position
	await get_tree().create_timer(4.0).timeout
	var movido: float = z1.global_position.distance_to(p0)
	print("[dormidos] quieto 4 s: se ha movido %.2f m, dormida %s" % [movido, str(z1.dormida)])
	jugador.global_position = z1.global_position + Vector3(8.0, 0.0, 0.0)
	await get_tree().create_timer(1.0).timeout
	print("[dormidos] a 8 m: dormida %s" % str(z1.dormida))
	var ok1: bool = movido < 0.5 and not z1.dormida
	_sacar("zombi", Vector3(140.0, 1.2, 41.0))
	var z2 = _vivos.back()
	z2.dormir()
	jugador.global_position = Vector3(140.0, 1.2, 41.0) + Vector3(-25.0, 0.0, 0.0)
	get_tree().call_group("enemies", "hear_noise", jugador.global_position, 50.0)
	await get_tree().create_timer(0.5).timeout
	print("[dormidos] tiro a 25 m: dormida %s" % str(z2.dormida))
	var ok2: bool = not z2.dormida
	print("[dormidos] %s" % ("TODO BIEN" if ok1 and ok2 else "FALLO"))
	get_tree().quit()


# ======================================================================================================
# LA MUSICA (Left 4 Dead 2: godot/sounds/l4d2/musica, tools/importar_l4d2.py). Va por los EVENTOS de la
# historia, asi que suena igual en todas las maquinas:
#   fondo    el ambiente de No Mercy en bucle (una pista tras otra) y, cada poco, una capa de tension
#   horda    el aviso segun su tamaño y los tambores de combate mientras dura
#   tank     su tema mientras siga vivo (manda sobre todo lo demas)
#   capas    refugio, final (la radio), rescate, huida, muerte, y el aviso de los especiales
# Por el bus Master y con el volumen de musica de los ajustes.
# ======================================================================================================
const MUSICA := "l4d2/musica/"
var _mus_fondo: AudioStreamPlayer = null
var _mus_capa: AudioStreamPlayer = null
var _mus_combate: AudioStreamPlayer = null
var _mus_tank: AudioStreamPlayer = null
var _tension_t := 40.0
var _combate_t := 0.0            ## s que le quedan a los tambores de la horda
var _mus_prioridad := false      ## la capa que suena es de las que no se pisan (refugio, final, rescate...)

func _mus_db(base: float) -> float:
	# el ajuste de musica va de 0 a 1 y esta pensado para el lobby (0,10 por defecto): aqui ese 0,10 es el
	# volumen normal de la campaña, y el ajuste la sube o la baja a partir de ahi
	return base + linear_to_db(clampf(float(Settings.music_volume) / 0.02, 0.0001, 2.0))


func _mus_player(nombre: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = nombre
	p.bus = "Master"
	add_child(p)
	return p


func _musica_montar() -> void:
	if Audio.sin_bf or not DirAccess.dir_exists_absolute("res://sounds/l4d2/musica"):
		return
	_mus_fondo = _mus_player("MusicaFondo")
	_mus_capa = _mus_player("MusicaCapa")
	_mus_combate = _mus_player("MusicaCombate")
	_mus_tank = _mus_player("MusicaTank")
	_mus_fondo.finished.connect(_mus_siguiente_fondo)
	_mus_combate.finished.connect(func():
		if _combate_t > 0.0:
			_mus_sonar(_mus_combate, "combate", -6.0))
	_mus_capa.finished.connect(func(): _mus_prioridad = false)
	_mus_siguiente_fondo()
	print("[campana] musica: fondo %s" % ("sonando" if _mus_fondo.playing else "SIN PISTAS"))


func _mus_sonar(p: AudioStreamPlayer, clave: String, db: float) -> bool:
	if p == null:
		return false
	var st: AudioStream = Audio._pick(MUSICA + clave)
	if st == null:
		return false
	p.stream = st
	p.volume_db = _mus_db(db)
	p.play()
	return true


func _mus_siguiente_fondo() -> void:
	_mus_sonar(_mus_fondo, "ambiente", -12.0 if (_combate_t > 0.0 or (_mus_tank and _mus_tank.playing)) else -6.0)


## Una pista suelta encima del fondo. `prioridad`: las de la historia; mientras suenan, los avisos de
## especiales y la tension no las pisan.
func _musica_capa(clave: String, db: float, prioridad := false) -> void:
	if _mus_capa == null:
		return
	if _mus_capa.playing and _mus_prioridad and not prioridad:
		return
	if _mus_sonar(_mus_capa, clave, db):
		_mus_prioridad = prioridad


func _musica_horda(n: int) -> void:
	if _mus_capa == null:
		return
	var tam := "horda_s" if n < 8 else ("horda_m" if n < 14 else ("horda_l" if n < 20 else "horda_x"))
	if not (_mus_capa.playing and _mus_prioridad):
		_mus_sonar(_mus_capa, tam, -2.0)
	_combate_t = maxf(_combate_t, 18.0 + n * 1.2)
	if not _mus_combate.playing and not (_mus_tank and _mus_tank.playing):
		# los tambores entran cuando acaba el aviso (unos 6 s)
		get_tree().create_timer(5.5).timeout.connect(func():
			if _combate_t > 0.0 and not _mus_combate.playing:
				_mus_sonar(_mus_combate, "combate", -6.0))


func _musica_tank(on: bool) -> void:
	if _mus_tank == null:
		return
	if on:
		if not _mus_tank.playing:
			_mus_sonar(_mus_tank, "tank", -2.0)
			if _mus_tank.stream is AudioStreamOggVorbis:
				(_mus_tank.stream as AudioStreamOggVorbis).loop = true
		_mus_combate.stop()
		_mus_fondo.volume_db = _mus_db(-14.0)
	elif _mus_tank.playing:
		var tw := _mus_tank.create_tween()
		tw.tween_property(_mus_tank, "volume_db", -60.0, 2.5)
		tw.tween_callback(_mus_tank.stop)
		_mus_fondo.volume_db = _mus_db(-6.0)


var _mus_reintento := 0.0

func _musica_tick(dt: float) -> void:
	if _mus_fondo == null:
		return
	# EL FONDO, EN CUANTO ESTE CARGADO (2026-09-27): el audio ya no carga nada en el hilo principal en partida y
	# los bancos llegan en hilos a los pocos segundos; al montar la musica aun no estaban y el fondo no sonaba nunca
	if not _mus_fondo.playing:
		_mus_reintento -= dt
		if _mus_reintento <= 0.0:
			_mus_reintento = 1.5
			_mus_siguiente_fondo()
	if _combate_t > 0.0:
		_combate_t -= dt
		if _combate_t <= 0.0 and _mus_combate.playing:
			var tw := _mus_combate.create_tween()
			tw.tween_property(_mus_combate, "volume_db", -60.0, 2.0)
			tw.tween_callback(_mus_combate.stop)
	# (LA TENSION al azar se quito: sonaba un susto sin que pasara nada. Pedido del usuario, 2026-09-24)
	_ver_especiales(dt)


## --gordoportontest: el gordo revienta con su animacion (sin fisica) y su explosion daña a los zombis de al
## lado; y un zombi despierto al otro lado del porton cerrado no lo cruza
func _prueba_gordo_porton() -> void:
	await get_tree().create_timer(4.0).timeout
	fase = "porton"
	jugador.global_position = Vector3(90.0, 1.2, 74.0)
	jugador.set("invulnerable", true)
	await get_tree().create_timer(0.5).timeout
	var c0 := Vector3(110.0, 1.2, 74.0)
	_sacar("gordo", c0)
	var g = _vivos.back()
	var otros: Array = []
	for dx in [-1.5, 1.5, 0.0]:
		_sacar("zombi", c0 + Vector3(dx, 0, 1.5))
		otros.append(_vivos.back())
	await get_tree().create_timer(0.3).timeout
	var vidas0: Array = otros.map(func(o): return float(o.vida))
	g.take_damage(1.0e6)
	var clip_ok: bool = g._anim != null and g._anim.is_playing() and String(g._anim_actual).contains("muerte")
	print("[gordoporton] gordo muerto: animacion de muerte sonando %s, cuerpo con fisica %s" % [str(clip_ok), str(g.get_parent() == null)])
	await get_tree().create_timer(4.0).timeout
	var danados := 0
	for i in otros.size():
		if not is_instance_valid(otros[i]) or bool(otros[i].muerta) or float(otros[i].vida) < float(vidas0[i]):
			danados += 1
	print("[gordoporton] zombis alcanzados por la explosion: %d de %d" % [danados, otros.size()])
	# el porton: uno despierto al oeste, el jugador al este
	_sacar("zombi", Vector3(52.0, 1.2, 74.0))
	var z = _vivos.back()
	await get_tree().create_timer(10.0).timeout
	print("[gordoporton] zombi al otro lado tras 10 s: x=%.1f (el porton esta en x 62-63)" % z.global_position.x)
	var ok: bool = clip_ok and danados >= 2 and z.global_position.x < 61.5
	print("[gordoporton] %s" % ("TODO BIEN" if ok else "FALLO"))
	get_tree().quit()


# ======================================================================================================
# BOTIQUINES Y MUNICION POR EL MAPA (objeto_campana.gd). Sitios fijos -como el original: la mesa de la
# azotea, el refugio, la farmacia, el control militar, la azotea del hospital- y unos cuantos al azar por
# el recorrido, distintos en cada partida.
# ======================================================================================================
var _objetos: Dictionary = {}      ## id -> nodo
var _lista_objetos: Array = []     ## [[id, tipo, x, y, z]] (el anfitrion la guarda para quien la pida)

const OBJ_SEPARACION := 16.0     ## m minimos entre dos objetos sueltos del mapa
const OBJ_BOTIQUINES := 9
const OBJ_MUNICION := 11

func _repartir_objetos() -> void:
	var lista: Array = []
	var nid := 1
	var puestos: Array = []          ## [Vector3] ya colocados (para la separacion)
	var sal: Vector3 = _v(cfg.get("salida", [0, 0, 0]))
	var y_az: float = sal.y
	# LA MESA DE LA SALIDA, como en Left 4 Dead: un botiquin por cabeza (cuatro jugadores) en fila
	var mesa: Vector3 = _v(cfg.get("mesa", [14.45, y_az + 1.2, 11.8]))
	for i in 4:
		lista.append([nid, "botiquin_mesa", mesa.x + i * 0.6, mesa.y, mesa.z, PI * 0.5]); nid += 1
	puestos.append(mesa + Vector3(0.9, 0, 0))
	if cfg.has("municion_mesa"):
		var mm: Vector3 = _v(cfg["municion_mesa"])
		lista.append([nid, "municion", mm.x, mm.y, mm.z, 0.0]); nid += 1
	var ref: Dictionary = cfg.get("refugio", {})
	var ref_rect: Array = ref.get("rect", []) if not ref.is_empty() else []
	# SITIOS CON SENTIDO: el refugio (una caja de municion), las tiendas (la farmacia: un botiquin) y los
	# sitios de pelea (municion). Cada uno se comprueba y se corre al hueco libre mas cercano, contra pared.
	var fijos: Array = []
	if not ref_rect.is_empty():
		fijos.append(["municion", Vector3((float(ref_rect[0]) + float(ref_rect[2])) / 2 - 2.0, 1.0, float(ref_rect[3]) - 1.6)])
	for b in cfg.get("botin", []):
		fijos.append(["botiquin", Vector3(float(b[0]), float(b[1]), float(b[2]))])
	for p in cfg.get("municion_fija", [[120.0, 1.0, 70.0], [100.0, 1.0, 138.0], [138.0, 20.2, 130.0], [33.0, 1.0, 27.5]]):
		fijos.append(["municion", Vector3(p[0], p[1], p[2])])
	for f in fijos:
		var sitio = _sitio_contra_pared(f[1])
		if sitio != null and _lejos_de(puestos, sitio[0], 8.0):
			lista.append([nid, f[0], sitio[0].x, sitio[0].y, sitio[0].z, sitio[1]]); nid += 1
			puestos.append(sitio[0])
	# Y POR EL RECORRIDO, AL AZAR Y SEPARADOS: se recorre la ruta a trozos de 5 m, en cada trozo se busca una
	# pared cerca (a un lado de la calle, en un rincon del piso) y se deja ahi si no hay otro objeto a
	# menos de OBJ_SEPARACION. Distinto cada partida, pero nunca metido en un muro ni flotando.
	var cand: Array = []
	for k in range(1, ruta.size()):
		var a: Vector3 = ruta[k - 1]
		var b: Vector3 = ruta[k]
		var largo := a.distance_to(b)
		var n := maxi(1, int(largo / 5.0))
		for m in n:
			cand.append(a.lerp(b, (m + randf()) / n))
	cand.shuffle()
	var faltan := {"botiquin": OBJ_BOTIQUINES, "municion": OBJ_MUNICION}
	var turno := 0
	for q in cand:
		if faltan["botiquin"] <= 0 and faltan["municion"] <= 0:
			break
		if not ref_rect.is_empty() and q.x > float(ref_rect[0]) - 3 and q.x < float(ref_rect[2]) + 3 \
				and q.z > float(ref_rect[1]) - 3 and q.z < float(ref_rect[3]) + 3:
			continue
		if q.distance_to(sal) < 12.0:
			continue
		var sitio = _sitio_contra_pared(q + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))
		if sitio == null or not _lejos_de(puestos, sitio[0], OBJ_SEPARACION):
			continue
		var t := "botiquin" if turno % 2 == 0 else "municion"
		if faltan[t] <= 0:
			t = "municion" if t == "botiquin" else "botiquin"
		faltan[t] -= 1
		turno += 1
		lista.append([nid, t, sitio[0].x, sitio[0].y, sitio[0].z, sitio[1]]); nid += 1
		puestos.append(sitio[0])
	_lista_objetos = lista
	_evento("objetos", lista)
	print("[campana] objetos repartidos: %d (%d botiquines y %d de municion por el mapa)" % [lista.size(),
		lista.filter(func(o): return String(o[1]) == "botiquin").size(), lista.filter(func(o): return String(o[1]) == "municion").size()])


func _lejos_de(puestos: Array, p: Vector3, d: float) -> bool:
	for q in puestos:
		if (q as Vector3).distance_to(p) < d:
			return false
	return true


## ¿Cabe aqui un objeto? Suelo de verdad debajo (a menos de 2,5 m), su caja libre de voxels y 1,9 m de aire
## encima (nada de meterlo bajo una escalera o dentro de un muro). Devuelve el punto del suelo o null.
func _sitio_libre(p: Vector3) -> Variant:
	var h: Dictionary = world.raycast(p + Vector3.UP * 1.2, Vector3.DOWN, 3.7)
	if not h.get("hit", false):
		return null
	var f: Vector3 = h["position"]
	if world.box_solid(f + Vector3(-0.28, 0.06, -0.28), f + Vector3(0.28, 0.55, 0.28)):
		return null
	if world.raycast(f + Vector3.UP * 0.1, Vector3.UP, 1.9).get("hit", false):
		return null
	# que el suelo sea suelo (no el borde de una cornisa): los cuatro rincones tambien apoyan
	for e in [Vector3(0.25, 0, 0.25), Vector3(-0.25, 0, 0.25), Vector3(0.25, 0, -0.25), Vector3(-0.25, 0, -0.25)]:
		var he: Dictionary = world.raycast(f + e + Vector3.UP * 0.3, Vector3.DOWN, 0.6)
		if not he.get("hit", false):
			return null
	return f


## Busca, cerca de `p`, un hueco libre PEGADO A UNA PARED (como se deja una caja en la vida real) y el giro
## para que mire hacia fuera. [punto, giro] o null.
func _sitio_contra_pared(p: Vector3) -> Variant:
	var base = _sitio_libre(p)
	if base == null:
		for r in [1.0, 2.0, 3.0]:
			for k in 8:
				var ang := TAU * k / 8.0
				base = _sitio_libre(p + Vector3(cos(ang), 0, sin(ang)) * r)
				if base != null:
					break
			if base != null:
				break
	if base == null:
		return null
	var mejor = null
	var mejor_d := 99.0
	for k in 8:
		var ang := TAU * k / 8.0
		var dir := Vector3(cos(ang), 0, sin(ang))
		var hw: Dictionary = world.raycast(base + Vector3.UP * 0.35, dir, 6.0)
		if not hw.get("hit", false):
			continue
		var d: float = (base + Vector3.UP * 0.35).distance_to(hw["position"])
		if d < mejor_d:
			var junto = _sitio_libre(base + dir * maxf(0.0, d - 0.42))
			if junto != null:
				mejor_d = d
				mejor = [junto, atan2(-dir.x, -dir.z) + PI]
	if mejor != null:
		return mejor
	return [base, randf() * TAU]


func _crear_objeto(oid: int, tipo: String, p: Vector3, giro = null) -> void:
	if _objetos.has(oid):
		return
	var o: Node3D = ObjetoCampana.new()
	if giro != null:
		o.giro_fijo = true
		o.rotation.y = float(giro)
	o.en_fila = tipo.ends_with("_mesa")            # en la mesa, en fila y sin girar (no se montan unos en otros)
	o.tipo = tipo.trim_suffix("_mesa")
	o.id = oid
	o.jugador = jugador
	o.world = world
	add_child(o)
	o.global_position = p
	o.recogido.connect(_objeto_recogido)
	_objetos[oid] = o


func _objeto_recogido(o: Node3D) -> void:
	var oid: int = int(o.id)
	if _en_red and not _soy_host:
		Net.net_campana_pide("coger:%d" % oid)
		o.queue_free()
		_objetos.erase(oid)
	else:
		_evento("quita_objeto", [oid])


# ======================================================================================================
# EL EQUIPO, ARRIBA A LA IZQUIERDA (2026-09-24, pedido, "como el juego de verdad"): el boton de curarse con
# el botiquin y, al lado, un circulo por jugador con su cara (el retrato del personaje, como en el lobby),
# un anillo de vida que baja cuando le dañan y su nombre de cuenta debajo. Con dos jugadores, dos.
# ======================================================================================================
const LobbyScript := preload("res://scripts/lobby.gd")
const RETRATO_TAM := 62.0
const MASCARA_CIRCULO := """
shader_type canvas_item;
uniform float gris = 0.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float r = length(UV - vec2(0.5));
	c.a *= 1.0 - smoothstep(0.47, 0.5, r);
	float l = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	c.rgb = mix(c.rgb, vec3(l) * 0.6, gris);
	COLOR = c;
}
"""
var _capa_equipo: CanvasLayer = null
var _fila_equipo: HBoxContainer = null
var _btn_cura: Button = null
var _retratos: Dictionary = {}      ## id -> {caja, cara, anillo, nombre, vida, max, skin}
var _equipo_t := 0.0
var _vida_envio_t := 0.0
var _caras: Dictionary = {}         ## skin -> Texture2D (recortada y cacheada)
var _shader_circulo: Shader = null

func _montar_equipo() -> void:
	_capa_equipo = CanvasLayer.new()
	_capa_equipo.layer = 2
	add_child(_capa_equipo)
	_fila_equipo = HBoxContainer.new()
	_fila_equipo.position = Vector2(16, 14)
	_fila_equipo.add_theme_constant_override("separation", 10)
	_fila_equipo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_capa_equipo.add_child(_fila_equipo)
	# el boton del botiquin
	_btn_cura = Button.new()
	_btn_cura.custom_minimum_size = Vector2(66, 66)
	_btn_cura.focus_mode = Control.FOCUS_NONE
	_btn_cura.tooltip_text = "" if Settings.is_touch() else "Curarse con el botiquín (H)"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.07, 0.78)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	for k in ["normal", "hover", "pressed", "disabled", "focus"]:
		_btn_cura.add_theme_stylebox_override(k, sb)
	_btn_cura.pressed.connect(func():
		if is_instance_valid(jugador) and jugador.has_method("usar_cura"):
			jugador.usar_cura("botiquin"))
	_btn_cura.draw.connect(_dibujar_boton_cura)
	_fila_equipo.add_child(_btn_cura)
	_shader_circulo = Shader.new()
	_shader_circulo.code = MASCARA_CIRCULO
	if is_instance_valid(jugador) and jugador.has_signal("health_changed"):
		jugador.health_changed.connect(func(_v): _mandar_vida())
	_equipo_tick(1.0)


func _dibujar_boton_cura() -> void:
	var b := _btn_cura
	var c := b.size * 0.5 + Vector2(0, -4)
	var lleva: int = int(jugador.get("botiquines")) if is_instance_valid(jugador) else 0
	var curando: bool = is_instance_valid(jugador) and String(jugador.get("curando")) != ""
	var rojo := Color(0.85, 0.12, 0.10) if lleva > 0 else Color(0.35, 0.20, 0.20)
	var blanco := Color(1, 1, 1) if lleva > 0 else Color(0.5, 0.5, 0.5)
	# la bolsa y su cruz
	b.draw_rect(Rect2(c - Vector2(20, 13), Vector2(40, 26)), rojo, true)
	b.draw_rect(Rect2(c - Vector2(20, 13), Vector2(40, 26)), Color(0, 0, 0, 0.5), false, 2.0)
	b.draw_rect(Rect2(c - Vector2(9, 3), Vector2(18, 6)), blanco, true)
	b.draw_rect(Rect2(c - Vector2(3, 9), Vector2(6, 18)), blanco, true)
	b.draw_rect(Rect2(c + Vector2(-7, -18), Vector2(14, 5)), Color(0.1, 0.1, 0.1), true)
	var f := ThemeDB.fallback_font
	var txt := "CURANDO" if curando else ("H" if lleva > 0 else "SIN")
	var w: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	b.draw_string(f, Vector2((b.size.x - w) * 0.5, b.size.y - 5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(1.0, 0.85, 0.3) if curando else Color(0.85, 0.87, 0.9))


func _mandar_vida() -> void:
	if not is_instance_valid(jugador):
		return
	var m: float = jugador.vida_max() if jugador.has_method("vida_max") else 100.0
	var v: float = 0.0 if bool(jugador.get("spectating")) else float(jugador.get("health"))
	Net.net_vida(v, m)


func _cara(skin: String) -> Texture2D:
	if _caras.has(skin):
		return _caras[skin]
	var ruta := "res://avatar/retratos/%s.png" % skin.to_lower().replace(" ", "_")
	var tex: Texture2D = null
	if ResourceLoader.exists(ruta):
		var t = load(ruta)
		if t is Texture2D:
			var img: Image = (t as Texture2D).get_image()
			if img != null:
				# el mismo recorte de la cara que el lobby (_cara_perfil)
				var reg := Rect2i(112, 0, 108, 108).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
				tex = ImageTexture.create_from_image(img.get_region(reg))
	_caras[skin] = tex
	return tex


func _mi_skin() -> String:
	var i := clampi(int(Settings.avatar_skin), 0, LobbyScript.SKINS.size() - 1)
	return String(LobbyScript.SKINS[i]["n"])


func _equipo_tick(dt: float) -> void:
	if _fila_equipo == null:
		return
	_vida_envio_t -= dt
	if _vida_envio_t <= 0.0:
		_vida_envio_t = 1.5
		_mandar_vida()
	_equipo_t -= dt
	if _btn_cura:
		_btn_cura.queue_redraw()
	if _equipo_t > 0.0:
		for id in _retratos:
			(_retratos[id]["anillo"] as Control).queue_redraw()
		return
	_equipo_t = 0.25
	# quien hay: yo y los de la sala
	var yo: int = multiplayer.get_unique_id() if _en_red else 1
	var ids: Array = [yo]
	if _en_red:
		for id in Net.players.keys():
			if int(id) != yo:
				ids.append(int(id))
	for id in _retratos.keys():
		if not (id in ids):
			(_retratos[id]["caja"] as Control).queue_free()
			_retratos.erase(id)
	for id in ids:
		var skin := _mi_skin() if id == yo else _skin_de(id)
		var nombre := String(Settings.player_name) if id == yo else String((Net.players.get(id, {}) as Dictionary).get("name", "Jugador"))
		if not _retratos.has(id):
			_retratos[id] = _crear_retrato(nombre)
		var r: Dictionary = _retratos[id]
		if String(r.get("skin", "")) != skin:
			r["skin"] = skin
			(r["cara"] as TextureRect).texture = _cara(skin)
		(r["nombre"] as Label).text = nombre
		if id == yo:
			r["vida"] = 0.0 if bool(jugador.get("spectating")) else float(jugador.get("health"))
			r["max"] = jugador.vida_max() if jugador.has_method("vida_max") else 100.0
		else:
			var vv: Array = Net.vidas.get(id, [100.0, 100.0])
			r["vida"] = 0.0 if bool(Net.dead_players.get(id, false)) else float(vv[0])
			r["max"] = float(vv[1])
		var caido: bool = float(r["vida"]) <= 0.0
		((r["cara"] as TextureRect).material as ShaderMaterial).set_shader_parameter("gris", 1.0 if caido else 0.0)
		(r["anillo"] as Control).queue_redraw()


func _skin_de(id: int) -> String:
	var np = Net.remotes.get(id)
	if np != null and is_instance_valid(np) and "_aspecto_actual" in np:
		var a := String(np.get("_aspecto_actual"))
		if a != "":
			return a.split("|")[0]
	return _mi_skin()


func _crear_retrato(nombre: String) -> Dictionary:
	var caja := VBoxContainer.new()
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_theme_constant_override("separation", 2)
	_fila_equipo.add_child(caja)
	var marco := Control.new()
	marco.custom_minimum_size = Vector2(RETRATO_TAM + 10, RETRATO_TAM + 10)
	marco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(marco)
	var fondo := Panel.new()
	var sbf := StyleBoxFlat.new()
	sbf.bg_color = Color(0.05, 0.05, 0.06, 0.85)
	sbf.set_corner_radius_all(int(RETRATO_TAM))
	fondo.add_theme_stylebox_override("panel", sbf)
	fondo.position = Vector2(5, 5)
	fondo.size = Vector2(RETRATO_TAM, RETRATO_TAM)
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marco.add_child(fondo)
	var cara := TextureRect.new()
	cara.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cara.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cara.position = Vector2(5, 5)
	cara.size = Vector2(RETRATO_TAM, RETRATO_TAM)
	cara.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = _shader_circulo
	cara.material = sm
	marco.add_child(cara)
	var anillo := Control.new()
	anillo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anillo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marco.add_child(anillo)
	var etiqueta := Label.new()
	etiqueta.text = nombre
	etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	etiqueta.custom_minimum_size = Vector2(RETRATO_TAM + 10, 0)
	etiqueta.clip_text = true
	etiqueta.add_theme_font_size_override("font_size", 12)
	etiqueta.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	etiqueta.add_theme_constant_override("shadow_offset_y", 1)
	caja.add_child(etiqueta)
	var r := {"caja": caja, "cara": cara, "anillo": anillo, "nombre": etiqueta, "vida": 100.0, "max": 100.0, "vista": 100.0}
	anillo.draw.connect(_dibujar_anillo.bind(anillo, r))
	return r


## El anillo de vida: carril oscuro y, encima, lo que queda de vida (verde, amarillo, rojo). Baja poco a poco
## (se ve caer el golpe) y, recien dañado, parpadea en blanco un instante.
func _dibujar_anillo(anillo: Control, r: Dictionary) -> void:
	var c := anillo.size * 0.5
	var radio := RETRATO_TAM * 0.5 + 2.5
	var objetivo: float = clampf(float(r["vida"]) / maxf(float(r["max"]), 1.0), 0.0, 1.0)
	var vista: float = float(r.get("vista", objetivo))
	var golpe := false
	if vista > objetivo + 0.002:
		vista = move_toward(vista, objetivo, 0.02)
		golpe = true
	else:
		vista = objetivo
	r["vista"] = vista
	anillo.draw_arc(c, radio, 0.0, TAU, 64, Color(0, 0, 0, 0.7), 7.0, true)
	var col := Color(0.25, 0.85, 0.35) if objetivo > 0.6 else (Color(0.95, 0.80, 0.15) if objetivo > 0.3 else Color(0.95, 0.20, 0.15))
	if golpe:
		# lo que se acaba de perder, en blanco, antes de apagarse
		anillo.draw_arc(c, radio, -PI * 0.5, -PI * 0.5 + TAU * vista, 64, Color(1, 1, 1, 0.85), 5.0, true)
	if objetivo > 0.0:
		anillo.draw_arc(c, radio, -PI * 0.5, -PI * 0.5 + TAU * objetivo, 64, col, 5.0, true)
	else:
		var f := ThemeDB.fallback_font
		var w: float = f.get_string_size("CAÍDO", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		anillo.draw_string(f, c + Vector2(-w * 0.5, 4), "CAÍDO", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.3, 0.25))


func _on_cura_otro(de: int, evento: String, nombre: String = "") -> void:
	if is_instance_valid(jugador) and jugador.has_method("curado_evento"):
		if nombre == "":
			nombre = String((Net.players.get(de, {}) as Dictionary).get("name", "compañero"))
		jugador.curado_evento(de, nombre, evento)


## --curaotrotest (banco LAN, en las dos copias): el invitado se queda a 40 de vida y quieto; el anfitrion
## coge un botiquin, se pone a su lado y lo cura. El invitado dice como acaba.
func _prueba_cura_otro() -> void:
	await get_tree().create_timer(14.0).timeout
	if not _en_red:
		print("[curaotro] sin red"); return
	if not _soy_host:
		jugador.health = 40.0
		jugador.health_changed.emit(40.0)
		_mandar_vida()
		for i in 14:
			await get_tree().create_timer(1.0).timeout
			print("[curaotro] invitado: vida %.0f  barra %s" % [float(jugador.health), str(jugador.get("_curado_por"))])
		print("[curaotro] invitado FIN vida %.0f -> %s" % [float(jugador.health), "TODO BIEN" if jugador.health >= jugador.vida_max() - 0.5 else "FALLA"])
		return
	await get_tree().create_timer(2.0).timeout
	var ids: Array = Net.remotes.keys()
	if ids.is_empty():
		print("[curaotro] FALLA: no hay invitado"); return
	var pid := int(ids[0])
	jugador.coger_cura("botiquin", 3)
	print("[curaotro] anfitrion: botiquines %d (tope 1)  vida del otro %s" % [int(jugador.botiquines), str(Net.vidas.get(pid))])
	jugador.global_position = (Net.remotes[pid] as Node3D).global_position + Vector3(0.8, 0.3, 0)
	await get_tree().create_timer(1.0).timeout
	_usables_tick()
	print("[curaotro] anfitrion: boton sobre el companero: %s" % _usable_mirado)
	jugador.curar_a(pid, "prueba")
	await get_tree().create_timer(7.5).timeout
	print("[curaotro] anfitrion FIN: botiquines %d, curando '%s'" % [int(jugador.botiquines), String(jugador.curando)])


## LOS QUE SE QUEDAN ABAJO EN EL FINAL TREPAN (como en Left 4 Dead, que suben por las fachadas): el que lleve
## unos segundos en la calle, a mas de 4 m por debajo de la azotea, aparece asomando por el peto. Asi nadie se
## queda debajo esperando (ni rompiendo el techo) y tu no tienes que bajar a por el.
var _abajo_t: Dictionary = {}

func _trepar_a_la_azotea() -> void:
	var az: Array = cfg.get("azotea_hospital", [])
	if az.size() < 5 or (_en_red and not _soy_host):
		return
	var y_az: float = float(az[1])
	for c in _vivos:
		if not is_instance_valid(c) or bool(c.muerta):
			continue
		var k: int = c.get_instance_id()
		if (c as Node3D).global_position.y > y_az - 4.0:
			_abajo_t.erase(k)
			continue
		_abajo_t[k] = float(_abajo_t.get(k, 0.0)) + 0.5
		if float(_abajo_t[k]) < 3.0:
			continue
		var p = _punto_azotea(6.0)
		if p != null:
			if c.has_method("despertar"):
				c.despertar(false)
			if _trepa_desde != null and c.has_method("trepar"):
				c.trepar(_trepa_desde, p)
			else:
				(c as Node3D).global_position = p
			_abajo_t.erase(k)


## --finaltest: el final de la radio con el jugador en el helipuerto, invulnerable. Cada 10 s: cuantos bichos
## hay arriba y abajo, y cuantos boquetes han hecho (tiene que ser 0: en la campana no rompen)
func _prueba_final() -> void:
	await get_tree().create_timer(5.0).timeout
	var az: Array = cfg.get("azotea_hospital", [])
	var y_az: float = float(az[1])
	jugador.set("invulnerable", true)
	jugador.global_position = _v(cfg["helipuerto"]) + Vector3(0, 0.6, 0)
	fase = "radio"
	_usar_radio()
	var max_abajo := 0
	for f in OS.get_cmdline_user_args():
		if String(f).begins_with("--fototrepar="):
			# foto de uno trepando: la camara en la azotea, mirando por encima del peto
			var ruta := String(f).substr(13)
			var centro := Vector3((float(az[0]) + float(az[3])) / 2, y_az, (float(az[2]) + float(az[4])) / 2)
			for intento in 80:
				await get_tree().create_timer(0.1).timeout
				var cual = null
				for c in _vivos:
					if is_instance_valid(c) and bool(c.trepando) and (c as Node3D).global_position.y > y_az - 1.6 and (c as Node3D).global_position.y < y_az:
						cual = c
						break
				if cual == null:
					continue
				var cp: Vector3 = (cual as Node3D).global_position
				var hacia := Vector3(centro.x - cp.x, 0, centro.z - cp.z).normalized()
				var cf := Camera3D.new()
				add_child(cf)
				cf.global_position = cp - hacia * 4.0 + Vector3(0, 1.5, 0) + hacia.cross(Vector3.UP) * 2.0
				cf.look_at(cp + Vector3(0, 0.3, 0))
				print("[final] trepando en %s (azotea a %.1f)" % [str(cp), y_az])
				cf.make_current()
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(ruta)
				print("[final] foto trepando: ", ruta)
				get_tree().quit()
				return
	for i in 9:
		await get_tree().create_timer(10.0).timeout
		var arriba := 0
		var abajo := 0
		var boquetes := 0
		for c in _vivos:
			if not is_instance_valid(c):
				continue
			boquetes += int(c.dg_romper)
			if (c as Node3D).global_position.y > y_az - 4.0:
				arriba += 1
			else:
				abajo += 1
		if i >= 2:
			max_abajo = maxi(max_abajo, abajo)
		jugador.global_position = _v(cfg["helipuerto"]) + Vector3(0, 0.6, 0)
		print("[final] %d s: oleada %d · arriba %d · abajo %d · boquetes %d · bajas %d" % [(i + 1) * 10, _final_ola + 1, arriba, abajo, boquetes, bajas])
	print("[final] %s" % ("TODO BIEN" if max_abajo <= 2 else "FALLA: se quedan abajo"))


## --objetostest: los objetos del mapa ni metidos en muros ni amontonados, y se cogen con el boton
func _prueba_objetos() -> void:
	await get_tree().create_timer(5.0).timeout
	jugador.set("invulnerable", true)
	fase = "inicio"
	var malos := 0
	var juntos := 0
	var sueltos: Array = []
	for oid in _objetos:
		var o: Node3D = _objetos[oid]
		if bool(o.en_fila):
			continue
		var f: Vector3 = o.global_position
		if world.box_solid(f + Vector3(-0.2, 0.08, -0.2), f + Vector3(0.2, 0.5, 0.2)):
			malos += 1
			print("[objetos] METIDO EN UN MURO: %s en %s" % [o.tipo, str(f)])
		var h: Dictionary = world.raycast(f + Vector3.UP * 0.3, Vector3.DOWN, 0.6)
		if not h.get("hit", false):
			malos += 1
			print("[objetos] FLOTANDO: %s en %s" % [o.tipo, str(f)])
		for q in sueltos:
			if (q as Vector3).distance_to(f) < 8.0:
				juntos += 1
		sueltos.append(f)
	print("[objetos] %d sueltos · mal puestos %d · pares a menos de 8 m %d" % [sueltos.size(), malos, juntos])
	# coger con el boton: un botiquin y una caja de municion
	var cogidos := 0
	for t in ["botiquin", "municion"]:
		for oid in _objetos.keys():
			var o: Node3D = _objetos[oid]
			if String(o.tipo) != t or bool(o.en_fila):
				continue
			jugador.global_position = o.global_position + Vector3(0.8, 0.2, 0)
			if t == "municion":
				jugador.set_reserve(jugador.current, 0)      # con la reserva llena no se ofrece la caja
			await get_tree().create_timer(1.5).timeout
			var antes: int = int(jugador.botiquines)
			var sigue_ahi_sin_boton := is_instance_valid(o)
			_usables_tick()
			print("[objetos] junto a %s: boton '%s' (sin pulsar, sigue en el suelo: %s)" % [t, _usable_mirado, str(sigue_ahi_sin_boton)])
			usar_desde_jugador()
			await get_tree().create_timer(0.5).timeout
			var ok: bool = not _objetos.has(oid) and (t != "botiquin" or int(jugador.botiquines) == antes + 1)
			print("[objetos] cogido %s: %s" % [t, str(ok)])
			if ok and sigue_ahi_sin_boton:
				cogidos += 1
			break
	print("[objetos] %s" % ("TODO BIEN" if malos == 0 and juntos == 0 and cogidos == 2 else "FALLA"))
