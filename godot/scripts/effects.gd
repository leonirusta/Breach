extends Node3D
## Efectos con pools fijos (sin asignar en caliente): polvo de impacto/derrumbe, polvo al caer
## escombros, chispas al disparar metal. GPUParticles3D one-shot reutilizados en round-robin.
##
## Polvo "de verdad" sin texturas externas: se genera una vez una textura de humo (gradiente
## radial x ruido fractal, 128x128) con alpha; cada partícula rota al azar, crece, se aclara
## y se desvanece con curva; el material recibe luz (la nube tiene lado iluminado y sombra),
## se funde suavemente con el suelo (proximity fade) y no escribe profundidad.

var dust_pool: Array[GPUParticles3D] = []
var puff_pool: Array[GPUParticles3D] = []
var muzzle_pool: Array[GPUParticles3D] = []   ## humo de la boca del arma: su propio grupo, muy barato
var _heat_vivos: Array = []                   ## [punto en el mundo, tiempo, vida, radio]
var spark_pool: Array[GPUParticles3D] = []
## LA SANGRE, CON SUS PROPIAS PARTICULAS (2026-10-04, bug: "disparo al metal y a veces salen chispas como de sangre"): la
## salpicadura reutilizaba las de las chispas y les dejaba puesto el rojo; la siguiente chispa del metal salia roja
var blood_part_pool: Array[GPUParticles3D] = []
var blood_part_i := 0
var fire_pool: Array[GPUParticles3D] = []
var cloud_pool: Array[GPUParticles3D] = []
var light_pool: Array[OmniLight3D] = []
## Las luces de explosiones son puramente visuales. Este multiplicador viene del ajuste
## "Distancia de luces": si el jugador las apaga, no se crean destellos dinámicos que
## puedan comerse la GPU durante una horda.
var light_scale := 1.0
var _explosions: Array = []   # explosiones vivas: [t, flash_life, pos, size, light, glow_life, flash_i, glow_i]
var fire_i := 0
var cloud_i := 0
var light_i := 0
var dust_i := 0
var puff_i := 0
var muzzle_i := 0
var spark_i := 0
var quality := 1
var player = null  # jugador local: para la sacudida de camara por explosion cercana

## LOS EFECTOS QUE NO SE VEN, NO SE SIMULAN (2026-10-04, pedido: "si hay una explosion fuera de camara, que haga el daño
## pero que mi movil no procese particulas ni humo; y si entro justo despues, ver el humo y lo destruido"). Solo IMAGEN:
## el tallado, los trozos y su fisica son iguales en todas las maquinas (la red) y no se tocan; el sonido, la sacudida, la
## tierra en la lente y la sordera tampoco. Lo que cambia, segun `nivel_fx`:
##   0 COMPLETO   en pantalla a menos de FX_MEDIA_M (y siempre a menos de FX_PEGADO_M)
##   1 MEDIO      en pantalla entre FX_MEDIA_M y FX_LEJOS_M: menos particulas, sin chorros ni nube volumetrica
##   2 MINIMO     en pantalla mas lejos: un fogonazo pequeño y algo de polvo
##   3 NADA       fuera de pantalla: nada de imagen. La explosion se APUNTA (`_fx_pendientes`) FX_PENDIENTE_S segundos:
##                si en ese rato entra en la vista, sale su humo (menos cuanto mas tiempo paso). Lo destruido ya esta.
## Los impactos de bala y el polvo de lo que cae siguen la misma regla (sin pendiente: duran un instante).
## `--sinlodfx` = todo como antes. Contadores para las pruebas: `fx_niveles`.
const FX_PEGADO_M := 8.0
const FX_MEDIA_M := 35.0
const FX_LEJOS_M := 70.0
const FX_PENDIENTE_S := 8.0
static var _sin_lod_fx: bool = "--sinlodfx" in OS.get_cmdline_user_args()
var fx_niveles := [0, 0, 0, 0]       ## explosiones por nivel (pruebas)
var fx_tardias := 0                  ## humos que salieron al entrar en la vista despues (pruebas)
var _fx_pendientes: Array = []       ## [pos, radio, segundo en que revento]
var _fx_pend_t := 0.0


func nivel_fx(pos: Vector3, radio := 0.0) -> int:
	if _sin_lod_fx or not is_inside_tree():
		return 0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 0
	var d: float = cam.global_position.distance_to(pos) - radio
	if d < FX_PEGADO_M:
		return 0
	if not _en_pantalla(cam, pos, radio):
		return 3
	# TAPADO POR LAS PAREDES (2026-10-10, pedido: "que no se procese lo que hay detras de las paredes, dentro de las
	# casas"): en el encuadre pero detras de un edificio. Si el centro no se ve y la columna de encima (por donde sube el
	# humo) tampoco, es como fuera de la vista: nada de imagen (la explosion se apunta y su humo sale si la rodeas). Si
	# la columna asoma por encima del tejado, lo minimo.
	var tap := _tapado(cam, pos, radio)
	if tap == 2:
		return 3
	if tap == 1:
		return 2
	if d < FX_MEDIA_M:
		return 0
	return 1 if d < FX_LEJOS_M else 2


## 0 se ve, 1 el centro tapado pero la columna de encima asoma, 2 tapado del todo. Rayos contra la rejilla de voxels
## (no contra los bloques sueltos). `--sinfxtapado` = sin mirar.
static var _sin_fx_tapado: bool = "--sinfxtapado" in OS.get_cmdline_user_args()
var fx_tapados := 0                  ## efectos que no salieron por estar detras de una pared (pruebas)
func _tapado(cam: Camera3D, pos: Vector3, radio: float) -> int:
	if _sin_fx_tapado or world == null or not world.has_method("raycast"):
		return 0
	var o := cam.global_position
	if not _rayo_tapa(o, pos, radio + 0.6):
		return 0
	# la columna: el humo de una explosion sube; un impacto de bala (radio pequeño) no tiene columna
	if radio >= 1.0 and not _rayo_tapa(o, pos + Vector3.UP * (radio * 2.0 + 2.0), 0.6):
		return 1
	fx_tapados += 1
	return 2


func _rayo_tapa(o: Vector3, p: Vector3, margen: float) -> bool:
	var to := p - o
	var dist := to.length()
	if dist < 0.5:
		return false
	var h: Dictionary = world.raycast(o, to / dist, dist)
	if not h.get("hit", false):
		return false
	return o.distance_to(h.get("position", p)) < dist - margen


func _en_pantalla(cam: Camera3D, pos: Vector3, radio: float) -> bool:
	# con su radio de margen: una explosion grande al borde de la vista se ve aunque su centro quede fuera
	var to := pos - cam.global_position
	var dist := to.length()
	if dist < 0.01:
		return true
	var fwd := -cam.global_transform.basis.z
	var cos_lim := cos(deg_to_rad(cam.fov * 0.5 * 1.45) + atan2(radio * 1.5, dist))   # ~ el ancho de la vista apaisada
	return fwd.dot(to / dist) > cos_lim


## Las que reventaron fuera de la vista y ahora se ven: su humo, lo que quede de el
func _fx_pendientes_tick(dt: float) -> void:
	if _fx_pendientes.is_empty():
		return
	_fx_pend_t -= dt
	if _fx_pend_t > 0.0:
		return
	_fx_pend_t = 0.2
	var ahora := Time.get_ticks_msec() * 0.001
	var cam := get_viewport().get_camera_3d()
	var quedan: Array = []
	for e in _fx_pendientes:
		var edad: float = ahora - float(e[2])
		if edad > FX_PENDIENTE_S:
			continue
		var pos: Vector3 = e[0]
		var r: float = e[1]
		if cam != null and _en_pantalla(cam, pos, r) and cam.global_position.distance_to(pos) - r < FX_LEJOS_M and _tapado(cam, pos, r) < 2:
			var k: float = clampf(1.0 - edad / FX_PENDIENTE_S, 0.15, 1.0)
			smoke(pos + Vector3(0, r * 0.3, 0), r * 0.2, Color(0.36, 0.35, 0.34), 0.25 * k)
			dust(pos, r * 0.25 * k, Color(0.7, 0.68, 0.66))
			fx_tardias += 1
		else:
			quedan.append(e)
	_fx_pendientes = quedan
var world = null   # VoxelWorld: humo simulado que choca con los voxels (world.emit_smoke)
var particle_scale := 1.0   # menú gráfico: multiplicador de escombros/partículas
var smoke_scale := 1.0      # menú gráfico: multiplicador de humo (0 = sin humo)
var budget_per_frame := 6
var used_this_frame := 0
var smoke_tex: ImageTexture
var alpha_curve_tex: CurveTexture
var scale_curve_tex: CurveTexture

func setup(q: int) -> void:
	quality = q
	if world and smoke_tex == null:
		pass
	if world:
		call_deferred("_setup_world_smoke")
	for p in dust_pool: p.queue_free()
	for p in puff_pool: p.queue_free()
	for p in spark_pool: p.queue_free()
	for p in blood_part_pool: p.queue_free()
	blood_part_pool.clear()
	for p in muzzle_pool: p.queue_free()
	for p in vaho_pool: p.queue_free()
	for p in chapoteo_pool: p.queue_free()
	vaho_pool.clear(); vaho_i = 0
	chapoteo_pool.clear(); chapoteo_i = 0
	dust_pool.clear(); puff_pool.clear(); spark_pool.clear(); muzzle_pool.clear()
	_heat_vivos.clear(); _chorros.clear()
	if smoke_tex == null:
		smoke_tex = _make_smoke_texture(128 if q <= 1 else 256)
		alpha_curve_tex = _curve([Vector2(0, 0.0), Vector2(0.08, 1.0), Vector2(0.5, 0.7), Vector2(1, 0.0)])
		scale_curve_tex = _curve([Vector2(0, 0.35), Vector2(0.3, 1.0), Vector2(1, 1.6)])
	var nd: int = [6, 10, 16, 24][clampi(q, 0, 3)]
	var ns: int = [4, 8, 12, 16][clampi(q, 0, 3)]
	budget_per_frame = [3, 5, 8, 12][clampi(q, 0, 3)]
	for i in nd:
		dust_pool.append(_make_dust(false))
	for i in nd:
		puff_pool.append(_make_dust(true))
	for i in ns:
		spark_pool.append(_make_sparks())
	for i in [2, 3, 4, 6][clampi(q, 0, 3)]:
		blood_part_pool.append(_make_blood_particles())
	# uno por cada disparo que pueda estar vivo a la vez: con 0,5 s de vida y un fusil a 10 tiros
	# por segundo hacen falta unos 6 para que no se pisen entre si
	for i in ([4, 6, 8, 10][clampi(q, 0, 3)]):
		muzzle_pool.append(_make_muzzle())
	for p in fire_pool: p.queue_free()
	for p in cloud_pool: p.queue_free()
	for l in light_pool: l.queue_free()
	fire_pool.clear(); cloud_pool.clear(); light_pool.clear()
	# Los índices rotatorios se reinician con los pools: al bajar de calidad los pools se
	# encogen y un índice viejo apuntaba fuera de rango (los usos indexan ANTES de aplicar
	# el módulo). Saltaba al cambiar de calidad en partida.
	fire_i = 0; cloud_i = 0; light_i = 0; dust_i = 0; puff_i = 0; spark_i = 0; muzzle_i = 0; blood_part_i = 0
	# Las explosiones en curso guardan una referencia a su luz: si el pool se libera, esa
	# referencia queda colgando y petaba al leerla el frame siguiente.
	_explosions.clear()
	for i in [2, 3, 4, 6][clampi(q, 0, 3)]:
		fire_pool.append(_make_fire())
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.5, 0.2)
		l.omni_range = 12.0
		l.omni_attenuation = 1.2
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		light_pool.append(l)
	# escondidos hasta que se disparen (FxDormir: parados seguian costando su llamada de dibujo)
	for pd in dust_pool + puff_pool + spark_pool + blood_part_pool + muzzle_pool + fire_pool + cloud_pool:
		FxDormir.dormir(pd)

