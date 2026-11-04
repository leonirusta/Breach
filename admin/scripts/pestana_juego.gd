class_name PestanaJuego
extends VBoxContainer
## JUEGO (pestaña del inicio, 2026-09-30, pedido: "que la aplicacion admin pueda modificar la probabilidad de que te
## toque comun, especial, etc.; agregar destacados con precios en la tienda; modificar todo el juego; la cantidad de
## cartas que te dan los cofres"). Lo que el juego deja ajustar desde el SERVIDOR (servidor/index.js, "LOS AJUSTES DEL
## JUEGO", que valida cada uno con validarJuego y validarDestacados):
##   PROBABILIDADES  cofres_sube: lo que SUBE un cofre en cada toque, y la tabla de donde ACABA (se calcula aqui, en vivo)
##   PREMIOS         cofres_premios: por rareza, las opciones con su peso (cartas y copias, oro, cubos, diamantes, articulo)
##   MEJORAS         cartas_copias, cartas_cubos y cartas_oro: lo que cuesta subir una carta de nivel
##   CARTAS          cartas_valores: lo que da cada carta a nivel 1 y lo que suma cada nivel
##   PERSONAJES      personajes_coste: cubos y oro de cada nivel
##   ORO             oro_partida: el % del oro de cada partida
##   PASE            pase_niveles: los 20 niveles, fila gratis y fila premium (juego_pase.gd)
##   DESTACADOS      la lista de la tienda con su precio y su moneda, y destacados_diarios (juego_destacados.gd)
## GET /admin/juego da {fabrica, actual (solo lo que cambio el panel), efectivo, destacados, articulos}. Cada seccion
## edita una COPIA de lo efectivo; GUARDAR manda solo sus claves que cambian (POST /admin/juego {clave, valor}, o POST
## /admin/destacados {lista}) y DE FABRICA manda valor null (y la lista vacia). Se ve una seccion a la vez (los botones
## de arriba); cada boton lleva un punto: amarillo si el panel la cambio (CAMBIADO), naranja si hay cambios sin guardar.

const SECCIONES := [
	{"id": "sube", "boton": "Probabilidades", "titulo": "Cofres · probabilidades", "icono": "cofre", "claves": ["cofres_sube"],
		"texto": "Al abrir un cofre se toca 4 veces, y en cada toque puede subir de rareza. Aquí se ajusta cuánto sube."},
	{"id": "premios", "boton": "Premios", "titulo": "Cofres · premios", "icono": "regalo", "claves": ["cofres_premios"], "largo": true,
		"texto": "Lo que da el cofre según la rareza en la que acaba: una de estas opciones, al azar según su peso."},
	{"id": "mejoras", "boton": "Mejoras", "titulo": "Cartas · mejoras", "icono": "nivel", "claves": ["cartas_copias", "cartas_cubos", "cartas_oro"],
		"texto": "Lo que cuesta subir una carta de nivel: copias de esa carta, cubos de fuerza y oro (nunca diamantes). La primera copia la da a nivel 1."},
	{"id": "valores", "boton": "Cartas", "titulo": "Cartas · lo que dan", "icono": "carta", "claves": ["cartas_valores"], "largo": true,
		"texto": "Lo que da cada carta a nivel 1 y lo que suma cada nivel más (hasta el 10)."},
	{"id": "personajes", "boton": "Personajes", "titulo": "Personajes · fuerza", "icono": "usuario", "claves": ["personajes_coste"],
		"texto": "Lo que cuesta cada nivel de fuerza de un personaje, en cubos de fuerza y oro."},
	{"id": "oro", "boton": "Oro", "titulo": "Oro por partida", "icono": "oro", "claves": ["oro_partida"],
		"texto": "El juego calcula el oro de cada partida (modo, bajas, victoria...) y de eso se da este porcentaje."},
	{"id": "pase", "boton": "Pase", "titulo": "Pase de batalla", "icono": "estrella", "claves": ["pase_config", "pase_niveles"], "largo": true,
		"texto": "Encenderlo o apagarlo, la temporada y lo que da cada nivel. GRATIS lo reclama cualquiera al llegar; PRÉMIUM, quien compró el pase de esa temporada."},
	{"id": "destacados", "boton": "Destacados", "titulo": "Destacados de la tienda", "icono": "tienda",
		"claves": ["destacados", "destacados_diarios"], "largo": true,
		"texto": "Artículos que salen primero en DESTACADAS, al precio y en la moneda que pongas aquí."},
]
## Lo que se puede elegir en los selectores de articulos (el pase premium no: ni en cofres ni en destacados)
const TIPOS_VENTA := ["arma", "pintura", "personaje", "mazo", "habilidad"]

var app
var cargada := false               ## ya se pidio una vez
var datos := {}                    ## lo ultimo de GET /admin/juego (se va poniendo al dia con lo que se guarda)
var _arts := {}                    ## clave -> {clave, tipo, nombre, precio}
var _secs: Array = []              ## una por SECCIONES
var _sel := 0
var _info: Label
var _barra: HFlowContainer
var _caja: VBoxContainer
var _pedido := 0


func _init(p_app) -> void:
	app = p_app
	add_theme_constant_override("separation", 12)


func _ready() -> void:
	_barra = HFlowContainer.new()
	_barra.add_theme_constant_override("h_separation", 8)
	_barra.add_theme_constant_override("v_separation", 8)
	add_child(_barra)
	_info = Tema.linea("", 13, Tema.TEXTO2, 600)
	add_child(_info)
	_caja = Tema.vbox(12)
	add_child(_caja)


# ------------------------------------------------------------------ cargar
func cargar() -> void:
	cargada = true
	_pedido += 1
	var mio := _pedido
	for n in _caja.get_children():
		n.queue_free()
	for n in _barra.get_children():
		n.queue_free()
	_soltar()
	_caja.add_child(Girador.new())
	_info.text = "Cargando…"
	var r: Dictionary = await app.api.pedir("GET", "/admin/juego")
	if mio != _pedido or not is_inside_tree():
		return
	for n in _caja.get_children():
		n.queue_free()
	if not r["ok"]:
		datos = {}
		_info.text = "No se pudo cargar"
		_caja.add_child(Tema.vacio("alerta", Tema.frase(String(r["error"])), "Toca actualizar arriba para reintentar."))
		return
	datos = r["datos"]
	for k in ["fabrica", "actual", "efectivo"]:
		if not datos.get(k) is Dictionary:
			datos[k] = {}
	if not datos.get("destacados") is Array:
		datos["destacados"] = []
	_arts.clear()
	for a in datos.get("articulos", []):
		_arts[String(a.get("clave", ""))] = a
	# el selector de articulos (Formularios) usa la misma lista
	if Formularios.catalogo.is_empty():
		var lista: Array = (datos.get("articulos", []) as Array).duplicate(true)
		var orden := {"arma": 0, "pintura": 1, "personaje": 2, "mazo": 3, "habilidad": 4}
		lista.sort_custom(func(a, b):
			var ta: int = orden.get(String(a.get("tipo", "")), 9)
			var tb: int = orden.get(String(b.get("tipo", "")), 9)
			if ta != tb:
				return ta < tb
			return String(a.get("nombre", "")).naturalnocasecmp_to(String(b.get("nombre", ""))) < 0)
		Formularios.catalogo = lista
	_armar()


