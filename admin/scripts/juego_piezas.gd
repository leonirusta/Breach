class_name JuegoPiezas
extends RefCounted
## PIEZAS DE LA PESTAÑA JUEGO (pestana_juego.gd, juego_pase.gd, juego_destacados.gd):
##   - lo que el panel tiene que saber del juego para enseñarlo: las RAREZAS (nombre y color, como RAREZAS de
##     godot/scripts/skins_armas.gd), los cofres en masculino (cofre_pantalla.gd NOMBRES), las CARTAS (cartas.gd LISTA)
##     y las HABILIDADES (habilidad.gd LISTA). Si el juego cambia esas listas, hay que cambiarlas aqui.
##   - la cuenta de los cofres (`final_cofre`: donde acaba un cofre tras sus toques)
##   - numeros con coma, comparar valores del servidor, y controles propios, grandes para el dedo: el DESLIZADOR, el
##     INTERRUPTOR, el campo DECIMAL, el selector de rareza con − y +, y el boton de color (una rareza, un tipo).

const RAREZAS := [
	{"nombre": "COMÚN", "corto": "COM.", "color": Color(0.72, 0.75, 0.80)},
	{"nombre": "POCO COMÚN", "corto": "P. COM.", "color": Color(0.38, 0.82, 0.45)},
	{"nombre": "RARA", "corto": "RARA", "color": Color(0.30, 0.62, 1.00)},
	{"nombre": "ÉPICA", "corto": "ÉPICA", "color": Color(0.70, 0.36, 1.00)},
	{"nombre": "LEGENDARIA", "corto": "LEG.", "color": Color(1.00, 0.72, 0.12)},
	{"nombre": "MÍTICA", "corto": "MÍT.", "color": Color(1.00, 0.30, 0.42)},
]
const COFRES := ["COMÚN", "POCO COMÚN", "RARO", "ÉPICO", "LEGENDARIO", "MÍTICO"]
const COFRES_FRASE := ["Común", "Poco común", "Raro", "Épico", "Legendario", "Mítico"]
const TOQUES := 4                  ## cofres.gd TOQUES: en cada uno puede subir una rareza

const CARTAS := [
	{"id": "dano", "nombre": "AUMENTO DE DAÑO", "rareza": 0, "color": Color(0.93, 0.22, 0.24)},
	{"id": "municion", "nombre": "MUNICIÓN AL ELIMINAR", "rareza": 2, "color": Color(0.85, 0.25, 0.85)},
	{"id": "vida", "nombre": "SALUD MÁX.", "rareza": 0, "color": Color(0.25, 0.8, 0.35)},
	{"id": "regeneracion", "nombre": "REGEN. DE SALUD", "rareza": 1, "color": Color(0.25, 0.75, 0.4)},
	{"id": "vampiro", "nombre": "VAMPIRO", "rareza": 2, "color": Color(0.78, 0.1, 0.28)},
	{"id": "rescatista", "nombre": "RESCATISTA", "rareza": 2, "color": Color(0.15, 0.72, 0.62)},
	{"id": "blindaje", "nombre": "BLINDAJE", "rareza": 1, "color": Color(0.4, 0.52, 0.7)},
	{"id": "piel_dura", "nombre": "PIEL DURA", "rareza": 1, "color": Color(0.66, 0.44, 0.24)},
	{"id": "velocidad", "nombre": "VEL. DE MOVIMIENTO", "rareza": 0, "color": Color(0.2, 0.55, 0.95)},
	{"id": "salto", "nombre": "SALTO ALTO", "rareza": 1, "color": Color(0.35, 0.45, 0.95)},
	{"id": "destruccion", "nombre": "DAÑO POR DESTRUCCIÓN", "rareza": 2, "color": Color(0.95, 0.5, 0.15)},
	{"id": "explosion", "nombre": "EXPLOSIÓN AMPLIA", "rareza": 3, "color": Color(0.95, 0.35, 0.1)},
	{"id": "enfriamiento", "nombre": "REDUCCIÓN DE ENFRIAMIENTO", "rareza": 3, "color": Color(0.98, 0.72, 0.1)},
	{"id": "definitiva", "nombre": "RECARGA DE DEFINITIVA", "rareza": 3, "color": Color(0.95, 0.45, 0.12)},
]
const NIVEL_MAX_CARTA := 10

