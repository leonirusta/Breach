class_name VistaActivas
extends Control
## LAS CUENTAS ACTIVAS HOY (2026-10-20, pedido: "si toco Activas hoy, ver el usuario de las que se conectaron"). La abre
## la tarjeta "Activas hoy" del RESUMEN. Las de las ultimas 24 h, de la mas reciente a la mas vieja, con la misma fila que
## JUGADORES (nombre, @usuario, ID, cuanto hace; tocarla abre la cuenta). GET /admin/cuentas?hoy=1&pagina=

var app
var inicio                  ## la vista de inicio: su _fila_cuenta pinta cada fila
var _lista: VBoxContainer
var _info: Label
var _mas: Boton
var _pagina := 0


func _init(p_app, p_inicio) -> void:
	app = p_app
	inicio = p_inicio


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
	tv.add_child(Tema.linea("Activas hoy", 20, Tema.TEXTO, 800))
	_info = Tema.linea("Cargando…", 11, Tema.TEXTO3)
	tv.add_child(_info)
	h.add_child(tv)
	var ref := Boton.new("", "refrescar", "icono", 48)
	ref.custom_minimum_size.x = 48
	ref.tocado.connect(func(): _cargar(true))
	h.add_child(ref)
	raiz.add_child(p)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.scroll_deadzone = 100000
	sc.add_to_group("desliza")
	raiz.add_child(sc)
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for lado in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + lado, 14)
	sc.add_child(m)
	var v := Tema.vbox(10)
	m.add_child(v)
	_lista = Tema.vbox(8)
	v.add_child(_lista)
	_mas = Boton.new("Cargar más", "", "fantasma", 48)
	_mas.visible = false
	_mas.tocado.connect(func():
		_pagina += 1
		_cargar(false))
	v.add_child(_mas)
	_cargar(true)


func _cargar(desde_cero: bool) -> void:
	if desde_cero:
		_pagina = 0
		for n in _lista.get_children():
			n.queue_free()
		_lista.add_child(Girador.new())
	_mas.cargando = not desde_cero
	var r: Dictionary = await app.api.pedir("GET", "/admin/cuentas?hoy=1&pagina=%d" % _pagina)
	if not is_inside_tree():
		return
	_mas.cargando = false
	if desde_cero:
		for n in _lista.get_children():
			n.queue_free()
	if not r["ok"]:
		_info.text = "No se pudo cargar"
		_lista.add_child(Tema.vacio("alerta", Tema.frase(String(r["error"])), "Toca actualizar arriba para reintentar."))
		return
	var d: Dictionary = r["datos"]
	var total := int(d.get("total", 0))
	_info.text = "%s cuenta%s en las últimas 24 h" % [Tema.numero(total), "" if total == 1 else "s"]
	for c in d.get("cuentas", []):
		_lista.add_child(inicio._fila_cuenta(c))
	if total == 0:
		_lista.add_child(Tema.vacio("reloj", "Nadie hoy", "Ninguna cuenta se ha conectado en las últimas 24 horas."))
	_mas.visible = int(d.get("pagina", 0)) < int(d.get("paginas", 1)) - 1
