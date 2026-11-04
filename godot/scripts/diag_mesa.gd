extends Node
## --diagmesa: LA MESA DEL MAPA DE PRUEBAS, EN VIVO. Cada medio segundo cuenta lo que queda de cada pata
## y del tablero (voxels del mundo), que ve el analizador estructural (islas, su centro de masas y su
## apoyo, la peor relacion carga/capacidad, fallos) y que bloques se han soltado alrededor. Solo escribe
## cuando algo cambia. Consola y user://diag_mesa.log.

var world: Node
var player: Node3D

const CENTRO := Vector3(11.0, 0.0, 11.0)
const PATAS := {"-x-z": Vector3(-3, 0, -3), "-x+z": Vector3(-3, 0, 3), "+x-z": Vector3(3, 0, -3), "+x+z": Vector3(3, 0, 3)}

var _log: FileAccess
var _t := 0.0
var _ultimo := ""
var _patas0 := {}
var _techo0 := 0


func _ready() -> void:
	_log = FileAccess.open("user://diag_mesa.log", FileAccess.WRITE)
	if world.has_method("set_struct_debug_enabled"):
		world.set_struct_debug_enabled(true)
	_escribir("=== diagmesa arrancado ===")


func _escribir(t: String) -> void:
	var linea := "[diagmesa %7.2f] %s" % [Time.get_ticks_msec() / 1000.0, t]
	print(linea)
	if _log:
		_log.store_line(linea)
		_log.flush()


func _process(dt: float) -> void:
	_t += dt
	if _t < 0.5 or not is_instance_valid(world):
		return
	_t = 0.0
	# patas: 0,8 m de lado, de 0,8 a 4,8 m de alto. Tablero: 9 x 9 m entre 4,8 y 5,6 m.
	var patas := {}
	for k in PATAS.keys():
		var c: Vector3 = CENTRO + PATAS[k]
		patas[k] = int(world.contar_voxels(Vector3(c.x - 0.45, 0.85, c.z - 0.45), Vector3(c.x + 0.45, 4.75, c.z + 0.45)))
	var techo: int = world.contar_voxels(Vector3(6.4, 4.75, 6.4), Vector3(15.6, 5.7, 15.6))
	if _patas0.is_empty():
		_patas0 = patas.duplicate()
		_techo0 = techo
		_escribir("al empezar: patas %s · tablero %d voxels" % [str(patas), techo])
	var txt_patas := ""
	for k in patas.keys():
		var p0: int = maxi(int(_patas0[k]), 1)
		txt_patas += "%s %d%% " % [k, int(100.0 * float(patas[k]) / float(p0))]
	var st: Dictionary = world.get_stats()
	var estr := "analisis activo %s · islas %s · fallos %s · peor carga %.2f · fragmentos %s" % [
		str(st.get("struct_active", "-")), str(st.get("struct_islands", "-")), str(st.get("struct_failures", "-")),
		float(st.get("struct_worst_ratio", 0.0)), str(st.get("struct_fragments", "-"))]
	# bloques soltados alrededor de la mesa
	var nb := 0
	var vb := 0
	var tablero_bloque := ""
	for bd in world.get_bodies_debug():
		var p: Vector3 = bd.pos
		if Vector2(p.x - CENTRO.x, p.z - CENTRO.z).length() < 8.0:
			nb += 1
			vb += int(bd.voxels)
			if int(bd.voxels) > 5000:            # ~37.000 a 10 cm, ~9.400 a 20 cm
				tablero_bloque = " · TABLERO SUELTO como bloque (%d vox) en %s" % [int(bd.voxels), str(p.snapped(Vector3.ONE * 0.01))]
	# CADA BLOQUE GRANDE de alrededor, con lo que dice de el el motor: donde esta, si se mueve y en que estado
	# lo tiene (anclado = estatico en Jolt; congelado = fundido en el dibujo comun). Para el tablero que
	# "flota": se ve si nacio y se quedo quieto en su sitio o si cayo y se apoya en algo.
	var lista := ""
	for bd in world.get_bodies_debug():
		var pb: Vector3 = bd.pos
		if int(bd.voxels) < 60 or Vector2(pb.x - CENTRO.x, pb.z - CENTRO.z).length() > 8.0:
			continue
		var inf: Dictionary = world.info_cuerpo(bd.rid) if (bd.rid as RID).is_valid() else {}
		lista += "\n     bloque %d vox en %s tam %s%s" % [int(bd.voxels), str(pb.snapped(Vector3.ONE * 0.1)), str(bd.size),
			(" · anclado %s congelado %s parado %s" % [str(inf.get("anclado")), str(inf.get("congelado")), str(inf.get("parado"))]) if inf.get("existe", false) else (" · SIN CUERPO" if not (bd.rid as RID).is_valid() else "")]
	var clave := "patas %s| tablero %d%% | bloques %d (%d vox)%s | %s%s" % [txt_patas,
		int(100.0 * float(techo) / float(maxi(_techo0, 1))), nb, vb, tablero_bloque, estr, lista]
	if clave == _ultimo:
		return
	_ultimo = clave
	_escribir(clave)
	# lo que ve el analizador de cada isla que toque la mesa
	var dbg: Dictionary = world.get_struct_debug() if world.has_method("get_struct_debug") else {}
	for isl in dbg.get("islands", []):
		var com: Vector3 = isl.get("com", Vector3.ZERO)
		if Vector2(com.x - CENTRO.x, com.z - CENTRO.z).length() < 7.0:
			_escribir("   isla %s: masa %s celdas %s · centro de masas %s · apoyo %s · peor carga %.2f" % [
				str(isl.get("id")), str(isl.get("mass")), str(isl.get("cells")), str(com.snapped(Vector3.ONE * 0.01)),
				str((isl.get("support", Vector3.ZERO) as Vector3).snapped(Vector3.ONE * 0.01)), float(isl.get("worst_ratio", 0.0))])
	if not dbg.is_empty():
		_escribir("   analisis: iteracion %s · region %s..%s · islas evaluadas %s (saltadas %s) · celdas %s · fallos %s · %.1f ms" % [
			str(dbg.get("iteration")), str(dbg.get("region_min")), str(dbg.get("region_max")), str(dbg.get("islands_evaluated")),
			str(dbg.get("islands_skipped")), str(dbg.get("cells_evaluated")), str(dbg.get("failures")), float(dbg.get("ms", 0.0))])