const HABILIDADES := [
	{"id": "gancho", "nombre": "GANCHO"}, {"id": "salto", "nombre": "SALTO DEMOLEDOR"},
	{"id": "invisible", "nombre": "INVISIBLE"}, {"id": "punetazo", "nombre": "PUÑETAZO"},
]

## Los premios de los cofres y del pase: nombre, icono y color
const TIPOS := {
	"carta": ["Cartas", "carta", Color("ff6b9a")], "oro": ["Oro", "oro", Tema.ORO], "cubos": ["Cubos", "cubo", Tema.CUBOS],
	"diamantes": ["Diamantes", "diamante", Tema.DIAMANTE], "articulo": ["Artículo", "caja", Tema.ACENTO],
	"cofre": ["Cofre", "cofre", Tema.TEXTO2], "modelo": ["Skin", "usuario", Tema.ACENTO],
	"pintura": ["Pintura", "diamante", Tema.ACENTO], "mazo": ["Mazo", "lapiz", Tema.ACENTO],
	"habilidad": ["Habilidad", "exp", Tema.EXP],
}


static func nombre_tipo(t: String) -> String:
	return String(TIPOS.get(t, [t])[0])


static func icono_tipo(t: String) -> String:
	return String(TIPOS.get(t, ["", "caja"])[1])


static func color_tipo(t: String) -> Color:
	return TIPOS.get(t, ["", "", Tema.TEXTO2])[2]


static func color_rareza(r: int) -> Color:
	return RAREZAS[clampi(r, 0, 5)]["color"]


static func nombre_rareza(r: int) -> String:
	return String(RAREZAS[clampi(r, 0, 5)]["nombre"])


static func nombre_habilidad(id: String) -> String:
	for h in HABILIDADES:
		if String(h["id"]) == id:
			return String(h["nombre"])
	return id.to_upper()


static func nombre_carta(id: String) -> String:
	for c in CARTAS:
		if String(c["id"]) == id:
			return String(c["nombre"])
	return id.to_upper()


# ------------------------------------------------------------------ cuentas
## Donde acaba un cofre que empieza en `inicio`: la probabilidad de cada rareza (6) tras los toques. En cada toque, si
## no es mitica, sube una con la probabilidad de su rareza de ahora (una cadena de Markov de 6 estados).
static func final_cofre(sube: Array, inicio: int, toques := TOQUES) -> Array:
	var p := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	p[clampi(inicio, 0, 5)] = 1.0
	for _i in toques:
		var q := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		for r in 6:
			if p[r] <= 0.0:
				continue
			var s := clampf(float(sube[r]), 0.0, 1.0) if r < 5 and r < sube.size() else 0.0
			q[r] += p[r] * (1.0 - s)
			if r < 5:
				q[r + 1] += p[r] * s
		p = q
	return p


## Dos valores del servidor iguales (los numeros, con tolerancia: del JSON llegan como float)
static func igual(a, b) -> bool:
	var na := typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT
	var nb := typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT
	if na and nb:
		return absf(float(a) - float(b)) < 1e-7
	if typeof(a) != typeof(b):
		return false
	if a is Array:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in (a as Array).size():
			if not igual(a[i], b[i]):
				return false
		return true
	if a is Dictionary:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for k in a:
			if not (b as Dictionary).has(k) or not igual(a[k], b[k]):
				return false
		return true
	return a == b


static func copia(x):
	if x is Array or x is Dictionary:
		return x.duplicate(true)
	return x


