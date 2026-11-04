extends "res://scripts/campana_kit.gd"
## EPISODIO 5 DE LA CAMPAÑA: "LA BASE AEREA" (campana_base, tools/generar_mapa_campana5.py). 2026-09-28.
##
## El ultimo tren del episodio 4 sale del tunel de noche, con TORMENTA, y el ejercito ha volado la via: descarrila
## junto a una refineria (escena de entrada: el tren, la voladura, el vuelco). Al otro lado esta la base aerea, donde
## un avion de carga os saca si le encendeis la pista. DOCE PUZZLES, todos nuevos, y casi todos a base de EXPLOSIONES:
##    1 EL MORTERO           girar y elegir la carga; se ve donde cae y se corrige (blanco: la casa de bombas)
##    2 LA ESFERA DE GAS     abrir la valvula, esperar a que la nube llegue a la fuga y dispararle DESDE LEJOS
##    3 EL PUENTE COLGANTE   la verja tarda 40 s y la horda cruza el puente: se vuela disparando a sus anclajes
##    4 EL COLECTOR          44 m buceando por un tubo inundado; se respira en los pozos de registro
##    5 LA DEMOLICION        cuatro empalmes y el detonador: el edificio se viene abajo (de verdad) y revienta el muro
##    6 LA BALIZA            la luz roja del mastil parpadea las tres cifras de la verja; se teclean
##    7 EL CAMPO DE MINAS    se revientan a tiros (y en cadena), o se les lleva la horda encima
##    8 EL TANQUE            el cañon de un tanque abandonado contra la puerta blindada del hangar
##    9 EL RADAR             girar la antena hasta que la señal pite seguida
##   10 LAS LUCES DE PISTA   tres cuadros; hay que aguantar junto a cada uno
##   11 EL ATERRIZAJE        (escena) baja el avion... y un helicoptero en llamas se estrella en la pista
##   12 EL CAMION CISTERNA   volarlo a tiros para echar el helicoptero de la pista. Todos al avion: despegue.
##
## Escenas de camara: la entrada (el descarrilamiento, con la cinematica de siempre), la demolicion, la pista que se
## enciende, el aterrizaje con el helicoptero y el despegue. Las dianas (objetos a los que se dispara) son
## diana_campana.gd: la bala llega por danar_bala y la explosion por take_damage.

const COLOR_AVISO := Color(1.0, 0.75, 0.1)
const COLOR_INFO := Color(0.35, 0.8, 1.0)
const COLOR_PELIGRO := Color(1.0, 0.3, 0.1)
const ROTULOS := {"mortero": "p01", "tabla": "p01", "blanco": "p01", "valvula": "p02", "fuga": "p02", "anclajes": "p03",
	"mando_verja": "p03", "colector": "p04", "detonador": "p05", "empalme0": "p05", "empalme1": "p05", "empalme2": "p05",
	"empalme3": "p05", "teclado": "p06", "minas": "p07", "tanque": "p08", "radar": "p09", "cuadro0": "p10",
	"cuadro1": "p10", "cuadro2": "p10", "camion": "p12"}

var _comprobar_t5 := 0.0
# --- el tren de la entrada ---
var _tren5: Node3D = null
var _loco5: Node3D = null
var _plataforma5: Node3D = null
var _tren_t := -1.0
# --- 1 el mortero ---
var _mortero_yaw: Node3D = null
var _mortero_ang := 45.0
var _mortero_carga := 1
var _mortero_label: Label3D = null
var _mortero_cd := 0.0
# --- 2 la esfera ---
var _nube: CPUParticles3D = null
var _nube_t := -1.0
var _gas_ruido: AudioStreamPlayer3D = null
var _fuga_luz: OmniLight3D = null
# --- 3 el puente y la verja ---
var _verja: StaticBody3D = null
var _verja_barrera := AABB()
var _verja_t := -1.0
var _anclajes_rotos: Array = [false, false]
var _puente_caido := false
var _tanda_puente_t := 0.0
# --- 5 la demolicion ---
var _empalmes: Array = [false, false, false, false]
var _detonador_luces: Array = []
# --- 6 la baliza ---
var _baliza_luz: OmniLight3D = null
var _baliza_bola: MeshInstance3D = null
var _baliza_t := 0.0
var _tecleado := ""
var _pantalla: Label3D = null
var _verja_int: StaticBody3D = null
var _verja_int_barrera := AABB()
# --- 7 las minas ---
var _minas: Array = []                ## [{pos, nodo, viva}]
var _minas_t := 0.0
var _led_t := 0.0
# --- 8 el tanque ---
var _torreta: Node3D = null
var _tanque_ang := 180.0
var _tanque_cd := 0.0
var _laser: MeshInstance3D = null
var _laser_punto: MeshInstance3D = null
var _blindada: StaticBody3D = null
var _blindada_golpes := 0
var _blindada_barrera := AABB()
# --- 9 el radar ---
var _antena: Node3D = null
var _radar_ang := 0.0
var _radar_label: Label3D = null
var _pitido_t := 0.0
# --- 10 la pista ---
var _cuadros_k: Array = [0.0, 0.0, 0.0]
var _cuadros_hechos: Array = [false, false, false]
var _luces_pista: Array = [[], [], []]
var _pista_red_t := 0.0
var _cuadros_label: Array = []
# --- 11 / 12 el avion, el helicoptero y el camion ---
var _avion: Node3D = null
var _helices: Array = []
var _rampa: Node3D = null
var _avion_cuerpos: StaticBody3D = null
var _heli_caido: Node3D = null
var _camion_vida := 900.0
var _avion_ruido: AudioStreamPlayer3D = null
var _tanda_final5 := 0.0
var _final_tank5 := false
# --- 4 el aire (el colector) ---
var _aire := 14.0
var _aire_capa: CanvasLayer = null
var _aire_barra: ColorRect = null
var _aire_dano_t := 0.0
# --- las escenas de camara ---
# --- ambiente ---
var _focos: Array = []
var _llama: OmniLight3D = null


# ======================================================================================================
# LA ESCENA
# ======================================================================================================
func _montar_escena() -> void:
	super._montar_escena()
	rotulo_fase = ROTULOS
	_arreglar_puertas_refugio()
	_muros_invisibles()
	if _soy_host:
		_sortear()
	_montar_tren()
	_montar_ambiente()
	_montar_p01()
	_montar_p02()
	_montar_p03()
	_montar_p05()
	_montar_p06()
	_montar_p07()
	_montar_p08()
	_montar_p09()
	_montar_p10()
	_montar_avion()
	_montar_p12()
	_aplicar_par5()


func _fase_de_rotulos() -> String:
	var f := fase
	if f == "inicio":
		return "p01"
	if f == "p11":
		return "p12"
	return f


func _sortear() -> void:
	var cif := [randi_range(1, 9), randi_range(1, 9), randi_range(1, 9)]
	var minas: Array = []
	var c: Array = _c("p07_minas").get("campo", [104, 115, 135, 141])
	var n := int(_c("p07_minas").get("n", 46))
	var intentos := 0
	while minas.size() < n and intentos < 4000:
		intentos += 1
		var x := randf_range(float(c[0]) + 0.8, float(c[2]) - 1.0)
		var z := randf_range(float(c[1]) + 0.8, float(c[3]) - 0.8)
		var ok := true
		for m in minas:
			if Vector2(float(m[0]) - x, float(m[1]) - z).length() < 2.6:
				ok = false
				break
		# la entrada de la verja, despejada un par de metros
		if x > float(c[2]) - 2.5 and z > 124.0 and z < 132.0:
			ok = false
		if ok:
			minas.append([snappedf(x, 0.01), snappedf(z, 0.01)])
	par = {"cifras": cif, "minas": minas, "radar": float(randi_range(0, 35) * 10)}
	print("[campana5] sorteo: cifras %s · %d minas · radar %d" % [str(cif), minas.size(), int(par["radar"])])


func _aplicar_par5() -> void:
	if par.is_empty():
		return
	_montar_minas()


func _estado_dict() -> Dictionary:
	var minas_vivas: Array = []
	for m in _minas:
		minas_vivas.append(bool(m["viva"]))
	return {"hecho": hecho, "par": par, "fase": fase, "empalmes": _empalmes, "anclajes": _anclajes_rotos,
		"mortero": [_mortero_ang, _mortero_carga], "tanque": _tanque_ang, "radar": _radar_ang, "cuadros": _cuadros_hechos,
		"minas": minas_vivas, "golpes": _blindada_golpes, "camion": _camion_vida}


func _aplicar_estado(txt: String) -> void:
	var d = JSON.parse_string(txt)
	if not (d is Dictionary) or _soy_host:
		return
	var nuevo_par: Dictionary = d.get("par", {})
	var habia_minas := not par.is_empty()
	par = nuevo_par
	fase = String(d.get("fase", fase))
	if not habia_minas:
		_aplicar_par5()
	_empalmes = d.get("empalmes", _empalmes)
	var m: Array = d.get("mortero", [45.0, 1])
	_mortero_ang = float(m[0])
	_mortero_carga = int(m[1])
	_tanque_ang = float(d.get("tanque", 180.0))
	_radar_ang = float(d.get("radar", 0.0))
	_blindada_golpes = int(d.get("golpes", 0))
	_camion_vida = float(d.get("camion", 900.0))
	var mv: Array = d.get("minas", [])
	for i in mini(mv.size(), _minas.size()):
		if not bool(mv[i]) and bool(_minas[i]["viva"]):
			_mina_quitar(i)
	var an: Array = d.get("anclajes", [false, false])
	for i in an.size():
		if bool(an[i]):
			_anclaje_roto(i, true)
	var cu: Array = d.get("cuadros", [false, false, false])
	for i in cu.size():
		if bool(cu[i]):
			_tramo_pista(i, true)
	var hh: Dictionary = d.get("hecho", {})
	for k in hh:
		if bool(hh[k]) and not _h(String(k)):
			_resolver5(String(k), true)
	_refrescar5()


func _refrescar5() -> void:
	_mortero_refrescar()
	_torreta_refrescar(true)
	_antena_refrescar(true)
	for i in mini(_empalme_mandos.size(), _empalmes.size()):
		if bool(_empalmes[i]):
			_mando_hecho5("p05_e%d" % i)
		else:
			_piloto5(_empalme_mandos[i], "alarma")
	_detonador_refrescar()


func _resolver5(k: String, ya: bool) -> void:
	if _h(k):
		return
	hecho[k] = true
	match k:
		"p01": _p01_resuelto(ya)
		"p02": _p02_resuelto(ya)
		"p03": _p03_resuelto(ya)
		"p05": _p05_resuelto(ya)
		"p06": _p06_resuelto(ya)
		"p08": _p08_resuelto(ya)
		"p09": _p09_resuelto(ya)
		"p11": _p11_resuelto(ya)
		"p12": _p12_resuelto(ya)
	if not ya:
		Audio.ui("objetivo_tomado", -4.0)


# ======================================================================================================
# LA ENTRADA: el tren sale del tunel, la via vuela y el tren vuelca (la cinematica de siempre mira; esto se mueve)
# ======================================================================================================
func _modelo_tren() -> Array:
	var rojo := _mm(Color(0.62, 0.12, 0.08), 0.35, 0.55)
	var crema := _mm(Color(0.9, 0.84, 0.7), 0.2, 0.6)
	var negro := _mm(Color(0.07, 0.07, 0.07), 0.6, 0.5)
	var loco := Node3D.new()
	_caja_mesh(loco, Vector3(11.4, 0.55, 2.8), Vector3(0, 1.2, 0), negro)
	_caja_mesh(loco, Vector3(8.1, 2.0, 2.2), Vector3(1.6, 2.45, 0), rojo)
	_caja_mesh(loco, Vector3(8.1, 0.3, 2.24), Vector3(1.6, 2.3, 0), crema)
	_caja_mesh(loco, Vector3(3.0, 2.9, 2.8), Vector3(-4.0, 2.9, 0), rojo)
	_caja_mesh(loco, Vector3(3.1, 0.25, 2.9), Vector3(-4.0, 4.45, 0), negro)
	for bx in [-3.9, 3.9]:
		for dx in [-0.7, 0.0, 0.7]:
			for sz in [-0.75, 0.75]:
				_cil_mesh(loco, 0.45, 0.12, Vector3(bx + dx, 0.55, sz), negro, Vector3(PI / 2, 0, 0), 12)
	var foco := SpotLight3D.new()
	foco.light_energy = 6.0
	foco.spot_range = 45.0
	foco.spot_angle = 24.0
	foco.light_color = Color(1.0, 0.95, 0.8)
	loco.add_child(foco)
	foco.position = Vector3(5.8, 2.5, 0)
	foco.rotation.y = -PI / 2
	var plat := Node3D.new()
	_caja_mesh(plat, Vector3(5.8, 0.4, 2.8), Vector3(0, 1.0, 0), _mm(Color(0.36, 0.26, 0.18), 0.0, 0.9))
	_caja_mesh(plat, Vector3(5.8, 0.5, 2.6), Vector3(0, 0.55, 0), negro)
	for s in [-1.0, 1.0]:
		_caja_mesh(plat, Vector3(0.9, 0.9, 2.8), Vector3(s * 2.45, 1.65, 0), _mm(Color(0.6, 0.55, 0.42), 0.0, 0.95))
	return [loco, plat]


func _montar_tren() -> void:
	var c := _c("tren")
	if c.is_empty():
		return
	_tren5 = Node3D.new()
	_tren5.name = "TrenDescarrilado"
	add_child(_tren5)
	var m := _modelo_tren()
	_loco5 = m[0]
	_plataforma5 = m[1]
	_tren5.add_child(_loco5)
	_tren5.add_child(_plataforma5)
	var hay_cine: bool = DisplayServer.get_name() != "headless" and not ("--sinintro" in OS.get_cmdline_user_args())
	for a in OS.get_cmdline_user_args():
		if String(a).ends_with("test") or String(a).begins_with("--campanafoto") or String(a).begins_with("--ir="):
			hay_cine = false
	if hay_cine:
		_tren_t = 0.0
	_tren_colocar(99.0 if not hay_cine else 0.0)


