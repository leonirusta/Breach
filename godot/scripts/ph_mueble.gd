extends StaticBody3D
## UN MUEBLE DE LA CASA (PROP HUNT, 2026-10-21). La malla y la caja de choque salen de ph_muebles.gd. Aguanta balas
## (`danar_bala`, la ruta de player.fire para lo que no es una persona) y explosiones (`take_damage`, Combat) y al
## acabarsele la vida SE ROMPE: salta en trozos de sus propios colores (effects.trozos_mazo, solo imagen), suena a su
## material y deja de chocar. Las teles llevan su pantalla (ph_tele.gd): con los golpes se rompe y al romperse se apaga.
## Disparar a un mueble no castiga al cazador (pedido): solo lo rompe.

const Muebles := preload("res://scripts/ph_muebles.gd")
const TeleScript := preload("res://scripts/ph_tele.gd")

var tipo := ""
var vida := 100.0
var vida_max := 100.0
var roto := false
var efectos = null          ## effects.gd de la partida (para los trozos)
var tele = null             ## la pantalla, si es una tele
var _pantalla_rota := false
var _pantalla_t := 0
var _malla: MeshInstance3D
var _choque: CollisionShape3D
var al_romper: Callable = Callable()   ## prop_hunt.gd: para avisar a las demas pantallas


func montar(p_tipo: String, p_efectos) -> void:
	tipo = p_tipo
	efectos = p_efectos
	name = "Mueble_" + tipo
	add_to_group("ph_muebles")
	collision_layer = 1
	collision_mask = 0
	_malla = MeshInstance3D.new()
	_malla.mesh = Muebles.malla(tipo)
	add_child(_malla)
	var a: AABB = Muebles.caja_choque(tipo)
	var forma := BoxShape3D.new()
	forma.size = a.size
	_choque = CollisionShape3D.new()
	_choque.shape = forma
	_choque.position = a.get_center()
	add_child(_choque)
	vida_max = Muebles.vida(tipo)
	vida = vida_max
	var pa: Dictionary = Muebles.pantalla(tipo)
	if not pa.is_empty():
		tele = TeleScript.new()
		tele.montar(pa, tipo == "tele")
		add_child(tele)


func centro() -> Vector3:
	return global_transform * Muebles.caja_choque(tipo).get_center()


func danar_bala(d: float, punto: Vector3, dir: Vector3) -> bool:
	if roto:
		return false
	_golpe(d, punto)
	return true


func take_damage(d: float, _push: Vector3 = Vector3.ZERO) -> void:
	if not roto:
		_golpe(d, centro())


func _golpe(d: float, punto: Vector3) -> void:
	# LA TELE (2026-10-21, pedido): el primer golpe le rompe la PANTALLA (grieta, pixeles y negro) y el siguiente la tele
	if tele != null:
		if not _pantalla_rota:
			_pantalla_rota = true
			_pantalla_t = Time.get_ticks_msec()
			tele.golpe(to_local(punto), 1.0)
			tele.apagar_rota()
			Audio.rotura("cristal", "s", punto, 0.0, 30.0, Audio.PRI_HIGH)
			if efectos and efectos.has_method("sparks"):
				efectos.sparks(punto, global_transform.basis.z)
			return
		# (los perdigones de una escopeta o una rafaga llegan juntos: el segundo golpe tiene que ser OTRO golpe)
		if Time.get_ticks_msec() - _pantalla_t > 250:
			romper()
		return
	vida -= d
	# (sin trozos al golpear, pedido: "las particulas, cuando se rompen")
	if vida <= 0.0:
		romper()
	else:
		Audio.choque(Muebles.CLASE.get(tipo, "madera"), "s", punto, -6.0, 30.0, Audio.PRI_LOW)


## Se rompe: trozos de cada color, sonido de su material, y fuera la malla y el choque (la tele se apaga antes)
func romper() -> void:
	if roto:
		return
	roto = true
	if al_romper.is_valid():
		al_romper.call()
	var c0 := centro()
	if tele != null:
		tele.apagar_rota()
	if efectos:
		var vistos := {}
		for b in Muebles.cajas(tipo):
			var k: String = (b[6] as Color).to_html(false)
			if vistos.has(k) or vistos.size() >= 6:
				continue
			vistos[k] = true
			var p: Vector3 = global_transform * Vector3((b[0] + b[3]) * 0.5, (b[1] + b[4]) * 0.5, (b[2] + b[5]) * 0.5)
			if efectos.has_method("trozos_mazo"):
				efectos.trozos_mazo(p, Vector3.UP, b[6], 10)
		if efectos.has_method("dust"):
			efectos.dust(c0, 0.6)
	var clase: String = Muebles.CLASE.get(tipo, "madera")
	var vol: float = Muebles.caja_choque(tipo).get_volume()
	Audio.rotura(clase, "l" if vol > 0.6 else ("m" if vol > 0.08 else "s"), c0, 0.0, 40.0, Audio.PRI_HIGH)
	_choque.disabled = true
	_malla.visible = false
	if tele != null:
		tele.visible = false