# ------------------------------------------------------------------ numeros
## 45 -> "45", 2.5 -> "2,5", 0.125 -> "0,13" (hasta `dec` decimales, sin ceros de mas)
static func num(v: float, dec := 2) -> String:
	var t := ("%." + str(dec) + "f") % v
	if "." in t:
		t = t.rstrip("0").trim_suffix(".")
	return t.replace(".", ",")


## Una probabilidad (0..1) para la tabla: "54,9 %", "<0,1 %", o "—" si no puede pasar
static func pct(p: float) -> String:
	if p <= 1e-9:
		return "—"
	if p * 100.0 < 0.05:
		return "<0,1 %"
	if p >= 0.9995:
		return "100 %"
	return ("%.1f %%" % (p * 100.0)).replace(".", ",")


## Lo escrito en un campo decimal ("12,5") -> 12.5; vacio o raro -> -1
static func leer(t: String) -> float:
	t = t.strip_edges().replace(",", ".")
	if t == "" or t == ".":
		return -1.0
	return t.to_float() if t.is_valid_float() else -1.0


static func leer_entero(t: String) -> int:
	t = t.strip_edges()
	return int(t) if t.is_valid_int() else -1


# ------------------------------------------------------------------ piezas
## Un campo para numeros con decimales (coma o punto)
static func campo_decimal(texto := "", ancho := 0.0) -> LineEdit:
	var e := Tema.campo("", false, texto)
	e.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	e.max_length = 9
	e.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if ancho > 0.0:
		e.custom_minimum_size.x = ancho
		e.size_flags_horizontal = Control.SIZE_FILL
	e.text_changed.connect(func(t: String):
		var limpio := ""
		var coma := false
		for ch in t:
			if ch >= "0" and ch <= "9":
				limpio += ch
			elif (ch == "," or ch == ".") and not coma:
				limpio += ","
				coma = true
		if limpio != t:
			var col := e.caret_column
			e.text = limpio
			e.caret_column = mini(col, limpio.length()))
	return e


## Un campo para enteros, alineado a la derecha
static func campo_entero(valor: int, ancho := 0.0, max_len := 9) -> LineEdit:
	var e := Tema.campo_numero("", valor)
	e.max_length = max_len
	e.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if ancho > 0.0:
		e.custom_minimum_size.x = ancho
		e.size_flags_horizontal = Control.SIZE_FILL
	return e


## Una fila "min – max" con dos campos de enteros. `al_cambiar(min, max)` (-1 si un campo no vale).
static func rango(mn: int, mx: int, al_cambiar: Callable) -> HBoxContainer:
	var h := Tema.hbox(8)
	var a := campo_entero(mn)
	var b := campo_entero(mx)
	var guion := Tema.etiqueta("–", 18, Tema.TEXTO3, 700)
	guion.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(a)
	h.add_child(guion)
	h.add_child(b)
	var avisar := func(_t):
		al_cambiar.call(leer_entero(a.text), leer_entero(b.text))
	a.text_changed.connect(avisar)
	b.text_changed.connect(avisar)
	return h


## Una etiqueta de campo (gris, pequeña) encima de lo que sea
static func rotulo(texto: String) -> Label:
	return Tema.etiqueta(texto, 13, Tema.TEXTO2, 600)


## La rareza en una pastilla de su color
static func chip_rareza(r: int, cofre := false) -> PanelContainer:
	return Tema.chip(COFRES[clampi(r, 0, 5)] if cofre else nombre_rareza(r), color_rareza(r))


## Un circulo tintado con un icono (cabeceras)
static func circulo(icono: String, color: Color, lado := 18) -> PanelContainer:
	var circ := PanelContainer.new()
	circ.add_theme_stylebox_override("panel", Tema.caja(Color(color, 0.15), 10, Color.TRANSPARENT, 0, Vector4(7, 7, 7, 7)))
	circ.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	circ.mouse_filter = Control.MOUSE_FILTER_IGNORE
	circ.add_child(Iconos.new(icono, color, lado))
	return circ


