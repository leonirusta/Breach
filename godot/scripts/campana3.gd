extends "res://scripts/campana.gd"
## EPISODIO 3 DE LA CAMPAÑA: "EL AMANECER" (campana_amanecer, tools/generar_mapa_campana3.py). 2026-09-27.
##
## El barco del episodio 2 os deja AL AMANECER en el muelle de un pueblo de pescadores en cuesta. La radio de la
## ciudadela, arriba del cerro, llama al helicoptero. Hay que subir cuatro terrazas, y cada salto es un PUZZLE:
##   1. EL CONTENEDOR del andamio: se revientan los puntales, cae pegado al malecon y se trepa por el.
##   2. LA PERSIANA del pasaje: uno trepa (contenedor de basura -> quiosco -> balcon) y tira de la palanca.
##   3. LA CHIMENEA de la conservera: se revienta su pie y cae como un arbol sobre el barranco: se cruza por encima.
##   4. EL MONTACARGAS del acantilado: se arranca el generador (ruido: horda, y un Tank), todos dentro y arriba.
##   5. EL PUENTE LEVADIZO: se rompe la tranca que aguanta el contrapeso y el puente cae sobre el foso.
##   Y el final de siempre: la radio, las oleadas trepando las murallas y el helicoptero. Al escapar, la salida de
##   cine: el helicoptero despega y se va hacia el sol, sobre el mar.
##
## Los objetos que caen (contenedor, chimenea, puente) son OBJETOS, no voxels, para que caigan igual en todas las
## pantallas; se puede trepar a ellos (grupo "trepable", ver player._rayo_trepa). Lo que se rompe son voxels.
## Todo lo decide el anfitrion y lo avisa por los eventos de la campaña.

const BARCO_SALE := 26.0          ## s que tarda el barco en irse por el horizonte
const TREPABLE := "trepable"

var _cont: StaticBody3D = null
var _cont_caido := false
var _persiana: StaticBody3D = null
var _persiana_abierta := false
var _barrera_persiana := AABB()
var _chim_pivote: Node3D = null
var _chim_cuerpo: StaticBody3D = null
var _chim_caida := false
var _gen_estado := 0              ## 0 apagado, 1 calentando, 2 listo
var _gen_t := 0.0
var _gen_tank := false
var _gen_ruido: AudioStreamPlayer3D = null
var _cabina: AnimatableBody3D = null
var _reja_oeste: Node3D = null
var _reja_este: Node3D = null
var _cabina_luz: OmniLight3D = null
var _boton_luz: OmniLight3D = null
# LOS MANDOS DE VERDAD (mandos.gd, 2026-09-28: "me dice toca la palanca y no hay ninguna palanca")
var _mando_palanca: Node3D = null      ## la palanca de la persiana, en la caja amarilla del balcon
var _mando_generador: Node3D = null    ## el panel de arranque, en la cara sur de la caseta
var _mando_botonera: Node3D = null     ## la botonera colgante del montacargas (va con la cabina)
var _asc_estado := 0              ## 0 abajo, 1 subiendo, 2 arriba
var _asc_t := 0.0
var _asc_ruido: AudioStreamPlayer3D = null
var _asc_atasco := false
var _bots_cabina: Array = []      ## [[bot, offset xz]]
var _puente_pivote: Node3D = null
var _puente_bajado := false
var _contrapeso: Node3D = null
var _cadenas: Array = []          ## [MeshInstance3D] (las del puente)
var _cadena_contrapeso: MeshInstance3D = null
var _barrera_puente := AABB()
var _barco: Node3D = null
var _barco_t := -1.0
var _carteles: Dictionary = {}
var _comprobar_t := 0.0
var _llenos: Dictionary = {}      ## id -> [voxels por rodaja al empezar] (para saber si esta CORTADO)
var _cine_final_hecha := false
var _cine_final_corriendo := false


# ======================================================================================================
# LA ESCENA
# ======================================================================================================
func _montar_escena() -> void:
	super._montar_escena()
	_arreglar_puertas_refugio()
	_montar_contenedor()
	_montar_persiana()
	_montar_chimenea()
	_montar_montacargas()
	_montar_puente()
	_montar_barco()
	_montar_mandos()
	var c: Dictionary = cfg.get("contenedor", {})
	if not c.is_empty():
		var pz: Array = c["puntales"]
		var cen := Vector3.ZERO
		for p in pz:
			cen += (_v([p[0], p[1], p[2]]) + _v([p[3], p[4], p[5]])) * 0.5
		cen /= maxf(1.0, pz.size())
		_rotulo("contenedor", "REVENTAD LOS PUNTALES", cen + Vector3(0, 0.6, 3.2), Color(0.95, 0.75, 0.1))
	var ch: Dictionary = cfg.get("chimenea", {})
	if not ch.is_empty():
		var b: Array = ch["base"]
		_rotulo("chimenea", "REVENTAD EL PIE", Vector3((float(b[0]) + float(b[3])) / 2 - 2.6, float(b[1]) + 2.8, (float(b[2]) + float(b[5])) / 2), Color(0.95, 0.3, 0.1))
	var pu: Dictionary = cfg.get("puente", {})
	if not pu.is_empty():
		var t: Array = pu["tranca"]
		_rotulo("tranca", "ROMPED LA TRANCA", Vector3(float(t[0]) - 1.5, float(t[1]) + 1.2, (float(t[2]) + float(t[5])) / 2), Color(0.95, 0.3, 0.1))


func _rotulo(id: String, texto: String, p: Vector3, color: Color) -> void:
	# SIN CARTELES FLOTANTES DE PISTA (2026-09-28, pedido: "que no aparezcan textos flotando diciendo rompe tal cosa
	# para subir; quiero que el jugador piense y mire el entorno"). Las llamadas se quedan (dicen que es cada cosa, para
	# quien lea el codigo), pero ya no pintan nada. Lo impreso EN los objetos (bidones, carteles de puertas, paneles)
	# sigue: eso es parte del mundo, no una pista flotando.
	return
	@warning_ignore("unreachable_code")
	var c := Label3D.new()
	c.text = texto
	c.font_size = 80
	c.pixel_size = 0.01
	c.modulate = color
	c.outline_size = 14
	c.outline_modulate = Color(0, 0, 0, 0.85)
	c.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(c)
	c.global_position = p
	_carteles[id] = c


func _quitar_cartel(id: String) -> void:
	if _carteles.has(id) and is_instance_valid(_carteles[id]):
		_carteles[id].queue_free()
	_carteles.erase(id)


