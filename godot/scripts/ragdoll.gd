extends Node3D
## RAGDOLL DE VERDAD: doce cuerpos rígidos con juntas, resueltos por el motor de física. Nada de
## poses guionizadas — cada muerte cae distinta porque la calcula el solver, no una tabla.
##
## POR QUÉ NO CUELGA DEL AVATAR, que es lo que haría cualquiera. El avatar vive escalado a ~0.021
## (el rig mide ~80 unidades de alto y el personaje 1,7 m), y la física de Godot con cuerpos bajo un
## nodo escalado así no es de fiar: los márgenes de colisión y las tolerancias del solver están en
## unidades de mundo, y a esa escala los tensores de inercia salen minúsculos. El resultado típico es
## un ragdoll que vibra, atraviesa el suelo o explota.
##
## Aquí los cuerpos se crean SUELTOS, a escala 1:1 en metros, con las posiciones sacadas de dónde
## está cada hueso en el mundo en el instante de morir. La física los resuelve en metros, como
## cualquier caja del juego, y luego se lee su transformada y se escribe en el esqueleto. El avatar
## sigue escalado y no se entera.
##
## EL COSTE, RESUELTO POR TIEMPO Y NO POR CUPO. Doce cuerpos por cadáver y catorce cadáveres serían
## 168 cuerpos, que no los aguanta una integrada. La primera versión limitaba a tres ragdolls activos
## y dormía al más viejo al aparecer uno nuevo — y eso se ve fatal: mataba a alguien y un cadáver de
## al lado se quedaba tieso de golpe, a mitad de caer.
##
## Ahora TODOS tienen ragdoll, y NINGUNO SE QUEDA TIESO. Antes cada cuerpo se congelaba entero a
## los tres segundos (o antes si se paraba): `freeze` en modo estatico, que lo convierte en una
## estatua. Ahorraba solver, pero el cadaver dejaba de ser un cuerpo -le disparabas o le caia algo
## encima y no se inmutaba- y eso se nota. Orden del jugador: los cuerpos no se endurecen.
##
## El coste no se dispara por eso, por dos motivos. Uno: el motor ya DUERME solo a un cuerpo rigido
## quieto (`can_sleep`), y un cuerpo dormido no cuesta solver pero sigue siendo blando: en cuanto
## algo lo toca -una bala, una explosion, otro cuerpo- se despierta y se mueve con sus juntas. Dos:
## el tope de cadaveres del ajuste grafico es de cuatro, asi que nunca hay mas de 48 piezas.
##
## Y CUANDO TERMINA DE CAER, SE DUERME DEL TODO (2026-10-02, pedido: "los cadaveres dormiran las fisicas en cuanto
## terminen de caer al piso; se activaran cuando alguien lo recoja para llevarlo o reviva"). Medido en la cafeteria con
## bots (--perfmapa): con 36-60 piezas de cadaver despiertas el paso de Jolt llegaba a 117-121 ms; el sueño del motor no
## bastaba, porque las piezas sobre la malla del mundo seguian temblando sin dormirse. Ahora, cuando todas llevan
## QUIETO_S casi quietas (o el motor ya las durmio), se CONGELAN estaticas (`_congelar`): siguen ahi para que otro
## cadaver caiga encima, pero no cuestan solver. Llevar el cuerpo o revivir quita este ragdoll y monta otro
## (rescate.gd), y un empujon tardio (`empujar`) lo despierta. Mientras cae, nada cambia.

