class_name VistaReporte
extends Control
## UN REPORTE ENTERO (desde la pestaña REPORTES, pestana_reportes.gd). De arriba abajo:
##   cabecera     estado, fecha y hora, cuanto hace, el id
##   REPORTADO    nombre, usuario, ID, nivel, si esta bloqueada, me gusta recibidos; sus reportes en contra (cuantos, de
##                cuantas personas distintas, cuantos sin revisar); VER CUENTA y BLOQUEAR CUENTA
##   REPORTADO POR  quien lo mando (como esta ahora su cuenta) y cuantos reportes ha mandado en total; VER CUENTA
##   MOTIVOS, MENSAJE, PARTIDA (modo, mapa, sala, lo que hizo el reportado: puesto, puntos, bajas, muertes, titulo)
##   HISTORIAL    los motivos de todos sus reportes (barras) y sus otros reportes (tocar uno lo abre)
##   REVISION     los cambios de estado con su nota
## Abajo, fijo: DESCARTAR y MARCAR REVISADO (o VOLVER A PENDIENTE). Cada cambio pide una nota opcional.
## GET /admin/reporte?id= · POST /admin/reporte/estado {id, estado, nota} · POST /admin/cuenta (bloquear)

var app
var id := ""
var lista: PestanaReportes = null   ## la pestaña de la que viene (se refresca al volver)
var d: Dictionary = {}              ## lo que dio el servidor: {reporte, contra, otros, reportes_hechos}
var _sc: ScrollContainer
var _caja: VBoxContainer
var _pie: HBoxContainer
var cargado := false


func _init(p_app, p_id: String, p_lista: PestanaReportes = null) -> void:
	app = p_app
	id = p_id
	lista = p_lista


func _ready() -> void:
	var raiz := Tema.vbox(0)
	raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(raiz)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Tema.caja(Tema.FONDO, 0, Color.TRANSPARENT, 0, Vector4(6, 8, 8, 8)))
	var h := Tema.hbox(4)
	p.add_child(h)
	var atras := Boton.new("", "atras", "icono", 48)
	atras.custom_minimum_size.x = 48
	atras.tocado.connect(app.volver)
	h.add_child(atras)
	var tv := Tema.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.add_child(Tema.linea("Reporte", 20, Tema.TEXTO, 800))
	tv.add_child(Tema.linea("#" + id, 11, Tema.TEXTO3))
	h.add_child(tv)
	var ref := Boton.new("", "refrescar", "icono", 48)
	ref.custom_minimum_size.x = 48
	ref.tocado.connect(cargar)
	h.add_child(ref)
	raiz.add_child(p)
	_sc = ScrollContainer.new()
	_sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sc.scroll_deadzone = 100000
	_sc.add_to_group("desliza")
	raiz.add_child(_sc)
	var m := Tema.margen(16, 6, 16, 24)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sc.add_child(m)
	_caja = Tema.vbox(12)
	m.add_child(_caja)
	_caja.add_child(Girador.new())
	# las acciones, fijas abajo
	var pp := PanelContainer.new()
	var st := Tema.caja(Tema.SUP, 0, Color.TRANSPARENT, 0, Vector4(14, 10, 14, 12))
	st.border_color = Tema.BORDE
	st.border_width_top = 1
	pp.add_theme_stylebox_override("panel", st)
	_pie = Tema.hbox(10)
	pp.add_child(_pie)
	raiz.add_child(pp)
	cargar()


func cargar() -> void:
	var r: Dictionary = await app.api.pedir("GET", "/admin/reporte?id=" + id.uri_encode())
	if not is_inside_tree():
		return
	if not r["ok"]:
		app.avisar(Tema.frase(String(r["error"])), false)
		if r["codigo"] == 404:
			app.volver()
		return
	_poner(r["datos"])


func _poner(nuevo: Dictionary) -> void:
	d = nuevo
	cargado = true
	var y := _sc.scroll_vertical
	for n in _caja.get_children():
		n.queue_free()
	for n in _pie.get_children():
		n.queue_free()
	_pintar()
	await get_tree().process_frame
	if is_instance_valid(_sc):
		_sc.scroll_vertical = y


func al_volver() -> void:
	cargar()


func bajar(px: int) -> void:
	_sc.scroll_vertical += px


