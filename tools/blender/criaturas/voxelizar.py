"""Criaturas de VOXELS a partir de las formas de organico.Pieza (elipsoides y capsulas).

Se calcula con numpy la distancia a la forma mas cercana en una rejilla de voxels: dentro (<0) es
solido, y el voxel toma el color, el brillo y el hueso de esa forma. La piel se arruga moviendo la
superficie con ruido (menos de un voxel). Cada hueso tiene su propia malla colgada de el, como el
soldado: la mandibula, los dientes y los colmillos se mueven solos y la boca se abre de verdad.
"""
import bpy
import numpy as np
from mathutils import Matrix, Vector

# esquinas de cada cara, en orden antihorario visto desde fuera: +X, -X, +Y, -Y, +Z, -Z
_ESQ = np.array([
    [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)], [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)],
    [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)], [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)],
    [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)], [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)],
], dtype=np.float32)
_DIRS = [(0, 1), (0, -1), (1, 1), (1, -1), (2, 1), (2, -1)]


def _caja(f):
    if f.tipo == "elip":
        c, r, _ = f.d
        e = max(r)
        return np.array(c) - e, np.array(c) + e
    a, b, ra, rb = f.d
    e = max(ra, rb)
    return np.minimum(np.array(a), np.array(b)) - e, np.maximum(np.array(a), np.array(b)) + e


def _distancia(f, X, Y, Z):
    if f.tipo == "elip":
        c, r, inv = f.d
        m = np.array(inv, dtype=np.float32)
        px, py, pz = X - c.x, Y - c.y, Z - c.z
        qx = m[0, 0] * px + m[0, 1] * py + m[0, 2] * pz
        qy = m[1, 0] * px + m[1, 1] * py + m[1, 2] * pz
        qz = m[2, 0] * px + m[2, 1] * py + m[2, 2] * pz
        return (np.sqrt((qx / r.x) ** 2 + (qy / r.y) ** 2 + (qz / r.z) ** 2) - 1.0) * min(r)
    a, b, ra, rb = f.d
    ab = b - a
    L2 = max(ab.length_squared, 1e-9)
    t = np.clip(((X - a.x) * ab.x + (Y - a.y) * ab.y + (Z - a.z) * ab.z) / L2, 0.0, 1.0)
    dx, dy, dz = X - (a.x + ab.x * t), Y - (a.y + ab.y * t), Z - (a.z + ab.z * t)
    return np.sqrt(dx * dx + dy * dy + dz * dz) - (ra + (rb - ra) * t)


def _ruido_valor(P, celda):
    """ruido de valor 3D suave (-1..1): valores al azar en una rejilla de `celda` metros, interpolados"""
    g = P / celda
    i = np.floor(g).astype(np.int64)
    f = g - i
    f = f * f * (3.0 - 2.0 * f)

    def h(dx, dy, dz):
        v = ((i[:, 0] + dx) * 73856093) ^ ((i[:, 1] + dy) * 19349663) ^ ((i[:, 2] + dz) * 83492791)
        v = (v ^ (v >> 13)) * 1274126177
        return ((v ^ (v >> 16)) & 1023).astype(np.float32) / 511.5 - 1.0

    x0 = h(0, 0, 0) * (1 - f[:, 0]) + h(1, 0, 0) * f[:, 0]
    x1 = h(0, 1, 0) * (1 - f[:, 0]) + h(1, 1, 0) * f[:, 0]
    x2 = h(0, 0, 1) * (1 - f[:, 0]) + h(1, 0, 1) * f[:, 0]
    x3 = h(0, 1, 1) * (1 - f[:, 0]) + h(1, 1, 1) * f[:, 0]
    y0 = x0 * (1 - f[:, 1]) + x1 * f[:, 1]
    y1 = x2 * (1 - f[:, 1]) + x3 * f[:, 1]
    return y0 * (1 - f[:, 2]) + y1 * f[:, 2]


