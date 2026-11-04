extends Node3D
## EL ARMA EN LAS MANOS. Catorce armas de fuego modeladas en Blender (tools/blender/armas/) y
## exportadas a res://armas/<id>.glb, mas tres piezas que siguen siendo de codigo: el mazo, la C4 y
## el fusil laser.
##
## SE ACABARON LOS ACCESORIOS. Antes el arma nacia pelada y le montabas mira, boquilla, mango y
## cargador desde un taller; eso obligaba a que todas las armas fueran el mismo modelo parametrico
## con un riel encima, y ninguna tenia personalidad. Ahora CADA ARMA TRAE LA SUYA soldada de fabrica
## -diopter, punto rojo, holografica, prisma, telescopica, el PGO del RPG, o simples miras de
## hierro- y esa mira es parte del modelo.
##
## El arma apunta hacia -Z. Los puntos de sujecion y punteria NO se miden aqui: salen de
## res://armas/armas.json, que escribe el mismo script de Blender que modela el arma. Asi lo que se
## ve en Blender y lo que se apunta en el juego son lo mismo, sin numeros copiados a mano.
##   `sight_pos`   eje optico de la mira: el juego lo pone en el eje de la camara al apuntar
##   `muzzle_pos`  la boca de verdad, accesorio incluido: de ahi salen fogonazo, humo y traza
##   `grip_pos` / `foregrip_pos` donde agarran las dos manos

const ARMAS_DIR := "res://armas/"

var sight_pos := Vector3(0, 0.086, -0.13)
var muzzle_pos := Vector3(0, 0.012, -0.71)
var flash: GPUParticles3D          ## el fogonazo (atlas animado, ver shaders/fogonazo.gdshader)
var flash_gas: GPUParticles3D      ## el gas caliente que sale detras
var flash_light: OmniLight3D
var flash_t := 0.0
var reticle: Node3D                ## la reticula de la optica (emisiva, se ve al encarar)

var m_metal: StandardMaterial3D
var m_dark: StandardMaterial3D
var m_polymer: StandardMaterial3D
var m_tan: StandardMaterial3D
var m_glass: StandardMaterial3D
var m_reticle: StandardMaterial3D
var m_rubber: StandardMaterial3D

var kind := "rifle"                  # "rifle" | "shotgun" | "rocket" | "pistol" | "smg" | "sniper" | "sledge" | "c4" | "laser"
var arma_id := ""                    # id del catalogo: carga res://armas/<id>.glb
var one_handed := false              # pistola / C4: la otra mano no sujeta el arma
var rear_z := 0.28                   # m: cuánto sobresale la culata por detrás del origen
var ads_dist := 0.0                  # m: distancia de la mira a la camara al apuntar (0 = la de su tipo, en player.gd)
## m: la misma EN EL MOVIL (0 = la mitad de ads_dist, player._mira_cerca). Aqui y no en armas.json, que lo escribe la
## exportacion de Blender.
var ads_dist_movil := 0.0
## LAS MIRAS QUE EN EL MOVIL QUEDABAN PEGADAS AL OJO (2026-10-01, revisadas foto a foto con el usuario): con la mitad de la
## distancia del PC la carcasa de la holografica del bullpup, el punto rojo de la PDW y el de la escopeta automatica
## tapaban la pantalla, y la pistola .45 iba algo justa. Estas van a su distancia propia en el movil (m).
const ADS_MOVIL := {"fusil_bullpup": 0.15, "pdw_57": 0.14, "escopeta_auto": 0.13, "pistola_45": 0.08}
## Las que llevan el punto de mira delantero con la puntita verde (`_poner_mira_delantera`)
const MIRA_DELANTERA := ["pistola_9"]
const MIRA_DELANTERA_ALTO := 0.009       ## m por encima del eje de la mira: asi asoma entre las dos muescas del alza (con menos la tapa la corredera)
var grip_pos := Vector3(0.0, -0.075, 0.03)      # empuñadura (mano del gatillo), en metros del modelo
var foregrip_pos := Vector3(0.0, -0.045, -0.30) # apoyo de la otra mano
var fp_foregrip_pos := Vector3(0.0, -0.045, -0.14) # ídem en primera persona (brazos reales, sin estirar)
var fogonazo := 1.0                  # 1 = normal; un arma silenciada apenas destella
## EL CARGADOR VA APARTE, sin fundirse con el resto del arma: en la recarga animada del avatar sale
## del pozo, cae al suelo y entra uno nuevo. Su origen es el punto que asienta en el pozo.
var cargador: Node3D = null
var cargador_asiento := Vector3.ZERO
const CARGADOR_ASIENTO := Vector3(0.0, -0.0451, -0.0512)   # respaldo para armas sin ficha

static var _ficha: Dictionary = {}


## La ficha de las catorce armas: puntos de sujecion y punteria, tal como salieron de Blender.
## LAS ESCENAS DE LAS ARMAS SE QUEDAN EN MEMORIA (2026-10-01, medido en la cafeteria con bots: reaparecer un bot
## con un arma que nadie llevaba costaba 178 ms en el hilo principal, cargando el .glb en plena partida, y cuando
## moria el ultimo que la llevaba Godot la soltaba y la siguiente vez la volvia a leer del disco). `pedir_en_hilos`
## las encarga al empezar la carga del mapa; `escena` las da sin tocar el disco si ya estan.
static var _escenas: Dictionary = {}     # id -> PackedScene
static var _pedidas: Dictionary = {}     # id -> ruta encargada en un hilo y aun sin recoger

