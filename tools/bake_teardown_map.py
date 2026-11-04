#!/usr/bin/env python3
"""
Horneador de mapas de Teardown -> .vxmap (formato de mapa de Breach / vxcore).

Lee la escena XML de un mod de Teardown (grupos, cuerpos, <vox> con objetos nombrados, prefabs
<instance>, <voxbox>), coloca cada voxel de cada .vox (formato MagicaVoxel, grafo de escena
nTRN/nGRP/nSHP) en una rejilla global de 10 cm y escribe:

  - dust.vxmap      : voxels de 10 cm (fidelidad exacta al mod, PC)
  - dust_lo.vxmap   : voxels de 20 cm (2x2x2 -> 1, para móvil)

Colores: las paletas de todos los .vox se cuantizan (k-means ponderado por uso) a 239 materiales
conservando la CLASE FÍSICA de Teardown, que va codificada en el índice de paleta:
  1-8 glass · 9-24 grass · 25-40 dirt · 41-56 plastic · 57-72 wood · 73-88 plaster · 89-104 concrete
  105-120 brick · 121-136 weak metal · 137-152 hard masonry · 153-168 hard metal · 169-176 heavy metal
  177-224 rock · 225-240 unphysical · 241-255 reservado

Uso:  python bake_teardown_map.py "<carpeta del mod>" <escena.xml> <salida sin extensión>
"""
import sys, os, struct, math, time
import xml.etree.ElementTree as ET
import numpy as np

VOXEL = 0.1
CHUNK = 32

# clase -> (strength, density, support, massQ, flags)   flags: 1 anchor, 2 indestructible, 4 glass
CLASS_PHYS = {
    "glass":       (10, 2500, 0, 17, 4),
    "grass":       (200, 1500, 16, 10, 1),
    "dirt":        (200, 1600, 16, 10, 1),
    "plastic":     (45, 900, 6, 6, 0),
    "wood":        (55, 600, 8, 4, 0),
    "plaster":     (40, 1000, 10, 7, 0),
    "concrete":    (170, 2400, 16, 16, 0),
    "brick":       (120, 1900, 13, 13, 0),
    "weakmetal":   (150, 7000, 18, 45, 0),
    "hardmasonry": (200, 2500, 18, 17, 0),
    "hardmetal":   (220, 7800, 20, 52, 0),
    "heavymetal":  (240, 7800, 22, 52, 0),
    "rock":        (230, 2600, 20, 17, 0),
    "unphysical":  (30, 300, 1, 2, 0),
    "ground":      (255, 2400, 16, 16, 3),
    "terrain":     (230, 2600, 20, 17, 1),   # roca del heightmap (ground.lua): ancla, destructible con explosivos
}
# ground.lua: materiales de la capa superior según el canal B del heightmap
TERRAIN_TOP = {32: (121, 84, 75), 48: (131, 119, 103), 64: (218, 197, 170), 80: (217, 205, 189),
               96: (91, 88, 84), 112: (150, 122, 86), 128: (188, 171, 143), 144: (163, 148, 127)}
TERRAIN_SAND = (188, 171, 143)
CLASS_ORDER = list(CLASS_PHYS.keys())

def td_class(idx: int) -> str:
    if idx <= 8: return "glass"
    if idx <= 24: return "grass"
    if idx <= 40: return "dirt"
    if idx <= 56: return "plastic"
    if idx <= 72: return "wood"
    if idx <= 88: return "plaster"
    if idx <= 104: return "concrete"
    if idx <= 120: return "brick"
    if idx <= 136: return "weakmetal"
    if idx <= 152: return "hardmasonry"
    if idx <= 168: return "hardmetal"
    if idx <= 176: return "heavymetal"
    if idx <= 224: return "rock"
    if idx <= 240: return "unphysical"
    return "unphysical"

# ----------------------------------------------------------------------------- .vox
def mv_rot(byte: int) -> np.ndarray:
    """Descodifica la rotación de MagicaVoxel (byte) a matriz 3x3 de enteros."""
    r = np.zeros((3, 3), dtype=np.int64)
    i0 = byte & 3
    i1 = (byte >> 2) & 3
    i2 = 3 - i0 - i1
    r[0, i0] = -1 if (byte >> 4) & 1 else 1
    r[1, i1] = -1 if (byte >> 5) & 1 else 1
    r[2, i2] = -1 if (byte >> 6) & 1 else 1
    return r

