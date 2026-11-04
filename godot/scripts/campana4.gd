extends "res://scripts/campana_kit.gd"
## EPISODIO 4 DE LA CAMPAÑA: "LA PRESA" (campana_presa, tools/generar_mapa_campana4.py). 2026-09-28.
##
## Al helicoptero del episodio 3 se le acaba el combustible y aterriza AL ATARDECER en la cantera de un embalse.
## Abajo, en el valle, sale el ULTIMO TREN. Se baja por la coronacion de la presa, por DENTRO de ella, por la
## central, por el canal de desague, se cruza el rio en barcaza, el pueblo, la serreria y la estacion.
## VEINTE PUZZLES, todos distintos (el mapa y su orden, en tools/mapa_campana4/disposicion.py):
##    1 LA VAGONETA          reventar el calzo: baja por la via y revienta la barricada
##    2 LAS DOS PALANCAS     una en cada garita, a la vez (5 s)
##    3 EL CAMION EN LLAMAS  la llave general de bombeo y luego la boca de incendios
##    4 LA CUERDA Y LA PLACA la puerta solo se abre con peso: el pale de sacos cae sobre la placa (Portal)
##    5 EL CUADRO DE LUCES   cuatro interruptores que cambian tambien los de al lado: todas encendidas
##    6 EL PASILLO DE VAPOR  pasar entre chorros y cerrar la llave del final
##    7 LAS VALVULAS         tres ruedas de colores en el orden de la pizarra (un acertijo)
##    8 LA ESCLUSA           todos dentro; se cierra una compuerta y solo entonces se abre la otra
##    9 LAS TUBERIAS         girar codos hasta que el agua llega: las bombas vacian el pozo
##   10 EL PUENTE GRUA       saca el rodete que tapa el desague
##   11 LA BOMBONA           a cuestas hasta el derrumbe, mecha, y correr
##   12 LA VALLA ELECTRICA   reventar los tres aisladores del transformador
##   13 LA BARCAZA          dos manivelas: hay que quedarse girando con la horda encima
##   14 LA LLAVE            en una de cuatro casas (cada partida en otra)
##   15 LA TIROLINA         tensar el cable con el torno y bajar volando sobre el barranco
##   16 LAS PASARELAS       suben unos segundos: cruzar corriendo y bloquearlas desde el otro lado
##   17 LA BOLA             tres golpes de la grua de demolicion abren el muro de la estacion
##   18 LA COMBINACION      ANDEN, RELOJ y VAGON dan las tres cifras de la oficina
##   19 LAS AGUJAS          el vagon a la via muerta y la aguja otra vez a la via 1
##   20 EL GASOIL           seis bidones a cuestas hasta la locomotora, arrancarla y aguantar. Y el tren se va.
##
## Lo que se mueve son OBJETOS (iguales en todas las pantallas); lo que se rompe, voxels. Todo lo decide el
## anfitrion y lo cuenta con eventos; quien entra tarde pide "estado4" y lo recibe entero. Lo sorteado (el orden
## de las valvulas, las tuberias, la casa de la llave, las cifras) tambien lo sortea el anfitrion.

const COLOR_VALV := [Color(0.85, 0.10, 0.07), Color(0.12, 0.34, 0.92), Color(0.98, 0.80, 0.10)]
const ACERTIJO := ["la del color de la SANGRE", "la del color del CIELO", "la del color del SOL"]
const AGUA_RIO := 1.2

var _comprobar_t := 0.0
var _red_t4 := 0.0
var _heli_quieto: Node3D = null

# --- 1 la vagoneta ---
var _vag: AnimatableBody3D = null
var _vag_s := -1.0                  ## metros recorridos por la via (-1 = calzada)
var _vag_v := 0.0
var _vag_largo := 0.0
var _vag_barricada := false
var _vag_al_agua := false
# --- 2 las palancas ---
var _p02_t := [-100.0, -100.0]
var _p02_palancas: Array = []       ## [Node3D (el mango)]
var _p02_luces: Array = []
var _p02_puerta: StaticBody3D = null
var _p02_barrera := AABB()
# --- 3 el fuego ---
var _fuego_nodo: Node3D = null
var _fuego_cuerpo: StaticBody3D = null
var _fuego_parts: Array = []
var _fuego_luz: OmniLight3D = null
var _fuego_ruido: AudioStreamPlayer3D = null
var _fuego_barrera := AABB()
var _fuego_vivo := true
var _p03_presion := false
# --- 4 la placa ---
var _p04_puerta: StaticBody3D = null
var _p04_pale: StaticBody3D = null
var _p04_cuerdas: Array = []
var _p04_placa_nodo: Node3D = null
var _p04_pisada := false
var _p04_barrera := AABB()
var _p04_puerta_y0 := 0.0
# --- 5 el cuadro ---
var _luces: Array = [false, false, false, false]
var _p05_lamparas: Array = []
var _p05_mangos: Array = []
var _p05_reja: StaticBody3D = null
var _p05_barrera := AABB()
var _galeria_luces: Array = []
# --- 6 el vapor ---
var _chorros: Array = []            ## [{parts, x, audio}]
var _vapor_t := 0.0
var _vapor_on := true
# --- 7 las valvulas ---
var _valv_nodos: Array = []         ## [Node3D (la rueda)]
var _valv_luces: Array = []
var _valv_paso := 0
var _p07_compuerta: StaticBody3D = null
var _p07_barrera := AABB()
var _pizarra: Array = []            ## [Label3D]
# --- 8 la esclusa ---
var _p08_a: StaticBody3D = null
var _p08_b: StaticBody3D = null
var _p08_barrera := AABB()
var _p08_estado := 0                ## 0 abierta A, 1 cerrando, 2 abierta B
# --- 9 las tuberias ---
var _tubos_rot: Array = []
var _tubos_nodos: Array = []        ## [Node3D (los brazos de cada pieza)]
var _pozo_agua_y := 5.4
var _pozo_vaciando := false
# --- 10 la grua ---
var _grua_puente: Node3D = null
var _grua_carro: Node3D = null
var _grua_gancho: Node3D = null
var _grua_cables: Array = []
var _rotor: StaticBody3D = null
var _grua_ocupada := false
var _grua_ruido: AudioStreamPlayer3D = null
# --- 11 / 20 lo que se lleva a cuestas ---
var _mecha_t := -1.0
var _mecha_ruido: AudioStreamPlayer3D = null
# --- 12 la valla ---
var _valla: StaticBody3D = null
var _valla_puerta: Node3D = null
var _valla_parts: Array = []
var _valla_ruido: AudioStreamPlayer3D = null
var _valla_barrera := AABB()
var _aisladores_rotos: Array = [false, false, false]
var _chispa_t := 0.0
# --- 13 la barcaza ---
var _barcaza: AnimatableBody3D = null
var _barcaza_fase := 0              ## 0 en la orilla sur, 1 trayendola, 2 en la norte, 3 cruzando, 4 hecha
var _barcaza_k := 0.0               ## 0..1 de la fase que toque
var _barcaza_k_vis := 0.0
var _man1: Node3D = null
var _man2: Node3D = null
var _man_carraca_t := 0.0
var _man_tanda_t := 0.0
var _man_tank := false
var _cancela: StaticBody3D = null
var _bots_barcaza: Array = []
var _cable_barcaza: MeshInstance3D = null
var _frio_t := 0.0
# --- 14 la llave ---
var _llave_pueblo := false
var _llave_nodo: Node3D = null
var _porton_hojas: Array = []
var _porton_cuerpo: StaticBody3D = null
var _porton_barrera := AABB()
# --- 15 la tirolina ---
var _cable_tenso := false
var _cable_tirolina: Array = []     ## [MeshInstance3D] (tramos)
var _torno_nodo: Node3D = null
var _tirolina_t := -1.0
var _tirolina_carro: Node3D = null
# --- 16 las pasarelas ---
var _pasarelas: Array = []          ## [AnimatableBody3D]
var _pasarelas_fijas := false
var _pasarelas_ocupadas := false
var _pasarelas_tw: Array = []
# --- 17 la bola ---
var _bola_pivote: Node3D = null
var _bola_golpes := 0
var _bola_ocupada := false
# --- 18 la combinacion ---
var _diales: Array = [0, 0, 0]
var _dial_labels: Array = []
var _p18_puerta: StaticBody3D = null
var _llave_loco := false
var _llave_loco_nodo: Node3D = null
var _pistas_labels: Dictionary = {}
var _reloj_aguja: Node3D = null
# --- 19 las agujas ---
var _aguja := 0                     ## 0 via 1, 1 via muerta
var _aguja_mango: Node3D = null
var _aguja_luces: Array = []
var _vagon: AnimatableBody3D = null
var _vagon_fuera := false
var _vagon_s := -1.0
var _vagon_camino: Array = []
# --- 20 el gasoil y el tren ---
var _gasoil := 0
var _tren: Node3D = null
var _tren_cuerpos: Array = []
var _tren_gasoil_label: Label3D = null
var _tren_humo: CPUParticles3D = null
var _tren_foco: SpotLight3D = null
var _tren_motor: AudioStreamPlayer3D = null
var _calentar_t := 0.0
var _final_tank := false
var _tanda_final_t := 0.0


# ======================================================================================================
# LA ESCENA
# ======================================================================================================
func _montar_escena() -> void:
	super._montar_escena()
	rotulo_fase = ROTULO_FASE
	_arreglar_puertas_refugio()
	_muros_invisibles()
	if _soy_host:
		_sortear()
	_montar_heli()
	_montar_p01()
	_montar_p02()
	_montar_p03()
	_montar_p04()
	_montar_p05()
	_montar_p06()
	_montar_p07()
	_montar_p08()
	_montar_p09()
	_montar_p10()
	_montar_p11()
	_montar_p12()
	_montar_p13()
	_montar_p14()
	_montar_p15()
	_montar_p16()
	_montar_p17()
	_montar_p18()
	_montar_p19()
	_montar_p20()
	_aplicar_par()




































func _fase_de_rotulos() -> String:
	var f := fase
	if f == "inicio":
		f = "p01"
	if f == "arrancar" or f == "calentar":
		f = "p20"
	if f == "p10" and not _h("p09"):
		f = "p09"
	return f


func _bot_fijado(b: Node) -> bool:
	return _bots_barcaza.any(func(pb): return pb[0] == b)


## Cada rotulo es de un puzzle y solo se ve mientras toca ese puzzle y de cerca (si no, la pantalla se llenaba)
const ROTULO_FASE := {"calzo": "p01", "barricada": "p01", "palanca0": "p02", "palanca1": "p02", "llave_bombeo": "p03",
	"boca": "p03", "puerta_torre": "p04", "taco": "p04", "cuadro": "p05", "vapor": "p06", "llave_vapor": "p06",
	"valvulas": "p07", "esclusa": "p08", "tubos": "p09", "mando_grua": "p10", "bombona": "p11", "derrumbe": "p11",
	"aislador0": "p12", "aislador1": "p12", "aislador2": "p12", "valla": "p12", "manivela1": "p13", "manivela2": "p13",
	"porton": "p14", "torno": "p15", "tirolina": "p15", "pasarelas": "p16", "bloqueo": "p16", "grua_bola": "p17",
	"diales": "p18", "aguja": "p19", "freno": "p19", "tapon": "p20"}



























# ------------------------------------------------------------------ el refugio (puertas en el norte y el oeste)