static func escena(id: String) -> PackedScene:
	var ps: PackedScene = _escenas.get(id)
	if ps != null:
		return ps
	var ruta: String = ARMAS_DIR + id + ".glb"
	if _pedidas.has(id):
		_pedidas.erase(id)
		ps = ResourceLoader.load_threaded_get(ruta) as PackedScene   # espera solo si aun no ha acabado
	if ps == null:
		ps = load(ruta) as PackedScene
	if ps != null:
		_escenas[id] = ps
	return ps

static func pedir_en_hilos(ids: Array) -> void:
	for i in ids:
		var id := String(i)
		var ruta: String = ARMAS_DIR + id + ".glb"
		if id == "" or _escenas.has(id) or _pedidas.has(id) or not ResourceLoader.exists(ruta):
			continue
		if ResourceLoader.load_threaded_request(ruta) == OK:
			_pedidas[id] = ruta

## Las que ya acabaron en su hilo pasan a la memoria (sin esperar a las demas).
static func recoger_pedidas() -> void:
	for id in _pedidas.keys():
		if ResourceLoader.load_threaded_get_status(String(_pedidas[id])) == ResourceLoader.THREAD_LOAD_LOADED:
			escena(String(id))

static func ficha() -> Dictionary:
	if _ficha.is_empty():
		var f := FileAccess.open(ARMAS_DIR + "armas.json", FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if typeof(d) == TYPE_DICTIONARY:
				_ficha = d
	return _ficha


static func hay_modelo(id: String) -> bool:
	return ficha().has(id)


static func _v3(a, por_defecto: Vector3) -> Vector3:
	if typeof(a) != TYPE_ARRAY or (a as Array).size() < 3:
		return por_defecto
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _ready() -> void:
	var _tr := Time.get_ticks_usec()
	_materials()
	Prof.add("wm.materiales", Time.get_ticks_usec() - _tr)
	_tr = Time.get_ticks_usec()
	_build()
	Prof.add("wm.build", Time.get_ticks_usec() - _tr)
	_tr = Time.get_ticks_usec()
	_colocar_fogonazo()
	Prof.add("wm.fogonazo", Time.get_ticks_usec() - _tr)
	_tr = Time.get_ticks_usec()
	_bake_static()
	Prof.add("wm.bake", Time.get_ticks_usec() - _tr)
	# solo procesa mientras dura el destello de un disparo (fire_flash lo enciende): con 18 armas en escena eran
	# 18 llamadas por fotograma para no hacer nada
	set_process(false)


# ---------------------------------------------------------------------------
# EL MODELO DE BLENDER
# ---------------------------------------------------------------------------
func _build() -> void:
	if kind == "escudo":
		_build_escudo()
		return
	if arma_id != "" and ficha().has(arma_id):
		_build_glb()
		_build_flash()
		return
	match kind:
		"c4":
			_build_c4()
		"laser":
			_build_laser()
		"sledge":
			_build_sledge()
		_:
			# arma sin modelo (no deberia pasar): un tocho para que se vea que falta algo.
			# EL AVISO ES LO IMPORTANTE. Este caso saltaba callado, asi que un id mal escrito o una
			# llamada sin id ponia un PALO en las manos del personaje y no habia forma de saber por
			# que: parecia un problema de la animacion y era el modelo que no se habia encontrado.
			push_warning("[arma] SIN MODELO: kind=%s arma_id='%s' -> palo de relleno. %s" % [
				kind, arma_id,
				"el id no esta en armas.json" if arma_id != "" else "se llamo a equip_weapon SIN id"])
			print("[arma] SIN MODELO: kind=%s arma_id='%s'" % [kind, arma_id])
			_box(Vector3(0.06, 0.06, 0.5), Vector3(0, 0, -0.2), m_dark)
			_build_flash()


## ESCUDO BALISTICO + PISTOLA (escudo.gd). Este nodo es la PISTOLA, que es lo que dispara y lo que agarra la
## mano del gatillo; el escudo nace como hijo `escudo_nodo` y quien lo lleva (avatar o camara) lo saca de
## aqui y lo mueve por su cuenta: no va pegado a la pistola, cada uno tiene su mano y su animacion.
var escudo_nodo: Node3D = null

func _build_escudo() -> void:
	_build_glb(preload("res://scripts/escudo.gd").PISTOLA)
	_build_flash()
	one_handed = false
	escudo_nodo = preload("res://scripts/escudo.gd").modelo()
	add_child(escudo_nodo)


func _build_glb(id: String = "") -> void:
	if id == "":
		id = arma_id
	if not ficha().has(id):
		return
	var d: Dictionary = ficha()[id]
	var ps := escena(id)
	if ps == null:
		push_warning("[arma] no carga %s.glb" % id)
		return
	var _tg := Time.get_ticks_usec()
	var raiz := ps.instantiate() as Node3D
	raiz.name = "Modelo"
	add_child(raiz)
	Prof.add("arma.instanciar", Time.get_ticks_usec() - _tg)
	for hijo in raiz.get_children():
		if hijo is GeometryInstance3D:
			(hijo as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if hijo.name.begins_with("Cargador"):
			cargador = hijo as Node3D
		elif hijo.name.begins_with("Cristal"):
			(hijo as MeshInstance3D).material_override = m_glass
		elif hijo.name.begins_with("Reticula"):
			(hijo as MeshInstance3D).material_override = m_reticle
			reticle = hijo as Node3D
	# LA SKIN, si la hay: se pinta ENCIMA del modelo recien montado, sin tocar el .glb (skins_armas.gd).
	_tg = Time.get_ticks_usec()
	_pintar_skin(raiz)
	Prof.add("arma.pintar", Time.get_ticks_usec() - _tg)
	grip_pos = _v3(d.get("grip"), grip_pos)
	foregrip_pos = _v3(d.get("foregrip"), foregrip_pos)
	fp_foregrip_pos = _v3(d.get("fp_foregrip"), fp_foregrip_pos)
	sight_pos = _v3(d.get("sight"), sight_pos)
	muzzle_pos = _v3(d.get("muzzle"), muzzle_pos)
	cargador_asiento = _v3(d.get("mag_seat"), CARGADOR_ASIENTO)
	one_handed = bool(d.get("mano", false))
	rear_z = float(d.get("rear_z", 0.3))
	ads_dist = float(d.get("ads_dist", 0.0))
	ads_dist_movil = float(ADS_MOVIL.get(id, 0.0))
	if id in MIRA_DELANTERA:
		_poner_mira_delantera(raiz)
	fogonazo = float(d.get("fogonazo", 1.0))
	if one_handed:
		foregrip_pos = grip_pos
		fp_foregrip_pos = grip_pos


## LA SKIN DEL ARMA. La pintura va por `set_surface_override_material`, asi que el modelo y la malla son
## los mismos de siempre: lo unico que cambia es con que material se dibuja cada pieza. Si el arma no
## lleva skin puesta, no se toca nada.
##
## `skin_forzada` existe para los retratos de la tienda: enseñar una skin que todavia no llevas puesta.
var skin_forzada := ""
var skin_puesta := ""        # la que lleva pintada AHORA el modelo ya montado ("" = ninguna)
var _raiz_pintable: Node = null   # la raiz del .glb, para poder repintar sin rehacer el arma

func _pintar_skin(raiz: Node) -> void:
	_raiz_pintable = raiz
	var id := skin_forzada
	if id == "":
		id = SkinsArmas.equipada(arma_id)
	elif id == "-":
		id = ""   # forzada a SIN pintura (los bots sin skin: no heredan la del jugador)
	skin_puesta = id
	if id == "":
		return
	SkinsArmas.aplicar(raiz, id)


## Repinta el arma si la skin equipada ha cambiado desde que se monto el modelo.
##
## Hace falta porque el MUÑECO (tercera persona, y lo que ven los demas) no rehace el arma cuando el
## tipo y el id son los mismos —y al cambiar de skin lo son—, asi que se quedaba con la pintura vieja
## o directamente sin pintar. Repintar cuesta un puñado de `set_surface_override_material`: nada que
## ver con rehacer el modelo.
func repintar_skin() -> bool:
	if _raiz_pintable == null or not is_instance_valid(_raiz_pintable):
		return false
	var id := skin_forzada
	if id == "":
		id = SkinsArmas.equipada(arma_id)
	elif id == "-":
		id = ""   # forzada a SIN pintura (los bots sin skin: no heredan la del jugador)
	if id == skin_puesta:
		return false
	SkinsArmas.limpiar(_raiz_pintable)
	skin_puesta = id
	if id != "":
		SkinsArmas.aplicar(_raiz_pintable, id)
	return true


## Fusiona las primitivas estáticas de las armas de código (mazo, C4, láser) en UNA malla con una
## superficie por material. Las armas de Blender ya vienen fundidas de fábrica y no pasan por aquí.
func _bake_static() -> void:
	var tools := {}      # Material -> SurfaceTool
	var order: Array[Material] = []
	var to_free: Array[Node] = []
	_collect_static(self, Transform3D.IDENTITY, tools, order, to_free)
	var merged := ArrayMesh.new()
	for m in order:
		(tools[m] as SurfaceTool).commit(merged)
	if merged.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Baked"
	mi.mesh = merged
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	for n in to_free:
		n.queue_free()

func _collect_static(node: Node, xf: Transform3D, tools: Dictionary, order: Array[Material], to_free: Array[Node]) -> void:
	for ch in node.get_children():
		if ch == reticle or ch == flash or ch == flash_gas or ch == flash_light or ch == cargador or ch == escudo_nodo:
			continue
		if ch is MeshInstance3D:
			var mi := ch as MeshInstance3D
			var m := mi.material_override as StandardMaterial3D
			if m and mi.mesh and m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				if not tools.has(m):
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					st.set_material(m)
					tools[m] = st
					order.append(m)
				var t := xf * mi.transform
				for srf in mi.mesh.get_surface_count():
					(tools[m] as SurfaceTool).append_from(mi.mesh, srf, t)
				to_free.append(mi)
				continue
		if ch is Node3D:
			_collect_static(ch, xf * (ch as Node3D).transform, tools, order, to_free)

func _mat(color: Color, metallic: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	m.metallic_specular = 0.6
	return m

func _materials() -> void:
	m_metal = _mat(Color(0.32, 0.33, 0.36), 0.9, 0.32)      # acero pavonado
	m_dark = _mat(Color(0.09, 0.09, 0.1), 0.7, 0.45)         # aluminio anodizado negro
	m_polymer = _mat(Color(0.12, 0.12, 0.13), 0.05, 0.72)    # polímero
	m_tan = _mat(Color(0.45, 0.38, 0.27), 0.05, 0.8)         # polímero arena
	m_rubber = _mat(Color(0.06, 0.06, 0.06), 0.0, 0.95)
	m_glass = StandardMaterial3D.new()
	m_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_glass.albedo_color = Color(0.55, 0.75, 1.0, 0.22)
	m_glass.metallic = 0.6
	m_glass.roughness = 0.05
	m_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	m_reticle = StandardMaterial3D.new()
	m_reticle.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# SEMITRANSPARENTE (2026-09-23, pedido): el punto opaco y brillante tapaba lo que habia detras al apuntar
	# a algo pequeño o lejos. Al 55 % y con la mitad de brillo se sigue viendo y deja ver el blanco.
	m_reticle.albedo_color = Color(1.0, 0.15, 0.1, 0.55)
	m_reticle.emission_enabled = true
	m_reticle.emission = Color(1.0, 0.2, 0.1)
	m_reticle.emission_energy_multiplier = 3.0
	m_reticle.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# LA RETICULA SE DIBUJA SIEMPRE ENCIMA. Es lo unico del arma que tiene que salir nitido pase lo
	# que pase: si la tapa el cristal de la propia optica o la traga el desenfoque, apuntar deja de
	# funcionar. Son dos milimetros de punto, asi que verla a traves de una pared no delata a nadie.
	m_reticle.no_depth_test = true
	m_reticle.render_priority = 5

func _box(size: Vector3, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else self).add_child(mi)
	return mi

func _cyl(r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3(90, 0, 0)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = 20
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## MAZO, calcado del de Teardown (data/vox/tool/sledge.vox, 3x7x24 voxels a 5 cm):
##   - mango de madera de 1,05 m con sección de 5 cm
##   - cabeza de acero de 15 x 35 x 15 cm en la punta
##   - virola metálica y agarre de goma, que es lo que se ve en el modelo original
## Las dos manos van en el mango separadas 0,55 m, como marca tool/sledge.xml (tp_action_rh/lh).
func _build_sledge() -> void:
	one_handed = false
	muzzle_pos = Vector3(0, 0, -0.62)          # la cabeza: de ahi sale el golpe
	# MANOS: la derecha (agarre principal) al FINAL del mango y la izquierda al medio, que es como
	# se sujeta un mazo para tener palanca.
	grip_pos = Vector3(0.0, 0.0, 0.34)         # mano derecha (final del mango)
	foregrip_pos = Vector3(0.0, 0.0, 0.05)     # mano izquierda (medio del mango)
	fp_foregrip_pos = foregrip_pos
	sight_pos = Vector3(0, 0.05, 0)
	rear_z = 0.42
	var madera := _mat(Color(0.58, 0.40, 0.21), 0.0, 0.7)
	var madera2 := _mat(Color(0.50, 0.34, 0.17), 0.0, 0.75)
	var acero := _mat(Color(0.46, 0.46, 0.48), 0.55, 0.35)
	var acero2 := _mat(Color(0.54, 0.54, 0.56), 0.55, 0.28)
	var goma := _mat(Color(0.09, 0.09, 0.10), 0.0, 0.9)
	_box(Vector3(0.05, 0.05, 1.05), Vector3(0, 0, 0.0), madera)
	_box(Vector3(0.052, 0.014, 1.05), Vector3(0, 0.018, 0.0), madera2)
	_box(Vector3(0.058, 0.058, 0.26), Vector3(0, 0, 0.36), goma)
	_box(Vector3(0.07, 0.07, 0.035), Vector3(0, 0, 0.515), goma)
	_box(Vector3(0.075, 0.075, 0.07), Vector3(0, 0, -0.47), acero2)
	# CABEZA: 15 x 35 x 15 cm CRUZADA AL MANGO, como un mazo de verdad. Las caras de golpeo quedan
	# arriba y abajo del arma, que es por donde pega en el arco del mazazo.
	_box(Vector3(0.15, 0.35, 0.15), Vector3(0, 0, -0.60), acero)
	_box(Vector3(0.155, 0.03, 0.155), Vector3(0, 0.175, -0.60), acero2)
	_box(Vector3(0.155, 0.03, 0.155), Vector3(0, -0.175, -0.60), acero2)
	for s in [-1.0, 1.0]:
		_box(Vector3(0.16, 0.30, 0.03), Vector3(0, 0, -0.60 + 0.062 * s), acero2)
		_box(Vector3(0.03, 0.30, 0.16), Vector3(0.062 * s, 0, -0.60), acero2)


## Fusil láser: cuerpo blanco de polímero, disipadores, celda de energía azul emisiva, lente y
## anillos del emisor. Sin cañón metálico ni freno de boca: no dispara pólvora.
func _build_laser() -> void:
	muzzle_pos = Vector3(0, 0.02, -0.62)
	grip_pos = Vector3(0.0, -0.075, 0.03)
	foregrip_pos = Vector3(0.0, -0.04, -0.28)
	fp_foregrip_pos = Vector3(0.0, -0.045, -0.15)
	sight_pos = Vector3(0, 0.088, -0.14)
	rear_z = 0.24
	var m_shell := _mat(Color(0.86, 0.88, 0.92), 0.25, 0.35)      # carcasa blanca
	var m_trim := _mat(Color(0.16, 0.17, 0.20), 0.35, 0.45)
	var m_core := StandardMaterial3D.new()
	m_core.albedo_color = Color(0.35, 0.75, 1.0)
	m_core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m_core.emission_enabled = true
	m_core.emission = Color(0.35, 0.8, 1.0)
	m_core.emission_energy_multiplier = 7.0
	_box(Vector3(0.056, 0.055, 0.34), Vector3(0, 0.015, -0.04), m_shell)
	_box(Vector3(0.05, 0.042, 0.2), Vector3(0, -0.03, 0.0), m_trim)          # inferior
	_box(Vector3(0.046, 0.012, 0.4), Vector3(0, 0.05, -0.14), m_trim)        # riel
	for i in range(6):
		_box(Vector3(0.066, 0.03, 0.012), Vector3(0, 0.02, -0.02 - i * 0.045), m_trim)
	_box(Vector3(0.062, 0.02, 0.1), Vector3(0, 0.0, 0.06), m_core)
	_box(Vector3(0.03, 0.05, 0.09), Vector3(0, -0.055, -0.02), m_shell)      # cargador de celdas
	_box(Vector3(0.026, 0.012, 0.07), Vector3(0, -0.055, -0.02), m_core)
	_cyl(0.016, 0.016, 0.3, Vector3(0, 0.02, -0.4), m_shell)
	for i in range(4):
		_cyl(0.021, 0.021, 0.012, Vector3(0, 0.02, -0.3 - i * 0.07), m_trim)
	_cyl(0.013, 0.013, 0.02, Vector3(0, 0.02, -0.6), m_core)                 # lente
	_box(Vector3(0.028, 0.09, 0.032), Vector3(0, -0.075, 0.05), m_trim, Vector3(-12, 0, 0))
	_box(Vector3(0.024, 0.05, 0.03), Vector3(0, -0.055, -0.28), m_trim)
	_box(Vector3(0.04, 0.06, 0.14), Vector3(0, 0.0, 0.19), m_shell)
	# colimador integrado: dos paredes, techo y el punto azul
	_box(Vector3(0.040, 0.014, 0.070), Vector3(0, 0.063, -0.14), m_trim)
	for s in [-1.0, 1.0]:
		_box(Vector3(0.004, 0.034, 0.062), Vector3(s * 0.018, 0.087, -0.14), m_trim)
	_box(Vector3(0.040, 0.004, 0.062), Vector3(0, 0.105, -0.14), m_trim)
	_box(Vector3(0.005, 0.005, 0.003), Vector3(0, 0.088, -0.15), m_core)
	reticle = get_child(get_child_count() - 1)


## C4 estilo CS2: bloque de explosivo plástico envuelto, panel de control con teclado numérico,
## pantalla de cuenta atrás, piloto rojo, antena y haz de cables de colores.
func _build_c4() -> void:
	one_handed = true
	grip_pos = Vector3(0.0, -0.035, 0.0)
	foregrip_pos = grip_pos
	fp_foregrip_pos = grip_pos
	muzzle_pos = Vector3.ZERO
	sight_pos = Vector3(0, 0.05, 0)
	rear_z = 0.1
	build_c4_into(self)

## Construye la geometría dentro de `root`. Estático para que la C4 plantada use exactamente el
## mismo modelo que la que llevas en la mano, sin duplicar el diseño.
static func build_c4_into(root: Node3D) -> void:
	var mk := func(c: Color, met: float, ro: float) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = c; m.metallic = met; m.roughness = ro; m.metallic_specular = 0.6
		return m
	var m_brick: StandardMaterial3D = mk.call(Color(0.72, 0.66, 0.50), 0.0, 0.85)    # explosivo plástico, tono arena
	var m_wrap: StandardMaterial3D = mk.call(Color(0.30, 0.31, 0.28), 0.05, 0.75)    # cinta/envoltorio verde oliva
	var m_case: StandardMaterial3D = mk.call(Color(0.13, 0.14, 0.15), 0.15, 0.55)    # carcasa del panel
	var m_metal: StandardMaterial3D = mk.call(Color(0.34, 0.35, 0.38), 0.9, 0.30)
	var m_key: StandardMaterial3D = mk.call(Color(0.22, 0.23, 0.25), 0.1, 0.6)
	var m_rub: StandardMaterial3D = mk.call(Color(0.05, 0.05, 0.05), 0.0, 0.95)
	var wire_cols := [Color(0.75, 0.10, 0.10), Color(0.10, 0.25, 0.75), Color(0.85, 0.70, 0.10), Color(0.9, 0.9, 0.9)]
	var m_screen: StandardMaterial3D = mk.call(Color(0.04, 0.09, 0.05), 0.0, 0.25)
	var m_led := StandardMaterial3D.new()
	m_led.albedo_color = Color(1.0, 0.12, 0.08)
	m_led.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m_led.emission_enabled = true
	m_led.emission = Color(1.0, 0.15, 0.1)
	m_led.emission_energy_multiplier = 8.0
	var m_digit := StandardMaterial3D.new()
	m_digit.albedo_color = Color(0.35, 1.0, 0.4)
	m_digit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m_digit.emission_enabled = true
	m_digit.emission = Color(0.3, 1.0, 0.35)
	m_digit.emission_energy_multiplier = 4.0

	var box := func(size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = size
		mi.mesh = bm; mi.material_override = mat; mi.position = pos; mi.rotation_degrees = rot
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var cyl := func(r: float, h: float, pos: Vector3, mat: Material, rot := Vector3(90, 0, 0)) -> void:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new(); cm.top_radius = r; cm.bottom_radius = r; cm.height = h; cm.radial_segments = 12
		mi.mesh = cm; mi.material_override = mat; mi.position = pos; mi.rotation_degrees = rot
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)

	# --- cuerpo: dos panes de explosivo apilados, con cintas alrededor ---
	box.call(Vector3(0.20, 0.055, 0.11), Vector3(0, -0.03, 0), m_brick)
	box.call(Vector3(0.19, 0.05, 0.105), Vector3(0, 0.018, 0), m_brick)
	for x in [-0.06, 0.06]:
		box.call(Vector3(0.016, 0.115, 0.118), Vector3(x, -0.006, 0), m_wrap)   # cintas transversales
	box.call(Vector3(0.205, 0.012, 0.115), Vector3(0, -0.058, 0), m_wrap)       # base
	# --- panel de control encima ---
	box.call(Vector3(0.115, 0.030, 0.082), Vector3(0, 0.058, 0), m_case)
	box.call(Vector3(0.119, 0.006, 0.086), Vector3(0, 0.043, 0), m_metal)       # pestaña inferior
	box.call(Vector3(0.058, 0.004, 0.026), Vector3(-0.022, 0.074, -0.020), m_screen)
	for i in range(4):                                                          # dígitos
		box.call(Vector3(0.007, 0.003, 0.014), Vector3(-0.043 + i * 0.013, 0.0765, -0.020), m_digit)
	box.call(Vector3(0.003, 0.003, 0.004), Vector3(-0.0175, 0.0765, -0.020), m_digit)   # dos puntos
	for r in range(4):
		for c in range(3):
			box.call(Vector3(0.011, 0.005, 0.009), Vector3(-0.043 + c * 0.014, 0.0755, 0.002 + r * 0.0125), m_key)
	cyl.call(0.006, 0.006, Vector3(0.040, 0.076, -0.020), m_metal, Vector3(0, 0, 0))
	cyl.call(0.0042, 0.009, Vector3(0.040, 0.079, -0.020), m_led, Vector3(0, 0, 0))
	cyl.call(0.0035, 0.05, Vector3(0.050, 0.093, 0.028), m_rub, Vector3(0, 0, 8))
	cyl.call(0.0055, 0.010, Vector3(0.050, 0.072, 0.028), m_metal, Vector3(0, 0, 0))
	for i in range(4):
		var c: Color = wire_cols[i]
		var mw: StandardMaterial3D = mk.call(c, 0.0, 0.6)
		var x := -0.052 + i * 0.010
		cyl.call(0.0022, 0.055, Vector3(x, 0.040, 0.050), mw, Vector3(28, 0, 6 - i * 4))
		cyl.call(0.0022, 0.030, Vector3(x - 0.004, 0.012, 0.062), mw, Vector3(70, 0, 0))
	for x in [-0.055, 0.055]:
		cyl.call(0.006, 0.026, Vector3(x, 0.030, 0.030), m_metal, Vector3(12, 0, 0))


func _build_flash() -> void:
	# EL FOGONAZO. Particulas con un atlas de 16 fotogramas, o sea que el destello ARDE y cambia de
	# forma mientras dura. Ver shaders/fogonazo.gdshader.
	flash = GPUParticles3D.new()
	flash.name = "Fogonazo"
	flash.amount = 1
	flash.one_shot = true
	flash.emitting = false
	flash.explosiveness = 1.0
	flash.lifetime = 0.095          # lo que dura la llamarada: menos que un parpadeo
	flash.local_coords = true       # clavado a la boca del canon aunque el arma retroceda
	flash.visibility_aabb = AABB(Vector3(-0.6, -0.6, -0.9), Vector3(1.2, 1.2, 1.5))
	var fp := ParticleProcessMaterial.new()
	fp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	fp.direction = Vector3(0, 0, -1)
	fp.spread = 0.0
	fp.initial_velocity_min = 0.0
	fp.initial_velocity_max = 0.0
	fp.gravity = Vector3.ZERO
	fp.scale_min = 0.85
	fp.scale_max = 1.25
	fp.anim_speed_min = 1.0
	fp.anim_speed_max = 1.0
	fp.anim_offset_min = 0.0
	fp.anim_offset_max = 0.0
	flash.process_material = fp
	flash.draw_pass_1 = _malla_fogonazo()
	flash.position = muzzle_pos + Vector3(0, 0, -0.02)
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flash)
	FxDormir.dormir(flash)      # escondido hasta el primer tiro (parado seguia costando su llamada de dibujo)

	# EL GAS CALIENTE, la otra mitad del efecto. Va en mezcla aditiva: no es humo gris, es el gas
	# iluminado por el propio fogonazo. El humo gris que se queda flotando lo pone effects.gd aparte.
	flash_gas = GPUParticles3D.new()
	flash_gas.name = "GasCaliente"
	flash_gas.amount = 2
	flash_gas.one_shot = true
	flash_gas.emitting = false
	flash_gas.explosiveness = 0.9
	flash_gas.randomness = 0.5
	flash_gas.lifetime = 0.26
	flash_gas.local_coords = false   # este NO se pega al canon: se queda donde salio
	flash_gas.visibility_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3, 3, 3))
	var gp := ParticleProcessMaterial.new()
	gp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	gp.emission_sphere_radius = 0.02
	gp.direction = Vector3(0, 0, -1)
	gp.spread = 22.0
	gp.initial_velocity_min = 0.5
	gp.initial_velocity_max = 1.3
	gp.damping_min = 5.0             # frena en seguida: es una bocanada, no un chorro
	gp.damping_max = 9.0
	gp.gravity = Vector3(0, 0.4, 0)
	gp.scale_min = 0.55
	gp.scale_max = 1.0
	gp.color = Color(1.0, 0.97, 0.92, 0.5)
	gp.angle_min = 0.0
	gp.angle_max = 360.0             # cada bocanada girada: si no salen todas calcadas
	gp.anim_speed_min = 1.0
	gp.anim_speed_max = 1.0
	flash_gas.process_material = gp
	var q := QuadMesh.new()
	q.size = Vector2(0.19, 0.19)
	q.material = _mat_atlas("res://shaders/humo_arma.gdshader", "res://assets/humo_arma.png")
	flash_gas.draw_pass_1 = q
	flash_gas.position = muzzle_pos + Vector3(0, 0, -0.04)
	flash_gas.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flash_gas)
	FxDormir.dormir(flash_gas)
	flash_light = OmniLight3D.new()
	flash_light.light_color = Color(1.0, 0.7, 0.35)
	flash_light.light_energy = 6.0
	flash_light.omni_range = 5.0
	flash_light.shadow_enabled = false
	flash_light.position = muzzle_pos + Vector3(0, 0, -0.1)
	flash_light.visible = false
	add_child(flash_light)

