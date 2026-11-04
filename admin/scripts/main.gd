extends Control
## BREACH ADMIN (2026-09-28): el panel de administracion de las cuentas, APK aparte del juego.
##
## Pantallas: ENTRAR (servidor y clave del panel) -> INICIO (JUGADORES, EN VIVO, RESUMEN, REGALOS, TIENDA, JUEGO, REPORTES,
## VERSION, MENSAJES) -> FICHA de una cuenta (o un REPORTE o un MENSAJE entero).
## Todo lo que cambia una cuenta lo hace el SERVIDOR (servidor/admin.js): aqui solo se pide y se enseña.
##
## Esta escena lleva lo comun: la pila de pantallas, las ventanas (Dialogo), los avisos de abajo, la sesion guardada
## y el DESPLAZAMIENTO CON EL DEDO de las listas (con inercia): los ScrollContainer del grupo "desliza" no se mueven
## solos al arrastrar (scroll_deadzone enorme) y lo hace `_input`, que ademas marca `Tema.arrastrando` para que
## soltar el dedo encima de un boton despues de arrastrar no lo dispare.
##
## Pruebas: `--url=<servidor> --clave=<clave> --fotos=<carpeta>` entra solo y fotografia cada pantalla (JUEGO al final).
## `--juegoprueba --fotos=<carpeta>`: sin servidor, solo la pestaña JUEGO con las tablas de fabrica de verdad
## (juego_prueba.gd), editando y guardando en memoria. `--juegotest` (con --url y --clave): cambia y guarda cada seccion
## de JUEGO, comprueba con GET /admin/juego que quedo, y la vuelve a DE FABRICA (solo contra un servidor de pruebas).
## REPORTES: sin servidor salen con `--juegoprueba` (una docena inventados); `--solo=reportes` fotografia solo esa
## pestaña (con --juegoprueba ademas marca, descarta y bloquea en memoria). `--reportestest` (con --url y --clave, contra
## un servidor de pruebas con reportes): lista, filtra, abre uno, lo marca revisado, lo comprueba con GET y lo devuelve.
## MENSAJES (HABLAR CON NOSOTROS): `--solo=mensajes` fotografia la lista, uno abierto y (con --juegoprueba, en memoria)
## marcado hecho.

const ARCHIVO := "user://admin.cfg"
const SERVIDOR := "https://breach-cuentas-36080028239.us-central1.run.app"

var api: Api
var _vistas: Control
var _pila: Array = []
var _capa_dlg: Control
var _capa_aviso: MarginContainer
var _pila_aviso: VBoxContainer
var _aviso: PanelContainer = null
var _args := {}

# el dedo sobre una lista
var _apretado := false
var _p0 := Vector2.ZERO
var _sc: ScrollContainer = null
var _sch: ScrollContainer = null     ## la barra de abajo (se arrastra de lado)
var _horizontal := false            ## este arrastre es de lado
var _vel := 0.0
var _t_mov := 0


func _ready() -> void:
	theme = Tema.crear_tema()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			_args[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
		elif a.begins_with("--"):
			_args[a.substr(2)] = true
	var fondo := ColorRect.new()
	fondo.color = Tema.FONDO
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fondo)
	_vistas = Control.new()
	_vistas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vistas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vistas)
	_capa_dlg = Control.new()
	_capa_dlg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_capa_dlg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_capa_dlg)
	# los avisos: abajo, a lo ancho, encima de la barra de pestañas (y del teclado si esta abierto)
	_capa_aviso = Tema.margen(12, 12, 12, 84)
	_capa_aviso.set_anchors_preset(Control.PRESET_FULL_RECT)
	_capa_aviso.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_capa_aviso)
	_pila_aviso = Tema.vbox(8)
	_pila_aviso.alignment = BoxContainer.ALIGNMENT_END
	_pila_aviso.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_capa_aviso.add_child(_pila_aviso)
	api = Api.new()
	add_child(api)
	api.sesion_caducada.connect(_sesion_caducada)
	if _args.has("juegoprueba"):
		# sin servidor: no se lee ni se guarda la sesion
		api.falso = JuegoPrueba.new()
		api.url = "sin servidor · tablas de fábrica"
		api.token = "prueba"
		ir_a(VistaInicio.new(self), true)
		if _args.has("fotos"):
			_fotos.call_deferred()
		return
	# la sesion guardada (el token del panel dura 12 h)
	var cfg := ConfigFile.new()
	cfg.load(ARCHIVO)
	api.url = String(_args.get("url", cfg.get_value("panel", "url", SERVIDOR)))
	# una direccion vieja guardada (de antes del respaldo) se cambia por la de Google: asi entra en el cambio automatico
	# (y una de una prueba local: el panel va siempre a Google y su respaldo salvo con --url)
	if not _args.has("url") and api.url != Api.SERVIDOR_RESPALDO:
		api.url = Api.SERVIDOR_RESPALDO if Api.SOLO_PC else Api.SERVIDOR_GOOGLE
	var vence := float(cfg.get_value("panel", "vence", 0.0))
	if not _args.has("clave") and Time.get_unix_time_from_system() < vence:
		api.token = String(cfg.get_value("panel", "token", ""))
	if _args.has("tokenprueba"):
		api.token = String(_args["tokenprueba"])       # (pruebas contra un servidor LOCAL)
	_aviso_parche()
	if api.token != "":
		ir_a(VistaInicio.new(self), true)
	else:
		ir_a(VistaEntrar.new(self), true)
	if _args.has("probarrespaldo"):    # --probarrespaldo: una peticion y a quien acabo yendo
		_probar_respaldo.call_deferred()
	if _args.has("juegotest"):
		_probar_juego.call_deferred()
	elif _args.has("reportestest"):
		_probar_reportes.call_deferred()
	elif _args.has("fotos"):
		_fotos.call_deferred()


# ------------------------------------------------------------------ sesion
func guardar_sesion(token: String, horas: float) -> void:
	api.token = token
	var cfg := ConfigFile.new()
	cfg.set_value("panel", "url", api.url)
	cfg.set_value("panel", "token", token)
	cfg.set_value("panel", "vence", Time.get_unix_time_from_system() + horas * 3600.0 - 120.0)
	cfg.save(ARCHIVO)


