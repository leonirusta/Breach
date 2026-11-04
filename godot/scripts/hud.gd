extends CanvasLayer
const Estadisticas := preload("res://scripts/estadisticas.gd")
## HUD adaptable a cualquier pantalla: retícula, munición, vida, marcador de impacto, mensajes,
## pantalla de carga, perfilador (F3) con registro CSV (F4) y controles táctiles (si hay pantalla táctil).
## Todo se construye por código para que las posiciones dependan del tamaño real y del área segura (notch).
##
## Encima de esa base viven las capas de "sensación de shooter": barra de armas con icono 2D del
## modelo, marcador de partida (bandos, tanteo y bajas), sangre en la lente, viñeta de vida baja,
## flechas de daño direccional, aberración cromática al recibir un golpe, desenfoque de movimiento
## y la mira telescópica del francotirador.

const MobileControls := preload("res://scripts/mobile_controls.gd")
const MinimapScript := preload("res://scripts/minimap.gd")

var player
var main
var root: Control
var crosshair: Control
var cross_lines: Array[ColorRect] = []
var hit_marker: Control
var hit_t := 0.0
## --diagvivo: contar por la consola lo que pasa mientras se juega (ver main.gd).
var _diag_vivo := "--diagvivo" in OS.get_cmdline_user_args()
var ammo_label: Label
var weapon_label: Label
var kills_label: Label
var objective_label: Label
var quality_label: Label
var health_bar: ProgressBar
var armor_bar: ProgressBar
var casco_bar: ProgressBar = null
## VENDAS Y BOTIQUINES (player.gd): cuantas llevas, encima de la vida, y la barra de progreso al curarte
var curas_label: Label = null
var cura_bar: ProgressBar = null
var cura_label: Label = null
var _curas_on := false      ## el casco del botin (player.casco): barrita al lado del chaleco
var profiler_panel: PanelContainer
var profiler_label: Label
var loading_panel: ColorRect
var loading_bar: ProgressBar
var loading_label: Label
var message: Label
var msg_t := 0.0
var damage_rect: ColorRect
var damage_t := 0.0
var mobile: Control
var csv: FileAccess
var csv_t := 0.0
var stats_t := 0.0
var last_stats: Dictionary = {}
var last_quality := 1
var quality_name := ""
var safe_l := 0.0
var safe_r := 0.0
var safe_t := 0.0
var safe_b := 0.0
var menu_panel: PanelContainer = null
var fps_label: Label
var fps_label2: Label            ## la segunda columna del contador: lo que mas pesa (Prof)
var show_fps := false

# --- combate ---
var action_panel: PanelContainer = null   ## aviso de acción ("MANTÉN [E]...") con barra de progreso
var action_label: Label
var action_bar: ProgressBar
var action_t := 0.0
var weapon_bar: HBoxContainer = null      ## ranuras de armas abajo en el centro, con icono 2D
var weapon_cards: Array = []
var _bar_con_c4 := false                  ## si la barra dibujada ahora incluye la ranura de C4
var killfeed: Control = null
var score_panel: Control = null           ## el marcador de arriba en el centro (marcador_hud.gd)
var score_label: Label
var feed_box: VBoxContainer = null        ## bajas recientes
var round_banner: Label = null
var round_banner_t := 0.0
var minimap: Control = null
var boton_habilidad: Control = null
var barra_energia: Control = null     ## la ENERGIA de la invisibilidad (barra_energia.gd), debajo de la vida
var boton_blindaje: Control = null    ## el BLINDAJE (boton_blindaje.gd), a la izquierda del de la habilidad

# --- efectos de pantalla ---
var vignette: TextureRect                 ## viñeta roja cuando te queda poca vida
var aberration: ColorRect                 ## separación de canales al recibir daño
var aberration_copia: BackBufferCopy = null   ## su copia de pantalla: ver _efectos_orden
var dmg_arcs: Array = []                  ## flechas de "me disparan desde ahí"
var dmg_dirs: Array = []                  ## [posición del atacante, tiempo restante]
var scope: Control = null                 ## mira telescópica (francotirador)
var scope_on := false
var mblur: ColorRect = null               ## desenfoque de movimiento
var blood_layer: Control = null           ## sangre en la lente
var _drops: Array = []                    ## [nodo, vida, vida total, velocidad de caída]
var _drop_pool: Array[TextureRect] = []
var _drop_tex: Array[ImageTexture] = []
# --- TIERRA Y EMPAÑADO EN LA LENTE ------------------------------------------------------------
## Una explosion cerca y a la vista te tira tierra al cristal y lo empaña con el calor. El empaño
## se va sole en un segundo; la tierra SE QUEDA hasta que el personaje se la quita con el brazo.
var dirt_layer: Control
var _dirt_tex: Array[ImageTexture] = []
var _dirt_tex_claro: Array[ImageTexture] = []   ## la misma tierra, clara: la que queda delante del escudo
var _dirt: Array = []                     ## [nodo, alfa, x en pantalla]
var fog_rect: ColorRect                   ## el vaho, un desenfoque que se disipa
var fog_t := 0.0
const FOG_BAJA := 0.30                    ## por segundo: a 0,30 el vaho tarda algo mas de 3 s en irse
var combat_panel: PanelContainer = null   ## panel de opciones de combate (desde el menú)
var carrier_label: Label = null           ## quién lleva la C4
var carrier_icon: TextureRect = null      ## la bombita que va delante de ese nombre


func setup(p, m) -> void:
	player = p
	main = m
	player.ammo_changed.connect(_on_ammo)
	player.health_changed.connect(_on_health)
	player.damaged.connect(func(): damage_t = 0.4)
	# El marcador de acierto cambia de color y tamaño según dónde diste: blanco al cuerpo, dorado a
	# la cabeza y rojo grande si lo mataste. Es el 80 % de la satisfacción de acertar.
	player.hit_marker.connect(func(): Estadisticas.sumar("aciertos"))
	player.hit_marker.connect(func():
		if _diag_vivo:
			print("[vivo] marcador de acierto: %s (lo enciende %s)" % [
				String(player.hit_kind), String(player.get("hit_origen"))])
		hit_t = 0.20 if String(player.hit_kind) == "kill" else 0.12
		var col := Color(1, 1, 1, 0.95)
		var sc := 1.0
		if String(player.hit_kind) == "kill":
			col = Color(1.0, 0.25, 0.2, 1.0)
			sc = 1.45
		elif String(player.hit_kind) == "head":
			col = Color(1.0, 0.85, 0.25, 1.0)
			sc = 1.2
		hit_marker.modulate = col
		hit_marker.scale = Vector2(sc, sc))
	if not Net.carrier_changed.is_connected(refresh_carrier):
		Net.carrier_changed.connect(refresh_carrier)
	if not Net.feed_event.is_connected(add_feed):
		Net.feed_event.connect(add_feed)
	if not Net.players_changed.is_connected(_refresh_score):
		Net.players_changed.connect(_refresh_score)
	if not Net.round_over.is_connected(_on_round_over):
		Net.round_over.connect(_on_round_over)
	if mobile:
		mobile.setup(player)
	if minimap and minimap.has_method("setup") and main:
		minimap.setup(player, main.world, main)
	if boton_habilidad:
		boton_habilidad.player = player
	if barra_energia:
		barra_energia.player = player
	if boton_blindaje:
		boton_blindaje.player = player


func _ready() -> void:
	if "--capaspantalla" in OS.get_cmdline_user_args():
		_capas_pantalla_diag.call_deferred()
	layer = 10
	root = Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build()
	root.resized.connect(_layout)
	_layout()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	# el perfilador (F3) es de pruebas: online no sale aunque se dejara encendido
	profiler_panel.visible = Settings.show_profiler and Settings.herramientas()


## Etiqueta que se añade sola al HUD.
func _label(font_size: int, color := Color.WHITE) -> Label:
	var l := _ulabel(font_size, color)
	root.add_child(l)
	return l


## Igual, pero SIN padre: para meterla dentro de otro contenedor (si no, Godot se queja de que el
## nodo ya tiene padre).
func _ulabel(font_size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build() -> void:
	damage_rect = ColorRect.new()
	damage_rect.color = Color(0.7, 0.0, 0.0, 0.0)
	# ESCONDIDO MIENTRAS NO HAY ROJO (2026-10-01, la noche de optimizacion): visible con el color a alfa 0 se pintaba un
	# rectangulo a pantalla completa CADA fotograma (lo listaba --lienzos), que no se veia y costaba GPU
	damage_rect.visible = false
	damage_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(damage_rect)

	crosshair = Control.new()
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)
	for i in 4:
		var r := ColorRect.new()
		r.color = Color(1, 1, 1, 0.9)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crosshair.add_child(r)
		cross_lines.append(r)
	hit_marker = Control.new()
	hit_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hit_marker.visible = false
	root.add_child(hit_marker)
	for i in 4:
		var r := ColorRect.new()
		r.color = Color(1, 1, 1, 1)
		r.size = Vector2(3, 14)
		r.pivot_offset = Vector2(1.5, 7)
		r.rotation = PI * 0.25 + PI * 0.5 * i
		r.position = Vector2(-1.5, -7) + Vector2(cos(PI * 0.25 + PI * 0.5 * i + PI * 0.5), sin(PI * 0.25 + PI * 0.5 * i + PI * 0.5)) * 14.0
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hit_marker.add_child(r)

	ammo_label = _label(36)
	weapon_label = _label(16, Color(0.85, 0.85, 0.85))
	kills_label = _label(20)
	kills_label.text = "Bajas: 0"
	# FUERA (2026-10-03, pedido: "por que dice puntos, bots vivos, numero de bajas en texto blanco? quitalo, nunca te lo
	# pedi"): el texto de arriba ya no se ve; las cuentas siguen (el marcador y el final las enseñan a su manera)
	kills_label.visible = false
	preload("res://scripts/puntuacion.gd").aviso = func():
		if is_instance_valid(kills_label):
			_refresh_kills()
	# los nombres y la vida de los compañeros, a traves de las paredes (etiquetas_equipo.gd). Va la primera de la
	# interfaz para quedar DEBAJO de todo lo demas
	var etiquetas := preload("res://scripts/etiquetas_equipo.gd").new()
	etiquetas.name = "EtiquetasEquipo"
	root.add_child(etiquetas)
	root.move_child(etiquetas, 0)
	# EL REGISTRO DE BAJAS, arriba a la izquierda (killfeed.gd)
	killfeed = preload("res://scripts/killfeed.gd").new()
	killfeed.name = "RegistroBajas"
	root.add_child(killfeed)
	if not Net.baja_feed.is_connected(killfeed.baja):
		Net.baja_feed.connect(func(a, ea, k, i, v, ev, c):
			var _tk := Time.get_ticks_usec()
			killfeed.baja(a, ea, k, i, v, ev, c)
			Prof.add("baja.killfeed", Time.get_ticks_usec() - _tk))
	objective_label = _label(17, Color(1.0, 0.9, 0.55))
	objective_label.text = ""
	quality_label = _label(14, Color(0.8, 0.9, 1.0))
	quality_label.visible = false   # el "Calidad X" arriba a la derecha se quito de la interfaz (2026-09-18); sigue en el perfilador (F3)
	carrier_label = _label(16, Color(1.0, 0.86, 0.3))
	carrier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	carrier_label.text = ""
	# icono de bomba dibujado a mano: la fuente por defecto de Godot no trae emojis (saldria un
	# cuadrado vacio), asi que se pinta la textura por codigo
	carrier_icon = TextureRect.new()
	carrier_icon.texture = _bomb_icon_texture()
	carrier_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	carrier_icon.size = Vector2(22, 22)
	carrier_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carrier_icon.visible = false
	root.add_child(carrier_icon)

	health_bar = ProgressBar.new()
	health_bar.max_value = 100
	health_bar.value = 100
	health_bar.show_percentage = false
	health_bar.custom_minimum_size = Vector2(260, 14)
	health_bar.size = Vector2(260, 14)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.15, 0.15, 0.9)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	health_bar.add_theme_stylebox_override("fill", fill)
	health_bar.add_theme_stylebox_override("background", bg)
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(health_bar)

	# ARMADURA: la misma barra en azul, justo encima de la vida. Solo se ve si llevas chaleco puesto.
	armor_bar = ProgressBar.new()
	armor_bar.max_value = 100
	armor_bar.value = 0
	armor_bar.show_percentage = false
	armor_bar.custom_minimum_size = Vector2(260, 10)
	armor_bar.size = Vector2(260, 10)
	var fill_a := StyleBoxFlat.new()
	fill_a.bg_color = Color(0.35, 0.70, 1.0, 0.92)
	armor_bar.add_theme_stylebox_override("fill", fill_a)
	armor_bar.add_theme_stylebox_override("background", bg)
	armor_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	armor_bar.visible = false
	root.add_child(armor_bar)

	# CASCO: una barrita corta y ocre a la derecha del chaleco. Discreta a proposito: solo existe en los
	# mapas con botin y no tiene que competir con la vida. Solo se ve con el casco puesto.
	casco_bar = ProgressBar.new()
	casco_bar.max_value = 100
	casco_bar.value = 0
	casco_bar.show_percentage = false
	casco_bar.custom_minimum_size = Vector2(64, 10)
	casco_bar.size = Vector2(64, 10)
	var fill_c := StyleBoxFlat.new()
	fill_c.bg_color = Color(0.86, 0.68, 0.30, 0.92)
	casco_bar.add_theme_stylebox_override("fill", fill_c)
	casco_bar.add_theme_stylebox_override("background", bg)
	casco_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	casco_bar.visible = false
	root.add_child(casco_bar)

	curas_label = Label.new()
	curas_label.add_theme_font_size_override("font_size", 15)
	curas_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.92))
	curas_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	curas_label.add_theme_constant_override("outline_size", 4)
	curas_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	curas_label.visible = false
	root.add_child(curas_label)
	# la barra de curarse: en medio, por debajo de la mira, como en cualquier battle royale
	cura_bar = ProgressBar.new()
	cura_bar.max_value = 1.0
	cura_bar.step = 0.001
	cura_bar.show_percentage = false
	cura_bar.custom_minimum_size = Vector2(220, 8)
	cura_bar.size = Vector2(220, 8)
	var fill_cu := StyleBoxFlat.new()
	fill_cu.bg_color = Color(0.45, 0.90, 0.50, 0.95)
	cura_bar.add_theme_stylebox_override("fill", fill_cu)
	cura_bar.add_theme_stylebox_override("background", bg)
	cura_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cura_bar.visible = false
	root.add_child(cura_bar)
	cura_label = Label.new()
	cura_label.add_theme_font_size_override("font_size", 16)
	cura_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	cura_label.add_theme_constant_override("outline_size", 4)
	cura_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cura_label.custom_minimum_size = Vector2(220, 20)
	cura_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cura_label.visible = false
	root.add_child(cura_label)

	# ESCUDO BALISTICO: su vida (500) en gris acero, encima de la armadura. Solo con el escudo en la mano.
	escudo_bar = ProgressBar.new()
	escudo_bar.max_value = 500
	escudo_bar.value = 500
	escudo_bar.show_percentage = false
	escudo_bar.custom_minimum_size = Vector2(260, 10)
	escudo_bar.size = Vector2(260, 10)
	var fill_e := StyleBoxFlat.new()
	fill_e.bg_color = Color(0.80, 0.84, 0.88, 0.92)
	escudo_bar.add_theme_stylebox_override("fill", fill_e)
	escudo_bar.add_theme_stylebox_override("background", bg)
	escudo_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	escudo_bar.visible = false
	root.add_child(escudo_bar)
	escudo_label = _label(12, Color(0.85, 0.88, 0.92))
	escudo_label.text = "ESCUDO"
	escudo_label.visible = false

	message = _label(20, Color(1, 0.92, 0.6))
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.modulate.a = 0.0

	_build_action_panel()
	_build_screen_fx()

	profiler_panel = PanelContainer.new()
	profiler_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0, 0, 0, 0.55)
	psb.set_content_margin_all(8)
	profiler_panel.add_theme_stylebox_override("panel", psb)
	profiler_label = Label.new()
	profiler_label.add_theme_font_size_override("font_size", 13)
	profiler_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	profiler_panel.add_child(profiler_label)
	root.add_child(profiler_panel)

	loading_panel = ColorRect.new()
	loading_panel.color = Color(0.05, 0.06, 0.08, 1)
	loading_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	# EN SU PROPIA CAPA, ENCIMA DE TODO EL JUEGO (2026-10-10, bug: "antes de acabar la carga se ve el fondo azul con una
	# explosion"): iba dentro de `root` con la interfaz, y los efectos de pantalla que se estrenan durante la carga (la
	# lente, la onda del misil...: se dibujan encima de toda la interfaz) la tapaban un instante con el mapa sin cargar.
	# Capa 110: por encima del juego y por debajo de la carta de bienvenida y el aviso de version (124/125).
	var capa_carga := CanvasLayer.new()
	capa_carga.name = "CapaCarga"
	capa_carga.layer = 110
	add_child(capa_carga)
	capa_carga.add_child(loading_panel)
	# LA MISMA IMAGEN DEL ARRANQUE, de fondo mientras se genera el mapa. Antes era un rectangulo
	# gris oscuro y esos segundos de espera se hacian largos mirando nada.
	# UNA PORTADA AL AZAR (Settings.PORTADAS), no siempre la misma
	var portada := Settings.portada_al_azar()
	if portada != "":
		# ENTERA, sin recortar los lados en pantallas alargadas (Settings.nodo_portada)
		loading_panel.add_child(Settings.nodo_portada(portada))
		# un velo oscuro por encima: sin el, el texto blanco y la barra se pierden sobre la imagen
		var velo := ColorRect.new()
		velo.color = Color(0.02, 0.02, 0.03, 0.55)
		velo.set_anchors_preset(Control.PRESET_FULL_RECT)
		velo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		loading_panel.add_child(velo)
	# LA PANTALLA DE CARGA DE LA PARTIDA (carga_partida.gd, 2026-10-28): los jugadores, el plano y el modo. No en la campaña
	# ni en el tutorial (traen su propia entrada). --cargaclasica = la de antes
	var mapa_c := String(Settings.map)
	if not ("--cargaclasica" in OS.get_cmdline_user_args()) and not Settings.tutorial_activo 			and not FileAccess.file_exists("res://maps/%s.campana.json" % mapa_c):
		carga_partida = preload("res://scripts/carga_partida.gd").new(mapa_c)
		loading_panel.add_child(carga_partida)
	loading_label = Label.new()
	loading_label.text = "Generando ciudad y mallando chunks..."
	loading_label.add_theme_font_size_override("font_size", 24)
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_panel.add_child(loading_label)
	loading_bar = ProgressBar.new()
	loading_bar.max_value = 1.0
	loading_bar.show_percentage = false
	loading_bar.size = Vector2(420, 16)
	loading_panel.add_child(loading_bar)

	minimap = MinimapScript.new()
	minimap.name = "Minimap"
	root.add_child(minimap)
	# LA HABILIDAD (boton_habilidad.gd): bajo el minimapa, o en su sitio si no hay minimapa
	barra_energia = preload("res://scripts/barra_energia.gd").new()
	barra_energia.name = "BarraEnergia"
	root.add_child(barra_energia)
	boton_habilidad = preload("res://scripts/boton_habilidad.gd").new()
	boton_habilidad.name = "BotonHabilidad"
	boton_habilidad.hud = self
	root.add_child(boton_habilidad)
	boton_blindaje = preload("res://scripts/boton_blindaje.gd").new()
	boton_blindaje.name = "BotonBlindaje"
	boton_blindaje.boton = boton_habilidad
	root.add_child(boton_blindaje)

	if Settings.is_touch():
		build_mobile_controls()
	# botón MENÚ (arriba a la derecha, atajo Esc): agrupa todas las herramientas y la configuración gráfica.
	# CON EL ESTILO DEL LOBBY: caja oscura con las esquinas cortadas, las tres rayas en amarillo y la letra
	# estrecha. El "☰" de antes dependia de que la fuente trajera ese simbolo.
	var bm := Button.new()
	bm.focus_mode = Control.FOCUS_NONE
	bm.name = "MenuBtn"
	bm.tooltip_text = "Menú (Esc)"
	bm.add_theme_stylebox_override("normal", _corte_menu(Color(0.012, 0.014, 0.018, 0.74), LINEA_MENU, 1, 10))
	bm.add_theme_stylebox_override("hover", _corte_menu(Color(0.05, 0.055, 0.065, 0.88), ORO_MENU, 1, 10))
	bm.add_theme_stylebox_override("pressed", _corte_menu(Color(0, 0, 0, 0.92), ORO_MENU, 2, 10))
	bm.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	bm.pressed.connect(toggle_menu)
	root.add_child(bm)
	# EL CHAT Y EL MICROFONO, a la izquierda del MENU (chat_voz.gd; solo con gente en la partida)
	var cv = preload("res://scripts/chat_voz.gd").new()
	cv.name = "ChatVoz"
	cv.hud = self
	root.add_child(cv)
	bm.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bm.size = Vector2(140, 50)          # (era 118 x 42: 2026-10-05, pedido "un poco mas grande")
	bm.position = Vector2(root.size.x - 152, 12)
	var bmh := HBoxContainer.new()
	bmh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bmh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bmh.alignment = BoxContainer.ALIGNMENT_CENTER
	bmh.add_theme_constant_override("separation", 10)
	bm.add_child(bmh)
	var rayas := VBoxContainer.new()
	rayas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rayas.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rayas.add_theme_constant_override("separation", 5)
	bmh.add_child(rayas)
	for i in 3:
		var raya := ColorRect.new()
		raya.color = ORO_MENU
		raya.mouse_filter = Control.MOUSE_FILTER_IGNORE
		raya.custom_minimum_size = Vector2(17 if i == 1 else 24, 4)
		raya.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		rayas.add_child(raya)
	var bml := Label.new()
	bml.text = "MENÚ"
	bml.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bml.add_theme_font_override("font", _fuente_menu())
	bml.add_theme_font_size_override("font_size", 26)
	bml.add_theme_color_override("font_color", Color.WHITE)
	bmh.add_child(bml)
	# contador de FPS (menú gráfico)
	fps_label = Label.new()
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_label.add_theme_font_size_override("font_size", 12)
	fps_label.add_theme_color_override("font_color", Color(1.0, 0.83, 0.0))
	fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	fps_label.add_theme_constant_override("outline_size", 4)
	fps_label.add_theme_constant_override("line_spacing", -2)
	fps_label2 = fps_label.duplicate()
	fps_label2.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	fps_label2.visible = false
	root.add_child(fps_label2)
	fps_label.position = Vector2(root.size.x - 130, 58)
	fps_label.visible = false
	root.add_child(fps_label)


## Aviso de acción con barra: plantar, desactivar, abrir la caja fuerte, espectar...
func _build_action_panel() -> void:
	action_panel = PanelContainer.new()
	action_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.035, 0.05, 0.82)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	action_panel.add_theme_stylebox_override("panel", sb)
	root.add_child(action_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_panel.add_child(v)
	action_label = _ulabel(18, Color(1.0, 0.92, 0.7))
	action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(action_label)
	action_bar = ProgressBar.new()
	action_bar.max_value = 1.0
	action_bar.show_percentage = false
	action_bar.custom_minimum_size = Vector2(280, 8)
	action_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := StyleBoxFlat.new()
	f.bg_color = Color(1.0, 0.83, 0.2, 0.95)
	var b := StyleBoxFlat.new()
	b.bg_color = Color(0, 0, 0, 0.5)
	action_bar.add_theme_stylebox_override("fill", f)
	action_bar.add_theme_stylebox_override("background", b)
	v.add_child(action_bar)


func show_action(text: String, t01: float) -> void:
	if action_panel == null:
		return
	action_label.text = text
	action_bar.value = clampf(t01, 0.0, 1.0)
	action_bar.visible = t01 > 0.0
	action_panel.visible = true
	action_t = 0.15        # si nadie lo refresca, desaparece solo


## EL ESPECTADOR (pedido: sin la caja negra del medio). Abajo a la izquierda, en la esquina: a quien miras
## y, al lado, un boton cuadrado para cambiar entre su vista (primera persona, por defecto) y detras de el.
## `titulo` vacio lo esconde.
var _esp_caja: Control = null
var _esp_titulo: Label = null
var _esp_nombre: Label = null
var _esp_btn: Button = null

var _esp_flechas: Array = []

func espectador(titulo: String, nombre: String = "") -> void:
	if titulo == "":
		if _esp_caja:
			_esp_caja.visible = false
		return
	if _esp_caja == null:
		_esp_caja = HBoxContainer.new()
		_esp_caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_esp_caja.add_theme_constant_override("separation", 12)
		_esp_caja.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_esp_caja.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_esp_caja.offset_left = 18.0
		_esp_caja.offset_bottom = -18.0
		root.add_child(_esp_caja)
		var col := Color(1.0, 0.83, 0.0)
		_esp_btn = Button.new()
		_esp_btn.focus_mode = Control.FOCUS_NONE
		_esp_btn.custom_minimum_size = Vector2(64, 64)
		_esp_btn.expand_icon = true
		_esp_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_esp_btn.add_theme_constant_override("icon_max_width", 44)
		_esp_btn.icon = preload("res://scripts/touch_icons.gd").get_icon("view")
		for n in ["icon_normal_color", "icon_hover_color"]:
			_esp_btn.add_theme_color_override(n, col)
		_esp_btn.add_theme_color_override("icon_pressed_color", Color.WHITE)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.055, 0.07, 0.55)
		sb.border_color = Color(col.r, col.g, col.b, 0.9)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(0)
		sb.set_content_margin_all(8)
		for st in ["normal", "hover", "focus", "pressed"]:
			_esp_btn.add_theme_stylebox_override(st, sb)
		_esp_btn.pressed.connect(func():
			if player and player.has_method("toggle_third_person"):
				player.toggle_third_person())
		# (SIN LETRAS DE TECLAS en el movil; en el PC, su tecla: teclas_pc.gd)
		preload("res://scripts/teclas_pc.gd").marca(_esp_btn, "V")
		# el texto, sin fondo: una raya amarilla a la izquierda y letra con sombra
		var raya := ColorRect.new()
		raya.color = col
		raya.custom_minimum_size = Vector2(3, 0)
		raya.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var textos := VBoxContainer.new()
		textos.mouse_filter = Control.MOUSE_FILTER_IGNORE
		textos.alignment = BoxContainer.ALIGNMENT_CENTER
		textos.add_theme_constant_override("separation", 0)
		_esp_titulo = Label.new()
		_esp_titulo.add_theme_font_size_override("font_size", 13)
		_esp_titulo.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
		_esp_nombre = Label.new()
		_esp_nombre.add_theme_font_size_override("font_size", 20)
		_esp_nombre.add_theme_color_override("font_color", Color.WHITE)
		for l in [_esp_titulo, _esp_nombre]:
			l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
			l.add_theme_constant_override("shadow_offset_x", 1)
			l.add_theme_constant_override("shadow_offset_y", 2)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			textos.add_child(l)
		_esp_caja.add_child(_esp_btn)
		# ESPECTANDO, SIEMPRE EN TERCERA PERSONA (2026-10-18, pedido): sin el boton de la camara
		_esp_btn.visible = false
		# CAMBIAR A QUIEN SE MIRA (2026-10-15, pedido): dos flechas tocables (disparar / apuntar siguen valiendo)
		for paso in [-1, 1]:
			var fl := Button.new()
			fl.focus_mode = Control.FOCUS_NONE
			fl.custom_minimum_size = Vector2(64, 64)
			fl.text = "◀" if paso < 0 else "▶"
			fl.add_theme_font_size_override("font_size", 30)
			fl.add_theme_color_override("font_color", col)
			fl.add_theme_color_override("font_pressed_color", Color.WHITE)
			for st in ["normal", "hover", "focus", "pressed"]:
				fl.add_theme_stylebox_override(st, sb)
			fl.pressed.connect(func():
				if player and player.has_method("espectar_siguiente"):
					player.espectar_siguiente(paso))
			_esp_caja.add_child(fl)
			if paso < 0:
				_esp_flechas = [fl]
			else:
				_esp_flechas.append(fl)
		_esp_caja.add_child(raya)
		_esp_caja.add_child(textos)
	# las flechas solo cuando hay a quien cambiar (mirando a un compañero)
	for fl in _esp_flechas:
		if is_instance_valid(fl):
			fl.visible = titulo == "ESPECTANDO"
	_esp_titulo.text = titulo
	_esp_nombre.text = nombre
	_esp_nombre.visible = nombre != ""
	_esp_caja.visible = true