# ------------------------------------------------------------------ la ficha del reporte
func _pintar() -> void:
	var r: Dictionary = d.get("reporte", {})
	var estado := String(r.get("estado", ""))
	var col := PestanaReportes.color_estado(estado)
	# ---- cabecera
	var cab := Tema.tarjeta(16, Tema.SUP.lerp(col, 0.05))
	var cv := Tema.vbox(10)
	cab.add_child(cv)
	var h := Tema.hbox(12)
	var circ := PanelContainer.new()
	circ.add_theme_stylebox_override("panel", Tema.caja(Color(col, 0.16), 12, Color.TRANSPARENT, 0, Vector4(10, 10, 10, 10)))
	circ.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	circ.add_child(Iconos.new("bandera", col, 24))
	h.add_child(circ)
	var tv := Tema.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.add_child(Tema.linea(PestanaReportes.nombre_estado(estado), 20, col, 800))
	tv.add_child(Tema.linea("Recibido el %s · %s" % [Tema.fecha(r.get("t", null)), Tema.hace(r.get("t", null))], 13, Tema.TEXTO2))
	h.add_child(tv)
	cv.add_child(h)
	if r.get("revisado", null) != null and estado != "pendiente":
		cv.add_child(Tema.linea("%s el %s" % ["Revisado" if estado == "revisado" else "Descartado", Tema.fecha(r.get("revisado", null))], 12, Tema.TEXTO3))
	if String(r.get("nota", "")) != "":
		var nota := Tema.tarjeta(10, Tema.SUP2)
		nota.add_child(Tema.parrafo("Nota: " + String(r["nota"]), 13, Tema.TEXTO))
		cv.add_child(nota)
	_caja.add_child(cab)
	# ---- el reportado
	var a: Dictionary = r.get("a", {})
	var contra: Dictionary = d.get("contra", {})
	_caja.add_child(Tema.seccion("Reportado"))
	var ta := _tarjeta_persona(a, true)
	var va: VBoxContainer = ta.get_child(0)
	var datos := Tema.hbox(8)
	datos.add_child(_cifra(str(int(contra.get("total", 0))), "reportes", Tema.TEXTO))
	var n := int(contra.get("reportadores", 0))
	datos.add_child(_cifra(str(n), "jugadores distintos", Tema.PELIGRO if n >= 3 else (Tema.AVISO if n >= 2 else Tema.TEXTO)))
	datos.add_child(_cifra(str(int(contra.get("pendientes", 0))), "sin revisar", Tema.AVISO if int(contra.get("pendientes", 0)) > 0 else Tema.TEXTO))
	va.add_child(datos)
	var bot := Tema.hbox(10)
	var ver := Boton.new("Ver cuenta", "usuario", "secundario", 46)
	ver.tam = 14
	ver.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ver.disabled = not bool(a.get("existe", true))
	ver.tocado.connect(func(): ver_cuenta(String(a.get("u", ""))))
	bot.add_child(ver)
	var bl := bool(a.get("bloqueada", false))
	var bb := Boton.new("Desbloquear" if bl else "Bloquear cuenta", "candado_abierto" if bl else "bloqueo", "secundario" if bl else "peligro", 46)
	bb.tam = 14
	bb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bb.disabled = not bool(a.get("existe", true))
	bb.tocado.connect(bloquear)
	bot.add_child(bb)
	va.add_child(bot)
	_caja.add_child(ta)
	# ---- quien lo mando
	var de: Dictionary = r.get("de", {})
	_caja.add_child(Tema.seccion("Reportado por"))
	var td := _tarjeta_persona(de, false)
	var vd: VBoxContainer = td.get_child(0)
	var hechos := int(d.get("reportes_hechos", 0))
	var bd := Tema.hbox(10)
	var linea := Tema.linea("Ha enviado %d reporte%s" % [hechos, "" if hechos == 1 else "s"], 13, Tema.TEXTO2)
	linea.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bd.add_child(linea)
	var ver2 := Boton.new("Ver cuenta", "usuario", "fantasma", 40)
	ver2.tam = 13
	ver2.disabled = not bool(de.get("existe", true))
	ver2.tocado.connect(func(): ver_cuenta(String(de.get("u", ""))))
	bd.add_child(ver2)
	vd.add_child(bd)
	_caja.add_child(td)
	# ---- motivos
	_caja.add_child(Tema.seccion("Motivos"))
	var tm := Tema.tarjeta(14)
	var vm := Tema.vbox(8)
	tm.add_child(vm)
	var textos: Array = r.get("motivos_texto", [])
	var motivos: Array = r.get("motivos", [])
	for i in motivos.size():
		var fila := Tema.hbox(10)
		var c := PestanaReportes.color_motivo(String(motivos[i]))
		var pt := PanelContainer.new()
		pt.add_theme_stylebox_override("panel", Tema.caja(c, 4))
		pt.custom_minimum_size = Vector2(8, 8)
		pt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		fila.add_child(pt)
		fila.add_child(Tema.linea(String(textos[i]) if i < textos.size() else PestanaReportes.texto_motivo(String(motivos[i])), 15, Tema.TEXTO, 600))
		var grupo := String(PestanaReportes.MOTIVOS.get(String(motivos[i]), ["", "otro"])[1])
		fila.add_child(Tema.chip({"trampas": "TRAMPAS", "conducta": "CONDUCTA"}.get(grupo, "OTRO"), c, "", false))
		vm.add_child(fila)
	_caja.add_child(tm)
	# ---- mensaje
	_caja.add_child(Tema.seccion("Mensaje"))
	var tmsg := Tema.tarjeta(14)
	var msg := String(r.get("mensaje", "")).strip_edges()
	if msg == "":
		tmsg.add_child(Tema.parrafo("No escribió nada.", 14, Tema.TEXTO3))
	else:
		var hm := Tema.hbox(10)
		var comilla := Tema.etiqueta("“", 34, Tema.ACENTO, 800)
		comilla.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		hm.add_child(comilla)
		hm.add_child(Tema.parrafo(msg, 15, Tema.TEXTO))
		tmsg.add_child(hm)
	_caja.add_child(tmsg)
	# ---- partida
	var p: Dictionary = r.get("partida", {})
	var jp: Dictionary = p.get("jugador", {})
	_caja.add_child(Tema.seccion("Partida"))
	var tp := Tema.tarjeta(14)
	var vp := Tema.vbox(8)
	tp.add_child(vp)
	vp.add_child(_dato("mando", "Modo", PestanaReportes.texto_modo(String(p.get("modo", "")))))
	vp.add_child(_dato("mapa", "Mapa", PestanaReportes.texto_mapa(String(p.get("mapa", "")))))
	if String(p.get("sala_nombre", "")) != "" or String(p.get("sala", "")) != "":
		vp.add_child(_dato("servidor", "Sala", (String(p.get("sala_nombre", "")) + ("  (%s)" % String(p["sala"]) if String(p.get("sala", "")) != "" else "")).strip_edges()))
	vp.add_child(_dato("id", "Partida", String(p.get("clave", "—"))))
	vp.add_child(Tema.separador())
	vp.add_child(Tema.linea("LO QUE HIZO %s" % String(jp.get("nombre", a.get("nombre", ""))).to_upper(), 11, Tema.TEXTO3, 700))
	var rej := GridContainer.new()
	rej.columns = 4
	rej.add_theme_constant_override("h_separation", 8)
	rej.add_theme_constant_override("v_separation", 8)
	var bajas := int(jp.get("bajas", 0))
	var muertes := int(jp.get("muertes", 0))
	for o in [["Puesto", "%d.º" % int(jp.get("puesto", 0)) if int(jp.get("puesto", 0)) > 0 else "—"], ["Puntos", Tema.numero(int(jp.get("puntos", 0)))],
			["Bajas", str(bajas)], ["Muertes", str(muertes)]]:
		rej.add_child(_cifra(String(o[1]), String(o[0]).to_lower(), Tema.TEXTO))
	vp.add_child(rej)
	var kd := float(bajas) / maxf(1.0, float(muertes))
	var kd_col := Tema.PELIGRO if kd >= 4.0 else Tema.TEXTO2
	var hk := Tema.hbox(8)
	hk.add_child(Tema.linea("Bajas por muerte: %.1f" % kd, 13, kd_col, 600 if kd >= 4.0 else 400))
	if String(jp.get("titulo", "")) != "":
		hk.add_child(Tema.chip(String(jp["titulo"]), Tema.ACENTO, "trofeo", false))
	vp.add_child(hk)
	_caja.add_child(tp)
	# ---- historial contra el reportado
	_caja.add_child(Tema.seccion("Historial contra %s" % String(a.get("nombre", ""))))
	var th := Tema.tarjeta(14)
	var vh := Tema.vbox(10)
	th.add_child(vh)
	var por: Dictionary = contra.get("motivos", {})
	var claves: Array = por.keys()
	claves.sort_custom(func(x, y): return int(por[x]) > int(por[y]))
	var tot := maxi(1, int(contra.get("total", 1)))
	for k in claves:
		var fila := Tema.vbox(4)
		var fh := Tema.hbox(8)
		fh.add_child(Tema.linea(PestanaReportes.texto_motivo(String(k)), 14, Tema.TEXTO, 600))
		var cuenta := Tema.etiqueta("%d de %d" % [int(por[k]), int(contra.get("total", 0))], 13, Tema.TEXTO2, 600)
		fh.add_child(cuenta)
		fila.add_child(fh)
		fila.add_child(_barra(float(por[k]) / tot, PestanaReportes.color_motivo(String(k))))
		vh.add_child(fila)
	var otros: Array = d.get("otros", [])
	if not otros.is_empty():
		vh.add_child(Tema.separador())
		vh.add_child(Tema.linea("SUS OTROS REPORTES", 11, Tema.TEXTO3, 700))
		for o in otros:
			vh.add_child(_fila_otro(o))
	if lista != null:
		var todos := Boton.new("Ver todos sus reportes en la lista", "buscar", "texto", 40)
		todos.tam = 14
		todos.tocado.connect(func():
			lista.ver_jugador(String(a.get("u", "")))
			app.volver())
		vh.add_child(todos)
	_caja.add_child(th)
	# ---- revision
	var hist: Array = r.get("historial", [])
	if not hist.is_empty():
		_caja.add_child(Tema.seccion("Revisión"))
		var trv := Tema.tarjeta(14)
		var vr := Tema.vbox(8)
		trv.add_child(vr)
		for i in range(hist.size() - 1, -1, -1):
			var e: Dictionary = hist[i]
			var fr := Tema.hbox(10)
			var ic := Iconos.new("reloj", Tema.TEXTO3, 14)
			ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			fr.add_child(ic)
			fr.add_child(Tema.parrafo(String(e.get("que", "")), 13, Tema.TEXTO))
			var f := Tema.etiqueta(Tema.fecha(e.get("t", null)), 12, Tema.TEXTO3)
			f.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			fr.add_child(f)
			vr.add_child(fr)
		_caja.add_child(trv)
	# ---- las acciones de abajo
	if estado == "pendiente":
		var desc := Boton.new("Descartar", "cerrar", "secundario", 52)
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc.tocado.connect(func(): cambiar_estado("descartado"))
		_pie.add_child(desc)
		var rev := Boton.new("Marcar revisado", "check", "primario", 52)
		rev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rev.size_flags_stretch_ratio = 1.4
		rev.tocado.connect(func(): cambiar_estado("revisado"))
		_pie.add_child(rev)
	else:
		var vuelve := Boton.new("Volver a pendiente", "refrescar", "secundario", 52)
		vuelve.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vuelve.tocado.connect(func(): cambiar_estado("pendiente"))
		_pie.add_child(vuelve)
		var otro := "descartado" if estado == "revisado" else "revisado"
		var b2 := Boton.new("Descartar" if otro == "descartado" else "Marcar revisado", "cerrar" if otro == "descartado" else "check",
			"fantasma", 52)
		b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b2.tocado.connect(func(): cambiar_estado(otro))
		_pie.add_child(b2)


