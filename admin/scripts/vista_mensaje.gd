class_name VistaMensaje
extends Control
## UN MENSAJE ENTERO (desde la pestaña MENSAJES, pestana_mensajes.gd). De arriba abajo:
##   cabecera     el tipo (idea, error, reporte, otro), el estado, fecha y hora, cuanto hace, y la nota si la hay
##   MENSAJE      el texto entero (hasta 1000 letras, con sus saltos de linea) y COPIAR
##   DE           quien lo mando (nombre, usuario, ID, nivel, si esta bloqueada o borrada) y cuantos ha mandado; VER CUENTA.
##                Sin cuenta: "Anónimo"
##   CONTACTO     el correo o el Discord que dejo, con COPIAR
##   DISPOSITIVO  version de la app, plataforma, modelo y el mapa en el que estaba
##   HISTORIAL    los cambios de estado con su nota
## Abajo, fijo: MARCAR LEÍDO / MARCAR HECHO / VOLVER A NUEVO (los dos que no es ahora). Cada cambio pide una nota opcional.
## Al ABRIR uno NUEVO se marca LEÍDO solo (sin nota).
## GET /admin/mensaje?id= · POST /admin/mensaje/estado {id, estado, nota}

var app
var id := ""
var lista: PestanaMensajes = null   ## la pestaña de la que viene (se refresca al volver)
var d: Dictionary = {}              ## lo que dio el servidor: {mensaje, del_mismo, tipos}
var _sc: ScrollContainer
var _caja: VBoxContainer
var _pie: HBoxContainer
var cargado := false
var _primera := true                ## la primera carga: si es NUEVO, se marca leido


func _init(p_app, p_id: String, p_lista: PestanaMensajes = null) -> void:
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
	tv.add_child(Tema.linea("Mensaje", 20, Tema.TEXTO, 800))
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
	var r: Dictionary = await app.api.pedir("GET", "/admin/mensaje?id=" + id.uri_encode())
	if not is_inside_tree():
		return
	if not r["ok"]:
		app.avisar(Tema.frase(String(r["error"])), false)
		if r["codigo"] == 404:
			app.volver()
		return
	var primera := _primera
	_primera = false
	if primera and String(r["datos"].get("mensaje", {}).get("estado", "")) == "nuevo":
		# abrirlo es leerlo: se marca LEIDO solo, sin nota ni aviso
		var r2: Dictionary = await app.api.pedir("POST", "/admin/mensaje/estado", {"id": id, "estado": "leido", "nota": ""})
		if not is_inside_tree():
			return
		if r2["ok"]:
			r = r2
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