func hide_action() -> void:
	if action_panel:
		action_panel.visible = false
	action_t = 0.0


# ---------------------------------------------------------------------------
# Efectos de pantalla: viñeta de vida, flechas de daño, aberración, mira y estela
# ---------------------------------------------------------------------------
func _build_screen_fx() -> void:
	# VIÑETA DE VIDA: los bordes se tiñen de rojo según lo bajo que estés. Es información
	# periférica: te enteras de que estás para morir sin mirar la barra.
	vignette = TextureRect.new()
	vignette.texture = _vignette_texture()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.modulate = Color(1, 1, 1, 0.0)
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(vignette)
	# ARCO DE DAÑO: apunta a quien te ha disparado
	for i in 4:
		var arc := _ulabel(34, Color(1.0, 0.25, 0.2, 0.9))
		arc.text = "▲"
		arc.visible = false
		root.add_child(arc)
		dmg_arcs.append(arc)
	# ABERRACIÓN CROMÁTICA al recibir un impacto: los canales se separan un instante. Sólo está
	# viva mientras dura el golpe (visible = false el resto del tiempo: no cuesta nada).
	aberration = ColorRect.new()
	aberration.set_anchors_preset(Control.PRESET_FULL_RECT)
	aberration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aberration.visible = false
	var sh := Shader.new()
	sh.code = _mips("""
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear;   // (sin mipmaps: solo se lee el nivel 0; 2026-10-10)
uniform float amount = 0.0;
void fragment() {
	vec2 d = SCREEN_UV - vec2(0.5);
	float k = amount * dot(d, d) * 4.0;
	float r = texture(screen, SCREEN_UV + d * k * 0.010).r;
	float g = texture(screen, SCREEN_UV).g;
	float b = texture(screen, SCREEN_UV - d * k * 0.010).b;
	COLOR = vec4(r, g, b, 1.0);
}
""")
	var sm := ShaderMaterial.new()
	sm.shader = sh
	aberration.material = sm
	root.add_child(aberration)
	aberration_copia = _copia_para(aberration, "CopiaAberracion")
	_efectos_orden()


## Textura de viñeta: transparente en el centro, roja hacia los bordes. Se genera una vez.
func _vignette_texture() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (Vector2(x, y) / float(n - 1)) * 2.0 - Vector2.ONE
			var d: float = clampf((u.length() - 0.45) / 0.75, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.75, 0.02, 0.02, pow(d, 1.6)))
	return ImageTexture.create_from_image(img)


## Un enemigo te ha dado: se marca de dónde venía el tiro durante 2 s.
func damage_from(attacker_pos: Vector3) -> void:
	dmg_dirs.append([attacker_pos, 2.0])
	if dmg_dirs.size() > dmg_arcs.size():
		dmg_dirs.pop_front()


## Coloca las flechas de daño alrededor de la mira, girando según de dónde te disparan.
func _update_damage_arcs(dt: float) -> void:
	if dmg_arcs.is_empty():
		return
	var cam: Camera3D = player.get_node_or_null("Head/Camera3D") if (player and is_instance_valid(player)) else null
	var c: Vector2 = root.size * 0.5
	for i in dmg_arcs.size():
		var arc: Label = dmg_arcs[i]
		if i >= dmg_dirs.size():
			arc.visible = false
			continue
		# EL RELOJ CORRE SIEMPRE, haya camara o no. Saltandoselo cuando no la hay, las flechas se
		# quedaban guardadas con su tiempo intacto y reaparecian enteras mas tarde.
		var e: Array = dmg_dirs[i]
		e[1] -= dt
		dmg_dirs[i] = e
		if cam == null:
			arc.visible = false
			continue
		if e[1] <= 0.0:
			arc.visible = false
			continue
		# DOS COSAS ESTABAN MAL AQUI, y por eso la flecha "no indicaba nada y mareaba":
		#
		# 1. EL LADO ESTABA CAMBIADO. Con el angulo de antes, a quien te disparaba desde la DERECHA la
		#    flecha lo señalaba a la izquierda. O sea que girabas hacia donde no era.
		# 2. LA CAMARA CABECEA. El angulo salia del vector de la camara CON su inclinacion: mirando al
		#    cielo o al suelo, sus componentes x y z se van a cero y atan2 devuelve cualquier cosa, asi
		#    que la flecha se ponia a girar sola con solo mover la vista.
		#
		# Ahora los dos vectores se aplanan al suelo (la altura del que dispara no cambia por donde hay
		# que girarse) y el angulo va medido desde donde miras: 0 de frente, +90 por la derecha.
		var to: Vector3 = (e[0] as Vector3) - player.global_position
		to.y = 0.0
		var fwd: Vector3 = -cam.global_transform.basis.z
		fwd.y = 0.0
		if fwd.length_squared() < 1.0e-6:       # mirando a plomo arriba o abajo: vale hacia donde apunta el cuerpo
			fwd = -player.global_transform.basis.z
			fwd.y = 0.0
		if to.length_squared() < 1.0e-6 or fwd.length_squared() < 1.0e-6:
			arc.visible = false
			continue
		var ang: float = wrapf(atan2(to.x, -to.z) - atan2(fwd.x, -fwd.z), -PI, PI)
		arc.visible = true
		arc.modulate.a = clampf(e[1] / 2.0, 0.0, 1.0)
		arc.rotation = ang                      # el triangulo apunta HACIA FUERA, al que dispara
		arc.pivot_offset = arc.size * 0.5
		arc.position = c + Vector2(sin(ang), -cos(ang)) * 110.0 - arc.size * 0.5
	var k := dmg_dirs.size() - 1
	while k >= 0:
		if float(dmg_dirs[k][1]) <= 0.0:
			dmg_dirs.remove_at(k)
		k -= 1


# ---------------------------------------------------------------------------
# DESENFOQUE DE MOVIMIENTO. Godot no lo trae de serie, así que se hace en pantalla: se toma la
# imagen ya dibujada y se promedian unas cuantas muestras EN LA DIRECCIÓN en la que se mueve la
# vista. Quieto, el nodo está oculto y no cuesta absolutamente nada.
# ---------------------------------------------------------------------------
func _build_mblur() -> void:
	mblur = ColorRect.new()
	mblur.name = "MotionBlur"
	mblur.set_anchors_preset(Control.PRESET_FULL_RECT)
	mblur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mblur.visible = false
	var sh := Shader.new()
	sh.code = _mips("""
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear;   // (sin mipmaps: solo se lee el nivel 0; 2026-10-10)
uniform vec2 dir = vec2(0.0);
void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb * 0.30;
	c += texture(screen, SCREEN_UV - dir * 0.20).rgb * 0.22;
	c += texture(screen, SCREEN_UV - dir * 0.40).rgb * 0.18;
	c += texture(screen, SCREEN_UV - dir * 0.60).rgb * 0.13;
	c += texture(screen, SCREEN_UV - dir * 0.80).rgb * 0.10;
	c += texture(screen, SCREEN_UV - dir * 1.00).rgb * 0.07;
	COLOR = vec4(c, 1.0);
}
""")
	var m := ShaderMaterial.new()
	m.shader = sh
	mblur.material = m
	root.add_child(mblur)
	# EL DESENFOQUE VA DEBAJO DE LA INTERFAZ. Lee la pantalla y se dibuja encima, asi que arrastraba
	# tambien la munición, la mira y los mensajes: al girar, las letras se estiraban o desaparecian.
	# Puesto el primero de la lista, emborrona el mundo y deja la interfaz nitida.
	root.move_child(mblur, 0)
	if is_instance_valid(fog_rect):
		root.move_child(fog_rect, 0)      # el vaho, aun mas abajo
	if is_instance_valid(dirt_layer):
		root.move_child(dirt_layer, 1)
	# el agua de la lente, otra vez encima de todo esto (ver _efectos_orden)
	_efectos_orden()
	_ui_centrar(root.scale.x < 0.999)


# ---------------------------------------------------------------------------
# DISTORSION POR CALOR sobre una explosion. Se hace en pantalla, no con una malla 3D: en una malla
# normal `hint_screen_texture` se lee antes de que exista la copia de pantalla y sale una BOLA
# BLANCA (primer intento). Aqui, como en el desenfoque de movimiento, la copia ya esta hecha.
# ---------------------------------------------------------------------------
var calor: ColorRect = null
var calor_copia: BackBufferCopy = null

func _build_calor() -> void:
	calor = ColorRect.new()
	calor.name = "Calor"
	calor.set_anchors_preset(Control.PRESET_FULL_RECT)
	calor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	calor.visible = false
	var sh := Shader.new()
	sh.code = _mips("""
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear;   // (sin mipmaps: solo se lee el nivel 0; 2026-10-10)
uniform vec2 centro = vec2(0.5);
uniform float radio = 0.2;
uniform float fuerza = 0.0;
uniform float tiempo = 0.0;
uniform float aspecto = 1.777;
void fragment() {
	vec2 d = SCREEN_UV - centro;
	d.x *= aspecto;                       // circulo de verdad, no elipse
	float dist = length(d) / max(radio, 0.001);
	// solo dentro de la burbuja, y sin borde duro
	float k = 1.0 - smoothstep(0.35, 1.0, dist);
	if (k <= 0.001) {
		COLOR = texture(screen, SCREEN_UV);
	} else {
		// ondas que suben: es aire caliente, sube y tiembla
		float o1 = sin(SCREEN_UV.y * 90.0 - tiempo * 9.0 + SCREEN_UV.x * 40.0);
		float o2 = cos(SCREEN_UV.x * 70.0 + tiempo * 7.0 - SCREEN_UV.y * 25.0);
		vec2 desvio = vec2(o1 * 0.6, o2 - 0.8) * fuerza * k * 0.012;
		COLOR = texture(screen, SCREEN_UV + desvio);
	}
}
""")
	var m := ShaderMaterial.new()
	m.shader = sh
	calor.material = m
	root.add_child(calor)
	calor_copia = _copia_para(calor, "CopiaCalor")
	_efectos_orden()
	_ui_centrar(root.scale.x < 0.999)


## `centro` y `radio` en UV de pantalla; `fuerza` de 0 a 1 (0 = apagado).
func set_heat(centro: Vector2, radio: float, fuerza: float) -> void:
	if fuerza <= 0.005:
		if calor:
			calor.visible = false
		return
	if calor == null:
		_build_calor()
	calor.visible = true
	var m := calor.material as ShaderMaterial
	m.set_shader_parameter("centro", centro)
	m.set_shader_parameter("radio", radio)
	m.set_shader_parameter("fuerza", fuerza)
	m.set_shader_parameter("tiempo", float(Time.get_ticks_msec()) * 0.001)
	m.set_shader_parameter("aspecto", root.size.x / maxf(root.size.y, 1.0))


## `d` es el desplazamiento de la vista en UV de pantalla (x horizontal, y vertical).
func set_motion_blur(d: Vector2) -> void:
	if Settings.motion_blur <= 0.01:
		if mblur:
			mblur.visible = false
		return
	if mblur == null:
		_build_mblur()
	if d.length() < 0.0015:
		mblur.visible = false
		return
	mblur.visible = true
	# tope: por muy rápido que gires, la estela no pasa de un 1,4 % de la pantalla
	var v: Vector2 = d.limit_length(0.014) * Settings.motion_blur
	(mblur.material as ShaderMaterial).set_shader_parameter("dir", v)


# ---------------------------------------------------------------------------
# SANGRE EN LA LENTE. Si le das a alguien a bocajarro, la cámara se salpica: gotas irregulares que
# resbalan un poco y se van secando. Las texturas se generan por código (nada de imágenes) y se
# reutiliza un anillo de nodos: cero asignaciones por disparo.
# ---------------------------------------------------------------------------
func _make_drop_texture(seed_v: int) -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var lobes: Array = [[Vector2(0.5, 0.5), rng.randf_range(0.22, 0.32)]]
	for i in rng.randi_range(3, 6):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.12, 0.34)
		lobes.append([Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * d, rng.randf_range(0.05, 0.13)])
	for y in n:
		for x in n:
			var uv := Vector2(float(x) / (n - 1), float(y) / (n - 1))
			var a := 0.0
			for L in lobes:
				var d: float = uv.distance_to(L[0])
				var r: float = L[1]
				if d < r:
					a = maxf(a, 1.0 - pow(d / r, 2.2))
			a *= 0.75 + 0.25 * sin(uv.x * 37.0 + seed_v) * cos(uv.y * 31.0 - seed_v)
			var rojo := Color(0.42, 0.02, 0.02, clampf(a, 0.0, 1.0) * 0.92)
			rojo.r = lerpf(0.55, 0.30, clampf(a, 0.0, 1.0))
			img.set_pixel(x, y, rojo)
	return ImageTexture.create_from_image(img)


func _build_blood_layer() -> void:
	blood_layer = Control.new()
	blood_layer.name = "BloodLens"
	blood_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	blood_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(blood_layer)
	for i in 4:
		_drop_tex.append(_make_drop_texture(1000 + i * 77))


# LA NIEVE NO VA AQUI. Se probo como capa de pantalla (el shader "Multilayer Snowfall") y quedaba
# como si te hubieran pegado los copos al cristal: no tienen profundidad, no pasan por detras de un
# edificio y no se posan. Los copos son PARTICULAS y viven en el mundo, junto a la lluvia (ver
# main.gd, `_make_nieve`). Aqui solo queda esta nota para que a nadie se le ocurra devolverla.

# --- ONDA EXPANSIVA -----------------------------------------------------------------------------
# El aire doblandose al reventar algo. Es un anillo que sale del punto del estallido y se abre: por
# dentro y por fuera no toca nada, solo empuja la imagen justo en el filo.
var onda_rect: ColorRect = null
var onda_copia: BackBufferCopy = null
var _onda_t := 0.0
var _onda_dur := 0.0
var _onda_fuerza := 0.0


# --- OJO DE PEZ ---------------------------------------------------------------------------------
# La lente curva de camara de casco. Va MUY floja a proposito: entera marea y, peor, te quita
# punteria, porque el centro de la pantalla deja de ser recto y lo que apuntas no esta donde lo ves.
# A 0.10 se nota que los bordes respiran al girar la camara y poco mas, que es justo lo que se pidio.
var ojo_rect: ColorRect = null
## --pantallamips: los efectos de pantalla vuelven a pedir la copia con mipmaps (como antes del 2026-10-10)
static var _pantalla_mips: bool = "--pantallamips" in OS.get_cmdline_user_args()
static func _mips(code: String) -> String:
	return code.replace("hint_screen_texture, filter_linear;", "hint_screen_texture, filter_linear_mipmap;") if _pantalla_mips else code
var ojo_copia: BackBufferCopy = null
## Los dos materiales de la capa de lente: la lente COMPLETA (lee la pantalla) y la viñeta sola (no la lee).
## Todos los ajustes van a `_ojo_mat`; `_lente_visible` decide cual se pone.
var _ojo_mat: ShaderMaterial = null
var _vineta_mat: ShaderMaterial = null
var ojo_pez := true
var grano_sensor := true
const OJO_FUERZA := 0.10
const OJO_ABERRA := 0.55      ## separacion de color en el borde
const OJO_GRANO := 0.45       ## ruido de sensor
# CAMARA DE CUERPO. La misma pasada, con todo subido y con lo que solo tiene sentido aqui: vineta,
# grado lavado, realce y obturador de barrido. Estos numeros son el "look", y estan puestos para que
# se note sin llegar a estorbar: el gran angular ensancha pero no marea, y el grado lava los negros
# sin que dejes de ver lo que hay en la sombra, que es donde suele estar el que te dispara.
const BC_FUERZA := 0.30
const BC_ABERRA := 1.0
const BC_GRANO := 0.85
const BC_VINETA := 0.85     ## subida: con la bodycam las esquinas se cierran de verdad
const BC_DESATURA := 0.28
const BC_NEGROS := 0.16
const BC_NITIDEZ := 0.55


func _build_ojo() -> void:
	ojo_rect = ColorRect.new()
	ojo_rect.name = "OjoDePez"
	ojo_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	ojo_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/ojo_pez.gdshader")
	m.set_shader_parameter("fuerza", OJO_FUERZA if ojo_pez else 0.0)
	m.set_shader_parameter("aberra", OJO_ABERRA if grano_sensor else 0.0)
	m.set_shader_parameter("grano", OJO_GRANO if grano_sensor else 0.0)
	ojo_rect.material = m
	_ojo_mat = m
	_vineta_mat = ShaderMaterial.new()
	_vineta_mat.shader = load("res://shaders/vineta.gdshader")
	# LA COPIA DE PANTALLA, justo debajo. Sin esto la interfaz DESAPARECE al mover la camara, y el
	# motivo es de los que no se adivinan: el desenfoque de movimiento tambien lee la pantalla y vive
	# en el fondo de la lista, asi que cuando se enciende -o sea, solo al girar- la copia de pantalla
	# del lienzo se toma ALLI, antes de que se dibuje nada de la interfaz. El ojo de pez, que esta
	# arriba, acababa releyendo esa copia vieja y pintandola encima: se comia el HUD entero.
	# Reproducido y arreglado en el banco (--ojofoto): con un segundo shader de pantalla abajo la
	# interfaz se va; con esta copia delante, vuelve.
	ojo_copia = BackBufferCopy.new()
	ojo_copia.name = "CopiaOjo"
	ojo_copia.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	root.add_child(ojo_copia)
	root.add_child(ojo_rect)
	_ojo_orden()
	_ojo_aspecto()
	get_viewport().size_changed.connect(_ojo_aspecto)


## DONDE VA LA CAPA. Encima de TODA la interfaz, para que la mira, los numeros y los arcos de dano
## se curven con el resto: si va debajo, la pantalla se dobla pero la interfaz se queda plana encima
## y se nota que son dos cosas pegadas.
##
## La excepcion son los botones tactiles, que van por encima y sin tocar. No es por gusto: un boton
## dibujado curvado sigue RECIBIENDO el dedo donde esta de verdad, no donde lo ves, asi que curvarlos
## seria mover el boton de sitio para el ojo y dejarlo quieto para el dedo. En el borde de la
## pantalla, que es justo donde estan, es donde mas se desplazaria.
##
## Se comprueba cada cuadro porque los paneles (marcador, matanzas, menu) se crean cuando hacen
## falta, y uno creado despues se colaria por encima. Comparar dos indices no cuesta nada; solo se
## mueve algo cuando de verdad esta descolocado.
## APAGADO DE VERDAD. Poner las fuerzas a cero deja el shader sin hacer nada, PERO la pasada a
## pantalla completa y la copia de pantalla se siguen pagando igual: en una integrada eso es de lo
## mas caro que hay y no se notaba porque el efecto seguia "apagado". Con los dos interruptores en
## OFF se esconden los dos nodos y entonces si que no cuesta nada.
## Lo que manda el menu grafico: 0 apagada, 1 sutil, 2 marcada. Apagada de verdad -el nodo se
## esconde- porque una pasada a pantalla completa "sin efecto" cuesta exactamente lo mismo que con
## efecto: se paga la copia de pantalla y el relleno igual.
## CAMARA DE CUERPO: 0 apagada, 1 sutil, 2 completa. Manda por encima de la lente normal porque es
## la misma pasada; encenderla sube el gran angular, la aberracion y el grano, y ademas enciende lo
## que solo existe aqui.
var bodycam := 0
var lente_nivel := 1        ## el nivel de "Lente de camara" que hay puesto ahora
var vineta_nivel := 1       ## la vineta va aparte: se puede tener sin nada mas
var _lente_prev := -1       ## el que habia ANTES de encender la bodycam, para devolverlo
var _mira_px := Vector2.ZERO  ## desvio de la mira respecto al centro (lo mueve la camara de cuerpo)


func set_bodycam(nivel: int) -> void:
	var antes := bodycam
	bodycam = nivel
	if nivel <= 0:
		# SE APAGA Y SE DEVUELVE LO QUE HABIA. Nada de dejarlo en un valor fijo: si tenias la lente
		# en Sutil, vuelve a Sutil, y si la tenias apagada se queda apagada.
		if ojo_rect:
			var m0 := _ojo_mat
			for u in ["vineta", "desatura", "negros", "nitidez", "obturador"]:
				m0.set_shader_parameter(u, 0.0)
		set_mira_desvio(Vector2.ZERO)   # sin bodycam la mira vuelve al centro exacto
		_hud_minimo(false)
		if _lente_prev >= 0:
			set_lente(_lente_prev)
			_lente_prev = -1
		else:
			set_lente(lente_nivel)
		_aplicar_vineta()
		return
	# SE ENCIENDE: la lente normal se APARTA, no se suma. Las dos curvan la imagen con el mismo
	# shader, asi que encendidas a la vez el gran angular saldria del doble de ancho y ya no seria el
	# efecto de una camara de cuerpo, seria un ojo de pez de feria. Se guarda lo que habia para
	# poder devolverlo tal cual al apagarla.
	if antes <= 0:
		_lente_prev = lente_nivel
	if ojo_rect == null:
		_build_ojo()
	ojo_pez = true
	grano_sensor = true
	var f: float = 0.55 if nivel == 1 else 1.0
	var m := _ojo_mat
	m.set_shader_parameter("fuerza", BC_FUERZA * f * bc_mult("bc_curva"))
	m.set_shader_parameter("aberra", BC_ABERRA * f * bc_mult("bc_aberra"))
	m.set_shader_parameter("grano", BC_GRANO * f * bc_mult("bc_grano"))
	m.set_shader_parameter("desatura", BC_DESATURA * f * bc_mult("bc_lavado"))
	m.set_shader_parameter("negros", BC_NEGROS * f * bc_mult("bc_negros"))
	m.set_shader_parameter("nitidez", BC_NITIDEZ * f * bc_mult("bc_nitidez"))
	_ojo_orden()   # el ajuste "afecta a la interfaz" cambia en que capa va: hay que recolocarla
	if rec_box:
		rec_box.visible = bc_nivel("bc_rec") > 0
	_aplicar_vineta()
	_hud_minimo(true)
	_lente_visible()


## Rota el nivel y mueve tambien la camara del jugador, que es la otra mitad del efecto: sin ella
## solo cambia la imagen y se pierde justo lo que mas se nota.
func _ciclar_bodycam() -> void:
	var n: int = (bodycam + 1) % 3
	if main and main.has_method("set_bodycam"):
		main.set_bodycam(n)      # imagen, camara y campo de vision, todo por el mismo sitio
	else:
		set_bodycam(n)
	flash_message("BODYCAM: %s" % ["OFF", "SUTIL", "COMPLETA"][n])


# --- ROTULO DE GRABACION ------------------------------------------------------------------------
# El punto rojo, el REC y la fecha con la hora, abajo. Va DEBAJO de la capa de lente a proposito:
# en una camara de verdad ese rotulo esta quemado en el video, asi que tiene que curvarse y coger el
# grano con todo lo demas. Puesto por encima se vería plano y se notaria pegado.
var rec_box: Control = null