## La tarjeta de una persona del reporte: avatar, nombre, usuario, ID, nivel y sus chips
func _tarjeta_persona(p: Dictionary, reportado: bool) -> PanelContainer:
	var tj := Tema.tarjeta(16, Tema.SUP.lerp(Tema.PELIGRO, 0.04) if reportado else Tema.SUP)
	var v := Tema.vbox(12)
	tj.add_child(v)
	var h := Tema.hbox(14)
	h.add_child(Tema.avatar(String(p.get("nombre", "")), 58 if reportado else 46))
	var tv := Tema.vbox(3)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.add_child(Tema.linea(String(p.get("nombre", "")), 21 if reportado else 17, Tema.TEXTO, 800))
	var sub := "@" + String(p.get("u", "")) if not bool(p.get("google", false)) else "cuenta de Google"
	tv.add_child(Tema.linea(sub, 13, Tema.TEXTO2))
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	chips.add_child(Tema.chip("NV %d" % int(p.get("nivel", 1)), Tema.ACENTO))
	if PestanaReportes.texto_id(p.get("id", null)) != "":
		chips.add_child(Tema.chip("ID %s" % PestanaReportes.texto_id(p["id"]), Tema.TEXTO2, "id"))
	if not bool(p.get("existe", true)):
		chips.add_child(Tema.chip("CUENTA BORRADA", Tema.TEXTO3))
	if bool(p.get("bloqueada", false)):
		chips.add_child(Tema.chip("BLOQUEADA", Tema.PELIGRO, "bloqueo"))
	if reportado and int(p.get("likes", 0)) > 0:
		chips.add_child(Tema.chip("%d ME GUSTA" % int(p["likes"]), Tema.OK))
	tv.add_child(chips)
	h.add_child(tv)
	v.add_child(h)
	if bool(p.get("bloqueada", false)) and String(p.get("motivo_bloqueo", "")) != "":
		v.add_child(Tema.parrafo("Motivo del bloqueo: " + String(p["motivo_bloqueo"]), 13, Tema.PELIGRO))
	return tj


