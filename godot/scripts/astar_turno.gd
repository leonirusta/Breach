class_name AstarTurno
## EL A* POR TURNOS. Buscar camino es lo mas caro que hace la IA (hasta ~45 ms una busqueda sin salida en
## un mapa a 10 cm, `--astarmide`), y el tiron de verdad era cuando COINCIDIAN varias en el mismo
## fotograma: seis zombis replanificando a la vez, o un bot que al no encontrar camino probaba nueve
## puntos intermedios seguidos.
##
## Ahora todos (criaturas y bots) piden turno aqui. Cada fotograma de fisica hay un presupuesto de tiempo;
## cuando se gasta, los demas esperan al siguiente fotograma con la ruta que ya tenian, que un fotograma
## de retraso en replanificar no se nota y un tiron si. Siempre pasa al menos una busqueda por fotograma,
## para que nadie se quede sin ruta nunca.

## Microsegundos de A* por fotograma de fisica, entre todos.
const PRESUPUESTO_US := 5000
## TOPE DE NODOS POR BUSQUEDA (2026-09-26, medido con --medirfps en las hordas de la campaña: una sola busqueda
## sin salida -el jugador en un tejado, un bot rodeado- llegaba a 45-55 ms, y como "siempre pasa una por
## fotograma" el presupuesto no la paraba). Con tope, sin completar devuelve el tramo hacia el nodo mas cercano
## a la meta: el bicho avanza por ahi y al acabarlo replanifica. `--sintopeastar` para comparar.
const EXPANSIONES_MAX := 6000
static var sin_tope: bool = "--sintopeastar" in OS.get_cmdline_user_args()

static var _frame := -1
static var _gastado_us := 0
static var _hechas := 0

## ¿Queda turno en este fotograma?
static var sin_turno: bool = "--sinturno" in OS.get_cmdline_user_args()

static func puedo() -> bool:
	_nuevo_frame()
	if sin_turno:
		return true
	return _hechas == 0 or _gastado_us < PRESUPUESTO_US


## Busca camino apuntando lo que ha costado.
static func buscar(world, desde: Vector3, hasta: Vector3, quien: String = "") -> PackedVector3Array:
	_nuevo_frame()
	var t0 := Time.get_ticks_usec()
	var camino: PackedVector3Array = world.find_path(desde, hasta, -1 if sin_tope else EXPANSIONES_MAX)
	var us := Time.get_ticks_usec() - t0
	Prof.add("astar." + quien, us)
	_gastado_us += us
	_hechas += 1
	if quien != "":
		var st: Array = por_quien.get(quien, [0, 0, 0, 0])
		st[0] += 1
		st[1] += us
		st[2] = maxi(st[2], us)
		if camino.is_empty():
			st[3] += 1
		por_quien[quien] = st
	return camino

## quien -> [busquedas, us totales, peor us, vacias] (para --astarpartida)
static var por_quien := {}


## Para medir (--astarpartida): el fotograma con mas A* y cuantos pasaron de 16 ms.
static var peor_us := 0
static var fotogramas_sobre_16 := 0

static func _nuevo_frame() -> void:
	var f := Engine.get_physics_frames()
	if f != _frame:
		peor_us = maxi(peor_us, _gastado_us)
		if _gastado_us > 16000:
			fotogramas_sobre_16 += 1
		_frame = f
		_gastado_us = 0
		_hechas = 0
