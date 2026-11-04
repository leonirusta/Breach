extends RefCounted
## LA LINTERNA SE CORTA EN LA PARED (2026-10-20, bug: "la linterna de un amigo traspasaba las paredes y alumbraba todo;
## y creo que consume rendimiento"). La linterna va SIN SOMBRA a proposito (un foco con sombra que se mueve con la camara
## cuesta demasiado en el movil), asi que su luz pasaba a traves de todo. Aqui, varias veces por segundo, cinco rayos (el
## centro y cuatro hacia el borde del cono) miden hasta donde llega antes de chocar, y el ALCANCE del foco se queda en eso
## (+ un poco, para que alumbre la propia pared): lo de detras ya no recibe luz. Ademas, menos alcance = menos pixeles que
## iluminar. Lo usan la linterna propia (main.gd) y la de los demas (net_player.gd). `--linternasincorte` = como antes.

const CADA_S := 0.12            ## cada cuanto se mide (una luz que se mueve con la mirada no necesita mas)
const MARGEN := 0.8             ## m de luz detras del primer choque (la pared y un poco de suelo delante)
const MINIMO := 2.5             ## nunca menos (pegado a una pared)
static var _apagado: bool = "--linternasincorte" in OS.get_cmdline_user_args()


## Ajusta el alcance de `luz` (un SpotLight3D encendido) a lo que se ve delante. `tope`: su alcance de fabrica.
static func ajustar(luz: SpotLight3D, world, tope: float) -> void:
	if _apagado or luz == null or not luz.visible or world == null or not world.has_method("raycast"):
		if luz:
			luz.spot_range = tope
		return
	var o: Vector3 = luz.global_position
	var b: Basis = luz.global_transform.basis
	var fwd: Vector3 = -b.z
	var abre := tan(deg_to_rad(luz.spot_angle * 0.6))
	var lejos := 0.0
	for d in [Vector2.ZERO, Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var dir: Vector3 = (fwd + b.x * d.x * abre + b.y * d.y * abre).normalized()
		var r: Dictionary = world.raycast(o, dir, tope)
		var dist: float = float(r.get("distance", tope)) if bool(r.get("hit", false)) else tope
		lejos = maxf(lejos, dist)
	luz.spot_range = clampf(lejos + MARGEN, MINIMO, tope)
