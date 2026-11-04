class_name PestanaVivo
extends VBoxContainer
## EN VIVO (pestaña del inicio, 2026-09-29, pedido: "que el panel me diga cuando alguien juega, y cuando hay una partida
## un boton ESPECTAR que me abra el juego y entre solo en la partida como espectador").
##   arriba                con que CUENTA DEL JUEGO se especta (la del administrador): POST /admin/espectador
##   PARTIDAS EN CURSO     cada sala anunciada, con la foto de su mapa: nombre, anfitrion, jugadores, estado, si se
##                         puede entrar desde fuera, y ESPECTAR
##   JUGADORES CONECTADOS  quien ha dado señales (lobby o partida); tocar uno abre su ficha
## Se pide GET /admin/vivo cada 10 s con la pestaña a la vista y cada 15 s si no: todo el rato que la app esta delante
## (en segundo plano Android para el bucle y no se pide nada; al volver se pide en el acto). Cada vuelta se compara con
## la anterior: una sala nueva o alguien que empieza a jugar dan un AVISO abajo (y vibra), en cualquier pantalla del
## panel. La primera vuelta no avisa, y una sala que se cae y vuelve con otro id no cuenta como nueva.
## ESPECTAR: POST /admin/espectar {sala} deja la orden en el servidor para la cuenta del juego; el juego la recoge en su
## latido o al volver al primer plano. Aqui solo se abre Breach (`abrir_juego`: ver alli lo de Android 11).
##
## Las fotos de los mapas (`res://mapas/`) son recortes de las del juego (godot/assets/mapas y las portadas de los
## modos). Sin foto de su mapa sale la de su modo, y sin esa, un fondo dibujado.

signal cambiado(salas: int)        ## tras cada vuelta: cuantas salas hay (el punto rojo de la pestaña)

const CADA_VISTA := 10.0           ## segundos entre vueltas con la pestaña a la vista
const CADA_FONDO := 15.0           ## ...y con otra pantalla delante
const PAQUETE := "com.breach.voxelfps"
## La actividad del juego que se puede abrir desde fuera. En las plantillas de Godot 4.7 `GodotApp` NO esta exportada;
## la del icono es el alias `com.godot.game.GodotAppLauncher` (android_source.zip, src/main/AndroidManifest.xml).
const LANZADOR := "com.godot.game.GodotAppLauncher"
const FLAG_ACTIVITY_NEW_TASK := 0x10000000
const FLAG_ACTIVITY_RESET_TASK_IF_NEEDED := 0x00200000     ## como el icono: si ya esta abierto, lo trae delante
const CARPETA_MAPAS := "res://mapas/"

## Los nombres de los mapas como los pone el juego (Settings.map_title), en minusculas bonitas
const MAPAS := {
	"pve_cuarentena": "Cuarentena", "campana_huida": "La Huida", "campana_puerto": "El Puerto",
	"campana_amanecer": "El Amanecer", "campana_presa": "La Presa", "campana_base": "La Base Aérea",
	"campana_cumbre": "La Cumbre", "campana_parque": "El Parque", "campana_volcan": "El Volcán",
	"monaco": "Mónaco", "isla": "Isla", "city": "Ciudad",
}
## EL MODO LO DECIDE EL MAPA (CLAUDE.md): sitios de bomba, duelo, atraco, PvE... El `modo` que anuncia la sala suele
## venir vacio, asi que primero el mapa.
const MODO_DE_MAPA := {"dust": "bomba", "hangar": "duelo", "nuke": "duelo", "city": "atraco", "monaco": "atraco",
	"isla": "royale", "pve_cuarentena": "zombis"}
const MODOS := {"bomba": "Bomba", "duelo": "Duelo", "atraco": "Atraco", "royale": "Battle royale", "zombis": "Zombis",
	"campana": "Campaña", "libre": "Libre"}

var app
var datos := {}                    ## lo ultimo que dio /admin/vivo (ordenado)
var cargada := false               ## ya llego una vuelta buena
var _abrir_ficha: Callable
var _mostrar: Callable             ## lleva a esta pestaña (tocar un aviso)
var _pidiendo := false
var _t_pedido := -1000.0           ## cuando salio la ultima peticion (segundos de reloj)
var _t_datos := 0.0                ## cuando llegaron los datos de ahora
var _base := false                 ## hay una vuelta con la que comparar
var _firma := ""                   ## lo que se ve (sin los segundos): si no cambia, no se repinta
var _error := ""
var _vistas := {}                  ## sala ("id:..." y "n:anfitrion|nombre") -> cuando se vio por ultima vez (unix)
var _donde := {}                   ## usuario -> "lobby" / "partida" en la vuelta anterior
var _empezo := {}                  ## usuario -> cuando se aviso de que empezo a jugar (unix)
var _nombres := {}                 ## usuario -> nombre (para enseñar la cuenta del juego con su nombre)
var _relojes: Array = []           ## [Label, segundos abierta al llegar los datos]
var _cuenta: VBoxContainer
var _punto: Control
var _estado: Label
var _nota: Label
var _caja: VBoxContainer
static var _fotos := {}
static var _sombreado: Shader = null


