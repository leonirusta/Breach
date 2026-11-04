extends CanvasLayer
## LA ARMERIA (2026-09-29, pedido con captura de Pixel Gun 3D: "en la armeria quiero que sea asi la interfaz de la armeria").
##
##   arriba izq.  "Armería", IR A CARTAS >> (lobby._abrir_cartas, con el globo de Cartas.avisos) y las OCHO casillas
##                hexagonales con las cartas equipadas (cartas.gd: su color, su icono, su nombre y su nivel; las vacias,
##                tenues).
##   abajo izq.   el bloque morado: CARTAS, PERSONAJE (personaje_pantalla.gd) y ESTILO (las skins del personaje).
##   centro       el personaje con su skin, en 3D, CON EL ARMA de la ranura que miras en las manos (y su pintura), en una
##                sala azul con cubos flotando. Se gira arrastrando y vuelve solo. La guardia es la de ESCAPARATE
##                (`GUARDIA` -> avatar_animator.pose_menu: solo este muñeco), no la cruzada en diagonal de la partida.
##   derecha      EQUIPAMIENTO ACTIVO: la FUERZA y la SALUD del personaje, su ficha (retrato, SOLDADO y la skin) y las
##                ranuras de verdad (PRIMARIA y SECUNDARIA grandes; PESADA, C4 y GRANADA chicas) con el arma, la tecla y el
##                PODER (un resumen de sus datos, `_poder`). Abajo los tres EQUIPOS (1 | 2 | 3: Settings.presets_equipo).
##   arriba der.  los cubos, el oro y los diamantes, y la casa (vuelve al lobby).
##
## EL SELECTOR (segunda captura, al tocar una ranura): a la izquierda la columna violeta con las armas en dos columnas
## (las tuyas en azul con su PODER, la que miras con borde amarillo, la puesta con el visto, NUEVO en las que no has
## mirado; las que no tienes, casillas violetas tenues con candado); en medio el panel de la que miras (nombre, ranura,
## rareza, el PODER en grande, la tabla de datos, lo que es, el tipo, la PROPIEDAD ESPECIAL y su HISTORIA) con EQUIPAR,
## ⇄ (otra ranura), $ (la tienda) y el spray (su pintura, o el modelo del mazo); la X magenta vuelve a la armeria y la
## pestaña > recoge el panel. A la derecha el personaje con el arma que miras y las cinco ranuras abajo.
##
## Se dibuja en un lienzo de 720 de alto escalado a la pantalla (como personaje_pantalla.gd); el ancho es el que haya.
## Lo abre el lobby (`_abrir_armeria`, con `lobby`). Fotos: --armeriafoto=<carpeta> (`fotos`).

signal cerrado

const IconoLobby := preload("res://scripts/icono_lobby.gd")
const AvatarScript := preload("res://scripts/avatar_animator.gd")
const LobbyScript := preload("res://scripts/lobby.gd")
const HabilidadScript := preload("res://scripts/habilidad.gd")
const WeaponModelScript := preload("res://scripts/weapon_model.gd")
## Las cartas se cargan a mano (y solo si estan): la pantalla no depende de que esten terminadas
const RUTA_CARTAS := "res://scripts/cartas.gd"
const RUTA_CARTAS_PANTALLA := "res://scripts/cartas_pantalla.gd"

const ALTO := 720.0
const HORIZONTE := 430.0
## el hueco de la vista 3D y donde caen los pies del personaje
const VISTA := Vector2(700, 700)
const VISTA_Y := 8.0
const PIES_Y := 660.0
## la columna izquierda y el panel de la derecha
const IZQ_ANCHO := 410.0
const PANEL_W := 388.0
const PANEL_MARGEN := 42.0
## el selector: la columna de las armas (el panel de detalle va al lado, `_det_ancho`)
const SEL_IZQ := 250.0
## la fila de las cinco ranuras con el selector abierto
const FILA_ANCHOS := [108.0, 108.0, 86.0, 86.0, 86.0]
const FILA_ALTO := 86.0

## LOS COLORES, medidos en las capturas
const PARED_ARRIBA := Color8(20, 58, 178)
const PARED_MEDIO := Color8(34, 106, 222)
const PARED_ABAJO := Color8(70, 160, 244)
const SUELO_LEJOS := Color8(96, 184, 250)
const SUELO_CERCA := Color8(36, 104, 214)
const TINTA := Color8(12, 22, 66)
const LAVANDA := Color8(132, 118, 214)
const LAVANDA_CLARA := Color8(176, 164, 240)
const BLOQUE := Color8(64, 68, 206)
const BLOQUE_CLARO := Color8(86, 92, 228)
const PANEL := Color(0.06, 0.17, 0.50, 0.66)
const PANEL_BORDE := Color(0.55, 0.78, 1.0, 0.38)
const CASILLA_A := Color8(132, 204, 252)
const CASILLA_B := Color8(64, 136, 226)
const ROJO := Color8(236, 44, 70)
const AMARILLO := Color8(255, 212, 52)
const AMARILLO_OSCURO := Color8(206, 150, 16)
const VERDE := Color8(118, 238, 70)
const CIAN := Color8(60, 198, 238)
const PESTANAS := Color8(24, 44, 124)
const VIOLETA_OSCURO := Color8(40, 30, 104)
const VIOLETA := Color8(90, 74, 196)
const VIOLETA_CLARO := Color8(128, 110, 226)
const MAGENTA := Color8(226, 48, 170)
const COLOR_CUBOS := Color(0.78, 0.52, 1.0)

## LAS RANURAS: las tres de verdad (Settings.loadout) y las dos fijas (la C4 de los mapas de bomba y la granada)
const RANURAS := [
	{"id": "primary", "tecla": "1", "nombre": "Primaria"},
	{"id": "secondary", "tecla": "2", "nombre": "Secundaria"},
	{"id": "heavy", "tecla": "3", "nombre": "Pesada"},
	{"id": "c4", "tecla": "4", "nombre": "C4"},
	{"id": "granada", "tecla": "G", "nombre": "Granada"},
]

## LA GUARDIA DE ESCAPARATE (avatar_animator.pose_menu): el arma baja, delante del cuerpo y apuntando al frente algo
## cruzada, en vez de la de "action" de la partida (cruzada en diagonal sobre el pecho, que de frente se ve fatal y
## arrastraba el brazo derecho por delante del pecho). Misma forma que HOLD_POSES: [posicion desde el ojo, giro].
## (Colocadas mirando primeros planos de frente, de tres cuartos y de perfil con --armeriafoto y ARMERIA_POSES: el fusil y la
## escopeta a la altura del cinturon, cruzando el cuerpo a 45 grados con la boca algo baja; la pistola a dos manos delante
## del pecho. Los brazos llegan sin estirarse y no se despegan del hombro.)
const GUARDIA := {
	# (2026-10-12, pedido: la derecha al gatillo, el arma inclinada al otro lado y mas horizontal, "que la culata no
	# traspase el pecho": reflejadas y a 70 grados en vez de 45, elegidas con ARMERIA_POSES)
	"rifle": [Vector3(-0.22, -0.66, -0.22), Vector3(-6.0, -70.0, 4.0)],
	"shotgun": [Vector3(-0.22, -0.66, -0.22), Vector3(-6.0, -70.0, 4.0)],
	"pistol": [Vector3(-0.04, -0.60, -0.32), Vector3(-8.0, -10.0, 0.0)],
}

## Lo que es cada arma, en una linea
const DESCRIPCION := {
	"carabina_556": "Corta, ligera y con óptica de prisma: la que sirve para todo.",
	"fusil_762": "Pega fuerte y se lleva más pared en cada bala. Retrocede como una mula.",
	"fusil_bullpup": "Silenciada y compacta: casi no se oye ni se ve el fogonazo.",
	"smg_9mm": "El subfusil de siempre: estable, preciso y fácil de controlar.",
	"smg_compacta": "Escupe dieciséis balas por segundo. De cerca no perdona.",
	"pdw_57": "Cargador de cuarenta y bala perforante: para no recargar nunca.",
	"escopeta_bomba": "Nueve perdigones por cartucho. Abre puertas y tabiques de un tiro.",
	"escopeta_auto": "Semiautomática: el doble de cadencia que la de corredera.",
	"rifle_precision": "Telescópica de verdad y un disparo que tumba a cualquiera.",
	"pistola_9": "La de serie. Diecisiete balas y una recarga rápida.",
	"pistola_45": "Más daño por bala y micro punto rojo para no fallar.",
	"revolver_44": "Seis balas que pegan como un fusil. Lento, pero no perdona.",
	"bazooka_rpg": "Un cohete, un agujero en el edificio. Radio de explosión enorme.",
	"bazooka_at4": "Más ligero que el RPG y con óptica 2x: menos radio, más puntería.",
	"sledge": "Sin munición y sin límite: parte hormigón a golpes.",
	"escudo_pistola": "Escudo balístico con una pistola asomando por el canto.",
}
## SU HISTORIA
const HISTORIA := {
	"carabina_556": "Salió de los arsenales de la policía de la ciudad cuando empezaron las brechas. Nadie la eligió por bonita: la eligieron porque nunca se encasquilla, ni siquiera llena de polvo de ladrillo.",
	"fusil_762": "Un fusil de batalla viejo, de los que se guardaban en los cuarteles por si acaso. El acaso llegó. Cada bala se lleva un trozo de pared y la mitad del tabique de detrás.",
	"fusil_bullpup": "Lo montó un armero del puerto para los que entran sin llamar. El silenciador va integrado y el cargador detrás del gatillo: cabe entero bajo una gabardina.",
	"smg_9mm": "El subfusil de las patrullas del metro. Tres generaciones de agentes aprendieron a tirar con él y todos dicen lo mismo: no se mueve.",
	"smg_compacta": "Nació para caber en la guantera de un coche. Lo que le falta de alcance lo compensa con una cadencia que vacía el cargador en dos segundos.",
	"pdw_57": "Arma de escolta con munición perforante de 5,7. La diseñaron para pasar chalecos; aquí pasa también puertas de madera y tabiques de pladur.",
	"escopeta_bomba": "La de corredera de toda la vida, calibre 12. Los equipos de asalto la llaman la llave maestra: no hay cerradura que aguante dos cartuchos.",
	"escopeta_auto": "Una escopeta de competición convertida en arma de asalto. Recarga sola con el gas del disparo: basta con volver a apretar el gatillo.",
	"rifle_precision": "De cerrojo, con telescópica de caza mayor. Dicen que su primer dueño tiraba desde las grúas del puerto a más de trescientos metros.",
	"pistola_9": "La que te dan el primer día. No destaca en nada, y precisamente por eso nunca falla cuando todo lo demás se ha quedado sin balas.",
	"pistola_45": "Pistola táctica de calibre gordo con el micro punto rojo atornillado a la corredera. Menos balas, pero cada una cuenta.",
	"revolver_44": "Seis recámaras y un calibre de caza. Es lento de recargar y da un tirón que levanta la muñeca, pero lo que toca no se levanta.",
	"bazooka_rpg": "Lanzagranadas de tubo reutilizable, de los que vienen de otras guerras. Un solo cohete basta para tumbar la fachada de un edificio.",
	"bazooka_at4": "Lanzacohetes antitanque de un solo uso... que alguien aprendió a recargar. La óptica 2x mete el cohete por una ventana a doscientos metros.",
	"sledge": "Un mazo de obra de cinco kilos. No necesita munición ni excusas: cada golpe abre un hueco en el muro y lo que haya detrás se entera.",
	"escudo_pistola": "Escudo balístico de las unidades de intervención, con mirilla y el canto preparado para asomar la pistola. Las balas de frente no pasan.",
}
## Si un arma nueva no trae la suya, la de su familia
const HISTORIA_TIPO := {
	"rifle": "Un fusil hecho para la ciudad en ruinas: aguanta el polvo, el barro y los derrumbes, y sigue disparando.",
	"smg": "Corto y rápido, para pasillos, escaleras y todo lo que se pelea a menos de veinte metros.",
	"shotgun": "Calibre 12 y mucha pólvora. Lo que no tumba, lo abre.",
	"sniper": "Para los que prefieren mirar desde lejos cómo se cae el edificio.",
	"pistol": "La que siempre va encima, por si todo lo demás falla.",
	"rocket": "Un tubo, un cohete y un edificio menos.",
	"sledge": "Hierro y mango. No hace falta más.",
	"escudo": "Lo que se pone entre tú y las balas.",
}

var lobby = null
## Las fotos (--armeriafoto) no tocan el disco: con esto, equipar y pintar solo cambian lo que hay en memoria
var solo_memoria := false

var _raiz: Control
var _w := 1280.0
var _k := 1.0
const EscalaPantalla := preload("res://scripts/escala_pantalla.gd")   ## plegable abierto: no se estrecha (ver alli)
var _franjas: Array = []
var _f: SystemFont            ## la gruesa en cursiva (titulos y numeros, como en las capturas)
var _fn: SystemFont           ## la gruesa derecha
var _fd: SystemFont           ## la de los textos
var _brillo: GradientTexture2D
var _t := 0.0
var _cerrando := false
var _primera := true
## la ranura que se mira (el muñeco la lleva en las manos)
var _slot := "primary"
## el selector: su ranura ("" = cerrado), el arma que se mira, el panel recogido y la pintura abierta
var _sel_slot := ""
var _viendo := ""
var _plegado := false
var _pintura_abierta := false
var _scroll_rejilla := 0
var _scroll_pinturas := 0
# piezas
var _capa_armeria: Control
var _capa_selector: Control
var _selector: Control
var _detalle: Control
var _rejilla_sc: ScrollContainer
var _pinturas_sc: ScrollContainer
var _saldo: _Dibujo
var _saldo_cubo: Control
var _aviso: Label
var _aviso_t := 0.0
var _aviso_txt := ""
var _aviso_col := Color.WHITE
var _cubos: Array = []        ## [x 0..1, y, radio, fase, velocidad, alfa, giro, giro/s]
var _cartas_script = null
# la vista 3D
var _vp: SubViewport
var _cam: Camera3D
var _avatar: Node3D
var _foto: TextureRect
var _gira: Control
var _vx := Vector3(640, PIES_Y, 1.0)   ## donde esta la vista ahora: (centro x, pies y, escala)
var _arrastrando := false
var _reposo_t := 0.0
var _giro_objetivo := PI - 0.4     ## de tres cuartos, con el arma de lado (asi se ve entera, como en la captura)
var _arma_puesta := ""
var _skin_montada := ""


func _ready() -> void:
	layer = 56          # por debajo del personaje (58), la tienda y las cartas (60): se abren encima
	_f = _fuente(900, true)
	_fn = _fuente(900, false)
	_fd = _fuente(700, false)
	_brillo = GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	_brillo.gradient = g
	_brillo.fill = GradientTexture2D.FILL_RADIAL
	_brillo.fill_from = Vector2(0.5, 0.5)
	_brillo.fill_to = Vector2(1.0, 0.5)
	_brillo.width = 128
	_brillo.height = 128
	_iniciar_presets()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260929
	for i in 34:
		var r := rng.randf_range(5.0, 30.0) if rng.randf() < 0.65 else rng.randf_range(18.0, 40.0)
		_cubos.append([rng.randf(), rng.randf_range(10.0, 690.0), r, rng.randf() * TAU, rng.randf_range(0.35, 0.9),
			clampf(0.25 + r / 45.0, 0.3, 1.0) * rng.randf_range(0.6, 1.0), rng.randf() * TAU, rng.randf_range(-0.25, 0.25)])
	_montar_vista()
	_montar()
	_raiz.modulate.a = 0.0
	create_tween().tween_property(_raiz, "modulate:a", 1.0, 0.18)
	Audio.ui("submenu_abre", -8.0)
	Cuenta.sesion_cambiada.connect(_al_cambiar_cuenta)
	get_viewport().size_changed.connect(_al_redimensionar)
	if is_instance_valid(lobby) and lobby.has_method("set_chrome_visible"):
		lobby.set_chrome_visible(false)
	_poner_avatar_luego()


static func _fuente(peso: int, cursiva: bool) -> SystemFont:
	return preload("res://scripts/fuentes.gd").de(peso, cursiva)      # compartida: ver fuentes.gd


## TODO SE REHACE DE UNA VEZ (equipar, pintar, cambiar de equipo...): son unos cientos de nodos y los retratos de las armas
## ya estan cocinados; lo que se conserva es el estado (la ranura, el selector, el arma que se mira, los desplazamientos)
func _montar() -> void:
	var tam: Vector2 = get_viewport().get_visible_rect().size
	var m := EscalaPantalla.medir(tam, ALTO)
	_k = m["k"]
	_w = m["w"]
	EscalaPantalla.quitar(_franjas)
	_franjas = EscalaPantalla.franjas(self, tam, m["y0"], PARED_ARRIBA, SUELO_CERCA)
	if is_instance_valid(_rejilla_sc):
		_scroll_rejilla = _rejilla_sc.scroll_vertical
	if is_instance_valid(_pinturas_sc):
		_scroll_pinturas = _pinturas_sc.scroll_vertical
	if is_instance_valid(_raiz):
		_raiz.queue_free()
	_raiz = Control.new()
	_raiz.mouse_filter = Control.MOUSE_FILTER_STOP
	_raiz.scale = Vector2(_k, _k)
	_raiz.position.y = m["y0"]
	_raiz.size = Vector2(_w, ALTO)
	add_child(_raiz)
	_dibujo(Vector2.ZERO, _raiz.size, _pintar_fondo, _raiz)
	var cubos := _dibujo(Vector2.ZERO, _raiz.size, _pintar_cubos, _raiz)
	cubos.animado = true
	_montar_centro()
	_capa_armeria = _capa()
	_montar_izquierda(_capa_armeria)
	_montar_derecha(_capa_armeria)
	_capa_selector = _capa()
	if _sel_slot != "":
		_montar_selector(_capa_selector)
	_montar_fila(_capa_selector)
	_montar_arriba()
	_aviso = _texto("", 21, Color.WHITE, 5)
	_aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aviso.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var pastilla := StyleBoxFlat.new()
	pastilla.bg_color = Color(0.02, 0.05, 0.25, 0.82)
	pastilla.set_corner_radius_all(12)
	pastilla.border_color = Color(1, 1, 1, 0.25)
	pastilla.set_border_width_all(2)
	pastilla.content_margin_left = 18
	pastilla.content_margin_right = 18
	pastilla.content_margin_top = 6
	pastilla.content_margin_bottom = 8
	_aviso.add_theme_stylebox_override("normal", pastilla)
	_raiz.add_child(_aviso)
	if _aviso_t > 0.0:
		_aviso.text = _aviso_txt
		_aviso.add_theme_color_override("font_color", _aviso_col)
	_colocar_aviso()
	_aviso.modulate.a = clampf(_aviso_t / 0.4, 0.0, 1.0)
	_capa_armeria.visible = _sel_slot == ""
	_capa_selector.visible = _sel_slot != ""
	if is_instance_valid(_saldo):
		_saldo.visible = _sel_slot == ""
	if _vp != null:
		_vp.size = Vector2i(int(VISTA.x * _k), int(VISTA.y * _k))
		_foto.texture = _vp.get_texture()
	if _primera:
		_primera = false
		var o := _vista_objetivo()
		_vx = o
	_colocar_vista()