## Donde esta el tren en el segundo t de la entrada (a partir de 6,4 s, volcado y quieto)
func _tren_colocar(t: float) -> void:
	var c := _c("tren")
	var vy := float(c.get("y", 5.2))
	var vz := float(c.get("via_z", 11.0))
	var x_fin := 42.0
	var x0 := -26.0
	var t_vuelco := 4.4
	var x: float
	if t < t_vuelco:
		x = x0 + t * 14.0
	else:
		var u := clampf((t - t_vuelco) / 2.0, 0.0, 1.0)
		var x_v := x0 + t_vuelco * 14.0
		x = lerpf(x_v, x_fin, 1.0 - (1.0 - u) * (1.0 - u))
	var k := clampf((t - t_vuelco) / 1.6, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	if is_instance_valid(_loco5):
		_loco5.global_position = Vector3(x, vy - e * 1.4, vz + e * 3.2)
		_loco5.rotation = Vector3(e * 1.32, e * 0.18, e * 0.05)
	if is_instance_valid(_plataforma5):
		_plataforma5.global_position = Vector3(x - 9.2 + e * 1.0, vy - e * 0.6, vz + e * 1.6)
		_plataforma5.rotation = Vector3(e * 0.25, -e * 0.55, 0.0)


func _tren_tick(dt: float) -> void:
	if _tren_t < 0.0:
		return
	var antes := _tren_t
	_tren_t += dt
	_tren_colocar(_tren_t)
	if antes < 3.9 and _tren_t >= 3.9:
		var v: Array = _c("tren").get("voladura", [46, 7, 54, 15])
		var p := Vector3((float(v[0]) + float(v[2])) / 2, 6.0, (float(v[1]) + float(v[3])) / 2)
		var escena := get_tree().current_scene
		if escena and "effects" in escena and escena.effects and escena.effects.has_method("explosion"):
			escena.effects.explosion(p, 5.0)
			escena.effects.explosion(p + Vector3(-2, 0.5, 1), 3.0)
		Audio.explosion(p, 5.0)
	if antes < 4.4 and _tren_t >= 4.4:
		Audio.bf3d("destru/metal", _loco5.global_position, 8.0, 120.0, Audio.PRI_TOP)
	if antes < 5.8 and _tren_t >= 5.8:
		_golpe(_loco5.global_position, 2.0, "destru/derrumbe")
	if _tren_t >= 7.0:
		_tren_t = -1.0
		_tren_colocar(99.0)
		_tren_final()


## El tren ya volcado: humo, fuego y colision (se trepa por el)
func _tren_final() -> void:
	if not is_instance_valid(_loco5) or _loco5.has_node("Choque"):
		return
	var sb := StaticBody3D.new()
	sb.name = "Choque"
	sb.collision_layer = 1
	_loco5.add_child(sb)
	_colision_caja(sb, Vector3(11.4, 3.4, 2.8), Vector3(0, 2.2, 0))
	var sb2 := StaticBody3D.new()
	sb2.collision_layer = 1
	_plataforma5.add_child(sb2)
	_colision_caja(sb2, Vector3(5.8, 1.2, 2.8), Vector3(0, 1.0, 0))
	var humo := _particulas(_loco5, Vector3(1.0, 2.8, 0), 26, 4.0, Color(0.12, 0.12, 0.12, 0.7), Color(0.3, 0.3, 0.3), 2.2, false)
	humo.direction = Vector3.UP
	humo.initial_velocity_min = 1.0
	humo.initial_velocity_max = 2.0
	humo.local_coords = false
	var fuego := _particulas(_loco5, Vector3(2.0, 2.2, 0.6), 22, 0.8, Color(1.0, 0.8, 0.3, 0.9), Color(0.6, 0.1, 0.0), 0.9, true)
	fuego.direction = Vector3.UP
	fuego.initial_velocity_min = 0.5
	fuego.initial_velocity_max = 1.6
	fuego.gravity = Vector3(0, 3.0, 0)
	fuego.local_coords = false
	_luz(_loco5, Vector3(2.0, 3.0, 1.0), Color(1.0, 0.5, 0.2), 2.4, 12.0)


# ======================================================================================================
# EL AMBIENTE: la llama de la antorcha, los focos que barren, los charcos ardiendo
# ======================================================================================================
func _montar_ambiente() -> void:
	var llama := _particulas(self, Vector3(124.0, 29.4, 7.0), 40, 1.1, Color(1.0, 0.8, 0.35, 0.95), Color(0.7, 0.15, 0.02), 1.6, true)
	llama.direction = Vector3.UP
	llama.spread = 18.0
	llama.initial_velocity_min = 2.0
	llama.initial_velocity_max = 4.0
	llama.gravity = Vector3(1.0, 2.0, 0)
	_llama = _luz(self, Vector3.ZERO, Color(1.0, 0.55, 0.2), 3.0, 45.0)
	_llama.global_position = Vector3(124.0, 30.0, 7.0)
	for p in [Vector3(72, 3.1, 26), Vector3(110, 3.1, 30), Vector3(90, 3.1, 52)]:
		var f := _particulas(self, p, 24, 0.9, Color(1.0, 0.8, 0.3, 0.9), Color(0.6, 0.1, 0.0), 1.2, true)
		f.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		f.emission_box_extents = Vector3(1.6, 0.1, 1.1)
		f.direction = Vector3.UP
		f.gravity = Vector3(0, 3.0, 0)
		f.initial_velocity_min = 0.4
		f.initial_velocity_max = 1.4
		_bucle_bf("bf/amb/bucle_fuego", self, Vector3.ZERO, -2.0, 40.0)
	for q in [Vector3(20.0, 11.0, 140.0), Vector3(170.0, 11.0, 140.0)]:
		var foco := SpotLight3D.new()
		foco.light_energy = 4.0
		foco.spot_range = 70.0
		foco.spot_angle = 9.0
		foco.light_color = Color(0.85, 0.9, 1.0)
		foco.shadow_enabled = false
		add_child(foco)
		foco.global_position = q
		_focos.append(foco)


func _ambiente_tick(dt: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	for i in _focos.size():
		var f: SpotLight3D = _focos[i]
		if is_instance_valid(f):
			f.rotation = Vector3(-0.45 + sin(t * 0.3 + i) * 0.15, sin(t * 0.25 + i * 2.0) * 1.2 + (PI if i == 1 else 0.0), 0.0)
	if is_instance_valid(_llama):
		_llama.light_energy = 2.6 + sin(t * 9.0) * 0.4 + randf() * 0.4


# ======================================================================================================
# LOS MANDOS (2026-09-28, pedido: "me dice toca la palanca y no hay ninguna palanca"). Cada cosa que se usa con el
# boton tiene su mando de verdad (mandos.gd) y el aviso de usar sale ENCIMA de el. Donde varios usables comparten
# sitio (el mortero, el tanque, el radar) va UNA CONSOLA con una tecla por usable. Nada lee posiciones globales
# mientras se monta la escena: todo sale de los datos del json (y del mapa, con rayos).
# ======================================================================================================
const CONSOLA_INCL := 0.61                    ## el panel de las consolas, inclinado 35 grados hacia atras
var _mandos5: Dictionary = {}                 ## id del usable -> su mando
var _empalme_mandos: Array = []               ## los cuatro cuadros de los empalmes (tipo interruptor)


## La altura del suelo (voxels) bajo `p`: los mapas van a 10 y a 20 cm y la cota del json no siempre cae en la cara
func _suelo_en(p: Vector3, desde: float = 1.5) -> float:
	if world == null:
		return p.y
	var h: Dictionary = world.raycast(p + Vector3.UP * desde, Vector3.DOWN, desde + 1.5)
	return float((h["position"] as Vector3).y) if bool(h.get("hit", false)) else p.y


## Donde sale el aviso de usar de un mando: por delante de su cara (`fuera` metros)
func _en_mando(id: String, defecto: Vector3, fuera: float = 0.08) -> Vector3:
	var m = _mandos5.get(id)
	if m == null or not is_instance_valid(m) or not (m as Node3D).is_inside_tree():
		return defecto
	var n := m as Node3D
	return n.global_position + n.global_transform.basis.z * fuera


## El gesto de un mando (tecla que se hunde, volante que gira...) en todas las maquinas
func _pulsar5(id: String, dejar_hecho: bool = false) -> void:
	var m = _mandos5.get(id)
	if m != null and is_instance_valid(m):
		Mandos.accionar(m, dejar_hecho)


## El piloto de un mando, tambien si aun no esta en el arbol (Mandos lo pone en "espera" al entrar)
func _piloto5(m, estado: String) -> void:
	if m == null or not is_instance_valid(m):
		return
	var n := m as Node3D
	if n.is_inside_tree():
		Mandos.piloto(n, estado)
	else:
		n.tree_entered.connect(func(): Mandos.piloto(n, estado), CONNECT_ONE_SHOT | CONNECT_DEFERRED)


## Un mando que ya se uso (quien entra tarde, o lo resuelto de golpe): la palanca abajo, sin gesto, y el piloto verde
func _mando_hecho5(id: String) -> void:
	var m = _mandos5.get(id)
	if m == null or not is_instance_valid(m):
		return
	var n := m as Node3D
	if n.has_meta("brazo"):
		(n.get_meta("brazo") as Node3D).rotation.x = 0.5 if n.has_meta("interruptor") else PI - 0.45
	_piloto5(n, "hecho")


## UNA CONSOLA DE PIE: el armario, el panel inclinado hacia quien la usa (las teclas van en su mitad de abajo) y, si
## `pantalla`, una pantalla en su franja de arriba (su Label3D, en la meta "pantalla"). `normal`: hacia donde mira
## (donde se pone el jugador). En el nodo, +X es la derecha de quien la usa y +Z va hacia el. Es baja (`alto` es el
## armario; el panel acaba medio metro mas arriba): por encima se ve el mortero, la torreta o la antena. Lleva su
## lamparita encendida: de noche y con tormenta, sin ella era una mancha negra.
func _consola(suelo: Vector3, normal: Vector3, ancho: float, pantalla: bool, color: Color = Color(0.35, 1.0, 0.45), alto: float = 0.95) -> Node3D:
	var n := Node3D.new()
	n.name = "Consola"
	add_child(n)
	var nz := Vector3(normal.x, 0.0, normal.z).normalized()
	n.transform = Transform3D(Basis.looking_at(-nz, Vector3.UP), Vector3(suelo.x, _suelo_en(suelo), suelo.z))
	var chapa := _mm(Color(0.36, 0.4, 0.3), 0.45, 0.6)
	var oscuro := _mm(Color(0.08, 0.085, 0.09), 0.5, 0.5)
	_caja_mesh(n, Vector3(ancho, alto, 0.6), Vector3(0, alto * 0.5, -0.05), chapa)
	_caja_mesh(n, Vector3(ancho + 0.05, 0.08, 0.65), Vector3(0, 0.04, -0.05), oscuro)              # el zocalo
	for s in [-1.0, 1.0]:                                                                           # los cantos
		_caja_mesh(n, Vector3(0.03, alto - 0.05, 0.62), Vector3(s * ancho * 0.5, alto * 0.5 + 0.025, -0.05), oscuro)
	var nor := Vector3(0, sin(CONSOLA_INCL), cos(CONSOLA_INCL))
	var sube := Vector3(0, cos(CONSOLA_INCL), -sin(CONSOLA_INCL))
	var cara := Vector3(0, alto, 0.25) + sube * 0.3                                                  # el centro del panel
	var losa := _caja_mesh(n, Vector3(ancho, 0.6, 0.3), cara - nor * 0.15, chapa)
	losa.rotation.x = -CONSOLA_INCL
	var placa := _caja_mesh(n, Vector3(ancho - 0.06, 0.54, 0.012), cara + nor * 0.006, oscuro)
	placa.rotation.x = -CONSOLA_INCL
	# la franja de peligro del canto de delante
	for i in int(ancho / 0.12):
		var f := _caja_mesh(n, Vector3(0.06, 0.035, 0.012), Vector3(-ancho * 0.5 + 0.06 + i * 0.12, alto - 0.05, 0.256), _mm(Color(0.93, 0.68, 0.06), 0.25, 0.55) if i % 2 == 0 else oscuro)
		f.rotation.z = 0.6
	# la lamparita del panel: un flexo corto en la esquina de atras, que alumbra las teclas
	var tope := cara + sube * 0.3 - nor * 0.08
	var esquina := Vector3(ancho * 0.5 - 0.08, tope.y, tope.z)
	_cil_mesh(n, 0.012, 0.3, esquina + Vector3(0, 0.15, 0), oscuro, Vector3.ZERO, 6)
	var pantalla_l := _cil_mesh(n, 0.05, 0.07, esquina + Vector3(0, 0.3, 0.05), oscuro, Vector3(-1.1, 0, 0), 10)
	_esfera_mesh(pantalla_l, 0.03, Vector3(0, -0.03, 0), _brillo(Color(1.0, 0.9, 0.7), 3.0))
	_luz(n, cara + nor * 0.45 + Vector3(ancho * 0.25, 0.1, 0), Color(1.0, 0.88, 0.7), 0.9, 2.2)
	n.set_meta("cara", cara)
	if pantalla:
		var pn := Node3D.new()
		pn.position = cara + sube * 0.17 + nor * 0.012
		pn.rotation.x = -CONSOLA_INCL
		n.add_child(pn)
		_caja_mesh(pn, Vector3(ancho - 0.14, 0.17, 0.012), Vector3.ZERO, _brillo(Color(0.02, 0.06, 0.035), 0.5))
		var l := _texto3d("", Vector3(0, 0, 0.008), color, 48, false, pn)
		l.pixel_size = 0.0011
		l.outline_size = 0
		n.set_meta("pantalla", l)
	return n


## Un mando en el panel de una consola, a `x` metros del centro (+ a la derecha de quien la usa)
func _consola_mando(con: Node3D, tipo: String, x: float, v: float = -0.1) -> Node3D:
	var nor := Vector3(0, sin(CONSOLA_INCL), cos(CONSOLA_INCL))
	var sube := Vector3(0, cos(CONSOLA_INCL), -sin(CONSOLA_INCL))
	var cara: Vector3 = con.get_meta("cara")
	return Mandos.crear(tipo, con, cara + Vector3(x, 0, 0) + sube * v + nor * 0.012, nor, true)


## Un cable (tubo fino) de `a` a `b`, sin look_at: sirve mientras se monta la escena
func _cable_entre(a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var d := b - a
	var largo := d.length()
	var mi := _cil_mesh(self, r, maxf(largo, 0.01), Vector3.ZERO, mat, Vector3.ZERO, 8)
	var y := d / maxf(largo, 0.001)
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	return mi


# ======================================================================================================
# 1. EL MORTERO
# ======================================================================================================
func _dir_ang(a_grados: float) -> Vector3:
	var a := deg_to_rad(a_grados)
	return Vector3(cos(a), 0.0, sin(a))


func _montar_p01() -> void:
	var c := _c("p01_mortero")
	if c.is_empty():
		return
	var p := _v(c["pos"])
	_mortero_ang = float(c.get("angulo0", 45.0))
	var base := Node3D.new()
	add_child(base)
	base.global_position = p
	var verde := _mm(Color(0.3, 0.34, 0.2), 0.5, 0.6)
	var negro := _mm(Color(0.08, 0.08, 0.08), 0.6, 0.5)
	_cil_mesh(base, 0.45, 0.08, Vector3(0, 0.04, 0), negro, Vector3.ZERO, 16)
	_mortero_yaw = Node3D.new()
	base.add_child(_mortero_yaw)
	_mortero_yaw.position = Vector3(0, 0.1, 0)
	var tubo := Node3D.new()
	_mortero_yaw.add_child(tubo)
	tubo.rotation.z = deg_to_rad(55.0)
	_cil_mesh(tubo, 0.07, 1.3, Vector3(0.62, 0, 0), verde, Vector3(0, 0, PI / 2), 12)
	for s in [-0.3, 0.3]:
		var pata := _cuerda(negro, 0.025)
		pata.top_level = false
		pata.reparent(_mortero_yaw, false)
		pata.position = Vector3(0.55, 0.35, s)
		pata.rotation = Vector3(s * 0.8, 0, 0.35)
		pata.scale = Vector3(1, 0.8, 1)
	# LA CONSOLA DE TIRO, al oeste del tubo y junto a la entrada de los sacos: quien la usa mira al ESTE, hacia el
	# blanco, y ve girar el mortero por encima. ◀ ▶ el rumbo, ▲ la carga, la seta roja ¡FUEGO!; el rumbo y la carga,
	# en su pantalla (antes era un letrero flotando junto al tubo)
	var con := _consola(Vector3(p.x - 1.3, p.y, p.z - 1.5), Vector3.LEFT, 1.3, true, COLOR_AVISO, 0.8)
	_mandos5["p01_izq"] = _consola_mando(con, "tecla_izq", -0.48)
	_mandos5["p01_der"] = _consola_mando(con, "tecla_der", -0.18)
	_mandos5["p01_carga"] = _consola_mando(con, "tecla_arriba", 0.12)
	_mandos5["p01_fuego"] = _consola_mando(con, "boton", 0.45)
	_mortero_label = con.get_meta("pantalla")
	var tabla := _texto3d("TABLA DE TIRO\nCARGA 1 · 18 m\nCARGA 2 · 26 m\nCARGA 3 · 35 m\nCARGA 4 · 44 m\n\nCASA DE BOMBAS: al ESTE, a unos 35 m",
		p + Vector3(2.2, 1.0, -2.45), Color(0.1, 0.1, 0.12), 20, false, null, 0.0)
	tabla.outline_size = 0
	_rotulo("mortero", "MORTERO · girad, elegid la carga y ¡FUEGO!", p + Vector3(0, 2.8, 0), COLOR_AVISO)
	_rotulo("blanco", "BLANCO: CASA DE BOMBAS", _v(c["blanco"]) + Vector3(-1.5, 3.4, 0), COLOR_PELIGRO)
	_mortero_refrescar()


func _mortero_refrescar() -> void:
	if is_instance_valid(_mortero_yaw):
		var d := _dir_ang(_mortero_ang)
		_mortero_yaw.rotation.y = atan2(-d.z, d.x)
	if is_instance_valid(_mortero_label):
		var brujula := ["E", "SE", "S", "SO", "O", "NO", "N", "NE"]
		var i := int(round(fposmod(_mortero_ang, 360.0) / 45.0)) % 8
		_mortero_label.text = "RUMBO %d° (%s)\nCARGA %d" % [int(fposmod(_mortero_ang, 360.0)), brujula[i], _mortero_carga]


## El anfitrion: donde cae el proyectil (con su dispersion). Si cae cerca del blanco, le da.
func _mortero_disparo() -> void:
	var c := _c("p01_mortero")
	var p := _v(c["pos"])
	var cargas: Array = c["cargas"]
	var alcance := float(cargas[clampi(_mortero_carga - 1, 0, cargas.size() - 1)])
	var d := _dir_ang(_mortero_ang)
	var impacto := p + d * alcance + Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0))
	var blanco := _v(c["blanco"])
	var da := Vector2(impacto.x - blanco.x, impacto.z - blanco.z).length() < float(c.get("radio_blanco", 3.4))
	if da:
		impacto = blanco
	else:
		var h: Dictionary = world.raycast(Vector3(impacto.x, 30.0, impacto.z), Vector3.DOWN, 40.0)
		impacto.y = (h["position"] as Vector3).y if h.get("hit", false) else 3.0
	_evento("p01_disparo", [impacto.x, impacto.y, impacto.z, 1 if da else 0])


func _mortero_proyectil(impacto: Vector3, da: bool) -> void:
	var c := _c("p01_mortero")
	var p := _v(c["pos"]) + Vector3(0, 0.9, 0) + _dir_ang(_mortero_ang) * 0.5
	Audio.play3d("gen/mortero/disparo", p, 6.0, 0.05, 120.0, Audio.PRI_HIGH)
	var fx = jugador.get("effects") if is_instance_valid(jugador) else null
	if fx and fx.has_method("dust"):
		fx.dust(p, 0.6)
	var bala := _esfera_mesh(self, 0.09, Vector3.ZERO, _brillo(Color(1.0, 0.6, 0.3), 1.2))
	bala.global_position = p
	var vuelo := 2.2
	var cima := maxf(p.y, impacto.y) + p.distance_to(impacto) * 0.45
	var mover := func(k: float) -> void:
		if is_instance_valid(bala):
			var q := p.lerp(impacto, k)
			q.y = lerpf(p.y, impacto.y, k) + 4.0 * (cima - lerpf(p.y, impacto.y, k)) * k * (1.0 - k)
			bala.global_position = q
	var tw := create_tween()
	tw.tween_method(mover, 0.0, 1.0, vuelo)
	get_tree().create_timer(vuelo - 1.0).timeout.connect(func(): Audio.play3d("gen/mortero/silbido", impacto + Vector3.UP * 6.0, 4.0, 0.05, 90.0, Audio.PRI_HIGH))
	tw.tween_callback(func():
		if is_instance_valid(bala):
			bala.queue_free()
		_explosion(impacto + Vector3.UP * 0.3, 3.0, 70.0, 2.4)
		if da and _soy_host:
			_evento("p01", []))


func _p01_resuelto(ya: bool) -> void:
	_quitar_cartel("mortero")
	_quitar_cartel("blanco")
	for id in ["p01_izq", "p01_der", "p01_carga", "p01_fuego"]:
		_piloto5(_mandos5.get(id), "hecho")
	var r: Array = _c("p01_mortero").get("hueco", [])
	if r.size() == 6:
		var mn := _mn(r)
		var mx := _mx(r)
		_tallar_rejilla(Vector3(mn.x - 0.5, 0, 0), Vector3.RIGHT, mx.x - mn.x + 1.0,
			[mn.y + 0.5, mn.y + 1.2, mn.y + 1.9, mn.y + 2.4], [mn.z + 0.5, (mn.z + mx.z) / 2, mx.z - 0.5], Vector3.UP, Vector3.BACK, 0.55)
	if not ya:
		_mensaje_local("¡BLANCO! La pared de la CASA DE BOMBAS ha volado: a la refinería")


# ======================================================================================================
# 2. LA ESFERA DE GAS
# ======================================================================================================
func _montar_p02() -> void:
	var c := _c("p02_esfera")
	if c.is_empty():
		return
	var v := _v(c["valvula"])
	# LA VALVULA DE ALIVIO: un volante rojo tumbado encima de su cuerpo azul (el bloque del mapa, de 0,9 m), como una
	# valvula de compuerta de verdad (antes era un disco plano flotando)
	_mandos5["p02_valvula"] = Mandos.crear("volante", self, Vector3(v.x, _suelo_en(v + Vector3(0, 0.9, 0), 0.6), v.z), Vector3.UP)
	var f := _v(c["fuga"])
	var brida := _diana("fuga", f, Vector3(0.7, 0.7, 0.5))
	_cil_mesh(brida, 0.3, 0.15, Vector3.ZERO, _mm(Color(0.75, 0.12, 0.08), 0.6, 0.4), Vector3(PI / 2, 0, 0), 14)
	for k in 6:
		var a := k * TAU / 6.0
		_cil_mesh(brida, 0.035, 0.22, Vector3(cos(a) * 0.23, sin(a) * 0.23, 0), _mm(Color(0.2, 0.2, 0.2), 0.8, 0.4), Vector3(PI / 2, 0, 0), 6)
	_fuga_luz = _luz(brida, Vector3(0, 0.6, -0.4), Color(1.0, 0.2, 0.1), 0.0, 5.0)
	_rotulo("valvula", "VÁLVULA DE ALIVIO DE LA ESFERA", v + Vector3(0, 2.4, 0), COLOR_INFO)
	_rotulo("fuga", "LA FUGA · cuando llegue el gas, ¡disparadle DESDE LEJOS!", f + Vector3(0, 2.2, -1.0), COLOR_PELIGRO)


func _p02_valvula() -> void:
	if _nube_t >= 0.0:
		return
	_nube_t = 0.0
	var c := _c("p02_esfera")
	var v := _v(c["valvula"])
	var f := _v(c["fuga"])
	_pulsar5("p02_valvula", true)
	Audio.play3d("gen/valvula/giro", v + Vector3.UP, 0.0, 0.05, 30.0, Audio.PRI_MID)
	_gas_ruido = _bucle_bf("bf/amb/bucle_gas", self, Vector3.ZERO, 4.0, 50.0)
	if _gas_ruido:
		_gas_ruido.global_position = (v + f) * 0.5
	_nube = _particulas(self, (v + f) * 0.5 + Vector3(0, 0.6, 0), 70, 4.0, Color(0.85, 0.88, 0.8, 0.35), Color(0.7, 0.72, 0.68), 3.0, false)
	_nube.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_nube.emission_box_extents = Vector3(1.0, 0.3, 1.0)
	_nube.direction = Vector3(0, 0.1, 1)
	_nube.spread = 60.0
	_nube.initial_velocity_min = 0.2
	_nube.initial_velocity_max = 0.8
	_nube.gravity = Vector3(0, -0.05, 0.1)
	_mensaje_local("¡EL GAS SALE! Cuando la nube llegue a la FUGA del muro, alejaos y disparadle")


func _nube_tick(dt: float) -> void:
	if _nube_t < 0.0 or _h("p02"):
		return
	_nube_t += dt
	var c := _c("p02_esfera")
	var dur := float(c.get("nube_s", 9.0))
	var k := clampf(_nube_t / dur, 0.0, 1.0)
	if is_instance_valid(_nube):
		var v := _v(c["valvula"])
		var f := _v(c["fuga"])
		_nube.emission_box_extents = Vector3(1.0 + k * 5.0, 0.3 + k * 0.5, 1.0 + k * (f.z - v.z) * 0.5)
	if is_instance_valid(_fuga_luz):
		_fuga_luz.light_energy = (1.5 + sin(Time.get_ticks_msec() * 0.012) * 1.2) if k >= 1.0 else 0.0


func _gas_listo() -> bool:
	return _nube_t >= float(_c("p02_esfera").get("nube_s", 9.0))


func _p02_resuelto(ya: bool) -> void:
	_quitar_cartel("valvula")
	_quitar_cartel("fuga")
	_piloto5(_mandos5.get("p02_valvula"), "hecho")
	var c := _c("p02_esfera")
	var br: Array = c.get("brecha", [])
	if br.size() == 6:
		var mn := _mn(br)
		var mx := _mx(br)
		var us: Array = []
		var x := mn.x + 0.4
		while x < mx.x:
			us.append(x)
			x += 0.8
		_tallar_rejilla(Vector3(0, 0, mn.z - 0.5), Vector3.BACK, mx.z - mn.z + 1.0, us, [mn.y + 0.5, mn.y + 1.2, mn.y + 1.9, mn.y + 2.6, mn.y + 3.2],
			Vector3.RIGHT, Vector3.UP, 0.5)
	if is_instance_valid(_nube):
		_nube.emitting = false
	if is_instance_valid(_gas_ruido):
		_gas_ruido.queue_free()
	if _dianas.has("fuga"):
		(_dianas["fuga"] as Node).queue_free()
		_dianas.erase("fuga")
	if ya:
		return
	# LA BOLA DE FUEGO: la nube arde de la fuga a la esfera, y la esfera revienta
	var e: Array = c["esfera"]
	var ec := Vector3(float(e[0]), float(e[1]), float(e[2]))
	var f := _v(c["fuga"])
	for k in 5:
		var q := f.lerp(ec + Vector3(0, -3.0, 0), k / 4.0)
		get_tree().create_timer(k * 0.12).timeout.connect(func(): _explosion(q, 3.2, 90.0, 0.0))
	get_tree().create_timer(0.7).timeout.connect(func():
		_explosion(ec + Vector3(0, -2.0, 0), 7.0, 200.0, 4.2)
		_explosion(f, 4.0, 150.0, 3.6)
		_bola_de_fuego(ec))
	_mensaje_local("¡¡LA ESFERA HA REVENTADO!!")


func _bola_de_fuego(p: Vector3) -> void:
	var bola := _esfera_mesh(self, 1.0, Vector3.ZERO, _brillo(Color(1.0, 0.55, 0.15), 4.0))
	bola.global_position = p
	var m := bola.material_override as StandardMaterial3D
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var luz := _luz(self, Vector3.ZERO, Color(1.0, 0.6, 0.25), 18.0, 60.0)
	luz.global_position = p + Vector3.UP * 3.0
	var tw := create_tween()
	tw.tween_property(bola, "scale", Vector3.ONE * 14.0, 0.9).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(bola, "global_position:y", p.y + 9.0, 3.0)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 3.0)
	tw.parallel().tween_property(luz, "light_energy", 0.0, 3.5)
	tw.tween_callback(func():
		bola.queue_free()
		luz.queue_free())
	var humo := _particulas(self, p + Vector3.UP * 4.0, 40, 9.0, Color(0.1, 0.1, 0.1, 0.8), Color(0.25, 0.25, 0.25), 6.0, false)
	humo.direction = Vector3.UP
	humo.initial_velocity_min = 2.0
	humo.initial_velocity_max = 4.0
	humo.gravity = Vector3(1.5, 1.0, 0)
	get_tree().create_timer(25.0).timeout.connect(func():
		if is_instance_valid(humo):
			humo.emitting = false)


