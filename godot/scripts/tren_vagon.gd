extends PhysicsBody3D
## Un vagon del tren de la habitacion (tren_cuarto.gd): las balas y las explosiones se las pasa al tren.


func danar_bala(d: float, punto: Vector3, _dir: Vector3) -> bool:
	var t = get_meta("tren") if has_meta("tren") else null
	if t == null:
		return false
	t.golpe_en(int(get_meta("tren_i")), d, punto)
	return true


func take_damage(d: float, _push: Vector3 = Vector3.ZERO) -> void:
	var t = get_meta("tren") if has_meta("tren") else null
	if t != null:
		t.danar(int(get_meta("tren_i")), d, global_position + Vector3(0, 1, 0))


## un tiro o un mazazo con el punto del golpe: rompe el pedazo de ahi (player.gd lo llama antes que take_damage)
func golpe_en(d: float, punto: Vector3) -> void:
	var t = get_meta("tren") if has_meta("tren") else null
	if t != null:
		t.golpe_en(int(get_meta("tren_i")), d, punto)
