## EDITOR DE PUNTERIA. Abre el soldado apuntando, de frente y de cerca, para colocar el arma en el
## ojo a mano y ver el gesto del parpado.
##
## Existe porque afinar esto "a ciegas" no funciono: cada cambio pedia editar el codigo, volver a
## abrir el juego y mirar una captura, y con eso se fueron muchas vueltas para acabar con el fusil
## atravesado en la cara. Aqui se mueve una barra y el soldado se recoloca al momento.
##
## Cuando quede bien, COPIAR CONFIGURACION deja los valores en el portapapeles listos para pegar en
## avatar_animator.gd (aim_ojo, aim_delante, aim_giro).
##
## CON EL BOTON "ARMA: MAZO" el mismo panel pasa al mazazo: una barra congela el arco en cualquier
## punto (0 a 100 %) para poder posarlo, porque el golpe dura 0,4 s y a esa velocidad no se coloca
## nada. Ahi se editan las dos poses del gesto, los tiempos y las curvas, y se ve si el momento en
## que revienta el muro cae donde el hierro toca de verdad.
##
## Se abre con:  Godot --path godot -- --miraeditor
extends Control

const AvatarScript := preload("res://scripts/avatar_animator.gd")

const GOLD := Color(1.0, 0.83, 0.0)

var avatar
var cam: Camera3D
var titulo: Label
var _barras: Dictionary = {}          ## nombre -> [HSlider, Label]
var _vista := 0                       ## 0 de frente, 1 de perfil, 2 tres cuartos
var _cerca := false                   ## primer plano de la cara, para juzgar el ojo
## CLIPS QUE SE PUEDEN VER, con la pose de arma que le toca a cada uno y cuanto "se mueve" el
## personaje. Correr y andar usan poses distintas ("run" y "action"), asi que al cambiar de clip
## cambian tambien las barras de la pose.
const CLIPS := [
	["run_fwd", "run", "CORRIENDO", 1.0],
	["walk_fwd", "walk", "ANDANDO", 0.45],
	["idle_1", "action", "QUIETO", 0.0],
	["crouch_fwd", "crouch", "AGACHADO", 0.5],
	["jump_loop", "jump", "SALTANDO", 1.0],
]
var _clip := 0                        ## indice en CLIPS
var _pose_nombre := "run"
## Un contenedor por bloque: se enseña solo el que corresponde a lo que estas editando, y COPIAR
## copia solo eso. Con todo a la vez se copiaba la configuracion entera y luego habia que separar
## a mano que era de cada cosa.
var _caja_mira: VBoxContainer
var _caja_clip: VBoxContainer
var _caja_mazo: VBoxContainer
var _fila_mazo: HBoxContainer
var _fila_mazo2: HBoxContainer
## MAZO. `_congelado` para el arco parado en un punto y poder posar; sin eso el mazazo dura 0,4 s
## y no da tiempo ni a verlo, mucho menos a colocar nada.
var _arma := "rifle"
var _congelado := true
var _vel := 1.0                       ## camara lenta al reproducir: 1, 0,25 o 0,1
var _aviso_mazo: Label                ## donde cae el impacto respecto al arco
var _aviso_k: Label                   ## que pose manda en el punto congelado
## MIENTRAS SE MONTA EL PANEL, `_aplicar` no toca nada. Al rellenar las barras del mazo saltaban sus
## avisos de cambio, y `_aplicar` guardaba como "pose editada del fusil" las barras del fusil, que
## todavia estaban a cero: al abrir el editor las poses que habias hecho aparecian en blanco.
var _montando := true
## BUCLE. Reproducir una sola vez no sirve: el mazazo pasa, el arco se queda suelto y a partir de
## ahi mover las barras no se ve. En bucle el gesto se repite solo y puedes seguir editando encima.
var _bucle := false
var _bucle_t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_montar_escena()
	_montar_ui()
	_colocar_camara()
	if "--posetest" in OS.get_cmdline_user_args():
		_comprobar_poses()


## COMPROBACION: recorre los clips y contrasta lo que hay en las barras con lo que hay escrito en el
## codigo. Existe porque un fallo aqui no se ve (el editor abre igual) y te deja editar encima de
## ceros creyendo que estas retocando tus poses.
func _comprobar_poses() -> void:
	var mal := 0
	for i in CLIPS.size():
		_clip = i
		_aplicar_clip()
		var pr: Array = AvatarScript.HOLD_POSES["rifle"][_pose_nombre]
		var pos: Vector3 = pr[0]
		var rot: Vector3 = pr[1]
		var ok: bool = (absf(pos.x - _val("pos_x")) < 0.005 and absf(pos.y - _val("pos_y")) < 0.005
			and absf(pos.z - _val("pos_z")) < 0.005 and absf(rot.x - _val("rot_x")) < 0.05
			and absf(rot.y - _val("rot_y")) < 0.05 and absf(rot.z - _val("rot_z")) < 0.05)
		if not ok:
			mal += 1
		print("[poses] %-8s codigo %s %s · barras (%.3f, %.3f, %.3f) (%.1f, %.1f, %.1f) -> %s" % [
			_pose_nombre, str(pos), str(rot),
			_val("pos_x"), _val("pos_y"), _val("pos_z"),
			_val("rot_x"), _val("rot_y"), _val("rot_z"), "BIEN" if ok else "MAL"])
	print("[poses] %d de %d clips cargan tus valores -> %s" % [
		CLIPS.size() - mal, CLIPS.size(), "BIEN" if mal == 0 else "MAL"])
	get_tree().quit()


