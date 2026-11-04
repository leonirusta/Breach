extends Node3D
## UNA PUERTA QUE SE ABRE SOLA. Las crea y las mueve `puertas.gd` (el gestor): esta no tiene _process
## propio, porque un mapa trae cientos y casi todas estan lejos de todo el mundo sin hacer nada.
##
## El nodo esta en el centro del umbral, a ras de suelo, girado `giro` grados sobre Y. En su espacio
## local la puerta ocupa el plano XY (ancho a lo largo de X) y se cruza a lo largo de Z. Cada hoja
## cuelga de un pivote en su bisagra; abrirla es girar ese pivote.
##
## EL HUECO YA VIENE TALLADO EN LOS VOXELS con este mismo ancho y alto: la puerta no quita ni pone
## voxels, solo tapa el agujero. Por eso el A* de los bots (que va por la rejilla) la cruza siempre,
## abierta o cerrada, y por eso tampoco hace falta decirle nada a la red: cada maquina ve a todos los
## personajes y abre la misma puerta por su cuenta.

const ANGULO := deg_to_rad(95.0)
## LA HOJA ES UN CUERPO CON BISAGRA, no una animacion. Tiene angulo y velocidad angular; un muelle (el
## "motor" de la puerta automatica) la lleva a donde quiere estar, y cualquier cosa puede empujarla por el
## camino: si la chocas corriendo se abre de golpe y rebota en el tope, si la empujas despacio cede despacio,
## una explosion la sacude. Soltada, vuelve con el muelle y se para por la amortiguacion.
const RIGIDEZ := 42.0          ## 1/s^2 del muelle cuando quiere estar abierta
const RIGIDEZ_CIERRE := 22.0   ## algo mas blando al cerrarse: se cierra sin portazo (amortiguado justo)
const AMORTIGUA := 9.0         ## 1/s
const REBOTE := 0.35           ## lo que conserva al chocar contra el tope (95 grados)
const VEL_MAX := 9.0           ## rad/s: ni un misil la hace girar como un ventilador
const GRUESO := 0.05           ## m de hoja
const HOLGURA := 0.02          ## m de aire entre la hoja y el marco, para que no roce

var ancho := 1.0
var alto := 2.2
var tipo := "madera"
var doble := false
var indice := -1

## -1, 0 o 1: hacia donde quiere estar abierta (0 = cerrada). El signo es el lado desde el que se ha
## llegado: se abre hacia el contrario, empujando hacia fuera de quien entra y nunca contra el.
var objetivo := 0.0
var abierta := 0.0             ## -1..1: donde esta ahora (angulo / ANGULO)
var ang := 0.0                 ## rad: + abre hacia -Z local con la hoja izquierda
var vel := 0.0                 ## rad/s
var sin_nadie_t := 0.0         ## s que lleva sin nadie cerca estando abierta
var caida := false             ## el marco ha reventado: la hoja se viene abajo y desaparece
var _caida_t := 0.0
var _hojas: Array[Node3D] = [] ## pivotes (uno o dos)
var _cuerpos: Array = []       ## AnimatableBody3D de cada hoja, solo si hay alguien cerca
var sondas_iniciales := -1
## SE ROMPE COMO LA MADERA. Vida de la hoja segun el material: las balas, los mazazos y las explosiones se la
## quitan (puertas.gd, danar) y al llegar a cero salta en trozos con fisica que caen al suelo.
const VIDA_TIPO := {"madera": 90.0, "cristal": 20.0, "metal": 350.0}
var vida := 90.0
var gestor = null               ## puertas.gd, para los materiales de los trozos     ## cuantos puntos del marco eran solidos al cargar el mapa
var marco_t := 0.0             ## cuando se miro el marco por ultima vez (segundos de partida)


