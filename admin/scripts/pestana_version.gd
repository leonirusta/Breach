class_name PestanaVersion
extends VBoxContainer
## VERSION (pestaña del inicio, 2026-10-01, pedido: "una opcion para que los jugadores actualicen la aplicacion, para
## indicarles que hay una version nueva... con un botoncito, sin estar desplegando el servidor", y "que no le aparezca a
## los que ya tienen la version actualizada").
## Es el ajuste del juego `version_app` = {ultima, minima, url, mensaje} (servidor/index.js, validarJuego; GET y POST
## /admin/juego, como los de la pestaña JUEGO). El juego (godot/scripts/aviso_version.gd) compara su numero
## (Settings.VERSION_APP = el version code del APK; tools/subir_version.py lo sube) y:
##   - menor que ULTIMA: aviso con ACTUALIZAR y MAS TARDE
##   - menor que la ultima y OBLIGATORIA encendido: sin MAS TARDE (minima = ultima)
##   - igual o mayor: nada
## Llega a los jugadores al abrir el juego y, a los que estan dentro con sesion, en unos segundos (el latido).

const URL_TIENDA := "https://play.google.com/store/apps/details?id=com.breach.voxelfps"

var app
var cargada := false
var _caja: VBoxContainer
var _estado: Label
var _ultima: LineEdit
var _obligatoria: JuegoPiezas.Interruptor
var _url: LineEdit
var _mensaje: LineEdit
var _guardar: Boton
var _actual := {}
var _pedido := 0


func _init(p_app) -> void:
	app = p_app
	add_theme_constant_override("separation", 14)


func _ready() -> void:
	var tj := Tema.tarjeta(18, Color(Tema.ACENTO, 0.07))
	var h := Tema.hbox(14)
	tj.add_child(h)
	var ic := Iconos.new("bajar", Tema.ACENTO, 34)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	h.add_child(Tema.parrafo("Cuando subas un APK nuevo, pon aquí su número de versión. A los jugadores que tengan uno MENOR " +
		"les sale un aviso para descargarlo al abrir el juego; a los que ya lo tienen, nada.", 14, Tema.TEXTO2))
	add_child(tj)
	_estado = Tema.linea("", 15, Tema.TEXTO, 700)
	add_child(_estado)
	_caja = Tema.vbox(14)
	add_child(_caja)


func cargar() -> void:
	cargada = true
	_pedido += 1
	var mio := _pedido
	for n in _caja.get_children():
		n.queue_free()
	_caja.add_child(Girador.new())
	_estado.text = "Cargando…"
	var r: Dictionary = await app.api.pedir("GET", "/admin/juego")
	if mio != _pedido or not is_inside_tree():
		return
	for n in _caja.get_children():
		n.queue_free()
	if not r["ok"]:
		_estado.text = "No se pudo cargar"
		_caja.add_child(Tema.vacio("alerta", Tema.frase(String(r["error"])), "Toca actualizar arriba para reintentar."))
		return
	var ef = (r["datos"].get("efectivo", {}) as Dictionary).get("version_app", null)
	if not ef is Dictionary:
		_estado.text = "El servidor todavía no tiene esta opción"
		_caja.add_child(Tema.vacio("servidor", "Falta actualizar el servidor una vez",
			"Hay que desplegar el servidor (servidor\\desplegar.bat) una sola vez para que esta pestaña funcione."))
		return
	_actual = ef
	_armar()


func _armar() -> void:
	var ultima := int(_actual.get("ultima", 0))
	var minima := int(_actual.get("minima", 0))
	if ultima <= 0:
		_estado.text = "Ahora: sin aviso"
	else:
		_estado.text = "Ahora: última versión %d · %s" % [ultima, "OBLIGATORIA" if minima >= ultima else "se puede dejar para más tarde"]
	# el numero, con un +1 al lado (lo normal: cada APK nuevo sube uno)
	_caja.add_child(Tema.seccion("Última versión"))
	var fila := Tema.hbox(10)
	_ultima = Tema.campo_numero("número del APK nuevo", ultima if ultima > 0 else -1)
	fila.add_child(_ultima)
	var mas := Boton.new("+1", "mas", "secundario", 52)
	mas.custom_minimum_size.x = 92
	mas.tocado.connect(func():
		_ultima.text = str(maxi(int(_ultima.text) if _ultima.text != "" else ultima, 0) + 1))
	fila.add_child(mas)
	_caja.add_child(fila)
	_caja.add_child(Tema.parrafo("Es el «version code» del APK (sale al exportarlo con tools/subir_version.py).", 12, Tema.TEXTO3))
	# obligatoria
	var h := Tema.hbox(12)
	var tv := Tema.vbox(3)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(Tema.parrafo("Obligatoria", 15, Tema.TEXTO, 700))
	tv.add_child(Tema.parrafo("Sin «más tarde»: quien no actualice no puede seguir jugando.", 12, Tema.TEXTO3))
	h.add_child(tv)
	_obligatoria = JuegoPiezas.Interruptor.new(ultima > 0 and minima >= ultima)
	h.add_child(_obligatoria)
	_caja.add_child(h)
	# enlace y mensaje
	_caja.add_child(Tema.seccion("Dónde se descarga"))
	_url = Tema.campo("vacío = la ficha del juego en la Play Store", false, String(_actual.get("url", "")))
	_caja.add_child(_url)
	_caja.add_child(Tema.seccion("Mensaje (opcional)"))
	_mensaje = Tema.campo("vacío = «Ya puedes descargar la versión nueva…»", false, String(_actual.get("mensaje", "")))
	_mensaje.max_length = 300
	_caja.add_child(_mensaje)
	_caja.add_child(Tema.espacio(4))
	_guardar = Boton.new("Avisar a los jugadores", "megafono", "primario", 56)
	_guardar.tocado.connect(_enviar)
	_caja.add_child(_guardar)
	var quitar := Boton.new("Quitar el aviso", "cerrar", "secundario", 50)
	quitar.tocado.connect(func():
		var d: Dialogo = app.dialogo("Quitar el aviso", "cerrar", Tema.TEXTO2)
		d.cuerpo.add_child(Tema.parrafo("Nadie verá el aviso de versión nueva hasta que pongas otra.", 15))
		d.boton("Cancelar").tocado.connect(d.cerrar)
		d.boton("Quitar", "primario").tocado.connect(func():
			d.cerrar()
			_mandar(null)))
	_caja.add_child(quitar)


func _enviar() -> void:
	var n := int(_ultima.text) if _ultima.text.strip_edges() != "" else 0
	if n <= 0:
		app.avisar("Pon el número de la versión nueva", false)
		return
	var url := _url.text.strip_edges()
	if url != "" and not (url.begins_with("https://") or url.begins_with("http://") or url.begins_with("market://")):
		app.avisar("El enlace tiene que empezar por https://", false)
		return
	_mandar({"ultima": n, "minima": n if _obligatoria.si else 0, "url": url, "mensaje": _mensaje.text.strip_edges()})


func _mandar(valor) -> void:
	if is_instance_valid(_guardar):
		_guardar.cargando = true
	var r: Dictionary = await app.api.pedir("POST", "/admin/juego", {"clave": "version_app", "valor": valor})
	if not is_inside_tree():
		return
	if is_instance_valid(_guardar):
		_guardar.cargando = false
	if not r["ok"]:
		app.avisar(Tema.frase(String(r["error"])), false)
		return
	app.avisar("Aviso quitado" if valor == null else "Listo: los que tengan una versión menor que %d verán el aviso" % int(valor["ultima"]))
	cargar()
