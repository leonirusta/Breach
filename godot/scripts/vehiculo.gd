extends VehicleBody3D
## UN VEHICULO CONDUCIBLE. Lo crea y lo destruye el gestor (vehiculos.gd); aqui esta lo que es un coche:
## el modelo, las ruedas, la conduccion, la camara de quien va dentro y lo que pasa cuando se rompe.
##
## LOS MODELOS SON DE VOXELES (13 cm), hechos en Blender con tools/blender/vehiculos y exportados a
## `godot/vehiculos/<tipo>.glb` + `vehiculos.json`. La ficha trae, YA EN COORDENADAS DE GODOT, los
## asientos, las ruedas con su radio, el motor, el escape, los faros y (el helicoptero) los rotores.
## Aqui no se mide nada del modelo: se lee la ficha.
##
## RUEDAS: cada `VehicleWheel3D` va en el sitio que dice la ficha y la malla de la rueda cuelga de el, asi
## que la suspension y el giro de la direccion mueven la malla solos. El mundo es de voxels, pero Jolt le
## pone cuerpos estaticos a los chunks de alrededor, que es contra lo que ruedan.
##
## QUIEN CONDUCE MANDA. El jugador que va al volante mueve el vehiculo en SU maquina y manda la postura
## (Net.net_vehiculo); los demas solo la copian. Es lo mismo que se hace con los bloques: una sola maquina
## decide y las otras miran, que es lo unico que no se desincroniza.
##
## EL JUGADOR NO ES UN PASAJERO FISICO: mientras va dentro, el vehiculo le lleva la posicion a mano
## (`paso_jugador`, igual que el avion del salto) y su capsula no choca con nada. Meterlo como cuerpo
## dentro de otro cuerpo solo da temblores.

## El motor de cada tipo: un bucle de un segundo sintetizado (tools/generar_sonidos_vehiculos.py) al que
## se le cambia el tono con las vueltas. Sale del sitio del motor que dice la ficha.
const MOTORES := {
	"coche": "res://sounds/vehiculos/motor_coche.wav",
	"todoterreno": "res://sounds/vehiculos/motor_coche.wav",
	"moto": "res://sounds/vehiculos/motor_moto.wav",
	"helicoptero": "res://sounds/vehiculos/motor_heli.wav",
}

## Conduccion por tipo: fuerza del motor, freno, angulo de direccion (grados), velocidad tope (m/s),
## y el agarre. Son los numeros de un arcade, no de un simulador: esto es un battle royale.
const AJUSTE := {
	"coche":        {"motor": 5200.0, "freno": 55.0, "giro": 30.0, "tope": 27.0, "agarre": 3.2, "vida": 800.0},
	"todoterreno":  {"motor": 8000.0, "freno": 70.0, "giro": 28.0, "tope": 24.0, "agarre": 3.6, "vida": 1300.0},
	"moto":         {"motor": 1800.0, "freno": 28.0, "giro": 40.0, "tope": 30.0, "agarre": 2.6, "vida": 350.0},
	"helicoptero":  {"motor": 0.0,    "freno": 0.0,  "giro": 0.0,  "tope": 32.0, "agarre": 1.0, "vida": 900.0},
}

const MARCHA_ATRAS := 0.75      ## de la fuerza del motor hacia atras (iba tan lenta que no servia)
const TOPE_ATRAS := 0.55        ## del tope de velocidad, hacia atras
const CAMARA := Vector3(0.0, 1.25, 5.6)     ## detras y arriba del vehiculo (coche)
## EL HELICOPTERO MIDE 8,2 m Y LA CAMARA IBA A 3. Estas dos constantes estaban escritas pero NADIE
## LAS USABA: la camara de tercera persona se quedaba en los 3,05 m de siempre (player.gd,
## TP_OFFSET), que para un coche pasa y para un helicoptero es tenerlo pegado a la cara. Ahora las
## lee `camara_offset()`.
const CAMARA_HELI := Vector3(0.0, 3.8, 14.5)


## Donde va la camara de tercera persona cuando vas en este vehiculo: detras y arriba, y mas lejos
## cuanto mas grande es lo que conduces.
func camara_offset() -> Vector3:
	return CAMARA_HELI if tipo == "helicoptero" else CAMARA
## Lo que hay que bajar al jugador para que, sentado, la cabeza le quede a ~0,8 m del asiento.
const ALTURA_SENTADO := 0.80
const ALCANCE_ENTRAR := 3.2     ## m a los que se puede subir
const SALTO_SALIR := 1.2        ## m al lado donde te deja al bajarte
const DANO_CHOQUE := 0.9        ## vida por cada m/s de golpe por encima del umbral
const CHOQUE_MIN := 7.0         ## m/s: por debajo, un roce no hace nada
const ATROPELLO := 4.0          ## m/s (14 km/h) a partir de los que atropellar hace dano
const ATROPELLO_DANO := 13.0    ## dano por m/s por encima de ATROPELLO (a 100 por hora, mata)

# --- EMBESTIR ---------------------------------------------------------------------------------------
## LO QUE TE LLEVAS POR DELANTE. Un coche lanzado contra una valla la revienta; a paso de hombre, no. El
## boquete y lo que es capaz de romper crecen con la velocidad, y cada embestida te frena y te abolla.
const EMBESTIR_MIN := 4.5       ## m/s (16 km/h): por debajo no se rompe nada, solo se choca
const EMBESTIR_TODO := 22.0     ## m/s (80 km/h): de aqui para arriba se lleva por delante lo que sea
## EL BOQUETE VA CON EL ANCHO DEL VEHICULO, no es un numero fijo: una moto abre un agujero de moto y un
## todoterreno se lleva por delante un trozo de pared de su tamaño. Estos dos numeros son la parte del
## ancho que se lleva: a la velocidad minima, poco mas que un roce; a tope, el morro entero.
const EMBESTIR_R_MIN := 0.32    ## del ancho del vehiculo, a la velocidad minima
const EMBESTIR_R_MAX := 1.05    ## del ancho del vehiculo, a toda velocidad
## Dureza que es capaz de romper: poca a poca velocidad (madera, matorral, valla) y todo a mucha. Es el
## mismo numero que usa el motor para las explosiones.
const EMBESTIR_POT_MIN := 90
const EMBESTIR_POT_MAX := 255
const EMBESTIR_FRENO := 0.55    ## lo que te queda de velocidad tras llevarte algo por delante
const EMBESTIR_DANO := 18.0     ## vida que te cuesta cada embestida, por metro de boquete

# --- BALAS CONTRA LA CHAPA -------------------------------------------------------------------------
## Un vehiculo NO es a prueba de balas. Cada impacto le quita vida y suelta chispas donde pega; cuando
## se le acaba, revienta igual que si lo hubieras estrellado. Donde pegas importa: arriba estan los
## cristales y delante el motor, y los dos se llevan mas que una puerta.
const BALA_DANO := 1.0          ## multiplica al daño del arma (un fusil son ~25 por tiro)
const BALA_CRISTAL := 1.8       ## si pega en la parte de arriba (cristales)
const BALA_MOTOR := 1.5         ## si pega en el morro (el motor)