func _init(p_app, p_abrir_ficha: Callable, p_mostrar: Callable) -> void:
	app = p_app
	_abrir_ficha = p_abrir_ficha
	_mostrar = p_mostrar
	add_theme_constant_override("separation", 14)


func _ready() -> void:
	_cuenta = Tema.vbox(0)
	add_child(_cuenta)
	# la linea de estado: el punto (rojo si hay partidas), "2 partidas · 5 conectados" y cada cuanto se mira
	var fila := Tema.hbox(8)
	_punto = Control.new()
	_punto.custom_minimum_size = Vector2(12, 12)
	_punto.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_punto.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_punto.set_meta("color", Tema.TEXTO3)
	_punto.draw.connect(func():
		var col: Color = _punto.get_meta("color")
		var c := _punto.size * 0.5
		if col == Tema.VIVO:
			_punto.draw_circle(c, 6.0, Color(col, 0.25))
		_punto.draw_circle(c, 3.5, col))
	fila.add_child(_punto)
	_estado = Tema.linea("Cargando…", 14, Tema.TEXTO2, 600)
	_estado.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fila.add_child(_estado)
	_nota = Tema.etiqueta("", 12, Tema.TEXTO3, 600)
	_nota.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fila.add_child(_nota)
	add_child(fila)
	_caja = Tema.vbox(12)
	add_child(_caja)
	_caja.add_child(Girador.new())
	_pintar_cuenta()
	var reloj := Timer.new()
	reloj.wait_time = 1.0
	reloj.autostart = true
	reloj.timeout.connect(_tic)
	add_child(reloj)
	cargar()


func _ahora() -> float:
	return Time.get_ticks_msec() / 1000.0


func _tic() -> void:
	var cada := CADA_VISTA if is_visible_in_tree() else CADA_FONDO
	if not _pidiendo and _ahora() - _t_pedido >= cada:
		cargar()
	if is_visible_in_tree():
		_tic_relojes()


func _notification(what: int) -> void:
	# de vuelta al primer plano (o a la ventana, en PC): se mira ya, no dentro de 15 s
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if _ahora() - _t_pedido > 3.0:
			_t_pedido = -1000.0


## La pestaña se pone a la vista: si lo de ahora tiene mas de 3 s, otra vuelta
func al_mostrar() -> void:
	if _ahora() - _t_pedido > 3.0:
		cargar()


# ------------------------------------------------------------------ pedir y comparar
func cargar() -> void:
	if _pidiendo:
		return
	_pidiendo = true
	_t_pedido = _ahora()
	var r: Dictionary = await app.api.pedir("GET", "/admin/vivo")
	_pidiendo = false
	if not is_inside_tree():
		return
	if not r["ok"]:
		_error = String(r["error"])
		if not cargada:
			for n in _caja.get_children():
				n.queue_free()
			_caja.add_child(Tema.vacio("alerta", Tema.frase(_error), "Se vuelve a intentar solo en unos segundos."))
		_pintar_estado()
		return
	_error = ""
	var nuevos: Dictionary = r["datos"]
	_ordenar(nuevos)
	if _base:
		_avisar(_cambios(nuevos))
	_recordar(nuevos)
	_base = true
	datos = nuevos
	_t_datos = _ahora()
	cargada = true
	for j in datos.get("jugadores", []):
		_nombres[String(j.get("usuario", ""))] = String(j.get("nombre", ""))
	var f := _firma_de(datos)
	if f != _firma:
		_firma = f
		_pintar()
		_pintar_cuenta()
	else:
		_tic_relojes()
	_pintar_estado()
	cambiado.emit((datos.get("salas", []) as Array).size())


static func _ordenar(d: Dictionary) -> void:
	var salas: Array = d.get("salas", [])
	salas.sort_custom(func(a, b):
		if bool(a.get("jugando", false)) != bool(b.get("jugando", false)):
			return bool(a.get("jugando", false))
		if int(a.get("jugadores", 0)) != int(b.get("jugadores", 0)):
			return int(a.get("jugadores", 0)) > int(b.get("jugadores", 0))
		return String(a.get("nombre", "")).naturalnocasecmp_to(String(b.get("nombre", ""))) < 0)
	var jug: Array = d.get("jugadores", [])
	jug.sort_custom(func(a, b):
		var pa := String(a.get("donde", "")) == "partida"
		var pb := String(b.get("donde", "")) == "partida"
		if pa != pb:
			return pa
		return String(a.get("nombre", "")).naturalnocasecmp_to(String(b.get("nombre", ""))) < 0)


## Lo que se ve, sin los segundos (que cambian en cada vuelta)
static func _firma_de(d: Dictionary) -> String:
	var s: Array = []
	for x in d.get("salas", []):
		s.append([x.get("id"), x.get("nombre"), x.get("anfitrion"), x.get("mapa"), x.get("modo"), x.get("jugadores"),
			x.get("max"), x.get("jugando"), x.get("abierta")])
	var j: Array = []
	for x in d.get("jugadores", []):
		j.append([x.get("usuario"), x.get("nombre"), x.get("donde")])
	return JSON.stringify([s, j, d.get("espectador", "")])


