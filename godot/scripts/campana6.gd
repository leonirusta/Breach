extends "res://scripts/campana_kit.gd"
## EPISODIO 6 DE LA CAMPAÑA: "LA CUMBRE" (campana_cumbre, tools/generar_mapa_campana6.py). 2026-09-30.
##
## El avion del episodio 5 pierde un motor sobre la sierra y aterriza de PANZA en un lago helado (escena de entrada:
## baja ardiendo, toca el hielo, patina y se parte). De dia y NEVANDO. Hay que subir a la cumbre, donde el teleferico
## de la estacion de esqui baja al otro lado. DOCE PUZZLES, ninguno repetido de los episodios anteriores:
##    1 EL HIELO FINO        las placas oscuras se rompen si os quedais encima; las blancas aguantan. Agua helada.
##    2 EL TANK EN EL LAGO   a tiros cuesta muchisimo: hay que llevarlo al hielo fino, que no aguanta su peso
##    3 EL GRISU             en la mina NO SE PUEDE DISPARAR (revienta). Extractor, puerta, y desde fuera, la bombona:
##                           la mina vuela con la horda dentro y se hunde (se rellena de escombro)
##    4 LA QUITANIEVES       escoltarla carretera arriba; su pala abre los ventisqueros. Sin escolta o rodeada, se para
##    5 EL ROBOT TEDAX       se conduce por un hueco del derrumbe viendo por su camara (en la pantalla de la furgoneta)
##                           y se detona la carga
##    6 LA AVALANCHA         tres GAZEX en la cornisa de nieve: a tiros. La cornisa cae y RELLENA el barranco
##    7 LA VENTISCA          no se ve nada y el frio mata: braseros, grietas con puentes de nieve falsos, la campana
##    8 LAS CAMPANAS         la espadaña toca una melodia; se repite disparando a las campanas en orden (3 rondas)
##    9 LOS LASERES          el pasillo del laboratorio: saltar, agacharse y esperar el hueco. El primero los apaga
##   10 LOS ESPEJOS          el laser de estrella guia, con cuatro espejos giratorios, hasta el receptor de la verja
##   11 EL SOPLETE           se lleva en la mano y derrite el muro de hielo y los frenos de la rueda del teleferico
##   12 EL TELEFERICO        la cabina tarda un minuto en subir (aguantad, con un Tank), todos dentro y abajo
##
## Escenas de camara: el aterrizaje de panza, el Tank que se hunde, la mina que revienta, la voladura del derrumbe,
## la avalancha, la verja que abre el laser y la salida en la cabina con la estacion volando. Lo que se AÑADE al mundo
## (el relleno de la avalancha, el escombro de la mina) va por `place_settled`, igual en todas las maquinas.

const COLOR_AVISO := Color(1.0, 0.75, 0.1)
const COLOR_INFO := Color(0.35, 0.8, 1.0)
const COLOR_PELIGRO := Color(1.0, 0.3, 0.1)
const G6 := 3.0
const M6 := 9.0
const ROTULOS := {"hielo": "p01", "grisu": "p03", "extractor": "p03", "bombona": "p03", "quitanieves": "p04",
	"robot": "p05", "gazex": "p06", "braseros": "p07", "campanas": "p08", "cuerda": "p08", "laseres": "p09",
	"panel": "p09", "espejos": "p10", "emisor": "p10", "soplete": "p11", "hielo_sala": "p11", "teleferico": "p12"}
## los bidones de gasoil que revientan a tiros (repartidos por todo el mapa: para las hordas)
const BIDONES := [[132.0, 3.0, 150.0], [158.0, 3.0, 134.0], [170.0, 3.0, 110.5], [150.0, 3.0, 82.5], [176.0, 3.0, 80.5],
	[186.2, 4.3, 50.0], [186.2, 6.0, 8.0], [100.0, 9.0, 6.0], [70.0, 9.0, 52.0], [58.5, 9.0, 64.0], [50.0, 9.0, 39.0],
	[36.0, 9.0, 8.0]]

var _comprobar_t6 := 0.0
var _matid: Dictionary = {}
var _bidones_vivos: Array = []
# la entrada
var _avion6: Node3D = null
var _avion_t := -1.0
var _avion_humo: CPUParticles3D = null
# 1 el hielo
var _rotas: Dictionary = {}              ## "c,f" -> true
var _grietas: Dictionary = {}            ## "c,f" -> MeshInstance3D
var _pisado: Dictionary = {}             ## "c,f" -> s que ha pasado MI jugador encima
var _pedida: Dictionary = {}             ## "c,f" -> true (ya he pedido romperla)
var _criat_hielo: Dictionary = {}        ## (anfitrion) id de criatura -> [placa, s]
var _hielo_host_t := 0.0
var _gruesas: Dictionary = {}
# 2 el tank
var _tank6: Node = null
var _tank_hundido := false
# 3 el grisu
var _grisu := 0                          ## 0 lleno, 1 extractor arrancando, 2 puerta abierta, 3 ya ha reventado
var _vent_t := -1.0
var _puerta_abierta := false
var _aspas: Node3D = null
var _vent_ruido: AudioStreamPlayer3D = null
var _puerta_mina: StaticBody3D = null
var _puerta_mina_barrera := AABB()
var _mun_arma := -1
var _mun_cargador := -1
var _chispa_t := 0.0
# 4 la quitanieves
var _qn: AnimatableBody3D = null
var _qn_s := 0.0
var _qn_s_vista := 0.0
var _qn_estado := 0                      ## 0 aparcada, 1 en marcha, 2 sin escolta, 3 rodeada, 4 derrumbe, 5 barranco
var _qn_largo := 0.0
var _qn_pala_t := 0.0
var _qn_red_t := 0.0
var _qn_motor: AudioStreamPlayer3D = null
var _qn_giro: Node3D = null
var _qn_tanda_t := 0.0
var _qn_pisa_t := 0.0
# 5 el robot
var _robot: Node3D = null
var _robot_celda := Vector2(158.5, 13.5)
var _robot_dir := 0                      ## 0 -x, 1 -z, 2 +x, 3 +z
var _robot_carga := false
var _robot_vp: SubViewport = null
var _robot_cam: Camera3D = null
var _pantalla_robot: MeshInstance3D = null
# 6 la avalancha
var _gazex: Array = [false, false, false]
var _gazex_pos: Array = [Vector3(111.5, 21.4, 7.2), Vector3(118.0, 22.0, 8.6), Vector3(124.5, 21.4, 7.2)]
var _gazex_nodos: Array = []
var _cornisa_llena := 0
var _cornisa_t := 0.0
# 7 la ventisca
var _frio := 100.0
var _braseros: Array = [true, false, false, false]
var _brasero_fx: Array = [null, null, null, null]
var _vent_k := 0.0                       ## 0..1: cuanto de ventisca hay alrededor de MI jugador
var _viento: AudioStreamPlayer = null
var _campana_t := 0.0
var _caida_t := 0.0
var _falso_t := 0.0
var _falso_k := ""
var _falsos_rotos: Dictionary = {}
var _niebla_base := -1.0
var _frio_dano_t := 0.0
# 8 las campanas
var _campanas6: Array = []
var _campana_luz: Array = []
var _toque := 0
var _toque_i := 0
var _tocando := false
var _campana_ultimo: Array = [0.0, 0.0, 0.0, 0.0]
var _porton6: Array = []
var _porton_barrera := AABB()
# 9 los laseres
var _laseres: Array = []                 ## [{tipo, x, mallas: [MeshInstance3D]}]
var _laseres_on := true
var _alarma_cd := 0.0
var _laser_ruido: AudioStreamPlayer3D = null
# 10 los espejos
var _espejos: Array = []
var _espejo_nodos: Array = []
var _haz_on := false
var _haz_mallas: Array = []
var _haz_puntos: Array = []
var _haz_llega := false
var _receptor_luz: MeshInstance3D = null
var _verja6: StaticBody3D = null
var _verja6_barrera := AABB()
var _haz_dano_t := 0.0
# 11 el soplete
var _llama_t := 0.0
var _hielo_libre: Array = [false, false, false, false]   ## el muro y los tres frenos
var _hielo_t := 0.0
var _soplete_ruido: AudioStreamPlayer3D = null
# 12 el teleferico
var _cabina: AnimatableBody3D = null
var _cabina_t := -1.0
var _tanda_final6 := 0.0
var _final_tank6 := false
var _barrera_cable: StaticBody3D = null
var _rueda: Node3D = null
var _rueda_gira := false
var _cables_fuera: Array = []
# LOS MANDOS (mandos.gd): lo que se usa con el boton, de verdad y con su piloto (ambar latiendo: se puede usar;
# verde: hecho; apagado: aun no). Sin carteles: se encuentran mirando el sitio.
var _mnd_extractor: Node3D = null
var _mnd_p05: Dictionary = {}         ## "p05_izq" / "p05_avanza" / "p05_der" / "p05_detonar" -> su mando en la consola
var _mnd_laseres: Node3D = null
var _baliza_laseres: MeshInstance3D = null
var _mnd_emisor: Node3D = null
var _mnd_teleferico: Node3D = null
var _cuerda_p08: Node3D = null           ## la cuerda de la espadaña (da un tiron al tocar)
var _cuerda_p08_dir := Vector3.DOWN
var _cuerda_p08_mano := Vector3.ZERO     ## el centro de la agarradera (donde sale el boton)
# la barra del hud (frio, grisu, extractor...)
var _barra_capa: CanvasLayer = null
var _barra_llena: ColorRect = null
var _barra_texto: Label = null


# ======================================================================================================
# LA ESCENA
# ======================================================================================================
func _montar_escena() -> void:
	super._montar_escena()
	rotulo_fase = ROTULOS
	_arreglar_puertas_refugio()
	_muros_invisibles()
	_matid = cfg.get("mat", {})
	for g in _c("p01_hielo").get("gruesas", []):
		_gruesas["%d,%d" % [int(g[0]), int(g[1])]] = true
	if _soy_host:
		_sortear()
	_montar_avion6()
	_montar_bidones()
	_montar_p01()
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


func _fase_de_rotulos() -> String:
	match fase:
		"inicio", "p02":
			return "p01"
		"p04b":
			return "p04"
		"camino_refugio", "refugio":
			return "p09"
		"subir":
			return "p12"
	return fase


## Lo que sortea el anfitrion: las tres melodias de la espadaña (sin repetir campana seguida)
func _sortear() -> void:
	var melodias: Array = []
	for n in _c("p08_campanas").get("rondas", [3, 4, 5]):
		var m: Array = []
		var antes := -1
		for i in int(n):
			var k := randi_range(0, 3)
			while k == antes:
				k = randi_range(0, 3)
			m.append(k)
			antes = k
		melodias.append(m)
	par = {"melodias": melodias}
	print("[campana6] sorteo: melodias %s" % str(melodias))


func _estado_dict() -> Dictionary:
	return {"hecho": hecho, "par": par, "fase": fase, "rotas": _rotas.keys(), "grisu": _grisu, "qn": [_qn_s, _qn_estado],
		"robot": [_robot_celda.x, _robot_celda.y, _robot_dir, _robot_carga], "puerta": _puerta_abierta,
		"vent": _vent_t, "gazex": _gazex, "braseros": _braseros,
		"falsos": _falsos_rotos.keys(), "toque": _toque, "laseres": _laseres_on, "espejos": _espejos, "haz": _haz_on,
		"hielo": _hielo_libre, "cabina": _cabina_t}


func _aplicar_estado(txt: String) -> void:
	var d = JSON.parse_string(txt)
	if not (d is Dictionary) or _soy_host:
		return
	par = d.get("par", par)
	fase = String(d.get("fase", fase))
	for k in d.get("rotas", []):
		var cf := String(k).split(",")
		if cf.size() == 2:
			_romper_placa(int(cf[0]), int(cf[1]), true)
	_grisu = int(d.get("grisu", 0))
	_vent_t = float(d.get("vent", -1.0))
	if bool(d.get("puerta", false)):
		_p03_puerta()
	var q: Array = d.get("qn", [0.0, 0])
	_qn_s = float(q[0])
	_qn_s_vista = _qn_s
	_qn_estado = int(q[1])
	var r: Array = d.get("robot", [158.5, 13.5, 0, false])
	_robot_celda = Vector2(float(r[0]), float(r[1]))
	_robot_dir = int(r[2])
	_robot_carga = bool(r[3])
	_robot_colocar(true)
	var gz: Array = d.get("gazex", [false, false, false])
	for i in gz.size():
		if bool(gz[i]) and not bool(_gazex[i]):
			_gazex_revienta(i, true)
	var br: Array = d.get("braseros", _braseros)
	for i in br.size():
		if bool(br[i]):
			_encender_brasero(i, true)
	for k in d.get("falsos", []):
		var ij := String(k).split(",")
		if ij.size() == 2:
			_romper_falso(int(ij[0]), int(ij[1]), true)
	_toque = int(d.get("toque", 0))
	var es: Array = d.get("espejos", _espejos)
	for i in mini(es.size(), _espejos.size()):
		_espejos[i] = int(es[i])
		_espejo_refrescar(i, true)
	_haz_on = bool(d.get("haz", false))
	var hl: Array = d.get("hielo", _hielo_libre)
	for i in hl.size():
		_hielo_libre[i] = bool(hl[i])
	var hh: Dictionary = d.get("hecho", {})
	for k in hh:
		if bool(hh[k]) and not _h(String(k)):
			_resolver6(String(k), true)
	if not bool(d.get("laseres", true)):
		_laseres_apagar(true)
	_haz_calcular()


func _resolver6(k: String, ya: bool) -> void:
	if _h(k):
		return
	hecho[k] = true
	match k:
		"p02": _p02_resuelto(ya)
		"p03": _p03_resuelto(ya)
		"p05": _p05_resuelto(ya)
		"p06": _p06_resuelto(ya)
		"p08": _p08_resuelto(ya)
		"p09": _laseres_apagar(ya)
		"p10": _p10_resuelto(ya)
		"p11": _p11_resuelto(ya)
	if not ya:
		Audio.ui("objetivo_tomado", -4.0)


# ======================================================================================================
# UTILIDADES DEL EPISODIO
# ======================================================================================================
## La altura del firme de la carretera (la misma formula que el generador)
func _camino_y(x: float, z: float) -> float:
	var yc := float(_c("p04_quitanieves").get("curva_y", 6.0))
	if z >= 76.0:
		return G6
	if x >= 178.0:
		if z >= 16.0:
			return G6 + (76.0 - z) / 60.0 * (yc - G6)
		return yc
	if x >= 128.0:
		return yc + (178.0 - x) / 50.0 * (M6 - yc)
	return M6


## Pone voxels (solo en el aire) de un material de la paleta del mapa. Cada maquina lo hace igual.
func _rellenar(mn: Vector3, mx: Vector3, mat_id: int) -> void:
	if world == null or mat_id <= 0:
		return
	var vs: float = float(world.get_voxel_size())
	var o := Vector3i(floori(mn.x / vs), floori(mn.y / vs), floori(mn.z / vs))
	var f := Vector3i(ceili(mx.x / vs), ceili(mx.y / vs), ceili(mx.z / vs))
	var tam := f - o
	if tam.x <= 0 or tam.y <= 0 or tam.z <= 0:
		return
	var mats := PackedByteArray()
	mats.resize(tam.x * tam.y * tam.z)
	mats.fill(mat_id)
	world.place_settled(o, tam, mats)


## Si MI jugador esta dentro de la caja, lo saca a `fuera` (antes de rellenar de escombro o de nieve)
func _sacar_de(mn: Vector3, mx: Vector3, fuera: Vector3) -> void:
	if not is_instance_valid(jugador):
		return
	var p: Vector3 = jugador.global_position
	if p.x > mn.x and p.x < mx.x and p.y > mn.y - 1.0 and p.y < mx.y and p.z > mn.z and p.z < mx.z:
		jugador.global_position = fuera
		jugador.velocity = Vector3.ZERO


## La barra de abajo (frio, grisu, la quitanieves...). `v` de 0 a 1; titulo vacio: se esconde
var _en_foto := -1


func _barra(titulo: String, v: float, color: Color) -> void:
	if _en_foto < 0:
		_en_foto = 0
		for a in OS.get_cmdline_user_args():
			if String(a).begins_with("--campanafoto"):
				_en_foto = 1
	if titulo == "" or _en_foto == 1:
		if _barra_capa:
			_barra_capa.visible = false
		return
	if _barra_capa == null:
		_barra_capa = CanvasLayer.new()
		_barra_capa.layer = 5
		add_child(_barra_capa)
		var fondo := ColorRect.new()
		fondo.color = Color(0, 0, 0, 0.5)
		fondo.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		fondo.offset_left = -170
		fondo.offset_right = 170
		fondo.offset_top = 96
		fondo.offset_bottom = 114
		_barra_capa.add_child(fondo)
		_barra_llena = ColorRect.new()
		_barra_llena.position = Vector2(3, 3)
		_barra_llena.size = Vector2(334, 12)
		fondo.add_child(_barra_llena)
		_barra_texto = Label.new()
		_barra_texto.position = Vector2(0, -24)
		_barra_texto.add_theme_font_size_override("font_size", 15)
		_barra_texto.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		fondo.add_child(_barra_texto)
	_barra_capa.visible = true
	_barra_llena.size.x = 334.0 * clampf(v, 0.0, 1.0)
	_barra_llena.color = color
	_barra_texto.text = titulo


func _placa_key(c: int, f: int) -> String:
	return "%d,%d" % [c, f]


func _rompe_local(pos: Vector3, fuerza: float) -> void:
	var fx = jugador.get("effects") if is_instance_valid(jugador) else null
	if fx and fx.has_method("dust"):
		fx.dust(pos, fuerza)


# ======================================================================================================
# LA ENTRADA: el avion baja ardiendo, toca el hielo, patina y se parte (la cinematica de siempre mira)
# ======================================================================================================
func _modelo_avion6() -> Node3D:
	var n := Node3D.new()
	var oliva := _mm(Color(0.34, 0.37, 0.26), 0.3, 0.6)
	var oscuro := _mm(Color(0.2, 0.22, 0.16), 0.4, 0.6)
	var cristal := _mm(Color(0.1, 0.12, 0.14), 0.8, 0.2)
	# el fuselaje a lo largo de -X (hacia donde vuela)
	_cil_mesh(n, 2.2, 30.0, Vector3(0, 2.2, 0), oliva, Vector3(0, 0, PI / 2), 18)
	_esfera_mesh(n, 2.2, Vector3(-15.0, 2.2, 0), oliva)
	_caja_mesh(n, Vector3(1.6, 0.7, 2.6), Vector3(-15.2, 3.2, 0), cristal)
	_cil_mesh(n, 1.2, 5.0, Vector3(16.5, 3.0, 0), oliva, Vector3(0, 0, PI / 2 + 0.25), 14)
	_caja_mesh(n, Vector3(4.0, 5.2, 0.35), Vector3(16.0, 6.2, 0), oliva)
	_caja_mesh(n, Vector3(3.4, 0.3, 11.0), Vector3(16.0, 3.6, 0), oliva)
	_caja_mesh(n, Vector3(5.0, 0.45, 38.0), Vector3(-1.0, 4.0, 0), oliva)
	for z in [-12.0, -6.5, 6.5, 12.0]:
		_cil_mesh(n, 0.8, 4.2, Vector3(-3.0, 3.2, z), oscuro, Vector3(0, 0, PI / 2), 12)
		var h := Node3D.new()
		h.name = "Helice"
		n.add_child(h)
		h.position = Vector3(-5.2, 3.2, z)
		_caja_mesh(h, Vector3(0.1, 4.0, 0.3), Vector3.ZERO, oscuro)
		_caja_mesh(h, Vector3(0.1, 0.3, 4.0), Vector3.ZERO, oscuro)
	return n


func _montar_avion6() -> void:
	_avion6 = _modelo_avion6()
	_avion6.name = "AvionAterriza"
	add_child(_avion6)
	# EL MOTOR QUE ARDE: fuego y una columna de humo negro que se ve desde toda la montaña
	var fuego := _particulas(_avion6, Vector3(-3.0, 3.4, -12.0), 30, 0.8, Color(1.0, 0.8, 0.3, 0.95), Color(0.7, 0.12, 0.0), 1.3, true)
	fuego.direction = Vector3(1, 0.4, 0)
	fuego.initial_velocity_min = 2.0
	fuego.initial_velocity_max = 5.0
	fuego.local_coords = false
	_avion_humo = _particulas(_avion6, Vector3(-2.0, 3.6, -12.0), 40, 5.0, Color(0.1, 0.1, 0.1, 0.8), Color(0.3, 0.3, 0.3), 3.0, false)
	_avion_humo.direction = Vector3(1, 0.3, 0)
	_avion_humo.initial_velocity_min = 1.0
	_avion_humo.initial_velocity_max = 3.0
	_avion_humo.local_coords = false
	var hay_cine: bool = DisplayServer.get_name() != "headless" and not ("--sinintro" in OS.get_cmdline_user_args())
	for a in OS.get_cmdline_user_args():
		if String(a).ends_with("test") or String(a).begins_with("--campanafoto") or String(a).begins_with("--ir="):
			hay_cine = false
	if hay_cine:
		_avion_t = 0.0
		_avion_colocar(0.0)
	else:
		_avion_restos()


## Donde esta el avion en el segundo t de la entrada
func _avion_colocar(t: float) -> void:
	if not is_instance_valid(_avion6):
		return
	var az := float(_c("avion").get("z", 142.0))
	var toca := 3.0
	var p: Vector3
	var cabeceo := 0.0
	var alabeo := 0.0
	if t < toca:
		var u := t / toca
		p = Vector3(lerpf(236.0, 104.0, u), lerpf(36.0, G6 + 0.1, u * (2.0 - u) * 0.5 + u * u * 0.5), az + sin(u * 3.0) * 1.5)
		cabeceo = -0.10 * (1.0 - u)
		alabeo = 0.12 * sin(u * 4.0)
	else:
		var u := clampf((t - toca) / 3.8, 0.0, 1.0)
		var e := 1.0 - (1.0 - u) * (1.0 - u)
		p = Vector3(lerpf(104.0, 38.0, e), G6 - 0.4, az + sin(u * 5.0) * 0.8)
		cabeceo = 0.04 * sin(u * 18.0) * (1.0 - u)
		alabeo = -0.06 * u
	_avion6.global_position = p
	_avion6.rotation = Vector3(alabeo, sin(t * 0.8) * 0.05, cabeceo)
	for h in _avion6.get_children():
		if h.name.begins_with("Helice"):
			(h as Node3D).rotation.x = t * 30.0