## Cada seccion guarda su `pintar`, que la nombra a ella: se vacian a mano para romper el ciclo y que se liberen
func _soltar() -> void:
	for s in _secs:
		(s as Dictionary).clear()
	_secs.clear()


func _exit_tree() -> void:
	_soltar()


## Actualizar (arriba): si hay cambios sin guardar, se pregunta antes de perderlos
func refrescar() -> void:
	var sin := 0
	for s in _secs:
		if _sin_guardar(s):
			sin += 1
	if sin == 0:
		cargar()
		return
	var d: Dialogo = app.dialogo("Cambios sin guardar", "alerta", Tema.AVISO)
	d.cuerpo.add_child(Tema.parrafo("Hay %d sección%s con cambios sin guardar. Si recargas, se pierden." % [sin, "" if sin == 1 else "es"], 15))
	d.boton("Cancelar").tocado.connect(d.cerrar)
	d.boton("Recargar", "peligro", "refrescar").tocado.connect(func():
		d.cerrar()
		cargar())


func listo() -> bool:
	return not datos.is_empty() and not _secs.is_empty()


func _armar() -> void:
	for i in SECCIONES.size():
		var s := _seccion(SECCIONES[i])
		_secs.append(s)
		var b := _BotonSeccion.new(String(SECCIONES[i]["boton"]))
		b.tocado.connect(func(): ver_seccion(i))
		_barra.add_child(b)
		s["boton"] = b
		_caja.add_child(s["tarjeta"])
		s["pintar"].call()
		tocado(s)
	var nota := Tema.parrafo("Lo guardado lo usa el servidor al momento (cofres, pase, oro); el juego se entera en su siguiente latido y al abrir la tienda.", 12, Tema.TEXTO3)
	_caja.add_child(nota)
	ver_seccion(_sel)


func ver_seccion(i: int) -> void:
	_sel = clampi(i, 0, SECCIONES.size() - 1)
	for k in _secs.size():
		_secs[k]["tarjeta"].visible = k == _sel
		_secs[k]["boton"].estilo = "sel" if k == _sel else "fantasma"


## La seccion por su id (las fotos y la prueba)
func seccion(id: String) -> Dictionary:
	for s in _secs:
		if String(s["id"]) == id:
			return s
	return {}


func indice(id: String) -> int:
	for i in SECCIONES.size():
		if String(SECCIONES[i]["id"]) == id:
			return i
	return 0


func nombre_articulo(clave: String) -> String:
	return String(_arts.get(clave, {}).get("nombre", clave))


func tipo_articulo(clave: String) -> String:
	var t := String(_arts.get(clave, {}).get("tipo", ""))
	return t if t != "" else Imagenes.tipo_de(clave)


func precio_articulo(clave: String) -> int:
	return int(_arts.get(clave, {}).get("precio", 0))


# ------------------------------------------------------------------ una seccion: la tarjeta
func _seccion(def: Dictionary) -> Dictionary:
	var s := {"id": def["id"], "def": def, "claves": def["claves"], "estado": {}, "guardar": [], "fabrica": [], "ocupada": false}
	for k in s["claves"]:
		s["estado"][k] = JuegoPiezas.copia(_base(k))
	var tj := Tema.tarjeta(16)
	var v := Tema.vbox(14)
	tj.add_child(v)
	var cab := Tema.hbox(12)
	cab.add_child(JuegoPiezas.circulo(String(def["icono"]), Tema.ACENTO, 20))
	var tv := Tema.vbox(6)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(Tema.linea(String(def["titulo"]), 19, Tema.TEXTO, 800))
	var chips := Tema.hbox(6)
	s["chip_cambiado"] = Tema.chip("CAMBIADO", Tema.ACENTO, "lapiz")
	s["chip_fabrica"] = Tema.chip("DE FÁBRICA", Tema.TEXTO3, "check", false)
	s["chip_sin"] = Tema.chip("SIN GUARDAR", Tema.AVISO, "alerta")
	for k in ["chip_cambiado", "chip_fabrica", "chip_sin"]:
		s[k].size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chips.add_child(s[k])
	chips.add_child(Tema.expandir())
	var desc := Boton.new("Descartar", "", "texto", 28)
	desc.tam = 13
	desc.tocado.connect(func(): _rehacer(s))
	s["descartar"] = desc
	chips.add_child(desc)
	tv.add_child(chips)
	cab.add_child(tv)
	v.add_child(cab)
	v.add_child(Tema.parrafo(String(def["texto"]), 13, Tema.TEXTO2))
	if def.get("largo", false):
		v.add_child(_acciones(s))
	var cuerpo := Tema.vbox(14)
	v.add_child(cuerpo)
	s["cuerpo"] = cuerpo
	v.add_child(Tema.separador())
	v.add_child(_acciones(s))
	s["tarjeta"] = tj
	match String(def["id"]):
		"sube":
			s["pintar"] = func(): _pintar_sube(s)
		"premios":
			s["rareza"] = 0
			s["pintar"] = func(): _pintar_premios(s)
		"mejoras":
			s["pintar"] = func(): _pintar_mejoras(s)
		"valores":
			s["pintar"] = func(): _pintar_valores(s)
		"personajes":
			s["pintar"] = func(): _pintar_personajes(s)
		"oro":
			s["pintar"] = func(): _pintar_oro(s)
		"pase":
			s["pintar"] = func(): JuegoPase.pintar(self, s)
		"destacados":
			s["pintar"] = func(): JuegoDestacados.pintar(self, s)
	return s


## [De fabrica] [Guardar]
func _acciones(s: Dictionary) -> HBoxContainer:
	var h := Tema.hbox(10)
	var f := Boton.new("De fábrica", "refrescar", "fantasma", 50)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	f.custom_minimum_size.x = 0
	f.tam = 15
	f.tocado.connect(func(): de_fabrica(s))
	h.add_child(f)
	var g := Boton.new("Guardar", "check", "primario", 50)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.custom_minimum_size.x = 0
	g.tam = 15
	g.tocado.connect(func(): guardar(s))
	h.add_child(g)
	s["fabrica"].append(f)
	s["guardar"].append(g)
	return h


## Vacia el cuerpo de una seccion y lo devuelve (para volver a pintarlo)
func vaciar(s: Dictionary) -> VBoxContainer:
	var c: VBoxContainer = s["cuerpo"]
	for n in c.get_children():
		c.remove_child(n)
		n.queue_free()
	return c


## Un subtitulo dentro de una tarjeta (MAYUSCULAS, gris)
static func subtitulo(texto: String) -> Label:
	return Tema.etiqueta(texto.to_upper(), 12, Tema.TEXTO3, 700)


# ------------------------------------------------------------------ estado de una seccion
## Si el servidor aun no trae una clave nueva (uno sin desplegar), la de fabrica de aqui: sin ella la seccion se rompia
const FABRICA_LOCAL := {"cartas_cubos": [0, 1, 1, 2, 3, 4, 6, 8, 12, 16]}


