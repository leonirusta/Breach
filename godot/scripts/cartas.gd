class_name Cartas
## LAS CARTAS (2026-09-29, pedido con capturas del juego de referencia: "DESTREZAS ACTIVAS / SET DE DESTREZAS"). Cada
## carta mejora un poquito una cosa (daño, regeneracion fuera de combate, salud maxima, velocidad, salto, destruccion,
## explosiones, municion al eliminar, y las ESPECIALES, que acortan la recarga de la habilidad definitiva del personaje).
##
## - Se llevan RANURAS (8) EQUIPADAS: solo cuentan las equipadas (`equipadas()`).
## - La primera copia te da la carta a NIVEL 1; las siguientes se juntan ("5/2": tienes 5, hacen falta 2) y MEJORAR gasta
##   esas copias, CUBOS DE FUERZA y ORO (`COPIAS_MEJORA` / `CUBOS_MEJORA` / `ORO_MEJORA`, por el nivel que tienes) y sube
##   un nivel, hasta NIVEL_MAX. Nunca con diamantes (pedido, 2026-09-30: "cubos de fuerza y dinero, como el personaje").
## - Las copias las dan sobre todo los COFRES (cofres.gd, premio "carta"): antes cartas que cosas gordas como las skins.
## - Con cuenta las lleva el SERVIDOR (`perfil.cartas`: id -> {"n": nivel, "c": copias}; mejorar es /carta/mejorar); sin
##   cuenta, `Settings.cartas`. Lo equipado va siempre en `Settings.cartas_equipadas` (es una preferencia, como la skin).
## - En la partida se lee `efecto(id)`: lo de las cartas equipadas MAS las ventajas del personaje (nivel_personaje.gd).

const RANURAS := 8
const NIVEL_MAX := 10
## Copias para pasar del nivel n al n+1 (el indice es el nivel que tienes; el 0 no se usa: la primera copia da el 1)
const COPIAS_MEJORA := [0, 2, 4, 6, 10, 14, 20, 28, 38, 50]
## Oro para pasar del nivel n al n+1
const ORO_MEJORA := [0, 40, 80, 150, 250, 400, 600, 850, 1200, 1600]
## Cubos de fuerza para pasar del nivel n al n+1 (2026-09-30, pedido: "subir una carta cuesta cubos de fuerza y dinero")
const CUBOS_MEJORA := [0, 1, 1, 2, 3, 4, 6, 8, 12, 16]

## Las CATEGORIAS (los filtros de la derecha del SET). "icono": dibujo de icono_lobby.gd
const CATEGORIAS := [
	{"id": "dano", "nombre": "DAÑO", "icono": "carta_dano"},
	{"id": "supervivencia", "nombre": "SUPERVIVENCIA", "icono": "carta_vida"},
	{"id": "movilidad", "nombre": "MOVILIDAD", "icono": "carta_velocidad"},
	{"id": "destruccion", "nombre": "DESTRUCCIÓN", "icono": "carta_destruccion"},
	{"id": "especial", "nombre": "ESPECIAL", "icono": "carta_especial"},
]

