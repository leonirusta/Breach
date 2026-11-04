extends RefCounted
## ESCUDO BALISTICO + PISTOLA. Lo que comparten el avatar (tercera persona, lo que ven los demas) y la camara
## (primera persona): los datos de la animacion hecha en Blender, como se mezclan los clips y el modelo.
##
## La animacion esta en tools/blender/escudo_anim.py y sale a res://avatar/escudo.json (exportar_escudo.py):
## por clip y por frame, donde van el escudo y la pistola respecto al cuello (tercera persona) y respecto
## al ojo (primera), las manos cuando sueltan su objeto y el cargador nuevo en la recarga. El cuerpo de cada
## clip (torso, cabeza y la postura de perfil) va en clips_breach.json como escudo_<clip>.
##
## LA MEZCLA. Un estado dice cuanto se esta apuntando y en que punto va cada gesto:
##   guardia   siempre, en bucle (respira, cambia el peso, vigila)
##   apuntar   0..1: el clip recorre el camino de la pistola ALREDEDOR del canto del escudo, asi que se
##             muestrea en ese punto (mezclar guardia y posicion de tiro la haria atravesar el escudo)
##   disparo   el retroceso, sumado encima de lo que se este haciendo
##   impacto   el golpe en el escudo, sumado encima
##   recarga / rotura   mandan del todo mientras duran

const RUTA := "res://avatar/escudo.json"
const MODELO := "res://armas/escudo_balistico.glb"
const ID := "escudo_pistola"
## La pistola que se lleva con el escudo, y con la que te quedas cuando se rompe.
const PISTOLA := "pistola_9"
## Vida del escudo. Lo que le llega de frente se lo come el; al llegar a 0 se rompe y se suelta.
const VIDA := 600.0       ## (era 300; el doble, pedido 2026-10-15)
## Hasta donde cubre, en grados a cada lado del frente. Con la pistola fuera el escudo se abre un poco
## por su canto derecho y cubre algo menos.
const CUBRE_GRADOS := 58.0
const CUBRE_GRADOS_APUNTANDO := 46.0
## El centro del cuerpo del escudo respecto a la mano (ficha res://armas/escudo.json)
const CENTRO := Vector3(0.0, 0.0, -0.095)
const TAM := Vector3(0.578, 0.938, 0.05)
const CLAVES_OBJ := ["esc_tp", "pis_tp", "esc_fp", "pis_fp"]

static var _d: Dictionary = {}
static var _leido := false


static func datos() -> Dictionary:
	if not _leido:
		_leido = true
		var f := FileAccess.open(RUTA, FileAccess.READ)
		if f:
			var j = JSON.parse_string(f.get_as_text())
			if typeof(j) == TYPE_DICTIONARY and j.has("clips"):
				_d = j
	return _d


static func disponible() -> bool:
	return not datos().is_empty()


## Lo que dura un clip, en segundos.
static func duracion(clip: String) -> float:
	var d := datos()
	if d.is_empty() or not d["clips"].has(clip):
		return 0.0
	var n: int = int(d["clips"][clip]["frames"])
	var fps: float = float(d.get("fps", 30.0))
	return float(n) / fps if clip == "guardia" else float(n - 1) / fps


static func _v(a: Array, i: int = 0) -> Vector3:
	return Vector3(float(a[i]), float(a[i + 1]), float(a[i + 2]))


static func _q(a: Array, i: int = 3) -> Quaternion:
	return Quaternion(float(a[i]), float(a[i + 1]), float(a[i + 2]), float(a[i + 3])).normalized()


## Un clip en el punto k (0..1). En bucle (guardia) el ultimo frame enlaza con el primero.
## Devuelve {esc_tp: [pos, giro], pis_tp, esc_fp, pis_fp, mano_der: [pos, libre], mano_izq, mag_nuevo: [pos, giro]}.
static func muestra(clip: String, k: float) -> Dictionary:
	var d := datos()
	if d.is_empty() or not d["clips"].has(clip):
		return {}
	var c: Dictionary = d["clips"][clip]
	var n: int = int(c["frames"])
	var bucle := clip == "guardia"
	var fr: float
	var i0: int
	var i1: int
	if bucle:
		fr = fposmod(k, 1.0) * float(n)
		i0 = int(fr) % n
		i1 = (i0 + 1) % n
	else:
		fr = clampf(k, 0.0, 1.0) * float(n - 1)
		i0 = int(fr)
		i1 = mini(i0 + 1, n - 1)
	var t: float = fr - floorf(fr)
	var out := {}
	for clave in CLAVES_OBJ + ["mag_nuevo"]:
		var a: Array = c[clave][i0]
		var b: Array = c[clave][i1]
		out[clave] = [_v(a).lerp(_v(b), t), _q(a).slerp(_q(b), t)]
	for clave in ["mano_der", "mano_izq"]:
		var a2: Array = c[clave][i0]
		var b2: Array = c[clave][i1]
		out[clave] = [_v(a2).lerp(_v(b2), t), lerpf(float(a2[3]), float(b2[3]), t)]
	return out


