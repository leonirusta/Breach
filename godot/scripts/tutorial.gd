extends Node
## EL TUTORIAL (2026-10-04, pedido: "un mapa muy chico para un tutorial: empieza con el mazo para romper una pared y
## entrar, recoges la metralleta que te regalan y la pruebas, destruyes unas columnas para que caiga una viga y subes,
## te enseña a trepar, las granadas, y te explica las fisicas del juego haciendo destruccion. Al completarlo vas al
## lobby. Cuando sos nuevo").
##
## El mapa es `tutorial` (tools/generar_mapa_tutorial.py) y trae `maps/tutorial.tutorial.json` con donde esta cada cosa.
## Lo arranca main._empezar_tutorial; el vestibulo lo pide al cerrar la carta de bienvenida la primera vez
## (lobby._lanzar_tutorial). Solo, sin red y sin bots.
##
## CADA PASO SE DA POR HECHO MIRANDO EL MUNDO, no por eventos: el tapiado tiene un hueco por el que cabes, las dianas
## ya no estan, la losa ya no esta donde estaba, estas encima del mirador... Asi el orden en que hagas las cosas da igual
## y nunca hay forma de atascarse: si rompes las columnas antes de tiempo, ese paso pasa solo al llegar a el.
##
## Pruebas: --map=tutorial (o --tutorial) y --tutorialtest (lo recorre solo y dice TODO BIEN o lo que falla);
## fotos: --tutorialfoto=<carpeta>.

const FuentesScript := preload("res://scripts/fuentes.gd")
const AvisoUsar := preload("res://scripts/aviso_usar.gd")

const ACENTO := Color(1.0, 0.8, 0.12)          ## el amarillo del objetivo (el de los numeros pintados en el mapa)
const VERDE := Color(0.45, 0.95, 0.55)
const CIAN := Color(0.45, 0.85, 1.0)           ## el de las tarjetas de FISICA
const FONDO := Color(0.055, 0.065, 0.085, 0.9)

var main: Node = null
var world = null
var jugador = null
var hud = null
var cfg: Dictionary = {}
var paso := -1
var _t_paso := 0.0
var _chk := 0.0
var _tactil := false
var _hecho := false             ## el tutorial ya se dio por terminado (o saltado)

## voxels de cada cosa al empezar: el paso se da por hecho cuando quedan pocos donde estaban
var _vox_dianas: Array = []
var _vox_losa := 0
var _vox_deposito := 0

var _arma: Node3D = null        ## el subfusil de la mesa (null cuando ya lo tienes)
var _tiene_arma := false
var _rampa: Node3D = null
var _rampa_caida := false
var _aviso: Button = null
var _cajas_pasadas := false

# --- la interfaz ---
var _capa: CanvasLayer
var _tarjeta: PanelContainer
var _lbl_paso: Label
var _lbl_titulo: Label
var _lbl_texto: Label
var _fila_botones: HBoxContainer
var _fisica: PanelContainer
var _lbl_fisica_t: Label
var _lbl_fisica: Label
var _fisica_t := 0.0
var _saltar: Button
var _saltar_armado := 0.0
var _final: Control = null

## Los pasos, en orden: `titulo`, `texto`, `botones` (los ICONOS de los botones de la pantalla que se usan: el juego es
## para el movil, asi que nada de teclas ni letras, pedido 2026-10-04; "stick" y "deslizar" se dibujan aqui, el resto son
## los de touch_icons.gd) y una tarjeta de fisica al empezar el paso ("antes") o al acabarlo ("despues").
const PASOS := [
	{"id": "mover", "titulo": "MUÉVETE",
		"texto": "Anda con el joystick y desliza el dedo para mirar. Ve hasta el círculo amarillo: desde ahí harás todo el tutorial.",
		"botones": ["stick", "deslizar"]},
	{"id": "mazo", "titulo": "EL MAZO", "reto": "mazo",
		"texto": "Delante se ha levantado una pared. Dale tres mazazos con el botón de disparo: cada golpe abre un agujero.",
		"botones": ["fire"],
		"despues": ["TODO SE ROMPE", "Cada trocito del mundo se puede romper: paredes, suelos, columnas, tejados. Lo que arrancas no desaparece: cae y se queda ahí."]},
	{"id": "coger", "titulo": "TU PRIMERA ARMA", "reto": "mesa",
		"texto": "En la mesa te espera un subfusil. Acércate y toca la mano para cogerlo.",
		"botones": ["interact"]},
	{"id": "tiro", "titulo": "PRUÉBALO", "reto": "tiro",
		"texto": "Las dianas cuelgan de un puesto de tiro: rompe los DOS POSTES de madera a balazos y que caiga todo.",
		"botones": ["aim", "fire", "reload"],
		"antes": ["LAS BALAS ROMPEN", "La madera, el ladrillo y el hormigón saltan de un balazo. Apunta a la base de los postes: lo que se queda sin apoyo, cae."]},
	{"id": "columnas", "titulo": "LO QUE NO SE SOSTIENE, CAE", "reto": "columnas",
		"texto": "La losa de hormigón se apoya en dos columnas. Rómpelas las dos y mira cómo cae.",
		"botones": ["fire"],
		"despues": ["GRAVEDAD DE VERDAD", "Sin apoyo, la losa entera se suelta y cae como un bloque que pesa, golpea y se queda donde cae. Te puedes subir encima."]},
	{"id": "trepar", "titulo": "TREPA", "reto": "trepar",
		"texto": "Camina contra los bloques sin soltar el joystick: tu soldado trepa solo. Sube hasta arriba del todo.",
		"botones": ["stick", "jump"]},
	{"id": "granadas", "titulo": "EL GRAN DERRUMBE", "reto": "granadas",
		"texto": "Ya tienes granadas. La torre de hormigón se apoya en una base de ladrillo: lánzale una granada a la BASE y mira dónde cae.",
		"botones": ["grenade"],
		"antes": ["EXPLOSIONES", "Arrancan todo lo que pillan y empujan los trozos. Quita lo que aguanta algo y se viene abajo con su propio peso."],
		"despues": ["PESO, MASA Y VELOCIDAD", "Lo que cae pesa: cuanto más grande y más rápido llega, más destroza al chocar. En Breach cada derrumbe tiene consecuencias."]},
]


# ======================================================================================================
# ARRANQUE
# ======================================================================================================
func empezar(p_main: Node, p_world, p_jugador, p_hud) -> void:
	main = p_main
	world = p_world
	jugador = p_jugador
	hud = p_hud
	_tactil = Settings.is_touch()
	var txt := FileAccess.get_file_as_string("res://maps/tutorial.tutorial.json")
	var j = JSON.parse_string(txt)
	cfg = j if j is Dictionary else {}
	if cfg.is_empty():
		push_warning("[tutorial] sin tutorial.tutorial.json")
		return
	jugador.set("invulnerable", true)            # nadie te ataca, y una granada a tus pies no te quita el tutorial
	# mirando al tapiado (la salida del mapa no trae hacia donde se mira)
	var hacia: Vector3 = _v(cfg["circulo"]) - (jugador as Node3D).global_position
	(jugador as Node3D).rotation.y = atan2(-hacia.x, -hacia.z)
	# la luz de la tarde de la cafeteria (el mismo kit de materiales): con la de siempre los revoques salian azulados
	if main.has_method("cielo_tarde") and not ("--tutorialsintarde" in OS.get_cmdline_user_args()):
		main.cielo_tarde(float(cfg.get("sol_azimut", 200.0)))
	_solo_el_mazo()
	_montar_ui()
	if "--sonidosmapa" in OS.get_cmdline_user_args():
		pass
	if "--tutorialdiag" in OS.get_cmdline_user_args():
		for k in (cfg.get("mats", {}) as Dictionary).keys():
			var m := int(cfg["mats"][k])
			var inf: Dictionary = world.get_material_info(m)
			print("[sonidos] %-16s dureza %3d densidad %5d -> %s" % [k, int(inf.get("strength", 0)), int(inf.get("density", 0)), Audio.material_class(m)])
	if "--tutorialtest" in OS.get_cmdline_user_args():
		_prueba.call_deferred()
	for f in OS.get_cmdline_user_args():
		if String(f).begins_with("--tutorialfoto="):
			_fotos.call_deferred(String(f).substr(15))
	await get_tree().create_timer(0.6).timeout
	_ir_a(0)


