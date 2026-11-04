class_name Weapons
## Definición de armas. `power` es la potencia de destrucción en la escala de materiales de vxcore
## (cristal 10, pladur 30, madera 55, ladrillo 120, hormigón 170, metal 200).
##
## EL CATÁLOGO SALE DE BLENDER. Las catorce armas de fuego se modelan en tools/blender/armas/ y se
## exportan a res://armas/*.glb junto con res://armas/armas.json, que trae el id, el nombre y el tipo
## de cada una. Aquí sólo viven sus ESTADÍSTICAS y su precio: así no hay dos listas que mantener y es
## imposible que el arma que ves y el arma que dispara sean distintas.
##
## NO HAY ACCESORIOS. Cada arma trae su mira soldada de fábrica (ver weapon_model.gd): no se montan
## piezas, se elige el arma. El mazo, la C4 y el fusil láser no salen de Blender: son de código.
##
## `LIST` es el equipamiento de la partida (ranuras PRIMARIA, SECUNDARIA, PESADA + C4), construido con
## `rebuild()` a partir de Settings.loadout. Todo el código del juego sigue indexando `Weapons.LIST`.

const WeaponModel := preload("res://scripts/weapon_model.gd")
const EscudoScript := preload("res://scripts/escudo.gd")

const FAMILY := {
	"rifle":   {"mag": 30, "reserve": 150, "rps": 10.0, "damage": 27.0, "power": 70, "spread": 0.012, "recoil": 0.012, "range": 180.0, "pellets": 1, "reload": 2.2, "impulse": 2.5, "auto": true, "explosive": false, "ads_fov": 0.62, "sound": "rifle"},
	"smg":     {"mag": 30, "reserve": 180, "rps": 12.5, "damage": 20.0, "power": 55, "spread": 0.020, "recoil": 0.009, "range": 70.0, "pellets": 1, "reload": 1.8, "impulse": 1.5, "auto": true, "explosive": false, "ads_fov": 0.75, "sound": "smg"},
	"shotgun": {"mag": 6, "reserve": 36, "rps": 1.5, "damage": 11.0, "power": 60, "spread": 0.055, "recoil": 0.045, "range": 35.0, "pellets": 9, "reload": 2.4, "impulse": 1.5, "auto": false, "explosive": false, "ads_fov": 0.8, "sound": "shotgun"},
	"sniper":  {"mag": 10, "reserve": 40, "rps": 2.5, "damage": 75.0, "power": 110, "spread": 0.003, "recoil": 0.05, "range": 400.0, "pellets": 1, "reload": 2.8, "impulse": 4.0, "auto": false, "explosive": false, "ads_fov": 0.35, "sound": "sniper"},
	"pistol":  {"mag": 8, "reserve": 48, "rps": 5.0, "damage": 22.0, "power": 45, "spread": 0.018, "recoil": 0.018, "range": 60.0, "pellets": 1, "reload": 1.4, "impulse": 1.0, "auto": false, "explosive": false, "ads_fov": 0.8, "sound": "pistol"},
	"rocket":  {"mag": 1, "reserve": 1, "rps": 0.9, "damage": 130.0, "power": 255, "spread": 0.0, "recoil": 0.06, "range": 250.0, "pellets": 1, "reload": 2.6, "impulse": 0.0, "auto": false, "explosive": true, "radius": 4.0, "ads_fov": 0.75, "sound": "rocket"},
	# Láser: haz continuo de alta cadencia, sin dispersión ni retroceso y con muchísimo alcance.
	# Poco daño por impacto pero 20 por segundo, y potencia alta: corta la pared por donde pasa.
	"laser":   {"mag": 120, "reserve": 480, "rps": 20.0, "damage": 9.0, "power": 150, "spread": 0.0, "recoil": 0.0, "range": 300.0, "pellets": 1, "reload": 2.0, "impulse": 0.5, "auto": true, "explosive": false, "ads_fov": 0.55, "sound": "spark"},
	# MAZO (cuerpo a cuerpo). No gasta municion: `mag` -1 = infinito. El "power" 255 es lo que le
	# permite partir hormigon, igual que el de Teardown.
	"sledge":  {"mag": 1, "reserve": 0, "rps": 1.15, "damage": 34.0, "power": 255, "spread": 0.0, "recoil": 0.03, "range": 3.0, "pellets": 1, "reload": 0.0, "impulse": 6.0, "auto": true, "explosive": false, "radius": 0.64, "ads_fov": 1.0, "sound": "sledge", "melee": true},
	# ESCUDO BALISTICO + PISTOLA (escudo.gd): dispara la pistola de 9 mm, algo menos precisa porque se tira
	# asomando por el canto del escudo, y la recarga es mas lenta porque se hace con el escudo delante.
	"escudo":  {"mag": 17, "reserve": 85, "rps": 5.0, "damage": 20.0, "power": 45, "spread": 0.018, "recoil": 0.013, "range": 55.0, "pellets": 1, "reload": 1.8, "impulse": 1.0, "auto": false, "explosive": false, "ads_fov": 0.82, "sound": "pistol"},
	"c4":      {"mag": 1, "reserve": 0, "rps": 1.5, "damage": 120.0, "power": 240, "spread": 0.0, "recoil": 0.0, "range": 4.0, "pellets": 1, "reload": 0.0, "impulse": 0.0, "auto": false, "explosive": true, "radius": 3.0, "ads_fov": 1.0, "sound": "c4"},
}