func _build_rec() -> void:
	rec_box = Control.new()
	rec_box.name = "RotuloREC"
	rec_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	rec_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var punto := ColorRect.new()
	punto.name = "Punto"
	punto.color = Color(0.92, 0.12, 0.10)
	punto.size = Vector2(13, 13)
	punto.position = Vector2(40, 34)
	rec_box.add_child(punto)
	var lb := _label(19)
	lb.name = "Rec"
	lb.text = "REC"
	lb.position = Vector2(62, 28)
	rec_box.add_child(lb)
	var reloj := _label(17)
	reloj.name = "Reloj"
	reloj.position = Vector2(40, 56)
	rec_box.add_child(reloj)
	root.add_child(rec_box)
	root.move_child(rec_box, 1)     # debajo de la lente, encima del mundo


## Se llama cada cuadro mientras la bodycam esta puesta. El punto rojo parpadea a un segundo, que es
## el ritmo al que parpadean de verdad.
func _update_rec(_dt: float) -> void:
	if rec_box == null or not rec_box.visible:
		return
	var t: Dictionary = Time.get_datetime_dict_from_system()
	(rec_box.get_node("Reloj") as Label).text = "%04d-%02d-%02d  %02d:%02d:%02d" % [
		t.year, t.month, t.day, t.hour, t.minute, t.second]
	var enc: bool = fmod(float(Time.get_ticks_msec()) * 0.001, 1.4) < 0.9
	(rec_box.get_node("Punto") as ColorRect).visible = enc
	(rec_box.get_node("Rec") as Label).visible = enc


## INTERFAZ AL MINIMO. Una camara de cuerpo no dibuja un contador de balas encima de lo que graba.
## Se esconden, no se borran: al apagar la bodycam vuelven solas.
##
## LA MIRA SE QUEDA. Estuvo escondida un rato, cuando el arma disparaba por donde apuntaba ella y la
## mira habria sido mentira. Ahora la bala sale por el centro exacto, asi que quitar la mira solo
## seria esconderte el dato que necesitas para jugar. Realismo que te hace jugar peor no es realismo,
## es una molestia.
func _hud_minimo(on: bool) -> void:
	# EL ROTULO "REC" SE QUITO. Quedaba arriba a la izquierda y molestaba mas de lo que aportaba: en
	# una bodycam de verdad esta ahi, pero en una pantalla de juego es una cosa mas tapandote la
	# esquina y sin decirte nada util. El constructor sigue en el archivo por si algun dia se quiere.
	if rec_box:
		rec_box.visible = false
	_ui_centrar(on)
	# LA BARRA DE ARMAS NO SE TOCA. Estaba en esta lista y fue un error grave: son BOTONES, no adorno,
	# y en Android es la unica forma de cambiar de arma. Con la camara de cuerpo puesta por defecto,
	# el movil se quedaba sin selector de armas.
	#
	# La regla que faltaba: el "HUD minimo" puede esconder lo que INFORMA, nunca lo que se PULSA.
	# LA MIRA GUIA SE VA, EL MARCADOR DE ACIERTO SE QUEDA. Una camara de cuerpo no dibuja una cruz
	# encima de lo que graba, y el aviso de impacto ya te dice si le has dado: con eso alcanza y la
	# pantalla queda limpia. Apuntar pasa a ser a ojo, que es la idea.
	for n in [ammo_label, weapon_label, crosshair]:
		if n and is_instance_valid(n):
			n.visible = not on


## LA INTERFAZ, METIDA HACIA EL CENTRO. La curvatura del gran angular agranda la imagen y empuja los
## bordes fuera de la pantalla; con la bodycam al maximo eso se comia las esquinas del HUD. La
## solucion buena no es aplanar la curva -eso la hacia parecer un globo- sino apartar la interfaz del
## filo. Se encoge el contenedor entero un 10 %.
##
## Y hay que DESENCOGER dos cosas: la capa de lente tiene que seguir cubriendo la pantalla completa o
## se veria un marco sin efecto alrededor, y los botones tactiles tienen que quedarse donde el dedo
## los espera. Las dos se contra-escalan sobre su propio centro, asi que vuelven a su tamano real.
func _ui_centrar(on: bool) -> void:
	if root == null:
		return
	var s: float = 0.90 if on else 1.0
	var tam: Vector2 = get_viewport().get_visible_rect().size
	root.pivot_offset = tam * 0.5
	root.scale = Vector2(s, s)
	var inv: float = 1.0 / s
	# la lente tiene que cubrir la pantalla entera, y lo que se pulsa tiene que quedarse donde el
	# dedo lo espera: los tres se desencogen sobre su propio centro
	# `mobile` ya no esta aqui: cuelga de la capa y no le llega la escala, asi que no hay nada que
	# deshacerle. Justo por eso se saco.
	# EL AGUA Y EL DESENFOQUE TAMBIEN. Son efectos de la camara, no de la interfaz: con la interfaz
	# encogida hacia el centro, las gotas quedaban metidas en un recuadro con un marco seco alrededor.
	# (2026-10-10, bug: "con la bodycam la viñeta roja de vida baja es un cuadrado que no llena la pantalla"): la viñeta
	# de vida, el destello de daño, la sangre y la tierra en la lente y la niebla de pantalla, igual: son de la camara
	for n in [ojo_rect, weapon_bar, lluvia_rect, mblur, aberration, calor, onda_rect,
			get("vignette"), get("damage_rect"), blood_layer, get("dirt_layer"), get("fog_rect")]:
		if n and is_instance_valid(n):
			(n as Control).pivot_offset = tam * 0.5
			(n as Control).scale = Vector2(inv, inv)


## Mueve la cruz de puntería los pixeles que haga falta para que caiga donde de verdad va la bala.
## Con la camara de cuerpo la vista se bambolea y la punteria no, asi que la cruz deja de estar en el
## centro exacto de la pantalla: eso es correcto, es la vista la que se ha movido, no tu mano.
func set_mira_desvio(px: Vector2) -> void:
	if crosshair == null or not is_instance_valid(crosshair):
		return
	# CENTRO MAS DESVIO. Antes era `crosshair.position = px` a secas, y era un error de bulto: `px` es
	# el desvio respecto al centro, no una posicion. Asignandolo tal cual, la mira se iba a unos pocos
	# pixeles de la ESQUINA superior izquierda. Lo delato el marcador de acierto, que se quedaba en el
	# medio -donde tenia que estar- y por eso no coincidia con la mira.
	_mira_px = px
	var cen: Vector2 = root.size * 0.5 + px
	crosshair.position = cen
	# el marcador de acierto va CON la mira: confirma un impacto en el punto al que apuntaste, asi que
	# dejarlo en el centro mientras la mira esta desviada es senalar a otro sitio
	if hit_marker and is_instance_valid(hit_marker):
		hit_marker.position = cen


## La cizalla del obturador. La manda el jugador cada cuadro segun lo rapido que este girando.
## `set_obturador` lo llama el jugador con la velocidad de giro; aqui se escala con su mando.
func set_obturador(v: float) -> void:
	if ojo_rect == null or bodycam <= 0:
		return
	_ojo_mat.set_shader_parameter("obturador", v * bc_mult("bc_barrido"))


func set_lente(nivel: int) -> void:
	if bodycam > 0:
		# manda la camara de cuerpo, que usa la misma pasada. Se apunta igual, para poder volver a
		# este valor cuando se apague.
		lente_nivel = nivel
		_lente_prev = nivel
		return
	lente_nivel = nivel
	var on: bool = nivel > 0
	ojo_pez = on
	grano_sensor = on
	if ojo_rect == null:
		if not on:
			return          # ni se molesta en montarla
		_build_ojo()
	var mult: float = 2.0 if nivel >= 2 else 1.0
	var m := _ojo_mat
	m.set_shader_parameter("fuerza", OJO_FUERZA * mult if on else 0.0)
	m.set_shader_parameter("aberra", OJO_ABERRA * mult if on else 0.0)
	m.set_shader_parameter("grano", OJO_GRANO * mult if on else 0.0)
	_aplicar_vineta()
	_lente_visible()


## LA VINETA, DECIDIDA EN UN SOLO SITIO. La escriben tres caminos distintos (su propia opcion, la
## lente y la camara de cuerpo) sobre el mismo uniform: si cada uno la pusiera por su cuenta, el
## ultimo en hablar ganaria y encender la bodycam te borraria la vineta que tenias, o al reves.
## LOS MANDOS FINOS DE LA BODYCAM. Cada opcion es un MULTIPLICADOR sobre el aspecto base, con
## "Normal" (indice 2) valiendo 1,0: asi se puede subir o bajar cada pieza sin que el ajuste pierda
## sentido si algun dia se retoca ese aspecto base. Ver Settings.GFX_OPTIONS.
const BC_ESCALA := [0.0, 0.5, 1.0, 1.5, 2.1, 3.0]

func bc_nivel(clave: String) -> int:
	# la calidad la lleva main; sin el (menus, pruebas) se usa ULTRA, que es el ajuste de fabrica
	var q: int = int(main.quality) if (main != null and "quality" in main) else 3
	return Settings.gfx_value(clave, q)

func bc_mult(clave: String) -> float:
	return BC_ESCALA[clampi(bc_nivel(clave), 0, BC_ESCALA.size() - 1)]


func _aplicar_vineta() -> void:
	if ojo_rect == null:
		return
	var v: float = [0.0, 0.45, 0.75][clampi(vineta_nivel, 0, 2)]
	if bodycam > 0:
		v = maxf(v, BC_VINETA * (0.55 if bodycam == 1 else 1.0) * bc_mult("bc_vineta"))
	_ojo_mat.set_shader_parameter("vineta", v)
	if _vineta_mat:
		_vineta_mat.set_shader_parameter("vineta", v)


func set_vineta(nivel: int) -> void:
	vineta_nivel = nivel
	if ojo_rect == null:
		if nivel <= 0:
			return
		_build_ojo()
	_aplicar_vineta()
	_lente_visible()


static var _lente_movil: bool = "--lentemovil" in OS.get_cmdline_user_args()

func _lente_visible() -> void:
	# la vineta sola ya justifica dibujar la capa: es lo unico que puede quedar encendido con todo
	# lo demas apagado
	#
	# CON LA VIÑETA SOLA, LA CAPA BARATA (vineta.gdshader): una capa negra por encima, sin leer la pantalla ni
	# copiarla. La lente completa -y su copia del lienzo entero a resolucion nativa- solo cuando hay algo que
	# de verdad repinta la imagen. En una GPU de movil esa copia es de lo mas caro del cuadro.
	var completa: bool = ojo_pez or grano_sensor or bodycam > 0
	var hace_falta: bool = completa or vineta_nivel > 0 or bodycam > 0
	# EN EL MOVIL, NUNCA LA LENTE COMPLETA (2026-10-13, bug: "en un S9 va re lento, GPU 44 ms"; pedido: "que los efectos
	# de pantalla se hagan una vez y queden asi"): copiaba la pantalla entera a resolucion nativa y la releia hasta 8 veces
	# por pixel CADA fotograma. Queda la capa barata (la viñeta, sin leer la pantalla); se pierde la curvatura. --lentemovil
	# = la completa tambien en el movil.
	if completa and Settings.is_mobile() and not _lente_movil:
		completa = false
	if ojo_rect and is_instance_valid(ojo_rect):
		ojo_rect.visible = hace_falta
		var mat: ShaderMaterial = _ojo_mat if completa or _vineta_mat == null else _vineta_mat
		if ojo_rect.material != mat:
			ojo_rect.material = mat
	if ojo_copia and is_instance_valid(ojo_copia):
		ojo_copia.visible = completa


func _ojo_orden() -> void:
	if ojo_rect == null or ojo_rect.get_parent() != root:
		return
	# LA INTERFAZ, FUERA DE LA LENTE si asi se ha pedido (Graficos -> BODYCAM -> "Afecta a la
	# interfaz"). La capa va ENCIMA de todo para que la mira y los numeros se curven con la imagen,
	# que es lo que la hace parecer un video; pero eso tambien les mete grano, aberracion y viñeta
	# encima, y en un movil los textos pequenos se leen peor. Bajandola al fondo -justo sobre el
	# mundo 3D y por debajo de todo el HUD- se curva el mundo y la interfaz se queda plana y limpia.
	if bc_nivel("bc_ui") <= 0:
		# JUSTO ENCIMA DE LOS EFECTOS DE PANTALLA Y DEBAJO DEL HUD. Nada de mandarla al indice 0 a
		# pelo: ahi abajo ya viven el desenfoque, la lluvia, la sangre y el calor, y `_efectos_orden`
		# los recoloca cada cuadro, asi que las dos funciones se pelearian por el mismo sitio y la
		# capa parpadearia. Se busca el mas alto de ellos y la lente se pone encima: el mundo y sus
		# efectos se curvan juntos -que es lo correcto, son parte de la imagen- y todo lo que venga
		# despues, que es el HUD entero, se queda plano.
		var suelo := -1
		for n in [mblur, fog_rect, dirt_layer, onda_rect, calor, lluvia_rect, aberration]:
			if n != null and is_instance_valid(n) and n.get_parent() == root:
				suelo = maxi(suelo, (n as Node).get_index())
		var i_copia: int = suelo + 1
		if ojo_copia and is_instance_valid(ojo_copia):
			if ojo_copia.get_index() != i_copia:
				root.move_child(ojo_copia, i_copia)
			if ojo_rect.get_index() != i_copia + 1:
				root.move_child(ojo_rect, i_copia + 1)
		elif ojo_rect.get_index() != i_copia:
			root.move_child(ojo_rect, i_copia)
		return
	# de abajo arriba:  ...todo lo demas... | copia de pantalla | ojo de pez | botones tactiles
	var n: int = root.get_child_count()
	# ENCIMA DE LA LENTE VA TODO LO QUE SE PULSA, no solo los botones tactiles. La barra de armas
	# estaba debajo, y ahi se veia el fallo: la lente lee la pantalla y la repinta, y al aparecer el
	# desenfoque de movimiento -o sea al mover la camara- la copia que releia no siempre traia la
	# barra ya dibujada. Resultado: los botones de armas se iban y volvian al girar.
	#
	# Poniendolos arriba deja de depender de en que orden se copie la pantalla: no los toca nadie.
	var arriba: Array = []
	# (2026-10-10, bug: "los botones de habilidad no detectan bien el click, tengo que darle al lado"): los botones de
	# HABILIDAD y BLINDAJE tambien se pulsan. Debajo de la lente se dibujaban curvados -corridos hacia fuera- y el toque
	# seguia donde estaban de verdad.
	for c in [weapon_bar, boton_habilidad, boton_blindaje]:
		if c != null and is_instance_valid(c) and c.get_parent() == root:
			arriba.append(c)
	# CON SUELO EN 1. En Android `arriba` tiene DOS nodos (botones tactiles y barra de armas), asi que
	# `tope` baja dos posiciones mas que en PC. Si el HUD todavia tiene pocos hijos -y `_ojo_orden`
	# corre desde el primer cuadro, mientras carga- `tope - 1` se iba a negativo, y un indice negativo
	# en `move_child` cuenta desde el FINAL: la copia de pantalla acababa por encima de la lente y el
	# orden entero quedaba del reves. En PC no pasaba porque `arriba` esta vacio.
	var tope: int = maxi(n - 1 - arriba.size(), 1)
	var bien: bool = ojo_rect.get_index() == tope
	if ojo_copia and is_instance_valid(ojo_copia) and ojo_copia.get_index() != tope - 1:
		bien = false
	for i in arriba.size():
		if (arriba[i] as Node).get_index() != tope + 1 + i:
			bien = false
	if bien:
		return
	# se mueven los tres de abajo arriba: cada `move_child` corre a los de en medio, asi que hacerlo
	# en otro orden deja al siguiente descolocado
	if ojo_copia and is_instance_valid(ojo_copia):
		root.move_child(ojo_copia, tope - 1)
	root.move_child(ojo_rect, tope)
	for i in arriba.size():
		root.move_child(arriba[i], tope + 1 + i)


## La curva tiene que ser redonda en PANTALLA, no en coordenadas de textura: sin esto, en una
## pantalla ancha el efecto sale ovalado y se nota mas arriba y abajo que a los lados.
func _ojo_aspecto() -> void:
	if ojo_rect == null:
		return
	var t: Vector2 = get_viewport().get_visible_rect().size
	_ojo_mat.set_shader_parameter("aspect", t.x / maxf(t.y, 1.0))
	if _vineta_mat:
		_vineta_mat.set_shader_parameter("aspect", t.x / maxf(t.y, 1.0))


func set_ojo_pez(on: bool) -> void:
	if bodycam > 0:
		# con la camara de cuerpo puesta estos dos no mandan: comparten los mismos uniforms y
		# tocarlos le romperia el ajuste. Se avisa en vez de hacer algo a medias y en silencio.
		flash_message("LO LLEVA LA BODYCAM")
		return
	ojo_pez = on
	if ojo_rect == null:
		_build_ojo()
	_ojo_mat.set_shader_parameter("fuerza", OJO_FUERZA if on else 0.0)
	_lente_visible()
	flash_message("OJO DE PEZ: %s" % ("ON" if on else "OFF"))


## El grano y la separacion de color van juntos en el mismo interruptor porque son la misma cosa:
## como se porta el cristal y como se porta el sensor. Y comparten pasada, asi que apagar uno solo no
## ahorraria nada.
func set_grano(on: bool) -> void:
	if bodycam > 0:
		flash_message("LO LLEVA LA BODYCAM")
		return
	grano_sensor = on
	if ojo_rect == null:
		_build_ojo()
	var m := _ojo_mat
	m.set_shader_parameter("aberra", OJO_ABERRA if on else 0.0)
	m.set_shader_parameter("grano", OJO_GRANO if on else 0.0)
	_lente_visible()
	flash_message("GRANO Y COLOR: %s" % ("ON" if on else "OFF"))


func _build_onda() -> void:
	onda_rect = ColorRect.new()
	onda_rect.name = "OndaExpansiva"
	onda_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	onda_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	onda_rect.visible = false
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/onda.gdshader")
	onda_rect.material = m
	root.add_child(onda_rect)
	onda_copia = _copia_para(onda_rect, "CopiaOnda")
	_efectos_orden()                   # sobre el mundo, debajo de la interfaz
	_ui_centrar(root.scale.x < 0.999)


## `centro` en coordenadas de pantalla (0..1) y `fuerza` de 0 a 1. Lo llama effects.gd al estallar.
func onda_expansiva(centro: Vector2, fuerza: float) -> void:
	if fuerza <= 0.01:
		return
	if onda_rect == null:
		_build_onda()
	var m := onda_rect.material as ShaderMaterial
	m.set_shader_parameter("center", centro)
	# LEVE a proposito: un misil no te tiene que dejar la pantalla como una lavadora. Lo que se
	# quiere es notar el golpe de aire, no marearse.
	m.set_shader_parameter("strength", 0.018 + 0.020 * fuerza)
	m.set_shader_parameter("aberration", 0.30)
	m.set_shader_parameter("width", 0.030)
	m.set_shader_parameter("feather", 0.110)
	_onda_dur = 0.45 + 0.25 * fuerza
	_onda_t = _onda_dur
	_onda_fuerza = fuerza
	onda_rect.visible = true


func _update_onda(dt: float) -> void:
	if onda_rect == null or not onda_rect.visible:
		return
	_onda_t = maxf(0.0, _onda_t - dt)
	var k: float = 1.0 - _onda_t / maxf(_onda_dur, 0.01)
	var m := onda_rect.material as ShaderMaterial
	# el anillo se abre deprisa al principio y se va frenando, como una onda de verdad
	m.set_shader_parameter("radius", sqrt(k) * (0.42 + 0.28 * _onda_fuerza))
	# y se apaga hacia el final para que no se corte de golpe
	m.set_shader_parameter("fuerza_total", (1.0 - k * k) * _onda_fuerza)
	if _onda_t <= 0.0:
		onda_rect.visible = false


# --- AGUA EN LA LENTE ---------------------------------------------------------------------------
# Las gotas NO son dibujos pegados en la pantalla: son lentes. El shader lee la imagen y la vuelve a
# leer desplazada segun la forma de cada gota, que es lo que hace el agua de verdad: desviar la luz
# que la atraviesa. Por eso a traves de una gota se ve el mundo movido, y por eso funciona sobre
# cualquier fondo sin pintar nada.
# La primera version eran texturas de gota resbalando y se notaba a la legua que eran pegatinas.
var lluvia_rect: ColorRect = null
## Copia de pantalla justo antes del agua: ver _efectos_orden.
var lluvia_copia: BackBufferCopy = null
var _lluvia_k := 0.0


var _lente_ligera := false

func _build_lluvia_lente() -> void:
	lluvia_rect = ColorRect.new()
	lluvia_rect.name = "AguaLente"
	lluvia_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	lluvia_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lluvia_rect.visible = false
	var m := ShaderMaterial.new()
	# (--lentemips: el de antes, con la pantalla con mipmaps: banco de la lluvia, 2026-10-05)
	# EN EL MOVIL, LA LIGERA: las mismas gotas sin copiar la pantalla (lluvia_lente_ligera.gdshader). --lenteligera en el PC
	_lente_ligera = (Settings.is_mobile() or "--lenteligera" in OS.get_cmdline_user_args()) and not ("--lentecompleta" in OS.get_cmdline_user_args())
	m.shader = load("res://shaders/lluvia_lente_mips.gdshader" if "--lentemips" in OS.get_cmdline_user_args() else ("res://shaders/lluvia_lente_ligera.gdshader" if _lente_ligera else "res://shaders/lluvia_lente.gdshader"))
	# ESTILO "CHAPARRON": muchas gotas, cristal bien mojado y el mundo tirando a frio detras.
	m.set_shader_parameter("azul", 0.8)
	m.set_shader_parameter("fuerza", 1.0)
	m.set_shader_parameter("desenfoque", 5.0)
	m.set_shader_parameter("velocidad", 0.20)
	# EN MOVIL, UNA SOLA CAPA DE GOTAS. Es lo que mas cuesta de todo el efecto y, a pantalla completa
	# y con la resolucion de un telefono, la segunda capa casi no se distingue.
	m.set_shader_parameter("capas", 1 if Settings.is_mobile() else 2)
	if "--lentesingotas" in OS.get_cmdline_user_args():
		m.set_shader_parameter("diag_sin_gotas", 1)        # banco de la lluvia: solo la copia de la pantalla
	lluvia_rect.material = m
	lluvia_copia = BackBufferCopy.new()
	lluvia_copia.name = "CopiaLluvia"
	lluvia_copia.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	lluvia_copia.visible = false
	root.add_child(lluvia_copia)
	root.add_child(lluvia_rect)
	# la copia de pantalla solo cuesta mientras hay agua que dibujar
	lluvia_rect.visibility_changed.connect(func() -> void:
		if is_instance_valid(lluvia_copia):
			lluvia_copia.visible = lluvia_rect.visible and not _lente_ligera)   # la ligera no lee la pantalla: sin copia
	_efectos_orden()
	# si la camara de cuerpo ya estaba puesta, el agua nace a pantalla completa desde el principio
	_ui_centrar(root.scale.x < 0.999)


## EL AGUA VA JUSTO ENCIMA DEL DESENFOQUE, CON SU PROPIA COPIA DE PANTALLA DELANTE.
##
## Las dos cosas leen la pantalla y la vuelven a pintar, y Godot solo hace UNA copia automatica de
## la pantalla por lienzo: la toma al llegar al primero que la pide. El segundo relee esa misma copia
## vieja y la pinta encima, borrando lo que hubiera hecho el primero. Por eso al mover la camara
## -que es cuando aparece el desenfoque- las gotas desaparecian: una capa pisaba a la otra con una
## foto de antes. Es el mismo fallo que ya se comio la interfaz con el ojo de pez (ver ojo_copia).
##
## Con una copia EXPLICITA justo antes del agua, esta lee la imagen ya desenfocada y dibuja las
## gotas encima. Queda debajo de la interfaz: el agua moja el mundo, no la municion ni la mira.
##
## Hay que llamarla tambien cuando se crea el desenfoque, porque se crea tarde (al mover la camara
## por primera vez) y se coloca abajo del todo, desordenando lo que ya habia.
## TODOS LOS EFECTOS QUE LEEN LA PANTALLA, EN FILA Y DEBAJO DE LA INTERFAZ, cada uno con su copia.
##
## Empezo con la lluvia, pero el fallo era de todos: Godot hace UNA copia automatica de la pantalla por
## lienzo, al llegar al primero que la pide, y los siguientes releen esa foto vieja y la pintan encima.
## La aberracion -la separacion de colores al recibir un tiro- se dibujaba ENCIMA de la barra de vida:
## en cuanto habia otro efecto de pantalla por debajo (el desenfoque al girar), repintaba una imagen de
## antes de que existiera la barra, y la barra desaparecia mientras duraba el golpe. El calor de las
## explosiones iba aun peor, encima de TODA la interfaz.
##
## Orden, de abajo arriba: [vaho, desenfoque, tierra] | onda | calor | agua | aberracion | interfaz...
## Cada efecto lleva justo delante su propia copia, que solo trabaja mientras el efecto se ve.
func _efectos_orden() -> void:
	if root == null:
		return
	var ref: Node = null
	for n in [mblur, fog_rect, dirt_layer]:
		if n != null and is_instance_valid(n) and n.get_parent() == root:
			if ref == null or n.get_index() > ref.get_index():
				ref = n
	for par in [[onda_copia, onda_rect], [calor_copia, calor], [lluvia_copia, lluvia_rect], [aberration_copia, aberration]]:
		var copia = par[0]
		var rect = par[1]
		if copia == null or rect == null or not is_instance_valid(copia) or not is_instance_valid(rect):
			continue
		if ref == null:
			root.move_child(copia, 0)
		else:
			_poner_encima(copia, ref)
		_poner_encima(rect, copia)
		ref = rect


## Copia de pantalla para un efecto: se enciende y se apaga con el, para no copiar la pantalla entera
## cada cuadro cuando el efecto no se esta viendo.
func _copia_para(rect: CanvasItem, nombre: String) -> BackBufferCopy:
	var c := BackBufferCopy.new()
	c.name = nombre
	c.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	c.visible = rect.visible
	root.add_child(c)
	rect.visibility_changed.connect(func() -> void:
		if is_instance_valid(c):
			c.visible = rect.visible)
	return c


