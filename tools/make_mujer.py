"""LA URBANA: una mujer con ropa de calle (2026-09-29, pedido: "ahora una mujer con otra ropa apropiada").

Mismo principio que el Civil (tools/make_civil.py): el SOLDADO DE SERIE con sus 28 huesos (animaciones, parpadeo, el
ojo que se cierra al apuntar), sin el equipo que abulta, y vestido de nuevo:
  - chaqueta VAQUERA clara, abierta, con cuello, bolsillos de pecho con solapa, costuras y los puños vueltos,
  - camiseta BLANCA debajo (se ve por la abertura y asoma por debajo de la chaqueta),
  - pantalon NEGRO ajustado y BOTINES marrones con la suela oscura y algo de tacon,
  - la cintura mas estrecha (se quita la columna de cada lado de la tripa) y un poco de pecho bajo la camiseta,
  - la cabeza: MELENA COBRIZA que enmarca la cara y cae por la espalda, flequillo de lado, cara en ovalo, piel lisa y
    SIN MAQUILLAJE. Los ojos van en los huesos del soldado (eye_*), repintados: parpadean igual.

Escribe tools/piezas_blender/vecino_ella.json (el nombre va detras de "vecino_civil": las piezas entran en la paleta
por orden de nombre y asi no se mueve el color de ninguna de las que ya habia). Uso:
    python tools/make_mujer.py && python tools/make_soldier.py
"""
import io
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_comando import _h, ruido, RIG, BASE, RAIZ   # noqa: E402
from make_civil import NUCLEO_Z, FUERA                 # noqa: E402  (que es equipo del soldado y se quita)

SALIDA = os.path.join(RAIZ, "tools", "piezas_blender", "vecino_ella.json")

COLORES = {
    "denim": (108, 144, 188), "denim_osc": (80, 112, 156), "denim_claro": (140, 172, 208), "denim_costura": (206, 168, 104),
    "camiseta": (238, 236, 230), "camiseta_sombra": (214, 212, 206),
    "pantalon": (38, 38, 44), "pantalon_luz": (50, 50, 58),
    "botin": (112, 70, 42), "botin_osc": (86, 52, 30), "botin_suela": (46, 34, 26),
    "piel_luz": (246, 212, 184), "piel": (234, 194, 162), "piel_osc": (212, 170, 138), "piel_honda": (184, 142, 112),
    "labios": (214, 150, 134),                                        # su color, apenas mas rosado que la piel
    "blanco_ojo": (242, 240, 236), "iris": (132, 92, 58), "iris_osc": (98, 66, 40),
    "pelo": (136, 64, 34), "pelo_osc": (102, 46, 24), "pelo_luz": (172, 92, 52),
    "ceja": (112, 54, 30), "pestana": (58, 34, 24),
}
colores = [list(c) for c in COLORES.values()]
idx = {n: i for i, n in enumerate(COLORES.keys())}


def _var(p, semilla, k):
    return _h(p[0] + 100, p[1] + 100, p[2] + 100, semilla) < k


def _piel(t, p):
    if _var(p, 5, 0.16):
        t += 1 if _var(p, 6, 0.5) else -1
    return ("piel_luz", "piel", "piel_osc", "piel_honda")[max(0, min(3, t))]


def _pelo(p):
    # mechones: el ruido va a lo largo (poca escala en Y) para que parezcan hebras que caen
    n = ruido(p[0] * 3.0, p[1] * 0.6, p[2] * 3.0, 3.0, 51)
    if n > 0.66:
        return "pelo_luz"
    return "pelo_osc" if n < 0.34 else "pelo"


def denim(p):
    n = ruido(p[0], p[1], p[2], 3.0, 61)
    if n > 0.68:
        return "denim_claro"
    return "denim_osc" if n < 0.28 else "denim"


def pantalon(p):
    return "pantalon_luz" if ruido(p[0], p[1], p[2], 2.5, 71) > 0.8 else "pantalon"


# la chaqueta esta ABIERTA por delante: entre estas columnas (x) se ve la camiseta
ABERTURA = (-5, 0)


