extends RefCounted
## LA MARCHA VIVA Y LA MIRADA (2026-10-28, pedido: "cuando corren los movimientos son bruscos, estan bien hechos pero de
## modo simple; quiero que se sienta vivo: el cuerpo se inclina, casi se cae, apoya el pie y con la punta termina de
## elevarse... y que al mirar a los lados primero gire la cabeza, hasta unos 90 grados, y recien ahi el cuerpo, ayudandose
## con los pies").
##
## Una capa ENCIMA del clip, la misma para el jugador, los bots y los demas por la red (avatar_animator la llama despues de
## poner el clip y antes del arma). No cambia ningun clip: los pies siguen donde los pone la animacion y el CUERPO se mueve
## sobre ellos, con una IK de dos huesos por pierna que los deja plantados:
##   - el PESO DE CADA PISADA: al apoyar un pie la cadera se hunde y rebota (un muelle), y el tronco cabecea hacia delante
##     por la inercia y se recupera. Es lo que hace que un paso "pese".
##   - la CAIDA CONTROLADA: al arrancar el cuerpo se echa hacia delante (desde los tobillos y la cintura), al frenar se echa
##     atras y se asienta con un pequeño vaiven; en las curvas se inclina hacia dentro.
##   - el PESO DE LADO: la cadera va sobre el pie que carga.
##   - el DESPEGUE CON LA PUNTA: el pie de atras, antes de levantarse, gira sobre la bola del pie (talon arriba) con los
##     dedos apoyados.
##   - la CABEZA ESTABLE: el tronco gira y se balancea, la cabeza no (se le quita el alabeo y mira a donde tiene que mirar).
##   - la MIRADA EN CASCADA: cabeza -> pecho -> cadera. Mirando sin pelear, la cabeza gira sola hasta MIRA_CABEZA_MAX; mas
##     alla la sigue el pecho, y si la cintura se tuerce de mas (o se queda torcida un rato) la cadera se recoloca DANDO
##     PASOS (el clip de giro en el sitio). Disparando, apuntando o andando el pecho (y el arma) van con la mirada.
## `--sinmarchaviva` = todo como antes. `--sinmirada` quita solo la mirada.

const SIN_MARCHA := "--sinmarchaviva"
const SIN_MIRADA := "--sinmirada"
static var apagada: bool = SIN_MARCHA in OS.get_cmdline_user_args()
static var sin_mirada: bool = SIN_MIRADA in OS.get_cmdline_user_args()
## (se apago un rato creyendo que hacia patinar el pie en las curvas; medido otra vez solo con el pie clavado, con y sin
## talon da lo mismo: era ruido de pocas muestras)
static var _sin_talon: bool = "--sintalon" in OS.get_cmdline_user_args()
static var _log: bool = "--marchalog" in OS.get_cmdline_user_args()
var _log_pies := [Vector3.INF, Vector3.INF]

# --- la pisada -------------------------------------------------------------------------------------------------------
const MUELLE_F := 3.1            ## Hz del muelle vertical de la cadera
const MUELLE_Z := 0.52           ## amortiguamiento (menos de 1: rebota un poco)
const PISADA_V := 1.35           ## m/s que se hunde la cadera al apoyar, a toda velocidad (esprintando ~3,5 cm)
const PISADA_MAX := 0.06         ## m, tope del hundimiento
const CABECEO_V := 1.6          ## rad/s de cabeceo hacia delante al apoyar, a toda velocidad (~3 grados)
const CABECEO_F := 2.6
const CABECEO_Z := 0.5
const HISTERESIS := 0.010        ## m entre los dos pies para dar por cambiado el de apoyo
# --- la caida controlada -----------------------------------------------------------------------------------------------
## (2026-10-28, bug: los bots corriendo iban casi acostados: cambian de velocidad y de rumbo de golpe en cada esquina del
## camino, y con 0,020 / 0,20 / 0,14 la inclinacion llegaba a 15 grados delante, 12 atras y 9 de lado, sobre los 30 del
## clip de esprintar. Medido en la cafeteria con --marchalog)
const LEAN_K := 0.010            ## rad por m/s2 de aceleracion hacia delante
const LEAN_MAX := 0.10           ## rad hacia delante (11 grados)
const LEAN_MIN := -0.08          ## rad hacia atras al frenar
const LEAN_F := 1.9
const LEAN_Z := 0.46
const LEAN_VEL := 0.075          ## rad de mas hacia delante a toda velocidad (~4 grados; trotando ~2,7)
const LEAN_TOBILLO := 0.35       ## parte de la inclinacion que se hace desde los tobillos (todo el cuerpo); el resto, cintura
const BANCO_K := 0.010           ## rad por m/s2 de aceleracion de lado (en una curva)
const BANCO_MAX := 0.08
const ACEL_SUAVE := 5.0          ## 1/s con que se suaviza la aceleracion medida
# --- el peso de lado y la punta -------------------------------------------------------------------------------------------
const PESO_LADO := 0.16          ## fraccion del camino de la cadera hacia el pie que carga
const PESO_ANCHO := 0.05         ## m de diferencia de altura entre pies para cargar del todo uno
const FIJO_ALTO := 0.035         ## m por encima de su altura de apoyo a la que el pie todavia cuenta como apoyado
const FIJO_LEJOS := 0.32         ## m que puede separarse el clip del pie clavado antes de soltarlo
const FIJO_ALCANCE := 0.995      ## de la pierna estirada: mas lejos el pie clavado se suelta (probado 0,965: en el trote se soltaba siempre y patinaba)
const FIJO_ENTRA := 30.0         ## 1/s
const FIJO_SALE := 9.0
const REC_F := 4.2               ## Hz del cuerpo al disparar (a 7,5 cada tiro era un tiron de un cuadro: en rafaga, temblor)
const REC_Z := 0.55              ## amortiguado: encaja el tiro, rebota una vez y se asienta (a 0,32 temblaba)
const REC_PITCH := 1.5           ## rad/s hacia atras por disparo de fuerza 1 (en rafaga se suma: el cuerpo aguanta echado)
const REC_GIRO := 0.7            ## rad/s de giro al azar
const REC_ATRAS := 0.55          ## m/s que el cuerpo se va hacia atras (~1 cm)
const GUARDIA_BAJA := 0.030      ## m que baja la cadera en guardia (disparando o apuntando de pie): rodillas un poco
const GUARDIA_VEL := 3.5         ## 1/s con que entra y sale
const TIRO_RODILLAS := 0.22      ## m/s que la cadera cede hacia abajo con cada disparo de fuerza 1
const GOLPE_PITCH := 3.4         ## rad/s del tronco por un golpe de fuerza 1 (~4 grados)
const GOLPE_ALABEO := 3.0
const GOLPE_GIRO := 2.2
const GOLPE_RODILLAS := 0.45     ## m/s que ceden las rodillas
const ATERRIZA_V := 1.9          ## m/s que se hunde la cadera al caer de un salto normal (~5 cm)
const ATERRIZA_CAB := 2.2
const RESPIRA_S := 3.9           ## s por respiracion de pie
const RESPIRA_PECHO := 0.012     ## rad que el pecho se abre y se echa atras al tomar aire
const PESO_S := 6.3              ## s que tarda en pasar el peso de una pierna a la otra y volver
const PESO_QUIETO := 0.009       ## m de lado de ese vaiven
const TALON_MAX := 0.21          ## rad que sube la punta del pie de delante antes de apoyar (12 grados)
const PUNTA_MAX := 0.42          ## rad que gira el pie sobre su bola al despegar (24 grados)
# --- la cabeza ---------------------------------------------------------------------------------------------------------
const RECARGA_BAJA := 0.28       ## lo que baja la vista al recargar (seno del angulo: ~16 grados)
const RECARGA_GIRO := 0.18       ## rad hacia la mano de apoyo
const CABEZA_FIRME := 0.85       ## cuanto cabeceo del tronco se le quita a la cabeza
const CABEZA_ALABEO := 0.75      ## cuanto alabeo del tronco se le quita a la cabeza
# --- la mirada ---------------------------------------------------------------------------------------------------------
const MIRA_CABEZA_MAX := deg_to_rad(72.0)   ## lo que gira la cabeza sola sobre el pecho antes de que la siga el pecho
const MIRA_CINTURA_MAX := deg_to_rad(62.0)  ## lo que se tuerce la cintura antes de que la cadera de pasos
const MIRA_CINTURA_TOPE := deg_to_rad(88.0) ## de ahi no pasa nunca (la cadera se arrastra)
const MIRA_ASENTAR := deg_to_rad(24.0)      ## con la cintura torcida mas que esto un rato quieto, se recoloca
const MIRA_ASENTAR_S := 1.4
const GIRO_VEL := deg_to_rad(230.0)         ## rad/s de la cadera dando pasos
const GIRO_FIN := deg_to_rad(5.0)
const CABEZA_VEL := 12.0         ## 1/s con que la cabeza alcanza la mirada
const CABEZA_VEL_MAX := deg_to_rad(760.0)
const PECHO_PELEA := 26.0        ## 1/s del pecho disparando / apuntando
const PECHO_ANDANDO := 13.0
const PECHO_SUELTO := 7.0        ## 1/s con que el pecho se acerca a la cabeza cuando la pasa de MIRA_CABEZA_MAX
const CADERA_ANDANDO := 11.0

