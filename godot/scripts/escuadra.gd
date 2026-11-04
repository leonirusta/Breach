class_name Escuadra
extends Node
## EL MANDO. Un tablón compartido donde los bots apuntan lo que pasa y consultan a dónde hace falta
## ir. Es lo único que necesita un equipo para parecer coordinado: no hace falta que se hablen entre
## ellos, basta con que todos miren el mismo sitio.
##
## POR QUÉ ASÍ Y NO CON MENSAJES ENTRE BOTS. Veinte bots avisándose unos a otros son cuatrocientas
## llamadas por aviso, y encima hay que decidir quién habla con quién. Con un tablón, avisar cuesta
## una entrada en una lista y consultar cuesta recorrer cuatro o cinco. Es la misma idea que un
## equipo real gritando por radio: nadie habla con nadie en particular, se habla al aire y cada uno
## decide si le toca.
##
## Las alertas CADUCAN, y eso es lo que evita el comportamiento de rebaño: si no caducaran, el primer
## disparo de la partida seguiría llamando gente diez minutos después.

## Cuánto dura un aviso antes de que a nadie le importe.
const VIDA := 12.0
## Cuántos bots como máximo acuden al mismo aviso. Sin tope, un solo tiro vacía el mapa entero hacia
## un punto y el resto queda sin defender — que es exactamente lo que hace un equipo malo.
const ACUDEN_MAX := 4

## Cada aviso: {"pos", "team" (a quién le interesa), "peso", "t" (cuándo se apuntó), "van" (cuántos)}
static var _avisos: Array = []


## Alguien ha disparado o ha muerto en `pos`. `team` es el bando AL QUE LE INTERESA saberlo (el del
## que sufre), y `peso` lo urgente que es: un compañero muerto pesa más que un tiro oído.
static func avisar(pos: Vector3, team: String, peso: float) -> void:
	var ahora: float = Time.get_ticks_msec() * 0.001
	_limpiar(ahora)
	# SI YA HAY UN AVISO CERCA, SE REFUERZA en vez de añadir otro. Un tiroteo son veinte disparos: sin
	# esto la lista se llenaría de veinte avisos del mismo sitio y el reparto de gente se volvería
	# absurdo (cuatro bots por cada disparo).
	for a in _avisos:
		if String(a["team"]) == team and (a["pos"] as Vector3).distance_to(pos) < 14.0:
			a["pos"] = ((a["pos"] as Vector3) + pos) * 0.5
			a["peso"] = minf(float(a["peso"]) + peso, 10.0)
			a["t"] = ahora
			return
	_avisos.append({"pos": pos, "team": team, "peso": peso, "t": ahora, "van": 0})


## A dónde debería ir un bot de `team` que esté libre, o INF si no hace falta ir a ningún sitio.
## Devuelve también si quedan plazas: el que llama debe apuntarse con `apuntarse`.
static func foco(team: String) -> Vector3:
	var ahora: float = Time.get_ticks_msec() * 0.001
	_limpiar(ahora)
	var mejor: Dictionary = {}
	var mejor_peso := 0.0
	for a in _avisos:
		if String(a["team"]) != team:
			continue
		if int(a["van"]) >= ACUDEN_MAX:
			continue
		# lo reciente pesa más: un aviso de hace diez segundos ya casi no llama
		var frescura: float = 1.0 - clampf((ahora - float(a["t"])) / VIDA, 0.0, 1.0)
		var p: float = float(a["peso"]) * frescura
		if p > mejor_peso:
			mejor_peso = p
			mejor = a
	return (mejor["pos"] as Vector3) if not mejor.is_empty() else Vector3.INF


## Un bot dice "voy yo". Así el siguiente que pregunte ve una plaza menos y se queda en su puesto.
static func apuntarse(team: String, pos: Vector3) -> void:
	for a in _avisos:
		if String(a["team"]) == team and (a["pos"] as Vector3).distance_to(pos) < 2.0:
			a["van"] = int(a["van"]) + 1
			return


static func _limpiar(ahora: float) -> void:
	var i := 0
	while i < _avisos.size():
		if ahora - float(_avisos[i]["t"]) > VIDA:
			_avisos.remove_at(i)
		else:
			i += 1


## Al empezar una ronda se borra todo: los avisos de la ronda anterior no valen nada y si se quedaran
## los bots saldrían del spawn corriendo hacia donde murió alguien hace dos minutos.
static func reiniciar() -> void:
	_avisos.clear()
