## Perfilador ligero por fases de GDScript (sólo se imprime en pruebas: --falltest / --bench).
extends Node
static var acc: Dictionary = {}
static var peor: Dictionary = {}     ## el peor tramo de cada clave (us): las medias esconden los bajones
static var frames := 0
static func add(key: String, usec: int) -> void:
	acc[key] = acc.get(key, 0) + usec
	if usec > int(peor.get(key, 0)):
		peor[key] = usec
static func report() -> String:
	var parts: PackedStringArray = []
	var keys := acc.keys()
	keys.sort()
	for k in keys:
		parts.append("%s %.2f/%.0f" % [k, acc[k] / 1000.0 / maxf(1.0, frames), peor.get(k, 0) / 1000.0])
	return " ".join(parts) + " (ms/frame media/peor, %d frames)" % frames
static func reset() -> void:
	acc.clear(); peor.clear(); frames = 0
