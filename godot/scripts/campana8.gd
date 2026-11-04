extends "res://scripts/campana_kit.gd"
## EPISODIO 8 DE LA CAMPAÑA: "EL VOLCAN" (campana_volcan, tools/generar_mapa_campana8.py). 2026-10-02.
##
## El globo del episodio 7 se mete en una nube de ceniza y cae en una ISLA VOLCANICA en erupcion (escena de entrada).
## De noche, con el resplandor de la lava. La estacion vulcanologica tiene un hidroavion en la bahia. NUEVE PUZZLES:
##    1 LA CAMARA TERMICA   en la cabaña; en la nube de ceniza no se ve nada sin ella (cada uno coge la suya)
##    2 LA NUBE DE CENIZA   con la camara se ven las criaturas (calientes) y los mojones del camino
##    3 LAS BOMBAS          el llano: caen bombas volcanicas (la marca roja avisa); el abrigo de hormigon protege
##    4 LA TORRE DE AGUA    sus cuatro patas a tiros: cae al rio de lava, el vapor revienta y queda una costra que se cruza
##    5 LA ROCA Y EL GEISER se empuja una roca por la rejilla (sokoban) hasta el geiser: la lanza contra el derrumbe
##    6 LAS MASCARAS        el valle del azufre mata sin mascara; los filtros se gastan y hay cajas de repuesto
##    7 LA COLADA           las tres cargas del dique: la lava baja por el pueblo, arrasa la horda, y fria se cruza
##    8 EL TUNEL DE LAVA    la lava sube a golpes por el suelo del tubo; se espera en las alcobas altas
##    9 EL HIDROAVION       calentar los motores un minuto (aguantad) y todos a bordo; despega con la erupcion
##
## Escenas de camara: el globo que cae, la torre de agua en la lava, el geiser que lanza la roca, la colada que arrasa
## el pueblo y la gran erupcion con el hidroavion despegando. La lava es del juego (planos con un sombreado propio).

const COLOR_AVISO := Color(1.0, 0.75, 0.1)
const COLOR_INFO := Color(0.35, 0.8, 1.0)
const COLOR_PELIGRO := Color(1.0, 0.3, 0.1)
const G8 := 3.0
const ROTULOS := {"camara": "p01", "bombas": "p03", "torre": "p04", "roca": "p05", "mascaras": "p06", "dique": "p07",
	"tunel": "p08", "hidro": "p09"}
const BIDONES := [[48.0, 3.0, 150.0], [120.0, 3.0, 150.0], [140.0, 3.0, 128.0], [158.0, 3.0, 78.0], [134.0, 3.0, 50.0],
	[150.0, 3.0, 28.0], [104.0, 3.0, 20.0], [70.0, 3.0, 36.0], [34.0, 3.0, 20.0], [46.0, 3.0, 112.0]]
const SOMBREADO_LAVA := "shader_type spatial;\nrender_mode unshaded, cull_disabled;\nuniform float fria = 0.0;\nvoid fragment() {\n\tvec2 uv = UV * 7.0 + vec2(TIME * 0.05, TIME * 0.03);\n\tfloat n = sin(uv.x * 3.1 + sin(uv.y * 2.3 + TIME * 0.4)) * 0.5 + 0.5;\n\tfloat m = sin(uv.y * 4.7 + sin(uv.x * 1.7 - TIME * 0.3)) * 0.5 + 0.5;\n\tfloat k = n * m;\n\tvec3 c = mix(vec3(0.55, 0.06, 0.0), vec3(1.0, 0.55, 0.05), k);\n\tc = mix(c, vec3(1.0, 0.92, 0.45), pow(k, 6.0));\n\tvec3 costra = mix(vec3(0.07, 0.05, 0.05), vec3(0.5, 0.08, 0.0), pow(k, 8.0));\n\tALBEDO = mix(c * 1.7, costra, fria);\n}\n"

var _comprobar_t8 := 0.0
var _bidones_vivos: Array = []
var _sombreado_lava: Shader = null
var _ceniza_fx: CPUParticles3D = null
var _erupcion_t := 12.0
var _niebla_base := -1.0
# la entrada
var _globo8: Node3D = null
var _globo_t := -1.0
# 1-2 la camara termica y la ceniza
var _termica := false
var _termica_capa: CanvasLayer = null
var _marcas_calor: Array = []
var _k_ceniza := 0.0
# 3 las bombas
var _bombas_t := 0.0
# 4 la torre de agua
var _torre: Node3D = null
var _patas: Array = [false, false, false, false]
var _rio_lava: MeshInstance3D = null
var _costra_puente: MeshInstance3D = null
# 5 la roca
var _roca: StaticBody3D = null
var _roca_celda := Vector2i(9, 13)
var _roca_encima_t := -1.0
var _geiser_chicos_t := 0.0
# 6 las mascaras
var _mascara := false
var _filtro := 0.0
var _mascara_capa: CanvasLayer = null
var _mascara_ruido: AudioStreamPlayer = null
var _gas_dano_t := 0.0
# 7 la colada
var _cargas: Array = [false, false, false]
var _colada_t := -1.0
var _colada_z_tallado := 51.0
var _colada_plano: MeshInstance3D = null
var _colada_fria := -1.0
var _colada_ruido: AudioStreamPlayer3D = null
var _pueblo_dormido := false
# 8 el tunel
var _tunel_t := -1.0
var _tunel_planos: Array = []
var _tunel_y := 0.0
var _tunel_aviso := false
# 9 el hidroavion
var _hidro: AnimatableBody3D = null
var _helices: Array = []
var _calentar_t := -1.0
var _listo := false
var _hidro_ruido: AudioStreamPlayer3D = null
var _tanda_final8 := 0.0
var _final_tank8 := false
# LOS MANDOS (mandos.gd): lo que se usa con el boton, de verdad y con su piloto (ambar latiendo: se puede usar;
# verde: hecho; apagado: aun no). Sin carteles: se encuentran mirando el sitio.
var _mnd_mascaras: Node3D = null      ## las tres mascaras colgadas en la taquilla (el piloto es de cada uno)
var _mnd_filtros: Array = []         ## los botes de filtro encima de cada caja
var _mnd_roca: Node3D = null          ## la palanca de recolocar la roca (se usa muchas veces)
var _mnd_motores: Node3D = null       ## el panel de arranque, en el costado del hidroavion junto a la puerta
# la barra
var _barra_capa: CanvasLayer = null
var _barra_llena: ColorRect = null
var _barra_texto: Label = null
var _barra_pide: Array = []
var _en_foto := -1


# ======================================================================================================
# LA ESCENA
# ======================================================================================================
func _montar_escena() -> void:
	super._montar_escena()
	rotulo_fase = ROTULOS
	_arreglar_puertas_refugio()
	_muros_invisibles()
	_sombreado_lava = Shader.new()
	_sombreado_lava.code = SOMBREADO_LAVA
	_montar_volcan()
	_montar_globo8()
	_montar_bidones()
	_montar_p01()
	_montar_p04()
	_montar_p05()
	_montar_p06()
	_montar_p07()
	_montar_p08()
	_montar_p09()


func _fase_de_rotulos() -> String:
	match fase:
		"inicio":
			return "p01"
		"p02":
			return "p01"
		"camino_refugio", "refugio", "enfriando":
			return "p08"
		"subir":
			return "p09"
	return fase


func _estado_dict() -> Dictionary:
	return {"hecho": hecho, "fase": fase, "patas": _patas, "roca": [_roca_celda.x, _roca_celda.y], "cargas": _cargas,
		"calentar": _calentar_t, "listo": _listo, "tunel": _tunel_t}


func _aplicar_estado(txt: String) -> void:
	var d = JSON.parse_string(txt)
	if not (d is Dictionary) or _soy_host:
		return
	fase = String(d.get("fase", fase))
	var pa: Array = d.get("patas", [])
	for i in pa.size():
		if bool(pa[i]):
			_pata_rota(i, true)
	var ro: Array = d.get("roca", [9, 13])
	_roca_celda = Vector2i(int(ro[0]), int(ro[1]))
	_roca_colocar(true)
	var ca: Array = d.get("cargas", [])
	for i in ca.size():
		if bool(ca[i]):
			_carga_revienta(i, true)
	_calentar_t = float(d.get("calentar", -1.0))
	_listo = bool(d.get("listo", false))
	if float(d.get("tunel", -1.0)) >= 0.0 and _tunel_t < 0.0:
		_tunel_t = 0.0
	var hh: Dictionary = d.get("hecho", {})
	for k in hh:
		if bool(hh[k]) and not _h(String(k)):
			_resolver8(String(k), true)


func _resolver8(k: String, ya: bool) -> void:
	if _h(k):
		return
	hecho[k] = true
	match k:
		"p04": _p04_resuelto(ya)
		"p05": _p05_resuelto(ya)
		"p07": _p07_resuelto(ya)
	if not ya:
		Audio.ui("objetivo_tomado", -4.0)


# ======================================================================================================
# UTILIDADES
# ======================================================================================================
func _barra_quiero(t: String, v: float, c: Color) -> void:
	if _barra_pide.is_empty():
		_barra_pide = [t, v, c]


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


func _pedir(accion: String) -> void:
	if _en_red and not _soy_host:
		Net.net_campana_pide(accion)
	else:
		_on_pide(accion, _mi_id())


## Lo que es de cada uno (la camara termica, la mascara, los filtros) no pasa por el anfitrion
func usar_desde_jugador() -> void:
	if _usable_mirado.begins_with("local:"):
		_usar_local(_usable_mirado.substr(6))
		return
	super.usar_desde_jugador()


func _dentro(p: Vector3, r: Array, margen := 0.0) -> bool:
	return p.x > float(r[0]) - margen and p.x < float(r[2]) + margen and p.z > float(r[1]) - margen and p.z < float(r[3]) + margen


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


func _rompe_local(pos: Vector3, fuerza: float) -> void:
	var fx = jugador.get("effects") if is_instance_valid(jugador) else null
	if fx and fx.has_method("dust"):
		fx.dust(pos, fuerza)


func _bola_fuego8(p: Vector3, tam: float) -> void:
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


