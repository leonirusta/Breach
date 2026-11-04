class_name JuegoDestacados
extends RefCounted
## LOS DESTACADOS DE LA TIENDA en la pestaña JUEGO (pestana_juego.gd): hasta 8 articulos que salen primero en
## DESTACADAS, cada uno a SU precio y en SU moneda (oro o diamantes; el juego los cobra asi, sin descuentos). En el
## orden de la lista (se sube y se baja). El pase premium no se puede destacar. Debajo, el interruptor
## `destacados_diarios`: si la tienda sigue enseñando tambien las pinturas del dia.
## GUARDAR manda la lista entera (POST /admin/destacados) y, si cambio, el interruptor (POST /admin/juego).

const MAX := 8
const PRECIO_MAX := 10000000


static func pintar(tab, s: Dictionary) -> void:
	var c: VBoxContainer = tab.vaciar(s)
	var lista: Array = s["estado"]["destacados"]
	if lista.is_empty():
		var vacio := Tema.tarjeta(16, Color(1, 1, 1, 0.02))
		var vv := Tema.vbox(6)
		vacio.add_child(vv)
		var ic := Iconos.new("tienda", Tema.TEXTO3, 34)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vv.add_child(ic)
		var t := Tema.parrafo("Sin destacados del panel", 15, Tema.TEXTO, 700)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vv.add_child(t)
		var p := Tema.parrafo("La tienda enseña en DESTACADAS lo de siempre. Añade artículos con su precio.", 13, Tema.TEXTO3)
		p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vv.add_child(p)
		c.add_child(vacio)
	for i in lista.size():
		c.add_child(_fila(tab, s, i))
	var mas := Boton.new("Añadir destacado  (%d/%d)" % [lista.size(), MAX], "mas", "fantasma", 50)
	mas.tam = 15
	mas.disabled = lista.size() >= MAX
	mas.tocado.connect(func():
		var ya: Array = []
		for x in lista:
			ya.append(String(x.get("clave", "")))
		Formularios.elegir_articulo(tab.app, ya, func(a: Dictionary):
			if lista.size() < MAX and not String(a["clave"]) in ya:
				lista.append({"clave": String(a["clave"]), "precio": maxi(1, int(a.get("precio", 1))), "moneda": "monedas"})
			s["pintar"].call()
			tab.tocado(s), PestanaJuego.TIPOS_VENTA, "ya está destacado"))
	c.add_child(mas)
	c.add_child(Tema.separador())
	# el interruptor de las pinturas del dia
	var h := Tema.hbox(12)
	var tv := Tema.vbox(3)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(Tema.parrafo("Seguir mostrando las pinturas del día", 15, Tema.TEXTO, 700))
	tv.add_child(Tema.parrafo("Además de estos, DESTACADAS enseña las pinturas que cambian cada día.", 12, Tema.TEXTO3))
	h.add_child(tv)
	var sw := JuegoPiezas.Interruptor.new(bool(s["estado"].get("destacados_diarios", true)))
	sw.cambiado.connect(func(si: bool):
		s["estado"]["destacados_diarios"] = si
		tab.tocado(s))
	h.add_child(sw)
	c.add_child(h)


static func _fila(tab, s: Dictionary, i: int) -> Control:
	var lista: Array = s["estado"]["destacados"]
	var d: Dictionary = lista[i]
	var clave := String(d.get("clave", ""))
	var tipo: String = tab.tipo_articulo(clave)
	var tj := PanelContainer.new()
	tj.add_theme_stylebox_override("panel", Tema.caja(Tema.SUP2, 14, Tema.BORDE, 1, Vector4(12, 12, 12, 12)))
	var v := Tema.vbox(10)
	tj.add_child(v)
	# arriba: la foto, el nombre, y subir / bajar / quitar
	var arriba := Tema.hbox(10)
	arriba.add_child(Imagenes.miniatura(clave, tipo, 84))
	var tv := Tema.vbox(1)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.add_child(Tema.linea(tab.nombre_articulo(clave), 15, Tema.TEXTO, 700))
	tv.add_child(Tema.linea("%d.º  ·  %s" % [i + 1, Tema.nombre_articulo_tipo(tipo)], 12, Tema.TEXTO3))
	var normal := JuegoPiezas.cifra("oro", Tema.ORO, "normal " + Tema.numero(tab.precio_articulo(clave)), 12, Tema.TEXTO3)
	tv.add_child(normal)
	arriba.add_child(tv)
	for o in [["subir", -1], ["bajar", 1]]:
		var b := Boton.new("", String(o[0]), "icono", 40)
		b.custom_minimum_size.x = 40
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var otro := i + int(o[1])
		b.disabled = otro < 0 or otro >= lista.size()
		b.tocado.connect(func():
			var x = lista[i]
			lista[i] = lista[otro]
			lista[otro] = x
			s["pintar"].call()
			tab.tocado(s))
		arriba.add_child(b)
	var q := Boton.new("", "papelera", "icono", 40)
	q.custom_minimum_size.x = 40
	q.color_icono = Tema.PELIGRO
	q.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	q.tocado.connect(func():
		lista.remove_at(i)
		s["pintar"].call()
		tab.tocado(s))
	arriba.add_child(q)
	v.add_child(arriba)
	# abajo: el precio y la moneda
	var abajo := Tema.hbox(8)
	var icono := Iconos.new("diamante" if String(d.get("moneda", "")) == "creditos" else "oro",
		Tema.DIAMANTE if String(d.get("moneda", "")) == "creditos" else Tema.ORO, 20)
	icono.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	abajo.add_child(icono)
	var e := JuegoPiezas.campo_entero(int(d.get("precio", 0)), 0, 8)
	e.alignment = HORIZONTAL_ALIGNMENT_LEFT
	e.custom_minimum_size.x = 90
	e.text_changed.connect(func(t: String):
		d["precio"] = JuegoPiezas.leer_entero(t)
		tab.tocado(s))
	abajo.add_child(e)
	var mon := JuegoPiezas.eleccion([["monedas", "Oro", Tema.ORO], ["creditos", "Diamantes", Tema.DIAMANTE]],
		"creditos" if String(d.get("moneda", "")) == "creditos" else "monedas", func(m):
			d["moneda"] = String(m)
			icono.icono = "diamante" if m == "creditos" else "oro"
			icono.color = Tema.DIAMANTE if m == "creditos" else Tema.ORO
			tab.tocado(s), 48, 13)
	mon.custom_minimum_size.x = 196
	mon.size_flags_horizontal = Control.SIZE_FILL
	abajo.add_child(mon)
	v.add_child(abajo)
	return tj


## Antes de mandar ("" = bien)
static func validar(_tab, lista: Array) -> String:
	if lista.size() > MAX:
		return "Como mucho %d destacados" % MAX
	for i in lista.size():
		var p := int(lista[i].get("precio", 0))
		if p < 1 or p > PRECIO_MAX:
			return "Destacado %d: el precio va de 1 a %s" % [i + 1, Tema.numero(PRECIO_MAX)]
		if String(lista[i].get("clave", "")).begins_with("pase_"):
			return "El pase no se puede destacar"
	return ""