func _montar_escena() -> void:
	# El 3D NO puede colgar de este Control (vive en una capa 2D): se cuelga de la escena, que es
	# la que tiene el mundo 3D. Aqui solo queda la interfaz.
	var mundo := Node3D.new()
	var raiz: Node = get_tree().current_scene
	if raiz == null:
		raiz = get_tree().root
	raiz.add_child(mundo)
	avatar = AvatarScript.new()
	mundo.add_child(avatar)
	avatar.build(1.75, false)
	avatar.equip_rifle()
	avatar.aiming = false
	# el clip se pone con la misma funcion que usa el boton: asi al arrancar tambien se le dice al
	# avatar CUANTO SE MUEVE. Sin eso el motor lo cree quieto, no mezcla la pose de correr y mover
	# sus barras no hacia absolutamente nada.
	_aplicar_clip()
	# el modelo mira hacia -Z; la camara se pone en ese lado
	avatar.rotation.y = 0.0
	var sol := DirectionalLight3D.new()
	sol.rotation = Vector3(deg_to_rad(-28.0), deg_to_rad(200.0), 0.0)
	sol.light_energy = 1.6
	mundo.add_child(sol)
	var relleno := DirectionalLight3D.new()
	relleno.rotation = Vector3(deg_to_rad(-10.0), deg_to_rad(40.0), 0.0)
	relleno.light_energy = 0.5
	relleno.light_color = Color(0.75, 0.85, 1.0)
	mundo.add_child(relleno)
	cam = Camera3D.new()
	cam.fov = 16.0
	mundo.add_child(cam)
	cam.make_current()


## CAMARA LIBRE: se arrastra con el raton para girar alrededor del soldado y se acerca con la
## rueda. Los tres botones de VISTA siguen ahi como atajo a los angulos utiles (frente, perfil,
## tres cuartos), pero para juzgar si el arma tapa la cara hace falta poder mirar desde donde sea.
var _giro := Vector2(PI, -0.05)       ## rumbo y altura de la camara, en radianes
var _dist := 3.2                      ## metros hasta el personaje
var _alto := 1.15                     ## a que altura mira (cuerpo entero)
var _arrastrando := false

func _colocar_camara() -> void:
	var foco := Vector3(0.0, _alto, 0.0)
	var cy := cos(_giro.y)
	var dir := Vector3(sin(_giro.x) * cy, sin(_giro.y), cos(_giro.x) * cy)
	cam.position = foco + dir * _dist
	cam.look_at(foco, Vector3.UP)


## Se usa _unhandled_input a proposito: lo que se toca en el panel (barras, botones) lo consume la
## interfaz y no llega aqui, asi que arrastrar sobre una barra NO mueve la camara.
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var b := e as InputEventMouseButton
		if b.button_index == MOUSE_BUTTON_LEFT:
			_arrastrando = b.pressed
		elif b.pressed and b.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(0.55, _dist - 0.12)
			_colocar_camara()
		elif b.pressed and b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(6.0, _dist + 0.12)
			_colocar_camara()
	elif e is InputEventMouseMotion and _arrastrando:
		var m := e as InputEventMouseMotion
		_giro.x -= m.relative.x * 0.008
		# tope arriba y abajo: sin el, la camara se da la vuelta y se ve todo del reves
		_giro.y = clampf(_giro.y + m.relative.y * 0.006, -1.2, 1.2)
		_colocar_camara()