class VoxFile:
    def __init__(self, path):
        d = open(path, "rb").read()
        assert d[:4] == b'VOX ', path
        self.sizes = []; self.models = []; self.palette = None
        self.trn = {}; self.grp = {}; self.shp = {}
        self.matl = {}          # índice de paleta -> dict MATL de MagicaVoxel (_type, _emit, _flux...)
        self.path = path
        self.overrides = None   # lo asigna el Baker (reglas por mapa)
        def rd_str(b, o):
            n = struct.unpack("<I", b[o:o+4])[0]; return b[o+4:o+4+n].decode('latin1'), o+4+n
        def rd_dict(b, o):
            n = struct.unpack("<I", b[o:o+4])[0]; o += 4; dd = {}
            for _ in range(n):
                k, o = rd_str(b, o); v, o = rd_str(b, o); dd[k] = v
            return dd, o
        def walk(p, end):
            while p < end:
                cid = d[p:p+4]; n, m = struct.unpack("<II", d[p+4:p+12]); body = d[p+12:p+12+n]
                if cid == b'MAIN': walk(p+12+n, p+12+n+m)
                elif cid == b'SIZE': self.sizes.append(struct.unpack("<III", body[:12]))
                elif cid == b'XYZI':
                    n2 = struct.unpack("<I", body[:4])[0]
                    self.models.append(np.frombuffer(body[4:4+4*n2], dtype=np.uint8).reshape(-1, 4).copy())
                elif cid == b'RGBA':
                    self.palette = np.frombuffer(body[:1024], dtype=np.uint8).reshape(256, 4).copy()
                elif cid == b'MATL':
                    mid = struct.unpack("<I", body[:4])[0]; dd, _o = rd_dict(body, 4)
                    self.matl[mid] = dd
                elif cid == b'nTRN':
                    nid = struct.unpack("<I", body[:4])[0]; attrs, o = rd_dict(body, 4)
                    child = struct.unpack("<i", body[o:o+4])[0]; o += 8
                    o += 4; nf = struct.unpack("<I", body[o:o+4])[0]; o += 4
                    frames = []
                    for _ in range(nf):
                        fd, o = rd_dict(body, o); frames.append(fd)
                    self.trn[nid] = (attrs.get('_name', ''), child, frames[0] if frames else {})
                elif cid == b'nGRP':
                    nid = struct.unpack("<I", body[:4])[0]; attrs, o = rd_dict(body, 4)
                    n2 = struct.unpack("<I", body[o:o+4])[0]; o += 4
                    self.grp[nid] = list(struct.unpack("<%di" % n2, body[o:o+4*n2]))
                elif cid == b'nSHP':
                    nid = struct.unpack("<I", body[:4])[0]; attrs, o = rd_dict(body, 4)
                    n2 = struct.unpack("<I", body[o:o+4])[0]; o += 4
                    ms = []
                    for _ in range(n2):
                        mid = struct.unpack("<i", body[o:o+4])[0]; o += 4; _a, o = rd_dict(body, o); ms.append(mid)
                    self.shp[nid] = ms
                p += 12 + n + m
        walk(8, len(d))
        if self.palette is None:
            self.palette = np.zeros((256, 4), dtype=np.uint8)
        # paleta MV: índice de voxel i usa palette[i-1]
        self.pal_rgb = np.zeros((256, 3), dtype=np.int64)
        self.pal_rgb[1:] = self.palette[:255, :3]
        # colocaciones: (model_id, R 3x3, t, nombre)
        self.placements = []
        if self.trn:
            self._walk_node(0, np.eye(3, dtype=np.int64), np.zeros(3, dtype=np.int64), "")
        else:
            for mi in range(len(self.models)):
                self.placements.append((mi, np.eye(3, dtype=np.int64), np.zeros(3, dtype=np.int64), ""))

    def class_of(self, idx: int) -> str:
        """Clase física de un índice de paleta: rango de Teardown, corregido por el tipo de material de
        MagicaVoxel (_metal -> metal débil, _glass -> cristal) y por las reglas del mapa (overrides)."""
        cls = td_class(idx)
        m = self.matl.get(idx, {})
        t = m.get('_type', '')
        if t == '_metal' and cls not in ("hardmetal", "heavymetal", "weakmetal"):
            cls = "weakmetal"
        elif t == '_glass' and cls != "glass":
            cls = "glass"
        ov = self.overrides or {}
        if cls != "glass":
            cls = ov.get("class_remap", {}).get(cls, cls)
            fn = os.path.basename(self.path).lower()
            for pat, c2 in ov.get("class_by_file", {}).items():
                if pat.lower() in fn:
                    cls = c2
                    break
        return cls

    def emissive(self, idx: int) -> bool:
        """Emisivo si MagicaVoxel lo marca como Emit con power (_flux) >= 2, como exige Teardown."""
        m = self.matl.get(idx, {})
        if m.get('_type', '') != '_emit':
            return False
        try:
            return float(m.get('_flux', '0')) >= 2.0 and float(m.get('_emit', '0')) > 0.0
        except ValueError:
            return False

    def _walk_node(self, nid, R, t, name):
        if nid in self.trn:
            nm, child, fr = self.trn[nid]
            lr = mv_rot(int(fr.get('_r', '4'))) if '_r' in fr else np.eye(3, dtype=np.int64)
            lt = np.array([int(v) for v in fr.get('_t', '0 0 0').split()], dtype=np.int64)
            R2 = R @ lr
            t2 = R @ lt + t
            self._walk_node(child, R2, t2, nm or name)
        elif nid in self.grp:
            for c in self.grp[nid]:
                self._walk_node(c, R, t, name)
        elif nid in self.shp:
            for mi in self.shp[nid]:
                self.placements.append((mi, R, t, name))

    def voxels_world_mv(self, object_name=None):
        """Devuelve (coords MV enteras Nx3, índices de paleta N) de los modelos que coinciden."""
        outs = []
        for mi, R, t, name in self.placements:
            if object_name and name != object_name:
                continue
            xyzi = self.models[mi]
            # índices 241..255 son reservados en Teardown (255 = marcador "hueco", rojo puro): no son voxels visibles
            xyzi = xyzi[xyzi[:, 3] < 241]
            if xyzi.shape[0] == 0:
                continue
            size = np.array(self.sizes[mi], dtype=np.int64)
            v = xyzi[:, :3].astype(np.int64)
            # centrado exacto en medias unidades: c = 2v + 1 - size  (impar), rotar, volver a entero
            c = 2 * v + 1 - size
            cr = c @ R.T
            w = (cr - 1) // 2 + t
            if object_name:
                # <vox object="..."> : Teardown pivota el objeto en el CENTRO de su caja en horizontal y en su
                # BASE en vertical (z de MagicaVoxel), ignorando dónde esté colocado dentro de la escena .vox
                # (los modders reparten los objetos por la escena). Comprobado con item_pot (tapa a +0.4 m en el
                # XML = altura de la olla) y plant_palmtree (hojas en la copa del tronco de 5,1 m).
                w = (cr - 1) // 2
                w[:, 2] -= w[:, 2].min()
            outs.append((w, xyzi[:, 3].astype(np.int64)))
        if not outs:
            return np.zeros((0, 3), dtype=np.int64), np.zeros(0, dtype=np.int64)
        return np.concatenate([o[0] for o in outs]), np.concatenate([o[1] for o in outs])

    def bounds_mv(self, object_name=None):
        mn = np.array([1e9]*3); mx = np.array([-1e9]*3); found = False
        for mi, R, t, name in self.placements:
            if object_name and name != object_name: continue
            size = np.array(self.sizes[mi], dtype=np.int64)
            corners = np.array([[x, y, z] for x in (0, size[0]) for y in (0, size[1]) for z in (0, size[2])], dtype=np.int64)
            c = 2 * corners - size
            w = (c @ R.T) // 2 + t
            if object_name:
                w = (c @ R.T) // 2
                w[:, 2] -= w[:, 2].min()
            mn = np.minimum(mn, w.min(0)); mx = np.maximum(mx, w.max(0)); found = True
        return (mn, mx) if found else None

