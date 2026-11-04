extends StaticBody3D
## LA CAJA QUE RECIBE LAS BALAS DE UN ESCONDIDO (prop_hunt.gd): del tamaño del mueble en el que se ha convertido. El
## daño se lo pasa a su dueño (la persona o el bot), que es el que muere.

var dueno: Node = null


func take_damage(d: float, push: Vector3 = Vector3.ZERO) -> void:
	if is_instance_valid(dueno) and dueno.has_method("take_damage"):
		if "golpe_tipo" in dueno:
			dueno.golpe_tipo = "bala"
		dueno.take_damage(d, push)


func altura_cabeza() -> float:
	return 99.0           # un mueble no tiene cabeza: nada de tiros a la cabeza


func _get(p: StringName):
	if p == &"health" and is_instance_valid(dueno):
		return dueno.get("health")
	return null