func _capa() -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = _raiz.size
	_raiz.add_child(c)
	return c


func _al_redimensionar() -> void:
	if _cerrando or not is_inside_tree():
		return
	_montar()
	_vx = _vista_objetivo()
	_colocar_vista()


func _al_cambiar_cuenta() -> void:
	if not _cerrando and is_inside_tree():
		_montar.call_deferred()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _pintura_abierta:
			_pintura_abierta = false
			_montar()
		elif _sel_slot != "":
			_cerrar_selector()
		else:
			_cerrar()


func _cerrar() -> void:
	if _cerrando:
		return
	_cerrando = true
	Audio.ui("submenu_cierra", -8.0)
	if is_instance_valid(lobby):
		var cajon = lobby.get("drawer")
		if lobby.has_method("set_chrome_visible") and not (cajon is Control and (cajon as Control).visible):
			lobby.set_chrome_visible(true)
		# la tarjeta ARMERÍA del lobby dice el arma principal, y la MOCHILA la skin
		if lobby.has_method("_refrescar_tarjetas"):
			lobby._refrescar_tarjetas()
		if lobby.has_method("_refrescar_cuenta"):
			lobby._refrescar_cuenta()
	cerrado.emit()
	var tw := create_tween()
	tw.tween_property(_raiz, "modulate:a", 0.0, 0.15)
	tw.tween_callback(queue_free)


# ================================================================== datos
## Arma REAL de una ranura (como lobby._slot_weapon): lo guardado, o la de fabrica si esta vacio o ya no existe
static func _arma(slot: String) -> String:
	var id := String(Settings.loadout.get(slot, ""))
	if id == "" or not Weapons.catalog().has(id):
		return Weapons.default_for(slot)
	return id


static func _nombre_arma(id: String) -> String:
	var mid := Weapons.modelo_de(id)
	if mid != id:
		return TiendaAjustes.nombre(mid, String(Weapons.NOMBRE_SKIN.get(mid, "MAZO")))
	return TiendaAjustes.nombre(id, String(Weapons.get_def(id).get("name", id)))


## Lo que se dibuja de una ranura: el arma de verdad, o la C4 / la granada
static func _def_ranura(slot: String) -> Dictionary:
	if slot == "granada":
		return {"id": "granada", "name": "GRANADA", "kind": "grenade", "damage": Weapons.GRENADE_DAMAGE, "pellets": 1,
			"rps": 0.5, "range": 25.0, "recoil": 0.0, "mag": 1, "power": Weapons.GRENADE_POWER}
	if slot == "c4":
		return Weapons.get_def("c4")
	return Weapons.get_def(_arma(slot))


## EL PODER: un numero que resume el arma (como el rayo de las capturas), sacado de SUS datos: daño por disparo, cadencia,
## alcance, control, cargador y lo que rompe. Va de 20 y pocos (la pistola de serie) a 60 y tantos (los lanzacohetes).
static func _poder(d: Dictionary) -> int:
	var dmg := clampf(float(d.get("damage", 0.0)) * float(d.get("pellets", 1)) / 130.0, 0.05, 1.0)
	var rps := clampf(float(d.get("rps", 1.0)) / 15.0, 0.05, 1.0)
	var alc := clampf(float(d.get("range", 0.0)) / 300.0, 0.05, 1.0)
	var ctl := clampf(1.0 - float(d.get("recoil", 0.0)) / 0.08, 0.05, 1.0)
	var mag := clampf(float(d.get("mag", 1)) / 64.0, 0.05, 1.0)
	var des := clampf(float(d.get("power", 0)) / 255.0, 0.05, 1.0)
	return int(round(100.0 * (0.35 * dmg + 0.2 * rps + 0.1 * alc + 0.1 * ctl + 0.1 * mag + 0.15 * des)))


## LA RAREZA DE UN ARMA, por lo que cuesta (los colores de SkinsArmas.RAREZAS): de serie COMÚN ... 3.000+ LEGENDARIA
static func _rareza_arma(id: String) -> Dictionary:
	var p := Weapons.precio(id)
	var i := 0
	if p > 2600:
		i = 4
	elif p > 1800:
		i = 3
	elif p > 900:
		i = 2
	elif p > 0:
		i = 1
	return SkinsArmas.RAREZAS[i]


## LA PROPIEDAD ESPECIAL: lo que la distingue, sacado de sus datos. [icono, nombre, valor]
static func _propiedad(id: String) -> Array:
	var d := Weapons.get_def(id)
	var k := String(d.get("kind", ""))
	if k == "escudo":
		return ["escudo", "ESCUDO BALÍSTICO", "PARA LAS BALAS DE FRENTE"]
	if bool(d.get("melee", false)) or k == "sledge":
		return ["destruccion", "ROMPE HORMIGÓN", "SIN MUNICIÓN"]
	if bool(d.get("explosive", false)):
		return ["explosion", "RADIO DE EXPLOSIÓN", "%s m" % _num(float(d.get("radius", 0.0)))]
	if String(d.get("sound", "")) == "silenced":
		return ["sigilo", "SILENCIADA", "FOGONAZO -%d%%" % int(round((1.0 - float(d.get("fogonazo", 1.0))) * 100.0))]
	if int(d.get("pellets", 1)) > 1:
		return ["perdigones", "PERDIGONES", "×%d POR DISPARO" % int(d.get("pellets", 1))]
	if float(d.get("ads_fov", 1.0)) <= 0.4:
		return ["mira", "ÓPTICA TELESCÓPICA", "ZOOM ×%s" % _num(1.0 / float(d.get("ads_fov", 1.0)))]
	# lo que mas destaca frente a los de su familia (weapons.gd FAMILY)
	var fam: Dictionary = Weapons.FAMILY.get(k, {})
	var mejor := ["mira", "ÓPTICA", String(Weapons.OPTICAS.get(String(d.get("optica", "")), "DE SERIE")).to_upper()]
	var tope := 1.03
	if not fam.is_empty():
		for c in [["municion", "MUNICIÓN MÁX.", float(d.mag) / maxf(1.0, float(fam.mag))],
				["cadencia", "CADENCIA", float(d.rps) / maxf(0.01, float(fam.rps))],
				["dano", "DAÑO", float(d.damage) / maxf(0.01, float(fam.damage))],
				["mira", "ALCANCE", float(d.range) / maxf(0.01, float(fam.range))],
				["mira", "CONTROL", float(fam.recoil) / maxf(0.0001, float(d.recoil))],
				["recarga", "RECARGA RÁPIDA", float(fam.reload) / maxf(0.01, float(d.reload))],
				["mira", "PRECISIÓN", float(fam.spread) / maxf(0.0001, float(d.spread))]]:
			if float(c[2]) > tope:
				tope = float(c[2])
				mejor = [c[0], c[1], "+%d%%" % int(round((float(c[2]) - 1.0) * 100.0))]
	return mejor


## La tabla de datos: [icono, nombre, valor]
static func _datos_tabla(id: String) -> Array:
	var d := Weapons.get_def(id)
	var melee := bool(d.get("melee", false))
	var pel := int(d.get("pellets", 1))
	return [
		["dano", "DAÑO", ("%d×%d" % [int(d.damage), pel]) if pel > 1 else str(int(d.damage))],
		["cadencia", "CADENCIA DE TIRO", "%s/s" % _num(float(d.rps))],
		["municion", "MUNICIÓN", "∞" if melee else "%d / %d" % [int(d.mag), int(d.get("reserve", 0))]],
		["movimiento", "VEL. MOVIMIENTO", "85%" if String(d.kind) == "escudo" else "100%"],
		["destruccion", "DESTRUCCIÓN", str(int(d.get("power", 0)))],
	]


## EL ORDEN DEL SELECTOR: primero las tuyas (las de su tipo delante: cualquier arma entra en cualquier ranura, pero en la
## primaria se buscan fusiles), luego las que no tienes
func _armas_selector(slot: String) -> Array:
	var tipos: Array = Weapons.SLOT_KINDS.get(slot, [])
	var mias: Array = []
	var suyas_no: Array = []
	var ajenas: Array = []
	for id in Weapons.ids_equipables():
		var tipo := String(Weapons.get_def(id).kind)
		if Settings.tengo_arma(id):
			if tipo in tipos:
				mias.append(id)
			else:
				suyas_no.append(id)
		else:
			ajenas.append(id)
	return mias + suyas_no + ajenas


# ================================================================== los equipos (1 | 2 | 3) y lo NUEVO
func _iniciar_presets() -> void:
	var p: Dictionary = Settings.presets_equipo
	if not (p.get("lista") is Array) or (p["lista"] as Array).size() != 3:
		p["lista"] = [{}, {}, {}]
		p["activo"] = 0
	p["activo"] = clampi(int(p.get("activo", 0)), 0, 2)
	# LO NUEVO: la primera vez, todo lo que ya tienes esta visto (si no, salian NUEVO las tres de serie)
	if not (p.get("vistas") is Array):
		var vistas: Array = []
		for id in Weapons.ids_equipables():
			if Settings.tengo_arma(id):
				vistas.append(id)
		p["vistas"] = vistas
	Settings.presets_equipo = p
	# el equipo activo ES lo que llevas (si algo lo cambio fuera de la armeria, manda lo de fuera)
	var lista: Array = p["lista"]
	lista[int(p["activo"])] = _equipo_actual()


func _equipo_actual() -> Dictionary:
	var lo := {}
	var pint := {}
	for s in Weapons.SLOTS:
		var id := _arma(s)
		lo[s] = id
		var mid := Weapons.modelo_de(id)
		var sk := SkinsArmas.equipada(mid)
		if sk != "":
			pint[mid] = sk
	return {"loadout": lo, "pinturas": pint, "mazo": Settings.skin_mazo}


func _guardar_preset() -> void:
	var p: Dictionary = Settings.presets_equipo
	var lista: Array = p["lista"]
	lista[int(p.get("activo", 0))] = _equipo_actual()


func _preset_activo() -> int:
	return int(Settings.presets_equipo.get("activo", 0))


func _cambiar_preset(i: int) -> void:
	var p: Dictionary = Settings.presets_equipo
	var act := _preset_activo()
	if i == act:
		Audio.ui("aceptar", -12.0)
		_avisar("EQUIPO %d · ES EL QUE LLEVAS" % (i + 1))
		return
	var lista: Array = p["lista"]
	lista[act] = _equipo_actual()
	var nuevo: Dictionary = lista[i] if lista[i] is Dictionary else {}
	var copia := false
	if not nuevo.has("loadout"):
		nuevo = _equipo_actual().duplicate(true)
		lista[i] = nuevo
		copia = true
	p["activo"] = i
	_aplicar_equipo(nuevo)
	_guardar()
	Audio.equip_sound(true)
	_avisar(("EQUIPO %d · copia del %d: cámbialo a tu gusto" % [i + 1, act + 1]) if copia else "EQUIPO %d" % (i + 1), AMARILLO)
	_montar()
	_poner_arma()


func _aplicar_equipo(e: Dictionary) -> void:
	var mz := String(e.get("mazo", ""))
	Settings.skin_mazo = mz if (mz == "" or Settings.tengo(mz)) else ""
	var lo: Dictionary = e.get("loadout", {})
	for s in Weapons.SLOTS:
		var id := String(lo.get(s, ""))
		if id == "" or not Weapons.catalog().has(id) or not Settings.tengo_arma(id):
			id = Weapons.default_for(s)
		Settings.loadout[s] = id
	var pint: Dictionary = e.get("pinturas", {})
	for s in Weapons.SLOTS:
		var mid := Weapons.modelo_de(String(Settings.loadout[s]))
		var sk := String(pint.get(mid, ""))
		if sk != "" and SkinsArmas.mia(sk):
			Settings.skins_arma[mid] = sk
		else:
			Settings.skins_arma.erase(mid)


func _guardar() -> void:
	if not solo_memoria:
		Settings.save()


func _visto(id: String) -> bool:
	return id in (Settings.presets_equipo.get("vistas", []) as Array)


func _marcar_visto(id: String) -> void:
	if not Settings.tengo_arma(id) or _visto(id):
		return
	var vistas: Array = Settings.presets_equipo["vistas"]
	vistas.append(id)
	_guardar()


# ================================================================== equipar
func _equipar(slot: String, arma: String) -> void:
	var antes := _arma(slot)
	Settings.loadout[slot] = arma
	_guardar_preset()
	_guardar()
	Audio.equip_sound(antes != arma)
	_avisar("%s EN %s" % [_nombre_arma(arma), String(Weapons.SLOT_NAMES.get(slot, slot))], AMARILLO)


func _poner_pintura(mid: String, sk: String) -> void:
	# (lo que hace SkinsArmas.equipar, sin su guardado: guarda `_guardar`)
	if sk == "":
		Settings.skins_arma.erase(mid)
	else:
		Settings.skins_arma[mid] = sk
	_guardar_preset()
	_guardar()
	Audio.equip_sound(true)
	_avisar(("%s · %s" % [_nombre_arma(_viendo), SkinsArmas.nombre_de(sk)]) if sk != "" else "%s · SIN PINTURA" % _nombre_arma(_viendo), AMARILLO)


func _poner_mazo(sid: String) -> void:
	Settings.skin_mazo = sid
	_guardar_preset()
	_guardar()
	Audio.equip_sound(true)
	_avisar("MAZO · %s" % (TiendaAjustes.nombre(sid, String(Weapons.NOMBRE_SKIN.get(sid, sid))) if sid != "" else "DE HIERRO"), AMARILLO)


# ================================================================== piezas
func _texto(t: String, tam: int, col: Color, contorno := 6, f: Font = null) -> Label:
	var l := Label.new()
	l.text = t
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", f if f != null else _f)
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", col)
	if contorno > 0:
		l.add_theme_color_override("font_outline_color", TINTA)
		l.add_theme_constant_override("outline_size", contorno)
		l.add_theme_color_override("font_shadow_color", Color(0.0, 0.02, 0.15, 0.45))
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 3)
		l.add_theme_constant_override("shadow_outline_size", contorno)
	return l


func _dibujo(pos: Vector2, tam: Vector2, pintar: Callable, padre: Node) -> _Dibujo:
	var d := _Dibujo.new()
	d.position = pos
	d.size = tam
	d.pintar = pintar
	if padre != null:
		padre.add_child(d)
	return d


## Un boton que se dibuja a mano (`pintar`) y encoge un poco al apretarlo
func _boton(r: Rect2, pintar: Callable, al_pulsar: Callable, padre: Node) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.position = r.position
	b.size = r.size
	b.pivot_offset = r.size * 0.5
	b.set_meta("sin_sonido", true)     # el sonido lo pone cada accion (Audio engancha uno a todos los botones)
	for e in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(e, StyleBoxEmpty.new())
	padre.add_child(b)
	_dibujo(Vector2.ZERO, r.size, pintar, b)
	b.button_down.connect(func(): b.scale = Vector2(0.95, 0.95))
	b.button_up.connect(func(): b.scale = Vector2.ONE)
	b.pressed.connect(al_pulsar)
	return b


func _icono(nombre: String, col: Color, pos: Vector2, tam: float, padre: Node) -> Control:
	var ic := IconoLobby.new()
	ic.icono = nombre
	ic.color = col
	ic.position = pos
	ic.size = Vector2(tam, tam)
	padre.add_child(ic)
	return ic


## Texto dibujado con su contorno y su sombra (letra gorda, blanca, con borde oscuro)
func _txt(ci: CanvasItem, t: String, pos: Vector2, tam: int, col: Color, alin := HORIZONTAL_ALIGNMENT_LEFT,
		ancho := -1.0, contorno := 6, f: Font = null) -> void:
	var fuente: Font = f if f != null else _f
	if contorno > 0:
		ci.draw_string_outline(fuente, pos + Vector2(0, 3), t, alin, ancho, tam, contorno, Color(0.0, 0.02, 0.15, 0.4))
		ci.draw_string_outline(fuente, pos, t, alin, ancho, tam, contorno, TINTA)
	ci.draw_string(fuente, pos, t, alin, ancho, tam, col)


func _base(cy: float, tam: int, f: Font = null) -> float:
	var fuente: Font = f if f != null else _f
	return cy + (fuente.get_ascent(tam) - fuente.get_descent(tam)) * 0.5


func _ancho(t: String, tam: int, f: Font = null) -> float:
	return (f if f != null else _f).get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x


func _cabe(t: String, tam: int, ancho: float, minimo: int, f: Font = null) -> int:
	var s := tam
	while s > minimo and _ancho(t, s, f) > ancho:
		s -= 1
	return s


static func _con_puntos(v: int) -> String:
	var t := str(absi(v))
	var out := ""
	while t.length() > 3:
		out = "." + t.substr(t.length() - 3) + out
		t = t.substr(0, t.length() - 3)
	return ("-" if v < 0 else "") + t + out


static func _num(v: float) -> String:
	if absf(v - roundf(v)) < 0.05:
		return str(int(roundf(v)))
	return ("%.1f" % v).replace(".", ",")


func _degradado_v(ci: CanvasItem, r: Rect2, arriba: Color, abajo: Color) -> void:
	ci.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([arriba, arriba, abajo, abajo]))


func _degradado_h(ci: CanvasItem, r: Rect2, izq: Color, der: Color) -> void:
	ci.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([izq, der, der, izq]))