func _claves_sala(s: Dictionary) -> Array:
	return ["id:" + String(s.get("id", "")), "n:%s|%s" % [String(s.get("anfitrion", "")), String(s.get("nombre", ""))]]


## Lo que ha cambiado desde la vuelta anterior, en frases para el aviso
func _cambios(nuevos: Dictionary) -> Array:
	var msgs: Array = []
	var ahora := Time.get_unix_time_from_system()
	for s in nuevos.get("salas", []):
		var nueva := true
		for k in _claves_sala(s):
			if _vistas.has(k) and ahora - float(_vistas[k]) < 300.0:
				nueva = false
		if nueva:
			var mapa := nombre_mapa(String(s.get("mapa", "")))
			msgs.append("Nueva partida: %s" % String(s.get("nombre", "Sala")) + ("" if mapa == "" else " · " + mapa))
	var yo := String(nuevos.get("espectador", ""))
	for j in nuevos.get("jugadores", []):
		var u := String(j.get("usuario", ""))
		if u == yo or String(j.get("donde", "")) != "partida" or String(_donde.get(u, "")) == "partida":
			continue
		if ahora - float(_empezo.get(u, 0.0)) < 120.0:
			continue          # entra y sale de partidas seguidas: un aviso cada 2 minutos como mucho
		msgs.append("%s empezó a jugar" % String(j.get("nombre", u)))
	return msgs


func _recordar(nuevos: Dictionary) -> void:
	var ahora := Time.get_unix_time_from_system()
	for s in nuevos.get("salas", []):
		for k in _claves_sala(s):
			_vistas[k] = ahora
	for k in _vistas.keys():
		if ahora - float(_vistas[k]) > 600.0:
			_vistas.erase(k)
	var d := {}
	for j in nuevos.get("jugadores", []):
		var u := String(j.get("usuario", ""))
		d[u] = String(j.get("donde", ""))
		if d[u] == "partida" and String(_donde.get(u, "")) != "partida":
			_empezo[u] = ahora
	_donde = d


func _avisar(msgs: Array) -> void:
	if msgs.is_empty():
		return
	var t := "\n".join(PackedStringArray(msgs.slice(0, 3)))
	if msgs.size() > 3:
		t += "\ny %d más" % (msgs.size() - 3)
	print("[vivo] ", t.replace("\n", " / "))
	app.avisar(t, true, "vivo", Tema.VIVO, _mostrar)
	if OS.get_name() == "Android":
		Input.vibrate_handheld(200)


# ------------------------------------------------------------------ pintar
func _pintar_estado() -> void:
	var ns := (datos.get("salas", []) as Array).size()
	var nj := (datos.get("jugadores", []) as Array).size()
	if cargada:
		if ns == 0 and nj == 0:
			_estado.text = "Sin partidas · nadie conectado"
		else:
			_estado.text = "%d partida%s · %d conectado%s" % [ns, "" if ns == 1 else "s", nj, "" if nj == 1 else "s"]
	_punto.set_meta("color", Tema.VIVO if ns > 0 else (Tema.OK if nj > 0 else Tema.TEXTO3))
	_punto.queue_redraw()
	if _error != "":
		_nota.text = "sin conexión · reintentando"
		_nota.add_theme_color_override("font_color", Tema.AVISO)
	else:
		_nota.text = "se actualiza sola"
		_nota.add_theme_color_override("font_color", Tema.TEXTO3)


func _pintar() -> void:
	for n in _caja.get_children():
		n.queue_free()
	_relojes.clear()
	var salas: Array = datos.get("salas", [])
	var jugadores: Array = datos.get("jugadores", [])
	if salas.is_empty() and jugadores.is_empty():
		_caja.add_child(Tema.vacio("vivo", "Nadie está jugando ahora",
			"Esta pantalla se actualiza sola. Con el panel abierto, te avisa en cuanto empiece una partida."))
		return
	_caja.add_child(_cabecera("Partidas en curso", salas.size()))
	if salas.is_empty():
		_caja.add_child(_linea_vacia("mando", "Ninguna partida abierta ahora."))
	for s in salas:
		_caja.add_child(_tarjeta_sala(s))
	_caja.add_child(Tema.espacio(6))
	_caja.add_child(_cabecera("Jugadores conectados", jugadores.size()))
	if jugadores.is_empty():
		_caja.add_child(_linea_vacia("grupo", "Nadie conectado ahora."))
	var lista := Tema.vbox(8)
	for j in jugadores:
		lista.add_child(_fila_jugador(j))
	_caja.add_child(lista)
	_tic_relojes()


func _cabecera(texto: String, n: int) -> Control:
	var h := Tema.seccion(texto)
	h.add_child(Tema.etiqueta(str(n), 12, Tema.TEXTO3, 700))
	return h


func _linea_vacia(icono: String, texto: String) -> Control:
	var tj := Tema.tarjeta(14)
	var h := Tema.hbox(10)
	var ic := Iconos.new(icono, Tema.TEXTO3, 18)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	h.add_child(Tema.parrafo(texto, 14, Tema.TEXTO3))
	tj.add_child(h)
	return tj