## Material del humo simulado (multimesh del núcleo): billboard con la textura de humo procedural y el color
## + alfa por instancia. Sin sombreado (como el polvo de GPU), no escribe profundidad.
func _setup_world_smoke() -> void:
	if world == null or not world.has_method("set_smoke_material"):
		return
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = smoke_tex
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.disable_receive_shadows = true
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.12   # corto: el humo vive pegado a techos y paredes
	world.set_smoke_material(m)

## Humo que choca con el mundo (se queda bajo los techos, se extiende por los huecos, dura más en interiores).
## `size` en m (radio de la explosión / tamaño de la nube), `tint` color del material.
func smoke(pos: Vector3, size: float, tint: Color = Color(0.68, 0.68, 0.69), amount: float = 1.0) -> void:
	if world == null or not world.has_method("emit_smoke") or "--nosmoke" in OS.get_cmdline_user_args():
		return
	if smoke_scale <= 0.0:
		return
	var s := clampf(size, 0.4, 5.0)
	amount *= smoke_scale
	# pocas partículas (cada una se simula contra los voxels): 6-40 por evento, radios mayores para cubrir lo mismo
	# MENOS Y MAS SUTIL. Antes eran hasta 40 particulas que crecian hasta 2x el tamano del evento y
	# duraban hasta 18 s: en un derrumbe la pantalla se llenaba de humo y no se veia jugar.
	var count := int(clampf(2.0 + s * 1.5 * amount, 1.0, 8.0))
	# el color de instancia se interpreta como lineal: pasar a lineal para que un gris 0,35 no salga casi blanco
	var c := _gris(tint).lerp(Color(0.6, 0.6, 0.61), 0.15).srgb_to_linear()
	# vida larga: 10-18 s (al aire libre el núcleo la acorta a la mitad), radio 0,35·s -> 1,4·s
	# vida corta: 3-4,5 s (al aire libre el núcleo la acorta más), radio 0,5·s -> 2,0·s
	# radio inicial 0,35s -> final 0,9s (antes 2,0s: se comia la calle), vida 1,6-2,4 s (antes 3-4,5)
	# y menos flotabilidad, para que no suba como una columna.
	world.emit_smoke(pos + Vector3(0, 0.2 * s, 0), count, 0.22 * s, 0.3 + 0.12 * s, c, 1.0 + 0.08 * s, 0.25 * s, 0.5 * s, 0.10)
	if "--smokelog" in OS.get_cmdline_user_args():
		print("[smoke] emit %s n=%d s=%.2f -> activas %d" % [pos, count, s, world.get_stats().get("smoke_active", -1)])

func _process(dt: float) -> void:
	var _pt0 := Time.get_ticks_usec()
	_process_inner(dt)
	Prof.add("effects", Time.get_ticks_usec() - _pt0)


## Ajuste compartido por todos los destellos temporales (explosiones, cohetes y fuego).
## Reducir el radio es más barato que sólo bajar la intensidad: limita los píxeles y mallas
## a los que el renderizador móvil debe aplicar la luz.
func set_light_quality(nivel: int) -> void:
	light_scale = [0.0, 0.45, 0.60, 0.75, 0.90, 1.0][clampi(nivel, 0, 5)]
	if light_scale <= 0.0:
		for l in light_pool:
			l.visible = false
		_explosions.clear()

func _process_inner(dt: float) -> void:
	FxDormir.barrer()
	_trozos_tick(dt)
	_manchas_tick(dt)
	_tick_quemas(dt)
	_fx_pendientes_tick(dt)
	if not _tracers.is_empty():
		_update_tracers(dt)
	if not _shells.is_empty():
		_update_shells(dt)
	if not _humo_vivos.is_empty():
		_update_humo(dt)
	used_this_frame = 0
	if not _heat_vivos.is_empty():
		_update_heat(dt)
	if not _chorros.is_empty():
		_update_chorros(dt)
	# luz de la explosión (explosion.lua): flash de 0,1-0,4 s muy intenso + brasa de ~1 s que decae al cuadrado
	var keep: Array = []
	for e in _explosions:
		e[0] += dt
		var t: float = e[0]
		if not is_instance_valid(e[4]):
			continue        # su luz ya no existe (cambio de calidad): se descarta la explosión
		var l: OmniLight3D = e[4]
		var flash_life: float = e[1]
		var glow_life: float = e[5]
		if t < glow_life:
			var qf := maxf(0.0, 1.0 - t / flash_life)
			var qg := 1.0 - t / glow_life
			l.light_energy = e[6] * qf + e[7] * qg * qg
			l.global_position = e[2] + Vector3(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5), randf_range(-0.5, 0.5)) * qg * qg
			keep.append(e)
		else:
			l.visible = false
	_explosions = keep

# ---------------------------------------------------------------------------
# Recursos procedurales
# ---------------------------------------------------------------------------
func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for p in points:
		c.add_point(p)
	var t := CurveTexture.new()
	t.curve = c
	return t