var av                            ## el avatar_animator
var _ok := false
var _bi := {}                     ## nombre -> indice de hueso
var w := 0.0                      ## cuanto manda la capa (0..1, entra y sale suave)
# la pisada
var _comp := 0.0
var _comp_v := 0.0
var _comp_media := 0.0            ## la media del muelle: se le quita para que el vaiven quede centrado (no hunda el cuerpo)
var _cab_media := 0.0
var _cab := 0.0
var _cab_v := 0.0
var _apoyo := 0                   ## -1 pie l, 1 pie r, 0 sin saber
# el retroceso del cuerpo al disparar (muelles rapidos: tiembla y se asienta)
var _rec := 0.0
var _rec_v := 0.0
var _rec_y := 0.0
var _rec_yv := 0.0
var _rec_z := 0.0
var _rec_zv := 0.0
var _f_cab0 := Vector3.FORWARD   ## hacia donde miraba la cabeza antes de mover el tronco
var _gol := 0.0                   ## alabeo del tronco por un golpe recibido (rad)
var _gol_v := 0.0
var _quieto := 0.0                ## 0..1: cuanto lleva de pie sin moverse (entra la respiracion y el peso)
var _vida_t := 0.0
var _fatiga := 0.0                ## 0..1: se llena corriendo; parado, respira mas rapido y hondo hasta que se calma
var _resp_fase := 0.0
var _fase := 0.0                  ## cada muñeco respira a su ritmo (no todos a la vez)
var mirada_libre := false         ## (bots) quieto y sin pelear, la cabeza mira a los lados de vez en cuando
var _libre_yaw := 0.0
var _libre_meta := 0.0
var _libre_pitch := 0.0
var _libre_pmeta := 0.0
var _libre_t := 2.0
var _recarga_w := 0.0             ## recargando, la cabeza mira el arma
var _guardia := 0.0              ## 0 de pie normal, 1 en guardia
# la caida controlada
var _pos_prev := Vector3.INF
var _vel_prev := Vector3.ZERO
var _acel := Vector3.ZERO         ## en el marco del cuerpo (x derecha, z atras)
var _lean := 0.0
var _lean_v := 0.0
var _banco := 0.0
var _banco_v := 0.0
var _lado := 0.0                  ## desplazamiento de la cadera hacia el pie que carga (unidades del esqueleto)
# la mirada (rumbos en el mundo, rad)
var _yaw_ok := false
var _y_cab := 0.0
var _y_pecho := 0.0
var _y_cadera := 0.0
var _girando := 0                 ## +1 la cadera gira a la derecha, -1 a la izquierda, 0 quieta
var _torcido_t := 0.0
# el pie plantado (0 = l, 1 = r)
var _fijo := [false, false]
var _fijo_w := [0.0, 0.0]
var _fijo_pos := [Vector3.ZERO, Vector3.ZERO]      ## donde se clavo (mundo)
var _h_suelo := [1.0, 1.0]                          ## la altura del tobillo cuando apoya (m, la mas baja reciente)
var _pel_escrita := Vector3.INF   ## la posicion de la cadera que escribio esta capa el cuadro anterior...
var _pel_delta := Vector3.ZERO     ## ...y lo que le sumo (los clips del .bin no la reponen cada cuadro: se acumulaba)
var _v_suave := Vector3.ZERO
var _v_suave_prev := Vector3.INF
var arma_yaw := 0.0               ## lo que gira el arma con el pecho (rad, sobre el cuello), lo aplica avatar_animator
var cabeza_yaw := 0.0             ## lo que tiene que girar la cabeza sobre el marco del esqueleto
var _mirada_on := true


