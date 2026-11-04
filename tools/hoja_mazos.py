"""Junta las fotos de los mazos del muestrario en UNA lamina, con su nombre y su lema.

    python tools/hoja_mazos.py [carpeta_de_fotos] [salida.png]

Las fotos las saca antes:
    blender -b --python tools/blender/armas/render_mazos.py -- <carpeta_de_fotos>
"""
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FOTOS = sys.argv[1] if len(sys.argv) > 1 else os.path.join(RAIZ, "docs", "mazos")
SALIDA = sys.argv[2] if len(sys.argv) > 2 else os.path.join(RAIZ, "docs", "mazos_nuevos.png")

# el catalogo se lee del propio .py del muestrario: una lista que mantener, no dos
texto = open(os.path.join(RAIZ, "tools", "blender", "armas", "mazos.py"), encoding="utf-8").read()
ENTRADAS = re.findall(
    r'\{"id": "(mazo_[a-z]+)", "nombre": "([^"]+)", "f": \w+,\s*\n\s*"lema": "([^"]+)"', texto)

COLS = 3
W, H = 430, 614          # cada foto, escalada
PIE = 84                 # el hueco del texto debajo
MARGEN = 16

filas = (len(ENTRADAS) + COLS - 1) // COLS
hoja = Image.new("RGB", (COLS * (W + MARGEN) + MARGEN, filas * (H + PIE + MARGEN) + MARGEN),
                 (13, 14, 18))
d = ImageDraw.Draw(hoja)
try:
    f_nom = ImageFont.truetype("arialbd.ttf", 27)
    f_sub = ImageFont.truetype("arial.ttf", 17)
except Exception:
    f_nom = f_sub = ImageFont.load_default()

puestos = 0
for k, (mid, nombre, lema) in enumerate(ENTRADAS):
    ruta = os.path.join(FOTOS, mid + ".png")
    if not os.path.exists(ruta):
        print("[hoja] falta %s" % ruta)
        continue
    x = MARGEN + (k % COLS) * (W + MARGEN)
    y = MARGEN + (k // COLS) * (H + PIE + MARGEN)
    im = Image.open(ruta).convert("RGB").resize((W, H), Image.LANCZOS)
    hoja.paste(im, (x, y))
    d.rectangle([x, y, x + W - 1, y + H + PIE - 1], outline=(46, 50, 60), width=2)
    d.text((x + 14, y + H + 10), nombre, font=f_nom, fill=(238, 240, 245))
    # el lema, partido a mano: no cabe de una linea
    linea, yy = "", y + H + 44
    for palabra in lema.split():
        if d.textlength(linea + " " + palabra, font=f_sub) > W - 28:
            d.text((x + 14, yy), linea, font=f_sub, fill=(150, 156, 168))
            linea, yy = palabra, yy + 21
        else:
            linea = (linea + " " + palabra).strip()
    d.text((x + 14, yy), linea, font=f_sub, fill=(150, 156, 168))
    puestos += 1

os.makedirs(os.path.dirname(SALIDA), exist_ok=True)
hoja.save(SALIDA)
print("[hoja] %d mazos -> %s" % (puestos, SALIDA))
