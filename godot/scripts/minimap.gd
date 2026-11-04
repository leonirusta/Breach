extends Control
## CUANTO DURA LA MARCA DE UN DISPARO en el minimapa, en segundos.
const MARCA_S := 1.0
## Disparos recientes: {"pos", "team", "t"}. Es estatico porque quien dispara (un bot, un jugador de
## la red) no conoce al minimapa ni tiene por que: deja el aviso aqui y el minimapa lo recoge.
static var _disparos: Array = []


## Lo llama cualquiera que dispare. Solo se dibujara si el bando NO es el tuyo.
## SITIOS QUE PONE EL MODO DE JUEGO (id -> {pos, color}). El PvE marca aqui el puesto de empezar la
## oleada mientras esta fuera, para saber donde queda cuando lo pierdes de vista. No caducan solos:
## los quita quien los puso (y al entrar en una partida nueva se limpian).
static var sitios: Dictionary = {}

static func marcar_sitio(id: String, pos: Vector3, color: Color, flecha: bool = false) -> void:
	sitios[id] = {"pos": pos, "color": color, "flecha": flecha}


static func quitar_sitio(id: String) -> void:
	sitios.erase(id)


static func marcar_disparo(pos: Vector3, team: String) -> void:
	_disparos.append({"pos": pos, "team": team, "t": Time.get_ticks_msec() * 0.001})
	if _disparos.size() > 40:
		_disparos.remove_at(0)

## MINIMAPA (arriba a la derecha). No renderiza el mundo otra vez: eso sería una segunda pasada
## completa de la escena y a 60 fps no cabe. En vez de eso SONDEA la rejilla de voxels con rayos
## verticales sobre una cuadrícula y guarda el resultado en una imagen, que se repinta sólo cuando
## te alejas del centro del último sondeo. El coste se reparte en varios frames.
##
## Encima de esa imagen se dibuja lo vivo: tú (flecha), los compañeros y rivales, los sitios de
## bomba y la C4 plantada.

const GRID := 72               ## muestras por lado
const SPAN := 90.0             ## m que abarca el minimapa
const REBUILD_DIST := 18.0     ## m que te puedes alejar antes de rehacer el sondeo
const ROWS_PER_FRAME := 6      ## filas sondeadas por frame (el sondeo entero tarda ~12 frames)

var player: Node3D = null
var world = null
var main = null

var _img: Image
var _tex: ImageTexture
var _center := Vector3.ZERO     # centro del sondeo en curso / terminado
var _scan_center := Vector3.ZERO
var _scan_row := GRID           # GRID = no hay sondeo en marcha
var _ready_once := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true          # los circulos de la zona son mucho mas grandes que el minimapa
	custom_minimum_size = Vector2(168, 168)
	size = Vector2(168, 168)
	_img = Image.create(GRID, GRID, false, Image.FORMAT_RGBA8)
	_img.fill(Color(0.06, 0.07, 0.09, 0.85))
	_tex = ImageTexture.create_from_image(_img)


func setup(p: Node3D, w, m) -> void:
	player = p
	world = w
	main = m


func _process(_dt: float) -> void:
	var _pf0 := Time.get_ticks_usec()
	_process_sin_medir(_dt)
	Prof.add("minimapa", Time.get_ticks_usec() - _pf0)


func _process_sin_medir(_dt: float) -> void:
	if player == null or world == null:
		return
	# SOLO EN BOMBA (2026-09-28, pedido): en los demas modos el minimapa no se ve (ni se pinta: no cuesta nada)
	var ver: bool = main != null and bool(main.get("bomb_mode"))
	if visible != ver:
		visible = ver
	if not ver:
		return
	# TOCARLO ABRE EL MAPA GRANDE, pero solo en el battle royale: en los demas mapas no hay mapa grande y el
	# minimapa sigue sin comerse los toques (ni los clics) de lo que tenga debajo
	mouse_filter = Control.MOUSE_FILTER_STOP if _zona() != null else Control.MOUSE_FILTER_IGNORE
	if _scan_row < GRID:
		_scan_rows()
	elif not _ready_once or player.global_position.distance_to(_center) > REBUILD_DIST:
		_scan_center = player.global_position
		_scan_row = 0
	queue_redraw()