def color_cuerpo(hueso, p):
    x, y, z = p
    if hueso in ("chest", "stomach", "hood", "shoulder_l", "shoulder_r"):
        if hueso == "stomach" and y <= 40:
            return pantalon(p)                                          # la cinturilla
        if hueso == "stomach" and y == 41:
            return "camiseta_sombra"                                    # la camiseta asoma bajo la chaqueta
        if hueso == "chest" and z == -2 and ABERTURA[0] <= x <= ABERTURA[1]:
            if y >= 60 and -4 <= x <= -1:
                return "piel"                                           # el escote redondo
            return "camiseta" if y >= 50 else "camiseta_sombra"
        if hueso == "stomach" and z == -2 and ABERTURA[0] <= x <= ABERTURA[1]:
            return "camiseta_sombra"
        if hueso == "hood" and y >= 60:
            return "denim_claro"                                        # el cuello de la chaqueta
        # las solapas de los bolsillos del pecho y las costuras
        if hueso == "chest" and z == -2 and y in (55, 56) and (-8 <= x <= -6 or 1 <= x <= 3):
            return "denim_osc" if y == 56 else "denim_costura"
        if hueso == "chest" and z == -2 and x in (-6, 1):
            return "denim_costura" if y % 3 == 0 else "denim_osc"     # el canto de la abertura, pespunteado
        return denim(p)
    if hueso in ("arm_upper_l", "arm_upper_r"):
        return denim(p)
    if hueso in ("arm_lower_l", "arm_lower_r"):
        ax = abs(x + 2.5)
        if ax >= 30.5:
            return "denim_claro"                                        # el puño vuelto
        return denim(p)
    if hueso in ("hand_l", "hand_r", "neck"):
        return _piel_lisa(1)
    if hueso in ("pelvis", "leg_upper_l", "leg_upper_r"):
        return pantalon(p)
    if hueso in ("leg_lower_l", "leg_lower_r"):
        if y >= 9:
            return pantalon(p)
        if y == 8:
            return "botin_osc"                                          # la boca del botin
        return "botin"
    if hueso in ("foot_l", "foot_r", "toes_l", "toes_r"):
        if y <= -2:
            return "botin_suela"
        if y == -1 and z >= 4:
            return "botin_suela"                                        # el tacon
        return "botin_osc" if (y == 2 and z <= 0) else "botin"
    return None


def extras(hueso, d):
    """Lo que se AÑADE al cuerpo del soldado: el pecho bajo la camiseta."""
    o = [int(round(d["world_pos"][i] + d["mesh_off"][i])) for i in range(3)]
    out = {}
    if hueso == "chest":
        for y in range(52, 56):
            for x in range(-5, 1):
                esquina = (y in (52, 55)) and x in (-5, -3, -2, 0)
                if not esquina and x not in (-3, -2) or (y in (53, 54) and x in (-3, -2)):
                    out[(x, y, -3)] = "camiseta" if y >= 53 else "camiseta_sombra"
    return o, out


# ---------------------------------------------------------------------------------------------------------------
# LA CABEZA (rehecha el 2026-09-29, pedido: "la cara es horrible, parece un travesti" y "no le pongas maquillaje").
# Lo que la hacia masculina era el CRANEO DEL SOLDADO: la frente salia un voxel por encima de los ojos (una ceja de
# boxeador), la mandibula era cuadrada y la piel moteada parecia barba de dos dias; encima, labios rosas, colorete y
# rabillo. Ahora: la frente PLANA, la cara en OVALO (la barbilla se estrecha), la piel LISA, sin nariz saliente, los
# labios de su color y los ojos con el iris grande. Nada de maquillaje.
# Los ojos: el hueso de arriba (eye_*_up) se pinta de PARPADO (la fila de abajo, la linea de las pestañas; la de
# arriba, piel) y el de abajo (eye_*_dn) de ojo con el iris de dos columnas hacia la nariz. Al cerrarse, los dos se
# aplastan hacia la linea que los separa: el ojo se cierra en la linea de las pestañas.
# ---------------------------------------------------------------------------------------------------------------
def _piel_lisa(t):
    return ("piel_luz", "piel", "piel_osc", "piel_honda")[max(0, min(3, t))]


def _color_craneo(p):
    x, y, z = p
    if z >= 5 and y >= 64:
        return _pelo(p)
    if x in (-7, 2) and z >= -3 and y >= 64:
        return _pelo(p)                                               # los lados, tapados por la melena
    if z == -4:
        cx = abs(x + 2.5)
        t = 0 if cx <= 2.0 else 1
        if y == 66 and x in (-3, -2):
            t = 1                                                     # la sombra de debajo de la nariz
        if y == 65 and x in (-3, -2):
            return "labios"                                           # los labios, de su color
        if y <= 63:
            t = 1
        return _piel_lisa(t)
    return _piel_lisa(1 if y >= 64 or z <= 0 else 2)


