extends Control
## LA PANTALLA DE "CONECTANDO" (2026-09-28, pedido con captura): al pulsar JUGAR, mientras se busca partida.
##
## Encima del lobby, que se sigue viendo desenfocado y oscurecido:
##   - un RESPLANDOR azul que vira a violeta hacia fuera, con ondas concentricas que salen del centro;
##   - dos ARCOS DORADOS finos, dos TRAZOS BLANCOS gruesos y dos arcos blancos tenues, girando a distinto
##     paso y en sentidos contrarios, con su halo (no son lineas planas);
##   - "POR FAVOR, ESPERA" pequeño y el estado grande ("BUSCANDO PARTIDA", "CONECTANDO AL SERVIDOR"...), en
##     cursiva gruesa, y debajo del anillo el detalle en pequeño.
## El lobby (lobby.gd, _am_montar_panel) pone los botones en `botones` y cambia los textos con `decir`.
## Todo va medido sobre 1080 de alto y se escala con la ventana.

const ORO := Color(1.0, 0.69, 0.13)
const BLANCO := Color(1, 1, 1)

var botones: HBoxContainer
var _pequeno: Label
var _grande: Label
var _detalle: Label
var _arcos: Control
var _t := 0.0
var _k := 1.0
var _fuente_fina: SystemFont
var _fuente_gorda: SystemFont

const SOMBRA_FONDO := """
shader_type canvas_item;
// el lobby de detras, desenfocado y oscurecido hacia azul
uniform sampler2D pantalla : hint_screen_texture, filter_linear_mipmap;
uniform float entra = 1.0;
void fragment() {
	vec3 c = textureLod(pantalla, SCREEN_UV, 3.0 * entra).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 tinte = mix(c, vec3(l) * vec3(0.5, 0.55, 1.0), 0.5) * 0.72 + vec3(0.02, 0.02, 0.07);
	COLOR = vec4(mix(c, tinte, entra), 1.0);
}
"""