# ----------------------------------------------------------------------------- XML / transformaciones
def rot_euler_td(x, y, z):
    """Teardown: yaw (Y), pitch (X), roll (Z). Matriz = Ry * Rx * Rz."""
    cx, sx = math.cos(math.radians(x)), math.sin(math.radians(x))
    cy, sy = math.cos(math.radians(y)), math.sin(math.radians(y))
    cz, sz = math.cos(math.radians(z)), math.sin(math.radians(z))
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return Ry @ Rx @ Rz

def parse_vec(s, default):
    if s is None: return np.array(default, dtype=np.float64)
    parts = s.split()
    vals = []
    for p in parts[:3]:
        try:
            vals.append(float(p))
        except ValueError:   # algunos mods escriben rot="0 0 -" o similares
            vals.append(0.0)
    return np.array(vals + [0.0] * (3 - len(vals)), dtype=np.float64)

def local_matrix(el):
    pos = parse_vec(el.get("pos"), [0, 0, 0])
    rot = parse_vec(el.get("rot"), [0, 0, 0])
    M = np.eye(4)
    M[:3, :3] = rot_euler_td(rot[0], rot[1], rot[2])
    M[:3, 3] = pos
    return M

SKIP_TAGS = {"light", "location", "joint", "trigger", "water", "boundary", "rope", "script", "voxscript", "voxagon",
             "environment", "postprocessing", "spawnpoint", "screen", "wheel", "parameters", "vertex", "layers", "layer"}
SKIP_INSTANCE_SUBSTR = ("chicken", "robot/", "mech")

