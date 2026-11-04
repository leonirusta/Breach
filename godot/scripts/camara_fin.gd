extends Node3D
## LA CAMARA DE CINE DEL FINAL (2026-10-28, pedido: "al salir el mensaje de victoria, la camara se eleva y recorre el mapa
## mostrando toda la destruccion, tipo Hollywood, sin cortes, en bucle hasta salir de la partida"). Las pantallas del final
## van semitransparentes encima.
##
## Rehecha el mismo dia (pedido: "al elevarse traspasa las paredes y el techo; el deslizamiento no es cinematografico"):
## nunca atraviesa nada porque solo se mueve por tramos COMPROBADOS:
## - LA SUBIDA: recta hacia arriba desde tus ojos (y un poco hacia atras) mirandote. Si hay techo encima se para debajo
##   de el; entonces, tras un momento, fundido a negro corto y sigue fuera.
## - LAS ORBITAS: un arco lento alrededor de cada sitio con destruccion (effects.explosiones, agrupadas en 10 m), con el
##   radio recortado en cada angulo por un rayo desde el sitio: siempre del lado de dentro de la primera pared.
## - LOS VUELOS de un sitio al siguiente: sube en vertical (comprobado: cielo libre encima), cruza por encima del tejado
##   mas alto del camino (medido con rayos) y baja en vertical. Las esquinas se redondean sin salir de la zona libre.
## Todo con aceleraciones suaves (cada toma arranca y frena con curva) y la vista amortiguada. --sincamarafin = como antes.

const ALTO_SUBIDA := 9.0       # cuanto sube desde los ojos si hay cielo
const ATRAS_SUBIDA := 5.0      # y cuanto se aparta hacia atras
const MARGEN_TECHO := 0.7
const MARGEN_CRUCERO := 4.0    # por encima del tejado mas alto del vuelo
const ORBITA_S := 6.5
const ORBITA_ARCO := 1.9       # rad (~110 grados)
const ORBITA_R := 11.0
const ORBITA_ALTO0 := 6.5      # la orbita baja de esta altura...
const ORBITA_ALTO1 := 3.2      # ...a esta
const VEL_VUELO := 10.0        # m/s de media en los vuelos
const MAX_SITIOS := 10
const SUAVE_POS := 0.18        # s de amortiguado de la posicion (solo redondea; el camino ya es suave)
const SUAVE_MIRA := 0.35       # s de amortiguado de la vista

var world
var cam: Camera3D
var _tomas: Array = []         # cola del bucle (sin la subida)
var _toma: Dictionary = {}
var _i := -1
var _t := 0.0
var _pos := Vector3.ZERO
var _mira := Vector3.ZERO
var _desde: Transform3D
var _negro: ColorRect
var _tam: Vector3
var _ultima_ok := Vector3.INF


static func empezar(main: Node, w, desde: Camera3D) -> Node3D:
	var c = load("res://scripts/camara_fin.gd").new()
	c.world = w
	c.process_mode = Node.PROCESS_MODE_ALWAYS
	main.add_child(c)
	c._montar(desde)
	return c


func _montar(desde: Camera3D) -> void:
	_tam = world.get_world_size()
	cam = Camera3D.new()
	cam.fov = 58.0
	cam.far = 1200.0
	add_child(cam)
	_desde = desde.global_transform if desde else Transform3D.IDENTITY
	cam.global_transform = _desde
	cam.current = true
	var capa := CanvasLayer.new()
	capa.layer = 40            # debajo de las pantallas del final (45+)
	add_child(capa)
	_negro = ColorRect.new()
	_negro.color = Color(0, 0, 0, 0)
	_negro.set_anchors_preset(Control.PRESET_FULL_RECT)
	_negro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capa.add_child(_negro)
	_pos = _desde.origin
	_mira = _desde.origin - _desde.basis.z * 10.0
	_armar()
	_toma = _tomas[0]
	_i = 0


# --- comprobaciones del mundo ---

func _rayo(o: Vector3, dir: Vector3, largo: float) -> float:
	var h: Dictionary = world.raycast(o, dir, largo)
	return float(h.get("distance", largo)) if bool(h.get("hit", false)) else largo


func _techo_en(x: float, z: float) -> float:
	var h: Dictionary = world.raycast(Vector3(x, _tam.y - 0.5, z), Vector3.DOWN, _tam.y)
	return float(h["position"].y) if bool(h.get("hit", false)) else 0.0


func _cielo(p: Vector3) -> bool:
	for o in [Vector3.ZERO, Vector3(0.4, 0, 0), Vector3(-0.4, 0, 0), Vector3(0, 0, 0.4), Vector3(0, 0, -0.4)]:
		if bool(world.raycast(p + o, Vector3.UP, _tam.y).get("hit", false)):
			return false
	return true


