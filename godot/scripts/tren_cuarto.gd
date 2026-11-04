extends Node3D
## EL TREN DE JUGUETE DE LA HABITACION (2026-10-21, pedido con capturas de Mini Royale: "un tren que va moviendose por
## todo el mapa; se puede destruir el tren, se puede destruir la via, y el tren se cae y deja de andar").
## Da vueltas por la via de voxels que dibuja tools/generar_mapa_cuarto.py (el camino viene en <mapa>.br.json "tren").
## - Cada vagon es un AnimatableBody3D (se le puede subir encima: te lleva). Mira los rieles debajo de la locomotora:
##   si alguien rompio la via delante, DESCARRILA: los vagones pasan a cuerpos rigidos con su velocidad y caen.
## - Se rompe a tiros y con explosiones (danar_bala / take_damage, grupo "damageable"); sin locomotora no anda.
## - En red manda el anfitrion: la distancia recorrida cada segundo, el descarrile y lo roto (net_campana "tren_*");
##   el invitado pide el daño (net_campana_pide "tren_dano:i:d").
## Pruebas: --map=cuarto --sinprecarga --nobots --trentest (anda, se rompe la via delante y descarrila)

const LARGO := 3.0           ## m de cada vagon
const ANCHO := 1.7
const ALTO := 2.2
## los choques de cada vagon: [ancho, alto, largo, y del centro]
const CHOQUES := [
	[[1.7, 2.1, 3.0, 1.15]],                                   # locomotora
	[[1.7, 1.45, 3.0, 0.8]],                                   # tender (encima, el carbon)
	[[1.7, 2.0, 3.0, 1.1]],                                    # pasajeros (al techo se sube desde el tender)
	[[1.7, 0.66, 3.0, 0.4], [1.3, 1.1, 2.7, 1.28]],            # troncos: la plataforma y la pila
	# la batea de cola: el piso y los cuatro muros de chapa (x y z del centro en los dos ultimos)
	[[1.7, 0.8, 3.0, 0.4], [0.08, 0.9, 2.94, 1.2, -0.8, 0.0], [0.08, 0.9, 2.94, 1.2, 0.8, 0.0],
		[1.6, 0.9, 0.08, 1.2, 0.0, -1.44], [1.6, 0.9, 0.08, 1.2, 0.0, 1.44]],
]
const VIDA_PARTE := 70.0     ## cada pedazo (chimenea, cabina, un tronco...): unos tiros o dos mazazos
const HUECO := 0.45          ## entre vagones
const VIDA := 120.0       ## el vagon ENTERO (solo las explosiones): un bazucazo
const VagonScript := preload("res://scripts/tren_vagon.gd")
const MODELOS := ["res://modelos/tren/locomotora.glb", "res://modelos/tren/tender.glb", "res://modelos/tren/pasajeros.glb",
	"res://modelos/tren/troncos.glb", "res://modelos/tren/plataforma.glb"]
## EL TREN LARGO (2026-10-21, pedido: "mucho mas largo, con una parte trasera de piso y muros de metal"): que modelo lleva
## cada vagon, de la locomotora a la cola
const ORDEN := [0, 1, 2, 3, 2, 3, 4]
const COLORES := [Color(0.85, 0.18, 0.15), Color(0.2, 0.42, 0.85), Color(0.28, 0.68, 0.3), Color(0.95, 0.78, 0.15),
	Color(0.55, 0.3, 0.72)]

var main
var world
var cfg := {}
var _p: PackedVector3Array = []
var _acum: PackedFloat32Array = []
var _total := 0.0
var _s := 0.0
var _vel := 3.2
var _vagones: Array = []     ## {cuerpo, vida, roto, color}
var _parado := false
var _descarrilado := false
var _sync_t := 0.0
var _mira_t := 0.0
var _prueba := false
var _t_vox := 0