func _v(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _caja(d: Dictionary) -> Array:
	return [_v(d["min"]), _v(d["max"])]


## SOLO EL MAZO, como al empezar el battle royale (main._on_world_ready): las dos ranuras de fuego vacias y la
## pesada con el mazo. Sin C4 ni granadas hasta su paso.
func _solo_el_mazo() -> void:
	var nueva: Array[Dictionary] = []
	nueva.append(Weapons.get_def("vacio").duplicate())
	nueva.append(Weapons.get_def("vacio").duplicate())
	nueva.append(Weapons.get_def("sledge").duplicate())
	Weapons.LIST = nueva
	jugador.set("current", 2)
	jugador.refresh_ammo_slots()
	jugador.set("grenades", 0)
	if jugador.has_method("_equip_model"):
		jugador._equip_model()
	if hud and hud.has_method("build_weapon_bar"):
		hud.build_weapon_bar()


func _medir_inicio() -> void:
	_vox_dianas.clear()
	for d in cfg.get("dianas", []):
		var c := _caja(d)
		_vox_dianas.append(maxi(1, int(world.contar_voxels(c[0], c[1]))))
	var cl := _caja(cfg["losa"])
	_vox_losa = maxi(1, int(world.contar_voxels(cl[0], cl[1])))
	var cd := _caja(cfg["deposito"])
	_vox_deposito = maxi(1, int(world.contar_voxels(cd[0], cd[1])))


# ======================================================================================================
# LOS PASOS
# ======================================================================================================
func _ir_a(n: int) -> void:
	_t_paso = 0.0
	if n >= PASOS.size():
		paso = -1
		_terminar()
		return
	var p: Dictionary = PASOS[n]
	if p.has("reto"):
		paso = -1
		_lbl_paso.text = "TUTORIAL  ·  PASO %d DE %d" % [n + 1, PASOS.size()]
		_lbl_titulo.text = "PREPARANDO EL RETO…"
		_lbl_titulo.add_theme_color_override("font_color", ACENTO)
		_lbl_texto.text = ""
		_poner_botones([])
		await _reconstruir(String(p["reto"]))
		if not is_inside_tree() or _hecho:
			return
	paso = n
	_lbl_paso.text = "TUTORIAL  ·  PASO %d DE %d" % [n + 1, PASOS.size()]
	_lbl_titulo.text = String(p["titulo"])
	_lbl_titulo.add_theme_color_override("font_color", Color.WHITE)
	_lbl_texto.text = preload("res://scripts/teclas_pc.gd").frase(String(p["texto"]))
	_poner_botones(p.get("botones", []))
	_entrar_tarjeta()
	if p.has("antes"):
		_tarjeta_fisica(p["antes"])
	Audio.ui("objetivo_nuevo", -4.0)
	match String(p["id"]):
		"coger":
			_poner_arma_en_mesa()
		"tiro":
			_dar_subfusil()          # por si acaso (si se salto la mesa)
		"granadas":
			jugador.set("grenades", 3)
			if hud and hud.has_method("build_weapon_bar"):
				hud.build_weapon_bar()
	print("[tutorial] paso %d: %s" % [n + 1, String(p["id"])])


func _process(dt: float) -> void:
	if cfg.is_empty() or _hecho or paso < 0 or not is_instance_valid(jugador):
		return
	_t_paso += dt
	_arma_tick(dt)
	_ui_tick(dt)
	_chk -= dt
	if _chk > 0.0:
		return
	_chk = 0.2
	_municion()
	var id := String(PASOS[paso]["id"])
	if hud and hud.has_method("set_objetivo_mundo"):
		var o := _objetivo(id)
		if o != Vector3.INF:
			hud.set_objetivo_mundo(o, "")
		else:
			hud.quitar_objetivo_mundo()
	if _cumplido(id):
		_paso_hecho()


## Donde apunta el marcador amarillo en cada paso (Vector3.INF = ninguno)
func _objetivo(id: String) -> Vector3:
	if id == "mover":
		return _v(cfg["circulo"]) + Vector3(0, 0.6, 0)
	if id == "coger":
		return MESA_ARMA + Vector3(0, 0.3, 0)
	var z := _zona(id)
	if z.is_empty():
		return Vector3.INF
	var c: Vector3 = (z[0] + z[1]) * 0.5
	match id:
		"tiro":
			# el poste que siga en pie
			if _corte(Vector3(X0 - 2.4, G_SUELO, 14.8), Vector3(X0 - 2.0, G_SUELO + 3.2, 15.2)) == INF:
				return Vector3(X0 - 2.2, G_SUELO + 0.8, 15.0)
			return Vector3(X0 + 2.2, G_SUELO + 0.8, 15.0)
		"columnas":
			return Vector3(X0, G_SUELO + 1.2, 12.0)
		"trepar":
			return Vector3(X0, z[0].y + 0.3, c.z)
		"granadas":
			return Vector3(X0, G_SUELO + 0.6, 12.6)          # la base de la torre
	return c


func _cumplido(id: String) -> bool:
	if _construyendo:
		return false
	_soltar_lo_cortado(id)
	var p: Vector3 = jugador.global_position
	match id:
		"mover":
			var c := _v(cfg["circulo"])
			return Vector2(p.x - c.x, p.z - c.z).length() < 1.4 or _t_paso > 25.0
		"mazo":
			# TRES AGUJEROS Y LISTO (2026-10-20, pedido: "cuesta mucho romperla toda; con tres golpes ya completaste"): cada
			# golpe que arranca algo de la pared cuenta como un agujero; con tres (o con el hueco abierto) se da por hecho
			var zm := _zona("mazo")
			var ahora_vox := int(world.contar_voxels(zm[0], zm[1]))
			if _mazo_vox < 0:
				_mazo_vox = ahora_vox
			elif ahora_vox < _mazo_vox - 3:
				_mazo_agujeros += 1
				_mazo_vox = ahora_vox
				_lbl_texto.text = "¡Agujero %d de 3! Sigue golpeando la pared." % _mazo_agujeros if _mazo_agujeros < 3 else "¡Eso es!"
				Audio.ui("aceptar", -8.0)
			return _mazo_agujeros >= 3 or _hay_paso(zm[0], zm[1])
		"coger":
			return _tiene_arma
		"tiro", "columnas":
			var zt := _zona(id)
			return world.contar_voxels(zt[0], zt[1]) < _vox_zona * 0.4
		"trepar":
			return _dentro(p, _zona("trepar"))
		"granadas":
			# granadas sin fin hasta que caiga (que nadie se quede sin poder acabar)
			if int(jugador.get("grenades")) <= 0 and _t_paso > 2.0:
				jugador.set("grenades", 2)
			var zg := _zona("granadas")
			return _soltado.has("casa") and world.contar_voxels(zg[0], zg[1]) < _vox_zona * 0.5
	return false


## El subfusil, directo a la mano (sin ir a cogerlo: el tutorial se hace sin moverse del puesto)
## El subfusil girando sobre la mesa recien construida (con su luz y el aviso de la mano: _arma_tick)
func _poner_arma_en_mesa() -> void:
	if _tiene_arma:
		return
	if _arma == null or not is_instance_valid(_arma):
		_montar_arma()
	if _arma != null and is_instance_valid(_arma):
		_arma.global_position = MESA_ARMA


func _dar_subfusil() -> void:
	if _tiene_arma:
		return
	var id := String((cfg.get("arma", {}) as Dictionary).get("id", "smg_9mm"))
	jugador.coger_arma(id, 0)
	jugador.switch_weapon(0)
	_tiene_arma = true
	Audio.bf3d("soldado/coger_arma", jugador.global_position + Vector3(0, 1.0, 0), -2.0, 15.0, Audio.PRI_MID)
	if hud and hud.has_method("flash_message"):
		hud.flash_message("¡SUBFUSIL!")


func _paso_hecho() -> void:
	var p: Dictionary = PASOS[paso]
	_lbl_titulo.text = "✓  " + String(p["titulo"])
	_lbl_titulo.add_theme_color_override("font_color", VERDE)
	Audio.ui("objetivo_tomado", -3.0)
	if p.has("despues"):
		_tarjeta_fisica(p["despues"])
	var siguiente := paso + 1
	paso = -1                     # nada de comprobar mientras se ve el ✓
	if hud and hud.has_method("quitar_objetivo_mundo"):
		hud.quitar_objetivo_mundo()
	# el derrumbe final se mira: el cartel de fin espera a que caiga todo
	await get_tree().create_timer(5.0 if String(p["id"]) == "granadas" else 1.4).timeout
	if not is_inside_tree() or _hecho:
		return
	_ir_a(siguiente)


func _diana_rota(i: int) -> bool:
	var c := _caja(cfg["dianas"][i])
	return world.contar_voxels(c[0], c[1]) < int(_vox_dianas[i]) * 0.35


func _dentro(p: Vector3, c: Array) -> bool:
	var a: Vector3 = c[0]
	var b: Vector3 = c[1]
	return p.x >= a.x and p.x <= b.x and p.z >= a.z and p.z <= b.z and p.y >= a.y and p.y <= b.y


## ¿Cabe una persona por el muro? Como campana2._hay_paso: ventanas de 0,8 x 1,3 a lo largo del muro y de lado a lado
## de su grosor; tres voxels sueltos en el borde no tapan nada.
func _hay_paso(mn: Vector3, mx: Vector3) -> bool:
	var a_lo_largo_x: bool = (mx.x - mn.x) > (mx.z - mn.z)
	var largo: float = (mx.x - mn.x) if a_lo_largo_x else (mx.z - mn.z)
	var y0: float = mn.y + 0.3
	var u := 0.45
	while u <= largo - 0.45:
		var b0: Vector3
		var b1: Vector3
		if a_lo_largo_x:
			b0 = Vector3(mn.x + u - 0.4, y0, mn.z)
			b1 = Vector3(mn.x + u + 0.4, y0 + 1.3, mx.z)
		else:
			b0 = Vector3(mn.x, y0, mn.z + u - 0.4)
			b1 = Vector3(mx.x, y0 + 1.3, mn.z + u + 0.4)
		if world.contar_voxels(b0, b1) <= 3:
			return true
		u += 0.3
	return false


## Municion de sobra en el subfusil: aqui se aprende, no se administra
func _municion() -> void:
	if not _tiene_arma:
		return
	# MUNICION INFINITA (2026-10-12, pedido): el cargador y la reserva, siempre llenos
	var reserva: Array = jugador.get("reserve")
	var carg: Array = jugador.get("ammo")
	for i in Weapons.LIST.size():
		var w: Dictionary = Weapons.LIST[i]
		if int(w.get("mag", 0)) <= 0:
			continue
		if i < reserva.size():
			reserva[i] = int(w.get("reserve", 90))
		if i < carg.size():
			carg[i] = int(w.get("mag", 0))


# ======================================================================================================
# EL SUBFUSIL DE LA MESA
# ======================================================================================================
func _montar_arma() -> void:
	var d: Dictionary = cfg.get("arma", {})
	if d.is_empty():
		return
	_arma = Node3D.new()
	_arma.name = "ArmaTutorial"
	add_child(_arma)
	_arma.global_position = _v(d["pos"])
	var ruta := "res://armas/%s.glb" % String(d.get("id", "smg_9mm"))
	if ResourceLoader.exists(ruta):
		var ps = load(ruta)
		if ps is PackedScene:
			var inst: Node = ps.instantiate()
			_arma.add_child(inst)
			if inst is Node3D:
				(inst as Node3D).rotation_degrees = Vector3(0, 90, 0)
	var luz := OmniLight3D.new()
	luz.light_color = ACENTO
	luz.light_energy = 0.8
	luz.omni_range = 1.6
	luz.position = Vector3(0, 0.3, 0)
	_arma.add_child(luz)


func _arma_tick(dt: float) -> void:
	if _arma == null or not is_instance_valid(_arma):
		_aviso_usar(false)
		return
	_arma.rotation.y += dt * 1.2
	var cam := get_viewport().get_camera_3d()
	var cerca: bool = jugador.global_position.distance_to(_arma.global_position) < 2.4
	if cerca and cam and not cam.is_position_behind(_arma.global_position):
		_aviso_usar(true, cam.unproject_position(_arma.global_position + Vector3(0, 0.25, 0)))
		if Input.is_action_just_pressed("interact"):
			usar_desde_jugador()
	else:
		_aviso_usar(false)


func _aviso_usar(on: bool, donde := Vector2.ZERO) -> void:
	if not on:
		if _aviso and is_instance_valid(_aviso):
			_aviso.quitar()
		return
	if _aviso == null or not is_instance_valid(_aviso):
		_aviso = AvisoUsar.new()
		_aviso.pressed.connect(usar_desde_jugador)
		hud.add_child(_aviso)
	_aviso.poner("arma_tutorial", "COGER EL SUBFUSIL", false, "interact")     # la mano, tambien en el PC (sin la E)
	_aviso.colocar(donde)


## Lo llama el boton del aviso (dedo) y la tecla E (aqui mismo, por _arma_tick)
func usar_desde_jugador() -> void:
	if _arma == null or not is_instance_valid(_arma):
		return
	if jugador.global_position.distance_to(_arma.global_position) > 2.6:
		return
	var id := String(cfg["arma"].get("id", "smg_9mm"))
	jugador.coger_arma(id, 0)
	jugador.switch_weapon(0)
	_tiene_arma = true
	Audio.bf3d("soldado/coger_arma", jugador.global_position + Vector3(0, 1.0, 0), -2.0, 15.0, Audio.PRI_MID)
	_arma.queue_free()
	_arma = null
	_aviso_usar(false)


# ======================================================================================================
# LA VIGA (como la del episodio 2, campana2.gd): un objeto que gira sobre el borde del altillo; las pilas son voxels
# ======================================================================================================
func _mm(c: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


func _montar_rampa() -> void:
	var rc: Dictionary = cfg.get("viga", {})
	if rc.is_empty():
		return
	var largo := float(rc.get("largo", 6.0))
	var ancho := float(rc.get("ancho", 2.0))
	_rampa = Node3D.new()
	_rampa.name = "Viga"
	add_child(_rampa)
	_rampa.global_position = _v(rc["bisagra"])
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(largo, 0.22, ancho)
	cs.shape = bs
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	mi.mesh = bm
	mi.material_override = _mm(Color(0.34, 0.36, 0.38), 0.7, 0.55)
	sb.add_child(mi)
	for lado in [-1, 1]:
		for i in 8:
			var f := MeshInstance3D.new()
			var fm := BoxMesh.new()
			fm.size = Vector3(largo / 8.0 - 0.02, 0.24, 0.16)
			f.mesh = fm
			f.material_override = _mm(Color(0.85, 0.65, 0.05) if i % 2 == 0 else Color(0.05, 0.05, 0.05), 0.3, 0.5)
			f.position = Vector3(-largo / 2 + largo / 8.0 * (i + 0.5), 0.0, lado * (ancho / 2 - 0.08))
			sb.add_child(f)
	for k in 3:
		var n := MeshInstance3D.new()
		var nm := BoxMesh.new()
		nm.size = Vector3(0.14, 0.26, ancho - 0.2)
		n.mesh = nm
		n.material_override = _mm(Color(0.2, 0.2, 0.22), 0.8, 0.5)
		n.position = Vector3(-largo * (k + 0.5) / 3.0, -0.18, 0)
		sb.add_child(n)
	_rampa.add_child(sb)
	sb.position = Vector3(-largo / 2, -0.11, 0)


## Las dos pilas ya no llegan arriba: en su metro de arriba casi no queda nada
func _pilas_rotas() -> bool:
	for pila in cfg["viga"].get("pilas", []):
		var mn: Vector3 = _v(pila[0])
		var mx: Vector3 = _v(pila[1])
		var arriba := Vector3(mn.x, mx.y - 1.0, mn.z)
		if world.contar_voxels(arriba, mx) > 6:
			return false
	return true


func _tirar_rampa() -> void:
	if _rampa_caida or not is_instance_valid(_rampa):
		return
	_rampa_caida = true
	var rc: Dictionary = cfg["viga"]
	var largo := float(rc.get("largo", 6.0))
	var alto: float = _rampa.global_position.y - float(rc.get("suelo", 1.0))
	var ang := asin(clampf(alto / largo, 0.0, 1.0))
	var tw := create_tween()
	tw.tween_property(_rampa, "rotation:z", ang, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_rampa, "rotation:z", ang - 0.06, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_rampa, "rotation:z", ang, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	var abajo := _rampa.global_position + Vector3(-largo * cos(ang), -alto, 0)
	tw.tween_callback(func():
		_aplastar_pilas()
		Audio.bf3d("destru/metal", abajo, 4.0, 60.0, Audio.PRI_HIGH)
		Audio.bf3d("destru/metal", _rampa.global_position, 0.0, 40.0, Audio.PRI_MID))


## Al caer, la viga aplasta lo que quede de las pilas (si no, su pie se apoyaba en los muñones)
func _aplastar_pilas() -> void:
	for pila in cfg["viga"].get("pilas", []):
		var mn: Vector3 = _v(pila[0])
		var mx: Vector3 = _v(pila[1])
		var cz := (mn.z + mx.z) * 0.5
		var y := mn.y + 0.35
		while y < mx.y + 0.4:
			world.carve_beam(Vector3(mn.x - 0.3, y, cz), Vector3.RIGHT, (mx.x - mn.x) + 0.6, 0.55, 255, true)
			y += 0.5


# ======================================================================================================
# EL FINAL
# ======================================================================================================
func _terminar() -> void:
	if _hecho:
		return
	_hecho = true
	# EL REGALO: las armas con las que se empieza, en la pantalla de recompensa del vestibulo al volver (la primera vez)
	if not Settings.regalo_tutorial_dado and not ("--tutorialtest" in OS.get_cmdline_user_args()):
		Settings.regalo_tutorial_dado = true
		Settings.regalo_tutorial_pendiente = true
	_marcar_hecho()
	Settings.save()
	if hud and hud.has_method("quitar_objetivo_mundo"):
		hud.quitar_objetivo_mundo()
	Audio.ui("subir_rango", -2.0)
	_tarjeta.visible = false
	_saltar.visible = false
	_fisica.visible = false
	_montar_final()


func _marcar_hecho() -> void:
	Settings.tutorial_activo = false
	if not Settings.tutorial_hecho and not ("--tutorialtest" in OS.get_cmdline_user_args()):
		Settings.tutorial_hecho = true
		Settings.save()


func _al_vestibulo() -> void:
	_marcar_hecho()
	if main and main.has_method("go_to_lobby"):
		main.go_to_lobby()


func _exit_tree() -> void:
	# salir por el menu cuenta como hecho: el tutorial no vuelve a salir solo
	_marcar_hecho()


# ======================================================================================================
# LA INTERFAZ: la tarjeta del paso (arriba), la de FISICA (a la izquierda), SALTAR y el final
# ======================================================================================================
func _letra(peso: int) -> Font:
	return FuentesScript.de(peso, false)


func _caja_estilo(borde: Color, ancho_izq: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = FONDO
	sb.border_color = borde
	sb.border_width_left = ancho_izq
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 18 + ancho_izq
	sb.content_margin_right = 20
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	return sb


func _etiqueta(tam: int, peso: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _letra(peso))
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _montar_ui() -> void:
	_capa = CanvasLayer.new()
	_capa.layer = 12                 # encima del HUD (10), debajo de los menus
	add_child(_capa)
	var raiz := Control.new()
	raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_capa.add_child(raiz)
	# --- la tarjeta del paso, arriba en el centro ---
	_tarjeta = PanelContainer.new()
	_tarjeta.add_theme_stylebox_override("panel", _caja_estilo(ACENTO, 6))
	_tarjeta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz.add_child(_tarjeta)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tarjeta.add_child(vb)
	_lbl_paso = _etiqueta(13, 700, ACENTO)
	vb.add_child(_lbl_paso)
	_lbl_titulo = _etiqueta(28, 800, Color.WHITE)
	vb.add_child(_lbl_titulo)
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 12)
	fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(fila)
	_fila_botones = HBoxContainer.new()
	_fila_botones.add_theme_constant_override("separation", 6)
	_fila_botones.alignment = BoxContainer.ALIGNMENT_CENTER
	_fila_botones.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fila.add_child(_fila_botones)
	_lbl_texto = _etiqueta(17, 500, Color(0.86, 0.88, 0.9))
	_lbl_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_texto.custom_minimum_size = Vector2(480, 0)
	_lbl_texto.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fila.add_child(_lbl_texto)
	# --- la tarjeta de FISICA, a la izquierda ---
	_fisica = PanelContainer.new()
	_fisica.add_theme_stylebox_override("panel", _caja_estilo(CIAN, 4))
	_fisica.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fisica.modulate.a = 0.0
	raiz.add_child(_fisica)
	var vf := VBoxContainer.new()
	vf.add_theme_constant_override("separation", 4)
	vf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fisica.add_child(vf)
	var cab := _etiqueta(12, 700, CIAN)
	cab.text = "CÓMO FUNCIONA BREACH"
	vf.add_child(cab)
	_lbl_fisica_t = _etiqueta(21, 800, Color.WHITE)
	vf.add_child(_lbl_fisica_t)
	_lbl_fisica = _etiqueta(15, 500, Color(0.84, 0.88, 0.92))
	_lbl_fisica.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_fisica.custom_minimum_size = Vector2(340, 0)
	vf.add_child(_lbl_fisica)
	# --- SALTAR TUTORIAL, arriba a la izquierda (dos toques) ---
	_saltar = Button.new()
	_saltar.text = "SALTAR TUTORIAL"
	_saltar.focus_mode = Control.FOCUS_NONE
	_saltar.add_theme_font_override("font", _letra(700))
	_saltar.add_theme_font_size_override("font_size", 14)
	var sbs := _caja_estilo(Color(1, 1, 1, 0.25), 0)
	sbs.content_margin_left = 14
	sbs.content_margin_right = 14
	sbs.content_margin_top = 8
	sbs.content_margin_bottom = 8
	sbs.shadow_size = 0
	for st in ["normal", "hover", "pressed"]:
		_saltar.add_theme_stylebox_override(st, sbs)
	_saltar.add_theme_color_override("font_color", Color(0.85, 0.87, 0.9))
	_saltar.pressed.connect(_pulsar_saltar)
	raiz.add_child(_saltar)
	_colocar()
	get_viewport().size_changed.connect(_colocar)


func _colocar() -> void:
	if not is_instance_valid(_tarjeta):
		return
	var tam: Vector2 = get_viewport().get_visible_rect().size
	var esc: float = clampf(tam.y / 720.0, 0.75, 1.6)
	for c in [_tarjeta, _fisica, _saltar]:
		(c as Control).scale = Vector2(esc, esc)
	_tarjeta.reset_size()
	_tarjeta.position = Vector2((tam.x - _tarjeta.size.x * esc) * 0.5, 18.0 * esc)
	_fisica.reset_size()
	# abajo a la izquierda, encima de la vida (mas arriba la tapaba la flecha del objetivo cuando queda a un lado)
	_fisica.position = Vector2(20.0 * esc, tam.y - (_fisica.size.y + 70.0) * esc)
	_saltar.reset_size()
	_saltar.position = Vector2(20.0 * esc, 18.0 * esc)


## Los iconos de los botones del paso (como los de la pantalla: circulo oscuro con su dibujo)
func _poner_botones(lista: Array) -> void:
	for c in _fila_botones.get_children():
		c.queue_free()
	_fila_botones.visible = not lista.is_empty()
	for b in lista:
		var ch := BotonIcono.new()
		ch.icono = String(b)
		# EN EL PC, LAS TECLAS (2026-10-20, pedido: "el tutorial sin los iconos de movil")
		if preload("res://scripts/teclas_pc.gd").es_pc():
			ch.tecla = preload("res://scripts/teclas_pc.gd").texto(String(b))
			ch.custom_minimum_size = Vector2(preload("res://scripts/teclas_pc.gd").ancho(ch.tecla, 40.0) + 6.0, BotonIcono.LADO)
		_fila_botones.add_child(ch)


class BotonIcono extends Control:
	var icono := ""
	var tecla := ""             ## en el PC: el texto de la tecla (entonces se dibuja la tecla, no el icono)
	const LADO := 46.0

	func _init() -> void:
		custom_minimum_size = Vector2(LADO, LADO)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if tecla != "":
			preload("res://scripts/teclas_pc.gd").dibujar(self, size * 0.5, tecla, 40.0)
			return
		var c := Vector2(LADO, LADO) * 0.5
		var r := LADO * 0.5 - 2.0
		draw_circle(c, r, Color(0.0, 0.0, 0.0, 0.5))
		draw_arc(c, r, 0.0, TAU, 40, Color(1, 1, 1, 0.75), 2.0, true)
		match icono:
			"stick":
				# el joystick: el aro de fuera y la bola, corrida arriba (andando hacia delante)
				draw_arc(c, r * 0.62, 0.0, TAU, 32, Color(1, 1, 1, 0.55), 2.0, true)
				draw_circle(c + Vector2(0, -r * 0.22), r * 0.34, Color(1, 1, 1, 0.92))
			"deslizar":
				# deslizar para mirar: el dedo (el punto) y una flecha a cada lado
				draw_circle(c, r * 0.18, Color(1, 1, 1, 0.92))
				for sg in [-1.0, 1.0]:
					var p := c + Vector2(sg * r * 0.62, 0)
					draw_line(c + Vector2(sg * r * 0.3, 0), p, Color(1, 1, 1, 0.92), 2.5, true)
					draw_colored_polygon(PackedVector2Array([p + Vector2(sg * 5.0, 0), p + Vector2(-sg * 2.0, -5.0),
						p + Vector2(-sg * 2.0, 5.0)]), Color(1, 1, 1, 0.92))
			_:
				var tex: Texture2D = preload("res://scripts/touch_icons.gd").get_icon(icono)
				if tex:
					var t := LADO * 0.62
					draw_texture_rect(tex, Rect2(c - Vector2(t, t) * 0.5, Vector2(t, t)), false)


func _entrar_tarjeta() -> void:
	_tarjeta.reset_size()
	_colocar()
	var y0 := _tarjeta.position.y
	_tarjeta.position.y = y0 - 30.0
	_tarjeta.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_tarjeta, "position:y", y0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_tarjeta, "modulate:a", 1.0, 0.25)


func _tarjeta_fisica(d: Array) -> void:
	_lbl_fisica_t.text = String(d[0])
	_lbl_fisica.text = String(d[1])
	_fisica.reset_size()
	_colocar()
	_fisica_t = 9.0
	var x0 := _fisica.position.x
	_fisica.position.x = x0 - 40.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_fisica, "position:x", x0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_fisica, "modulate:a", 1.0, 0.3)
	Audio.ui("aviso", -8.0)


func _ui_tick(dt: float) -> void:
	if _fisica_t > 0.0:
		_fisica_t -= dt
		if _fisica_t <= 0.0:
			create_tween().tween_property(_fisica, "modulate:a", 0.0, 0.5)
	if _saltar_armado > 0.0:
		_saltar_armado -= dt
		if _saltar_armado <= 0.0:
			_saltar.text = "SALTAR TUTORIAL"


func _pulsar_saltar() -> void:
	if _saltar_armado > 0.0:
		_terminar_saltado()
		return
	_saltar_armado = 3.0
	_saltar.text = "¿SEGURO? TOCA OTRA VEZ"
	_saltar.reset_size()


func _terminar_saltado() -> void:
	_hecho = true
	_al_vestibulo()


func _montar_final() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_final = Control.new()
	_final.set_anchors_preset(Control.PRESET_FULL_RECT)
	_capa.add_child(_final)
	var velo := ColorRect.new()
	velo.color = Color(0.02, 0.025, 0.035, 0.0)
	velo.set_anchors_preset(Control.PRESET_FULL_RECT)
	velo.mouse_filter = Control.MOUSE_FILTER_STOP
	_final.add_child(velo)
	var centro := VBoxContainer.new()
	centro.alignment = BoxContainer.ALIGNMENT_CENTER
	centro.add_theme_constant_override("separation", 14)
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	_final.add_child(centro)
	var eti := _etiqueta(16, 700, ACENTO)
	eti.text = "TUTORIAL COMPLETADO"
	eti.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centro.add_child(eti)
	var tit := _etiqueta(54, 900, Color.WHITE)
	tit.text = "¡YA SABES ROMPERLO TODO!"
	tit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tit.add_theme_constant_override("outline_size", 8)
	centro.add_child(tit)
	var sub := _etiqueta(18, 500, Color(0.85, 0.88, 0.92))
	sub.text = "Mazo, balas, gravedad, rampas, trepar y granadas. El resto lo aprendes rompiendo." + \
		("\nEn el vestíbulo te espera tu regalo: tus primeras armas." if Settings.regalo_tutorial_pendiente else "")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centro.add_child(sub)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	centro.add_child(hb)
	var b := Button.new()
	b.text = "  IR AL VESTÍBULO  "
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", _letra(800))
	b.add_theme_font_size_override("font_size", 24)
	var sb := StyleBoxFlat.new()
	sb.bg_color = ACENTO
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	var sbh := sb.duplicate()
	sbh.bg_color = ACENTO.lightened(0.15)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sbh)
	b.add_theme_stylebox_override("pressed", sbh)
	b.add_theme_stylebox_override("focus", sbh)
	b.add_theme_color_override("font_color", Color(0.08, 0.07, 0.04))
	b.add_theme_color_override("font_hover_color", Color(0.08, 0.07, 0.04))
	b.add_theme_color_override("font_pressed_color", Color(0.08, 0.07, 0.04))
	b.pressed.connect(_al_vestibulo)
	hb.add_child(b)
	b.grab_focus.call_deferred()
	centro.modulate.a = 0.0
	centro.scale = Vector2(0.92, 0.92)
	centro.pivot_offset = get_viewport().get_visible_rect().size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(velo, "color:a", 0.72, 0.6)
	tw.tween_property(centro, "modulate:a", 1.0, 0.5).set_delay(0.2)
	tw.tween_property(centro, "scale", Vector2.ONE, 0.5).set_delay(0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ======================================================================================================
# LOS RETOS, CONSTRUIDOS DELANTE DEL PUESTO (2026-10-20, pedido: "la parte 1 que rompa la pared; cuando la completes el
# escenario se reconstruye a la 2, sin que la persona se tenga que mover; en la de disparo tiene que romper el palo que
# sostiene los carteles"). Cada reto es una lista de cajas [min, max, material] en metros, y al pasar de uno a otro lo
# roto se va en polvo (los bloques sueltos se quitan y lo que queda en pie se vaporiza) y el siguiente CRECE de abajo
# arriba, capa a capa, con chispas doradas. El jugador vuelve al PUESTO en el polvo.
# ======================================================================================================
const G_SUELO := 1.0
const X0 := 6.3                       ## el centro de la zona de los retos (la linea del puesto)

## la mesa con el subfusil: a dos pasos del puesto (se anda hasta ella)
const MESA_ARMA := Vector3(6.3, 2.1, 7.6)

func _reto(id: String) -> Array:
	var x := X0
	var g := G_SUELO
	match id:
		"mesa":
			var m := [[Vector3(x - 0.8, g + 0.8, 7.2), Vector3(x + 0.8, g + 1.0, 8.0), "tablas"]]
			for p in [[x - 0.8, 7.2], [x + 0.6, 7.2], [x - 0.8, 7.8], [x + 0.6, 7.8]]:
				m.append([Vector3(p[0], g, p[1]), Vector3(p[0] + 0.2, g + 0.8, p[1] + 0.2), "madera_viga"])
			return m
		"mazo":
			return [[Vector3(x - 1.8, g, 7.0), Vector3(x + 1.8, g + 2.8, 7.4), "ladrillo"]]
		"tiro":
			# EL PUESTO DE TIRO (2026-10-20, pedido: "parece una cruz, mejoralo"): dos postes con una viga arriba y tres
			# DIANAS REDONDAS colgando de cadenas (anillo de madera, blanco de tablas y el centro amarillo)
			var out := [
				[Vector3(x - 2.4, g, 14.8), Vector3(x - 2.0, g + 3.2, 15.2), "madera_viga"],
				[Vector3(x + 2.0, g, 14.8), Vector3(x + 2.4, g + 3.2, 15.2), "madera_viga"],
				[Vector3(x - 2.6, g + 3.2, 14.8), Vector3(x + 2.6, g + 3.6, 15.2), "madera_viga"],
			]
			for cx in [x - 1.4, x, x + 1.4]:
				out.append([Vector3(cx - 0.1, g + 2.8, 14.9), Vector3(cx + 0.1, g + 3.2, 15.1), "acero"])
				out.append_array(_diana_redonda(cx, g + 2.2, 14.9))
			return out
		"columnas":
			return [
				[Vector3(x - 1.6, g + 2.6, 10.8), Vector3(x + 1.6, g + 3.0, 13.2), "hormigon"],
				[Vector3(x - 1.3, g, 11.7), Vector3(x - 0.7, g + 2.6, 12.3), "hormigon"],
				[Vector3(x + 0.7, g, 11.7), Vector3(x + 1.3, g + 2.6, 12.3), "hormigon"],
			]
		"trepar":
			return [
				[Vector3(x - 1.8, g, 7.4), Vector3(x + 1.8, g + 1.4, 8.6), "tablas"],
				[Vector3(x - 1.8, g + 1.2, 7.4), Vector3(x + 1.8, g + 1.4, 8.6), "madera_viga"],
				[Vector3(x - 1.8, g, 8.6), Vector3(x + 1.8, g + 2.4, 9.8), "ladrillo"],
				[Vector3(x - 1.8, g + 2.2, 8.6), Vector3(x + 1.8, g + 2.4, 9.8), "hormigon"],
			]
		"granadas":
			# LA TORRE (2026-10-20, pedido: "una casa de madera y algo grande que hay que destruir de la base para que caiga y
			# demostrar que cada destruccion tiene consecuencias: fisicas y daño por velocidad, peso y masa"): base de
			# ladrillo, fuste de hormigon y un deposito macizo arriba, delante de la casa
			var torre := [
				# pegada a la fachada; el deposito, en voladizo ENCIMA DEL TEJADO: sin base cae casi a plomo sobre la casa
				[Vector3(x - 0.6, g, 12.0), Vector3(x + 0.6, g + 1.2, 13.2), "ladrillo"],
				[Vector3(x - 0.4, g + 1.2, 12.2), Vector3(x + 0.4, g + 6.0, 13.0), "hormigon"],
				[Vector3(x - 1.2, g + 6.0, 12.2), Vector3(x + 1.2, g + 7.4, 16.6), "hormigon"],
				[Vector3(x - 1.3, g + 6.2, 12.1), Vector3(x + 1.3, g + 6.4, 16.7), "acero"],
			]
			return torre + _casa()
	return []


## La caja que se vigila de cada reto: la que tiene que desaparecer (o donde hay que estar)
func _zona(id: String) -> Array:
	var x := X0
	var g := G_SUELO
	match id:
		"mazo":
			return [Vector3(x - 1.8, g, 7.0), Vector3(x + 1.8, g + 2.8, 7.4)]
		"tiro":
			return [Vector3(x - 2.6, g + 3.2, 14.8), Vector3(x + 2.6, g + 3.6, 15.2)]      # la viga: cae con los postes
		"columnas":
			return [Vector3(x - 1.6, g + 2.6, 10.8), Vector3(x + 1.6, g + 3.0, 13.2)]      # la losa
		"trepar":
			return [Vector3(x - 1.8, g + 2.2, 8.6), Vector3(x + 1.8, g + 4.6, 9.8)]        # encima del bloque alto
		"granadas":
			return [Vector3(CASA[0], g, CASA[1]), Vector3(CASA[2], g + 3.8, CASA[3])]          # la casa
	return []


## LA CASA DE MADERA detras de la torre: cuatro paredes de tablas con puerta y ventanas, postes en las esquinas y un
## tejado a dos aguas de vigas (escalonado), de 6 x 4 m
const CASA := [3.3, 13.6, 9.3, 17.6]          ## x0, z0, x1, z1

func _casa() -> Array:
	var g := G_SUELO
	var x0: float = CASA[0]
	var z0: float = CASA[1]
	var x1: float = CASA[2]
	var z1: float = CASA[3]
	var h := 2.6
	var out := []
	# paredes (la de delante con la puerta y dos ventanas)
	out.append([Vector3(x0, g, z0), Vector3(X0 - 0.5, g + h, z0 + 0.2), "tablas"])
	out.append([Vector3(X0 + 0.5, g, z0), Vector3(x1, g + h, z0 + 0.2), "tablas"])
	out.append([Vector3(X0 - 0.5, g + 2.0, z0), Vector3(X0 + 0.5, g + h, z0 + 0.2), "tablas"])
	out.append([Vector3(x0, g, z1 - 0.2), Vector3(x1, g + h, z1), "tablas"])
	out.append([Vector3(x0, g, z0), Vector3(x0 + 0.2, g + h, z1), "tablas"])
	out.append([Vector3(x1 - 0.2, g, z0), Vector3(x1, g + h, z1), "tablas"])
	# postes de las esquinas y la viga de arriba
	for p in [[x0, z0], [x1 - 0.2, z0], [x0, z1 - 0.2], [x1 - 0.2, z1 - 0.2]]:
		out.append([Vector3(p[0], g, p[1]), Vector3(p[0] + 0.2, g + h, p[1] + 0.2), "madera_viga"])
	# el tejado a dos aguas: capas que se estrechan hacia la cumbrera (a lo largo de X)
	var k := 0
	while k < 6:
		var zz0 := z0 - 0.2 + k * 0.4
		var zz1 := z1 + 0.2 - k * 0.4
		if zz1 - zz0 < 0.4:
			break
		out.append([Vector3(x0 - 0.2, g + h + k * 0.2, zz0), Vector3(x1 + 0.2, g + h + (k + 1) * 0.2, zz1), "madera_viga"])
		k += 1
	return out


## Una diana redonda de 1,2 m mirando al puesto (-Z), con su centro en (cx, cy): filas de voxels de 20 cm, el anillo de
## fuera de madera, el blanco de tablas y el centro amarillo
func _diana_redonda(cx: float, cy: float, z0: float) -> Array:
	var out := []
	var vs := 0.2
	var r := 0.6
	var y := cy - r
	while y < cy + r - 0.01:
		var x := cx - r
		while x < cx + r - 0.01:
			var d := Vector2(x + vs * 0.5 - cx, y + vs * 0.5 - cy).length()
			if d <= r:
				var mat := "pintura_amarilla" if d < 0.2 else ("tablas" if d < 0.42 else "madera_viga")
				out.append([Vector3(x, y, z0), Vector3(x + vs, y + vs, z0 + 0.2), mat])
			x += vs
		y += vs
	return out


var _mazo_vox := -1
var _mazo_agujeros := 0
var _reto_actual := ""
var _soltado := {}                    ## lo que ya se solto de cada reto (para no soltarlo dos veces)


## LO QUE SE QUEDA SIN APOYO, CAE. Lo construido en juego el motor lo da por anclado aunque se corte por debajo (lo que
## se pone con place_settled cuenta como mapa intacto), asi que el tutorial lo suelta el mismo: con el palo partido por
## algun sitio, todo lo de encima (travesaño y carteles) pasa a ser un bloque que cae; con las dos columnas partidas, la
## losa; con tres patas rotas, el deposito.
func _soltar_lo_cortado(id: String) -> void:
	var x := X0
	var g := G_SUELO
	match id:
		"tiro":
			if _soltado.has("tiro"):
				return
			var c1 := _corte(Vector3(x - 2.4, g, 14.8), Vector3(x - 2.0, g + 3.2, 15.2))
			var c2 := _corte(Vector3(x + 2.0, g, 14.8), Vector3(x + 2.4, g + 3.2, 15.2))
			if c1 < INF and c2 < INF:
				_soltado["tiro"] = true
				_soltar(Vector3(x - 2.8, minf(c1, c2), 14.6), Vector3(x + 2.8, g + 3.8, 15.4), Vector3(0, 0, 0.6))
		"columnas":
			if _soltado.has("columnas"):
				return
			var c1 := _corte(Vector3(x - 1.3, g, 11.7), Vector3(x - 0.7, g + 2.6, 12.3))
			var c2 := _corte(Vector3(x + 0.7, g, 11.7), Vector3(x + 1.3, g + 2.6, 12.3))
			if c1 < INF and c2 < INF:
				_soltado["columnas"] = true
				_soltar(Vector3(x - 1.4, c1, 11.6), Vector3(x - 0.6, g + 2.6, 12.4), Vector3.ZERO)
				_soltar(Vector3(x + 0.6, c2, 11.6), Vector3(x + 1.4, g + 2.6, 12.4), Vector3.ZERO)
				_soltar(Vector3(x - 1.6, g + 2.6, 10.8), Vector3(x + 1.6, g + 3.0, 13.2), Vector3.ZERO)
		"granadas":
			if _soltado.has("granadas"):
				return
			var corte := _corte(Vector3(x - 0.6, g, 12.0), Vector3(x + 0.6, g + 1.2, 13.2))
			if corte == INF:
				corte = _corte(Vector3(x - 0.4, g + 1.2, 12.2), Vector3(x + 0.4, g + 6.0, 13.0))
			if corte < INF:
				_soltado["granadas"] = true
				# TODA LA TORRE DE ENCIMA, inclinada hacia la casa (+Z): se vence y cae sobre el tejado
				# desde el SUELO (con la base entera: lo que quedara de ella hacia de bisagra y la volcaba hacia el jugador)
				# (2026-10-20, bug: "se queda flotando un segundo y despues cae"): lo grande y alto arranca con menos gravedad
				# (el motor lo deja caer a camara lenta para que se vea); aqui sale ya cayendo
				_soltar(Vector3(x - 1.4, g + 0.2, 11.8), Vector3(x + 1.4, g + 7.6, 16.8), Vector3(0, -6.0, 0.6), Vector3.ZERO)
				_casa_se_viene_abajo()

## LA CASA, AL LLEGARLE LA TORRE: cuando el deposito toca el tejado (o pasados 2,5 s), el tejado y las paredes se sueltan
## como bloques y se vienen abajo, con lo que el golpe de la torre (su peso y su velocidad) ya tallo
func _casa_se_viene_abajo() -> void:
	var g := G_SUELO
	var t := 0.0
	var tejado := [Vector3(CASA[0] - 0.2, g + 2.6, CASA[1] - 0.2), Vector3(CASA[2] + 0.2, g + 4.0, CASA[3] + 0.2)]
	var antes := int(world.contar_voxels(tejado[0], tejado[1]))
	# SOLO CUANDO LE LLEGA LA TORRE (2026-10-20, bug: "la casa se derrumba sin que la torre le haya caido encima"): antes
	# se venia abajo a los 2,5 s pasara lo que pasara; ahora espera al golpe (y, por si acaso, 8 s como mucho)
	# el deposito esta 2,2 m por encima del tejado y sale cayendo a 6 m/s: llega en ~0,3 s (o antes, si ya lo talla)
	while t < 0.35 and is_inside_tree():
		await get_tree().create_timer(0.05).timeout
		t += 0.05
		if int(world.contar_voxels(tejado[0], tejado[1])) < antes - 3:
			break                  # el golpe ya le ha arrancado algo: llego
	if not is_inside_tree():
		return
	_soltado["casa"] = true
	var efectos = main.get("effects") if main else null
	if efectos and efectos.has_method("collapse_dust"):
		efectos.collapse_dust(Vector3(X0, g + 1.5, (CASA[1] + CASA[3]) * 0.5), 4.0, Color(0.7, 0.6, 0.45))
	# el tejado entero cae hacia dentro y las paredes se abren hacia fuera
	_soltar(tejado[0], tejado[1], Vector3(0, -5.0, 0.5), Vector3(0.6, 0, 0.3))
	_soltar(Vector3(CASA[0], g + 0.2, CASA[1]), Vector3(CASA[2], g + 2.6, CASA[1] + 0.2), Vector3(0, 0, -1.5), Vector3(-0.8, 0, 0))
	_soltar(Vector3(CASA[0], g + 0.2, CASA[3] - 0.2), Vector3(CASA[2], g + 2.6, CASA[3]), Vector3(0, 0, 1.5), Vector3(0.8, 0, 0))
	_soltar(Vector3(CASA[0], g + 0.2, CASA[1] + 0.2), Vector3(CASA[0] + 0.2, g + 2.6, CASA[3] - 0.2), Vector3(-1.5, 0, 0), Vector3(0, 0, 0.8))
	_soltar(Vector3(CASA[2] - 0.2, g + 0.2, CASA[1] + 0.2), Vector3(CASA[2], g + 2.6, CASA[3] - 0.2), Vector3(1.5, 0, 0), Vector3(0, 0, -0.8))
	Audio.ui("objetivo_tomado", -6.0)


## La primera capa VACIA de un poste (la altura del corte) o INF si sigue entero
func _corte(mn: Vector3, mx: Vector3) -> float:
	var vs: float = float(world.get_voxel_size())
	# lo que tiene una capa entera de la caja: si queda menos de una cuarta parte, esa capa ya no sostiene nada
	var lleno := maxi(1, roundi((mx.x - mn.x) / vs) * roundi((mx.z - mn.z) / vs))
	var y := mn.y
	while y < mx.y - 0.01:
		if int(world.contar_voxels(Vector3(mn.x + 0.02, y + 0.02, mn.z + 0.02), Vector3(mx.x - 0.02, y + vs - 0.02, mx.z - 0.02))) * 4 < lleno:
			return y + vs
		y += vs
	return INF


## Todo lo que haya en la caja pasa a ser UN bloque suelto que cae (place_detached: lee los voxels de alli y los quita)
func _soltar(mn: Vector3, mx: Vector3, vel: Vector3, ang := Vector3.INF) -> void:
	var vs: float = float(world.get_voxel_size())
	var o := Vector3i(roundi(mn.x / vs), roundi(mn.y / vs), roundi(mn.z / vs))
	var f := Vector3i(roundi(mx.x / vs), roundi(mx.y / vs), roundi(mx.z / vs))
	var tam := f - o
	if tam.x <= 0 or tam.y <= 0 or tam.z <= 0:
		return
	var n := tam.x * tam.y * tam.z
	var bits := PackedByteArray()
	bits.resize((n + 7) / 8)
	bits.fill(255)
	var giro := ang if ang != Vector3.INF else Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))
	world.place_detached(o, tam, bits, vel, giro)
	print("[tutorial] se suelta %s-%s" % [str(mn), str(mx)])