func _con_borde(ci: CanvasItem, pts: PackedVector2Array, relleno: Color, grosor := 5.0, borde := TINTA) -> void:
	var cerrado := pts.duplicate()
	cerrado.append(pts[0])
	ci.draw_polyline(cerrado, borde, grosor, true)
	ci.draw_colored_polygon(pts, relleno)


static func _caja(r: Rect2, radio: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var rr := minf(radio, minf(r.size.x, r.size.y) * 0.5)
	var centros := [Vector2(r.end.x - rr, r.position.y + rr), Vector2(r.end.x - rr, r.end.y - rr),
		Vector2(r.position.x + rr, r.end.y - rr), Vector2(r.position.x + rr, r.position.y + rr)]
	for k in 4:
		for i in 5:
			var a := -PI * 0.5 + (k + i / 4.0) * PI * 0.5
			out.append(centros[k] + Vector2(cos(a), sin(a)) * rr)
	return out


## Paralelogramo en `r` con el borde de arriba corrido `s` a la derecha (las cajas inclinadas de las capturas)
static func _inclinada(r: Rect2, s: float) -> PackedVector2Array:
	return PackedVector2Array([r.position + Vector2(s, 0), Vector2(r.end.x, r.position.y), r.end - Vector2(s, 0),
		Vector2(r.position.x, r.end.y)])


static func _hex(c: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in 6:
		var a := deg_to_rad(60.0 * k - 90.0)
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


static func _pts(c: Vector2, r: float, arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in arr:
		out.append(c + Vector2(float(q[0]), float(q[1])) * r)
	return out


func _avisar(t: String, col := Color.WHITE) -> void:
	_aviso_txt = t
	_aviso_col = col
	_aviso_t = 2.4
	if is_instance_valid(_aviso):
		_aviso.text = t
		_aviso.add_theme_color_override("font_color", col)
		_aviso.modulate.a = 1.0
		_colocar_aviso()


## el aviso, en su pastilla sobre el personaje (entre los paneles), del ancho del texto
func _colocar_aviso() -> void:
	if not is_instance_valid(_aviso):
		return
	var x0 := IZQ_ANCHO + 10.0
	var x1 := _px() - 10.0
	if _sel_slot != "":
		x0 = _ra() + 10.0
		x1 = _w - 10.0
	# en una linea: si no cabe, la letra baja (sin partir: una pastilla alta tapaba al personaje)
	var tam := _cabe(_aviso.text, 21, x1 - x0 - 44.0, 12)
	_aviso.add_theme_font_size_override("font_size", tam)
	var ancho := minf(_ancho(_aviso.text, tam) + 44.0, x1 - x0)
	_aviso.size = Vector2(ancho, 44.0)
	_aviso.position = Vector2((x0 + x1) * 0.5 - ancho * 0.5, 64)


# ================================================================== los dibujitos
## Los iconos de la armeria, blancos con el borde oscuro de todo (o del color que se pida). `r` = medio lado.
func _glifo(ci: CanvasItem, tipo: String, c: Vector2, r: float, col := Color.WHITE, borde := true) -> void:
	var g := maxf(2.0, r * 0.2) if borde else 0.0
	var b := TINTA if borde else Color(0, 0, 0, 0)
	match tipo:
		"rayo":
			var p := _pts(c, r, [[0.1, -1.0], [0.62, -1.0], [0.18, -0.2], [0.62, -0.2], [-0.32, 1.0], [-0.06, 0.12], [-0.52, 0.12]])
			if borde:
				_con_borde(ci, p, col, g, b)
			else:
				ci.draw_colored_polygon(p, col)
		"corazon":
			if borde:
				ci.draw_circle(c + Vector2(-r * 0.48, -r * 0.18), r * 0.56 + g * 0.5, b)
				ci.draw_circle(c + Vector2(r * 0.48, -r * 0.18), r * 0.56 + g * 0.5, b)
				ci.draw_colored_polygon(_pts(c, r, [[-1.12, -0.04], [1.12, -0.04], [0, 1.12]]), b)
			ci.draw_circle(c + Vector2(-r * 0.48, -r * 0.18), r * 0.56, col)
			ci.draw_circle(c + Vector2(r * 0.48, -r * 0.18), r * 0.56, col)
			ci.draw_colored_polygon(_pts(c, r, [[-1.02, -0.02], [1.02, -0.02], [0, 0.98]]), col)
			ci.draw_circle(c + Vector2(-r * 0.5, -r * 0.34), r * 0.18, Color(1, 1, 1, 0.55))
		"check":
			var p := _pts(c, r, [[-0.8, 0.0], [-0.25, 0.55], [0.85, -0.6]])
			if borde:
				ci.draw_polyline(p, b, r * 0.62, true)
			ci.draw_polyline(p, col, r * 0.36, true)
		"candado":
			ci.draw_arc(c + Vector2(0, -r * 0.16), r * 0.54, PI, TAU, 12, b, r * 0.56, true)
			ci.draw_arc(c + Vector2(0, -r * 0.16), r * 0.54, PI, TAU, 12, col, r * 0.26, true)
			_con_borde(ci, _caja(Rect2(c + Vector2(-r * 0.84, -r * 0.2), Vector2(r * 1.68, r * 1.28)), r * 0.2), col, maxf(2.0, r * 0.26), b)
			ci.draw_circle(c + Vector2(0, r * 0.4), r * 0.18, b)
		"dano":
			var p := PackedVector2Array()
			for k in 16:
				var a := deg_to_rad(22.5 * k - 90.0)
				p.append(c + Vector2(cos(a), sin(a)) * r * (1.0 if k % 2 == 0 else 0.5))
			if borde:
				_con_borde(ci, p, col, g, b)
			else:
				ci.draw_colored_polygon(p, col)
		"explosion":
			var p := PackedVector2Array()
			var q := PackedVector2Array()
			for k in 18:
				var a := deg_to_rad(20.0 * k - 90.0)
				var m := (1.0 if k % 2 == 0 else 0.55) * (0.92 if k % 4 == 2 else 1.0)
				p.append(c + Vector2(cos(a), sin(a)) * r * m)
				q.append(c + Vector2(cos(a), sin(a)) * r * m * 0.52)
			_con_borde(ci, p, col, g, b)
			ci.draw_colored_polygon(q, Color(1.0, 0.8, 0.3, col.a))
		"cadencia":
			for i in 3:
				var x := -0.62 + i * 0.62
				var h := 0.7 + 0.15 * i
				var p := _pts(c, r, [[x - 0.2, 0.9], [x + 0.2, 0.9], [x + 0.2, 0.9 - h], [x, 0.9 - h - 0.35], [x - 0.2, 0.9 - h]])
				_con_borde(ci, p, col, maxf(1.5, g * 0.7), b)
		"municion":
			var p := _pts(c, r, [[-0.34, 1.0], [0.34, 1.0], [0.34, -0.2], [0.0, -1.0], [-0.34, -0.2]])
			_con_borde(ci, p, col, g, b)
			ci.draw_line(c + Vector2(-r * 0.34, r * 0.55), c + Vector2(r * 0.34, r * 0.55), b, maxf(1.5, r * 0.14))
		"movimiento":
			for i in 2:
				var x := -0.55 + i * 0.7
				var p := _pts(c, r, [[x - 0.35, -0.85], [x + 0.1, -0.85], [x + 0.55, 0.0], [x + 0.1, 0.85], [x - 0.35, 0.85], [x + 0.1, 0.0]])
				_con_borde(ci, p, col, maxf(1.5, g * 0.8), b)
		"destruccion":
			_con_borde(ci, _pts(c, r, [[-1.0, -0.62], [1.0, -0.62], [1.0, 0.62], [-1.0, 0.62]]), col, g, b)
			ci.draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), b, maxf(1.2, r * 0.1))
			ci.draw_line(c + Vector2(-r * 0.1, -r * 0.62), c + Vector2(-r * 0.1, 0), b, maxf(1.2, r * 0.1))
			ci.draw_line(c + Vector2(r * 0.5, 0), c + Vector2(r * 0.5, r * 0.62), b, maxf(1.2, r * 0.1))
			ci.draw_polyline(_pts(c, r, [[0.25, -0.75], [0.05, -0.3], [0.35, 0.05], [0.1, 0.4], [0.3, 0.75]]), ROJO, maxf(1.5, r * 0.16), true)
		"escudo":
			var p := _pts(c, r, [[0.0, -1.0], [0.85, -0.7], [0.8, 0.1], [0.0, 1.0], [-0.8, 0.1], [-0.85, -0.7]])
			_con_borde(ci, p, col, g, b)
			ci.draw_colored_polygon(_pts(c, r, [[0.0, -0.7], [0.5, -0.5], [0.48, 0.05], [0.0, 0.65]]), Color(0, 0.05, 0.25, 0.25))
		"sigilo":
			var p := PackedVector2Array()
			for k in 13:
				var a := PI * k / 12.0
				p.append(c + Vector2(-cos(a), -sin(a) * 0.55) * r)
			for k in range(1, 12):
				var a := PI * k / 12.0
				p.append(c + Vector2(cos(a), sin(a) * 0.55) * r)
			_con_borde(ci, p, col, g, b)
			ci.draw_circle(c, r * 0.3, b)
			ci.draw_line(c + Vector2(-r * 0.8, r * 0.8), c + Vector2(r * 0.8, -r * 0.8), b, r * 0.34)
			ci.draw_line(c + Vector2(-r * 0.8, r * 0.8), c + Vector2(r * 0.8, -r * 0.8), col, r * 0.16)
		"perdigones":
			for q in [[0, 0], [0.62, 0], [-0.62, 0], [0.31, 0.54], [-0.31, 0.54], [0.31, -0.54], [-0.31, -0.54]]:
				ci.draw_circle(c + Vector2(float(q[0]), float(q[1])) * r, r * 0.3, b)
				ci.draw_circle(c + Vector2(float(q[0]), float(q[1])) * r, r * 0.2, col)
		"mira":
			ci.draw_arc(c, r * 0.66, 0.0, TAU, 24, b, r * 0.36, true)
			ci.draw_arc(c, r * 0.66, 0.0, TAU, 24, col, r * 0.18, true)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				ci.draw_line(c + d * r * 0.3, c + d * r * 1.0, b, r * 0.34)
				ci.draw_line(c + d * r * 0.34, c + d * r * 0.96, col, r * 0.16)
		"recarga":
			ci.draw_arc(c, r * 0.7, deg_to_rad(-60), deg_to_rad(230), 20, b, r * 0.4, true)
			ci.draw_arc(c, r * 0.7, deg_to_rad(-60), deg_to_rad(230), 20, col, r * 0.2, true)
			var pc := c + Vector2(cos(deg_to_rad(-60)), sin(deg_to_rad(-60))) * r * 0.7
			_con_borde(ci, PackedVector2Array([pc + Vector2(-r * 0.42, -r * 0.2), pc + Vector2(r * 0.34, -r * 0.42),
				pc + Vector2(r * 0.1, r * 0.4)]), col, maxf(1.5, g * 0.7), b)
		"cambio":
			for s in [-1.0, 1.0]:
				var y: float = -0.38 * float(s)
				var p := _pts(c, r, [[-0.8 * s, y - 0.12], [0.3 * s, y - 0.12], [0.3 * s, y - 0.42], [0.95 * s, y], [0.3 * s, y + 0.42],
					[0.3 * s, y + 0.12], [-0.8 * s, y + 0.12]])
				_con_borde(ci, p, col, maxf(1.5, g * 0.8), b)
		"pintura":
			_con_borde(ci, _caja(Rect2(c + Vector2(-r * 0.46, -r * 0.3), Vector2(r * 0.92, r * 1.3)), r * 0.16), col, g, b)
			_con_borde(ci, _pts(c, r, [[-0.3, -0.58], [0.3, -0.58], [0.3, -0.3], [-0.3, -0.3]]), col, g, b)
			_con_borde(ci, _pts(c, r, [[-0.12, -0.82], [0.14, -0.82], [0.14, -0.58], [-0.12, -0.58]]), col, maxf(1.5, g * 0.7), b)
			for q in [[0.42, -0.92], [0.66, -0.74], [0.5, -0.56], [0.8, -0.98], [0.86, -0.6]]:
				ci.draw_circle(c + Vector2(float(q[0]), float(q[1])) * r, r * 0.1, col)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.46, r * 0.18), Vector2(r * 0.92, r * 0.34)), Color(0, 0.05, 0.3, 0.3))
		"cartas":
			var atras := PackedVector2Array()
			for q in [[-0.95, -0.55], [0.05, -0.85], [0.5, 0.6], [-0.5, 0.9]]:
				atras.append(c + Vector2(float(q[0]), float(q[1])) * r)
			_con_borde(ci, atras, Color(col, 0.75), g, b)
			_con_borde(ci, _pts(c, r, [[-0.35, -0.9], [0.8, -0.9], [0.8, 0.95], [-0.35, 0.95]]), col, g, b)
			_con_borde(ci, _pts(c, r, [[0.22, -0.62], [0.58, -0.12], [0.34, -0.12], [0.34, 0.55], [0.1, 0.55], [0.1, -0.12], [-0.14, -0.12]]),
				BLOQUE, maxf(1.5, g * 0.4), b)
		"personaje":
			_con_borde(ci, _pts(c, r, [[-0.92, 1.0], [-0.72, 0.1], [0.72, 0.1], [0.92, 1.0]]), col, g, b)
			_con_borde(ci, _pts(c, r, [[-0.44, -1.0], [0.44, -1.0], [0.44, -0.12], [-0.44, -0.12]]), col, g, b)
		"rifle":
			var p := _pts(c, r, [[-1.0, -0.12], [-0.42, -0.3], [0.9, -0.3], [0.9, -0.12], [0.3, -0.12], [0.3, 0.1], [0.05, 0.1],
				[-0.05, 0.5], [-0.28, 0.5], [-0.22, 0.1], [-0.55, 0.12], [-1.0, 0.34]])
			_con_borde(ci, p, col, g, b)
		"pistola":
			_con_borde(ci, _pts(c, r, [[-0.8, -0.5], [0.85, -0.5], [0.85, -0.12], [-0.1, -0.12], [-0.3, 0.8], [-0.78, 0.8], [-0.52, -0.12], [-0.8, -0.12]]), col, g, b)
		"mazo":
			_con_borde(ci, _pts(c, r, [[-0.08, -0.4], [0.08, -0.4], [0.08, 1.0], [-0.08, 1.0]]), col, g, b)
			_con_borde(ci, _pts(c, r, [[-0.8, -0.95], [0.8, -0.95], [0.8, -0.35], [-0.8, -0.35]]), col, g, b)
		"gota":
			var p := PackedVector2Array()
			for k in 13:
				var a := PI * k / 12.0
				p.append(c + Vector2(cos(a), sin(a)) * r * 0.62 + Vector2(0, r * 0.28))
			p.append(c + Vector2(0, -r))
			_con_borde(ci, p, col, maxf(1.5, g * 0.7), b)
		"x":
			for s in [1.0, -1.0]:
				ci.draw_line(c + Vector2(-r * 0.7, -r * 0.7 * s), c + Vector2(r * 0.7, r * 0.7 * s), b, r * 0.56)
			for s in [1.0, -1.0]:
				ci.draw_line(c + Vector2(-r * 0.66, -r * 0.66 * s), c + Vector2(r * 0.66, r * 0.66 * s), col, r * 0.3)


func _moneda(ci: CanvasItem, c: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := PI / 8.0 + i * TAU / 8.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	var canto := PackedVector2Array()
	var dentro := PackedVector2Array()
	for p in pts:
		canto.append(p + Vector2(0, r * 0.2))
		dentro.append(c + (p - c) * 0.68)
	ci.draw_colored_polygon(canto, Color(0.70, 0.42, 0.02))
	ci.draw_colored_polygon(pts, Color(1.0, 0.80, 0.16))
	ci.draw_colored_polygon(dentro, Color(0.94, 0.64, 0.07))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.42), c + Vector2(r * 0.34, 0), c + Vector2(0, r * 0.42),
		c + Vector2(-r * 0.34, 0)]), Color(1.0, 0.94, 0.58))


func _gema(ci: CanvasItem, c: Vector2, r: float) -> void:
	var arriba := c.y - r * 0.62
	var medio := c.y - r * 0.10
	var abajo := c.y + r * 0.95
	var borde := PackedVector2Array([Vector2(c.x - r * 0.55, arriba), Vector2(c.x + r * 0.55, arriba), Vector2(c.x + r, medio),
		Vector2(c.x, abajo), Vector2(c.x - r, medio)])
	var filo := PackedVector2Array()
	for p in borde:
		filo.append(p + (p - c).normalized() * 1.6)
	ci.draw_colored_polygon(filo, Color(0.03, 0.28, 0.14))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(c.x - r, medio), Vector2(c.x + r, medio), Vector2(c.x, abajo)]),
		Color(0.10, 0.60, 0.33))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(c.x - r * 0.25, medio), Vector2(c.x + r, medio), Vector2(c.x, abajo)]),
		Color(0.18, 0.74, 0.42))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(c.x - r * 0.55, arriba), Vector2(c.x + r * 0.55, arriba),
		Vector2(c.x + r, medio), Vector2(c.x - r, medio)]), Color(0.42, 0.93, 0.60))


## Un globo rojo con un numero (las marcas de las capturas)
func _globo(ci: CanvasItem, c: Vector2, r: float, t: String, fondo := ROJO) -> void:
	ci.draw_circle(c + Vector2(0, 2), r + 2.5, Color(0, 0.02, 0.15, 0.45))
	ci.draw_circle(c, r + 2.5, Color.WHITE)
	ci.draw_circle(c, r, fondo)
	var tam := int(r * 1.25)
	_txt(ci, t, Vector2(c.x - r * 2.0, _base(c.y, tam)), tam, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r * 4.0, 3)