## Sondea unas cuantas filas: un rayo vertical por celda. Si toca, se pinta según la altura; si no,
## queda transparente (calle, hueco, fuera del mapa).
func _scan_rows() -> void:
	var step := SPAN / float(GRID)
	var base := _scan_center - Vector3(SPAN * 0.5, 0, SPAN * 0.5)
	var top: float = world.get_world_size().y - 0.5
	var eye_y: float = _scan_center.y
	for _r in ROWS_PER_FRAME:
		if _scan_row >= GRID:
			break
		var z := _scan_row
		for x in GRID:
			var p := base + Vector3((x + 0.5) * step, 0, (z + 0.5) * step)
			var hit: Dictionary = world.raycast(Vector3(p.x, top, p.z), Vector3.DOWN, top)
			var col := Color(0, 0, 0, 0)
			if hit.hit:
				var h: float = hit.position.y
				var rel: float = clampf((h - eye_y + 6.0) / 18.0, 0.0, 1.0)
				# gris azulado por altura: lo que está a tu nivel o por encima, más claro
				col = Color(0.16, 0.18, 0.22).lerp(Color(0.72, 0.76, 0.84), rel)
				col.a = 0.92
			_img.set_pixel(x, z, col)
		_scan_row += 1
	_tex.update(_img.duplicate())   # copia: con el hilo de render separado la subida se hace despues
	if _scan_row >= GRID:
		_center = _scan_center
		_ready_once = true


func _zona():
	var zb = main.get("zona_br") if main else null
	return zb if (zb != null and is_instance_valid(zb)) else null