var _vox_zona := 1
var _construyendo := false


## Lo de antes, fuera (en polvo) y el reto nuevo, creciendo de abajo arriba. Devuelve cuando ya esta en pie.
func _reconstruir(siguiente: String) -> void:
	_construyendo = true
	var anterior := _reto_actual
	_reto_actual = siguiente
	_soltado.clear()
	var efectos = main.get("effects") if main else null
	var centro := Vector3(X0, G_SUELO + 1.2, 10.5)
	# 1 lo roto se va: los bloques sueltos y lo que siga en pie del reto anterior
	if anterior != "":
		Audio.ui("objetivo_tomado", -10.0)
		if efectos and efectos.has_method("dust"):
			# poco polvo: mucho tapaba el reto nuevo varios segundos
			efectos.dust(Vector3(X0, G_SUELO + 0.4, 10.5), 1.0, Color(0.9, 0.85, 0.7))
		await get_tree().create_timer(0.25).timeout
		var censo: PackedInt64Array = world.censo_bloques()
		for i in range(0, censo.size(), 2):
			world.quitar_bloque(int(censo[i]))
		for c in _reto(anterior):
			_vaporizar(c[0], c[1])
		# EL SUELO TAMBIEN (2026-10-20, pedido): los agujeros y crateres de la zona, rellenos de tierra y adoquin
		var mats_suelo: Dictionary = cfg.get("mats", {})
		_rellenar(Vector3(0.6, 0.4, 2.0), Vector3(12.0, 0.8, 20.0), int(mats_suelo.get("suelo_tierra", 0)))
		_rellenar(Vector3(0.6, 0.8, 2.0), Vector3(12.0, G_SUELO, 20.0), int(mats_suelo.get("adoquin", 0)))
		await get_tree().create_timer(0.35).timeout
	# 2 el jugador, de vuelta al puesto mirando a los retos
	if is_instance_valid(jugador):
		var p := _v(cfg.get("puesto", [X0, G_SUELO, 5.2]))
		if Vector2(jugador.global_position.x - p.x, jugador.global_position.z - p.z).length() > 0.6 or jugador.global_position.y > p.y + 0.5:
			jugador.global_position = p + Vector3(0, 0.1, 0)
			jugador.velocity = Vector3.ZERO
			world.set_player_position(jugador.global_position)
		jugador.rotation.y = PI
	# 3 el reto nuevo, capa a capa (cada capa de voxels, de abajo arriba, en ~1,6 s)
	var cajas := _reto(siguiente)
	if not cajas.is_empty():
		var vs: float = float(world.get_voxel_size())
		var ymin := INF
		var ymax := -INF
		for c in cajas:
			ymin = minf(ymin, (c[0] as Vector3).y)
			ymax = maxf(ymax, (c[1] as Vector3).y)
		var capas := maxi(1, int(round((ymax - ymin) / vs)))
		var por_capa := clampf(1.6 / capas, 0.03, 0.12)
		for k in capas:
			var y0 := ymin + k * vs
			for c in cajas:
				var a: Vector3 = c[0]
				var b: Vector3 = c[1]
				if y0 + vs * 0.5 < a.y or y0 + vs * 0.5 > b.y:
					continue
				_rellenar(Vector3(a.x, y0, a.z), Vector3(b.x, y0 + vs, b.z), int((cfg.get("mats", {}) as Dictionary).get(String(c[2]), 0)))
			if efectos and efectos.has_method("sparks") and k % 2 == 0:
				efectos.sparks(Vector3(X0 + randf_range(-1.6, 1.6), y0, 11.0 + randf_range(-3.0, 3.0)), Vector3.UP)
			if k % 4 == 0:
				Audio.ui("pasar", -14.0)
			await get_tree().create_timer(por_capa).timeout
		if efectos and efectos.has_method("dust"):
			efectos.dust(centro, 0.7, Color(1.0, 0.85, 0.4))
		Audio.ui("subir_rango", -8.0)
	var z := _zona(siguiente)
	_vox_zona = maxi(1, int(world.contar_voxels(z[0], z[1]))) if not z.is_empty() else 1
	if siguiente == "tiro" and "--tutorialdiag" in OS.get_cmdline_user_args():
		var capas_palo := []
		var yy := G_SUELO
		while yy < G_SUELO + 3.0:
			capas_palo.append(int(world.contar_voxels(Vector3(X0 - 0.18, yy + 0.02, 14.82), Vector3(X0 + 0.18, yy + 0.18, 15.18))))
			yy += 0.2
		print("[tutorial] palo por capas: %s" % str(capas_palo))
	_construyendo = false


