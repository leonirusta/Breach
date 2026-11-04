extends SkeletonModifier3D
class_name MirarBicho
## LA CRIATURA TE MIRA Y TE ALCANZA. Las animaciones son fijas: el Goliat mordia siempre a la misma
## altura (la suya, a 5 metros) y zarpeaba al aire, asi que de cerca parecia que peleaba con un fantasma
## mientras tu le disparabas a las rodillas. Y quieto delante de ti se quedaba mirando al frente.
##
## Esto se ejecuta DESPUES de la animacion (por eso es un SkeletonModifier3D y no codigo suelto en
## _physics_process: ahi el AnimationPlayer volveria a pisar los huesos el mismo cuadro) y corrige dos
## cosas sobre lo que ya hizo el clip:
##
## 1. LA MIRADA Y LA INCLINACION. La cadena espalda -> pecho -> cuello -> cabeza gira lo justo para que
##    el morro apunte a donde estas. Si estas abajo, el bicho se dobla hacia abajo; es lo mismo que
##    hace un perro para olerte los pies. Con `agacha` el reparto se carga en la espalda y el pecho,
##    que es lo que hace que BAJE de verdad (para morder) en vez de solo estirar el cuello.
## 2. LOS BRAZOS. Cinematica inversa de dos huesos (hombro y codo) para que la mano acabe DONDE ESTAS,
##    no donde decia el clip. El codo se queda en el plano en el que ya estaba, asi que el gesto sigue
##    siendo el de la animacion: solo se estira o se acorta.
##
## Todo va con peso: a 0 manda la animacion tal cual. Los huesos que no existan en ese bicho se saltan,
## asi que el mismo modificador vale para el zombi, la araña y el jefe.

## A donde mira (en MUNDO). Lo pone criatura.gd cada cuadro.
var objetivo := Vector3.ZERO
## 0..1: cuanto hace caso a `objetivo` la cadena del tronco.
var peso := 0.0
## 0..1: cuanto se reparte el giro hacia ABAJO (espalda y pecho) en vez de solo cuello y cabeza.
var agacha := 0.0
## 0..1 y de que lados ("l", "r"): los brazos que van a por el objetivo.
var peso_brazos := 0.0
var brazos: Array = []
## Hasta donde por encima del suelo se apunta (el pecho del jugador lo pone criatura.gd en `objetivo`).
var cadena: Array = ["spine", "chest", "neck", "head"]
## El punto del bicho que tiene que quedar apuntando: el morro. Si no hay, la cabeza.
var punta_nombres: Array = ["nariz", "jaw", "head"]

## Cuanto pone cada hueso de la cadena, mirando de frente y agachandose.
const REPARTO := [0.14, 0.22, 0.30, 0.34]
const REPARTO_AGACHA := [0.34, 0.30, 0.22, 0.14]
## Tope por hueso, que si no se dobla como un calcetin.
const TOPE := [0.42, 0.52, 0.70, 0.85]      ## radianes (24, 30, 40, 49 grados)
## Lo que tarda el peso en subir y bajar: sin esto, al empezar el ataque la cabeza pega un salto.
const SUAVE := 6.0

## LO QUE SE QUEDA A FALTAR, en metros, para la prueba --goliatmira. Se mide AQUI DENTRO porque desde
## fuera `get_bone_global_pose` devuelve la pose de la animacion, sin las correcciones de este modificador:
## midiendolo fuera parecia que la mano seguia a 2,5 m cuando en realidad se queda a 45 cm.
var dist_morro := -1.0
var dist_mano := -1.0
var _suave := 0.0
var _suave_brazos := 0.0
var _idx: Array = []            ## indices de la cadena (-1 los que no existen)
var _idx_punta := -1
var _cache_para: Skeleton3D = null


func _buscar(skel: Skeleton3D) -> void:
	_idx.clear()
	for n in cadena:
		_idx.append(skel.find_bone(String(n)))
	_idx_punta = -1
	for n in punta_nombres:
		var i := skel.find_bone(String(n))
		if i >= 0:
			_idx_punta = i
			break
	_cache_para = skel


func _process_modification_with_delta(dt: float) -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	if _cache_para != skel:
		_buscar(skel)
	_suave = move_toward(_suave, clampf(peso, 0.0, 1.0), dt * SUAVE)
	_suave_brazos = move_toward(_suave_brazos, clampf(peso_brazos, 0.0, 1.0), dt * SUAVE)
	var obj: Vector3 = skel.global_transform.affine_inverse() * objetivo
	if _suave <= 0.002 and _suave_brazos <= 0.002:
		_medir(skel, obj)
		return
	if _suave > 0.002 and _idx_punta >= 0:
		_inclinar(skel, obj)
		_apuntar(skel, obj)
	if _suave_brazos > 0.002:
		for lado in brazos:
			_brazo(skel, String(lado), obj)
	_medir(skel, obj)


