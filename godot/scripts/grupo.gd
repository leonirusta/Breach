extends Node
## EL EQUIPO DEL JUGADOR (2026-09-30, pedido con captura de Pixel Gun: "FORMAR EQUIPO"). Autoload `Grupo`.
##
## "Al apretar EQUIPO en el lobby aparecera una lista de todos los amigos tuyos conectados. Podras enviarle una
## solicitud y le aparecera arriba en el lobby, con tiempo para aceptarla o rechazarla. Al aceptar, el compañero
## ingresara y apareceran en el mismo lobby, se veran juntos. El maximo depende del modo de juego."
##
## Todo lo lleva el servidor EN MEMORIA (servidor/equipos.js). Aqui solo se pregunta y se avisa:
##   - EN EL LOBBY se pregunta por /grupo/estado cada pocos segundos (mas a menudo con una invitacion en el aire o con
##     el lider montando sala). En partida no: el latido de la cuenta (cada minuto) te mantiene en el equipo y trae
##     `grupo_v`, que si cambia hace preguntar en cuanto se vuelve.
##   - `invitacion(ficha)`: te invitan (el lobby la enseña arriba con la cuenta atras, aviso_amistad.gd).
##   - `aviso(texto)`: aceptaron, rechazaron, caduco, te expulsaron... (el lobby lo pone en su letrero).
##   - `cambiado`: entro o salio alguien, cambio el lider, el modo o su aspecto (el lobby rehace los muñecos).
##   - `sala_del_lider(sala)`: el lider ha montado sala para jugar: los demas entran solos (lobby_grupo.gd).
##
## EN LA PARTIDA: cada jugador lleva en `Net.players[id]` su `grupo` (el id del equipo, "" sin equipo) y `grupo_lider`
## (net.gd, `_register`). El anfitrion pone a los del mismo equipo en el mismo bando (Net._set_team).

signal cambiado
signal invitacion(ficha: Dictionary)
signal aviso(texto: String)
signal sala_del_lider(sala: Dictionary)
## EL CHAT DEL EQUIPO EN EL LOBBY (2026-10-15, chat_equipo.gd): un mensaje de alguien del equipo (o el mio)
signal chat_llega(nombre: String, texto: String)

## El tope del equipo en cada modo: lo que cabe en un bando (bomba y duelo 5 contra 5, el atraco son tres bandos de 3,
## los zombis 4 como la campaña). El battle royale y el libre no tienen bandos: el equipo entra en la misma partida.
const MAX_POR_MODO := {"bomba": 5, "duelo": 5, "atraco": 3, "zombis": 4, "royale": 4, "libre": 5}
const MAX := 5
## Cada cuanto se pregunta en el lobby: normal / con algo en el aire
const SONDEO_S := 4.0
const SONDEO_RAPIDO_S := 2.0
## La sala del lider solo se sigue si es reciente (al volver de una partida no se entra en la de antes)
const SALA_RECIENTE_S := 75

## El equipo tal como lo manda el servidor ({} = sin equipo): {id, v, soy_lider, modo, mapa, max, miembros, sala}
var estado: Dictionary = {}
var _chat_n := -1          ## el ultimo mensaje del chat del equipo que tengo (-1: ninguno aun: no se piden los viejos)
## Las invitaciones que HE MANDADO y siguen en el aire: ID publico del amigo -> ms (reloj de aqui) en que caducan
var enviadas: Dictionary = {}
## Las invitaciones que me han llegado (ya avisadas): id -> ms en que caducan
var _vistas: Dictionary = {}
var _sala_n := -1                    ## la ultima sala del lider que ya se atendio
var _t := 1.5
var _ocupado := false
var _http: HTTPRequest
var _grupo_v := ""
var _prueba := false                  ## --equipofoto: datos de ejemplo, sin red


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_al_estado)
	# --grupoinforme=<s> (pruebas del equipo): N segundos despues de empezar la partida, quien hay en la sala, de que
	# equipo y en que bando, y fuera (el banco de dos copias lo lee del registro)
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--grupoinforme="):
			var s := float(String(a).substr(15))
			Net.match_starting.connect(func(_m: String):
				get_tree().create_timer(s).timeout.connect(_informe), CONNECT_ONE_SHOT)