## LAS CARTAS. `base`: lo que da a nivel 1; `paso`: lo que suma cada nivel mas; `unidad`: "%" (se enseña por 100) o el
## texto que va detras del numero. `rareza`: la de SkinsArmas.RAREZAS (0 comun .. 4 legendaria): el color de la carta y lo
## que cuesta que salga en un cofre. `stat`: el titulo de la linea del detalle ("VELOCIDAD DE MOVIMIENTO +7% > +9%").
const LISTA := [
	{"id": "dano", "nombre": "AUMENTO DE DAÑO", "cat": "dano", "rareza": 0, "icono": "carta_dano",
		"color": Color(0.93, 0.22, 0.24), "stat": "DAÑO", "base": 0.02, "paso": 0.01, "unidad": "%",
		"desc": "Tus balas, golpes y explosiones hacen más daño a jugadores, bots y criaturas."},
	{"id": "municion", "nombre": "MUNICIÓN AL ELIMINAR", "cat": "dano", "rareza": 2, "icono": "carta_municion",
		"color": Color(0.85, 0.25, 0.85), "stat": "CARGADOR RECUPERADO", "base": 0.15, "paso": 0.03, "unidad": "%",
		"desc": "Al eliminar a alguien recuperas parte del cargador del arma que llevas."},
	{"id": "vida", "nombre": "SALUD MÁX.", "cat": "supervivencia", "rareza": 0, "icono": "carta_vida",
		"color": Color(0.25, 0.8, 0.35), "stat": "SALUD MÁXIMA", "base": 0.03, "paso": 0.015, "unidad": "%",
		"desc": "Más salud máxima."},
	{"id": "regeneracion", "nombre": "REGEN. DE SALUD", "cat": "supervivencia", "rareza": 1, "icono": "carta_regeneracion",
		"color": Color(0.25, 0.75, 0.4), "stat": "REGENERACIÓN", "base": 2.0, "paso": 0.6, "unidad": " vida/s",
		"desc": "Fuera de combate recuperas vida poco a poco: vuelves antes a la pelea."},
	# (2026-10-03, pedido: las ideas 8 y 10)
	{"id": "vampiro", "nombre": "VAMPIRO", "cat": "supervivencia", "rareza": 2, "icono": "carta_vampiro",
		"color": Color(0.78, 0.1, 0.28), "stat": "VIDA POR ELIMINACIÓN", "base": 8.0, "paso": 2.5, "unidad": " vida",
		"desc": "Cada eliminación te cura al momento."},
	{"id": "rescatista", "nombre": "RESCATISTA", "cat": "supervivencia", "rareza": 2, "icono": "carta_rescatista",
		"color": Color(0.15, 0.72, 0.62), "stat": "RAPIDEZ AL REANIMAR", "base": 0.10, "paso": 0.04, "unidad": "%",
		"desc": "Reanimas a tus compañeros más rápido y vuelven a la pelea con más vida."},
	# (2026-10-03, pedido: las de defensa BLINDAJE y PIEL DURA; el tipo de golpe lo marca quien lo da: player.golpe_tipo)
	{"id": "blindaje", "nombre": "BLINDAJE", "cat": "supervivencia", "rareza": 1, "icono": "carta_blindaje",
		"color": Color(0.4, 0.52, 0.7), "stat": "DAÑO DE BALA RECIBIDO", "base": 0.03, "paso": 0.01, "unidad": "% menos",
		"desc": "Las balas te hacen menos daño."},
	{"id": "piel_dura", "nombre": "PIEL DURA", "cat": "supervivencia", "rareza": 1, "icono": "carta_piel_dura",
		"color": Color(0.66, 0.44, 0.24), "stat": "DAÑO CUERPO A CUERPO RECIBIDO", "base": 0.05, "paso": 0.02,
		"unidad": "% menos", "desc": "Los mazazos, los puñetazos y los zarpazos de los zombis te hacen menos daño."},
	{"id": "velocidad", "nombre": "VEL. DE MOVIMIENTO", "cat": "movilidad", "rareza": 0, "icono": "carta_velocidad",
		"color": Color(0.2, 0.55, 0.95), "stat": "VELOCIDAD DE MOVIMIENTO", "base": 0.02, "paso": 0.008, "unidad": "%",
		"desc": "Te mueves más rápido."},
	{"id": "salto", "nombre": "SALTO ALTO", "cat": "movilidad", "rareza": 1, "icono": "carta_salto",
		"color": Color(0.35, 0.45, 0.95), "stat": "ALTURA DE SALTO", "base": 0.04, "paso": 0.015, "unidad": "%",
		"desc": "Saltas más alto."},
	{"id": "destruccion", "nombre": "DAÑO POR DESTRUCCIÓN", "cat": "destruccion", "rareza": 2, "icono": "carta_destruccion",
		"color": Color(0.95, 0.5, 0.15), "stat": "DAÑO A ESTRUCTURAS", "base": 0.15, "paso": 0.06, "unidad": "%",
		"desc": "Tus balas rompen más pared en cada tiro: abres coberturas antes."},
	{"id": "explosion", "nombre": "EXPLOSIÓN AMPLIA", "cat": "destruccion", "rareza": 3, "icono": "carta_explosion",
		"color": Color(0.95, 0.35, 0.1), "stat": "RADIO DE EXPLOSIÓN", "base": 0.05, "paso": 0.02, "unidad": "%",
		"desc": "Tus granadas, cohetes y cargas hacen el agujero más grande."},
	{"id": "enfriamiento", "nombre": "REDUCCIÓN DE ENFRIAMIENTO", "cat": "especial", "rareza": 3, "icono": "carta_especial",
		"color": Color(0.98, 0.72, 0.1), "stat": "RECARGA DE LA DEFINITIVA", "base": 0.05, "paso": 0.025, "unidad": "% menos",
		"desc": "La habilidad definitiva de tu personaje se recarga antes."},
	# (2026-10-03, pedido: la idea 24)
	{"id": "definitiva", "nombre": "RECARGA DE DEFINITIVA", "cat": "especial", "rareza": 3, "icono": "carta_definitiva",
		"color": Color(0.95, 0.45, 0.12), "stat": "CARGA POR BAJA O ASISTENCIA", "base": 0.04, "paso": 0.012, "unidad": "%",
		"desc": "Cada eliminación o asistencia te carga más la barra de la habilidad definitiva."},
]