class Baker:
    def __init__(self, mod_root):
        self.mod_root = mod_root
        self.vox_cache = {}
        self.items = []       # (kind, data) kind: "vox" (VoxFile, object, M4x4) | "box" (M, size, rgb)
        self.spawns = []
        self.lights = []
        self.warnings = []
        self.overlaps = []
        self.terrain_set = frozenset()
        self.overrides = {}

    def resolve(self, f):
        if f.startswith("MOD/"): f = f[4:]
        return os.path.join(self.mod_root, f.replace("/", os.sep))

    def vox(self, path):
        if path not in self.vox_cache:
            vf = VoxFile(path)
            vf.overrides = self.overrides
            self.vox_cache[path] = vf
        return self.vox_cache[path]

    def walk(self, el, M, depth=0):
        tag = el.tag
        if tag == "spawnpoint":
            Ms = M @ local_matrix(el)
            self.spawns.append((Ms[:3, 3].copy(), parse_vec(el.get("rot"), [0, 0, 0])[1]))
            return
        if tag == "voxscript" and el.get("file", "").endswith("ground.lua"):
            Mv = M @ local_matrix(el)
            tile = 62; img = None
            for prm in el:
                if prm.tag == "parameters":
                    tile = int(prm.get("tilesize", "62")); img = prm.get("file")
            if img:
                path = self.resolve(img)
                if os.path.exists(path):
                    self.items.append(("heightmap", Mv, path, tile))
                else:
                    print("  [aviso] falta heightmap", path)
            return
        if tag in SKIP_TAGS:
            return
        Ml = M @ local_matrix(el) if tag not in ("scene", "prefab") else M
        if tag == "vox":
            f = el.get("file")
            if f:
                path = self.resolve(f)
                if os.path.exists(path):
                    scale = float(el.get("scale", "1") or 1)
                    desc = "%s%s" % (f, (" object=" + el.get("object")) if el.get("object") else "")
                    self.items.append(("vox", self.vox(path), el.get("object"), Ml, scale, desc))
                else:
                    print("  [aviso] falta", path)
        elif tag == "voxbox":
            size = parse_vec(el.get("size"), [1, 1, 1]).astype(np.int64)
            col = parse_vec(el.get("color"), [1, 1, 1])
            brush = None
            if el.get("brush"):
                bp = self.resolve(el.get("brush"))
                if os.path.exists(bp):
                    brush = (self.vox(bp), el.get("object"), parse_vec(el.get("offset"), [0, 0, 0]).astype(np.int64))
                else:
                    print("  [aviso] falta brush", bp)
            self.items.append(("box", Ml, size, (col * 255).astype(np.int64), brush))
        elif tag == "instance":
            f = el.get("file", "")
            if any(s in f for s in SKIP_INSTANCE_SUBSTR):
                return
            path = self.resolve(f)
            if os.path.exists(path) and path.endswith(".xml"):
                sub = ET.parse(path).getroot()
                for child in sub:
                    # el grupo raíz del prefab guarda la posición del editor: se ignora (manda el <instance>)
                    if child.tag == "group" and (child.get("name", "").startswith("instance=") or True):
                        for gc in child:
                            self.walk(gc, Ml, depth + 1)
                    else:
                        self.walk(child, Ml, depth + 1)
            return
        for child in el:
            if tag == "spawnpoint":
                break
            self.walk(child, Ml, depth + 1)

    # ------------------------------------------------------------------ colores
    def build_palette(self):
        """Histograma (clase, rgb) ponderado por voxels; k-means por clase hasta 239 entradas."""
        hist = {}
        for it in self.items:
            if it[0] == "box" and len(it) > 4 and it[4] is not None:
                it = ("vox", it[4][0], it[4][1])
            if it[0] != "vox": continue
            vf, obj = it[1], it[2]
            _, idx = vf.voxels_world_mv(obj)
            if idx.size == 0: continue
            counts = np.bincount(idx, minlength=256)
            for i in np.nonzero(counts)[0]:
                if i == 0: continue
                key = (vf.class_of(int(i)), tuple(int(c) for c in vf.pal_rgb[i]), vf.emissive(int(i)))
                hist[key] = hist.get(key, 0) + int(counts[i])
        by_class = {}
        for (cls, rgb, em), w in hist.items():
            by_class.setdefault((cls, em), []).append((rgb, w))
        total_w = sum(hist.values())
        budget = 239 - 1 - len(TERRAIN_TOP)   # los materiales fijos del terreno se añaden después
        # reparto: mínimo 2 por clase presente, resto proporcional a sqrt(peso) para no ahogar clases raras
        alloc = {}
        for cls, lst in by_class.items():
            alloc[cls] = min(len(lst), 2)
        rem = budget - sum(alloc.values())
        weights = {cls: math.sqrt(sum(w for _, w in lst)) for cls, lst in by_class.items()}
        sw = sum(weights.values()) or 1.0
        for cls, lst in by_class.items():
            extra = int(rem * weights[cls] / sw)
            alloc[cls] = min(len(lst), alloc[cls] + extra)
        # ajustar sobrantes (y recortar si el redondeo se pasa del presupuesto)
        left = budget - sum(alloc.values())
        for cls, lst in sorted(by_class.items(), key=lambda kv: -len(kv[1])):
            if left <= 0: break
            add = min(left, len(lst) - alloc[cls]); alloc[cls] += add; left -= add
        while sum(alloc.values()) > budget:
            big = max(alloc, key=lambda k: alloc[k])
            alloc[big] -= 1
        palette = []   # (cls, rgb, emisivo)
        self.color_map = {}   # (cls, rgb, emisivo) -> material id
        for (cls, em), lst in by_class.items():
            cols = np.array([c for c, _ in lst], dtype=np.float64)
            ws = np.array([w for _, w in lst], dtype=np.float64)
            k = max(1, alloc[(cls, em)])
            if len(lst) <= k:
                centers = cols; assign = np.arange(len(lst))
            else:
                centers, assign = weighted_kmeans(cols, ws, k)
            base = len(palette)
            for c in centers:
                palette.append((cls, tuple(int(round(v)) for v in c), em))
            for (rgb, _), a in zip(lst, assign):
                self.color_map[(cls, rgb, em)] = 17 + base + int(a)
        # materiales fijos del terreno (ground.lua)
        self.terrain_ids = {}
        for bval, rgb in [(0, TERRAIN_SAND)] + sorted(TERRAIN_TOP.items()):
            key = ("terrain", rgb, False)
            if key not in self.color_map:
                palette.append(key); self.color_map[key] = 17 + len(palette) - 1
            self.terrain_ids[bval] = self.color_map[key]
        self.terrain_set = frozenset(int(v) for v in self.terrain_ids.values())
        assert len(palette) <= 239, len(palette)
        self.palette = palette
        print("  paleta:", len(palette), "materiales;", {c[0] + ("*" if c[1] else ""): sum(1 for p in palette if (p[0], p[2]) == c) for c in by_class}, "(* = emisivo)")

    def file_lut(self, vf):
        lut = np.zeros(256, dtype=np.uint8)
        for i in range(1, 256):
            key = (vf.class_of(i), tuple(int(c) for c in vf.pal_rgb[i]), vf.emissive(i))
            lut[i] = self.color_map.get(key, 17)
        return lut

    # ------------------------------------------------------------------ colocación
    def compute_bounds(self):
        mn = np.array([1e9]*3); mx = np.array([-1e9]*3)
        for it in self.items:
            if it[0] == "vox":
                vf, obj, M = it[1], it[2], it[3]
                b = vf.bounds_mv(obj)
                if b is None: continue
                lo, hi = b
                corners = np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])], dtype=np.float64)
                td = np.stack([corners[:, 0], corners[:, 2], -corners[:, 1]], 1) * VOXEL
                w = (M[:3, :3] @ td.T).T + M[:3, 3]
            elif it[0] == "heightmap":
                from PIL import Image
                M, path = it[1], it[2]
                im = np.array(Image.open(path))
                hmax = int(im[..., 0].max()) + 1
                corners = np.array([[x, y, z] for x in (0, im.shape[1]) for y in (0, hmax) for z in (0, im.shape[0])], dtype=np.float64) * VOXEL
                w = (M[:3, :3] @ corners.T).T + M[:3, 3]
            else:
                M, size = it[1], it[2]
                corners = np.array([[x, y, z] for x in (0, size[0]) for y in (0, size[1]) for z in (0, size[2])], dtype=np.float64) * VOXEL
                w = (M[:3, :3] @ corners.T).T + M[:3, 3]
            mn = np.minimum(mn, w.min(0)); mx = np.maximum(mx, w.max(0))
        return mn, mx

    def place(self, voxel_size):
        mn, mx = self.bounds
        origin = np.floor(mn / voxel_size) * voxel_size - np.array([voxel_size, 0.0, voxel_size]) * 2
        # el suelo (y mínimo) queda en la fila 0 -> anclaje automático
        origin[1] = math.floor(mn[1] / voxel_size) * voxel_size
        dims_m = mx - origin
        ncx = int(math.ceil(dims_m[0] / voxel_size / CHUNK)) + 1
        ncy = int(math.ceil(dims_m[1] / voxel_size / CHUNK)) + 1
        ncz = int(math.ceil(dims_m[2] / voxel_size / CHUNK)) + 1
        chunks = {}
        sx, sy, sz = ncx * CHUNK, ncy * CHUNK, ncz * CHUNK
        t0 = time.time(); nvox = 0
        # el terreno primero: los edificios se escriben después y ganan donde se solapan
        order = sorted(range(len(self.items)), key=lambda i: 0 if self.items[i][0] == "heightmap" else 1)
        for n, ii in enumerate(order):
            it = self.items[ii]
            if it[0] == "heightmap":
                nvox += self._place_heightmap(chunks, it, origin, voxel_size, sx, sy, sz)
                continue
            if it[0] == "vox":
                vf, obj, M, scale, desc = it[1], it[2], it[3], it[4], it[5]
                w_mv, idx = vf.voxels_world_mv(obj)
                if idx.size == 0:
                    self.warnings.append("sin voxels: %s en (%.1f, %.1f, %.1f)%s" % (desc, *M[:3, 3], " (¿nombre de objeto mal escrito?)" if obj else ""))
                    continue
                lut = self.file_lut(vf)
                mats = lut[idx]
                # MV (x,y,z) -> Teardown (x, z, -y-1) en voxels de 0.1; centro del voxel
                td = np.stack([w_mv[:, 0], w_mv[:, 2], -w_mv[:, 1] - 1], 1).astype(np.float64)
                R = M[:3, :3]
                axis_aligned = np.all(np.abs(np.abs(R) - np.round(np.abs(R))) < 1e-4)
                cell = VOXEL * scale   # <vox scale="..."> cambia el tamaño del voxel de esa forma
                overlap = 0
                if axis_aligned and abs(scale - 1.0) < 1e-6 or voxel_size > cell * 1.5:
                    centers = (td + 0.5) * cell
                    w = (R @ centers.T).T + M[:3, 3]
                    overlap += self._scatter(chunks, w, mats, origin, voxel_size, sx, sy, sz, self.terrain_set)
                else:
                    # rotación arbitraria o escala: supermuestreo para no dejar huecos en la rejilla destino
                    ns = max(2, int(math.ceil(cell / voxel_size)) + 1)
                    offs = (np.arange(ns) + 0.5) / ns
                    for ox in offs:
                        for oy in offs:
                            for oz in offs:
                                centers = (td + np.array([ox, oy, oz])) * cell
                                w = (R @ centers.T).T + M[:3, 3]
                                overlap += self._scatter(chunks, w, mats, origin, voxel_size, sx, sy, sz, self.terrain_set, count_only_first=(ox == offs[0] and oy == offs[0] and oz == offs[0]))
                nvox += idx.size
                if idx.size >= 30 and overlap > 0.2 * idx.size:
                    self.overlaps.append((overlap / idx.size, desc, M[:3, 3].copy(), int(idx.size)))
            else:
                M, size, rgb = it[1], it[2], it[3]
                brush = it[4] if len(it) > 4 else None
                pat = None
                if brush is not None:
                    # patrón: voxels del brush en coordenadas Teardown (x, y, z) con mínimo en 0; se repite (tiling)
                    bvf, bobj, boff = brush
                    w_mv, bidx = bvf.voxels_world_mv(bobj)
                    if bidx.size:
                        btd = np.stack([w_mv[:, 0], w_mv[:, 2], -w_mv[:, 1] - 1], 1)
                        btd -= btd.min(0)
                        bdims = btd.max(0) + 1
                        pat = np.zeros(tuple(bdims), dtype=np.uint8)
                        pat[btd[:, 0], btd[:, 1], btd[:, 2]] = self.file_lut(bvf)[bidx]
                        pat_off = boff
                # por losas en y para no reservar cajas de cientos de millones de celdas
                for y0 in range(0, int(size[1]), 8):
                    y1 = min(int(size[1]), y0 + 8)
                    gx, gy, gz = np.meshgrid(np.arange(size[0]), np.arange(y0, y1), np.arange(size[2]), indexing="ij")
                    pts = np.stack([gx.ravel(), gy.ravel(), gz.ravel()], 1)
                    if pat is not None:
                        pi = (pts + pat_off) % np.array(pat.shape)
                        mats = pat[pi[:, 0], pi[:, 1], pi[:, 2]]
                        keep = mats != 0
                        pts = pts[keep]; mats = mats[keep]
                        if pts.shape[0] == 0:
                            continue
                    else:
                        mats = np.full(len(pts), 16, dtype=np.uint8)
                    # voxbox: pos = esquina mínima
                    centers = (pts.astype(np.float64) + 0.5) * VOXEL
                    w = (M[:3, :3] @ centers.T).T + M[:3, 3]
                    self._scatter(chunks, w, mats, origin, voxel_size, sx, sy, sz, self.terrain_set)
                    nvox += len(w)
            if (n + 1) % 100 == 0:
                print("  %d/%d elementos, %d voxels, %.1fs" % (n + 1, len(self.items), nvox, time.time() - t0))
        print("  colocados %d voxels en %d chunks (%dx%dx%d) en %.1fs" % (nvox, len(chunks), ncx, ncy, ncz, time.time() - t0))
        self.report()
        return chunks, (ncx, ncy, ncz), origin

    def report(self):
        """Validación: formas vacías (nombre de objeto inexistente) y formas que se solapan con otras
        formas no-terreno (una carrocería dentro de una pared, una hoja dentro de un tronco...).
        Un solape alto casi siempre significa un pivote o una transformación mal interpretada."""
        print("--- validación ---")
        for wmsg in self.warnings[:40]:
            print("  [aviso] " + wmsg)
        if len(self.warnings) > 40:
            print("  ... %d avisos más" % (len(self.warnings) - 40))
        self.overlaps.sort(key=lambda o: -o[0])
        if self.overlaps:
            print("  formas con más del 20 %% de sus voxels dentro de otras formas: %d" % len(self.overlaps))
            for frac, desc, pos, n in self.overlaps[:25]:
                print("  [solape %3d%%] %s en (%.1f, %.1f, %.1f), %d voxels" % (round(frac * 100), desc, pos[0], pos[1], pos[2], n))
        else:
            print("  sin solapes significativos entre formas")
        if not self.warnings and not self.overlaps:
            print("  OK: todas las formas colocadas y sin solapes")

    def _place_heightmap(self, chunks, it, origin, voxel_size, sx, sy, sz):
        """Réplica de ground.lua: columna de arena de 0..r-1 por píxel y capa superior en r según el canal B."""
        from PIL import Image
        M, path = it[1], it[2]
        im = np.array(Image.open(path))
        H, W = im.shape[0], im.shape[1]
        R = im[..., 0].astype(np.int64); Bc = im[..., 2].astype(np.int64)
        total = 0
        rows_per_block = 16
        for y0 in range(0, H, rows_per_block):
            y1 = min(H, y0 + rows_per_block)
            r = R[y0:y1]; b = Bc[y0:y1]
            # columnas: repetir cada píxel r veces con alturas 0..r-1
            px, py = np.meshgrid(np.arange(W), np.arange(y0, y1), indexing="xy")
            flat_r = r.ravel(); flat_x = px.ravel(); flat_z = py.ravel(); flat_b = b.ravel()
            reps = flat_r
            xs = np.repeat(flat_x, reps); zs = np.repeat(flat_z, reps)
            ys = np.concatenate([np.arange(k) for k in reps]) if reps.sum() else np.zeros(0, dtype=np.int64)
            mats = np.full(len(xs), self.terrain_ids[0], dtype=np.uint8)
            # capa superior (sólo donde hay columna, r>0)
            top = flat_r > 0
            tx = flat_x[top]; tz = flat_z[top]; ty = flat_r[top]; tb = flat_b[top]
            tm = np.array([self.terrain_ids.get(int(v), self.terrain_ids[0]) for v in tb], dtype=np.uint8) if len(tb) else np.zeros(0, dtype=np.uint8)
            allx = np.concatenate([xs, tx]); ally = np.concatenate([ys, ty]); allz = np.concatenate([zs, tz]); allm = np.concatenate([mats, tm])
            if len(allx) == 0: continue
            pts = np.stack([allx, ally, allz], 1).astype(np.float64)
            centers = (pts + 0.5) * VOXEL
            w = (M[:3, :3] @ centers.T).T + M[:3, 3]
            self._scatter(chunks, w, allm, origin, voxel_size, sx, sy, sz)
            total += len(allx)
        print("  terreno (heightmap %dx%d): %d voxels" % (W, H, total))
        return total

    @staticmethod
    def _scatter(chunks, w, mats, origin, voxel_size, sx, sy, sz, terrain_set=frozenset(), count_only_first=True):
        """Escribe los voxels y devuelve cuántos caen sobre voxels ya escritos de otra forma (no terreno)."""
        g = np.floor((w - origin) / voxel_size).astype(np.int64)
        ok = (g[:, 0] >= 0) & (g[:, 1] >= 0) & (g[:, 2] >= 0) & (g[:, 0] < sx) & (g[:, 1] < sy) & (g[:, 2] < sz)
        g = g[ok]; m = mats[ok]
        overlap = 0
        if g.shape[0] == 0: return 0
        cx, cy, cz = g[:, 0] >> 5, g[:, 1] >> 5, g[:, 2] >> 5
        ncx = sx // CHUNK; ncy = sy // CHUNK
        key = cx + ncx * (cy + ncy * cz)
        local = (g[:, 0] & 31) | ((g[:, 1] & 31) << 5) | ((g[:, 2] & 31) << 10)
        order = np.argsort(key, kind="stable")
        key = key[order]; local = local[order]; m = m[order]
        uniq, start = np.unique(key, return_index=True)
        ends = list(start[1:]) + [len(key)]
        for k, s, e in zip(uniq, start, ends):
            arr = chunks.get(int(k))
            if arr is None:
                arr = np.zeros(CHUNK ** 3, dtype=np.uint8); chunks[int(k)] = arr
            if count_only_first and terrain_set:
                prev = arr[local[s:e]]
                nz = prev != 0
                if nz.any():
                    overlap += int(np.count_nonzero(~np.isin(prev[nz], list(terrain_set))))
            arr[local[s:e]] = m[s:e]
        return overlap