## Un hexagono de color con su relieve (las casillas de las cartas)
func _hexagono(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_colored_polygon(_hex(c + Vector2(0, 3), r + 3.0), Color(0.05, 0.03, 0.25, 0.45))
	ci.draw_colored_polygon(_hex(c, r + 3.0), TINTA)
	ci.draw_colored_polygon(_hex(c, r), col.darkened(0.28))
	ci.draw_colored_polygon(_hex(c + Vector2(0, -r * 0.06), r * 0.86), col)
	# el brillo de arriba
	var h := _hex(c + Vector2(0, -r * 0.06), r * 0.86)
	ci.draw_colored_polygon(PackedVector2Array([h[5], h[0], h[1], (h[1] + h[5]) * 0.5]), Color(1, 1, 1, 0.22))
	ci.draw_polyline(PackedVector2Array([h[4], h[5], h[0], h[1]]), Color(1, 1, 1, 0.35), 2.0, true)


## Un cubo de fuerza pequeñito dibujado (para el globo del personaje)
func _cubo_2d(ci: CanvasItem, c: Vector2, r: float, giro: float, a: float) -> void:
	var p := PackedVector2Array()
	for k in 6:
		var an := giro + deg_to_rad(-90.0 + 60.0 * k)
		p.append(c + Vector2(cos(an), sin(an)) * r)
	ci.draw_colored_polygon(PackedVector2Array([p[0], p[1], c, p[5]]), Color(0.84, 0.96, 1.0, 0.34 * a))
	ci.draw_colored_polygon(PackedVector2Array([c, p[1], p[2], p[3]]), Color(0.42, 0.70, 1.0, 0.24 * a))
	ci.draw_colored_polygon(PackedVector2Array([p[5], c, p[3], p[4]]), Color(0.60, 0.85, 1.0, 0.28 * a))
	var borde := Color(0.88, 0.98, 1.0, 0.9 * a)
	var w := clampf(r * 0.08, 1.0, 2.6)
	var cerr := p.duplicate()
	cerr.append(p[0])
	ci.draw_polyline(cerr, borde, w, true)
	ci.draw_line(c, p[1], Color(borde, borde.a * 0.7), w * 0.8, true)
	ci.draw_line(c, p[3], Color(borde, borde.a * 0.7), w * 0.8, true)
	ci.draw_line(c, p[5], Color(borde, borde.a * 0.7), w * 0.8, true)


# ================================================================== el fondo: una sala azul de bloques
func _px() -> float:
	return _w - PANEL_MARGEN - PANEL_W


func _det_ancho() -> float:
	return clampf(_w - SEL_IZQ - 540.0, 420.0, 520.0)


## donde empieza lo de la derecha con el selector abierto
func _ra() -> float:
	return SEL_IZQ + (26.0 if _plegado else _det_ancho())


func _pintar_fondo(ci: Control) -> void:
	var s := ci.size
	var hz := HORIZONTE
	var cx := (IZQ_ANCHO + _px()) * 0.5
	_degradado_v(ci, Rect2(0, 0, s.x, hz * 0.6), PARED_ARRIBA, PARED_MEDIO)
	_degradado_v(ci, Rect2(0, hz * 0.6, s.x, hz * 0.4 + 1.0), PARED_MEDIO, PARED_ABAJO)
	_degradado_v(ci, Rect2(0, hz, s.x, s.y - hz), SUELO_LEJOS, SUELO_CERCA)
	# LA SALA EN PERSPECTIVA (un patio largo, como en la captura): camara a 1,6 m, paredes a 8 m a cada lado y el fondo a
	# 30 m; baldosas de 2 m. f = 575: los pies del personaje (a 4 m) caen en PIES_Y.
	var f := 575.0
	var yo := 1.6
	var pr := func(x: float, y: float, z: float) -> Vector2:
		return Vector2(cx + f * x / z, hz + f * (yo - y) / z)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var linea := Color(0.78, 0.94, 1.0, 0.16)
	# las paredes de los lados: bloques de 2 m con su tono
	for lado in [-1.0, 1.0]:
		var x: float = 8.0 * lado
		var z := 30.0
		while z > 2.5:
			var z2 := maxf(z - 2.0, 2.2)
			for fila in 9:
				var y0 := fila * 2.0
				var q := PackedVector2Array([pr.call(x, y0, z), pr.call(x, y0 + 2.0, z), pr.call(x, y0 + 2.0, z2), pr.call(x, y0, z2)])
				var luz := rng.randf_range(-0.06, 0.1) + (0.08 if (fila + int(z)) % 3 == 0 else 0.0)
				ci.draw_colored_polygon(q, Color(0.55, 0.8, 1.0, clampf(0.05 + luz, 0.0, 0.2)))
				var cerr := q.duplicate()
				cerr.append(q[0])
				ci.draw_polyline(cerr, linea, 1.5, true)
			z = z2
	# el fondo del patio: la columna de luz y los bloques altos
	var fondo := Rect2(pr.call(-8.0, 22.0, 30.0), pr.call(8.0, 0.0, 30.0) - pr.call(-8.0, 22.0, 30.0))
	ci.draw_rect(fondo, Color(0.55, 0.85, 1.0, 0.16))
	for i in 8:
		for j in 11:
			var p0: Vector2 = pr.call(-8.0 + i * 2.0, j * 2.0, 30.0)
			var p1: Vector2 = pr.call(-6.0 + i * 2.0, j * 2.0 + 2.0, 30.0)
			var rr := Rect2(Vector2(p0.x, p1.y), Vector2(p1.x - p0.x, p0.y - p1.y))
			if rng.randf() < 0.55:
				ci.draw_rect(rr.grow(-1.0), Color(0.75, 0.92, 1.0, rng.randf_range(0.04, 0.16)))
			ci.draw_rect(rr, linea, false, 1.0)
	# torres de bloques detras (la ciudad de la captura, muy clara)
	for t in [[-5.5, 26.0, 2.0, 16.0], [-2.0, 24.0, 2.5, 22.0], [2.4, 25.0, 2.0, 18.0], [5.2, 27.0, 2.0, 13.0]]:
		var a: Vector2 = pr.call(float(t[0]) - float(t[2]) * 0.5, float(t[3]), float(t[1]))
		var b2: Vector2 = pr.call(float(t[0]) + float(t[2]) * 0.5, 0.0, float(t[1]))
		ci.draw_rect(Rect2(a, b2 - a), Color(0.8, 0.95, 1.0, 0.12))
		ci.draw_rect(Rect2(a, b2 - a), Color(0.85, 0.97, 1.0, 0.22), false, 1.5)
	# la luz que baja por el centro
	ci.draw_texture_rect(_brillo, Rect2(cx - 300, -260, 600, hz + 360), false, Color(0.72, 0.94, 1.0, 0.45))
	ci.draw_texture_rect(_brillo, Rect2(cx - 150, -120, 300, hz + 140), false, Color(0.9, 1.0, 1.0, 0.35))
	# EL SUELO: baldosas de 2 m en perspectiva
	var xl := -8.0
	while xl <= 8.01:
		ci.draw_line(pr.call(xl, 0.0, 30.0), pr.call(xl, 0.0, 2.2), Color(0.85, 0.97, 1.0, 0.18), 1.5, true)
		xl += 2.0
	var zl := 30.0
	while zl >= 2.2:
		ci.draw_line(pr.call(-8.0, 0.0, zl), pr.call(8.0, 0.0, zl), Color(0.85, 0.97, 1.0, 0.18), 1.5, true)
		zl -= 2.0 if zl > 8.0 else 1.0
	# rejillas del suelo (las de la captura, delante y a la derecha)
	for gr in [[1.2, 3.6, 5.0, 7.0], [-4.8, -2.8, 8.0, 10.0], [-0.8, 0.8, 12.0, 13.0]]:
		var x0 := float(gr[0])
		var x1 := float(gr[1])
		var z0 := float(gr[2])
		var z1 := float(gr[3])
		var q := PackedVector2Array([pr.call(x0, 0.0, z0), pr.call(x1, 0.0, z0), pr.call(x1, 0.0, z1), pr.call(x0, 0.0, z1)])
		ci.draw_colored_polygon(q, Color(0.02, 0.18, 0.5, 0.28))
		var n := 7
		for k in n + 1:
			var xx := lerpf(x0, x1, float(k) / n)
			ci.draw_line(pr.call(xx, 0.0, z0), pr.call(xx, 0.0, z1), Color(0.75, 0.92, 1.0, 0.28), 1.2, true)
	# los bordes, mas oscuros
	_degradado_h(ci, Rect2(0, 0, s.x * 0.28, s.y), Color(0.03, 0.08, 0.34, 0.5), Color(0.03, 0.08, 0.34, 0.0))
	_degradado_h(ci, Rect2(s.x * 0.72, 0, s.x * 0.28 + 1.0, s.y), Color(0.03, 0.08, 0.34, 0.0), Color(0.03, 0.08, 0.34, 0.45))
	_degradado_v(ci, Rect2(0, s.y - 90, s.x, 90), Color(0.02, 0.06, 0.3, 0.0), Color(0.02, 0.06, 0.3, 0.35))


## Los cubos que flotan (y la luz del suelo bajo los pies, que sigue al personaje)
func _pintar_cubos(ci: Control) -> void:
	ci.draw_texture_rect(_brillo, Rect2(_vx.x - 300.0 * _vx.z, _vx.y - 90.0 * _vx.z, 600.0 * _vx.z, 180.0 * _vx.z), false,
		Color(0.85, 1.0, 1.0, 0.42))
	for c in _cubos:
		var y := float(c[1]) + sin(_t * float(c[4]) + float(c[3])) * 7.0
		var pos := Vector2(float(c[0]) * ci.size.x, y)
		_cubo_2d(ci, pos, float(c[2]), float(c[6]) + _t * float(c[7]), float(c[5]))


# ================================================================== el centro: la vista 3D
func _montar_centro() -> void:
	_foto = TextureRect.new()
	_foto.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_foto.stretch_mode = TextureRect.STRETCH_SCALE
	_foto.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(_foto)
	# arrastrar gira al personaje
	_gira = Control.new()
	_gira.mouse_filter = Control.MOUSE_FILTER_STOP
	_gira.gui_input.connect(_entrada_gira)
	_raiz.add_child(_gira)


## (centro x, pies y, escala) a donde tiene que ir la vista
func _vista_objetivo() -> Vector3:
	if _sel_slot == "":
		return Vector3((IZQ_ANCHO + _px()) * 0.5, PIES_Y, 1.0)
	return Vector3((_ra() + _w) * 0.5, ALTO - FILA_ALTO - 22.0, clampf((_w - _ra() - 40.0) / 620.0, 0.8, 0.95))


func _colocar_vista() -> void:
	if not is_instance_valid(_foto):
		return
	var pivote := Vector2(VISTA.x * 0.5, PIES_Y - VISTA_Y)
	_foto.size = VISTA
	_foto.pivot_offset = pivote
	_foto.scale = Vector2(_vx.z, _vx.z)
	_foto.position = Vector2(_vx.x, _vx.y) - pivote
	if is_instance_valid(_gira):
		_gira.size = Vector2(320, 520) * _vx.z
		_gira.position = Vector2(_vx.x - _gira.size.x * 0.5, _vx.y - _gira.size.y - 6.0)


func _entrada_gira(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_arrastrando = e.pressed
	elif e is InputEventScreenTouch:
		_arrastrando = e.pressed
	elif _arrastrando and (e is InputEventMouseMotion or e is InputEventScreenDrag):
		if is_instance_valid(_avatar):
			_avatar.rotation.y += e.relative.x * 0.012


func _montar_vista() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(700, 700)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.64, 0.8, 1.0)
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	# de frente algo calida, un contraluz cian (la sala azul de detras) y una de relleno
	for l in [[Vector3(-28, -30, 0), Color(1.0, 0.96, 0.9), 1.45], [Vector3(-14, 165, 0), Color(0.5, 0.88, 1.0), 1.3],
			[Vector3(-20, 60, 0), Color(0.75, 0.85, 1.0), 0.45]]:
		var dl := DirectionalLight3D.new()
		dl.rotation_degrees = l[0]
		dl.light_color = l[1]
		dl.light_energy = l[2]
		_vp.add_child(dl)
	var sombra := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.2, 1.6)
	sombra.mesh = pm
	var ms := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled;
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	ALBEDO = vec3(0.0, 0.06, 0.28);
	ALPHA = (1.0 - smoothstep(0.1, 1.0, d)) * 0.42;
}
"
	ms.shader = sh
	sombra.material_override = ms
	sombra.position.y = 0.005
	_vp.add_child(sombra)
	# la camara: el personaje de 1,75 m ocupa ~560 de los 700 del hueco y tiene los pies en PIES_Y
	_cam = Camera3D.new()
	_poner_camara()
	_vp.add_child(_cam)


func _poner_camara() -> void:
	_cam.fov = 30.0
	var visible_m := 1.75 * VISTA.y / 560.0
	var dist := visible_m / (2.0 * tan(deg_to_rad(15.0)))
	var pies := (PIES_Y - VISTA_Y) / VISTA.y
	_cam.position = Vector3(0.0, (pies - 0.5) * visible_m, dist)
	_cam.rotation = Vector3.ZERO


## Montar el muñeco cuesta ~0,7 s la primera vez: primero que salga la pantalla
func _poner_avatar_luego() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or _cerrando:
		return
	_poner_avatar()


func _poner_avatar() -> void:
	if is_instance_valid(_avatar):
		_avatar.queue_free()
	var i := clampi(Settings.avatar_skin, 0, LobbyScript.SKINS.size() - 1)
	var sk: Dictionary = LobbyScript.SKINS[i]
	var av = AvatarScript.new()
	_vp.add_child(av)
	av.build(1.75, false, sk["c"], true, false, LobbyScript.skin_id(), LobbyScript.skin_receta())
	LobbyScript.aplicar_skin(av)
	av.pose_menu = GUARDIA
	# LA DERECHA AL GATILLO (2026-10-12, pedido: "invertí los brazos"): en este esqueleto los huesos _l son el lado
	# DERECHO del personaje y sin cambiar el gatillo lo llevaba la izquierda. Solo este muñeco de escaparate.
	av._swap_hands = true
	av.pistola_una_mano_menu = true
	av.play("idle_1")
	_avatar = av
	_skin_montada = _clave_skin()
	_arma_puesta = ""
	_poner_arma(false)
	av.rotation.y = _giro_objetivo + 0.5
	_reposo_t = 2.5


static func _clave_skin() -> String:
	return "%d|%s" % [Settings.avatar_skin, LobbyScript.skin_id()]


## EL ARMA EN LAS MANOS: con el selector abierto la que se mira; si no, la de la ranura marcada
func _arma_en_manos() -> String:
	if _sel_slot != "" and _viendo != "":
		return _viendo
	if _slot in Weapons.SLOTS:
		return _arma(_slot)
	return _arma("primary")


func _poner_arma(gesto := true) -> void:
	if not is_instance_valid(_avatar):
		return
	var id := _arma_en_manos()
	var d := Weapons.get_def(id)
	var kind := String(d.get("model", d.get("kind", "rifle")))
	var mid := Weapons.modelo_de(id)
	var clave := "%s|%s|%s" % [kind, mid, SkinsArmas.equipada(mid)]
	if clave == _arma_puesta:
		return
	var otra := not _arma_puesta.begins_with("%s|%s|" % [kind, mid])
	var habia := _arma_puesta != ""
	_arma_puesta = clave
	# EL ESCUDO, CON LAS MANOS DE LA PARTIDA (2026-10-16, bug: "el brazo derecho se pone en el izquierdo y sobresale
	# del escudo"): sus poses ya dicen que mano lleva el asa y cual la pistola; la inversion de la guardia de
	# escaparate (_swap_hands, para las demas armas) se las cambiaba de lado
	_avatar._swap_hands = kind != "escudo"
	_avatar.escudo_delante = 0.05
	_avatar.equip_weapon(kind, mid)
	_avatar.set("_since_fire", 999.0)    # sin encarar: la guardia, quieto
	_avatar.aiming = false
	_avatar.move_amount = 0.0
	_avatar.look_pitch = 0.0
	if kind == "escudo" and _avatar.has_clip("escudo_guardia"):
		_avatar.play("escudo_guardia")
	elif _avatar.current_clip != "idle_1":
		_avatar.play("idle_1")
	if gesto and habia and otra:
		_avatar.hold_swap(0.3)


func _process(dt: float) -> void:
	_t += dt
	if _aviso_t > 0.0:
		_aviso_t -= dt
		if is_instance_valid(_aviso):
			_aviso.modulate.a = clampf(_aviso_t / 0.4, 0.0, 1.0)
	var o := _vista_objetivo()
	if _vx.distance_to(o) > 0.05:
		_vx = _vx.lerp(o, 1.0 - exp(-dt * 9.0))
		_colocar_vista()
	if is_instance_valid(_saldo) and int(_t * 4.0) != int((_t - dt) * 4.0):
		_saldo.queue_redraw()
	if not is_instance_valid(_avatar):
		return
	if _arrastrando:
		_reposo_t = 0.0
	else:
		_reposo_t += dt
		if _reposo_t > 2.5:
			_avatar.rotation.y = lerp_angle(_avatar.rotation.y, _giro_objetivo, 1.0 - exp(-dt * 2.4))


# ================================================================== arriba: el saldo y la casa
const SALDO_PASTILLA := 140.0

func _montar_arriba() -> void:
	_boton(Rect2(_w - 150, 0, 150, 70), _pintar_casa, _cerrar, _raiz)
	var ancho := SALDO_PASTILLA * 3.0 + 16.0
	_saldo = _dibujo(Vector2(_w - 150 - 14 - ancho, 12), Vector2(ancho, 52), _pintar_saldo, _raiz)
	_saldo_cubo = _icono("cubo_fuerza", COLOR_CUBOS, Vector2(-2, 6), 40, _saldo)


func _pintar_casa(ci: Control) -> void:
	var w := ci.size.x
	var h := ci.size.y
	var forma := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(18, h), Vector2(0, h - 18)])
	var sombra := PackedVector2Array()
	for p in forma:
		sombra.append(p + Vector2(0, 4))
	ci.draw_colored_polygon(sombra, Color(0, 0.02, 0.2, 0.35))
	ci.draw_colored_polygon(forma, CIAN)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.45), Vector2(0, h * 0.45)]),
		Color(1, 1, 1, 0.14))
	var c := Vector2(w * 0.54, 36)
	var casa := PackedVector2Array([c + Vector2(-24, -1), c + Vector2(0, -22), c + Vector2(24, -1), c + Vector2(17, -1),
		c + Vector2(17, 20), c + Vector2(-17, 20), c + Vector2(-17, -1)])
	ci.draw_colored_polygon(casa, Color.WHITE)
	ci.draw_rect(Rect2(c + Vector2(-6, 6), Vector2(12, 14)), CIAN)