# ------------------------------------------------------------------ el helicoptero que os ha traido
func _montar_heli() -> void:
	var hp: Vector3 = _v(cfg.get("heli", [13, 38, 9]))
	var h := _modelo_heli()
	add_child(h)
	h.global_position = hp + Vector3(0, 1.62, 0)
	h.rotation.y = 0.5
	_heli_quieto = h
	var rotor := _heli_rotor
	_heli_rotor = null
	# el rotor se va parando y el motor se apaga (el piloto se queda con el aparato: sin combustible)
	var tw := create_tween()
	tw.tween_method(func(v: float):
		if is_instance_valid(rotor):
			rotor.rotation.y += v * 0.016, 30.0, 0.0, 9.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for c in h.get_children():
		if c is AudioStreamPlayer3D:
			var a := c as AudioStreamPlayer3D
			var ta := a.create_tween()
			ta.tween_property(a, "volume_db", a.volume_db - 40.0, 8.0)
			ta.tween_callback(a.stop)
		if c is SpotLight3D:
			(c as SpotLight3D).visible = false


# ======================================================================================================
# LO SORTEADO (el anfitrion) Y EL ESTADO PARA QUIEN ENTRA TARDE
# ======================================================================================================
func _sortear() -> void:
	var colores := [0, 1, 2]
	colores.shuffle()
	var orden := [0, 1, 2]
	orden.shuffle()
	# las luces: desde todas encendidas, una a tres pulsaciones al azar (asi siempre tiene solucion)
	var luces := [true, true, true, true]
	while not luces.has(false):
		for k in randi_range(1, 3):
			luces = _pulsar(luces, randi() % 4)
	par = {"valv_colores": colores, "valv_orden": orden, "luces": luces, "tubos": _generar_tubos(),
		"casa": randi() % 4, "cifras": [randi_range(1, 9), randi_range(1, 9), randi_range(1, 9)]}
	_luces = luces.duplicate()
	_tubos_rot = (par["tubos"]["rot"] as Array).duplicate()
	print("[campana4] sorteo: valvulas %s orden %s · luces %s · casa %d · cifras %s" % [str(colores), str(orden),
		str(luces), int(par["casa"]), str(par["cifras"])])


func _estado_dict() -> Dictionary:
	var objs := {}
	for id in _obj4:
		var o: Dictionary = _obj4[id]
		var p: Vector3 = o["pos"]
		objs[id] = [String(o["estado"]), int(o["pid"]), p.x, p.y, p.z]
	return {"hecho": hecho, "par": par, "fase": fase, "luces": _luces, "tubos": _tubos_rot, "diales": _diales,
		"aguja": _aguja, "vagon": _vagon_fuera, "gasoil": _gasoil, "bola": _bola_golpes, "barcaza": [_barcaza_fase, _barcaza_k],
		"llave_pueblo": _llave_pueblo, "llave_loco": _llave_loco, "cable": _cable_tenso, "pasarelas": _pasarelas_fijas,
		"presion": _p03_presion, "aisladores": _aisladores_rotos, "objs": objs, "valv_paso": _valv_paso}




func _aplicar_estado(txt: String) -> void:
	var d = JSON.parse_string(txt)
	if not (d is Dictionary):
		return
	if _soy_host:
		return
	par = d.get("par", {})
	fase = String(d.get("fase", fase))
	_luces = d.get("luces", _luces)
	_tubos_rot = d.get("tubos", _tubos_rot)
	_diales = d.get("diales", _diales)
	_aguja = int(d.get("aguja", 0))
	_gasoil = int(d.get("gasoil", 0))
	_llave_pueblo = bool(d.get("llave_pueblo", false))
	_llave_loco = bool(d.get("llave_loco", false))
	_p03_presion = bool(d.get("presion", false))
	_aisladores_rotos = d.get("aisladores", _aisladores_rotos)
	_valv_paso = int(d.get("valv_paso", 0))
	var bz: Array = d.get("barcaza", [0, 0.0])
	_barcaza_fase = int(bz[0])
	_barcaza_k = float(bz[1])
	_barcaza_k_vis = _barcaza_k
	_aplicar_par()
	var hh: Dictionary = d.get("hecho", {})
	for k in hh:
		if bool(hh[k]) and not _h(String(k)):
			_resolver(String(k), true)
	if bool(d.get("cable", false)) and not _cable_tenso:
		_tensar_cable(true)
	if bool(d.get("pasarelas", false)) and not _pasarelas_fijas:
		_fijar_pasarelas(true)
	if bool(d.get("vagon", false)) and not _vagon_fuera:
		_vagon_rueda(true)
	var golpes := int(d.get("bola", 0))
	while _bola_golpes < golpes:
		_bola_golpe(_bola_golpes + 1, true)
	var objs: Dictionary = d.get("objs", {})
	for id in objs:
		var o: Array = objs[id]
		_obj_estado(String(id), String(o[0]), int(o[1]), Vector3(float(o[2]), float(o[3]), float(o[4])))
	_mecha_ver()
	_refrescar_todo()


## Lo que depende del sorteo: la pizarra, las piezas de las tuberias, las luces del cuadro, la llave, las cifras
func _aplicar_par() -> void:
	if par.is_empty():
		return
	_pizarra_texto()
	_tubos_montar_piezas()
	_luces_refrescar()
	_llave_colocar()
	_cifras_refrescar()
	_valvulas_colores()


func _refrescar_todo() -> void:
	_luces_refrescar()
	_tubos_refrescar()
	_diales_refrescar()
	_aguja_refrescar()
	_gasoil_refrescar()
	_man_refrescar()
	_mandos_refrescar4()


## Un puzzle resuelto: cada uno con su animacion (o de golpe si `ya`: quien entra tarde)
func _resolver(k: String, ya: bool) -> void:
	if _h(k):
		return
	hecho[k] = true
	match k:
		"p01": _p01_resuelto(ya)
		"p02": _p02_resuelto(ya)
		"p03": _p03_resuelto(ya)
		"p04": _p04_resuelto(ya)
		"p05": _p05_resuelto(ya)
		"p06": _p06_resuelto(ya)
		"p07": _p07_resuelto(ya)
		"p08": _p08_resuelto(ya)
		"p09": _p09_resuelto(ya)
		"p10": _p10_resuelto(ya)
		"p11": _p11_resuelto(ya)
		"p12": _p12_resuelto(ya)
		"p13": _p13_resuelto(ya)
		"p14": _p14_resuelto(ya)
		"p15": _p15_resuelto(ya)
		"p16": _p16_resuelto(ya)
		"p17": _p17_resuelto(ya)
		"p18": _p18_resuelto(ya)
		"p19": _p19_resuelto(ya)
		"p20": pass
	if not ya and k != "p20":
		Audio.ui("objetivo_tomado", -4.0)


# ======================================================================================================
# LOS MANDOS (2026-09-28, pedido: "me dice toca la palanca y no hay ninguna palanca"). Cada cosa que se usa con el
# boton tiene su mando de verdad (mandos.gd: volantes, palancas, manivelas, el panel de arranque...) y el aviso de
# usar sale ENCIMA de el. Mientras se monta la escena no se lee ninguna posicion global: todo sale del json y del
# mapa (rayos contra los voxels). Este nodo es un Node (no 3D): la `position` de sus hijos ya es la del mundo.
# ======================================================================================================
var _mandos4: Dictionary = {}                 ## id del usable -> su mando
var _p05_mandos: Array = []                   ## los cuatro interruptores del cuadro de luces
var _mecha_nodo: Node3D = null                ## la mecha de la bombona (se ve cuando no se lleva en brazos)
var _mecha_puntos: Array = []                 ## su recorrido, del mechero al grifo (en la bombona)
var _tirolina_parado: Node3D = null           ## la polea con su asa, esperando arriba
var _boca_gasoil: Node3D = null               ## la boca de carga de la locomotora
var _boca_salida := Vector3.ZERO              ## de donde sale el chorro de la boca de incendios


## La altura de la cara de arriba (voxels) bajo `p`: los mapas van a 10 y a 20 cm y la cota del json no siempre cae
func _suelo4(p: Vector3, desde: float = 1.0) -> float:
	if world == null:
		return p.y
	var h: Dictionary = world.raycast(p + Vector3.UP * desde, Vector3.DOWN, desde + 1.5)
	return float((h["position"] as Vector3).y) if bool(h.get("hit", false)) else p.y


## Donde sale el aviso de usar de un mando: por delante de su cara (`fuera` metros)
func _en_mando4(id: String, defecto: Vector3, fuera: float = 0.12) -> Vector3:
	var m = _mandos4.get(id)
	if m == null or not is_instance_valid(m) or not (m as Node3D).is_inside_tree():
		return defecto
	var n := m as Node3D
	return n.global_position + n.global_transform.basis.z * fuera


## El gesto de un mando en todas las maquinas (se llama desde el evento)
func _pulsar4(id: String, dejar_hecho: bool = true) -> void:
	var m = _mandos4.get(id)
	if m != null and is_instance_valid(m) and (m as Node3D).is_inside_tree():
		Mandos.accionar(m, dejar_hecho)


## El piloto de un mando, tambien si aun no esta en el arbol (Mandos lo pone en "espera" al entrar)
func _piloto4(m, estado: String) -> void:
	if m == null or not is_instance_valid(m):
		return
	var n := m as Node3D
	if n.is_inside_tree():
		Mandos.piloto(n, estado)
	else:
		n.tree_entered.connect(func(): Mandos.piloto(n, estado), CONNECT_ONE_SHOT | CONNECT_DEFERRED)


## Un mando que ya se uso (quien entra tarde, o lo resuelto de golpe): la palanca abajo, sin gesto, y el piloto verde
func _mando_hecho4(id: String) -> void:
	var m = _mandos4.get(id)
	if m == null or not is_instance_valid(m):
		return
	var n := m as Node3D
	if n.has_meta("brazo"):
		(n.get_meta("brazo") as Node3D).rotation.x = 0.5 if n.has_meta("interruptor") else PI - 0.45
	_piloto4(n, "hecho")


## La chapa de un volante de pared (gris con el marco amarillo, como la de las palancas): sobre el ladrillo rojo de la
## caseta de bombeo el volante rojo no se distinguia
func _chapa_volante4(m: Node3D) -> void:
	if m == null or not is_instance_valid(m):
		return
	_caja_mesh(m, Vector3(0.6, 0.6, 0.01), Vector3(0, 0, 0.005), _mm(Color(0.93, 0.68, 0.06), 0.25, 0.55))
	_caja_mesh(m, Vector3(0.54, 0.54, 0.016), Vector3(0, 0, 0.01), _mm(Color(0.3, 0.32, 0.34), 0.7, 0.45))


## Un tubo (o cable) de `a` a `b` sin look_at, en el espacio de `padre`
func _tubo4(padre: Node, a: Vector3, b: Vector3, r: float, mat: Material, segs: int = 10) -> MeshInstance3D:
	var d := b - a
	var largo := d.length()
	var mi := _cil_mesh(padre, r, maxf(largo, 0.01), Vector3.ZERO, mat, Vector3.ZERO, segs)
	var y := d / maxf(largo, 0.001)
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	return mi


## Lo que dice cada mando segun como va la partida (quien entra tarde lo recibe todo de golpe)
func _mandos_refrescar4() -> void:
	if _p03_presion and not _h("p03"):
		_piloto4(_mandos4.get("p03_boca"), "espera")
	if _p03_presion:
		_mando_hecho4("p03_llave")
	if _barcaza_fase >= 2:
		_piloto4(_man1, "hecho")
		_piloto4(_man2, "hecho" if _barcaza_fase >= 4 else "espera")
	if _gasoil >= 6:
		_piloto4(_mandos4.get("p20_arranque"), "espera")


# ======================================================================================================
# 1. LA VAGONETA
# ======================================================================================================
func _p01_camino() -> Array:
	var out: Array = []
	for p in _c("p01_vagoneta").get("via", []):
		out.append(_v(p))
	return out


func _montar_p01() -> void:
	var via := _p01_camino()
	if via.size() < 2:
		return
	_vag_largo = 0.0
	for i in via.size() - 1:
		_vag_largo += (via[i + 1] as Vector3).distance_to(via[i])
	_vag = _animable("Vagoneta", via[0])
	var oxido := _mm(Color(0.42, 0.24, 0.13), 0.5, 0.8)
	var hierro := _mm(Color(0.14, 0.14, 0.15), 0.8, 0.5)
	var piedra := _mm(Color(0.55, 0.52, 0.48), 0.0, 0.95)
	_colision_caja(_vag, Vector3(1.3, 1.1, 2.2), Vector3(0, 0.85, 0))
	# la caja en tolva (mas ancha arriba), las ruedas y la carga de piedra
	_caja_mesh(_vag, Vector3(1.1, 0.5, 2.0), Vector3(0, 0.55, 0), oxido)
	_caja_mesh(_vag, Vector3(1.35, 0.6, 2.25), Vector3(0, 1.05, 0), oxido)
	_caja_mesh(_vag, Vector3(1.2, 0.08, 2.1), Vector3(0, 1.36, 0), piedra)
	for k in 5:
		_esfera_mesh(_vag, 0.28 + 0.06 * (k % 2), Vector3(-0.35 + 0.18 * k, 1.42, -0.7 + 0.35 * k), piedra)
	for sx in [-0.5, 0.5]:
		for sz in [-0.7, 0.7]:
			_cil_mesh(_vag, 0.26, 0.12, Vector3(sx, 0.28, sz), hierro, Vector3(0, 0, PI / 2), 12)
	_caja_mesh(_vag, Vector3(1.4, 0.12, 0.12), Vector3(0, 0.75, 1.15), hierro)
	_rotulo("calzo", "REVENTAD EL CALZO", _centro(_c("p01_vagoneta").get("calzo", [0, 0, 0, 0, 0, 0])) + Vector3(0, 1.6, 0.4), Color(0.95, 0.75, 0.1))
	_rotulo("barricada", "BARRICADA", _centro(_c("p01_vagoneta").get("barricada", [0, 0, 0, 0, 0, 0])) + Vector3(0, 2.6, -0.6), Color(0.95, 0.3, 0.1))


func _p01_resuelto(ya: bool) -> void:
	_quitar_cartel("calzo")
	_quitar_cartel("barricada")
	if ya:
		_p01_romper_barricada()
		if is_instance_valid(_vag):
			_vag.queue_free()
		return
	_vag_s = 0.0
	_vag_v = 2.2
	Audio.bf3d("destru/madera", _vag.global_position, 2.0, 40.0, Audio.PRI_MID)
	_mensaje_local("¡EL CALZO HA SALTADO! La vagoneta va cuesta abajo…")


func _p01_romper_barricada() -> void:
	var b: Array = _c("p01_vagoneta").get("barricada", [])
	if b.is_empty():
		return
	var cx := float(_c("p01_vagoneta")["via"][0][0])
	_tallar_rejilla(Vector3(cx, 0, float(b[2]) - 0.8), Vector3.BACK, float(b[5]) - float(b[2]) + 1.6,
		[-1.4, -0.7, 0.0, 0.7, 1.4], [float(b[1]) + 0.5, float(b[1]) + 1.2, float(b[1]) + 1.9, float(b[1]) + 2.4],
		Vector3.RIGHT, Vector3.UP, 0.5)


func _vagoneta_tick(dt: float) -> void:
	if _vag_s < 0.0 or not is_instance_valid(_vag):
		return
	var via := _p01_camino()
	# por donde va: el tramo y la pendiente (la gravedad tira de ella en la rampa)
	var s := _vag_s
	var i := 0
	while i < via.size() - 2 and s > (via[i + 1] as Vector3).distance_to(via[i]):
		s -= (via[i + 1] as Vector3).distance_to(via[i])
		i += 1
	var a: Vector3 = via[i]
	var b: Vector3 = via[i + 1]
	var tramo := a.distance_to(b)
	var dirv := (b - a) / maxf(tramo, 0.001)
	var acel := -dirv.y * 9.8 * 0.9 - 0.25
	if _vag_al_agua:
		acel = -6.0
	_vag_v = clampf(_vag_v + acel * dt, 0.8 if _vag_barricada else 2.0, 16.0)
	_vag_s += _vag_v * dt
	var p := a + dirv * minf(s, tramo)
	_vag.global_position = p
	if Vector2(dirv.x, dirv.z).length() > 0.01:
		_vag.rotation.y = atan2(dirv.x, dirv.z)
	_vag.rotation.x = -asin(clampf(dirv.y, -1.0, 1.0)) * 0.9
	# la barricada
	var bz: float = float(_c("p01_vagoneta")["barricada"][2])
	if not _vag_barricada and p.z > bz - 1.2:
		_vag_barricada = true
		_vag_v *= 0.55
		_p01_romper_barricada()
		_golpe(p + Vector3(0, 1.0, 1.0), 1.8, "destru/madera")
		_golpe(p + Vector3(0, 1.0, 1.5), 1.2, "destru/derrumbe_medio")
		_mensaje_local("¡LA VAGONETA HA REVENTADO LA BARRICADA!")
	# el final: se sale del embarcadero y al agua
	if not _vag_al_agua and i >= via.size() - 3:
		_vag_al_agua = true
	if _vag_s >= _vag_largo:
		_vag_s = -1.0
		Audio.bf3d("amb/grifo_revienta", p, 6.0, 80.0, Audio.PRI_HIGH)
		var fx = jugador.get("effects") if is_instance_valid(jugador) else null
		if fx and fx.has_method("dust"):
			fx.dust(p + Vector3.UP * 0.5, 2.0)
		var tw := _vag.create_tween()
		tw.tween_property(_vag, "global_position:y", p.y - 6.0, 2.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(_vag.queue_free)


# ======================================================================================================
# 2. LAS DOS PALANCAS
# ======================================================================================================
func _montar_p02() -> void:
	var c := _c("p02_palancas")
	if c.is_empty():
		return
	var r: Array = c["puerta"]
	var cen := _centro(r)
	var tam := _mx(r) - _mn(r)
	_p02_puerta = _estatico("PuertaCoronacion", cen)
	_colision_caja(_p02_puerta, tam, Vector3.ZERO)
	var gris := _mm(Color(0.30, 0.32, 0.33), 0.7, 0.5)
	var amarillo := _mm(Color(0.85, 0.66, 0.08), 0.4, 0.5)
	_caja_mesh(_p02_puerta, Vector3(tam.x + 0.1, 0.18, tam.z), Vector3(0, tam.y / 2 - 0.09, 0), gris)
	_caja_mesh(_p02_puerta, Vector3(tam.x + 0.1, 0.18, tam.z), Vector3(0, -tam.y / 2 + 0.3, 0), gris)
	var n := int(tam.z / 0.22)
	for i in n:
		_caja_mesh(_p02_puerta, Vector3(0.06, tam.y - 0.2, 0.06), Vector3(0, 0.05, -tam.z / 2 + 0.11 + i * 0.22), gris)
	for i in 5:
		_caja_mesh(_p02_puerta, Vector3(0.14, 0.35, tam.z / 5 - 0.05), Vector3(0, 0.4, -tam.z / 2 + (i + 0.5) * tam.z / 5), amarillo if i % 2 == 0 else _mm(Color(0.05, 0.05, 0.05), 0.3, 0.5))
	_texto3d("PRESA DE EL SALTO\nACCESO RESTRINGIDO", Vector3(-0.1, 0.9, 0), Color(0.95, 0.9, 0.8), 40, false, _p02_puerta, -PI / 2)
	_p02_barrera = AABB(_mn(r) + Vector3(-0.6, -1.0, 0), tam + Vector3(1.2, 3.0, 0))
	CriaturaScript.barreras.append(_p02_barrera)
	for i in (c["palancas"] as Array).size():
		var p: Vector3 = _v(c["palancas"][i])
		var base := Node3D.new()
		add_child(base)
		base.global_position = p
		_caja_mesh(base, Vector3(0.3, 1.0, 0.3), Vector3(0, 0.5, 0), _mm(Color(0.2, 0.22, 0.2), 0.6, 0.5))
		var mango := Node3D.new()
		mango.position = Vector3(0, 1.0, 0)
		base.add_child(mango)
		_caja_mesh(mango, Vector3(0.06, 0.7, 0.06), Vector3(0, 0.35, 0), _mm(Color(0.1, 0.1, 0.1), 0.6, 0.5))
		_esfera_mesh(mango, 0.07, Vector3(0, 0.72, 0), _mm(Color(0.8, 0.1, 0.05), 0.2, 0.4))
		mango.rotation.x = 0.6
		_p02_palancas.append(mango)
		var luz := _esfera_mesh(base, 0.08, Vector3(0.22, 1.05, 0), _brillo(Color(0.9, 0.1, 0.05), 1.5))
		_p02_luces.append(luz)
		_rotulo("palanca%d" % i, "PALANCA %d" % (i + 1), p + Vector3(0, 2.3, 0), Color(0.95, 0.75, 0.1))


func _p02_tira(i: int) -> void:
	if i < 0 or i >= _p02_palancas.size():
		return
	var mango: Node3D = _p02_palancas[i]
	var tw := mango.create_tween()
	tw.tween_property(mango, "rotation:x", -0.6, 0.25)
	Audio.bf3d("destru/metal", mango.global_position, -4.0, 30.0, Audio.PRI_MID)
	(_p02_luces[i] as MeshInstance3D).material_override = _brillo(Color(0.1, 0.95, 0.2), 2.0)
	if not _h("p02"):
		var ventana := float(_c("p02_palancas").get("ventana", 5.0))
		get_tree().create_timer(ventana).timeout.connect(func():
			if _h("p02") or not is_instance_valid(mango):
				return
			var t2 := mango.create_tween()
			t2.tween_property(mango, "rotation:x", 0.6, 0.4)
			(_p02_luces[i] as MeshInstance3D).material_override = _brillo(Color(0.9, 0.1, 0.05), 1.5))
		_mensaje_local("PALANCA %d ABAJO · ¡la otra, rápido! (%d s)" % [i + 1, int(ventana)])


func _p02_resuelto(ya: bool) -> void:
	for i in 2:
		_quitar_cartel("palanca%d" % i)
	CriaturaScript.barreras.erase(_p02_barrera)
	if not is_instance_valid(_p02_puerta):
		return
	_sin_colision(_p02_puerta)
	for i in _p02_luces.size():
		(_p02_luces[i] as MeshInstance3D).material_override = _brillo(Color(0.1, 0.95, 0.2), 2.0)
		(_p02_palancas[i] as Node3D).rotation.x = -0.6
	if ya:
		_p02_puerta.global_position.y -= 3.4
		return
	var tw := _p02_puerta.create_tween()
	tw.tween_property(_p02_puerta, "global_position:y", _p02_puerta.global_position.y - 3.4, 3.0).set_trans(Tween.TRANS_SINE)
	Audio.play3d("gen/persiana/sube", _p02_puerta.global_position, 4.0, 0.02, 60.0, Audio.PRI_HIGH)
	_mensaje_local("¡LA PUERTA DE LA PRESA SE ABRE!")


# ======================================================================================================
# 3. EL CAMION EN LLAMAS
# ======================================================================================================




func _montar_p03() -> void:
	var c := _c("p03_fuego")
	if c.is_empty():
		return
	var r: Array = c["rect"]
	var cen := _centro(r)
	var tam := _mx(r) - _mn(r)
	_fuego_cuerpo = _estatico("Fuego", cen)
	_colision_caja(_fuego_cuerpo, tam, Vector3.ZERO)
	_fuego_nodo = Node3D.new()
	add_child(_fuego_nodo)
	_fuego_nodo.global_position = Vector3(cen.x, _mn(r).y, cen.z)
	# llamas a lo largo del camion y del charco de gasoil, y el humo negro que se ve desde la cantera
	for k in 5:
		var px := -tam.x * 0.4 + k * tam.x * 0.2
		var f := _particulas(_fuego_nodo, Vector3(px, 0.3, 0), 36, 1.0, Color(1.0, 0.85, 0.35, 0.95), Color(0.6, 0.12, 0.02), 1.3, true)
		f.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		f.emission_box_extents = Vector3(tam.x * 0.1, 0.4, tam.z * 0.45)
		f.direction = Vector3.UP
		f.spread = 15.0
		f.gravity = Vector3(0, 3.0, 0)
		f.initial_velocity_min = 0.6
		f.initial_velocity_max = 2.0
		f.scale_amount_min = 0.7
		f.scale_amount_max = 1.6
		_fuego_parts.append(f)
	var humo := _particulas(_fuego_nodo, Vector3(0, 3.0, 0), 30, 5.0, Color(0.12, 0.11, 0.1, 0.7), Color(0.3, 0.28, 0.26), 3.5, false)
	humo.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	humo.emission_box_extents = Vector3(tam.x * 0.4, 0.5, tam.z * 0.3)
	humo.direction = Vector3.UP
	humo.gravity = Vector3(1.0, 1.8, 0.5)
	humo.initial_velocity_min = 1.0
	humo.initial_velocity_max = 2.5
	humo.scale_amount_min = 1.0
	humo.scale_amount_max = 2.4
	_fuego_parts.append(humo)
	_fuego_luz = _luz(_fuego_nodo, Vector3(0, 2.0, 0), Color(1.0, 0.55, 0.2), 3.0, 16.0)
	_fuego_ruido = _bucle_bf("bf/amb/bucle_fuego", _fuego_nodo, Vector3(0, 1.0, 0), 4.0, 70.0)
	_fuego_barrera = AABB(_mn(r) - Vector3(0.5, 1.0, 0.5), tam + Vector3(1.0, 2.0, 1.0))
	CriaturaScript.barreras.append(_fuego_barrera)
	# LA LLAVE GENERAL: un volante rojo en la pared norte de la caseta de bombeo, con su tubo azul que sube a la
	# tuberia de las bombas (antes era un disco plano en el aire)
	var ll := _v(c["llave"])
	var mll := Mandos.en_pared(world, "volante", self, ll + Vector3(0, 1.15, 0), Vector3(0, 0, 1), 1.3)
	_mandos4["p03_llave"] = mll
	_chapa_volante4(mll)
	var azul := _mm(Color(0.16, 0.3, 0.62), 0.6, 0.45)
	var cuerpo := mll.position + Vector3(0, 0, 0.08)
	_tubo4(self, cuerpo + Vector3(0, 0.06, 0), Vector3(cuerpo.x, ll.y + 2.9, cuerpo.z), 0.05, azul)
	_tubo4(self, Vector3(cuerpo.x, ll.y + 2.9, cuerpo.z - 0.05), Vector3(cuerpo.x, ll.y + 2.9, ll.z + 0.25), 0.05, azul)
	# LA BOCA DE INCENDIOS: el hidrante es del mapa; encima, su tapa con el volante rojo (se abre girandolo) y, al
	# lado del camion, la salida con su racor, de donde sale el chorro. Sin presion su piloto esta apagado.
	var bo := _v(c["boca"])
	var tapa := _suelo4(Vector3(bo.x, bo.y + 1.07, bo.z - 0.1), 0.5)
	var rojo := _mm(Color(0.72, 0.08, 0.06), 0.35, 0.5)
	var laton := _mm(Color(0.78, 0.62, 0.3), 0.85, 0.35)
	_cil_mesh(self, 0.3, 0.05, Vector3(bo.x, tapa + 0.025, bo.z - 0.1), rojo, Vector3.ZERO, 18)
	var mbo := Mandos.crear("volante", self, Vector3(bo.x, tapa + 0.05, bo.z - 0.1), Vector3.UP)
	_mandos4["p03_boca"] = mbo
	_piloto4(mbo, "apagado")
	_boca_salida = Vector3(bo.x + 0.42, tapa - 0.4, bo.z - 0.1)
	_cil_mesh(self, 0.08, 0.26, Vector3(bo.x + 0.28, tapa - 0.4, bo.z - 0.1), rojo, Vector3(0, 0, PI / 2), 12)
	_cil_mesh(self, 0.1, 0.06, Vector3(bo.x + 0.41, tapa - 0.4, bo.z - 0.1), laton, Vector3(0, 0, PI / 2), 12)
	_rotulo("llave_bombeo", "LLAVE GENERAL", ll + Vector3(0, 2.2, 0.6), Color(0.3, 0.8, 1.0))
	_rotulo("boca", "BOCA DE INCENDIOS", _v(c["boca"]) + Vector3(0, 1.8, -0.5), Color(0.95, 0.3, 0.1))


func _p03_llave() -> void:
	if _p03_presion:
		return
	_p03_presion = true
	_quitar_cartel("llave_bombeo")
	_pulsar4("p03_llave")
	_piloto4(_mandos4.get("p03_boca"), "espera")          # ya hay presion: la boca se puede abrir
	var ll := _v(_c("p03_fuego").get("llave", [0, 0, 0]))
	Audio.play3d("gen/generador/arranque", ll + Vector3.UP, 0.0, 0.02, 50.0, Audio.PRI_HIGH)
	Audio.play3d("gen/valvula/giro", ll + Vector3.UP, 0.0, 0.05, 30.0, Audio.PRI_MID)
	_mensaje_local("¡LAS BOMBAS DAN PRESIÓN! Ahora la BOCA DE INCENDIOS")


func _p03_resuelto(ya: bool) -> void:
	_quitar_cartel("boca")
	_quitar_cartel("llave_bombeo")
	_p03_presion = true
	CriaturaScript.barreras.erase(_fuego_barrera)
	if is_instance_valid(_fuego_cuerpo):
		_sin_colision(_fuego_cuerpo)
	_mando_hecho4("p03_llave")
	if ya:
		_mando_hecho4("p03_boca")
		_apagar_fuego(0.1)
		return
	_pulsar4("p03_boca")
	# el chorro, en arco sobre el camion: sale del racor de la boca que da al camion
	var boca := _v(_c("p03_fuego").get("boca", [0, 0, 0]))
	var salida := _boca_salida if _boca_salida != Vector3.ZERO else boca + Vector3(0, 1.1, 0)
	var chorro := _particulas(self, salida, 60, 1.3, Color(0.75, 0.85, 1.0, 0.8), Color(0.9, 0.95, 1.0), 0.45, false)
	chorro.direction = Vector3(1.0, 0.75, -0.25).normalized()
	chorro.spread = 4.0
	chorro.initial_velocity_min = 11.0
	chorro.initial_velocity_max = 12.5
	chorro.gravity = Vector3(0, -9.8, 0)
	Audio.bf3d("amb/grifo_revienta", boca, 4.0, 60.0, Audio.PRI_HIGH)
	var ag := _bucle_bf("bf/amb/bucle_rio", self, Vector3.ZERO, 0.0, 40.0)
	if ag:
		ag.global_position = boca + Vector3(4, 1, -1)
	get_tree().create_timer(1.5).timeout.connect(func(): _apagar_fuego(5.0))
	get_tree().create_timer(9.0).timeout.connect(func():
		if is_instance_valid(chorro):
			chorro.emitting = false
		if is_instance_valid(ag):
			ag.queue_free())
	_mensaje_local("¡EL AGUA APAGA EL FUEGO!")


func _apagar_fuego(dur: float) -> void:
	_fuego_vivo = false
	for f in _fuego_parts:
		if is_instance_valid(f):
			var p := f as CPUParticles3D
			var tw := p.create_tween()
			tw.tween_property(p, "scale_amount_max", 0.05, dur)
			tw.tween_callback(func(): p.emitting = false)
	if is_instance_valid(_fuego_luz):
		create_tween().tween_property(_fuego_luz, "light_energy", 0.0, dur)
	if is_instance_valid(_fuego_ruido):
		var tr := _fuego_ruido.create_tween()
		tr.tween_property(_fuego_ruido, "volume_db", -60.0, dur)
		tr.tween_callback(_fuego_ruido.queue_free)
	if dur > 1.0 and is_instance_valid(_fuego_nodo):
		var vapor := _particulas(_fuego_nodo, Vector3(0, 1.0, 0), 40, 3.0, Color(0.85, 0.85, 0.85, 0.6), Color(0.6, 0.6, 0.6), 2.4, false)
		vapor.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		vapor.emission_box_extents = Vector3(6.0, 0.5, 2.0)
		vapor.direction = Vector3.UP
		vapor.gravity = Vector3(0, 1.5, 0)
		vapor.initial_velocity_min = 0.5
		vapor.initial_velocity_max = 1.5
		get_tree().create_timer(dur + 3.0).timeout.connect(func():
			if is_instance_valid(vapor):
				vapor.emitting = false)


# ======================================================================================================
# 4. LA CUERDA Y LA PLACA
# ======================================================================================================
func _montar_p04() -> void:
	var c := _c("p04_placa")
	if c.is_empty():
		return
	var gris := _mm(Color(0.28, 0.30, 0.31), 0.75, 0.45)
	var amarillo := _mm(Color(0.85, 0.66, 0.08), 0.4, 0.5)
	# LA PUERTA de la torre: una hoja de acero que sube cuando hay peso en la placa
	var r: Array = c["puerta"]
	var tam := _mx(r) - _mn(r)
	_p04_puerta = _estatico("PuertaTorre", _centro(r))
	_p04_puerta_y0 = _p04_puerta.global_position.y
	_colision_caja(_p04_puerta, tam, Vector3.ZERO)
	_caja_mesh(_p04_puerta, tam, Vector3.ZERO, gris)
	for k in 4:
		_caja_mesh(_p04_puerta, Vector3(tam.x, 0.08, tam.z + 0.04), Vector3(0, -tam.y / 2 + 0.4 + k * 0.6, 0), _mm(Color(0.18, 0.2, 0.2), 0.8, 0.5))
	_texto3d("TORRE DE TOMA", Vector3(0, tam.y / 2 - 0.3, tam.z / 2 + 0.03), Color(0.95, 0.9, 0.8), 32, false, _p04_puerta)
	_p04_barrera = AABB(_mn(r) - Vector3(0.4, 1.0, 1.0), tam + Vector3(0.8, 2.0, 2.0))
	CriaturaScript.barreras.append(_p04_barrera)
	# LA PLACA
	var pl: Array = c["placa"]
	_p04_placa_nodo = Node3D.new()
	add_child(_p04_placa_nodo)
	_p04_placa_nodo.global_position = Vector3((float(pl[0]) + float(pl[3])) / 2, float(pl[1]) + 0.04, (float(pl[2]) + float(pl[5])) / 2)
	_caja_mesh(_p04_placa_nodo, Vector3(float(pl[3]) - float(pl[0]), 0.08, float(pl[5]) - float(pl[2])), Vector3.ZERO, _mm(Color(0.5, 0.52, 0.55), 0.85, 0.35))
	_esfera_mesh(_p04_placa_nodo, 0.07, Vector3(0.55, 0.05, 0.55), _brillo(Color(0.9, 0.1, 0.05), 1.6))
	# EL PALE de sacos colgado de la pluma
	var punta := _v(c["punta"])
	var pale_y := float(c.get("pale_y", 38.2))
	_p04_pale = _estatico("Pale", Vector3(punta.x, pale_y + 0.45, punta.z))
	_p04_pale.add_to_group(TREPABLE)
	_colision_caja(_p04_pale, Vector3(1.3, 0.9, 1.3), Vector3.ZERO)
	_caja_mesh(_p04_pale, Vector3(1.3, 0.14, 1.3), Vector3(0, -0.38, 0), _mm(Color(0.45, 0.33, 0.2), 0.0, 0.9))
	var saco := _mm(Color(0.72, 0.66, 0.52), 0.0, 0.95)
	for i in 3:
		for j in 2:
			_caja_mesh(_p04_pale, Vector3(0.4, 0.34, 0.6), Vector3(-0.42 + i * 0.42, -0.14 + j * 0.34, 0.0), saco)
	_texto3d("CEMENTO", Vector3(0, 0.1, 0.33), Color(0.3, 0.3, 0.3), 24, false, _p04_pale)
	var cuerda_mat := _mm(Color(0.62, 0.55, 0.38), 0.0, 0.9)
	for k in 3:
		_p04_cuerdas.append(_cuerda(cuerda_mat, 0.025))
	_p04_cuerdas_tick()
	_rotulo("puerta_torre", "SOLO SE ABRE CON PESO EN LA PLACA", _centro(r) + Vector3(0, 2.2, 0.8), Color(0.95, 0.75, 0.1))
	_rotulo("taco", "¿Y SI CAE EL PALÉ? · el TACO de la cuerda", _v(c["poste"]) + Vector3(0, -2.4, 0.4), Color(0.95, 0.5, 0.1))


func _p04_cuerdas_tick() -> void:
	if _h("p04") or _p04_cuerdas.size() < 3 or not is_instance_valid(_p04_pale):
		return
	var c := _c("p04_placa")
	var punta := _v(c["punta"])
	var poste := _v(c["poste"])
	var t: Array = c["taco"]
	var taco := _centro(t)
	_linea(_p04_cuerdas[0], punta + Vector3(0, -0.2, 0), _p04_pale.global_position + Vector3(0, 0.45, 0))
	_linea(_p04_cuerdas[1], punta + Vector3(0, 0.05, 0), poste + Vector3(0, 0.1, 0))
	_linea(_p04_cuerdas[2], poste + Vector3(0.1, 0.0, 0.1), taco)


func _p04_placa(on: bool) -> void:
	_p04_pisada = on
	if not is_instance_valid(_p04_puerta) or _h("p04"):
		return
	var tw := _p04_puerta.create_tween()
	if on:
		tw.tween_property(_p04_puerta, "global_position:y", _p04_puerta_y0 + 2.5, 0.5).set_trans(Tween.TRANS_QUAD)
		_sin_colision(_p04_puerta)
	else:
		tw.tween_property(_p04_puerta, "global_position:y", _p04_puerta_y0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func(): _con_colision(_p04_puerta))
	Audio.bf3d("destru/metal", _p04_puerta.global_position, -4.0, 30.0, Audio.PRI_MID)
	if is_instance_valid(_p04_placa_nodo):
		_p04_placa_nodo.global_position.y += -0.04 if on else 0.04


func _p04_resuelto(ya: bool) -> void:
	_quitar_cartel("taco")
	_quitar_cartel("puerta_torre")
	CriaturaScript.barreras.erase(_p04_barrera)
	for cu in _p04_cuerdas:
		if is_instance_valid(cu):
			cu.queue_free()
	_p04_cuerdas.clear()
	var pl: Array = _c("p04_placa").get("placa", [0, 34, 0, 0, 34, 0])
	var fin_y := float(pl[1]) + 0.12 + 0.45
	if is_instance_valid(_p04_puerta):
		_sin_colision(_p04_puerta)
		if ya:
			_p04_puerta.global_position.y = _p04_puerta_y0 + 2.5
		else:
			_p04_puerta.create_tween().tween_property(_p04_puerta, "global_position:y", _p04_puerta_y0 + 2.5, 0.6)
	if not is_instance_valid(_p04_pale):
		return
	if ya:
		_p04_pale.global_position.y = fin_y
		return
	var tw := _p04_pale.create_tween()
	tw.tween_property(_p04_pale, "global_position:y", fin_y, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		_golpe(_p04_pale.global_position, 1.2, "destru/madera")
		if is_instance_valid(_p04_placa_nodo):
			_p04_placa_nodo.global_position.y -= 0.04)
	tw.tween_property(_p04_pale, "global_position:y", fin_y + 0.1, 0.1)
	tw.tween_property(_p04_pale, "global_position:y", fin_y, 0.12)
	_mensaje_local("¡EL PALÉ HA CAÍDO SOBRE LA PLACA! La puerta de la torre se queda abierta")


# ======================================================================================================
# 5. EL CUADRO DE LUCES
# ======================================================================================================
static func _pulsar(l: Array, i: int) -> Array:
	var out := l.duplicate()
	for j in [i - 1, i, i + 1]:
		if j >= 0 and j < out.size():
			out[j] = not bool(out[j])
	return out


func _cuadro_pos(i: int) -> Vector3:
	var c: Vector3 = _v(_c("p05_cuadro").get("pos", [0, 0, 0]))
	return Vector3(c.x + (1.5 - i) * 0.45, c.y + 1.2, c.z - 0.2)


func _montar_p05() -> void:
	var c := _c("p05_cuadro")
	if c.is_empty():
		return
	var cp: Vector3 = _v(c["pos"])
	var caja := Node3D.new()
	add_child(caja)
	caja.global_position = cp
	_caja_mesh(caja, Vector3(2.0, 1.4, 0.12), Vector3(0, 1.55, -0.12), _mm(Color(0.25, 0.3, 0.28), 0.6, 0.5))
	_texto3d("ALUMBRADO GALERÍA", Vector3(0, 2.1, -0.2), Color(0.9, 0.9, 0.85), 22, false, caja, PI)
	# la cara del cuadro de voxels del mapa (a 20 cm sale 5 cm por delante del tablero de chapa): ahi van los mandos
	var cara_z := cp.z - 0.18
	if world != null:
		var hz: Dictionary = world.raycast(Vector3(cp.x, cp.y + 1.2, cp.z - 1.2), Vector3.BACK, 1.5)
		if bool(hz.get("hit", false)):
			cara_z = minf(cara_z, float((hz["position"] as Vector3).z))
	for i in 4:
		var p := _cuadro_pos(i)
		# cada interruptor, su cajita con la palanca grande (abajo apagado, arriba encendido), atornillada al cuadro
		var m := Mandos.crear("interruptor", self, Vector3(p.x, p.y, cara_z - 0.005), Vector3(0, 0, -1))
		_p05_mandos.append(m)
		_mandos4["p05_%d" % i] = m
		_p05_mangos.append(m.get_meta("brazo"))
		var lamp := _esfera_mesh(self, 0.09, Vector3.ZERO, _brillo(Color(0.9, 0.1, 0.05), 1.5))
		lamp.global_position = p + Vector3(0, 0.55, 0)
		_p05_lamparas.append(lamp)
		_texto3d(str(i + 1), Vector3(p.x, p.y + 0.34, cara_z - 0.02), Color(0.9, 0.9, 0.8), 18, false, null, PI)     # (encima de su cajita)
	# la reja de la galeria (hacia el oeste) y las lamparas (apagadas)
	var rr: Array = c["reja"]
	var tam := _mx(rr) - _mn(rr)
	_p05_reja = _estatico("RejaGaleria", _centro(rr))
	_colision_caja(_p05_reja, tam, Vector3.ZERO)
	var hierro := _mm(Color(0.16, 0.16, 0.17), 0.8, 0.5)
	for i in int(tam.z / 0.18):
		_caja_mesh(_p05_reja, Vector3(0.05, tam.y, 0.05), Vector3(0, 0, -tam.z / 2 + 0.09 + i * 0.18), hierro)
	for y in [-tam.y / 2 + 0.2, 0.0, tam.y / 2 - 0.15]:
		_caja_mesh(_p05_reja, Vector3(0.08, 0.08, tam.z), Vector3(0, y, 0), hierro)
	_p05_barrera = AABB(_mn(rr) - Vector3(0.6, 0.5, 0), tam + Vector3(1.2, 1.0, 0))
	CriaturaScript.barreras.append(_p05_barrera)
	for p in c.get("luces", []):
		var o := _luz(self, Vector3.ZERO, Color(1.0, 0.92, 0.75), 0.0, 9.0)
		o.global_position = _v(p)
		o.visible = false
		_galeria_luces.append(o)
	_rotulo("cuadro", "ENCENDED LAS 4 LUCES", cp + Vector3(0, 2.6, -0.6), Color(0.3, 0.8, 1.0))


func _luces_refrescar() -> void:
	for i in mini(_p05_lamparas.size(), _luces.size()):
		var on := bool(_luces[i])
		(_p05_lamparas[i] as MeshInstance3D).material_override = _brillo(Color(0.1, 0.95, 0.25) if on else Color(0.9, 0.1, 0.05), 2.0 if on else 1.2)
		(_p05_mangos[i] as Node3D).rotation.x = 0.5 if on else -0.5
		if i < _p05_mandos.size():
			_piloto4(_p05_mandos[i], "hecho" if on else "espera")


func _p05_resuelto(ya: bool) -> void:
	_quitar_cartel("cuadro")
	_luces = [true, true, true, true]
	_luces_refrescar()
	CriaturaScript.barreras.erase(_p05_barrera)
	for k in _galeria_luces.size():
		var o: OmniLight3D = _galeria_luces[k]
		if not is_instance_valid(o):
			continue
		o.visible = true
		if ya:
			o.light_energy = 1.1
		else:
			var tw := o.create_tween()
			tw.tween_interval(0.15 * k)
			tw.tween_property(o, "light_energy", 1.4, 0.05)
			tw.tween_property(o, "light_energy", 0.1, 0.08)
			tw.tween_property(o, "light_energy", 1.1, 0.1)
	if is_instance_valid(_p05_reja):
		_sin_colision(_p05_reja)
		if ya:
			_p05_reja.global_position.y += 2.6
		else:
			_p05_reja.create_tween().tween_property(_p05_reja, "global_position:y", _p05_reja.global_position.y + 2.6, 2.4).set_trans(Tween.TRANS_SINE)
			Audio.play3d("gen/ascensor/reja", _p05_reja.global_position, 2.0, 0.02, 40.0, Audio.PRI_HIGH)
			_mensaje_local("¡LUZ! La reja de la galería se levanta")


# ======================================================================================================
# 6. EL PASILLO DE VAPOR
# ======================================================================================================
func _montar_p06() -> void:
	var c := _c("p06_vapor")
	if c.is_empty():
		return
	var z: Array = c["z"]
	var y := float(c["y"])
	for x in c["chorros"]:
		var n := Node3D.new()
		add_child(n)
		n.global_position = Vector3(float(x), y + 1.9, float(z[0]) + 0.35)
		var p := _particulas(n, Vector3.ZERO, 40, 0.8, Color(0.95, 0.95, 0.95, 0.75), Color(0.8, 0.82, 0.85), 0.9, false)
		p.direction = Vector3(0, -0.35, 1.0).normalized()
		p.spread = 16.0
		p.initial_velocity_min = 5.0
		p.initial_velocity_max = 7.0
		p.gravity = Vector3(0, 0.5, 0)
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.8
		var au := _bucle_bf("bf/amb/bucle_gas", n, Vector3(0, -0.5, 1.2), -2.0, 30.0)
		_chorros.append({"parts": p, "x": float(x), "audio": au, "on": true})
	_rotulo("vapor", "¡VAPOR! pasad entre los chorros", Vector3(float(c["chorros"][0]) + 2.0, y + 2.4, (float(z[0]) + float(z[1])) / 2), Color(1.0, 0.6, 0.2))
	_rotulo("llave_vapor", "LLAVE DEL VAPOR", _v(c["llave"]) + Vector3(0, 2.2, 0.8), Color(0.3, 0.8, 1.0))
	# LA LLAVE DEL VAPOR: un volante en la pared norte, al final de la tuberia de vapor (que llega hasta ella: sube del
	# cuerpo de la valvula y va por la pared hasta donde empieza la del mapa, en x 78)
	var ll := _v(c["llave"])
	var mv := Mandos.en_pared(world, "volante", self, ll + Vector3(0, 1.2, 0.4), Vector3(0, 0, 1), 1.3)
	_mandos4["p06_llave"] = mv
	_chapa_volante4(mv)
	var oxido := _mm(Color(0.42, 0.24, 0.14), 0.7, 0.6)
	var cuerpo := mv.position + Vector3(0, 0, 0.08)
	var alto_tubo := y + 2.0
	_tubo4(self, cuerpo + Vector3(0, 0.06, 0), Vector3(cuerpo.x, alto_tubo, cuerpo.z), 0.07, oxido)
	_tubo4(self, Vector3(cuerpo.x, alto_tubo, cuerpo.z - 0.07), Vector3(cuerpo.x, alto_tubo, float(z[0]) + 0.3), 0.07, oxido)
	_tubo4(self, Vector3(cuerpo.x - 0.07, alto_tubo, float(z[0]) + 0.3), Vector3(78.2, alto_tubo, float(z[0]) + 0.3), 0.12, oxido)


## Cada chorro sopla 1,6 s y calla 1,6 s, cada uno un poco despues que el de al lado: una ola que se cruza
## esperando en los huecos entre chorros.
func _vapor_tick(dt: float) -> void:
	if not _vapor_on or _chorros.is_empty():
		return
	_vapor_t += dt
	var c := _c("p06_vapor")
	var z: Array = c["z"]
	var y := float(c["y"])
	for k in _chorros.size():
		var ch: Dictionary = _chorros[k]
		var on: bool = fmod(_vapor_t + k * 0.8, 3.2) < 1.6
		if on != bool(ch["on"]):
			ch["on"] = on
			(ch["parts"] as CPUParticles3D).emitting = on
			var au = ch["audio"]
			if au and is_instance_valid(au):
				(au as AudioStreamPlayer3D).volume_db = (-2.0 if on else -40.0) + Audio.master_db
		if on and is_instance_valid(jugador) and not bool(jugador.get("spectating")):
			var jp: Vector3 = jugador.global_position
			if absf(jp.x - float(ch["x"])) < 0.9 and jp.z > float(z[0]) and jp.z < float(z[1]) and absf(jp.y - y) < 1.5:
				_dano_local(22.0 * dt, Vector3(0, 0, 1.5), "¡VAPOR!")


func _p06_resuelto(ya: bool) -> void:
	_quitar_cartel("vapor")
	_quitar_cartel("llave_vapor")
	_vapor_on = false
	for ch in _chorros:
		(ch["parts"] as CPUParticles3D).emitting = false
		var au = ch["audio"]
		if au and is_instance_valid(au):
			(au as AudioStreamPlayer3D).queue_free()
	if ya:
		_mando_hecho4("p06_llave")
	else:
		_pulsar4("p06_llave")
		Audio.play3d("gen/valvula/giro", _v(_c("p06_vapor").get("llave", [0, 0, 0])) + Vector3.UP, 2.0, 0.05, 40.0, Audio.PRI_HIGH)
		_mensaje_local("¡VAPOR CERRADO!")





# ======================================================================================================
# 7. LAS VALVULAS EN ORDEN
# ======================================================================================================
func _montar_p07() -> void:
	var c := _c("p07_valvulas")
	if c.is_empty():
		return
	var y := float(c["y"])
	var z := float(c["z"])
	for i in (c["x"] as Array).size():
		var x := float(c["x"][i])
		var rueda := Node3D.new()
		add_child(rueda)
		rueda.global_position = Vector3(x, y + 1.4, z + 1.25)
		_cil_mesh(rueda, 0.55, 0.08, Vector3.ZERO, _mm(Color(0.5, 0.5, 0.5), 0.6, 0.5), Vector3(PI / 2, 0, 0), 20)
		_cil_mesh(rueda, 0.45, 0.1, Vector3.ZERO, _mm(Color(0.2, 0.2, 0.2), 0.6, 0.5), Vector3(PI / 2, 0, 0), 20)
		for k in 3:
			var radio := _caja_mesh(rueda, Vector3(0.9, 0.07, 0.07), Vector3.ZERO, _mm(Color(0.5, 0.5, 0.5), 0.6, 0.5))
			radio.rotation.z = k * PI / 3
		_valv_nodos.append(rueda)
		var lamp := _esfera_mesh(self, 0.08, Vector3.ZERO, _brillo(Color(0.3, 0.3, 0.3), 0.3))
		lamp.global_position = Vector3(x, y + 2.35, z + 1.0)
		_valv_luces.append(lamp)
	# LA PIZARRA: un acertijo con el orden (lo escribe el anfitrion)
	var pz: Vector3 = _v(c["pizarra"])
	for k in 4:
		var l := _texto3d("", pz + Vector3(0, 0.45 - k * 0.3, 0.15), Color(0.95, 0.95, 0.92), 26, false)
		l.outline_size = 4
		_pizarra.append(l)
	# la compuerta a la escalera
	var r: Array = c["compuerta"]
	var tam := _mx(r) - _mn(r)
	_p07_compuerta = _estatico("CompuertaValvulas", _centro(r))
	_colision_caja(_p07_compuerta, tam, Vector3.ZERO)
	_caja_mesh(_p07_compuerta, tam, Vector3.ZERO, _mm(Color(0.3, 0.33, 0.34), 0.8, 0.45))
	for k in 3:
		_caja_mesh(_p07_compuerta, Vector3(tam.x + 0.06, 0.1, tam.z), Vector3(0, -0.9 + k * 0.9, 0), _mm(Color(0.2, 0.22, 0.22), 0.8, 0.5))
	_p07_barrera = AABB(_mn(r) - Vector3(1.0, 0.5, 0.2), tam + Vector3(2.0, 1.0, 0.4))
	CriaturaScript.barreras.append(_p07_barrera)
	_rotulo("valvulas", "EL ORDEN ESTÁ EN LA PIZARRA DEL VIGILANTE", Vector3(53.0, y + 3.6, 46.0), Color(0.3, 0.8, 1.0))


func _valvulas_colores() -> void:
	var col: Array = par.get("valv_colores", [0, 1, 2])
	for i in mini(_valv_nodos.size(), col.size()):
		var rueda: Node3D = _valv_nodos[i]
		var m := _mm(COLOR_VALV[int(col[i])], 0.4, 0.5)
		for ch in rueda.get_children():
			if ch is MeshInstance3D:
				(ch as MeshInstance3D).material_override = m
				break


func _pizarra_texto() -> void:
	if _pizarra.size() < 4:
		return
	var col: Array = par.get("valv_colores", [0, 1, 2])
	var orden: Array = par.get("valv_orden", [0, 1, 2])
	(_pizarra[0] as Label3D).text = "MANIOBRA DEL DESAGÜE:"
	for k in 3:
		var pos_i := int(orden[k])
		(_pizarra[k + 1] as Label3D).text = "%dº  %s" % [k + 1, ACERTIJO[int(col[pos_i])]]


func _valvula_giro(i: int, paso: int) -> void:
	if i >= 0 and i < _valv_nodos.size():
		var rueda: Node3D = _valv_nodos[i]
		rueda.create_tween().tween_property(rueda, "rotation:z", rueda.rotation.z + TAU, 1.2).set_trans(Tween.TRANS_SINE)
		Audio.play3d("gen/valvula/giro", rueda.global_position, 0.0, 0.05, 30.0, Audio.PRI_MID)
		(_valv_luces[i] as MeshInstance3D).material_override = _brillo(Color(0.1, 0.95, 0.25), 2.0)
	_valv_paso = paso


func _valvula_mal() -> void:
	_valv_paso = 0
	for l in _valv_luces:
		(l as MeshInstance3D).material_override = _brillo(Color(0.9, 0.1, 0.05), 2.0)
	var c := _c("p07_valvulas")
	var p := Vector3(53.0, float(c.get("y", 19.0)) + 2.0, 45.0)
	var estallido := _particulas(self, p, 70, 1.6, Color(0.95, 0.95, 0.95, 0.8), Color(0.8, 0.8, 0.8), 1.6, false)
	estallido.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	estallido.emission_box_extents = Vector3(5.0, 0.5, 1.0)
	estallido.direction = Vector3(0, -0.3, 1)
	estallido.spread = 50.0
	estallido.initial_velocity_min = 3.0
	estallido.initial_velocity_max = 6.0
	estallido.one_shot = true
	Audio.play3d("gen/vapor/estallido", p, 6.0, 0.03, 60.0, Audio.PRI_HIGH)
	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(estallido):
			estallido.queue_free()
		for l in _valv_luces:
			if is_instance_valid(l):
				(l as MeshInstance3D).material_override = _brillo(Color(0.3, 0.3, 0.3), 0.3))
	if is_instance_valid(jugador) and jugador.global_position.distance_to(p) < 6.0:
		_dano_local(8.0, Vector3.ZERO, "¡ORDEN EQUIVOCADO! El vapor revienta")
	_mensaje_local("¡ORDEN EQUIVOCADO! Vuelve a leer la pizarra")


func _p07_resuelto(ya: bool) -> void:
	_quitar_cartel("valvulas")
	for l in _valv_luces:
		(l as MeshInstance3D).material_override = _brillo(Color(0.1, 0.95, 0.25), 2.0)
	CriaturaScript.barreras.erase(_p07_barrera)
	if not is_instance_valid(_p07_compuerta):
		return
	_sin_colision(_p07_compuerta)
	if ya:
		_p07_compuerta.global_position.y += 2.7
		return
	_p07_compuerta.create_tween().tween_property(_p07_compuerta, "global_position:y", _p07_compuerta.global_position.y + 2.7, 3.0).set_trans(Tween.TRANS_SINE)
	Audio.play3d("gen/persiana/sube", _p07_compuerta.global_position, 4.0, 0.02, 50.0, Audio.PRI_HIGH)
	_mensaje_local("¡LA COMPUERTA SE ABRE! Bajad por la escalera")


# ======================================================================================================
# 8. LA ESCLUSA
# ======================================================================================================
func _montar_p08() -> void:
	var c := _c("p08_esclusa")
	if c.is_empty():
		return
	var gris := _mm(Color(0.3, 0.33, 0.34), 0.8, 0.45)
	var franja := _mm(Color(0.85, 0.66, 0.08), 0.4, 0.5)
	for k in 2:
		var r: Array = c["a"] if k == 0 else c["b"]
		var tam := _mx(r) - _mn(r)
		var sb := _estatico("EsclusaA" if k == 0 else "EsclusaB", _centro(r))
		_colision_caja(sb, tam, Vector3.ZERO)
		_caja_mesh(sb, tam, Vector3.ZERO, gris)
		_caja_mesh(sb, tam + Vector3(0.02, -tam.y + 0.25, 0.02), Vector3(0, -tam.y / 2 + 0.3, 0), franja)
		_cil_mesh(sb, 0.35, 0.1, Vector3(0, 0.1, 0), _mm(Color(0.5, 0.1, 0.08), 0.5, 0.5), Vector3(0, 0, PI / 2) if k == 0 else Vector3(PI / 2, 0, 0), 16)
		if k == 0:
			_p08_a = sb
			sb.global_position.y += 2.6          # la A empieza abierta (se entra por ella)
			_sin_colision(sb)
		else:
			_p08_b = sb
			_p08_barrera = AABB(_mn(r) - Vector3(0.3, 0.5, 0.6), tam + Vector3(0.6, 1.0, 1.2))
			CriaturaScript.barreras.append(_p08_barrera)
	# LA PALANCA DE LA ESCLUSA, atornillada en la pared norte, y encima su letrero pintado en el hormigon (antes era una
	# caja con una bola: no se veia que se pudiera bajar nada)
	var pl := _v(c["palanca"])
	var mp := Mandos.en_pared(world, "palanca", self, pl + Vector3(0, 1.3, 0.4), Vector3(0, 0, 1), 1.3)
	_mandos4["p08_palanca"] = mp
	var letrero := _texto3d("ESCLUSA\nCERRAR A · ABRIR B", mp.position + Vector3(0, 0.75, 0.02), Color(0.92, 0.85, 0.55), 26, false)
	letrero.pixel_size = 0.0045
	letrero.outline_size = 4
	_rotulo("esclusa", "TODOS DENTRO Y CERRAD LA COMPUERTA", pl + Vector3(-2.0, 2.6, 2.0), Color(0.3, 0.8, 1.0))


func _p08_resuelto(ya: bool) -> void:
	_quitar_cartel("esclusa")
	var r: Array = _c("p08_esclusa").get("a", [0, 0, 0, 0, 0, 0])
	var ya_y := float(r[1]) + (float(r[4]) - float(r[1])) / 2
	if ya:
		if is_instance_valid(_p08_a):
			_p08_a.global_position.y = ya_y
			_con_colision(_p08_a)
		_p08_abrir_b(true)
		return
	_p08_estado = 1
	if is_instance_valid(_p08_a):
		var tw := _p08_a.create_tween()
		tw.tween_property(_p08_a, "global_position:y", ya_y, 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			_con_colision(_p08_a)
			Audio.bf3d("destru/metal", _p08_a.global_position, 4.0, 40.0, Audio.PRI_HIGH))
	# la palanca baja y su piloto se pone ROJO mientras se iguala la presion (verde cuando se abre la B)
	_pulsar4("p08_palanca", false)
	_piloto4(_mandos4.get("p08_palanca"), "alarma")
	var c := _c("p08_esclusa")
	var rr: Array = c["rect"]
	var cen := Vector3((float(rr[0]) + float(rr[2])) / 2, float(c["suelo"]) + 3.0, (float(rr[1]) + float(rr[3])) / 2)
	get_tree().create_timer(2.2).timeout.connect(func():
		Audio.play3d("gen/esclusa/silbido", cen, 4.0, 0.02, 40.0, Audio.PRI_HIGH)
		var gotas := _particulas(self, cen, 40, 1.2, Color(0.7, 0.8, 0.9, 0.6), Color(0.6, 0.7, 0.8), 0.25, false)
		gotas.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		gotas.emission_box_extents = Vector3(3.5, 0.2, 3.0)
		gotas.gravity = Vector3(0, -9.8, 0)
		get_tree().create_timer(5.0).timeout.connect(func():
			if is_instance_valid(gotas):
				gotas.queue_free())
		_mensaje_local("IGUALANDO LA PRESIÓN…"))
	get_tree().create_timer(7.5).timeout.connect(func(): _p08_abrir_b(false))


func _p08_abrir_b(ya: bool) -> void:
	_p08_estado = 2
	CriaturaScript.barreras.erase(_p08_barrera)
	if ya:
		_mando_hecho4("p08_palanca")
	else:
		_piloto4(_mandos4.get("p08_palanca"), "hecho")
	if not is_instance_valid(_p08_b):
		return
	_sin_colision(_p08_b)
	if ya:
		_p08_b.global_position.y += 2.6
		return
	_p08_b.create_tween().tween_property(_p08_b, "global_position:y", _p08_b.global_position.y + 2.6, 2.4).set_trans(Tween.TRANS_SINE)
	Audio.play3d("gen/persiana/sube", _p08_b.global_position, 3.0, 0.02, 40.0, Audio.PRI_HIGH)
	_mensaje_local("¡LA COMPUERTA B SE ABRE! A la central")


# ======================================================================================================
# 9. LAS TUBERIAS
# ======================================================================================================
## Direcciones: 0 arriba, 1 derecha (vista de frente), 2 abajo, 3 izquierda
static func _aberturas(tipo: String, rot: int) -> Array:
	var base := [1, 3] if tipo == "recto" else [0, 1]
	var out: Array = []
	for o in base:
		out.append((int(o) + rot) % 4)
	return out


static func _flujo(tipo: Array, rot: Array) -> Array:
	var f := 0
	var c := 0
	var entra := 3
	var vistas: Array = []
	for _paso in 12:
		if f < 0 or f > 2 or c < 0 or c > 2:
			return [vistas, false]
		var i := f * 3 + c
		var ab := _aberturas(String(tipo[i]), int(rot[i]))
		if not (entra in ab):
			return [vistas, false]
		vistas.append(i)
		var sale := -1
		for o in ab:
			if int(o) != entra:
				sale = int(o)
		if f == 2 and c == 2 and sale == 1:
			return [vistas, true]
		match sale:
			0: f -= 1
			1: c += 1
			2: f += 1
			3: c -= 1
		entra = (sale + 2) % 4
	return [vistas, false]


func _generar_tubos() -> Dictionary:
	var movs := [1, 1, 2, 2]
	movs.shuffle()
	var camino: Array = [[0, 0]]
	var f := 0
	var c := 0
	for m in movs:
		if int(m) == 1:
			c += 1
		else:
			f += 1
		camino.append([f, c])
	var tipo: Array = []
	var rot: Array = []
	for i in 9:
		tipo.append("recto" if randf() < 0.45 else "codo")
		rot.append(randi() % 4)
	var entra := 3
	for k in camino.size():
		var ff := int(camino[k][0])
		var cc := int(camino[k][1])
		var sale := 1
		if k + 1 < camino.size():
			sale = 1 if int(camino[k + 1][1]) > cc else 2
		tipo[ff * 3 + cc] = "recto" if (entra + 2) % 4 == sale else "codo"
		entra = (sale + 2) % 4
	var intentos := 0
	while bool(_flujo(tipo, rot)[1]) or (_flujo(tipo, rot)[0] as Array).size() > 2:
		for i in 9:
			rot[i] = randi() % 4
		intentos += 1
		if intentos > 50:
			break
	return {"tipo": tipo, "rot": rot}


func _tubo_pos(i: int) -> Vector3:
	var c := _c("p09_tubos")
	var cen := _v(c.get("centro", [0, 0, 0]))
	var paso := float(c.get("paso", 0.95))
	var f := i / 3
	var col := i % 3
	return Vector3(cen.x + (1 - col) * paso, cen.y + (1 - f) * paso, cen.z - 0.14)


func _montar_p09() -> void:
	var c := _c("p09_tubos")
	if c.is_empty():
		return
	for i in 9:
		var n := Node3D.new()
		add_child(n)
		n.global_position = _tubo_pos(i)
		_caja_mesh(n, Vector3(0.85, 0.85, 0.06), Vector3(0, 0, 0.06), _mm(Color(0.15, 0.17, 0.18), 0.5, 0.6))
		var brazos := Node3D.new()
		n.add_child(brazos)
		_tubos_nodos.append(brazos)
	var cen := _v(c["centro"])
	_texto3d("BOMBAS DE ACHIQUE · UNID LA ENTRADA CON LA SALIDA", cen + Vector3(0, 1.75, -0.2), Color(0.95, 0.9, 0.8), 24, false, null, PI)
	_texto3d("ENTRADA ▶", _tubo_pos(0) + Vector3(0.95, 0.35, -0.05), Color(0.4, 0.8, 1.0), 22, false, null, PI)
	_texto3d("▶ SALIDA", _tubo_pos(8) + Vector3(-0.95, -0.35, -0.05), Color(0.4, 0.8, 1.0), 22, false, null, PI)
	_rotulo("tubos", "PANEL DE LAS BOMBAS · girad los codos", cen + Vector3(0, 2.4, -1.2), Color(0.3, 0.8, 1.0))
	_pozo_agua_y = float(c.get("agua", 5.4))


func _tubos_montar_piezas() -> void:
	_tubos_refrescar()


func _tubos_refrescar() -> void:
	var t: Dictionary = par.get("tubos", {})
	if t.is_empty() or _tubos_nodos.size() < 9:
		return
	var tipo: Array = t["tipo"]
	if _tubos_rot.size() < 9:
		_tubos_rot = (t["rot"] as Array).duplicate()
	var fl := _flujo(tipo, _tubos_rot)
	var vistas: Array = fl[0]
	var gris := _mm(Color(0.55, 0.56, 0.58), 0.7, 0.4)
	var agua := _brillo(Color(0.2, 0.55, 1.0), 2.2)
	var dirs := [Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, -1, 0), Vector3(1, 0, 0)]
	for i in 9:
		var brazos: Node3D = _tubos_nodos[i]
		for ch in brazos.get_children():
			ch.queue_free()
		var mat: Material = agua if i in vistas else gris
		_cil_mesh(brazos, 0.12, 0.14, Vector3(0, 0, -0.04), mat, Vector3(PI / 2, 0, 0), 10)
		for o in _aberturas(String(tipo[i]), int(_tubos_rot[i])):
			var d: Vector3 = dirs[int(o)]
			var tam := Vector3(0.43, 0.14, 0.12) if absf(d.x) > 0.5 else Vector3(0.14, 0.43, 0.12)
			_caja_mesh(brazos, tam, d * 0.215 + Vector3(0, 0, -0.04), mat)