func fire_flash(with_light: bool) -> void:
	if flash == null or flash_light == null:
		return   # el láser, el mazo y la C4 no tienen fogonazo de pólvora
	# el abanico girado al azar en cada tiro: dos fogonazos seguidos nunca salen calcados
	flash.rotation.z = randf() * TAU
	FxDormir.lanzar(flash)
	flash.emitting = true
	# el gas caliente se puede apagar desde la configuracion grafica; el fogonazo no, que ese es
	# informacion de juego: te dice desde donde te disparan
	if flash_gas and _gas_permitido():
		FxDormir.lanzar(flash_gas)
		flash_gas.emitting = true
	flash_light.visible = with_light
	flash_t = 0.055
	set_process(true)

## Pone el fogonazo, el gas y la luz en la boca DE VERDAD del arma y les da el tamaño que toque: el
## fusil silenciado apenas destella (su `fogonazo` sale de la ficha), un freno de boca lo abre mas.
func _colocar_fogonazo() -> void:
	if flash == null:
		return
	flash.position = muzzle_pos + Vector3(0, 0, -0.02)
	if flash_gas:
		flash_gas.position = muzzle_pos + Vector3(0, 0, -0.04)
	if flash_light:
		flash_light.position = muzzle_pos + Vector3(0, 0, -0.1)
	var f := clampf(fogonazo, 0.12, 1.6)
	var fp := flash.process_material as ParticleProcessMaterial
	if fp:
		fp.scale_min = 0.85 * f
		fp.scale_max = 1.25 * f
	if flash_gas:
		var gp := flash_gas.process_material as ParticleProcessMaterial
		if gp:
			gp.scale_min = 0.55 * f
			gp.scale_max = 1.00 * f
		flash_gas.amount = 1 if f < 0.5 else 2
	if flash_light:
		flash_light.light_energy = 6.0 * f
		flash_light.omni_range = 5.0 * (0.55 + 0.45 * f)