# ======================================================================================================
# 3. EL PUENTE COLGANTE Y LA VERJA
# ======================================================================================================
func _montar_p03() -> void:
	var c := _c("p03_puente")
	if c.is_empty():
		return
	var r: Array = c["verja"]
	var tam := _mx(r) - _mn(r)
	_verja = _estatico("Verja", _centro(r))
	_colision_caja(_verja, tam + Vector3(0, 0.4, 0), Vector3(0, 0.2, 0))
	var hierro := _mm(Color(0.25, 0.26, 0.27), 0.8, 0.5)
	for k in int(tam.x / 0.2):
		_caja_mesh(_verja, Vector3(0.05, tam.y, 0.05), Vector3(-tam.x / 2 + 0.1 + k * 0.2, 0, 0), hierro)
	for y in [-tam.y / 2 + 0.15, 0.0, tam.y / 2 - 0.1]:
		_caja_mesh(_verja, Vector3(tam.x, 0.1, 0.1), Vector3(0, y, 0), hierro)
	_verja_barrera = AABB(_mn(r) - Vector3(0, 1.0, 1.0), tam + Vector3(0, 2.0, 2.0))
	CriaturaScript.barreras.append(_verja_barrera)
	var an: Array = c["anclajes"]
	for i in an.size():
		var p := _v(an[i])
		var d := _diana("anclaje%d" % i, p, Vector3(0.9, 1.0, 0.7))
		_caja_mesh(d, Vector3(0.7, 0.8, 0.5), Vector3.ZERO, _mm(Color(0.75, 0.1, 0.06), 0.3, 0.6))
		_caja_mesh(d, Vector3(0.72, 0.12, 0.52), Vector3(0, 0.2, 0), _mm(Color(0.9, 0.8, 0.1), 0.3, 0.5))
		_texto3d("C4", Vector3(0, -0.1, -0.27), Color(0.95, 0.95, 0.9), 26, false, d, PI)
	_rotulo("anclajes", "CARGAS DE LOS ANCLAJES · volad el puente si viene la horda", _centro([an[0][0], an[0][1], an[0][2], an[1][0], an[1][1], an[1][2]]) + Vector3(0, 3.2, 0), COLOR_PELIGRO)
	_rotulo("mando_verja", "MANDO DE LA VERJA (tarda 40 s)", _v(c["mando"]) + Vector3(0, 2.2, 0), COLOR_AVISO)
	# EL MANDO: una palanca atornillada en la cara sur del cuadro verde del mapa (junto al pilar de la verja), que es
	# por donde se llega del puente
	var mv := _v(c["mando"])
	_mandos5["p03_mando"] = Mandos.en_pared(world, "palanca", self, Vector3(mv.x - 0.4, mv.y + 1.15, mv.z - 0.7), Vector3(0, 0, -1), 1.3)


func _verja_tick(dt: float) -> void:
	if _verja_t < 0.0 or _h("p03"):
		return
	var dur := float(_c("p03_puente").get("abrir_s", 40.0))
	_verja_t += dt
	var k := clampf(_verja_t / dur, 0.0, 1.0)
	if is_instance_valid(_verja):
		var r: Array = _c("p03_puente")["verja"]
		_verja.global_position.x = _centro(r).x + k * (float(r[3]) - float(r[0]) - 0.6)
	if not _soy_host and _en_red:
		return
	_texto = "LA VERJA SE ABRE · %d s · ¡AGUANTAD!%s" % [ceili(dur - _verja_t), "" if _puente_caido else " · ¡VOLAD EL PUENTE!"]
	# la horda viene de la refineria por el puente mientras siga en pie
	if not _puente_caido:
		_tanda_puente_t -= dt
		if _tanda_puente_t <= 0.0:
			_tanda_puente_t = 7.0
			_horda_desde_refineria(6)
	if k >= 1.0:
		_evento("p03", [])


func _horda_desde_refineria(n: int) -> void:
	var sitios: Array = []
	for q in _pistas:
		var p: Vector3 = q
		if p.x > 64.0 and p.x < 128.0 and p.z > 36.0 and p.z < 60.0:
			sitios.append(p)
	if sitios.is_empty():
		_horda(n, "")
		return
	for i in n:
		_sacar("corredor" if randf() < 0.35 else "zombi", (sitios[randi() % sitios.size()] as Vector3) + Vector3(0, 0.2, 0))


func _anclaje_roto(i: int, ya: bool) -> void:
	if i < 0 or i >= _anclajes_rotos.size() or bool(_anclajes_rotos[i]):
		return
	_anclajes_rotos[i] = true
	var id := "anclaje%d" % i
	var p: Vector3 = (_dianas[id] as Node3D).global_position if _dianas.has(id) else Vector3.ZERO
	if _dianas.has(id):
		(_dianas[id] as Node).queue_free()
		_dianas.erase(id)
	if not ya:
		_explosion(p, 2.2, 60.0, 0.0)
	if not _anclajes_rotos.has(false):
		_puente_cae(ya)


## El puente se va al canal: se talla el tablero (cada maquina, determinista) y cae una copia colgando del norte
func _puente_cae(ya: bool) -> void:
	if _puente_caido:
		return
	_puente_caido = true
	_quitar_cartel("anclajes")
	var c := _c("p03_puente")
	var t: Array = c["tablero"]
	var y := float(c.get("y", 3.4))
	var x0 := float(t[0])
	var z0 := float(t[1])
	var x1 := float(t[2])
	var z1 := float(t[3])
	var us: Array = [x0 + 0.4, (x0 + x1) / 2, x1 - 0.4]
	_tallar_rejilla(Vector3(0, 0, z0 + 0.9), Vector3.BACK, z1 - z0 - 0.9, us, [y - 0.15, y + 0.5], Vector3.RIGHT, Vector3.UP, 0.55)
	CriaturaScript.barreras.append(AABB(Vector3(x0 - 0.5, y - 3.0, z0 + 1.2), Vector3(x1 - x0 + 1.0, 6.0, z1 - z0 - 2.0)))
	if ya:
		return
	var pivote := Node3D.new()
	add_child(pivote)
	pivote.global_position = Vector3((x0 + x1) / 2, y, z0 + 0.9)
	var tablero := Node3D.new()
	pivote.add_child(tablero)
	var largo := z1 - z0 - 0.9
	_caja_mesh(tablero, Vector3(x1 - x0, 0.3, largo), Vector3(0, -0.15, largo / 2), _mm(Color(0.42, 0.3, 0.19), 0.0, 0.9))
	var tw := pivote.create_tween()
	tw.tween_property(pivote, "rotation:x", deg_to_rad(72.0), 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): _golpe(pivote.global_position + Vector3(0, -3.0, 4.0), 1.4, "destru/madera"))
	Audio.play3d("gen/derrumbe/puente", pivote.global_position + Vector3(0, 0, 5), 8.0, 0.02, 120.0, Audio.PRI_HIGH)
	_mensaje_local("¡EL PUENTE SE VA AL CANAL! La horda ya no cruza")