func _montar_ui() -> void:
	# LOS BOTONES VAN ARRIBA Y LAS BARRAS EN UNA LISTA CON SCROLL. Con todo seguido, al anadir las
	# del parpado el panel crecio mas que la pantalla y COPIAR CONFIGURACION se quedaba fuera, que
	# es justo el boton que hace falta al final.
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.09, 0.93)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(1)
	sb.border_color = Color(GOLD, 0.7)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 16
	panel.offset_top = 16
	panel.offset_bottom = -16
	panel.offset_right = 16 + 430
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	titulo = Label.new()
	titulo.text = "PUNTERIA"
	titulo.add_theme_font_size_override("font_size", 22)
	titulo.add_theme_color_override("font_color", GOLD)
	v.add_child(titulo)
	var ayuda := Label.new()
	ayuda.text = "Arrastra con el raton para girar la camara; rueda para acercarte."
	ayuda.add_theme_font_size_override("font_size", 12)
	ayuda.add_theme_color_override("font_color", Color(0.72, 0.76, 0.86))
	ayuda.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(ayuda)

	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 6)
	v.add_child(fila)
	fila.add_child(_boton("VISTA", func():
		_vista = (_vista + 1) % 3
		_giro = [Vector2(PI, -0.05), Vector2(PI * 0.5, -0.05), Vector2(PI * 0.75, -0.15)][_vista]
		_colocar_camara()))
	fila.add_child(_boton("REPRODUCIR OJO", func(): _repetir_ojo()))
	fila.add_child(_boton("CLIP", func(): _siguiente_clip()))
	var fila2 := HBoxContainer.new()
	fila2.add_theme_constant_override("separation", 6)
	v.add_child(fila2)
	fila2.add_child(_boton("VER / OCULTAR ARMA", func():
		if avatar and avatar.weapon_root and is_instance_valid(avatar.weapon_root):
			avatar.weapon_root.visible = not avatar.weapon_root.visible))
	fila2.add_child(_boton("APUNTAR SI / NO", func():
		if avatar:
			avatar.aiming = not avatar.aiming
		_refrescar_titulo()))
	fila2.add_child(_boton("CARA DE CERCA", func():
		_dist = 0.75 if _dist > 1.2 else 2.2
		_colocar_camara()))
	var fila3 := HBoxContainer.new()
	fila3.add_theme_constant_override("separation", 6)
	v.add_child(fila3)
	var copiar := _boton("COPIAR CONFIGURACION", func(): _copiar())
	copiar.custom_minimum_size = Vector2(0, 40)
	fila3.add_child(copiar)
	fila3.add_child(_boton("POR DEFECTO", func(): _por_defecto()))
	fila3.add_child(_boton("SALIR", func(): get_tree().quit()))
	var fila0 := HBoxContainer.new()
	fila0.add_theme_constant_override("separation", 6)
	v.add_child(fila0)
	var b_arma := _boton("ARMA: FUSIL", func(): pass)
	b_arma.pressed.connect(func():
		_cambiar_arma()
		b_arma.text = "ARMA: MAZO" if _arma == "sledge" else "ARMA: FUSIL")
	fila0.add_child(b_arma)
	_fila_mazo = HBoxContainer.new()
	_fila_mazo.add_theme_constant_override("separation", 6)
	v.add_child(_fila_mazo)
	var b_rep := _boton("REPRODUCIR EN BUCLE", func(): pass)
	b_rep.pressed.connect(func():
		_bucle_mazo(not _bucle)
		b_rep.text = "PARAR" if _bucle else "REPRODUCIR EN BUCLE")
	_fila_mazo.add_child(b_rep)
	var b_vel := _boton("VELOCIDAD x1", func(): pass)
	b_vel.pressed.connect(func():
		_vel = {1.0: 0.25, 0.25: 0.1, 0.1: 1.0}[_vel]
		b_vel.text = "VELOCIDAD x%s" % ("1" if _vel == 1.0 else str(_vel)))
	_fila_mazo.add_child(b_vel)
	# SALTOS A LOS TRES PUNTOS LIMPIOS del arco. En medio de dos tramos la pose es una MEZCLA y lo
	# que mueves sale a medias; en estos tres puntos manda una sola pose y se coloca de verdad.
	_fila_mazo2 = HBoxContainer.new()
	_fila_mazo2.add_theme_constant_override("separation", 6)
	v.add_child(_fila_mazo2)
	_fila_mazo2.add_child(_boton("GUARDIA", func(): _ir_a(0.0)))
	_fila_mazo2.add_child(_boton("VER LA CARGA", func(): _ir_a(_val("sw_carga"))))
	_fila_mazo2.add_child(_boton("VER EL GOLPE", func(): _ir_a(_val("sw_carga") + _val("sw_golpe"))))
	_fila_mazo2.add_child(_boton("VER LA PASADA", func():
		_ir_a((_val("sw_carga") + _val("sw_golpe") + 100.0) * 0.5)))
	# LOS DOS FINALES. Al aire el mazo pasa de largo; acertando se queda clavado y vuelve derecho.
	var b_fin := _boton("FINAL: AL AIRE", func(): pass)
	b_fin.pressed.connect(func():
		if avatar:
			avatar._swing_res = 1 if avatar._swing_res != 1 else 2
			b_fin.text = "FINAL: ACERTANDO" if avatar._swing_res == 1 else "FINAL: AL AIRE"
		_aplicar())
	_fila_mazo2.add_child(b_fin)

	var sep := HSeparator.new()
	v.add_child(sep)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var lista := VBoxContainer.new()
	lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lista.add_theme_constant_override("separation", 4)
	scroll.add_child(lista)

	_caja_mira = VBoxContainer.new()
	_caja_mira.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lista.add_child(_caja_mira)
	_caja_clip = VBoxContainer.new()
	_caja_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lista.add_child(_caja_clip)
	_caja_mazo = VBoxContainer.new()
	_caja_mazo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lista.add_child(_caja_mazo)
	_titulo_grupo(_caja_mira, "ARMA AL APUNTAR (donde se apoya la mira)")
	_barra(_caja_mira, "ojo_x", "Ojo · izquierda-derecha", AvatarScript.aim_ojo.x, -8.0, 8.0)
	_barra(_caja_mira, "ojo_y", "Ojo · abajo-arriba", AvatarScript.aim_ojo.y, -6.0, 12.0)
	_barra(_caja_mira, "ojo_z", "Ojo · dentro-fuera", AvatarScript.aim_ojo.z, -12.0, 4.0)
	_barra(_caja_mira, "delante", "Mira por delante del ojo (m)", AvatarScript.aim_delante, 0.0, 0.8)
	_barra(_caja_mira, "giro_x", "Giro · cabeceo", AvatarScript.aim_giro.x, -90.0, 90.0)
	_barra(_caja_mira, "giro_y", "Giro · guinada", AvatarScript.aim_giro.y, -90.0, 90.0)
	_barra(_caja_mira, "giro_z", "Giro · alabeo", AvatarScript.aim_giro.z, -90.0, 90.0)
	# EL OJO, aparte. Se coloca con REPRODUCIR OJO en marcha y la cara de cerca.
	_titulo_grupo(_caja_mira, "OJO (el gesto de entornar)")
	_barra(_caja_mira, "parp_x", "Ojo cerrado · lados", AvatarScript.parpado_off.x, -10.0, 10.0)
	_barra(_caja_mira, "parp_y", "Ojo cerrado · arriba-abajo", AvatarScript.parpado_off.y, -12.0, 12.0)
	_barra(_caja_mira, "parp_z", "Ojo cerrado · delante-atras", AvatarScript.parpado_off.z, -8.0, 8.0)
	_barra(_caja_mira, "parp_rec", "Cuanto se cierra el ojo", AvatarScript.parpado_cierre, 0.0, 1.0)
	# POSE DEL ARMA EN EL CLIP QUE SE VE. Corriendo, el arma se tumba contra el cuerpo; andando va
	# encarada. Son poses distintas y aqui se editan las dos, cada una con su clip delante.
	_titulo_grupo(_caja_clip, "ARMA EN ESTE CLIP")
	_barra(_caja_clip, "pos_x", "Arma · lados", 0.0, -1.0, 1.0)
	_barra(_caja_clip, "pos_y", "Arma · arriba-abajo", 0.0, -1.2, 1.0)
	_barra(_caja_clip, "pos_z", "Arma · delante-atras", 0.0, -1.0, 1.0)
	_barra(_caja_clip, "rot_x", "Arma · cabeceo", 0.0, -180.0, 180.0)
	_barra(_caja_clip, "rot_y", "Arma · guinada", 0.0, -180.0, 180.0)
	_barra(_caja_clip, "rot_z", "Arma · alabeo", 0.0, -180.0, 180.0)
	# EL MAZAZO. Lo primero es la barra de MOMENTO: congela el arco donde la dejes y a partir de ahi
	# las poses se colocan mirando el fotograma parado, que es la unica forma de acertar.
	_titulo_grupo(_caja_mazo, "MAZAZO · momento del arco")
	_barra(_caja_mazo, "sw_k", "Momento del golpe (%)", 0.0, 0.0, 100.0, 1.0)
	# QUE POSE MANDA AQUI. Sin esto uno se pone en mitad del arco, donde la pose es media carga y
	# medio golpe, mueve las barras y parece que el editor no responde: lo que hace es diluirse.
	_aviso_k = Label.new()
	_aviso_k.add_theme_font_size_override("font_size", 12)
	_aviso_k.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caja_mazo.add_child(_aviso_k)
	# LA GUARDIA: como lleva el mazo en la mano. No es parte del mazazo, pero es la pose que se ve
	# casi todo el rato y es la que hay que tocar para inclinarlo (hierro arriba, mango abajo).
	# Ademas es la base sobre la que se mezclan las otras dos, asi que moverla mueve el gesto entero.
	_titulo_grupo(_caja_mazo, "0 · GUARDIA (como lo lleva en la mano)")
	_barra(_caja_mazo, "sg_x", "Mazo · lados", 0.0, -1.0, 1.0, 0.01)
	_barra(_caja_mazo, "sg_y", "Mazo · arriba-abajo", 0.0, -1.2, 1.0, 0.01)
	_barra(_caja_mazo, "sg_z", "Mazo · delante-atras", 0.0, -1.0, 1.0, 0.01)
	_barra(_caja_mazo, "sg_rx", "Mazo · cabeceo (hierro arriba / abajo)", 0.0, -180.0, 180.0, 0.1)
	_barra(_caja_mazo, "sg_ry", "Mazo · guinada (cruzarlo al cuerpo)", 0.0, -180.0, 180.0, 0.1)
	_barra(_caja_mazo, "sg_rz", "Mazo · alabeo", 0.0, -180.0, 180.0, 0.1)
	_titulo_grupo(_caja_mazo, "1 · CARGA (el mazo arriba, sobre el hombro)")
	_barra(_caja_mazo, "su_x", "Mazo · lados", 0.0, -1.0, 1.0, 0.01)
	_barra(_caja_mazo, "su_y", "Mazo · arriba-abajo", 0.0, -1.2, 1.0, 0.01)
	_barra(_caja_mazo, "su_z", "Mazo · delante-atras", 0.0, -1.0, 1.0, 0.01)
	_barra(_caja_mazo, "su_rx", "Mazo · cabeceo", 0.0, -180.0, 180.0, 0.1)
	_barra(_caja_mazo, "su_ry", "Mazo · guinada", 0.0, -180.0, 180.0, 0.1)
	_barra(_caja_mazo, "su_rz", "Mazo · alabeo", 0.0, -180.0, 180.0, 0.1)
	_titulo_grupo(_caja_mazo, "2 · GOLPE (donde revienta el muro)")
	_barra(_caja_mazo, "sh_x", "Mazo · lados", 0.0, -1.0, 1.0, 0.01)
	_barra(_caja_mazo, "sh_y", "Mazo · arriba-abajo", 0.0, -1.2, 1.0, 0.01)
	_barra(_caja_mazo, "sh_z", "Mazo · delante-atras", 0.0, -1.0, 1.0, 0.01)
	_barra(_caja_mazo, "sh_rx", "Mazo · cabeceo", 0.0, -180.0, 180.0, 0.1)
	_barra(_caja_mazo, "sh_ry", "Mazo · guinada", 0.0, -180.0, 180.0, 0.1)
	_barra(_caja_mazo, "sh_rz", "Mazo · alabeo", 0.0, -180.0, 180.0, 0.1)
	# LOS TIEMPOS. Son los que dan el peso: una carga lenta y un golpe seco se sienten como un mazo;
	# los dos tramos iguales se sienten como saludar con la mano.
	# LA PASADA DE LARGO: donde acaba el mazo cuando el golpe se va al aire y el envion se lo lleva.
	_titulo_grupo(_caja_mazo, "3 · PASADA DE LARGO (golpe al aire)")
	_barra(_caja_mazo, "sp_x", "Mazo · lados", 0.0, -1.0, 1.0, 0.01)
	_barra(_caja_mazo, "sp_y", "Mazo · arriba-abajo", 0.0, -1.2, 1.0, 0.01)
	_barra(_caja_mazo, "sp_z", "Mazo · delante-atras", 0.0, -1.0, 1.0, 0.01)
	_barra(_caja_mazo, "sp_rx", "Mazo · cabeceo", 0.0, -180.0, 180.0, 0.1)
	_barra(_caja_mazo, "sp_ry", "Mazo · guinada", 0.0, -180.0, 180.0, 0.1)
	_barra(_caja_mazo, "sp_rz", "Mazo · alabeo", 0.0, -180.0, 180.0, 0.1)
	_titulo_grupo(_caja_mazo, "4 · TIEMPOS")
	_barra(_caja_mazo, "sw_dur", "Dura el arco entero (s)", AvatarScript.swing_dur_s, 0.15, 1.20, 0.01)
	_barra(_caja_mazo, "sw_hit", "Revienta el muro en el segundo", AvatarScript.swing_hit_at, 0.02, 1.20, 0.01)
	_barra(_caja_mazo, "sw_carga", "Acaba la carga al (%)", AvatarScript.swing_carga * 100.0, 5.0, 80.0, 1.0)
	_barra(_caja_mazo, "sw_golpe", "Dura el golpe (%)", AvatarScript.swing_golpe * 100.0, 5.0, 80.0, 1.0)
	# EL AVISO IMPORTANTE: el segundo en que se rompen los voxels y el punto del arco en que el mazo
	# llega abajo son dos numeros distintos, y si no coinciden el muro revienta antes de que el
	# hierro lo toque. Aqui se ven los dos juntos.
	_aviso_mazo = Label.new()
	_aviso_mazo.add_theme_font_size_override("font_size", 12)
	_aviso_mazo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caja_mazo.add_child(_aviso_mazo)
	var b_cuadrar := _boton("CUADRAR EL IMPACTO CON EL GOLPE", func():
		(_barras["sw_hit"][0] as HSlider).value = _val("sw_dur") * (_val("sw_carga") + _val("sw_golpe")) / 100.0)
	_caja_mazo.add_child(b_cuadrar)
	_barra(_caja_mazo, "sw_lento", "Al aire, la vuelta va a esta velocidad", AvatarScript.swing_pasada_lento, 0.2, 1.0, 0.05)
	_barra(_caja_mazo, "sw_frena", "Acertando, se queda clavado (s)", AvatarScript.swing_frenazo, 0.0, 0.4, 0.01)
	_titulo_grupo(_caja_mazo, "5 · CURVAS (menos de 1 = arranca rapido y frena)")
	_barra(_caja_mazo, "sw_cc", "Curva de la carga", AvatarScript.swing_curva_carga, 0.2, 3.0, 0.05)
	_barra(_caja_mazo, "sw_cg", "Curva del golpe", AvatarScript.swing_curva_golpe, 0.2, 3.0, 0.05)
	_barra(_caja_mazo, "sw_cv", "Curva de la vuelta", AvatarScript.swing_curva_vuelta, 0.2, 3.0, 0.05)
	_cargar_mazo()
	_montando = false
	_cargar_pose()


