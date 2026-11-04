"""LAS MONTANAS del norte: la cordillera que se ve desde toda la isla.

  - EL TUNEL: la carretera del norte atraviesa la cordillera por dentro, 90 m de tunel iluminado con aceras,
    boca de hormigon a cada lado y coches abandonados. Es la ruta rapida entre la ciudad y la cala del norte,
    y un pasillo largo y peligroso.
  - EL OBSERVATORIO en la cumbre: edificio redondo de dos plantas con cupula y telescopio, y al lado la
    antena de radio con su luz roja. El mejor sitio de francotirador del mapa, y el mas expuesto.
  - EL BUNKER excavado en la falda sur: pasillo de entrada en trinchera y sala de hormigon con botin bueno.
  - EL REFUGIO: cabana de troncos en una terraza de la falda.
  - LA CALA DEL NORTE: donde sale el tunel. Chiringuito, aparcamiento y torre de socorrista.

El monte entero es material ancla: las explosiones abren crateres, no lo derrumban.
"""
import math

import disposicion as D
import edificios as E
import naturaleza as NAT
import ciudad as C

XT, ZS, ZN, _ = D.TUNEL
REFUGIO = (212.0, 128.0)
CALA = (266.0, 40.0)


def planificar(T):
    T.macizo(XT - 14, ZN - 6, XT + 14, ZS + 6)
    cx, cz = D.CUMBRE
    yc = T.altura(cx, cz)
    T.aplanar(cx - 11, cz - 11, cx + 11, cz + 11, yc - 1.5, falda=9.0, mat="grava")
    x, z = REFUGIO
    T.aplanar(x - 8, z - 7, x + 8, z + 7, T.altura(x, z), falda=6.0, mat="tierra")
    T.aplanar(CALA[0] - 12, CALA[1] - 6, CALA[0] + 8, CALA[1] + 8, D.q(D.MAR_Y + 1.05), falda=6.0, mat="arena_playa")


def construir(l, T, rng):
    l.zona = "montana"
    _tunel(l, T, rng)
    _observatorio(l, T, rng)
    _bunker(l, T, rng)
    x, z = REFUGIO
    y = T.altura(x, z)
    E.casa(l, x - 5, z - 4, x + 5, z + 4, y, rng, frente="+z", tronco=True, tejado="pizarra", plantas=2, nivel=2)
    T.ocupar(x - 8, z - 7, x + 8, z + 7)
    l.spawn(x, y + 0.5, z + 6)
    _cala(l, T, rng)


