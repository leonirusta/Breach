extends "res://scripts/marcador_cs2.gd"
## EL MARCADOR DEL DUELO SIN REAPARECER (2026-10-15, pedido: "uno especial para este modo; el de bomba es muy CS:GO").
## Con la letra y las formas del marcador del duelo (marcador_hud.gd): barra oscura con los lados en diagonal y la caja
## de en medio en hexagono, del color del que va ganando.
##
##   (o)(o)(o)(o)  [ RONDA 2 · ●○ ○○ ]  (o)(o)(o)(o)
##        3 EN PIE                         4 EN PIE
##
##   - a la izquierda TU equipo (azul), a la derecha el rival (rojo): un medallon redondo por jugador; al caer se pone
##     gris con una raya y da un fogonazo rojo; al revivirlo con RCP vuelve a color con un destello blanco. El tuyo, con
##     aro dorado.
##   - en medio, la ronda y dos puntos por equipo (las rondas para ganar, Main.ELIM_RONDAS).
##   - ULTIMO EN PIE: tu a la izquierda, los rivales a la derecha y en medio cuantos quedan vivos.
## Los datos los saca el padre (marcador_cs2._mirar). Lo crea hud.build_match_hud.

const AZUL := Color(0.18, 0.56, 1.0)
const ROJO := Color(0.95, 0.26, 0.36)
const MORADO := Color(0.62, 0.36, 0.93)
const ORO := Color(1.0, 0.82, 0.22)
const MED := 15.0             ## radio del medallon
const MAX_MED := 5
const ALTO_E := 52.0
const ANCHO_CAJA := 150.0
var _cambios: Dictionary = {}   ## nombre -> [vivo, instante del cambio]


func _ancho() -> float:
	return ANCHO_CAJA + 2.0 * (30.0 + MAX_MED * (MED * 2.0 + 5.0)) + 40.0


func _ready() -> void:
	super._ready()
	size = Vector2(_ancho(), ALTO_E + 26)


## [izq, der]: mi equipo y el rival (en ultimo en pie el padre ya pone: yo en _ct, los rivales en _t)
func _lados() -> Array:
	if _ffa:
		return [_ct, _t]
	if Net.my_team() == Net.TEAM_T:
		return [_t, _ct]
	return [_ct, _t]


func _rondas_lados() -> Array:
	if Net.my_team() == Net.TEAM_T:
		return [int(_rondas[1]), int(_rondas[0])]
	return [int(_rondas[0]), int(_rondas[1])]