func _avion_tick(dt: float) -> void:
	if _avion_t < 0.0:
		return
	var antes := _avion_t
	_avion_t += dt
	_avion_colocar(_avion_t)
	if antes <= 0.0:
		Audio.play3d("gen/avion/pasada", Vector3(160.0, 20.0, 142.0), 10.0, 0.0, 500.0, Audio.PRI_TOP)
	if antes < 3.0 and _avion_t >= 3.0:
		var p := _avion6.global_position
		_golpe(p, 2.5, "destru/metal")
		Audio.play3d("gen/hielo/rompe", p, 8.0, 0.0, 200.0, Audio.PRI_TOP)
		var polvo := _particulas(self, p, 60, 2.4, Color(0.95, 0.97, 1.0, 0.9), Color(0.8, 0.85, 0.9), 3.0, false)
		polvo.one_shot = true
		polvo.explosiveness = 0.9
		polvo.initial_velocity_min = 4.0
		polvo.initial_velocity_max = 10.0
		polvo.spread = 70.0
		polvo.direction = Vector3.UP
		get_tree().create_timer(3.0).timeout.connect(polvo.queue_free)
	# el rastro de nieve y chispas mientras patina
	if _avion_t >= 3.0 and _avion_t < 6.8 and int(_avion_t * 10.0) != int(antes * 10.0):
		var q := _avion6.global_position + Vector3(6.0, 0.4, randf_range(-3.0, 3.0))
		var s := _particulas(self, q, 10, 1.6, Color(0.95, 0.97, 1.0, 0.8), Color(0.85, 0.9, 0.95), 1.8, false)
		s.one_shot = true
		s.explosiveness = 0.8
		s.initial_velocity_min = 2.0
		s.initial_velocity_max = 5.0
		s.direction = Vector3(1, 1, 0)
		get_tree().create_timer(2.0).timeout.connect(s.queue_free)
	if antes < 6.0 and _avion_t >= 6.0:
		# SE PARTE: fogonazo, chapa y una nube de nieve que lo tapa todo
		var p := _avion6.global_position
		var escena := get_tree().current_scene
		if escena and "effects" in escena and escena.effects and escena.effects.has_method("explosion"):
			escena.effects.explosion(p + Vector3(4.0, 2.0, 0), 3.0)
		Audio.bf3d("destru/derrumbe_grave", p, 10.0, 250.0, Audio.PRI_TOP)
		var nube := _particulas(self, p + Vector3(0, 1.5, 0), 90, 3.5, Color(0.96, 0.97, 1.0, 0.95), Color(0.85, 0.88, 0.92), 5.0, false)
		nube.one_shot = true
		nube.explosiveness = 0.85
		nube.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		nube.emission_box_extents = Vector3(12.0, 1.0, 4.0)
		nube.initial_velocity_min = 2.0
		nube.initial_velocity_max = 6.0
		nube.spread = 90.0
		get_tree().create_timer(4.0).timeout.connect(nube.queue_free)
	if _avion_t >= 7.0:
		_avion_t = -1.0
		_avion_restos()


## Ya en el suelo: el avion de la escena se va y quedan los restos del mapa (voxels) con el motor ardiendo
func _avion_restos() -> void:
	if is_instance_valid(_avion6):
		_avion6.queue_free()
	_avion6 = null
	var az := float(_c("avion").get("z", 142.0))
	var motor := Vector3(19.0, G6 + 0.6, az - 6.0)
	var fuego := _particulas(self, motor, 26, 0.9, Color(1.0, 0.8, 0.3, 0.95), Color(0.7, 0.12, 0.0), 1.2, true)
	fuego.direction = Vector3.UP
	fuego.gravity = Vector3(0, 3.0, 0)
	fuego.initial_velocity_min = 0.6
	fuego.initial_velocity_max = 1.8
	var humo := _particulas(self, motor + Vector3(0, 1.0, 0), 34, 7.0, Color(0.08, 0.08, 0.08, 0.75), Color(0.35, 0.35, 0.35), 3.2, false)
	humo.direction = Vector3.UP
	humo.gravity = Vector3(0.6, 0.8, 0)
	humo.initial_velocity_min = 1.0
	humo.initial_velocity_max = 2.2
	_luz(self, motor + Vector3(0, 1.2, 0), Color(1.0, 0.5, 0.2), 2.4, 14.0)
	_bucle_bf("bf/amb/bucle_fuego", self, motor, -2.0, 40.0)


# ======================================================================================================
# LOS BIDONES DE GASOIL (revientan a tiros: para las hordas)
# ======================================================================================================
func _montar_bidones() -> void:
	var rojo := _mm(Color(0.62, 0.1, 0.07), 0.35, 0.55)
	for i in BIDONES.size():
		var p := _v(BIDONES[i])
		var d := _diana("bidon%d" % i, p + Vector3(0, 0.45, 0), Vector3(0.6, 0.9, 0.6))
		_cil_mesh(d, 0.3, 0.9, Vector3.ZERO, rojo, Vector3.ZERO, 12)
		_cil_mesh(d, 0.31, 0.05, Vector3(0, 0.3, 0), _mm(Color(0.2, 0.2, 0.2), 0.6, 0.5), Vector3.ZERO, 12)
		_texto3d("GASOIL", Vector3(0, 0.05, 0.31), Color(1.0, 0.9, 0.3), 12, false, d)
		_bidones_vivos.append(true)


func _bidon_revienta(i: int, ya: bool) -> void:
	if i < 0 or i >= _bidones_vivos.size() or not bool(_bidones_vivos[i]):
		return
	_bidones_vivos[i] = false
	var d = _dianas.get("bidon%d" % i)
	var p := _v(BIDONES[i]) + Vector3(0, 0.5, 0)
	if is_instance_valid(d):
		d.queue_free()
	_dianas.erase("bidon%d" % i)
	_explosion(p, 3.2, 140.0, 2.4, ya)
	if not ya:
		_bola_fuego6(p, 2.4)


func _bola_fuego6(p: Vector3, tam: float) -> void:
	var b := _particulas(self, p, 40, 1.4, Color(1.0, 0.85, 0.4, 1.0), Color(0.6, 0.1, 0.0), tam, true)
	b.one_shot = true
	b.explosiveness = 0.9
	b.initial_velocity_min = 2.0
	b.initial_velocity_max = 6.0
	b.spread = 180.0
	b.gravity = Vector3(0, 4.0, 0)
	var h := _particulas(self, p + Vector3.UP, 30, 4.0, Color(0.1, 0.1, 0.1, 0.8), Color(0.3, 0.3, 0.3), tam * 1.6, false)
	h.one_shot = true
	h.explosiveness = 0.6
	h.direction = Vector3.UP
	h.initial_velocity_min = 1.5
	h.initial_velocity_max = 3.0
	get_tree().create_timer(4.5).timeout.connect(func():
		b.queue_free()
		h.queue_free())


# ======================================================================================================
# 1. EL HIELO FINO
# ======================================================================================================
func _montar_p01() -> void:
	var c := _c("p01_hielo")
	if c.is_empty():
		return
	var sp := _v(cfg.get("salida", [47, 3, 142]))
	_rotulo("hielo", "HIELO BLANCO: AGUANTA\nHIELO OSCURO: SE ROMPE", sp + Vector3(2.5, 2.4, -2.0), COLOR_AVISO)


## La placa fina que hay bajo `p` (o "" si es gruesa, rota, o no estas encima del hielo)
func _placa_fina(p: Vector3, alto: float = 0.9) -> String:
	var c := _c("p01_hielo")
	if c.is_empty():
		return ""
	var lago: Array = c["lago"]
	var pl := float(c.get("placa", 4.0))
	if p.x < float(lago[0]) or p.x >= float(lago[2]) or p.z < float(lago[1]) or p.z >= float(lago[3]):
		return ""
	if p.y < G6 - 0.25 or p.y > G6 + alto:
		return ""
	var k := _placa_key(int((p.x - float(lago[0])) / pl), int((p.z - float(lago[1])) / pl))
	if _gruesas.has(k) or _rotas.has(k):
		return ""
	return k


func _placa_centro(k: String) -> Vector3:
	var c := _c("p01_hielo")
	var lago: Array = c["lago"]
	var pl := float(c.get("placa", 4.0))
	var cf := k.split(",")
	return Vector3(float(lago[0]) + (int(cf[0]) + 0.5) * pl, G6, float(lago[1]) + (int(cf[1]) + 0.5) * pl)


## Cada maquina mira a SU jugador: cuanto lleva encima de cada placa fina (no se recupera: el hielo ya esta tocado)
func _hielo_tick(dt: float) -> void:
	if not is_instance_valid(jugador) or bool(jugador.get("spectating")):
		return
	var jp: Vector3 = jugador.global_position
	var c := _c("p01_hielo")
	if c.is_empty():
		return
	var lago: Array = c["lago"]
	# EL AGUA HELADA: dentro del lago y por debajo del hielo
	if jp.x > float(lago[0]) and jp.x < float(lago[2]) and jp.z > float(lago[1]) and jp.z < float(lago[3]) and jp.y < G6 - 0.35:
		_dano_local(10.0 * dt, Vector3.ZERO, "¡EL AGUA ESTÁ HELADA! ¡SAL DEL AGUA YA!")
	if not jugador.is_on_floor():
		return
	var k := _placa_fina(jp)
	if k == "" or _pedida.has(k):
		return
	var antes := float(_pisado.get(k, 0.0))
	var t := antes + dt
	_pisado[k] = t
	var aguanta := float(c.get("aguanta_s", 1.3))
	if antes == 0.0 or int(antes * 2.5) != int(t * 2.5):
		Audio.play3d("gen/hielo/cruje", jp, -2.0 + t * 3.0, 0.1, 25.0, Audio.PRI_MID)
	_grieta_ver(k, clampf(t / aguanta, 0.0, 1.0))
	if t >= aguanta:
		_pedida[k] = true
		var accion := "hielo:" + k
		if _en_red and not _soy_host:
			Net.net_campana_pide(accion)
		else:
			_on_pide(accion, _mi_id())


## Las grietas que se ven en la placa (cada vez mas largas)
func _grieta_ver(k: String, f: float) -> void:
	var mi: MeshInstance3D = _grietas.get(k)
	if mi == null:
		mi = MeshInstance3D.new()
		var im := ImmediateMesh.new()
		mi.mesh = im
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.05, 0.1, 0.16)
		mi.material_override = m
		add_child(mi)
		mi.global_position = _placa_centro(k) + Vector3(0, 0.03, 0)
		mi.set_meta("semilla", hash(k))
		_grietas[k] = mi
	var im2 := mi.mesh as ImmediateMesh
	im2.clear_surfaces()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(mi.get_meta("semilla"))
	im2.surface_begin(Mesh.PRIMITIVE_LINES)
	for r in 7:
		var a := rng.randf() * TAU
		var p := Vector3.ZERO
		var largo := 2.0 * f * rng.randf_range(0.6, 1.0)
		var n := 5
		for s in n:
			var q := p + Vector3(cos(a), 0, sin(a)) * largo / n
			im2.surface_add_vertex(p)
			im2.surface_add_vertex(q)
			p = q
			a += rng.randf_range(-0.6, 0.6)
	im2.surface_end()


## (el anfitrion) las criaturas que pisan hielo fino: las normales tardan, el Tank lo rompe en el acto
func _hielo_host_tick(dt: float) -> void:
	_hielo_host_t -= dt
	if _hielo_host_t > 0.0:
		return
	_hielo_host_t = 0.25
	var c := _c("p01_hielo")
	if c.is_empty():
		return
	var lago: Array = c["lago"]
	for cr in _vivos:
		if not is_instance_valid(cr) or bool(cr.get("muerta")):
			continue
		var p: Vector3 = (cr as Node3D).global_position
		# las que han caido al agua: la hipotermia (y el Tank se hunde)
		if p.x > float(lago[0]) and p.x < float(lago[2]) and p.z > float(lago[1]) and p.z < float(lago[3]) and p.y < G6 - 0.5:
			if cr == _tank6:
				if not _tank_hundido:
					_evento("p02_hunde", [p.x, p.y, p.z])
			elif cr.has_method("take_damage"):
				cr.take_damage(12.0, Vector3.ZERO)
			continue
		var k := _placa_fina(p, 2.6)          # (el origen de las grandes no esta en los pies)
		if k == "":
			_criat_hielo.erase(cr.get_instance_id())
			continue
		var reg: Array = _criat_hielo.get(cr.get_instance_id(), [k, 0.0])
		if String(reg[0]) != k:
			reg = [k, 0.0]
		reg[1] = float(reg[1]) + 0.25
		_criat_hielo[cr.get_instance_id()] = reg
		var aguanta := 0.2 if String(cr.get("tipo")) == "tanque" else 2.4
		if float(reg[1]) >= aguanta:
			var cf := k.split(",")
			_evento("p01_rompe", [int(cf[0]), int(cf[1])])


func _romper_placa(c: int, f: int, ya: bool) -> void:
	var k := _placa_key(c, f)
	if _rotas.has(k):
		return
	_rotas[k] = true
	if _grietas.has(k):
		var g = _grietas[k]
		if is_instance_valid(g):
			g.queue_free()
		_grietas.erase(k)
	var cc := _c("p01_hielo")
	var lago: Array = cc["lago"]
	var pl := float(cc.get("placa", 4.0))
	var x0 := float(lago[0]) + c * pl
	var z0 := float(lago[1]) + f * pl
	var y := float(cc.get("fino_y", 2.7)) + 0.15
	if world:
		var z := z0 + 0.15
		while z < z0 + pl - 0.1:
			world.carve_beam(Vector3(x0 + 0.2, y, z), Vector3.RIGHT, pl - 0.4, 0.22, 255, true)
			z += 0.28
	if ya:
		return
	var centro := Vector3(x0 + pl * 0.5, G6, z0 + pl * 0.5)
	Audio.play3d("gen/hielo/rompe", centro, 4.0, 0.08, 60.0, Audio.PRI_HIGH)
	var cristal := _particulas(self, centro + Vector3(0, 0.2, 0), 50, 1.4, Color(0.8, 0.92, 1.0, 0.95), Color(0.5, 0.7, 0.9), 0.35, false)
	cristal.one_shot = true
	cristal.explosiveness = 0.95
	cristal.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	cristal.emission_box_extents = Vector3(pl * 0.4, 0.1, pl * 0.4)
	cristal.initial_velocity_min = 1.5
	cristal.initial_velocity_max = 4.0
	cristal.direction = Vector3.UP
	cristal.gravity = Vector3(0, -9.8, 0)
	var agua := _particulas(self, centro, 30, 1.0, Color(0.6, 0.75, 0.9, 0.8), Color(0.4, 0.55, 0.7), 0.5, false)
	agua.one_shot = true
	agua.explosiveness = 0.9
	agua.initial_velocity_min = 2.0
	agua.initial_velocity_max = 5.0
	agua.direction = Vector3.UP
	agua.gravity = Vector3(0, -9.8, 0)
	get_tree().create_timer(2.0).timeout.connect(func():
		cristal.queue_free()
		agua.queue_free())
	if is_instance_valid(jugador) and jugador.global_position.distance_to(centro) < 6.0 and jugador.has_method("add_shake"):
		jugador.add_shake(0.25)


# ======================================================================================================
# 2. EL TANK EN EL LAGO
# ======================================================================================================
func _p02_sale_tank() -> void:
	var p := _v(_c("p02_tank").get("salida", [182, 3, 140]))
	var n0 := contenedor.get_child_count() if contenedor else 0
	_sacar("tanque", p)
	if contenedor and contenedor.get_child_count() > n0:
		_tank6 = contenedor.get_child(contenedor.get_child_count() - 1)
	_evento("p02_rugido", [p.x, p.y, p.z])


func _p02_hunde(p: Vector3) -> void:
	_tank_hundido = true
	Audio.play3d("gen/hielo/rompe", p, 10.0, 0.0, 120.0, Audio.PRI_TOP)
	var agua := _particulas(self, p + Vector3(0, 0.5, 0), 70, 1.6, Color(0.7, 0.82, 0.95, 0.9), Color(0.4, 0.55, 0.7), 0.8, false)
	agua.one_shot = true
	agua.explosiveness = 0.9
	agua.initial_velocity_min = 3.0
	agua.initial_velocity_max = 8.0
	agua.direction = Vector3.UP
	agua.gravity = Vector3(0, -9.8, 0)
	get_tree().create_timer(3.0).timeout.connect(agua.queue_free)
	_corte([[p + Vector3(9.0, 4.0, 7.0), p + Vector3(0, 0.5, 0), 0.0], [p + Vector3(7.0, 2.5, 5.0), p + Vector3(0, -1.5, 0), 3.2]], 3.4, "")
	if _soy_host:
		get_tree().create_timer(2.5).timeout.connect(func():
			if is_instance_valid(_tank6) and _tank6.has_method("take_damage"):
				_tank6.take_damage(99999.0, Vector3.ZERO)
			_evento("p02", []))


func _p02_resuelto(ya: bool) -> void:
	if ya:
		return
	_mensaje_local("¡EL TANK SE HA IDO AL FONDO!" if _tank_hundido else "¡EL TANK HA CAÍDO!")


# ======================================================================================================
# 3. EL GRISU
# ======================================================================================================
func _montar_p03() -> void:
	var c := _c("p03_grisu")
	if c.is_empty():
		return
	# la puerta de ventilacion (chapa gorda, se abre cuando el extractor tira)
	var pu: Array = c["puerta"]
	_puerta_mina = _estatico("PuertaMina", _centro(pu))
	var tam := _mx(pu) - _mn(pu)
	_caja_mesh(_puerta_mina, tam, Vector3.ZERO, _mm(Color(0.42, 0.4, 0.36), 0.6, 0.5))
	_caja_mesh(_puerta_mina, Vector3(tam.x * 0.9, 0.3, tam.z + 0.04), Vector3(0, 0.6, 0), _mm(Color(0.8, 0.62, 0.1), 0.4, 0.6))
	_colision_caja(_puerta_mina, tam, Vector3.ZERO)
	_puerta_mina_barrera = AABB(_mn(pu) - Vector3(0.2, 0.5, 0.5), tam + Vector3(0.4, 1.0, 1.0))
	CriaturaScript.barreras.append(_puerta_mina_barrera)
	# el EXTRACTOR: un aro y cuatro aspas
	var v := _v(c["ventilador"])
	var aro := Node3D.new()
	add_child(aro)
	aro.global_position = v
	var gris := _mm(Color(0.3, 0.32, 0.34), 0.6, 0.45)
	_cil_mesh(aro, 1.5, 0.5, Vector3.ZERO, gris, Vector3(0, 0, PI / 2), 20)
	_aspas = Node3D.new()
	aro.add_child(_aspas)
	_aspas.position = Vector3(0.35, 0, 0)
	for i in 4:
		var a := _caja_mesh(_aspas, Vector3(0.08, 1.3, 0.35), Vector3(0, 0.62, 0), _mm(Color(0.7, 0.62, 0.2), 0.5, 0.5))
		a.position = Vector3(0, 0.62 * cos(i * PI / 2), 0.62 * sin(i * PI / 2))
		a.rotation.x = i * PI / 2
	# el MANDO del extractor: el cuadro electrico con su interruptor grande, atornillado a la roca de la galeria (entre
	# dos marcos de entibacion: justo delante del mando habia un poste) y el tubo del cable por el techo hasta el
	# ventilador, para que se vea que es suyo. Antes era una caja verde flotando a 80 cm del suelo.
	var mando := _v(c["mando"])
	_mnd_extractor = Mandos.en_pared(world, "interruptor", self, mando + Vector3(-0.1, 1.25, -0.65), Vector3(-1, 0, 0), 1.5)
	var tubo_mat := _mm(Color(0.3, 0.31, 0.32), 0.6, 0.5)
	var sale := _mnd_extractor.transform * Vector3(0, 0.22, 0.07)
	var techo := Vector3(sale.x, G6 + 3.05, sale.z)
	_mnd_tubo(self, sale, techo, 0.022, tubo_mat)
	_mnd_tubo(self, techo, Vector3(_v(c["ventilador"]).x + 1.8, techo.y, techo.z), 0.022, tubo_mat)
	# la BOMBONA junto a la salida (la chispa buena)
	var b := _v(c["bombona"])
	var d := _diana("grisu", b + Vector3(0, 0.55, 0), Vector3(0.6, 1.1, 0.6))
	var rojo := _mm(Color(0.78, 0.12, 0.08), 0.4, 0.5)
	_cil_mesh(d, 0.28, 1.0, Vector3.ZERO, rojo, Vector3.ZERO, 14)
	_esfera_mesh(d, 0.28, Vector3(0, 0.5, 0), rojo)
	_texto3d("GAS", Vector3(0, 0.1, 0.29), Color(1, 1, 1), 16, false, d)
	var boca := Vector3(152.0, G6, 104.6)
	_rotulo("grisu", "¡GRISÚ!\nPROHIBIDO DISPARAR EN LA MINA", boca + Vector3(0, 4.6, 0.6), COLOR_PELIGRO)
	_rotulo("extractor", "EXTRACTOR", mando + Vector3(0, 2.2, 0), COLOR_INFO)
	_rotulo("bombona", "DESDE FUERA:\nDISPARAD A LA BOMBONA", b + Vector3(0, 2.0, -3.2), COLOR_AVISO)


func _en_grisu(p: Vector3) -> bool:
	var k: Array = _c("p03_grisu").get("caja", [])
	if k.is_empty():
		return false
	return p.x > float(k[0]) and p.x < float(k[3]) and p.y > float(k[1]) and p.y < float(k[4]) and p.z > float(k[2]) and p.z < float(k[5])


## Cada maquina mira si SU jugador ha disparado dentro de la mina con el gas lleno
func _grisu_tick(dt: float) -> void:
	_chispa_t -= dt
	if not is_instance_valid(jugador) or bool(jugador.get("spectating")):
		return
	var dentro := _en_grisu(jugador.global_position)
	var arma := int(jugador.get("current"))
	var municion = jugador.get("ammo")
	var cargador := -1
	if municion is Array and arma >= 0 and arma < (municion as Array).size():
		cargador = int(municion[arma])
	var disparo := arma == _mun_arma and cargador >= 0 and cargador < _mun_cargador
	_mun_arma = arma
	_mun_cargador = cargador
	if dentro and _grisu < 3 and not _h("p03"):
		var lleno := 1.0 if _grisu < 2 else 0.55
		_barra_quiero("GRISÚ · NO DISPARÉIS" if _grisu < 2 else "GRISÚ", lleno, Color(0.85, 0.75, 0.2, 0.95))
		if disparo and _chispa_t <= 0.0:
			_chispa_t = 3.0
			var accion := "grisu_chispa"
			if _en_red and not _soy_host:
				Net.net_campana_pide(accion)
			else:
				_on_pide(accion, _mi_id())
	elif _vent_t >= 0.0 and not _puerta_abierta and jugador.global_position.distance_to(_v(_c("p03_grisu")["mando"])) < 30.0:
		var s := float(_c("p03_grisu").get("arranque_s", 12.0))
		_barra_quiero("EL EXTRACTOR ARRANCA", _vent_t / s, Color(0.4, 0.8, 1.0, 0.95))


func _ventilador_tick(dt: float) -> void:
	if (_vent_t < 0.0 and not _puerta_abierta) or not is_instance_valid(_aspas):
		return
	var s := float(_c("p03_grisu").get("arranque_s", 12.0))
	if _vent_t >= 0.0 and not _puerta_abierta:
		_vent_t = minf(s, _vent_t + dt)
	var vel := 14.0 * (clampf(_vent_t / s, 0.0, 1.0) if not _puerta_abierta else 1.0)
	_aspas.rotation.x += vel * dt
	if _soy_host and not _puerta_abierta and _vent_t >= s:
		_evento("p03_puerta", [])