func _gui_input(event: InputEvent) -> void:
	var toca: bool = (event is InputEventScreenTouch and event.pressed) or \
		(event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if toca and _zona() != null:
		_zona().alternar_mapa()
		accept_event()


func _world_to_map(p: Vector3) -> Vector2:
	# el mapa está fijo (norte arriba); el que gira es el icono del jugador
	var rel := Vector2(p.x - _center.x, p.z - _center.z) / SPAN + Vector2(0.5, 0.5)
	return rel * size


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.03, 0.035, 0.045, 0.82), true)
	if _ready_once:
		draw_texture_rect(_tex, r, false, Color(1, 1, 1, 1))
	draw_rect(r, Color(0.45, 0.47, 0.52, 0.9), false, 2.0)
	if player == null:
		return

	# sitios de bomba, SOLO EN MODO BOMBA. En la ciudad y en hangar se generan solos aunque no haya
	# bomba, y salian igual: dos circulos naranjas con A y B que no marcaban nada y confundian con el
	# objetivo del atraco.
	if main and "bomb_sites" in main and bool(main.get("bomb_mode")):
		var names := ["A", "B", "C"]
		for i in main.bomb_sites.size():
			var sp: Vector2 = _world_to_map(main.bomb_sites[i].pos)
			if r.has_point(sp):
				draw_circle(sp, 9.0, Color(0.9, 0.55, 0.15, 0.35))
				draw_string(ThemeDB.fallback_font, sp + Vector2(-4, 5), names[i % 3],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.82, 0.3))

	# LA ZONA DEL BATTLE ROYALE (zona_br.gd): el muro en azul y la que viene en blanco. Si la que viene queda
	# fuera del minimapa, una flecha en el borde dice hacia donde ir
	var zb = main.get("zona_br") if main else null
	if zb != null and is_instance_valid(zb) and zb.en_marcha:
		var px: float = size.x / SPAN
		var mz: Vector3 = zb.muro()
		if mz.y < zb.RADIO_INICIAL - 1.0:
			draw_arc(_world_to_map(mz), mz.y * px, 0.0, TAU, 128, Color(0.3, 0.5, 1.0, 0.95), 2.5, true)
		var sg = zb.siguiente()
		if sg != null:
			var cz: Vector2 = _world_to_map(sg)
			draw_arc(cz, maxf(sg.y, 1.0) * px, 0.0, TAU, 128, Color(1, 1, 1, 0.9), 1.5, true)
			var fuera: bool = Vector2(player.global_position.x - sg.x, player.global_position.z - sg.z).length() > sg.y
			if fuera and not r.grow(-6.0).has_point(cz):
				var yo: Vector2 = _world_to_map(player.global_position)
				var d: Vector2 = (cz - yo).normalized()
				var punta: Vector2 = size * 0.5 + d * (size.x * 0.46)
				var lado := Vector2(-d.y, d.x)
				draw_colored_polygon(PackedVector2Array([punta, punta - d * 11.0 + lado * 6.0, punta - d * 11.0 - lado * 6.0]),
					Color(1, 1, 1, 0.95))

	# SITIOS FIJOS DEL MODO (el puesto de empezar oleada del PvE): laten despacio para que se vean
	for s in sitios.values():
		var sp: Vector2 = _world_to_map(s["pos"] as Vector3)
		var col: Color = s["color"]
		if r.has_point(sp):
			var lat: float = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.006)
			draw_circle(sp, 5.0, Color(col, lat))
			draw_arc(sp, 8.5, 0.0, TAU, 22, Color(col, 0.85), 1.6, true)
		elif bool(s.get("flecha", false)):
			# FUERA DEL MINIMAPA: una flecha en el borde hacia donde queda (el objetivo de la campaña)
			var yo2: Vector2 = _world_to_map(player.global_position)
			var d2: Vector2 = (sp - yo2).normalized()
			var punta2: Vector2 = size * 0.5 + d2 * (size.x * 0.46)
			var lado2 := Vector2(-d2.y, d2.x)
			draw_colored_polygon(PackedVector2Array([punta2, punta2 - d2 * 12.0 + lado2 * 7.0, punta2 - d2 * 12.0 - lado2 * 7.0]), col)

	# C4 plantada: parpadea
	if is_instance_valid(Net.bomb_node):
		var bp: Vector2 = _world_to_map(Net.bomb_node.global_position)
		if r.has_point(bp):
			var k: float = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.012)
			draw_circle(bp, 5.0, Color(1.0, 0.25, 0.2, k))

	# LOS COMPANEROS, SIEMPRE. Saber donde esta tu equipo no es hacer trampa, es coordinarse.
	for rp in Net.remotes.values():
		if not is_instance_valid(rp):
			continue
		if not (Net.team_of(rp.peer_id) == Net.my_team() and Net.my_team() != ""):
			continue
		if Net.todos_contra_todos():
			continue                        # todos contra todos: nadie es compañero (en escuadras, si)
		var pp: Vector2 = _world_to_map(rp.global_position)
		if r.has_point(pp):
			draw_circle(pp, 4.5, Color(0.35, 0.85, 0.45))

	# LOS ENEMIGOS, SOLO AL DISPARAR. Antes salian como puntos rojos fijos: sabias donde estaban
	# TODOS, todo el rato, y eso quita el juego entero -no hay a quien flanquear ni de quien
	# esconderse si el mapa te lo enseña-. Ahora el punto aparece cuando alguien dispara y se apaga
	# en un segundo: te dice DESDE DONDE vino el tiro, que es lo que de verdad oirias, y nada mas.
	var ahora: float = Time.get_ticks_msec() * 0.001
	var i := 0
	while i < _disparos.size():
		var d: Dictionary = _disparos[i]
		var edad: float = ahora - float(d["t"])
		if edad > MARCA_S:
			_disparos.remove_at(i)
			continue
		i += 1
		if String(d["team"]) == Net.my_team() and Net.my_team() != "":
			continue                      # un tiro tuyo o de un companero no delata a nadie
		var dp: Vector2 = _world_to_map(d["pos"] as Vector3)
		if not r.has_point(dp):
			continue
		# se apaga hacia el final en vez de desaparecer de golpe
		var a: float = clampf(1.0 - edad / MARCA_S, 0.0, 1.0)
		draw_circle(dp, 4.0 + 2.0 * (1.0 - a), Color(0.95, 0.35, 0.25, a))

	# tú: flecha que gira con la cámara
	var me: Vector2 = _world_to_map(player.global_position)
	var yaw: float = -player.rotation.y
	var tip := me + Vector2(sin(yaw), -cos(yaw)) * 9.0
	var l := me + Vector2(sin(yaw + 2.5), -cos(yaw + 2.5)) * 7.0
	var rr := me + Vector2(sin(yaw - 2.5), -cos(yaw - 2.5)) * 7.0
	draw_colored_polygon(PackedVector2Array([tip, l, me, rr]), Color(1.0, 0.85, 0.15))
