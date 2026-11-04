class_name PestanaTorneos
extends VBoxContainer
## TORNEOS (pestaña del inicio, 2026-10-18, pedido: "los torneos semanales se hacen aleatoriamente, pero yo desde el
## panel puedo modificar todo: el modo, el estilo de juego y los premios").
## El servidor (servidor/torneos.js) monta uno cada semana solo (sabado 20-22 h de Argentina, el modo segun el nivel de
## quienes juegan); aqui se ve y se cambia: modo, submodo, mapa, dia y hora, duracion, premios del 1.º, 2.º y 3.º; y se
## puede volver a sortear, anunciar en Discord otra vez o terminarlo ya (reparte los premios y publica el podio).
## Rutas: GET/POST /admin/torneo, /admin/torneo/sortear, /admin/torneo/anunciar, /admin/torneo/terminar.

const ZONA_H := -3
const MODOS := [["bomba", "Bomba", "bandera"], ["dm", "Duelo", "mira"]]
const SUBS := {"bomba": [["", "Normal", ""]], "dm": [["equipos", "Equipos", "grupo"], ["todos", "Todos contra todos", "usuario"]]}
const NOMBRE_MAPA := {"": "Cualquiera", "dust": "Dust", "cafeteria": "Cafetería", "hangar": "Hangar"}
const RAREZAS := ["Común", "Raro", "Épico", "Legendario", "Mítico", "Ultra"]

var app
var cargada := false
var _caja: VBoxContainer
var _estado: Label
var _datos := {}
var _pedido := 0
# lo que se esta editando
var _modo := "bomba"
var _sub := ""
var _mapa := ""
var _dia: LineEdit
var _mes: LineEdit
var _hora: LineEdit
var _min: LineEdit
var _dur: LineEdit
var _premios := {}            ## puesto -> {cubos, cofres, rareza, oro} (LineEdit / int)
var _anunciar: JuegoPiezas.Interruptor
var _guardar: Boton
var _subs_caja: VBoxContainer
var _mapas_caja: VBoxContainer


func _init(p_app) -> void:
	app = p_app
	add_theme_constant_override("separation", 14)


func _ready() -> void:
	var tj := Tema.tarjeta(18, Color(Tema.ACENTO, 0.07))
	var h := Tema.hbox(14)
	tj.add_child(h)
	var ic := Iconos.new("trofeo", Tema.ACENTO, 34)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	h.add_child(Tema.parrafo("Cada semana se arma un torneo solo (sábado de 20 a 22 h). Aquí lo puedes cambiar todo. " +
		"Al terminar, el 1.º, 2.º y 3.º reciben el premio en su buzón y Discord publica a los ganadores.", 14, Tema.TEXTO2))
	add_child(tj)
	_estado = Tema.linea("", 15, Tema.TEXTO, 700)
	add_child(_estado)
	_caja = Tema.vbox(14)
	add_child(_caja)


func cargar() -> void:
	cargada = true
	_pedido += 1
	var mio := _pedido
	for n in _caja.get_children():
		n.queue_free()
	_caja.add_child(Girador.new())
	_estado.text = "Cargando…"
	var r: Dictionary = await app.api.pedir("GET", "/admin/torneo")
	if mio != _pedido or not is_inside_tree():
		return
	for n in _caja.get_children():
		n.queue_free()
	if not r["ok"]:
		_estado.text = "No se pudo cargar"
		_caja.add_child(Tema.vacio("alerta", Tema.frase(String(r["error"])), "Si el servidor es viejo, hay que reiniciarlo una vez."))
		return
	_datos = r["datos"]
	var t = _datos.get("torneo")
	if not t is Dictionary:
		_estado.text = "Todavía no hay torneo (se crea en un minuto)"
		return
	_modo = String(t.get("modo", "bomba"))
	_sub = String(t.get("sub", ""))
	_mapa = String(t.get("mapa", ""))
	_armar(t)


func _local(ms: float) -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(int(ms / 1000.0) + ZONA_H * 3600)