## Deja `nodo` justo encima de `ref`. `move_child` quita y vuelve a meter: si el nodo estaba por
## debajo, al sacarlo `ref` baja un puesto, y hay que contarlo o queda uno de por medio.
func _poner_encima(nodo: Node, ref: Node) -> void:
	var r: int = ref.get_index()
	root.move_child(nodo, r if nodo.get_index() < r else r + 1)


## `k` de 0 a 1: cuanta agua te esta entrando en la lente. Lo llama main.gd segun si llueve, si
## estas a cielo abierto y cuanto levantas la vista.
func lens_rain(k: float, dt: float) -> void:
	if _diag_sin_lente_lluvia or sin_lente_lluvia:
		k = 0.0                 # --sinlentelluvia: banco de la lluvia (que cuesta cada pieza)
	if lluvia_rect == null:
		if k <= 0.001:
			return
		_build_lluvia_lente()
	# EL CRISTAL SE MOJA DE A POCO. A 1,6 tardaba medio segundo y aparecian todas las gotas de
	# golpe, como si te hubieran tirado un cubo. A 0,28 tarda unos tres segundos y medio, y como el
	# shader va soltando primero las salpicaduras quietas y luego las que caen, se ve llenarse:
	# primero cuatro gotas sueltas, luego los regueros. Secarse tarda el doble.
	var sube: float = 0.28 if k > _lluvia_k else 0.14
	_lluvia_k = move_toward(_lluvia_k, clampf(k, 0.0, 1.0), dt * sube)
	lluvia_rect.visible = _lluvia_k > 0.004
	if lluvia_rect.visible:
		var m := lluvia_rect.material as ShaderMaterial
		m.set_shader_parameter("cantidad", _lluvia_k)


## LAS GOTAS SOLO EN EL CRISTAL DEL ESCUDO (2026-10-28): `q` = sus 4 esquinas en pixeles de pantalla; vacio = toda la lente
func lente_recorte(q: PackedVector2Array) -> void:
	if lluvia_rect == null:
		return
	var m := lluvia_rect.material as ShaderMaterial
	if q.size() != 4:
		m.set_shader_parameter("con_recorte", 0)
		return
	var tam := lluvia_rect.get_viewport_rect().size
	m.set_shader_parameter("con_recorte", 1)
	for i in 4:
		m.set_shader_parameter("q%d" % i, q[i] / tam)


## en el movil con lluvia, sin las gotas en la lente (main._lluvia_movil_ligera)
var sin_lente_lluvia := false
static var _diag_sin_lente_lluvia: bool = "--sinlentelluvia" in OS.get_cmdline_user_args()


## Seca la lente de golpe (al morir, al cambiar de ronda).
func clear_lens_rain() -> void:
	_lluvia_k = 0.0
	if lluvia_rect and is_instance_valid(lluvia_rect):
		lluvia_rect.visible = false


## Grano de tierra: manchas irregulares y opacas, mas anchas que altas (van pegadas al cristal).
func _make_dirt_texture(seed_v: int, claro: bool = false) -> ImageTexture:
	var n := 48
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var lobes: Array = [[Vector2(0.5, 0.5), rng.randf_range(0.16, 0.26)]]
	for i in rng.randi_range(4, 8):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.10, 0.32)
		lobes.append([Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * d, rng.randf_range(0.04, 0.11)])
	for y in n:
		for x in n:
			var uv := Vector2(float(x) / (n - 1), float(y) / (n - 1))
			var a := 0.0
			for L in lobes:
				var d: float = uv.distance_to(L[0])
				var r: float = L[1]
				if d < r:
					a = maxf(a, 1.0 - pow(d / r, 1.7))
			# grano: la tierra no es una mancha lisa, es polvo con trozos
			a *= 0.55 + 0.45 * absf(sin(uv.x * 61.0 + seed_v) * cos(uv.y * 53.0 - seed_v * 0.7))
			var t := clampf(a, 0.0, 1.0)
			var tono := 0.30 + 0.16 * sin(uv.x * 17.0 + seed_v)
			if claro:
				# polvo iluminado de frente: gris tierra claro, no marron
				tono = 0.62 + 0.12 * sin(uv.x * 17.0 + seed_v)
				img.set_pixel(x, y, Color(tono + 0.05, tono * 0.95, tono * 0.84, t * 0.95))
				continue
			img.set_pixel(x, y, Color(tono + 0.10, tono * 0.82, tono * 0.55, t * 0.95))
	return ImageTexture.create_from_image(img)


func _build_dirt_layer() -> void:
	dirt_layer = Control.new()
	dirt_layer.name = "TierraLente"
	dirt_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dirt_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dirt_layer)
	for i in 5:
		_dirt_tex.append(_make_dirt_texture(3100 + i * 131))
		_dirt_tex_claro.append(_make_dirt_texture(3100 + i * 131, true))
	# EL VAHO. Aqui solo va el VELO: una capa blanca muy floja. El desenfoque de verdad lo hace la
	# camara (profundidad de campo), no un shader de pantalla.
	# El shader que habia leia la textura de la pantalla y se dibujaba ENCIMA de todo: blanqueaba la
	# interfaz entera y hacia parpadear la tierra, porque la tierra se dibujaba antes de la copia de
	# pantalla y luego quedaba tapada. El velo va el PRIMERO de la lista, o sea por debajo de la mira
	# y de los marcadores: mancha lo que se ve del mundo y deja limpia la interfaz.
	fog_rect = ColorRect.new()
	fog_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fog_rect.color = Color(0.88, 0.88, 0.86, 0.0)
	fog_rect.visible = false
	root.add_child(fog_rect)
	root.move_child(fog_rect, 0)
	root.move_child(dirt_layer, 1)   # la tierra, justo encima del velo y debajo de la interfaz


## TIERRA AL CRISTAL. `punto` es donde ha estallado, ya en coordenadas de pantalla: los grumos se
## agrupan de ese lado, que es de donde te ha llegado la tierra. `fuerza` de 0 a 1.
## `ventana`: con el ESCUDO en la cara, lo que se ve a traves de su cristal. Fuera de ese recuadro detras
## de la lente hay acero negro, y la tierra marron sobre negro no se ve: parecia que el escudo no dejaba
## ensuciarse la lente. Como el polvo de verdad, delante de algo oscuro la tierra se ve CLARA (le da la luz
## de frente) y delante del cielo, oscura. Vacia = sin escudo.
func lens_dirt(punto: Vector2, fuerza: float, ventana: Rect2 = Rect2()) -> void:
	if dirt_layer == null:
		_build_dirt_layer()
	var s: Vector2 = root.size
	# MAS TIERRA: con una decena de grumos el cristal se veia salpicado, no sucio. Un misil cerca
	# te deja el visor hecho un asco.
	var n := int(clampf(11.0 + fuerza * 19.0, 11.0, 30.0))
	for i in n:
		var d := TextureRect.new()
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d.stretch_mode = TextureRect.STRETCH_SCALE
		d.texture = _dirt_tex[randi() % _dirt_tex.size()]
		var tam: float = s.y * randf_range(0.06, 0.24) * (0.60 + fuerza * 0.95)
		d.size = Vector2(tam * randf_range(0.9, 1.6), tam)
		d.pivot_offset = d.size * 0.5
		d.rotation = randf() * TAU
		# agrupados alrededor del estallido, con algun grumo suelto lejos
		var lejos: float = s.y * (0.45 if randf() < 0.25 else 0.16)
		var p: Vector2 = punto + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * lejos
		p.x = clampf(p.x, 0.0, s.x)
		p.y = clampf(p.y, 0.0, s.y)
		d.position = p - d.size * 0.5
		var al: float = randf_range(0.42, 0.95) * clampf(0.55 + fuerza, 0.45, 1.0)
		d.modulate = Color(1, 1, 1, al)
		if ventana.has_area() and not ventana.grow(-s.y * 0.02).has_point(p):
			d.texture = _dirt_tex_claro[randi() % _dirt_tex_claro.size()]
			d.modulate = Color(1, 1, 1, minf(al * 1.1, 1.0))
		d.visible = true
		dirt_layer.add_child(d)
		_dirt.append([d, al, p.x])
	# tope: con muchos estallidos seguidos no se ve nada y ademas cuesta
	while _dirt.size() > 48:
		var v: Array = _dirt.pop_front()
		if v[0] and is_instance_valid(v[0]):
			(v[0] as Node).queue_free()


## EL VAHO del calor. Se va solo, rapido.
func lens_fog(fuerza: float) -> void:
	if dirt_layer == null:
		_build_dirt_layer()
	fog_t = maxf(fog_t, clampf(fuerza, 0.0, 1.0))


## Cuanta tierra queda pegada (0 = cristal limpio). Lo usa el jugador para saber si toca limpiar.
func lens_dirt_amount() -> int:
	return _dirt.size()


## EL BRAZO PASANDO POR EL CRISTAL. `k` va de 0 a 1 segun avanza la mano; `desde_derecha` dice por
## que lado entra. Se borra lo que ya ha pasado la mano, asi que si el gesto se corta a medias la
## tierra que queda es justo la del lado que no le dio tiempo a limpiar.
func wipe_lens(k: float, desde_derecha: bool) -> void:
	if _dirt.is_empty():
		return
	var ancho: float = maxf(root.size.x, 1.0)
	var linea: float = (1.0 - clampf(k, 0.0, 1.0)) * ancho if desde_derecha else clampf(k, 0.0, 1.0) * ancho
	var i := _dirt.size() - 1
	while i >= 0:
		var e: Array = _dirt[i]
		var d = e[0]
		if d == null or not is_instance_valid(d):
			_dirt.remove_at(i)
			i -= 1
			continue
		var x: float = e[2]
		var pasado: bool = x >= linea if desde_derecha else x <= linea
		if pasado:
			# no desaparece de golpe: se va emborronando conforme la mano pasa por encima
			var a: float = float(e[1]) * clampf(1.0 - (absf(x - linea) / (ancho * 0.18)), 0.0, 1.0)
			d.modulate.a = a
			if a <= 0.02:
				d.queue_free()
				_dirt.remove_at(i)
		i -= 1


## Cristal limpio de golpe (al reaparecer, al cambiar de ronda).
func clear_lens() -> void:
	for e in _dirt:
		if e[0] and is_instance_valid(e[0]):
			(e[0] as Node).queue_free()
	_dirt.clear()
	fog_t = 0.0
	if fog_rect and is_instance_valid(fog_rect):
		fog_rect.visible = false


func _update_lens(dt: float) -> void:
	if fog_rect == null or not is_instance_valid(fog_rect):
		return
	if fog_t > 0.0:
		# SE DISIPA DESPACIO. A 0,85 duraba poco mas de un segundo y practicamente no se veia: el
		# estallido todavia tapaba la pantalla cuando el vaho ya se habia ido.
		fog_t = maxf(0.0, fog_t - dt * FOG_BAJA)
		fog_rect.visible = true
		fog_rect.color.a = fog_t * 0.20
	elif fog_rect.visible:
		fog_rect.visible = false


## `fuerza` de 0 a 1: a bocajarro salpica más y más grande.
func blood_splash(fuerza: float) -> void:
	if blood_layer == null:
		_build_blood_layer()
	var s: Vector2 = root.size
	var n := int(clampf(2.0 + fuerza * 5.0, 2.0, 7.0))
	for i in n:
		var d: TextureRect
		if _drop_pool.size() < 14:
			d = TextureRect.new()
			d.mouse_filter = Control.MOUSE_FILTER_IGNORE
			d.stretch_mode = TextureRect.STRETCH_SCALE
			blood_layer.add_child(d)
			_drop_pool.append(d)
		else:
			d = _drop_pool[randi() % _drop_pool.size()]
		d.texture = _drop_tex[randi() % _drop_tex.size()]
		var tam: float = s.y * randf_range(0.05, 0.16) * (0.6 + fuerza * 0.8)
		d.size = Vector2(tam, tam)
		d.pivot_offset = d.size * 0.5
		d.rotation = randf() * TAU
		d.position = Vector2(randf_range(0.05, 0.95) * s.x, randf_range(0.15, 0.85) * s.y) - d.size * 0.5
		d.modulate = Color(1, 1, 1, randf_range(0.55, 0.95))
		d.visible = true
		_drops.append([d, 0.0, randf_range(3.5, 6.5), randf_range(4.0, 16.0)])


func _update_blood(dt: float) -> void:
	var i := _drops.size() - 1
	while i >= 0:
		var e: Array = _drops[i]
		var d: TextureRect = e[0]
		if not is_instance_valid(d):
			_drops.remove_at(i)
			i -= 1
			continue
		e[1] += dt
		var k: float = e[1] / float(e[2])
		if k >= 1.0:
			d.visible = false
			_drops.remove_at(i)
			i -= 1
			continue
		# resbala hacia abajo (cada vez más despacio, como una gota secándose) y se desvanece
		d.position.y += float(e[3]) * dt * (1.0 - k)
		d.modulate.a = (1.0 - k * k) * 0.95
		_drops[i] = e
		i -= 1


# ---------------------------------------------------------------------------
# MIRA TELESCÓPICA (francotirador): todo negro menos un círculo, con retícula de cruz. Se dibuja
# con nodos (nada de texturas gigantes) para que en móvil no cueste memoria.
# ---------------------------------------------------------------------------
func _build_scope() -> void:
	scope = Control.new()
	scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	scope.visible = false
	root.add_child(scope)
	for i in 4:
		var b := ColorRect.new()
		b.color = Color(0, 0, 0, 1)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scope.add_child(b)
	var ring := TextureRect.new()
	ring.texture = _scope_texture()
	ring.name = "Ring"
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.stretch_mode = TextureRect.STRETCH_SCALE
	scope.add_child(ring)
	for i in 4:
		var l := ColorRect.new()
		l.color = Color(0, 0, 0, 0.92)
		l.name = "Cross%d" % i
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scope.add_child(l)


## Anillo de la lente: transparente dentro, negro fuera, con el borde suavizado.
func _scope_texture() -> ImageTexture:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (Vector2(x, y) / float(n - 1)) * 2.0 - Vector2.ONE
			var d: float = u.length()
			var a: float = clampf((d - 0.90) / 0.06, 0.0, 1.0)
			var vig: float = clampf((d - 0.55) / 0.45, 0.0, 1.0) * 0.55
			img.set_pixel(x, y, Color(0, 0, 0, maxf(a, vig)))
	return ImageTexture.create_from_image(img)


func set_scope(on: bool) -> void:
	if scope == null:
		_build_scope()
	scope_on = on
	scope.visible = on
	if not on:
		return
	var s: Vector2 = root.size
	var c: Vector2 = s * 0.5
	var r: float = minf(s.x, s.y) * 0.46
	var ring: TextureRect = scope.get_node("Ring")
	ring.position = c - Vector2(r, r)
	ring.size = Vector2(r * 2.0, r * 2.0)
	var bars: Array = []
	for ch in scope.get_children():
		if ch is ColorRect and not String(ch.name).begins_with("Cross"):
			bars.append(ch)
	if bars.size() >= 4:
		bars[0].position = Vector2.ZERO;              bars[0].size = Vector2(c.x - r, s.y)
		bars[1].position = Vector2(c.x + r, 0);       bars[1].size = Vector2(s.x - (c.x + r), s.y)
		bars[2].position = Vector2(c.x - r, 0);       bars[2].size = Vector2(r * 2.0, c.y - r)
		bars[3].position = Vector2(c.x - r, c.y + r); bars[3].size = Vector2(r * 2.0, s.y - (c.y + r))
	var arm: float = r * 0.78
	var th := 2.0
	scope.get_node("Cross0").position = Vector2(c.x - th * 0.5, c.y - arm); scope.get_node("Cross0").size = Vector2(th, arm - 16.0)
	scope.get_node("Cross1").position = Vector2(c.x - th * 0.5, c.y + 16.0); scope.get_node("Cross1").size = Vector2(th, arm - 16.0)
	scope.get_node("Cross2").position = Vector2(c.x - arm, c.y - th * 0.5); scope.get_node("Cross2").size = Vector2(arm - 16.0, th)
	scope.get_node("Cross3").position = Vector2(c.x + 16.0, c.y - th * 0.5); scope.get_node("Cross3").size = Vector2(arm - 16.0, th)


# ---------------------------------------------------------------------------
# Barra de armas: una tarjeta por ranura con el MODELO 3D del arma renderizado a 2D
# ---------------------------------------------------------------------------
func build_weapon_bar() -> void:
	if weapon_bar and is_instance_valid(weapon_bar):
		weapon_bar.queue_free()
	weapon_cards.clear()
	weapon_bar = HBoxContainer.new()
	weapon_bar.name = "WeaponBar"
	weapon_bar.add_theme_constant_override("separation", 6)
	weapon_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(weapon_bar)
	var IconScript := preload("res://scripts/weapon_icon.gd")
	# LA RANURA DE LA C4 SOLO EXISTE MIENTRAS LLEVAS LA BOMBA. La policia no la lleva nunca, y el
	# terrorista solo desde que la recoge del suelo hasta que la planta o la suelta al morir. Antes
	# el hueco estaba siempre ahi con un "0" al lado, y confundia.
	var lleva_c4: bool = player != null and is_instance_valid(player) and player.has_c4()
	_bar_con_c4 = lleva_c4
	var orden: Array = Weapons.orden_ranuras()
	for i in range(3, Weapons.LIST.size()):
		orden.append(i)
	for i in orden:
		var w: Dictionary = Weapons.LIST[i]
		if not lleva_c4 and String(w.get("kind", "")) == "c4":
			continue
		# LA RANURA SIN ARMA NO SE ENSEÑA (2026-10-04, pedido con captura: "aparece un palo negro cuando no tengo arma"):
		# en el tutorial y al empezar el battle royale las ranuras de fuego van vacias; salen al coger un arma
		# (player.coger_arma rehace la barra)
		if String(w.get("kind", "")) == "vacio":
			continue
		var card := Button.new()
		card.focus_mode = Control.FOCUS_NONE
		card.custom_minimum_size = Vector2(124, 74)
		card.tooltip_text = String(w.get("name", ""))
		var idx: int = i
		card.pressed.connect(func():
			if player:
				player.switch_weapon(idx)
			refresh_weapon_bar())
		# icono: render 2D del modelo 3D del arma
		var vp: SubViewport = IconScript.make(String(w.get("model", w.get("kind", "rifle"))), String(w.get("id", "")), 72)
		card.add_child(vp)
		var tex := TextureRect.new()
		tex.texture = vp.get_texture()
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.offset_top = 2
		tex.offset_bottom = -14
		card.add_child(tex)
		# número de ranura y munición
		var num := _ulabel(11, Color(0.85, 0.88, 0.95))
		num.text = str((Weapons.orden_ranuras().find(i) + 1) if i < 3 else (i + 1))
		num.position = Vector2(6, 2)
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(num)
		var am := _ulabel(12, Color(0.9, 0.92, 1.0))
		am.name = "Ammo"
		am.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		am.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(am)
		card.set_meta("slot", i)
		weapon_bar.add_child(card)
		weapon_cards.append(card)
	refresh_weapon_bar()
	_layout()


func refresh_weapon_bar() -> void:
	var _tb := Time.get_ticks_usec()
	_refresh_weapon_bar_real()
	Prof.add("hud.barra", Time.get_ticks_usec() - _tb)


func _refresh_weapon_bar_real() -> void:
	if weapon_bar == null or not is_instance_valid(weapon_bar):
		return
	for card in weapon_cards:
		if not is_instance_valid(card):
			continue
		var i: int = int(card.get_meta("slot", -1))
		if i < 0 or i >= Weapons.LIST.size():
			continue
		var sel: bool = player != null and is_instance_valid(player) and player.current == i
		for st in [["normal", Color(0.06, 0.07, 0.10, 0.82)], ["hover", Color(0.10, 0.12, 0.17, 0.9)], ["pressed", Color(0.12, 0.14, 0.2, 0.9)]]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = st[1] if not sel else Color(0.14, 0.12, 0.04, 0.92)
			sb.set_corner_radius_all(6)
			sb.set_border_width_all(2 if sel else 1)
			sb.border_color = Color(1.0, 0.83, 0.0, 0.95) if sel else Color(0.30, 0.33, 0.40, 0.8)
			card.add_theme_stylebox_override(st[0], sb)
		var am: Label = card.get_node_or_null("Ammo")
		if am and player and is_instance_valid(player) and i < player.ammo.size():
			var melee: bool = bool(Weapons.LIST[i].get("melee", false))
			am.text = "∞" if melee else "%d / %d" % [player.ammo[i], player.reserve[i]]
			am.position = Vector2(0, card.size.y - 16)
			am.size = Vector2(card.custom_minimum_size.x, 14)


# ---------------------------------------------------------------------------
# Marcador de partida (modo bomba): bandos, tanteo, bajas recientes y cartel de fin de ronda
# ---------------------------------------------------------------------------
func build_match_hud() -> void:
	# EL MARCADOR ES DE BOMBA **Y DE DUELO A MUERTE**. Estaba solo para bomba, asi que en hangar -que
	# es duelo a muerte- no habia marcador arriba a la izquierda: se jugaba sin saber el tanteo ni
	# cuantas bajas faltaban. El actualizador (`set_scores`) ya sabia pintar el de duelo desde el
	# principio; lo que faltaba era CONSTRUIR el panel.
	var bomb: bool = main and ("bomb_mode" in main) and bool(main.bomb_mode)
	var duelo: bool = main and ("dm_mode" in main) and bool(main.dm_mode)
	var atraco: bool = main and ("ciudad3" in main) and bool(main.ciudad3)
	if score_panel and is_instance_valid(score_panel):
		score_panel.queue_free()
	if feed_box and is_instance_valid(feed_box):
		feed_box.queue_free()
	score_panel = null
	feed_box = null
	if not (bomb or duelo or atraco):
		return
	# EL MARCADOR, ARRIBA EN EL CENTRO (marcador_hud.gd): los medidores de los dos equipos y el reloj. EN BOMBA, el
	# de CS2 (marcador_cs2.gd, pedido): retratos, rondas y la cuenta atras de la ronda
	# y en el duelo SIN REAPARECER (eliminacion / ultimo en pie, pedido: "los avatares como en bomba")
	var cs2: bool = bomb or (duelo and Net.es_dm_elim())
	if cs2 and not bomb:
		score_panel = preload("res://scripts/marcador_elim.gd").new()      # su propio diseño (marcador_elim.gd)
	else:
		score_panel = preload("res://scripts/marcador_cs2.gd").new() if cs2 else preload("res://scripts/marcador_hud.gd").new()
	if cs2:
		score_panel.main_ref = main
	score_panel.name = "ScorePanel"
	root.add_child(score_panel)
	score_label = null

	feed_box = VBoxContainer.new()
	feed_box.name = "Feed"
	feed_box.alignment = BoxContainer.ALIGNMENT_END
	feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed_box.add_theme_constant_override("separation", 2)
	root.add_child(feed_box)

	if round_banner == null:
		round_banner = _label(34, Color(1.0, 0.83, 0.2))
		round_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		round_banner.text = ""
	_refresh_score()
	_layout()


## Marcador con el tanteo de la ronda. En BBCode no: dos colores con una sola etiqueta se resuelve
## componiendo el texto y tiñendo por bando en el propio panel.
## DUELO A MUERTE: el marcador no cuenta rondas ganadas sino BAJAS, y hay que ver cuanto falta para
## el objetivo. Lo pone main.gd cada vez que cae alguien.
var _dm := []      ## [bajas_t, bajas_ct, objetivo] · vacio = no es duelo a muerte

func set_dm_marcador(t: int, ct: int, objetivo: int) -> void:
	_dm = [t, ct, objetivo]
	_refresh_score()


func _refresh_score() -> void:
	if score_panel == null or not is_instance_valid(score_panel) or not score_panel.has_method("poner"):
		return
	var t := Net.score_t
	var ct := Net.score_ct
	var obj := 0
	# EL OBJETIVO DESDE EL PRINCIPIO: sin el, hasta la primera baja los medidores salian llenos (hasta el reloj)
	if _dm.is_empty() and main and ("dm_mode" in main) and bool(main.dm_mode) and ("dm_objetivo" in main):
		var bj: Dictionary = main.get("dm_bajas") if main.get("dm_bajas") is Dictionary else {}
		_dm = [int(bj.get("t", 0)), int(bj.get("ct", 0)), int(main.dm_objetivo)]
	if not _dm.is_empty():
		t = int(_dm[0])
		ct = int(_dm[1])
		obj = int(_dm[2])
	# DUELO TODOS CONTRA TODOS (Net.es_dm_todos): tus bajas a la izquierda, las del mejor rival a la derecha
	if main and bool(main.get("dm_mode")) and Net.es_dm_todos() and main.has_method("dm_todos_marcador"):
		var mt: Array = main.dm_todos_marcador()
		var mias := int(mt[0])
		var suyas := int(mt[1])
		var cinta_t := "VAS EMPATADO EN CABEZA" if mias + suyas > 0 else ""     # a 0-0, recien empezada, sin cinta
		var col_t: Color = score_panel.MORADO
		if mias > suyas:
			cinta_t = "¡VAS PRIMERO!"
			col_t = score_panel.VERDE_MANZANA
		elif suyas > mias:
			cinta_t = "LÍDER: %s" % String(mt[2]).to_upper()
			col_t = score_panel.ROJO
		score_panel.poner(mias, suyas, int(mt[3]), score_panel.AZUL, score_panel.ROJO, cinta_t, col_t)
		return
	# MI EQUIPO A LA IZQUIERDA Y EN AZUL; el rival a la derecha y en rojo (sin equipo: los naranjas a la izquierda)
	var mine := Net.my_team()
	var yo := ct if mine == Net.TEAM_CT else t
	var el := t if mine == Net.TEAM_CT else ct
	var cinta := "EQUIPOS EMPATADOS" if yo + el > 0 else ""     # a 0-0, recien empezada, sin cinta (marcador_hud.poner)
	var color_cinta: Color = score_panel.MORADO
	if yo != el:
		if mine == "":
			cinta = "GANA EL %s" % Net.nombre_equipo(Net.TEAM_T if t > ct else Net.TEAM_CT)
		else:
			cinta = "VAIS GANANDO" if yo > el else "VAIS PERDIENDO"
			color_cinta = score_panel.VERDE_MANZANA if yo > el else score_panel.ROJO
	score_panel.poner(yo, el, obj, score_panel.AZUL, score_panel.ROJO, cinta, color_cinta)