func _rellenar(mn: Vector3, mx: Vector3, mat_id: int) -> void:
	if mat_id <= 0:
		return
	var vs: float = float(world.get_voxel_size())
	var o := Vector3i(roundi(mn.x / vs), roundi(mn.y / vs), roundi(mn.z / vs))
	var f := Vector3i(roundi(mx.x / vs), roundi(mx.y / vs), roundi(mx.z / vs))
	var tam := f - o
	if tam.x <= 0 or tam.y <= 0 or tam.z <= 0:
		return
	var mats := PackedByteArray()
	mats.resize(tam.x * tam.y * tam.z)
	mats.fill(mat_id)
	world.place_settled(o, tam, mats)


## Lo que quede en pie de una caja, fuera sin escombros (rayos que vaporizan, como el tallado del puñetazo)
func _vaporizar(mn: Vector3, mx: Vector3) -> void:
	var y := mn.y + 0.1
	while y < mx.y:
		var z := mn.z + 0.1
		while z < mx.z:
			world.carve_beam(Vector3(mn.x - 0.1, y, z), Vector3.RIGHT, (mx.x - mn.x) + 0.2, 0.12, 255, true)
			z += 0.2
		y += 0.2


# ======================================================================================================
# PRUEBAS
# ======================================================================================================
## --tutorialtest: lo recorre solo, paso a paso, haciendo lo que haria el jugador por el camino corto (moverle,
## tallar lo que hay que romper como lo romperia un arma, coger el arma) y dice si cada paso se cumple.
func _prueba() -> void:
	var fallos: Array = []
	var esperar := func(id: String, seg: float) -> bool:
		var t := 0.0
		while t < seg:
			await get_tree().create_timer(0.25).timeout
			t += 0.25
			if paso >= 0 and paso < PASOS.size() and String(PASOS[paso]["id"]) != id:
				return true
			if paso == -1 and _hecho:
				return true
		return false
	var hasta_que_toque := func(id: String) -> void:
		for _i in 60:
			if paso >= 0 and String(PASOS[paso]["id"]) == id:
				return
			await get_tree().create_timer(0.25).timeout
	var romper := func(mn: Vector3, mx: Vector3) -> void:
		var y := mn.y + 0.1
		while y <= mx.y:
			world.carve_beam(Vector3(mn.x - 0.3, y, (mn.z + mx.z) * 0.5), Vector3.RIGHT, (mx.x - mn.x) + 0.6, maxf(0.6, (mx.z - mn.z) * 0.5 + 0.2), 255, true)
			y += 0.3
	await get_tree().create_timer(2.0).timeout
	# 1 mover
	jugador.global_position = _v(cfg["circulo"]) + Vector3(0, 0.1, 0)
	world.set_player_position(jugador.global_position)
	if not await esperar.call("mover", 4.0):
		fallos.append("mover")
	# 2 mazo: la pared construida y tallada
	await hasta_que_toque.call("mazo")
	var zm := _zona("mazo")
	print("[tutorialtest] pared: %d voxels" % world.contar_voxels(zm[0], zm[1]))
	romper.call(zm[0], zm[1])
	if not await esperar.call("mazo", 5.0):
		fallos.append("mazo")
	# 3 coger: a la mesa y tocar la mano
	await hasta_que_toque.call("coger")
	jugador.global_position = MESA_ARMA + Vector3(0, -1.1, -1.4)
	world.set_player_position(jugador.global_position)
	await get_tree().create_timer(0.5).timeout
	usar_desde_jugador()
	if not await esperar.call("coger", 4.0):
		fallos.append("coger")
	# 4 tiro: los dos postes partidos abajo; la viga y las dianas tienen que caer
	await hasta_que_toque.call("tiro")
	print("[tutorialtest] arma en la mano: %s · travesaño %d voxels" % [String(Weapons.LIST[int(jugador.get("current"))].get("id", "?")),
		world.contar_voxels(_zona("tiro")[0], _zona("tiro")[1])])
	for px in [X0 - 2.2, X0 + 2.2]:
		romper.call(Vector3(px - 0.3, G_SUELO + 0.6, 14.8), Vector3(px + 0.3, G_SUELO + 1.0, 15.2))
	if not await esperar.call("tiro", 8.0):
		fallos.append("tiro (el travesaño no ha caido: %d de %d)" % [world.contar_voxels(_zona("tiro")[0], _zona("tiro")[1]), _vox_zona])
	# 4 columnas
	await hasta_que_toque.call("columnas")
	for cx in [X0 - 1.0, X0 + 1.0]:
		romper.call(Vector3(cx - 0.4, G_SUELO + 0.6, 11.6), Vector3(cx + 0.4, G_SUELO + 1.2, 12.4))
	if not await esperar.call("columnas", 8.0):
		fallos.append("columnas (la losa no ha caido)")
	# 5 trepar: andar contra los bloques
	await hasta_que_toque.call("trepar")
	jugador.rotation.y = PI
	Input.action_press("move_forward")
	var trepo: bool = await esperar.call("trepar", 14.0)
	Input.action_release("move_forward")
	if not trepo:
		fallos.append("trepar (pos %s)" % str(jugador.global_position))
	# 6 granadas: una de verdad a las patas
	await hasta_que_toque.call("granadas")
	Net.net_explode(world, Vector3(X0, G_SUELO + 0.5, 12.0), Weapons.GRENADE_RADIUS, Weapons.GRENADE_POWER)
	if not await esperar.call("granadas", 8.0):
		var zg := _zona("granadas")
		fallos.append("derrumbe (la casa sigue: %d de %d voxels, casa soltada=%s)" % [world.contar_voxels(zg[0], zg[1]), _vox_zona, str(_soltado.has("casa"))])
	await get_tree().create_timer(1.0).timeout
	print("[tutorialtest] %s" % ("TODO BIEN" if fallos.is_empty() else "FALLA: " + ", ".join(PackedStringArray(fallos))))
	get_tree().quit()


