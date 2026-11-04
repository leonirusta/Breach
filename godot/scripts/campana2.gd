extends "res://scripts/campana.gd"
## EPISODIO 2 DE LA CAMPAÑA: "EL PUERTO" (campana_puerto, tools/generar_mapa_campana2.py). 2026-09-24.
##
## El helicoptero del episodio 1 se estrella en un patio de vias. De ahi al rio, donde espera un barco. Lo nuevo
## es que EL CAMINO SE ABRE ROMPIENDO:
##   1. EL TAPIADO del tunel bajo las vias: tablones clavados de pared a pared. Hay que romperlos (a tiros, a
##      mazazos, con una explosion). Se da por abierto cuando por algun sitio CABE UNA PERSONA (se prueban
##      huecos de 0,7 x 1,6 m de lado a lado: world.box_solid), no por cuanto se ha roto.
##   2. LA RAMPA de la nave: una viga ancha de acero apoyada ARRIBA de dos pilas de ladrillo, junto al altillo.
##      Se revientan las pilas y la viga cae de un lado: queda de rampa del suelo al altillo. La viga es un
##      objeto (no voxels) para que caiga igual en todas las pantallas; los voxels son las pilas.
##   3. LA BARRICADA de palets del callejon, al salir del refugio.
## Y misiones nuevas: los TRES FUSIBLES del puerto (en las casetas) para dar corriente a la reja del muelle, que
## se abre con la horda encima; y la SIRENA del muelle, que llama al barco y trae el final.
##
## Todo lo decide el anfitrion (como en el episodio 1) y lo avisa por los eventos de la campaña.

const FUSIBLES_N := 3
var _rotos: Dictionary = {}          ## id del rompible -> true cuando ya se pasa
var _rampa_caida := false
var _rampa: Node3D = null            ## el pivote (en la bisagra, el borde del altillo)
var _fusibles_nodos: Array = []      ## [Node3D] (null cuando ya se ha cogido)
var _fusibles_cogidos := 0
var _romper_t := 0.0
var _carteles: Dictionary = {}       ## id -> Label3D (las pintadas de "ROMPED")
var _barco_t := 0.0


# ======================================================================================================
# LA ESCENA
# ======================================================================================================
func _montar_escena() -> void:
	super._montar_escena()
	_montar_rampa()
	_montar_fusibles()
	# (sin las pintadas de "ROMPED" delante de cada pared que se rompe, 2026-09-28: que se vea por el entorno)


## LOS MANDOS (mandos.gd): los fusibles van en el CUADRO ELECTRICO gris de la sala de control (se le pone su
## interruptor grande en la cara que da al muelle), y la SIRENA se toca en la caja amarilla de su poste.
func _mando_porton_def() -> Array:
	var b = (cfg.get("porton", {}) as Dictionary).get("boton", null)
	return [] if b == null else ["interruptor", _v(b) + Vector3(0, 1.3, -0.4), Vector3(0, 0, 1)]


func _mando_radio_def() -> Array:
	var r = cfg.get("radio", null)
	return [] if r == null else ["boton", _v(r) + Vector3(0, 1.2, -1.4), Vector3(0, 0, -1)]


## LA VIGA: 7,2 x 3 m de chapa gruesa con franjas de peligro en los cantos. Pivota sobre el borde del altillo;
## al principio esta horizontal, encima de las pilas.
func _montar_rampa() -> void:
	var rc: Dictionary = cfg.get("rampa", {})
	if rc.is_empty():
		return
	var largo := float(rc.get("largo", 7.2))
	var ancho := float(rc.get("ancho", 3.0))
	_rampa = Node3D.new()
	_rampa.name = "Rampa"
	add_child(_rampa)
	_rampa.global_position = _v(rc["bisagra"])
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(largo, 0.22, ancho)
	cs.shape = bs
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	mi.mesh = bm
	mi.material_override = _mm(Color(0.34, 0.36, 0.38), 0.7, 0.55)
	sb.add_child(mi)
	# las franjas de los cantos y los nervios de debajo
	for lado in [-1, 1]:
		for i in 9:
			var f := MeshInstance3D.new()
			var fm := BoxMesh.new()
			fm.size = Vector3(largo / 9.0 - 0.02, 0.24, 0.18)
			f.mesh = fm
			f.material_override = _mm(Color(0.85, 0.65, 0.05) if i % 2 == 0 else Color(0.05, 0.05, 0.05), 0.3, 0.5)
			f.position = Vector3(-largo / 2 + largo / 9.0 * (i + 0.5), 0.0, lado * (ancho / 2 - 0.09))
			sb.add_child(f)
	for k in 4:
		var n := MeshInstance3D.new()
		var nm := BoxMesh.new()
		nm.size = Vector3(0.14, 0.3, ancho - 0.2)
		n.mesh = nm
		n.material_override = _mm(Color(0.2, 0.2, 0.22), 0.8, 0.5)
		n.position = Vector3(-largo * (k + 0.5) / 4.0, -0.2, 0)
		sb.add_child(n)
	_rampa.add_child(sb)
	sb.position = Vector3(-largo / 2, -0.11, 0)