## LO QUE HACE DISTINTA A CADA ARMA. Lo que no aparece lo hereda de su familia. `ads_fov` mas bajo =
## mas zoom al encarar, y va con la OPTICA que lleva puesta el modelo: la carabina trae un prisma, el
## fusil 7,62 miras de hierro, y el rifle de precision una telescopica de verdad.
const STATS := {
	# --- FUSILES ---
	"carabina_556": {"rps": 11.5, "damage": 24.0, "spread": 0.011, "recoil": 0.009, "range": 145.0,
		"reload": 1.9, "mag": 30, "reserve": 180, "ads_fov": 0.52, "power": 70},
	"fusil_762": {"rps": 8.0, "damage": 36.0, "spread": 0.015, "recoil": 0.021, "range": 175.0,
		"reload": 2.4, "mag": 30, "reserve": 150, "ads_fov": 0.72, "power": 95},
	"fusil_bullpup": {"rps": 10.0, "damage": 26.0, "spread": 0.009, "recoil": 0.010, "range": 150.0,
		"reload": 2.1, "mag": 30, "reserve": 180, "ads_fov": 0.60, "sound": "silenced", "fogonazo": 0.2},
	# --- SUBFUSILES ---
	"smg_9mm": {"rps": 13.0, "damage": 19.0, "spread": 0.016, "recoil": 0.008, "range": 80.0,
		"reload": 1.9, "mag": 30, "reserve": 210, "ads_fov": 0.70},
	"smg_compacta": {"rps": 16.0, "damage": 15.0, "spread": 0.027, "recoil": 0.010, "range": 50.0,
		"reload": 1.6, "mag": 32, "reserve": 224, "ads_fov": 0.82, "power": 45},
	"pdw_57": {"rps": 14.0, "damage": 18.0, "spread": 0.014, "recoil": 0.007, "range": 90.0,
		"reload": 1.7, "mag": 40, "reserve": 240, "ads_fov": 0.68, "power": 75},
	# --- ESCOPETAS ---
	# LA DE BOMBEO (2026-10-01, pedido): UN tiro por pulsacion tambien en el movil ("bombeo": hay que soltar y volver a
	# tocar, player.gd) y mucho mas dañina que la automatica: 9 x 15 = 135 por tiro contra 8 x 11 = 88
	"escopeta_bomba": {"rps": 1.3, "damage": 15.0, "pellets": 9, "spread": 0.060, "recoil": 0.048,
		"range": 30.0, "reload": 2.8, "mag": 6, "reserve": 42, "ads_fov": 0.85, "bombeo": true},
	# la automatica dispara mientras se mantenga apretado (tambien en el PC)
	"escopeta_auto": {"rps": 2.8, "damage": 11.0, "pellets": 8, "spread": 0.048, "recoil": 0.034,
		"range": 36.0, "reload": 2.4, "mag": 8, "reserve": 48, "ads_fov": 0.74, "auto": true},
	# --- PRECISION ---
	"rifle_precision": {"rps": 1.1, "damage": 95.0, "spread": 0.001, "recoil": 0.045, "range": 350.0,
		"reload": 3.0, "mag": 5, "reserve": 35, "ads_fov": 0.28, "power": 130},
	# --- CORTAS ---
	"pistola_9": {"rps": 6.0, "damage": 20.0, "spread": 0.014, "recoil": 0.011, "range": 55.0,
		"reload": 1.3, "mag": 17, "reserve": 85},
	"pistola_45": {"rps": 5.0, "damage": 30.0, "spread": 0.011, "recoil": 0.017, "range": 60.0,
		"reload": 1.4, "mag": 10, "reserve": 60, "ads_fov": 0.76, "power": 60},
	"revolver_44": {"rps": 2.2, "damage": 55.0, "spread": 0.008, "recoil": 0.042, "range": 85.0,
		"reload": 2.6, "mag": 6, "reserve": 36, "power": 95, "impulse": 2.0},
	# --- PESADAS ---
	"bazooka_rpg": {"damage": 130.0, "radius": 4.2, "reserve": 3, "reload": 3.0, "ads_fov": 0.80},
	"bazooka_at4": {"damage": 115.0, "radius": 3.6, "reserve": 4, "reload": 2.4, "ads_fov": 0.58},
}