## Una línea del registro de bajas ("matador ▸ víctima"), que se desvanece sola.
func add_feed(text: String, color: Color) -> void:
	if feed_box == null or not is_instance_valid(feed_box):
		return
	var l := _ulabel(15, color)
	l.text = text
	feed_box.add_child(l)
	while feed_box.get_child_count() > 5:
		feed_box.get_child(0).queue_free()
	var t := get_tree().create_timer(6.0)
	t.timeout.connect(func():
		if is_instance_valid(l):
			l.queue_free())


func _on_round_over(winner: String, reason: String) -> void:
	if Net.dm_mode:
		# la pantalla de victoria la abre main.gd, que es quien tiene la tabla de bajas
		_refresh_score()
		return
	var quien := Net.nombre_equipo(winner)
	Audio.voz_fin_ronda(winner == Net.my_team(), reason.to_upper().contains("BOMBA"))
	round_banner_t = 6.0
	if round_banner and is_instance_valid(round_banner):
		round_banner.text = "%s GANAN LA RONDA\n%s" % [quien, reason]
		round_banner.modulate.a = 1.0
	_refresh_score()


## PANTALLA DE VICTORIA DEL DUELO A MUERTE: EL PODIO. Los tres mejores de la partida, de pie y en 3D
## como el avatar del lobby, cada uno en su podio: el MVP en el centro y mas alto, el segundo a la
## izquierda y el tercero a la derecha. Debajo de cada podio, su puesto, su nombre y sus bajas; arriba
## a la izquierda, si habeis ganado y el marcador; abajo a la derecha, el boton para volver al lobby.
## NO se vuelve solo: cada uno se queda mirando el podio lo que quiera.
##
## Es un mundo 3D APARTE (SubViewport con mundo propio): ni la niebla, ni la lluvia, ni la luz del
## mapa llegan hasta aqui, y se ve igual en cualquier mapa y a cualquier hora.
##
## Cuelga de la capa, no de `root`: por encima de la lente de ojo de pez y sin encoger con la camara
## de cuerpo, igual que el menu (ver menu_panel).
##
## `filas`: [{nombre, equipo, bajas, muertes, es_yo}]
var victoria: Control = null

const AvatarPodio := preload("res://scripts/avatar_animator.gd")
const LobbyPodio := preload("res://scripts/lobby.gd")

## [x, alto del podio, color del anillo, texto del puesto] para el 1.o, 2.o y 3.o
const PODIO := [
	[0.0, 0.34, Color(1.0, 0.83, 0.0), "MVP"],
	[-1.55, 0.20, Color(0.80, 0.84, 0.90), "2.º"],
	[1.55, 0.10, Color(0.85, 0.52, 0.28), "3.º"],
]

## `linea`: si viene, sustituye al marcador de bajas bajo el titulo (la ciudad lo usa para los puntos de
## los tres equipos, que no caben en "uno contra otro").
## `titulo`: fuerza el cartel ("VICTORIA" / "DERROTA"). Vacio = se decide por `ganador` como siempre.
## `premio`: {exp, oro, subio, nivel_ahora} de `Settings.premiar`. Vacio = no se enseña nada.
##
## HACIA FALTA PODER FORZARLO. El cartel salia de `ganador == Net.my_team()`, y en el modo oleadas no
## hay equipos: al morir salia la pantalla SIN decir victoria ni derrota, porque ningun equipo
## coincidia con el tuyo.
## ¿Esta puesta la pantalla de fin de partida? Lo usa el banco de pruebas: "se acabo la partida" y
## "sale el podio" son dos cosas distintas y conviene poder preguntar por la segunda.
func tiene_pantalla_victoria() -> bool:
	return victoria != null and is_instance_valid(victoria)


## LA TABLA DEL FINAL (victoria_final.gd), la ultima pantalla de main.secuencia_fin en todos los modos: una, dos
## o tres tablas (`equipos`), y con tema "zombi" en negro y sangre.
func mostrar_victoria_final(gane: bool, marcador: Array, filas: Array, premio: Dictionary, tema := "", titulo := "",
		equipos: Array = []) -> void:
	if victoria and is_instance_valid(victoria):
		victoria.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for n in [weapon_bar, mobile, crosshair]:
		if n and is_instance_valid(n):
			(n as CanvasItem).visible = false
	Audio.voz_fin_partida(gane)
	var vf = preload("res://scripts/victoria_final.gd").new()
	vf.gane = gane
	vf.marcador = marcador
	vf.filas = filas
	vf.premio = premio
	vf.main_ref = main
	vf.tema = tema
	vf.titulo = titulo
	vf.equipos = equipos
	vf.name = "Victoria"
	add_child(vf)
	victoria = vf


func mostrar_victoria(ganador: String, bajas_t: int, bajas_ct: int, filas: Array, linea: String = "",
		titulo: String = "", premio: Dictionary = {}) -> void:
	if victoria and is_instance_valid(victoria):
		victoria.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for n in [weapon_bar, mobile, crosshair]:
		if n and is_instance_valid(n):
			(n as CanvasItem).visible = false
	var mio: bool = ganador == Net.my_team() if titulo == "" else titulo == "VICTORIA"
	Audio.voz_fin_partida(mio)
	# LOS MODOS POR EQUIPOS (duelo a muerte, bomba) tienen la pantalla nueva: la lista de los dos equipos con sus
	# puntos y sus me gusta (victoria_final.gd). Los demas (oleadas, atraco, battle royale) siguen con el podio.
	if linea == "" and titulo == "":
		var vf = preload("res://scripts/victoria_final.gd").new()
		vf.gane = mio
		var mi_eq := Net.my_team()
		vf.marcador = [bajas_ct if mi_eq == Net.TEAM_CT else bajas_t, bajas_t if mi_eq == Net.TEAM_CT else bajas_ct]
		vf.filas = filas
		vf.premio = premio
		vf.main_ref = main
		vf.name = "Victoria"
		add_child(vf)
		victoria = vf
		return
	var dorado := Color(1.0, 0.83, 0.0)
	var rojo := Color(0.95, 0.35, 0.32)
	var tenue := Color(0.72, 0.76, 0.85)

	# los tres mejores: mas bajas primero, y a igualdad, menos muertes
	var orden := filas.duplicate()
	orden.sort_custom(func(x, y) -> bool:
		if int(x["bajas"]) != int(y["bajas"]):
			return int(x["bajas"]) > int(y["bajas"])
		return int(x["muertes"]) < int(y["muertes"]))
	var top: Array = orden.slice(0, mini(3, orden.size()))

	victoria = Control.new()
	victoria.name = "Victoria"
	victoria.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	victoria.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(victoria)

	# --- EL ESCENARIO 3D, detras de todo -----------------------------------------------------------
	var marco := SubViewportContainer.new()
	marco.stretch = true
	marco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	marco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	victoria.add_child(marco)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	marco.add_child(sv)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.030, 0.032, 0.040)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.68)
	env.ambient_light_energy = 0.7
	we.environment = env
	sv.add_child(we)
	# la misma luz que el lobby: sol calido con sombra, contraluz frio y relleno ambar
	var sol := DirectionalLight3D.new()
	sol.light_energy = 2.6
	sol.shadow_enabled = true
	sol.rotation_degrees = Vector3(-40, 35, 0)
	sv.add_child(sol)
	# ALTAS: pegadas al suelo dejaban un charco de luz azul y otro naranja en el suelo brillante
	for spec in [[Vector3(-2.8, 3.6, -2.0), Color(0.55, 0.8, 1.0), 2.4], [Vector3(2.8, 3.2, 2.2), Color(1.0, 0.75, 0.3), 1.6]]:
		var lt := OmniLight3D.new()
		lt.position = spec[0]
		lt.light_color = spec[1]
		lt.light_energy = spec[2]
		lt.omni_range = 8.0
		sv.add_child(lt)
	# y un foco sobre el MVP, que es a quien hay que mirar
	var foco := SpotLight3D.new()
	foco.position = Vector3(0, 4.2, 1.2)
	foco.light_energy = 6.0
	foco.spot_range = 7.0
	foco.spot_angle = 22.0
	foco.light_color = Color(1.0, 0.93, 0.75)
	sv.add_child(foco)
	foco.look_at(Vector3(0, 0.6, 0), Vector3.UP)

	var suelo := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	suelo.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.030, 0.032, 0.038)
	fm.roughness = 0.7
	fm.metallic = 0.1
	suelo.material_override = fm
	suelo.position.y = -0.01
	sv.add_child(suelo)

	var cam := Camera3D.new()
	cam.fov = 42.0
	sv.add_child(cam)
	cam.position = Vector3(0.0, 1.45, 5.9)
	# mirando algo por debajo de las cabezas: sube todo el escenario en pantalla y deja sitio a los
	# letreros de debajo de los podios sin que el del tercero choque con el boton de volver
	cam.look_at(Vector3(0, 0.65, 0), Vector3.UP)
	cam.current = true

	var cabezas: Array = []      # donde poner cada letrero: [posicion 3D sobre la cabeza, fila, puesto]
	for i in top.size():
		var f: Dictionary = top[i]
		var spec: Array = PODIO[i]
		var x: float = spec[0]
		var alto: float = spec[1]
		var col: Color = spec[2]
		var ped := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.62
		cm.bottom_radius = 0.68
		cm.height = alto
		cm.radial_segments = 40
		ped.mesh = cm
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.075, 0.078, 0.09)
		pmat.roughness = 0.4
		pmat.metallic = 0.5
		ped.material_override = pmat
		ped.position = Vector3(x, alto * 0.5, 0.0)
		sv.add_child(ped)
		var anillo := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.64
		tm.outer_radius = 0.675
		tm.rings = 40
		anillo.mesh = tm
		var rm := StandardMaterial3D.new()
		rm.albedo_color = col
		rm.emission_enabled = true
		rm.emission = col
		rm.emission_energy_multiplier = 2.2
		anillo.material_override = rm
		anillo.position = Vector3(x, alto + 0.005, 0.0)
		sv.add_child(anillo)

		# EL AVATAR. Tu con tu skin; los demas con el color de su bando, igual que en partida.
		var av = AvatarPodio.new()
		sv.add_child(av)
		var yo: bool = bool(f.get("es_yo", false))
		if yo:
			av.build(1.75, false, Color.WHITE, true, false, LobbyPodio.skin_id(), LobbyPodio.skin_receta())
			LobbyPodio.aplicar_skin(av)
		else:
			av.build(1.75, false, _tinte_equipo(String(f["equipo"])), true)
		av.position = Vector3(x, alto, 0.0)
		# de cara a la camara, y los de los lados girados un poco hacia el centro
		av.rotation.y = PI - x * 0.16
		if i == 0 and av.has_clip("emote_1"):
			av.play("emote_1", true)
			var fin_emote: float = float(AvatarPodio._baked("emote_1")["dur"])
			get_tree().create_timer(fin_emote).timeout.connect(func() -> void:
				if is_instance_valid(av):
					av.play("idle_menu" if av.has_clip("idle_menu") else "idle_1"))
		else:
			av.play("idle_menu" if av.has_clip("idle_menu") else "idle_1")
		# el punto de delante y abajo del podio: ahi va el letrero (ver mas abajo)
		cabezas.append([Vector3(x, 0.0, 0.70), f, i])

	# --- LA INTERFAZ, encima del escenario -----------------------------------------------------------
	var arriba := VBoxContainer.new()
	arriba.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	arriba.position = Vector2(36, 20)
	arriba.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arriba.add_theme_constant_override("separation", 0)
	victoria.add_child(arriba)
	var cartel: String = titulo if titulo != "" else ("VICTORIA" if mio else "DERROTA")
	arriba.add_child(_texto(cartel, 58, dorado if mio else rojo, false))
	var marcador_final: String = linea if linea != "" else "%s  %d  :  %d  %s" % [Net.nombre_equipo(Net.TEAM_T), bajas_t, bajas_ct, Net.nombre_equipo(Net.TEAM_CT)]
	arriba.add_child(_texto(marcador_final, 22, Color.WHITE, false))
	# LO QUE TE LLEVAS. Perder no da nada, y entonces se dice: enseñar un cero es mas claro que no
	# enseñar nada, porque asi se ve que el premio existe y que hay que ganarselo.
	if bool(premio.get("servidor", false)):
		# EL PREMIO LO ESTA CALCULANDO EL SERVIDOR y llega por HTTP unos cientos de milisegundos
		# despues de abrirse esta pantalla. Enseñar "+0 EXP" mientras tanto seria mentir, asi que se
		# pone un aviso y se rellena cuando conteste.
		var linea_premio := _texto("calculando el premio...", 26, tenue, false)
		arriba.add_child(linea_premio)
		var linea_cuenta := _texto("", 18, tenue, false)
		arriba.add_child(linea_cuenta)
		var pintar := func():
			if not is_instance_valid(linea_premio):
				return
			var pr: Dictionary = Cuenta.ultimo_premio
			var e := int(pr.get("exp", 0))
			var o := int(pr.get("oro", 0))
			if e > 0 or o > 0:
				linea_premio.text = "+%d EXP   +%d ◈" % [e, o]
				linea_premio.add_theme_color_override("font_color", dorado)
			else:
				linea_premio.text = String(pr.get("motivo", "sin premio: hay que ganar"))
			linea_cuenta.text = "nivel %d · %d EXP · ◈ %d" % [Cuenta.nivel(), Cuenta.experiencia(), Cuenta.monedas()]
			# MISIONES COMPLETADAS EN ESTA PARTIDA: se dicen aqui, que es donde se entienden
			var hechas: Array = pr.get("misiones", []) if pr.get("misiones", []) is Array else []
			if not hechas.is_empty():
				var partes: PackedStringArray = []
				for m in hechas:
					partes.append("✔ %s  +%d ◈" % [String(m.get("texto", "")), int(m.get("premio", 0))])
				linea_cuenta.text += "\nMISIÓN COMPLETADA: " + "   ·   ".join(partes)
		if not Cuenta.sesion_cambiada.is_connected(pintar):
			Cuenta.sesion_cambiada.connect(pintar, CONNECT_ONE_SHOT)
		# ...Y SI EL SERVIDOR NO CONTESTA, TAMBIEN SE DICE. Sin esto el cartel se quedaba en
		# "calculando el premio..." para siempre, que es la peor de las tres respuestas posibles:
		# el jugador no sabe si ha ganado algo, si lo ha perdido, o si el juego se ha colgado.
		var fallo := func(m: String):
			if is_instance_valid(linea_premio):
				linea_premio.text = "no se pudo guardar el premio: " + m
				linea_premio.add_theme_color_override("font_color", rojo)
			if is_instance_valid(linea_cuenta):
				linea_cuenta.text = "se reintentara al volver a entrar"
		if not Cuenta.error_cuenta.is_connected(fallo):
			Cuenta.error_cuenta.connect(fallo, CONNECT_ONE_SHOT)
	elif not premio.is_empty():
		var ex := int(premio.get("exp", 0))
		var oro_p := int(premio.get("oro", 0))
		if ex > 0 or oro_p > 0:
			arriba.add_child(_texto("+%d EXP   +%d ◈" % [ex, oro_p], 26, dorado, false))
			if bool(premio.get("subio", false)):
				arriba.add_child(_texto("¡NIVEL %d!" % int(premio.get("nivel_ahora", 1)), 24, dorado, false))
		else:
			arriba.add_child(_texto("sin premio: hay que ganar", 20, tenue, false))
		var en: Array = Settings.exp_en_nivel()
		arriba.add_child(_texto("nivel %d · %d / %d EXP · ◈ %d" % [
			Settings.nivel(), int(en[0]), int(en[1]), Settings.monedas], 18, tenue, false))

	var letreros: Array = []
	for c in cabezas:
		var f: Dictionary = c[1]
		var i: int = c[2]
		var caja := VBoxContainer.new()
		caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caja.custom_minimum_size = Vector2(260, 0)
		caja.add_theme_constant_override("separation", 0)
		victoria.add_child(caja)
		var yo: bool = bool(f.get("es_yo", false))
		var puesto: String = PODIO[i][3]
		caja.add_child(_texto(("★  " if i == 0 else "") + puesto, 26 if i == 0 else 18, PODIO[i][2], true))
		caja.add_child(_texto(String(f["nombre"]) + ("  (tú)" if yo else ""), 26 if i == 0 else 20, dorado if yo else Color.WHITE, true))
		caja.add_child(_texto(Net.nombre_equipo(String(f["equipo"])), 13, Net.color_equipo(String(f["equipo"])).lerp(Color.WHITE, 0.35), true))
		var b: int = int(f["bajas"])
		var mu: int = int(f["muertes"])
		caja.add_child(_texto("%d bajas · %d muertes · K/D %.2f" % [b, mu, float(b) / float(maxi(mu, 1))], 14, tenue, true))
		letreros.append([caja, c[0]])

	# VOLVER AL LOBBY, abajo a la derecha. Nada de cuenta atras: el podio se mira lo que se quiera.
	var volver := Button.new()
	volver.text = "VOLVER AL LOBBY"
	volver.focus_mode = Control.FOCUS_NONE
	volver.add_theme_font_size_override("font_size", 20)
	for estado in ["font_color", "font_hover_color", "font_pressed_color"]:
		volver.add_theme_color_override(estado, Color(0.08, 0.08, 0.1))
	volver.add_theme_stylebox_override("normal", _caja(dorado, dorado, 0, 12, 14))
	volver.add_theme_stylebox_override("hover", _caja(dorado.lightened(0.18), dorado.lightened(0.18), 0, 12, 14))
	volver.add_theme_stylebox_override("pressed", _caja(dorado.darkened(0.12), dorado.darkened(0.12), 0, 12, 14))
	volver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	volver.offset_left = -310
	volver.offset_top = -86
	volver.offset_right = -30
	volver.offset_bottom = -28
	volver.pressed.connect(func() -> void:
		volver.disabled = true           # un solo clic: dos seguidos cambiarian de escena dos veces
		if main and main.has_method("go_to_lobby"):
			main.go_to_lobby())
	victoria.add_child(volver)

	# LOS LETREROS, DEBAJO DE CADA PODIO. Encima de las cabezas chocaban con el titulo: las cabezas
	# quedan en el tercio de arriba y el letrero del MVP tapaba "VICTORIA" y el marcador.
	#
	# Se colocan proyectando con la camara del podio, y hay que esperar a que el contenedor tenga su
	# tamano definitivo: si no, la camara proyecta sobre un lienzo de 0x0.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(victoria) or not is_instance_valid(cam):
		return
	for par in letreros:
		var caja: Control = par[0]
		var pt: Vector2 = cam.unproject_position(par[1])
		var tam: Vector2 = caja.get_combined_minimum_size()
		caja.position = Vector2(pt.x - tam.x * 0.5, pt.y + 6.0)


## TINTE DEL AVATAR DE UN EQUIPO EN EL PODIO. El podio daba por hecho que habia dos bandos -"t" o "el
## otro"- y con los tres de la ciudad un bot VIOLETA salia como EQUIPO AZUL, con su tinte. Ahora cada uno
## lleva el color de su equipo; con dos equipos, el azulado y el rojizo de siempre.
func _tinte_equipo(eq: String) -> Color:
	if Net.equipos.size() >= 3:
		return Net.color_equipo(eq).lerp(Color.WHITE, 0.45)
	return Color(1.0, 0.72, 0.66) if eq == Net.TEAM_T else Color(0.62, 0.80, 1.0)


func _texto(t: String, tam: int, col: Color, centrado: bool) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", col)
	if centrado:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _caja(bg: Color, borde: Color, ancho: int, radio: int, margen: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radio)
	sb.set_border_width_all(ancho)
	sb.border_color = borde
	sb.set_content_margin_all(margen)
	return sb


# ---------------------------------------------------------------------------
# Portador de la C4: arriba, junto al nombre. En CS saber quién la lleva vale una ronda.
# ---------------------------------------------------------------------------
## Bomba redonda con mecha: circulo oscuro con brillo arriba a la izquierda y una mecha corta
## naranja saliendo por arriba. 32x32 basta al tamaño al que se dibuja.
func _bomb_icon_texture() -> ImageTexture:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(15.0, 19.0)
	for y in n:
		for x in n:
			var p := Vector2(x, y)
			var d: float = p.distance_to(c)
			if d <= 10.5:
				# cuerpo: mas claro hacia arriba a la izquierda (luz) y casi negro abajo
				var luz: float = clampf(1.0 - (p - c + Vector2(3.5, 4.0)).length() / 11.0, 0.0, 1.0)
				var t: float = 0.14 + luz * 0.55
				var a: float = clampf((10.5 - d) / 1.2, 0.0, 1.0)
				img.set_pixel(x, y, Color(t * 0.55, t * 0.56, t * 0.62, a))
	# mecha: dos trazos hacia arriba a la derecha, con la chispa en la punta
	for i in 9:
		var t := float(i) / 8.0
		var q := Vector2(15.0 + t * 6.0, 9.0 - t * 5.5)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var xx := int(q.x) + dx
				var yy := int(q.y) + dy
				if xx >= 0 and xx < n and yy >= 0 and yy < n:
					img.set_pixel(xx, yy, Color(1.0, 0.72, 0.18, 1.0) if t > 0.72 else Color(0.62, 0.48, 0.22, 1.0))
	return ImageTexture.create_from_image(img)


func refresh_carrier() -> void:
	if carrier_label == null or not is_instance_valid(carrier_label):
		return
	var bomb: bool = main and ("bomb_mode" in main) and bool(main.bomb_mode)
	if not bomb or Net.bomb_carrier == 0 or is_instance_valid(Net.bomb_node):
		carrier_label.text = ""
		if carrier_icon:
			carrier_icon.visible = false
		return
	var mio: bool = (not Net.is_online()) or Net.bomb_carrier == multiplayer.get_unique_id()
	if mio:
		carrier_label.text = "     %s  ·  LLEVAS LA C4" % Settings.player_name
		carrier_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.3))
	else:
		carrier_label.text = "     %s lleva la C4" % Net.carrier_name()
		carrier_label.add_theme_color_override("font_color", Color(0.72, 0.86, 1.0))
	if carrier_icon:
		carrier_icon.visible = true
		# pegado a la izquierda del texto, que va centrado: se mide el ancho real de la etiqueta
		var ancho: float = carrier_label.get_theme_font("font").get_string_size(
			carrier_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, carrier_label.get_theme_font_size("font_size")).x
		carrier_icon.position = Vector2(carrier_label.position.x + carrier_label.size.x * 0.5 - ancho * 0.5,
			carrier_label.position.y - 2.0)


# ---------------------------------------------------------------------------
# Controles táctiles
# ---------------------------------------------------------------------------
## Quita los controles táctiles (en PC, al cerrar el editor: allí se montan a la fuerza para poder
## diseñarlos, pero no tienen que quedarse en pantalla).
func drop_mobile_controls() -> void:
	if mobile and is_instance_valid(mobile):
		mobile.queue_free()
	mobile = null


func build_mobile_controls() -> void:
	if mobile and is_instance_valid(mobile):
		return
	mobile = MobileControls.new()
	mobile.set_anchors_preset(Control.PRESET_FULL_RECT)
	if loading_panel != null and loading_panel.visible:
		mobile.visible = false          # con la carga puesta, escondidos (set_loading los devuelve)
	# FUERA DE `root`, COLGANDO DIRECTAMENTE DE LA CAPA. Y no es un detalle de orden: el mando tactil
	# hace la deteccion de toques A MANO, comparando la posicion del dedo EN PANTALLA contra los
	# rectangulos locales de sus botones. Eso solo funciona si nadie le aplica una transformacion.
	#
	# Al encoger `root` un 10 % para la camara de cuerpo, `mobile` heredaba esa escala; se
	# contra-escalaba para que se VIERA bien, pero su transformacion dejaba de ser la identidad y los
	# botones quedaban dibujados en un sitio y buscados en otro. El dedo fallaba por unos pixeles.
	#
	# Colgando de la capa no hereda nada. Y como se anade despues de `root`, sigue dibujandose encima
	# de todo, que es lo que ya se queria.
	add_child(mobile)
	if player:
		mobile.setup(player)
	mobile.set_safe(safe_l, safe_r, safe_t, safe_b)