func _montar_fusibles() -> void:
	for i in (cfg.get("fusibles", []) as Array).size():
		var p: Vector3 = _v(cfg["fusibles"][i])
		var n := Node3D.new()
		n.name = "Fusible%d" % i
		var caja := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.16, 0.34, 0.16)
		caja.mesh = bm
		caja.material_override = _mm(Color(0.95, 0.75, 0.1), 0.2, 0.4)
		n.add_child(caja)
		for s in [-1, 1]:
			var tapa := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.09
			cm.bottom_radius = 0.09
			cm.height = 0.05
			tapa.mesh = cm
			tapa.material_override = _mm(Color(0.7, 0.7, 0.72), 0.9, 0.3)
			tapa.position = Vector3(0, s * 0.19, 0)
			n.add_child(tapa)
		var luz := OmniLight3D.new()
		luz.light_color = Color(1.0, 0.8, 0.2)
		luz.light_energy = 1.2
		luz.omni_range = 3.0
		n.add_child(luz)
		add_child(n)
		n.global_position = p + Vector3.UP * 0.25
		_fusibles_nodos.append(n)


## Al empezar: nada de helicoptero de paso. El vuestro esta ahi, hecho pedazos (con su fuego y su humo).
func _al_empezar() -> void:
	if "--irnave" in OS.get_cmdline_user_args():
		_ir_a_nave.call_deferred()
	var he: Vector3 = _v(cfg.get("heli_estrellado", [0, 0, 0]))
	if he == Vector3.ZERO:
		return
	var h := _modelo_heli()
	for c in h.find_children("*", "AudioStreamPlayer3D", true, false):
		c.queue_free()
	for c in h.find_children("*", "SpotLight3D", true, false):
		c.queue_free()
	add_child(h)
	h.global_position = he + Vector3(0, 1.1, 0)
	h.rotation = Vector3(0.35, 0.9, 0.55)
	if is_instance_valid(_heli_rotor):
		_heli_rotor.rotation = Vector3(0.2, 0.7, 0.4)
		_heli_rotor = null
	_mensaje_local("PILOTO: «...está mordido... no he podido... Salid de aquí. Hay barcos en el RÍO»")


# ======================================================================================================
# LO QUE SE ROMPE (solo el anfitrion mira; avisa a todos)
# ======================================================================================================
func _process_sin_medir(dt: float) -> void:
	super._process_sin_medir(dt)
	_fusibles_giran(dt)
	_barco_tick(dt)
	if (_en_red and not _soy_host) or terminado or world == null:
		return
	_romper_t -= dt
	if _romper_t > 0.0:
		return
	_romper_t = 0.4
	for r in cfg.get("rompibles", []):
		var id := String(r["id"])
		if not _rotos.has(id) and _hay_paso(_v(r["min"]), _v(r["max"])):
			_evento("roto", [id])
	if not _rampa_caida and _pilas_rotas():
		_evento("rampa", [])


## ¿Cabe una persona? Se prueban ventanas de 0,8 x 1,3 m (lo que ocupa uno agachado: capsula de 0,35 m de
## radio) a lo largo del muro y de lado a lado de su grosor. Tres voxels sueltos en el borde no tapan nada.
func _hay_paso(mn: Vector3, mx: Vector3) -> bool:
	var a_lo_largo_x: bool = (mx.x - mn.x) > (mx.z - mn.z)
	var largo: float = (mx.x - mn.x) if a_lo_largo_x else (mx.z - mn.z)
	var y0: float = mn.y + 0.3          # lo que quede a ras de suelo (un escalon) se pasa andando
	var u := 0.45
	while u <= largo - 0.45:
		var b0: Vector3
		var b1: Vector3
		if a_lo_largo_x:
			b0 = Vector3(mn.x + u - 0.4, y0, mn.z)
			b1 = Vector3(mn.x + u + 0.4, y0 + 1.3, mx.z)
		else:
			b0 = Vector3(mn.x, y0, mn.z + u - 0.4)
			b1 = Vector3(mx.x, y0 + 1.3, mn.z + u + 0.4)
		if world.contar_voxels(b0, b1) <= 3:
			return true
		u += 0.3
	return false