## Un plano de lava (rect x0, z0, x1, z1) a la altura y, con su sombreado y su resplandor
func _lava_plano(r: Array, y: float, luz := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(float(r[2]) - float(r[0]), float(r[3]) - float(r[1]))
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = _sombreado_lava
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = Vector3((float(r[0]) + float(r[2])) / 2.0, y, (float(r[1]) + float(r[3])) / 2.0)
	if luz:
		var l := _luz(mi, Vector3(0, 1.2, 0), Color(1.0, 0.4, 0.1), 2.5, maxf(q.size.x, q.size.y) * 0.8 + 6.0)
		l.name = "Luz"
	return mi


func _lava_enfriar(mi: MeshInstance3D, k: float) -> void:
	if is_instance_valid(mi) and mi.material_override is ShaderMaterial:
		(mi.material_override as ShaderMaterial).set_shader_parameter("fria", k)
		var l = mi.get_node_or_null("Luz")
		if l:
			(l as OmniLight3D).light_energy = 2.5 * (1.0 - k)


## Si MI jugador pisa lava (rect y altura): se quema
func _quema_lava(r: Array, y: float, dt: float) -> void:
	if not is_instance_valid(jugador) or bool(jugador.get("spectating")):
		return
	var p: Vector3 = jugador.global_position
	if _dentro(p, r) and p.y < y + 0.35:
		_dano_local(35.0 * dt, Vector3(0, 3.0, 0), "¡LAVA! ¡Sal de ahí!")


# ======================================================================================================
# EL VOLCAN: el crater que brilla, las erupciones y la ceniza que cae en todo el mapa
# ======================================================================================================
func _montar_volcan() -> void:
	var v: Array = cfg.get("volcan", [92, 88, 34, 33])
	var cima := Vector3(float(v[0]), float(v[3]) - 2.6, float(v[1]))
	_lava_plano([cima.x - 5.5, cima.z - 5.5, cima.x + 5.5, cima.z + 5.5], cima.y)
	var humo := _particulas(self, cima + Vector3(0, 3, 0), 60, 9.0, Color(0.15, 0.12, 0.12, 0.8), Color(0.35, 0.3, 0.3, 0.0), 6.0, false)
	humo.direction = Vector3.UP
	humo.spread = 18.0
	humo.initial_velocity_min = 3.0
	humo.initial_velocity_max = 6.0
	humo.gravity = Vector3(1.2, 1.0, 0.4)
	var l := _luz(self, cima + Vector3(0, 6, 0), Color(1.0, 0.35, 0.1), 6.0, 90.0)
	l.name = "LuzCrater"
	# la ceniza que cae (sigue a la camara)
	_ceniza_fx = _particulas(self, Vector3.ZERO, 500, 6.0, Color(0.55, 0.52, 0.5, 0.8), Color(0.35, 0.33, 0.32, 0.0), 0.06, false)
	_ceniza_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_ceniza_fx.emission_box_extents = Vector3(22, 0.5, 22)
	_ceniza_fx.direction = Vector3(0.3, -1, 0.1)
	_ceniza_fx.initial_velocity_min = 0.8
	_ceniza_fx.initial_velocity_max = 1.6
	_ceniza_fx.gravity = Vector3(0, -0.6, 0)
	_ceniza_fx.local_coords = false
	_bucle_directo("res://sounds/gen/lava/burbujas1.ogg", self, cima, 6.0, 160.0)


func _volcan_tick(dt: float) -> void:
	if is_instance_valid(_ceniza_fx):
		var c := get_viewport().get_camera_3d()
		if c:
			_ceniza_fx.global_position = c.global_position + Vector3(0, 12, 0)
	_erupcion_t -= dt
	if _erupcion_t <= 0.0:
		_erupcion_t = randf_range(22.0, 40.0)
		_erupcion(false)


## Una erupcion: el rugido, fuego en el crater, bombas que vuelan a las laderas (sin daño: es el paisaje)
func _erupcion(grande: bool) -> void:
	var v: Array = cfg.get("volcan", [92, 88, 34, 33])
	var cima := Vector3(float(v[0]), float(v[3]), float(v[1]))
	Audio.play3d("gen/volcan/rugido", cima, 10.0 if grande else 4.0, 0.1, 500.0, Audio.PRI_HIGH)
	_bola_fuego8(cima + Vector3(0, 2, 0), 5.0 if grande else 3.0)
	for k in (14 if grande else 5):
		var a := randf() * TAU
		var hacia := cima + Vector3(cos(a) * randf_range(12.0, 30.0), -randf_range(14.0, 26.0), sin(a) * randf_range(12.0, 30.0))
		_bomba_vuela(cima + Vector3(0, 3, 0), hacia, randf_range(1.6, 2.6), false)
	if is_instance_valid(jugador) and jugador.has_method("add_shake"):
		jugador.add_shake(0.5 if grande else 0.2)


## Una bomba volcanica: una piedra al rojo que vuela en arco y, si `revienta`, explota al caer
func _bomba_vuela(desde: Vector3, hacia: Vector3, dur: float, revienta: bool) -> void:
	var b := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.45
	sm.height = 0.8
	sm.radial_segments = 8
	sm.rings = 4
	b.mesh = sm
	b.material_override = _brillo(Color(1.0, 0.4, 0.1), 3.0)
	add_child(b)
	b.global_position = desde
	var cola := _particulas(b, Vector3.ZERO, 14, 0.8, Color(1.0, 0.6, 0.2, 0.9), Color(0.2, 0.2, 0.2, 0.0), 0.6, false)
	cola.local_coords = false
	cola.initial_velocity_min = 0.0
	cola.initial_velocity_max = 0.5
	var arco := func(u: float) -> void:
		if not is_instance_valid(b):
			return
		var q := desde.lerp(hacia, u)
		q.y += sin(u * PI) * 14.0
		b.global_position = q
	var tw := b.create_tween()
	tw.tween_method(arco, 0.0, 1.0, dur)
	tw.tween_callback(func():
		if revienta:
			_explosion(hacia + Vector3(0, 0.5, 0), 2.4, 55.0, 2.0)
			_bola_fuego8(hacia + Vector3(0, 0.5, 0), 1.8)
		b.queue_free())


# ======================================================================================================
# LA ENTRADA: el globo cae desde la nube de ceniza a la playa negra
# ======================================================================================================
func _montar_globo8() -> void:
	_globo8 = Node3D.new()
	_globo8.name = "GloboCaido"
	add_child(_globo8)
	var mimbre := _mm(Color(0.55, 0.4, 0.22), 0.0, 0.9)
	_caja_mesh(_globo8, Vector3(4.0, 1.2, 4.0), Vector3(0, 0.6, 0), mimbre)
	var tela := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 7.0
	sm.height = 16.0
	tela.mesh = sm
	tela.material_override = _mm(Color(0.85, 0.25, 0.15), 0.0, 0.7)
	tela.name = "Tela"
	_globo8.add_child(tela)
	tela.position = Vector3(0, 13.0, 0)
	var hay_cine: bool = DisplayServer.get_name() != "headless" and not ("--sinintro" in OS.get_cmdline_user_args())
	for a in OS.get_cmdline_user_args():
		if String(a).ends_with("test") or String(a).begins_with("--campanafoto") or String(a).begins_with("--ir="):
			hay_cine = false
	if hay_cine:
		_globo_t = 0.0
		_globo_colocar(0.0)
	else:
		_globo_colocar(99.0)


func _globo_colocar(t: float) -> void:
	if not is_instance_valid(_globo8):
		return
	var g: Array = cfg.get("globo", [30, 142])
	var fin := Vector3(float(g[0]), G8, float(g[1]))
	var tela: Node3D = _globo8.get_node("Tela")
	if t < 5.5:
		var u := t / 5.5
		_globo8.global_position = (fin + Vector3(50.0, 34.0, 30.0)).lerp(fin, u * u)
		_globo8.rotation = Vector3(sin(t * 2.0) * 0.2, t * 0.6, cos(t * 1.7) * 0.25)
		tela.scale = Vector3.ONE.lerp(Vector3(1.0, 0.5, 1.0), u)
	else:
		_globo8.global_position = fin
		_globo8.rotation = Vector3(0.35, 1.2, 0.2)
		tela.position = Vector3(0, 0.6, 9.0)
		tela.scale = Vector3(1.0, 0.1, 1.0)


func _globo_tick(dt: float) -> void:
	if _globo_t < 0.0:
		return
	var antes := _globo_t
	_globo_t += dt
	_globo_colocar(_globo_t)
	if antes < 5.5 and _globo_t >= 5.5:
		_golpe(_globo8.global_position, 2.5, "destru/madera")
		_rompe_local(_globo8.global_position + Vector3(0, 0.5, 0), 5.0)
		_erupcion(true)
	if _globo_t > 6.0:
		_globo_t = -1.0


# ======================================================================================================
# LOS BIDONES (revientan a tiros)
# ======================================================================================================
func _montar_bidones() -> void:
	var rojo := _mm(Color(0.62, 0.1, 0.07), 0.35, 0.55)
	for i in BIDONES.size():
		var p := _v(BIDONES[i])
		var d := _diana("bidon%d" % i, p + Vector3(0, 0.45, 0), Vector3(0.6, 0.9, 0.6))
		_cil_mesh(d, 0.3, 0.9, Vector3.ZERO, rojo, Vector3.ZERO, 12)
		_texto3d("GASOIL", Vector3(0, 0.05, 0.31), Color(1.0, 0.9, 0.3), 12, false, d)
		_bidones_vivos.append(true)


func _bidon_revienta(i: int, ya: bool) -> void:
	if i < 0 or i >= _bidones_vivos.size() or not bool(_bidones_vivos[i]):
		return
	_bidones_vivos[i] = false
	var d = _dianas.get("bidon%d" % i)
	if is_instance_valid(d):
		d.set("activa", false)
		d.queue_free()
	_dianas.erase("bidon%d" % i)
	var p := _v(BIDONES[i]) + Vector3(0, 0.5, 0)
	_explosion(p, 3.2, 140.0, 2.4, ya)
	if not ya:
		_bola_fuego8(p, 2.4)


# ======================================================================================================
# 1-2. LA CAMARA TERMICA Y LA NUBE DE CENIZA
# ======================================================================================================
func _montar_p01() -> void:
	var c := _c("p01_camara")
	if c.is_empty():
		return
	var p := _v(c["camara"])
	var cam := _estatico("CamaraTermica", p + Vector3(0, 0.95, 0))
	_caja_mesh(cam, Vector3(0.35, 0.22, 0.25), Vector3.ZERO, _mm(Color(0.2, 0.2, 0.22), 0.5, 0.5))
	_cil_mesh(cam, 0.08, 0.12, Vector3(0, 0, -0.15), _brillo(Color(1.0, 0.3, 0.1), 1.5), Vector3(PI / 2, 0, 0), 10)
	_rotulo("camara", "CÁMARA TÉRMICA\n(sin ella, en la ceniza no se ve nada)", p + Vector3(0, 2.4, 0), COLOR_INFO)
	# los mojones del camino: piedras calientes (con la camara se ven de lejos)
	for m in _c("p02_ceniza").get("mojones", []):
		var q := Vector3(float(m[0]), G8 + 1.6, float(m[1]))
		var e := _esfera_mesh(self, 0.3, q, _brillo(Color(1.0, 0.5, 0.15), 2.0))
		e.name = "Mojon"
		_marcas_calor.append(e)
		e.visible = false


func _en_ceniza(p: Vector3) -> bool:
	var z: Array = _c("p02_ceniza").get("zona", [58, 124, 126, 164])
	return _dentro(p, z)


func _ceniza_tick(dt: float) -> void:
	if not is_instance_valid(jugador):
		return
	var dentro := _en_ceniza(jugador.global_position) and not terminado
	_k_ceniza = move_toward(_k_ceniza, 1.0 if dentro else 0.0, dt * 0.6)
	var escena := get_tree().current_scene
	if escena and "env" in escena and escena.env and escena.env.environment:
		var e: Environment = escena.env.environment
		if _niebla_base < 0.0:
			_niebla_base = e.fog_density
		e.fog_enabled = true
		e.fog_density = lerpf(_niebla_base, 0.035 if _termica else 0.11, _k_ceniza)
	var ve := _termica and _k_ceniza > 0.4
	for mk in _marcas_calor:
		if is_instance_valid(mk):
			(mk as Node3D).visible = ve
	if _termica_capa:
		_termica_capa.visible = ve
		if ve:
			_marcas_criaturas()


## La termografia: la pantalla tenida y cada criatura cercana, una mancha caliente que se ve a traves de la ceniza
func _termica_encender() -> void:
	_termica = true
	Audio.play3d("gen/termica/pitido", jugador.global_position if is_instance_valid(jugador) else Vector3.ZERO, 0.0, 0.0, 10.0, Audio.PRI_MID)
	_termica_capa = CanvasLayer.new()
	_termica_capa.layer = 4
	add_child(_termica_capa)
	var tinte := ColorRect.new()
	tinte.color = Color(0.35, 0.05, 0.45, 0.28)
	tinte.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tinte.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_termica_capa.add_child(tinte)
	var t := Label.new()
	t.text = "◉ TERMOGRAFÍA"
	t.add_theme_font_size_override("font_size", 16)
	t.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	t.position = Vector2(24, 140)
	_termica_capa.add_child(t)
	_termica_capa.visible = false
	_mensaje_local("CÁMARA TÉRMICA: se enciende sola dentro de la ceniza")


var _manchas: Array = []


func _marcas_criaturas() -> void:
	var n := 0
	var jp: Vector3 = jugador.global_position
	for cr in get_tree().get_nodes_in_group("criaturas"):
		if not is_instance_valid(cr) or bool(cr.get("muerta")) or (cr as Node3D).global_position.distance_to(jp) > 45.0:
			continue
		if n >= _manchas.size():
			var m := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(0.9, 1.9)
			m.mesh = q
			var mat := _brillo(Color(1.0, 0.85, 0.2), 4.0)
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
			mat.no_depth_test = true
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = 0.75
			m.material_override = mat
			add_child(m)
			_manchas.append(m)
		var mm: MeshInstance3D = _manchas[n]
		mm.visible = true
		mm.global_position = (cr as Node3D).global_position + Vector3(0, 1.0, 0)
		n += 1
	for k in range(n, _manchas.size()):
		(_manchas[k] as Node3D).visible = false


# ======================================================================================================
# 3. LAS BOMBAS VOLCANICAS (el llano)
# ======================================================================================================
## (el anfitrion) mientras haya alguien en el llano, cada poco una bomba cerca de alguien
func _bombas_host_tick(dt: float) -> void:
	if not (fase in ["p03", "p04"]):
		return
	var z: Array = _c("p03_bombas").get("zona", [126, 112, 164, 164])
	var ab: Array = _c("p03_bombas").get("abrigo", [150, 112, 160, 118])
	var en: Array = []
	for pl in _jugadores_vivos():
		var p: Vector3 = (pl as Node3D).global_position
		if _dentro(p, z) and not _dentro(p, ab):
			en.append(p)
	if en.is_empty():
		return
	_bombas_t -= dt
	if _bombas_t > 0.0:
		return
	_bombas_t = randf_range(0.6, 1.1)
	var p0: Vector3 = en.pick_random()
	var q := p0 + Vector3(randf_range(-9.0, 9.0), 0, randf_range(-9.0, 9.0))
	q.x = clampf(q.x, float(z[0]) + 1.0, float(z[2]) - 3.0)
	q.z = clampf(q.z, float(z[1]) + 1.0, float(z[3]) - 3.0)
	_evento("p03_bomba", [q.x, q.z])


func _bomba_marca(x: float, z: float) -> void:
	var p := Vector3(x, G8 + 0.06, z)
	var marca := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 2.2
	cm.bottom_radius = 2.2
	cm.height = 0.04
	marca.mesh = cm
	var mat := _brillo(Color(1.0, 0.1, 0.05), 2.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.55
	marca.material_override = mat
	add_child(marca)
	marca.global_position = p
	var tw := marca.create_tween()
	tw.set_loops(4)
	tw.tween_property(marca, "scale", Vector3(0.6, 1, 0.6), 0.18)
	tw.tween_property(marca, "scale", Vector3.ONE, 0.18)
	if is_instance_valid(jugador) and jugador.global_position.distance_to(p) < 50.0:
		Audio.play3d("gen/bomba/silba", p + Vector3(0, 10, 0), 2.0, 0.1, 60.0, Audio.PRI_MID)
	var v: Array = cfg.get("volcan", [92, 88, 34, 33])
	var desde := Vector3(float(v[0]), float(v[3]) + 4.0, float(v[1]))
	_bomba_vuela(desde.lerp(p, 0.6) + Vector3(0, 18, 0), p, 1.4, true)
	get_tree().create_timer(1.5).timeout.connect(marca.queue_free)


# ======================================================================================================
# 4. LA TORRE DE AGUA (cae al rio de lava: vapor y costra)
# ======================================================================================================
func _montar_p04() -> void:
	var c := _c("p04_torre")
	if c.is_empty():
		return
	var rio: Array = c["rio"]
	_rio_lava = _lava_plano(rio, float(c.get("lava_y", 1.4)))
	_bucle_directo("res://sounds/gen/lava/burbujas1.ogg", self, _centro([rio[0], 1.4, rio[1], rio[2], 1.4, rio[3]]), 0.0, 40.0)
	var to: Array = c["torre"]
	var alto := float(c.get("alto", 14.0))
	_torre = Node3D.new()
	_torre.name = "TorreAgua"
	add_child(_torre)
	_torre.global_position = Vector3(float(to[0]), G8 + 0.4, float(to[1]))
	var hierro := _mm(Color(0.32, 0.3, 0.3), 0.8, 0.4)
	var dep := _mm(Color(0.62, 0.64, 0.66), 0.7, 0.35)
	_cil_mesh(_torre, 3.2, 5.0, Vector3(0, alto - 2.5, 0), dep, Vector3.ZERO, 20)
	_cil_mesh(_torre, 3.4, 0.5, Vector3(0, alto + 0.2, 0), hierro, Vector3.ZERO, 20)
	_texto3d("AGUA", Vector3(0, alto - 2.4, 3.22), Color(0.2, 0.3, 0.6), 64, false, _torre)
	var k := 0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var pie := Vector3(sx * 2.4, 0.0, sz * 2.4)
			var pata := _cuerda(hierro, 0.18)
			_linea(pata, _torre.global_position + pie, _torre.global_position + Vector3(sx * 1.8, alto - 5.0, sz * 1.8))
			pata.top_level = false
			pata.reparent(_torre, true)
			var d := _diana("pata%d" % k, _torre.global_position + pie + Vector3(0, 1.2, 0), Vector3(0.6, 1.6, 0.6))
			_caja_mesh(d, Vector3(0.5, 0.6, 0.5), Vector3(0, -0.4, 0), _brillo(Color(1.0, 0.75, 0.1), 1.4))
			k += 1
	_rotulo("torre", "LA TORRE DE AGUA\ndisparad a sus 4 PATAS: caerá al río", _torre.global_position + Vector3(-5.0, 4.0, 2.0), COLOR_AVISO)


func _pata_rota(i: int, ya: bool) -> void:
	if i < 0 or i >= _patas.size() or bool(_patas[i]):
		return
	_patas[i] = true
	var d = _dianas.get("pata%d" % i)
	if is_instance_valid(d):
		(d as Node3D).visible = false
		d.set("activa", false)
		_sin_colision(d)
	if not ya and is_instance_valid(_torre):
		Audio.bf3d("destru/metal", _torre.global_position, 2.0, 60.0, Audio.PRI_HIGH)
		var tw := _torre.create_tween()
		tw.tween_property(_torre, "rotation:x", _torre.rotation.x - 0.03, 0.3)
		_mensaje_local("PATA %d DE 4" % _patas.count(true) if _patas.count(true) < 4 else "¡LA TORRE SE VIENE ABAJO!")


func _p04_resuelto(ya: bool) -> void:
	var c := _c("p04_torre")
	var pu: Array = c["puente"]
	var costra := int((cfg.get("mat", {}) as Dictionary).get("costra", 0))
	var enfria := func() -> void:
		_rellenar(Vector3(float(pu[0]), G8 - 0.6, float(pu[1])), Vector3(float(pu[2]), G8, float(pu[3])), costra)
		if is_instance_valid(_costra_puente):
			return
		_costra_puente = _lava_plano(pu, float(c.get("lava_y", 1.4)) + 0.02, false)
		_lava_enfriar(_costra_puente, 1.0)
	if ya:
		if is_instance_valid(_torre):
			_torre.rotation.x = -PI / 2
			_torre.global_position += Vector3(0, -0.2, -2.0)
		enfria.call()
		return
	var to := _torre.global_position
	var cam := to + Vector3(18.0, 8.0, 10.0)
	_corte([[cam, to + Vector3(0, 10, 0), 0.0], [cam + Vector3(-2, -2, -6), to + Vector3(0, 2, -9), 2.2], [cam + Vector3(-4, -3, -10), to + Vector3(0, 3, -10), 6.0]], 6.2, "")
	var tw := _torre.create_tween()
	tw.tween_property(_torre, "rotation:x", -PI / 2, 1.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	get_tree().create_timer(1.8).timeout.connect(func():
		var p := to + Vector3(0, 0, -10.0)
		Audio.play3d("gen/vapor/siseo", p, 12.0, 0.0, 200.0, Audio.PRI_TOP)
		_golpe(p, 3.0, "destru/metal")
		var vapor := _particulas(self, p, 120, 5.0, Color(0.95, 0.95, 0.95, 0.9), Color(0.8, 0.8, 0.8, 0.0), 5.0, false)
		vapor.one_shot = true
		vapor.explosiveness = 0.85
		vapor.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		vapor.emission_box_extents = Vector3(5.0, 1.0, 5.0)
		vapor.direction = Vector3.UP
		vapor.initial_velocity_min = 4.0
		vapor.initial_velocity_max = 10.0
		vapor.gravity = Vector3(0, 1.5, 0)
		get_tree().create_timer(6.0).timeout.connect(vapor.queue_free)
		_explosion(p + Vector3(0, 1, 0), 4.0, 80.0, 0.0)
		enfria.call())
	_mensaje_local("¡EL AGUA ENFRÍA LA LAVA! Se puede cruzar por la costra")


# ======================================================================================================
# 5. LA ROCA Y EL GEISER (sokoban)
# ======================================================================================================
func _celda_pos(c: Vector2i) -> Vector3:
	var r := _c("p05_roca")
	var re: Array = r["rejilla"]
	var ca := float(r.get("casilla", 2.0))
	return Vector3(float(re[0]) + (c.x + 0.5) * ca, G8, float(re[1]) + (c.y + 0.5) * ca)


func _montar_p05() -> void:
	var r := _c("p05_roca")
	if r.is_empty():
		return
	var ini: Array = r["inicio"]
	_roca_celda = Vector2i(int(ini[0]), int(ini[1]))
	_roca = _estatico("RocaGeiser", _celda_pos(_roca_celda))
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.95
	sm.height = 1.8
	sm.radial_segments = 10
	sm.rings = 6
	m.mesh = sm
	m.material_override = _mm(Color(0.25, 0.22, 0.22), 0.1, 0.95)
	m.name = "Malla"
	_roca.add_child(m)
	m.position = Vector3(0, 0.9, 0)
	_colision_caja(_roca, Vector3(1.8, 1.8, 1.8), Vector3(0, 0.9, 0))
	_rotulo("roca", "LA ROCA: empujadla hasta la boca del GEISER GRANDE\n(el géiser la lanzará contra el derrumbe)", _celda_pos(_roca_celda) + Vector3(0, 3.0, 0), COLOR_AVISO)
	# la PALANCA de recolocar: un armario de pie en el suelo (antes un poste flotando a 20 cm con un palo rojo
	# luminoso) mirando al campo de la rejilla, que es donde se atasca la roca
	var pa := _v(r["palanca"])
	var pb := _mnd_armario("PalancaRoca", pa, Vector3(0, 0, -1), Vector3(0.5, 1.3, 0.35), Color(0.3, 0.3, 0.32))
	_mnd_roca = Mandos.crear("palanca", pb, Vector3(0, 0.95, 0.176), Vector3(0, 0, 1), true)


func _roca_colocar(ya: bool) -> void:
	if not is_instance_valid(_roca):
		return
	var p := _celda_pos(_roca_celda)
	if ya:
		_roca.global_position = p
		return
	var tw := _roca.create_tween()
	tw.tween_property(_roca, "global_position", p, 0.5).set_trans(Tween.TRANS_SINE)
	var malla: Node3D = _roca.get_node("Malla")
	tw.parallel().tween_property(malla, "rotation:x", malla.rotation.x + 1.2, 0.5)
	Audio.play3d("gen/roca/arrastre", p, 2.0, 0.1, 30.0, Audio.PRI_MID)


## (el anfitrion) el jugador empuja desde donde esta: la roca va hacia el otro lado, si hay sitio
func _roca_empuja(desde: Vector3) -> void:
	if _h("p05") or _roca_encima_t >= 0.0:
		return
	var r := _c("p05_roca")
	var rp := _celda_pos(_roca_celda)
	var d := Vector2(rp.x - desde.x, rp.z - desde.z)
	var dir := Vector2i(signi(int(signf(d.x))), 0) if absf(d.x) > absf(d.y) else Vector2i(0, int(signf(d.y)))
	var dest := _roca_celda + dir
	var tam: Array = r["tam"]
	var libre := dest.x >= 0 and dest.y >= 0 and dest.x < int(tam[0]) and dest.y < int(tam[1])
	for p in r.get("piedras", []):
		if int(p[0]) == dest.x and int(p[1]) == dest.y:
			libre = false
	if not libre:
		_evento("p05_no", [])
		return
	var gi: Array = r["geiser"]
	_evento("p05_mueve", [dest.x, dest.y])
	if dest.x == int(gi[0]) and dest.y == int(gi[1]):
		_evento("p05_encima", [])


func _roca_encima_tick(dt: float) -> void:
	if _roca_encima_t < 0.0:
		return
	_roca_encima_t += dt
	if _roca_encima_t >= 3.0:
		_roca_encima_t = -1.0
		if _soy_host and not _h("p05"):
			_evento("p05", [])


func _geiseres_tick(dt: float) -> void:
	_geiser_chicos_t -= dt
	if _geiser_chicos_t > 0.0:
		return
	_geiser_chicos_t = randf_range(3.0, 6.0)
	var chicos: Array = _c("p05_roca").get("chicos", [])
	if chicos.is_empty() or not is_instance_valid(jugador):
		return
	var g: Array = chicos.pick_random()
	var p := Vector3(float(g[0]), G8, float(g[1]))
	if jugador.global_position.distance_to(p) > 60.0:
		return
	_chorro(p, 6.0)


func _chorro(p: Vector3, alto: float) -> void:
	var ch := _particulas(self, p, 70, 2.4, Color(0.95, 0.95, 0.95, 0.9), Color(0.85, 0.85, 0.85, 0.0), 1.2, false)
	ch.direction = Vector3.UP
	ch.spread = 8.0
	ch.initial_velocity_min = alto * 1.2
	ch.initial_velocity_max = alto * 1.8
	ch.gravity = Vector3(0, -6.0, 0)
	get_tree().create_timer(2.2).timeout.connect(func():
		ch.emitting = false
		get_tree().create_timer(2.5).timeout.connect(ch.queue_free))
	Audio.play3d("gen/geiser/erupcion", p, 0.0, 0.1, 50.0, Audio.PRI_MID)


func _p05_resuelto(ya: bool) -> void:
	var r := _c("p05_roca")
	var de: Array = r["derrumbe"]
	var br: Array = r["brecha"]
	var brecha := func() -> void:
		if world:
			var y := 0.4
			while y < 8.4:
				world.carve_beam(Vector3(float(br[0]), G8 + y, (float(de[1]) + float(de[3])) / 2.0), Vector3(1, 0, 0), float(br[1]) - float(br[0]), 3.0, 255, true)
				y += 2.0
	if ya:
		brecha.call()
		if is_instance_valid(_roca):
			_roca.global_position = Vector3((float(br[0]) + float(br[1])) / 2.0, G8, float(de[1]) - 4.0)
			_sin_colision(_roca)
		return
	var gi: Array = r["geiser"]
	var gp := _celda_pos(Vector2i(int(gi[0]), int(gi[1])))
	var hacia := Vector3((float(br[0]) + float(br[1])) / 2.0, G8 + 3.0, (float(de[1]) + float(de[3])) / 2.0)
	_chorro(gp, 12.0)
	_sin_colision(_roca)
	var cam := gp + Vector3(16.0, 6.0, 10.0)
	_corte([[cam, gp + Vector3(0, 2, 0), 0.0], [cam, gp + Vector3(0, 14, -6), 1.4], [cam + Vector3(-6, 4, -14), hacia, 4.2]], 4.4, "")
	var desde := _roca.global_position
	var arco := func(u: float) -> void:
		if not is_instance_valid(_roca):
			return
		var q := desde.lerp(hacia, u)
		q.y += sin(u * PI) * 16.0
		_roca.global_position = q
		(_roca.get_node("Malla") as Node3D).rotation.x = u * 9.0
	var tw := create_tween()
	tw.tween_interval(0.7)
	tw.tween_method(arco, 0.0, 1.0, 2.2).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		brecha.call()
		_explosion(hacia, 4.0, 90.0, 0.0)
		_bola_fuego8(hacia, 3.0)
		_golpe(hacia, 3.5, "destru/derrumbe_grave")
		_rompe_local(hacia, 5.0)
		if is_instance_valid(_roca):
			_roca.global_position = hacia + Vector3(0, -3.0, -4.0))
	_mensaje_local("¡EL GÉISER LANZA LA ROCA CONTRA EL DERRUMBE!")


# ======================================================================================================
# 6. LAS MASCARAS (el valle del azufre)
# ======================================================================================================
func _montar_p06() -> void:
	var c := _c("p06_azufre")
	if c.is_empty():
		return
	var z: Array = c["zona"]
	var nube := _particulas(self, Vector3((float(z[0]) + float(z[2])) / 2.0, G8 + 1.5, (float(z[1]) + float(z[3])) / 2.0), 160, 6.0,
		Color(0.85, 0.8, 0.3, 0.35), Color(0.7, 0.65, 0.2, 0.0), 4.0, false)
	nube.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	nube.emission_box_extents = Vector3((float(z[2]) - float(z[0])) / 2.0, 1.2, (float(z[3]) - float(z[1])) / 2.0)
	nube.direction = Vector3(0.2, 1, 0)
	nube.initial_velocity_min = 0.2
	nube.initial_velocity_max = 0.8
	nube.gravity = Vector3.ZERO
	var ta := _v(c["taquilla"])
	# LAS MASCARAS colgadas de su barra en la cara de la taquilla que da al valle (antes la taquilla era un bloque de
	# chapa liso: no se veia que ahi hubiera nada), y encima de cada caja verde, sus tres BOTES DE FILTRO
	_mnd_mascaras = Mandos.en_pared(world, "mascaras", self, Vector3(ta.x, G8 + 1.35, ta.z - 0.9), Vector3(0, 0, -1), 1.5)
	for cj in c.get("cajas", []):
		_mnd_filtros.append(_mnd_de_pie("filtros", self, _v(cj) + Vector3(0, 0.8, 0), Vector3(0, 0, -1)))
	_rotulo("mascaras", "MÁSCARAS DE GAS\n(el azufre mata sin ella)", ta + Vector3(0, 3.2, 0), COLOR_PELIGRO)


func _en_azufre(p: Vector3) -> bool:
	var z: Array = _c("p06_azufre").get("zona", [100, 12, 166, 40])
	return _dentro(p, z) and p.y < G8 + 6.0


func _azufre_tick(dt: float) -> void:
	if not is_instance_valid(jugador) or bool(jugador.get("spectating")):
		return
	var dentro := _en_azufre(jugador.global_position) and not terminado
	var maximo := float(_c("p06_azufre").get("filtro_s", 45.0))
	if dentro and _mascara:
		_filtro = maxf(0.0, _filtro - dt)
	if dentro or (_mascara and _filtro < maximo):
		if _mascara:
			_barra_quiero("FILTRO DE LA MÁSCARA · %d s" % int(ceilf(_filtro)), _filtro / maximo,
				Color(1.0, 0.3, 0.2, 0.95) if _filtro < 10.0 else Color(0.6, 1.0, 0.4, 0.95))
		else:
			_barra_quiero("¡GAS! SIN MÁSCARA", 0.0, Color(1.0, 0.3, 0.2, 0.95))
	if dentro and (not _mascara or _filtro <= 0.0):
		_gas_dano_t -= dt
		if _gas_dano_t <= 0.0:
			_gas_dano_t = 0.6
			if jugador.has_method("take_damage") and not bool(jugador.get("invulnerable")):
				jugador.take_damage(6.0, Vector3.ZERO)
			var ahora := Time.get_ticks_msec() * 0.001
			if ahora - _dano_aviso_t > 3.0:
				_dano_aviso_t = ahora
				_mensaje_local("¡EL AZUFRE TE AHOGA! " + ("Coge una MÁSCARA en la taquilla" if not _mascara else "¡CAMBIA EL FILTRO!"))
	if _mascara_capa:
		_mascara_capa.visible = _mascara and dentro
	if is_instance_valid(_mascara_ruido):
		if _mascara and dentro and not _mascara_ruido.playing:
			_mascara_ruido.play()
		elif not (_mascara and dentro) and _mascara_ruido.playing:
			_mascara_ruido.stop()


func _ponerse_mascara() -> void:
	_mascara = true
	_filtro = float(_c("p06_azufre").get("filtro_s", 45.0))
	_mascara_capa = CanvasLayer.new()
	_mascara_capa.layer = 4
	add_child(_mascara_capa)
	for lado in 4:
		var r := ColorRect.new()
		r.color = Color(0.02, 0.02, 0.02, 0.85)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		match lado:
			0:
				r.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
				r.offset_bottom = 60
			1:
				r.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
				r.offset_top = -80
			2:
				r.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
				r.offset_right = 90
			3:
				r.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
				r.offset_left = -90
		_mascara_capa.add_child(r)
	_mascara_capa.visible = false
	_mascara_ruido = AudioStreamPlayer.new()
	var st = load("res://sounds/gen/mascara/respira1.ogg")
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	_mascara_ruido.stream = st
	_mascara_ruido.volume_db = -8.0
	add_child(_mascara_ruido)
	_mensaje_local("MÁSCARA PUESTA · el filtro dura %d s dentro del gas" % int(_filtro))


# ======================================================================================================
# 7. LA COLADA (las cargas del dique: la lava baja por el pueblo)
# ======================================================================================================
func _montar_p07() -> void:
	var c := _c("p07_colada")
	if c.is_empty():
		return
	var la: Array = c["lago"]
	_lava_plano(la, float(c.get("lago_y", 8.0)) - 0.4)
	var ca: Array = c["cargas"]
	for i in ca.size():
		var d := _diana("carga%d" % i, _v(ca[i]), Vector3(0.7, 0.7, 0.5))
		_caja_mesh(d, Vector3(0.6, 0.5, 0.3), Vector3.ZERO, _mm(Color(0.8, 0.12, 0.08), 0.3, 0.5))
		_esfera_mesh(d, 0.08, Vector3(0, 0.32, -0.16), _brillo(Color(1.0, 0.1, 0.05), 3.0))
	_rotulo("dique", "EL DIQUE DEL LAGO DE LAVA\n3 CARGAS: la lava bajará por el pueblo", _v(ca[1]) + Vector3(0, 3.0, -3.0), COLOR_AVISO)


func _carga_revienta(i: int, ya: bool) -> void:
	if i < 0 or i >= _cargas.size() or bool(_cargas[i]):
		return
	_cargas[i] = true
	var d = _dianas.get("carga%d" % i)
	var p: Vector3 = (d as Node3D).global_position if is_instance_valid(d) else Vector3.ZERO
	if is_instance_valid(d):
		d.set("activa", false)
		d.queue_free()
	_dianas.erase("carga%d" % i)
	if not ya:
		_explosion(p, 2.4, 40.0, 0.0)
		_bola_fuego8(p, 1.6)
		_mensaje_local("CARGA %d DE 3" % _cargas.count(true) if _cargas.count(true) < 3 else "¡EL DIQUE REVIENTA!")


## (el anfitrion) la horda que duerme en el pueblo (la arrasara la colada)
func _pueblo_horda() -> void:
	if _pueblo_dormido:
		return
	_pueblo_dormido = true
	for i in 22:
		var p := Vector3(randf_range(72.0, 100.0), G8 + 0.2, randf_range(26.0, 34.0) if randf() < 0.6 else randf_range(14.0, 48.0))
		var n0 := _vivos.size()
		_sacar("zombi" if randf() < 0.8 else "corredor", p)
		if _vivos.size() > n0 and _vivos.back().has_method("dormir"):
			_vivos.back().dormir()


func _colada_tick(dt: float) -> void:
	var c := _c("p07_colada")
	if c.is_empty():
		return
	var cam: Array = c["camino"]
	var ancho := float(c.get("ancho", 10.0))
	var cx := float(cam[0][0])
	var z_ini := float(cam[0][1])
	var z_fin := float(cam[cam.size() - 1][1])
	if _colada_t >= 0.0:
		_colada_t += dt
		var z := maxf(z_fin, z_ini - _colada_t * 3.2)
		# LO QUE SE LLEVA POR DELANTE: casas, muros y bichos
		while _colada_z_tallado > z:
			_colada_z_tallado -= 0.5
			if world:
				var y := 0.35
				while y < 6.0:
					world.carve_beam(Vector3(cx - ancho / 2.0, G8 + y, _colada_z_tallado), Vector3(1, 0, 0), ancho, 0.45, 255, true)
					y += 0.7
			if _soy_host:
				for cr in _vivos:
					if is_instance_valid(cr) and absf((cr as Node3D).global_position.x - cx) < ancho / 2.0 + 0.5 and \
							(cr as Node3D).global_position.z > _colada_z_tallado - 1.0 and cr.has_method("take_damage"):
						cr.take_damage(99999.0, Vector3(0, 2, -3))
		if is_instance_valid(_colada_plano):
			var largo := maxf(0.5, z_ini - z)
			_colada_plano.scale = Vector3(1.0, 1.0, largo)
			_colada_plano.global_position = Vector3(cx, G8 + 0.22, z_ini - largo / 2.0)
		if is_instance_valid(_colada_ruido):
			_colada_ruido.global_position = Vector3(cx, G8 + 1.0, z)
		if z <= z_fin + 0.01:
			_colada_t = -1.0
			_colada_fria = 0.0
			var costa := Vector3(cx, G8, z_fin)
			Audio.play3d("gen/vapor/siseo", costa, 10.0, 0.0, 150.0, Audio.PRI_TOP)
			var vapor := _particulas(self, costa, 80, 5.0, Color(0.9, 0.9, 0.9, 0.9), Color(0.7, 0.7, 0.7, 0.0), 5.0, false)
			vapor.one_shot = true
			vapor.explosiveness = 0.7
			vapor.direction = Vector3.UP
			vapor.initial_velocity_min = 3.0
			vapor.initial_velocity_max = 8.0
			get_tree().create_timer(6.0).timeout.connect(vapor.queue_free)
			if is_instance_valid(_colada_ruido):
				_colada_ruido.queue_free()
	if _colada_fria >= 0.0 and _colada_fria < 1.0:
		_colada_fria = minf(1.0, _colada_fria + dt / 18.0)
		_lava_enfriar(_colada_plano, _colada_fria)
		if _soy_host and _colada_fria >= 1.0:
			_evento("p07_fria", [])
	# la lava todavia caliente quema
	if is_instance_valid(_colada_plano) and _colada_fria < 0.7:
		var z2 := maxf(z_fin, z_ini - maxf(0.0, _colada_t) * 3.2) if _colada_t >= 0.0 else z_fin
		_quema_lava([cx - ancho / 2.0, z2, cx + ancho / 2.0, z_ini], G8 + 0.22, dt)


func _p07_resuelto(ya: bool) -> void:
	var c := _c("p07_colada")
	var cam: Array = c["camino"]
	var ancho := float(c.get("ancho", 10.0))
	var cx := float(cam[0][0])
	var z_ini := float(cam[0][1])
	var z_fin := float(cam[cam.size() - 1][1])
	var di: Array = c["dique"]
	if world:
		var y := 0.3
		while y < 7.0:
			world.carve_beam(Vector3(float(di[0]) + 0.5, G8 + y, (float(di[1]) + float(di[3])) / 2.0), Vector3(1, 0, 0), float(di[2]) - float(di[0]) - 1.0, 1.4, 255, true)
			y += 1.0
	_colada_plano = _lava_plano([cx - ancho / 2.0, z_ini - 1.0, cx + ancho / 2.0, z_ini], G8 + 0.22)
	if ya:
		_colada_z_tallado = z_ini
		_colada_t = 999.0
		_colada_tick(0.0)
		_colada_fria = 1.0
		_lava_enfriar(_colada_plano, 1.0)
		return
	_colada_t = 0.0
	_colada_ruido = _bucle_directo("res://sounds/gen/colada/avance1.ogg", self, Vector3(cx, G8 + 1, z_ini), 8.0, 90.0)
	var d := Vector3(cx, G8 + 5.0, z_ini)
	for k in 5:
		var kk := k
		get_tree().create_timer(0.15 * kk).timeout.connect(func():
			_explosion(d + Vector3(randf_range(-5, 5), randf_range(-1, 2), 0), 3.0, 60.0, 0.0)
			_bola_fuego8(d + Vector3(randf_range(-5, 5), 0, 0), 2.4))
	var camara := _v(c.get("camara", [66, 16, 44]))
	_corte([[camara, d, 0.0], [camara + Vector3(0, 2, -8), Vector3(cx, G8, 36.0), 4.0], [camara + Vector3(2, 3, -20), Vector3(cx, G8, 16.0), 10.0]], 10.2, "")
	_mensaje_local("¡LA LAVA BAJA POR EL PUEBLO! Apartaos de su camino")


# ======================================================================================================
# 8. EL TUNEL DE LAVA (la lava sube a golpes por el suelo)
# ======================================================================================================
func _montar_p08() -> void:
	var c := _c("p08_tunel")
	if c.is_empty():
		return
	var tr: Array = c["tramos"]
	var w := float(c.get("ancho", 4.0)) / 2.0
	var suelo := float(c.get("suelo", 1.2))
	_tunel_y = suelo - 0.4
	for i in range(tr.size() - 1):
		var a: Array = tr[i]
		var b: Array = tr[i + 1]
		var r := [minf(float(a[0]), float(b[0])) - w, minf(float(a[1]), float(b[1])) - w, maxf(float(a[0]), float(b[0])) + w, maxf(float(a[1]), float(b[1])) + w]
		var p := _lava_plano(r, _tunel_y, i % 2 == 0)
		p.set_meta("rect", r)
		_tunel_planos.append(p)
	_rotulo("tunel", "EL TÚNEL DE LAVA\nla lava sube a golpes: esperad en las ALCOBAS", _v([tr[0][0], suelo + 3.5, tr[0][1] - 1.0]), COLOR_PELIGRO)


## El ciclo (cada maquina con su reloj desde que el anfitrion lo arranca): abajo, avisa, sube, aguanta, baja
func _tunel_tick(dt: float) -> void:
	var c := _c("p08_tunel")
	if c.is_empty() or _tunel_t < 0.0:
		return
	var per := float(c.get("periodo", 11.0))
	var suelo := float(c.get("suelo", 1.2))
	var alta := float(c.get("lava_alta", suelo + 0.7))
	var baja := suelo - 0.4
	_tunel_t += dt
	var t := fposmod(_tunel_t, per)
	var y := baja
	if t > 5.0 and t < 6.2:
		y = lerpf(baja, alta, (t - 5.0) / 1.2)
	elif t >= 6.2 and t < 8.7:
		y = alta
	elif t >= 8.7 and t < 9.9:
		y = lerpf(alta, baja, (t - 8.7) / 1.2)
	_tunel_y = y
	for p in _tunel_planos:
		if is_instance_valid(p):
			(p as Node3D).global_position.y = y
	var cerca := is_instance_valid(jugador) and _en_tunel(jugador.global_position)
	if cerca:
		if t > 3.6 and t < 5.0 and not _tunel_aviso:
			_tunel_aviso = true
			Audio.play3d("gen/tierra/temblor", jugador.global_position + Vector3(0, -2, 0), 4.0, 0.0, 30.0, Audio.PRI_HIGH)
			if jugador.has_method("add_shake"):
				jugador.add_shake(0.35)
			_mensaje_local("¡LA LAVA SUBE! ¡A UNA ALCOBA!")
		if t > 10.0:
			_tunel_aviso = false
		for p in _tunel_planos:
			if is_instance_valid(p):
				_quema_lava(p.get_meta("rect"), y, dt)
		_barra_quiero("TÚNEL DE LAVA · " + ("¡SUBE!" if y > baja + 0.05 else "sube en %d s" % int(ceilf(5.0 - t)) if t < 5.0 else "baja…"),
			1.0 - (y - baja) / (alta - baja), Color(1.0, 0.4, 0.1, 0.95))
	if _soy_host and y > suelo:
		for cr in _vivos:
			if is_instance_valid(cr) and _en_tunel((cr as Node3D).global_position) and (cr as Node3D).global_position.y < y + 0.2 and cr.has_method("take_damage"):
				cr.take_damage(20.0 * dt, Vector3.ZERO)


func _en_tunel(p: Vector3) -> bool:
	for pl in _tunel_planos:
		if is_instance_valid(pl) and _dentro(p, pl.get_meta("rect")):
			return p.y < float(_c("p08_tunel").get("suelo", 1.2)) + 3.0
	return false


# ======================================================================================================
# 9. EL HIDROAVION
# ======================================================================================================
func _montar_p09() -> void:
	var c := _c("p09_hidroavion")
	if c.is_empty():
		return
	var p := _v(c["pos"])
	_hidro = _animable("Hidroavion", p)
	var blanco := _mm(Color(0.9, 0.9, 0.88), 0.3, 0.5)
	var rojo := _mm(Color(0.75, 0.12, 0.1), 0.3, 0.5)
	var cristal := _mm(Color(0.12, 0.16, 0.2), 0.8, 0.1)
	# mirando al oeste (-X): el fuselaje, los flotadores, el ala alta y dos motores
	_caja_mesh(_hidro, Vector3(11.0, 2.4, 2.4), Vector3(0, 2.6, 0), blanco)
	_caja_mesh(_hidro, Vector3(11.1, 0.4, 2.45), Vector3(0, 2.0, 0), rojo)
	_caja_mesh(_hidro, Vector3(1.6, 1.0, 2.2), Vector3(-5.6, 3.0, 0), cristal)
	_caja_mesh(_hidro, Vector3(3.0, 1.8, 0.3), Vector3(5.2, 4.4, 0), rojo)
	_caja_mesh(_hidro, Vector3(2.0, 0.3, 4.0), Vector3(5.2, 3.6, 0), blanco)
	_caja_mesh(_hidro, Vector3(3.0, 0.35, 16.0), Vector3(-1.2, 4.1, 0), blanco)
	for s in [-1.0, 1.0]:
		_caja_mesh(_hidro, Vector3(8.0, 0.8, 0.9), Vector3(-0.5, 0.4, s * 2.4), blanco)
		_caja_mesh(_hidro, Vector3(0.2, 1.6, 0.2), Vector3(-2.0, 1.2, s * 2.0), blanco)
		_caja_mesh(_hidro, Vector3(0.2, 1.6, 0.2), Vector3(1.5, 1.2, s * 2.0), blanco)
		_cil_mesh(_hidro, 0.6, 2.2, Vector3(-2.6, 3.7, s * 3.8), rojo, Vector3(0, 0, PI / 2), 12)
		var h := Node3D.new()
		_hidro.add_child(h)
		h.position = Vector3(-3.8, 3.7, s * 3.8)
		_caja_mesh(h, Vector3(0.1, 3.0, 0.25), Vector3.ZERO, _mm(Color(0.1, 0.1, 0.1), 0.5, 0.5))
		_helices.append(h)
	# por dentro: suelo y paredes (con la puerta al norte, hacia el muelle)
	_colision_caja(_hidro, Vector3(10.0, 0.2, 2.2), Vector3(0, 1.4, 0))
	_colision_caja(_hidro, Vector3(10.0, 2.2, 0.15), Vector3(0, 2.6, 1.15))
	_colision_caja(_hidro, Vector3(8.5, 2.2, 0.15), Vector3(-0.75, 2.6, -1.15))           # la puerta, en la cola (x 3,5..5)
	_colision_caja(_hidro, Vector3(10.0, 0.2, 2.4), Vector3(0, 3.8, 0))
	_texto3d("VULCANOLOGÍA", Vector3(0, 2.8, 1.23), Color(0.75, 0.12, 0.1), 40, false, _hidro, PI)
	# EL PANEL DE ARRANQUE en el costado, justo delante de la puerta (la cara que da al muelle), a la altura de la
	# mano desde la pasarela. Antes el boton salia en el aire. Hijo del hidroavion: se mece con el.
	_mnd_motores = Mandos.crear("arranque", _hidro, Vector3(3.0, 2.45, -1.205), Vector3(0, 0, -1), true)
	# la pasarela del muelle a la puerta
	var mu: Array = c["muelle"]
	var pas := _estatico("PasarelaHidro", Vector3(float(mu[0]) - 1.1, G8 - 0.08, p.z - 1.9))
	_caja_mesh(pas, Vector3(2.8, 0.15, 1.6), Vector3.ZERO, _mm(Color(0.4, 0.3, 0.2), 0.0, 0.9))
	_colision_caja(pas, Vector3(2.8, 0.15, 1.6), Vector3.ZERO)
	_rotulo("hidro", "EL HIDROAVIÓN\narrancad los motores (tardan un minuto)", p + Vector3(0, 6.0, 0), COLOR_AVISO)


func _hidro_tick(dt: float) -> void:
	if not is_instance_valid(_hidro):
		return
	var t := Time.get_ticks_msec() * 0.001
	if not _cine_final_corriendo:
		var p := _v(_c("p09_hidroavion")["pos"])
		_hidro.global_position = p + Vector3(0, sin(t * 0.9) * 0.08, 0)
	var vel := 0.0
	if _calentar_t >= 0.0:
		var s := float(_c("p09_hidroavion").get("calentar_s", 55.0))
		if not _listo:
			_calentar_t = minf(s, _calentar_t + dt)
			if is_instance_valid(jugador) and jugador.global_position.distance_to(_hidro.global_position) < 50.0:
				_barra_quiero("LOS MOTORES SE CALIENTAN · %d s" % int(ceilf(s - _calentar_t)), _calentar_t / s, Color(0.4, 0.9, 1.0, 0.95))
			if _soy_host and _calentar_t >= s:
				_evento("p09_listo", [])
		vel = 10.0 + 30.0 * clampf(_calentar_t / s, 0.0, 1.0)
	for h in _helices:
		if is_instance_valid(h):
			(h as Node3D).rotation.x += vel * dt


func _en_hidro(q: Vector3) -> bool:
	if not is_instance_valid(_hidro):
		return false
	var l := _hidro.global_transform.affine_inverse() * q
	return absf(l.x) < 5.0 and absf(l.z) < 1.1 and l.y > 1.0 and l.y < 3.8


# ======================================================================================================
# LA SALIDA DE CINE: el hidroavion sale de la bahia y despega mientras el volcan revienta
# ======================================================================================================
func _cine_final() -> void:
	if _cine_final_hecha or not is_instance_valid(_hidro):
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
	var p0 := _hidro.global_position
	var mar := p0 + Vector3(-40.0, 0.0, 0.0)
	var cielo := p0 + Vector3(-110.0, 34.0, -20.0)
	var v: Array = cfg.get("volcan", [92, 88, 34, 33])
	var cima := Vector3(float(v[0]), float(v[3]), float(v[1]))
	var planos := [[p0 + Vector3(4.0, 3.0, 12.0), p0 + Vector3(0, 2.5, 0), 0.0],
		[p0 + Vector3(-18.0, 5.0, 14.0), mar + Vector3(0, 2, 0), 5.0],
		[p0 + Vector3(-50.0, 18.0, 30.0), cima, 9.0],
		[p0 + Vector3(-70.0, 30.0, 20.0), cielo, 14.0]]
	_corte(planos, 14.0, "")
	if hud:
		hud.visible = false
	Audio.play3d("gen/hidro/motor", p0, 10.0, 0.0, 300.0, Audio.PRI_TOP)
	var tw := _hidro.create_tween()
	tw.tween_property(_hidro, "global_position", mar, 5.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_hidro, "global_position", cielo, 7.0).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(_hidro, "rotation:z", -0.25, 2.5)
	# LA GRAN ERUPCION
	for k in 7:
		var kk := k
		get_tree().create_timer(3.0 + kk * 1.1).timeout.connect(func(): _erupcion(true))
	var capa := CanvasLayer.new()
	capa.layer = 31
	add_child(capa)
	var titulo := Label.new()
	titulo.text = "EPISODIO 8 COMPLETADO"
	titulo.add_theme_font_size_override("font_size", 58)
	titulo.add_theme_color_override("font_color", Color(1.0, 0.75, 0.5))
	titulo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	titulo.add_theme_constant_override("shadow_offset_y", 3)
	titulo.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.grow_horizontal = Control.GROW_DIRECTION_BOTH
	titulo.modulate.a = 0.0
	capa.add_child(titulo)
	var sub := Label.new()
	sub.text = "…y la isla revienta a vuestra espalda"
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
	_mensaje_local("RADIO: «…estación vulcanológica de la isla: evacuación en HIDROAVIÓN desde la bahía…»")
	if not _soy_host:
		Net.net_campana_pide("estado4")
	elif _en_red:
		_mandar_estado()
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--ir="):
			_ir_a(String(a).substr(5).replace("_", " "))
	if "--volcan8test" in OS.get_cmdline_user_args():
		_prueba8()


## --volcan8test: los nueve seguidos y sin jugar. Es para ver que no se rompe nada.
func _prueba8() -> void:
	jugador.set("invulnerable", true)
	await get_tree().create_timer(2.0).timeout
	print("[volcan8test] inicio · fase %s" % fase)
	_usar_local("camara")
	await get_tree().create_timer(1.0).timeout
	print("[volcan8test] camara · termica %s · p01 %s · fase %s" % [str(_termica), str(_h("p01")), fase])
	# las bombas: al llano
	await _ir_a("llano")
	await get_tree().create_timer(6.0).timeout
	print("[volcan8test] bombas · fase %s · vida %s" % [fase, str(jugador.get("health"))])
	# la torre de agua
	await _ir_a("orilla del rio")
	var pu: Array = _c("p04_torre")["puente"]
	var antes := int(world.contar_voxels(Vector3(float(pu[0]), 2.0, float(pu[1])), Vector3(float(pu[2]), G8, float(pu[3]))))
	for i in 4:
		_diana_host("pata%d" % i, 30.0)
	await get_tree().create_timer(5.0).timeout
	var despues := int(world.contar_voxels(Vector3(float(pu[0]), 2.0, float(pu[1])), Vector3(float(pu[2]), G8, float(pu[3]))))
	print("[volcan8test] torre · p04 %s · costra %d -> %d · fase %s" % [str(_h("p04")), antes, despues, fase])
	# la roca: la solucion del sokoban, empujando desde el lado bueno
	await _ir_a("geiseres")
	var sol := [Vector2i(0, -1), Vector2i(0, -1), Vector2i(0, -1), Vector2i(0, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 0),
		Vector2i(0, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(0, -1), Vector2i(0, -1)]
	for d in sol:
		var rp := _celda_pos(_roca_celda)
		_roca_empuja(rp - Vector3(float(d.x), 0, float(d.y)) * 1.5)
		await get_tree().create_timer(0.6).timeout
	print("[volcan8test] roca · celda %s · encima %s" % [str(_roca_celda), str(_roca_encima_t >= 0.0)])
	await get_tree().create_timer(7.0).timeout
	var de: Array = _c("p05_roca")["derrumbe"]
	var br: Array = _c("p05_roca")["brecha"]
	print("[volcan8test] geiser · p05 %s · derrumbe en la brecha %d voxels · fase %s" % [str(_h("p05")),
		int(world.contar_voxels(Vector3(float(br[0]) + 1.0, G8 + 0.3, float(de[1])), Vector3(float(br[1]) - 1.0, G8 + 3.0, float(de[3])))), fase])
	# las mascaras
	await _ir_a("taquilla")
	_usar_local("mascara")
	jugador.global_position = Vector3(126.0, G8 + 0.3, 26.0)
	await get_tree().create_timer(3.0).timeout
	print("[volcan8test] azufre · mascara %s · filtro %.1f · vida %s" % [str(_mascara), _filtro, str(jugador.get("health"))])
	# la colada
	await _ir_a("pueblo")
	await get_tree().create_timer(1.0).timeout
	for i in 3:
		_diana_host("carga%d" % i, 30.0)
	await get_tree().create_timer(18.0).timeout
	print("[volcan8test] colada · p07 %s · fila de casas %d voxels · fase %s" % [str(_h("p07")),
		int(world.contar_voxels(Vector3(85.0, G8 + 0.5, 14.0), Vector3(91.0, G8 + 3.0, 48.0))), fase])
	await get_tree().create_timer(18.0).timeout
	print("[volcan8test] enfriada · fase %s" % fase)
	# el tunel
	await _ir_a("tunel")
	await get_tree().create_timer(8.0).timeout
	print("[volcan8test] tunel · ciclo %.1f · lava %.2f · fase %s" % [_tunel_t, _tunel_y, fase])
	# el hidroavion
	_c("p09_hidroavion")["calentar_s"] = 3.0
	await _ir_a("muelle")
	await get_tree().create_timer(1.0).timeout
	_pide_extra("p09_motores")
	await get_tree().create_timer(4.5).timeout
	jugador.global_position = _hidro.global_transform * Vector3(0, 1.6, 0)
	await get_tree().create_timer(3.0).timeout
	print("[volcan8test] hidro · listo %s · a bordo %s · fase %s · terminado %s" % [str(_listo), str(_en_hidro(jugador.global_position)), fase, str(terminado)])
	await get_tree().create_timer(17.0).timeout
	print("[volcan8test] fin · cine hecha %s · vida %s" % [str(_cine_final_hecha), str(jugador.get("health"))])
	get_tree().quit()


func _ir_a(nombre: String) -> void:
	var i := _indice_de(nombre)
	if i >= ruta.size() or not _soy_host:
		return
	var orden := [["p01", "ceniza"], ["p02", "llano"], ["p03", "orilla del rio"], ["p04", "otra orilla"], ["p05", "brecha"],
		["p06", "fin del azufre"], ["p07", "calle mayor"], ["p08", "bahia"]]
	for po in orden:
		if i >= _indice_de(String(po[1])):
			if String(po[0]) in ["p04", "p05", "p07"]:
				_resolver8(String(po[0]), true)
			else:
				hecho[String(po[0])] = true
	progreso = i
	fase = _fase_por_hecho8()
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
	print("[campana8] --ir=%s: fase %s" % [nombre, fase])


func _fase_por_hecho8() -> String:
	for k in ["p01", "p02", "p03", "p04", "p05", "p06", "p07"]:
		if not _h(k):
			return k
	if progreso < _indice_de("patio de la estacion"):
		return "camino_refugio"
	if not _h("p08"):
		return "p08"
	if not _listo:
		return "p09"
	return "subir"


# ======================================================================================================
# CADA CUADRO
# ======================================================================================================
func _process_sin_medir(dt: float) -> void:
	super._process_sin_medir(dt)
	_barra_pide = []
	_rotulos_tick(dt)
	_volcan_tick(dt)
	_globo_tick(dt)
	_ceniza_tick(dt)
	_roca_encima_tick(dt)
	_geiseres_tick(dt)
	_azufre_tick(dt)
	_colada_tick(dt)
	_tunel_tick(dt)
	_hidro_tick(dt)
	_mnd_tick()
	var rio: Array = _c("p04_torre").get("rio", [])
	if not rio.is_empty() and not (_h("p04") and is_instance_valid(jugador) and _dentro(jugador.global_position, _c("p04_torre")["puente"])):
		_quema_lava(rio, float(_c("p04_torre").get("lava_y", 1.4)), dt)
	if _barra_pide.is_empty():
		_barra("", 0.0, Color.WHITE)
	else:
		_barra(String(_barra_pide[0]), float(_barra_pide[1]), _barra_pide[2])
	if (_en_red and not _soy_host) or terminado or world == null:
		return
	_bombas_host_tick(dt)
	_final_tick8(dt)
	_bots_t -= dt
	if _bots_t <= 0.0:
		_bots_t = 2.0
		_bots_al_dia()
	_comprobar_t8 -= dt
	if _comprobar_t8 > 0.0:
		return
	_comprobar_t8 = 0.3
	if fase == "p02" and progreso >= _indice_de("llano"):
		hecho["p02"] = true
	if fase == "p03" and progreso >= _indice_de("orilla del rio"):
		hecho["p03"] = true
	if fase == "p06" and progreso >= _indice_de("fin del azufre"):
		hecho["p06"] = true
	if fase == "p08" and progreso >= _indice_de("bahia"):
		hecho["p08"] = true
	if fase == "p08" and _tunel_t < 0.0 and progreso >= _indice_de("tunel"):
		_evento("p08_empieza", [])


func _final_tick8(dt: float) -> void:
	if (fase == "p09" and _calentar_t >= 0.0) or fase == "subir":
		_tanda_final8 -= dt
		if _tanda_final8 <= 0.0:
			_tanda_final8 = 10.0
			if _cola.size() < 8:
				_horda(9, "")
		if not _final_tank8:
			_final_tank8 = true
			_cola.push_front("tanque")
			_mensaje("¡UN TANK EN LA BAHÍA!")


# ======================================================================================================
# LA HISTORIA (el anfitrion)
# ======================================================================================================
const TEXTOS8 := {
	"p01": "LA CABAÑA · coged una CÁMARA TÉRMICA: en la ceniza no se ve nada sin ella",
	"p02": "LA NUBE DE CENIZA · seguid los MOJONES calientes (la cámara los ve de lejos)",
	"p03": "EL LLANO · ¡BOMBAS! Cuando veáis la marca roja, apartaos · el abrigo de hormigón protege",
	"p04": "EL RÍO DE LAVA · derribad la TORRE DE AGUA sobre el río (sus 4 patas)",
	"p05": "LOS GÉISERES · empujad la ROCA hasta la boca del GÉISER GRANDE: la lanzará contra el derrumbe",
	"p06": "EL VALLE DEL AZUFRE · coged una MÁSCARA en la taquilla y cambiad el FILTRO en las cajas",
	"p07": "EL PUEBLO · la fila de casas no deja pasar: reventad el DIQUE (3 cargas) y que baje la lava",
	"enfriando": "LA COLADA · esperad a que la lava se enfríe (se pone negra) para cruzar",
	"camino_refugio": "¡Pasad por la colada fría! A la ESTACIÓN (refugio)",
	"p08": "EL TÚNEL DE LAVA · la lava sube a golpes: esperad en las ALCOBAS altas",
	"p09": "EL HIDROAVIÓN · arrancad los MOTORES: tardan un minuto en calentarse. ¡AGUANTAD!",
	"subir": "¡TODOS AL HIDROAVIÓN! (la puerta, por la pasarela del muelle)",
}


func _historia() -> void:
	match fase:
		"inicio":
			_poner_fase("p01", TEXTOS8["p01"])
		"p01":
			if _h("p01"):
				_poner_fase("p02", TEXTOS8["p02"])
		"p02":
			if _h("p02"):
				_poner_fase("p03", TEXTOS8["p03"])
		"p03":
			if _h("p03"):
				_poner_fase("p04", TEXTOS8["p04"])
		"p04":
			if _h("p04"):
				_poner_fase("p05", TEXTOS8["p05"])
		"p05":
			if _h("p05"):
				_poner_fase("p06", TEXTOS8["p06"])
		"p06":
			if _h("p06"):
				_poner_fase("p07", TEXTOS8["p07"])
				_pueblo_horda()
		"p07":
			if _h("p07"):
				_poner_fase("enfriando", TEXTOS8["enfriando"])
		"enfriando":
			if _colada_fria >= 1.0:
				_poner_fase("camino_refugio", TEXTOS8["camino_refugio"])
		"camino_refugio":
			var ref: Dictionary = _c("refugio")
			if not ref.is_empty() and _todos_dentro(ref["rect"], float(ref.get("suelo", 0.0)) - 1.0):
				_poner_fase("refugio", "")
				_llegar_al_refugio()
		"refugio":
			if progreso >= _indice_de("patio de la estacion"):
				_poner_fase("p08", TEXTOS8["p08"])
		"p08":
			if _h("p08"):
				_poner_fase("p09", TEXTOS8["p09"])
		"p09":
			if _listo:
				_poner_fase("subir", TEXTOS8["subir"])
		"subir":
			var vivos := _jugadores_vivos()
			var dentro := 0
			for pl in vivos:
				if _en_hidro((pl as Node3D).global_position):
					dentro += 1
			_texto = "¡TODOS AL HIDROAVIÓN! · %d de %d a bordo" % [dentro, vivos.size()]
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
	_texto = "REFUGIO · vida y munición repuestas · la puerta SUR se abre en 10 s"
	_objetivo(_texto)


func _objetivo_punto() -> Array:
	var sig := func(tope: String) -> Vector3:
		var i := mini(progreso + 1, _indice_de(tope))
		return ruta[clampi(i, 0, ruta.size() - 1)]
	match fase:
		"inicio", "p01":
			return [_v(_c("p01_camara")["camara"]) + Vector3.UP, "CÁMARA TÉRMICA"]
		"p02":
			return [sig.call("llano"), "LOS MOJONES"]
		"p03":
			return [sig.call("orilla del rio"), "EL RÍO"]
		"p04":
			return [_torre.global_position + Vector3(0, 2, 0) if is_instance_valid(_torre) else ruta[progreso], "TORRE DE AGUA"]
		"p05":
			if is_instance_valid(_roca):
				return [_roca.global_position + Vector3(0, 2.2, 0), "LA ROCA"]
		"p06":
			if not _mascara:
				return [_v(_c("p06_azufre")["taquilla"]) + Vector3.UP, "MÁSCARAS"]
			return [sig.call("fin del azufre"), "SALIDA DEL VALLE"]
		"p07":
			for i in _cargas.size():
				if not bool(_cargas[i]):
					return [_v(_c("p07_colada")["cargas"][i]), "CARGA %d DEL DIQUE" % (i + 1)]
		"enfriando", "camino_refugio":
			return [sig.call("refugio"), "LA ESTACIÓN"]
		"refugio":
			var ps = _c("refugio").get("puerta_salida", null)
			return [_v([ps[0], G8, ps[1]]) if ps != null else ruta[progreso], "SALIDA DEL REFUGIO"]
		"p08":
			return [sig.call("bahia"), "SALIDA DEL TÚNEL"]
		"p09", "subir":
			if is_instance_valid(_hidro):
				return [_hidro.global_position + Vector3(4.0, 3.0, 0), "HIDROAVIÓN"]
	return [Vector3.INF, ""]


func _tope_ruta() -> int:
	var cierres := [["p04", "otra orilla"], ["p05", "brecha"], ["p07", "calle mayor"]]
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


## Los pilotos de este episodio siguiendo al estado (cada fotograma). Las mascaras son de cada uno: su piloto se
## pone verde cuando YO llevo la mia.
func _mnd_tick() -> void:
	_mnd_luz(_mnd_mascaras, "hecho" if _mascara else "espera")
	_mnd_luz(_mnd_roca, "apagado" if _h("p05") else "espera")
	_mnd_luz(_mnd_motores, "hecho" if _calentar_t >= 0.0 else "espera")


## La palanca de recolocar la roca se usa muchas veces: baja y, al rato, vuelve arriba
func _palanca_ida_vuelta(m: Node3D) -> void:
	if not is_instance_valid(m) or not m.has_meta("brazo"):
		return
	Mandos.accionar(m, false)
	var tw := m.create_tween()
	tw.tween_interval(0.9)
	tw.tween_property(m.get_meta("brazo"), "rotation:x", 0.4, 0.6).set_trans(Tween.TRANS_SINE)


# ======================================================================================================
# LO QUE SE USA
# ======================================================================================================
func _usables_extra(f: String) -> void:
	if terminado:
		return
	var jp: Vector3 = jugador.global_position if is_instance_valid(jugador) else Vector3.ZERO
	if not _termica:
		_u("local:camara", _v(_c("p01_camara")["camara"]) + Vector3(0, 1.0, 0), "COGER UNA CÁMARA TÉRMICA", 2.4)
	if not _mascara:
		_u("local:mascara", _mnd_donde(_mnd_mascaras, Vector3(0, 0.05, 0.18), _v(_c("p06_azufre")["taquilla"]) + Vector3(0, 1.3, -0.5)),
			"COGER UNA MÁSCARA DE GAS", 2.6)
	else:
		for cj in _c("p06_azufre").get("cajas", []):
			if jp.distance_to(_v(cj)) < 2.4:
				_u("local:filtro", _v(cj) + Vector3(0, 0.98, 0), "CAMBIAR EL FILTRO", 2.4)
	if f == "p05" and is_instance_valid(_roca) and jp.distance_to(_roca.global_position + Vector3(0, 0.9, 0)) < 2.6 and _roca_encima_t < 0.0:
		_u("p05_empuja", _roca.global_position + Vector3(0, 1.4, 0), "EMPUJAR LA ROCA", 2.8)
	if f == "p05":
		_u("p05_recolocar", _mnd_donde(_mnd_roca, Vector3(0, 0.15, 0.15), _v(_c("p05_roca")["palanca"]) + Vector3(0, 1.1, -0.3)),
			"RECOLOCAR LA ROCA (volver a empezar)")
	if f == "p09" and _calentar_t < 0.0 and is_instance_valid(_hidro):
		_u("p09_motores", _mnd_donde(_mnd_motores, Vector3(0.09, 0.04, 0.15), _hidro.global_transform * Vector3(3.0, 2.45, -1.4)), "ARRANCAR LOS MOTORES", 3.5)


func _usar_local(que: String) -> void:
	match que:
		"camara":
			if not _termica:
				_termica_encender()
				_pedir("p01_tengo")
		"mascara":
			if not _mascara:
				_ponerse_mascara()
		"filtro":
			_filtro = float(_c("p06_azufre").get("filtro_s", 45.0))
			Audio.bf3d("gadget/c4_coger", jugador.global_position if is_instance_valid(jugador) else Vector3.ZERO, 0.0, 20.0, Audio.PRI_MID)
			_mensaje_local("FILTRO NUEVO")


func _pide_extra(accion: String) -> void:
	var de := _pide_de
	if accion.begins_with("diana:"):
		var partes := accion.split(":")
		if partes.size() >= 3:
			_diana_host(partes[1], float(partes[2]))
		return
	match accion:
		"p01_tengo":
			if not _h("p01"):
				hecho["p01"] = true
		"p05_empuja":
			var q := _nodo_de(de)
			if q != null:
				_roca_empuja(q.global_position)
		"p05_recolocar":
			if not _h("p05") and _roca_encima_t < 0.0:
				_evento("p05_recoloca", [])
				var ini: Array = _c("p05_roca")["inicio"]
				_evento("p05_mueve", [int(ini[0]), int(ini[1])])
		"p09_motores":
			if fase == "p09" and _calentar_t < 0.0:
				_evento("p09_motores", [])


## El anfitrion decide que pasa cuando le dan a una diana
func _diana_host(id: String, _dano: float) -> void:
	if id.begins_with("bidon"):
		_evento("bidon", [int(id.substr(5))])
	elif id.begins_with("pata"):
		var i := int(id.substr(4))
		if i < 0 or i >= _patas.size() or bool(_patas[i]):
			return
		_evento("p04_pata", [i])
		if _patas.count(true) >= 4 and not _h("p04"):
			get_tree().create_timer(0.6).timeout.connect(func(): _evento("p04", []))
	elif id.begins_with("carga"):
		var i := int(id.substr(5))
		if i < 0 or i >= _cargas.size() or bool(_cargas[i]):
			return
		_evento("p07_carga", [i])
		if _cargas.count(true) >= 3 and not _h("p07"):
			get_tree().create_timer(1.0).timeout.connect(func(): _evento("p07", []))


func _evento_extra(e: String, datos: Array) -> void:
	match e:
		"fase4":
			if not _soy_host:
				fase = String(datos[0])
		"estado4":
			_aplicar_estado(String(datos[0]))
		"bidon":
			_bidon_revienta(int(datos[0]), false)
		"p03_bomba":
			_bomba_marca(float(datos[0]), float(datos[1]))
		"p04_pata":
			_pata_rota(int(datos[0]), false)
		"p05_mueve":
			_roca_celda = Vector2i(int(datos[0]), int(datos[1]))
			_roca_colocar(false)
		"p05_recoloca":
			_palanca_ida_vuelta(_mnd_roca)
		"p05_no":
			_mensaje_local("La roca no se mueve: hay algo al otro lado")
		"p05_encima":
			_roca_encima_t = 0.0
			_mensaje_local("¡LA ROCA TAPA EL GÉISER! Apartaos… va a reventar")
			Audio.play3d("gen/tierra/temblor", _roca.global_position if is_instance_valid(_roca) else Vector3.ZERO, 4.0, 0.0, 60.0, Audio.PRI_HIGH)
		"p07_carga":
			_carga_revienta(int(datos[0]), false)
		"p07_fria":
			_colada_fria = 1.0
			_lava_enfriar(_colada_plano, 1.0)
			_mensaje_local("LA COLADA SE HA ENFRIADO: ya se puede cruzar")
		"p08_empieza":
			_tunel_t = 0.0
		"p09_motores":
			_calentar_t = 0.0
			_mnd_accionar(_mnd_motores)
			_hidro_ruido = _bucle_directo("res://sounds/gen/hidro/motor1.ogg", _hidro, Vector3(-3.0, 3.7, 0), 2.0, 80.0)
			_mensaje_local("¡LOS MOTORES ARRANCAN! Un minuto para que se calienten: ¡AGUANTAD!")
		"p09_listo":
			_listo = true
			_mensaje_local("¡MOTORES LISTOS! ¡TODOS AL HIDROAVIÓN!")
		_:
			if e.length() == 3 and e.begins_with("p"):
				_resolver8(e, false)


func _on_evento(e: String, datos: Array) -> void:
	super._on_evento(e, datos)
	if e == "escapan":
		_cine_final()
