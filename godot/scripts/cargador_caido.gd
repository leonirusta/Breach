extends Node3D
## CARGADOR VACIO que suelta un soldado al recargar (avatar_animator._soltar_cargador). Cae con la
## velocidad que llevaba en la mano, da un bote corto, se queda tumbado y desaparece a los pocos
## segundos. Sin cuerpo fisico: son tres cajas y no merece la pena meterlas en Jolt.

var vel := Vector3.ZERO
var suelo_y := 0.0
var _giro := Vector3(7.0, 0.0, 2.5)    # rad/s mientras vuela
var _vida := 5.0
var _botes := 0

func _process(dt: float) -> void:
	_vida -= dt
	if _vida <= 0.0:
		queue_free()
		return
	if _botes >= 2:
		return
	vel.y -= 9.8 * dt
	global_position += vel * dt
	rotate_object_local(Vector3.RIGHT, _giro.x * dt)
	rotate_object_local(Vector3.FORWARD, _giro.z * dt)
	if global_position.y <= suelo_y + 0.02 and vel.y < 0.0:
		global_position.y = suelo_y + 0.02
		_botes += 1
		vel = Vector3(vel.x * 0.3, -vel.y * 0.25, vel.z * 0.3)
		_giro *= 0.3
		if _botes >= 2:
			# tumbado de lado, con el rumbo que traia
			var rumbo: float = global_transform.basis.get_euler().y
			global_transform.basis = Basis.from_euler(Vector3(0.0, rumbo, PI * 0.5))
