extends Node3D
## LA TORMENTA: RELAMPAGOS Y TRUENOS mientras llueve (pedido 2026-09-21: "la tormenta completa").
##
## Cada RAYO_CADA_MIN..MAX segundos cae un rayo a una distancia al azar:
##   * el DESTELLO: el sol, la luz ambiente y el cielo suben de golpe con un parpadeo doble (fuerte, flojo,
##     fuerte) y vuelven a lo que habia. Mas fuerte cuanto mas cerca. Es lo que mas se nota y no cuesta nada:
##     solo se mueven tres numeros durante medio segundo.
##   * el RAYO: si cae cerca y a veces, una linea quebrada con ramas, del cielo al horizonte. Una malla de
##     cintas encarada a la camara, sin sombra y aditiva; los edificios que haya delante la tapan.
##   * el TRUENO: tools/generar_truenos.py (sintetizados, sin derechos). Llega con el retraso del sonido
##     (340 m/s) y la variante segun la distancia: de cerca con chasquido, de lejos solo el rumor.
##
## Es decorado: cada maquina tira sus propios rayos. No toca nada de la partida.

const RAYO_CADA_MIN := 7.0
const RAYO_CADA_MAX := 22.0
const DIST_MIN := 150.0
const DIST_MAX := 900.0
const DIST_RAYO_VISIBLE := 600.0      ## mas lejos el rayo no se ve, solo el resplandor
const VEL_SONIDO := 340.0

var main: Node = null
var _t := 5.0
# el destello en curso
var _fl_t := -1.0
var _fl_fuerza := 0.0
var _base_sol := 0.0
var _base_amb := 0.0
var _base_cielo := 1.0
var _rayo: MeshInstance3D = null
var _mat_rayo: StandardMaterial3D = null
var _truenos: Dictionary = {}
var _nuevos: Array = []
var _audio: AudioStreamPlayer = null


func _ready() -> void:
	for n in ["cerca", "medio", "lejos"]:
		var ruta := "res://sounds/tormenta/trueno_%s.wav" % n
		if ResourceLoader.exists(ruta):
			_truenos[n] = load(ruta)
	# LOS TRUENOS DE VERDAD (2026-10-13): los efectos que se bajan a sounds/tormenta/nuevos/ (wav, mp3 u ogg); suena uno al
	# azar. BudgetPixel (CC BY 4.0: hay que nombrar a "BudgetPixel AI" en los creditos)
	var dir := DirAccess.open("res://sounds/tormenta/nuevos")
	if dir:
		for f in dir.get_files():
			var fn := String(f).trim_suffix(".import").trim_suffix(".remap")
			if fn.get_extension() in ["wav", "mp3", "ogg"]:
				var st = load("res://sounds/tormenta/nuevos/" + fn)
				if st != null and not _nuevos.has(st):
					_nuevos.append(st)
	_audio = AudioStreamPlayer.new()
	_audio.bus = "Lluvia" if AudioServer.get_bus_index("Lluvia") >= 0 else "Master"
	add_child(_audio)
	_mat_rayo = StandardMaterial3D.new()
	_mat_rayo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_rayo.albedo_color = Color(0.82, 0.88, 1.0, 1.0)
	_mat_rayo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_rayo.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat_rayo.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_rayo.no_depth_test = false
	_rayo = MeshInstance3D.new()
	_rayo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rayo.material_override = _mat_rayo
	_rayo.visible = false
	add_child(_rayo)


## --sinrayos: llueve sin relampagos (para comparar fotos con lluvia, banco de la lluvia 2026-10-05)
var _sin_rayos: bool = "--sinrayos" in OS.get_cmdline_user_args()


func _process(dt: float) -> void:
	if main == null or not is_instance_valid(main):
		return
	if _fl_t >= 0.0:
		_destello(dt)
	if not bool(main.get("raining")) or _sin_rayos:
		return
	_t -= dt
	if _t <= 0.0:
		_t = randf_range(RAYO_CADA_MIN, RAYO_CADA_MAX)
		cae_un_rayo()


## Un rayo ahora (tambien lo usa la prueba --fototormenta).
func cae_un_rayo(dist: float = -1.0, hacia: Vector3 = Vector3.ZERO) -> void:
	var d := dist if dist > 0.0 else randf_range(DIST_MIN, DIST_MAX)
	var pl = main.get("player")
	var centro: Vector3 = pl.global_position if pl != null and is_instance_valid(pl) else Vector3.ZERO
	var ang := randf() * TAU
	var dir := Vector3(cos(ang), 0.0, sin(ang))
	if hacia != Vector3.ZERO:
		dir = Vector3(hacia.x, 0.0, hacia.z).normalized()
	var donde := centro + dir * d
	_fl_fuerza = clampf(1.35 - d / DIST_MAX, 0.3, 1.0)
	_empezar_destello()
	if d < DIST_RAYO_VISIBLE and (hacia != Vector3.ZERO or randf() < 0.66):
		_dibujar_rayo(donde, centro)
	_trueno(d)


# --------------------------------------------------------------------------------------------------
# EL DESTELLO
# --------------------------------------------------------------------------------------------------

func _empezar_destello() -> void:
	var sol = main.get("sun")
	var env = main.get("env")
	if _fl_t < 0.0:          # si ya habia uno en curso, se conserva su base (no la del destello)
		_base_sol = float(sol.light_energy) if sol else 0.0
		if env and env.environment:
			_base_amb = env.environment.ambient_light_energy
			_base_cielo = env.environment.background_energy_multiplier
	_fl_t = 0.0


