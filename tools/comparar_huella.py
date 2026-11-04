#!/usr/bin/env python3
"""Compara la huella del mapa de dos maquinas (user://huella_host.txt y huella_cliente.txt).

Las escribe el banco de LAN al terminar (--lanreport): un chunk por linea con sus voxels solidos.
El porcentaje es masa en desacuerdo sobre masa total, chunk a chunk (3,2 m de lado), que es lo que
de verdad responde a "acabamos con el mismo mapa".
"""
import os

U = os.path.join(os.path.expanduser("~"), "AppData", "Roaming", "Godot", "app_userdata", "Breach")


def leer(n):
    d = {}
    ruta = os.path.join(U, n)
    if not os.path.exists(ruta):
        return d
    for l in open(ruta, encoding="utf-8").read().split("\n"):
        p = l.split()
        if len(p) == 4:
            d[(p[0], p[1], p[2])] = int(p[3])
    return d


h, c = leer("huella_host.txt"), leer("huella_cliente.txt")
if not h or not c:
    print("faltan huellas (¿corrio el banco?)")
    raise SystemExit(1)
todos = set(h) | set(c)
dif = sum(abs(h.get(k, 0) - c.get(k, 0)) for k in todos)
tot = max(1, sum(h.values()))
malos = sum(1 for k in todos if h.get(k, 0) != c.get(k, 0))
print("%d chunks · %d voxels · %d en desacuerdo (%d chunks) · COINCIDENCIA %.4f %%"
      % (len(todos), sum(h.values()), dif, malos, 100.0 * (1.0 - dif / tot)))