## Lo que cuesta cada arma en la armería. 0 = la tienes desde el principio.
const PRECIOS := {
	"smg_compacta": 0, "pistola_9": 0, "escopeta_bomba": 0,   # gratis: el equipo de una cuenta nueva (2026-09-18)
	"carabina_556": 600, "pistola_45": 800, "smg_9mm": 900,
	"revolver_44": 1300, "fusil_762": 1400, "pdw_57": 1800,
	"bazooka_at4": 2000, "escopeta_auto": 2200, "bazooka_rpg": 2600,
	"fusil_bullpup": 3200, "rifle_precision": 3800,
	"escudo_pistola": 4500,
}

const GRENADE_RADIUS := 2.6
const GRENADE_POWER := 200
const GRENADE_DAMAGE := 90.0
const GRENADE_FUSE := 2.4

const SLOTS := ["primary", "secondary", "heavy"]
const SLOT_NAMES := {"primary": "PRIMARIA", "secondary": "SECUNDARIA", "heavy": "PESADA"}
## El MAZO se equipa en la ranura pesada: o llevas lanzacohetes o llevas mazo.
const SLOT_KINDS := {"primary": ["rifle", "smg", "shotgun", "sniper", "escudo"], "secondary": ["pistol", "smg", "shotgun", "escudo"], "heavy": ["rocket", "sledge"]}
const KIND_NAMES := {"vacio": "Sin arma", "rifle": "Fusil", "smg": "Subfusil", "shotgun": "Escopeta", "sniper": "Francotirador", "pistol": "Pistola", "rocket": "Lanzacohetes", "c4": "Explosivo", "laser": "Láser", "sledge": "Mazo", "escudo": "Escudo", "ammo": "Munición"}
## Como se llama la mira que trae cada arma soldada. Sale de la ficha de Blender (`optica`).
const OPTICAS := {
	"hierro": "Miras de hierro", "diopter": "Alza de diopter", "punto": "Punto rojo",
	"holo": "Holográfica", "prisma": "Óptica de prisma", "visor": "Telescópica",
	"grano": "Grano y anillo", "micro": "Micro punto rojo", "pgo": "Óptica PGO", "tubo": "Óptica 2x",
}

