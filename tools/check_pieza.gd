extends SceneTree
## Comprueba que una pieza ENTERA (las de Blender, con `tapa`) llega de verdad a la malla.
## Godot ... --headless --path godot --script res://../tools/check_pieza.gd
func _init() -> void:
	var A := load("res://scripts/avatar_animator.gd")
	var rig: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://avatar/soldier_rig.json"))
	var pal: Array = JSON.parse_string(FileAccess.get_file_as_string("res://avatar/palette.json"))
	var pz: Dictionary = rig["piezas"]["heraldo_pro"]
	var n := 0
	for k in pz["vox"]:
		n += pz["vox"][k].size()
	print("[pz] heraldo_pro: %d huesos, %d voxels, tapa=%d" % [pz["vox"].size(), n, pz.get("tapa", []).size()])
	print("[pz] paleta=%d colores_soldado=%d c0=%d" % [pal.size(), int(rig.get("colores_soldado", -1)),
		pal.size() - int(rig.get("colores_soldado", 0))])
	var a = A.new()
	get_root().add_child(a)
	a.build(1.75, false, Color(1, 1, 1), true, false, "Heraldo Forjado", {"piezas": ["heraldo_pro"]})
	var aabb: AABB = a.mesh_inst.get_aabb()
	print("[pz] malla puesta: AABB tam=%s" % str(aabb.size))
	quit()
