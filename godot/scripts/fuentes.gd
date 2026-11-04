extends RefCounted
## LAS FUENTES DE LAS PANTALLAS, COMPARTIDAS (2026-09-30, pedido: "el pase, la tienda, las tareas tardan en abrir").
## Cada pantalla creaba sus SystemFont nuevas al abrirse, y una fuente nueva no trae dibujada ninguna letra: al primer
## fotograma se rasterizaban todas las letras de todos los tamaños otra vez (el tiron de ~0,8 s al volver a abrir el pase
## o las tareas, medido con --medirpantallas). Aqui hay UNA por peso y estilo para todo el juego: las letras se dibujan una
## vez por sesion.

static var _cache: Dictionary = {}


static func de(peso: int, cursiva: bool) -> SystemFont:
	var clave := peso * 2 + (1 if cursiva else 0)
	if not _cache.has(clave):
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Segoe UI", "Roboto", "Arial", "sans-serif"])
		f.font_weight = peso
		f.font_italic = cursiva
		_cache[clave] = f
	return _cache[clave]