static var _catalog: Dictionary = {}     # id -> definición completa
static var LIST: Array[Dictionary] = []   # equipamiento de la partida (ver rebuild)
## EL MAZO PRIMERO (2026-10-21, pedido: "en el battle royale empiezo solo con el mazo y sale con el 3: deberia ser el 1, y
## el arma que coja, el 2"): en las tres primeras ranuras se cuentan primero el mazo y luego las armas que haya, sin las
## vacias. Lo pone main en el battle royale; lo usan la barra (el numero) y las teclas 1-2-3.
static var mazo_primero := false


## las ranuras 0..2 en el orden en que se ven y se numeran
static func orden_ranuras() -> Array:
	var r: Array = []
	var n := mini(3, LIST.size())
	if not mazo_primero:
		for i in n:
			r.append(i)
		return r
	for i in n:
		if String(LIST[i].get("kind", "")) == "sledge":
			r.append(i)
	for i in n:
		var k := String(LIST[i].get("kind", ""))
		if k != "sledge" and k != "vacio":
			r.append(i)
	return r


## la ranura de la tecla 1, 2 o 3 (n = 0, 1, 2); -1 si no hay
static func ranura_de_tecla(n: int) -> int:
	if not mazo_primero:
		return n
	var o := orden_ranuras()
	return o[n] if n < o.size() else -1
## La C4 sólo se lleva en los mapas con sitios de bomba (dust2). En la ciudad no pinta nada, así
## que ni aparece en la ranura ni en la barra de armas. Lo fija main.gd antes de rebuild().
static var with_c4 := true


## Catálogo completo: las catorce de Blender + mazo, C4 y láser. Cada entrada: id, name, kind, stats.
static func catalog() -> Dictionary:
	if not _catalog.is_empty():
		return _catalog
	for id in WeaponModel.ficha().keys():
		var f: Dictionary = WeaponModel.ficha()[id]
		var nom = f.get("nombre")
		var tipo = f.get("kind")
		var d := _make(id, String(nom) if nom != null else id,
			String(tipo) if tipo != null else "rifle", STATS.get(id, {}))
		d["precio"] = int(PRECIOS.get(id, 0))
		# OJO CON `get(clave, por_defecto)`: el valor por defecto solo se usa si la clave NO ESTA. El
		# mazo chupetin trae "optica": null -un mazo no lleva mira- asi que la clave si esta y lo que
		# llegaba a String() era null: "Invalid call 'String' constructor" en cada arranque. Un arma
		# sin optica es normal, asi que se arregla aqui y no en el .json.
		var op = f.get("optica")
		d["optica"] = String(op) if op != null else ""
		_catalog[id] = d
	# LAS SKINS NO SON ARMAS. Un modelo alternativo del mazo esta en `armas.json` igual que un fusil
	# -es lo que le da su .glb-, pero no se compra ni se equipa como arma aparte: se elige en la
	# pestaña de SKINS y sustituye al modelo del arma que ya tienes.
	for sid in SKINS_ARMA:
		_catalog.erase(sid)
	# las tres de codigo (weapon_model.gd): no tienen modelo de Blender ni se compran en la armeria
	_catalog["c4"] = _make("c4", "C4", "c4", {})
	_catalog["laser"] = _make("laser", "FUSIL LÁSER", "laser", {})
	_catalog["sledge"] = _make("sledge", "MAZO", "sledge", {})
	# RANURA VACIA. En el battle royale se empieza sin armas: las dos primeras ranuras llevan esto, que
	# no dispara ni recarga, y se sustituyen en cuanto coges un arma del suelo. No es un arma de verdad,
	# asi que no sale en la armeria ni se puede equipar desde el menu.
	_catalog["vacio"] = _make("vacio", "SIN ARMA", "vacio", {"mag": 0, "reserve": 0, "damage": 0.0,
		"rps": 0.5, "range": 0.0, "melee": false, "auto": false})
	# el escudo tampoco sale de la ficha de armas: es escudo_balistico.glb + la pistola de 9 mm (escudo.gd)
	var esc := _make("escudo_pistola", "ESCUDO BALÍSTICO", "escudo", {"precio": int(PRECIOS["escudo_pistola"])})
	esc["optica"] = "hierro"
	_catalog["escudo_pistola"] = esc
	return _catalog