func _init(avatar) -> void:
	av = avatar
	_fase = randf() * TAU
	for n in ["pelvis", "stomach", "chest", "neck", "head", "leg_upper_l", "leg_lower_l", "foot_l", "toes_l",
			"leg_upper_r", "leg_lower_r", "foot_r", "toes_r"]:
		if not av.bone_idx.has(n):
			return
		_bi[n] = av.bone_idx[n]
	_ok = true


static func _q(sk: Skeleton3D, i: int) -> Quaternion:
	return Quaternion(sk.get_bone_global_pose(i).basis.orthonormalized())


## Gira el hueso `i` en el marco del esqueleto (q delante de su giro global), sin tocar su posicion.
static func _girar(sk: Skeleton3D, i: int, q: Quaternion) -> void:
	var p := sk.get_bone_parent(i)
	var g := _q(sk, i)
	var pg := _q(sk, p) if p >= 0 else Quaternion.IDENTITY
	sk.set_bone_pose_rotation(i, (pg.inverse() * (q * g)).normalized())


## Pone el hueso `i` con este giro global (marco del esqueleto).
static func _poner(sk: Skeleton3D, i: int, g: Quaternion) -> void:
	var p := sk.get_bone_parent(i)
	var pg := _q(sk, p) if p >= 0 else Quaternion.IDENTITY
	sk.set_bone_pose_rotation(i, (pg.inverse() * g).normalized())


static func _yaw_de(b: Basis) -> float:
	var f: Vector3 = -b.z
	return atan2(-f.x, -f.z)


## Un muelle amortiguado. EN PASOS CHICOS (2026-10-28, bug: "los bots vibran despues de disparar, va 2 frames atras y
## adelante"): los bots se animan a 30, 20 u 8 Hz y les llega el tiempo acumulado (hasta 1/8 s); con un muelle de 7,5 Hz
## el paso de una vez se volvia inestable y el cuerpo temblaba en vez de asentarse. Se parte en pasos de 1/120 s como mucho
## y la velocidad se integra antes que la posicion (semi-implicito: estable).
static func _muelle(x: float, v: float, meta: float, f: float, z: float, dt: float) -> Vector2:
	var om := TAU * f
	var n: int = clampi(ceili(dt * 120.0), 1, 20)
	var h: float = minf(dt, 0.25) / float(n)
	for _i in n:
		var a := -om * om * (x - meta) - 2.0 * z * om * v
		v += a * h
		x += v * h
	return Vector2(x, v)


## UN DISPARO: el cuerpo encaja el golpe (2026-10-28, pedido: "cuando dispara, que vibre todo el cuerpo, el retroceso del
## cuerpo"). El pecho se va atras, gira un poco al azar y la cadera recula; los muelles lo devuelven temblando.
func disparo(fuerza: float) -> void:
	_rec_v += REC_PITCH * fuerza
	_rec_yv += randf_range(-1.0, 1.0) * REC_GIRO * fuerza
	_rec_zv += REC_ATRAS * fuerza
	_comp_v -= TIRO_RODILLAS * fuerza          # las rodillas encajan el golpe


## UN GOLPE RECIBIDO (2026-10-28, bucle de pulido): el tronco cede hacia donde empuja el golpe (atras si viene de
## frente, de lado si viene de lado), gira un poco y las rodillas flojean. `dir` en el mundo (hacia donde empuja).
func golpe(dir: Vector3, fuerza: float) -> void:
	var f: float = clampf(fuerza, 0.0, 1.6)
	var d: Vector3 = av.global_basis.orthonormalized().inverse() * dir
	d.y = 0.0
	if d.length() < 0.05:
		d = Vector3(randf_range(-0.4, 0.4), 0.0, 1.0)      # sin direccion: como de frente
	d = d.normalized()
	_rec_v += GOLPE_PITCH * f * d.z                       # +z (hacia atras del cuerpo) = se echa atras
	_gol_v += GOLPE_ALABEO * f * -d.x                    # empujado a su derecha (+x): se ladea a la derecha
	_rec_yv += randf_range(-1.0, 1.0) * GOLPE_GIRO * f
	_comp_v -= GOLPE_RODILLAS * f


## AL ATERRIZAR (2026-10-28, bucle de pulido): las piernas encajan el peso segun lo rapido que se caia (m/s hacia abajo):
## la cadera se hunde y rebota y el tronco cabecea hacia delante.
func aterrizar(v_caida: float) -> void:
	var f: float = clampf((v_caida - 1.5) / 6.0, 0.0, 1.2)
	if f <= 0.0:
		return
	_comp_v -= ATERRIZA_V * f
	_cab_v += ATERRIZA_CAB * f
	# en el aire la capa estaba apagada (clips de salto): entra ya, o el golpe se perderia mientras sube su peso
	w = maxf(w, 0.75)


## AGACHARSE O LEVANTARSE (bucle de pulido): el clip cambia de postura; esto le da el peso (al bajar se pasa un poco y
## vuelve, al subir un empujon) y un cabeceo.
func agacharse(abajo: bool) -> void:
	_comp_v += -0.55 if abajo else 0.35
	_cab_v += 0.9 if abajo else -0.6


## UN MAZAZO (bucle de pulido): el tronco se va hacia el golpe, gira con el swing y las rodillas meten el peso.
func mazazo() -> void:
	_cab_v += 2.4
	_rec_yv -= 1.6
	_comp_v -= 0.55


## El rumbo hacia el que se gira la cadera dando pasos (+1 = a su derecha), para que avatar_animator ponga el clip de
## giro en el sitio. 0 = no se esta girando.
func giro() -> int:
	return _girando if w > 0.5 else 0


func mirada_activa() -> bool:
	return _ok and not apagada and not sin_mirada and _mirada_on and w > 0.01