func empezar(p_main: Node, p_world, p_cfg: Dictionary) -> void:
	main = p_main
	world = p_world
	cfg = p_cfg
	name = "TrenCuarto"
	for q in cfg.get("camino", []):
		_p.append(Vector3(float(q[0]), float(q[1]), float(q[2])))
	if _p.size() < 4:
		return
	_acum.resize(_p.size() + 1)
	_acum[0] = 0.0
	for i in _p.size():
		_total += _p[i].distance_to(_p[(i + 1) % _p.size()])
		_acum[i + 1] = _total
	_vel = float(cfg.get("velocidad", 3.2))
	for k in ORDEN.size():
		_vagones.append(_montar_vagon(k))
	Net.campana_evento.connect(_red_evento)
	Net.campana_pide.connect(_red_pide)
	_prueba = "--trentest" in OS.get_cmdline_user_args()
	_colocar()
	print("[tren] %d vagones, via de %.0f m, voxels en %d ms" % [_vagones.size(), _total, _t_vox])
	if _prueba:
		_test.call_deferred()


func _manda() -> bool:
	return not Net.is_online() or Net.hosting


# ------------------------------------------------------------------------------------------------------- el modelo
func _caja(padre: Node3D, tam: Vector3, pos: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = tam
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.45
	mi.material_override = m
	mi.position = pos
	padre.add_child(mi)


func _rueda(padre: Node3D, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.34
	cm.bottom_radius = 0.34
	cm.height = 0.22
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.12, 0.13)
	mi.material_override = m
	mi.rotation.z = PI * 0.5
	mi.position = pos
	padre.add_child(mi)


func _montar_vagon(k: int) -> Dictionary:
	var b := AnimatableBody3D.new()
	b.set_script(VagonScript)
	# SE MUEVE COMO PLATAFORMA (pedido: "me subo y no me lleva"): con sync_to_physics Godot calcula su velocidad y el
	# que esta encima viaja con el
	b.sync_to_physics = true
	b.add_to_group("damageable")
	b.set_meta("tren_i", k)
	add_child(b)
	var col: Color = COLORES[k % COLORES.size()]
	var tipo: int = ORDEN[k] if k < ORDEN.size() else 2 + (k % 2)
	# EL MODELO (tools/blender/tren_juguete.py): un nodo por pedazo. Cada pedazo choca con su caja hasta que lo rompes;
	# desde el primer golpe es de VOXELS (_voxelizar) y choca con lo que queda de ellos
	var partes := {}
	var modelo: PackedScene = load(MODELOS[tipo])
	if modelo:
		var inst: Node = modelo.instantiate()
		b.add_child(inst)
		for mi in inst.find_children("p_*", "MeshInstance3D", true, false):
			var nom := String(mi.name).substr(2)
			var t_loc: Transform3D = _en_cuerpo(b, mi)
			var ab: AABB = t_loc * (mi as MeshInstance3D).get_aabb()
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = ab.size.max(Vector3(0.05, 0.05, 0.05))
			cs.shape = bs
			cs.position = ab.get_center()
			b.add_child(cs)
			partes[nom] = {"nodo": mi, "t": t_loc, "ab": ab, "choques": [cs], "vox": null, "mm": null, "roto": false}
	# TODO EL TREN EN VOXELS DESDE EL PRINCIPIO (2026-10-21, pedido: "dejalo en voxels, lo liso pierde la esencia del
	# juego"): cada pedazo se pasa a voxels de VOX al montarlo, con el color de su material
	var t0 := Time.get_ticks_msec()
	for nom in partes:
		_voxelizar(partes[nom], b)
	_t_vox += Time.get_ticks_msec() - t0
	var d := {"cuerpo": b, "vida": VIDA, "roto": false, "color": col, "partes": partes}
	b.set_meta("tren", self)
	return d


# ------------------------------------------------------------------------------------------------------- moverse
func _punto(s: float) -> Array:
	s = fposmod(s, _total)
	var lo := 0
	var hi := _p.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if _acum[mid] <= s:
			lo = mid
		else:
			hi = mid - 1
	var a: Vector3 = _p[lo]
	var b: Vector3 = _p[(lo + 1) % _p.size()]
	var seg := _acum[lo + 1] - _acum[lo]
	var t := 0.0 if seg <= 0.0 else (s - _acum[lo]) / seg
	return [a.lerp(b, t), (b - a).normalized()]


func _colocar() -> void:
	for k in _vagones.size():
		var v: Dictionary = _vagones[k]
		if v.roto or _descarrilado:
			continue
		var c := _s - k * (LARGO + HUECO)
		var f: Array = _punto(c + LARGO * 0.5)
		var t: Array = _punto(c - LARGO * 0.5)
		var centro: Vector3 = (f[0] + t[0]) * 0.5
		var dir: Vector3 = (f[0] - t[0]).normalized()
		var cuerpo: Node3D = v.cuerpo
		cuerpo.global_transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), centro)


