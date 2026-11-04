# -*- coding: utf-8 -*-
"""Recomprime PNG sin perder un solo pixel.

    python tools/comprimir_png.py godot/assets/inicio.png godot/assets/icono.png

POR QUE HACE FALTA. Un PNG guarda cada fila precedida de un byte que dice con que FILTRO se
codifico: ninguno, la diferencia con el pixel de la izquierda, con el de arriba, la media de ambos,
o Paeth (una prediccion que elige entre los tres vecinos). El filtro no cambia lo que se ve: cambia
cuanto se PARECEN entre si los bytes que luego comprime zlib, y ahi esta todo el margen.

Casi ningun programa se molesta en probarlos: escriben siempre el mismo y ya. Aqui se prueban los
cinco en cada fila y se elige el que deja los bytes mas parecidos entre si -la heuristica clasica de
minima suma de valores absolutos-, y ademas se comprime al maximo. Es lo mismo que hace `optipng`.

NO TOCA UN PIXEL: se decodifica, se vuelve a codificar y se comprueba que los datos crudos son
identicos byte a byte antes de sustituir nada. Si el resultado no sale mas pequeno, se deja el
original en paz.

No hay PIL en esta maquina, asi que el decodificador esta escrito a mano (zlib + deshacer filtros).
"""
import os
import struct
import sys
import zlib


