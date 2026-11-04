"""Saca la posicion EN COORDENADAS DEL JUEGO de los elementos con nombre/etiqueta interesantes
de un mod de Teardown (sitios de bomba, spawns de cada equipo, localizadores).

Reutiliza el recorrido de jerarquia del horneador, asi que las transformadas de los grupos
padre se acumulan igual que al hornear los voxels; si no, las posiciones del XML son locales
y caen en cualquier sitio. Al final resta el `origin` del .vxmap, como hace extract_xml_lights.

Uso:  python find_markers.py <carpeta del mod> <escena.xml> <mapa.vxmap> [patron ...]
"""
import sys, os, re
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xml.etree.ElementTree as ET
import bake_teardown_map as B
from extract_xml_lights import map_origin

class MarkerBaker(B.Baker):
    def __init__(self, root, pats):
        super().__init__(root)
        self.pats = [re.compile(p, re.I) for p in pats]
        self.hits = []

    def walk(self, el, M, depth=0):
        Ml = M @ B.local_matrix(el)
        etiqueta = "%s %s" % (el.get("name", ""), el.get("tags", ""))
        if any(p.search(etiqueta) for p in self.pats):
            self.hits.append((el.tag, el.get("name", ""), el.get("tags", ""), Ml[:3, 3].copy()))
        # los <location> no tienen hijos y el horneador los ignora: hay que mirarlos aqui
        if el.tag in ("location", "spawnpoint", "trigger"):
            return
        super().walk(el, M, depth)

def main():
    if len(sys.argv) < 4:
        print(__doc__); sys.exit(1)
    root, scene, vxmap = sys.argv[1], sys.argv[2], sys.argv[3]
    pats = sys.argv[4:] or ["site", "spawn", "bomb"]
    org = map_origin(vxmap)
    b = MarkerBaker(root, pats)
    b.walk(ET.parse(scene).getroot(), np.eye(4))
    print("origin del mapa:", np.round(org, 2))
    print("%d coincidencias (posiciones ya en coordenadas del juego)" % len(b.hits))
    grupos = {}
    for tag, name, tags, p in b.hits:
        g = p - org
        clave = "%s <%s> tags=%s" % (name, tag, tags)
        grupos.setdefault(clave, []).append(g)
    for clave, ps in sorted(grupos.items()):
        a = np.array(ps)
        if len(ps) == 1:
            print("  %-46s  %s" % (clave, np.round(a[0], 1)))
        else:
            print("  %-46s  x%-4d centro %s  min %s  max %s" % (
                clave, len(ps), np.round(a.mean(0), 1), np.round(a.min(0), 1), np.round(a.max(0), 1)))

if __name__ == "__main__":
    main()