func _physics_process(dt: float) -> void:
	if _p.size() < 4 or _descarrilado:
		return
	if bool(main.get("loading")):
		return
	var loco_ok: bool = _vagones.size() > 0 and not _vagones[0].roto
	if not _parado and loco_ok:
		_s += _vel * dt
	_colocar()
	if not _manda():
		return
	if not loco_ok and not _parado:
		_parado = true
		Net.net_campana("tren_s", [_s, true])
	# los rieles de delante: si no estan, se va de la via
	_mira_t -= dt
	if _mira_t <= 0.0 and not _parado:
		_mira_t = 0.1
		var f: Array = _punto(_s + LARGO * 0.5 + 0.6)
		if not _hay_via(f[0]):
			_descarrilar()
			Net.net_campana("tren_descarrila", [_s])
			return
	_sync_t -= dt
	if _sync_t <= 0.0:
		_sync_t = 1.0
		Net.net_campana("tren_s", [_s, _parado])


func _hay_via(p: Vector3) -> bool:
	if world == null:
		return true
	return world.box_solid(p + Vector3(-0.7, -0.55, -0.7), p + Vector3(0.7, -0.08, 0.7))


func _descarrilar() -> void:
	if _descarrilado:
		return
	_descarrilado = true
	print("[tren] DESCARRILA en s=%.1f" % _s)
	Audio.rotura("metal", "l", _vagones[0].cuerpo.global_position, 0.0, 60.0, Audio.PRI_HIGH)
	for k in _vagones.size():
		var v: Dictionary = _vagones[k]
		if v.roto:
			continue
		var viejo: AnimatableBody3D = v.cuerpo
		var rb := RigidBody3D.new()
		rb.set_script(VagonScript)
		rb.mass = 40.0
		rb.continuous_cd = true
		rb.add_to_group("damageable")
		rb.set_meta("tren", self)
		rb.set_meta("tren_i", k)
		add_child(rb)
		rb.global_transform = viejo.global_transform
		for h in viejo.get_children():
			h.reparent(rb, false)
		var adelante: Vector3 = -viejo.global_transform.basis.z
		rb.linear_velocity = adelante * _vel * (1.0 - k * 0.12)
		rb.angular_velocity = Vector3(randf_range(-0.6, 0.6), randf_range(-0.4, 0.4), randf_range(-1.2, 1.2))
		viejo.queue_free()
		v.cuerpo = rb


# ------------------------------------------------------------------------------------------------------- daño
static func de(n: Node):
	return n.get_meta("tren") if n != null and n.has_meta("tren") else null


func danar(i: int, d: float, punto: Vector3) -> void:
	if i < 0 or i >= _vagones.size() or _vagones[i].roto:
		return
	if not _manda():
		Net.net_campana_pide("tren_dano:%d:%.1f" % [i, d])
		effects_chispas(punto)
		return
	effects_chispas(punto)
	_vagones[i].vida -= d
	if _vagones[i].vida <= 0.0:
		_romper(i)
		Net.net_campana("tren_roto", [i])


func effects_chispas(punto: Vector3) -> void:
	var fx = main.get("effects") if main else null
	if fx and fx.has_method("sparks"):
		fx.sparks(punto, Vector3.UP)
	Audio.choque("metal", "s", punto, -4.0, 30.0, Audio.PRI_LOW)