def _tunel(l, T, rng):
    ys = T.altura(XT, ZS + 3.0)
    yn = T.altura(XT, ZN - 3.0)
    ancho, paso = 4.5, 1.5
    n = int((ZS - ZN) / paso)
    cotas = []
    for i in range(n + 1):
        z = ZS - i * paso
        y = D.q(ys + (yn - ys) * i / n)
        cotas.append((z, y))
    # la excavacion: caja hasta 3 m y boveda de 4,5 m de radio encima; luego se rellena el suelo
    for (za, ya), (zb, _yb) in zip(cotas, cotas[1:]):
        z0, z1 = min(za, zb) - 0.05, max(za, zb) + 0.05
        l.caja(XT - ancho, ya, z0, XT + ancho, ya + 3.0, z1, "roca_monte", hueco=True)
        l.cilindro(XT, ya + 3.0, z0, ancho, z1 - z0, "roca_monte", hueco=True, eje="z")
        l.caja(XT - ancho - 0.3, ya - 1.8, z0, XT + ancho + 0.3, ya, z1, "hormigon_oscuro")
        l.caja(XT - 3.3, ya - 0.3, z0, XT + 3.3, ya, z1, "asfalto")
        if int(za / 3) % 2:
            l.caja(XT - 0.08, ya - 0.3, z0, XT + 0.08, ya, z1, "linea_amarilla")
        # aceras de 1 m a cada lado, elevadas 0,3 m
        l.caja(XT - ancho - 0.3, ya, z0, XT - 3.3, ya + 0.3, z1, "acera")
        l.caja(XT + 3.3, ya, z0, XT + ancho + 0.3, ya + 0.3, z1, "acera")
    # lamparas en la boveda cada 12 m: tubo fluorescente metido en la roca, y su luz
    for i in range(0, n, 8):
        z, y = cotas[i]
        if T.altura(XT, z) < y + 9.0:          # tramo al aire (antes de la boca): la lampara no tendria donde agarrarse
            continue
        for s in (-1, 1):
            x0 = XT + s * 3.9
            l.caja(min(x0, x0 + s * 0.9), y + 5.4, z - 0.9, max(x0, x0 + s * 0.9), y + 5.7, z + 0.9, "luz_fria")
        l.luz(XT, y + 5.2, z, (200, 225, 255), 0.9, 11.0)
    # bocas: marco de hormigon donde el monte ya cubre el tunel
    for sentido, lista in ((1, cotas), (-1, cotas[::-1])):
        for z, y in lista:
            if T.altura(XT, z) > y + 9.0:
                l.caja(XT - 6.3, y - 0.9, z - 0.8, XT + 6.3, y + 8.6, z + 0.8, "hormigon")
                l.caja(XT - ancho, y, z - 0.9, XT + ancho, y + 3.0, z + 0.9, "hormigon", hueco=True)
                l.cilindro(XT, y + 3.0, z - 0.9, ancho, 1.8, "hormigon", hueco=True, eje="z")
                l.caja(XT - 3.3, y - 0.3, z - 0.9, XT + 3.3, y, z + 0.9, "asfalto")
                l.caja(XT - ancho - 0.3, y, z - 0.9, XT - 3.3, y + 0.3, z + 0.9, "acera")
                l.caja(XT + 3.3, y, z - 0.9, XT + ancho + 0.3, y + 0.3, z + 0.9, "acera")
                # franjas de aviso amarillas y negras sobre la boca
                for k in range(8):
                    l.caja(XT - 6.3 + k * 1.575, y + 7.6, z - 0.9 if sentido > 0 else z + 0.8,
                           XT - 6.3 + (k + 1) * 1.575, y + 8.3, z - 0.8 if sentido > 0 else z + 0.9,
                           "chapa_amarilla" if k % 2 else "metal_oscuro")
                break
    # coches abandonados dentro y botin
    for k, i in enumerate((n // 4, n // 2, 3 * n // 4)):
        z, y = cotas[i]
        l.loot(XT + (-1.7 if k % 2 else 1.7), y, z + 2.5, "arma" if k == 1 else "municion", 2)
    l.spawn(XT, ys + 0.5, ZS + 8)


def _cono_hueco(l, cx, y, cz, capas, mat, grosor=0.3, hueco_desde=None):
    """Cupula aproximada por troncos de cono (r0, r1, alto), vaciada por dentro a partir de `hueco_desde` (la
    cupula arranca por debajo de la losa para morderla, pero la losa se queda: es el suelo).

    EL HUECO ES LA MISMA CUPULA ENCOGIDA `grosor` Y BAJADA 0,45 m. Encogerla solo en horizontal dejaba la
    cascara de un voxel donde la cupula se tumba (arriba), y a 15 cm eso se parte en anillos sueltos: el motor
    los veia como flotadores. Asi queda >= `grosor` de lado y >= 0,45 m por arriba en todas partes."""
    yy = y
    for r0, r1, h in capas:
        l.cono(cx, yy, cz, r0, r1, h, mat)
        yy += h - 0.02
    top = yy
    desde = hueco_desde if hueco_desde is not None else y
    yy = y
    for r0, r1, h in capas:
        a, b = yy - 0.45, yy + h - 0.02 - 0.45
        a2 = max(a, desde)
        if b > a2:
            k0 = (a2 - a) / h
            ra = r0 + (r1 - r0) * k0
            l.cono(cx, a2, cz, max(0.2, ra - grosor), max(0.0, r1 - grosor), b - a2 + 0.02, mat, hueco=True)
        yy += h - 0.02
    return top


def _observatorio(l, T, rng):
    cx, cz = D.CUMBRE
    y0 = T.altura(cx, cz)
    fl0 = y0 + 0.15
    R, alto, pisos = 7.2, 3.6, 2
    ys = [fl0 + i * alto for i in range(pisos)]
    techo = fl0 + pisos * alto
    l.cilindro(cx, y0 - 0.9, cz, R + 0.3, 1.05, "hormigon")
    for yb in ys:
        l.cilindro(cx, yb, cz, R, alto, "revoco_blanco")
        l.cilindro(cx, yb, cz, R - 0.3, alto - 0.3, "revoco_blanco", hueco=True)
        l.cilindro(cx, yb - 0.15, cz, R - 0.3, 0.15, "baldosa")
    # ventanas en rendija alrededor, con cristal en el plano del muro
    for yb in ys:
        for k in range(10):
            a = k * math.tau / 10
            if abs(a - math.pi * 0.5) < 0.3:
                continue
            wx, wz = cx + math.cos(a) * (R - 0.15), cz + math.sin(a) * (R - 0.15)
            l.caja(wx - 0.5, yb + 1.1, wz - 0.5, wx + 0.5, yb + 2.4, wz + 0.5, "revoco_blanco", hueco=True)
            l.caja(wx - 0.08, yb + 1.1, wz - 0.08, wx + 0.08, yb + 2.4, wz + 0.08, "vidrio")
    # escalera en U en medio, cerrada por dos muros (torre de escalera exenta)
    m = E.Marco(cx - 3.0, cz - 3.6, cx + 3.0, cz + 1.8, "+z")
    E.nucleo_escalera(m, l, ys, alto, a_azotea=True)
    for yb in ys:
        m.caja(l, 0, yb, 0, m.W, yb + alto, E.T_MURO, "hormigon")
        m.caja(l, 0, yb, 0, E.T_MURO, yb + alto, 2 * E.FRANJA + 2 * E.T_MURO, "hormigon")
    # puerta al sur (hacia la isla)
    l.puerta(cx, fl0, cz + R - 0.15, 0.0, ancho=1.2, alto=2.4, tipo="metal", grosor=0.9)
    # la cupula con su rendija y el telescopio
    _cono_hueco(l, cx, techo - 0.3, cz, [(R, R - 0.4, 1.6), (R - 0.4, R - 1.6, 1.7), (R - 1.6, R - 3.6, 1.6), (R - 3.6, 0.6, 1.3)],
                "chapa_blanca", hueco_desde=techo)
    l.caja(cx - 0.6, techo + 1.5, cz - R - 0.5, cx + 0.6, techo + 7.0, cz - 1.5, "chapa_blanca", hueco=True)
    l.cilindro(cx + 2.5, techo, cz - 1.5, 0.6, 1.4, "metal_oscuro")
    l.linea(cx + 2.5, techo + 1.6, cz - 1.5, cx + 1.2, techo + 4.6, cz - 4.2, 0.9, "chapa_blanca")
    for yb in ys:
        l.loot_sala(cx - R + 2.5, cz + 2.2, cx + R - 2.5, cz + R - 1.5, yb, rng, 3, 2)
    l.loot(cx - 3.5, techo, cz + 2.5, "arma", 3)
    # la antena de radio: celosia de tres montantes con riostras, anclada 0,6 m en el suelo
    ax, az = cx + 14.0, cz + 2.0
    ay = T.altura_min(ax - 2, az - 2, ax + 2, az + 2)
    alto_a = 26.0
    pies = [(ax + 1.3 * math.cos(a), az + 1.3 * math.sin(a)) for a in (0.0, math.tau / 3, 2 * math.tau / 3)]
    for px, pz in pies:
        l.cilindro(px, ay - 0.6, pz, 0.35, 0.9, "hormigon")
        l.linea(px, ay, pz, ax + (px - ax) * 0.3, ay + alto_a, az + (pz - az) * 0.3, 0.2, "chapa_roja")
    for k in range(1, 13):
        h = alto_a * k / 13
        f = 1.0 - 0.7 * k / 13
        pts = [(ax + (px - ax) * f, az + (pz - az) * f) for px, pz in pies]
        for i in range(3):
            (a0, b0), (a1, b1) = pts[i], pts[(i + 1) % 3]
            l.linea(a0, ay + h, b0, a1, ay + h, b1, 0.15, "chapa_blanca" if k % 2 else "chapa_roja")
    l.esfera(ax, ay + alto_a + 0.2, az, 0.45, "luz_roja")
    l.luz(ax, ay + alto_a + 0.2, az, (255, 50, 40), 1.2, 10.0)
    T.ocupar(cx - 16, cz - 12, cx + 18, cz + 12)
    l.spawn(cx, fl0 + 0.3, cz + R + 3.0)


def _bunker(l, T, rng):
    """Bunker metido en la falda sur. Se busca subiendo por la ladera el primer sitio con 6 m de monte encima."""
    x = 206.0
    z = 150.0
    y_pie = T.altura(x, z)
    while z > 100.0 and T.altura(x, z) < y_pie + 7.0:
        z -= 1.0
    y = D.q(y_pie + 0.3)
    z_boca = z + 2.0                 # la fachada queda un poco dentro del monte
    x0, x1, z0, z1 = x - 6.0, x + 6.0, z_boca - 11.0, z_boca
    # hueco en el monte + cascaron de hormigon de 0,45 m
    l.caja(x0 - 0.5, y - 0.6, z0 - 0.5, x1 + 0.5, y + 4.0, z1 + 0.2, "hormigon", hueco=True)
    l.caja(x0, y - 0.6, z0, x1, y + 3.9, z1, "hormigon_oscuro")
    l.caja(x0 + 0.45, y, z0 + 0.45, x1 - 0.45, y + 3.45, z1 - 0.45, "hormigon_oscuro", hueco=True)
    # trinchera de acceso: del pie de la ladera a la puerta
    zt = z_boca
    while zt < z_boca + 14.0 and T.altura(x, zt) > y + 0.3:
        zt += 1.0
    l.caja(x - 1.8, y, z_boca, x + 1.8, y + 4.0, zt + 1.0, "roca_monte", hueco=True)
    l.caja(x - 1.8, y - 0.3, z_boca, x + 1.8, y, zt + 1.0, "hormigon")
    for s in (-1, 1):                                   # muros de contencion de la trinchera
        l.caja(x + s * 1.8, y - 0.6, z_boca, x + s * 2.25, y + 3.6, zt + 1.0, "hormigon")
    l.puerta(x, y, z1 - 0.225, 0.0, ancho=1.2, alto=2.4, tipo="metal", grosor=0.8)
    l.caja(x - 0.4, y + 2.6, z1, x + 0.4, y + 2.9, z1 + 0.3, "luz_roja")
    l.luz(x, y + 2.7, z1 + 0.8, (255, 70, 50), 0.7, 6.0)
    # dentro: literas, cajas, un tabique con paso
    l.caja(x0 + 0.45, y, z0 + 5.0, x1 - 3.0, y + 3.45, z0 + 5.3, "hormigon")
    l.caja(x1 - 3.0 - 1.4, y, z0 + 5.0, x1 - 3.0, y + 2.4, z0 + 5.3, "hormigon", hueco=True)
    for k in range(3):
        l.caja(x0 + 0.45, y, z0 + 1.0 + k * 1.3, x0 + 2.4, y + 0.6, z0 + 1.9 + k * 1.3, "metal_oscuro")
        l.caja(x0 + 0.45, y + 1.3, z0 + 1.0 + k * 1.3, x0 + 2.4, y + 1.45, z0 + 1.9 + k * 1.3, "metal_oscuro")
    l.luz(x, y + 3.0, z0 + 3.0, (255, 214, 170), 0.6, 7.0)
    l.loot_sala(x0 + 0.5, z0 + 0.5, x1 - 0.5, z0 + 5.0, y, rng, 3, 3)
    l.loot_sala(x0 + 0.5, z0 + 5.3, x1 - 0.5, z1 - 0.5, y, rng, 2, 2)
    T.macizo(x0 - 6, z0 - 6, x1 + 6, z1 + 6)
    T.ocupar(x0 - 3, z0, x1 + 3, zt + 3)


def _cala(l, T, rng):
    """Chiringuito, aparcamiento y torre de socorrista donde sale el tunel."""
    x, z = CALA
    y = D.q(D.MAR_Y + 1.05)
    E.casa(l, x - 10, z - 3, x - 2, z + 3, y, rng, frente="+z", muro="revoco_blanco", tejado="teja",
           nivel=1, porche=True)
    torre_socorrista(l, x + 4.0, z + 5.0, y, rng)
    T.ocupar(x - 12, z - 6, x + 8, z + 8)
    l.spawn(x, y + 0.5, z + 4.0)


def torre_socorrista(l, x, z, y, rng):
    """Torre de socorrista de madera: cuatro patas metidas en la arena, plataforma, casilla y escalera."""
    for dx in (-0.9, 0.9):
        for dz in (-0.9, 0.9):
            l.caja(x + dx - 0.12, y - 0.6, z + dz - 0.12, x + dx + 0.12, y + 2.4, z + dz + 0.12, "madera")
    l.caja(x - 1.2, y + 2.4, z - 1.2, x + 1.2, y + 2.7, z + 1.2, "madera_clara")
    l.caja(x - 1.2, y + 2.7, z - 1.2, x + 1.2, y + 3.6, z - 1.05, "madera_clara")
    l.caja(x - 1.35, y + 4.6, z - 1.35, x + 1.35, y + 4.8, z + 1.35, "toldo_rojo")
    for dx in (-1.1, 1.1):
        l.caja(x + dx - 0.08, y + 2.7, z - 1.1, x + dx + 0.08, y + 4.65, z - 0.95, "madera")
        l.caja(x + dx - 0.08, y + 2.7, z + 0.95, x + dx + 0.08, y + 4.65, z + 1.1, "madera")
    for k in range(8):
        h = y + (k + 1) * 0.3
        l.caja(x - 0.5, max(y - 0.3, h - 0.45), z + 1.2 + (7 - k) * 0.35, x + 0.5, h, z + 1.2 + (8 - k) * 0.35 + 0.02, "madera")
    l.loot(x, y + 2.7, z, "municion", 1)