def _lin(c):
    c = np.asarray(c, dtype=np.float32)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def voxelizar(piezas, vox, rig, col, huesos_cuerpo, arrugas=0.7, material=None):
    """piezas: [(Pieza, hueso)]; hueso None = cada voxel al hueso de huesos_cuerpo mas cercano.
    Devuelve (objetos, caras)."""
    formas = [(f, pi) for pi, (p, _h) in enumerate(piezas) for f in p.formas]
    lo = np.min([_caja(f)[0] for f, _ in formas], axis=0) - 2 * vox
    hi = np.max([_caja(f)[1] for f, _ in formas], axis=0) + 2 * vox
    org = np.floor(lo / vox) * vox
    n = (np.ceil((hi - org) / vox).astype(int) + 1)
    mejor = np.full(n, np.inf, dtype=np.float32)
    cual = np.full(n, -1, dtype=np.int16)
    for fi, (f, _pi) in enumerate(formas):
        a, b = _caja(f)
        i0 = np.clip(np.floor((a - org) / vox).astype(int), 0, n - 1)
        i1 = np.clip(np.ceil((b - org) / vox).astype(int) + 1, 1, n)
        ax = [org[k] + (np.arange(i0[k], i1[k], dtype=np.float32) + 0.5) * vox for k in range(3)]
        X, Y, Z = np.meshgrid(ax[0], ax[1], ax[2], indexing='ij')
        d = _distancia(f, X, Y, Z).astype(np.float32)
        s = (slice(i0[0], i1[0]), slice(i0[1], i1[1]), slice(i0[2], i1[2]))
        m = d < mejor[s]
        mejor[s][m] = d[m]
        cual[s][m] = fi
    # PRIORIDAD: ojos, pupilas y parpados se quedan con sus voxels aunque esten metidos en el craneo (por
    # la forma mas cercana ganaba el craneo, que es mas grande, y los ojos no se veian)
    for fi in sorted(range(len(formas)), key=lambda k: formas[k][0].prio):
        f = formas[fi][0]
        if f.prio <= 0:
            continue
        a, b = _caja(f)
        i0 = np.clip(np.floor((a - org) / vox).astype(int), 0, n - 1)
        i1 = np.clip(np.ceil((b - org) / vox).astype(int) + 1, 1, n)
        ax = [org[k] + (np.arange(i0[k], i1[k], dtype=np.float32) + 0.5) * vox for k in range(3)]
        X, Y, Z = np.meshgrid(ax[0], ax[1], ax[2], indexing='ij')
        d = _distancia(f, X, Y, Z).astype(np.float32)
        s = (slice(i0[0], i1[0]), slice(i0[1], i1[1]), slice(i0[2], i1[2]))
        m = d < 0.0
        mejor[s][m] = np.minimum(mejor[s][m], -vox * 2.0)
        cual[s][m] = fi
    # arrugas: la superficie se mueve con ruido (solo cerca de la piel). RUIDO DE VALOR, no senos: con
    # senos salian franjas diagonales por todo el cuerpo, como una cebra.
    cand = np.argwhere(mejor < vox * 1.5)
    P = org + (cand.astype(np.float32) + 0.5) * vox
    ruido = 0.65 * _ruido_valor(P, 0.32) + 0.35 * _ruido_valor(P, 0.11)
    dentro = mejor[cand[:, 0], cand[:, 1], cand[:, 2]] - ruido * vox * arrugas < 0.0
    solido = np.zeros(n, dtype=bool)
    solido[mejor < -vox * 1.5] = True
    c2 = cand[dentro]
    solido[c2[:, 0], c2[:, 1], c2[:, 2]] = True
    celdas = np.argwhere(solido)
    # color, brillo y hueso de cada voxel
    ids = cual[celdas[:, 0], celdas[:, 1], celdas[:, 2]]
    colores = np.array([f.color for f, _ in formas], dtype=np.float32)
    brillos = np.array([f.brillo for f, _ in formas], dtype=np.float32)
    pieza_de = np.array([pi for _, pi in formas], dtype=np.int32)
    h = (celdas[:, 0].astype(np.int64) * 73856093) ^ (celdas[:, 1].astype(np.int64) * 19349663) \
        ^ (celdas[:, 2].astype(np.int64) * 83492791)
    # manchas grandes y suaves de la piel + un pelo de variacion por voxel
    manchas = _ruido_valor(centros_todos := org + (celdas.astype(np.float32) + 0.5) * vox, 0.45)
    tono = 0.92 + 0.08 * ((h ^ (h >> 13)) & 1023).astype(np.float32) / 1023.0 + 0.14 * manchas
    col_vox = np.clip(colores[ids] * tono[:, None], 0.0, 1.0)
    bri_vox = brillos[ids]
    nombres = []
    hueso_vox = np.zeros(len(celdas), dtype=np.int32)
    centros = org + (celdas.astype(np.float32) + 0.5) * vox
    bones = rig.data.bones
    for pi, (_p, hueso) in enumerate(piezas):
        sel = pieza_de[ids] == pi
        if hueso is not None:
            if hueso not in nombres:
                nombres.append(hueso)
            hueso_vox[sel] = nombres.index(hueso)
            continue
        pts = centros[sel]
        dist = []
        for hn in huesos_cuerpo:
            if hn not in nombres:
                nombres.append(hn)
            a, b = np.array(bones[hn].head_local), np.array(bones[hn].tail_local)
            ab = b - a
            t = np.clip(((pts - a) @ ab) / max(float(ab @ ab), 1e-9), 0.0, 1.0)
            dist.append(np.linalg.norm(pts - (a + t[:, None] * ab), axis=1))
        cerca = np.argmin(np.array(dist), axis=0)
        hueso_vox[sel] = np.array([nombres.index(huesos_cuerpo[k]) for k in range(len(huesos_cuerpo))])[cerca]
    # indice de voxel por celda, para mirar vecinos
    indice = np.full(n, -1, dtype=np.int32)
    indice[celdas[:, 0], celdas[:, 1], celdas[:, 2]] = np.arange(len(celdas), dtype=np.int32)
    # CARAS CONTRA EL AIRE *Y CONTRA OTRO HUESO*. Cortando solo contra el aire, la malla de cada hueso
    # queda ABIERTA justo por donde se junta con la vecina (ahi no hay cara: el vecino es solido). En
    # reposo no se nota, pero al animar los huesos se separan un pelo y SE VE EL INTERIOR del bicho:
    # piezas que parecen transparentes y trozos que aparecen y desaparecen al moverse. Cerrando cada
    # pieza por su costura, cada una es un solido estanco. Cuesta unos triangulos mas, solo los del
    # corte, y a cambio el cuerpo ya no tiene agujeros se mueva como se mueva.
    hgrid = np.full(n, -1, dtype=np.int32)
    hgrid[celdas[:, 0], celdas[:, 1], celdas[:, 2]] = hueso_vox
    caras_celda, caras_dir = [], []
    for di, (eje, s) in enumerate(_DIRS):
        vecino_h = np.full(n, -1, dtype=np.int32)
        src = [slice(None)] * 3
        dst = [slice(None)] * 3
        if s > 0:
            src[eje], dst[eje] = slice(1, None), slice(0, -1)
        else:
            src[eje], dst[eje] = slice(0, -1), slice(1, None)
        vecino_h[tuple(dst)] = hgrid[tuple(src)]
        fc = np.argwhere(solido & (vecino_h != hgrid))
        caras_celda.append(fc)
        caras_dir.append(np.full(len(fc), di, dtype=np.int8))
    fc = np.concatenate(caras_celda)
    fd = np.concatenate(caras_dir)
    fv = indice[fc[:, 0], fc[:, 1], fc[:, 2]]
    objetos = []
    for hi_, hn in enumerate(nombres):
        sel = hueso_vox[fv] == hi_
        if not np.any(sel):
            continue
        celda, dirs, vx = fc[sel], fd[sel], fv[sel]
        nf = len(celda)
        verts = ((celda[:, None, :].astype(np.float32) + _ESQ[dirs]) * vox + org).reshape(-1, 3).astype(np.float32)
        me = bpy.data.meshes.new("V_" + hn)
        me.vertices.add(nf * 4)
        me.vertices.foreach_set("co", verts.ravel())
        me.loops.add(nf * 4)
        me.loops.foreach_set("vertex_index", np.arange(nf * 4, dtype=np.int32))
        me.polygons.add(nf)
        me.polygons.foreach_set("loop_start", np.arange(0, nf * 4, 4, dtype=np.int32))
        me.update(calc_edges=True)
        ca = me.color_attributes.new("Col", 'FLOAT_COLOR', 'CORNER')
        rgba = np.concatenate([_lin(col_vox[vx]), np.ones((nf, 1), dtype=np.float32)], axis=1)
        ca.data.foreach_set("color", np.repeat(rgba, 4, axis=0).ravel())
        me.color_attributes.active_color = ca
        br = me.attributes.new("Brillo", 'FLOAT', 'FACE')
        br.data.foreach_set("value", bri_vox[vx])
        if material:
            me.materials.append(material)
        ob = bpy.data.objects.new("V_" + hn, me)
        col.objects.link(ob)
        b = bones[hn]
        ob.parent, ob.parent_type, ob.parent_bone = rig, 'BONE', hn
        ob.matrix_parent_inverse = (b.matrix_local @ Matrix.Translation((0, b.length, 0))).inverted()
        objetos.append(ob)
    return objetos, int(len(fc))
