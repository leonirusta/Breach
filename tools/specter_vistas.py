"""SPECTER: lee la LAMINA TECNICA (las cuatro vistas del "MODELO EN VOXELS") y la pasa a rejillas de bloques.

Cada vista se recorta, se separa del fondo negro (y de las rayas de la cuadricula), se mide (de la coronilla a la suela =
86 voxels del soldado) y se divide en bloques de 2 voxels del soldado (unos 7 pixeles de la lamina, el tamaño de los
bloques de la foto). Cada bloque se queda con el color mediano de sus pixeles, pasado a la PALETA DE LA PROPIA FOTO (los
colores que mas salen, por k-medias). Lo usa tools/make_specter.py; con --ver deja las rejillas en grande para mirarlas.

Uso:  python tools/specter_vistas.py --ver=<carpeta>
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAMINA = os.path.join(RAIZ, "tools", "referencias", "specter_tecnica.jpg")

# las cuatro vistas en la lamina (x0, y0, x1, y1), con margen
CAJAS = {"frente": (100, 110, 320, 452), "espalda": (520, 110, 740, 452),
         "izquierda": (120, 476, 320, 832), "derecha": (540, 476, 740, 832)}
ALTO = 86.0          # de la suela (-2) a la coronilla (84), en voxels del soldado
SUELA = -2.0
CELDA = 2.0          # el bloque: 2 voxels del soldado
FONDO = 24           # por debajo de esto (el maximo de r, g, b) es fondo


def cargar():
    return Image.open(LAMINA).convert("RGB")


def mascara(a):
    """Lo que es personaje: mas claro que el fondo negro, sin las rayas finas de la cuadricula (una apertura de 3x3) y
    con los huecos de dentro rellenos (el negro de la armadura puede bajar del umbral)."""
    m = a.max(axis=2) > FONDO
    img = Image.fromarray((m * 255).astype(np.uint8))
    img = img.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))      # fuera las rayas
    img = img.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))      # tapar los agujeros
    m = np.asarray(img) > 127
    # rellenar lo que quede encerrado fila a fila (entre el primer y el ultimo pixel de la fila, si el hueco es corto)
    out = m.copy()
    for y in range(m.shape[0]):
        xs = np.where(m[y])[0]
        if len(xs) < 2:
            continue
        fila = m[y]
        x = xs[0]
        while x < xs[-1]:
            if not fila[x]:
                x1 = x
                while x1 < xs[-1] and not fila[x1]:
                    x1 += 1
                if x1 - x <= 6:
                    out[y, x:x1] = True
                x = x1
            else:
                x += 1
    return mayor_trozo(out)


def mayor_trozo(m):
    """Solo la figura: el trozo conectado mas grande (fuera las rayas de los rotulos y los restos de la cuadricula)"""
    h, w = m.shape
    visto = np.zeros_like(m, dtype=bool)
    mejor = None
    for y0 in range(h):
        for x0 in range(w):
            if not m[y0, x0] or visto[y0, x0]:
                continue
            pila, trozo = [(y0, x0)], []
            visto[y0, x0] = True
            while pila:
                y, x = pila.pop()
                trozo.append((y, x))
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < h and 0 <= xx < w and m[yy, xx] and not visto[yy, xx]:
                        visto[yy, xx] = True
                        pila.append((yy, xx))
            if mejor is None or len(trozo) > len(mejor):
                mejor = trozo
    out = np.zeros_like(m, dtype=bool)
    for y, x in mejor or []:
        out[y, x] = True
    return out


def medir(m):
    """La coronilla, la suela, la escala (pixeles por voxel) y el centro de la cabeza"""
    filas = np.where(m.any(axis=1))[0]
    arriba, abajo = int(filas[0]), int(filas[-1]) + 1
    s = (abajo - arriba) / ALTO
    # el centro: el de la cabeza (las filas del primer 15 % de la altura)
    cab = m[arriba:arriba + int((abajo - arriba) * 0.15)]
    cols = np.where(cab.any(axis=0))[0]
    centro = (cols[0] + cols[-1] + 1) / 2.0
    return arriba, abajo, s, centro


def rejilla(vista, im=None):
    """{ (i, j): (r, g, b) } con i = columna de bloques (0 = el centro de la cabeza, + a la derecha de la imagen) y j la
    fila (0 = la de la suela). Y la escala, por si hace falta."""
    im = im or cargar()
    a = np.asarray(im.crop(CAJAS[vista])).astype(np.int32)
    m = mascara(a)
    arriba, abajo, s, centro = medir(m)
    paso = CELDA * s
    out = {}
    nj = int(round(ALTO / CELDA))
    ni = int(m.shape[1] / paso) + 2
    for j in range(nj):
        y1 = abajo - j * paso
        y0 = y1 - paso
        for i in range(-ni, ni + 1):
            x0 = centro + (i - 0.5) * paso
            x1 = x0 + paso
            ya, yb = int(round(y0)), int(round(y1))
            xa, xb = int(round(x0)), int(round(x1))
            if xb <= 0 or xa >= m.shape[1] or yb <= 0 or ya >= m.shape[0]:
                continue
            xa, ya = max(xa, 0), max(ya, 0)
            sub = m[ya:yb, xa:xb]
            if sub.size == 0 or sub.mean() < 0.5:
                continue
            # el color: el mediano del centro del bloque (los bordes se mezclan con el vecino)
            ca, cb = (ya + yb) // 2, (xa + xb) // 2
            r = 2
            px = a[max(ca - r, 0):ca + r + 1, max(cb - r, 0):cb + r + 1].reshape(-1, 3)
            out[(i, j)] = tuple(int(v) for v in np.median(px, axis=0))
    return out, s


def paleta(rejillas, k=10, iters=30):
    """Los k colores de la foto (k-medias sobre todos los bloques)"""
    pts = np.array([c for r in rejillas for c in r.values()], dtype=np.float64)
    rng = np.random.default_rng(7)
    cent = pts[rng.choice(len(pts), k, replace=False)]
    for _ in range(iters):
        d = ((pts[:, None, :] - cent[None, :, :]) ** 2).sum(axis=2)
        lab = d.argmin(axis=1)
        for q in range(k):
            if (lab == q).any():
                cent[q] = pts[lab == q].mean(axis=0)
    return [tuple(int(round(v)) for v in c) for c in cent]


def a_paleta(col, pal):
    d = [sum((col[t] - p[t]) ** 2 for t in range(3)) for p in pal]
    return pal[int(np.argmin(d))]


def calido(c):
    """La PIEL de la cara y las manos: tonos calidos (el rojo bastante por encima del azul)"""
    return c[0] - c[2] > 22


def todas():
    im = cargar()
    rs = {v: rejilla(v, im)[0] for v in CAJAS}
    # dos paletas: la de la armadura (grises) y la de la piel, que si no se la comen los grises
    fria = [{k: c for k, c in r.items() if not calido(c)} for r in rs.values()]
    tibia = [{k: c for k, c in r.items() if calido(c)} for r in rs.values()]
    pal = paleta(fria, 11) + paleta(tibia, 3)
    pf, pt = pal[:11], pal[11:]
    for v in rs:
        rs[v] = {k: a_paleta(c, pt if calido(c) else pf) for k, c in rs[v].items()}
    return rs, pal


def main():
    dest = None
    for a in sys.argv[1:]:
        if a.startswith("--ver="):
            dest = a[6:]
    rs, pal = todas()
    print("paleta:", pal)
    for v, r in rs.items():
        js = [j for _, j in r]
        print("%s: %d bloques, filas %d..%d" % (v, len(r), min(js), max(js)))
        if dest:
            os.makedirs(dest, exist_ok=True)
            i0 = min(i for i, _ in r)
            i1 = max(i for i, _ in r)
            w, h = i1 - i0 + 1, max(js) + 1
            img = Image.new("RGB", (w, h), (0, 0, 0))
            for (i, j), c in r.items():
                img.putpixel((i - i0, h - 1 - j), c)
            img.resize((w * 16, h * 16), Image.NEAREST).save(os.path.join(dest, "rejilla_%s.png" % v))


if __name__ == "__main__":
    main()