## Cabecera de bloque: separa a la vista lo del arma de lo del ojo.
func _titulo_grupo(padre: Node, texto: String) -> void:
	var sep := HSeparator.new()
	padre.add_child(sep)
	var l := Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", GOLD)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	padre.add_child(l)


func _barra(padre: Node, id: String, texto: String, valor: float, mn: float, mx: float, paso := 0.0) -> void:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 13)
	padre.add_child(l)
	var h := HSlider.new()
	h.min_value = mn
	h.max_value = mx
	h.step = paso if paso > 0.0 else (0.01 if id.begins_with("pos_") else 0.05)
	h.value = valor
	h.custom_minimum_size = Vector2(380, 20)
	padre.add_child(h)
	_barras[id] = [h, l, texto]
	h.value_changed.connect(func(_x): _aplicar())
	_texto_barra(id)


func _texto_barra(id: String) -> void:
	var e: Array = _barras[id]
	(e[1] as Label).text = "%s:  %.2f" % [String(e[2]), (e[0] as HSlider).value]


func _val(id: String) -> float:
	return (_barras[id][0] as HSlider).value


## Los valores de las barras van directos al animador: el soldado se recoloca en el mismo frame.
func _aplicar() -> void:
	if _montando:
		return
	AvatarScript.aim_ojo = Vector3(_val("ojo_x"), _val("ojo_y"), _val("ojo_z"))
	AvatarScript.aim_delante = _val("delante")
	AvatarScript.aim_giro = Vector3(_val("giro_x"), _val("giro_y"), _val("giro_z"))
	AvatarScript.parpado_off = Vector3(_val("parp_x"), _val("parp_y"), _val("parp_z"))
	AvatarScript.parpado_cierre = _val("parp_rec")
	AvatarScript.pose_edit["rifle/" + _pose_nombre] = [
		Vector3(_val("pos_x"), _val("pos_y"), _val("pos_z")),
		Vector3(_val("rot_x"), _val("rot_y"), _val("rot_z"))]
	if _barras.has("sw_k"):
		_aplicar_mazo()
	for id in _barras.keys():
		_texto_barra(id)