func _base(k: String):
	if k == "destacados":
		return datos.get("destacados", [])
	return datos["efectivo"].get(k, datos["fabrica"].get(k, FABRICA_LOCAL.get(k)))


func _en_actual(k: String) -> bool:
	if k == "destacados":
		return not (datos.get("destacados", []) as Array).is_empty()
	return (datos["actual"] as Dictionary).has(k) and datos["actual"][k] != null


func _cambiado(s: Dictionary) -> bool:
	for k in s["claves"]:
		if _en_actual(k):
			return true
	return false


func _sin_guardar(s: Dictionary) -> bool:
	for k in s["claves"]:
		if not JuegoPiezas.igual(s["estado"][k], _base(k)):
			return true
	return false


## Tras cada cambio: las pastillas, los botones y el punto de la seccion
func tocado(s: Dictionary) -> void:
	var sg := _sin_guardar(s)
	var cam := _cambiado(s)
	s["chip_cambiado"].visible = cam
	s["chip_fabrica"].visible = not cam
	s["chip_sin"].visible = sg
	s["descartar"].visible = sg
	if not s["ocupada"]:
		for b in s["guardar"]:
			b.disabled = not sg
		for b in s["fabrica"]:
			b.disabled = not (cam or sg)
	if s.has("boton"):
		s["boton"].punto = Tema.AVISO if sg else (Tema.ACENTO if cam else Color.TRANSPARENT)
	_pintar_info()


func _pintar_info() -> void:
	var cam := 0
	var sin := 0
	for s in _secs:
		if _cambiado(s):
			cam += 1
		if _sin_guardar(s):
			sin += 1
	var t := "Todo como viene de fábrica" if cam == 0 else "%d sección%s cambiada%s por el panel" % [cam, "" if cam == 1 else "es", "" if cam == 1 else "s"]
	if sin > 0:
		t += "  ·  %d sin guardar" % sin
	_info.text = t
	_info.add_theme_color_override("font_color", Tema.AVISO if sin > 0 else Tema.TEXTO2)


## Vuelve a lo que hay en el servidor (descartar, o tras guardar)
func _rehacer(s: Dictionary) -> void:
	for k in s["claves"]:
		s["estado"][k] = JuegoPiezas.copia(_base(k))
	s["pintar"].call()
	tocado(s)


## Para las fotos y la prueba: pone un valor en una seccion como si se hubiera editado a mano
func editar_valor(id: String, clave: String, valor) -> void:
	var s := seccion(id)
	if s.is_empty():
		return
	s["estado"][clave] = JuegoPiezas.copia(valor)
	s["pintar"].call()
	tocado(s)


func _ocupada(s: Dictionary, si: bool) -> void:
	s["ocupada"] = si
	for b in s["guardar"]:
		b.cargando = si
	for b in s["fabrica"]:
		b.disabled = si
	if not si:
		tocado(s)


# ------------------------------------------------------------------ guardar y de fabrica
## Manda una clave al servidor y pone al dia `datos`. `valor` null = la de fabrica (destacados: la lista vacia).
func _mandar(k: String, valor) -> Dictionary:
	if k == "destacados":
		var rd: Dictionary = await app.api.pedir("POST", "/admin/destacados", {"lista": valor if valor != null else []})
		if rd["ok"]:
			datos["destacados"] = rd["datos"].get("destacados", valor if valor != null else [])
		return rd
	var r: Dictionary = await app.api.pedir("POST", "/admin/juego", {"clave": k, "valor": valor})
	if r["ok"]:
		var nuevo = r["datos"].get("valor", null)
		if nuevo == null:
			datos["actual"].erase(k)
			datos["efectivo"][k] = JuegoPiezas.copia(datos["fabrica"].get(k))
		else:
			datos["actual"][k] = JuegoPiezas.copia(nuevo)
			datos["efectivo"][k] = JuegoPiezas.copia(nuevo)
		datos["v"] = r["datos"].get("v", datos.get("v", 0))
	return r


## GUARDAR: solo las claves de la seccion que cambian. Devuelve si fue bien (la prueba lo mira).
func guardar(s: Dictionary) -> bool:
	if s["ocupada"]:
		return false
	var err := _validar(s)
	if err != "":
		app.avisar(err, false)
		return false
	var cambios: Array = []
	for k in s["claves"]:
		if not JuegoPiezas.igual(s["estado"][k], _base(k)):
			cambios.append(k)
	if cambios.is_empty():
		return true
	_ocupada(s, true)
	for k in cambios:
		var r: Dictionary = await _mandar(k, s["estado"][k])
		if not is_inside_tree() or s.is_empty():          # (o se recargo la pestaña mientras tanto)
			return false
		if not r["ok"]:
			_ocupada(s, false)
			app.avisar(Tema.frase(String(r["error"])), false)
			return false
	s["ocupada"] = false
	for b in s["guardar"]:
		b.cargando = false
	_rehacer(s)
	app.avisar("Guardado: " + String(s["def"]["titulo"]).to_lower())
	return true


## DE FABRICA: pregunta y quita lo que puso el panel en la seccion (si solo hay cambios sin guardar, los descarta)
func de_fabrica(s: Dictionary) -> void:
	var en_srv: Array = []
	for k in s["claves"]:
		if _en_actual(k):
			en_srv.append(k)
	var sg := _sin_guardar(s)
	if en_srv.is_empty() and not sg:
		return
	var d: Dialogo = app.dialogo("Volver a lo de fábrica", "refrescar", Tema.PELIGRO, String(s["def"]["titulo"]))
	var texto := ""
	if en_srv.is_empty():
		texto = "Esta sección ya está como viene de fábrica. Se descartan los cambios sin guardar."
	else:
		texto = "Se borra lo que cambió el panel en esta sección y el juego vuelve a usar sus valores de fábrica."
		if "destacados" in en_srv:
			var n := (datos.get("destacados", []) as Array).size()
			texto += " Se quita%s %s destacado%s de la tienda." % ["n" if n != 1 else "", "el" if n == 1 else "los %d" % n, "" if n == 1 else "s"]
		if sg:
			texto += " Los cambios sin guardar también se pierden."
	d.cuerpo.add_child(Tema.parrafo(texto, 15))
	d.boton("Cancelar").tocado.connect(d.cerrar)
	d.boton("De fábrica", "peligro", "refrescar").tocado.connect(func():
		d.cerrar()
		if en_srv.is_empty():
			_rehacer(s)
			app.avisar("Cambios descartados")
		else:
			restaurar(s))


## Lo que hace DE FABRICA en el servidor (sin preguntar). Devuelve si fue bien.
func restaurar(s: Dictionary) -> bool:
	if s["ocupada"]:
		return false
	_ocupada(s, true)
	for k in s["claves"]:
		if not _en_actual(k):
			continue
		var r: Dictionary = await _mandar(k, null)
		if not is_inside_tree() or s.is_empty():          # (o se recargo la pestaña mientras tanto)
			return false
		if not r["ok"]:
			_ocupada(s, false)
			app.avisar(Tema.frase(String(r["error"])), false)
			return false
	s["ocupada"] = false
	for b in s["guardar"]:
		b.cargando = false
	_rehacer(s)
	app.avisar(String(s["def"]["titulo"]) + ": de fábrica")
	return true