func _p03_resuelto(ya: bool) -> void:
	_quitar_cartel("mando_verja")
	_mando_hecho5("p03_mando")
	CriaturaScript.barreras.erase(_verja_barrera)
	if is_instance_valid(_verja):
		_sin_colision(_verja)
		var r: Array = _c("p03_puente")["verja"]
		_verja.global_position.x = _centro(r).x + (float(r[3]) - float(r[0]) - 0.6)
	if not ya:
		_mensaje_local("¡LA VERJA ESTÁ ABIERTA! Al PATIO: el COLECTOR sale al otro lado")


# ======================================================================================================
# 4. EL COLECTOR: EL AIRE. Bajo el agua se gasta (14 s); fuera se recupera deprisa; sin aire, te ahogas.
# ======================================================================================================
func _aire_tick(dt: float) -> void:
	var ag = preload("res://scripts/agua.gd").actual
	if ag == null or not is_instance_valid(ag) or not is_instance_valid(jugador) or bool(jugador.get("spectating")):
		return
	var maximo := float(_c("p04_colector").get("aire_s", 14.0))
	var bajo: bool = ag.esta_submarino()
	if bajo:
		_aire = maxf(0.0, _aire - dt)
	else:
		_aire = minf(maximo, _aire + dt * 5.0)
	if _aire_capa == null and bajo:
		_aire_capa = CanvasLayer.new()
		_aire_capa.layer = 5
		add_child(_aire_capa)
		var fondo := ColorRect.new()
		fondo.color = Color(0, 0, 0, 0.5)
		fondo.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		fondo.offset_left = -160
		fondo.offset_right = 160
		fondo.offset_top = 90
		fondo.offset_bottom = 108
		_aire_capa.add_child(fondo)
		_aire_barra = ColorRect.new()
		_aire_barra.color = Color(0.4, 0.8, 1.0, 0.95)
		_aire_barra.position = Vector2(3, 3)
		_aire_barra.size = Vector2(314, 12)
		fondo.add_child(_aire_barra)
		var l := Label.new()
		l.text = "AIRE"
		l.position = Vector2(-48, -3)
		l.add_theme_font_size_override("font_size", 16)
		fondo.add_child(l)
	if _aire_capa:
		_aire_capa.visible = _aire < maximo - 0.05
		if _aire_barra:
			_aire_barra.size.x = 314.0 * _aire / maximo
			_aire_barra.color = Color(1.0, 0.25, 0.15, 0.95) if _aire < maximo * 0.3 else Color(0.4, 0.8, 1.0, 0.95)
	if _aire <= 0.0 and bajo:
		_aire_dano_t -= dt
		if _aire_dano_t <= 0.0:
			_aire_dano_t = 0.5
			if jugador.has_method("take_damage") and not bool(jugador.get("invulnerable")):
				jugador.take_damage(6.0, Vector3.ZERO)
			var ahora := Time.get_ticks_msec() * 0.001
			if ahora - _dano_aviso_t > 3.0:
				_dano_aviso_t = ahora
				_mensaje_local("¡TE AHOGAS! ¡Sube a un POZO DE REGISTRO a respirar!")


# ======================================================================================================
# 5. LA DEMOLICION
# ======================================================================================================
func _montar_p05() -> void:
	var c := _c("p05_demolicion")
	if c.is_empty():
		return
	var em: Array = c["empalmes"]
	var e: Array = c["edificio"]
	var cen := Vector3((float(e[0]) + float(e[2])) * 0.5, 0.0, (float(e[1]) + float(e[3])) * 0.5)
	var cable_mat := _mm(Color(0.06, 0.06, 0.06), 0.1, 0.7)
	for i in em.size():
		var p := _v(em[i])
		# EL EMPALME: un cuadro electrico en su poste, mirando hacia fuera del edificio (de donde se llega), con el
		# interruptor abajo y el piloto ROJO: la linea esta cortada. Al reconectar, el interruptor sube y se pone verde.
		# Su cable baja por el poste y va por el suelo hacia el edificio (la linea de las cargas).
		var fuera := Vector3(p.x - cen.x, 0.0, p.z - cen.z).normalized()
		var m := Mandos.en_pared(world, "interruptor", self, p + Vector3(0, 1.15, 0), fuera, 0.05)
		_empalme_mandos.append(m)
		_mandos5["p05_e%d" % i] = m
		_piloto5(m, "alarma")
		var suelo := _suelo_en(p + Vector3(0, 0.5, 0))
		var pie := Vector3(p.x, suelo + 0.03, p.z) - fuera * 0.12
		_cable_entre(p + Vector3(0, 0.95, 0) - fuera * 0.1, pie, 0.018, cable_mat)
		_cable_entre(pie, pie - fuera * 1.6 + Vector3(0.25, 0, 0.25).rotated(Vector3.UP, i), 0.018, cable_mat)
		_rotulo("empalme%d" % i, "EMPALME %d" % (i + 1), p + Vector3(0, 2.3, 0), COLOR_AVISO)
	var dp := _v(c["detonador"])
	var det := Node3D.new()
	det.name = "Detonador"
	add_child(det)
	det.global_position = dp
	_caja_mesh(det, Vector3(0.6, 0.5, 0.4), Vector3(0, 0.25, 0), _mm(Color(0.35, 0.28, 0.12), 0.2, 0.7))
	var mango := Node3D.new()
	mango.name = "Mango"
	det.add_child(mango)
	mango.position = Vector3(0, 0.9, 0)
	_caja_mesh(mango, Vector3(0.04, 0.5, 0.04), Vector3.ZERO, _mm(Color(0.6, 0.6, 0.6), 0.8, 0.4))
	_caja_mesh(mango, Vector3(0.4, 0.05, 0.05), Vector3(0, 0.25, 0), _mm(Color(0.1, 0.1, 0.1), 0.4, 0.5))
	for i in 4:
		var l2 := _esfera_mesh(det, 0.04, Vector3(-0.18 + i * 0.12, 0.52, 0.21), _brillo(Color(0.9, 0.1, 0.05), 1.6))
		_detonador_luces.append(l2)
	_rotulo("detonador", "DETONADOR · antes, los 4 EMPALMES", dp + Vector3(0, 2.0, 0), COLOR_PELIGRO)


func _detonador_refrescar() -> void:
	for i in mini(_detonador_luces.size(), _empalmes.size()):
		(_detonador_luces[i] as MeshInstance3D).material_override = _brillo(Color(0.1, 0.95, 0.25) if bool(_empalmes[i]) else Color(0.9, 0.1, 0.05), 1.8)


func _empalme(i: int) -> void:
	if i < 0 or i >= _empalmes.size() or bool(_empalmes[i]):
		return
	_empalmes[i] = true
	_quitar_cartel("empalme%d" % i)
	_pulsar5("p05_e%d" % i, true)
	_detonador_refrescar()
	Audio.play3d("gen/interruptor/clic", _en_mando("p05_e%d" % i, _v(_c("p05_demolicion")["empalmes"][i]) + Vector3(0, 1.2, 0)), 2.0, 0.05, 20.0, Audio.PRI_MID)
	var n := 0
	for e in _empalmes:
		if bool(e):
			n += 1
	_mensaje_local("EMPALME RECONECTADO (%d de 4)%s" % [n, " · ¡AL DETONADOR!" if n == 4 else ""])


## LA DEMOLICION: cuenta atras, corte de camara, cargas en los pilares, el pasillo del medio, la planta baja entera
## (lo de arriba se queda sin apoyo y el motor lo tira: se viene abajo de verdad) y el muro de la base
func _p05_resuelto(ya: bool) -> void:
	_quitar_cartel("detonador")
	var c := _c("p05_demolicion")
	var e: Array = c["edificio"]
	var e0 := float(e[0])
	var ez0 := float(e[1])
	var e1 := float(e[2])
	var ez1 := float(e[3])
	var piso := float(c.get("piso", 3.2))
	var plantas := int(c.get("plantas", 3))
	var g := 3.0
	var tallar := func() -> void:
		# 1) el pasillo del medio, de arriba abajo (asi caen dos mitades y el paso queda libre)
		var us: Array = []
		var x := 155.3
		while x < 159.3:
			us.append(x)
			x += 0.6
		var vs: Array = []
		var y := g + 0.3
		while y < g + plantas * piso + 1.2:
			vs.append(y)
			y += 0.6
		_tallar_rejilla(Vector3(0, 0, ez0 - 1.0), Vector3.BACK, ez1 - ez0 + 2.0, us, vs, Vector3.RIGHT, Vector3.UP, 0.42)
		# 2) la planta baja entera (cerramientos y pilares): lo de arriba se queda en el aire
		var us2: Array = []
		x = e0 - 0.2
		while x < e1 + 0.2:
			us2.append(x)
			x += 0.6
		_tallar_rejilla(Vector3(0, 0, ez0 - 0.5), Vector3.BACK, ez1 - ez0 + 1.0, us2, [g + 0.35, g + 0.95, g + 1.55, g + 2.15, g + 2.6],
			Vector3.RIGHT, Vector3.UP, 0.42)
		# 3) el muro de la base
		var h: Array = c["hueco"]
		var us3: Array = []
		x = float(h[0]) + 0.3
		while x < float(h[3]):
			us3.append(x)
			x += 0.6
		_tallar_rejilla(Vector3(0, 0, float(h[2]) - 0.5), Vector3.BACK, float(h[5]) - float(h[2]) + 1.0, us3,
			[g + 0.35, g + 0.95, g + 1.55, g + 2.15, g + 2.75, g + 3.35, g + 3.8], Vector3.RIGHT, Vector3.UP, 0.42)
	if ya:
		tallar.call()
		return
	var centro := Vector3((e0 + e1) / 2, g + 4.0, (ez0 + ez1) / 2)
	var cam_p := _v(c.get("camara", [140, 16, 84]))
	_corte([[cam_p, centro, 0.0], [cam_p + Vector3(3.0, -1.5, 2.0), centro + Vector3(0, -1.5, 0), 9.0]], 9.0, "DEMOLICIÓN")
	var det := get_node_or_null("Detonador/Mango") as Node3D
	if det:
		det.create_tween().tween_property(det, "position:y", 0.55, 0.3)
	for k in 3:
		get_tree().create_timer(k * 0.8).timeout.connect(func(): Audio.play2d("gen/teclado/tecla", 0.0, 0.0, Audio.PRI_HIGH))
	Audio.bf2d("amb/sirena", -4.0, Audio.PRI_HIGH)
	# las cargas: una detras de otra por los pilares, y el tallado en el momento del estruendo
	var pilares: Array = []
	for px in [e0 + 0.55, (e0 + e1) / 2, e1 - 0.55]:
		for pz in [ez0 + 0.55, ez1 - 0.55]:
			pilares.append(Vector3(px, g + 1.2, pz))
	for i in pilares.size():
		var q: Vector3 = pilares[i]
		get_tree().create_timer(2.6 + i * 0.16).timeout.connect(func(): _explosion(q, 2.0, 60.0, 1.3))
	get_tree().create_timer(3.4).timeout.connect(func():
		tallar.call()
		_golpe(centro, 2.0, "destru/derrumbe_grave")
		var polvo := _particulas(self, centro + Vector3(0, -2.0, 0), 60, 7.0, Color(0.55, 0.5, 0.45, 0.7), Color(0.4, 0.38, 0.35), 6.0, false)
		polvo.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		polvo.emission_box_extents = Vector3(12.0, 2.0, 7.0)
		polvo.direction = Vector3.UP
		polvo.spread = 70.0
		polvo.initial_velocity_min = 1.0
		polvo.initial_velocity_max = 4.0
		polvo.gravity = Vector3(0, -0.3, 0)
		polvo.one_shot = true
		get_tree().create_timer(12.0).timeout.connect(func():
			if is_instance_valid(polvo):
				polvo.queue_free()))
	get_tree().create_timer(4.4).timeout.connect(func(): _golpe(centro, 2.0, "destru/derrumbe"))
	_mensaje_local("¡FUEGO EN LA DEMOLICIÓN!")


# ======================================================================================================
# 6. LA BALIZA Y EL TECLADO
# ======================================================================================================
func _tecla_pos(k: int) -> Vector3:
	## 1..9 en rejilla de 3, luego BORRAR (9) y ABRIR (10)
	var t := _v(_c("p06_baliza").get("teclado", [0, 0, 0]))
	var col := k % 3
	var fil := k / 3
	return Vector3(t.x + 0.06, t.y + 1.6 - fil * 0.16, t.z - 0.16 + col * 0.16)


func _montar_p06() -> void:
	var c := _c("p06_baliza")
	if c.is_empty():
		return
	_baliza_bola = _esfera_mesh(self, 0.3, Vector3.ZERO, _brillo(Color(0.3, 0.05, 0.03), 0.4))
	_baliza_bola.global_position = _v(c["mastil"])
	_baliza_luz = _luz(self, Vector3.ZERO, Color(1.0, 0.15, 0.08), 0.0, 22.0)
	_baliza_luz.global_position = _v(c["mastil"]) + Vector3(0, 0.3, 0)
	var t := _v(c["teclado"])
	var caja := Node3D.new()
	add_child(caja)
	caja.global_position = t
	_caja_mesh(caja, Vector3(0.1, 0.8, 0.6), Vector3(0, 1.4, 0), _mm(Color(0.2, 0.21, 0.22), 0.7, 0.4))
	_caja_mesh(caja, Vector3(0.1, 1.0, 0.1), Vector3(0, 0.5, 0), _mm(Color(0.1, 0.1, 0.1), 0.7, 0.4))
	var nombres := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "OK"]
	for k in nombres.size():
		var p := _tecla_pos(k)
		var tecla := _caja_mesh(self, Vector3(0.03, 0.12, 0.12), Vector3.ZERO, _mm(Color(0.55, 0.56, 0.58), 0.6, 0.4))
		tecla.global_position = p
		var l := _texto3d(nombres[k], p + Vector3(0.025, 0, 0), Color(0.05, 0.05, 0.05), 14, false, null, PI / 2)
		l.outline_size = 0
	_pantalla = _texto3d("- - -", t + Vector3(0.07, 1.78, 0), Color(0.3, 1.0, 0.4), 30, false, null, PI / 2)
	_pantalla.outline_size = 2
	var r: Array = c["verja"]
	var tam := _mx(r) - _mn(r)
	_verja_int = _estatico("VerjaInterior", _centro(r))
	_colision_caja(_verja_int, tam + Vector3(0, 0.4, 0), Vector3(0, 0.2, 0))
	var hierro := _mm(Color(0.25, 0.26, 0.27), 0.8, 0.5)
	for k in int(tam.z / 0.2):
		_caja_mesh(_verja_int, Vector3(0.05, tam.y, 0.05), Vector3(0, 0, -tam.z / 2 + 0.1 + k * 0.2), hierro)
	for y in [-tam.y / 2 + 0.15, 0.0, tam.y / 2 - 0.1]:
		_caja_mesh(_verja_int, Vector3(0.1, 0.1, tam.z), Vector3(0, y, 0), hierro)
	_texto3d("ACCESO RESTRINGIDO\nCÓDIGO: el que da la BALIZA del mástil", Vector3(0.1, 0.6, 0), COLOR_AVISO, 26, false, _verja_int, PI / 2)
	_verja_int_barrera = AABB(_mn(r) - Vector3(1.0, 1.0, 0), tam + Vector3(2.0, 2.0, 0))
	CriaturaScript.barreras.append(_verja_int_barrera)
	_rotulo("teclado", "TECLADO · mirad la BALIZA roja del mástil y contad", t + Vector3(0.6, 2.6, 0), COLOR_INFO)


## La baliza parpadea las tres cifras: tantos destellos como la cifra, pausa, la siguiente; y una pausa larga
func _baliza_tick(dt: float) -> void:
	if _h("p06") or not is_instance_valid(_baliza_luz):
		return
	var cif: Array = par.get("cifras", [])
	if cif.size() < 3:
		return
	var sec: Array = []           # [encendida, segundos]
	for d in cif:
		for k in int(d):
			sec.append([true, 0.35])
			sec.append([false, 0.35])
		sec.append([false, 1.1])
	sec.append([false, 2.4])
	var total := 0.0
	for s in sec:
		total += float(s[1])
	_baliza_t = fmod(_baliza_t + dt, total)
	var acc := 0.0
	var on := false
	for s in sec:
		acc += float(s[1])
		if _baliza_t < acc:
			on = bool(s[0])
			break
	_baliza_luz.light_energy = 5.0 if on else 0.0
	_baliza_bola.material_override = _brillo(Color(1.0, 0.15, 0.08), 4.0) if on else _brillo(Color(0.3, 0.05, 0.03), 0.4)


