extends Node
## LAS MANOS Y EL ARMA, SIEMPRE NITIDAS, Y EL HUMO POR DELANTE (2026-10-14, pedidos: "con el render bajo mis manos y mi
## arma se ven espantosas" y luego "que se vean nitidas, pero que el humo y los efectos las tapen").
## El mundo 3D se dibuja a una fraccion de la pantalla (Render 3D, 40 % en el movil). Aqui los brazos y el arma van en su
## CAPA propia (CAPA_BRAZOS) y se dibujan aparte, a resolucion completa, en DOS SubViewports con la misma camara:
##   A: solo los brazos y el arma -> su silueta (el canal alfa) dice DONDE se ven
##   B: los brazos y el arma JUNTO CON lo que hay en la capa 1 a menos de ALCANCE m (el humo, el polvo, las chispas, las
##      gotas...) -> el color, con el humo por delante si esta delante (la profundidad la resuelve el propio dibujo)
## Encima del mundo (y debajo de la interfaz y de los efectos de lente, en su CanvasLayer -1, a pantalla completa) se pone
## el color de B recortado con la silueta de A. Fuera de las manos se sigue viendo el mundo con su humo de siempre (una
## sola vez). Lo que NO pasa por delante: una pared de voxels (el arma ya no se mete en los muros).
## Solo si el Render 3D esta por debajo del 95 %. --sinbrazosnitidos = como antes.

const CAPA_BRAZOS := 1 << 19          ## la capa visual 20
const CAPA_EFECTOS := 1               ## donde van las particulas, el humo y los muñecos (el mundo de voxels va en la 11)
const ALCANCE := 4.0                   ## m: mas alla, lo que hubiera esta detras de las manos
## EL SOL, SOLO PARA LA CAMARA PRINCIPAL (2026-10-14, bug: "las sombras del mundo parpadean"): con el sol a la vista de las
## camaras de la capa, su mapa de sombras se rehacia para cada una (con otro encuadre) en el mismo fotograma. El sol de
## verdad pasa a CAPA_SOL (solo la ve la principal) y a las manos las alumbra una copia sin sombra en CAPA_BRAZOS.
const CAPA_SOL := 1 << 12

const SOMBREADO_MEZCLA := """
shader_type canvas_item;
uniform sampler2D color_b : filter_linear, hint_default_transparent;
void fragment() {
	float a = texture(TEXTURE, UV).a;          // la silueta de las manos (A)
	vec4 c = texture(color_b, UV);              // las manos con el humo de delante (B)
	COLOR = vec4(c.rgb, a);
}
"""

var jugador: Node = null
var _sub_a: SubViewport = null
var _sub_b: SubViewport = null
var _cam_a: Camera3D = null
var _cam_b: Camera3D = null
var _capa: CanvasLayer = null
var _rect: TextureRect = null
var _env: Environment = null
var _t_capas := 0.0
var _t_env := 0.0
var _activa := false
var _sky_de := 0
var _sol_brazos: DirectionalLight3D = null
var _sol: DirectionalLight3D = null
static var _con_niebla: bool = "--brazosniebla" in OS.get_cmdline_user_args()
## APAGADA DE FABRICA (2026-10-14, medido a 2220x1080 en el hangar: el cuadro 8,8 -> 14-15 ms con ella; en el S9, con una
## captura a 14 fps, la GPU iba a 47 ms): dibujar dos imagenes mas a resolucion completa de pantalla cuesta mas de lo que
## vale. --brazosnitidos = encendida.
static var _apagada: bool = not ("--brazosnitidos" in OS.get_cmdline_user_args())


func _ready() -> void:
	process_priority = 1000            # despues del jugador: la camara ya esta donde va este fotograma
	if _apagada:
		return
	_env = Environment.new()
	_env.background_mode = Environment.BG_CLEAR_COLOR
	_env.background_color = Color(0, 0, 0, 0)
	_sub_a = _nueva_sub()
	_cam_a = _nueva_cam(_sub_a, CAPA_BRAZOS)
	_sub_b = _nueva_sub()
	_cam_b = _nueva_cam(_sub_b, CAPA_BRAZOS | CAPA_EFECTOS)
	_capa = CanvasLayer.new()
	_capa.layer = -1                   # encima del mundo 3D, debajo de la interfaz (y de la lente: lluvia, sangre, tierra)
	add_child(_capa)
	_rect = TextureRect.new()
	_rect.texture = _sub_a.get_texture()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var sh := Shader.new()
	sh.code = SOMBREADO_MEZCLA
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("color_b", _sub_b.get_texture())
	_rect.material = mat
	_rect.visible = false
	_capa.add_child(_rect)
	get_viewport().size_changed.connect(_tam)
	_tam()


func _nueva_sub() -> SubViewport:
	var s := SubViewport.new()
	s.transparent_bg = true
	s.render_target_update_mode = SubViewport.UPDATE_DISABLED
	s.msaa_3d = Viewport.MSAA_DISABLED
	add_child(s)
	return s


func _nueva_cam(s: SubViewport, mascara: int) -> Camera3D:
	var c := Camera3D.new()
	c.cull_mask = mascara
	c.far = ALCANCE
	c.environment = _env
	s.add_child(c)
	c.current = true
	return c


## A los PIXELES de verdad de la pantalla (en el movil el lienzo de la interfaz va escalado: con su tamaño la capa salia
## mas chica y se veia una raya)
func _tam() -> void:
	var t: Vector2i = get_window().size if get_window() else Vector2i(get_viewport().get_visible_rect().size)
	for s in [_sub_a, _sub_b]:
		if s:
			s.size = t


