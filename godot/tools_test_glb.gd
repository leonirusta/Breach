extends SceneTree
## Prueba de importacion: carga una criatura .glb, cuenta mallas y lista sus animaciones.
## godot --headless --path godot -s res://tools_test_glb.gd -- res://criaturas/goliat.glb

func _initialize() -> void:
	var ruta := "res://criaturas/goliat.glb"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("res://"):
			ruta = a
	var ps := load(ruta) as PackedScene
	if ps == null:
		print("[glb] NO CARGA ", ruta)
		quit()
		return
	var n := ps.instantiate()
	var mallas := n.find_children("*", "MeshInstance3D", true, false)
	var ap := n.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var esq: Variant = null if n.find_children("*", "Skeleton3D", true, false).is_empty() else true
	var tris := 0
	var con_color := 0
	var muestra := Color()
	for m in mallas:
		var mesh: Mesh = (m as MeshInstance3D).mesh
		if mesh:
			for s in mesh.get_surface_count():
				tris += mesh.surface_get_array_index_len(s) / 3 if mesh.surface_get_array_index_len(s) > 0 else mesh.surface_get_array_len(s) / 3
				var cols = mesh.surface_get_arrays(s)[Mesh.ARRAY_COLOR]
				if cols != null and cols.size() > 0:
					con_color += 1
					muestra = cols[0]
	print("[glb] %s: mallas=%d tris=%d esqueleto=%s superficies_con_color=%d color_ejemplo=%s" % [ruta, mallas.size(), tris, str(esq != null), con_color, str(muestra)])
	if ap:
		for an in ap.get_animation_list():
			print("[glb]   anim %s  %.2f s" % [an, ap.get_animation(an).length])
	else:
		print("[glb] SIN AnimationPlayer")
	n.free()
	quit()