func _pintar_saldo(ci: Control) -> void:
	var valores := [Settings.saldo_cubos(), Settings.saldo(), Settings.saldo_creditos()]
	for i in 3:
		var x0 := 16.0 + i * SALDO_PASTILLA
		var r := Rect2(x0 + 8.0, 9.0, SALDO_PASTILLA - 30.0, 34.0)
		ci.draw_colored_polygon(_caja(r, 9.0), Color(0.01, 0.04, 0.24, 0.55))
		var c := Vector2(x0 + 6.0, 26.0)
		if i == 0:
			_saldo_cubo.position = Vector2(c.x - 22.0, c.y - 22.0)
			_saldo_cubo.size = Vector2(44, 44)
		elif i == 1:
			_moneda(ci, c + Vector2(0, -2), 17.0)
		else:
			_gema(ci, c + Vector2(0, -1), 17.0)
		var t := _con_puntos(int(valores[i]))
		var tam := _cabe(t, 24, r.size.x - 34.0, 15)
		_txt(ci, t, Vector2(r.position.x + 26.0, _base(r.get_center().y, tam)), tam, Color.WHITE,
			HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 34.0, 5)


# ================================================================== la izquierda: las CARTAS y el menu
func _cartas():
	if _cartas_script == null and ResourceLoader.exists(RUTA_CARTAS):
		_cartas_script = load(RUTA_CARTAS)
	return _cartas_script


func _cartas_equipadas() -> Array:
	var c = _cartas()
	if c == null:
		return []
	var eq = c.equipadas()
	return eq if eq is Array else []


func _avisos_cartas() -> int:
	var c = _cartas()
	return int(c.avisos()) if c != null else 0


func _carta_en(i: int) -> String:
	var eq := _cartas_equipadas()
	return String(eq[i]) if i < eq.size() else ""


func _montar_izquierda(padre: Control) -> void:
	var titulo := _texto("Armería", 50, Color.WHITE, 8, _f)
	titulo.position = Vector2(62, 8)
	padre.add_child(titulo)
	_boton(Rect2(64, 90, 352, 48), _pintar_ir_cartas, _ir_cartas, padre)
	var c = _cartas()
	for i in 8:
		var r := Rect2(62 + (i % 4) * 90, 146 + floori(i / 4.0) * 120, 86, 114)
		var b := _boton(r, _pintar_casilla_carta.bind(i), _tocar_carta.bind(i), padre)
		var id := _carta_en(i)
		if id != "" and c != null:
			# el hexagono brillante de la carta (icono_lobby "carta_<x>", en su color); debajo va uno liso por si faltara
			var d: Dictionary = c.datos(id)
			_icono(String(d.get("icono", "")), d.get("color", LAVANDA) as Color, Vector2(43 - 32, 42 - 32), 64, b)
			_dibujo(Vector2.ZERO, r.size, _pintar_casilla_carta_encima.bind(i), b)
	# el bloque morado de abajo
	_dibujo(Vector2(0, 470), Vector2(IZQ_ANCHO, ALTO - 470), _pintar_bloque, padre)
	var acciones := [_ir_cartas, _ir_personaje.bind(false), _ir_personaje.bind(true)]
	for k in 3:
		_boton(Rect2(14, 478 + k * 78, 380, 72), _pintar_menu.bind(k), acciones[k], padre)


func _pintar_ir_cartas(ci: Control) -> void:
	var w := ci.size.x
	var h := ci.size.y
	ci.draw_rect(Rect2(0, 5, w - 44, h - 10), Color(0.02, 0.06, 0.3, 0.55))
	ci.draw_rect(Rect2(0, 5, 4, h - 10), Color(1, 1, 1, 0.5))
	_txt(ci, "IR A CARTAS", Vector2(16, _base(h * 0.5, 21)), 21, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
	# la caja blanca con las dos flechas
	var bx := Rect2(w - 50, 0, 50, h)
	ci.draw_rect(Rect2(bx.position + Vector2(0, 3), bx.size), Color(0, 0.02, 0.2, 0.35))
	ci.draw_colored_polygon(_caja(bx, 4.0), Color.WHITE)
	var c := bx.get_center()
	for dx in [-7.0, 6.0]:
		ci.draw_polyline(PackedVector2Array([c + Vector2(dx - 5, -9), c + Vector2(dx + 4, 0), c + Vector2(dx - 5, 9)]), TINTA, 4.0, true)
	var n := _avisos_cartas()
	if n > 0:
		_globo(ci, Vector2(w - 4, 4), 12.0, str(n))


func _pintar_casilla_carta(ci: Control, i: int) -> void:
	var r := Rect2(Vector2.ZERO, ci.size)
	var id := _carta_en(i)
	ci.draw_rect(Rect2(r.position + Vector2(0, 3), r.size), Color(0.05, 0.04, 0.3, 0.35))
	if id == "":
		# vacia: tenue
		ci.draw_rect(r, Color(LAVANDA, 0.32))
		ci.draw_rect(r.grow(-1.0), Color(1, 1, 1, 0.16), false, 2.0)
		var cc := Vector2(r.size.x * 0.5, 42.0)
		ci.draw_colored_polygon(_hex(cc, 28.0), Color(1, 1, 1, 0.08))
		var h := _hex(cc, 28.0)
		h.append(h[0])
		ci.draw_polyline(h, Color(1, 1, 1, 0.22), 2.0, true)
		return
	_degradado_v(ci, r, LAVANDA_CLARA, LAVANDA)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(r.size.x, 0), Vector2(0, r.size.y * 0.6)]), Color(1, 1, 1, 0.1))
	ci.draw_rect(r.grow(-1.0), Color(1, 1, 1, 0.5), false, 2.0)
	ci.draw_rect(r, Color(0.2, 0.12, 0.5, 0.6), false, 1.0)
	var c = _cartas()
	var d: Dictionary = c.datos(id) if c != null else {}
	_hexagono(ci, Vector2(r.size.x * 0.5, 42.0), 28.0, d.get("color", LAVANDA) as Color)


## Encima del icono: el nombre, el nivel, la flecha de mejorar y lo nuevo
func _pintar_casilla_carta_encima(ci: Control, i: int) -> void:
	var id := _carta_en(i)
	var c = _cartas()
	if id == "" or c == null:
		return
	var d: Dictionary = c.datos(id)
	var w := ci.size.x
	var h := ci.size.y
	# el nombre, en una linea o en dos (partido por el espacio mas centrado) si no cabe
	var nombre := String(d.get("nombre", id))
	var lineas: Array = [nombre]
	if _ancho(nombre, 11, _fn) > w - 8:
		var mejor := -1
		for k in nombre.length():
			if nombre[k] == " " and (mejor < 0 or absi(k - nombre.length() / 2) < absi(mejor - nombre.length() / 2)):
				mejor = k
		if mejor > 0:
			lineas = [nombre.substr(0, mejor), nombre.substr(mejor + 1)]
	for k in lineas.size():
		var linea := String(lineas[k])
		var tam := _cabe(linea, 11, w - 6, 8, _fn)
		var cy := h - 11.0 - 12.0 * float(lineas.size() - 1 - k)
		_txt(ci, linea, Vector2(0, _base(cy, tam, _fn)), tam, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, w, 3, _fn)
	# el nivel, en una pastilla bajo el hexagono
	var nv := "NV %d" % int(c.nivel(id))
	var pw := _ancho(nv, 12, _fn) + 10.0
	var pr := Rect2(w * 0.5 - pw * 0.5, 64.0, pw, 16)
	ci.draw_colored_polygon(_caja(pr, 5.0), Color(0.03, 0.05, 0.25, 0.85))
	_txt(ci, nv, Vector2(pr.position.x, _base(pr.get_center().y, 12, _fn)), 12, AMARILLO, HORIZONTAL_ALIGNMENT_CENTER, pw, 0, _fn)
	# la flecha naranja de "se puede mejorar" (la de la captura) y el punto de nueva
	if bool(c.copias_listas(id)):
		var p := Vector2(w - 12, 64)
		_con_borde(ci, _pts(p, 8.0, [[0, -1], [1, 0], [0.4, 0], [0.4, 0.9], [-0.4, 0.9], [-0.4, 0], [-1, 0]]), Color8(255, 150, 30), 2.5)
	if bool(c.nueva(id)):
		_globo(ci, Vector2(w - 6, 6), 7.0, "")


func _tocar_carta(i: int) -> void:
	var id := _carta_en(i)
	if id == "" and _cartas() != null:
		Audio.ui("aceptar", -10.0)
		_avisar("RANURA DE CARTA VACÍA · equipa una en CARTAS")
		return
	_ir_cartas()


func _pintar_bloque(ci: Control) -> void:
	var s := ci.size
	var forma := PackedVector2Array([Vector2(0, 0), Vector2(s.x - 16, 0), Vector2(s.x, 16), Vector2(s.x, s.y), Vector2(0, s.y)])
	ci.draw_polygon(forma, PackedColorArray([BLOQUE_CLARO, BLOQUE_CLARO, BLOQUE_CLARO, BLOQUE, BLOQUE]))
	ci.draw_polyline(PackedVector2Array([Vector2(0, 1), Vector2(s.x - 16, 1), Vector2(s.x - 1, 16)]), Color(1, 1, 1, 0.3), 2.0, true)


func _pintar_menu(ci: Control, k: int) -> void:
	var h := ci.size.y
	var nombre: String = ["CARTAS", "PERSONAJE", "ESTILO"][k]
	var icono: String = ["cartas", "personaje", "pintura"][k]
	var c := Vector2(84, h * 0.5)
	_glifo(ci, icono, c, 20.0)
	_txt(ci, nombre, Vector2(128, _base(h * 0.5, 32)), 32, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 6)
	var n := 0
	if k == 0:
		n = _avisos_cartas()
	elif k == 1 and NivelPersonaje.que_falta(NivelPersonaje.equipado()) == "":
		n = 1       # se le puede subir la fuerza ya
	if n > 0:
		_globo(ci, c + Vector2(20, -20), 12.0, str(n))


func _ir_cartas() -> void:
	if is_instance_valid(lobby) and lobby.has_method("_abrir_cartas") and ResourceLoader.exists(RUTA_CARTAS_PANTALLA):
		Audio.ui("aceptar", -8.0)
		var p = lobby._abrir_cartas()
		if p != null and p.has_signal("cerrado") and not p.is_connected("cerrado", _al_volver):
			p.connect("cerrado", _al_volver)
		return
	Audio.ui("aceptar", -10.0)
	_avisar("CARTAS · PRÓXIMAMENTE")


func _ir_personaje(skins: bool) -> void:
	if not is_instance_valid(lobby) or not lobby.has_method("_abrir_personaje"):
		return
	Audio.ui("aceptar", -8.0)
	var p = lobby._abrir_personaje()
	if p == null:
		return
	if skins and p.has_method("_ver_skins"):
		p.call_deferred("_ver_skins", true)
	if p.has_signal("cerrado") and not p.is_connected("cerrado", _al_volver):
		p.connect("cerrado", _al_volver)


## Al volver de otra pantalla (personaje, tienda, cartas): pudo cambiar la skin, lo comprado o las cartas
func _al_volver() -> void:
	if _cerrando or not is_inside_tree():
		return
	if is_instance_valid(lobby) and lobby.has_method("set_chrome_visible"):
		lobby.call_deferred("set_chrome_visible", false)
	_montar.call_deferred()
	# el muñeco solo se rehace si cambio la skin (montarlo cuesta ~0,7 s); si no, basta con repintar el arma
	if _skin_montada != _clave_skin():
		_poner_avatar.call_deferred()
	else:
		_arma_puesta = ""
		_poner_arma.call_deferred(false)


# ================================================================== la derecha: EQUIPAMIENTO ACTIVO
func _montar_derecha(padre: Control) -> void:
	var der := Control.new()
	der.mouse_filter = Control.MOUSE_FILTER_IGNORE
	der.position = Vector2(_px(), 0)
	der.size = Vector2(PANEL_W, ALTO)
	padre.add_child(der)
	_dibujo(Vector2.ZERO, der.size, _pintar_panel, der)
	_boton(Rect2(12, 194, 32, 36), _pintar_info, _tocar_info, der)
	_icono("cubo_fuerza", COLOR_CUBOS, Vector2(50, 191), 42, der)
	# LA FICHA DEL PERSONAJE: el retrato (la cabeza y el pecho del retrato horneado), SOLDADO y la skin
	var pj := NivelPersonaje.equipado()
	var ficha := _boton(Rect2(12, 250, PANEL_W - 24, 122), _pintar_ficha, _ir_personaje.bind(false), der)
	var marco := Control.new()
	marco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marco.clip_contents = true
	marco.position = Vector2(4, 4)
	marco.size = Vector2(114, 114)
	ficha.add_child(marco)
	marco.add_child(_retrato_skin(Vector2(114, 114)))
	_dibujo(Vector2.ZERO, ficha.size, _pintar_ficha_encima, ficha)
	var hab := String(NivelPersonaje.datos(pj).get("habilidad", "gancho"))
	_icono(String(HabilidadScript.datos(hab).get("icono", "gancho")), Color.WHITE, Vector2(12, 92), 22, ficha)
	_icono("usuario", Color.WHITE, Vector2(143, 75), 26, ficha)
	# LAS RANURAS
	for i in RANURAS.size():
		var r := _rect_ranura(i)
		var b := _boton(r, _pintar_ranura.bind(i, false), _tocar_ranura.bind(i), der)
		var img := _miniatura(String(RANURAS[i]["id"]), Vector2(170, 74) if i < 2 else Vector2(110, 56))
		_encajar(img, Rect2(8, 16, r.size.x - 16, r.size.y - 42))
		b.add_child(img)
		_dibujo(Vector2.ZERO, r.size, _pintar_ranura_encima.bind(i, false), b)
	# LOS TRES EQUIPOS
	var pw := (PANEL_W - 24.0) / 3.0
	for i in 3:
		_boton(Rect2(12 + i * pw, 632, pw, 50), _pintar_pestana.bind(i), _cambiar_preset.bind(i), der)


func _rect_ranura(i: int) -> Rect2:
	if i == 0:
		return Rect2(12, 384, 178, 112)
	if i == 1:
		return Rect2(198, 384, 178, 112)
	return Rect2(12 + (i - 2) * 124, 504, 116, 112)


## La miniatura de lo que va en una ranura (cocinada por el lobby, con la pintura puesta)
func _miniatura(slot: String, tam: Vector2) -> Control:
	if not is_instance_valid(lobby):
		return Control.new()
	if slot == "granada":
		return lobby._retrato("granada:mini", tam, func(mundo: Node3D, cam: Camera3D, sv: SubViewport):
			mundo.add_child(AvatarScript.malla_granada(1.0))
			lobby._encuadrar_mini(mundo, cam, sv))
	if slot == "c4":
		return lobby._mini_arma_3d("c4", tam)
	return _mini_arma(_arma(slot), tam)


func _mini_arma(id: String, tam: Vector2) -> Control:
	if not is_instance_valid(lobby):
		return Control.new()
	var mid := Weapons.modelo_de(id)
	var skin := SkinsArmas.equipada(mid)
	if mid != id:
		return lobby._mini_arma_3d(mid, tam, "sledge", skin)
	return lobby._mini_arma_3d(id, tam, "", skin)


## Encaja una miniatura (TextureRect del lobby) en un hueco: sin tamaño minimo, estirada a lo que quepa
static func _encajar(img: Control, r: Rect2) -> void:
	img.custom_minimum_size = Vector2.ZERO
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if img is TextureRect:
		(img as TextureRect).expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		(img as TextureRect).stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.position = r.position
	img.size = r.size
	img.pivot_offset = r.size * 0.5


## El retrato de la skin puesta: la cabeza y el pecho del retrato horneado (avatar/retratos/<nombre>.png)
func _retrato_skin(tam: Vector2) -> Control:
	var i := clampi(Settings.avatar_skin, 0, LobbyScript.SKINS.size() - 1)
	var ruta := "res://avatar/retratos/%s.png" % String(LobbyScript.SKINS[i]["n"]).to_lower().replace(" ", "_")
	var tr := TextureRect.new()
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.size = tam
	if ResourceLoader.exists(ruta):
		var tex: Texture2D = load(ruta)
		var at := AtlasTexture.new()
		at.atlas = tex
		var s := tex.get_size()
		at.region = Rect2(s.x * 0.19, s.y * 0.04, s.x * 0.62, s.x * 0.62)
		tr.texture = at
		return tr
	if is_instance_valid(lobby) and lobby.has_method("_mini_avatar_3d"):
		var m: Control = lobby._mini_avatar_3d(i, tam)
		_encajar(m, Rect2(Vector2.ZERO, tam))
		return m
	return tr


func _pintar_panel(ci: Control) -> void:
	var w := ci.size.x
	# la cabecera blanca
	var cab := PackedVector2Array([Vector2(0, 126), Vector2(w, 126), Vector2(w, 168), Vector2(w - 12, 180), Vector2(0, 180)])
	var sombra := PackedVector2Array()
	for p in cab:
		sombra.append(p + Vector2(0, 4))
	ci.draw_colored_polygon(sombra, Color(0, 0.02, 0.2, 0.3))
	ci.draw_colored_polygon(cab, Color(0.97, 0.98, 1.0))
	_txt(ci, "EQUIPAMIENTO ACTIVO", Vector2(18, _base(153, 22)), 22, TINTA, HORIZONTAL_ALIGNMENT_LEFT, -1, 0)
	# el cuerpo
	var cuerpo := Rect2(0, 180, w, 520)
	ci.draw_rect(cuerpo, PANEL)
	ci.draw_rect(cuerpo, PANEL_BORDE, false, 2.0)
	# la fila de la fuerza y la salud
	ci.draw_rect(Rect2(2, 186, w - 4, 50), Color(0.02, 0.06, 0.3, 0.4))
	var pj := NivelPersonaje.equipado()
	_txt(ci, str(NivelPersonaje.nivel(pj)), Vector2(98, _base(212, 34)), 34, AMARILLO, HORIZONTAL_ALIGNMENT_LEFT, -1, 6)
	var salud := str(NivelPersonaje.salud(pj))
	var sw := _ancho(salud, 34)
	_glifo(ci, "corazon", Vector2(w - 26 - sw - 18, 211), 13.0, ROJO)
	_txt(ci, salud, Vector2(w - 14 - sw, _base(212, 34)), 34, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 6)
	ci.draw_line(Vector2(10, 242), Vector2(w - 10, 242), Color(0.6, 0.82, 1.0, 0.35), 2.0)
	# la fila de los equipos
	var fr := Rect2(12, 632, w - 24, 50)
	ci.draw_rect(Rect2(fr.position + Vector2(0, 3), fr.size), Color(0, 0.02, 0.2, 0.35))
	ci.draw_rect(fr, PESTANAS)
	ci.draw_rect(fr, Color(0.5, 0.7, 1.0, 0.3), false, 1.5)
	var pw := fr.size.x / 3.0
	for i in [1, 2]:
		ci.draw_line(Vector2(fr.position.x + pw * i, fr.position.y + 10), Vector2(fr.position.x + pw * i, fr.end.y - 10),
			Color(1, 1, 1, 0.22), 2.0)