## Qué hueso mueve cada cuerpo y hasta dónde llega. El segundo nombre es el hueso que marca su
## PUNTA: un hueso de por sí es un punto, y hace falta el siguiente para saber cuánto mide y hacia
## dónde apunta. Los que no tienen siguiente (cabeza, manos, pies) se estiran a mano.
const CADENA := [
	["pelvis", "stomach", 0.15],
	["stomach", "chest", 0.14],
	["chest", "neck", 0.15],
	["head", "", 0.11],
	["arm_upper_l", "arm_lower_l", 0.055],
	["arm_lower_l", "hand_l", 0.048],
	["arm_upper_r", "arm_lower_r", 0.055],
	["arm_lower_r", "hand_r", 0.048],
	["leg_upper_l", "leg_lower_l", 0.075],
	["leg_lower_l", "foot_l", 0.062],
	["leg_upper_r", "leg_lower_r", 0.075],
	["leg_lower_r", "foot_r", 0.062],
]
## De quién cuelga cada cuerpo (dentro del ragdoll, no en el rig: aquí no hay hombros ni cuello).
const PADRE := {
	"stomach": "pelvis", "chest": "stomach", "head": "chest",
	"arm_upper_l": "chest", "arm_lower_l": "arm_upper_l",
	"arm_upper_r": "chest", "arm_lower_r": "arm_upper_r",
	"leg_upper_l": "pelvis", "leg_lower_l": "leg_upper_l",
	"leg_upper_r": "pelvis", "leg_lower_r": "leg_upper_r",
}
## Cuánto puede abrirse cada junta, en grados. Aquí está la diferencia entre un muñeco de trapo y un
## cuerpo: una rodilla que gira 90° hacia delante se ve como goma. Los codos y las rodillas van
## cortos y con poca torsión; la cadera y los hombros, sueltos.
const LIMITE := {
	"stomach": [22.0, 14.0], "chest": [20.0, 14.0], "head": [38.0, 22.0],
	"arm_upper_l": [72.0, 40.0], "arm_lower_l": [58.0, 12.0],
	"arm_upper_r": [72.0, 40.0], "arm_lower_r": [58.0, 12.0],
	"leg_upper_l": [55.0, 22.0], "leg_lower_l": [50.0, 8.0],
	"leg_upper_r": [55.0, 22.0], "leg_lower_r": [50.0, 8.0],
}

var _skel: Skeleton3D = null
var _idx := {}                  ## nombre de hueso -> índice en el esqueleto
var _cuerpos := {}              ## nombre -> RigidBody3D
var _off := {}                  ## nombre -> del cuerpo al hueso (para deshacerlo al leer)
var _orden: Array = []          ## los huesos en orden de padres primero


## Monta el ragdoll a partir de la pose en la que murió. `vel` es la velocidad que llevaba, para que
## salga despedido hacia donde iba y no caiga a plomo.
## Devuelve null si el rig no trae los huesos que hacen falta: quien llama debe tener un plan B.
## Un empujon de mas a todo el cuerpo (el golpe que lo mato llego despues de montarlo: net_player.empujar_muerte)
func empujar(v: Vector3) -> void:
	if congelado:
		despertar()
	for b in _cuerpos.values():
		if b is RigidBody3D and is_instance_valid(b):
			(b as RigidBody3D).linear_velocity += v * randf_range(0.8, 1.2)


## SOLO PARA DIAGNOSTICO (--medirmuerte): sin CCD / sin choque entre cadaveres. De fabrica, apagados.
static var _diag_sin_ccd: bool = "--ragdollsinccd" in OS.get_cmdline_user_args()
static var _diag_sin_choque: bool = "--ragdollsinchoque" in OS.get_cmdline_user_args()
static var _diag_congelar: bool = "--cadaveresfps" in OS.get_cmdline_user_args()   ## dice cuando se congela cada uno
static var _diag_sin_congelar: bool = "--ragdollsincongelar" in OS.get_cmdline_user_args()   ## A/B: no dormirlos al caer

## LOS QUE NO SE VEN NO SE HACEN MUÑECO DE TRAPO (2026-10-13, pedido: "si esta lejos o una pared me lo tapa, que no
## lo procese"): a mas de RAGDOLL_LEJOS m de la camara, fuera del encuadre o con una pared en medio, no se montan los
## doce cuerpos con juntas; el que llama hace lo de siempre sin ragdoll (el cuerpo cae entero, un solo cuerpo). Si te lo
## llevas a hombros o te acercas, ya estaba en el suelo. --ragdollsiempre = como antes.
const RAGDOLL_LEJOS := 35.0
static var _siempre: int = -1

static func se_ve(skel: Skeleton3D) -> bool:
	if _siempre < 0:
		_siempre = 1 if "--ragdollsiempre" in OS.get_cmdline_user_args() else 0
	if _siempre == 1 or skel == null or not skel.is_inside_tree():
		return true
	var cam := skel.get_viewport().get_camera_3d()
	if cam == null:
		return true
	var p: Vector3 = skel.global_position + Vector3(0, 1.0, 0)
	var d: float = cam.global_position.distance_to(p)
	if d < 6.0:
		return true
	if d > RAGDOLL_LEJOS or not cam.is_position_in_frustum(p):
		return false
	var juego = Net.game
	var mundo = juego.get("world") if juego != null and is_instance_valid(juego) else null
	if mundo != null and mundo.has_method("raycast"):
		var h: Dictionary = mundo.raycast(cam.global_position, (p - cam.global_position) / d, d - 0.6)
		if bool(h.get("hit", false)):
			return false          # una pared en medio
	return true