func cerrar_sesion(mensaje := "") -> void:
	api.token = ""
	var cfg := ConfigFile.new()
	cfg.set_value("panel", "url", api.url)
	cfg.save(ARCHIVO)
	for d in _capa_dlg.get_children():
		d.queue_free()
	ir_a(VistaEntrar.new(self), true)
	if mensaje != "":
		avisar(mensaje, false)


func _sesion_caducada() -> void:
	if api.token != "":
		cerrar_sesion("La sesión del panel caducó: vuelve a entrar")


# ------------------------------------------------------------------ pantallas
## Pone una pantalla encima (o la deja sola, con `raiz`)
func ir_a(v: Control, raiz := false) -> void:
	if raiz:
		for x in _pila:
			x.queue_free()
		_pila.clear()
	elif not _pila.is_empty():
		(_pila.back() as Control).visible = false
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vistas.add_child(v)
	_pila.append(v)
	if not raiz:
		v.position.x = 60.0
		v.modulate.a = 0.0
		var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(v, "position:x", 0.0, 0.22)
		tw.tween_property(v, "modulate:a", 1.0, 0.18)


func volver() -> void:
	if _pila.size() <= 1:
		return
	var v: Control = _pila.pop_back()
	v.queue_free()
	var ant: Control = _pila.back()
	ant.visible = true
	if ant.has_method("al_volver"):
		ant.al_volver()


func vista_actual() -> Control:
	return _pila.back() if not _pila.is_empty() else null


# ------------------------------------------------------------------ ventanas y avisos
func dialogo(titulo: String, icono := "", color := Tema.ACENTO, subtitulo := "") -> Dialogo:
	var d := Dialogo.new(titulo, icono, color, subtitulo)
	_capa_dlg.add_child(d)
	return d


func hay_dialogo() -> bool:
	return _dialogo_arriba() != null


## La ventana de encima (el selector de articulos se abre encima de otra ventana)
func _dialogo_arriba() -> Dialogo:
	for i in range(_capa_dlg.get_child_count() - 1, -1, -1):
		var d := _capa_dlg.get_child(i)
		if d is Dialogo and not d.is_queued_for_deletion():
			return d
	return null


## Un aviso abajo que se va solo. `ok` = verde con check; si no, rojo con la alerta. Con `icono` (y su `color`), ese
## icono en vez del check (los de EN VIVO: la pantalla roja); con `al_tocar`, tocarlo hace algo (y se va).
func avisar(texto: String, ok := true, icono := "", color := Color.TRANSPARENT, al_tocar := Callable()) -> void:
	if _aviso != null and is_instance_valid(_aviso):
		_aviso.queue_free()
	var p := PanelContainer.new()
	var col := Tema.OK if ok else Tema.PELIGRO
	if color.a > 0.0:
		col = color
	p.add_theme_stylebox_override("panel", Tema.caja(Tema.SUP3, 14, Color(col, 0.55), 1, Vector4(16, 14, 16, 14)))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := Tema.hbox(12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := Iconos.new(icono if icono != "" else ("check" if ok else "alerta"), col, 20)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	h.add_child(Tema.parrafo(texto, 15, Tema.TEXTO))
	if al_tocar.is_valid():
		var fl := Iconos.new("flecha", Tema.TEXTO3, 14)
		fl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(fl)
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not Tema.arrastrando:
				p.queue_free()
				al_tocar.call())
	p.add_child(h)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pila_aviso.add_child(p)
	_aviso = p
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.18)
	tw.tween_interval(4.5 if icono != "" else (2.8 if ok else 4.0))
	tw.chain().tween_property(p, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(p.queue_free)


func _alto_teclado() -> float:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return 0.0
	var kb := float(DisplayServer.virtual_keyboard_get_height())
	if kb <= 0.0:
		return 0.0
	var k := get_viewport().get_screen_transform().get_scale().y
	return kb / maxf(0.01, k)


# ------------------------------------------------------------------ el dedo
func _scroll_en(p: Vector2) -> ScrollContainer:
	var mejor: ScrollContainer = null
	var area := INF
	var arriba := _dialogo_arriba()
	for n in get_tree().get_nodes_in_group("desliza"):
		var sc := n as ScrollContainer
		if sc == null or not sc.is_visible_in_tree():
			continue
		if arriba != null and not arriba.is_ancestor_of(sc):
			continue
		var r := sc.get_global_rect()
		if r.has_point(p) and r.get_area() < area:
			mejor = sc
			area = r.get_area()
	return mejor


## La barra de abajo (vista_inicio.gd): se arrastra en HORIZONTAL (grupo "desliza_h")
func _scroll_h_en(p: Vector2) -> ScrollContainer:
	if _dialogo_arriba() != null:
		return null
	for n in get_tree().get_nodes_in_group("desliza_h"):
		var sc := n as ScrollContainer
		if sc != null and sc.is_visible_in_tree() and sc.get_global_rect().has_point(p):
			return sc
	return null


func _input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := e as InputEventMouseButton
		if mb.pressed:
			_apretado = true
			_p0 = mb.position
			_sc = _scroll_en(mb.position)
			_sch = _scroll_h_en(mb.position)
			_horizontal = false
			_vel = 0.0
			Tema.arrastrando = false
		else:
			_apretado = false
			if Time.get_ticks_msec() - _t_mov > 80:
				_vel = 0.0              # el dedo se quedo quieto antes de soltar: sin inercia
	elif e is InputEventMouseMotion and _apretado and _sch != null and is_instance_valid(_sch) and \
			(_horizontal or (not Tema.arrastrando and absf((e as InputEventMouseMotion).position.x - _p0.x) > 10.0 and
			absf((e as InputEventMouseMotion).position.x - _p0.x) > absf((e as InputEventMouseMotion).position.y - _p0.y))):
		# la barra de abajo, de lado
		var mh := e as InputEventMouseMotion
		Tema.arrastrando = true
		_horizontal = true
		var ahora_h := Time.get_ticks_msec()
		var dt_h := maxf(0.001, (ahora_h - _t_mov) / 1000.0)
		_t_mov = ahora_h
		_sch.scroll_horizontal = int(_sch.scroll_horizontal - mh.relative.x)
		_vel = lerpf(_vel, -mh.relative.x / dt_h, 0.4) if dt_h < 0.1 else -mh.relative.x / 0.016
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion and _apretado and _sc != null and is_instance_valid(_sc):
		var mm := e as InputEventMouseMotion
		if not Tema.arrastrando and absf(mm.position.y - _p0.y) > 10.0 and absf(mm.position.y - _p0.y) > absf(mm.position.x - _p0.x):
			Tema.arrastrando = true
			var foco := get_viewport().gui_get_focus_owner()
			if foco is LineEdit:
				foco.release_focus()
		if Tema.arrastrando:
			var ahora := Time.get_ticks_msec()
			var dt := maxf(0.001, (ahora - _t_mov) / 1000.0)
			_t_mov = ahora
			_sc.scroll_vertical = int(_sc.scroll_vertical - mm.relative.y)
			_vel = lerpf(_vel, -mm.relative.y / dt, 0.4) if dt < 0.1 else -mm.relative.y / 0.016
			get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	# la inercia al soltar
	if not _apretado and absf(_vel) > 30.0 and _horizontal and _sch != null and is_instance_valid(_sch):
		var antes_h := _sch.scroll_horizontal
		_sch.scroll_horizontal = int(_sch.scroll_horizontal + _vel * dt)
		_vel *= pow(0.04, dt)
		if _sch.scroll_horizontal == antes_h:
			_vel = 0.0
	elif not _apretado and absf(_vel) > 30.0 and _sc != null and is_instance_valid(_sc):
		var antes := _sc.scroll_vertical
		_sc.scroll_vertical = int(_sc.scroll_vertical + _vel * dt)
		_vel *= pow(0.04, dt)
		if _sc.scroll_vertical == antes:
			_vel = 0.0
	# el teclado del movil tapa la ventana: que suba
	var kb := _alto_teclado()
	for d in _capa_dlg.get_children():
		if d is Dialogo:
			d.teclado(kb)
	_capa_aviso.add_theme_constant_override("margin_bottom", int(84.0 + kb))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		for i in range(_capa_dlg.get_child_count() - 1, -1, -1):
			var d := _capa_dlg.get_child(i)
			if d is Dialogo and not d.is_queued_for_deletion():
				d.cerrar()
				return
		if _pila.size() > 1:
			volver()
		else:
			get_tree().quit()


# ------------------------------------------------------------------ fotos de prueba
func _foto(nombre: String) -> void:
	for _i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var dir := String(_args["fotos"])
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(nombre + ".png"))
	print("[fotos] ", nombre)


