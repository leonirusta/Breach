class_name Combat
## Utilidades de combate compartidas.

# ---------------------------------------------------------------------------
# LO QUE HAS HECHO EN ESTA PARTIDA, para el premio: daño repartido, objetivos cumplidos (plantar o
# desactivar la C4, ingresar un cubo) y bajas en el PvE. Las monedas de jugar pagan por esto y por
# ser MVP (ver `Settings.monedas_de_partida` y servidor/index.js). Se pone a cero al empezar partida.
# Solo cuenta lo del jugador de ESTA maquina: cada uno cobra lo suyo.
# ---------------------------------------------------------------------------
static var partida_dano := 0.0
static var partida_objetivos := 0
static var partida_bajas_pve := 0
static var partida_dano_jefe := 0.0

static func empezar_partida() -> void:
	partida_dano = 0.0
	partida_objetivos = 0
	partida_bajas_pve = 0
	partida_dano_jefe = 0.0


## Apunta daño si lo hace el jugador local. Se llama ANTES de aplicarlo: asi se lee la vida que le
## quedaba a la victima y no se cuenta daño de mas sobre alguien que ya casi no tenia.
static func anotar_dano(autor, victima, dmg: float) -> void:
	if autor == null or not is_instance_valid(autor) or autor != Net.local_player or dmg <= 0.0:
		return
	var real := dmg
	if victima != null and is_instance_valid(victima):
		for campo in ["health", "vida"]:
			if campo in victima:
				real = minf(dmg, maxf(0.0, float(victima.get(campo))))
				break
		if "muerta" in victima and bool(victima.get("muerta")):
			real = 0.0
	partida_dano += real
	if victima != null and is_instance_valid(victima) and "datos" in victima \
			and bool((victima.get("datos") as Dictionary).get("jefe", false)):
		partida_dano_jefe += real

## Daño en área a todo lo del grupo "damageable" (jugador, enemigos) con caída lineal.
## `autor`: quien lanzo lo que ha explotado. Se le apunta a cada herido como su ultimo atacante,
## para que una baja por cohete cuente en el marcador de quien disparo (pantalla de victoria / MVP).
## `tumbar`: si la onda TIRA AL SUELO a quien pilla. Es de los EXPLOSIVOS (cohete, granada, C4): una
## explosion te quita el equilibrio. Los golpes de las criaturas hacen dano y empujan, pero NO tumban:
## con el Goliat dando martillazos al suelo cada tres segundos te pasabas la pelea levantandote.
##
## EN RED HAY DOS CLASES DE EXPLOSION, y cada una tiene que llamar a esto de una forma:
##  - UNA SOLA MAQUINA la resuelve (el cohete de quien disparo, la granada de quien la tiro, el golpe de un
##    bicho en el anfitrion): `remotos = true`. Ademas de lo suyo daña a las COPIAS (que pasan el golpe a su
##    dueño) y a los JUGADORES DE LAS OTRAS MAQUINAS, que no estan en "damageable" y no se enteraban: un
##    cohete de bot o una granada no le quitaban vida al compañero de LAN.
##  - CADA MAQUINA la resuelve por su cuenta (la C4, que la anuncia el anfitrion y revienta en todas):
##    `solo_propios = true`. Solo lo de esta maquina; las copias NO, o el bot recibia el golpe una vez por
##    jugador.
static func _es_companero(n: Node, autor: Node) -> bool:
	if n.is_in_group("criaturas"):
		return false
	# TODOS CONTRA TODOS (el battle royale en SOLO, el duelo en TODOS: Net.todos_contra_todos): nadie es compañero de
	# nadie, aunque la etiqueta de bando coincida (en el battle royale en solitario las personas son todas "t")
	if Net.todos_contra_todos() and String(Settings.modo) != "pve":
		return false
	var persona: bool = n.is_in_group("bots") or n.is_in_group("player") or ("team" in n and not n.is_in_group("enemies"))
	if autor != null and is_instance_valid(autor):
		if autor.is_in_group("criaturas"):
			return false
		if "team" in autor and "team" in n and String(autor.get("team")) != "" and String(autor.get("team")) == String(n.get("team")):
			return true
	if String(Settings.modo) == "pve" and (persona or n.is_in_group("bots")):
		return autor == null or not is_instance_valid(autor) or not autor.is_in_group("criaturas")
	return false

