extends Node3D
## EL PEDAZO DE SUELO QUE TE TIRA EL GOLIAT. El jefe clava las garras en el suelo, arranca un trozo
## (que deja su agujero de verdad: los voxels salen de la rejilla) y te lo lanza. Vuela en parabola
## girando y, donde cae, REVIENTA: abre un socavon y hace daño en area.
##
## No es un cuerpo fisico: los voxels son la rejilla del mundo, asi que se mueve a mano y pregunta al
## mundo con un raycast por cada paso, igual que el escupitajo del escupidor.

const G := 9.8

var world = null
var jugador: Node3D = null
var autor: Node = null
var dano := 45.0
var radio := 2.4                      ## m de socavon al reventar
var potencia := 190                   ## dureza que es capaz de romper
var _v := Vector3.ZERO
var _giro := Vector3.ZERO
var _vida := 6.0
## PEDRUSCO DE ADORNO (el que ven los invitados). Vuela y se ve caer, pero no abre socavon ni hace
## daño: eso lo reparte la maquina del anfitrion, que es quien lleva al bicho.
var ajeno := false


## `tam` es el lado del pedrusco en metros; `color` sale del material del suelo que arranco.
func lanzar(p_world, p_jugador: Node3D, p_autor: Node, objetivo: Vector3, rapidez: float,
		p_dano: float, tam: float, color: Color) -> void:
	world = p_world
	jugador = p_jugador
	autor = p_autor
	dano = p_dano
	radio = maxf(radio, tam * 1.5)
	var d := objetivo - global_position
	var t := clampf(Vector3(d.x, 0.0, d.z).length() / maxf(rapidez, 1.0), 0.45, 2.2)
	_v = d / t + Vector3.UP * 0.5 * G * t
	_giro = Vector3(randf_range(-3.0, 3.0), randf_range(-2.0, 2.0), randf_range(-3.0, 3.0))
	add_child(malla_roca(tam, color))


## UNA ROCA, NO TRES (2026-09-23, pedido: "hay 2 rocas en 1"). Eran tres cajas sueltas giradas al azar y se
## leian como piedras pegadas. Ahora es un solo pedrusco: una esfera de pocas caras con los vertices empujados
## al azar y caras planas, que se lee como piedra partida. Lo usa tambien la roca en la mano (criatura.gd),
## asi que no cambia de forma al lanzarla.
static func malla_roca(tam: float, color: Color) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = tam * 0.5
	sm.height = tam * 0.85
	sm.radial_segments = 7
	sm.rings = 4
	var arr: Array = sm.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var sem := randi()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)            # caras planas: piedra partida, no un canto rodado
	for k in idx:
		var v: Vector3 = vs[k]
		# mismo empuje para el mismo vertice (si no, las caras se abririan): se saca de su posicion
		var h := hash(Vector3i(roundi(v.x * 1000.0), roundi(v.y * 1000.0), roundi(v.z * 1000.0))) ^ sem
		var f := 0.78 + float(absi(h) % 1000) / 1000.0 * 0.40
		st.add_vertex(v * f)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.08)
	m.roughness = 0.95
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	return mi


func _process(dt: float) -> void:
	_vida -= dt
	if _vida <= 0.0:
		queue_free()
		return
	_v.y -= G * dt
	rotation += _giro * dt
	var paso := _v * dt
	if world and paso.length() > 0.0001:
		var h: Dictionary = world.raycast(global_position, paso.normalized(), paso.length() + 0.15)
		if h.get("hit", false):
			_reventar(h["position"])
			return
	global_position += paso
	if is_instance_valid(jugador) and global_position.distance_to(jugador.global_position + Vector3.UP * 1.1) < 1.2:
		_reventar(global_position)


func _reventar(p: Vector3) -> void:
	if ajeno:
		queue_free()
		return
	# ES UNA PIEDRA, NO UN MISIL: el usuario pidio que rompa fuerte pero que suene a piedra. `explode`
	# mete siempre fuego, humo y el estruendo de una granada. El tallado del laser rompe sin nada de eso
	# y sin perder fuerza hacia fuera, asi que con el 60 % del radio abre lo mismo que la explosion
	# (hormigon a 255 caia hasta el 58 % del radio). Replicado, y suena a piedra partiendose para todos.
	if world and world.has_method("carve_beam"):
		var dir := _v.normalized() if _v.length() > 0.01 else Vector3.DOWN
		var r := radio * 0.6
		Net.net_carve_beam(world, p - dir * r * 0.5, dir, r, r, potencia, false)
	Net.net_ruido_rotura(p, 0, int(1500.0 * radio))      # material 0 = piedra/obra
	# `false` = no tumba: perder el equilibrio es cosa de los misiles, no de esto
	Combat.damage_around(get_tree(), p, radio + 0.6, dano, autor, false, true)
	queue_free()