## LO DEL MAZO va a las mismas variables que usa el juego, asi que lo que se ve en el editor es
## exactamente lo que se vera jugando (y en primera persona, que comparte tiempos).
func _aplicar_mazo() -> void:
	AvatarScript.pose_edit["sledge/action"] = [
		Vector3(_val("sg_x"), _val("sg_y"), _val("sg_z")),
		Vector3(_val("sg_rx"), _val("sg_ry"), _val("sg_rz"))]
	AvatarScript.pose_edit["sledge/swing_up"] = [
		Vector3(_val("su_x"), _val("su_y"), _val("su_z")),
		Vector3(_val("su_rx"), _val("su_ry"), _val("su_rz"))]
	AvatarScript.pose_edit["sledge/swing_hit"] = [
		Vector3(_val("sh_x"), _val("sh_y"), _val("sh_z")),
		Vector3(_val("sh_rx"), _val("sh_ry"), _val("sh_rz"))]
	AvatarScript.pose_edit["sledge/swing_past"] = [
		Vector3(_val("sp_x"), _val("sp_y"), _val("sp_z")),
		Vector3(_val("sp_rx"), _val("sp_ry"), _val("sp_rz"))]
	AvatarScript.swing_pasada_lento = _val("sw_lento")
	AvatarScript.swing_frenazo = _val("sw_frena")
	AvatarScript.swing_dur_s = _val("sw_dur")
	AvatarScript.swing_hit_at = _val("sw_hit")
	AvatarScript.swing_carga = _val("sw_carga") / 100.0
	AvatarScript.swing_golpe = _val("sw_golpe") / 100.0
	AvatarScript.swing_curva_carga = _val("sw_cc")
	AvatarScript.swing_curva_golpe = _val("sw_cg")
	AvatarScript.swing_curva_vuelta = _val("sw_cv")
	# congelado = el arco parado donde diga la barra; suelto = -1 y el gesto corre con su reloj
	AvatarScript.swing_scrub = (_val("sw_k") / 100.0) if (_arma == "sledge" and _congelado) else -1.0
	if _aviso_k:
		var k: float = _val("sw_k") / 100.0
		var c0: float = _val("sw_carga") / 100.0
		var g0: float = _val("sw_golpe") / 100.0
		var carga: float = pow(clampf(k / maxf(c0, 0.01), 0.0, 1.0), _val("sw_cc"))
		var golpe: float = pow(clampf((k - c0) / maxf(g0, 0.01), 0.0, 1.0), _val("sw_cg"))
		var vuelta: float = pow(clampf((k - c0 - g0) / maxf(1.0 - c0 - g0, 0.01), 0.0, 1.0), _val("sw_cv"))
		var w_up: float = clampf(carga - golpe, 0.0, 1.0)
		var w_hit: float = clampf(golpe - vuelta, 0.0, 1.0)
		var quien := "manda la GUARDIA entera: mueve el bloque 0"
		if w_up >= 0.98:
			quien = "manda la CARGA entera: mueve el bloque 1"
		elif w_hit >= 0.98:
			quien = "manda el GOLPE entero: mueve el bloque 2"
		elif w_up > 0.05 or w_hit > 0.05:
			quien = "MEZCLA: carga %.0f%% + golpe %.0f%% (lo que muevas sale a medias)" % [w_up * 100.0, w_hit * 100.0]
		_aviso_k.text = quien
		var limpio: bool = w_up >= 0.98 or w_hit >= 0.98 or (w_up < 0.02 and w_hit < 0.02)
		_aviso_k.add_theme_color_override("font_color",
			Color(0.6, 0.85, 0.6) if limpio else Color(0.85, 0.8, 0.5))
	if _aviso_mazo:
		var pct: float = 100.0 * _val("sw_hit") / maxf(_val("sw_dur"), 0.01)
		var abajo: float = _val("sw_carga") + _val("sw_golpe")
		var desfase: float = absf(pct - abajo)
		_aviso_mazo.text = "El muro revienta al %.0f%% del arco y el mazo llega abajo al %.0f%%.  %s" % [
			pct, abajo,
			"Cuadrado." if desfase < 6.0 else "DESCUADRADO: se rompe antes de tocar." if pct < abajo else "DESCUADRADO: se rompe despues de tocar."]
		_aviso_mazo.add_theme_color_override("font_color",
			Color(0.6, 0.85, 0.6) if desfase < 6.0 else Color(1.0, 0.55, 0.4))