# ------------------------------------------------------------------ el mensaje
func _pintar() -> void:
	var m: Dictionary = d.get("mensaje", {})
	var estado := String(m.get("estado", ""))
	var tipo := String(m.get("tipo", "otro"))
	var col := PestanaMensajes.color_tipo(tipo)
	# ---- cabecera
	var cab := Tema.tarjeta(16, Tema.SUP.lerp(col, 0.05))
	var cv := Tema.vbox(10)
	cab.add_child(cv)
	var h := Tema.hbox(12)
	var circ := PanelContainer.new()
	circ.add_theme_stylebox_override("panel", Tema.caja(Color(col, 0.16), 12, Color.TRANSPARENT, 0, Vector4(10, 10, 10, 10)))
	circ.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	circ.add_child(Iconos.new(PestanaMensajes.icono_tipo(tipo), col, 24))
	h.add_child(circ)
	var tv := Tema.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tt := String(m.get("tipo_texto", d.get("tipos", {}).get(tipo, PestanaMensajes.texto_tipo(tipo))))
	tv.add_child(Tema.linea(tt, 19, col, 800))
	tv.add_child(Tema.linea("Recibido el %s · %s" % [Tema.fecha(m.get("t", null)), Tema.hace(m.get("t", null))], 13, Tema.TEXTO2))
	h.add_child(tv)
	var ce := Tema.chip(PestanaMensajes.nombre_estado(estado), PestanaMensajes.color_estado(estado), "check" if estado == "hecho" else "")
	ce.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ce)
	cv.add_child(h)
	if String(m.get("nota", "")) != "":
		var nota := Tema.tarjeta(10, Tema.SUP2)
		nota.add_child(Tema.parrafo("Nota: " + String(m["nota"]), 13, Tema.TEXTO))
		cv.add_child(nota)
	_caja.add_child(cab)
	# ---- el mensaje entero
	var sm := Tema.seccion("Mensaje")
	var texto := String(m.get("mensaje", "")).strip_edges()
	var copiar := Boton.new("Copiar", "copiar", "texto", 30)
	copiar.tam = 13
	copiar.tocado.connect(func():
		DisplayServer.clipboard_set(texto)
		app.avisar("Mensaje copiado"))
	sm.add_child(copiar)
	_caja.add_child(sm)
	var tmsg := Tema.tarjeta(16)
	var hm := Tema.hbox(10)
	var comilla := Tema.etiqueta("“", 34, Tema.ACENTO, 800)
	comilla.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hm.add_child(comilla)
	# un parrafo por cada salto de linea (un Label con lineas en blanco las dibuja mucho mas altas)
	var cuerpo := Tema.vbox(10)
	cuerpo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for par in texto.split("
", false):
		if par.strip_edges() != "":
			var l := Tema.parrafo(par.strip_edges(), 16, Tema.TEXTO)
			l.add_theme_constant_override("line_spacing", 3)
			cuerpo.add_child(l)
	hm.add_child(cuerpo)
	tmsg.add_child(hm)
	_caja.add_child(tmsg)
	# ---- quien
	_caja.add_child(Tema.seccion("De"))
	_caja.add_child(_tarjeta_de(m.get("de", null)))
	# ---- contacto
	var contacto := String(m.get("contacto", "")).strip_edges()
	_caja.add_child(Tema.seccion("Contacto"))
	var tc := Tema.tarjeta(14)
	var hc := Tema.hbox(10)
	tc.add_child(hc)
	var ic := Iconos.new("correo", Tema.ACENTO if contacto != "" else Tema.TEXTO3, 18)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hc.add_child(ic)
	if contacto == "":
		hc.add_child(Tema.parrafo("No dejó forma de contacto: solo se le puede responder arreglándolo en el juego.", 14, Tema.TEXTO3))
	else:
		var cl := Tema.parrafo(contacto, 15, Tema.TEXTO, 600)
		cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hc.add_child(cl)
		var cc := Boton.new("Copiar", "copiar", "fantasma", 38)
		cc.tam = 13
		cc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cc.tocado.connect(func():
			DisplayServer.clipboard_set(contacto)
			app.avisar("Contacto copiado"))
		hc.add_child(cc)
	_caja.add_child(tc)
	# ---- dispositivo
	var info: Dictionary = m.get("info", {})
	_caja.add_child(Tema.seccion("Desde dónde escribió"))
	var ti := Tema.tarjeta(14)
	var vi := Tema.vbox(8)
	ti.add_child(vi)
	var ver := int(info.get("version", 0))
	vi.add_child(_dato("bajar", "Versión", "v%d" % ver if ver > 0 else "—"))
	vi.add_child(_dato("mando", "Plataforma", String(info.get("plataforma", "")) if String(info.get("plataforma", "")) != "" else "—"))
	vi.add_child(_dato("senal", "Modelo", String(info.get("modelo", "")) if String(info.get("modelo", "")) != "" else "—"))
	var mapa := String(info.get("mapa", ""))
	vi.add_child(_dato("mapa", "Mapa", PestanaReportes.texto_mapa(mapa) if mapa != "" else "En el vestíbulo"))
	_caja.add_child(ti)
	# ---- historial
	var hist: Array = m.get("historial", [])
	if not hist.is_empty():
		_caja.add_child(Tema.seccion("Historial"))
		var th := Tema.tarjeta(14)
		var vh := Tema.vbox(8)
		th.add_child(vh)
		for i in range(hist.size() - 1, -1, -1):
			var e: Dictionary = hist[i]
			var fr := Tema.hbox(10)
			var icr := Iconos.new("reloj", Tema.TEXTO3, 14)
			icr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			fr.add_child(icr)
			fr.add_child(Tema.parrafo(_texto_cambio(String(e.get("que", ""))), 13, Tema.TEXTO))
			var f := Tema.etiqueta(Tema.fecha(e.get("t", null)), 12, Tema.TEXTO3)
			f.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			fr.add_child(f)
			vh.add_child(fr)
		_caja.add_child(th)
	# ---- las acciones de abajo: los dos estados que no es ahora
	var acciones: Array = []
	match estado:
		"nuevo":
			acciones = [["leido", "secundario"], ["hecho", "primario"]]
		"leido":
			acciones = [["nuevo", "secundario"], ["hecho", "primario"]]
		_:
			acciones = [["nuevo", "secundario"], ["leido", "fantasma"]]
	for a in acciones:
		var e := String(a[0])
		var b := Boton.new({"nuevo": "Volver a nuevo", "leido": "Marcar leído", "hecho": "Marcar hecho"}[e],
			{"nuevo": "refrescar", "leido": "ojo", "hecho": "check"}[e], String(a[1]), 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if String(a[1]) == "primario":
			b.size_flags_stretch_ratio = 1.3
		b.tocado.connect(func(): cambiar_estado(e))
		_pie.add_child(b)


## "nuevo → leido · nota" con las palabras de la pantalla
static func _texto_cambio(que: String) -> String:
	for k in ["nuevo", "leido", "hecho"]:
		que = que.replace(k + " →", PestanaMensajes.nombre_estado(k).capitalize() + " →")
		que = que.replace("→ " + k, "→ " + PestanaMensajes.nombre_estado(k).capitalize())
	return que


## Quien lo mando: su tarjeta (con VER CUENTA), o "Anónimo" si escribio sin cuenta
func _tarjeta_de(de) -> PanelContainer:
	var tj := Tema.tarjeta(16)
	var v := Tema.vbox(12)
	tj.add_child(v)
	var h := Tema.hbox(14)
	v.add_child(h)
	if not (de is Dictionary):
		var circ := PanelContainer.new()
		circ.add_theme_stylebox_override("panel", Tema.caja(Tema.SUP3, 23, Color.TRANSPARENT, 0, Vector4(12, 12, 12, 12)))
		circ.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		circ.add_child(Iconos.new("usuario", Tema.TEXTO3, 22))
		h.add_child(circ)
		var tv := Tema.vbox(2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tv.add_child(Tema.linea("Anónimo", 17, Tema.TEXTO, 800))
		tv.add_child(Tema.parrafo("Escribió sin entrar con su cuenta.", 13, Tema.TEXTO3))
		h.add_child(tv)
		return tj
	var p: Dictionary = de
	h.add_child(Tema.avatar(String(p.get("nombre", "")), 50))
	var tv := Tema.vbox(3)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.add_child(Tema.linea(String(p.get("nombre", "")), 18, Tema.TEXTO, 800))
	tv.add_child(Tema.linea("@" + String(p.get("u", "")), 13, Tema.TEXTO2))
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
	tv.add_child(chips)
	h.add_child(tv)
	var n := int(d.get("del_mismo", 0))
	var bd := Tema.hbox(10)
	var linea := Tema.linea("Ha enviado %d mensaje%s" % [n, "" if n == 1 else "s"], 13, Tema.TEXTO2)
	linea.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bd.add_child(linea)
	var ver := Boton.new("Ver cuenta", "usuario", "secundario", 42)
	ver.tam = 14
	ver.disabled = not bool(p.get("existe", true))
	ver.tocado.connect(func(): ver_cuenta(String(p.get("u", ""))))
	bd.add_child(ver)
	v.add_child(bd)
	return tj


func _dato(icono: String, titulo: String, valor: String) -> Control:
	var h := Tema.hbox(10)
	var ic := Iconos.new(icono, Tema.TEXTO3, 16)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var t := Tema.etiqueta(titulo, 14, Tema.TEXTO2)
	t.custom_minimum_size.x = 84
	h.add_child(t)
	var v := Tema.linea(valor, 14, Tema.TEXTO, 600)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(v)
	return h


# ------------------------------------------------------------------ acciones
func ver_cuenta(u: String) -> void:
	if u != "":
		app.ir_a(VistaFicha.new(app, u))


## Nuevo / leido / hecho, con una nota opcional que queda en el mensaje
func cambiar_estado(estado: String) -> void:
	var titulo: String = {"leido": "Marcar como leído", "hecho": "Marcar como hecho", "nuevo": "Volver a nuevo"}[estado]
	var icono: String = {"leido": "ojo", "hecho": "check", "nuevo": "refrescar"}[estado]
	var m: Dictionary = d.get("mensaje", {})
	var de = m.get("de", null)
	var dlg: Dialogo = app.dialogo(titulo, icono, PestanaMensajes.color_estado(estado),
		"Mensaje de %s" % (String(de.get("nombre", "")) if de is Dictionary else "un anónimo"))
	dlg.cuerpo.add_child(Tema.parrafo({"leido": "Lo has leído, pero queda algo por hacer (arreglarlo, contestarle, pensarlo).",
		"hecho": "Ya está: arreglado, contestado o apuntado. Sale de lo que falta por mirar.",
		"nuevo": "Vuelve a contar como sin leer (el número rojo de la pestaña)."}[estado], 14, Tema.TEXTO2))
	dlg.cuerpo.add_child(Tema.etiqueta("Nota (opcional)", 14, Tema.TEXTO2, 600))
	var nota := Tema.campo("Ej.: arreglado en la versión 15, le escribí…")
	nota.max_length = 300
	dlg.cuerpo.add_child(nota)
	dlg.boton("Cancelar").tocado.connect(dlg.cerrar)
	var ok := dlg.boton({"leido": "Leído", "hecho": "Hecho", "nuevo": "A nuevo"}[estado],
		"primario" if estado == "hecho" else "secundario", icono)
	ok.tocado.connect(func():
		ok.cargando = true
		var bien := await enviar_estado(estado, nota.text.strip_edges())
		if is_instance_valid(ok):
			ok.cargando = false
		if bien:
			dlg.cerrar())


## Manda el cambio de estado y repinta. Devuelve si fue bien (lo usan tambien las fotos).
func enviar_estado(estado: String, nota := "") -> bool:
	var r: Dictionary = await app.api.pedir("POST", "/admin/mensaje/estado", {"id": id, "estado": estado, "nota": nota})
	if not r["ok"]:
		app.avisar(Tema.frase(String(r["error"])), false)
		return false
	if is_inside_tree():
		_poner(r["datos"])
	app.avisar({"leido": "Mensaje marcado como leído", "hecho": "Mensaje marcado como hecho", "nuevo": "Mensaje nuevo otra vez"}[estado])
	return true