## Despues del clip (pose, cadera del clip, altura del suelo), antes de la columna y del arma.
## `quieto_clip` = esta en un clip de pie o andando (no un gesto de cuerpo entero); `en_suelo`, `lvel` (marco del cuerpo).
func paso(dt: float, permitido: bool, lvel: Vector3, en_suelo: bool, agachado: bool, pelea: bool) -> void:
	arma_yaw = 0.0
	cabeza_yaw = 0.0
	if not _ok or apagada or dt <= 0.0:
		return
	var sk: Skeleton3D = av.skeleton
	if sk == null:
		return
	w = move_toward(w, 1.0 if permitido else 0.0, dt * (3.0 if permitido else 6.0))
	var mt: Transform3D = av.global_transform
	var yaw_av: float = _yaw_de(mt.basis)
	# reaparecer o un salto de sitio: todo de nuevo, sin muelles ni cadera girada de antes
	if _pos_prev.is_finite() and mt.origin.distance_to(_pos_prev) > 3.0:
		reiniciar()
	_pos_prev = mt.origin
	# --- la aceleracion del cuerpo: de SU velocidad (la de la fisica, la que pasa drive_locomotion), suavizada. Medirla de
	# la posicion del nodo daba picos: la fisica mueve el cuerpo a sus pasos y el muñeco se dibuja a los suyos ---
	var v_cuerpo: Vector3 = Basis(Vector3.UP, yaw_av) * lvel
	_v_suave = _v_suave.lerp(v_cuerpo, 1.0 - exp(-18.0 * dt)) if _v_suave_prev.is_finite() else v_cuerpo
	var ac_mundo: Vector3 = (_v_suave - _v_suave_prev) / dt if _v_suave_prev.is_finite() else Vector3.ZERO
	_v_suave_prev = _v_suave
	ac_mundo.y = 0.0
	var ac_local: Vector3 = Basis(Vector3.UP, yaw_av).inverse() * ac_mundo
	ac_local = ac_local.limit_length(40.0)
	_acel = _acel.lerp(ac_local, 1.0 - exp(-ACEL_SUAVE * dt))
	_mirada(dt, yaw_av, lvel, en_suelo, pelea)
	if w <= 0.001:
		soltar_cadera()
		return
	var hs: float = Vector2(lvel.x, lvel.z).length()
	var sp: float = clampf(hs / 5.0, 0.0, 1.2)
	var anda: float = clampf((hs - 0.3) / 1.2, 0.0, 1.0) if en_suelo else 0.0
	var m_u: float = float(av.scale.x)    # metros por unidad del esqueleto
	if m_u <= 0.0:
		return
	var suelo_y: float = -sk.position.y
	var piv: Vector3 = sk.get_bone_global_pose(_bi["pelvis"]).origin
	# --- 1. la cadera mira con retraso (la mirada en cascada) ---
	var cad: float = wrapf(_y_cadera - yaw_av, -PI, PI) * w if mirada_activa() else 0.0
	if absf(cad) > 0.0005:
		_girar(sk, _bi["pelvis"], Quaternion(Vector3.UP, cad))
	# la mirada del clip (ya con la cadera girada): la cabeza la conserva mientras el tronco se mueve (paso 10)
	var ih0: int = _bi["head"]
	var f_loc0: Vector3 = sk.get_bone_global_rest(ih0).basis.orthonormalized().inverse() * Vector3.FORWARD
	_f_cab0 = (sk.get_bone_global_pose(ih0).basis.orthonormalized() * f_loc0).normalized()
	# --- 2. donde estan los pies segun el clip (ya con la cadera girada) ---
	var pies := []
	for lado in ["l", "r"]:
		var iu: int = _bi["leg_upper_" + lado]
		var il: int = _bi["leg_lower_" + lado]
		var i_f: int = _bi["foot_" + lado]
		var it: int = _bi["toes_" + lado]
		pies.append({"u": iu, "l": il, "f": i_f, "t": it,
			"cadera": sk.get_bone_global_pose(iu).origin, "rodilla": sk.get_bone_global_pose(il).origin,
			"tobillo": sk.get_bone_global_pose(i_f).origin, "bola": sk.get_bone_global_pose(it).origin,
			"qf": _q(sk, i_f), "qt": _q(sk, it)})
	var hl: float = ((pies[0]["tobillo"] as Vector3).y - suelo_y) * m_u
	var hr: float = ((pies[1]["tobillo"] as Vector3).y - suelo_y) * m_u
	# --- 3. el peso de cada pisada ---
	var nuevo := _apoyo
	if hl < hr - HISTERESIS:
		nuevo = -1
	elif hr < hl - HISTERESIS:
		nuevo = 1
	if nuevo != _apoyo:
		if _apoyo != 0 and anda > 0.0:
			_comp_v -= PISADA_V * sp * anda * (0.55 if agachado else 1.0)
			_cab_v += CABECEO_V * sp * anda * (0.5 if agachado else 1.0)
		_apoyo = nuevo
	var r := _muelle(_comp, _comp_v, 0.0, MUELLE_F, MUELLE_Z, dt)
	_comp = clampf(r.x, -PISADA_MAX, PISADA_MAX * 0.6)
	_comp_v = r.y
	r = _muelle(_cab, _cab_v, 0.0, CABECEO_F, CABECEO_Z, dt)
	_cab = clampf(r.x, -0.1, 0.12)
	_cab_v = r.y
	# los golpes de cada pisada van todos hacia abajo (y hacia delante): sin quitarles la media el cuerpo iba hundido
	# ~10 cm todo el rato. Lo que queda es el vaiven: baja al apoyar, sube al pasar por encima del pie
	_comp_media = lerpf(_comp_media, _comp, 1.0 - exp(-1.6 * dt))
	_cab_media = lerpf(_cab_media, _cab, 1.0 - exp(-1.6 * dt))
	var comp: float = _comp - _comp_media
	var cab: float = _cab - _cab_media
	r = _muelle(_rec, _rec_v, 0.0, REC_F, REC_Z, dt)
	_rec = clampf(r.x, -0.12, 0.2)
	_rec_v = r.y
	r = _muelle(_rec_y, _rec_yv, 0.0, REC_F * 0.8, REC_Z, dt)
	_rec_y = clampf(r.x, -0.12, 0.12)
	_rec_yv = r.y
	r = _muelle(_gol, _gol_v, 0.0, 4.2, 0.5, dt)
	_gol = clampf(r.x, -0.2, 0.2)
	_gol_v = r.y
	r = _muelle(_rec_z, _rec_zv, 0.0, REC_F * 0.7, 0.45, dt)
	_rec_z = clampf(r.x, -0.03, 0.05)
	_rec_zv = r.y
	# --- 4. la caida controlada: inclinarse con la aceleracion, ladearse en las curvas ---
	var lean_meta: float = clampf(-_acel.z * LEAN_K, LEAN_MIN, LEAN_MAX) * (1.0 if en_suelo else 0.3)
	# y la CAIDA CONSTANTE: corriendo hacia delante el cuerpo va algo echado, "cayendose" sobre cada paso
	if en_suelo and -lvel.z > 0.5:
		# (esprintando el clip ya va echado ~30 grados: casi nada mas)
		lean_meta += LEAN_VEL * clampf(-lvel.z / 5.0, 0.0, 1.0) * (0.4 if agachado else 1.0) * (1.0 - 0.75 * smoothstep(3.6, 4.8, hs))
	r = _muelle(_lean, _lean_v, lean_meta, LEAN_F, LEAN_Z, dt)
	_lean = clampf(r.x, LEAN_MIN * 1.4, LEAN_MAX * 1.3)
	_lean_v = r.y
	var banco_meta: float = clampf(_acel.x * BANCO_K, -BANCO_MAX, BANCO_MAX) * clampf(hs / 2.5, 0.0, 1.0)
	r = _muelle(_banco, _banco_v, banco_meta, 1.6, 0.6, dt)
	_banco = r.x
	_banco_v = r.y
	# --- 5. el peso de lado: la cadera sobre el pie que carga ---
	var marco := Basis(Vector3.UP, cad)                     # el marco de la cadera (girada con la mirada)
	var derecha: Vector3 = marco * Vector3.RIGHT
	var wl: float = clampf(0.5 + (hr - hl) / PESO_ANCHO, 0.0, 1.0)
	var p_pie: Vector3 = (pies[1]["tobillo"] as Vector3).lerp(pies[0]["tobillo"] as Vector3, wl)
	var lado_meta: float = (p_pie - piv).dot(derecha) * PESO_LADO * anda * (1.0 - 0.45 * clampf(sp, 0.0, 1.0))
	_lado = lerpf(_lado, lado_meta, 1.0 - exp(-12.0 * dt))
	# --- 5b. la GUARDIA (2026-10-28, pedido: "disparando no quede derecho tieso; una flexion sutil de las rodillas, como
	# una persona real para mantener el equilibrio"): de pie peleando la cadera baja un poco y las rodillas se doblan
	# (los pies siguen plantados: la IK) ---
	_guardia = move_toward(_guardia, 1.0 if pelea and en_suelo and hs < 0.6 else 0.0, GUARDIA_VEL * dt)
	var guardia_y: float = -GUARDIA_BAJA * smoothstep(0.0, 1.0, _guardia) * (0.4 if agachado else 1.0)
	# --- 5c. DE PIE QUIETO (bucle de pulido): respira y pasa el peso de una pierna a otra muy despacio. En guardia
	# casi no (se queda firme) ---
	_vida_t += dt
	_quieto = move_toward(_quieto, 1.0 if hs < 0.3 and en_suelo else 0.0, dt * (0.8 if hs < 0.3 else 4.0))
	var q_k: float = smoothstep(0.0, 1.0, _quieto) * (1.0 - 0.65 * _guardia)
	# EL CANSANCIO (bucle de pulido): corriendo se llena; parado se vacia en unos segundos y mientras respira mas rapido
	# y mas hondo (la fase se acumula: cambiar el periodo no da saltos)
	_fatiga = clampf(_fatiga + (dt * 0.25 if hs > 4.0 else -dt * 0.12), 0.0, 1.0)
	_resp_fase += dt * TAU / lerpf(RESPIRA_S, 1.5, _fatiga)
	var respira: float = sin(_resp_fase + _fase) * RESPIRA_PECHO * (1.0 + 2.2 * _fatiga) * q_k
	var peso_x: float = sin(_vida_t * TAU / PESO_S + _fase * 1.7) * PESO_QUIETO * q_k
	# --- 6. mover la cadera y girarla desde los pies ---
	var atras: Vector3 = marco * Vector3.BACK
	var pie_c: Vector3 = ((pies[0]["tobillo"] as Vector3) + (pies[1]["tobillo"] as Vector3)) * 0.5
	pie_c.y = suelo_y
	var q_cuerpo := (Quaternion(derecha, -_lean * LEAN_TOBILLO * w) * Quaternion(atras, -_banco * w)).normalized()
	var p_nueva: Vector3 = pie_c + q_cuerpo * (piv - pie_c)
	p_nueva += Vector3(0.0, (comp + guardia_y) / m_u, 0.0) * w + derecha * (_lado + peso_x / m_u) * w + atras * (_rec_z / m_u) * w
	var ip: int = _bi["pelvis"]
	_poner_cadera(sk, ip, p_nueva - piv)
	_girar(sk, ip, q_cuerpo)
	# --- 7. la cintura: la parte de la inclinacion que no va desde los tobillos, y el cabeceo de la pisada ---
	var cintura: float = (_lean * (1.0 - LEAN_TOBILLO) + cab - respira) * w
	if absf(cintura) > 0.0005:
		_girar(sk, _bi["stomach"], Quaternion(derecha, -cintura * 0.45))
		_girar(sk, _bi["chest"], Quaternion(derecha, -cintura * 0.55))
	# el retroceso: el pecho se echa atras y gira (la cabeza la endereza el paso 10, como hace uno al disparar)
	if absf(_rec) > 0.0003 or absf(_rec_y) > 0.0003 or absf(_gol) > 0.0003:
		var q_gol := Quaternion(atras, -_gol)
		_girar(sk, _bi["stomach"], Quaternion(derecha, _rec * 0.35 * w) * Quaternion(Vector3.UP, _rec_y * 0.4 * w) * q_gol.slerp(Quaternion.IDENTITY, 1.0 - 0.4 * w))
		_girar(sk, _bi["chest"], Quaternion(derecha, _rec * 0.65 * w) * Quaternion(Vector3.UP, _rec_y * 0.6 * w) * q_gol.slerp(Quaternion.IDENTITY, 1.0 - 0.6 * w))
	# --- 8. el pecho con la mirada (lo que la cintura se tuerce sobre la cadera) ---
	if mirada_activa():
		var torsion: float = wrapf(_y_pecho - _y_cadera, -PI, PI) * w
		if absf(torsion) > 0.0005:
			_girar(sk, _bi["stomach"], Quaternion(Vector3.UP, torsion * 0.4))
			_girar(sk, _bi["chest"], Quaternion(Vector3.UP, torsion * 0.6))
		arma_yaw = wrapf(_y_pecho - yaw_av, -PI, PI) * w
		cabeza_yaw = wrapf(_y_cab - yaw_av, -PI, PI) * w
	# MIRAR ALREDEDOR (bots quietos sin pelear, bucle de pulido): de vez en cuando la cabeza se va a un lado o al suelo y
	# vuelve; no toca el arma ni el cuerpo. El jugador y los de la red no: su cabeza dice a donde miran de verdad
	var libre_k: float = 1.0 if mirada_libre and not pelea and hs < 0.3 else 0.0
	_libre_t -= dt
	if _libre_t <= 0.0:
		_libre_t = randf_range(1.6, 4.5)
		var mira_lejos: bool = randf() < 0.6
		_libre_meta = randf_range(-0.6, 0.6) if mira_lejos else 0.0
		_libre_pmeta = randf_range(-0.12, 0.18) if mira_lejos else 0.0
	_libre_yaw = lerpf(_libre_yaw, _libre_meta * libre_k, 1.0 - exp(-3.2 * dt))
	_libre_pitch = lerpf(_libre_pitch, _libre_pmeta * libre_k, 1.0 - exp(-3.2 * dt))
	cabeza_yaw += _libre_yaw * w
	# RECARGANDO MIRA EL ARMA (bucle de pulido): la vista baja al cargador y se gira un poco hacia la mano de apoyo
	_recarga_w = move_toward(_recarga_w, 1.0 if bool(av.reloading) else 0.0, dt * (3.5 if bool(av.reloading) else 2.5))
	cabeza_yaw += RECARGA_GIRO * smoothstep(0.0, 1.0, _recarga_w) * w
	# --- 9. las piernas, otra vez a sus pies: el de apoyo CLAVADO en el suelo (no patina) y el de atras despega sobre la
	# punta ---
	var punta_k: float = clampf(hs / 3.0, 0.0, 1.0) * anda * w * (0.4 if agachado else 1.0)
	var adelante: Vector3 = marco * Vector3.FORWARD
	var xf: Transform3D = sk.global_transform
	var xf_inv: Transform3D = xf.affine_inverse()
	var clavar: bool = (anda > 0.2 or _girando != 0) and w > 0.5 and en_suelo
	for k in 2:
		var pie: Dictionary = pies[k]
		pie["adelante"] = adelante
		var tob0: Vector3 = pie["tobillo"]
		var tob: Vector3 = tob0
		var qf: Quaternion = pie["qf"]
		var h: float = (tob0.y - suelo_y) * m_u
		_h_suelo[k] = minf(_h_suelo[k] + 0.08 * dt, h)
		var apoya: bool = h < _h_suelo[k] + FIJO_ALTO
		var w_clip: Vector3 = xf * tob0
		if clavar and apoya and not _fijo[k]:
			_fijo[k] = true
			_fijo_pos[k] = w_clip
		if _fijo[k]:
			var lejos: float = Vector2(w_clip.x - _fijo_pos[k].x, w_clip.z - _fijo_pos[k].z).length()
			var cad_w: Vector3 = xf * (pie["cadera"] as Vector3)
			var alcance: float = ((pie["rodilla"] as Vector3) - (pie["cadera"] as Vector3)).length() 				+ (tob0 - (pie["rodilla"] as Vector3)).length()
			var llega: bool = (cad_w - _fijo_pos[k]).length() < alcance * xf.basis.get_scale().x * FIJO_ALCANCE
			if not clavar or not apoya or lejos > FIJO_LEJOS or not llega:
				_fijo[k] = false
		_fijo_w[k] = move_toward(_fijo_w[k], 1.0 if _fijo[k] else 0.0, dt * (FIJO_ENTRA if _fijo[k] else FIJO_SALE))
		if _fijo_w[k] > 0.001:
			var meta_w: Vector3 = Vector3(_fijo_pos[k].x, w_clip.y, _fijo_pos[k].z)
			tob = tob0.lerp(xf_inv * meta_w, smoothstep(0.0, 1.0, _fijo_w[k]))
		if punta_k > 0.001 and -lvel.z > absf(lvel.x) * 0.5:
			var bola: Vector3 = (pie["bola"] as Vector3) + (tob - tob0)
			var atras_n: float = (tob - (pie["cadera"] as Vector3)).dot(-adelante) / maxf(((pie["cadera"] as Vector3) - tob0).length(), 0.01)
			var baja: float = 1.0 - smoothstep(0.025, 0.09, (bola.y - suelo_y) * m_u)
			var th: float = PUNTA_MAX * smoothstep(0.12, 0.5, atras_n) * baja * punta_k
			if th > 0.002:
				var v: Vector3 = tob - bola
				var eje: Vector3 = Vector3.UP.cross(adelante).normalized()
				if (Quaternion(eje, th) * v).y < v.y:
					eje = -eje
				var qr := Quaternion(eje, th)
				tob = bola + qr * v
				qf = (qr * qf).normalized()
		# EL TALON PRIMERO (bucle de pulido): el pie de delante llega al suelo con la punta levantada
		var qt_pie: Quaternion = pie["qt"]
		if punta_k > 0.001 and -lvel.z > absf(lvel.x) * 0.5 and not _fijo[k] and not _sin_talon:
			var del_n: float = -(tob - (pie["cadera"] as Vector3)).dot(-adelante) / maxf(((pie["cadera"] as Vector3) - tob0).length(), 0.01)
			var sobre: float = h - _h_suelo[k]
			var th2: float = TALON_MAX * smoothstep(0.1, 0.4, del_n) * (1.0 - smoothstep(0.03, 0.13, sobre)) * punta_k
			if th2 > 0.002:
				var eje2: Vector3 = Vector3.UP.cross(adelante).normalized()
				var punta_v: Vector3 = (pie["bola"] as Vector3) - tob0
				if (Quaternion(eje2, th2) * punta_v).y < punta_v.y:
					eje2 = -eje2
				var qr2 := Quaternion(eje2, th2)
				qf = (qr2 * qf).normalized()
				qt_pie = (qr2 * qt_pie).normalized()
		pie["qt"] = qt_pie
		_pierna(sk, pie, tob, qf)
	# --- 10. la cabeza estable, mirando a donde tiene que mirar ---
	_cabeza(sk, marco)
	if _log:
		var txt := ""
		for k in 2:
			var wp: Vector3 = sk.global_transform * sk.get_bone_global_pose(_bi["foot_" + ["l", "r"][k]]).origin
			var h: float = wp.y - av.global_position.y
			var desliz: float = 0.0 if not _log_pies[k].is_finite() else Vector2(wp.x - _log_pies[k].x, wp.z - _log_pies[k].z).length() / dt
			_log_pies[k] = wp
			txt += " pie%s h %.3f v %.2f" % [["l", "r"][k], h, desliz]
			txt += " fijo%d %.2f" % [k, _fijo_w[k]]
		var hw: Vector3 = sk.global_transform * sk.get_bone_global_pose(_bi["head"]).origin
		print("[marchalog] rec %.3f w %.2f hs %.2f comp %.3f cab %.3f lean %.3f banco %.3f lado %.3f cadera %.1f pecho %.1f cabeza %.1f nodo %.1f gira %d cabeza_y %.3f%s" % [
			_rec, w, hs, comp, cab, _lean, _banco, _lado * m_u, rad_to_deg(_y_cadera), rad_to_deg(_y_pecho), rad_to_deg(_y_cab),
			rad_to_deg(yaw_av), _girando, hw.y - av.global_position.y, txt])