## Textura de humo: disco suave (falloff cúbico) modulado por ruido fractal -> bordes irregulares.
func _make_smoke_texture(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.frequency = 3.0 / size
	noise.seed = 7
	var noise2 := FastNoiseLite.new()
	noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise2.frequency = 9.0 / size
	noise2.seed = 21
	var c := size * 0.5
	for y in size:
		for x in size:
			var dx := (x - c) / c
			var dy := (y - c) / c
			var r := sqrt(dx * dx + dy * dy)
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5          # 0..1
			var n2 := noise2.get_noise_2d(x, y) * 0.5 + 0.5
			# el radio efectivo varía con el ruido: silueta irregular en vez de un círculo perfecto
			var edge := 0.62 + 0.3 * n
			var a := clampf(1.0 - r / edge, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)                             # smoothstep
			a *= 0.7 + 0.3 * n2                                     # densidad interna con grumos
			var shade := 0.75 + 0.25 * n                            # variación de brillo
			img.set_pixel(x, y, Color(shade, shade, shade, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _smoke_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	# Sin sombreado: el polvo lleva su propio color "iluminado por el cielo". Con luz por píxel, en la
	# sombra de un edificio salía como una mancha oscura casi invisible.
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = smoke_tex
	m.albedo_color = Color(1, 1, 1, 1)
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.disable_receive_shadows = true
	m.no_depth_test = false
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.proximity_fade_enabled = true       # se funde con el suelo/paredes en vez de cortarse
	m.proximity_fade_distance = 0.2       # corto: el polvo nace pegado a las superficies
	m.particles_anim_h_frames = 1
	m.particles_anim_v_frames = 1
	return m

# ---------------------------------------------------------------------------
# Emisores
# ---------------------------------------------------------------------------
## Polvo. `puff` = variante rápida y pequeña (impactos de bala); si no, nube lenta que se expande.
func _make_dust(puff: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = (8 if puff else 16) if quality <= 1 else (12 if puff else 28)
	p.lifetime = 0.9 if puff else 2.6
	p.explosiveness = 0.85
	p.randomness = 0.3
	p.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 85.0
	pm.initial_velocity_min = 1.2 if puff else 0.8
	pm.initial_velocity_max = 3.0 if puff else 2.4
	pm.gravity = Vector3(0, 0.15, 0) if not puff else Vector3(0, -0.5, 0)   # la nube grande asciende despacio
	pm.damping_min = 1.2
	pm.damping_max = 2.2
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -25.0
	pm.angular_velocity_max = 25.0
	pm.scale_min = 0.7
	pm.scale_max = 1.5
	pm.scale_curve = scale_curve_tex
	pm.alpha_curve = alpha_curve_tex
	pm.lifetime_randomness = 0.35
	pm.color = Color(0.62, 0.57, 0.5, 0.85)
	p.process_material = pm
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.0, 1.0) if puff else Vector2(1.8, 1.8)
	mesh.material = _smoke_material()
	p.draw_pass_1 = mesh
	add_child(p)
	return p

## HUMO DE LA BOCA DEL ARMA. Grupo propio y aparte del polvo por dos razones: es un efecto que se
## dispara MUCHO (diez veces por segundo con un fusil) y tiene que ser barato y discreto, y ademas
## no puede pasar por el humo simulado contra voxels, que cuesta lo suyo por particula y esta
## pensado para explosiones y derrumbes, no para cada tiro.
## Lanza los chorros y el temblor de calor de una explosion de radio `radius`.
func tendrils(pos: Vector3, radius: float) -> void:
	_lanzar_chorros(pos, radius)
	# DISTORSION POR CALOR. El primer intento era una esfera 3D con un shader que leia la pantalla:
	# salia una BOLA BLANCA. En una malla normal `hint_screen_texture` se lee antes de que exista la
	# copia de pantalla, asi que devuelve blanco. Se hace donde esa tecnica si funciona: como efecto
	# de PANTALLA en el HUD (igual que el desenfoque de movimiento). Aqui solo se guarda el punto en
	# el mundo y cada frame se proyecta a la pantalla, que es lo que el shader necesita.
	if quality >= 2:
		_heat_vivos.append([pos, 0.0, 0.60 + radius * 0.10, radius])


# ---------------------------------------------------------------------------
# TENDRILS: los chorros de humo negro con la punta encendida que salen despedidos de una explosion.
#
# Tres intentos hasta dar con esto, y los dos primeros valen de aviso:
#  1) Estelas de particulas (GPUParticles3D + trail_enabled), con QuadMesh y luego con
#     RibbonTrailMesh + `use_particle_trails`: NO SE VEIAN.
#  2) Un cono alargado por chorro: se veia, pero un solido con aristas parece "un triangulo de
#     papel", no humo.
# Lo que si lo parece: cada chorro es una HILERA DE BOCANADAS blandas -- cuadros con la textura de
# humo, siempre de cara a la camara -- con la cabeza encendida delante y el humo abriendose y
# oscureciendose hacia la cola. El borde difuso de la textura es lo que quita la sensacion de
# recorte de papel.
# ---------------------------------------------------------------------------
## Bocanadas por chorro. Con 5 quedaban SEPARADAS y el chorro se leia como manchas sueltas en vez
## de como un hilo: hacen falta las suficientes para que se solapen entre si.
const CHORRO_PUFFS := 7

var _puff_pool: Array[MeshInstance3D] = []
var _chorros: Array = []          ## [nodos, origen, direccion, largo, tiempo, vida, giro]
var _puff_i := 0

func _puff_node(cabeza: bool) -> MeshInstance3D:
	if _puff_pool.size() < 90:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1.0, 1.0)
		mi.mesh = q
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		m.albedo_texture = smoke_tex          # textura blanda: sin ella vuelven los bordes duros
		m.disable_receive_shadows = true
		m.no_depth_test = false
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_puff_pool.append(mi)
		return mi
	_puff_i = (_puff_i + 1) % _puff_pool.size()
	return _puff_pool[_puff_i]


func _lanzar_chorros(pos: Vector3, radius: float) -> void:
	if particle_scale <= 0.0 or smoke_tex == null:
		return
	var f: float = clampf(radius / 4.0, 0.35, 2.2)
	# menos chorros, pero cada uno con mas cuerpo: se lee mejor que muchos hilos flojos
	var n := int(clampf(5.0 + 3.0 * f, 4.0, 9.0) * clampf(particle_scale, 0.4, 1.0))
	for i in n:
		# repartidos por toda la esfera, con desorden y sesgo hacia arriba (abajo esta el suelo)
		var a := randf() * TAU
		var b := acos(randf_range(-0.5, 1.0))
		var dir := Vector3(sin(b) * cos(a), cos(b), sin(b) * sin(a)).normalized()
		var nodos: Array = []
		for j in CHORRO_PUFFS:
			nodos.append(_puff_node(j == 0))
		_chorros.append([nodos, pos + dir * (radius * 0.3), dir,
			radius * randf_range(2.0, 4.5), 0.0, randf_range(0.7, 1.4) + 0.3 * f, randf() * TAU])


## Cada chorro sale disparado, se abre y se apaga de naranja a negro.
func _update_chorros(dt: float) -> void:
	var i := _chorros.size() - 1
	while i >= 0:
		var e: Array = _chorros[i]
		e[4] += dt
		var k: float = e[4] / float(e[5])
		var nodos: Array = e[0]
		if k >= 1.0:
			for nd in nodos:
				if is_instance_valid(nd):
					nd.visible = false
			_chorros.remove_at(i)
			i -= 1
			continue
		_chorros[i] = e
		i -= 1
		var origen: Vector3 = e[1]
		var dir: Vector3 = e[2]
		var largo: float = float(e[3])
		var giro: float = float(e[6])
		# sale rapido y frena: casi todo el recorrido en el primer tercio
		var avance: float = 1.0 - pow(1.0 - k, 2.6)
		# ejes de lado, para separar cada bocanada un poco del eje y que el chorro serpentee
		var lado := dir.cross(Vector3.UP)
		if lado.length() < 0.01:
			lado = Vector3.RIGHT
		lado = lado.normalized()
		var lado2 := dir.cross(lado).normalized()
		for j in nodos.size():
			var nd: MeshInstance3D = nodos[j]
			if not is_instance_valid(nd):
				continue
			# t = 0 en la CABEZA (lo que va delante, encendido) y 1 en la cola (humo)
			var t: float = float(j) / float(maxi(nodos.size() - 1, 1))
			# la hilera ocupa el 55 % del recorrido, no el 85 %: asi las bocanadas se pisan y forman
			# un hilo continuo en vez de ir dejando huecos entre una y otra
			var d: float = largo * avance * (1.0 - t * 0.55)
			var serpiente: float = sin(giro + t * 3.4) * largo * 0.055
			nd.global_position = origen + dir * d 				+ lado * serpiente + lado2 * cos(giro * 1.7 + t * 2.9) * largo * 0.045 				+ Vector3(0, 0.8 * k * k * (0.3 + t), 0)          # la cola sube: es humo caliente
			# la cabeza es pequena y la cola se abre segun se deshace
			var tam: float = largo * (0.085 + 0.20 * t) * (0.60 + 0.70 * k)
			nd.scale = Vector3(tam, tam, tam)
			var m := nd.material_override as StandardMaterial3D
			# cabeza encendida los primeros instantes; el resto, humo negro desde el principio
			# cabeza encendida mas marcada: es "la mecha de la punta"
			var calor: float = clampf((1.0 - t * 3.2) * (1.0 - k * 1.5), 0.0, 1.0)
			var col: Color = Color(0.07, 0.065, 0.06).lerp(Color(1.0, 0.62, 0.16), calor)
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if calor > 0.30 else BaseMaterial3D.BLEND_MODE_MIX
			m.albedo_color = Color(col.r, col.g, col.b, (1.0 - k * k) * (0.40 + 0.50 * (1.0 - t)))
			nd.visible = true


## Proyecta las explosiones vivas a coordenadas de pantalla y le pasa al HUD la mas fuerte.
func _update_heat(dt: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var hud = player.hud if (player and is_instance_valid(player) and "hud" in player) else null
	var mejor := 0.0
	var uv := Vector2(0.5, 0.5)
	var rad := 0.2
	var i := _heat_vivos.size() - 1
	while i >= 0:
		var e: Array = _heat_vivos[i]
		e[1] += dt
		var k: float = e[1] / float(e[2])
		if k >= 1.0:
			_heat_vivos.remove_at(i)
			i -= 1
			continue
		_heat_vivos[i] = e
		i -= 1
		if cam == null or hud == null:
			continue
		var pos3: Vector3 = e[0]
		if cam.is_position_behind(pos3):
			continue
		var f: float = (1.0 - k) * (1.0 - k)
		if f <= mejor:
			continue
		# radio en pantalla: se proyecta el centro y un punto a `radius` de distancia lateral
		var vp: Vector2 = get_viewport().get_visible_rect().size
		var c2: Vector2 = cam.unproject_position(pos3)
		var b2: Vector2 = cam.unproject_position(pos3 + cam.global_transform.basis.x * float(e[3]) * 1.6)
		mejor = f
		uv = c2 / vp
		rad = clampf(c2.distance_to(b2) / maxf(vp.x, 1.0), 0.04, 0.9)
	if hud and hud.has_method("set_heat"):
		hud.set_heat(uv, rad, mejor)


# --- VAHO AL RESPIRAR ---------------------------------------------------------------------------
# Solo con nieve. Es de esas cosas que nadie mira, pero un mapa nevado donde nadie respira se lee
# como decorado. Un grupo compartido de cuatro emisores da para el jugador y para los que tenga
# delante: cada aliento dura menos de un segundo y se respira cada tres, asi que no se pisan.
var vaho_pool: Array[GPUParticles3D] = []
var vaho_i := 0


func _make_vaho() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 5
	p.lifetime = 0.95
	p.explosiveness = 0.55
	p.randomness = 0.5
	p.visibility_aabb = AABB(Vector3(-1.2, -1.2, -1.2), Vector3(2.4, 2.4, 2.4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.025
	pm.direction = Vector3(0, 0, -1)
	pm.spread = 20.0
	pm.initial_velocity_min = 0.35
	pm.initial_velocity_max = 0.75
	pm.damping_min = 1.4               # el aliento sale y se para: no es humo que suba
	pm.damping_max = 2.4
	pm.gravity = Vector3(0, 0.28, 0)   # y despues sube flojito, porque va caliente
	pm.scale_min = 0.35
	pm.scale_max = 0.7
	pm.scale_curve = scale_curve_tex
	pm.alpha_curve = alpha_curve_tex
	pm.lifetime_randomness = 0.35
	pm.color = Color(0.92, 0.94, 0.98, 0.17)   # apenas se ve, como debe ser
	p.process_material = pm
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.22, 0.22)
	mesh.material = _smoke_material()
	p.draw_pass_1 = mesh
	add_child(p)
	return p


## Un aliento. `pos` la boca, `dir` hacia donde mira la cara. Lo llaman el jugador y los demas
## cuerpos; si no hay nieve no hace nada, asi que se puede llamar sin comprobar.
func vaho(pos: Vector3, dir: Vector3, frio := 1.0) -> void:
	if frio <= 0.05 or particle_scale <= 0.0:
		return
	if vaho_pool.is_empty():
		for _i in 4:
			vaho_pool.append(_make_vaho())
	var p: GPUParticles3D = vaho_pool[vaho_i % vaho_pool.size()]
	vaho_i = (vaho_i + 1) % vaho_pool.size()
	p.global_position = pos
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = dir.normalized()
	pm.color.a = 0.17 * clampf(frio, 0.0, 1.0) * clampf(particle_scale, 0.3, 1.0)
	FxDormir.lanzar(p)
	p.emitting = true


# --- SALPICADURAS ------------------------------------------------------------------------------
# Pisar un charco. Sale gratis en informacion: el mapa de techos ya dice donde llega la lluvia y
# `mojado` dice cuanto, asi que aqui solo hay que tirar cuatro gotas hacia arriba y a los lados.
var chapoteo_pool: Array[GPUParticles3D] = []
var chapoteo_i := 0


func _make_chapoteo() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 14
	p.lifetime = 0.55
	p.explosiveness = 1.0
	p.randomness = 0.5
	p.visibility_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.06
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 62.0                    # hacia arriba y abriendose, como el agua al pisarla
	pm.initial_velocity_min = 1.1
	pm.initial_velocity_max = 2.8
	pm.gravity = Vector3(0, -9.8, 0)    # gotas de verdad: suben y caen
	pm.scale_min = 0.6
	pm.scale_max = 1.5
	pm.lifetime_randomness = 0.4
	pm.color = Color(0.86, 0.92, 1.0, 0.95)
	p.process_material = pm
	var q := QuadMesh.new()
	# GOTAS QUE SE VEAN. A 3 cm eran puntos: correcto de tamano y completamente invisible en
	# movimiento, que es cuando ocurren. El agua salpicada se ve porque refleja, no porque sea grande.
	q.size = Vector2(0.055, 0.055)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.88, 0.94, 1.0, 0.92)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.disable_receive_shadows = true
	q.material = mat
	p.draw_pass_1 = q
	add_child(p)
	return p


## `fuerza` sube con la velocidad: correr salpica mas que andar, y caerse mas que correr.
func chapoteo(pos: Vector3, fuerza := 1.0) -> void:
	if fuerza <= 0.05 or particle_scale <= 0.0:
		return
	if chapoteo_pool.is_empty():
		for _i in 4:
			chapoteo_pool.append(_make_chapoteo())
	var p: GPUParticles3D = chapoteo_pool[chapoteo_i % chapoteo_pool.size()]
	chapoteo_i = (chapoteo_i + 1) % chapoteo_pool.size()
	p.global_position = pos
	var pm := p.process_material as ParticleProcessMaterial
	var f: float = clampf(fuerza, 0.3, 2.5)
	pm.initial_velocity_min = 1.0 * f
	pm.initial_velocity_max = 2.6 * f
	p.amount_ratio = clampf(0.45 + 0.45 * f, 0.35, 1.0)
	FxDormir.lanzar(p)
	p.emitting = true


func _make_muzzle() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 4 if quality <= 1 else 6
	# Al salir UNA VEZ POR RAFAGA (y no por tiro) puede permitirse durar mas y moverse despacio:
	# es un canon caliente humeando, no el fogonazo.
	p.lifetime = 0.95
	p.explosiveness = 0.75
	p.randomness = 0.4
	p.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.03
	pm.direction = Vector3(0, 0, -1)   # se reorienta en cada disparo hacia donde apunta el canon
	pm.spread = 14.0
	pm.initial_velocity_min = 0.45
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0, 0.75, 0)   # se despega del canon y se deshace hacia arriba
	pm.damping_min = 2.0               # frena pronto: no es una estela, es una nubecilla
	pm.damping_max = 3.5
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -60.0
	pm.angular_velocity_max = 60.0
	pm.scale_min = 0.10
	pm.scale_max = 0.22
	pm.scale_curve = scale_curve_tex
	pm.alpha_curve = alpha_curve_tex
	pm.lifetime_randomness = 0.4
	pm.color = Color(0.78, 0.76, 0.72, 0.30)   # gris claro y MUY translucido: es un detalle, no una cortina
	p.process_material = pm
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.55, 0.55)
	mesh.material = _smoke_material()
	p.draw_pass_1 = mesh
	add_child(p)
	return p


## Bocanada de humo en la boca del canon. `dir` es hacia donde apunta el arma; `fuerza` sube con el
## calibre (una escopeta echa mas que una pistola).
func muzzle_smoke(pos: Vector3, dir: Vector3, fuerza := 1.0) -> void:
	if muzzle_pool.is_empty() or particle_scale <= 0.0:
		return
	var p: GPUParticles3D = muzzle_pool[muzzle_i % muzzle_pool.size()]
	muzzle_i = (muzzle_i + 1) % muzzle_pool.size()
	p.global_position = pos
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = dir.normalized()
	var f: float = clampf(fuerza, 0.3, 2.5)
	pm.initial_velocity_min = 0.40 * f
	pm.initial_velocity_max = 1.05 * f
	pm.scale_min = 0.09 * f
	pm.scale_max = 0.20 * f
	# con la calidad baja (o el humo bajado en el menu) se ve menos, pero no desaparece del todo
	pm.color.a = 0.30 * clampf(particle_scale, 0.3, 1.0)
	p.amount_ratio = clampf(0.5 + 0.5 * f, 0.4, 1.0)
	FxDormir.lanzar(p)
	p.emitting = true


func _make_sparks() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 26
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.randomness = 0.4
	p.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 55.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 11.0
	pm.gravity = Vector3(0, -14, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.5
	pm.particle_flag_align_y = true          # la chispa se alinea con su velocidad: estela
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.scale_curve = _curve([Vector2(0, 1.0), Vector2(0.7, 0.8), Vector2(1, 0.0)])
	pm.color_ramp = _gradient(Color(1.0, 0.95, 0.7, 1.0), Color(1.0, 0.35, 0.05, 0.0))
	pm.lifetime_randomness = 0.5
	p.process_material = pm
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.018, 0.22, 0.018)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.emission_enabled = true
	m.emission = Color(1.0, 0.55, 0.15)
	m.emission_energy_multiplier = 4.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = m
	p.draw_pass_1 = mesh
	add_child(p)
	return p

## La salpicadura de sangre: gotas rojas oscuras, sin brillo, que caen (como las chispas pero sin luz ni estela larga)
func _make_blood_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 14
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.randomness = 0.4
	p.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 45.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0, -14, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.5
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.scale_curve = _curve([Vector2(0, 1.0), Vector2(0.7, 0.8), Vector2(1, 0.0)])
	pm.color = Color(0.42, 0.03, 0.03)
	pm.lifetime_randomness = 0.5
	p.process_material = pm
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.03, 0.06, 0.03)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	mesh.material = m
	p.draw_pass_1 = mesh
	add_child(p)
	return p