func _gas_permitido() -> bool:
	var mn := get_tree().root.get_node_or_null("Main") if is_inside_tree() else null
	if mn and ("_gas_arma_on" in mn):
		return bool(mn._gas_arma_on)
	return true


func _process(dt: float) -> void:
	var _pt0 := Time.get_ticks_usec()
	_process_inner(dt)
	Prof.add("weapon_model", Time.get_ticks_usec() - _pt0)

func _process_inner(dt: float) -> void:
	if flash_t > 0.0:
		flash_t -= dt
		if flash_t <= 0.0:
			flash_light.visible = false   # las particulas se apagan solas al cumplir su vida
	if flash_t <= 0.0:
		set_process(false)


## LA GEOMETRIA DEL FOGONAZO: tres cuadrados en abanico que CONTIENEN el eje del canon, como las
## aspas de un ventilador. De lado ves uno de plano y el destello se lee entero; mirando de frente
## por el canon los verias de canto, que es la raya fea de siempre, y justo ahi el fresnel invertido
## del shader los borra. Por eso hacen falta varios y no un cartel: un cartel solo funciona desde un
## angulo, y en una partida te ven desde todos.
func _malla_fogonazo() -> ArrayMesh:
	var largo := 0.34
	var ancho := 0.30
	var atras := 0.24
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	# CADA ASPA, DOS VECES, con la normal del derecho y del reves: el fresnel del shader usa
	# clamp(dot(N,V), 0, 1), o sea que una normal al reves da CERO y el aspa desaparece.
	for a in 3:
		var ang: float = float(a) * PI / 3.0
		var ejex := Vector3(cos(ang), sin(ang), 0.0)      # el ancho del aspa
		var nrm := Vector3(-sin(ang), cos(ang), 0.0)      # perpendicular: lo que mira el fresnel
		for lado in [1.0, -1.0]:
			var base: int = vs.size()
			for e in [[-1.0, atras], [1.0, atras], [1.0, -largo], [-1.0, -largo]]:
				vs.append(ejex * (ancho * 0.5 * float(e[0])) + Vector3(0, 0, float(e[1])))
				ns.append(nrm * lado)
			uvs.append(Vector2(0, 1)); uvs.append(Vector2(1, 1))
			uvs.append(Vector2(1, 0)); uvs.append(Vector2(0, 0))
			for i in [0, 1, 2, 0, 2, 3]:
				idx.append(base + i)
	# LA TAPA: un cuadrado atravesado, mirando hacia donde sale la bala, para el que tienes enfrente.
	var tapa := 0.30
	var tz := -0.06
	for cara in [-1.0, 1.0]:
		var base2: int = vs.size()
		for e in [[-1.0, 1.0], [1.0, 1.0], [1.0, -1.0], [-1.0, -1.0]]:
			vs.append(Vector3(float(e[0]) * tapa * 0.5, float(e[1]) * tapa * 0.5, tz))
			ns.append(Vector3(0, 0, cara))
		uvs.append(Vector2(0, 1)); uvs.append(Vector2(1, 1))
		uvs.append(Vector2(1, 0)); uvs.append(Vector2(0, 0))
		for i in [0, 1, 2, 0, 2, 3]:
			idx.append(base2 + i)

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, _mat_atlas("res://shaders/fogonazo.gdshader", "res://assets/fogonazo.png"))
	return m


