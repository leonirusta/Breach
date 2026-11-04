extends Node3D
## Avatar voxel con rig por huesos y animaciones reales, portado de teardown-godot
## (scripts/AvatarAnimator.gd). Cada hueso es un Node3D con una malla de cubos; los clips
## vienen como listas (t, pos, quat) por hueso en avatar/sven_lagom.bin. La geometría se
## construye UNA vez y se comparte entre todas las instancias (jugador y bots): coste cero
## por instancia salvo los Node3D del rig.

## Esqueleto y arte del personaje. `soldier_rig.json` es el soldado detallado (12.824 voxels, el
## doble de resolucion); `avatar_rig.json` es el modelo viejo (1.141) y sigue ahi por si hay que
## volver. Los dos tienen los MISMOS huesos y posiciones de reposo, asi que las animaciones, la IK
## y las poses del arma valen para ambos: se cambia esta linea y ya.
const RIG_PATH := "res://avatar/soldier_rig.json"
const ANIM_PATH := "res://avatar/sven_lagom.bin"
const PALETTE_PATH := "res://avatar/palette.json"

static var _shared_meshes: Dictionary = {}   # hueso -> ArrayMesh (compartido)
static var _shared_rig: Dictionary = {}
static var _shared_clips: Dictionary = {}    # nombre -> {"fps", "bones": {hueso: [[px,py,pz,qx,qy,qz,qw,t],...]}}
static var _shared_bind: Dictionary = {}
static var _shared_bind_global: Dictionary = {}   # orientación global de reposo por hueso (cadena de binds)
static var _loaded := false
static var _alto_arte := 0.0          # alto del arte del rig en voxels (build)
static var _alto_arte_hecho := false

var bone_nodes: Dictionary = {}
var material: StandardMaterial3D
var current_clip := ""
var _time := 0.0
## Multiplicador de cadencia del clip. Sincronizar esto con la velocidad real evita que los
## pies patinen: al ir despacio el ciclo de correr se reproduce lento y se lee como andar.
## No afecta a la mezcla entre clips, que va en tiempo real para que las transiciones no se atasquen.
var anim_speed := 1.0
## Cuánto acompaña el arma a la zancada, 0..1. Lo fija el jugador según su velocidad real,
## para que al andar despacio apenas se mueva y al esprintar acompañe.
var sway_amount := 1.0
## Inercia de la mirada (weapon sway), en rad: al girar la cámara el arma se queda atrás y se
## reacomoda. Lo fija el dueño; en cero (bots) no cambia nada. Se ve también en tercera persona
## porque gira el arma alrededor del cuello y los brazos la siguen por IK.
## Cuánto se está moviendo el dueño, 0..1. El arma va baja al andar y arriba al pararse.
var move_amount := 0.0
var _lower_w := 0.0
## APUNTANDO. Lo pone el dueno (jugador o bot) cada frame. Sube el arma hasta el ojo derecho y
## entorna el ojo izquierdo, que es lo que se ve desde fuera cuando alguien encara el arma.
var aiming := false
var _aim_w := 0.0
var look_sway := Vector2.ZERO
const LOOK_SWAY_ROT := 0.85
## Ganancia del balanceo lateral del arma. Deliberadamente baja: con la original (5.0) el arma
## barría 204° de pico a pico corriendo, medido sobre el avance del pie derecho. ~7° acompaña
## el paso sin llamar la atención.
const SWAY_GAIN := 0.18
var _sway_ang := 0.0
var _blend_from := ""
var _blend_time := 0.0
var _blend_prev_time := 0.0     ## en que instante se dejo el clip anterior (para mezclar desde ahi)
var _blend_duration := 0.15
## Duración de la mezcla entre clips; el dueño la sube al pasar a reposo para que la parada
## no se vea de golpe.
var blend_time := 0.15

static func _load_shared() -> void:
	if _loaded:
		return
	_loaded = true
	var rf := FileAccess.open(RIG_PATH, FileAccess.READ)
	if rf:
		var d = JSON.parse_string(rf.get_as_text())
		if typeof(d) == TYPE_DICTIONARY:
			_shared_rig = d
	var pal: Array = []
	var pf := FileAccess.open(PALETTE_PATH, FileAccess.READ)
	if pf:
		var p = JSON.parse_string(pf.get_as_text())
		if typeof(p) == TYPE_ARRAY:
			pal = p
	_shared_pal = pal          # se guarda para poder rehornear el soldado con otra ropa
	var bones: Dictionary = _shared_rig.get("bones", {})
	for bname in bones.keys():
		var vox: Array = bones[bname]["voxels"]
		if bname == "hand_l" or bname == "hand_r":
			vox = _mano_sin_dedos(vox)
		vox = _recortar_hood(bones, String(bname), vox)
		var m := _build_bone_mesh(vox, pal)
		if m:
			_shared_meshes[bname] = m
	_load_animations()

## LA OTRA "HOMBRERA" (2026-10-28, pedido: "le veo la hombrera en el brazo derecho, mira la espalda"): el bloque de
## arriba de la espalda (`hood`, lo alto del chaleco) esta corrido hacia un lado y asomaba sobre el hombro derecho.
## Se quitan sus voxels que caen fuera del ancho del pecho. `--hombroantes` = como antes.
static func _recortar_hood(bones: Dictionary, bname: String, vox: Array) -> Array:
	if bname != "hood" or _hombro_antes or not bones.has("chest") or not bones.has("hood"):
		return vox
	var cx: float = float(bones["chest"]["world_pos"][0]) + _mesh_off(bones, "chest").x
	var xmin := INF
	var xmax := -INF
	for v in bones["chest"]["voxels"]:
		xmin = minf(xmin, cx + float(v[0]))
		xmax = maxf(xmax, cx + float(v[0]))
	var hx: float = float(bones["hood"]["world_pos"][0]) + _mesh_off(bones, "hood").x
	var out: Array = []
	for v in vox:
		var x: float = hx + float(v[0])
		if x >= xmin - 0.01 and x <= xmax + 0.01:
			out.append(v)
	return out


## Malla de cubos de un hueso (culling de caras entre voxels vecinos, color de paleta).
## MANO CUADRADA, SIN DEDOS. El modelo trae dedos modelados voxel a voxel: a la escala a la que se
## ve el personaje no se distinguen, y de cerca (primera persona) se ven como pinchos sueltos.
## Se sustituye la mano por un bloque macizo, tipo manopla.
##
## Que extremo es el de los dedos no se sabe de antemano (depende de como se exportara el modelo),
## asi que se deduce: se cuenta cuantos voxels hay en cada rodaja a lo largo del eje mas largo, y
## el lado con menos relleno son los dedos (estan separados y dejan huecos). Se recorta ese lado y
## el resto se rellena entero.
static func _mano_sin_dedos(voxels: Array) -> Array:
	if voxels.size() < 4:
		return voxels
	var mn := Vector3i(999999, 999999, 999999)
	var mx := Vector3i(-999999, -999999, -999999)
	var colores := {}
	for v in voxels:
		var c := Vector3i(int(v[0]), int(v[1]), int(v[2]))
		mn = Vector3i(mini(mn.x, c.x), mini(mn.y, c.y), mini(mn.z, c.z))
		mx = Vector3i(maxi(mx.x, c.x), maxi(mx.y, c.y), maxi(mx.z, c.z))
		var idx := int(v[3])
		colores[idx] = int(colores.get(idx, 0)) + 1
	# color mas repetido: el de la piel de la mano
	var color := 0
	var mejor := -1
	for k in colores.keys():
		if int(colores[k]) > mejor:
			mejor = int(colores[k])
			color = int(k)
	var tam := mx - mn + Vector3i.ONE
	# eje mas largo = el que va de la muneca a la punta de los dedos
	var eje := 0
	if tam.y >= tam.x and tam.y >= tam.z:
		eje = 1
	elif tam.z >= tam.x and tam.z >= tam.y:
		eje = 2
	var largo: int = [tam.x, tam.y, tam.z][eje]
	# LA MANO DE ESTE MODELO SON 8 VOXELES SUELTOS en una caja de 3x2x3, con huecos: esos salientes
	# en diagonal son los que se ven como dedos. No hay nada que recortar, hay que RELLENAR. El
	# recorte del extremo solo tiene sentido en manos largas con dedos modelados de verdad.
	if largo < 5:
		var lleno: Array = []
		for x in range(mn.x, mx.x + 1):
			for y in range(mn.y, mx.y + 1):
				for z in range(mn.z, mx.z + 1):
					lleno.append([x, y, z, color])
		return _puno_redondo(lleno, mn, mx)
	# relleno de cada rodaja
	var rodaja := PackedInt32Array()
	rodaja.resize(largo)
	for v in voxels:
		var c := Vector3i(int(v[0]), int(v[1]), int(v[2])) - mn
		var i: int = [c.x, c.y, c.z][eje]
		if i >= 0 and i < largo:
			rodaja[i] += 1
	var tercio: int = maxi(1, largo / 3)
	var a := 0
	var b := 0
	for i in tercio:
		a += rodaja[i]
		b += rodaja[largo - 1 - i]
	# se recorta un 30 % por el lado flojo (los dedos)
	var corte: int = maxi(1, int(round(largo * 0.30)))
	var desde: int = corte if a < b else 0
	var hasta: int = largo if a < b else largo - corte
	var out: Array = []
	for x in range(mn.x, mx.x + 1):
		for y in range(mn.y, mx.y + 1):
			for z in range(mn.z, mx.z + 1):
				var c := Vector3i(x, y, z) - mn
				var i: int = [c.x, c.y, c.z][eje]
				if i < desde or i >= hasta:
					continue
				out.append([x, y, z, color])
	return _puno_redondo(out)


## PUÑO REDONDEADO (2026-09-27, pedido: "no me gusta que la mano sea cuadrada"). A la caja se le quitan las
## ARISTAS: los voxels que estan en el borde de dos ejes a la vez (contando solo los ejes de 3 o mas). En la
## mano del soldado, 3x2x3, cada capa queda en cruz y se lee como un puño, no como un dado.
static func _puno_redondo(caja: Array, mn := Vector3i(999999, 999999, 999999), mx := Vector3i(-999999, -999999, -999999)) -> Array:
	if caja.is_empty():
		return caja
	if mn.x == 999999:
		for v in caja:
			mn = Vector3i(mini(mn.x, int(v[0])), mini(mn.y, int(v[1])), mini(mn.z, int(v[2])))
			mx = Vector3i(maxi(mx.x, int(v[0])), maxi(mx.y, int(v[1])), maxi(mx.z, int(v[2])))
	var out: Array = []
	for v in caja:
		var bordes := 0
		for k in 3:
			var lo: int = [mn.x, mn.y, mn.z][k]
			var hi: int = [mx.x, mx.y, mx.z][k]
			var c: int = int(v[k])
			if hi - lo >= 2 and (c == lo or c == hi):
				bordes += 1
		if bordes < 2:
			out.append(v)
	return out


# ---------------------------------------------------------------------------
# SKINS DE DISENO. Una skin no es un tinte encima de todo (eso lavaba tambien la cara): REPINTA
# partes concretas del soldado, cada una por su lado. Asi hay skins con otro pantalon, otro casco o
# otras botas, no solo el mismo muneco de otro color.
# La piel, los ojos, las cejas, el cristal de las gafas, el metal y el parche rojo NO se tocan
# NUNCA: eso es la persona y sus cacharros, no la ropa.
# ---------------------------------------------------------------------------
## Los colores del soldado son los 19 ultimos de la paleta (los pone tools/make_soldier.py), asi que
## el primero se calcula desde el final: si manana el script anade colores, esto sigue cuadrando.
const SOLDADO_COLORES := 19          ## solo por si un rig viejo no lo dice


## Cuantos colores del final de la paleta son del soldado. Lo dice el propio rig: al anadir los de
## podredumbre y laton pasaron de 19 a 27, y dandolo por hecho se habria descuadrado la ropa entera.
static func _colores_soldado() -> int:
	return int(_shared_rig.get("colores_soldado", SOLDADO_COLORES))
## Que prenda es cada uno de esos 19 colores. Los que faltan son los intocables.
## El 17 es el IRIS: no es ropa, pero se repinta igual y con eso se cambia el color de la mirada.
const SKIN_PRENDA := {0: "guerrera", 1: "guerrera", 2: "guerrera", 3: "cinchas",
	4: "equipo", 5: "equipo", 6: "casco", 7: "casco", 8: "botas", 15: "bolsillos",
	17: "ojos"}
## Huesos de la mitad de abajo: ahi la tela de la guerrera es en realidad el PANTALON. Es lo que
## permite que una skin lleve pantalon de otro color que la chaqueta.
const HUESOS_PANTALON := ["pelvis", "leg_upper_l", "leg_upper_r", "leg_lower_l", "leg_lower_r"]


## El color final de un voxel segun la receta de la skin. `rel` es su hueco entre los 19 colores del
## soldado. Los tonos claros y oscuros de cada prenda se sacan del color base, asi que la receta
## solo tiene que decir UN color por prenda y los pliegues y las partes altas salen solos.
static func _color_skin(rel: int, bname: String, receta: Dictionary, base: Color) -> Color:
	if receta.is_empty() or not SKIN_PRENDA.has(rel):
		return base
	var prenda: String = SKIN_PRENDA[rel]
	if prenda == "guerrera" and bname in HUESOS_PANTALON:
		prenda = "pantalon"
	if not receta.has(prenda):
		return base
	var c: Color = receta[prenda]
	match rel:
		1: return c.darkened(0.24)      # pliegues, axilas, entrepierna
		2: return c.lightened(0.16)     # partes altas, donde da la luz
		5: return c.darkened(0.30)      # negro profundo del equipo
		7: return c.lightened(0.14)     # lo alto del casco
		_: return c


static func _build_bone_mesh(voxels: Array, pal: Array, receta: Dictionary = {}, bname: String = "") -> ArrayMesh:
	if voxels.is_empty():
		return null
	var solid := {}
	for v in voxels:
		solid[Vector3i(int(v[0]), int(v[1]), int(v[2]))] = int(v[3])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dirs := [Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,1,0), Vector3i(0,-1,0), Vector3i(0,0,1), Vector3i(0,0,-1)]
	var shade: Array[float] = [0.85, 0.75, 1.0, 0.55, 0.9, 0.8]
	for c in solid.keys():
		var idx: int = solid[c]
		var col := Color(0.8, 0.6, 0.5)
		if idx >= 0 and idx < pal.size():
			var p = pal[idx]
			col = Color8(int(p[0]), int(p[1]), int(p[2]))
		if not receta.is_empty():
			col = _color_skin(idx - (pal.size() - _colores_soldado()), bname, receta, col)
		for fi in range(6):
			var d: Vector3i = dirs[fi]
			if solid.has(c + d):
				continue
			var n := Vector3(d)
			var base := Vector3(c) + Vector3(0.5, 0.5, 0.5) + n * 0.5
			# ejes tangenciales
			var u := Vector3(0, 1, 0) if abs(n.y) < 0.5 else Vector3(1, 0, 0)
			var w := n.cross(u)
			u = w.cross(n)
			var cc: Color = col.srgb_to_linear() * shade[fi]
			cc.a = 1.0
			var p0 := base + (-u - w) * 0.5
			var p1 := base + (u - w) * 0.5
			var p2 := base + (u + w) * 0.5
			var p3 := base + (-u + w) * 0.5
			st.set_normal(n)
			st.set_color(cc)
			# horario visto desde fuera (Godot)
			for p in [p0, p2, p1, p0, p3, p2]:
				st.add_vertex(p)
	return st.commit()

## Los cuaterniones del .bin están en los ejes originales del modelo (MagicaVoxel, Z arriba); el rig JSON
## ya está en Y arriba. Conjugar por la rotación de ejes (x -> z) los pasa al marco del rig. Se verificó
## numéricamente: es la única permutación que mantiene la pose T exacta y deja los brazos colgando en
## ik_pose_a e idle (sin ella, las claves giraban los huesos sobre su propio eje y los brazos se despegaban).
const _AXIS_FIX := Quaternion(Vector3.UP, -PI / 2.0)
static func _to_rig_axes(q: Quaternion) -> Quaternion:
	return (_AXIS_FIX * q.normalized() * _AXIS_FIX.inverse()).normalized()

static func _load_animations() -> void:
	var f := FileAccess.open(ANIM_PATH, FileAccess.READ)
	if not f:
		return
	var n_bones := f.get_32()
	for i in range(n_bones):
		var l := f.get_16()
		var bname := f.get_buffer(l).get_string_from_ascii()
		var qbuf := f.get_buffer(16)
		_shared_bind[bname] = _to_rig_axes(Quaternion(qbuf.decode_float(0), qbuf.decode_float(4), qbuf.decode_float(8), qbuf.decode_float(12)))
	var n_clips := f.get_32()
	for i in range(n_clips):
		var nl := f.get_16()
		var clip_name := f.get_buffer(nl).get_string_from_ascii()
		var fps := f.get_float()
		var bone_count := f.get_32()
		var clip_bones := {}
		for b in range(bone_count):
			var bnl := f.get_16()
			var bone_name := f.get_buffer(bnl).get_string_from_ascii()
			var n_keys := f.get_32()
			var keys: Array = []
			for k in range(n_keys):
				var buf := f.get_buffer(32)
				var q := _to_rig_axes(Quaternion(buf.decode_float(12), buf.decode_float(16), buf.decode_float(20), buf.decode_float(24)))
				keys.append([buf.decode_float(0), buf.decode_float(4), buf.decode_float(8), q.x, q.y, q.z, q.w, buf.decode_float(28)])
			clip_bones[bone_name] = keys
		_shared_clips[clip_name] = {"fps": fps, "bones": clip_bones}
	f.close()
	_cargar_clips_breach()
	_shared_baked.clear()
	# Formato (verificado con ik_pose_t / ik_pose_a): el bind del .bin ES la pose T con la que está
	# modelado el voxel, y tanto el bind como las claves son rotaciones LOCALES respecto al marco del
	# hueso padre (la pelvis lleva una permutación de ejes de 120°). Por eso el esqueleto se construye
	# con esos marcos nativos (ver _prepare_rig) y las claves se aplican tal cual.

## CLIPS HECHOS EN BLENDER para este soldado (tools/blender/caminar_anim.py + exportar_clips.py): el
## paso de caminar y la carrera militar. Mismo formato que las claves del .bin -rotacion local respecto
## al padre en los marcos del rig-, asi que las mezclas, la zancada y el ajuste de suelo les valen igual.
## Traen ademas el vaiven de la pelvis (voxels), que los clips del .bin no tienen.
const CLIPS_BREACH_PATH := "res://avatar/clips_breach.json"
static var _clip_pelvis: Dictionary = {}

static func _cargar_clips_breach() -> void:
	var f := FileAccess.open(CLIPS_BREACH_PATH, FileAccess.READ)
	if not f:
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return
	for clip_name in d.keys():
		var c: Dictionary = d[clip_name]
		var clip_bones := {}
		for bname in c["bones"].keys():
			var keys: Array = []
			for k in c["bones"][bname]:
				keys.append([0.0, 0.0, 0.0, float(k[1]), float(k[2]), float(k[3]), float(k[4]), float(k[0])])
			clip_bones[bname] = keys
		_shared_clips[clip_name] = {"fps": float(c.get("fps", 30.0)), "bones": clip_bones}
		if c.has("pelvis"):
			var ts := PackedFloat32Array()
			var ps := PackedVector3Array()
			for k in c["pelvis"]:
				ts.append(float(k[0]))
				ps.append(Vector3(float(k[1]), float(k[2]), float(k[3])))
			_clip_pelvis[clip_name] = {"t": ts, "p": ps}
		if c.has("arma"):
			_clip_arma[clip_name] = _leer_pista_arma(c["arma"])
		if c.has("raiz"):
			_clip_raiz[clip_name] = _leer_pista_raiz(c["raiz"], float(c.get("alto", 1.75)))
	for nombre in CLIPS_ESPEJO:
		_espejar_clip(nombre)


## EL PUÑETAZO CON EL BRAZO DE ORO (2026-09-30, pedido: "el brazo de oro es el derecho, como en la lamina, y el puñetazo
## se da con ese"). El clip de Blender pega con los huesos _r; el brazo de oro de "Puño de Oro" (el derecho anatomico: de
## frente, a la izquierda de la pantalla) son los _l. Se ESPEJA AL CARGAR, entero (pelvis, tronco, cabeza y piernas
## tambien, para que el cuerpo siga siendo coherente): cada hueso toma la deformacion de su pareja (_l <-> _r) reflejada
## en el plano YZ del rig (x -> -x). La deformacion es D = Q * Qreposo^-1, la rotacion global respecto a la de reposo:
## asi da igual como esten orientados los marcos nativos de cada hueso. D' = S D S es el cuaternion (x, -y, -z, w). El
## vaiven de la pelvis va con la x al reves. Solo el puñetazo: el arma, las recargas y lo demas no se tocan.
const CLIPS_ESPEJO := ["punetazo"]


static func _pareja(b: String) -> String:
	if b.ends_with("_l"):
		return b.substr(0, b.length() - 2) + "_r"
	if b.ends_with("_r"):
		return b.substr(0, b.length() - 2) + "_l"
	if b.contains("_l_"):
		return b.replace("_l_", "_r_")
	if b.contains("_r_"):
		return b.replace("_r_", "_l_")
	return b


static func _espejar_clip(nombre: String) -> void:
	var clip: Dictionary = _shared_clips.get(nombre, {})
	if clip.is_empty():
		return
	var cb: Dictionary = clip["bones"]
	if cb.is_empty():
		return
	var parents: Dictionary = _shared_rig.get("bone_parents", {})
	# todos los huesos, con los padres antes que los hijos
	var todos := {}
	for b in _shared_bind.keys():
		todos[String(b)] = true
	for b in cb.keys():
		todos[String(b)] = true
	var orden: Array = []
	var puesto := {}
	var guarda := 0
	while orden.size() < todos.size() and guarda < 64:
		guarda += 1
		for b in todos.keys():
			if puesto.has(b):
				continue
			var pb = parents.get(b)
			if pb == null or not todos.has(String(pb)) or puesto.has(String(pb)):
				orden.append(b)
				puesto[b] = true
	var reposo := {}
	for b in orden:
		var pb = parents.get(b)
		var bind: Quaternion = _shared_bind.get(b, Quaternion.IDENTITY)
		reposo[b] = ((reposo[String(pb)] as Quaternion) * bind).normalized() if pb != null and reposo.has(String(pb)) else bind
	var primero: String = cb.keys()[0]
	var ref: Array = cb[primero]
	var nuevas := {}
	for b in cb.keys():
		nuevas[b] = []
	for i in ref.size():
		var t: float = float(ref[i][7])
		var glob := {}
		for b in orden:
			var q: Quaternion = _shared_bind.get(b, Quaternion.IDENTITY)
			if cb.has(b):
				var ks: Array = cb[b]
				var k: Array = ks[i] if ks.size() == ref.size() else ks[clampi(int(round(t / maxf(0.0001, float(ref.back()[7])) * (ks.size() - 1))), 0, ks.size() - 1)]
				q = Quaternion(float(k[3]), float(k[4]), float(k[5]), float(k[6])).normalized()
			var pb = parents.get(b)
			glob[b] = ((glob[String(pb)] as Quaternion) * q).normalized() if pb != null and glob.has(String(pb)) else q
		var espejo := {}
		for b in orden:
			var par := _pareja(b)
			if not glob.has(par):
				par = b
			var d: Quaternion = (glob[par] as Quaternion) * (reposo[par] as Quaternion).inverse()
			espejo[b] = (Quaternion(d.x, -d.y, -d.z, d.w) * (reposo[b] as Quaternion)).normalized()
		for b in cb.keys():
			var pb = parents.get(b)
			var ql: Quaternion = espejo[b]
			if pb != null and espejo.has(String(pb)):
				ql = ((espejo[String(pb)] as Quaternion).inverse() * ql).normalized()
			(nuevas[b] as Array).append([0.0, 0.0, 0.0, ql.x, ql.y, ql.z, ql.w, t])
	clip["bones"] = nuevas
	if _clip_pelvis.has(nombre):
		var ps: PackedVector3Array = _clip_pelvis[nombre]["p"]
		for i in ps.size():
			ps[i] = Vector3(-ps[i].x, ps[i].y, ps[i].z)
		_clip_pelvis[nombre]["p"] = ps
	_shared_baked.erase(nombre)

## LA RAIZ DE LA SUBIDA (tools/blender/trepar_real_anim.py, exportar_clips.py ... unavez). Por frame: donde
## estan los pies respecto al borde que se escala y tres pesos. Ya en metros del avatar del juego (se animo
## sobre un soldado de 1,75 m y el del juego mide ALTURA).
static var _clip_raiz: Dictionary = {}
const RAIZ_CANALES := ["delante", "arriba", "lado", "manos", "arma", "esfuerzo"]

static func _leer_pista_raiz(filas: Array, alto: float) -> Dictionary:
	var k: float = ALTURA / maxf(alto, 0.01)
	var out := {"t": PackedFloat32Array()}
	for n in RAIZ_CANALES:
		out[n] = PackedFloat32Array()
	for fila in filas:
		out["t"].append(float(fila[0]))
		for i in RAIZ_CANALES.size():
			# las tres primeras son distancias y escalan con el cuerpo; los pesos no
			out[RAIZ_CANALES[i]].append(float(fila[i + 1]) * (k if i < 3 else 1.0))
	return out

## La subida en el segundo `t` del clip: {delante, arriba, lado (m), manos, arma, esfuerzo (0..1)}.
## Vacio si el clip no trae raiz (el de antes, o si falta el archivo).
static func trepar_muestra(t: float) -> Dictionary:
	if not _clip_raiz.has("trepar"):
		return {}
	var r: Dictionary = _clip_raiz["trepar"]
	var ts: PackedFloat32Array = r["t"]
	var n := ts.size()
	if n == 0:
		return {}
	var i1 := ts.bsearch(t)
	var i0 := clampi(i1 - 1, 0, n - 1)
	i1 = clampi(i1, 0, n - 1)
	var a: float = 0.0 if i0 == i1 else clampf((t - ts[i0]) / maxf(ts[i1] - ts[i0], 1e-5), 0.0, 1.0)
	var out := {}
	for c in RAIZ_CANALES:
		var v: PackedFloat32Array = r[c]
		out[c] = lerpf(v[i0], v[i1], a)
	return out

## MUROS MAS BAJOS QUE EL DE BLENDER. `suelo_rel` es donde esta el suelo respecto al canto (negativo). El
## tramo en el que los pies irian por debajo de ese suelo no existe en ese muro: la subida empieza despues,
## con los pies ya a la altura que toca en la pared. Un muro igual o mas alto que el animado empieza en 0.
static func trepar_inicio(suelo_rel: float) -> float:
	if not _clip_raiz.has("trepar"):
		return 0.0
	var r: Dictionary = _clip_raiz["trepar"]
	var arriba: PackedFloat32Array = r["arriba"]
	for i in range(arriba.size() - 1, -1, -1):
		if arriba[i] < suelo_rel - 0.02:
			return float(r["t"][i])
	return 0.0

## EL FUSIL DE BLENDER (exportar_clips.py ... arma). Por frame: origen del arma respecto al cuello, giro,
## las dos munecas y el giro de cada mano en el espacio del arma, y los dos codos respecto al cuello; en
## voxels y ejes del esqueleto. Solo lo traen los ciclos de marcha hechos en Blender (caminar, agachado).
static var _clip_arma: Dictionary = {}

static func _leer_pista_arma(filas: Array) -> Dictionary:
	var ts := PackedFloat32Array()
	var vs := {"pos": PackedVector3Array(), "gat": PackedVector3Array(), "apo": PackedVector3Array(),
		"cgat": PackedVector3Array(), "capo": PackedVector3Array()}
	var qs := {"rot": [], "qgat": [], "qapo": []}
	var v := func(k: Array, i: int) -> Vector3:
		return Vector3(float(k[i]), float(k[i + 1]), float(k[i + 2]))
	var q := func(k: Array, i: int) -> Quaternion:
		return Quaternion(float(k[i]), float(k[i + 1]), float(k[i + 2]), float(k[i + 3])).normalized()
	for k in filas:
		ts.append(float(k[0]))
		vs["pos"].append(v.call(k, 1))
		qs["rot"].append(q.call(k, 4))
		vs["gat"].append(v.call(k, 8))
		vs["apo"].append(v.call(k, 11))
		qs["qgat"].append(q.call(k, 14))
		qs["qapo"].append(q.call(k, 18))
		vs["cgat"].append(v.call(k, 22))
		vs["capo"].append(v.call(k, 25))
	var out := {"t": ts}
	out.merge(vs)
	out.merge(qs)
	return out

## La pista del arma en el instante `t` del clip, interpolada; vacia si el clip no la trae.
static func _pista_arma(clip_name: String, t: float) -> Dictionary:
	var pa: Dictionary = _clip_arma.get(clip_name, {})
	if pa.is_empty():
		return {}
	var ts: PackedFloat32Array = pa["t"]
	var n := ts.size()
	var i := clampi(ts.bsearch(t) - 1, 0, n - 2)
	var w := clampf((t - ts[i]) / maxf(ts[i + 1] - ts[i], 1e-5), 0.0, 1.0)
	var out := {}
	for k in ["pos", "gat", "apo", "cgat", "capo"]:
		out[k] = (pa[k][i] as Vector3).lerp(pa[k][i + 1], w)
	for k in ["rot", "qgat", "qapo"]:
		out[k] = (pa[k][i] as Quaternion).slerp(pa[k][i + 1], w)
	return out

## Mezcla de dos muestras de la pista (al pasar de un clip con arma a otro con arma).
static func _mezclar_pista(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	var out := {}
	for k in ["pos", "gat", "apo", "cgat", "capo"]:
		out[k] = (a[k] as Vector3).lerp(b[k], w)
	for k in ["rot", "qgat", "qapo"]:
		out[k] = (a[k] as Quaternion).slerp(b[k], w)
	return out

## Cuanto se aparta la pelvis de su reposo en el instante `t` del clip (cero si el clip no lo trae).
static func _pelvis_off(clip_name: String, t: float) -> Vector3:
	var tr: Dictionary = _clip_pelvis.get(clip_name, {})
	if tr.is_empty():
		return Vector3.ZERO
	var ts: PackedFloat32Array = tr["t"]
	var ps: PackedVector3Array = tr["p"]
	var n := ts.size()
	if n == 0:
		return Vector3.ZERO
	if t <= ts[0]:
		return ps[0]
	if t >= ts[n - 1]:
		return ps[n - 1]
	var i := clampi(ts.bsearch(t) - 1, 0, n - 2)
	var w := clampf((t - ts[i]) / maxf(ts[i + 1] - ts[i], 1e-5), 0.0, 1.0)
	return ps[i].lerp(ps[i + 1], w)

## Pre-horneado por clip: tiempos en PackedFloat32Array y cuaterniones ya multiplicados por bind^-1.
## Se calcula una vez (compartido entre avatares) y ahorra ~10x en el muestreo por frame.
## Clips en los que el cuerpo va por el aire: no se les ajusta el pie al suelo (ver _baked).
const AIRE := {"jump_start": true, "jump_loop": true, "jump_end": true}
static var _shared_baked: Dictionary = {}
static func _baked(clip_name: String) -> Dictionary:
	if _shared_baked.has(clip_name):
		return _shared_baked[clip_name]
	var clip: Dictionary = _shared_clips[clip_name]
	var out := {"bones": {}, "dur": 0.0, "ground": 0.0}
	var parents: Dictionary = _shared_rig.get("bone_parents", {})
	for bname in clip["bones"].keys():
		var keys: Array = clip["bones"][bname]
		var ts := PackedFloat32Array()
		var qs: Array[Quaternion] = []
		for k in keys:
			ts.append(k[7])
			# rotación local respecto al padre, en el marco nativo del rig: se aplica tal cual
			qs.append(Quaternion(k[3], k[4], k[5], k[6]).normalized())
		if ts.size() > 0:
			out["dur"] = max(out["dur"], ts[ts.size() - 1])
		out["bones"][bname] = {"t": ts, "q": qs}
	# Los clips no traen traslación de la raíz (Teardown mueve el cuerpo entero desde el controlador), así
	# que al agacharse o saltar las piernas se doblan pero la pelvis se queda a la altura de pie y el
	# personaje "flota". Se calcula por clip cuánto hay que bajar el esqueleto para que, en el instante en
	# que un pie está más bajo, ese pie quede a la altura del pie en reposo (FK sobre 24 muestras).
	_prepare_rig()
	var feet := ["foot_l", "foot_r", "toes_l", "toes_r"]
	# altura de los pies en reposo (posiciones del rig, con el suelo en y = 0)
	var bones_wp: Dictionary = _shared_rig.get("bones", {})
	var min_y := INF
	for bname in bones_wp.keys():
		min_y = min(min_y, bones_wp[bname]["world_pos"][1])
	var rest_foot := INF
	for fb in feet:
		if bones_wp.has(fb):
			rest_foot = min(rest_foot, float(bones_wp[fb]["world_pos"][1]) + _mesh_off(bones_wp, fb).y - min_y)
	var min_foot := INF
	var samples := 24
	for si in samples:
		var tt: float = out["dur"] * float(si) / float(samples)
		var glob := {}
		for bname in _shared_bone_order:
			var pname = parents.get(bname)
			var local: Vector3 = _shared_rest_local[bname]
			if pname == null:
				local += _pelvis_off(clip_name, tt)   # con la pelvis baja, el pie tambien baja
			var q: Quaternion = _shared_bind.get(bname, Quaternion.IDENTITY)
			if out["bones"].has(bname):
				q = _sample_baked(out["bones"][bname], tt)
			var xf := Transform3D(Basis(q), local)
			glob[bname] = (glob[pname] * xf) if pname != null else xf
		for fb in feet:
			if glob.has(fb):
				min_foot = min(min_foot, ((glob[fb] as Transform3D) * _mesh_off(bones_wp, fb)).y)
	if rest_foot < INF and min_foot < INF:
		out["ground"] = rest_foot - min_foot
	# EN EL AIRE NO HAY PIE APOYADO, ASI QUE NO HAY NADA QUE APOYAR.
	#
	# Este ajuste sube o baja el esqueleto para que el pie mas bajo del clip toque el suelo. Tiene
	# sentido andando, donde el pie DEBE quedarse plantado, y en los clips de andar sale un retoque
	# de menos de un voxel (idle +0,60 · run_fwd -0,17 · jump_land -0,65).
	#
	# Pero en vuelo las piernas se recogen, y forzarlas al suelo baja el CUERPO ENTERO: jump_loop
	# pedia -16,61 voxels, casi ochenta centimetros. Eso es lo que se veia al saltar — el personaje
	# se hundia de golpe y volvia, y parecia que hacia la animacion de aterrizar sin haber tocado
	# nada. No era la animacion: era el cuerpo cayendose bajo sus pies.
	# Y un clip que trae su propia raiz (la subida) ya pone el cuerpo donde va: player.gd mueve al jugador
	# con esa pista, y apoyar ademas el pie mas bajo lo desplazaria del muro.
	if AIRE.has(clip_name) or _clip_raiz.has(clip_name):
		out["ground"] = 0.0
	# Y RED DE SEGURIDAD para cualquier otro clip: mas de dos voxels de correccion no es "ajustar el
	# pie al suelo", es que ese clip no tiene un pie que apoyar.
	out["ground"] = clampf(float(out["ground"]), -2.0, 2.0)
	# LOS INSTANTES COMUNES (2026-10-01, rendimiento): si todos los huesos tienen las claves en los mismos instantes
	# (lo normal: los clips salen de Blender a fps fijos), el fotograma y el peso se buscan UNA vez por clip y no una por
	# hueso (`_muestra_comun`). Si alguno difiere, `t_comun` queda vacio y se muestrea hueso a hueso como siempre.
	var t_comun := PackedFloat32Array()
	var primero := true
	for bn in (out["bones"] as Dictionary).keys():
		var tsb: PackedFloat32Array = out["bones"][bn]["t"]
		if primero:
			t_comun = tsb
			primero = false
		elif tsb != t_comun:
			t_comun = PackedFloat32Array()
			break
	out["t_comun"] = t_comun
	# EN PLANO PARA EL C++ (AnimMuestreo): [fotograma][casilla de _shared_bone_order][x, y, z, w] y que casillas trae
	if not t_comun.is_empty():
		var ns := _shared_bone_order.size()
		var nf := t_comun.size()
		var qf := PackedFloat32Array()
		qf.resize(nf * ns * 4)
		var mk := PackedByteArray()
		mk.resize(ns)
		for si2 in ns:
			var bd = (out["bones"] as Dictionary).get(_shared_bone_order[si2])
			if bd == null:
				continue
			mk[si2] = 1
			var qsb: Array[Quaternion] = bd["q"]
			for f in nf:
				var qq: Quaternion = qsb[f]
				var k := (f * ns + si2) * 4
				qf[k] = qq.x
				qf[k + 1] = qq.y
				qf[k + 2] = qq.z
				qf[k + 3] = qq.w
		out["qflat"] = qf
		out["qmask"] = mk
	if "--posedbg" in OS.get_cmdline_user_args():
		print("[pose] %s dur %.2f rest_foot %.2f min_foot %.2f ground %.2f" % [clip_name, out["dur"], rest_foot, min_foot, out["ground"]])
	_shared_baked[clip_name] = out
	return out

## [modo, i, w] para muestrear en `t` unas claves en los instantes `ts`, EXACTAMENTE como _sample_baked:
## modo 0 = la primera, 1 = la ultima, 2 = slerp(i, i + 1, w). Vacio si no hay instantes comunes.
static func _muestra_comun(ts: PackedFloat32Array, t: float) -> Array:
	var n := ts.size()
	if n == 0:
		return []
	if n == 1 or t <= ts[0]:
		return [0, 0, 0.0]
	if t >= ts[n - 1]:
		return [1, n - 1, 0.0]
	var i := ts.bsearch(t) - 1
	i = clampi(i, 0, n - 2)
	var ta := ts[i]
	var tb := ts[i + 1]
	var w := 0.0 if tb <= ta else clampf((t - ta) / (tb - ta), 0.0, 1.0)
	return [2, i, w]

static func _muestra_con(b: Dictionary, m: Array) -> Quaternion:
	var qs: Array[Quaternion] = b["q"]
	var modo: int = m[0]
	if modo == 0:
		return qs[0]
	if modo == 1:
		return qs[qs.size() - 1]
	var i: int = m[1]
	return qs[i].slerp(qs[i + 1], float(m[2]))

static func _sample_baked(b: Dictionary, t: float) -> Quaternion:
	var ts: PackedFloat32Array = b["t"]
	var qs: Array[Quaternion] = b["q"]
	var n := ts.size()
	if n == 0:
		return Quaternion.IDENTITY
	if n == 1 or t <= ts[0]:
		return qs[0]
	if t >= ts[n - 1]:
		return qs[n - 1]
	var i := ts.bsearch(t) - 1
	i = clampi(i, 0, n - 2)
	var ta := ts[i]
	var tb := ts[i + 1]
	var w := 0.0 if tb <= ta else clampf((t - ta) / (tb - ta), 0.0, 1.0)
	return qs[i].slerp(qs[i + 1], w)

## Construye el rig. height_m: altura deseada del personaje.
var _first_person := false
var _arms_only := false
var _external_weapon := false   # el arma la maneja otro nodo (vista en primera persona)
var _swap_hands := false
var skeleton: Skeleton3D
var mesh_inst: MeshInstance3D
var bone_idx: Dictionary = {}                 # nombre de hueso -> índice en el Skeleton3D
static var _skin_cache: Dictionary = {}      # id de skin -> {"skin": ArrayMesh, "arms": ArrayMesh}
static var _shared_pal: Array = []
static var _shared_min_y := 0.0
static var _shared_skin_mesh: ArrayMesh       # UNA malla skinnada para todos los avatares
static var _shared_arms_mesh: ArrayMesh       # sólo hombros, brazos y manos (brazos en primera persona)
const ARM_BONES := ["arm_upper_l", "arm_lower_l", "hand_l", "arm_upper_r", "arm_lower_r", "hand_r"]   # sin deltoides: en primera persona sólo se ven brazos y manos
## Los brazos de primera persona llevan LAS DOS MANOS horneadas. Cual de ellas tapa el arma no se
## sabe al hornear: depende de `_swap_hands`, que se decide al equipar. La que sobra se esconde en
## caliente encogiendo su hueso (ver _esconder_mano_del_gatillo).
## SIN MANOS (2026-09-28, pedido): los brazos de primera persona solo se ven al lanzar una granada, y las manos
## de voxels parecian bolas; el brazo acaba cuadrado en la muneca. Los huesos de las manos siguen (la granada y la
## anilla van colgadas de ellos), solo no llevan voxels.
const ARM_BONES_FP := ["arm_upper_l", "arm_lower_l", "arm_upper_r", "arm_lower_r"]
static var _shared_bone_order: Array = []     # huesos en orden padres-primero
static var _shared_rest_local: Dictionary = {}   # nombre -> posición local de reposo

## Orden padres-primero y posiciones locales de reposo (compartido).
static func _prepare_rig() -> void:
	if not _shared_bone_order.is_empty():
		return
	var bones: Dictionary = _shared_rig.get("bones", {})
	var parents: Dictionary = _shared_rig.get("bone_parents", {})
	var min_y := INF
	for bname in bones.keys():
		min_y = min(min_y, bones[bname]["world_pos"][1])
	var pending: Array = bones.keys()
	var built := {}
	var guard := 0
	while pending.size() > 0 and guard < 50:
		guard += 1
		var still: Array = []
		for bname in pending:
			var pname = parents.get(bname)
			if pname != null and not built.has(pname):
				still.append(bname)
				continue
			var wp: Array = bones[bname]["world_pos"]
			var world_pos := Vector3(wp[0], wp[1], wp[2])
			var bind: Quaternion = _shared_bind.get(bname, Quaternion.IDENTITY)
			var local := world_pos
			if pname != null:
				var pwp: Array = bones[pname]["world_pos"]
				# el offset al hijo se expresa en el marco de reposo del PADRE (así al rotar el padre
				# con su clave local, el hijo lo sigue: los brazos dejan de despegarse del cuerpo)
				var pg: Quaternion = _shared_bind_global[pname]
				local = pg.inverse() * (world_pos - Vector3(pwp[0], pwp[1], pwp[2]))
				_shared_bind_global[bname] = (pg * bind).normalized()
			else:
				local.y -= min_y
				_shared_bind_global[bname] = bind
			_shared_rest_local[bname] = local
			_shared_bone_order.append(bname)
			built[bname] = true
		pending = still
	# Malla skinnada: los vértices de cada hueso pasan al espacio de reposo global (traslación = world_pos - min_y)
	# con índice de hueso y peso 1. El skinning en GPU sustituye a 24 nodos + 24 draw calls por personaje.
	_shared_min_y = min_y
	_shared_skin_mesh = _bake_skin_mesh(bones, min_y, [], _shared_meshes)
	_shared_arms_mesh = _bake_skin_mesh(bones, min_y, ARM_BONES_FP, _shared_meshes)

## Los huesos que las piezas puestas mueven de sitio: nombre -> posicion (coordenadas del rig, como
## `world_pos`). Vacio para el soldado y para cualquier skin que no los traiga.
static func _articulaciones_de(receta: Dictionary) -> Dictionary:
	var out := {}
	var catalogo: Dictionary = _shared_rig.get("piezas", {})
	for nombre in receta.get("piezas", []):
		var art: Dictionary = (catalogo.get(String(nombre), {}) as Dictionary).get("articulaciones", {})
		for b in art.keys():
			var v: Array = art[b]
			out[String(b)] = Vector3(float(v[0]), float(v[1]), float(v[2]))
	return out


## Posicion local de reposo de un hueso cuando el o su padre estan en otro sitio: la misma cuenta que
## `_prepare_rig`, con las posiciones movidas.
static func _local_con_juntas(bname: String, pname: String, juntas: Dictionary) -> Vector3:
	var bones: Dictionary = _shared_rig.get("bones", {})
	var wb: Array = bones[bname]["world_pos"]
	var wpa: Array = bones[pname]["world_pos"]
	var wp: Vector3 = juntas[bname] if juntas.has(bname) else Vector3(wb[0], wb[1], wb[2])
	var pwp: Vector3 = juntas[pname] if juntas.has(pname) else Vector3(wpa[0], wpa[1], wpa[2])
	var pg: Quaternion = _shared_bind_global[pname]
	return pg.inverse() * (wp - pwp)


## Desplazamiento de la malla dentro de su hueso. El rig retargeteado separa el pivote
## (world_pos, en la articulación) del origen del arte (world_pos + mesh_off). Los rigs
## antiguos no traen el campo y siguen funcionando igual.
static func _mesh_off(bones: Dictionary, bname: String) -> Vector3:
	var b: Dictionary = bones.get(bname, {})
	if not b.has("mesh_off"):
		return Vector3.ZERO
	var mo: Array = b["mesh_off"]
	return Vector3(mo[0], mo[1], mo[2])

## LA MALLA DE UNA SKIN, horneada una vez y guardada. Cuesta lo mismo que la del soldado normal,
## pero solo se paga la primera vez que alguien la usa: en una partida son dos o tres, y en el
## armario se hornean las que enseñas.
static func mallas_skin(id: String, receta: Dictionary) -> Dictionary:
	_load_shared()
	if id == "" or receta.is_empty():
		return {"skin": _shared_skin_mesh, "arms": _shared_arms_mesh}
	if _skin_cache.has(id):
		return _skin_cache[id]
	var bones: Dictionary = _shared_rig.get("bones", {})
	# LAS PIEZAS. Un casco integral, una mochila o una capucha no son un modelo nuevo: son voxels
	# que se SUMAN a los huesos que ya existen (y a veces borran los de debajo, como el casco viejo
	# cuando le pones uno integral). Por eso todos los avatares comparten esqueleto, animaciones y
	# los cuatro huesos de parpado: la animacion del ojo funciona lleven lo que lleven.
	var catalogo: Dictionary = _shared_rig.get("piezas", {})
	var puestas: Array = receta.get("piezas", [])
	var quita := {}          # colores del soldado base que las piezas tapan
	var extra := {}          # hueso -> voxels que se anaden
	# HUECOS DE VERDAD. Una herida no es una mancha de color hueso: es que FALTA carne y por el
	# agujero se ve el hueso metido dentro. Estas coordenadas se borran del cuerpo antes de poner
	# la pieza, asi que la superficie se hunde de verdad en vez de quedar pintada y lisa.
	var borrar := {}         # hueso -> {Vector3i: true}
	# HUESOS TAPADOS. `quita` borra por color y `borra` por coordenada: valen para un casco o una
	# herida, pero no para un MODELO ENTERO. Un avatar esculpido aparte ocupa el cuerpo completo, y
	# dejar el soldado debajo se nota en los bordes (asoman dedos y orejas por dentro de la armadura).
	# Con `tapa` la pieza dice de que huesos es dueña y el cuerpo de debajo no se dibuja.
	var tapados := {}        # hueso -> true
	# PIEZAS FINAS (blend_a_pieza.py --fino): el modelo a su resolucion de origen, en un .bin aparte.
	# Sus huesos no llevan voxels de la rejilla del soldado: los dibuja el .bin, ver _hornear_fino.
	var finos: Array = []
	var huesos_finos := {}
	# `manos_soldado`: las manos de la pieza no se ponen y se dibujan las del soldado (bloque sin dedos).
	# Un modelo esculpido con dedos no se puede agarrar bien al arma: la mano es un solo hueso rigido.
	var manos_soldado: bool = bool(receta.get("manos_soldado", false))
	const MANOS := ["hand_l", "hand_r"]
	for nombre in puestas:
		var pzf: Dictionary = catalogo.get(String(nombre), {})
		if pzf.has("fino"):
			finos.append(String(pzf["fino"]))
			for t in pzf.get("tapa", []):
				huesos_finos[String(t)] = true
			if huesos_finos.has("head"):
				# los parpados del soldado asomaban por la cara del modelo como bloques sueltos
				for ojo in ["eye_l_up", "eye_l_dn", "eye_r_up", "eye_r_dn"]:
					tapados[ojo] = true
	for nombre in puestas:
		if String(nombre) in PIEZAS_COLGANTES:
			continue          # esa no va cosida al cuerpo: se cuelga aparte y se balancea
		var pz: Dictionary = catalogo.get(String(nombre), {})
		if pz.is_empty():
			continue
		for q in pz.get("quita", []):
			quita[int(q)] = true
		for t in pz.get("tapa", []):
			if manos_soldado and String(t) in MANOS:
				continue
			tapados[String(t)] = true
		var br: Dictionary = pz.get("borra", {})
		for bn in br.keys():
			var mapa: Dictionary = borrar.get(bn, {})
			for c in br[bn]:
				mapa[Vector3i(int(c[0]), int(c[1]), int(c[2]))] = true
			borrar[bn] = mapa
		if pz.has("fino"):
			continue          # su cuerpo lo pone el .bin, no los voxels remuestreados
		var vx: Dictionary = pz.get("vox", {})
		for bn in vx.keys():
			if manos_soldado and String(bn) in MANOS:
				continue
			var acc: Array = extra.get(bn, [])
			acc.append_array(vx[bn])
			extra[bn] = acc
	# LA FRANJA DE LOS OJOS, LIBRE (2026-09-23): el yelmo del Heraldo de Ceniza ponia voxels justo delante de
	# los parpados, que se cerraban por detras del casco y al apuntar no se veia cerrar el ojo. Se quitan los
	# voxels de las piezas de la cabeza que caen delante de un parpado (misma X e Y, hasta 4 voxels por delante):
	# quedan como las cuencas del casco. No toca los modelos enteros (`tapa`), que traen sus propios parpados.
	var es_zombi := false   # las caras de zombi traen sus propios ojos pintados: no se tocan
	for pzn in puestas:
		if String(pzn).begins_with("zombie"):
			es_zombi = true
	if extra.has("head") and not tapados.has("head") and not es_zombi:
		var ho: Vector3 = _off_hueso(bones, "head")
		var ojos := {}
		var z_ojo := 1e9
		for e in ["eye_l_up", "eye_l_dn", "eye_r_up", "eye_r_dn"]:
			if not bones.has(e):
				continue
			var eo: Vector3 = _off_hueso(bones, e)
			for v in bones[e]["voxels"]:
				ojos[Vector2i(int(v[0] + eo.x), int(v[1] + eo.y))] = true
				z_ojo = minf(z_ojo, v[2] + eo.z)
		var limpio_h: Array = []
		for v in extra["head"]:
			var wx := int(v[0] + ho.x); var wy := int(v[1] + ho.y); var wz: float = v[2] + ho.z
			if ojos.has(Vector2i(wx, wy)) and wz <= z_ojo + 0.5 and wz >= z_ojo - 4.5:
				continue
			limpio_h.append(v)
		extra["head"] = limpio_h
	var c0: int = _shared_pal.size() - _colores_soldado()
	var mallas := {}
	for bname in bones.keys():
		var vox: Array = bones[bname]["voxels"]
		if tapados.has(String(bname)):
			vox = []                 # ese hueso lo pone la pieza entera
		elif bname == "hand_l" or bname == "hand_r":
			vox = _mano_sin_dedos(vox)
		var huecos: Dictionary = borrar.get(bname, {})
		if not quita.is_empty() or not huecos.is_empty():
			var limpio: Array = []
			for v in vox:
				if quita.has(int(v[3]) - c0):
					continue
				if huecos.has(Vector3i(int(v[0]), int(v[1]), int(v[2]))):
					continue
				limpio.append(v)
			vox = limpio
		if extra.has(bname):
			vox = vox + extra[bname]
		vox = _recortar_hood(bones, String(bname), vox)
		var m := _build_bone_mesh(vox, _shared_pal, receta, String(bname))
		if m:
			mallas[bname] = m
	var out := {
		"skin": _bake_skin_mesh(bones, _shared_min_y, [], mallas),
		"arms": _bake_skin_mesh(bones, _shared_min_y, ARM_BONES_FP, mallas)}
	var t_fino := Time.get_ticks_msec()
	for ruta in finos:
		_hornear_fino(out["skin"], ruta, bones, _shared_min_y, [], receta)
		_hornear_fino(out["arms"], ruta, bones, _shared_min_y, ARM_BONES_FP, receta)
	if not finos.is_empty():
		print("[avatar] skin %s: pieza fina horneada en %d ms" % [id, Time.get_ticks_msec() - t_fino])
	_skin_cache[id] = out
	return out


# ---------------------------------------------------------------------------
# LO QUE CUELGA. Un llavero pegado a la malla de la mochila se mueve como un ladrillo: es parte del
# cuerpo y no se entera de nada. Estas piezas NO se hornean con el resto: se cuelgan de un pivote
# sobre el hueso del pecho y se balancean con el movimiento, como colgaria de verdad.
# ---------------------------------------------------------------------------
const PIEZAS_COLGANTES := ["llavero_calavera", "llavero_dado", "llavero_chapa"]
## Cuanto tira el movimiento del llavero, cuanto lo devuelve la gravedad y cuanto se frena.
const COLG_TIRON := 0.055
const COLG_MUELLE := 46.0
const COLG_FRENO := 5.2
const COLG_TOPE := 0.95        ## rad: no se va a dar la vuelta por encima del hombro

var _colgante: Node3D = null
var _piezas_puestas: Array = []
var _colg_ang := Vector2.ZERO
var _colg_vel := Vector2.ZERO
var _colg_pos := Vector3.ZERO
var _colg_v := Vector3.ZERO


## Cuelga la pieza del hueso del pecho, con su pivote arriba del todo (donde estaria el mosqueton).
func _colgar_pieza(nombre: String) -> void:
	if skeleton == null or not bone_idx.has("chest"):
		return
	var mi := malla_pieza(nombre)
	if mi == null:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = "chest"
	skeleton.add_child(att)
	att.bone_idx = bone_idx["chest"]
	var pivote := Node3D.new()
	# DE DONDE CUELGA: de la esquina de abajo y de un lado de LA MOCHILA QUE LLEVES, no del pecho.
	# Cada mochila tiene su tamano, asi que el punto se saca de sus propios voxels; sin mochila
	# se engancha al cinturon, por detras.
	var bones: Dictionary = _shared_rig.get("bones", {})
	var off: Vector3 = _mesh_off(bones, "chest")
	pivote.position = off + _enganche_mochila()
	att.add_child(pivote)
	mi.position = Vector3.ZERO      # la pieza ya esta dibujada colgando de su origen
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivote.add_child(mi)
	_colgante = pivote


## Las mochilas, de la mas grande a la mas pequena. Solo puede haber una puesta.
const MOCHILAS := ["paracaidas", "mochila_grande", "mochila_tactica", "mochila", "mochila_calle", "petate"]

## El punto del que cuelga el llavero: la esquina de abajo, a la derecha y por detras, de la mochila
## puesta. Se mide sobre los voxels de esa mochila, asi que vale para todas.
func _enganche_mochila() -> Vector3:
	var catalogo: Dictionary = _shared_rig.get("piezas", {})
	for m in MOCHILAS:
		if not (m in _piezas_puestas):
			continue
		var vx: Array = catalogo.get(m, {}).get("vox", {}).get("chest", [])
		if vx.is_empty():
			continue
		var x0 := 999.0
		var x1 := -999.0
		var y0 := 999.0
		var z1 := -999.0
		for v in vx:
			x0 = minf(x0, float(v[0]))
			x1 = maxf(x1, float(v[0]))
			y0 = minf(y0, float(v[1]))
			z1 = maxf(z1, float(v[2]))
		# a un lado (no en el centro, que quedaria escondido), abajo del todo y en la cara de atras
		return Vector3(x1 - 1.0, y0 + 1.0, z1 - 0.5)
	return Vector3(4.0, -6.0, 5.0)      # sin mochila: colgado del cinturon, por detras


## El balanceo. Se mide la ACELERACION del punto del que cuelga (no la velocidad: colgando de algo
## que va a velocidad constante, un llavero se queda quieto) y se le da al pendulo en sentido
## contrario. Lo demas es un muelle que lo devuelve al centro y un freno para que no vibre.
func _update_colgante(dt: float) -> void:
	if _colgante == null or not is_instance_valid(_colgante) or dt <= 0.0:
		return
	var p: Vector3 = _colgante.global_position
	var v: Vector3 = (p - _colg_pos) / dt
	if _colg_pos == Vector3.ZERO:
		v = Vector3.ZERO
	var a: Vector3 = (v - _colg_v) / dt
	_colg_pos = p
	_colg_v = v
	# la sacudida, en los ejes del propio personaje
	var loc: Vector3 = global_transform.basis.inverse() * a
	var tiron := Vector2(clampf(-loc.z * COLG_TIRON, -12.0, 12.0), clampf(loc.x * COLG_TIRON, -12.0, 12.0))
	_colg_vel += (tiron - _colg_ang * COLG_MUELLE - _colg_vel * COLG_FRENO) * dt
	_colg_ang += _colg_vel * dt
	_colg_ang.x = clampf(_colg_ang.x, -COLG_TOPE, COLG_TOPE)
	_colg_ang.y = clampf(_colg_ang.y, -COLG_TOPE, COLG_TOPE)
	_colgante.rotation = Vector3(_colg_ang.x, 0.0, _colg_ang.y)


## LA PIEZA SOLA, sin el soldado debajo. Para el escaparate de accesorios: una mochila son unos
## cientos de voxels y se hornea al momento, al reves que un avatar entero (12.858, unos 0,7 s).
static func malla_pieza(nombre: String) -> MeshInstance3D:
	_load_shared()
	var pz: Dictionary = _shared_rig.get("piezas", {}).get(nombre, {})
	if pz.is_empty():
		return null
	var vox: Array = []
	for bn in pz.get("vox", {}).keys():
		vox.append_array(pz["vox"][bn])
	if vox.is_empty():
		return null
	var m := _build_bone_mesh(vox, _shared_pal)
	if m == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mi.material_override = mat
	return mi


## Suelta la malla de una skin. Guardarlas todas serian decenas de megas: en el armario se hornea
## una, se le saca la foto y se olvida.
static func olvidar_skin(id: String) -> void:
	_skin_cache.erase(id)


## Donde cae el voxel (0,0,0) de un hueso en el modelo (lo mismo que suma `_bake_skin_mesh`, sin min_y).
static func _off_hueso(bones: Dictionary, bname: String) -> Vector3:
	var wp: Array = bones[bname]["world_pos"]
	return Vector3(wp[0], wp[1], wp[2]) + _mesh_off(bones, bname)

## SIN MANOS, EN TODOS LOS MODELOS (2026-09-28, pedido: "que desaparezcan de raiz: ni en el lobby, ni en tercera
## persona, ni se las vea un amigo"). Los voxels de estos huesos no se hornean nunca, en ningun avatar ni pieza: el
## brazo acaba cuadrado en la muneca. Los huesos siguen (IK, lo que se cuelga de la mano: la granada, el botiquin).
const HUESOS_SIN_VOXELS := ["hand_l", "hand_r"]

# ---------------------------------------------------------------------------------------------------
# ARTICULACIONES ELASTICAS (2026-10-28, bug: "las rodillas se separan de la pierna: la rodilla queda arriba y el femur
# abajo"). Cada voxel era de UN hueso, asi que al doblar una articulacion los dos bloques rigidos se abrian (o se metian
# uno en el otro). Ahora los vertices cerca de la articulacion se reparten entre los dos huesos: justo en la junta mitad y
# mitad, y a ELASTICA_R voxels ya del todo del suyo. La malla se estira en vez de abrirse; el voxel se ve igual en reposo.
# Los mismos huesos, las mismas animaciones. `--sinelasticas` = como antes.
# Junta -> [voxels de reparto, como se mide]: "eje" a lo largo del miembro (asi la superficie de un muslo gordo reparte
# igual que su centro) o "radio" (el tobillo, donde el pie sale en otra direccion).
# ---------------------------------------------------------------------------------------------------
const ELASTICAS := {
	"leg_upper_l": 5.0, "leg_upper_r": 5.0,       # cadera
	"leg_lower_l": 5.0, "leg_lower_r": 5.0,       # rodilla
	"foot_l": 4.0, "foot_r": 4.0,                 # tobillo
	"toes_l": 3.0, "toes_r": 3.0,                 # dedos
	# clavicula y hombro RIGIDOS (2026-11-01, bug con captura: "la espalda se estira con el arma"): el hueso del hombro ya
	# no se dibuja (HOMBRO_AL_BRAZO) y al apuntar gira distinto que el brazo: la manga se estiraba en trapecio
	"arm_lower_l": 4.5, "arm_lower_r": 4.5,       # codo
	"stomach": 4.0, "chest": 4.0,                 # cintura y pecho
	# cuello y cabeza RIGIDOS (2026-10-30, pedido: "al girar la cabeza se tira la piel de la cara")
}
const TORSO_RIGIDO := ["chest", "stomach", "spine", "spine_1", "spine_2", "neck"]
static var _sin_elasticas: bool = "--sinelasticas" in OS.get_cmdline_user_args()
static var _juntas_el: Dictionary = {}     ## (min_y) -> {hueso: [junta, eje, hijos]}

static func _juntas_elasticas(bones: Dictionary, min_y: float) -> Dictionary:
	var clave := "%.3f" % min_y
	if _juntas_el.has(clave):
		return _juntas_el[clave]
	var padres: Dictionary = _shared_rig.get("bone_parents", {})
	var pos := {}
	for b in bones.keys():
		var wp: Array = bones[b]["world_pos"]
		pos[b] = Vector3(wp[0], wp[1] - min_y, wp[2])
	var hijos := {}
	for b in padres.keys():
		var pa = padres[b]
		if pa != null:
			if not hijos.has(pa):
				hijos[pa] = []
			hijos[pa].append(b)
	var out := {}
	for b in pos.keys():
		var j: Vector3 = pos[b]
		# el eje del miembro: de la junta al hijo que sigue la cadena (o desde el padre si no tiene)
		var eje := Vector3.ZERO
		for h in hijos.get(b, []):
			if ELASTICAS.has(h) and pos.has(h):
				eje = ((pos[h] as Vector3) - j).normalized()
				break
		if eje == Vector3.ZERO and padres.get(b) != null and pos.has(padres[b]):
			eje = (j - (pos[padres[b]] as Vector3)).normalized()
		out[b] = [j, eje, hijos.get(b, []), padres.get(b)]
	_juntas_el[clave] = out
	return out

## Los huesos y pesos de un vertice del hueso `bname` en `p` (espacio de la malla en reposo).
static func _pesos_elasticos(juntas: Dictionary, bi_de: Dictionary, bname: String, p: Vector3, only: Array = [], hombrera := false) -> Array:
	var hb := PackedInt32Array([int(bi_de[bname]), 0, 0, 0])
	var pw := PackedFloat32Array([1.0, 0.0, 0.0, 0.0])
	if _sin_elasticas or not juntas.has(bname) or hombrera:
		return [hb, pw]
	var otros := []
	var jb: Array = juntas[bname]
	# la junta con su padre: lo que el vertice se ha metido en su hueso, a lo largo de su eje
	# (los brazos de primera persona solo se reparten entre ellos: sus hombros se llevan a las esquinas de la pantalla)
	if ELASTICAS.has(bname) and jb[3] != null and bi_de.has(jb[3]) and (only.is_empty() or jb[3] in only):
		var r: float = ELASTICAS[bname]
		var d: float = (p - (jb[0] as Vector3)).length() if (jb[1] as Vector3) == Vector3.ZERO 			else (p - (jb[0] as Vector3)).dot(jb[1])
		# del otro lado de la junta (d < 0: un muslo que asoma por debajo de la rodilla) va con el otro hueso
		var w: float = 1.0 - smoothstep(-r, r, d)
		if w > 0.01:
			otros.append([int(bi_de[jb[3]]), w])
	# las juntas con sus hijos: lo que le falta para llegar a la junta, en la direccion de ese hijo
	for h in jb[2]:
		if not ELASTICAS.has(h) or not juntas.has(h) or not bi_de.has(h) or not (only.is_empty() or h in only):
			continue
		# EL TORSO NO SE ESTIRA CON LOS BRAZOS (2026-10-31, bug con captura: "al mover el brazo se dobla todo el diseño de
		# la espalda"): el pecho no reparte con los hombros; es el brazo el que se estira hacia el pecho
		if bname in TORSO_RIGIDO and String(h).begins_with("shoulder"):
			continue
		var jh: Array = juntas[h]
		var r2: float = ELASTICAS[h]
		var hacia: Vector3 = (jh[0] as Vector3) - (jb[0] as Vector3)
		var d2: float = (p - (jh[0] as Vector3)).length() if hacia.length() < 0.01 			else ((jh[0] as Vector3) - p).dot(hacia.normalized())
		var w2: float = 1.0 - smoothstep(-r2, r2, d2)
		if w2 > 0.01:
			otros.append([int(bi_de[h]), w2])
	if otros.is_empty():
		return [hb, pw]
	var suma := 0.0
	for k in mini(otros.size(), 3):
		hb[k + 1] = otros[k][0]
		pw[k + 1] = otros[k][1]
		suma += float(otros[k][1])
	if suma > 1.0:
		for k in 3:
			pw[k + 1] *= 1.0 / suma
		suma = 1.0
	pw[0] = 1.0 - suma
	return [hb, pw]

static func _bi_de() -> Dictionary:
	var d := {}
	for i in _shared_bone_order.size():
		d[_shared_bone_order[i]] = i
	return d


const HOMBRO_AL_BRAZO := {"shoulder_l": "arm_upper_l", "shoulder_r": "arm_upper_r"}
static var _hombro_antes: bool = "--hombroantes" in OS.get_cmdline_user_args()

static func _bake_skin_mesh(bones: Dictionary, min_y: float, only: Array, mallas: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if mallas.is_empty():
		return ArrayMesh.new()     # todo el cuerpo lo pone una pieza fina: se le anade despues
	var juntas := _juntas_elasticas(bones, min_y)
	var bi_de := _bi_de()
	for i in _shared_bone_order.size():
		var bname: String = _shared_bone_order[i]
		if not mallas.has(bname):
			continue
		if not only.is_empty() and not (bname in only):
			continue
		if bname in HUESOS_SIN_VOXELS:
			continue
		var wp: Array = bones[bname]["world_pos"]
		var off := Vector3(wp[0], wp[1] - min_y, wp[2]) + _mesh_off(bones, bname)
		# EL HOMBRO ES DEL BRAZO (2026-10-28, pedido: "los hombros estan pegados al torax; que el hombro sea parte del
		# brazo, como en los personajes nuevos"): los voxels de la hombrera van con el hueso del brazo y giran con el
		# (en reposo, en el mismo sitio). `--hombroantes` = como antes.
		# (y desde el mismo dia, pedido: "las hombreras no las eliminaste: eliminalas, que quede el brazo como Puño de Oro o
		# el nanotraje") la hombrera del soldado de voxels NO se dibuja: el brazo arranca en su articulacion
		if HOMBRO_AL_BRAZO.has(bname) and not _hombro_antes:
			continue
		var hueso_malla: String = bname
		var arrays: Array = (mallas[bname] as ArrayMesh).surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for k in verts.size():
			var pv: Vector3 = verts[k] + off
			var hw: Array = _pesos_elasticos(juntas, bi_de, hueso_malla, pv, only, hueso_malla != bname)
			st.set_normal(norms[k])
			st.set_color(cols[k])
			st.set_bones(hw[0])
			st.set_weights(hw[1])
			st.add_vertex(pv)
	# CON INDICES (2026-10-02, medido con los bots: animar sus muñecos era lo que mas pesaba de ellos, 2,5-5 ms de CPU y
	# 1,5-2,5 de GPU por fotograma con 9 bots). Sin indexar, cada triangulo llevaba sus tres vertices y la piel se recalcula
	# vertice a vertice en cada animacion: las esquinas compartidas se pagaban varias veces. Se ve exactamente igual
	# (mismo sitio, normal, color y hueso). --sinindicesmuneco = antes.
	if not "--sinindicesmuneco" in OS.get_cmdline_user_args():
		st.index()
	return st.commit()

## UNA PIEZA FINA, a la resolucion con la que se esculpio (un modelo de 1 cm, sin pasarlo a la rejilla
## de 2,6 cm del soldado, que le rompia la cara). El .bin (tools/make_soldier.py, escribir_fino) trae
## rectangulos ya fundidos por color; aqui solo se convierten en cuatro vertices cada uno y se anaden
## como una superficie mas de la malla skinnada, con el mismo material.
static func _hornear_fino(malla: ArrayMesh, ruta: String, bones: Dictionary, min_y: float, only: Array, receta: Dictionary) -> void:
	var datos := FileAccess.get_file_as_bytes(ruta)
	if datos.size() < 4:
		push_warning("[avatar] no se pudo leer la pieza fina %s" % ruta)
		return
	var ejes := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	var shade: Array[float] = [0.85, 0.75, 1.0, 0.55, 0.9, 0.8]
	var c0 := _shared_pal.size() - _colores_soldado()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var huesos := PackedInt32Array()
	var pesos := PackedFloat32Array()
	var indices := PackedInt32Array()
	var pos := 4
	var juntas := {}
	var bi_de := {}
	var n_huesos := datos.decode_u32(0)
	for _h in n_huesos:
		var largo := datos.decode_u16(pos)
		var bname := datos.slice(pos + 2, pos + 2 + largo).get_string_from_ascii()
		pos += 2 + largo
		var origen := Vector3(datos.decode_float(pos), datos.decode_float(pos + 4), datos.decode_float(pos + 8))
		var e := datos.decode_float(pos + 12)
		var nq := datos.decode_u32(pos + 16)
		pos += 20
		var q := datos.slice(pos, pos + nq * 28).to_int32_array()
		pos += nq * 28
		var bi := _shared_bone_order.find(bname)
		if bi < 0 or not bones.has(bname) or (not only.is_empty() and not (bname in only)) or bname in HUESOS_SIN_VOXELS:
			continue
		var wp: Array = bones[bname]["world_pos"]
		var off := Vector3(wp[0], wp[1] - min_y, wp[2]) + _mesh_off(bones, bname) + origen
		if juntas.is_empty():
			juntas = _juntas_elasticas(bones, min_y)
			bi_de = _bi_de()
		var v0 := verts.size()
		verts.resize(v0 + nq * 4)
		norms.resize(v0 + nq * 4)
		cols.resize(v0 + nq * 4)
		huesos.resize((v0 + nq * 4) * 4)
		pesos.resize((v0 + nq * 4) * 4)
		var i0 := indices.size()
		indices.resize(i0 + nq * 6)
		var colores := {}       # (indice de paleta * 6 + cara) -> color ya sombreado
		for k in nq:
			var b := k * 7
			var fi: int = q[b]
			var ax := fi >> 1
			var ua := 1 if ax == 0 else 0
			var va := 1 if ax == 2 else 2
			var pmin := Vector3.ZERO
			pmin[ax] = q[b + 1]
			pmin[ua] = q[b + 2]
			pmin[va] = q[b + 3]
			var ext := Vector3.ZERO
			ext[ua] = q[b + 4]
			ext[va] = q[b + 5]
			var cen := off + (pmin + ext * 0.5) * e
			var n: Vector3 = ejes[fi]
			# los mismos ejes tangentes y el mismo orden que _build_bone_mesh (horario visto desde fuera)
			var u := Vector3(0, 1, 0) if absf(n.y) < 0.5 else Vector3(1, 0, 0)
			var w := n.cross(u)
			u = w.cross(n)
			# un pelo mas grande que su hueco: al fundir caras quedan juntas en T y por esas rendijas
			# de coma flotante se colaba el fondo como lineas de puntos
			var hu := u * (absf(u.dot(ext)) * e * 0.5 + e * 0.02)
			var hw := w * (absf(w.dot(ext)) * e * 0.5 + e * 0.02)
			var clave: int = q[b + 6] * 6 + fi
			var cc: Color
			if colores.has(clave):
				cc = colores[clave]
			else:
				var ip: int = q[b + 6]
				var col := Color(0.8, 0.6, 0.5)
				if ip >= 0 and ip < _shared_pal.size():
					var pc = _shared_pal[ip]
					col = Color8(int(pc[0]), int(pc[1]), int(pc[2]))
				if not receta.is_empty():
					col = _color_skin(ip - c0, bname, receta, col)
				cc = col.srgb_to_linear() * shade[fi]
				cc.a = 1.0
				colores[clave] = cc
			var vi := v0 + k * 4
			verts[vi] = cen - hu - hw
			verts[vi + 1] = cen + hu - hw
			verts[vi + 2] = cen + hu + hw
			verts[vi + 3] = cen - hu + hw
			for j in 4:
				norms[vi + j] = n
				cols[vi + j] = cc
				var hm: String = String(HOMBRO_AL_BRAZO.get(bname, bname)) if not _hombro_antes else bname
				var pz: Array = _pesos_elasticos(juntas, bi_de, hm, verts[vi + j], only, hm != bname)
				for m in 4:
					huesos[(vi + j) * 4 + m] = (pz[0] as PackedInt32Array)[m]
					pesos[(vi + j) * 4 + m] = (pz[1] as PackedFloat32Array)[m]
			var ii := i0 + k * 6
			indices[ii] = vi
			indices[ii + 1] = vi + 2
			indices[ii + 2] = vi + 1
			indices[ii + 3] = vi
			indices[ii + 4] = vi + 3
			indices[ii + 5] = vi + 2
	if verts.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_BONES] = huesos
	arr[Mesh.ARRAY_WEIGHTS] = pesos
	arr[Mesh.ARRAY_INDEX] = indices
	malla.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)


## ALTURA DEL SOLDADO EN PARTIDA. Un sitio y no veinte: jugador, bots y jugadores de red miden lo
## mismo o las miras, los ojos y las cápsulas dejan de cuadrar entre sí.
const ALTURA := 1.60

## Con que se construyo por ultima vez (alto, tinte, skin, receta): el resumen de muerte (muerte_resumen.gd) hace
## una copia del muñeco de quien te mato con esto.
var build_args: Array = []

func build(height_m: float = 1.75, shadows_only: bool = false, tint: Color = Color.WHITE, cast_shadows: bool = true, arms_only: bool = false, skin_id: String = "", receta: Dictionary = {}) -> void:
	build_args = [height_m, tint, skin_id, receta]
	_hombro_parte = float(receta.get("hombro_parte", HOMBRO_PARTE))
	_codo_recto = receta.get("codo_recto", {})
	_hombro_baja = float(receta.get("hombro_baja", HOMBRO_BAJA))
	var _tb := Time.get_ticks_usec()
	_first_person = shadows_only
	_body_visible = not shadows_only   # (las armas colgadas lo miran: sin esto, en primera persona se veian hasta cambiar de arma)
	_arms_only = arms_only
	_load_shared()
	_prepare_rig()
	for c in get_children():
		c.queue_free()
	bone_nodes.clear()
	bone_idx.clear()
	_huesos_lista = []
	_casillas = PackedInt32Array()
	# RECONSTRUIR EL AVATAR TIRA EL ARMA: el esqueleto es nuevo y el fusil colgaba del viejo. Se
	# apunta lo que llevaba para devolverselo al final (los bots se reconstruyen al repartir bandos
	# y se quedaban disparando con las manos vacias).
	var _rearm_kind := weapon_kind
	var _rearm_id := _arma_id
	if weapon_root and not _external_weapon:
		weapon_root = null
		grip_marker = null
		fore_marker = null
		_wm = null
		weapon_kind = ""
		_arma_id = ""
	Prof.add("av.build.0inicio", Time.get_ticks_usec() - _tb)
	_tb = Time.get_ticks_usec()
	var bones: Dictionary = _shared_rig.get("bones", {})
	var parents: Dictionary = _shared_rig.get("bone_parents", {})
	if bones.is_empty():
		return
	# Altura real del arte (los pivotes del rig retargeteado ya no la representan). UNA VEZ: el rig es el mismo
	# para todos y recorrer sus voxels eran ~9 ms en cada montaje (cada bot que reaparece se monta dos veces).
	if not _alto_arte_hecho:
		_alto_arte_hecho = true
		var min_y := INF
		var max_y := -INF
		for bname in bones.keys():
			var vox: Array = bones[bname]["voxels"]
			if vox.is_empty():
				continue
			var oy: float = float(bones[bname]["world_pos"][1]) + _mesh_off(bones, bname).y
			for v in vox:
				min_y = min(min_y, oy + float(v[1]))
				max_y = max(max_y, oy + float(v[1]) + 1.0)
		_alto_arte = max_y - min_y
	var s: float = height_m / max(_alto_arte, 1.0)
	scale = Vector3(s, s, s)
	Prof.add("av.build.1altura", Time.get_ticks_usec() - _tb)
	_tb = Time.get_ticks_usec()
	material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	material.albedo_color = tint
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton"
	add_child(skeleton)
	# ARTICULACIONES PROPIAS DE LA SKIN. Un modelo esculpido aparte no tiene por que tener el codo ni los
	# ojos donde el soldado: el Heraldo lleva la manga hasta media distancia del antebrazo y los ojos 7 cm
	# mas abajo. La pieza trae donde van SUS huesos y aqui se usan en este esqueleto; la malla no se mueve
	# (esta horneada en coordenadas de reposo) y los demas avatares siguen con las del rig.
	var juntas := _articulaciones_de(receta)
	for i in _shared_bone_order.size():
		var bname: String = _shared_bone_order[i]
		var idx := skeleton.add_bone(bname)
		bone_idx[bname] = idx
		var pname = parents.get(bname)
		if pname != null and bone_idx.has(pname):
			skeleton.set_bone_parent(idx, bone_idx[pname])
		var local: Vector3 = _shared_rest_local[bname]
		if pname != null and (juntas.has(bname) or juntas.has(String(pname))):
			local = _local_con_juntas(bname, String(pname), juntas)
		var bind: Quaternion = _shared_bind.get(bname, Quaternion.IDENTITY)
		skeleton.set_bone_rest(idx, Transform3D(Basis(bind), local))
		skeleton.set_bone_pose_position(idx, local)
		skeleton.set_bone_pose_rotation(idx, bind)
	Prof.add("av.build.2esqueleto", Time.get_ticks_usec() - _tb)
	_tb = Time.get_ticks_usec()
	mesh_inst = MeshInstance3D.new()
	var mallas := mallas_skin(skin_id, receta)
	Prof.add("av.build.3mallas", Time.get_ticks_usec() - _tb)
	_tb = Time.get_ticks_usec()
	mesh_inst.mesh = mallas["arms"] if arms_only else mallas["skin"]
	_colgante = null
	_colg_pos = Vector3.ZERO
	_piezas_puestas = receta.get("piezas", [])
	if not arms_only:
		for nombre in receta.get("piezas", []):
			if String(nombre) in PIEZAS_COLGANTES:
				_colgar_pieza(String(nombre))
				break
	mesh_inst.material_override = material
	mesh_inst.skin = skeleton.create_skin_from_rest_transforms()
	if shadows_only:
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	elif not cast_shadows or arms_only:
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	skeleton.add_child(mesh_inst)
	mesh_inst.skeleton = mesh_inst.get_path_to(skeleton)
	Prof.add("av.build.4piel", Time.get_ticks_usec() - _tb)
	_tb = Time.get_ticks_usec()
	# EL FUEGO del modelo (si lo trae su receta), colgado de sus huesos
	if not arms_only and not shadows_only:
		_montar_fuego(receta)
	# y se le devuelve el arma que llevaba antes de reconstruirse
	# (los brazos de primera persona NO: su arma cuelga de la camara, no del rig)
	if _rearm_kind != "" and not _external_weapon and not arms_only:
		equip_weapon(_rearm_kind, _rearm_id)
	Prof.add("av.build.5fuego_arma", Time.get_ticks_usec() - _tb)

# ---------------------------------------------------------------------------
# EL FUEGO DE UN MODELO (el Heraldo de Llama: calavera y ojos ardiendo en azul). En Blender es un
# shader VOLUMETRICO que no existe en el juego, asi que aqui se rehace con particulas: llamas que suben
# desde su punto, pegadas al hueso (siguen a la cabeza) y dejando estela al moverse, mas una luz azul.
# La receta dice donde: {"hueso", "pos" (m, respecto al hueso, marco del avatar), "tam" (m), "luz"}.
# Posiciones sacadas del .blend (FuegoCalavera, FuegoOjo_D/I, BrilloOjos).
# ---------------------------------------------------------------------------
func _montar_fuego(receta: Dictionary) -> void:
	_fuegos.clear()
	var llamas: Array = receta.get("fuego", [])
	if llamas.is_empty() or skeleton == null:
		return
	for f in llamas:
		var hueso := String(f.get("hueso", "head"))
		if not bone_idx.has(hueso):
			continue
		# NO SE CUELGA DEL HUESO: su rotacion de reposo mezclaba los ejes (una llama "delante de los ojos"
		# salia en la oreja). Es un nodo aparte, en coordenadas del mundo, que cada fotograma se pone donde
		# esta el hueso MAS el desplazamiento en el marco del AVATAR (arriba es arriba, delante es delante).
		var punto := Node3D.new()
		punto.name = "Fuego_" + hueso
		punto.top_level = true
		add_child(punto)
		var tam: float = float(f.get("tam", 0.3))
		if tam > 0.0:
			punto.add_child(_llama(tam, Color(f.get("color", "3a9dffff")), float(f.get("brillo", 1.0))))
		var luz: float = float(f.get("luz", 0.0))
		if luz > 0.0:
			var l := OmniLight3D.new()
			l.light_color = Color(0.15, 0.5, 1.0)
			l.light_energy = luz
			l.omni_range = 0.6      # solo la calavera: con 1,6 m pintaba de azul cada escalon de 1 cm del pecho
			l.shadow_enabled = false
			punto.add_child(l)
		var p: Array = f.get("pos", [0, 0, 0])
		_fuegos.append([punto, int(bone_idx[hueso]), Vector3(float(p[0]), float(p[1]), float(p[2]))])
	_colocar_fuego()


var _fuegos: Array = []          ## [nodo, indice del hueso, desplazamiento en metros (marco del avatar)]

func _colocar_fuego() -> void:
	if _fuegos.is_empty() or skeleton == null or not is_inside_tree():
		return
	var gb: Basis = global_transform.basis.orthonormalized()
	for fz in _fuegos:
		var nodo: Node3D = fz[0]
		if not is_instance_valid(nodo):
			continue
		var hueso_g: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(int(fz[1])).origin
		nodo.global_position = hueso_g + gb * (fz[2] as Vector3)


static var _llama_tex: Texture2D = null

## `brillo`: cuanto mas opaca. Las llamas pequeñas (los ojos) la necesitan o no se ven.
func _llama(tam: float, color: Color, brillo: float = 1.0) -> GPUParticles3D:
	var pt := GPUParticles3D.new()
	pt.amount = clampi(int(tam * 70.0), 6, 24)
	pt.lifetime = 0.5
	pt.local_coords = false            # al moverse deja estela, como una llama de verdad
	pt.visibility_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 3, 2))
	pt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = tam * 0.22
	pm.direction = Vector3.UP
	pm.spread = 14.0
	pm.initial_velocity_min = tam * 0.9
	pm.initial_velocity_max = tam * 1.9
	pm.gravity = Vector3(0, tam * 2.2, 0)       # sube: el aire caliente
	pm.damping_min = tam * 0.5
	pm.damping_max = tam * 1.0
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	var escala := Curve.new()
	escala.add_point(Vector2(0.0, 0.55))
	escala.add_point(Vector2(0.25, 1.0))
	escala.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = escala
	pm.scale_curve = ct
	# LA RAMPA DEL .BLEND: casi blanco en el corazon, azul, y se apaga a azul oscuro
	var g := Gradient.new()
	# con mezcla aditiva, poca opacidad: si no, las llamas se suman hasta el blanco y parece una bola
	g.set_color(0, Color(0.55, 0.85, 1.0, minf(1.0, 0.55 * brillo)))
	g.set_color(1, Color(0.0, 0.10, 0.9, 0.0))
	g.add_point(0.3, Color(color.r * 0.8, color.g * 0.8, color.b, minf(1.0, 0.45 * brillo)))
	g.add_point(0.7, Color(0.0, 0.22, 1.0, minf(1.0, 0.2 * brillo)))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	pt.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(tam * 0.32, tam * 0.62)     # mas alta que ancha: lengua de fuego, no bola
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = false
	if _llama_tex == null:
		var rg := Gradient.new()
		rg.set_color(0, Color(1, 1, 1, 1))
		rg.set_color(1, Color(1, 1, 1, 0))
		var rt := GradientTexture2D.new()
		rt.gradient = rg
		rt.fill = GradientTexture2D.FILL_RADIAL
		rt.fill_from = Vector2(0.5, 0.5)
		rt.fill_to = Vector2(0.5, 0.0)
		rt.width = 64
		rt.height = 64
		_llama_tex = rt
	mat.albedo_texture = _llama_tex
	quad.material = mat
	pt.draw_pass_1 = quad
	return pt


## Duración real de un clip, para que quien lo use no tenga que adivinarla.
## Hornea de una vez todos los clips. El horneado es perezoso y costaba un micro-tirón la
## primera vez que se usaba cada clip (saltar, aterrizar, girar). Se hace al construir.

func warm_up() -> void:
	for n in _shared_clips.keys():
		_baked(n)

func clip_dur(n: String) -> float:
	return float(_baked(n)["dur"]) if _shared_clips.has(n) else 0.0

# --- Locomoción compartida -------------------------------------------------------------------
# La eligen igual el jugador y los bots: una sola implementación, así todos se ven idénticos.
## Velocidad real (m/s) para la que está animado cada ciclo, medida del propio .bin: el pie
## apoyado barre el suelo a esa velocidad. Reproducir a hspeed/CLIP_SPEED evita que patinen.
# --- CALIBRACION DE MARCHA ------------------------------------------------------------------------
# CADA MODO DE ANDAR, POR SEPARADO: a que velocidad se mueve el cuerpo y a que velocidad se
# reproduce su animacion. Nada mas. Se ajustan desde el menu, en CALIBRAR ANIMACION.
#
#   vel  = metros por segundo a los que avanza el personaje en ese modo
#   anim = a cuanto se reproduce el ciclo (1.0 = tal cual esta animado)
#
# `anim` es el numero de referencia PARA `vel`. Si alguien se mueve mas despacio -un bot andando, o
# vos apuntando- la animacion se frena en la misma proporcion, asi que la calibracion aguanta a
# cualquier velocidad y no solo a la de la tabla.
static var CAL := {
	"andar":     {"vel": 3.10, "anim": 1.35},
	"esprintar": {"vel": 5.00, "anim": 1.21},
	"atras":     {"vel": 2.55, "anim": 0.76},
	"lateral_i": {"vel": 2.89, "anim": 0.76},
	"lateral_d": {"vel": 2.89, "anim": 0.86},
	"agachado":  {"vel": 1.55, "anim": 1.15},
}

## LO QUE BARRE EL SUELO CADA CICLO, en m/s. NO ES UN AJUSTE: es una medida de la animacion, tan
## fija como su duracion. Sale de mirar cuanto avanza el pie apoyado en un ciclo. Estaba en el panel
## de calibracion como si fuera una opcion y solo servia para liarla: de aqui no se toca.
const CLIP_SPEED := {
	"run_fwd": 2.01, "run_bwd": 1.11, "run_l": 1.38, "run_r": 1.23,
	"run_fwd_l": 2.01, "run_fwd_r": 2.01, "run_bwd_l": 1.23, "run_bwd_r": 1.16,
	"crouch_fwd": 1.14, "crouch_bwd": 1.19, "crouch_l": 1.45, "crouch_r": 1.37,
	"crouch_fwd_l": 1.19, "crouch_fwd_r": 1.10, "crouch_bwd_l": 1.24, "crouch_bwd_r": 1.21,
	"caminar": 1.44, "crouch_fwd_tactico": 0.96,
	"subir_escalera": 1.2, "bajar_escalera": 1.2,
}
## EN UNA ESCALERA (+1 subiendo, -1 bajando): lo pone quien mueve el cuerpo (player.gd, net_player.gd) y
## drive_locomotion cambia el paso del llano por el de peldaños (tools/blender/escalera_anim.py).
var escalera := 0
## DE FRENTE, CADA MODO CON SU PASO (clips_breach.json): caminar tiene el suyo en vez del de correr a
## menos velocidad, y el agachado hacia delante uno nuevo (el del .bin iba encorvado a 50 grados y con
## la cabeza girada a un lado). El nombre del agachado empieza por "crouch" A PROPOSITO: de eso depende
## la pose del arma agachado (_crouch_w). Si el clip no esta cargado, se queda el del .bin.
const CLIP_PROPIO := {"run_fwd": {"andar": "caminar"}, "crouch_fwd": {"agachado": "crouch_fwd_tactico"}}
var _pelvis_movida := false
const REF_SPRINT := 5.0        # para graduar el balanceo del arma con la velocidad

## EN QUE MODO SE ESTA ANDANDO, mirando solo hacia donde va el cuerpo y si va agachado. Se deduce
## aqui y no lo pasa quien llama, para que valga igual para el jugador y para los bots sin tocar
## ninguno de los dos.
static func modo_marcha(lvel: Vector3, crouch: bool) -> String:
	if crouch:
		return "agachado"
	var v := Vector2(lvel.x, lvel.z)
	if v.length() < 0.01:
		return "andar"
	if absf(v.x) > absf(v.y):
		return "lateral_d" if v.x > 0.0 else "lateral_i"
	if v.y > 0.0:
		return "atras"
	# de frente: es esprintar a partir del punto medio entre andar y esprintar
	var corte: float = (float(CAL["andar"]["vel"]) + float(CAL["esprintar"]["vel"])) * 0.5
	return "esprintar" if v.length() >= corte else "andar"

# --- ZANCADA ELASTICA (stride warping) ----------------------------------------------------------
# Con la animacion mas lenta que lo que el cuerpo avanza, el pie patinaria hacia delante. En vez de
# acelerar el ciclo -que se ve a camara rapida- se ALARGA LA ZANCADA: se separan mas las piernas
# girando cadera y rodilla mas de lo que dice el clip. El pie sigue plantado y el gesto se ve largo
# en vez de acelerado, que es como corre alguien de verdad al apretar.
#
# Esto ya no se ajusta a mano: sale solo de la diferencia entre lo que pide la fisica y la velocidad
# de animacion que hayas puesto para ese modo.
const ZANCADA_MAX := 1.60      # y no mas de un 60 %, o las piernas hacen angulos imposibles
## Lo que se abren las piernas respecto al clip. 1.0 = tal cual viene animado.
var zancada := 1.0
## Los huesos que se estiran: las dos piernas enteras. La pelvis NO -girarla mueve todo el cuerpo- y
## los brazos tampoco, que sostienen el arma y los coloca la IK despues.
const HUESOS_ZANCADA := {
	"leg_upper_l": true, "leg_lower_l": true, "foot_l": true,
	"leg_upper_r": true, "leg_lower_r": true, "foot_r": true,
}
## LA RODILLA TIENE TOPE. Alargar la zancada exagera tambien lo que se dobla la rodilla, y es la unica
## articulacion que llega a un imposible: medido con --piernasfoto, esprintando (run_fwd dobla 116 grados
## en el clip) el x1,6 la llevaba a 176, y agachado (122 en el clip, x1,4) a 171. La tibia se metia dentro
## del muslo y el talon subia hasta la cadera. Se exagera igual que el resto de la pierna, pero sin pasar
## de lo que dobla una rodilla de verdad. El paso no se acorta: el largo lo da el muslo, y la rodilla solo
## llega al tope con el pie en el aire.
const RODILLA_MAX := 2.44      # rad, unos 140 grados
const HUESOS_RODILLA := {"leg_lower_l": true, "leg_lower_r": true}
var _loco_idle := ""
var _loco_jump := 0.0
var _loco_land := 0.0
var _loco_floor := true

## Clip de marcha por octantes en el marco del cuerpo (-Z adelante, +X derecha). 0.383 = sin(22,5°),
## que parte el círculo en 8 sectores iguales. Los sufijos del .bin están al revés que su nombre:
## medido sobre el pie apoyado, `run_l` viaja a la DERECHA.
func move_clip(lv: Vector3, crouch: bool) -> String:
	var pre := "crouch" if crouch else "run"
	var fwd := -lv.z
	var right := lv.x
	var suf := ""
	if fwd > 0.383:
		suf = "_fwd"
	elif fwd < -0.383:
		suf = "_bwd"
	if absf(right) > 0.383:
		suf += "_l" if right > 0.0 else "_r"
	if suf == "":
		suf = "_l" if right > 0.0 else "_r"
	var n := pre + suf
	if has_clip(n):
		return n
	n = pre + ("_fwd" if fwd >= 0.0 else "_bwd")
	return n if has_clip(n) else (pre + "_idle" if crouch else "run_fwd")

## Elige clip y cadencia a partir del estado de locomoción. `lvel` es la velocidad en el marco
## del cuerpo. `turn_dir` != 0 reproduce el giro en el sitio (+1 = gira a su derecha).
func drive_locomotion(lvel: Vector3, crouch: bool, on_floor: bool, turn_dir: int, dt: float) -> void:
	if not lvel.is_finite():
		lvel = Vector3.ZERO
	_mv_lvel = lvel
	if crouch != _mv_crouch and _mv != null:
		_mv.agacharse(crouch)                  # el peso al bajar o subir (marcha_viva.gd)
	_mv_crouch = crouch
	_mv_suelo = on_floor
	# LA MIRADA EN CASCADA (marcha_viva.gd): si la cadera se esta recolocando, con el clip de giro en el sitio (pasos)
	if turn_dir == 0 and _mv != null:
		turn_dir = _mv.giro()
	if _caida_t >= 0.0:
		return            # tirado por una explosion: manda el clip de la caida hasta que acaba
	if _punio_t >= 0.0 or _salto_fase != "":
		return            # el punetazo o el salto de la habilidad: manda su clip (cuerpo entero) hasta que acaba
	if clip_rescate != "":
		return            # cargando, reanimando o levantandose (rescate.gd): manda ese clip
	if _trepa_t >= 0.0:
		# SE ACABA SOLA. Antes el reloj se quedaba clavado en cero (`maxf(..., 0)`), asi que la subida
		# solo terminaba si alguien llamaba a fin_trepar(): en tu maquina lo hace el jugador, pero al
		# VERLO POR LA RED no lo llama nadie, y el companero se quedaba trepando para siempre.
		_trepa_t -= dt
		if _trepa_t >= 0.0:
			return        # subiendo a un borde: manda el clip de trepar
		fin_trepar()
	if _muerto and _limp_t < 0.0:
		ojos_vivir()
	_loco_jump = maxf(_loco_jump - dt, 0.0)
	_loco_land = maxf(_loco_land - dt, 0.0)
	if on_floor and not _loco_floor:
		_loco_land = clip_dur("jump_land")
		if _mv != null:
			_mv.aterrizar(-_mv_vy)              # las piernas encajan la caida (marcha_viva.gd)
		_mv_vy = 0.0
	elif not on_floor and _loco_floor:
		_loco_jump = clip_dur("jump_start")
	_loco_floor = on_floor
	var hspeed := Vector2(lvel.x, lvel.z).length()
	move_amount = clampf(hspeed / 3.4, 0.0, 1.0)
	if not on_floor:
		# `restart`: son clips de un solo uso. Sin esto arrancaban por donde iba el clip anterior
		# (el de correr, por ejemplo) y el salto empezaba a mitad de gesto.
		# Y la mezcla es MAS LARGA en salto/aterrizaje: son las posturas mas distintas entre si de
		# todo el juego (correr -> encogerse -> caer), y con 0,15 s el cambio se notaba a saltos.
		blend_time = 0.28
		play("jump_start" if _loco_jump > 0.0 and has_clip("jump_start") else "jump_loop", _loco_jump > 0.0)
		blend_time = 0.15
		anim_speed = 1.0
		zancada = 1.0
	elif _loco_land > 0.0 and not crouch and has_clip("jump_land"):
		blend_time = 0.30
		play("jump_land", true)
		blend_time = 0.15
		anim_speed = 1.0
	elif hspeed > 0.35:
		var clip := move_clip(lvel.normalized(), crouch)
		if CLIP_PROPIO.has(clip):
			var propio: String = CLIP_PROPIO[clip].get(modo_marcha(lvel, crouch), "")
			if propio != "" and has_clip(propio):
				clip = propio
		# LA ESCALERA, de frente (o casi) y de pie: rodillas arriba y el cuerpo echado adelante al subir, de
		# puntera y mirando los peldaños al bajar. Va al paso que se avanza: la zancada ya es la de la escalera.
		var ce := "subir_escalera" if escalera > 0 else "bajar_escalera"
		if escalera != 0 and not crouch and -lvel.z > absf(lvel.x) * 0.7 and has_clip(ce):
			play(ce)
			anim_speed = clampf(hspeed / float(CLIP_SPEED[ce]), 0.5, 2.6)
			zancada = 1.0
			sway_amount = clampf(hspeed / REF_SPRINT, 0.0, 1.0)
			_loco_idle = ""
			return
		play(clip)
		# LA VELOCIDAD DE ANIMACION LA PONES VOS, por modo, en CALIBRAR ANIMACION. Aqui solo se
		# ajusta a la velocidad real: si este cuerpo se mueve a la mitad de la velocidad de
		# referencia de su modo, el ciclo va a la mitad.
		var m: Dictionary = CAL.get(modo_marcha(lvel, crouch), CAL["andar"])
		anim_speed = clampf(float(m["anim"]) * (hspeed / maxf(float(m["vel"]), 0.01)), 0.35, 3.0)
		# y lo que la animacion no cubra, lo cubre la zancada, para que el pie no patine
		var pide: float = hspeed / float(CLIP_SPEED.get(clip, 2.0))
		zancada = clampf(pide / maxf(anim_speed, 0.01), 1.0, ZANCADA_MAX)
		sway_amount = clampf(hspeed / REF_SPRINT, 0.0, 1.0)
		_loco_idle = ""
	elif turn_dir != 0 and has_clip(("crouch_turn" if crouch else "turn") + ("_l" if turn_dir > 0 else "_r")):
		play(("crouch_turn" if crouch else "turn") + ("_l" if turn_dir > 0 else "_r"), true)
		anim_speed = 1.0
		_loco_idle = ""
	else:
		if _loco_idle == "":
			_loco_idle = "idle_%d" % (randi() % 6 + 1)
			if not has_clip(_loco_idle):
				_loco_idle = "idle_1"
		blend_time = 0.34          # parada suave: cortar en seco a reposo se ve brusco
		# con el escudo, quieto es la GUARDIA: de perfil detras del escudo, el peso repartido y respirando
		if not crouch and weapon_kind == "escudo" and not _external_weapon and has_clip("escudo_guardia"):
			play("escudo_guardia")
		else:
			play("crouch_idle" if crouch else _loco_idle)
		blend_time = 0.15
		anim_speed = 1.0

# --- Cuerpo blando al morir -------------------------------------------------------------------
# No hay clip de muerte en el .bin y un ragdoll por hueso (PhysicalBone3D x24) sería caro en móvil.
# En su lugar el esqueleto se desploma hacia una pose floja mientras el cuerpo rígido cae y rueda:
# la columna se curva, los brazos cuelgan y las rodillas ceden. Se lee como que pierde el tono,
# en vez de caer tieso como una tabla.
# Un cuerpo sin tono NO apunta todos sus huesos al suelo: haciendo eso la columna se pliega sobre
# sí misma y el cadáver se encoge como una bola. Solo cuelgan los miembros libres; el tronco y las
# piernas se limitan a perder la tensión de la pose de combate.
#
## CUELGAN hacia la gravedad. El rig tiene +X a lo largo del hueso, así que colgar es llevar ese
## +X hacia abajo por el arco más corto.
const LIMP_HANG := {
	"shoulder_l": 0.30, "shoulder_r": 0.30,
	"arm_upper_l": 0.90, "arm_upper_r": 0.90,
	"arm_lower_l": 1.00, "arm_lower_r": 1.00,
	"hand_l": 0.70, "hand_r": 0.70,
	"neck": 0.35, "head": 0.45,
	# EL TRONCO Y LAS PIERNAS, AHORA TAMBIEN. Antes estaban en LIMP_RELAX, que solo los devuelve a su
	# POSE DE REPOSO... y el reposo de un rig construido de pie es la pose de pie. Asi que medio
	# cuerpo no se aflojaba nunca: volvia a estar recto, y el cadaver caia tieso de cintura para
	# abajo por mucho que los brazos colgaran.
	#
	# No van al maximo a proposito: una pierna con 1,0 se dobla como un fideo. Con la rodilla mas
	# suelta que el muslo, el cuerpo se plega por donde se plega de verdad.
	"leg_upper_l": 0.55, "leg_upper_r": 0.55,
	"leg_lower_l": 0.80, "leg_lower_r": 0.80,
	"foot_l": 0.50, "foot_r": 0.50,
}
## SE RELAJAN hacia su reposo: pierden la rigidez del clip sin doblarse hacia abajo. Así el tronco
## queda extendido y las piernas dejan de estar "de pie" en vez de encogerse.
## EL TRONCO SE DOBLA, NO CUELGA. Colgar consiste en girar el eje X del hueso hasta que apunte al
## suelo, y eso funciona en brazos y piernas porque ahi el eje X corre A LO LARGO del miembro. En la
## columna el eje X va de lado a lado del cuerpo: girarlo hacia abajo no hunde el tronco, lo LADEA.
## Se probo meter estomago y pecho en la tabla de colgar y no hacia nada util, que es justo lo que se
## veia -la panza seguia recta-.
##
## Un tronco muerto se PLIEGA sobre si mismo. Aqui se le da un doblez fijo, en grados, sobre su
## propio eje de flexion: el estomago cede mas que el pecho, como una espalda que se vence.
const LIMP_DOBLA := {
	"stomach": 26.0, "chest": 15.0,
}


## Lo unico que queda solo "relajandose": los dedos de los pies, que no tienen a donde colgar.
const LIMP_RELAX := ["toes_l", "toes_r"]
var _limp_t := -1.0

# EL SUELO, QUE HASTA AHORA NO EXISTIA PARA EL CADAVER. Los miembros perseguian la vertical sin
# enterarse de que habia debajo, asi que un brazo caido atravesaba el suelo, la escalera o el
# escombro sobre el que habia quedado el cuerpo. Eso es lo que delata que no es un ragdoll: no es que
# le falte fisica, es que los miembros no chocan con nada.
#
# En vez de meter doce cuerpos fisicos por cadaver -inviable: el avatar cuelga de un nodo escalado a
# 0,02 y con catorce cadaveres serian ciento setenta cuerpos- se sondea el hueco libre bajo cada
# miembro y se limita cuanto puede bajar. El brazo se para donde toca el suelo. Es un rayo por
# miembro cada 0,25 s, contra la version cara: dos rayos por cadaver.
const LIMP_LARGO := {          # cuanto mide cada miembro colgando, en metros
	"arm_lower_l": 0.30, "arm_lower_r": 0.30,
	"arm_upper_l": 0.30, "arm_upper_r": 0.30,
	"hand_l": 0.16, "hand_r": 0.16,
	"head": 0.14, "neck": 0.10,
	"shoulder_l": 0.20, "shoulder_r": 0.20,
	"stomach": 0.22, "chest": 0.24,
	"leg_upper_l": 0.42, "leg_upper_r": 0.42,
	"leg_lower_l": 0.40, "leg_lower_r": 0.40,
	"foot_l": 0.18, "foot_r": 0.18,
}
var mundo = null               ## el VoxelWorld, para poder preguntar por el suelo
var _suelo := {}               ## hueso -> metros libres hacia abajo
var _suelo_t := 0.0


## Busca el mundo subiendo por el arbol. El avatar no lo conoce de por si, y un cadaver cambia de
## padre al morir (pasa del bot al cuerpo rigido), asi que se resuelve cuando hace falta y no antes.
func _buscar_mundo() -> void:
	var n: Node = self
	while n != null:
		if "world" in n and n.world != null:
			mundo = n.world
			return
		n = n.get_parent()


## Cuanto hueco hay bajo cada miembro. Se refresca despacio a proposito: un cadaver no se mueve
## deprisa, y esto no tiene por que ser exacto, solo tiene que impedir que el brazo se hunda.
func _sondear_suelo(dt: float) -> void:
	_suelo_t -= dt
	if _suelo_t > 0.0:
		return
	_suelo_t = 0.25
	if mundo == null or not mundo.has_method("raycast") or skeleton == null:
		return
	for b in LIMP_LARGO.keys():
		if not bone_idx.has(b):
			continue
		var i: int = bone_idx[b]
		var wp: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(i)).origin
		var r: Dictionary = mundo.raycast(wp + Vector3(0, 0.05, 0), Vector3.DOWN, 2.5)
		_suelo[b] = (float(r.get("distance", 2.5)) - 0.05) if r.get("hit", false) else 2.5

## Deja el cuerpo sin tono. A partir de aquí los huesos persiguen la vertical con retraso.
func go_limp() -> void:
	ojos_morir()
	if skeleton == null:
		return
	# el escudo no se queda pegado al muerto: cae con el
	if escudo_activo() and _esc_root and is_instance_valid(_esc_root) and _esc_root.visible:
		_soltar_escudo(Vector3.ZERO)
	_limp_t = 0.0
	_suelo.clear()
	_suelo_t = 0.0
	_buscar_mundo()


## Y LA VUELTA. `go_limp` no tenia forma de deshacerse: `_limp_t` se ponia a cero y no habia nada que
## lo devolviera a -1, asi que un avatar desplomado se quedaba desplomado PARA SIEMPRE. En las
## oleadas eso se ve: un companero muere, la oleada se supera, revive... y en las demas pantallas
## sigue tirado como un muñeco de trapo, porque nadie le devolvio los huesos.
func levantar() -> void:
	_limp_t = -1.0
	ojos_vivir()
	if _esc_root and is_instance_valid(_esc_root):
		_esc_root.visible = true
	_esc_rotura = -1.0
	_esc_soltado = false
	_suelo.clear()
	_suelo_t = 0.0

## Los huesos NO se colocan en una pose final: persiguen la vertical con retraso, cada frame y
## para siempre. Ese retraso es lo que se lee como blando — si alcanzaran el objetivo al instante
## el cuerpo volvería a parecer rígido, solo que con los brazos abajo. Al rodar el cadáver los
## miembros van por detrás y se balancean solos.
func _apply_limp(dt: float) -> void:
	_limp_t += dt
	_sondear_suelo(dt)
	# LA FLACIDEZ ENTRA CASI DE GOLPE. Estaba en 1,2, o sea que tardaba 0,83 s en llegar al maximo...
	# y una caida por muerte dura medio segundo. Resultado: el cuerpo tocaba el suelo cuando todavia
	# iba por la mitad de blando, y lo que se veia era un muneco TIESO cayendo y ablandandose despues,
	# ya tumbado. El musculo se suelta en cuanto te matan, no en un segundo.
	var ramp: float = clampf(_limp_t * 6.0, 0.0, 1.0)
	# tronco y piernas: solo pierden la tensión, van hacia su reposo
	for b in LIMP_RELAX:
		if not bone_idx.has(b):
			continue
		var ir: int = bone_idx[b]
		var rest: Quaternion = skeleton.get_bone_rest(ir).basis.get_rotation_quaternion()
		var c0: Quaternion = skeleton.get_bone_pose_rotation(ir)
		skeleton.set_bone_pose_rotation(ir, c0.slerp(rest, 1.0 - pow(2.0, -1.6 * dt)))
	# miembros libres: persiguen la vertical CON RETRASO, siempre. Ese retraso es lo que se lee
	# como blando; si alcanzaran el objetivo al instante volverían a parecer rígidos.
	# el doblez del tronco, antes de los miembros: los brazos cuelgan DESDE el pecho ya vencido
	for b in LIMP_DOBLA.keys():
		if not bone_idx.has(b):
			continue
		var ib: int = bone_idx[b]
		var rest_b: Quaternion = skeleton.get_bone_rest(ib).basis.get_rotation_quaternion()
		var dobla: Quaternion = Quaternion(Vector3.RIGHT, deg_to_rad(float(LIMP_DOBLA[b]))) 
		var meta_b: Quaternion = (rest_b * dobla).normalized()
		var cur_b: Quaternion = skeleton.get_bone_pose_rotation(ib)
		skeleton.set_bone_pose_rotation(ib, cur_b.slerp(meta_b, 1.0 - pow(2.0, -3.5 * ramp * dt * 6.0)))

	for b in LIMP_HANG.keys():
		if not bone_idx.has(b):
			continue
		var i: int = bone_idx[b]
		var p := skeleton.get_bone_parent(i)
		var pg: Quaternion = Quaternion(skeleton.get_bone_global_pose(p).basis) if p >= 0 else Quaternion.IDENTITY
		var g: Quaternion = Quaternion(skeleton.get_bone_global_pose(i).basis)
		var axis: Vector3 = (g * Vector3.RIGHT).normalized()
		var drop: Quaternion = Quaternion(axis, Vector3.DOWN) if axis.dot(Vector3.DOWN) < 0.999 else Quaternion.IDENTITY
		var w: float = float(LIMP_HANG[b]) * ramp
		# EL TOPE DEL SUELO. Si bajo el miembro hay menos hueco que su propia longitud, no puede
		# bajar del todo: se le recorta las ganas de colgar en esa proporcion. El brazo queda
		# apoyado en vez de metido dentro del suelo, y sobre un escombro o un escalon queda a la
		# altura del escombro, que es exactamente lo que hace un cuerpo de verdad.
		if _suelo.has(b):
			var largo: float = float(LIMP_LARGO.get(b, 0.25))
			# CON SUELO EN 0,35, no en cero. Este tope existe para que un brazo no se meta dentro del
			# piso, pero llevado a cero tambien MATABA la flacidez: si el rayo salia con distancia
			# rara -por ejemplo empezando dentro de una pared- el miembro se quedaba rigido del todo.
			# Un miembro apoyado en el suelo sigue estando muerto, solo que no puede bajar mas.
			w *= maxf(clampf(float(_suelo[b]) / maxf(largo, 0.01), 0.0, 1.0), 0.35)
		var goal: Quaternion = (pg.inverse() * (Quaternion.IDENTITY.slerp(drop, w) * g)).normalized()
		# y persiguen mas rapido: el retraso es lo que se lee como blando, pero demasiado retraso se
		# lee como rigido. Al doble, el brazo ya va suelto mientras el cuerpo cae.
		var rate: float = 2.4 + 6.0 * float(LIMP_HANG[b])
		var cur: Quaternion = skeleton.get_bone_pose_rotation(i)
		skeleton.set_bone_pose_rotation(i, cur.slerp(goal, 1.0 - pow(2.0, -rate * dt)))

func has_clip(n: String) -> bool:
	return _shared_clips.has(n)

## Clips que NO son ciclo: se reproducen una vez y se quedan quietos al final (el que los lanzo
## decide cuando se vuelve a lo de siempre).
const CLIPS_UNA_VEZ := {"caida": true, "trepar": true, "jump_start": true, "jump_land": true, "punetazo": true,
	"salto_despegue": true, "salto_golpe": true,
	"rescate_levantar": true, "rescate_soltar": true, "rescate_ayudar": true, "rescate_revivido": true}


func play(clip_name: String, restart: bool = false) -> void:
	if not _shared_clips.has(clip_name) or clip_name == current_clip:
		return
	if current_clip != "":
		_blend_from = current_clip
		# INSTANTE CONGELADO del clip que se deja. Antes el clip anterior se muestreaba con el
		# tiempo del NUEVO (que además se reinicia en los clips de un solo uso), asi que la mezcla
		# no salia de la postura en la que estaba el cuerpo: al saltar y al caer se notaba el tiron.
		_blend_prev_time = _time
		_blend_time = 0.0
		_blend_duration = blend_time
	current_clip = clip_name
	if restart:
		_time = 0.0

var _skip_acc := 0.0
## EL MUESTREO EN C++ (2026-10-01): AnimMuestreo.posar hace el bucle de huesos de _process_inner (el mismo resultado: las
## mismas funciones de Quaternion de Godot) en una llamada. Con 9 bots era ~1,2 ms por fotograma en GDScript. Si la
## extension es vieja y no la trae, el bucle de siempre. A/B: --sinanimc.
static var _anim_c = (ClassDB.instantiate("AnimMuestreo") if ClassDB.class_exists("AnimMuestreo") and not ("--sinanimc" in OS.get_cmdline_user_args()) else null)
const _HUESOS_RETOQUE := ["leg_upper_l", "leg_lower_l", "foot_l", "leg_upper_r", "leg_lower_r", "foot_r"]
var _casillas := PackedInt32Array()      ## casilla de _shared_bone_order -> hueso de mi esqueleto (-1 si no lo tengo)
var _casillas_ok := false

func _preparar_casillas() -> void:
	_casillas = PackedInt32Array()
	_casillas.resize(_shared_bone_order.size())
	var vistos := 0
	for i in _shared_bone_order.size():
		var bn: String = _shared_bone_order[i]
		_casillas[i] = int(bone_idx[bn]) if bone_idx.has(bn) else -1
		if bone_idx.has(bn):
			vistos += 1
	# si mi esqueleto tuviera huesos que no estan en el orden comun, el C++ no los veria: entonces, el bucle de siempre
	_casillas_ok = vistos == bone_idx.size()
## --animcprueba: compara la pose del C++ con la del bucle de GDScript, hueso a hueso (angulo maximo)
static var _prueba_c: bool = "--animcprueba" in OS.get_cmdline_user_args()
static var _prueba_max := 0.0
static var _prueba_n := 0
static var _prueba_avisos := 0

func _comparar_c(cb: Dictionary, pb: Dictionary, mc: Array, mp: Array, bw: float) -> void:
	for bname in _huesos_lista:
		var bc = cb.get(bname)
		if bc == null:
			continue
		var q: Quaternion = _muestra_con(bc, mc)
		if _blend_from != "":
			var bp = pb.get(bname)
			if bp != null:
				q = _muestra_con(bp, mp).slerp(q, bw)
		var r: Quaternion = skeleton.get_bone_pose_rotation(bone_idx[bname])
		var ang: float = 2.0 * acos(clampf(absf(q.normalized().dot(r.normalized())), 0.0, 1.0))
		if ang > 0.001 and _prueba_avisos < 12:
			_prueba_avisos += 1
			print("[animc] %s clip %s mc %s · desde %s mp %s bw %.3f · gd %s · c %s" % [bname, current_clip, str(mc), _blend_from, str(mp), bw, str(q), str(r)])
		_prueba_max = maxf(_prueba_max, ang)
		_prueba_n += 1
	if _prueba_n % 20000 < 30:
		print("[animc] %d huesos comparados, diferencia maxima %.6f grados" % [_prueba_n, rad_to_deg(_prueba_max)])
var _escalonado := false
static var _sin_escalonar: bool = "--sinescalonar" in OS.get_cmdline_user_args()   ## A/B
# --- arma en las manos (IK de dos huesos por brazo sobre la animación) ---
const WeaponModelScript := preload("res://scripts/weapon_model.gd")
const HabFxScript := preload("res://scripts/hab_fx.gd")
var weapon_root: Node3D
# ---------------------------------------------------------------------------
# Sujeción del arma en tercera persona, portada de Teardown (C:/Games/Teardown/data/script/toolanimation.lua,
# player_locomotion.lua::locomotion_ik y las ubicaciones tp_* de data/prefab/tool/rifle|shotgun|rocket.xml).
#  * El arma se coloca en "espacio del ojo": origen a 1,7 m sobre el pie del avatar, sólo con la guiñada del
#    cuerpo. Pose tp_action al disparar/apuntar; tras 2 s sin disparar pasa a tp_run (arma en bandolera),
#    mezclada con tp_jump / tp_crouch según el clip. Las poses se amortiguan (60 Hz acción, 20 Hz resto).
#  * Se suma el bamboleo del hombro derecho de la animación, el cabeceo del brazo alrededor del cuello
#    (x1 acción, x0,5 bandolera), el balanceo por el pie derecho y el cabeceo del propio arma (x1 / x0,4).
#  * Las manos van por IK (hombro -> mano) a la empuñadura y al guardamanos del modelo del arma; nuestra
#    empuñadura se hace coincidir con la ubicación tp_action_rh de Teardown.
#  * Mirar arriba/abajo arquea estómago/pecho/cabeza (0,6/0,6/0,3) y el retroceso echa el pecho atrás
#    (25 grados x retroceso^6) y la cabeza adelante (10 grados).
# Teardown tiene +X a la derecha; nuestro modelo tiene la derecha en -X: se espeja X (giros Y y Z cambian
# de signo). Posiciones en metros, giros en grados (orden Ry·Rx·Rz, como el editor de Teardown).
# ---------------------------------------------------------------------------
const EYE_HEIGHT_M := 1.7
## AJUSTES DEL APUNTADO. Son variables y no constantes porque se afinan a mano en el editor de
## puntería (lobby, --miraeditor): alli se mueven con barras, se ve el resultado al momento y se
## copian los valores ya buenos para pegarlos aqui.
##
## Los valores de abajo NO estan puestos a tanteo: salieron del editor, colocados a mano sobre el
## modelo hasta que la mira quedo en el ojo, y copiados de ahi.
##
## `aim_ojo` es el OJO DERECHO respecto al HUESO DE LA CABEZA, en voxels del modelo. Va atado a la
## cabeza y no a una altura fija: con la constante vieja de 1,70 m el "ojo" caia en y=78 cuando la
## cabeza esta en y=64 -- 14 voxels por encima del craneo -- y el arma flotaba sobre la cabeza.
static var aim_ojo := Vector3(2.70, -0.25, -4.50)
## Cuanto por delante del ojo se pone la mira, en metros.
## (las armas largas: la culata al hombro y la mira pegada a la cara. Estaba a 0,45 y el arma quedaba 79 cm delante
## del cuello: los brazos no llegaban y se veia FLOTANDO delante de las manos -22 y 54 cm de hueco, medido-)
static var aim_delante := 0.160
## La pistola se apunta con los brazos estirados, a dos manos: la mira bastante mas lejos del ojo
const AIM_DELANTE_PISTOLA := 0.36
## Donde va la mano de APOYO en la pistola, respecto a la empuñadura (metros, en el arma): abrazando la mano del gatillo
## por el lado de fuera y un poco por debajo
const PISTOLA_APOYO := Vector3(0.042, -0.028, 0.018)
## Giro extra del arma al apuntar (grados: cabeceo, guinada, alabeo). Es lo que permite recogerla
## contra el hombro en vez de dejarla atravesada delante de la cara.
static var aim_giro := Vector3.ZERO

## POSES DEL ARMA QUE SE ESTAN EDITANDO. El editor mete aqui {"rifle/run": [pos, rot], ...} y esas
## mandan sobre las de HOLD_POSES sin tocar el codigo. Vacio = se usan las de siempre.
## LA CLAVE LLEVA EL ARMA DELANTE a proposito: el fusil y el mazo tienen poses con el MISMO nombre
## ("action", "run"...), y con la clave a secas editar la del fusil le cambiaba la guardia al mazo.
static var pose_edit := {}


## La pose `nombre` del arma `kind`: la que este en edicion si la hay, y si no la del catalogo.
static func _pose_de(poses: Dictionary, nombre: String, kind := "rifle") -> Array:
	var k: String = kind + "/" + nombre
	if pose_edit.has(k):
		return pose_edit[k]
	return poses[nombre]
const HOLD_POSES := {
	"rifle": {
		"action": [Vector3(0.270, -0.690, -0.140), Vector3(-21.3, 72.8, -0.4)],
		"action_crouch": [Vector3(0.3, -0.5, -0.15), Vector3(0, 0, 5)],
		# CORRIENDO: el arma se TUMBA contra el cuerpo, igual que en primera persona (ahi el alabeo
		# llega a 84 grados). Sin alabeo, en tercera persona seguia apuntando al frente mientras
		# corrias, que es lo que no cuadraba entre las dos vistas.
		# la BOCA mas a la derecha (guinada 34 -> 62): asi el arma queda inclinada contra el cuerpo y
		# hacia el centro, en vez de seguir apuntando al frente mientras corres
		# TODAS LAS POSES DE ESTE BLOQUE (action, walk, run, crouch, jump) estan colocadas a mano en
		# el editor de poses (EDITOR POSES.bat), cada una con su animacion delante. No son numeros
		# de tanteo: si hay que retocarlas, se abre el editor y se copian de ahi, no se tocan aqui
		# a ojo.
		"run": [Vector3(0.050, -0.710, -0.070), Vector3(16.0, 27.2, -26.3)],
		# ANDAR TIENE SU PROPIA POSE. Antes caminar usaba la de estar quieto y solo se acercaba a la
		# de correr segun la velocidad, asi que no habia forma de afinar el paso sin tocar tambien
		# la parada. Ahora hay tres: quieto ("action"), andando ("walk") y corriendo ("run").
		"walk": [Vector3(0.210, -0.650, -0.220), Vector3(-46.6, 126.9, -30.0)],
		"jump": [Vector3(0.140, -0.760, 0.020), Vector3(24.0, 62.0, -60.0)],
		# Colocada en el editor de poses, con el personaje agachado delante.
		"crouch": [Vector3(-0.300, -0.540, -0.270), Vector3(-73.9, -180.0, -180.0)],
		"reload": [Vector3(0.18, -0.55, -0.02), Vector3(22, 20, -25)],
		"swap": [Vector3(0.22, -0.75, 0.06), Vector3(55, 25, 0)],
		"rh": Vector3(0.0, 0.05, -0.1),
	},
	"sledge": {
		# El cabeceo POSITIVO es el que levanta la cabeza del mazo. Con valores negativos el hierro
		# se iba al suelo y el avatar quedaba con los brazos en alto sujetando el mango: horrible.
		# MISMO CRUCE QUE EN PRIMERA PERSONA. Alli la pose es (52, -62, -12); aqui las poses se
		# espejan (_td_pose invierte guinada y alabeo), asi que se escriben con el signo cambiado
		# para que el mazo se vea igual desde fuera que desde los ojos del jugador.
		# mas abajo y mas afuera: pegado arriba, la cabeza del mazo quedaba junto a la cara del
		# personaje y el brazo derecho le cruzaba por delante
		# OJO: aqui NO vale copiar la pose de primera persona. Desde los ojos del jugador un mango
		# apuntando al frente se ve "cruzado"; desde fuera se ve DE CANTO y el mazo parece un palito.
		# Para que se lea desde fuera, el mango tiene que ir atravesado al cuerpo (guinada pequena)
		# y subiendo, o sea de la cadera derecha al hombro izquierdo.
		# GUARDIA: la cabeza de hierro cruzada por delante del HOMBRO DERECHO y el mango bajando
		# hacia la cadera izquierda. (Las poses se espejan al aplicarse, de ahi los signos.)
		# La guinada POSITIVA lleva la cabeza al hombro DERECHO (las poses se aplican espejadas: con
		# valores negativos se iba al izquierdo, que es lo que se veia mal).
		"action": [Vector3(0.34, -0.52, -0.14), Vector3(24.0, 52.0, -16.0)],
		"action_crouch": [Vector3(0.40, -0.58, -0.10), Vector3(24.0, 52.0, -16.0)],
		# Al correr el mazo BAJA y se terciona mas, igual que hace el fusil. Antes estas tres poses
		# se habian quedado con el signo viejo de la guinada, asi que al echar a correr el mazo daba
		# un salto al otro hombro en vez de acomodarse.
		"run": [Vector3(0.30, -0.62, -0.06), Vector3(14.0, 60.0, -55.0)],
		"jump": [Vector3(0.30, -0.66, -0.10), Vector3(10.0, 66.0, -12.0)],
		"crouch": [Vector3(0.34, -0.64, -0.02), Vector3(20.0, 48.0, -14.0)],
		"swap": [Vector3(0.2, -0.72, 0.06), Vector3(20.0, 25.0, 0.0)],
		# EL MAZAZO, en dos tiempos: carga por encima del hombro derecho y golpe cruzando al frente.
		"swing_up": [Vector3(0.30, -0.16, 0.26), Vector3(78.0, -70.0, 24.0)],
		"swing_hit": [Vector3(-0.10, -0.72, -0.46), Vector3(-58.0, 10.0, -20.0)],
		# GOLPE AL AIRE: el mazo no se para donde iba a estar la pared, sigue de largo por el envion
		# y se va al costado contrario antes de recomponerse. Es la continuacion del recorrido de
		# swing_up a swing_hit: cruza el cuerpo (la x cambia de lado) y se acerca al cuerpo (z sube)
		# porque el hierro va girando alrededor del jugador, no atravesando el suelo.
		"swing_past": [Vector3(-0.34, -0.66, -0.16), Vector3(-40.0, 62.0, -46.0)],
		"rh": Vector3(0.0, 0.0, 0.05),
	},
	"shotgun": {
		"action": [Vector3(0.25, -0.6, 0.05), Vector3(0, 0, 0)],
		"action_crouch": [Vector3(0.3, -0.6, 0.2), Vector3(0, 0, 0)],
		"run": [Vector3(0.20, -0.78, 0.16), Vector3(20, 58, -62)],
		"reload": [Vector3(0.22, -0.7, 0.1), Vector3(22, 18, -28)],
		"swap": [Vector3(0.25, -0.85, 0.16), Vector3(55, 25, 0)],
		"rh": Vector3(0.0, 0.0, -0.15),
	},
	"rocket": {
		"action": [Vector3(0.26, -0.24, -0.1), Vector3(0, 0, 0)],
		"action_crouch": [Vector3(0.38, -0.36, 0.0), Vector3(0, 0, 0)],
		"run": [Vector3(0.22, -0.50, 0.04), Vector3(20, 55, -55)],
		"jump": [Vector3(0.26, -0.16, -0.08), Vector3(10, 5, 5)],
		"crouch": [Vector3(0.38, -0.36, 0.0), Vector3(0, 0, 0)],
		"reload": [Vector3(0.24, -0.42, 0.0), Vector3(18, 15, -20)],
		"swap": [Vector3(0.26, -0.6, 0.08), Vector3(50, 20, 0)],
		"rh": Vector3(0.0, -0.06, -0.18),
	},
	# LA PISTOLA, A DOS MANOS Y A LA ALTURA DEL PECHO (2026-09-28, pedido: "la agarra con una sola mano; la levanta
	# muy alto, por encima de la cabeza"). Estas poses venian del gun.xml de Teardown sin ajustar a este muñeco: con el
	# ojo del esqueleto a 1,7 m quedaban 33 cm POR ENCIMA del cuello (medido, --agarrefoto). Ahora: delante del pecho,
	# casi al centro y la boca un poco baja (preparada); la otra mano la abraza (_apply_arm_ik_inner, PISTOLA_APOYO).
	"pistol": {   # (antes: data/prefab/tool/gun.xml)
		"action": [Vector3(0.10, -0.80, -0.20), Vector3(-14, 0, 0)],
		"action_crouch": [Vector3(0.12, -0.62, -0.22), Vector3(-14, 0, 0)],
		"run": [Vector3(0.16, -0.90, -0.08), Vector3(-45, 8, 8)],
		"jump": [Vector3(0.14, -0.84, -0.14), Vector3(-20, 0, 8)],
		"crouch": [Vector3(0.14, -0.66, -0.18), Vector3(-18, 0, 4)],
		"reload": [Vector3(0.10, -0.80, -0.16), Vector3(24, 18, -18)],
		"swap": [Vector3(0.18, -0.92, -0.04), Vector3(55, 25, 0)],
		"rh": Vector3(-0.015, 0.045, -0.067),
	},
}
## LAS FAMILIAS TAMBIEN. El arma trae en "model" su FAMILIA si la tiene (weapons.gd: ak, ar, bullpup,
## pdw, cerrojo, pistola), no su tipo, y las que faltaban aqui caian en la pose del fusil: la PISTOLA
## TACTICA se sujetaba y se recargaba en tercera persona como un fusil.
const HOLD_ALIAS := {"smg": "rifle", "sniper": "rifle", "c4": "pistol", "pistola": "pistol",
	"ak": "rifle", "ar": "rifle", "bullpup": "rifle", "pdw": "rifle", "cerrojo": "rifle"}
## El mazo no se sujeta como un fusil: se lleva terciado delante del pecho, con la cabeza arriba a
## un lado. Con la pose del fusil el brazo derecho tenia que estirarse hacia atras para alcanzar el
## mango y atravesaba la espalda.
## VACIO, NO "rifle". Este era el valor de "que arma llevo puesta", y arrancar en "rifle" hacia que un
## avatar RECIEN CONSTRUIDO, que no habia empuñado nada en su vida, pasara por el "devolverle el arma
## que llevaba" del final de build(): llamaba a equip_weapon("rifle", "") -sin id-, y weapon_model.gd,
## al no encontrar modelo, le ponia en las manos el PALO de relleno. Eso es lo que se veia en el
## maniqui del lobby: un soldado sujetando un palo con las dos manos.
##
## Con "" no hay arma que devolver, que es la verdad: quien quiera uno, que llame a equip_weapon.
var weapon_kind := ""
var look_pitch := 0.0            # rad, positivo = mirar hacia arriba (lo fija el dueño: jugador o bot)
## LA GUARDIA DE LA ARMERIA (armeria_pantalla.gd, 2026-09-29): tipo de pose -> [posicion, giro], con la forma de HOLD_POSES,
## en lugar de la de "action" (el arma cruzada en diagonal, que de frente y quieto en un menu se veia mal). Solo la pone la
## armeria en SU muñeco; en todos los demas (jugador, bots, lobby) esta vacia y se sujeta exactamente igual que siempre.
var pose_menu: Dictionary = {}
var pistola_una_mano_menu := false    ## la armeria: la pistola solo con la mano del gatillo
## Si este fotograma sujeta con la guardia de escaparate (lo pone _update_rifle_transform; lo lee la IK de los brazos)
var _en_guardia_menu := false
var _mira_pitch := 0.0           # el mismo cabeceo, sin recortar: es el que usa la linea de puntería
var _wm: Node3D                   # modelo del arma (WeaponModel) cuando lo crea el avatar
## Escala de dibujo del arma en TERCERA PERSONA, por id (ver equip_weapon). 1 = tamaño real.
## (con la escala general de abajo: la compacta, que ya iba agrandada, algo menos; las PISTOLAS, mas, que se las comian
## los puños aun a x1,5)
const ESCALA_ARMA_TP := {"smg_compacta": 1.15, "pistola_9": 1.3, "pistola_45": 1.3, "revolver_44": 1.3}
## Y ENCIMA, PARA TODAS (2026-10-03, pedido: "en tercera persona el arma se ve muy chica, la mano la tapa"): `--armaescala=K`
## la cambia para comparar (lobby._armas_foto)
static var escala_armas_tp: float = _leer_escala_armas()


static func _leer_escala_armas() -> float:
	for f in OS.get_cmdline_user_args():
		if String(f).begins_with("--armaescala="):
			return clampf(float(String(f).substr(13)), 0.5, 3.0)
	return ESCALA_ARMAS_TP_FABRICA


## Medido con lobby._armas_foto (los 10 personajes con 6 armas, apuntando): a x1,0 los puños tapaban casi todo el arma;
## x1,5 se ve bien en todos y x1,8 se pasa (el francotirador y el cohete enormes). Los MAZOS no crecen (ya son grandes).
const ESCALA_ARMAS_TP_FABRICA := 1.5


## La escala de dibujo de un arma en tercera persona (relativa a su tamaño real)
static func escala_tp(arma_id: String, kind: String = "") -> float:
	var k := float(ESCALA_ARMA_TP.get(arma_id, 1.0))
	if kind == "sledge" or arma_id.begins_with("mazo_"):
		return k
	return k * escala_armas_tp
var _arma_k := 1.0
var _crouch_w := 0.0
var _jump_w := 0.0
## Gestos de manos. No hay clips de recarga ni de cambio de arma en el .bin, así que se hacen
## con las poses de agarre: el arma baja y se ladea, y los brazos la siguen por IK.
var reloading := false      # lo fija el dueño mientras dura la recarga
## Lo que dura la recarga del arma que lleva (weapons.gd). La pone el dueno ANTES de `reloading`:
## la recarga animada se estira o se encoge para durar eso mismo.
var reload_dur := 2.2
var _reload_w := 0.0
var _swap_t := 0.0
var _swap_w := 0.0
var _recoil := 0.0
var _since_fire := 100.0
var _hold_pos := Vector3.ZERO     # pose amortiguada (espacio del ojo, metros, ya espejada)
var _hold_rot := Quaternion.IDENTITY
var _hold_init := false
var _arm_pitch := 0.0
## Lo que tarda el arma en volver de "encarada" a la pose de llevarla, despues de un tiro.
const TIRO_ENCARA := 0.90
var _dbg_aim_ef := 0.0      ## solo para el banco (--lanapunta)
var _tool_pitch := 0.0

## Disparo: pose de acción durante 2 s y retroceso en el torso.
func kick() -> void:
	_since_fire = 0.0
	# con el escudo el retroceso lo hace su clip (escudo_disparo): el tiron del pecho de los fusiles
	# encima lo sacaba de detras del escudo
	if weapon_kind == "escudo":
		_esc_disparo = 0.0
		_recoil = 0.3
		return
	_recoil = 1.0
	# EL CUERPO ENTERO ENCAJA EL TIRO (marcha_viva.gd): mas cuanto mas pega el arma
	if _mv != null:
		_mv.disparo(float(FUERZA_TIRO.get(weapon_kind, 0.7)))

## UN GOLPE RECIBIDO: el cuerpo lo encaja (marcha_viva.golpe). `empuje` = hacia donde empuja, en el mundo.
func recibir_golpe(empuje: Vector3, dano: float) -> void:
	if _mv != null:
		_mv.golpe(empuje, clampf(dano / 40.0, 0.3, 1.5))

## Lo que mueve el cuerpo cada disparo, por tipo de arma (1 = un fusil fuerte).
const FUERZA_TIRO := {"pistol": 0.45, "smg": 0.5, "rifle": 0.75, "lmg": 0.8, "shotgun": 1.6, "sniper": 1.9,
	"rocket": 2.2, "laser": 0.3}

## Apuntando: mantiene la pose de acción sin retroceso.
func hold_action() -> void:
	# con el ESCUDO no (2026-10-15, bug: "al dejar de apuntar tarda un segundo en volver a cubrirse"): el escudo lee
	# _since_fire como "acaba de disparar", y apuntar lo ponia a 0 en cada fotograma: al soltar, la pistola se quedaba
	# fuera el "encarar tras el tiro" (0,54 s) antes de empezar a volver
	if escudo_activo():
		return
	_since_fire = 0.0

## Gesto de guardar/sacar al cambiar de arma.
func hold_swap(dur: float = 0.35) -> void:
	_swap_t = maxf(_swap_t, dur)

## MAZAZO (cuerpo a cuerpo). Lo ve todo el mundo menos quien golpea, asi que tiene que leerse de
## lejos: carga por encima del hombro y golpe largo cruzando al frente.
var _swing_t := 0.0
var _swing_dur := 0.4
## AJUSTES DEL MAZAZO, editables en caliente desde el editor de poses.
## `swing_scrub`: -1 = el gesto corre solo; 0..1 = congelado en ese punto del arco.
static var swing_scrub := -1.0
## Cuanto dura el arco entero y a que segundo cae el impacto que rompe voxels. Los lee tambien
## player.gd: el gesto que se ve y el momento en que pica tienen que ir juntos.
## EL IMPULSO SE TIENE QUE VER. Con 0,40 s en total la carga duraba 0,14 s: el mazo subia y bajaba
## casi en el mismo gesto y no se leia. Ahora el arco entero dura 0,55 s y la carga se lleva la
## mitad, con su parada arriba antes de reventar.
static var swing_dur_s := 0.85        ## el mazazo de Blender: amago, carga, golpe, rebote y guardia
## Y el muro se rompe cuando el hierro LLEGA ABAJO, no antes: es (carga + golpe) x duracion.
## Estaba en 0,19 s, o sea al 47 % del arco, con el mazo todavia cayendo.
static var swing_hit_at := 0.50        ## frame 31 de 52 a 60 fps: la cabeza del mazo llega abajo
## Donde acaba cada tramo, en fraccion del arco: cargar y golpear (el resto es la vuelta).
static var swing_carga := 0.50
static var swing_golpe := 0.24
## Curvas de cada tramo: por debajo de 1 arranca rapido y frena; por encima, al reves.
## La carga sube pronto y se QUEDA ARRIBA un instante (curva por debajo de 1): esa parada es lo que
## hace que se vea el impulso en vez de un simple subir y bajar.
static var swing_curva_carga := 0.65
## EL GOLPE ACELERA. Con la curva por debajo de 1 salia disparado del hombro y llegaba al muro
## frenando: justo al reves que un mazazo, y de paso era el salto mas feo del gesto (1,2 m entre
## dos poses seguidas). Por encima de 1 sale despacio de arriba y entra reventando.
static var swing_curva_golpe := 2.0
static var swing_curva_vuelta := 1.2
## LOS DOS FINALES DEL MAZAZO. Al aire el gesto sigue de largo y la vuelta va mas lenta (el envion
## se lleva al personaje y le cuesta recomponerse); acertando, el hierro se queda CLAVADO un
## instante en el punto del impacto y de ahi se recompone.
static var swing_pasada_lento := 0.55   ## cuanto se frena la vuelta al fallar (1 = igual)
static var swing_frenazo := 0.08        ## s que el mazo se queda clavado al acertar

## 0 = todavia no se sabe si ha dado en algo · 1 = ha acertado · 2 = al aire.
## Mientras no se sepa se trata como fallo: es lo que se ve si el golpe no llega a resolverse (por
## ejemplo el mazazo de otro jugador en red, que se anima antes de saber en que ha dado).
var _swing_res := 0
var _swing_frena := 0.0               ## s que queda clavado en el impacto
var _swing_lento := 1.0               ## multiplicador del reloj del arco

func play_swing(dur: float = 0.4) -> void:
	_swing_dur = maxf(0.15, dur)
	_swing_t = _swing_dur
	_swing_res = 0
	_swing_frena = 0.0
	_swing_lento = 1.0
	# EL CUERPO ACOMPAÑA EL MAZAZO (marcha_viva.gd): el peso va al golpe
	if _mv != null:
		_mv.mazazo()


## Le dice al gesto en que ha acabado el golpe, en el instante del impacto.
## LIMPIARSE LA CARA con el antebrazo. Lo usa el bot de escaparate y cualquiera que se ensucie.
## EL GESTO TIENE TRES TIEMPOS, que es lo que lo hace humano: primero SUELTA el arma y sube el
## brazo, luego cruza por delante de la cara, y al final vuelve a agarrar el arma. Sin los dos
## tramos de ida y vuelta el brazo aparecia ya en la cara, de un fotograma al siguiente.
const LIMPIA_SUBE := 0.30     ## fraccion del gesto que tarda en soltar el arma y llegar a la cara
const LIMPIA_BAJA := 0.30     ## fraccion final: volver a agarrar el arma
var _limpia_t := 0.0
var _limpia_dur := 0.9


## Cuanto manda el gesto ahora mismo, de 0 a 1: sube al soltar el arma, se mantiene mientras cruza
## la cara y baja al volver. Con esto se mezcla TODO (el brazo y el arma bajando), asi que nada
## salta de golpe.
func _limpia_peso() -> float:
	if _limpia_t <= 0.0:
		return 0.0
	var k: float = 1.0 - (_limpia_t / _limpia_dur)
	if k < LIMPIA_SUBE:
		return smoothstep(0.0, 1.0, k / LIMPIA_SUBE)
	if k > 1.0 - LIMPIA_BAJA:
		return smoothstep(0.0, 1.0, (1.0 - k) / LIMPIA_BAJA)
	return 1.0


## Por donde va el barrido por delante de la cara (0 a 1). Solo corre en el tramo de en medio: al
## subir y al bajar el brazo no barre, va y viene.
func _limpia_barrido() -> float:
	var k: float = 1.0 - (_limpia_t / _limpia_dur)
	return clampf((k - LIMPIA_SUBE) / maxf(1.0 - LIMPIA_SUBE - LIMPIA_BAJA, 0.01), 0.0, 1.0)


## VENDARSE (2026-09-24, pedido: "con mi mano agarro el botiquin y me vendo el brazo"). La mano de apoyo
## suelta el arma y cruza el antebrazo delante del pecho; la del gatillo lleva el rollo de venda y le da
## vueltas alrededor. Igual que limpiarse: se cambian los objetivos del IK y los brazos se doblan solos.
const VENDA_SUBE := 0.15
const VENDA_BAJA := 0.15
var _venda_t := 0.0
var _venda_dur := 6.0
var _venda_prop: Node3D = null

func play_vendar(dur: float = 6.0) -> void:
	_venda_dur = maxf(0.5, dur)
	_venda_t = _venda_dur
	if _venda_prop == null and skeleton != null and bone_idx.has("hand_r") and bone_idx.has("arm_lower_r"):
		var ba := BoneAttachment3D.new()
		ba.bone_name = "hand_r"
		skeleton.add_child(ba)
		# a la escala del esqueleto: la bolsa mide lo que el antebrazo
		var largo: float = skeleton.get_bone_global_rest(bone_idx["hand_r"]).origin.distance_to(
			skeleton.get_bone_global_rest(bone_idx["arm_lower_r"]).origin)
		var rojo := StandardMaterial3D.new()
		rojo.albedo_color = Color(0.62, 0.06, 0.05)
		rojo.roughness = 0.75
		var blanco := StandardMaterial3D.new()
		blanco.albedo_color = Color(0.95, 0.95, 0.93)
		var negro := StandardMaterial3D.new()
		negro.albedo_color = Color(0.05, 0.05, 0.05)
		var bolsa := Node3D.new()
		bolsa.position = Vector3(0, -largo * 0.7, largo * 0.2)
		ba.add_child(bolsa)
		var piezas := [
			[Vector3(0.95, 0.45, 0.5), Vector3.ZERO, rojo],
			[Vector3(0.33, 0.1, 0.012), Vector3(0, 0, 0.256), blanco],
			[Vector3(0.1, 0.33, 0.012), Vector3(0, 0, 0.256), blanco],
			[Vector3(0.33, 0.1, 0.012), Vector3(0, 0, -0.256), blanco],
			[Vector3(0.1, 0.33, 0.012), Vector3(0, 0, -0.256), blanco],
			[Vector3(0.9, 0.025, 0.04), Vector3(0, 0.235, 0), negro],
			[Vector3(0.45, 0.04, 0.07), Vector3(0, 0.33, 0), negro],
		]
		for p in piezas:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = (p[0] as Vector3) * largo * 2.2
			mi.mesh = bm
			mi.material_override = p[2]
			mi.position = (p[1] as Vector3) * largo * 2.2
			bolsa.add_child(mi)
		_venda_prop = ba
	if _venda_prop:
		_venda_prop.visible = true
		# tu propio personaje en primera persona: el botiquin solo da sombra (lo ven los demas, no tu)
		var modo := (GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if _first_person or not _body_visible
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
		for mi in _venda_prop.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = modo
	# el arma se guarda mientras dura (pedido: "cuando me vendo se ve el arma, ocultala")
	if weapon_root and is_instance_valid(weapon_root):
		weapon_root.visible = false


func parar_vendar() -> void:
	_venda_t = 0.0
	if _venda_prop:
		_venda_prop.visible = false
	if weapon_root and is_instance_valid(weapon_root):
		weapon_root.visible = true


func _venda_peso() -> float:
	if _venda_t <= 0.0:
		return 0.0
	var k: float = 1.0 - (_venda_t / _venda_dur)
	if k < VENDA_SUBE:
		return smoothstep(0.0, 1.0, k / VENDA_SUBE)
	if k > 1.0 - VENDA_BAJA:
		return smoothstep(0.0, 1.0, (1.0 - k) / VENDA_BAJA)
	return 1.0


func play_limpiar(dur: float = 0.9) -> void:
	_limpia_dur = maxf(0.3, dur)
	_limpia_t = _limpia_dur


func swing_result(golpeo: bool) -> void:
	if _swing_t <= 0.0:
		return
	_swing_res = 1 if golpeo else 2
	if golpeo:
		_swing_frena = swing_frenazo
	else:
		_swing_lento = swing_pasada_lento

static func _td_pose(p: Array) -> Array:
	var e: Vector3 = p[1]
	var b := Basis.from_euler(Vector3(deg_to_rad(e.x), -deg_to_rad(e.y), -deg_to_rad(e.z)), EULER_ORDER_YXZ)
	return [Vector3(-p[0].x, p[0].y, p[0].z), Quaternion(b).normalized()]

static func _mix_pose(a: Array, b: Array, t: float) -> Array:
	return [(a[0] as Vector3).lerp(b[0], t), (a[1] as Quaternion).slerp(b[1], t)]

## Desplazamiento de un hueso respecto a su posición de reposo (bamboleo de la animación), en voxels.
func _bone_anim_offset(bname: String) -> Vector3:
	if not bone_idx.has(bname):
		return Vector3.ZERO
	var i: int = bone_idx[bname]
	# el ajuste de suelo del clip (skeleton.position) forma parte del desplazamiento real del hueso: al
	# agacharse el hombro baja y el arma debe bajar con él
	return skeleton.get_bone_global_pose(i).origin + skeleton.position - skeleton.get_bone_global_rest(i).origin

## Gira un hueso (y su cadena) alrededor del eje lateral del esqueleto; positivo = echarse hacia atrás.
func _rotate_bone_lateral(bname: String, deg: float) -> void:
	if is_zero_approx(deg) or not bone_idx.has(bname):
		return
	var i: int = bone_idx[bname]
	var p := skeleton.get_bone_parent(i)
	var g := Quaternion(skeleton.get_bone_global_pose(i).basis)
	var pg := Quaternion(skeleton.get_bone_global_pose(p).basis) if p >= 0 else Quaternion.IDENTITY
	var ng := (Quaternion(Vector3.RIGHT, deg_to_rad(deg)) * g).normalized()
	skeleton.set_bone_pose_rotation(i, (pg.inverse() * ng).normalized())

## Igual que el anterior pero sobre la vertical: sirve para que el torso se quede atrás al girar.
func _rotate_bone_yaw(bname: String, deg: float) -> void:
	if is_zero_approx(deg) or not bone_idx.has(bname):
		return
	var i: int = bone_idx[bname]
	var p := skeleton.get_bone_parent(i)
	var g := Quaternion(skeleton.get_bone_global_pose(i).basis)
	var pg := Quaternion(skeleton.get_bone_global_pose(p).basis) if p >= 0 else Quaternion.IDENTITY
	var ng := (Quaternion(Vector3.UP, deg_to_rad(deg)) * g).normalized()
	skeleton.set_bone_pose_rotation(i, (pg.inverse() * ng).normalized())

## Torso: arqueo al mirar arriba/abajo y retroceso (player_locomotion.lua: rot0/rot1/rot2 y RotateBone chest/neck).
func _apply_spine(dt: float) -> void:
	if _arms_only or not bone_idx.has("stomach"):
		return
	_recoil = maxf(0.0, _recoil - 5.0 * dt)
	var deg := rad_to_deg(look_pitch)
	var w := 0.5 * clampf(absf(deg) / 90.0, 0.0, 1.0) * (0.5 + 0.5 * (1.0 - _crouch_w)) * (1.0 - _caida_w)
	var r6 := pow(_recoil, 6.0)
	_rotate_bone_lateral("stomach", 0.6 * deg * w)
	_rotate_bone_lateral("chest", 0.6 * deg * w + 25.0 * r6)
	_rotate_bone_lateral("neck", -10.0 * r6)
	_rotate_bone_lateral("head", 0.3 * deg * w)
	# Inercia al girar la cámara: el torso se queda atrás y se recoloca, igual que el arma. Se
	# reparte por la columna (más arriba, más giro) para que se lea como acomodarse y no como un
	# bloque rígido. Mismo signo que el arma para que acompañen.
	if absf(look_sway.x) > 0.001:
		var sw := -rad_to_deg(look_sway.x)
		_rotate_bone_yaw("stomach", sw * 0.25)
		_rotate_bone_yaw("chest", sw * 0.45)
		_rotate_bone_yaw("head", sw * 0.30)

## Pone un fusil en las manos: el arma cuelga del pecho (sigue al torso) y una IK analítica de dos huesos
## por brazo lleva la mano derecha a la empuñadura y la izquierda al guardamanos, encima de cualquier clip
## (correr, agacharse, reposo...). El codo se orienta hacia un "imán" (abajo/afuera) como en cualquier
## rig de FPS en tercera persona.
var grip_marker: Marker3D
var _ik_debug := false
var fore_marker: Marker3D
const ELBOW_MAGNET_R := Vector3(-12.0, 16.0, 6.0)   # codo derecho: abajo, afuera y atrás
const ELBOW_MAGNET_L := Vector3(9.0, 16.0, -2.0)    # codo izquierdo: abajo y afuera
## LA MANO DE APOYO SUELTA (2026-10-11, correr con la pistola en primera persona): con mano_libre_w > 0 la mano de apoyo
## va a `mano_libre` (en coordenadas del mundo) en vez de al arma, con el codo colgando natural. Lo pone player.gd.
var mano_libre := Vector3.ZERO
var mano_libre_w := 0.0
## y adonde van los CODOS mientras tanto (mundo): fuera de la pantalla por cada esquina de abajo, asi cada brazo entra
## desde su esquina (pedido: "el brazo sale del medio de la pantalla")
var codo_libre := Vector3.ZERO
var codo_gatillo := Vector3.ZERO
## ...y los HOMBROS (mundo): el hombro de los brazos de primera persona esta en el centro y el brazo nacia de ahi; se
## lleva a cada esquina de abajo (fuera de la pantalla) en la proporcion de mano_libre_w
var hombro_libre := Vector3.ZERO
var hombro_gatillo := Vector3.ZERO
## EL GROSOR DEL ANTEBRAZO en primera persona (2026-10-11, pedido: "achica un poquito las manos para que no tapen el
## arma"; el guante es el final del antebrazo): escala del hueso de cada antebrazo en lo ancho (x, z). 1 = como siempre.
var grosor_fp := 1.0
var hombros_w := 0.0                  ## cuanto mandan hombro_* y codo_* (player.gd: siempre en primera persona con arma)
var _hombros_movidos := false
var _hombros_reposo := {}
static var _codo_apoyo_k: float = (func() -> float:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--codoapoyo="):
			return float(String(a).substr(12))
	return 0.0).call()   # (probado: no cambiaba nada medible; queda apagado hasta saber que se ve mal)
const CODO_GAT_BAJA := Vector3(3.0, -6.0, 0.0)       # voxels: el codo del gatillo, mas abajo y mas pegado
const HOMBRO_BAJA := 4.0      ## voxels que se hunde la articulacion del brazo al apuntar
const HOMBRO_PARTE := 0.65                           ## lo que gira el hueso del hombro del total del brazo (_solve_arm)
## POR MODELO (receta "hombro_parte" / "hombro_baja"). El Heraldo Forjado lleva la articulacion del brazo 6-10
## voxels hacia fuera de la clavicula: girar la clavicula hacia el arma se llevaba el brazo entero hacia delante
## al recargar ("los hombros se van para adelante"). Su hombro es una bola centrada en la articulacion y no
## necesita que la clavicula acompañe: ahi va a 0.
var _hombro_parte := HOMBRO_PARTE
var _hombro_baja := HOMBRO_BAJA
## (receta "codo_recto") hueso -> 0..1: cuanto se endereza en los clips de reposo
var _codo_recto: Dictionary = {}

func equip_rifle() -> void:
	equip_weapon("rifle", "carabina_556")

var _arma_id := ""
## Skin fija del arma de este muñeco ("-" = sin pintura). La ponen los bots: sobrevive a rehacer el arma.
var skin_arma_forzada := ""
var _one_hand := false

## Pone un arma en las manos: el TIPO decide como se sujeta y el ID cual es (res://armas/<id>.glb).
## Sustituye a la anterior si la hubiera.
func equip_weapon(kind: String, arma_id: String = "") -> void:
	if not skeleton:
		return
	# OJO con el arma "ya equipada": al reconstruir el avatar (build) el esqueleto es NUEVO y el
	# arma vieja se va con el anterior, pero `weapon_root` se quedaba apuntando a un nodo LIBERADO.
	# Como el tipo y la malla coincidian, esto salia por la puerta de atras y el bot se quedaba sin
	# fusil: disparando con las manos vacias.
	if weapon_root and not is_instance_valid(weapon_root):
		weapon_root = null
		grip_marker = null
		fore_marker = null
		_wm = null
		_esc_root = null
	if weapon_root and not _external_weapon:
		if weapon_kind == kind and _arma_id == arma_id:
			# Mismo arma... pero puede haber cambiado la SKIN, y eso aqui no se notaba: el muñeco se
			# quedaba con la pintura vieja mientras en primera persona ya se veia la nueva.
			if _wm and is_instance_valid(_wm):
				_wm.repintar_skin()
			return
		var _tqe := Time.get_ticks_usec()
		_quitar_escudo()
		_guardar_arma_actual()
		Prof.add("av.eq.0quitar", Time.get_ticks_usec() - _tqe)
		weapon_root = null
		grip_marker = null
		fore_marker = null
		_wm = null
	_quitar_escudo()
	weapon_kind = kind
	_arma_id = arma_id
	_hold_init = false
	# LA QUE YA TENIA GUARDADA, sin montarla de cero (ver ARMAS GUARDADAS, abajo)
	if kind != "vacio" and _sacar_arma_guardada(kind, arma_id):
		return
	# MANOS VACIAS. La ranura vacia del battle royale no tiene modelo: sin esto se montaba el arma por
	# defecto de WeaponModel y al muñeco le salia "un palo negro" en las manos.
	if kind == "vacio":
		weapon_root = null
		grip_marker = null
		fore_marker = null
		_wm = null
		_one_hand = false
		return
	var _teq := Time.get_ticks_usec()
	weapon_root = Node3D.new()
	weapon_root.name = "Weapon"
	skeleton.add_child(weapon_root)
	var wm := WeaponModelScript.new()
	Prof.add("av.eq.1nuevo", Time.get_ticks_usec() - _teq)
	_teq = Time.get_ticks_usec()
	wm.kind = kind
	wm.arma_id = arma_id
	if skin_arma_forzada != "":
		wm.skin_forzada = skin_arma_forzada   # un bot lleva SU skin, no la del jugador
	# EL ARMA A ESCALA DEL MUÑECO, no a escala real. Las manos del avatar son bloques de ~15 cm: un arma
	# corta a su tamaño de verdad (la metralleta compacta mide 47 cm) quedaba tapada entre los dos puños y
	# desde fuera parecia un juguete. Solo es el dibujo en tercera persona: la primera persona usa su propio
	# modelo (WeaponPivot) y los disparos salen de la camara.
	_arma_k = escala_tp(arma_id, kind)
	wm.scale = Vector3.ONE * _arma_k / scale.x   # el arma está en metros; el esqueleto en voxels
	weapon_root.add_child(wm)
	Prof.add("av.eq.2montar", Time.get_ticks_usec() - _teq)
	_teq = Time.get_ticks_usec()
	_wm = wm
	_one_hand = wm.one_handed
	if wm.flash_light:
		wm.flash_light.visible = false
	if _first_person:   # el jugador sólo ve su sombra: el fusil también
		for mi in wm.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	grip_marker = Marker3D.new()
	grip_marker.name = "Grip"
	grip_marker.position = wm.grip_pos * _arma_k / scale.x
	weapon_root.add_child(grip_marker)
	fore_marker = Marker3D.new()
	fore_marker.name = "Foregrip"
	fore_marker.position = wm.foregrip_pos * _arma_k / scale.x
	weapon_root.add_child(fore_marker)
	# Si el cuerpo estaba oculto (primera persona: solo se ve la sombra), el arma nueva tiene que
	# nacer igual de oculta. Antes salia entera y en primera persona veias un fusil flotando
	# delante de la cara, pegado a la pantalla.
	if not _body_visible:
		for mi in wm.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	Prof.add("av.eq.3marcas", Time.get_ticks_usec() - _teq)
	_teq = Time.get_ticks_usec()
	_update_rifle_transform(0.0)
	Prof.add("av.eq.4colocar", Time.get_ticks_usec() - _teq)
	_teq = Time.get_ticks_usec()
	_apply_arm_ik()
	_mover_parpados()
	Prof.add("av.eq.5ik", Time.get_ticks_usec() - _teq)

# --- ARMAS GUARDADAS (2026-10-02, medido con los bots a cohetazos en la cafeteria: cada cambio fusil <-> lanzacohetes
# montaba y horneaba el modelo del arma de cero, 16-17 ms de pico; `bot.cambiar_arma` / `wm.build` / `wm.bake`) -------------
# Al cambiar de arma, la anterior NO se tira: se esconde y se guarda (como mucho ARMAS_GUARDADAS_MAX por muñeco). Si se vuelve
# a sacar la misma (mismo tipo, modelo y pintura), se enseña otra vez. Al soltar el arma (muerte) o reconstruir el rig se
# van todas. Vale para los bots, los jugadores de red y tu muñeco.
const ARMAS_GUARDADAS_MAX := 3
var _armas_guardadas: Array = []      ## [{clave, root, wm, one_hand, k}], la mas reciente al final


func _clave_arma(kind: String, arma_id: String) -> String:
	return "%s|%s|%s" % [kind, arma_id, skin_arma_forzada]


func _guardar_arma_actual() -> void:
	# EL ESCUDO NO SE GUARDA (2026-10-14, bug: "el escudo invisible"): va en la mano (_montar_escudo) y se borra al
	# cambiar de arma (_quitar_escudo); la pistola guardada volvia sin el
	var con_escudo: bool = _wm != null and is_instance_valid(_wm) and "escudo_nodo" in _wm and _wm.escudo_nodo != null
	if weapon_root == null or not is_instance_valid(weapon_root) or _wm == null or not is_instance_valid(_wm) \
			or con_escudo or String(weapon_kind) == "escudo" or "--sinarmasguardadas" in OS.get_cmdline_user_args():
		if weapon_root and is_instance_valid(weapon_root):
			weapon_root.queue_free()
		return
	weapon_root.visible = false
	if grip_marker and is_instance_valid(grip_marker):
		grip_marker.queue_free()
	if fore_marker and is_instance_valid(fore_marker):
		fore_marker.queue_free()
	_armas_guardadas.append({"clave": _clave_arma(weapon_kind, _arma_id), "root": weapon_root, "wm": _wm,
		"one_hand": _one_hand, "k": _arma_k})
	while _armas_guardadas.size() > ARMAS_GUARDADAS_MAX:
		var vieja: Dictionary = _armas_guardadas.pop_front()
		if is_instance_valid(vieja["root"]):
			(vieja["root"] as Node).queue_free()


func _sacar_arma_guardada(kind: String, arma_id: String) -> bool:
	var clave := _clave_arma(kind, arma_id)
	for i in range(_armas_guardadas.size() - 1, -1, -1):
		var e: Dictionary = _armas_guardadas[i]
		if String(e["clave"]) != clave:
			continue
		_armas_guardadas.remove_at(i)
		if not is_instance_valid(e["root"]) or not is_instance_valid(e["wm"]) or (e["root"] as Node).get_parent() != skeleton:
			return false
		return _usar_guardada(e)
	# ...y si no la tiene, la del ALMACEN de la partida (la que solto otro muñeco al morir)
	if almacen_activo and not _sin_almacen and skeleton != null:
		var lista: Array = _almacen.get("%s|%s" % [kind, arma_id], [])
		while not lista.is_empty():
			var e2: Dictionary = lista.pop_back()
			if not is_instance_valid(e2["root"]) or not is_instance_valid(e2["wm"]):
				continue
			if not is_equal_approx(float(e2["sx"]), scale.x) or (e2["root"] as Node).get_parent() != null:
				(e2["root"] as Node).queue_free()
				continue
			var _tal := Time.get_ticks_usec()
			skeleton.add_child(e2["root"])
			var wm2 = e2["wm"]
			wm2.skin_forzada = skin_arma_forzada   # la pintura es de quien la coge ("" = la del jugador, "-" = ninguna)
			if wm2.flash_light:
				wm2.flash_light.visible = false
			Prof.add("av.eq.almacen", Time.get_ticks_usec() - _tal)
			return _usar_guardada(e2)
	return false


## Enseña y coloca un arma ya montada (guardada en este muñeco o sacada del almacen).
func _usar_guardada(e: Dictionary) -> bool:
	var _teq := Time.get_ticks_usec()
	weapon_root = e["root"]
	weapon_root.visible = true
	_wm = e["wm"]
	_one_hand = bool(e["one_hand"])
	_arma_k = float(e["k"])
	if _wm.has_method("repintar_skin"):
		_wm.repintar_skin()
	var sombra_sola: bool = _first_person or not _body_visible
	for mi in _wm.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if sombra_sola:
			m3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		elif m3.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			m3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	grip_marker = Marker3D.new()
	grip_marker.name = "Grip"
	grip_marker.position = _wm.grip_pos * _arma_k / scale.x
	weapon_root.add_child(grip_marker)
	fore_marker = Marker3D.new()
	fore_marker.name = "Foregrip"
	fore_marker.position = _wm.foregrip_pos * _arma_k / scale.x
	weapon_root.add_child(fore_marker)
	Prof.add("av.eq.guardada", Time.get_ticks_usec() - _teq)
	_update_rifle_transform(0.0)
	_apply_arm_ik()
	_mover_parpados()
	return true


func _soltar_armas_guardadas() -> void:
	for e in _armas_guardadas:
		if is_instance_valid(e["root"]) and not _al_almacen(String(e["clave"]), e["root"], e["wm"], bool(e["one_hand"]), float(e["k"])):
			(e["root"] as Node).queue_free()
	_armas_guardadas.clear()


# --- EL ALMACEN DE ARMAS DE LA PARTIDA (2026-10-02, pedido: "muchos bots juntos peleando dan lag"; medido con --botsjuntos:
# cada bot que reaparecia montaba y horneaba su arma de cero, `av.eq.2montar` 13-16 ms). El arma del que muere no se tira:
# se descuelga y se guarda (por tipo y modelo, como mucho ALMACEN_MAX por cada uno) y el siguiente muñeco que la saque se la
# lleva tal cual, repintada con SU pintura. Solo durante la partida (main lo enciende y lo vacia al salir), y nunca el arma
# de primera persona (externa). A/B: --sinalmacenarmas.
static var almacen_activo := false
static var _almacen: Dictionary = {}     ## "tipo|modelo" -> [{root, wm, one_hand, k, sx}]
const ALMACEN_MAX := 3
static var _sin_almacen: bool = "--sinalmacenarmas" in OS.get_cmdline_user_args()


func _al_almacen(clave_skin: String, root: Node, wm: Node, one_hand: bool, k: float) -> bool:
	if not almacen_activo or _sin_almacen or root == null or not is_instance_valid(root) or wm == null or not is_instance_valid(wm):
		return false
	var partes := clave_skin.split("|")
	if partes.size() < 2 or String(partes[0]) in ["", "vacio", "escudo"]:
		return false
	var clave := "%s|%s" % [partes[0], partes[1]]
	var lista: Array = _almacen.get(clave, [])
	if lista.size() >= ALMACEN_MAX:
		return false
	for c in root.get_children():
		if c is Marker3D:
			c.queue_free()   # los puntos de agarre se rehacen al sacarla
	# EL CONTORNO ROJO NO VIAJA CON EL ARMA (2026-10-14, bug: "veo el arma de un compañero o enemigos con borde rojo sin
	# que me hayan matado"): el del que te mato (player._poner_xray) va en las mallas de su arma, y al morir el arma venia
	# aqui y la sacaba otro bot con el borde puesto
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mo = (m as MeshInstance3D).material_overlay
		if mo != null and mo.has_meta("xray"):
			(m as MeshInstance3D).material_overlay = null
	if root.get_parent():
		root.get_parent().remove_child(root)
	(root as Node3D).visible = true
	lista.append({"root": root, "wm": wm, "one_hand": one_hand, "k": k, "sx": scale.x})
	_almacen[clave] = lista
	return true


static func vaciar_almacen() -> void:
	for lista in _almacen.values():
		for e in lista:
			if is_instance_valid(e["root"]):
				(e["root"] as Node).free()
	_almacen.clear()


## Brazos en primera persona: el arma es el modelo de la cámara (WeaponPivot); aquí sólo se colocan los
## puntos de agarre y las manos siguen al arma en cada frame (también al apuntar). `swap_hands`: la mano
## del gatillo es la del lado +X del modelo.
func attach_external_weapon(weapon: Node3D, grip_local: Vector3, fore_local: Vector3, swap_hands: bool = true, one_hand: bool = false) -> void:
	weapon_root = weapon
	_external_weapon = true
	_swap_hands = swap_hands
	_one_hand = one_hand
	grip_marker = Marker3D.new()
	grip_marker.name = "GripIK"
	grip_marker.position = grip_local
	weapon.add_child(grip_marker)
	fore_marker = Marker3D.new()
	fore_marker.name = "ForegripIK"
	fore_marker.position = fore_local
	weapon.add_child(fore_marker)

## Quita el arma que sujeta el avatar (la creada por equip_weapon) y lo devuelve a su
## animación normal, sin pose de agarre. En el lobby el avatar va desarmado; sólo empuña en partida.
## Muestra u oculta el cuerpo del avatar propio, arma incluida, conservando la sombra.
## En primera persona el jugador sólo ve su sombra (SHADOWS_ONLY); en tercera se ve entero.
var _body_visible := true

## ACABADO DE LA SKIN. El color solo no basta: lo que separa el oro del amarillo es que REFLEJE.
# --- DISOLVERSE ---------------------------------------------------------------------------------
# Irse consumiendose en vez de desaparecer de golpe. Lo usan los cadaveres cuando les toca marcharse
# y el reaparecer, que es lo mismo del reves.
#
# El truco esta en que el material del avatar es SUYO, no compartido: se puede cambiar por el de
# disolver sin tocar a nadie mas. Y se guarda el original para devolverlo, porque un avatar que
# reaparece tiene que volver a ser un avatar normal, no quedarse con un shader caro puesto para
# siempre.
var _dis_mat: ShaderMaterial = null
var _huesos_lista: Array = []   ## bone_idx.keys() guardado (keys() crea un Array nuevo en cada llamada)
## EL SOMBREADO DE DISOLVER, CARGADO PARA SIEMPRE (2026-10-01, medido en duelo con bots: con `load()` cada cadaver,
## al irse el ultimo Godot soltaba el sombreado y el siguiente lo recompilaba: 5 pipelines, ~65-70 ms de tiron cada
## pocos segundos). Con preload vive lo que el script; ademas main lo precalienta al cargar el mapa.
const DISOLVER_SH := preload("res://shaders/disolver.gdshader")
const DISOLVER_RUIDO := preload("res://assets/ruido_humo_0.png")


## `k` de 0 (entero) a 1 (no queda nada). Volver a 0 devuelve el material de siempre.
func disolucion(k: float) -> void:
	k = clampf(k, 0.0, 1.0)
	if k <= 0.0001:
		if _dis_mat != null:
			_dis_mat = null
			_pintar_mallas(material)
		return
	if _dis_mat == null:
		_dis_mat = ShaderMaterial.new()
		_dis_mat.shader = DISOLVER_SH
		_dis_mat.set_shader_parameter("dissolve_texture", DISOLVER_RUIDO)
		_dis_mat.set_shader_parameter("albedo", material.albedo_color if material else Color.WHITE)
		_dis_mat.set_shader_parameter("roughness_value", 0.95)
		_pintar_mallas(_dis_mat)
	_dis_mat.set_shader_parameter("dissolve_amount", k)
	if _blob != null and is_instance_valid(_blob):
		_blob.visible = false          # desapareciendo: sin mancha en el suelo


## Todas las mallas del avatar de una vez: la del cuerpo, y lo que le cuelgue.
func _pintar_mallas(m: Material) -> void:
	_pintar_rec(self, m)


func _pintar_rec(n: Node, m: Material) -> void:
	for c in n.get_children():
		# la mancha de sombra de los pies (sombra_blob.gd) no: con la disolucion salia un cuadrado rojo en el suelo
		if c is MeshInstance3D and not c.has_meta("sin_contorno"):
			(c as MeshInstance3D).material_override = m
		if c.get_child_count() > 0:
			_pintar_rec(c, m)


## Se aplica despues de construir y solo a este avatar (su material es suyo), asi que ponerte de
## cromo no deja a los bots cromados.
func aplicar_acabado(metalico: float, rugosidad: float) -> void:
	if material == null:
		return
	material.metallic = clampf(metalico, 0.0, 1.0)
	material.roughness = clampf(rugosidad, 0.02, 1.0)
	# con metalico alto hace falta algo de reflejo especular o el modelo sale casi negro
	material.metallic_specular = 0.5 + 0.4 * clampf(metalico, 0.0, 1.0)


func set_body_visible(on: bool) -> void:
	_body_visible = on
	var mode := (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on
		else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	if mesh_inst:
		mesh_inst.cast_shadow = mode
	if weapon_root and is_instance_valid(weapon_root):
		for mi in weapon_root.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = mode
	if _esc_root and is_instance_valid(_esc_root):
		for mi in _esc_root.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = mode
	_modo_guardadas()

func unequip_weapon() -> void:
	_quitar_escudo()
	_soltar_armas_guardadas()
	if weapon_root and not _external_weapon and is_instance_valid(weapon_root) \
			and not _al_almacen(_clave_arma(weapon_kind, _arma_id), weapon_root, _wm, _one_hand, _arma_k):
		weapon_root.queue_free()
	weapon_root = null
	grip_marker = null
	fore_marker = null
	_wm = null
	weapon_kind = ""
	_arma_id = ""
	_hold_init = false

func detach_weapon() -> void:
	weapon_root = null
	grip_marker = null
	fore_marker = null
	_external_weapon = false
	# ...y olvidar QUE arma era. Si no, al reconstruirse el rig se creia que llevaba una y se
	# fabricaba una copia propia: en primera persona salia un arma pegada a la camara.
	weapon_kind = ""
	_arma_id = ""

## IK de dos huesos (hombro -> codo -> muñeca) en espacio del esqueleto. Mantiene la torsión que trae la
## animación y sólo "balancea" cada hueso hacia su objetivo (arco mínimo), así el resultado es estable.
var _ik_us_acc := 0
var _ik_frames := 0
func _apply_arm_ik() -> void:
	if not weapon_root or not grip_marker or not is_instance_valid(weapon_root) or not is_instance_valid(grip_marker):
		return
	var _t0 := Time.get_ticks_usec()
	_apply_arm_ik_inner()
	if _arms_only and "--posedbg" in OS.get_cmdline_user_args():
		_ik_us_acc += Time.get_ticks_usec() - _t0
		_ik_frames += 1
		if _ik_frames == 120:
			print("[ik-fp] media %.3f ms por frame" % (_ik_us_acc / 1000.0 / _ik_frames))
			_ik_us_acc = 0
			_ik_frames = 0

## PRIMERA PERSONA: NI MANOS NI BRAZOS. Todo eso queda pegado a la camara, encima del arma, y le
## tapaba el diseno. Se deja solo el arma, como en la mayoria de los shooters de movil.
##
## El esqueleto se sigue montando y moviendo: es el que lleva los puntos de agarre por IK y el que
## coloca el arma. Lo unico que no se dibuja es su MALLA. Tampoco se puede quitar del horneado,
## porque esa malla se comparte con el avatar de tercera persona, que si tiene brazos y manos.
## OJO ENTORNADO AL APUNTAR. El derecho (el que va al arma) se queda abierto; el izquierdo se
## entorna, como quien cierra un ojo para encarar.
##
## EL OJO SE CIERRA ENCOGIENDOSE, no tapandolo con un parpado. Antes habia una pieza aparte que
## bajaba por encima, y las dos se peleaban por el mismo sitio: al cerrarse se veia desaparecer el
## ojo blanco y aparecer el parpado de golpe. Ahora el ojo ES un hueso, anclado en su fila de
## arriba, y se aplasta hacia abajo hasta quedar en nada; debajo asoma la cara, que ya es piel.
## Una sola pieza, ningun conflicto, y el cierre sale continuo en vez de a saltos.
## Cuanto llega a cerrarse el ojo: 1 = del todo, 0,6 = entornado. Como los valores del apuntado, se
## afina en el editor de punteria viendo el gesto.
static var parpado_cierre := 0.95
## Desplazamiento fino del ojo CERRADO, en voxels (lados, arriba-abajo, delante-atras).
static var parpado_off := Vector3.ZERO


## CABEZA QUIETA AL APUNTAR. El clip de reposo mueve la cabeza y el cuello todo el rato, y con el
## arma encarada eso queda fatal: cuando apoyas la mira en el ojo la cabeza se queda clavada, es el
## arma la que sigue a la cabeza y no al reves. Ademas hacia imposible juzgar si la mira estaba en
## su sitio, porque no paraba de bailar.
##
## No se congela el hueso "a lo bruto": se acerca su pose a la de reposo segun cuanto estas
## apuntando, asi que el gesto entra y sale suave con el mismo peso que sube el arma.
func _estabilizar_cabeza() -> void:
	# con el escudo la cabeza la lleva su clip: se asoma a la ventana y se ladea para apuntar por el canto
	if _aim_w <= 0.001 or skeleton == null or escudo_activo():
		return
	for nombre in ["neck", "head"]:
		if not bone_idx.has(nombre):
			continue
		var i: int = bone_idx[nombre]
		var reposo: Transform3D = skeleton.get_bone_rest(i)
		skeleton.set_bone_pose_position(i, skeleton.get_bone_pose_position(i).lerp(reposo.origin, _aim_w))
		skeleton.set_bone_pose_rotation(i, skeleton.get_bone_pose_rotation(i).slerp(
			reposo.basis.get_rotation_quaternion(), _aim_w).normalized())


func _mover_parpados(dt: float = 0.0) -> void:
	if skeleton == null:
		return
	_estabilizar_cabeza()
	# EL PESO DE APUNTAR SE MUEVE AQUI. Antes se actualizaba dentro del calculo de la pose del arma,
	# que solo corre desde _process: cualquier otra ruta (las hojas de poses, los retratos) lo
	# dejaba clavado en 0 y ni el arma subia ni el ojo se cerraba, sin que nada fallara a la vista.
	if dt > 0.0:
		# SUBE MAS RAPIDO DE LO QUE SUBIA. A 2,6 tardaba 0,38 s en encarar del todo y los bots ya
		# habian disparado: veias el fogonazo con el arma todavia a medio subir. A 6,5 son 0,15 s.
		# Bajarla es mas lento que subirla: soltar la mira es un gesto perezoso, encararla no.
		_aim_w = move_toward(_aim_w, 1.0 if aiming else 0.0, (6.5 if aiming else 3.4) * dt)
	# solo el izquierdo: el derecho es el que mira por la mira y se queda abierto. Las dos mitades
	# de cada ojo van con el mismo peso: se cierran a la vez, una desde arriba y otra desde abajo.
	if dt > 0.0:
		_ojos_tick(dt)
	var k_ojos: float = ojos_k
	_ojo("eye_l_up", maxf(_aim_w, k_ojos))
	_ojo("eye_l_dn", maxf(_aim_w, k_ojos))
	_ojo("eye_r_up", k_ojos)
	_ojo("eye_r_dn", k_ojos)


# ---------------------------------------------------------------------------------------------------
# LOS PARPADOS AL MORIR Y AL REVIVIR (2026-10-28, pedido: "cuando alguien muere, los dos parpados se van cerrando
# lentamente; muerto, los dos ojos cerrados; y en la RCP, cuando esta a punto de resucitar, empieza a abrirlos").
# `ojos_k` 0 abiertos, 1 cerrados. Al morir lo cierra un Tween (el muñeco muerto no siempre se procesa: lo mueve el
# ragdoll) y se queda cerrado; en la RCP (rescate.gd pone `ojos_rcp` = 0..1 del avance) parpadea al final y se abre;
# vivo otra vez (drive_locomotion), se abren del todo con un parpadeo.
# ---------------------------------------------------------------------------------------------------
var ojos_k := 0.0
var ojos_rcp := -1.0                ## avance de la RCP que le hacen (0..1), -1 = ninguna
var _muerto := false
var _ojos_tw: Tween = null
var _ojos_t := 0.0
var _parpadeo_t := randf_range(0.5, 5.0)
const PARPADEO_DUR := 0.16
var _abriendo := -1.0               ## s desde que vuelve a la vida (abre con un parpadeo)

func ojos_morir() -> void:
	if _muerto:
		return
	_muerto = true
	_abriendo = -1.0
	if _ojos_tw != null and _ojos_tw.is_valid():
		_ojos_tw.kill()
	if not is_inside_tree():
		ojos_k = 1.0
		return
	_ojos_tw = create_tween()
	# primero caen a medias, un instante de pesadez, y se cierran del todo
	_ojos_tw.tween_method(_ojos_poner, ojos_k, 0.55, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_ojos_tw.tween_interval(0.25)
	_ojos_tw.tween_method(_ojos_poner, 0.55, 1.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _ojos_poner(k: float) -> void:
	ojos_k = k
	if skeleton == null:
		return
	_ojo("eye_l_up", k)
	_ojo("eye_l_dn", k)
	_ojo("eye_r_up", k)
	_ojo("eye_r_dn", k)

## De vuelta a la vida: se abren con un parpadeo (lo llama drive_locomotion y el fin de la RCP).
func ojos_vivir() -> void:
	if not _muerto:
		return
	_muerto = false
	ojos_rcp = -1.0
	if _ojos_tw != null and _ojos_tw.is_valid():
		_ojos_tw.kill()
	_abriendo = 0.0

func _ojos_tick(dt: float) -> void:
	_ojos_t += dt
	if _muerto:
		if ojos_rcp >= 0.0 and (_ojos_tw == null or not _ojos_tw.is_running()):
			# casi revivido: los parpados tiemblan, intentan abrirse y vuelven a caer, y al final se abren a medias
			var p: float = clampf(ojos_rcp, 0.0, 1.0)
			var abre: float = smoothstep(0.62, 1.0, p)
			var lucha: float = 0.0 if p < 0.55 or p > 0.97 else 0.22 * maxf(sin(_ojos_t * 7.0), 0.0) * smoothstep(0.55, 0.75, p)
			ojos_k = clampf(1.0 - abre * 0.6 - lucha, 0.0, 1.0)
		return
	# VIVO, PARPADEA (bucle de pulido): cada 2,5-6 s un parpadeo de 0,16 s, a veces doble; cada uno a su ritmo
	if _abriendo < 0.0:
		_parpadeo_t -= dt
		if _parpadeo_t <= -PARPADEO_DUR:
			_parpadeo_t = randf_range(2.5, 6.0)
			if randf() < 0.18:
				_parpadeo_t = 0.22            # el segundo de un parpadeo doble
		if _parpadeo_t < 0.0:
			var u: float = -_parpadeo_t / PARPADEO_DUR        # 0..1 del parpadeo: baja rapido, sube algo mas lento
			ojos_k = smoothstep(0.0, 0.4, u) * (1.0 - smoothstep(0.45, 1.0, u))
		else:
			ojos_k = 0.0
		return
	if _abriendo >= 0.0:
		_abriendo += dt
		# se abren en 0,35 s, un parpadeo a los 0,6 y otro a 1,1
		var k: float = 1.0 - smoothstep(0.0, 0.35, _abriendo)
		for c in [0.6, 1.1]:
			var d: float = absf(_abriendo - c)
			if d < 0.09:
				k = maxf(k, 1.0 - d / 0.09)
		ojos_k = k
		if _abriendo > 1.3:
			_abriendo = -1.0
			ojos_k = 0.0


## `k` = 0 ojo abierto, 1 ojo cerrado del todo.
func _ojo(nombre: String, k: float) -> void:
	if not bone_idx.has(nombre):
		return
	var i: int = bone_idx[nombre]
	# arranca y frena suave: no se cierra a velocidad constante
	var s: float = k * k * (3.0 - 2.0 * k)
	# `parpado_cierre` es cuanto llega a cerrarse (1 = del todo). Se deja algo por encima de cero
	# para que no desaparezca de golpe el ultimo pixel.
	var alto: float = maxf(1.0 - s * parpado_cierre, 0.02)
	# QUE EJE ES "HACIA ARRIBA". Escalando la Y del hueso el ojo se cerraba DE LADO: la Y local de
	# este hueso no apunta al cielo (el esqueleto trae sus propias orientaciones de reposo). En vez
	# de suponerlo, se mira cual de los tres ejes locales es el que mas se parece a la vertical del
	# mundo, y se aplasta ese. Asi el ojo se cierra de arriba abajo en cualquier hueso.
	var g: Basis = skeleton.get_bone_global_rest(i).basis
	var ejes := [g.x, g.y, g.z]
	var vert := 0
	var mejor := -1.0
	for j in 3:
		var d: float = absf((ejes[j] as Vector3).normalized().dot(Vector3.UP))
		if d > mejor:
			mejor = d
			vert = j
	var esc := Vector3.ONE
	esc[vert] = alto
	skeleton.set_bone_pose_scale(i, esc)
	var reposo: Vector3 = skeleton.get_bone_rest(i).origin
	skeleton.set_bone_pose_position(i, reposo + parpado_off * s * _vox_m())


## Metros que mide un voxel del modelo (el rig lo trae en `voxel_size_m`).
func _vox_m() -> float:
	return float(_shared_rig.get("voxel_size_m", 0.0257))


func _esconder_brazos_fp() -> void:
	# (al lanzar una granada si se ven: player.gd enciende `ver_brazos_fp` mientras dura el gesto)
	var ver := ver_brazos_fp or siempre_brazos_fp
	if _arms_only and mesh_inst and mesh_inst.visible != ver:
		mesh_inst.visible = ver


## Los brazos de primera persona, a la vista (solo mientras se lanza una granada)
var ver_brazos_fp := false
## SIEMPRE A LA VISTA (2026-10-11, pedido: "quiero que las manos esten en el arma, siempre visibles en primera persona").
## Lo pone player.gd; --sinbrazosfp = escondidos como antes (salvo la granada)
var siempre_brazos_fp := false


# ---------------------------------------------------------------------------------------------------
# LANZAR UNA GRANADA (2026-09-28, pedido): el arma abajo, la mano del gatillo coge la granada, la otra le
# quita la anilla, se echa atras y la tira, rapido; luego vuelve el arma. Lo mismo en primera persona
# (player.gd, con sus propias posiciones delante de la camara) y en tercera (aqui, alrededor de los
# hombros), con el MISMO reloj: LANZAR_DUR y LANZAR_SUELTA. En red lo arranca Net.net_lanzar.
# ---------------------------------------------------------------------------------------------------
const LANZAR_DUR := 0.9
const LANZAR_SUELTA := 0.52
## [t, mano del gatillo (lado, arriba, adelante), mano de apoyo] respecto al centro de los hombros
const LANZAR_TP := [
	[0.00, Vector3(0.14, -0.30, 0.25), Vector3(-0.14, -0.30, 0.25)],
	[0.14, Vector3(0.12, -0.14, 0.30), Vector3(-0.06, -0.16, 0.30)],
	[0.26, Vector3(0.08, -0.10, 0.32), Vector3(0.06, -0.02, 0.32)],
	[0.32, Vector3(0.09, -0.10, 0.32), Vector3(-0.04, -0.02, 0.30)],
	[0.40, Vector3(0.16, 0.04, 0.12), Vector3(-0.12, -0.10, 0.32)],
	[0.47, Vector3(0.20, 0.22, -0.10), Vector3(-0.10, -0.04, 0.38)],
	[0.54, Vector3(0.10, 0.18, 0.45), Vector3(-0.14, -0.22, 0.20)],
	[0.66, Vector3(0.08, -0.18, 0.36), Vector3(-0.14, -0.30, 0.18)],
	[0.80, Vector3(0.14, -0.34, 0.20), Vector3(-0.14, -0.34, 0.20)],
]
var _lanz_t := -1.0
var _lanz_arma_oculta := false
## En que punto del gesto van la granada y la anilla (lo pone el reloj de aqui en tercera persona, y player.gd en los
## brazos de primera). <0 = nada en las manos.
var lanz_prop_t := -1.0
var _lanz_granada: Node3D = null      # BoneAttachment3D en la mano del gatillo
var _lanz_anilla: Node3D = null       # BoneAttachment3D en la mano de apoyo (la anilla, ya quitada)


## Empieza el gesto (el tuyo visto desde fuera, o el de otro jugador que ha llegado por la red)
func lanzar_granada() -> void:
	if _arms_only:
		return
	_lanz_t = 0.0


## Posicion de las manos en el gesto a tiempo `t`, interpolada entre las claves (suave en cada tramo)
static func lanzar_muestra(tabla: Array, t: float) -> Array:
	if t <= float(tabla[0][0]):
		return [tabla[0][1], tabla[0][2]]
	for i in range(1, tabla.size()):
		var b: Array = tabla[i]
		if t <= float(b[0]):
			var a: Array = tabla[i - 1]
			var k: float = smoothstep(0.0, 1.0, (t - float(a[0])) / maxf(0.001, float(b[0]) - float(a[0])))
			return [(a[1] as Vector3).lerp(b[1], k), (a[2] as Vector3).lerp(b[2], k)]
	var ult: Array = tabla[tabla.size() - 1]
	return [ult[1], ult[2]]


## Cuanto mandan las manos del gesto sobre las del arma, y cuanto esta el arma escondida, a tiempo `t`
static func lanzar_pesos(t: float) -> Vector2:
	var manos := smoothstep(0.0, 0.10, t) * (1.0 - smoothstep(0.66, 0.80, t))
	var arma := smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.62, 0.90, t))
	return Vector2(manos, arma)


## La granada que se ve en la mano: cuerpo verde oliva con estrias, la cuchara y la anilla (nodo "Anilla")
static func malla_granada(escala: float = 1.0) -> Node3D:
	var n := Node3D.new()
	var cuerpo := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.026 * escala
	cm.bottom_radius = 0.028 * escala
	cm.height = 0.07 * escala
	cuerpo.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.33, 0.2)
	mat.roughness = 0.6
	cuerpo.material_override = mat
	n.add_child(cuerpo)
	for k in 3:
		var aro := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.026 * escala
		tm.outer_radius = 0.031 * escala
		aro.mesh = tm
		aro.position.y = (-0.02 + 0.02 * k) * escala
		aro.material_override = mat
		n.add_child(aro)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.62, 0.64, 0.66)
	metal.metallic = 0.8
	metal.roughness = 0.35
	var tapa := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.02, 0.022, 0.02) * escala
	tapa.mesh = bm
	tapa.position.y = 0.045 * escala
	tapa.material_override = metal
	n.add_child(tapa)
	var cuchara := MeshInstance3D.new()
	var bc := BoxMesh.new()
	bc.size = Vector3(0.008, 0.07, 0.014) * escala
	cuchara.mesh = bc
	cuchara.position = Vector3(0.03, 0.02, 0.0) * escala
	cuchara.rotation.z = -0.12
	cuchara.material_override = metal
	n.add_child(cuchara)
	var anilla := MeshInstance3D.new()
	anilla.name = "Anilla"
	var ta := TorusMesh.new()
	ta.inner_radius = 0.009 * escala
	ta.outer_radius = 0.014 * escala
	anilla.mesh = ta
	anilla.rotation.x = PI * 0.5
	anilla.position = Vector3(-0.018, 0.052, 0.0) * escala
	anilla.material_override = metal
	n.add_child(anilla)
	return n


## La granada en la palma de la mano del gatillo y, al tirar de ella, la anilla en la de apoyo. Van colgadas de los
## huesos (BoneAttachment3D): siguen al puno despues del IK. En tu propio cuerpo en primera persona, solo sombra.
func _lanzar_piezas() -> void:
	var t := lanz_prop_t
	if t < 0.0:
		if _lanz_granada:
			_lanz_granada.visible = false
		if _lanz_anilla:
			_lanz_anilla.visible = false
		return
	if skeleton == null or not bone_idx.has("hand_r") or not bone_idx.has("arm_lower_r"):
		return
	if _lanz_granada == null:
		var mano_g := "hand_l" if _swap_hands else "hand_r"
		var mano_a := "hand_r" if _swap_hands else "hand_l"
		# la escala del esqueleto: el antebrazo mide ~0,24 m de verdad
		var largo: float = skeleton.get_bone_global_rest(bone_idx["hand_r"]).origin.distance_to(
			skeleton.get_bone_global_rest(bone_idx["arm_lower_r"]).origin)
		var k := largo / 0.24
		var ba := BoneAttachment3D.new()
		ba.bone_name = mano_g
		skeleton.add_child(ba)
		var g := malla_granada(k * (1.25 if _arms_only else 1.0))
		g.position = Vector3(0.0, -largo * 0.62, largo * 0.12)
		ba.add_child(g)
		_lanz_granada = ba
		var bb := BoneAttachment3D.new()
		bb.bone_name = mano_a
		skeleton.add_child(bb)
		var solo := malla_granada(k * (1.25 if _arms_only else 1.0))
		for c in solo.get_children():
			if c.name != "Anilla":
				c.queue_free()
		solo.position = Vector3(0.0, -largo * 0.62, 0.0)
		bb.add_child(solo)
		_lanz_anilla = bb
	var ver_g := t > 0.06 and t < LANZAR_SUELTA
	var ver_a := t >= 0.28 and t < 0.66
	_lanz_granada.visible = ver_g
	_lanz_anilla.visible = ver_a
	if ver_g:
		var anilla := _lanz_granada.find_child("Anilla", true, false) as Node3D
		if anilla:
			anilla.visible = t < 0.28
	# tu cuerpo visto desde tus ojos: la granada solo da sombra (la de tus brazos de primera persona es otra)
	var modo := (GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if not _arms_only and not _body_visible
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	for pieza in [_lanz_granada, _lanz_anilla]:
		for mi in (pieza as Node).find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).cast_shadow != modo:
				(mi as MeshInstance3D).cast_shadow = modo


## Cada fotograma, en tercera persona: las munecas al gesto (encima de las del arma), el arma escondida y la
## granada en la mano hasta que se suelta
func _lanzar_tick(delta: float) -> void:
	if _lanz_t < 0.0 or skeleton == null:
		return
	_lanz_t += delta
	if _lanz_t >= LANZAR_DUR:
		_lanz_t = -1.0
		agarrar_borde(Vector3.ZERO, Vector3.ZERO, 0.0)
		if _lanz_arma_oculta and weapon_root != null and is_instance_valid(weapon_root):
			weapon_root.visible = true
		_lanz_arma_oculta = false
		lanz_prop_t = -1.0
		return
	var hd := skeleton.find_bone("shoulder_r")
	var hi := skeleton.find_bone("shoulder_l")
	if hd < 0 or hi < 0:
		return
	var p_d: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(hd).origin)
	var p_i: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(hi).origin)
	# el marco del gesto: "adelante" hacia donde mira el muneco (su -Z, medido: el arma cae por ahi) y "lado"
	# hacia el hombro de la mano del gatillo. Antes "adelante" salia de los hombros y daba la ESPALDA: el hueso
	# shoulder_r esta en el -X del muneco, y el gesto se hacia hacia atras con los brazos rotos.
	var adelante := -global_transform.basis.z
	adelante.y = 0.0
	adelante = adelante.normalized() if adelante.length() > 0.0001 else Vector3.FORWARD
	var hombro_gat := p_i if _swap_hands else p_d
	var hombro_apo := p_d if _swap_hands else p_i
	var derecha := adelante.cross(Vector3.UP)
	var lado := derecha if (hombro_gat - hombro_apo).dot(derecha) >= 0.0 else -derecha
	var centro := (p_d + p_i) * 0.5
	var m := lanzar_muestra(LANZAR_TP, _lanz_t)
	var aqui := func(v: Vector3) -> Vector3: return centro + lado * v.x + Vector3.UP * v.y + adelante * v.z
	var mano_g: Vector3 = aqui.call(m[0])
	var mano_a: Vector3 = aqui.call(m[1])
	var w := lanzar_pesos(_lanz_t)
	agarrar_borde(mano_g, mano_a, w.x, null, true)
	# el arma, fuera mientras las manos estan en la granada
	if weapon_root != null and is_instance_valid(weapon_root):
		var ocultar := w.y > 0.5
		if ocultar != _lanz_arma_oculta:
			_lanz_arma_oculta = ocultar
			weapon_root.visible = not ocultar
	lanz_prop_t = _lanz_t


# ---------------------------------------------------------------------------------------------------
# LOS GESTOS DE LAS HABILIDADES (habilidad.gd, 2026-09-28). Como el de la granada: claves [t, mano del gatillo, mano de
# apoyo] alrededor de los hombros (lado del gatillo, arriba, adelante), munecas por IK con los codos naturales y el
# arma guardada mientras las manos estan en otra cosa. Algunos se PARAN en un punto ("pausa") hasta soltar_gesto():
# el salto se queda con los brazos arriba mientras vuela, el gancho con el brazo estirado mientras tira.
# Los brazos de primera persona los mueve habilidad.gd con sus propias claves (delante de la camara); aqui solo se
# les ponen las piezas de la mano (gesto_pieza / gesto_pieza_t).
# ---------------------------------------------------------------------------------------------------
const GESTOS := {
	# (el cuerpo lo lleva el clip de Blender; estas claves son el respaldo sin clip. Duracion y pesos: los del clip, que
	# los usan tambien los brazos de primera persona)
	"punetazo": {"dur": 2.5, "entra": 0.12, "sale": [2.1, 2.45], "claves": [
		[0.00, Vector3(0.14, -0.30, 0.25), Vector3(-0.14, -0.30, 0.25)],
		[0.15, Vector3(0.16, -0.12, 0.12), Vector3(-0.08, -0.04, 0.32)],
		[0.35, Vector3(0.20, -0.10, -0.08), Vector3(-0.06, 0.00, 0.34)],
		[0.78, Vector3(0.21, -0.08, -0.12), Vector3(-0.06, 0.02, 0.34)],
		[0.86, Vector3(0.02, 0.04, 0.62), Vector3(-0.16, -0.12, 0.10)],
		[1.00, Vector3(0.04, 0.00, 0.58), Vector3(-0.16, -0.12, 0.12)],
		[1.20, Vector3(0.12, -0.22, 0.30), Vector3(-0.14, -0.26, 0.24)],
		[1.35, Vector3(0.14, -0.32, 0.22), Vector3(-0.14, -0.32, 0.22)]]},
	# (el cuerpo lo llevan los clips de Blender; estas claves son el respaldo. Pesos y pausa: los de primera persona)
	"salto": {"dur": 1.2, "entra": 0.08, "sale": [0.95, 1.2], "pausa": 0.40, "claves": [
		[0.00, Vector3(0.14, -0.30, 0.25), Vector3(-0.14, -0.30, 0.25)],
		[0.18, Vector3(0.18, -0.40, -0.10), Vector3(-0.18, -0.40, -0.10)],
		[0.28, Vector3(0.20, 0.30, 0.10), Vector3(-0.20, 0.30, 0.10)],
		[0.40, Vector3(0.14, 0.40, 0.02), Vector3(-0.30, 0.00, 0.30)],
		[0.47, Vector3(0.06, -0.60, 0.40), Vector3(-0.34, -0.20, -0.05)],
		[0.62, Vector3(0.06, -0.62, 0.38), Vector3(-0.34, -0.22, -0.05)],
		[1.20, Vector3(0.14, -0.32, 0.22), Vector3(-0.14, -0.32, 0.22)]]},
	# el gancho: la mano del gatillo apunta al garfio (se calcula cada cuadro, ver _gesto_tick); estas claves son la
	# otra mano y la ida y la vuelta
	"gancho": {"dur": 0.50, "entra": 0.10, "sale": [0.30, 0.50], "pausa": 0.14, "claves": [
		[0.00, Vector3(0.14, -0.30, 0.25), Vector3(-0.14, -0.30, 0.25)],
		[0.14, Vector3(0.10, 0.00, 0.55), Vector3(-0.12, -0.16, 0.24)],
		[0.50, Vector3(0.14, -0.32, 0.22), Vector3(-0.14, -0.32, 0.22)]]},
	# invisible: la mano de apoyo sube la muneca (el aparato) y la otra le da un toque
	"invisible": {"dur": 0.75, "entra": 0.10, "sale": [0.50, 0.75], "claves": [
		[0.00, Vector3(0.14, -0.30, 0.25), Vector3(-0.14, -0.30, 0.25)],
		[0.20, Vector3(0.12, -0.14, 0.28), Vector3(-0.04, -0.10, 0.30)],
		[0.32, Vector3(0.00, -0.08, 0.32), Vector3(-0.04, -0.10, 0.30)],
		[0.45, Vector3(0.12, -0.14, 0.28), Vector3(-0.04, -0.10, 0.30)],
		[0.75, Vector3(0.14, -0.32, 0.22), Vector3(-0.14, -0.32, 0.22)]]},
}
var _gesto := ""
var _gesto_t := -1.0
var _gesto_pausa := 0.0            ## lo que queda parado en la pausa (INF: hasta soltar_gesto)
var _gesto_punto := Vector3.ZERO   ## el gancho: a donde apunta el brazo (mundo)
var _gesto_arma_oculta := false
## La pieza de la mano: "punetazo" (el puno encendido) o "gancho" (el lanzagarfios). En tercera persona la pone el reloj
## del gesto; en los brazos de primera persona, habilidad.gd.
var gesto_pieza := ""
var gesto_pieza_t := -1.0
var _pieza_puno: Node3D = null
var _pieza_gancho: Node3D = null


# ---------------------------------------------------------------------------------------------------
# EL PUÑETAZO HECHO EN BLENDER (tools/blender/punetazo_anim.py, 2026-09-28): clip "punetazo" de CUERPO ENTERO, 2,5 s a
# 60 fps. Grita con los brazos arriba, se pone en guardia, adelanta el pie, enrosca cadera y hombros con el peso atras
# y golpea: la cadera se abre, el tronco se desenrosca y el brazo sale recto a la altura del hombro (impacto a
# PUNIO_IMPACTO). Mientras dura: la locomocion no cambia de clip, el arma se guarda y los BRAZOS SON LOS DEL CLIP
# (el IK del arma se mezcla fuera con `_punio_w`: sin eso los brazos volvian a buscar un fusil que no esta).
# ---------------------------------------------------------------------------------------------------
const PUNIO_IMPACTO := 95.0 / 60.0
var _punio_t := -1.0
var _punio_w := 0.0


## Empieza el punetazo de cuerpo entero. false si no hay clip (entonces vale el gesto de IK de siempre).
func punetazo_cuerpo() -> bool:
	if _arms_only or not has_clip("punetazo"):
		return false
	_punio_t = 0.0
	anim_speed = 1.0
	zancada = 1.0
	blend_time = 0.12
	play("punetazo", true)
	blend_time = 0.15
	return true


func punetazo_en_curso() -> bool:
	return _punio_t >= 0.0


## FUERA TODO LO DE LAS HABILIDADES (la vista del lobby, al acabar o al cambiar de habilidad): gestos, clips de cuerpo
## entero, piezas de la mano, invisibilidad y arma escondida. Sin esto el muneco se quedaba en la ultima postura.
func reset_habilidades() -> void:
	_gesto = ""
	_gesto_t = -1.0
	_gesto_pausa = 0.0
	_gesto_arma_oculta = false
	gancho_tira = false
	gesto_pieza = ""
	gesto_pieza_t = -1.0
	_punio_t = -1.0
	_punio_w = 0.0
	_salto_fase = ""
	agarrar_borde(Vector3.ZERO, Vector3.ZERO, 0.0)
	set_invisible(false)
	if weapon_root and is_instance_valid(weapon_root):
		weapon_root.visible = true
	if current_clip != "idle_1":
		blend_time = 0.25
		play("idle_1", true)
		blend_time = 0.15


# ---------------------------------------------------------------------------------------------------
# EL SALTO DEMOLEDOR HECHO EN BLENDER (tools/blender/salto_anim.py, 2026-09-28): tres clips que se encadenan.
#   salto_despegue (0,45 s)  se agacha, se estira de puntillas con los brazos al cielo y recoge las piernas; el jugador
#                            sale disparado a los SALTO_IMPULSO s
#   salto_aire (bucle)       en vuelo, el puno cargado por encima de la cabeza, mientras dure el vuelo
#   salto_golpe (1,6 s)      al tocar el suelo (salto_aterriza): superheroe, rodilla al suelo y el puno revienta el suelo
#                            a SALTO_IMPACTO; se incorpora y vuelve al fusil
# Como el punetazo: la locomocion no cambia de clip, los brazos son los del clip y el arma se guarda.
# ---------------------------------------------------------------------------------------------------
const SALTO_IMPULSO := 0.2
const SALTO_IMPACTO := 7.0 / 60.0
var _salto_fase := ""      ## "" | "despegue" | "aire" | "golpe"


func salto_cuerpo() -> bool:
	if _arms_only or not (has_clip("salto_despegue") and has_clip("salto_aire") and has_clip("salto_golpe")):
		return false
	_salto_fase = "despegue"
	anim_speed = 1.0
	zancada = 1.0
	blend_time = 0.08
	play("salto_despegue", true)
	blend_time = 0.15
	return true


## Toca el suelo: el golpe (desde el aire o, si aterriza antes de acabar el despegue, desde donde vaya)
func salto_aterriza() -> void:
	if _salto_fase == "" or not has_clip("salto_golpe"):
		return
	_salto_fase = "golpe"
	anim_speed = 1.0
	blend_time = 0.05
	play("salto_golpe", true)
	blend_time = 0.15


func saltando() -> bool:
	return _salto_fase != ""


## Cada fotograma (desde _punio_brazos): del despegue al aire, y al acabar el golpe, fuera
func _salto_tick() -> void:
	if _salto_fase == "":
		return
	var clip := {"despegue": "salto_despegue", "aire": "salto_aire", "golpe": "salto_golpe"}[_salto_fase] as String
	if current_clip != clip:
		_salto_fase = ""          # otro clip se lo ha quitado (una caida, la muerte)
		return
	if _salto_fase == "despegue" and _time >= clip_dur("salto_despegue") - 0.001:
		_salto_fase = "aire"
		blend_time = 0.06
		play("salto_aire", true)
		blend_time = 0.15
	elif _salto_fase == "golpe" and _time >= clip_dur("salto_golpe") - 0.001:
		_salto_fase = ""


## Los brazos: los del IK del arma y, encima, los del clip con el peso `_punio_w`. Y el puno encendido, con el reloj
## del clip (lo pinta _gesto_piezas).
func _punio_brazos(delta: float) -> void:
	_salto_tick()
	if _punio_t >= 0.0:
		_punio_t += delta
		if current_clip != "punetazo" or _punio_t > 3.5:
			_punio_t = -1.0          # otro clip se lo ha quitado (una caida, la muerte): se acaba aqui
	var quiere := 1.0 if _punio_t >= 0.0 and _time < clip_dur("punetazo") - 0.12 else 0.0
	if _salto_fase != "" and not (_salto_fase == "golpe" and _time >= clip_dur("salto_golpe") - 0.2):
		quiere = 1.0
	_punio_w = move_toward(_punio_w, quiere, delta * 7.0)
	if _punio_t >= 0.0:
		gesto_pieza = "punetazo"
		gesto_pieza_t = _time
	elif gesto_pieza == "punetazo" and _gesto != "punetazo" and not _arms_only:
		gesto_pieza = ""
		gesto_pieza_t = -1.0
	if _punio_w <= 0.0:
		_apply_arm_ik()
		return
	var del_clip := {}
	for hb in HUESOS_BRAZOS:
		if bone_idx.has(hb):
			del_clip[hb] = skeleton.get_bone_pose_rotation(bone_idx[hb])
	_apply_arm_ik()
	var w := smoothstep(0.0, 1.0, _punio_w)
	for hb in del_clip.keys():
		var i: int = bone_idx[hb]
		skeleton.set_bone_pose_rotation(i, skeleton.get_bone_pose_rotation(i).slerp(del_clip[hb], w))
	# el IK baja la articulacion del brazo (la posicion del hueso): con los brazos del clip, la de reposo
	for hb in ["arm_upper_l", "arm_upper_r"]:
		if bone_idx.has(hb):
			var i2: int = bone_idx[hb]
			skeleton.set_bone_pose_position(i2, skeleton.get_bone_pose_position(i2).lerp(skeleton.get_bone_rest(i2).origin, w))


func gesto(nombre: String, pausa: float = 0.0, punto: Vector3 = Vector3.ZERO) -> void:
	if _arms_only or not GESTOS.has(nombre):
		return
	_gesto = nombre
	_gesto_t = 0.0
	_gesto_pausa = pausa
	_gesto_punto = punto


func soltar_gesto() -> void:
	_gesto_pausa = 0.0


func gesto_punto(p: Vector3) -> void:
	_gesto_punto = p


static func gesto_pesos(nombre: String, t: float) -> Vector2:
	var g: Dictionary = GESTOS.get(nombre, {})
	if g.is_empty() or t < 0.0:
		return Vector2.ZERO
	var sale: Array = g["sale"]
	var manos := smoothstep(0.0, float(g["entra"]), t) * (1.0 - smoothstep(float(sale[0]), float(sale[1]), t))
	return Vector2(manos, manos)


## La palma de la mano en el mundo (la muneca y unos centimetros hacia los dedos): de ahi sale la cuerda del gancho
func mano_mundo(gatillo: bool = true) -> Vector3:
	if skeleton == null:
		return global_position + Vector3.UP * 1.3
	var n := ("hand_l" if _swap_hands else "hand_r") if gatillo else ("hand_r" if _swap_hands else "hand_l")
	if not bone_idx.has(n):
		return global_position + Vector3.UP * 1.3
	var t: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx[n])
	return t.origin - t.basis.y.normalized() * 0.06


func hombro_mundo(gatillo: bool = true) -> Vector3:
	if skeleton == null:
		return global_position + Vector3.UP * 1.3
	var n := ("shoulder_l" if _swap_hands else "shoulder_r") if gatillo else ("shoulder_r" if _swap_hands else "shoulder_l")
	if not bone_idx.has(n):
		return global_position + Vector3.UP * 1.3
	return skeleton.to_global(skeleton.get_bone_global_pose(bone_idx[n]).origin)


func _gesto_tick(delta: float) -> void:
	if _gesto_t < 0.0 or skeleton == null:
		return
	var g: Dictionary = GESTOS[_gesto]
	var pausa := float(g.get("pausa", -1.0))
	if pausa >= 0.0 and _gesto_t >= pausa and _gesto_pausa > 0.0:
		_gesto_t = pausa
		_gesto_pausa -= delta
	else:
		_gesto_t += delta
	if _gesto_t >= float(g["dur"]):
		_gesto_t = -1.0
		_gesto = ""
		agarrar_borde(Vector3.ZERO, Vector3.ZERO, 0.0)
		_gesto_arma_oculta = false
		gesto_pieza = ""
		gesto_pieza_t = -1.0
		return
	var hd := skeleton.find_bone("shoulder_r")
	var hi := skeleton.find_bone("shoulder_l")
	if hd < 0 or hi < 0:
		return
	var p_d: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(hd).origin)
	var p_i: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(hi).origin)
	var adelante := -global_transform.basis.z
	adelante.y = 0.0
	adelante = adelante.normalized() if adelante.length() > 0.0001 else Vector3.FORWARD
	var hombro_gat := p_i if _swap_hands else p_d
	var hombro_apo := p_d if _swap_hands else p_i
	var derecha := adelante.cross(Vector3.UP)
	var lado := derecha if (hombro_gat - hombro_apo).dot(derecha) >= 0.0 else -derecha
	var centro := (p_d + p_i) * 0.5
	var m := lanzar_muestra(g["claves"], _gesto_t)
	var aqui := func(v: Vector3) -> Vector3: return centro + lado * v.x + Vector3.UP * v.y + adelante * v.z
	var mano_g: Vector3 = aqui.call(m[0])
	var mano_a: Vector3 = aqui.call(m[1])
	# EL GANCHO: el brazo del gatillo estirado hacia el garfio (a 60 cm del hombro)
	if _gesto == "gancho" and _gesto_punto != Vector3.ZERO:
		var hacia := _gesto_punto - hombro_gat
		if hacia.length() > 0.1:
			var k := smoothstep(0.0, 0.14, minf(_gesto_t, 0.14))
			var suelta := 1.0 - smoothstep(0.30, 0.50, _gesto_t)
			mano_g = mano_g.lerp(hombro_gat + hacia.normalized() * 0.6, k * suelta)
			# MIENTRAS TIRA, LA OTRA MANO SE AGARRA A LA CUERDA, un palmo por debajo de la primera (antes se quedaba en
			# el pecho, como quien sujeta un vaso)
			if _gancho_w > 0.01:
				var agarre := hombro_gat + hacia.normalized() * 0.40 + (hombro_apo - hombro_gat) * 0.30
				mano_a = mano_a.lerp(agarre, _gancho_w * suelta)
	var w := gesto_pesos(_gesto, _gesto_t)
	agarrar_borde(mano_g, mano_a, w.x, null, true)
	_gesto_arma_oculta = w.y > 0.3
	gesto_pieza = _gesto if _gesto in ["punetazo", "gancho"] else ""
	gesto_pieza_t = _gesto_t


## El puno encendido (punetazo) y el lanzagarfios (gancho), colgados de la mano del gatillo. Con `gesto_pieza_t` el puno
## crece mientras se carga y revienta en el golpe.
## EL PUÑO DE ORO (2026-09-30, las laminas de concepto): un puño de cubos dorados (hab_fx.puno_dorado) que se enciende
## desde el grito, y el antebrazo que se vuelve de oro (_brillo_brazo). El SALTO DEMOLEDOR tambien lo lleva: en el aire
## (el puño cargado por encima de la cabeza) y hasta que revienta el suelo.
func _gesto_piezas() -> void:
	var t := gesto_pieza_t
	# (los brazos de primera persona van siempre al ritmo del clip: habilidad.FP)
	var clip := _punio_t >= 0.0 or _arms_only
	var ver_puno := gesto_pieza == "punetazo" and ((t > 0.4 and t < 2.12) if clip else (t > 0.1 and t < 1.05))
	# el salto: en tercera persona manda el clip; en los brazos de primera persona, habilidad.gd ("salto", pausa en 0,40
	# con el puño arriba hasta tocar el suelo). `desde_suelo`: lo que hace que toco el suelo (-1: aun en el aire)
	var en_salto := false
	var desde_suelo := -1.0
	if _salto_fase == "aire":
		en_salto = true
	elif _salto_fase == "golpe" and _time < SALTO_IMPACTO + 0.35:
		en_salto = true
		desde_suelo = _time
	elif gesto_pieza == "salto" and t > 0.26 and t < 0.40 + SALTO_IMPACTO + 0.3:
		en_salto = true
		desde_suelo = t - 0.40 if t > 0.40 else -1.0
	ver_puno = ver_puno or en_salto
	var ver_gancho := gesto_pieza == "gancho" and t >= 0.0
	if (ver_puno or ver_gancho) and skeleton != null and bone_idx.has("hand_r") and bone_idx.has("arm_lower_r"):
		var largo: float = skeleton.get_bone_global_rest(bone_idx["hand_r"]).origin.distance_to(
			skeleton.get_bone_global_rest(bone_idx["arm_lower_r"]).origin)
		var k := largo / 0.24
		var mano_g := "hand_l" if _swap_hands else "hand_r"
		if ver_puno and _pieza_puno == null:
			_pieza_puno = BoneAttachment3D.new()
			# EL PUÑO VA EN EL BRAZO QUE PEGA: los huesos _l (el derecho anatomico, el brazo de oro de "Puño de Oro").
			# En tercera persona el clip se espeja para pegar con ese (CLIPS_ESPEJO); en los brazos de primera persona
			# esa ya es la mano del gatillo (attach_external_weapon: swap_hands)
			_pieza_puno.bone_name = MANO_PUNO
			skeleton.add_child(_pieza_puno)
			# dos puños: el de oro (el puñetazo) y el de cristal (el salto); se enseña el que toque. ENCIMA DEL GUANTE: los
			# modelos no tienen mano y el guante es el final del antebrazo; su centro, en el rig, queda a (+1, -1, -0,5)
			# voxels de la muñeca (el guante de oro de "Puño de Oro": x 23,5..30,5, y 57..65, z -3..6, muñeca en 26, 62, 2)
			var rb: Basis = skeleton.get_bone_global_rest(bone_idx[MANO_PUNO]).basis
			var sobre_guante: Vector3 = rb.inverse() * Vector3(1.0, -1.0, -0.5)
			for pal in ["oro", "cristal"]:
				var n := HabFxScript.puno_dorado(k, false, pal)
				n.position = sobre_guante
				_pieza_puno.add_child(n)
		if ver_gancho and _pieza_gancho == null:
			_pieza_gancho = BoneAttachment3D.new()
			_pieza_gancho.bone_name = mano_g
			skeleton.add_child(_pieza_gancho)
			var caja := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.07, 0.16, 0.08) * k
			caja.mesh = bm
			var mm := StandardMaterial3D.new()
			mm.albedo_color = Color(0.16, 0.17, 0.19)
			mm.metallic = 0.7
			mm.roughness = 0.4
			caja.material_override = mm
			caja.position = Vector3(0.0, -largo * 0.25, 0.0)
			_pieza_gancho.add_child(caja)
			var franja := MeshInstance3D.new()
			var bf := BoxMesh.new()
			bf.size = Vector3(0.075, 0.03, 0.085) * k
			franja.mesh = bf
			var mf := StandardMaterial3D.new()
			mf.albedo_color = Color(0.35, 1.0, 0.45)
			mf.emission_enabled = true
			mf.emission = Color(0.3, 1.0, 0.4)
			mf.emission_energy_multiplier = 2.0
			franja.material_override = mf
			franja.position = Vector3(0.0, -largo * 0.25 - 0.05 * k, 0.0)
			_pieza_gancho.add_child(franja)
	var brazo := 0.0
	if _pieza_puno:
		# (tu cuerpo visto desde tus ojos no lo lleva: el puño de primera persona es el de los brazos)
		_pieza_puno.visible = ver_puno and (_arms_only or _body_visible)
		if ver_puno:
			# crece mientras se carga, tiembla, y en el golpe se hace grande y se apaga
			# con el clip: se enciende con el grito (0,45 s) y del todo en la guardia (1,5 s), revienta en el impacto
			# (1,58) y se apaga al recoger el brazo
			var c0 := 0.45 if clip else 0.12
			var c1 := 1.5 if clip else 0.8
			var gi := PUNIO_IMPACTO if clip else 0.86
			var carga := smoothstep(c0, c1, t)
			var golpe := smoothstep(gi - 0.03, gi + 0.02, t) * (1.0 - smoothstep(gi + 0.04, gi + 0.2, t))
			var apaga := 1.0 - (smoothstep(1.62, 1.85, t) if clip else smoothstep(0.95, 1.05, t))
			var tiembla := 1.0 + (sin(t * 70.0) * 0.08 if t > c1 - 0.3 and t < gi - 0.02 else 0.0)
			# EL GUANTE QUE SE HINCHA (pedido): en reposo, del tamaño del guante (1,1: lo tapa); con la carga crece hasta el
			# guantelete enorme de la lamina (1,7) pasandose un poco y temblando; aguanta el golpe; y al acabar el
			# puñetazo vuelve a su tamaño en 0,3 s y se esconde
			# (en los brazos de primera persona crece menos: a medio metro de la camara, el grande tapaba media pantalla)
			var hincha := 1.1 + (0.3 if _arms_only else 0.6) * _sale_atras(carga) + 0.035 * sin(t * 38.0) * carga * (1.0 - golpe)
			if clip:
				hincha = lerpf(hincha, 1.1, smoothstep(1.8, 2.1, t))
				apaga = 1.0 - smoothstep(1.8, 2.1, t)
			if en_salto:
				# EL SALTO: el puño lleno todo el vuelo; al tocar el suelo, el fogonazo del golpe y se apaga
				carga = 1.0
				golpe = 0.0
				apaga = 1.0
				tiembla = 1.0 + sin(Time.get_ticks_msec() * 0.05) * 0.05
				if desde_suelo >= 0.0:
					golpe = smoothstep(SALTO_IMPACTO - 0.05, SALTO_IMPACTO, desde_suelo) \
						* (1.0 - smoothstep(SALTO_IMPACTO + 0.03, SALTO_IMPACTO + 0.2, desde_suelo))
					apaga = 1.0 - smoothstep(SALTO_IMPACTO + 0.1, SALTO_IMPACTO + 0.35, desde_suelo)
			(_pieza_puno.get_node("Puno") as Node3D).visible = not en_salto
			(_pieza_puno.get_node("PunoCristal") as Node3D).visible = en_salto
			var n := _puno_activo()
			if en_salto:
				hincha = (0.8 if _arms_only else 1.1 + 0.3 * smoothstep(0.0, 1.0, carga)) - 0.3 * (1.0 - apaga)
			# (el halo, desde dentro no: a medio metro de la camara es una caja palida enorme)
			(n.get_node("Halo") as Node3D).visible = not _arms_only
			n.scale = Vector3.ONE * maxf(0.05, (hincha + 0.15 * golpe) * tiembla)
			(n.get_node("Luz") as OmniLight3D).light_energy = (0.4 + 1.8 * carga + 3.0 * golpe) * apaga
			var so := n.get_node_or_null("Solido") as GeometryInstance3D
			if so:
				so.set_instance_shader_parameter("brillo", carga + 1.5 * golpe)
			brazo = (0.25 * carga + 0.75 * carga * carga + golpe) * apaga
	_brillo_brazo(brazo, "cristal" if en_salto else "oro")
	if _pieza_gancho:
		_pieza_gancho.visible = ver_gancho
	# tu cuerpo visto desde tus ojos: solo sombra (en primera persona las lleva el muneco de los brazos)
	var modo := (GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if not _arms_only and not _body_visible
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	for pieza in [_pieza_puno, _pieza_gancho]:
		if pieza == null:
			continue
		for mi in (pieza as Node).find_children("*", "MeshInstance3D", true, false):
			var gi := mi as MeshInstance3D
			if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and gi.cast_shadow != modo:
				gi.cast_shadow = modo
		for luz in (pieza as Node).find_children("Luz", "OmniLight3D", true, false):
			(luz as OmniLight3D).visible = _arms_only or _body_visible


## La mano del puño (ver _gesto_piezas)
const MANO_PUNO := "hand_l"


## Sale y se pasa un poco antes de quedarse (0 -> 1, con un 10 % de rebote): el guante al hincharse
static func _sale_atras(x: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	var u := clampf(x, 0.0, 1.0) - 1.0
	return 1.0 + c3 * u * u * u + c1 * u * u


## El puño que se ve: el de cristal en el salto, el de oro en el puñetazo
func _puno_activo() -> Node3D:
	var c := _pieza_puno.get_node_or_null("PunoCristal") as Node3D
	if c != null and c.visible:
		return c
	return _pieza_puno.get_node("Puno") as Node3D


## Donde esta el puño en el mundo (lo siguen los cubos de la carga y la estela del salto): la pieza si se ve, si no la
## palma de esa mano
func puno_mundo() -> Vector3:
	if _pieza_puno != null and _pieza_puno.visible:
		return _puno_activo().global_position
	if skeleton == null or not bone_idx.has(MANO_PUNO):
		return global_position + Vector3.UP * 1.3
	var t: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx[MANO_PUNO])
	return t.origin - t.basis.y.normalized() * 0.06


## EL BRAZO ENCENDIDO: el material_overlay del muñeco enciende la capsula del codo al puño (hab_fx.SH_BRAZO), sea cual
## sea la skin, de oro (el puñetazo) o de cristal (el salto). Con `fuerza` 0 se quita (no cuesta nada sin usarse).
var _mat_brazo: ShaderMaterial = null

func _brillo_brazo(fuerza: float, paleta: String = "oro") -> void:
	if mesh_inst == null or skeleton == null:
		return
	if fuerza <= 0.01 or not (_arms_only or _body_visible):
		if _mat_brazo != null and mesh_inst.material_overlay == _mat_brazo:
			mesh_inst.material_overlay = null
		return
	var mano := MANO_PUNO
	var codo := MANO_PUNO.replace("hand", "arm_lower")
	if not bone_idx.has(mano) or not bone_idx.has(codo):
		return
	if _mat_brazo == null:
		_mat_brazo = HabFxScript.material_brazo()
	var pm: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(bone_idx[mano]).origin)
	var pc: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(bone_idx[codo]).origin)
	var puno := pm
	if _pieza_puno and _pieza_puno.visible:
		puno = _puno_activo().global_position
	var tintes: Array = HabFxScript.tintes_brazo(paleta)
	_mat_brazo.set_shader_parameter("tinte_a", tintes[0])
	_mat_brazo.set_shader_parameter("tinte_b", tintes[1])
	var largo := maxf(0.02, pm.distance_to(pc))
	_mat_brazo.set_shader_parameter("pa", pc + (pc - pm) * 0.3)
	_mat_brazo.set_shader_parameter("pb", puno)
	_mat_brazo.set_shader_parameter("radio", largo * 0.6)
	_mat_brazo.set_shader_parameter("vox", largo * 0.16)
	_mat_brazo.set_shader_parameter("fuerza", clampf(fuerza, 0.0, 1.6))
	if mesh_inst.material_overlay != _mat_brazo:
		mesh_inst.material_overlay = _mat_brazo


# ---------------------------------------------------------------------------------------------------
# INVISIBLE (habilidad.gd): todo el muneco -cuerpo, arma, colgadas, escudo- con un material que solo DISTORSIONA lo
# que hay detras (como el camuflaje de Predator) y un filo azul muy tenue. Sin sombra. Se deshace dejando cada malla
# como estaba. El propio jugador se ve con mas filo (sabe donde tiene las manos).
# ---------------------------------------------------------------------------------------------------
const SOMBREADO_INVISIBLE := """
shader_type spatial;
render_mode blend_mix, unshaded, cull_back, depth_draw_opaque;
uniform sampler2D pantalla : hint_screen_texture, filter_linear;   // (sin mipmaps: solo se lee el nivel 0; 2026-10-10)
uniform float filo = 0.25;
uniform vec4 color_filo : source_color = vec4(0.55, 0.85, 1.0, 1.0);
void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	vec2 ola = vec2(sin(TIME * 3.1 + VERTEX.y * 18.0), cos(TIME * 2.3 + VERTEX.x * 15.0)) * 0.004;
	vec3 fondo = textureLod(pantalla, SCREEN_UV + NORMAL.xy * 0.03 + ola, 0.0).rgb;
	ALBEDO = mix(fondo, color_filo.rgb, clamp(fres * filo, 0.0, 1.0));
	ALPHA = 0.98;
}
"""
## EN LOS MENUS (2026-10-03, pedido: "al PROBAR la invisibilidad se ve horrible, no como en el juego"): la de la partida
## dibuja lo que hay DETRAS (la pantalla) torcido, y en la vista de un menu detras no hay nada (el fondo es transparente
## y lo pone la interfaz por debajo): salia una silueta negra. Esta es cristal de verdad: casi transparente, el filo cian
## y las mismas ondas, y la interfaz se ve a traves. Escribe profundidad para no ver las piezas de dentro del cuerpo.
const SOMBREADO_INVISIBLE_MENU := """
shader_type spatial;
render_mode blend_mix, unshaded, cull_back, depth_draw_always;
uniform vec4 color_filo : source_color = vec4(0.55, 0.85, 1.0, 1.0);
void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float ola = 0.5 + 0.5 * sin(TIME * 3.1 + VERTEX.y * 18.0 + VERTEX.x * 9.0);
	ALBEDO = mix(vec3(0.78, 0.92, 1.0), color_filo.rgb, clamp(fres * 1.3, 0.0, 1.0));
	ALPHA = clamp(0.05 + 0.07 * ola + fres * 0.8, 0.0, 0.92);
}
"""
static var _mat_invisible_menu: ShaderMaterial = null
static var _mat_invisible: ShaderMaterial = null
static var _mat_invisible_propio: ShaderMaterial = null
var invisible := false
var _invis_propio := false
var _invis_guardado: Dictionary = {}     ## id de la malla -> [la malla, su material_override, su sombra]
var _invis_t := 0.0


static func material_invisible(propio: bool) -> ShaderMaterial:
	if _mat_invisible == null:
		var sh := Shader.new()
		sh.code = SOMBREADO_INVISIBLE
		_mat_invisible = ShaderMaterial.new()
		_mat_invisible.shader = sh
		_mat_invisible.set_shader_parameter("filo", 0.22)
		_mat_invisible_propio = ShaderMaterial.new()
		_mat_invisible_propio.shader = sh
		_mat_invisible_propio.set_shader_parameter("filo", 0.9)
	return _mat_invisible_propio if propio else _mat_invisible


var _invis_menu := false

## `menu`: la vista de un menu (personaje_pantalla, habilidades): el cristal sin pantalla detras
func set_invisible(on: bool, propio: bool = false, menu: bool = false) -> void:
	if on == invisible:
		return
	invisible = on
	if on:
		_invis_propio = propio
		_invis_menu = menu
		_invis_aplicar()
	else:
		for k in _invis_guardado.keys():
			var e: Array = _invis_guardado[k]
			var mi = e[0]
			if is_instance_valid(mi):
				(mi as MeshInstance3D).material_override = e[1]
				# LA SOMBRA NO SE DEVUELVE (2026-10-03, bug: "en tercera persona se me acaba la invisibilidad y mi personaje no
				# aparece"): la invisibilidad no la toca, y devolver la de cuando empezo pisaba el cambio de vista: invisible en
				# primera persona (el cuerpo "solo sombra") y luego a tercera, al acabar volvia a "solo sombra" y no se veia
		_invis_guardado.clear()


## Las mallas nuevas (cambiar de arma, recoger algo) tambien: se repasa cada cuarto de segundo
func _invis_aplicar() -> void:
	var mat := material_invisible(_invis_propio)
	if _invis_menu:
		if _mat_invisible_menu == null:
			var sh := Shader.new()
			sh.code = SOMBREADO_INVISIBLE_MENU
			_mat_invisible_menu = ShaderMaterial.new()
			_mat_invisible_menu.shader = sh
		mat = _mat_invisible_menu
	for mi in find_children("*", "MeshInstance3D", true, false):
		var k := (mi as Object).get_instance_id()
		if _invis_guardado.has(k):
			continue
		# la sombra NO se toca: el material es transparente y ya no la da; y una malla "solo sombra" (tu cuerpo visto
		# desde tus ojos) pasada a OFF se DIBUJABA: salia tu fantasma delante de la camara
		_invis_guardado[k] = [mi, (mi as MeshInstance3D).material_override, (mi as MeshInstance3D).cast_shadow]
		(mi as MeshInstance3D).material_override = mat


# ------------------------------------------------------------------ EL NANOTRAJE (2026-10-03, el Specter)
## El brillo del traje encima del muñeco (shaders/nanotraje_cuerpo.gdshader, como material_overlay de cada malla): el
## BLINDAJE puesto (hexagonos y filo azul acero) y el BARRIDO de luz de pies a cabeza al encender el blindaje, al volverse
## invisible o al hacer el super salto. Lo ven todos (habilidad.recibir lo pone en las copias de red).
const TRAJE_SH := preload("res://shaders/nanotraje_cuerpo.gdshader")
const TRAJE_ACERO := Color(0.35, 0.74, 1.0)    ## celeste (mas azul que el acero de antes: se notaba poco)
const TRAJE_CIAN := Color(0.35, 0.9, 1.0)
var _traje_mat: ShaderMaterial = null
var _traje_blindaje := false
var _traje_fuerza := 0.0
var _traje_barrido := -1.0
var _traje_puestas: Dictionary = {}      ## id -> malla con el brillo puesto
var _traje_repaso := 0.0


func set_blindaje(on: bool) -> void:
	if on == _traje_blindaje:
		return
	_traje_blindaje = on
	traje_barrido(TRAJE_ACERO if on else TRAJE_CIAN)


func traje_barrido(col: Color) -> void:
	if _traje_mat == null:
		_traje_mat = ShaderMaterial.new()
		_traje_mat.shader = TRAJE_SH
	_traje_mat.set_shader_parameter("color", col)
	_traje_barrido = 0.0
	_traje_poner()


func _traje_poner() -> void:
	for mi in find_children("*", "MeshInstance3D", true, false):
		var k := (mi as Object).get_instance_id()
		if _traje_puestas.has(k):
			continue
		if (mi as MeshInstance3D).material_overlay != null:
			continue                  # ya lleva otro brillo (el brazo de oro)
		(mi as MeshInstance3D).material_overlay = _traje_mat
		_traje_puestas[k] = mi


func _traje_quitar() -> void:
	for k in _traje_puestas.keys():
		var mi = _traje_puestas[k]
		if is_instance_valid(mi) and (mi as MeshInstance3D).material_overlay == _traje_mat:
			(mi as MeshInstance3D).material_overlay = null
	_traje_puestas.clear()


func _traje_tick(delta: float) -> void:
	if _traje_mat == null:
		return
	_traje_fuerza = move_toward(_traje_fuerza, 1.0 if _traje_blindaje else 0.0, delta * 3.0)
	if _traje_barrido >= 0.0:
		_traje_barrido += delta / 0.7
		if _traje_barrido >= 1.0:
			_traje_barrido = -1.0
			if _traje_blindaje:
				_traje_mat.set_shader_parameter("color", TRAJE_ACERO)
	if _traje_fuerza <= 0.001 and _traje_barrido < 0.0:
		if not _traje_puestas.is_empty():
			_traje_quitar()
		return
	_traje_repaso -= delta
	if _traje_repaso <= 0.0:
		_traje_repaso = 0.25            # las mallas nuevas (cambiar de arma) tambien
		_traje_poner()
	_traje_mat.set_shader_parameter("fuerza", _traje_fuerza)
	_traje_mat.set_shader_parameter("barrido", _traje_barrido)
	_traje_mat.set_shader_parameter("base_y", global_position.y)


func _invis_tick(delta: float) -> void:
	if not invisible:
		return
	_invis_t -= delta
	if _invis_t <= 0.0:
		_invis_t = 0.25
		_invis_aplicar()


## AGARRARSE A UN BORDE (player.gd, _trepar): las dos munecas van a dos puntos del MUNDO, encima de
## lo que diga el arma. Con peso 0 no hace nada. Vale para los brazos de primera persona y el cuerpo.
var manos_borde_w := 0.0
var _mano_borde_gatillo := Vector3.ZERO
var _mano_borde_apoyo := Vector3.ZERO

## `marco`: si se da, los dos puntos van en SUS coordenadas y se pasan al mundo al resolver el brazo (la granada en
## primera persona los da respecto a la camara: asi siguen a la vista aunque se gire entre dos pasos de fisica)
var _borde_marco: Node3D = null

## `codos_naturales`: los codos abajo, un poco afuera y atras (lanzar la granada). Sin eso siguen el iman de sujetar el
## fusil, que los abre hacia los lados: con las manos en otra parte, el codo se veia roto.
var _borde_codos := false

func agarrar_borde(gatillo_mundo: Vector3, apoyo_mundo: Vector3, peso: float, marco: Node3D = null, codos_naturales := false) -> void:
	manos_borde_w = clampf(peso, 0.0, 1.0)
	_mano_borde_gatillo = gatillo_mundo
	_mano_borde_apoyo = apoyo_mundo
	_borde_marco = marco
	_borde_codos = codos_naturales


## Hacia donde dobla el codo de un brazo suelto: abajo, algo afuera (del lado de su hombro) y algo atras. En el
## espacio del esqueleto, donde delante es -Z (ver ELBOW_MAGNET_R).
func _iman_codo_natural(hombro: String) -> Vector3:
	var s: Vector3 = skeleton.get_bone_global_pose(bone_idx[hombro]).origin
	var centro: Vector3 = skeleton.get_bone_global_pose(bone_idx["neck"]).origin if bone_idx.has("neck") else Vector3.ZERO
	var afuera := signf(s.x - centro.x)
	return s + Vector3(afuera * 0.45, -1.0, 0.25).normalized() * 20.0

## Lo que mide el brazo desde el hombro hasta la muneca (en el espacio del esqueleto)
const BRAZO_ALCANCE_FP := 0.85
## ...y por arma, cuando la de todas no basta (2026-10-12, pedido: la compacta "un poquito mas abajo")
const APOYO_BAJA_ARMA := {"smg_compacta": 0.09}
static var APOYO_BAJA_FP: float = (func() -> float:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--apoyobaja="):
			return float(String(a).substr(12))
	return 0.06).call()
var _largos_brazo := {}
func _largo_brazo(hombro: String) -> float:
	if _largos_brazo.has(hombro):
		return float(_largos_brazo[hombro])
	var lado := hombro.substr(hombro.length() - 1)
	var l := 0.0
	for b in ["arm_upper_" + lado, "arm_lower_" + lado, "hand_" + lado]:
		if bone_idx.has(b):
			l += skeleton.get_bone_rest(bone_idx[b]).origin.length()
	_largos_brazo[hombro] = l
	return l

## Lleva los hombros de primera persona a sus esquinas (hombro_libre / hombro_gatillo), o los devuelve a su sitio.
func _mover_hombros(grip_t := Vector3.INF, fore_t := Vector3.INF) -> void:
	if not (bone_idx.has("shoulder_l") and bone_idx.has("shoulder_r")):
		return
	if _arms_only:
		for nb2 in ["arm_lower_l", "arm_lower_r"]:
			if bone_idx.has(nb2):
				var esc := Vector3(grosor_fp, 1.0, grosor_fp)
				if skeleton.get_bone_pose_scale(bone_idx[nb2]) != esc:
					skeleton.set_bone_pose_scale(bone_idx[nb2], esc)
	var w := hombros_w if hombro_libre != Vector3.ZERO else 0.0
	if w <= 0.001:
		if _hombros_movidos:
			for nb in _hombros_reposo:
				skeleton.set_bone_pose_position(bone_idx[nb], _hombros_reposo[nb])
			_hombros_movidos = false
		return
	var libre: String = "shoulder_r" if _swap_hands else "shoulder_l"
	var gat: String = "shoulder_l" if _swap_hands else "shoulder_r"
	# (la mano libre de la carrera va a mano_libre, no al arma)
	var obj_libre: Vector3 = skeleton.to_local(mano_libre) if mano_libre_w > 0.5 else fore_t
	for par in [[libre, hombro_libre, obj_libre], [gat, hombro_gatillo, grip_t]]:
		var nb: String = par[0]
		var bi: int = bone_idx[nb]
		if not _hombros_reposo.has(nb):
			_hombros_reposo[nb] = skeleton.get_bone_pose_position(bi)
		if (par[1] as Vector3) == Vector3.ZERO:
			continue
		var padre := skeleton.get_bone_parent(bi)
		var g_padre: Transform3D = skeleton.get_bone_global_pose(padre) if padre >= 0 else Transform3D()
		var p_esq: Vector3 = skeleton.to_local(par[1])
		# QUE LA MANO LLEGUE (2026-10-12, pedido: "la mano izquierda flota, no toca el arma"; medido: 15-35 cm en todas las
		# armas largas): si desde la esquina el brazo no alcanza su objetivo, el hombro se acerca a el lo justo
		var obj: Vector3 = par[2]
		if obj.is_finite():
			var largo := _largo_brazo(nb)
			if largo > 0.0 and p_esq.distance_to(obj) > largo * BRAZO_ALCANCE_FP:
				p_esq = obj + (p_esq - obj).normalized() * largo * BRAZO_ALCANCE_FP
		var quiero: Vector3 = g_padre.affine_inverse() * p_esq
		skeleton.set_bone_pose_position(bi, (_hombros_reposo[nb] as Vector3).lerp(quiero, w))
	_hombros_movidos = true


func _apply_arm_ik_inner() -> void:
	var grip_t: Vector3
	var fore_t: Vector3
	if _external_weapon:
		grip_t = skeleton.to_local(grip_marker.global_position)
		fore_t = skeleton.to_local(fore_marker.global_position)
	else:
		var wt := weapon_root.transform
		grip_t = wt * grip_marker.position
		fore_t = wt * fore_marker.position
	# LA PISTOLA, A DOS MANOS (pedido): la de apoyo abraza la del gatillo (PISTOLA_APOYO), en vez de colgar
	if _one_hand and not escudo_activo():
		if _external_weapon:
			var gb: Basis = grip_marker.global_transform.basis.orthonormalized()
			fore_t = skeleton.to_local(grip_marker.global_position + gb * PISTOLA_APOYO)
		else:
			fore_t = weapon_root.transform * (grip_marker.position + PISTOLA_APOYO / maxf(scale.x, 0.0001))
	# encarada y por delante del pecho, la mano de apoyo se desliza por el arma hasta donde llega (_apoyo_al_alcance)
	elif not _external_weapon and (not sin_despeje or (EMPUNADURA_PECHO > 0.0 and (_dbg_aim_ef > 0.001 or _en_guardia_menu))) and HOLD_ALIAS.get(weapon_kind, weapon_kind) in DESPEJE_TIPOS:
		fore_t = _apoyo_al_alcance(grip_t, fore_t)
	_esconder_brazos_fp()
	# ESCUDO: las dos munecas donde las lleva la animacion de Blender (la derecha en la pistola, la
	# izquierda en el asa, o sueltas en la recarga y la rotura), ya giradas con la mirada
	if escudo_activo():
		grip_t = _esc_mano_der
		fore_t = _esc_mano_izq
	# ANDAR CON EL FUSIL DE BLENDER (_aplicar_pista_arma): las munecas donde las lleva el ciclo, no en los
	# puntos de agarre del modelo, y los codos doblando hacia donde los dobla el ciclo
	var iman_gat := ELBOW_MAGNET_R
	var iman_apo := ELBOW_MAGNET_L
	var w_pista := 0.0
	# los CODOS y el giro de las manos siguen al clip aunque las munecas se claven en el canto: colgado de
	# un borde los codos tiemblan y apuntan donde se animaron, no al iman de sujetar el arma
	var w_iman := 0.0
	if _pista_w > 0.0 and not _external_weapon and not _pista.is_empty():
		w_iman = _pista_w * (1.0 - smoothstep(0.0, 1.0, _caida_w))
		w_pista = w_iman * (1.0 - smoothstep(0.0, 1.0, manos_borde_w))
		var wp := weapon_root.transform
		grip_t = grip_t.lerp(wp * (_pista["gat"] as Vector3), _pista_w)
		fore_t = fore_t.lerp(wp * (_pista["apo"] as Vector3), _pista_w)
		var cuello: Vector3 = skeleton.get_bone_global_pose(bone_idx["neck"]).origin
		# EL CODO DEL GATILLO, MAS BAJO (2026-09-23, "el codo lo veo raro"): el de la pista del clip lo subia casi a la
		# altura del hombro y muy abierto (ala de pollo). Se baja ~15 cm y se mete un poco hacia el cuerpo.
		iman_gat = ELBOW_MAGNET_R.lerp(cuello + (_pista["cgat"] as Vector3) + CODO_GAT_BAJA, w_iman)
		iman_apo = ELBOW_MAGNET_L.lerp(cuello + (_pista["capo"] as Vector3), w_iman)
	# RECARGA ANIMADA: la mano de apoyo suelta el guardamanos y va al cargador, al portacargador y a la manija
	if _recarga_w > 0.0 and not _external_weapon:
		fore_t = fore_t.lerp(_recarga_mano, smoothstep(0.0, 1.0, _recarga_w))
	# CAIDA: las dos manos sueltan el arma y van al suelo, a la rodilla y de vuelta
	if _caida_w > 0.0 and not _external_weapon:
		var wc := smoothstep(0.0, 1.0, _caida_w)
		grip_t = grip_t.lerp(_caida_grip, wc)
		fore_t = fore_t.lerp(_caida_fore, wc)
	# LIMPIARSE LA CARA. La mano de apoyo (la que no lleva el gatillo) sube y cruza por delante de
	# los ojos, de un lado al otro. Se hace sustituyendo su objetivo de IK en vez de escribir una
	# pose: asi el codo y el hombro los coloca la misma cadena de siempre y el brazo se dobla solo.
	if _limpia_t > 0.0 and bone_idx.has("head"):
		var w: float = _limpia_peso()
		var b: float = _limpia_barrido()
		var cabeza: Vector3 = skeleton.get_bone_global_pose(bone_idx["head"]).origin
		# entra por fuera, roza la cara en el centro del recorrido y sale por el otro lado
		var lado: float = lerpf(1.0, -1.0, b)
		var roce: float = sin(b * PI)
		# POR DELANTE DE LA CARA, no dentro. El ojo esta a z -4,5 en este esqueleto, asi que a -4 el
		# antebrazo atravesaba el craneo: se adelanta a -11, un palmo por delante del morro.
		fore_t = fore_t.lerp(cabeza + Vector3(lado * 9.0, -1.0 + 1.5 * roce, -11.0 - 2.0 * roce), w)
	# VENDARSE: el antebrazo de apoyo cruzado delante del pecho y la otra mano dando vueltas con la venda
	if _venda_t > 0.0 and bone_idx.has("head"):
		var wv: float = _venda_peso()
		var kv: float = 1.0 - (_venda_t / _venda_dur)
		# RESPECTO A LA CABEZA, como limpiarse: un palmo por debajo de los ojos y por delante, que se VEA en
		# primera persona (colgado del cuello quedaba por debajo de la camara y solo asomaba un codo)
		var cabeza_v: Vector3 = skeleton.get_bone_global_pose(bone_idx["head"]).origin
		var brazo_v: Vector3 = cabeza_v + Vector3(-2.5, -7.0, -12.0)
		var ang: float = kv * TAU * 4.0
		var giro := Vector3(4.0, cos(ang) * 2.2, -sin(ang) * 2.2)
		if _swap_hands:
			grip_t = grip_t.lerp(brazo_v, wv)
			fore_t = fore_t.lerp(brazo_v + Vector3(-giro.x, giro.y, giro.z), wv)
		else:
			fore_t = fore_t.lerp(brazo_v, wv)
			grip_t = grip_t.lerp(brazo_v + giro, wv)
	# TREPAR: las dos manos al canto, aunque el arma sea de una mano
	# (la pistola ya va siempre a dos manos: solo el escudo, que lleva su propia animacion, decide aparte)
	var una_mano := _one_hand and escudo_activo() and _recarga_w <= 0.0 and _venda_t <= 0.0
	# LA PISTOLA A UNA MANO EN LA ARMERIA (2026-10-12, pedido con captura: "a dos manos se deforman; que la sujete solo la
	# derecha"): la de apoyo no va al arma y se queda en su pose de reposo
	if _en_guardia_menu and _one_hand and pistola_una_mano_menu:
		una_mano = true
	if manos_borde_w > 0.0:
		var wb := smoothstep(0.0, 1.0, manos_borde_w)
		var bg := _mano_borde_gatillo
		var ba := _mano_borde_apoyo
		if _borde_marco != null and is_instance_valid(_borde_marco):
			bg = _borde_marco.to_global(bg)
			ba = _borde_marco.to_global(ba)
		grip_t = grip_t.lerp(skeleton.to_local(bg), wb)
		fore_t = fore_t.lerp(skeleton.to_local(ba), wb)
		una_mano = false
	var iman_l := ELBOW_MAGNET_L
	var iman_r := ELBOW_MAGNET_R
	# LA GUARDIA DE ESCAPARATE (2026-09-30, pedido con captura: "el codo derecho se mete muy adentro, sale del hombro
	# y se tuerce hacia adentro, y la mano sobresale del arma"). Con el arma baja, los imanes de los codos de la partida
	# (y los de la pista del clip, pensados para el arma al pecho) dejaban el codo del gatillo por DENTRO de la
	# empuñadura: el antebrazo apuntaba hacia fuera y el puño asomaba por detras del arma. En la guardia los dos codos
	# cuelgan como los de un brazo suelto: abajo, algo afuera y algo atras (_iman_codo_natural).
	if _en_guardia_menu and bone_idx.has("shoulder_l") and bone_idx.has("shoulder_r"):
		iman_gat = _iman_codo_natural("shoulder_r")
		iman_apo = _iman_codo_natural("shoulder_l")
		iman_r = iman_gat
		iman_l = iman_apo
	if manos_borde_w > 0.0 and _borde_codos and bone_idx.has("shoulder_l") and bone_idx.has("shoulder_r"):
		var wc := smoothstep(0.0, 1.0, manos_borde_w)
		var nat_l := _iman_codo_natural("shoulder_l")
		var nat_r := _iman_codo_natural("shoulder_r")
		iman_l = iman_l.lerp(nat_l, wc)
		iman_r = iman_r.lerp(nat_r, wc)
		iman_gat = iman_gat.lerp(nat_r, wc)
		iman_apo = iman_apo.lerp(nat_l, wc)
	# LA MANO DE APOYO, POR DEBAJO DEL ARMA (2026-10-12, pedido: "a veces la mano izquierda tapa el arma, que no este mas
	# arriba que el arma"): en primera persona su punto se baja APOYO_BAJA_FP por el "abajo" del arma, asi la mano agarra
	# el guardamanos desde abajo. --apoyobaja=m
	if _arms_only and _external_weapon and fore_marker and not _one_hand and APOYO_BAJA_FP > 0.0 and mano_libre_w < 0.5:
		var abajo_a: Vector3 = -(fore_marker.global_transform.basis.y.normalized())
		var id_arma: String = String(weapon_root.get("arma_id")) if weapon_root and "arma_id" in weapon_root else ""
		fore_t = skeleton.to_local(skeleton.to_global(fore_t) + abajo_a * float(APOYO_BAJA_ARMA.get(id_arma, APOYO_BAJA_FP)))
	# LA MANO DEL GATILLO, TAMBIEN POR DEBAJO (2026-10-12, pedido: "la mano derecha se ve muy arriba y me tapa el arma", en
	# la metralleta y la pistola): en primera persona la muñeca baja GATILLO_BAJA_FP por el "abajo" del arma y la mano agarra
	# la empuñadura desde abajo. --gatillobaja=m (0 = como antes)
	if _arms_only and gatillo_extra_w > 0.001:
		grip_t = grip_t.lerp(skeleton.to_local(skeleton.to_global(grip_t) + gatillo_extra), gatillo_extra_w)
	if _arms_only and _external_weapon and grip_marker and _gatillo_baja() > 0.0:
		var abajo_g: Vector3 = -(grip_marker.global_transform.basis.y.normalized())
		# (la pistola, mas: la mano se comia la corredera; pedido 2026-10-13)
		var k_arma: String = String(weapon_root.get("kind")) if weapon_root and "kind" in weapon_root else weapon_kind
		var baja_g: float = _gatillo_baja() + (GATILLO_BAJA_PISTOLA if k_arma == "pistol" else 0.0)
		grip_t = skeleton.to_local(skeleton.to_global(grip_t) + abajo_g * baja_g)
	_mover_hombros(grip_t, fore_t)
	if mano_libre_w > 0.001 and bone_idx.has("shoulder_l") and bone_idx.has("shoulder_r"):
		fore_t = fore_t.lerp(skeleton.to_local(mano_libre), mano_libre_w)
		una_mano = false
	var wc: float = maxf(hombros_w, mano_libre_w)
	if wc > 0.001 and bone_idx.has("shoulder_l") and bone_idx.has("shoulder_r"):
		var cl: Vector3 = skeleton.to_local(codo_libre) if codo_libre != Vector3.ZERO else _iman_codo_natural("shoulder_r" if _swap_hands else "shoulder_l")
		var cg: Vector3 = skeleton.to_local(codo_gatillo) if codo_gatillo != Vector3.ZERO else Vector3.ZERO
		if _swap_hands:
			iman_r = iman_r.lerp(cl, wc)
			if cg != Vector3.ZERO:
				iman_l = iman_l.lerp(cg, wc)
		else:
			iman_apo = iman_apo.lerp(cl, wc)
			if cg != Vector3.ZERO:
				iman_gat = iman_gat.lerp(cg, wc)
	# EL CODO DE APOYO, FUERA DEL PECHO AL APUNTAR (2026-10-11, bug: "la mano izquierda no agarra el arma y al apuntar se
	# le mete en el cuerpo"): encarada, el arma sube a la cara y el iman fijo del codo de apoyo quedaba por DENTRO de la
	# linea del brazo, asi que el codo doblaba hacia el torso y el antebrazo cruzaba el pecho. Apuntando se lleva hacia el
	# de un brazo suelto (abajo, afuera y atras), en la proporcion en que se encara. --codoapoyo=K (0 = como antes).
	if not _en_guardia_menu and _dbg_aim_ef > 0.001 and _codo_apoyo_k > 0.0 and bone_idx.has("shoulder_l") and bone_idx.has("shoulder_r"):
		var ka: float = clampf(_dbg_aim_ef * _codo_apoyo_k, 0.0, 1.0)
		if _swap_hands:
			iman_r = iman_r.lerp(_iman_codo_natural("shoulder_r"), ka)
		else:
			iman_apo = iman_apo.lerp(_iman_codo_natural("shoulder_l"), ka)
	if _swap_hands:
		_solve_arm("shoulder_l", "arm_upper_l", "arm_lower_l", "hand_l", grip_t, iman_l)
		if not una_mano:
			_solve_arm("shoulder_r", "arm_upper_r", "arm_lower_r", "hand_r", fore_t, iman_r)
	else:
		_solve_arm("shoulder_r", "arm_upper_r", "arm_lower_r", "hand_r", grip_t, iman_gat)
		if not una_mano:
			_solve_arm("shoulder_l", "arm_upper_l", "arm_lower_l", "hand_l", fore_t, iman_apo)
		# EL PUÑO SOBRE EL ARMA, NO DELANTE (guardia de escaparate): el guante va unos 5 voxels mas alla del hueso de la
		# muñeca, y con la muñeca en el guardamanos el puño asomaba por delante del arma ("la mano sobresale del arma").
		# Se echa la muñeca atras, a lo largo del antebrazo que acaba de salir, y se vuelve a resolver.
		if _en_guardia_menu:
			var atras_g: Vector3 = grip_t - (grip_t - skeleton.get_bone_global_pose(bone_idx["arm_lower_r"]).origin).normalized() * GUARDIA_PUNO
			_solve_arm("shoulder_r", "arm_upper_r", "arm_lower_r", "hand_r", atras_g, iman_gat)
			if not una_mano:
				var atras_f: Vector3 = fore_t - (fore_t - skeleton.get_bone_global_pose(bone_idx["arm_lower_l"]).origin).normalized() * GUARDIA_PUNO
				_solve_arm("shoulder_l", "arm_upper_l", "arm_lower_l", "hand_l", atras_f, iman_apo)
		if w_iman > 0.0:
			var w_limpia: float = _limpia_peso() if _limpia_t > 0.0 else 0.0
			_girar_manos_pista(w_iman, 0.0 if una_mano else
				w_iman * (1.0 - smoothstep(0.0, 1.0, _recarga_w)) * (1.0 - w_limpia))

## Cadena hombro -> (brazo superior rígido con el hombro) -> antebrazo -> muñeca. El primer segmento es el
## hombro+brazo superior: el deltoides (voxels del hueso "shoulder") gira con el brazo y el brazo no se
## despega del cuerpo. En reposo los cuatro huesos están casi alineados, así que el segmento es recto.
func _solve_arm(shoulder: String, upper: String, lower: String, hand: String, target: Vector3, magnet: Vector3) -> void:
	if not (bone_idx.has(shoulder) and bone_idx.has(upper) and bone_idx.has(lower) and bone_idx.has(hand)):
		return
	var ish: int = bone_idx[shoulder]
	var iu: int = bone_idx[upper]
	var il: int = bone_idx[lower]
	# brazo superior recto respecto al hombro (pose de reposo)
	skeleton.set_bone_pose_rotation(iu, _shared_bind.get(upper, Quaternion.IDENTITY))
	# EL HOMBRO SOLO ACOMPAÑA (2026-09-23, "el hombro se le sale de lugar"). Todo el giro lo hacia el hueso del
	# HOMBRO, que pivota dentro del torso: al levantar el brazo, el bloque del hombro y el borde de arriba del
	# brazo salian por encima, hacia el cuello, como dislocado. Ahora el hombro se lleva un 30 % del giro (el
	# deltoides que se levanta) y el resto lo hace el brazo desde SU articulacion, mas arriba y mas afuera.
	var s0: Vector3 = skeleton.get_bone_global_pose(ish).origin
	var e0: Vector3 = skeleton.get_bone_global_pose(il).origin
	var psh: int = skeleton.get_bone_parent(ish)
	var g_parent := Quaternion(skeleton.get_bone_global_pose(psh).basis) if psh >= 0 else Quaternion.IDENTITY
	var g_sh0 := Quaternion(skeleton.get_bone_global_pose(ish).basis)
	var hacia := (target - s0).normalized()
	# el hombro solo gira hacia delante/los lados, NO sube: si sube, levanta la articulacion y el brazo queda
	# por encima del hombro ("el brazo esta mas arriba del hombro"). La altura la pone el brazo.
	var reposo := (e0 - s0).normalized()
	hacia = Vector3(hacia.x, 0.0, hacia.z).normalized() * sqrt(maxf(0.0, 1.0 - reposo.y * reposo.y)) + Vector3.UP * reposo.y
	hacia = hacia.normalized()
	var r_parcial := Quaternion.IDENTITY.slerp(Quaternion((e0 - s0).normalized(), hacia), _hombro_parte)
	skeleton.set_bone_pose_rotation(ish, (g_parent.inverse() * (r_parcial * g_sh0).normalized()).normalized())
	# LA ARTICULACION BAJA AL LEVANTAR EL BRAZO ("al apuntar se sube mas arriba que el hombro"): con el brazo
	# hacia delante el bloque del brazo asomaba por encima del hombro; se hunde lo que haga falta en el torso.
	var rest_u: Vector3 = skeleton.get_bone_rest(iu).origin
	var alza := clampf(1.0 + (target - s0).normalized().y * 1.5, 0.0, 1.0)
	var g_sh1 := Quaternion(skeleton.get_bone_global_pose(ish).basis)
	skeleton.set_bone_pose_position(iu, rest_u + g_sh1.inverse() * (Vector3.DOWN * _hombro_baja * alza))
	# y el IK de dos huesos, con la raiz en la ARTICULACION del brazo (su hueso, ya desplazado por el hombro)
	var s_pos: Vector3 = skeleton.get_bone_global_pose(iu).origin
	var e_pos: Vector3 = skeleton.get_bone_global_pose(il).origin
	var v_local: Vector3 = skeleton.get_bone_rest(bone_idx[hand]).origin
	var l1 := s_pos.distance_to(e_pos)
	var l2 := v_local.length()
	var to_t := target - s_pos
	var d := clampf(to_t.length(), 0.01, l1 + l2 - 0.01)
	var dir := to_t.normalized()
	# codo: en el plano hombro-objetivo-imán, del lado del imán
	var m := magnet - s_pos
	var perp := m - dir * m.dot(dir)
	if perp.length_squared() < 1e-4:
		perp = Vector3.DOWN
	perp = perp.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var elbow := s_pos + dir * (l1 * cos_a) + perp * (l1 * sqrt(maxf(0.0, 1.0 - cos_a * cos_a)))
	# brazo: girar (arco minimo) el segmento articulacion->codo hacia el codo calculado
	var g_sh := skeleton.get_bone_global_pose(ish).basis.get_rotation_quaternion()
	var g_up := skeleton.get_bone_global_pose(iu).basis.get_rotation_quaternion()
	var cur_u := (e_pos - s_pos).normalized()
	var want_u := (elbow - s_pos).normalized()
	var r_up := (Quaternion(cur_u, want_u) * g_up).normalized()
	skeleton.set_bone_pose_rotation(iu, (g_sh.inverse() * r_up).normalized())
	# antebrazo: desde el codo (ya recolocado) hacia la muñeca
	var g_upper := skeleton.get_bone_global_pose(iu).basis.get_rotation_quaternion()
	var g_lower := skeleton.get_bone_global_pose(il).basis.get_rotation_quaternion()
	var e_now: Vector3 = skeleton.get_bone_global_pose(il).origin
	var cur_v := (g_lower * v_local).normalized()
	var want_v := (target - e_now).normalized()
	var r_lower := (Quaternion(cur_v, want_v) * g_lower).normalized()
	skeleton.set_bone_pose_rotation(il, (g_upper.inverse() * r_lower).normalized())
	if _ik_debug:
		print("[ik] %s shoulder %s elbow_calc %s elbow_real %s hand_real %s target %s l1 %.1f l2 %.1f d %.1f" % [shoulder, str(s_pos), str(elbow), str(e_now), str(skeleton.get_bone_global_pose(bone_idx[hand]).origin), str(target), l1, l2, d])

## LAS MANOS SIEMPRE LLEGAN AL ARMA (2026-09-28, pedido: "al apuntar el arma se va muy adelante de las manos, se ve
## flotando"). El IK de los brazos para en su largo: si la empuñadura o el guardamanos quedan mas lejos, la mano se
## queda corta y el arma flota. Aqui, si alguno de los dos queda fuera del alcance de su hombro, se TRAE el arma hacia
## el (en linea recta) lo que sobre. Con la pistola, la mano de apoyo va a su sitio junto a la empuñadura.
var _alcance_brazo := -1.0
const GUARDIA_ALCANCE := 0.80
## Lo que se echa atras la muñeca en la guardia para que el puño (el guante, mas alla del hueso) quede sobre el arma
const GUARDIA_PUNO := 3.5

## `apoyo_suelto` (0..1, lo que se esta encarando): cuanto deja de contar la mano de APOYO de un arma de dos manos. Al
## encarar el arma va por delante del pecho (_despejar_pecho) y el guardamanos de un fusil queda fuera del brazo del
## muñeco: si la mano de apoyo tirara del arma hacia su hombro la volveria a meter en el pecho. En vez de eso, esa mano
## se desliza por el arma hasta donde llega (_apoyo_al_alcance). La del gatillo sigue mandando siempre.
func _al_alcance(origin: Vector3, rot: Quaternion, s: float, apoyo_suelto: float = 0.0) -> Vector3:
	if grip_marker == null or not (bone_idx.has("arm_upper_r") and bone_idx.has("arm_upper_l") and bone_idx.has("arm_lower_r") and bone_idx.has("hand_r")):
		return origin
	if _alcance_brazo < 0.0:
		var l1: float = skeleton.get_bone_rest(bone_idx["arm_lower_r"]).origin.length()
		var l2: float = skeleton.get_bone_rest(bone_idx["hand_r"]).origin.length()
		_alcance_brazo = (l1 + l2) * 0.96
	var b := Basis(rot)
	var hombro_g: Vector3 = skeleton.get_bone_global_pose(bone_idx["arm_upper_l" if _swap_hands else "arm_upper_r"]).origin
	var hombro_a: Vector3 = skeleton.get_bone_global_pose(bone_idx["arm_upper_r" if _swap_hands else "arm_upper_l"]).origin
	var apoyo_local: Vector3 = (grip_marker.position + PISTOLA_APOYO / s) if _one_hand else fore_marker.position
	# EN LA GUARDIA DE ESCAPARATE los brazos no llegan estirados (2026-09-30, pedido: "el codo se mete muy adentro, sale
	# del hombro"): con el brazo de apoyo al limite, el codo no tenia donde doblar y se iba al centro del pecho. Ahi el
	# arma se trae hasta que las dos manos quedan a GUARDIA_ALCANCE de su largo, con los codos doblados.
	var alcance := _alcance_brazo * (GUARDIA_ALCANCE if _en_guardia_menu else 1.0)
	for _k in 4:
		var g: Vector3 = origin + b * grip_marker.position
		var f: Vector3 = origin + b * apoyo_local
		var exceso := g.distance_to(hombro_g) - alcance
		var dir := (g - hombro_g).normalized()
		var ef := (f.distance_to(hombro_a) - alcance) * (1.0 if _one_hand else 1.0 - apoyo_suelto)
		if ef > exceso:
			exceso = ef
			dir = (f - hombro_a).normalized()
		if exceso <= 0.05:
			break
		origin -= dir * (exceso + 0.3)
	return origin


# ---------------------------------------------------------------------------
# EL ARMA NO SE METE EN EL PECHO (2026-09-30, pedido: "cuando disparo lleva el arma al pecho y se le mete dentro").
# Al encarar (apuntar o disparar) la mira va a `aim_delante` del ojo, y la culata, que va detras de la mira, quedaba
# DENTRO del torso: medido con --pechofoto, 17-28 cm en el soldado y 26-45 cm en Puño de Oro y Golpe de Cristal (mas
# pecho, casco y hombreras). Ahora, encarando, el arma se ADELANTA a lo largo de su cañon (la mira sigue en la linea del
# ojo) lo justo para que nada de su parte de atras quede dentro del cuerpo de ESTE muñeco, sea la skin que sea:
#  * el PERFIL de cada malla, sacado una vez de sus propios triangulos (_perfil_cuerpo): por grupo de huesos (vientre,
#    pecho, cada hombro, cabeza), la z de delante y la de atras de cada columna de un voxel, en reposo;
#  * unos cuantos PUNTOS del arma (lo de atras, lo de abajo y lo de arriba de su mitad trasera), una vez por arma
#    (_puntos_arma);
#  * cada fotograma encarando se llevan esos puntos al reposo de cada grupo y se mira cuanto se meten (_hundimiento).
# ---------------------------------------------------------------------------
## Grupos del perfil: hueso de la malla -> hueso cuyo marco lo mueve. Solo lo que puede tocar un arma encarada.
const PERFIL_GRUPOS := {"stomach": "stomach", "chest": "chest", "hood": "chest", "neck": "chest",
	"shoulder_l": "shoulder_l", "shoulder_r": "shoulder_r", "head": "head",
	"eye_l_up": "head", "eye_l_dn": "head", "eye_r_up": "head", "eye_r_dn": "head"}
## Las poses que se despejan (el lanzacohetes va al hombro a proposito y el mazo no se encara)
const DESPEJE_TIPOS := ["rifle", "shotgun", "pistol"]
## Lo que queda el arma por delante del cuerpo (m) y lo rapido que vuelve atras cuando ya no hace falta (m/s)
const DESPEJE_MARGEN := 0.012
const DESPEJE_VUELTA := 0.5
## La mano de apoyo, al deslizarse por el arma, no se acerca a la del gatillo mas que esto (m)
const APOYO_MIN := 0.11
static var EMPUNADURA_PECHO: float = (func() -> float:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--pechoarma="):
			return float(String(a).substr(12))
	return 8.0).call()
## --sindespeje: el arma encarada como antes (A/B)
## APAGADO (2026-09-30): el usuario paro este arreglo a medias ("esta rebugueado, no veo mejora"). Queda el codigo; se
## prueba con --condespeje.
static var sin_despeje := not ("--condespeje" in OS.get_cmdline_user_args())
static var _perfiles := {}
static var _puntos_cache := {}
var _despeje := 0.0              ## lo que se adelanta ahora el arma encarada (voxels, a lo largo del cañon)


## EL PERFIL DEL CUERPO de una malla skinnada (espacio de reposo del esqueleto, voxels, delante = -Z): por grupo, la z de
## delante y la de atras de cada columna (x, y) de un voxel. Solo cuentan las caras de delante y de atras (las mallas
## son de voxels: las caras de los lados y de arriba no ocupan columna). Se hace una vez por malla.
static func _perfil_cuerpo(malla: Mesh) -> Array:
	var clave := malla.get_instance_id()
	if _perfiles.has(clave):
		return _perfiles[clave]
	var grupos := {}          # hueso del grupo -> [x0, x1, y0, y1, z0, z1, ...] (la caja de cada triangulo que cuenta)
	for srf in malla.get_surface_count():
		var arr: Array = malla.surface_get_arrays(srf)
		if arr[Mesh.ARRAY_VERTEX] == null or arr[Mesh.ARRAY_BONES] == null:
			continue
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var con := idx.size() > 0
		var ntri: int = (idx.size() if con else v.size()) / 3
		var ultimo_b := -1
		var lista: Array = []
		var usa := false
		for t in ntri:
			var i0: int = idx[t * 3] if con else t * 3
			var b: int = bo[i0 * 4]
			if b != ultimo_b:
				ultimo_b = b
				var g = PERFIL_GRUPOS.get(_shared_bone_order[b] if b < _shared_bone_order.size() else "", null)
				usa = g != null
				if usa:
					if not grupos.has(g):
						grupos[g] = []
					lista = grupos[g]
			if not usa:
				continue
			var a: Vector3 = v[i0]
			var bb: Vector3 = v[idx[t * 3 + 1] if con else t * 3 + 1]
			var c: Vector3 = v[idx[t * 3 + 2] if con else t * 3 + 2]
			var x0 := minf(a.x, minf(bb.x, c.x)) + 0.01
			var x1 := maxf(a.x, maxf(bb.x, c.x)) - 0.01
			var y0 := minf(a.y, minf(bb.y, c.y)) + 0.01
			var y1 := maxf(a.y, maxf(bb.y, c.y)) - 0.01
			if x1 < x0 or y1 < y0:
				continue      # cara de lado o de arriba: no tapa ninguna columna
			lista.append_array([x0, x1, y0, y1, minf(a.z, minf(bb.z, c.z)), maxf(a.z, maxf(bb.z, c.z))])
	var out: Array = []
	for g in grupos.keys():
		var cajas: Array = grupos[g]
		if cajas.is_empty():
			continue
		var gx0 := INF
		var gx1 := -INF
		var gy0 := INF
		var gy1 := -INF
		for k in range(0, cajas.size(), 6):
			gx0 = minf(gx0, cajas[k])
			gx1 = maxf(gx1, cajas[k + 1])
			gy0 = minf(gy0, cajas[k + 2])
			gy1 = maxf(gy1, cajas[k + 3])
		var ox := int(floor(gx0))
		var oy := int(floor(gy0))
		var w := int(floor(gx1)) - ox + 1
		var h := int(floor(gy1)) - oy + 1
		var delante := PackedFloat32Array()
		delante.resize(w * h)
		delante.fill(INF)
		var atras := PackedFloat32Array()
		atras.resize(w * h)
		atras.fill(-INF)
		for k in range(0, cajas.size(), 6):
			for y in range(int(floor(cajas[k + 2])) - oy, int(floor(cajas[k + 3])) - oy + 1):
				for x in range(int(floor(cajas[k])) - ox, int(floor(cajas[k + 1])) - ox + 1):
					var i := y * w + x
					delante[i] = minf(delante[i], cajas[k + 4])
					atras[i] = maxf(atras[i], cajas[k + 5])
		out.append({"hueso": g, "x0": ox, "y0": oy, "w": w, "h": h, "delante": delante, "atras": atras})
	_perfiles[clave] = out
	return out


## LOS PUNTOS DEL ARMA que pueden tocar el cuerpo (metros, en el modelo; delante = -Z): de su mitad de atras (desde un
## poco por delante del guardamanos), lo de mas atras de cada columna (x, y) y lo de mas abajo y mas arriba de cada
## columna (x, z), en celdas de 4 cm (8 de ancho). Al cabecear, lo de abajo del arma va hacia el vientre y lo de arriba
## hacia la cara. Una vez por arma.
func _puntos_arma() -> PackedVector3Array:
	if _wm == null or not is_instance_valid(_wm):
		return PackedVector3Array()
	var clave := _arma_id if _arma_id != "" else String(weapon_kind)
	if _puntos_cache.has(clave):
		return _puntos_cache[clave]
	var zmin: float = (_wm.foregrip_pos.z if not _one_hand else _wm.muzzle_pos.z) - 0.02
	var atras := {}
	var abajo := {}
	var arriba := {}
	for n in _wm.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != _wm:
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		for srf in mi.mesh.get_surface_count():
			var vv = mi.mesh.surface_get_arrays(srf)[Mesh.ARRAY_VERTEX]
			if vv == null:
				continue
			for v0 in (vv as PackedVector3Array):
				var v: Vector3 = xf * v0
				if v.z < zmin:
					continue
				var cx := int(floor(v.x / 0.08))
				var k1 := Vector2i(cx, int(floor(v.y / 0.04)))
				if not atras.has(k1) or v.z > (atras[k1] as Vector3).z:
					atras[k1] = v
				var k2 := Vector2i(cx, int(floor(v.z / 0.04)))
				if not abajo.has(k2) or v.y < (abajo[k2] as Vector3).y:
					abajo[k2] = v
				if not arriba.has(k2) or v.y > (arriba[k2] as Vector3).y:
					arriba[k2] = v
	var vistos := {}
	var out := PackedVector3Array()
	for d in [atras, abajo, arriba]:
		for v in (d as Dictionary).values():
			if not vistos.has(v):
				vistos[v] = true
				out.append(v)
	_puntos_cache[clave] = out
	return out


## CUANTO HAY QUE ADELANTAR EL ARMA (voxels, a lo largo de su cañon) para que ninguno de `pts` quede dentro del cuerpo,
## con el arma en `origin` / `rot` (espacio del esqueleto). Cada grupo del perfil se mira en SU reposo: el punto se lleva
## de la pose de ahora a la de reposo de su hueso, y ahi se compara con la columna.
func _hundimiento(origin: Vector3, rot: Quaternion, pts: PackedVector3Array, perfil: Array) -> float:
	var xa := Transform3D(Basis(rot), origin) * _wm.transform
	var canon: Vector3 = Basis(rot) * Vector3(0, 0, -1)
	var peor := 0.0
	for g in perfil:
		var ig: int = bone_idx.get(g["hueso"], -1)
		if ig < 0:
			continue
		var m: Transform3D = skeleton.get_bone_global_rest(ig) * skeleton.get_bone_global_pose(ig).affine_inverse()
		var xf := m * xa
		# lo que avanza hacia delante (-Z del reposo) cada voxel que se adelanta el arma por su cañon
		var avance: float = maxf(-(m.basis * canon).z, 0.35)
		var fr: PackedFloat32Array = g["delante"]
		var at: PackedFloat32Array = g["atras"]
		var ox: int = g["x0"]
		var oy: int = g["y0"]
		var w: int = g["w"]
		var h: int = g["h"]
		for p in pts:
			var q: Vector3 = xf * p
			var cx := int(floor(q.x)) - ox
			var cy := int(floor(q.y)) - oy
			if cx < 0 or cy < 0 or cx >= w or cy >= h:
				continue
			var i := cy * w + cx
			if q.z > fr[i] and q.z < at[i]:
				peor = maxf(peor, (q.z - fr[i]) / avance)
	return peor


## LO QUE LE FALTA A UN BRAZO PARA LLEGAR a `objetivo` (voxels; <= 0 = llega), con la cuenta de _solve_arm: el hombro gira
## _hombro_parte hacia el objetivo y la articulacion baja al levantar el brazo, y desde ahi el brazo mide lo que mide. (El
## `_alcance_brazo` de _al_alcance no cuenta con eso y se queda corto: al encarar traia el arma hacia atras sin hacer
## falta, y eso tambien la metia en el pecho.) Deja en `_articulacion` donde queda la del brazo.
var _articulacion := Vector3.ZERO
const BRAZO_HOLGURA := 0.3        ## voxels que se deja de margen al largo del brazo

func _falta_brazo(gatillo: bool, objetivo: Vector3, doblar := 0.0) -> float:
	var r := gatillo != _swap_hands
	var sh: String = "shoulder_r" if r else "shoulder_l"
	var up: String = "arm_upper_r" if r else "arm_upper_l"
	var lo: String = "arm_lower_r" if r else "arm_lower_l"
	var ha: String = "hand_r" if r else "hand_l"
	if not (bone_idx.has(sh) and bone_idx.has(up) and bone_idx.has(lo) and bone_idx.has(ha)):
		return 0.0
	var g_sh: Transform3D = skeleton.get_bone_global_pose(bone_idx[sh])
	var s0: Vector3 = g_sh.origin
	var rest_u: Vector3 = skeleton.get_bone_rest(bone_idx[up]).origin
	var codo: Vector3 = skeleton.get_bone_pose_position(bone_idx[lo])
	var u0: Vector3 = g_sh * rest_u
	var reposo: Vector3 = ((g_sh * (rest_u + _shared_bind.get(up, Quaternion.IDENTITY) * codo)) - s0).normalized()
	var hacia: Vector3 = (objetivo - s0).normalized()
	var alza := clampf(1.0 + hacia.y * 1.5, 0.0, 1.0)
	hacia = (Vector3(hacia.x, 0.0, hacia.z).normalized() * sqrt(maxf(0.0, 1.0 - reposo.y * reposo.y)) + Vector3.UP * reposo.y).normalized()
	var giro := Quaternion.IDENTITY
	if reposo.dot(hacia) > -0.99:
		giro = Quaternion.IDENTITY.slerp(Quaternion(reposo, hacia), _hombro_parte)
	_articulacion = s0 + giro * (u0 - s0) + Vector3.DOWN * _hombro_baja * alza
	var largo: float = codo.length() + skeleton.get_bone_rest(bone_idx[ha]).origin.length()
	return objetivo.distance_to(_articulacion) - (largo * (1.0 - doblar) - BRAZO_HOLGURA)


## EL ARMA DEL TODO ENCARADA, por delante del cuerpo: con la mira en la linea del ojo (`origin` / `rot` salen de t_aim),
## se trae hacia el hombro del gatillo SOLO si esa mano no llega de verdad (_falta_brazo; con la pistola, tambien la otra,
## que la abraza), y se adelanta por el cañon lo que pida el cuerpo (_despejar_pecho).
func _origen_encarado(origin: Vector3, rot: Quaternion, s: float, dt: float) -> Vector3:
	var b := Basis(rot)
	var apoyo_local: Vector3 = grip_marker.position + PISTOLA_APOYO / s
	for _k in 3:
		var falta := _falta_brazo(true, origin + b * grip_marker.position)
		var hacia: Vector3 = _articulacion - (origin + b * grip_marker.position)
		if _one_hand:
			var fa := _falta_brazo(false, origin + b * apoyo_local)
			if fa > falta:
				falta = fa
				hacia = _articulacion - (origin + b * apoyo_local)
		if falta <= 0.05:
			break
		origin += hacia.normalized() * (falta + 0.2)
	return origin + b * Vector3(0, 0, -1) * _despejar_pecho(origin, rot, s, dt)


## LO QUE SE ADELANTA EL ARMA ENCARADA (voxels, por su cañon) para que no se meta en el cuerpo, con el arma del todo
## encarada en `origin` / `rot` (ver arriba). Nunca tanto que la mano del GATILLO deje de llegar a la empuñadura: mirando
## muy arriba, con las hombreras de las skins gordas, haria falta mas de lo que da el brazo, y un arma flotando delante de
## las manos se ve peor que la culata rozando el pecho. `hay` = false: no se esta encarando (vuelve a 0 despacio).
func _despejar_pecho(origin: Vector3, rot: Quaternion, s: float, dt: float, hay: bool = true) -> float:
	var objetivo := 0.0
	if hay and not _en_guardia_menu and _wm != null and mesh_inst != null and mesh_inst.mesh != null:
		var perfil := _perfil_cuerpo(mesh_inst.mesh)
		var pts := _puntos_arma()
		var canon: Vector3 = Basis(rot) * Vector3(0, 0, -1)
		for _k in 3:
			var d := _hundimiento(origin + canon * objetivo, rot, pts, perfil)
			if d <= 0.05:
				break
			objetivo += d + DESPEJE_MARGEN / s
		# el tope del brazo del gatillo (y del de apoyo en la pistola, que va pegado a la empuñadura)
		var g: Vector3 = origin + Basis(rot) * grip_marker.position
		var ap: Vector3 = origin + Basis(rot) * (grip_marker.position + PISTOLA_APOYO / s)
		if objetivo > 0.0 and (_falta_brazo(true, g + canon * objetivo) > 0.0 or (_one_hand and _falta_brazo(false, ap + canon * objetivo) > 0.0)):
			var lo := 0.0
			var hi := objetivo
			for _i in 8:
				var m := (lo + hi) * 0.5
				if _falta_brazo(true, g + canon * m) > 0.0 or (_one_hand and _falta_brazo(false, ap + canon * m) > 0.0):
					hi = m
				else:
					lo = m
			objetivo = lo
	# sube al momento (el arma no se llega a ver dentro) y vuelve despacio (sin tirones al cambiar de columna)
	if dt <= 0.0 or objetivo >= _despeje:
		_despeje = objetivo
	else:
		_despeje = move_toward(_despeje, objetivo, DESPEJE_VUELTA / s * dt)
	return _despeje


## LA MANO DE APOYO SE DESLIZA POR EL ARMA si no llega a su agarre: por la linea del guardamanos a la empuñadura, hasta el
## punto mas adelantado al que llega su brazo y nunca a menos de APOYO_MIN de la mano del gatillo (si ni ahi llega, se
## queda ahi con el brazo estirado). Al encarar, el arma va por delante del pecho y el guardamanos de un fusil queda
## fuera del brazo del muñeco.
## ENCARADA, CON EL CODO DOBLADO (2026-10-11, bug: "la mano izquierda no agarra el arma y al apuntar se mete en el cuerpo"):
## la mano se quedaba en el limite exacto del brazo, el brazo recto, y la linea recta del hombro de apoyo al arma (en el
## otro hombro) cruzaba el pecho por dentro. Apuntando se le deja APOYO_DOBLA del largo de margen: la mano se agarra un
## poco mas atras en el arma, el codo se dobla y baja fuera del cuerpo (el iman, _iman_codo_natural). --apoyodobla=X.
static var APOYO_DOBLA: float = (func() -> float:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--apoyodobla="):
			return float(String(a).substr(13))
	return 0.0).call()   # (probado: la mano ya llega a su guardamanos; queda apagado)

func _apoyo_al_alcance(grip_t: Vector3, fore_t: Vector3) -> Vector3:
	var dobla: float = APOYO_DOBLA * clampf(_dbg_aim_ef, 0.0, 1.0)
	if _falta_brazo(false, fore_t, dobla) <= 0.0:
		return fore_t
	var largo := grip_t.distance_to(fore_t)
	var a: Vector3 = grip_t + (fore_t - grip_t) / maxf(largo, 0.001) * minf(APOYO_MIN / maxf(scale.x, 0.0001), largo)
	if _falta_brazo(false, a, dobla) > 0.0:
		return a
	var b := fore_t
	for _i in 8:
		var m := (a + b) * 0.5
		if _falta_brazo(false, m, dobla) > 0.0:
			b = m
		else:
			a = m
	return a


func _update_rifle_transform(dt: float) -> void:
	var _tr := Time.get_ticks_usec()
	_en_guardia_menu = false
	if not weapon_root or _external_weapon or not bone_idx.has("neck") or not grip_marker:
		return
	if escudo_activo():
		_aplicar_escudo(dt)
		if _prof_av:
			Prof.add("av.a.escudo", Time.get_ticks_usec() - _tr)
		return
	var s := scale.x   # metros por voxel
	# SI ALGO LLEGO NO FINITO, SE EMPIEZA DE NUEVO. Estos valores se suavizan con lerp/slerp contra el cuadro
	# anterior, asi que un unico NaN (de donde venga) los dejaba en NaN para siempre y el muñeco y su arma
	# desaparecian de la pantalla con miles de errores. Se resetean y en el cuadro siguiente vuelven solos.
	if not (is_finite(_sway_ang) and is_finite(_arm_pitch) and _hold_pos.is_finite()
			and is_finite(_hold_rot.x + _hold_rot.y + _hold_rot.z + _hold_rot.w) and is_finite(sway_amount) and is_finite(look_pitch)):
		_sway_ang = 0.0
		_arm_pitch = 0.0
		_hold_init = false
		if not is_finite(sway_amount):
			sway_amount = 0.0
		if not is_finite(look_pitch):
			look_pitch = 0.0
	if _wm:   # puntos de agarre del modelo (por si el modelo se construyó después de crear los marcadores)
		grip_marker.position = _wm.grip_pos * _arma_k / s
		fore_marker.position = _wm.foregrip_pos * _arma_k / s
	# el arma con la que se buscan las poses: varias comparten juego (una SMG usa las del fusil)
	var pose_kind: String = HOLD_ALIAS.get(weapon_kind, weapon_kind)
	if not HOLD_POSES.has(pose_kind):
		pose_kind = "rifle"
	var poses: Dictionary = HOLD_POSES[pose_kind]
	_since_fire += dt
	var snap := dt <= 0.0   # hojas de poses / primer frame: sin amortiguar
	_crouch_w = move_toward(_crouch_w, 1.0 if current_clip.begins_with("crouch") else 0.0, 1.0 if snap else 4.0 * dt)
	_jump_w = move_toward(_jump_w, 1.0 if current_clip.begins_with("jump") else 0.0, 1.0 if snap else 4.0 * dt)
	# pose objetivo (toolanimation.lua::tickToolAnimator)
	var pose := _td_pose(_pose_de(poses, "action", pose_kind))
	# la guardia de escaparate de la armeria (`pose_menu`): vacia en todos los demas muñecos, que no cambian
	_en_guardia_menu = pose_menu.has(pose_kind)
	if _en_guardia_menu:
		pose = _td_pose(pose_menu[pose_kind])
	if poses.has("action_crouch") and _crouch_w > 0.0:
		pose = _mix_pose(pose, _td_pose(_pose_de(poses, "action_crouch", pose_kind)), _crouch_w)
	# El arma baja e inclina mientras el dueño se mueve, y vuelve a apuntar al pararse o
	# disparar. Antes dependía sólo del tiempo sin disparar (2 s), así que se bajaba estando
	# quieto y seguía apuntando al frente mientras caminabas.
	var lower: float = clampf(move_amount, 0.0, 1.0) * clampf((_since_fire - 0.3) / 0.5, 0.0, 1.0)
	# ...y no se baja mientras se esta encarando: eran dos poses tirando del arma a la vez
	lower *= 1.0 - clampf((TIRO_ENCARA - _since_fire) / (TIRO_ENCARA * 0.4), 0.0, 1.0)
	_lower_w = lower if snap else move_toward(_lower_w, lower, 4.0 * dt)
	var alt := _lower_w > 0.01
	if _lower_w > 0.0:
		# TRES TRAMOS: de quieto a andando en la primera mitad del rango de velocidad, y de andando
		# a corriendo en la segunda. Antes solo habia dos poses y "andar" era un punto intermedio
		# que no se podia tocar por su cuenta.
		if poses.has("walk"):
			if _lower_w <= 0.5:
				pose = _mix_pose(pose, _td_pose(_pose_de(poses, "walk", pose_kind)), _lower_w / 0.5)
			else:
				pose = _mix_pose(_td_pose(_pose_de(poses, "walk", pose_kind)),
					_td_pose(_pose_de(poses, "run", pose_kind)), (_lower_w - 0.5) / 0.5)
		elif poses.has("run"):
			pose = _mix_pose(pose, _td_pose(_pose_de(poses, "run", pose_kind)), _lower_w)
		if poses.has("jump") and _jump_w > 0.0:
			pose = _mix_pose(pose, _td_pose(_pose_de(poses, "jump", pose_kind)), _jump_w * _lower_w)
		if poses.has("crouch") and _crouch_w > 0.0:
			pose = _mix_pose(pose, _td_pose(_pose_de(poses, "crouch", pose_kind)), _crouch_w * _lower_w)
	if snap:
		_aim_w = 1.0 if aiming else 0.0   # hojas de pose: sin transicion
	# Los gestos van los últimos: mandan sobre la pose de acción/carrera/agachado.
	# con la recarga animada (fusiles) la pose fija de recarga sobra: la anima _aplicar_recarga
	_reload_w = move_toward(_reload_w, 1.0 if reloading and not _recarga_activa(pose_kind) else 0.0, 1.0 if snap else 5.0 * dt)
	_swap_t = maxf(_swap_t - dt, 0.0)
	_swap_w = move_toward(_swap_w, 1.0 if _swap_t > 0.0 else 0.0, 1.0 if snap else 8.0 * dt)
	if poses.has("reload") and _reload_w > 0.0:
		pose = _mix_pose(pose, _td_pose(poses["reload"]), _reload_w)
	if poses.has("swap") and _swap_w > 0.0:
		pose = _mix_pose(pose, _td_pose(poses["swap"]), _swap_w)
	# el mazazo manda sobre todo lo demas mientras dura
	# EL MAZAZO. `swing_scrub` >= 0 congela el arco en ese punto (0 a 1): es lo que permite pararlo
	# a medio golpe en el editor y colocar las poses, porque a 0,4 s de duracion no hay quien pose
	# nada. En el juego vale -1 y el gesto corre con su reloj.
	if _prof_av:
		Prof.add("av.a.mezcla", Time.get_ticks_usec() - _tr); _tr = Time.get_ticks_usec()
	_update_colgante(dt)
	if _venda_t > 0.0:
		_venda_t = maxf(0.0, _venda_t - dt)
		if _venda_t <= 0.0:
			parar_vendar()
	if _limpia_t > 0.0:
		_limpia_t = maxf(0.0, _limpia_t - dt)
		# EL ARMA SE SUELTA: baja a la pose de correr mientras dura el gesto. Sin esto el fusil se
		# quedaba clavado en el sitio con una mano volando a la cara, que es lo que se veia falso.
		if poses.has("run"):
			pose = _mix_pose(pose, _td_pose(_pose_de(poses, "run", pose_kind)), _limpia_peso() * 0.9)
	if (swing_scrub >= 0.0 or _swing_t > 0.0) and poses.has("swing_up"):
		var k: float = swing_scrub
		if swing_scrub < 0.0:
			# el reloj del arco: clavado mientras dura el frenazo del impacto, y mas lento en la
			# vuelta si el golpe fue al aire
			if _swing_frena > 0.0:
				_swing_frena = maxf(0.0, _swing_frena - dt)
			else:
				_swing_t = maxf(0.0, _swing_t - dt * _swing_lento)
			k = 1.0 - (_swing_t / _swing_dur)
		_mazo_k = k
		# Los tres tramos del gesto: CARGAR (echarlo atras), GOLPEAR y VOLVER. Los cortes y las
		# curvas son ajustables porque son justo lo que da la sensacion de peso: una carga lenta y
		# un golpe seco no se parecen en nada a lo contrario.
		var carga: float = pow(clampf(k / swing_carga, 0.0, 1.0), swing_curva_carga)
		var golpe: float = pow(clampf((k - swing_carga) / maxf(swing_golpe, 0.01), 0.0, 1.0), swing_curva_golpe)
		var vuelta: float = pow(clampf((k - swing_carga - swing_golpe) / maxf(1.0 - swing_carga - swing_golpe, 0.01), 0.0, 1.0), swing_curva_vuelta)
		pose = _mix_pose(pose, _td_pose(_pose_de(poses, "swing_up", pose_kind)), clampf(carga - golpe, 0.0, 1.0))
		pose = _mix_pose(pose, _td_pose(_pose_de(poses, "swing_hit", pose_kind)), clampf(golpe - vuelta, 0.0, 1.0))
		# SI NO HA DADO EN NADA, la vuelta no es una vuelta: el mazo pasa de largo al costado y solo
		# despues se recompone. Es un bulto que sube y baja dentro del ultimo tramo, asi que el
		# gesto acaba igual en la guardia sin dar ningun tiron.
		if _swing_res != 1 and poses.has("swing_past"):
			var resto: float = maxf(1.0 - swing_carga - swing_golpe, 0.01)
			var u: float = clampf((k - swing_carga - swing_golpe) / resto, 0.0, 1.0)
			if u > 0.0:
				pose = _mix_pose(pose, _td_pose(_pose_de(poses, "swing_past", pose_kind)), sin(u * PI) * 0.9)
	var a := 1.0 if snap else 1.0 - pow(2.0, -(20.0 if alt else 60.0) * dt)
	if not _hold_init:
		_hold_pos = pose[0]
		_hold_rot = pose[1]
		_hold_init = true
		a = 1.0
	else:
		_hold_pos = _hold_pos.lerp(pose[0], a)
		_hold_rot = _hold_rot.slerp(pose[1], a).normalized()
	# espacio del ojo -> esqueleto (voxels): ojo a 1,7 m sobre el suelo del avatar (el esqueleto va desplazado
	# por el ajuste de suelo del clip, por eso se resta su posición)
	var eye := Vector3(0.0, EYE_HEIGHT_M / s, 0.0) - skeleton.position
	if _prof_av:
		Prof.add("av.a.pose", Time.get_ticks_usec() - _tr); _tr = Time.get_ticks_usec()
	var neck: Vector3 = skeleton.get_bone_global_pose(bone_idx["neck"]).origin
	var t_pos := eye + _hold_pos / s + _bone_anim_offset("shoulder_r")
	var rot := _hold_rot
	# cabeceo del brazo: la posición del arma gira alrededor del cuello
	_arm_pitch = lerpf(_arm_pitch, look_pitch * (0.5 if alt else 1.0), a)
	t_pos = neck + Quaternion(Vector3.RIGHT, _arm_pitch) * (t_pos - neck)
	# balanceo con el avance del pie derecho (guiñada; espejo -> signo cambiado)
	var sway_t: float = -_bone_anim_offset("foot_r").z * s * SWAY_GAIN * clampf(sway_amount, 0.0, 1.0)
	# amortiguado: el ángulo persigue su objetivo en vez de saltar, así no da tirones al
	# aumentar la cadencia con la velocidad
	_sway_ang = sway_t if snap else lerpf(_sway_ang, sway_t, 1.0 - pow(2.0, -18.0 * dt))
	var sway := Quaternion(Vector3.UP, _sway_ang)
	t_pos = neck + sway * (t_pos - neck)
	rot = (sway * rot).normalized()
	if look_sway.length_squared() > 1e-8:
		var lq := (Quaternion(Vector3.UP, -look_sway.x * LOOK_SWAY_ROT)
			* Quaternion(Vector3.RIGHT, -look_sway.y * LOOK_SWAY_ROT)).normalized()
		t_pos = neck + lq * (t_pos - neck)
		rot = (lq * rot).normalized()
	# cabeceo del propio arma sobre su pivote
	_tool_pitch = lerpf(_tool_pitch, look_pitch * (0.4 if alt else 1.0), 1.0 if dt <= 0.0 else 1.0 - pow(2.0, -30.0 * dt))
	# CABECEO PARA ENCARAR, aparte de los dos de arriba. Esos dos van amortiguados y recortados (a
	# la mitad con el arma baja) para que llevar el arma no sea rigido, pero AL APUNTAR el arma
	# tiene que mirar EXACTAMENTE a donde mira su dueno. Se estaban sumando los dos, o sea CABECEO
	# DOBLE: apuntando a la cabeza de alguien el arma le miraba al suelo, y para que apuntara a la
	# cabeza habia que mirar por encima de ella. En red eso hace pensar que el otro te ha fallado.
	_mira_pitch = look_pitch if snap else lerpf(_mira_pitch, look_pitch, 1.0 - pow(2.0, -26.0 * dt))
	rot = (Quaternion(Vector3.RIGHT, _tool_pitch) * rot).normalized()
	# el origen del modelo se elige para que NUESTRA empuñadura caiga en la ubicación tp_action_rh de Teardown
	# APUNTAR: en vez de buscar a mano una postura que "parezca" encarada, se RESUELVE. Se traza una
	# linea invisible desde el ojo hacia donde mira el personaje y se coloca el arma para que su
	# MIRA caiga en esa linea. Asi la mira queda a la altura del ojo por construccion, en cualquier
	# arma y con cualquier cabeceo, sin numeros magicos.
	#
	# Antes esto era una pose escrita a mano y no habia manera: con el arma baja la mira salia a la
	# altura del pecho y al subirla se ponia vertical, porque en este esqueleto el arma APUNTA HACIA
	# DONDE LA ALEJAS del cuello. Ese enredo desaparece resolviendo la geometria.
	# AL DISPARAR TAMBIEN SE ENCARA, no solo manteniendo el boton de apuntar.
	#
	# Medido en el banco de LAN mirando a un compañero mientras disparaba: el cañon de su avatar
	# apuntaba 74,5 grados FUERA de donde el estaba apuntando de verdad, y la boca le quedaba a
	# 0,87 m del suelo con el ojo a 1,60. La pose de "accion" lleva el arma cruzada al pecho, que
	# esta muy bien para andar con ella, pero es la que se veia al tirar desde la cadera: en su
	# pantalla apuntaba al frente y en la tuya disparaba al piso.
	#
	# Se resuelve con lo que ya habia: la misma geometria que coloca la mira en la linea del ojo se
	# aplica tambien un rato despues de cada tiro. No retrasa la bala -sale en el instante del
	# clic-, solo endereza al muñeco mientras dispara, que es lo que se ve desde fuera.
	# se mantiene ENTERO mientras dura la rafaga y se suelta al final: con una curva que baja desde el
	# primer instante, entre tiro y tiro el arma se caia otra vez al costado y parecia que temblaba
	var encara: float = clampf((TIRO_ENCARA - _since_fire) / (TIRO_ENCARA * 0.4), 0.0, 1.0)
	var aim_ef: float = maxf(_aim_w, encara)
	_dbg_aim_ef = aim_ef
	var t_aim := Vector3.ZERO
	var q_mira := Quaternion.IDENTITY
	if aim_ef > 0.001:
		var giro := Quaternion(Basis.from_euler(Vector3(
			deg_to_rad(aim_giro.x), deg_to_rad(aim_giro.y), deg_to_rad(aim_giro.z))))
		q_mira = (Quaternion(Vector3.RIGHT, _mira_pitch) * giro).normalized()
		var adelante: Vector3 = q_mira * Vector3(0, 0, -1)
		var ojo: Vector3 = skeleton.get_bone_global_pose(bone_idx["head"]).origin + aim_ojo
		var mira_local: Vector3 = (_wm.sight_pos if _wm else Vector3(0, 0.086, -0.13)) / s
		t_aim = ojo + adelante * ((AIM_DELANTE_PISTOLA if pose_kind == "pistol" else aim_delante) / s) - q_mira * mira_local
		t_pos = t_pos.lerp(t_aim, aim_ef)
		rot = rot.slerp(q_mira, aim_ef).normalized()
	var rh: Vector3 = poses["rh"]
	var agarre_rh: Vector3 = Vector3(-rh.x, rh.y, rh.z) / s - grip_marker.position
	var origin := t_pos + rot * agarre_rh
	var despeja: bool = pose_kind in DESPEJE_TIPOS and not sin_despeje
	if _prof_av:
		Prof.add("av.a.mira", Time.get_ticks_usec() - _tr); _tr = Time.get_ticks_usec()
	origin = _al_alcance(origin, rot, s, aim_ef if despeja else 0.0)
	# ENCARADA, POR DELANTE DEL CUERPO de este muñeco (EL ARMA NO SE METE EN EL PECHO, mas arriba). El arma del todo
	# encarada se resuelve aparte (_origen_encarado: a medio camino, con la pose de llevarla del editor, saldria otra cosa
	# y a saltos) y manda en la proporcion en que se esta encarando.
	if despeja and aim_ef > 0.001:
		origin = origin.lerp(_origen_encarado(t_aim + q_mira * agarre_rh, q_mira, s, dt), aim_ef)
	else:
		_despejar_pecho(origin, rot, s, dt, false)
	# LA EMPUÑADURA, POR DELANTE DEL PECHO (2026-10-11, bug con captura: "al apuntar la mano se le mete adentro del
	# cuerpo"): encarando, con el fusil, la escopeta o el subfusil la empuñadura quedaba en el centro del torso y DETRAS
	# del plano de los hombros (medido con --botapuntafoto: 2 voxels detras), asi que la mano del gatillo y su antebrazo
	# iban por dentro del pecho. Se adelanta el arma por su cañon (la mira sigue en la linea del ojo) lo justo para que la
	# empuñadura quede EMPUNADURA_PECHO por delante del hombro. (El despeje entero, --condespeje, la mandaba a brazo
	# estirado.) --pechoarma=N (voxels; 0 = como antes).
	# (y en la GUARDIA DEL MENU, la de la armeria: 2026-10-12, bug con captura "el brazo izquierdo no se ve, atraviesa el
	# cuerpo para sujetar el arma"; ahi la empuñadura tambien caia dentro del pecho)
	var w_pecho: float = 1.0 if _en_guardia_menu else aim_ef
	if w_pecho > 0.001 and EMPUNADURA_PECHO > 0.0 and pose_kind != "pistol" and not _one_hand:
		var sh_g: String = "shoulder_l" if _swap_hands else "shoulder_r"
		if bone_idx.has(sh_g):
			var hombro_g: Vector3 = skeleton.get_bone_global_pose(bone_idx[sh_g]).origin
			var canon_g: Vector3 = rot * Vector3(0, 0, -1)
			var gp: Vector3 = origin + rot * grip_marker.position
			var frente: float = hombro_g.z - EMPUNADURA_PECHO
			if gp.z > frente and canon_g.z < -0.2:
				origin += canon_g * ((gp.z - frente) / -canon_g.z) * w_pecho
	if _prof_av:
		Prof.add("av.a.alcance", Time.get_ticks_usec() - _tr); _tr = Time.get_ticks_usec()
	weapon_root.transform = Transform3D(Basis(rot), origin)
	if _prof_av:
		Prof.add("av.a.colocar", Time.get_ticks_usec() - _tr); _tr = Time.get_ticks_usec()
	_aplicar_pista_arma(dt, pose_kind, snap)
	if _prof_av:
		Prof.add("av.a.pista", Time.get_ticks_usec() - _tr); _tr = Time.get_ticks_usec()
	_aplicar_recarga(dt, pose_kind, s)
	if _prof_av:
		Prof.add("av.a.recarga", Time.get_ticks_usec() - _tr); _tr = Time.get_ticks_usec()
	_aplicar_caida(dt, s)
	if _prof_av:
		Prof.add("av.a.caida", Time.get_ticks_usec() - _tr); _tr = Time.get_ticks_usec()
	_aplicar_mazazo(s)
	# SIN CABEZA, para verse desde los propios ojos (player.gd, la caida en primera persona): el hueso de la cabeza
	# encogido, que la camara va dentro del casco
	if sin_cabeza and bone_idx.has("head"):
		skeleton.set_bone_pose_scale(bone_idx["head"], Vector3.ONE * 0.001)
	elif _cabeza_encogida and bone_idx.has("head"):
		skeleton.set_bone_pose_scale(bone_idx["head"], Vector3.ONE)
	_cabeza_encogida = sin_cabeza
	if _prof_av:
		Prof.add("av.a.resto", Time.get_ticks_usec() - _tr)


# ---------------------------------------------------------------------------
# EL FUSIL DE BLENDER AL ANDAR. caminar y crouch_fwd_tactico traen la pista del arma de su ciclo
# (exportar_clips.py ... arma): donde va el fusil respecto al cuello, donde lo cogen las dos munecas,
# hacia donde doblan los codos y el giro de cada mano. Mientras suenan mandan sobre las poses de sujecion
# (walk / run / crouch), que eran otra cosa: medido con --caminarmide contra el .blend, con el cuerpo
# identico, la boca del fusil caia a 54-112 cm de donde la lleva el ciclo y las munecas a 14-48 cm.
# Encima se sigue sumando lo que es de jugar: el cabeceo de la mirada y la inercia al girar la camara
# (mirando al frente y sin girar sale el ciclo de Blender tal cual). Al disparar, apuntar, cambiar de
# arma o limpiarse la cara vuelve la pose del juego.
# ---------------------------------------------------------------------------
var _pista := {}                 ## muestra de la pista en este frame (ver _pista_arma)
var _pista_w := 0.0              ## cuanto manda: 0 = poses del juego, 1 = el ciclo de Blender
var _pista_fuego := 1.0          ## cae a 0 al disparar, como el arma bajada (_lower_w)


func _aplicar_pista_arma(dt: float, pose_kind: String, snap: bool) -> void:
	_pista_w = 0.0
	if pose_kind != "rifle" or _one_hand or _arms_only or _clip_arma.is_empty():
		_pista = {}
		return
	var a: Dictionary = _pista_arma(current_clip, _time)
	var b: Dictionary = _pista_arma(_blend_from, _blend_prev_time) if _blend_from != "" else {}
	var bw: float = clampf(_blend_time / maxf(_blend_duration, 0.001), 0.0, 1.0) if _blend_from != "" else 1.0
	var peso := 0.0
	if not a.is_empty() and not b.is_empty():
		_pista = _mezclar_pista(b, a, bw)
		peso = 1.0
	elif not a.is_empty():
		_pista = a
		peso = bw
	elif not b.is_empty():
		_pista = b
		peso = 1.0 - bw
	else:
		_pista = {}
		return
	var fuego: float = clampf((_since_fire - 0.3) / 0.5, 0.0, 1.0)
	_pista_fuego = fuego if snap else move_toward(_pista_fuego, fuego, 6.0 * dt)
	var w: float = peso * _pista_fuego * (1.0 - _aim_w) * (1.0 - _swap_w)   # `_pista_fuego` ya cae al disparar
	if _limpia_t > 0.0:
		w *= 1.0 - _limpia_peso()
	if w <= 0.001:
		return
	_pista_w = smoothstep(0.0, 1.0, w)
	var cuello: Vector3 = skeleton.get_bone_global_pose(bone_idx["neck"]).origin
	var pos: Vector3 = Quaternion(Vector3.RIGHT, _arm_pitch) * (_pista["pos"] as Vector3)
	var giro: Quaternion = _pista["rot"]
	if look_sway.length_squared() > 1e-8:
		var lq := (Quaternion(Vector3.UP, -look_sway.x * LOOK_SWAY_ROT)
			* Quaternion(Vector3.RIGHT, -look_sway.y * LOOK_SWAY_ROT)).normalized()
		pos = lq * pos
		giro = (lq * giro).normalized()
	giro = (Quaternion(Vector3.RIGHT, _tool_pitch) * giro).normalized()
	weapon_root.transform = weapon_root.transform.interpolate_with(Transform3D(Basis(giro), cuello + pos), _pista_w)

## Las manos giradas como en el ciclo de Blender respecto al arma: la IK solo coloca las munecas, y el
## giro que traia la mano del clip, puesto sobre un antebrazo que la IK ha movido, la dejaba torcida.
func _girar_manos_pista(w_gat: float, w_apo: float) -> void:
	var rq := Quaternion(weapon_root.transform.basis.orthonormalized())
	for par in [["hand_r", "qgat", w_gat], ["hand_l", "qapo", w_apo]]:
		var w: float = par[2]
		if w <= 0.001 or not bone_idx.has(par[0]):
			continue
		var hi: int = bone_idx[par[0]]
		var padre := skeleton.get_bone_parent(hi)
		if padre < 0:
			continue
		var g_padre := Quaternion(skeleton.get_bone_global_pose(padre).basis.orthonormalized())
		var g_reposo := Quaternion(skeleton.get_bone_global_rest(hi).basis.orthonormalized())
		var quiere: Quaternion = (rq * (_pista[par[1]] as Quaternion) * g_reposo).normalized()
		var local := skeleton.get_bone_pose_rotation(hi)
		skeleton.set_bone_pose_rotation(hi, local.slerp((g_padre.inverse() * quiere).normalized(), w).normalized())


# ---------------------------------------------------------------------------
# RECARGA ANIMADA DEL FUSIL. Hecha en Blender sobre este mismo soldado (tools/blender/recarga_anim.py)
# y exportada frame a frame por tools/blender/exportar_recarga.py. NO es un clip de huesos: mueve lo
# mismo que ya mueven las poses de sujecion -el arma y el objetivo de IK de la mano de apoyo- y ademas
# el cargador. Asi las piernas siguen con su clip (andar, agacharse) y los brazos los resuelve la IK
# de siempre. El arma se coloca respecto al CUELLO, que es a lo que van atadas las poses del juego.
# ---------------------------------------------------------------------------
const RECARGA_PATH := "res://avatar/recarga_fusil.json"
const RECARGA_CLIP_S := 2.2          ## lo que dura tal cual se animo; se estira a `reload_dur`
const CargadorCaidoScript := preload("res://scripts/cargador_caido.gd")
static var _recarga: Dictionary = {}
static var _recarga_leida := false
var _recarga_t := -1.0               ## segundos de clip; -1 = sin recarga en curso
var _recarga_w := 0.0
var _recarga_mano := Vector3.ZERO    ## objetivo de la mano de apoyo, en el esqueleto
var _recarga_soltado := false

## UNA RECARGA POR TIPO DE ARMA (2026-09-23, pedido: "la pistola no usa la de la metra"). La del fusil es la de
## Blender (recarga_fusil.json); las demas las escribe tools/generar_recargas.py en el mismo formato, con la mano
## y el cargador contados desde el asiento del cargador de cada arma ("relativo").
const RECARGAS := {"rifle": "res://avatar/recarga_fusil.json", "pistol": "res://avatar/recarga_pistola.json",
	"smg": "res://avatar/recarga_fusil.json", "sniper": "res://avatar/recarga_cerrojo.json",
	"shotgun": "res://avatar/recarga_escopeta.json", "rocket": "res://avatar/recarga_cohete.json"}
static var _recargas := {}

static func _recarga_datos(tipo: String = "rifle") -> Dictionary:
	if _recargas.has(tipo):
		return _recargas[tipo]
	var d: Dictionary = {}
	var ruta := String(RECARGAS.get(tipo, ""))
	if ruta != "":
		var f := FileAccess.open(ruta, FileAccess.READ)
		if f:
			var j = JSON.parse_string(f.get_as_text())
			if typeof(j) == TYPE_DICTIONARY and int(j.get("frames", 0)) > 1:
				d = j
	_recargas[tipo] = d
	return d

## SOLO EL FUSIL PARA EL QUE SE HIZO: el de weapon_model._build_rifle, el unico con el cargador aparte (el
## mismo que tools/blender/arma_fusil.py). Antes bastaba con sujetarse "como un fusil", y eso metia la
## recarga del fusil en armas donde no encaja -el AK, el subfusil PDW, los de cerrojo, las mallas del
## catalogo-, con la mano yendo a buscar un cargador que no esta ahi. Esas, igual que la escopeta, la
## pistola y el lanzacohetes, siguen con su pose de recarga de siempre.
func _recarga_activa(pose_kind: String) -> bool:
	if weapon_kind == "rifle" or weapon_kind == "smg":   # metralletas y subfusiles: la del fusil, como antes (pedido)
		return pose_kind == "rifle" and not _one_hand and _wm != null and is_instance_valid(_wm.cargador) \
			and not _recarga_datos("rifle").is_empty()
	return _wm != null and not _recarga_datos(weapon_kind).is_empty()

static func _rv3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

static func _rquat(a, i: int = 0) -> Quaternion:
	return Quaternion(float(a[i]), float(a[i + 1]), float(a[i + 2]), float(a[i + 3])).normalized()

func _cargador_a_su_sitio(cg: Node3D) -> void:
	if cg:
		cg.visible = true
		# cada arma asienta su cargador donde diga SU ficha (armas.json), no donde lo ponia el fusil
		# de codigo de antes: con un asiento fijo el cargador del AK entraba por el aire
		var asiento: Vector3 = _wm.cargador_asiento if _wm else WeaponModelScript.CARGADOR_ASIENTO
		cg.transform = Transform3D(Basis.IDENTITY, asiento)

func _aplicar_recarga(dt: float, pose_kind: String, s: float) -> void:
	var cg: Node3D = _wm.cargador if _wm and is_instance_valid(_wm.cargador) else null
	var activa := _recarga_activa(pose_kind)
	if reloading and activa:
		if _recarga_t < 0.0:
			_recarga_t = 0.0
			_recarga_soltado = false
		elif dt > 0.0:
			_recarga_t += dt * float(_recarga_datos(weapon_kind if weapon_kind != "" else "rifle").get("dur", RECARGA_CLIP_S)) / maxf(reload_dur, 0.1)
	_recarga_w = move_toward(_recarga_w, 1.0 if reloading and activa else 0.0, 1.0 if dt <= 0.0 else 6.0 * dt)
	if _recarga_w <= 0.0 or _recarga_t < 0.0:
		_recarga_w = 0.0
		_recarga_t = -1.0
		_cargador_a_su_sitio(cg)
		return
	var d := _recarga_datos(weapon_kind if weapon_kind != "" else "rifle")
	if d.is_empty():
		return
	var n: int = int(d["frames"])
	# mano y cargador contados desde el asiento del cargador DE ESTA arma (las recargas generadas)
	var asiento := Vector3.ZERO
	if bool(d.get("relativo", false)) and _wm:
		asiento = _wm.cargador_asiento
	var fps: float = float(d.get("fps", 30.0))
	var fr: float = clampf(_recarga_t * fps, 0.0, float(n - 1))
	var i0: int = int(fr)
	var i1: int = mini(i0 + 1, n - 1)
	var k: float = fr - float(i0)
	var pos: Vector3 = _rv3(d["arma_pos"][i0]).lerp(_rv3(d["arma_pos"][i1]), k) / s
	var rot: Quaternion = _rquat(d["arma_rot"][i0]).slerp(_rquat(d["arma_rot"][i1]), k)
	var cuello: Vector3 = skeleton.get_bone_global_pose(bone_idx["neck"]).origin
	var w := smoothstep(0.0, 1.0, _recarga_w)
	weapon_root.transform = weapon_root.transform.interpolate_with(Transform3D(Basis(rot), cuello + pos), w)
	_recarga_mano = weapon_root.transform * ((_rv3(d["mano_izq"][i0]).lerp(_rv3(d["mano_izq"][i1]), k) + asiento) / s)
	# cortada a medias (cambio de arma): el cargador vuelve a su sitio sin esperar a que acabe la mezcla
	if not reloading:
		_cargador_a_su_sitio(cg)
		return
	if cg == null:
		return
	var m0 = d["mag"][i0]
	var m1 = d["mag"][i1]
	if m0 == null:
		cg.visible = false
	else:
		var mp: Vector3 = _rv3(m0)
		var mq: Quaternion = _rquat(m0, 3)
		if m1 != null:
			mp = mp.lerp(_rv3(m1), k)
			mq = mq.slerp(_rquat(m1, 3), k)
		mp += asiento
		cg.visible = true
		cg.transform = Transform3D(Basis(mq), mp)
	if not _recarga_soltado and fr >= float(d.get("suelta", n)) - 1.0:
		_recarga_soltado = true
		_soltar_cargador(cg, d)

## El cargador vacio se suelta: una copia en la escena con la velocidad que llevaba en la mano. El que
## esta en el arma se esconde y reaparece como el cargador nuevo cuando la mano lo saca de la funda.
func _soltar_cargador(cg: Node3D, d: Dictionary) -> void:
	if _first_person or not _body_visible or not is_inside_tree():
		return
	var escena := get_tree().current_scene
	if escena == null:
		return
	var i: int = int(d["suelta"]) - 1
	var vel := Vector3.ZERO
	if i >= 1 and d["mag"][i] != null and d["mag"][i - 1] != null:
		var dl: Vector3 = (_rv3(d["mag"][i]) - _rv3(d["mag"][i - 1])) * float(d.get("fps", 30.0)) * float(d.get("dur", RECARGA_CLIP_S)) / maxf(reload_dur, 0.1)
		vel = _wm.global_transform.basis * dl
	var caido: Node3D = CargadorCaidoScript.new()
	escena.add_child(caido)
	caido.global_transform = cg.global_transform.orthonormalized()
	var copia := cg.duplicate() as Node3D
	copia.transform = Transform3D.IDENTITY
	copia.visible = true
	caido.add_child(copia)
	caido.vel = vel
	caido.suelo_y = global_position.y


# ---------------------------------------------------------------------------
# CAIDA POR EXPLOSION (tools/blender/caida_anim.py). El cuerpo es un clip ("caida" en clips_breach.json)
# que NO se repite; el fusil colgado de la correa y las dos munecas (en el suelo, en la rodilla, de
# vuelta al arma) van en caida_arma.json y se aplican como en la recarga: moviendo el arma y los
# objetivos de la IK, que es lo que coloca los brazos en este rig.
# ---------------------------------------------------------------------------
const CAIDA_ARMA_PATH := "res://avatar/caida_arma.json"
static var _caida_arma: Dictionary = {}
static var _caida_leida := false
var sin_cabeza := false               ## player.gd: verse caer desde los ojos sin ver el casco por dentro
var _cabeza_encogida := false
var _caida_t := -1.0                 ## >= 0 mientras dura la caida
var _caida_reloj := 0.0              ## segundos de clip de la caida (se congela al acabar, para la mezcla)
var _caida_w := 0.0
var _caida_grip := Vector3.ZERO
var _caida_fore := Vector3.ZERO

static func _caida_datos() -> Dictionary:
	if not _caida_leida:
		_caida_leida = true
		var f := FileAccess.open(CAIDA_ARMA_PATH, FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if typeof(d) == TYPE_DICTIONARY and int(d.get("frames", 0)) > 1:
				_caida_arma = d
	return _caida_arma

## Tirado al suelo por una explosion. Mientras dura, drive_locomotion no cambia de clip.
func caer() -> void:
	if _caida_t >= 0.0 or not has_clip("caida"):
		return
	_caida_t = 0.0
	_caida_reloj = 0.0
	anim_speed = 1.0
	zancada = 1.0
	blend_time = 0.10
	play("caida", true)
	blend_time = 0.15

func cayendo() -> bool:
	return _caida_t >= 0.0


# ---------------------------------------------------------------------------
# SUBIR A UN BORDE (tools/blender/trepar_real_anim.py). El cuerpo lo lleva el clip "trepar": colgado
# del canto, las botas trepando por la pared con los brazos temblando, la rodilla al borde, de pie, un
# paso y el fusil de vuelta. El fusil y las munecas van en la pista del arma del clip (a la espalda
# mientras sube); mientras las palmas estan en el canto la IK del juego las clava al borde DE VERDAD
# (player.gd::_trepar -> agarrar_borde), que no siempre esta a la altura a la que se animo.
#
# Se reproduce a su velocidad (3 s) y player.gd mueve al jugador con la raiz del clip. En un muro
# mas bajo que el animado se entra a mitad (`desde`, ver trepar_inicio).
# ---------------------------------------------------------------------------
var _trepa_t := -1.0

func trepar(dur: float, desde: float = 0.0) -> void:
	if not has_clip("trepar"):
		return
	# EL ESCUDO, ESCONDIDO MIENTRAS SUBE (2026-10-15, pedido): vuelve en fin_trepar
	if _esc_root and is_instance_valid(_esc_root) and not _esc_soltado:
		_esc_root.visible = false
	var largo: float = clip_dur("trepar")
	desde = clampf(desde, 0.0, largo)
	_trepa_t = maxf(dur, 0.05)
	anim_speed = clampf((largo - desde) / maxf(dur, 0.05), 0.5, 4.0)
	zancada = 1.0
	blend_time = 0.08
	play("trepar", true)
	_time = desde
	blend_time = 0.15

## Segundo del clip de la subida en el que va, o -1 si no esta subiendo (para mandarlo por la red).
func trepar_reloj() -> float:
	return _time if _trepa_t >= 0.0 and current_clip == "trepar" else -1.0


## Esconder / volver a enseñar el escudo (los brazos de primera persona al trepar: player._trepar)
func escudo_visible(v: bool) -> void:
	if _esc_root and is_instance_valid(_esc_root) and not _esc_soltado and _esc_rotura < 0.0:
		_esc_root.visible = v


func trepando() -> bool:
	return _trepa_t >= 0.0


## Al acabar la subida se vuelve a lo de siempre (si no, el clip se quedaria congelado al final).
func fin_trepar() -> void:
	if _trepa_t >= 0.0 and _esc_root and is_instance_valid(_esc_root) and not _esc_soltado and _esc_rotura < 0.0 and _limp_t < 0.0:
		_esc_root.visible = true
	_trepa_t = -1.0
	anim_speed = 1.0

func _aplicar_caida(dt: float, s: float) -> void:
	_caida_w = move_toward(_caida_w, 1.0 if _caida_t >= 0.0 else 0.0, 1.0 if dt <= 0.0 else 8.0 * dt)
	if _caida_w <= 0.0:
		return
	var d := _caida_datos()
	if d.is_empty():
		_caida_w = 0.0
		return
	var n: int = int(d["frames"])
	var fr: float = clampf(_caida_reloj * float(d.get("fps", 30.0)), 0.0, float(n - 1))
	var i0: int = int(fr)
	var i1: int = mini(i0 + 1, n - 1)
	var k: float = fr - float(i0)
	var pos: Vector3 = _rv3(d["arma_pos"][i0]).lerp(_rv3(d["arma_pos"][i1]), k) / s
	var rot: Quaternion = _rquat(d["arma_rot"][i0]).slerp(_rquat(d["arma_rot"][i1]), k)
	var cuello: Vector3 = skeleton.get_bone_global_pose(bone_idx["neck"]).origin
	weapon_root.transform = weapon_root.transform.interpolate_with(Transform3D(Basis(rot), cuello + pos), smoothstep(0.0, 1.0, _caida_w))
	_caida_grip = weapon_root.transform * (_rv3(d["mano_gatillo"][i0]).lerp(_rv3(d["mano_gatillo"][i1]), k) / s)
	_caida_fore = weapon_root.transform * (_rv3(d["mano_apoyo"][i0]).lerp(_rv3(d["mano_apoyo"][i1]), k) / s)


# ---------------------------------------------------------------------------
# MAZAZO HECHO EN BLENDER (tools/blender/mazo_anim.py). Sustituye al de las tres poses mezcladas, que
# no hacia arco: iba en linea recta de una pose a otra y el cuerpo no participaba. Ahora el mazo
# recorre el arco de verdad (mazo.json, frame a frame a 60 fps) y el torso y la cabeza hacen el gesto
# del clip "mazazo" encima de lo que hagan las piernas, que siguen con su clip (andar, quieto...).
# El reloj es el de siempre (_swing_t, con el frenazo al acertar y la vuelta lenta al fallar).
# ---------------------------------------------------------------------------
const MAZO_PATH := "res://avatar/mazo.json"
const MAZO_HUESOS := ["stomach", "chest", "neck", "head", "hood"]
static var _mazo: Dictionary = {}
static var _mazo_leido := false
var _mazo_k := -1.0                  ## punto del golpe, 0 a 1

static func _mazo_datos() -> Dictionary:
	if not _mazo_leido:
		_mazo_leido = true
		var f := FileAccess.open(MAZO_PATH, FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if typeof(d) == TYPE_DICTIONARY and int(d.get("frames", 0)) > 1:
				_mazo = d
	return _mazo

static func mazo_disponible() -> bool:
	return not _mazo_datos().is_empty()

## Cuanto manda el mazazo en el punto `k`: entra al arrancar la carga y suelta al volver a la guardia.
static func _mazo_peso(k: float) -> float:
	return smoothstep(0.0, 0.12, k) * (1.0 - smoothstep(0.80, 1.0, k))

static func _mazo_muestra(pos_key: String, rot_key: String, k: float) -> Array:
	var d := _mazo_datos()
	var n: int = int(d["frames"])
	var fr: float = clampf(k * float(n - 1), 0.0, float(n - 1))
	var i0: int = int(fr)
	var i1: int = mini(i0 + 1, n - 1)
	var t: float = fr - float(i0)
	return [_rv3(d[pos_key][i0]).lerp(_rv3(d[pos_key][i1]), t), _rquat(d[rot_key][i0]).slerp(_rquat(d[rot_key][i1]), t)]

## El mazo en PRIMERA PERSONA en el punto `k` del golpe: [posicion, giro, peso], en el espacio de la
## camara. Lo usa player.gd para el arma que ve el jugador.
static func mazo_fp(k: float) -> Array:
	if not mazo_disponible():
		return []
	var m := _mazo_muestra("fp_pos", "fp_rot", k)
	return [m[0], m[1], _mazo_peso(k)]

func _mazazo_activo() -> bool:
	return _mazo_k >= 0.0 and (_swing_t > 0.0 or swing_scrub >= 0.0) and weapon_kind == "sledge"

func _aplicar_mazazo(s: float) -> void:
	if not _mazazo_activo() or not mazo_disponible():
		return
	var w := _mazo_peso(_mazo_k)
	if w <= 0.0:
		return
	var m := _mazo_muestra("tp_pos", "tp_rot", _mazo_k)
	var cuello: Vector3 = skeleton.get_bone_global_pose(bone_idx["neck"]).origin
	weapon_root.transform = weapon_root.transform.interpolate_with(Transform3D(Basis(m[1]), cuello + (m[0] as Vector3) / s), w)

# ---------------------------------------------------------------------------
# SENTADO EN UN VEHICULO
#
# No es un clip: es una pose que se pone ENCIMA de lo que haya (normalmente el reposo), doblando caderas
# y rodillas. Asi el mismo personaje vale dentro y fuera del coche sin animar nada nuevo, y funciona
# igual en el jugador, en los remotos y en los bots.
#
# Lo pone el vehiculo (vehiculo.gd) cada cuadro: `sentado` sube a 1 al subirte y baja a 0 al bajarte, y
# `sentado_volante` dice si las manos van al volante (conductor) o caidas en las piernas (pasajero).
# ---------------------------------------------------------------------------

var sentado := 0.0              ## 0 de pie, 1 sentado del todo
var sentado_volante := false    ## manos al volante (conductor) o en las piernas (pasajero)

## Cuanto dobla cada cosa al sentarse (grados). La cadera casi 90, la rodilla un poco menos, y los pies
## apoyados; es la postura de alguien en un asiento de coche, no en una silla de oficina.
const SENT_CADERA := -82.0
const SENT_RODILLA := 72.0
const SENT_TOBILLO := 10.0
const SENT_BRAZO_VOLANTE := -62.0
const SENT_ANTEBRAZO_VOLANTE := -38.0
const SENT_BRAZO_PASAJERO := -18.0


## Gira un hueso `grados` sobre un eje del MUNDO, mezclando con lo que ya tenia. Es el mismo camino que
## usan las manos de la pista: se calcula en global y se pasa al espacio del padre.
func _girar_hueso(nombre: String, eje: Vector3, grados: float, w: float) -> void:
	if w <= 0.001 or not bone_idx.has(nombre):
		return
	var hi: int = bone_idx[nombre]
	var padre := skeleton.get_bone_parent(hi)
	if padre < 0:
		return
	var g_padre := Quaternion(skeleton.get_bone_global_pose(padre).basis.orthonormalized())
	var g_actual := Quaternion(skeleton.get_bone_global_pose(hi).basis.orthonormalized())
	var quiere := (Quaternion(eje.normalized(), deg_to_rad(grados)) * g_actual).normalized()
	var local := skeleton.get_bone_pose_rotation(hi)
	skeleton.set_bone_pose_rotation(hi, local.slerp((g_padre.inverse() * quiere).normalized(), w).normalized())


func _aplicar_sentado() -> void:
	if sentado <= 0.001 or skeleton == null:
		return
	var w: float = clampf(sentado, 0.0, 1.0)
	for lado in ["_l", "_r"]:
		_girar_hueso("leg_upper" + lado, Vector3.RIGHT, SENT_CADERA, w)
		_girar_hueso("leg_lower" + lado, Vector3.RIGHT, SENT_RODILLA, w)
		_girar_hueso("foot" + lado, Vector3.RIGHT, SENT_TOBILLO, w)
		var brazo: float = SENT_BRAZO_VOLANTE if sentado_volante else SENT_BRAZO_PASAJERO
		_girar_hueso("arm_upper" + lado, Vector3.RIGHT, brazo, w)
		if sentado_volante:
			_girar_hueso("arm_lower" + lado, Vector3.RIGHT, SENT_ANTEBRAZO_VOLANTE, w)


func _aplicar_mazazo_cuerpo() -> void:
	if not _mazazo_activo() or not _shared_clips.has("mazazo"):
		return
	var w := _mazo_peso(_mazo_k)
	if w <= 0.0:
		return
	var bk := _baked("mazazo")
	var t: float = _mazo_k * float(bk["dur"])
	for bname in MAZO_HUESOS:
		if bone_idx.has(bname) and bk["bones"].has(bname):
			var i: int = bone_idx[bname]
			skeleton.set_bone_pose_rotation(i, skeleton.get_bone_pose_rotation(i).slerp(_sample_baked(bk["bones"][bname], t), w))


# ---------------------------------------------------------------------------
# ESCUDO BALISTICO + PISTOLA (escudo.gd; animado en tools/blender/escudo_anim.py). Como el mazazo y la
# recarga, de Blender no vienen los huesos de los brazos: vienen el ESCUDO y la PISTOLA respecto al cuello
# y las dos munecas, y la IK de siempre coloca los brazos. El torso y la cabeza van con los clips escudo_*
# de clips_breach.json encima de lo que hagan las piernas; quieto, el cuerpo entero es la guardia.
# ---------------------------------------------------------------------------
const EscudoScript := preload("res://scripts/escudo.gd")
const ESCUDO_TORSO := ["stomach", "chest", "hood", "neck", "head"]
const ESCUDO_PIERNAS := ["pelvis", "leg_upper_l", "leg_lower_l", "foot_l", "toes_l",
	"leg_upper_r", "leg_lower_r", "foot_r", "toes_r"]
var _esc_root: Node3D = null         ## el escudo en la mano: cuelga del esqueleto, como el arma
var _esc_e := {}                     ## el estado de este frame (ver EscudoScript.pose)
var _esc_guardia := 0.0              ## reloj de la guardia, s
var _esc_apunta := 0.0               ## 0..1: por donde va el camino de sacar la pistola por el canto
var _esc_disparo := -1.0             ## 0..1 mientras dura cada gesto; -1 = no esta pasando
var _esc_impacto := -1.0
var _esc_recarga := -1.0
var _esc_rotura := -1.0
var _esc_soltado := false            ## el escudo roto ya salio de la mano
var _esc_prev := Transform3D.IDENTITY
var _esc_mag_soltado := false        ## en esta recarga ya cayo el cargador vacio
## El dueño mantiene el gatillo: saca la pistola aunque no apunte (player.gd espera a que salga para tirar).
var escudo_sacar := false
## lo maneja el JUGADOR de esta maquina con el boton (player.gd): entonces el gatillo suelto la esconde en el acto, sin el
## "encarar tras el tiro" (que queda para los bots y las copias de red, que no mandan el boton)
var escudo_por_boton := false
var _esc_aim_prev := false
var _esc_sin_encara := false
var _esc_mano_der := Vector3.ZERO    ## objetivos de la IK, en el esqueleto
var _esc_mano_izq := Vector3.ZERO


func escudo_activo() -> bool:
	return weapon_kind == "escudo" and not _external_weapon and EscudoScript.disponible()


## El estado de este frame. Lo lee player.gd para mover la vista en primera persona al mismo compas.
func escudo_estado() -> Dictionary:
	return _esc_e


func escudo_soltado() -> bool:
	return _esc_soltado


## Le han dado al escudo: el brazo encaja el golpe y se recoloca.
func escudo_golpe() -> void:
	if weapon_kind == "escudo" and _esc_rotura < 0.0:
		_esc_impacto = 0.0


## Se ha roto: se suelta, cae, y la mano libre va a la pistola.
func escudo_romper() -> void:
	if weapon_kind == "escudo" and _esc_rotura < 0.0:
		_esc_rotura = 0.0
		_esc_soltado = false
		_esc_impacto = -1.0


func _quitar_escudo() -> void:
	if _esc_root and is_instance_valid(_esc_root):
		_esc_root.queue_free()
	_esc_root = null
	_esc_e = {}
	_esc_apunta = 0.0
	_esc_disparo = -1.0
	_esc_impacto = -1.0
	_esc_recarga = -1.0
	_esc_rotura = -1.0
	_esc_soltado = false


## El modelo trae el escudo como hijo de la pistola (weapon_model._build_escudo): se pasa a su propio nodo
## del esqueleto, porque cada uno va en una mano.
func _montar_escudo() -> void:
	if _wm == null or not is_instance_valid(_wm) or _wm.escudo_nodo == null or not is_instance_valid(_wm.escudo_nodo):
		return
	_esc_root = Node3D.new()
	_esc_root.name = "Escudo"
	skeleton.add_child(_esc_root)
	var n: Node3D = _wm.escudo_nodo
	n.get_parent().remove_child(n)
	_esc_root.add_child(n)
	n.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE / scale.x), Vector3.ZERO)
	var modo := (GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if _first_person or not _body_visible
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = modo


## Metros que se adelanta el escudo hacia su frente. 0 en la partida; la armeria (camara al pecho, muy cerca) lo
## separa un poco para que la esquina de la manga no asome por la plancha.
var escudo_delante := 0.0


static func _esc_avanza(k: float, dt: float, clip: String) -> float:
	if k < 0.0:
		return k
	k += dt / maxf(EscudoScript.duracion(clip), 0.05)
	return -1.0 if k > 1.0 else k


func _escudo_tick(dt: float) -> void:
	_esc_guardia = _time if current_clip == "escudo_guardia" else _esc_guardia + dt
	# SACAR LA PISTOLA: apuntando y al disparar (como el encarar de los fusiles). En la recarga y la rotura no
	# AL SOLTAR APUNTAR SE ESCONDE YA (2026-09-23, pedido): el "encarar tras el tiro" la dejaba fuera 0,54 s mas
	# y luego tardaba 0,5 s en volver; casi un segundo con la pistola asomada. Soltar apuntar anula esa espera
	# hasta el siguiente disparo.
	if _esc_aim_prev and not aiming:
		_esc_sin_encara = true
	if _since_fire < dt * 2.0 and not aiming:
		_esc_sin_encara = false   # disparo nuevo sin apuntar: vuelve el encarar normal
	_esc_aim_prev = aiming
	var tras_tiro: bool = _since_fire < TIRO_ENCARA * 0.6 and not _esc_sin_encara
	# (2026-10-16, bug: "disparando mucho con la pistola, al soltar el boton sigue apuntando medio segundo"): con el boton
	# del jugador, soltar = volver detras del escudo ya; el "encarar tras el tiro" (0,54 s) solo para bots y copias de red
	if escudo_por_boton:
		tras_tiro = false
	var encara: bool = (aiming or escudo_sacar or tras_tiro) and _esc_recarga < 0.0 and _esc_rotura < 0.0
	# asomarla por el canto dura lo que el clip (0,33 s); esconderla, lo mismo
	var d_ap: float = maxf(EscudoScript.duracion("apuntar"), 0.05)
	_esc_apunta = move_toward(_esc_apunta, 1.0 if encara else 0.0, dt / d_ap)
	_esc_disparo = _esc_avanza(_esc_disparo, dt, "disparo")
	_esc_impacto = _esc_avanza(_esc_impacto, dt, "impacto")
	if reloading and _esc_rotura < 0.0:
		# la recarga se estira a lo que dura la del arma
		_esc_recarga = 0.0 if _esc_recarga < 0.0 else minf(_esc_recarga + dt / maxf(reload_dur, 0.1), 1.0)
	else:
		_esc_recarga = -1.0
	if _esc_rotura >= 0.0:
		# se queda en el ultimo frame hasta que el dueño cambia a la pistola sola
		_esc_rotura = minf(_esc_rotura + dt / maxf(EscudoScript.duracion("rotura"), 0.05), 1.0)
	_esc_e = {"guardia": _esc_guardia, "apunta": _esc_apunta, "disparo": _esc_disparo,
		"impacto": _esc_impacto, "recarga": _esc_recarga, "rotura": _esc_rotura}


func _aplicar_escudo_cuerpo(dt: float) -> void:
	if not escudo_activo():
		return
	_escudo_tick(dt)
	# quieto, los gestos mueven tambien los pies (el paso atras al encajar un golpe); andando, las piernas
	# son del clip de andar
	var pies: float = (1.0 - clampf(move_amount * 3.0, 0.0, 1.0)) if current_clip == "escudo_guardia" else 0.0
	var i_pel: int = bone_idx.get("pelvis", -1)
	for capa in EscudoScript.capas_cuerpo(_esc_e):
		var nombre: String = capa[0]
		var w: float = float(capa[2])
		if w <= 0.001 or not _shared_clips.has(nombre):
			continue
		var t: float = float(capa[1])
		var huesos: Dictionary = _baked(nombre)["bones"]
		if pies > 0.0 and nombre != "escudo_guardia":
			for bname in ESCUDO_PIERNAS:
				if bone_idx.has(bname) and huesos.has(bname):
					var i: int = bone_idx[bname]
					skeleton.set_bone_pose_rotation(i, skeleton.get_bone_pose_rotation(i).slerp(
						_sample_baked(huesos[bname], t), w * pies))
		for bname in ESCUDO_TORSO:
			if not (bone_idx.has(bname) and huesos.has(bname)):
				continue
			var i: int = bone_idx[bname]
			var q: Quaternion = _sample_baked(huesos[bname], t)
			# EL PECHO MIRA A DONDE MIRABA EN BLENDER, lleve la cadera el clip que lleve. En la guardia la
			# pelvis va girada 24 grados y el abdomen lo compensa; andando la cadera va de frente, y con el
			# giro del abdomen tal cual el pecho se iba de lado. Se pone en global respecto a la pelvis del clip.
			if bname == "stomach" and i_pel >= 0 and huesos.has("pelvis"):
				q = (skeleton.get_bone_pose_rotation(i_pel).inverse() * _sample_baked(huesos["pelvis"], t) * q).normalized()
			skeleton.set_bone_pose_rotation(i, skeleton.get_bone_pose_rotation(i).slerp(q, w).normalized())


func _aplicar_escudo(dt: float) -> void:
	var s := scale.x
	_since_fire += dt
	_pista_w = 0.0
	_pista = {}
	_recarga_w = 0.0
	if _esc_root != null and not is_instance_valid(_esc_root):
		_esc_root = null
	if _esc_root == null:
		_montar_escudo()
	if dt <= 0.0:
		# hojas de poses / recien equipado: sin transicion
		_esc_apunta = 1.0 if aiming else 0.0
		_esc_e["guardia"] = _esc_guardia
		_esc_e["apunta"] = _esc_apunta
	var p := EscudoScript.pose(_esc_e)
	if p.is_empty():
		return
	var cuello: Vector3 = skeleton.get_bone_global_pose(bone_idx["neck"]).origin
	# LA MIRADA: todo gira con el cabeceo alrededor del cuello. Con la pistola fuera, entero (se apunta
	# donde se mira); en guardia a medias: mirando al cielo no se sube el escudo por encima de la cabeza
	var objetivo: float = look_pitch * lerpf(0.55, 1.0, _esc_apunta)
	_mira_pitch = objetivo if dt <= 0.0 else lerpf(_mira_pitch, objetivo, 1.0 - pow(2.0, -16.0 * dt))
	var giro := Quaternion(Vector3.RIGHT, _mira_pitch)
	if look_sway.length_squared() > 1e-8:
		giro = (Quaternion(Vector3.UP, -look_sway.x * LOOK_SWAY_ROT)
			* Quaternion(Vector3.RIGHT, -look_sway.y * LOOK_SWAY_ROT) * giro).normalized()
	var pis: Array = p["pis_tp"]
	var esc: Array = p["esc_tp"]
	weapon_root.transform = Transform3D(Basis((giro * (pis[1] as Quaternion)).normalized()), cuello + giro * ((pis[0] as Vector3) / s))
	_escudo_cargador()
	_esc_mano_der = cuello + giro * ((p["mano_der"][0] as Vector3) / s)
	_esc_mano_izq = cuello + giro * ((p["mano_izq"][0] as Vector3) / s)
	if _esc_root == null:
		return
	var xf := Transform3D(Basis((giro * (esc[1] as Quaternion)).normalized()), cuello + giro * ((esc[0] as Vector3) / s))
	if escudo_delante != 0.0:
		xf.origin += xf.basis * Vector3(0.0, 0.0, -escudo_delante / s)
	_esc_root.transform = xf
	# LA ROTURA: en el frame en que la mano suelta el asa, el escudo pasa a ser un cuerpo que cae con la
	# velocidad que llevaba
	if _esc_rotura >= 0.0 and not _esc_soltado and float(p["mano_izq"][1]) >= 0.5 and dt > 0.0:
		var ahora: Vector3 = (skeleton.global_transform * xf).origin
		var antes: Vector3 = (skeleton.global_transform * _esc_prev).origin
		_soltar_escudo((ahora - antes) / maxf(dt, 1.0 / 60.0))
	_esc_prev = xf


## El cargador de la pistola durante la recarga: cae el vacio, y el nuevo va de la funda a la mano y al arma.
func _escudo_cargador() -> void:
	var cg: Node3D = _wm.cargador if _wm and is_instance_valid(_wm.cargador) else null
	if cg == null:
		return
	var k: float = float(_esc_e.get("recarga", -1.0))
	if k < 0.0:
		_esc_mag_soltado = false
		cg.visible = true
		cg.transform = Transform3D(Basis.IDENTITY, _wm.cargador_asiento)
		return
	var xf = EscudoScript.cargador(k, _wm.cargador_asiento)
	if xf != null:
		cg.visible = true
		cg.transform = xf
		return
	if not _esc_mag_soltado:
		_esc_mag_soltado = true
		if not _first_person and _body_visible and is_inside_tree() and get_tree().current_scene:
			var caido: Node3D = CargadorCaidoScript.new()
			get_tree().current_scene.add_child(caido)
			caido.global_transform = cg.global_transform.orthonormalized()
			var copia := cg.duplicate() as Node3D
			copia.transform = Transform3D.IDENTITY
			copia.visible = true
			caido.add_child(copia)
			caido.vel = global_transform.basis.orthonormalized() * Vector3(0.3, -0.6, 0.0)
			caido.suelo_y = global_position.y
	cg.visible = false


func _soltar_escudo(vel: Vector3) -> void:
	_esc_soltado = true
	if _esc_root == null or not is_instance_valid(_esc_root):
		return
	_esc_root.visible = false
	if not is_inside_tree() or get_tree().current_scene == null:
		return
	var g: Transform3D = _esc_root.global_transform
	EscudoScript.soltar(get_tree().current_scene, Transform3D(g.basis.orthonormalized(), g.origin), vel.limit_length(4.0))


func _process(delta: float) -> void:
	var _ta := Time.get_ticks_usec()
	_process_inner(delta)
	_blob_tick(delta)
	Prof.add("avatar", Time.get_ticks_usec() - _ta)


static var _prof_av := "--botsprof" in OS.get_cmdline_user_args()

## LA MANCHA DE SOMBRA (sombra_blob.gd): solo en partida, solo si el sol no da sombra (el movil) y no en los brazos de
## primera persona. Se mira una vez por segundo.
static var _sin_mancha: bool = "--sinmancha" in OS.get_cmdline_user_args()
var _blob: Node3D = null
var _blob_t := 0.0
static var _blob_avisado := false

func _blob_tick(dt: float) -> void:
	_blob_t -= dt
	if _blob_t > 0.0:
		return
	_blob_t = 0.25
	var juego = Net.game
	# la tuya en primera persona no: en el movil se veia como una mancha oscura delante (bug con captura)
	var quiere := not _sin_mancha and not _arms_only and not _first_person and juego != null and is_instance_valid(juego)
	if quiere:
		var sol = juego.get("sun")
		quiere = sol != null and is_instance_valid(sol) and not (sol as DirectionalLight3D).shadow_enabled
	if quiere and _blob == null:
		_blob = preload("res://scripts/sombra_blob.gd").new()
		_blob.cuerpo = self
		add_child(_blob)
		if not _blob_avisado:
			_blob_avisado = true
			print("[mancha] sombra bajo los personajes (el sol no da sombra)")
	elif not quiere and _blob != null:
		_blob.queue_free()
		_blob = null

func _process_inner(delta: float) -> void:
	var _tpa := Time.get_ticks_usec()
	_lanzar_tick(delta)
	_lanzar_piezas()
	_gesto_tick(delta)
	_gesto_piezas()
	_invis_tick(delta)
	_traje_tick(delta)
	_forcejeo_reponer()
	_colocar_fuego()
	if _prof_av:
		Prof.add("av.p.gestos", Time.get_ticks_usec() - _tpa)
		_tpa = Time.get_ticks_usec()
	if _limp_t >= 0.0 and skeleton != null:
		_apply_limp(delta)          # muerto: solo se desploma, nada de clips ni IK
		return
	if current_clip == "" or not _shared_clips.has(current_clip) or skeleton == null:
		return
	# Los bots se animan a menos Hz según la distancia (cerca 30 Hz, 15 m: 20 Hz, 40 m: 8 Hz) y NADA cuando
	# están fuera del encuadre: la actualización del esqueleto + skinning de 10 personajes a 60 Hz era la
	# principal fuente de tirones (130 frames >22 ms por minuto con avatares, 7 sin ellos). El jugador (sombra
	# y brazos) sigue a 60 Hz. delta acumulado para no perder tiempo de animación.
	# ESCALONADOS (2026-10-01): todos los bots aparecen en el mismo fotograma y reciben el mismo delta, asi que sin
	# esto se animaban TODOS en el mismo fotograma (a 60 fps y 30 Hz: uno con los 10 esqueletos y el siguiente con
	# ninguno), un vaiven de varios ms de un fotograma a otro. Cada uno arranca con una fase distinta y la conserva.
	if not _escalonado:
		_escalonado = true
		if not _sin_escalonar:
			_skip_acc = randf() * (1.0 / 30.0)
	_skip_acc += delta
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam and not _first_person and not _arms_only and not anim_siempre:
		var d := cam.global_position.distance_squared_to(global_position)
		var period := 1.0 / 30.0 if d < 225.0 else (1.0 / 20.0 if d < 1600.0 else 1.0 / 8.0)
		# EN EL MOVIL, MENOS AUN (2026-10-13, pedido: "optimiza los muñecos"): cerca 24 Hz, a 15 m 15 y a 40 m 6
		if _movil_anim < 0:
			_movil_anim = 1 if (Settings.is_mobile() or "--animmovil" in OS.get_cmdline_user_args()) else 0
		if _movil_anim == 1:
			period *= 1.3
		# DE CERCA, CADA CUADRO (2026-10-28, bug: "la animacion de los bots no es fluida, va como 2 frames atras y adelante"):
		# a 30 Hz con la pantalla a 60 o mas cada pose se veia dos cuadros y correr o disparar salia a saltos. A menos de
		# ANIM_CERCA_M se anima en cada cuadro (en el movil, a 45 Hz). Son pocos a la vez. `--botsanim30` = como antes.
		if d < ANIM_CERCA_M * ANIM_CERCA_M and not _anim30:
			period = 0.0 if _movil_anim == 0 else 1.0 / 45.0
		# UN MAZAZO NO SE PUEDE BAJAR DE HZ. Dura 0,4 s: a 30 Hz salen 12 poses para un arco de mas
		# de metro y medio, o sea la cabeza de hierro saltando de 40 en 40 cm y hasta 1,2 m de una
		# vez. Mientras dura el golpe, y de cerca, se anima a la tasa de la pantalla; son 0,4 s y un
		# solo personaje, no es lo que carga la CPU.
		if _swing_t > 0.0 and d < 900.0:
			period = 0.0
		# LA MIRADA EN CASCADA compensa el giro del nodo dentro del esqueleto: si el nodo ha girado desde la ultima pose,
		# saltarse este cuadro dibujaria el cuerpo girado de golpe (marcha_viva.gd)
		if _mv != null and _mv.w > 0.01 and absf(wrapf(global_basis.get_euler().y - _mv_yaw_pose, -PI, PI)) > 0.035:
			period = 0.0
		if _skip_acc < period:
			return
		# fuera del encuadre (con margen): no tocar el esqueleto
		if d > 16.0 and not cam.is_position_in_frustum(global_position + Vector3(0, 0.9, 0)) and not cam.is_position_in_frustum(global_position + Vector3(0, 1.7, 0)):
			return
	delta = _skip_acc
	_skip_acc = 0.0
	_time += delta * anim_speed * (0.0 if pausa_clip else 1.0)
	var baked := _baked(current_clip)
	var duration: float = baked["dur"]
	# LOS CLIPS DE UN SOLO USO SE QUEDAN EN SU ULTIMO FOTOGRAMA. Antes solo la caida hacia esto y todo
	# lo demas daba la vuelta con fmod: por eso al acabar de trepar el muñeco volvia a empezar el
	# gesto una y otra vez. Andar, correr y estar quieto SI dan la vuelta, que para eso son ciclos.
	if CLIPS_UNA_VEZ.has(current_clip):
		if _time >= duration:
			_time = duration
			if current_clip == "caida":
				_caida_t = -1.0
			elif current_clip == "trepar":
				_trepa_t = -1.0
			elif current_clip == "punetazo":
				_punio_t = -1.0
		if current_clip == "caida":
			_caida_reloj = _time
	elif duration > 0.0:
		_time = fmod(_time, duration)
	if _blend_from != "":
		_blend_time += delta
		if _blend_time >= _blend_duration:
			_blend_from = ""
	_gancho_reponer()
	var cb: Dictionary = baked["bones"]
	var pbaked: Dictionary = _baked(_blend_from) if _blend_from != "" else {}
	var pb: Dictionary = pbaked["bones"] if _blend_from != "" else {}
	var bw := clampf(_blend_time / _blend_duration, 0.0, 1.0)
	# el fotograma de cada clip, buscado una vez (si sus huesos comparten instantes: ver _baked)
	var mc: Array = _muestra_comun(baked["t_comun"], _time) if baked.has("t_comun") else []
	var mp: Array = _muestra_comun(pbaked["t_comun"], _blend_prev_time) if _blend_from != "" and pbaked.has("t_comun") else []
	if _huesos_lista.size() != bone_idx.size():
		_huesos_lista = bone_idx.keys()
	var por_c := false
	if _anim_c != null and not mc.is_empty() and baked.has("qflat") and (_blend_from == "" or (not mp.is_empty() and pbaked.has("qflat"))):
		if _casillas.size() != _shared_bone_order.size():
			_preparar_casillas()
		por_c = _casillas_ok
	if por_c:
		var vacio_f := PackedFloat32Array()
		var vacio_b := PackedByteArray()
		var mezcla := _blend_from != ""
		_anim_c.posar(skeleton, _casillas, baked["qflat"], baked["qmask"], int(mc[1]), float(mc[2]),
			mezcla, pbaked["qflat"] if mezcla else vacio_f, pbaked["qmask"] if mezcla else vacio_b,
			int(mp[1]) if mezcla else 0, float(mp[2]) if mezcla else 0.0, bw)
		if _prueba_c:
			_comparar_c(cb, pb, mc, mp, bw)
		# lo que solo toca a unos huesos, sobre la pose que acaba de poner (igual que el bucle de abajo)
		var con_zancada := zancada > 1.001
		var con_codo := not _codo_recto.is_empty() and current_clip.begins_with("idle")
		if con_zancada or con_codo:
			for bname in (_HUESOS_RETOQUE if not con_codo else _HUESOS_RETOQUE + _codo_recto.keys()):
				if not bone_idx.has(bname) or not cb.has(bname):
					continue
				var bi: int = bone_idx[bname]
				var q2: Quaternion = skeleton.get_bone_pose_rotation(bi)
				if con_zancada and HUESOS_ZANCADA.has(bname):
					var reposo2: Quaternion = _shared_bind.get(bname, Quaternion.IDENTITY)
					var t2: float = zancada
					if HUESOS_RODILLA.has(bname):
						var dobla2: float = 2.0 * acos(clampf(absf((reposo2.inverse() * q2).w), 0.0, 1.0))
						t2 = clampf(RODILLA_MAX / maxf(dobla2, 0.001), 1.0, zancada)
					q2 = reposo2.slerp(q2, t2).normalized()
				if con_codo and _codo_recto.has(bname):
					q2 = q2.slerp(_shared_bind.get(bname, Quaternion.IDENTITY), float(_codo_recto[bname])).normalized()
				skeleton.set_bone_pose_rotation(bi, q2)
	for bname in ([] if por_c else _huesos_lista):
		var bc = cb.get(bname)
		if bc == null:
			continue
		var q: Quaternion = _muestra_con(bc, mc) if not mc.is_empty() else _sample_baked(bc, _time)
		if _blend_from != "":
			var bp = pb.get(bname)
			if bp != null:
				q = (_muestra_con(bp, mp) if not mp.is_empty() else _sample_baked(bp, _blend_prev_time)).slerp(q, bw)
		# ZANCADA ELASTICA: se exagera el giro de la pierna alejandolo de su postura de reposo. Un
		# slerp con t > 1 extrapola, que es exactamente "lo mismo, pero mas": la rodilla flexiona en
		# el eje que ya flexionaba, sin inventarse una direccion nueva.
		if zancada > 1.001 and HUESOS_ZANCADA.has(bname):
			var reposo: Quaternion = _shared_bind.get(bname, Quaternion.IDENTITY)
			var t: float = zancada
			if HUESOS_RODILLA.has(bname):
				# lo que dobla ya la rodilla (desde la pierna recta) y cuanto se le deja exagerar
				var dobla: float = 2.0 * acos(clampf(absf((reposo.inverse() * q).w), 0.0, 1.0))
				t = clampf(RODILLA_MAX / maxf(dobla, 0.001), 1.0, zancada)
			q = reposo.slerp(q, t).normalized()
		# EL BRAZO RECTO EN REPOSO, por skin (receta "codo_recto": hueso -> cuanto se endereza). El Puño de Oro, con su
		# guantelete enorme, en el reposo doblaba el antebrazo hacia el cuerpo y parecia el codo roto (2026-09-30)
		if _codo_recto.has(bname) and current_clip.begins_with("idle"):
			q = q.slerp(_shared_bind.get(bname, Quaternion.IDENTITY), float(_codo_recto[bname])).normalized()
		skeleton.set_bone_pose_rotation(bone_idx[bname], q)
	# VAIVEN DE LA PELVIS de los clips hechos en Blender; al volver a un clip del .bin, a su sitio
	if bone_idx.has("pelvis"):
		var con_pelvis := _clip_pelvis.has(current_clip) or (_blend_from != "" and _clip_pelvis.has(_blend_from))
		if con_pelvis or _pelvis_movida:
			var off := _pelvis_off(current_clip, _time)
			if _blend_from != "":
				off = _pelvis_off(_blend_from, _blend_prev_time).lerp(off, bw)
			skeleton.set_bone_pose_position(bone_idx["pelvis"], _shared_rest_local["pelvis"] + off)
			_pelvis_movida = con_pelvis
	_aplicar_mazazo_cuerpo()
	_aplicar_sentado()
	_aplicar_escudo_cuerpo(delta)
	_aplicar_gancho_cuerpo(delta)
	# bajar/subir el esqueleto para que el pie más bajo del clip toque el suelo (ver _baked)
	var ground: float = 0.0 if current_clip == "salto_aire" else float(baked["ground"])
	if _blend_from != "":
		ground = lerpf(0.0 if _blend_from == "salto_aire" else float(_baked(_blend_from)["ground"]), ground, bw)
	skeleton.position.y = ground
	if _prof_av:
		Prof.add("av.p.clip", Time.get_ticks_usec() - _tpa)
		_tpa = Time.get_ticks_usec()
	_marcha_viva(delta)
	if _prof_av:
		Prof.add("av.p.marcha", Time.get_ticks_usec() - _tpa)
		_tpa = Time.get_ticks_usec()
	var _t0 := Time.get_ticks_usec()
	_apply_spine(delta)
	if _prof_av:
		Prof.add("av.p.espalda", Time.get_ticks_usec() - _tpa)
		_tpa = Time.get_ticks_usec()
	_arma_con_pecho(0.0)
	_update_rifle_transform(delta)
	_arma_con_pecho(_mv.arma_yaw if _mv != null else 0.0)
	if _prof_av:
		Prof.add("av.p.arma", Time.get_ticks_usec() - _tpa)
		_tpa = Time.get_ticks_usec()
	_punio_brazos(delta)
	_aplicar_forcejeo(delta)
	_aplicar_rescate_vivo(delta)
	if _prof_av:
		Prof.add("av.p.resto", Time.get_ticks_usec() - _tpa)
	# AL FINAL DEL TODO. Cada frame se reponen los huesos con el clip de animacion, asi que si el
	# parpado se coloca antes (dentro del calculo de la pose del arma) esa reposicion se lo lleva
	# por delante y el ojo no se cierra nunca.
	_mover_parpados(delta)
	if _probe:
		_probe_us += Time.get_ticks_usec() - _t0
		_probe_n += 1
		if _probe_n >= 600:
			print("[avatar] torso+arma+IK: %.3f ms por avatar y frame" % (_probe_us / 1000.0 / _probe_n))
			_probe_us = 0
			_probe_n = 0

# ---------------------------------------------------------------------------------------------------
# LA MARCHA VIVA Y LA MIRADA EN CASCADA (2026-10-28): marcha_viva.gd. Solo en partida (en los menus el muñeco posa) y
# no en los brazos ni en el cuerpo de primera persona (este solo da sombra). `--marchaviva` la fuerza fuera de partida
# (bancos de fotos).
# ---------------------------------------------------------------------------------------------------
const MarchaViva := preload("res://scripts/marcha_viva.gd")
static var _marcha_forzada: bool = "--marchaviva" in OS.get_cmdline_user_args()
var _mv = null
var _mv_lvel := Vector3.ZERO
var _mv_crouch := false
var _mv_suelo := true
var _mv_y_prev := INF
var _mv_vy := 0.0                  ## la velocidad hacia abajo mas rapida de la caida en curso (para el aterrizaje)
var _mv_en_juego := -1             ## -1 sin mirar, 0 no, 1 si (se mira una vez por segundo)
var _mv_mirar_t := 0.0
var _arma_yaw_puesto := 0.0
var _mv_yaw_pose := 0.0
var _arma_yaw_nodo: Node3D = null

func _marcha_viva(dt: float) -> void:
	if MarchaViva.apagada or _arms_only or skeleton == null:
		return
	_mv_mirar_t -= dt
	if _mv_mirar_t <= 0.0:
		_mv_mirar_t = 1.0
		var j = Net.game
		_mv_en_juego = 1 if _marcha_forzada or (j != null and is_instance_valid(j) and (j as Node).is_ancestor_of(self)) else 0
	if _mv_en_juego != 1 or _first_person:
		if _mv != null:
			_mv.soltar_cadera()
			_mv.reiniciar()
			_mv.w = 0.0
		return
	if _mv == null:
		_mv = MarchaViva.new(self)
		# los bots miran alrededor cuando no pelean (su nodo es un BotBase)
		var dueno := get_parent()
		_mv.mirada_libre = dueno != null and dueno.has_method("c_tick")
	# lo rapido que cae (la velocidad que llega por drive_locomotion no trae la vertical): la mas rapida de este vuelo
	var y_ahora: float = global_position.y
	if not _mv_suelo and dt > 0.0 and is_finite(_mv_y_prev):
		_mv_vy = minf(_mv_vy, (y_ahora - _mv_y_prev) / dt)
	_mv_y_prev = y_ahora
	var c := current_clip
	var de_pie: bool = c.begins_with("run") or c.begins_with("caminar") or c.begins_with("idle") or c.begins_with("turn") 		or c.begins_with("crouch") or c == "subir_escalera" or c == "bajar_escalera" or c == "jump_land"
	var permitido: bool = de_pie and _caida_t < 0.0 and _trepa_t < 0.0 and _punio_t < 0.0 		and _salto_fase == "" and clip_rescate == "" and _limp_t < 0.0 and sentado <= 0.01 and not forcejeo 		and _gancho_w <= 0.01 and pose_menu.is_empty() and not escudo_activo() and _gesto == ""
	var pelea: bool = aiming or _aim_w > 0.05 or _since_fire < 1.4 or _swing_t > 0.0 or reloading
	_mv.paso(dt, permitido, _mv_lvel, _mv_suelo, _mv_crouch, pelea)
	_mv_yaw_pose = global_basis.get_euler().y


## EL ARMA VA CON EL PECHO: la pose del arma se calcula en el marco del esqueleto (mirando al frente); la mirada en
## cascada gira el pecho y el arma tiene que ir con el. Se gira sobre el cuello ANTES de la IK de los brazos y se deshace
## antes de volver a calcularla (algunas pistas mezclan con la transformada del cuadro anterior).
func _arma_con_pecho(yaw: float) -> void:
	if _arma_yaw_nodo != null and is_instance_valid(_arma_yaw_nodo) and absf(_arma_yaw_puesto) > 0.00001 			and _arma_yaw_nodo == weapon_root and bone_idx.has("neck"):
		_arma_yaw_nodo.transform = _girar_en_cuello(_arma_yaw_nodo.transform, -_arma_yaw_puesto)
	_arma_yaw_puesto = 0.0
	_arma_yaw_nodo = null
	if absf(yaw) < 0.00001 or weapon_root == null or not is_instance_valid(weapon_root) or _external_weapon 			or not bone_idx.has("neck"):
		return
	weapon_root.transform = _girar_en_cuello(weapon_root.transform, yaw)
	_arma_yaw_puesto = yaw
	_arma_yaw_nodo = weapon_root

func _girar_en_cuello(t: Transform3D, yaw: float) -> Transform3D:
	var cuello: Vector3 = skeleton.get_bone_global_pose(bone_idx["neck"]).origin
	var r := Basis(Vector3.UP, yaw)
	return Transform3D(r * t.basis, cuello + r * (t.origin - cuello))


static var _probe := "--posedbg" in OS.get_cmdline_user_args()
static var _probe_us := 0
static var _probe_n := 0


# ---------------------------------------------------------------------------------------------------
# ARMAS GUARDADAS (2026-09-23, pedido): lo que no llevas en la mano se ve colgado del cuerpo, tambien para
# los demas en LAN y online. La pesada (lanzacohetes, mazo, escudo) cruzada a la espalda; la pistola en la
# cadera derecha; el arma larga que no usas, colgada del costado izquierdo. Coordenadas en voxels del soldado
# (x a su izquierda, y arriba, z hacia atras), relativas al hueso; se compensa la orientacion de reposo del hueso.
# ---------------------------------------------------------------------------------------------------
var _guardadas_s := "-"
var _guardadas_nodos: Array = []

func set_armas_guardadas(s: String) -> void:
	if s == _guardadas_s or skeleton == null:
		return
	_guardadas_s = s
	for n in _guardadas_nodos:
		if is_instance_valid(n):
			n.queue_free()
	_guardadas_nodos.clear()
	if s == "":
		return
	var espalda := 0
	var costado := 0
	for e in s.split(";"):
		var p := e.split("|")
		if p.size() < 2:
			continue
		var kind := String(p[0])
		var aid := String(p[1])
		var skin := String(p[2]) if p.size() > 2 else ""
		var hueso := "chest"
		var pos := Vector3.ZERO
		var rot := Vector3.ZERO
		if kind in ["rocket", "sledge", "escudo"]:
			# a la espalda, en diagonal; la segunda cruzada al reves
			hueso = "chest"
			pos = Vector3(2.5, 6.0, 11.0 + espalda * 2.5)
			rot = Vector3(90.0, 0.0, 35.0 if espalda % 2 == 0 else -35.0)
			if kind == "escudo":
				rot = Vector3(0.0, 180.0, 0.0)
				pos = Vector3(2.5, 4.0, 12.0 + espalda * 2.5)
			espalda += 1
		elif kind == "pistol":
			# del PECHO y no de la cadera: la cadera va girada en la animacion y la pistola salia en horizontal.
			# (la cadera cae 13 voxels por debajo del pecho y 5 por detras)
			hueso = "chest"
			pos = Vector3(-4.5, -14.0, 5.0)
			rot = Vector3(-90.0, 0.0, 0.0)
		else:
			# arma larga colgada del costado izquierdo, boca abajo
			hueso = "chest"
			pos = Vector3(10.5 + costado * 2.5, -11.0, 6.0)
			rot = Vector3(-80.0, 0.0, 8.0)
			costado += 1
		if not bone_idx.has(hueso):
			continue
		var att := BoneAttachment3D.new()
		att.bone_name = hueso
		skeleton.add_child(att)
		att.bone_idx = bone_idx[hueso]
		var wm := WeaponModelScript.new()
		wm.kind = kind
		wm.arma_id = aid
		wm.skin_forzada = skin if skin != "" else "-"
		# colocacion en el espacio del esqueleto, deshaciendo la orientacion de reposo del hueso
		var rest: Transform3D = skeleton.get_bone_global_rest(bone_idx[hueso])
		var deseo := Transform3D(Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z))), rest.origin + pos)
		var local := rest.affine_inverse() * deseo
		var k: float = escala_tp(aid) / scale.x
		local.basis = local.basis.scaled(Vector3.ONE * k)
		wm.transform = local
		att.add_child(wm)
		if wm.flash_light:
			wm.flash_light.visible = false
		_guardadas_nodos.append(att)
	_modo_guardadas()

## EN PRIMERA PERSONA NO SE VEN (2026-09-23, pedido: "el arma pesada me tapa la camara"): tu propio muñeco
## lleva colgado el lanzacohetes a la espalda y su boca asomaba delante de la camara al andar. Como el resto
## del cuerpo en primera persona, solo proyectan sombra; en tercera persona y en los demas, se ven.
## Lo fija el jugador de ESTA maquina cada medio segundo con su vista real (player.gd): asi no depende de
## que todos los caminos que cambian la camara (ronda nueva, avion, caida, reaparecer) avisen al muñeco.
## -1 = no lo dice nadie (los muñecos de los demas): se usa _body_visible.
var guardadas_primera_persona := -1

func _modo_guardadas() -> void:
	var visibles: bool = _body_visible if guardadas_primera_persona < 0 else guardadas_primera_persona == 0
	var modo := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if visibles else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	for att in _guardadas_nodos:
		if is_instance_valid(att):
			for mi in att.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).cast_shadow = modo


# ---------------------------------------------------------------------------------------------------
# FORCEJEO (2026-09-23, pedido: "cuando el Goliat me tiene me quedo duro"). No hay clip para esto, asi que va
# encima de la pose: los brazos arriba empujando la mano que te agarra, las piernas pataleando por turnos y el
# torso retorciendose. Se gira cada hueso en el espacio del esqueleto (x a los lados, y arriba, z atras) sobre
# su pose de este cuadro, padres antes que hijos. El arma se esconde: no la estas sujetando.
# ---------------------------------------------------------------------------------------------------
var forcejeo := false
var _forcejeo_t := 0.0
var _forcejeo_w := 0.0

func _girar_global(bname: String, eje: Vector3, ang: float) -> void:
	if not bone_idx.has(bname) or absf(ang) < 0.0001:
		return
	var i: int = bone_idx[bname]
	var g: Transform3D = skeleton.get_bone_global_pose(i)
	g.basis = (Basis(eje.normalized(), ang) * g.basis).orthonormalized()
	skeleton.set_bone_global_pose(i, g)

## Los huesos que retuerce el forcejeo. Se escriben con set_bone_global_pose, que SE QUEDA PUESTO: si el clip
## que viene despues no mueve alguno (los brazos en varios reposos), se quedaba en la ultima postura del
## forcejeo para siempre (2026-09-27, pedido: "cuando matamos al bicho que agarra al bot sigue la animacion de
## los brazos"). Al acabar se devuelven a su reposo UNA vez, antes del clip del fotograma siguiente.
## --animsiempre (pruebas): anima aunque este fuera de camara o lejos, para medir poses sin mirarlas
static var anim_siempre: bool = "--animsiempre" in OS.get_cmdline_user_args()

const HUESOS_FORCEJEO := ["chest", "arm_upper_l", "arm_upper_r", "arm_lower_l", "arm_lower_r",
	"leg_upper_l", "leg_upper_r", "leg_lower_l", "leg_lower_r"]
var _forcejeo_limpiar := false
static var sin_reponer: bool = "--sinreponer" in OS.get_cmdline_user_args()   ## A/B del arreglo

func _forcejeo_reponer() -> void:
	if not _forcejeo_limpiar or skeleton == null or sin_reponer:
		return
	_forcejeo_limpiar = false
	for n in HUESOS_FORCEJEO:
		if bone_idx.has(n):
			var i: int = bone_idx[n]
			skeleton.set_bone_pose_rotation(i, skeleton.get_bone_rest(i).basis.get_rotation_quaternion())


func _aplicar_forcejeo(dt: float) -> void:
	var antes := _forcejeo_w
	_forcejeo_w = move_toward(_forcejeo_w, 1.0 if forcejeo else 0.0, dt * 6.0)
	# (NO con el arma de primera persona -_external_weapon: la de los brazos cuelga de la camara y su visibilidad la
	# lleva player.gd-. Reescribirla aqui cada cuadro deshacia el ocultarla al mirar por el visor del francotirador: el
	# visor salia tapado por el propio modelo, 2026-09-28)
	if weapon_root and is_instance_valid(weapon_root) and not _external_weapon:
		# vendandose o lanzando una granada, el arma guardada (esto corre cada fotograma: si no lo sabe, la vuelve a
		# enseñar y los demas veian el arma flotando mientras tirabas)
		weapon_root.visible = _forcejeo_w < 0.5 and _venda_t <= 0.0 and not _lanz_arma_oculta and not _gesto_arma_oculta \
			and _punio_w < 0.3
	if _forcejeo_w <= 0.0:
		if antes > 0.0:
			_forcejeo_limpiar = true
		return
	_forcejeo_t += dt
	var t := _forcejeo_t
	var w := _forcejeo_w
	# el torso se retuerce y se arquea
	_girar_global("chest", Vector3.UP, sin(t * 9.0) * 0.35 * w)
	_girar_global("chest", Vector3.RIGHT, (-0.25 + sin(t * 7.0) * 0.15) * w)
	# los brazos arriba, empujando la mano (con un temblor rapido de esfuerzo)
	for lado in [["arm_upper_l", 1.0, 0.0], ["arm_upper_r", -1.0, 1.7]]:
		var sube: float = (2.3 + sin(t * 13.0 + float(lado[2])) * 0.25) * w
		_girar_global(String(lado[0]), Vector3.FORWARD * float(lado[1]), sube)
	for lado in [["arm_lower_l", 0.0], ["arm_lower_r", 2.1]]:
		_girar_global(String(lado[0]), Vector3.RIGHT, (-0.6 + sin(t * 15.0 + float(lado[1])) * 0.35) * w)
	# las piernas pataleando por turnos
	_girar_global("leg_upper_l", Vector3.RIGHT, sin(t * 11.0) * 0.7 * w)
	_girar_global("leg_upper_r", Vector3.RIGHT, sin(t * 11.0 + PI) * 0.7 * w)
	_girar_global("leg_lower_l", Vector3.RIGHT, (0.5 + sin(t * 11.0 + 1.2) * 0.5) * w)
	_girar_global("leg_lower_r", Vector3.RIGHT, (0.5 + sin(t * 11.0 + PI + 1.2) * 0.5) * w)


# ---------------------------------------------------------------------------------------------------
# EL CUERPO MIENTRAS TIRA EL GANCHO (2026-09-29, pedido: "mejora la animacion de la soga, el personaje sube derecho, da
# risa"). Subia de pie y tieso con la pose de estar en el aire. No hay clip: va encima de la pose, como el forcejeo.
# Mientras la cuerda tira (habilidad.gd pone `gancho_tira`, en esta maquina y en las copias de red):
#   - el cuerpo entero se INCLINA hacia el garfio (el 62 % del angulo entre la vertical y la cuerda), girando alrededor
#     del PECHO, que es de donde tira el brazo, con un vaiven de pendulo;
#   - las piernas CUELGAN y se arrastran por detras de lo que tira, con las rodillas dobladas, un poco abiertas y cada
#     una a su ritmo;
#   - la otra mano se agarra a la cuerda (_gesto_tick).
# Entra en 0,15 s y sale en 0,25: al soltarse se vuelve a la pose del aire sin salto.
# ---------------------------------------------------------------------------------------------------
var gancho_tira := false
var _gancho_w := 0.0
var _gancho_t := 0.0
const GANCHO_HUESOS := ["pelvis", "leg_upper_l", "leg_upper_r", "leg_lower_l", "leg_lower_r"]

## Antes del clip: los huesos que toca el gancho, a su reposo (si el clip no mueve alguno, la inclinacion se sumaria
## cuadro a cuadro). La posicion de la pelvis la repone el propio clip con `_pelvis_movida`.
func _gancho_reponer() -> void:
	if _gancho_w <= 0.0 or skeleton == null:
		return
	for n in GANCHO_HUESOS:
		if bone_idx.has(n):
			var i: int = bone_idx[n]
			skeleton.set_bone_pose_rotation(i, skeleton.get_bone_rest(i).basis.get_rotation_quaternion())
	if bone_idx.has("pelvis") and _shared_rest_local.has("pelvis"):
		skeleton.set_bone_pose_position(bone_idx["pelvis"], _shared_rest_local["pelvis"])


func _aplicar_gancho_cuerpo(dt: float) -> void:
	var tira_ya := gancho_tira and _gesto_punto != Vector3.ZERO
	_gancho_w = move_toward(_gancho_w, 1.0 if tira_ya else 0.0, dt * (6.5 if tira_ya else 4.0))
	if _gancho_w <= 0.0 or skeleton == null or not bone_idx.has("pelvis") or not bone_idx.has("chest"):
		_gancho_t = 0.0
		return
	_gancho_t += dt
	var w := _gancho_w * _gancho_w * (3.0 - 2.0 * _gancho_w)
	var bi := skeleton.global_transform.basis.orthonormalized().inverse()
	var pecho_s: Vector3 = skeleton.get_bone_global_pose(bone_idx["chest"]).origin
	var tira := _gesto_punto - skeleton.to_global(pecho_s)
	if tira.length() < 0.4:
		return
	tira = tira.normalized()
	var adelante := -global_transform.basis.z
	adelante.y = 0.0
	adelante = adelante.normalized() if adelante.length() > 0.001 else Vector3.FORWARD
	# 1) EL CUERPO ENTERO, hacia el garfio, girando alrededor del pecho
	var arriba := Vector3.UP.slerp(tira, 0.62)
	var eje := Vector3.UP.cross(arriba)
	var ang := Vector3.UP.angle_to(arriba) * w + sin(_gancho_t * 3.4) * 0.06 * w
	if eje.length() > 0.0001 and absf(ang) > 0.001:
		var r := Basis((bi * eje).normalized(), ang)
		var ip: int = bone_idx["pelvis"]
		var g: Transform3D = skeleton.get_bone_global_pose(ip)
		g.basis = (r * g.basis).orthonormalized()
		g.origin = pecho_s + r * (g.origin - pecho_s)
		skeleton.set_bone_global_pose(ip, g)
		_pelvis_movida = true          # el clip del cuadro siguiente devuelve la pelvis a su sitio
	# 2) LAS PIERNAS: cuelgan, se arrastran detras de lo que tira y doblan las rodillas
	var cuelga := (-tira + Vector3.DOWN * 0.7).normalized()
	var centro_s: Vector3 = skeleton.get_bone_global_pose(bone_idx["pelvis"]).origin
	for lado in [["_l", 0.0, 0.85], ["_r", 1.7, 1.25]]:
		var sufijo: String = lado[0]
		if not (bone_idx.has("leg_upper" + sufijo) and bone_idx.has("leg_lower" + sufijo) and bone_idx.has("foot" + sufijo)):
			continue
		var cadera_s: Vector3 = skeleton.get_bone_global_pose(bone_idx["leg_upper" + sufijo]).origin
		var abre := skeleton.global_transform.basis.orthonormalized() * (cadera_s - centro_s)
		abre = abre.normalized() if abre.length() > 0.001 else Vector3.ZERO
		var fase_p: float = _gancho_t * 3.4 + float(lado[1])
		var muslo := (cuelga + adelante * (0.30 + sin(fase_p) * 0.18) + abre * 0.16).normalized()
		var espinilla := (muslo * 0.45 - adelante * float(lado[2]) + Vector3.DOWN * 0.25).normalized()
		_apuntar_hueso("leg_upper" + sufijo, "leg_lower" + sufijo, bi * muslo, w)
		_apuntar_hueso("leg_lower" + sufijo, "foot" + sufijo, bi * espinilla, w)


# ---------------------------------------------------------------------------------------------------
# RESCATE (rescate.gd) — POSES PROVISIONALES, en codigo, hasta que esten los clips de Blender.
#   cargando: el portador, con el brazo derecho sujetando el cuerpo sobre el hombro y el izquierdo delante
#   rcp:      de rodillas, brazos rectos, compresiones
#   pose_rescate("cargado"/"tumbado"): el cuerpo (muñeco sin _process: lo llama rescate.gd)
# Ejes del esqueleto: y arriba, -z delante, x a la izquierda del soldado.
# ---------------------------------------------------------------------------------------------------
var cargando := false
var rcp := false
var _rcp_t := 0.0

func _apuntar_hueso(bname: String, hijo: String, dir: Vector3, peso: float = 1.0) -> void:
	if not bone_idx.has(bname) or not bone_idx.has(hijo) or dir.length() < 0.01:
		return
	var i: int = bone_idx[bname]
	var g: Transform3D = skeleton.get_bone_global_pose(i)
	var a: Vector3 = skeleton.get_bone_global_pose(bone_idx[hijo]).origin - g.origin
	if a.length() < 0.001:
		return
	a = a.normalized()
	var d := dir.normalized()
	var eje := a.cross(d)
	if eje.length() < 0.0001:
		return
	var ang: float = acos(clampf(a.dot(d), -1.0, 1.0)) * peso
	g.basis = (Basis(eje.normalized(), ang) * g.basis).orthonormalized()
	skeleton.set_bone_global_pose(i, g)

func _aplicar_rescate_vivo(dt: float) -> void:
	if not cargando and not rcp:
		return
	if _brazos_clip != "":
		# CARGANDO AL COMPAÑERO (pedido): piernas y cuerpo andan como siempre; solo los brazos llevan el clip
		if weapon_root and is_instance_valid(weapon_root):
			weapon_root.visible = false
		_brazos_t += dt
		var bk := _baked(_brazos_clip)
		var dur: float = bk["dur"]
		var tt: float = fmod(_brazos_t, dur) if dur > 0.0 else 0.0
		var bb: Dictionary = bk["bones"]
		for hb in HUESOS_BRAZOS:
			if bb.has(hb) and bone_idx.has(hb):
				skeleton.set_bone_pose_rotation(bone_idx[hb], _sample_baked(bb[hb], tt))
		return
	if clip_rescate != "":
		if weapon_root and is_instance_valid(weapon_root):
			weapon_root.visible = false
		return          # hay clip de Blender: la pose provisional ya no hace falta
	if weapon_root and is_instance_valid(weapon_root):
		weapon_root.visible = false
	if cargando:
		# la mano derecha arriba, sobre el hombro, sujetando las piernas; la izquierda delante, en su espalda
		_apuntar_hueso("arm_upper_r", "arm_lower_r", Vector3(-0.35, 0.85, -0.35))
		_apuntar_hueso("arm_lower_r", "hand_r", Vector3(0.45, 0.35, -0.6))
		_apuntar_hueso("arm_upper_l", "arm_lower_l", Vector3(0.1, -0.2, -1.0))
		_apuntar_hueso("arm_lower_l", "hand_l", Vector3(-0.5, 0.45, -0.6))
		_girar_global("chest", Vector3.RIGHT, -0.12)     # algo echado adelante por el peso
	if rcp:
		_rcp_t += dt
		var bombeo := 0.5 + 0.5 * sin(_rcp_t * TAU * 1.8)   # ~110 compresiones por minuto
		skeleton.position.y -= 0.55 / maxf(scale.y, 0.001)  # de rodillas
		_apuntar_hueso("leg_upper_l", "leg_lower_l", Vector3(0.1, -0.1, -1.0))
		_apuntar_hueso("leg_upper_r", "leg_lower_r", Vector3(-0.1, -0.1, -1.0))
		_apuntar_hueso("leg_lower_l", "foot_l", Vector3(0.0, -0.3, 1.0))
		_apuntar_hueso("leg_lower_r", "foot_r", Vector3(0.0, -0.3, 1.0))
		_girar_global("chest", Vector3.RIGHT, -0.55 - 0.12 * bombeo)
		for lado in ["l", "r"]:
			_apuntar_hueso("arm_upper_" + lado, "arm_lower_" + lado, Vector3(0.0, -0.85, -0.5))
			_apuntar_hueso("arm_lower_" + lado, "hand_" + lado, Vector3(0.0, -0.9, -0.4))

## Pose del CUERPO (muñeco sin _process): "cargado" cuelga los miembros hacia el suelo de verdad (se llama cada
## cuadro, que el cuerpo se mueve con el portador), "tumbado" boca arriba con los brazos pegados, "" nada.
var _pose_rescate := ""
func pose_rescate(modo: String) -> void:
	_pose_rescate = modo
	if skeleton == null:
		return
	if weapon_root and is_instance_valid(weapon_root):
		weapon_root.visible = modo == ""
	if modo == "":
		return
	skeleton.reset_bone_poses()
	var abajo: Vector3 = skeleton.global_transform.basis.inverse() * Vector3.DOWN
	if modo == "cargado":
		for par in [["arm_upper_l", "arm_lower_l"], ["arm_lower_l", "hand_l"], ["arm_upper_r", "arm_lower_r"],
				["arm_lower_r", "hand_r"], ["neck", "head"]]:
			_apuntar_hueso(par[0], par[1], abajo, 0.85)
		for par in [["leg_upper_l", "leg_lower_l"], ["leg_upper_r", "leg_lower_r"]]:
			_apuntar_hueso(par[0], par[1], abajo, 0.6)
		_apuntar_hueso("leg_lower_l", "foot_l", abajo, 0.8)
		_apuntar_hueso("leg_lower_r", "foot_r", abajo, 0.8)
	elif modo == "tumbado":
		for lado in ["l", "r"]:
			_apuntar_hueso("arm_upper_" + lado, "arm_lower_" + lado, Vector3(0.15 if lado == "l" else -0.15, -1.0, 0.05))
			_apuntar_hueso("arm_lower_" + lado, "hand_" + lado, Vector3(0.0, -1.0, 0.0))

func refrescar_pose_rescate() -> void:
	if _pose_rescate == "cargado":
		pose_rescate("cargado")


## LOS CLIPS DEL RESCATE (tools/blender/rescate_anim.py). Mientras hay uno puesto, la locomocion no lo cambia.
## `pausa_clip` lo congela en su fotograma (el que va a revivir espera tumbado en el primero durante la RCP).
var clip_rescate := ""
var pausa_clip := false

const HUESOS_BRAZOS := ["shoulder_l", "arm_upper_l", "arm_lower_l", "hand_l", "shoulder_r", "arm_upper_r", "arm_lower_r", "hand_r"]
var _brazos_clip := ""
var _brazos_t := 0.0

func poner_clip_rescate(nombre: String, pausado := false) -> void:
	_brazos_clip = ""
	if nombre == "rescate_cargar" and has_clip(nombre):
		# andar cargado: la locomocion sigue mandando en piernas y cuerpo; los brazos, en _aplicar_rescate_vivo
		clip_rescate = ""
		pausa_clip = false
		anim_speed = 1.0
		_brazos_clip = nombre
		_brazos_t = 0.0
		return
	clip_rescate = nombre
	pausa_clip = pausado
	anim_speed = 1.0
	if nombre == "" or not has_clip(nombre):
		clip_rescate = ""
		return
	_limp_t = -1.0
	_caida_t = -1.0
	_trepa_t = -1.0
	set_process(true)
	play(nombre, true)


static var _movil_anim: int = -1
const ANIM_CERCA_M := 12.0
static var _anim30: bool = "--botsanim30" in OS.get_cmdline_user_args()
const GATILLO_BAJA_FP := 0.035
const GATILLO_BAJA_PISTOLA := 0.03
## La mano del gatillo apartada (en el mundo) en la recarga de primera persona, para que no tape el cargador (player.gd)
var gatillo_extra := Vector3.ZERO
var gatillo_extra_w := 0.0
static var _gat_baja := -1.0
static func _gatillo_baja() -> float:
	if _gat_baja < 0.0:
		_gat_baja = GATILLO_BAJA_FP
		for a in OS.get_cmdline_user_args():
			if String(a).begins_with("--gatillobaja="):
				_gat_baja = maxf(0.0, float(String(a).substr(14)))
	return _gat_baja