def cabeza(d):
    o = [int(round(d["world_pos"][i] + d["mesh_off"][i])) for i in range(3)]
    viejo = {(o[0] + int(v[0]), o[1] + int(v[1]), o[2] + int(v[2])) for v in d["voxels"]}
    n = {}
    for p in viejo:
        x, y, z = p
        if y >= 71 or (z <= -5 and y <= 65):
            continue
        # EL OVALO: la barbilla se estrecha (fuera las esquinas de la mandibula)
        if y == 63 and x in (-6, 1):
            continue
        if y == 64 and x in (-6, 1) and z == -4:
            continue
        n[p] = _color_craneo(p)
    # el craneo de arriba: la FRENTE PLANA (en la misma cara que el resto, z -4) y pelo por fuera
    for y in range(71, 77):
        for x in range(-7, 3):
            for z in range(-4, 7):
                frente = z == -4 and y <= 73 and -6 <= x <= 1
                n[(x, y, z)] = _piel_lisa(0 if abs(x + 2.5) <= 2.0 else 1) if frente else _pelo((x, y, z))
    for x in (-6, -5, -4, -2, -1, 0):
        n[(x, 73, -4)] = "ceja"                                       # las cejas, finas y del color del pelo
    # los mechones que enmarcan la cara llegan hasta delante (si no, el canto de la cara queda al aire)
    for y in range(62, 74):
        for x in (-7, 2):
            for z in (-4, -3):
                n[(x, y, z)] = _pelo((x, y, z))
    # el FLEQUILLO: un voxel por delante de la frente, arriba, y cayendo hacia un lado
    for x in range(-7, 3):
        n[(x, 75, -5)] = _pelo((x, 75, -5))
        if x <= -1:
            n[(x, 74, -5)] = _pelo((x, 74, -5))
    # LA MELENA: por los lados enmarca la cara hasta la mandibula, por detras cae por la espalda
    for y in range(62, 77):
        for z in range(-3, 8):
            for x in (-8, 3):
                if y <= 63 and z <= -2:
                    continue                                          # las puntas, algo recogidas delante
                n[(x, y, z)] = _pelo((x, y, z))
    for y in range(56, 77):
        for x in range(-8, 4):
            if y < 62 and x in (-8, 3):
                continue                                              # abajo se estrecha
            if y < 59 and x in (-7, 2):
                continue
            n[(x, y, 7)] = _pelo((x, y, 7))
            if y >= 60:
                n[(x, y, 8)] = _pelo((x, y, 8))
    for x in range(-7, 3):                                            # el volumen de arriba
        for z in range(-4, 8):
            if not (x in (-7, 2) and z in (-4, 7)):
                n[(x, 77, z)] = _pelo((x, 77, z))
    return [[p[0] - o[0], p[1] - o[1], p[2] - o[2], "N", idx[c]] for p, c in sorted(n.items())]


def ojo(hueso, voxels):
    """El parpado (eye_*_up) y el ojo (eye_*_dn), pintados de nuevo. En local: x 0..2; en el izquierdo la nariz
    queda en x=2 y en el derecho en x=0."""
    nariz = 2 if hueso.startswith("eye_l") else 0
    out = []
    for v in voxels:
        x, y = int(v[0]), int(v[1])
        if hueso.endswith("_up"):
            c = "pestana" if y == 0 else _piel_lisa(0)
        else:
            if abs(x - nariz) <= 1:
                # (la fila de arriba oscura, pegada a las pestañas, le ponia cara de enfado)
                c = "iris_osc" if (y == -1 and x == nariz) else "iris"
            else:
                c = "blanco_ojo"
        out.append([v[0], v[1], v[2], "N", idx[c]])
    return out



def main():
    rig = json.load(io.open(RIG, encoding="utf-8"))
    vox = {}
    for hueso, d in rig["bones"].items():
        if hueso == "head":
            vox[hueso] = cabeza(d)
            continue
        if hueso in FUERA:
            vox[hueso] = []
            continue
        if hueso.startswith("eye_"):
            vox[hueso] = ojo(hueso, d["voxels"])
            continue
        o = [int(round(d["world_pos"][i] + d["mesh_off"][i])) for i in range(3)]
        nz = NUCLEO_Z.get(hueso)
        lista = []
        for v in d["voxels"]:
            p = (o[0] + int(v[0]), o[1] + int(v[1]), o[2] + int(v[2]))
            if nz and not (nz[0] <= p[2] <= nz[1]):
                continue
            # LA CINTURA: la tripa pierde la columna de cada lado (de 12 a 10 de ancho)
            if hueso == "stomach" and p[0] in (-8, 3) and p[1] >= 41:
                continue
            lista.append([v[0], v[1], v[2], "N", idx[color_cuerpo(hueso, p)]])
        oo, mas = extras(hueso, d)
        ya = {(int(v[0]), int(v[1]), int(v[2])) for v in lista}
        for p, c in mas.items():
            l = (p[0] - oo[0], p[1] - oo[1], p[2] - oo[2])
            if l not in ya:
                lista.append([l[0], l[1], l[2], "N", idx[c]])
        vox[hueso] = lista
    fuera = {
        "nombre": "vecino_ella",
        "origen": "tools/make_mujer.py (el soldado de serie sin equipo: chaqueta vaquera, camiseta, pantalon negro, botines y melena)",
        "tapa": sorted(rig["bones"].keys()),
        "colores": colores,
        "vox": vox,
    }
    json.dump(fuera, io.open(SALIDA, "w", encoding="utf-8"), separators=(",", ":"), ensure_ascii=False)
    print("escrito %s: %d voxels, %d colores" % (SALIDA, sum(len(l) for l in vox.values()), len(colores)))


if __name__ == "__main__":
    main()
