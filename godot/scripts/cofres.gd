class_name Cofres
## LOS COFRES (2026-09-29, pedido: "un cofre bien diseñado, tipo Brawl Stars: al apretar, si tienes suerte te sale
## epica, legendaria, mitica... con muy buenas animaciones").
##
## Un cofre EMPIEZA en una rareza (la que dice quien lo da: el pase da comunes, poco comunes y raros) y se abre a
## TOQUES: en cada uno puede SUBIR una rareza (SUBE: cuanto mas alta, mas dificil) y al ultimo se abre y da UNA cosa de
## la rareza en la que acabo (PREMIOS). Las rarezas son las de siempre (SkinsArmas.RAREZAS: COMUN, POCO COMUN, RARA,
## EPICA, LEGENDARIA, MITICA), con sus colores.
##
## Con cuenta lo sortea el SERVIDOR (/cofre/abrir, con esta misma tabla exportada a servidor/progreso.json) y el juego
## solo ANIMA lo que le dice (`etapas`: la rareza despues de cada toque); sin cuenta se sortea aqui. Lo que se da es
## pequeño a proposito: casi siempre CARTAS (cartas.gd) y si no oro o CUBOS DE FUERZA (la moneda de subir de nivel a los
## personajes: nivel_personaje.gd); pinturas, mazos y personajes solo en las rarezas altas, y nunca uno que ya tengas.

const TOQUES := 4
## La probabilidad de subir UNA rareza en cada toque, segun la rareza en la que estas (0 comun .. 4 legendaria)
## (2026-09-30, pedido: "los legendarios y miticos tienen que costar mas en salir; aqui hay mucha suerte"): de un comun,
## legendaria 1 de cada ~1.700 (antes 1 de 170); de un epico del pase, legendaria el 18 % (antes el 48 %)
const SUBE := [0.40, 0.25, 0.12, 0.05, 0.02]
## Lo que puede dar cada rareza: se sortea UNA opcion por su peso "w". CASI SIEMPRE CARTAS (2026-09-29, pedido: "que en
## los cofres salgan cartas que se van subiendo de nivel; mayormente cartas antes que cosas zarpadas como skins"):
##   "carta": copias (entre min y max) de UNA carta de rareza hasta "hasta" (cartas.gd), sin las que ya estan al maximo;
##            si no te falta ninguna, "si_no".
##   "articulo": uno del pool que NO tengas; si ya los tienes todos, "si_no".
##   el resto (oro, cubos, diamantes): una cantidad entre min y max.
const PREMIOS := [
	# COMUN
	[{"t": "carta", "w": 60, "hasta": 0, "min": 1, "max": 2, "si_no": {"t": "oro", "min": 20, "max": 30}},
		{"t": "oro", "w": 25, "min": 15, "max": 30}, {"t": "cubos", "w": 15, "min": 1, "max": 1}],
	# POCO COMUN
	[{"t": "carta", "w": 60, "hasta": 1, "min": 2, "max": 3, "si_no": {"t": "oro", "min": 50, "max": 70}},
		{"t": "oro", "w": 20, "min": 40, "max": 70}, {"t": "cubos", "w": 20, "min": 1, "max": 2}],
	# RARA
	[{"t": "carta", "w": 60, "hasta": 2, "min": 3, "max": 5, "si_no": {"t": "cubos", "min": 3, "max": 4}},
		{"t": "cubos", "w": 25, "min": 2, "max": 4}, {"t": "oro", "w": 15, "min": 90, "max": 130}],
	# EPICA
	[{"t": "carta", "w": 60, "hasta": 3, "min": 5, "max": 8, "si_no": {"t": "cubos", "min": 6, "max": 7}},
		{"t": "cubos", "w": 25, "min": 5, "max": 7},
		{"t": "articulo", "w": 15, "pool": ["sk_ceniza", "sk_arena", "sk_bosque", "sk_hormigon"], "si_no": {"t": "cubos", "min": 6, "max": 6}}],
	# LEGENDARIA
	[{"t": "carta", "w": 55, "hasta": 3, "min": 8, "max": 12, "si_no": {"t": "cubos", "min": 12, "max": 12}},
		{"t": "articulo", "w": 30, "pool": ["sk_oxido", "sk_tropical", "sk_neon", "sk_cyber", "sk_toxico",
		"mazo_obra", "mazo_llave", "mazo_extintor", "mazo_yunque"], "si_no": {"t": "cubos", "min": 12, "max": 12}},
		{"t": "cubos", "w": 15, "min": 10, "max": 13}],
	# MITICA
	[{"t": "carta", "w": 45, "hasta": 3, "min": 14, "max": 20, "si_no": {"t": "diamantes", "min": 10, "max": 10}},
		{"t": "articulo", "w": 40, "pool": ["sk_dorado", "sk_glaciar", "sk_calle", "sk_dragon", "sk_prisma", "modelo:Heraldo de Ceniza"],
		"si_no": {"t": "diamantes", "min": 10, "max": 10}},
		{"t": "diamantes", "w": 15, "min": 10, "max": 10}],
]

## Las de verdad: las del panel (TiendaAjustes, "cofres_sube" / "cofres_premios") o las de aqui
static func sube() -> Array:
	return TiendaAjustes.juego("cofres_sube", SUBE)


static func premios() -> Array:
	return TiendaAjustes.juego("cofres_premios", PREMIOS)


## El resultado del ultimo cofre abierto (el de este aparato; con cuenta llega con Cuenta.cofre_abierto)
static var ultimo: Dictionary = {}