func _esperar(seg: float) -> void:
	await get_tree().create_timer(seg).timeout


func _fotos() -> void:
	await _esperar(0.6)
	var v = vista_actual()
	# TORNEOS (con --url y --clave, contra un servidor de verdad o LOCAL): la pestaña y desplazada hasta abajo
	if String(_args.get("solo", "")) == "torneos":
		if v is VistaEntrar and _args.has("clave"):
			await v.entrar_con(String(_args["clave"]))
		await _esperar(1.5)
		v = vista_actual()
		v.ver_pestana(VistaInicio.P_TORNEOS)
		await _esperar(2.0)
		await _foto("t1_torneo")
		for n in get_tree().get_nodes_in_group("desliza"):
			if (n as Control).is_visible_in_tree():
				(n as ScrollContainer).scroll_vertical = 900
		await _esperar(0.4)
		await _foto("t2_premios")
		for n in get_tree().get_nodes_in_group("desliza"):
			if (n as Control).is_visible_in_tree():
				(n as ScrollContainer).scroll_vertical = 100000
		await _esperar(0.4)
		await _foto("t3_tabla")
		get_tree().quit(0)
		return
	if String(_args.get("solo", "")) == "tienda" and v is VistaInicio:
		v.ver_pestana(VistaInicio.P_TIENDA)
		await _esperar(4.0)
		await _foto("t_tienda")
		get_tree().quit(0)
		return
	if _args.has("juegoprueba"):
		if String(_args.get("solo", "")) == "version":
			await _fotos_version()
			get_tree().quit(0)
			return
		if String(_args.get("solo", "")) == "bloqueos":
			await _fotos_bloqueos()
			get_tree().quit(0)
			return
		if String(_args.get("solo", "")) == "mensajes":
			await _fotos_mensajes("m", true)
			get_tree().quit(0)
			return
		if String(_args.get("solo", "")) != "reportes":
			await _fotos_juego("j", true)
		await _fotos_reportes("r", true)
		get_tree().quit(0)
		return
	if v is VistaEntrar:
		await _foto("01_entrar")
		if _args.has("clave"):
			await v.entrar_con(String(_args["clave"]))
	await _esperar(1.5)
	v = vista_actual()
	if not (v is VistaInicio):
		print("[fotos] no se pudo entrar")
		get_tree().quit(1)
		return
	if String(_args.get("solo", "")) == "reportes":
		await _fotos_reportes("r", false)
		get_tree().quit(0)
		return
	if String(_args.get("solo", "")) == "codigos":
		v.ver_pestana(VistaInicio.P_CODIGOS)
		await _esperar(1.5)
		await _foto("c1_codigos")
		v.codigos.editar({})
		await _esperar(0.8)
		await _foto("c2_nuevo")
		get_tree().quit(0)
		return
	if String(_args.get("solo", "")) == "mensajes":
		await _fotos_mensajes("m", false)
		get_tree().quit(0)
		return
	await _foto("02_jugadores")
	# EN VIVO: ya pidio al entrar; se espera a que llegue
	v.ver_pestana(VistaInicio.P_VIVO)
	for _i in 30:
		if v.vivo.cargada:
			break
		await _esperar(0.2)
	await _esperar(0.8)
	await _foto("03_vivo")
	v.bajar(700)
	await _esperar(0.4)
	await _foto("04_vivo_abajo")
	v.bajar(-100000)
	if _args.has("espectar"):
		# ESPECTAR entero, tocando lo que tocaria uno: la primera sala y, si hace falta, la cuenta del juego
		# `--espectar=<usuario>`. OJO: cambia la cuenta del juego en el servidor (solo contra uno de pruebas).
		var salas: Array = v.vivo.datos.get("salas", [])
		if not salas.is_empty():
			v.vivo.espectar(salas[0])
			await _esperar(0.8)
			if hay_dialogo():
				await _foto("05a_espectar_sin_cuenta")
				for b in _capa_dlg.find_children("*", "Button", true, false):
					if b.has_meta("usuario") and String(b.get_meta("usuario")) == String(_args["espectar"]):
						b.tocado.emit()
				await _esperar(1.2)
			await _foto("05b_espectar_aviso")
			await _esperar(0.6)
	v.vivo.elegir_cuenta()
	await _esperar(0.5)
	await _foto("05_cuenta_juego")
	for d in _capa_dlg.get_children():
		d.queue_free()
	v.ver_pestana(VistaInicio.P_RESUMEN)
	await _esperar(1.2)
	await _foto("06_resumen")
	v.ver_pestana(VistaInicio.P_REGALOS)
	await _esperar(1.0)
	await _foto("07_regalos")
	v.nuevo_regalo_todos()
	await _esperar(0.5)
	await _foto("08_regalo_todos")
	for d in _capa_dlg.get_children():
		d.queue_free()
	v.ver_pestana(VistaInicio.P_TIENDA)
	await _esperar(1.5)
	await _foto("09_tienda")
	v.bajar(1400)
	await _esperar(0.4)
	await _foto("10_tienda_abajo")
	v.bajar(-100000)
	v.tienda.editar()
	await _esperar(0.5)
	await _foto("11_tienda_editar")
	for e in _capa_dlg.find_children("*", "LineEdit", true, false):
		if (e as LineEdit).virtual_keyboard_type == LineEdit.KEYBOARD_TYPE_NUMBER:
			e.text = "300"
			e.text_changed.emit(e.text)
	await _foto("12_tienda_precio")
	for d in _capa_dlg.get_children():
		d.queue_free()
	v.ver_pestana(VistaInicio.P_JUGADORES)
	await _esperar(1.0)
	var primero := String(_args.get("abrir", ""))
	if primero != "":
		v.abrir_ficha(primero)
		await _esperar(1.5)
		var f = vista_actual()
		await _foto("13_ficha")
		if f is VistaFicha:
			f.desplazar_al_final()
			await _esperar(0.5)
			await _foto("14_ficha_abajo")
			f.editar_numero("monedas")
			await _esperar(0.4)
			await _foto("15_editar_oro")
			for d in _capa_dlg.get_children():
				d.queue_free()
			f.enviar_regalo()
			await _esperar(0.4)
			await _foto("16_regalo")
			for d in _capa_dlg.get_children():
				d.queue_free()
			f.elegir_articulo(func(_k): pass)
			await _esperar(1.2)
			await _foto("17_articulos")
			for d in _capa_dlg.get_children():
				d.queue_free()
			f.cambiar_clave()
			await _esperar(0.4)
			await _foto("18_clave")
			for d in _capa_dlg.get_children():
				d.queue_free()
			f.borrar_cuenta()
			await _esperar(0.4)
			await _foto("19_borrar")
			for d in _capa_dlg.get_children():
				d.queue_free()
	avisar("Oro actualizado: 1.200 → 5.000")
	await _esperar(0.5)
	await _foto("20_aviso")
	# el aviso de EN VIVO (el mismo que sale al cambiar algo), encima de la ficha
	v.vivo._avisar(["Nueva partida: Sala de Ana · Mónaco", "Pepe empezó a jugar"])
	await _esperar(0.5)
	await _foto("21_aviso_vivo")
	# JUEGO, solo mirando (con un servidor de verdad no se guarda nada)
	while vista_actual() != v and _pila.size() > 1:
		volver()
	await _fotos_juego("22", false)
	while vista_actual() != v and _pila.size() > 1:
		volver()
	await _fotos_reportes("23", false)
	while vista_actual() != v and _pila.size() > 1:
		volver()
	await _fotos_mensajes("24", false)
	get_tree().quit(0)