func _p09_resuelto(ya: bool) -> void:
	_quitar_cartel("tubos")
	_tubos_refrescar()
	if ya:
		_pozo_nivel(float(_c("p09_tubos").get("vacia", 0.5)))
		return
	var pozo: Array = _c("p09_tubos").get("pozo", [98, 70, 110, 82])
	var cen := Vector3((float(pozo[0]) + float(pozo[2])) / 2, 6.0, (float(pozo[1]) + float(pozo[3])) / 2)
	Audio.play3d("gen/generador/arranque", cen, 4.0, 0.02, 80.0, Audio.PRI_HIGH)
	var ruido := _bucle_directo("res://sounds/gen/generador/bucle1.ogg", self, Vector3.ZERO, 0.0, 70.0)
	if ruido:
		ruido.global_position = cen
	var gluglu := _bucle_bf("bf/amb/bucle_rio", self, Vector3.ZERO, 2.0, 40.0)
	if gluglu:
		gluglu.global_position = cen + Vector3(0, -3, 0)
	_pozo_vaciando = true
	var tw := create_tween()
	tw.tween_method(_pozo_nivel, _pozo_agua_y, float(_c("p09_tubos").get("vacia", 0.5)), 18.0).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		_pozo_vaciando = false
		if is_instance_valid(ruido):
			ruido.queue_free()
		if is_instance_valid(gluglu):
			gluglu.queue_free()
		_mensaje_local("EL POZO ESTÁ VACÍO · la GRÚA tiene corriente"))
	_mensaje_local("¡LAS BOMBAS VACÍAN EL POZO!")


## El agua del pozo: la lamina de agua.gd baja (y con ella el nado)
func _pozo_nivel(y: float) -> void:
	_pozo_agua_y = y
	var ag = preload("res://scripts/agua.gd").actual
	if ag == null or not is_instance_valid(ag):
		return
	var pozo: Array = _c("p09_tubos").get("pozo", [98, 70, 110, 82])
	var r := Rect2(float(pozo[0]), float(pozo[1]), float(pozo[2]) - float(pozo[0]), float(pozo[3]) - float(pozo[1]))
	var cuerpos: Array = ag.get("cuerpos")
	var planos: Array = ag.get("_planos")
	var desp := planos.size() - cuerpos.size()          # el mar va primero si lo hay
	for i in cuerpos.size():
		var rr: Rect2 = cuerpos[i]["rect"]
		if rr.position.distance_to(r.position) < 0.5 and rr.size.distance_to(r.size) < 0.5:
			cuerpos[i]["y"] = y
			var pl = planos[i + desp] if i + desp < planos.size() else null
			if pl and is_instance_valid(pl):
				(pl as Node3D).position.y = y
				(pl as Node3D).visible = y > 1.0


