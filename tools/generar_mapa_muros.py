#!/usr/bin/env python3
"""MAPA DE PRUEBA "muros": la subida de Blender (trepar_real_anim.py) contra muros de verdad.

Una calle por altura de muro (1,30 · 1,55 · 1,75 · 2,30 m), todos a lo largo de X con la cara en x=8,
para que `--treparfoto` ponga al jugador delante de cada uno, le haga trepar y mida donde acaban las
manos y los pies. 1,55 es la altura a la que se animo (1,70 m para un soldado de 1,75, el del juego
mide 1,60).

No es un mapa para jugar: se genera, se prueba y se borra (no va en el APK ni en la lista de mapas).

Uso:  python tools/generar_mapa_muros.py
"""
import os
import numpy as np

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAPAS = os.path.join(RAIZ, "godot", "maps")
NOMBRE = "muros"

# se reutilizan el escritor y el troceado del mapa "pruebas" sin ejecutar su montaje
src = open(os.path.join(RAIZ, "tools", "generar_mapa_pruebas.py"), encoding="utf-8").read()
src = src[:src.index("ANCHO = NX * VOXEL")] + src[src.index("def rle_chunk"):src.index("def main():")]
g = {"__file__": os.path.join(RAIZ, "tools", "generar_mapa_pruebas.py")}
exec(compile(src, "pruebas", "exec"), g)

VOXEL, CHUNK = g["VOXEL"], g["CHUNK"]
CHUNKS = (8, 2, 6)
NX, NY, NZ = (c * CHUNK for c in CHUNKS)
g["CHUNKS"], g["NX"], g["NY"], g["NZ"] = CHUNKS, NX, NY, NZ
vol = np.zeros((NX, NY, NZ), dtype=np.uint8)
g["vol"] = vol
caja = g["caja"]
Y0 = g["Y0"]

caja(0, 0, 0, NX * VOXEL, 0.4, NZ * VOXEL, "base")
caja(0, 0.4, 0, NX * VOXEL, Y0, NZ * VOXEL, "suelo_blanco")

ALTURAS = [1.3, 1.55, 1.75, 2.3]
for i, h in enumerate(ALTURAS):
    z = 2.0 + i * 4.0
    caja(8.0, Y0, z - 1.2, 10.0, Y0 + h, z + 1.2, "gris")

sp = [(4.0, Y0 + 0.1, 2.0, 270.0)]
hi, s_hi = g["trocear"](vol, CHUNKS)
lo_vol = g["bajar_resolucion"](vol)
dims_lo = (CHUNKS[0] // 2, CHUNKS[1] // 2, CHUNKS[2] // 2)
lo, s_lo = g["trocear"](lo_vol, dims_lo)
base = os.path.join(MAPAS, NOMBRE)
g["escribir"](base + ".vxmap", VOXEL, CHUNKS, sp, hi)
g["escribir"](base + "_lo.vxmap", VOXEL * 2, dims_lo, sp, lo)
print("== %s: Y0 %.2f · muros %s en z=%s" % (NOMBRE, Y0, ALTURAS, [2.0 + i * 4.0 for i in range(len(ALTURAS))]))