## Oculta o muestra todo lo que es "de combate": al elegir bando o al espectar, la pantalla se
## queda limpia.
func set_combat_ui_visible(on: bool) -> void:
	# El panel de accion NO se enciende aqui: lo gobierna su propio reloj. Encendiendolo a mano se
	# quedaba en pantalla para siempre con el texto viejo ("ESPECTANDO A ..."), porque su reloj ya
	# estaba a cero y nada volvia a apagarlo.
	#
	# Y EL MARCADOR DE ACIERTO, IGUAL, que estaba en esta lista: se encendia al aparecer el HUD y se
	# quedaba PUESTO para siempre -las cuatro rayas blancas alrededor de la mira, como si acabaras de
	# acertar un tiro-, porque lo unico que lo apaga esta dentro de `if hit_t > 0.0` y su reloj ya
	# estaba a cero. Lo gobierna su reloj y nadie mas. (Cazado en vivo con --diagvivo.)
	if hit_marker and is_instance_valid(hit_marker) and not on:
		hit_marker.visible = false
		hit_t = 0.0
	for n in [weapon_bar, ammo_label, weapon_label, crosshair, health_bar, mobile]:
		if n and is_instance_valid(n):
			n.visible = on
	# la de armadura va aparte: si no llevas chaleco no se enciende aunque se encienda el resto
	if armor_bar and is_instance_valid(armor_bar):
		armor_bar.visible = on and (armor_bar.value > 0.01 or _placas_on)
	if _placa_btn and is_instance_valid(_placa_btn):
		_placa_btn.visible = on
	if casco_bar and is_instance_valid(casco_bar):
		casco_bar.visible = on and casco_bar.value > 0.01
	if curas_label and is_instance_valid(curas_label):
		curas_label.visible = on and _curas_on
	if escudo_bar and is_instance_valid(escudo_bar):
		escudo_bar.visible = on and _escudo_on
		escudo_label.visible = escudo_bar.visible
	# ...Y SI LA CAMARA DE CUERPO ESTA PUESTA, se vuelve a esconder lo que ella esconde. Este bucle
	# enciende la interfaz de combate entera sin preguntar, asi que cada vez que reaparecias te
	# devolvia la mira que la bodycam habia quitado. Esconderla una vez no basta: hay que volver a
	# aplicar el estado cada vez que alguien enciende la interfaz de golpe.
	if on and bodycam > 0:
		_hud_minimo(true)
	if not on:
		hide_action()
		_ocultar_arcos()


## Las flechas de "me disparan desde ahi": fuera de la vista y sin recuerdos.
func _ocultar_arcos() -> void:
	dmg_dirs.clear()
	for a in dmg_arcs:
		if a and is_instance_valid(a):
			a.visible = false


## BORRA TODO LO QUE PINTA EL COMBATE EN PANTALLA: sangre en el cristal, flechas de dano, marcador
## de acierto, tinte rojo y aberracion. Se llama al morir y al reaparecer.
## Existe porque nada de esto se limpiaba: al morir de un explosivo la pantalla se llenaba de
## sangre (hasta 6,5 s de vida cada gota) y esos regueros rojos seguian ahi en la ronda siguiente.
func clear_combat_fx() -> void:
	for e in _drops:
		var d = e[0]
		if d and is_instance_valid(d):
			d.visible = false
	_drops.clear()
	_ocultar_arcos()
	clear_lens()
	clear_lens_rain()
	hit_t = 0.0
	if hit_marker and is_instance_valid(hit_marker):
		hit_marker.visible = false
	damage_t = 0.0
	if vignette and is_instance_valid(vignette):
		vignette.modulate.a = 0.0
	if aberration and is_instance_valid(aberration):
		aberration.visible = false
	hide_action()


# ---------------------------------------------------------------------------
# Menú de partida
# ---------------------------------------------------------------------------
## Panel propio de COMBATE, abierto desde el menú de la partida. Cada opción es un botón que
## muestra su estado; al tocarlo cambia y el panel se repinta.
func open_combat_panel() -> void:
	if combat_panel and is_instance_valid(combat_panel):
		combat_panel.queue_free()
		combat_panel = null
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	combat_panel = PanelContainer.new()
	combat_panel.name = "CombatLayer"
	var dim := StyleBoxFlat.new()
	dim.bg_color = Color(0, 0, 0, 0.6)
	combat_panel.add_theme_stylebox_override("panel", dim)
	combat_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# FUERA DE `root`, COLGANDO DE LA CAPA. `root` va por debajo de la lente de ojo de pez y ademas
	# se encoge con la camara de cuerpo. La lente DOBLA la imagen, pero el raton se comprueba contra
	# donde estan los botones de verdad, sin doblar: con la camara de cuerpo completa el boton que
	# veias no estaba donde el juego lo buscaba, y el clic caia en la opcion de al lado. Un shader
	# no puede llevarse la entrada con el, asi que lo que se pulsa no puede ir debajo de uno.
	# Colgando de la capa se dibuja despues de `root`: encima de la lente, recto y a escala 1.
	add_child(combat_panel)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	combat_panel.add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _corte_menu(Color(0.018, 0.021, 0.027, 0.97), LINEA_MENU, 1, 22, 24, 18))
	card.custom_minimum_size = Vector2(minf(600.0, root.size.x - 60.0), 0)
	center.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	card.add_child(vb)
	var cab := HBoxContainer.new()
	cab.add_theme_constant_override("separation", 12)
	vb.add_child(cab)
	var raya := ColorRect.new()
	raya.color = ORO_MENU
	raya.custom_minimum_size = Vector2(5, 28)
	raya.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cab.add_child(raya)
	var title := Label.new()
	title.text = "COMBATE"
	title.add_theme_font_override("font", _fuente_menu())
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color.WHITE)
	cab.add_child(title)
	for opt in [
		["APUNTAR AL DISPARAR", Settings.fire_ads, "Manteniendo el disparo apuntas con la mirilla; al soltar, baja el arma.",
			func(): Settings.fire_ads = not Settings.fire_ads],
		["VIBRACIÓN", Settings.vibration, "Vibra al disparar y al recibir daño. Nada mas.",
			func(): Settings.vibration = not Settings.vibration],
		["EFECTO DE CÁMARA", Settings.camera_feel > 0.01, "Balanceo al andar, inclinacion al moverte de lado y sacudida en las explosiones.",
			func(): Settings.camera_feel = 0.0 if Settings.camera_feel > 0.01 else 1.0],
		["ENFOQUE AL APUNTAR", Settings.focus_mode > 0, "Al apuntar, el fondo se desenfoca y la vista se va a lo que tienes en la mira.",
			func(): Settings.focus_mode = 0 if Settings.focus_mode > 0 else 1],
	]:
		var cb: Callable = opt[3]
		var on: bool = bool(opt[1])
		var b := _menu_button("%s:   %s" % [String(opt[0]), "ON" if on else "OFF"],
			Color(0.10, 0.24, 0.12, 0.95) if on else Color(0.08, 0.085, 0.10, 0.95), Color(0.55, 1.0, 0.55) if on else Color(0.80, 0.82, 0.86), 17, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# se repinta reabriendo el panel: así la etiqueta y el color muestran el valor nuevo
		b.pressed.connect(func(): cb.call(); Settings.save(); open_combat_panel(); open_combat_panel())
		vb.add_child(b)
		var d := Label.new()
		d.text = String(opt[2])
		d.add_theme_font_size_override("font_size", 12)
		d.add_theme_color_override("font_color", Color(0.72, 0.75, 0.82))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(d)
	var back := _menu_button("‹  VOLVER AL MENÚ", Color(0.08, 0.085, 0.10, 0.95), Color.WHITE, 16, 44)
	back.pressed.connect(func(): open_combat_panel(); toggle_menu())
	vb.add_child(back)


## Panel de menú en partida: herramientas ordenadas + acceso a la configuración gráfica.
## Lo que se aparta mientras el menu esta abierto, con la visibilidad que tenia cada uno.
var _menu_ocultos: Array = []

func toggle_menu() -> void:
	if menu_panel:
		menu_panel.queue_free()
		menu_panel = null
		# se devuelve a cada uno la visibilidad QUE TENIA, no un `true` a ciegas: la barra de armas
		# tambien esta escondida en el modo de HUD minimo y en la camara de cuerpo
		for par in _menu_ocultos:
			var n = par[0]
			if is_instance_valid(n):
				(n as CanvasItem).visible = bool(par[1])
		_menu_ocultos.clear()
		if not Settings.is_touch():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# FUERA LO QUE SE DIBUJA POR ENCIMA DEL MENU. La barra de armas y el mando tactil se ponen
	# deliberadamente delante de todo lo demas -la lente de ojo de pez no debe deformarlos, y el dedo
	# tiene que alcanzarlos siempre-, y el menu se cuelga de `root`, por debajo. Resultado: las
	# ranuras de armas tapaban las opciones del menu.
	#
	# Apartarlos es mejor que colar el menu aun mas arriba: con el menu abierto no se dispara ni se
	# cambia de arma, asi que esos mandos no pintan nada ahi, y ademas dejaban de estorbar al dedo.
	for n in [weapon_bar, mobile]:
		if n and is_instance_valid(n):
			_menu_ocultos.append([n, (n as CanvasItem).visible])
			(n as CanvasItem).visible = false
	# capa a pantalla completa (oscurece el juego) + contenedor centrado
	menu_panel = PanelContainer.new()
	menu_panel.name = "MenuLayer"
	var dimsb := StyleBoxFlat.new()
	dimsb.bg_color = Color(0, 0, 0, 0.70)
	menu_panel.add_theme_stylebox_override("panel", dimsb)
	menu_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# FUERA DE `root`, COLGANDO DE LA CAPA. `root` va por debajo de la lente de ojo de pez y ademas
	# se encoge con la camara de cuerpo. La lente DOBLA la imagen, pero el raton se comprueba contra
	# donde estan los botones de verdad, sin doblar: con la camara de cuerpo completa el boton que
	# veias no estaba donde el juego lo buscaba, y el clic caia en la opcion de al lado. Un shader
	# no puede llevarse la entrada con el, asi que lo que se pulsa no puede ir debajo de uno.
	# Colgando de la capa se dibuja despues de `root`: encima de la lente, recto y a escala 1.
	add_child(menu_panel)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_panel.add_child(center)
	var herramientas: bool = Settings.herramientas()
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _corte_menu(Color(0.018, 0.021, 0.027, 0.97), LINEA_MENU, 1, 22, 24, 18))
	# con herramientas va a dos columnas: una sola no cabia de alto en una pantalla de 720
	card.custom_minimum_size = Vector2(minf(1120.0 if herramientas else 700.0, root.size.x - 40.0), 0)
	center.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	card.add_child(vb)

	# cabecera: raya amarilla, MENÚ y CERRAR
	var cab := HBoxContainer.new()
	cab.add_theme_constant_override("separation", 12)
	vb.add_child(cab)
	var raya := ColorRect.new()
	raya.color = ORO_MENU
	raya.custom_minimum_size = Vector2(5, 30)
	raya.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cab.add_child(raya)
	var title := Label.new()
	title.text = "MENÚ"
	title.add_theme_font_override("font", _fuente_menu())
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cab.add_child(title)
	var close0 := _menu_button("CERRAR  (Esc)", Color(0.08, 0.085, 0.10, 0.95), Color.WHITE, 16, 42)
	close0.custom_minimum_size = Vector2(150, 42)
	close0.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close0.pressed.connect(toggle_menu)
	cab.add_child(close0)
	var filo := ColorRect.new()
	filo.color = LINEA_MENU
	filo.custom_minimum_size = Vector2(0, 1)
	vb.add_child(filo)

	var cuerpo := HBoxContainer.new()
	cuerpo.add_theme_constant_override("separation", 18)
	vb.add_child(cuerpo)
	var opciones := VBoxContainer.new()
	opciones.add_theme_constant_override("separation", 8)
	opciones.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opciones.custom_minimum_size = Vector2(420 if herramientas else 0, 0)
	cuerpo.add_child(opciones)
	opciones.add_child(_fila_menu("ajustes", "CONFIGURACIÓN GRÁFICA", "calidad, imagen, cámara y rendimiento", ORO_MENU,
		func(): toggle_menu(); if main: main.open_graphics_menu()))
	opciones.add_child(_fila_menu("tactil", "CONTROLES TÁCTILES", "mueve y ajusta los botones de la pantalla", Color(0.55, 0.80, 1.0),
		func(): toggle_menu(); if main: main.open_touch_editor()))
	# COMBATE: una sola entrada que abre su propio panel. Con las cuatro opciones sueltas aquí el
	# menú crecía demasiado.
	opciones.add_child(_fila_menu("mira", "COMBATE", "apuntar al disparar, vibración, cámara y enfoque", Color(1.0, 0.55, 0.30),
		func(): toggle_menu(); open_combat_panel()))
	# CALIBRAR ANIMACION fuera del menu: es una herramienta de ajuste fino de las animaciones, no algo
	# que pinte nada en una partida. Sigue existiendo (`main.open_calibrar_anim`) para cuando haga
	# falta tocarlas.
	# FOTO SIN INTERFAZ. Cierra el menu, oculta la interfaz un par de cuadros y dispara.
	opciones.add_child(_fila_menu("camara", "SACAR FOTO", "la partida tal cual, sin interfaz", Color(0.70, 0.90, 0.60), sacar_foto))
	opciones.add_child(_boton_volver_al_lobby())
	# HERRAMIENTAS: SOLO EN PRUEBAS OFFLINE.
	#
	# Dentro de esta rejilla hay VIDA INFINITA, MUNICION INFINITA, NOCLIP, DEMOLER EDIFICIO y CAMBIAR
	# MAPA. En una partida con gente eso no es un menu de opciones, es un menu de trampas, asi que ni
	# se construye: no basta con esconderlo, porque un boton escondido se sigue pudiendo pulsar desde
	# un script. Se enciende desde CUENTA -> PROBAR OFFLINE, y aun asi se apaga solo en cuanto hay red.
	# Sin cartel de "no disponible": un menu limpio no tiene por que contar lo que no tiene.
	if not herramientas:
		return
	var der := VBoxContainer.new()
	der.add_theme_constant_override("separation", 8)
	der.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cuerpo.add_child(der)
	var sec := Label.new()
	sec.text = "HERRAMIENTAS  ·  PRUEBAS OFFLINE"
	sec.add_theme_font_override("font", _fuente_menu())
	sec.add_theme_font_size_override("font_size", 18)
	sec.add_theme_color_override("font_color", ORO_MENU)
	der.add_child(sec)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 5)
	der.add_child(grid)
	var tools := [
		["BOTS: %s  (F7)" % ("ON" if Settings.bots_enabled else "OFF"), func(): if main: main.set_bots(not Settings.bots_enabled)],
		["CALIDAD: %s  (F5)" % quality_name, func(): if main: main.set_quality_manual((main.quality + 1) % 4)],
		["PERFILADOR  (F3)", func(): profiler_panel.visible = not profiler_panel.visible; Settings.show_profiler = profiler_panel.visible; Settings.save()],
		["GRABAR CSV  (F4)", func(): if csv: stop_csv() else: start_csv("manual")],
		["COPIAR XYZ  (F9)", func(): if main: main.copy_coords()],
		["DEMOLER EDIFICIO  (F6)", func(): if main: main.demolish_nearest()],
		["CAMBIAR MAPA  (F8)", func(): if main: main.cycle_map()],
		["NOCHE: %s" % ("ON" if (main and main.night) else "OFF"), func(): if main: main.set_night(not main.night)],
		["LLUVIA: %s" % ("ON" if (main and main.raining) else "OFF"), func(): if main: main.set_rain(not main.raining)],
		["NIEVE: %s" % ("ON" if (main and main.nevando) else "OFF"), func(): if main: main.set_nieve(not main.nevando)],
		# LA BODYCAM, AQUI TAMBIEN. Vive en la configuracion grafica, pero llegar hasta alli, cambiarla
		# y darle a APLICAR para ver si te gusta es demasiado camino: asi se prueba de un boton, en
		# marcha, y se compara al momento. Va rotando Off -> Sutil -> Completa.
		["AMBIENTE: %s" % Audio.ambiente_nombre(), func():
			if main: flash_message("AMBIENTE: %s" % Audio.ambiente_siguiente(main.current_map))],
		["OJO DE PEZ: %s" % ("—" if bodycam > 0 else ("ON" if ojo_pez else "OFF")), func(): set_ojo_pez(not ojo_pez)],
		["GRANO Y COLOR: %s" % ("—" if bodycam > 0 else ("ON" if grano_sensor else "OFF")), func(): set_grano(not grano_sensor)],
		["AÑADIR BOT DEMO", func(): if main: main.spawn_demo_bot()],
		["BOT QUE APUNTA", func(): if main: main.spawn_bot_apuntando()],
		["BOT CON MAZO", func(): if main: main.spawn_bot_mazo()],
		["BOT QUE SE LIMPIA", func(): if main: main.spawn_bot_limpia()],
		["VIDA INFINITA: %s" % ("ON" if (main and main.player and main.player.vida_infinita) else "OFF"), func(): if main and main.player: main.player.toggle_vida_infinita()],
		["MUNICIÓN INFINITA: %s" % ("ON" if (main and main.player and main.player.municion_infinita) else "OFF"), func(): if main and main.player: main.player.toggle_municion_infinita()],
		["NOCLIP: %s" % ("ON" if (main and main.player and main.player.noclip) else "OFF"), func(): if main and main.player: main.player.toggle_noclip()],
		["OCLUSIÓN VOLUMÉTRICA  (F12)", func(): if main: main.toggle_voxel_ao()],
		["DEPURACIÓN ESTRUCTURAL  (F11)", func(): if main: main.toggle_struct_debug()],
	]
	for t in tools:
		var bt := _menu_button(t[0], Color(0.07, 0.075, 0.09, 0.95), Color(0.88, 0.89, 0.92), 12, 30)
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cb: Callable = t[1]
		bt.pressed.connect(func(): cb.call(); toggle_menu())
		grid.add_child(bt)


## VOLVER AL LOBBY: ESTE NO ES UNA HERRAMIENTA, ES LA PUERTA.
##
## Estaba dentro de la rejilla de herramientas, asi que al esconderla en online el jugador se quedaba
## sin forma de salir de la partida desde el menu. Sale siempre, en las dos ramas, y ademas es lo que
## te desconecta de la sala: `go_to_lobby` llama a `Net.leave()`.
func _boton_volver_al_lobby() -> Button:
	return _fila_menu("salir", "VOLVER AL LOBBY", "sales de la partida y de la sala  ·  F10", Color(0.95, 0.35, 0.30),
		func(): toggle_menu(); if main: main.go_to_lobby())


func _menu_button(text: String, bg: Color, fg: Color, size: int, alto: int = 38) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.custom_minimum_size = Vector2(0, alto)
	b.add_theme_font_override("font", _fuente_menu())
	b.add_theme_font_size_override("font_size", size + 2)     # la letra estrecha es mas pequeña a igual tamaño
	for n in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(n, fg)
	for st in [["normal", bg], ["hover", bg.lightened(0.12)], ["pressed", bg.darkened(0.15)]]:
		b.add_theme_stylebox_override(st[0], _corte_menu(st[1], Color.TRANSPARENT, 0, mini(10, int(alto / 3.0)), 8, 3))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


# --- estilo del menu: el mismo del lobby ------------------------------------
const IconoMenu := preload("res://scripts/icono_lobby.gd")
const ORO_MENU := Color(1.0, 0.78, 0.05)
const LINEA_MENU := Color(1.0, 1.0, 1.0, 0.13)


## La letra estrecha de los titulos del lobby (de sistema: no pesa nada en el APK).
func _fuente_menu() -> Font:
	return LobbyPodio._fuente_titulos()


## Caja con las esquinas de arriba a la izquierda y abajo a la derecha cortadas en diagonal.
func _corte_menu(bg: Color, borde: Color = Color.TRANSPARENT, ancho: int = 0, corte: int = 10, mx: int = 10, my: int = 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = borde
	sb.set_border_width_all(ancho)
	sb.corner_radius_top_left = corte
	sb.corner_radius_bottom_right = corte
	sb.corner_detail = 1
	sb.content_margin_left = mx
	sb.content_margin_right = mx
	sb.content_margin_top = my
	sb.content_margin_bottom = my
	return sb


## UNA FILA DEL MENU: icono en su color, el nombre grande y debajo que hay dentro. El nombre es el TEXTO
## DEL BOTON (las pruebas buscan los botones por su texto: "COMBATE", "SACAR FOTO", "VOLVER AL LOBBY").
func _fila_menu(icono: String, titulo: String, sub: String, acento: Color, al_pulsar: Callable) -> Button:
	var b := Button.new()
	b.text = titulo
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 62)
	b.add_theme_font_override("font", _fuente_menu())
	b.add_theme_font_size_override("font_size", 24)
	for n in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(n, Color.WHITE)
	var normal := _corte_menu(Color(0.05, 0.055, 0.065, 0.95), LINEA_MENU, 1, 12)
	var encima := _corte_menu(Color(0.08, 0.085, 0.10, 0.98), acento, 1, 12)
	var pulsado := _corte_menu(Color(0.02, 0.02, 0.025), acento, 2, 12)
	for st in [normal, encima, pulsado]:
		st.content_margin_left = 66
		st.content_margin_bottom = 20       # el nombre sube y deja sitio a la linea de debajo
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", encima)
	b.add_theme_stylebox_override("pressed", pulsado)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(al_pulsar)
	var ic = IconoMenu.new()
	ic.icono = icono
	ic.color = acento
	ic.anchor_top = 0.5
	ic.anchor_bottom = 0.5
	ic.offset_left = 18
	ic.offset_right = 50
	ic.offset_top = -16
	ic.offset_bottom = 16
	b.add_child(ic)
	var s := Label.new()
	s.text = sub
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_theme_font_size_override("font_size", 12)
	s.add_theme_color_override("font_color", Color(0.62, 0.64, 0.68))
	s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	s.anchor_top = 1.0
	s.anchor_bottom = 1.0
	s.anchor_right = 1.0
	s.offset_left = 67
	s.offset_right = -40
	s.offset_top = -27
	s.offset_bottom = -9
	b.add_child(s)
	var fl := Label.new()
	fl.text = "›"
	fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fl.add_theme_font_override("font", _fuente_menu())
	fl.add_theme_font_size_override("font_size", 34)
	fl.add_theme_color_override("font_color", Color(0.55, 0.57, 0.62))
	fl.anchor_left = 1.0
	fl.anchor_right = 1.0
	fl.anchor_top = 0.5
	fl.anchor_bottom = 0.5
	fl.offset_left = -30
	fl.offset_right = -12
	fl.offset_top = -24
	fl.offset_bottom = 18
	b.add_child(fl)
	return b


func toggle_profiler(on: bool) -> void:
	if profiler_panel:
		profiler_panel.visible = on


## Área segura (notch/redondeos) en píxeles lógicos. Sólo relevante en móvil.
func _compute_safe() -> void:
	safe_l = 0.0; safe_r = 0.0; safe_t = 0.0; safe_b = 0.0
	if not Settings.is_mobile():
		return
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 0 or win.y <= 0:
		return
	var sa := DisplayServer.get_display_safe_area()
	var ratio := root.size / win
	safe_l = sa.position.x * ratio.x
	safe_t = sa.position.y * ratio.y
	safe_r = (win.x - sa.end.x) * ratio.x
	safe_b = (win.y - sa.end.y) * ratio.y


func _layout() -> void:
	var s := root.size
	if s.x <= 0 or s.y <= 0:
		return
	_compute_safe()
	var c := s * 0.5
	crosshair.position = c + _mira_px
	var gap := 7.0
	var len := 11.0
	cross_lines[0].position = Vector2(-1, -gap - len); cross_lines[0].size = Vector2(2, len)
	cross_lines[1].position = Vector2(-1, gap);        cross_lines[1].size = Vector2(2, len)
	cross_lines[2].position = Vector2(-gap - len, -1); cross_lines[2].size = Vector2(len, 2)
	cross_lines[3].position = Vector2(gap, -1);        cross_lines[3].size = Vector2(len, 2)
	hit_marker.position = c + _mira_px
	ammo_label.position = Vector2(s.x - safe_r - 240, s.y - safe_b - 78)
	weapon_label.position = Vector2(s.x - safe_r - 240, s.y - safe_b - 100)
	health_bar.position = Vector2(safe_l + 24, s.y - safe_b - 40)
	if barra_energia:
		barra_energia.position = Vector2(safe_l + 24, s.y - safe_b - 23)
		barra_energia.size = Vector2(260, 15)
	if armor_bar:
		armor_bar.position = Vector2(safe_l + 24, s.y - safe_b - 54)
	if casco_bar:
		casco_bar.position = Vector2(safe_l + 24 + 268, s.y - safe_b - 54)
	if _placa_btn and is_instance_valid(_placa_btn):
		_placa_btn.position = Vector2(safe_l + 24 + 340, s.y - safe_b - 86)
	if curas_label:
		curas_label.position = Vector2(safe_l + 24, s.y - safe_b - 96)
	if cura_bar:
		cura_bar.position = Vector2(c.x - 110, c.y + 90)
		cura_label.position = Vector2(c.x - 110, c.y + 66)
	if escudo_bar:
		escudo_bar.position = Vector2(safe_l + 24, s.y - safe_b - 68)
		escudo_label.position = Vector2(safe_l + 290, s.y - safe_b - 74)
	kills_label.position = Vector2(c.x - 60, safe_t + (112 if score_panel and is_instance_valid(score_panel) else 12))
	# el aviso del objetivo, por DEBAJO del marcador de CS2 (bomba), que es mas bajo que el de los demas modos
	var cs2: bool = score_panel != null and is_instance_valid(score_panel) and not score_panel.has_method("poner")
	objective_label.position = Vector2(c.x - 260, safe_t + (54 if cs2 else 40))
	objective_label.size = Vector2(520, 26)
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if carrier_label and is_instance_valid(carrier_label):
		carrier_label.position = Vector2(c.x - 260, safe_t + (80 if cs2 else 62))
		carrier_label.size = Vector2(520, 22)
	# el boton MENU y el minimapa viven en esa esquina: la calidad se corre a la izquierda para no
	# quedar debajo de ninguno de los dos
	quality_label.position = Vector2(s.x - safe_r - 430, safe_t + 14)
	if fps_label:
		# ARRIBA A LA DERECHA, PEGADO AL BOTON MENU Y PEQUEÑO (2026-10-04, pedido: "en el centro molesta; en una esquina, mas
		# chico o en columnas, y que no lo tape nada en ningun modo"). La esquina de arriba a la izquierda es del registro de
		# bajas, el centro del marcador, abajo los botones del movil; debajo del MENU van el minimapa y las habilidades. Aqui,
		# en lineas cortas alineadas a la derecha, no lo tapa nada (y nunca se mete en el marcador: c.x + 300)
		var fin_x := s.x - safe_r - 164.0
		var ini_x := maxf(c.x + 300.0, fin_x - 250.0)
		fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		fps_label.size = Vector2(fin_x - ini_x, 46)
		fps_label.position = Vector2(ini_x, safe_t + 8)
		# y debajo, lo que mas pesa: termina antes que los botones de habilidad que van bajo el MENU
		if fps_label2:
			var fin2 := s.x - safe_r - 184.0
			fps_label2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			fps_label2.size = Vector2(maxf(60.0, fin2 - ini_x), 46)
			fps_label2.position = Vector2(fin2 - fps_label2.size.x, safe_t + 54)
	message.position = Vector2(c.x - 400, c.y + 110)
	message.size = Vector2(800, 40)
	profiler_panel.position = Vector2(safe_l + 24, safe_t + 60)
	loading_label.position = Vector2(c.x - 300, c.y - 60)
	loading_label.size = Vector2(600, 40)
	loading_bar.position = Vector2(c.x - 210, c.y)
	if carga_partida != null:
		loading_label.visible = false
		var sc: Vector2 = loading_panel.size
		loading_bar.position = Vector2(0, sc.y - 6)
		loading_bar.size = Vector2(sc.x, 6)
	# aviso de acción: justo debajo de la mira
	if action_panel and is_instance_valid(action_panel):
		action_panel.position = Vector2(c.x - 160, c.y + 60)
		action_panel.custom_minimum_size = Vector2(320, 0)
	# barra de armas: abajo en el centro, por encima del área segura
	if weapon_bar and is_instance_valid(weapon_bar):
		var w := float(weapon_cards.size()) * 130.0
		weapon_bar.position = Vector2(c.x - w * 0.5, s.y - safe_b - 84)
		weapon_bar.size = Vector2(w, 74)
	if score_panel and is_instance_valid(score_panel):
		score_panel.position = Vector2(c.x - score_panel.size.x * 0.5, safe_t + 6)
	if killfeed and is_instance_valid(killfeed):
		killfeed.position = Vector2(safe_l + 14, safe_t + 14)
	if feed_box and is_instance_valid(feed_box):
		# en bomba, debajo del boton de la habilidad (que va debajo del minimapa)
		var bomba_hud: bool = main != null and bool(main.get("bomb_mode"))
		feed_box.position = Vector2(s.x - safe_r - 340, safe_t + (350 if bomba_hud else 210))
		feed_box.size = Vector2(320, 120)
	if round_banner and is_instance_valid(round_banner):
		round_banner.position = Vector2(c.x - 400, c.y - 140)
		round_banner.size = Vector2(800, 90)
	if minimap and is_instance_valid(minimap):
		minimap.position = Vector2(s.x - safe_r - 184, safe_t + 72)   # 72 (era 40, luego 64): tocaba con el boton MENU
	if scope_on:
		set_scope(true)
	if carrier_label and is_instance_valid(carrier_label) and carrier_label.text != "":
		refresh_carrier()
	if mobile:
		mobile.set_safe(safe_l, safe_r, safe_t, safe_b)