# --- LAS HELICES CORTAN ----------------------------------------------------------------------------
## Un rotor a 300 revoluciones no rebota contra las cosas: las parte. Lo que el disco toque se talla
## (pared, arbol, valla) y a quien toque lo mata. Y el helicoptero se lleva su parte: una helice que
## muerde hormigon no sigue entera mucho rato.
const ROTOR_GIRO_MIN := 0.45    ## de 0 a 1: por debajo el rotor va demasiado lento para cortar
const ROTOR_SONDAS := 6         ## puntos del disco que se miran por mordisco (giran: lo barren entero)
const ROTOR_CADENCIA := 0.05    ## s entre mordiscos: sin esto se inunda la red de tallados
const ROTOR_POT := 200          ## dureza que corta (la misma escala que las explosiones)
const ROTOR_DANO_PERSONA := 250.0   ## lo que se lleva quien toque el disco: mata
## Lo que le cuesta al helicoptero cada mordisco. Bajo a proposito: a 20 mordiscos por segundo, con
## 40 se destrozaba solo en segundo y medio de rozar una pared (medido). Con 4 aguanta unos diez
## segundos comiendo hormigon, que es justo lo que se quiere: corta, pero se gasta.
const ROTOR_DANO_PROPIO := 4.0

# --- helicoptero -----------------------------------------------------------------------------------
const HELI_SUBIDA := 13.0       ## m/s2 de mas sobre la gravedad con el colectivo al maximo
## EL EMPUJE, Y POR QUE ERA TAN LENTO. El cuerpo lleva `linear_damp = 0.35`, o sea que la velocidad
## se queda donde el empuje empata con el rozamiento: con 9,0 x 0,35 = 3,15 m/s2 el tope real eran
## 10 m/s (36 km/h) por mucho que la ficha dijera 32. Medido con --pruebaheli. Con 13 m/s2 el tope
## sale por encima del de la ficha, asi que manda la ficha y no el rozamiento.
const HELI_EMPUJE := 13.0       ## m/s2 hacia donde se empuja
const HELI_GIRO := 1.6          ## rad/s de guiñada
## Cuanto se tumba al empujar. Es lo que se VE de que el helicoptero va a algun lado: con 0,42 se
## quedaba en 12 grados de verdad (el par no llegaba a mas), que no se nota.
const HELI_INCLINA := 0.52      ## rad de inclinacion maxima
const HELI_PAR := 3.4           ## fuerza con la que busca esa inclinacion (antes 2,2: se quedaba corto)
## BAJAR. Con el colectivo a cero la sustentacion valia EXACTAMENTE la gravedad, asi que agachandose
## el helicoptero se quedaba flotando y no bajaba nunca (medido: -0,5 m/s, o sea que subia). El
## colectivo puede ponerse en negativo, que es quitar paso a las palas y caer.
const HELI_COLECTIVO_MIN := -0.55

var tipo := "coche"
var ficha: Dictionary = {}
var id := -1                    ## el numero de punto del mapa (el mismo en todas las maquinas)
var vida := 800.0
var vida_max := 800.0
var conductor = null            ## el jugador local, si va al volante
var pasajero = null             ## el jugador local, si va de pasajero
var mi_asiento := -1
var _dentro_t := 0.0            ## s desde que te subiste (ver paso_jugador)            ## en que asiento va el jugador local (-1 = no va dentro)
## asiento -> peer que lo ocupa. Lo mismo en todas las maquinas (lo reparte la red).
var ocupados: Dictionary = {}
var remoto := false             ## lo conduce otro: aqui solo se copia la postura que llega
var gestor = null

var _ruedas: Array = []         ## VehicleWheel3D en el orden de la ficha
var _rotores: Array = []        ## [nodo, eje, rpm, radio] del helicoptero
var _rotor_t := 0.0             ## cuenta atras entre mordiscos de la helice
var _rotor_fase := 0.0          ## por donde va el barrido del disco
var cortados := 0               ## cuantas cosas ha cortado la helice (para las pruebas)
var balazos := 0                ## impactos de bala recibidos (para las pruebas)
var _faros: Array = []
var _cuerpo: Node3D = null
var _colectivo := 0.0           ## helicoptero: 0..1
var _motor_on := false
var _audio: AudioStreamPlayer3D = null
var _cartel: Label3D = null
var _luz_dentro: OmniLight3D = null
var color := Color.WHITE       ## el color de ESTE vehiculo
var pintadas := 0              ## superficies de carroceria repintadas (para las pruebas)
var _t_red := 0.0
var _roto := false
var _humo := 0.0
var _vuelco := 0.0
var _atropellados := 0          ## para las pruebas
var _tp_antes := false          ## si el jugador iba en tercera persona antes de subirse
var _v_antes := Vector3.ZERO    ## la velocidad del cuadro anterior (para medir los frenazos)
var _bots: Dictionary = {}      ## asiento -> bot sentado dentro
var _capa_jug := 0              ## la colision que tenia el jugador antes de subirse
var _mascara_jug := 0              ## s boca arriba del reves


static func ajuste_de(t: String) -> Dictionary:
	return AJUSTE.get(t, AJUSTE["coche"])


func construir(t: String, f: Dictionary) -> void:
	tipo = t
	ficha = f
	var aj: Dictionary = ajuste_de(t)
	vida_max = float(aj["vida"])
	vida = vida_max
	mass = float(f.get("masa", 1200.0))
	# el centro de masas bajo: sin esto un coche de voxels vuelca en la primera curva
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, float(f["tamano"][1]) * 0.12, 0.0)   # cuanto mas bajo, menos vuelca y menos bota
	continuous_cd = true
	max_contacts_reported = 4
	contact_monitor = true
	body_entered.connect(_on_choque)
	add_to_group("vehiculos")

	var esc: PackedScene = escena_de(t)
	_cuerpo = esc.instantiate()
	add_child(_cuerpo)
	_pintar()
	# la caja de colision: el modelo entero menos un poco, levantada a su sitio
	var tam: Array = f["tamano"]
	var caja := BoxShape3D.new()
	# LA CAJA NO PUEDE BAJAR DE LAS RUEDAS. Con la caja rozando el suelo el coche va arrastrando la panza:
	# empuja el motor entero y no pasa de 40 por hora. El bajo de la caja queda por encima del eje.
	# EL BAJO DE LA CAJA. En un coche va por encima del eje de las ruedas (con menos, el chasis raspa en
	# cuanto la suspension comprime). EL HELICOPTERO NO TIENE RUEDAS: se le ponia el radio por defecto y
	# la caja le empezaba a 56 cm del suelo, o sea que los patines quedaban fuera, el aparato se hundia
	# en el terreno y no habia manera de despegar (medido: 5,6 m en ocho segundos, cuando antes subia 160).
	var suelo := 0.06
	var ruedas: Array = f.get("ruedas", [])
	if not ruedas.is_empty():
		var radio_r := 0.0
		for r in ruedas:
			radio_r = maxf(radio_r, float(r["radio"]))
		suelo = radio_r + 0.22
	var altura: float = maxf(0.5, float(tam[1]) - suelo)
	caja.size = Vector3(float(tam[0]) * 0.92, altura, float(tam[2]) * 0.94)
	var cs := CollisionShape3D.new()
	cs.shape = caja
	cs.position = Vector3(0.0, suelo + altura * 0.5, 0.0)
	add_child(cs)

	_montar_luz_interior(f)
	_montar_motor(f, aj)
	_montar_ruedas(f, aj)
	_montar_rotores(f)
	_montar_faros(f)
	if tipo == "helicoptero":
		gravity_scale = 1.0
		angular_damp = 2.5
		linear_damp = 0.35


