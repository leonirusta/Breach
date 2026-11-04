extends MeshInstance3D
## LA MANCHA DE SOMBRA BAJO LOS PERSONAJES (2026-10-13, pedido: "la mancha de abajo mio", como Pixel Gun y la guia de
## Unity para moviles). Con la sombra del sol apagada (el movil: sombras horneadas en el mapa, settings.gd GFX_MOVIL) los
## muñecos no proyectan nada y parecen flotar; esto pone un circulo oscuro difuminado en el suelo, bajo los pies. Un plano
## con la textura de un degradado, sin luz y sin leer nada: casi gratis. La malla y el material son UNO para todos.
## Se pega al suelo con un rayo 15 veces por segundo y se aclara y encoge cuanto mas alto esta el personaje.
## La crea avatar_animator._blob_tick. --sinmancha = sin ella.

const RADIO := 0.42
const ALTO_MAX := 3.0
const HZ := 15.0

static var _malla: QuadMesh = null
static var _mat: StandardMaterial3D = null

var cuerpo: Node3D = null          ## el muñeco (su raiz): la mancha sigue sus pies
var _t := 0.0
var _suelo_y := 0.0
var _hay_suelo := false


static func material() -> StandardMaterial3D:
	if _mat == null:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.55))
		g.set_color(1, Color(0, 0, 0, 0.0))
		g.add_point(0.55, Color(0, 0, 0, 0.32))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.albedo_texture = tex
		_mat.albedo_color = Color.WHITE
		_mat.render_priority = -1
		_mat.no_depth_test = false
		_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return _mat


func _ready() -> void:
	if _malla == null:
		_malla = QuadMesh.new()
		_malla.size = Vector2(RADIO * 2.0, RADIO * 2.0)
		_malla.orientation = PlaneMesh.FACE_Y
	mesh = _malla
	set_meta("sin_contorno", true)      # el contorno rojo del que te mato (player._xray_cubrir) no la pinta
	material_override = material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	_t = randf() / HZ


func _process(dt: float) -> void:
	# sin cuerpo, o el cuerpo desapareciendo (la disolucion del cadaver): sin mancha
	if cuerpo == null or not is_instance_valid(cuerpo) or not cuerpo.is_visible_in_tree() or cuerpo.get("_dis_mat") != null:
		visible = false
		return
	var pies: Vector3 = cuerpo.global_position
	_t -= dt
	if _t <= 0.0:
		_t = 1.0 / HZ
		var w = Net.game.get("world") if Net.game != null and is_instance_valid(Net.game) else null
		_hay_suelo = false
		if w != null and is_instance_valid(w):
			var h: Dictionary = w.raycast(pies + Vector3(0, 0.4, 0), Vector3.DOWN, ALTO_MAX + 0.4)
			if bool(h.get("hit", false)):
				_hay_suelo = true
				_suelo_y = float((h["position"] as Vector3).y)
	if not _hay_suelo:
		visible = false
		return
	var alto := maxf(0.0, pies.y - _suelo_y)
	var k := clampf(1.0 - alto / ALTO_MAX, 0.0, 1.0)
	visible = k > 0.05
	# quieto (el muñeco parado), nada que mandar al servidor de render: cada escritura le avisa aunque no cambie
	var pos := Vector3(pies.x, _suelo_y + 0.03, pies.z)
	if pos != _pos_vista or k != _k_visto:
		_pos_vista = pos
		_k_visto = k
		global_position = pos
		scale = Vector3.ONE * lerpf(0.6, 1.0, k)
		transparency = 1.0 - k


var _pos_vista := Vector3(INF, INF, INF)
var _k_visto := -1.0
