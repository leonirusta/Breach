extends StaticBody3D
## UNA DIANA DE LA CAMPAÑA (2026-09-28): un objeto al que se le puede disparar o volar. Las balas llegan por
## player.fire -> danar_bala (el mismo camino que los vehiculos: saltan chispas y suena la chapa) y las
## explosiones por Combat.damage_around -> take_damage (esta en el grupo "damageable"). Cada maquina avisa a la
## campaña con `golpeada`; la campaña le pide al anfitrion lo que toque (el decide).

signal golpeada(id: String, dano: float, donde: Vector3)

var id := ""
var activa := true


func _ready() -> void:
	add_to_group("damageable")


func danar_bala(dano: float, donde: Vector3, _dir: Vector3) -> bool:
	if not activa:
		return false
	golpeada.emit(id, dano, donde)
	return true


func take_damage(dano: float, _empuje: Vector3 = Vector3.ZERO) -> void:
	if activa:
		golpeada.emit(id, dano * 3.0, global_position)
