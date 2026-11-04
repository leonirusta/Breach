extends Node
## Sonido del juego con la biblioteca de Teardown (godot/sounds/td, importada con
## tools/import_teardown_sounds.py).
##
## * Biblioteca: cada evento elige al azar una variante de la carpeta correspondiente
##   (masonry/hit-s*, metal/break-l*, wood/step*...). Las clases de material de vxcore se traducen a las
##   carpetas de Teardown por dureza y banderas.
## * Voces: pool de reproductores 3D con PRIORIDAD (explosión > disparo > rotura > impacto/escombro).
##   Un sonido nuevo coge una voz libre o roba la de menor prioridad y más antigua; nunca corta a uno más
##   importante. Los impactos y escombros tienen presupuesto por frame; explosiones y disparos no.
##   (Antes un pool circular y un presupuesto global hacían que la explosión del cohete se perdiera entre
##   las decenas de roturas que genera en el mismo frame.)
## * Distancia: atenuación por inverso del cuadrado + filtro paso-bajo progresivo (lo lejano suena
##   apagado) + retardo por velocidad del sonido (340 m/s) a partir de 40 m.
## * Espacio: un bus "World" con reverberación cuya mezcla se ajusta cada 0,2 s midiendo lo cerrado que
##   está el lugar del oyente (rayos de línea de visión hacia arriba y alrededor): interiores con eco,
##   exteriores secos.

const ROOT := "res://sounds/td/"
const POOL_3D := 32
const POOL_2D := 8
const SPEED_OF_SOUND := 340.0

const PRI_LOW := 0      # impactos de bala, escombros pequeños
const PRI_MID := 1      # roturas, aterrizajes de piezas, pasos
const PRI_HIGH := 2     # disparos
const PRI_TOP := 3      # explosiones

var _lib: Dictionary = {}          # "carpeta/prefijo" -> Array[AudioStream]
var _pool3d: Array[AudioStreamPlayer3D] = []
var _pri3d: Array[int] = []
var _t3d: Array[float] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _pri2d: Array[int] = []
var _t2d: Array[float] = []
var _ambience: AudioStreamPlayer
var _rain: AudioStreamPlayer
var _class_cache: Dictionary = {}  # id de material -> carpeta
var world: Node = null
var master_db := 0.0
var _budget: Array[int] = [0, 0, 0, 0]   # sonidos lanzados este frame por prioridad
const BUDGET := [8, 8, 99, 99]
var _pending: Array = []            # [t_play, key, pos, db, pitch_var, max_dist, pri]
var enabled := true
var played: Dictionary = {}         # diagnóstico: clave -> veces reproducida (-1 si no hay archivos)

# reverberación por espacio
var _bus_idx := -1
var _reverb: AudioEffectReverb
var enclosure := 0.0                # 0 = exterior abierto, 1 = interior cerrado (medido)
var _probe_t := 0.0


func set_master_volume(v: float) -> void:
	master_db = linear_to_db(clampf(v, 0.0001, 1.0))
	if _ambience:
		_ambience.volume_db = -14.0 + master_db
	if _rain:
		_rain.volume_db = LLUVIA_DB + master_db


func _ready() -> void:
	_setup_bus()
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 60.0
		p.unit_size = 4.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		p.max_polyphony = 1
		# lo lejano suena apagado: paso-bajo progresivo con la distancia (Teardown hace lo mismo)
		p.attenuation_filter_cutoff_hz = 2200.0
		p.attenuation_filter_db = -22.0
		p.bus = "World"
		add_child(p)
		_pool3d.append(p)
		_pri3d.append(-1)
		_t3d.append(0.0)
	for i in POOL_2D:
		var p2 := AudioStreamPlayer.new()
		p2.bus = "World"
		add_child(p2)
		_pool2d.append(p2)
		_pri2d.append(-1)
		_t2d.append(0.0)
	_ambience = AudioStreamPlayer.new()
	_ambience.volume_db = -14.0
	add_child(_ambience)
	_rain = AudioStreamPlayer.new()
	_rain.volume_db = -8.0
	add_child(_rain)
	# todos los botones del juego suenan (capa de Battlefield, ver _enganchar_botones)
	get_tree().node_added.connect(_enganchar_botones)


## Bus "World" (Master <- World) con reverberación; la mezcla la fija la medida de espacio cerrado.
func _setup_bus() -> void:
	_setup_deafness()
	_bus_idx = AudioServer.get_bus_index("World")
	if _bus_idx < 0:
		_bus_idx = AudioServer.bus_count
		AudioServer.add_bus(_bus_idx)
		AudioServer.set_bus_name(_bus_idx, "World")
		AudioServer.set_bus_send(_bus_idx, "Master")
	_reverb = AudioEffectReverb.new()
	_reverb.room_size = 0.4
	_reverb.damping = 0.6
	_reverb.spread = 0.8
	_reverb.predelay_msec = 40.0
	_reverb.wet = 0.06
	_reverb.dry = 1.0
	AudioServer.add_bus_effect(_bus_idx, _reverb)
	# UN LIMITADOR AL FINAL DEL BUS. Esto es lo que faltaba de verdad: con una metralleta a quince
	# tiros por segundo hay diez o doce disparos sonando a la vez, cada uno con su cola de
	# reverberacion, y todos se SUMAN. Al pasarse de 0 dB la mezcla recorta y eso es exactamente el
	# ruido sucio que se oye: no es que falten voces, es que la suma no cabe.
	#
	# El limitador la aplasta antes de que recorte. Es la red de seguridad que hace que ninguna
	# situacion -diez jugadores disparando en LAN, una explosion sobre una rafaga- pueda romper el
	# sonido, en vez de ir racionando efectos uno a uno adivinando el peor caso.
	var lim: AudioEffect = null
	if ClassDB.class_exists("AudioEffectHardLimiter"):
		lim = ClassDB.instantiate("AudioEffectHardLimiter")
	elif ClassDB.class_exists("AudioEffectLimiter"):
		lim = ClassDB.instantiate("AudioEffectLimiter")
	if lim:
		if "ceiling_db" in lim:
			lim.ceiling_db = -0.5
		AudioServer.add_bus_effect(_bus_idx, lim)


func _process(dt: float) -> void:
	var _pt0 := Time.get_ticks_usec()
	_process_inner(dt)
	Prof.add("audio", Time.get_ticks_usec() - _pt0)

func _process_inner(dt: float) -> void:
	# (desglose para --perfmapa, 2026-10-10: claves au.t.*)
	var _ts := Time.get_ticks_usec()
	_recoger_llegadas()
	Prof.add("au.t.llegadas", Time.get_ticks_usec() - _ts); _ts = Time.get_ticks_usec()
	_diferidos_tick()
	Prof.add("au.t.diferidos", Time.get_ticks_usec() - _ts); _ts = Time.get_ticks_usec()
	_update_deafness(dt)
	Prof.add("au.t.sordera", Time.get_ticks_usec() - _ts); _ts = Time.get_ticks_usec()
	_guerra_tick(dt)
	Prof.add("au.t.guerra", Time.get_ticks_usec() - _ts); _ts = Time.get_ticks_usec()
	_amb_tick(dt)
	Prof.add("au.t.ambiente", Time.get_ticks_usec() - _ts); _ts = Time.get_ticks_usec()
	_colas_tick()
	Prof.add("au.t.colas", Time.get_ticks_usec() - _ts); _ts = Time.get_ticks_usec()
	_ronda_tick(dt)
	_budget = [0, 0, 0, 0]
	var now := Time.get_ticks_msec() * 0.001
	# sonidos retardados por la velocidad del sonido
	if not _pending.is_empty():
		var keep: Array = []
		for pnd in _pending:
			if now >= pnd[0]:
				_play3d_now(pnd[1], pnd[2], pnd[3], pnd[4], pnd[5], pnd[6], pnd[7] if pnd.size() > 7 else 1.0)
			else:
				keep.append(pnd)
		_pending = keep
	Prof.add("au.t.pendientes", Time.get_ticks_usec() - _ts); _ts = Time.get_ticks_usec()
	_probe_t -= dt
	if _probe_t <= 0.0:
		_probe_t = 0.2
		_probe_enclosure()
	Prof.add("au.t.sala", Time.get_ticks_usec() - _ts)


## Mide lo cerrado que está el sitio del oyente: rayos de línea de visión de 14 m hacia arriba, en
## diagonal y en horizontal. Cuantos más chocan, más reverberación (interior) y sala más grande.
func _probe_enclosure() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or world == null or not world.has_method("has_line_of_sight"):
		return
	var o: Vector3 = cam.global_position
	var blocked := 0
	var total := 0
	const R := 14.0
	var dirs: Array[Vector3] = [Vector3.UP]
	for k in 8:
		var a := k * TAU / 8.0
		dirs.append(Vector3(cos(a), 0.0, sin(a)))
		dirs.append(Vector3(cos(a) * 0.7, 0.7, sin(a) * 0.7))
	for d in dirs:
		total += 1
		if not world.has_line_of_sight(o, o + d * R):
			blocked += 1
	var target := float(blocked) / float(total)
	# el techo pesa: a cielo abierto no hay de donde rebote, por muchas paredes que tengas al lado.
	# Antes esto lo dejaba en un 35 % y era demasiado castigo: en un patio o bajo un porche, donde
	# el eco SE OYE, la medida caia tanto que no quedaba nada.
	if world.has_line_of_sight(o, o + Vector3.UP * R):
		target *= 0.5
	enclosure = lerpf(enclosure, target, 0.5)
	if _reverb:
		# LA MEZCLA, MUCHO MAS ARRIBA. Estaba en 0,42 de humedo contra 1,0 de seco: la cola existia
		# pero se la comia el sonido directo y no se oia. Un disparo en un pasillo de hormigon es de
		# los sonidos mas reverberantes que hay; a 0,75 por fin se nota que estas dentro.
		# 0,55 y no 0,75: la cola es energia, y doce disparos con cola al 75 % de humedo llenaban el
		# bus ellos solos. A 0,55 se sigue oyendo perfectamente que estas dentro y queda margen.
		_reverb.wet = lerpf(0.04, 0.55, enclosure)
		_reverb.room_size = lerpf(0.3, 0.95, enclosure)
		_reverb.damping = lerpf(0.7, 0.22, enclosure)   # menos amortiguado = cola mas larga
		# el retardo de la primera reflexion crece con la sala: en un sitio grande el rebote tarda
		_reverb.predelay_msec = lerpf(18.0, 55.0, enclosure)


# ---------------------------------------------------------------------------
# Biblioteca
# ---------------------------------------------------------------------------
func _variants(key: String) -> Array:
	if _lib.has(key):
		return _lib[key]
	# EN PARTIDA NO SE CARGA NADA EN EL HILO PRINCIPAL (2026-09-26, medido con --medirfps: 78 claves cargadas en
	# pleno juego, de 10 a 112 ms cada una -la primera voz de cada criatura, el desfibrilador, la sirena...-, y
	# eran TODOS los bajones del modo zombi). Se encarga a un hilo y suena la proxima vez que se pida; lo normal
	# es que ya este, porque los bancos del modo se cargan al empezar (precalentar_bancos).
	if _en_partida:
		_pedir_en_hilo(key)
		return []
	var _tv := Time.get_ticks_usec()
	var _out := _variants_cargar(key)
	Prof.add("au.load", Time.get_ticks_usec() - _tv)
	if _medir_cargas and Time.get_ticks_usec() - _tv > 3000:
		print("[au.load] %.0f ms  %s (%d variantes)" % [(Time.get_ticks_usec() - _tv) / 1000.0, key, _out.size()])
	return _out

var _medir_cargas: bool = "--medirfps" in OS.get_cmdline_user_args()


## PRECALENTAR LA BIBLIOTECA. Las variantes se cargaban la PRIMERA vez que sonaba cada clave: un
## DirAccess y un load() por archivo, 50-140 ms de golpe en mitad de la partida (medido con --bancofps:
## el primer aterrizaje del jugador, la primera explosion, el primer impacto de cada material). Aqui se
## cargan las claves que usa el juego durante la pantalla de carga, unas pocas por cuadro.
var _precalentado := false
var presupuesto_precalentar_ms := 400.0   ## ms por cuadro mientras carga el mapa (esos cuadros ya duran ~1 s); main lo baja al empezar
func precalentar() -> void:
	if _precalentado:
		return
	_precalentado = true
	var claves: PackedStringArray = []
	for cls in ["masonry", "metal", "wood", "glass", "plastic", "dirt", "foliage"]:
		for k in ["hit-s", "hit-m", "hit-l", "break-s", "break-m", "break-l", "land", "step", "jump"]:
			claves.append("%s/%s" % [cls, k])
	# LA EXPLOSION, en un hilo y ya en WAV (BANCO_EXPLOSION); con --sinwavexplosion, como antes (aqui, en OGG)
	if _sin_wav_explosion or _sin_conv:
		claves.append_array(PackedStringArray(["explosion/s", "explosion/m", "explosion/l"]))
	else:
		_tareas.append(WorkerThreadPool.add_task(_claves_en_hilo.bind(BANCO_EXPLOSION), false, "audio explosion"))
	if not (_sin_wav_raros or _sin_conv):
		_tareas.append(WorkerThreadPool.add_task(_claves_en_hilo.bind(BANCO_RAROS), false, "audio raros"))
	for k in ["throw/s", "spark", "bullet-pass", "bullet-hit",
			"clickdown", "clickup", "tools/dryfire", "tools/rifle", "tools/shotgun", "tools/launcher", "tools/gun", "silenced", "zombi/muerte"]:
		claves.append(k)
	# los choques y roturas de Crysis: en hilos y YA en WAV (ver _listar_y_cargar), mientras carga el mapa
	if _hay_choques():
		precalentar_bancos(["crysis"])
	var t0 := Time.get_ticks_msec()
	var n := 0
	var tf := Time.get_ticks_usec()
	for k in claves:
		if _en_partida:
			_pedir_en_hilo(k)              # ya jugando: lo que falte, en hilos (antes 4 ms por cuadro... y una clave eran 40)
		elif not _lib.has(k):
			_variants_cargar(k)
			n += 1
		# presupuesto por cuadro, no un await fijo: con la carga lenta, 13 esperas eran 15 s y la
		# biblioteca seguia cargandose ya en partida
		if Time.get_ticks_usec() - tf > int(presupuesto_precalentar_ms * 1000.0) and is_inside_tree():
			await get_tree().process_frame
			tf = Time.get_ticks_usec()
	if debug:
		print("[audio] precalentadas %d claves en %d ms" % [n, Time.get_ticks_msec() - t0])


# ---------------------------------------------------------------------------
# CARGA EN SEGUNDO PLANO: el disco y el decodificador, fuera del fotograma
# ---------------------------------------------------------------------------
var _en_partida := false                ## main lo pone al empezar: desde ahi, nada de cargas en el hilo principal
var _pendientes := {}                   ## clave -> true (encargada a un hilo)
var _llegadas := {}                     ## clave -> Array de AudioStream (lo escribe el hilo, bajo _cerrojo)
var _cerrojo := Mutex.new()
var cargadas_en_hilo := 0               ## (para las pruebas)

func _pedir_en_hilo(key: String) -> void:
	if _pendientes.has(key) or _lib.has(key):
		return
	_pendientes[key] = true
	_tareas.append(WorkerThreadPool.add_task(_cargar_en_hilo.bind(key), false, "audio " + key))


## LAS TAREAS EN HILOS SE ESPERAN (2026-10-01). Antes se lanzaban y no se esperaban nunca: (1) Godot pide esperar cada
## tarea para soltar lo que guarda de ella, y (2) al cerrar el juego con una carga de bancos aun en marcha, el hilo
## seguia ejecutando codigo de este nodo ya liberado y el proceso moria con un acceso a memoria invalido (medido: TODAS
## las salidas de una partida acababan en "Segmentation fault", codigo 139). Ahora se recogen al acabar y al cerrar se
## avisa a los hilos (`_cerrando`) y se espera a que terminen.
var _tareas: Array[int] = []
var _cerrando := false

func _soltar_tareas_hechas() -> void:
	var i := 0
	while i < _tareas.size():
		if WorkerThreadPool.is_task_completed(_tareas[i]):
			WorkerThreadPool.wait_for_task_completion(_tareas[i])
			_tareas.remove_at(i)
		else:
			i += 1


func _esperar_tareas() -> void:
	_cerrando = true
	for t in _tareas:
		WorkerThreadPool.wait_for_task_completion(t)
	_tareas.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_esperar_tareas()


func _cargar_en_hilo(key: String) -> void:
	if _cerrando:
		return
	var out := _listar_y_cargar(key)
	_cerrojo.lock()
	_llegadas[key] = out
	_cerrojo.unlock()


