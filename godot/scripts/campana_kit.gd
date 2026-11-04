extends "res://scripts/campana.gd"
## EL KIT DE LOS EPISODIOS DE PUZZLES (2026-09-28). Lo comun de campana4.gd, campana5.gd y los que vengan: piezas de
## malla y colision, rotulos que salen solo en el puzzle que toca, particulas (fuego, vapor, chispas), sonido en
## bucle, tallado determinista (`_tallar_rejilla`, `_cortado`), muros invisibles del json (`muros`), las puertas del
## refugio en cualquier cara (`refugio.salida_cara`), el dano local (fuego, vapor, electricidad), LO QUE SE LLEVA A
## CUESTAS (`_obj4`: el anfitrion dice quien lleva que; `player.carga_lenta`), los bots que se quedan atras, la fase
## que viaja a los invitados ("fase4") y el estado para quien entra tarde ("estado4", `_estado_dict`).
##
## Cada episodio: `rotulo_fase` (id del rotulo -> fase en la que se ve), `_fase_de_rotulos()`, `_estado_dict()` y
## `_bot_fijado(bot)` si mueve bots a mano (barcaza, cabinas).

var rotulo_fase: Dictionary = {}     ## id del rotulo -> la fase en la que se ve (sin entrada: siempre, de cerca)


## La fase con la que se eligen los rotulos (cada episodio la ajusta: "inicio" es la del primer puzzle, etc.)
func _fase_de_rotulos() -> String:
	return fase


## Lo que el anfitrion manda a quien entra tarde (cada episodio lo rellena)
func _estado_dict() -> Dictionary:
	return {}


## Bots que el episodio lleva a mano (en una barcaza, en una cabina): no se les teletransporta
func _bot_fijado(_b: Node) -> bool:
	return false


const TREPABLE := "trepable"


const CARGA_LENTA := 0.72


var hecho: Dictionary = {}          ## "p01".."p20" -> true


var par: Dictionary = {}            ## lo sorteado por el anfitrion


var _carteles: Dictionary = {}


var _llenos: Dictionary = {}


var _pide_de := 1


var _bots_t := 0.0


var _cine_final_hecha := false


var _cine_final_corriendo := false


var _dano_t := 0.0


var _obj4: Dictionary = {}          ## id -> {tipo, estado, pid, pos: Vector3, nodo}


func _c(k: String) -> Dictionary:
	var d = cfg.get(k, {})
	return d if d is Dictionary else {}


func _h(k: String) -> bool:
	return bool(hecho.get(k, false))


func _mn(r) -> Vector3:
	return Vector3(float(r[0]), float(r[1]), float(r[2]))


func _mx(r) -> Vector3:
	return Vector3(float(r[3]), float(r[4]), float(r[5]))


func _centro(r) -> Vector3:
	return (_mn(r) + _mx(r)) * 0.5


func _aabb(r) -> AABB:
	var a := _mn(r)
	return AABB(a, _mx(r) - a)


func _mi_id() -> int:
	return multiplayer.get_unique_id() if _en_red else 1