func _romper(i: int) -> void:
	var v: Dictionary = _vagones[i]
	if v.roto:
		return
	v.roto = true
	var c: Node3D = v.cuerpo
	var p: Vector3 = c.global_position + Vector3(0, 1.0, 0)
	var fx = main.get("effects") if main else null
	if fx:
		if fx.has_method("trozos_mazo"):
			fx.trozos_mazo(p, Vector3.UP, v.color, 24)
			fx.trozos_mazo(p, Vector3.UP, Color(0.15, 0.15, 0.16), 10)
		if fx.has_method("dust"):
			fx.dust(p, 1.2)
	Audio.rotura("metal", "l", p, 0.0, 50.0, Audio.PRI_HIGH)
	c.queue_free()
	print("[tren] vagon %d roto" % i)


## UN TIRO O UN MAZAZO (pedido: "que se rompa en voxels, no el pedazo entero, y que el choque siga a lo que queda"):
## el pedazo que recibe se vuelve de voxels y pierde los de una bola alrededor del golpe (mas grande con mas daño:
## una bala ~15 cm, un mazazo ~45). El vagon sigue andando. Con el vagon entero solo puede una explosion (danar).
const VOX := 0.12            ## m de cada voxel del tren
const CELDA_CHOQUE := 3      ## voxels por lado de cada caja de choque


func golpe_en(i: int, d: float, punto: Vector3) -> void:
	if i < 0 or i >= _vagones.size() or _vagones[i].roto:
		return
	effects_chispas(punto)
	var cuerpo: Node3D = _vagones[i].cuerpo
	var loc: Vector3 = cuerpo.global_transform.affine_inverse() * punto
	var mejor := ""
	var mejor_d := INF
	for nom in _vagones[i].partes:
		var pa: Dictionary = _vagones[i].partes[nom]
		if pa.roto:
			continue
		var ab: AABB = pa.ab
		var dd: float = loc.clamp(ab.position, ab.end).distance_to(loc)
		if dd < mejor_d:
			mejor_d = dd
			mejor = nom
	if mejor == "" or mejor_d > 1.0:
		return
	var r: float = clampf(0.08 + d * 0.0028, 0.14, 0.55)
	if not _manda():
		Net.net_campana_pide("tren_golpe:%d:%s:%.3f:%.3f:%.3f:%.3f" % [i, mejor, loc.x, loc.y, loc.z, r])
	else:
		Net.net_campana("tren_golpe", [i, mejor, loc.x, loc.y, loc.z, r])
	_quitar_vox(i, mejor, loc, r)


