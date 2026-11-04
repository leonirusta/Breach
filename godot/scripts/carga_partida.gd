extends Control
## LA PANTALLA DE CARGA DE LA PARTIDA (2026-10-28, pedido con la foto del "match loading" de Call of Duty Mobile): los
## jugadores de la partida en tarjetas (tu equipo a la izquierda en azul, los rivales a la derecha en rojo), con el retrato
## de su skin, su nivel y su nombre; en el medio el plano del mapa desde arriba (res://ui/planos/<mapa>.png, sacado UNA vez
## con --planofoto y reutilizado) con las salidas de cada bando, y debajo el modo, el mapa y como se gana; abajo un consejo.
## Las tarjetas salen de la sala (personas) y de los bots que ya existen: se repasan cada medio segundo mientras dura la
## carga, asi van apareciendo. Va dentro de hud.loading_panel, sobre la portada. --cargaclasica = la de antes.

const _F := preload("res://scripts/fuentes.gd")
const LobbyScript := preload("res://scripts/lobby.gd")
const W := 1920.0
const H := 1080.0
const AZUL := Color(0.16, 0.43, 0.80)
const ROJO := Color(0.74, 0.20, 0.20)
const AMARILLO := Color(1.0, 0.83, 0.25)
const CARTA := Vector2(236, 268)

const CONSEJOS := [
	"Las paredes de metal aguantan dos balas: todo lo demás cae de un balazo.",
	"Vuela las columnas de abajo y lo de arriba se viene abajo por su propio peso.",
	"El mazo abre un hueco en cualquier pared: úsalo para crear tu propio camino.",
	"La escopeta talla la pared a cada disparo: perfecta para entrar por donde no te esperan.",
	"Las granadas rebotan: lánzalas contra la pared para meterlas por una ventana.",
	"Trepar te lleva a sitios que nadie vigila: los tejados mandan.",
	"El blindaje gasta energía mientras está puesto: apágalo cuando no te disparen.",
	"Un cohete contra el suelo de arriba deja caer a quien esté encima.",
	"Moverse sin parar gasta más energía estando invisible.",
	"Los escombros grandes sirven de cobertura... hasta que alguien los vuela.",
	"Si tumbas un edificio entero, el tiempo se frena un instante para todos.",
	"Cinco bajas en una misma ronda de bomba es un AS.",
	"Cuando oigas el pitido de una granada cerca, aléjate: no esperes a verla.",
	"Una granada contra el techo hace llover escombros sobre quien esté debajo.",
	"Los policías no desactivan la bomba si te ven: primero tendrán que encontrarte.",
	"Mantener el salto con el Specter carga un súper salto que llega a los tejados.",
	"Los bloques caídos se pueden trepar: úsalos como escalera.",
	"Agachado y quieto cuesta más verte de lejos.",
	"Un puñetazo del Puño de Oro abre un túnel a través de varias paredes.",
	"A un compañero caído lo puedes revivir: no lo dejes atrás.",
]

var _lienzo: Control
var _cartas_izq: Control
var _cartas_der: Control
var _firma := ""
var _t := 0.0
var _mapa := ""
var _centro_hecho := false


func _init(mapa: String) -> void:
	_mapa = mapa
	name = "CargaPartida"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_lienzo = Control.new()
	_lienzo.size = Vector2(W, H)
	_lienzo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lienzo)
	_cartas_izq = Control.new()
	_cartas_der = Control.new()
	for c in [_cartas_izq, _cartas_der]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_lienzo.add_child(c)
	_fondo()
	_montar_consejo()
	resized.connect(_encajar)
	_encajar()
	_refrescar()


func _encajar() -> void:
	var s: Vector2 = size
	if s.x < 2.0:
		s = get_viewport_rect().size
	var k := minf(s.x / W, s.y / H)
	_lienzo.scale = Vector2(k, k)
	_lienzo.position = (s - Vector2(W, H) * k) * 0.5


