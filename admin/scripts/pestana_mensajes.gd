class_name PestanaMensajes
extends VBoxContainer
## LOS MENSAJES DE LOS JUGADORES (pestaña del inicio, 2026-10-01). Los manda el juego con el boton HABLAR CON NOSOTROS
## (ideas, errores, algo que reportar o solo hablar; con su cuenta o sin ella) y los guarda servidor/contacto.js.
##   arriba     el ESTADO (todos, nuevos, leidos, hechos, con cuantos hay de cada) y el TIPO
##   la lista   cada mensaje: el tipo con su color, cuando, quien (o "Anónimo"), el principio del texto y el estado
##              (los NUEVOS con la raya amarilla a la izquierda). Tocar uno abre el mensaje entero (vista_mensaje.gd)
## GET /admin/mensajes?estado=&tipo=&pagina=

signal pendientes(n: int)          ## los mensajes NUEVOS (el numero rojo de la pestaña)

## Los tipos: clave -> [texto corto, icono, color]. Las mismas claves que TIPOS en servidor/contacto.js; el texto largo
## lo manda el servidor (`tipos`).
const TIPOS := {
	"sugerencia": ["Idea", "estrella", Tema.EXP],
	"error": ["Error", "alerta", Tema.PELIGRO],
	"reporte": ["Reporte", "bandera", Tema.AVISO],
	"otro": ["Otro", "correo", Tema.CUBOS],
}
const PLURALES := {"": "Todos los tipos", "sugerencia": "Ideas", "error": "Errores", "reporte": "Reportes", "otro": "Otros"}
const ESTADOS := [["", "Todos"], ["nuevo", "Nuevos"], ["leido", "Leídos"], ["hecho", "Hechos"]]

var app
var cargada := false
var listo := false                 ## llego la ultima peticion (las pruebas esperan a esto)
var datos := {}                    ## lo ultimo que dio el servidor
var _info: Label
var _lista: VBoxContainer
var _mas: Boton
var _b_estado := {}
var _b_tipo := {}
var _estado := ""
var _tipo := ""
var _pagina := 0
var _pedido := 0


func _init(p_app) -> void:
	app = p_app
	add_theme_constant_override("separation", 12)


static func color_estado(e: String) -> Color:
	return {"nuevo": Tema.ACENTO, "leido": Tema.TEXTO2, "hecho": Tema.OK}.get(e, Tema.TEXTO2)


static func nombre_estado(e: String) -> String:
	return {"nuevo": "NUEVO", "leido": "LEÍDO", "hecho": "HECHO"}.get(e, e.to_upper())


static func color_tipo(t: String) -> Color:
	return TIPOS.get(t, TIPOS["otro"])[2]


static func icono_tipo(t: String) -> String:
	return String(TIPOS.get(t, TIPOS["otro"])[1])


static func texto_tipo(t: String) -> String:
	return String(TIPOS.get(t, [t.capitalize()])[0])


## "Android · v14" (lo que se sabe de donde escribio)
static func texto_app(plataforma: String, version) -> String:
	var partes: Array = []
	if plataforma != "":
		partes.append(plataforma)
	if int(version if version != null else 0) > 0:
		partes.append("v%d" % int(version))
	return " · ".join(partes)


