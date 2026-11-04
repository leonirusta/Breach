extends Node
## LOS EFECTOS DEL NANOTRAJE EN TU PANTALLA (2026-10-03, pedido: "animaciones super realistas y cinematograficas a la
## invisibilidad, al blindaje y al salto, con efecto de camara; el blindaje como el de Crysis 3, en la lente"). Lo crea
## habilidad.gd para el jugador de esta maquina con un personaje de ENERGIA (el Specter). Una capa con la LENTE
## (shaders/nanotraje_lente.gdshader) que solo se dibuja con algo encendido, y la CAMARA: `fov_extra` (lo suma
## habilidad._camara_tick) y los temblores del jugador.

const LENTE := preload("res://shaders/nanotraje_lente.gdshader")
## (2026-10-03, el lag del blindaje) el blindaje y el super salto van en OTRA capa que no lee la pantalla: la lente de la
## invisibilidad (que si tuerce lo de detras) obligaba a copiar la pantalla entera cada fotograma. Ahora solo se copia
## mientras estas invisible. Medido con --nanofps.
const LENTE_BLINDAJE := preload("res://shaders/nanotraje_lente_blindaje.gdshader")

var player: Node = null
var fov_extra := 0.0          ## grados que suma a la vista (negativo cierra)

var _capa: CanvasLayer
var _rect: ColorRect             ## la invisibilidad (lee la pantalla)
var _mat: ShaderMaterial
var _rect_b: ColorRect           ## el blindaje y el salto (no la lee)
var _mat_b: ShaderMaterial
var _t := 0.0
var _blindaje := 0.0
var _blindaje_obj := 0.0
var _barrido := -1.0
var _golpe := 0.0
var _golpe_dir := Vector2(0, 1)
var _invis := 0.0
var _invis_obj := 0.0
var _onda := -1.0
var _carga := 0.0
var _carga_t := 0.0          ## s desde la ultima vez que se dijo la carga (si se deja de decir, se va)
var _lineas := 0.0
var _kick := 0.0             ## el tiron de la vista (grados), que vuelve solo
var _calentando := false     ## los primeros fotogramas, precalentando (la lente se queda puesta)


func _ready() -> void:
	_capa = CanvasLayer.new()
	_capa.layer = -1              # encima del mundo, debajo de la interfaz (como la pantalla de hab_fx)
	add_child(_capa)
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = LENTE
	_rect.material = _mat
	_rect.visible = false
	_capa.add_child(_rect)
	_rect_b = ColorRect.new()
	_rect_b.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect_b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat_b = ShaderMaterial.new()
	_mat_b.shader = LENTE_BLINDAJE
	_rect_b.material = _mat_b
	_rect_b.visible = false
	_capa.add_child(_rect_b)
	_precalentar()


## PRECALENTADO: la primera vez que se dibuja cada sombreado se compila (300-700 ms de tiron al encender el blindaje o la
## invisibilidad). Se dibujan los dos un par de fotogramas al empezar, sin que se note: la lente con todo a 0 deja la
## imagen igual, y el brillo del traje con fuerza 0 no suma nada.
func _precalentar() -> void:
	_calentando = true
	_rect.visible = true
	_rect_b.visible = true
	var cubo := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.05, 0.05)
	cubo.mesh = bm
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/nanotraje_cuerpo.gdshader")
	cubo.material_override = m
	var cam = player.get("cam") if player != null else null
	if cam != null and is_instance_valid(cam):
		(cam as Node).add_child(cubo)
		cubo.position = Vector3(0, 0, -0.6)
	else:
		add_child(cubo)
	for _i in 3:
		await get_tree().process_frame
	cubo.queue_free()
	_calentando = false
	_rect.visible = false
	_rect_b.visible = false


func _temblor(fuerza: float, dur: float) -> void:
	if player != null and is_instance_valid(player) and player.has_method("temblor_suelo"):
		player.temblor_suelo(fuerza, dur)


func _shake(k: float) -> void:
	if player != null and is_instance_valid(player) and player.has_method("add_shake"):
		player.add_shake(k)