func _process(dt: float) -> void:
	if not is_visible_in_tree():
		return
	_t += dt
	if not _centro_hecho:
		var m = get_tree().current_scene
		var cm := String(m.get("current_map")) if m and m.get("current_map") != null else ""
		if cm != "" and cm != "city":
			_mapa = cm
			_centro_hecho = true
			_montar_centro()
	if _t >= 0.5:
		_t = 0.0
		_refrescar()


# ------------------------------------------------------------------ quien juega
static func _nivel_bot(nombre: String) -> int:
	return 5 + int(abs(hash(nombre)) % 140)


## [[izquierda], [derecha]]: cada uno {nombre, nivel, skin, yo}
func _equipos() -> Array:
	var main = get_tree().current_scene
	var yo_equipo := ""
	var player = main.get("player") if main else null
	if player and "team" in player:
		yo_equipo = String(player.team)
	var todos: Array = []
	var mi_id: int = multiplayer.get_unique_id() if Net.is_online() else 1
	if Net.is_online() and not Net.players.is_empty():
		for id in Net.players.keys():
			var p: Dictionary = Net.players[id]
			var cu: Dictionary = p.get("cuenta", {}) if p.get("cuenta") is Dictionary else {}
			var es_yo: bool = int(id) == mi_id
			todos.append({"nombre": String(cu.get("nombre", p.get("name", "Jugador"))), "nivel": int(cu.get("nivel", 1)),
				"skin": Settings.avatar_skin if es_yo else int(cu.get("skin", 0)), "yo": es_yo,
				"team": yo_equipo if es_yo else String(p.get("team", ""))})
	else:
		todos.append({"nombre": String(Settings.player_name), "nivel": int(Cuenta.nivel()) if Cuenta.conectado() else 1,
			"skin": Settings.avatar_skin, "yo": true, "team": yo_equipo})
	for g in ["enemies", "aliados"]:
		for b in get_tree().get_nodes_in_group(g):
			if not is_instance_valid(b) or not ("nombre_marcador" in b):
				continue
			var nb := String(b.nombre_marcador)
			if nb == "" or nb.begins_with("BOT") or nb.begins_with("RIVAL"):
				continue
			todos.append({"nombre": nb, "nivel": _nivel_bot(nb), "skin": 0, "yo": false,
				"team": String(b.team) if "team" in b else ""})
	# los bots que van "entrando" mientras la sala sigue abierta (Net.espera_bots, lo manda el anfitrion)
	if Net.esperando_gente():
		for eb in Net.espera_bots:
			todos.append({"nombre": String(eb[0]), "nivel": _nivel_bot(String(eb[0])), "skin": 0, "yo": false,
				"team": String(eb[1])})
	var izq: Array = []
	var der: Array = []
	var todos_contra_todos: bool = Net.dm_mode and Net.es_dm_todos() if Net.has_method("es_dm_todos") else false
	for p in todos:
		if p["yo"]:
			izq.push_front(p)
		elif todos_contra_todos:
			(izq if izq.size() <= der.size() else der).append(p)
		elif yo_equipo != "" and String(p["team"]) == yo_equipo:
			izq.append(p)
		else:
			der.append(p)
	return [izq, der]


func _refrescar() -> void:
	var eq := _equipos()
	var firma := JSON.stringify(eq)
	if firma == _firma:
		return
	_firma = firma
	_poner_cartas(_cartas_izq, eq[0], true)
	_poner_cartas(_cartas_der, eq[1], false)


## Como en la foto: hasta 5 por lado, 3 en la columna de fuera y 2 en la de dentro (bajada media carta, sin tapar la
## banda del modo). Con mas, una rejilla de cartas mas chicas en ese mismo hueco.
const SITIOS_5 := [Vector2(160, 115), Vector2(160, 405), Vector2(160, 695), Vector2(418, 258), Vector2(418, 548)]