## LAS ESCENAS DE LOS VEHICULOS SE QUEDAN EN MEMORIA (2026-10-01, medido en la isla: crear el primer coche de un tipo
## al acercarse eran 130-260 ms leyendo su .glb en plena partida, y al alejarse y liberarlo Godot lo soltaba y la
## siguiente vez otra vez). `vehiculos.gd` las pide en hilos al cargar el mapa; aqui se recogen.
static var _escenas: Dictionary = {}     # tipo -> PackedScene
static var _pedidas: Dictionary = {}     # tipo -> ruta encargada en un hilo

static func pedir_en_hilos(tipos: Array) -> void:
	for t0 in tipos:
		var t := String(t0)
		var ruta := "res://vehiculos/%s.glb" % t
		if _escenas.has(t) or _pedidas.has(t) or not ResourceLoader.exists(ruta):
			continue
		if ResourceLoader.load_threaded_request(ruta) == OK:
			_pedidas[t] = ruta

static func escena_de(t: String) -> PackedScene:
	var ps: PackedScene = _escenas.get(t)
	if ps != null:
		return ps
	var ruta := "res://vehiculos/%s.glb" % t
	if _pedidas.has(t):
		_pedidas.erase(t)
		ps = ResourceLoader.load_threaded_get(ruta) as PackedScene
	if ps == null:
		ps = load(ruta) as PackedScene
	if ps != null:
		_escenas[t] = ps
	return ps


## Colores de carroceria. Son los de un aparcamiento de verdad (y ninguno blanco: en un mapa de voxels
## claros, un coche blanco desaparece contra el suelo).
const PINTURAS := [
	Color(0.62, 0.10, 0.09), Color(0.10, 0.22, 0.52), Color(0.10, 0.36, 0.20), Color(0.78, 0.55, 0.06),
	Color(0.12, 0.13, 0.15), Color(0.36, 0.38, 0.42), Color(0.55, 0.28, 0.08), Color(0.28, 0.12, 0.40),
	Color(0.05, 0.42, 0.45), Color(0.70, 0.30, 0.10),
]


## CADA COCHE, DE SU COLOR. El modelo trae la carroceria en un material aparte para esto. El color sale
## del NUMERO DEL PUNTO del mapa, no de un random: asi el coche rojo de la esquina es rojo en todas las
## pantallas, sin mandar nada por la red.
func _pintar() -> void:
	color = PINTURAS[absi(id * 7 + tipo.length() * 3) % PINTURAS.size()]
	pintadas = 0
	for n in _mallas_de(_cuerpo):
		var m: MeshInstance3D = n
		var malla: Mesh = m.mesh
		if malla == null:
			continue
		for i in malla.get_surface_count():
			var mat: Material = m.get_active_material(i)
			if mat == null:
				continue
			# el material de la carroceria se llama asi desde Blender; el otro ("detalle") lleva los
			# colores fijos de faros, cristales y ruedas y no se toca
			var nombre := String(mat.resource_name)
			if nombre == "" and mat is BaseMaterial3D:
				nombre = String((mat as BaseMaterial3D).resource_path.get_file())
			if not nombre.begins_with("carroceria"):
				continue
			var nuevo := StandardMaterial3D.new()
			nuevo.albedo_color = color
			nuevo.metallic = 0.35
			nuevo.roughness = 0.42
			m.set_surface_override_material(i, nuevo)
			pintadas += 1