## `forzar`: aunque no se vea (el precalentado de main bajo la pantalla de carga: el PRIMER ragdoll de la partida
## eran 8-9 ms, casi todo inicializar las juntas; los siguientes, ~1 ms).
## Al morir se le cierran los ojos despacio (avatar_animator.ojos_morir), haya ragdoll o no.
static func _cerrar_ojos(skel: Skeleton3D) -> void:
	var av := skel.get_parent()
	if av != null and av.has_method("ojos_morir"):
		av.ojos_morir()


static func crear(padre: Node, skel: Skeleton3D, vel: Vector3, empuje: Vector3, forzar := false) -> Node3D:
	if skel == null or not skel.is_inside_tree():
		return null
	_cerrar_ojos(skel)
	if not forzar and not se_ve(skel):
		return null
	var rd = load("res://scripts/ragdoll.gd").new()
	rd.name = "Ragdoll"
	rd.add_to_group("ragdolls")
	padre.add_child(rd)
	if not rd._construir(skel, vel, empuje):
		rd.queue_free()
		return null
	return rd


# ---------------------------------------------------------------------------
# RAGDOLL PARA CUALQUIER BICHO. El de arriba vale para el soldado porque conoce sus huesos por el
# nombre; los bichos del PvE tienen cada uno los suyos (cola, mandibulas, seis patas de araña, el
# Goliat con 37), asi que la cadena se saca DEL PROPIO ESQUELETO: se miden los huesos, se cogen los
# mas largos hasta el tope que se pida y cada uno cuelga del antepasado elegido mas cercano.
#
# Antes los monstruos caian como un muñeco de madera: un solo cuerpo rigido con el modelo colgado,
# que rueda y rebota pero por dentro sigue en la pose en la que murio. Con esto se aflojan.
# ---------------------------------------------------------------------------
const MIN_LARGO := 0.12        ## m: por debajo de esto el hueso no lleva cuerpo (dedos, parpados)
const MAX_CUERPOS := 12        ## tope por cadaver, que esto lo resuelve el motor en cada cuadro

static func crear_auto(padre: Node, skel: Skeleton3D, vel: Vector3, empuje: Vector3,
		max_cuerpos: int = MAX_CUERPOS) -> Node3D:
	if skel == null or not skel.is_inside_tree() or skel.get_bone_count() < 3:
		return null
	_cerrar_ojos(skel)
	if not se_ve(skel):
		return null
	var rd = load("res://scripts/ragdoll.gd").new()
	rd.name = "Ragdoll"
	padre.add_child(rd)
	if not rd._construir_auto(skel, vel, empuje, max_cuerpos):
		rd.queue_free()
		return null
	return rd