## Lo que han terminado los hilos pasa a la biblioteca (una vez por fotograma, en _process)
func _recoger_llegadas() -> void:
	if not _tareas.is_empty() and Engine.get_process_frames() % 30 == 0:
		_soltar_tareas_hechas()
	if _conv_esperando > 0:
		_cerrojo.lock()
		var cl := _conv_llegadas
		_conv_llegadas = []
		_cerrojo.unlock()
		for c in cl:
			_conv[c[0]] = c[1]
			_conv_esperando -= 1
			if c[1] != null:
				convertidos += 1
				_conv_bytes += (c[1] as AudioStreamWAV).data.size()
	# (antes salia si no habia nada pedido, y lo de los BANCOS se quedaba esperando a que alguien pidiera otra cosa)
	_cerrojo.lock()
	var l := _llegadas
	if not l.is_empty():
		_llegadas = {}
	_cerrojo.unlock()
	for k in l:
		_lib[k] = l[k]
		_pendientes.erase(k)
		cargadas_en_hilo += 1


## LOS SONIDOS QUE MAS SUENAN, EN WAV (2026-10-01, medido). Cada play() de un OGG arranca su decodificador Vorbis
## (desempaqueta sus tablas): 0,9-2 ms en el hilo principal por disparo, impacto o casquillo; con 9 bots en la
## cafeteria eran ~1 ms por fotograma de media y 5-10 ms los fotogramas en que coincidian varios. Un AudioStreamWAV
## arranca en 0,001 ms y, al mezclar, descomprimir QOA cuesta mucho menos que Vorbis (en el movil, menos calor).
## Los archivos NO se tocan: cuando un sonido corto (<= 4 s, sin bucle) ha sonado CONV_MIN_USOS veces, un hilo lo
## decodifica una vez (mix_audio, la misma salida que oiria el jugador) y lo guarda como WAV de 16 bits; desde ahi
## suena ese. Se normaliza antes (algunos disparos pasan de 1,0 de pico y el WAV los recortaria) y la diferencia exacta
## vuelve en el volumen (meta gan_db). Medido contra el OGG: mismo nivel y 73-79 dB de relacion senal/error (o sea,
## igual; el QOA, mas pequeño, dejaba 17-22 dB en los clics y disparos y se descarto). Pesa 86 KB por segundo en mono y
## el doble en estereo; como solo pasan los que mas suenan, son unos pocos MB (tope CONV_MAX_BYTES). A/B: --sinwavcaliente.
const CONV_MIN_USOS := 3
const CONV_MAX_S := 4.0
const CONV_MAX_BYTES := 12 * 1024 * 1024
var _conv_bytes := 0                 ## lo que ocupan ya los convertidos
var _conv: Dictionary = {}           ## AudioStream (ogg) -> AudioStreamWAV, o null si esta encargado o no se puede
var _conv_usos: Dictionary = {}      ## AudioStream -> veces que ha sonado (hasta que se encarga)
var _conv_llegadas: Array = []       ## [ogg, wav o null] (lo escribe el hilo, bajo _cerrojo)
var _conv_esperando := 0
var convertidos := 0                 ## (para las pruebas)
static var _sin_conv: bool = "--sinwavcaliente" in OS.get_cmdline_user_args()

func _caliente(st: AudioStream) -> AudioStream:
	if _sin_conv or not (st is AudioStreamOggVorbis):
		return st
	if _conv.has(st):
		var w = _conv[st]
		return w if w != null else st
	var n := int(_conv_usos.get(st, 0)) + 1
	if n < CONV_MIN_USOS:
		_conv_usos[st] = n
		return st
	_conv_usos.erase(st)
	_conv[st] = null          # encargado (o imposible): no se vuelve a pedir
	var largo := st.get_length()
	if (st as AudioStreamOggVorbis).loop or largo <= 0.0 or (largo > CONV_MAX_S and not _duracion_rota(largo)) 			or _cerrando or _conv_bytes > CONV_MAX_BYTES:
		return st
	_conv_esperando += 1
	_tareas.append(WorkerThreadPool.add_task(_convertir_en_hilo.bind(st), false, "audio wav"))
	return st


func _convertir_en_hilo(st: AudioStream) -> void:
	var w: AudioStreamWAV = null
	if not _cerrando:
		w = _a_wav(st)
	_cerrojo.lock()
	_conv_llegadas.append([st, w])
	_cerrojo.unlock()


## LA DURACION ROTA (2026-10-02, medido con --audiocenso y los bots a tiros): hay OGG cuya ultima pagina dice una
## duracion absurda (bf/bala/chasquido1.ogg: 89.478 s, y dura uno). Se los saltaba la conversion, y era el chasquido de
## las balas que te pasan cerca: 103 veces en 90 s a 1,75 ms cada arranque (el de al lado, ya en WAV, 0,07). Ahora se
## decodifican hasta que el propio reproductor se para, con el tope de siempre.
static func _duracion_rota(largo: float) -> bool:
	return largo > 3600.0


static func _a_wav(st: AudioStream, max_s: float = CONV_MAX_S) -> AudioStreamWAV:
	var largo := st.get_length()
	var rota := _duracion_rota(largo)
	if largo <= 0.0 or (largo > max_s and not rota):
		return null
	var rate := int(AudioServer.get_mix_rate())
	var pb := st.instantiate_playback()
	if pb == null:
		return null
	pb.start(0.0)
	var fr: PackedVector2Array
	if rota:
		# a trozos, hasta que se acabe de verdad (o el tope): mix_audio rellena con silencio al pasarse
		var tope := int(max_s * rate)
		while fr.size() < tope and pb.is_playing():
			fr.append_array(pb.mix_audio(1.0, 2048))
		if pb.is_playing():
			pb.stop()
			return null           # mas largo que el tope: no es un sonido corto
		var fin := fr.size()
		while fin > 0 and absf(fr[fin - 1].x) < 0.00001 and absf(fr[fin - 1].y) < 0.00001:
			fin -= 1          # el silencio con el que se relleno el ultimo trozo
		fr.resize(fin + 32)
	else:
		fr = pb.mix_audio(1.0, int(ceil(largo * rate)) + 32)
	pb.stop()
	if fr.size() < 16:
		return null
	var muestras := fr.to_byte_array().to_float32_array()
	var arr := Array(muestras)
	var pico := maxf(float(arr.max()), -float(arr.min()))
	if pico < 0.0001:
		return null
	# ¿mono grabado en estereo? (los dos canales iguales): se guarda en mono, la mitad
	var mono := true
	var paso := maxi(1, fr.size() / 1500)
	for k in range(0, fr.size(), paso):
		if absf(fr[k].x - fr[k].y) > 0.00001:
			mono = false
			break
	var datos := muestras.to_byte_array()
	var h := PackedByteArray()
	h.resize(44)
	h.encode_u32(0, 0x46464952)          # "RIFF"
	h.encode_u32(4, 36 + datos.size())
	h.encode_u32(8, 0x45564157)          # "WAVE"
	h.encode_u32(12, 0x20746d66)         # "fmt "
	h.encode_u32(16, 16)
	h.encode_u16(20, 3)                  # coma flotante
	h.encode_u16(22, 2)
	h.encode_u32(24, rate)
	h.encode_u32(28, rate * 8)
	h.encode_u16(32, 8)
	h.encode_u16(34, 32)
	h.encode_u32(36, 0x61746164)         # "data"
	h.encode_u32(40, datos.size())
	var w := AudioStreamWAV.load_from_buffer(h + datos, {"compress/mode": 0, "edit/normalize": true, "force/mono": mono})
	if w == null:
		return null
	w.set_meta("gan_db", linear_to_db(pico))
	return w


## BANCOS: todas las claves de unas carpetas (p. ej. "l4d2/criaturas" -> "l4d2/criaturas/gordo/ataque",
## ...), cargadas en hilos al empezar el mapa. Asi la primera voz de cada bicho ya esta en memoria.
func precalentar_bancos(carpetas: Array) -> void:
	_tareas.append(WorkerThreadPool.add_task(_bancos_en_hilo.bind(carpetas), false, "audio bancos"))


func _bancos_en_hilo(carpetas: Array) -> void:
	var claves := {}
	for c in carpetas:
		_claves_de_carpeta("res://sounds/" + String(c), String(c), claves)
	for k in claves:
		if _cerrando:
			return
		if _lib.has(k):
			continue
		var out := _listar_y_cargar(k)
		_cerrojo.lock()
		_llegadas[k] = out
		_cerrojo.unlock()


func _claves_de_carpeta(ruta: String, clave: String, claves: Dictionary) -> void:
	var dir := DirAccess.open(ruta)
	if dir == null:
		return
	for sub in dir.get_directories():
		_claves_de_carpeta(ruta + "/" + sub, clave + "/" + sub, claves)
	for f in dir.get_files():
		var fn: String = f.trim_suffix(".import").trim_suffix(".remap")
		if not fn.ends_with(".ogg"):
			continue
		var stem := fn.trim_suffix(".ogg")
		# "ataque3" -> "ataque": el prefijo sin los digitos del final
		var i := stem.length()
		while i > 0 and stem[i - 1] >= "0" and stem[i - 1] <= "9":
			i -= 1
		claves[clave + "/" + stem.substr(0, i)] = true


func _variants_cargar(key: String) -> Array:
	var out := _listar_y_cargar(key)
	_lib[key] = out
	return out


## Sin tocar _lib (se puede llamar desde un hilo)
func _listar_y_cargar(key: String) -> Array:
	var parts := key.rsplit("/", true, 1)
	# "bf/..." vive en sounds/bf (Battlefield, temporal), no dentro de la biblioteca de Teardown
	var raiz: String = "res://sounds/" if (key.begins_with("bf/") or key.begins_with("armas/") or key.begins_with("l4d2/") or key.begins_with("gen/") or key.begins_with("crysis/")) else ROOT
	var folder: String = raiz + (parts[0] + "/" if parts.size() > 1 else "")
	var prefix: String = parts[-1]
	var out: Array = []
	var dir := DirAccess.open(folder)
	var vistos := {}
	if dir:
		for f in dir.get_files():
			var fn: String = f.trim_suffix(".import").trim_suffix(".remap")
			# en el editor estan el .ogg y su .import: sin esto cada sonido se cargaba DOS veces
			if not fn.ends_with(".ogg") or vistos.has(fn):
				continue
			vistos[fn] = true
			var stem := fn.trim_suffix(".ogg")
			# prefijo exacto seguido de dígitos: "hit-s" no debe coger "hit-s-loop" ni "hit-sm"
			if stem == prefix or (stem.begins_with(prefix) and stem.substr(prefix.length()).is_valid_int()):
				# carga directa del .ogg (sin pasar por el importador del editor: funciona también en
				# ejecuciones sin editor y en exportaciones que incluyan los .ogg como archivos)
				var st: AudioStream = _load_ogg(folder + fn)
				if st:
					out.append(st)
	if out.is_empty():
		push_warning("[audio] sin archivos para la clave '%s' (%s%s*.ogg)" % [key, folder, prefix])
	# LOS DE CRYSIS, YA EN WAV (2026-10-03, pedido: "muchas variantes, pero que no haya nada de lag"): son cientos de
	# variantes cortas y cada una sonaria pocas veces, asi que casi ninguna llegaria a "caliente" y cada arranque de OGG
	# eran 1-2,4 ms en el hilo principal (medido con --audiocenso). Se decodifican aqui (en el hilo de los bancos, durante
	# la carga) y en partida arrancan en ~0,001 ms. ~16 MB en memoria (crysis_bytes); --sinwavcaliente los deja en OGG.
	# Y LOS DE LA EXPLOSION (2026-10-05, auditoria + pedido "segui con el sonido de las explosiones a WAV"): medido con
	# --audiocenso a cohetazos en la cafeteria, arrancar sonidos eran 881 ms en 60 s en el hilo principal y lo que mas
	# pesaba era la explosion: las capas de BF (escombros, derrumbe grave, crujido...) y los estallidos de Teardown
	# (explosion/l, /m) a 0,9-1,6 ms cada arranque. Duran mas de CONV_MAX_S, asi que nunca pasaban a "caliente". Se
	# convierten aqui (hilo de los bancos, durante la carga) con su propio tope. --sinwavexplosion = como antes.
	var es_explosion: bool = key in BANCO_EXPLOSION and not _sin_wav_explosion
	var es_raro: bool = key in BANCO_RAROS and not _sin_wav_raros
	if (key.begins_with("crysis/") or es_explosion or es_raro) and not _sin_conv:
		for i in out.size():
			var w := _a_wav(out[i], CONV_EXPLOSION_MAX_S if es_explosion else CONV_MAX_S)
			if w != null:
				w.resource_name = (out[i] as AudioStream).resource_path
				out[i] = w
				_cerrojo.lock()
				if es_explosion:
					explosion_bytes += w.data.size()
				elif es_raro:
					raros_bytes += w.data.size()
				else:
					crysis_bytes += w.data.size()
				_cerrojo.unlock()
	return out

var crysis_bytes := 0         ## lo que ocupan en memoria los de Crysis ya en WAV
var explosion_bytes := 0      ## y los de la explosion (BANCO_EXPLOSION)
## Lo que suena en cada explosion (Audio.explosion y _te_cae_encima): se carga en un hilo al empezar y ya en WAV
const BANCO_EXPLOSION := ["explosion/s", "explosion/m", "explosion/l", "bf/destru/hormigon", "bf/destru/ladrillo",
	"bf/destru/metal", "bf/destru/escombros", "bf/destru/crujido", "bf/destru/derrumbe_grave",
	"bf/yo/destruccion_fuerte", "bf/yo/destruccion", "bf/yo/zona"]
const CONV_EXPLOSION_MAX_S := 20.0
## LOS RAROS PERO CAROS (2026-10-16, --audiocenso en la cafeteria con bots): suenan pocas veces por partida (morir, el
## lanzacohetes, el cohete que pasa, la explosion en la cara), asi que nunca llegan a "caliente" y cada arranque de OGG
## eran 1-2 ms en el hilo principal, justo en los fotogramas de una muerte o una explosion. ~0,8 MB de OGG, ~6 MB en
## WAV. Se cargan en un hilo al empezar, como BANCO_EXPLOSION (y con su tope). --sinwavraros = como antes.
const BANCO_RAROS := ["bf/soldado/muere", "bf/soldado/muere_bala", "bf/soldado/muere_cuchillo", "bf/soldado/muere_explosion",
	"bf/soldado/cae_suelo", "bf/soldado/cargador_fusil", "bf/soldado/cargador_subfusil", "bf/proyectil/cohete_pasa",
	"bf/proyectil/cohete_sale", "bf/proyectil/cohete_estela", "bf/yo/explosion_cerca", "bf/yo/explosion_fuerte",
	"bf/yo/explosion_pitido", "bf/yo/metralla"]
static var _sin_wav_raros: bool = "--sinwavraros" in OS.get_cmdline_user_args()
var raros_bytes := 0
static var _sin_wav_explosion: bool = "--sinwavexplosion" in OS.get_cmdline_user_args()


## Claves sueltas cargadas en un hilo (como _bancos_en_hilo, pero sin recorrer carpetas enteras)
func _claves_en_hilo(claves: Array) -> void:
	for k in claves:
		if _cerrando:
			return
		if _lib.has(k):
			continue
		var out := _listar_y_cargar(String(k))
		_cerrojo.lock()
		_llegadas[String(k)] = out
		_cerrojo.unlock()