## La posicion de la cadera = la del clip + `delta`. Si nadie la ha tocado desde que la escribimos, la del clip es la de
## antes de nuestro delta.
func _poner_cadera(sk: Skeleton3D, ip: int, delta: Vector3) -> void:
	var ahora: Vector3 = sk.get_bone_pose_position(ip)
	var base: Vector3 = ahora - _pel_delta if ahora.is_equal_approx(_pel_escrita) else ahora
	var nueva: Vector3 = base + delta
	sk.set_bone_pose_position(ip, nueva)
	_pel_escrita = nueva
	_pel_delta = delta


## Sin la capa este cuadro: la cadera, sin lo nuestro.
func soltar_cadera() -> void:
	var sk: Skeleton3D = av.skeleton
	if not _ok or sk == null or not _pel_escrita.is_finite():
		return
	var ip: int = _bi["pelvis"]
	if sk.get_bone_pose_position(ip).is_equal_approx(_pel_escrita):
		sk.set_bone_pose_position(ip, _pel_escrita - _pel_delta)
	_pel_escrita = Vector3.INF
	_pel_delta = Vector3.ZERO


## IK de dos huesos: muslo y tibia hasta el tobillo `meta`, conservando el plano de la rodilla del clip; el pie con el giro
## `qf` y los dedos como venian (apoyados).
func _pierna(sk: Skeleton3D, pie: Dictionary, meta: Vector3, qf: Quaternion) -> void:
	var iu: int = pie["u"]
	var il: int = pie["l"]
	var i_f: int = pie["f"]
	var it: int = pie["t"]
	var c0: Vector3 = pie["cadera"]
	var k0: Vector3 = pie["rodilla"]
	var t0: Vector3 = pie["tobillo"]
	var a: float = (k0 - c0).length()
	var b: float = (t0 - k0).length()
	if a < 0.01 or b < 0.01:
		return
	var c: Vector3 = sk.get_bone_global_pose(iu).origin
	var hacia: Vector3 = meta - c
	var d: float = clampf(hacia.length(), absf(a - b) + 0.01, a + b - 0.005)
	var dir: Vector3 = hacia.normalized() if hacia.length() > 0.0001 else (t0 - c0).normalized()
	# el plano de la rodilla: hacia donde sale la rodilla del clip respecto a la linea cadera-tobillo
	var eje0: Vector3 = (t0 - c0).normalized()
	var polo: Vector3 = (k0 - c0) - eje0 * (k0 - c0).dot(eje0)
	if polo.length() < 0.05:
		polo = pie.get("adelante", Vector3.FORWARD)      # pierna recta en el clip: la rodilla sale hacia delante
	polo = (polo - dir * polo.dot(dir)).normalized()
	var cos_a: float = clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var rod: Vector3 = c + dir * (a * cos_a) + polo * (a * sqrt(1.0 - cos_a * cos_a))
	# muslo: de donde apunta ahora a donde tiene que apuntar
	var k_ahora: Vector3 = sk.get_bone_global_pose(il).origin
	var v1: Vector3 = (k_ahora - c).normalized()
	var v2: Vector3 = (rod - c).normalized()
	if v1.dot(v2) < 0.99999:
		_girar(sk, iu, Quaternion(v1, v2))
	var k1: Vector3 = sk.get_bone_global_pose(il).origin
	var t_ahora: Vector3 = sk.get_bone_global_pose(i_f).origin
	var v3: Vector3 = (t_ahora - k1).normalized()
	var v4: Vector3 = (c + dir * d - k1).normalized()
	if v3.dot(v4) < 0.99999:
		_girar(sk, il, Quaternion(v3, v4))
	_poner(sk, i_f, qf)
	_poner(sk, it, pie["qt"])