# ---------------------------------------------------------------------------
# Estado
# ---------------------------------------------------------------------------
## LAS CAPAS DE PANTALLA, ESTRENADAS DURANTE LA CARGA (2026-10-01, medido con bots en la cafeteria). Se montaban la
## primera vez que hacian falta, en plena partida: la onda del primer misil (147 ms: su sombreado compilandose), la
## mira telescopica (su anillo se pinta pixel a pixel, 256x256), la tierra y la sangre en la lente (texturas hechas
## a mano), el calor y el desenfoque. Aqui se montan todas mientras la pantalla de carga lo tapa todo, y las de
## sombreado se dibujan tres fotogramas con fuerza cero (salen igual que la pantalla) para que se compilen ya.
func precalentar_efectos() -> void:
	if root == null:
		return
	var t0 := Time.get_ticks_msec()
	if blood_layer == null:
		_build_blood_layer()
	if dirt_layer == null:
		_build_dirt_layer()
	if scope == null:
		_build_scope()
	if onda_rect == null:
		_build_onda()
	if calor == null:
		_build_calor()
	if mblur == null and Settings.motion_blur > 0.01:
		_build_mblur()
	if loading_panel != null and loading_panel.visible and loading_panel.get_parent() != null:
		loading_panel.get_parent().move_child(loading_panel, -1)   # que la carga siga tapandolo todo
	var encendidas: Array = []
	for r in [onda_rect, calor, mblur]:
		if r != null and is_instance_valid(r) and not (r as CanvasItem).visible:
			(r as CanvasItem).visible = true
			encendidas.append(r)
	print("[hud] capas de pantalla montadas en %d ms" % (Time.get_ticks_msec() - t0))
	for _f in 3:
		await get_tree().process_frame
	for r in encendidas:
		if is_instance_valid(r):
			(r as CanvasItem).visible = false


var _escala_antes_carga := -1.0
const ESCALA_CARGA := 0.25

var carga_partida: Control = null

var _cartel_mapa := false

func set_loading(on: bool) -> void:
	# la sala sigue abierta: la carga se queda (Net.sala_retiene_carga); al arrancar la quita _velo_espera_quitar
	if not on and Net.sala_retiene_carga():
		return
	# EL NOMBRE DEL MAPA AL EMPEZAR (2026-11-01): la primera vez que se quita la carga, el cartel de jugada con el mapa
	if not on and loading_panel.visible and not _cartel_mapa:
		_cartel_mapa = true
		var m = Net.game
		var cm := String(m.get("current_map")) if m != null and is_instance_valid(m) and m.get("current_map") != null else ""
		if cm != "" and cm != "city" and cm != "tutorial":
			get_tree().create_timer(0.6).timeout.connect(func(): anuncio(Settings.map_title(cm).to_upper()))
	loading_panel.visible = on
	# DETRAS DE LA CARGA, EL 3D AL MINIMO (2026-10-15, pedido: "la pantalla de carga va con mucho lag"): el mapa se sigue
	# dibujando detras (asi se compilan los sombreados de los efectos que se precalientan), pero nadie lo ve: a un cuarto
	# de resolucion la GPU queda libre para la carga. Al quitarla vuelve lo que hubiera (si nadie lo cambio entretanto).
	# --cargaresolucion = como antes.
	var vp := get_viewport()
	if vp and not ("--cargaresolucion" in OS.get_cmdline_user_args()):
		if on and _escala_antes_carga < 0.0:
			_escala_antes_carga = vp.scaling_3d_scale
			vp.scaling_3d_scale = ESCALA_CARGA
		elif not on and _escala_antes_carga >= 0.0:
			if is_equal_approx(vp.scaling_3d_scale, ESCALA_CARGA):
				vp.scaling_3d_scale = _escala_antes_carga
			_escala_antes_carga = -1.0
	# los botones TACTILES cuelgan de la capa, fuera de `root` (ver build_mobile_controls), y se dibujaban encima de la carga
	if mobile and is_instance_valid(mobile):
		mobile.visible = not on
	# LA CARGA TAPA TODO (2026-09-23): se creaba ANTES que el minimapa, el boton MENU y los controles tactiles,
	# y lo creado despues se dibuja encima, asi que se veian por encima de la pantalla de carga. Se pasa al
	# frente al mostrarla, y otra vez al final del fotograma por si algo se crea justo despues.
	if on and loading_panel.get_parent() != null:
		loading_panel.get_parent().move_child(loading_panel, -1)
		(func(): if is_instance_valid(loading_panel) and loading_panel.visible and loading_panel.get_parent() != null: loading_panel.get_parent().move_child(loading_panel, -1)).call_deferred()
	# el otro sitio que la devolvia: al acabar de cargar. Con la bodycam puesta, no.
	crosshair.visible = (not on) and bodycam <= 0


func set_progress(p: float) -> void:
	loading_bar.value = p
	loading_label.text = "Generando ciudad y mallando chunks... %d%%" % int(p * 100.0)


var _bots_alive := 0
var _kills := 0

func set_kills(n: int) -> void:
	_kills = n
	_refresh_kills()


## MARCADOR DE OBJETIVO EN EL MUNDO. Un circulo amarillo encima de a donde hay que ir -la caja fuerte
## del atraco, luego el cubo, luego el terminal- que se ve A TRAVES de las paredes, con su nombre y la
## distancia. Si el objetivo queda fuera de la vista, el circulo se pega al borde de la pantalla con una
## flecha hacia donde esta; si esta detras, sale en el borde del lado por el que hay que girar.
##
## Cuelga de la capa y no de `root`: son coordenadas de pantalla de verdad, y `root` se encoge con la
## camara de cuerpo. Va justo encima de `root` y debajo del mando tactil y de los menus. En la foto sin
## interfaz se oculta como el resto.
##
## Quien lo usa lo pide cada cuadro (heist.gd, en _tick_objective): asi sigue al objetivo aunque se mueva.
var _obj_pos := Vector3.ZERO
var _obj_texto := ""
var _obj_activo := false
var _obj_marca: Control = null
## 0..1 mientras alguien abre la caja o ingresa el cubo; -1 si no hay nada cargandose
var _obj_progreso := -1.0
## color de la marca: amarillo para el atraco, rojo para el puesto de empezar oleada del PvE
var _obj_color := Color(1.0, 0.84, 0.1)
var _obj_color_carga := Color(1.0, 1.0, 0.85)

## `progreso`: de 0 a 1 el circulo SE VA LLENANDO, para ver de lejos que alguien esta abriendo la caja
## (o ingresando el cubo). -1 = circulo vacio.
## `color_carga`: el color de la barra redonda. En el atraco es el del EQUIPO que esta abriendo la caja o
## al que es el ingreso, asi que se ve de un vistazo QUIEN esta cargando y cuanto le falta.
func set_objetivo_mundo(pos: Vector3, texto: String, progreso: float = -1.0,
		color: Color = Color(1.0, 0.84, 0.1), color_carga: Color = Color(1.0, 1.0, 0.85)) -> void:
	_obj_pos = pos
	_obj_texto = texto
	_obj_progreso = progreso
	_obj_color = color
	_obj_color_carga = color_carga
	_obj_activo = true
	if _obj_marca == null or not is_instance_valid(_obj_marca):
		_obj_marca = Control.new()
		_obj_marca.name = "MarcaObjetivo"
		_obj_marca.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_obj_marca.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_obj_marca)
		move_child(_obj_marca, root.get_index() + 1)
		_obj_marca.draw.connect(_dibujar_objetivo)
	_obj_marca.visible = true
	_obj_marca.queue_redraw()


func quitar_objetivo_mundo() -> void:
	_obj_activo = false
	if _obj_marca and is_instance_valid(_obj_marca):
		_obj_marca.visible = false


func _dibujar_objetivo() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not _obj_activo:
		return
	# PEGADO AL OBJETIVO NO HACE FALTA: a menos de 4 m ya sale el panel de accion ("ABRIENDO LA CAJA")
	# con su propia barra, y el circulo quedaba justo encima de el, en el centro de la pantalla. Quien
	# mira desde lejos lo sigue viendo.
	if cam.global_position.distance_to(_obj_pos) < 4.0:
		return
	var tam: Vector2 = get_viewport().get_visible_rect().size
	var centro := tam * 0.5
	var margen := 48.0
	var detras: bool = cam.is_position_behind(_obj_pos)
	var p: Vector2 = cam.unproject_position(_obj_pos)
	if detras:
		p = tam - p          # detras: se refleja, para que el borde elegido sea el del lado a girar
	var zona := Rect2(Vector2(margen, margen), tam - Vector2(margen, margen) * 2.0)
	var en_vista: bool = (not detras) and zona.has_point(p)
	var dir := (p - centro)
	if dir.length() < 0.001:
		dir = Vector2(0, 1)
	if not en_vista:
		var esc: float = minf((centro.x - margen) / maxf(absf(dir.x), 0.001), (centro.y - margen) / maxf(absf(dir.y), 0.001))
		p = centro + dir * esc
	# MIENTRAS CARGA, TODO EL INDICADOR VA DEL COLOR DE QUIEN CARGA (aro, punto y texto): la barra sola
	# era un hilo que no se distinguia del aro amarillo de siempre.
	var amarillo := _obj_color_carga if _obj_progreso >= 0.0 else _obj_color
	var sombra := Color(0, 0, 0, 0.55)
	var pulso: float = 1.0 + 0.12 * sin(Time.get_ticks_msec() * 0.005)
	# con carga en marcha el circulo crece: es lo que hay que poder leer de lejos
	var r: float = (22.0 if _obj_progreso >= 0.0 else 16.0) * pulso
	_obj_marca.draw_arc(p, r, 0.0, TAU, 40, sombra, 7.0, true)
	_obj_marca.draw_arc(p, r, 0.0, TAU, 40, amarillo, 3.5, true)
	_obj_marca.draw_circle(p, 4.0, amarillo)
	# LA CARGA: un arco blanco que da la vuelta desde arriba, en el sentido de las agujas del reloj
	if _obj_progreso >= 0.0:
		var k: float = clampf(_obj_progreso, 0.0, 1.0)
		# la barra redonda POR FUERA del aro, gruesa, sobre su carril oscuro
		var rb: float = r + 10.0
		_obj_marca.draw_arc(p, rb, 0.0, TAU, 56, Color(0, 0, 0, 0.6), 10.0, true)
		_obj_marca.draw_arc(p, rb, 0.0, TAU, 56, Color(1, 1, 1, 0.14), 6.0, true)
		if k > 0.001:
			_obj_marca.draw_arc(p, rb, -PI * 0.5, -PI * 0.5 + TAU * k, 56, _obj_color_carga, 7.0, true)
	if not en_vista:
		var d := dir.normalized()
		var lado := Vector2(-d.y, d.x) * 8.0
		var base := p + d * (r + 4.0)
		var punta := p + d * (r + 16.0)
		_obj_marca.draw_colored_polygon(PackedVector2Array([punta, base + lado, base - lado]), amarillo)
	var dist: float = cam.global_position.distance_to(_obj_pos)
	# sin texto (la campaña): solo los metros, pequeños
	var txt := ("%s · %d m" % [_obj_texto, int(dist)]) if _obj_texto != "" else "%d m" % int(dist)
	if _obj_progreso >= 0.0:
		txt += " · %d %%" % int(clampf(_obj_progreso, 0.0, 1.0) * 100.0)
	var f := ThemeDB.fallback_font
	var fs := 15 if _obj_texto != "" else 13
	var w: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tp := p + Vector2(-w * 0.5, r + (34.0 if _obj_progreso >= 0.0 else 22.0))
	tp.x = clampf(tp.x, 6.0, tam.x - w - 6.0)
	tp.y = clampf(tp.y, 20.0, tam.y - 8.0)
	_obj_marca.draw_string_outline(f, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.8))
	_obj_marca.draw_string(f, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, amarillo)


## MARCADOR DEL ATRACO EN LA CIUDAD: arriba a la izquierda, los tres equipos en columna con sus puntos,
## y EL QUE VA GANANDO, ARRIBA. A igualdad se respeta el orden de siempre (amarillo, azul, violeta) para
## que las filas no bailen cuando todos van a cero. Tu equipo sale en dorado con "(tu)".
var _puntos_panel: PanelContainer = null
var _puntos_lista: VBoxContainer = null

func set_puntos_equipos(puntos: Dictionary, objetivo: int) -> void:
	if _puntos_panel == null or not is_instance_valid(_puntos_panel):
		_puntos_panel = PanelContainer.new()
		_puntos_panel.name = "PuntosEquipos"
		_puntos_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.035, 0.045, 0.80)
		sb.set_corner_radius_all(5)
		sb.set_border_width_all(1)
		sb.border_color = Color(0.35, 0.38, 0.45, 0.7)
		sb.set_content_margin_all(10)
		_puntos_panel.add_theme_stylebox_override("panel", sb)
		_puntos_panel.position = Vector2(18, 14)
		root.add_child(_puntos_panel)
		_puntos_lista = VBoxContainer.new()
		_puntos_lista.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_puntos_lista.add_theme_constant_override("separation", 4)
		_puntos_panel.add_child(_puntos_lista)
	for c in _puntos_lista.get_children():
		_puntos_lista.remove_child(c)
		c.queue_free()
	_puntos_lista.add_child(_texto("ATRACO · gana quien llegue a %d" % objetivo, 13, Color(0.72, 0.76, 0.85), false))
	var orden: Array = Net.equipos.duplicate()
	orden.sort_custom(func(a, b) -> bool:
		var pa := int(puntos.get(a, 0))
		var pb := int(puntos.get(b, 0))
		if pa != pb:
			return pa > pb
		return Net.equipos.find(a) < Net.equipos.find(b))
	for eq in orden:
		var fila := HBoxContainer.new()
		fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fila.add_theme_constant_override("separation", 8)
		var muestra := ColorRect.new()
		muestra.color = Net.color_equipo(eq)
		muestra.custom_minimum_size = Vector2(12, 12)
		muestra.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		muestra.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fila.add_child(muestra)
		var yo: bool = eq == Net.my_team()
		var nombre := _texto(Net.nombre_equipo(eq) + ("  (tú)" if yo else ""), 16, Color(1.0, 0.83, 0.0) if yo else Color.WHITE, false)
		nombre.custom_minimum_size = Vector2(200, 0)
		fila.add_child(nombre)
		var pts := _texto("%d puntos" % int(puntos.get(eq, 0)), 16, Net.color_equipo(eq).lerp(Color.WHITE, 0.35), false)
		pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pts.custom_minimum_size = Vector2(100, 0)
		fila.add_child(pts)
		_puntos_lista.add_child(fila)


func set_objective(t: String, inside: bool) -> void:
	objective_label.text = t
	objective_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6) if inside else Color(1.0, 0.9, 0.55))


func set_bots_alive(n: int) -> void:
	_bots_alive = n
	_refresh_kills()


func _refresh_kills() -> void:
	# LOS PUNTOS DE LA PARTIDA, EN VIVO (puntuacion.gd): los mismos que salen luego en MEJORES JUGADORES
	var pts: int = preload("res://scripts/puntuacion.gd").puntos(Net.nombre_propio())
	kills_label.text = "Puntos: %d  ·  Bajas: %d  ·  Bots vivos: %d" % [pts, _kills, _bots_alive]


func set_bots_state(_on: bool) -> void:
	pass   # el estado se lee de Settings al abrir el menú


func set_quality_name(n: String) -> void:
	quality_name = n
	quality_label.text = "Calidad %s" % n


## FOTO SIN INTERFAZ. Se oculta todo lo que es INTERFAZ -mira, municion, vida, minimapa, marcador,
## mensajes, botones tactiles, paneles, el REC de la camara de cuerpo y los nombres sobre los bots- y
## se deja lo que es CAMARA: el ojo de pez, el agua y la sangre en la lente, la vineta. Eso es parte de
## lo que se ve, no de la interfaz.
##
## EL ARMA TAMBIEN SE VA, y la foto se saca a maxima calidad y sin el desenfoque de enfoque: lo pidio
## el usuario ("que se oculte el arma... y todo al ultra, saca la foto y vuelve a mi configuracion").
## De eso se encarga main.foto_modo_max() / foto_modo_restaurar().
##
## Se oculta, se esperan dos cuadros ya dibujados sin interfaz, se captura, y se devuelve a cada cosa la
## visibilidad QUE TENIA (no un `true` a ciegas: hay capas que estaban apagadas a proposito).
##
## Donde se guarda: en la carpeta Imagenes del sistema, en Breach/. Si no se puede escribir ahi (en
## Android sin permiso de almacenamiento), en la carpeta del juego. El aviso dice la ruta exacta.
const CAPAS_CAMARA := ["mblur", "blood_layer", "dirt_layer", "fog_rect", "calor", "onda_rect", "ojo_rect",
	"ojo_copia", "lluvia_rect", "lluvia_copia", "aberration", "aberration_copia", "calor_copia", "onda_copia",
	"damage_rect", "vignette", "scope"]
var _fotografiando := false
var ultima_foto := ""

func sacar_foto() -> void:
	if _fotografiando:
		return
	_fotografiando = true
	if menu_panel:
		toggle_menu()
	# EL MODO MAXIMO, ANTES DE ESCONDER NADA. Al reves no vale: aplicar la calidad vuelve a tocar la
	# interfaz (lente, viñeta, nombre de la calidad) y lo que ya estaba escondido reaparecia, asi que
	# la foto salia con la mira y la municion puestas.
	var prev := {}
	if main != null and is_instance_valid(main) and main.has_method("foto_modo_max"):
		prev = main.foto_modo_max()
		# sin esperar a nada (pedido: "lo mas rapido que de el celular"): las distancias no cambian, asi que no hay
		# mallas nuevas que esperar; un solo cuadro para que se dibuje ya con la calidad maxima
		await get_tree().process_frame
	var camara := {}
	for k in CAPAS_CAMARA:
		var n = get(k)
		if n != null and is_instance_valid(n):
			camara[n] = true
	var apagados: Array = []
	for c in root.get_children():
		if c is CanvasItem and not camara.has(c) and (c as CanvasItem).visible:
			apagados.append(c)
	for c in get_children():
		if c != root and c is CanvasItem and (c as CanvasItem).visible:
			apagados.append(c)
	for b in get_tree().get_nodes_in_group("bots"):
		if "_tag" in b and b._tag != null and is_instance_valid(b._tag) and b._tag.visible:
			apagados.append(b._tag)
	for n in [fps_label, fps_label2, boton_habilidad, boton_blindaje, barra_energia]:
		if n != null and is_instance_valid(n) and (n as CanvasItem).visible and not apagados.has(n):
			apagados.append(n)
	for n in apagados:
		n.visible = false
	# el HUD vuelve a encender cosas en su _process (el contador de FPS, la habilidad...): se apagan otra vez JUSTO
	# antes de dibujar el cuadro de la foto (bug: "en las fotos se ve la habilidad y el contador amarillo")
	var nodos3d: Array = prev.get("nodos", [])
	var reapagar := func():
		for n in apagados:
			if is_instance_valid(n):
				n.visible = false
		for n in nodos3d:
			if is_instance_valid(n):
				(n as Node3D).visible = false
	RenderingServer.frame_pre_draw.connect(reapagar)
	await RenderingServer.frame_post_draw
	RenderingServer.frame_pre_draw.disconnect(reapagar)
	var img := get_viewport().get_texture().get_image()
	if main != null and is_instance_valid(main) and main.has_method("foto_modo_restaurar"):
		main.foto_modo_restaurar(prev)
	for n in apagados:
		if is_instance_valid(n):
			n.visible = true
	_fotografiando = false
	_destello()
	flash_message("Foto guardada")      # sin la ruta (pedido); se ven en la GALERIA del lobby
	ultima_foto = _guardar_foto(img)


## EN ANDROID, A LA GALERIA. Sin el permiso de almacenamiento la escritura en Pictures fallaba en silencio y la
## foto acababa en la carpeta privada de la app (user://fotos), que la galeria no ve. Ahora se pide el permiso la
## primera vez (y se espera la respuesta) y se guarda en Pictures/Breach; la galeria la muestra en cuanto
## vuelve a escanear (al abrirla). Si aun asi no se puede, se avisa de donde quedo.
var _permiso_fotos_pedido := false
const CARPETA_FOTOS := "user://fotos"     ## la que lee la galeria del lobby (galeria_fotos.gd)

## Guarda en un hilo (codificar un PNG grande en el movil eran cientos de ms en el hilo principal) y devuelve la ruta
func _guardar_foto(img: Image) -> String:
	var nombre := "breach_%s.png" % Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var android := OS.get_name() == "Android"
	if android and not _permiso_fotos_pedido:
		_permiso_fotos_pedido = true
		OS.request_permissions()            # sin esperar: si aun no esta, esta foto se queda solo en la galeria del juego
	DirAccess.make_dir_recursive_absolute(CARPETA_FOTOS)
	var ruta := CARPETA_FOTOS.path_join(nombre)
	var imagenes := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	var fuera := "" if imagenes == "" else imagenes.path_join("Breach")
	WorkerThreadPool.add_task(func():
		var err := img.save_png(ruta)
		if err != OK:
			print("[foto] no se pudo guardar (error %d)" % err)
			return
		if fuera != "":
			DirAccess.make_dir_recursive_absolute(fuera)
			if img.save_png(fuera.path_join(nombre)) == OK and android:
				call_deferred("_registrar_en_galeria", ProjectSettings.globalize_path(fuera.path_join(nombre))))
	return ProjectSettings.globalize_path(ruta)


## Que la galeria de Android se entere YA: sin esto el archivo existe pero no aparece hasta que el sistema
## vuelve a escanear. Se llama a MediaScannerConnection.scanFile por el puente Java de Godot; si el puente no
## esta (PC, o una version sin el), no pasa nada.
func _registrar_en_galeria(ruta: String) -> void:
	if not Engine.has_singleton("JavaClassWrapper"):
		return
	var wrapper = Engine.get_singleton("JavaClassWrapper")
	var scanner = wrapper.wrap("android.media.MediaScannerConnection")
	var hilo = wrapper.wrap("android.app.ActivityThread")
	if scanner == null or hilo == null:
		return
	var app = hilo.currentApplication()
	if app == null:
		return
	scanner.scanFile(app, PackedStringArray([ruta]), null, null)


func _destello() -> void:
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 0.55)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	var tw := r.create_tween()
	tw.tween_property(r, "color:a", 0.0, 0.25)
	tw.tween_callback(r.queue_free)


## LOS TEXTOS DEL MEDIO, FUERA (2026-10-12, pedido: "Rendimiento: resolucion dinamica ajustada y los textos que salen en
## ese mismo lugar, quitalos"). Solo se queda lo que se pidio que siga (MENSAJES_QUE_QUEDAN). --conmensajes = todos.
const MENSAJES_QUE_QUEDAN := ["¡TE HAN REVIVIDO!"]
static var _con_mensajes: int = -1