func _armar(t: Dictionary) -> void:
	var estado := String(t.get("estado", ""))
	var ini := _local(float(t.get("inicio", 0)))
	_estado.text = "Torneo #%d · %s · %s" % [int(t.get("n", 0)), {"proximo": "PRÓXIMO", "activo": "EN MARCHA", "terminado": "TERMINADO"}.get(estado, estado),
		String(t.get("titulo", ""))]
	var nv: Dictionary = _datos.get("niveles", {})
	_caja.add_child(Tema.parrafo("Jugadores de las dos últimas semanas: %d · con nivel 5 (duelo): %d · con nivel 10: %d. %s" % [
		int(nv.get("n", 0)), int(nv.get("n5", 0)), int(nv.get("n10", 0)),
		"Sale sorteado automáticamente." if bool(t.get("auto", false)) else "Lo cambiaste a mano."], 13, Tema.TEXTO3))
	# modo
	_caja.add_child(Tema.seccion("Modo"))
	_caja.add_child(Formularios.segmentos(MODOS, _modo, func(v):
		_modo = String(v)
		_sub = String(SUBS[_modo][0][0])
		var mapas: Array = (_datos.get("mapas", {}) as Dictionary).get(_modo, [])
		if _mapa != "" and not _mapa in mapas:
			_mapa = ""
		_pintar_subs_y_mapas()))
	_subs_caja = Tema.vbox(10)
	_caja.add_child(_subs_caja)
	_mapas_caja = Tema.vbox(10)
	_caja.add_child(_mapas_caja)
	_pintar_subs_y_mapas()
	# cuando
	_caja.add_child(Tema.seccion("Cuándo (hora de Argentina)"))
	var f := Tema.hbox(8)
	_dia = Tema.campo_numero("día", int(ini["day"]))
	_mes = Tema.campo_numero("mes", int(ini["month"]))
	_hora = Tema.campo_numero("hora", int(ini["hour"]))
	_min = Tema.campo_numero("min", int(ini["minute"]))
	for c in [_dia, _mes, _hora, _min]:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		f.add_child(c)
	_caja.add_child(f)
	_caja.add_child(Tema.parrafo("Día / mes / hora / minutos", 12, Tema.TEXTO3))
	_dur = Tema.campo_numero("duración en minutos", int(round((float(t.get("fin", 0)) - float(t.get("inicio", 0))) / 60000.0)))
	_caja.add_child(_dur)
	_caja.add_child(Tema.parrafo("Duración en minutos (lo normal: 120)", 12, Tema.TEXTO3))
	# premios
	var premios: Dictionary = t.get("premios", {})
	for i in [1, 2, 3]:
		_caja.add_child(Tema.seccion(["", "🥇 Premio del 1.º", "🥈 Premio del 2.º", "🥉 Premio del 3.º"][i]))
		var p: Dictionary = premios.get(str(i), {})
		var fila := Tema.hbox(8)
		var cubos := Tema.campo_numero("cubos", int(p.get("cubos", 0)))
		var cofres := Tema.campo_numero("cofres", int(p.get("cofres", 0)))
		var oro := Tema.campo_numero("oro", int(p.get("oro", 0)))
		for c in [cubos, cofres, oro]:
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			fila.add_child(c)
		_caja.add_child(fila)
		_caja.add_child(Tema.parrafo("Cubos de fuerza / cofres / oro · rareza de los cofres:", 12, Tema.TEXTO3))
		var ent := {"cubos": cubos, "cofres": cofres, "oro": oro, "rareza": int(p.get("rareza", 0))}
		_premios[i] = ent
		var ops: Array = []
		for k in RAREZAS.size():
			ops.append([str(k), RAREZAS[k], "cofre"])
		_caja.add_child(Formularios.segmentos_filas(ops, str(ent["rareza"]), func(v): ent["rareza"] = int(v), 3, 42.0))
	# anunciar y guardar
	var h := Tema.hbox(12)
	var tv := Tema.vbox(3)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(Tema.parrafo("Anunciarlo otra vez en Discord", 15, Tema.TEXTO, 700))
	tv.add_child(Tema.parrafo("Con los cambios, para que todos se enteren.", 12, Tema.TEXTO3))
	h.add_child(tv)
	_anunciar = JuegoPiezas.Interruptor.new(true)
	h.add_child(_anunciar)
	_caja.add_child(h)
	_guardar = Boton.new("Guardar el torneo", "check", "primario", 56)
	_guardar.tocado.connect(_enviar)
	_caja.add_child(_guardar)
	var sortear := Boton.new("Sortear otro al azar", "dado", "secundario", 50)
	sortear.tocado.connect(func(): _accion("/admin/torneo/sortear", {"anunciar": _anunciar.si}, "Sorteado otro torneo"))
	_caja.add_child(sortear)
	var anunciar := Boton.new("Anunciar en Discord ahora", "megafono", "secundario", 50)
	anunciar.tocado.connect(func(): _accion("/admin/torneo/anunciar", {}, "Anunciado en Discord"))
	_caja.add_child(anunciar)
	if estado == "activo":
		var terminar := Boton.new("Terminar ya y dar los premios", "trofeo", "secundario", 50)
		terminar.tocado.connect(func():
			var d: Dialogo = app.dialogo("Terminar el torneo", "trofeo", Tema.TEXTO2)
			d.cuerpo.add_child(Tema.parrafo("Se cierra ahora: el 1.º, 2.º y 3.º reciben su premio y Discord publica el podio.", 15))
			d.boton("Cancelar").tocado.connect(d.cerrar)
			d.boton("Terminar", "primario").tocado.connect(func():
				d.cerrar()
				_accion("/admin/torneo/terminar", {}, "Torneo terminado: premios repartidos")))
		_caja.add_child(terminar)
	# la tabla
	var top: Array = t.get("top", [])
	_caja.add_child(Tema.seccion("Tabla (%d jugadores)" % int(t.get("todos", top.size()))))
	if top.is_empty():
		_caja.add_child(Tema.parrafo("Todavía nadie sumó puntos.", 14, Tema.TEXTO3))
	for i in top.size():
		var fj: Dictionary = top[i]
		_caja.add_child(Tema.parrafo("%s %s · %d puntos · %d partidas" % [["🥇", "🥈", "🥉"][i] if i < 3 else "%d." % (i + 1),
			String(fj.get("nombre", "")), int(fj.get("puntos", 0)), int(fj.get("partidas", 0))], 15, Tema.TEXTO, 700 if i < 3 else 400))
	var ant = _datos.get("anterior")
	if ant is Dictionary:
		_caja.add_child(Tema.seccion("Ganadores del anterior (#%d)" % int(ant.get("n", 0))))
		for fj in ant.get("top", []):
			_caja.add_child(Tema.parrafo("%s · %d puntos" % [String(fj.get("nombre", "")), int(fj.get("puntos", 0))], 14, Tema.TEXTO2))