# ------------------------------------------------------------------ VERSION: fotos (--juegoprueba --solo=version)
func _fotos_version() -> void:
	var v = vista_actual()
	v.ver_pestana(VistaInicio.P_VERSION)
	await _esperar(1.0)
	await _foto("v1_version")
	# guardar una version nueva obligatoria (en el servidor falso) y ver como queda
	var p: PestanaVersion = v.version
	p._ultima.text = "2"
	p._obligatoria.si = true
	p._enviar()
	await _esperar(1.2)
	await _foto("v2_guardada")
	# la barra de abajo, deslizada hasta el final
	for n in get_tree().get_nodes_in_group("desliza_h"):
		(n as ScrollContainer).scroll_horizontal = 10000
	await _esperar(0.3)
	await _foto("v3_barra_al_final")


# ------------------------------------------------------------------ BLOQUEOS: fotos (--juegoprueba --solo=bloqueos)
## La pestaña tal cual (de fabrica, Nuke), un modo y un personaje apagados y guardados, y el buscador de articulos
func _fotos_bloqueos() -> void:
	var v = vista_actual()
	v.ver_pestana(VistaInicio.P_BLOQUEOS)
	await _esperar(1.2)
	await _foto("b1_bloqueos")
	var p: PestanaBloqueos = v.bloqueos
	p._edit["modos"].append("atraco")
	p._edit["personajes"].append("specter")
	p._mandar(p._edit)
	await _esperar(1.2)
	await _foto("b2_guardados")
	for n in get_tree().get_nodes_in_group("desliza"):
		if (n as ScrollContainer).is_visible_in_tree():
			(n as ScrollContainer).scroll_vertical = 10000
	await _esperar(0.4)
	await _foto("b3_articulos")


