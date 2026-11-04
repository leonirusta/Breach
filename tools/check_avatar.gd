extends SceneTree
## Verificacion headless del avatar: construye el rig y comprueba huesos, escala y suelo.
func _init() -> void:
	var A := load("res://scripts/avatar_animator.gd")
	var a = A.new()
	get_root().add_child(a)
	a.build(1.75, false)
	print("[chk] huesos=%d" % a.bone_idx.size())
	print("[chk] escala=%s" % str(a.scale))
	var sk = a.skeleton
	print("[chk] raiz=%s padre_de_pelvis=%s" % [sk.get_bone_name(0), sk.get_bone_name(sk.get_bone_parent(a.bone_idx["pelvis"]))])
	var aabb: AABB = a.mesh_inst.get_aabb()
	print("[chk] AABB tam=%s pos=%s" % [str(aabb.size), str(aabb.position)])
	for cn in ["idle_1", "crouch_idle", "run_fwd"]:
		a.play(cn)
		print("[chk] clip %s ok" % cn)
	for cn in ["idle_1", "crouch_idle", "run_fwd", "jump_loop", "swim"]:
		var bk = A._baked(cn)
		print("[chk] ground %-12s = %+.4f  (dur %.2f)" % [cn, bk["ground"], bk["dur"]])
	for pair in [["shoulder_l","shoulder_r"],["hand_l","hand_r"]]:
		var l: Vector3 = sk.get_bone_global_pose(a.bone_idx[pair[0]]).origin
		var r: Vector3 = sk.get_bone_global_pose(a.bone_idx[pair[1]]).origin
		print("[chk] %s y=%.3f  %s y=%.3f  dY=%+.4f" % [pair[0], l.y, pair[1], r.y, r.y - l.y])
	quit()
