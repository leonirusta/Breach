extends Node3D
## EL AVION DEL BATTLE ROYALE: solo lo que se ve y se oye. Lo mueve salto_br.gd.
##
## La malla es de voxels de 20 cm y viene hecha de casa (tools/generar_avion_br.py -> res://avion/avion_br.bin):
## aqui solo se copia a un ArrayMesh, sin mallar nada. Encima van las cuatro helices, que giran, y el
## zumbido de los motores, que se SINTETIZA al cargar (nada de audio con derechos: CLAUDE.md). Vuela a
## 170 m, fuera del mundo de voxels: no toca el motor ni la fisica.
##
## Ejes del modelo: el morro hacia -Z. Para volar hacia `dir` basta con look_at(pos + dir).

const RUTA := "res://avion/avion_br.bin"
## Bujes de las helices (los mismos que HELICES en tools/generar_avion_br.py)
const HELICES := [Vector3(-12.4, 1.5, -6.0), Vector3(-6.4, 1.5, -6.4), Vector3(6.4, 1.5, -6.4), Vector3(12.4, 1.5, -6.0)]
const RPM_HELICE := 14.0             ## vueltas por segundo que se ven (las de verdad van a mas: con el
									## refresco de pantalla se veria girar al reves)
## Donde se sienta el pasaje (la bodega) y por donde se salta (la rampa), en espacio del avion
const ASIENTO := Vector3(0.0, -1.4, 2.0)
const RAMPA := Vector3(0.0, -3.2, 12.5)

static var _malla_cache: ArrayMesh = null
static var _sonido_cache: AudioStreamWAV = null
var _helices: Array[Node3D] = []
var _motor: AudioStreamPlayer3D = null


func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = malla()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # a 170 m la sombra cae fuera de todo
	add_child(mi)
	var mat_pala := StandardMaterial3D.new()
	mat_pala.albedo_color = Color(0.13, 0.13, 0.14)
	mat_pala.roughness = 0.6
	var mat_punta := StandardMaterial3D.new()
	mat_punta.albedo_color = Color(0.86, 0.7, 0.16)
	for h in HELICES:
		var piv := Node3D.new()
		piv.position = h + Vector3(0, 0, -0.45)
		add_child(piv)
		# cuatro palas de 2 m, voxel a voxel (0,2 m de canto) como el resto del avion
		for k in 4:
			var pala := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.2, 1.9, 0.12)
			pala.mesh = bm
			pala.material_override = mat_pala
			pala.position = Vector3(0, 1.05, 0).rotated(Vector3.FORWARD, k * PI * 0.5)
			pala.rotation.z = -k * PI * 0.5
			piv.add_child(pala)
			var punta := MeshInstance3D.new()
			var bp := BoxMesh.new()
			bp.size = Vector3(0.21, 0.2, 0.13)
			punta.mesh = bp
			punta.material_override = mat_punta
			punta.position = Vector3(0, 1.95, 0).rotated(Vector3.FORWARD, k * PI * 0.5)
			piv.add_child(punta)
		_helices.append(piv)
	# el ruido de los motores: se oye desde lejos, que es lo que avisa de que viene
	_motor = AudioStreamPlayer3D.new()
	_motor.stream = sonido_motores()
	_motor.unit_size = 60.0
	_motor.max_distance = 900.0
	_motor.volume_db = 2.0
	_motor.bus = "Master"
	add_child(_motor)
	_motor.play()


func _process(dt: float) -> void:
	for i in _helices.size():
		_helices[i].rotate_object_local(Vector3.FORWARD, dt * TAU * RPM_HELICE * (1.0 if i % 2 == 0 else -1.0))


## Volumen de los motores: mas bajo cuando lo oyes desde dentro (el que va en la bodega).
func set_volumen(db: float) -> void:
	if _motor:
		_motor.volume_db = db


static func malla() -> ArrayMesh:
	if _malla_cache != null:
		return _malla_cache
	var am := ArrayMesh.new()
	var f := FileAccess.open(RUTA, FileAccess.READ)
	if f == null:
		push_warning("[avion] falta %s (tools/generar_avion_br.py)" % RUTA)
		var caja := BoxMesh.new()
		caja.size = Vector3(4, 4, 28)
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, caja.get_mesh_arrays())
		_malla_cache = am
		return am
	var magia := f.get_buffer(4).get_string_from_ascii()
	if magia != "AVB1":
		push_warning("[avion] %s no es un avion (%s)" % [RUTA, magia])
	var nv := f.get_32()
	var ni := f.get_32()
	var pos := f.get_buffer(nv * 12).to_float32_array()
	var nor := f.get_buffer(nv * 12).to_float32_array()
	var col := f.get_buffer(nv * 4)
	var idx := f.get_buffer(ni * 4).to_int32_array()
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var cs := PackedColorArray()
	vs.resize(nv)
	ns.resize(nv)
	cs.resize(nv)
	for i in nv:
		vs[i] = Vector3(pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2])
		ns[i] = Vector3(nor[i * 3], nor[i * 3 + 1], nor[i * 3 + 2])
		cs[i] = Color8(col[i * 4], col[i * 4 + 1], col[i * 4 + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_COLOR] = cs
	arr[Mesh.ARRAY_INDEX] = idx
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.55
	m.metallic = 0.25
	# las caras salen del generador con un sentido de giro que no se ha comprobado en todas: sin descartar
	# ninguna se ven todas, y son 20.000 triangulos de un solo objeto
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	am.surface_set_material(0, m)
	_malla_cache = am
	return am


## EL ZUMBIDO DE CUATRO MOTORES DE HELICE, hecho aqui mismo: el tono de las palas (armonicos de ~62 Hz),
## un rugido grave de ruido filtrado y un batido lento entre motores. Dos segundos que se repiten sin
## costura (todas las frecuencias dan vueltas enteras en ese tiempo).
static func sonido_motores() -> AudioStreamWAV:
	if _sonido_cache != null:
		return _sonido_cache
	var sr := 22050
	var n := sr * 2
	var datos := PackedByteArray()
	datos.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var ruido := 0.0
	var ruido2 := 0.0
	for i in n:
		var t := float(i) / float(sr)
		var s := 0.0
		# palas: 62 y 64 Hz (dos pares de motores algo desacompasados: batido de 2 Hz)
		for f0 in [62.0, 64.0]:
			for h in 5:
				s += sin(TAU * f0 * (h + 1) * t) * (0.34 / (h + 1.0))
		# rugido: ruido filtrado dos veces (grave), modulado por el paso de las palas
		ruido += (rng.randf_range(-1.0, 1.0) - ruido) * 0.08
		ruido2 += (ruido - ruido2) * 0.1
		s += ruido2 * 3.2 * (0.75 + 0.25 * sin(TAU * 31.0 * t))
		s *= 0.32
		var v := int(clampf(s, -1.0, 1.0) * 32000.0)
		datos.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = sr
	w.stereo = false
	w.data = datos
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	_sonido_cache = w
	return w