func _construir_auto(skel: Skeleton3D, vel: Vector3, empuje: Vector3, max_cuerpos: int) -> bool:
	_skel = skel
	var sg: Transform3D = skel.global_transform
	var n := skel.get_bone_count()
	var pos: Array[Vector3] = []
	for i in n:
		_idx[skel.get_bone_name(i)] = i
		pos.append((sg * skel.get_bone_global_pose(i)).origin)
	# el largo de cada hueso: hasta su primer hijo, y si no tiene, lo que mida el hueso en el rig
	var hijo := {}
	for i in n:
		var p := skel.get_bone_parent(i)
		if p >= 0 and not hijo.has(p):
			hijo[p] = i
	var largo: Array[float] = []
	for i in n:
		largo.append(pos[i].distance_to(pos[hijo[i]]) if hijo.has(i) else 0.0)
	# los que valen: ni controles de animacion ni cosas diminutas
	var candidatos: Array[int] = []
	for i in n:
		var nombre := skel.get_bone_name(i)
		if nombre.begins_with("IK_") or nombre.begins_with("POLE_") or nombre.begins_with("CTRL_"):
			continue
		if largo[i] >= MIN_LARGO:
			candidatos.append(i)
	if candidatos.size() < 3:
		return false
	candidatos.sort_custom(func(a, b): return largo[a] > largo[b])
	var elegidos := {}
	for i in candidatos.slice(0, max_cuerpos):
		elegidos[i] = true
	# ORDEN DE PADRES PRIMERO: la pose de un hueso se escribe relativa a su padre, asi que el padre
	# tiene que estar puesto antes.
	# OJO: `keys()` devuelve un Array sin tipo, y asignarlo tal cual a un Array[int] revienta en
	# ejecucion (y el ragdoll no llegaba a montarse nunca: los bichos seguian cayendo tiesos).
	var lista: Array[int] = []
	for k in elegidos.keys():
		lista.append(int(k))
	lista.sort_custom(func(a, b): return _hondura(skel, a) < _hondura(skel, b))
	for i in lista:
		var nombre := skel.get_bone_name(i)
		var ini: Vector3 = pos[i]
		var fin: Vector3 = pos[hijo[i]] if hijo.has(i) else ini + (sg * skel.get_bone_global_pose(i)).basis.y.normalized() * largo[i]
		var l: float = maxf(ini.distance_to(fin), 0.08)
		var r: float = clampf(l * 0.28, 0.045, 0.45)
		var rb := RigidBody3D.new()
		rb.collision_layer = 8      # capa de cadaveres: el jugador (mascara 5) NO choca con ellos; antes bloqueaban el paso (2026-09-18)
		rb.collision_mask = 1 if _diag_sin_choque else (1 | 8)   # contra el mundo y otros cadaveres
		rb.name = nombre
		rb.mass = clampf(l * 22.0, 1.2, 40.0)
		rb.linear_damp = 0.9
		rb.angular_damp = 3.2
		rb.continuous_cd = not _diag_sin_ccd
		rb.can_sleep = true
		var col := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = r
		cap.height = maxf(l, r * 2.2)
		col.shape = cap
		rb.add_child(col)
		add_child(rb)
		rb.global_transform = _mirando(ini + (fin - ini) * 0.5, fin - ini)
		rb.linear_velocity = vel + empuje * randf_range(0.8, 1.2)
		rb.angular_velocity = Vector3(randf_range(-2.0, 2.0), randf_range(-1.5, 1.5), randf_range(-2.0, 2.0))
		_cuerpos[nombre] = rb
		_off[nombre] = rb.global_transform.affine_inverse() * (sg * skel.get_bone_global_pose(i))
		_orden.append(nombre)
		# de quien cuelga: el antepasado elegido mas cercano (puede saltarse hombros y cuellos)
		var p := skel.get_bone_parent(i)
		while p >= 0 and not elegidos.has(p):
			p = skel.get_bone_parent(p)
		if p < 0:
			continue
		var j := ConeTwistJoint3D.new()
		j.set("swing_span", deg_to_rad(52.0))
		j.set("twist_span", deg_to_rad(16.0))
		# NADA DE `softness`: EL PROYECTO USA JOLT Y JOLT LA IGNORA.
		#
		# Ponerla no hacia nada salvo escribir un aviso del motor POR CADA ARTICULACION Y POR CADA
		# MUERTE. Medido en una partida LAN normal: 1.023 avisos, 22.000 lineas de registro, casi todo
		# esto. Y escribir en consola cuesta tiempo justo cuando mas pasa -en un tiroteo-.
		j.set("relaxation", 1.0)
		add_child(j)
		j.global_position = ini
		j.node_a = (_cuerpos[skel.get_bone_name(p)] as Node).get_path()
		j.node_b = (rb as Node).get_path()
	set_physics_process(true)
	return _cuerpos.size() >= 3


static func _hondura(skel: Skeleton3D, i: int) -> int:
	var d := 0
	var p := skel.get_bone_parent(i)
	while p >= 0:
		d += 1
		p = skel.get_bone_parent(p)
	return d