func _fotos(carpeta: String) -> void:
	DirAccess.make_dir_recursive_absolute(carpeta)
	var foto := func(n: String) -> void:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(carpeta.path_join("tutorial_%s.png" % n))
	await get_tree().create_timer(2.0).timeout
	jugador.global_position = _v(cfg["circulo"]) + Vector3(0, 0.1, 0)
	world.set_player_position(jugador.global_position)
	for id in ["mazo", "mesa", "tiro", "columnas", "trepar", "granadas"]:
		for _i in 80:
			if _construyendo:
				break
			await get_tree().create_timer(0.1).timeout
		await get_tree().create_timer(0.7).timeout
		await foto.call(id + "_creciendo")
		while _construyendo:
			await get_tree().create_timer(0.1).timeout
		await get_tree().create_timer(1.0).timeout
		await foto.call(id)
		var z := _zona(id)
		if id == "mesa":
			jugador.global_position = MESA_ARMA + Vector3(0, -1.1, -1.4)
			world.set_player_position(jugador.global_position)
			await get_tree().create_timer(0.6).timeout
			await foto.call("mesa_cerca")
			usar_desde_jugador()
			continue
		if id == "trepar":
			jugador.global_position = Vector3(X0, z[0].y + 0.2, (z[0].z + z[1].z) * 0.5)
			world.set_player_position(jugador.global_position)
		elif id == "tiro":
			world.carve_beam(Vector3(X0 - 2.8, G_SUELO + 0.8, 15.0), Vector3.RIGHT, 1.2, 0.5, 255, true)
			world.carve_beam(Vector3(X0 + 1.6, G_SUELO + 0.8, 15.0), Vector3.RIGHT, 1.2, 0.5, 255, true)
		elif id == "mazo":
			world.carve_beam(Vector3(X0 - 1.0, G_SUELO + 1.0, 7.2), Vector3.RIGHT, 2.0, 0.9, 255, true)
		elif id == "granadas":
			Net.net_explode(world, Vector3(X0, G_SUELO + 0.5, 12.0), Weapons.GRENADE_RADIUS, Weapons.GRENADE_POWER)
			for k in 8:
				await get_tree().create_timer(0.35).timeout
				await foto.call("derrumbe_%d" % k)
		else:
			Net.net_explode(world, (z[0] + z[1]) * 0.5 - Vector3(0, 1.0, 0), 2.5, 400)
		if id == "tiro":
			await get_tree().create_timer(1.2).timeout
			await foto.call("tiro_cae")
	await get_tree().create_timer(4.0).timeout
	await foto.call("final")
	get_tree().quit()