func _mallas_de(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for h in n.get_children():
		out += _mallas_de(h)
	return out


## LUZ DE HABITACULO. Los cristales son transparentes, pero por dentro el coche esta a oscuras y desde
## fuera el cristal se lee como una chapa negra: no se ve quien va dentro. Una luz floja dentro (sin
## sombras, que no las paga esta maquina) basta para que se distinga al que va sentado. Solo se enciende
## si hay alguien.
func _montar_luz_interior(f: Dictionary) -> void:
	_luz_dentro = OmniLight3D.new()
	_luz_dentro.position = Vector3(0.0, float(f.get("suelo_cabina", 0.4)) + 0.75, 0.0)
	_luz_dentro.omni_range = maxf(2.2, float(f["tamano"][2]) * 0.6)
	_luz_dentro.light_energy = 1.7
	_luz_dentro.light_color = Color(1.0, 0.95, 0.85)
	_luz_dentro.shadow_enabled = false
	_luz_dentro.visible = false
	add_child(_luz_dentro)


## EL SONIDO DEL MOTOR. Un solo reproductor por vehiculo, en el sitio del motor, apagado mientras nadie lo
## arranca: veintisiete coches sonando a la vez en un mapa de quinientos metros no los paga esta maquina.
func _montar_motor(f: Dictionary, _aj: Dictionary) -> void:
	var ruta: String = String(MOTORES.get(tipo, ""))
	if ruta == "" or not ResourceLoader.exists(ruta):
		return
	var st: AudioStream = load(ruta)
	if st is AudioStreamWAV:
		(st as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(st as AudioStreamWAV).loop_end = (st as AudioStreamWAV).data.size() / 2
	_audio = AudioStreamPlayer3D.new()
	_audio.stream = st
	_audio.position = Vector3(float(f["motor"][0]), float(f["motor"][1]), float(f["motor"][2]))
	_audio.unit_size = 6.0
	_audio.max_distance = 90.0
	_audio.volume_db = -6.0
	_audio.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(_audio)


## Cada rueda de la ficha pasa a ser un VehicleWheel3D con su malla dentro: asi la suspension y la
## direccion mueven el dibujo sin que nadie tenga que copiar transformaciones a mano.
func _montar_ruedas(f: Dictionary, aj: Dictionary) -> void:
	for r in f.get("ruedas", []):
		var w := VehicleWheel3D.new()
		w.position = Vector3(float(r["pos"][0]), float(r["pos"][1]), float(r["pos"][2]))
		w.wheel_radius = float(r["radio"])
		# SUSPENSION PEGADA AL SUELO. Con muelles duros (42) y poca amortiguacion el coche botaba en cada
		# escalon de voxel, se despegaba del piso y vibraba. Un muelle mas blando, MUCHO mas amortiguado y
		# con mas recorrido se come los escalones del terreno de voxels en vez de rebotar en ellos.
		w.wheel_rest_length = 0.26
		w.wheel_friction_slip = float(aj["agarre"])
		w.suspension_travel = 0.28
		# EL MUELLE TIENE QUE AGUANTAR EL PESO. Con muelles muy blandos el coche se hunde hasta que el
		# chasis arrastra por el suelo y no pasa de 4 por hora (medido). Lo que quita el rebote no es
		# ablandar el muelle, es AMORTIGUARLO: por eso el muelle vuelve a ser firme y lo que sube mucho
		# es el amortiguador, sobre todo al estirarse (relaxation), que es cuando rebotaba.
		w.suspension_stiffness = 32.0 if tipo != "todoterreno" else 26.0
		w.damping_compression = 0.95
		w.damping_relaxation = 1.35
		w.suspension_max_force = mass * 12.0
		w.use_as_steering = bool(r.get("dirige", false))
		w.use_as_traction = not bool(r.get("dirige", false)) or tipo == "todoterreno"
		add_child(w)
		_ruedas.append(w)
		var malla: Node = _cuerpo.find_child(String(r["nodo"]), true, false)
		if malla is Node3D:
			var m: Node3D = malla
			m.get_parent().remove_child(m)
			w.add_child(m)
			m.position = Vector3.ZERO
			m.rotation = Vector3.ZERO


func _montar_rotores(f: Dictionary) -> void:
	for r in f.get("rotores", []):
		var n: Node = _cuerpo.find_child(String(r["nodo"]), true, false)
		if n is Node3D:
			# EL RADIO DEL DISCO sale de la propia malla: la ficha no lo trae, y sin el no se puede
			# saber que toca la helice. Se mide la caja de la pala y se coge su lado mas largo.
			var radio := 0.0
			# EL PROPIO NODO CUENTA. El rotor del .glb ES la malla, no un padre con palas dentro:
			# mirando solo a los hijos el radio salia 0 y la helice "no tocaba" nada (medido: 0,50 m,
			# que es el minimo de abajo, cuando el disco mide varios metros).
			var mallas: Array = (n as Node3D).find_children("*", "MeshInstance3D", true, false)
			if n is MeshInstance3D:
				mallas.append(n)
			for mi in mallas:
				var m: MeshInstance3D = mi
				if m.mesh == null:
					continue
				# CUANTO SE ALEJA DEL EJE, que no es lo mismo que el tamaño de la caja: una pala
				# centrada en el origen mide 10,6 m de punta a punta pero su radio es 5,3. Sumando
				# tamaño y posicion salia el doble, y el disco de corte llegaba al doble de lejos.
				var caja: AABB = m.mesh.get_aabb()
				var a: Vector3 = caja.position.abs()
				var b: Vector3 = (caja.position + caja.size).abs()
				radio = maxf(radio, maxf(maxf(a.x, b.x), maxf(maxf(a.y, b.y), maxf(a.z, b.z))))
			_rotores.append([n, String(r.get("eje", "y")), float(r.get("rpm", 5.0)), maxf(radio, 0.5)])


func _montar_faros(f: Dictionary) -> void:
	for p in f.get("faros", []):
		var l := SpotLight3D.new()
		l.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		# UN SpotLight3D DE GODOT ALUMBRA HACIA SU -Z, que es justo hacia donde mira el vehiculo: con los
		# 180 grados que habia puestos, los faros alumbraban al maletero.
		l.rotation_degrees = Vector3(-5.0, 0.0, 0.0)
		l.spot_range = 38.0
		l.spot_angle = 38.0
		l.light_energy = 3.0
		l.light_color = Color(1.0, 0.96, 0.85)
		l.shadow_enabled = false             # una sombra por faro no la paga esta maquina
		l.visible = false
		add_child(l)
		_faros.append(l)


## EL CARTEL. Sin el no sabes si estas a tiro: el jugador apretaba E a dos metros y no pasaba nada, sin
## saber si era la distancia, el coche o la tecla. Solo existe cuando hay alguien cerca.
func cartel(on: bool, texto: String = "") -> void:
	if not on:
		if _cartel != null and is_instance_valid(_cartel):
			_cartel.visible = false
		return
	if _cartel == null or not is_instance_valid(_cartel):
		_cartel = Label3D.new()
		_cartel.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_cartel.no_depth_test = false
		_cartel.fixed_size = true
		_cartel.pixel_size = 0.0012
		_cartel.outline_size = 14
		_cartel.modulate = Color(1.0, 0.95, 0.7)
		_cartel.position = Vector3(0.0, float(ficha["tamano"][1]) + 0.5, 0.0)
		add_child(_cartel)
	_cartel.text = texto
	_cartel.visible = true


# ---------------------------------------------------------------------------------------------------
# SUBIRSE Y BAJARSE
# ---------------------------------------------------------------------------------------------------

## ¿Esta este jugador al lado de una puerta? (se mide al asiento del conductor)
func al_alcance(p: Vector3) -> bool:
	return p.distance_to(global_position) < ALCANCE_ENTRAR + float(ficha["tamano"][2]) * 0.5


## CUANTOS CABEN Y DONDE. El asiento 0 es el del volante; los demas son de pasajero. Quien ocupa cada uno
## se guarda por NUMERO DE ASIENTO, no por jugador: asi el que llega tarde se sienta detras en todas las
## pantallas a la vez y dos no pueden caer en el mismo sitio.
func asientos() -> int:
	return int(ficha.get("asientos", []).size())


func asiento_pos(i: int) -> Vector3:
	var a: Array = ficha.get("asientos", [])
	if i < 0 or i >= a.size():
		return Vector3(0.0, 1.0, 0.0)
	return Vector3(float(a[i]["pos"][0]), float(a[i]["pos"][1]), float(a[i]["pos"][2]))


## El primer asiento libre, empezando por el volante (si el volante esta cogido, de copiloto para atras).
func asiento_libre() -> int:
	for i in asientos():
		# el volante de un coche que conduce otro (remoto) nunca esta libre, aunque aun no haya llegado su asiento
		if i == 0 and remoto:
			continue
		if not ocupados.has(i):
			return i
	return -1


func libre() -> bool:
	return not _roto and asiento_libre() >= 0


func entrar(pl, asiento: int = -1) -> bool:
	if _roto:
		return false
	var i: int = asiento if asiento >= 0 else asiento_libre()
	if i < 0 or ocupados.has(i):
		return false
	if i == 0 and remoto:
		return false                      # el volante lo lleva otro
	ocupados[i] = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	mi_asiento = i
	pl.br_control = self
	# EL MODO DE CAMARA ES DEL JUGADOR, NO DEL COCHE. Al bajarse se le devolvia a primera persona
	# SIEMPRE, y el que jugaba en tercera se quedaba sin verse y con la camara pegada a la cara
	# ("no veo mi personaje y la camara no me sigue"). Se apunta como estaba y se le devuelve igual.
	_tp_antes = bool(pl.get("third_person"))
	pl.set_third_person(true)
	pl.velocity = Vector3.ZERO
	_dentro_t = 0.0
	# SIN COLISION MIENTRAS VAS DENTRO. La capsula del jugador y el cuerpo del coche se pelean: Jolt los
	# separa y al asomarte por la ventanilla te escupia a dos metros del coche (medido: x = -2,11).
	# Dentro no hace falta colision: al jugador lo coloca el vehiculo cuadro a cuadro.
	_capa_jug = pl.collision_layer
	_mascara_jug = pl.collision_mask
	pl.collision_layer = 0
	pl.collision_mask = 0
	if i == 0:
		conductor = pl
		_motor_on = true
		freeze = false
		for l in _faros:
			l.visible = true
	else:
		pasajero = pl
	if gestor != null and is_instance_valid(gestor):
		gestor.aviso_conducir(self, true)
	return true


## Se baja el jugador LOCAL (vaya al volante o de pasajero).
func salir() -> void:
	if OS.is_debug_build() and "--trazasalir" in OS.get_cmdline_user_args():
		print("[veh] salir() con asiento %d, roto %s" % [mi_asiento, str(_roto)])
		print_stack()
	var pl = conductor if conductor != null else pasajero
	var era_conductor: bool = conductor != null
	if mi_asiento >= 0:
		ocupados.erase(mi_asiento)
	var asiento_salido: int = mi_asiento
	mi_asiento = -1
	conductor = null
	pasajero = null
	if era_conductor:
		_motor_on = false
		engine_force = 0.0
		brake = float(ajuste_de(tipo)["freno"])
		for l in _faros:
			l.visible = false
	if gestor != null and is_instance_valid(gestor):
		gestor.aviso_bajar(self, asiento_salido)
	if pl == null or not is_instance_valid(pl):
		return
	pl.br_control = null
	pl.collision_layer = _capa_jug
	pl.collision_mask = _mascara_jug
	var av = pl.get("avatar")
	if av != null and is_instance_valid(av) and ("sentado" in av):
		av.sentado = 0.0
	# set_third_person deja el cuerpo, el arma y la camara como toquen: se llama AL FINAL y no se toca
	# nada de eso a mano despues.
	pl.set_third_person(_tp_antes)
	# por su lado del vehiculo (los asientos de la izquierda salen por la izquierda), y si ahi hay pared,
	# por el otro
	var hacia: float = -1.0 if asiento_salido % 2 == 0 else 1.0
	var lado: Vector3 = global_transform.basis.x * (float(ficha["tamano"][0]) * 0.5 + SALTO_SALIR) * hacia
	var destino: Vector3 = global_position + lado + Vector3(0, 0.4, 0)
	if gestor != null and is_instance_valid(gestor) and gestor.tapado(destino):
		destino = global_position - lado + Vector3(0, 0.4, 0)
	pl.global_position = destino
	pl.velocity = linear_velocity * 0.4


## Lo llama player.gd mientras vas dentro (pl.br_control = este vehiculo), igual que el avion del salto.
func paso_jugador(pl, dt: float) -> void:
	if _roto:
		salir()
		return
	# NO SE PUEDE LEER LA MISMA PULSACION QUE TE HA SUBIDO. player.interact() te sienta y, en ese mismo
	# cuadro, aqui "interact" sigue recien pulsado: te bajabas al instante y parecia que E no hacia nada
	# (te quedabas plantado al lado de la puerta).
	_dentro_t += dt
	if _dentro_t > 0.3 and Input.is_action_just_pressed("interact"):
		salir()
		return
	# SENTADO DE VERDAD. El jugador va donde dice el asiento de la ficha y el avatar dobla caderas y
	# rodillas (avatar_animator.sentado): ni de pie dentro del coche, ni la cabeza atravesando el techo.
	var asiento: int = maxi(0, mi_asiento)
	# EL JUGADOR SE COLOCA POR LOS PIES, no por el culo: su posicion es la base de la capsula y la
	# cabeza le queda 1,55 m mas arriba. Sentado en el asiento a pelo, la cabeza salia por el techo
	# (medido: 2,66 m con el techo a 1,50). Se baja el nodo lo que mide una persona sentada, y asi la
	# coronilla cae a unos 80 cm del asiento, que es lo que mide alguien sentado de verdad.
	# LOS PIES, EN EL SUELO DE LA CABINA (lo dice la ficha). Bajando una altura fija, en el coche los pies
	# quedaban POR DEBAJO del piso y desde dentro se veian las piernas atravesando la chapa.
	var suelo_cab: float = float(ficha.get("suelo_cabina", asiento_pos(asiento).y - ALTURA_SENTADO))
	var sitio: Vector3 = Vector3(asiento_pos(asiento).x, suelo_cab, asiento_pos(asiento).z)
	pl.global_position = to_global(sitio)
	pl.velocity = Vector3.ZERO
	_postura(pl, asiento)
	pl._update_third_person_cam(dt)


## DENTRO DE UN VEHICULO NO SE DISPARA. Se probo lo de asomarse por la ventanilla y no compensaba: el
## muñeco quedaba medio subido a la puerta, mas de pie al lado del coche que asomado, y un pasajero
## disparando desde un coche en marcha es ademas lo mas dificil de cuadrar en red. Si vas dentro, vas
## dentro; para tirar, te bajas. La ficha sigue trayendo `ventanillas` por si algun dia se retoma.
func deja_disparar() -> bool:
	return false


## La postura del muñeco: sentado, con las manos al volante si conduces. La ven todos: es el mismo
## avatar que ven los demas jugadores.
func _postura(pl, asiento: int) -> void:
	var av = pl.get("avatar")
	if av == null or not is_instance_valid(av) or not ("sentado" in av):
		return
	av.sentado = 1.0
	av.sentado_volante = asiento == 0
	# EN PRIMERA PERSONA, SIN BRAZOS: los de primera persona cuelgan de la camara, no estan sentados, y
	# quedaban flotando delante de la cara. El cuerpo de tercera persona lo maneja set_third_person.
	var wp = pl.get("weapon_pivot")
	if wp is Node3D and not bool(pl.get("third_person")):
		(wp as Node3D).visible = false


## SENTAR A UN BOT. Un bot no tiene `br_control`: se le lleva la posicion desde aqui, igual que al
## jugador, y se le pone la misma pose de sentado (su avatar es el mismo). Lo usan la prueba y, cuando
## los bots aprendan a conducir, ellos.
func sentar_bot(e: Node3D, asiento: int) -> void:
	if e == null or not is_instance_valid(e):
		return
	ocupados[asiento] = -1
	_bots[asiento] = e


func _bots_a_su_sitio() -> void:
	for asiento in _bots.keys():
		var e = _bots[asiento]
		if not is_instance_valid(e):
			_bots.erase(asiento)
			ocupados.erase(asiento)
			continue
		var suelo_cab: float = float(ficha.get("suelo_cabina", 0.3))
		var a: Vector3 = asiento_pos(asiento)
		e.global_position = to_global(Vector3(a.x, suelo_cab, a.z))
		e.global_rotation.y = global_rotation.y
		var av = e.get("avatar")
		if av != null and is_instance_valid(av) and ("sentado" in av):
			av.sentado = 1.0
			av.sentado_volante = asiento == 0


## LO QUE PIDE QUIEN CONDUCE. En PC, el teclado; en el movil, el joystick y el pad que sale al
## subirse (mobile_controls.gd).
##
## EL MOVIL NO PODIA NI FRENAR NI SUBIR. Aqui solo se miraba el TECLADO, asi que en un telefono el
## freno del coche y el colectivo del helicoptero no existian: se podia despegar (el joystick
## inclina) pero no subir, ni bajar, ni frenar. De ahi el "en moviles no se como hacerlo".
func _entrada() -> Dictionary:
	var pl = conductor
	var mov := Vector2.ZERO
	var arriba: bool = Input.is_action_pressed("jump")
	var freno: bool = Input.is_action_pressed("crouch")
	if pl != null and is_instance_valid(pl):
		mov = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var tm = pl.get("touch_move")
		if tm is Vector2:
			mov += tm
		var tv = pl.get("touch_vehiculo")
		if tv is Vector3:
			mov += Vector2(tv.x, tv.y)
			arriba = arriba or tv.z > 0.5
			freno = freno or tv.z < -0.5
	if mov.length() > 1.0:
		mov = mov.normalized()
	return {"mov": mov, "freno": freno, "arriba": arriba}


# ---------------------------------------------------------------------------------------------------
# CONDUCCION
# ---------------------------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	_girar_rotores(dt)
	_sonar(dt)
	if not _bots.is_empty():
		_bots_a_su_sitio()
	if _luz_dentro != null and is_instance_valid(_luz_dentro):
		_luz_dentro.visible = not ocupados.is_empty()
	if remoto or _roto:
		return
	if conductor == null or not is_instance_valid(conductor):
		# sin nadie al volante no se conduce, pero el vehiculo sigue siendo un cuerpo normal: de pasajero
		# se puede ir en un coche que no lleva nadie (parado, claro)
		engine_force = 0.0
		steering = 0.0
		return
	var aj: Dictionary = ajuste_de(tipo)
	var e: Dictionary = _entrada()
	if tipo == "helicoptero":
		_volar(e, dt, aj)
	else:
		_rodar(e, dt, aj)
	_atropellar()
	_embestir()
	_golpes(dt)
	_agua_y_fondo()
	_t_red += dt
	if _t_red >= 0.05:
		_t_red = 0.0
		if gestor != null and is_instance_valid(gestor):
			gestor.mandar_postura(self)


func _rodar(e: Dictionary, dt: float, aj: Dictionary) -> void:
	var mov: Vector2 = e["mov"]
	# LOS SIGNOS. `get_vector` da y = atras - adelante (W es y = -1) y x = derecha - izquierda. El motor de
	# Godot empuja hacia -Z con fuerza POSITIVA y la direccion gira a la izquierda con angulo POSITIVO, o
	# sea que W es -y y la direccion es -x... y estaba puesto al reves de los dos: con W se iba marcha
	# atras y con A el coche se iba a la derecha.
	var acel: float = -mov.y                     # W = +1 = quiero ir hacia mi morro
	var vel_adelante: float = linear_velocity.dot(-global_transform.basis.z)
	var tope: float = float(aj["tope"])
	# la direccion se cierra con la velocidad: a 100 no se gira como en un aparcamiento
	var cierre: float = clampf(1.0 - absf(vel_adelante) / (tope * 1.3), 0.35, 1.0)
	steering = lerpf(steering, deg_to_rad(float(aj["giro"])) * -mov.x * cierre, 8.0 * dt)
	if e["freno"] or (acel < -0.1 and vel_adelante > 1.0):
		engine_force = 0.0
		brake = float(aj["freno"])
	else:
		brake = 0.0 if absf(acel) > 0.05 else float(aj["freno"]) * 0.12
		# EN GODOT, FUERZA NEGATIVA EMPUJA HACIA -Z, que es hacia donde mira el vehiculo: por eso con W
		# se iba marcha atras. El signo va aqui, no en la entrada.
		var fuerza: float = -float(aj["motor"]) * acel
		if acel < 0.0:
			fuerza *= MARCHA_ATRAS
		if vel_adelante > tope or (vel_adelante < -tope * TOPE_ATRAS and acel < 0.0):
			fuerza = 0.0
		engine_force = fuerza
	# EL TOPE DE VERDAD. Cortar el gas no basta: cuesta abajo, y con el par que endereza la moto, se
	# llegaba a 238 por hora. Por encima del tope se frena la velocidad, no solo el motor.
	var v: Vector3 = linear_velocity
	var plano := Vector2(v.x, v.z)
	if plano.length() > tope:
		plano = plano.normalized() * lerpf(plano.length(), tope, minf(1.0, 6.0 * dt))
		linear_velocity = Vector3(plano.x, v.y, plano.y)
	# LA MOTO SE CAE SOLA con dos ruedas: se endereza con un par, mas fuerte cuanto mas inclinada. Es lo
	# que hace cualquier juego con motos; una moto que se acuesta en cada curva no se puede jugar.
	if tipo == "moto":
		var arriba: Vector3 = global_transform.basis.y
		var err: Vector3 = arriba.cross(Vector3.UP)
		apply_torque(err * mass * 7.0 - angular_velocity * mass * 0.9)
	# BOCA ARRIBA DEL REVES: si te quedas con las ruedas al aire dos segundos, el coche se da la vuelta
	# solo (en un battle royale quedarse tumbado en un descampado es perder la partida por nada).
	if global_transform.basis.y.dot(Vector3.UP) < 0.1:
		_vuelco += dt
		if _vuelco > 2.0:
			_vuelco = 0.0
			var t := global_transform
			t.basis = Basis(Vector3.UP, t.basis.get_euler().y)
			t.origin += Vector3(0, 1.0, 0)
			global_transform = t
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
	else:
		_vuelco = 0.0


func _volar(e: Dictionary, dt: float, aj: Dictionary) -> void:
	var mov: Vector2 = e["mov"]
	var quiere: float = (1.0 if e["arriba"] else 0.0) - (1.0 if e["freno"] else 0.0)
	_colectivo = clampf(_colectivo + quiere * dt * 1.6 - (0.0 if absf(quiere) > 0.01 else _colectivo * dt * 0.6),
		HELI_COLECTIVO_MIN, 1.0)
	# el rumbo lo lleva la mirada del piloto: se gira hacia donde mira, como en cualquier juego de heli
	if conductor != null and is_instance_valid(conductor):
		var look = conductor.get("look")
		if look is Vector2:
			var quiero: float = float(look.x)
			var ahora: float = global_rotation.y
			var d: float = wrapf(quiero - ahora, -PI, PI)
			angular_velocity.y = clampf(d * 2.2, -HELI_GIRO, HELI_GIRO)
	var b: Basis = global_transform.basis
	# inclinacion hacia donde se empuja, y empuje en esa direccion
	var inc := Vector3(mov.y, 0.0, 0.0) * HELI_INCLINA
	var roll := -mov.x * HELI_INCLINA
	var obj := Basis(Vector3.UP, global_rotation.y) * Basis.from_euler(Vector3(inc.x, 0.0, roll))
	var err: Quaternion = (obj.get_rotation_quaternion() * b.get_rotation_quaternion().inverse()).normalized()
	var eje: Vector3 = err.get_axis()
	var ang: float = err.get_angle()
	if ang > PI:
		ang -= TAU
	if eje.length() > 0.01:
		var par: Vector3 = eje.normalized() * ang * mass * HELI_PAR
		par.y = 0.0                              # la guiñada la lleva la mirada, no esto
		apply_torque(par - Vector3(angular_velocity.x, 0.0, angular_velocity.z) * mass * 1.1)
	var sube: float = (9.8 + HELI_SUBIDA * _colectivo) * mass
	apply_central_force(b.y * sube - Vector3.UP * 9.8 * mass * 0.0)
	apply_central_force(b * Vector3(-mov.x, 0.0, mov.y) * HELI_EMPUJE * mass)
	if linear_velocity.length() > float(aj["tope"]):
		linear_velocity = linear_velocity.normalized() * float(aj["tope"])


## AL AGUA Y AL VACIO. Un coche que se mete en el mar se cala y te deja fuera (nadando, que es lo que hace
## cualquier battle royale); si alguien se sale por el borde del mundo, el vehiculo revienta antes de
## llevarse al jugador a menos cien metros — medido: una moto a 117 por hora acabo en y = -129.
func _agua_y_fondo() -> void:
	if global_position.y < 0.4:
		reventar()
		return
	var m: Node = gestor.main if gestor != null and is_instance_valid(gestor) else null
	if m == null:
		return
	var ag = m.get("agua")
	if ag == null or not is_instance_valid(ag) or not ag.has_method("profundidad"):
		return
	if ag.profundidad(global_position + Vector3(0, 0.3, 0)) > 0.9 and tipo != "helicoptero":
		engine_force = 0.0
		brake = 40.0
		if conductor != null and is_instance_valid(conductor):
			if m.get("hud"):
				m.hud.flash_message("EL MOTOR SE HA CALADO")
			salir()


## El tono y el volumen siguen a las vueltas: parado ralenti, y cuanto mas corre mas agudo. Es lo que hace
## que un coche suene a coche sin tener veinte muestras grabadas.
func _sonar(dt: float) -> void:
	if _audio == null:
		return
	var encendido: bool = _motor_on or remoto or (tipo == "helicoptero" and _colectivo > 0.02)
	if not encendido or _roto:
		if _audio.playing:
			_audio.stop()
		return
	if not _audio.playing:
		_audio.play()
	var v: float = linear_velocity.length()
	var aj: Dictionary = ajuste_de(tipo)
	var k: float = clampf(v / maxf(1.0, float(aj["tope"])), 0.0, 1.35)
	if tipo == "helicoptero":
		k = clampf(_colectivo, 0.0, 1.0)
	_audio.pitch_scale = lerpf(_audio.pitch_scale, lerpf(0.75, 1.75, k), minf(1.0, 6.0 * dt))
	_audio.volume_db = lerpf(_audio.volume_db, lerpf(-12.0, -1.0, k), minf(1.0, 4.0 * dt))


## ¿Esta el helicoptero posado? Volando, los tirones del control no son golpes.
func is_on_floor_heli() -> bool:
	if world_de() == null:
		return false
	var r: Dictionary = world_de().raycast(global_position + Vector3(0, 0.3, 0), Vector3.DOWN, 1.2)
	return bool(r.get("hit", false))


func _girar_rotores(dt: float) -> void:
	if _rotores.is_empty():
		return
	# EL ROTOR GIRA CON EL MOTOR. El colectivo es el paso de las palas -cuanto levantan-, no a que
	# velocidad giran; y ademas ahora puede ser negativo, que hacia girar las palas al reves.
	var v: float = (0.35 + maxf(_colectivo, 0.0)) if (_motor_on or remoto) else 0.0
	if v <= 0.01:
		return
	for r in _rotores:
		var n: Node3D = r[0]
		if not is_instance_valid(n):
			continue
		var a: float = float(r[2]) * v * TAU * dt
		match String(r[1]):
			"x": n.rotate_x(a)
			"z": n.rotate_z(a)
			_: n.rotate_y(a)
	# Y CORTA SIEMPRE QUE GIRE. Estaba atado a `v >= 0,45`, y volando llano v vale 0,35: las palas
	# atravesaban las cosas salvo que estuvieras subiendo. Medido: 0 mordiscos contra un talud.
	if (_motor_on or remoto) and not remoto:
		_rotores_cortan(dt)


## LO QUE TOCA LA HELICE, SE PARTE. El disco se mira por puntos repartidos por el borde que ademas van
## girando, asi que entre cuadro y cuadro barren la circunferencia entera.
##
## Solo lo hace la maquina que manda el helicoptero (`remoto` es falso): el tallado ya viaja replicado
## y, si lo hicieran todas, el mismo boquete se abriria varias veces.
func _rotores_cortan(dt: float) -> void:
	var w = world_de()
	if w == null or _roto:
		return
	_rotor_t -= dt
	if _rotor_t > 0.0:
		return
	for r in _rotores:
		var n: Node3D = r[0]
		if not is_instance_valid(n):
			continue
		var radio: float = float(r[3])
		var centro: Vector3 = n.global_position
		var base: Basis = n.global_transform.basis
		# el eje de giro y los dos que forman el plano del disco
		var eje: Vector3 = base.y
		var u: Vector3 = base.x
		var v2: Vector3 = base.z
		match String(r[1]):
			"x":
				eje = base.x
				u = base.y
				v2 = base.z
			"z":
				eje = base.z
				u = base.x
				v2 = base.y
		# 1) ¿HAY ALGUIEN EN EL DISCO? Se mira antes que el mundo: una persona no frena la helice.
		for quien in _gente_cerca():
			var d: Vector3 = quien.global_position + Vector3(0, 0.9, 0) - centro
			if absf(d.dot(eje)) < 0.45 and d.length() < radio + 0.35 and float(quien.health) > 0.0:
				if quien.has_method("take_damage"):
					quien.take_damage(ROTOR_DANO_PERSONA, (quien.global_position - centro).normalized())
				cortados += 1
		# 2) ¿Y MUNDO? RAYOS DEL EJE HACIA FUERA, no cubitos en el borde. Seis cubos de 20 cm sobre una
		# circunferencia de 33 metros dejan cinco metros de hueco entre uno y otro: las palas pasaban
		# por encima de un muro sin tocarlo (medido: 0 mordiscos volando contra un talud). Un rayo
		# cubre TODO el radio, y seis rayos que ademas giran barren el disco entero.
		for i in ROTOR_SONDAS:
			var ang: float = TAU * (float(i) / float(ROTOR_SONDAS)) + _rotor_fase
			var hacia: Vector3 = (u * cos(ang) + v2 * sin(ang)).normalized()
			var son: Dictionary = w.raycast_con_piezas(centro + hacia * 0.55, hacia, radio - 0.55) \
				if w.has_method("raycast_con_piezas") else w.raycast(centro + hacia * 0.55, hacia, radio - 0.55)
			if not son.get("hit", false):
				continue
			var p: Vector3 = son["position"]
			Net.net_carve_beam(w, p - hacia * 0.15, hacia, 0.60, 0.46, ROTOR_POT, false)
			Audio.piece_break(1, p, 90)
			danar(ROTOR_DANO_PROPIO)
			cortados += 1
			break                      # un mordisco por cuadro y rotor: ni se nota y no satura la red
	_rotor_fase = fmod(_rotor_fase + 1.1, TAU)
	_rotor_t = ROTOR_CADENCIA


## Los cuerpos con vida que hay a mano: bots, el jugador de esta maquina y los jugadores remotos.
func _gente_cerca() -> Array:
	var out: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		# LOS QUE VAN DENTRO NO SE CORTAN CON SU PROPIO ROTOR. Van sentados a la altura del disco, asi
		# que sin esto un pasajero moria en cuanto se arrancaba el helicoptero.
		# (`_bots` es asiento -> bot, asi que lo que hay que mirar son sus VALORES)
		if is_instance_valid(e) and ("health" in e) and not (e in _bots.values()):
			out.append(e)
	var mn = gestor.main if gestor != null and is_instance_valid(gestor) else null
	if mn != null and ("player" in mn) and is_instance_valid(mn.player) and ("health" in mn.player):
		# quien va dentro no se corta con su propio rotor
		if mn.player != conductor and mn.player != pasajero:
			out.append(mn.player)
	if Net.remotes != null:
		for k in Net.remotes.keys():
			# y tampoco los de otras maquinas que vayan en ESTE vehiculo (`ocupados` es asiento -> peer)
			if int(k) in ocupados.values():
				continue
			var rp = Net.remotes[k]
			if is_instance_valid(rp) and ("health" in rp):
				out.append(rp)
	return out


## EMBESTIR: el morro contra el mundo. Se mira con un rayo lo que hay justo delante; si se llega tocando a
## suficiente velocidad, se abre un boquete del tamaño que da la velocidad y el coche se frena y se abolla.
## A 20 por hora se rompe un seto o una valla de madera; a 80, un muro.
##
## LO ABRE QUIEN CONDUCE Y VIAJA REPLICADO (`Net.net_explode`): con `world.explode` a secas el boquete solo
## saldria en esta maquina y el mapa de los demas se quedaria con la pared entera.
func _embestir() -> void:
	# EL HELICOPTERO NO EMBISTE. Su rayo de morro pillaba el suelo al inclinarse y se frenaba a la mitad
	# EN CADA CUADRO: con el colectivo a tope subia 5,8 m en ocho segundos en vez de 160, y encima se
	# abollaba solo. Un helicoptero que choca no abre un boquete: se cae.
	if world_de() == null or tipo == "helicoptero":
		return
	var v: float = linear_velocity.length()
	if v < EMBESTIR_MIN:
		return
	var fwd: Vector3 = -global_transform.basis.z
	if linear_velocity.dot(fwd) < 0.0:
		fwd = -fwd                                  # marcha atras: se embiste con el maletero
	var largo: float = float(ficha["tamano"][2]) * 0.5
	var desde: Vector3 = global_position + Vector3(0, float(ficha["tamano"][1]) * 0.35, 0) + fwd * (largo * 0.6)
	var alcance: float = largo * 0.5 + v * 0.06
	var r: Dictionary = world_de().raycast(desde, fwd, alcance)
	if not r.hit:
		return
	var k: float = clampf((v - EMBESTIR_MIN) / (EMBESTIR_TODO - EMBESTIR_MIN), 0.0, 1.0)
	var ancho: float = float(ficha["tamano"][0])
	var radio: float = lerpf(EMBESTIR_R_MIN, EMBESTIR_R_MAX, k) * ancho * 0.85
	var potencia: int = int(lerpf(float(EMBESTIR_POT_MIN), float(EMBESTIR_POT_MAX), k))
	# UN GOLPE, NO UNA BOMBA. Con `explode` salia fuego, humo y el estruendo de una granada cada vez que
	# rozabas una pared ("cuando choco se escucha el ruido de una explosion"). Se talla un boquete y suena
	# a material roto, igual que el golpe de manos del jefe del PvE. Va replicado: si no, el agujero solo
	# saldria en esta maquina y los demas seguirian viendo la pared entera.
	var punto: Vector3 = r.position - fwd * (radio * 0.3)
	Net.net_carve_beam(world_de(), punto, fwd, radio * 1.1, radio, potencia, false)
	Audio.piece_break(int(r.material), r.position, int(radio * 400.0))
	Audio.bf3d("destru/coche", r.position, 0.0, 80.0, Audio.PRI_HIGH)
	# el golpe te frena y te abolla: cuanto mas gordo el boquete, mas caro sale
	linear_velocity *= EMBESTIR_FRENO
	danar(radio * EMBESTIR_DANO)


func world_de():
	if gestor != null and is_instance_valid(gestor):
		return gestor.world
	return null


## ATROPELLAR: a partir de cierta velocidad, lo que se cruce por delante se lleva un golpe. Los bots y los
## jugadores tienen su propio cuerpo, asi que basta con mirar quien esta pegado al morro.
func _atropellar() -> void:
	var v: float = linear_velocity.length()
	if v < ATROPELLO:
		return
	var fwd: Vector3 = global_transform.basis.z * (-1.0 if linear_velocity.dot(-global_transform.basis.z) >= 0.0 else 1.0)
	var morro: Vector3 = global_position + fwd * float(ficha["tamano"][2]) * 0.5
	var dano: float = (v - ATROPELLO) * ATROPELLO_DANO
	var ancho: float = float(ficha["tamano"][0]) * 0.5 + 0.5
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not ("health" in e):
			continue
		if e.global_position.distance_to(morro) < ancho and float(e.health) > 0.0:
			if e.has_method("take_damage"):
				e.take_damage(dano, linear_velocity.normalized())
			_atropellados += 1


# ---------------------------------------------------------------------------------------------------
# ROMPERSE
# ---------------------------------------------------------------------------------------------------

func _on_choque(_c: Node) -> void:
	pass          # el daño de los golpes se mide por el frenazo (ver _golpes), que capta tambien el mundo


## EL DESGASTE DE LOS GOLPES. `body_entered` solo avisa de choques contra OTROS CUERPOS, y el mundo es de
## voxels: contra una pared no saltaba nunca y el coche parecia indestructible. Aqui se mira el FRENAZO:
## cuanta velocidad se ha perdido de un cuadro al siguiente. Un bordillo quita un pellizco; empotrarse a
## ochenta se lleva media chapa, y a cero el coche revienta.
const FRENAZO_MIN := 2.2        ## m/s perdidos en un cuadro por debajo de los cuales es conduccion normal
const FRENAZO_DANO := 26.0      ## vida por cada m/s perdido de mas
func _golpes(dt: float) -> void:
	if tipo == "helicoptero" and not is_on_floor_heli():
		_v_antes = linear_velocity
		return
	var v: Vector3 = linear_velocity
	if _v_antes.length() > 1.0 and dt > 0.0:
		var perdido: float = (_v_antes - v).length()
		# una frenada normal son ~8 m/s2: en un cuadro (1/60 s) no llega a 0,15 m/s. Todo lo que pase de
		# FRENAZO_MIN en un solo cuadro es un golpe, no el freno.
		if perdido > FRENAZO_MIN:
			var d: float = (perdido - FRENAZO_MIN) * FRENAZO_DANO
			danar(d)
			if d > 25.0:
				Audio.piece_break(1, global_position, int(d * 6.0))
				Audio.bf3d("destru/coche", global_position, 2.0, 80.0, Audio.PRI_HIGH)
	_v_antes = v


## UN BALAZO EN LA CHAPA. Lo llama quien dispara (player.gd, enemy.gd) cuando su rayo pega en este
## vehiculo. Devuelve true si ha hecho daño, para que quien dispara sepa que ha acertado a algo.
func danar_bala(dano: float, punto: Vector3, _dir: Vector3) -> bool:
	if _roto or dano <= 0.0:
		return false
	balazos += 1
	var local: Vector3 = global_transform.affine_inverse() * punto
	var alto: float = float(ficha["tamano"][1])
	var largo: float = float(ficha["tamano"][2])
	var k := BALA_DANO
	if local.y > alto * 0.28:
		k = BALA_CRISTAL
	elif local.z < -largo * 0.22:
		k = BALA_MOTOR
	danar(dano * k)
	return true


func danar(d: float) -> void:
	if _roto or d <= 0.0:
		return
	vida -= d
	if vida <= vida_max * 0.35:
		_humo = 1.0
	if vida <= 0.0:
		reventar()


func reventar() -> void:
	if _roto:
		return
	_roto = true
	vida = 0.0
	# BF: la ignicion y el coche ardiendo un buen rato (se apaga solo a los 25 s)
	Audio.bf3d("destru/fuego_prende", global_position, 2.0, 80.0, Audio.PRI_HIGH)
	Audio.bucle3d(self, "fuego", "destru/fuego_restos", true, -2.0, 60.0)
	Audio.bucle3d(self, "motor", "destru/motor_chisporrotea", true, -8.0, 30.0)
	get_tree().create_timer(25.0).timeout.connect(func():
		Audio.bucle3d(self, "fuego", "", false)
		Audio.bucle3d(self, "motor", "", false))
	var dentro = conductor if conductor != null else pasajero
	if dentro != null and is_instance_valid(dentro):
		salir()
		if dentro.has_method("take_damage"):
			dentro.take_damage(70.0, Vector3.UP)
	if gestor != null and is_instance_valid(gestor):
		gestor.reventado(self)