func _hueco(p: Vector3) -> bool:
	return not world.box_solid(p - Vector3(0.45, 0.45, 0.45), p + Vector3(0.45, 0.45, 0.45))


func _libre_entre(a: Vector3, b: Vector3) -> bool:
	var d := a.distance_to(b)
	return d < 0.05 or _rayo(a, (b - a) / d, d) >= d - 0.01


# --- las tomas ---

func _armar() -> void:
	var sitios := _elegir_sitios()
	var orbitas: Array = []
	for s in sitios:
		var o := _orbita(s)
		if not o.is_empty():
			orbitas.append(o)
	# LA SUBIDA (solo la primera vez)
	var ojo := _desde.origin
	var yo := ojo - Vector3(0, 0.9, 0)
	var arriba := minf(ALTO_SUBIDA, _rayo(ojo, Vector3.UP, ALTO_SUBIDA + MARGEN_TECHO) - MARGEN_TECHO)
	arriba = maxf(arriba, 0.0)
	var atras := -_desde.basis.z
	atras.y = 0
	atras = -atras.normalized() if atras.length() > 0.01 else Vector3.BACK
	var top := ojo + Vector3(0, arriba, 0)
	# hacia atras: lo que dejen los rayos a la altura de arriba y a media subida
	var bk := minf(ATRAS_SUBIDA, minf(_rayo(top, atras, ATRAS_SUBIDA + 1.0), _rayo(ojo + Vector3(0, arriba * 0.5, 0), atras, ATRAS_SUBIDA + 1.0)) - 1.0)
	bk = maxf(bk, 0.0)
	var fin_subida := top + atras * bk
	if not _hueco(fin_subida) or not _libre_entre(top, fin_subida):
		fin_subida = top
	var mira_yo := yo if bk > 1.2 else yo - atras * 3.0
	var fuera := _cielo(fin_subida) and arriba >= ALTO_SUBIDA - 0.01
	if arriba >= 1.5:
		_tomas.append({"tipo": "subir", "a": ojo, "b": top, "c": fin_subida, "mira": mira_yo, "dur": 4.5})
	else:
		# techo encima a menos de 1,5 m: no se sube (se quedaria pegada al techo); se sale con el fundido
		fin_subida = ojo
		mira_yo = _desde.origin - _desde.basis.z * 10.0
	if orbitas.is_empty():
		_tomas.append({"tipo": "quieto", "p": fin_subida, "mira": mira_yo, "dur": 999999.0})
		return
	if fuera:
		_tomas.append(_vuelo(fin_subida, mira_yo, orbitas[0]))
	else:
		_tomas.append({"tipo": "quieto", "p": fin_subida, "mira": mira_yo, "dur": 1.8})
		_tomas.append({"tipo": "fundido", "p": fin_subida, "mira": mira_yo, "a": orbitas[0], "dur": 1.2})
	var bucle := _tomas.size()
	for k in orbitas.size():
		_tomas.append(orbitas[k])
		var sig: Dictionary = orbitas[(k + 1) % orbitas.size()]
		if orbitas.size() > 1:
			_tomas.append(_vuelo(_orbita_pos(orbitas[k], 1.0), orbitas[k]["c"] + Vector3(0, 1, 0), sig))
		else:
			# una sola: la misma orbita de vuelta (ida y vuelta, sin saltos)
			_tomas.append(_orbita_vuelta(orbitas[k]))
	set_meta("bucle", bucle)


func _elegir_sitios() -> Array[Vector3]:
	var fx = get_tree().current_scene.get("effects")
	var puntos: Array = fx.explosiones.duplicate() if fx and "explosiones" in fx else []
	var grupos: Array = []          # [centro, cuantas]
	for p in puntos:
		var hecho := false
		for g in grupos:
			if (g[0] as Vector3).distance_to(p) < 10.0:
				g[0] = (g[0] as Vector3).lerp(p, 1.0 / (g[1] + 1.0))
				g[1] += 1
				hecho = true
				break
		if not hecho:
			grupos.append([p, 1])
	grupos.sort_custom(func(a, b): return a[1] > b[1])
	var out: Array[Vector3] = []
	for g in grupos.slice(0, MAX_SITIOS):
		var p: Vector3 = g[0]
		p.y = maxf(p.y - 1.0, 0.0)
		out.append(p)
	if out.size() < 3:
		var c := Vector3(_tam.x * 0.5, 0, _tam.z * 0.5)
		for k in 4:
			var a := TAU * k / 4.0
			var p := c + Vector3(cos(a), 0, sin(a)) * minf(_tam.x, _tam.z) * 0.22
			p.y = _techo_en(p.x, p.z)
			out.append(p)
	# en orden de recorrido: el mas cercano cada vez
	var ord: Array[Vector3] = [out[0]]
	var resto := out.slice(1)
	while not resto.is_empty():
		var u: Vector3 = ord[-1]
		var mejor := 0
		for i in resto.size():
			if (resto[i] as Vector3).distance_to(u) < (resto[mejor] as Vector3).distance_to(u):
				mejor = i
		ord.append(resto[mejor])
		resto.remove_at(mejor)
	return ord


