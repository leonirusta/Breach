# -*- coding: utf-8 -*-
"""Genera los dos atlas de fotogramas del disparo: el fogonazo y la bocanada de gas caliente.

Los shaders que los usan (shaders/fogonazo.gdshader y shaders/humo_arma.gdshader) son CC0 y vienen
de Godot Shaders, pero SUS IMAGENES NO son CC0: el autor lo dice expresamente. Asi que las suyas no
se pueden coger y estas se dibujan aqui desde cero.

Los dos shaders leen una rejilla de fotogramas y sacan cual toca de `INSTANCE_CUSTOM.z`, que es lo
que avanza la particula a lo largo de su vida. 4x4 = 16 fotogramas de 128 px.

    python tools/make_fogonazo.py

No hay PIL en esta maquina, asi que el PNG se escribe a mano (zlib + CRC), como se hizo con las
estrellas del cielo y el ruido del humo.
"""
import math, os, struct, zlib

LADO = 4          # fotogramas por fila y por columna
PX = 128          # lado de cada fotograma
N = LADO * PX

RAIZ = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot", "assets")


def png(ruta, pix, w, h):
    """pix: lista de filas, cada fila una lista de (r,g,b,a) enteros 0-255."""
    crudo = b""
    for fila in pix:
        crudo += b"\x00" + bytes([c for p in fila for c in p])
    def trozo(tipo, datos):
        return (struct.pack(">I", len(datos)) + tipo + datos
                + struct.pack(">I", zlib.crc32(tipo + datos) & 0xFFFFFFFF))
    with open(ruta, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(trozo(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        f.write(trozo(b"IDAT", zlib.compress(crudo, 9)))
        f.write(trozo(b"IEND", b""))
    print("%s  %dx%d  %.0f KB" % (os.path.basename(ruta), w, h, os.path.getsize(ruta) / 1024.0))


def suave(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3.0 - 2.0 * x)


# --- ruido de celosia, para que el humo tenga grumos y no sea una pelota lisa -------------------
def _h(x, y, s):
    n = (x * 374761393 + y * 668265263 + s * 1442695040888963407) & 0xFFFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def ruido(x, y, s):
    xi, yi = int(math.floor(x)), int(math.floor(y))
    xf, yf = x - xi, y - yi
    u, v = suave(xf), suave(yf)
    a = _h(xi, yi, s); b = _h(xi + 1, yi, s)
    c = _h(xi, yi + 1, s); d = _h(xi + 1, yi + 1, s)
    return (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v


def fractal(x, y, s, oct=3):
    v, amp, esc, tot = 0.0, 1.0, 1.0, 0.0
    for i in range(oct):
        v += ruido(x * esc, y * esc, s + i * 91) * amp
        tot += amp
        amp *= 0.5
        esc *= 2.1
    return v / tot


# ================================================================= EL FOGONAZO
# Una estrella de polvora: nucleo blanco casi cegador y puntas irregulares hacia fuera. Crece de
# golpe en dos fotogramas (un fogonazo no "aparece", estalla) y luego se apaga.
PUNTAS = 9
FASE = [0.00, 0.62, 1.31, 1.88, 2.55, 3.27, 3.91, 4.62, 5.44]  # repartidas a mano: iguales dan una flor
LARGO = [1.00, 0.48, 0.86, 0.55, 0.97, 0.44, 0.79, 0.62, 0.90]
ANCHO = [0.13, 0.08, 0.11, 0.07, 0.14, 0.07, 0.10, 0.08, 0.12]  # puas finas, no petalos


def fogonazo():
    filas = [[(0, 0, 0, 0)] * N for _ in range(N)]
    for f in range(LADO * LADO):
        t = f / float(LADO * LADO - 1)
        # ESTALLA. Ya esta casi entero en el primer fotograma: un fogonazo no crece, aparece hecho.
        crece = (0.78 if f == 0 else 1.0) * (1.0 + 0.30 * t)
        vida = 1.0 if t < 0.08 else max(0.0, 1.0 - (t - 0.08) / 0.92) ** 1.9
        # PARPADEO: la polvora no arde parejo, cada fotograma tira una pua mas y otra menos
        giro = f * 0.37
        for i in range(PUNTAS):
            pass
        fy, fx = divmod(f, LADO)
        for y in range(PX):
            for x in range(PX):
                u = (x - PX * 0.5 + 0.5) / (PX * 0.46)
                v = (y - PX * 0.5 + 0.5) / (PX * 0.46)
                r = math.hypot(u, v)
                if r > 1.15 or vida <= 0.0:
                    continue
                ang = math.atan2(v, u)
                # LAS PUAS: cada una, una campana estrecha en su angulo. Estrecha de verdad, que si
                # se ensancha deja de parecer polvora y parece un sol de dibujos.
                punta = 0.0
                for i in range(PUNTAS):
                    d = (ang - FASE[i] - giro + math.pi) % (2 * math.pi) - math.pi
                    largo = LARGO[i] * (0.75 + 0.35 * (0.5 + 0.5 * math.sin(f * 2.1 + i * 1.7)))
                    punta = max(punta, largo * math.exp(-(d / ANCHO[i]) ** 2))
                borde = crece * (0.16 + 0.84 * punta)
                # EL NUCLEO va aparte del recorte de las puas: si se recorta con ellas sale un
                # poligono, que es lo que pasaba antes.
                nucleo = math.exp(-(r / (0.17 * crece)) ** 2.2)
                puas = 0.0
                if r <= borde:
                    puas = (1.0 - r / max(borde, 0.001)) ** 1.35
                i_tot = min(1.0, puas * 0.80 + nucleo * 1.8) * vida
                if i_tot <= 0.004:
                    continue
                # blanco quemado en el centro, amarillo, y naranja fuerte en la punta
                cal = min(1.0, nucleo * 2.2 + puas * 0.35)
                rr = 1.0
                gg = 0.30 + 0.70 * cal
                bb = 0.02 + 0.88 * cal ** 2.2
                filas[fy * PX + y][fx * PX + x] = (
                    int(rr * 255), int(gg * 255), int(bb * 255), int(min(1.0, i_tot) * 255))
    png(os.path.join(RAIZ, "fogonazo.png"), filas, N, N)


# ================================================================= EL GAS CALIENTE
# La bocanada que sale detras del fogonazo: una bola de grumos que se abre y se deshace. Va en
# mezcla aditiva (asi viene el shader), o sea que es gas ILUMINADO, no una nube gris: por eso tira a
# blanco sucio y dura poco. El humo gris que se queda flotando ya lo pone effects.gd por su cuenta.
def humo_arma():
    filas = [[(0, 0, 0, 0)] * N for _ in range(N)]
    for f in range(LADO * LADO):
        t = f / float(LADO * LADO - 1)
        # Ya sale hecha: el gas esta ahi desde el primer fotograma, solo se abre y se deshace.
        crece = 0.26 + 0.82 * suave(min(1.0, t / 0.70))
        vida = max(0.0, 1.0 - t) ** 1.25
        fy, fx = divmod(f, LADO)
        for y in range(PX):
            for x in range(PX):
                u = (x - PX * 0.5 + 0.5) / (PX * 0.47)
                v = (y - PX * 0.5 + 0.5) / (PX * 0.47)
                r = math.hypot(u, v)
                if r > 1.1 or vida <= 0.0:
                    continue
                # LOS GRUMOS. Ruido fino y con muchas octavas: con poco detalle salia una bola de
                # algodon, y el gas de un canon son jirones. Y se estiran hacia fuera segun se abre,
                # que es por donde escapa: por eso el ruido se lee en coordenadas radiales.
                ang = math.atan2(v, u)
                gr = fractal(ang * 2.4 + t * 1.6, r * 4.2 - t * 2.2, 7, 4)
                gr = gr * 0.65 + fractal(u * 5.5 + t * 1.1, v * 5.5 - t * 0.7, 23, 3) * 0.35
                borde = crece * (0.45 + 0.80 * gr)
                if r > borde:
                    continue
                k = 1.0 - r / max(borde, 0.001)
                d = (k ** 1.25) * (0.20 + 1.05 * gr) * vida
                if d <= 0.004:
                    continue
                # el centro guarda calor mas tiempo que los bordes
                cal = min(1.0, k * 1.3) * (1.0 - t * 0.7)
                rr = 0.72 + 0.28 * cal
                gg = 0.68 + 0.24 * cal
                bb = 0.64 + 0.10 * cal
                a = min(1.0, d * 0.85)
                filas[fy * PX + y][fx * PX + x] = (
                    int(rr * 255), int(gg * 255), int(bb * 255), int(a * 255))
    png(os.path.join(RAIZ, "humo_arma.png"), filas, N, N)


if __name__ == "__main__":
    fogonazo()
    humo_arma()