## Trae al panel las poses del mazazo tal y como estan hoy en el codigo.
func _cargar_mazo() -> void:
	var poses: Dictionary = AvatarScript.HOLD_POSES.get("sledge", {})
	for par in [["sg", "action"], ["su", "swing_up"], ["sh", "swing_hit"], ["sp", "swing_past"]]:
		var p: Array = poses.get(String(par[1]), [Vector3.ZERO, Vector3.ZERO])
		var pos: Vector3 = p[0]
		var rot: Vector3 = p[1]
		for q in [["_x", pos.x], ["_y", pos.y], ["_z", pos.z],
				["_rx", rot.x], ["_ry", rot.y], ["_rz", rot.z]]:
			(_barras[String(par[0]) + String(q[0])][0] as HSlider).value = q[1]
	# tocar la barra del MOMENTO corta el bucle y congela el arco ahi: es lo que uno espera al
	# arrastrarla, y si no el gesto seguia corriendo por debajo peleandose con la barra
	(_barras["sw_k"][0] as HSlider).value_changed.connect(func(_x):
		_congelado = true
		_bucle = false)


## Cambia entre fusil y mazo. Con el mazo se pone al personaje QUIETO: el mazazo se juzga parado,
## con el clip de correr por debajo no se distingue que mueve el golpe y que mueve la carrera.
func _cambiar_arma() -> void:
	_arma = "sledge" if _arma == "rifle" else "rifle"
	if avatar:
		if _arma == "sledge":
			avatar.aiming = false
			avatar.equip_weapon("sledge")
			_clip = 2
			_aplicar_clip()
		else:
			avatar.equip_rifle()
	_congelado = true
	_aplicar()
	_refrescar_titulo()


