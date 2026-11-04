"""PINTURA Y RASTERIZADO del mapa CAFETERIA URBANA.

Lo distinto del kit de siempre (tools/mapa_pve/raster.py):

1. CADA RESOLUCION SE RASTERIZA POR SU CUENTA. El kit hace el mapa de 10 cm y saca el de 20 cm reduciendo (el voxel
   de 20 cm se queda con uno de sus 8 hijos, que a veces es uno de DENTRO del muro y sin dibujo). Pero el juego carga
   el de 20 cm tambien en PC: aqui las primitivas se pasan dos veces, a 10 y a 20 cm, y los dibujos se calculan en la
   rejilla de cada una. Un ladrillo con su junta a 10 cm; a 20 cm la junta no cabe y cada pieza va de su tono.
2. SE PINTA TODO EL VOLUMEN, no solo lo que se ve. Si una explosion arranca el revoque, detras sale ladrillo CON
   dibujo (la lamina: "se destruye el revoque y los ladrillos"). El mapa es pequeño y el RLE lo paga sin notarse.

Los dibujos (codigos en materiales.py). X, Y, Z son indices de voxel de la resolucion que se pinta; f es 1 a 10 cm
y 2 a 20 cm. U = X + Z sirve de coordenada horizontal en cualquier fachada.
"""
import math
import zlib
import numpy as np
import raster as R          # tools/mapa_pve/raster.py: preparar, rasterizar_baldosa, _trocear, textura_variacion
import materiales as M

CHUNK = 32


def _hash(a, b):
    return ((a * 73856093) ^ (b * 19349663) ^ ((a + b) * 83492791)) & 0x7fffffff