func _poner_cartas(caja: Control, lista: Array, izquierda: bool) -> void:
	for n in caja.get_children():
		n.queue_free()
	var n := mini(lista.size(), 12)
	var k := 1.0
	for i in n:
		var pos: Vector2
		if n <= 5:
			pos = SITIOS_5[i]
		else:
			# 3 o 4 filas y columnas estrechas, que no lleguen a la banda del medio (x < 640)
			var filas := 3 if n <= 6 else 4
			k = 0.74 if filas == 3 else 0.6
			var col := i / filas
			pos = Vector2(150.0 + col * (CARTA.x * k + 16.0), 115.0 + (i % filas) * (CARTA.y * k + 18.0) + (60.0 if col % 2 == 1 else 0.0))
		var c := _carta(lista[i], izquierda)
		c.scale = Vector2(k, k)
		c.position = pos if izquierda else Vector2(W - pos.x - CARTA.x * k, pos.y)
		caja.add_child(c)


func _carta(p: Dictionary, izquierda: bool) -> Control:
	var raiz := Control.new()
	raiz.size = CARTA
	raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var yo: bool = bool(p.get("yo", false))
	# el fondo: negro con el canto claro; la tuya, clara como la de la foto
	var fondo := Panel.new()
	fondo.size = CARTA
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.90, 0.91, 0.93) if yo else Color(0.07, 0.075, 0.085, 0.96)
	sb.border_color = Color(0.85, 0.86, 0.88, 0.9) if yo else Color(0.32, 0.34, 0.37, 0.9)
	sb.set_border_width_all(3)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 8
	fondo.add_theme_stylebox_override("panel", sb)
	raiz.add_child(fondo)
	# el emblema del bando, tenue detras del muñeco
	var emb := Label.new()
	emb.text = "◆"
	emb.add_theme_font_size_override("font_size", 150)
	emb.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55, 0.12 if not yo else 0.18))
	emb.position = Vector2(8, -10)
	raiz.add_child(emb)
	# el retrato de su skin
	var tex := _retrato(int(p.get("skin", 0)))
	if tex:
		var clip := Control.new()
		clip.clip_contents = true
		clip.position = Vector2(3, 3)
		clip.size = Vector2(CARTA.x - 6, CARTA.y - 6)
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		raiz.add_child(clip)
		var r := TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# del pecho para arriba: el retrato es de cuerpo entero, se agranda y se sube
		r.size = Vector2(CARTA.x * 2.1, CARTA.y * 2.1)
		r.position = Vector2(-CARTA.x * 0.55 + (14.0 if izquierda else -14.0), -CARTA.y * 0.16)
		r.flip_h = not izquierda
		clip.add_child(r)
	var lv := Label.new()
	lv.text = "LV. %d" % int(p.get("nivel", 1))
	lv.add_theme_font_override("font", _F.de(700, false))
	lv.add_theme_font_size_override("font_size", 24)
	lv.add_theme_color_override("font_color", AMARILLO.darkened(0.15) if yo else AMARILLO)
	lv.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	lv.add_theme_constant_override("outline_size", 5)
	lv.position = Vector2(20, CARTA.y - 98)
	raiz.add_child(lv)
	# la placa del nombre
	var placa := Panel.new()
	placa.size = Vector2(CARTA.x - 20, 44)
	placa.position = Vector2(10, CARTA.y - 62)
	var sp := StyleBoxFlat.new()
	sp.bg_color = AZUL if izquierda else ROJO
	sp.border_color = sp.bg_color.lightened(0.25)
	sp.border_width_bottom = 3
	placa.add_theme_stylebox_override("panel", sp)
	raiz.add_child(placa)
	var nom := Label.new()
	nom.text = String(p.get("nombre", ""))
	nom.add_theme_font_override("font", _F.de(600, false))
	nom.add_theme_font_size_override("font_size", 25)
	nom.add_theme_color_override("font_color", Color(1, 1, 1))
	nom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nom.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nom.clip_text = true
	nom.size = placa.size
	placa.add_child(nom)
	return raiz