## Fuego de explosión (explosion.lua::fireUpdate): bolas naranjas emisivas que suben y encogen, vida 0,5-1,3 s.
func _make_fire() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 48 if quality <= 1 else 80
	p.lifetime = 1.0
	p.explosiveness = 0.6
	p.randomness = 0.5
	p.visibility_aabb = AABB(Vector3(-10, -10, -10), Vector3(20, 20, 20))
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 6.0
	pm.gravity = Vector3(0, 4.0, 0)          # ParticleGravity(1..10): el fuego sube
	pm.damping_min = 3.0
	pm.damping_max = 6.0
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.scale_curve = _curve([Vector2(0, 1.0), Vector2(0.6, 0.6), Vector2(1, 0.15)])
	pm.color_ramp = _gradient(Color(1.0, 0.6, 0.4, 1.0), Color(1.0, 0.3, 0.2, 0.0))   # ParticleColor(1,.6,.4 -> 1,.3,.2), alfa 1->0
	pm.lifetime_randomness = 0.6
	p.process_material = pm
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.0, 1.0)
	var m := _smoke_material()
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.emission_enabled = true
	m.emission = Color(1.0, 0.45, 0.2)
	m.emission_energy_multiplier = 3.0   # ParticleEmissive(2..5)
	m.proximity_fade_enabled = false
	mesh.material = m
	p.draw_pass_1 = mesh
	add_child(p)
	return p

## Nube lateral rápida (explosionLarge): anillo de ~125 partículas a 8-12 m/s que se frena (drag 0,2).
func _make_cloud() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 60 if quality <= 1 else 120
	p.lifetime = 1.0
	p.explosiveness = 1.0
	p.randomness = 0.4
	p.visibility_aabb = AABB(Vector3(-16, -8, -16), Vector3(32, 16, 32))
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 1, 0)
	pm.emission_ring_radius = 1.0
	pm.emission_ring_inner_radius = 0.9
	pm.emission_ring_height = 0.2
	pm.direction = Vector3(1, 0, 0)
	pm.spread = 180.0
	pm.flatness = 0.9                          # casi sólo horizontal
	pm.initial_velocity_min = 8.0
	pm.initial_velocity_max = 12.0
	pm.radial_velocity_min = 8.0
	pm.radial_velocity_max = 12.0
	pm.gravity = Vector3.ZERO
	pm.damping_min = 6.0
	pm.damping_max = 9.0
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	pm.scale_curve = _curve([Vector2(0, 0.3), Vector2(1, 1.0)])   # ParticleRadius(0.3, 1.0)
	pm.alpha_curve = _curve([Vector2(0, 1.0), Vector2(0.4, 0.6), Vector2(1, 0.0)])   # easeout
	pm.color = Color(0.8, 0.75, 0.7, 0.9)
	pm.lifetime_randomness = 0.5
	p.process_material = pm
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	mesh.material = _smoke_material()
	p.draw_pass_1 = mesh
	add_child(p)
	return p