def leer_png(ruta):
    """Devuelve (ancho, alto, canales, filas_crudas). Solo 8 bits sin entrelazar."""
    d = open(ruta, "rb").read()
    if d[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("no es un PNG")
    i = 8
    idat = b""
    w = h = depth = ctype = interlace = 0
    paleta = None
    while i < len(d):
        ln = struct.unpack(">I", d[i:i + 4])[0]
        tipo = d[i + 4:i + 8]
        datos = d[i + 8:i + 8 + ln]
        if tipo == b"IHDR":
            w, h, depth, ctype, _comp, _filt, interlace = struct.unpack(">IIBBBBB", datos)
        elif tipo == b"PLTE":
            paleta = datos
        elif tipo == b"IDAT":
            idat += datos
        elif tipo == b"IEND":
            break
        i += 12 + ln
    if depth != 8 or interlace != 0:
        raise ValueError("solo 8 bits y sin entrelazar (este es %d bits, entrelazado %d)" % (depth, interlace))
    canales = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    return w, h, canales, ctype, paleta, zlib.decompress(idat)


def deshacer_filtros(w, h, canales, crudo):
    """Del flujo con byte de filtro por fila a las filas de pixeles tal cual."""
    ancho_fila = w * canales
    salida = bytearray(h * ancho_fila)
    prev = bytearray(ancho_fila)
    p = 0
    for y in range(h):
        f = crudo[p]; p += 1
        fila = bytearray(crudo[p:p + ancho_fila]); p += ancho_fila
        if f == 1:
            for x in range(canales, ancho_fila):
                fila[x] = (fila[x] + fila[x - canales]) & 255
        elif f == 2:
            for x in range(ancho_fila):
                fila[x] = (fila[x] + prev[x]) & 255
        elif f == 3:
            for x in range(ancho_fila):
                izq = fila[x - canales] if x >= canales else 0
                fila[x] = (fila[x] + ((izq + prev[x]) >> 1)) & 255
        elif f == 4:
            for x in range(ancho_fila):
                a = fila[x - canales] if x >= canales else 0
                b = prev[x]
                c = prev[x - canales] if x >= canales else 0
                pa = abs(b - c); pb = abs(a - c); pc = abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                fila[x] = (fila[x] + pr) & 255
        salida[y * ancho_fila:(y + 1) * ancho_fila] = fila
        prev = fila
    return salida


def _coste(fila):
    """Lo 'plana' que queda una fila filtrada. Menos suma = bytes mas parecidos = comprime mejor."""
    return sum(b if b < 128 else 256 - b for b in fila)


def aplicar_mejor_filtro(w, h, canales, pix):
    """Vuelve a montar el flujo eligiendo el mejor filtro FILA A FILA."""
    ancho_fila = w * canales
    fuera = bytearray()
    prev = bytearray(ancho_fila)
    for y in range(h):
        fila = pix[y * ancho_fila:(y + 1) * ancho_fila]
        candidatas = []
        # 0: sin filtro
        candidatas.append((0, bytes(fila)))
        # 1: diferencia con la izquierda
        s = bytearray(fila)
        for x in range(ancho_fila - 1, canales - 1, -1):
            s[x] = (fila[x] - fila[x - canales]) & 255
        candidatas.append((1, bytes(s)))
        # 2: diferencia con la de arriba
        u = bytearray(ancho_fila)
        for x in range(ancho_fila):
            u[x] = (fila[x] - prev[x]) & 255
        candidatas.append((2, bytes(u)))
        # 3: media de izquierda y arriba
        a3 = bytearray(ancho_fila)
        for x in range(ancho_fila):
            izq = fila[x - canales] if x >= canales else 0
            a3[x] = (fila[x] - ((izq + prev[x]) >> 1)) & 255
        candidatas.append((3, bytes(a3)))
        # 4: Paeth
        p4 = bytearray(ancho_fila)
        for x in range(ancho_fila):
            a = fila[x - canales] if x >= canales else 0
            b = prev[x]
            c = prev[x - canales] if x >= canales else 0
            pa = abs(b - c); pb = abs(a - c); pc = abs(a + b - 2 * c)
            pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
            p4[x] = (fila[x] - pr) & 255
        candidatas.append((4, bytes(p4)))
        mejor = min(candidatas, key=lambda t: _coste(t[1]))
        fuera.append(mejor[0])
        fuera += mejor[1]
        prev = fila
    return bytes(fuera)


def escribir_png(ruta, w, h, ctype, paleta, flujo):
    def trozo(tipo, datos):
        return (struct.pack(">I", len(datos)) + tipo + datos
                + struct.pack(">I", zlib.crc32(tipo + datos) & 0xFFFFFFFF))
    with open(ruta, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(trozo(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, ctype, 0, 0, 0)))
        if paleta is not None:
            f.write(trozo(b"PLTE", paleta))
        f.write(trozo(b"IDAT", zlib.compress(flujo, 9)))
        f.write(trozo(b"IEND", b""))


def comprimir(ruta):
    antes = os.path.getsize(ruta)
    try:
        w, h, canales, ctype, paleta, crudo = leer_png(ruta)
    except ValueError as e:
        print("  %-22s SALTADO (%s)" % (os.path.basename(ruta), e))
        return 0, 0
    pix = deshacer_filtros(w, h, canales, crudo)
    flujo = aplicar_mejor_filtro(w, h, canales, pix)
    tmp = ruta + ".tmp"
    escribir_png(tmp, w, h, ctype, paleta, flujo)
    # COMPROBACION: los pixeles del archivo nuevo tienen que ser IDENTICOS a los del viejo.
    w2, h2, c2, _t2, _p2, crudo2 = leer_png(tmp)
    pix2 = deshacer_filtros(w2, h2, c2, crudo2)
    if pix2 != pix:
        os.remove(tmp)
        print("  %-22s ABORTADO: los pixeles no coinciden" % os.path.basename(ruta))
        return 0, 0
    despues = os.path.getsize(tmp)
    if despues >= antes:
        os.remove(tmp)
        print("  %-22s %7.1f KB  ya estaba bien comprimido, se deja" % (os.path.basename(ruta), antes / 1024.0))
        return antes, antes
    os.replace(tmp, ruta)
    print("  %-22s %7.1f -> %7.1f KB   (-%.1f %%)  identico pixel a pixel"
          % (os.path.basename(ruta), antes / 1024.0, despues / 1024.0, 100.0 * (antes - despues) / antes))
    return antes, despues


if __name__ == "__main__":
    tot_a = tot_d = 0
    for r in sys.argv[1:]:
        a, d = comprimir(r)
        tot_a += a; tot_d += d
    if tot_a:
        print("  %-22s %7.1f -> %7.1f KB   (-%.1f %%)"
              % ("TOTAL", tot_a / 1024.0, tot_d / 1024.0, 100.0 * (tot_a - tot_d) / tot_a))