## Enciende o apaga el bucle. Encendido, el mazazo se repite solo a la velocidad elegida y las
## barras siguen funcionando: ves el cambio en la siguiente pasada sin tener que parar.
func _bucle_mazo(encender: bool) -> void:
	if avatar == null:
		return
	if encender and _arma != "sledge":
		_cambiar_arma()
	_bucle = encender
	_bucle_t = 0.0
	_congelado = not encender
	_aplicar()
	_refrescar_titulo()


## Congela el arco en un punto concreto (en %). Corta el bucle: son dos formas de mirar el gesto.
func _ir_a(pct: float) -> void:
	_bucle = false
	_congelado = true
	(_barras["sw_k"][0] as HSlider).value = clampf(pct, 0.0, 100.0)
	_aplicar()
	_refrescar_titulo()


func _process(dt: float) -> void:
	if not _bucle or avatar == null:
		return
	_bucle_t -= dt
	if _bucle_t <= 0.0:
		# el arco entero mas un respiro de guardia, para que se distinga donde acaba y donde empieza
		var largo: float = _val("sw_dur") / _vel
		_bucle_t = largo + 0.35
		avatar.play_swing(largo)


## Cambia de clip y trae a las barras la pose que le corresponde.
func _siguiente_clip() -> void:
	_clip = (_clip + 1) % CLIPS.size()
	_aplicar_clip()


func _aplicar_clip() -> void:
	var c: Array = CLIPS[_clip]
	if avatar:
		avatar.play(String(c[0]))
		# `move_amount` es lo que decide cuanto se baja el arma: sin el, corriendo se seguiria
		# viendo la pose de quieto y las barras de la pose de correr no moverian nada
		avatar.move_amount = float(c[3])
		# y el arma solo baja pasado medio segundo sin disparar: se adelanta ese reloj para que la
		# pose de correr se vea YA, sin esperar
		avatar._since_fire = 3.0
	_pose_nombre = String(c[1])
	_cargar_pose()
	_refrescar_titulo()


## AVISO EN PANTALLA. Apuntando, el arma se coloca resolviendo la linea del ojo y ese calculo manda
## sobre la pose del clip: las barras de "ARMA EN ESTE CLIP" no mueven nada. Sin decirlo, uno mueve
## barras que no hacen efecto y piensa que el editor esta roto.
func _refrescar_titulo() -> void:
	if titulo == null:
		return
	var c: Array = CLIPS[_clip]
	var apunta: bool = avatar != null and avatar.aiming
	var mazo: bool = _arma == "sledge"
	if mazo:
		titulo.text = "MAZO · en bucle (x%s)" % ("1" if _vel == 1.0 else str(_vel)) if _bucle else "MAZO · arco congelado al %.0f%%" % _val("sw_k")
	else:
		titulo.text = "POSES · %s%s" % [String(c[2]), "  ·  APUNTANDO" if apunta else ""]
	titulo.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35) if apunta and not mazo else GOLD)
	# solo se ve lo que de verdad manda ahora mismo
	if _caja_mira:
		_caja_mira.visible = apunta and not mazo
	if _caja_clip:
		_caja_clip.visible = not apunta and not mazo
	if _caja_mazo:
		_caja_mazo.visible = mazo
	if _fila_mazo:
		_fila_mazo.visible = mazo
	if _fila_mazo2:
		_fila_mazo2.visible = mazo