func _gradient(a: Color, b: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------
## Polvo: `size` escala la nube (0.3 impacto de bala, 1-4 derrumbe). `tint` = color del material roto.
## EL POLVO ES GRIS (2026-09-28, pedido: "todo el polvo -golpes, disparos, explosiones- sale marron, barro, tierra;
## me gustaria gris"). Del color que llegue se queda casi solo su luminosidad: un 12 % del tono, para que el ladrillo
## no salga igual que el hormigon. Lo usan el polvo, el humo y la nube de los derrumbes.
static func _gris(c: Color, tono: float = 0.12) -> Color:
	var l := c.get_luminance()
	return Color(l, l, l).lerp(c, tono)


func dust(pos: Vector3, size: float, tint: Color = Color(0.62, 0.62, 0.63)) -> void:
	if used_this_frame >= budget_per_frame:
		return
	used_this_frame += 1
	var small := size < 0.6
	var pool := puff_pool if small else dust_pool
	if pool.is_empty():
		return
	var idx := (puff_i if small else dust_i) % pool.size()
	var p := pool[idx]
	if small: puff_i = (puff_i + 1) % pool.size()
	else: dust_i = (dust_i + 1) % pool.size()
	var s := clampf(size, 0.3, 4.0)
	p.global_position = pos + Vector3(0, 0.25 * s, 0)
	# Las partículas viven en coordenadas globales: la escala del nodo NO las agranda. El tamaño
	# de la nube se aplica al material: tamaño de partícula, radio de emisión y velocidad.
	var pm := p.process_material as ParticleProcessMaterial
	pm.scale_min = maxf(0.4, 0.7 * s)
	pm.scale_max = maxf(0.8, 1.5 * s)
	pm.emission_sphere_radius = 0.25 * s
	pm.initial_velocity_min = (1.2 if small else 0.9) * s
	pm.initial_velocity_max = (3.0 if small else 2.6) * s
	p.lifetime = (0.9 if small else 2.2) + 0.5 * s
	# polvo GRIS: el material casi sin color, mezclado con un gris claro (antes, con un beis de tierra: salia marron)
	var c := _gris(tint).lerp(Color(0.72, 0.72, 0.73), 0.55).srgb_to_linear()
	pm.color = Color(c.r, c.g, c.b, 0.9 if small else 0.85)
	# partículas proporcionales al tamaño del impacto: un balazo (0,4 m) no necesita 16 quads a pantalla
	# completa; en la GPU integrada el relleno de estos quads translúcidos es el mayor pico de combate.
	p.amount_ratio = clampf(s / 1.5, 0.35, 1.0)
	FxDormir.lanzar(p)
	p.emitting = true
	# explosiones grandes: segunda capa más baja y ancha (polvo que rueda por el suelo)
	if s >= 1.2 and used_this_frame < budget_per_frame and dust_pool.size() > 1:
		used_this_frame += 1
		var p2 := dust_pool[dust_i]
		dust_i = (dust_i + 1) % dust_pool.size()
		p2.global_position = pos + Vector3(0, 0.1 * s, 0)
		var pm2 := p2.process_material as ParticleProcessMaterial
		pm2.scale_min = 0.9 * s
		pm2.scale_max = 1.8 * s
		pm2.emission_sphere_radius = 0.5 * s
		pm2.initial_velocity_min = 1.5 * s
		pm2.initial_velocity_max = 3.5 * s
		pm2.color = Color(c.r * 0.85, c.g * 0.85, c.b * 0.85, 0.75)
		p2.lifetime = 2.6 + 0.6 * s
		FxDormir.lanzar(p2)
		p2.emitting = true

## Explosión completa con la receta de Teardown (data/script/explosion.lua: explosionSmall/Medium/Large):
## chispas, fuego, humo que sube, flash + brasa de luz y, en las grandes, la nube lateral. `radius` en m.
# ---------------------------------------------------------------------------
# HUMO VOLUMETRICO. El humo de particulas es un monton de carteles planos: en cuanto te acercas se
# ve que son laminas y atraviesan las paredes. Esto es un VOLUMEN de niebla, asi que se mete entre
# las ruinas y se ve distinto segun por donde lo mires.
# Se guardan unos pocos y se van reciclando, como todo lo demas aqui.
# ---------------------------------------------------------------------------
var _humo_pool: Array[FogVolume] = []
var _humo_vivos: Array = []          ## [FogVolume, vida, total]
var _humo_i := 0
var _humo_mat: ShaderMaterial = null

func _humo_material() -> ShaderMaterial:
	if _humo_mat != null:
		return _humo_mat
	_humo_mat = ShaderMaterial.new()
	_humo_mat.shader = load("res://shaders/humo.gdshader")
	if ResourceLoader.exists("res://assets/ruido_humo_0.png"):
		_humo_mat.set_shader_parameter("noise00", load("res://assets/ruido_humo_0.png"))
		_humo_mat.set_shader_parameter("noise01", load("res://assets/ruido_humo_1.png"))
	return _humo_mat


## Una nube de humo que se queda en el sitio y se deshace. `r` es el radio de la explosion.
## PRECALENTAR: la primera explosion de la partida costaba 158 ms (medido con --bancofps): el material
## del humo volumetrico se cargaba entonces (shader + dos texturas de ruido) y las particulas de cada
## pool se dibujaban por primera vez. Aqui se hace todo eso durante la carga, bajo el suelo, delante de
## la camara para que entre en el encuadre (y se compile lo que haya que compilar) sin verse.
func precalentar(pos: Vector3) -> void:
	var _t0 := Time.get_ticks_msec()
	humo_volumetrico(pos, 1.5)
	for p in spark_pool + blood_part_pool + fire_pool + dust_pool + puff_pool + cloud_pool:
		if p and is_instance_valid(p):
			p.global_position = pos
			FxDormir.lanzar(p)
			p.emitting = true
	dust(pos, 1.0)
	smoke(pos, 0.5, Color(0.36, 0.35, 0.34), 0.25)
	tendrils(pos, 2.0)
	print("[effects] precalentado en %d ms" % (Time.get_ticks_msec() - _t0))


func humo_volumetrico(pos: Vector3, r: float) -> void:
	if quality <= 0 or Settings.is_mobile():
		return          # niebla volumetrica en un movil no: cuesta demasiado
	var f: FogVolume
	if _humo_pool.size() < 6:
		f = FogVolume.new()
		f.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		# cada nube lleva SU material: si comparten uno, comparten tambien la vida y se apagan todas
		# a la vez, aunque hayan reventado en momentos distintos
		var m := _humo_material().duplicate() as ShaderMaterial
		f.material = m
		add_child(f)
		_humo_pool.append(f)
	else:
		_humo_i = (_humo_i + 1) % _humo_pool.size()
		f = _humo_pool[_humo_i]
	var lado: float = clampf(r * 3.2, 3.0, 16.0)
	f.size = Vector3(lado, lado * 0.9, lado)
	f.global_position = pos + Vector3(0, lado * 0.30, 0)
	f.visible = true
	var dur: float = clampf(4.0 + r * 1.2, 4.0, 11.0)
	_humo_vivos.append([f, dur, dur])


func _update_humo(dt: float) -> void:
	var i := _humo_vivos.size() - 1
	while i >= 0:
		var e: Array = _humo_vivos[i]
		var f: FogVolume = e[0]
		if not is_instance_valid(f):
			_humo_vivos.remove_at(i)
			i -= 1
			continue
		e[1] -= dt
		var k: float = clampf(e[1] / maxf(e[2], 0.01), 0.0, 1.0)
		(f.material as ShaderMaterial).set_shader_parameter("vida", k)
		# y sube despacio mientras se deshace, como el humo de verdad
		f.global_position.y += dt * 0.35
		if e[1] <= 0.0:
			f.visible = false
			_humo_vivos.remove_at(i)
		else:
			_humo_vivos[i] = e
		i -= 1


# --- QUEMADURAS ---------------------------------------------------------------------------------
# Cada explosion deja la superficie de alrededor chamuscada (voxel.gdshader, `quemas`). Desde el 2026-10-11 (pedido) sin
# las brasas rojas del filo y SIN DESAPARECER DE GOLPE: cada mancha dura QUEMA_VIDA s y se apaga en QUEMA_APAGA s (el
# shader va con `quemas_fin`); si se llenan las QUEMAS_MAX, la mas vieja empieza a apagarse antes de que haga falta su
# sitio (desde QUEMAS_AVISO en uso). El reloj del shader solo corre mientras alguna se este apagando o viva.
const QUEMAS_MAX := 16
# LAS QUEMADURAS PERMANENTES (2026-10-28, pedido): cada explosion pinta su negro en un volumen de celdas de QUEMA_CELDA m
# que cubre el mapa (R8, voxel.gdshader `quema_vol`) y se queda TODA LA PARTIDA. El sombreado hace una lectura por pixel
# en vez del bucle de 16. Mapas enormes (mas de QUEMA_VOL_MAX celdas): celdas de 2 m. Se sube a la tarjeta como mucho
# cada 0,2 s. --quemasantes = las 16 que se apagan.
const QUEMA_CELDA := 1.0
var explosiones: Array[Vector3] = []   ## donde hubo explosiones esta partida (camara_fin.gd)
const QUEMA_VOL_MAX := 3000000
var _qv_datos := PackedByteArray()
var _qv_dim := Vector3i.ZERO
var _qv_celda := 1.0
var _qv_tex: ImageTexture3D = null
var _qv_sucio := false
var _qv_t := 0.0
static var _quemas_antes_v := -1

static func _quemas_antes() -> bool:
	if _quemas_antes_v < 0:
		_quemas_antes_v = 1 if "--quemasantes" in OS.get_cmdline_user_args() else 0
	return _quemas_antes_v == 1


func _quema_vol_pintar(pos: Vector3, radius: float) -> void:
	if _qv_dim == Vector3i.ZERO:
		var tam: Vector3 = world.get_world_size()
		_qv_celda = QUEMA_CELDA
		if (tam.x / _qv_celda) * (tam.y / _qv_celda) * (tam.z / _qv_celda) > QUEMA_VOL_MAX:
			_qv_celda = 2.0
		_qv_dim = Vector3i(maxi(1, ceili(tam.x / _qv_celda)), maxi(1, ceili(tam.y / _qv_celda)), maxi(1, ceili(tam.z / _qv_celda)))
		_qv_datos.resize(_qv_dim.x * _qv_dim.y * _qv_dim.z)
	# lo mismo que el bucle de antes: negro pegado al agujero, degradado hasta 1,7 radios
	var r_fuera := radius * 1.7 + _qv_celda
	var c := pos / _qv_celda
	var rc := r_fuera / _qv_celda
	for z in range(maxi(0, floori(c.z - rc)), mini(_qv_dim.z, ceili(c.z + rc) + 1)):
		for y in range(maxi(0, floori(c.y - rc)), mini(_qv_dim.y, ceili(c.y + rc) + 1)):
			for x in range(maxi(0, floori(c.x - rc)), mini(_qv_dim.x, ceili(c.x + rc) + 1)):
				var d := (Vector3(x + 0.5, y + 0.5, z + 0.5) * _qv_celda).distance_to(pos)
				var v := 1.0 - smoothstep(radius * 0.9, radius * 1.7, d)
				if v <= 0.0:
					continue
				var i := x + _qv_dim.x * (y + _qv_dim.y * z)
				var b := int(v * 255.0)
				if b > _qv_datos[i]:
					_qv_datos[i] = b
	_qv_sucio = true


func _quema_vol_tick(dt: float) -> void:
	_qv_t += dt
	if not _qv_sucio or _qv_t < 0.2 or world == null or world.opaque_material == null:
		return
	_qv_t = 0.0
	_qv_sucio = false
	var capas: Array[Image] = []
	var por_capa := _qv_dim.x * _qv_dim.y
	for z in _qv_dim.z:
		capas.append(Image.create_from_data(_qv_dim.x, _qv_dim.y, false, Image.FORMAT_R8, _qv_datos.slice(z * por_capa, (z + 1) * por_capa)))
	var m := world.opaque_material as ShaderMaterial
	if _qv_tex == null:
		_qv_tex = ImageTexture3D.new()
		_qv_tex.create(Image.FORMAT_R8, _qv_dim.x, _qv_dim.y, _qv_dim.z, false, capas)
		m.set_shader_parameter("quema_vol", _qv_tex)
		m.set_shader_parameter("quema_tam", Vector3(_qv_dim) * _qv_celda)
		m.set_shader_parameter("quema_on", 1)
	else:
		_qv_tex.update(capas)
const QUEMAS_AVISO := 12
const QUEMA_VIDA := 60.0
const QUEMA_APAGA := 4.0     ## el mismo 4.0 del shader
var _quemas: PackedVector4Array = PackedVector4Array()
var _quemas_fin: PackedFloat32Array = PackedFloat32Array()
var _quema_reloj := 0.0
var _quemas_hasta := 0.0

func quemadura(pos: Vector3, radius: float) -> void:
	if world == null or world.opaque_material == null or not (world.opaque_material is ShaderMaterial):
		return
	if explosiones.size() < 300:
		explosiones.append(pos)          # para la camara de cine del final (camara_fin.gd)
	if not _quemas_antes():
		_quema_vol_pintar(pos, radius)
		return
	if _quemas.size() < QUEMAS_MAX:
		_quemas.resize(QUEMAS_MAX)
		_quemas_fin.resize(QUEMAS_MAX)
		for k in QUEMAS_MAX:
			_quemas_fin[k] = -100.0
	# un sitio libre (ya apagada) o, si no hay, la que antes se acabe
	var slot := 0
	for k in QUEMAS_MAX:
		if _quemas_fin[k] < _quemas_fin[slot]:
			slot = k
	_quemas[slot] = Vector4(pos.x, pos.y, pos.z, radius)
	_quemas_fin[slot] = _quema_reloj + QUEMA_VIDA + QUEMA_APAGA
	# MUCHAS A LA VEZ: la mas vieja empieza ya a apagarse, para que cuando haga falta su sitio no se vaya de golpe
	var vivas := 0
	for k in QUEMAS_MAX:
		if _quemas_fin[k] > _quema_reloj:
			vivas += 1
	if vivas >= QUEMAS_AVISO:
		var vieja := -1
		for k in QUEMAS_MAX:
			if k != slot and _quemas_fin[k] > _quema_reloj + QUEMA_APAGA and (vieja < 0 or _quemas_fin[k] < _quemas_fin[vieja]):
				vieja = k
		if vieja >= 0:
			_quemas_fin[vieja] = _quema_reloj + QUEMA_APAGA
	var m := world.opaque_material as ShaderMaterial
	m.set_shader_parameter("quemas", _quemas)
	m.set_shader_parameter("quemas_fin", _quemas_fin)
	m.set_shader_parameter("quemas_n", QUEMAS_MAX)
	m.set_shader_parameter("quemas_reloj", _quema_reloj)
	_quemas_hasta = 0.0
	for k in QUEMAS_MAX:
		_quemas_hasta = maxf(_quemas_hasta, _quemas_fin[k])


func _tick_quemas(dt: float) -> void:
	_quema_vol_tick(dt)
	_quema_reloj += dt
	if _quema_reloj > _quemas_hasta + 0.5 or world == null or world.opaque_material == null:
		return
	var m := world.opaque_material as ShaderMaterial
	m.set_shader_parameter("quemas_reloj", _quema_reloj)
	# todas apagadas: el shader ya no entra en el bucle
	if _quema_reloj > _quemas_hasta:
		m.set_shader_parameter("quemas_n", 0)


static var _misiles: Array = []     # [posicion, instante] de los ultimos cohetes que han reventado

static func misil_revienta(p: Vector3) -> void:
	_misiles.append([p, Time.get_ticks_msec()])
	if _misiles.size() > 8:
		_misiles.pop_front()

static func _fue_misil(p: Vector3) -> bool:
	var ahora := Time.get_ticks_msec()
	for m in _misiles:
		if ahora - int(m[1]) < 1500 and (m[0] as Vector3).distance_to(p) < 3.0:
			return true
	return false


## EL FUEGO DE LAS EXPLOSIONES (ajuste "Fuego de las explosiones", 2026-10-05, pedido: "una animacion muy fuerte;
## quiero poder desactivarla"): sin el, ni bola de fuego ni chorros de humo con la punta encendida (ni su temblor de
## calor). Quedan el fogonazo de luz, las chispas, el polvo y el humo. Solo imagen: el daño no cambia.
var fuego_on := true

func explosion(pos: Vector3, radius: float) -> void:
	var _tq := Time.get_ticks_usec()
	quemadura(pos, radius)
	Prof.add("ex.quemadura", Time.get_ticks_usec() - _tq)
	# BAJO EL AGUA NO HAY FUEGO NI HUMO. Para el motor el mar es aire: la explosion abre su crater en la
	# arena del fondo igual que en tierra, y eso esta bien. Pero la bola de fuego, el humo y la tierra en
	# la lente bajo tres metros de agua quedaban ridiculos. Ahi lo que se ve es la columna de agua que
	# sube a la superficie.
	var ag = AguaScript.actual
	if ag != null:
		var sup: float = ag.nivel_en(pos)
		if sup > -INF and sup - pos.y > 0.6:
			_explosion_bajo_agua(pos, radius, sup)
			return
	var _tx := Time.get_ticks_usec()
	# las puertas del mapa (puertas.gd) se sacuden o saltan de los goznes
	get_tree().call_group("gestor_puertas", "onda", pos, radius)
	# SACUDIDA: una explosion cerca mueve la vista. Cae con la distancia y se acaba en ~0,4 s.
	if player and is_instance_valid(player) and player.has_method("add_shake"):
		var d: float = player.global_position.distance_to(pos)
		var _tsh := Time.get_ticks_usec()
		if d < radius * 8.0:
			player.add_shake(clampf(radius * 0.10 * (1.0 - d / (radius * 8.0)), 0.0, 0.3))
		Prof.add("ex.sh.sacudida", Time.get_ticks_usec() - _tsh)
		_tsh = Time.get_ticks_usec()
		# TIERRA Y VAHO EN LA LENTE. Solo de cerca; que lo estes viendo o no lo decide el jugador,
		# que es quien tiene la camara.
		# LA TIERRA SOLO LLEGA DE CERCA. Era 4 radios (un misil de 4 m salpicaba desde 16 m: "estoy
		# lejos y me llega tierra"); ahora 2, la mitad.
		if d < radius * 2.0 and player.has_method("ensuciar_lente"):
			player.ensuciar_lente(pos, clampf(1.0 - d / (radius * 2.0), 0.15, 1.0))
		Prof.add("ex.sh.lente", Time.get_ticks_usec() - _tsh)
		_tsh = Time.get_ticks_usec()
		# SORDERA: solo si ha reventado MUY cerca. Todo suena amortiguado unos segundos y queda un
		# pitido agudo. Si el estallido te mata, se corta al momento (lo hace `die`).
		if d < radius * 2.0 and player.health > 0.0:
			Audio.deafen(clampf(1.0 - d / (radius * 2.0), 0.25, 1.0))
		Prof.add("ex.sh.sordera", Time.get_ticks_usec() - _tsh)
	Prof.add("ex.shake", Time.get_ticks_usec() - _tx); _tx = Time.get_ticks_usec()
	# LO QUE NO SE VE NO SE SIMULA (nivel_fx): fuera de pantalla, nada de imagen; se apunta por si la miras luego
	var nv := nivel_fx(pos, radius)
	fx_niveles[nv] += 1
	if nv >= 1:
		var mn0 := get_parent()
		if mn0 and mn0.has_method("refrescar_techo"):
			mn0.refrescar_techo(pos, radius * 1.4)
	if nv == 3:
		_fx_pendientes.append([pos, radius, Time.get_ticks_msec() * 0.001])
		if _fx_pendientes.size() > 24:
			_fx_pendientes.pop_front()
		return
	if nv >= 1:
		_explosion_lejana(pos, radius, nv)
		return
	humo_volumetrico(pos, radius)
	Prof.add("ex.humo", Time.get_ticks_usec() - _tx); _tx = Time.get_ticks_usec()
	# el boquete cambia lo que hay encima: el mapa de techos hay que rehacerlo ahi
	var mn := get_parent()
	if mn and mn.has_method("refrescar_techo"):
		mn.refrescar_techo(pos, radius * 1.4)
	Prof.add("ex.techo", Time.get_ticks_usec() - _tx); _tx = Time.get_ticks_usec()
	# LA ONDA, solo si la estas viendo: si revienta a tu espalda no tiene sentido doblar la pantalla.
	var mo := get_parent()
	var onda_ok: bool = not (mo and ("_onda_on" in mo) and not bool(mo._onda_on))
	# SOLO LOS MISILES (2026-09-23, pedido): la onda salia con granadas, C4 y barriles. Ahora solo si en ese sitio
	# acaba de reventar un cohete (rocket.gd lo apunta en `misil_revienta` justo antes de explotar).
	onda_ok = onda_ok and _fue_misil(pos)
	if onda_ok and player and is_instance_valid(player) and player.has_method("onda_en_pantalla"):
		player.onda_en_pantalla(pos, radius)
	Prof.add("ex.onda", Time.get_ticks_usec() - _tx); _tx = Time.get_ticks_usec()
	var large := radius >= 3.5
	var medium := radius >= 1.8 and not large
	var size: float = 0.8 if large else (0.5 if medium else 0.2)
	# chispas (50/30/10 a 5/3/2 m/s)
	if not spark_pool.is_empty():
		var p := spark_pool[spark_i]
		spark_i = (spark_i + 1) % spark_pool.size()
		p.global_position = pos
		var pm := p.process_material as ParticleProcessMaterial
		pm.direction = Vector3.UP
		pm.spread = 180.0
		pm.initial_velocity_min = (5.0 if large else (3.0 if medium else 2.0)) * 1.5
		pm.initial_velocity_max = (5.0 if large else (3.0 if medium else 2.0)) * 3.0
		p.amount_ratio = 1.0 if large else (0.6 if medium else 0.3)
		p.lifetime = 1.6
		FxDormir.lanzar(p)
		p.emitting = true
	# fuego (fire.size 0,8/0,5/0,2; vida 0,7/0,6/0,5 s)
	if fuego_on and not fire_pool.is_empty():
		var f := fire_pool[fire_i]
		fire_i = (fire_i + 1) % fire_pool.size()
		f.global_position = pos
		var fm := f.process_material as ParticleProcessMaterial
		fm.emission_sphere_radius = size * 0.6
		fm.scale_min = size * 1.5
		fm.scale_max = size * 3.0
		fm.initial_velocity_min = size * 4.0
		fm.initial_velocity_max = size * 12.0
		f.lifetime = 0.5 + size * 0.5
		f.amount_ratio = 1.0 if large else (0.6 if medium else 0.35)
		FxDormir.lanzar(f)
		f.emitting = true
	# humo (smoke.size 1,0/0,7/0,5, vida 3/1,5/1 s, sube): nube inicial rápida de GPU + humo simulado que
	# choca con el mundo (se queda bajo techos, se cuela por huecos, dura más en interiores)
	# Un cohete tiene que dejar un fogonazo y polvo, no una cortina de humo delante de la cara. La
	# nube de GPU se queda en la mitad del radio y el humo simulado (el que dura) en un tercio y con
	# poca cantidad: se nota que ha explotado ahi, pero se sigue viendo y se puede seguir jugando.
	Prof.add("ex.pools", Time.get_ticks_usec() - _tx); _tx = Time.get_ticks_usec()
	dust(pos, radius * 0.3, Color(0.8, 0.76, 0.72))
	Prof.add("ex.dust", Time.get_ticks_usec() - _tx); _tx = Time.get_ticks_usec()
	smoke(pos, radius * 0.2, Color(0.36, 0.35, 0.34), 0.25)
	Prof.add("ex.smoke", Time.get_ticks_usec() - _tx); _tx = Time.get_ticks_usec()
	# chorros de humo negro con la punta encendida + temblor de calor sobre la bola de fuego
	if fuego_on:
		tendrils(pos, radius)
	Prof.add("ex.tendrils", Time.get_ticks_usec() - _tx); _tx = Time.get_ticks_usec()
	# nube lateral rápida sólo en las grandes
	# La "nube lateral" (anillo de 120 partículas a 8-12 m/s) se ha quitado: eran partículas de GPU
	# sin colisión, así que la onda expansiva atravesaba paredes y escombros. El humo simulado de
	# `smoke()` sí choca con los voxels y hace ese trabajo bien; además ahorra 120 partículas por
	# explosión grande, que es donde estaba el pico de coste.
	# luz: flash (200/500/1000 durante 0,1/0,2/0,4 s) + brasa (15/30/50 durante 0,8/1,0/1,2 s)
	if light_scale > 0.0 and not light_pool.is_empty():
		var l := light_pool[light_i]
		light_i = (light_i + 1) % light_pool.size()
		l.global_position = pos
		l.omni_range = (6.0 + radius * 3.0) * light_scale
		l.visible = true
		# intensidades de Teardown (PointLight) escaladas a energía de OmniLight
		var flash_i: float = (1000.0 if large else (500.0 if medium else 200.0)) * 0.012
		var glow_i: float = (50.0 if large else (30.0 if medium else 15.0)) * 0.08
		_explosions.append([0.0, 0.4 if large else (0.2 if medium else 0.1), pos, size, l, 1.2 if large else (1.0 if medium else 0.8), flash_i, glow_i])

## LA EXPLOSION VISTA DE LEJOS (nivel_fx 1 y 2): el fogonazo, menos chispas y polvo, el humo justo, sin chorros ni nube
## volumetrica; la luz solo a media distancia
func _explosion_lejana(pos: Vector3, radius: float, nv: int) -> void:
	var large := radius >= 3.5
	var medium := radius >= 1.8 and not large
	var size: float = 0.8 if large else (0.5 if medium else 0.2)
	var k: float = 0.5 if nv == 1 else 0.3
	if nv == 1 and not spark_pool.is_empty():
		var p := spark_pool[spark_i]
		spark_i = (spark_i + 1) % spark_pool.size()
		p.global_position = pos
		var pm := p.process_material as ParticleProcessMaterial
		pm.direction = Vector3.UP
		pm.spread = 180.0
		pm.initial_velocity_min = (5.0 if large else (3.0 if medium else 2.0)) * 1.5
		pm.initial_velocity_max = (5.0 if large else (3.0 if medium else 2.0)) * 3.0
		p.amount_ratio = (1.0 if large else (0.6 if medium else 0.3)) * k
		p.lifetime = 1.6
		FxDormir.lanzar(p)
		p.emitting = true
	if fuego_on and not fire_pool.is_empty():
		var f := fire_pool[fire_i]
		fire_i = (fire_i + 1) % fire_pool.size()
		f.global_position = pos
		var fm := f.process_material as ParticleProcessMaterial
		fm.emission_sphere_radius = size * 0.6
		fm.scale_min = size * 1.5
		fm.scale_max = size * 3.0
		fm.initial_velocity_min = size * 4.0
		fm.initial_velocity_max = size * 12.0
		f.lifetime = 0.5 + size * 0.5
		f.amount_ratio = (1.0 if large else (0.6 if medium else 0.35)) * k
		FxDormir.lanzar(f)
		f.emitting = true
	dust(pos, radius * 0.3 * (0.8 if nv == 1 else 0.6), Color(0.8, 0.76, 0.72))
	smoke(pos, radius * 0.2, Color(0.36, 0.35, 0.34), 0.25 * k)
	if nv == 1 and light_scale > 0.0 and not light_pool.is_empty():
		var l := light_pool[light_i]
		light_i = (light_i + 1) % light_pool.size()
		l.global_position = pos
		l.omni_range = (6.0 + radius * 3.0) * light_scale
		l.visible = true
		var flash_i: float = (1000.0 if large else (500.0 if medium else 200.0)) * 0.012
		var glow_i: float = (50.0 if large else (30.0 if medium else 15.0)) * 0.08
		_explosions.append([0.0, 0.4 if large else (0.2 if medium else 0.1), pos, size, l, 0.6, flash_i, glow_i * 0.6])


## Chispas al golpear metal; `normal` orienta el chorro.
# ---------------------------------------------------------------------------
# TRAZADORES. La bala era invisible: salia el fogonazo y aparecia el agujero. Un trazador fino que
# RECORRE el camino (no aparece entero de golpe) es lo que hace que se vea que estas disparando algo.
# Se reutiliza un anillo de mallas: cero asignaciones por disparo.
# ---------------------------------------------------------------------------
## VELOCIDAD y aspecto del trazador. La primera version era un cuadrado dorado gordo que cruzaba la
## pantalla: horrible. Un trazador de verdad es un hilo casi blanco, finisimo, que se ve un instante
## y se apaga; el color calido solo se nota en la estela que deja detras.
## A QUE VELOCIDAD CRUZA LA ESTELA. A 420 m/s se veia LA BALA VIAJANDO: un punto amarillo cruzando el
## aire, que es justo lo que no debe parecer -en el juego el disparo es instantaneo-. A 1.100 m/s (lo
## que va una bala de fusil de verdad) el ojo solo pilla el rayajo, no el punto.
## LA BALA SE VE VIAJAR (2026-09-25, pedido: "no veo la bala viajar; quiero que se vea el proyectil, bala
## transparente, amarillo no tan amarillo"). A 1.100 m/s y con 1 cm de grueso cruzaba la pantalla en uno o
## dos fotogramas y no se veia. Ahora va a velocidad DE VISTA (no de fisica: el impacto sigue siendo en el
## acto), mas gruesa y corta, como una bala con su estelita, semitransparente y de un amarillo palido.
const TRACER_SPEED := 170.0
const TRACER_R := 0.045         ## m de radio de la cabeza (exagerado a proposito: a 20 m una de 2 cm eran 2 pixeles)
const TRACER_LEN := 2.6         ## m de largo: la bala y su estela
var _traza_n := 0               ## para dejar estela solo una de cada tres balas
const TRACER_MIN := 2.5         ## por debajo de esta distancia no se dibuja (a bocajarro molesta)
var _tracers: Array = []        ## [malla, desde, hacia, avance, vida]
var _tracer_pool: Array[MeshInstance3D] = []
var _tracer_i := 0
var _tracer_mat: StandardMaterial3D = null

const AguaScript := preload("res://scripts/agua.gd")

## La explosion que revienta bajo el agua: sacudida (amortiguada por el agua, y sin sordera ni tierra en
## la lente) y un surtidor de chapoteos en la superficie encima, mas alto cuanto mas cerca de ella.
func _explosion_bajo_agua(pos: Vector3, radius: float, sup: float) -> void:
	var hondo: float = sup - pos.y
	var fuerza: float = clampf(radius * 0.8 * (1.0 - hondo / (radius * 4.0)), 0.4, 2.5)
	if player and is_instance_valid(player) and player.has_method("add_shake"):
		var d: float = player.global_position.distance_to(pos)
		if d < radius * 6.0:
			player.add_shake(clampf(radius * 0.06 * (1.0 - d / (radius * 6.0)), 0.0, 0.18))
	var arriba := Vector3(pos.x, sup + 0.03, pos.z)
	chapoteo(arriba, fuerza * 1.6)
	for i in 3:
		var a: float = TAU * float(i) / 3.0 + randf() * 0.6
		chapoteo(arriba + Vector3(cos(a), 0.0, sin(a)) * radius * 0.35, fuerza)
	# (el estampido lo pone quien llama, con Audio.explosion, igual que en tierra)


func _tracer_node() -> MeshInstance3D:
	if _tracer_pool.size() < 48:
		if _tracer_mat == null:
			_tracer_mat = StandardMaterial3D.new()
			_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_tracer_mat.albedo_color = Color(1.0, 0.93, 0.66, 0.55)   # amarillo palido y transparente
			_tracer_mat.emission_enabled = true
			_tracer_mat.emission = Color(1.0, 0.86, 0.52)             # calido, no dorado chillon
			_tracer_mat.emission_energy_multiplier = 1.5
			_tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_tracer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			_tracer_mat.no_depth_test = false
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = TRACER_R
		cm.bottom_radius = TRACER_R * 0.25    # se afina hacia atras, como una estela
		cm.height = 1.0
		cm.radial_segments = 5
		cm.rings = 0
		mi.mesh = cm
		mi.material_override = _tracer_mat.duplicate()   # cada uno con su alfa
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_tracer_pool.append(mi)
		return mi
	_tracer_i = (_tracer_i + 1) % _tracer_pool.size()
	return _tracer_pool[_tracer_i]


## Estela de un disparo, de la boca del arma al impacto.
func tracer(from: Vector3, to: Vector3, _largo: float = 0.0, empieza_m: float = 0.0) -> void:
	if empieza_m > 0.0:
		from = from + (to - from).normalized() * minf(empieza_m, from.distance_to(to))   # no pegada a la cara
	# EN TODAS LAS CALIDADES (2026-09-25): con los efectos al minimo -lo normal en el movil y en el PC del
	# usuario- no salia ni una bala, en ningun modo. Es una malla de cinco lados de un pool: no cuesta nada.
	var dist: float = from.distance_to(to)
	if dist < TRACER_MIN:
		return          # a quemarropa solo seria un borron delante de la cara
	# TODAS LAS BALAS SE VEN (pedido). Lo de "una de cada tres" venia de las trazadoras de verdad, pero con el
	# jugador filtrando tambien otra de cada tres se veia una de cada NUEVE: parecia que no salia nada.
	var mi := _tracer_node()
	mi.visible = true
	_tracers.append([mi, from, to, 0.0, 1.0])


func _update_tracers(dt: float) -> void:
	var i := _tracers.size() - 1
	while i >= 0:
		var t: Array = _tracers[i]
		var mi: MeshInstance3D = t[0]
		if not is_instance_valid(mi):
			_tracers.remove_at(i)
			i -= 1
			continue
		var from: Vector3 = t[1]
		var to: Vector3 = t[2]
		t[3] += TRACER_SPEED * dt
		var dist: float = from.distance_to(to)
		var dir: Vector3 = (to - from) / maxf(0.001, dist)
		var head: Vector3 = from + dir * minf(t[3], dist)
		var tail: Vector3 = from + dir * clampf(t[3] - TRACER_LEN, 0.0, dist)
		var largo: float = head.distance_to(tail)
		if t[3] - TRACER_LEN >= dist or largo < 0.05:
			mi.visible = false
			_tracers.remove_at(i)
			i -= 1
			continue
		# el cilindro va de cola a cabeza; en Godot el cilindro crece en Y, asi que se orienta con
		# look_at (que mira por -Z) y se gira 90 grados
		mi.global_position = (head + tail) * 0.5
		mi.look_at(mi.global_position + dir, Vector3.UP)
		mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		mi.scale = Vector3(1.0, largo, 1.0)
		# se apaga segun se acerca al final: no desaparece de golpe
		t[4] = clampf(1.0 - (t[3] - TRACER_LEN) / maxf(1.0, dist), 0.15, 1.0)
		var m := mi.material_override as StandardMaterial3D
		m.albedo_color.a = 0.55 * float(t[4])
		m.emission_energy_multiplier = 1.5 * float(t[4])
		_tracers[i] = t
		i -= 1


# ---------------------------------------------------------------------------
# CASQUILLOS. Saltan del arma, giran, botan una vez y suenan al caer. Es adorno puro y es de lo que
# mas se nota. Sin fisica de verdad: parabola a mano, un bote y a dormir.
# ---------------------------------------------------------------------------
var _shells: Array = []          ## [malla, velocidad, giro, vida, boto]
var _shell_pool: Array[MeshInstance3D] = []
var _shell_i := 0

## CASQUILLO DE UN ARMA AJENA (otro jugador de la sala o un bot). El tuyo sale del arma de primera
## persona; los demas no tienen arma de primera persona, asi que sale de la de su avatar.
## Sin esto, en red veias el fogonazo, el humo y la traza del otro, pero no soltaba una sola vaina.
func shell_ajena(wm, dir: Vector3) -> void:
	if wm == null or not is_instance_valid(wm) or quality <= 0:
		return
	var b: Basis = wm.global_transform.basis
	var from: Vector3 = wm.global_transform * (wm.muzzle_pos * 0.25 + Vector3(0.05, 0.03, 0.30))
	var v: Vector3 = b.x * randf_range(1.9, 3.1) + b.y * randf_range(1.4, 2.2) + b.z * randf_range(0.2, 0.9)
	shell(from, v, String(wm.kind) == "shotgun")


## `cartucho` = escopeta. Una escopeta no escupe vainas de laton: escupe CARTUCHOS, que son de
## plastico rojo, mas gordos y mas largos, y no brillan como el metal.
static var vainas_diag: Array = []      ## --vainasbot: quien suelta cada vaina

func shell(pos: Vector3, vel: Vector3, cartucho: bool = false, corta: bool = false) -> void:
	if quality <= 0:
		return
	if _vainas_diag_on:
		var st := get_stack()
		vainas_diag.append(String(st[1]["function"]) + "@" + String(st[1]["source"]).get_file() + ":" + str(st[1]["line"]) if st.size() > 1 else "?")
	var mi: MeshInstance3D
	if _shell_pool.size() < VAINAS_MAX:
		mi = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.008
		cm.bottom_radius = 0.009
		cm.height = 0.032
		cm.radial_segments = 6
		cm.rings = 0
		mi.mesh = cm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.85, 0.65, 0.25)
		m.metallic = 0.15
		m.roughness = 0.6
		m.metallic_specular = 0.2
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_shell_pool.append(mi)
	else:
		_shell_i = (_shell_i + 1) % _shell_pool.size()
		mi = _shell_pool[_shell_i]
	# el aspecto se pone en cada disparo, no al crear la pieza: el mismo monton de casquillos sirve
	# para el laton del fusil y para el cartucho de la escopeta
	var mat := mi.material_override as StandardMaterial3D
	if mat:
		if cartucho:
			mat.albedo_color = Color(0.62, 0.07, 0.05)   # plastico rojo
			mat.metallic = 0.0
			mat.roughness = 0.75
			mat.metallic_specular = 0.2
			mat.emission_enabled = true
			mat.emission = Color(0.12, 0.01, 0.0)
		else:
			# LATON SIN METAL DE VERDAD (2026-10-12, bug del movil: "un reflejo como de sol y puntos negros"): con metallic 0,9
			# y sin reflejos del cielo, en el movil la vaina salia NEGRA y su brillo especular, pasado de 1, encendia el
			# resplandor (glow) en el suelo. Ahora casi mate, con un poco de luz propia para que se lea dorada
			mat.albedo_color = Color(0.85, 0.65, 0.25)
			mat.metallic = 0.15
			mat.roughness = 0.6
			mat.metallic_specular = 0.2
			mat.emission_enabled = true
			mat.emission = Color(0.25, 0.18, 0.05)
	# la de 9 mm (pistolas y subfusiles de pistola), corta y fina; la de fusil, la de siempre; el cartucho, gordo y largo
	mi.scale = (Vector3(1.55, 1.85, 1.55) if cartucho else (Vector3(0.85, 0.6, 0.85) if corta else Vector3.ONE)) * VAINA_ESCALA
	mi.visible = true
	mi.global_position = pos
	mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	# EL SUELO, UNA VEZ al salir (2026-10-12, bug: "las vainas ya no quedan en el piso"): find_ground no lo encontraba y
	# caian atravesandolo; ahora un rayo hacia abajo. Y se quedan en el suelo VAINA_VIDA s.
	var suelo := pos.y - 50.0
	if world != null:
		var h: Dictionary = world.raycast(pos + Vector3.UP * 0.05, Vector3.DOWN, 8.0)
		if h.get("hit", false):
			suelo = (h["position"] as Vector3).y
	# (la pieza reutilizada es la mas vieja: deja de moverse como la de antes)
	for k in range(_shells.size() - 1, -1, -1):
		if _shells[k][0] == mi:
			_shells.remove_at(k)
	_shells.append([mi, vel, Vector3(randf_range(-14, 14), randf_range(-8, 8), randf_range(-14, 14)), VAINA_VIDA, false, suelo, 0])