func _teclado_mostrar(txt: String) -> void:
	if is_instance_valid(_pantalla):
		var t := ""
		for k in 3:
			t += (txt[k] if k < txt.length() else "-") + (" " if k < 2 else "")
		_pantalla.text = t


func _p06_resuelto(ya: bool) -> void:
	_quitar_cartel("teclado")
	CriaturaScript.barreras.erase(_verja_int_barrera)
	if is_instance_valid(_baliza_luz):
		_baliza_luz.light_energy = 0.0
	if is_instance_valid(_pantalla):
		_pantalla.text = "O K"
	if is_instance_valid(_verja_int):
		_sin_colision(_verja_int)
		if ya:
			_verja_int.global_position.z += 5.6
		else:
			_verja_int.create_tween().tween_property(_verja_int, "global_position:z", _verja_int.global_position.z + 5.6, 3.0).set_trans(Tween.TRANS_SINE)
			Audio.play3d("gen/ascensor/reja", _verja_int.global_position, 2.0, 0.02, 40.0, Audio.PRI_HIGH)
			_mensaje_local("¡CÓDIGO CORRECTO! Cuidado: detrás está el CAMPO DE MINAS")


# ======================================================================================================
# 7. EL CAMPO DE MINAS
# ======================================================================================================
func _montar_p07() -> void:
	var c := _c("p07_minas")
	if c.is_empty():
		return
	var campo: Array = c["campo"]
	_rotulo("minas", "¡CAMPO DE MINAS! reventadlas a tiros para abrir paso", Vector3(float(campo[2]) - 2.0, 5.5, (float(campo[1]) + float(campo[3])) / 2), COLOR_PELIGRO)


func _montar_minas() -> void:
	if not _minas.is_empty():
		return
	var y := float(_c("p07_minas").get("y", 3.0))
	var ms: Array = par.get("minas", [])
	for i in ms.size():
		var p := Vector3(float(ms[i][0]), y, float(ms[i][1]))
		var d := _diana("mina%d" % i, p + Vector3(0, 0.15, 0), Vector3(0.55, 0.35, 0.55))
		_cil_mesh(d, 0.22, 0.1, Vector3(0, -0.1, 0), _mm(Color(0.22, 0.25, 0.16), 0.5, 0.6), Vector3.ZERO, 12)
		for k in 3:
			var a := k * TAU / 3.0
			_cil_mesh(d, 0.012, 0.12, Vector3(cos(a) * 0.06, 0.0, sin(a) * 0.06), _mm(Color(0.3, 0.3, 0.3), 0.8, 0.4), Vector3.ZERO, 4)
		var led := _esfera_mesh(d, 0.025, Vector3(0.1, -0.03, 0), _brillo(Color(1.0, 0.05, 0.02), 3.0))
		led.name = "Led"
		_minas.append({"pos": p, "nodo": d, "viva": true})


func _minas_tick(dt: float) -> void:
	# el piloto rojo de cada mina parpadea (cada maquina)
	_led_t += dt
	var on := fmod(_led_t, 1.4) < 0.12
	for m in _minas:
		if bool(m["viva"]) and is_instance_valid(m["nodo"]):
			var led := (m["nodo"] as Node).get_node_or_null("Led") as Node3D
			if led:
				led.visible = on
	if (_en_red and not _soy_host) or _minas.is_empty():
		return
	# el anfitrion: quien pisa cerca de una mina la hace saltar (personas y bichos; los bots no, que no piensan)
	_minas_t -= dt
	if _minas_t > 0.0:
		return
	_minas_t = 0.1
	var pisan: Array = []
	for pl in _jugadores_vivos():
		pisan.append((pl as Node3D).global_position)
	for cr in _vivos:
		if is_instance_valid(cr):
			pisan.append((cr as Node3D).global_position)
	for i in _minas.size():
		var m: Dictionary = _minas[i]
		if not bool(m["viva"]):
			continue
		var mp: Vector3 = m["pos"]
		for q in pisan:
			var p: Vector3 = q
			if absf(p.y - mp.y) < 1.2 and Vector2(p.x - mp.x, p.z - mp.z).length() < 0.9:
				_mina_salta(i)
				break


## El anfitrion hace saltar una mina (y las de al lado, en cadena, un poco despues)
func _mina_salta(i: int) -> void:
	if i < 0 or i >= _minas.size() or not bool(_minas[i]["viva"]):
		return
	_minas[i]["viva"] = false
	_evento("p07_mina", [i])
	var p: Vector3 = _minas[i]["pos"]
	for j in _minas.size():
		if j != i and bool(_minas[j]["viva"]) and (_minas[j]["pos"] as Vector3).distance_to(p) < 3.0:
			var jj := j
			get_tree().create_timer(0.22 + randf() * 0.15).timeout.connect(func(): _mina_salta(jj))


func _mina_quitar(i: int) -> void:
	if i < 0 or i >= _minas.size():
		return
	_minas[i]["viva"] = false
	var id := "mina%d" % i
	if _dianas.has(id):
		(_dianas[id] as Node).queue_free()
		_dianas.erase(id)


func _mina_explota(i: int) -> void:
	if i < 0 or i >= _minas.size():
		return
	var p: Vector3 = _minas[i]["pos"]
	_mina_quitar(i)
	_explosion(p + Vector3.UP * 0.2, 1.8, 95.0, 1.1)


# ======================================================================================================
# 8. EL TANQUE
# ======================================================================================================
func _montar_p08() -> void:
	var c := _c("p08_tanque")
	if c.is_empty():
		return
	var p := _v(c["pos"])
	var oliva := _mm(Color(0.3, 0.34, 0.2), 0.45, 0.65)
	var oscuro := _mm(Color(0.12, 0.13, 0.1), 0.5, 0.6)
	var casco := _estatico("Tanque", p)
	casco.add_to_group(TREPABLE)
	_colision_caja(casco, Vector3(6.6, 1.6, 3.4), Vector3(0, 0.8, 0))
	_caja_mesh(casco, Vector3(6.6, 1.0, 3.0), Vector3(0, 1.0, 0), oliva)
	_caja_mesh(casco, Vector3(6.2, 0.4, 2.6), Vector3(0.1, 1.65, 0), oliva)
	for s in [-1.0, 1.0]:
		_caja_mesh(casco, Vector3(6.8, 0.9, 0.6), Vector3(0, 0.45, s * 1.5), oscuro)
		for k in 6:
			_cil_mesh(casco, 0.34, 0.5, Vector3(-2.7 + k * 1.08, 0.4, s * 1.5), oscuro, Vector3(PI / 2, 0, 0), 10)
	_torreta = Node3D.new()
	casco.add_child(_torreta)
	_torreta.position = Vector3(-0.3, 1.85, 0)
	_caja_mesh(_torreta, Vector3(2.6, 0.8, 2.2), Vector3(0, 0.4, 0), oliva)
	_cil_mesh(_torreta, 0.13, 4.0, Vector3(3.2, 0.45, 0), oliva, Vector3(0, 0, PI / 2), 12)
	_cil_mesh(_torreta, 0.2, 0.5, Vector3(5.2, 0.45, 0), oscuro, Vector3(0, 0, PI / 2), 12)
	_texto3d("★", Vector3(0, 0.45, 1.11), Color(0.9, 0.9, 0.85), 60, false, _torreta)
	# la mira laser del cañon (se ve adonde ira el proyectil)
	_laser = _cuerda(_brillo(Color(1.0, 0.1, 0.05), 3.0), 0.012)
	_laser_punto = _esfera_mesh(self, 0.12, Vector3.ZERO, _brillo(Color(1.0, 0.1, 0.05), 4.0))
	_tanque_ang = float(c.get("giro0", 180.0))
	_torreta_refrescar(true)
	# LA CONSOLA DE TIRO, en el suelo al SUR del tanque, con su cable al casco: quien la usa mira al norte, por encima
	# del tanque, y ve la torreta, el laser y la puerta blindada al fondo. ◀ ▶ la torreta, la seta roja ¡FUEGO!
	var con := _consola(p + Vector3(0, 0, 3.2), Vector3.BACK, 1.0, false)
	_mandos5["p08_izq"] = _consola_mando(con, "tecla_izq", -0.33)
	_mandos5["p08_der"] = _consola_mando(con, "tecla_der", -0.03)
	_mandos5["p08_fuego"] = _consola_mando(con, "boton", 0.28)
	var goma := _mm(Color(0.05, 0.05, 0.05), 0.1, 0.7)
	var cs := _suelo_en(p + Vector3(0.3, 0.5, 2.8))
	_cable_entre(Vector3(p.x + 0.3, cs + 0.3, p.z + 2.83), Vector3(p.x + 0.3, cs + 0.03, p.z + 2.6), 0.025, goma)
	_cable_entre(Vector3(p.x + 0.3, cs + 0.03, p.z + 2.6), Vector3(p.x + 0.3, p.y + 0.92, p.z + 1.82), 0.025, goma)
	_cable_entre(Vector3(p.x + 0.3, p.y + 0.92, p.z + 1.82), Vector3(p.x + 0.3, p.y + 1.25, p.z + 1.5), 0.025, goma)
	# la puerta blindada del hangar
	var r: Array = c["puerta"]
	var tam := _mx(r) - _mn(r)
	_blindada = _estatico("PuertaBlindada", _centro(r))
	_colision_caja(_blindada, tam, Vector3.ZERO)
	_caja_mesh(_blindada, tam, Vector3.ZERO, _mm(Color(0.36, 0.38, 0.36), 0.85, 0.35))
	for k in 5:
		_caja_mesh(_blindada, Vector3(tam.x + 0.06, 0.12, tam.z), Vector3(0, -tam.y / 2 + 0.6 + k * 0.95, 0), _mm(Color(0.85, 0.66, 0.08), 0.4, 0.5))
	_texto3d("HANGAR 3\nBLINDADA", Vector3(0.45, 0.4, 0), Color(0.1, 0.1, 0.1), 50, false, _blindada, PI / 2)
	_blindada_barrera = AABB(_mn(r) - Vector3(0.8, 1.0, 0), tam + Vector3(1.6, 2.0, 0))
	CriaturaScript.barreras.append(_blindada_barrera)
	_rotulo("tanque", "TANQUE · girad la torreta y ¡FUEGO! contra la PUERTA BLINDADA", p + Vector3(0, 4.2, 0), COLOR_AVISO)


func _boca_canon() -> Vector3:
	if not is_instance_valid(_torreta):
		return Vector3.ZERO
	return _torreta.global_transform * Vector3(5.5, 0.45, 0)


func _torreta_refrescar(ya: bool) -> void:
	if not is_instance_valid(_torreta):
		return
	var d := _dir_ang(_tanque_ang)
	var obj := atan2(-d.z, d.x)
	if ya:
		_torreta.rotation.y = obj
	else:
		var dest := _torreta.rotation.y + angle_difference(_torreta.rotation.y, obj)
		_torreta.create_tween().tween_property(_torreta, "rotation:y", dest, 0.45).set_trans(Tween.TRANS_SINE)
		Audio.play3d("gen/tanque/torreta", _torreta.global_position, -2.0, 0.05, 25.0, Audio.PRI_MID)


func _laser_tick() -> void:
	if not is_instance_valid(_torreta) or not is_instance_valid(_laser) or _h("p08") and fase != "p12":
		if is_instance_valid(_laser):
			_laser.visible = false
			_laser_punto.visible = false
		return
	var boca := _boca_canon()
	var dir := (_torreta.global_transform.basis * Vector3.RIGHT).normalized()
	var fin := boca + dir * 120.0
	var hp := _rayo_puerta(boca, dir)
	if hp != Vector3.INF:
		fin = hp
	else:
		var h: Dictionary = world.raycast(boca, dir, 120.0)
		if h.get("hit", false):
			fin = h["position"]
	_linea(_laser, boca, fin)
	_laser_punto.visible = true
	_laser_punto.global_position = fin


## ¿El proyectil entra en la puerta blindada? (es un objeto: el rayo de voxels no la ve)
func _rayo_puerta(o: Vector3, d: Vector3) -> Vector3:
	if not is_instance_valid(_blindada) or _h("p08"):
		return Vector3.INF
	var r: Array = _c("p08_tanque")["puerta"]
	var caja := AABB(_mn(r), _mx(r) - _mn(r)).grow(0.2)
	var hit = caja.intersects_segment(o, o + d * 150.0)
	return hit if hit != null else Vector3.INF


## El anfitrion dispara el cañon: a la puerta (si la ve) o a lo que haya (voxels: explosion de verdad)
func _tanque_disparo() -> void:
	var boca := _boca_canon()
	var dir := (_torreta.global_transform.basis * Vector3.RIGHT).normalized()
	var hp := _rayo_puerta(boca, dir)
	var puerta := hp != Vector3.INF
	var fin := hp
	if not puerta:
		var h: Dictionary = world.raycast(boca, dir, 150.0)
		fin = h["position"] if h.get("hit", false) else boca + dir * 150.0
		# el camion de combustible (el final) tambien se puede volar a cañonazos
		var dc = _dianas.get("camion")
		if dc != null and is_instance_valid(dc):
			var cr: Array = _c("p12_camion")["camion"]
			var caja := AABB(Vector3(float(cr[0]), 3.0, float(cr[1])), Vector3(float(cr[2]) - float(cr[0]), 3.0, float(cr[3]) - float(cr[1])))
			var hc = caja.intersects_segment(boca, fin)
			if hc != null:
				fin = hc
				_on_pide("diana:camion:900", 1)
	_evento("p08_disparo", [fin.x, fin.y, fin.z, 1 if puerta else 0])
	if puerta:
		_blindada_golpes += 1
		if _blindada_golpes >= int(_c("p08_tanque").get("golpes", 3)):
			get_tree().create_timer(0.6).timeout.connect(func(): _evento("p08", []))


func _tanque_fuego(fin: Vector3, puerta: bool) -> void:
	var boca := _boca_canon()
	Audio.play3d("gen/tanque/canon", boca, 10.0, 0.04, 200.0, Audio.PRI_TOP)
	var fx = jugador.get("effects") if is_instance_valid(jugador) else null
	if fx and fx.has_method("dust"):
		fx.dust(boca, 1.2)
	var traza := _cuerda(_brillo(Color(1.0, 0.8, 0.4), 3.0), 0.06)
	_linea(traza, boca, fin)
	get_tree().create_timer(0.08).timeout.connect(func():
		if is_instance_valid(traza):
			traza.queue_free())
	_explosion(fin, 2.6, 80.0, 0.0 if puerta else 2.2)
	if puerta and is_instance_valid(_blindada):
		var tw := _blindada.create_tween()
		tw.tween_property(_blindada, "rotation:z", randf_range(-0.05, 0.05), 0.08)
		tw.tween_property(_blindada, "rotation:z", 0.0, 0.2)


func _p08_resuelto(ya: bool) -> void:
	_quitar_cartel("tanque")
	for id in ["p08_izq", "p08_der", "p08_fuego"]:
		_piloto5(_mandos5.get(id), "hecho")
	CriaturaScript.barreras.erase(_blindada_barrera)
	if not is_instance_valid(_blindada):
		return
	_sin_colision(_blindada)
	if ya:
		_blindada.visible = false
		return
	# la puerta sale volando hacia dentro del hangar
	var tw := _blindada.create_tween()
	tw.tween_property(_blindada, "global_position", _blindada.global_position + Vector3(-7.0, -1.6, 1.5), 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_blindada, "rotation", Vector3(0.3, 0.6, 1.45), 0.7)
	tw.tween_callback(func(): _golpe(_blindada.global_position, 1.6, "destru/metal"))
	_mensaje_local("¡LA PUERTA BLINDADA HA VOLADO! Cruzad el HANGAR hasta la TORRE DE CONTROL")