func _caja_mesh(padre: Node3D, tam: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = tam
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	padre.add_child(mi)
	return mi


func _colision_caja(padre: Node3D, tam: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = tam
	cs.shape = bs
	cs.position = pos
	padre.add_child(cs)


## LAS PUERTAS DEL REFUGIO. La base las pone a ras del suelo del episodio 1 (Y = 1) y mirando en Z; aqui el refugio
## esta a Y2 y la salida da al ESTE.
func _arreglar_puertas_refugio() -> void:
	var ref: Dictionary = cfg.get("refugio", {})
	if ref.is_empty():
		return
	var y := float(ref.get("suelo", 1.0))
	if is_instance_valid(_bisagra_entrada):
		_bisagra_entrada.global_position.y = y + 1.35
	if is_instance_valid(_puerta_refugio):
		var ps: Array = ref["puerta_salida"]
		_puerta_refugio.rotation.y = PI / 2
		_puerta_refugio.global_position = Vector3(float(ps[0]) - 0.2, y + 1.35, float(ps[1]))


## Se abren deslizandose a lo largo de su propia hoja (la de la salida mira al este: se desliza en Z)
func _abrir_puerta(sb: StaticBody3D) -> void:
	for c in sb.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = true
	var tw := sb.create_tween()
	tw.tween_property(sb, "global_position", sb.global_position - sb.global_transform.basis.x * 1.7, 1.2).set_trans(Tween.TRANS_QUAD)
	Audio.bf3d("destru/metal", sb.global_position, -2.0, 30.0, Audio.PRI_MID)


func _cerrar_entrada_refugio() -> void:
	if not is_instance_valid(_bisagra_entrada) or absf(_bisagra_entrada.rotation.y) < 0.01:
		return
	var ref: Dictionary = cfg.get("refugio", {})
	var pe: Array = ref.get("puerta_entrada", [0, 0])
	var y := float(ref.get("suelo", 1.0))
	var hueco := Vector3(float(pe[0]), y, float(pe[1]))
	if is_instance_valid(jugador):
		var jp: Vector3 = jugador.global_position
		if Vector2(jp.x - hueco.x, jp.z - hueco.z).length() < 1.6:
			jugador.global_position = Vector3(jp.x, jp.y, hueco.z + 1.8)
	var tw := create_tween()
	tw.tween_property(_bisagra_entrada, "rotation:y", 0.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): Audio.bf3d("destru/metal", hueco + Vector3.UP, 0.0, 40.0, Audio.PRI_MID))
	CriaturaScript.barreras.append(AABB(Vector3(hueco.x - 1.2, y - 1.0, hueco.z - 0.8), Vector3(2.4, 5.5, 1.2)))


# ------------------------------------------------------------------ 1. el contenedor
func _montar_contenedor() -> void:
	var c: Dictionary = cfg.get("contenedor", {})
	if c.is_empty():
		return
	var k: Array = c["caja"]
	var mn := _v([k[0], k[1], k[2]])
	var mx := _v([k[3], k[4], k[5]])
	var tam := mx - mn
	_cont = StaticBody3D.new()
	_cont.name = "Contenedor"
	_cont.collision_layer = 1
	_cont.collision_mask = 0
	_cont.add_to_group(TREPABLE)
	add_child(_cont)
	_cont.global_position = (mn + mx) * 0.5
	_colision_caja(_cont, tam, Vector3.ZERO)
	var azul := _mm(Color(0.10, 0.30, 0.58), 0.45, 0.55)
	var oscuro := _mm(Color(0.06, 0.18, 0.36), 0.45, 0.6)
	var oxido := _mm(Color(0.45, 0.22, 0.10), 0.3, 0.8)
	_caja_mesh(_cont, tam, Vector3.ZERO, azul)
	# la chapa ondulada (costillas en los lados largos) y el marco
	var n := int(tam.x / 0.3)
	for i in n:
		var x := -tam.x / 2 + (i + 0.5) * tam.x / n
		for s in [-1, 1]:
			_caja_mesh(_cont, Vector3(0.1, tam.y - 0.24, 0.05), Vector3(x, 0, s * (tam.z / 2 + 0.02)), oscuro)
	for s in [-1, 1]:
		_caja_mesh(_cont, Vector3(tam.x + 0.04, 0.12, tam.z + 0.04), Vector3(0, s * (tam.y / 2 - 0.06), 0), oscuro)
	# las puertas del fondo con sus cierres, un churrete de oxido y la marca
	_caja_mesh(_cont, Vector3(0.06, tam.y - 0.3, tam.z - 0.2), Vector3(tam.x / 2 + 0.03, 0, 0), oscuro)
	for z in [-0.5, -0.2, 0.2, 0.5]:
		_caja_mesh(_cont, Vector3(0.05, tam.y - 0.4, 0.04), Vector3(tam.x / 2 + 0.07, 0, z * tam.z * 0.8), _mm(Color(0.7, 0.7, 0.72), 0.8, 0.4))
	_caja_mesh(_cont, Vector3(1.4, 0.9, 0.02), Vector3(-1.2, 0.25, tam.z / 2 + 0.05), _mm(Color(0.92, 0.92, 0.9), 0.1, 0.6))
	_caja_mesh(_cont, Vector3(0.5, tam.y * 0.7, 0.02), Vector3(1.8, -0.2, tam.z / 2 + 0.06), oxido)


func _contenedor_cae() -> void:
	if _cont_caido or not is_instance_valid(_cont):
		return
	_cont_caido = true
	_quitar_cartel("contenedor")
	var c: Dictionary = cfg["contenedor"]
	var k: Array = c["caja"]
	var alto := float(k[4]) - float(k[1])
	var fin_y := float(c.get("suelo", 1.0)) + alto * 0.5
	var p0 := _cont.global_position
	var tw := create_tween()
	tw.tween_property(_cont, "global_position:y", fin_y, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_cont, "rotation:z", 0.05, 0.55)
	tw.tween_callback(func():
		_golpe(Vector3(p0.x, fin_y - alto * 0.5, p0.z), 1.6, "destru/metal")
		_tallar_caja(c["puntales"], 0.6))
	tw.tween_property(_cont, "global_position:y", fin_y + 0.14, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_cont, "rotation:z", -0.02, 0.12)
	tw.tween_property(_cont, "global_position:y", fin_y, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_cont, "rotation:z", 0.0, 0.14)
	tw.tween_callback(func(): Audio.bf3d("destru/metal", _cont.global_position, 0.0, 40.0, Audio.PRI_MID))
	_mensaje_local("¡EL CONTENEDOR HA CAÍDO! Trepad: cajas → contenedor → MALECÓN")


## Un golpe fuerte: sonido, polvo y temblor de camara para quien este cerca
func _golpe(p: Vector3, fuerza: float, clave: String) -> void:
	Audio.bf3d(clave, p, 6.0, 90.0, Audio.PRI_HIGH)
	var fx = jugador.get("effects") if is_instance_valid(jugador) else null
	if fx and fx.has_method("dust"):
		fx.dust(p + Vector3.UP * 0.4, fuerza)
		fx.dust(p + Vector3(1.5, 0.3, 0.5), fuerza * 0.7)
		fx.dust(p + Vector3(-1.5, 0.3, -0.5), fuerza * 0.7)
	if is_instance_valid(jugador) and jugador.has_method("add_shake"):
		var d: float = jugador.global_position.distance_to(p)
		if d < 30.0:
			jugador.add_shake(clampf(0.6 * (1.0 - d / 30.0) * fuerza, 0.05, 0.8))


## Lo que quede de unos apoyos (puntales, el pie de la chimenea) desaparece al caer lo de encima: si no, el
## objeto caido se apoyaria en los munones. Cada maquina lo hace al recibir el evento (el tallado es determinista).
func _tallar_caja(cajas: Array, radio: float) -> void:
	for k in cajas:
		var mn := _v([k[0], k[1], k[2]])
		var mx := _v([k[3], k[4], k[5]])
		var y := mn.y + radio * 0.5
		while y < mx.y + 0.3:
			var c := Vector3((mn.x + mx.x) * 0.5, y, (mn.z + mx.z) * 0.5)
			world.carve_beam(c - Vector3((mx.x - mn.x) * 0.5 + 0.2, 0, 0), Vector3.RIGHT, (mx.x - mn.x) + 0.4, radio, 255, true)
			y += radio * 0.8


# ------------------------------------------------------------------ 2. la persiana
func _montar_persiana() -> void:
	var p: Dictionary = cfg.get("persiana", {})
	if p.is_empty():
		return
	var r: Array = p["rect"]
	var mn := _v([r[0], r[1], r[2]])
	var mx := _v([r[3], r[4], r[5]])
	var tam := mx - mn
	_persiana = StaticBody3D.new()
	_persiana.name = "Persiana"
	_persiana.collision_layer = 1
	add_child(_persiana)
	_persiana.global_position = (mn + mx) * 0.5
	_colision_caja(_persiana, Vector3(tam.x, tam.y, 0.14), Vector3.ZERO)
	var gris := _mm(Color(0.52, 0.54, 0.56), 0.7, 0.45)
	var gris2 := _mm(Color(0.42, 0.44, 0.46), 0.7, 0.5)
	var n := int(tam.y / 0.1)
	for i in n:
		_caja_mesh(_persiana, Vector3(tam.x, 0.09, 0.08 if i % 2 == 0 else 0.1), Vector3(0, -tam.y / 2 + (i + 0.5) * tam.y / n, 0), gris if i % 2 == 0 else gris2)
	_caja_mesh(_persiana, Vector3(tam.x, 0.16, 0.14), Vector3(0, -tam.y / 2 + 0.08, 0), _mm(Color(0.2, 0.2, 0.22), 0.7, 0.5))
	# una pintada roja "CERRADO" (de lejos, una banda) y el candado
	_caja_mesh(_persiana, Vector3(tam.x * 0.7, 0.35, 0.02), Vector3(0, 0.3, 0.07), _mm(Color(0.7, 0.08, 0.06), 0.0, 0.9))
	_caja_mesh(_persiana, Vector3(0.18, 0.22, 0.1), Vector3(0.6, -tam.y / 2 + 0.3, 0.1), _mm(Color(0.75, 0.62, 0.2), 0.8, 0.3))
	_barrera_persiana = AABB(Vector3(mn.x - 0.3, mn.y - 1.0, mn.z - 1.0), Vector3(tam.x + 0.6, tam.y + 2.0, 2.2))
	CriaturaScript.barreras.append(_barrera_persiana)


func _persiana_sube() -> void:
	if _persiana_abierta or not is_instance_valid(_persiana):
		return
	_persiana_abierta = true
	CriaturaScript.barreras.erase(_barrera_persiana)
	var tw := _persiana.create_tween()
	tw.tween_property(_persiana, "global_position:y", _persiana.global_position.y + 3.25, 3.0).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		for c in _persiana.get_children():
			if c is CollisionShape3D:
				(c as CollisionShape3D).disabled = true)
	Audio.play3d("gen/persiana/sube", _persiana.global_position, 4.0, 0.02, 60.0, Audio.PRI_HIGH)
	_mensaje_local("¡LA PERSIANA SUBE! Al PASAJE, y cuesta arriba")