## Los cofres por abrir: la rareza con la que empieza cada uno
static func pendientes() -> Array:
	if Cuenta.conectado():
		var c = Cuenta.perfil.get("cofres", [])
		return c if c is Array else []
	return Settings.cofres


static func cuantos() -> int:
	return pendientes().size()


## El sorteo de un cofre: {"inicio", "etapas": [rareza tras cada toque], "rareza" (la final), "premio": {"t", "v"}}.
## `tengo(clave) -> bool` dice lo que ya es tuyo (para no repetir articulos).
static func tirar(inicio: int, tengo: Callable, rng: RandomNumberGenerator, nivel_carta: Callable = Callable()) -> Dictionary:
	var r := clampi(inicio, 0, 5)
	var etapas: Array = []
	for i in TOQUES:
		if r < 5 and rng.randf() < float(sube()[r]):
			r += 1
		etapas.append(r)
	if not nivel_carta.is_valid():
		nivel_carta = func(id: String) -> int: return Cartas.nivel(id)
	return {"inicio": inicio, "etapas": etapas, "rareza": r, "premio": _premio(r, tengo, rng, nivel_carta)}


static func _premio(r: int, tengo: Callable, rng: RandomNumberGenerator, nivel_carta: Callable) -> Dictionary:
	var opciones: Array = premios()[r]
	var total := 0
	for x in opciones:
		total += int(x.get("w", 1))
	var tiro := rng.randi() % maxi(1, total)
	var o: Dictionary = opciones[0]
	for x in opciones:
		tiro -= int(x.get("w", 1))
		if tiro < 0:
			o = x
			break
	if String(o["t"]) == "carta":
		# una carta de rareza hasta "hasta" que no este al maximo (las que no tienes, igual que las demas)
		var libres: Array = []
		for c in Cartas.LISTA:
			if int(c["rareza"]) <= int(o["hasta"]) and int(nivel_carta.call(String(c["id"]))) < Cartas.NIVEL_MAX:
				libres.append(String(c["id"]))
		if libres.is_empty():
			o = o["si_no"]
		else:
			var id: String = libres[rng.randi() % libres.size()]
			return {"t": "carta", "v": id, "n": rng.randi_range(int(o["min"]), int(o["max"])),
				"nueva": int(nivel_carta.call(id)) <= 0}
	if String(o["t"]) == "articulo":
		var libres: Array = []
		for k in o["pool"]:
			if not bool(tengo.call(String(k))):
				libres.append(String(k))
		if libres.is_empty():
			o = o["si_no"]
		else:
			return {"t": "articulo", "v": libres[rng.randi() % libres.size()]}
	return {"t": String(o["t"]), "v": rng.randi_range(int(o["min"]), int(o["max"]))}


## Abrir el primero de los pendientes. "enviado" (con cuenta: el resultado llega con Cuenta.cofre_abierto(resultado)),
## "hecho" (sin cuenta: ya esta en `ultimo`) o "no" (no hay cofres).
static func abrir() -> String:
	if cuantos() <= 0:
		return "no"
	if Cuenta.conectado():
		return "enviado" if Cuenta.cofre_abrir() else "no"
	var inicio := int(Settings.cofres.pop_front())
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	ultimo = tirar(inicio, func(k: String) -> bool: return Settings.tengo(k), rng)
	_dar_local(ultimo["premio"])
	Settings.save()
	return "hecho"


static func _dar_local(p: Dictionary) -> void:
	match String(p.get("t", "")):
		"oro":
			Settings.monedas += int(p["v"])
		"cubos":
			Settings.cubos += int(p["v"])
		"carta":
			Cartas.dar_local(String(p["v"]), int(p.get("n", 1)))
		"articulo":
			var k := String(p["v"])
			if k.begins_with("modelo:"):
				if not k.substr(7) in Settings.modelos_comprados:
					Settings.modelos_comprados.append(k.substr(7))
			elif not k in Settings.armas_compradas:
				Settings.armas_compradas.append(k)
		# (los diamantes no existen sin cuenta: la mitica sin articulos libres solo sale con cuenta)


## La rareza en bonito: {"nombre", "color"} (las de las pinturas)
static func rareza(i: int) -> Dictionary:
	return SkinsArmas.RAREZAS[clampi(i, 0, SkinsArmas.RAREZAS.size() - 1)]


## El nombre de lo que ha tocado ("35 ORO", "20 CUBOS DE FUERZA", "SELVA DIGITAL"...)
static func nombre_premio(p: Dictionary) -> String:
	match String(p.get("t", "")):
		"oro":
			return "%d ORO" % int(p["v"])
		"cubos":
			return "%d CUBOS DE FUERZA" % int(p["v"])
		"diamantes":
			return "%d DIAMANTES" % int(p["v"])
		"carta":
			return "%s ×%d" % [String(Cartas.datos(String(p["v"])).get("nombre", "CARTA")), int(p.get("n", 1))]
		"articulo":
			var k := String(p["v"])
			if k.begins_with("modelo:"):
				return TiendaAjustes.nombre(k, k.substr(7)).to_upper()
			if Weapons.SKINS_ARMA.has(k):
				return TiendaAjustes.nombre(k, String(Weapons.NOMBRE_SKIN.get(k, k))).to_upper()
			return String(SkinsArmas.nombre_de(k))
	return "?"


## La tabla para el servidor (--exportarprecios la escribe en servidor/progreso.json)
static func para_servidor() -> Dictionary:
	return {"toques": TOQUES, "sube": SUBE, "premios": PREMIOS, "cartas": Cartas.para_servidor()}