## Los dos shaders del disparo leen la misma rejilla de 4x4 fotogramas.
func _mat_atlas(shader: String, textura: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(shader)
	m.set_shader_parameter("texture_albedo", load(textura))
	m.set_shader_parameter("particles_anim_h_frames", 4)
	m.set_shader_parameter("particles_anim_v_frames", 4)
	# en el movil, sin glow y con menos precision de color, el fogonazo a x4 se recortaba a una mancha plana
	if Settings.is_mobile() and not ("--fogonazopc" in OS.get_cmdline_user_args()):
		m.set_shader_parameter("ganancia", 1.6)
	return m


## EL PUNTO DE MIRA DELANTERO (2026-10-01, pedido: "a la pistola le falta ese fierrito en el medio con punta verde, muy
## chiquitito"): un poste de acero junto a la boca, con la punta a la altura de la linea de mira (la del alza, sight_pos),
## y encima un puntito verde que brilla (tritio). No sale de Blender: se pone aqui al montar el arma ("mira_delantera").
func _poner_mira_delantera(raiz: Node3D) -> void:
	var z := muzzle_pos.z + 0.014
	var alto := 0.016          # (a la mitad de alta: pedido 2026-10-13)
	var arriba := sight_pos.y + MIRA_DELANTERA_ALTO   # la punta: asoma por la muesca del alza
	var poste := MeshInstance3D.new()
	poste.name = "MiraDelantera"
	var caja := BoxMesh.new()
	caja.size = Vector3(0.0032, alto, 0.005)
	poste.mesh = caja
	var acero := StandardMaterial3D.new()
	acero.albedo_color = Color(0.08, 0.085, 0.09)
	acero.metallic = 0.6
	acero.roughness = 0.45
	poste.material_override = acero
	poste.position = Vector3(0.0, arriba - alto * 0.5, z)
	poste.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	raiz.add_child(poste)
	# (el punto verde de la punta se quito: pedido, "quedo horrible")