## Una chispa dentro con el gas: revienta la mina entera (sin hundirla: el gas se va y ya no sirve)
func _grisu_revienta_dentro() -> void:
	_grisu = 3
	var c := _c("p03_grisu")
	var tramos: Array = c.get("tramos", [])
	var k := 0
	for t in tramos:
		var a := Vector3(float(t[0]), G6 + 1.6, float(t[1]))
		var b := Vector3(float(t[2]), G6 + 1.6, float(t[3]))
		var n := int(maxf(2.0, a.distance_to(b) / 4.0))
		for i in n:
			var p := a.lerp(b, (i + 0.5) / n)
			var kk := k
			get_tree().create_timer(0.12 * kk).timeout.connect(func(): _explosion(p, 2.4, 70.0, 0.0))
			k += 1
	_mensaje_local("¡UNA CHISPA! ¡EL GRISÚ HA REVENTADO!")


func _p03_ventilador() -> void:
	if _grisu == 0:
		_grisu = 1
	_vent_t = 0.0
	_mnd_accionar(_mnd_extractor)
	var c := _c("p03_grisu")
	_vent_ruido = _bucle_directo("res://sounds/gen/mina/ventilador1.ogg", self, _v(c["ventilador"]), 0.0, 40.0)
	Audio.play3d("gen/ascensor/arranque", _v(c["mando"]), 0.0, 0.0, 40.0, Audio.PRI_HIGH)
	_mensaje_local("EL EXTRACTOR ARRANCA · la puerta se abre cuando tire del todo · ¡SIN DISPARAR!")


func _p03_puerta() -> void:
	if _puerta_abierta:
		return
	_puerta_abierta = true
	if _grisu == 1:
		_grisu = 2
	if is_instance_valid(_puerta_mina):
		_sin_colision(_puerta_mina)
		var tw := _puerta_mina.create_tween()
		tw.tween_property(_puerta_mina, "global_position:y", _puerta_mina.global_position.y + 3.1, 2.5).set_trans(Tween.TRANS_SINE)
		Audio.bf3d("destru/metal", _puerta_mina.global_position, 2.0, 50.0, Audio.PRI_HIGH)
	CriaturaScript.barreras.erase(_puerta_mina_barrera)
	if _grisu == 3:
		_mensaje_local("La puerta está abierta. La mina ya no tiene gas: ¡SEGUID!")
	else:
		_mensaje_local("¡PUERTA ABIERTA! SALID… y desde fuera, DISPARAD A LA BOMBONA: la horda está dentro")


## La mina revienta de verdad: fuego en cadena de la salida a la boca, se hunde y se rellena de escombro
func _p03_resuelto(ya: bool) -> void:
	var c := _c("p03_grisu")
	_grisu = 3
	var tramos: Array = c.get("tramos", [])
	var alto := float(c.get("alto", 3.2))
	# fuera los que esten dentro (antes de meter roca donde estan)
	var ultimo: Array = tramos.back() if not tramos.is_empty() else [134, 84, 138, 92]
	_sacar_de(Vector3(float(ultimo[0]), G6, float(ultimo[1]) - 0.5), Vector3(float(ultimo[2]), G6 + alto, float(ultimo[3])), Vector3(140.0, G6 + 0.2, 80.0))
	var roca := int(_matid.get("roca_suelta", 0))
	# se hunde la ultima galeria (la de la salida) y la boca del pueblo: escombro hasta el techo
	_rellenar(Vector3(float(ultimo[0]), G6, float(ultimo[1]) + 0.9), Vector3(float(ultimo[2]), G6 + alto, float(ultimo[3])), roca)
	if not tramos.is_empty():
		var primero: Array = tramos[0]
		_rellenar(Vector3(float(primero[0]), G6, float(primero[3]) - 3.0), Vector3(float(primero[2]), G6 + alto, float(primero[3])), roca)
	if _soy_host:
		for cr in _vivos:
			if is_instance_valid(cr) and _en_grisu((cr as Node3D).global_position) and cr.has_method("take_damage"):
				cr.take_damage(99999.0, Vector3.ZERO)
		if world:
			Net.net_explode(world, Vector3(136.0, G6 + 4.2, 84.6), 2.6, 255)
	if ya:
		return
	var cam := _v(c.get("camara", [140, 10, 70]))
	var salida := Vector3(136.0, G6 + 1.6, 84.0)
	_corte([[cam, salida, 0.0], [cam + Vector3(-3.0, -2.0, 3.0), salida + Vector3(0, 2.0, 0), 5.5]], 5.8, "")
	var k := 0
	for ti in range(tramos.size() - 1, -1, -1):
		var t: Array = tramos[ti]
		var a := Vector3(float(t[0]) + 2.0, G6 + 1.6, float(t[1]) + 2.0)
		var b := Vector3(float(t[2]) - 2.0, G6 + 1.6, float(t[3]) - 2.0)
		for i in 3:
			var p := a.lerp(b, i / 2.0)
			var kk := k
			get_tree().create_timer(0.2 + 0.18 * kk).timeout.connect(func():
				_explosion(p, 2.8, 90.0, 0.0)
				_bola_fuego6(p, 2.0))
			k += 1
	# la llamarada que sale por la puerta y la montaña que se viene abajo encima
	get_tree().create_timer(0.4).timeout.connect(func():
		_bola_fuego6(salida + Vector3(0, 0, -2.0), 4.0)
		_golpe(salida, 3.0, "destru/derrumbe_grave"))
	get_tree().create_timer(2.0).timeout.connect(func():
		_golpe(salida + Vector3(0, 3.0, 0), 3.0, "destru/derrumbe")
		_rompe_local(salida + Vector3(0, 1.0, -3.0), 3.0))
	get_tree().create_timer(1.2).timeout.connect(func():
		_bola_fuego6(Vector3(152.0, G6 + 1.6, 105.0), 4.0))
	_mensaje_local("¡LA MINA HA VOLADO CON LA HORDA DENTRO!")


# ======================================================================================================
# 4. LA QUITANIEVES (escolta)
# ======================================================================================================
func _montar_p04() -> void:
	var c := _c("p04_quitanieves")
	if c.is_empty():
		return
	var r: Array = c["ruta"]
	_qn_largo = 0.0
	for i in range(1, r.size()):
		_qn_largo += Vector2(float(r[i][0]) - float(r[i - 1][0]), float(r[i][1]) - float(r[i - 1][1])).length()
	_qn = _animable("Quitanieves", Vector3.ZERO)
	var amarillo := _mm(Color(0.9, 0.62, 0.08), 0.35, 0.5)
	var negro := _mm(Color(0.08, 0.08, 0.08), 0.5, 0.6)
	var cristal := _mm(Color(0.15, 0.2, 0.24), 0.8, 0.15)
	var acero := _mm(Color(0.55, 0.56, 0.58), 0.8, 0.35)
	# hacia -Z: la pala delante, la cabina detras
	_caja_mesh(_qn, Vector3(2.6, 0.9, 6.2), Vector3(0, 1.1, 0.2), amarillo)
	_caja_mesh(_qn, Vector3(2.4, 1.1, 2.0), Vector3(0, 2.0, -1.6), amarillo)
	_caja_mesh(_qn, Vector3(2.5, 1.9, 2.2), Vector3(0, 2.5, 1.4), amarillo)
	_caja_mesh(_qn, Vector3(2.52, 0.8, 1.6), Vector3(0, 2.9, 1.1), cristal)
	_caja_mesh(_qn, Vector3(2.6, 0.12, 2.3), Vector3(0, 3.5, 1.4), negro)
	for s in [-1.0, 1.0]:
		for z in [-1.9, 2.0]:
			_cil_mesh(_qn, 0.72, 0.5, Vector3(s * 1.3, 0.72, z), negro, Vector3(0, 0, PI / 2), 14)
	var pala := Node3D.new()
	_qn.add_child(pala)
	pala.position = Vector3(0, 0.7, -3.7)
	for s in [-1.0, 1.0]:
		var m := _caja_mesh(pala, Vector3(2.0, 1.2, 0.12), Vector3(s * 0.9, 0, 0.35), acero)
		m.rotation.y = s * 0.42
	_caja_mesh(pala, Vector3(3.8, 0.18, 0.2), Vector3(0, -0.52, 0.45), _mm(Color(0.8, 0.1, 0.08), 0.4, 0.5))
	_qn_giro = Node3D.new()
	_qn.add_child(_qn_giro)
	_qn_giro.position = Vector3(0, 3.75, 1.4)
	_esfera_mesh(_qn_giro, 0.2, Vector3.ZERO, _brillo(Color(1.0, 0.55, 0.05), 3.0))
	var baliza := SpotLight3D.new()
	baliza.light_color = Color(1.0, 0.55, 0.1)
	baliza.light_energy = 5.0
	baliza.spot_range = 18.0
	baliza.spot_angle = 30.0
	baliza.shadow_enabled = false
	_qn_giro.add_child(baliza)
	baliza.rotation.x = -0.35
	for s in [-0.9, 0.9]:
		var faro := SpotLight3D.new()
		faro.light_color = Color(1.0, 0.95, 0.82)
		faro.light_energy = 4.0
		faro.spot_range = 26.0
		faro.spot_angle = 28.0
		faro.shadow_enabled = false
		_qn.add_child(faro)
		faro.position = Vector3(s, 2.2, -2.6)
		faro.rotation.x = -0.12
	_colision_caja(_qn, Vector3(2.8, 2.6, 7.4), Vector3(0, 1.5, -0.3))
	_qn_motor = _bucle_directo("res://sounds/gen/quitanieves/motor1.ogg", _qn, Vector3(0, 1.5, 0), -60.0, 45.0)
	_qn_colocar(0.0)
	_rotulo("quitanieves", "QUITANIEVES", Vector3(144.0, G6 + 4.6, 80.0), COLOR_AVISO)


## (x, z, rumbo) a `s` metros del principio de la ruta
func _qn_punto(s: float) -> Array:
	var r: Array = _c("p04_quitanieves")["ruta"]
	var resto := s
	for i in range(1, r.size()):
		var a := Vector2(float(r[i - 1][0]), float(r[i - 1][1]))
		var b := Vector2(float(r[i][0]), float(r[i][1]))
		var l := a.distance_to(b)
		if resto <= l or i == r.size() - 1:
			var p := a.lerp(b, clampf(resto / maxf(l, 0.01), 0.0, 1.0))
			return [p, (b - a).normalized()]
		resto -= l
	return [Vector2(float(r[0][0]), float(r[0][1])), Vector2(1, 0)]


var _qn_puesta := -1.0


func _qn_colocar(s: float) -> void:
	if not is_instance_valid(_qn) or is_equal_approx(s, _qn_puesta):
		return
	_qn_puesta = s
	var pr := _qn_punto(s)
	var p: Vector2 = pr[0]
	var d: Vector2 = pr[1]
	var y := _camino_y(p.x, p.y)
	var y_delante := _camino_y(p.x + d.x * 3.0, p.y + d.y * 3.0)
	var t := Transform3D()
	t.basis = Basis.looking_at(Vector3(d.x, (y_delante - y) / 3.0, d.y), Vector3.UP)
	t.origin = Vector3(p.x, y, p.y)
	_qn.global_transform = t


func _qn_frente() -> Vector3:
	var pr := _qn_punto(_qn_s)
	var p: Vector2 = pr[0]
	var d: Vector2 = pr[1]
	var f := p + d * 3.9
	return Vector3(f.x, _camino_y(f.x, f.y), f.y)


func _en_ventisquero(p: Vector3) -> bool:
	for v in _c("p04_quitanieves").get("ventisqueros", []):
		if p.x > float(v[0]) - 1.2 and p.x < float(v[2]) + 1.2 and p.z > float(v[1]) - 1.2 and p.z < float(v[3]) + 1.2:
			return true
	return false


## Todas las maquinas: la quitanieves va hacia donde dice el anfitrion; la baliza gira, el motor suena
func _qn_tick(dt: float) -> void:
	if not is_instance_valid(_qn):
		return
	_qn_s_vista = move_toward(_qn_s_vista, _qn_s, dt * 4.0) if absf(_qn_s - _qn_s_vista) < 12.0 else _qn_s
	_qn_colocar(_qn_s_vista)
	if is_instance_valid(_qn_giro):
		_qn_giro.rotation.y += dt * (6.0 if _qn_estado > 0 else 0.0)
	if is_instance_valid(_qn_motor):
		_qn_motor.volume_db = -60.0 if _qn_estado == 0 else (-2.0 if _qn_estado == 1 else -10.0)
		_qn_motor.pitch_scale = 1.15 if _qn_estado == 1 else 0.85
	if is_instance_valid(jugador) and _qn_estado in [1, 2, 3] and jugador.global_position.distance_to(_qn.global_position) < 30.0:
		var txt := "QUITANIEVES · %d %%" % int(_qn_s / maxf(1.0, _qn_largo) * 100.0)
		if _qn_estado == 2:
			txt += " · ¡SIN ESCOLTA NO AVANZA!"
		elif _qn_estado == 3:
			txt += " · ¡LA RODEAN!"
		_barra_quiero(txt, _qn_s / maxf(1.0, _qn_largo), Color(0.95, 0.65, 0.1, 0.95))


## (el anfitrion) avanza, se para, abre los ventisqueros y atropella
func _qn_host_tick(dt: float) -> void:
	if _qn_estado in [0, 4, 5] or not is_instance_valid(_qn):
		return
	var c := _c("p04_quitanieves")
	var pr := _qn_punto(_qn_s)
	var p2: Vector2 = pr[0]
	var p := Vector3(p2.x, _camino_y(p2.x, p2.y), p2.y)
	var escolta := false
	for pl in _jugadores_vivos():
		if (pl as Node3D).global_position.distance_to(p) < 15.0:
			escolta = true
	var rodean := 0
	for cr in _vivos:
		if is_instance_valid(cr) and not bool(cr.get("muerta")) and not bool(cr.get("dormida")) 				and (cr as Node3D).global_position.distance_to(p) < 4.8:
			rodean += 1
	var nuevo := 1
	if not escolta:
		nuevo = 2
	elif rodean >= 3:
		nuevo = 3
	if nuevo != _qn_estado:
		_evento("p04_estado", [_qn_s, nuevo])
	if _qn_estado == 1:
		var frente := _qn_frente()
		var v := float(c.get("v", 2.0)) * (0.55 if _en_ventisquero(frente) else 1.0)
		_qn_s = minf(_qn_s + v * dt, _qn_largo)
		_qn_s_vista = _qn_s
		frente = _qn_frente()
		if not _h("p05") and frente.z < 20.0 and frente.x <= float(c.get("derrumbe_x", 158.2)):
			_evento("p04_estado", [_qn_s, 4])
		elif _qn_s >= _qn_largo - 0.01:
			_evento("p04_estado", [_qn_s, 5])
		_qn_pala_t -= dt
		if _qn_pala_t <= 0.0:
			_qn_pala_t = 0.3
			if _en_ventisquero(frente):
				var d: Vector2 = pr[1]
				_evento("p04_pala", [frente.x, frente.y, frente.z, d.x, d.y])
			Combat.damage_around(get_tree(), frente + Vector3.UP * 0.8, 2.4, 45.0, null, false)
	_qn_red_t -= dt
	if _qn_red_t <= 0.0:
		_qn_red_t = 0.25
		if _en_red:
			Net.net_campana("p04_s", [_qn_s])
	_qn_tanda_t -= dt
	if _qn_tanda_t <= 0.0:
		_qn_tanda_t = 28.0
		if _cola.size() < 6:
			_horda(8, "")


func _qn_nuevo_estado(s: float, e: int) -> void:
	var antes := _qn_estado
	_qn_s = s
	_qn_estado = e
	if not is_instance_valid(_qn):
		return
	var p := _qn.global_position
	match e:
		1:
			if antes == 0 or antes == 4:
				Audio.play3d("gen/quitanieves/bocina", p + Vector3.UP * 2.0, 4.0, 0.0, 90.0, Audio.PRI_HIGH)
			if antes in [2, 3]:
				_mensaje_local("La quitanieves sigue")
		2:
			_mensaje_local("¡LA QUITANIEVES SE PARA! Sin escolta no avanza: QUEDAOS CERCA")
		3:
			_mensaje_local("¡LA ESTÁN RODEANDO! Quitadle los bichos de encima")
			Audio.play3d("gen/quitanieves/bocina", p + Vector3.UP * 2.0, 2.0, 0.0, 70.0, Audio.PRI_MID)
		4:
			_mensaje_local("¡UN DERRUMBE CORTA LA CARRETERA! El ROBOT de la furgoneta de los TEDAX")
			Audio.play3d("gen/quitanieves/bocina", p + Vector3.UP * 2.0, 4.0, 0.0, 90.0, Audio.PRI_HIGH)
		5:
			_mensaje_local("La quitanieves llega al BARRANCO… y el puente no está")


func _qn_pala(f: Vector3, d: Vector2) -> void:
	if world == null:
		return
	var lado := Vector3(-d.y, 0.0, d.x)
	var y := _camino_y(f.x, f.z)
	for k in range(-5, 6):
		var b := f + lado * (k * 0.42) + Vector3(d.x, 0, d.y) * 0.3
		world.carve_beam(Vector3(b.x, y - 0.15, b.z), Vector3.UP, 3.6, 0.4, 120, true)
	if is_instance_valid(jugador) and jugador.global_position.distance_to(f) < 40.0:
		var s := _particulas(self, f + Vector3.UP * 1.2, 26, 1.6, Color(0.96, 0.97, 1.0, 0.95), Color(0.85, 0.88, 0.92), 0.6, false)
		s.one_shot = true
		s.explosiveness = 0.7
		s.direction = Vector3(-d.y, 1.2, d.x)
		s.spread = 40.0
		s.initial_velocity_min = 3.0
		s.initial_velocity_max = 7.0
		s.gravity = Vector3(0, -6.0, 0)
		get_tree().create_timer(2.0).timeout.connect(s.queue_free)
		_qn_pisa_t -= 0.3
		if _qn_pisa_t <= 0.0:
			_qn_pisa_t = 1.8
			Audio.play3d("gen/quitanieves/pala", f, 2.0, 0.1, 40.0, Audio.PRI_MID)


# ======================================================================================================
# 5. EL ROBOT DE LOS TEDAX (se conduce viendo por su camara)
# ======================================================================================================
func _montar_p05() -> void:
	var c := _c("p05_robot")
	if c.is_empty():
		return
	var celdas: Array = c["celdas"]
	_robot_celda = Vector2(float(celdas[0][0]), float(celdas[0][1]))
	_robot = Node3D.new()
	_robot.name = "RobotTedax"
	add_child(_robot)
	var gris := _mm(Color(0.25, 0.27, 0.28), 0.6, 0.5)
	var negro := _mm(Color(0.06, 0.06, 0.06), 0.4, 0.7)
	var amarillo := _mm(Color(0.95, 0.72, 0.1), 0.3, 0.5)
	_caja_mesh(_robot, Vector3(0.62, 0.26, 0.82), Vector3(0, 0.24, 0), gris)
	for s in [-0.36, 0.36]:
		_caja_mesh(_robot, Vector3(0.14, 0.24, 0.9), Vector3(s, 0.13, 0), negro)
	_caja_mesh(_robot, Vector3(0.64, 0.05, 0.2), Vector3(0, 0.38, 0.3), amarillo)
	_caja_mesh(_robot, Vector3(0.06, 0.45, 0.06), Vector3(0, 0.6, 0.2), gris)
	_caja_mesh(_robot, Vector3(0.16, 0.1, 0.14), Vector3(0, 0.85, 0.18), negro)
	_caja_mesh(_robot, Vector3(0.06, 0.06, 0.5), Vector3(0.18, 0.42, -0.32), gris)
	var carga := _caja_mesh(_robot, Vector3(0.22, 0.14, 0.18), Vector3(0, 0.44, -0.05), _mm(Color(0.72, 0.1, 0.07), 0.3, 0.5))
	carga.name = "Carga"
	var foco := SpotLight3D.new()
	foco.light_energy = 3.0
	foco.spot_range = 9.0
	foco.spot_angle = 38.0
	foco.shadow_enabled = false
	_robot.add_child(foco)
	foco.position = Vector3(0, 0.85, -0.1)
	# LA CAMARA DEL ROBOT: lo que ve sale en la pantalla de la furgoneta
	_robot_vp = SubViewport.new()
	_robot_vp.size = Vector2i(320, 240)
	_robot_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_robot_vp)
	_robot_cam = Camera3D.new()
	_robot_cam.fov = 72.0
	_robot_cam.near = 0.05
	_robot_cam.far = 60.0
	_robot_vp.add_child(_robot_cam)
	# LA CONSOLA, detras de la furgoneta. Quien conduce se pone al oeste mirando al este (con la carretera y el
	# derrumbe a la espalda): el teclado inclinado hacia el con las tres teclas de flecha (GIRAR ◀, AVANZAR ▲,
	# GIRAR ▶, de izquierda a derecha como se ven), el DETONADOR a la derecha y la pantalla con su marco encima.
	# Antes era una mesa lisa: "me dice pulsa y no hay nada que pulsar".
	var con := _v(c["consola"])
	var mesa := _estatico("ConsolaRobot", con + Vector3(0, 0.5, 0))
	var chapa := _mm(Color(0.22, 0.24, 0.26), 0.5, 0.5)
	var oscuro := _mm(Color(0.07, 0.07, 0.08), 0.3, 0.8)
	_caja_mesh(mesa, Vector3(0.7, 1.0, 1.5), Vector3.ZERO, chapa)
	_caja_mesh(mesa, Vector3(0.74, 0.08, 1.54), Vector3(0, -0.46, 0), oscuro)
	_colision_caja(mesa, Vector3(0.7, 1.0, 1.5), Vector3.ZERO)
	var incl := 0.5
	var nt := Vector3(-sin(incl), cos(incl), 0)             # la cara del teclado (hacia -X y arriba)
	var teclado := _caja_mesh(mesa, Vector3(0.3, 0.04, 1.0), Vector3(-0.18, 0.56, -0.2), _mm(Color(0.12, 0.13, 0.14), 0.4, 0.6))
	teclado.rotation.z = incl
	_caja_mesh(mesa, Vector3(0.05, 0.14, 1.0), Vector3(-0.04, 0.565, -0.2), chapa)
	for t in [["p05_izq", "tecla_izq", -0.5], ["p05_avanza", "tecla_arriba", -0.2], ["p05_der", "tecla_der", 0.1]]:
		_mnd_p05[t[0]] = Mandos.crear(String(t[1]), mesa, Vector3(-0.18, 0.56, float(t[2])) + nt * 0.021, nt, true)
	_mnd_p05["p05_detonar"] = _mnd_de_pie("detonador", mesa, Vector3(-0.08, 0.5, 0.48), Vector3(-1, 0, 0))
	Mandos.piloto(_mnd_p05["p05_detonar"], "apagado")      # sin la carga puesta no hay nada que detonar
	_pantalla_robot = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.68)
	_pantalla_robot.mesh = q
	var mp := StandardMaterial3D.new()
	mp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mp.albedo_texture = _robot_vp.get_texture()
	_pantalla_robot.material_override = mp
	mesa.add_child(_pantalla_robot)
	_pantalla_robot.position = Vector3(0.12, 1.0, -0.2)
	_pantalla_robot.rotation.y = -PI / 2
	_pantalla_robot.rotation.x = -0.2
	_caja_mesh(_pantalla_robot, Vector3(0.98, 0.76, 0.05), Vector3(0, 0, -0.03), oscuro)       # el marco del monitor
	_caja_mesh(mesa, Vector3(0.06, 0.36, 0.12), Vector3(0.15, 0.68, -0.2), oscuro)             # y su pie
	_rotulo("robot", "ROBOT DE LOS TEDAX\n(se ve por su cámara)", con + Vector3(0, 2.4, 0), COLOR_INFO)
	_robot_colocar(true)