# ======================================================================================================
# 9. EL RADAR
# ======================================================================================================
func _montar_p09() -> void:
	var c := _c("p09_radar")
	if c.is_empty():
		return
	var p := _v(c["pos"])
	var base := Node3D.new()
	add_child(base)
	base.global_position = p
	var gris := _mm(Color(0.7, 0.72, 0.72), 0.6, 0.4)
	_cil_mesh(base, 0.5, 1.4, Vector3(0, 0.7, 0), _mm(Color(0.3, 0.32, 0.32), 0.7, 0.5), Vector3.ZERO, 12)
	_antena = Node3D.new()
	base.add_child(_antena)
	_antena.position = Vector3(0, 1.6, 0)
	var plato := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.8
	sm.height = 1.2
	sm.is_hemisphere = true
	plato.mesh = sm
	plato.material_override = gris
	plato.rotation.z = -PI / 2
	plato.position = Vector3(0.2, 0.6, 0)
	_antena.add_child(plato)
	_cil_mesh(_antena, 0.04, 1.4, Vector3(0.9, 0.6, 0), gris, Vector3(0, 0, PI / 2), 6)
	_cil_mesh(_antena, 0.15, 0.3, Vector3(1.6, 0.6, 0), _mm(Color(0.2, 0.2, 0.2), 0.6, 0.5), Vector3(0, 0, PI / 2), 8)
	# LA CONSOLA DEL RADAR, al noroeste de la antena (de donde se llega por la escalera), girada hacia ella: por
	# encima se ve el plato girar. ◀ ▶ y la señal en su pantalla (antes era un letrero flotando)
	var hacia := Vector3(-0.5, 0.0, -0.866)
	var con := _consola(p + hacia * 2.75, hacia, 0.9, true)
	_mandos5["p09_izq"] = _consola_mando(con, "tecla_izq", -0.17)
	_mandos5["p09_der"] = _consola_mando(con, "tecla_der", 0.17)
	_radar_label = con.get_meta("pantalla")
	_radar_ang = 0.0
	_antena_refrescar(true)
	_rotulo("radar", "RADAR · girad la antena hasta que la señal pite seguida", p + Vector3(0, 4.2, 0), COLOR_INFO)


func _senal() -> float:
	var obj := float(par.get("radar", 0.0))
	var dif := absf(angle_difference(deg_to_rad(_radar_ang), deg_to_rad(obj)))
	return clampf(1.0 - dif / PI, 0.0, 1.0)


func _antena_refrescar(ya: bool) -> void:
	if not is_instance_valid(_antena):
		return
	var obj := deg_to_rad(-_radar_ang)
	if ya:
		_antena.rotation.y = obj
	else:
		var dest := _antena.rotation.y + angle_difference(_antena.rotation.y, obj)
		_antena.create_tween().tween_property(_antena, "rotation:y", dest, 0.4)
	if is_instance_valid(_radar_label):
		var s := _senal()
		var n := int(round(s * 10.0))
		_radar_label.text = "SEÑAL %d %%\n%s" % [int(s * 100.0), "▮".repeat(n) + "▯".repeat(10 - n)]


func _radar_tick(dt: float) -> void:
	if _h("p09") or not is_instance_valid(_antena) or not is_instance_valid(jugador):
		return
	if jugador.global_position.distance_to(_antena.global_position) > 14.0:
		return
	_pitido_t -= dt
	if _pitido_t <= 0.0:
		var s := _senal()
		_pitido_t = lerpf(1.3, 0.1, s * s)
		Audio.play3d("gen/radar/pitido", _antena.global_position, -4.0 + s * 4.0, 0.0, 30.0, Audio.PRI_MID)


func _p09_resuelto(ya: bool) -> void:
	_quitar_cartel("radar")
	for id in ["p09_izq", "p09_der"]:
		_piloto5(_mandos5.get(id), "hecho")
	_radar_ang = float(par.get("radar", 0.0))
	_antena_refrescar(ya)
	if is_instance_valid(_radar_label):
		_radar_label.text = "CONTACTO"
	if not ya:
		Audio.bf2d("amb/radio", 0.0, Audio.PRI_HIGH)
		_mensaje_local("PILOTO: «¡Base, os oigo! Encended las LUCES DE LA PISTA y bajo a por vosotros»")


# ======================================================================================================
# 10. LAS LUCES DE LA PISTA
# ======================================================================================================
func _montar_p10() -> void:
	var c := _c("p10_pista")
	if c.is_empty():
		return
	var cu: Array = c["cuadros"]
	for i in cu.size():
		var p := _v(cu[i])
		var caja := Node3D.new()
		add_child(caja)
		caja.global_position = p
		_caja_mesh(caja, Vector3(1.0, 1.6, 0.5), Vector3(0, 0.8, 0), _mm(Color(0.25, 0.27, 0.25), 0.6, 0.5))
		_caja_mesh(caja, Vector3(1.04, 0.2, 0.54), Vector3(0, 1.3, 0), _mm(Color(0.85, 0.66, 0.08), 0.4, 0.5))
		_cuadros_label.append(_texto3d("TRAMO %d · 0 %%" % (i + 1), p + Vector3(0, 2.2, 0.3), COLOR_AVISO, 30))
		_rotulo("cuadro%d" % i, "LUCES DE PISTA %d · quedaos al lado" % (i + 1), p + Vector3(0, 3.2, 0), COLOR_AVISO)
	var pi: Array = c["pista"]
	var x0 := float(pi[0])
	var z0 := float(pi[1])
	var x1 := float(pi[2])
	var z1 := float(pi[3])
	var tramo := (x1 - x0) / 3.0
	var x := x0 + 3.0
	while x < x1 - 2.0:
		var i := clampi(int((x - x0) / tramo), 0, 2)
		for z in [z0 + 0.2, z1 - 0.2]:
			var l := _caja_mesh(self, Vector3(0.3, 0.25, 0.3), Vector3.ZERO, _brillo(Color(0.25, 0.2, 0.1), 0.2))
			l.global_position = Vector3(x, 3.12, z)
			(_luces_pista[i] as Array).append(l)
		x += 8.0


func _pista_tick(dt: float) -> void:
	if _h("p10") or not _h("p09"):
		return
	var c := _c("p10_pista")
	var cu: Array = c["cuadros"]
	if _soy_host or not _en_red:
		var dur := float(c.get("aguantar_s", 10.0))
		for i in cu.size():
			if bool(_cuadros_hechos[i]):
				continue
			var p := _v(cu[i])
			var alguien := false
			for pl in _jugadores_vivos():
				if (pl as Node3D).global_position.distance_to(p) < 2.6:
					alguien = true
			if alguien:
				_cuadros_k[i] = minf(1.0, float(_cuadros_k[i]) + dt / dur)
				if float(_cuadros_k[i]) >= 1.0:
					_evento("p10_tramo", [i])
		_pista_red_t -= dt
		if _pista_red_t <= 0.0:
			_pista_red_t = 0.3
			_evento("p10_k", _cuadros_k)
		var hechos := 0
		for h in _cuadros_hechos:
			if bool(h):
				hechos += 1
		_texto = "LUCES DE LA PISTA · %d de 3 tramos · quedaos junto a cada CUADRO" % hechos
		if hechos >= 3:
			_evento("p10", [])
			get_tree().create_timer(6.5).timeout.connect(func(): _evento("p11_empieza", []))
	for i in mini(_cuadros_label.size(), 3):
		(_cuadros_label[i] as Label3D).text = "TRAMO %d · %s" % [i + 1, "ENCENDIDO" if bool(_cuadros_hechos[i]) else "%d %%" % int(float(_cuadros_k[i]) * 100.0)]


func _tramo_pista(i: int, ya: bool) -> void:
	if i < 0 or i > 2 or bool(_cuadros_hechos[i]):
		return
	_cuadros_hechos[i] = true
	_cuadros_k[i] = 1.0
	_quitar_cartel("cuadro%d" % i)
	var luces: Array = _luces_pista[i]
	for k in luces.size():
		var l: MeshInstance3D = luces[k]
		if ya:
			l.material_override = _brillo(Color(1.0, 0.85, 0.5), 5.0)
		else:
			get_tree().create_timer(k * 0.03).timeout.connect(func():
				if is_instance_valid(l):
					l.material_override = _brillo(Color(1.0, 0.85, 0.5), 5.0))
	if not ya:
		Audio.play3d("gen/generador/arranque", _v(_c("p10_pista")["cuadros"][i]), 2.0, 0.0, 60.0, Audio.PRI_HIGH)
		_mensaje_local("¡TRAMO %d ENCENDIDO!" % (i + 1))


## La pista entera encendida: un plano alto de las luces corriendo hacia el este
func _p10_corte() -> void:
	var pi: Array = _c("p10_pista")["pista"]
	var zc := (float(pi[1]) + float(pi[3])) / 2
	_corte([[Vector3(-6, 16, zc - 18), Vector3(60, 3, zc), 0.0], [Vector3(20, 12, zc - 22), Vector3(140, 3, zc), 6.0]], 6.0, "LA PISTA, ENCENDIDA")
	for i in 3:
		for l in _luces_pista[i]:
			var m: MeshInstance3D = l
			var t := (m.global_position.x / 176.0) * 2.0
			get_tree().create_timer(t).timeout.connect(func():
				if is_instance_valid(m):
					m.material_override = _brillo(Color(1.0, 1.0, 1.0), 12.0)
					get_tree().create_timer(0.15).timeout.connect(func():
						if is_instance_valid(m):
							m.material_override = _brillo(Color(1.0, 0.85, 0.5), 5.0)))


# ======================================================================================================
# 11. EL AVION, EL ATERRIZAJE Y EL HELICOPTERO
# ======================================================================================================
func _modelo_avion() -> Node3D:
	## Un Hercules: fuselaje, ala alta, cuatro motores con helice, deriva y la rampa de cola. +X es el morro.
	var a := Node3D.new()
	var gris := _mm(Color(0.46, 0.5, 0.52), 0.5, 0.5)
	var oscuro := _mm(Color(0.2, 0.22, 0.24), 0.6, 0.5)
	var cristal := _mm(Color(0.2, 0.28, 0.32), 0.6, 0.1)
	_caja_mesh(a, Vector3(20.0, 3.8, 4.0), Vector3(0, 2.6, 0), gris)
	var morro := _esfera_mesh(a, 2.0, Vector3(10.0, 2.7, 0), gris)
	morro.scale = Vector3(1.6, 0.95, 1.0)
	_caja_mesh(a, Vector3(1.6, 0.8, 2.6), Vector3(10.6, 3.7, 0), cristal)
	_caja_mesh(a, Vector3(7.0, 2.4, 3.2), Vector3(-13.0, 3.3, 0), gris)
	_caja_mesh(a, Vector3(3.6, 5.5, 0.35), Vector3(-15.0, 6.8, 0), gris)
	_caja_mesh(a, Vector3(3.2, 0.3, 11.0), Vector3(-15.2, 4.3, 0), gris)
	_caja_mesh(a, Vector3(4.2, 0.45, 30.0), Vector3(1.0, 4.9, 0), gris)
	for z in [-11.0, -5.5, 5.5, 11.0]:
		_cil_mesh(a, 0.55, 3.6, Vector3(2.4, 4.3, z), oscuro, Vector3(0, 0, PI / 2), 12)
		var helice := Node3D.new()
		a.add_child(helice)
		helice.position = Vector3(4.3, 4.3, z)
		for k in 4:
			var pala := _caja_mesh(helice, Vector3(0.1, 2.0, 0.25), Vector3(0, 1.0, 0), oscuro)
			var brazo := Node3D.new()
			helice.add_child(brazo)
			pala.reparent(brazo, false)
			brazo.rotation.x = k * PI / 2
		_helices.append(helice)
	for s in [-1.0, 1.0]:
		_caja_mesh(a, Vector3(3.0, 1.4, 1.0), Vector3(0.5, 0.9, s * 2.2), oscuro)
		_cil_mesh(a, 0.5, 0.4, Vector3(0.5, 0.5, s * 2.6), _mm(Color(0.08, 0.08, 0.08), 0.3, 0.8), Vector3(PI / 2, 0, 0), 12)
	_cil_mesh(a, 0.35, 0.3, Vector3(8.0, 0.5, 0), _mm(Color(0.08, 0.08, 0.08), 0.3, 0.8), Vector3(PI / 2, 0, 0), 12)
	var luz_r := _luz(a, Vector3(1.0, 5.1, -15.0), Color(1.0, 0.1, 0.05), 2.0, 5.0)
	var luz_v := _luz(a, Vector3(1.0, 5.1, 15.0), Color(0.1, 1.0, 0.2), 2.0, 5.0)
	luz_r.name = "LuzRoja"
	luz_v.name = "LuzVerde"
	var foco := SpotLight3D.new()
	foco.light_energy = 8.0
	foco.spot_range = 90.0
	foco.spot_angle = 20.0
	foco.shadow_enabled = false
	a.add_child(foco)
	foco.position = Vector3(12.0, 1.8, 0)
	foco.rotation = Vector3(0, -PI / 2, 0)
	_texto3d("FUERZA AÉREA", Vector3(-2.0, 3.2, 2.02), Color(0.9, 0.9, 0.9), 70, false, a)
	# la rampa de cola (se baja al aterrizar)
	_rampa = Node3D.new()
	a.add_child(_rampa)
	_rampa.position = Vector3(-10.0, 1.0, 0)
	_caja_mesh(_rampa, Vector3(4.0, 0.25, 3.4), Vector3(-2.0, 0, 0), oscuro)
	return a


func _montar_avion() -> void:
	var c := _c("p11_avion")
	if c.is_empty():
		return
	_avion = _modelo_avion()
	_avion.name = "Avion"
	add_child(_avion)
	_avion.visible = false
	_avion.global_position = Vector3(-300, 60, 150)


func _helices_tick(dt: float) -> void:
	for h in _helices:
		if is_instance_valid(h) and (_avion.visible if is_instance_valid(_avion) else false):
			(h as Node3D).rotation.x += dt * 38.0


## El avion en tierra, aparcado mirando al oeste con la rampa bajada: su bodega se pisa
func _avion_aparcado() -> void:
	var c := _c("p11_avion")
	var pa: Array = c["para"]
	var y := float(c.get("y", 3.0))
	_avion.visible = true
	_avion.global_position = Vector3(float(pa[0]), y, float(pa[1]))
	_avion.rotation = Vector3(0, PI, 0)
	if is_instance_valid(_rampa):
		_rampa.rotation.z = 0.28
	if not is_instance_valid(_avion_cuerpos):
		_avion_cuerpos = StaticBody3D.new()
		_avion_cuerpos.collision_layer = 1
		_avion.add_child(_avion_cuerpos)
		_colision_caja(_avion_cuerpos, Vector3(21.0, 0.3, 3.6), Vector3(0, 1.05, 0))          # el suelo de la bodega
		for s in [-1.0, 1.0]:
			_colision_caja(_avion_cuerpos, Vector3(21.0, 3.5, 0.3), Vector3(0, 2.7, s * 1.95))
		_colision_caja(_avion_cuerpos, Vector3(21.0, 0.3, 4.0), Vector3(0, 4.45, 0))
		_colision_caja(_avion_cuerpos, Vector3(0.3, 3.5, 4.0), Vector3(10.2, 2.7, 0))
		# la rampa (una cuña hasta el suelo)
		var r := CollisionShape3D.new()
		var rs := BoxShape3D.new()
		rs.size = Vector3(4.2, 0.25, 3.4)
		r.shape = rs
		r.position = Vector3(-12.0, 0.55, 0)
		r.rotation.z = 0.26
		_avion_cuerpos.add_child(r)
	if _avion_ruido == null:
		_avion_ruido = _bucle_directo("res://sounds/gen/avion/motor1.ogg", _avion, Vector3(2, 4, 0), 4.0, 250.0)


func _en_avion(p: Vector3) -> bool:
	if not is_instance_valid(_avion) or not _avion.visible:
		return false
	var local := _avion.global_transform.affine_inverse() * p
	return local.x > -11.0 and local.x < 9.5 and absf(local.z) < 1.9 and local.y > 0.7 and local.y < 4.2