## Una cifra con su icono delante (oro, cubos, diamantes...)
static func cifra(icono: String, color: Color, texto: String, tam := 15, col_texto := Tema.TEXTO) -> HBoxContainer:
	var h := Tema.hbox(5)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := Iconos.new(icono, color, tam - 1)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	h.add_child(Tema.etiqueta(texto, tam, col_texto, 700))
	return h


## EL SELECTOR DE RAREZA: [−] la pastilla [+]. `al_cambiar(r)`. Devuelve la fila.
static func selector_rareza(r: int, al_cambiar: Callable, minimo := 0, maximo := 5, cofre := false) -> HBoxContainer:
	var h := Tema.hbox(8)
	var estado := {"r": clampi(r, minimo, maximo)}
	var menos := Boton.new("", "menos", "fantasma", 44)
	menos.custom_minimum_size.x = 44
	var mas := Boton.new("", "mas", "fantasma", 44)
	mas.custom_minimum_size.x = 44
	var caja := CenterContainer.new()
	caja.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caja.custom_minimum_size.y = 44
	var pintar := func():
		for n in caja.get_children():
			n.queue_free()
		var col := color_rareza(estado["r"])
		var ch := PanelContainer.new()
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ch.add_theme_stylebox_override("panel", Tema.caja(Color(col, 0.16), 10, Color(col, 0.6), 1, Vector4(16, 7, 16, 7)))
		ch.add_child(Tema.etiqueta(COFRES[estado["r"]] if cofre else nombre_rareza(estado["r"]), 15, col, 800))
		caja.add_child(ch)
		menos.disabled = estado["r"] <= minimo
		mas.disabled = estado["r"] >= maximo
	menos.tocado.connect(func():
		estado["r"] = maxi(minimo, estado["r"] - 1)
		pintar.call()
		al_cambiar.call(estado["r"]))
	mas.tocado.connect(func():
		estado["r"] = mini(maximo, estado["r"] + 1)
		pintar.call()
		al_cambiar.call(estado["r"]))
	h.add_child(menos)
	h.add_child(caja)
	h.add_child(mas)
	pintar.call()
	return h


## Una fila de botones de color de los que se elige uno: [[valor, texto, color], ...]. `al_cambiar(valor)`.
static func eleccion(opciones: Array, sel, al_cambiar: Callable, alto := 42.0, tam := 13, columnas := 0) -> Container:
	var cont: Container
	if columnas > 0:
		var g := GridContainer.new()
		g.columns = columnas
		g.add_theme_constant_override("h_separation", 6)
		g.add_theme_constant_override("v_separation", 6)
		cont = g
	else:
		cont = Tema.hbox(6)
	var botones: Array = []
	for o in opciones:
		var b := BotonColor.new(String(o[1]), o[2] if o.size() > 2 else Tema.ACENTO, alto)
		b.tam = tam
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.x = 0
		b.activo = o[0] == sel
		botones.append(b)
		cont.add_child(b)
	for i in botones.size():
		botones[i].tocado.connect(func():
			for j in botones.size():
				botones[j].activo = j == i
			al_cambiar.call(opciones[i][0]))
	return cont


## Un boton con un color propio (una rareza, un tipo de premio): borde y texto de su color; elegido, tintado.
class BotonColor extends Boton:
	var col := Tema.ACENTO
	var activo := false:
		set(v):
			activo = v
			_estilos()
			queue_redraw()

	func _init(p_texto := "", p_color := Tema.ACENTO, alto := 42.0) -> void:
		col = p_color
		super(p_texto, "", "fantasma", alto)

	func _estilos() -> void:
		var bg := Color(col, 0.18) if activo else Color(0, 0, 0, 0)
		var borde := Color(col, 0.9) if activo else Tema.BORDE
		add_theme_stylebox_override("normal", Tema.caja(bg, 12, borde, 2 if activo else 1))
		add_theme_stylebox_override("hover", Tema.caja(Color(col, 0.24) if activo else Color(1, 1, 1, 0.05), 12, borde, 2 if activo else 1))
		add_theme_stylebox_override("pressed", Tema.caja(Color(col, 0.3), 12, borde, 2 if activo else 1))
		add_theme_stylebox_override("disabled", Tema.caja(Color(bg, bg.a * 0.45), 12, Color(borde, borde.a * 0.5), 1))
		add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	func _color_texto() -> Color:
		return col if activo else Color(col.lerp(Tema.TEXTO2, 0.35), 0.95)