func _tic_relojes() -> void:
	var pasado := _ahora() - _t_datos
	for r in _relojes:
		var l: Label = r[0]
		if is_instance_valid(l):
			var s: float = r[1] + pasado
			l.text = "recién abierta" if s < 60.0 else "abierta hace " + Tema.duracion(s)


## La cuenta del juego con la que se especta (o la llamada a configurarla)
func _pintar_cuenta() -> void:
	for n in _cuenta.get_children():
		n.queue_free()
	var u := String(datos.get("espectador", ""))
	# EN EL MOVIL NO HACE FALTA ELEGIR CUENTA (2026-10-02): se especta con el Breach de este telefono (ver `espectar`)
	if por_aparato():
		var hm := Tema.hbox(12)
		hm.add_child(_circulo("ojo", Tema.ACENTO))
		var tvm := Tema.vbox(2)
		tvm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tvm.add_child(Tema.parrafo("Se especta con el Breach de este móvil", 15, Tema.TEXTO, 700))
		tvm.add_child(Tema.parrafo("Con la cuenta que tengas abierta en el juego. Nunca saca a nadie de su partida.", 12, Tema.TEXTO2))
		hm.add_child(tvm)
		_cuenta.add_child(hm)
		return
	if cargada and u == "":
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", Tema.caja(Color(Tema.ACENTO, 0.07), 16, Color(Tema.ACENTO, 0.35), 1, Vector4(16, 16, 16, 16)))
		var v := Tema.vbox(14)
		p.add_child(v)
		var h := Tema.hbox(14)
		h.add_child(_circulo("ojo", Tema.ACENTO))
		var tv := Tema.vbox(4)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(Tema.parrafo("Configura tu cuenta del juego para poder espectar", 16, Tema.TEXTO, 700))
		tv.add_child(Tema.parrafo("Es la cuenta con la que entras a Breach en este móvil: el juego entrará con ella en la partida, como espectador.", 13, Tema.TEXTO2))
		h.add_child(tv)
		v.add_child(h)
		var b := Boton.new("Elegir mi cuenta del juego", "usuario", "primario", 50)
		b.tam = 15
		b.tocado.connect(func(): elegir_cuenta())
		v.add_child(b)
		_cuenta.add_child(p)
		return
	if u == "":
		return
	var tj := Tema.tarjeta(14)
	var h2 := Tema.hbox(12)
	tj.add_child(h2)
	h2.add_child(_circulo("ojo", Tema.ACENTO))
	var tv2 := Tema.vbox(2)
	tv2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv2.add_child(Tema.linea("ESPECTAS CON", 11, Tema.TEXTO3, 700))
	var nombre := String(_nombres.get(u, ""))
	var quien := Tema.hbox(6)
	if nombre != "" and nombre != u:
		var ln := Tema.etiqueta(nombre, 16, Tema.TEXTO, 700)
		quien.add_child(ln)
		var lu := Tema.linea(_texto_usuario(u), 13, Tema.TEXTO3)
		lu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		quien.add_child(lu)
	else:
		quien.add_child(Tema.linea(_texto_usuario(u), 16, Tema.TEXTO, 700))
	tv2.add_child(quien)
	var donde := String(_donde.get(u, ""))
	if donde == "partida":
		tv2.add_child(Tema.linea("Conectada · jugando", 12, Tema.AVISO, 600))
	elif donde == "lobby":
		tv2.add_child(Tema.linea("Conectada · en el lobby", 12, Tema.OK, 600))
	else:
		tv2.add_child(Tema.linea("Sin conectar: al espectar se abre Breach", 12, Tema.TEXTO3))
	h2.add_child(tv2)
	var cam := Boton.new("Cambiar", "lapiz", "fantasma", 40)
	cam.tam = 13
	cam.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cam.tocado.connect(func(): elegir_cuenta())
	h2.add_child(cam)
	_cuenta.add_child(tj)


func _circulo(icono: String, color: Color, lado := 20) -> Control:
	var circ := PanelContainer.new()
	circ.add_theme_stylebox_override("panel", Tema.caja(Color(color, 0.14), 12, Color.TRANSPARENT, 0, Vector4(10, 10, 10, 10)))
	circ.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	circ.mouse_filter = Control.MOUSE_FILTER_IGNORE
	circ.add_child(Iconos.new(icono, color, lado))
	return circ


static func _texto_usuario(u: String) -> String:
	return "cuenta de Google" if u.begins_with("g_") else "@" + u


