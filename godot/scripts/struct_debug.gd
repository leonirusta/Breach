## Visualización de depuración del analizador estructural (Fase 31). SÓLO desarrollo: F11 la alterna y en
## builds de release no hace nada (OS.is_debug_build()).
##
## Dibuja cada celda evaluada de la última iteración como un cubo coloreado por su ratio carga/capacidad:
##   verde < 0,7 (estable) · amarillo 0,7-0,9 (cargada) · naranja 0,9-1,08 (crítica) · rojo > 1,08 (sobrecargada)
##   magenta = sin ruta de apoyo · gris = fallida (extraída) · azul = apoyo directo (suelo/borde) · blanco = saltada
## Además: caja de la región, centro del daño (esfera), centro de masas de cada isla (esfera) y su apoyo (línea).
## Todo con un MultiMesh (un draw call) + un ImmediateMesh para líneas.
extends Node3D

var world: Node
var enabled := false
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _lines: MeshInstance3D
var _im: ImmediateMesh
var _frame := 0
var _last_iter := -1

const STATE_AIR := 0
const STATE_STABLE := 1
const STATE_HIGH := 2
const STATE_CRITICAL := 3
const STATE_OVERLOADED := 4
const STATE_UNSUPPORTED := 5
const STATE_FAILED := 6
const STATE_GROUNDED := 7
const STATE_SKIPPED := 8

func _ready() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = false
	box.material = mat
	_mm.mesh = box
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)
	_im = ImmediateMesh.new()
	_lines = MeshInstance3D.new()
	_lines.mesh = _im
	var lm := StandardMaterial3D.new()
	lm.vertex_color_use_as_albedo = true
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.no_depth_test = true
	_lines.material_override = lm
	add_child(_lines)
	visible = false

func set_enabled(on: bool) -> void:
	enabled = on and OS.is_debug_build()
	visible = enabled
	if not enabled:
		_mm.instance_count = 0
		_im.clear_surfaces()

static func _color_for(state: int, ratio: float) -> Color:
	match state:
		STATE_UNSUPPORTED: return Color(1.0, 0.2, 1.0, 0.85)
		STATE_FAILED: return Color(0.35, 0.35, 0.35, 0.6)
		STATE_GROUNDED: return Color(0.3, 0.5, 1.0, 0.45)
		STATE_SKIPPED: return Color(1.0, 1.0, 1.0, 0.25)
	if ratio > 1.08: return Color(1.0, 0.1, 0.1, 0.85)
	if ratio > 0.9: return Color(1.0, 0.55, 0.1, 0.7)
	if ratio > 0.7: return Color(1.0, 0.95, 0.2, 0.6)
	return Color(0.2, 0.9, 0.3, 0.45)

func _process(_dt: float) -> void:
	if not enabled or world == null:
		return
	_frame += 1
	if (_frame % 6) != 0:   # el analizador itera cada 6 frames: no hay nada nuevo antes
		return
	var d: Dictionary = world.get_struct_debug()
	if d.is_empty():
		return
	var centers: PackedVector3Array = d.get("cell_centers", PackedVector3Array())
	var ratios: PackedFloat32Array = d.get("cell_ratios", PackedFloat32Array())
	var states: PackedByteArray = d.get("cell_states", PackedByteArray())
	var cell: float = d.get("cell_size", 0.5)
	var n := centers.size()
	_mm.instance_count = n
	var s := cell * 0.92
	for i in n:
		var xf := Transform3D(Basis().scaled(Vector3(s, s, s)), centers[i])
		_mm.set_instance_transform(i, xf)
		_mm.set_instance_color(i, _color_for(states[i], ratios[i]))
	_mm.visible_instance_count = n
	# líneas: región, centro de daño, islas
	_im.clear_surfaces()
	_im.surface_begin(Mesh.PRIMITIVE_LINES)
	var mn: Vector3 = d.get("region_min", Vector3.ZERO)
	var mx: Vector3 = d.get("region_max", Vector3.ZERO)
	_box(mn, mx, Color(0.2, 0.8, 1.0))
	var dc: Vector3 = d.get("damage_center", Vector3.ZERO)
	_cross(dc, 0.6, Color(1, 0.3, 0.3))
	for isl in d.get("islands", []):
		var com: Vector3 = isl.get("com", Vector3.ZERO)
		var sup: Vector3 = isl.get("support", Vector3.ZERO)
		_cross(com, 0.5, Color(1, 1, 0.2))
		_im.surface_set_color(Color(1, 1, 0.2)); _im.surface_add_vertex(com)
		_im.surface_set_color(Color(0.3, 0.6, 1.0)); _im.surface_add_vertex(sup)
	_im.surface_end()
	if d.get("iteration", 0) != _last_iter:
		_last_iter = d.get("iteration", 0)
		print("[struct] it %d: islas %d (saltadas %d), celdas %d, fallos %d, peor ratio %.2f, %.2f ms" % [
			_last_iter, d.get("islands_evaluated", 0), d.get("islands_skipped", 0), d.get("cells_evaluated", 0), d.get("failures", 0), d.get("worst_ratio", 0.0), d.get("ms", 0.0)])

func _box(a: Vector3, b: Vector3, c: Color) -> void:
	var p := [Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z),
			  Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z)]
	var e := [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]
	for pair in e:
		_im.surface_set_color(c); _im.surface_add_vertex(p[pair[0]])
		_im.surface_set_color(c); _im.surface_add_vertex(p[pair[1]])

func _cross(p: Vector3, r: float, c: Color) -> void:
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		_im.surface_set_color(c); _im.surface_add_vertex(p - axis * r)
		_im.surface_set_color(c); _im.surface_add_vertex(p + axis * r)