# ------------------------------------------------------------------ MENSAJES: fotos (--solo=mensajes)
## La lista, el filtro de tipo, un mensaje abierto (se marca leido solo) y abajo; con `editar` (solo sin servidor) ademas
## la ventana de MARCAR HECHO con su nota, el mensaje hecho y la lista de vuelta.
func _fotos_mensajes(pre: String, editar: bool) -> void:
	var v = vista_actual()
	if not (v is VistaInicio):
		print("[fotos] MENSAJES: no hay inicio")
		return
	var p: PestanaMensajes = v.mensajes
	v.ver_pestana(VistaInicio.P_MENSAJES)
	p.ver_estado("")
	await _esperar_lista(p)
	# la barra de abajo, hasta el final: que se vea la pestaña con su numero
	for n in get_tree().get_nodes_in_group("desliza_h"):
		(n as ScrollContainer).scroll_horizontal = 10000
	await _foto(pre + "a_mensajes")
	v.bajar(640)
	await _esperar(0.3)
	await _foto(pre + "b_mensajes_abajo")
	v.bajar(-100000)
	p.ver_tipo("sugerencia")
	await _esperar_lista(p)
	await _foto(pre + "c_filtro_ideas")
	p.ver_tipo("")
	p.ver_estado("nuevo")
	await _esperar_lista(p)
	var lista: Array = p.datos.get("mensajes", [])
	if lista.is_empty():
		p.ver_estado("")
		await _esperar_lista(p)
		lista = p.datos.get("mensajes", [])
	if lista.is_empty():
		print("[fotos] MENSAJES: no hay ninguno")
		return
	p.abrir(String(lista[0]["id"]))
	await _esperar(0.3)
	var m = vista_actual()
	if not (m is VistaMensaje) or not await _esperar_mensaje(m):
		print("[fotos] MENSAJES: el mensaje no cargó")
		return
	await _esperar(0.4)
	await _foto(pre + "d_mensaje")
	m.bajar(100000)
	await _esperar(0.3)
	await _foto(pre + "e_mensaje_abajo")
	m.bajar(-100000)
	if editar:
		m.cambiar_estado("hecho")
		await _esperar(0.4)
		for e in _capa_dlg.find_children("*", "LineEdit", true, false):
			(e as LineEdit).text = "arreglado en la versión 15"
		await _foto(pre + "f_marcar_hecho")
		for b in _capa_dlg.find_children("*", "Button", true, false):
			if b is Boton and (b as Boton).texto == "Hecho":
				b.tocado.emit()
		await _esperar(1.0)
		await _foto(pre + "g_hecho")
		volver()
		await _esperar_lista(p)
		await _esperar(0.3)
		await _foto(pre + "h_lista_de_vuelta")
		# uno sin cuenta (Anónimo y sin contacto)
		for x in p.datos.get("mensajes", []):
			if x.get("de", null) == null:
				p.abrir(String(x["id"]))
				await _esperar(0.3)
				m = vista_actual()
				if m is VistaMensaje and await _esperar_mensaje(m):
					m.bajar(100000)
					await _esperar(0.3)
					await _foto(pre + "i_anonimo")
				volver()
				await _esperar(0.5)
				break
	else:
		volver()
		await _esperar(0.5)


func _esperar_lista(p: PestanaMensajes) -> bool:
	for _i in 60:
		if p.listo:
			await _esperar(0.2)
			return true
		await _esperar(0.1)
	return false


func _esperar_mensaje(m: VistaMensaje) -> bool:
	for _i in 60:
		if m.cargado:
			await _esperar(0.2)
			return true
		await _esperar(0.1)
	return false


# ------------------------------------------------------------------ JUEGO: fotos y prueba
func _cerrar_dialogos() -> void:
	for d in _capa_dlg.get_children():
		d.queue_free()
	await _esperar(0.2)


func _esperar_juego(v) -> PestanaJuego:
	v.ver_pestana(VistaInicio.P_JUEGO)
	var j: PestanaJuego = v.juego
	for _i in 60:
		if j.listo():
			break
		await _esperar(0.2)
	await _esperar(0.5)
	return j if j.listo() else null


## Cada seccion de JUEGO. Con `editar` (solo sin servidor, o contra uno de pruebas) ademas cambia y guarda.
func _fotos_juego(pre: String, editar: bool) -> void:
	var v = vista_actual()
	if not (v is VistaInicio):
		print("[fotos] JUEGO: no hay inicio")
		return
	var j := await _esperar_juego(v)
	if j == null:
		print("[fotos] JUEGO no cargó")
		await _foto(pre + "_juego_error")
		return
	var ir := func(id: String, px := 0):
		j.ver_seccion(j.indice(id))
		v.bajar(-100000)
		if px != 0:
			v.bajar(px)
	ir.call("sube")
	await _foto(pre + "a_probabilidades")
	ir.call("sube", 560)
	await _foto(pre + "b_probabilidades_abajo")
	if editar:
		j.editar_valor("sube", "cofres_sube", [0.6, 0.45, 0.3, 0.2, 0.12])
		ir.call("sube")
		await _foto(pre + "c_probabilidades_editado")
		await j.guardar(j.seccion("sube"))
		await _esperar(0.4)
		await _foto(pre + "d_probabilidades_guardado")
	ir.call("premios")
	await _foto(pre + "e_premios_comun")
	ir.call("premios", 620)
	await _foto(pre + "f_premios_comun_abajo")
	var sp := j.seccion("premios")
	sp["rareza"] = 4
	sp["pintar"].call()
	ir.call("premios", 520)
	await _foto(pre + "g_premios_legendario")
	ir.call("premios", 1250)
	await _foto(pre + "h_premios_legendario_articulo")
	sp["rareza"] = 0
	sp["pintar"].call()
	ir.call("mejoras")
	await _foto(pre + "i_mejoras")
	ir.call("valores")
	await _foto(pre + "j_cartas")
	if editar:
		var vals: Dictionary = JuegoPiezas.copia(j.seccion("valores")["estado"]["cartas_valores"])
		vals["dano"]["base"] = 0.03
		j.editar_valor("valores", "cartas_valores", vals)
	ir.call("valores", 1150)
	await _foto(pre + "k_cartas_abajo")
	ir.call("personajes")
	await _foto(pre + "l_personajes")
	ir.call("oro")
	await _foto(pre + "m_oro")
	ir.call("pase")
	await _foto(pre + "n_pase")
	ir.call("pase", 1500)
	await _foto(pre + "o_pase_abajo")
	JuegoPase.editar(j, j.seccion("pase"), 0, "g", 0)
	await _foto(pre + "p_pase_premio")
	await _cerrar_dialogos()
	JuegoPase.editar(j, j.seccion("pase"), 8, "g", 0)
	await _foto(pre + "q_pase_skin")
	await _cerrar_dialogos()
	JuegoPase.editar(j, j.seccion("pase"), 1, "p", -1)
	await _esperar(0.2)
	for b in _capa_dlg.find_children("*", "Button", true, false):
		if b is Boton and (b as Boton).texto == "Habilidad":
			b.tocado.emit()
	await _foto(pre + "r_pase_habilidad")
	await _cerrar_dialogos()
	if editar:
		j.editar_valor("destacados", "destacados", [{"clave": "sk_dragon", "precio": 300, "moneda": "creditos"},
			{"clave": "modelo:Heraldo de Llama", "precio": 4000, "moneda": "monedas"}, {"clave": "mazo_plasma", "precio": 1500, "moneda": "monedas"}])
		j.editar_valor("destacados", "destacados_diarios", false)
	ir.call("destacados")
	await _foto(pre + "s_destacados")
	Formularios.elegir_articulo(self, ["sk_dragon"], func(_a): pass, PestanaJuego.TIPOS_VENTA, "ya está destacado")
	await _esperar(0.4)
	await _foto(pre + "t_destacados_elegir")
	await _cerrar_dialogos()
	if editar:
		await j.guardar(j.seccion("destacados"))
		await _esperar(0.4)
		await _foto(pre + "u_destacados_guardado")
	ir.call("sube")
	j.de_fabrica(j.seccion("sube"))
	await _foto(pre + "v_de_fabrica")
	await _cerrar_dialogos()