## EL DESLIZADOR: una barra gruesa con una bola grande, de 0 a 1. Se arrastra de lado (si el dedo se va para arriba o
## abajo, main.gd lo toma como desplazar la lista y el deslizador se queda donde estaba). `cambiado(v)` al moverlo.
class Deslizador extends Control:
	signal cambiado(v: float)
	var valor := 0.0:
		set(v):
			valor = clampf(v, 0.0, 1.0)
			queue_redraw()
	var color := Tema.ACENTO
	var marca := -1.0                  ## una rayita (lo de fabrica), o -1
	var paso := 0.005
	var _arrastra := false

	func _init(p_valor := 0.0, p_color := Tema.ACENTO) -> void:
		valor = p_valor
		color = p_color
		custom_minimum_size = Vector2(0, 40)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_arrastra = (e as InputEventMouseButton).pressed
			if _arrastra:
				_poner((e as InputEventMouseButton).position.x)
			accept_event()
		elif e is InputEventMouseMotion and _arrastra:
			if Tema.arrastrando:
				_arrastra = false
				return
			_poner((e as InputEventMouseMotion).position.x)
			accept_event()

	func _poner(x: float) -> void:
		var r := 13.0
		var v := clampf((x - r) / maxf(1.0, size.x - 2.0 * r), 0.0, 1.0)
		if paso > 0.0:
			v = roundf(v / paso) * paso
		v = roundf(v * 1000.0) / 1000.0
		if absf(v - valor) > 1e-9:
			valor = v
			cambiado.emit(valor)

	func _draw() -> void:
		var r := 13.0
		var y := size.y * 0.5
		var w := size.x - 2.0 * r
		draw_style_box(Tema.caja(Tema.SUP3, 5), Rect2(r, y - 5.0, w, 10.0))
		if valor > 0.0:
			draw_style_box(Tema.caja(Color(color, 0.85), 5), Rect2(r, y - 5.0, maxf(10.0, w * valor), 10.0))
		if marca >= 0.0:
			var mx := r + w * clampf(marca, 0.0, 1.0)
			draw_line(Vector2(mx, y - 11.0), Vector2(mx, y + 11.0), Color(Tema.TEXTO, 0.55), 2.0, true)
		var c := Vector2(r + w * valor, y)
		draw_circle(c, r, Tema.FONDO)
		draw_circle(c, r - 1.0, color)
		draw_circle(c, 4.5, Color(Tema.FONDO, 0.55))


## EL INTERRUPTOR: si / no, grande. `cambiado(si)` al tocarlo.
class Interruptor extends Control:
	signal cambiado(si: bool)
	var si := false:
		set(v):
			si = v
			queue_redraw()

	func _init(p_si := false) -> void:
		si = p_si
		custom_minimum_size = Vector2(60, 36)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			if not (e as InputEventMouseButton).pressed and not Tema.arrastrando:
				si = not si
				cambiado.emit(si)
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2(0, (size.y - 32.0) * 0.5), Vector2(size.x, 32.0))
		draw_style_box(Tema.caja(Tema.OK if si else Tema.SUP3, 16, Color.TRANSPARENT if si else Tema.BORDE, 0 if si else 1), r)
		var c := Vector2(r.end.x - 16.0 if si else r.position.x + 16.0, r.get_center().y)
		draw_circle(c, 12.0, Color.WHITE if si else Tema.TEXTO2)