static var _retratos: Dictionary = {}

static func _retrato(i: int) -> Texture2D:
	if _retratos.has(i):
		return _retratos[i]
	var skins: Array = LobbyScript.SKINS
	var n := String(skins[clampi(i, 0, skins.size() - 1)]["n"]).to_lower().replace(" ", "_")
	var ruta := "res://avatar/retratos/%s.png" % n
	var t: Texture2D = load(ruta) if ResourceLoader.exists(ruta) else null
	_retratos[i] = t
	return t


# ------------------------------------------------------------------ el centro: plano, modo y mapa
const SOMBREADO_PLANO := """shader_type canvas_item;
// el plano con sus colores de verdad (pedido: "con color, como antes"), con tres rayas rojas alrededor del borde
uniform vec2 px = vec2(0.002);
float a_en(sampler2D t, vec2 uv) { return texture(t, uv).a; }
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float fuera = 0.0;
	for (int k = 1; k <= 3; k++) {
		float d = float(k) * 14.0;
		float m = max(max(a_en(TEXTURE, UV + vec2(px.x * d, 0.0)), a_en(TEXTURE, UV - vec2(px.x * d, 0.0))),
			max(a_en(TEXTURE, UV + vec2(0.0, px.y * d)), a_en(TEXTURE, UV - vec2(0.0, px.y * d))));
		float m2 = max(max(a_en(TEXTURE, UV + vec2(px.x * (d - 4.0), 0.0)), a_en(TEXTURE, UV - vec2(px.x * (d - 4.0), 0.0))),
			max(a_en(TEXTURE, UV + vec2(0.0, px.y * (d - 4.0))), a_en(TEXTURE, UV - vec2(0.0, px.y * (d - 4.0)))));
		fuera = max(fuera, (m - m2) * (1.0 - float(k - 1) * 0.25));
	}
	vec4 raya = vec4(0.95, 0.25, 0.25, clamp(fuera, 0.0, 1.0) * 0.9);
	COLOR = c.a > 0.5 ? vec4(c.rgb, 0.97) : raya;
}
"""

func _montar_centro() -> void:
	var caja := Rect2(735, 95, 470, 590)
	var ruta := "res://ui/planos/%s.png" % _mapa
	if ResourceLoader.exists(ruta):
		var tex: Texture2D = load(ruta)
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.position = caja.position
		tr.size = caja.size
		var sh := Shader.new()
		sh.code = SOMBREADO_PLANO
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("px", Vector2(1.0 / tex.get_width(), 1.0 / tex.get_height()))
		tr.material = m
		_lienzo.add_child(tr)
		_marcar_salidas(tex, caja)
	# la banda de abajo: icono, modo, mapa y como se gana, entre dos rayas amarillas
	var banda := ColorRect.new()
	banda.color = Color(0.10, 0.11, 0.12, 0.82)
	banda.position = Vector2(668, 698)
	banda.size = Vector2(584, 250)
	banda.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lienzo.add_child(banda)
	for y in [698.0, 944.0]:
		var raya := ColorRect.new()
		raya.color = AMARILLO
		raya.position = Vector2(700, y)
		raya.size = Vector2(520, 3)
		_lienzo.add_child(raya)
	var icono := Label.new()
	icono.text = "⛨"
	icono.add_theme_font_size_override("font_size", 104)
	icono.add_theme_color_override("font_color", Color(0.93, 0.94, 0.96))
	icono.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	icono.add_theme_constant_override("outline_size", 8)
	icono.position = Vector2(712, 690)
	_lienzo.add_child(icono)
	var info := _modo()
	var modo := Label.new()
	modo.text = String(info[0])
	modo.add_theme_font_override("font", _F.de(800, false))
	modo.add_theme_font_size_override("font_size", 30)
	modo.add_theme_color_override("font_color", AMARILLO)
	modo.position = Vector2(830, 722)
	_lienzo.add_child(modo)
	var barra := ColorRect.new()
	barra.color = Color(0.95, 0.95, 0.95)
	barra.position = Vector2(830, 770)
	barra.size = Vector2(5, 40)
	_lienzo.add_child(barra)
	var mapa := Label.new()
	mapa.text = Settings.map_title(_mapa).to_upper()
	mapa.add_theme_font_override("font", _F.de(800, false))
	mapa.add_theme_font_size_override("font_size", 38)
	mapa.add_theme_color_override("font_color", Color(0.96, 0.96, 0.97))
	mapa.position = Vector2(847, 764)
	_lienzo.add_child(mapa)
	var desc := RichTextLabel.new()
	desc.bbcode_enabled = true
	desc.fit_content = true
	desc.scroll_active = false
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc.add_theme_font_override("normal_font", _F.de(500, false))
	desc.add_theme_font_size_override("normal_font_size", 27)
	desc.add_theme_color_override("default_color", Color(0.95, 0.95, 0.96))
	desc.text = "[center]%s[/center]" % String(info[1])
	desc.position = Vector2(680, 830)
	desc.size = Vector2(560, 110)
	_lienzo.add_child(desc)