func _informe() -> void:
	var yo := Net.multiplayer.get_unique_id() if Net.is_online() else 1
	var lista: Array = []
	for pid in Net.players.keys():
		var p: Dictionary = Net.players[pid]
		lista.append("%s%s[equipo %s%s · bando %s]" % [String(p.get("name", "")), " (yo)" if int(pid) == yo else "",
			String(p.get("grupo", "")).left(6), " LIDER" if bool(p.get("grupo_lider", false)) else "", String(p.get("team", "-"))])
	print("[grupoinforme] mapa %s · anfitrion %s · %d jugadores: %s" % [Net.room_map, str(Net.hosting), Net.players.size(),
		" | ".join(PackedStringArray(lista))])
	print("[grupoinforme] mi bando %s · el de mi equipo %s" % [Net.my_team(), Net.bando_de_mi_grupo()])
	get_tree().quit()


# ==================================================================================================================
# LO QUE PREGUNTA EL JUEGO
# ==================================================================================================================
func en_grupo() -> bool:
	return not estado.is_empty() and miembros().size() >= 2


func id_grupo() -> String:
	return String(estado.get("id", "")) if en_grupo() else ""


func soy_lider() -> bool:
	return en_grupo() and bool(estado.get("soy_lider", false))


func miembros() -> Array:
	var m = estado.get("miembros", [])
	return m if m is Array else []


## Los demas (sin mi)
func otros() -> Array:
	return miembros().filter(func(m): return not bool((m as Dictionary).get("yo", false)))


func tamano() -> int:
	return maxi(1, miembros().size())


func lider() -> Dictionary:
	for m in miembros():
		if bool((m as Dictionary).get("lider", false)):
			return m
	return {}


static func max_de_modo(modo: String) -> int:
	return int(MAX_POR_MODO.get(modo, MAX))


## El modo con el que va a jugar el equipo: el que tiene elegido el LIDER (el tuyo si lo eres o si no hay equipo)
func modo_del_equipo() -> String:
	var propio := String(load("res://scripts/lobby.gd")._modo_de(Settings.map))
	if not en_grupo() or soy_lider() or String(estado.get("modo", "")) == "":
		return propio
	return String(estado["modo"])


## El ID de 6 cifras como texto. OJO: el JSON trae los numeros como float y `str(482698.0)` es "482698.0", que el
## servidor no encuentra ("ese jugador no existe")
static func id_txt(v) -> String:
	if v == null:
		return ""
	if v is float or v is int:
		return str(int(v))
	return str(v)


## ¿Ya le mande una invitacion a este amigo (por su ID de 6 cifras) y sigue en el aire? Devuelve los segundos que le quedan.
func quedan_invitacion(id_pub: String) -> float:
	if not enviadas.has(id_pub):
		return 0.0
	return maxf(0.0, (float(enviadas[id_pub]) - Time.get_ticks_msec()) * 0.001)


## Pregunta ya (al abrir FORMAR EQUIPO, tras invitar...)
func pedir_ya() -> void:
	_t = minf(_t, 0.05)


# ==================================================================================================================
# LO QUE HACE EL JUGADOR. `al_acabar(ok, error)` en todas.
# ==================================================================================================================
func invitar(id_pub: String, max_modo: int, al_acabar: Callable = Callable()) -> void:
	_post("/grupo/invitar", {"id": id_pub, "max": max_modo}, func(ok: bool, j: Dictionary, err: String):
		if ok:
			enviadas[id_pub] = Time.get_ticks_msec() + int(float((j.get("invitacion", {}) as Dictionary).get("quedan", 20.0)) * 1000.0)
			pedir_ya()
		if al_acabar.is_valid():
			al_acabar.call(ok, err))


func responder(id_inv: String, aceptar: bool, al_acabar: Callable = Callable()) -> void:
	_post("/grupo/responder", {"id": id_inv, "aceptar": aceptar}, func(ok: bool, j: Dictionary, err: String):
		if ok and j.get("grupo", null) is Dictionary:
			_poner(j["grupo"])
		pedir_ya()
		if al_acabar.is_valid():
			al_acabar.call(ok, err))


