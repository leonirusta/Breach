class_name Girador
extends Control
## "Cargando": un arco amarillo que gira, centrado en su sitio.

var _t := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(0, 90)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(dt: float) -> void:
	_t += dt
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	draw_arc(c, 16, 0, TAU, 40, Color(1, 1, 1, 0.06), 4, true)
	var a := _t * 6.0
	draw_arc(c, 16, a, a + PI * (0.6 + 0.35 * sin(_t * 3.0)), 24, Tema.ACENTO, 4, true)
