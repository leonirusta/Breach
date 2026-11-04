"""Dice a que alturas hay suelo en una columna (x,z) de un .vxmap, en coordenadas del juego.

Sirve para colocar a mano sitios de bomba y spawns en un mapa recien importado: en un mapa de
varias plantas (de_nuke tiene el sitio A en la nave y el B en el sotano, uno encima del otro)
hace falta saber la altura EXACTA de cada planta, y a ojo desde el XML no se acierta.

Uso:  python probe_column.py <mapa.vxmap> <x> <z> [radio]
"""
import sys, struct
import numpy as np

def load(path):
    d = open(path, "rb").read()
    assert d[:4] == b"VXMP", "no es un .vxmap"
    ver, vs = struct.unpack_from("<If", d, 4)
    dx, dy, dz = struct.unpack_from("<III", d, 12)
    org = np.array(struct.unpack_from("<fff", d, 24))
    return d, ver, vs, (dx, dy, dz), org

def main():
    if len(sys.argv) < 4:
        print(__doc__); sys.exit(1)
    path = sys.argv[1]
    X, Z = float(sys.argv[2]), float(sys.argv[3])
    R = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0
    d, ver, vs, dims, org = load(path)
    print("%s: %dx%dx%d voxels de %.2f m, origin %s" % (path, dims[0], dims[1], dims[2], vs, np.round(org, 1)))
    print("mundo: %.1f x %.1f x %.1f m" % (dims[0] * vs, dims[1] * vs, dims[2] * vs))
    # decodificar con el mismo lector que fix_floaters (RLE por chunk)
    sys.path.insert(0, ".")
    import fix_floaters as F
    vol = F.read_volume(path) if hasattr(F, "read_volume") else None
    if vol is None:
        print("fix_floaters no expone read_volume; usa su main()")
        sys.exit(2)
    ix, iz = int(X / vs), int(Z / vs)
    rr = max(1, int(R / vs))
    col = vol[max(0, ix - rr):ix + rr + 1, :, max(0, iz - rr):iz + rr + 1]
    ocup = (col != 0).any(axis=(0, 2))
    print("columna (%.1f, %.1f) +-%.1f m -> tramos solidos (altura del juego):" % (X, Z, R))
    y = 0
    n = 0
    while y < len(ocup):
        if ocup[y]:
            y0 = y
            while y < len(ocup) and ocup[y]:
                y += 1
            alto = (y - y0) * vs
            print("   %6.1f .. %6.1f m  (%.1f m de grosor)   -> pisar en y=%.1f" % (y0 * vs, y * vs, alto, y * vs + 0.2))
            n += 1
        else:
            y += 1
    if n == 0:
        print("   nada solido en esa columna")

if __name__ == "__main__":
    main()