## Le quita a la cabeza el alabeo del tronco (y casi todo su giro) y la pone mirando a `cabeza_yaw`, conservando el
## cabeceo del clip. Se reparte entre cuello (40 %) y cabeza.
func _cabeza(sk: Skeleton3D, _marco: Basis) -> void:
	var ih: int = _bi["head"]
	var inn: int = _bi["neck"]
	var reposo: Basis = sk.get_bone_global_rest(ih).basis.orthonormalized()
	var f_loc: Vector3 = reposo.inverse() * Vector3.FORWARD
	var u_loc: Vector3 = reposo.inverse() * Vector3.UP
	var g: Basis = sk.get_bone_global_pose(ih).basis.orthonormalized()
	var f: Vector3 = (g * f_loc).normalized()
	var u: Vector3 = (g * u_loc).normalized()
	if absf(f.y) > 0.97:
		return
	# el cabeceo: el que traia el clip, no el que le dan la pisada, la inclinacion o el retroceso del tronco (la mirada se
	# queda firme, como la de una persona al correr o al disparar)
	var fy: float = clampf(lerpf(f.y, clampf(_f_cab0.y, -0.95, 0.95), CABEZA_FIRME) - _libre_pitch * w
		- RECARGA_BAJA * smoothstep(0.0, 1.0, _recarga_w) * w, -0.95, 0.95)
	var horiz := sqrt(maxf(1.0 - fy * fy, 0.0))
	var fd := Vector3(-sin(cabeza_yaw) * horiz, fy, -cos(cabeza_yaw) * horiz).normalized()
	var lado: Vector3 = fd.cross(Vector3.UP).normalized()
	var ud_recto: Vector3 = lado.cross(fd).normalized()
	# el alabeo que traia, quitado en CABEZA_ALABEO
	var u_proy: Vector3 = (u - fd * u.dot(fd)).normalized()
	var ud: Vector3 = u_proy.slerp(ud_recto, CABEZA_ALABEO) if u_proy.length() > 0.5 else ud_recto
	var ahora := Basis.looking_at(f, u)
	var meta := Basis.looking_at(fd, ud)
	var delta := Quaternion((meta * ahora.inverse()).orthonormalized())
	var dw: Quaternion = Quaternion.IDENTITY.slerp(delta, w)
	var qn: Quaternion = Quaternion.IDENTITY.slerp(dw, 0.4)
	_girar(sk, inn, qn)
	_girar(sk, ih, (dw * qn.inverse()).normalized())