func _pintar_info(ci: Control) -> void:
	var r := Rect2(Vector2.ZERO, ci.size)
	ci.draw_colored_polygon(_caja(r, 4.0), Color(0.62, 0.7, 0.92, 0.9))
	_txt(ci, "i", Vector2(0, _base(r.size.y * 0.5, 26)), 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 4)


func _tocar_info() -> void:
	Audio.ui("aceptar", -10.0)
	var pj := NivelPersonaje.equipado()
	_avisar("FUERZA %d: el nivel del personaje (súbelo en PERSONAJE)  ·  SALUD %d" % [NivelPersonaje.nivel(pj), NivelPersonaje.salud(pj)])


func _pintar_ficha(ci: Control) -> void:
	var w := ci.size.x
	var pr := Rect2(2, 2, 118, 118)
	ci.draw_rect(Rect2(pr.position + Vector2(0, 3), pr.size), Color(0, 0.02, 0.2, 0.35))
	_degradado_v(ci, pr, Color8(168, 222, 255), Color8(84, 156, 236))
	ci.draw_texture_rect(_brillo, Rect2(pr.position + Vector2(-20, -10), pr.size + Vector2(40, 40)), false, Color(1, 1, 1, 0.35))
	var pj := NivelPersonaje.equipado()
	var nombre := String(NivelPersonaje.datos(pj).get("nombre", "SOLDADO"))
	var tam := _cabe(nombre, 40, w - 136, 24)
	_txt(ci, nombre, Vector2(132, _base(30, tam)), tam, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 7)
	# la skin, en su tira
	var tira := Rect2(132, 64, w - 134, 48)
	ci.draw_colored_polygon(_caja(tira, 6.0), Color(0.02, 0.05, 0.26, 0.6))
	var mini := Rect2(138, 70, 36, 36)
	_degradado_v(ci, mini, Color8(120, 236, 255), Color8(40, 150, 230))
	ci.draw_rect(mini, Color(1, 1, 1, 0.7), false, 1.5)
	var sk := LobbyScript.skin_nombre()
	var nom := TiendaAjustes.nombre("modelo:" + sk, sk).to_upper()
	var t2 := _cabe(nom, 21, tira.size.x - 56, 12)
	_txt(ci, nom, Vector2(184, _base(tira.get_center().y, t2)), t2, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 4)


func _pintar_ficha_encima(ci: Control) -> void:
	var pr := Rect2(2, 2, 118, 118)
	ci.draw_rect(pr, Color(1, 1, 1, 0.85), false, 2.0)
	var pj := NivelPersonaje.equipado()
	_globo(ci, Vector2(pr.end.x - 6, pr.position.y + 6), 14.0, str(NivelPersonaje.nivel(pj)))
	# la habilidad y su nivel, abajo (el icono lo pone un IconoLobby encima)
	var pill := Rect2(6, 90, 62, 26)
	ci.draw_colored_polygon(_caja(pill, 7.0), Color(0.02, 0.05, 0.25, 0.8))
	_txt(ci, str(NivelPersonaje.nivel_habilidad(pj)), Vector2(34, _base(pill.get_center().y, 20)), 20, VERDE,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 4)


## Una casilla de arma: azul claro con su brillo; la que se mira, con el borde amarillo
func _pintar_casilla(ci: Control, marcada: bool, apagada := false) -> void:
	var r := Rect2(Vector2.ZERO, ci.size)
	ci.draw_rect(Rect2(r.position + Vector2(0, 4), r.size), Color(0, 0.02, 0.2, 0.35))
	if apagada:
		ci.draw_rect(r, Color(LAVANDA, 0.3))
		var cc := r.get_center()
		var h := _hex(cc, minf(r.size.x, r.size.y) * 0.3)
		ci.draw_colored_polygon(h, Color(1, 1, 1, 0.06))
		h.append(h[0])
		ci.draw_polyline(h, Color(1, 1, 1, 0.16), 2.0, true)
		ci.draw_rect(r.grow(-1.0), Color(1, 1, 1, 0.14), false, 2.0)
		return
	_degradado_v(ci, r, CASILLA_A, CASILLA_B)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(r.size.x * 0.62, 0), Vector2(0, r.size.y * 0.75)]),
		Color(1, 1, 1, 0.12))
	ci.draw_texture_rect(_brillo, Rect2(r.size.x * 0.1, r.size.y * 0.05, r.size.x * 0.8, r.size.y * 0.8), false, Color(1, 1, 1, 0.22))
	if marcada:
		ci.draw_rect(r.grow(2.0), Color(AMARILLO, 0.35), false, 4.0)
		ci.draw_rect(r.grow(-1.5), AMARILLO, false, 3.5)
	else:
		ci.draw_rect(r.grow(-1.0), Color(0.86, 0.95, 1.0, 0.85), false, 2.0)


func _pintar_ranura(ci: Control, i: int, fila: bool) -> void:
	var slot := String(RANURAS[i]["id"])
	_pintar_casilla(ci, (slot == _sel_slot) if fila else (slot == _slot and _sel_slot == ""))