# ======================================================================================================
# 10. EL PUENTE GRUA
# ======================================================================================================
func _montar_p10() -> void:
	var c := _c("p10_grua")
	if c.is_empty():
		return
	var gy := float(c["y"])
	var z: Array = c["z"]
	var z0 := float(z[0])
	var z1 := float(z[1])
	var amarillo := _mm(Color(0.86, 0.66, 0.1), 0.5, 0.5)
	var negro := _mm(Color(0.08, 0.08, 0.08), 0.6, 0.5)
	_grua_puente = Node3D.new()
	add_child(_grua_puente)
	_grua_puente.global_position = Vector3(float(c.get("x0", 70.0)), gy, (z0 + z1) / 2)
	var largo := z1 - z0 - 0.2
	for s in [-0.45, 0.45]:
		_caja_mesh(_grua_puente, Vector3(0.35, 1.1, largo), Vector3(s, 0, 0), amarillo)
	for k in int(largo / 2.0):
		_caja_mesh(_grua_puente, Vector3(0.9, 0.1, 0.1), Vector3(0, 0.5, -largo / 2 + 1.0 + k * 2.0), negro)
	for s in [-1.0, 1.0]:
		_caja_mesh(_grua_puente, Vector3(2.2, 0.8, 0.8), Vector3(0, -0.2, s * (largo / 2 - 0.3)), amarillo)
	_caja_mesh(_grua_puente, Vector3(0.95, 0.5, 4.0), Vector3(0, 0.1, 0), _mm(Color(0.1, 0.1, 0.1), 0.3, 0.5))
	_texto3d("25 t", Vector3(0.62, 0, 3.0), Color(0.05, 0.05, 0.05), 60, false, _grua_puente, PI / 2)
	_grua_carro = Node3D.new()
	_grua_puente.add_child(_grua_carro)
	_grua_carro.position = Vector3(0, 0.75, 0)
	_caja_mesh(_grua_carro, Vector3(1.6, 0.7, 1.8), Vector3.ZERO, _mm(Color(0.25, 0.27, 0.28), 0.7, 0.5))
	_cil_mesh(_grua_carro, 0.35, 1.4, Vector3(0, 0.1, 0), negro, Vector3(0, 0, PI / 2), 12)
	_grua_gancho = Node3D.new()
	add_child(_grua_gancho)
	_grua_gancho.global_position = _grua_puente.global_position + Vector3(0, -4.0, 0)
	_caja_mesh(_grua_gancho, Vector3(0.5, 0.7, 0.4), Vector3.ZERO, amarillo)
	_cil_mesh(_grua_gancho, 0.22, 0.12, Vector3(0, -0.5, 0), negro, Vector3(PI / 2, 0, 0), 12)
	var cable_mat := _mm(Color(0.1, 0.1, 0.1), 0.6, 0.5)
	for s in [-0.12, 0.12]:
		_grua_cables.append(_cuerda(cable_mat, 0.025))
	# EL RODETE: de pie contra la boca del desague, en el fondo del pozo
	var rp := _v(c["rotor"])
	var rr := float(c.get("rotor_r", 2.2))
	_rotor = _estatico("Rodete", rp)
	_colision_caja(_rotor, Vector3(rr * 2.0, rr * 2.0, 1.0), Vector3.ZERO)
	var bronce := _mm(Color(0.55, 0.42, 0.22), 0.8, 0.4)
	_cil_mesh(_rotor, rr, 0.35, Vector3(0, 0, -0.3), bronce, Vector3(PI / 2, 0, 0), 24)
	_cil_mesh(_rotor, rr * 0.55, 0.9, Vector3.ZERO, bronce, Vector3(PI / 2, 0, 0), 20)
	for k in 12:
		var ala := _caja_mesh(_rotor, Vector3(rr * 0.9, 0.12, 0.6), Vector3(0, 0, 0.1), bronce)
		ala.rotation = Vector3(0, 0.3, k * TAU / 12)
		ala.position = Vector3(cos(k * TAU / 12), sin(k * TAU / 12), 0) * rr * 0.62 + Vector3(0, 0, 0.1)
	_cil_mesh(_rotor, 0.35, 1.2, Vector3(0, 0, 0.5), _mm(Color(0.3, 0.3, 0.3), 0.8, 0.4), Vector3(PI / 2, 0, 0), 12)
	_rotulo("mando_grua", "MANDO DE LA GRÚA", _v(c["mando"]) + Vector3(0, 2.2, -0.4), Color(0.95, 0.75, 0.1))
	# EL MANDO DE LA GRUA: el pupitre amarillo del mapa (1,1 m) estaba pelado. Encima, al fondo, su tablero de chapa
	# con la palanca de maniobra, un reloj de carga y su placa
	var mg := _v(c["mando"])
	var tapa := _suelo4(mg + Vector3(0, 1.1, -0.1), 0.6)
	var gris := _mm(Color(0.3, 0.32, 0.33), 0.7, 0.45)
	_caja_mesh(self, Vector3(1.1, 1.0, 0.1), Vector3(mg.x, tapa + 0.5, mg.z + 0.22), gris)
	_caja_mesh(self, Vector3(1.16, 0.06, 0.16), Vector3(mg.x, tapa + 1.03, mg.z + 0.2), negro)
	var mgr := Mandos.crear("palanca", self, Vector3(mg.x - 0.25, tapa + 0.33, mg.z + 0.17), Vector3(0, 0, -1))
	_mandos4["p10_mando"] = mgr
	_cil_mesh(self, 0.1, 0.03, Vector3(mg.x + 0.28, tapa + 0.5, mg.z + 0.16), negro, Vector3(PI / 2, 0, 0), 16)
	_cil_mesh(self, 0.085, 0.02, Vector3(mg.x + 0.28, tapa + 0.5, mg.z + 0.145), _mm(Color(0.93, 0.92, 0.86), 0.0, 0.5), Vector3(PI / 2, 0, 0), 16)
	var aguja := _caja_mesh(self, Vector3(0.012, 0.07, 0.004), Vector3(mg.x + 0.28 + 0.02, tapa + 0.52, mg.z + 0.132), _mm(Color(0.8, 0.1, 0.05), 0.0, 0.5))
	aguja.rotation.z = -0.6
	var placa := _texto3d("PUENTE GRÚA\n25 t", Vector3(mg.x + 0.3, tapa + 0.86, mg.z + 0.165), Color(0.95, 0.8, 0.2), 18, false, null, PI)
	placa.pixel_size = 0.004
	placa.outline_size = 0


func _grua_cables_tick() -> void:
	if not is_instance_valid(_grua_carro) or not is_instance_valid(_grua_gancho):
		return
	var arriba := _grua_carro.global_position
	for k in _grua_cables.size():
		var s := -0.12 if k == 0 else 0.12
		_linea(_grua_cables[k], arriba + Vector3(s, -0.3, 0), _grua_gancho.global_position + Vector3(s, 0.35, 0))


## La maniobra entera (la misma en todas las maquinas): el puente al pozo, el carro sobre el rodete, el gancho
## baja, engancha, sube, el puente a la zona de descarga, baja, suelta y sube.
func _p10_maniobra(ya: bool) -> void:
	var c := _c("p10_grua")
	var rp := _v(c["rotor"])
	var rr := float(c.get("rotor_r", 2.2))
	var desc := _v(c["descarga"])
	var gy := float(c["y"])
	var z: Array = c["z"]
	var zc := (float(z[0]) + float(z[1])) / 2
	if ya:
		if is_instance_valid(_rotor):
			_rotor.global_position = desc + Vector3(0, 0.5, 0)
			_rotor.rotation.x = PI / 2
		_grua_puente.global_position.x = desc.x
		return
	_grua_ocupada = true
	_quitar_cartel("mando_grua")
	_grua_ruido = _bucle_directo("res://sounds/gen/ascensor/bucle1.ogg", _grua_puente, Vector3(0, 0.5, 0), 0.0, 60.0)
	Audio.play3d("gen/ascensor/arranque", _grua_puente.global_position, 2.0, 0.0, 60.0, Audio.PRI_HIGH)
	var tw := create_tween()
	tw.set_parallel(false)
	var dx := absf(_grua_puente.global_position.x - rp.x)
	tw.tween_property(_grua_puente, "global_position:x", rp.x, maxf(1.5, dx / 5.0)).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(_grua_gancho, "global_position:x", rp.x, maxf(1.5, dx / 5.0)).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_grua_carro, "position:z", rp.z - zc, 2.0).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(_grua_gancho, "global_position:z", rp.z, 2.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_grua_gancho, "global_position:y", rp.y + rr + 0.5, 4.0).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		Audio.bf3d("destru/metal", _grua_gancho.global_position, 2.0, 40.0, Audio.PRI_HIGH)
		if is_instance_valid(_rotor):
			_sin_colision(_rotor)
			_rotor.reparent(_grua_gancho, true))
	tw.tween_interval(0.6)
	tw.tween_property(_grua_gancho, "global_position:y", gy - 3.0, 4.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_grua_puente, "global_position:x", desc.x, 3.0).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(_grua_gancho, "global_position:x", desc.x, 3.0).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(_grua_carro, "position:z", desc.z - zc, 3.0).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(_grua_gancho, "global_position:z", desc.z, 3.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_grua_gancho, "global_position:y", desc.y + rr * 2.0 + 0.55, 3.5).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		if is_instance_valid(_rotor):
			_rotor.reparent(self, true)
			var tr := _rotor.create_tween()
			tr.tween_property(_rotor, "rotation:x", PI / 2, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tr.parallel().tween_property(_rotor, "global_position:y", desc.y + 0.5, 0.8)
			tr.tween_callback(func():
				_con_colision(_rotor)
				_golpe(_rotor.global_position, 1.4, "destru/metal")))
	tw.tween_interval(1.0)
	tw.tween_property(_grua_gancho, "global_position:y", gy - 3.0, 2.5).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		_grua_ocupada = false
		if is_instance_valid(_grua_ruido):
			_grua_ruido.queue_free()
		Audio.play3d("gen/ascensor/parada", _grua_puente.global_position, 0.0, 0.0, 50.0, Audio.PRI_MID))


func _p10_resuelto(ya: bool) -> void:
	_quitar_cartel("mando_grua")
	if ya:
		_mando_hecho4("p10_mando")
	else:
		_pulsar4("p10_mando")
	_p10_maniobra(ya)
	if not ya:
		_mensaje_local("LA GRÚA SACA EL RODETE DEL POZO…")


# ======================================================================================================
# 11 y 20. LO QUE SE LLEVA A CUESTAS: la bombona y los bidones
# ======================================================================================================


func _montar_p11() -> void:
	var c := _c("p11_bombona")
	if not c.is_empty():
		_obj_crear("bombona", "bombona", _v(c["pos"]))
		_montar_mecha()
		_rotulo("bombona", "BOMBONA DE PROPANO", _v(c["pos"]) + Vector3(0, 1.7, 0), Color(0.95, 0.5, 0.1))
		_rotulo("derrumbe", "DERRUMBE · haría falta algo que explote", _v(c["marca"]) + Vector3(0, 2.2, 0), Color(0.95, 0.3, 0.1))
















## LA MECHA de la bombona: negra, encintada al costado, baja al suelo y acaba en el mechero rojo (de tirar). Antes no
## habia mecha ninguna y "ENCENDER LA MECHA" salia en el aire. Se ve con la bombona en el suelo; en brazos no.
func _montar_mecha() -> void:
	var o: Dictionary = _obj4.get("bombona", {})
	if o.is_empty() or not is_instance_valid(o["nodo"]):
		return
	var bn: Node3D = o["nodo"]
	_mecha_nodo = Node3D.new()
	_mecha_nodo.name = "Mecha"
	bn.add_child(_mecha_nodo)
	var negro := _mm(Color(0.05, 0.05, 0.05), 0.0, 0.8)
	# del mechero (en el suelo) al grifo de la bombona: por ahi corre la chispa al encenderla. Sale hacia el OESTE (-X):
	# en el taller la bombona tiene el banco al este, y en la marca el derrumbe tambien esta al este
	_mecha_puntos = [Vector3(-0.64, 0.03, 0.34), Vector3(-0.5, 0.025, 0.42), Vector3(-0.36, 0.025, 0.3), Vector3(-0.25, 0.05, 0.12),
		Vector3(-0.215, 0.3, 0.07), Vector3(-0.215, 0.68, 0.07), Vector3(-0.16, 0.92, 0.05), Vector3(-0.075, 1.02, 0.03)]
	for k in range(_mecha_puntos.size() - 1):
		_tubo4(_mecha_nodo, _mecha_puntos[k], _mecha_puntos[k + 1], 0.013, negro, 6)
	_tubo4(_mecha_nodo, Vector3(-0.64, 0.035, 0.34), Vector3(-0.8, 0.04, 0.3), 0.024, _mm(Color(0.8, 0.12, 0.06), 0.2, 0.5), 8)
	# el rollo que sobra, en el suelo, y la cinta americana que la sujeta
	var rollo := MeshInstance3D.new()
	var tro := TorusMesh.new()
	tro.inner_radius = 0.07
	tro.outer_radius = 0.1
	rollo.mesh = tro
	rollo.material_override = negro
	rollo.position = Vector3(-0.5, 0.015, 0.58)
	rollo.scale = Vector3(1.0, 0.5, 1.0)
	_mecha_nodo.add_child(rollo)
	for yy in [0.3, 0.64]:
		var cinta := MeshInstance3D.new()
		var tc := TorusMesh.new()
		tc.inner_radius = 0.198
		tc.outer_radius = 0.23
		tc.rings = 20
		cinta.mesh = tc
		cinta.material_override = _mm(Color(0.6, 0.6, 0.57), 0.1, 0.6)
		cinta.position = Vector3(0, yy, 0)
		cinta.scale = Vector3(1.0, 0.8, 1.0)
		_mecha_nodo.add_child(cinta)
	_mecha_ver()


func _mecha_ver() -> void:
	if not is_instance_valid(_mecha_nodo):
		return
	var o: Dictionary = _obj4.get("bombona", {})
	_mecha_nodo.visible = not o.is_empty() and String(o["estado"]) != "lleva"


func _p11_mecha() -> void:
	var o: Dictionary = _obj4.get("bombona", {})
	if o.is_empty() or not is_instance_valid(o["nodo"]):
		return
	var n: Node3D = o["nodo"]
	_mecha_t = 6.0
	var chispas := _particulas(n, Vector3(0, 1.1, 0), 24, 0.5, Color(1.0, 0.8, 0.3, 1.0), Color(1.0, 0.3, 0.05), 0.12, true)
	chispas.direction = Vector3.UP
	chispas.spread = 60.0
	chispas.initial_velocity_min = 1.5
	chispas.initial_velocity_max = 3.0
	chispas.gravity = Vector3(0, -6, 0)
	# la chispa sale del mechero y corre por la mecha hasta el grifo (6 s: lo que tarda en reventar)
	if _mecha_puntos.size() >= 2:
		chispas.position = _mecha_puntos[0]
		var tw := chispas.create_tween()
		var tramo := 5.6 / float(_mecha_puntos.size() - 1)
		for k in range(1, _mecha_puntos.size()):
			tw.tween_property(chispas, "position", _mecha_puntos[k], tramo)
	_mecha_ruido = _bucle_directo("res://sounds/gen/mecha/chisporroteo1.ogg", chispas, Vector3.ZERO, 4.0, 40.0)
	Audio.bf3d("gadget/c4_activar", n.global_position, 2.0, 40.0, Audio.PRI_HIGH)
	_mensaje_local("¡MECHA ENCENDIDA! ¡ALEJAOS!")


func _p11_resuelto(ya: bool) -> void:
	_quitar_cartel("derrumbe")
	_quitar_cartel("bombona")
	var c := _c("p11_bombona")
	var d: Array = c.get("derrumbe", [0, 0, 0, 0, 0, 0])
	var o: Dictionary = _obj4.get("bombona", {})
	var p: Vector3 = _centro(d)
	if not o.is_empty():
		p = o["pos"]
		_obj_estado("bombona", "usado", 0, p)
	if is_instance_valid(_mecha_ruido):
		_mecha_ruido.queue_free()
	# el boquete garantizado (cada maquina: el tallado es determinista)
	var y0 := float(d[1])
	_tallar_rejilla(Vector3(float(d[0]) - 1.2, 0, 0), Vector3.RIGHT, float(d[3]) - float(d[0]) + 2.4,
		[y0 + 0.75, y0 + 1.4, y0 + 2.0, y0 + 2.6], [float(d[2]) + 0.5, (float(d[2]) + float(d[5])) / 2, float(d[5]) - 0.5],
		Vector3.UP, Vector3.BACK, 0.55)
	if ya:
		return
	var escena := get_tree().current_scene
	if escena and "effects" in escena and escena.effects and escena.effects.has_method("explosion"):
		escena.effects.explosion(p + Vector3.UP * 0.6, 4.0)
	Audio.explosion(p + Vector3.UP * 0.6, 4.0)
	if is_instance_valid(jugador):
		var dist: float = jugador.global_position.distance_to(p)
		if dist < 7.0 and jugador.has_method("take_damage") and not bool(jugador.get("invulnerable")):
			jugador.take_damage(80.0 * (1.0 - dist / 7.0), (jugador.global_position - p).normalized() * 6.0)
		if jugador.has_method("add_shake") and dist < 40.0:
			jugador.add_shake(clampf(0.8 * (1.0 - dist / 40.0), 0.1, 0.8))
	_mensaje_local("¡BOOM! El derrumbe ha volado")


# ======================================================================================================
# 12. LA VALLA ELECTRIFICADA
# ======================================================================================================
func _montar_p12() -> void:
	var c := _c("p12_valla")
	if c.is_empty():
		return
	var x := float(c["x"])
	var z: Array = c["z"]
	var y := float(c["y"])
	var z0 := float(z[0])
	var z1 := float(z[1])
	var alto := 3.0
	_valla = _estatico("VallaElectrica", Vector3(x, y + alto / 2, (z0 + z1) / 2))
	_colision_caja(_valla, Vector3(0.3, alto + 0.6, z1 - z0), Vector3(0, 0.3, 0))
	var metal := _mm(Color(0.45, 0.47, 0.48), 0.8, 0.45)
	var malla := _mm(Color(0.3, 0.32, 0.33), 0.8, 0.5)
	for zz in range(0, int(z1 - z0) + 1, 2):
		_caja_mesh(_valla, Vector3(0.1, alto + 0.6, 0.1), Vector3(0, 0.3 - (0.8 if z0 + zz > 100.0 else 0.0), -(z1 - z0) / 2 + zz), metal)
	for k in 7:
		_caja_mesh(_valla, Vector3(0.03, 0.03, z1 - z0), Vector3(0, -alto / 2 + 0.2 + k * 0.45, 0), malla)
	for k in int((z1 - z0) / 0.25):
		_caja_mesh(_valla, Vector3(0.02, alto, 0.02), Vector3(0, 0, -(z1 - z0) / 2 + k * 0.25), malla)
	for k in 5:
		_esfera_mesh(_valla, 0.06, Vector3(0, alto / 2 + 0.25, -(z1 - z0) / 2 + 0.5 + k * 1.0), _brillo(Color(0.4, 0.7, 1.0), 2.0))
	_texto3d("⚡ PELIGRO · ALTA TENSIÓN ⚡", Vector3(-0.2, 0.6, -(z1 - z0) / 2 + 2.0), Color(1.0, 0.85, 0.1), 40, false, _valla, -PI / 2)
	# las chispas y el zumbido
	for k in 3:
		var ch := _particulas(_valla, Vector3(-0.1, -alto / 2 + 0.6 + k * 0.9, -(z1 - z0) / 2 + 0.6 + k * 1.1), 18, 0.35, Color(0.7, 0.85, 1.0, 1.0), Color(0.3, 0.5, 1.0), 0.1, true)
		ch.spread = 180.0
		ch.initial_velocity_min = 1.5
		ch.initial_velocity_max = 4.0
		ch.gravity = Vector3(0, -9.8, 0)
		ch.emitting = false
		ch.one_shot = true
		_valla_parts.append(ch)
	_valla_ruido = _bucle_directo("res://sounds/gen/electrico/zumbido1.ogg", _valla, Vector3.ZERO, 0.0, 30.0)
	_valla_barrera = AABB(Vector3(x - 1.0, y - 1.0, z0 - 0.5), Vector3(2.0, alto + 3.0, z1 - z0 + 1.0))
	CriaturaScript.barreras.append(_valla_barrera)
	for i in (c["aisladores"] as Array).size():
		var a: Array = c["aisladores"][i]
		_rotulo("aislador%d" % i, "AISLADOR %d" % (i + 1), _centro(a) + Vector3(0, 1.3, 0.6), Color(0.3, 0.8, 1.0))
	_rotulo("valla", "REVENTAD LOS 3 AISLADORES DEL TRANSFORMADOR", Vector3(x - 3.0, y + 3.8, (z0 + z1) / 2 - 1.0), Color(1.0, 0.85, 0.1))


func _valla_tick(dt: float) -> void:
	if _h("p12") or not is_instance_valid(_valla):
		return
	_chispa_t -= dt
	if _chispa_t <= 0.0:
		_chispa_t = randf_range(0.6, 2.2)
		var ch: CPUParticles3D = _valla_parts[randi() % _valla_parts.size()]
		ch.restart()
		ch.emitting = true
	if not is_instance_valid(jugador) or bool(jugador.get("spectating")):
		return
	var c := _c("p12_valla")
	var jp: Vector3 = jugador.global_position
	var z: Array = c["z"]
	if absf(jp.x - float(c["x"])) < 0.75 and jp.z > float(z[0]) - 0.3 and jp.z < float(z[1]) + 0.3 and jp.y < float(c["y"]) + 3.5:
		var ahora := Time.get_ticks_msec() * 0.001
		if ahora - _dano_aviso_t > 0.7:
			_dano_aviso_t = ahora
			if jugador.has_method("take_damage") and not bool(jugador.get("invulnerable")):
				jugador.take_damage(18.0, Vector3(-4.0, 1.0, 0))
			jugador.global_position.x -= 0.6
			Audio.bf3d("gadget/desfib_descarga", jp + Vector3.UP, 2.0, 30.0, Audio.PRI_HIGH)
			_mensaje_local("¡CALAMBRAZO! La valla está electrificada")


func _p12_aislador(i: int) -> void:
	if i < 0 or i >= _aisladores_rotos.size() or bool(_aisladores_rotos[i]):
		return
	_aisladores_rotos[i] = true
	_quitar_cartel("aislador%d" % i)
	var a: Array = _c("p12_valla")["aisladores"][i]
	var p := _centro(a)
	var ch := _particulas(self, p, 40, 0.6, Color(0.8, 0.9, 1.0, 1.0), Color(0.3, 0.5, 1.0), 0.14, true)
	ch.spread = 180.0
	ch.initial_velocity_min = 3.0
	ch.initial_velocity_max = 7.0
	ch.gravity = Vector3(0, -9.8, 0)
	ch.one_shot = true
	get_tree().create_timer(2.0).timeout.connect(func():
		if is_instance_valid(ch):
			ch.queue_free())
	Audio.bf3d("gadget/desfib_descarga", p, 6.0, 60.0, Audio.PRI_HIGH)
	var rotos := 0
	for r in _aisladores_rotos:
		if bool(r):
			rotos += 1
	if rotos < 3:
		_mensaje_local("¡AISLADOR REVENTADO! (%d de 3)" % rotos)


func _p12_resuelto(ya: bool) -> void:
	_quitar_cartel("valla")
	for i in 3:
		_quitar_cartel("aislador%d" % i)
	CriaturaScript.barreras.erase(_valla_barrera)
	if is_instance_valid(_valla_ruido):
		_valla_ruido.queue_free()
	if not is_instance_valid(_valla):
		return
	_sin_colision(_valla)
	# la valla se viene abajo, tumbada hacia el rio (se pasa por encima)
	if ya:
		_valla.rotation.x = 0.0
		_valla.visible = false
		return
	var tw := _valla.create_tween()
	tw.tween_property(_valla, "rotation:z", -PI / 2 + 0.05, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_valla, "global_position:y", _valla.global_position.y - 1.2, 1.2)
	tw.tween_callback(func(): _golpe(_valla.global_position, 1.0, "destru/metal"))
	_mensaje_local("¡SIN CORRIENTE! La valla se cae")


# ======================================================================================================
# 13. LA BARCAZA
# ======================================================================================================
func _barcaza_z(k: float, fase_b: int) -> float:
	var z: Array = _c("p13_barcaza").get("z", [103.2, 118.8])
	var zn := float(z[0])
	var zs := float(z[1])
	match fase_b:
		0: return zs
		1: return lerpf(zs, zn, k)
		2: return zn
		3: return lerpf(zn, zs, k)
	return zs


func _montar_p13() -> void:
	var c := _c("p13_barcaza")
	if c.is_empty():
		return
	var tam: Array = c["tam"]
	var w := float(tam[0])
	var d := float(tam[1])
	var y := float(c["y"])
	_barcaza = _animable("Barcaza", Vector3(float(c["x"]), y - 0.2, _barcaza_z(0.0, 0)))
	var madera := _mm(Color(0.42, 0.3, 0.19), 0.0, 0.9)
	var madera2 := _mm(Color(0.34, 0.24, 0.15), 0.0, 0.9)
	var hierro := _mm(Color(0.15, 0.15, 0.16), 0.8, 0.5)
	_colision_caja(_barcaza, Vector3(w, 0.4, d), Vector3.ZERO)
	for i in int(w / 0.4):
		_caja_mesh(_barcaza, Vector3(0.38, 0.4, d), Vector3(-w / 2 + 0.2 + i * 0.4, 0, 0), madera if i % 2 == 0 else madera2)
	for s in [-1.0, 1.0]:
		_caja_mesh(_barcaza, Vector3(0.6, 0.7, d + 0.2), Vector3(s * (w / 2 + 0.2), -0.25, 0), hierro)      # flotadores
		_colision_caja(_barcaza, Vector3(0.1, 1.1, d), Vector3(s * (w / 2 - 0.05), 0.75, 0))                 # barandillas
		_caja_mesh(_barcaza, Vector3(0.06, 0.06, d), Vector3(s * (w / 2 - 0.05), 1.25, 0), hierro)
		for k in 5:
			_caja_mesh(_barcaza, Vector3(0.06, 1.05, 0.06), Vector3(s * (w / 2 - 0.05), 0.72, -d / 2 + 0.3 + k * (d - 0.6) / 4), hierro)
	# LAS DOS MANIVELAS: cada una en su torno (la caja del engranaje con el tambor del cable encima) y la manivela de
	# verdad en su costado, a la altura de la mano. Antes eran un disco rojo plano: no se veia que se girase.
	var gris := _mm(Color(0.34, 0.36, 0.34), 0.7, 0.45)
	var amarillo := _mm(Color(0.86, 0.66, 0.1), 0.4, 0.5)
	# la de a bordo, en el lado este (mira al oeste, a la cubierta): hija de la barcaza, se mueve con ella
	var tx := w / 2 - 0.9
	_caja_mesh(_barcaza, Vector3(0.5, 1.2, 0.62), Vector3(tx, 0.8, -1.0), gris)
	_caja_mesh(_barcaza, Vector3(0.54, 0.08, 0.66), Vector3(tx, 1.42, -1.0), amarillo)
	_cil_mesh(_barcaza, 0.17, 0.72, Vector3(tx + 0.02, 1.62, -1.0), hierro, Vector3(PI / 2, 0, 0), 14)
	_colision_caja(_barcaza, Vector3(0.5, 1.2, 0.62), Vector3(tx, 0.8, -1.0))
	_man2 = Mandos.crear("manivela", _barcaza, Vector3(tx - 0.25, 1.2, -1.0), Vector3.LEFT, true)
	_mandos4["p13_man2"] = _man2
	_piloto4(_man2, "apagado")
	# la de la orilla norte, sobre el pedestal de hormigon del mapa (0,8 m); mira al este, al embarcadero
	var mp := _v(c["manivela"])
	var ped := _suelo4(mp + Vector3(0, 0.8, 0), 0.6)
	_caja_mesh(self, Vector3(0.6, 0.56, 0.66), Vector3(mp.x, ped + 0.28, mp.z), gris)
	_caja_mesh(self, Vector3(0.64, 0.08, 0.7), Vector3(mp.x, ped + 0.6, mp.z), amarillo)
	_cil_mesh(self, 0.17, 0.72, Vector3(mp.x - 0.05, ped + 0.8, mp.z), hierro, Vector3(PI / 2, 0, 0), 14)
	_man1 = Mandos.crear("manivela", self, Vector3(mp.x + 0.3, ped + 0.3, mp.z), Vector3.RIGHT)
	_mandos4["p13_man1"] = _man1
	# el cable de lado a lado del rio
	var cab: Array = c["cable"]
	_cable_barcaza = _cuerda(hierro, 0.03)
	_linea(_cable_barcaza, _v(cab[0]), _v(cab[1]))
	# la cancela del muelle sur (se abre cuando atraca)
	var cr: Array = c["cancela"]
	var ctam := _mx(cr) - _mn(cr)
	_cancela = _estatico("CancelaMuelle", _centro(cr))
	_colision_caja(_cancela, ctam + Vector3(0, 1.0, 0), Vector3(0, 0.5, 0))
	for k in int(ctam.x / 0.2):
		_caja_mesh(_cancela, Vector3(0.04, ctam.y, 0.04), Vector3(-ctam.x / 2 + 0.1 + k * 0.2, 0, 0), hierro)
	_caja_mesh(_cancela, Vector3(ctam.x, 0.08, 0.08), Vector3(0, ctam.y / 2, 0), hierro)
	_rotulo("manivela1", "MANIVELA · traed la barcaza", _v(c["manivela"]) + Vector3(0, 2.4, 0), Color(0.95, 0.75, 0.1))