## EL ATERRIZAJE (escena para todos): baja por el oeste, toca, rueda, se para, da la vuelta... y un helicoptero
## en llamas cae en mitad de la pista
func _p11_aterrizaje(ya: bool) -> void:
	var c := _c("p11_avion")
	var pa: Array = c["para"]
	var y := float(c.get("y", 3.0))
	var hp: Array = c["heli"]
	if ya:
		_avion_aparcado()
		_heli_estrellado(Vector3(float(hp[0]), y, float(hp[1])), true)
		return
	_avion.visible = true
	_avion.rotation = Vector3(0, 0, 0)
	var dest := Vector3(float(pa[0]), y, float(pa[1]))
	var toma := Vector3(24.0, y, dest.z)
	var inicio := Vector3(-120.0, y + 38.0, dest.z)
	_avion.global_position = inicio
	_avion_ruido = _bucle_directo("res://sounds/gen/avion/motor1.ogg", _avion, Vector3(2, 4, 0), 6.0, 300.0)
	var cam_p := _v(c.get("camara", [120, 12, 136]))
	_corte([[Vector3(50, 9, dest.z - 20), inicio + Vector3(40, -10, 0), 0.0],
		[Vector3(58, 6, dest.z - 16), toma + Vector3(10, 2, 0), 4.5],
		[cam_p, dest + Vector3(-20, 3, 0), 9.0],
		[cam_p + Vector3(-6, 2, 4), Vector3(float(hp[0]), y + 2.0, float(hp[1])), 14.0]], 14.0, "")
	var tw := create_tween()
	tw.tween_property(_avion, "global_position", toma, 4.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_avion, "rotation:z", 0.08, 4.8)
	tw.tween_callback(func():
		_avion.rotation.z = 0.0
		Audio.play3d("gen/tanque/torreta", _avion.global_position, 6.0, 0.0, 120.0, Audio.PRI_HIGH)
		var fx = jugador.get("effects") if is_instance_valid(jugador) else null
		if fx and fx.has_method("dust"):
			fx.dust(_avion.global_position, 1.5))
	tw.tween_property(_avion, "global_position", dest + Vector3(-6.0, 0, 0), 4.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_avion, "rotation:y", PI, 2.2).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(_avion, "global_position", dest, 2.2)
	tw.tween_callback(func():
		if is_instance_valid(_rampa):
			_rampa.create_tween().tween_property(_rampa, "rotation:z", 0.28, 1.5)
		_avion_aparcado())
	# el helicoptero: cae ardiendo del cielo a los 9 s
	get_tree().create_timer(9.0).timeout.connect(func(): _heli_estrellado(Vector3(float(hp[0]), y, float(hp[1])), false))
	_mensaje_local("¡EL AVIÓN ESTÁ AQUÍ!")