# ------------------------------------------------------------------ 3. la chimenea
func _montar_chimenea() -> void:
	var ch: Dictionary = cfg.get("chimenea", {})
	if ch.is_empty():
		return
	var largo := float(ch.get("largo", 15.0))
	var r := float(ch.get("radio", 0.95))
	var base: Array = ch["base"]
	var alto_base := float(base[4]) - float(base[1])
	_chim_pivote = Node3D.new()
	_chim_pivote.name = "Chimenea"
	add_child(_chim_pivote)
	_chim_pivote.global_position = _v(ch["pivote"])
	_chim_cuerpo = StaticBody3D.new()
	_chim_cuerpo.collision_layer = 1
	_chim_cuerpo.add_to_group(TREPABLE)
	_chim_pivote.add_child(_chim_cuerpo)
	_chim_cuerpo.position = Vector3(-r, alto_base + largo / 2, 0)
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = r * 0.92
	cy.height = largo
	cs.shape = cy
	_chim_cuerpo.add_child(cs)
	# LA PASARELA: una losa plana a lo largo del lomo (tumbada queda ENCIMA): sobre un cilindro se resbalaria
	_colision_caja(_chim_cuerpo, Vector3(0.3, largo, 1.3), Vector3(-(r - 0.15), 0, 0))
	var ladrillo := _mm(Color(0.62, 0.30, 0.20), 0.0, 0.9)
	var anillo := _mm(Color(0.78, 0.72, 0.62), 0.0, 0.8)
	var hollin := _mm(Color(0.1, 0.09, 0.08), 0.0, 1.0)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * 0.78
	cm.bottom_radius = r
	cm.height = largo
	cm.radial_segments = 16
	mi.mesh = cm
	mi.material_override = ladrillo
	_chim_cuerpo.add_child(mi)
	for k in range(1, int(largo / 1.6)):
		var a := MeshInstance3D.new()
		var am := CylinderMesh.new()
		var rr: float = lerpf(r, r * 0.78, (k * 1.6) / largo) + 0.03
		am.top_radius = rr
		am.bottom_radius = rr
		am.height = 0.14
		am.radial_segments = 16
		a.mesh = am
		a.material_override = anillo
		a.position = Vector3(0, -largo / 2 + k * 1.6, 0)
		_chim_cuerpo.add_child(a)
	var boca := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = r * 0.92
	bm.bottom_radius = r * 0.82
	bm.height = 0.5
	boca.mesh = bm
	boca.material_override = hollin
	boca.position = Vector3(0, largo / 2 + 0.2, 0)
	_chim_cuerpo.add_child(boca)


