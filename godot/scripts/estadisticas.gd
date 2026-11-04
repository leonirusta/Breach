## ESTADISTICAS DEL JUGADOR (2026-09-23, pedido). Todo lo que se cuenta partida a partida y se guarda en
## user://estadisticas.cfg: partidas, victorias, bajas, muertes, disparos, aciertos, tiempo jugado, la mejor
## racha de bajas sin morir, la oleada mas alta en el modo zombi y cuantas veces se ha jugado cada mapa.
## Solo cuenta lo de ESTE jugador (Net.local_player); los bots y los demas no suman aqui.
## Se guarda al acabar cada partida y como mucho cada 30 s mientras se juega (no en cada disparo).
extends RefCounted

const RUTA := "user://estadisticas.cfg"     ## sin cuenta (las de este aparato)
## POR CUENTA (2026-10-12, bug: "una cuenta nueva tiene mas de 100 partidas"): iban en un archivo por aparato, asi que una
## cuenta nueva enseñaba todas las partidas jugadas antes en ese movil. Con sesion, un archivo por usuario; y PARTIDAS y
## VICTORIAS salen del servidor (perfil: partidas, ganadas), que las lleva por cuenta.
## El md5 del usuario se calculaba en CADA fotograma (tick -> _cargar -> _ruta): ahora solo cuando cambia el usuario.
static var _ruta_usuario := ""
static var _ruta_hecha := ""
static func _ruta() -> String:
	var u := String(Cuenta.perfil.get("usuario", "")) if Cuenta.conectado() else ""
	if u == "":
		return RUTA
	if u != _ruta_usuario:
		_ruta_usuario = u
		_ruta_hecha = "user://estadisticas_%s.cfg" % u.md5_text().substr(0, 16)
	return _ruta_hecha
static var _ruta_cargada := ""
const CLAVES := ["partidas", "victorias", "derrotas", "bajas", "bajas_zombis", "muertes", "disparos", "aciertos",
	"segundos", "mejor_racha", "oleada_max"]

static var datos := {}
static var mapas := {}
static var _cargado := false
static var _racha := 0
static var _sucio := false
static var _guardado_t := 0.0


static func _cargar() -> void:
	var ruta := _ruta()
	if _cargado and ruta == _ruta_cargada:
		return
	if _cargado and _sucio and _ruta_cargada != "":
		_guardar_en(_ruta_cargada)        # lo de la cuenta anterior, a su archivo, antes de cambiar
	_cargado = true
	_ruta_cargada = ruta
	mapas.clear()
	for k in CLAVES:
		datos[k] = 0
	var cfg := ConfigFile.new()
	if cfg.load(ruta) != OK:
		return
	for k in CLAVES:
		datos[k] = int(cfg.get_value("stats", k, 0))
	for m in (cfg.get_section_keys("mapas") if cfg.has_section("mapas") else PackedStringArray()):
		mapas[m] = int(cfg.get_value("mapas", m, 0))


static func guardar() -> void:
	_cargar()
	_guardar_en(_ruta_cargada)


static var _sin_hilo := OS.get_cmdline_user_args().has("--estadisticassinhilo")
static func _guardar_en(ruta: String, en_hilo: bool = false) -> void:
	var cfg := ConfigFile.new()
	for k in CLAVES:
		cfg.set_value("stats", k, int(datos.get(k, 0)))
	for m in mapas.keys():
		cfg.set_value("mapas", String(m), int(mapas[m]))
	# EN PARTIDA, A DISCO EN UN HILO (2026-10-27): escribir el archivo en el hilo principal eran 1-20 ms de tiron
	# cada 30 s (mas con el disco frio). El ConfigFile ya esta montado aqui: el hilo solo lo escribe.
	if en_hilo and not _sin_hilo:
		WorkerThreadPool.add_task(func(): cfg.save(ruta))
	else:
		cfg.save(ruta)
	_sucio = false