## Modelos que son SKIN y no arma. Id de `armas.json` -> a que arma le cambian el aspecto.
const SKINS_ARMA := {
	"mazo_chupetin": "sledge", "mazo_obra": "sledge", "mazo_llave": "sledge",
	"mazo_senal": "sledge", "mazo_extintor": "sledge", "mazo_tempano": "sledge",
	"mazo_plasma": "sledge", "mazo_femur": "sledge", "mazo_yunque": "sledge",
	"mazo_trofeo": "sledge",
}
## Como se llaman en la tienda.
const NOMBRE_SKIN := {
	"mazo_chupetin": "MAZO CHUPETÍN", "mazo_obra": "MAZO DE OBRA",
	"mazo_llave": "LLAVE DEL MECÁNICO", "mazo_senal": "SEÑAL DE STOP",
	"mazo_extintor": "EXTINTOR", "mazo_tempano": "TÉMPANO",
	"mazo_plasma": "MARTILLO DE PLASMA", "mazo_femur": "FÉMUR",
	"mazo_yunque": "YUNQUE", "mazo_trofeo": "TROFEO",
}
## Una linea que diga QUE ES, debajo del retrato de la tienda.
const LEMA_SKIN := {
	"mazo_chupetin": "bola rosa y palo blanco",
	"mazo_obra": "acero forjado y fibra naranja",
	"mazo_llave": "llave inglesa del tamaño de un remo",
	"mazo_senal": "arrancada de la esquina, con poste",
	"mazo_extintor": "bombona, latón y manguera",
	"mazo_tempano": "hielo tallado, encendido por dentro",
	"mazo_plasma": "cabeza partida con el núcleo en medio",
	"mazo_femur": "hueso viejo, cuero y cuatro clavos",
	"mazo_yunque": "un yunque entero en la punta",
	"mazo_trofeo": "copa de oro con peana",
}
## EL PRECIO SUBE CON LO QUE LUCE, no con lo que costo hacerlo: los dos de mapa son baratos y los
## que llevan pieza encendida (tempano, plasma) o dorada son los caros.
const PRECIO_SKIN := {
	"mazo_chupetin": 1200, "mazo_obra": 600, "mazo_llave": 800,
	"mazo_senal": 1000, "mazo_extintor": 1100, "mazo_femur": 1400,
	"mazo_yunque": 1300, "mazo_tempano": 1900, "mazo_plasma": 2200,
	"mazo_trofeo": 2500,
}


## El modelo que hay que cargar para un arma, mirando si tiene skin puesta.
static func modelo_de(id: String) -> String:
	if id == "sledge" and Settings.skin_mazo != "":
		return Settings.skin_mazo
	return id


static func _make(id: String, name: String, kind: String, over: Dictionary) -> Dictionary:
	var d: Dictionary = (FAMILY.get(kind, FAMILY["rifle"]) as Dictionary).duplicate()
	for k in over.keys():
		d[k] = over[k]
	d["id"] = id
	d["name"] = name
	d["kind"] = kind
	d["model"] = kind          # tipo de pose de sujeción (player.gd FP_HOLD / avatar_animator)
	d["precio"] = int(over.get("precio", 0))
	return d


static func get_def(id: String) -> Dictionary:
	var c := catalog()
	return c.get(id, c.get(default_for("primary")))


## Lo que cuesta un arma. 0 = la tienes desde el principio.
static func precio(id: String) -> int:
	return int(get_def(id).get("precio", 0))