func _process(dt: float) -> void:
	if _apagada or jugador == null or not is_instance_valid(jugador):
		return
	var cam: Camera3D = jugador.get("cam")
	var pivote: Node3D = jugador.get("weapon_pivot")
	var brazos: Node3D = jugador.get("fp_arms")
	if cam == null or not is_instance_valid(cam):
		return
	var bajo: bool = get_viewport().scaling_3d_scale < 0.95
	var se_ve: bool = (pivote != null and pivote.is_visible_in_tree()) or (brazos != null and is_instance_valid(brazos) and brazos.is_visible_in_tree())
	var quiere := bajo and se_ve and not bool(jugador.get("third_person"))
	if quiere != _activa:
		_activa = quiere
		_rect.visible = quiere
		var modo := SubViewport.UPDATE_ALWAYS if quiere else SubViewport.UPDATE_DISABLED
		_sub_a.render_target_update_mode = modo
		_sub_b.render_target_update_mode = modo
		cam.cull_mask = (cam.cull_mask & ~CAPA_BRAZOS) if quiere else (cam.cull_mask | CAPA_BRAZOS)
		_poner_sol(quiere)
		_t_capas = 0.0
	if not _activa:
		return
	if is_instance_valid(_sol) and is_instance_valid(_sol_brazos):
		_sol_brazos.global_transform = _sol.global_transform
		_sol_brazos.light_color = _sol.light_color
		_sol_brazos.light_energy = _sol.light_energy
		_sol_brazos.visible = _sol.visible
	for c in [_cam_a, _cam_b]:
		c.global_transform = cam.global_transform
		c.fov = cam.fov
		c.near = cam.near
		c.keep_aspect = cam.keep_aspect
	# las capas: los modelos cambian (otra arma, el fogonazo, la granada en la mano), se miran 5 veces por segundo
	_t_capas -= dt
	if _t_capas <= 0.0:
		_t_capas = 0.2
		for raiz in [pivote, brazos]:
			if raiz != null and is_instance_valid(raiz):
				_poner_capa(raiz)
	# la luz, el cielo y el tono de la escena, para que casen
	_t_env -= dt
	if _t_env <= 0.0:
		_t_env = 0.5
		var we := get_viewport().find_world_3d()
		var e: Environment = we.environment if we else null
		if e == null and jugador.get_tree().current_scene:
			var envn = jugador.get_tree().current_scene.get("env")
			e = envn.environment if envn != null and is_instance_valid(envn) else null
		if e:
			# SU PROPIA COPIA DEL CIELO (2026-10-14, bug: "el mapa parpadea al sol"): compartiendo el mismo Sky, su luz
			# (ambiente y reflejos) se recalculaba para cada camara y la del mapa saltaba de un fotograma a otro, y toda la
			# imagen salia un 25 % mas brillante. Se copia una vez y otra vez solo si el de la escena cambia.
			if e.sky != null and e.sky.get_instance_id() != _sky_de:
				_sky_de = e.sky.get_instance_id()
				_env.sky = e.sky.duplicate()
			elif e.sky == null:
				_env.sky = null
				_sky_de = 0
			_env.sky_custom_fov = e.sky_custom_fov
			_env.ambient_light_source = e.ambient_light_source
			_env.ambient_light_color = e.ambient_light_color
			_env.ambient_light_energy = e.ambient_light_energy
			_env.ambient_light_sky_contribution = e.ambient_light_sky_contribution
			_env.reflected_light_source = e.reflected_light_source
			_env.tonemap_mode = e.tonemap_mode
			_env.tonemap_exposure = e.tonemap_exposure
			_env.tonemap_white = e.tonemap_white
			_env.adjustment_enabled = e.adjustment_enabled
			_env.adjustment_brightness = e.adjustment_brightness
			_env.adjustment_contrast = e.adjustment_contrast
			_env.adjustment_saturation = e.adjustment_saturation
			# la niebla tambien (dentro de una nube, el arma se emborrona como el resto)
			_env.fog_enabled = e.fog_enabled and _con_niebla
			_env.fog_light_color = e.fog_light_color
			_env.fog_light_energy = e.fog_light_energy
			_env.fog_density = e.fog_density


func _poner_sol(on: bool) -> void:
	if _sol == null:
		var esc = jugador.get_tree().current_scene if jugador and jugador.is_inside_tree() else null
		var s = esc.get("sun") if esc != null else null
		if s is DirectionalLight3D:
			_sol = s
	if not is_instance_valid(_sol):
		return
	_sol.layers = CAPA_SOL if on else 1
	if on and _sol_brazos == null:
		_sol_brazos = DirectionalLight3D.new()
		_sol_brazos.layers = CAPA_BRAZOS
		_sol_brazos.light_cull_mask = CAPA_BRAZOS | CAPA_EFECTOS
		_sol_brazos.shadow_enabled = false
		_sol.get_parent().add_child(_sol_brazos)
	if is_instance_valid(_sol_brazos):
		_sol_brazos.visible = on


func _poner_capa(n: Node) -> void:
	# el FOGONAZO y el gas (particulas que suman luz) se quedan en el mundo: en la capa salian opacos, "como pintura"
	if n is GPUParticles3D or n is CPUParticles3D:
		return
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = CAPA_BRAZOS
	for c in n.get_children():
		_poner_capa(c)