## Las dos pilas ya no llegan arriba (su remate, el trozo de 1 m de debajo de la viga, esta vacio)
func _pilas_rotas() -> bool:
	var rc: Dictionary = cfg.get("rampa", {})
	if rc.is_empty():
		return false
	for pila in rc.get("pilas", []):
		var mn: Vector3 = _v(pila[0])
		var mx: Vector3 = _v(pila[1])
		if world.box_solid(Vector3(mn.x, mx.y - 1.0, mn.z), mx):
			return false
	return true


func _evento_extra(e: String, datos: Array) -> void:
	match e:
		"roto":
			var id := String(datos[0])
			_rotos[id] = true
			if _carteles.has(id) and is_instance_valid(_carteles[id]):
				_carteles[id].queue_free()
			_mensaje_local("¡PASO ABIERTO!")
			Audio.ui("objetivo_tomado", -3.0)
		"rampa":
			_tirar_rampa()
		"fusible":
			var i := int(datos[0])
			_fusibles_cogidos = int(datos[1])
			if i < _fusibles_nodos.size() and is_instance_valid(_fusibles_nodos[i]):
				Audio.bf3d("soldado/coger", (_fusibles_nodos[i] as Node3D).global_position, 0.0, 20.0, Audio.PRI_MID)
				_fusibles_nodos[i].queue_free()
			_fusibles_nodos[i] = null
			_mensaje_local("FUSIBLE %d de %d" % [_fusibles_cogidos, FUSIBLES_N])