## Lo que pasa de una partida a otra dentro de la misma sesion (para no releer el perfil en cada tiro)
static var _cache_efectos: Dictionary = {}


static func datos(id: String) -> Dictionary:
	for c in LISTA:
		if String(c["id"]) == id:
			return c
	return {}


static func ids() -> Array:
	var out: Array = []
	for c in LISTA:
		out.append(String(c["id"]))
	return out


static func de_categoria(cat: String) -> Array:
	var out: Array = []
	for c in LISTA:
		if cat == "" or cat == "todo" or String(c["cat"]) == cat:
			out.append(String(c["id"]))
	return out


static func nombre_categoria(cat: String) -> String:
	for c in CATEGORIAS:
		if String(c["id"]) == cat:
			return String(c["nombre"])
	return ""


static func rareza(id: String) -> int:
	return int(datos(id).get("rareza", 0))


# ---------------------------------------------------------------------------------------------------------------
# LO QUE TIENES
# ---------------------------------------------------------------------------------------------------------------
static func _tabla() -> Dictionary:
	var d = Cuenta.perfil.get("cartas", {}) if Cuenta.conectado() else Settings.cartas
	return d if d is Dictionary else {}


static func _estado(id: String) -> Dictionary:
	var e = _tabla().get(id, {})
	return e if e is Dictionary else {}


static func nivel(id: String) -> int:
	return clampi(int(_estado(id).get("n", 0)), 0, NIVEL_MAX)


static func tiene(id: String) -> bool:
	return nivel(id) > 0


## Las copias juntadas para el siguiente nivel
static func copias(id: String) -> int:
	return int(_estado(id).get("c", 0))


## Las que hacen falta para el siguiente nivel (0 al maximo)
static func copias_para(id: String) -> int:
	var n := nivel(id)
	return int(copias_mejora()[n]) if n >= 1 and n < NIVEL_MAX else 0


static func oro_para(id: String) -> int:
	var n := nivel(id)
	return int(oro_mejora()[n]) if n >= 1 and n < NIVEL_MAX else 0


static func cubos_para(id: String) -> int:
	var n := nivel(id)
	var t := cubos_mejora()
	return int(t[n]) if n >= 1 and n < NIVEL_MAX and n < t.size() else 0


## Las tablas de verdad: las del panel (TiendaAjustes, "cartas_copias" / "cartas_oro") o las de aqui
static func copias_mejora() -> Array:
	return TiendaAjustes.juego("cartas_copias", COPIAS_MEJORA)


static func oro_mejora() -> Array:
	return TiendaAjustes.juego("cartas_oro", ORO_MEJORA)


static func cubos_mejora() -> Array:
	return TiendaAjustes.juego("cartas_cubos", CUBOS_MEJORA)


## Lo que da cada carta: {"base", "paso"} del panel ("cartas_valores") o el de LISTA
static func _base_paso(id: String) -> Array:
	var d := datos(id)
	var aj = TiendaAjustes.juego("cartas_valores", {})
	if aj is Dictionary and (aj as Dictionary).has(id):
		var x: Dictionary = aj[id]
		return [float(x.get("base", d.get("base", 0.0))), float(x.get("paso", d.get("paso", 0.0)))]
	return [float(d.get("base", 0.0)), float(d.get("paso", 0.0))]


## Cuantas tienes (el "DISPONIBLE: 11/31" del set)
static func disponibles() -> int:
	var k := 0
	for id in ids():
		if tiene(id):
			k += 1
	return k


