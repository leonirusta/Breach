class_name TiendaAjustes
## LOS AJUSTES DE LA TIENDA QUE PONE EL PANEL (2026-09-29, pedido: "que el APK del administrador pueda editar los
## nombres de los productos de la tienda y modificar precios").
##
## El servidor guarda precios y nombres propios ENCIMA de la lista del juego (servidor/index.js, "LOS AJUSTES DE LA
## TIENDA") y cobra con ellos. Cuenta los pide con GET /tienda al arrancar y cada vez que el latido dice que cambiaron
## (`tv`), y se guardan en disco para enseñarlos igual sin conexion.
##
## Las armas y las pinturas se cambian EN SU CATALOGO (Weapons._catalog, SkinsArmas._catalogo), guardando lo de fabrica
## aparte: asi el nombre nuevo sale en todas partes (tienda, mochila, HUD, muerte...) sin tocar cada sitio. Los mazos,
## los personajes y los niveles de las habilidades se preguntan aqui (`precio()` / `nombre()`) donde se enseñan.
## Las claves son las del servidor: el id del arma o de la pintura, el del mazo, "modelo:<nombre>" y "hab_<id>_<n>".

const RUTA := "user://tienda_ajustes.json"

static var precios: Dictionary = {}     ## clave -> precio del panel
static var nombres: Dictionary = {}     ## clave -> nombre del panel
## LOS AJUSTES DEL JUEGO del panel (2026-09-30): cofres, cartas, personajes, oro de partida, pase... Lo que no este es lo
## de fabrica. Las claves y lo que es cada una: servidor/index.js, "LOS AJUSTES DEL JUEGO". Se leen con `juego()`.
static var ajustes_juego: Dictionary = {}
## LOS DESTACADOS de la tienda que pone el panel: [{"clave", "precio", "moneda": "monedas" | "creditos"}]
static var destacados: Array = []
static var version := -1
static var _orig_arma: Dictionary = {}      ## id -> [nombre, precio] de fabrica
static var _orig_pintura: Dictionary = {}   ## id -> nombre de fabrica


## Lo que cuesta: el del panel si lo cambio, si no `defecto` (el de fabrica)
static func precio(clave: String, defecto: int) -> int:
	var p := int(precios.get(clave, 0))
	return p if p > 0 and defecto > 0 else defecto


static func nombre(clave: String, defecto: String) -> String:
	var n := String(nombres.get(clave, ""))
	return n if n != "" else defecto


## Un ajuste del juego: el del panel o `defecto` (el de fabrica)
static func juego(clave: String, defecto: Variant) -> Variant:
	var v = ajustes_juego.get(clave, null)
	return defecto if v == null else v


## LOS BLOQUEOS DEL PANEL (2026-10-03, pedido: "bloquear un mapa, un personaje, un articulo o un modo para que nadie lo
## use mientras arreglo un bug, subir la actualizacion y volver a activarlo"). El ajuste del juego `bloqueos` =
## {mapas, modos, personajes, articulos}: listas de ids ("nuke", "royale", "specter", "carabina_556", "sk_oxido",
## "modelo:Civil", "mazo_obra"...). Lo bloqueado no sale (mapas, tienda), sale con candado (modos, personajes), no se
## compra (aqui y en el servidor) y no se usa en partida (el arma o la pintura vuelven a las de serie; el personaje, al
## soldado). De fabrica, NUKE (sin terminar). `--sinbloqueos` lo ignora (pruebas).
const BLOQUEOS_FABRICA := {"mapas": ["nuke"], "modos": [], "personajes": [], "articulos": []}
static var _sin_bloqueos: bool = "--sinbloqueos" in OS.get_cmdline_user_args()

static func bloqueos() -> Dictionary:
	var b = juego("bloqueos", null)
	return b if b is Dictionary else BLOQUEOS_FABRICA


static func bloqueado(tipo: String, id: String) -> bool:
	if _sin_bloqueos or id == "":
		return false
	var l = bloqueos().get(tipo, [])
	return l is Array and id in l


## El destacado del panel de una clave ({} si no lo es)
static func destacado(clave: String) -> Dictionary:
	for d in destacados:
		if d is Dictionary and String(d.get("clave", "")) == clave:
			return d
	return {}


## Lo que manda el servidor: {"v", "precios": {clave: n}, "nombres": {clave: texto}, "destacados": [...], "juego": {...}}
static func aplicar(j: Dictionary, guardar := true) -> void:
	precios = {}
	nombres = {}
	var jg = j.get("juego", {})
	ajustes_juego = jg if jg is Dictionary else {}
	destacados = []
	var de = j.get("destacados", [])
	if de is Array:
		for d in de:
			if d is Dictionary and int(d.get("precio", 0)) > 0:
				destacados.append({"clave": String(d.get("clave", "")), "precio": int(d["precio"]),
					"moneda": "creditos" if String(d.get("moneda", "")) == "creditos" else "monedas"})
	var pr = j.get("precios", {})
	if pr is Dictionary:
		for k in pr:
			var p := int(pr[k])
			if p > 0:
				precios[String(k)] = p
	var no = j.get("nombres", {})
	if no is Dictionary:
		for k in no:
			var n := String(no[k]).strip_edges().left(40)
			if n != "":
				nombres[String(k)] = n
	version = int(j.get("v", 0))
	_al_catalogo()
	_al_juego()
	if guardar:
		var f := FileAccess.open(RUTA, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"v": version, "precios": precios, "nombres": nombres,
				"destacados": destacados, "juego": ajustes_juego}))


## Los de la ultima vez (sin conexion tambien se ven los precios y los nombres del panel)
static func cargar_disco() -> void:
	if not FileAccess.file_exists(RUTA):
		return
	var j = JSON.parse_string(FileAccess.get_file_as_string(RUTA))
	if j is Dictionary:
		aplicar(j, false)


## Todo a fabrica (--exportarprecios: lo que se exporta al servidor es la lista del juego, no la del panel)
static func limpiar() -> void:
	precios = {}
	nombres = {}
	ajustes_juego = {}
	destacados = []
	_al_catalogo()
	_al_juego()


## Lo que se guarda calculado y depende de los ajustes del juego: se rehace
static func _al_juego() -> void:
	PaseBatalla._niveles = []
	Cartas._cache_efectos = {}


static func _al_catalogo() -> void:
	var cat := Weapons.catalog()
	for id in cat:
		var d: Dictionary = cat[id]
		if not _orig_arma.has(id):
			_orig_arma[id] = [String(d.get("name", id)), int(d.get("precio", 0))]
		var o: Array = _orig_arma[id]
		d["name"] = nombre(String(id), String(o[0]))
		d["precio"] = precio(String(id), int(o[1]))
	for sk in SkinsArmas.catalogo():
		var sid := String(sk["id"])
		if not _orig_pintura.has(sid):
			_orig_pintura[sid] = String(sk["nombre"])
		sk["nombre"] = nombre(sid, String(_orig_pintura[sid]))