## LA VIGA CAE: gira sobre el borde del altillo hasta apoyar el otro extremo en el suelo, con un rebote.
func _tirar_rampa() -> void:
	if _rampa_caida or not is_instance_valid(_rampa):
		return
	_rampa_caida = true
	var rc: Dictionary = cfg.get("rampa", {})
	var largo := float(rc.get("largo", 7.2))
	var alto: float = _rampa.global_position.y - float(rc.get("suelo", 1.0))
	var ang := asin(clampf(alto / largo, 0.0, 1.0))
	var tw := create_tween()
	tw.tween_property(_rampa, "rotation:z", ang, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_rampa, "rotation:z", ang - 0.06, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_rampa, "rotation:z", ang, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	var abajo := _rampa.global_position + Vector3(-largo * cos(ang), -alto, 0)
	tw.tween_callback(func():
		_aplastar_pilas()
		Audio.bf3d("destru/metal", abajo, 4.0, 60.0, Audio.PRI_HIGH)
		Audio.bf3d("destru/metal", _rampa.global_position, 0.0, 40.0, Audio.PRI_MID))
	_mensaje_local("¡LA VIGA HA CAÍDO! Subid por ella al ALTILLO")


## AL CAER, LA VIGA APLASTA LO QUE QUEDE DE LAS PILAS: si no, su pie se apoyaba en los munones y dejaba un
## bulto de 2 m al empezar la rampa. Cada maquina lo hace al recibir el evento (el tallado es determinista).
func _aplastar_pilas() -> void:
	var rc: Dictionary = cfg.get("rampa", {})
	for pila in rc.get("pilas", []):
		var mn: Vector3 = _v(pila[0])
		var mx: Vector3 = _v(pila[1])
		var cz := (mn.z + mx.z) * 0.5
		var y := mn.y + 0.35
		while y < mx.y + 0.4:
			world.carve_beam(Vector3(mn.x - 0.3, y, cz), Vector3.RIGHT, (mx.x - mn.x) + 0.6, 0.55, 255, true)
			y += 0.5


func _fusibles_giran(dt: float) -> void:
	for n in _fusibles_nodos:
		if n != null and is_instance_valid(n):
			(n as Node3D).rotation.y += dt * 1.6


# ======================================================================================================
# LA HISTORIA
# ======================================================================================================
func _historia() -> void:
	match fase:
		"inicio":
			_poner_fase("tapiado", "Salid del patio de vías: el túnel está TAPIADO · ¡ROMPEDLO!")
		"tapiado":
			if _rotos.has("tapiado"):
				_poner_fase("nave", "Seguid por la calle hasta la NAVE del fondo")
		"nave":
			if not _rampa_caida and progreso >= _indice_de("nave"):
				_texto = "El ALTILLO no tiene escalera · ¡REVENTAD LAS PILAS que sujetan la viga!"
			if _rampa_caida:
				_poner_fase("camino", "Subid por la viga al ALTILLO y cruzad la pasarela")
		"camino":
			if progreso >= _indice_de("escalera"):
				_texto = "Bajad por la torre y llegad al REFUGIO del callejón"
			var ref: Dictionary = cfg.get("refugio", {})
			if not ref.is_empty() and _todos_dentro(ref["rect"]):
				_poner_fase("refugio", "")
				_llegar_al_refugio()
		"refugio":
			if progreso >= _indice_de("barricada") or _alguien_cerca(_centro_rompible("barricada"), 6.0):
				_poner_fase("barricada", "El callejón está cerrado · ¡ROMPED LA BARRICADA!")
		"barricada":
			if _rotos.has("barricada"):
				_poner_fase("fusibles", "La reja del muelle no tiene corriente · buscad los 3 FUSIBLES en las casetas del puerto")
		"fusibles":
			_texto = "FUSIBLES: %d de %d · buscadlos en las casetas del puerto" % [_fusibles_cogidos, FUSIBLES_N]
			if _fusibles_cogidos >= FUSIBLES_N:
				_poner_fase("porton", "Poned los fusibles en el CUADRO de la sala de control")
		"porton":
			pass
		"abriendo":
			pass
		"muelle":
			if _alguien_cerca(_v(cfg.get("radio", [0, 0, 0])), 14.0):
				_poner_fase("radio", "Tocad la SIRENA del muelle para llamar al barco")
		"final":
			_final_tick()
		"helicoptero":
			_abordar_tick()


func _tras_porton() -> void:
	_poner_fase("muelle", "¡LA REJA ESTÁ ABIERTA! Corred al MUELLE y tocad la sirena")
	_cola.push_front("tanque")
	_mensaje("¡UN TANK!")


func _objetivo_punto() -> Array:
	var sig := func(tope: String) -> Vector3:
		var i := mini(progreso + 1, _indice_de(tope))
		return ruta[clampi(i, 0, ruta.size() - 1)]
	match fase:
		"inicio", "tapiado":
			return [_centro_rompible("tapiado"), "TAPIADO · ROMPEDLO"]
		"nave":
			if progreso >= _indice_de("nave"):
				return [_centro_pilas(), "PILAS · REVENTADLAS"]
			return [sig.call("nave"), "HACIA LA NAVE"]
		"camino":
			if progreso < _indice_de("escalera"):
				return [sig.call("escalera"), "ALTILLO" if progreso < _indice_de("altillo") else "PASARELA"]
			return [sig.call("refugio"), "REFUGIO"]
		"refugio":
			var ps = (cfg.get("refugio", {}) as Dictionary).get("puerta_salida", null)
			return [_v([ps[0], 1.0, ps[1]]) if ps != null else ruta[progreso], "SALIDA DEL REFUGIO"]
		"barricada":
			return [_centro_rompible("barricada"), "BARRICADA · ROMPEDLA"]
		"fusibles":
			var mejor := Vector3.INF
			var d := INF
			var yo: Vector3 = jugador.global_position if is_instance_valid(jugador) else ruta[progreso]
			for n in _fusibles_nodos:
				if n != null and is_instance_valid(n):
					var q: Vector3 = (n as Node3D).global_position
					if q.distance_to(yo) < d:
						d = q.distance_to(yo)
						mejor = q
			if mejor != Vector3.INF:
				return [mejor - Vector3.UP * 0.9, "FUSIBLE (%d/%d)" % [_fusibles_cogidos, FUSIBLES_N]]
		"porton":
			return [_v((cfg.get("porton", {}) as Dictionary).get("boton", [0, 0, 0])), "CUADRO ELÉCTRICO"]
		"abriendo":
			return [_porton.global_position if is_instance_valid(_porton) else ruta[progreso], "REJA · AGUANTA"]
		"muelle", "radio":
			return [_v(cfg.get("radio", [0, 0, 0])), "SIRENA"]
		"final":
			return [_v(cfg.get("helipuerto", [0, 0, 0])), "EMBARCADERO · AGUANTA"]
		"helicoptero":
			return [_v(cfg.get("helipuerto", [0, 0, 0])), "¡AL BARCO!"]
	return [Vector3.INF, ""]


func _centro_rompible(id: String) -> Vector3:
	for r in cfg.get("rompibles", []):
		if String(r["id"]) == id:
			var c: Vector3 = (_v(r["min"]) + _v(r["max"])) * 0.5
			return Vector3(c.x, _v(r["min"]).y, c.z)
	return ruta[progreso]


func _centro_pilas() -> Vector3:
	var rc: Dictionary = cfg.get("rampa", {})
	var c := Vector3.ZERO
	var n := 0
	for pila in rc.get("pilas", []):
		c += (_v(pila[0]) + _v(pila[1])) * 0.5
		n += 1
	return Vector3(c.x / maxi(n, 1), float(rc.get("suelo", 1.0)), c.z / maxi(n, 1))


## HASTA DONDE PUEDEN SALIR BICHOS: nunca al otro lado de lo que aun no esta abierto (se quedarian atascados
## detras del tapiado o bajo el altillo)
func _tope_ruta() -> int:
	if not _rotos.has("tapiado"):
		return _indice_de("tapiado del tunel")
	if not _rampa_caida:
		return _indice_de("bajo la rampa")
	if not _rotos.has("barricada") and fase in ["camino", "refugio", "barricada"]:
		return _indice_de("barricada")
	if fase in ["camino", "refugio", "barricada", "fusibles", "porton", "abriendo"]:
		return _indice_de("sala de control")
	return 999


# ======================================================================================================
# LO QUE SE USA: los fusibles (de todos) y el cuadro / la sirena (del json)
# ======================================================================================================
func _usables_extra(_f: String) -> void:
	if not is_instance_valid(jugador):
		return
	for i in _fusibles_nodos.size():
		var n = _fusibles_nodos[i]
		if n == null or not is_instance_valid(n):
			continue
		if (n as Node3D).global_position.distance_to(jugador.global_position) < 2.4:
			_usables.append({"id": "fusible:%d" % i, "pos": (n as Node3D).global_position, "texto": "COGER EL FUSIBLE", "cerca": 2.4})


func _pide_extra(accion: String) -> void:
	if accion.begins_with("fusible:"):
		var i := int(accion.substr(8))
		if i < _fusibles_nodos.size() and _fusibles_nodos[i] != null:
			_evento("fusible", [i, _fusibles_cogidos + 1])


func _fase_invitado() -> String:
	var t: String = _texto_red
	if t.begins_with("Poned los fusibles"):
		return "porton"
	if t.begins_with("Tocad la SIRENA"):
		return "radio"
	return ""


# ======================================================================================================
# EL BARCO (el final): llega por el rio, para junto al embarcadero y se sube desde su punta
# ======================================================================================================
func _heli_al_rescate() -> void:
	if is_instance_valid(_heli):
		_heli.queue_free()
	var para: Vector3 = _v(cfg.get("barco", [16, 0.55, 125.5]))
	_heli = _modelo_barco()
	add_child(_heli)
	_heli_desde = para + Vector3(150.0, 0, 0)
	_heli_hasta = para
	_heli_dur = 13.0
	_heli_t = 0.0
	_heli_modo = "barco"
	_heli.global_position = _heli_desde


func _heli_tick(dt: float) -> void:
	if _heli_modo != "barco":
		return                   # (el del principio esta estrellado: no se mueve)


func _barco_tick(dt: float) -> void:
	if _heli_modo != "barco" or not is_instance_valid(_heli):
		return
	_heli_t += dt
	_barco_t += dt
	var k: float = clampf(_heli_t / _heli_dur, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 2.5)          # entra rapido y frena al atracar
	var p: Vector3 = _heli_desde.lerp(_heli_hasta, e)
	p.y += sin(_barco_t * 1.3) * 0.06
	_heli.global_position = p
	_heli.rotation = Vector3(sin(_barco_t * 0.9) * 0.025, PI, sin(_barco_t * 1.1) * 0.03)


func _modelo_barco() -> Node3D:
	var b := Node3D.new()
	b.name = "Barco"
	var casco := _mm(Color(0.12, 0.16, 0.2), 0.3, 0.6)
	var blanco := _mm(Color(0.82, 0.83, 0.8), 0.2, 0.5)
	var rojo := _mm(Color(0.6, 0.08, 0.06), 0.2, 0.6)
	var piezas := [
		[Vector3(14.0, 1.6, 4.6), Vector3(0, 0.3, 0), casco],
		[Vector3(14.1, 0.25, 4.7), Vector3(0, 1.2, 0), rojo],
		[Vector3(5.0, 2.4, 3.6), Vector3(1.5, 2.4, 0), blanco],
		[Vector3(5.1, 0.7, 3.7), Vector3(1.5, 2.9, 0), _mm(Color(0.25, 0.4, 0.5), 0.1, 0.1)],
		[Vector3(0.3, 3.0, 0.3), Vector3(2.5, 5.0, 0), casco],
	]
	for pz in piezas:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = pz[0]
		mi.mesh = bm
		mi.material_override = pz[2]
		mi.position = pz[1]
		b.add_child(mi)
	var proa := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(4.6, 3.0, 1.6)
	proa.mesh = pm
	proa.material_override = casco
	proa.rotation = Vector3(PI / 2, 0, -PI / 2)
	proa.position = Vector3(-8.4, 0.3, 0)
	b.add_child(proa)
	var foco := OmniLight3D.new()
	foco.light_color = Color(1.0, 0.95, 0.85)
	foco.light_energy = 3.0
	foco.omni_range = 18.0
	foco.position = Vector3(-4.0, 4.0, 0)
	b.add_child(foco)
	var baliza := OmniLight3D.new()
	baliza.light_color = Color(0.2, 1.0, 0.3)
	baliza.light_energy = 2.0
	baliza.omni_range = 6.0
	baliza.position = Vector3(2.5, 6.6, 0)
	b.add_child(baliza)
	var motor := AudioStreamPlayer3D.new()
	var st = load("res://sounds/l4d2/heli/bucle_lejos1.ogg") if ResourceLoader.exists("res://sounds/l4d2/heli/bucle_lejos1.ogg") else null
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
		motor.stream = st
		motor.pitch_scale = 0.55
		motor.unit_size = 20.0
		motor.max_distance = 300.0
		motor.volume_db = -4.0 + Audio.master_db
		motor.bus = "World"
		motor.autoplay = true
		b.add_child(motor)
	return b


# ======================================================================================================
# --episodio2test: la historia entera sola. Rompe lo rompible A TIROS (world.shoot, lo mismo que un fusil) y
# cuenta cuantos hacen falta; luego recorre, coge los fusibles, abre la reja, toca la sirena, aguanta y sube.
# ======================================================================================================
func _ready() -> void:
	if "--episodio2test" in OS.get_cmdline_user_args():
		_prueba_episodio2.call_deferred()


func _a_tiros(desde: Vector3, centro: Vector3, ancho: Vector2, hasta_que: Callable, tope: int = 600) -> int:
	jugador.global_position = desde
	for n in tope:
		var q := centro + Vector3(0, randf_range(-ancho.y, ancho.y), 0) + (Vector3(0, 0, randf_range(-ancho.x, ancho.x))
			if absf(centro.x - desde.x) > absf(centro.z - desde.z) else Vector3(randf_range(-ancho.x, ancho.x), 0, 0))
		world.shoot(desde, (q - desde).normalized(), 30.0, 60)
		if n % 10 == 9:
			await get_tree().create_timer(0.45).timeout
			if hasta_que.call():
				return n + 1
	return -1


## A MAZAZOS: el mismo tallado que el mazo del jugador (player._mazazo_pared: carve_beam de 0,35 m, radio
## 0,32 y potencia 255), en una rejilla de golpes delante del hueco
func _a_mazazos(fwd: Vector3, centro: Vector3, hasta_que: Callable, tope: int = 80) -> int:
	var lado := fwd.cross(Vector3.UP).normalized()
	var golpes := [Vector2(0, 0.4), Vector2(0, 0.9), Vector2(0, 1.4), Vector2(0.35, 0.4), Vector2(0.35, 0.9), Vector2(0.35, 1.4),
		Vector2(-0.35, 0.4), Vector2(-0.35, 0.9), Vector2(-0.35, 1.4)]
	for n in tope:
		var g: Vector2 = golpes[n % golpes.size()]
		var punto := Vector3(centro.x, 1.0 + g.y, centro.z) + lado * g.x - fwd * 0.2 + fwd * (0.25 * int(n / golpes.size()))
		var r = world.carve_beam(punto - fwd * 0.15, fwd, 0.35, 0.32, 255, false)
		await get_tree().create_timer(0.25).timeout
		if n % 9 == 8:
			print("[ep2]     mazazo %d: %s · voxels en el hueco %d" % [n + 1, str(r), world.contar_voxels(Vector3(centro.x - 0.4, 1.12, centro.z - 0.4), Vector3(centro.x + 0.4, 2.42, centro.z + 0.7))])
		if hasta_que.call():
			return n + 1
	return -1


func _prueba_episodio2() -> void:
	await get_tree().create_timer(4.0).timeout
	jugador.set("invulnerable", true)
	_prueba = true
	var fallos: Array = []
	print("[ep2] fase %s · paso por el tapiado %s · pilas rotas %s" % [fase, str(_hay_paso(_v(cfg["rompibles"][0]["min"]), _v(cfg["rompibles"][0]["max"]))), str(_pilas_rotas())])
	if _rotos.size() > 0 or _rampa_caida:
		fallos.append("ya roto al empezar")
	# 1. el tapiado, a tiros
	var zona_a := Vector3(62.6, 1.1, 21.1)
	var zona_b := Vector3(63.3, 2.9, 22.1)
	print("[ep2] voxels en la zona del tapiado: %d" % world.contar_voxels(zona_a, zona_b))
	var r0: Dictionary = world.shoot(Vector3(58.0, 2.4, 21.6), Vector3(1, 0, 0), 30.0, 60)
	print("[ep2] un tiro: %s" % str(r0))
	await get_tree().create_timer(0.3).timeout
	print("[ep2] voxels tras un tiro: %d" % world.contar_voxels(zona_a, zona_b))
	var tiros := await _a_tiros(Vector3(58.0, 2.4, 21.6), Vector3(62.9, 2.0, 21.6), Vector2(0.45, 0.8), func(): return _rotos.has("tapiado"))
	print("[ep2] tapiado roto con %d tiros · fase %s" % [tiros, fase])
	jugador.global_position = Vector3(61.5, 1.3, 21.6)
	jugador.set("crouching", true)
	for k in 90:
		jugador.velocity.x = 3.0
		jugador.global_position.x += 0.04
		await get_tree().physics_frame
	jugador.set("crouching", false)
	print("[ep2] cruzando el hueco andando: x %.2f (el tapiado esta en 62.9)" % jugador.global_position.x)
	if tiros < 0:
		fallos.append("tapiado")
	await get_tree().create_timer(1.0).timeout
	for i in range(3, 7):
		jugador.global_position = ruta[i] + Vector3(0, 0.4, 0)
		await get_tree().create_timer(0.6).timeout
	print("[ep2] en la nave: fase %s · %s" % [fase, _texto])
	# 2. las pilas, a tiros (a media altura: el trozo de arriba se suelta y cae)
	var rc: Dictionary = cfg["rampa"]
	var total := 0
	for pila in rc["pilas"]:
		var c: Vector3 = (_v(pila[0]) + _v(pila[1])) * 0.5
		var t2 := await _a_tiros(Vector3(c.x - 5.0, 2.2, c.z), Vector3(c.x, 2.0, c.z), Vector2(0.35, 0.25), func():
			return not world.box_solid(Vector3(_v(pila[0]).x, _v(pila[1]).y - 1.0, _v(pila[0]).z), _v(pila[1])))
		total += maxi(t2, 0)
		print("[ep2]   pila: %d tiros" % t2)
	await get_tree().create_timer(2.0).timeout
	print("[ep2] rampa caida %s (%d tiros) · giro %.2f · fase %s" % [str(_rampa_caida), total, _rampa.rotation.z if is_instance_valid(_rampa) else -1.0, fase])
	if not _rampa_caida:
		fallos.append("rampa")
	# LA RAMPA SE PUEDE ANDAR: rayos hacia abajo a lo largo de la viga caida (la fisica de verdad, la que pisa el
	# jugador): tiene que subir sin saltos del suelo al altillo
	var espacio := get_viewport().world_3d.direct_space_state
	var alturas: Array = []
	for k in 8:
		var x: float = _rampa.global_position.x - float(rc["largo"]) * (1.0 - (k + 0.5) / 8.0)
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 8.0, _rampa.global_position.z), Vector3(x, 0.0, _rampa.global_position.z))
		var hr := espacio.intersect_ray(q)
		alturas.append(snappedf(float((hr.get("position", Vector3.ZERO) as Vector3).y), 0.01))
	print("[ep2] la viga caida, de abajo arriba: %s (altillo a %.2f)" % [str(alturas), _rampa.global_position.y])
	for i in range(8, ruta.size()):
		jugador.global_position = ruta[i] + Vector3(0, 0.4, 0)
		await get_tree().create_timer(0.7 if ruta_nombres[i] != "refugio" else 2.0).timeout
		if ruta_nombres[i] == "barricada":
			var c2: Vector3 = _centro_rompible("barricada")
			var rb: Dictionary = world.shoot(Vector3(c2.x - 1.5, 2.4, c2.z - 5.0), Vector3(0, 0, 1), 30.0, 60)
			print("[ep2] tiro a la barricada: %s · voxels en la zona %d" % [str(rb), world.contar_voxels(Vector3(142.1, 1.1, 85.6), Vector3(142.9, 2.5, 86.7))])
			var t3 := await _a_mazazos(Vector3(0, 0, 1), Vector3(c2.x - 1.5, 1.0, 86.0), func(): return _rotos.has("barricada"))
			print("[ep2] barricada rota con %d MAZAZOS · fase %s" % [t3, fase])
			if t3 < 0:
				fallos.append("barricada")
			await get_tree().create_timer(1.0).timeout
		if ruta_nombres[i] == "puerto":
			for f in 3:
				jugador.global_position = _v(cfg["fusibles"][f]) + Vector3(0, -0.5, 1.0 if f != 1 else -1.0)
				await get_tree().create_timer(0.6).timeout
				_usables_tick()
				var id := _usable_mirado
				usar_desde_jugador()
				await get_tree().create_timer(0.6).timeout
				print("[ep2]   fusible %d: boton '%s' · llevais %d · fase %s" % [f + 1, id, _fusibles_cogidos, fase])
		if ruta_nombres[i] == "sala de control":
			jugador.global_position = _v(cfg["porton"]["boton"]) + Vector3(0, 0.4, 0)
			await get_tree().create_timer(0.8).timeout
			_on_pide("porton", 1)
			_abrir_t = 1.0
			await get_tree().create_timer(1.8).timeout
			print("[ep2] reja: fase %s" % fase)
		print("[ep2] ruta %d %s -> progreso %d fase %s" % [i, ruta_nombres[i], progreso, fase])
	jugador.global_position = _v(cfg["radio"]) + Vector3(0, 0.4, 0)
	await get_tree().create_timer(1.2).timeout
	_on_pide("radio", 1)
	print("[ep2] sirena: fase %s" % fase)
	for n in 30:
		await get_tree().create_timer(1.5).timeout
		for c in _vivos:
			c.take_damage(1.0e7)
		_cola.clear()
		if fase == "helicoptero":
			break
	jugador.global_position = _v(cfg["helipuerto"]) + Vector3(0, 0.6, 0)
	await get_tree().create_timer(17.0).timeout
	print("[ep2] barco: terminado %s · episodio apuntado %s" % [str(terminado), str(_mapa() in Settings.campanas_hechas)])
	if not terminado:
		fallos.append("final")
	print("[ep2] %s" % ("TODO BIEN" if fallos.is_empty() else "FALLA: " + ", ".join(fallos)))



## --irnave (para verlo a mano): se salta el tapiado y te deja en la calle, delante de la NAVE de la viga
func _ir_a_nave() -> void:
	await get_tree().create_timer(2.0).timeout
	_rotos["tapiado"] = true
	progreso = maxi(0, _indice_de("nave") - 1)
	if is_instance_valid(jugador):
		jugador.global_position = ruta[progreso] + Vector3.UP * 0.5
	await get_tree().create_timer(0.3).timeout
	for b in get_tree().get_nodes_in_group("aliados_pve"):
		if is_instance_valid(b) and b.has_method("teletransportar_a"):
			b.teletransportar_a(jugador)
