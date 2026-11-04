extends Node3D
const EffectsScript := preload("res://scripts/effects.gd")
## Cohete: proyectil recto que explota al tocar voxels, enemigos o escombros.

## Lo que tumba al suelo el cohete a quien pilla vivo (2026-09-30, pedido: un 10 %; antes siempre)
const PROB_TUMBAR := 0.10
var world
var vel := Vector3.ZERO
var life := 6.0
var radius := 4.0
var power := 255
var damage := 130.0
var shooter: Node3D
## Estela: puffs pequeños sembrados por distancia recorrida (no por frame, así no depende de
## los FPS) y con vida corta, para que se deshaga casi al salir.
const TRAIL_STEP := 1.2      # m entre puffs
var effects = null
var _trail_d := 0.0
## COHETE DE OTRO (llega por red). Vuela y deja su estela para que se vea, pero NO rompe ni hace daño:
## el boquete y el daño los reparte la maquina de quien lo disparo, que es la que manda en su tiro.
var ajeno := false

func setup(w, dir: Vector3, s: Node3D, r: float, p: int, d: float) -> void:
	# quien lo tira se apunta cuando: si cambia de arma antes de que llegue, la baja sigue siendo del cohete (Net.arma_de)
	if s != null and is_instance_valid(s):
		s.set_meta("cohete_ms", Time.get_ticks_msec())
	add_to_group("phys_anchor")   # mantiene la colisión del mundo a su alrededor
	world = w
	vel = dir * 48.0
	shooter = s
	radius = r
	power = p
	damage = d
	look_at(global_position + dir, Vector3.UP)
	_estela_bf()


## BF: el rugido del motor del cohete, pegado a el (3D: se oye acercarse, pasar y alejarse), y el silbido
## de pasada cuando cruza cerca de tu cabeza.
var _estela: AudioStreamPlayer3D = null
var _pasado := false
func _estela_bf() -> void:
	if Audio.sin_bf:
		return
	var st: AudioStream = Audio._pick("bf/proyectil/cohete_estela")
	if st == null:
		return
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	_estela = AudioStreamPlayer3D.new()
	_estela.stream = st
	_estela.unit_size = 5.0
	_estela.max_distance = 120.0
	_estela.volume_db = -4.0 + Audio.master_db
	_estela.bus = "World"
	add_child(_estela)
	_estela.play()


func _pasada_bf() -> void:
	if _pasado or not is_instance_valid(shooter):
		return
	var oyente: Vector3 = Audio._listener_pos()
	if oyente == Vector3.INF or shooter.global_position.distance_to(oyente) < 3.0:
		return          # el tuyo no te pasa por al lado
	if global_position.distance_to(oyente) < 9.0:
		_pasado = true
		Audio.bf3d("proyectil/cohete_pasa", global_position, 0.0, 40.0, Audio.PRI_HIGH)

func _physics_process(dt: float) -> void:
	life -= dt
	if life <= 0.0:
		queue_free()
		return
	var from := global_position
	var step := vel * dt
	# estela: un puff cada TRAIL_STEP metros, pequeño y de vida corta
	if effects and effects.has_method("dust"):
		_trail_d += step.length()
		while _trail_d >= TRAIL_STEP:
			_trail_d -= TRAIL_STEP
			effects.dust(from - vel.normalized() * 0.4, 0.28, Color(0.72, 0.70, 0.68))
	var to := from + step
	var q := PhysicsRayQueryParameters3D.create(from, to)
	if shooter:
		q.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var vox: Dictionary = world.raycast(from, vel.normalized(), step.length())
	var hit_pos: Variant = null
	if hit:
		hit_pos = hit.position
	if vox.hit and (hit_pos == null or vox.distance < from.distance_to(hit_pos)):
		hit_pos = vox.position
	if hit_pos != null:
		_explode(hit_pos - vel.normalized() * 0.25)
		return
	global_position = to
	_pasada_bf()

func _explode(p: Vector3) -> void:
	EffectsScript.misil_revienta(p)   # la onda en pantalla es SOLO de los misiles (effects.explosion)
	if ajeno:
		queue_free()               # el estallido de verdad ya viene por su cuenta
		return
	Net.net_explode(world, p, radius, power)
	# el que lo lanzo, si sigue vivo, se apunta las bajas de la explosion
	Combat.damage_around(get_tree(), p, radius * 2.0, damage, shooter if is_instance_valid(shooter) else null, true, true,
		false, Vector3.ZERO, PROB_TUMBAR)
	queue_free()
