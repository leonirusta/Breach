extends SceneTree
## Altura de la pelvis sobre el pie mas bajo: mide la POSE, independiente de "ground".
func _init() -> void:
	var A := load("res://scripts/avatar_animator.gd")
	var a = A.new()
	get_root().add_child(a)
	a.build(1.75, false)
	var sk = a.skeleton
	for cn in ["idle_1", "crouch_idle", "run_fwd", "jump_loop", "swim", "crouch_fwd"]:
		var bk = A._baked(cn)
		var cb: Dictionary = bk["bones"]
		var acc := 0.0
		for si in 8:
			var t: float = bk["dur"] * float(si) / 8.0
			for bname in a.bone_idx.keys():
				if cb.has(bname):
					sk.set_bone_pose_rotation(a.bone_idx[bname], A._sample_baked(cb[bname], t))
			sk.force_update_all_bone_transforms()
			var pel: float = sk.get_bone_global_pose(a.bone_idx["pelvis"]).origin.y
			var f1: float = sk.get_bone_global_pose(a.bone_idx["foot_l"]).origin.y
			var f2: float = sk.get_bone_global_pose(a.bone_idx["foot_r"]).origin.y
			acc += pel - min(f1, f2)
		print("[pose] %-12s pelvis_sobre_pie = %6.3f vox   ground = %+7.3f" % [cn, acc / 8.0, bk["ground"]])
	quit()
