"""Hoja de contacto con todas las skins: tools/hoja_skins.py -> docs/skins_armas.png

Las fotos las saca el juego (`--fotoskins`, una por skin en user://skins_fotos). Aqui solo se montan
en una parrilla con su nombre y su rareza, que es como se miran de verdad: juntas y comparandolas.
"""
import os
import re

from PIL import Image, ImageDraw, ImageFont

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FOTOS = os.path.expanduser(r"~/AppData/Roaming/Godot/app_userdata/Breach/skins_fotos")
SALIDA = os.path.join(RAIZ, "docs", "skins_armas.png")

# el orden y los datos salen del catalogo del juego, leyendo el .gd (una sola fuente de verdad)
gd = open(os.path.join(RAIZ, "godot", "scripts", "skins_armas.gd"), encoding="utf-8").read()
RAREZAS = ["COMÚN", "POCO COMÚN", "RARA", "ÉPICA", "LEGENDARIA", "MÍTICA"]
COLORES = [(184, 191, 204), (97, 209, 115), (77, 158, 255), (179, 92, 255), (255, 184, 31), (255, 77, 107)]
skins = []
for m in re.finditer(r'\{"id": "(\w+)", "nombre": "([^"]+)", "rareza": (\d+), "estilo": "(\w+)"', gd):
    skins.append({"id": m.group(1), "nombre": m.group(2), "rareza": int(m.group(3)), "estilo": m.group(4)})

COLS = 3
W, H = 560, 320
PIE = 54
try:
    f_nom = ImageFont.truetype("arialbd.ttf", 26)
    f_sub = ImageFont.truetype("arial.ttf", 19)
except Exception:
    f_nom = f_sub = ImageFont.load_default()

filas = (len(skins) + COLS - 1) // COLS
hoja = Image.new("RGB", (COLS * W, filas * (H + PIE)), (12, 13, 17))
d = ImageDraw.Draw(hoja)
for i, s in enumerate(skins):
    ruta = os.path.join(FOTOS, s["id"] + ".png")
    if not os.path.exists(ruta):
        continue
    x = (i % COLS) * W
    y = (i // COLS) * (H + PIE)
    hoja.paste(Image.open(ruta).convert("RGB"), (x, y))
    col = COLORES[s["rareza"]]
    d.rectangle([x, y + H, x + W, y + H + PIE], fill=(18, 19, 24))
    d.rectangle([x, y + H, x + 6, y + H + PIE], fill=col)          # tira del color de la rareza
    d.text((x + 18, y + H + 6), s["nombre"], font=f_nom, fill=(240, 242, 246))
    d.text((x + 18, y + H + 31), "%s · %s" % (RAREZAS[s["rareza"]], s["estilo"].upper()), font=f_sub, fill=col)
os.makedirs(os.path.dirname(SALIDA), exist_ok=True)
hoja.save(SALIDA)
print("[hoja] %s (%d skins, %dx%d)" % (SALIDA, len(skins), hoja.width, hoja.height))