## Monta las hojas con las mallas compartidas del gestor (una por tipo y tamaño, no una por puerta).
func montar(malla_hoja: Mesh) -> void:
	var n := 2 if doble else 1
	for i in n:
		var piv := Node3D.new()
		# la izquierda con la bisagra en -X y la hoja hacia +X; la derecha al reves (escala -1 en X
		# dejaria las normales del reves: se gira 180 grados en su lugar)
		if i == 0:
			piv.position = Vector3(-ancho * 0.5, 0.0, 0.0)
		else:
			piv.position = Vector3(ancho * 0.5, 0.0, 0.0)
		add_child(piv)
		var mi := MeshInstance3D.new()
		mi.mesh = malla_hoja
		# LEJOS NO SE DIBUJA. Cientos de puertas por el mapa: a mas de 120 m una hoja es un pixel y la
		# niebla ya se ha comido el hueco de todas formas.
		mi.visibility_range_end = 120.0
		mi.visibility_range_end_margin = 10.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if i == 1:
			mi.rotation.y = PI      # la hoja derecha mira al otro lado: su largo va hacia -X
		piv.add_child(mi)
		_hojas.append(piv)


## Cuerpo fisico de las hojas: solo mientras haya alguien cerca (lo decide el gestor). Asi Jolt no
## carga con seiscientas cajas cinematicas que no va a tocar nadie.
func set_cuerpo(on: bool) -> void:
	var tiene := not _cuerpos.is_empty()
	if on == tiene or (on and caida):
		return
	if not on:
		for c in _cuerpos:
			if is_instance_valid(c):
				c.queue_free()
		_cuerpos.clear()
		return
	var n := _hojas.size()
	var largo: float = ancho / float(n) - HOLGURA
	for i in n:
		var b := AnimatableBody3D.new()
		b.add_to_group("hoja_puerta")     # las balas la atraviesan (player.gd, fire)
		# SIN sync_to_physics. Con el, el cuerpo solo sigue SUS movimientos locales, y la hoja gira moviendo el
		# pivote (su padre): la colision se quedaba en la posicion de cerrada aunque la puerta se viera abierta,
		# una pared invisible en el hueco (medido con --pasapuertas: pasaban 4 de 32). Sin el, sigue la
		# bisagra; y lo que haria el empuje ya lo hace puertas.gd (la hoja cede a quien la toca).
		b.sync_to_physics = false
		b.collision_layer = 1
		b.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(largo, alto - HOLGURA, GRUESO + 0.03)
		cs.shape = bx
		cs.position = Vector3((largo * 0.5 + HOLGURA * 0.5) * (1.0 if i == 0 else -1.0), alto * 0.5, 0.0)
		b.add_child(cs)
		_hojas[i].add_child(b)
		_cuerpos.append(b)


func tiene_cuerpo() -> bool:
	return not _cuerpos.is_empty()


## Pide abrirse desde un lado (`lado` > 0: quien llega esta en +Z local). Si ya esta abierta hacia
## algun lado se queda asi: si no, al cruzar alguien por medio la puerta cambiaria de sentido y le daria
## en la cara al que viene detras.
func pedir_abrir(lado: float) -> void:
	sin_nadie_t = 0.0
	if objetivo != 0.0:
		return
	objetivo = -1.0 if lado > 0.0 else 1.0


func pedir_cerrar() -> void:
	objetivo = 0.0


## Avanza la bisagra. Devuelve true mientras siga moviendose (el gestor deja de llamarla cuando no).
func paso(dt: float) -> bool:
	if caida:
		return _paso_caida(dt)
	var meta: float = objetivo * ANGULO
	var k: float = RIGIDEZ if objetivo != 0.0 else RIGIDEZ_CIERRE
	vel += (k * (meta - ang) - AMORTIGUA * vel) * dt
	vel = clampf(vel, -VEL_MAX, VEL_MAX)
	ang += vel * dt
	if absf(ang) > ANGULO:
		ang = signf(ang) * ANGULO
		if vel * signf(ang) > 0.0:
			vel = -vel * REBOTE           # el tope: la hoja da contra la pared y rebota un poco
	abierta = ang / ANGULO
	_poner_angulo()
	return absf(vel) > 0.02 or absf(meta - ang) > 0.01