func _robot_dirv(d: int) -> Vector2:
	return [Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0), Vector2(0, 1)][posmod(d, 4)]


func _robot_colocar(ya: bool) -> void:
	if not is_instance_valid(_robot):
		return
	var p := Vector3(_robot_celda.x, _camino_y(_robot_celda.x, _robot_celda.y) + 0.02, _robot_celda.y)
	var giro: float = [PI / 2, 0.0, -PI / 2, PI][posmod(_robot_dir, 4)]
	var carga := _robot.get_node_or_null("Carga")
	if carga:
		carga.visible = not _robot_carga
	if ya:
		_robot.global_position = p
		_robot.rotation.y = giro
		return
	var tw := _robot.create_tween()
	tw.tween_property(_robot, "global_position", p, 0.5)
	var actual := _robot.rotation.y
	var dif := wrapf(giro - actual, -PI, PI)
	tw.parallel().tween_property(_robot, "rotation:y", actual + dif, 0.4)
	Audio.play3d("gen/robot/motor", p, 0.0, 0.1, 25.0, Audio.PRI_MID)


func _robot_tick(_dt: float) -> void:
	if not is_instance_valid(_robot_vp) or not is_instance_valid(_robot):
		return
	var cerca := is_instance_valid(jugador) and fase == "p05" and jugador.global_position.distance_to(_v(_c("p05_robot")["consola"])) < 14.0
	_robot_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if cerca else SubViewport.UPDATE_DISABLED
	# sin pintar, la textura del viewport es basura de colores: mientras no se usa, la pantalla esta apagada
	if is_instance_valid(_pantalla_robot) and _pantalla_robot.material_override is StandardMaterial3D:
		(_pantalla_robot.material_override as StandardMaterial3D).albedo_color = Color.WHITE if cerca else Color(0.02, 0.025, 0.03)
	if cerca and is_instance_valid(_robot_cam):
		var t := _robot.global_transform
		_robot_cam.global_transform = Transform3D(t.basis, t.origin + t.basis.y * 0.85 + t.basis.z * 0.1)
		_robot_cam.rotate_object_local(Vector3.RIGHT, -0.12)


## (el anfitrion) un paso adelante: si la celda de delante tiene roca, choca
func _robot_avanza() -> void:
	var dv := _robot_dirv(_robot_dir)
	var dest := _robot_celda + dv
	var y := _camino_y(dest.x, dest.y)
	var n := 0
	if world:
		n = int(world.contar_voxels(Vector3(dest.x - 0.33, y + 0.18, dest.y - 0.33), Vector3(dest.x + 0.33, y + 0.8, dest.y + 0.33)))
	if n > 12:
		_evento("p05_choca", [])
		return
	var meta: Array = _c("p05_robot").get("meta", [150.5, 10.5])
	var llega := dest.distance_to(Vector2(float(meta[0]), float(meta[1]))) < 0.1
	_evento("p05_mueve", [dest.x, dest.y, _robot_dir, 1 if (llega or _robot_carga) else 0])
	if llega and not _robot_carga:
		_mensaje("CARGA COLOCADA JUNTO A LA PIEDRA CLAVE · ¡DETONAD DESDE LA FURGONETA!")


func _p05_resuelto(ya: bool) -> void:
	var c := _c("p05_robot")
	var d: Array = c.get("derrumbe", [148, 6.5, 6, 156, 12.5, 16])
	_mnd_accionar(_mnd_p05.get("p05_detonar"))             # el embolo del detonador, abajo
	# LA ROCA SE VA: las explosiones pierden fuerza con la distancia y la piedra aguanta (solo mordian un 27 %), asi
	# que la carga TALLA el derrumbe entero con haces que siguen la pendiente de la carretera (cada maquina, igual)
	if world:
		var xa := float(d[3]) + 1.2
		var xb := float(d[0]) - 1.0
		var h := 0.25
		while h < 6.8:
			var z := float(d[2]) + 0.4
			while z < float(d[5]) - 0.3:
				var a := Vector3(xa, _camino_y(xa, z) + h, z)
				var b := Vector3(xb, _camino_y(xb, z) + h, z)
				world.carve_beam(a, (b - a).normalized(), a.distance_to(b), 0.36, 255, true)
				z += 0.5
			h += 0.5
	if is_instance_valid(_robot):
		_robot.visible = false
	if ya:
		return
	var centro := Vector3((float(d[0]) + float(d[3])) / 2.0, _camino_y(152.0, 11.0) + 2.0, (float(d[2]) + float(d[5])) / 2.0)
	var cam := Vector3(171.0, 11.8, 11.8)
	_corte([[cam, centro, 0.0], [cam + Vector3(-2.0, 1.5, 2.5), centro + Vector3(0, 2.5, 0), 4.5]], 4.8, "")
	for i in 5:
		var p := centro + Vector3(randf_range(-3.0, 3.0), randf_range(-0.5, 2.0), randf_range(-3.5, 3.5))
		var k := i
		get_tree().create_timer(0.15 * k).timeout.connect(func():
			_explosion(p, 3.0, 120.0, 0.0)
			_bola_fuego6(p, 2.2))
	get_tree().create_timer(0.6).timeout.connect(func():
		_golpe(centro, 3.0, "destru/derrumbe_grave")
		_rompe_local(centro, 4.0))
	var rocas := _particulas(self, centro + Vector3.UP, 60, 2.4, Color(0.45, 0.42, 0.4, 1.0), Color(0.3, 0.28, 0.26), 0.5, false)
	rocas.one_shot = true
	rocas.explosiveness = 0.95
	rocas.initial_velocity_min = 5.0
	rocas.initial_velocity_max = 14.0
	rocas.spread = 70.0
	rocas.direction = Vector3.UP
	rocas.gravity = Vector3(0, -9.8, 0)
	get_tree().create_timer(3.0).timeout.connect(rocas.queue_free)
	_mensaje_local("¡EL DERRUMBE HA VOLADO! La quitanieves puede seguir")


# ======================================================================================================
# 6. LA AVALANCHA (los tres GAZEX de la cornisa; la nieve rellena el barranco)
# ======================================================================================================
func _montar_p06() -> void:
	var c := _c("p06_alud")
	if c.is_empty():
		return
	var tubo := _mm(Color(0.62, 0.64, 0.66), 0.7, 0.4)
	var rojo := _mm(Color(0.8, 0.14, 0.08), 0.4, 0.5)
	for i in _gazex_pos.size():
		var p: Vector3 = _gazex_pos[i]
		var d := _diana("gazex%d" % i, p, Vector3(1.0, 1.4, 1.0))
		# el exploder: un tubo que mira ladera abajo y la bombona de gas roja al lado
		_cil_mesh(d, 0.35, 2.6, Vector3(0, 0.2, 0.6), tubo, Vector3(1.1, 0, 0), 12)
		_cil_mesh(d, 0.32, 0.9, Vector3(0.6, -0.1, -0.2), rojo, Vector3.ZERO, 12)
		_esfera_mesh(d, 0.32, Vector3(0.6, 0.35, -0.2), rojo)
		var luz := _esfera_mesh(d, 0.08, Vector3(0, 0.75, 0), _brillo(Color(1.0, 0.1, 0.05), 3.0))
		luz.name = "Luz"
		_gazex_nodos.append(d)
	_rotulo("gazex", "GAZEX: DISPARAD A LAS\nBOMBONAS DE LA CORNISA", Vector3(128.0, 12.6, 12.0), COLOR_AVISO)


func _gazex_revienta(i: int, ya: bool) -> void:
	if i < 0 or i >= _gazex.size() or bool(_gazex[i]):
		return
	_gazex[i] = true
	var p: Vector3 = _gazex_pos[i]
	var d = _dianas.get("gazex%d" % i)
	if is_instance_valid(d):
		d.queue_free()
	_dianas.erase("gazex%d" % i)
	if _soy_host and world:
		Net.net_explode(world, p + Vector3(0, -0.6, 1.2), 3.4, 255)
	if ya:
		return
	_explosion(p, 3.4, 60.0, 0.0)
	_bola_fuego6(p, 3.0)
	var nieve := _particulas(self, p, 50, 3.0, Color(0.96, 0.97, 1.0, 0.95), Color(0.85, 0.88, 0.92), 1.4, false)
	nieve.one_shot = true
	nieve.explosiveness = 0.9
	nieve.initial_velocity_min = 3.0
	nieve.initial_velocity_max = 9.0
	nieve.direction = Vector3(0, 0.3, 1)
	nieve.spread = 60.0
	nieve.gravity = Vector3(0, -6.0, 0)
	get_tree().create_timer(3.5).timeout.connect(nieve.queue_free)
	var n := 0
	for g in _gazex:
		if bool(g):
			n += 1
	_mensaje_local("¡GAZEX %d DE 3!" % n if n < 3 else "¡LA CORNISA SE SUELTA!")


## La cornisa cae: la avalancha barre el final de la carretera y RELLENA el barranco (se cruza por la nieve)
func _p06_resuelto(ya: bool) -> void:
	var c := _c("p06_alud")
	var r: Array = c.get("relleno", [108.6, 5.2, 125.4, 16.8])
	var y0 := float(c.get("relleno_y", 6.0))
	var mn := Vector3(float(r[0]), y0, float(r[1]))
	var mx := Vector3(float(r[2]), M6, float(r[3]))
	var nieve := int(_matid.get("nieve_dura", 0))
	if _soy_host:
		for cr in _vivos:
			if not is_instance_valid(cr):
				continue
			var q: Vector3 = (cr as Node3D).global_position
			if q.x > 100.0 and q.x < 150.0 and q.z < 22.0 and cr.has_method("take_damage"):
				cr.take_damage(99999.0, Vector3(0, -2, 6))
		if world:
			var k: Array = c.get("caja", [108, 16.2, 2.5, 128.5, 22.4, 11])
			var x := float(k[0]) + 2.0
			while x < float(k[3]):
				Net.net_explode(world, Vector3(x, 19.4, 7.5), 3.4, 60)
				x += 4.0
	if ya:
		_sacar_de(mn, mx, Vector3(131.0, M6 - 0.1, 11.0))
		_rellenar(mn, mx, nieve)
		return
	# LA ESCENA: la cornisa se suelta, la nieve cae en cascada y el barranco se llena
	var cam := _v(c.get("camara", [96, 16, 30]))
	var cornisa := Vector3(118.0, 19.0, 7.0)
	var fondo := Vector3(117.0, 5.0, 11.0)
	_corte([[cam, cornisa, 0.0], [cam + Vector3(1.0, 1.0, -2.0), fondo, 4.0], [cam + Vector3(3.0, -2.0, -6.0), fondo + Vector3(0, 3.0, 0), 9.0]], 9.2, "")
	Audio.play3d("gen/alud/estruendo", cornisa, 12.0, 0.0, 400.0, Audio.PRI_TOP)
	for i in 6:
		var p := cornisa + Vector3(-8.0 + i * 3.2, randf_range(-1.0, 1.5), randf_range(-1.0, 1.0))
		var cae := _particulas(self, p, 70, 3.2, Color(0.97, 0.98, 1.0, 0.98), Color(0.86, 0.9, 0.95), 2.6, false)
		cae.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		cae.emission_box_extents = Vector3(1.8, 1.0, 1.4)
		cae.direction = Vector3(0, -0.6, 1)
		cae.spread = 25.0
		cae.initial_velocity_min = 3.0
		cae.initial_velocity_max = 8.0
		cae.gravity = Vector3(0, -9.0, 0)
		var kk := i
		get_tree().create_timer(4.5 + kk * 0.2).timeout.connect(func(): cae.emitting = false)
		get_tree().create_timer(9.0).timeout.connect(cae.queue_free)
	var polvo := _particulas(self, fondo, 80, 5.0, Color(0.95, 0.96, 1.0, 0.9), Color(0.82, 0.86, 0.9), 6.0, false)
	polvo.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	polvo.emission_box_extents = Vector3(9.0, 2.0, 7.0)
	polvo.initial_velocity_min = 1.0
	polvo.initial_velocity_max = 4.0
	polvo.spread = 90.0
	get_tree().create_timer(6.0).timeout.connect(func(): polvo.emitting = false)
	get_tree().create_timer(11.0).timeout.connect(polvo.queue_free)
	for t in [0.3, 1.2, 2.4, 3.6, 5.0]:
		get_tree().create_timer(t).timeout.connect(func(): _golpe(fondo, 2.5, "destru/derrumbe_grave"))
	# el relleno sube por capas (en todas las maquinas igual)
	var capas := 6
	for i in capas:
		var a := y0 + (M6 - y0) * i / capas
		var b := y0 + (M6 - y0) * (i + 1) / capas
		var ki := i
		get_tree().create_timer(1.6 + ki * 0.5).timeout.connect(func():
			_sacar_de(Vector3(mn.x, a, mn.z), Vector3(mx.x, b + 1.8, mx.z), Vector3(131.0, M6 - 0.1, 11.0))
			_rellenar(Vector3(mn.x, a, mn.z), Vector3(mx.x, b, mx.z), nieve))
	get_tree().create_timer(9.5).timeout.connect(func():
		_mensaje_local("¡LA AVALANCHA HA TAPADO EL BARRANCO! Cruzad por la nieve"))


# ======================================================================================================
# 7. LA VENTISCA (frio, braseros, grietas con puentes de nieve falsos y la campana para orientarse)
# ======================================================================================================
func _montar_p07() -> void:
	var c := _c("p07_ventisca")
	if c.is_empty():
		return
	var br: Array = c.get("braseros", [])
	for i in br.size():
		var p := _v(br[i])
		var n := Node3D.new()
		add_child(n)
		n.global_position = p + Vector3(0, 0.9, 0)
		var f := _particulas(n, Vector3.ZERO, 26, 0.8, Color(1.0, 0.8, 0.3, 0.95), Color(0.7, 0.12, 0.0), 0.8, true)
		f.direction = Vector3.UP
		f.gravity = Vector3(0, 3.0, 0)
		f.initial_velocity_min = 0.4
		f.initial_velocity_max = 1.4
		f.name = "Fuego"
		var l := _luz(n, Vector3(0, 0.6, 0), Color(1.0, 0.55, 0.2), 2.2, 9.0)
		l.name = "Luz"
		n.visible = false
		_brasero_fx[i] = n
	_encender_brasero(0, true)
	_rotulo("braseros", "BRASEROS: CALOR\n(encendedlos)", _v(br[0]) + Vector3(0, 2.6, 0), COLOR_INFO)
	_viento = AudioStreamPlayer.new()
	var st = load("res://sounds/gen/viento/ventisca1.ogg")
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	_viento.stream = st
	_viento.volume_db = -60.0
	_viento.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(_viento)


func _encender_brasero(i: int, ya: bool) -> void:
	if i < 0 or i >= _braseros.size():
		return
	_braseros[i] = true
	var n = _brasero_fx[i]
	if is_instance_valid(n):
		(n as Node3D).visible = true
		if not ya:
			Audio.bf3d("gadget/c4_activar", (n as Node3D).global_position, 0.0, 30.0, Audio.PRI_MID)
			_bucle_bf("bf/amb/bucle_fuego", n, Vector3.ZERO, -6.0, 18.0)


func _calor_cerca(p: Vector3) -> bool:
	var br: Array = _c("p07_ventisca").get("braseros", [])
	for i in br.size():
		if bool(_braseros[i]) and p.distance_to(_v(br[i])) < 5.5:
			return true
	return false


func _en_ventisca(p: Vector3) -> bool:
	var z: Array = _c("p07_ventisca").get("zona", [62, 0, 110, 56])
	return p.x > float(z[0]) and p.x < float(z[2]) and p.z > float(z[1]) and p.z < float(z[3]) and p.y > M6 - 4.0


## Cada maquina, lo de SU jugador: la niebla, el viento, el frio, las caidas y los puentes de nieve que ceden
func _ventisca_tick(dt: float) -> void:
	var c := _c("p07_ventisca")
	if c.is_empty() or not is_instance_valid(jugador):
		return
	var jp: Vector3 = jugador.global_position
	var dentro := _en_ventisca(jp) and not bool(jugador.get("spectating")) and not terminado
	_vent_k = move_toward(_vent_k, 1.0 if dentro else 0.0, dt * 0.45)
	var escena := get_tree().current_scene
	if escena and "env" in escena and escena.env and escena.env.environment:
		var e: Environment = escena.env.environment
		if _niebla_base < 0.0:
			_niebla_base = e.fog_density
		if _vent_k > 0.001 or not is_equal_approx(e.fog_density, _niebla_base):
			e.fog_enabled = true
			e.fog_density = lerpf(_niebla_base, 0.075, _vent_k)
	if escena and "_nieve_fx" in escena and escena._nieve_fx and escena._nieve_fx.process_material is ParticleProcessMaterial:
		var m: ParticleProcessMaterial = escena._nieve_fx.process_material
		m.direction = Vector3(-1.0 * _vent_k, -1.0, 0.4 * _vent_k).normalized()
		m.initial_velocity_min = lerpf(0.6, 6.0, _vent_k)
		m.initial_velocity_max = lerpf(1.4, 10.0, _vent_k)
	if is_instance_valid(_viento):
		if _vent_k > 0.01 and not _viento.playing:
			_viento.play()
		_viento.volume_db = lerpf(-40.0, -4.0, _vent_k)
		if _vent_k <= 0.01 and _viento.playing:
			_viento.stop()
	# EL FRIO
	var maximo := 100.0
	if dentro:
		if _calor_cerca(jp):
			_frio = minf(maximo, _frio + dt * 22.0)
		else:
			_frio = maxf(0.0, _frio - dt * maximo / float(c.get("frio_s", 45.0)))
	else:
		_frio = minf(maximo, _frio + dt * 12.0)
	if dentro or _frio < maximo - 0.5:
		_barra_quiero("FRÍO · buscad un BRASERO" if _frio < 35.0 else "FRÍO", _frio / maximo,
			Color(1.0, 0.3, 0.2, 0.95) if _frio < 30.0 else Color(0.55, 0.8, 1.0, 0.95))
	if _frio <= 0.0 and dentro:
		_frio_dano_t -= dt
		if _frio_dano_t <= 0.0:
			_frio_dano_t = 0.8
			if jugador.has_method("take_damage") and not bool(jugador.get("invulnerable")):
				jugador.take_damage(5.0, Vector3.ZERO)
			var ahora := Time.get_ticks_msec() * 0.001
			if ahora - _dano_aviso_t > 3.0:
				_dano_aviso_t = ahora
				_mensaje_local("¡TE ESTÁS CONGELANDO! Un BRASERO, ya")
	# LA CAMPANA del monasterio (para orientarse en la ventisca)
	if _vent_k > 0.3:
		_campana_t -= dt
		if _campana_t <= 0.0:
			_campana_t = 4.5
			var cp: Array = _c("p08_campanas").get("campanas", [])
			if not cp.is_empty():
				Audio.play3d("gen/campana/c1", _v(cp[0]), 6.0, 0.0, 140.0, Audio.PRI_MID)
	# LAS CAIDAS (a una grieta o al barranco)
	var caido := -1
	var gr: Array = c.get("grietas", [])
	for i in gr.size():
		var g: Array = gr[i]
		if jp.x > float(g[0]) and jp.x < float(g[2]) and jp.z > float(g[1]) and jp.z < float(g[3]) and jp.y < M6 - 2.2:
			caido = i
	var gar: Array = _c("p06_alud").get("garganta", [110, 0, 124, 84])
	var en_gar := jp.x > float(gar[0]) and jp.x < float(gar[2]) and jp.z > float(gar[1]) and jp.z < float(gar[3]) and jp.y < M6 - 3.5
	if (caido >= 0 or en_gar) and not bool(jugador.get("spectating")):
		_caida_t += dt
		if _caida_t > 0.6:
			_caida_t = 0.0
			var sal: Vector3
			if caido >= 0:
				sal = _v(c["salvado"][caido])
			elif progreso >= _indice_de("puente de nieve"):
				sal = Vector3(105.0, M6 + 0.2, 10.0)
			else:
				sal = Vector3(131.0, M6 - 0.1, 11.0)
			jugador.global_position = sal + Vector3.UP * 0.3
			jugador.velocity = Vector3.ZERO
			if jugador.has_method("take_damage") and not bool(jugador.get("invulnerable")):
				jugador.take_damage(20.0, Vector3.ZERO)
			_mensaje_local("¡HAS CAÍDO A UNA GRIETA!" if caido >= 0 else "¡HAS CAÍDO AL BARRANCO!")
	else:
		_caida_t = 0.0
	# LOS PUENTES DE NIEVE FALSOS: ceden si te quedas encima
	var fal: Array = c.get("falsos", [])
	var sobre := ""
	if jugador.is_on_floor() and jp.y > M6 - 0.3 and jp.y < M6 + 0.7:
		for i in mini(fal.size(), gr.size()):
			var g: Array = gr[i]
			if jp.z < float(g[1]) - 0.3 or jp.z > float(g[3]) + 0.3:
				continue
			for j in (fal[i] as Array).size():
				var f: Array = fal[i][j]
				if jp.x > float(f[0]) and jp.x < float(f[1]) and not _falsos_rotos.has("%d,%d" % [i, j]):
					sobre = "%d,%d" % [i, j]
	if sobre == "":
		_falso_t = 0.0
		_falso_k = ""
	else:
		if sobre != _falso_k:
			_falso_k = sobre
			_falso_t = 0.0
			Audio.play3d("gen/hielo/cruje", jp, -4.0, 0.1, 20.0, Audio.PRI_MID)
		_falso_t += dt
		if _falso_t > 0.35:
			_falso_t = -99.0
			var accion := "falso:" + sobre
			if _en_red and not _soy_host:
				Net.net_campana_pide(accion)
			else:
				_on_pide(accion, _mi_id())


func _romper_falso(i: int, j: int, ya: bool) -> void:
	var k := "%d,%d" % [i, j]
	if _falsos_rotos.has(k):
		return
	_falsos_rotos[k] = true
	var c := _c("p07_ventisca")
	var g: Array = c["grietas"][i]
	var f: Array = c["falsos"][i][j]
	if world:
		var z := float(g[1]) - 0.3
		while z <= float(g[3]) + 0.3:
			world.carve_beam(Vector3(float(f[0]) + 0.1, M6 - 0.35, z), Vector3.RIGHT, float(f[1]) - float(f[0]) - 0.2, 0.42, 60, true)
			z += 0.35
	if ya:
		return
	var centro := Vector3((float(f[0]) + float(f[1])) / 2.0, M6, (float(g[1]) + float(g[3])) / 2.0)
	var s := _particulas(self, centro, 50, 2.0, Color(0.96, 0.97, 1.0, 0.95), Color(0.85, 0.88, 0.92), 0.9, false)
	s.one_shot = true
	s.explosiveness = 0.9
	s.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	s.emission_box_extents = Vector3(1.4, 0.2, 1.6)
	s.initial_velocity_min = 0.5
	s.initial_velocity_max = 2.0
	s.gravity = Vector3(0, -7.0, 0)
	get_tree().create_timer(3.0).timeout.connect(s.queue_free)
	Audio.bf3d("destru/derrumbe_medio", centro, 0.0, 50.0, Audio.PRI_HIGH)


