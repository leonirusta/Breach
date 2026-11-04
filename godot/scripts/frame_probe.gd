## Último nodo en procesar cada frame: mide el tiempo desde el inicio de process/physics (señales del árbol)
## hasta aquí = coste de _process/_physics_process de todos los nodos (scripts + VoxelWorld).
extends Node
var main: Node
func _process(_dt: float) -> void:
	if main:
		main._probe_report("process", Time.get_ticks_usec() - main._probe_t0)
func _physics_process(_dt: float) -> void:
	if main:
		main._probe_report("physics", Time.get_ticks_usec() - main._probe_p0)