## EL CARTEL DE JUGADA (2026-11-01): derrumbes, medallas, rondas, "eres el ultimo"... Arriba en el centro, grande, entra
## con un golpe de escala y se va solo. NO es flash_message (los textos del medio se quitaron a peticion el 2026-10-12):
## es su propio canal y se apaga en AJUSTES > CONTROLES > "Avisos de jugadas" (Settings.avisos_jugada).
var _anuncio: Label = null
var _anuncio_tw: Tween = null

func anuncio(t: String) -> void:
	if not Settings.avisos_jugada:
		return
	if _anuncio == null or not is_instance_valid(_anuncio):
		_anuncio = Label.new()
		_anuncio.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_anuncio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_anuncio.add_theme_font_override("font", preload("res://scripts/fuentes.gd").de(800, false))
		_anuncio.add_theme_font_size_override("font_size", 34)
		_anuncio.add_theme_color_override("font_color", Color(1.0, 0.86, 0.3))
		_anuncio.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.0, 0.9))
		_anuncio.add_theme_constant_override("outline_size", 10)
		_anuncio.size = Vector2(1100, 50)
		_anuncio.pivot_offset = Vector2(550, 25)
		add_child(_anuncio)
	var vs: Vector2 = get_viewport().get_visible_rect().size
	_anuncio.position = Vector2(vs.x * 0.5 - 550.0, vs.y * 0.17)
	_anuncio.text = t
	if _anuncio_tw and _anuncio_tw.is_valid():
		_anuncio_tw.kill()
	_anuncio.modulate.a = 1.0
	_anuncio.scale = Vector2(1.35, 1.35)
	_anuncio_tw = _anuncio.create_tween().set_ignore_time_scale(true)
	_anuncio_tw.tween_property(_anuncio, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_anuncio_tw.tween_interval(2.2)
	_anuncio_tw.tween_property(_anuncio, "modulate:a", 0.0, 0.5)


func flash_message(t: String) -> void:
	if _con_mensajes < 0:
		_con_mensajes = 1 if "--conmensajes" in OS.get_cmdline_user_args() else 0
	# (en los modos zombi y la campaña siguen: alli cuentan la historia y lo que hay que hacer)
	var juego = Net.game
	var zombis: bool = juego != null and is_instance_valid(juego) and "pve" in juego and juego.pve != null
	if _con_mensajes == 0 and not zombis and not (t in MENSAJES_QUE_QUEDAN):
		return
	message.text = t
	message.modulate.a = 1.0
	msg_t = 3.5


func _on_ammo(mag: int, res: int, wname: String) -> void:
	# el cuerpo a cuerpo no gasta munición
	if player and is_instance_valid(player) and player.current < Weapons.LIST.size() and bool(Weapons.LIST[player.current].get("melee", false)):
		ammo_label.text = "∞"
	else:
		ammo_label.text = "%d / %d" % [mag, res]
	weapon_label.text = wname
	refresh_weapon_bar()


## Chaleco puesto (0..100). La barra azul solo esta a la vista mientras quede algo.
var escudo_bar: ProgressBar
var escudo_label: Label
var _escudo_on := false

## La vida del escudo. `on`: lo llevas en la mano (roto o sin sacar, la barra no se ve).
func set_escudo(v: float, on: bool) -> void:
	_escudo_on = on
	if escudo_bar == null or not is_instance_valid(escudo_bar):
		return
	escudo_bar.value = v
	escudo_bar.visible = on
	escudo_label.visible = on
	escudo_label.text = "ESCUDO  %d" % int(ceilf(v))
	# cuando le queda poco se pone rojo: esta a punto de reventar
	var fill := escudo_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill:
		fill.bg_color = Color(0.80, 0.84, 0.88, 0.92) if v > 150.0 else Color(0.95, 0.35, 0.25, 0.95)


func set_armor(a: float) -> void:
	if armor_bar == null or not is_instance_valid(armor_bar):
		return
	if _placas_on:
		armor_bar.max_value = 150.0
		armor_bar.value = a
		armor_bar.visible = true
		return
	# LA BARRA SE ESTIRA SI TE PASAS. En el PvE la armadura se acumula sin tope, asi que con 300 la
	# barra se quedaba clavada al maximo y no habia forma de saber cuanta llevabas. El maximo de la
	# barra sube al siguiente multiplo de 100 y el numero se enseña aparte.
	if a > armor_bar.max_value:
		armor_bar.max_value = ceilf(a / 100.0) * 100.0
	elif a <= 100.0 and armor_bar.max_value > 100.0:
		armor_bar.max_value = 100.0
	armor_bar.value = a
	armor_bar.visible = a > 0.01


## Cuantas vendas y botiquines llevas. `on`: el mapa tiene botin (en los demas no se enseña nada).
func set_curas(vendas: int, botiquines: int, on: bool) -> void:
	if curas_label == null or not is_instance_valid(curas_label):
		return
	_curas_on = on
	var t := "VENDAS %d   ·   BOTIQUINES %d" % [vendas, botiquines]     # (sin "[7] [8] [H]": sin letras de teclas)
	curas_label.text = t
	curas_label.visible = on


## La barra de curarse: `k` de 0 a 1, o negativo para quitarla.
func set_cura(k: float, texto: String) -> void:
	if cura_bar == null or not is_instance_valid(cura_bar):
		return
	var on := k >= 0.0
	cura_bar.visible = on
	cura_label.visible = on
	if on:
		cura_bar.value = k
		cura_label.text = "%s  %.1f s" % [texto, maxf(0.0, (1.0 - k) * (3.0 if texto == "VENDANDO" else 6.0))]


func set_casco(c: float) -> void:
	if casco_bar == null or not is_instance_valid(casco_bar):
		return
	casco_bar.value = c
	casco_bar.visible = c > 0.01


func _on_health(h: float) -> void:
	# la barra llena es la vida maxima del modo (300, o 100 en el PvE), no un 100 fijo
	if player and is_instance_valid(player) and player.has_method("vida_max"):
		health_bar.max_value = player.vida_max()
	health_bar.value = h


func update_stats(stats: Dictionary, quality: int) -> void:
	last_stats = stats
	last_quality = quality


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not loading_panel.visible:
		if combat_panel and is_instance_valid(combat_panel):
			open_combat_panel()
		else:
			toggle_menu()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_profiler"):
		if not Settings.herramientas():
			return                        # online, F3 no hace nada (es de pruebas)
		profiler_panel.visible = not profiler_panel.visible
		Settings.show_profiler = profiler_panel.visible
		Settings.save()
	elif event.is_action_pressed("toggle_csv"):
		if not Settings.herramientas():
			return                        # online, F4 tampoco
		if csv:
			stop_csv()
			flash_message("CSV cerrado")
		else:
			start_csv("manual")
			flash_message("Grabando CSV en user://")


func _process(dt: float) -> void:
	var _pt0 := Time.get_ticks_usec()
	_process_inner(dt)
	Prof.add("hud", Time.get_ticks_usec() - _pt0)


## EL CONTADOR DE FPS, CON LO QUE HACE FALTA PARA SABER POR QUE NO SUBE (2026-09-22: en un movil seguia
## en 30 con todo al minimo). "tope" es Engine.max_fps (0 = sin tope), "Hz" el refresco de la pantalla,
## "vs" la sincronizacion vertical, y GPU/CPU los ms del ultimo medio segundo. Si la GPU pasa de ~16 ms el
## limite es la grafica; si la GPU va holgada y sigue en 30, lo esta limitando el ritmo de Android.
## EL CONTADOR (F3 / ajustes). SIN NUMEROS DE MENTIRA (2026-10-04, pedido): antes decia "CPU 119 ms (guion 119 · fisica
## ...)" yendo a 115 fps, porque sumaba los monitores TIME_PROCESS y TIME_PHYSICS_PROCESS, que en esta maquina salen
## mayores que el fotograma entero (no miden coste: ver CLAUDE.md). Ahora solo lo que se mide de verdad:
##   fotograma   el tiempo REAL entre fotogramas (media y el peor del medio segundo: los tirones)
##   GPU         lo que tarda la tarjeta en dibujar (RenderingServer)
##   dibujo      lo que tarda la CPU en mandar a dibujar (RenderingServer)
##   y debajo, lo que mas pesa del juego medido con Prof (reloj de pared por fase)
var _fps_t := 0.0
var _fps_n := 0
var _fps_gpu := 0.0
var _fps_mide := false
var _fps_rcpu := 0.0
var _fps_dt := 0.0
var _fps_peor := 0.0
var _fps_prof := {}


func _fps_diag(dt: float) -> void:
	var vp_rid := get_viewport().get_viewport_rid()
	if not _fps_mide:
		_fps_mide = true
		RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	_fps_t += dt
	_fps_n += 1
	_fps_dt += dt * 1000.0
	_fps_peor = maxf(_fps_peor, dt * 1000.0)
	if _fps_n % 4 == 0:      # 1 de cada 4 (x4): pedirlo cada cuadro sincroniza el hilo de render separado
		_fps_gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid) * 4.0
		_fps_rcpu += RenderingServer.viewport_get_measured_render_time_cpu(vp_rid) * 4.0
	if _fps_t < 0.5:
		return
	var n := float(_fps_n)
	# LO QUE MAS PESA DEL GUION en este medio segundo (Prof acumula microsegundos por fase desde el arranque)
	var sube: Array = []
	for k in Prof.acc.keys():
		var d: float = float(int(Prof.acc[k]) - int(_fps_prof.get(k, 0))) / 1000.0 / n
		if d >= 0.3:
			sube.append([d, String(k)])
	_fps_prof = Prof.acc.duplicate()
	sube.sort_custom(func(x, y): return x[0] > y[0])
	var top := PackedStringArray()
	for e in sube.slice(0, 5):
		top.append("%s %.1f" % [e[1], e[0]])
	# en lineas cortas (la columna de la esquina): lo de siempre arriba y lo que mas pesa, una cosa por linea (3 como mucho)
	fps_label.text = "%d FPS · %.1f ms (peor %.0f)\nGPU %.1f · dibujo %.1f ms\n%d Hz · tope %d · vs %d" % [
		roundi(n / maxf(0.001, _fps_t)), _fps_dt / n, _fps_peor,   # (los fps, del mismo medio segundo)
		_fps_gpu / n, _fps_rcpu / n,
		roundi(DisplayServer.screen_get_refresh_rate()), Engine.max_fps, DisplayServer.window_get_vsync_mode()]
	if fps_label2:
		fps_label2.text = "\n".join(top.slice(0, 3))
	_fps_t = 0.0
	_fps_n = 0
	_fps_gpu = 0.0
	_fps_rcpu = 0.0
	_fps_dt = 0.0
	_fps_peor = 0.0

func _process_inner(dt: float) -> void:
	# LA CARGA TAPA TODO, SIEMPRE (2026-10-04): lo que se monta mientras esta puesta (la barra de armas se rehace al cargar
	# el equipo; los botones...) se añade detras y se dibujaba ENCIMA de la pantalla de carga y de la espera
	if loading_panel != null and loading_panel.visible:
		var pa := loading_panel.get_parent()
		if pa != null and loading_panel.get_index() != pa.get_child_count() - 1:
			pa.move_child(loading_panel, -1)
	# la marca del objetivo sigue a la camara aunque nadie la vuelva a pedir (la campana la pone una vez).
	# Un fotograma si y otro no: a 60 fps no se nota y cuesta la mitad
	if _obj_activo and _obj_marca and is_instance_valid(_obj_marca):
		_obj_marca.queue_redraw()
	if fps_label:
		fps_label.visible = show_fps
		if fps_label2:
			fps_label2.visible = show_fps
		if show_fps:
			_fps_diag(dt)
	# MIRA TELESCÓPICA: sólo con el francotirador y apuntando. Oculta la mira normal.
	var want_scope: bool = (player != null and is_instance_valid(player) and player.aiming
		and player.current < Weapons.LIST.size()
		and String(Weapons.LIST[player.current].get("sound", "")) == "sniper" and not player.spectating)
	if want_scope != scope_on:
		set_scope(want_scope)
	# al apuntar, la mira holográfica del arma sustituye a la retícula del HUD
	if player and crosshair and not loading_panel.visible:
		# ...Y CON LA CAMARA DE CUERPO, NUNCA. Esta linea corre CADA CUADRO, asi que era la que mandaba
		# de verdad: se podia esconder la mira en el respawn, al acabar de cargar y al encender la
		# bodycam, que al cuadro siguiente esta la devolvia. Perseguir las llamadas puntuales no
		# servia de nada mientras existiera un escritor por frame.
		# (2026-10-02, pedido) NI MUERTO NI ESPECTANDO (en la camara del caido salia en medio de la pantalla) y, MIENTRAS
		# SALE EL MARCADOR DE ACIERTO (las rayas blancas, rojas en la cabeza, doradas al matar), la mira se aparta: vuelve
		# cuando el marcador se va
		crosshair.visible = (bodycam <= 0) and not player.aiming and not scope_on and player.get("agarre") == null 			and not bool(player.get("spectating")) and float(player.get("health")) > 0.0 and hit_t <= 0.0
	# la ranura de la C4 aparece al recogerla y desaparece al plantarla o soltarla: se mira aqui en
	# vez de en cada sitio que la da o la quita, que son varios y es facil olvidarse de uno
	if weapon_bar and is_instance_valid(weapon_bar) and player and is_instance_valid(player):
		if player.has_c4() != _bar_con_c4:
			build_weapon_bar()
	if hit_t > 0.0:
		hit_t -= dt
		hit_marker.visible = hit_t > 0.0
	# EL MARCADOR COLGADO (--diagvivo). Si las cuatro rayas siguen puestas con el reloj a cero es que
	# alguien las encendio por fuera de aqui, o que este _process se quedo parado mientras contaba.
	elif hit_marker != null and is_instance_valid(hit_marker) and hit_marker.visible:
		if _diag_vivo:
			print("[vivo] EL MARCADOR DE ACIERTO SE HA QUEDADO PUESTO (reloj %.3f): lo apago" % hit_t)
		hit_marker.visible = false
	if msg_t > 0.0:
		msg_t -= dt
		message.modulate.a = clampf(msg_t, 0.0, 1.0)
	if action_t > 0.0:
		action_t -= dt
		if action_t <= 0.0 and action_panel:
			action_panel.visible = false
	if round_banner_t > 0.0 and round_banner and is_instance_valid(round_banner):
		round_banner_t -= dt
		round_banner.modulate.a = clampf(round_banner_t, 0.0, 1.0)
		if round_banner_t <= 0.0:
			round_banner.text = ""
	_update_damage_arcs(dt)
	_update_lens(dt)
	_update_onda(dt)
	if bodycam > 0:
		_update_rec(dt)
	if ojo_rect == null and (ojo_pez or grano_sensor):
		_build_ojo()
	elif ojo_rect:
		_ojo_orden()
	if not _drops.is_empty():
		_update_blood(dt)
	if vignette and player and is_instance_valid(player):
		# rojo creciente por debajo del 60 % de vida
		var h: float = clampf(float(player.health) / (player.vida_max() if player.has_method("vida_max") else 100.0), 0.0, 1.0)
		var want: float = clampf((0.6 - h) / 0.6, 0.0, 1.0) * 0.85
		if bool(player.get("spectating")):
			want = 0.0          # muerto y mirando a un compañero: sin el rojo de la muerte encima de su vista
		vignette.modulate.a = lerpf(vignette.modulate.a, want, clampf(4.0 * dt, 0.0, 1.0))
	if aberration:
		aberration.visible = damage_t > 0.0
		if damage_t > 0.0:
			(aberration.material as ShaderMaterial).set_shader_parameter("amount", clampf(damage_t * 2.5, 0.0, 1.0))
	if damage_t > 0.0:
		damage_t -= dt
		damage_rect.color.a = clampf(damage_t, 0.0, 0.4) * 0.8
		damage_rect.visible = damage_rect.color.a > 0.004 and not _fotografiando
	elif damage_rect.visible:
		damage_rect.visible = false
	stats_t += dt
	if profiler_panel.visible and stats_t >= 0.25:
		stats_t = 0.0
		profiler_label.text = _profiler_text()
	if csv:
		var _t0 := Time.get_ticks_usec()
		_csv_row(dt)
		if player and player.get_parent().has_method("_probe_report"):
			player.get_parent()._probe_report("hud.csv", Time.get_ticks_usec() - _t0)


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "." + out
	return out


func _profiler_text() -> String:
	var vp := get_viewport().get_viewport_rid()
	var fps := Engine.get_frames_per_second()
	var frame_ms := 1000.0 / maxf(float(fps), 1.0)
	var proc_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(vp)
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var mem := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var vram := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var objs := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
	var dc := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	var phys_active := int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
	var s := last_stats
	var lines := PackedStringArray()
	lines.append("FPS %d   frame %.1f ms   (process %.1f · physics %.1f)" % [fps, frame_ms, proc_ms, phys_ms])
	lines.append("Render CPU %.2f ms   GPU %.2f ms   draw calls %d   objetos %d   triángulos %s" % [cpu, gpu, dc, objs, _thousands(prims)])
	lines.append("RAM %.0f MB   VRAM %.0f MB   física activa %d   %s" % [mem, vram, phys_active, RenderingServer.get_video_adapter_name()])
	if not s.is_empty():
		lines.append("--- vxcore [%s]%s ---" % [s.get("quality", "?"), "  CARGANDO" if s.get("loading", false) else ""])
		lines.append("chunks %d (cerca %d · regiones LOD %d · tris %s · LOD %.0f m · render %.0f m)   voxels %s   destruidos %s   mundo %.1f MB" % [
			s.get("chunks", 0), s.get("chunks_visible", 0), s.get("regions_visible", 0), _thousands(int(s.get("tris_visible", 0))),
			s.get("lod_distance", 0.0), s.get("render_distance", 0.0),
			_thousands(int(s.get("voxels_solid", 0))), _thousands(int(s.get("voxels_destroyed", 0))), s.get("mem_world_mb", 0.0)])
		lines.append("jobs %d   resultados %d   subidas/frame %d   física: cola %d, %d/frame" % [
			s.get("jobs_pending", 0), s.get("mesh_results_pending", 0), s.get("uploads_frame", 0), s.get("phys_queue", 0), s.get("phys_updates_frame", 0)])
		lines.append("cuerpos %d (rigid %d · cheap %d)   piezas %d   diminutas %d   re-vox %d   escombros %d/%d" % [
			s.get("bodies_active", 0), s.get("bodies_rigid", 0), s.get("bodies_cheap", 0), s.get("pieces_total", 0),
			s.get("tiny_pieces", 0), s.get("revoxelized", 0), s.get("debris_active", 0), s.get("debris_capacity", 0)])
		lines.append("ms: update %.2f   carve %.3f   malla(job) %.2f / máx %.1f   conn %.2f   solve %.3f   extract %.2f   A* %.2f   host %.2f / máx %.2f" % [
			s.get("t_update_ms", 0.0), s.get("t_carve_ms", 0.0), s.get("t_mesh_job_ms", 0.0), s.get("t_mesh_job_max_ms", 0.0),
			s.get("t_conn_ms", 0.0), s.get("t_solve_ms", 0.0), s.get("t_extract_ms", 0.0), s.get("t_nav_ms", 0.0),
			s.get("t_host_ms", 0.0), s.get("t_host_max_ms", 0.0)])
		lines.append("estructura: %s  iteraciones %d  islas %d (saltadas %d)  celdas %d  fallos %d  fragmentos %d  peor ratio %.2f  %.2f ms/it (máx %.1f)   trozos %.1f ms   rayos %s (pasos %s · saltos %s)   chunks sin lock %d" % [
			"ACTIVA" if s.get("struct_active", 0) > 0 else "dormida", s.get("struct_iterations", 0), s.get("struct_islands", 0), s.get("struct_islands_skipped", 0),
			s.get("struct_cells", 0), s.get("struct_failures", 0), s.get("struct_fragments", 0), s.get("struct_worst_ratio", 0.0),
			s.get("t_struct_ms", 0.0), s.get("t_struct_max_ms", 0.0), s.get("t_clumps_ms", 0.0),
			_thousands(int(s.get("rays_traced", 0))), _thousands(int(s.get("ray_steps", 0))), _thousands(int(s.get("ray_skips", 0))), s.get("chunks_skipped_nolock", 0)])
	return "\n".join(lines)


# ---------------------------------------------------------------------------
# CSV para comparar objetivamente cambios (A/B)
# ---------------------------------------------------------------------------
func start_csv(tag: String) -> void:
	var name := "user://bench_%s_%s.csv" % [tag, Time.get_datetime_string_from_system().replace(":", "-")]
	csv = FileAccess.open(name, FileAccess.WRITE)
	if csv:
		csv.store_line("t,fps,frame_ms,cpu_ms,gpu_ms,ram_mb,vram_mb,draw_calls,primitives,chunks_visible,tris_visible,bodies,debris,update_ms,host_ms,jobs,quality,process_ms,physics_ms,objects")
		csv_t = 0.0
		print("CSV: ", ProjectSettings.globalize_path(name))


func stop_csv() -> void:
	if csv:
		csv.close()
		csv = null


func _csv_row(dt: float) -> void:
	csv_t += dt
	var vp := get_viewport().get_viewport_rid()
	var s := last_stats
	csv.store_line("%.3f,%d,%.3f,%.3f,%.3f,%.1f,%.1f,%d,%d,%d,%d,%d,%d,%.3f,%.3f,%d,%d,%.3f,%.3f,%d" % [
		csv_t, Engine.get_frames_per_second(), dt * 1000.0,
		RenderingServer.viewport_get_measured_render_time_cpu(vp), RenderingServer.viewport_get_measured_render_time_gpu(vp),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)), int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)),
		s.get("chunks_visible", 0), int(s.get("tris_visible", 0)), s.get("bodies_active", 0), s.get("debris_active", 0),
		s.get("t_update_ms", 0.0), s.get("t_host_ms", 0.0), s.get("jobs_pending", 0), last_quality,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))])



## --capaspantalla: a los 12 s, las capas de la interfaz que se dibujan a PANTALLA COMPLETA (lo caro en el movil), con su
## sombreado y si leen la pantalla
func _capas_pantalla_diag() -> void:
	await get_tree().create_timer(12.0).timeout
	var tam: Vector2 = get_viewport().get_visible_rect().size
	var n := 0
	var pila: Array = [self]
	while not pila.is_empty():
		var x: Node = pila.pop_back()
		for c in x.get_children():
			pila.append(c)
		if x is BackBufferCopy and (x as BackBufferCopy).is_visible_in_tree():
			print("[capas] COPIA DE PANTALLA: %s" % x.get_path())
			n += 1
		if x is Control and (x as Control).is_visible_in_tree():
			var r: Rect2 = (x as Control).get_global_rect()
			if r.size.x >= tam.x * 0.9 and r.size.y >= tam.y * 0.9:
				var mat = (x as CanvasItem).material
				var sh := ""
				if mat is ShaderMaterial and (mat as ShaderMaterial).shader:
					sh = (mat as ShaderMaterial).shader.resource_path.get_file()
				if sh != "" or (x is ColorRect and (x as ColorRect).color.a > 0.0) or x is TextureRect:
					print("[capas] %-40s %s %s" % [str(x.name), x.get_class(), sh])
					n += 1
	print("[capas] %d capas de pantalla completa" % n)



# --- LAS PLACAS DEL BATTLE ROYALE (player.gd, "LAS PLACAS") ---------------------------------------------------------
## La barra del escudo va en 3 tramos (una placa cada uno, como en Call of Duty Mobile) y al lado de la vida sale el boton
## PLACA con las que llevas: tocarlo te pone una (player.usar_placa). Solo en los mapas de battle royale.
var _placas_on := false
var _placa_btn: Button = null
var _placa_n: Label = null


func set_placas(n: int, armor: float, on: bool) -> void:
	if not on:
		return
	if not _placas_on:
		_placas_on = true
		_montar_placas()
	set_armor(armor)
	if _placa_n:
		_placa_n.text = str(n)
	if _placa_btn:
		_placa_btn.modulate = Color(1, 1, 1, 1.0 if n > 0 and armor < 149.5 else 0.45)


func _montar_placas() -> void:
	if armor_bar and is_instance_valid(armor_bar):
		for k in [1, 2]:
			var sep := ColorRect.new()
			sep.color = Color(0.02, 0.03, 0.05, 0.95)
			sep.size = Vector2(3, 10)
			sep.position = Vector2(260.0 * k / 3.0 - 1.5, 0)
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			armor_bar.add_child(sep)
	_placa_btn = Button.new()
	_placa_btn.custom_minimum_size = Vector2(64, 56)
	_placa_btn.size = Vector2(64, 56)
	_placa_btn.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.12, 0.75)
	sb.border_color = Color(0.35, 0.70, 1.0, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	for st in ["normal", "hover", "pressed"]:
		_placa_btn.add_theme_stylebox_override(st, sb)
	var ruta := "res://ui/iconos/escudo.svg"
	if ResourceLoader.exists(ruta):
		_placa_btn.icon = load(ruta)
		_placa_btn.expand_icon = true
		_placa_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_placa_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		_placa_btn.add_theme_constant_override("icon_max_width", 34)
	_placa_btn.pressed.connect(func():
		if player and player.has_method("usar_placa"):
			player.usar_placa())
	_placa_n = Label.new()
	_placa_n.add_theme_font_size_override("font_size", 16)
	_placa_n.add_theme_color_override("font_color", Color.WHITE)
	_placa_n.add_theme_constant_override("outline_size", 4)
	_placa_n.add_theme_color_override("font_outline_color", Color.BLACK)
	_placa_n.position = Vector2(46, 34)
	_placa_n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placa_btn.add_child(_placa_n)
	root.add_child(_placa_btn)
	_layout()