# ======================================================================================================
# 8. LAS CAMPANAS DE LA ESPADAÑA (la melodia se repite disparando a las campanas, en orden)
# ======================================================================================================
func _montar_p08() -> void:
	var c := _c("p08_campanas")
	if c.is_empty():
		return
	var bronce := _mm(Color(0.62, 0.45, 0.2), 0.85, 0.35)
	var hierro := _mm(Color(0.1, 0.1, 0.1), 0.6, 0.5)
	var cp: Array = c["campanas"]
	for i in cp.size():
		var p := _v(cp[i])
		var d := _diana("campana%d" % i, p, Vector3(1.5, 1.6, 1.4))
		var eje := Node3D.new()
		d.add_child(eje)
		eje.position = Vector3(0, 0.75, 0)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.42
		cm.bottom_radius = 0.72
		cm.height = 1.15
		cm.radial_segments = 18
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = bronce
		eje.add_child(mi)
		mi.position = Vector3(0, -0.72, 0)
		_esfera_mesh(eje, 0.42, Vector3(0, -0.2, 0), bronce)
		_cil_mesh(eje, 0.76, 0.1, Vector3(0, -1.28, 0), bronce, Vector3.ZERO, 18)
		_esfera_mesh(eje, 0.14, Vector3(0, -1.2, 0), hierro)
		_caja_mesh(d, Vector3(1.9, 0.18, 0.18), Vector3(0, 0.8, 0), hierro)
		var luz := _luz(d, Vector3(0, -0.2, -1.0), Color(1.0, 0.8, 0.4), 0.0, 6.0)
		_campanas6.append(eje)
		_campana_luz.append(luz)
	# LA CUERDA que baja de la campana mayor hasta el poste: gorda, atada a una argolla en la cabeza del poste y con su
	# agarradera de lana a rayas justo encima, a la altura de la mano (ahi se coge). Antes era un hilo de 3,5 cm que
	# casi no se veia. Al tocar da un tiron (_cuerda_tiron, en todas las maquinas).
	var cu := _v(c["cuerda"])
	var poste := cu + Vector3(0, 1.2, 0)
	var arriba := _v(cp[cp.size() - 1]) + Vector3(0.5, -0.5, -0.3)
	var sube := (arriba - poste).normalized()
	_cuerda_p08_dir = -sube
	_cuerda_p08 = Node3D.new()
	_cuerda_p08.name = "CuerdaEspadana"
	add_child(_cuerda_p08)
	_mnd_tubo(_cuerda_p08, poste, arriba, 0.03, _mm(Color(0.62, 0.52, 0.36), 0.0, 0.9))
	var franjas := [Color(0.72, 0.1, 0.08), Color(0.92, 0.9, 0.84), Color(0.12, 0.22, 0.6)]
	for k in 6:
		var a := poste + sube * (0.06 + k * 0.075)
		_mnd_tubo(_cuerda_p08, a, a + sube * 0.075, 0.055, _mm(franjas[k % 3], 0.0, 1.0))
	var argolla := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.05
	tor.outer_radius = 0.075
	argolla.mesh = tor
	argolla.material_override = _mm(Color(0.12, 0.12, 0.13), 0.8, 0.4)
	add_child(argolla)
	argolla.position = poste + Vector3(0, 0.03, 0)
	_cuerda_p08_mano = poste + sube * 0.28
	# el porton (dos hojas que se abren hacia dentro)
	var po: Array = c["porton"]
	var mn := _mn(po)
	var mx := _mx(po)
	var ancho := (mx.x - mn.x) / 2.0
	var madera := _mm(Color(0.36, 0.24, 0.14), 0.0, 0.85)
	for s in [0, 1]:
		var bisagra := Node3D.new()
		add_child(bisagra)
		bisagra.global_position = Vector3(mn.x if s == 0 else mx.x, mn.y, (mn.z + mx.z) / 2.0)
		var hoja := StaticBody3D.new()
		hoja.collision_layer = 1
		hoja.collision_mask = 0
		bisagra.add_child(hoja)
		hoja.position = Vector3(ancho / 2.0 * (1.0 if s == 0 else -1.0), (mx.y - mn.y) / 2.0, 0)
		_caja_mesh(hoja, Vector3(ancho, mx.y - mn.y, 0.25), Vector3.ZERO, madera)
		for yy in [-1.2, 0.0, 1.2]:
			_caja_mesh(hoja, Vector3(ancho, 0.12, 0.3), Vector3(0, yy, 0), hierro)
		_colision_caja(hoja, Vector3(ancho, mx.y - mn.y, 0.25), Vector3.ZERO)
		_porton6.append(bisagra)
	_porton_barrera = AABB(mn - Vector3(0.2, 0.5, 0.6), (mx - mn) + Vector3(0.4, 1.0, 1.2))
	CriaturaScript.barreras.append(_porton_barrera)
	_rotulo("campanas", "LA ESPADAÑA\nrepetid la melodía disparando a las campanas", _v(cp[0]) + Vector3(5.4, 4.2, -1.0), COLOR_AVISO)
	_rotulo("cuerda", "CUERDA", cu + Vector3(0, 2.0, 0), COLOR_INFO)


func _campana_suena(i: int, color: Color, fuerte: float) -> void:
	if i < 0 or i >= _campanas6.size():
		return
	var eje: Node3D = _campanas6[i]
	if is_instance_valid(eje):
		var tw := eje.create_tween()
		tw.tween_property(eje, "rotation:x", 0.45 * fuerte, 0.25).set_trans(Tween.TRANS_SINE)
		tw.tween_property(eje, "rotation:x", -0.3 * fuerte, 0.45).set_trans(Tween.TRANS_SINE)
		tw.tween_property(eje, "rotation:x", 0.0, 0.6).set_trans(Tween.TRANS_SINE)
		Audio.play3d("gen/campana/c%d" % (i + 1), eje.global_position, 8.0, 0.0, 160.0, Audio.PRI_HIGH)
	var l: OmniLight3D = _campana_luz[i]
	if is_instance_valid(l):
		l.light_color = color
		var tl := l.create_tween()
		tl.tween_property(l, "light_energy", 5.0, 0.1)
		tl.tween_property(l, "light_energy", 0.0, 0.8)


func _p08_toca(ronda: int) -> void:
	var mel: Array = par.get("melodias", [])
	if ronda >= mel.size():
		return
	_tocando = true
	_toque = ronda
	_toque_i = 0
	var notas: Array = mel[ronda]
	_mensaje_local("ESCUCHAD… (ronda %d de %d)" % [ronda + 1, mel.size()])
	for k in notas.size():
		var n := int(notas[k])
		get_tree().create_timer(0.9 + k * 1.0).timeout.connect(func(): _campana_suena(n, Color(1.0, 0.8, 0.4), 1.0))
	get_tree().create_timer(0.9 + notas.size() * 1.0 + 0.3).timeout.connect(func():
		_tocando = false
		_mensaje_local("¡AHORA VOSOTROS! Disparad a las campanas en el mismo orden"))


## (el anfitrion) le han dado a la campana i
func _campana_tiro(i: int) -> void:
	var ahora := Time.get_ticks_msec() * 0.001
	if ahora - float(_campana_ultimo[i]) < 0.55:
		return
	_campana_ultimo[i] = ahora
	var mel: Array = par.get("melodias", [])
	if fase != "p08" or _tocando or _toque >= mel.size():
		_evento("p08_nota", [i, 2])
		return
	var notas: Array = mel[_toque]
	if int(notas[_toque_i]) == i:
		_toque_i += 1
		_evento("p08_nota", [i, 1])
		if _toque_i >= notas.size():
			_toque += 1
			_toque_i = 0
			if _toque >= mel.size():
				get_tree().create_timer(1.0).timeout.connect(func(): _evento("p08", []))
			else:
				_evento("p08_ronda", [_toque])
	else:
		_toque_i = 0
		_evento("p08_nota", [i, 0])
		_horda(8, "¡MAL! Las campanas han llamado a la HORDA · tirad otra vez de la cuerda")


func _p08_resuelto(ya: bool) -> void:
	CriaturaScript.barreras.erase(_porton_barrera)
	for s in _porton6.size():
		var b: Node3D = _porton6[s]
		if not is_instance_valid(b):
			continue
		var fin := (-1.0 if s == 0 else 1.0) * 1.7
		if ya:
			b.rotation.y = fin
		else:
			b.create_tween().tween_property(b, "rotation:y", fin, 3.0).set_trans(Tween.TRANS_SINE)
	if ya:
		return
	for i in _campanas6.size():
		var k := i
		get_tree().create_timer(0.3 * k).timeout.connect(func(): _campana_suena(k, Color(0.4, 1.0, 0.4), 1.4))
	_mensaje_local("¡EL PORTÓN DEL MONASTERIO SE ABRE!")


# ======================================================================================================
# 9. LOS LASERES DEL LABORATORIO
# ======================================================================================================
func _montar_p09() -> void:
	var c := _c("p09_laseres")
	if c.is_empty():
		return
	var rojo := _brillo(Color(1.0, 0.05, 0.03), 4.0)
	rojo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rojo.albedo_color.a = 0.85
	var tipos := ["bajo", "sube", "barre", "alto", "doble"]
	var xs: Array = c["x"]
	for i in xs.size():
		var t: String = tipos[i % tipos.size()]
		var mallas: Array = []
		var n := 2 if t == "doble" else 1
		for k in n:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.03, 0.03, 4.0) if t in ["bajo", "sube", "alto"] else Vector3(0.03, 3.0, 0.03)
			mi.mesh = bm
			mi.material_override = rojo
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			mallas.append(mi)
		_laseres.append({"tipo": t, "x": float(xs[i]), "mallas": mallas})
	var pa: Array = c["pasillo"]
	_laser_ruido = _bucle_directo("res://sounds/gen/laser/zumbido1.ogg", self,
		Vector3((float(pa[0]) + float(pa[2])) / 2.0, M6 + 1.5, (float(pa[1]) + float(pa[3])) / 2.0), -6.0, 22.0)
	# EL PANEL: un armario de laboratorio de pie en el suelo (antes flotaba a 40 cm) con la PALANCA grande en el frente,
	# mirando al este, por donde se llega del pasillo. Arriba, el piloto rojo de "laseres encendidos".
	var panel := _v(c["panel"])
	var pb := _mnd_armario("PanelLaseres", panel, Vector3(1, 0, 0), Vector3(0.62, 1.5, 0.45), Color(0.78, 0.79, 0.8))
	_mnd_laseres = Mandos.crear("palanca", pb, Vector3(0, 1.02, 0.226), Vector3(0, 0, 1), true)
	_baliza_laseres = _cil_mesh(pb, 0.07, 0.12, Vector3(0.18, 1.58, 0), _brillo(Color(1.0, 0.1, 0.05), 2.5), Vector3.ZERO, 12)
	_rotulo("laseres", "LÁSERES · NO LOS TOQUÉIS\n(saltad, agachaos, esperad el hueco)", Vector3(58.0, M6 + 3.2, 72.0), COLOR_PELIGRO)
	_rotulo("panel", "APAGAR LÁSERES", panel + Vector3(0, 2.2, 0), COLOR_INFO)


## Donde esta cada laser ahora (lo mismo en todas las maquinas, con su reloj: solo es para mirar y esquivar)
func _laser_estado(l: Dictionary, t: float) -> Array:
	var pa: Array = _c("p09_laseres")["pasillo"]
	var zc := (float(pa[1]) + float(pa[3])) / 2.0
	match String(l["tipo"]):
		"bajo":
			return [["h", 0.35]]
		"sube":
			return [["h", 0.25 + 1.55 * (0.5 + 0.5 * sin(t * TAU / 3.2))]]
		"barre":
			return [["v", zc + 1.7 * sin(t * TAU / 4.0)]]
		"alto":
			return [["h", 1.25]]
		"doble":
			var s := 0.5 + 0.5 * sin(t * TAU / 3.0)
			return [["v", zc - 1.75 * s], ["v", zc + 1.75 * s]]
	return []


func _laseres_tick(dt: float) -> void:
	if _laseres.is_empty() or not _laseres_on:
		return
	_alarma_cd -= dt
	var t := Time.get_ticks_msec() * 0.001
	var pa: Array = _c("p09_laseres")["pasillo"]
	var zc := (float(pa[1]) + float(pa[3])) / 2.0
	var jp: Vector3 = jugador.global_position if is_instance_valid(jugador) else Vector3.INF
	var cerca := jp.distance_to(Vector3(float(pa[0]) + 13.0, M6, zc)) < 45.0
	var tocado := false
	var agachado := bool(jugador.get("crouching")) if is_instance_valid(jugador) else false
	var arriba := jp.y + (1.12 if agachado else 1.72)
	for l in _laseres:
		var est := _laser_estado(l, t)
		var mallas: Array = l["mallas"]
		for k in est.size():
			var e: Array = est[k]
			var mi: MeshInstance3D = mallas[k]
			mi.visible = cerca
			if String(e[0]) == "h":
				mi.global_position = Vector3(float(l["x"]), M6 + float(e[1]), zc)
				if absf(jp.x - float(l["x"])) < 0.32 and jp.y + 0.06 < M6 + float(e[1]) and arriba > M6 + float(e[1]) and absf(jp.z - zc) < 2.0:
					tocado = true
			else:
				mi.global_position = Vector3(float(l["x"]), M6 + 1.5, float(e[1]))
				if absf(jp.x - float(l["x"])) < 0.32 and absf(jp.z - float(e[1])) < 0.32 and jp.y < M6 + 3.0:
					tocado = true
	if tocado and _alarma_cd <= 0.0 and not bool(jugador.get("spectating")):
		_alarma_cd = 3.0
		if _en_red and not _soy_host:
			Net.net_campana_pide("p09_alarma")
		else:
			_on_pide("p09_alarma", _mi_id())


func _p09_alarma(pid: int) -> void:
	var pa: Array = _c("p09_laseres")["pasillo"]
	var centro := Vector3((float(pa[0]) + float(pa[2])) / 2.0, M6 + 2.5, (float(pa[1]) + float(pa[3])) / 2.0)
	Audio.play3d("gen/laser/alarma", centro, 8.0, 0.0, 90.0, Audio.PRI_TOP)
	var l := _luz(self, centro, Color(1.0, 0.1, 0.05), 6.0, 30.0)
	var tl := l.create_tween()
	for k in 4:
		tl.tween_property(l, "light_energy", 0.0, 0.25)
		tl.tween_property(l, "light_energy", 6.0, 0.25)
	tl.tween_callback(l.queue_free)
	if pid == _mi_id() and is_instance_valid(jugador):
		jugador.global_position = _v(_c("p09_laseres").get("inicio", [58.5, 9, 72])) + Vector3.UP * 0.2
		jugador.velocity = Vector3.ZERO
		if jugador.has_method("take_damage") and not bool(jugador.get("invulnerable")):
			jugador.take_damage(10.0, Vector3.ZERO)
		_mensaje_local("¡ALARMA! Has tocado un láser: vuelta al principio")
	else:
		_mensaje_local("¡ALARMA EN EL LABORATORIO!")


func _laseres_apagar(ya: bool) -> void:
	_laseres_on = false
	_mnd_accionar(_mnd_laseres)
	if is_instance_valid(_baliza_laseres):
		_baliza_laseres.material_override = _mm(Color(0.25, 0.05, 0.04), 0.2, 0.6)
	for l in _laseres:
		for mi in l["mallas"]:
			if is_instance_valid(mi):
				(mi as MeshInstance3D).visible = false
	if is_instance_valid(_laser_ruido):
		_laser_ruido.queue_free()
	if not ya:
		_mensaje_local("¡LÁSERES APAGADOS!")
		Audio.play3d("gen/espejo/receptor", _v(_c("p09_laseres")["panel"]) + Vector3.UP, 2.0, 0.0, 40.0, Audio.PRI_HIGH)


# ======================================================================================================
# 10. LOS ESPEJOS (el laser de estrella guia hasta el receptor de la verja de la estacion)
# ======================================================================================================
func _montar_p10() -> void:
	var c := _c("p10_espejos")
	if c.is_empty():
		return
	var y := float(c.get("y", M6 + 1.4))
	var es: Array = c["espejos"]
	var ini: Array = c.get("inicio", [])
	var marco := _mm(Color(0.2, 0.22, 0.25), 0.6, 0.4)
	var plata := _mm(Color(0.85, 0.88, 0.92), 1.0, 0.05)
	for i in es.size():
		_espejos.append(int(ini[i]) if i < ini.size() else 0)
		var base := Node3D.new()
		add_child(base)
		base.global_position = Vector3(float(es[i][0]), M6 + 0.6, float(es[i][1]))
		_cil_mesh(base, 0.06, 0.8, Vector3(0, 0.4, 0), marco, Vector3.ZERO, 8)
		var cabeza := Node3D.new()
		base.add_child(cabeza)
		cabeza.position = Vector3(0, y - (M6 + 0.6), 0)
		_caja_mesh(cabeza, Vector3(1.2, 1.2, 0.08), Vector3.ZERO, marco)
		_caja_mesh(cabeza, Vector3(1.05, 1.05, 0.1), Vector3(0, 0, 0.0), plata)
		_espejo_nodos.append(cabeza)
		_espejo_refrescar(i, true)
	var ex: Array = c["emisor"]
	var em := _estatico("EmisorLaser", Vector3(float(ex[0]), y, float(ex[1])))
	_cil_mesh(em, 0.35, 1.4, Vector3(0.3, 0, 0), _mm(Color(0.9, 0.9, 0.92), 0.5, 0.4), Vector3(0, 0, PI / 2), 14)
	_cil_mesh(em, 0.2, 0.1, Vector3(-0.42, 0, 0), _brillo(Color(1.0, 0.75, 0.1), 3.0), Vector3(0, 0, PI / 2), 14)
	# EL MANDO DEL EMISOR: un armario estrecho de pie (antes una caja lisa flotando a 40 cm) con el cuadro del
	# interruptor mirando al norte, por donde se llega, y la manguera del cable por el suelo hasta la peana del laser
	var mando := _v(c["mando"])
	var mb := _mnd_armario("MandoEmisor", mando, Vector3(0, 0, 1), Vector3(0.46, 1.3, 0.3))
	_mnd_emisor = Mandos.crear("interruptor", mb, Vector3(0, 0.98, 0.151), Vector3(0, 0, 1), true)
	var cable_mat := _mm(Color(0.06, 0.06, 0.06), 0.1, 0.8)
	_mnd_tubo(self, mando + Vector3(0, 0.04, -0.16), Vector3(float(ex[0]) + 0.82, M6 + 0.04, mando.z - 0.16), 0.035, cable_mat)
	_mnd_tubo(self, Vector3(float(ex[0]) + 0.82, M6 + 0.04, mando.z - 0.16), Vector3(float(ex[0]) + 0.82, M6 + 0.04, float(ex[1])), 0.035, cable_mat)
	var rc: Array = c["receptor"]
	_receptor_luz = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.45
	cm.bottom_radius = 0.45
	cm.height = 0.1
	_receptor_luz.mesh = cm
	_receptor_luz.material_override = _brillo(Color(0.8, 0.05, 0.05), 2.0)
	add_child(_receptor_luz)
	_receptor_luz.global_position = Vector3(float(rc[0]), y, float(rc[1]) + 0.1)
	_receptor_luz.rotation.x = PI / 2
	# la verja de la estacion (una persiana de acero que sube)
	var vj: Array = c["verja"]
	_verja6 = _estatico("VerjaEstacion", _centro(vj))
	var tam := _mx(vj) - _mn(vj)
	_caja_mesh(_verja6, tam, Vector3.ZERO, _mm(Color(0.5, 0.52, 0.55), 0.7, 0.4))
	for k in 5:
		_caja_mesh(_verja6, Vector3(tam.x, 0.08, tam.z + 0.04), Vector3(0, -tam.y / 2.0 + 0.5 + k * 0.8, 0), _mm(Color(0.3, 0.3, 0.32), 0.7, 0.4))
	_colision_caja(_verja6, tam, Vector3.ZERO)
	_verja6_barrera = AABB(_mn(vj) - Vector3(0.3, 0.5, 0.5), tam + Vector3(0.6, 1.0, 1.0))
	CriaturaScript.barreras.append(_verja6_barrera)
	var amarillo := _brillo(Color(1.0, 0.72, 0.1), 5.0)
	amarillo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	amarillo.albedo_color.a = 0.9
	for k in 10:
		var h := _cuerda(amarillo, 0.035)
		h.visible = false
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_haz_mallas.append(h)
	_rotulo("espejos", "ESPEJOS: GIRADLOS\nhasta el RECEPTOR de la verja", Vector3(40.0, M6 + 3.4, 50.0), COLOR_AVISO)
	_rotulo("emisor", "LÁSER DE ESTRELLA GUÍA", mando + Vector3(0, 2.2, 0), COLOR_INFO)


func _espejo_normal(e: int) -> Vector2:
	var a := deg_to_rad(float(posmod(e, 4)) * 45.0)
	return Vector2(cos(a), sin(a))


func _espejo_refrescar(i: int, ya: bool) -> void:
	if i >= _espejo_nodos.size():
		return
	var n: Node3D = _espejo_nodos[i]
	if not is_instance_valid(n):
		return
	var nv := _espejo_normal(int(_espejos[i]))
	var giro := atan2(nv.x, nv.y)
	var actual := n.rotation.y
	var dif := wrapf(giro - actual, -PI / 2, PI / 2)
	if ya:
		n.rotation.y = actual + dif
	else:
		n.create_tween().tween_property(n, "rotation:y", actual + dif, 0.35).set_trans(Tween.TRANS_BACK)
		Audio.play3d("gen/espejo/giro", n.global_position, 0.0, 0.05, 25.0, Audio.PRI_MID)
	_haz_calcular()


## El camino del haz (en el plano: los espejos son de dos caras y el haz rebota en 45 grados)
func _haz_calcular() -> void:
	_haz_puntos.clear()
	_haz_llega = false
	var c := _c("p10_espejos")
	if c.is_empty():
		return
	if _haz_on:
		var y := float(c.get("y", M6 + 1.4))
		var es: Array = c["espejos"]
		var pt: Array = c.get("patio", [4, 38, 56, 62])
		var rc: Array = c["receptor"]
		var rp := Vector2(float(rc[0]), float(rc[1]))
		var ex: Array = c["emisor"]
		var p := Vector2(float(ex[0]) - 0.5, float(ex[1]))
		var d := Vector2(-1, 0)
		var ultimo := -1
		_haz_puntos.append(Vector3(p.x, y, p.y))
		for rebote in 9:
			var mejor := INF
			var cual := -1
			for i in es.size():
				if i == ultimo:
					continue
				var m := Vector2(float(es[i][0]), float(es[i][1]))
				var t := (m - p).dot(d)
				if t < 0.3:
					continue
				if (p + d * t - m).length() < 0.5 and t < mejor:
					mejor = t
					cual = i
			var tr := (rp - p).dot(d)
			if tr > 0.3 and (p + d * tr - rp).length() < 0.6 and tr < mejor:
				_haz_puntos.append(Vector3(rp.x, y, rp.y))
				_haz_llega = true
				break
			if cual < 0:
				# hasta la pared del patio
				var tw := 999.0
				if d.x < -0.01:
					tw = minf(tw, (float(pt[0]) + 0.6 - p.x) / d.x)
				if d.x > 0.01:
					tw = minf(tw, (float(pt[2]) - 0.6 - p.x) / d.x)
				if d.y < -0.01:
					tw = minf(tw, (float(pt[1]) - 0.6 - p.y) / d.y)
				if d.y > 0.01:
					tw = minf(tw, (float(pt[3]) - 0.4 - p.y) / d.y)
				var fin := p + d * maxf(0.0, tw)
				_haz_puntos.append(Vector3(fin.x, y, fin.y))
				break
			p = Vector2(float(es[cual][0]), float(es[cual][1]))
			_haz_puntos.append(Vector3(p.x, y, p.y))
			var n := _espejo_normal(int(_espejos[cual]))
			if absf(d.dot(n)) > 0.05:
				d = (d - 2.0 * d.dot(n) * n).normalized()
				d = Vector2(snappedf(d.x, 0.001), snappedf(d.y, 0.001)).normalized()
			ultimo = cual
	for k in _haz_mallas.size():
		var h: MeshInstance3D = _haz_mallas[k]
		if k + 1 < _haz_puntos.size():
			_linea(h, _haz_puntos[k], _haz_puntos[k + 1])
		else:
			h.visible = false
	if is_instance_valid(_receptor_luz):
		_receptor_luz.material_override = _brillo(Color(0.1, 1.0, 0.25) if (_haz_llega or _h("p10")) else Color(0.8, 0.05, 0.05), 2.5)
	if _soy_host and _haz_llega and not _h("p10"):
		get_tree().create_timer(0.6).timeout.connect(func():
			if not _h("p10"):
				_evento("p10", []))