func _cifra(valor: String, titulo: String, color: Color) -> Control:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", Tema.caja(Tema.SUP2, 12, Color.TRANSPARENT, 0, Vector4(10, 8, 10, 8)))
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := Tema.vbox(0)
	pc.add_child(v)
	var n := Tema.etiqueta(valor, 20, color, 800)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var t := Tema.etiqueta(titulo, 11, Tema.TEXTO3, 600)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	return pc


func _dato(icono: String, titulo: String, valor: String) -> Control:
	var h := Tema.hbox(10)
	var ic := Iconos.new(icono, Tema.TEXTO3, 16)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var t := Tema.etiqueta(titulo, 14, Tema.TEXTO2)
	t.custom_minimum_size.x = 64
	h.add_child(t)
	var v := Tema.linea(valor, 14, Tema.TEXTO, 600)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(v)
	return h


func _barra(k: float, color: Color) -> Control:
	var b := Control.new()
	b.custom_minimum_size = Vector2(0, 8)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.draw.connect(func():
		b.draw_style_box(Tema.caja(Tema.SUP3, 4), Rect2(Vector2.ZERO, b.size))
		var w := maxf(8.0, b.size.x * clampf(k, 0.0, 1.0))
		b.draw_style_box(Tema.caja(color, 4), Rect2(Vector2.ZERO, Vector2(w, b.size.y))))
	return b