def patron(cod, X, Y, Z, k, ruido, f):
    """Indice de color (0..k-1) de cada voxel segun el dibujo de su material."""
    U = X + Z
    k = k.astype(np.int64)
    sucio = ruido >= 3
    if cod == M.LADRILLO:
        # colores: 6 tonos de pieza, junta, mugre
        nt = np.maximum(1, k - 2)
        if f == 1:
            # hiladas de 30 cm: dos filas de pieza y una de mortero; piezas de 40 cm y llaga de 10, a matajunta
            fila = Y // 3
            u = U + (fila & 1) * 2
            junta = ((Y % 3) == 2) | ((u % 5) == 4)
            out = _hash(u // 5, fila) % nt
            out = np.where(sucio & (_hash(u // 5, fila + 7) % 5 == 0), k - 1, out)
            out = np.where(junta, k - 2, out)
        else:
            # a 20 cm la junta no cabe: hiladas de un voxel, piezas de dos, a matajunta, cada una de su tono
            u = U + (Y & 1)
            out = _hash(u // 2, Y) % nt
            out = np.where(sucio & (_hash(u // 2, Y + 7) % 4 == 0), k - 1, out)
        return np.clip(out, 0, k - 1)
    if cod == M.SILLAR:
        nt = np.maximum(1, k - 2)
        if f == 1:
            fila = Y // 3
            u = U + (fila & 1) * 3
            junta = (Y % 3 == 0) | ((u % 6) == 0)
            out = _hash(u // 6, fila) % nt
            out = np.where(junta, k - 2, np.where(sucio, k - 1, out))
        else:
            fila = Y // 2
            u = U + (fila & 1) * 2
            junta = (Y % 2 == 0) & ((u % 3) == 0)
            out = _hash(u // 3, fila) % nt
            out = np.where(junta, k - 2, np.where(sucio & (out == 0), k - 1, out))
        return np.clip(out, 0, k - 1)
    if cod == M.REVOQUE:
        # base casi siempre, algo mas oscuro a manchas y la mugre solo en lo peor (chorretones)
        return np.clip(np.where(ruido >= 3, 2, np.where(ruido == 2, 1, 0)), 0, k - 1)
    if cod == M.TEJA:
        # canal y cobija alternos, cada hilada (un escalon) con su sombra, musgo en lo sucio
        if f == 1:
            out = (U // 2) & 1
            out = np.where((Y % 2) == 0, out + 2, out)
        else:
            out = U & 1
            out = np.where((Y & 1) == 0, out + 2, out)
        out = np.where(sucio & (_hash(U, Y) % 3 == 0), k - 1, out)
        return np.clip(out, 0, k - 1)
    if cod == M.BALDOSA:
        # baldosas de 40 cm a damero; a 10 cm con su llaga
        if f == 1:
            llaga = ((X % 4) == 0) | ((Z % 4) == 0)
            out = (X // 4 + Z // 4) & 1
            out = np.where((_hash(X // 4, Z // 4) % 7) == 0, 2, out)
            out = np.where(llaga, k - 1, out)
        else:
            out = (X // 2 + Z // 2) & 1
            out = np.where((_hash(X // 2, Z // 2) % 7) == 0, 2, out)
        return np.clip(out, 0, k - 1)
    if cod == M.LOSA_ACERA:
        # losas de acera de 60 x 40 cm; a 10 cm con junta
        if f == 1:
            junta = ((X % 6) == 0) | ((Z % 4) == 0)
            out = _hash(X // 6, Z // 4) % np.maximum(1, k - 1)
            out = np.where(junta, k - 1, out)
        else:
            out = _hash(X // 3, Z // 2) % np.maximum(1, k - 1)
        return np.clip(out, 0, k - 1)
    if cod == M.ADOQUIN:
        nt = np.maximum(1, k - 1)
        if f == 1:
            fila = Z // 3
            u = X + (fila & 1) * 2
            junta = ((Z % 3) == 0) | ((u % 4) == 0)
            out = np.where(junta, k - 1, _hash(u // 4, fila) % nt)
        else:
            u = X + (Z & 1)
            out = _hash(u // 2, Z) % nt
        return np.clip(out, 0, k - 1)
    if cod == M.RAYAS:
        return np.clip((U * f // 3) & 1, 0, k - 1)
    if cod == M.TABLAS:
        # tablones de 20 cm tumbados; en un suelo corren a lo largo de X (el indice es Z)
        nt = np.maximum(1, k - 1)
        idx = (Y + Z) * f
        if f == 1:
            ranura = (idx % 2) == 0
            out = _hash(idx // 2, X // 24) % nt
            out = np.where(ranura & ((_hash(idx, X // 24) & 3) == 0), k - 1, out)
        else:
            out = _hash(idx // 2, X // 12) % nt
        return np.clip(out, 0, k - 1)
    if cod == M.TABLAS_V:
        # tablas de puerta y postigo, de pie: el indice es U
        nt = np.maximum(1, k - 1)
        idx = U * f
        if f == 1:
            out = np.where((idx % 2) == 0, k - 1, _hash(idx // 2, 3) % nt)
        else:
            out = _hash(idx // 2, 3) % nt
        return np.clip(out, 0, k - 1)
    if cod == M.LAMAS:
        return np.clip(Y & 1, 0, k - 1)
    if cod == M.MAMPOSTERIA:
        # piedras irregulares: celdas de 40 x 30 cm desplazadas por un hash, junta clara alrededor (a 10 cm)
        nt = np.maximum(1, k - 1)
        if f == 1:
            fila = Y // 3
            desp = _hash(fila, 11) % 4
            u = U + desp
            ancho = 3 + (_hash(u // 4, fila) % 3)
            junta = ((Y % 3) == 0) | ((u % 4) == 0)
            out = np.where(junta & ((_hash(u, Y) % 3) != 0), k - 1, _hash(u // 4, fila) % nt)
            del ancho
        else:
            fila = Y // 2
            u = U + (_hash(fila, 11) % 3)
            out = _hash(u // 2, fila) % nt
        return np.clip(out, 0, k - 1)
    if cod == M.CESPED:
        return np.clip((ruido + (_hash(X * f // 3, Z * f // 3) & 1)) % k, 0, k - 1)
    if cod == M.VETA:
        return np.clip(_hash((Y * f) // 2, 5) % k, 0, k - 1)
    return np.clip(ruido % k, 0, k - 1)


# ---------------------------------------------------------------------------------------------------------------
# PALETA
# ---------------------------------------------------------------------------------------------------------------
# EL JUEGO AVIVA EL COLOR: el shader del mundo multiplica la saturacion x1,45 (main.COLOR_VIVO_MATERIAL) y el ambiente
# otro x1,12. Con los colores tal cual (los de la lamina) la madera salia naranja chillon y los arboles verde lima. Se
# le quita saturacion a la paleta para que EN PANTALLA quede como la lamina; lo que en la lamina ya es vivo (el rotulo,
# los toldos rojos, las flores, los grafitis, las luces) algo menos.
SATURACION = 0.62
SATURACION_VIVOS = 0.82
VIVOS = ("cartel_", "grafiti_", "flor_", "luz_", "toldo_rojo", "banderola", "chapa_bomberos", "piloto",
         "faro", "sombrilla_roja", "madera_puerta_roja")


def ajustar(c, nombre):
    s = SATURACION_VIVOS if nombre.startswith(VIVOS) else SATURACION
    lum = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    return tuple(int(max(0, min(255, round(lum + (v - lum) * s)))) for v in c)


def construir_paleta(usados, fisica, por_nombre):
    """(entradas, id_de, nvar, codigo, desp). Solo los materiales `usados`. Las entradas son las del .vxmap:
    R, G, B, fuerza, densidad, flags, soporte, masa."""
    entradas, id_de = [], {}
    nvar = np.ones(256, np.int64)
    codigo = np.zeros(256, np.int64)
    desp = np.zeros((256, 3), np.int64)
    for nombre in M.MATERIALES:
        if nombre not in usados:
            continue
        rgb, tipo = M.MATERIALES[nombre]
        fis = por_nombre.get(nombre) or fisica.get(tipo) or fisica["hormigon"]
        cols = M.colores(nombre)
        base = 16 + len(entradas)
        if base + len(cols) > 256:
            raise RuntimeError("paleta llena en %s (%d colores ya)" % (nombre, len(entradas)))
        id_de[nombre] = base
        for c in cols:
            c = ajustar(c, nombre)
            entradas.append((c[0], c[1], c[2]) + tuple(fis))
        nvar[base] = len(cols)
        if nombre in M.PATRONES:
            codigo[base] = M.PATRONES[nombre][0]
        h = zlib.crc32(nombre.encode("utf-8"))
        desp[base] = (h % 64, (h >> 6) % 64, (h >> 12) % 64)
    return entradas, id_de, nvar, codigo, desp


# ---------------------------------------------------------------------------------------------------------------
# PINTAR UNA BALDOSA
# ---------------------------------------------------------------------------------------------------------------
def pintar(vol, ax0, az0, f, nvar, codigo, desp, VAR):
    ix, iy, iz = np.nonzero(vol)
    if ix.size == 0:
        return
    ids = vol[ix, iy, iz].astype(np.int64)
    k = nvar[ids]
    m = k > 1
    if not m.any():
        return
    ix, iy, iz, ids, k = ix[m], iy[m], iz[m], ids[m], k[m]
    X = ix.astype(np.int64) + ax0
    Y = iy.astype(np.int64)
    Z = iz.astype(np.int64) + az0
    P = VAR.shape[0]
    d = desp[ids]
    # el ruido va en METROS (indices de 10 cm): a 20 cm cada voxel salta dos celdas de la tabla
    ruido = VAR[(X * f + d[:, 0]) % P, (Y * f + d[:, 1]) % P, (Z * f + d[:, 2]) % P].astype(np.int64)
    var = ruido % k
    cods = codigo[ids]
    for cod in np.unique(cods[cods > 0]):
        mm = cods == cod
        r = ruido[mm]
        if cod == M.REVOQUE:
            # chorretones: el ruido estirado en vertical (50 cm)
            dm = d[mm]
            r = VAR[(X[mm] * f + dm[:, 0]) % P, ((Y[mm] * f) // 5 + dm[:, 1]) % P, (Z[mm] * f + dm[:, 2]) % P].astype(np.int64)
        var[mm] = patron(int(cod), X[mm], Y[mm], Z[mm], k[mm], r, f)
    vol[ix, iy, iz] = (ids + var).astype(np.uint8)


# ---------------------------------------------------------------------------------------------------------------
# RASTERIZAR EL MAPA A LAS DOS RESOLUCIONES
# ---------------------------------------------------------------------------------------------------------------
def rasterizar(prims, id_de, nvar, codigo, desp, VAR, chunks, vs=0.1, al_terminar=None, avisar=print):
    """Devuelve (chunks_hi, chunks_lo, dims_lo, solidos_hi, solidos_lo). `al_terminar(tx, tz, hi, lo)` recibe cada
    baldosa ya pintada a las dos resoluciones (256 voxels de 10 cm = 128 de 20 cm = 25,6 m)."""
    ncx, ncy, ncz = chunks
    dims_lo = ((ncx + 1) // 2, (ncy + 1) // 2, (ncz + 1) // 2)
    vs2 = vs * 2
    dvox_hi = (ncx * CHUNK, ncy * CHUNK, ncz * CHUNK)
    dvox_lo = (dims_lo[0] * CHUNK, dims_lo[1] * CHUNK, dims_lo[2] * CHUNK)
    lista_hi, cajas_hi = R.preparar(prims, vs, dvox_hi, id_de)
    lista_lo, cajas_lo = R.preparar(prims, vs2, dvox_lo, id_de)
    alto_hi = int(min(dvox_hi[1], max(128, math.ceil(int(cajas_hi[:, 3].max()) / 64.0) * 64)))
    alto_lo = alto_hi // 2
    hi, lo = {}, {}
    s_hi = s_lo = 0
    B = R.BALDOSA
    ntx, ntz = (dvox_hi[0] + B - 1) // B, (dvox_hi[2] + B - 1) // B
    for tz in range(ntz):
        for tx in range(ntx):
            ax0, az0 = tx * B, tz * B
            vh = R.rasterizar_baldosa(lista_hi, cajas_hi, (ax0, ax0 + B, az0, az0 + B), alto_hi, vs)
            pintar(vh, ax0, az0, 1, nvar, codigo, desp, VAR)
            s_hi += R._trocear(vh, tx, tz, B, chunks, alto_hi, hi)
            b0x, b0z = tx * (B // 2), tz * (B // 2)
            vl = R.rasterizar_baldosa(lista_lo, cajas_lo, (b0x, b0x + B // 2, b0z, b0z + B // 2), alto_lo, vs2)
            pintar(vl, b0x, b0z, 2, nvar, codigo, desp, VAR)
            s_lo += R._trocear(vl, tx, tz, B // 2, dims_lo, alto_lo, lo)
            if al_terminar:
                al_terminar(tx, tz, vh, vl)
            del vh, vl
        avisar("  baldosas: fila %d/%d, chunks %d (10 cm) / %d (20 cm)" % (tz + 1, ntz, len(hi), len(lo)))
    return hi, lo, dims_lo, s_hi, s_lo, alto_hi, alto_lo