## El haz quema (a las criaturas, en el anfitrion; y a MI jugador, en cada maquina)
func _haz_tick(dt: float) -> void:
	if not _haz_on or _haz_puntos.size() < 2:
		return
	var jp: Vector3 = jugador.global_position + Vector3.UP * 1.2 if is_instance_valid(jugador) else Vector3.INF
	for k in _haz_puntos.size() - 1:
		var a: Vector3 = _haz_puntos[k]
		var b: Vector3 = _haz_puntos[k + 1]
		var q := Geometry3D.get_closest_point_to_segment(jp, a, b)
		if q.distance_to(jp) < 0.45:
			_dano_local(18.0 * dt, Vector3.ZERO, "¡EL LÁSER QUEMA!")
	if not _soy_host:
		return
	_haz_dano_t -= dt
	if _haz_dano_t > 0.0:
		return
	_haz_dano_t = 0.3
	for cr in _vivos:
		if not is_instance_valid(cr) or bool(cr.get("muerta")):
			continue
		var cp: Vector3 = (cr as Node3D).global_position + Vector3.UP * 1.0
		for k in _haz_puntos.size() - 1:
			var q := Geometry3D.get_closest_point_to_segment(cp, _haz_puntos[k], _haz_puntos[k + 1])
			if q.distance_to(cp) < 0.7 and cr.has_method("take_damage"):
				cr.take_damage(40.0, Vector3.ZERO)
				break


func _p10_resuelto(ya: bool) -> void:
	CriaturaScript.barreras.erase(_verja6_barrera)
	if is_instance_valid(_receptor_luz):
		_receptor_luz.material_override = _brillo(Color(0.1, 1.0, 0.25), 2.5)
	if is_instance_valid(_verja6):
		_sin_colision(_verja6)
		if ya:
			_verja6.global_position.y += 4.0
		else:
			_verja6.create_tween().tween_property(_verja6, "global_position:y", _verja6.global_position.y + 4.0, 3.0).set_trans(Tween.TRANS_SINE)
	if ya:
		return
	var rc: Array = _c("p10_espejos")["receptor"]
	var r := Vector3(float(rc[0]), M6 + 1.6, float(rc[1]))
	Audio.play3d("gen/espejo/receptor", r, 6.0, 0.0, 60.0, Audio.PRI_TOP)
	Audio.bf3d("destru/metal", r + Vector3(-4.0, 1.0, 0), 2.0, 50.0, Audio.PRI_HIGH)
	_corte([[r + Vector3(5.0, 2.5, 8.0), r, 0.0], [r + Vector3(2.0, 1.5, 6.0), r + Vector3(-4.5, 1.0, -1.0), 3.4]], 3.6, "")
	_mensaje_local("¡EL RECEPTOR SE ENCIENDE! La verja de la estación se abre")


# ======================================================================================================
# 11. EL SOPLETE (se lleva y derrite el hielo de la sala de maquinas)
# ======================================================================================================
func _modelo_obj(tipo: String) -> Node3D:
	if tipo != "soplete":
		return super._modelo_obj(tipo)
	var n := Node3D.new()
	var azul := _mm(Color(0.15, 0.3, 0.7), 0.4, 0.5)
	var laton := _mm(Color(0.75, 0.62, 0.3), 0.9, 0.3)
	_cil_mesh(n, 0.1, 0.36, Vector3(0, 0.2, 0.08), azul, Vector3.ZERO, 12)
	_esfera_mesh(n, 0.1, Vector3(0, 0.38, 0.08), azul)
	_cil_mesh(n, 0.025, 0.42, Vector3(0, 0.42, -0.14), laton, Vector3(PI / 2, 0, 0), 8)
	_cil_mesh(n, 0.04, 0.08, Vector3(0, 0.42, -0.36), laton, Vector3(PI / 2, 0, 0), 8)
	var llama := _particulas(n, Vector3(0, 0.42, -0.42), 30, 0.25, Color(0.5, 0.7, 1.0, 0.95), Color(1.0, 0.5, 0.1), 0.12, true)
	llama.direction = Vector3(0, 0, -1)
	llama.spread = 8.0
	llama.initial_velocity_min = 2.0
	llama.initial_velocity_max = 3.5
	llama.gravity = Vector3.ZERO
	llama.emitting = false
	llama.name = "Llama"
	var brillo := OmniLight3D.new()
	brillo.light_color = Color(0.5, 0.7, 1.0)
	brillo.light_energy = 0.6
	brillo.omni_range = 2.0
	brillo.position = Vector3(0, 0.6, 0)
	brillo.name = "Brillo"
	n.add_child(brillo)
	return n


func _montar_p11() -> void:
	var c := _c("p11_soplete")
	if c.is_empty():
		return
	_obj_crear("soplete", "soplete", _v(c["soplete"]) + Vector3(0, 0.96, 0))
	_rotulo("soplete", "SOPLETE", _v(c["soplete"]) + Vector3(0, 2.2, 0), COLOR_INFO)
	var mu: Array = c["muro"]
	_rotulo("hielo_sala", "HIELO: DERRETIDLO\nCON EL SOPLETE", _centro(mu) + Vector3(1.4, 2.4, 0), COLOR_AVISO)


func _hielo_cajas() -> Array:
	var c := _c("p11_soplete")
	var out: Array = [c.get("muro", [])]
	for h in c.get("hielos", []):
		out.append(h)
	return out


## Cada maquina: si el soplete lo llevo YO, la llama sale y cada cuarto de segundo aviso donde da
func _soplete_tick(dt: float) -> void:
	var o: Dictionary = _obj4.get("soplete", {})
	if o.is_empty():
		return
	var n = o.get("nodo")
	var lleva := String(o.get("estado", "")) == "lleva"
	if is_instance_valid(n):
		var ll = (n as Node3D).get_node_or_null("Llama")
		if ll:
			(ll as CPUParticles3D).emitting = lleva
	var mio := lleva and int(o.get("pid", 0)) == _mi_id()
	if mio and not is_instance_valid(_soplete_ruido):
		_soplete_ruido = _bucle_directo("res://sounds/gen/soplete/llama1.ogg", jugador, Vector3(0, 1.4, 0), -4.0, 20.0)
	elif not mio and is_instance_valid(_soplete_ruido):
		_soplete_ruido.queue_free()
		_soplete_ruido = null
	if not mio or not is_instance_valid(jugador) or jugador.get("cam") == null:
		return
	_llama_t -= dt
	if _llama_t > 0.0:
		return
	_llama_t = 0.25
	var cam: Camera3D = jugador.cam
	var p := cam.global_position - cam.global_transform.basis.z * 1.25 - cam.global_transform.basis.y * 0.2
	var accion := "p11_llama:%.2f:%.2f:%.2f" % [p.x, p.y, p.z]
	if _en_red and not _soy_host:
		Net.net_campana_pide(accion)
	else:
		_on_pide(accion, _mi_id())


func _dentro_de(p: Vector3, k: Array, margen: float) -> bool:
	return p.x > float(k[0]) - margen and p.x < float(k[3]) + margen and p.y > float(k[1]) - margen \
		and p.y < float(k[4]) + margen and p.z > float(k[2]) - margen and p.z < float(k[5]) + margen


func _derrite(p: Vector3) -> void:
	if world:
		world.carve_beam(p, Vector3.UP, 0.05, 0.55, 100, true)
	if is_instance_valid(jugador) and jugador.global_position.distance_to(p) < 25.0:
		var v := _particulas(self, p, 12, 1.2, Color(0.9, 0.95, 1.0, 0.6), Color(0.8, 0.85, 0.9), 0.5, false)
		v.one_shot = true
		v.explosiveness = 0.6
		v.direction = Vector3.UP
		v.initial_velocity_min = 0.5
		v.initial_velocity_max = 1.5
		v.gravity = Vector3(0, 1.0, 0)
		get_tree().create_timer(1.5).timeout.connect(v.queue_free)


## (el anfitrion) cuanto queda de cada trozo de hielo
func _hielo_host_check(dt: float) -> void:
	if _h("p11") or fase != "p11" or world == null:
		return
	_hielo_t -= dt
	if _hielo_t > 0.0:
		return
	_hielo_t = 0.5
	var cajas := _hielo_cajas()
	var umbral := float(_c("p11_soplete").get("umbral", 0.3))
	for i in cajas.size():
		if bool(_hielo_libre[i]):
			continue
		var k: Array = cajas[i]
		var mn := Vector3(float(k[0]), float(k[1]) + 0.05, float(k[2]))
		var mx := Vector3(float(k[3]), float(k[4]), float(k[5]))
		var n := int(world.contar_voxels(mn, mx))
		var id := "hielo%d" % i
		if not _llenos.has(id):
			_llenos[id] = n
			continue
		if n <= int(_llenos[id]) * umbral:
			_evento("p11_libre", [i])
	var todos := true
	for l in _hielo_libre:
		if not bool(l):
			todos = false
	if todos:
		_evento("p11", [])


func _p11_resuelto(ya: bool) -> void:
	_rueda_gira = false
	if ya:
		return
	_mensaje_local("¡LA RUEDA ESTÁ LIBRE! Al MANDO del teleférico, junto al andén")
	Audio.bf3d("destru/metal", _v(_c("p12_teleferico").get("rueda", [26, 12, 15])), 2.0, 40.0, Audio.PRI_HIGH)


# ======================================================================================================
# 12. EL TELEFERICO
# ======================================================================================================
func _montar_p12() -> void:
	var c := _c("p12_teleferico")
	if c.is_empty():
		return
	var ru: Array = c["rueda"]
	_rueda = Node3D.new()
	add_child(_rueda)
	_rueda.global_position = Vector3(float(ru[0]), float(ru[1]), float(ru[2]))
	var hierro := _mm(Color(0.2, 0.2, 0.22), 0.8, 0.4)
	var tm := TorusMesh.new()
	tm.inner_radius = float(ru[3]) - 0.35
	tm.outer_radius = float(ru[3])
	var aro := MeshInstance3D.new()
	aro.mesh = tm
	aro.material_override = hierro
	_rueda.add_child(aro)
	for k in 6:
		var r := _caja_mesh(_rueda, Vector3(float(ru[3]) * 2.0, 0.15, 0.2), Vector3.ZERO, hierro)
		r.rotation.y = k * PI / 6.0
	# la CABINA (llega de fuera del mapa por el cable)
	_cabina = _animable("Cabina", _cabina_lejos())
	var rojo := _mm(Color(0.72, 0.1, 0.08), 0.4, 0.45)
	var cristal := _mm(Color(0.12, 0.16, 0.2), 0.8, 0.1)
	var gris := _mm(Color(0.45, 0.46, 0.48), 0.7, 0.4)
	_caja_mesh(_cabina, Vector3(5.0, 0.2, 2.8), Vector3(0, -0.1, 0), gris)
	_caja_mesh(_cabina, Vector3(0.15, 2.6, 2.8), Vector3(-2.45, 1.3, 0), rojo)
	for s in [-1.0, 1.0]:
		_caja_mesh(_cabina, Vector3(5.0, 1.0, 0.12), Vector3(0, 0.5, s * 1.35), rojo)
		_caja_mesh(_cabina, Vector3(4.6, 1.2, 0.1), Vector3(0, 1.6, s * 1.35), cristal)
		_caja_mesh(_cabina, Vector3(5.0, 0.4, 0.12), Vector3(0, 2.4, s * 1.35), rojo)
	_caja_mesh(_cabina, Vector3(5.2, 0.25, 3.0), Vector3(0, 2.7, 0), rojo)
	_caja_mesh(_cabina, Vector3(0.2, 3.6, 0.2), Vector3(0, 4.5, 0), gris)
	_caja_mesh(_cabina, Vector3(2.0, 0.4, 0.5), Vector3(0, 6.4, 0), gris)
	_texto3d("TELEFÉRICO DE LA CUMBRE", Vector3(0, 2.0, 1.42), Color(1, 1, 1), 22, false, _cabina)
	_colision_caja(_cabina, Vector3(5.0, 0.2, 2.8), Vector3(0, -0.1, 0))
	_colision_caja(_cabina, Vector3(0.15, 2.6, 2.8), Vector3(-2.45, 1.3, 0))
	_colision_caja(_cabina, Vector3(5.0, 2.6, 0.12), Vector3(0, 1.3, 1.36))
	_colision_caja(_cabina, Vector3(5.0, 2.6, 0.12), Vector3(0, 1.3, -1.36))
	_colision_caja(_cabina, Vector3(5.2, 0.25, 3.0), Vector3(0, 2.7, 0))
	_cabina.visible = false
	# los cables de fuera del mapa, hasta el valle
	var lejos := _cabina_lejos()
	var cy := float(c.get("cable_y", M6 + 6.6))
	for dz in [-1.6, 1.6]:
		var cab := _cuerda(hierro, 0.06)
		var a := Vector3(0.0, cy, float(c["cabina"][2]) + dz)
		_linea(cab, a, lejos + Vector3(0, cy - M6, dz))
		_cables_fuera.append(cab)
	# la barrera del hueco del cable (el borde del mapa)
	_barrera_cable = _estatico("BarreraCable", Vector3(-0.1, M6 + 3.0, float(c["cabina"][2])))
	_colision_caja(_barrera_cable, Vector3(0.6, 8.0, 9.0), Vector3.ZERO)
	# EL PUPITRE DEL OPERADOR, delante de la ventana de su caseta y mirando al anden: el panel de ARRANQUE (reloj,
	# boton verde gordo) en el tablero inclinado. Antes era una caja flotando a 35 cm con un cubo verde.
	var mando := _v(c["mando"])
	var pu := _mnd_pupitre("MandoTeleferico", mando, Vector3(0, 0, -1), 1.0, Color(0.25, 0.3, 0.26))
	_mnd_teleferico = Mandos.crear("arranque", pu[0], pu[1], pu[2], true)
	_rotulo("teleferico", "MANDO DEL TELEFÉRICO", mando + Vector3(0, 2.3, 0), COLOR_INFO)


func _cabina_lejos() -> Vector3:
	var c := _c("p12_teleferico")
	var cz: float = float(c.get("cabina", [8, 9, 16])[2])
	return Vector3(-240.0, M6 - 70.0, cz)


func _cabina_muelle() -> Vector3:
	return _v(_c("p12_teleferico").get("cabina", [8, 9, 16])) + Vector3(0, 0.05, 0)


func _cabina_tick(dt: float) -> void:
	if is_instance_valid(_rueda) and (_rueda_gira or _cabina_t >= 0.0):
		_rueda.rotation.y += dt * 0.8
	if _cabina_t < 0.0 or not is_instance_valid(_cabina) or _cine_final_corriendo:
		return
	var espera := float(_c("p12_teleferico").get("espera_s", 60.0))
	var antes := _cabina_t
	_cabina_t = minf(espera, _cabina_t + dt)
	var u := _cabina_t / espera
	var e := 1.0 - (1.0 - u) * (1.0 - u) * (1.0 - u) if u > 0.7 else u * 0.95
	_cabina.visible = true
	_cabina.global_position = _cabina_lejos().lerp(_cabina_muelle(), clampf(e, 0.0, 1.0))
	_cabina.rotation.x = sin(_cabina_t * 1.3) * 0.03
	if is_instance_valid(jugador) and fase in ["p12", "subir"] and jugador.global_position.distance_to(_cabina_muelle()) < 40.0:
		_barra_quiero("LA CABINA SUBE · %d s" % int(ceilf(espera - _cabina_t)) if _cabina_t < espera else "¡LA CABINA HA LLEGADO!", u,
			Color(0.95, 0.3, 0.2, 0.95))
	for marca in [0.35, 0.7]:
		if antes < espera * marca and _cabina_t >= espera * marca:
			Audio.play3d("gen/teleferico/pilona", _cabina.global_position, 6.0, 0.0, 200.0, Audio.PRI_HIGH)
	if _soy_host and antes < espera and _cabina_t >= espera and not _h("p12"):
		_evento("p12", [])


func _p12_marcha() -> void:
	_cabina_t = 0.0
	_mnd_accionar(_mnd_teleferico)
	_rueda_gira = true
	var c := _c("p12_teleferico")
	_bucle_directo("res://sounds/gen/teleferico/motor1.ogg", _rueda, Vector3.ZERO, 0.0, 50.0)
	Audio.play3d("gen/ascensor/arranque", _v(c["mando"]), 2.0, 0.0, 60.0, Audio.PRI_HIGH)
	_mensaje_local("¡EL TELEFÉRICO ARRANCA! La cabina viene del otro lado: un minuto · ¡AGUANTAD!")


func _en_cabina(p: Vector3) -> bool:
	var m := _cabina_muelle()
	return absf(p.x - m.x) < 2.4 and absf(p.z - m.z) < 1.3 and p.y > m.y - 0.6 and p.y < m.y + 2.4


# ======================================================================================================
# LA SALIDA DE CINE: la cabina se va por el cable y la estacion vuela a su espalda
# ======================================================================================================
func _cine_final() -> void:
	if _cine_final_hecha or not is_instance_valid(_cabina):
		_cine_final_hecha = true
		return
	_cine_final_corriendo = true
	if is_instance_valid(jugador):
		jugador.set_physics_process(false)
		jugador.set_process_unhandled_input(false)
		var av = jugador.get("avatar")
		if av != null:
			av.visible = false
		for nn in ["weapon_pivot", "fp_arms"]:
			var nd = jugador.get(nn)
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
	if is_instance_valid(_barrera_cable):
		_barrera_cable.queue_free()
	var p0 := _cabina_muelle()
	var fuera := p0 + Vector3(-70.0, -18.0, 0)
	var estacion := Vector3(30.0, M6 + 3.0, 16.0)
	var planos := [[p0 + Vector3(6.0, 3.5, 12.0), p0 + Vector3(0, 1.5, 0), 0.0],
		[p0 + Vector3(-4.0, 5.0, 14.0), p0 + Vector3(-18.0, -2.0, 0), 4.5],
		[p0 + Vector3(-30.0, 2.0, 12.0), estacion, 9.0],
		[p0 + Vector3(-46.0, -6.0, 10.0), fuera + Vector3(-10.0, -6.0, 0), 14.0]]
	_corte(planos, 14.0, "")
	if hud:
		hud.visible = false
	Audio.play3d("gen/teleferico/pilona", p0, 6.0, 0.0, 200.0, Audio.PRI_TOP)
	var tw := _cabina.create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(_cabina, "global_position", fuera, 12.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(_cabina, "rotation:x", 0.08, 3.0)
	# LA ESTACION VUELA: los depositos de gasoil y, en cadena, la sala de maquinas y el anden
	var c := _c("p12_teleferico")
	var dep: Array = c.get("depositos", [])
	var k := 0
	for d in dep:
		var p := _v(d) + Vector3(0, 2.0, 0)
		var kk := k
		get_tree().create_timer(4.0 + kk * 0.5).timeout.connect(func():
			_explosion(p, 5.0, 0.0, 4.5)
			_bola_fuego6(p, 5.0)
			_golpe(p, 3.0, "destru/derrumbe_grave"))
		k += 1
	for q in [Vector3(26.0, M6 + 3.0, 15.0), Vector3(18.0, M6 + 4.0, 12.0), Vector3(40.0, M6 + 2.0, 26.0), Vector3(10.0, M6 + 6.0, 16.0)]:
		var kk := k
		get_tree().create_timer(4.6 + kk * 0.45).timeout.connect(func():
			_explosion(q, 4.0, 0.0, 3.6)
			_bola_fuego6(q, 4.0))
		k += 1
	var capa := CanvasLayer.new()
	capa.layer = 31
	add_child(capa)
	var titulo := Label.new()
	titulo.text = "EPISODIO 6 COMPLETADO"
	titulo.add_theme_font_size_override("font_size", 58)
	titulo.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0))
	titulo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	titulo.add_theme_constant_override("shadow_offset_y", 3)
	titulo.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.grow_horizontal = Control.GROW_DIRECTION_BOTH
	titulo.modulate.a = 0.0
	capa.add_child(titulo)
	var sub := Label.new()
	sub.text = "…y la cumbre arde a vuestra espalda mientras bajáis al otro valle"
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
	tt.tween_interval(9.5)
	tt.tween_property(titulo, "modulate:a", 1.0, 1.4)
	tt.parallel().tween_property(sub, "modulate:a", 1.0, 2.0)
	tt.tween_interval(3.0)
	tt.tween_property(negro, "color:a", 1.0, 1.6)
	tt.tween_callback(func():
		_cine_final_hecha = true
		_cine_final_corriendo = false)


# ======================================================================================================
# AL EMPEZAR
# ======================================================================================================
func _al_empezar() -> void:
	Audio.bf2d("amb/radio", -4.0, Audio.PRI_MID)
	_mensaje_local("RADIO: «…estación de esquí de la cumbre. El TELEFÉRICO baja al otro valle. Si alguien nos oye: SUBID»")
	if not _soy_host:
		Net.net_campana_pide("estado4")
	elif _en_red:
		_mandar_estado()
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--ir="):
			_ir_a(String(a).substr(5).replace("_", " "))
	if "--cumbre6test" in OS.get_cmdline_user_args():
		_prueba6()
	if "--cumbre6btest" in OS.get_cmdline_user_args():
		_prueba6b()