## [MODO, "como se gana" con lo importante en amarillo]
func _modo() -> Array:
	var y := "[color=#ffd440]%s[/color]"
	if FileAccess.file_exists("res://maps/%s.sites.json" % _mapa):
		return ["BOMBA", "Los atacantes plantan la C4 y los defensores la desactivan. %s." % (y % "Sin reaparecer")]
	if FileAccess.file_exists("res://maps/%s.prophunt.json" % _mapa):
		return ["ESCONDIDAS", "Escóndete convertido en un mueble o %s antes de que acabe el tiempo." % (y % "encuentra a los escondidos")]
	if FileAccess.file_exists("res://maps/%s.dm.json" % _mapa):
		var sub := String(Settings.submodo_de(_mapa))
		if sub == "todos":
			return ["TODOS CONTRA TODOS", "Gana el primero en llegar al límite de bajas. Reapareces %s." % (y % "lejos de los rivales")]
		if sub == "eliminacion" or sub == "ultimo":
			return ["ELIMINACIÓN", "Sin reaparecer: gana el equipo que %s." % (y % "deje al otro sin nadie en pie")]
		return ["DUELO POR EQUIPOS", "El primer equipo en llegar al límite de bajas gana. Reapareces %s." % (y % "cerca de tu equipo")]
	if _mapa == "isla":
		return ["BATTLE ROYALE", "Salta del avión, busca armas y %s mientras la zona se cierra." % (y % "sé el último en pie")]
	if _mapa in Settings.MAPAS_ATRACO:
		return ["ATRACO", "Abre la caja fuerte y %s antes que el otro equipo." % (y % "lleva el botín a la salida")]
	if _mapa in Settings.MAPAS_PVE:
		return ["SUPERVIVENCIA", "Aguanta las oleadas de infectados %s." % (y % "junto a tu equipo")]
	return ["LIBRE", "Rompe todo lo que quieras: %s." % (y % "el mapa entero es destructible")]