## `empuje`: si no es cero, el empujon que se lleva cada uno, igual para todos y en esa direccion (el puñetazo: todos
## salen volando hacia donde va el golpe, con la fuerza del mazo). Si es cero, el de siempre: desde el centro.
## EL DAÑO DE UN TUBO (el puñetazo, 2026-09-28: "le tire un monton de puñetazos a los bots y no les quite nada"). Con
## damage_around se media desde el centro de cada tramo de 3 m, A LA ALTURA DE LOS OJOS, hasta los PIES del bot: con esa
## diferencia de altura y la caida con la distancia llegaba un 15 % a 3 m y nada a 12 (medido, --punobottest). Aqui
## cuenta quien tenga el CUERPO (pies + 1 m) dentro del tubo `a`-`b` de radio `radio`: entero en el eje, 60 % en el
## borde. `ya`: los que ya ha pillado esta misma onda (cada uno, UNA vez: los tramos se solapan). `empuje`: sale volando
## hacia ahi. Mismas reglas que damage_around (bandos, bichos, jugadores de otras maquinas).
static func damage_tubo(tree: SceneTree, a: Vector3, b: Vector3, radio: float, dmg: float, autor: Node, empuje: Vector3,
		ya: Dictionary, remotos: bool = true, solo_propios: bool = true) -> void:
	var ab := b - a
	var largo2 := maxf(ab.length_squared(), 0.0001)
	var hasta_eje := func(p: Vector3) -> float:
		var t := clampf((p - a).dot(ab) / largo2, 0.0, 1.0)
		return p.distance_to(a + ab * t)
	for n in tree.get_nodes_in_group("damageable"):
		if not n is Node3D or n == autor or ya.has(n.get_instance_id()):
			continue
		if solo_propios and ((("remoto" in n) and bool(n.get("remoto"))) or (("soy_copia" in n) and bool(n.get("soy_copia")))):
			continue
		if _es_companero(n, autor) or not n.has_method("take_damage"):
			continue
		if "health" in n and float(n.get("health")) <= 0.0:
			continue
		var d: float = hasta_eje.call((n as Node3D).global_position + Vector3.UP * 1.0)
		if d > radio:
			continue
		ya[n.get_instance_id()] = true
		var dano := dmg * (1.0 - 0.4 * d / radio)
		if autor != null and is_instance_valid(autor) and "ultimo_atacante" in n:
			n.ultimo_atacante = autor
		anotar_dano(autor, n, dano)
		if "golpe_tipo" in n:
			n.golpe_tipo = "cuerpo"     # puñetazo / salto (la carta PIEL DURA)
		n.take_damage(dano, empuje)
		if dano >= 10.0 and is_instance_valid(n) and n.has_method("derribar") and "health" in n and float(n.health) > 0.0:
			n.derribar(empuje.normalized())
	if not remotos or not Net.is_online():
		return
	var bando_autor := ""
	if autor != null and is_instance_valid(autor) and "team" in autor:
		bando_autor = String(autor.get("team"))
	for id in Net.remotes.keys():
		var r = Net.remotes[id]
		if not is_instance_valid(r) or bool(r.get("dead")) or ya.has("r%d" % int(id)):
			continue
		if bando_autor != "" and Net.team_of(int(id)) == bando_autor and not Net.todos_contra_todos():
			continue
		var d2: float = hasta_eje.call((r as Node3D).global_position + Vector3.UP * 1.0)
		if d2 > radio:
			continue
		ya["r%d" % int(id)] = true
		Net.report_hit(int(id), dmg * (1.0 - 0.4 * d2 / radio), empuje, "cuerpo")


