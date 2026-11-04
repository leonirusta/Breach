extends Control
## TU ESCUADRA, A LA IZQUIERDA (2026-09-30, battle royale por escuadras: Net.es_escuadras). Pedido: "que se vea la lista
## de la escuadra con su barra de vida". La cabecera con el nombre y el color de la escuadra y, debajo, una fila por
## miembro: tu el primero (TÚ, en amarillo), luego las personas de tu escuadra y los bots que la rellenan (sin nombre de
## bot: COMPAÑERO), cada uno con su vida en tiempo real, los metros a los que esta y tachado si ha caido.
## La vida de las personas llega por Net.vidas (cada uno manda la suya); la de los bots, de su nodo (en el invitado, de
## la copia que manda el anfitrion). La crea zona_br.gd en su capa de interfaz; se repinta cinco veces por segundo.

const TINTA := Color(0.05, 0.04, 0.12, 0.92)
const FONDO := Color(0.07, 0.06, 0.16, 0.74)
const ROJO := Color(0.93, 0.22, 0.36)
const VERDE := Color(0.46, 0.9, 0.3)
const ANCHO := 236.0
const FILA := 36.0

var zona: Node = null
var _t := 0.0
var _fuerte: Font
var _normal: Font
var _max_bot: Dictionary = {}       ## vida mas alta vista a cada bot (su maxima)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fuerte = preload("res://scripts/fuentes.gd").de(800, true)
	_normal = preload("res://scripts/fuentes.gd").de(600, false)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(dt: float) -> void:
	_t -= dt
	if _t <= 0.0:
		_t = 0.2
		queue_redraw()


## [nombre, vida, maxima, caido, metros, es_yo]
func miembros() -> Array:
	var out: Array = []
	var mia := String(Net.my_team())
	if not Net.es_escuadra(mia):
		return out
	var yo = Net.local_player
	var pos_yo := Vector3.ZERO
	if yo != null and is_instance_valid(yo):
		pos_yo = (yo as Node3D).global_position
		var vmax: float = float(yo.vida_max()) if yo.has_method("vida_max") else 100.0
		var vida: float = maxf(0.0, float(yo.get("health")))
		var caido: bool = vida <= 0.0 or bool(yo.get("spectating"))
		out.append(["TÚ", 0.0 if caido else vida, vmax, caido, -1.0, true])
	# las personas de tu escuadra (tambien las que aun estan cargando: salen sin vida)
	var ids: Array = Net.players.keys()
	ids.sort()
	for id in ids:
		if Net.is_online() and int(id) == multiplayer.get_unique_id():
			continue
		if Net.team_of(int(id)) != mia:
			continue
		var v: Array = Net.vidas.get(int(id), [])
		var vida2 := float(v[0]) if v.size() > 0 else -1.0
		var vmax2 := float(v[1]) if v.size() > 1 else 100.0
		var caido2: bool = Net.is_dead(int(id)) or (v.size() > 0 and vida2 <= 0.0)
		var metros := -1.0
		var r = Net.remotes.get(int(id))
		if r != null and is_instance_valid(r):
			metros = pos_yo.distance_to((r as Node3D).global_position)
		out.append([String(Net.players[id].get("name", "JUGADOR")), 0.0 if caido2 else vida2, vmax2, caido2, metros, false])
	# los bots que la rellenan
	var k := 0
	for b in get_tree().get_nodes_in_group("bots"):
		if not is_instance_valid(b) or not ("team" in b) or String(b.team) != mia:
			continue
		k += 1
		var vida3: float = maxf(0.0, float(b.health)) if "health" in b else 0.0
		var clave := b.get_instance_id()
		_max_bot[clave] = maxf(float(_max_bot.get(clave, 100.0)), vida3)
		out.append(["COMPAÑERO %d" % k, vida3, float(_max_bot[clave]), vida3 <= 0.0,
			pos_yo.distance_to((b as Node3D).global_position), false])
	return out