func _fila_otro(o: Dictionary) -> Control:
	var tj := PanelContainer.new()
	tj.add_theme_stylebox_override("panel", Tema.caja(Tema.SUP2, 12, Color.TRANSPARENT, 0, Vector4(12, 10, 12, 10)))
	var v := Tema.vbox(6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tj.add_child(v)
	var h := Tema.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var estado := String(o.get("estado", ""))
	h.add_child(Tema.chip(PestanaReportes.nombre_estado(estado), PestanaReportes.color_estado(estado)))
	h.add_child(Tema.linea("de %s · %s" % [String(o.get("de", {}).get("nombre", "")), Tema.hace(o.get("t", null))], 13, Tema.TEXTO2))
	var fl := Iconos.new("flecha", Tema.TEXTO3, 12)
	fl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(fl)
	v.add_child(h)
	v.add_child(PestanaReportes.chips_motivos(o.get("motivos", [])))
	var oid := String(o.get("id", ""))
	PestanaReportes.tocable(tj, func(): app.ir_a(VistaReporte.new(app, oid, lista)))
	return tj


# ------------------------------------------------------------------ acciones
func ver_cuenta(u: String) -> void:
	if u != "":
		app.ir_a(VistaFicha.new(app, u))


## Pendiente / revisado / descartado, con una nota opcional que queda en el reporte
func cambiar_estado(estado: String) -> void:
	var titulo: String = {"revisado": "Marcar como revisado", "descartado": "Descartar el reporte", "pendiente": "Volver a pendiente"}[estado]
	var icono: String = {"revisado": "check", "descartado": "cerrar", "pendiente": "refrescar"}[estado]
	var dlg: Dialogo = app.dialogo(titulo, icono, PestanaReportes.color_estado(estado),
		"Reporte de %s" % String(d.get("reporte", {}).get("a", {}).get("nombre", "")))
	dlg.cuerpo.add_child(Tema.parrafo({"revisado": "Lo has mirado y has actuado (o no hacía falta). Queda apuntado con la fecha.",
		"descartado": "El reporte no se sostiene: no hay nada que hacer. Sigue contando en el historial del jugador.",
		"pendiente": "Vuelve a la lista de lo que falta por mirar."}[estado], 14, Tema.TEXTO2))
	dlg.cuerpo.add_child(Tema.etiqueta("Nota (opcional)", 14, Tema.TEXTO2, 600))
	var nota := Tema.campo("Ej.: visto en la repetición, sin pruebas…")
	nota.max_length = 200
	dlg.cuerpo.add_child(nota)
	dlg.boton("Cancelar").tocado.connect(dlg.cerrar)
	var ok := dlg.boton({"revisado": "Revisado", "descartado": "Descartar", "pendiente": "A pendiente"}[estado],
		"primario" if estado == "revisado" else "secundario", icono)
	ok.tocado.connect(func():
		ok.cargando = true
		var bien := await enviar_estado(estado, nota.text.strip_edges())
		if is_instance_valid(ok):
			ok.cargando = false
		if bien:
			dlg.cerrar())


## Manda el cambio de estado y repinta. Devuelve si fue bien (lo usa tambien la prueba).
func enviar_estado(estado: String, nota := "") -> bool:
	var r: Dictionary = await app.api.pedir("POST", "/admin/reporte/estado", {"id": id, "estado": estado, "nota": nota})
	if not r["ok"]:
		app.avisar(Tema.frase(String(r["error"])), false)
		return false
	if is_inside_tree():
		_poner(r["datos"])
	app.avisar({"revisado": "Reporte marcado como revisado", "descartado": "Reporte descartado", "pendiente": "Reporte pendiente otra vez"}[estado])
	return true


## BLOQUEAR LA CUENTA DEL REPORTADO (la accion de siempre del panel, POST /admin/cuenta), con el motivo ya escrito a
## partir del reporte; y el reporte queda revisado con la nota "cuenta bloqueada".
func bloquear() -> void:
	var r: Dictionary = d.get("reporte", {})
	var a: Dictionary = r.get("a", {})
	var u := String(a.get("u", ""))
	if bool(a.get("bloqueada", false)):
		var dd: Dialogo = app.dialogo("Desbloquear", "candado_abierto", Tema.OK, String(a.get("nombre", "")))
		dd.cuerpo.add_child(Tema.parrafo("Podrá volver a entrar y jugar con su cuenta.", 15))
		dd.boton("Cancelar").tocado.connect(dd.cerrar)
		var bok := dd.boton("Desbloquear", "primario")
		bok.tocado.connect(func():
			bok.cargando = true
			var rr: Dictionary = await app.api.pedir("POST", "/admin/cuenta", {"u": u, "cambios": {"bloqueada": false}})
			if is_instance_valid(bok):
				bok.cargando = false
			if not rr["ok"]:
				app.avisar(Tema.frase(String(rr["error"])), false)
				return
			dd.cerrar()
			app.avisar("Cuenta desbloqueada")
			cargar())
		return
	var textos: Array = []
	for m in r.get("motivos", []):
		textos.append(PestanaReportes.texto_motivo(String(m)).to_lower())
	var n := int(d.get("contra", {}).get("reportadores", 1))
	var motivo := ("Reportado por %s: %s" % ["%d jugadores" % n if n != 1 else "un jugador", ", ".join(textos)]).left(120)
	var dlg: Dialogo = app.dialogo("Bloquear cuenta", "bloqueo", Tema.PELIGRO, String(a.get("nombre", "")))
	var aviso := Tema.tarjeta(12, Color(Tema.PELIGRO, 0.08))
	aviso.add_child(Tema.parrafo("No podrá entrar con su cuenta ni cobrar partidas. Si está conectado, lo echa en menos de un minuto. Se puede deshacer desde su ficha.", 14, Tema.TEXTO))
	dlg.cuerpo.add_child(aviso)
	dlg.cuerpo.add_child(Tema.etiqueta("Motivo (lo verá al intentar entrar)", 14, Tema.TEXTO2, 600))
	var mot := Tema.campo("Ej.: trampas, insultos…", false, motivo)
	mot.max_length = 120
	dlg.cuerpo.add_child(mot)
	dlg.boton("Cancelar").tocado.connect(dlg.cerrar)
	var ok := dlg.boton("Bloquear", "peligro", "bloqueo")
	ok.tocado.connect(func():
		ok.cargando = true
		var rr: Dictionary = await app.api.pedir("POST", "/admin/cuenta", {"u": u, "cambios": {"bloqueada": true, "motivo": mot.text.strip_edges()}})
		if is_instance_valid(ok):
			ok.cargando = false
		if not rr["ok"]:
			app.avisar(Tema.frase(String(rr["error"])), false)
			return
		dlg.cerrar()
		app.avisar("Cuenta de %s bloqueada" % String(a.get("nombre", "")))
		if String(r.get("estado", "")) == "pendiente":
			await enviar_estado("revisado", "cuenta bloqueada")
		else:
			cargar())