func _pintar_subs_y_mapas() -> void:
	for n in _subs_caja.get_children():
		n.queue_free()
	for n in _mapas_caja.get_children():
		n.queue_free()
	var subs: Array = SUBS.get(_modo, [])
	if subs.size() > 1:
		_subs_caja.add_child(Tema.seccion("Estilo de juego"))
		_subs_caja.add_child(Formularios.segmentos(subs, _sub, func(v): _sub = String(v)))
	_mapas_caja.add_child(Tema.seccion("Mapa"))
	var ops: Array = [["", "Cualquiera", "mapa"]]
	for m in (_datos.get("mapas", {}) as Dictionary).get(_modo, []):
		ops.append([String(m), String(NOMBRE_MAPA.get(String(m), String(m))), "mapa"])
	_mapas_caja.add_child(Formularios.segmentos(ops, _mapa, func(v): _mapa = String(v)))


func _num(c: LineEdit) -> int:
	return int(c.text) if c.text.strip_edges().is_valid_int() else 0


func _enviar() -> void:
	var d := {"year": int(Time.get_datetime_dict_from_system()["year"]), "month": _num(_mes), "day": _num(_dia),
		"hour": _num(_hora), "minute": _num(_min), "second": 0}
	if d["month"] < 1 or d["month"] > 12 or d["day"] < 1 or d["day"] > 31 or d["hour"] > 23 or d["minute"] > 59:
		app.avisar("Revisa el día y la hora", false)
		return
	var ms := float(Time.get_unix_time_from_datetime_dict(d) - ZONA_H * 3600) * 1000.0
	# si la fecha cae muy atras (cambio de año), al año siguiente
	if ms < Time.get_unix_time_from_system() * 1000.0 - 180.0 * 86400000.0:
		d["year"] += 1
		ms = float(Time.get_unix_time_from_datetime_dict(d) - ZONA_H * 3600) * 1000.0
	var premios := {}
	for i in _premios.keys():
		var e: Dictionary = _premios[i]
		premios[str(i)] = {"cubos": _num(e["cubos"]), "cofres": _num(e["cofres"]), "oro": _num(e["oro"]), "rareza": int(e["rareza"])}
	_accion("/admin/torneo", {"modo": _modo, "sub": _sub, "mapa": _mapa, "inicio": ms, "duracion_min": maxi(15, _num(_dur)),
		"premios": premios, "anunciar": _anunciar.si}, "Torneo guardado")


func _accion(ruta: String, cuerpo: Dictionary, ok_texto: String) -> void:
	if is_instance_valid(_guardar):
		_guardar.cargando = true
	var r: Dictionary = await app.api.pedir("POST", ruta, cuerpo)
	if not is_inside_tree():
		return
	if is_instance_valid(_guardar):
		_guardar.cargando = false
	if not r["ok"]:
		app.avisar(Tema.frase(String(r["error"])), false)
		return
	app.avisar(ok_texto)
	cargar()