func _heli_estrellado(p: Vector3, ya: bool) -> void:
	if is_instance_valid(_heli_caido):
		return
	var h := _modelo_heli()
	add_child(h)
	_heli_rotor = null
	for ch in h.get_children():
		if ch is AudioStreamPlayer3D:
			(ch as AudioStreamPlayer3D).queue_free()
		if ch is SpotLight3D:
			(ch as SpotLight3D).visible = false
	_heli_caido = h
	var reposo := p + Vector3(0, 1.3, 0)
	var fuego := _particulas(h, Vector3(0, 0.8, 0), 34, 1.0, Color(1.0, 0.8, 0.35, 0.95), Color(0.7, 0.12, 0.02), 1.4, true)
	fuego.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fuego.emission_box_extents = Vector3(2.5, 0.6, 1.0)
	fuego.direction = Vector3.UP
	fuego.gravity = Vector3(0, 3.0, 0)
	fuego.initial_velocity_min = 0.6
	fuego.initial_velocity_max = 2.0
	fuego.local_coords = false
	_luz(h, Vector3(0, 2.0, 0), Color(1.0, 0.5, 0.2), 3.0, 16.0)
	if ya:
		h.global_position = reposo
		h.rotation = Vector3(0.3, 0.8, 0.5)
		return
	h.global_position = p + Vector3(-40.0, 30.0, 20.0)
	h.rotation = Vector3(0.2, 1.2, 0.4)
	var tw := h.create_tween()
	tw.tween_property(h, "global_position", reposo, 2.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(h, "rotation", Vector3(0.3, 0.8 + TAU, 0.5), 2.4)
	tw.tween_callback(func():
		_explosion(reposo, 4.5, 60.0, 0.0)
		_golpe(reposo, 2.0, "destru/metal"))
	Audio.play2d("l4d2/heli/pasa", 0.0, 0.0, Audio.PRI_HIGH)


func _p11_resuelto(ya: bool) -> void:
	if not ya:
		_mensaje_local("PILOTO: «¡Hay un helicóptero ardiendo en la pista! ¡Quitadlo o no despego! ¡Volad el CAMIÓN CISTERNA!»")
		Audio.bf2d("amb/radio", 0.0, Audio.PRI_HIGH)


# ======================================================================================================
# 12. EL CAMION CISTERNA
# ======================================================================================================
func _montar_p12() -> void:
	var c := _c("p12_camion")
	if c.is_empty():
		return
	var cr: Array = c["camion"]
	_camion_vida = float(c.get("vida", 900.0))
	var d := _diana("camion", Vector3((float(cr[0]) + float(cr[2])) / 2 - 0.8, 4.9, (float(cr[1]) + float(cr[3])) / 2),
		Vector3(float(cr[2]) - float(cr[0]) - 1.8, 2.2, float(cr[3]) - float(cr[1])))
	_rotulo("camion", "CAMIÓN CISTERNA · ¡volad el helicóptero de la pista!", Vector3((float(cr[0]) + float(cr[2])) / 2, 8.0, (float(cr[1]) + float(cr[3])) / 2), COLOR_PELIGRO)


func _p12_resuelto(ya: bool) -> void:
	_quitar_cartel("camion")
	var c := _c("p12_camion")
	var cr: Array = c["camion"]
	var p := Vector3((float(cr[0]) + float(cr[2])) / 2, 4.5, (float(cr[1]) + float(cr[3])) / 2)
	if _dianas.has("camion"):
		(_dianas["camion"] as Node).queue_free()
		_dianas.erase("camion")
	var fuera := Vector3(p.x + 8.0, 3.8, 158.2)
	if ya:
		if is_instance_valid(_heli_caido):
			_heli_caido.global_position = fuera
		return
	_explosion(p, 5.5, 160.0, 3.2)
	get_tree().create_timer(0.25).timeout.connect(func(): _explosion(p + Vector3(2.0, 0.5, 0.5), 3.5, 60.0, 0.0))
	_bola_de_fuego(p)
	if is_instance_valid(_heli_caido):
		var tw := _heli_caido.create_tween()
		tw.tween_property(_heli_caido, "global_position", fuera + Vector3(0, 3.0, 0), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(_heli_caido, "rotation", _heli_caido.rotation + Vector3(1.2, 2.0, 2.6), 1.2)
		tw.tween_property(_heli_caido, "global_position", fuera, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func(): _golpe(fuera, 1.6, "destru/metal"))
	_mensaje_local("¡¡EL CAMIÓN HA REVENTADO!! La pista está libre: ¡TODOS AL AVIÓN!")


# ======================================================================================================
# AL EMPEZAR
# ======================================================================================================
func _al_empezar() -> void:
	Audio.bf2d("amb/radio", -4.0, Audio.PRI_MID)
	_mensaje_local("RADIO: «Aquí base aérea. Hemos volado la vía: no entra nada infectado. Si estáis vivos, venid A PIE»")
	if not _soy_host:
		Net.net_campana_pide("estado4")
	elif _en_red:
		_mandar_estado()
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--ir="):
			_ir_a(String(a).substr(5).replace("_", " "))
	if "--base5test" in OS.get_cmdline_user_args():
		_prueba_final5()


## --base5test (con --ir=pista): el final entero sin jugar (las luces, el aterrizaje, el camion, el avion y el despegue)
func _prueba_final5() -> void:
	await get_tree().create_timer(2.0).timeout
	for i in 3:
		_evento("p10_tramo", [i])
	print("[base5test] luces de pista encendidas · fase %s" % fase)
	await get_tree().create_timer(24.0).timeout
	print("[base5test] tras el aterrizaje · fase %s · avion visible %s" % [fase, str(_avion.visible if is_instance_valid(_avion) else false)])
	_diana_host("camion", 5000.0)
	await get_tree().create_timer(3.0).timeout
	print("[base5test] camion · p12 %s · fase %s" % [str(_h("p12")), fase])
	if is_instance_valid(jugador) and is_instance_valid(_avion):
		jugador.global_position = _avion.global_transform * Vector3(-4.0, 1.3, 0.0)
	for b in get_tree().get_nodes_in_group("aliados_pve"):
		if is_instance_valid(b):
			(b as Node3D).global_position = _avion.global_transform * Vector3(-6.0, 1.3, 0.5)
	await get_tree().create_timer(4.0).timeout
	print("[base5test] a bordo: %s · fase %s · terminado %s" % [str(_en_avion(jugador.global_position)), fase, str(terminado)])
	await get_tree().create_timer(16.0).timeout
	print("[base5test] fin · cine hecha %s" % str(_cine_final_hecha))
	get_tree().quit()


func _ir_a(nombre: String) -> void:
	var i := _indice_de(nombre)
	if i >= ruta.size() or not _soy_host:
		return
	var orden := [["p01", "refineria"], ["p02", "puente"], ["p03", "patio"], ["p05", "escombros"],
		["p06", "minas"], ["p08", "hangar"], ["p09", "pista"]]
	for par_o in orden:
		if i >= _indice_de(String(par_o[1])):
			_evento(String(par_o[0]), [])
	progreso = i
	await get_tree().create_timer(0.5).timeout
	if is_instance_valid(jugador):
		jugador.global_position = ruta[i] + Vector3.UP * 0.4
	for b in get_tree().get_nodes_in_group("aliados_pve"):
		if is_instance_valid(b) and b.has_method("teletransportar_a"):
			b.teletransportar_a(jugador)
	fase = _fase_por_hecho5()
	print("[campana5] --ir=%s: fase %s" % [nombre, fase])


func _fase_por_hecho5() -> String:
	for k in ["p01", "p02", "p03"]:
		if not _h(k):
			return k
	if progreso < _indice_de("salida del colector"):
		return "p04"
	if not _h("p05"):
		return "p05"
	if progreso < _indice_de("refugio"):
		return "camino_refugio"
	for k in ["p06"]:
		if not _h(k):
			return k
	if progreso < _indice_de("tanque"):
		return "p07"
	for k in ["p08", "p09", "p10", "p11", "p12"]:
		if not _h(k):
			return k
	return "subir"


# ======================================================================================================
# CADA CUADRO
# ======================================================================================================
func _process_sin_medir(dt: float) -> void:
	super._process_sin_medir(dt)
	_rotulos_tick(dt)
	_tren_tick(dt)
	_ambiente_tick(dt)
	_nube_tick(dt)
	_verja_tick(dt)
	_baliza_tick(dt)
	_minas_tick(dt)
	_laser_tick()
	_radar_tick(dt)
	_pista_tick(dt)
	_helices_tick(dt)
	_aire_tick(dt)
	if (_en_red and not _soy_host) or terminado or world == null:
		return
	_mortero_cd -= dt
	_tanque_cd -= dt
	_final_tick5(dt)
	_bots_t -= dt
	if _bots_t <= 0.0:
		_bots_t = 2.0
		_bots_al_dia()
	_comprobar_t5 -= dt
	if _comprobar_t5 > 0.0:
		return
	_comprobar_t5 = 0.3
	# el campo de minas se da por cruzado al llegar al tanque
	if fase == "p07" and progreso >= _indice_de("tanque"):
		hecho["p07"] = true
		_mensaje("¡CAMPO DE MINAS CRUZADO! El TANQUE: su cañón contra la PUERTA BLINDADA")


func _final_tick5(dt: float) -> void:
	if fase == "p12" or fase == "subir":
		_tanda_final5 -= dt
		if _tanda_final5 <= 0.0:
			_tanda_final5 = 11.0
			if _cola.size() < 8:
				_horda(9, "")
		if not _final_tank5:
			_final_tank5 = true
			_cola.push_front("tanque")
			_mensaje("¡UN TANK EN LA PISTA!")


# ======================================================================================================
# LA HISTORIA (el anfitrion)
# ======================================================================================================
const TEXTOS5 := {
	"p01": "LA VÍA ESTÁ VOLADA · usad el MORTERO del montículo contra la CASA DE BOMBAS",
	"p02": "LA REFINERÍA · abrid la VÁLVULA de la ESFERA y, cuando el gas llegue a la FUGA, disparadle desde lejos",
	"p03": "EL CANAL · cruzad el PUENTE y abrid la VERJA (tarda 40 s): si la horda cruza, VOLAD EL PUENTE",
	"p04": "EL COLECTOR INUNDADO · bajad al pozo y bucead; se respira en los POZOS DE REGISTRO",
	"p05": "LA OBRA · reconectad los 4 EMPALMES y hundid el DETONADOR del búnker",
	"camino_refugio": "¡El muro de la base ha caído! Al REFUGIO: la caseta de guardia",
	"p06": "LA VERJA INTERIOR · el código lo parpadea la BALIZA roja del mástil",
	"p07": "EL CAMPO DE MINAS · reventadlas a tiros y cruzad hasta el TANQUE",
	"p08": "EL TANQUE · girad la torreta y disparad a la PUERTA BLINDADA del hangar (3 cañonazos)",
	"p09": "LA TORRE DE CONTROL · subid al RADAR y girad la antena hasta que pite seguida",
	"p10": "LAS LUCES DE LA PISTA · quedaos junto a cada CUADRO hasta que se encienda su tramo",
	"p11": "EL AVIÓN LLEGA…",
	"p12": "¡UN HELICÓPTERO EN LA PISTA! Volad el CAMIÓN CISTERNA para echarlo",
	"subir": "¡TODOS AL AVIÓN! Subid por la rampa de cola",
}


func _historia() -> void:
	match fase:
		"inicio":
			_poner_fase("p01", TEXTOS5["p01"])
		"p01", "p02":
			if _h(fase):
				var s := "p02" if fase == "p01" else "p03"
				_poner_fase(s, TEXTOS5[s])
		"p03":
			if _h("p03"):
				_poner_fase("p04", TEXTOS5["p04"])
		"p04":
			if progreso >= _indice_de("salida del colector"):
				_poner_fase("p05", TEXTOS5["p05"])
		"p05":
			if _h("p05"):
				_poner_fase("camino_refugio", TEXTOS5["camino_refugio"])
				_horda(HORDA_TAM, "¡LA DEMOLICIÓN HA DESPERTADO A TODO EL MUNDO!")
			else:
				var n := 0
				for e in _empalmes:
					if bool(e):
						n += 1
				_texto = "%s · %d de 4" % [TEXTOS5["p05"], n]
		"camino_refugio":
			var ref: Dictionary = _c("refugio")
			if not ref.is_empty() and _todos_dentro(ref["rect"], float(ref.get("suelo", 0.0)) - 1.0):
				_poner_fase("refugio", "")
				_llegar_al_refugio()
		"refugio":
			if progreso >= _indice_de("verja interior"):
				_poner_fase("p06", TEXTOS5["p06"])
		"p06":
			if _h("p06"):
				_poner_fase("p07", TEXTOS5["p07"])
		"p07":
			if _h("p07"):
				_poner_fase("p08", TEXTOS5["p08"])
		"p08":
			if _h("p08"):
				_poner_fase("p09", TEXTOS5["p09"])
			else:
				_texto = "%s · %d de %d" % [TEXTOS5["p08"], _blindada_golpes, int(_c("p08_tanque").get("golpes", 3))]
		"p09":
			if _h("p09"):
				_poner_fase("p10", TEXTOS5["p10"])
		"p10":
			if _h("p10"):
				_poner_fase("p11", TEXTOS5["p11"])
		"p11":
			if _h("p11"):
				_poner_fase("p12", TEXTOS5["p12"])
				_tanda_final5 = 4.0
		"p12":
			if _h("p12"):
				_poner_fase("subir", TEXTOS5["subir"])
			else:
				_texto = "%s · %d %%" % [TEXTOS5["p12"], int(100.0 - _camion_vida / float(_c("p12_camion").get("vida", 900.0)) * 100.0)]
		"subir":
			var vivos := _jugadores_vivos()
			var dentro := 0
			for pl in vivos:
				if _en_avion((pl as Node3D).global_position):
					dentro += 1
			_texto = "¡TODOS AL AVIÓN! · %d de %d a bordo" % [dentro, vivos.size()]
			if dentro == vivos.size() and vivos.size() > 0:
				terminado = true
				_poner_fase("fin", "")
				_evento("escapan", [])
				_mensaje("¡HABÉIS ESCAPADO!")
				_objetivo("VICTORIA · %d bajas" % bajas)
				if _en_red:
					Net.net_fin_pve(true, FINAL.size(), bajas, puntos)
				get_tree().create_timer(3.0).timeout.connect(func(): _fin(true))


func _llegar_al_refugio() -> void:
	super._llegar_al_refugio()
	_texto = "REFUGIO · vida y munición repuestas · la puerta OESTE se abre en 10 s"
	_objetivo(_texto)


func _objetivo_punto() -> Array:
	var sig := func(tope: String) -> Vector3:
		var i := mini(progreso + 1, _indice_de(tope))
		return ruta[clampi(i, 0, ruta.size() - 1)]
	match fase:
		"inicio", "p01":
			return [_v(_c("p01_mortero").get("pos", [0, 0, 0])), "MORTERO"]
		"p02":
			if _nube_t < 0.0:
				return [_v(_c("p02_esfera").get("valvula", [0, 0, 0])), "VÁLVULA DE LA ESFERA"]
			return [_v(_c("p02_esfera").get("fuga", [0, 0, 0])), "FUGA · ¡DISPARAD DESDE LEJOS!" if _gas_listo() else "EL GAS SE EXTIENDE…"]
		"p03":
			if _verja_t < 0.0:
				return [_v(_c("p03_puente").get("mando", [0, 0, 0])), "MANDO DE LA VERJA"]
			if not _puente_caido:
				return [_v(_c("p03_puente")["anclajes"][0]), "ANCLAJES DEL PUENTE"]
			return [_v(_c("p03_puente").get("mando", [0, 0, 0])), "VERJA · AGUANTAD"]
		"p04":
			return [sig.call("salida del colector"), "COLECTOR"]
		"p05":
			for i in _empalmes.size():
				if not bool(_empalmes[i]):
					return [_v(_c("p05_demolicion")["empalmes"][i]), "EMPALME %d" % (i + 1)]
			return [_v(_c("p05_demolicion").get("detonador", [0, 0, 0])), "DETONADOR"]
		"camino_refugio":
			return [sig.call("refugio"), "REFUGIO"]
		"refugio":
			var ps = _c("refugio").get("puerta_salida", null)
			return [_v([ps[0], 3.0, ps[1]]) if ps != null else ruta[progreso], "SALIDA DEL REFUGIO"]
		"p06":
			return [_v(_c("p06_baliza").get("teclado", [0, 0, 0])), "TECLADO DE LA VERJA"]
		"p07":
			return [ruta[_indice_de("tanque")], "TANQUE"]
		"p08":
			return [_v(_c("p08_tanque").get("pos", [0, 0, 0])), "TANQUE"]
		"p09":
			return [_v(_c("p09_radar").get("pos", [0, 0, 0])), "RADAR"]
		"p10":
			for i in 3:
				if not bool(_cuadros_hechos[i]):
					return [_v(_c("p10_pista")["cuadros"][i]), "CUADRO DE PISTA %d" % (i + 1)]
		"p12":
			var cr: Array = _c("p12_camion")["camion"]
			return [Vector3((float(cr[0]) + float(cr[2])) / 2, 4.0, (float(cr[1]) + float(cr[3])) / 2), "CAMIÓN CISTERNA"]
		"subir":
			if is_instance_valid(_avion):
				return [_avion.global_transform * Vector3(-12.5, 0.5, 0), "¡AL AVIÓN!"]
	return [Vector3.INF, ""]


func _tope_ruta() -> int:
	var cierres := [["p01", "casa de bombas"], ["p02", "muro sur"], ["p03", "verja"], ["p05", "escombros"],
		["p06", "verja interior"], ["p08", "tanque"]]
	for c in cierres:
		if not _h(String(c[0])):
			return _indice_de(String(c[1]))
	return 999


# ======================================================================================================
# LO QUE SE USA
# ======================================================================================================
func _usables_extra(_f: String) -> void:
	if terminado:
		return
	var jp: Vector3 = jugador.global_position if is_instance_valid(jugador) else Vector3.ZERO
	# (cada usable, encima de su mando: las teclas de las consolas, el volante, la palanca, los cuadros)
	# 1 el mortero
	if not _h("p01"):
		var mp := _v(_c("p01_mortero")["pos"])
		_u("p01_izq", _en_mando("p01_izq", mp + Vector3(-0.7, 1.0, -0.8)), "GIRAR EL MORTERO ◀ (5°)", 2.4)
		_u("p01_der", _en_mando("p01_der", mp + Vector3(0.7, 1.0, -0.8)), "GIRAR EL MORTERO ▶ (5°)", 2.4)
		_u("p01_carga", _en_mando("p01_carga", mp + Vector3(-2.1, 0.6, 1.0)), "CAMBIAR LA CARGA (ahora %d)" % _mortero_carga, 2.4)
		_u("p01_fuego", _en_mando("p01_fuego", mp + Vector3(0.6, 0.9, 1.0), 0.14), "¡FUEGO!", 2.4)
	# 2 la valvula
	if _h("p01") and not _h("p02") and _nube_t < 0.0:
		_u("p02_valvula", _en_mando("p02_valvula", _v(_c("p02_esfera")["valvula"]) + Vector3(0, 1.1, 0), 0.2), "ABRIR LA VÁLVULA DE ALIVIO (sale gas)")
	# 3 el mando de la verja
	if _h("p02") and not _h("p03") and _verja_t < 0.0:
		_u("p03_mando", _en_mando("p03_mando", _v(_c("p03_puente")["mando"]) + Vector3(0, 1.2, 0), 0.12), "ABRIR LA VERJA (tarda 40 s: vendrá la horda)")
	# 5 los empalmes y el detonador
	if _h("p03") and not _h("p05"):
		var em: Array = _c("p05_demolicion")["empalmes"]
		for i in em.size():
			if not bool(_empalmes[i]):
				_u("p05_e%d" % i, _en_mando("p05_e%d" % i, _v(em[i]) + Vector3(0, 1.1, 0), 0.18), "RECONECTAR EL EMPALME %d" % (i + 1))
		_u("p05_det", _v(_c("p05_demolicion")["detonador"]) + Vector3(0, 0.9, 0), "HUNDIR EL DETONADOR")
	# 6 el teclado
	if _h("p05") and not _h("p06"):
		var nombres := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "BORRAR", "ABRIR"]
		for k in nombres.size():
			_u("p06_k%d" % k, _tecla_pos(k), "TECLA %s" % nombres[k], 2.0)
	# 8 el tanque
	if _h("p06") and (not _h("p08") or fase == "p12"):
		var tp := _v(_c("p08_tanque")["pos"])
		if tp.distance_to(jp) < 6.0:
			_u("p08_izq", _en_mando("p08_izq", tp + Vector3(-1.2, 1.6, 1.9)), "TORRETA ◀ (15°)", 2.8)
			_u("p08_der", _en_mando("p08_der", tp + Vector3(1.2, 1.6, 1.9)), "TORRETA ▶ (15°)", 2.8)
			_u("p08_fuego", _en_mando("p08_fuego", tp + Vector3(0, 2.2, 1.9), 0.14), "¡FUEGO! (cañón)", 2.8)
	# 9 el radar
	if _h("p08") and not _h("p09"):
		var rp := _v(_c("p09_radar")["pos"])
		_u("p09_izq", _en_mando("p09_izq", rp + Vector3(-1.0, 1.2, -1.6)), "GIRAR LA ANTENA ◀ (10°)", 2.8)
		_u("p09_der", _en_mando("p09_der", rp + Vector3(1.0, 1.2, -1.6)), "GIRAR LA ANTENA ▶ (10°)", 2.8)


func _pide_extra(accion: String) -> void:
	if accion.begins_with("diana:"):
		var partes := accion.split(":")
		if partes.size() < 3:
			return
		_diana_host(partes[1], float(partes[2]))
		return
	if accion.begins_with("p05_e"):
		var i := int(accion.substr(5))
		if not bool(_empalmes[i]):
			_evento("p05_empalme", [i])
		return
	if accion.begins_with("p06_k"):
		var k := int(accion.substr(5))
		if k <= 8:
			if _tecleado.length() < 3:
				_tecleado += str(k + 1)
		elif k == 9:
			_tecleado = ""
		else:
			var cif: Array = par.get("cifras", [])
			var buena := "%d%d%d" % [int(cif[0]), int(cif[1]), int(cif[2])] if cif.size() >= 3 else "???"
			if _tecleado == buena:
				_evento("p06", [])
				return
			_tecleado = ""
			_evento("p06_error", [])
			return
		_evento("p06_teclas", [_tecleado])
		return
	match accion:
		"p01_izq", "p01_der":
			_mortero_ang += -5.0 if accion == "p01_izq" else 5.0
			_evento("p01_apunta", [_mortero_ang, _mortero_carga, accion])      # (la tecla: se hunde en todas)
		"p01_carga":
			_mortero_carga = _mortero_carga % 4 + 1
			_evento("p01_apunta", [_mortero_ang, _mortero_carga, accion])
		"p01_fuego":
			if _mortero_cd <= 0.0 and not _h("p01"):
				_mortero_cd = 3.2
				_mortero_disparo()
		"p02_valvula":
			if _nube_t < 0.0:
				_evento("p02_valvula", [])
		"p03_mando":
			if _verja_t < 0.0:
				_evento("p03_mando", [])
				_horda(HORDA_TAM, "¡LA VERJA HACE RUIDO! ¡LA HORDA VIENE POR EL PUENTE!")
				_tanda_puente_t = 6.0
		"p05_det":
			if _h("p05"):
				return
			if _empalmes.has(false):
				var n := 0
				for e in _empalmes:
					if bool(e):
						n += 1
				_mensaje("EL DETONADOR NO TIENE LÍNEA · faltan %d EMPALMES" % (4 - n))
				return
			_evento("p05", [])
		"p08_izq", "p08_der":
			_tanque_ang += -15.0 if accion == "p08_izq" else 15.0
			_evento("p08_gira", [_tanque_ang, accion])
		"p08_fuego":
			if _tanque_cd <= 0.0:
				_tanque_cd = 3.0
				_tanque_disparo()
		"p09_izq", "p09_der":
			_radar_ang = fposmod(_radar_ang + (10.0 if accion == "p09_izq" else -10.0), 360.0)
			_evento("p09_gira", [_radar_ang, accion])
			if _senal() > 0.985:
				get_tree().create_timer(1.0).timeout.connect(func(): _evento("p09", []))


## El anfitrion decide que pasa cuando le dan a una diana
func _diana_host(id: String, dano: float) -> void:
	if id == "fuga":
		if _h("p02"):
			return
		if _gas_listo():
			_evento("p02", [])
			_horda(HORDA_TAM, "")
		elif _nube_t < 0.0:
			_mensaje("La fuga está cerrada: NO HAY GAS · abrid antes la VÁLVULA de la esfera")
	elif id.begins_with("anclaje"):
		var i := int(id.substr(7))
		if not bool(_anclajes_rotos[i]):
			_evento("p03_anclaje", [i])
	elif id.begins_with("mina"):
		_mina_salta(int(id.substr(4)))
	elif id == "camion":
		if fase != "p12" or _h("p12"):
			return
		_camion_vida -= dano
		if _camion_vida <= 0.0:
			_evento("p12", [])


func _evento_extra(e: String, datos: Array) -> void:
	match e:
		"fase4":
			if not _soy_host:
				fase = String(datos[0])
		"estado4":
			_aplicar_estado(String(datos[0]))
		"p01_apunta":
			_mortero_ang = float(datos[0])
			_mortero_carga = int(datos[1])
			_mortero_refrescar()
			if datos.size() > 2:
				_pulsar5(String(datos[2]))
			Audio.play3d("gen/dial/clic", _v(_c("p01_mortero")["pos"]) + Vector3.UP, 0.0, 0.05, 20.0, Audio.PRI_MID)
		"p01_disparo":
			_pulsar5("p01_fuego")
			_mortero_proyectil(Vector3(float(datos[0]), float(datos[1]), float(datos[2])), int(datos[3]) != 0)
		"p02_valvula":
			_p02_valvula()
		"p03_mando":
			_pulsar5("p03_mando", true)
			_verja_t = 0.0
			Audio.play3d("gen/ascensor/arranque", _v(_c("p03_puente")["mando"]), 2.0, 0.0, 60.0, Audio.PRI_HIGH)
			Audio.bf3d("modo/bomba_alarma", _v(_c("p03_puente")["mando"]) + Vector3.UP * 3.0, 4.0, 150.0, Audio.PRI_HIGH)
		"p03_anclaje":
			_anclaje_roto(int(datos[0]), false)
		"p05_empalme":
			_empalme(int(datos[0]))
		"p06_teclas":
			_tecleado = String(datos[0])
			_teclado_mostrar(_tecleado)
			Audio.play3d("gen/teclado/tecla", _tecla_pos(4), -2.0, 0.05, 15.0, Audio.PRI_MID)
		"p06_error":
			_tecleado = ""
			if is_instance_valid(_pantalla):
				_pantalla.text = "E R R"
			Audio.play3d("gen/teclado/error", _tecla_pos(4), 2.0, 0.0, 20.0, Audio.PRI_HIGH)
			_mensaje_local("CÓDIGO INCORRECTO · contad bien los destellos de la baliza")
		"p07_mina":
			_mina_explota(int(datos[0]))
		"p08_gira":
			_tanque_ang = float(datos[0])
			_torreta_refrescar(false)
			if datos.size() > 1:
				_pulsar5(String(datos[1]))
		"p08_disparo":
			_pulsar5("p08_fuego")
			_tanque_fuego(Vector3(float(datos[0]), float(datos[1]), float(datos[2])), int(datos[3]) != 0)
		"p09_gira":
			_radar_ang = float(datos[0])
			_antena_refrescar(false)
			if datos.size() > 1:
				_pulsar5(String(datos[1]))
		"p10_k":
			if not _soy_host:
				_cuadros_k = datos.duplicate()
		"p10_tramo":
			_tramo_pista(int(datos[0]), false)
		"p10":
			hecho["p10"] = true
			_p10_corte()
		"p11_empieza":
			_p11_aterrizaje(false)
			if _soy_host:
				get_tree().create_timer(14.5).timeout.connect(func(): _evento("p11", []))
		_:
			if e.length() == 3 and e.begins_with("p"):
				_resolver5(e, false)


# ======================================================================================================
# LA SALIDA DE CINE: el avion despega por la pista encendida y se mete en la tormenta
# ======================================================================================================
func _on_evento(e: String, datos: Array) -> void:
	super._on_evento(e, datos)
	if e == "escapan":
		_cine_final()


func _cine_final() -> void:
	if _cine_final_hecha or not is_instance_valid(_avion):
		_cine_final_hecha = true
		return
	_cine_final_corriendo = true
	if is_instance_valid(jugador):
		jugador.set_physics_process(false)
		jugador.set_process_unhandled_input(false)
		var av = jugador.get("avatar")
		if av != null:
			av.visible = false
		for n in ["weapon_pivot", "fp_arms"]:
			var nd = jugador.get(n)
			if nd != null and is_instance_valid(nd):
				nd.visible = false
	for r in Net.remotes.values():
		if is_instance_valid(r):
			(r as Node3D).visible = false
	for b in get_tree().get_nodes_in_group("aliados_pve"):
		if is_instance_valid(b):
			(b as Node3D).visible = false
	if _capa_equipo:
		_capa_equipo.visible = false
	var p0 := _avion.global_position
	var cam_p := _v(_c("cine_final").get("camara", [40.0, 9.0, 140.0]))
	var despegue := Vector3(-60.0, p0.y + 24.0, p0.z)
	var planos := [[cam_p, p0 + Vector3(0, 3, 0), 0.0], [cam_p + Vector3(-4, 1, 2), Vector3(30, 6, p0.z), 7.0],
		[cam_p + Vector3(-10, 4, 4), despegue, 13.0]]
	_corte(planos, 13.0, "")
	if hud:
		hud.visible = false
	if is_instance_valid(_rampa):
		_rampa.create_tween().tween_property(_rampa, "rotation:z", 0.0, 1.5)
	Audio.play3d("gen/avion/pasada", p0, 8.0, 0.0, 400.0, Audio.PRI_TOP)
	var tw := create_tween()
	tw.tween_interval(1.5)
	tw.tween_property(_avion, "global_position:x", 40.0, 6.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_avion, "global_position", despegue, 5.0).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(_avion, "rotation:z", 0.22, 2.0)
	var capa := CanvasLayer.new()
	capa.layer = 31
	add_child(capa)
	var titulo := Label.new()
	titulo.text = "EPISODIO 5 COMPLETADO"
	titulo.add_theme_font_size_override("font_size", 58)
	titulo.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	titulo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	titulo.add_theme_constant_override("shadow_offset_y", 3)
	titulo.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.grow_horizontal = Control.GROW_DIRECTION_BOTH
	titulo.modulate.a = 0.0
	capa.add_child(titulo)
	var sub := Label.new()
	sub.text = "…y la base se queda atrás, ardiendo bajo la tormenta"
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(0.92, 0.9, 0.84))
	sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sub.position.y += 56.0
	sub.modulate.a = 0.0
	capa.add_child(sub)
	var negro := ColorRect.new()
	negro.color = Color(0, 0, 0, 0)
	negro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	capa.add_child(negro)
	var tt := create_tween()
	tt.tween_interval(8.5)
	tt.tween_property(titulo, "modulate:a", 1.0, 1.4)
	tt.parallel().tween_property(sub, "modulate:a", 1.0, 2.0)
	tt.tween_interval(3.0)
	tt.tween_property(negro, "color:a", 1.0, 1.6)
	tt.tween_callback(func():
		_cine_final_hecha = true
		_cine_final_corriendo = false)