static var _vainas_diag_on: bool = "--vainasbot" in OS.get_cmdline_user_args()
const VAINA_ESCALA := 1.8   ## mas grandes que de verdad (pedido: "no se ven"): a tamaño real eran puntos
const VAINAS_MAX := 20      ## vainas a la vez (las mas viejas se reutilizan)
const VAINA_VIDA := 9.0     ## segundos que dura cada una (en el suelo casi todo)

func _update_shells(dt: float) -> void:
	var i := _shells.size() - 1
	while i >= 0:
		var sh: Array = _shells[i]
		var mi: MeshInstance3D = sh[0]
		if not is_instance_valid(mi):
			_shells.remove_at(i)
			i -= 1
			continue
		var v: Vector3 = sh[1]
		v.y -= 22.0 * dt
		var np: Vector3 = mi.global_position + v * dt
		var gy: float = float(sh[5])
		if bool(sh[4]):
			# ya en el suelo: quieta, tumbada
			np = mi.global_position
			v = Vector3.ZERO
		elif np.y <= gy + 0.008 and v.y < 0.0:
			np.y = gy + 0.008
			sh[6] = int(sh[6]) + 1
			if int(sh[6]) == 1:
				Audio.play3d("clickup", np, -14.0, 0.3, 12.0, Audio.PRI_LOW)   # tintineo del casquillo
				v = Vector3(v.x * 0.35, absf(v.y) * 0.28, v.z * 0.35)
				sh[2] = (sh[2] as Vector3) * 0.4
			else:
				sh[4] = true          # al segundo bote se queda
				var r: Vector3 = mi.rotation
				mi.rotation = Vector3(PI * 0.5, r.y, 0.0)
		mi.global_position = np
		if not bool(sh[4]):
			mi.rotation += sh[2] * dt
		sh[1] = v
		sh[3] -= dt
		if sh[3] <= 0.0:
			mi.visible = false
			_shells.remove_at(i)
		else:
			_shells[i] = sh
		i -= 1