func _ready() -> void:
	# el estado, con cuantos hay de cada (los numeros llegan con la lista)
	var seg := HFlowContainer.new()
	seg.add_theme_constant_override("h_separation", 8)
	seg.add_theme_constant_override("v_separation", 8)
	for o in ESTADOS:
		var b := Boton.new(String(o[1]), "", "sel" if o[0] == _estado else "fantasma", 38)
		b.tam = 14
		b.texto = b.texto            # se vuelve a medir con su tamaño de letra
		var k := String(o[0])
		b.tocado.connect(func(): ver_estado(k))
		_b_estado[k] = b
		seg.add_child(b)
	add_child(seg)
	# el tipo
	var tipos := HFlowContainer.new()
	tipos.add_theme_constant_override("h_separation", 8)
	tipos.add_theme_constant_override("v_separation", 8)
	for k in [""] + TIPOS.keys():
		var b := Boton.new(String(PLURALES.get(k, k)), "" if k == "" else icono_tipo(k), "sel" if k == _tipo else "fantasma", 36)
		b.tam = 13
		b.texto = b.texto
		if k != "":
			b.color_icono = color_tipo(k)
		var kk := String(k)
		b.tocado.connect(func(): ver_tipo(kk))
		_b_tipo[kk] = b
		tipos.add_child(b)
	add_child(tipos)
	_info = Tema.linea("", 14, Tema.TEXTO2, 600)
	add_child(_info)
	_lista = Tema.vbox(10)
	add_child(_lista)
	_mas = Boton.new("Cargar más", "", "fantasma", 48)
	_mas.visible = false
	_mas.tocado.connect(func():
		_pagina += 1
		cargar(false))
	add_child(_mas)


# ------------------------------------------------------------------ filtros
func ver_estado(k: String) -> void:
	_estado = k
	for k2 in _b_estado:
		_b_estado[k2].estilo = "sel" if k2 == k else "fantasma"
	cargar()


func ver_tipo(k: String) -> void:
	_tipo = k
	for k2 in _b_tipo:
		_b_tipo[k2].estilo = "sel" if k2 == k else "fantasma"
	cargar()


## Los numeros de cada estado en sus botones ("Nuevos 3")
func _poner_cuentas(cuentas: Dictionary, total_todos: int) -> void:
	for o in ESTADOS:
		var k := String(o[0])
		var n := total_todos if k == "" else int(cuentas.get(k, 0))
		_b_estado[k].texto = "%s  %d" % [String(o[1]), n]


# ------------------------------------------------------------------ la lista
func cargar(desde_cero := true) -> void:
	cargada = true
	listo = false
	_pedido += 1
	var mio := _pedido
	if desde_cero:
		_pagina = 0
		for n in _lista.get_children():
			n.queue_free()
		_lista.add_child(Girador.new())
		_info.text = "Cargando…"
	_mas.cargando = not desde_cero
	var ruta := "/admin/mensajes?estado=%s&tipo=%s&pagina=%d" % [_estado, _tipo, _pagina]
	var r: Dictionary = await app.api.pedir("GET", ruta)
	if mio != _pedido or not is_inside_tree():
		return
	_mas.cargando = false
	if desde_cero:
		for n in _lista.get_children():
			n.queue_free()
	if not r["ok"]:
		_info.text = "No se pudo cargar"
		_lista.add_child(Tema.vacio("alerta", Tema.frase(String(r["error"])), "Toca actualizar arriba para reintentar."))
		listo = true
		return
	datos = r["datos"]
	var cuentas: Dictionary = datos.get("cuentas", {})
	pendientes.emit(int(cuentas.get("nuevo", 0)))
	_poner_cuentas(cuentas, int(datos.get("total_todos", 0)))
	var total := int(datos.get("total", 0))
	_info.text = "%s mensaje%s" % [Tema.numero(total), "" if total == 1 else "s"]
	if int(cuentas.get("nuevo", 0)) > 0 and _estado != "nuevo":
		_info.text += "  ·  %d sin leer" % int(cuentas["nuevo"])
	for m in datos.get("mensajes", []):
		_lista.add_child(fila_mensaje(m, abrir))
	if total == 0:
		var hay_filtro := _estado != "" or _tipo != ""
		_lista.add_child(Tema.vacio("correo", "No hay mensajes" + (" con ese filtro" if hay_filtro else ""),
			"Llegan desde el botón HABLAR CON NOSOTROS del juego." if not hay_filtro else "Prueba con otro estado o tipo."))
	_mas.visible = int(datos.get("pagina", 0)) < int(datos.get("paginas", 1)) - 1
	listo = true


func abrir(id: String) -> void:
	app.ir_a(VistaMensaje.new(app, id, self))