## "" si se puede mejorar ya; si no, por que: "no_la_tienes", "maximo", "copias", "cubos", "oro"
static func que_falta(id: String) -> String:
	var n := nivel(id)
	if n <= 0:
		return "no_la_tienes"
	if n >= NIVEL_MAX:
		return "maximo"
	if copias(id) < copias_para(id):
		return "copias"
	if Settings.saldo_cubos() < cubos_para(id):
		return "cubos"
	if Settings.saldo() < oro_para(id):
		return "oro"
	return ""


## ¿Tiene la flecha de "se puede mejorar"? (copias de sobra, aunque falte el oro: como en la referencia)
static func copias_listas(id: String) -> bool:
	var n := nivel(id)
	return n >= 1 and n < NIVEL_MAX and copias(id) >= copias_para(id)


## Mejorar. "hecho" (sin cuenta, ya esta), "enviado" (el servidor: llega con Cuenta.sesion_cambiada, o Cuenta.error_cuenta)
## o lo que falte (que_falta)
static func mejorar(id: String) -> String:
	var f := que_falta(id)
	if f != "":
		return f
	if Cuenta.conectado():
		return "enviado" if Cuenta.carta_mejorar(id) else "no"
	var n := nivel(id)
	var coste := oro_para(id)
	var e: Dictionary = _estado(id).duplicate()
	e["c"] = copias(id) - int(copias_mejora()[n])
	e["n"] = n + 1
	Settings.cartas[id] = e
	Settings.cubos -= cubos_para(id)
	Settings.monedas -= coste
	Settings.save()
	_cache_efectos.clear()
	return "hecho"


## Sin cuenta: sumar copias (cofres.gd). La primera da el nivel 1 y la equipa si hay hueco.
static func dar_local(id: String, k: int = 1) -> void:
	if datos(id).is_empty() or k <= 0:
		return
	var e: Dictionary = _estado(id).duplicate()
	var n := int(e.get("n", 0))
	var c := int(e.get("c", 0))
	if n <= 0:
		n = 1
		k -= 1
		equipar_si_cabe(id)
	e["n"] = n
	e["c"] = c + k
	Settings.cartas[id] = e
	_cache_efectos.clear()


# ---------------------------------------------------------------------------------------------------------------
# LO EQUIPADO (las RANURAS de "DESTREZAS ACTIVAS")
# ---------------------------------------------------------------------------------------------------------------
static func equipadas() -> Array:
	var out: Array = []
	for x in Settings.cartas_equipadas:
		var id := String(x)
		if tiene(id) and not id in out and out.size() < RANURAS:
			out.append(id)
	return out


static func equipada(id: String) -> bool:
	return id in equipadas()


## Equipar. false si no la tienes o si no cabe (hay que quitar otra antes)
static func equipar(id: String) -> bool:
	if not tiene(id):
		return false
	var eq := equipadas()
	if id in eq:
		return true
	if eq.size() >= RANURAS:
		return false
	eq.append(id)
	Settings.cartas_equipadas = eq
	Settings.save()
	_cache_efectos.clear()
	return true


static func quitar(id: String) -> void:
	var eq := equipadas()
	eq.erase(id)
	Settings.cartas_equipadas = eq
	Settings.save()
	_cache_efectos.clear()


## Cambiar una equipada por otra (la ranura queda en su sitio)
static func cambiar(sale: String, entra: String) -> bool:
	if not tiene(entra):
		return false
	var eq := equipadas()
	var i := eq.find(sale)
	if i < 0:
		return equipar(entra)
	if entra in eq:
		eq.erase(entra)
		i = eq.find(sale)
	eq[i] = entra
	Settings.cartas_equipadas = eq
	Settings.save()
	_cache_efectos.clear()
	return true


## La primera vez que te sale una carta se equipa sola si hay hueco
static func equipar_si_cabe(id: String) -> void:
	var eq := equipadas()
	if not id in eq and eq.size() < RANURAS and not id in Settings.cartas_equipadas:
		Settings.cartas_equipadas.append(id)


# ---------------------------------------------------------------------------------------------------------------
# "NUEVO" (la cinta roja de las cartas que no has mirado)
# ---------------------------------------------------------------------------------------------------------------
static func nueva(id: String) -> bool:
	return tiene(id) and not id in Settings.cartas_vistas


static func marcar_vista(id: String) -> void:
	if not id in Settings.cartas_vistas:
		Settings.cartas_vistas.append(id)
		Settings.save()