# ---------------------------------------------------------------------------
# SANGRE. Un impacto en el cuerpo tiene que verse distinto de uno en la pared: salpicadura roja en
# la direccion del disparo y, si hay pared detras, una mancha que se queda.
# ---------------------------------------------------------------------------
var _blood_pool: Array[MeshInstance3D] = []
var _manchas_t := 0.0


## LA SANGRE SE VA CON LA PARED (2026-10-27, pedido: "rompo la pared y la salpicadura queda flotando"): 4 veces por
## segundo se mira si el voxel donde se pego cada mancha sigue ahi (son 14 como mucho). `--sangreflotante` = como antes.
func _manchas_tick(dt: float) -> void:
	_manchas_t -= dt
	if _manchas_t > 0.0 or world == null or _sangre_flotante:
		return
	_manchas_t = 0.25
	for mi in _blood_pool:
		if not mi.visible or not mi.has_meta("ancla"):
			continue
		var a: Vector3 = mi.get_meta("ancla")
		if not world.box_solid(a - Vector3.ONE * 0.05, a + Vector3.ONE * 0.05):
			mi.visible = false
static var _sangre_flotante := "--sangreflotante" in OS.get_cmdline_user_args()
var _blood_i := 0
var _blood_mats: Array[StandardMaterial3D] = []


## UNA MANCHA DE VERDAD, NO UN CUADRADO. La mancha era el QuadMesh entero pintado de rojo oscuro al 90 %: un
## cuadrado, y en el movil, con su luz, un cuadrado NEGRO semitransparente (pedido 2026-09-21). Ahora lleva
## una textura hecha aqui: una mancha central de borde irregular y unas gotas alrededor, transparente por
## fuera. Tres variantes (semilla distinta) para que no se repita la misma forma en la pared.
func _mat_mancha(variante: int) -> StandardMaterial3D:
	const N := 64
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 + variante * 104729
	var ruido := FastNoiseLite.new()
	ruido.seed = 31 + variante
	ruido.frequency = 0.09
	# gotas: [centro, radio] en coordenadas 0..1
	var gotas: Array = []
	for g in rng.randi_range(5, 9):
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(0.30, 0.46)
		gotas.append([Vector2(0.5, 0.5) + Vector2(cos(ang), sin(ang)) * dist, rng.randf_range(0.025, 0.06)])
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	for y in N:
		for x in N:
			var p := Vector2((x + 0.5) / N, (y + 0.5) / N)
			var d := p.distance_to(Vector2(0.5, 0.5))
			# borde irregular: el radio de la mancha central sube y baja con el ruido
			var borde := 0.26 + 0.07 * ruido.get_noise_2d(x, y)
			var a := 1.0 - smoothstep(borde - 0.04, borde + 0.02, d)
			for gt in gotas:
				var dg: float = p.distance_to(gt[0])
				a = maxf(a, 1.0 - smoothstep(float(gt[1]) * 0.6, float(gt[1]), dg))
			# el centro mas denso y oscuro que el borde, como sangre que se ha secado
			var oscuro := 0.75 + 0.25 * (1.0 - clampf(d / 0.3, 0.0, 1.0))
			img.set_pixel(x, y, Color(0.55 * oscuro, 0.02, 0.02, a * 0.92))
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.albedo_color = Color.WHITE
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.roughness = 0.35
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	return mat