func _man_refrescar() -> void:
	if is_instance_valid(_barcaza):
		_barcaza_k_vis = _barcaza_k
		_barcaza.global_position.z = _barcaza_z(_barcaza_k, _barcaza_fase)


func _barcaza_rect() -> Array:
	var c := _c("p13_barcaza")
	var tam: Array = c.get("tam", [6, 6])
	var x := float(c.get("x", 162.0))
	var zc := _barcaza.global_position.z if is_instance_valid(_barcaza) else 110.0
	return [x - float(tam[0]) / 2 + 0.1, zc - float(tam[1]) / 2 + 0.1, x + float(tam[0]) / 2 - 0.1, zc + float(tam[1]) / 2 - 0.1]


func _en_barcaza(p: Vector3) -> bool:
	var r := _barcaza_rect()
	return p.x > float(r[0]) and p.x < float(r[2]) and p.z > float(r[1]) and p.z < float(r[3]) and p.y > AGUA_RIO - 0.2


## El anfitrion: mientras alguien se quede junto a la manivela, avanza
func _barcaza_host(dt: float) -> void:
	if _barcaza_fase != 1 and _barcaza_fase != 3:
		return
	var man: Node3D = _man1 if _barcaza_fase == 1 else _man2
	if not is_instance_valid(man):
		return
	var girando := false
	for pl in _jugadores_vivos():
		if (pl as Node3D).global_position.distance_to(man.global_position) < 2.2:
			girando = true
			break
	var tiempo := float(_c("p13_barcaza").get("tiempo", 22.0))
	if girando:
		_barcaza_k = minf(1.0, _barcaza_k + dt / tiempo)
	_texto = ("LA BARCAZA SE ACERCA · %d %% · ¡quedaos junto a la MANIVELA!" if _barcaza_fase == 1 else "CRUZANDO EL RÍO · %d %% · ¡seguid girando la MANIVELA!") % int(_barcaza_k * 100.0)
	if not girando:
		_texto += " · ¡NADIE GIRA!"
	# la horda no para mientras suena el trasto
	_man_tanda_t -= dt
	if _man_tanda_t <= 0.0:
		_man_tanda_t = 12.0
		if _cola.size() < 6:
			_horda(7, "")
	if _barcaza_fase == 3 and not _man_tank and _barcaza_k > 0.3:
		_man_tank = true
		_cola.push_front("tanque")
		_mensaje("¡UN TANK EN LA ORILLA!")
	_red_t4 -= dt
	if _red_t4 <= 0.0:
		_red_t4 = 0.25
		_evento("p13_k", [_barcaza_fase, _barcaza_k, 1 if girando else 0])
	if _barcaza_k >= 1.0:
		if _barcaza_fase == 1:
			_evento("p13_llega", [])
		else:
			_evento("p13", [])


func _barcaza_fisica(dt: float) -> void:
	if not is_instance_valid(_barcaza):
		return
	# suave hacia lo ultimo que dijo el anfitrion
	_barcaza_k_vis = move_toward(_barcaza_k_vis, _barcaza_k, dt * 0.12)
	var z := _barcaza_z(_barcaza_k_vis, _barcaza_fase)
	var t := Time.get_ticks_msec() * 0.001
	var y := float(_c("p13_barcaza").get("y", 1.6)) - 0.2 + sin(t * 1.3) * 0.03
	# la x, del json: leida del propio cuerpo salia 0 (el AnimatableBody con sync_to_physics devuelve la del servidor
	# de fisica, que al principio es el origen) y la barcaza se quedaba para siempre en x 0, a 160 m del embarcadero
	var x := float(_c("p13_barcaza").get("x", 162.0))
	_barcaza.global_position = Vector3(x, y, z)
	# los compañeros bot de a bordo van con ella
	for par_b in _bots_barcaza:
		var b = par_b[0]
		if is_instance_valid(b):
			var off: Vector2 = par_b[1]
			b.global_position = Vector3(_barcaza.global_position.x + off.x, y + 0.3, z + off.y)
			b.velocity = Vector3.ZERO
	# el de esta maquina, si esta a bordo y se le escapa el suelo, arriba
	if is_instance_valid(jugador) and _en_barcaza(jugador.global_position) and jugador.global_position.y < y + 0.15:
		jugador.global_position.y = y + 0.22


func _man_gira(man: Node3D, dt: float) -> void:
	if not is_instance_valid(man):
		return
	var r: Node3D = man.get_meta("rueda") if man.has_meta("rueda") else null      # (el disco de la manivela)
	if r:
		r.rotation.z -= dt * 5.0
	_man_carraca_t -= dt
	if _man_carraca_t <= 0.0:
		_man_carraca_t = 0.45
		Audio.play3d("gen/manivela/carraca", man.global_position, -2.0, 0.08, 30.0, Audio.PRI_MID)


var _man_girando_red := false

func _p13_k(fase_b: int, k: float, girando: bool) -> void:
	if fase_b != _barcaza_fase and fase_b == 3:
		_barcaza_k_vis = 0.0
	_barcaza_fase = fase_b
	_barcaza_k = k
	_man_girando_red = girando


func _p13_llega() -> void:
	_barcaza_fase = 2
	_barcaza_k = 0.0
	_barcaza_k_vis = 0.0
	_quitar_cartel("manivela1")
	_piloto4(_man1, "hecho")
	_piloto4(_man2, "espera")          # ahora toca la de a bordo
	Audio.bf3d("destru/madera", _barcaza.global_position if is_instance_valid(_barcaza) else Vector3.ZERO, 2.0, 40.0, Audio.PRI_HIGH)
	_rotulo("manivela2", "TODOS A BORDO · MANIVELA", _man2.global_position + Vector3(0, 2.2, 0) if is_instance_valid(_man2) else Vector3.ZERO, Color(0.95, 0.75, 0.1))
	_mensaje_local("¡LA BARCAZA HA LLEGADO! TODOS A BORDO y girad su manivela")


func _p13_resuelto(ya: bool) -> void:
	_quitar_cartel("manivela1")
	_quitar_cartel("manivela2")
	_piloto4(_man1, "hecho")
	_piloto4(_man2, "hecho")
	_barcaza_fase = 4
	_barcaza_k = 1.0
	_barcaza_k_vis = 1.0
	if is_instance_valid(_barcaza):
		_barcaza.global_position.z = _barcaza_z(1.0, 3)
	for par_b in _bots_barcaza:
		var b = par_b[0]
		if is_instance_valid(b):
			b.set_physics_process(true)
			b.global_position += Vector3(0, 0.4, 5.5)
	_bots_barcaza.clear()
	if is_instance_valid(_cancela):
		_sin_colision(_cancela)
		if ya:
			_cancela.visible = false
		else:
			var tw := _cancela.create_tween()
			tw.tween_property(_cancela, "global_position:y", _cancela.global_position.y + 2.4, 1.5).set_trans(Tween.TRANS_SINE)
			Audio.play3d("gen/ascensor/reja", _cancela.global_position, 2.0, 0.02, 40.0, Audio.PRI_HIGH)
	if not ya:
		_mensaje_local("¡OTRA ORILLA! Subid al PUEBLO: el refugio está arriba")


## Los compañeros bot suben a la barcaza con vosotros (el anfitrion)
func _bots_a_bordo() -> void:
	_bots_barcaza.clear()
	if _en_red and not _soy_host:
		return
	var i := 0
	for b in get_tree().get_nodes_in_group("aliados_pve"):
		if not is_instance_valid(b):
			continue
		var off := Vector2(-1.8 + (i % 2) * 1.6, -1.6 + float(i / 2) * 2.4)
		i += 1
		b.set_physics_process(false)
		_bots_barcaza.append([b, off])


# ======================================================================================================
# 14. LA LLAVE DEL PORTON
# ======================================================================================================
func _montar_p14() -> void:
	var c := _c("p14_llave")
	if c.is_empty():
		return
	var r: Array = c["porton"]
	var tam := _mx(r) - _mn(r)
	_porton_cuerpo = _estatico("PortonPueblo", _centro(r))
	_colision_caja(_porton_cuerpo, tam, Vector3.ZERO)
	var hierro := _mm(Color(0.12, 0.12, 0.13), 0.8, 0.5)
	for s in [-1.0, 1.0]:
		var bis := Node3D.new()
		_porton_cuerpo.add_child(bis)
		bis.position = Vector3(0, 0, s * tam.z / 2)
		var hoja := Node3D.new()
		bis.add_child(hoja)
		hoja.position = Vector3(0, 0, -s * tam.z / 4)
		for k in int(tam.z / 2 / 0.16):
			_caja_mesh(hoja, Vector3(0.05, tam.y - 0.1, 0.05), Vector3(0, 0, -tam.z / 4 + 0.08 + k * 0.16), hierro)
		for y in [-tam.y / 2 + 0.2, 0.2, tam.y / 2 - 0.2]:
			_caja_mesh(hoja, Vector3(0.08, 0.08, tam.z / 2), Vector3(0, y, 0), hierro)
		_porton_hojas.append(bis)
	# la cadena y el candado (en la cara del pueblo)
	var cand := _v(c["candado"])
	var cad := Node3D.new()
	cad.name = "Candado"
	_porton_cuerpo.add_child(cad)
	cad.global_position = cand + Vector3(0, 1.1, 0)
	_caja_mesh(cad, Vector3(0.12, 0.16, 0.1), Vector3.ZERO, _mm(Color(0.7, 0.6, 0.2), 0.9, 0.3))
	# el arco del candado (una U de acero) y la cerradura, en la cara que da al pueblo: que se vea que es un candado
	var arco := MeshInstance3D.new()
	var ta := TorusMesh.new()
	ta.inner_radius = 0.035
	ta.outer_radius = 0.052
	arco.mesh = ta
	arco.material_override = _mm(Color(0.62, 0.63, 0.65), 0.9, 0.3)
	arco.rotation = Vector3(0, 0, PI / 2)
	arco.position = Vector3(0, 0.09, 0)
	cad.add_child(arco)
	_cil_mesh(cad, 0.018, 0.01, Vector3(0.061, -0.02, 0), _mm(Color(0.05, 0.05, 0.05), 0.2, 0.6), Vector3(0, 0, PI / 2), 8)
	for k in 5:
		var e := _caja_mesh(cad, Vector3(0.03, 0.1, 0.06), Vector3(0, 0.15 + k * 0.08, (k % 2) * 0.03), _mm(Color(0.5, 0.5, 0.5), 0.9, 0.3))
		e.rotation.y = (k % 2) * PI / 2
	_porton_barrera = AABB(_mn(r) - Vector3(0.6, 0.5, 0.2), tam + Vector3(1.2, 1.0, 0.4))
	CriaturaScript.barreras.append(_porton_barrera)
	_rotulo("porton", "CERRADO CON CANDADO · la LLAVE está en alguna casa", _centro(r) + Vector3(1.0, 2.4, 0), Color(0.95, 0.75, 0.1))


func _llave_colocar() -> void:
	var c := _c("p14_llave")
	if c.is_empty() or _llave_pueblo:
		return
	var casas: Array = c.get("casas", [])
	var i := int(par.get("casa", 0))
	if i < 0 or i >= casas.size():
		return
	var p := _v((casas[i] as Dictionary)["mesa"])
	if not is_instance_valid(_llave_nodo):
		_llave_nodo = Node3D.new()
		add_child(_llave_nodo)
		var oro := _brillo(Color(0.95, 0.75, 0.2), 0.8)
		_cil_mesh(_llave_nodo, 0.07, 0.03, Vector3(-0.1, 0.02, 0), oro, Vector3(PI / 2, 0, 0), 12)
		_caja_mesh(_llave_nodo, Vector3(0.2, 0.025, 0.03), Vector3(0.05, 0.02, 0), oro)
		_caja_mesh(_llave_nodo, Vector3(0.03, 0.025, 0.06), Vector3(0.13, 0.02, 0.03), oro)
		var brillo := _luz(_llave_nodo, Vector3(0, 0.3, 0), Color(1.0, 0.85, 0.4), 0.6, 2.5)
		brillo.name = "Brillo"
	_llave_nodo.global_position = p


func _p14_coger() -> void:
	_llave_pueblo = true
	if is_instance_valid(_llave_nodo):
		_llave_nodo.queue_free()
	Audio.bf3d("gadget/c4_coger", jugador.global_position if is_instance_valid(jugador) else Vector3.ZERO, 0.0, 20.0, Audio.PRI_MID)
	_rotulo("porton", "¡YA TENÉIS LA LLAVE! · abrid el CANDADO", _centro(_c("p14_llave").get("porton", [0, 0, 0, 0, 0, 0])) + Vector3(1.0, 2.4, 0), Color(0.3, 1.0, 0.4))
	_mensaje_local("¡LA LLAVE DEL PORTÓN!")


func _p14_resuelto(ya: bool) -> void:
	_quitar_cartel("porton")
	_llave_pueblo = true
	if is_instance_valid(_llave_nodo):
		_llave_nodo.queue_free()
	CriaturaScript.barreras.erase(_porton_barrera)
	if not is_instance_valid(_porton_cuerpo):
		return
	_sin_colision(_porton_cuerpo)
	var cad := _porton_cuerpo.get_node_or_null("Candado")
	if cad:
		cad.queue_free()
	for k in _porton_hojas.size():
		var bis: Node3D = _porton_hojas[k]
		var ang := (-1.0 if k == 0 else 1.0) * 1.7
		if ya:
			bis.rotation.y = ang
		else:
			bis.create_tween().tween_property(bis, "rotation:y", ang, 2.0).set_trans(Tween.TRANS_SINE)
	if not ya:
		Audio.play3d("gen/ascensor/reja", _porton_cuerpo.global_position, 2.0, 0.02, 40.0, Audio.PRI_HIGH)
		_mensaje_local("¡EL PORTÓN SE ABRE! Al MIRADOR y al depósito de agua")


# ======================================================================================================
# 15. LA TIROLINA
# ======================================================================================================
func _montar_p15() -> void:
	var c := _c("p15_tirolina")
	if c.is_empty():
		return
	var acero := _mm(Color(0.2, 0.2, 0.21), 0.8, 0.4)
	for k in 10:
		_cable_tirolina.append(_cuerda(acero, 0.035))
	_torno_nodo = Node3D.new()
	add_child(_torno_nodo)
	_torno_nodo.global_position = _v(c["torno"]) + Vector3(0, 0.95, 0)
	_cil_mesh(_torno_nodo, 0.3, 0.7, Vector3.ZERO, _mm(Color(0.3, 0.3, 0.3), 0.8, 0.4), Vector3(0, 0, PI / 2), 14)
	var mango := _caja_mesh(_torno_nodo, Vector3(0.06, 0.5, 0.06), Vector3(0.4, 0.25, 0), acero)
	mango.name = "Mango"
	# LA POLEA DE LA TIROLINA, esperando arriba en el cable (antes solo habia cable y no se sabia de donde agarrarse):
	# el carro con su rueda, la barra que cuelga y el asa en T con los puños rojos, a la altura de la mano
	var cab: Array = c["cable"]
	var da := _v(cab[1]) - _v(cab[0])
	_tirolina_parado = Node3D.new()
	_tirolina_parado.name = "PoleaTirolina"
	add_child(_tirolina_parado)
	_tirolina_parado.rotation.y = atan2(-da.x, -da.z)          # su -Z, cable abajo
	var gris := _mm(Color(0.3, 0.3, 0.32), 0.8, 0.4)
	var rojo := _mm(Color(0.8, 0.1, 0.05), 0.3, 0.5)
	for s in [-1.0, 1.0]:
		_caja_mesh(_tirolina_parado, Vector3(0.025, 0.2, 0.26), Vector3(s * 0.05, -0.03, 0), gris)
	_cil_mesh(_tirolina_parado, 0.07, 0.06, Vector3(0, 0.06, 0), _mm(Color(0.15, 0.15, 0.16), 0.8, 0.4), Vector3(0, 0, PI / 2), 14)
	var alto_asa := _v(c["arriba"]).y + 1.4
	_tirolina_parado.set_meta("asa_y", alto_asa)
	var barra := _caja_mesh(_tirolina_parado, Vector3(0.04, 1.0, 0.04), Vector3(0, -0.6, 0), gris)
	barra.name = "Barra"
	var asa := Node3D.new()
	asa.name = "Asa"
	_tirolina_parado.add_child(asa)
	_caja_mesh(asa, Vector3(0.56, 0.045, 0.045), Vector3.ZERO, gris)
	for s in [-1.0, 1.0]:
		_cil_mesh(asa, 0.03, 0.16, Vector3(s * 0.2, 0, 0), rojo, Vector3(0, 0, PI / 2), 10)
	_cable_dibujar(3.2)
	_rotulo("torno", "TORNO · tensad el cable", _v(c["torno"]) + Vector3(0, 2.0, 0), Color(0.95, 0.75, 0.1))


func _cable_dibujar(comba: float) -> void:
	var c := _c("p15_tirolina")
	var cab: Array = c.get("cable", [])
	if cab.size() < 2 or _cable_tirolina.is_empty():
		return
	var a := _v(cab[0])
	var b := _v(cab[1])
	var n := _cable_tirolina.size()
	for k in n:
		var t0 := float(k) / n
		var t1 := float(k + 1) / n
		var p0 := a.lerp(b, t0) + Vector3.DOWN * comba * 4.0 * t0 * (1.0 - t0)
		var p1 := a.lerp(b, t1) + Vector3.DOWN * comba * 4.0 * t1 * (1.0 - t1)
		_linea(_cable_tirolina[k], p0, p1)
	# la polea, a un palmo del poste, sobre el cable (flojo o tenso): la barra llega siempre al asa a la altura de la mano
	if is_instance_valid(_tirolina_parado):
		var tp := 0.25 / maxf(a.distance_to(b), 1.0)
		var q := a.lerp(b, tp) + Vector3.DOWN * comba * 4.0 * tp * (1.0 - tp)
		_tirolina_parado.position = q
		var largo := maxf(0.3, q.y - float(_tirolina_parado.get_meta("asa_y")))
		var barra := _tirolina_parado.get_node("Barra") as Node3D
		barra.scale = Vector3(1.0, largo, 1.0)
		barra.position = Vector3(0, -largo * 0.5, 0)
		(_tirolina_parado.get_node("Asa") as Node3D).position = Vector3(0, -largo, 0)


func _tensar_cable(ya: bool) -> void:
	_cable_tenso = true
	_quitar_cartel("torno")
	if ya:
		_cable_dibujar(0.35)
		return
	var tw := create_tween()
	tw.tween_method(_cable_dibujar, 3.2, 0.35, 3.0).set_trans(Tween.TRANS_SINE)
	if is_instance_valid(_torno_nodo):
		_torno_nodo.create_tween().tween_property(_torno_nodo, "rotation:x", _torno_nodo.rotation.x + TAU * 3.0, 3.0)
	for k in 6:
		get_tree().create_timer(k * 0.5).timeout.connect(func():
			if is_instance_valid(_torno_nodo):
				Audio.play3d("gen/manivela/carraca", _torno_nodo.global_position, 0.0, 0.08, 30.0, Audio.PRI_MID))
	var ar := _v(_c("p15_tirolina").get("arriba", [0, 0, 0]))
	_rotulo("tirolina", "TIROLINA · ¡abajo!", ar + Vector3(0, 2.4, 0), Color(0.3, 1.0, 0.4))
	_mensaje_local("¡CABLE TENSO! Bajad por la TIROLINA")


func _p15_resuelto(_ya: bool) -> void:
	_quitar_cartel("tirolina")


## Cada uno baja solo (lo hace su propia maquina); los demas lo ven por su posicion de siempre
func _tirolina_bajar() -> void:
	if _tirolina_t >= 0.0 or not _cable_tenso or not is_instance_valid(jugador):
		return
	var c := _c("p15_tirolina")
	var cab: Array = c["cable"]
	var a := _v(cab[0])
	var b := _v(cab[1])
	_tirolina_t = 0.0
	jugador.set_physics_process(false)
	jugador.set("velocity", Vector3.ZERO)
	if is_instance_valid(_tirolina_parado):
		_tirolina_parado.visible = false          # (la coges tu: baja contigo)
	_tirolina_carro = Node3D.new()
	add_child(_tirolina_carro)
	_tirolina_carro.global_position = a
	var gris := _mm(Color(0.25, 0.25, 0.26), 0.8, 0.4)
	_cil_mesh(_tirolina_carro, 0.1, 0.06, Vector3.ZERO, gris, Vector3(PI / 2, 0, 0), 12)
	_caja_mesh(_tirolina_carro, Vector3(0.05, 0.5, 0.05), Vector3(0, -0.3, 0), gris)
	_caja_mesh(_tirolina_carro, Vector3(0.5, 0.05, 0.05), Vector3(0, -0.55, 0), _mm(Color(0.8, 0.1, 0.05), 0.3, 0.5))
	Audio.play3d("gen/tirolina/zumbido", a, 2.0, 0.03, 60.0, Audio.PRI_HIGH)
	_mensaje_local("¡YIIIAAAA!")


func _tirolina_tick(dt: float) -> void:
	if _tirolina_t < 0.0:
		return
	var c := _c("p15_tirolina")
	var cab: Array = c["cable"]
	var a := _v(cab[0])
	var b := _v(cab[1])
	var dur := 4.6
	_tirolina_t += dt
	var k := clampf(_tirolina_t / dur, 0.0, 1.0)
	var e := k * k * (1.6 - 0.6 * k)
	var p := a.lerp(b, e) + Vector3.DOWN * 0.35 * 4.0 * e * (1.0 - e)
	if is_instance_valid(_tirolina_carro):
		_tirolina_carro.global_position = p
		_tirolina_carro.look_at(b + Vector3(0, 0.01, 0), Vector3.UP)
	if is_instance_valid(jugador):
		jugador.global_position = p + Vector3(0, -2.25, 0)
		if bool(jugador.get("spectating")) or float(jugador.get("health")) <= 0.0:
			k = 1.0
	if k >= 1.0:
		_tirolina_t = -1.0
		if is_instance_valid(_tirolina_carro):
			_tirolina_carro.queue_free()
		if is_instance_valid(_tirolina_parado):
			_tirolina_parado.visible = true
		if is_instance_valid(jugador):
			var abajo := _v(c["abajo"])
			jugador.global_position = abajo + Vector3(0, 0.3, 0)
			jugador.set("velocity", Vector3.ZERO)
			jugador.set_physics_process(true)
			Audio.play3d("grab", abajo + Vector3.UP, 0.0, 0.05, 20.0, Audio.PRI_MID)


# ======================================================================================================
# 16. LAS PASARELAS HIDRAULICAS
# ======================================================================================================
func _pasarela_y(arriba: bool) -> float:
	var c := _c("p16_pasarelas")
	return (float(c.get("arriba", 4.0)) if arriba else float(c.get("abajo", 0.9))) - 0.15


func _montar_p16() -> void:
	var c := _c("p16_pasarelas")
	if c.is_empty():
		return
	var z: Array = c["z"]
	var lado := float(c.get("lado", 1.3))
	var hondo := float(z[1]) - float(z[0])
	var amarillo := _mm(Color(0.85, 0.66, 0.08), 0.5, 0.5)
	var chapa := _mm(Color(0.35, 0.37, 0.38), 0.8, 0.4)
	for x in c["x"]:
		var pa := _animable("Pasarela", Vector3(float(x), _pasarela_y(false), (float(z[0]) + float(z[1])) / 2))
		_colision_caja(pa, Vector3(lado, 0.3, hondo), Vector3.ZERO)
		_caja_mesh(pa, Vector3(lado, 0.3, hondo), Vector3.ZERO, chapa)
		for s in [-1.0, 1.0]:
			_caja_mesh(pa, Vector3(lado + 0.02, 0.32, 0.12), Vector3(0, 0, s * (hondo / 2 - 0.06)), amarillo)
		_caja_mesh(pa, Vector3(0.3, 3.2, 0.3), Vector3(0, -1.75, 0), _mm(Color(0.6, 0.6, 0.62), 0.9, 0.3))     # el piston
		_pasarelas.append(pa)
	for k in 2:
		var p := _v(c["palanca"] if k == 0 else c["bloqueo"])
		var base := Node3D.new()
		base.name = "Palanca%d" % k
		add_child(base)
		base.global_position = p
		_caja_mesh(base, Vector3(0.3, 1.0, 0.3), Vector3(0, 0.5, 0), _mm(Color(0.2, 0.22, 0.2), 0.6, 0.5))
		var mango := Node3D.new()
		mango.name = "Mango"
		mango.position = Vector3(0, 1.0, 0)
		base.add_child(mango)
		_caja_mesh(mango, Vector3(0.06, 0.7, 0.06), Vector3(0, 0.35, 0), _mm(Color(0.1, 0.1, 0.1), 0.6, 0.5))
		_esfera_mesh(mango, 0.07, Vector3(0, 0.72, 0), _mm(Color(0.85, 0.66, 0.08), 0.2, 0.4))
		mango.rotation.x = 0.6
	_rotulo("pasarelas", "PASARELAS · suben unos segundos", _v(c["palanca"]) + Vector3(0, 2.2, 0), Color(0.95, 0.75, 0.1))
	_rotulo("bloqueo", "BLOQUEO DE LAS PASARELAS", _v(c["bloqueo"]) + Vector3(0, 2.2, 0), Color(0.3, 0.8, 1.0))


func _palanca_mango(k: int, abajo: bool) -> void:
	var b := get_node_or_null("Palanca%d" % k)
	if b:
		var m := b.get_node_or_null("Mango") as Node3D
		if m:
			m.create_tween().tween_property(m, "rotation:x", -0.6 if abajo else 0.6, 0.25)