## Un arco alrededor del sitio con el radio recortado por la primera pared en cada angulo. Empieza y acaba con cielo
## encima (para poder llegar y salir en vertical). Vacio si el sitio no tiene un arco asi.
func _orbita(c: Vector3) -> Dictionary:
	const N := 14
	var mejor := {}
	var mejor_r := 0.0
	for k in 12:
		var a0 := TAU * k / 12.0
		var rs: Array[float] = []
		var hs: Array[float] = []
		var ok := true
		var suma := 0.0
		for j in N + 1:
			var f := float(j) / N
			var a := a0 + ORBITA_ARCO * f
			var h := lerpf(ORBITA_ALTO0, ORBITA_ALTO1, _suave(f))
			var dir := Vector3(cos(a), 0, sin(a))
			var o := c + Vector3(0, h, 0)
			if not _hueco(o):
				ok = false
				break
			var r := minf(ORBITA_R, _rayo(o, dir, ORBITA_R + 1.5) - 1.5)
			if r < 4.0:
				ok = false
				break
			rs.append(r)
			hs.append(h)
			suma += r
		if not ok:
			continue
		# el radio cambia despacio: el menor de los vecinos (nunca mas fuera de lo medido)
		var rs2: Array[float] = rs.duplicate()
		for j in rs.size():
			rs2[j] = minf(rs[j], minf(rs[maxi(j - 1, 0)], rs[mini(j + 1, rs.size() - 1)]))
		var o := {"tipo": "orbita", "c": c, "a0": a0, "rs": rs2, "hs": hs, "dur": ORBITA_S}
		if not _cielo(_orbita_pos(o, 0.0)) or not _cielo(_orbita_pos(o, 1.0)):
			continue
		# y entre muestras, sin cortar esquinas
		var cuerdas := true
		for j in N:
			if not _libre_entre(_orbita_pos(o, float(j) / N), _orbita_pos(o, float(j + 1) / N)):
				cuerdas = false
				break
		if cuerdas and suma > mejor_r:
			mejor_r = suma
			mejor = o
	return mejor


func _orbita_pos(o: Dictionary, f: float) -> Vector3:
	var rs: Array = o["rs"]
	var hs: Array = o["hs"]
	var x := clampf(f, 0.0, 1.0) * (rs.size() - 1)
	var j := mini(int(x), rs.size() - 2)
	var u := x - j
	var r := lerpf(rs[j], rs[j + 1], u)
	var h := lerpf(hs[j], hs[j + 1], u)
	var a: float = o["a0"] + ORBITA_ARCO * f
	return o["c"] + Vector3(cos(a) * r, h, sin(a) * r)


func _orbita_vuelta(o: Dictionary) -> Dictionary:
	var v := o.duplicate()
	v["vuelta"] = true
	return v


## Sube en vertical, cruza por encima de todo y baja en vertical al principio de la orbita siguiente
func _vuelo(a: Vector3, mira_a: Vector3, o: Dictionary) -> Dictionary:
	var b := _orbita_pos(o, 0.0)
	var alto := maxf(a.y, b.y) + 3.0
	var d := Vector2(b.x - a.x, b.z - a.z)
	var n := maxi(int(d.length() / 1.5), 1)
	var lado := Vector2(-d.y, d.x).normalized() * 2.0 if d.length() > 0.01 else Vector2.ZERO
	for i in n + 1:
		var q := Vector2(a.x, a.z) + d * (float(i) / n)
		for l in [Vector2.ZERO, lado, -lado]:
			alto = maxf(alto, _techo_en(q.x + l.x, q.y + l.y) + MARGEN_CRUCERO)
	var pts := _redondear(PackedVector3Array([a, Vector3(a.x, alto, a.z), Vector3(b.x, alto, b.z), b]))
	var largo := 0.0
	for i in pts.size() - 1:
		largo += pts[i].distance_to(pts[i + 1])
	return {"tipo": "vuelo", "pts": pts, "largo": largo, "mira_a": mira_a, "mira_b": o["c"] + Vector3(0, 1, 0),
		"dur": clampf(largo / VEL_VUELO, 3.0, 9.0)}


# --- el recorrido ---