func _construir(skel: Skeleton3D, vel: Vector3, empuje: Vector3) -> bool:
	_skel = skel
	for i in skel.get_bone_count():
		_idx[skel.get_bone_name(i)] = i
	# el mundo del esqueleto: de aquí salen las posiciones en metros, ya con la escala del avatar
	var sg: Transform3D = skel.global_transform
	for fila in CADENA:
		var hueso: String = String(fila[0])
		if not _idx.has(hueso):
			return false
		var xf_h: Transform3D = sg * skel.get_bone_global_pose(_idx[hueso])
		var ini: Vector3 = xf_h.origin
		var fin: Vector3
		var punta: String = String(fila[1])
		if punta != "" and _idx.has(punta):
			fin = (sg * skel.get_bone_global_pose(_idx[punta])).origin
		else:
			# sin hueso siguiente: se estira en la dirección que ya lleva el hueso
			fin = ini + xf_h.basis.y.normalized() * 0.16
		var largo: float = maxf(ini.distance_to(fin), 0.06)
		var radio: float = float(fila[2])

		var rb := RigidBody3D.new()
		rb.collision_layer = 8      # capa de cadaveres: el jugador (mascara 5) NO choca con ellos; antes bloqueaban el paso (2026-09-18)
		rb.collision_mask = 1 if _diag_sin_choque else (1 | 8)   # contra el mundo y otros cadaveres
		rb.name = hueso
		rb.mass = clampf(largo * 22.0, 1.2, 14.0)
		# AMORTIGUADO, y bastante. Sin esto el ragdoll se sacude y parece electrocutado; el
		# roce es lo que hace que se desplome como un peso muerto en vez de rebotar.
		rb.linear_damp = 0.9
		rb.angular_damp = 3.2
		rb.continuous_cd = not _diag_sin_ccd      # a la velocidad de un disparo, sin esto atraviesa el suelo
		rb.can_sleep = true
		var col := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = radio
		cap.height = maxf(largo, radio * 2.2)
		col.shape = cap
		rb.add_child(col)
		add_child(rb)
		# la cápsula de Godot crece en Y: se orienta del inicio a la punta y se centra en medio
		var dir: Vector3 = (fin - ini)
		var centro: Vector3 = ini + dir * 0.5
		rb.global_transform = _mirando(centro, dir)
		rb.linear_velocity = vel + empuje * randf_range(0.8, 1.2)
		rb.angular_velocity = Vector3(randf_range(-2.0, 2.0), randf_range(-1.5, 1.5), randf_range(-2.0, 2.0))
		_cuerpos[hueso] = rb
		# lo que hay que deshacer para pasar del cuerpo al hueso al leerlo de vuelta
		_off[hueso] = rb.global_transform.affine_inverse() * xf_h
		_orden.append(hueso)

	# LAS JUNTAS, en el punto donde se tocan los dos huesos. Cono con torsión: es la que se parece a
	# una articulación de verdad -abre en abanico y gira poco- y la que evita el efecto goma.
	for hueso in _cuerpos.keys():
		if not PADRE.has(hueso):
			continue
		var pn: String = String(PADRE[hueso])
		if not _cuerpos.has(pn):
			continue
		var j := ConeTwistJoint3D.new()
		var lim: Array = LIMITE.get(hueso, [45.0, 20.0])
		j.set("swing_span", deg_to_rad(float(lim[0])))
		j.set("twist_span", deg_to_rad(float(lim[1])))
		# NADA DE `softness`: EL PROYECTO USA JOLT Y JOLT LA IGNORA.
		#
		# Ponerla no hacia nada salvo escribir un aviso del motor POR CADA ARTICULACION Y POR CADA
		# MUERTE. Medido en una partida LAN normal: 1.023 avisos, 22.000 lineas de registro, casi todo
		# esto. Y escribir en consola cuesta tiempo justo cuando mas pasa -en un tiroteo-.
		j.set("relaxation", 1.0)
		add_child(j)
		var art: Vector3 = (_skel.global_transform * _skel.get_bone_global_pose(_idx[hueso])).origin
		j.global_position = art
		j.node_a = (_cuerpos[pn] as Node).get_path()
		j.node_b = (_cuerpos[hueso] as Node).get_path()
	set_physics_process(true)
	return true