func salir(al_acabar: Callable = Callable()) -> void:
	_post("/grupo/salir", {}, func(ok: bool, _j: Dictionary, err: String):
		if ok:
			_poner({})
		if al_acabar.is_valid():
			al_acabar.call(ok, err))


func expulsar(clave: String, al_acabar: Callable = Callable()) -> void:
	_post("/grupo/expulsar", {"k": clave}, func(ok: bool, _j: Dictionary, err: String):
		pedir_ya()
		if al_acabar.is_valid():
			al_acabar.call(ok, err))


## EL LIDER HA MONTADO SALA: {sala (id de Salas), mapa, modo, anfitrion, lan (sus IP de casa), puerto}. {} = ya no hay.
func anunciar_sala(d: Dictionary) -> void:
	if not soy_lider():
		return
	_post("/grupo/sala", d, func(_ok: bool, _j: Dictionary, _e: String): pedir_ya())


## Lo que trae el latido de la cuenta: si el equipo cambio mientras jugabas, se pregunta en cuanto se pueda
func del_latido(j: Dictionary) -> void:
	var v := String(j.get("grupo_v", ""))
	if v != _grupo_v:
		_grupo_v = v
		pedir_ya()


# ==================================================================================================================
# EL SONDEO
# ==================================================================================================================
func _en_lobby() -> bool:
	var escena := get_tree().current_scene
	return escena != null and escena.has_method("_abrir_centro")


func _process(dt: float) -> void:
	if _prueba:
		return
	_t -= dt
	if _t > 0.0:
		return
	# fuera del lobby no se pregunta (el latido de la cuenta hace de "sigo aqui"); sin sesion, nada
	if not _en_lobby() or not Cuenta.conectado():
		_t = 1.0
		if not Cuenta.conectado() and not estado.is_empty():
			_poner({})
		return
	var rapido := not enviadas.is_empty() or (en_grupo() and not soy_lider())
	_t = SONDEO_RAPIDO_S if rapido else SONDEO_S
	if en_grupo():
		_t = 1.0           # con equipo, cada segundo: que el chat no tarde
	if _ocupado:
		return
	var cuerpo := {"donde": "lobby", "yo": _mi_aspecto()}
	if _chat_n >= 0:
		cuerpo["chat_desde"] = _chat_n
	var cab := PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + Cuenta.token])
	if _http.request(Cuenta.url + "/grupo/estado", cab, HTTPClient.METHOD_POST, JSON.stringify(cuerpo)) == OK:
		_ocupado = true


## Lo que ven los demas de mi en SU lobby: la skin, el arma principal y su pintura (y el lider, el modo elegido)
func _mi_aspecto() -> Dictionary:
	var arma := String(Settings.loadout.get("primary", ""))
	if arma == "" or not Weapons.catalog().has(arma):
		arma = Weapons.default_for("primary")
	var d := {"skin": Settings.avatar_skin, "arma": arma, "pintura": SkinsArmas.equipada(Weapons.modelo_de(arma)),
		"mapa": Settings.map}
	d["modo"] = load("res://scripts/lobby.gd")._modo_de(Settings.map)
	return d


func _al_estado(_r: int, codigo: int, _c: PackedStringArray, cuerpo: PackedByteArray) -> void:
	_ocupado = false
	if codigo != 200:
		return
	var j = JSON.parse_string(cuerpo.get_string_from_utf8())
	if not (j is Dictionary):
		return
	_llega(j)