func _pasarelas_suben() -> void:
	if _pasarelas_ocupadas or _pasarelas_fijas:
		return
	_pasarelas_ocupadas = true
	_palanca_mango(0, true)
	var subidas := float(_c("p16_pasarelas").get("subidas", 5.5))
	Audio.play3d("gen/ascensor/arranque", _v(_c("p16_pasarelas").get("palanca", [0, 0, 0])), 2.0, 0.0, 50.0, Audio.PRI_HIGH)
	# suben de la orilla de la palanca (este) hacia el otro lado, y se hunden en el mismo orden
	var n := _pasarelas.size()
	for i in n:
		var pa: AnimatableBody3D = _pasarelas[n - 1 - i]
		var tw := pa.create_tween()
		_pasarelas_tw.append(tw)
		tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tw.tween_interval(i * 0.3)
		tw.tween_property(pa, "global_position:y", _pasarela_y(true), 0.9).set_trans(Tween.TRANS_SINE)
		tw.tween_interval(subidas + i * 0.3)
		tw.tween_callback(func():
			if _pasarelas_fijas:
				tw.kill())
		tw.tween_property(pa, "global_position:y", _pasarela_y(false), 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	get_tree().create_timer(subidas + n * 0.6 + 2.6).timeout.connect(func():
		_pasarelas_ocupadas = false
		if not _pasarelas_fijas:
			_palanca_mango(0, false))
	_mensaje_local("¡LAS PASARELAS SUBEN! ¡Cruzad antes de que se hundan!")


func _fijar_pasarelas(ya: bool) -> void:
	_pasarelas_fijas = true
	_quitar_cartel("pasarelas")
	_quitar_cartel("bloqueo")
	_palanca_mango(1, true)
	for t in _pasarelas_tw:
		if t != null and (t as Tween).is_valid():
			(t as Tween).kill()
	_pasarelas_tw.clear()
	for pa in _pasarelas:
		var p := pa as AnimatableBody3D
		if ya:
			p.global_position.y = _pasarela_y(true)
		else:
			var tw := p.create_tween()
			tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
			tw.tween_property(p, "global_position:y", _pasarela_y(true), 1.0).set_trans(Tween.TRANS_SINE)
	if not ya:
		Audio.bf3d("destru/metal", _v(_c("p16_pasarelas").get("bloqueo", [0, 0, 0])), 0.0, 40.0, Audio.PRI_HIGH)
		_mensaje_local("¡PASARELAS BLOQUEADAS ARRIBA! Ya pasa todo el mundo")


func _p16_resuelto(ya: bool) -> void:
	if not _pasarelas_fijas:
		_fijar_pasarelas(ya)


# ======================================================================================================
# 17. LA BOLA DE DEMOLICION
# ======================================================================================================
func _montar_p17() -> void:
	var c := _c("p17_bola")
	if c.is_empty():
		return
	var pl := _v(c["pluma"])
	var rp := _v(c["reposo"])
	var largo := pl.distance_to(rp)
	_bola_pivote = Node3D.new()
	add_child(_bola_pivote)
	_bola_pivote.global_position = pl
	var negro := _mm(Color(0.1, 0.1, 0.1), 0.6, 0.5)
	var cable := _cil_mesh(_bola_pivote, 0.04, largo, Vector3(0, -largo / 2, 0), negro, Vector3.ZERO, 6)
	cable.name = "Cable"
	_esfera_mesh(_bola_pivote, 0.9, Vector3(0, -largo, 0), _mm(Color(0.16, 0.16, 0.17), 0.85, 0.35))
	_cil_mesh(_bola_pivote, 0.2, 0.5, Vector3(0, -largo + 0.95, 0), negro)
	_rotulo("grua_bola", "GRÚA DE DEMOLICIÓN · 3 golpes", _v(c["cabina"]) + Vector3(0, 3.6, 0), Color(0.95, 0.75, 0.1))
	# LA PALANCA DE LA GRUA, en el costado este del cuerpo amarillo, junto a la cabina (antes no habia nada: se
	# "accionaba la grua" en el aire). Baja con cada golpe y vuelve arriba cuando la bola esta quieta.
	var cb := _v(c["cabina"])
	_mandos4["p17_grua"] = Mandos.en_pared(world, "palanca", self, Vector3(cb.x + 0.6, cb.y + 1.35, cb.z - 1.2), Vector3(1, 0, 0), 1.6)


func _bola_idle(_dt: float) -> void:
	if not is_instance_valid(_bola_pivote) or _bola_ocupada:
		return
	var t := Time.get_ticks_msec() * 0.001
	_bola_pivote.rotation.z = sin(t * 0.9) * 0.012
	_bola_pivote.rotation.x = sin(t * 0.7) * 0.01


func _bola_golpe(n: int, ya: bool) -> void:
	if n <= _bola_golpes:
		return
	_bola_golpes = n
	var c := _c("p17_bola")
	var radios := [1.1, 1.6, 2.2]
	var r: float = radios[clampi(n - 1, 0, 2)]
	var bq := _v(c["boquete"])
	var mx: Array = c.get("muro_x", [38.0, 40.0])
	var abrir := func():
		var us: Array = []
		var vs: Array = []
		var y := -r
		while y <= r:
			us.append(y)
			y += 0.45
		var z := -r
		while z <= r:
			vs.append(z)
			z += 0.45
		for u in us:
			for v in vs:
				if float(u) * float(u) + float(v) * float(v) <= r * r:
					world.carve_beam(Vector3(float(mx[1]) + 1.2, bq.y + float(u), bq.z + float(v)), Vector3.LEFT, float(mx[1]) - float(mx[0]) + 2.4, 0.4, 255, true)
	if ya or not is_instance_valid(_bola_pivote):
		abrir.call()
		if n >= 3:
			_quitar_cartel("grua_bola")
			_mando_hecho4("p17_grua")
		return
	_bola_ocupada = true
	_pulsar4("p17_grua", n >= 3)
	var pl := _v(c["pluma"])
	var rp := _v(c["reposo"])
	var largo := pl.distance_to(rp)
	var ang_golpe := asin(clampf((float(mx[1]) + 0.9 - pl.x) / largo, -1.0, 1.0))
	Audio.play3d("gen/ascensor/arranque", _v(c["cabina"]), 0.0, 0.0, 50.0, Audio.PRI_MID)
	var tw := create_tween()
	tw.tween_property(_bola_pivote, "rotation:z", 0.5, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): Audio.play3d("gen/bola/silbido", _bola_pivote.global_position + Vector3(0, -largo, 0), 4.0, 0.03, 50.0, Audio.PRI_HIGH))
	tw.tween_property(_bola_pivote, "rotation:z", ang_golpe, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		abrir.call()
		var impacto := Vector3(float(mx[1]), bq.y, bq.z)
		_golpe(impacto, 2.0, "destru/derrumbe" if n >= 3 else "destru/ladrillo")
		_golpe(impacto + Vector3(-1.0, 0, 0), 1.2, "destru/hormigon")
		if n >= 3 and _soy_host:
			Net.net_explode(world, impacto + Vector3(-0.6, 0, 0), 1.5, 180))
	tw.tween_property(_bola_pivote, "rotation:z", 0.12, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_bola_pivote, "rotation:z", 0.0, 1.6).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		_bola_ocupada = false
		# la palanca vuelve arriba para el golpe siguiente (con el tercero se queda abajo, en verde)
		var mg = _mandos4.get("p17_grua")
		if n < 3 and mg != null and is_instance_valid(mg) and (mg as Node3D).has_meta("brazo"):
			var brazo: Node3D = (mg as Node3D).get_meta("brazo")
			brazo.create_tween().tween_property(brazo, "rotation:x", 0.4, 0.4).set_trans(Tween.TRANS_SINE))
	if n < 3:
		_mensaje_local("¡GOLPE %d! El muro aguanta… (%d de 3)" % [n, n])
	else:
		_quitar_cartel("grua_bola")


func _p17_resuelto(ya: bool) -> void:
	while _bola_golpes < 3:
		_bola_golpe(_bola_golpes + 1, true)
	_quitar_cartel("grua_bola")
	_piloto4(_mandos4.get("p17_grua"), "hecho")
	if not ya:
		_mensaje_local("¡EL MURO HA CAÍDO! A la ESTACIÓN")


# ======================================================================================================
# 18. LA COMBINACION
# ======================================================================================================
func _dial_pos(i: int) -> Vector3:
	var d := _v(_c("p18_combinacion").get("diales", [0, 0, 0]))
	return Vector3(d.x + i * 0.32, d.y + 1.35, d.z + 0.08)


func _montar_p18() -> void:
	var c := _c("p18_combinacion")
	if c.is_empty():
		return
	var r: Array = c["puerta"]
	var tam := _mx(r) - _mn(r)
	_p18_puerta = _estatico("PuertaOficina", _centro(r))
	_colision_caja(_p18_puerta, tam, Vector3.ZERO)
	_caja_mesh(_p18_puerta, tam, Vector3.ZERO, _mm(Color(0.38, 0.26, 0.16), 0.0, 0.8))
	_caja_mesh(_p18_puerta, Vector3(tam.x * 0.6, 0.6, tam.z + 0.02), Vector3(0, 0.5, 0), _mm(Color(0.3, 0.4, 0.45), 0.4, 0.2))
	_texto3d("JEFE DE ESTACIÓN\nCLAVE: ANDÉN · RELOJ · VAGÓN", Vector3(0, 1.45, tam.z / 2 + 0.03), Color(0.95, 0.9, 0.8), 18, false, _p18_puerta)
	var d := _v(c["diales"])
	var caja := Node3D.new()
	add_child(caja)
	caja.global_position = d
	_caja_mesh(caja, Vector3(1.1, 0.5, 0.1), Vector3(0.32, 1.35, 0.03), _mm(Color(0.2, 0.2, 0.22), 0.7, 0.4))
	for i in 3:
		var p := _dial_pos(i)
		var boton := _cil_mesh(self, 0.12, 0.08, Vector3.ZERO, _mm(Color(0.7, 0.62, 0.3), 0.8, 0.3), Vector3(PI / 2, 0, 0), 14)
		boton.global_position = p + Vector3(0, 0, 0.02)
		var l := _texto3d("0", p + Vector3(0, 0, 0.08), Color(0.05, 0.05, 0.05), 40, false)
		l.outline_size = 0
		_dial_labels.append(l)
	# las tres pistas: el cartel del anden, el reloj parado y el numero del vagon (este, en el vagon)
	_pistas_labels["anden"] = _texto3d("ANDÉN ?", _v(c["anden"]) + Vector3(0, 2.7, 0.08), Color(0.1, 0.1, 0.12), 34, false)
	(_pistas_labels["anden"] as Label3D).outline_size = 0
	var rl := _v(c["reloj"])
	_reloj_aguja = Node3D.new()
	add_child(_reloj_aguja)
	_reloj_aguja.global_position = rl + Vector3(0, 0, 0.25)
	_caja_mesh(_reloj_aguja, Vector3(0.06, 0.45, 0.03), Vector3(0, 0.2, 0), _mm(Color(0.05, 0.05, 0.05), 0.3, 0.5))
	var minutero := _caja_mesh(self, Vector3(0.04, 0.65, 0.03), Vector3.ZERO, _mm(Color(0.05, 0.05, 0.05), 0.3, 0.5))
	minutero.global_position = rl + Vector3(0, 0.3, 0.27)
	_pistas_labels["reloj"] = _texto3d("", rl + Vector3(0, -1.1, 0.3), Color(0.95, 0.9, 0.8), 20, false)
	_rotulo("diales", "OFICINA · la clave: ANDÉN, RELOJ y VAGÓN", d + Vector3(0.3, 2.6, 0.6), Color(0.3, 0.8, 1.0))


func _cifras_refrescar() -> void:
	var cif: Array = par.get("cifras", [])
	if cif.size() < 3:
		return
	if _pistas_labels.has("anden"):
		(_pistas_labels["anden"] as Label3D).text = "ANDÉN %d" % int(cif[0])
	if is_instance_valid(_reloj_aguja):
		_reloj_aguja.rotation.z = -float(int(cif[1])) / 12.0 * TAU
	if _pistas_labels.has("reloj"):
		(_pistas_labels["reloj"] as Label3D).text = "(parado a las %d en punto)" % int(cif[1])
	if _pistas_labels.has("vagon"):
		(_pistas_labels["vagon"] as Label3D).text = "Nº %d" % int(cif[2])


func _diales_refrescar() -> void:
	for i in mini(_dial_labels.size(), _diales.size()):
		(_dial_labels[i] as Label3D).text = str(int(_diales[i]))


func _p18_resuelto(ya: bool) -> void:
	_quitar_cartel("diales")
	var cif: Array = par.get("cifras", [0, 0, 0])
	_diales = cif.duplicate()
	_diales_refrescar()
	if is_instance_valid(_p18_puerta):
		_sin_colision(_p18_puerta)
		var destino := _p18_puerta.global_position + Vector3(-1.9, 0, 0)
		if ya:
			_p18_puerta.global_position = destino
		else:
			_p18_puerta.create_tween().tween_property(_p18_puerta, "global_position", destino, 1.2).set_trans(Tween.TRANS_QUAD)
			Audio.play3d("gen/dial/clic", _dial_pos(1), 4.0, 0.02, 30.0, Audio.PRI_HIGH)
			Audio.bf3d("destru/madera", _p18_puerta.global_position, -2.0, 30.0, Audio.PRI_MID)
			_mensaje_local("¡CLIC! La oficina se abre: coged la LLAVE DE LA LOCOMOTORA")
	if not _llave_loco:
		var lp := _v(_c("p18_combinacion").get("llave", [0, 0, 0]))
		_llave_loco_nodo = Node3D.new()
		add_child(_llave_loco_nodo)
		_llave_loco_nodo.global_position = lp
		var metal := _brillo(Color(0.8, 0.8, 0.85), 0.6)
		_caja_mesh(_llave_loco_nodo, Vector3(0.22, 0.03, 0.06), Vector3.ZERO, metal)
		_caja_mesh(_llave_loco_nodo, Vector3(0.1, 0.05, 0.1), Vector3(-0.14, 0, 0), _mm(Color(0.1, 0.1, 0.1), 0.2, 0.6))
		_luz(_llave_loco_nodo, Vector3(0, 0.3, 0), Color(0.8, 0.9, 1.0), 0.6, 2.5)


func _p18_llave() -> void:
	_llave_loco = true
	if is_instance_valid(_llave_loco_nodo):
		_llave_loco_nodo.queue_free()
	Audio.bf3d("gadget/c4_coger", jugador.global_position if is_instance_valid(jugador) else Vector3.ZERO, 0.0, 20.0, Audio.PRI_MID)
	_mensaje_local("¡LA LLAVE DE LA LOCOMOTORA!")


# ======================================================================================================
# 19. LAS AGUJAS Y EL VAGON
# ======================================================================================================
func _montar_p19() -> void:
	var c := _c("p19_agujas")
	if c.is_empty():
		return
	var y := float(c["y"])
	var vz := float(c["via_z"])
	# la palanca de la aguja y el cuadro del itinerario
	var pp := _v(c["palanca"])
	var base := Node3D.new()
	add_child(base)
	base.global_position = pp
	_caja_mesh(base, Vector3(0.5, 0.4, 0.3), Vector3(0, 0.2, 0), _mm(Color(0.2, 0.2, 0.2), 0.6, 0.5))
	_aguja_mango = Node3D.new()
	_aguja_mango.position = Vector3(0, 0.4, 0)
	base.add_child(_aguja_mango)
	_caja_mesh(_aguja_mango, Vector3(0.07, 1.3, 0.07), Vector3(0, 0.65, 0), _mm(Color(0.1, 0.1, 0.1), 0.6, 0.5))
	_caja_mesh(_aguja_mango, Vector3(0.12, 0.25, 0.12), Vector3(0, 1.3, 0), _mm(Color(0.9, 0.9, 0.9), 0.2, 0.5))
	var panel := Node3D.new()
	add_child(panel)
	panel.global_position = pp + Vector3(-1.6, 0, -0.4)
	panel.rotation.y = PI
	_caja_mesh(panel, Vector3(0.12, 2.2, 0.12), Vector3(0, 1.1, 0), _mm(Color(0.15, 0.15, 0.15), 0.6, 0.5))
	_caja_mesh(panel, Vector3(1.4, 0.9, 0.08), Vector3(0, 2.4, 0), _mm(Color(0.1, 0.12, 0.12), 0.4, 0.6))
	_texto3d("ITINERARIO", Vector3(0, 2.75, 0.06), Color(0.95, 0.9, 0.8), 18, false, panel)
	var nombres := ["VÍA 1 → TÚNEL", "VÍA MUERTA", "VÍA LIBRE"]
	for k in 3:
		var l := _esfera_mesh(panel, 0.06, Vector3(-0.55, 2.55 - k * 0.22, 0.05), _brillo(Color(0.3, 0.3, 0.3), 0.3))
		_aguja_luces.append(l)
		_texto3d(nombres[k], Vector3(0.05, 2.55 - k * 0.22, 0.06), Color(0.9, 0.9, 0.85), 16, false, panel)
	# EL VAGON de mercancias, parado en la via 1 entre la locomotora y el tunel
	var vg: Array = c["vagon"]
	var x0 := float(vg[0])
	var x1 := float(vg[1])
	var largo := x1 - x0
	_vagon = _animable("Vagon", Vector3((x0 + x1) / 2, y, vz))
	_colision_caja(_vagon, Vector3(largo, 3.2, 2.9), Vector3(0, 2.2, 0))
	var marron := _mm(Color(0.40, 0.22, 0.14), 0.3, 0.8)
	var marron2 := _mm(Color(0.33, 0.18, 0.11), 0.3, 0.8)
	var negro := _mm(Color(0.08, 0.08, 0.08), 0.6, 0.5)
	_caja_mesh(_vagon, Vector3(largo, 3.0, 2.8), Vector3(0, 2.3, 0), marron)
	for k in int(largo / 0.6):
		_caja_mesh(_vagon, Vector3(0.08, 2.9, 2.84), Vector3(-largo / 2 + 0.3 + k * 0.6, 2.3, 0), marron2)
	_caja_mesh(_vagon, Vector3(largo + 0.2, 0.2, 3.0), Vector3(0, 3.85, 0), _mm(Color(0.3, 0.3, 0.3), 0.5, 0.6))
	_caja_mesh(_vagon, Vector3(largo, 0.4, 2.4), Vector3(0, 0.75, 0), negro)
	for sx in [-largo / 2 + 1.2, largo / 2 - 1.2]:
		for sz in [-0.5, 0.5]:
			for dx in [-0.5, 0.5]:
				_cil_mesh(_vagon, 0.42, 0.12, Vector3(sx + dx, 0.45, sz * 1.0), negro, Vector3(PI / 2, 0, 0), 14)
	_pistas_labels["vagon"] = _texto3d("Nº ?", Vector3(-1.0, 2.6, -1.45), Color(0.95, 0.95, 0.9), 90, false, _vagon)
	(_pistas_labels["vagon"] as Label3D).rotation.y = PI
	_texto3d("RENFE · MERCANCÍAS", Vector3(1.2, 1.4, -1.45), Color(0.9, 0.85, 0.7), 34, false, _vagon, PI)
	var fr := _v(c["freno"])
	# EL FRENO DE MANO del vagon: su volante en el costado sur, junto a la testera del este (donde esta el punto del
	# freno), a la altura de la mano. Es hijo del vagon: se va con el. (Antes era un disco plano en la testera.)
	_mandos4["p19_freno"] = Mandos.crear("volante", _vagon, Vector3(largo / 2 - 0.55, 1.45, 1.4), Vector3.BACK, true)
	# el camino del vagon: por la via 1 hasta la aguja y luego la via muerta
	_vagon_camino = [Vector3((x0 + x1) / 2, y, vz)]
	for p in c["via_muerta"]:
		_vagon_camino.append(Vector3(float(p[0]), y, float(p[1])))
	var ult: Vector3 = _vagon_camino[_vagon_camino.size() - 1]
	var penult: Vector3 = _vagon_camino[_vagon_camino.size() - 2]
	_vagon_camino[_vagon_camino.size() - 1] = ult + (penult - ult).normalized() * (largo / 2 + 0.4)
	_rotulo("aguja", "AGUJA", pp + Vector3(0, 2.2, 0), Color(0.95, 0.75, 0.1))
	_rotulo("freno", "FRENO DEL VAGÓN", fr + Vector3(0, 2.6, 0.3), Color(0.95, 0.5, 0.1))
	_aguja_refrescar()


func _aguja_refrescar() -> void:
	if is_instance_valid(_aguja_mango):
		_aguja_mango.rotation.x = -0.5 if _aguja == 0 else 0.5
	if _aguja_luces.size() >= 3:
		(_aguja_luces[0] as MeshInstance3D).material_override = _brillo(Color(0.1, 0.95, 0.25), 2.0) if _aguja == 0 else _brillo(Color(0.3, 0.3, 0.3), 0.3)
		(_aguja_luces[1] as MeshInstance3D).material_override = _brillo(Color(0.95, 0.7, 0.1), 2.0) if _aguja == 1 else _brillo(Color(0.3, 0.3, 0.3), 0.3)
		(_aguja_luces[2] as MeshInstance3D).material_override = _brillo(Color(0.1, 0.95, 0.25), 2.0) if _h("p19") else _brillo(Color(0.9, 0.1, 0.05), 1.2)


func _aguja_cambio(a: int) -> void:
	_aguja = a
	_aguja_refrescar()
	if is_instance_valid(_aguja_mango):
		Audio.bf3d("destru/metal", _aguja_mango.global_position, -2.0, 30.0, Audio.PRI_MID)


func _vagon_rueda(ya: bool) -> void:
	if _vagon_fuera:
		return
	_vagon_fuera = true
	_quitar_cartel("freno")
	if ya:
		_mando_hecho4("p19_freno")
	else:
		_pulsar4("p19_freno")
	if ya:
		if is_instance_valid(_vagon) and _vagon_camino.size() >= 2:
			var fin: Vector3 = _vagon_camino[_vagon_camino.size() - 1]
			var ant: Vector3 = _vagon_camino[_vagon_camino.size() - 2]
			_vagon.global_position = fin
			var rumbo := atan2(-(fin - ant).z, (fin - ant).x)
			if absf(angle_difference(0.0, rumbo)) > PI / 2:
				rumbo += PI
			_vagon.rotation.y = rumbo
		return
	_vagon_s = 0.0
	Audio.bf3d("destru/metal", _vagon.global_position if is_instance_valid(_vagon) else Vector3.ZERO, 0.0, 40.0, Audio.PRI_HIGH)
	_mensaje_local("¡FRENO FUERA! El vagón se va a la vía muerta")


func _vagon_tick(dt: float) -> void:
	if _vagon_s < 0.0 or not is_instance_valid(_vagon) or _vagon_camino.size() < 2:
		return
	_vagon_s += dt * clampf(0.6 + _vagon_s * 0.35, 0.6, 3.2)
	var s := _vagon_s
	var i := 0
	while i < _vagon_camino.size() - 2 and s > (_vagon_camino[i + 1] as Vector3).distance_to(_vagon_camino[i]):
		s -= (_vagon_camino[i + 1] as Vector3).distance_to(_vagon_camino[i])
		i += 1
	var a: Vector3 = _vagon_camino[i]
	var b: Vector3 = _vagon_camino[i + 1]
	var tramo := a.distance_to(b)
	var p := a.lerp(b, clampf(s / maxf(tramo, 0.01), 0.0, 1.0))
	_vagon.global_position = p
	var d := b - a
	var rumbo := atan2(-d.z, d.x)
	if absf(angle_difference(_vagon.rotation.y, rumbo)) > PI / 2:
		rumbo += PI
	_vagon.rotation.y = lerp_angle(_vagon.rotation.y, rumbo, clampf(dt * 3.0, 0.0, 1.0))
	if i == _vagon_camino.size() - 2 and s >= tramo:
		_vagon_s = -1.0
		_golpe(p, 1.2, "destru/metal")


func _p19_resuelto(ya: bool) -> void:
	_quitar_cartel("aguja")
	if not _vagon_fuera:
		_vagon_rueda(true)
	_aguja = 0
	_aguja_refrescar()
	if not ya:
		_mensaje_local("¡VÍA LIBRE HACIA EL TÚNEL!")


# ======================================================================================================
# 20. EL GASOIL Y EL TREN
# ======================================================================================================
func _montar_p20() -> void:
	var c := _c("p20_gasoil")
	if c.is_empty():
		return
	var y := float(c["y"])
	var vz := float(c["via_z"])
	var lo: Array = c["loco"]
	var co: Array = c["coche"]
	_tren = Node3D.new()
	_tren.name = "Tren"
	add_child(_tren)
	_tren.global_position = Vector3(float(lo[0]), y, vz)
	var rojo := _mm(Color(0.62, 0.12, 0.08), 0.35, 0.55)
	var crema := _mm(Color(0.9, 0.84, 0.7), 0.2, 0.6)
	var negro := _mm(Color(0.07, 0.07, 0.07), 0.6, 0.5)
	var amarillo := _mm(Color(0.9, 0.7, 0.1), 0.3, 0.5)
	var cristal := _mm(Color(0.2, 0.3, 0.35), 0.6, 0.1)
	var ll := float(lo[1]) - float(lo[0])
	# la locomotora: bastidor, capo largo delante, cabina detras, bogies
	var loco := StaticBody3D.new()
	loco.collision_layer = 1
	_tren.add_child(loco)
	_tren_cuerpos.append(loco)
	_colision_caja(loco, Vector3(ll, 3.4, 2.8), Vector3(ll / 2, 2.4, 0))
	_caja_mesh(loco, Vector3(ll, 0.55, 2.8), Vector3(ll / 2, 1.2, 0), negro)
	_caja_mesh(loco, Vector3(ll - 3.3, 2.0, 2.2), Vector3((ll - 3.3) / 2 + 0.15, 2.45, 0), rojo)
	_caja_mesh(loco, Vector3(ll - 3.3, 0.3, 2.24), Vector3((ll - 3.3) / 2 + 0.15, 2.3, 0), crema)
	_caja_mesh(loco, Vector3(3.0, 2.9, 2.8), Vector3(ll - 1.6, 2.9, 0), rojo)
	_caja_mesh(loco, Vector3(3.1, 0.25, 2.9), Vector3(ll - 1.6, 4.45, 0), negro)
	for s in [-1.0, 1.0]:
		_caja_mesh(loco, Vector3(1.4, 0.9, 0.04), Vector3(ll - 1.6, 3.5, s * 1.41), cristal)
	_caja_mesh(loco, Vector3(0.04, 0.9, 2.2), Vector3(ll - 3.1, 3.5, 0), cristal)
	for k in 6:
		_caja_mesh(loco, Vector3(0.12, 0.5, 2.82), Vector3(0.05, 1.6 + (k % 2) * 0.01, -1.1 + k * 0.44), amarillo if k % 2 == 0 else negro)
	_cil_mesh(loco, 0.18, 0.8, Vector3(2.0, 3.8, 0), negro)                     # el escape
	for bx in [1.6, ll - 1.6]:
		for dx in [-0.7, 0.0, 0.7]:
			for sz in [-0.75, 0.75]:
				_cil_mesh(loco, 0.45, 0.12, Vector3(bx + dx, 0.55, sz), negro, Vector3(PI / 2, 0, 0), 14)
	_tren_foco = SpotLight3D.new()
	_tren_foco.light_energy = 0.0
	_tren_foco.spot_range = 40.0
	_tren_foco.spot_angle = 22.0
	_tren_foco.light_color = Color(1.0, 0.95, 0.8)
	loco.add_child(_tren_foco)
	_tren_foco.position = Vector3(-0.1, 2.5, 0)
	_tren_foco.rotation.y = PI / 2
	_esfera_mesh(loco, 0.18, Vector3(-0.05, 2.5, 0), _mm(Color(0.9, 0.9, 0.8), 0.3, 0.2))
	_texto3d("EL SALTO 1318", Vector3(ll - 1.6, 3.0, 1.45), Color(0.95, 0.9, 0.8), 40, false, loco)
	# LA BOCA DE CARGA DEL GASOIL, en el costado del capo que da al anden: el cuello con su tapon amarillo y, encima,
	# el contador pintado en la chapa (antes era un letrero flotando y no habia boca ninguna)
	var tx := float(c["tapon"][0]) - float(lo[0])
	_boca_gasoil = Node3D.new()
	_boca_gasoil.name = "BocaGasoil"
	loco.add_child(_boca_gasoil)
	_boca_gasoil.position = Vector3(tx, 2.0, -1.1)
	# (el cuello sale del capo hacia arriba y hacia fuera, a 45 grados, como el de un deposito de verdad)
	_caja_mesh(_boca_gasoil, Vector3(0.3, 0.3, 0.03), Vector3(0, 0, -0.015), negro)
	var acero_g := _mm(Color(0.5, 0.5, 0.52), 0.85, 0.35)
	_cil_mesh(_boca_gasoil, 0.12, 0.05, Vector3(0, 0, -0.035), acero_g, Vector3(PI / 2, 0, 0), 16)
	_cil_mesh(_boca_gasoil, 0.07, 0.34, Vector3(0, 0.1, -0.13), acero_g, Vector3(-PI / 4, 0, 0), 14)
	var tapon_n := Node3D.new()
	_boca_gasoil.add_child(tapon_n)
	tapon_n.position = Vector3(0, 0.22, -0.25)
	tapon_n.rotation.x = -PI / 4
	_cil_mesh(tapon_n, 0.095, 0.07, Vector3.ZERO, amarillo, Vector3.ZERO, 16)
	_caja_mesh(tapon_n, Vector3(0.16, 0.035, 0.035), Vector3(0, 0.05, 0), _mm(Color(0.85, 0.66, 0.1), 0.6, 0.4))
	_tren_gasoil_label = _texto3d("GASOIL 0 / 6", Vector3(tx, 2.75, -1.115), Color(1.0, 0.85, 0.2), 52, false, loco, PI)
	_tren_gasoil_label.pixel_size = 0.0045
	# EL ARRANQUE: el panel (reloj, boton verde gordo) en el costado de la cabina que da al anden, junto a la ventanilla.
	# Antes el punto estaba DENTRO del capo, a 6 m de la cabina. Apagado hasta que el deposito esta lleno.
	_mandos4["p20_arranque"] = Mandos.crear("arranque", loco, Vector3(ll - 2.6, 2.15, -1.4), Vector3.FORWARD, true)
	_piloto4(_mandos4["p20_arranque"], "apagado")
	_tren_humo = _particulas(loco, Vector3(2.0, 4.3, 0), 30, 3.0, Color(0.15, 0.15, 0.15, 0.7), Color(0.35, 0.35, 0.35), 1.2, false)
	_tren_humo.direction = Vector3.UP
	_tren_humo.initial_velocity_min = 2.0
	_tren_humo.initial_velocity_max = 3.5
	_tren_humo.gravity = Vector3(0.5, 1.0, 0)
	_tren_humo.emitting = false
	# la plataforma: donde se sube todo el mundo (a ras del anden)
	var coche := StaticBody3D.new()
	coche.collision_layer = 1
	_tren.add_child(coche)
	_tren_cuerpos.append(coche)
	var cx := (float(co[0]) + float(co[1])) / 2 - float(lo[0])
	var cl := float(co[1]) - float(co[0])
	var cy := float(c.get("coche_y", y + 1.2))
	_colision_caja(coche, Vector3(cl, 0.4, 2.8), Vector3(cx, cy - y - 0.2, 0))
	_caja_mesh(coche, Vector3(cl, 0.4, 2.8), Vector3(cx, cy - y - 0.2, 0), _mm(Color(0.36, 0.26, 0.18), 0.0, 0.9))
	_caja_mesh(coche, Vector3(cl, 0.5, 2.6), Vector3(cx, cy - y - 0.65, 0), negro)
	for s in [-1.0, 1.0]:
		_colision_caja(coche, Vector3(0.9, 0.9, 2.8), Vector3(cx + s * (cl / 2 - 0.45), cy - y + 0.45, 0))
		_caja_mesh(coche, Vector3(0.9, 0.9, 2.8), Vector3(cx + s * (cl / 2 - 0.45), cy - y + 0.45, 0), _mm(Color(0.6, 0.55, 0.42), 0.0, 0.95))
		_caja_mesh(coche, Vector3(cl - 1.8, 0.06, 0.06), Vector3(cx, cy - y + 1.0, s * 1.35), negro)
		for k in 4:
			_caja_mesh(coche, Vector3(0.06, 1.0, 0.06), Vector3(cx - cl / 2 + 0.9 + k * (cl - 1.8) / 3, cy - y + 0.5, s * 1.35), negro)
		for dx in [-0.5, 0.5]:
			_cil_mesh(coche, 0.42, 0.12, Vector3(cx + s * (cl / 2 - 1.0) + dx, 0.45, 0.75), negro, Vector3(PI / 2, 0, 0), 14)
			_cil_mesh(coche, 0.42, 0.12, Vector3(cx + s * (cl / 2 - 1.0) + dx, 0.45, -0.75), negro, Vector3(PI / 2, 0, 0), 14)
	# los seis bidones de gasoil repartidos por la estacion
	for i in (c["bidones"] as Array).size():
		_obj_crear("bidon%d" % i, "bidon", _v(c["bidones"][i]))
	_rotulo("tapon", "DEPÓSITO DE GASOIL", _v(c["tapon"]) + Vector3(0, 2.8, -0.6), Color(1.0, 0.85, 0.2))


