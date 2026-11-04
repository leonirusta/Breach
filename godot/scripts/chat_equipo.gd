extends Control
## EL CHAT Y LA VOZ DEL EQUIPO EN EL LOBBY (2026-10-15, pedido: "en el lobby, si tengo un equipo, que aparezca la opcion
## de chatear y el microfono para hablar con el equipo"). Lo crea lobby_grupo.gd en su capa (lienzo de 720 de alto) y
## sale solo con equipo, encima de la tira EQUIPO n/max.
##   CHAT  una caja para escribir (con el dedo: campo_tactil); va por el servidor (Grupo.mandar_chat -> /grupo/chat) y
##         llega con el sondeo del equipo (cada segundo con equipo). Los mensajes salen encima de los botones.
##   MIC   TwoVoIP como en la partida (Opus + RNNoise, chat_voz.gd), pero en el lobby no hay conexion entre vosotros: los
##         paquetes se juntan y van al servidor cada VOZ_CADA s (/grupo/voz), que se lleva a la vez los de los demas.
##         Por eso tiene ~1 s de retraso (en partida, ~0,25). Las voces no van en 3D: suenan como una llamada.

const VOZ_CADA := 0.4
const VIDA := 12.0
const ORO := Color(1.0, 0.82, 0.22)
const VERDE := Color(0.36, 0.9, 0.45)
const ChatVoz := preload("res://scripts/chat_voz.gd")

var _b_chat: Button
var _b_mic: Button
var _log: VBoxContainer
var _caja: PanelContainer = null
var _campo: LineEdit = null
var mic_on := false
var _mic: Node = null
var _mic_boton: Button = null
var _salientes: Array = []          ## paquetes de Opus (base64) por mandar
var _http: HTTPRequest
var _ocupado := false
var _t := 0.0
var _voces: Dictionary = {}         ## k (clave del miembro) -> AudioStreamPlayer
var _habla: Dictionary = {}         ## nombre -> segundos
var _habla_lbl: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(420, 260)
	_b_chat = _boton("chat")
	_b_chat.position = Vector2(0, size.y - 52)
	_b_chat.pressed.connect(_abrir_caja)
	_b_mic = _boton("mic")
	_b_mic.position = Vector2(62, size.y - 52)
	if Settings.is_touch():          # en el movil, mantener para hablar (como en la partida)
		_b_mic.button_down.connect(func(): poner_mic(true))
		_b_mic.button_up.connect(func():
			await get_tree().create_timer(0.35).timeout
			if not _b_mic.button_pressed:
				poner_mic(false))
	else:
		_b_mic.pressed.connect(func(): poner_mic(not mic_on))
	_habla_lbl = Label.new()
	_habla_lbl.position = Vector2(126, size.y - 44)
	_habla_lbl.add_theme_font_size_override("font_size", 15)
	_habla_lbl.add_theme_color_override("font_color", VERDE)
	_habla_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_habla_lbl.add_theme_constant_override("outline_size", 4)
	add_child(_habla_lbl)
	_log = VBoxContainer.new()
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.alignment = BoxContainer.ALIGNMENT_END
	_log.position = Vector2(0, 0)
	_log.size = Vector2(size.x, size.y - 60)
	add_child(_log)
	_http = HTTPRequest.new()
	_http.timeout = 6.0
	add_child(_http)
	_http.request_completed.connect(_al_voz)
	if not Grupo.chat_llega.is_connected(_on_chat):
		Grupo.chat_llega.connect(_on_chat)


func _boton(tipo: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.size = Vector2(56, 50)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.06, 0.15, 0.78)
	sb.border_color = Color(1, 1, 1, 0.3)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	for st in ["normal", "hover", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	var sp := sb.duplicate()
	sp.border_color = ORO
	b.add_theme_stylebox_override("pressed", sp)
	var ic = ChatVoz._Icono.new()
	ic.tipo = tipo
	ic.duenyo = self
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(ic)
	add_child(b)
	return b


func _process(dt: float) -> void:
	for l in _log.get_children():
		var v: float = float(l.get_meta("vida", 0.0)) - dt
		l.set_meta("vida", v)
		l.modulate.a = clampf(v, 0.0, 1.0) if not (_caja and is_instance_valid(_caja)) else 1.0
	for n in _habla.keys():
		_habla[n] = float(_habla[n]) - dt
		if float(_habla[n]) <= 0.0:
			_habla.erase(n)
	_habla_lbl.text = "  ".join(_habla.keys().map(func(n): return "🎤 " + String(n)))
	# LA VOZ: cada VOZ_CADA s se mandan los mios y se recogen los de los demas (aunque yo no hable)
	_t -= dt
	if _t <= 0.0 and not _ocupado and Grupo.en_grupo() and Cuenta.conectado() and ChatVoz.voz_disponible():
		_t = VOZ_CADA
		var cab := PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + Cuenta.token])
		var p := _salientes
		_salientes = []
		if _http.request(Cuenta.url + "/grupo/voz", cab, HTTPClient.METHOD_POST, JSON.stringify({"p": p})) == OK:
			_ocupado = true