## Cuantas hay para mirar o mejorar (el globo rojo de la armeria / CARTAS)
static func avisos(cat: String = "") -> int:
	var k := 0
	for id in de_categoria(cat):
		if nueva(id) or copias_listas(id):
			k += 1
	return k


# ---------------------------------------------------------------------------------------------------------------
# LO QUE DAN
# ---------------------------------------------------------------------------------------------------------------
## Lo que da una carta a un nivel (sin mirar si la tienes): 0 a nivel 0
static func valor_a(id: String, n: int) -> float:
	if datos(id).is_empty() or n <= 0:
		return 0.0
	var bp := _base_paso(id)
	var v := float(bp[0]) + float(bp[1]) * float(mini(n, NIVEL_MAX) - 1)
	# EL DOBLE DE POTENCIA (2026-10-25, pedido: "+100 % a las cartas, menos las de destruccion del entorno"): todas x2
	# salvo la categoria DESTRUCCION (daño a estructuras y radio de explosion). `--cartasantes` = como antes.
	if String(datos(id).get("cat", "")) != "destruccion" and not _cartas_antes:
		v *= POTENCIA
	return v
const POTENCIA := 2.0
static var _cartas_antes := "--cartasantes" in OS.get_cmdline_user_args()


## "+6%", "+2,4 vida/s", "+10% menos"... a un nivel dado (por defecto el suyo)
static func texto_valor(id: String, n: int = -1) -> String:
	var d := datos(id)
	if d.is_empty():
		return ""
	if n < 0:
		n = nivel(id)
	return formato(id, valor_a(id, n))


## Un valor de esta carta en bonito: "+6%", "+2,4 vida/s", y lo que RESTA con signo menos ("-10%": la recarga)
static func formato(id: String, v: float) -> String:
	var u := String(datos(id).get("unidad", ""))
	if u == "% menos":
		return "-%s%%" % _num(v * 100.0)
	if u.begins_with("%"):
		return "+%s%s" % [_num(v * 100.0), u]
	return "+%s%s" % [_num(v), u]


static func _num(v: float) -> String:
	var t := ("%.1f" % v).replace(".", ",")
	return t.trim_suffix(",0")


## LO QUE SE USA EN LA PARTIDA: las cartas EQUIPADAS mas las ventajas del personaje (NivelPersonaje.ventajas_activas).
## 0 si no hay nada. Se guarda hasta que algo cambia (equipar, mejorar, otra partida: `refrescar()`).
static func efecto(id: String) -> float:
	if _cache_efectos.is_empty():
		refrescar()
	return float(_cache_efectos.get(id, 0.0))


static func refrescar() -> void:
	_cache_efectos = {"_": 0.0}
	for id in equipadas():
		_cache_efectos[id] = float(_cache_efectos.get(id, 0.0)) + valor_a(id, nivel(id))
	for v in NivelPersonaje.ventajas_activas():
		var cid := String(v.get("carta", ""))
		_cache_efectos[cid] = float(_cache_efectos.get(cid, 0.0)) + float(v.get("valor", 0.0))
		# una ventaja puede dar mas de una cosa ("extra": {efecto: valor}; la de NV.7 del Specter)
		var extra = v.get("extra", {})
		if extra is Dictionary:
			for k in extra:
				_cache_efectos[String(k)] = float(_cache_efectos.get(String(k), 0.0)) + float(extra[k])


## El multiplicador de algo con tope (lo que usa el juego): 1 + efecto
static func mult(id: String) -> float:
	return 1.0 + efecto(id)


# ---------------------------------------------------------------------------------------------------------------
# EL SERVIDOR
# ---------------------------------------------------------------------------------------------------------------
## Lo que --exportarprecios escribe en progreso.json (el servidor sortea con las rarezas y cobra las mejoras con esto)
static func para_servidor() -> Dictionary:
	var rar := {}
	var nombres := {}
	var valores := {}
	for c in LISTA:
		rar[String(c["id"])] = int(c["rareza"])
		nombres[String(c["id"])] = String(c["nombre"])
		valores[String(c["id"])] = {"base": float(c["base"]), "paso": float(c["paso"]), "unidad": String(c["unidad"])}
	return {"ids": ids(), "rareza": rar, "nombres": nombres, "valores": valores, "nivel_max": NIVEL_MAX,
		"copias": COPIAS_MEJORA, "oro": ORO_MEJORA, "cubos": CUBOS_MEJORA}