## LA PRUEBA CONTRA UN SERVIDOR (`--juegotest`): cada seccion cambia algo, GUARDAR, y se mira con GET que quedo; luego
## un error del servidor tiene que salir en el aviso; y al final DE FABRICA en todas y se mira que no queda nada.
## `--juegotest=guardar` se para antes de DE FABRICA (para mirar el servidor por fuera) y `--juegotest=fabrica` solo
## hace DE FABRICA en todas y lo comprueba.
func _probar_juego() -> void:
	var modo := str(_args["juegotest"])
	await _esperar(0.6)
	var v = vista_actual()
	if v is VistaEntrar and _args.has("clave"):
		await v.entrar_con(String(_args["clave"]))
		await _esperar(1.0)
	v = vista_actual()
	if not (v is VistaInicio):
		print("[juegotest] no se pudo entrar")
		get_tree().quit(1)
		return
	var j := await _esperar_juego(v)
	if j == null:
		print("[juegotest] JUEGO no cargó")
		get_tree().quit(1)
		return
	var fallos := 0
	var ef: Dictionary = j.datos["efectivo"]
	# los cambios de cada seccion, sobre copias de lo que hay
	var premios: Array = JuegoPiezas.copia(ef["cofres_premios"])
	premios[0][0]["max"] = 3
	premios[2].append({"t": "articulo", "w": 5, "pool": ["sk_arena", "mazo_obra"], "si_no": {"t": "oro", "min": 40, "max": 60}})
	var copias: Array = JuegoPiezas.copia(ef["cartas_copias"])
	copias[1] = 3
	var oro_c: Array = JuegoPiezas.copia(ef["cartas_oro"])
	oro_c[1] = 55
	var vals: Dictionary = JuegoPiezas.copia(ef["cartas_valores"])
	vals["dano"]["base"] = 0.03
	vals["dano"]["paso"] = 0.015
	var coste: Dictionary = JuegoPiezas.copia(ef["personajes_coste"])
	coste["2"] = [25, 30]
	var pase: Array = JuegoPiezas.copia(ef["pase_niveles"])
	pase[10]["g"] = [{"t": "diamantes", "v": 5}]
	pase[0]["p"] = [{"t": "modelo", "v": "Civil"}, {"t": "habilidad", "v": "gancho"}, {"t": "pintura", "v": "sk_arena"}]
	var dest := [{"clave": "sk_dragon", "precio": 300, "moneda": "creditos"}, {"clave": "mazo_obra", "precio": 500, "moneda": "monedas"}]
	var casos := [
		["sube", {"cofres_sube": [0.5, 0.4, 0.3, 0.2, 0.1]}, func(g: Dictionary) -> bool:
			return JuegoPiezas.igual(g["actual"].get("cofres_sube"), [0.5, 0.4, 0.3, 0.2, 0.1])],
		["premios", {"cofres_premios": premios}, func(g: Dictionary) -> bool:
			var p = g["actual"].get("cofres_premios")
			return p is Array and int(p[0][0]["max"]) == 3 and String(p[2].back()["t"]) == "articulo" \
				and JuegoPiezas.igual(p[2].back()["pool"], ["sk_arena", "mazo_obra"])],
		["mejoras", {"cartas_copias": copias, "cartas_oro": oro_c}, func(g: Dictionary) -> bool:
			return int(g["actual"].get("cartas_copias", [0, 0])[1]) == 3 and int(g["actual"].get("cartas_oro", [0, 0])[1]) == 55],
		["valores", {"cartas_valores": vals}, func(g: Dictionary) -> bool:
			var x = g["actual"].get("cartas_valores", {}).get("dano", {})
			return JuegoPiezas.igual(x.get("base"), 0.03) and JuegoPiezas.igual(x.get("paso"), 0.015)],
		["personajes", {"personajes_coste": coste}, func(g: Dictionary) -> bool:
			return JuegoPiezas.igual(g["actual"].get("personajes_coste", {}).get("2"), [25, 30])],
		["oro", {"oro_partida": 0.25}, func(g: Dictionary) -> bool:
			return JuegoPiezas.igual(g["actual"].get("oro_partida"), 0.25)],
		["pase", {"pase_niveles": pase}, func(g: Dictionary) -> bool:
			var p = g["actual"].get("pase_niveles")
			return p is Array and JuegoPiezas.igual(p[10]["g"], [{"t": "diamantes", "v": 5}]) \
				and JuegoPiezas.igual(p[0]["p"], pase[0]["p"])],
		["destacados", {"destacados": dest, "destacados_diarios": false}, func(g: Dictionary) -> bool:
			return JuegoPiezas.igual(g["destacados"], dest) and g["actual"].get("destacados_diarios") == false],
	]
	for caso in casos:
		if modo == "fabrica":
			break
		j.ver_seccion(j.indice(caso[0]))
		for k in caso[1]:
			j.editar_valor(caso[0], k, caso[1][k])
		var s := j.seccion(caso[0])
		var sin := j._sin_guardar(s)
		var ok: bool = await j.guardar(s)
		var g: Dictionary = await api.pedir("GET", "/admin/juego")
		var bien: bool = sin and ok and g["ok"] and caso[2].call(g["datos"]) and not j._sin_guardar(s) and j._cambiado(s)
		print("[juegotest] %s guardar %s" % ["OK   " if bien else "FALLO", caso[0]])
		if not bien:
			fallos += 1
			print("   sin_guardar antes=%s guardar=%s get=%s" % [sin, ok, g["ok"]])
	if _args.has("fotos") and modo != "fabrica":
		j.ver_seccion(j.indice("sube"))
		v.bajar(-100000)
		await _foto("jt_a_todo_guardado")
		j.ver_seccion(j.indice("destacados"))
		await _foto("jt_b_destacados_guardado")
	if modo == "guardar":
		print("[juegotest] ", "GUARDADO (sin de fábrica)" if fallos == 0 else "%d FALLOS" % fallos)
		get_tree().quit(fallos)
		return
	# un error del servidor: por el camino de GUARDAR, tiene que decir que no y salir en el aviso
	var malo: Array = JuegoPiezas.copia(j.datos["efectivo"]["pase_niveles"])
	malo[3]["g"] = [{"t": "modelo", "v": "No Existe"}]
	j.ver_seccion(j.indice("pase"))
	j.editar_valor("pase", "pase_niveles", malo)
	var ok_malo: bool = await j.guardar(j.seccion("pase"))
	var hay_aviso := _aviso != null and is_instance_valid(_aviso)
	var bien_malo: bool = not ok_malo and hay_aviso and j._sin_guardar(j.seccion("pase"))
	print("[juegotest] %s error del servidor en el aviso" % ["OK   " if bien_malo else "FALLO"])
	if not bien_malo:
		fallos += 1
	if _args.has("fotos"):
		v.bajar(-100000)
		await _foto("jt_c_error_servidor")
	j._rehacer(j.seccion("pase"))
	# DE FABRICA en todas
	for caso in casos:
		j.ver_seccion(j.indice(caso[0]))
		var ok2: bool = await j.restaurar(j.seccion(caso[0]))
		if not ok2:
			fallos += 1
			print("[juegotest] FALLO de fábrica ", caso[0])
	var g2: Dictionary = await api.pedir("GET", "/admin/juego")
	var limpio: bool = g2["ok"] and (g2["datos"]["actual"] as Dictionary).is_empty() and (g2["datos"]["destacados"] as Array).is_empty()
	var sin_marca := true
	for caso in casos:
		sin_marca = sin_marca and not j._cambiado(j.seccion(caso[0]))
	print("[juegotest] %s de fábrica: actual=%s destacados=%s" % ["OK   " if limpio and sin_marca else "FALLO",
		JSON.stringify(g2["datos"].get("actual", {})), JSON.stringify(g2["datos"].get("destacados", []))])
	if not (limpio and sin_marca):
		fallos += 1
	if _args.has("fotos"):
		j.ver_seccion(j.indice("sube"))
		v.bajar(-100000)
		await _foto("jt_d_de_fabrica")
	print("[juegotest] ", "TODO BIEN" if fallos == 0 else "%d FALLOS" % fallos)
	get_tree().quit(fallos)