func _medir(skel: Skeleton3D, obj: Vector3) -> void:
	var esc: float = skel.global_transform.basis.get_scale().x
	if _idx_punta >= 0:
		dist_morro = skel.get_bone_global_pose(_idx_punta).origin.distance_to(obj) * esc
	dist_mano = -1.0
	for lado in ["l", "r"]:
		var i := skel.find_bone("hand_" + lado)
		if i >= 0:
			var d: float = skel.get_bone_global_pose(i).origin.distance_to(obj) * esc
			dist_mano = d if dist_mano < 0.0 else minf(dist_mano, d)


## LA CINTURA. Con la espalda sola no llega: el brazo del Goliat mide 3 m y el bicho pega desde casi
## 4, asi que por mucho que gire el tronco la mano se queda en el aire. Doblando la CADERA hacia ti, el
## hombro entero se viene adelante y abajo, que es de donde sale el alcance de verdad.
##
## Y LAS PIERNAS SE QUEDAN DONDE ESTABAN: los muslos cuelgan de la cadera, asi que al doblarla se irian
## hacia atras y el bicho pareceria que se cae de espaldas. Se les deshace el mismo giro, y quedan de
## pie mientras el cuerpo se echa encima de ti, como cuando alguien se agacha a coger algo del suelo.
const TOPE_CADERA := 0.38        ## radianes (22 grados)

func _inclinar(skel: Skeleton3D, obj: Vector3) -> void:
	var bi := skel.find_bone("pelvis")
	if bi < 0 or _idx_punta < 0:
		return
	var pose := skel.get_bone_global_pose(bi)
	var punta: Vector3 = skel.get_bone_global_pose(_idx_punta).origin
	var a: Vector3 = punta - pose.origin
	var b: Vector3 = obj - pose.origin
	if a.length() < 0.02 or b.length() < 0.02:
		return
	a = a.normalized()
	b = b.normalized()
	var eje: Vector3 = a.cross(b)
	if eje.length() < 0.0001:
		return
	eje = eje.normalized()
	var ang: float = acos(clampf(a.dot(b), -1.0, 1.0)) * lerpf(0.10, 0.34, clampf(agacha, 0.0, 1.0)) * _suave
	ang = clampf(ang, -TOPE_CADERA, TOPE_CADERA)
	if absf(ang) < 0.0005:
		return
	skel.set_bone_global_pose(bi, Transform3D(Basis(eje, ang) * pose.basis, pose.origin))
	for pierna in ["thigh_l", "thigh_r", "leg_upper_l", "leg_upper_r"]:
		var pi := skel.find_bone(pierna)
		if pi < 0:
			continue
		var pp := skel.get_bone_global_pose(pi)
		skel.set_bone_global_pose(pi, Transform3D(Basis(eje, -ang) * pp.basis, pp.origin))


## LA CADENA. Cada hueso gira una parte del angulo que le falta al morro para apuntarte, empezando por
## la espalda. Es el metodo de toda la vida (CCD) con una sola pasada: mas pasadas afinarian mas, pero
## esto no tiene que ser exacto, tiene que parecer un bicho mirandote.
func _apuntar(skel: Skeleton3D, obj: Vector3) -> void:
	for i in _idx.size():
		var bi: int = _idx[i]
		if bi < 0:
			continue
		var pose := skel.get_bone_global_pose(bi)
		var punta: Vector3 = skel.get_bone_global_pose(_idx_punta).origin
		var a: Vector3 = punta - pose.origin
		var b: Vector3 = obj - pose.origin
		if a.length() < 0.02 or b.length() < 0.02:
			continue
		a = a.normalized()
		b = b.normalized()
		var eje: Vector3 = a.cross(b)
		if eje.length() < 0.0001:
			continue
		var reparto: float = lerpf(REPARTO[i], REPARTO_AGACHA[i], clampf(agacha, 0.0, 1.0))
		var ang: float = acos(clampf(a.dot(b), -1.0, 1.0)) * reparto * _suave
		ang = clampf(ang, -TOPE[i], TOPE[i])
		if absf(ang) < 0.0005:
			continue
		skel.set_bone_global_pose(bi, Transform3D(Basis(eje.normalized(), ang) * pose.basis, pose.origin))