def weighted_kmeans(cols, ws, k, iters=12):
    # inicialización: los k colores más pesados, separados
    order = np.argsort(-ws)
    centers = [cols[order[0]]]
    for i in order[1:]:
        if len(centers) >= k: break
        d = min(np.sum((cols[i] - c) ** 2) for c in centers)
        if d > 60: centers.append(cols[i])
    while len(centers) < k:
        centers.append(cols[order[len(centers) % len(order)]] + np.random.RandomState(len(centers)).randn(3))
    C = np.array(centers, dtype=np.float64)
    for _ in range(iters):
        d = ((cols[:, None, :] - C[None, :, :]) ** 2).sum(2)
        a = d.argmin(1)
        for j in range(k):
            msk = a == j
            if msk.any():
                C[j] = (cols[msk] * ws[msk, None]).sum(0) / ws[msk].sum()
    d = ((cols[:, None, :] - C[None, :, :]) ** 2).sum(2)
    return np.clip(np.round(C), 0, 255), d.argmin(1)

def downsample(chunks, dims):
    """2x2x2 -> 1 (sólido si alguno lo es; material del primero sólido). Dims de salida = ceil(dims/2)."""
    ncx, ncy, ncz = dims
    ocx, ocy, ocz = (ncx + 1) // 2, (ncy + 1) // 2, (ncz + 1) // 2
    out = {}
    for key, arr in chunks.items():
        cx = key % ncx; cy = (key // ncx) % ncy; cz = key // (ncx * ncy)
        a = arr.reshape(CHUNK, CHUNK, CHUNK)            # [z][y][x]
        b = a.reshape(16, 2, 16, 2, 16, 2).transpose(0, 2, 4, 1, 3, 5).reshape(16, 16, 16, 8)
        solid = b > 0
        anyv = solid.any(3)
        first = np.argmax(solid, axis=3)
        vals = np.take_along_axis(b, first[..., None], 3)[..., 0]
        vals[~anyv] = 0
        okey = (cx // 2) + ocx * ((cy // 2) + ocy * (cz // 2))
        oarr = out.get(okey)
        if oarr is None:
            oarr = np.zeros(CHUNK ** 3, dtype=np.uint8); out[okey] = oarr
        o3 = oarr.reshape(CHUNK, CHUNK, CHUNK)
        ox, oy, oz = (cx & 1) * 16, (cy & 1) * 16, (cz & 1) * 16
        region = o3[oz:oz+16, oy:oy+16, ox:ox+16]
        region[vals > 0] = vals[vals > 0]
    return out, (ocx, ocy, ocz)

def write_vxmap(path, voxel_size, dims, origin, palette, spawns, chunks):
    # SOLO EL DE 20 CM (2026-10-14, pedido): el de 10 cm ya no se escribe; se juega siempre el `_lo` (los viejos, en el
    # escritorio, carpeta mapas). BREACH_MAPA_10CM=1 lo vuelve a escribir.
    if not str(path).endswith("_lo.vxmap") and not os.environ.get("BREACH_MAPA_10CM"):
        print("  (no se escribe %s: solo el de 20 cm)" % os.path.basename(str(path)))
        return 0
    with open(path, "wb") as f:
        f.write(b'VXMP'); f.write(struct.pack("<I", 1))
        f.write(struct.pack("<f", voxel_size))
        f.write(struct.pack("<iii", *dims))
        f.write(struct.pack("<fff", *origin))
        # materiales: id 16 = suelo del mapa, 17.. = paleta
        entries = [("ground", (188, 171, 143), False)] + palette
        f.write(struct.pack("<H", len(entries)))
        for cls, rgb, em in entries:
            st, dens, sup, mass, flags = CLASS_PHYS[cls]
            if em: flags |= 8   # MF_EMISSIVE
            f.write(struct.pack("<BBBBHBBB", rgb[0], rgb[1], rgb[2], st, dens, flags, sup, mass))
        f.write(struct.pack("<H", len(spawns)))
        for pp, yaw in spawns:
            f.write(struct.pack("<ffff", pp[0], pp[1], pp[2], yaw))
        keys = sorted(chunks.keys())
        f.write(struct.pack("<I", len(keys)))
        total_runs = 0
        for k in keys:
            arr = chunks[k]
            # RLE
            change = np.flatnonzero(np.diff(arr.astype(np.int16))) + 1
            starts = np.concatenate([[0], change])
            lens = np.diff(np.concatenate([starts, [len(arr)]]))
            vals = arr[starts]
            runs = []
            for l, v in zip(lens, vals):
                while l > 65535:
                    runs.append((65535, int(v))); l -= 65535
                runs.append((int(l), int(v)))
            f.write(struct.pack("<II", k, len(runs)))
            f.write(b''.join(struct.pack("<HB", l, v) for l, v in runs))
            total_runs += len(runs)
        print("  escrito %s: %d chunks, %d runs, %.1f MB" % (path, len(keys), total_runs, os.path.getsize(path) / 1048576))

def main():
    if len(sys.argv) < 4:
        print(__doc__); sys.exit(1)
    mod_root, scene, out = sys.argv[1], sys.argv[2], sys.argv[3]
    t0 = time.time()
    baker = Baker(mod_root)
    # reglas por mapa (clases físicas): tools/map_overrides/<nombre>.json
    ov_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "map_overrides", os.path.basename(out) + ".json")
    if os.path.exists(ov_path):
        import json
        baker.overrides = json.load(open(ov_path, encoding="utf-8"))
        print("reglas del mapa:", ov_path, baker.overrides)
    root = ET.parse(scene).getroot()
    baker.walk(root, np.eye(4))
    print("elementos:", len(baker.items), "spawns:", len(baker.spawns), "archivos vox:", len(baker.vox_cache))
    baker.build_palette()
    baker.bounds = baker.compute_bounds()
    print("límites (m): min %s max %s" % (np.round(baker.bounds[0], 2), np.round(baker.bounds[1], 2)))
    chunks, dims, origin = baker.place(VOXEL)
    spawns = [((p - origin), yaw) for p, yaw in baker.spawns]
    write_vxmap(out + ".vxmap", VOXEL, dims, origin, baker.palette, spawns, chunks)
    lo, ldims = downsample(chunks, dims)
    write_vxmap(out + "_lo.vxmap", VOXEL * 2, ldims, origin, baker.palette, spawns, lo)
    # limpieza automática de flotadores (trozos sin conexión con el suelo) en los dos mapas
    try:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import fix_floaters
        for f in [x for x in (out + ".vxmap", out + "_lo.vxmap") if os.path.exists(x)]:
            sys.argv = ["fix_floaters", f]
            fix_floaters.main()
    except ImportError as e:
        print("  [aviso] fix_floaters no disponible (%s): ejecútalo a mano" % e)
    print("hecho en %.1fs" % (time.time() - t0))

if __name__ == "__main__":
    main()