func _poner_angulo() -> void:
	for i in _hojas.size():
		# la hoja izquierda (bisagra en -X) va hacia -Z girando en positivo; la derecha, al reves
		_hojas[i].rotation.y = -ang if i == 0 else ang


## Algo le da un empujon: `dw` rad/s de golpe.
func empujar(dw: float) -> void:
	if caida:
		return
	vel = clampf(vel + dw, -VEL_MAX, VEL_MAX)


## Algo la esta empujando de forma continua (un cuerpo contra la hoja): cede al menos a `w` rad/s en el
## sentido de `w`. No se suma cada cuadro (se dispararia): la hoja va, como poco, a la velocidad del empuje.
func ceder(w: float) -> void:
	if caida:
		return
	if w > 0.0 and vel < w:
		vel = minf(w, VEL_MAX)
	elif w < 0.0 and vel > w:
		vel = maxf(w, -VEL_MAX)


## Direccion de la hoja `i` (de la bisagra a la punta) en el plano XZ local, y su bisagra.
func hoja_dir(i: int) -> Vector2:
	var s := 1.0 if i == 0 else -1.0
	return Vector2(s * cos(ang), sin(ang))


func hoja_bisagra(i: int) -> Vector2:
	return Vector2(-ancho * 0.5 if i == 0 else ancho * 0.5, 0.0)


func hoja_largo() -> float:
	return ancho / float(_hojas.size()) - HOLGURA


func n_hojas() -> int:
	return _hojas.size()


## Hacia donde tiene que girar (signo de dw) para que el punto de la hoja a `t` m de la bisagra se aparte
## de `p` (XZ local). 0 si da igual.
func sentido_apartar(i: int, t: float, p: Vector2) -> float:
	var d := hoja_dir(i)
	var h := hoja_bisagra(i)
	var s := 1.0 if i == 0 else -1.0
	var punto := h + d * t
	var n := p - punto
	# derivada de la punta con el angulo: por donde se mueve la hoja al abrir mas
	var m := Vector2(-s * sin(ang), cos(ang)) * t
	var proj := m.dot(n)
	if absf(proj) < 1e-5:
		return 0.0
	return -signf(proj)


## Puntos del marco en espacio local: las dos jambas (abajo y arriba) y el dintel. `vs` es el voxel.
func sondas(vs: float) -> Array:
	var fuera: float = ancho * 0.5 + maxf(vs, 0.1) * 1.5
	var arriba: float = alto + maxf(vs, 0.1) * 1.2
	return [Vector3(-fuera, 0.4, 0.0), Vector3(fuera, 0.4, 0.0),
		Vector3(-fuera, alto - 0.3, 0.0), Vector3(fuera, alto - 0.3, 0.0),
		Vector3(0.0, arriba, 0.0), Vector3(-ancho * 0.3, arriba, 0.0), Vector3(ancho * 0.3, arriba, 0.0)]


## Cuantos puntos del marco siguen siendo voxel. Leer un voxel suelto no necesita lock (CLAUDE.md:
## un dato desfasado un frame es inofensivo).
func sondas_solidas(world) -> int:
	var n := 0
	var vs: float = world.get_voxel_size() if world.has_method("get_voxel_size") else 0.2
	for s in sondas(vs):
		if int(world.get_material_at(to_global(s))) != 0:
			n += 1
	return n


## ¿Se ha quedado sin marco? Mas de la mitad de lo que era solido al cargar ya no esta. Una puerta que
## nacio sin nada alrededor (una cancela suelta) no se cae nunca por esto.
func marco_roto(world) -> bool:
	if sondas_iniciales <= 0:
		return false
	return sondas_solidas(world) * 2 <= sondas_iniciales