## Los rombos amarillos con "Salida" donde sale cada bando (las del .dm.json), sobre el plano
func _marcar_salidas(tex: Texture2D, caja: Rect2) -> void:
	var fj := "res://ui/planos/%s.json" % _mapa
	var fd := "res://maps/%s.dm.json" % _mapa
	if not FileAccess.file_exists(fj) or not FileAccess.file_exists(fd):
		return
	var meta = JSON.parse_string(FileAccess.get_file_as_string(fj))
	var dm = JSON.parse_string(FileAccess.get_file_as_string(fd))
	if not (meta is Dictionary) or not (dm is Dictionary):
		return
	var k := minf(caja.size.x / tex.get_width(), caja.size.y / tex.get_height())
	var dib := Vector2(tex.get_width(), tex.get_height()) * k
	var org := caja.position + (caja.size - dib) * 0.5
	for clave in ["spawn_t", "spawn_ct"]:
		var p = dm.get(clave)
		if not (p is Array) or p.size() < 3:
			continue
		var u := (float(p[0]) - float(meta["x0"])) / float(meta["ancho_m"])
		var v := (float(p[2]) - float(meta["z0"])) / float(meta["alto_m"])
		var punto := org + Vector2(u, v) * dib
		var rombo := Label.new()
		rombo.text = "◈"
		rombo.add_theme_font_size_override("font_size", 46)
		rombo.add_theme_color_override("font_color", AMARILLO)
		rombo.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		rombo.add_theme_constant_override("outline_size", 6)
		rombo.position = punto - Vector2(16, 32)
		_lienzo.add_child(rombo)
		var et := Label.new()
		et.text = "Punto de salida"
		et.add_theme_font_override("font", _F.de(600, false))
		et.add_theme_font_size_override("font_size", 28)
		et.add_theme_color_override("font_color", Color(0.97, 0.97, 0.97))
		et.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		et.add_theme_constant_override("outline_size", 6)
		et.position = punto + Vector2(28, -40)
		_lienzo.add_child(et)
		var raya := ColorRect.new()
		raya.color = AMARILLO
		raya.position = punto + Vector2(28, -2)
		raya.size = Vector2(200, 2)
		_lienzo.add_child(raya)


const SOMBREADO_FONDO := """shader_type canvas_item;
uniform sampler2D pantalla : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	vec3 c = textureLod(pantalla, SCREEN_UV, 5.0).rgb;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 gris = mix(vec3(l), c, 0.18);
	COLOR = vec4(mix(gris, vec3(0.62, 0.65, 0.69), 0.55) * 0.82, 1.0);
}
"""

func _fondo() -> void:
	var cp := BackBufferCopy.new()
	cp.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(cp)
	move_child(cp, 0)
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SOMBREADO_FONDO
	var m := ShaderMaterial.new()
	m.shader = sh
	r.material = m
	add_child(r)
	move_child(r, 1)
	# la rejilla tenue del suelo, como la de la foto
	var rej := ColorRect.new()
	rej.set_anchors_preset(Control.PRESET_FULL_RECT)
	rej.color = Color(0, 0, 0, 0.0)
	add_child(rej)
	move_child(rej, 2)


func _montar_consejo() -> void:
	var l := Label.new()
	l.text = String(CONSEJOS[randi() % CONSEJOS.size()])
	# a veces, lo tuyo (2026-11-01)
	if Settings.bajas_total >= 10 and randf() < 0.25:
		l.text = "Llevas %d bajas en total. ¿Cuántas caen hoy?" % Settings.bajas_total
	l.add_theme_font_override("font", _F.de(500, false))
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", Color(0.93, 0.93, 0.95))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(0, 1020)
	l.size = Vector2(W, 40)
	_lienzo.add_child(l)
	var franja := ColorRect.new()
	franja.color = Color(0, 0, 0, 0.35)
	franja.position = Vector2(0, 1010)
	franja.size = Vector2(W, 70)
	franja.show_behind_parent = false
	_lienzo.add_child(franja)
	_lienzo.move_child(franja, 0)


## --cargafoto=<ruta.png>: deja la carga delante (aunque ya haya cargado) y saca una foto a los 10 s, con los bots ya puestos
var _foto_t := 0.0
func _physics_process(dt: float) -> void:
	var ruta := ""
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--cargafoto="):
			ruta = String(a).substr(12)
	if ruta == "":
		set_physics_process(false)
		return
	_foto_t += dt
	var panel := get_parent() as Control
	if panel and not panel.visible:
		panel.visible = true
		panel.get_parent().move_child(panel, -1)
	if _foto_t > 10.0 and _foto_t - dt <= 10.0:
		_refrescar()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ruta)
		print("[cargafoto] ", ruta)
		get_tree().quit()