static func _suave(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return k * k * k * (k * (k * 6.0 - 15.0) + 10.0)


## Un punto de la polilinea (ya redondeada en _redondear) por distancia recorrida
func _en_poli(pts: PackedVector3Array, s: float) -> Vector3:
	for i in pts.size() - 1:
		var L := pts[i].distance_to(pts[i + 1])
		if s <= L:
			return pts[i].lerp(pts[i + 1], s / L if L > 0.001 else 1.0)
		s -= L
	return pts[pts.size() - 1]


## Las esquinas de arriba del vuelo, en curva (Bezier) de radio 2,5 m: corta solo por el lado de dentro, que esta por
## debajo del crucero lo que mucho 1,8 m y el crucero va 4 m por encima del tejado mas alto
func _redondear(p: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array([p[0]])
	for i in range(1, p.size() - 1):
		var r := minf(2.5, minf(p[i].distance_to(p[i - 1]), p[i].distance_to(p[i + 1])) * 0.45)
		var a := p[i] + (p[i - 1] - p[i]).normalized() * r
		var b := p[i] + (p[i + 1] - p[i]).normalized() * r
		for k in 9:
			var t := k / 8.0
			out.append(a.lerp(p[i], t).lerp(p[i].lerp(b, t), t))
	out.append(p[p.size() - 1])
	return out


func _siguiente() -> void:
	_t = 0.0
	_i += 1
	if _i >= _tomas.size():
		_i = int(get_meta("bucle", 1))
	_toma = _tomas[_i]


func _process(dt: float) -> void:
	if cam == null or _toma.is_empty():
		return
	dt = minf(dt, 0.05)
	_t += dt
	var dur: float = _toma["dur"]
	var k := clampf(_t / dur, 0.0, 1.0)
	var quiero_p := _pos
	var quiero_m := _mira
	var directo := false
	match String(_toma["tipo"]):
		"subir":
			var e := _suave(k)
			var e2 := _suave(clampf((k - 0.25) / 0.75, 0.0, 1.0))
			quiero_p = _toma["a"].lerp(_toma["b"], e) + (_toma["c"] - _toma["b"]) * e2
			quiero_m = (_desde.origin - _desde.basis.z * 10.0).lerp(_toma["mira"], _suave(k * 1.4))
			directo = true
		"quieto":
			quiero_p = _toma["p"]
			quiero_m = _toma["mira"]
		"fundido":
			# medio fundido a negro, salto al principio de la orbita y vuelta (nunca se ve el salto)
			_negro.color.a = 1.0 - absf(k * 2.0 - 1.0)
			if k < 0.5:
				quiero_p = _toma["p"]
				quiero_m = _toma["mira"]
			else:
				var o: Dictionary = _toma["a"]
				quiero_p = _orbita_pos(o, 0.0)
				quiero_m = o["c"] + Vector3(0, 1, 0)
				_pos = quiero_p
				_mira = quiero_m
				directo = true
			if k >= 1.0:
				_negro.color.a = 0.0
		"orbita":
			var f := _suave(k) if not _toma.get("vuelta", false) else 1.0 - _suave(k)
			# velocidad casi constante en el medio, arranque y frenada suaves
			f = lerpf(k if not _toma.get("vuelta", false) else 1.0 - k, f, 0.55)
			quiero_p = _orbita_pos(_toma, f)
			quiero_m = _toma["c"] + Vector3(0, 1.0, 0)
		"vuelo":
			var pts: PackedVector3Array = _toma["pts"]
			quiero_p = _en_poli(pts, float(_toma["largo"]) * _suave(k))
			# arriba mira hacia el sitio siguiente; al principio todavia al de atras
			quiero_m = (_toma["mira_a"] as Vector3).lerp(_toma["mira_b"], _suave(clampf((k - 0.1) / 0.6, 0.0, 1.0)))
	if directo:
		_pos = quiero_p
		if String(_toma["tipo"]) == "subir":
			_mira = quiero_m
	else:
		_pos = _pos.lerp(quiero_p, 1.0 - exp(-dt / SUAVE_POS))
		_mira = _mira.lerp(quiero_m, 1.0 - exp(-dt / SUAVE_MIRA))
	# ultima defensa: si algo (un bloque que cae) ocupa la camara, se queda donde estaba (subir la meteria en el techo)
	if world.box_solid(_pos - Vector3(0.15, 0.15, 0.15), _pos + Vector3(0.15, 0.15, 0.15)) and _ultima_ok != Vector3.INF:
		_pos = _ultima_ok
	else:
		_ultima_ok = _pos
	var dir := _mira - _pos
	if dir.length() > 0.05 and absf(dir.normalized().dot(Vector3.UP)) < 0.995:
		cam.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), _pos)
	else:
		cam.global_position = _pos
	if k >= 1.0:
		_siguiente()