## Encima de la miniatura: el nombre, la tecla (el globo rojo), el PODER y la pintura
func _pintar_ranura_encima(ci: Control, i: int, fila: bool) -> void:
	var w := ci.size.x
	var h := ci.size.y
	var slot := String(RANURAS[i]["id"])
	var chica := fila or i >= 2
	if not fila:
		_txt(ci, String(RANURAS[i]["nombre"]).to_upper(), Vector2(8, _base(12, 11, _fn)), 11, Color(1, 1, 1, 0.9),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 3, _fn)
	_globo(ci, Vector2(w - 12, 12), 11.0 if chica else 13.0, String(RANURAS[i]["tecla"]))
	var poder := str(_poder(_def_ranura(slot)))
	var tam := 16 if chica else 20
	var pw := _ancho(poder, tam) + 26.0
	var pill := Rect2(w - pw - 5, h - (22.0 if chica else 27.0) - 4, pw, 22.0 if chica else 27.0)
	ci.draw_colored_polygon(_caja(pill, 6.0), Color(0.02, 0.05, 0.25, 0.78))
	_glifo(ci, "rayo", Vector2(pill.position.x + 11, pill.get_center().y), 7.0 if chica else 8.5, AMARILLO, false)
	_txt(ci, poder, Vector2(pill.position.x + 20, _base(pill.get_center().y, tam)), tam, AMARILLO, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
	# la pintura puesta: una gota del color de su rareza
	if slot in Weapons.SLOTS:
		var sk := SkinsArmas.equipada(Weapons.modelo_de(_arma(slot)))
		if sk != "":
			var c := Vector2(13, h - 14)
			ci.draw_circle(c, 10.0, Color.WHITE)
			ci.draw_circle(c, 8.0, SkinsArmas.rareza_de(sk)["color"] as Color)
			_glifo(ci, "gota", c, 5.0, Color.WHITE, false)


func _tocar_ranura(i: int) -> void:
	var slot := String(RANURAS[i]["id"])
	if slot == "c4":
		Audio.ui("aceptar", -10.0)
		_avisar("C4 · va siempre contigo en los mapas de bomba (tecla 4: pégala y otra vez para detonar)")
		return
	if slot == "granada":
		Audio.ui("aceptar", -10.0)
		_avisar("GRANADA · va siempre contigo (tecla G)")
		return
	_abrir_selector(slot)


func _pintar_pestana(ci: Control, i: int) -> void:
	var w := ci.size.x
	var h := ci.size.y
	var activo := i == _preset_activo()
	if activo:
		var forma := _inclinada(Rect2(0, 0, w, h), 12.0) if i > 0 else PackedVector2Array([Vector2(0, 0), Vector2(w, 0),
			Vector2(w - 12, h), Vector2(0, h)])
		ci.draw_colored_polygon(forma, AMARILLO)
		ci.draw_colored_polygon(PackedVector2Array([forma[0], forma[1], forma[1] + Vector2(-3, h * 0.45), forma[0] + Vector2(0, h * 0.45)]),
			Color(1, 1, 1, 0.22))
	_txt(ci, str(i + 1), Vector2(0, _base(h * 0.5, 32)), 32, TINTA if activo else Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, w,
		0 if activo else 5)


# ================================================================== EL SELECTOR
func _abrir_selector(slot: String) -> void:
	Audio.ui("aceptar", -8.0)
	_sel_slot = slot
	_slot = slot
	_viendo = _arma(slot)
	_marcar_visto(_viendo)
	_plegado = false
	_pintura_abierta = false
	_scroll_rejilla = 0
	_montar()
	_poner_arma()
	# entra de lado: el selector desde la izquierda y la fila de ranuras desde abajo
	_selector.position.x = -SEL_IZQ - _det_ancho()
	create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_property(_selector, "position:x", 0.0, 0.24)


func _cerrar_selector() -> void:
	if _sel_slot == "":
		return
	Audio.ui("atras", -8.0)
	_sel_slot = ""
	_pintura_abierta = false
	_plegado = false
	_montar()
	_poner_arma()
	_capa_armeria.modulate.a = 0.0
	create_tween().tween_property(_capa_armeria, "modulate:a", 1.0, 0.18)


func _montar_selector(padre: Control) -> void:
	_selector = Control.new()
	_selector.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selector.size = Vector2(SEL_IZQ + _det_ancho() + 30.0, ALTO)
	padre.add_child(_selector)
	# el panel de la que miras (detras de la columna: al recogerlo se mete debajo)
	var dw := _det_ancho()
	_detalle = Control.new()
	_detalle.mouse_filter = Control.MOUSE_FILTER_STOP
	_detalle.position = Vector2(SEL_IZQ - (dw if _plegado else 0.0), 0)
	_detalle.size = Vector2(dw, ALTO)
	_selector.add_child(_detalle)
	_montar_detalle(_detalle)
	# la columna de las armas
	var col := Control.new()
	col.mouse_filter = Control.MOUSE_FILTER_STOP
	col.size = Vector2(SEL_IZQ, ALTO)
	_selector.add_child(col)
	_dibujo(Vector2.ZERO, col.size, _pintar_columna, col)
	var t := _texto(String(_nombre_ranura(_sel_slot)), 30, Color.WHITE, 6, _f)
	t.position = Vector2(58, 14)
	col.add_child(t)
	_rejilla_sc = ScrollContainer.new()
	_rejilla_sc.position = Vector2(8, 70)
	_rejilla_sc.size = Vector2(SEL_IZQ - 12, ALTO - 78)
	_rejilla_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_barra_fina(_rejilla_sc)
	col.add_child(_rejilla_sc)
	var rej := GridContainer.new()
	rej.columns = 2
	rej.add_theme_constant_override("h_separation", 8)
	rej.add_theme_constant_override("v_separation", 8)
	_rejilla_sc.add_child(rej)
	var ids := _armas_selector(_sel_slot)
	for id in ids:
		rej.add_child(_carta_arma(String(id)))
	# se completa la ultima fila, y dos filas mas de casillas vacias (las de la captura)
	var huecos := (2 - ids.size() % 2) % 2 + 4
	for _i in huecos:
		var v := _Dibujo.new()
		v.custom_minimum_size = Vector2(113, 100)
		v.pintar = func(ci: Control): _pintar_casilla(ci, false, true)
		rej.add_child(v)
	var sc := _scroll_rejilla
	(func(): if is_instance_valid(_rejilla_sc): _rejilla_sc.scroll_vertical = sc).call_deferred()


## La barra de desplazamiento, fina y lila (la del tema por defecto era un tocho gris)
static func _barra_fina(sc: ScrollContainer) -> void:
	var b := sc.get_v_scroll_bar()
	var g := StyleBoxFlat.new()
	g.bg_color = Color(0.8, 0.76, 1.0, 0.45)
	g.set_corner_radius_all(3)
	g.content_margin_left = 3
	g.content_margin_right = 3
	var g2 := g.duplicate() as StyleBoxFlat
	g2.bg_color = Color(0.9, 0.86, 1.0, 0.75)
	var pista := StyleBoxFlat.new()
	pista.bg_color = Color(0, 0, 0, 0.12)
	pista.set_corner_radius_all(3)
	pista.content_margin_left = 3
	pista.content_margin_right = 3
	b.add_theme_stylebox_override("scroll", pista)
	b.add_theme_stylebox_override("scroll_focus", pista)
	b.add_theme_stylebox_override("grabber", g)
	b.add_theme_stylebox_override("grabber_highlight", g2)
	b.add_theme_stylebox_override("grabber_pressed", g2)


static func _nombre_ranura(slot: String) -> String:
	for r in RANURAS:
		if String(r["id"]) == slot:
			return String(r["nombre"])
	return slot


func _pintar_columna(ci: Control) -> void:
	var r := Rect2(Vector2.ZERO, ci.size)
	_degradado_v(ci, r, VIOLETA_OSCURO.lightened(0.06), VIOLETA_OSCURO.darkened(0.18))
	ci.draw_line(Vector2(r.size.x - 1, 0), Vector2(r.size.x - 1, r.size.y), Color(1, 1, 1, 0.14), 2.0)
	ci.draw_rect(Rect2(0, 0, r.size.x, 62), Color(0, 0, 0.1, 0.25))
	var glifo := "rifle"
	if _sel_slot == "secondary":
		glifo = "pistola"
	elif _sel_slot == "heavy":
		glifo = "mazo"
	_glifo(ci, glifo, Vector2(32, 32), 16.0)


## Una carta de arma del selector: la tuya en azul con su PODER; la que miras, con borde amarillo; la puesta, con el
## visto; las que no has mirado, NUEVO; las que no tienes, tenues con candado
func _carta_arma(id: String) -> Control:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.clip_contents = true
	b.set_meta("sin_sonido", true)
	b.custom_minimum_size = Vector2(113, 100)
	for e in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(e, StyleBoxEmpty.new())
	var mia := Settings.tengo_arma(id)
	var fondo := _Dibujo.new()
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fondo.pintar = func(ci: Control): _pintar_casilla(ci, false, not mia)
	b.add_child(fondo)
	var img := _mini_arma(id, Vector2(150, 64))
	_encajar(img, Rect2(4, 14, 105, 62))
	img.rotation = deg_to_rad(-24.0)
	if not mia:
		img.modulate = Color(0.75, 0.7, 1.0, 0.4)
	b.add_child(img)
	var encima := _Dibujo.new()
	encima.set_anchors_preset(Control.PRESET_FULL_RECT)
	encima.pintar = _pintar_carta_arma_encima.bind(id)
	b.add_child(encima)
	b.pressed.connect(_ver_arma.bind(id))
	return b


func _pintar_carta_arma_encima(ci: Control, id: String) -> void:
	var w := ci.size.x
	var h := ci.size.y
	var mia := Settings.tengo_arma(id)
	if id == _viendo:
		ci.draw_rect(Rect2(1.5, 1.5, w - 3, h - 3), AMARILLO, false, 3.5)
	if mia:
		var poder := str(_poder(Weapons.get_def(id)))
		var pw := _ancho(poder, 24)
		_glifo(ci, "rayo", Vector2(w - pw - 18, h - 16), 9.0, VERDE)
		_txt(ci, poder, Vector2(w - pw - 7, _base(h - 16, 24)), 24, VERDE, HORIZONTAL_ALIGNMENT_LEFT, -1, 5)
	else:
		_glifo(ci, "candado", Vector2(w - 16, h - 16), 9.0, Color(1, 1, 1, 0.85))
		var precio := _con_puntos(Weapons.precio(id))
		_txt(ci, precio, Vector2(6, _base(h - 15, 14)), 14, Color(1, 0.9, 0.6, 0.9), HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
	# la puesta en ESTA ranura: el visto amarillo; si va en otra, su tecla
	if mia and _arma(_sel_slot) == id:
		ci.draw_circle(Vector2(w - 14, 14), 12.0, TINTA)
		ci.draw_circle(Vector2(w - 14, 14), 10.0, AMARILLO)
		_glifo(ci, "check", Vector2(w - 14, 14), 6.5, TINTA, false)
	elif mia:
		for i in 3:
			var s := String(Weapons.SLOTS[i])
			if s != _sel_slot and _arma(s) == id:
				_globo(ci, Vector2(w - 13, 13), 9.0, str(i + 1), Color(0.3, 0.34, 0.5))
				break
	# NUEVA (no la has mirado): la cinta roja en la esquina
	if mia and not _visto(id):
		ci.draw_colored_polygon(PackedVector2Array([Vector2(0, 16), Vector2(16, 0), Vector2(44, 0), Vector2(0, 44)]), ROJO)
		ci.draw_set_transform(Vector2(15, 17), -PI * 0.25, Vector2.ONE)
		_txt(ci, "NUEVO", Vector2(-24, _base(0, 11, _fn)), 11, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 48, 0, _fn)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _ver_arma(id: String) -> void:
	if id == _viendo:
		return
	Audio.ui("aceptar", -12.0)
	_viendo = id
	_marcar_visto(id)
	if _pintura_abierta and not Settings.tengo_arma(id):
		_pintura_abierta = false
	_montar()
	_poner_arma()


# ------------------------------------------------------------------ el panel de la que miras
func _montar_detalle(det: Control) -> void:
	var dw := det.size.x
	var id := _viendo
	var mia := Settings.tengo_arma(id)
	_dibujo(Vector2.ZERO, det.size, _pintar_detalle, det)
	var nombre := _nombre_arma(id)
	var tam := _cabe(nombre, 34, dw - 200, 20)
	var nom := _texto(nombre, tam, Color.WHITE, 6, _f)
	nom.position = Vector2(22, 12)
	det.add_child(nom)
	# el arma, en grande y algo inclinada
	var img := _mini_arma(id, Vector2(320, 128))
	_encajar(img, Rect2(dw * 0.40, 70, dw * 0.56, 140))
	img.rotation = deg_to_rad(-10.0)
	if not mia:
		img.modulate = Color(1, 1, 1, 0.55)
	det.add_child(img)
	# lo que es
	var desc := _texto(String(DESCRIPCION.get(id, HISTORIA_TIPO.get(String(Weapons.get_def(id).kind), ""))), 15,
		Color(0.93, 0.92, 1.0), 0, _fd)
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_constant_override("line_spacing", -2)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.position = Vector2(18, 398)
	desc.size = Vector2(dw - 36, 42)
	det.add_child(desc)
	# la propiedad especial (el texto lo dibuja el panel)
	# la historia, en su caja con desplazamiento
	var sc := ScrollContainer.new()
	sc.position = Vector2(18, 580)
	sc.size = Vector2(dw - 36, 62)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_barra_fina(sc)
	det.add_child(sc)
	var his := _texto(String(HISTORIA.get(id, HISTORIA_TIPO.get(String(Weapons.get_def(id).kind), ""))), 14,
		Color(0.86, 0.84, 0.98), 0, _fd)
	his.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	his.custom_minimum_size = Vector2(dw - 50, 0)
	his.mouse_filter = Control.MOUSE_FILTER_PASS
	sc.add_child(his)
	# los botones de abajo, en cajas inclinadas: EQUIPAR, ⇄, $ y el spray
	var y := 652.0
	var bw := dw * 0.40
	var x := 16.0
	_boton(Rect2(x, y, bw, 52), _pintar_btn_equipar, _pulsar_equipar, det)
	x += bw + 8.0
	_boton(Rect2(x, y, 60, 52), _pintar_btn.bind("cambio"), _pulsar_cambio, det)
	x += 68.0
	var cw := dw - 16.0 - x - 68.0
	_boton(Rect2(x, y, cw, 52), _pintar_btn_compra, _pulsar_compra, det)
	x += cw + 8.0
	_boton(Rect2(x, y, 60, 52), _pintar_btn.bind("pintura"), _pulsar_pintura, det)
	# la X magenta (vuelve a la armeria) y la pestaña > (recoge el panel)
	_boton(Rect2(dw - 60, 0, 60, 54), _pintar_x, _cerrar_selector, det)
	_boton(Rect2(dw, 316, 28, 80), _pintar_pliegue, _plegar, det)
	if _pintura_abierta:
		_montar_pintura(det)


func _pintar_detalle(ci: Control) -> void:
	var w := ci.size.x
	var id := _viendo
	var d := Weapons.get_def(id)
	_degradado_v(ci, Rect2(0, 0, w, ALTO), VIOLETA.lightened(0.05), VIOLETA.darkened(0.12))
	ci.draw_line(Vector2(w - 1, 0), Vector2(w - 1, ALTO), Color(1, 1, 1, 0.18), 2.0)
	# la ranura, bajo el nombre
	_txt(ci, String(Weapons.SLOT_NAMES.get(_sel_slot, _sel_slot)), Vector2(24, _base(64, 16, _fn)), 16, LAVANDA_CLARA,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 0, _fn)
	# la rareza, arriba a la derecha (junto a la X)
	var rar := _rareza_arma(id)
	var rt := String(rar["nombre"])
	var rw := _ancho(rt, 13, _fn) + 18.0
	var rr := Rect2(w - 70 - rw, 16, rw, 24)
	ci.draw_colored_polygon(_inclinada(rr, 6.0), rar["color"] as Color)
	_txt(ci, rt, Vector2(rr.position.x, _base(rr.get_center().y, 13, _fn)), 13, TINTA, HORIZONTAL_ALIGNMENT_CENTER, rw, 0, _fn)
	# EL PODER, en grande
	var poder := str(_poder(d))
	_glifo(ci, "rayo", Vector2(38, 124), 20.0, VERDE)
	_txt(ci, poder, Vector2(64, _base(124, 54)), 54, VERDE, HORIZONTAL_ALIGNMENT_LEFT, -1, 7)
	_txt(ci, "PODER", Vector2(66, _base(170, 14, _fn)), 14, Color(0.85, 1.0, 0.8), HORIZONTAL_ALIGNMENT_LEFT, -1, 3, _fn)
	# LA TABLA
	var tabla := Rect2(16, 212, w - 32, 180)
	ci.draw_colored_polygon(_caja(Rect2(tabla.position + Vector2(0, 3), tabla.size), 8.0), Color(0.05, 0.02, 0.25, 0.35))
	ci.draw_colored_polygon(_caja(tabla, 8.0), Color(0.97, 0.97, 1.0))
	var filas := _datos_tabla(id)
	for k in filas.size():
		var fy := tabla.position.y + 8.0 + k * 34.0
		if k % 2 == 1:
			ci.draw_rect(Rect2(tabla.position.x + 6, fy, tabla.size.x - 12, 32), Color(0.86, 0.86, 0.97))
		var cy := fy + 16.0
		_glifo(ci, String(filas[k][0]), Vector2(tabla.position.x + 22, cy), 10.0, VIOLETA, false)
		_txt(ci, String(filas[k][1]), Vector2(tabla.position.x + 42, _base(cy, 16, _fn)), 16, Color8(52, 40, 120),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 0, _fn)
		_txt(ci, String(filas[k][2]), Vector2(tabla.position.x, _base(cy, 19)), 19, TINTA, HORIZONTAL_ALIGNMENT_RIGHT,
			tabla.size.x - 14, 0)
	# EL TIPO
	var tipo := String(Weapons.KIND_NAMES.get(String(d.kind), String(d.kind))).to_upper()
	var tw := _ancho(tipo, 14, _fn) + 26.0
	var chip := Rect2(18, 452, tw, 26)
	ci.draw_colored_polygon(_inclinada(chip, 7.0), VIOLETA_OSCURO)
	_txt(ci, tipo, Vector2(chip.position.x, _base(chip.get_center().y, 14, _fn)), 14, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, tw, 0, _fn)
	# LA PROPIEDAD ESPECIAL
	var pe := _propiedad(id)
	var caja := Rect2(16, 486, w - 32, 64)
	ci.draw_colored_polygon(_caja(caja, 8.0), Color(0.12, 0.08, 0.36, 0.75))
	ci.draw_polyline(_cerrado(_caja(caja, 8.0)), Color(1, 1, 1, 0.16), 1.5, true)
	var ic := Vector2(caja.position.x + 32, caja.get_center().y)
	ci.draw_circle(ic, 22.0, Color(1, 1, 1, 0.12))
	ci.draw_circle(ic, 18.0, AMARILLO)
	_glifo(ci, String(pe[0]), ic, 11.0, Color.WHITE)
	_txt(ci, "PROPIEDAD ESPECIAL", Vector2(caja.position.x + 64, _base(caja.position.y + 18, 12, _fn)), 12, LAVANDA_CLARA,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 0, _fn)
	var linea := "%s  %s" % [String(pe[1]), String(pe[2])]
	var t2 := _cabe(linea, 20, caja.size.x - 76, 12)
	_txt(ci, linea, Vector2(caja.position.x + 64, _base(caja.position.y + 42, t2)), t2, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
	# LA HISTORIA
	_txt(ci, "HISTORIA", Vector2(18, _base(566, 14, _fn)), 14, LAVANDA_CLARA, HORIZONTAL_ALIGNMENT_LEFT, -1, 0, _fn)
	ci.draw_line(Vector2(96, 566), Vector2(w - 18, 566), Color(1, 1, 1, 0.14), 1.5)


static func _cerrado(p: PackedVector2Array) -> PackedVector2Array:
	var c := p.duplicate()
	c.append(p[0])
	return c


func _pintar_btn_equipar(ci: Control) -> void:
	var r := Rect2(Vector2.ZERO, ci.size)
	var mia := Settings.tengo_arma(_viendo)
	var puesta := mia and _arma(_sel_slot) == _viendo
	var forma := _inclinada(r, 10.0)
	var sombra := PackedVector2Array()
	for p in forma:
		sombra.append(p + Vector2(0, 4))
	ci.draw_colored_polygon(sombra, Color(0.03, 0.0, 0.2, 0.4))
	if puesta:
		ci.draw_colored_polygon(forma, Color(0.36, 0.3, 0.62))
		_glifo(ci, "check", Vector2(30, r.size.y * 0.5), 9.0, Color(1, 1, 1, 0.75))
		_txt(ci, "EQUIPADO", Vector2(44, _base(r.size.y * 0.5, 20)), 20, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_LEFT, -1, 0)
	elif mia:
		ci.draw_colored_polygon(forma, AMARILLO)
		ci.draw_colored_polygon(PackedVector2Array([forma[0], forma[1], forma[1] + Vector2(-4, r.size.y * 0.45),
			forma[0] + Vector2(-4, r.size.y * 0.45)]), Color(1, 1, 1, 0.25))
		_txt(ci, "EQUIPAR", Vector2(0, _base(r.size.y * 0.5, 22)), 22, TINTA, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 0)
	else:
		ci.draw_colored_polygon(forma, Color(0.4, 0.38, 0.55))
		_glifo(ci, "candado", Vector2(30, r.size.y * 0.5), 9.0, Color(1, 1, 1, 0.7))
		_txt(ci, "EQUIPAR", Vector2(44, _base(r.size.y * 0.5, 20)), 20, Color(1, 1, 1, 0.55), HORIZONTAL_ALIGNMENT_LEFT, -1, 0)


func _pintar_btn(ci: Control, tipo: String) -> void:
	var r := Rect2(Vector2.ZERO, ci.size)
	var forma := _inclinada(r, 8.0)
	var sombra := PackedVector2Array()
	for p in forma:
		sombra.append(p + Vector2(0, 4))
	ci.draw_colored_polygon(sombra, Color(0.03, 0.0, 0.2, 0.4))
	var apagado := tipo == "pintura" and not Settings.tengo_arma(_viendo)
	ci.draw_colored_polygon(forma, VIOLETA_CLARO.darkened(0.25) if apagado else VIOLETA_CLARO)
	ci.draw_colored_polygon(PackedVector2Array([forma[0], forma[1], forma[1] + Vector2(-3, r.size.y * 0.45),
		forma[0] + Vector2(-3, r.size.y * 0.45)]), Color(1, 1, 1, 0.14))
	_glifo(ci, tipo, r.get_center(), 13.0, Color(1, 1, 1, 0.5) if apagado else Color.WHITE)


func _pintar_btn_compra(ci: Control) -> void:
	var r := Rect2(Vector2.ZERO, ci.size)
	var forma := _inclinada(r, 8.0)
	var sombra := PackedVector2Array()
	for p in forma:
		sombra.append(p + Vector2(0, 4))
	ci.draw_colored_polygon(sombra, Color(0.03, 0.0, 0.2, 0.4))
	if Settings.tengo_arma(_viendo):
		ci.draw_colored_polygon(forma, VIOLETA_CLARO.darkened(0.25))
		_txt(ci, "$", Vector2(0, _base(r.size.y * 0.5, 28)), 28, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 0)
		return
	ci.draw_colored_polygon(forma, AMARILLO)
	var precio := _con_puntos(Weapons.precio(_viendo))
	var tam := _cabe(precio, 21, r.size.x - 46, 12)
	var tw := _ancho(precio, tam) + 26.0
	var x0 := r.size.x * 0.5 - tw * 0.5
	_moneda(ci, Vector2(x0 + 10, r.size.y * 0.5 - 1), 10.0)
	_txt(ci, precio, Vector2(x0 + 26, _base(r.size.y * 0.5, tam)), tam, TINTA, HORIZONTAL_ALIGNMENT_LEFT, -1, 0)


func _pintar_x(ci: Control) -> void:
	var w := ci.size.x
	var h := ci.size.y
	var forma := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(12, h), Vector2(0, h - 12)])
	ci.draw_colored_polygon(forma, MAGENTA)
	_glifo(ci, "x", Vector2(w * 0.5 + 2, h * 0.5), 14.0)


func _pintar_pliegue(ci: Control) -> void:
	var w := ci.size.x
	var h := ci.size.y
	ci.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w - 6, 6), Vector2(w - 6, h - 6), Vector2(0, h)]), VIOLETA)
	ci.draw_polyline(PackedVector2Array([Vector2(0, 0), Vector2(w - 6, 6), Vector2(w - 6, h - 6), Vector2(0, h)]), Color(1, 1, 1, 0.2), 1.5)
	var c := Vector2(w * 0.42, h * 0.5)
	# abierto, ">" (como en la captura); recogido, "<"
	var s := -1.0 if _plegado else 1.0
	ci.draw_polyline(PackedVector2Array([c + Vector2(-4 * s, -9), c + Vector2(5 * s, 0), c + Vector2(-4 * s, 9)]), Color.WHITE, 3.5, true)


func _plegar() -> void:
	Audio.ui("aceptar", -12.0)
	_plegado = not _plegado
	_pintura_abierta = false
	if not is_instance_valid(_detalle):
		return
	var dw := _det_ancho()
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_detalle, "position:x", SEL_IZQ - (dw if _plegado else 0.0), 0.22)
	tw.tween_callback(func(): if not _cerrando: _montar())
	_colocar_aviso()


func _pulsar_equipar() -> void:
	var id := _viendo
	if not Settings.tengo_arma(id):
		Audio.ui("aviso", -10.0)
		_avisar("PRIMERO CÓMPRALA · %s ◈ %s" % [_nombre_arma(id), _con_puntos(Weapons.precio(id))])
		return
	if _arma(_sel_slot) == id:
		Audio.ui("aceptar", -12.0)
		_avisar("YA LA LLEVAS EN %s" % String(Weapons.SLOT_NAMES.get(_sel_slot, _sel_slot)))
		return
	_equipar(_sel_slot, id)
	_montar()
	_poner_arma()


## ⇄: la misma arma, en otra ranura (PRIMARIA -> SECUNDARIA -> PESADA)
func _pulsar_cambio() -> void:
	var i := Weapons.SLOTS.find(_sel_slot)
	_sel_slot = String(Weapons.SLOTS[(i + 1) % Weapons.SLOTS.size()])
	_slot = _sel_slot
	Audio.ui("aceptar", -10.0)
	_avisar("PONER EN %s" % String(Weapons.SLOT_NAMES.get(_sel_slot, _sel_slot)))
	_montar()


func _pulsar_compra() -> void:
	if Settings.tengo_arma(_viendo):
		Audio.ui("aceptar", -12.0)
		_avisar("%s · YA ES TUYA" % _nombre_arma(_viendo))
		return
	_abrir_tienda("armas")


func _abrir_tienda(seccion: String) -> void:
	if not is_instance_valid(lobby) or not lobby.has_method("_abrir_tienda"):
		return
	Audio.ui("aceptar", -8.0)
	var t = lobby._abrir_tienda(seccion)
	if t != null and t.has_signal("cerrada") and not t.is_connected("cerrada", _al_volver):
		t.connect("cerrada", _al_volver)


func _pulsar_pintura() -> void:
	if not Settings.tengo_arma(_viendo):
		Audio.ui("aviso", -10.0)
		_avisar("PRIMERO CÓMPRALA: luego la pintas")
		return
	Audio.ui("aceptar", -10.0)
	_pintura_abierta = not _pintura_abierta
	_scroll_pinturas = 0
	_montar()


# ------------------------------------------------------------------ la pintura (o el modelo del mazo) de la que miras
func _montar_pintura(det: Control) -> void:
	var dw := det.size.x
	var caja := Control.new()
	caja.mouse_filter = Control.MOUSE_FILTER_STOP
	caja.position = Vector2(12, 212)
	caja.size = Vector2(dw - 24, 432)
	det.add_child(caja)
	_dibujo(Vector2.ZERO, caja.size, _pintar_caja_pintura, caja)
	_boton(Rect2(caja.size.x - 46, 6, 40, 38), func(ci: Control): _glifo(ci, "x", ci.size * 0.5, 10.0),
		func(): Audio.ui("atras", -10.0); _pintura_abierta = false; _montar(), caja)
	var mid := Weapons.modelo_de(_viendo)
	_pinturas_sc = ScrollContainer.new()
	_pinturas_sc.position = Vector2(10, 52)
	_pinturas_sc.size = Vector2(caja.size.x - 20, caja.size.y - 60)
	_pinturas_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_barra_fina(_pinturas_sc)
	caja.add_child(_pinturas_sc)
	var rej := GridContainer.new()
	rej.columns = maxi(3, int((_pinturas_sc.size.x + 8) / 94.0))
	rej.add_theme_constant_override("h_separation", 8)
	rej.add_theme_constant_override("v_separation", 8)
	_pinturas_sc.add_child(rej)
	if _viendo == "sledge":
		# EL MAZO NO SE PINTA: se cambia de modelo (las skins de mazo que tienes)
		rej.add_child(_opcion("", "DE HIERRO", Settings.skin_mazo == "", func(): _poner_mazo(""); _montar(); _poner_arma(),
			_mini_arma_mazo("")))
		for sid in Weapons.SKINS_ARMA.keys():
			if Settings.tengo(String(sid)):
				var s := String(sid)
				rej.add_child(_opcion(s, TiendaAjustes.nombre(s, String(Weapons.NOMBRE_SKIN.get(s, s))), Settings.skin_mazo == s,
					func(): _poner_mazo(s); _montar(); _poner_arma(), _mini_arma_mazo(s)))
		rej.add_child(_opcion("+", "MÁS MAZOS", false, func(): _abrir_tienda("mazos"), null))
	elif WeaponModelScript.hay_modelo(mid):
		var puesta := SkinsArmas.equipada(mid)
		rej.add_child(_opcion("", "SIN PINTURA", puesta == "", func(): _poner_pintura(mid, ""); _montar(); _poner_arma(), null))
		for s in SkinsArmas.catalogo():
			var sid := String(s["id"])
			if SkinsArmas.mia(sid):
				rej.add_child(_opcion(sid, SkinsArmas.nombre_de(sid), puesta == sid,
					func(): _poner_pintura(mid, sid); _montar(); _poner_arma(), null))
		rej.add_child(_opcion("+", "MÁS PINTURAS", false, func(): _abrir_tienda("pinturas"), null))
	else:
		var l := _texto("Esta arma no se pinta.", 17, Color.WHITE, 4, _fd)
		rej.add_child(l)
	var sc := _scroll_pinturas
	(func(): if is_instance_valid(_pinturas_sc): _pinturas_sc.scroll_vertical = sc).call_deferred()


