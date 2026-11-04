"""Saca las entidades <light> del XML original de Teardown, con su transformada de mundo.

El horneador las descarta (SKIP_TAGS) porque no aportan voxels, pero traen color, tipo,
alcance e intensidad reales. Se reutiliza su mismo recorrido de jerarquia para que las
posiciones salgan en el mismo marco que el .vxmap.

El XML da coordenadas DEL MOD. El juego coloca el mundo en (0,0,0), y vx_mapfile.h lo dice:
"coordenadas originales del mod = nuestras + origin". Asi que hay que restar el origin que
guarda el .vxmap, o las luces caen decenas de metros fuera del mapa.

Uso:  python extract_xml_lights.py <carpeta del mod> <escena.xml> <salida.json> <mapa.vxmap>
"""
import sys, os, json
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xml.etree.ElementTree as ET
import bake_teardown_map as B

class LightBaker(B.Baker):
    def __init__(self, root):
        super().__init__(root)
        self.lights = []

    def walk(self, el, M, depth=0):
        if el.tag == "light":
            Ml = M @ B.local_matrix(el)
            self.lights.append({
                "pos": Ml[:3, 3].copy(),
                "type": el.get("type", "point"),
                "color": B.parse_vec(el.get("color"), [1, 1, 1]),
                "scale": float(el.get("scale", "1") or 1),
                "angle": float(el.get("angle", "90") or 90),
                "tags": el.get("tags", ""),
                "size": el.get("size", ""),
                "dir": (Ml[:3, :3] @ np.array([0.0, 0.0, -1.0])),
            })
            return
        super().walk(el, M, depth)

def map_origin(vxmap):
    import struct
    d = open(vxmap, "rb").read(36)
    assert d[:4] == b"VXMP", "no es un .vxmap"
    return np.array(struct.unpack_from("<fff", d, 24))

def main(root, scene, dst, vxmap):
    org = map_origin(vxmap)
    print("origin del mapa: %s (se resta para pasar a coordenadas del juego)" % (org,))
    b = LightBaker(root)
    b.walk(ET.parse(scene).getroot(), np.eye(4))
    print("luces encontradas:", len(b.lights))
    tags = {}
    for l in b.lights:
        tags[l["tags"]] = tags.get(l["tags"], 0) + 1
    print("por tag:", tags)
    ys = np.array([l["pos"][1] for l in b.lights])
    print("altura: min %.1f  mediana %.1f  max %.1f" % (ys.min(), np.median(ys), ys.max()))
    # Por defecto sólo las etiquetadas "night": son las que el mapa enciende de noche, y el resto
    # son de relleno que en pleno día no aporta. PERO hay mods (de_nuke) que no etiquetan ninguna:
    # ahí quedarse con las "night" deja el mapa a oscuras, sin una sola luz. Si no hay ninguna
    # etiquetada, se cogen todas.
    hay_night = any("night" in l["tags"] for l in b.lights)
    if not hay_night:
        print("  ninguna luz trae el tag night: se quedan las %d" % len(b.lights))
    out = []
    for l in b.lights:
        if hay_night and "night" not in l["tags"]:
            continue
        # Teardown no guarda alcance: "scale" es la intensidad. Se reparte en energía y
        # alcance con un tope, para que una luz de scale 32 no bañe medio mapa.
        sc = max(0.2, l["scale"])
        energy = round(min(1.2 + 0.35 * sc, 5.0), 3)
        reach = round(min(6.0 + 1.6 * sc, 22.0), 2)
        gp = l["pos"] - org
        out.append({
            "pos": [round(float(c), 3) for c in gp],
            "color": [round(float(c), 4) for c in l["color"][:3]],
            "energy": energy,
            "range": reach,
        })
    json.dump({"lights": out, "source": "teardown-xml"}, open(dst, "w"), separators=(",", ":"))
    print("escrito %s: %d luces (de %d)" % (dst, len(out), len(b.lights)))

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
