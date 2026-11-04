"""COMPROBACIONES del mapa CAFETERIA URBANA sobre el volumen de 20 cm (el que se juega), sin abrir Godot.

1. FLOTANTES: componentes conexas por caras (6 vecinos) que no tocan ningun material ancla. docs/10: objetivo 0
   conjuntos de 100 voxels o mas (y mejor 0 del todo: este mapa no se carga con soldadura).
2. NAVEGACION: el A* de core/src/vx_nav.cpp a 20 cm (celda de 2 voxels = 0,4 m, agente de 9 voxels = 1,8 m, sube 4 =
   0,8 m, baja 15 = 3 m, 8 vecinos sin cortar esquinas). Desde las dos bases del duelo se recorre lo alcanzable y se
   comprueba cada punto de salida.
3. PUNTOS DE SALIDA: suelo debajo, 2 m libres encima, nada en 0,5 m alrededor y alcanzables desde las bases.
"""
import math
from collections import deque
import numpy as np
from scipy import ndimage

VS = 0.2
CELDA, AGENTE, SUBE, BAJA = 2, 9, 4, 15


def flotantes(vol, ancla_ids, minimo=1):
    """[(voxels, (x, y, z) centro en m, (x0,y0,z0,x1,y1,z1) caja en m, ids de material)] de mayor a menor."""
    solido = vol != 0
    etiq, n = ndimage.label(solido, structure=ndimage.generate_binary_structure(3, 1))
    ancla = np.isin(vol, np.asarray(sorted(ancla_ids), dtype=vol.dtype))
    con_ancla = np.unique(etiq[ancla])
    tam = np.bincount(etiq.ravel(), minlength=n + 1)
    sueltos = np.setdiff1d(np.arange(1, n + 1), con_ancla)
    out = []
    if sueltos.size == 0:
        return out
    objs = ndimage.find_objects(etiq)
    for e in sueltos:
        if tam[e] < minimo:
            continue
        sl = objs[e - 1]
        sub = etiq[sl] == e
        idx = np.argwhere(sub)
        c = idx.mean(axis=0) + [s.start for s in sl]
        mats = np.unique(vol[sl][sub])
        caja = tuple(round(v * VS, 2) for v in (sl[0].start, sl[1].start, sl[2].start, sl[0].stop, sl[1].stop, sl[2].stop))
        out.append((int(tam[e]), tuple(round((v + 0.5) * VS, 2) for v in c), caja, [int(m) for m in mats]))
    out.sort(key=lambda t: -t[0])
    return out


class Nav:
    def __init__(self, vol):
        solido = vol != 0
        X, Y, Z = solido.shape
        cx, cz = X // CELDA, Z // CELDA
        s = solido[:cx * CELDA, :, :cz * CELDA].reshape(cx, CELDA, Y, cz, CELDA)
        algun = s.any(axis=(1, 4))            # (cx, Y, cz): algun voxel solido en la celda a esa altura
        cs = np.cumsum(algun, axis=1, dtype=np.int32)
        arriba = cs[:, np.minimum(np.arange(Y) + AGENTE, Y - 1), :] - cs
        self.pisable = algun & (arriba == 0)
        self.Y = Y
        self.niveles = {}
        xs, ys, zs = np.nonzero(self.pisable)
        for x, y, z in zip(xs.tolist(), ys.tolist(), zs.tolist()):
            self.niveles.setdefault((x, z), []).append(y)
        for k in self.niveles:
            self.niveles[k].sort()
        self.visit = set()

    def _vecino(self, cx, cz, y):
        lv = self.niveles.get((cx, cz))
        if not lv:
            return -1
        mejor = -1
        for v in lv:
            if v > y + SUBE:
                break
            if v >= y - BAJA:
                mejor = v
        return mejor

    def celda_de(self, x, y, z):
        cx, cz = int(x / (VS * CELDA)), int(z / (VS * CELDA))
        pies = int(math.floor(y / VS + 1e-6))
        lv = [v for v in self.niveles.get((cx, cz), []) if pies - 3 <= v + 1 <= pies + 3]
        if not lv:
            return None
        return (cx, cz, min(lv, key=lambda v: abs(v + 1 - pies)))

    def recorrer(self, desde):
        dirs = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1))
        cola = deque()
        for p in desde:
            c = self.celda_de(*p)
            if c and c not in self.visit:
                self.visit.add(c)
                cola.append(c)
        while cola:
            cx, cz, y = cola.popleft()
            for dx, dz in dirs:
                ny = self._vecino(cx + dx, cz + dz, y)
                if ny < 0:
                    continue
                if dx and dz:
                    ya, yb = self._vecino(cx + dx, cz, y), self._vecino(cx, cz + dz, y)
                    if ya < 0 or yb < 0 or abs(ya - y) > SUBE or abs(yb - y) > SUBE:
                        continue
                k = (cx + dx, cz + dz, ny)
                if k not in self.visit:
                    self.visit.add(k)
                    cola.append(k)
        return len(self.visit)

    def alcanzable(self, x, y, z):
        c = self.celda_de(x, y, z)
        return c is not None and c in self.visit

    def planta_png(self, ruta, vol_top_rgb=None):
        """Mapa de navegacion: gris lo pisable, verde lo alcanzable."""
        X, Z = self.pisable.shape[0], self.pisable.shape[2]
        img = np.zeros((Z, X, 3), np.uint8)
        for (cx, cz), lv in self.niveles.items():
            img[cz, cx] = (70, 70, 70)
        for (cx, cz, y) in self.visit:
            img[cz, cx] = (60, 200, 90) if y < 12 else (60, 140, 230)
        from PIL import Image
        Image.fromarray(img).resize((X * 3, Z * 3), Image.NEAREST).save(ruta)


def salida_ok(vol, x, y, z):
    """Suelo debajo, 2 m libres encima y 0,5 m alrededor."""
    ix, iz = int(x / VS), int(z / VS)
    iy = int(round(y / VS))
    if not (0 <= ix < vol.shape[0] and 0 <= iz < vol.shape[2]):
        return False, "fuera"
    col = vol[ix, :iy, iz]
    if not (col[max(0, iy - 2):iy] != 0).any():
        return False, "sin suelo"
    caja = vol[max(0, ix - 2):ix + 3, iy:iy + 10, max(0, iz - 2):iz + 3]
    if (caja != 0).any():
        return False, "algo encima o al lado"
    return True, "ok"