## el nodo de la malla en coordenadas del vagon
static func _en_cuerpo(b: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var x: Node = n
	while x != null and x != b:
		if x is Node3D:
			t = (x as Node3D).transform * t
		x = x.get_parent()
	return t


## EL PEDAZO HECHO VOXELS (la primera vez que se le pega): se recorren sus triangulos y se marca cada voxel por el que
## pasa la superficie, con el color de su material. Queda una cascara de voxels de VOX con la forma del modelo.
func _voxelizar(pa: Dictionary, cuerpo: Node3D) -> void:
	var mi: MeshInstance3D = pa.nodo
	var vox := {}
	var mesh: Mesh = mi.mesh
	var t: Transform3D = pa.t
	for si in mesh.get_surface_count():
		var col := Color(0.5, 0.5, 0.5)
		var m: Material = mi.get_active_material(si)
		if m is BaseMaterial3D:
			col = (m as BaseMaterial3D).albedo_color
		var arr: Array = mesh.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var ntri: int = (idx.size() if idx.size() > 0 else vs.size()) / 3
		for k in ntri:
			var a: Vector3 = t * vs[idx[k * 3] if idx.size() > 0 else k * 3]
			var b2: Vector3 = t * vs[idx[k * 3 + 1] if idx.size() > 0 else k * 3 + 1]
			var c: Vector3 = t * vs[idx[k * 3 + 2] if idx.size() > 0 else k * 3 + 2]
			var lado: float = maxf(a.distance_to(b2), maxf(b2.distance_to(c), c.distance_to(a)))
			var n: int = clampi(int(ceil(lado / (VOX * 0.5))), 1, 60)
			for u in n + 1:
				for v in n + 1 - u:
					var p: Vector3 = a + (b2 - a) * (float(u) / n) + (c - a) * (float(v) / n)
					var key := Vector3i(floori(p.x / VOX), floori(p.y / VOX), floori(p.z / VOX))
					if not vox.has(key):
						vox[key] = col
	pa.vox = vox
	mi.visible = false
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * VOX
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true          # (los colores van como el albedo de los materiales: sin esto salian lavados)
	mat.roughness = 0.5
	bm.material = mat
	mm.mesh = bm
	mmi.multimesh = mm
	cuerpo.add_child(mmi)
	pa.mm = mmi
	_rehacer_vox(pa, cuerpo)


## la malla de voxels y las cajas de choque de lo que queda (cajas de CELDA_CHOQUE voxels, juntadas a lo largo de x)
func _rehacer_vox(pa: Dictionary, cuerpo: Node3D) -> void:
	var vox: Dictionary = pa.vox
	var mm: MultiMesh = (pa.mm as MultiMeshInstance3D).multimesh
	mm.instance_count = vox.size()
	var k := 0
	var celdas := {}
	for key in vox:
		mm.set_instance_transform(k, Transform3D(Basis.IDENTITY, (Vector3(key) + Vector3(0.5, 0.5, 0.5)) * VOX))
		mm.set_instance_color(k, vox[key])
		k += 1
		celdas[Vector3i(floori(float(key.x) / CELDA_CHOQUE), floori(float(key.y) / CELDA_CHOQUE), floori(float(key.z) / CELDA_CHOQUE))] = true
	for cs in pa.choques:
		if is_instance_valid(cs):
			cs.queue_free()
	pa.choques = []
	var lc := VOX * CELDA_CHOQUE
	var hechas := {}
	for c in celdas:
		if hechas.has(c):
			continue
		var x1: int = c.x
		while celdas.has(Vector3i(x1 + 1, c.y, c.z)) and not hechas.has(Vector3i(x1 + 1, c.y, c.z)):
			x1 += 1
		for xx in range(c.x, x1 + 1):
			hechas[Vector3i(xx, c.y, c.z)] = true
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3((x1 - c.x + 1) * lc, lc, lc)
		cs.shape = bs
		cs.position = Vector3((c.x + x1 + 1) * 0.5 * lc, (c.y + 0.5) * lc, (c.z + 0.5) * lc)
		cuerpo.add_child(cs)
		pa.choques.append(cs)
	if vox.is_empty():
		pa.roto = true


func _quitar_vox(i: int, nom: String, loc: Vector3, r: float) -> void:
	if i >= _vagones.size() or _vagones[i].roto or not _vagones[i].partes.has(nom):
		return
	var pa: Dictionary = _vagones[i].partes[nom]
	if pa.roto:
		return
	var cuerpo: Node3D = _vagones[i].cuerpo
	if pa.vox == null:
		_voxelizar(pa, cuerpo)
	var vox: Dictionary = pa.vox
	var lo := Vector3i(floori((loc.x - r) / VOX), floori((loc.y - r) / VOX), floori((loc.z - r) / VOX))
	var hi := Vector3i(floori((loc.x + r) / VOX), floori((loc.y + r) / VOX), floori((loc.z + r) / VOX))
	var quitados := 0
	var col := Color(0.5, 0.5, 0.5)
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				var key := Vector3i(x, y, z)
				if vox.has(key) and ((Vector3(key) + Vector3(0.5, 0.5, 0.5)) * VOX).distance_to(loc) <= r:
					col = vox[key]
					vox.erase(key)
					quitados += 1
	if quitados == 0:
		return
	_rehacer_vox(pa, cuerpo)
	var fx = main.get("effects") if main else null
	var p_mundo: Vector3 = cuerpo.global_transform * loc
	if fx and fx.has_method("trozos_mazo"):
		fx.trozos_mazo(p_mundo, Vector3.UP, col.linear_to_srgb(), clampi(quitados, 3, 16))
	Audio.rotura("madera" if nom.begins_with("tronco") else "metal", "s" if quitados < 12 else "m", p_mundo, -2.0, 35.0, Audio.PRI_MID)


# ------------------------------------------------------------------------------------------------------- red
func _red_evento(ev: String, datos: Array) -> void:
	if _manda():
		return
	match ev:
		"tren_s":
			# si va muy distinto, salta; si no, se corrige poco a poco
			var s_host: float = float(datos[0])
			var dif: float = s_host - _s
			_s += dif if absf(dif) > 4.0 else dif * 0.5
			_parado = bool(datos[1])
		"tren_descarrila":
			_s = float(datos[0])
			_colocar()
			_descarrilar()
		"tren_roto":
			_romper(int(datos[0]))
		"tren_golpe":
			_quitar_vox(int(datos[0]), String(datos[1]), Vector3(float(datos[2]), float(datos[3]), float(datos[4])), float(datos[5]))


func _red_pide(accion: String, _de: int) -> void:
	if accion.begins_with("tren_golpe:"):
		var tp := accion.split(":")
		if tp.size() == 7:
			var lp := Vector3(float(tp[3]), float(tp[4]), float(tp[5]))
			Net.net_campana("tren_golpe", [int(tp[1]), tp[2], lp.x, lp.y, lp.z, float(tp[6])])
			_quitar_vox(int(tp[1]), tp[2], lp, float(tp[6]))
		return
	if not accion.begins_with("tren_dano:"):
		return
	var t := accion.split(":")
	if t.size() == 3:
		danar(int(t[1]), float(t[2]), _vagones[int(t[1])].cuerpo.global_position if int(t[1]) < _vagones.size() else Vector3.ZERO)


# ------------------------------------------------------------------------------------------------------- prueba
func _test() -> void:
	await get_tree().create_timer(6.0).timeout
	var p0: Vector3 = _vagones[0].cuerpo.global_position
	await get_tree().create_timer(2.0).timeout
	print("[trentest] anda: %.1f m en 2 s" % p0.distance_to(_vagones[0].cuerpo.global_position))
	var chim: MeshInstance3D = _vagones[0].partes.get("chimenea", {}).get("nodo")
	print("[trentest] pedazos de la locomotora: %s" % str(_vagones[0].partes.keys()))
	if chim:
		var pc: Vector3 = chim.global_transform * chim.get_aabb().get_center()
		var t0 := Time.get_ticks_msec()
		golpe_en(0, 30.0, pc)
		var pa: Dictionary = _vagones[0].partes["chimenea"]
		var s0 := _s
		await get_tree().create_timer(1.0).timeout
		print("[trentest] chimenea en voxels: %d quedan, %d cajas, %d ms; el tren sigue: %s" % [(pa.vox as Dictionary).size(),
			pa.choques.size(), Time.get_ticks_msec() - t0 - 1000, str(_s > s0 + 1.0)])
		var antes: int = (pa.vox as Dictionary).size()
		for _k in 30:
			var cv: Vector3 = _vagones[0].cuerpo.global_transform * (pa.t as Transform3D) * chim.get_aabb().get_center()
			golpe_en(0, 200.0, cv + Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.4), randf_range(-0.3, 0.3)))
		print("[trentest] tras 30 mazazos: de %d a %d voxels, roto %s" % [antes, (pa.vox as Dictionary).size(), str(pa.roto)])
	var f: Array = _punto(_s + 12.0)
	world.explode(f[0], 1.6, 400.0)
	print("[trentest] via rota en %s, hay via: %s" % [str(f[0]), str(_hay_via(f[0]))])
	await get_tree().create_timer(8.0).timeout
	print("[trentest] descarrilado: %s, loco en %s" % [str(_descarrilado), str(_vagones[0].cuerpo.global_position)])
	danar(1, 999.0, _vagones[1].cuerpo.global_position)
	print("[trentest] vagon 1 roto: %s" % str(_vagones[1].roto))
	print("[trentest] TERMINADO")
	get_tree().quit()