# ------------------------------------------------------------------------------------------------ chat
func _abrir_caja() -> void:
	if _caja and is_instance_valid(_caja):
		_cerrar_caja()
		return
	_caja = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.06, 0.15, 0.94)
	sb.border_color = ORO
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	_caja.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	_caja.add_child(h)
	_campo = LineEdit.new()
	_campo.custom_minimum_size = Vector2(250, 44)
	_campo.max_length = 120
	_campo.placeholder_text = "Escribe a tu equipo..."
	_campo.add_theme_font_size_override("font_size", 20)
	_campo.text_submitted.connect(func(_t2): _enviar())
	h.add_child(_campo)
	preload("res://scripts/campo_tactil.gd").attach(_campo)
	var b := Button.new()
	b.text = "ENVIAR"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(100, 44)
	b.pressed.connect(_enviar)
	h.add_child(b)
	add_child(_caja)
	_caja.position = Vector2(0, size.y - 52 - 62)
	_campo.grab_focus()
	for l in _log.get_children():
		l.modulate.a = 1.0


func _cerrar_caja() -> void:
	if _caja and is_instance_valid(_caja):
		_caja.queue_free()
	_caja = null


func _enviar() -> void:
	if _campo and is_instance_valid(_campo):
		Grupo.mandar_chat(_campo.text)
	_cerrar_caja()


func _on_chat(nombre: String, txt: String) -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.custom_minimum_size = Vector2(size.x, 0)
	l.add_theme_font_size_override("normal_font_size", 17)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.text = "[color=#%s]%s:[/color] %s" % [ORO.to_html(false), ChatVoz._limpio(nombre), ChatVoz._limpio(txt)]
	l.set_meta("vida", VIDA)
	_log.add_child(l)
	while _log.get_child_count() > 5:
		var v := _log.get_child(0)
		_log.remove_child(v)
		v.queue_free()
	Audio.ui("click", -10.0)


# ------------------------------------------------------------------------------------------------ voz
func poner_mic(on: bool) -> void:
	if not ChatVoz.voz_disponible():
		return
	if on and OS.get_name() == "Android" and not ("android.permission.RECORD_AUDIO" in OS.get_granted_permissions()):
		OS.request_permission("android.permission.RECORD_AUDIO")
		return
	mic_on = on
	if on and _mic == null:
		_mic = ChatVoz.MicScript.new()
		add_child(_mic)
		_mic_boton = Button.new()
		_mic_boton.toggle_mode = true
		_mic.init_voip_mic(true, _mic_boton, null, null, null, null)
		_mic.set_opus_values(48000, 40, 1, 24000, 5, true, ClassDB.class_get_integer_constant("TwovoipOpusEncoder", "DENOISER_DISABLED"), ClassDB.class_get_integer_constant("TwovoipOpusEncoder", "AGC_DISABLED"))
		_mic.set_gain(ChatVoz.GANANCIA_MIC)       # (sin AGC: era lo que daba el lag, ver chat_voz.gd)
		_mic.set_vox_threshhold(ChatVoz.VOX_UMBRAL)
		_mic.transmit_audio_packet.connect(func(pq: PackedByteArray):
			_salientes.append(Marshalls.raw_to_base64(pq))
			if pq.size() > 0 and pq[0] != 123:
				_habla["Tú"] = 0.3)
	if _mic_boton:
		_mic_boton.button_pressed = on
	if _mic:
		_mic.set_process(on)
		if not on and _mic.get("currentlytalking"):
			_mic.processtalkstreamends(false)
	for c in _b_mic.get_children():
		(c as CanvasItem).queue_redraw()


func _al_voz(_r: int, codigo: int, _c: PackedStringArray, cuerpo: PackedByteArray) -> void:
	_ocupado = false
	if codigo != 200:
		return
	var j = JSON.parse_string(cuerpo.get_string_from_utf8())
	if not (j is Dictionary):
		return
	for e in j.get("voz", []):
		if not (e is Dictionary):
			continue
		var k := String(e.get("k", ""))
		var sp = _altavoz(k)
		var habla := false
		for b64 in e.get("p", []):
			var pq := Marshalls.base64_to_raw(String(b64))
			if pq.size() >= 3:
				sp.receive_audio_packet(pq)
				habla = habla or pq[0] != 123
		if habla:
			_habla[String(e.get("nombre", ""))] = 0.8


func _altavoz(k: String) -> Node:
	var a = _voces.get(k, null)
	if a != null and is_instance_valid(a):
		return a.get_node("TwoVoipSpeaker")
	a = AudioStreamPlayer.new()
	a.volume_db = 9.0         # mas fuerte (pedido 2026-10-15)
	add_child(a)
	var sp = ChatVoz.SpeakerScript.new()
	sp.name = "TwoVoipSpeaker"
	sp.audio_buffer_lag_time_target = 0.9          # llegan de medio segundo en medio segundo: algo mas de colchon
	sp.audio_buffer_lag_time_target_tolerance = 0.4
	a.add_child(sp)
	_voces[k] = a
	return sp