## Lo que se puede comprobar aqui antes de mandarlo ("" = bien). El servidor vuelve a validarlo todo.
func _validar(s: Dictionary) -> String:
	var e: Dictionary = s["estado"]
	match String(s["id"]):
		"premios":
			var todos: Array = e["cofres_premios"]
			for r in todos.size():
				var ops: Array = todos[r]
				var hay_peso := false
				for i in ops.size():
					var o: Dictionary = ops[i]
					var donde := "Cofre %s, opción %d: " % [JuegoPiezas.COFRES_FRASE[r].to_lower(), i + 1]
					var w := int(o.get("w", -1))
					if w < 0 or w > 1000:
						return donde + "el peso va de 0 a 1000"
					hay_peso = hay_peso or w > 0
					var t := String(o.get("t", ""))
					if t == "articulo":
						if (o.get("pool", []) as Array).is_empty():
							return donde + "elige al menos un artículo"
					elif int(o.get("min", -1)) < 0 or int(o.get("max", -1)) < int(o.get("min", 0)):
						return donde + "las cantidades van de menor a mayor"
					if o.has("si_no"):
						var sn: Dictionary = o["si_no"]
						if int(sn.get("min", -1)) < 0 or int(sn.get("max", -1)) < int(sn.get("min", 0)):
							return donde + "lo que da si no quedan: de menor a mayor"
				if not hay_peso:
					return "Cofre %s: alguna opción tiene que tener peso" % JuegoPiezas.COFRES_FRASE[r].to_lower()
		"mejoras":
			for k in ["cartas_copias", "cartas_cubos", "cartas_oro"]:
				for n in range(1, (e[k] as Array).size()):
					if int(e[k][n]) < 0:
						return "Nivel %d → %d: falta un número" % [n, n + 1]
		"personajes":
			for k in e["personajes_coste"]:
				var x: Array = e["personajes_coste"][k]
				if int(x[0]) < 0 or int(x[1]) < 0:
					return "Nivel %s: faltan los cubos o el oro" % k
		"oro":
			var f := float(e["oro_partida"])
			if f < 0.0 or f > 10.0:
				return "El oro por partida va de 0 % a 1.000 %"
		"valores":
			for id in e["cartas_valores"]:
				var x: Dictionary = e["cartas_valores"][id]
				for c in ["base", "paso"]:
					if float(x.get(c, -1)) < 0.0 or float(x.get(c, -1)) > 100.0:
						return JuegoPiezas.nombre_carta(String(id)) + ": valor fuera de rango"
		"pase":
			var ec := JuegoPase.validar_config(e.get("pase_config", {}))
			return ec if ec != "" else JuegoPase.validar(e["pase_niveles"])
		"destacados":
			return JuegoDestacados.validar(self, e["destacados"])
	return ""


# ------------------------------------------------------------------ COFRES · PROBABILIDADES
func _pintar_sube(s: Dictionary) -> void:
	var c := vaciar(s)
	var sube: Array = s["estado"]["cofres_sube"]
	var fab: Array = datos["fabrica"].get("cofres_sube", [])
	var arriba := Tema.hbox(8)
	var st := subtitulo("Dónde acaba el cofre")
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arriba.add_child(st)
	arriba.add_child(Tema.chip("TRAS %d TOQUES" % JuegoPiezas.TOQUES, Tema.TEXTO2, "cofre", false))
	c.add_child(arriba)
	var tabla := _TablaCofres.new()
	tabla.sube = sube
	tabla.filas = _filas_tabla()
	tabla.medir()
	c.add_child(tabla)
	c.add_child(Tema.parrafo("Cada fila es un cofre que empieza en esa rareza (los que da el pase); cada columna, la probabilidad de que acabe ahí.", 12, Tema.TEXTO3))
	c.add_child(Tema.separador())
	c.add_child(subtitulo("Probabilidad de subir en cada toque"))
	for r in 5:
		var fila := Tema.vbox(2)
		var h := Tema.hbox(6)
		var a := JuegoPiezas.chip_rareza(r, true)
		a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(a)
		var fl := Iconos.new("flecha", Tema.TEXTO3, 12)
		fl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(fl)
		var b := JuegoPiezas.chip_rareza(r + 1, true)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(b)
		h.add_child(Tema.expandir())
		var campo := JuegoPiezas.campo_decimal(JuegoPiezas.num(float(sube[r]) * 100.0, 1), 84)
		h.add_child(campo)
		var u := Tema.etiqueta("%", 16, Tema.TEXTO2, 700)
		u.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(u)
		fila.add_child(h)
		var d := JuegoPiezas.Deslizador.new(float(sube[r]), JuegoPiezas.color_rareza(r + 1))
		d.marca = float(fab[r]) if r < fab.size() else -1.0
		fila.add_child(d)
		var nota := Tema.etiqueta("", 12, Tema.TEXTO3, 600)
		nota.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		fila.add_child(nota)
		var pie := func():
			var f := float(fab[r]) if r < fab.size() else -1.0
			nota.visible = f >= 0.0 and absf(f - float(sube[r])) > 1e-6
			nota.text = "de fábrica %s %%" % JuegoPiezas.num(f * 100.0, 1)
		pie.call()
		d.cambiado.connect(func(x: float):
			sube[r] = x
			campo.text = JuegoPiezas.num(x * 100.0, 1)
			pie.call()
			tabla.queue_redraw()
			tocado(s))
		campo.text_changed.connect(func(t: String):
			var x := JuegoPiezas.leer(t)
			if x < 0.0:
				return
			x = roundf(minf(x, 100.0) * 10.0) / 1000.0
			sube[r] = x
			d.valor = x
			pie.call()
			tabla.queue_redraw()
			tocado(s))
		campo.focus_exited.connect(func(): campo.text = JuegoPiezas.num(float(sube[r]) * 100.0, 1))
		c.add_child(fila)
	c.add_child(Tema.parrafo("Un cofre MÍTICO es el más alto: ya no sube. La raya blanca de cada barra es lo de fábrica.", 12, Tema.TEXTO3))


## Las filas de la tabla: comun, poco comun, rara y las de los cofres del pase
func _filas_tabla() -> Array:
	var f := [0, 1, 2]
	for n in datos["efectivo"].get("pase_niveles", []):
		for fila in ["g", "p"]:
			for it in n.get(fila, []):
				if String(it.get("t", "")) == "cofre":
					var r := clampi(int(it.get("v", 0)), 0, 5)
					if not r in f:
						f.append(r)
	f.sort()
	return f