func _draw() -> void:
	var lista := miembros()
	if lista.is_empty():
		return
	var mia := String(Net.my_team())
	var col: Color = Net.color_equipo(mia)
	var vs := get_viewport_rect().size
	var x0 := 14.0
	var y0 := roundf(vs.y * 0.30)
	# la cabecera: franja inclinada del color de la escuadra con su nombre, y cuantos quedan en pie
	var en_pie := 0
	for m in lista:
		if not bool(m[3]):
			en_pie += 1
	var cab := PackedVector2Array([Vector2(x0, y0), Vector2(x0 + ANCHO, y0), Vector2(x0 + ANCHO - 8, y0 + 26), Vector2(x0 - 8, y0 + 26)])
	draw_colored_polygon(cab, col.darkened(0.25))
	draw_colored_polygon(PackedVector2Array([cab[0], cab[1], cab[1] + Vector2(-2, 6), cab[0] + Vector2(-2, 6)]), col.lightened(0.25))
	var titulo := Net.nombre_equipo(mia)
	draw_string_outline(_fuerte, Vector2(x0 + 4, y0 + 20), titulo, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 5, TINTA)
	draw_string(_fuerte, Vector2(x0 + 4, y0 + 20), titulo, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
	var cuenta := "%d/%d EN PIE" % [en_pie, lista.size()]
	var wc: float = _fuerte.get_string_size(cuenta, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string_outline(_fuerte, Vector2(x0 + ANCHO - wc - 14, y0 + 19), cuenta, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, TINTA)
	draw_string(_fuerte, Vector2(x0 + ANCHO - wc - 14, y0 + 19), cuenta, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.92))
	# las filas
	var y := y0 + 30.0
	for m in lista:
		_fila(Vector2(x0, y), m, col)
		y += FILA + 4.0


func _fila(p: Vector2, m: Array, col: Color) -> void:
	var nombre := String(m[0])
	var vida := float(m[1])
	var vmax := maxf(float(m[2]), 1.0)
	var caido := bool(m[3])
	var metros := float(m[4])
	var es_yo := bool(m[5])
	var forma := PackedVector2Array([p, p + Vector2(ANCHO, 0), p + Vector2(ANCHO - 6, FILA), p + Vector2(-6, FILA)])
	draw_colored_polygon(forma, Color(FONDO, 0.5) if caido else FONDO)
	# la tira del color de la escuadra a la izquierda (gris si ha caido)
	draw_colored_polygon(PackedVector2Array([p, p + Vector2(6, 0), p + Vector2(0, FILA), p + Vector2(-6, FILA)]),
		Color(0.45, 0.45, 0.5) if caido else col)
	var col_nombre: Color = Color(1.0, 0.86, 0.3) if es_yo else Color.WHITE
	if caido:
		col_nombre = Color(0.62, 0.62, 0.68)
	var tam := 15
	while tam > 10 and _normal.get_string_size(nombre, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x > ANCHO - 84:
		tam -= 1
	draw_string_outline(_normal, p + Vector2(10, 15), nombre, HORIZONTAL_ALIGNMENT_LEFT, ANCHO - 70, tam, 4, TINTA)
	draw_string(_normal, p + Vector2(10, 15), nombre, HORIZONTAL_ALIGNMENT_LEFT, ANCHO - 70, tam, col_nombre)
	# a la derecha: los metros (o CAÍDO)
	var der := "CAÍDO" if caido else ("%d m" % int(metros) if metros >= 0.0 else "")
	if der != "":
		var wd: float = _fuerte.get_string_size(der, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string_outline(_fuerte, p + Vector2(ANCHO - wd - 12, 15), der, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, TINTA)
		draw_string(_fuerte, p + Vector2(ANCHO - wd - 12, 15), der, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			ROJO.lightened(0.2) if caido else Color(0.85, 0.9, 1.0))
	# la barra de vida, inclinada como la fila: roja cuando queda poco
	var bx := p.x + 10.0
	var by := p.y + 22.0
	var bw := ANCHO - 30.0
	var bh := 8.0
	var fondo_b := PackedVector2Array([Vector2(bx, by), Vector2(bx + bw, by), Vector2(bx + bw - 2, by + bh), Vector2(bx - 2, by + bh)])
	draw_colored_polygon(fondo_b, Color(1, 1, 1, 0.14))
	if caido:
		draw_line(Vector2(bx, by + bh * 0.5), Vector2(bx + bw, by + bh * 0.5), Color(0.62, 0.62, 0.68, 0.7), 2.0)
		return
	if vida < 0.0:
		return                      # aun no ha llegado su vida
	var k := clampf(vida / vmax, 0.0, 1.0)
	if k <= 0.0:
		return
	var c_barra: Color = VERDE.lerp(ROJO, clampf((0.55 - k) / 0.4, 0.0, 1.0))
	draw_colored_polygon(PackedVector2Array([Vector2(bx, by), Vector2(bx + bw * k, by), Vector2(bx + bw * k - 2, by + bh),
		Vector2(bx - 2, by + bh)]), c_barra)