## --cumbre6test (con --ir=barranco): la avalancha, el soplete, el teleferico y la salida, sin jugar
func _prueba6() -> void:
	await get_tree().create_timer(2.0).timeout
	jugador.set("invulnerable", true)
	print("[cumbre6test] inicio · terminado %s · vida %s · fase %s" % [str(terminado), str(jugador.get("health")), fase])
	var r: Array = _c("p06_alud").get("relleno", [108.6, 5.2, 125.4, 16.8])
	var antes := int(world.contar_voxels(Vector3(float(r[0]), 6.0, float(r[1])), Vector3(float(r[2]), M6, float(r[3]))))
	for i in 3:
		_diana_host("gazex%d" % i, 500.0)
		await get_tree().create_timer(0.5).timeout
	await get_tree().create_timer(12.0).timeout
	var despues := int(world.contar_voxels(Vector3(float(r[0]), 6.0, float(r[1])), Vector3(float(r[2]), M6, float(r[3]))))
	print("[cumbre6test] avalancha · p06 %s · relleno %d -> %d voxels · fase %s" % [str(_h("p06")), antes, despues, fase])
	# al hielo de la sala de maquinas, con el soplete en la mano
	await _ir_a("sala de maquinas")
	await get_tree().create_timer(1.5).timeout
	print("[cumbre6test] en la sala · vida %s · pos %s · llenos %s" % [str(jugador.get("health")), str(jugador.global_position), str(_llenos)])
	_evento("obj4", ["soplete", "lleva", _mi_id(), 0.0, 0.0, 0.0])
	for k in _hielo_cajas():
		var mn := Vector3(float(k[0]), float(k[1]), float(k[2]))
		var mx := Vector3(float(k[3]), float(k[4]), float(k[5]))
		var x := mn.x + 0.3
		while x < mx.x:
			var z := mn.z + 0.3
			while z < mx.z:
				var y := mn.y + 0.3
				while y < mx.y:
					_pide_extra("p11_llama:%.2f:%.2f:%.2f" % [x, y, z])
					y += 0.7
				z += 0.7
			x += 0.7
	await get_tree().create_timer(2.0).timeout
	var cuenta: Array = []
	for k in _hielo_cajas():
		cuenta.append(int(world.contar_voxels(Vector3(float(k[0]), float(k[1]) + 0.05, float(k[2])), Vector3(float(k[3]), float(k[4]), float(k[5])))))
	print("[cumbre6test] voxels de hielo ahora %s · vida %s" % [str(cuenta), str(jugador.get("health"))])
	print("[cumbre6test] soplete · hielo %s · p11 %s · fase %s" % [str(_hielo_libre), str(_h("p11")), fase])
	# el teleferico (con la espera corta)
	_c("p12_teleferico")["espera_s"] = 4.0
	await _ir_a("anden")
	await get_tree().create_timer(1.0).timeout
	_pide_extra("p12_marcha")
	await get_tree().create_timer(6.0).timeout
	print("[cumbre6test] cabina · p12 %s · fase %s · t %.1f · espera %s · vida %s · terminado %s · pos %s" % [str(_h("p12")), fase, _cabina_t, str(_c("p12_teleferico").get("espera_s")), str(jugador.get("health")), str(terminado), str(jugador.global_position)])
	if is_instance_valid(jugador):
		jugador.global_position = _cabina_muelle() + Vector3(0, 0.3, 0)
	for b in get_tree().get_nodes_in_group("aliados_pve"):
		if is_instance_valid(b):
			(b as Node3D).global_position = _cabina_muelle() + Vector3(1.0, 0.3, 0.4)
	await get_tree().create_timer(4.0).timeout
	print("[cumbre6test] a bordo: %s · fase %s · terminado %s" % [str(_en_cabina(jugador.global_position)), fase, str(terminado)])
	await get_tree().create_timer(17.0).timeout
	print("[cumbre6test] fin · cine hecha %s" % str(_cine_final_hecha))
	get_tree().quit()


## --cumbre6btest: los puzzles de en medio, uno detras de otro y sin jugar (el hielo y el Tank, la mina, la escolta
## de la quitanieves, el robot, las campanas, los laseres y los espejos). Es para ver que no se rompe nada.
func _prueba6b() -> void:
	jugador.set("invulnerable", true)
	await get_tree().create_timer(2.0).timeout
	# 1-2 el hielo y el Tank
	var lago: Array = _c("p01_hielo")["lago"]
	var pl := float(_c("p01_hielo").get("placa", 4.0))
	var x0 := float(lago[0]) + 15 * pl
	var z0 := float(lago[1]) + 5 * pl
	var antes := int(world.contar_voxels(Vector3(x0, 2.6, z0), Vector3(x0 + pl, 3.1, z0 + pl)))
	_pide_extra("hielo:15,5")
	await get_tree().create_timer(0.5).timeout
	var despues := int(world.contar_voxels(Vector3(x0, 2.6, z0), Vector3(x0 + pl, 3.1, z0 + pl)))
	print("[cumbre6btest] placa 15,5 · %d -> %d voxels" % [antes, despues])
	progreso = _indice_de("mitad del lago")
	await get_tree().create_timer(1.5).timeout
	print("[cumbre6btest] fase %s · tank %s" % [fase, str(is_instance_valid(_tank6))])
	if is_instance_valid(_tank6):
		(_tank6 as Node3D).global_position = _placa_centro("13,5") + Vector3.UP * 0.5
	await get_tree().create_timer(6.0).timeout
	print("[cumbre6btest] tank hundido %s · p02 %s · fase %s" % [str(_tank_hundido), str(_h("p02")), fase])
	# 3 la mina: extractor, puerta y bombona
	_c("p03_grisu")["arranque_s"] = 2.0
	await _ir_a("ventilador")
	_pide_extra("grisu_chispa")
	await get_tree().create_timer(1.0).timeout
	print("[cumbre6btest] chispa · grisu %d · fase %s" % [_grisu, fase])
	_pide_extra("p03_ventilador")
	await get_tree().create_timer(3.5).timeout
	print("[cumbre6btest] extractor · puerta %s · p03 %s" % [str(_puerta_abierta), str(_h("p03"))])
	# otra vez con gas (para ver la voladura de verdad)
	hecho.erase("p03")
	_grisu = 2
	_diana_host("grisu", 50.0)
	await get_tree().create_timer(6.0).timeout
	var t: Array = (_c("p03_grisu")["tramos"] as Array).back()
	print("[cumbre6btest] mina volada · p03 %s · escombro %d voxels" % [str(_h("p03")),
		int(world.contar_voxels(Vector3(float(t[0]), G6, float(t[1]) + 1.0), Vector3(float(t[2]), G6 + 3.0, float(t[3]))))])
	# 4 la quitanieves hasta el derrumbe (deprisa y con escolta)
	await _ir_a("patio de la mina")
	_c("p04_quitanieves")["v"] = 9.0
	_pide_extra("p04_arrancar")
	var v1: Array = _c("p04_quitanieves")["ventisqueros"][0]
	var nv0 := int(world.contar_voxels(Vector3(float(v1[0]), 3.3, float(v1[1])), Vector3(float(v1[2]), 7.0, float(v1[3]))))
	for k in 60:
		await get_tree().create_timer(0.5).timeout
		if is_instance_valid(_qn):
			jugador.global_position = _qn.global_position - _qn.global_transform.basis.x * 3.0 + Vector3.UP * 0.6
		for cr in _vivos:
			if is_instance_valid(cr) and cr.has_method("take_damage"):
				cr.take_damage(99999.0, Vector3.ZERO)
		if _qn_estado == 4:
			break
	var nv1 := int(world.contar_voxels(Vector3(float(v1[0]), 3.3, float(v1[1])), Vector3(float(v1[2]), 7.0, float(v1[3]))))
	print("[cumbre6btest] quitanieves · estado %d · s %.1f de %.1f · ventisquero 1 %d -> %d · fase %s" % [_qn_estado, _qn_s, _qn_largo, nv0, nv1, fase])
	# 5 el robot por el laberinto
	await get_tree().create_timer(1.0).timeout
	jugador.global_position = _v(_c("p05_robot")["consola"]) + Vector3(-1.0, 0.4, -1.0)
	var ordenes := ["p05_avanza", "p05_avanza", "p05_avanza", "p05_avanza", "p05_der", "p05_avanza", "p05_avanza", "p05_avanza",
		"p05_avanza", "p05_izq", "p05_avanza", "p05_avanza", "p05_avanza", "p05_izq", "p05_avanza", "p05_der", "p05_avanza"]
	for o in ordenes:
		_pide_extra(o)
		await get_tree().create_timer(0.3).timeout
	print("[cumbre6btest] robot · celda %s · carga %s · fase %s" % [str(_robot_celda), str(_robot_carga), fase])
	_pide_extra("p05_detonar")
	await get_tree().create_timer(6.0).timeout
	var dz: Array = _c("p05_robot")["derrumbe"]
	print("[cumbre6btest] derrumbe · p05 %s · roca que queda %d · fase %s" % [str(_h("p05")),
		int(world.contar_voxels(Vector3(float(dz[0]), 8.0, float(dz[2])), Vector3(float(dz[3]), 11.5, float(dz[5])))), fase])
	for k in 60:
		await get_tree().create_timer(0.5).timeout
		if is_instance_valid(_qn):
			jugador.global_position = _qn.global_position - _qn.global_transform.basis.x * 3.0 + Vector3.UP * 0.6
		if _qn_estado == 5:
			break
	await get_tree().create_timer(1.0).timeout
	print("[cumbre6btest] quitanieves en el barranco · estado %d · p04 %s · fase %s" % [_qn_estado, str(_h("p04")), fase])
	# 7 un puente falso y un brasero
	_pide_extra("falso:0,0")
	_pide_extra("p07_b1")
	await get_tree().create_timer(0.5).timeout
	print("[cumbre6btest] falsos %s · braseros %s" % [str(_falsos_rotos.keys()), str(_braseros)])
	# 8 las campanas
	await _ir_a("espadaña")
	var mel: Array = par.get("melodias", [])
	for r in mel.size():
		_pide_extra("p08_cuerda")
		await get_tree().create_timer(0.9 + (mel[r] as Array).size() * 1.0 + 0.8).timeout
		for n in mel[r]:
			_diana_host("campana%d" % int(n), 30.0)
			await get_tree().create_timer(0.7).timeout
		await get_tree().create_timer(0.5).timeout
	await get_tree().create_timer(1.5).timeout
	print("[cumbre6btest] campanas · p08 %s · fase %s" % [str(_h("p08")), fase])
	# 9 los laseres
	await _ir_a("patio del laboratorio")
	_pide_extra("p09_alarma")
	await get_tree().create_timer(0.5).timeout
	_pide_extra("p09_panel")
	await get_tree().create_timer(0.5).timeout
	print("[cumbre6btest] laseres · p09 %s · encendidos %s · fase %s" % [str(_h("p09")), str(_laseres_on), fase])
	# 10 los espejos
	await _ir_a("patio de los espejos")
	_pide_extra("p10_on")
	for e in ["p10_e0", "p10_e1", "p10_e1", "p10_e1", "p10_e2", "p10_e2", "p10_e2"]:
		_pide_extra(e)
		await get_tree().create_timer(0.2).timeout
	await get_tree().create_timer(2.0).timeout
	print("[cumbre6btest] espejos %s · haz %s · llega %s · p10 %s · fase %s" % [str(_espejos), str(_haz_puntos.size()), str(_haz_llega), str(_h("p10")), fase])
	await get_tree().create_timer(4.0).timeout
	print("[cumbre6btest] fin · vida %s" % str(jugador.get("health")))
	get_tree().quit()


func _ir_a(nombre: String) -> void:
	var i := _indice_de(nombre)
	if i >= ruta.size() or not _soy_host:
		return
	hecho["p01"] = true
	var orden := [["p02", "orilla este"], ["p03", "patio de la mina"], ["p05", "tras el derrumbe"], ["p04", "barranco"],
		["p06", "puente de nieve"], ["p07", "espadaña"], ["p08", "claustro"], ["p09", "sala de control"],
		["p10", "estacion"], ["p11", "sala de maquinas"]]
	for po in orden:
		if i > _indice_de(String(po[1])) or (String(po[0]) in ["p02", "p03", "p05", "p04", "p07"] and i >= _indice_de(String(po[1]))):
			if String(po[0]) == "p04":
				hecho["p04"] = true
				_qn_s = _qn_largo
				_qn_s_vista = _qn_s
				_qn_estado = 5
			elif String(po[0]) == "p07":
				hecho["p07"] = true
			elif String(po[0]) == "p11":
				for k in _hielo_libre.size():
					_hielo_libre[k] = true
				_resolver6("p11", true)
			else:
				_resolver6(String(po[0]), true)
	progreso = i
	fase = _fase_por_hecho6()
	await get_tree().create_timer(0.5).timeout
	if is_instance_valid(jugador):
		jugador.set_physics_process(false)
		jugador.global_position = ruta[i] + Vector3.UP * 0.4
		jugador.velocity = Vector3.ZERO
		await get_tree().create_timer(1.5).timeout
		if is_instance_valid(jugador):
			jugador.global_position = ruta[i] + Vector3.UP * 0.4
			jugador.set_physics_process(true)
	for b in get_tree().get_nodes_in_group("aliados_pve"):
		if is_instance_valid(b) and b.has_method("teletransportar_a"):
			b.teletransportar_a(jugador)
	if _en_red:
		_mandar_estado()
	print("[campana6] --ir=%s: fase %s" % [nombre, fase])


func _fase_por_hecho6() -> String:
	if not _h("p02"):
		return "p01" if progreso < _indice_de("mitad del lago") else "p02"
	if not _h("p03"):
		return "p03"
	if not _h("p05"):
		return "p04" if _qn_estado != 4 else "p05"
	if not _h("p04"):
		return "p04b"
	if not _h("p06"):
		return "p06"
	if not _h("p07"):
		return "p07"
	if not _h("p08"):
		return "p08"
	if progreso < _indice_de("patio del laboratorio"):
		return "camino_refugio"
	for k in ["p09", "p10", "p11", "p12"]:
		if not _h(k):
			return k
	return "subir"


# ======================================================================================================
# CADA CUADRO
# ======================================================================================================
var _barra_pide: Array = []


## La barra la pide quien quiera; la primera peticion del cuadro gana
func _barra_quiero(t: String, v: float, c: Color) -> void:
	if _barra_pide.is_empty():
		_barra_pide = [t, v, c]


func _process_sin_medir(dt: float) -> void:
	super._process_sin_medir(dt)
	_barra_pide = []
	_rotulos_tick(dt)
	_avion_tick(dt)
	_hielo_tick(dt)
	_grisu_tick(dt)
	_ventilador_tick(dt)
	_qn_tick(dt)
	_robot_tick(dt)
	_ventisca_tick(dt)
	_laseres_tick(dt)
	_haz_tick(dt)
	_soplete_tick(dt)
	_cabina_tick(dt)
	_mnd_tick()
	if _barra_pide.is_empty():
		_barra("", 0.0, Color.WHITE)
	else:
		_barra(String(_barra_pide[0]), float(_barra_pide[1]), _barra_pide[2])
	if (_en_red and not _soy_host) or terminado or world == null:
		return
	_hielo_host_tick(dt)
	_qn_host_tick(dt)
	_hielo_host_check(dt)
	_final_tick6(dt)
	_obj_revisar()
	_bots_t -= dt
	if _bots_t <= 0.0:
		_bots_t = 2.0
		_bots_al_dia()
	_comprobar_t6 -= dt
	if _comprobar_t6 > 0.0:
		return
	_comprobar_t6 = 0.3
	# el Tank tambien puede caer a tiros
	if fase == "p02" and not _h("p02") and (not is_instance_valid(_tank6) or bool(_tank6.get("muerta"))) and not _tank_hundido:
		_evento("p02", [])
	if fase == "p07" and progreso >= _indice_de("espadaña"):
		hecho["p07"] = true


func _final_tick6(dt: float) -> void:
	if fase == "p12" or fase == "subir":
		_tanda_final6 -= dt
		if _tanda_final6 <= 0.0:
			_tanda_final6 = 10.0
			if _cola.size() < 8:
				_horda(9, "")
		if not _final_tank6 and _cabina_t >= 0.0:
			_final_tank6 = true
			_cola.push_front("tanque")
			_mensaje("¡UN TANK SUBE POR LA ESTACIÓN!")


# ======================================================================================================
# LA HISTORIA (el anfitrion)
# ======================================================================================================
const TEXTOS6 := {
	"p01": "EL LAGO HELADO · cruzad por el hielo BLANCO: el OSCURO cruje y se rompe (y el agua mata de frío)",
	"p02": "¡UN TANK! A tiros casi no cae: llevadlo al HIELO FINO, que no aguanta su peso",
	"p03": "LA MINA · lleva GRISÚ: NO DISPARÉIS dentro. Encended el EXTRACTOR del fondo",
	"p04": "LA QUITANIEVES · arrancadla y escoltadla: su pala abre los ventisqueros",
	"p05": "EL DERRUMBE · el ROBOT de los TEDAX: conducidlo por el hueco desde la furgoneta",
	"p04b": "LA QUITANIEVES sigue · escoltadla hasta el barranco",
	"p06": "EL BARRANCO · el puente ya no está. Disparad a los tres GAZEX de la CORNISA",
	"p07": "LA VENTISCA · BRASEROS para el frío, cuidado con los PUENTES DE NIEVE, seguid la CAMPANA",
	"p08": "EL MONASTERIO · tirad de la CUERDA y repetid la melodía disparando a las CAMPANAS",
	"camino_refugio": "¡El portón se abre! Al REFUGIO: el refectorio, a la izquierda",
	"p09": "EL LABORATORIO · pasad los LÁSERES sin tocarlos; el primero que llegue, que los APAGUE",
	"p10": "LOS ESPEJOS · encended el LÁSER y girad los ESPEJOS hasta el RECEPTOR de la verja",
	"p11": "LA ESTACIÓN · coged el SOPLETE del taller y derretid el HIELO de la sala de máquinas",
	"p12": "EL TELEFÉRICO · ponedlo en marcha: la cabina tarda un minuto en subir. ¡AGUANTAD!",
	"subir": "¡TODOS A LA CABINA!",
}


func _historia() -> void:
	match fase:
		"inicio":
			_poner_fase("p01", TEXTOS6["p01"])
		"p01":
			if progreso >= _indice_de("mitad del lago"):
				_poner_fase("p02", TEXTOS6["p02"])
				_p02_sale_tank()
		"p02":
			if _h("p02"):
				_poner_fase("p03", TEXTOS6["p03"])
		"p03":
			if _h("p03"):
				_poner_fase("p04", TEXTOS6["p04"])
		"p04":
			if _qn_estado == 4:
				_poner_fase("p05", TEXTOS6["p05"])
		"p05":
			if _h("p05"):
				_poner_fase("p04b", TEXTOS6["p04b"])
				get_tree().create_timer(3.5).timeout.connect(func(): _evento("p04_estado", [_qn_s, 1]))
		"p04b":
			if _qn_estado == 5:
				hecho["p04"] = true
				_poner_fase("p06", TEXTOS6["p06"])
		"p06":
			if _h("p06"):
				_poner_fase("p07", TEXTOS6["p07"])
		"p07":
			if _h("p07"):
				_poner_fase("p08", TEXTOS6["p08"])
		"p08":
			if _h("p08"):
				_poner_fase("camino_refugio", TEXTOS6["camino_refugio"])
				_horda(HORDA_TAM, "¡LAS CAMPANAS HAN DESPERTADO A TODA LA MONTAÑA!")
			else:
				var mel: Array = par.get("melodias", [])
				_texto = "%s · ronda %d de %d" % [TEXTOS6["p08"], mini(_toque + 1, mel.size()), mel.size()]
		"camino_refugio":
			var ref: Dictionary = _c("refugio")
			if not ref.is_empty() and _todos_dentro(ref["rect"], float(ref.get("suelo", 0.0)) - 1.0):
				_poner_fase("refugio", "")
				_llegar_al_refugio()
		"refugio":
			if progreso >= _indice_de("patio del laboratorio"):
				_poner_fase("p09", TEXTOS6["p09"])
		"p09":
			if _h("p09"):
				_poner_fase("p10", TEXTOS6["p10"])
		"p10":
			if _h("p10"):
				_poner_fase("p11", TEXTOS6["p11"])
		"p11":
			if _h("p11"):
				_poner_fase("p12", TEXTOS6["p12"])
			else:
				var n := 0
				for l in _hielo_libre:
					if bool(l):
						n += 1
				_texto = "%s · %d de 4" % [TEXTOS6["p11"], n]
		"p12":
			if _h("p12"):
				_poner_fase("subir", TEXTOS6["subir"])
		"subir":
			var vivos := _jugadores_vivos()
			var dentro := 0
			for pl in vivos:
				if _en_cabina((pl as Node3D).global_position):
					dentro += 1
			_texto = "¡TODOS A LA CABINA! · %d de %d dentro" % [dentro, vivos.size()]
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
			return [sig.call("orilla este"), "ORILLA ESTE"]
		"p02":
			if is_instance_valid(_tank6):
				return [(_tank6 as Node3D).global_position + Vector3.UP * 3.0, "TANK · AL HIELO FINO"]
			return [sig.call("boca de la mina"), "MINA"]
		"p03":
			if _vent_t < 0.0 and not _puerta_abierta:
				return [_v(_c("p03_grisu")["mando"]) + Vector3.UP, "EXTRACTOR · SIN DISPARAR"]
			if not _puerta_abierta:
				return [_v(_c("p03_grisu")["mando"]) + Vector3.UP, "EL EXTRACTOR ARRANCA…"]
			return [_v(_c("p03_grisu")["bombona"]) + Vector3.UP, "BOMBONA · DESDE FUERA"]
		"p04", "p04b":
			if is_instance_valid(_qn):
				return [_qn.global_position + Vector3.UP * 4.5, "QUITANIEVES" if _qn_estado != 0 else "ARRANCAR LA QUITANIEVES"]
		"p05":
			if _robot_carga:
				return [_v(_c("p05_robot")["consola"]) + Vector3.UP, "¡DETONAR!"]
			return [_v(_c("p05_robot")["consola"]) + Vector3.UP, "CONSOLA DEL ROBOT"]
		"p06":
			for i in _gazex.size():
				if not bool(_gazex[i]):
					return [_gazex_pos[i], "GAZEX %d" % (i + 1)]
		"p07":
			return [sig.call("espadaña"), "LA CAMPANA"]
		"p08":
			return [_v(_c("p08_campanas")["cuerda"]) + Vector3.UP, "CUERDA DE LA CAMPANA"]
		"camino_refugio":
			return [sig.call("refugio"), "REFUGIO"]
		"refugio":
			var ps = _c("refugio").get("puerta_salida", null)
			return [_v([ps[0], M6, ps[1]]) if ps != null else ruta[progreso], "SALIDA DEL REFUGIO"]
		"p09":
			return [_v(_c("p09_laseres")["panel"]) + Vector3.UP, "PANEL DE LOS LÁSERES"]
		"p10":
			if not _haz_on:
				return [_v(_c("p10_espejos")["mando"]) + Vector3.UP, "LÁSER DE ESTRELLA GUÍA"]
			var rc: Array = _c("p10_espejos")["receptor"]
			return [Vector3(float(rc[0]), M6 + 1.6, float(rc[1])), "RECEPTOR"]
		"p11":
			var o: Dictionary = _obj4.get("soplete", {})
			if not o.is_empty() and String(o["estado"]) != "lleva":
				return [(o["pos"] as Vector3) + Vector3.UP, "SOPLETE"]
			var cajas := _hielo_cajas()
			for i in cajas.size():
				if not bool(_hielo_libre[i]):
					return [_centro(cajas[i]), "HIELO"]
		"p12":
			if _cabina_t < 0.0:
				return [_v(_c("p12_teleferico")["mando"]) + Vector3.UP, "MANDO DEL TELEFÉRICO"]
			return [_cabina_muelle() + Vector3.UP * 2.0, "ANDÉN · AGUANTAD"]
		"subir":
			return [_cabina_muelle() + Vector3.UP * 1.5, "¡A LA CABINA!"]
	return [Vector3.INF, ""]