## LA TABLA: filas = el cofre con el que se empieza; columnas = donde acaba. Cada celda, tintada de su rareza segun la
## probabilidad y con una barrita abajo.
class _TablaCofres extends Control:
	var sube: Array = []
	var filas: Array = [0, 1, 2]
	const COL0 := 94.0
	const CAB := 24.0
	const ALTO := 40.0
	const SEP := 5.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func medir() -> void:
		custom_minimum_size.y = CAB + filas.size() * (ALTO + SEP)

	func _draw() -> void:
		var f7 := Tema.fuente(700)
		var f6 := Tema.fuente(600)
		var ancho := (size.x - COL0) / 6.0
		for j in 6:
			var t := String(JuegoPiezas.RAREZAS[j]["corto"])
			var tw := f7.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string(f7, Vector2(COL0 + ancho * j + (ancho - tw) * 0.5, 15), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, JuegoPiezas.color_rareza(j))
		for i in filas.size():
			var r0: int = filas[i]
			var y := CAB + i * (ALTO + SEP)
			var p := JuegoPiezas.final_cofre(sube, r0)
			draw_circle(Vector2(6, y + ALTO * 0.5), 5.0, JuegoPiezas.color_rareza(r0))
			draw_string(f6, Vector2(17, y + ALTO * 0.5 + 5.0), String(JuegoPiezas.COFRES_FRASE[r0]), HORIZONTAL_ALIGNMENT_LEFT, COL0 - 19.0, 13, Tema.TEXTO)
			for j in 6:
				var rc := Rect2(COL0 + ancho * j + 2.0, y, ancho - 4.0, ALTO)
				var col := JuegoPiezas.color_rareza(j)
				var pj: float = p[j]
				if pj > 1e-9:
					draw_style_box(Tema.caja(Color(col, 0.07 + 0.33 * pj), 8, Color(col, 0.25 + 0.5 * pj), 1), rc)
					var bw := maxf(3.0, (rc.size.x - 8.0) * pj)
					draw_rect(Rect2(rc.position.x + 4.0, rc.end.y - 6.0, bw, 3.0), Color(col, 0.95))
				else:
					draw_style_box(Tema.caja(Color(1, 1, 1, 0.025), 8), rc)
				var t := JuegoPiezas.pct(pj)
				var fz := 12
				var tw := f7.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fz).x
				draw_string(f7, Vector2(rc.position.x + (rc.size.x - tw) * 0.5, rc.position.y + 22.0), t,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fz, Tema.TEXTO if pj > 1e-9 else Tema.TEXTO3)


# ------------------------------------------------------------------ COFRES · PREMIOS
func _pintar_premios(s: Dictionary) -> void:
	var c := vaciar(s)
	var todos: Array = s["estado"]["cofres_premios"]
	var r: int = clampi(int(s.get("rareza", 0)), 0, maxi(0, todos.size() - 1))
	c.add_child(subtitulo("Rareza en la que acaba el cofre"))
	var opciones: Array = []
	for i in todos.size():
		opciones.append([i, JuegoPiezas.COFRES[i], JuegoPiezas.color_rareza(i)])
	c.add_child(JuegoPiezas.eleccion(opciones, r, func(x):
		s["rareza"] = x
		s["pintar"].call(), 44, 13, 3))
	if todos.is_empty():
		return
	var ops: Array = todos[r]
	var barra := _BarraReparto.new()
	barra.ops = ops
	c.add_child(barra)
	s["barra"] = barra
	s["pcts"] = []
	for i in ops.size():
		c.add_child(_opcion(s, r, i))
	var mas := Boton.new("Añadir opción  (%d/8)" % ops.size(), "mas", "fantasma", 48)
	mas.tam = 15
	mas.disabled = ops.size() >= 8
	mas.tocado.connect(func():
		ops.append({"t": "oro", "w": 10, "min": 10, "max": 20})
		s["pintar"].call()
		tocado(s))
	c.add_child(mas)
	_repartir(s)


## El % de cada opcion (su peso entre la suma) y la barra de arriba
func _repartir(s: Dictionary) -> void:
	var todos: Array = s["estado"]["cofres_premios"]
	var ops: Array = todos[clampi(int(s.get("rareza", 0)), 0, todos.size() - 1)]
	var total := 0
	for o in ops:
		total += maxi(0, int(o.get("w", 0)))
	for x in s.get("pcts", []):
		var o: Dictionary = ops[x[2]]
		var w := maxi(0, int(o.get("w", 0)))
		x[0].text = ("%s %%" % JuegoPiezas.num(100.0 * w / total, 1)) if total > 0 else "—"
		x[1].text = "Opción %d  ·  peso %d de %d" % [x[2] + 1, w, total]
	if s.has("barra") and is_instance_valid(s["barra"]):
		s["barra"].queue_redraw()


static func _resumen_opcion(o: Dictionary) -> String:
	var t := String(o.get("t", ""))
	var mn := int(o.get("min", 0))
	var mx := int(o.get("max", 0))
	var cant := Tema.numero(mn) if mn == mx else "%s–%s" % [Tema.numero(mn), Tema.numero(mx)]
	match t:
		"carta":
			return "%s cop%s de una carta" % [cant, "ia" if mn == 1 and mx == 1 else "ias"]
		"articulo":
			var n := (o.get("pool", []) as Array).size()
			return "Un artículo de %d" % n if n != 1 else "Un artículo"
	return "%s %s" % [cant, JuegoPiezas.nombre_tipo(t).to_lower()]


static func _entran(hasta: int) -> String:
	var n: Array = []
	for c in JuegoPiezas.CARTAS:
		if int(c["rareza"]) <= hasta:
			n.append(Tema.frase(String(c["nombre"]).to_lower()))
	return "Entran %d de %d cartas: %s." % [n.size(), JuegoPiezas.CARTAS.size(), ", ".join(n)]