## Lee del catalogo la pose del clip actual y la pone en las barras.
func _cargar_pose() -> void:
	if avatar == null or not _barras.has("pos_x"):
		return
	var poses: Dictionary = AvatarScript.HOLD_POSES.get("rifle", {})
	var p: Array = AvatarScript.pose_edit.get("rifle/" + _pose_nombre, poses.get(_pose_nombre, [Vector3.ZERO, Vector3.ZERO]))
	var pos: Vector3 = p[0]
	var rot: Vector3 = p[1]
	for par in [["pos_x", pos.x], ["pos_y", pos.y], ["pos_z", pos.z],
			["rot_x", rot.x], ["rot_y", rot.y], ["rot_z", rot.z]]:
		(_barras[par[0]][0] as HSlider).value = par[1]
	_aplicar()


func _por_defecto() -> void:
	var d := {"ojo_x": 2.70, "ojo_y": -0.25, "ojo_z": -4.50, "delante": 0.450,
		"giro_x": 0.0, "giro_y": 0.0, "giro_z": 0.0,
		"parp_x": 0.0, "parp_y": 0.0, "parp_z": 0.0, "parp_rec": 1.0}
	for id in d.keys():
		(_barras[id][0] as HSlider).value = d[id]
	_aplicar()


## Baja el ojo otra vez desde arriba, para ver el gesto entero sin salir del editor.
func _repetir_ojo() -> void:
	if avatar == null:
		return
	# dos pasadas con pausas largas: el gesto dura 0,3 s y de una sola vez no da tiempo a verlo
	for i in 2:
		avatar.aiming = false
		titulo.text = "PUNTERIA · ABRIENDO el ojo"
		await get_tree().create_timer(1.1).timeout
		avatar.aiming = true
		titulo.text = "PUNTERIA · CERRANDO el ojo"
		await get_tree().create_timer(1.1).timeout
	titulo.text = "PUNTERIA"


## Copia SOLO lo que se esta editando: apuntando, lo del arma encarada y el ojo; si no, la pose del
## clip que tengas delante. Antes salia todo junto y habia que separar a mano que era de cada cosa.
func _copiar() -> void:
	var txt := ""
	if _arma == "sledge":
		txt = ('"action":    [Vector3(%.2f, %.2f, %.2f), Vector3(%.1f, %.1f, %.1f)],
'
			+ '"swing_up":  [Vector3(%.2f, %.2f, %.2f), Vector3(%.1f, %.1f, %.1f)],
'
			+ '"swing_hit": [Vector3(%.2f, %.2f, %.2f), Vector3(%.1f, %.1f, %.1f)],
'
			+ '"swing_past":[Vector3(%.2f, %.2f, %.2f), Vector3(%.1f, %.1f, %.1f)],
'
			+ 'dura %.2f s · impacto a los %.2f s
'
			+ 'carga %.0f%% · golpe %.0f%% · curvas %.2f / %.2f / %.2f
'
			+ 'al aire la vuelta a %.2f · clavado %.2f s') % [
			_val("sg_x"), _val("sg_y"), _val("sg_z"), _val("sg_rx"), _val("sg_ry"), _val("sg_rz"),
			_val("su_x"), _val("su_y"), _val("su_z"), _val("su_rx"), _val("su_ry"), _val("su_rz"),
			_val("sh_x"), _val("sh_y"), _val("sh_z"), _val("sh_rx"), _val("sh_ry"), _val("sh_rz"),
			_val("sp_x"), _val("sp_y"), _val("sp_z"), _val("sp_rx"), _val("sp_ry"), _val("sp_rz"),
			_val("sw_dur"), _val("sw_hit"),
			_val("sw_carga"), _val("sw_golpe"), _val("sw_cc"), _val("sw_cg"), _val("sw_cv"),
			_val("sw_lento"), _val("sw_frena")]
		DisplayServer.clipboard_set(txt)
		titulo.text = "MAZO · copiado al portapapeles"
		print("[mazo] copiado:
" + txt)
		return
	if avatar != null and avatar.aiming:
		txt = ("aim_ojo = Vector3(%.2f, %.2f, %.2f)
aim_delante = %.3f
"
			+ "aim_giro = Vector3(%.1f, %.1f, %.1f)
"
			+ "parpado_off = Vector3(%.2f, %.2f, %.2f)
parpado_cierre = %.2f") % [
			_val("ojo_x"), _val("ojo_y"), _val("ojo_z"), _val("delante"),
			_val("giro_x"), _val("giro_y"), _val("giro_z"),
			_val("parp_x"), _val("parp_y"), _val("parp_z"), _val("parp_rec")]
	else:
		txt = "%s: pos Vector3(%.3f, %.3f, %.3f)  rot Vector3(%.1f, %.1f, %.1f)" % [
			_pose_nombre, _val("pos_x"), _val("pos_y"), _val("pos_z"),
			_val("rot_x"), _val("rot_y"), _val("rot_z")]
	DisplayServer.clipboard_set(txt)
	titulo.text = "PUNTERIA · copiado al portapapeles"
	print("[mira] copiado:
" + txt)


func _boton(texto: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = texto
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 34)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 14)
	for st in [["normal", Color(0.14, 0.17, 0.30)], ["hover", Color(0.20, 0.24, 0.40)], ["pressed", Color(0.10, 0.12, 0.22)]]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = st[1]
		sb.set_corner_radius_all(8)
		sb.set_content_margin_all(8)
		b.add_theme_stylebox_override(st[0], sb)
	b.pressed.connect(cb)
	return b