func _tope_ruta() -> int:
	var cierres := [["p03", "patio de la mina"], ["p05", "derrumbe"], ["p04", "barranco"], ["p06", "puente de nieve"],
		["p08", "claustro"], ["p09", "sala de control"], ["p10", "estacion"], ["p11", "anden"]]
	for c in cierres:
		if not _h(String(c[0])):
			return _indice_de(String(c[1]))
	return 999


# ======================================================================================================
# LOS MANDOS (mandos.gd): los armarios y pupitres donde van, y su piloto siguiendo al estado
# ======================================================================================================
## Un armario de chapa de pie en el suelo (zocalo, tejadillo y rejilla), con el frente hacia `normal`: +Z local, en
## z = tam.z / 2. `suelo`: el pie. Los mandos van atornillados al frente con Mandos.crear(..., local = true).
func _mnd_armario(nombre: String, suelo: Vector3, normal: Vector3, tam: Vector3, color := Color(0.33, 0.36, 0.38)) -> StaticBody3D:
	var sb := _estatico(nombre, suelo)
	sb.basis = Basis.looking_at(-Vector3(normal.x, 0.0, normal.z).normalized(), Vector3.UP)
	var oscuro := _mm(Color(0.07, 0.07, 0.08), 0.3, 0.8)
	_caja_mesh(sb, tam, Vector3(0, tam.y * 0.5, 0), _mm(color, 0.45, 0.55))
	_caja_mesh(sb, Vector3(tam.x + 0.04, 0.1, tam.z + 0.04), Vector3(0, 0.05, 0), oscuro)
	_caja_mesh(sb, Vector3(tam.x + 0.06, 0.04, tam.z + 0.08), Vector3(0, tam.y + 0.02, 0.01), _mm(color.darkened(0.3), 0.5, 0.5))
	for i in 3:
		_caja_mesh(sb, Vector3(tam.x * 0.6, 0.018, 0.01), Vector3(0, 0.2 + i * 0.045, tam.z * 0.5 + 0.004), oscuro)
	_colision_caja(sb, tam, Vector3(0, tam.y * 0.5, 0))
	return sb


## Un pupitre de operador de pie en el suelo, con el tablero inclinado hacia quien se pone delante (`normal`).
## Devuelve [nodo, centro del tablero, normal del tablero] (en el espacio del pupitre) para Mandos.crear(..., true).
func _mnd_pupitre(nombre: String, suelo: Vector3, normal: Vector3, ancho: float, color := Color(0.33, 0.36, 0.38)) -> Array:
	var sb := _estatico(nombre, suelo)
	sb.basis = Basis.looking_at(-Vector3(normal.x, 0.0, normal.z).normalized(), Vector3.UP)
	var chapa := _mm(color, 0.45, 0.55)
	_caja_mesh(sb, Vector3(ancho, 0.95, 0.6), Vector3(0, 0.475, 0), chapa)
	_caja_mesh(sb, Vector3(ancho + 0.04, 0.1, 0.64), Vector3(0, 0.05, 0), _mm(Color(0.07, 0.07, 0.08), 0.3, 0.8))
	_caja_mesh(sb, Vector3(ancho, 0.26, 0.1), Vector3(0, 1.08, -0.25), chapa)            # el respaldo del tablero
	_caja_mesh(sb, Vector3(ancho, 0.09, 0.3), Vector3(0, 0.995, -0.15), chapa)
	var a := 0.55
	var tablero := _caja_mesh(sb, Vector3(ancho + 0.02, 0.05, 0.56), Vector3(0, 1.05, 0), _mm(color.darkened(0.35), 0.4, 0.6))
	tablero.rotation.x = a
	_colision_caja(sb, Vector3(ancho, 1.1, 0.6), Vector3(0, 0.55, 0))
	var n := Vector3(0, cos(a), sin(a))
	return [sb, Vector3(0, 1.05, 0) + n * 0.026, n]


## Un mando que va DE PIE sobre algo (detonador, filtros), con el frente hacia `hacia` (en el espacio de `padre`).
## mandos.gd monta esos dos con la caja del reves (medido: el embolo quedaba COLGANDO por debajo de la mesa); aqui
## se endereza, y si algun dia se arregla alli, esto ya no hace nada.
func _mnd_de_pie(tipo: String, padre: Node, pos: Vector3, hacia: Vector3) -> Node3D:
	var base := Node3D.new()
	base.name = "Base_" + tipo
	padre.add_child(base)
	base.transform = Transform3D(Basis.looking_at(Vector3(hacia.x, 0.0, hacia.z).normalized(), Vector3.UP), pos)
	var m := Mandos.crear(tipo, base, Vector3.ZERO, Vector3.UP, true)
	if m.get_child_count() > 0 and m.get_child(0) is Node3D:
		var cuerpo := m.get_child(0) as Node3D
		if (m.transform.basis * cuerpo.transform.basis).y.y < 0.0:
			cuerpo.rotation.x = PI * 0.5
	return m


## El piloto sigue al estado, pero solo se toca si cambia (si no, el ambar no late). Si ya esta HECHO y aqui nadie
## lo ha accionado (el que entra tarde, el estado que llega), se acciona: la palanca baja, el embolo se hunde...
func _mnd_luz(m, estado: String) -> void:
	if not is_instance_valid(m) or not (m is Node3D) or String(m.get_meta("luz", "")) == estado:
		return
	m.set_meta("luz", estado)
	if estado == "hecho" and not bool(m.get_meta("accionado", false)):
		m.set_meta("accionado", true)
		Mandos.accionar(m)
	else:
		Mandos.piloto(m, estado)


## El gesto de usarlo (en todas las maquinas: se llama desde el evento) y el piloto a verde
func _mnd_accionar(m) -> void:
	if not is_instance_valid(m) or not (m is Node3D):
		return
	m.set_meta("accionado", true)
	m.set_meta("luz", "hecho")
	Mandos.accionar(m)


## Donde sale el boton de un mando (un punto en su espacio: +Z hacia fuera). Sin mando, `si_no`.
func _mnd_donde(m, local: Vector3, si_no: Vector3) -> Vector3:
	if is_instance_valid(m) and m is Node3D and (m as Node3D).is_inside_tree():
		return (m as Node3D).to_global(local)
	return si_no


## Un cilindro de `a` a `b` (en el espacio de `padre`): cables, tubos, cuerdas
func _mnd_tubo(padre: Node, a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var mi := _cil_mesh(padre, r, maxf(0.01, a.distance_to(b)), (a + b) * 0.5, mat, Vector3.ZERO, 8)
	var d := (b - a).normalized()
	var eje := Vector3.UP.cross(d)
	if eje.length() > 0.0001:
		mi.basis = Basis(eje.normalized(), Vector3.UP.angle_to(d))
	elif d.y < 0.0:
		mi.basis = Basis(Vector3.RIGHT, PI)
	return mi


## Los pilotos de este episodio siguiendo al estado (cada fotograma y en todas las maquinas)
func _mnd_tick() -> void:
	_mnd_luz(_mnd_extractor, "hecho" if (_vent_t >= 0.0 or _puerta_abierta) else ("apagado" if _h("p03") else "espera"))
	for id in ["p05_izq", "p05_avanza", "p05_der"]:
		_mnd_luz(_mnd_p05.get(id), "apagado" if _h("p05") else "espera")
	_mnd_luz(_mnd_p05.get("p05_detonar"), "hecho" if _h("p05") else ("espera" if _robot_carga else "apagado"))
	_mnd_luz(_mnd_laseres, "espera" if _laseres_on else "hecho")
	_mnd_luz(_mnd_emisor, "hecho" if (_haz_on or _h("p10")) else "espera")
	_mnd_luz(_mnd_teleferico, "hecho" if _cabina_t >= 0.0 else ("espera" if _h("p11") else "apagado"))


## La tecla de la consola del robot que se ha pulsado se hunde (y vuelve: se pulsa muchas veces)
func _mnd_tecla_p05(id: String) -> void:
	var m = _mnd_p05.get(id)
	if is_instance_valid(m):
		Mandos.accionar(m, false)


## El tiron de la cuerda de la espadaña al tocar
func _cuerda_tiron() -> void:
	if not is_instance_valid(_cuerda_p08):
		return
	var tw := _cuerda_p08.create_tween()
	tw.tween_property(_cuerda_p08, "position", _cuerda_p08_dir * 0.14, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_cuerda_p08, "position", Vector3.ZERO, 0.35).set_trans(Tween.TRANS_SINE)


# ======================================================================================================
# LO QUE SE USA
# ======================================================================================================
func _usables_extra(f: String) -> void:
	if terminado:
		return
	var jp: Vector3 = jugador.global_position if is_instance_valid(jugador) else Vector3.ZERO
	# 3 el extractor
	if f == "p03" and _vent_t < 0.0 and not _puerta_abierta:
		_u("p03_ventilador", _mnd_donde(_mnd_extractor, Vector3(0, 0, 0.2), _v(_c("p03_grisu")["mando"]) + Vector3(0.1, 1.1, 0)),
			"ENCENDER EL EXTRACTOR (tarda en tirar)")
	# 4 la quitanieves
	if f == "p04" and _qn_estado == 0 and is_instance_valid(_qn):
		_u("p04_arrancar", _qn.global_position + Vector3(0, 1.8, 0), "ARRANCAR LA QUITANIEVES", 3.5)
	# 5 el robot
	if f == "p05":
		var con := _v(_c("p05_robot")["consola"])
		if jp.distance_to(con) < 4.0:
			# cada uno en su tecla de la consola (a 30 cm unas de otras) y el detonador en su embolo
			if _robot_carga:
				_u("p05_detonar", _mnd_donde(_mnd_p05.get("p05_detonar"), Vector3(0, 0, 0.42), con + Vector3(-0.1, 1.4, 0.5)), "¡DETONAR LA CARGA!", 3.0)
			_u("p05_avanza", _mnd_donde(_mnd_p05.get("p05_avanza"), Vector3(0, 0, 0.05), con + Vector3(-0.3, 1.1, -0.2)), "ROBOT: AVANZAR ▲", 3.0)
			_u("p05_izq", _mnd_donde(_mnd_p05.get("p05_izq"), Vector3(0, 0, 0.05), con + Vector3(-0.3, 1.1, -0.5)), "ROBOT: GIRAR ◀", 3.0)
			_u("p05_der", _mnd_donde(_mnd_p05.get("p05_der"), Vector3(0, 0, 0.05), con + Vector3(-0.3, 1.1, 0.1)), "ROBOT: GIRAR ▶", 3.0)
	# 7 los braseros
	if f in ["p06", "p07", "p08"]:
		var br: Array = _c("p07_ventisca").get("braseros", [])
		for i in br.size():
			if not bool(_braseros[i]) and jp.distance_to(_v(br[i])) < 3.0:
				_u("p07_b%d" % i, _v(br[i]) + Vector3(0, 1.1, 0), "ENCENDER EL BRASERO")
	# 8 la cuerda de la espadaña
	if f == "p08" and not _tocando:
		var mel: Array = par.get("melodias", [])
		_u("p08_cuerda", _cuerda_p08_mano if _cuerda_p08_mano != Vector3.ZERO else _v(_c("p08_campanas")["cuerda"]) + Vector3(0, 1.2, 0),
			"TOCAR LA MELODÍA (ronda %d de %d)" % [mini(_toque + 1, mel.size()), mel.size()])
	# 9 el panel de los laseres
	if f == "p09":
		_u("p09_panel", _mnd_donde(_mnd_laseres, Vector3(0, 0.18, 0.15), _v(_c("p09_laseres")["panel"]) + Vector3(0.4, 1.2, 0)), "APAGAR LOS LÁSERES")
	# 10 el emisor y los espejos
	if f == "p10":
		if not _haz_on:
			_u("p10_on", _mnd_donde(_mnd_emisor, Vector3(0, 0, 0.2), _v(_c("p10_espejos")["mando"]) + Vector3(0, 1.0, 0.3)),
				"ENCENDER EL LÁSER DE ESTRELLA GUÍA")
		var es: Array = _c("p10_espejos")["espejos"]
		for i in es.size():
			var ep := Vector3(float(es[i][0]), M6 + 1.0, float(es[i][1]))
			if jp.distance_to(ep) < 3.0:
				_u("p10_e%d" % i, ep, "GIRAR EL ESPEJO (45°)", 2.6)
	# 11 el soplete
	var llevo := _llevo()
	if f == "p11" and llevo == "":
		var o: Dictionary = _obj4.get("soplete", {})
		if not o.is_empty() and String(o["estado"]) == "suelo" and (o["pos"] as Vector3).distance_to(jp) < 2.4:
			_u("coger:soplete", (o["pos"] as Vector3) + Vector3(0, 0.4, 0), "COGER EL SOPLETE")
	if llevo != "":
		_u("soltar", jp + Vector3(0, 1.0, 0), "SOLTAR EL SOPLETE", 5.0)
	# 12 el teleferico
	if f == "p12" and _cabina_t < 0.0:
		_u("p12_marcha", _mnd_donde(_mnd_teleferico, Vector3(0.09, 0.04, 0.15), _v(_c("p12_teleferico")["mando"]) + Vector3(0, 1.1, -0.3)),
			"PONER EN MARCHA EL TELEFÉRICO")


func _pide_extra(accion: String) -> void:
	var de := _pide_de
	if accion.begins_with("diana:"):
		var partes := accion.split(":")
		if partes.size() >= 3:
			_diana_host(partes[1], float(partes[2]))
		return
	if accion.begins_with("hielo:"):
		var cf := accion.substr(6).split(",")
		if cf.size() == 2 and not _rotas.has(accion.substr(6)):
			_evento("p01_rompe", [int(cf[0]), int(cf[1])])
		return
	if accion.begins_with("falso:"):
		var ij := accion.substr(6).split(",")
		if ij.size() == 2 and not _falsos_rotos.has(accion.substr(6)):
			_evento("p07_falso", [int(ij[0]), int(ij[1])])
		return
	if accion.begins_with("p07_b"):
		var i := int(accion.substr(5))
		if i >= 0 and i < _braseros.size() and not bool(_braseros[i]):
			_evento("p07_brasero", [i])
		return
	if accion.begins_with("p10_e"):
		var i := int(accion.substr(5))
		if fase == "p10" and i >= 0 and i < _espejos.size():
			_espejos[i] = (int(_espejos[i]) + 1) % 4
			_evento("p10_espejo", [i, _espejos[i]])
		return
	if accion.begins_with("p11_llama:"):
		var pp := accion.split(":")
		if pp.size() < 4:
			return
		var p := Vector3(float(pp[1]), float(pp[2]), float(pp[3]))
		Combat.damage_around(get_tree(), p, 1.6, 14.0, null, false)
		for k in _hielo_cajas():
			if (k as Array).size() >= 6 and _dentro_de(p, k, 0.7):
				_evento("p11_derrite", [p.x, p.y, p.z])
				break
		return
	if accion.begins_with("coger:"):
		var id := accion.substr(6)
		var o: Dictionary = _obj4.get(id, {})
		if o.is_empty() or String(o["estado"]) != "suelo" or _lleva_id(de) != "":
			return
		var p2: Vector3 = o["pos"]
		_evento("obj4", [id, "lleva", de, p2.x, p2.y, p2.z])
		return
	match accion:
		"soltar":
			var id2 := _lleva_id(de)
			if id2 == "":
				return
			var q := _nodo_de(de)
			var p3: Vector3 = q.global_position if q else Vector3.ZERO
			_evento("obj4", [id2, "suelo", 0, p3.x, p3.y + 0.05, p3.z])
		"grisu_chispa":
			if _grisu < 3 and not _h("p03"):
				_evento("p03_chispa", [])
		"p03_ventilador":
			if _vent_t < 0.0 and not _puerta_abierta and fase == "p03":
				_evento("p03_ventilador", [])
				_horda(12, "¡EL RUIDO DEL EXTRACTOR! La horda entra en la mina: ¡NO DISPARÉIS!")
		"p04_arrancar":
			if _qn_estado == 0:
				_evento("p04_estado", [_qn_s, 1])
				_qn_tanda_t = 12.0
				_horda(10, "")
		"p05_avanza":
			if fase == "p05":
				_robot_avanza()
		"p05_izq", "p05_der":
			if fase == "p05":
				_robot_dir = posmod(_robot_dir + (3 if accion == "p05_izq" else 1), 4)
				_evento("p05_mueve", [_robot_celda.x, _robot_celda.y, _robot_dir, 1 if _robot_carga else 0])
		"p05_detonar":
			if fase == "p05" and _robot_carga and not _h("p05"):
				_evento("p05", [])
		"p08_cuerda":
			if fase == "p08" and not _tocando:
				_evento("p08_toca", [_toque])
		"p09_alarma":
			if _laseres_on:
				_evento("p09_alarma", [de])
				_horda(6, "")
		"p09_panel":
			if fase == "p09":
				_evento("p09", [])
		"p10_on":
			if not _haz_on:
				_evento("p10_on", [])
		"p12_marcha":
			if _cabina_t < 0.0 and _h("p11"):
				_evento("p12_marcha", [])


## El anfitrion decide que pasa cuando le dan a una diana
func _diana_host(id: String, _dano: float) -> void:
	if id.begins_with("bidon"):
		_evento("bidon", [int(id.substr(5))])
	elif id == "grisu":
		if _h("p03") or _grisu == 3:
			return
		if _grisu == 2:
			_evento("p03", [])
		else:
			_evento("p03_chispa", [])
	elif id.begins_with("gazex"):
		var i := int(id.substr(5))
		if i < 0 or i >= _gazex.size() or bool(_gazex[i]):
			return
		_evento("p06_gazex", [i])
		var n := 0
		for g in _gazex:
			if bool(g):
				n += 1
		if n >= _gazex.size() and not _h("p06"):
			get_tree().create_timer(1.2).timeout.connect(func(): _evento("p06", []))
	elif id.begins_with("campana"):
		_campana_tiro(int(id.substr(7)))


func _evento_extra(e: String, datos: Array) -> void:
	match e:
		"fase4":
			if not _soy_host:
				fase = String(datos[0])
		"estado4":
			_aplicar_estado(String(datos[0]))
		"obj4":
			_obj_estado(String(datos[0]), String(datos[1]), int(datos[2]), Vector3(float(datos[3]), float(datos[4]), float(datos[5])))
		"bidon":
			_bidon_revienta(int(datos[0]), false)
		"p01_rompe":
			_romper_placa(int(datos[0]), int(datos[1]), false)
		"p02_rugido":
			var p := Vector3(float(datos[0]), float(datos[1]), float(datos[2]))
			Audio.voz_criatura("tanque", "alerta", p, 8.0, 250.0)
			_mensaje_local("¡UN TANK SALE DEL PUEBLO! A tiros casi no cae: llevadlo al HIELO FINO")
			if _soy_host and is_instance_valid(_tank6) and "vida" in _tank6:
				_tank6.vida = float(_tank6.vida) * 2.5
		"p02_hunde":
			_p02_hunde(Vector3(float(datos[0]), float(datos[1]), float(datos[2])))
		"p03_chispa":
			_grisu_revienta_dentro()
			if _soy_host and _grisu == 3:
				for cr in _vivos:
					if is_instance_valid(cr) and _en_grisu((cr as Node3D).global_position) and cr.has_method("take_damage"):
						cr.take_damage(400.0, Vector3.ZERO)
		"p03_ventilador":
			_p03_ventilador()
		"p03_puerta":
			var sin_gas := _grisu == 3
			_p03_puerta()
			if sin_gas:
				hecho["p03"] = true
		"p04_estado":
			_qn_nuevo_estado(float(datos[0]), int(datos[1]))
		"p04_s":
			if not _soy_host:
				_qn_s = float(datos[0])
		"p04_pala":
			_qn_pala(Vector3(float(datos[0]), float(datos[1]), float(datos[2])), Vector2(float(datos[3]), float(datos[4])))
		"p05_mueve":
			# la tecla que se ha pulsado se hunde en todas las maquinas (se sabe por lo que ha cambiado)
			var celda_n := Vector2(float(datos[0]), float(datos[1]))
			if celda_n != _robot_celda:
				_mnd_tecla_p05("p05_avanza")
			elif int(datos[2]) == posmod(_robot_dir + 3, 4):
				_mnd_tecla_p05("p05_izq")
			elif int(datos[2]) == posmod(_robot_dir + 1, 4):
				_mnd_tecla_p05("p05_der")
			_robot_celda = celda_n
			_robot_dir = int(datos[2])
			_robot_carga = int(datos[3]) != 0
			_robot_colocar(false)
		"p05_choca":
			_mnd_tecla_p05("p05_avanza")
			Audio.play3d("gen/teclado/error", _v(_c("p05_robot")["consola"]) + Vector3.UP, 0.0, 0.0, 20.0, Audio.PRI_MID)
			_mensaje_local("¡EL ROBOT CHOCA! Por ahí hay roca")
		"p06_gazex":
			_gazex_revienta(int(datos[0]), false)
		"p07_brasero":
			_encender_brasero(int(datos[0]), false)
		"p07_falso":
			_romper_falso(int(datos[0]), int(datos[1]), false)
		"p08_toca":
			_cuerda_tiron()
			_p08_toca(int(datos[0]))
		"p08_nota":
			var ok := int(datos[1])
			_campana_suena(int(datos[0]), Color(0.4, 1.0, 0.4) if ok == 1 else (Color(1.0, 0.2, 0.1) if ok == 0 else Color(1.0, 0.8, 0.4)), 0.8)
			if ok == 0:
				Audio.play3d("gen/teclado/error", _v(_c("p08_campanas")["cuerda"]) + Vector3.UP * 3.0, 4.0, 0.0, 50.0, Audio.PRI_HIGH)
				_toque_i = 0
		"p08_ronda":
			_toque = int(datos[0])
			_toque_i = 0
			_mensaje_local("¡BIEN! Ronda %d de %d · tirad otra vez de la cuerda" % [_toque + 1, (par.get("melodias", []) as Array).size()])
		"p09_alarma":
			_p09_alarma(int(datos[0]))
		"p10_on":
			_haz_on = true
			_mnd_accionar(_mnd_emisor)
			Audio.play3d("gen/espejo/receptor", _v(_c("p10_espejos")["mando"]) + Vector3.UP, 0.0, 0.0, 40.0, Audio.PRI_HIGH)
			_haz_calcular()
		"p10_espejo":
			var i := int(datos[0])
			if i >= 0 and i < _espejos.size():
				_espejos[i] = int(datos[1])
				_espejo_refrescar(i, false)
		"p11_derrite":
			_derrite(Vector3(float(datos[0]), float(datos[1]), float(datos[2])))
		"p11_libre":
			var i2 := int(datos[0])
			if i2 >= 0 and i2 < _hielo_libre.size() and not bool(_hielo_libre[i2]):
				_hielo_libre[i2] = true
				_mensaje_local("¡EL MURO DE HIELO CEDE!" if i2 == 0 else "¡UN FRENO DE LA RUEDA, LIBRE!")
				Audio.bf3d("destru/derrumbe_medio", _centro(_hielo_cajas()[i2]), 0.0, 40.0, Audio.PRI_HIGH)
		"p12_marcha":
			_p12_marcha()
		_:
			if e.length() == 3 and e.begins_with("p"):
				_resolver6(e, false)


func _on_evento(e: String, datos: Array) -> void:
	super._on_evento(e, datos)
	if e == "escapan":
		_cine_final()