## Una partida: la foto del mapa (con el estado y los jugadores encima), el nombre, el anfitrion, cuanto lleva abierta,
## el aviso si no se puede entrar desde fuera, y ESPECTAR
func _tarjeta_sala(s: Dictionary) -> Control:
	var jugando := bool(s.get("jugando", false))
	var col := Tema.AVISO if jugando else Tema.OK
	var mapa := String(s.get("mapa", ""))
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Tema.caja(Tema.SUP, 16, Tema.BORDE, 1, Vector4(1, 1, 1, 1)))
	var v := Tema.vbox(0)
	p.add_child(v)
	var ban := _Banner.new()
	ban.tex = foto_mapa(mapa, clave_modo(String(s.get("modo", "")), mapa))
	ban.titulo = nombre_mapa(mapa).to_upper()
	ban.modo = nombre_modo(String(s.get("modo", "")), mapa)
	ban.estado = "EN PARTIDA" if jugando else "ESPERANDO"
	ban.color = col
	ban.gente = "%d/%d" % [int(s.get("jugadores", 0)), maxi(int(s.get("max", 0)), int(s.get("jugadores", 0)))]
	ban.custom_minimum_size = Vector2(0, 124)
	v.add_child(ban)
	var m := Tema.margen(16, 14, 16, 16)
	v.add_child(m)
	var c := Tema.vbox(12)
	m.add_child(c)
	var tv := Tema.vbox(4)
	tv.add_child(Tema.linea(String(s.get("nombre", "Sala")), 18, Tema.TEXTO, 800))
	var sub := Tema.hbox(6)
	var anf := String(s.get("anfitrion", ""))
	if anf != "":
		sub.add_child(_mini_icono("usuario"))
		sub.add_child(Tema.etiqueta(anf, 13, Tema.TEXTO2, 600))
		sub.add_child(Tema.etiqueta("·", 13, Tema.TEXTO3))
	sub.add_child(_mini_icono("reloj"))
	var lt := Tema.linea("", 13, Tema.TEXTO3)
	sub.add_child(lt)
	_relojes.append([lt, float(s.get("desde", 0))])
	tv.add_child(sub)
	c.add_child(tv)
	if not bool(s.get("abierta", true)):
		var av := PanelContainer.new()
		av.add_theme_stylebox_override("panel", Tema.caja(Color(Tema.AVISO, 0.08), 10, Color(Tema.AVISO, 0.3), 1, Vector4(10, 8, 12, 8)))
		var ah := Tema.hbox(9)
		var ic := Iconos.new("alerta", Tema.AVISO, 15)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ah.add_child(ic)
		ah.add_child(Tema.parrafo("Puede que no se pueda entrar desde fuera: el router del anfitrión no abrió la sala.", 13, Tema.TEXTO2))
		av.add_child(ah)
		c.add_child(av)
	var b := Boton.new("ESPECTAR", "ojo", "primario", 50)
	b.tocado.connect(func(): espectar(s, b))
	c.add_child(b)
	return p


func _mini_icono(icono: String) -> Control:
	var ic := Iconos.new(icono, Tema.TEXTO3, 13)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return ic


## Un jugador conectado: tocarlo abre su ficha
func _fila_jugador(j: Dictionary) -> Control:
	var u := String(j.get("usuario", ""))
	var nombre := String(j.get("nombre", u))
	var jugando := String(j.get("donde", "")) == "partida"
	var fila := Boton.new("", "", "fila", 66)
	var h := Tema.hbox(12)
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 14
	h.offset_right = -12
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fila.add_child(h)
	var av = Tema.avatar(nombre, 40)
	av.punto = Tema.AVISO if jugando else Tema.OK
	h.add_child(av)
	var tv := Tema.vbox(1)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(Tema.linea(nombre, 15, Tema.TEXTO, 700))
	var sub := _texto_usuario(u)
	if u == String(datos.get("espectador", "")):
		sub += "  ·  tu cuenta del juego"
	tv.add_child(Tema.linea(sub, 12, Tema.TEXTO3))
	h.add_child(tv)
	var ch := Tema.chip("JUGANDO", Tema.AVISO, "mando") if jugando else Tema.chip("EN EL LOBBY", Tema.OK, "senal")
	ch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ch)
	var fl := Iconos.new("flecha", Tema.TEXTO3, 13)
	fl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(fl)
	fila.tocado.connect(func(): _abrir_ficha.call(u))
	return fila