# ------------------------------------------------------------------ REPORTES: fotos y prueba
func _esperar_reportes(p: PestanaReportes) -> bool:
	for _i in 60:
		if p.listo:
			await _esperar(0.35)
			return true
		await _esperar(0.15)
	return false


func _esperar_reporte(r: VistaReporte) -> bool:
	for _i in 60:
		if r.cargado:
			await _esperar(0.35)
			return true
		await _esperar(0.15)
	return false


## La pestaña REPORTES: pendientes, todos, el filtro de motivo, los mas reportados y un reporte entero con sus ventanas.
## Con `editar` (solo sin servidor) ademas lo marca revisado y bloquea la cuenta del reportado (en memoria).
func _fotos_reportes(pre: String, editar: bool) -> void:
	var v = vista_actual()
	if not (v is VistaInicio):
		print("[fotos] REPORTES: no hay inicio")
		return
	var p: PestanaReportes = v.reportes
	v.ver_pestana(VistaInicio.P_REPORTES)
	p.ver_estado("pendiente")
	await _esperar_reportes(p)
	await _foto(pre + "a_reportes_pendientes")
	v.bajar(640)
	await _esperar(0.3)
	await _foto(pre + "b_reportes_abajo")
	v.bajar(-100000)
	p.ver_estado("")
	await _esperar_reportes(p)
	await _foto(pre + "c_reportes_todos")
	p.elegir_motivo()
	await _esperar(0.4)
	await _foto(pre + "d_filtro_motivo")
	for b in _capa_dlg.find_children("*", "Button", true, false):
		if b is Boton and (b as Boton).texto == "Aimbot":
			b.tocado.emit()
	await _esperar_reportes(p)
	await _foto(pre + "e_filtro_aimbot")
	p.elegir_motivo()
	await _esperar(0.3)
	for b in _capa_dlg.find_children("*", "Button", true, false):
		if b is Boton and (b as Boton).texto == "Todos los motivos":
			b.tocado.emit()
	await _esperar_reportes(p)
	p.ver_orden("reportados")
	await _esperar_reportes(p)
	await _foto(pre + "f_mas_reportados")
	p.ver_orden("reciente")
	p.ver_estado("pendiente")
	await _esperar_reportes(p)
	var lista: Array = p.datos.get("reportes", [])
	if lista.is_empty():
		print("[fotos] REPORTES: no hay ninguno pendiente")
		return
	p.abrir(String(lista[0]["id"]))
	await _esperar(0.3)
	var r = vista_actual()
	if not (r is VistaReporte) or not await _esperar_reporte(r):
		print("[fotos] REPORTES: el reporte no cargó")
		return
	await _foto(pre + "g_reporte")
	r.bajar(620)
	await _esperar(0.3)
	await _foto(pre + "h_reporte_medio")
	r.bajar(100000)
	await _esperar(0.3)
	await _foto(pre + "i_reporte_abajo")
	r.bajar(-100000)
	r.cambiar_estado("revisado")
	await _esperar(0.4)
	await _foto(pre + "j_marcar_revisado")
	await _cerrar_dialogos()
	r.bloquear()
	await _esperar(0.4)
	await _foto(pre + "k_bloquear")
	await _cerrar_dialogos()
	if editar:
		r.bloquear()
		await _esperar(0.3)
		for b in _capa_dlg.find_children("*", "Button", true, false):
			if b is Boton and (b as Boton).texto == "Bloquear":
				b.tocado.emit()
		await _esperar(1.2)
		await _esperar_reporte(r)
		await _foto(pre + "l_bloqueado_y_revisado")
		r.ver_cuenta(String(r.d["reporte"]["a"]["u"]))
		await _esperar(1.2)
		await _foto(pre + "m_ver_cuenta")
		volver()
		await _esperar(0.3)
	volver()
	await _esperar(0.5)