## Una respuesta del servidor (o de la prueba): el equipo, las invitaciones, los avisos y la sala del lider
func _llega(j: Dictionary) -> void:
	var ahora := Time.get_ticks_msec()
	# LAS QUE HE MANDADO: las que el servidor aun tiene en el aire (el resto ya se contestaron o caducaron)
	var siguen: Dictionary = {}
	for e in j.get("enviadas", []):
		if e is Dictionary and e.get("id", null) != null:
			siguen[id_txt(e["id"])] = ahora + int(float(e.get("quedan", 0.0)) * 1000.0)
	enviadas = siguen
	# LAS QUE ME LLEGAN: cada una se avisa una vez
	for i in j.get("invitaciones", []):
		if not (i is Dictionary):
			continue
		var id := String(i.get("id", ""))
		if id == "" or _vistas.has(id):
			continue
		_vistas[id] = ahora + int(float(i.get("quedan", 20.0)) * 1000.0)
		var f: Dictionary = (i as Dictionary).duplicate()
		f["tipo"] = "equipo"
		invitacion.emit(f)
	for k in _vistas.keys():
		if int(_vistas[k]) < ahora - 60000:
			_vistas.erase(k)
	for a in j.get("avisos", []):
		if a is Dictionary:
			var t := _texto_aviso(a)
			if t != "":
				aviso.emit(t)
	var g = j.get("grupo", null)
	_poner(g if g is Dictionary else {})
	for m in j.get("chat", []):
		if m is Dictionary:
			_chat_n = maxi(_chat_n, int(m.get("n", 0)))
			chat_llega.emit(String(m.get("nombre", "")), String(m.get("txt", "")))
	_chat_n = maxi(_chat_n, int(j.get("chat_n", 0)))


func _poner(g: Dictionary) -> void:
	var antes := JSON.stringify(estado)
	estado = g
	if JSON.stringify(estado) != antes:
		cambiado.emit()
	# LA SALA DEL LIDER: nueva (cada una lleva su numero), reciente, y no soy yo el lider. Cada una se sigue UNA vez: al
	# volver de la partida no se vuelve a entrar en la misma.
	var s = estado.get("sala", null)
	if s is Dictionary:
		var n := int(s.get("n", 0))
		if n > _sala_n and not soy_lider() and int(s.get("edad", 999)) <= SALA_RECIENTE_S:
			_sala_n = n
			sala_del_lider.emit(s)
		_sala_n = maxi(_sala_n, n)


func _texto_aviso(a: Dictionary) -> String:
	var n := String(a.get("nombre", ""))
	match String(a.get("tipo", "")):
		"aceptada":
			return "¡%s se ha unido a tu equipo!" % n
		"entro":
			return "%s se ha unido al equipo" % n
		"rechazada":
			return "%s ha rechazado tu invitación" % n
		"caducada":
			return "%s no contestó a tiempo: la invitación ha caducado" % n if n != "" else "La invitación ha caducado"
		"salio":
			return "%s ha salido del equipo" % n
		"expulsado":
			return "%s ya no está en el equipo" % n
		"te_expulsaron":
			return "%s te ha sacado del equipo" % n
		"lider":
			return "Ahora eres el líder del equipo"
	return ""


# ==================================================================================================================
# LA RED
# ==================================================================================================================
func _post(ruta: String, cuerpo: Dictionary, al_acabar: Callable) -> void:
	if not Cuenta.conectado():
		al_acabar.call(false, {}, "no has iniciado sesión")
		return
	var h := HTTPRequest.new()
	h.timeout = 10.0
	add_child(h)
	h.request_completed.connect(func(_r: int, codigo: int, _c: PackedStringArray, cu: PackedByteArray):
		h.queue_free()
		var j = JSON.parse_string(cu.get_string_from_utf8())
		var d: Dictionary = j if j is Dictionary else {}
		var err := String(d.get("error", "")) if codigo != 200 else ""
		if codigo == 0:
			err = "el servidor no responde"
		al_acabar.call(codigo == 200, d, err))
	var cab := PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + Cuenta.token])
	if h.request(Cuenta.url + ruta, cab, HTTPClient.METHOD_POST, JSON.stringify(cuerpo)) != OK:
		h.queue_free()
		al_acabar.call(false, {}, "no se pudo conectar")


## Manda un mensaje al chat del equipo (llega a todos, tambien a mi, con el siguiente sondeo, que se adelanta)
func mandar_chat(txt: String) -> void:
	txt = txt.strip_edges().left(120)
	if txt == "" or not en_grupo():
		return
	_post("/grupo/chat", {"txt": txt}, func(_ok, _d, _e): pedir_ya())


## --equipofoto: un equipo de ejemplo, sin red (el sondeo se para)
func poner_prueba(g: Dictionary) -> void:
	_prueba = true
	estado = g
	cambiado.emit()