# ------------------------------------------------------------------ la cuenta del juego
## Elegir la cuenta del juego con la que se especta: los conectados ahora (lo normal: tienes el juego abierto) o
## buscando por usuario, nombre o ID (las de Google tienen un usuario "g_..." que nadie se sabe). `despues`: lo que se
## hace al elegirla (espectar la sala que se toco).
func elegir_cuenta(despues := Callable()) -> void:
	var actual := String(datos.get("espectador", ""))
	var d: Dialogo = app.dialogo("Tu cuenta del juego", "ojo", Tema.ACENTO, "Con la que espectas las partidas")
	d.cuerpo.add_child(Tema.parrafo("Breach entrará en la partida con esta cuenta, como espectador. Elige la que tienes abierta en el juego de este móvil.", 14, Tema.TEXTO2))
	var bs: Array = Tema.buscador("Usuario, nombre o ID")
	var buscar: LineEdit = bs[1]
	d.cuerpo.add_child(bs[0])
	var cab := Tema.seccion("Conectados ahora")
	var cab_l: Label = cab.get_child(0)
	d.cuerpo.add_child(cab)
	var lista := Tema.vbox(8)
	d.cuerpo.add_child(lista)
	var estado := {"pedido": 0}
	var elegir := func(u: String, nombre: String, fila: Boton):
		if u == actual:
			d.cerrar()
			if despues.is_valid():
				despues.call()
			return
		_guardar_cuenta(u, nombre, fila, d, despues)
	var pintar := func(cuentas: Array, vacio: String):
		for n in lista.get_children():
			n.queue_free()
		for c in cuentas:
			lista.add_child(_fila_elegir(c, actual, elegir))
		if cuentas.is_empty():
			lista.add_child(Tema.parrafo(vacio, 14, Tema.TEXTO3))
	var conectados := func():
		cab_l.text = "CONECTADOS AHORA"
		pintar.call(datos.get("jugadores", []), "Nadie conectado ahora. Abre Breach con tu cuenta, o búscala por usuario, nombre o ID.")
	buscar.text_changed.connect(func(t: String):
		estado["pedido"] += 1
		var mio: int = estado["pedido"]
		var q := t.strip_edges()
		if q == "":
			conectados.call()
			return
		cab_l.text = "RESULTADOS"
		await get_tree().create_timer(0.35).timeout
		if mio != estado["pedido"] or not is_instance_valid(lista):
			return
		for n in lista.get_children():
			n.queue_free()
		lista.add_child(Girador.new())
		var r: Dictionary = await app.api.pedir("GET", "/admin/cuentas?q=" + q.uri_encode())
		if mio != estado["pedido"] or not is_instance_valid(lista):
			return
		if not r["ok"]:
			pintar.call([], Tema.frase(String(r["error"])))
			return
		pintar.call((r["datos"].get("cuentas", []) as Array).slice(0, 8), "Ninguna cuenta coincide."))
	conectados.call()
	d.boton("Cancelar").tocado.connect(d.cerrar)
	if actual != "":
		var q := d.boton("Quitar", "peligro", "papelera")
		q.tocado.connect(func(): _guardar_cuenta("", "", q, d, Callable()))


## Una cuenta para elegir (de /admin/vivo o de /admin/cuentas: las dos traen usuario y nombre)
func _fila_elegir(c: Dictionary, actual: String, al_elegir: Callable) -> Boton:
	var u := String(c.get("usuario", ""))
	var nombre := String(c.get("nombre", u))
	var es := u == actual
	var fila := Boton.new("", "", "sel" if es else "fila", 62)
	var h := Tema.hbox(12)
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -14
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fila.add_child(h)
	var av = Tema.avatar(nombre, 38)
	var donde := String(c.get("donde", c.get("estado", "")))
	av.punto = Tema.AVISO if donde == "partida" else (Tema.OK if donde == "lobby" else Color.TRANSPARENT)
	h.add_child(av)
	var tv := Tema.vbox(1)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(Tema.linea(nombre, 15, Tema.TEXTO, 700))
	var sub := _texto_usuario(u)
	if c.get("id_pub", null) != null:
		sub += "  ·  ID %d" % int(c["id_pub"])
	if donde == "partida" or donde == "lobby":
		sub += "  ·  " + ("jugando" if donde == "partida" else "en el lobby")
	tv.add_child(Tema.linea(sub, 12, Tema.TEXTO3))
	h.add_child(tv)
	if es:
		var ch := Tema.chip("ACTUAL", Tema.ACENTO, "check")
		ch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ch)
	fila.set_meta("usuario", u)          # las fotos de prueba la eligen por aqui
	fila.tocado.connect(func(): al_elegir.call(u, nombre, fila))
	return fila


func _guardar_cuenta(u: String, nombre: String, boton: Boton, d: Dialogo, despues: Callable) -> void:
	boton.cargando = true
	var r: Dictionary = await app.api.pedir("POST", "/admin/espectador", {"usuario": u})
	if is_instance_valid(boton):
		boton.cargando = false
	if not r["ok"]:
		app.avisar(Tema.frase(String(r["error"])), false)
		return
	var nuevo := String(r["datos"].get("espectador", u))
	datos["espectador"] = nuevo
	if nuevo != "" and nombre != "":
		_nombres[nuevo] = nombre
	if is_instance_valid(d):
		d.cerrar()
	if not is_inside_tree():
		return
	_firma = _firma_de(datos)
	if cargada:
		_pintar()
	_pintar_cuenta()
	if nuevo == "":
		app.avisar("Ya no hay cuenta del juego para espectar")
		return
	app.avisar("Espectarás con " + (nombre if nombre != "" else _texto_usuario(nuevo)))
	if despues.is_valid():
		despues.call()


# ------------------------------------------------------------------ espectar
## ESPECTAR una sala: el servidor apunta la orden para la cuenta del juego y aqui se abre Breach
func espectar(s: Dictionary, boton: Boton = null) -> void:
	if not por_aparato() and String(datos.get("espectador", "")) == "":
		elegir_cuenta(func(): espectar(s))
		return
	if boton != null:
		boton.cargando = true
	var cuerpo := {"sala": String(s.get("id", ""))}
	if por_aparato():
		cuerpo["aparato"] = huella_aparato()
	var r: Dictionary = await app.api.pedir("POST", "/admin/espectar", cuerpo)
	if boton != null and is_instance_valid(boton):
		boton.cargando = false
	if not is_inside_tree():
		return
	if not r["ok"]:
		var e := String(r["error"])
		if "configura" in e:
			datos["espectador"] = ""
			_pintar_cuenta()
			elegir_cuenta(func(): espectar(s))
			return
		app.avisar(Tema.frase(e), false)
		if int(r["codigo"]) == 404:
			cargar()
		return
	var sala := String(s.get("nombre", "la partida"))
	if OS.get_name() != "Android":
		app.avisar("Abre Breach con tu cuenta del juego: entrará solo en la partida", true, "ojo", Tema.ACENTO)
	elif abrir_juego(String(r["datos"].get("paquete", PAQUETE))):
		app.avisar("Abriendo Breach… entrará en %s como espectador" % sala, true, "ojo", Tema.ACENTO)
	else:
		app.avisar("Abre Breach: entrará solo en la partida", true, "alerta", Tema.AVISO)