## La cascada de la mirada: la cabeza va a donde mira el muñeco (su nodo), el pecho la sigue con retraso y la cadera la
## ultima, dando pasos si estando quieto la cintura se tuerce de mas.
func _mirada(dt: float, yaw_av: float, lvel: Vector3, en_suelo: bool, pelea: bool) -> void:
	if not _yaw_ok or not mirada_activa() and w <= 0.01:
		_y_cab = yaw_av
		_y_pecho = yaw_av
		_y_cadera = yaw_av
		_yaw_ok = true
		_girando = 0
		return
	var hs: float = Vector2(lvel.x, lvel.z).length()
	var andando: bool = hs > 0.35 or not en_suelo
	# la cabeza: rapida, pero no instantanea (un bot que se da la vuelta de golpe gira la cabeza en un instante, no en cero)
	var dc: float = wrapf(yaw_av - _y_cab, -PI, PI)
	_y_cab += clampf(dc * (1.0 - exp(-CABEZA_VEL * dt)), -CABEZA_VEL_MAX * dt, CABEZA_VEL_MAX * dt)
	_y_cab = wrapf(_y_cab, -PI, PI)
	# el pecho
	var dp: float = wrapf(_y_cab - _y_pecho, -PI, PI)
	if pelea:
		_y_pecho += dp * (1.0 - exp(-PECHO_PELEA * dt))
	elif andando:
		_y_pecho += dp * (1.0 - exp(-PECHO_ANDANDO * dt))
	else:
		# suelto: la cabeza gira sola; el pecho solo sigue lo que pase de MIRA_CABEZA_MAX
		var sobra: float = signf(dp) * maxf(absf(dp) - MIRA_CABEZA_MAX, 0.0)
		_y_pecho += sobra * (1.0 - exp(-PECHO_SUELTO * 2.0 * dt))
		# y si se queda mirando a un lado, el pecho se va acercando despacio
		_y_pecho += dp * (1.0 - exp(-0.9 * dt))
	_y_pecho = wrapf(_y_pecho, -PI, PI)
	# la cadera
	var dh: float = wrapf(_y_pecho - _y_cadera, -PI, PI)
	if andando:
		_girando = 0
		_torcido_t = 0.0
		_y_cadera += wrapf(yaw_av - _y_cadera, -PI, PI) * (1.0 - exp(-CADERA_ANDANDO * dt))
	else:
		_torcido_t = _torcido_t + dt if absf(dh) > MIRA_ASENTAR else 0.0
		if _girando == 0 and (absf(dh) > MIRA_CINTURA_MAX or _torcido_t > MIRA_ASENTAR_S):
			_girando = 1 if dh < 0.0 else -1
		if _girando != 0:
			var paso_g: float = minf(GIRO_VEL * dt, absf(dh))
			_y_cadera += signf(dh) * paso_g
			if absf(wrapf(_y_pecho - _y_cadera, -PI, PI)) <= GIRO_FIN:
				_girando = 0
				_torcido_t = 0.0
	# nunca mas torcido que el tope (con un giro de golpe, la cadera se arrastra)
	var dt2: float = wrapf(_y_pecho - _y_cadera, -PI, PI)
	if absf(dt2) > MIRA_CINTURA_TOPE:
		_y_cadera = wrapf(_y_pecho - signf(dt2) * MIRA_CINTURA_TOPE, -PI, PI)
	_y_cadera = wrapf(_y_cadera, -PI, PI)


## Para colocarlo de golpe (reaparecer, montar el muñeco): todo mirando donde mira el nodo, sin muelles.
func reiniciar() -> void:
	_yaw_ok = false
	_pos_prev = Vector3.INF
	_vel_prev = Vector3.ZERO
	_acel = Vector3.ZERO
	_comp = 0.0
	_comp_v = 0.0
	_comp_media = 0.0
	_cab_media = 0.0
	_cab = 0.0
	_cab_v = 0.0
	_lean = 0.0
	_lean_v = 0.0
	_banco = 0.0
	_banco_v = 0.0
	_lado = 0.0
	_rec = 0.0
	_gol = 0.0
	_gol_v = 0.0
	_guardia = 0.0
	_rec_v = 0.0
	_rec_y = 0.0
	_rec_yv = 0.0
	_rec_z = 0.0
	_rec_zv = 0.0
	_girando = 0
	_fijo = [false, false]
	_fijo_w = [0.0, 0.0]
	_v_suave_prev = Vector3.INF