## En el editor/ejecutable de PC el .ogg está tal cual (load_from_file); en la APK sólo va el recurso importado
## (.oggvorbisstr), que se obtiene con load() a través del remapeo del .import.
func _load_ogg(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var r = load(path)
		if r is AudioStream:
			return r
	return AudioStreamOggVorbis.load_from_file(path)

var _ultima_variante: Dictionary = {}   ## clave -> indice de la ultima variante que sono

func _pick(key: String) -> AudioStream:
	var v := _variants(key)
	if v.is_empty():
		played[key] = -1
		return null
	played[key] = int(played.get(key, 0)) + 1
	# NUNCA LA MISMA DOS VECES SEGUIDAS: con cuatro variantes al azar, repetir sale una de cada cuatro y
	# el oido lo pilla enseguida ("siempre la misma explosion")
	var i := randi() % v.size()
	if v.size() > 1 and i == int(_ultima_variante.get(key, -1)):
		i = (i + 1 + randi() % (v.size() - 1)) % v.size()
	_ultima_variante[key] = i
	return v[i]


var _sonido_por_dureza: bool = "--sonidopordureza" in OS.get_cmdline_user_args()      ## = como antes

## Carpeta de Teardown para un material de vxcore (por su densidad, como la textura; --sonidopordureza = como antes).
func material_class(mat: int) -> String:
	if _class_cache.has(mat):
		return _class_cache[mat]
	var cls := "masonry"
	if world and world.has_method("get_material_info") and mat > 0:
		var info: Dictionary = world.get_material_info(mat)
		var st := int(info.get("strength", 170))
		var dens := int(info.get("density", 0))
		if _sonido_por_dureza:
			# (como antes: por la dureza; el hormigon y el adoquin de 150/220/240 sonaban a METAL)
			if info.get("glass", false):
				cls = "glass"
			elif st <= 30 or st <= 45:
				cls = "plastic"
			elif st == 200 and info.get("anchor", false):
				cls = "dirt"
			elif st <= 55:
				cls = "wood"
			elif st in [150, 220, 240]:
				cls = "metal"
		# EL SONIDO, POR LO QUE SE VE (2026-10-20, bug: "golpeo el piso de hormigon y suena a metal"): la misma regla que
		# la textura del material (voxel_world.cpp familiaTextura, por la DENSIDAD): metal desde 5000, tela/plastico hasta
		# 450, madera hasta 800, organico (hojas) hasta 1200, tierra hasta 1700 y el resto piedra, hormigon, ladrillo...
		elif info.get("glass", false):
			cls = "glass"
		elif dens >= 5000:
			cls = "metal"
		elif dens > 0 and dens <= 450:
			cls = "plastic"
		elif dens > 0 and dens <= 800:
			cls = "wood"
		elif dens > 0 and dens <= 1200:
			cls = "foliage"
		elif dens > 0 and dens <= 1700:
			cls = "dirt"
		else:
			cls = "masonry"       # yeso, hormigón, ladrillo, mampostería, roca, adoquín, baldosa
	_class_cache[mat] = cls
	return cls


static func size_tag(n: float, small: float, large: float) -> String:
	return "s" if n < small else ("l" if n >= large else "m")


# ---------------------------------------------------------------------------
# Voces
# ---------------------------------------------------------------------------
## Voz 3D libre o robada a un sonido de prioridad <= pri (el más antiguo). null si no hay ninguna.
## (2026-10-13, bug: "a veces no se oye la granada ni los disparos de mis compañeros"; medido con --audioperdidos: tras
## una explosion los cascotes llenaban las 32 voces y lo importante se quedaba SIN VOZ, porque no se robaba una voz de
## menos de 50 ms). Ahora: lo de prioridad baja (cascotes, impactos) deja siempre VOCES_RESERVADAS libres para lo
## demas, y un sonido de mas prioridad le quita la voz a uno de menos aunque acabe de empezar.
const VOCES_RESERVADAS := 8

func _alloc3d(pri: int) -> int:
	var now := Time.get_ticks_msec() * 0.001
	var best := -1
	var best_pri := 99
	var best_t := INF
	var libre := -1
	var libres := 0
	for i in POOL_3D:
		if not _pool3d[i].playing:
			libres += 1
			if libre < 0:
				libre = i
	if libre >= 0 and (pri > PRI_LOW or libres > VOCES_RESERVADAS):
		return libre
	for i in POOL_3D:
		if not _pool3d[i].playing:
			continue
		if _pri3d[i] <= pri and (_pri3d[i] < best_pri or (_pri3d[i] == best_pri and _t3d[i] < best_t)):
			best = i
			best_pri = _pri3d[i]
			best_t = _t3d[i]
	if best >= 0 and (best_pri < pri or now - best_t > 0.05):
		if _pool3d[best].playing:
			_pool3d[best].stop()
		return best
	return -1


func _alloc2d(pri: int) -> int:
	var best := -1
	var best_pri := 99
	var best_t := INF
	for i in POOL_2D:
		if not _pool2d[i].playing:
			return i
		if _pri2d[i] <= pri and (_pri2d[i] < best_pri or (_pri2d[i] == best_pri and _t2d[i] < best_t)):
			best = i
			best_pri = _pri2d[i]
			best_t = _t2d[i]
	return best


# ---------------------------------------------------------------------------
# Reproducción
# ---------------------------------------------------------------------------
func play3d(key: String, pos: Vector3, db: float = 0.0, pitch_var: float = 0.08, max_dist: float = 60.0, pri: int = PRI_LOW, tono: float = 1.0) -> void:
	if not enabled:
		return
	if _budget[pri] >= BUDGET[pri]:
		_perdido("tope", key)
		return
	_budget[pri] += 1
	# retardo por velocidad del sonido a partir de 40 m (explosiones y disparos lejanos llegan tarde)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam and pri >= PRI_HIGH:
		var dist := cam.global_position.distance_to(pos)
		if dist > 40.0:
			if dist > max_dist:
				_perdido("lejos", key)
				return
			_pending.append([Time.get_ticks_msec() * 0.001 + dist / SPEED_OF_SOUND, key, pos, db, pitch_var, max_dist, pri, tono])
			return
	_play3d_now(key, pos, db, pitch_var, max_dist, pri, tono)


func _play3d_now(key: String, pos: Vector3, db: float, pitch_var: float, max_dist: float, pri: int, tono: float = 1.0) -> void:
	var st := _pick(key)
	if st == null:
		_perdido("sin cargar", key)
		if debug:
			print("[audio] sin variantes para ", key)
		return
	_lanzar3d(st, pos, db, pitch_var, max_dist, pri, tono)


## Suelta por una voz 3D un sonido YA ELEGIDO, venga de la biblioteca o de donde sea.
## TOPE DE ARRANQUES POR FOTOGRAMA (2026-09-26, medido: con cuatro bots disparando a la vez, 10-15 ms de
## au.play en un fotograma; cada play() de un OGG arranca su decodificador, ~1 ms). Los que no caben esperan
## al fotograma siguiente -16 ms, no se oye la diferencia- y no se pierde ninguno. Y la MISMA clave en el mismo
## sitio en menos de REPITE_S suena una vez: dos disparos identicos solapados ya son uno para el oido.
const ARRANQUES_MAX := 6
const REPITE_S := 0.035
var _arranques := 0
var _diferidos: Array = []           ## [st, pos, db, pitch_var, max_dist, pri, tono]
var _ultimo_de: Dictionary = {}      ## AudioStream -> [t, pos]

func _lanzar3d(st: AudioStream, pos: Vector3, db: float, pitch_var: float, max_dist: float, pri: int, tono: float = 1.0) -> void:
	var ahora := Time.get_ticks_msec() * 0.001
	var u = _ultimo_de.get(st)
	if u != null and ahora - float(u[0]) < REPITE_S and (u[1] as Vector3).distance_to(pos) < 3.0:
		_perdido("repetido", str(st.resource_path).get_file())
		return
	if _arranques >= ARRANQUES_MAX:
		if _diferidos.size() < 24:
			_diferidos.append([st, pos, db, pitch_var, max_dist, pri, tono])
		else:
			_perdido("cola llena", str(st.resource_path).get_file())
		return
	_arranques += 1
	_ultimo_de[st] = [ahora, pos]
	_lanzar3d_ya(st, pos, db, pitch_var, max_dist, pri, tono)


## Al empezar cada fotograma: los que se quedaron sin sitio en el anterior, primero los de mas prioridad
func _diferidos_tick() -> void:
	_arranques = 0
	if _ultimo_de.size() > 256:
		_ultimo_de.clear()
	if _diferidos.is_empty():
		return
	var cola := _diferidos
	_diferidos = []
	cola.sort_custom(func(a, b): return int(a[5]) > int(b[5]))
	for d in cola:
		_lanzar3d(d[0], d[1], d[2], d[3], d[4], d[5], d[6])


func _lanzar3d_ya(st: AudioStream, pos: Vector3, db: float, pitch_var: float, max_dist: float, pri: int, tono: float = 1.0) -> void:
	var _tl := Time.get_ticks_usec()
	var i := _alloc3d(pri)
	Prof.add("au.alloc", Time.get_ticks_usec() - _tl); _tl = Time.get_ticks_usec()
	if i < 0:
		_perdido("sin voz p%d" % pri, str(st.resource_path).get_file())
		if debug:
			print("[audio] sin voz libre (prioridad ", pri, ")")
		return
	var p := _pool3d[i]
	_pri3d[i] = pri
	_t3d[i] = Time.get_ticks_msec() * 0.001
	var sr := _caliente(st)
	p.stream = sr
	p.global_position = pos
	# ¿HAY UNA PARED EN MEDIO? Un tiro detras de un muro suena sordo, no igual de nitido que uno a la
	# vista. Se resuelve bajando el corte del filtro de este altavoz: los agudos son lo primero que
	# se come el hormigon, y sin agudos el oido lo lee como "eso viene de detras de algo".
	#
	# Y esto NO es solo adorno, es informacion de juego: te dice si el que dispara te ve o no te ve.
	#
	# Solo se comprueba a partir de 4 m -lo que suena pegado a ti no lo tapa nada- y solo si el nucleo
	# sabe hacerlo. Es un rayo por sonido, en C++, y los sonidos que llegan tan lejos son pocos.
	var tapado := false
	if world and world.has_method("has_line_of_sight"):
		var oyente := _listener_pos()
		if oyente != Vector3.INF and oyente.distance_to(pos) > 4.0:
			tapado = not world.has_line_of_sight(pos, oyente)
	Prof.add("au.los", Time.get_ticks_usec() - _tl); _tl = Time.get_ticks_usec()
	p.attenuation_filter_cutoff_hz = 700.0 if tapado else 2200.0
	p.attenuation_filter_db = -30.0 if tapado else -22.0
	p.volume_db = db + master_db - (5.0 if tapado else 0.0) + float(sr.get_meta("gan_db", 0.0))
	# el tono base lo pone quien llama: asi un mismo sonido sirve para varias cosas cambiandolo
	p.pitch_scale = tono * randf_range(1.0 - pitch_var, 1.0 + pitch_var)
	p.max_distance = max_dist
	p.play()
	Prof.add("au.play", Time.get_ticks_usec() - _tl)
	if _censo_on:
		_censo_apunta(st, Time.get_ticks_usec() - _tl)


## CENSO (--audiocenso): que archivos suenan en partida, cuantas veces y cuanto cuesta arrancarlos (un OGG
## desempaqueta su decodificador en cada play(): 0,9-2 ms; un WAV, 0,003). Se imprime al cerrar.
static var _censo_on: bool = "--audiocenso" in OS.get_cmdline_user_args()
var _censo: Dictionary = {}          ## ruta -> [veces, us]

func _censo_apunta(st: AudioStream, us: int) -> void:
	var r: String = (st.resource_path if st.resource_path != "" else "wav:" + st.resource_name) if st else "?"
	var c = _censo.get(r)
	if c == null:
		c = [0, 0]
		_censo[r] = c
	c[0] += 1
	c[1] += us
	if us > 10000:
		print("[audiocenso] LENTO: %.1f ms en play() de %s (cuadro %d)" % [us / 1000.0, r, Engine.get_process_frames()])


func _exit_tree() -> void:
	_esperar_tareas()
	if not _censo_on:
		return
	var filas: Array = []
	var tot_us := 0
	var tot_n := 0
	for r in _censo:
		filas.append([r, _censo[r][0], _censo[r][1]])
		tot_us += int(_censo[r][1])
		tot_n += int(_censo[r][0])
	filas.sort_custom(func(a, b): return int(a[2]) > int(b[2]))
	print("[audiocenso] %d arranques, %.1f ms en play(), %d archivos distintos · pasados a WAV: %d (%.1f MB)" % [tot_n, tot_us / 1000.0, filas.size(), convertidos, _conv_bytes / 1048576.0])
	var cr_n := 0
	var cr_us := 0
	for f in filas:
		if "crysis" in String(f[0]):
			cr_n += int(f[1])
			cr_us += int(f[2])
	print("[audiocenso] Crysis: %d arranques, %.1f ms en play() (%.3f ms cada uno), %.1f MB en WAV" % [cr_n, cr_us / 1000.0, cr_us / 1000.0 / maxf(1.0, cr_n), crysis_bytes / 1048576.0])
	var ex_n := 0
	var ex_us := 0
	for f in filas:
		var ruta := String(f[0])
		if "/td/explosion/" in ruta or "/bf/destru/" in ruta or "/bf/yo/destruccion" in ruta or "/bf/yo/zona" in ruta:
			ex_n += int(f[1])
			ex_us += int(f[2])
	print("[audiocenso] Raros (BANCO_RAROS): %.1f MB en WAV" % (raros_bytes / 1048576.0))
	print("[audiocenso] Explosion: %d arranques, %.1f ms en play() (%.3f ms cada uno), %.1f MB en WAV" % [ex_n, ex_us / 1000.0, ex_us / 1000.0 / maxf(1.0, ex_n), explosion_bytes / 1048576.0])
	for i in mini(60, filas.size()):
		print("[audiocenso]   %5d x %7.1f ms  (%.2f ms cada uno)  %s" % [filas[i][1], filas[i][2] / 1000.0, filas[i][2] / 1000.0 / maxf(1.0, filas[i][1]), filas[i][0]])


## Donde esta la oreja. Devuelve INF si todavia no hay camara (durante la carga, por ejemplo).
func _listener_pos() -> Vector3:
	if not is_inside_tree():
		return Vector3.INF
	var c := get_viewport().get_camera_3d()
	return c.global_position if c else Vector3.INF


func play2d(key: String, db: float = 0.0, pitch_var: float = 0.05, pri: int = PRI_MID, tono: float = 1.0) -> void:
	if not enabled:
		return
	var st := _pick(key)
	if st == null:
		return
	var i := _alloc2d(pri)
	if i < 0:
		return
	var p := _pool2d[i]
	_pri2d[i] = pri
	_t2d[i] = Time.get_ticks_msec() * 0.001
	var sr := _caliente(st)
	p.stream = sr
	p.volume_db = db + master_db + float(sr.get_meta("gan_db", 0.0))
	p.pitch_scale = tono * randf_range(1.0 - pitch_var, 1.0 + pitch_var)
	var _tc := Time.get_ticks_usec()
	p.play()
	if _censo_on:
		_censo_apunta(st, Time.get_ticks_usec() - _tc)


# --- LOS CHOQUES DE CRYSIS (2026-10-03, pedido: "muchos sonidos para destruir metal o madera, con muchas variables para
# no repetir") ---------------------------------------------------------------------------------------------------------
# sounds/crysis/choque/<clase>/<s|m|l><n>.ogg (tools/importar_crysis_choques.py, 194 archivos: metal 66, piedra 45,
# madera 30, tierra 24, plastico 15, cristal 14), igualados a -20 dB RMS. Van ENCIMA de los de Teardown donde algo se
# rompe o cae, por material y tamaño: rotura, pieza que aterriza, escombro que toca el suelo y talla grande. Temporal
# como BF: sin la carpeta (o con --sincrysis) suena como antes.
const CHOQUE := "crysis/choque/"
const CHOQUE_CLASES := ["metal", "wood", "glass", "masonry", "dirt", "plastic"]
var _choques_on := -1
func _hay_choques() -> bool:
	if _choques_on < 0:
		_choques_on = 0 if "--sincrysis" in OS.get_cmdline_user_args() else int(DirAccess.dir_exists_absolute("res://sounds/" + CHOQUE + "metal"))
	return _choques_on == 1


## Un choque de Crysis del material (las clases sin banco propio, como el follaje, suenan a tierra)
func choque(cls: String, tam: String, pos: Vector3, db: float, max_dist: float, pri: int) -> void:
	if not _hay_choques():
		return
	if not cls in CHOQUE_CLASES:
		cls = "dirt" if cls == "foliage" else "masonry"
	play3d("%s%s/%s" % [CHOQUE, cls, tam], pos, db, 0.12, max_dist, pri)


## EL NANOTRAJE de Crysis (sounds/crysis/traje): "blindaje" = el traje endureciendose, "voz_blindaje" = "Maximum Armor"
## (habilidad.gd la pone solo a veces). false si no
## esta (sin la carpeta o con --sincrysis): quien llama pone el suyo de antes.
## `en_2d`: el de tu propio traje, en estereo y sin posicion (como en Crysis: el barrido de un lado a otro se oye).
var _hay_traje := -1
func traje(nombre: String, pos: Vector3, db: float, alcance: float, en_2d: bool = false) -> bool:
	if _hay_traje < 0:
		_hay_traje = int(_hay_choques() and DirAccess.dir_exists_absolute("res://sounds/crysis/traje"))
	if _hay_traje == 0:
		return false
	if en_2d:
		play2d("crysis/traje/" + nombre, db - 4.0, 0.0, PRI_HIGH)
	else:
		play3d("crysis/traje/" + nombre, pos, db, 0.0, alcance, PRI_HIGH)
	return true


## LAS ROTURAS de Crysis (physics_destructibles: chapa que se raja, tablas que se astillan, cristal, roca): hay de
## metal, madera y cristal en los tres tamaños y de piedra en grande. Si no hay del material o del tamaño, un choque.
const ROTURA := "crysis/rotura/"
const ROTURA_HAY := {"metal": "sml", "wood": "sml", "glass": "sml", "masonry": "l"}
func rotura(cls: String, tam: String, pos: Vector3, db: float, max_dist: float, pri: int) -> void:
	if not _hay_choques():
		return
	if tam in String(ROTURA_HAY.get(cls, "")):
		play3d("%s%s/%s" % [ROTURA, cls, tam], pos, db, 0.1, max_dist, pri)
	else:
		choque(cls, tam, pos, db, max_dist, pri)


## Impacto de bala / talla en un material: `removed` voxels quitados (tamaño del cráter).
func hit(mat: int, pos: Vector3, removed: int) -> void:
	var cls := material_class(mat)
	var tag := size_tag(removed, 12, 80)
	play3d("%s/hit-%s" % [cls, tag], pos, -2.0, 0.08, 60.0, PRI_LOW)
	if tag == "l":
		choque(cls, "m", pos, -6.0, 60.0, PRI_LOW)       # un mazazo o un perdigonazo que arranca un trozo
	if cls == "metal":
		play3d("spark", pos, -6.0, 0.1, 40.0, PRI_LOW)
	elif cls == "glass" and removed > 4:
		play3d("glass/break-s", pos, -4.0, 0.08, 60.0, PRI_MID)


## Rotura: una pieza se desprende (voxels = tamaño de la pieza).
func piece_break(mat: int, pos: Vector3, voxels: int) -> void:
	if debug:
		print("[audio] rotura mat=%d vox=%d en %s" % [mat, voxels, str(pos)])
	var cls := material_class(mat)
	var tag := size_tag(voxels, 120, 1500)
	play3d("%s/break-%s" % [cls, tag], pos, 2.0, 0.06, 90.0 if tag != "l" else 140.0, PRI_MID if tag != "s" else PRI_LOW)
	# y encima uno de Crysis que cambia cada vez: la rotura del material o un golpe suyo (en el metal: 14-10 de Teardown
	# por 3 roturas y 21-23 golpes de Crysis, y el tono de cada uno varia un 10-12 %: nunca suena igual dos veces)
	if randf() < 0.5:
		rotura(cls, tag, pos, -5.0 if tag != "s" else -9.0, 90.0, PRI_LOW)
	else:
		choque(cls, tag, pos, -4.0 if tag != "s" else -8.0, 90.0, PRI_LOW)
	if tag == "l":
		derrumbe(pos, voxels)
	elif tag == "m":
		rotura_bf(cls, pos)


## Un escombro toca el suelo.
## UN ESCOMBRO QUE ATERRIZA NO ES UN SONIDO CADA UNO. El nucleo entrega hasta 24 aterrizajes por frame
## y cada play() de un OGG cuesta ~1 ms (instancia el decodificador): 8 por frame eran 8 ms de CADA
## fotograma de demolicion (medido en Monaco con --bancofps), para un rumor a -14 dB que el oido no
## distingue de uno cada 25 ms.
var escombro_gap := 0.025       ## s entre sonidos de escombro pequeno (0 = sin limite, para medir)
var _escombro_t := -1.0
func debris_land(pos: Vector3, mat: int = 0) -> void:
	var ahora := Time.get_ticks_msec() * 0.001
	if ahora - _escombro_t < escombro_gap:
		return
	_escombro_t = ahora
	# del MATERIAL que cae (antes siempre el mismo golpe de piedra): dos de cada tres, uno de Crysis; el otro, el de siempre
	if _hay_choques() and randf() < 0.67:
		choque(material_class(mat) if mat > 0 else "masonry", "s", pos, -18.0, 25.0, PRI_LOW)
	else:
		play3d("masonry/hit-s", pos, -14.0, 0.15, 25.0, PRI_LOW)


## Una pieza grande aterriza.
func piece_land(mat: int, pos: Vector3, voxels: int) -> void:
	var cls := material_class(mat)
	play3d("%s/land" % cls, pos, 0.0 if voxels > 400 else -6.0, 0.08, 70.0, PRI_MID if voxels > 400 else PRI_LOW)
	# el golpe del material encima del sordo de Teardown (chapa, tablas, cascotes...)
	choque(cls, size_tag(voxels, 150, 800), pos, -10.0 if voxels > 400 else -15.0, 70.0, PRI_LOW)


const CAPAS_RAFAGA_S := 0.35
var _capas_t := -1e9


func explosion(pos: Vector3, radius: float) -> void:
	if debug:
		print("[audio] explosion r=%.1f en %s (oyente a %.1f m)" % [radius, str(pos), _listener_dist(pos)])
	# NO SIEMPRE LA MISMA: el tamano a veces coge el de al lado (un misil no suena igual dos veces), el
	# tono varia mas y encima va una capa de BF distinta cada vez: escombro, hormigon, metal, ladrillo
	var tam := size_tag(radius, 1.8, 3.5)
	if randf() < 0.35:
		tam = {"s": "m", "m": ["s", "l"][randi() % 2], "l": "m"}[tam]
	var _tx := Time.get_ticks_usec()
	play3d("explosion/%s" % tam, pos, 6.0, 0.10, 400.0, PRI_TOP)
	Prof.add("au.ex.base", Time.get_ticks_usec() - _tx); _tx = Time.get_ticks_usec()
	# LAS CAPAS DE ESCOMBRO, UNA VEZ POR RAFAGA (2026-10-02, medido con los bots a cohetazos: cada capa es un OGG largo que
	# arranca su decodificador, 8 ms de las tres juntas y 13 la explosion entera). Si la anterior fue hace menos de
	# CAPAS_RAFAGA_S, sus capas siguen sonando: esta solo pone su estallido. Una explosion suelta suena como siempre.
	var ahora_c: float = Time.get_ticks_msec() * 0.001
	if ahora_c - _capas_t >= CAPAS_RAFAGA_S or radius >= 3.5:
		_capas_t = ahora_c
		bf3d(["destru/hormigon", "destru/ladrillo", "destru/metal", "destru/escombros", "destru/crujido"][randi() % 5],
			pos, -2.0, 120.0, PRI_MID, 0.08)
		# BF: la cola de escombros que caen despues, y en las grandes el grave que se nota en el pecho
		bf3d("destru/escombros", pos, -2.0, 80.0, PRI_LOW)
		if radius >= 3.5:
			bf3d("destru/derrumbe_grave", pos, 0.0, 300.0, PRI_HIGH)
	Prof.add("au.ex.capas", Time.get_ticks_usec() - _tx); _tx = Time.get_ticks_usec()
	# EL MUNDO SE TE VIENE ENCIMA (los "Damage" de BF, en tu cabeza): un misil que revienta cerca te
	# cubre de escombro. Cuanto mas grande y mas cerca, mas fuerte la capa.
	_te_cae_encima(_listener_dist(pos), radius * 7.0)
	Prof.add("au.ex.encima", Time.get_ticks_usec() - _tx); _tx = Time.get_ticks_usec()
	_fuego_cerca(_listener_dist(pos), radius)
	Prof.add("au.ex.fuego", Time.get_ticks_usec() - _tx)

var debug := "--audiodbg" in OS.get_cmdline_user_args()
func _listener_dist(pos: Vector3) -> float:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	return cam.global_position.distance_to(pos) if cam else -1.0


## Paso del jugador (2D, sin atenuación) sobre el material bajo los pies.
func footstep(mat: int, running: bool) -> void:
	play2d("%s/step" % material_class(mat), -10.0 if not running else -6.0, 0.1, PRI_LOW)


## ARRANQUE DE RONDA: los primeros sesenta segundos, las pisadas ajenas suenan al 20 %.
## Al empezar la ronda salen veinte cuerpos a la vez de dos bases y todos echan a correr; con las
## pisadas a volumen normal eso no es informacion, es un ruido continuo que ademas tapa los disparos.
## Pasado el primer minuto la gente ya esta repartida por el mapa y una pisada vuelve a significar
## algo -alguien viene-, asi que recupera su volumen entero.
const RONDA_SILENCIO_S := 60.0
const RONDA_SILENCIO_DB := -14.0     # 20 log10(0,2): justo el 20 % de amplitud
var _ronda_t := -1e9

func empezar_ronda() -> void:
	_ronda_t = float(Time.get_ticks_msec()) / 1000.0

## Pisada de OTRO (bot o jugador en red). Va en 3D -la tuya no- para que se oiga de donde viene y se
## apague con la distancia: veinte bots sonando en 2D al mismo volumen era lo que sonaba "en bucle".
func footstep_otro(mat: int, running: bool, pos: Vector3) -> void:
	var db: float = -12.0 if not running else -8.0
	var t: float = float(Time.get_ticks_msec()) / 1000.0 - _ronda_t
	if t < RONDA_SILENCIO_S:
		db += RONDA_SILENCIO_DB
	play3d("%s/step" % material_class(mat), pos, db, 0.1, 26.0, PRI_LOW)


func jump(mat: int) -> void:
	play2d("%s/jump" % material_class(mat), -8.0, 0.05, PRI_MID)


func land(mat: int, hard: bool) -> void:
	play2d("%s/land" % material_class(mat), -2.0 if hard else -8.0, 0.05, PRI_MID)
	if hard:
		bf2d("yo/caida_baja", -6.0, PRI_MID)


## CADA ARMA SUENA A ELLA. Solo hay cinco familias de disparo grabadas (Teardown: gun, rifle, shotgun,
## launcher, tankgun, y el silenciado), asi que la identidad sale de mezclarlas: el cuerpo del tiro, su
## TONO (mas grave = mas calibre), su volumen, y una segunda capa que le da el caracter: el retumbe de la
## 7,62, el latigazo del .44, el golpe seco del de precision, los tiros de fusil de BF.
##   arma -> [clave, tono, db, capa, tono capa, db capa]   (capa "" = sin capa; "bf/..." = de Battlefield)
const PERFIL_ARMA := {
	"carabina_556":    ["tools/rifle", 1.08, 0.0, "bf/gadget/senuelo", 1.05, -9.0],
	"fusil_762":       ["tools/rifle", 0.86, 1.5, "tools/tankgun", 1.45, -11.0],
	"fusil_bullpup":   ["silenced", 1.0, 0.0, "", 1.0, 0.0],
	"smg_9mm":         ["tools/gun", 1.04, -1.0, "bf/gadget/senuelo", 1.25, -14.0],
	"smg_compacta":    ["tools/gun", 1.24, -3.0, "", 1.0, 0.0],
	"pdw_57":          ["tools/gun", 1.13, -2.0, "tools/rifle", 1.35, -12.0],
	"escopeta_bomba":  ["tools/shotgun", 0.90, 1.0, "tools/tankgun", 1.7, -14.0],
	"escopeta_auto":   ["tools/shotgun", 1.08, -1.0, "", 1.0, 0.0],
	"rifle_precision": ["tools/rifle", 0.76, 2.0, "tools/tankgun", 1.15, -7.0],
	"pistola_9":       ["tools/gun", 1.30, -3.0, "", 1.0, 0.0],
	"pistola_45":      ["tools/gun", 0.96, -1.0, "tools/shotgun", 1.6, -16.0],
	"revolver_44":     ["tools/tankgun", 1.65, -3.0, "tools/gun", 0.80, -5.0],
	"bazooka_rpg":     ["tools/launcher", 0.94, 0.0, "bf/proyectil/cohete_sale", 1.0, -2.0],
	"bazooka_at4":     ["tools/launcher", 1.10, 0.0, "bf/proyectil/cohete_sale", 1.12, -4.0],
}
## Por familia, para lo que no traiga arma concreta (armas nuevas sin perfil).
const PERFIL_FAMILIA := {
	"rifle": ["tools/rifle", 1.0, 0.0, "", 1.0, 0.0], "shotgun": ["tools/shotgun", 1.0, 0.0, "", 1.0, 0.0],
	"rocket": ["tools/launcher", 1.0, 0.0, "bf/proyectil/cohete_sale", 1.0, -2.0],
	"pistol": ["tools/gun", 1.15, -2.0, "", 1.0, 0.0], "smg": ["tools/gun", 1.0, 0.0, "", 1.0, 0.0],
	"sniper": ["tools/rifle", 0.8, 2.0, "tools/tankgun", 1.15, -7.0], "silenced": ["silenced", 1.0, 0.0, "", 1.0, 0.0],
}
## Los bots no llevan arma de la armeria: cada uno se queda con uno de estos al nacer (enemy.gd).
const ARMAS_BOT := ["carabina_556", "fusil_762", "smg_9mm", "bot_sks", "carabina_556", "fusil_762", "bot_sks"]

## DISPAROS DE VERDAD (godot/sounds/armas, tools/importar_disparos.py): grabaciones de armas reales de The Free
## Firearm Sound Library (CC0, se puede publicar). Cada arma tiene su toma de CERCA y la de LEJOS (media
## distancia: el estampido sin el chasquido mecanico). Si el arma tiene carpeta, manda sobre la mezcla.
const DISPARO_LEJOS := 35.0     ## m: a partir de aqui suena la toma de lejos
## LAS GRABACIONES SOLAS SONABAN TODAS IGUAL. La libreria grabo cada arma con el mismo microfono a la misma
## distancia al aire libre: asi, un disparo real es un chasquido de ~20 ms y una 9 mm y un AK-47 se separan
## menos de 1 kHz (medido). Encima se normalizaron todas al mismo pico, y lo que de verdad distingue una .22
## de un .30-06 es lo FUERTE que suena. Aqui se devuelve eso, como hace cualquier shooter:
##   arma -> [db de la grabacion, tono de la grabacion, db de la capa de cuerpo (la mezcla de PERFIL_ARMA)]
## El cuerpo es el que pone el caracter: el retumbe de la 7,62, la escopeta, el estampido del revolver.
const CALIBRE := {
	"pistola_9":       [-9.0, 1.14, -12.0],
	"pdw_57":          [-8.0, 1.12, -10.0],
	"smg_compacta":    [-8.0, 1.10, -9.0],
	"smg_9mm":         [-6.0, 1.04, -8.0],
	"pistola_45":      [-5.0, 0.94, -7.0],
	"carabina_556":    [-3.0, 1.00, -6.0],
	"bot_sks":         [-2.0, 0.96, -6.0],
	"revolver_44":     [-1.0, 0.84, -4.0],
	"fusil_762":       [-1.0, 0.90, -4.0],
	"escopeta_auto":   [0.0, 0.92, -2.0],
	"escopeta_bomba":  [1.0, 0.84, -1.0],
	"bot_palanca":     [0.0, 0.90, -5.0],
	"bot_cerrojo":     [1.0, 0.86, -4.0],
	"rifle_precision": [2.0, 0.80, -2.0],
}
## ¿EXISTE ESA CARPETA DE SONIDOS? Una vez por carpeta (2026-10-01, medido con bots: `_disparo_real` preguntaba al
## disco en CADA disparo de cada bot si existia la carpeta de su arma, y alguna de esas consultas tardaba 117 ms).
var _carpetas := {}

func _hay_carpeta(ruta: String) -> bool:
	if not _carpetas.has(ruta):
		_carpetas[ruta] = DirAccess.dir_exists_absolute(ruta)
	return bool(_carpetas[ruta])


## Las carpetas de sonido de TODAS las armas, miradas en la carga: la primera consulta al disco de cada una costaba
## hasta 120 ms en pleno tiroteo (el primer disparo de cada arma en la partida).
func precalentar_carpetas_armas(ids: Array) -> void:
	for i in ids:
		var id := String(i)
		if id == "":
			continue
		_hay_carpeta("res://sounds/l4d2/armas/" + id)
		_hay_carpeta("res://sounds/armas/" + id)


func _disparo_real(arma: String, lejos: bool) -> String:
	# LEFT 4 DEAD 2 PRIMERO (tools/importar_l4d2.py, TEMPORAL con derechos): disparos hechos para juego, uno
	# distinto por arma. Borrando godot/sounds/l4d2 se vuelve solo a las grabaciones CC0 de abajo.
	if arma != "" and not sin_bf and _hay_carpeta("res://sounds/l4d2/armas/" + arma) \
			and not _variants("l4d2/armas/%s/golpe" % arma).is_empty():
		return "l4d2/armas/%s/golpe" % arma
	if arma == "" or not _hay_carpeta("res://sounds/armas/" + arma):
		return ""        # sin grabacion (el bullpup silenciado, los lanzacohetes): la mezcla de siempre
	# GOLPE + COLA (tools/importar_disparos.py, la tecnica de hard-lines): de cerca suena solo el golpe seco,
	# y la cola va aparte (_cola_disparo). Si el arma no trae golpe, la toma de cerca entera.
	if not lejos and not _variants("armas/%s/golpe" % arma).is_empty():
		return "armas/%s/golpe" % arma
	var k := "armas/%s/%s" % [arma, "lejos" if lejos else "cerca"]
	if not _variants(k).is_empty():
		return k
	if lejos:
		return _disparo_real(arma, false)
	return ""

## LA COLA DEL DISPARO: el eco del campo, de la toma de lejos sin sus primeros 90 ms. Se aplaza un poco y
## cada disparo nuevo del mismo tirador la vuelve a aplazar: en rafaga solo suena tras el ULTIMO tiro,
## como se oye de verdad (el eco de cada bala se funde en uno), y el tiro suelto suena entero.
var _colas: Dictionary = {}    ## "arma|2d" o "arma|x,z" -> [cuando, arma, pos, 2d, db, tono]
const COLA_ESPERA := 0.13

func _cola_disparo(arma: String, pos: Vector3, en_2d: bool, db: float, tono: float) -> void:
	if _variants("armas/%s/cola" % arma).is_empty():
		return
	var id := arma + ("|2d" if en_2d else "|%d,%d" % [int(pos.x / 4.0), int(pos.z / 4.0)])
	_colas[id] = [Time.get_ticks_msec() * 0.001 + COLA_ESPERA, arma, pos, en_2d, db, tono]


func _colas_tick() -> void:
	if _colas.is_empty():
		return
	var ahora: float = Time.get_ticks_msec() * 0.001
	for id in _colas.keys():
		var c: Array = _colas[id]
		if ahora < float(c[0]):
			continue
		_colas.erase(id)
		var k := "armas/%s/cola" % String(c[1])
		if bool(c[3]):
			play2d(k, float(c[4]) - 2.0, 0.04, PRI_MID, float(c[5]))
		else:
			play3d(k, c[2], 4.0 + float(c[4]) - 2.0, 0.04, 220.0, PRI_LOW, float(c[5]))


## Disparo del jugador (2D) o de un bot (3D). `kind`: la familia ("rifle", "smg"...); `arma`: el id
## concreto ("fusil_762"), que es lo que decide el sonido cuando lo hay.
func gunshot(kind: String, pos: Vector3, first_person: bool, arma: String = "") -> void:
	var pf: Array = PERFIL_ARMA.get(arma, PERFIL_FAMILIA.get(kind, PERFIL_FAMILIA["smg"]))
	var key: String = pf[0]
	var tono: float = pf[1]
	var capa: String = pf[3]
	if sin_bf and capa.begins_with("bf/"):
		capa = ""
	# LA GRABACION DE VERDAD, si el arma la tiene, con su volumen y tono de calibre, y DEBAJO el cuerpo de
	# la mezcla (su clave de Teardown con su tono), que es lo que la distingue de las demas (ver CALIBRE)
	var _tgs := Time.get_ticks_usec()
	var real := _disparo_real(arma, not first_person and _listener_dist(pos) > DISPARO_LEJOS)
	Prof.add("au.gs.real", Time.get_ticks_usec() - _tgs)
	if real.begins_with("l4d2/"):
		# ya viene mezclado para juego, con su cuerpo y su cola: tal cual, sin capas encima
		key = real
		tono = 1.0
		capa = ""
		pf = [real, 1.0, -3.0, "", 1.0, 0.0]
		real = ""
	if real != "":
		var cal: Array = CALIBRE.get(arma, [-4.0, 1.0, -8.0])
		if first_person:
			play2d(key, float(cal[2]), 0.04, PRI_HIGH, tono)
		else:
			play3d(key, pos, 4.0 + float(cal[2]), 0.04, 220.0, PRI_MID, tono)
		key = real
		tono = float(cal[1])
		pf = [real, tono, float(cal[0]), capa, pf[4], float(pf[5]) - 3.0]
		if real.ends_with("/golpe"):
			_cola_disparo(arma, pos, first_person, float(cal[0]), tono)
	if first_person:
		play2d(key, float(pf[2]), 0.03, PRI_HIGH, tono)
		if capa != "":
			play2d(capa, float(pf[5]), 0.04, PRI_HIGH, float(pf[4]))
		_eco_disparo(key, pos)     # tu propio tiro tambien rebota en las paredes
		return
	play3d(key, pos, 4.0 + float(pf[2]), 0.04, 220.0, PRI_HIGH, tono)
	if capa != "":
		play3d(capa, pos, 4.0 + float(pf[5]), 0.04, 150.0, PRI_MID, float(pf[4]))
	# COLA LEJANA: de cerca el tiro es seco; de lejos lo que oyes es el estampido rodando entre los
	# edificios. Se lanza una segunda capa mas floja y retrasada. (El retardo por velocidad del
	# sonido ya lo hace play3d; esto es lo que llega DESPUES del frente.)
	# Antes empezaba a los 45 m y era una sola capa floja: se perdia. Ahora arranca a 25 m, son dos
	# capas, y la segunda llega mas tarde y mas apagada, que es como suena de verdad un tiro lejano
	# en una ciudad: el golpe, el rebote cercano y el retumbe.
	var d := _listener_dist(pos)
	# la cola lejana, tambien racionada y por el mismo motivo: en una rafaga a cincuenta metros eran
	# otras veinte voces por segundo que no aportaban nada porque se solapaban entre ellas
	var ahora2: float = Time.get_ticks_msec() * 0.001
	if d > 25.0 and ahora2 >= _cola_t and _pending.size() <= 20:
		_cola_t = ahora2 + 0.22
		var t0: float = ahora2 + d / SPEED_OF_SOUND
		_pending.append([t0 + 0.13, key, pos, -6.0 - d * 0.012, 0.30, 400.0, PRI_LOW])
		if d > 60.0:
			_pending.append([t0 + 0.34, key, pos, -13.0 - d * 0.010, 0.45, 500.0, PRI_LOW])
	_eco_disparo(key, pos)


## EL ECO DE ESTAR DENTRO. La reverberacion del bus pone la "cola" -esa nube que se apaga- pero lo
## que el oido reconoce como ECO son GOLPES sueltos: el disparo rebotando en la pared de enfrente y
## volviendo. Por eso van aparte, dos repeticiones cortas y apagadas, y solo si estas encerrado.
##
## Se usa la misma cola de sonidos retrasados que ya existe para la velocidad del sonido, asi que no
## hace falta ni un temporizador nuevo.
var _eco_t := 0.0              ## cuando se puede volver a echar eco (ver abajo)
var _cola_t := 0.0             ## lo mismo para la cola de los disparos lejanos
var _tiros_recientes := 0.0    ## cuenta con olvido: cuantos tiros van en el ultimo medio segundo
var _tiros_t := 0.0


func _eco_disparo(key: String, pos: Vector3) -> void:
	if enclosure < 0.30:
		return                     # a cielo abierto no hay de donde rebote
	# UN ECO CADA TANTO, NO UNO POR BALA. Aqui estaba el destrozo: cada tiro metia tres sonidos -el
	# directo y dos rebotes- y con un fusil a diez tiros por segundo son treinta voces por segundo
	# peleandose por el mismo grupo de altavoces. Se robaban la voz unas a otras (de ahi los cortes)
	# y al sumarse todas saturaban el bus.
	#
	# Y ademas es INNECESARIO: una sala no responde a cada bala por separado, responde al ruido. Con
	# un rebote cada 0,14 s la rafaga suena igual de reverberante y cuesta la sexta parte.
	var t: float = Time.get_ticks_msec() * 0.001
	if t < _eco_t:
		return
	# EN FUEGO SOSTENIDO, NADA DE REBOTES. Con una rafaga larga los rebotes no se distinguen -se
	# solapan entre ellos y con la reverberacion del bus- pero suman energia igual. Se cuentan los
	# tiros del ultimo medio segundo y a partir de seis se dejan de echar: la cola del bus ya hace
	# el trabajo y el sonido queda limpio.
	_tiros_recientes = _tiros_recientes * exp(-2.0 * maxf(t - _tiros_t, 0.0)) + 1.0
	_tiros_t = t
	if _tiros_recientes > 6.0:
		return
	# LA ESPERA, DE 0,14 A 0,30 s. Ya habia una -no estaba sin freno- pero para una metralleta a
	# quince tiros por segundo, 0,14 seguian siendo siete rebotes por segundo, y siete rebotes con su
	# cola son mucha energia en el bus. A 0,30 son tres como maximo.
	#
	# Esto es un cinturon de seguridad, no el arreglo: la causa del sonido sucio era que la suma se
	# pasaba de 0 dB y recortaba, y eso lo cierra el limitador del bus. Pero cuanto menos haya que
	# limitar, mas limpio queda, asi que las dos cosas van juntas.
	_eco_t = t + 0.30
	# y si la cola de sonidos retrasados ya va cargada, no se le echa mas leña
	if _pending.size() > 20:
		return
	var k: float = clampf((enclosure - 0.30) / 0.70, 0.0, 1.0)
	var ahora: float = Time.get_ticks_msec() * 0.001
	# el primer rebote llega antes en un cuarto pequeno y mas tarde en una nave grande
	var t1: float = lerpf(0.055, 0.13, k)
	_pending.append([ahora + t1, key, pos, -10.0 - 6.0 * (1.0 - k), 0.20, 90.0, PRI_LOW])
	_pending.append([ahora + t1 * 2.3, key, pos, -18.0 - 6.0 * (1.0 - k), 0.35, 90.0, PRI_LOW])


## Marcador de acierto: el "tin" de confirmacion. Distinto para cuerpo, cabeza y muerte: es el 80 %
## de la satisfaccion de acertar.
func hit_marker(kind: String) -> void:
	if kind == "head":
		play2d("clickup", -3.0, 0.0, PRI_HIGH)
	elif kind == "kill":
		play2d("clickup", 0.0, 0.0, PRI_HIGH)
		play2d("clickdown", -2.0, 0.0, PRI_HIGH)
		ui("baja", -8.0)
	else:
		play2d("clickdown", -7.0, 0.02, PRI_MID)


# ---------------------------------------------------------------------------
# SORDERA. Una explosion cerca te deja sordo unos segundos: todo suena amortiguado (filtro paso
# bajo sobre el bus maestro) y queda un pitido agudo. Es de los efectos que mas cambian la
# sensacion de un juego por lo poco que cuestan.
# ---------------------------------------------------------------------------
var _deaf_t := 0.0
var _deaf_max := 0.0
var _lowpass: AudioEffectLowPassFilter = null
var _lp_idx := -1
var _tinnitus: AudioStreamPlayer = null

func _setup_deafness() -> void:
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(0, _lowpass)
	_lp_idx = AudioServer.get_bus_effect_count(0) - 1
	AudioServer.set_bus_effect_enabled(0, _lp_idx, false)
	_tinnitus = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.2
	_tinnitus.stream = gen
	_tinnitus.bus = "Master"
	_tinnitus.volume_db = -80.0
	add_child(_tinnitus)
	_tono_tabla.resize(22050)
	for i in 22050:
		var ph := TAU * 3900.0 * float(i + 1) / 22050.0
		var v: float = sin(ph) * 0.35 + sin(ph * 1.5) * 0.1
		_tono_tabla[i] = Vector2(v, v)


## `fuerza` de 0 a 1: 1 es una explosion en la cara.
func deafen(fuerza: float) -> void:
	if _lowpass == null:
		return
	var _td := Time.get_ticks_usec()
	if fuerza > 0.45 and _deaf_t <= 0.5:
		bf2d("yo/explosion_fuerte" if fuerza > 0.8 else "yo/explosion_cerca", -2.0, PRI_TOP)
		bf2d("yo/metralla", -6.0, PRI_HIGH)
		if fuerza > 0.6:
			bf2d("yo/explosion_pitido", -10.0, PRI_HIGH)
	Prof.add("au.deaf.sonidos", Time.get_ticks_usec() - _td); _td = Time.get_ticks_usec()
	_deaf_max = maxf(_deaf_max, clampf(fuerza, 0.0, 1.0))
	_deaf_t = maxf(_deaf_t, 1.0 + 4.0 * _deaf_max)
	AudioServer.set_bus_effect_enabled(0, _lp_idx, true)
	Prof.add("au.deaf.filtro", Time.get_ticks_usec() - _td); _td = Time.get_ticks_usec()
	if not _tinnitus.playing:
		_tinnitus.play()
	Prof.add("au.deaf.pitido", Time.get_ticks_usec() - _td)


## Corta la sordera de golpe. Se usa al morir: si la explosion te mata no hay pitido que valga, y
## si no se cortara te acompanaria ya muerto y al reaparecer.
func stop_deafness() -> void:
	if _lowpass == null:
		return
	_deaf_t = 0.0
	_deaf_max = 0.0
	_lowpass.cutoff_hz = 20000.0
	if _lp_idx >= 0:
		AudioServer.set_bus_effect_enabled(0, _lp_idx, false)
	if _tinnitus and _tinnitus.playing:
		_tinnitus.stop()


func _update_deafness(dt: float) -> void:
	if _deaf_t <= 0.0:
		return
	_deaf_t -= dt
	var k: float = clampf(_deaf_t / maxf(0.01, 1.0 + 4.0 * _deaf_max), 0.0, 1.0)
	# de 400 Hz (sordo) a 20 kHz (normal), con curva suave
	_lowpass.cutoff_hz = lerpf(20000.0, 380.0, k * k)
	_tinnitus.volume_db = lerpf(-80.0, -16.0 - 10.0 * (1.0 - _deaf_max), k)
	# el pitido: seno de 3,9 kHz generado a mano
	var pb := _tinnitus.get_stream_playback()
	if pb:
		var n: int = pb.get_frames_available()
		if n > 0:
			if _tono_tabla.is_empty() or _pitido_antes:
				for i in n:
					_tone_ph += TAU * 3900.0 / 22050.0
					var v: float = sin(_tone_ph) * 0.35 + sin(_tone_ph * 1.5) * 0.1
					pb.push_frame(Vector2(v, v))
			else:
				# de la tabla, por tramos: el mismo tono sin un sin() por muestra en GDScript
				while n > 0:
					var m: int = mini(n, _tono_tabla.size() - _tono_i)
					pb.push_buffer(_tono_tabla.slice(_tono_i, _tono_i + m))
					_tono_i = (_tono_i + m) % _tono_tabla.size()
					n -= m
	if _deaf_t <= 0.0:
		_deaf_t = 0.0
		_deaf_max = 0.0
		_lowpass.cutoff_hz = 20000.0
		AudioServer.set_bus_effect_enabled(0, _lp_idx, false)
		_tinnitus.stop()

var _tone_ph := 0.0
## EL PITIDO EN TABLA (2026-10-16, medido en la cafeteria: al empezar la sordera el bufer de 0,2 s esta vacio y se
## rellenaban 4.410 muestras con dos sin() cada una en GDScript, 6-11 ms en un fotograma). 3.900 y 5.850 Hz dan un
## numero entero de vueltas en 22.050 muestras, asi que un segundo de tono se repite sin costura: se calcula al
## arrancar y se copia. Es la misma onda (sin la deriva de un `_tone_ph` que crece sin parar). --pitidoantes = antes.
var _tono_tabla := PackedVector2Array()
var _tono_i := 0
var _pitido_antes: bool = "--pitidoantes" in OS.get_cmdline_user_args()


## BAJO EL AGUA (agua.gd): todo suena ahogado mientras la cabeza esta hundida. Es un paso bajo aparte
## del de la sordera y no el mismo: si una explosion te deja sordo buceando, al salir la sordera tiene
## que seguir su curva y no cortarse de golpe porque el agua haya soltado el filtro.
var _lp_agua: AudioEffectLowPassFilter = null
var _lp_agua_idx := -1

func submarino(on: bool) -> void:
	if _lp_agua == null:
		if not on:
			return
		_lp_agua = AudioEffectLowPassFilter.new()
		_lp_agua.cutoff_hz = 650.0
		AudioServer.add_bus_effect(0, _lp_agua)
		_lp_agua_idx = AudioServer.get_bus_effect_count(0) - 1
	AudioServer.set_bus_effect_enabled(0, _lp_agua_idx, on)
	# BF: el golpe de meter la cabeza y sacarla, y el rumor de debajo del agua mientras dura
	bf2d("yo/bajo_agua_entra" if on else "yo/bajo_agua_sale", -6.0, PRI_MID)
	bucle("bajo_agua", "yo/bajo_agua", on, -10.0)


## EQUIPAR UN ARMA en la armeria. `cambio` es true cuando de verdad sustituyes lo que llevabas:
## suena el manoteo de guardar una y sacar otra. Volviendo a poner la misma solo hace clic.
func equip_sound(cambio: bool) -> void:
	if cambio:
		ui("equipar_principal", -6.0)
	play2d("clickdown", -4.0, 0.02, PRI_HIGH)
	if cambio:
		play2d("tools/dryfire", -6.0, 0.05, PRI_HIGH)


func dry_fire() -> void:
	play2d("tools/dryfire", -4.0, 0.0, PRI_HIGH)


## Silbido de una bala enemiga que pasa cerca.
func bullet_pass() -> void:
	play2d("bullet-pass", -6.0, 0.05, PRI_MID)


## UNA BALA QUE TE PASA ROZANDO: el aire rasgandose junto a la oreja. Va en 3D y EN EL PUNTO por
## donde ha pasado, no en la cabeza, para que se oiga de que lado ha ido y por encima o por debajo.
## Cuanto mas cerca, mas fuerte y mas agudo el chasquido; a partir de un par de metros no se oye.
##
## LAS BALAS DE BF, SEGUN QUIEN DISPARA Y DESDE DONDE (`arma` = id o familia del tirador, `lejos` = metros
## del tirador a ti):
##   * de precision: su chasquido seco, mas fuerte, y su zumbido propio
##   * escopeta: el enjambre de perdigones
##   * el resto: chasquido de fusil (dentro de un edificio, el de interior, que retumba)
##   * de lejos (mas de 60 m) el chasquido es el lejano: llega antes la bala que el tiro
##   * con la cabeza bajo el agua, el zumbido ahogado y nada mas
func bullet_whiz(pos: Vector3, dist: float, arma: String = "", lejos: float = 0.0) -> void:
	var k: float = clampf(1.0 - dist / WHIZ_DIST, 0.0, 1.0)
	if _lp_agua != null and _lp_agua_idx >= 0 and AudioServer.is_bus_effect_enabled(0, _lp_agua_idx):
		bf3d("bala/zumbido_agua", pos, -10.0 + 8.0 * k, 12.0, PRI_MID, 0.08)
		return
	play3d("bullet-pass", pos, -17.0 + 15.0 * k, 0.10, 14.0, PRI_MID)
	var precision: bool = arma == "sniper" or arma == "rifle_precision"
	var escopeta: bool = arma == "shotgun" or arma.begins_with("escopeta")
	var crack := "bala/chasquido"
	if precision:
		crack = "bala/chasquido_francotirador_lejos" if lejos > 60.0 else "bala/chasquido_francotirador"
	elif lejos > 60.0:
		crack = "bala/chasquido_lejos"
	elif enclosure > 0.5:
		crack = "bala/chasquido_interior"
	if not escopeta:
		bf3d(crack, pos, (-10.0 if precision else -14.0) + 10.0 * k, 20.0, PRI_MID, 0.08)
	if escopeta:
		bf3d("bala/zumbido_perdigon", pos, -10.0 + 8.0 * k, 14.0, PRI_MID, 0.08)
	elif precision:
		bf3d("bala/zumbido_francotirador", pos, -8.0 + 6.0 * k, 16.0, PRI_MID, 0.06)
	elif k > 0.5:
		bf3d("bala/zumbido_lejos" if lejos > 60.0 else "bala/zumbido", pos, -12.0, 12.0, PRI_LOW, 0.08)


const WHIZ_DIST := 2.6      ## m: mas lejos que esto, la bala ya no se oye pasar


func bullet_hit_player() -> void:
	play2d("bullet-hit", -2.0, 0.05, PRI_HIGH)


func throw_sound(pos: Vector3) -> void:
	play3d("throw/s", pos, -4.0, 0.08, 40.0, PRI_MID)


## Sonido suelto (clave de la biblioteca o ruta res:// a un .ogg propio), 3D.
func play_file(path: String, pos: Vector3, db: float = 0.0, pri: int = PRI_MID) -> void:
	if not _lib.has(path):
		var st: AudioStream = _load_ogg(path)
		_lib[path] = [st] if st else []
	_play3d_now(path, pos, db, 0.03, 60.0, pri)


## EL AMBIENTE DE CADA MAPA. Antes todos sonaban a viento, incluso dust2, que es un pueblo con
## calles: el viento pega arriba, no a nivel del suelo. Cada mapa lleva ahora el suyo.
const AMBIENTE_MAPA := {
	# DUST2, EN SILENCIO. Aqui estuvo el ventarron todo este tiempo: `field` es una grabacion de campo
	# abierto y es basicamente viento. Comprobado quitando el ambiente: sin el, el ruido se acaba.
	# Un mapa seco y cerrado entre muros no tiene por que sonar a nada de fondo; los tiros, los pasos
	# y el eco ya lo llenan. Cadena vacia = sin ambiente (lo entiende `start_ambience`).
	"dust": "",
	"nuke": "ambience/outdoor/field",
	"hangar": "ambience/outdoor/field",
	"city": "ambience/outdoor/night",      # rumor de ciudad
}


# QUE SUENA DE FONDO, ELEGIBLE EN MARCHA. Aqui no puedo escuchar los archivos, asi que en vez de ir
# cambiando el clip a ciegas y preguntando, se pueden probar todos desde el menu del juego. El primer
# valor es SILENCIO a proposito: es el que sirve de diagnostico. Si quitando el ambiente se acaba el
# ruido de viento, el viento ES el clip de fondo; si sigue sonando, viene de otro sitio.
const AMBIENTE_LISTA := ["", "field", "night", "forest", "lake", "lake_birds", "ocean", "winter"]
var ambiente_elegido := -1     ## -1 = el que decida el mapa; si no, indice en AMBIENTE_LISTA


## Devuelve el nombre de lo que esta sonando, para poder enseniarlo en el menu.
func ambiente_nombre() -> String:
	if ambiente_elegido < 0:
		return "MAPA"
	var n: String = AMBIENTE_LISTA[ambiente_elegido]
	return "SILENCIO" if n == "" else n.to_upper()


## Rota al siguiente y lo pone al momento, sin recargar el mapa.
func ambiente_siguiente(mapa: String) -> String:
	ambiente_elegido += 1
	if ambiente_elegido >= AMBIENTE_LISTA.size():
		ambiente_elegido = -1
	start_ambience(mapa)
	return ambiente_nombre()


## MUSICA DEL LOBBY (2026-09-18; tema nuevo el 2026-09-28; el 2026-09-29 "ambiente", el que trajo el usuario, y el
## anterior borrado para no ocupar sitio): godot/musica/lobby/ambiente.mp3 en bucle al volumen de Settings.music_volume (ajuste "Musica"). Suena en el lobby y
## sigue durante la pantalla de carga; se apaga cuando la partida esta lista (main._on_world_ready).
var _musica_lobby: AudioStreamPlayer = null
func set_music_volume(v: float) -> void:
	if _musica_lobby != null:
		_musica_lobby.volume_db = linear_to_db(maxf(0.0001, v))
func musica_lobby(on: bool) -> void:
	if on:
		if _musica_lobby != null and _musica_lobby.playing:
			return
		if _musica_lobby == null:
			_musica_lobby = AudioStreamPlayer.new()
			_musica_lobby.name = "MusicaLobby"
			_musica_lobby.bus = "Master"
			add_child(_musica_lobby)
		var st = load("res://musica/lobby/ambiente.mp3")
		if st == null:
			return
		if st is AudioStreamMP3:
			(st as AudioStreamMP3).loop = true
		_musica_lobby.stream = st
		_musica_lobby.volume_db = linear_to_db(maxf(0.0001, Settings.music_volume))
		_musica_lobby.play()
	elif _musica_lobby != null and _musica_lobby.playing:
		var tw := _musica_lobby.create_tween()
		tw.tween_property(_musica_lobby, "volume_db", -60.0, 1.2)
		tw.tween_callback(_musica_lobby.stop)


## EL AMBIENTE DE BATTLEFIELD DE CADA MAPA: dos o tres bucles de fondo (encima del de Teardown, o solos
## si el mapa pide silencio) y unos sueltos que salen de vez en cuando cerca, en una direccion al azar.
##   mapa -> [[bucle, db], ...], [[suelto, db], ...]
const AMB_BF := {
	"dust": [[["amb/bucle_viento", -18.0], ["amb/bucle_viento_metal", -22.0]],
		[["amb/pajaros", -16.0], ["amb/lata", -14.0], ["amb/cantos_lejos", -18.0], ["amb/puerta_lejos", -16.0]]],
	"monaco": [[["amb/bucle_ciudad", -20.0], ["amb/bucle_alarma_coche", -30.0]],
		[["amb/sirena", -14.0], ["amb/claxon", -16.0], ["amb/pajaros", -18.0], ["amb/radio", -18.0]]],
	"city": [[["amb/bucle_ciudad", -20.0], ["amb/bucle_policia", -28.0]],
		[["amb/sirena", -14.0], ["amb/claxon", -16.0], ["amb/radio", -18.0]]],
	"isla": [[["amb/bucle_rio", -18.0], ["amb/bucle_grillos", -22.0]],
		[["amb/pajaros", -12.0], ["amb/insectos", -18.0]]],
	"nuke": [[["amb/bucle_tension", -24.0], ["amb/bucle_viento_metal", -20.0]],
		[["amb/edificio_gime", -14.0], ["amb/puerta_lejos", -16.0], ["amb/lata", -16.0]]],
	"hangar": [[["amb/bucle_viento_metal", -18.0], ["amb/bucle_tension", -24.0]],
		[["amb/edificio_gime", -14.0], ["amb/pajaros", -18.0]]],
	"pve_cuarentena": [[["amb/bucle_goteo", -20.0], ["amb/bucle_alarma_fuego", -30.0], ["amb/bucle_fuego", -26.0]],
		[["amb/raton", -18.0], ["amb/edificio_gime", -14.0], ["amb/sirena", -18.0], ["amb/megafono", -18.0]]],
	"muros": [[["amb/bucle_viento", -20.0]], [["amb/pajaros", -16.0]]],
	"tutorial": [[["amb/bucle_viento", -22.0]], [["amb/pajaros", -14.0]]],
}
var _amb_bf: Array[AudioStreamPlayer] = []
var _amb_sueltos: Array = []
var _amb_t := 8.0

func _ambiente_bf(mapa: String) -> void:
	for p in _amb_bf:
		p.stop()
	_amb_sueltos = []
	if sin_bf:
		return
	var conf: Array = []
	for k in AMB_BF.keys():
		if mapa.begins_with(String(k)):
			conf = AMB_BF[k]
	if conf.is_empty():
		return
	var i := 0
	for b in conf[0]:
		if i >= _amb_bf.size():
			var np := AudioStreamPlayer.new()
			np.bus = "World"
			add_child(np)
			_amb_bf.append(np)
		var st := _pick("bf/" + String(b[0]))
		if st == null:
			continue
		if st is AudioStreamOggVorbis:
			(st as AudioStreamOggVorbis).loop = true
		_amb_bf[i].stream = st
		_amb_bf[i].volume_db = float(b[1]) + master_db
		_amb_bf[i].play()
		i += 1
	_amb_sueltos = conf[1]
	_amb_t = randf_range(6.0, 14.0)
	print("[ambiente] BF %s: %d bucles, %d sueltos" % [mapa, i, _amb_sueltos.size()])


func _amb_tick(dt: float) -> void:
	if _amb_sueltos.is_empty() or not guerra:
		return
	_amb_t -= dt
	if _amb_t > 0.0:
		return
	_amb_t = randf_range(8.0, 20.0)
	var o := _listener_pos()
	if o == Vector3.INF:
		return
	var e: Array = _amb_sueltos[randi() % _amb_sueltos.size()]
	var a := randf() * TAU
	var d := randf_range(15.0, 45.0)
	_guerra_suelta(String(e[0]), o + Vector3(cos(a) * d, randf_range(0.0, 8.0), sin(a) * d), float(e[1]) + 8.0)


func start_ambience(mapa: String = "") -> void:
	_ambiente_bf(mapa)
	# el viento de las alturas es de OTRO mapa: cambiar de mapa lo apaga (ver wind_height)
	if _viento and _viento.playing:
		_viento.stop()
	var clave := "ambience/outdoor/field"
	for k in AMBIENTE_MAPA.keys():
		if mapa.begins_with(String(k)):
			clave = String(AMBIENTE_MAPA[k])
	# el mapa puede pedir silencio, y entonces manda el silencio
	if clave == "" and ambiente_elegido < 0:
		_ambience.stop()
		print("[ambiente] %s -> SILENCIO (lo pide el mapa)" % mapa)
		return
	if ambiente_elegido >= 0:
		var elegido: String = AMBIENTE_LISTA[ambiente_elegido]
		if elegido == "":
			_ambience.stop()
			print("[ambiente] %s -> SILENCIO" % mapa)
			return
		clave = "ambience/outdoor/" + elegido
	print("[ambiente] %s -> %s" % [mapa, clave])
	var st := _pick(clave)
	if st == null:
		return
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	_ambience.stream = st
	_ambience.volume_db = -14.0 + master_db
	_ambience.play()


# ---------------------------------------------------------------------------
# EL VIENTO DE LAS ALTURAS. No es el ambiente del mapa: es una capa aparte que solo se oye cuando
# estas ARRIBA, en lo alto de un edificio. A ras de calle no sopla; segun subes, entra y crece.
# Es de las cosas que mas venden la altura, mas incluso que mirar hacia abajo.
# ---------------------------------------------------------------------------
var _viento: AudioStreamPlayer = null
const VIENTO_DESDE := 18.0     ## m: por debajo de esta altura no se oye nada
const VIENTO_TOPE := 55.0      ## m: a partir de aqui ya sopla a tope


## `altura` en metros sobre el suelo del mapa. Llamalo cada frame: se encarga de encender, subir,
## bajar y apagar el viento por su cuenta.
func wind_height(altura: float) -> void:
	var k: float = clampf((altura - VIENTO_DESDE) / maxf(VIENTO_TOPE - VIENTO_DESDE, 1.0), 0.0, 1.0)
	if k <= 0.001:
		if _viento and _viento.playing:
			_viento.stop()
		return
	if _viento == null:
		_viento = AudioStreamPlayer.new()
		add_child(_viento)
	if not _viento.playing:
		var st := _pick("ambience/outdoor/wind")
		if st == null:
			return
		if st is AudioStreamOggVorbis:
			(st as AudioStreamOggVorbis).loop = true
		_viento.stream = st
		_viento.play()
	# de casi inaudible a claramente presente; nunca tapa al ambiente del mapa
	_viento.volume_db = lerpf(-34.0, -9.0, k) + master_db
	_viento.pitch_scale = lerpf(0.92, 1.06, k)


func stop_wind() -> void:
	if _viento and _viento.playing:
		_viento.stop()


func ambience_playing() -> bool:
	return _ambience != null and _ambience.playing


func stop_ambience() -> void:
	_ambience.stop()
	for p in _amb_bf:
		p.stop()
	_amb_sueltos = []
	guerra = false
	parar_bucles()


## Lluvia en bucle (rain_heavy / rain_light de Teardown). Va en su propio reproductor para que
## la ambientación de fondo siga sonando debajo.
## el volumen de la lluvia (2026-10-12, pedido: "que se escuche un poco mas el agua"): era -8 dB
## y otra vez mas (2026-10-15, pedido: "subi el volumen de la lluvia mas"): -4 -> +2 dB
const LLUVIA_DB := 2.0

var _rain_quiere := false
var _rain_fuerte := true

func start_rain(heavy: bool = true) -> void:
	_rain_quiere = true
	_rain_fuerte = heavy
	var st := _pick("ambience/outdoor/rain_heavy" if heavy else "ambience/outdoor/rain_light")
	if st == null:
		# AUN NO ESTA CARGADA (2026-10-14, bug: "a veces llueve y no se oye la lluvia, los truenos si"): en partida lo
		# frio se pide a un hilo y no suena esta vez; antes no se volvia a intentar nunca. Se reintenta cada 0,5 s.
		if is_inside_tree():
			get_tree().create_timer(0.5).timeout.connect(func():
				if _rain_quiere and (_rain == null or not _rain.playing):
					start_rain(_rain_fuerte))
		return
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	_rain.stream = st
	_rain.volume_db = LLUVIA_DB + master_db
	_rain.play()


## BAJO TECHO SE OYE DE FUERA. `k` de 0 (a la intemperie) a 1 (dentro del todo): la lluvia baja de
## volumen y se le comen los agudos, que es lo que hace una pared. Sin esto, metido en una casa la
## lluvia sonaba exactamente igual que en la calle y se perdia la sensacion de haberse guarecido.
var _rain_lp: AudioEffectLowPassFilter = null
var _rain_bus := -1

func rain_cover(k: float) -> void:
	if _rain == null:
		return
	var c: float = clampf(k, 0.0, 1.0)
	_rain.volume_db = lerpf(LLUVIA_DB, LLUVIA_DB - 14.0, c) + master_db
	# el filtro vive en un bus propio para no tocar el resto del sonido del juego
	if _rain_bus < 0:
		_rain_bus = AudioServer.get_bus_index("Lluvia")
		if _rain_bus < 0:
			_rain_bus = AudioServer.bus_count
			AudioServer.add_bus(_rain_bus)
			AudioServer.set_bus_name(_rain_bus, "Lluvia")
			AudioServer.set_bus_send(_rain_bus, "Master")
			_rain_lp = AudioEffectLowPassFilter.new()
			_rain_lp.cutoff_hz = 20000.0
			AudioServer.add_bus_effect(_rain_bus, _rain_lp)
		_rain.bus = "Lluvia"
	if _rain_lp:
		# de 20 kHz (fuera, con todo el chispeo) a 900 Hz (dentro, solo el rumor grave)
		_rain_lp.cutoff_hz = lerpf(20000.0, 900.0, c * c)


func stop_rain() -> void:
	_rain_quiere = false
	if _rain:
		_rain.stop()


# ===========================================================================
# LA CAPA DE BATTLEFIELD (godot/sounds/bf, tools/importar_sonidos_bf.py). AUDIO TEMPORAL CON
# DERECHOS: se quita antes de publicar. Todo lo de aqui aguanta que la carpeta no exista: una clave
# sin archivos no suena y ya esta, el juego sigue con lo de Teardown.
#
# Lo que pone:
# * el LOCUTOR (voz): inicio y fin de ronda, bomba armada/desactivada, fuera de zona, victoria...
# * la INTERFAZ (ui): clics de todos los botones del juego, cuentas atras, fin de ronda
# * lo que te pasa A TI (yo/...): balazos, chaleco, vida baja con latido, caidas, muerte
# * capas encima de lo de Teardown: derrumbes con crujido previo, grave de explosion, chasquido de bala
# * la GUERRA DE FONDO: tiroteos, artilleria, sirenas y edificios gimiendo lejos, por todo el mapa
# ===========================================================================
var sin_bf := "--sinbf" in OS.get_cmdline_user_args()      ## A/B: sin ninguna capa de Battlefield

## Sonido de Battlefield en 3D. `key` sin el "bf/" (p. ej. "destru/derrumbe").
func bf3d(key: String, pos: Vector3, db: float = 0.0, max_dist: float = 80.0, pri: int = PRI_MID, pitch_var: float = 0.04) -> void:
	if sin_bf:
		return
	play3d("bf/" + key, pos, db, pitch_var, max_dist, pri)


## Sonido de Battlefield en tu cabeza (2D, con el eco del sitio).
func bf2d(key: String, db: float = 0.0, pri: int = PRI_MID, pitch_var: float = 0.02) -> void:
	if sin_bf:
		return
	play2d("bf/" + key, db, pitch_var, pri)


# --- EL LOCUTOR ------------------------------------------------------------------------------------
## Un solo altavoz: dos frases a la vez no se entienden. Si ya esta hablando, la nueva solo entra si
## es mas importante (fin de partida > bomba > ronda > avisos); si no, se descarta. Va por Master y
## no por World: es la radio, no suena en la sala ni se ensordece con la reverberacion.
var _voz: AudioStreamPlayer = null
var _voz_pri := -1
var _voz_ultima: Dictionary = {}     ## clave -> cuando se dijo (no repetir la misma frase seguida)
const VOZ_DB := -3.0

func voz(evento: String, pri: int = 1, repetir_s: float = 8.0) -> void:
	if sin_bf or not enabled:
		return
	var ahora: float = Time.get_ticks_msec() * 0.001
	if ahora - float(_voz_ultima.get(evento, -1e9)) < repetir_s:
		return
	if _voz == null:
		_voz = AudioStreamPlayer.new()
		_voz.name = "Locutor"
		_voz.bus = "Master"
		add_child(_voz)
	if _voz.playing and pri <= _voz_pri:
		return
	var st := _pick("bf/voz/" + evento)
	if st == null:
		return
	_voz_ultima[evento] = ahora
	_voz_pri = pri
	_voz.stream = st
	_voz.volume_db = VOZ_DB + master_db
	_voz.play()


## La voz de la ronda segun quien haya ganado: `ganamos` desde el punto de vista de este jugador.
func voz_fin_ronda(ganamos: bool, por_objetivo: bool) -> void:
	ui("fin_ronda", -4.0)
	if por_objetivo:
		voz("ronda_ganada_obj" if ganamos else "ronda_perdida_obj", 2)
	else:
		voz("ronda_ganada" if ganamos else "ronda_perdida", 2)


func voz_fin_partida(ganamos: bool) -> void:
	parar_bucles()
	guerra = false
	ui("victoria" if ganamos else "derrota", -2.0)
	voz("victoria" if ganamos else "derrota", 3, 1.0)


# --- LA INTERFAZ -----------------------------------------------------------------------------------
var _ui_t := 0.0

func ui(key: String, db: float = -6.0) -> void:
	if sin_bf or not enabled or not is_inside_tree():
		return
	var st := _pick("bf/ui/" + key)
	if st == null:
		return
	# un reproductor por sonido de menu, que se borra al acabar: dos clics seguidos no se cortan
	var p := AudioStreamPlayer.new()
	p.bus = "Master"
	p.stream = st
	p.volume_db = db + master_db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## CADA BOTON DEL JUEGO SUENA sin tocar cada menu: al entrar un boton en el arbol se le enganchan el
## "pasar por encima" y el "pulsar". Asi el lobby, la armeria, los ajustes y el HUD suenan igual.
## Un boton con el meta "sin_sonido" se queda mudo (los que ya suenan por su cuenta).
func _enganchar_botones(n: Node) -> void:
	if sin_bf:
		return
	if n is BaseButton:
		var b := n as BaseButton
		if b.has_meta("sin_sonido") or b.has_meta("_bf_ui"):
			return
		b.set_meta("_bf_ui", true)
		b.mouse_entered.connect(_ui_pasar.bind(b))
		if b is CheckButton or b is CheckBox:
			b.toggled.connect(func(on: bool): ui("activar" if on else "desactivar", -8.0))
		else:
			b.pressed.connect(func(): ui("atras" if _es_atras(b) else "aceptar", -7.0))
	elif n is Slider and not n.has_meta("_bf_ui"):
		n.set_meta("_bf_ui", true)
		(n as Slider).drag_ended.connect(func(_c: bool): ui("deslizador", -10.0))


func _ui_pasar(b: BaseButton) -> void:
	if not is_instance_valid(b) or b.disabled:
		return
	var ahora: float = Time.get_ticks_msec() * 0.001
	if ahora - _ui_t < 0.06:
		return
	_ui_t = ahora
	ui("pasar", -14.0)


func _es_atras(b: BaseButton) -> bool:
	var t := ""
	if b is Button:
		t = (b as Button).text.to_upper()
	return t.contains("VOLVER") or t.contains("ATRAS") or t.contains("ATRÁS") or t.contains("CERRAR") \
		or t.contains("SALIR") or t.contains("CANCELAR") or t == "X" or t == "✕"


# --- BUCLES (2D) -----------------------------------------------------------------------------------
## Sonidos que duran mientras dura algo: el latido con la vida baja, el aviso de fuera de zona, el
## viento al caer del avion... `on` los enciende y apaga con un fundido corto.
var _bucles: Dictionary = {}     ## nombre -> AudioStreamPlayer
var _bucle_tw: Dictionary = {}   ## nombre -> Tween del fundido de salida

func bucle(nombre: String, key: String, on: bool, db: float = -6.0) -> void:
	var p: AudioStreamPlayer = _bucles.get(nombre)
	if not on:
		# se puede llamar cada cuadro: el fundido se lanza una sola vez
		if p and p.playing and not p.has_meta("apagando"):
			p.set_meta("apagando", true)
			var tw := p.create_tween()
			tw.tween_property(p, "volume_db", -60.0, 0.4)
			tw.tween_callback(func():
				p.stop()
				p.remove_meta("apagando"))
			_bucle_tw[nombre] = tw
		return
	if sin_bf or not enabled:
		return
	if p == null:
		p = AudioStreamPlayer.new()
		p.name = "Bucle_" + nombre
		p.bus = "World"
		add_child(p)
		_bucles[nombre] = p
	if p.playing and not p.has_meta("apagando"):
		p.volume_db = db + master_db
		return
	# se estaba apagando y vuelve a hacer falta: se corta el fundido, o pararia el sonido nuevo
	var tw_viejo: Tween = _bucle_tw.get(nombre)
	if tw_viejo and tw_viejo.is_valid():
		tw_viejo.kill()
	p.remove_meta("apagando")
	var st := _pick("bf/" + key)
	if st == null:
		return
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	p.stream = st
	p.volume_db = db + master_db
	p.play()


func parar_bucles() -> void:
	for n in _bucles.keys():
		bucle(n, "", false)


# --- LA GUERRA DE FONDO ----------------------------------------------------------------------------
## Lo que hace que un mapa suene a frente y no a campo de pruebas: cada pocos segundos, lejos (70-220
## m) y en una direccion al azar, pasa algo que no es tuyo: una rafaga, un proyectil de artilleria que
## silba y revienta, una sirena, un edificio que gime, una radio. Van por altavoces propios con caida
## logaritmica para que a cien metros se oigan de verdad (los del juego caen con el cuadrado).
##
## Solo en partida (main lo enciende al estar el mundo listo; el lobby lo apaga). `--singuerra`: A/B.
var guerra := false
var _guerra_t := 6.0
var _guerra_pool: Array[AudioStreamPlayer3D] = []
const GUERRA_EVENTOS := [
	# [clave, peso, db]
	["amb/guerra", 6, 2.0],
	["gadget/senuelo", 5, -2.0],          # rafagas sueltas de fusil
	["bala/chasquido_lejos", 3, -4.0],
	["artilleria", 3, 0.0],               # especial: silbido + explosion
	["amb/sirena", 2, -6.0],
	["amb/edificio_gime", 2, -2.0],
	["destru/derrumbe_lejos", 1, 2.0],
	["amb/radio", 1, -10.0],
	["amb/megafono", 1, -8.0],
	["amb/claxon", 1, -10.0],
	["proyectil/canon_lejos", 1, -2.0],
	["amb/bengala", 1, -6.0],
]

func guerra_de_fondo(on: bool) -> void:
	guerra = on and not sin_bf and not ("--singuerra" in OS.get_cmdline_user_args())
	_guerra_t = randf_range(3.0, 7.0)


func _guerra_tick(dt: float) -> void:
	if not guerra:
		return
	_guerra_t -= dt
	if _guerra_t > 0.0:
		return
	_guerra_t = randf_range(3.5, 11.0)
	var oyente := _listener_pos()
	if oyente == Vector3.INF:
		return
	var total := 0
	for e in GUERRA_EVENTOS:
		total += int(e[1])
	var r := randi() % total
	var ev: Array = GUERRA_EVENTOS[0]
	for e in GUERRA_EVENTOS:
		r -= int(e[1])
		if r < 0:
			ev = e
			break
	var a := randf() * TAU
	var d := randf_range(70.0, 220.0)
	var pos: Vector3 = oyente + Vector3(cos(a) * d, randf_range(0.0, 25.0), sin(a) * d)
	if debug:
		print("[guerra] %s a %d m" % [ev[0], int(d)])
	if ev[0] == "artilleria":
		# el silbido por encima de la cabeza y, un segundo y pico despues, el pepinazo lejos
		_guerra_suelta("proyectil/artilleria", oyente + Vector3(cos(a) * 30.0, 40.0, sin(a) * 30.0), -4.0)
		var t := get_tree().create_timer(randf_range(1.2, 1.8))
		t.timeout.connect(func():
			_guerra_suelta_st(_pick("explosion/l"), pos, 6.0)
			_guerra_suelta("destru/derrumbe_grave", pos, 0.0))
		return
	_guerra_suelta(String(ev[0]), pos, float(ev[2]))


func _guerra_voz() -> AudioStreamPlayer3D:
	for p in _guerra_pool:
		if not p.playing:
			return p
	if _guerra_pool.size() >= 4:
		return null
	var p := AudioStreamPlayer3D.new()
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
	p.unit_size = 45.0
	p.max_distance = 600.0
	p.attenuation_filter_cutoff_hz = 3000.0     # de lejos, sin agudos
	p.attenuation_filter_db = -18.0
	p.bus = "World"
	add_child(p)
	_guerra_pool.append(p)
	return p


func _guerra_suelta(key: String, pos: Vector3, db: float) -> void:
	_guerra_suelta_st(_pick("bf/" + key), pos, db)


func _guerra_suelta_st(st: AudioStream, pos: Vector3, db: float) -> void:
	if st == null or not guerra:
		return
	var p := _guerra_voz()
	if p == null:
		return
	p.stream = st
	p.global_position = pos
	p.volume_db = db - 6.0 + master_db
	p.pitch_scale = randf_range(0.94, 1.04)
	p.play()


# --- LO QUE TE PASA A TI ---------------------------------------------------------------------------
## Vida baja: por debajo de VIDA_BAJA suena el aviso y queda el latido con la respiracion hasta que te
## curas o mueres. Se llama con cada cambio de vida.
const VIDA_BAJA := 30.0
var _vida_baja := false

func vida(h: float) -> void:
	var baja: bool = h > 0.0 and h < VIDA_BAJA
	if baja == _vida_baja:
		return
	_vida_baja = baja
	if baja:
		bf2d("yo/vida_baja", -4.0, PRI_HIGH)
	elif h > 0.0:
		bf2d("yo/regenera", -8.0, PRI_MID)
	# EL LATIDO EN BUCLE (SoldierDown_HeartBeat), por encima del zumbido grave y la respiracion
	bucle("latido", "yo/latido", baja, -4.0)
	bucle("zumbido_herido", "yo/vida_baja_bucle", baja, -14.0)
	bucle("respira", "yo/respira_herido", baja, -12.0)


## Te dan. `blindaje`: 0 nada, 1 se lo ha comido el chaleco, 2 el chaleco se acaba de romper.
func me_dan(cabeza: bool, blindaje: int) -> void:
	if blindaje == 2:
		bf2d("yo/chaleco_roto", -2.0, PRI_HIGH)
	elif blindaje == 1:
		bf2d("yo/chaleco", -5.0, PRI_HIGH)
	else:
		bf2d("yo/tiro_cabeza" if cabeza else "yo/bala", -5.0, PRI_HIGH, 0.05)
		bf2d("yo/bala_golpe", -9.0, PRI_MID, 0.06)


## Al morir: el golpe de la muerte, el suspiro, y se cortan el latido y demas bucles.
func me_muero(causa: String = "bala") -> void:
	_vida_baja = false
	parar_bucles()
	bf2d("yo/muerte_" + causa, -3.0, PRI_TOP)
	bf2d("yo/muerte_golpe", -6.0, PRI_TOP)
	if is_inside_tree():
		var t := get_tree().create_timer(0.6)
		t.timeout.connect(func(): bf2d("yo/muerte_suspiro", -8.0, PRI_HIGH))


func reaparezco() -> void:
	_vida_baja = false
	parar_bucles()
	ui("despliegue", -6.0)


# --- DERRUMBES ---------------------------------------------------------------------------------
## Un trozo grande de edificio se viene abajo: el crujido de la estructura, el estruendo y el grave.
## Uno cada poco como mucho: una demolicion suelta decenas de piezas en el mismo segundo y todas
## juntas serian un unico ruido blanco.
var _derrumbe_t := -10.0

func derrumbe(pos: Vector3, voxels: int) -> void:
	var ahora: float = Time.get_ticks_msec() * 0.001
	if ahora - _derrumbe_t < 1.6:
		return
	_derrumbe_t = ahora
	var grande: bool = voxels >= 5000
	_te_cae_encima(_listener_dist(pos), 45.0 if grande else 25.0)
	bf3d("destru/crujido", pos, -2.0, 120.0, PRI_MID)
	bf3d("destru/derrumbe" if grande else "destru/derrumbe_medio", pos, 4.0 if grande else 0.0, 250.0, PRI_TOP)
	if grande:
		bf3d("destru/derrumbe_grave", pos, 2.0, 300.0, PRI_HIGH)
	if _listener_dist(pos) > 60.0:
		bf3d("destru/derrumbe_lejos", pos, 2.0, 400.0, PRI_MID)
	bf3d("destru/escombros", pos, -4.0, 60.0, PRI_LOW)


## Destruction_Death / Destruction de BF: el estruendo de escombro cayendote alrededor. `alcance`: a que
## distancia deja de oirse. Muy cerca, el fuerte; a media distancia, el normal. Uno cada 1,5 s como mucho.
var _encima_t := -10.0
func _te_cae_encima(d: float, alcance: float) -> void:
	if d < 0.0 or d > alcance:
		return
	var ahora: float = Time.get_ticks_msec() * 0.001
	if ahora - _encima_t < 1.5:
		return
	_encima_t = ahora
	var k: float = 1.0 - d / alcance
	if k > 0.5:
		bf2d("yo/destruccion_fuerte", lerpf(-8.0, 0.0, (k - 0.5) * 2.0), PRI_TOP)
	else:
		bf2d("yo/destruccion", lerpf(-16.0, -6.0, k * 2.0), PRI_HIGH)


## Damage_Fire de BF: una explosion con fuego CERCA de ti. El golpe de la llamarada y el crepitar
## alrededor, que se va apagando en unos segundos (mas largo cuanto mayor la explosion).
var _fuego_gen := 0
func _fuego_cerca(d: float, radio: float) -> void:
	if d < 0.0 or d > radio * 4.5:
		return
	var k: float = 1.0 - d / (radio * 4.5)
	bf2d("yo/zona", lerpf(-12.0, -2.0, k), PRI_HIGH)             # Damage_Fire_Start
	bucle("fuego", "yo/fuego", true, lerpf(-18.0, -6.0, k))      # Damage_Fire_Normal / Small
	_fuego_gen += 1
	var gen := _fuego_gen
	if is_inside_tree():
		get_tree().create_timer(lerpf(2.0, 5.0, clampf(radio / 5.0, 0.0, 1.0))).timeout.connect(func():
			if gen == _fuego_gen:          # otra explosion lo ha reavivado: que siga
				bucle("fuego", "", false))


## MUERE OTRO (bot o jugador): el cuerpo contra el suelo y la voz segun como. Un empujon fuerte es una
## explosion (panico), el mazo o el cuchillo es forcejeo o degollado, y a tiros el grito de dolor. No todos
## gritan: a veces caen sin mas, como un tiro limpio.
func muere_otro(pos: Vector3, empujon: Vector3, cuerpo_a_cuerpo: bool) -> void:
	var cabeza: Vector3 = pos + Vector3(0, 1.5, 0)
	bf3d("soldado/muere", pos, -2.0, 40.0, PRI_MID)
	bf3d("soldado/cae_suelo", pos, -4.0, 30.0, PRI_LOW)
	if cuerpo_a_cuerpo:
		bf3d("soldado/muere_cuchillo", cabeza, -2.0, 40.0, PRI_MID)
	elif empujon.length() > 4.5:     # las balas empujan 1-3,5; una explosion cerca, hasta 9
		bf3d("soldado/muere_explosion", cabeza, -2.0, 60.0, PRI_MID)
	elif randf() < 0.7:
		bf3d("soldado/muere_bala", cabeza, -4.0, 45.0, PRI_MID)


## EL CUERPO DEL JUGADOR, cada cuadro (player.gd): respirar tras correr mucho, el esfuerzo al agacharse,
## y las brazadas nadando o buceando.
var _correr_t := 0.0
var _cansado := false
## (2026-09-30, otra vez: "a los tres segundos, subiendo de a poquito, y se oia muy bajita": -8 -> -2, el doble otra vez)
const JADEO_DESDE := 3.0     ## s corriendo sin que se oiga nada
const JADEO_SUBE := 6.0      ## s que tarda en llegar a toda su fuerza
## (2026-10-05, pedido: "se escucha mucho y molesta, un poco mas bajo": -2 -> -8, la mitad; y el resuello de parar igual)
const JADEO_DB := -8.0       ## a toda su fuerza
const JADEO_BAJA_S := 0.8   ## lo que tarda en apagarse al dejar de correr
var _jadeo_vol := 0.0
const RESUELLO_DB := -8.0    ## el "recuperar aire" al dejar de correr
var _agachado := false
var _agachar_t := 0.0
func mov_jugador(dt: float, corriendo: bool, agachado: bool, nadando: bool, buceando: bool, moviendose: bool) -> void:
	# EL JADEO VA ENTRANDO POCO A POCO (2026-09-30, pedido: "el doble de fuerte, pero corriendo unos metros no; si
	# vienes corriendo hace rato, que se empiece a escuchar gradualmente"): nada los primeros JADEO_DESDE s de carrera,
	# y de ahi sube hasta JADEO_DB (el doble que antes: -14 -> -8) en JADEO_SUBE s. Al parar baja igual de suave (el
	# tiempo corrido se descuenta al doble) y suena el resuello de recuperar aire.
	_correr_t = minf(_correr_t + dt, JADEO_DESDE + JADEO_SUBE) if corriendo else maxf(0.0, _correr_t - dt * 2.0)
	var cansado: bool = _correr_t > JADEO_DESDE
	if cansado != _cansado:
		_cansado = cansado
		if not cansado:
			bf2d("yo/respira_para", RESUELLO_DB, PRI_LOW)
	# AL PARAR SE APAGA SUAVE Y DEPRISA (2026-10-13, bug: "dejo de correr y se sigue oyendo y luego corta de la nada"):
	# antes seguia a toda fuerza mientras se descontaba el tiempo corrido y se cortaba en seco. Ahora el volumen baja a
	# cero en JADEO_BAJA_S desde que paras, y el bucle se apaga cuando ya no se oye.
	var fuerza := clampf((_correr_t - JADEO_DESDE) / JADEO_SUBE, 0.0, 1.0) if corriendo else 0.0
	if fuerza >= _jadeo_vol:
		_jadeo_vol = fuerza
	else:
		_jadeo_vol = maxf(fuerza, _jadeo_vol - dt / JADEO_BAJA_S)
	bucle("cansado", "yo/cansado", _jadeo_vol > 0.01, maxf(-50.0, JADEO_DB + linear_to_db(maxf(_jadeo_vol, 0.003))))
	# agacharse: un gruñido suave, y no mas de uno por segundo (hay quien lo machaca)
	var ahora: float = Time.get_ticks_msec() * 0.001
	if agachado and not _agachado and not nadando and ahora - _agachar_t > 1.0:
		_agachar_t = ahora
		bf2d("yo/agacharse", -16.0, PRI_LOW)
	_agachado = agachado
	bucle("nadar", "yo/nadar", nadando and not buceando and moviendose, -10.0)
	bucle("bucear", "yo/bucear", nadando and buceando, -10.0)


## LA RECARGA DE CADA ARMA, por pasos y a su ritmo (`dur` = lo que dura su recarga): sacar el cargador,
## meterlo y montar la corredera o el cerrojo. De Left 4 Dead 2 o de las grabaciones CC0; si el arma no
## trae ninguna, el cargador de BF por tipo (recarga_bf).
func recarga_arma(arma: String, kind: String, dur: float) -> void:
	var raiz := ""
	for r in ["l4d2/armas/", "armas/"]:
		if r == "l4d2/armas/" and sin_bf:
			continue
		if _hay_carpeta("res://sounds/" + r + arma):
			raiz = r + arma + "/"
			break
	var pasos := [["recarga_sacar", 0.12], ["recarga_meter", 0.5], ["recarga_cerrojo", 0.82]]
	var alguno := false
	for p in pasos:
		var k: String = raiz + String(p[0])
		if raiz == "" or _variants(k).is_empty():
			continue
		alguno = true
		get_tree().create_timer(maxf(0.01, dur * float(p[1]))).timeout.connect(func(): play2d(k, -4.0, 0.03, PRI_MID))
	if not alguno:
		recarga_bf(kind)


## VOZ DE UNA CRIATURA DEL PvE (Left 4 Dead 2, l4d2/criaturas/<tipo>/<evento>). El Goliat usa las del
## Tank mas graves: es el mismo monstruo, pero el doble de grande.
## Los especiales de Left 4 Dead 2 (2026-09-26) usan las voces que ya estaban importadas para sus primos
const VOZ_DE := {"cazador": "saltador", "fumador": "arrastrado", "jinete": "arana", "cargador": "bruto",
	"tanque": "acorazado", "bruja": "aullador"}

var _hay_carpeta_voz := {}

func voz_criatura(tipo: String, evento: String, pos: Vector3, db: float = 0.0, alcance: float = 50.0) -> void:
	if sin_bf:
		return
	tipo = String(VOZ_DE.get(tipo, tipo))
	var k := "l4d2/criaturas/%s/%s" % [tipo, evento]
	# la carpeta existe o no una vez, no en cada voz y cada pisada de cada bicho (era una consulta al disco por
	# sonido: con una horda, decenas por segundo)
	if not _hay_carpeta_voz.has(tipo):
		_hay_carpeta_voz[tipo] = DirAccess.dir_exists_absolute("res://sounds/l4d2/criaturas/" + tipo)
	if not bool(_hay_carpeta_voz[tipo]):
		return
	var tono: float = 0.78 if tipo == "goliat" else 1.0
	play3d(k, pos, db, 0.08, alcance, PRI_MID if evento != "paso" else PRI_LOW, tono)


## UN PASO SUELTO DE LA RECARGA DE ESA ARMA ("recarga_sacar", "recarga_meter", "recarga_cerrojo"): los lanza la recarga de
## primera persona (recarga_fp.gd) en su momento.
func paso_recarga(arma: String, paso: String) -> void:
	for r in ["l4d2/armas/", "armas/"]:
		if r == "l4d2/armas/" and sin_bf:
			continue
		var k: String = r + arma + "/" + paso
		if _hay_carpeta("res://sounds/" + r + arma) and not _variants(k).is_empty():
			play2d(k, -4.0, 0.03, PRI_MID)
			return


## LA CORREDERA tras cada tiro de la escopeta de bombeo (la misma de su recarga), `tras` segundos despues
func bombeo_arma(arma: String, tras: float) -> void:
	for r in ["l4d2/armas/", "armas/"]:
		var k: String = r + arma + "/recarga_cerrojo"
		if _hay_carpeta("res://sounds/" + r + arma) and not _variants(k).is_empty():
			get_tree().create_timer(tras).timeout.connect(func(): play2d(k, -5.0, 0.03, PRI_MID))
			return


## Disparo en seco de ESA arma (o el de Teardown si no trae).
func seco_arma(arma: String) -> void:
	for r in ["l4d2/armas/", "armas/"]:
		var k: String = r + arma + "/seco"
		if _hay_carpeta("res://sounds/" + r + arma) and not _variants(k).is_empty():
			play2d(k, -4.0, 0.02, PRI_HIGH)
			return
	dry_fire()


## El cargador de BF segun el tipo de arma, encima de la recarga que ya suena.
func recarga_bf(kind: String) -> void:
	var k: String = {
		"rifle": "soldado/cargador_fusil", "smg": "soldado/cargador_subfusil",
		"shotgun": "soldado/cargador_escopeta", "sniper": "soldado/cargador_cerrojo",
		"pistol": "soldado/cargador_subfusil",
	}.get(kind, "")
	if k != "":
		bf2d(k, -6.0, PRI_MID)


## SALIDA DE RONDA: si es la de partido (a un bando le falta una para ganar), el locutor avisa de que es
## la ultima; si no, la salida normal.
func inicio_ronda() -> void:
	var g = Net.game
	var tope := 0
	if g != null and g.get_script() != null:
		tope = int(g.get_script().get_script_constant_map().get("RONDAS_PARA_GANAR", 0))
	if tope > 0 and bool(g.get("bomb_mode")) and (Net.score_t == tope - 1 or Net.score_ct == tope - 1):
		voz("ultima_ronda", 2)
	else:
		voz("inicio_ronda", 1)
	_quedan_nos = -1
	_quedan_ellos = -1


## QUEDAN POCOS: cuando a un bando le queda uno solo en pie, el locutor lo dice (una vez por ronda y bando).
var _ronda_poll_t := 0.0
var _quedan_nos := -1
var _quedan_ellos := -1
func _ronda_tick(dt: float) -> void:
	_ronda_poll_t -= dt
	if _ronda_poll_t > 0.0:
		return
	_ronda_poll_t = 0.5
	var g = Net.game
	if g == null or not Net.round_live or not bool(g.get("bomb_mode")):
		return
	var mio: String = Net.my_team()
	if mio == "":
		return
	var otro: String = Net.TEAM_CT if mio == Net.TEAM_T else Net.TEAM_T
	var nos: int = Net.en_pie(mio)
	var ellos: int = Net.en_pie(otro)
	if nos == 1 and _quedan_nos > 1:
		voz("quedan_pocos_amigos", 1, 30.0)
	if ellos == 1 and _quedan_ellos > 1:
		voz("quedan_pocos_enemigos", 1, 30.0)
	_quedan_nos = nos
	_quedan_ellos = ellos


## BUCLE PEGADO A UN SITIO (3D): el fuego de un coche reventado, la alarma de la caja fuerte... Cuelga
## del nodo, asi que se mueve con el y muere con el. `on` = false lo apaga con un fundido.
func bucle3d(nodo: Node3D, nombre: String, key: String, on: bool, db: float = -4.0, alcance: float = 50.0) -> void:
	if nodo == null or not is_instance_valid(nodo):
		return
	var p: AudioStreamPlayer3D = nodo.get_node_or_null("BF_" + nombre)
	if not on:
		if p:
			var tw := p.create_tween()
			tw.tween_property(p, "volume_db", -60.0, 0.5)
			tw.tween_callback(p.queue_free)
			p.name = "BF_" + nombre + "_fuera"
		return
	if p or sin_bf or not enabled:
		return
	var st := _pick("bf/" + key)
	if st == null:
		return
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	p = AudioStreamPlayer3D.new()
	p.name = "BF_" + nombre
	p.stream = st
	p.unit_size = 5.0
	p.max_distance = alcance
	p.volume_db = db + master_db
	p.bus = "World"
	nodo.add_child(p)
	p.play()


## Capa de BF por material encima de la rotura de Teardown.
func rotura_bf(cls: String, pos: Vector3) -> void:
	var k: String = {
		"masonry": "destru/ladrillo", "metal": "destru/metal", "wood": "destru/madera",
		"glass": "destru/cristal", "plastic": "destru/plastico",
	}.get(cls, "")
	if k != "":
		bf3d(k, pos, -3.0, 90.0, PRI_LOW)


## --sonidosbf: PRUEBA DE OIDO. Suena cada capa de Battlefield una tras otra, a tu lado, con el nombre en
## pantalla y en consola (y cuantas variantes ha cargado: 0 = no encuentra los archivos).
const PRUEBA_BF := [
	["arma", "carabina_556"], ["armalejos", "carabina_556"], ["armalejos", "fusil_762"], ["armalejos", "rifle_precision"], ["arma", "fusil_762"], ["arma", "fusil_bullpup"], ["arma", "smg_9mm"], ["arma", "smg_compacta"], ["arma", "pdw_57"], ["arma", "escopeta_bomba"], ["arma", "escopeta_auto"], ["arma", "rifle_precision"], ["arma", "pistola_9"], ["arma", "pistola_45"], ["arma", "revolver_44"], ["arma", "bazooka_rpg"], ["arma", "bazooka_at4"],
	["explosion", ""], ["explosion", ""], ["explosion", ""],
	["voz", "inicio_ronda"], ["voz", "victoria"], ["voz", "fuera_limites"], ["voz", "bomba_armada_nos"],
	["ui", "aceptar"], ["ui", "fin_ronda"], ["ui", "bomba_mecha_corta"],
	["2d", "yo/bala"], ["2d", "yo/chaleco_roto"], ["2d", "yo/vida_baja"], ["latido", ""], ["2d", "yo/destruccion_fuerte"], ["fuego", ""], ["2d", "yo/muerte_bala"],
	["2d", "yo/explosion_cerca"], ["3d", "bala/chasquido"], ["3d", "destru/derrumbe"],
	["3d", "destru/crujido"], ["3d", "destru/derrumbe_grave"], ["3d", "modo/bomba_armada"],
	["3d", "gadget/c4_poner"], ["3d", "soldado/muere"], ["3d", "soldado/grito"],
	["3d", "soldado/paracaidas_abre"], ["3d", "destru/coche"],
	["guerra", "amb/guerra"], ["guerra", "gadget/senuelo"], ["guerra", "amb/sirena"],
	["guerra", "proyectil/artilleria"], ["guerra", "amb/edificio_gime"],
]

func prueba_bf(hud: Node) -> void:
	await get_tree().create_timer(3.0).timeout
	guerra = true
	for e in PRUEBA_BF:
		var tipo: String = e[0]
		var k: String = e[1]
		var clave: String = "bf/" + ("voz/" if tipo == "voz" else ("ui/" if tipo == "ui" else "")) + k
		if tipo.begins_with("arma"):
			clave = _disparo_real(k, tipo == "armalejos")
		var n: int = _variants(clave).size() if clave != "" and k != "" else 0
		var texto := "SONIDO BF: %s %s (%d)" % [tipo, k, n]
		print("[sonidosbf] ", texto)
		if hud and hud.has_method("flash_message"):
			hud.flash_message(texto)
		var oyente := _listener_pos()
		var cerca: Vector3 = (oyente if oyente != Vector3.INF else Vector3.ZERO) + Vector3(3.0, 0.0, 0.0)
		match tipo:
			"voz":
				_voz_ultima.clear()
				voz(k, 9)
			"ui":
				ui(k, 0.0)
			"2d":
				bf2d(k, 0.0, PRI_TOP)
			"3d":
				bf3d(k, cerca, 6.0, 80.0, PRI_TOP)
			"guerra":
				_guerra_suelta(k, cerca + Vector3(40.0, 5.0, 0.0), 6.0)
			"arma":
				# tres tiros seguidos, como se oye de verdad
				for _i in 3:
					gunshot("rifle", cerca, true, k)
					await get_tree().create_timer(0.18).timeout
			"armalejos":
				# el mismo tiro, disparado a 60 m (toma de lejos, con su retraso por la velocidad del sonido)
				for _i in 3:
					gunshot("rifle", cerca + Vector3(60.0, 0.0, 0.0), false, k)
					await get_tree().create_timer(0.4).timeout
			"explosion":
				explosion(cerca + Vector3(15.0, 0.0, 0.0), 3.0)
			"latido":
				vida(10.0)
			"fuego":
				vida(100.0)
				_fuego_cerca(2.0, 4.0)
		await get_tree().create_timer(3.5).timeout
	parar_bucles()
	print("[sonidosbf] FIN")


## --audioperdidos: cuenta los sonidos 3D que NO suenan y por que (tope, lejos, sin cargar, repetido, cola llena, sin
## voz). Se imprime cada 10 s.
static var _perdidos_on: bool = "--audioperdidos" in OS.get_cmdline_user_args()
var _perdidos: Dictionary = {}
var _perdidos_t := 0

func _perdido(por: String, key: String) -> void:
	if not _perdidos_on:
		return
	var k := por + " · " + key.get_basename()
	_perdidos[k] = int(_perdidos.get(k, 0)) + 1
	if Time.get_ticks_msec() - _perdidos_t > 10000:
		_perdidos_t = Time.get_ticks_msec()
		var l := _perdidos.keys()
		l.sort_custom(func(a, b): return int(_perdidos[a]) > int(_perdidos[b]))
		var txt := ""
		for x in l.slice(0, 14):
			txt += "
   %4d  %s" % [_perdidos[x], x]
		print("[audioperdidos] en 10 s:" + txt)
		_perdidos.clear()