# ------------------------------------------------------------------ lo que avisa habilidad.gd / player.gd
## Todo apagado de golpe, sin animacion (al reaparecer)
func apagar() -> void:
	_blindaje_obj = 0.0
	_blindaje = 0.0
	_invis_obj = 0.0
	_invis = 0.0
	_barrido = -1.0
	_onda = -1.0
	_golpe = 0.0
	_carga = 0.0
	_lineas = 0.0
	_kick = 0.0


func blindaje_on(on: bool) -> void:
	_blindaje_obj = 1.0 if on else 0.0
	if on:
		_barrido = 0.0
		_kick -= 5.0                 # la vista se "cierra" un instante, como si se tensara el traje
		_shake(0.08)
		_temblor(0.02, 0.18)


## Un golpe con el blindaje puesto: los hexagonos del lado de donde viene
func golpe(desde: Vector3, fuerza: float) -> void:
	_golpe = clampf(maxf(_golpe, 0.45 + fuerza), 0.0, 1.2)
	var cam = player.get("cam") if player != null and is_instance_valid(player) else null
	if cam != null and is_instance_valid(cam) and desde != Vector3.ZERO:
		var local: Vector3 = (cam as Camera3D).global_transform.basis.inverse() * (desde - (cam as Camera3D).global_position)
		var d := Vector2(local.x, maxf(0.0, local.z) - minf(0.0, local.y) * 0.5)
		_golpe_dir = d.normalized() if d.length() > 0.01 else Vector2(0, 1)
	_shake(0.05 + fuerza * 0.06)


func invisible_on(on: bool) -> void:
	_invis_obj = 1.0 if on else 0.0
	_onda = 0.0
	_kick += 4.0 if on else -3.0
	_temblor(0.012, 0.25)


## La carga del super salto (0..1), cada fotograma mientras se mantiene
func carga_salto(k: float) -> void:
	_carga = clampf(k, 0.0, 1.0)
	_carga_t = 0.0
	if k > 0.3:
		_temblor(0.004 + 0.012 * k, 0.1)


func salto() -> void:
	_carga = 0.0
	_lineas = 1.0
	_kick += 16.0
	_shake(0.14)


func aterrizaje(fuerza: float) -> void:
	_shake(0.08 + 0.12 * fuerza)
	_temblor(0.03 * fuerza, 0.3)
	_kick -= 4.0 * fuerza


func _process(dt: float) -> void:
	_t += dt
	_blindaje = move_toward(_blindaje, _blindaje_obj, dt * (3.0 if _blindaje_obj > _blindaje else 2.0))
	_invis = move_toward(_invis, _invis_obj, dt * (2.5 if _invis_obj > _invis else 3.0))
	if _barrido >= 0.0:
		_barrido += dt / 0.6
		if _barrido >= 1.0:
			_barrido = -1.0
	if _onda >= 0.0:
		_onda += dt / 0.75
		if _onda >= 1.0:
			_onda = -1.0
	_golpe = maxf(0.0, _golpe - dt * 3.0)
	_lineas = maxf(0.0, _lineas - dt * 1.4)
	_carga_t += dt
	if _carga_t > 0.08:
		_carga = maxf(0.0, _carga - dt * 4.0)
	_kick = lerpf(_kick, 0.0, 1.0 - exp(-dt * 4.5))
	fov_extra = _kick - 7.0 * _carga
	var invis := _invis > 0.001 or _onda >= 0.0 or _calentando
	var resto := _blindaje > 0.001 or _barrido >= 0.0 or _golpe > 0.001 or _carga > 0.001 or _lineas > 0.001 \
		or _calentando
	if _rect.visible != invis:
		_rect.visible = invis
	if _rect_b.visible != resto:
		_rect_b.visible = resto
	if invis:
		_mat.set_shader_parameter("tiempo", _t)
		_mat.set_shader_parameter("invisible", _invis)
		_mat.set_shader_parameter("onda", _onda)
	if resto:
		_mat_b.set_shader_parameter("tiempo", _t)
		_mat_b.set_shader_parameter("blindaje", _blindaje)
		_mat_b.set_shader_parameter("barrido", _barrido)
		_mat_b.set_shader_parameter("golpe", _golpe)
		_mat_b.set_shader_parameter("golpe_dir", _golpe_dir)
		_mat_b.set_shader_parameter("salto_carga", _carga)
		_mat_b.set_shader_parameter("salto_lineas", _lineas)