func _chimenea_cae() -> void:
	if _chim_caida or not is_instance_valid(_chim_pivote):
		return
	_chim_caida = true
	_quitar_cartel("chimenea")
	var ch: Dictionary = cfg["chimenea"]
	var base: Array = ch["base"]
	var alto_base := float(base[4]) - float(base[1])
	var largo := float(ch.get("largo", 15.0))
	Audio.play3d("gen/derrumbe/chimenea", _chim_pivote.global_position + Vector3.UP * 3.0, 8.0, 0.02, 140.0, Audio.PRI_HIGH)
	var tw := create_tween()
	# el pie cede: la chimenea baja de golpe hasta el suelo y se queda un instante temblando
	tw.tween_property(_chim_cuerpo, "position:y", largo / 2, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		_tallar_caja([base], 0.7)
		_golpe(_chim_pivote.global_position, 1.2, "destru/derrumbe_medio"))
	tw.tween_property(_chim_pivote, "rotation:z", -0.05, 0.9).set_trans(Tween.TRANS_SINE)
	# y vuelca, cada vez mas deprisa, como un arbol
	tw.tween_property(_chim_pivote, "rotation:z", -PI / 2, 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		var cae := _chim_pivote.global_position + Vector3(largo * 0.7, 0.5, 0)
		_golpe(cae, 2.0, "destru/derrumbe")
		_golpe(_chim_pivote.global_position + Vector3(largo, 0.5, 0), 1.4, "destru/derrumbe_grave"))
	tw.tween_property(_chim_pivote, "rotation:z", -PI / 2 + 0.035, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_chim_pivote, "rotation:z", -PI / 2, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_mensaje_local("¡LA CHIMENEA CAE! Trepad a ella y cruzad el barranco")


# ------------------------------------------------------------------ 4. el montacargas
func _montar_montacargas() -> void:
	var m: Dictionary = cfg.get("montacargas", {})
	if m.is_empty():
		return
	var c: Array = m["cabina"]
	var mn := _v([c[0], c[1], c[2]])
	var mx := _v([c[3], c[4], c[5]])
	var w := mx.x - mn.x
	var d := mx.z - mn.z
	var h := 2.7
	_cabina = AnimatableBody3D.new()
	_cabina.name = "Montacargas"
	_cabina.sync_to_physics = true
	_cabina.collision_layer = 1
	add_child(_cabina)
	_cabina.global_position = Vector3((mn.x + mx.x) / 2, mn.y, (mn.z + mx.z) / 2)
	var amarillo := _mm(Color(0.85, 0.66, 0.08), 0.5, 0.5)
	var rejilla := _mm(Color(0.16, 0.16, 0.17), 0.7, 0.6)
	var suelo := _mm(Color(0.30, 0.31, 0.32), 0.8, 0.45)
	# el suelo (de chapa estriada) y el techo
	_colision_caja(_cabina, Vector3(w, 0.2, d), Vector3(0, -0.08, 0))
	_caja_mesh(_cabina, Vector3(w, 0.2, d), Vector3(0, -0.08, 0), suelo)
	_colision_caja(_cabina, Vector3(w, 0.12, d), Vector3(0, h + 0.06, 0))
	_caja_mesh(_cabina, Vector3(w, 0.12, d), Vector3(0, h + 0.06, 0), rejilla)
	# los lados norte y sur: rejilla con su marco amarillo
	for s in [-1, 1]:
		_colision_caja(_cabina, Vector3(w, h, 0.08), Vector3(0, h / 2, s * (d / 2 - 0.04)))
		_caja_mesh(_cabina, Vector3(w, h, 0.05), Vector3(0, h / 2, s * (d / 2 - 0.04)), rejilla)
		_caja_mesh(_cabina, Vector3(w + 0.04, 0.12, 0.1), Vector3(0, h - 0.06, s * (d / 2 - 0.04)), amarillo)
		_caja_mesh(_cabina, Vector3(w + 0.04, 0.12, 0.1), Vector3(0, 1.1, s * (d / 2 - 0.04)), amarillo)
	for x in [-w / 2 + 0.06, w / 2 - 0.06]:
		for z in [-d / 2 + 0.06, d / 2 - 0.06]:
			_caja_mesh(_cabina, Vector3(0.12, h, 0.12), Vector3(x, h / 2, z), amarillo)
	# las dos rejas (oeste: la de abajo, abierta; este: la de arriba, cerrada)
	_reja_oeste = _reja(Vector3(-w / 2 + 0.03, 0, 0), d, h, rejilla, amarillo)
	_reja_oeste.position.y = h - 0.2                    # recogida arriba: se entra
	_reja_este = _reja(Vector3(w / 2 - 0.03, 0, 0), d, h, rejilla, amarillo)
	# la botonera, su luz (roja hasta que hay corriente) y la bombilla de la cabina
	# OJO: aqui la escena aun no esta en el arbol y `_cabina.global_position` se lee como (0,0,0): la botonera (y su
	# luz) acababan a 120 m, por eso "no habia nada que tocar". Se mide desde el centro de la cabina, que se sabe.
	var b: Vector3 = _v(m["boton"]) - Vector3((mn.x + mx.x) / 2, mn.y, (mn.z + mx.z) / 2)
	# (la botonera de verdad la pone _montar_mandos: en la cara de la caja naranja del mapa que da a la cabina)
	_boton_luz = OmniLight3D.new()
	_boton_luz.light_color = Color(1.0, 0.15, 0.1)
	_boton_luz.light_energy = 1.2
	_boton_luz.omni_range = 2.5
	_boton_luz.position = Vector3(b.x + 0.3, 1.4, b.z)
	_cabina.add_child(_boton_luz)
	_cabina_luz = OmniLight3D.new()
	_cabina_luz.light_color = Color(1.0, 0.9, 0.7)
	_cabina_luz.light_energy = 0.0
	_cabina_luz.omni_range = 6.0
	_cabina_luz.position = Vector3(0, h - 0.3, 0)
	_cabina.add_child(_cabina_luz)


func _reja(pos: Vector3, d: float, h: float, rejilla: Material, marco: Material) -> Node3D:
	var n := StaticBody3D.new()
	n.collision_layer = 1
	_cabina.add_child(n)
	n.position = pos
	_colision_caja(n, Vector3(0.08, h, d - 0.1), Vector3(0, h / 2, 0))
	for i in int(d / 0.25):
		_caja_mesh(n, Vector3(0.04, h, 0.04), Vector3(0, h / 2, -d / 2 + 0.15 + i * 0.25), rejilla)
	_caja_mesh(n, Vector3(0.1, 0.1, d - 0.1), Vector3(0, 0.1, 0), marco)
	_caja_mesh(n, Vector3(0.1, 0.1, d - 0.1), Vector3(0, h - 0.1, 0), marco)
	return n


func _cabina_rect() -> Array:
	var c: Array = (cfg.get("montacargas", {}) as Dictionary).get("cabina", [0, 0, 0, 0, 0, 0])
	return [float(c[0]) + 0.1, float(c[2]) + 0.1, float(c[3]) - 0.1, float(c[5]) - 0.1]


## La cabina sube (todas las maquinas a la vez con el evento). La mueve _physics_process: asi arrastra a los que
## van de pie en ella.
func _ascensor_sube() -> void:
	if _asc_estado != 0 or not is_instance_valid(_cabina):
		return
	_asc_estado = 1
	_asc_t = 0.0
	_asc_atasco = false
	var tw := _reja_oeste.create_tween()
	tw.tween_property(_reja_oeste, "position:y", 0.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	Audio.play3d("gen/ascensor/reja", _cabina.global_position, 0.0, 0.02, 30.0, Audio.PRI_MID)
	get_tree().create_timer(0.9).timeout.connect(func():
		Audio.play3d("gen/ascensor/arranque", _cabina.global_position + Vector3.UP * 2.0, 2.0, 0.0, 50.0, Audio.PRI_HIGH))
	_asc_ruido = _bucle_directo("res://sounds/gen/ascensor/bucle1.ogg", _cabina, Vector3(0, 3.5, 0), -2.0, 45.0)
	if _asc_ruido:
		_asc_ruido.stream_paused = true
		get_tree().create_timer(1.8).timeout.connect(func():
			if is_instance_valid(_asc_ruido):
				_asc_ruido.stream_paused = false)
	_cabina_luz.light_energy = 1.4
	# los compañeros bot van dentro: se les para y se les lleva
	_bots_cabina.clear()
	if not _en_red or _soy_host:
		var r := _cabina_rect()
		var i := 0
		for b in get_tree().get_nodes_in_group("aliados_pve"):
			if not is_instance_valid(b):
				continue
			var off := Vector2(lerpf(float(r[0]) + 0.5, float(r[2]) - 0.5, float(i % 2)), lerpf(float(r[1]) + 0.6, float(r[3]) - 0.6, float(i / 2) / 2.0))
			i += 1
			b.set_physics_process(false)
			_bots_cabina.append([b, off])


func _bucle_directo(ruta_ogg: String, padre: Node3D, pos: Vector3, db: float, alcance: float) -> AudioStreamPlayer3D:
	if not ResourceLoader.exists(ruta_ogg) and not FileAccess.file_exists(ruta_ogg):
		return null
	var st = load(ruta_ogg) if ResourceLoader.exists(ruta_ogg) else AudioStreamOggVorbis.load_from_file(ruta_ogg)
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	var a := AudioStreamPlayer3D.new()
	a.stream = st
	a.unit_size = 10.0
	a.max_distance = alcance
	a.volume_db = db + Audio.master_db
	a.bus = "World"
	padre.add_child(a)
	a.position = pos
	a.play()
	return a


func _physics_process(dt: float) -> void:
	if _asc_estado != 1 or not is_instance_valid(_cabina):
		return
	var m: Dictionary = cfg.get("montacargas", {})
	var y0 := float((m["cabina"] as Array)[1])
	var y1 := float(m.get("arriba", y0 + 12.0))
	var dur := float(m.get("duracion", 22.0))
	_asc_t += dt
	# arranca a los 1,8 s (cuando el motor coge vueltas); a mitad de camino SE ATASCA 3 s (se apagan las luces)
	var t: float = maxf(0.0, _asc_t - 1.8)
	var mitad := dur * 0.5
	var k: float
	if t < mitad:
		k = t / dur
	elif t < mitad + 3.0:
		k = mitad / dur
		if not _asc_atasco:
			_asc_atasco = true
			_mensaje_local("¡SE HA ATASCADO! …")
			Audio.play3d("gen/ascensor/parada", _cabina.global_position + Vector3.UP * 2.0, 0.0, 0.05, 40.0, Audio.PRI_HIGH)
			if is_instance_valid(_asc_ruido):
				_asc_ruido.stream_paused = true
		_cabina_luz.light_energy = 1.4 if randf() < 0.3 else 0.1
	else:
		if _asc_atasco and is_instance_valid(_asc_ruido) and _asc_ruido.stream_paused:
			_asc_ruido.stream_paused = false
			_cabina_luz.light_energy = 1.4
			Audio.play3d("gen/ascensor/arranque", _cabina.global_position + Vector3.UP * 2.0, 0.0, 0.0, 40.0, Audio.PRI_MID)
		k = (t - 3.0) / dur
	k = clampf(k, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	var y := lerpf(y0, y1, e)
	_cabina.global_position.y = y
	# el jugador de esta maquina, si esta dentro, no se queda atras (seguridad por si el suelo se le escapa)
	var r := _cabina_rect()
	if is_instance_valid(jugador) and not bool(jugador.get("spectating")):
		var jp: Vector3 = jugador.global_position
		if jp.x > float(r[0]) and jp.x < float(r[2]) and jp.z > float(r[1]) and jp.z < float(r[3]) and jp.y < y - 0.05 and jp.y > y - 2.5:
			jugador.global_position.y = y + 0.02
	for par in _bots_cabina:
		var b = par[0]
		if is_instance_valid(b):
			var off: Vector2 = par[1]
			b.global_position = Vector3(off.x, y + 0.05, off.y)
			b.velocity = Vector3.ZERO
	if k >= 1.0:
		_asc_estado = 2
		_ascensor_llega()


func _ascensor_llega() -> void:
	if is_instance_valid(_asc_ruido):
		_asc_ruido.queue_free()
	Audio.play3d("gen/ascensor/parada", _cabina.global_position + Vector3.UP * 2.0, 2.0, 0.0, 50.0, Audio.PRI_HIGH)
	get_tree().create_timer(1.0).timeout.connect(func():
		if is_instance_valid(_reja_este):
			var tw := _reja_este.create_tween()
			tw.tween_property(_reja_este, "position:y", 2.5, 1.0).set_trans(Tween.TRANS_QUAD)
			Audio.play3d("gen/ascensor/reja", _cabina.global_position, 0.0, 0.02, 30.0, Audio.PRI_MID))
	for par in _bots_cabina:
		var b = par[0]
		if is_instance_valid(b):
			b.set_physics_process(true)
			b.global_position += Vector3(3.5, 0.1, 0)
	_bots_cabina.clear()
	_mensaje_local("¡ARRIBA! Seguid hasta la CIUDADELA")


# ------------------------------------------------------------------ 5. el puente levadizo
func _montar_puente() -> void:
	var pu: Dictionary = cfg.get("puente", {})
	if pu.is_empty():
		return
	var largo := float(pu.get("largo", 6.0))
	var ancho := float(pu.get("ancho", 6.0))
	_puente_pivote = Node3D.new()
	_puente_pivote.name = "PuenteLevadizo"
	add_child(_puente_pivote)
	_puente_pivote.global_position = _v(pu["bisagra"])
	var tablero := StaticBody3D.new()
	tablero.collision_layer = 1
	_puente_pivote.add_child(tablero)
	tablero.position = Vector3(-largo / 2, -0.15, 0)
	_colision_caja(tablero, Vector3(largo, 0.3, ancho), Vector3.ZERO)
	var madera := _mm(Color(0.46, 0.32, 0.20), 0.0, 0.85)
	var madera2 := _mm(Color(0.38, 0.26, 0.16), 0.0, 0.9)
	var hierro := _mm(Color(0.16, 0.16, 0.17), 0.7, 0.5)
	for i in int(ancho / 0.3):
		_caja_mesh(tablero, Vector3(largo, 0.3, 0.28), Vector3(0, 0, -ancho / 2 + 0.15 + i * 0.3), madera if i % 2 == 0 else madera2)
	for x in [-largo / 2 + 0.4, 0.0, largo / 2 - 0.4]:
		_caja_mesh(tablero, Vector3(0.12, 0.33, ancho), Vector3(x, 0.01, 0), hierro)
	_puente_pivote.rotation.z = -PI / 2           # levantado: tapa la puerta del torreon
	# LAS CADENAS: del extremo del tablero a las poleas del torreon (se recalculan al bajar)
	for s in [-1, 1]:
		var c := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.05
		cm.height = 1.0
		c.mesh = cm
		c.material_override = hierro
		c.top_level = true
		add_child(c)
		_cadenas.append(c)
	# EL CONTRAPESO: un bloque de piedra colgado de la punta de la tranca
	var t: Array = pu["tranca"]
	var punta := Vector3(float(t[0]) + 0.2, float(t[1]), (float(t[2]) + float(t[5])) / 2)
	_contrapeso = Node3D.new()
	add_child(_contrapeso)
	_contrapeso.global_position = punta + Vector3.DOWN * 3.0
	_caja_mesh(_contrapeso, Vector3(1.1, 1.1, 1.1), Vector3.ZERO, _mm(Color(0.46, 0.45, 0.43), 0.0, 0.95))
	_caja_mesh(_contrapeso, Vector3(1.15, 0.12, 1.15), Vector3(0, 0.3, 0), hierro)
	_cadena_contrapeso = MeshInstance3D.new()
	var ccm := CylinderMesh.new()
	ccm.top_radius = 0.04
	ccm.bottom_radius = 0.04
	ccm.height = 1.0
	_cadena_contrapeso.mesh = ccm
	_cadena_contrapeso.material_override = hierro
	_cadena_contrapeso.top_level = true
	add_child(_cadena_contrapeso)
	_linea(_cadena_contrapeso, punta, _contrapeso.global_position + Vector3.UP * 0.55)
	_cadenas_puente()
	# barrera para los bichos (el puente subido tapa la puerta)
	var bis: Vector3 = _v(pu["bisagra"])
	_barrera_puente = AABB(Vector3(bis.x - 1.0, bis.y - 1.0, bis.z - ancho / 2 - 0.5), Vector3(3.0, 7.0, ancho + 1.0))
	CriaturaScript.barreras.append(_barrera_puente)


func _linea(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var largo := a.distance_to(b)
	if largo < 0.05:
		mi.visible = false
		return
	mi.visible = true
	mi.global_position = (a + b) * 0.5
	mi.look_at(b, Vector3.UP if absf((b - a).normalized().y) < 0.95 else Vector3.RIGHT)
	mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	mi.scale = Vector3(1.0, largo, 1.0)


func _cadenas_puente() -> void:
	if not is_instance_valid(_puente_pivote):
		return
	var pu: Dictionary = cfg.get("puente", {})
	var largo := float(pu.get("largo", 6.0))
	var ancho := float(pu.get("ancho", 6.0))
	var bis: Vector3 = _puente_pivote.global_position
	for i in _cadenas.size():
		var s := -1.0 if i == 0 else 1.0
		var punta: Vector3 = _puente_pivote.global_transform * Vector3(-largo + 0.3, 0.0, s * (ancho / 2 - 0.6))
		var polea := Vector3(bis.x + 0.1, bis.y + 5.4, bis.z + s * (ancho / 2 - 0.6))
		_linea(_cadenas[i], punta, polea)


func _puente_baja() -> void:
	if _puente_bajado or not is_instance_valid(_puente_pivote):
		return
	_puente_bajado = true
	_quitar_cartel("tranca")
	var pu: Dictionary = cfg["puente"]
	_tallar_caja([pu["tranca"]], 0.5)
	Audio.play3d("gen/derrumbe/puente", _puente_pivote.global_position + Vector3(-3, 4, 0), 8.0, 0.02, 120.0, Audio.PRI_HIGH)
	# el contrapeso se va al foso con su cadena
	if is_instance_valid(_contrapeso):
		var tc := _contrapeso.create_tween()
		tc.tween_property(_contrapeso, "global_position:y", _contrapeso.global_position.y - 12.0, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tc.tween_callback(func():
			_golpe(_contrapeso.global_position, 1.0, "destru/derrumbe_medio"))
	if is_instance_valid(_cadena_contrapeso):
		_cadena_contrapeso.queue_free()
	var tw := create_tween()
	tw.tween_interval(0.35)
	tw.tween_property(_puente_pivote, "rotation:z", 0.0, 1.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		_golpe(_puente_pivote.global_position + Vector3(-float(pu.get("largo", 6.0)), 0, 0), 1.6, "destru/madera")
		CriaturaScript.barreras.erase(_barrera_puente))
	tw.tween_property(_puente_pivote, "rotation:z", -0.05, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_puente_pivote, "rotation:z", 0.0, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_mensaje_local("¡EL PUENTE HA BAJADO! A la PLAZA DE ARMAS")


# ------------------------------------------------------------------ el barco que os ha traido
func _montar_barco() -> void:
	var para: Vector3 = _v(cfg.get("barco", [24, 0.55, 127]))
	_barco = Node3D.new()
	_barco.name = "Barco"
	var casco := _mm(Color(0.12, 0.16, 0.2), 0.3, 0.6)
	var blanco := _mm(Color(0.86, 0.87, 0.84), 0.2, 0.5)
	var rojo := _mm(Color(0.6, 0.08, 0.06), 0.2, 0.6)
	for pz in [[Vector3(14.0, 1.6, 4.6), Vector3(0, 0.3, 0), casco], [Vector3(14.1, 0.25, 4.7), Vector3(0, 1.2, 0), rojo],
			[Vector3(5.0, 2.4, 3.6), Vector3(1.5, 2.4, 0), blanco], [Vector3(5.1, 0.7, 3.7), Vector3(1.5, 2.9, 0), _mm(Color(0.25, 0.4, 0.5), 0.1, 0.1)],
			[Vector3(0.3, 3.0, 0.3), Vector3(2.5, 5.0, 0), casco]]:
		_caja_mesh(_barco, pz[0], pz[1], pz[2])
	var proa := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(4.6, 3.0, 1.6)
	proa.mesh = pm
	proa.material_override = casco
	proa.rotation = Vector3(PI / 2, 0, -PI / 2)
	proa.position = Vector3(-8.4, 0.3, 0)
	_barco.add_child(proa)
	add_child(_barco)
	_barco.global_position = para
	_barco.rotation.y = 0.0
	_bucle_directo("res://sounds/l4d2/heli/bucle_lejos1.ogg", _barco, Vector3(3, 2, 0), -10.0, 200.0)


func _barco_tick(dt: float) -> void:
	if not is_instance_valid(_barco):
		return
	var para: Vector3 = _v(cfg.get("barco", [24, 0.55, 127]))
	var t := Time.get_ticks_msec() * 0.001
	if _barco_t < 0.0:
		_barco.global_position = para + Vector3(0, sin(t * 1.2) * 0.05, 0)
		_barco.rotation = Vector3(sin(t * 0.8) * 0.02, 0, sin(t * 1.0) * 0.025)
		return
	_barco_t += dt
	var k: float = clampf(_barco_t / BARCO_SALE, 0.0, 1.0)
	var e := k * k
	_barco.global_position = para + Vector3(-e * 20.0, sin(t * 1.2) * 0.06, e * 140.0)
	_barco.rotation.y = lerpf(0.0, PI / 2, clampf(k * 3.0, 0.0, 1.0))
	if k >= 1.0:
		_barco.queue_free()
		_barco = null


# ======================================================================================================
# AL EMPEZAR: el capitan os deja y se va
# ======================================================================================================
func _al_empezar() -> void:
	_barco_t = 0.0
	Audio.bf2d("amb/radio", -4.0, Audio.PRI_MID)
	_mensaje_local("CAPITÁN: «Hasta aquí llego. La RADIO de la CIUDADELA, arriba del cerro, llama al helicóptero. ¡Suerte!»")
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--ir="):
			_ir_a(String(a).substr(5).replace("_", " "))


## --ir=<punto de la ruta> (para probarlo a mano): te deja en ese punto con los puzzles de antes ya resueltos.
## Ej.: --ir=chimenea, --ir=montacargas, --ir=foso
func _ir_a(nombre: String) -> void:
	var i := _indice_de(nombre)
	if i >= ruta.size():
		_mensaje_local("--ir: no hay ningun punto '%s'" % nombre)
		return
	if not _soy_host and _en_red:
		return
	if i > _indice_de("contenedor"):
		_evento("contenedor", [])
	if i > _indice_de("pasaje"):
		_evento("persiana", [])
	if i > _indice_de("barranco"):
		_evento("chimenea", [])
	if i > _indice_de("montacargas"):
		_asc_estado = 2
		if is_instance_valid(_cabina):
			_cabina.global_position.y = float((cfg.get("montacargas", {}) as Dictionary).get("arriba", 23.0))
			_reja_este.position.y = 2.5
	if i > _indice_de("puente levadizo"):
		_evento("puente", [])
	progreso = i
	print("[campana3] --ir=%s: contenedor %s, persiana %s, chimenea %s, montacargas %d, puente %s" % [nombre, str(_cont_caido),
		str(_persiana_abierta), str(_chim_caida), _asc_estado, str(_puente_bajado)])
	var fases := {"malecon": "malecon", "plaza del mercado": "plaza", "pasaje": "persiana", "cuesta": "cuesta",
		"mirador": "cuesta", "chimenea": "chimenea", "barranco": "cruzar", "calle alta": "camino", "patio del montacargas": "generador",
		"generador": "generador", "montacargas": "generador", "arriba del acantilado": "arriba", "foso": "puente",
		"puente levadizo": "plaza_armas", "plaza de armas": "plaza_armas", "radio": "radio", "helipuerto": "radio"}
	fase = String(fases.get(nombre, fase))
	await get_tree().create_timer(0.5).timeout
	if is_instance_valid(jugador):
		jugador.global_position = ruta[i] + Vector3.UP * 0.4
	for b in get_tree().get_nodes_in_group("aliados_pve"):
		if is_instance_valid(b) and b.has_method("teletransportar_a"):
			b.teletransportar_a(jugador)


# ======================================================================================================
# CADA CUADRO
# ======================================================================================================
func _process_sin_medir(dt: float) -> void:
	super._process_sin_medir(dt)
	_barco_tick(dt)
	if is_instance_valid(_puente_pivote):
		_cadenas_puente()
	if (_en_red and not _soy_host) or terminado or world == null:
		return
	_generador_tick(dt)
	_comprobar_t -= dt
	if _comprobar_t > 0.0:
		return
	_comprobar_t = 0.4
	var c: Dictionary = cfg.get("contenedor", {})
	if not _cont_caido and not c.is_empty():
		var rotos := 0
		for i in (c["puntales"] as Array).size():
			if _cortado("puntal%d" % i, c["puntales"][i], 0.25):
				rotos += 1
		if rotos >= 3:
			_evento("contenedor", [])
	var ch: Dictionary = cfg.get("chimenea", {})
	if not _chim_caida and not ch.is_empty() and _cortado("chimenea", ch["base"], 0.35):
		_evento("chimenea", [])
	var pu: Dictionary = cfg.get("puente", {})
	if not _puente_bajado and not pu.is_empty() and _cortado("tranca", pu["tranca"], 0.3, true):
		_evento("puente", [])


## ¿Esta CORTADO? Se parte la caja en rodajas de 0,4 m (en vertical, o a lo largo de X si `en_x`) y se miran los
## voxels de cada una contra los que tenia al empezar: si alguna se ha quedado por debajo de `umbral`, ya no
## aguanta. Asi cuenta un corte limpio de lado a lado, no desconchar la superficie.
func _cortado(id: String, k: Array, umbral: float, en_x: bool = false) -> bool:
	var mn := _v([k[0], k[1], k[2]])
	var mx := _v([k[3], k[4], k[5]])
	var rodajas: Array = []
	if en_x:
		var x := mn.x
		while x < mx.x - 0.1:
			rodajas.append([Vector3(x, mn.y, mn.z), Vector3(minf(x + 0.4, mx.x), mx.y, mx.z)])
			x += 0.4
	else:
		var y := mn.y + 0.1
		while y < mx.y - 0.1:
			rodajas.append([Vector3(mn.x, y, mn.z), Vector3(mx.x, minf(y + 0.4, mx.y), mx.z)])
			y += 0.4
	if not _llenos.has(id):
		var l: Array = []
		for r in rodajas:
			l.append(world.contar_voxels(r[0], r[1]))
		_llenos[id] = l
		return false
	var lleno: Array = _llenos[id]
	for i in mini(rodajas.size(), lleno.size()):
		if int(lleno[i]) <= 0:
			continue
		if world.contar_voxels(rodajas[i][0], rodajas[i][1]) <= int(lleno[i]) * umbral:
			return true
	return false


# ------------------------------------------------------------------ el generador (el evento)
func _arrancar_generador() -> void:
	if fase != "generador" or _gen_estado != 0:
		return
	_gen_estado = 1
	_gen_t = float((cfg.get("generador", {}) as Dictionary).get("calentar", 40.0))
	_evento("generador", [])
	_horda(HORDA_TAM, "¡EL GENERADOR HACE MUCHO RUIDO! ¡VIENE LA HORDA!")


func _generador_tick(dt: float) -> void:
	if _gen_estado != 1:
		return
	_gen_t -= dt
	_texto = "EL GENERADOR CALIENTA · %d s · ¡AGUANTAD!" % ceili(maxf(_gen_t, 0.0))
	_tanda_t -= dt
	if _tanda_t <= 0.0:
		_tanda_t = 11.0
		if _cola.size() < 6:
			_horda(8, "")
	if not _gen_tank and _gen_t < 22.0:
		_gen_tank = true
		_cola.push_front("tanque")
		_mensaje("¡UN TANK!")
	if _gen_t <= 0.0:
		_gen_estado = 2
		_evento("generador_listo", [])
		_poner_fase("montacargas", "¡Hay corriente! TODOS a la CABINA del montacargas y pulsad SUBIR")


# ======================================================================================================
# LA HISTORIA (solo el anfitrion)
# ======================================================================================================
func _historia() -> void:
	var y1: float = ruta[_indice_de("plaza del mercado")].y if _indice_de("plaza del mercado") < ruta.size() else 5.0
	match fase:
		"inicio":
			_poner_fase("contenedor", "La escalera del muelle se ha hundido · REVENTAD LOS PUNTALES del andamio y bajad el CONTENEDOR")
		"contenedor":
			if _cont_caido:
				_poner_fase("malecon", "Trepad: cajas → CONTENEDOR → MALECÓN")
		"malecon":
			for pl in _jugadores_vivos():
				if (pl as Node3D).global_position.y > y1 - 0.6:
					_poner_fase("plaza", "Cruzad la PLAZA DEL MERCADO hasta el PASAJE del norte")
					break
		"plaza":
			if _alguien_cerca(ruta[_indice_de("pasaje")], 12.0):
				_poner_fase("persiana", "La PERSIANA del pasaje está cerrada · subid al BALCÓN (contenedor de basura → quiosco) y tirad de la PALANCA")
		"persiana":
			if _persiana_abierta:
				_poner_fase("cuesta", "¡Abierto! Subid por la CUESTA hasta el MIRADOR")
		"cuesta":
			if progreso >= _indice_de("mirador"):
				_poner_fase("chimenea", "Un BARRANCO corta la calle · REVENTAD EL PIE de la CHIMENEA para tumbarla encima")
		"chimenea":
			if _chim_caida:
				_poner_fase("cruzar", "Trepad a la CHIMENEA caída y CRUZAD el barranco")
		"cruzar":
			if progreso >= _indice_de("calle alta"):
				_poner_fase("camino", "Llegad al REFUGIO: la PANADERÍA de la calle alta")
		"camino":
			var ref: Dictionary = cfg.get("refugio", {})
			if not ref.is_empty() and _todos_dentro(ref["rect"]):
				_poner_fase("refugio", "")
				_llegar_al_refugio()
		"refugio":
			if progreso >= _indice_de("patio del montacargas"):
				_poner_fase("generador", "El MONTACARGAS no tiene corriente · ARRANCAD EL GENERADOR (hará ruido)")
		"montacargas":
			var r := _cabina_rect()
			var dentro := 0
			var vivos := _jugadores_vivos()
			for pl in vivos:
				var p: Vector3 = (pl as Node3D).global_position
				if p.x > float(r[0]) and p.x < float(r[2]) and p.z > float(r[1]) and p.z < float(r[3]):
					dentro += 1
			_texto = "¡Hay corriente! TODOS a la CABINA y pulsad SUBIR · %d de %d dentro" % [dentro, vivos.size()]
		"subiendo":
			if _asc_estado == 2:
				_poner_fase("arriba", "Seguid hasta el FOSO de la CIUDADELA")
			else:
				_texto = "SUBIENDO… agarraos"
		"arriba":
			if _alguien_cerca(ruta[_indice_de("foso")], 10.0):
				_poner_fase("puente", "El PUENTE LEVADIZO está subido · ROMPED LA TRANCA del torreón (la viga de madera)")
		"puente":
			if _puente_bajado:
				_poner_fase("plaza_armas", "Cruzad el puente hasta la PLAZA DE ARMAS")
		"plaza_armas":
			if progreso >= _indice_de("plaza de armas"):
				_poner_fase("radio", "Usad la RADIO de la caseta para llamar al helicóptero")
		"final":
			_final_tick()
		"helicoptero":
			_trepar_a_la_azotea()
			_abordar_tick()


func _llegar_al_refugio() -> void:
	super._llegar_al_refugio()
	_texto = "REFUGIO · vida y munición repuestas · la puerta ESTE se abre en 10 s"
	_objetivo(_texto)


func _objetivo_punto() -> Array:
	var sig := func(tope: String) -> Vector3:
		var i := mini(progreso + 1, _indice_de(tope))
		return ruta[clampi(i, 0, ruta.size() - 1)]
	match fase:
		"inicio", "contenedor":
			var k: Array = (cfg.get("contenedor", {}) as Dictionary).get("caja", [0, 0, 0, 0, 0, 0])
			return [Vector3((float(k[0]) + float(k[3])) / 2, float((cfg["contenedor"] as Dictionary).get("suelo", 1.0)), (float(k[2]) + float(k[5])) / 2 + 1.6), "PUNTALES · REVENTADLOS"]
		"malecon":
			return [ruta[_indice_de("malecon")], "SUBID AL MALECÓN"]
		"plaza":
			return [sig.call("pasaje"), "PASAJE"]
		"persiana":
			return [_v((cfg.get("persiana", {}) as Dictionary).get("palanca", [0, 0, 0])), "PALANCA DE LA PERSIANA"]
		"cuesta":
			return [sig.call("mirador"), "HACIA EL MIRADOR"]
		"chimenea":
			var b: Array = (cfg.get("chimenea", {}) as Dictionary).get("base", [0, 0, 0, 0, 0, 0])
			return [Vector3((float(b[0]) + float(b[3])) / 2, float(b[1]), (float(b[2]) + float(b[5])) / 2), "PIE DE LA CHIMENEA · REVENTADLO"]
		"cruzar":
			return [ruta[_indice_de("barranco")], "CRUZAD POR LA CHIMENEA"]
		"camino":
			return [sig.call("refugio"), "REFUGIO"]
		"refugio":
			var ps = (cfg.get("refugio", {}) as Dictionary).get("puerta_salida", null)
			var yr := float((cfg.get("refugio", {}) as Dictionary).get("suelo", 1.0))
			return [_v([ps[0], yr, ps[1]]) if ps != null else ruta[progreso], "SALIDA DEL REFUGIO"]
		"generador":
			if _gen_estado == 1:
				return [ruta[_indice_de("montacargas")], "MONTACARGAS · AGUANTAD"]
			return [_v((cfg.get("generador", {}) as Dictionary).get("boton", [0, 0, 0])), "GENERADOR"]
		"montacargas":
			return [ruta[_indice_de("montacargas")], "MONTACARGAS · TODOS DENTRO"]
		"subiendo":
			return [_cabina.global_position + Vector3.UP * 3.0 if is_instance_valid(_cabina) else ruta[progreso], "SUBIENDO"]
		"arriba":
			return [sig.call("foso"), "HACIA LA CIUDADELA"]
		"puente":
			var t: Array = (cfg.get("puente", {}) as Dictionary).get("tranca", [0, 0, 0, 0, 0, 0])
			return [Vector3(float(t[0]), float(t[1]) - 1.3, (float(t[2]) + float(t[5])) / 2), "TRANCA · ROMPEDLA"]
		"plaza_armas":
			return [ruta[_indice_de("plaza de armas")], "PLAZA DE ARMAS"]
	return super._objetivo_punto()


## Hasta donde pueden salir bichos: nunca al otro lado de lo que aun esta cerrado
func _tope_ruta() -> int:
	if not _cont_caido:
		return _indice_de("contenedor")
	if not _persiana_abierta:
		return _indice_de("pasaje")
	if not _chim_caida:
		return _indice_de("chimenea")
	if _asc_estado < 2:
		return _indice_de("montacargas")
	if not _puente_bajado:
		return _indice_de("foso")
	return 999


# ======================================================================================================
# LO QUE SE USA: la palanca, el generador y la botonera del montacargas
# ======================================================================================================
func _usables_extra(f: String) -> void:
	match f:
		"persiana", "plaza":
			if not _persiana_abierta:
				var pp: Vector3 = _mando_palanca.global_position + _mando_palanca.global_transform.basis.z * 0.15 if is_instance_valid(_mando_palanca) 					else _v((cfg.get("persiana", {}) as Dictionary).get("palanca", [0, 0, 0])) + Vector3(0, 1.2, 0.15)
				_usables.append({"id": "palanca", "pos": pp,
					"texto": "TIRAR DE LA PALANCA (abre la persiana del pasaje)", "cerca": 2.4})
		"generador":
			if _gen_estado == 0:
				var pg: Vector3 = _mando_generador.global_position + _mando_generador.global_transform.basis.z * 0.15 if is_instance_valid(_mando_generador) 					else _v((cfg.get("generador", {}) as Dictionary).get("boton", [0, 0, 0])) + Vector3(0, 1.3, -0.3)
				_usables.append({"id": "generador", "pos": pg,
					"texto": "ARRANCAR EL GENERADOR (hará ruido: vendrá la horda)", "cerca": 2.4})
		"montacargas":
			if _asc_estado == 0:
				# el aviso, encima de la botonera de verdad (mandos.gd), no en el aire
				var pb: Vector3 = _mando_botonera.global_position + _mando_botonera.global_transform.basis.z * 0.12 if is_instance_valid(_mando_botonera) 					else _v((cfg.get("montacargas", {}) as Dictionary).get("boton", [0, 0, 0])) + Vector3(0.2, 1.3, 0)
				_usables.append({"id": "subir", "pos": pb,
					"texto": "SUBIR (todos dentro de la cabina)", "cerca": 2.2})


func _pide_extra(accion: String) -> void:
	match accion:
		"palanca":
			if not _persiana_abierta:
				_evento("persiana", [])
				_horda(10, "")
		"generador":
			_arrancar_generador()
		"subir":
			if fase != "montacargas" or _asc_estado != 0:
				return
			var r := _cabina_rect()
			var vivos := _jugadores_vivos()
			var fuera := 0
			for pl in vivos:
				var p: Vector3 = (pl as Node3D).global_position
				if not (p.x > float(r[0]) and p.x < float(r[2]) and p.z > float(r[1]) and p.z < float(r[3])):
					fuera += 1
			if fuera > 0:
				_mensaje("FALTAN %d EN LA CABINA · el montacargas no sube sin todos" % fuera)
				return
			_poner_fase("subiendo", "SUBIENDO… agarraos")
			_evento("subir", [])


## El invitado no lleva la fase: la deduce del cartel que le manda el anfitrion
func _fase_invitado() -> String:
	var t: String = _texto_red
	if t.begins_with("La PERSIANA"):
		return "persiana"
	if t.begins_with("El MONTACARGAS no tiene"):
		return "generador"
	if t.begins_with("¡Hay corriente!"):
		return "montacargas"
	if t.begins_with("Usad la RADIO"):
		return "radio"
	return ""


## La palanca de la persiana (atornillada a la caja electrica amarilla del balcon) y el panel de arranque del
## generador (en la cara sur de la caseta): cada uno en la pared que tiene detras. La botonera va con la cabina.
func _montar_mandos() -> void:
	var pal = (cfg.get("persiana", {}) as Dictionary).get("palanca", null)
	if pal != null:
		_mando_palanca = Mandos.en_pared(world, "palanca", self, _v(pal) + Vector3(0, 1.2, 0.35), Vector3(0, 0, 1))
	# LA BOTONERA (amarilla, SUBIR en verde): atornillada a la caja naranja del mapa, en la cara que da a la cabina.
	# Sin corriente, el piloto apagado; cuando arranca el generador, ambar; al subir, verde.
	var mb = (cfg.get("montacargas", {}) as Dictionary).get("boton", null)
	if mb != null:
		_mando_botonera = Mandos.en_pared(world, "botonera", self, _v(mb) + Vector3(0.45, 1.3, 0), Vector3(1, 0, 0))
		Mandos.piloto(_mando_botonera, "apagado")
	var gb = (cfg.get("generador", {}) as Dictionary).get("boton", null)
	if gb != null:
		_mando_generador = Mandos.en_pared(world, "arranque", self, _v(gb) + Vector3(0, 1.25, -0.5), Vector3(0, 0, -1))


func _evento_extra(e: String, _datos: Array) -> void:
	match e:
		"contenedor":
			_contenedor_cae()
		"persiana":
			Mandos.accionar(_mando_palanca)
			_persiana_sube()
		"chimenea":
			_chimenea_cae()
		"generador":
			# el boton verde se hunde y la aguja sube; el piloto en rojo mientras calienta
			Mandos.accionar(_mando_generador, false)
			Mandos.piloto(_mando_generador, "alarma")
			var b: Vector3 = _v((cfg.get("generador", {}) as Dictionary).get("boton", [0, 0, 0]))
			Audio.play3d("gen/generador/arranque", b + Vector3(0, 1.2, 2.0), 4.0, 0.02, 80.0, Audio.PRI_HIGH)
			get_tree().create_timer(2.6).timeout.connect(func():
				var casa := Node3D.new()
				add_child(casa)
				casa.global_position = b + Vector3(0, 1.2, 2.5)
				_gen_ruido = _bucle_directo("res://sounds/gen/generador/bucle1.ogg", casa, Vector3.ZERO, 2.0, 90.0))
			Audio.voz("bomba_armada_nos_a", 2)
		"generador_listo":
			Mandos.piloto(_mando_generador, "hecho")
			Mandos.piloto(_mando_botonera, "espera")      # ahora si: la botonera tiene corriente
			if is_instance_valid(_boton_luz):
				_boton_luz.light_color = Color(0.2, 1.0, 0.3)
				_boton_luz.light_energy = 2.0
			if is_instance_valid(_cabina_luz):
				_cabina_luz.light_energy = 1.4
			Audio.play3d("gen/ascensor/timbre", _cabina.global_position + Vector3.UP * 2.0 if is_instance_valid(_cabina) else Vector3.ZERO, 0.0, 0.0, 40.0, Audio.PRI_HIGH)
			Audio.ui("objetivo_tomado", -2.0)
			_mensaje_local("¡HAY CORRIENTE! Todos a la cabina")
		"subir":
			Mandos.accionar(_mando_botonera)
			_ascensor_sube()
		"puente":
			_puente_baja()


# ======================================================================================================
# LA SALIDA DE CINE: el helicoptero despega y se va hacia el sol, sobre el mar
# ======================================================================================================
func _on_evento(e: String, datos: Array) -> void:
	super._on_evento(e, datos)
	if e == "escapan":
		_cine_final()


func _heli_tick(dt: float) -> void:
	if _heli_modo == "cine":
		if is_instance_valid(_heli_rotor):
			_heli_rotor.rotation.y += dt * 30.0
		return
	super._heli_tick(dt)


func _cine_final() -> void:
	if _cine_final_hecha or not is_instance_valid(_heli):
		_cine_final_hecha = true
		return
	_cine_final_corriendo = true
	_heli_modo = "cine"
	var cf: Dictionary = cfg.get("cine_final", {})
	var hp: Vector3 = _heli.global_position
	var mar: Vector3 = _v(cf.get("hacia_mar", [hp.x - 60.0, hp.y + 10.0, hp.z + 150.0]))
	# los de a bordo: ni cuerpo, ni control, ni interfaz
	if is_instance_valid(jugador):
		jugador.set_physics_process(false)
		jugador.set_process_unhandled_input(false)
		var av = jugador.get("avatar")
		if av != null:
			av.visible = false
		for n in ["weapon_pivot", "fp_arms"]:
			var nd = jugador.get(n)
			if nd != null and is_instance_valid(nd):
				nd.visible = false
	for r in Net.remotes.values():
		if is_instance_valid(r):
			(r as Node3D).visible = false
	for b in get_tree().get_nodes_in_group("aliados_pve"):
		if is_instance_valid(b):
			(b as Node3D).visible = false
	if hud:
		hud.visible = false
	if _capa_equipo:
		_capa_equipo.visible = false
	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.far = 900.0
	add_child(cam)
	cam.global_position = hp + Vector3(-16.0, 4.0, -12.0)
	cam.look_at(hp + Vector3.UP * 2.0)
	cam.make_current()
	# franjas de cine y el rotulo
	var capa := CanvasLayer.new()
	capa.layer = 30
	add_child(capa)
	var alto := get_viewport().get_visible_rect().size.y * 0.11
	for arriba in [true, false]:
		var fr := ColorRect.new()
		fr.color = Color.BLACK
		fr.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if arriba else Control.PRESET_BOTTOM_WIDE)
		if arriba:
			fr.offset_bottom = alto
		else:
			fr.offset_top = -alto
		capa.add_child(fr)
	var titulo := Label.new()
	titulo.text = "EPISODIO 3 COMPLETADO"
	titulo.add_theme_font_size_override("font_size", 58)
	titulo.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
	titulo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	titulo.add_theme_constant_override("shadow_offset_y", 3)
	titulo.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.grow_horizontal = Control.GROW_DIRECTION_BOTH
	titulo.modulate.a = 0.0
	capa.add_child(titulo)
	var sub := Label.new()
	sub.text = "…y el sol sale sobre un mundo que ya no es el vuestro"
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(0.92, 0.9, 0.84))
	sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sub.position.y += 56.0
	sub.modulate.a = 0.0
	capa.add_child(sub)
	var negro := ColorRect.new()
	negro.color = Color(0, 0, 0, 0)
	negro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	capa.add_child(negro)
	# EL VUELO: sube recto, se inclina y se va hacia el mar; la camara se queda en la muralla y lo sigue
	var arriba_p := hp + Vector3(0, 14.0, 0)
	var tw := create_tween()
	tw.tween_property(_heli, "global_position", arriba_p, 3.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(cam, "global_position", hp + Vector3(-18.0, 9.0, -16.0), 3.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_heli, "rotation:z", -0.25, 0.8)
	tw.parallel().tween_property(_heli, "rotation:y", atan2(-(mar - hp).z, (mar - hp).x), 1.4)
	tw.tween_property(_heli, "global_position", mar, 9.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(cam, "global_position", hp + Vector3(-10.0, 14.0, -24.0), 9.0).set_trans(Tween.TRANS_SINE)
	var seguir := func(_k: float) -> void:
		if is_instance_valid(cam) and is_instance_valid(_heli):
			cam.look_at(_heli.global_position.lerp(mar, 0.15), Vector3.UP)
	tw.parallel().tween_method(seguir, 0.0, 1.0, 9.0)
	var tt := create_tween()
	tt.tween_interval(6.0)
	tt.tween_property(titulo, "modulate:a", 1.0, 1.4)
	tt.parallel().tween_property(sub, "modulate:a", 1.0, 2.0)
	tt.tween_interval(3.6)
	tt.tween_property(negro, "color:a", 1.0, 1.6)
	tt.tween_callback(func():
		_cine_final_hecha = true
		_cine_final_corriendo = false)


## Al ganar, la pantalla de resultado espera a que acabe la salida de cine
func _fin(gano: bool) -> void:
	if gano and _cine_final_corriendo:
		var espera := 0.0
		while _cine_final_corriendo and espera < 20.0:
			await get_tree().create_timer(0.25).timeout
			espera += 0.25
	super._fin(gano)