## Transformada que mira de un punto hacia una dirección con la cápsula tumbada en su eje Y.
func _mirando(centro: Vector3, dir: Vector3) -> Transform3D:
	var y: Vector3 = dir.normalized()
	if y.length_squared() < 0.0001:
		y = Vector3.UP
	# un eje cualquiera perpendicular, evitando el caso degenerado de que `y` sea el propio arriba
	var ref: Vector3 = Vector3.FORWARD if absf(y.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var x: Vector3 = ref.cross(y).normalized()
	var z: Vector3 = y.cross(x).normalized()
	return Transform3D(Basis(x, y, z), centro)


const QUIETO_V := 0.35          ## m/s: por debajo, una pieza esta quieta
const QUIETO_W := 1.5           ## rad/s
const QUIETO_S := 0.5           ## s seguidos con todas quietas para darlo por caido
const CONGELAR_MIN_S := 0.8     ## nunca antes de esto (el primer instante de la muerte puede ir lento)
const CONGELAR_MAX_S := 8.0     ## y como mucho esto, por si alguna pieza se queda temblando
var _vida := 0.0
var _quieto_t := 0.0
var congelado := false


## Ya ha caido: cada pieza pasa a ESTATICA (sin solver ni CCD) y la pose se queda como esta.
func _congelar() -> void:
	congelado = true
	if _diag_congelar:
		print("[ragdoll] congelado a los %.2f s (quieto %.2f s)" % [_vida, _quieto_t])
	for rb in _cuerpos.values():
		if is_instance_valid(rb):
			var b := rb as RigidBody3D
			b.continuous_cd = false
			b.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			b.freeze = true
	set_physics_process(false)


## Vuelve a simular (un empujon que llega tarde).
func despertar() -> void:
	if not congelado:
		return
	congelado = false
	_vida = 0.0
	_quieto_t = 0.0
	for rb in _cuerpos.values():
		if is_instance_valid(rb):
			var b := rb as RigidBody3D
			b.freeze = false
			b.continuous_cd = not _diag_sin_ccd
			b.sleeping = false
	set_physics_process(true)


## De la fisica al esqueleto mientras cae; al acabar de caer, se congela (ver la cabecera).
func _physics_process(dt: float) -> void:
	if _skel == null or not is_instance_valid(_skel):
		set_physics_process(false)
		return
	_vida += dt
	var quieto := true
	for rb in _cuerpos.values():
		if is_instance_valid(rb):
			var b := rb as RigidBody3D
			if not b.sleeping and (b.linear_velocity.length() > QUIETO_V or b.angular_velocity.length() > QUIETO_W):
				quieto = false
				break
	_quieto_t = _quieto_t + dt if quieto else 0.0
	if _vida >= CONGELAR_MIN_S and (_quieto_t >= QUIETO_S or _vida >= CONGELAR_MAX_S) and not _diag_sin_congelar:
		_copiar_pose()
		_congelar()
		return
	# SI TODAS LAS PIEZAS DUERMEN, no hay nada nuevo que copiar a los huesos este cuadro. No se
	# congela nada: en cuanto una pieza recibe un golpe el motor la despierta, deja de cumplirse esto
	# y la pose vuelve a seguir a la fisica.
	var todos_quietos := true
	for rb in _cuerpos.values():
		if is_instance_valid(rb) and not (rb as RigidBody3D).sleeping:
			todos_quietos = false
			break
	if todos_quietos:
		return
	_copiar_pose()


static var _estira: bool = "--ragdollestira" in OS.get_cmdline_user_args()

func _copiar_pose() -> void:
	# DE LA FISICA AL ESQUELETO. Se recorre en orden de padres primero, porque la pose de un hueso se
	# escribe RELATIVA a su padre y hace falta que el padre ya esté puesto.
	var inv: Transform3D = _skel.global_transform.affine_inverse()
	for hueso in _orden:
		var rb = _cuerpos.get(hueso)
		if rb == null or not is_instance_valid(rb):
			continue
		var i: int = _idx[hueso]
		# donde está el hueso en el mundo, según la física, y de ahí al espacio del esqueleto
		var mundo: Transform3D = (rb as RigidBody3D).global_transform * (_off[hueso] as Transform3D)
		var en_skel: Transform3D = inv * mundo
		var p: int = _skel.get_bone_parent(i)
		var local: Transform3D = en_skel
		if p >= 0:
			local = _skel.get_bone_global_pose(p).affine_inverse() * en_skel
		# SOLO LA CADERA TOMA LA POSICION DE LA FISICA (2026-10-28, bug: "al matar a un enemigo o darle con el mazo los
		# huesos se van del cuerpo, los brazos y las articulaciones se separan, se van lejos y se vuelven a acomodar").
		# Con un golpe fuerte las juntas de Jolt ceden un instante y las piezas se apartan; copiando su posicion, el
		# esqueleto se estiraba con ellas. Los demas huesos toman solo el GIRO y conservan su largo: el cuerpo no se
		# puede desarmar. `--ragdollestira` = como antes.
		if p < 0 or _estira:
			_skel.set_bone_pose_position(i, local.origin)
		else:
			_skel.set_bone_pose_position(i, _skel.get_bone_rest(i).origin)
		_skel.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())



