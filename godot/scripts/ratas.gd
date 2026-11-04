extends Node
## LAS RATAS DE LA HABITACION (2026-10-21, pedido: "una rata real que salga y persiga a los jugadores; enemigo de
## todos"). Modelo y clips: tools/blender/criaturas/rata.py -> res://criaturas/rata.glb. Cada rata es una criatura de
## siempre (criatura.gd) con el cerebro de perseguir: va a por el mas cercano, PERSONA O BOT (criatura.persigue_bots),
## muerde y, si la matan, al rato sale otra. Lo pide el <mapa>.br.json con "ratas": {"max", "primera", "cada",
## "salidas"}. Solo piensa quien manda (sin red, o el anfitrion).
## Pruebas: --map=cuarto --sinprecarga --ratastest (sale una enseguida y dice a por quien va) [--ratasfoto=<carpeta>].

const CriaturaScript := preload("res://scripts/criatura.gd")

## la rata: 4 m de cuerpo (una de verdad, a la escala del cuarto), rapida, muerde fuerte y aguanta unos tiros
const DATOS := {"nombre": "Rata", "vida": 260.0, "velocidad": 4.2, "vel_correr": 1.7, "dano": 22.0, "alcance": 2.8,
	"cadencia": 1.1, "amago": 0.36, "recuperar": 0.5, "alto": 1.4, "radio": 0.75, "salto": 6.0,
	"color": Color(0.30, 0.26, 0.23), "puntos": 250, "modelo": "res://criaturas/rata.glb",
	"vel_clip": {"caminar": 0.45, "correr": 2.0},
	# no sube: solo va a por quien este en el suelo (o a menos de 1,6 m por encima de ella)
	"solo_suelo": true, "alcance_alto": 1.6}

var main
var world
var jugador
var cfg := {}
var _cont: Node3D
var _vivas: Array = []
var _t := 0.0
var _prueba := false
var _sacadas := 0                ## las que han salido en la partida


func empezar(p_main: Node, p_world, p_jugador: Node3D, p_cfg: Dictionary) -> void:
	main = p_main
	world = p_world
	jugador = p_jugador
	cfg = p_cfg
	CriaturaScript.persigue_bots = true
	_cont = Node3D.new()
	_cont.name = "Ratas"
	main.add_child(_cont)
	_prueba = "--ratastest" in OS.get_cmdline_user_args() or "--ratasfoto" in " ".join(OS.get_cmdline_user_args())
	_t = 3.0 if _prueba else float(cfg.get("primera", 45.0))
	print("[ratas] la primera sale en %.0f s (como mucho %d a la vez)" % [_t, int(cfg.get("max", 3))])


func _exit_tree() -> void:
	CriaturaScript.persigue_bots = false


func _process(dt: float) -> void:
	if Net.is_online() and not Net.hosting:
		return
	if bool(main.get("loading")):
		return
	_vivas = _vivas.filter(func(r): return is_instance_valid(r) and float(r.get("vida")) > 0.0)
	_separar()
	_t -= dt
	if _t > 0.0:
		return
	_t = float(cfg.get("cada", 60.0))
	# CUANTAS SALEN (2026-10-22, pedido): una por minuto hasta 3; cada vez que la zona termina de cerrarse, 2 mas (de
	# a una por minuto); y ninguna mas cuando quedan 6 o menos vivos (personas y bots)
	var zb = main.get("zona_br")
	var cerradas := 0
	if zb != null and is_instance_valid(zb) and float(zb.t) >= float(zb.PRIMERA) + float(zb.CICLO):
		cerradas = int((float(zb.t) - float(zb.PRIMERA)) / float(zb.CICLO))
	if zb != null and is_instance_valid(zb) and zb.has_method("vivos") and zb.vivos().size() <= 6:
		return
	if _sacadas >= int(cfg.get("primeras", 3)) + 2 * cerradas:
		return
	_sacadas += 1
	_sacar()


## NO SE METEN UNA DENTRO DE OTRA (2026-10-21, pedido: "las ratas se superponen; que tengan colision entre ellas"):
## dos ratas mas cerca que dos radios se apartan cada una la mitad de lo que sobra (solo de lado: la altura no se toca)
func _separar() -> void:
	var r2: float = float(DATOS["radio"]) * 2.0
	for i in _vivas.size():
		var a: Node3D = _vivas[i]
		for j in range(i + 1, _vivas.size()):
			var b: Node3D = _vivas[j]
			var d: Vector3 = b.global_position - a.global_position
			d.y = 0.0
			var l := d.length()
			if l >= r2:
				continue
			var n: Vector3 = d / l if l > 0.001 else Vector3(1, 0, 0)
			var sobra := (r2 - l) * 0.5
			a.global_position -= n * sobra
			b.global_position += n * sobra


func _sacar() -> void:
	var salidas: Array = cfg.get("salidas", [])
	if salidas.is_empty():
		return
	var s: Array = salidas[randi() % salidas.size()]
	var c: CharacterBody3D = CriaturaScript.new()
	_cont.add_child(c)
	c.global_position = Vector3(float(s[0]), float(s[1]), float(s[2]))
	c.setup("rata", DATOS, world, jugador)
	c._obsesiva = randf() < 0.3
	_vivas.append(c)
	print("[ratas] sale una rata en %s" % str(c.global_position))
	if _prueba:
		_informe.call_deferred(c)


func _informe(c) -> void:
	for k in 4:
		await get_tree().create_timer(3.0).timeout
		if not is_instance_valid(c):
			return
		var obj = c.call("_objetivo_actual") if c.has_method("_objetivo_actual") else null
		print("[ratastest] rata en %s · va a por %s a %.1f m · vida %.0f" % [str(c.global_position),
			(obj.name if obj else "nadie"), (c.global_position.distance_to(obj.global_position) if obj else -1.0), float(c.vida)])
	for f in OS.get_cmdline_user_args():
		if String(f).begins_with("--ratasfoto="):
			var carpeta := String(f).substr(12)
			DirAccess.make_dir_recursive_absolute(carpeta)
			var cam := Camera3D.new()
			add_child(cam)
			cam.current = true
			for k in 3:
				var p: Vector3 = c.global_position
				cam.global_position = p + Vector3(5.5, 2.6, 4.5)
				cam.look_at(p + Vector3(0, 0.8, 0), Vector3.UP)
				for _i in 3:
					await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(carpeta.path_join("rata_juego_%d.png" % k))
				await get_tree().create_timer(0.8).timeout
	if "--ratastest" in OS.get_cmdline_user_args():
		print("[ratastest] TERMINADO")
		get_tree().quit()