func _gasoil_refrescar() -> void:
	if is_instance_valid(_tren_gasoil_label):
		_tren_gasoil_label.text = "GASOIL %d / 6" % _gasoil


func _p20_carga(n: int) -> void:
	_gasoil = n
	_gasoil_refrescar()
	Audio.play3d("gen/gasoil/verter", _v(_c("p20_gasoil").get("tapon", [0, 0, 0])) + Vector3.UP, 2.0, 0.05, 30.0, Audio.PRI_HIGH)
	if n < 6:
		_mensaje_local("GASOIL %d DE 6" % n)
	else:
		_quitar_cartel("tapon")
		_piloto4(_mandos4.get("p20_arranque"), "espera")          # ya se puede arrancar
		_mensaje_local("¡DEPÓSITO LLENO! ARRANCAD LA LOCOMOTORA")


func _p20_arranca() -> void:
	_pulsar4("p20_arranque")
	if is_instance_valid(_tren_humo):
		_tren_humo.emitting = true
	if is_instance_valid(_tren_foco):
		create_tween().tween_property(_tren_foco, "light_energy", 6.0, 2.0)
	var ar := _v(_c("p20_gasoil").get("arranque", [0, 0, 0]))
	Audio.play3d("gen/tren/arranque", ar, 6.0, 0.0, 120.0, Audio.PRI_TOP)
	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(_tren):
			_tren_motor = _bucle_directo("res://sounds/gen/tren/motor1.ogg", _tren, Vector3(3, 2.5, 0), 2.0, 120.0)
		Audio.play3d("gen/tren/bocina", ar, 8.0, 0.0, 300.0, Audio.PRI_TOP))
	_mensaje_local("¡EL MOTOR ARRANCA! Aguantad mientras calienta")


# ======================================================================================================
# AL EMPEZAR
# ======================================================================================================
func _al_empezar() -> void:
	Audio.bf2d("amb/radio", -4.0, Audio.PRI_MID)
	_mensaje_local("PILOTO: «Sin combustible, no llego más lejos. En el valle sale el ÚLTIMO TREN. ¡Bajad por la presa!»")
	var grillos := _bucle_bf("bf/amb/bucle_grillos", self, Vector3.ZERO, -8.0, 400.0)
	if grillos and is_instance_valid(jugador):
		grillos.reparent(jugador, false)
		grillos.position = Vector3.ZERO
	if not _soy_host:
		Net.net_campana_pide("estado4")
	elif _en_red:
		_mandar_estado()
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--ir="):
			_ir_a(String(a).substr(5).replace("_", " "))


## --ir=<punto de la ruta>: te deja alli con los puzzles de antes ya resueltos (para probar a mano)
func _ir_a(nombre: String) -> void:
	var i := _indice_de(nombre)
	if i >= ruta.size():
		_mensaje_local("--ir: no hay ningun punto '%s'" % nombre)
		return
	if not _soy_host:
		return
	var orden := [["p01", "carretera"], ["p02", "coronacion"], ["p03", "tras el camion"], ["p04", "fondo de la torre"],
		["p05", "galeria oeste"], ["p06", "sala de valvulas"], ["p07", "escalera"], ["p08", "tunel de la central"],
		["p09", "pozo"], ["p10", "fondo del pozo"], ["p11", "salida del desague"], ["p12", "embarcadero"],
		["p13", "muelle sur"], ["p14", "mirador"], ["p15", "serreria"], ["p16", "obra"], ["p17", "playa de vias"],
		["p18", "aguja"], ["p19", "locomotora"]]
	for par_o in orden:
		if i >= _indice_de(String(par_o[1])):
			if String(par_o[0]) == "p15":
				_evento("p15", [])
			elif String(par_o[0]) == "p18":
				_evento("p18", [])
				_evento("p18_llave", [])
			elif String(par_o[0]) == "p13":
				_evento("p13", [])
			else:
				_evento(String(par_o[0]), [])
	if i >= _indice_de("refugio"):
		fase = "refugio"
	progreso = i
	await get_tree().create_timer(0.5).timeout
	if is_instance_valid(jugador):
		jugador.global_position = ruta[i] + Vector3.UP * 0.4
	for b in get_tree().get_nodes_in_group("aliados_pve"):
		if is_instance_valid(b) and b.has_method("teletransportar_a"):
			b.teletransportar_a(jugador)
	fase = _fase_por_hecho()
	print("[campana4] --ir=%s: fase %s" % [nombre, fase])


## La fase que toca segun lo que ya esta hecho (para --ir y para quien entra tarde)
func _fase_por_hecho() -> String:
	for k in ["p01", "p02", "p03", "p04", "p05", "p06", "p07", "p08", "p09", "p10", "p11", "p12", "p13"]:
		if not _h(k):
			return k
	if progreso < _indice_de("refugio"):
		return "camino_refugio"
	for k in ["p14", "p15", "p16", "p17", "p18", "p19"]:
		if not _h(k):
			return k
	return "p20"


# ======================================================================================================
# CADA CUADRO
# ======================================================================================================
func _process_sin_medir(dt: float) -> void:
	super._process_sin_medir(dt)
	_vagoneta_tick(dt)
	_rotulos_tick(dt)
	_vapor_tick(dt)
	_fuego_tick(dt)
	_valla_tick(dt)
	_corriente(dt)
	_tirolina_tick(dt)
	_vagon_tick(dt)
	_bola_idle(dt)
	_grua_cables_tick()
	_p04_cuerdas_tick()
	if _man_girando_red and (_barcaza_fase == 1 or _barcaza_fase == 3):
		_man_gira(_man1 if _barcaza_fase == 1 else _man2, dt)
	if (_en_red and not _soy_host) or terminado or world == null:
		return
	_mecha_tick(dt)
	_barcaza_host(dt)
	_final_tick4(dt)
	_bots_t -= dt
	if _bots_t <= 0.0:
		_bots_t = 2.0
		_bots_al_dia()
	_comprobar_t -= dt
	if _comprobar_t > 0.0:
		return
	_comprobar_t = 0.25
	_obj_revisar()
	# 1: el calzo
	var c1 := _c("p01_vagoneta")
	if not _h("p01") and not c1.is_empty() and _cortado("calzo", c1["calzo"], 0.4):
		_evento("p01", [])
	# 4: la placa y el taco
	var c4 := _c("p04_placa")
	if not _h("p04") and not c4.is_empty():
		if _cortado("taco", c4["taco"], 0.35):
			_evento("p04", [])
		else:
			var pl: Array = c4["placa"]
			var hay := false
			var cuerpos := _jugadores_vivos() + get_tree().get_nodes_in_group("aliados_pve")
			for q in cuerpos:
				if not is_instance_valid(q):
					continue
				var p: Vector3 = (q as Node3D).global_position
				if p.x > float(pl[0]) - 0.15 and p.x < float(pl[3]) + 0.15 and p.z > float(pl[2]) - 0.15 and p.z < float(pl[5]) + 0.15 and absf(p.y - float(pl[1])) < 1.0:
					hay = true
					break
			if hay != _p04_pisada:
				_evento("p04_placa", [1 if hay else 0])
	# 12: los aisladores
	var c12 := _c("p12_valla")
	if not _h("p12") and not c12.is_empty():
		var rotos := 0
		for i in (c12["aisladores"] as Array).size():
			if bool(_aisladores_rotos[i]):
				rotos += 1
			elif _cortado("aislador%d" % i, c12["aisladores"][i], 0.45):
				_evento("p12_aislador", [i])
				rotos += 1
		if rotos >= 3:
			_evento("p12", [])


func _physics_process(dt: float) -> void:
	_barcaza_fisica(dt)


func _fuego_tick(dt: float) -> void:
	if not _fuego_vivo or not is_instance_valid(_fuego_luz):
		return
	_fuego_luz.light_energy = 2.6 + sin(Time.get_ticks_msec() * 0.013) * 0.5 + randf() * 0.4
	if not is_instance_valid(jugador) or bool(jugador.get("spectating")):
		return
	var r: Array = _c("p03_fuego").get("rect", [0, 0, 0, 0, 0, 0])
	var jp: Vector3 = jugador.global_position
	if jp.x > float(r[0]) - 0.8 and jp.x < float(r[3]) + 0.8 and jp.z > float(r[2]) - 0.8 and jp.z < float(r[5]) + 0.8 and jp.y < float(r[4]):
		_dano_local(25.0 * dt, Vector3(-2.0, 0, 0), "¡QUEMA! No se puede pasar por el fuego")


## LA CORRIENTE: quien se mete en el rio sale arrastrado a la orilla (a la que toque) y con frio. En el caz, hacia
## su escalera. Asi el rio no se cruza a nado ni se rodea la valla por el agua.
func _corriente(dt: float) -> void:
	if not is_instance_valid(jugador) or bool(jugador.get("spectating")) or _tirolina_t >= 0.0:
		return
	var p: Vector3 = jugador.global_position
	var c := _c("p13_barcaza")
	var rio: Array = c.get("rio", [0, 100, 176, 122])
	var destino := Vector3.INF
	if p.x > float(rio[0]) and p.x < float(rio[2]) and p.z > float(rio[1]) and p.z < float(rio[3]) and p.y < AGUA_RIO + 0.2:
		if is_instance_valid(_barcaza) and _en_barcaza(p):
			return
		if _h("p13"):
			destino = Vector3(float(c.get("x", 162.0)), p.y, 121.0)
		else:
			destino = Vector3(clampf(p.x - 4.0, 64.0, 170.0), p.y, 98.8)
	var cz := _c("p16_pasarelas")
	var caz: Array = cz.get("caz", [0, 0, 0, 0])
	if caz.size() >= 4 and p.x > float(caz[0]) and p.x < float(caz[2]) and p.z > float(caz[1]) and p.z < float(caz[3]) and p.y < float(cz.get("agua", 1.4)) + 0.2:
		destino = Vector3(60.0, p.y, 147.0)
	if destino == Vector3.INF:
		return
	var d := destino - p
	d.y = 0.0
	if d.length() > 0.4:
		jugador.global_position += d.normalized() * 3.2 * dt
	_frio_t -= dt
	if _frio_t <= 0.0:
		_frio_t = 1.0
		if jugador.has_method("take_damage") and not bool(jugador.get("invulnerable")):
			jugador.take_damage(3.0, Vector3.ZERO)
		var ahora := Time.get_ticks_msec() * 0.001
		if ahora - _dano_aviso_t > 4.0:
			_dano_aviso_t = ahora
			_mensaje_local("¡LA CORRIENTE TE ARRASTRA!")


func _mecha_tick(dt: float) -> void:
	if _mecha_t < 0.0:
		return
	_mecha_t -= dt
	if _mecha_t <= 0.0:
		_mecha_t = -1.0
		var o: Dictionary = _obj4.get("bombona", {})
		var p: Vector3 = o.get("pos", Vector3.ZERO)
		Net.net_explode(world, p + Vector3(0, 0.8, 0), 3.4, 255)
		Combat.damage_around(get_tree(), p + Vector3.UP, 6.0, 150.0, null, false)
		_evento("p11", [])
		_horda(HORDA_TAM, "¡LA EXPLOSIÓN HA ATRAÍDO A LA HORDA!")




# ======================================================================================================
# LA HISTORIA (el anfitrion)
# ======================================================================================================
const TEXTOS := {
	"p01": "La carretera está cortada · REVENTAD EL CALZO de la vagoneta de la cantera",
	"p02": "LA PUERTA DE LA PRESA · bajad las DOS PALANCAS a la vez (una en cada garita)",
	"p03": "EL CAMIÓN ARDE · abrid la LLAVE GENERAL de la caseta de bombeo y luego la BOCA DE INCENDIOS",
	"p04": "LA TORRE DE TOMA · su puerta solo se abre con PESO en la placa",
	"p05": "LA GALERÍA ESTÁ A OSCURAS · encended las 4 luces del CUADRO",
	"p06": "VAPOR · pasad entre los chorros y CERRAD LA LLAVE del final",
	"p07": "LAS VÁLVULAS · el orden está en la PIZARRA de la sala del vigilante",
	"p08": "LA ESCLUSA · TODOS DENTRO y cerrad la compuerta",
	"p09": "EL POZO INUNDADO · conectad las TUBERÍAS del panel de la entreplanta",
	"p10": "EL RODETE TAPA EL DESAGÜE · usad el MANDO DE LA GRÚA",
	"p11": "EL DERRUMBE · traed la BOMBONA del taller, dejadla en la marca y encended la mecha",
	"p12": "VALLA ELECTRIFICADA · reventad los 3 AISLADORES del transformador",
	"p13": "EL RÍO · girad la MANIVELA para traer la barcaza (quedaos a su lado)",
	"camino_refugio": "Subid al PUEBLO: el REFUGIO es la casa del guarda",
	"p14": "EL PORTÓN DEL PUEBLO · buscad la LLAVE en las casas",
	"p15": "EL DEPÓSITO DE AGUA · subid, tensad el cable con el TORNO y bajad por la TIROLINA",
	"p16": "EL CAZ · accionad las PASARELAS, cruzad antes de que se hundan y BLOQUEADLAS al otro lado",
	"p17": "EL MURO DE LA ESTACIÓN · usad la GRÚA DE DEMOLICIÓN (3 golpes)",
	"p18": "LA OFICINA · la clave está en el ANDÉN, el RELOJ y el VAGÓN",
	"p19": "EL VAGÓN TAPA LA VÍA · AGUJA a la vía muerta, soltad el FRENO, AGUJA a la vía 1",
	"p20": "GASOIL · traed los 6 BIDONES a la locomotora",
	"arrancar": "¡DEPÓSITO LLENO! ARRANCAD LA LOCOMOTORA",
}




func _historia() -> void:
	match fase:
		"inicio":
			_poner_fase("p01", TEXTOS["p01"])
		"p01", "p02", "p03", "p04", "p05", "p06", "p07", "p08", "p09", "p10", "p11", "p12", "p14", "p15", "p16", "p17":
			if _h(fase):
				var sig := {"p01": "p02", "p02": "p03", "p03": "p04", "p04": "p05", "p05": "p06", "p06": "p07", "p07": "p08",
					"p08": "p09", "p09": "p10", "p10": "p11", "p11": "p12", "p12": "p13", "p14": "p15", "p15": "p16", "p16": "p17",
					"p17": "p18"}
				var s: String = sig[fase]
				_poner_fase(s, TEXTOS[s])
			elif fase == "p15" and _cable_tenso:
				_texto = "¡CABLE TENSO! Bajad todos por la TIROLINA"
			elif fase == "p18" and _h("p18") and not _llave_loco:
				_texto = "Coged la LLAVE DE LA LOCOMOTORA de la mesa de la oficina"
			elif fase == "p11" and String(_obj4.get("bombona", {}).get("estado", "")) == "puesto":
				_texto = "LA BOMBONA ESTÁ EN SU SITIO · ENCENDED LA MECHA y alejaos"
			elif fase == "p10" and not _h("p09"):
				_texto = TEXTOS["p09"]
			elif fase == "p10" and _pozo_vaciando:
				_texto = "LAS BOMBAS VACÍAN EL POZO…"
		"p13":
			if _barcaza_fase == 2:
				var vivos := _jugadores_vivos()
				var dentro := 0
				for pl in vivos:
					if _en_barcaza((pl as Node3D).global_position):
						dentro += 1
				_texto = "TODOS A LA BARCAZA y girad su MANIVELA · %d de %d a bordo" % [dentro, vivos.size()]
			elif _barcaza_fase == 0:
				_texto = TEXTOS["p13"]
			if _h("p13"):
				_poner_fase("camino_refugio", TEXTOS["camino_refugio"])
		"camino_refugio":
			var ref: Dictionary = _c("refugio")
			if not ref.is_empty() and _todos_dentro(ref["rect"], float(ref.get("suelo", 0.0)) - 1.0):
				_poner_fase("refugio", "")
				_llegar_al_refugio()
		"refugio":
			if progreso >= _indice_de("calle del pueblo"):
				_poner_fase("p14", TEXTOS["p14"])
		"p18":
			if _h("p18") and _llave_loco:
				_poner_fase("p19", TEXTOS["p19"])
			elif _h("p18"):
				_texto = "Coged la LLAVE DE LA LOCOMOTORA de la mesa de la oficina"
		"p19":
			if _h("p19"):
				_poner_fase("p20", TEXTOS["p20"] + " · 0 de 6")
				_tanda_final_t = 6.0
				_horda(HORDA_TAM, "¡VIENE LA HORDA! ¡A por el gasoil!")
			elif _vagon_fuera:
				_texto = "¡El vagón está en la vía muerta! Ahora la AGUJA otra vez a la VÍA 1"
		"p20":
			_texto = "%s · %d de 6" % [TEXTOS["p20"], _gasoil]
			if _gasoil >= 6:
				_poner_fase("arrancar", TEXTOS["arrancar"])
		"arrancar":
			pass
		"calentar":
			_texto = "LA LOCOMOTORA CALIENTA · %d s · ¡AGUANTAD!" % ceili(maxf(_calentar_t, 0.0))
		"subir":
			var vivos2 := _jugadores_vivos()
			var dentro2 := 0
			for pl in vivos2:
				if _en_tren((pl as Node3D).global_position):
					dentro2 += 1
			_texto = "¡TODOS AL TREN! · %d de %d en la plataforma" % [dentro2, vivos2.size()]
			if dentro2 == vivos2.size() and vivos2.size() > 0:
				terminado = true
				_poner_fase("fin", "")
				_evento("escapan", [])
				_mensaje("¡HABÉIS ESCAPADO!")
				_objetivo("VICTORIA · %d bajas" % bajas)
				if _en_red:
					Net.net_fin_pve(true, FINAL.size(), bajas, puntos)
				get_tree().create_timer(3.0).timeout.connect(func(): _fin(true))


func _en_tren(p: Vector3) -> bool:
	var c := _c("p20_gasoil")
	var co: Array = c.get("coche", [0, 0])
	var lo: Array = c.get("loco", [0, 0])
	var vz := float(c.get("via_z", 142.0))
	var x0 := float(lo[1]) - 3.2
	var x1 := float(co[1])
	if is_instance_valid(_tren):
		var dx := _tren.global_position.x - float(lo[0])
		x0 += dx
		x1 += dx
	return p.x > x0 and p.x < x1 and absf(p.z - vz) < 1.6 and p.y > float(c.get("y", 4.0)) + 0.8


## El final: tandas de horda mientras se trae el gasoil, el Tank al tercer bidon, y la espera del motor
func _final_tick4(dt: float) -> void:
	if fase == "p20" or fase == "calentar":
		_tanda_final_t -= dt
		if _tanda_final_t <= 0.0:
			_tanda_final_t = 14.0 if fase == "p20" else 9.0
			if _cola.size() < 8:
				_horda(8 if fase == "p20" else 10, "")
		if fase == "p20" and _gasoil >= 3 and not _final_tank:
			_final_tank = true
			_cola.push_front("tanque")
			_mensaje("¡UN TANK!")
	if fase == "calentar":
		_calentar_t -= dt
		if _calentar_t <= 0.0:
			_poner_fase("subir", "¡TODOS AL TREN! Subid a la PLATAFORMA")
			_evento("tren_listo", [])


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
			if progreso < _indice_de("barricada") - 1:
				return [_centro(_c("p01_vagoneta").get("calzo", [0, 0, 0, 0, 0, 0])), "CALZO DE LA VAGONETA"]
			return [_centro(_c("p01_vagoneta").get("calzo", [0, 0, 0, 0, 0, 0])), "CALZO · REVENTADLO"]
		"p02":
			var pl: Array = _c("p02_palancas").get("palancas", [[0, 0, 0]])
			var cual := 0 if Time.get_ticks_msec() % 8000 < 4000 else 1
			return [_v(pl[cual]), "PALANCA %d" % (cual + 1)]
		"p03":
			if not _p03_presion:
				return [_v(_c("p03_fuego").get("llave", [0, 0, 0])), "LLAVE GENERAL DE BOMBEO"]
			return [_v(_c("p03_fuego").get("boca", [0, 0, 0])), "BOCA DE INCENDIOS"]
		"p04":
			if _p04_pisada:
				return [_centro(_c("p04_placa").get("taco", [0, 0, 0, 0, 0, 0])), "TACO DE LA CUERDA · REVENTADLO"]
			return [_centro(_c("p04_placa").get("placa", [0, 0, 0, 0, 0, 0])), "PLACA"]
		"p05":
			return [_v(_c("p05_cuadro").get("pos", [0, 0, 0])), "CUADRO DE LUCES"]
		"p06":
			return [_v(_c("p06_vapor").get("llave", [0, 0, 0])), "LLAVE DEL VAPOR"]
		"p07":
			if progreso < _indice_de("sala de valvulas") and not _vio_pizarra:
				return [_v(_c("p07_valvulas").get("pizarra", [0, 0, 0])), "PIZARRA DEL VIGILANTE"]
			return [ruta[_indice_de("sala de valvulas")], "VÁLVULAS"]
		"p08":
			return [_v(_c("p08_esclusa").get("palanca", [0, 0, 0])), "ESCLUSA · TODOS DENTRO"]
		"p09":
			return [_v(_c("p09_tubos").get("centro", [0, 0, 0])) + Vector3(0, -1.5, -1.0), "PANEL DE LAS BOMBAS"]
		"p10":
			if not _h("p09"):
				return [_v(_c("p09_tubos").get("centro", [0, 0, 0])) + Vector3(0, -1.5, -1.0), "PANEL DE LAS BOMBAS"]
			return [_v(_c("p10_grua").get("mando", [0, 0, 0])), "MANDO DE LA GRÚA"]
		"p11":
			var o: Dictionary = _obj4.get("bombona", {})
			var est := String(o.get("estado", "suelo"))
			if est == "suelo":
				return [o.get("pos", Vector3.ZERO), "BOMBONA"]
			return [_v(_c("p11_bombona").get("marca", [0, 0, 0])), "MARCA DEL DERRUMBE"]
		"p12":
			for i in 3:
				if not bool(_aisladores_rotos[i]):
					return [_centro(_c("p12_valla")["aisladores"][i]), "AISLADOR %d" % (i + 1)]
		"p13":
			if _barcaza_fase <= 1:
				return [_v(_c("p13_barcaza").get("manivela", [0, 0, 0])), "MANIVELA"]
			return [_man2.global_position if is_instance_valid(_man2) else ruta[progreso], "BARCAZA · MANIVELA"]
		"camino_refugio":
			return [sig.call("refugio"), "REFUGIO"]
		"refugio":
			var ps = _c("refugio").get("puerta_salida", null)
			return [_v([ps[0], _c("refugio").get("suelo", 8.0), ps[1]]) if ps != null else ruta[progreso], "SALIDA DEL REFUGIO"]
		"p14":
			if _llave_pueblo:
				return [_v(_c("p14_llave").get("candado", [0, 0, 0])), "CANDADO DEL PORTÓN"]
			return [_v(_c("p14_llave").get("candado", [0, 0, 0])) + Vector3(20, 0, 0), "BUSCAD LA LLAVE EN LAS CASAS"]
		"p15":
			if not _cable_tenso:
				return [_v(_c("p15_tirolina").get("torno", [0, 0, 0])), "TORNO DEL CABLE"]
			return [_v(_c("p15_tirolina").get("arriba", [0, 0, 0])), "TIROLINA"]
		"p16":
			if progreso >= _indice_de("caz") and _alguien_cerca(_v(_c("p16_pasarelas").get("bloqueo", [0, 0, 0])), 12.0):
				return [_v(_c("p16_pasarelas").get("bloqueo", [0, 0, 0])), "BLOQUEO DE LAS PASARELAS"]
			return [_v(_c("p16_pasarelas").get("palanca", [0, 0, 0])), "PALANCA DE LAS PASARELAS"]
		"p17":
			return [_v(_c("p17_bola").get("cabina", [0, 0, 0])), "GRÚA DE DEMOLICIÓN"]
		"p18":
			if _h("p18"):
				return [_v(_c("p18_combinacion").get("llave", [0, 0, 0])), "LLAVE DE LA LOCOMOTORA"]
			return [_v(_c("p18_combinacion").get("diales", [0, 0, 0])), "OFICINA · CLAVE"]
		"p19":
			if _vagon_fuera:
				return [_v(_c("p19_agujas").get("palanca", [0, 0, 0])), "AGUJA · A LA VÍA 1"]
			if _aguja == 0:
				return [_v(_c("p19_agujas").get("palanca", [0, 0, 0])), "AGUJA · A LA VÍA MUERTA"]
			return [_v(_c("p19_agujas").get("freno", [0, 0, 0])), "FRENO DEL VAGÓN"]
		"p20":
			var llevo := _llevo()
			if llevo != "":
				return [_v(_c("p20_gasoil").get("tapon", [0, 0, 0])), "DEPÓSITO DE LA LOCOMOTORA"]
			var mejor := Vector3.INF
			var jp: Vector3 = jugador.global_position if is_instance_valid(jugador) else Vector3.ZERO
			for id in _obj4:
				var ob: Dictionary = _obj4[id]
				if String(ob["tipo"]) == "bidon" and String(ob["estado"]) == "suelo":
					var q: Vector3 = ob["pos"]
					if mejor == Vector3.INF or q.distance_to(jp) < mejor.distance_to(jp):
						mejor = q
			if mejor != Vector3.INF:
				return [mejor, "BIDÓN DE GASOIL"]
			return [_v(_c("p20_gasoil").get("tapon", [0, 0, 0])), "DEPÓSITO DE LA LOCOMOTORA"]
		"arrancar":
			return [_en_mando4("p20_arranque", _v(_c("p20_gasoil").get("arranque", [0, 0, 0])), 0.0), "ARRANQUE"]
		"calentar":
			return [_v(_c("p20_gasoil").get("arranque", [0, 0, 0])), "LOCOMOTORA · AGUANTAD"]
		"subir":
			var co: Array = _c("p20_gasoil").get("coche", [0, 0])
			return [Vector3((float(co[0]) + float(co[1])) / 2, 5.2, float(_c("p20_gasoil").get("via_z", 142.0))), "¡AL TREN!"]
	return [Vector3.INF, ""]