var blood_n := 0        ## cuantas veces se ha llamado (diagnostico)

func blood(pos: Vector3, dir: Vector3) -> void:
	if quality <= 0:
		return
	blood_n += 1
	# salpicadura: sus propias particulas (las de las chispas se quedaban rojas)
	if not blood_part_pool.is_empty():
		var p: GPUParticles3D = blood_part_pool[blood_part_i]
		blood_part_i = (blood_part_i + 1) % blood_part_pool.size()
		p.global_position = pos
		var pm := p.process_material as ParticleProcessMaterial
		if pm:
			pm.direction = dir
		FxDormir.lanzar(p)
		p.emitting = true
	# mancha en lo que haya detras (a 2,5 m como mucho)
	if world == null:
		return
	var r: Dictionary = world.raycast(pos, dir.normalized(), 2.5)
	if not r.hit:
		return
	if _blood_mats.is_empty():
		for k in 3:
			_blood_mats.append(_mat_mancha(k))
	var mi: MeshInstance3D
	if _blood_pool.size() < 14:
		mi = MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1, 1)
		mi.mesh = qm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_blood_pool.append(mi)
	else:
		_blood_i = (_blood_i + 1) % _blood_pool.size()
		mi = _blood_pool[_blood_i]
	mi.material_override = _blood_mats[randi() % _blood_mats.size()]
	var n: Vector3 = r.normal if r.has("normal") else -dir
	mi.visible = true
	mi.global_position = r.position + n * 0.03
	if absf(n.dot(Vector3.UP)) > 0.95:
		mi.look_at_from_position(mi.global_position, mi.global_position - n, Vector3.FORWARD)
	else:
		mi.look_at_from_position(mi.global_position, mi.global_position - n, Vector3.UP)
	var sc: float = randf_range(0.25, 0.55)
	mi.scale = Vector3(sc, sc * randf_range(0.7, 1.3), 1.0)
	mi.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	# el voxel en el que se ha pegado: si se rompe, la mancha se va con el (_manchas_tick)
	mi.set_meta("ancla", r.position - n * 0.06)


## Nube de polvo que SE QUEDA tras un derrumbe: ciega la zona 15-20 s. Se apoya en el humo
## simulado contra los voxels, que ya rellena las habitaciones en vez de atravesar las paredes.
func collapse_dust(pos: Vector3, size: float, tint: Color) -> void:
	if nivel_fx(pos, size) >= 2:
		return
	# un solo foco y pequeno: marca donde ha caido el cacho, sin cortina
	smoke(pos, clampf(size * 0.3, 0.4, 0.9), tint.lerp(Color(0.66, 0.66, 0.67), 0.6), 0.3)


## IMPACTO SEGUN EL MATERIAL: el hormigon escupe polvo gris, el metal chispas, la madera astillas
## oscuras y el cristal esquirlas claras. Antes todo era la misma nube de polvo.
func impact(pos: Vector3, normal: Vector3, mat: int, color: Color) -> void:
	var cls: String = Audio.material_class(mat)
	# lo que no se ve no se simula (nivel_fx): fuera de pantalla o muy lejos, nada; a media distancia, sin chispas
	var nv := nivel_fx(pos, 0.3)
	if nv >= 2:
		if cls == "glass":
			grieta(pos)          # la grieta es del cristal, no un efecto: se queda
		return
	if nv == 1:
		dust(pos, 0.22, color.lerp(Color(0.68, 0.66, 0.62), 0.45))
		if cls == "glass":
			grieta(pos)
		return
	match cls:
		"metal":
			sparks(pos, normal)
			dust(pos, 0.16, Color(0.7, 0.7, 0.72))
		"glass":
			sparks(pos, normal)
			dust(pos, 0.2, Color(0.82, 0.9, 0.95))
			grieta(pos)
		"wood":
			dust(pos, 0.3, Color(0.45, 0.33, 0.2))
		"dirt", "sand":
			dust(pos, 0.42, color.lerp(Color(0.55, 0.48, 0.38), 0.5))
		_:
			dust(pos, 0.32, color.lerp(Color(0.68, 0.66, 0.62), 0.45))


# --- GRIETAS EN EL CRISTAL ----------------------------------------------------------------------
# Una lista corta y circular: las 16 ultimas. No se borran solas -un cristal no se cura- sino que la
# mas vieja deja sitio a la nueva. Con 16 da de sobra para que una luna se llene de estrellas antes
# de venirse abajo, y el coste en el shader es fijo pase lo que pase.
const GRIETAS_MAX := 16
var _grietas: PackedVector4Array = PackedVector4Array()
var _grieta_i := 0


func grieta(pos: Vector3, radio := 0.55) -> void:
	if world == null or world.glass_material == null:
		return
	var mn := get_parent()
	if mn and ("_cristal_roto" in mn) and not bool(mn._cristal_roto):
		return
	if _grietas.size() < GRIETAS_MAX:
		_grietas.resize(GRIETAS_MAX)
	_grietas[_grieta_i] = Vector4(pos.x, pos.y, pos.z, radio)
	_grieta_i = (_grieta_i + 1) % GRIETAS_MAX
	(world.glass_material as ShaderMaterial).set_shader_parameter("impactos", _grietas)


## Borra las grietas y deja el cristal como nuevo. Lo usa el menu grafico al apagar el efecto: con
## la lista a cero el shader sale por el camino corto y no cuesta nada.
func limpiar_grietas() -> void:
	if world == null or world.glass_material == null:
		return
	_grietas = PackedVector4Array()
	_grietas.resize(GRIETAS_MAX)
	_grieta_i = 0
	(world.glass_material as ShaderMaterial).set_shader_parameter("impactos", _grietas)


func sparks(pos: Vector3, normal: Vector3) -> void:
	if spark_pool.is_empty() or used_this_frame >= budget_per_frame:
		return
	used_this_frame += 1
	var p := spark_pool[spark_i]
	spark_i = (spark_i + 1) % spark_pool.size()
	p.global_position = pos + normal * 0.05
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = normal if normal.length() > 0.1 else Vector3.UP
	# (la explosion usa estas mismas y les cambia la forma: aqui vuelven a las de un impacto, ver _make_sparks)
	pm.spread = 55.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 11.0
	p.amount_ratio = 1.0
	p.lifetime = 0.6
	FxDormir.lanzar(p)
	p.emitting = true
	# el impacto en metal también levanta una pizca de polvo gris
	if not puff_pool.is_empty() and used_this_frame < budget_per_frame:
		dust(pos, 0.3, Color(0.5, 0.5, 0.52))


# --- LOS TROZOS DEL MAZO -------------------------------------------------------------------------
# Pedido 2026-10-11: "el mazo no genere bloques; que rompa al instante, pero que simule la destruccion con fisicas bajas:
# trozos que salen del golpe y desaparecen con efecto". El mazo abre el hueco vaporizando (sin bloques de Jolt) y aqui
# salen trozos SOLO DE IMAGEN: una multimalla de cubos con gravedad, un rebote en el suelo (la altura se mira con UN rayo
# al nacer) y se encogen hasta desaparecer. Sin trozos vivos la multimalla se esconde y no cuesta nada.
const TROZOS_MAX := 48
const TROZO_VIDA := 1.4
var _trozos_mm: MultiMeshInstance3D = null
var trozo_mat: ShaderMaterial = null   ## main.gd: trozo.gdshader (color y textura del material)
var _trozos: Array = []          ## [pos, vel, suelo_y, edad, tam, color, giro_eje, giro_vel]

func trozos_mazo(punto: Vector3, normal: Vector3, color: Color, n: int = 12, mat_id: int = -1) -> void:
	var capa: float = float(world.get_material_capa(mat_id)) if world != null and mat_id >= 0 and world.has_method("get_material_capa") else -1.0
	var vs: float = world.get_voxel_size() if world != null and world.has_method("get_voxel_size") else 0.2
	if _trozos_mm == null:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.instance_count = TROZOS_MAX
		mm.visible_instance_count = 0
		var caja := BoxMesh.new()
		caja.size = Vector3.ONE
		if trozo_mat != null:
			caja.material = trozo_mat
		else:
			var mat := StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.roughness = 0.9
			caja.material = mat
		mm.mesh = caja
		_trozos_mm = MultiMeshInstance3D.new()
		_trozos_mm.multimesh = mm
		_trozos_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_trozos_mm.top_level = true
		add_child(_trozos_mm)
	var nrm := normal.normalized() if normal.length_squared() > 0.001 else Vector3.UP
	for i in n:
		if _trozos.size() >= TROZOS_MAX:
			_trozos.pop_front()
		var p := punto + nrm * 0.1 + Vector3(randf_range(-0.25, 0.25), randf_range(-0.25, 0.25), randf_range(-0.25, 0.25))
		var v := nrm * randf_range(1.5, 4.0) + Vector3(randf_range(-1.6, 1.6), randf_range(0.5, 2.8), randf_range(-1.6, 1.6))
		var suelo := p.y - 6.0
		if world != null and world.has_method("raycast"):
			var h: Dictionary = world.raycast(p + Vector3.UP * 0.05, Vector3.DOWN, 6.0)
			if h.get("hit", false):
				suelo = float((h.position as Vector3).y)
		# EL COLOR DEL MATERIAL, tal cual (antes se mezclaba con gris): en lineal, como las particulas del motor
		var c := color.srgb_to_linear()
		c.a = 1.0
		var lado := randf_range(0.07, 0.17)
		_trozos.append([p, v, suelo, 0.0, lado, c,
			Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5).normalized(), randf_range(4.0, 12.0),
			Color(capa, maxf(lado / vs, 1.0), randf(), 0.0)])
	_trozos_mm.visible = true


func _trozos_tick(dt: float) -> void:
	if _trozos_mm == null or not _trozos_mm.visible:
		return
	var mm := _trozos_mm.multimesh
	var vivos: Array = []
	for t in _trozos:
		t[3] += dt
		if t[3] >= TROZO_VIDA:
			continue
		var p: Vector3 = t[0]
		var v: Vector3 = t[1]
		v.y -= 14.0 * dt
		p += v * dt
		var lado: float = t[4]
		if p.y - lado * 0.5 < t[2]:
			p.y = t[2] + lado * 0.5
			if v.y < -1.0:
				v = Vector3(v.x * 0.5, -v.y * 0.3, v.z * 0.5)      # un rebote flojo
			else:
				v = Vector3(v.x * 0.8, 0.0, v.z * 0.8)
				t[7] = float(t[7]) * 0.85
		t[0] = p
		t[1] = v
		vivos.append(t)
	_trozos = vivos
	var k := 0
	for t in _trozos:
		var queda: float = 1.0 - float(t[3]) / TROZO_VIDA
		var esc: float = float(t[4]) * clampf(queda * 2.5, 0.0, 1.0)     # se encogen en el ultimo 40 %
		var b := Basis(t[6] as Vector3, float(t[3]) * float(t[7])).scaled(Vector3.ONE * maxf(esc, 0.001))
		mm.set_instance_transform(k, Transform3D(b, t[0]))
		mm.set_instance_color(k, t[5])
		mm.set_instance_custom_data(k, t[8])
		k += 1
	mm.visible_instance_count = k
	if k == 0:
		_trozos_mm.visible = false