## LA PRUEBA DE REPORTES CONTRA UN SERVIDOR (`--reportestest`, con --url y --clave; tiene que haber reportes pendientes):
## la lista, los filtros, los mas reportados, un reporte entero, MARCAR REVISADO (comprobado con GET /admin/reporte) y
## vuelta a PENDIENTE para dejarlo como estaba. Con --fotos, las fotos por el camino.
func _probar_reportes() -> void:
	await _esperar(0.6)
	var v = vista_actual()
	if v is VistaEntrar and _args.has("clave"):
		await v.entrar_con(String(_args["clave"]))
		await _esperar(1.0)
	v = vista_actual()
	if not (v is VistaInicio):
		print("[reportestest] no se pudo entrar")
		get_tree().quit(1)
		return
	var fallos := 0
	var mirar := func(ok: bool, que: String) -> int:
		print("[reportestest] %s %s" % ["OK   " if ok else "FALLO", que])
		return 0 if ok else 1
	var p: PestanaReportes = v.reportes
	v.ver_pestana(VistaInicio.P_REPORTES)
	p.ver_estado("pendiente")
	await _esperar_reportes(p)
	var lista: Array = p.datos.get("reportes", [])
	var todos_pend := lista.all(func(x): return String(x["estado"]) == "pendiente")
	fallos += mirar.call(not lista.is_empty() and todos_pend, "lista de pendientes (%d)" % lista.size())
	fallos += mirar.call(int(v._nav[VistaInicio.P_REPORTES].insignia) == int(p.datos["cuentas"]["pendiente"]),
		"el numero de la pestaña: %d sin revisar" % int(v._nav[VistaInicio.P_REPORTES].insignia))
	if _args.has("fotos"):
		await _foto("rt_a_pendientes")
	if lista.is_empty():
		get_tree().quit(1)
		return
	# el filtro de motivo
	p._motivo = "aimbot"
	p.ver_estado("")
	await _esperar_reportes(p)
	var con: Array = p.datos.get("reportes", [])
	fallos += mirar.call(not con.is_empty() and con.all(func(x): return "aimbot" in x["motivos"]), "filtro aimbot (%d)" % con.size())
	p._motivo = ""
	# los mas reportados: por personas distintas
	p.ver_orden("reportados")
	await _esperar_reportes(p)
	var jug: Array = p.datos.get("jugadores", [])
	var ordenado := true
	for i in range(1, jug.size()):
		ordenado = ordenado and int(jug[i - 1]["reportadores"]) >= int(jug[i]["reportadores"])
	fallos += mirar.call(jug.size() >= 2 and ordenado, "más reportados: %s" % ", ".join(jug.map(func(x): return "%s %d" % [x["a"]["nombre"], x["reportadores"]])))
	if _args.has("fotos"):
		await _foto("rt_b_mas_reportados")
	# uno entero
	p.ver_orden("reciente")
	p.ver_estado("pendiente")
	await _esperar_reportes(p)
	var primero: Dictionary = p.datos["reportes"][0]
	p.abrir(String(primero["id"]))
	await _esperar(0.3)
	var r = vista_actual()
	var cargo: bool = r is VistaReporte and await _esperar_reporte(r)
	fallos += mirar.call(cargo and String(r.d["reporte"]["id"]) == String(primero["id"]) and int(r.d["contra"]["total"]) >= 1
		and String(r.d["reporte"]["de"]["nombre"]) != "", "el reporte entero: %s -> %s" % [primero["de"]["nombre"], primero["a"]["nombre"]])
	if not cargo:
		get_tree().quit(1)
		return
	if _args.has("fotos"):
		await _foto("rt_c_reporte")
	# MARCAR REVISADO, por el dialogo de verdad
	r.cambiar_estado("revisado")
	await _esperar(0.4)
	for e in _capa_dlg.find_children("*", "LineEdit", true, false):
		(e as LineEdit).text = "prueba del panel"
	for b in _capa_dlg.find_children("*", "Button", true, false):
		if b is Boton and (b as Boton).texto == "Revisado":
			b.tocado.emit()
	await _esperar(1.5)
	var g: Dictionary = await api.pedir("GET", "/admin/reporte?id=" + String(primero["id"]))
	var rg: Dictionary = g["datos"].get("reporte", {})
	fallos += mirar.call(g["ok"] and String(rg.get("estado", "")) == "revisado" and String(rg.get("nota", "")) == "prueba del panel"
		and not (rg.get("historial", []) as Array).is_empty() and String(r.d["reporte"]["estado"]) == "revisado",
		"marcado revisado con nota (GET: %s)" % String(rg.get("estado", "?")))
	if _args.has("fotos"):
		await _foto("rt_d_revisado")
	# en la lista de revisados
	volver()
	await _esperar(0.3)
	p.ver_estado("revisado")
	await _esperar_reportes(p)
	fallos += mirar.call((p.datos.get("reportes", []) as Array).any(func(x): return String(x["id"]) == String(primero["id"])),
		"sale en REVISADOS")
	if _args.has("fotos"):
		await _foto("rt_e_revisados")
	# y se deja como estaba
	if _args.has("dejar"):
		print("[reportestest] (se deja revisado)")
	else:
		var b2: Dictionary = await api.pedir("POST", "/admin/reporte/estado", {"id": primero["id"], "estado": "pendiente"})
		fallos += mirar.call(b2["ok"] and String(b2["datos"]["reporte"]["estado"]) == "pendiente", "vuelta a pendiente")
	print("[reportestest] ", "TODO BIEN" if fallos == 0 else "%d FALLOS" % fallos)
	get_tree().quit(fallos)


func _probar_respaldo() -> void:
	var r := await api.pedir("GET", "/salud")
	print("[probarrespaldo] ok %s codigo %d · servidor %s" % [str(r.ok), int(r.codigo), api.url])
	get_tree().quit()


## Al abrir con un parche nuevo puesto: "Panel actualizado" (una vez por parche)
func _aviso_parche() -> void:
	var pa = get_node_or_null("/root/ParcheAdmin")
	if pa == null or int(pa.aplicado) <= 0:
		return
	var cfg := ConfigFile.new()
	cfg.load("user://parche_visto.cfg")
	if int(cfg.get_value("p", "n", 0)) == int(pa.aplicado):
		return
	cfg.set_value("p", "n", int(pa.aplicado))
	cfg.save("user://parche_visto.cfg")
	await get_tree().create_timer(1.5).timeout
	avisar("Panel actualizado (parche %d)" % int(pa.aplicado))