const SOMBRA_BRILLO := """
shader_type canvas_item;
// el resplandor: nucleo azul claro, azul, violeta hacia fuera y ondas que salen del centro
uniform vec2 centro = vec2(960.0, 540.0);
uniform float radio = 460.0;
uniform float entra = 1.0;
uniform vec2 tam = vec2(1920.0, 1080.0);
void fragment() {
	vec2 p = UV * tam;
	float d = length(p - centro) / (radio * mix(0.75, 1.0, entra));
	float ondas = 0.5 + 0.5 * sin(d * 30.0 - TIME * 2.6);
	ondas = mix(1.0, 0.82 + 0.18 * ondas, smoothstep(0.08, 0.3, d) * smoothstep(1.25, 0.6, d));
	vec3 nucleo = vec3(0.42, 0.62, 1.0);
	vec3 azul = vec3(0.17, 0.36, 1.0);
	vec3 violeta = vec3(0.5, 0.18, 0.95);
	vec3 col = mix(nucleo, azul, smoothstep(0.0, 0.45, d));
	col = mix(col, violeta, smoothstep(0.4, 0.95, d));
	float a = smoothstep(1.35, 0.3, d);
	a = a * a * (3.0 - 2.0 * a);
	// un respiro lento de todo el halo
	float pulso = 0.93 + 0.07 * sin(TIME * 1.7);
	COLOR = vec4(col * ondas * pulso, clamp(a * 0.92, 0.0, 1.0) * entra);
}
"""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_fuente_fina = SystemFont.new()
	_fuente_fina.font_names = PackedStringArray(["Segoe UI", "Roboto", "Arial", "sans-serif"])
	_fuente_fina.font_weight = 700
	_fuente_fina.font_italic = true
	_fuente_gorda = SystemFont.new()
	_fuente_gorda.font_names = PackedStringArray(["Segoe UI", "Roboto", "Arial", "sans-serif"])
	_fuente_gorda.font_weight = 900
	_fuente_gorda.font_italic = true

	var fondo := ColorRect.new()
	fondo.name = "Fondo"
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mf := ShaderMaterial.new()
	var sf := Shader.new()
	sf.code = SOMBRA_FONDO
	mf.shader = sf
	fondo.material = mf
	add_child(fondo)

	var brillo := ColorRect.new()
	brillo.name = "Brillo"
	brillo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	brillo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mb := ShaderMaterial.new()
	var sb := Shader.new()
	sb.code = SOMBRA_BRILLO
	mb.shader = sb
	brillo.material = mb
	add_child(brillo)

	_arcos = Control.new()
	_arcos.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_arcos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arcos.draw.connect(_dibujar_arcos)
	add_child(_arcos)

	_pequeno = _letrero("POR FAVOR, ESPERA", _fuente_fina)
	_grande = _letrero("BUSCANDO PARTIDA", _fuente_gorda)
	_detalle = _letrero("", _fuente_fina)
	_detalle.add_theme_color_override("font_color", Color(0.86, 0.89, 1.0, 0.85))
	_detalle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	botones = HBoxContainer.new()
	botones.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(botones)

	get_viewport().size_changed.connect(_colocar)
	_colocar()
	# ENTRADA: el fondo se desenfoca, el halo crece y los anillos se abren
	var tw := create_tween().set_parallel(true)
	tw.tween_method(_entrar, 0.0, 1.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _letrero(texto: String, fuente: Font) -> Label:
	var l := Label.new()
	l.text = texto
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", fuente)
	l.add_theme_color_override("font_color", BLANCO)
	l.add_theme_color_override("font_shadow_color", Color(0.06, 0.04, 0.3, 0.38))
	add_child(l)
	return l


var _entra := 0.0

func _entrar(v: float) -> void:
	_entra = v
	for n in ["Fondo", "Brillo"]:
		var r := get_node_or_null(n) as ColorRect
		if r:
			(r.material as ShaderMaterial).set_shader_parameter("entra", v)
	for l in [_pequeno, _grande, _detalle]:
		l.modulate.a = v
	botones.modulate.a = v
	_arcos.queue_redraw()


## Cambia el estado. El grande hace un pequeño golpe al cambiar para que se note.
func decir(titulo: String, detalle: String) -> void:
	if is_instance_valid(_grande) and _grande.text != titulo:
		_grande.text = titulo
		_colocar()
		_grande.pivot_offset = _grande.size * 0.5
		_grande.scale = Vector2(1.08, 1.08)
		create_tween().tween_property(_grande, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if is_instance_valid(_detalle):
		_detalle.text = detalle


func _colocar() -> void:
	var vp := get_viewport_rect().size
	_k = vp.y / 1080.0
	var c := vp * 0.5
	var r := 210.0 * _k
	var brillo := get_node_or_null("Brillo") as ColorRect
	if brillo:
		var m := brillo.material as ShaderMaterial
		m.set_shader_parameter("centro", c)
		m.set_shader_parameter("radio", 560.0 * _k)
		m.set_shader_parameter("tam", vp)
	# los textos: que quepan (el grande se encoge si el estado es largo)
	var ancho_max := minf(vp.x - 60.0 * _k, 1500.0 * _k)
	_ajustar(_pequeno, _fuente_fina, 28.0 * _k, ancho_max, 2)
	_ajustar(_grande, _fuente_gorda, 52.0 * _k, ancho_max, 2)
	_pequeno.size = Vector2(ancho_max, 44.0 * _k)
	_pequeno.position = Vector2(c.x - ancho_max * 0.5, c.y - 48.0 * _k)
	_grande.size = Vector2(ancho_max, 72.0 * _k)
	_grande.position = Vector2(c.x - ancho_max * 0.5, c.y - 6.0 * _k)
	_detalle.add_theme_font_size_override("font_size", int(round(20.0 * _k)))
	_detalle.size = Vector2(minf(ancho_max, 760.0 * _k), 60.0 * _k)
	_detalle.position = Vector2(c.x - _detalle.size.x * 0.5, c.y + r + 34.0 * _k)
	botones.add_theme_constant_override("separation", int(18.0 * _k))
	botones.size = Vector2(vp.x, 56.0 * _k)
	botones.position = Vector2(0.0, vp.y - 120.0 * _k)
	_arcos.queue_redraw()


func _ajustar(l: Label, f: Font, tam: float, ancho_max: float, sombra: float) -> void:
	var t := int(round(tam))
	while t > 12 and f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, t).x > ancho_max:
		t -= 2
	l.add_theme_font_size_override("font_size", t)
	l.add_theme_constant_override("shadow_offset_x", int(round(sombra * _k)))
	l.add_theme_constant_override("shadow_offset_y", int(round(sombra * _k)))
	l.add_theme_constant_override("shadow_outline_size", int(round(14.0 * _k)))


func _process(dt: float) -> void:
	_t += dt
	_arcos.queue_redraw()


## Un arco con su halo: primero dos pasadas anchas y tenues del mismo color, luego el trazo.
func _arco(c: Vector2, r: float, desde: float, largo: float, ancho: float, col: Color) -> void:
	var a0 := deg_to_rad(desde)
	var a1 := deg_to_rad(desde + largo)
	var n := maxi(12, int(largo / 3.0))
	_arcos.draw_arc(c, r, a0, a1, n, Color(col, col.a * 0.10), ancho * 5.0, true)
	_arcos.draw_arc(c, r, a0, a1, n, Color(col, col.a * 0.22), ancho * 2.4, true)
	_arcos.draw_arc(c, r, a0, a1, n, col, ancho, true)


func _dibujar_arcos() -> void:
	var vp := get_viewport_rect().size
	var c := vp * 0.5
	# se abren al entrar: de 0,8 a 1 con un pelin de rebote
	var abre := 0.8 + 0.2 * ease(_entra, 0.4)
	var r := 210.0 * _k * abre
	var a := _entra
	# dorados: dos arcos largos y finos, giran despacio
	var g1 := -100.0 + _t * 28.0
	for i in 2:
		_arco(c, r, g1 + 180.0 * i, 112.0, 4.2 * _k, Color(ORO, a))
	# blancos gruesos y cortos, por dentro, al reves y mas deprisa
	var g2 := -150.0 - _t * 52.0
	for i in 2:
		_arco(c, r * 0.9, g2 + 180.0 * i, 28.0, 8.0 * _k, Color(BLANCO, a))
	# blancos tenues, mas adentro
	var g3 := -140.0 + _t * 40.0
	for i in 2:
		_arco(c, r * 0.8, g3 + 180.0 * i, 52.0, 2.6 * _k, Color(BLANCO, 0.4 * a))