func _mini_arma_mazo(sid: String) -> Control:
	if not is_instance_valid(lobby):
		return null
	return lobby._mini_arma_3d(sid if sid != "" else "sledge", Vector2(120, 50), "sledge")


func _pintar_caja_pintura(ci: Control) -> void:
	var r := Rect2(Vector2.ZERO, ci.size)
	ci.draw_colored_polygon(_caja(Rect2(r.position + Vector2(0, 5), r.size), 10.0), Color(0.03, 0.0, 0.2, 0.45))
	ci.draw_colored_polygon(_caja(r, 10.0), VIOLETA_OSCURO)
	ci.draw_polyline(_cerrado(_caja(r, 10.0)), Color(1, 1, 1, 0.22), 2.0, true)
	var titulo := "MODELO DEL MAZO" if _viendo == "sledge" else "PINTURA"
	_glifo(ci, "pintura", Vector2(26, 26), 12.0)
	_txt(ci, titulo, Vector2(46, _base(26, 22)), 22, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 5)
	var sub := _nombre_arma(_viendo)
	_txt(ci, sub, Vector2(52 + _ancho(titulo, 22), _base(27, 14, _fn)), 14, LAVANDA_CLARA, HORIZONTAL_ALIGNMENT_LEFT, -1, 0, _fn)


## Una opcion del cajon de pintura: la muestra (la textura del camuflaje, o el mazo), el nombre y el visto si es la puesta
func _opcion(sid: String, nombre: String, puesta: bool, al_pulsar: Callable, imagen: Control) -> Control:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(86, 112)
	b.set_meta("sin_sonido", true)
	for e in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(e, StyleBoxEmpty.new())
	var fondo := _Dibujo.new()
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fondo.pintar = _pintar_opcion.bind(sid, nombre, puesta, imagen != null)
	b.add_child(fondo)
	if imagen != null:
		_encajar(imagen, Rect2(6, 12, 74, 56))
		b.add_child(imagen)
		var encima := _Dibujo.new()
		encima.set_anchors_preset(Control.PRESET_FULL_RECT)
		encima.pintar = func(ci: Control): _pintar_visto(ci, puesta)
		b.add_child(encima)
	b.pressed.connect(al_pulsar)
	return b


func _pintar_opcion(ci: Control, sid: String, nombre: String, puesta: bool, con_imagen: bool) -> void:
	var m := Rect2(6, 4, 74, 74)
	var rar_col := Color(0.8, 0.8, 0.9)
	if sid != "" and sid != "+" and not con_imagen:
		rar_col = SkinsArmas.rareza_de(sid)["color"] as Color
	ci.draw_rect(Rect2(m.position + Vector2(0, 3), m.size), Color(0, 0, 0.15, 0.4))
	if sid == "+":
		ci.draw_rect(m, Color(1, 1, 1, 0.08))
		ci.draw_rect(m, Color(1, 1, 1, 0.3), false, 2.0)
		var c := m.get_center()
		ci.draw_line(c + Vector2(-14, 0), c + Vector2(14, 0), Color.WHITE, 5.0)
		ci.draw_line(c + Vector2(0, -14), c + Vector2(0, 14), Color.WHITE, 5.0)
	elif con_imagen:
		_degradado_v(ci, m, CASILLA_A, CASILLA_B)
		ci.draw_rect(m, Color(1, 1, 1, 0.7), false, 2.0)
	elif sid == "":
		ci.draw_rect(m, Color(0.3, 0.3, 0.38))
		ci.draw_line(m.position + Vector2(10, m.size.y - 10), m.end - Vector2(10, m.size.y - 10), Color(1, 1, 1, 0.8), 4.0)
		ci.draw_rect(m, Color(1, 1, 1, 0.5), false, 2.0)
	else:
		var s := SkinsArmas.por_id(sid)
		var capa: Dictionary = (s.get("capas", {}) as Dictionary).get("cuerpo", {})
		var tex: Texture2D = SkinsArmas._tex(String(capa.get("patron", "")))
		if tex != null:
			ci.draw_texture_rect(tex, m, false, capa.get("color", Color.WHITE) as Color)
		else:
			ci.draw_rect(m, capa.get("color", Color.GRAY) as Color)
		ci.draw_rect(m, rar_col, false, 3.0)
	if puesta and not con_imagen:
		_pintar_visto(ci, true)
	var tam := _cabe(nombre, 12, 84, 8, _fn)
	var lin := nombre
	_txt(ci, lin, Vector2(0, _base(92, tam, _fn)), tam, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, ci.size.x, 3, _fn)


func _pintar_visto(ci: Control, puesta: bool) -> void:
	if not puesta:
		return
	var m := Rect2(6, 4, 74, 74)
	ci.draw_rect(m.grow(1.5), AMARILLO, false, 3.5)
	ci.draw_circle(Vector2(m.end.x - 6, m.position.y + 6), 11.0, TINTA)
	ci.draw_circle(Vector2(m.end.x - 6, m.position.y + 6), 9.0, AMARILLO)
	_glifo(ci, "check", Vector2(m.end.x - 6, m.position.y + 6), 5.5, TINTA, false)


# ------------------------------------------------------------------ las cinco ranuras, abajo a la derecha (con el selector)
func _montar_fila(padre: Control) -> void:
	var ancho := 0.0
	for a in FILA_ANCHOS:
		ancho += float(a)
	ancho += 6.0 * (FILA_ANCHOS.size() - 1)
	var x := _w - 12.0 - ancho
	var y := ALTO - 12.0 - FILA_ALTO
	for i in RANURAS.size():
		var aw := float(FILA_ANCHOS[i])
		var r := Rect2(x, y, aw, FILA_ALTO)
		var b := _boton(r, _pintar_ranura.bind(i, true), _tocar_fila.bind(i), padre)
		var img := _miniatura(String(RANURAS[i]["id"]), Vector2(110, 56))
		_encajar(img, Rect2(6, 8, aw - 12, FILA_ALTO - 32))
		b.add_child(img)
		_dibujo(Vector2.ZERO, r.size, _pintar_ranura_encima.bind(i, true), b)
		x += aw + 6.0


func _tocar_fila(i: int) -> void:
	var slot := String(RANURAS[i]["id"])
	if not (slot in Weapons.SLOTS):
		_tocar_ranura(i)
		return
	if slot == _sel_slot:
		return
	Audio.ui("aceptar", -10.0)
	_sel_slot = slot
	_slot = slot
	_viendo = _arma(slot)
	_marcar_visto(_viendo)
	_pintura_abierta = false
	_scroll_rejilla = 0
	_montar()
	_poner_arma()


# ================================================================== --armeriafoto=<carpeta>
## Las fotos de la pantalla (las pide lobby.gd con --armeriafoto): la armeria, el selector, una equipada, una que no tienes,
## la pintura, el panel recogido, un cambio de equipo y los PRIMEROS PLANOS del muñeco con cada clase de arma (de frente,
## de tres cuartos y de perfil: los brazos tienen que seguir pegados a los hombros). Sin cuenta y EN MEMORIA: settings.cfg y
## cuenta.cfg se copian antes y se devuelven al acabar (equipar guarda).
func fotos(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	solo_memoria = true
	# AFINAR LA GUARDIA: ARMERIA_POSES="rifle:x,y,z,rx,ry,rz;pistol:..." saca solo los primeros planos de esas poses (no guarda)
	if OS.get_environment("ARMERIA_POSES") != "":
		await _fotos_poses(dir, OS.get_environment("ARMERIA_POSES"))
		get_tree().quit()
		return
	# NADA SE ESCRIBE (solo_memoria). Por si algo del proceso guardara igual (la cuenta, el lobby), se recuerda como
	# estaban los dos ficheros y, si al acabar han cambiado, se dejan como estaban. No se copian a disco: una copia
	# en disco la podia devolver OTRA prueba lanzada a la vez y dejar dentro lo de esta.
	var antes := {}
	for ruta in [Settings.PATH, Cuenta.ARCHIVO]:
		antes[ruta] = FileAccess.get_file_as_bytes(ruta) if FileAccess.file_exists(ruta) else PackedByteArray()
	Cuenta.token = ""
	Cuenta.perfil = {}
	var foto := func(nombre: String) -> void:
		await RenderingServer.frame_post_draw
		var ruta := dir.path_join(nombre)
		get_viewport().get_texture().get_image().save_png(ruta)
		print("[armeriafoto] %s" % ruta)
	# lo de prueba, en memoria: un par de armas, pinturas y un mazo
	for x in ["carabina_556", "escopeta_auto", "pdw_57", "sk_bosque", "sk_oxido", "sk_arena", "mazo_obra"]:
		if not (x in Settings.armas_compradas):
			Settings.armas_compradas.append(x)
	Settings.skins_arma["carabina_556"] = "sk_oxido"
	Settings.loadout["primary"] = "carabina_556"
	# seis cartas equipadas (dos huecos): una con copias para mejorar y otra sin mirar
	Settings.cartas = {"dano": {"n": 3, "c": 1}, "vida": {"n": 2, "c": 5}, "velocidad": {"n": 1, "c": 0},
		"destruccion": {"n": 4, "c": 2}, "regeneracion": {"n": 1, "c": 0}, "explosion": {"n": 2, "c": 1}}
	Settings.cartas_equipadas = ["dano", "vida", "velocidad", "destruccion", "regeneracion", "explosion"]
	Settings.cartas_vistas = ["dano", "vida", "velocidad", "destruccion", "regeneracion"]
	_iniciar_presets()
	(Settings.presets_equipo["vistas"] as Array).erase("pdw_57")    # para ver la cinta de NUEVO
	_montar()
	_arma_puesta = ""
	_poner_arma(false)
	await get_tree().create_timer(3.5).timeout
	await foto.call("armeria_a.png")
	# con toques DE VERDAD (por el Input, como un dedo): la ranura primaria abre el selector
	await _tocar_en(_rect_ranura(0).get_center() + Vector2(_px(), 0))
	print("[armeriafoto] toque en la ranura 1: %s" % ("abre el selector" if _sel_slot == "primary" else "NO RESPONDE"))
	if _sel_slot != "primary":
		_abrir_selector("primary")
	await get_tree().create_timer(1.8).timeout
	await foto.call("armeria_b_selector.png")
	_ver_arma("escopeta_bomba")
	await get_tree().create_timer(1.2).timeout
	await foto.call("armeria_c_detalle.png")
	_pulsar_equipar()
	await get_tree().create_timer(1.0).timeout
	await foto.call("armeria_d_equipada.png")
	_ver_arma("rifle_precision")
	await get_tree().create_timer(1.2).timeout
	await foto.call("armeria_e_sin_comprar.png")
	_ver_arma("carabina_556")
	await get_tree().create_timer(0.8).timeout
	_pulsar_pintura()
	await get_tree().create_timer(0.8).timeout
	await foto.call("armeria_f_pintura.png")
	_poner_pintura("carabina_556", "sk_bosque")
	_montar()
	_poner_arma()
	await get_tree().create_timer(1.2).timeout
	await foto.call("armeria_g_pintada.png")
	_pintura_abierta = false
	_plegar()
	await get_tree().create_timer(1.0).timeout
	await foto.call("armeria_h_plegado.png")
	_plegar()
	await get_tree().create_timer(0.6).timeout
	# la X magenta, tambien con el dedo
	await _tocar_en(Vector2(SEL_IZQ + _det_ancho() - 30.0, 27.0))
	print("[armeriafoto] toque en la X: %s" % ("vuelve a la armeria" if _sel_slot == "" else "NO RESPONDE"))
	if _sel_slot != "":
		_cerrar_selector()
	await get_tree().create_timer(0.8).timeout
	_cambiar_preset(1)
	await get_tree().create_timer(1.0).timeout
	await foto.call("armeria_i_equipo2.png")
	_cambiar_preset(0)
	await get_tree().create_timer(0.6).timeout
	# ESTILO: el personaje en sus skins, encima; y al cerrarlo, de vuelta aqui
	_ir_personaje(true)
	await get_tree().create_timer(1.6).timeout
	await foto.call("armeria_j_estilo.png")
	var pj = lobby.get("_capa_personaje") if is_instance_valid(lobby) else null
	if pj != null and is_instance_valid(pj) and pj.has_method("_cerrar"):
		pj._cerrar()
	await get_tree().create_timer(1.0).timeout
	await foto.call("armeria_k_vuelta.png")
	# LOS PRIMEROS PLANOS: el muñeco con cada clase de arma, la camara al pecho
	# con la skin puesta todas; con el soldado de serie y el Heraldo Forjado (hombros propios) el fusil y la pistola
	var skins := [Settings.avatar_skin]
	for a_s in OS.get_cmdline_user_args():   # --vistasskin=N: esa skin en vez de la puesta (y con todas las armas)
		if String(a_s).begins_with("--vistasskin="):
			skins = [int(String(a_s).substr(13))]
			Settings.avatar_skin = skins[0]
	for extra in ([] if skins[0] != Settings.avatar_skin or Array(OS.get_cmdline_user_args()).any(func(x): return String(x).begins_with("--vistasskin=")) else [0, 2]):
		if not (extra in skins) and extra < LobbyScript.SKINS.size():
			skins.append(extra)
	var skin_puesta := int(skins[0])
	var accesorios: Array = Settings.accesorios.duplicate()
	for sk in skins:
		Settings.avatar_skin = int(sk)
		if int(sk) != skin_puesta:
			Settings.accesorios = []
		_poner_avatar()
		await get_tree().create_timer(1.2).timeout
		var armas := ["carabina_556", "smg_9mm", "escopeta_bomba", "pistola_9", "bazooka_rpg", "sledge", "escudo_pistola"] if int(sk) == skin_puesta 			else ["carabina_556", "pistola_9"]
		for id in armas:
			Settings.loadout["primary"] = id
			_slot = "primary"
			_poner_arma(false)
			for g in [["menu", _giro_objetivo], ["frente", PI], ["tres_cuartos_otro", PI + 0.6], ["perfil", PI - 1.45], ["espalda", 0.0], ["espalda_lado", 0.7]]:
				_avatar.rotation.y = float(g[1])
				_reposo_t = -1000.0
				_cam.fov = 15.0
				var dist := _cam.position.z
				_cam.position = Vector3(0.0, 1.22, dist)
				for _q in 20:
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var ruta := dir.path_join("cerca_%d_%s_%s.png" % [int(sk), id, String(g[0])])
				_vp.get_texture().get_image().save_png(ruta)
				print("[armeriafoto] %s" % ruta)
			_poner_camara()
	Settings.avatar_skin = skin_puesta
	Settings.accesorios = accesorios
	for ruta in antes:
		var ahora := FileAccess.get_file_as_bytes(ruta) if FileAccess.file_exists(ruta) else PackedByteArray()
		if ahora != antes[ruta] and (antes[ruta] as PackedByteArray).size() > 0:
			var fa := FileAccess.open(ruta, FileAccess.WRITE)
			if fa != null:
				fa.store_buffer(antes[ruta])
				fa.close()
			print("[armeriafoto] %s habia cambiado: devuelto como estaba" % ruta)
	print("[armeriafoto] hecho (sin tocar los ajustes)")
	get_tree().quit()


## Un toque en un punto del lienzo (720 de alto), por el Input: pasa por los mismos botones que un dedo
func _tocar_en(p: Vector2) -> void:
	var g := p * _k
	var m := InputEventMouseMotion.new()
	m.position = g
	m.global_position = g
	Input.parse_input_event(m)
	await get_tree().process_frame
	for pulsado in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pulsado
		e.position = g
		e.global_position = g
		Input.parse_input_event(e)
		await get_tree().process_frame
	await get_tree().process_frame


func _fotos_poses(dir: String, lista: String) -> void:
	await get_tree().create_timer(2.5).timeout
	var armas := {"rifle": "carabina_556", "smg": "smg_9mm", "compacta": "smg_compacta", "shotgun": "escopeta_bomba", "pistol": "pistola_9"}
	var n := 0
	for e in lista.split(";"):
		var partes := String(e).split(":")
		var tipo := String(partes[0])
		var v := String(partes[1]).split(",")
		var pose := [Vector3(float(v[0]), float(v[1]), float(v[2])), Vector3(float(v[3]), float(v[4]), float(v[5]))]
		var clave := "rifle" if tipo in ["smg", "compacta"] else tipo
		var g: Dictionary = GUARDIA.duplicate()
		g[clave] = pose
		_avatar.pose_menu = g
		Settings.loadout["primary"] = String(armas.get(tipo, "carabina_556"))
		_slot = "primary"
		_arma_puesta = ""
		_poner_arma(false)
		for giro in [PI - 0.4, PI, PI + 0.5, PI - 1.45]:
			_avatar.rotation.y = float(giro)
			_reposo_t = -1000.0
			_cam.fov = 15.0
			_cam.position = Vector3(0.0, 1.22, _cam.position.z)
			for _q in 16:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var ruta := dir.path_join("pose_%02d_%s_%d.png" % [n, tipo, int(rad_to_deg(float(giro)))])
			_vp.get_texture().get_image().save_png(ruta)
		_poner_camara()
		n += 1
	print("[armeriafoto] %d poses" % n)


# ================================================================== el lienzo de todo
## Un Control que se pinta con una funcion (`pintar(self)`); `animado` lo repinta cada fotograma
class _Dibujo extends Control:
	var pintar: Callable
	var animado := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_dt: float) -> void:
		if animado:
			queue_redraw()

	func _draw() -> void:
		if pintar.is_valid():
			pintar.call(self)