## fuerte (0-0,07 s), flojo (hasta 0,15), fuerte otra vez (0,15-0,22) y se apaga hasta 0,55 s
func _curva(t: float) -> float:
	if t < 0.07:
		return t / 0.07
	if t < 0.15:
		return lerpf(1.0, 0.25, (t - 0.07) / 0.08)
	if t < 0.22:
		return lerpf(0.25, 0.85, (t - 0.15) / 0.07)
	if t < 0.55:
		return lerpf(0.85, 0.0, (t - 0.22) / 0.33)
	return 0.0


func _destello(dt: float) -> void:
	_fl_t += dt
	var k := _curva(_fl_t) * _fl_fuerza
	var sol = main.get("sun")
	var env = main.get("env")
	if sol:
		sol.light_energy = _base_sol + 2.6 * k
	if env and env.environment:
		env.environment.ambient_light_energy = _base_amb + 1.4 * k
		env.environment.background_energy_multiplier = _base_cielo * (1.0 + 2.5 * k)
	if _rayo.visible:
		_mat_rayo.albedo_color.a = clampf(k * 1.4, 0.0, 1.0)
	if _fl_t >= 0.55:
		_fl_t = -1.0
		if sol:
			sol.light_energy = _base_sol
		if env and env.environment:
			env.environment.ambient_light_energy = _base_amb
			env.environment.background_energy_multiplier = _base_cielo
		_rayo.visible = false


# --------------------------------------------------------------------------------------------------
# EL RAYO
# --------------------------------------------------------------------------------------------------

## Una polilinea quebrada del cielo al suelo (desplazamiento por mitades), y una o dos ramas.
func _quebrada(a: Vector3, b: Vector3, desvio: float, niveles: int) -> PackedVector3Array:
	var pts := PackedVector3Array([a, b])
	var d := desvio
	for _n in niveles:
		var nuevo := PackedVector3Array()
		for i in pts.size() - 1:
			nuevo.append(pts[i])
			var m: Vector3 = (pts[i] + pts[i + 1]) * 0.5
			m += Vector3(randf_range(-d, d), randf_range(-d, d) * 0.3, randf_range(-d, d))
			nuevo.append(m)
		nuevo.append(pts[pts.size() - 1])
		pts = nuevo
		d *= 0.55
	return pts


func _dibujar_rayo(suelo: Vector3, ojo: Vector3) -> void:
	var alto := 160.0
	var tronco := _quebrada(suelo + Vector3(randf_range(-40, 40), alto, randf_range(-40, 40)), suelo, 38.0, 6)
	var trazos: Array = [[tronco, 2.4]]
	for _r in randi_range(1, 2):
		var desde: Vector3 = tronco[randi_range(tronco.size() / 5, tronco.size() / 2)]
		var hasta := desde + Vector3(randf_range(-45, 45), -randf_range(30, 70), randf_range(-45, 45))
		trazos.append([_quebrada(desde, hasta, 16.0, 4), 1.1])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tr in trazos:
		var pts: PackedVector3Array = tr[0]
		var ancho: float = tr[1]
		for i in pts.size() - 1:
			var p0 := pts[i]
			var p1 := pts[i + 1]
			# la cinta, de cara a quien mira
			var lado := (p1 - p0).cross(ojo - p0).normalized() * ancho * 0.5
			st.add_vertex(p0 - lado)
			st.add_vertex(p0 + lado)
			st.add_vertex(p1 + lado)
			st.add_vertex(p0 - lado)
			st.add_vertex(p1 + lado)
			st.add_vertex(p1 - lado)
	_rayo.mesh = st.commit()
	_rayo.visible = true


# --------------------------------------------------------------------------------------------------
# EL TRUENO
# --------------------------------------------------------------------------------------------------

## EL TRUENO: los sintetizados de tools/generar_truenos.py (2026-10-13, pedido: "los de antes me gustaban mas"; los
## descargados de BudgetPixel se quitaron). Si hubiera alguno en sounds/tormenta/nuevos, suena ese. --sintrueno = ninguno.
func _trueno(d: float) -> void:
	if not _nuevos.is_empty():
		await get_tree().create_timer(d / VEL_SONIDO).timeout
		if not is_instance_valid(_audio):
			return
		_audio.stream = _nuevos[randi() % _nuevos.size()]
		_audio.volume_db = lerpf(-2.0, -14.0, clampf((d - DIST_MIN) / (DIST_MAX - DIST_MIN), 0.0, 1.0))
		_audio.pitch_scale = randf_range(0.92, 1.06)
		_audio.play()
		return
	if "--sintrueno" in OS.get_cmdline_user_args():
		return
	var clave := "cerca" if d < 300.0 else ("medio" if d < 600.0 else "lejos")
	var st = _truenos.get(clave)
	if st == null:
		return
	await get_tree().create_timer(d / VEL_SONIDO).timeout
	if not is_instance_valid(_audio):
		return
	_audio.stream = st
	_audio.volume_db = lerpf(0.0, -12.0, clampf((d - DIST_MIN) / (DIST_MAX - DIST_MIN), 0.0, 1.0))
	_audio.pitch_scale = randf_range(0.9, 1.08)
	_audio.play()