func _opcion(s: Dictionary, r: int, i: int) -> Control:
	var ops: Array = s["estado"]["cofres_premios"][r]
	var o: Dictionary = ops[i]
	var t := String(o.get("t", "oro"))
	var col := JuegoPiezas.color_tipo(t)
	var tj := PanelContainer.new()
	tj.add_theme_stylebox_override("panel", Tema.caja(Tema.SUP2, 14, Tema.BORDE, 1, Vector4(12, 12, 12, 12)))
	var v := Tema.vbox(10)
	tj.add_child(v)
	# cabecera: el tipo, lo que da, el % y quitar
	var cab := Tema.hbox(10)
	cab.add_child(JuegoPiezas.circulo(JuegoPiezas.icono_tipo(t), col, 18))
	var tv := Tema.vbox(1)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var titulo := Tema.linea(_resumen_opcion(o), 15, Tema.TEXTO, 700)
	tv.add_child(titulo)
	var sub := Tema.linea("", 12, Tema.TEXTO3)
	tv.add_child(sub)
	cab.add_child(tv)
	var pl := Tema.etiqueta("", 22, col, 800)
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cab.add_child(pl)
	s["pcts"].append([pl, sub, i])
	var q := Boton.new("", "papelera", "icono", 42)
	q.custom_minimum_size.x = 42
	q.color_icono = Tema.PELIGRO
	q.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	q.disabled = ops.size() <= 1
	q.tocado.connect(func():
		ops.remove_at(i)
		s["pintar"].call()
		tocado(s))
	cab.add_child(q)
	v.add_child(cab)
	var retitular := func(): titulo.text = _resumen_opcion(o)
	# el tipo
	var tipos: Array = []
	for x in ["carta", "oro", "cubos", "diamantes", "articulo"]:
		tipos.append([x, JuegoPiezas.nombre_tipo(x), JuegoPiezas.color_tipo(x)])
	v.add_child(JuegoPiezas.eleccion(tipos, t, func(nt):
		if nt != String(o.get("t", "")):
			ops[i] = _otro_tipo(o, String(nt), r)
			s["pintar"].call()
			tocado(s), 40, 12))
	# el peso
	var fp := Tema.hbox(10)
	var lp := JuegoPiezas.rotulo("Peso")
	lp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fp.add_child(lp)
	var ew := JuegoPiezas.campo_entero(int(o.get("w", 0)), 96, 4)
	ew.text_changed.connect(func(tx: String):
		o["w"] = JuegoPiezas.leer_entero(tx)
		_repartir(s)
		tocado(s))
	fp.add_child(ew)
	var pw := Tema.parrafo("de 0 a 1000; cuenta frente a las demás opciones", 12, Tema.TEXTO3)
	pw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fp.add_child(pw)
	v.add_child(fp)
	match t:
		"carta":
			v.add_child(JuegoPiezas.rotulo("Cartas de rareza hasta"))
			var entran := Tema.parrafo(_entran(int(o.get("hasta", 0))), 12, Tema.TEXTO3)
			v.add_child(JuegoPiezas.selector_rareza(int(o.get("hasta", 0)), func(nr: int):
				o["hasta"] = nr
				entran.text = _entran(nr)
				tocado(s)))
			v.add_child(entran)
			v.add_child(JuegoPiezas.rotulo("Copias (de una carta al azar)"))
			v.add_child(JuegoPiezas.rango(int(o.get("min", 1)), int(o.get("max", 1)), func(a: int, b: int):
				o["min"] = a
				o["max"] = b
				retitular.call()
				tocado(s)))
			v.add_child(_si_no(s, o, "Si ya tiene todas esas cartas al máximo, da"))
		"articulo":
			v.add_child(JuegoPiezas.rotulo("Uno de estos al azar (de los que no tenga)"))
			var pool: Array = o.get("pool", [])
			o["pool"] = pool
			for k in pool:
				v.add_child(_fila_pool(s, pool, String(k)))
			var mas := Boton.new("Añadir artículo  (%d/40)" % pool.size(), "mas", "fantasma", 46)
			mas.tam = 14
			mas.disabled = pool.size() >= 40
			mas.tocado.connect(func():
				Formularios.elegir_articulo(app, pool, func(a: Dictionary):
					if not String(a["clave"]) in pool:
						pool.append(String(a["clave"]))
					s["pintar"].call()
					tocado(s), TIPOS_VENTA, "ya está en la lista"))
			v.add_child(mas)
			v.add_child(_si_no(s, o, "Si ya los tiene todos, da"))
		_:
			v.add_child(JuegoPiezas.rotulo("Cantidad (al azar entre las dos)"))
			v.add_child(JuegoPiezas.rango(int(o.get("min", 0)), int(o.get("max", 0)), func(a: int, b: int):
				o["min"] = a
				o["max"] = b
				retitular.call()
				tocado(s)))
	return tj


func _fila_pool(s: Dictionary, pool: Array, k: String) -> Control:
	var h := Tema.hbox(10)
	h.add_child(Imagenes.miniatura(k, tipo_articulo(k), 74))
	var tv := Tema.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.add_child(Tema.linea(nombre_articulo(k), 14, Tema.TEXTO, 600))
	tv.add_child(Tema.linea(Tema.nombre_articulo_tipo(tipo_articulo(k)), 12, Tema.TEXTO3))
	h.add_child(tv)
	var q := Boton.new("", "cerrar", "icono", 42)
	q.custom_minimum_size.x = 42
	q.color_icono = Tema.TEXTO2
	q.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	q.tocado.connect(func():
		pool.erase(k)
		s["pintar"].call()
		tocado(s))
	h.add_child(q)
	return h


## Lo que da una carta o un articulo si ya no queda nada que dar: oro, cubos o diamantes
func _si_no(s: Dictionary, o: Dictionary, texto: String) -> Control:
	if not o.get("si_no") is Dictionary:
		o["si_no"] = {"t": "oro", "min": 20, "max": 30}
	var sn: Dictionary = o["si_no"]
	var caja := PanelContainer.new()
	caja.add_theme_stylebox_override("panel", Tema.caja(Color(1, 1, 1, 0.025), 12, Tema.BORDE, 1, Vector4(10, 10, 10, 10)))
	var v := Tema.vbox(8)
	caja.add_child(v)
	v.add_child(Tema.parrafo(texto, 13, Tema.TEXTO2, 600))
	var tipos: Array = []
	for x in ["oro", "cubos", "diamantes"]:
		tipos.append([x, JuegoPiezas.nombre_tipo(x), JuegoPiezas.color_tipo(x)])
	v.add_child(JuegoPiezas.eleccion(tipos, String(sn.get("t", "oro")), func(x):
		sn["t"] = x
		tocado(s), 38, 12))
	v.add_child(JuegoPiezas.rango(int(sn.get("min", 0)), int(sn.get("max", 0)), func(a: int, b: int):
		sn["min"] = a
		sn["max"] = b
		tocado(s)))
	return caja


## Una opcion que cambia de tipo: se queda con su peso y lo demas sale con valores razonables
static func _otro_tipo(o: Dictionary, nt: String, r: int) -> Dictionary:
	var w := int(o.get("w", 10))
	var si_no = o.get("si_no", {"t": "oro", "min": 20, "max": 30})
	match nt:
		"carta":
			return {"t": "carta", "w": w, "hasta": mini(r, 3), "min": 1, "max": 2, "si_no": si_no}
		"articulo":
			return {"t": "articulo", "w": w, "pool": [], "si_no": si_no}
	var mn := 10
	var mx := 20
	if String(o.get("t", "")) in ["oro", "cubos", "diamantes"]:
		mn = int(o.get("min", 10))
		mx = int(o.get("max", 20))
	return {"t": nt, "w": w, "min": mn, "max": mx}