## Una fila de la lista: el tipo y cuando; quien; el principio del mensaje; el estado y desde donde escribio
static func fila_mensaje(m: Dictionary, al_tocar: Callable) -> Control:
	var tj := Tema.tarjeta(14)
	var v := Tema.vbox(10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tj.add_child(v)
	var estado := String(m.get("estado", ""))
	var tipo := String(m.get("tipo", "otro"))
	var col := color_tipo(tipo)
	# arriba: el tipo con su icono, el estado y cuando
	var arriba := Tema.hbox(10)
	arriba.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var circ := PanelContainer.new()
	circ.add_theme_stylebox_override("panel", Tema.caja(Color(col, 0.16), 10, Color.TRANSPARENT, 0, Vector4(7, 7, 7, 7)))
	circ.mouse_filter = Control.MOUSE_FILTER_IGNORE
	circ.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	circ.add_child(Iconos.new(icono_tipo(tipo), col, 16))
	arriba.add_child(circ)
	var tl := Tema.etiqueta(texto_tipo(tipo).to_upper(), 13, col, 800)
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arriba.add_child(tl)
	if estado != "nuevo":
		var ch := Tema.chip(nombre_estado(estado), color_estado(estado), "check" if estado == "hecho" else "", false)
		ch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		arriba.add_child(ch)
	else:
		var ch := Tema.chip("NUEVO", Tema.ACENTO, "", true)
		ch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		arriba.add_child(ch)
	var cuando := Tema.linea(Tema.hace(m.get("t", null)), 12, Tema.TEXTO3)
	cuando.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cuando.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arriba.add_child(cuando)
	v.add_child(arriba)
	# el mensaje: lo primero que se lee
	var msg := String(m.get("mensaje", "")).strip_edges().replace("\n", " ")
	if msg.length() >= 160:
		msg += "…"          # la lista trae solo el principio (160 letras)
	var p := Tema.parrafo(msg, 15, Tema.TEXTO if estado == "nuevo" else Tema.TEXTO2, 500 if estado == "nuevo" else 400)
	p.max_lines_visible = 3
	p.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(p)
	# abajo: quien y desde donde
	var pie := Tema.hbox(8)
	pie.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var de = m.get("de", null)
	if de is Dictionary:
		pie.add_child(Tema.avatar(String(de.get("nombre", "")), 24))
		var nl := Tema.etiqueta(String(de.get("nombre", "")), 13, Tema.TEXTO2, 600)
		nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pie.add_child(nl)
		var nv := Tema.etiqueta("NV %d" % int(de.get("nivel", 1)), 12, Tema.TEXTO3)
		nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pie.add_child(nv)
	else:
		var ia := Iconos.new("usuario", Tema.TEXTO3, 16)
		ia.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pie.add_child(ia)
		var al := Tema.etiqueta("Anónimo", 13, Tema.TEXTO3, 600)
		al.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pie.add_child(al)
	var app_t := texto_app(String(m.get("plataforma", "")), m.get("version", 0))
	var dl := Tema.linea(app_t, 12, Tema.TEXTO3)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pie.add_child(dl)
	var ir := Iconos.new("flecha", Tema.TEXTO3, 12)
	ir.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pie.add_child(ir)
	v.add_child(pie)
	if estado == "nuevo":
		# una raya amarilla a la izquierda: lo que falta por leer se ve de lejos
		tj.add_theme_stylebox_override("panel", _caja_nuevo())
	var id := String(m.get("id", ""))
	PestanaReportes.tocable(tj, func(): al_tocar.call(id))
	return tj


static func _caja_nuevo() -> StyleBoxFlat:
	var s := Tema.caja(Tema.SUP.lerp(Tema.ACENTO, 0.03), 16, Color.TRANSPARENT, 0, Vector4(18, 14, 14, 14))
	s.border_color = Color(Tema.ACENTO, 0.85)
	s.border_width_left = 4
	return s