static func sumar(clave: String, n: int = 1) -> void:
	_cargar()
	datos[clave] = int(datos.get(clave, 0)) + n
	_sucio = true


static func maximo(clave: String, v: int) -> void:
	_cargar()
	if v > int(datos.get(clave, 0)):
		datos[clave] = v
		_sucio = true


# --- lo que llama el juego ----------------------------------------------------------------------------
static func baja(zombi: bool = false) -> void:
	sumar("bajas_zombis" if zombi else "bajas")
	_racha += 1
	maximo("mejor_racha", _racha)

static func muerte() -> void:
	sumar("muertes")
	_racha = 0

static func empieza_partida(mapa: String) -> void:
	_cargar()
	_racha = 0
	sumar("partidas")
	mapas[mapa] = int(mapas.get(mapa, 0)) + 1
	guardar()

static func fin_partida(gane: bool) -> void:
	sumar("victorias" if gane else "derrotas")
	guardar()

## Cada fotograma de partida: el tiempo jugado, y guardar de vez en cuando lo que haya cambiado.
static func tick(dt: float) -> void:
	_cargar()
	_guardado_t += dt
	if _guardado_t >= 1.0:
		sumar("segundos", int(_guardado_t))
		_guardado_t -= float(int(_guardado_t))
	if _sucio and Time.get_ticks_msec() % 30000 < 20:
		_cargar()
		_guardar_en(_ruta_cargada, true)


# --- para la pantalla ---
## Los numeros (estadisticas_pantalla.gd). Con sesion, partidas y victorias son las del servidor.
static func valores() -> Dictionary:
	_cargar()
	var d: Dictionary = datos.duplicate()
	if Cuenta.conectado():
		d["partidas"] = int(Cuenta.perfil.get("partidas", d["partidas"]))
		d["victorias"] = int(Cuenta.perfil.get("ganadas", d["victorias"]))
		d["derrotas"] = maxi(0, int(d["partidas"]) - int(d["victorias"]))
	var fav := "-"
	var fav_n := 0
	for m in mapas.keys():
		if int(mapas[m]) > fav_n:
			fav_n = int(mapas[m])
			fav = String(m)
	d["mapa_favorito"] = fav
	d["mapa_favorito_n"] = fav_n
	return d


static func resumen() -> Array:
	_cargar()
	var d := datos
	var bajas_tot: int = int(d["bajas"]) + int(d["bajas_zombis"])
	var kd: float = float(bajas_tot) / maxf(1.0, float(d["muertes"]))
	var prec: float = 100.0 * float(d["aciertos"]) / maxf(1.0, float(d["disparos"]))
	var pct_vic: float = 100.0 * float(d["victorias"]) / maxf(1.0, float(int(d["victorias"]) + int(d["derrotas"])))
	var seg: int = int(d["segundos"])
	var fav := "-"
	var fav_n := 0
	for m in mapas.keys():
		if int(mapas[m]) > fav_n:
			fav_n = int(mapas[m])
			fav = String(m).to_upper()
	return [
		["PARTIDAS", str(d["partidas"])],
		["VICTORIAS", "%d  (%.0f %%)" % [int(d["victorias"]), pct_vic]],
		["BAJAS", "%d  (+%d zombis)" % [int(d["bajas"]), int(d["bajas_zombis"])]],
		["MUERTES", str(d["muertes"])],
		["K/D", "%.2f" % kd],
		["PRECISION", "%.1f %%  (%d / %d)" % [prec, int(d["aciertos"]), int(d["disparos"])]],
		["MEJOR RACHA", "%d bajas sin morir" % int(d["mejor_racha"])],
		["OLEADA MAS ALTA", str(d["oleada_max"])],
		["TIEMPO JUGADO", "%dh %02dm" % [seg / 3600, (seg / 60) % 60]],
		["MAPA FAVORITO", "%s  (%d)" % [fav, fav_n]],
	]