static func _mezcla(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	if w <= 0.0 or b.is_empty():
		return a
	if w >= 1.0 or a.is_empty():
		return b
	var out := {}
	for clave in a.keys():
		var x: Array = a[clave]
		var y: Array = b[clave]
		if x[1] is Quaternion:
			out[clave] = [(x[0] as Vector3).lerp(y[0], w), (x[1] as Quaternion).slerp(y[1], w)]
		else:
			out[clave] = [(x[0] as Vector3).lerp(y[0], w), lerpf(float(x[1]), float(y[1]), w)]
	return out


## Suma a `base` lo que se mueve `d` desde su primer frame `d0`, con peso `w` (solo escudo y pistola).
static func _sumar(base: Dictionary, d: Dictionary, d0: Dictionary, w: float) -> Dictionary:
	if w <= 0.0 or d.is_empty():
		return base
	var out := base.duplicate()
	for clave in CLAVES_OBJ:
		var b: Array = base[clave]
		var dp: Vector3 = (d[clave][0] as Vector3) - (d0[clave][0] as Vector3)
		var dq: Quaternion = ((d[clave][1] as Quaternion) * (d0[clave][1] as Quaternion).inverse()).normalized()
		out[clave] = [(b[0] as Vector3) + dp * w, (Quaternion.IDENTITY.slerp(dq, w) * (b[1] as Quaternion)).normalized()]
	return out


## LA POSE DE ESTE FRAME. `e`: {guardia (s), apunta (0..1), disparo, impacto, recarga, rotura (0..1, o -1
## si no esta pasando)}. Vacio si no hay datos.
static func pose(e: Dictionary) -> Dictionary:
	if not disponible():
		return {}
	var tg: float = float(e.get("guardia", 0.0)) / maxf(duracion("guardia"), 0.01)
	var guardia := muestra("guardia", tg)
	var apunta: float = clampf(float(e.get("apunta", 0.0)), 0.0, 1.0)
	var p := guardia
	if apunta > 0.0:
		# el camino de apuntar manda; la respiracion de la guardia se va apagando segun sale la pistola
		var ap := muestra("apuntar", apunta)
		var g0 := muestra("guardia", 0.0)
		p = _sumar(ap, guardia, g0, 1.0 - apunta)
	var kd: float = float(e.get("disparo", -1.0))
	if kd >= 0.0 and kd <= 1.0:
		p = _sumar(p, muestra("disparo", kd), muestra("disparo", 0.0), maxf(apunta, 0.35))
	var ki: float = float(e.get("impacto", -1.0))
	if ki >= 0.0 and ki <= 1.0:
		p = _sumar(p, muestra("impacto", ki), muestra("impacto", 0.0), 1.0)
	var kr: float = float(e.get("recarga", -1.0))
	if kr >= 0.0:
		# entra y sale con suavidad por si la recarga empieza con la pistola fuera
		var wr: float = smoothstep(0.0, 0.06, kr) * (1.0 - smoothstep(0.94, 1.0, kr)) if apunta > 0.05 else 1.0
		p = _mezcla(p, muestra("recarga", kr), wr)
	var kb: float = float(e.get("rotura", -1.0))
	if kb >= 0.0:
		p = _mezcla(p, muestra("rotura", kb), 1.0)
	return p


## Los clips del CUERPO (clips_breach.json) y cuanto manda cada uno, en orden de aplicacion:
## [[clip, segundos, peso], ...]. El avatar los aplica uno tras otro con slerp.
static func capas_cuerpo(e: Dictionary) -> Array:
	var capas: Array = [["escudo_guardia", fposmod(float(e.get("guardia", 0.0)), maxf(duracion("guardia"), 0.01)), 1.0]]
	var apunta: float = clampf(float(e.get("apunta", 0.0)), 0.0, 1.0)
	if apunta > 0.0:
		capas.append(["escudo_apuntar", apunta * duracion("apuntar"), apunta])
	for gesto in ["disparo", "impacto", "recarga", "rotura"]:
		var k: float = float(e.get(gesto, -1.0))
		if k >= 0.0 and k <= 1.0:
			var w := 1.0
			if gesto == "disparo":
				w = apunta
			elif gesto == "impacto":
				w = 1.0 - 0.5 * apunta
			capas.append(["escudo_" + gesto, k * duracion(gesto), w])
	return capas


## PRIMERA PERSONA SEGUN EL CUELLO. Las pistas `_fp` van respecto al ojo ANIMADO, y en la recarga la cabeza
## se asoma por encima del escudo para mirar la pistola: respecto a ese ojo el escudo se venia a 5 cm de la
## camara y la pistola quedaba por detras de ella. La camara del juego no hace ese gesto, asi que lo que
## ve se saca de las pistas del cuello (lo que mueven los brazos respecto al pecho) mas la distancia del
## cuello al ojo en la guardia, medida en el primer frame. Devuelve [pos, giro] para "esc" o "pis".
static var _cuello_ojo := Vector3.INF

static func fp(p: Dictionary, que: String) -> Array:
	if _cuello_ojo == Vector3.INF:
		var g0 := muestra("guardia", 0.0)
		var tp0: Vector3 = g0["esc_tp"][0]
		_cuello_ojo = (g0["esc_fp"][0] as Vector3) - Vector3(-tp0.x, tp0.y, tp0.z)
	var pos: Vector3 = p[que + "_tp"][0]
	var q: Quaternion = p[que + "_tp"][1]
	# de los ejes del esqueleto (espejo en X) a los de la camara
	return [Vector3(-pos.x, pos.y, pos.z) + _cuello_ojo, Quaternion(q.x, -q.y, -q.z, q.w).normalized()]


## EL CARGADOR EN LA RECARGA, en el espacio de la pistola. Los tramos salen de escudo_anim.py (MAG_V, MAG_N):
## el vacio sigue en el arma hasta el frame 152, donde cae; hasta el 166 el nuevo esta en el portacargador
## (el arma va sin cargador) y desde el 180 ya esta metido. Devuelve null mientras el arma no tiene ninguno.
const REC_SUELTA := 11.0 / 53.0
const REC_COGE := 25.0 / 53.0
const REC_ENTRA := 39.0 / 53.0

static func cargador(k: float, asiento: Vector3) -> Variant:
	if k < REC_SUELTA or k >= REC_ENTRA or not disponible():
		return Transform3D(Basis.IDENTITY, asiento)
	if k < REC_COGE:
		return null
	var m := muestra("recarga", k)
	var p: Vector3 = m["mag_nuevo"][0]
	var q: Quaternion = m["mag_nuevo"][1]
	# se exporto con los ejes del esqueleto (espejo en X): al modelo de la pistola se vuelve reflejando
	return Transform3D(Basis(Quaternion(q.x, -q.y, -q.z, q.w).normalized()), Vector3(-p.x, p.y, p.z))


## EL MODELO DEL ESCUDO (Node3D en metros, el asa en el origen y el frente hacia -Z). Lo usan la mano y el
## escudo suelto, que asi es exactamente el mismo.
static func modelo(cristal: Material = null) -> Node3D:
	var raiz := Node3D.new()
	raiz.name = "Escudo"
	var ps := load(MODELO) as PackedScene
	if ps == null:
		push_warning("[escudo] no carga %s" % MODELO)
		return raiz
	var m := ps.instantiate() as Node3D
	m.name = "Modelo"
	raiz.add_child(m)
	for hijo in m.find_children("*", "MeshInstance3D", true, false):
		var mi := hijo as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if mi.name.begins_with("Cristal"):
			mi.material_override = cristal if cristal else _cristal()
			mi.set_meta("cristal", true)
	return raiz


## El cristal reventado: UNO para todos (2026-10-16, medido en la cafeteria con bots: crearlo nuevo en cada rotura
## eran 43 ms en el fotograma en que se rompe un escudo, y cargar el modelo la primera vez otros 16). `precalentar`
## lo deja hecho bajo la pantalla de carga.
static var _mat_roto: StandardMaterial3D = null

static func _romper_cristal(m: Node) -> void:
	if _mat_roto == null:
		_mat_roto = StandardMaterial3D.new()
		_mat_roto.albedo_color = Color(0.78, 0.82, 0.86, 0.85)
		_mat_roto.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_roto.roughness = 0.9
	for hijo in m.find_children("*", "MeshInstance3D", true, false):
		if (hijo as MeshInstance3D).has_meta("cristal"):
			(hijo as MeshInstance3D).material_override = _mat_roto


## EL DE REPUESTO: instanciar el .glb son ~16 ms en el fotograma de la rotura. Hay siempre uno hecho (con el cristal
## ya roto) y al gastarlo se hace el siguiente en un hilo (un nodo fuera del arbol se puede montar desde otro hilo).
## --sinrepuestoescudo = montarlo en el momento, como antes.
static var _repuesto: Node3D = null
static var _tarea_repuesto := -1
static var _sin_repuesto: bool = "--sinrepuestoescudo" in OS.get_cmdline_user_args()

static func _hacer_repuesto() -> void:
	var m := modelo()
	_romper_cristal(m)
	_repuesto = m

static func _modelo_roto() -> Node3D:
	if _tarea_repuesto >= 0 and WorkerThreadPool.is_task_completed(_tarea_repuesto):
		WorkerThreadPool.wait_for_task_completion(_tarea_repuesto)
		_tarea_repuesto = -1
	var m: Node3D = null
	if _repuesto != null and _tarea_repuesto < 0 and not _sin_repuesto:
		m = _repuesto
		_repuesto = null
	else:
		m = modelo()
		_romper_cristal(m)
	if not _sin_repuesto and _repuesto == null and _tarea_repuesto < 0:
		_tarea_repuesto = WorkerThreadPool.add_task(_hacer_repuesto)
	return m


## Un escudo roto de mentira (sin fisica) en `pos`, unos fotogramas, para que el modelo y el cristal roto se
## carguen y compilen bajo la pantalla de carga y no en la primera rotura de la partida.
static func precalentar(padre: Node, pos: Vector3) -> Node3D:
	var m := modelo()
	_romper_cristal(m)
	padre.add_child(m)
	m.global_position = pos
	if not _sin_repuesto and _repuesto == null and _tarea_repuesto < 0:
		_tarea_repuesto = WorkerThreadPool.add_task(_hacer_repuesto)
	return m


static var _mat_cristal: StandardMaterial3D = null

static func _cristal() -> StandardMaterial3D:
	if _mat_cristal == null:
		_mat_cristal = StandardMaterial3D.new()
		_mat_cristal.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# vidrio blindado: grueso, con su tinte verdoso y reflejando el cielo
		_mat_cristal.albedo_color = Color(0.50, 0.66, 0.66, 0.34)
		_mat_cristal.metallic = 0.5
		_mat_cristal.roughness = 0.06
		_mat_cristal.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mat_cristal


## ¿Tapa el escudo un golpe que llega de `desde` (direccion hacia el atacante, en el mundo)? `frente` es
## hacia donde mira quien lo lleva.
static func tapa(frente: Vector3, desde: Vector3, apuntando: bool) -> bool:
	var f := Vector3(frente.x, 0.0, frente.z)
	var a := Vector3(desde.x, 0.0, desde.z)
	if f.length_squared() < 1e-6 or a.length_squared() < 1e-6:
		return false
	var lim: float = cos(deg_to_rad(CUBRE_GRADOS_APUNTANDO if apuntando else CUBRE_GRADOS))
	return f.normalized().dot(a.normalized()) >= lim


## EL ESCUDO ROTO CAE AL SUELO: un cuerpo rigido con el mismo modelo, en la postura que tenia en la mano,
## con el empujon del golpe. Se queda un rato en el suelo y se desvanece.
static func soltar(padre: Node, xf: Transform3D, empuje: Vector3) -> RigidBody3D:
	if padre == null:
		return null
	var rb := RigidBody3D.new()
	rb.name = "EscudoRoto"
	rb.mass = 8.0
	rb.add_to_group("phys_anchor")
	# CON DETECCION CONTINUA: es una plancha de 5 cm, y cayendo de canto atravesaba el suelo en un solo paso
	# de fisica (medido: se colaba cuando una caja de 50 cm soltada a la vez se quedaba encima)
	rb.continuous_cd = true
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(TAM.x, TAM.y, 0.08)
	forma.shape = caja
	forma.position = CENTRO
	rb.add_child(forma)
	var m := _modelo_roto()
	rb.add_child(m)
	padre.add_child(rb)
	rb.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	rb.linear_velocity = empuje
	rb.angular_velocity = Vector3(randf_range(-1.5, -0.5), randf_range(-0.6, 0.6), randf_range(-0.8, 0.8))
	# LAS GRIETAS: el cristal roto se ve blanco y opaco, como el vidrio blindado reventado
	# el golpe contra el suelo: plancha de acero de ocho kilos (una sola vez, y solo si cae con fuerza)
	rb.contact_monitor = true
	rb.max_contacts_reported = 1
	rb.body_entered.connect(func(_otro: Node):
		if is_instance_valid(rb) and not rb.has_meta("sono") and rb.linear_velocity.length() > 1.2:
			rb.set_meta("sono", true)
			Audio.play3d("metal/land", rb.global_position, 0.0, 0.08, 50.0, Audio.PRI_MID))
	var tree := padre.get_tree()
	if tree:
		tree.create_timer(40.0).timeout.connect(func():
			if is_instance_valid(rb):
				rb.queue_free())
	return rb