## UN BRAZO HASTA DONDE ESTAS. Dos huesos, como una rodilla al reves: se calcula donde cae el codo para
## que la mano llegue al objetivo (trigonometria, no iteraciones) y se gira cada hueso hacia ahi. El
## codo se queda en el plano donde ya estaba, para no cambiar el gesto de la animacion.
func _brazo(skel: Skeleton3D, lado: String, obj: Vector3) -> void:
	var i0 := skel.find_bone("upperarm_" + lado)
	var i1 := skel.find_bone("forearm_" + lado)
	var i2 := skel.find_bone("hand_" + lado)
	if i0 < 0 or i1 < 0 or i2 < 0:
		return
	var p0: Vector3 = skel.get_bone_global_pose(i0).origin
	var p1: Vector3 = skel.get_bone_global_pose(i1).origin
	var p2: Vector3 = skel.get_bone_global_pose(i2).origin
	var l1: float = p0.distance_to(p1)
	var l2: float = p1.distance_to(p2)
	if l1 < 0.01 or l2 < 0.01:
		return
	# PEGA CON LAS GARRAS, NO CON LA MUÑECA (2026-09-23, pedido). El hueso de la mano nace en la muñeca, y era la
	# muñeca lo que se llevaba hasta ti. Ahora la muñeca se queda a un largo de mano (lo que mide la mano del
	# esqueleto, o 0,6 m) antes del objetivo: lo que te alcanza son los dedos.
	var largo_mano: float = 0.6
	var i3 := -1
	for ch in skel.get_bone_children(i2):
		i3 = ch
		break
	if i3 >= 0:
		largo_mano = clampf(p2.distance_to(skel.get_bone_global_pose(i3).origin) * 1.2, 0.3, 1.0)
	obj = obj - (obj - p0).normalized() * largo_mano
	# el objetivo, sin pasarse del alcance del brazo (estirado del todo se ve el tiron)
	var meta: Vector3 = p0 + (obj - p0).limit_length((l1 + l2) * 0.98)
	meta = p2.lerp(meta, _suave_brazos)
	var eje: Vector3 = meta - p0
	var d: float = clampf(eje.length(), 0.05, (l1 + l2) * 0.999)
	eje = eje.normalized()
	# EL CODO SE DOBLA COMO UN CODO (2026-09-23, pedido: "los codos se le rompen"). Se usaba el plano que
	# traia la animacion; con el brazo casi estirado ese plano no existe y el recambio (hacia delante) lo
	# doblaba al reves. Ahora hay un lado natural -hacia fuera y hacia atras del cuerpo, un poco abajo- y el
	# codo nunca se dobla hacia el lado contrario: si el de la animacion apunta al reves, se usa el natural.
	var natural: Vector3 = Vector3(signf(p0.x) if absf(p0.x) > 0.01 else (1.0 if lado == "l" else -1.0), 0.0, 0.0) * 0.55 + Vector3(0.0, -0.25, -1.0)   # atras = -Z en el Goliat (en Blender mira a -Y, que el glTF pasa a +Z)
	natural = (natural - eje * natural.dot(eje))
	var polo: Vector3 = (p1 - p0) - eje * (p1 - p0).dot(eje)
	if polo.length() < l1 * 0.2:   # brazo casi recto: la animacion no dice hacia donde doblar, se usa el natural
		polo = natural
	if polo.length() < 0.001:
		return
	polo = polo.normalized()
	var c: float = clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var codo: Vector3 = p0 + eje * (l1 * c) + polo * (l1 * sqrt(maxf(0.0, 1.0 - c * c)))
	_girar_hacia(skel, i0, p1, codo)
	var mano: Vector3 = skel.get_bone_global_pose(i2).origin
	_girar_hacia(skel, i1, mano, p0 + eje * d)


## gira el hueso `bi` sobre su origen para que el punto `desde` acabe apuntando a `hasta`
func _girar_hacia(skel: Skeleton3D, bi: int, desde: Vector3, hasta: Vector3) -> void:
	var pose := skel.get_bone_global_pose(bi)
	var a: Vector3 = desde - pose.origin
	var b: Vector3 = hasta - pose.origin
	if a.length() < 0.01 or b.length() < 0.01:
		return
	a = a.normalized()
	b = b.normalized()
	var eje: Vector3 = a.cross(b)
	if eje.length() < 0.0001:
		return
	var ang: float = acos(clampf(a.dot(b), -1.0, 1.0))
	skel.set_bone_global_pose(bi, Transform3D(Basis(eje.normalized(), ang) * pose.basis, pose.origin))