static func damage_around(tree: SceneTree, pos: Vector3, radius: float, dmg: float, autor: Node = null, tumbar: bool = true,
		remotos: bool = false, solo_propios: bool = false, empuje: Vector3 = Vector3.ZERO, prob_tumbar: float = 1.0) -> void:
	for n in tree.get_nodes_in_group("damageable"):
		if not n is Node3D:
			continue
		if solo_propios and ((("remoto" in n) and bool(n.get("remoto"))) or (("soy_copia" in n) and bool(n.get("soy_copia")))):
			continue
		var d: float = n.global_position.distance_to(pos)
		# SIN FUEGO AMIGO EN LAS EXPLOSIONES (2026-09-23, pedido): las balas ya lo respetaban, la onda no, y en
		# oleadas el cohete de un compañero te quitaba vida. Se salva quien sea del bando del autor (menos el
		# propio autor, que su cohete a los pies si le duele). En oleadas, sin autor conocido (una explosion que
		# llega por red), las personas y los bots tampoco reciben: ahi el unico enemigo son las criaturas.
		if n != autor and _es_companero(n, autor):
			continue
		# LOS BICHOS NO SE HACEN DAÑO (2026-09-23): el golpe al suelo del Goliat se lo comia EL MISMO y los zombis
		# de al lado. En la oleada del jefe, a fuerza de abrirse paso a golpes, se mataba solo y salia VICTORIA.
		if autor != null and is_instance_valid(autor) and autor.is_in_group("criaturas") and n.is_in_group("criaturas") \
				and not bool(autor.get("revienta_a_todos")):
			continue
		if d < radius and n.has_method("take_damage"):
			# la explosión también empuja: el cadáver sale despedido desde el centro
			var away: Vector3 = (n.global_position - pos)
			away.y = absf(away.y) + 0.6
			if autor != null and is_instance_valid(autor) and "ultimo_atacante" in n:
				n.ultimo_atacante = autor
			if n != autor:
				anotar_dano(autor, n, dmg * (1.0 - d / radius))
			n.take_damage(dmg * (1.0 - d / radius), empuje if empuje != Vector3.ZERO else away.normalized() * (9.0 * (1.0 - d / radius)))
			# SI NO LO HA MATADO, LO TIRA AL SUELO (player/enemy.derribar). Solo si le ha dado de verdad:
			# rozar el borde de la onda no tumba a nadie.
			if tumbar and dmg * (1.0 - d / radius) >= 10.0 and is_instance_valid(n) and n.has_method("derribar") \
					and "health" in n and float(n.health) > 0.0 and randf() < prob_tumbar:
				# `prob_tumbar`: el COHETE tumba solo 1 de cada 10 veces (2026-09-30, pedido: "con la bazuca, un 10 % que se
				# caiga al piso; ya no siempre"); el puñetazo (damage_tubo) y el salto, siempre
				n.derribar(empuje.normalized() if empuje != Vector3.ZERO else away.normalized())
	if not remotos or not Net.is_online():
		return
	# LOS JUGADORES DE LAS OTRAS MAQUINAS: su vida la lleva su maquina, asi que se les manda el golpe
	var bando_autor := ""
	if autor != null and is_instance_valid(autor) and "team" in autor:
		bando_autor = String(autor.get("team"))
	for id in Net.remotes.keys():
		var r = Net.remotes[id]
		if not is_instance_valid(r) or bool(r.get("dead")):
			continue
		var d2: float = (r as Node3D).global_position.distance_to(pos)
		if d2 >= radius:
			continue
		if bando_autor != "" and Net.team_of(int(id)) == bando_autor and not Net.todos_contra_todos():
			continue        # sin fuego amigo, como con las balas (net_player.is_friendly)
		var away2: Vector3 = (r as Node3D).global_position - pos
		away2.y = absf(away2.y) + 0.6
		Net.report_hit(int(id), dmg * (1.0 - d2 / radius), empuje if empuje != Vector3.ZERO else away2.normalized() * (9.0 * (1.0 - d2 / radius)))