func _brillo(c: Color, e: float = 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


func _caja_mesh(padre: Node, tam: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = tam
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	padre.add_child(mi)
	return mi


func _cil_mesh(padre: Node, r: float, h: float, pos: Vector3, mat: Material, rot := Vector3.ZERO, segs := 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = segs
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	padre.add_child(mi)
	return mi


func _esfera_mesh(padre: Node, r: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	padre.add_child(mi)
	return mi


func _colision_caja(padre: Node, tam: Vector3, pos: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = tam
	cs.shape = bs
	cs.position = pos
	padre.add_child(cs)
	return cs


func _estatico(nombre: String, pos: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = nombre
	sb.collision_layer = 1
	sb.collision_mask = 0
	add_child(sb)
	sb.global_position = pos
	return sb


func _animable(nombre: String, pos: Vector3) -> AnimatableBody3D:
	var ab := AnimatableBody3D.new()
	ab.name = nombre
	ab.sync_to_physics = true
	ab.collision_layer = 1
	ab.collision_mask = 0
	add_child(ab)
	ab.global_position = pos
	return ab


func _sin_colision(n: Node) -> void:
	for c in n.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = true


func _con_colision(n: Node) -> void:
	for c in n.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = false


func _texto3d(t: String, pos: Vector3, color: Color, tam: int = 64, bill := true, padre: Node = null, giro_y := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = t
	l.font_size = tam
	l.pixel_size = 0.01
	l.modulate = color
	l.outline_size = 12
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED if bill else BaseMaterial3D.BILLBOARD_DISABLED
	l.double_sided = true
	(padre if padre else self).add_child(l)
	if padre:
		l.position = pos
	else:
		l.global_position = pos
	l.rotation.y = giro_y
	return l


var _rotulos_t := 0.0


func _rotulo(id: String, texto: String, p: Vector3, color: Color) -> void:
	_quitar_cartel(id)
	# SIN CARTELES FLOTANTES DE PISTA (2026-09-28, pedido: "que no aparezcan textos flotando diciendo rompe tal cosa
	# para subir; quiero que el jugador piense y mire el entorno"). Las llamadas se quedan (dicen que es cada cosa, para
	# quien lea el codigo), pero ya no pintan nada. Lo impreso EN los objetos (bidones, carteles de puertas, paneles)
	# sigue: eso es parte del mundo, no una pista flotando.
	return
	@warning_ignore("unreachable_code")
	var l := _texto3d(texto, p, color, 52)
	l.visible = false
	_carteles[id] = l


func _rotulos_tick(dt: float) -> void:
	_rotulos_tick_t(dt)


func _rotulos_tick_t(dt: float) -> void:
	_rotulos_t -= dt
	if _rotulos_t > 0.0:
		return
	_rotulos_t = 0.3
	var ojo: Vector3 = jugador.global_position if is_instance_valid(jugador) else Vector3.ZERO
	var f := _fase_de_rotulos()
	for id in _carteles:
		var l = _carteles[id]
		if not is_instance_valid(l):
			continue
		var suyo := String(rotulo_fase.get(id, ""))
		(l as Label3D).visible = (suyo == "" or suyo == f) and (l as Label3D).global_position.distance_to(ojo) < 45.0


func _quitar_cartel(id: String) -> void:
	if _carteles.has(id) and is_instance_valid(_carteles[id]):
		_carteles[id].queue_free()
	_carteles.erase(id)


func _luz(padre: Node, pos: Vector3, color: Color, e: float, rango: float) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.light_color = color
	o.light_energy = e
	o.omni_range = rango
	o.shadow_enabled = false
	padre.add_child(o)
	o.position = pos
	return o


func _linea(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var largo := a.distance_to(b)
	if largo < 0.05:
		mi.visible = false
		return
	mi.visible = true
	mi.global_position = (a + b) * 0.5
	mi.look_at(b, Vector3.UP if absf((b - a).normalized().y) < 0.95 else Vector3.RIGHT)
	mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	mi.scale = Vector3(1.0, largo, 1.0)


func _cuerda(mat: Material, r: float = 0.03) -> MeshInstance3D:
	var c := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 1.0
	cm.radial_segments = 6
	c.mesh = cm
	c.material_override = mat
	c.top_level = true
	add_child(c)
	return c


func _bucle_directo(ruta_ogg: String, padre: Node, pos: Vector3, db: float, alcance: float) -> AudioStreamPlayer3D:
	if not ResourceLoader.exists(ruta_ogg) and not FileAccess.file_exists(ruta_ogg):
		return null
	var st = load(ruta_ogg) if ResourceLoader.exists(ruta_ogg) else AudioStreamOggVorbis.load_from_file(ruta_ogg)
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	var a := AudioStreamPlayer3D.new()
	a.stream = st
	a.unit_size = 10.0
	a.max_distance = alcance
	a.volume_db = db + Audio.master_db
	a.bus = "World"
	padre.add_child(a)
	a.position = pos
	a.play()
	return a


func _bucle_bf(clave: String, padre: Node, pos: Vector3, db: float, alcance: float) -> AudioStreamPlayer3D:
	var a := _bucle_en(Vector3.ZERO, clave, db, alcance)
	if a:
		a.reparent(padre, false)
		a.position = pos
	return a


## Un golpe fuerte: sonido, polvo y temblor de camara para quien este cerca
func _golpe(p: Vector3, fuerza: float, clave: String) -> void:
	Audio.bf3d(clave, p, 6.0, 90.0, Audio.PRI_HIGH)
	var fx = jugador.get("effects") if is_instance_valid(jugador) else null
	if fx and fx.has_method("dust"):
		fx.dust(p + Vector3.UP * 0.4, fuerza)
		fx.dust(p + Vector3(1.2, 0.3, 0.5), fuerza * 0.7)
	if is_instance_valid(jugador) and jugador.has_method("add_shake"):
		var d: float = jugador.global_position.distance_to(p)
		if d < 30.0:
			jugador.add_shake(clampf(0.6 * (1.0 - d / 30.0) * fuerza, 0.05, 0.8))


## Una rejilla de haces que vaporizan los voxels (cada maquina, con el evento: el tallado es determinista)
func _tallar_rejilla(desde: Vector3, dir: Vector3, largo: float, us: Array, vs: Array, eje_u: Vector3, eje_v: Vector3, radio: float) -> void:
	if world == null:
		return
	for u in us:
		for v in vs:
			var o: Vector3 = desde + eje_u * float(u) + eje_v * float(v)
			world.carve_beam(o, dir, largo, radio, 255, true)


## ¿Esta CORTADO? (igual que en el episodio 3) Rodajas de 0,4 m; si alguna se queda por debajo de `umbral` de los
## voxels que tenia al empezar, ya no aguanta.
func _cortado(id: String, k: Array, umbral: float) -> bool:
	var mn := _mn(k)
	var mx := _mx(k)
	var rodajas: Array = []
	var y := mn.y + 0.05
	while y < mx.y - 0.05:
		rodajas.append([Vector3(mn.x, y, mn.z), Vector3(mx.x, minf(y + 0.4, mx.y), mx.z)])
		y += 0.4
	if rodajas.is_empty():
		rodajas.append([mn, mx])
	if not _llenos.has(id):
		var l: Array = []
		for r in rodajas:
			l.append(world.contar_voxels(r[0], r[1]))
		_llenos[id] = l
		return false
	var lleno: Array = _llenos[id]
	for i in mini(rodajas.size(), lleno.size()):
		if int(lleno[i]) <= 0:
			continue
		if world.contar_voxels(rodajas[i][0], rodajas[i][1]) <= int(lleno[i]) * umbral:
			return true
	return false


func _muros_invisibles() -> void:
	for m in cfg.get("muros", []):
		var sb := _estatico("MuroInvisible", _centro(m))
		_colision_caja(sb, _mx(m) - _mn(m), Vector3.ZERO)


func _arreglar_puertas_refugio() -> void:
	var ref: Dictionary = _c("refugio")
	if ref.is_empty():
		return
	var y := float(ref.get("suelo", 1.0))
	if is_instance_valid(_bisagra_entrada):
		_bisagra_entrada.global_position.y = y + 1.35
	if is_instance_valid(_puerta_refugio):
		var ps: Array = ref["puerta_salida"]
		match String(ref.get("salida_cara", "oeste")):
			"oeste":
				_puerta_refugio.rotation.y = PI / 2
				_puerta_refugio.global_position = Vector3(float(ps[0]) + 0.2, y + 1.35, float(ps[1]))
			"este":
				_puerta_refugio.rotation.y = PI / 2
				_puerta_refugio.global_position = Vector3(float(ps[0]) - 0.2, y + 1.35, float(ps[1]))
			"norte":
				_puerta_refugio.rotation.y = 0.0
				_puerta_refugio.global_position = Vector3(float(ps[0]), y + 1.35, float(ps[1]) + 0.2)
			_:
				_puerta_refugio.rotation.y = 0.0
				_puerta_refugio.global_position = Vector3(float(ps[0]), y + 1.35, float(ps[1]) - 0.2)


func _abrir_puerta(sb: StaticBody3D) -> void:
	_sin_colision(sb)
	var tw := sb.create_tween()
	tw.tween_property(sb, "global_position", sb.global_position - sb.global_transform.basis.x * 1.7, 1.2).set_trans(Tween.TRANS_QUAD)
	Audio.bf3d("destru/metal", sb.global_position, -2.0, 30.0, Audio.PRI_MID)


func _cerrar_entrada_refugio() -> void:
	if not is_instance_valid(_bisagra_entrada) or absf(_bisagra_entrada.rotation.y) < 0.01:
		return
	var ref: Dictionary = _c("refugio")
	var pe: Array = ref.get("puerta_entrada", [0, 0])
	var y := float(ref.get("suelo", 1.0))
	var hueco := Vector3(float(pe[0]), y, float(pe[1]))
	if is_instance_valid(jugador):
		var jp: Vector3 = jugador.global_position
		if Vector2(jp.x - hueco.x, jp.z - hueco.z).length() < 1.6:
			jugador.global_position = Vector3(jp.x, jp.y, hueco.z + 1.8)
	var tw := create_tween()
	tw.tween_property(_bisagra_entrada, "rotation:y", 0.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): Audio.bf3d("destru/metal", hueco + Vector3.UP, 0.0, 40.0, Audio.PRI_MID))
	CriaturaScript.barreras.append(AABB(Vector3(hueco.x - 1.2, y - 1.0, hueco.z - 0.8), Vector3(2.4, 5.5, 1.2)))


func _mandar_estado() -> void:
	_evento("estado4", [JSON.stringify(_estado_dict())])


func _textura_bola() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _particulas(padre: Node, pos: Vector3, n: int, vida: float, color_a: Color, color_b: Color, tam: float, aditivo: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = n
	p.lifetime = vida
	var qm := QuadMesh.new()
	qm.size = Vector2(tam, tam)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if aditivo:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _textura_bola()
	qm.material = m
	p.mesh = qm
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([color_a, color_a.lerp(color_b, 0.5), Color(color_b.r, color_b.g, color_b.b, 0.0)])
	p.color_ramp = g
	padre.add_child(p)
	p.position = pos
	return p


var _dano_aviso_t := 0.0


func _dano_local(d: float, empuje: Vector3, aviso: String) -> void:
	if not is_instance_valid(jugador) or bool(jugador.get("invulnerable")):
		return
	_dano_t += d
	if _dano_t >= 4.0:
		if jugador.has_method("take_damage"):
			jugador.take_damage(_dano_t, empuje)
		_dano_t = 0.0
	jugador.global_position += empuje * get_process_delta_time()
	var ahora := Time.get_ticks_msec() * 0.001
	if ahora - _dano_aviso_t > 2.0:
		_dano_aviso_t = ahora
		_mensaje_local(aviso)


func _modelo_obj(tipo: String) -> Node3D:
	var n := Node3D.new()
	if tipo == "bombona":
		var rojo := _mm(Color(0.78, 0.12, 0.08), 0.4, 0.5)
		_cil_mesh(n, 0.2, 0.75, Vector3(0, 0.45, 0), rojo, Vector3.ZERO, 14)
		_esfera_mesh(n, 0.2, Vector3(0, 0.82, 0), rojo)
		_cil_mesh(n, 0.07, 0.14, Vector3(0, 1.05, 0), _mm(Color(0.7, 0.62, 0.3), 0.8, 0.4))
		_cil_mesh(n, 0.22, 0.08, Vector3(0, 0.06, 0), _mm(Color(0.2, 0.2, 0.2), 0.6, 0.5))
		_texto3d("PROPANO", Vector3(0, 0.5, 0.21), Color(0.95, 0.95, 0.95), 16, false, n)
	else:
		var rojo := _mm(Color(0.72, 0.1, 0.07), 0.3, 0.55)
		_caja_mesh(n, Vector3(0.36, 0.48, 0.18), Vector3(0, 0.26, 0), rojo)
		_caja_mesh(n, Vector3(0.24, 0.05, 0.06), Vector3(0, 0.54, 0), _mm(Color(0.15, 0.15, 0.15), 0.4, 0.6))
		_cil_mesh(n, 0.04, 0.08, Vector3(0.13, 0.53, 0), _mm(Color(0.8, 0.7, 0.2), 0.7, 0.4))
		_texto3d("GASOIL", Vector3(0, 0.3, 0.095), Color(0.95, 0.9, 0.3), 14, false, n)
	var brillo := OmniLight3D.new()
	brillo.light_color = Color(1.0, 0.7, 0.3)
	brillo.light_energy = 0.5
	brillo.omni_range = 2.0
	brillo.position = Vector3(0, 0.8, 0)
	brillo.name = "Brillo"
	n.add_child(brillo)
	return n


func _obj_crear(id: String, tipo: String, p: Vector3) -> void:
	var n := _modelo_obj(tipo)
	add_child(n)
	n.global_position = p
	_obj4[id] = {"tipo": tipo, "estado": "suelo", "pid": 0, "pos": p, "nodo": n}


func _nodo_de(pid: int) -> Node3D:
	if pid == _mi_id():
		return jugador
	var r = Net.remotes.get(pid) if _en_red else null
	return r if r != null and is_instance_valid(r) else null


func _vivo_id(pid: int) -> bool:
	if pid == _mi_id():
		return is_instance_valid(jugador) and float(jugador.get("health")) > 0.0 and not bool(jugador.get("spectating"))
	if not _en_red:
		return false
	var r = Net.remotes.get(pid)
	return r != null and is_instance_valid(r) and not bool(Net.dead_players.get(pid, false))


## Lo que lleva cada uno: el anfitrion lo decide y todos lo ven igual
func _obj_estado(id: String, estado: String, pid: int, p: Vector3) -> void:
	if not _obj4.has(id):
		return
	var o: Dictionary = _obj4[id]
	o["estado"] = estado
	o["pid"] = pid
	o["pos"] = p
	var n: Node3D = o["nodo"]
	if not is_instance_valid(n):
		return
	var carga := false
	for oid in _obj4:
		var oo: Dictionary = _obj4[oid]
		if String(oo["estado"]) == "lleva" and int(oo["pid"]) == _mi_id():
			carga = true
	if is_instance_valid(jugador):
		jugador.set("carga_lenta", CARGA_LENTA if carga else 1.0)
	match estado:
		"lleva":
			var quien := _nodo_de(pid)
			if quien == null:
				n.reparent(self, true)
				n.global_position = p
				return
			if quien == jugador and jugador.get("cam") != null:
				n.reparent(jugador.cam, false)
				n.position = Vector3(0.32, -0.62, -0.75)
				n.rotation = Vector3(0.1, 0.4, 0)
			else:
				n.reparent(quien, false)
				n.position = Vector3(0.28, 0.75, -0.35)
				n.rotation = Vector3.ZERO
			(n.get_node("Brillo") as OmniLight3D).visible = false
		"suelo", "puesto":
			n.reparent(self, true)
			n.global_position = p
			n.rotation = Vector3.ZERO
			(n.get_node("Brillo") as OmniLight3D).visible = true
		"usado":
			n.queue_free()
			o["nodo"] = null


func _llevo() -> String:
	for id in _obj4:
		var o: Dictionary = _obj4[id]
		if String(o["estado"]) == "lleva" and int(o["pid"]) == _mi_id():
			return String(id)
	return ""


func _lleva_id(pid: int) -> String:
	for id in _obj4:
		var o: Dictionary = _obj4[id]
		if String(o["estado"]) == "lleva" and int(o["pid"]) == pid:
			return String(id)
	return ""


## El anfitrion: quien muere o cae suelta lo que lleva
func _obj_revisar() -> void:
	for id in _obj4:
		var o: Dictionary = _obj4[id]
		if String(o["estado"]) != "lleva":
			continue
		var pid := int(o["pid"])
		if not _vivo_id(pid):
			var q := _nodo_de(pid)
			var p: Vector3 = q.global_position if q else (o["pos"] as Vector3)
			_evento("obj4", [id, "suelo", 0, p.x, p.y, p.z])


## Los compañeros bot que se quedan atras (tirolina, pasarelas, esclusa...) saltan con el grupo
func _bots_al_dia() -> void:
	var vivos := _jugadores_vivos()
	if vivos.is_empty():
		return
	for b in get_tree().get_nodes_in_group("aliados_pve"):
		if not is_instance_valid(b) or not b.has_method("teletransportar_a"):
			continue
		if _bot_fijado(b):
			continue
		var i := _indice_ruta((b as Node3D).global_position)
		if i < progreso - 2:
			var cerca: Node3D = vivos[0]
			for pl in vivos:
				if (pl as Node3D).global_position.distance_to((b as Node3D).global_position) < cerca.global_position.distance_to((b as Node3D).global_position):
					cerca = pl
			b.teletransportar_a(cerca)


func _poner_fase(f: String, texto: String) -> void:
	super._poner_fase(f, texto)
	if _soy_host:
		_evento("fase4", [f])


func _fase_invitado() -> String:
	return fase


func _u(id: String, pos: Vector3, texto: String, cerca: float = 2.2) -> void:
	_usables.append({"id": id, "pos": pos, "texto": texto, "cerca": cerca})


func _on_pide(accion: String, de: int) -> void:
	_pide_de = de
	if accion == "estado4":
		_mandar_estado()
		return
	# "coger:<id>" de lo que se lleva (bombona, bidones, soplete...): campana.gd se queda con todo lo que empieza
	# por "coger:" (sus objetos van por numero) y no llegaba nunca al episodio
	if accion.begins_with("coger:") and _obj4.has(accion.substr(6)):
		_pide_extra(accion)
		return
	super._on_pide(accion, de)


## Al ganar, la pantalla de resultado espera a que acabe la salida de cine
func _fin(gano: bool) -> void:
	if gano and _cine_final_corriendo:
		var espera := 0.0
		while _cine_final_corriendo and espera < 25.0:
			await get_tree().create_timer(0.25).timeout
			espera += 0.25
	super._fin(gano)


# ======================================================================================================
# DIANAS, CORTES DE CINE Y EXPLOSIONES (del episodio 5; los usan el 5 y el 6)
# ======================================================================================================
const DianaScript := preload("res://scripts/diana_campana.gd")
var _dianas: Dictionary = {}          ## id -> diana
var _corte_cam: Camera3D = null
var _corte_capa: CanvasLayer = null


## Una diana (se le dispara o se la vuela): avisa a esta maquina y la campaña se lo cuenta al anfitrion
func _diana(id: String, centro: Vector3, tam: Vector3) -> StaticBody3D:
	var d: StaticBody3D = DianaScript.new()
	d.name = "Diana_" + id
	d.collision_layer = 1
	d.collision_mask = 0
	d.set("id", id)
	add_child(d)
	d.global_position = centro
	_colision_caja(d, tam, Vector3.ZERO)
	d.connect("golpeada", _on_diana)
	_dianas[id] = d
	return d


func _on_diana(id: String, dano: float, _donde: Vector3) -> void:
	var accion := "diana:%s:%d" % [id, int(dano)]
	if _en_red and not _soy_host:
		Net.net_campana_pide(accion)
	else:
		_on_pide(accion, _mi_id())


## Un corte de camara de cine para todos (la demolicion, la pista, el aterrizaje): `planos` = [[pos, mira, t], ...]
func _corte(planos: Array, dur: float, titulo: String = "") -> void:
	_corte_fin()
	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.far = 900.0
	add_child(cam)
	cam.global_position = planos[0][0]
	cam.look_at(planos[0][1])
	cam.make_current()
	_corte_cam = cam
	_corte_capa = CanvasLayer.new()
	_corte_capa.layer = 30
	add_child(_corte_capa)
	var alto := get_viewport().get_visible_rect().size.y * 0.1
	for arriba in [true, false]:
		var fr := ColorRect.new()
		fr.color = Color.BLACK
		fr.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if arriba else Control.PRESET_BOTTOM_WIDE)
		if arriba:
			fr.offset_bottom = alto
		else:
			fr.offset_top = -alto
		_corte_capa.add_child(fr)
	if titulo != "":
		var l := Label.new()
		l.text = titulo
		l.add_theme_font_size_override("font_size", 30)
		l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6))
		l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		l.position.y -= alto + 40.0
		l.grow_horizontal = Control.GROW_DIRECTION_BOTH
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_corte_capa.add_child(l)
	if hud:
		hud.visible = false
	# las animaciones van atadas a la camara: si otro corte la quita antes, se acaban con ella
	var tw := cam.create_tween()
	for i in range(1, planos.size()):
		var t_i := float(planos[i][2]) - float(planos[i - 1][2])
		var p_i: Vector3 = planos[i][0]
		tw.tween_property(cam, "global_position", p_i, maxf(0.05, t_i)).set_trans(Tween.TRANS_SINE)
	var mirar := func(_k: float) -> void:
		if not is_instance_valid(cam):
			return
		var t := _k * dur
		var j := 0
		while j < planos.size() - 1 and t > float(planos[j + 1][2]):
			j += 1
		var a: Vector3 = planos[j][1]
		var b: Vector3 = planos[mini(j + 1, planos.size() - 1)][1]
		var t0 := float(planos[j][2])
		var t1 := float(planos[mini(j + 1, planos.size() - 1)][2])
		var u := clampf((t - t0) / maxf(0.01, t1 - t0), 0.0, 1.0)
		var m: Vector3 = a.lerp(b, u * u * (3.0 - 2.0 * u))
		if cam.global_position.distance_to(m) > 0.05:
			cam.look_at(m)
	cam.create_tween().tween_method(mirar, 0.0, 1.0, dur)
	var esta := cam.get_instance_id()
	get_tree().create_timer(dur).timeout.connect(func():
		if is_instance_valid(_corte_cam) and _corte_cam.get_instance_id() == esta:
			_corte_fin())


func _corte_fin() -> void:
	if is_instance_valid(_corte_cam):
		_corte_cam.queue_free()
		if is_instance_valid(jugador) and jugador.get("cam") != null:
			jugador.cam.make_current()
		if hud and not terminado:
			hud.visible = true
	_corte_cam = null
	if is_instance_valid(_corte_capa):
		_corte_capa.queue_free()
	_corte_capa = null


## Una explosion de verdad (el anfitrion talla y hace daño; cada maquina, lo que se ve y el daño a su jugador)
func _explosion(p: Vector3, radio: float, dano: float, rompe: float, ya: bool = false) -> void:
	if ya:
		return
	var escena := get_tree().current_scene
	if escena and "effects" in escena and escena.effects and escena.effects.has_method("explosion"):
		escena.effects.explosion(p, radio)
	Audio.explosion(p, radio)
	if is_instance_valid(jugador) and not bool(jugador.get("spectating")):
		var d: float = jugador.global_position.distance_to(p)
		if d < radio * 2.2 and jugador.has_method("take_damage") and not bool(jugador.get("invulnerable")):
			jugador.take_damage(dano * (1.0 - d / (radio * 2.2)), (jugador.global_position - p).normalized() * 7.0 + Vector3.UP * 3.0)
		if jugador.has_method("add_shake") and d < radio * 12.0:
			jugador.add_shake(clampf(radio * 0.12 * (1.0 - d / (radio * 12.0)), 0.05, 0.9))
	if _soy_host and world:
		if rompe > 0.0:
			Net.net_explode(world, p, rompe, 255)
		Combat.damage_around(get_tree(), p, radio * 2.0, dano * 1.5, null, false)