func _draw_ui() -> void:
	var w := size.x
	var h := ALTO_E
	var c := w * 0.5
	var ahora := Time.get_ticks_msec() * 0.001
	var lados := _lados()
	var vivos := [0, 0]
	for k in 2:
		for f in lados[k]:
			if bool(f[1]):
				vivos[k] += 1
	# la barra
	draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w - 24, h), Vector2(24, h)]),
		Color(0.14, 0.13, 0.19, 0.88))
	draw_line(Vector2(24, h), Vector2(w - 24, h), Color(1, 1, 1, 0.18), 2.0)
	# la caja de en medio, del color del que va ganando
	var rl := _rondas_lados()
	var cr := MORADO.lightened(0.2)
	if _ffa:
		cr = ORO.darkened(0.1) if vivos[0] > 0 else ROJO
	elif rl[0] > rl[1]:
		cr = AZUL.lightened(0.1)
	elif rl[1] > rl[0]:
		cr = ROJO.lightened(0.1)
	var m := ANCHO_CAJA * 0.5
	var hexa := PackedVector2Array([Vector2(c - m + 12, 2), Vector2(c + m - 12, 2), Vector2(c + m, h * 0.5), Vector2(c + m - 12, h - 2),
		Vector2(c - m + 12, h - 2), Vector2(c - m, h * 0.5)])
	draw_colored_polygon(hexa, cr)
	hexa.append(hexa[0])
	draw_polyline(hexa, Color(0.08, 0.06, 0.14), 3.0, true)
	var tinta := Color(0.1, 0.06, 0.16)
	if _ffa:
		_texto("EN PIE", Rect2(c - m, 4, ANCHO_CAJA, 14), 12, tinta)
		_texto(str(vivos[0] + vivos[1]), Rect2(c - m, 16, ANCHO_CAJA, h - 20), 28, Color.WHITE, true)
	else:
		_texto("RONDA %d" % (rl[0] + rl[1] + 1), Rect2(c - m, 4, ANCHO_CAJA, 16), 13, tinta)
		# los puntos: dos por equipo, llenos los ganados
		var obj := 2
		for k in 2:
			for i in obj:
				var x := c + (-1.0 if k == 0 else 1.0) * (18.0 + i * 20.0)
				var p := Vector2(x, h * 0.66)
				var lleno: bool = int(rl[k]) > i
				var col := AZUL if k == 0 else ROJO
				draw_circle(p, 7.5, Color(0.08, 0.06, 0.14))
				draw_circle(p, 5.5, col.lightened(0.2) if lleno else Color(0, 0, 0, 0.35))
				if lleno:
					draw_circle(p + Vector2(-1.5, -1.5), 1.8, Color(1, 1, 1, 0.7))
		draw_line(Vector2(c, h * 0.5), Vector2(c, h * 0.82), Color(0.08, 0.06, 0.14, 0.6), 2.0)
	# los medallones, hacia fuera desde la caja
	for k in 2:
		var lista: Array = lados[k]
		var col := (ORO if _ffa else AZUL) if k == 0 else ROJO
		for i in mini(lista.size(), MAX_MED):
			var dx := m + 22.0 + MED + i * (MED * 2.0 + 5.0)
			var p := Vector2(c - dx if k == 0 else c + dx, h * 0.5)
			_medallon(p, col, lista[i], ahora)
		# cuantos quedan, debajo
		var t := "%d EN PIE" % vivos[k]
		var rx := c - m - 160.0 if k == 0 else c + m + 10.0
		_texto(t, Rect2(rx, h + 2, 150, 20), 14, col.lightened(0.35) if vivos[k] > 0 else Color(0.6, 0.6, 0.62), true)


func _medallon(p: Vector2, col: Color, fila: Array, ahora: float) -> void:
	var nombre := String(fila[0])
	var vivo := bool(fila[1])
	var ant: Array = _cambios.get(nombre, [vivo, -10.0])
	if bool(ant[0]) != vivo:
		ant = [vivo, ahora]
		_cambios[nombre] = ant
	elif not _cambios.has(nombre):
		_cambios[nombre] = ant
	var t := ahora - float(ant[1])          # segundos desde que cayo / revivio
	var esc := 1.0
	if t < 0.35:
		esc = 1.0 + 0.35 * sin(t / 0.35 * PI)
	var r := MED * esc
	# aro
	# el tuyo y los de las demas personas, con aro dorado (los bots, blanco)
	var aro := ORO if (bool(fila[2]) or (fila.size() > 4 and bool(fila[4]))) else Color(1, 1, 1, 0.85)
	if not vivo:
		aro = Color(0.35, 0.35, 0.38, 0.9)
	draw_circle(p, r + 2.5, Color(0.08, 0.06, 0.14))
	draw_circle(p, r + 1.5, aro)
	var fondo := col.darkened(0.25) if vivo else Color(0.2, 0.2, 0.22)
	draw_circle(p, r, fondo)
	# la silueta (cabeza y hombros), recortada al circulo
	var sil := col.lightened(0.55) if vivo else Color(0.45, 0.45, 0.48)
	draw_circle(p + Vector2(0, -r * 0.22), r * 0.36, sil)
	var hombros := PackedVector2Array()
	for j in 13:
		var a := PI + PI * j / 12.0
		hombros.append(p + Vector2(cos(a) * r * 0.7, r * 0.78 + sin(a) * r * 0.55))
	draw_colored_polygon(hombros, sil)
	if not vivo:
		# la raya de eliminado
		draw_line(p + Vector2(-r * 0.7, r * 0.7), p + Vector2(r * 0.7, -r * 0.7), Color(0.95, 0.26, 0.36, 0.9), 3.0, true)
	# el fogonazo del cambio: rojo al caer, blanco al revivir
	if t < 0.6:
		var k := 1.0 - t / 0.6
		draw_arc(p, r + 3.0 + 10.0 * (1.0 - k), 0.0, TAU, 28, Color(1, 1, 1, 0.9 * k) if vivo else Color(1.0, 0.3, 0.3, 0.9 * k), 3.0, true)