## El reparto de una rareza en una barra: un trozo por opcion, del color de su tipo
class _BarraReparto extends Control:
	var ops: Array = []

	func _init() -> void:
		custom_minimum_size = Vector2(0, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var total := 0.0
		for o in ops:
			total += maxf(0.0, float(o.get("w", 0)))
		draw_style_box(Tema.caja(Tema.SUP3, 6), Rect2(Vector2.ZERO, size))
		if total <= 0.0:
			return
		var x := 0.0
		for o in ops:
			var w := maxf(0.0, float(o.get("w", 0))) / total * size.x
			if w <= 0.0:
				continue
			var col := JuegoPiezas.color_tipo(String(o.get("t", "")))
			draw_style_box(Tema.caja(col, 6), Rect2(x + 1.0, 0, maxf(2.0, w - 2.0), size.y))
			x += w


# ------------------------------------------------------------------ CARTAS · MEJORAS
func _pintar_mejoras(s: Dictionary) -> void:
	var c := vaciar(s)
	var copias: Array = s["estado"]["cartas_copias"]
	var oro: Array = s["estado"]["cartas_oro"]
	var cubos: Array = s["estado"]["cartas_cubos"]
	var total := Tema.parrafo("", 13, Tema.TEXTO2, 600)
	var sumar := func():
		var tc := 0
		var to := 0
		var tu := 0
		for n in range(1, copias.size()):
			tc += maxi(0, int(copias[n]))
			to += maxi(0, int(oro[n])) if n < oro.size() else 0
			tu += maxi(0, int(cubos[n])) if n < cubos.size() else 0
		total.text = "Para llevar una carta del nivel 1 al %d: %s copias, %s cubos de fuerza y %s de oro." % [
			copias.size(), Tema.numero(tc), Tema.numero(tu), Tema.numero(to)]
	c.add_child(_cabecera_tabla("Nivel", [["carta", Color("ff6b9a"), "Copias"], ["cubo", Tema.CUBOS, "Cubos"], ["oro", Tema.ORO, "Oro"]]))
	var fab_c: Array = datos["fabrica"].get("cartas_copias", [])
	var fab_u: Array = datos["fabrica"].get("cartas_cubos", [])
	var fab_o: Array = datos["fabrica"].get("cartas_oro", [])
	for n in range(1, copias.size()):
		var h := Tema.hbox(10)
		var l := Tema.etiqueta("%d → %d" % [n, n + 1], 16, Tema.TEXTO, 700)
		l.custom_minimum_size.x = 76
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(l)
		var a := _celda(int(copias[n]), fab_c[n] if n < fab_c.size() else null)
		var u := _celda(int(cubos[n]) if n < cubos.size() else 0, fab_u[n] if n < fab_u.size() else null)
		var b := _celda(int(oro[n]) if n < oro.size() else 0, fab_o[n] if n < fab_o.size() else null)
		(a.get_child(0) as LineEdit).text_changed.connect(func(t: String):
			copias[n] = JuegoPiezas.leer_entero(t)
			sumar.call()
			tocado(s))
		(u.get_child(0) as LineEdit).text_changed.connect(func(t: String):
			if n < cubos.size():
				cubos[n] = JuegoPiezas.leer_entero(t)
			sumar.call()
			tocado(s))
		(b.get_child(0) as LineEdit).text_changed.connect(func(t: String):
			oro[n] = JuegoPiezas.leer_entero(t)
			sumar.call()
			tocado(s))
		h.add_child(a)
		h.add_child(u)
		h.add_child(b)
		c.add_child(h)
	sumar.call()
	c.add_child(total)
	c.add_child(Tema.parrafo("El nivel %d es el máximo. Un campo con borde amarillo no está como viene de fábrica." % copias.size(), 12, Tema.TEXTO3))


## Una cabecera de tabla: el titulo de la primera columna y [icono, color, texto] de las demas
func _cabecera_tabla(primera: String, cols: Array) -> HBoxContainer:
	var h := Tema.hbox(10)
	var l := Tema.etiqueta(primera.to_upper(), 11, Tema.TEXTO3, 700)
	l.custom_minimum_size.x = 76
	h.add_child(l)
	for x in cols:
		var cc := JuegoPiezas.cifra(String(x[0]), x[1], String(x[2]).to_upper(), 12, Tema.TEXTO3)
		cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cc.alignment = BoxContainer.ALIGNMENT_END
		h.add_child(cc)
	return h


## Un campo de tabla (entero). Si no es el de fabrica, el borde amarillo. Devuelve una caja con el campo dentro.
func _celda(valor: int, fabrica) -> Control:
	var caja := MarginContainer.new()
	caja.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var e := JuegoPiezas.campo_entero(valor)
	e.custom_minimum_size.y = 48
	caja.add_child(e)
	var marcar := func(t: String):
		var dif := fabrica != null and JuegoPiezas.leer_entero(t) != int(fabrica)
		if dif:
			e.add_theme_stylebox_override("normal", Tema.caja(Tema.SUP2.lerp(Tema.ACENTO, 0.05), 12, Color(Tema.ACENTO, 0.55), 1, Vector4(14, 10, 14, 10)))
		else:
			e.remove_theme_stylebox_override("normal")
	e.text_changed.connect(marcar)
	marcar.call(e.text)
	return caja


# ------------------------------------------------------------------ CARTAS · LO QUE DAN
static func _unidad(u: String) -> String:
	if u.begins_with("%"):
		return u
	return u.strip_edges()


static func _escala(u: String) -> float:
	return 100.0 if u.begins_with("%") else 1.0


## "+6 %", "+2,4 vida/s", "−10 %" (lo que resta, como la recarga)
static func formato_carta(u: String, v: float) -> String:
	if u == "% menos":
		return "−%s %%" % JuegoPiezas.num(v * 100.0, 1)
	if u.begins_with("%"):
		return "+%s %%" % JuegoPiezas.num(v * 100.0, 1)
	return "+%s %s" % [JuegoPiezas.num(v, 2), u.strip_edges()]


func _pintar_valores(s: Dictionary) -> void:
	var c := vaciar(s)
	var vals: Dictionary = s["estado"]["cartas_valores"]
	var fab: Dictionary = datos["fabrica"].get("cartas_valores", {})
	for carta in JuegoPiezas.CARTAS:
		var id := String(carta["id"])
		if not vals.has(id):
			continue
		var x: Dictionary = vals[id]
		var fx: Dictionary = fab.get(id, {})
		var u := String(fx.get("unidad", x.get("unidad", "%")))
		var esc := _escala(u)
		var tj := PanelContainer.new()
		tj.add_theme_stylebox_override("panel", Tema.caja(Tema.SUP2, 14, Tema.BORDE, 1, Vector4(12, 12, 12, 12)))
		var v := Tema.vbox(10)
		tj.add_child(v)
		var cab := Tema.hbox(10)
		cab.add_child(JuegoPiezas.circulo("carta", carta["color"], 16))
		var nom := Tema.linea(String(carta["nombre"]), 15, Tema.TEXTO, 700)
		nom.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cab.add_child(nom)
		var ch := JuegoPiezas.chip_rareza(int(carta["rareza"]))
		ch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cab.add_child(ch)
		v.add_child(cab)
		var fila := Tema.hbox(10)
		var vista := Tema.linea("", 13, carta["color"].lerp(Tema.TEXTO, 0.35), 700)
		var nota := Tema.linea("", 12, Tema.TEXTO3)
		var repintar := func():
			var b := float(x.get("base", 0))
			var p := float(x.get("paso", 0))
			vista.text = "Nv 1: %s   ·   Nv 5: %s   ·   Nv 10: %s" % [formato_carta(u, b), formato_carta(u, b + p * 4.0), formato_carta(u, b + p * 9.0)]
			var fb := float(fx.get("base", b))
			var fp := float(fx.get("paso", p))
			nota.visible = absf(fb - b) > 1e-9 or absf(fp - p) > 1e-9
			nota.text = "De fábrica: %s a nivel 1 y %s por nivel" % [formato_carta(u, fb), formato_carta(u, fp)]
		for campo in [["base", "A nivel 1"], ["paso", "Cada nivel más"]]:
			var cv := Tema.vbox(6)
			cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cv.add_child(JuegoPiezas.rotulo(String(campo[1])))
			var ch2 := Tema.hbox(6)
			var e := JuegoPiezas.campo_decimal(JuegoPiezas.num(float(x.get(campo[0], 0)) * esc, 3))
			e.custom_minimum_size.y = 48
			ch2.add_child(e)
			var ul := Tema.etiqueta(_unidad(u), 14, Tema.TEXTO2, 700)
			ul.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			ch2.add_child(ul)
			cv.add_child(ch2)
			fila.add_child(cv)
			var k := String(campo[0])
			e.text_changed.connect(func(t: String):
				var n := JuegoPiezas.leer(t)
				if n < 0.0:
					return
				x[k] = roundf(n * 1000.0) / (1000.0 * esc)
				repintar.call()
				tocado(s))
			e.focus_exited.connect(func(): e.text = JuegoPiezas.num(float(x.get(k, 0)) * esc, 3))
		v.add_child(fila)
		v.add_child(vista)
		v.add_child(nota)
		repintar.call()
		c.add_child(tj)


# ------------------------------------------------------------------ PERSONAJES
func _pintar_personajes(s: Dictionary) -> void:
	var c := vaciar(s)
	var coste: Dictionary = s["estado"]["personajes_coste"]
	var fab: Dictionary = datos["fabrica"].get("personajes_coste", {})
	var niveles: Array = coste.keys()
	niveles.sort_custom(func(a, b): return int(a) < int(b))
	var total := Tema.parrafo("", 13, Tema.TEXTO2, 600)
	var sumar := func():
		var tc := 0
		var to := 0
		for k in niveles:
			tc += maxi(0, int(coste[k][0]))
			to += maxi(0, int(coste[k][1]))
		total.text = "Del nivel 1 al %s: %s cubos de fuerza y %s de oro." % [niveles.back() if not niveles.is_empty() else "1", Tema.numero(tc), Tema.numero(to)]
	c.add_child(_cabecera_tabla("Nivel", [["cubo", Tema.CUBOS, "Cubos"], ["oro", Tema.ORO, "Oro"]]))
	for k in niveles:
		var x: Array = coste[k]
		var fx = fab.get(k, null)
		var h := Tema.hbox(10)
		var l := Tema.etiqueta("%d → %s" % [int(k) - 1, k], 16, Tema.TEXTO, 700)
		l.custom_minimum_size.x = 76
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(l)
		var a := _celda(int(x[0]), fx[0] if fx is Array else null)
		var b := _celda(int(x[1]), fx[1] if fx is Array else null)
		(a.get_child(0) as LineEdit).text_changed.connect(func(t: String):
			x[0] = JuegoPiezas.leer_entero(t)
			sumar.call()
			tocado(s))
		(b.get_child(0) as LineEdit).text_changed.connect(func(t: String):
			x[1] = JuegoPiezas.leer_entero(t)
			sumar.call()
			tocado(s))
		h.add_child(a)
		h.add_child(b)
		c.add_child(h)
	sumar.call()
	c.add_child(total)
	c.add_child(Tema.parrafo("Cada nivel sube la salud y la habilidad del personaje. Con cuenta, lo cobra el servidor.", 12, Tema.TEXTO3))


# ------------------------------------------------------------------ ORO POR PARTIDA
func _pintar_oro(s: Dictionary) -> void:
	var c := vaciar(s)
	var fab := float(datos["fabrica"].get("oro_partida", 0.1))
	var grande := Tema.etiqueta("", 46, Tema.ORO, 800)
	grande.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bajo := Tema.etiqueta("del oro de cada partida", 14, Tema.TEXTO2, 600)
	bajo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ej := Tema.parrafo("", 13, Tema.TEXTO2)
	ej.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var d := JuegoPiezas.Deslizador.new(minf(1.0, float(s["estado"]["oro_partida"])), Tema.ORO)
	d.paso = 0.01
	d.marca = minf(1.0, fab)
	var campo := JuegoPiezas.campo_decimal("", 110)
	var poner := func(f: float, desde_campo: bool):
		f = clampf(f, 0.0, 10.0)
		s["estado"]["oro_partida"] = f
		grande.text = "%s %%" % JuegoPiezas.num(f * 100.0, 1)
		ej.text = "Una partida que da 500 de oro base → %s de oro." % Tema.numero(int(floor(500.0 * f)))
		d.valor = minf(1.0, f)
		if not desde_campo:
			campo.text = JuegoPiezas.num(f * 100.0, 1)
		tocado(s)
	c.add_child(Tema.espacio(4))
	c.add_child(grande)
	c.add_child(bajo)
	c.add_child(Tema.espacio(2))
	c.add_child(d)
	var h := Tema.hbox(8)
	var lf := JuegoPiezas.rotulo("Exacto")
	lf.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(lf)
	h.add_child(Tema.expandir())
	h.add_child(campo)
	var u := Tema.etiqueta("%", 16, Tema.TEXTO2, 700)
	u.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(u)
	c.add_child(h)
	var rap := Tema.hbox(6)
	for p in [5, 10, 25, 50, 100]:
		var b := Boton.new("%d %%" % p, "", "fantasma", 40)
		b.tam = 14
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.x = 0
		b.tocado.connect(func(): poner.call(p / 100.0, false))
		rap.add_child(b)
	c.add_child(rap)
	c.add_child(ej)
	c.add_child(Tema.parrafo("De fábrica, %s %%. La raya blanca de la barra es lo de fábrica; se puede escribir hasta 1.000 %%." % JuegoPiezas.num(fab * 100.0, 1), 12, Tema.TEXTO3))
	d.cambiado.connect(func(x: float): poner.call(x, false))
	campo.text_changed.connect(func(t: String):
		var x := JuegoPiezas.leer(t)
		if x >= 0.0:
			poner.call(roundf(minf(x, 1000.0) * 10.0) / 1000.0, true))
	campo.focus_exited.connect(func(): campo.text = JuegoPiezas.num(float(s["estado"]["oro_partida"]) * 100.0, 1))
	# lo de ahora, sin marcarlo como cambio
	var f0 := float(s["estado"]["oro_partida"])
	grande.text = "%s %%" % JuegoPiezas.num(f0 * 100.0, 1)
	ej.text = "Una partida que da 500 de oro base → %s de oro." % Tema.numero(int(floor(500.0 * f0)))
	campo.text = JuegoPiezas.num(f0 * 100.0, 1)


# ------------------------------------------------------------------ el boton de cada seccion (con su punto)
class _BotonSeccion extends Boton:
	var punto := Color.TRANSPARENT:
		set(v):
			punto = v
			queue_redraw()

	func _init(p_texto := "") -> void:
		super(p_texto, "", "fantasma", 38)
		tam = 13
		_medir()

	func _medir() -> void:
		super._medir()
		custom_minimum_size.x += 8.0

	func _draw() -> void:
		super._draw()
		if punto.a > 0.0:
			var c := Vector2(size.x - 9.0, 9.0)
			draw_circle(c, 5.5, Tema.FONDO)
			draw_circle(c, 4.0, punto)