## ROTA: la hoja desaparece y salen los trozos, empujados hacia `hacia` (hacia donde iba lo que la rompio).
## Madera: tablones partidos. Cristal: esquirlas. Metal: dos chapas.
func romper(hacia: Vector3) -> void:
	if caida:
		return
	set_cuerpo(false)
	caida = true
	var n := _hojas.size()
	var largo: float = ancho / float(n) - HOLGURA
	for i in n:
		var piv: Node3D = _hojas[i]
		var s := 1.0 if i == 0 else -1.0
		var trozos: Array = []          # [centro en la hoja, tamaño]
		match tipo:
			"cristal":
				for k in 12:
					var tx := randf_range(0.1, largo - 0.1)
					trozos.append([Vector3(tx * s, randf_range(0.3, alto - 0.3), 0.0), Vector3(randf_range(0.08, 0.22), randf_range(0.08, 0.3), 0.012)])
			"metal":
				trozos.append([Vector3(largo * 0.5 * s, alto * 0.27, 0.0), Vector3(largo, alto * 0.52, GRUESO)])
				trozos.append([Vector3(largo * 0.5 * s, alto * 0.76, 0.0), Vector3(largo, alto * 0.46, GRUESO)])
			_:
				var filas := 5
				for f in filas:
					var y := (f + 0.5) * alto / filas
					var corte := randf_range(0.3, 0.7) * largo
					trozos.append([Vector3(corte * 0.5 * s, y, 0.0), Vector3(corte - 0.02, alto / filas - 0.03, GRUESO)])
					trozos.append([Vector3((corte + (largo - corte) * 0.5) * s, y, 0.0), Vector3(largo - corte - 0.02, alto / filas - 0.03, GRUESO)])
		for tr in trozos:
			_trozo(piv.to_global(tr[0]), piv.global_transform.basis, tr[1], hacia)
		piv.visible = false
	get_tree().create_timer(0.1).timeout.connect(queue_free)


func _trozo(pos: Vector3, base: Basis, tam: Vector3, hacia: Vector3) -> void:
	var b := RigidBody3D.new()
	b.collision_layer = 0          # nadie choca con los trozos (ni estorban ni paran balas)...
	b.collision_mask = 1           # ...pero ellos si caen sobre el mundo
	var dens: float = 7800.0 if tipo == "metal" else (2500.0 if tipo == "cristal" else 600.0)
	b.mass = maxf(0.2, tam.x * tam.y * tam.z * dens)
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(maxf(tam.x, 0.04), maxf(tam.y, 0.04), maxf(tam.z, 0.04))
	cs.shape = bx
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = tam
	mi.mesh = bm
	if gestor and gestor.has_method("_mat"):
		mi.material_override = gestor._mat(tipo if tipo in ["cristal", "metal"] else "madera")
	b.add_child(mi)
	get_tree().current_scene.add_child(b)
	b.global_transform = Transform3D(base, pos)
	var dir := hacia.normalized() if hacia.length() > 0.01 else Vector3.UP
	b.linear_velocity = dir * randf_range(2.0, 5.5) + Vector3(randf_range(-1, 1), randf_range(0.5, 2.5), randf_range(-1, 1))
	b.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	# se quedan un rato en el suelo y se van encogiendo
	var tw := b.create_tween()
	tw.tween_interval(randf_range(5.0, 7.0))
	tw.tween_property(b, "scale", Vector3.ONE * 0.05, 0.8)
	tw.tween_callback(b.queue_free)


## SIN MARCO, LA PUERTA SE CAE. No se queda flotando en mitad del hueco de una pared que ya no existe:
## la hoja vuelca hacia un lado y se hunde en el suelo en menos de un segundo.
func caer() -> void:
	if caida:
		return
	set_cuerpo(false)      # ya no tapa nada
	caida = true
	_caida_t = 0.0


func _paso_caida(dt: float) -> bool:
	_caida_t += dt
	var k: float = clampf(_caida_t / 0.7, 0.0, 1.0)
	# vuelca sobre su canto inferior (hacia +Z local) acelerando, como algo que pesa
	rotation_degrees.x = 88.0 * k * k
	if _caida_t > 0.7:
		position.y -= dt * 0.6          # y se hunde un poco antes de irse
	if _caida_t > 1.6:
		queue_free()
		return false
	return true