## EN EL MOVIL la orden va al Breach de ESTE telefono (2026-10-02, pedido: "que mire que cuenta estoy usando"; y el fallo:
## con un amigo en la misma wifi la orden fue a la cuenta configurada, que era la suya, y su juego salio de la partida).
## La huella es la del juego (cuenta.gd `huella_aparato`): el ANDROID_ID es el mismo para las dos apps porque se firman con
## la misma llave. En el PC sigue haciendo falta elegir la cuenta.
static func por_aparato() -> bool:
	return OS.get_name() == "Android" and OS.get_unique_id() != ""


static func huella_aparato() -> String:
	return ("breach-aparato:" + OS.get_unique_id()).sha256_text().left(32)


## ABRE EL JUEGO en el movil. Devuelve si se pudo (en PC, o si algo falla, false: el aviso dice que lo abras tu).
## Con la API de Godot 4.4+: el singleton AndroidRuntime da la Activity y JavaClassWrapper las clases de Android.
##
## ANDROID 11+ ESCONDE LAS OTRAS APPS ("package visibility", API 30): sin declararlo, PackageManager no ve el juego y
## getLaunchIntentForPackage("com.breach.voxelfps") devuelve null aunque este instalado. Lo normal seria un <queries>
## en el manifiesto, pero este APK se exporta SIN gradle (gradle_build/use_gradle_build=false) y ese manifiesto no se
## puede tocar. Lo que la exportacion si deja es añadir permisos (permissions/custom_permissions en
## export_presets.cfg), y ahi va android.permission.QUERY_ALL_PACKAGES: es un permiso "normal" (se concede al
## instalar, sin preguntar); Google Play lo restringe, pero este APK no va a Play.
## Por si aun asi sale null, el segundo camino no le pregunta a PackageManager: un Intent explicito al lanzador del
## juego (LANZADOR). La visibilidad filtra lo que se le pregunta a PackageManager, no startActivity de una actividad
## exportada. Cualquier excepcion de Java (el juego no esta instalado: ActivityNotFoundException) la recoge
## JavaClassWrapper.get_exception() y cuenta como fallo. SIN PROBAR EN UN MOVIL todavia.
static func abrir_juego(paquete: String) -> bool:
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return false
	var rt = Engine.get_singleton("AndroidRuntime")
	var act = rt.getActivity() if rt != null else null
	if act == null:
		return false
	var intent = null
	var pm = act.getPackageManager()
	if pm != null and not _fallo_java("getPackageManager"):
		intent = pm.getLaunchIntentForPackage(paquete)
		if _fallo_java("getLaunchIntentForPackage"):
			intent = null
	if intent == null:
		print("[espectar] PackageManager no ve %s: Intent explicito a %s" % [paquete, LANZADOR])
		var componentes = JavaClassWrapper.wrap("android.content.ComponentName")
		var intents = JavaClassWrapper.wrap("android.content.Intent")
		# "paquete/clase" (unflattenFromString no tiene sobrecargas: sin dudas al elegir el metodo de Java)
		var comp = componentes.unflattenFromString(paquete + "/" + LANZADOR) if componentes != null else null
		if comp != null and not _fallo_java("ComponentName") and intents != null:
			intent = intents.makeMainActivity(comp)
			if _fallo_java("makeMainActivity"):
				intent = null
	if intent == null:
		return false
	intent.addFlags(FLAG_ACTIVITY_NEW_TASK | FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
	act.startActivity(intent)
	return not _fallo_java("startActivity")


static func _fallo_java(que: String) -> bool:
	var e = JavaClassWrapper.get_exception()
	if e != null:
		print("[espectar] fallo en %s: %s" % [que, str(e)])
		return true
	return false


# ------------------------------------------------------------------ mapas y modos
static func nombre_mapa(m: String) -> String:
	if m == "":
		return ""
	return String(MAPAS.get(m, m.capitalize()))


## El modo de una sala, en clave ("bomba", "duelo", "atraco", "royale", "zombis", "campana" o "libre")
static func clave_modo(modo: String, mapa: String) -> String:
	if mapa.begins_with("campana_"):
		return "campana"
	if MODO_DE_MAPA.has(mapa):
		return String(MODO_DE_MAPA[mapa])
	match modo:
		"pve", "zombis":
			return "zombis"
		"dm", "duelo":
			return "duelo"
		"br", "royale":
			return "royale"
		"bomba", "atraco":
			return modo
	return "libre"


static func nombre_modo(modo: String, mapa: String) -> String:
	return String(MODOS.get(clave_modo(modo, mapa), "Libre"))


## La foto del mapa (o la de su modo; la campaña, la de zombis), o null
static func foto_mapa(mapa: String, modo: String) -> Texture2D:
	for n in [mapa, "modo_" + ("zombis" if modo == "campana" else modo)]:
		if n == "" or n == "modo_":
			continue
		var ruta := CARPETA_MAPAS + String(n) + ".jpg"
		if not _fotos.has(ruta):
			_fotos[ruta] = load(ruta) as Texture2D if ResourceLoader.exists(ruta) else null
		if _fotos[ruta] != null:
			return _fotos[ruta]
	return null


static func sombreado() -> Shader:
	if _sombreado == null:
		_sombreado = Shader.new()
		# redondea las dos esquinas de arriba (las de la tarjeta), con el borde suave
		_sombreado.code = """shader_type canvas_item;
uniform vec2 tam = vec2(100.0, 100.0);
uniform float radio = 15.0;
varying vec2 pos;
void vertex() { pos = VERTEX; }
void fragment() {
	float a = 1.0;
	if (pos.y < radio) {
		if (pos.x < radio) { a = clamp(radio - length(pos - vec2(radio)) + 0.5, 0.0, 1.0); }
		else if (pos.x > tam.x - radio) { a = clamp(radio - length(pos - vec2(tam.x - radio, radio)) + 0.5, 0.0, 1.0); }
	}
	COLOR.a *= a;
}"""
	return _sombreado


## La cabecera de una partida: la foto del mapa recortada a lo ancho, oscurecida abajo para el titulo, con el estado
## arriba a la izquierda y la gente arriba a la derecha. Todo pintado a mano (como los botones).
class _Banner extends Control:
	var tex: Texture2D = null
	var titulo := ""
	var modo := ""
	var estado := ""
	var color := Tema.OK
	var gente := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var mat := ShaderMaterial.new()
		mat.shader = PestanaVivo.sombreado()
		material = mat
		resized.connect(func(): (material as ShaderMaterial).set_shader_parameter("tam", size))

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var r := Rect2(Vector2.ZERO, size)
		if tex != null:
			var ts := tex.get_size()
			var k := maxf(w / ts.x, h / ts.y)
			var trozo := size / k
			draw_texture_rect_region(tex, r, Rect2((ts - trozo) * Vector2(0.5, 0.45), trozo))
		else:
			draw_rect(r, Tema.SUP2)
			draw_rect(r, Color(color, 0.06))
			Iconos.dibujar(self, "mapa", Rect2(w - 118, h * 0.5 - 50, 100, 100), Color(1, 1, 1, 0.05), 6.0)
		# sombra arriba (las pastillas) y abajo (el titulo)
		var osc := Color(0.03, 0.035, 0.05)
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, 48), Vector2(0, 48)]),
			PackedColorArray([Color(osc, 0.55), Color(osc, 0.55), Color(osc, 0.0), Color(osc, 0.0)]))
		draw_polygon(PackedVector2Array([Vector2(0, h * 0.3), Vector2(w, h * 0.3), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([Color(osc, 0.0), Color(osc, 0.0), Color(osc, 0.9), Color(osc, 0.9)]))
		_pastilla(12, 12, estado, color, true, false)
		if gente != "":
			_pastilla(w - 12, 12, gente, Tema.TEXTO, false, true, "grupo")
		# el mapa y el modo, abajo
		var f := Tema.fuente(900)
		var f2 := Tema.fuente(600)
		var y := h - 15.0
		var x := 16.0
		if titulo != "":
			draw_string(f, Vector2(x, y + 1), titulo, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0, 0, 0, 0.5))
			draw_string(f, Vector2(x, y), titulo, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
			x += f.get_string_size(titulo, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 10
		if modo != "":
			var t := ("·  " if titulo != "" else "") + modo
			draw_string(f2, Vector2(x, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.78))

	## Una pastilla oscura con un punto (o un icono) y el texto; `derecha`: x es donde acaba
	func _pastilla(x: float, y: float, texto: String, col: Color, punto: bool, derecha: bool, icono := "") -> void:
		var f := Tema.fuente(800)
		var tam := 12
		var tw := f.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
		var lead := 14.0 if punto else (18.0 if icono != "" else 0.0)
		var ancho := 10.0 + lead + tw + 11.0
		var alto := 26.0
		if derecha:
			x -= ancho
		draw_style_box(Tema.caja(Color(0.035, 0.04, 0.06, 0.82), 13, Color(col, 0.5), 1), Rect2(x, y, ancho, alto))
		var cx := x + 10.0
		if punto:
			draw_circle(Vector2(cx + 4, y + alto * 0.5), 4.0, col)
		elif icono != "":
			Iconos.dibujar(self, icono, Rect2(cx, y + (alto - 14) * 0.5, 14, 14), Color(col, 0.8))
		draw_string(f, Vector2(cx + lead, y + (alto + f.get_ascent(tam) - f.get_descent(tam)) * 0.5), texto,
			HORIZONTAL_ALIGNMENT_LEFT, -1, tam, col)
