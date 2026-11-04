"""Post-proceso de mapas .vxmap: elimina los "flotadores".

Al importar un mod de Teardown quedan cientos de trozos de voxels sin conexión con el suelo: restos de
formas cuyos voxels de índice 241-255 (marcadores, descartados) los unían al resto, y atrezo apoyado en
superficies que al redondear su rotación queda un voxel en el aire. Como el juego ancla todo lo intacto al
cargar (regla "pristine"), esos trozos flotan hasta que se les dispara.

Para cada componente conexa (6-vecinos) que no toque un material ancla (terreno, tierra, suelo):
  * menos de MIN_VOXELS voxels  -> se borra (basura de la importación)
  * si no                        -> se deja caer voxel a voxel hasta que apoye en algo (máx. MAX_DROP);
                                    si no apoya en nada en ese recorrido, se borra.

Uso:  python fix_floaters.py <mapa.vxmap> [mapa_salida.vxmap]   (por defecto sobrescribe)
"""
import sys, struct, time
import numpy as np
from scipy import ndimage

MIN_VOXELS = 12
MAX_DROP = 60          # voxels (6 m a 10 cm)
CHUNK = 32


def read_vxmap(path):
    d = open(path, "rb").read()
    o = 0
    def rd(fmt):
        nonlocal o
        v = struct.unpack_from(fmt, d, o); o += struct.calcsize(fmt); return v
    assert d[:4] == b"VXMP"; o = 4
    rd("<I"); vs = rd("<f")[0]; ncx, ncy, ncz = rd("<iii"); rd("<fff")
    nmat = rd("<H")[0]
    mats = [rd("<BBBBHBBB") for _ in range(nmat)]
    nsp = rd("<H")[0]; o += 16 * nsp
    header = d[:o]                       # cabecera intacta (hasta nChunks)
    nch = rd("<I")[0]
    X, Y, Z = ncx * CHUNK, ncy * CHUNK, ncz * CHUNK
    vol = np.zeros((X, Y, Z), np.uint8)
    for _ in range(nch):
        idx, nruns = rd("<II")
        runs = np.frombuffer(d, dtype=np.dtype([("l", "<u2"), ("v", "u1")]), count=nruns, offset=o); o += 3 * nruns
        flat = np.repeat(runs["v"], runs["l"])
        cx = idx % ncx; cy = (idx // ncx) % ncy; cz = idx // (ncx * ncy)
        vol[cx * CHUNK:(cx + 1) * CHUNK, cy * CHUNK:(cy + 1) * CHUNK, cz * CHUNK:(cz + 1) * CHUNK] = flat.reshape(CHUNK, CHUNK, CHUNK).transpose(2, 1, 0)
    return header, (ncx, ncy, ncz), vs, mats, vol


def write_vxmap(path, header, dims, vol):
    ncx, ncy, ncz = dims
    out = [header]
    chunks = []
    for cz in range(ncz):
        for cy in range(ncy):
            for cx in range(ncx):
                blk = vol[cx * CHUNK:(cx + 1) * CHUNK, cy * CHUNK:(cy + 1) * CHUNK, cz * CHUNK:(cz + 1) * CHUNK]
                if not blk.any():
                    continue
                flat = blk.transpose(2, 1, 0).ravel()
                # RLE
                change = np.flatnonzero(np.diff(flat.astype(np.int16))) + 1
                starts = np.concatenate([[0], change]); ends = np.concatenate([change, [flat.size]])
                runs = []
                for s, e in zip(starts, ends):
                    v = int(flat[s]); n = int(e - s)
                    while n > 65535:
                        runs.append((65535, v)); n -= 65535
                    runs.append((n, v))
                idx = cx + ncx * (cy + ncy * cz)
                chunks.append(struct.pack("<II", idx, len(runs)) + b"".join(struct.pack("<HB", l, v) for l, v in runs))
    out.append(struct.pack("<I", len(chunks)))
    out.extend(chunks)
    open(path, "wb").write(b"".join(out))


def main():
    src = sys.argv[1]; dst = sys.argv[2] if len(sys.argv) > 2 else src
    t0 = time.time()
    header, dims, vs, mats, vol = read_vxmap(src)
    print("leído %s: %dx%dx%d voxels de %.2f m, sólidos %d (%.1f s)" % (src, *vol.shape, vs, int((vol > 0).sum()), time.time() - t0))
    if vol.size > 500_000_000:
        print("  mapa grande (%.0f M celdas): etiquetado a resolución mitad" % (vol.size / 1e6))
        main_big(src, dst, header, dims, vs, mats, vol, t0)
        return
    anchor_ids = [16 + i for i, m in enumerate(mats) if m[5] & 1]      # flag MF_ANCHOR
    lab, n = ndimage.label(vol > 0)
    anchored = set(np.unique(lab[np.isin(vol, anchor_ids)]).tolist())
    anchored.discard(0)
    sizes = np.bincount(lab.ravel())
    objs = ndimage.find_objects(lab)
    solid = vol > 0
    removed = settled = kept = 0; removed_vox = 0
    max_drop_vox = int(round(MAX_DROP * 0.1 / vs))
    for k in range(1, n + 1):
        if k in anchored:
            continue
        sl = objs[k - 1]
        if sl is None:
            continue
        comp = (lab[sl] == k)
        size = int(sizes[k])
        if size < MIN_VOXELS:
            vol[sl][comp] = 0; solid[sl][comp] = False
            removed += 1; removed_vox += size
            continue
        # dejar caer: buscar el primer dy con el que la pieza desplazada choca con algo (o con el suelo y=0)
        coords = np.argwhere(comp)
        vals = vol[sl][comp]
        x0, y0, z0 = sl[0].start, sl[1].start, sl[2].start
        gx = coords[:, 0] + x0; gy = coords[:, 1] + y0; gz = coords[:, 2] + z0
        # la pieza deja de existir mientras se prueba (no chocar consigo misma)
        vol[sl][comp] = 0; solid[sl][comp] = False
        land = -1
        for dy in range(1, max_drop_vox + 1):
            ny = gy - dy
            if (ny < 0).any() or solid[gx, ny, gz].any():
                land = dy - 1
                break
        if land < 0:
            removed += 1; removed_vox += size
            continue
        ny = gy - land
        vol[gx, ny, gz] = vals; solid[gx, ny, gz] = True
        if land == 0:
            kept += 1      # ya tocaba algo por debajo (contacto sin conexión de 6 vecinos, p. ej. cristal)
        else:
            settled += 1
    print("componentes sin ancla: %d -> borradas %d (%d voxels), asentadas %d, ya apoyadas %d (%.1f s)" % (
        n - len(anchored), removed, removed_vox, settled, kept, time.time() - t0))
    write_vxmap(dst, header, dims, vol)
    print("escrito %s (%.1f s)" % (dst, time.time() - t0))




def main_big(src, dst, header, dims, vs, mats, vol, t0):
    """Mapas de cientos de millones de celdas (no cabe el etiquetado denso en RAM): se etiqueta por losas en X
    y se unen las componentes entre losas con union-find. Con memoria acotada sólo se BORRAN los fragmentos
    sin ancla pequeños (< MIN_BIG voxels: basura de la importación que al primer daño sale en cientos de
    piezas); lo grande sin apoyo se deja y cae en el juego cuando se daña su zona."""
    MIN_BIG = 40
    anchor_ids = np.array([16 + i for i, m in enumerate(mats) if m[5] & 1], dtype=np.uint8)
    X, Y, Z = vol.shape
    SLAB = 64
    slabs = list(range(0, X, SLAB))
    # pase 1: etiquetas por losa, tamaños, anclas y pares de frontera
    parent = {}
    def find(a):
        while parent.get(a, a) != a:
            parent[a] = parent.get(parent[a], parent[a]); a = parent[a]
        return a
    def unite(a, b):
        ra, rb = find(a), find(b)
        if ra != rb: parent[rb] = ra
    size = {}; anch = set()
    prev_plane = None; prev_si = None
    for si, x0 in enumerate(slabs):
        sub = vol[x0:x0 + SLAB]
        lab, n = ndimage.label(sub > 0)
        cnt = np.bincount(lab.ravel(), minlength=n + 1)
        for k in range(1, n + 1):
            size[(si, k)] = int(cnt[k])
        a_lab = np.unique(lab[np.isin(sub, anchor_ids) | (np.arange(Y)[None, :, None] == 0)])
        for k in a_lab.tolist():
            if k: anch.add((si, k))
        if prev_plane is not None:
            cur = lab[0]
            m = (prev_plane > 0) & (cur > 0)
            pairs = np.unique(np.stack([prev_plane[m], cur[m]], 1), axis=0) if m.any() else np.zeros((0, 2), np.int64)
            for a, b in pairs.tolist():
                unite((prev_si, int(a)), (si, int(b)))
        prev_plane = lab[-1].copy(); prev_si = si
        del lab
        if si % 8 == 0:
            print("  losa %d/%d (%.1f s)" % (si + 1, len(slabs), time.time() - t0))
    roots_anch = set(find(a) for a in anch)
    root_size = {}
    for key, n in size.items():
        r = find(key); root_size[r] = root_size.get(r, 0) + n
    # pase 2: borrar fragmentos sin ancla pequeños
    removed = 0; removed_vox = 0; big_floaters = 0
    counted = set()
    for si, x0 in enumerate(slabs):
        sub = vol[x0:x0 + SLAB]
        lab, n = ndimage.label(sub > 0)
        kill = np.zeros(n + 1, dtype=bool)
        for k in range(1, n + 1):
            r = find((si, k))
            if r in roots_anch: continue
            if root_size[r] < MIN_BIG:
                kill[k] = True
                if r not in counted: counted.add(r); removed += 1; removed_vox += root_size[r]
            elif r not in counted:
                counted.add(r); big_floaters += 1
        if kill.any():
            sub[kill[lab]] = 0
        del lab
    print("componentes sin ancla: %d -> borradas %d (%d voxels); %d grandes sin apoyo se dejan (caen al dañarlas) (%.1f s)" % (
        removed + big_floaters, removed, removed_vox, big_floaters, time.time() - t0))
    write_vxmap(dst, header, dims, vol)
    print("escrito %s (%.1f s)" % (dst, time.time() - t0))


if __name__ == "__main__":
    main()