var _vio_pizarra := false


## Hasta donde pueden salir bichos: nunca al otro lado de lo que sigue cerrado
func _tope_ruta() -> int:
	var cierres := [["p01", "barricada"], ["p02", "puerta de la presa"], ["p03", "camion"], ["p04", "torre de toma"],
		["p05", "galeria"], ["p07", "sala de valvulas"], ["p08", "esclusa"], ["p10", "pozo"], ["p11", "derrumbe"],
		["p12", "valla"], ["p13", "embarcadero"], ["p14", "porton del pueblo"], ["p15", "deposito"], ["p16", "caz"],
		["p17", "obra"]]
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
	# (cada usable, encima de su mando: el volante, la palanca, la manivela, el asa, la boca de carga...)
	# 2 las palancas
	if not _h("p02") and _h("p01"):
		var pl: Array = _c("p02_palancas").get("palancas", [])
		for i in pl.size():
			_u("p02_%d" % i, _v(pl[i]) + Vector3(0, 1.4, 0), "BAJAR LA PALANCA %d (las dos a la vez)" % (i + 1))
	# 3 el fuego
	if not _h("p03") and _h("p02"):
		if not _p03_presion:
			_u("p03_llave", _en_mando4("p03_llave", _v(_c("p03_fuego")["llave"]) + Vector3(0, 1.1, 0.2), 0.2), "ABRIR LA LLAVE GENERAL DE BOMBEO")
		_u("p03_boca", _en_mando4("p03_boca", _v(_c("p03_fuego")["boca"]) + Vector3(0, 1.0, -0.2), 0.22), "ABRIR LA BOCA DE INCENDIOS")
	# 5 el cuadro
	if not _h("p05") and _h("p04"):
		for i in 4:
			_u("p05_%d" % i, _en_mando4("p05_%d" % i, _cuadro_pos(i), 0.17), "INTERRUPTOR %d" % (i + 1), 2.0)
	# 6 la llave del vapor
	if not _h("p06") and _h("p05"):
		_u("p06_llave", _en_mando4("p06_llave", _v(_c("p06_vapor")["llave"]) + Vector3(0, 1.2, 0.3), 0.2), "CERRAR LA LLAVE DEL VAPOR")
	# 7 las valvulas
	if not _h("p07") and _h("p06"):
		var cv := _c("p07_valvulas")
		for i in (cv["x"] as Array).size():
			_u("p07_%d" % i, Vector3(float(cv["x"][i]), float(cv["y"]) + 1.4, float(cv["z"]) + 1.3), "GIRAR ESTA VÁLVULA", 2.4)
		if not _vio_pizarra and is_instance_valid(jugador) and jp.distance_to(_v(cv["pizarra"])) < 3.5:
			_vio_pizarra = true
	# 8 la esclusa
	if not _h("p08") and _h("p07"):
		_u("p08_palanca", _en_mando4("p08_palanca", _v(_c("p08_esclusa")["palanca"]) + Vector3(0, 1.2, 0.3), 0.15), "CERRAR LA COMPUERTA A (todos dentro)")
	# 9 las tuberias
	if not _h("p09") and _h("p08"):
		for i in 9:
			_u("p09_%d" % i, _tubo_pos(i), "GIRAR ESTE CODO", 2.6)
	# 10 la grua
	if not _h("p10") and _h("p09") and not _pozo_vaciando:
		_u("p10_mando", _en_mando4("p10_mando", _v(_c("p10_grua")["mando"]) + Vector3(0, 1.2, -0.2), 0.15), "MOVER LA GRÚA (sacar el rodete)")
	# 11 / 20 lo que se lleva
	var llevo := _llevo()
	for id in _obj4:
		var o: Dictionary = _obj4[id]
		if llevo == "" and String(o["estado"]) == "suelo" and is_instance_valid(o["nodo"]) and (o["pos"] as Vector3).distance_to(jp) < 2.2:
			if String(o["tipo"]) == "bombona" and _h("p10"):
				_u("coger:" + String(id), (o["pos"] as Vector3) + Vector3(0, 0.7, 0), "COGER LA BOMBONA")
			elif String(o["tipo"]) == "bidon" and _h("p17"):
				_u("coger:" + String(id), (o["pos"] as Vector3) + Vector3(0, 0.5, 0), "COGER EL BIDÓN DE GASOIL")
	if llevo != "":
		var marca := _v(_c("p11_bombona").get("marca", [0, 0, 0]))
		var tapon := _v(_c("p20_gasoil").get("tapon", [0, 0, 0]))
		if llevo == "bombona" and jp.distance_to(marca) < 3.0:
			_u("p11_poner", marca + Vector3(0, 0.8, 0), "DEJAR LA BOMBONA JUNTO AL DERRUMBE", 3.0)
		elif llevo.begins_with("bidon") and jp.distance_to(tapon) < 3.2 and _h("p19"):
			var boca_g := _boca_gasoil.global_transform * Vector3(0, 0.25, -0.28) if is_instance_valid(_boca_gasoil) else tapon + Vector3(0, 1.2, 0)
			_u("p20_verter", boca_g, "ECHAR EL GASOIL (%d de 6)" % (_gasoil + 1), 3.2)
		else:
			_u("soltar", jp + Vector3(0, 1.0, 0), "SOLTAR LO QUE LLEVAS", 5.0)
	var bo: Dictionary = _obj4.get("bombona", {})
	if not bo.is_empty() and String(bo["estado"]) == "puesto" and _mecha_t < 0.0 and not _h("p11"):
		_u("p11_mecha", (bo["pos"] as Vector3) + Vector3(0, 1.0, 0), "ENCENDER LA MECHA (¡y correr!)", 2.4)
	# 13 la barcaza
	if not _h("p13") and _h("p12"):
		if _barcaza_fase == 0:
			_u("p13_man1", _en_mando4("p13_man1", _v(_c("p13_barcaza")["manivela"]) + Vector3(0, 1.0, 0), 0.2), "GIRAR LA MANIVELA (traer la barcaza)", 2.4)
		elif _barcaza_fase == 2 and is_instance_valid(_man2):
			_u("p13_man2", _en_mando4("p13_man2", _man2.global_position + Vector3(0, 1.0, 0), 0.2), "GIRAR LA MANIVELA (todos a bordo)", 2.4)
	# 14 la llave y el candado
	if not _h("p14") and _h("p13"):
		if not _llave_pueblo and is_instance_valid(_llave_nodo) and _llave_nodo.global_position.distance_to(jp) < 2.4:
			_u("p14_llave", _llave_nodo.global_position + Vector3(0, 0.2, 0), "COGER LA LLAVE DEL PORTÓN", 2.4)
		_u("p14_candado", _v(_c("p14_llave")["candado"]) + Vector3(0, 1.1, 0), "ABRIR EL CANDADO" if _llave_pueblo else "EL CANDADO (hace falta la llave)")
	# 15 el torno y la tirolina
	if _h("p14"):
		if not _cable_tenso:
			_u("p15_torno", _v(_c("p15_tirolina")["torno"]) + Vector3(0, 1.0, 0), "TENSAR EL CABLE CON EL TORNO")
		elif _tirolina_t < 0.0:
			var asa := _v(_c("p15_tirolina")["arriba"]) + Vector3(0, 1.2, 0)
			if is_instance_valid(_tirolina_parado) and _tirolina_parado.is_inside_tree():
				asa = (_tirolina_parado.get_node("Asa") as Node3D).global_position
			_u("tirolina", asa, "BAJAR POR LA TIROLINA", 2.6)
	# 16 las pasarelas
	if not _h("p16") and _h("p15"):
		if not _pasarelas_ocupadas:
			_u("p16_palanca", _v(_c("p16_pasarelas")["palanca"]) + Vector3(0, 1.3, 0), "ACCIONAR LAS PASARELAS (suben unos segundos)")
		_u("p16_bloqueo", _v(_c("p16_pasarelas")["bloqueo"]) + Vector3(0, 1.3, 0), "BLOQUEAR LAS PASARELAS ARRIBA")
	# 17 la bola
	if not _h("p17") and _h("p16") and not _bola_ocupada:
		_u("p17_grua", _en_mando4("p17_grua", _v(_c("p17_bola")["cabina"]) + Vector3(0, 1.2, 0), 0.15), "ACCIONAR LA GRÚA (golpe %d de 3)" % (_bola_golpes + 1))
	# 18 los diales y la llave de la locomotora
	if _h("p17"):
		if not _h("p18"):
			for i in 3:
				_u("p18_%d" % i, _dial_pos(i), "GIRAR EL DIAL %d (ahora %d)" % [i + 1, int(_diales[i])], 2.2)
		elif not _llave_loco:
			_u("p18_llave", _v(_c("p18_combinacion")["llave"]) + Vector3(0, 0.3, 0), "COGER LA LLAVE DE LA LOCOMOTORA", 2.4)
	# 19 la aguja y el freno
	if _h("p17") and not _h("p19"):
		_u("p19_aguja", _v(_c("p19_agujas")["palanca"]) + Vector3(0, 1.4, 0), "CAMBIAR LA AGUJA (ahora: %s)" % ("VÍA 1" if _aguja == 0 else "VÍA MUERTA"))
		if not _vagon_fuera:
			_u("p19_freno", _en_mando4("p19_freno", _v(_c("p19_agujas")["freno"]) + Vector3(0, 1.6, -0.3), 0.2), "SOLTAR EL FRENO DEL VAGÓN")
	# 20 el arranque
	if fase == "arrancar" or (_gasoil >= 6 and fase == "p20"):
		_u("p20_arranque", _en_mando4("p20_arranque", _v(_c("p20_gasoil")["arranque"]), 0.15), "ARRANCAR LA LOCOMOTORA" if _llave_loco else "ARRANCAR (falta la llave)", 2.6)


func usar_desde_jugador() -> void:
	if _usable_mirado == "tirolina":
		_tirolina_bajar()
		return
	super.usar_desde_jugador()




func _pide_extra(accion: String) -> void:
	var de := _pide_de
	if accion.begins_with("coger:"):
		var id := accion.substr(6)
		var o: Dictionary = _obj4.get(id, {})
		if o.is_empty() or String(o["estado"]) != "suelo" or _lleva_id(de) != "":
			return
		var p: Vector3 = o["pos"]
		_evento("obj4", [id, "lleva", de, p.x, p.y, p.z])
		return
	if accion == "soltar":
		var id2 := _lleva_id(de)
		if id2 == "":
			return
		var q := _nodo_de(de)
		var p2: Vector3 = q.global_position if q else Vector3.ZERO
		_evento("obj4", [id2, "suelo", 0, p2.x, p2.y + 0.05, p2.z])
		return
	if accion.begins_with("p02_"):
		var i := int(accion.substr(4))
		var ahora := Time.get_ticks_msec() * 0.001
		_p02_t[i] = ahora
		_evento("p02_palanca", [i])
		if not _h("p02") and absf(float(_p02_t[0]) - float(_p02_t[1])) <= float(_c("p02_palancas").get("ventana", 5.0)):
			_evento("p02", [])
		return
	if accion.begins_with("p05_"):
		if _h("p05"):
			return
		_luces = _pulsar(_luces, int(accion.substr(4)))
		_evento("p05_estado", _luces)
		if not _luces.has(false):
			_evento("p05", [])
			_horda(10, "¡LAS LUCES LOS HAN DESPERTADO!")
		return
	if accion.begins_with("p07_"):
		if _h("p07"):
			return
		var i2 := int(accion.substr(4))
		var orden: Array = par.get("valv_orden", [0, 1, 2])
		if _valv_paso < orden.size() and i2 == int(orden[_valv_paso]):
			_evento("p07_giro", [i2, _valv_paso + 1])
			if _valv_paso >= 3:
				_evento("p07", [])
		else:
			_evento("p07_mal", [])
			_horda(6, "")
		return
	if accion.begins_with("p09_"):
		if _h("p09"):
			return
		var i3 := int(accion.substr(4))
		_tubos_rot[i3] = (int(_tubos_rot[i3]) + 1) % 4
		_evento("p09_rot", _tubos_rot)
		var t: Dictionary = par.get("tubos", {})
		if bool(_flujo(t["tipo"], _tubos_rot)[1]):
			_evento("p09", [])
			_horda(12, "¡EL RUIDO DE LAS BOMBAS ATRAE A LA HORDA!")
		return
	if accion.begins_with("p18_") and accion != "p18_llave":
		if _h("p18"):
			return
		var i4 := int(accion.substr(4))
		_diales[i4] = (int(_diales[i4]) + 1) % 10
		_evento("p18_diales", _diales)
		var cif: Array = par.get("cifras", [])
		if cif.size() >= 3 and int(_diales[0]) == int(cif[0]) and int(_diales[1]) == int(cif[1]) and int(_diales[2]) == int(cif[2]):
			_evento("p18", [])
		return
	match accion:
		"p03_llave":
			if not _p03_presion:
				_evento("p03_llave", [])
		"p03_boca":
			if not _p03_presion:
				_mensaje("NO HAY PRESIÓN · abrid la LLAVE GENERAL en la caseta de bombeo")
			elif not _h("p03"):
				_evento("p03", [])
		"p06_llave":
			if not _h("p06"):
				_evento("p06", [])
		"p08_palanca":
			if _h("p08"):
				return
			var r: Array = _c("p08_esclusa")["rect"]
			var fuera := 0
			for pl in _jugadores_vivos():
				var pp: Vector3 = (pl as Node3D).global_position
				if not (pp.x > float(r[0]) and pp.x < float(r[2]) and pp.z > float(r[1]) and pp.z < float(r[3])):
					fuera += 1
			if fuera > 0:
				_mensaje("FALTAN %d DENTRO DE LA ESCLUSA · no se cierra sin todos" % fuera)
				return
			_evento("p08", [])
		"p10_mando":
			if not _h("p10") and _h("p09") and not _pozo_vaciando:
				_evento("p10", [])
				_horda(8, "")
		"p11_poner":
			var o2: Dictionary = _obj4.get("bombona", {})
			if o2.is_empty() or int(o2["pid"]) != de:
				return
			var m := _v(_c("p11_bombona")["marca"])
			_evento("obj4", ["bombona", "puesto", 0, m.x, m.y, m.z])
		"p11_mecha":
			var o3: Dictionary = _obj4.get("bombona", {})
			if not o3.is_empty() and String(o3["estado"]) == "puesto" and _mecha_t < 0.0:
				_evento("p11_mecha", [])
				_mecha_t = 6.0
		"p13_man1":
			if _barcaza_fase == 0 and _h("p12"):
				_barcaza_fase = 1
				_barcaza_k = 0.0
				_man_tanda_t = 3.0
				_evento("p13_k", [1, 0.0, 1])
				_horda(HORDA_TAM, "¡EL RUIDO DE LA MANIVELA ATRAE A LA HORDA!")
		"p13_man2":
			if _barcaza_fase != 2:
				return
			var vivos := _jugadores_vivos()
			var fuera2 := 0
			for pl in vivos:
				if not _en_barcaza((pl as Node3D).global_position):
					fuera2 += 1
			if fuera2 > 0:
				_mensaje("FALTAN %d EN LA BARCAZA · no se cruza sin todos" % fuera2)
				return
			_barcaza_fase = 3
			_barcaza_k = 0.0
			_man_tanda_t = 4.0
			_bots_a_bordo()
			_evento("p13_k", [3, 0.0, 1])
		"p14_llave":
			if not _llave_pueblo:
				_evento("p14_llave", [])
		"p14_candado":
			if _llave_pueblo and not _h("p14"):
				_evento("p14", [])
			elif not _llave_pueblo:
				_mensaje("EL PORTÓN ESTÁ CERRADO CON CANDADO · buscad la LLAVE en las casas")
		"p15_torno":
			if not _cable_tenso:
				_evento("p15", [])
		"p16_palanca":
			if not _pasarelas_ocupadas and not _pasarelas_fijas:
				_evento("p16_suben", [])
				if randf() < 0.6:
					_horda(6, "")
		"p16_bloqueo":
			if not _pasarelas_fijas:
				_evento("p16", [])
		"p17_grua":
			if _bola_ocupada or _h("p17"):
				return
			var n := _bola_golpes + 1
			_evento("p17_golpe", [n])
			_horda(5, "")
			if n >= 3:
				get_tree().create_timer(3.0).timeout.connect(func(): _evento("p17", []))
		"p18_llave":
			if _h("p18") and not _llave_loco:
				_evento("p18_llave", [])
		"p19_aguja":
			if not _h("p19"):
				var a := 1 - _aguja
				_evento("p19_aguja", [a])
				if a == 0 and _vagon_fuera:
					_evento("p19", [])
		"p19_freno":
			if _vagon_fuera:
				return
			if _aguja == 0:
				_mensaje("¡Así el vagón se iría por la VÍA 1 y taparía el túnel! Antes, la AGUJA a la VÍA MUERTA")
				return
			_evento("p19_vagon", [])
		"p20_verter":
			var id3 := _lleva_id(de)
			if id3 == "" or not id3.begins_with("bidon") or not _h("p19"):
				return
			_evento("obj4", [id3, "usado", 0, 0.0, 0.0, 0.0])
			_evento("p20_carga", [_gasoil + 1])
		"p20_arranque":
			if not (fase == "arrancar" or (_gasoil >= 6 and fase == "p20")):
				return
			if not _llave_loco:
				_mensaje("FALTA LA LLAVE DE LA LOCOMOTORA · está en la oficina del jefe de estación")
				return
			_calentar_t = float(_c("p20_gasoil").get("calentar", 25.0))
			_poner_fase("calentar", "")
			_evento("p20_arranca", [])
			_horda(HORDA_TAM + 6, "¡EL MOTOR HA ATRAÍDO A TODA LA HORDA! ¡AGUANTAD!")
			_cola.push_front("tanque")


func _evento_extra(e: String, datos: Array) -> void:
	match e:
		"fase4":
			if not _soy_host:
				fase = String(datos[0])
		"estado4":
			_aplicar_estado(String(datos[0]))
		"obj4":
			_obj_estado(String(datos[0]), String(datos[1]), int(datos[2]), Vector3(float(datos[3]), float(datos[4]), float(datos[5])))
			_mecha_ver()
		"p02_palanca":
			_p02_tira(int(datos[0]))
		"p03_llave":
			_p03_llave()
		"p04_placa":
			_p04_placa(int(datos[0]) != 0)
		"p05_estado":
			_luces = datos.duplicate()
			_luces_refrescar()
			Audio.play3d("gen/interruptor/clic", _cuadro_pos(1), 0.0, 0.05, 20.0, Audio.PRI_MID)
		"p07_giro":
			_valvula_giro(int(datos[0]), int(datos[1]))
		"p07_mal":
			_valvula_mal()
		"p09_rot":
			_tubos_rot = datos.duplicate()
			_tubos_refrescar()
			Audio.play3d("gen/interruptor/clic", _tubo_pos(4), -2.0, 0.08, 20.0, Audio.PRI_MID)
		"p11_mecha":
			_p11_mecha()
		"p12_aislador":
			_p12_aislador(int(datos[0]))
		"p13_k":
			_p13_k(int(datos[0]), float(datos[1]), int(datos[2]) != 0 if datos.size() > 2 else true)
		"p13_llega":
			_p13_llega()
		"p14_llave":
			_p14_coger()
		"p15":
			if not _cable_tenso:
				_tensar_cable(false)
			hecho["p15"] = true
		"p16_suben":
			_pasarelas_suben()
		"p16":
			_resolver("p16", false)
		"p17_golpe":
			_bola_golpe(int(datos[0]), false)
		"p18_diales":
			_diales = datos.duplicate()
			_diales_refrescar()
			Audio.play3d("gen/dial/clic", _dial_pos(1), -2.0, 0.05, 20.0, Audio.PRI_MID)
		"p18_llave":
			_p18_llave()
		"p19_aguja":
			_aguja_cambio(int(datos[0]))
		"p19_vagon":
			_vagon_rueda(false)
		"p20_carga":
			_p20_carga(int(datos[0]))
		"p20_arranca":
			_p20_arranca()
		"tren_listo":
			if is_instance_valid(_tren):
				Audio.play3d("gen/tren/bocina", _tren.global_position + Vector3(2, 3, 0), 8.0, 0.0, 300.0, Audio.PRI_TOP)
			_mensaje_local("¡EL TREN ESTÁ LISTO! ¡TODOS A LA PLATAFORMA!")
		_:
			if e.length() == 3 and e.begins_with("p"):
				_resolver(e, false)


# ======================================================================================================
# LA SALIDA DE CINE: el tren se va por el tunel
# ======================================================================================================
func _on_evento(e: String, datos: Array) -> void:
	super._on_evento(e, datos)
	if e == "escapan":
		_cine_final()


func _cine_final() -> void:
	if _cine_final_hecha or not is_instance_valid(_tren):
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
	for id in _obj4:
		var o: Dictionary = _obj4[id]
		if String(o["estado"]) == "lleva" and is_instance_valid(o["nodo"]):
			(o["nodo"] as Node3D).visible = false
	for r in Net.remotes.values():
		if is_instance_valid(r):
			(r as Node3D).visible = false
	for b in get_tree().get_nodes_in_group("aliados_pve"):
		if is_instance_valid(b):
			(b as Node3D).visible = false
	if hud:
		hud.visible = false
	if _capa_equipo:
		_capa_equipo.visible = false
	var c := _c("p20_gasoil")
	var cam := Camera3D.new()
	cam.fov = 52.0
	cam.far = 900.0
	add_child(cam)
	var cp := _v(_c("cine_final").get("camara", [20.0, 7.0, 132.0]))
	cam.global_position = cp
	cam.look_at(_tren.global_position + Vector3(6, 2, 0))
	cam.make_current()
	# franjas y rotulo
	var capa := CanvasLayer.new()
	capa.layer = 30
	add_child(capa)
	var alto := get_viewport().get_visible_rect().size.y * 0.11
	for arriba in [true, false]:
		var fr := ColorRect.new()
		fr.color = Color.BLACK
		fr.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if arriba else Control.PRESET_BOTTOM_WIDE)
		if arriba:
			fr.offset_bottom = alto
		else:
			fr.offset_top = -alto
		capa.add_child(fr)
	var titulo := Label.new()
	titulo.text = "EPISODIO 4 COMPLETADO"
	titulo.add_theme_font_size_override("font_size", 58)
	titulo.add_theme_color_override("font_color", Color(1.0, 0.8, 0.5))
	titulo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	titulo.add_theme_constant_override("shadow_offset_y", 3)
	titulo.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.grow_horizontal = Control.GROW_DIRECTION_BOTH
	titulo.modulate.a = 0.0
	capa.add_child(titulo)
	var sub := Label.new()
	sub.text = "…y el último tren se pierde en la montaña"
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
	# EL TREN ARRANCA: bocina, humo, y se va acelerando hacia el tunel del oeste
	Audio.play3d("gen/tren/bocina", _tren.global_position + Vector3(2, 3, 0), 10.0, 0.0, 400.0, Audio.PRI_TOP)
	if is_instance_valid(_tren_humo):
		_tren_humo.amount = 50
		_tren_humo.emitting = true
	var marcha := _bucle_directo("res://sounds/gen/tren/marcha1.ogg", _tren, Vector3(6, 1, 0), 4.0, 200.0)
	var x0 := _tren.global_position.x
	var tunel: Array = c.get("tunel", [0, 138, 3, 146])
	var x_fin := float(tunel[0]) - 40.0
	var tw := create_tween()
	tw.tween_interval(1.5)
	tw.tween_property(_tren, "global_position:x", x_fin, 11.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var seguir := func(_k: float) -> void:
		if is_instance_valid(cam) and is_instance_valid(_tren):
			var mira := _tren.global_position + Vector3(8, 2, 0)
			mira.x = maxf(mira.x, float(tunel[2]) + 2.0)
			cam.look_at(mira, Vector3.UP)
	tw.parallel().tween_method(seguir, 0.0, 1.0, 11.0)
	tw.parallel().tween_property(cam, "global_position", cp + Vector3(-8.0, 1.5, 3.0), 11.0).set_trans(Tween.TRANS_SINE)
	var tt := create_tween()
	tt.tween_interval(7.0)
	tt.tween_property(titulo, "modulate:a", 1.0, 1.4)
	tt.parallel().tween_property(sub, "modulate:a", 1.0, 2.0)
	tt.tween_interval(4.0)
	tt.tween_property(negro, "color:a", 1.0, 1.6)
	tt.tween_callback(func():
		if is_instance_valid(marcha):
			marcha.queue_free()
		_cine_final_hecha = true
		_cine_final_corriendo = false)
	print("[campana4] el tren sale desde x %.1f" % x0)