## TODAS las armas que se pueden equipar, en orden alfabetico. La C4 y el laser no salen: viven en
## ranuras fijas (la 4 y la 5) y no se eligen.
static func ids_equipables() -> Array:
	var out: Array = []
	for id in catalog().keys():
		if String(catalog()[id]["kind"]) in ["c4", "laser", "ammo", "vacio"]:
			continue
		out.append(id)
	out.sort_custom(func(a, b): return String(catalog()[a]["name"]).naturalnocasecmp_to(String(catalog()[b]["name"])) < 0)
	return out


static func ids_for_slot(slot: String) -> Array:
	var out: Array = []
	var kinds: Array = SLOT_KINDS.get(slot, [])
	for id in catalog().keys():
		if String(catalog()[id]["kind"]) in kinds:
			out.append(id)
	out.sort_custom(func(a, b): return String(catalog()[a]["name"]).naturalnocasecmp_to(String(catalog()[b]["name"])) < 0)
	return out


## Construye LIST a partir del equipamiento guardado (Settings.loadout).
static func rebuild() -> void:
	LIST.clear()
	for slot in SLOTS:
		var id: String = Settings.loadout.get(slot, "")
		# CUALQUIER ARMA EN CUALQUIER RANURA: sólo se corrige si lo guardado está vacío o ya no existe
		# en el catálogo (por ejemplo una partida vieja con los ids de antes).
		if id == "" or not catalog().has(id):
			id = default_for(slot)
		# BLOQUEADA DESDE EL PANEL (un bug, una mejora): se juega con la de serie de su ranura hasta que la vuelvan a activar
		elif TiendaAjustes.bloqueado("articulos", id):
			id = default_for(slot)
		LIST.append(get_def(id).duplicate())
	if with_c4:
		LIST.append(get_def("c4").duplicate())
	# EL LASER NO VIENE DE SERIE: hay que COMPRARLO en la tienda del modo zombis (pve.gd), y sólo
	# entonces se suma a la lista.
	if con_laser:
		LIST.append(get_def("laser").duplicate())


## Lo enciende la tienda del PvE al comprar el laser; se apaga al empezar una partida nueva.
static var con_laser := false


static func default_for(slot: String) -> String:
	match slot:
		"primary": return "smg_compacta"
		"secondary": return "pistola_9"
		_: return "sledge"


## Valor 0..1 de una estadística para las barras de la armería.
static func stat_bar(d: Dictionary, stat: String) -> float:
	match stat:
		"damage": return clampf(float(d.damage) * float(d.pellets) / 130.0, 0.05, 1.0)
		"rps": return clampf(float(d.rps) / 15.0, 0.05, 1.0)
		"range": return clampf(float(d.range) / 300.0, 0.05, 1.0)
		"recoil": return clampf(1.0 - float(d.recoil) / 0.08, 0.05, 1.0)
		"mag": return clampf(float(d.mag) / 64.0, 0.05, 1.0)
	return 0.5


## LAS ARMAS QUE NO LLEVAS EN LA MANO, para verlas colgadas del muñeco (avatar_animator.set_armas_guardadas).
## "tipo|modelo|skin" separadas por ";". Fuera la C4, el laser, la municion y las manos vacias.
## `escudo_roto`: el escudo ya se tiro (bug: "me rompieron el escudo, cambie de arma y lo tenia en la espalda"); de el
## queda solo su pistola, que se cuelga como pistola.
static func guardadas(actual: int, escudo_roto := false) -> String:
	var out: Array = []
	for i in LIST.size():
		if i == actual:
			continue
		var w: Dictionary = LIST[i]
		var k := String(w.get("model", w.get("kind", "")))
		if k in ["c4", "laser", "ammo", "vacio", ""]:
			continue
		var mid := modelo_de(String(w.get("id", "")))
		if k == "escudo" and escudo_roto:
			k = "pistol"
			mid = EscudoScript.PISTOLA
		out.append("%s|%s|%s" % [k, mid, SkinsArmas.equipada(mid)])
	return ";".join(out)
