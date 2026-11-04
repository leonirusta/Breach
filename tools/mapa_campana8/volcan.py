"""CONSTRUCCION del EPISODIO 8 "EL VOLCAN" (campana_volcan). Ver disposicion.py para el recorrido y los puzzles.

Una isla volcanica de noche: el cono (hueco, de basalto anclado) en el medio, acantilados alrededor, el valle de
ceniza, el llano de las bombas, el rio de lava con su cauce, el campo de geiseres con las piedras de la rejilla y el
derrumbe del norte, el valle del azufre, el pueblo con la fila de casas por donde bajara la colada y el lago de lava
con su dique, la estacion vulcanologica, el tunel de lava por dentro del monte del oeste y la bahia con el muelle.
Lo que se mueve, arde o explota lo pone el juego (campana8.gd): la lava, la torre de agua, la roca, las bombas,
el globo caido, el hidroavion.

`validacion=True`: los puzzles resueltos para el A* (la costra sobre el rio, la brecha del derrumbe y el paso de la
colada por el pueblo).
"""
import math
import disposicion as D
import lienzo as L
import campana as K           # el kit del episodio 1 (mesa, cama...)
import presa as P             # las piezas del episodio 4 (casas, farolas, pinos...)

G = D.G

# ======================================================================================================
# MATERIALES
# ======================================================================================================
MATERIALES = dict(P.MATERIALES)


def _pat(nombre, patron, colores, tipo):
    MATERIALES[nombre] = (colores[0], tipo)
    L.PATRONES[nombre] = (patron, colores)


_pat("basalto", "estratos", [(58, 54, 56), (48, 44, 46), (68, 62, 62), (40, 36, 38)], "suelo")
_pat("ceniza", "cesped", [(92, 88, 86), (80, 76, 74), (104, 100, 96), (70, 66, 64)], "suelo")
_pat("arena_negra", "cesped", [(40, 38, 40), (34, 32, 34), (48, 46, 48), (30, 28, 30)], "suelo")
_pat("azufre", "cesped", [(206, 186, 54), (184, 164, 40), (222, 204, 76), (160, 140, 30)], "suelo")
_pat("roca_volcanica", "estratos", [(46, 30, 28), (36, 24, 22), (58, 36, 30), (30, 20, 18)], "suelo")
_pat("costra", "cesped", [(34, 28, 28), (26, 22, 22), (60, 26, 18), (44, 34, 30)], "suelo")
MATERIALES.update({
    "obsidiana": ((20, 18, 26), "piedra"),
    "hormigon_estacion": ((150, 150, 146), "hormigon"),
    "chapa_estacion": ((170, 60, 40), "metal"),
    "negro_hollin": ((24, 22, 20), "tierra"),
})
CALIDA = (255, 190, 120)
LAVA = (255, 90, 30)
FRIA = (190, 214, 255)


def caja_hueca(l, x0, y0, z0, x1, y1, z1, mat, grosor=0.4, suelo=None, techo=True):
    l.caja(x0, y0, z0, x1, y1, z1, mat)
    l.caja(x0 + grosor, y0, z0 + grosor, x1 - grosor, y1 - (grosor if techo else -0.1), z1 - grosor, mat, hueco=True)
    if suelo:
        l.caja(x0 + grosor, y0 - 0.2, z0 + grosor, x1 - grosor, y0, z1 - grosor, suelo)


# ======================================================================================================
# LA ISLA: el mar, los acantilados, el volcan y las crestas que separan los tramos
# ======================================================================================================
def isla(l, validacion):
    X, Z = D.ANCHO_X, D.ANCHO_Z
    l.caja(0, 0, 0, X, D.ROCA_Y, Z, "roca_base")
    l.caja(0, D.ROCA_Y, 0, X, G - 0.2, Z, "roca_volcanica")
    l.caja(0, G - 0.2, 0, X, G, Z, "ceniza")
    # EL MAR: fuera de la isla, el fondo a 0,6
    i0, iz0, i1, iz1 = D.ISLA
    for (a0, b0, a1, b1) in ((0, 0, X, iz0), (0, iz1, X, Z), (0, iz0, i0, iz1), (i1, iz0, X, iz1)):
        l.caja(a0, 0.6, b0, a1, G, b1, "roca_volcanica", hueco=True)
        l.caja(a0, 0.4, b0, a1, 0.6, b1, "arena_negra")
    # LOS ACANTILADOS (menos la boca de la bahia)
    h = D.ACANTILADO_ALTO
    l.caja(i0, G, iz0, i1, h, iz0 + 3.0, "basalto")
    l.caja(i0, G, iz1 - 3.0, i1, h, iz1, "basalto")
    l.caja(i1 - 3.0, G, iz0, i1, h, iz1, "basalto")
    l.caja(i0, G, iz0, i0 + 3.0, h, iz1, "basalto")
    ba0, bz0, ba1, bz1 = D.BAHIA_AGUA
    l.caja(0, 0.6, bz0, ba1, h + 0.5, bz1, "basalto", hueco=True)
    l.caja(0, 0.4, bz0, ba1, 0.6, bz1, "arena_negra")
    for i in range(0, int(i1 - i0), 6):                      # la cresta del acantilado, dentada
        l.caja(i0 + i, h, iz0, i0 + i + 3.0, h + 1.0 + (i % 3) * 0.5, iz0 + 3.0, "basalto")
        l.caja(i0 + i, h, iz1 - 3.0, i0 + i + 3.0, h + 1.0 + (i % 5) * 0.4, iz1, "basalto")
    # EL VOLCAN: un cono hueco por capas, con el crater arriba
    vx, vz, vr, vy = D.VOLCAN
    capas = 14
    alto = (vy - G) / capas
    for i in range(capas):
        y0 = G + i * alto
        r = vr - i * (vr - 7.0) / capas
        l.cilindro(vx, y0, vz, r, alto + 0.05, "basalto")
        if r > 8.0:
            l.cilindro(vx, y0 - 0.05, vz, r - 4.0, alto + 0.15, "basalto", hueco=True)
    l.cilindro(vx, vy - 3.0, vz, 5.5, 3.5, "basalto", hueco=True)
    l.cilindro(vx, vy - 3.2, vz, 5.5, 0.3, "roca_volcanica")
    for k in range(10):                                        # coladas viejas (costras) por las laderas
        a = k / 10 * math.tau + 0.3
        x0, z0 = vx + math.cos(a) * 8.0, vz + math.sin(a) * 8.0
        x1, z1 = vx + math.cos(a) * (vr - 1.0), vz + math.sin(a) * (vr - 1.0)
        l.linea(x0, vy - 4.0, z0, x1, G + 0.8, z1, 1.6, "costra")
    # LAS CRESTAS que cierran los tramos
    l.caja(10.0, G, 119.0, 82.0, 14.0, 124.0, "basalto")                         # bahia | globo
    l.caja(120.0, G, 40.0, 126.0, 13.0, 70.0, "basalto")                         # geiseres | pueblo
    for (x, z) in ((30.0, 121.0), (55.0, 121.0), (123.0, 55.0)):
        l.elipsoide(x, 14.0, z, 6.0, 3.0, 4.0, "basalto")


# ======================================================================================================
# S: EL GLOBO, LA CABAÑA, LA NUBE DE CENIZA Y EL LLANO DE LAS BOMBAS
# ======================================================================================================
def sur(l, rng, validacion):
    # la playa negra donde cae el globo (la cesta y la tela son del juego) y la cabaña de los vulcanologos
    l.caja(12.0, G - 0.3, 136.0, 58.0, G, 163.0, "arena_negra")
    c0, cz0, c1, cz1 = D.CABANA
    caja_hueca(l, c0, G, cz0, c1, G + 3.2, cz1, "tablas", 0.3, suelo="tablas_oscuras")
    l.caja(c0 - 0.4, G, (cz0 + cz1) / 2 - 0.9, c0 + 0.4, G + 2.4, (cz0 + cz1) / 2 + 0.9, "tablas", hueco=True)
    l.caja(c0 - 0.5, G + 3.2, cz0 - 0.5, c1 + 0.5, G + 3.5, cz1 + 0.5, "chapa_estacion")
    K.mesa(l, (c0 + c1) / 2, (cz0 + cz1) / 2, G)
    l.luz((c0 + c1) / 2, G + 2.6, (cz0 + cz1) / 2, CALIDA, 0.8, 8.0)
    # la nube de ceniza: el valle con dunas y rocas; los mojones del camino son piedras calientes (del juego: brillan)
    x0, z0, x1, z1 = D.CENIZA
    for i in range(34):
        x, z = rng.uniform(x0 + 2, x1 - 2), rng.uniform(z0 + 2, z1 - 2)
        if any(math.hypot(x - mx, z - mz) < 4.0 for (mx, mz) in D.MOJONES):
            continue
        l.elipsoide(x, G, z, rng.uniform(1.5, 4.0), rng.uniform(0.6, 2.2), rng.uniform(1.5, 3.5), rng.choice(("basalto", "ceniza", "obsidiana")))
    for (mx, mz) in D.MOJONES:
        l.caja(mx - 0.4, G, mz - 0.4, mx + 0.4, G + 1.4, mz + 0.4, "obsidiana")
    # el llano de las bombas: crateres viejos, y el abrigo de hormigon junto al rio
    b0, bz0, b1, bz1 = D.BOMBAS
    for i in range(16):
        x, z = rng.uniform(b0 + 4, b1 - 4), rng.uniform(bz0 + 6, bz1 - 4)
        l.elipsoide(x, G, z, rng.uniform(1.2, 2.4), 0.8, rng.uniform(1.2, 2.4), "roca_volcanica", hueco=True)
        l.elipsoide(x, G - 0.1, z, rng.uniform(1.5, 2.8), 0.15, rng.uniform(1.5, 2.8), "negro_hollin")
    a0, az0, a1, az1 = D.REFUGIO_BOMBAS
    caja_hueca(l, a0, G, az0, a1, G + 2.8, az1, "hormigon_estacion", 0.5)
    l.caja(a0 + 3.0, G, az1 - 0.6, a1 - 3.0, G + 2.2, az1 + 0.1, "hormigon_estacion", hueco=True)
    l.caja(a0 + 3.0, G, az0 - 0.1, a1 - 3.0, G + 2.2, az0 + 0.6, "hormigon_estacion", hueco=True)


# ======================================================================================================
# E: EL RIO DE LAVA Y LOS GEISERES
# ======================================================================================================
def este(l, rng, validacion):
    # el cauce del rio (la lava es del juego) con sus orillas de roca
    r0, rz0, r1, rz1 = D.RIO
    l.caja(r0 - 2.0, 1.0, rz0, r1, G, rz1, "roca_volcanica", hueco=True)
    l.caja(r0 - 2.0, 0.8, rz0, r1, 1.0, rz1, "costra")
    for z in (rz0 - 0.4, rz1 + 0.4):
        l.caja(r0, G, z - 0.4, r1 - 3.0, G + 0.5, z + 0.4, "roca_volcanica")
    l.caja(r1 - 3.0, 1.0, rz0, r1, G, rz1, "roca_volcanica", hueco=True)                   # sale al mar por el acantilado
    if validacion:
        p0, pz0, p1, pz1 = D.PUENTE_LAVA
        l.caja(p0, 1.0, pz0, p1, G, pz1, "costra")
    # el pie de la torre de agua (la torre es del juego)
    tx, tz = D.TORRE_AGUA
    l.caja(tx - 3.0, G, tz - 3.0, tx + 3.0, G + 0.4, tz + 3.0, "hormigon_estacion")
    # EL CAMPO DE GEISERES: el suelo de azufre claro, las piedras de la rejilla y la boca del geiser grande
    g0, gz0, g1, gz1 = D.GEISERES
    l.caja(g0, G - 0.15, gz0, g1 - 3.0, G, gz1, "azufre")
    rx, rz = D.REJILLA
    for (c, f) in D.PIEDRAS:
        x, z = D.celda_centro(c, f)
        l.elipsoide(x, G, z, 0.95, 1.4, 0.95, "basalto")
        l.caja(x - 0.8, G, z - 0.8, x + 0.8, G + 1.2, z + 0.8, "basalto")
    gx, gz = D.celda_centro(*D.GEISER_GRANDE)
    l.cilindro(gx, G - 0.4, gz, 1.8, 0.8, "roca_volcanica")
    l.cilindro(gx, G - 0.4, gz, 0.9, 0.9, "roca_volcanica", hueco=True)
    for (x, z) in D.GEISERES_CHICOS:
        l.cilindro(x, G - 0.2, z, 1.0, 0.5, "azufre")
        l.cilindro(x, G - 0.3, z, 0.4, 0.8, "azufre", hueco=True)
    # EL DERRUMBE del norte (lo revienta la roca que lanza el geiser)
    d0, dz0, d1, dz1 = D.DERRUMBE_N
    l.caja(d0, G, dz0, d1 - 3.0, G + 5.5, dz1, "basalto")
    for i in range(10):
        l.elipsoide(rng.uniform(d0, d1 - 4), G + 5.0, rng.uniform(dz0, dz1), rng.uniform(1.5, 2.6), 1.2, 1.4, "basalto")
    if validacion:
        b0, b1 = D.BRECHA_N
        l.caja(b0, G, dz0 - 0.5, b1, G + 8.0, dz1 + 0.5, "basalto", hueco=True)
    l.luz(gx, G + 1.0, gz, (255, 220, 120), 0.6, 8.0)


# ======================================================================================================
# N: EL VALLE DEL AZUFRE Y EL PUEBLO (con el lago de lava y su dique)
# ======================================================================================================
def norte(l, rng, validacion):
    a0, az0, a1, az1 = D.AZUFRE
    l.caja(a0, G - 0.15, az0, a1 - 3.0, G, az1, "azufre")
    for i in range(22):                                              # fumarolas y costras amarillas
        x, z = rng.uniform(a0 + 3, a1 - 6), rng.uniform(az0 + 4, az1 - 3)
        l.elipsoide(x, G, z, rng.uniform(1.0, 2.5), rng.uniform(0.5, 1.6), rng.uniform(1.0, 2.2), rng.choice(("azufre", "basalto")))
    # la taquilla de las mascaras y las cajas de filtros (lo que se coge es del juego)
    tx, ty, tz = D.TAQUILLA_MASCARAS
    l.caja(tx - 1.5, G, tz - 0.3, tx + 1.5, G + 2.4, tz + 0.5, "chapa_estacion")
    for (x, y, z) in D.CAJAS_FILTRO:
        l.caja(x - 0.6, G, z - 0.4, x + 0.6, G + 0.8, z + 0.4, "acero_verde")
    # EL PUEBLO: casas a los dos lados de la calle mayor
    p0, pz0, p1, pz1 = D.PUEBLO
    c0, cz0, c1, cz1 = D.CALLE_PUEBLO
    l.caja(p0, G - 0.2, cz0, p1, G, cz1, "adoquin")
    for x in range(44, 80, 12):
        P.casa(l, (x, 14.0, x + 9.0, cz0 - 1.5), G, 2, rng, puerta=("+z", x + 4.5), tejado="teja")
        P.casa(l, (x, cz1 + 1.5, x + 9.0, cz1 + 10.0), G, 2, rng, puerta=("-z", x + 4.5), tejado="teja")
    for x in range(94, 100, 12):
        P.casa(l, (x, 14.0, 99.0, cz0 - 1.5), G, 2, rng, tejado="teja")
    # LA FILA DE CASAS que cierra el pueblo de norte a sur (por ahi bajara la colada)
    f0, f1 = D.FILA_CASAS
    for z in range(12, 50, 6):
        l.caja(f0, G, float(z), f1, G + 5.0, float(z) + 5.8, "piedra_casa")
        l.caja(f0 - 0.2, G + 5.0, float(z) - 0.2, f1 + 0.2, G + 5.4, float(z) + 6.0, "teja")
    l.caja(f0, G, 12.0, f1, G + 3.5, 50.0, "piedra_casa")                            # y los muros entre ellas
    if validacion:
        # por donde paso la colada (arrasado)
        cx = D.COLADA[0][0]
        l.caja(cx - D.COLADA_ANCHO / 2, G, 12.0, cx + D.COLADA_ANCHO / 2, G + 6.0, 50.0, "piedra_casa", hueco=True)
    # EL LAGO DE LAVA en la ladera (terraza alta) y su DIQUE (las cargas son del juego)
    la0, laz0, la1, laz1 = D.LAGO_LAVA
    l.caja(la0 - 3.0, G, laz0, la1 + 3.0, D.LAGO_LAVA_Y + 1.0, laz1 + 4.0, "basalto")
    l.caja(la0, D.LAGO_LAVA_Y - 1.2, laz0, la1, D.LAGO_LAVA_Y + 1.1, laz1, "basalto", hueco=True)
    di0, diz0, di1, diz1 = D.DIQUE
    l.caja(di0, G, diz0, di1, D.LAGO_LAVA_Y + 1.6, diz1, "roca_volcanica")
    for x, z in ((50.0, 30.0), (66.0, 30.0), (100.0, 22.0)):
        P.farola(l, x, z, G)
    l.luz((la0 + la1) / 2, D.LAGO_LAVA_Y + 1.5, (laz0 + laz1) / 2, LAVA, 2.0, 22.0)


# ======================================================================================================
# NO y O: LA ESTACION, EL TUNEL DE LAVA Y LA BAHIA
# ======================================================================================================
def oeste(l, rng, validacion):
    e0, ez0, e1, ez1 = D.ESTACION
    l.caja(e0, G - 0.2, ez0, e1, G, ez1, "hormigon")
    for (a0, b0, a1, b1) in ((e0, ez0, e1, ez0 + 0.4), (e0, ez0, e0 + 0.4, ez1), (e1 - 0.4, ez0, e1, 22.0),
                             (e1 - 0.4, 28.0, e1, ez1)):
        l.caja(a0, G, b0, a1, G + 2.4, b1, "hormigon_estacion")
    r0, rz0, r1, rz1 = D.REFUGIO
    caja_hueca(l, r0, G, rz0, r1, G + 3.6, rz1, "hormigon_estacion", 0.4, suelo="baldosa")
    pnx, pnz = D.REFUGIO_PUERTA_N
    l.caja(pnx - 0.9, G, pnz - 0.6, pnx + 0.9, G + 2.7, pnz + 0.6, "hormigon_estacion", hueco=True)
    psx, psz = D.REFUGIO_PUERTA_S
    l.caja(psx - 0.9, G, psz - 0.6, psx + 0.9, G + 2.7, psz + 0.6, "hormigon_estacion", hueco=True)
    l.caja(r0 - 0.3, G + 3.6, rz0 - 0.3, r1 + 0.3, G + 3.9, rz1 + 0.3, "chapa_estacion")
    K.cama(l, r0 + 1.0, rz0 + 1.2, G, "x", rng)
    K.cama(l, r0 + 1.0, rz1 - 2.6, G, "x", rng)
    K.mesa(l, (r0 + r1) / 2 + 2.0, (rz0 + rz1) / 2, G)
    l.caja(r1 - 1.4, G, rz0 + 1.0, r1 - 0.5, G + 1.6, rz0 + 4.0, "acero_verde")            # los sismografos
    l.luz((r0 + r1) / 2, G + 3.0, (rz0 + rz1) / 2, CALIDA, 1.0, 10.0)
    l.caja(32.0, G, 16.0, 36.0, G + 9.0, 18.0, "hierro")                                     # la antena
    # EL MONTE DEL OESTE (cascara) con un macizo alrededor del tunel, y el tunel de lava
    m0, mz0, m1, mz1 = D.MONTE_OESTE
    l.caja(m0, G, mz0, m1, 14.0, mz1, "basalto")
    l.caja(m0 + 3.0, G, mz0 + 3.0, m1 - 3.0, 11.0, mz1 - 3.0, "basalto", hueco=True)
    l.caja(m0, 13.6, mz0, m1, 14.0, mz1, "ceniza")
    tun = D.TUNEL
    w = D.TUNEL_ANCHO / 2
    for (a, b) in zip(tun, tun[1:]):
        x0, x1 = min(a[0], b[0]) - w, max(a[0], b[0]) + w
        z0, z1 = min(a[1], b[1]) - w, max(a[1], b[1]) + w
        l.caja(x0 - 5.0, G - 2.0, max(z0 - 5.0, mz0), x1 + 5.0, G + 7.0, min(z1 + 5.0, mz1), "basalto")   # el macizo del tubo
    for (x, z) in D.SALIENTES:
        l.caja(x - 5.0, G - 2.0, max(z - 5.0, mz0), x + 5.0, G + 7.0, min(z + 5.0, mz1), "basalto")
    for (a, b) in zip(tun, tun[1:]):
        x0, x1 = min(a[0], b[0]) - w, max(a[0], b[0]) + w
        z0, z1 = min(a[1], b[1]) - w, max(a[1], b[1]) + w
        l.caja(x0, D.TUNEL_SUELO, z0, x1, D.TUNEL_SUELO + D.TUNEL_ALTO, z1, "basalto", hueco=True)
        l.caja(x0, D.TUNEL_SUELO - 0.15, z0, x1, D.TUNEL_SUELO, z1, "costra")
        # el techo abovedado (y algo irregular)
        l.linea(a[0], D.TUNEL_SUELO + D.TUNEL_ALTO - 0.3, a[1], b[0], D.TUNEL_SUELO + D.TUNEL_ALTO - 0.3, b[1], D.TUNEL_ANCHO - 0.6, "basalto", hueco=True)
    for i in range(14):
        a, b = tun[i % (len(tun) - 1)], tun[i % (len(tun) - 1) + 1]
        t = rng.random()
        x, z = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
        l.elipsoide(x + rng.uniform(-1.5, 1.5), D.TUNEL_SUELO + 2.0, z + rng.uniform(-1.5, 1.5), 1.6, 1.4, 1.6, "basalto", hueco=True)
    # las ALCOBAS con su saliente (obsidiana, a salvo de la lava que sube) y un escalon
    for (x, z) in D.SALIENTES:
        l.caja(x - 1.6, D.TUNEL_SUELO, z - 1.6, x + 1.6, D.TUNEL_SUELO + D.TUNEL_ALTO, z + 1.6, "basalto", hueco=True)
        l.caja(x - 1.5, D.TUNEL_SUELO - 0.1, z - 1.5, x + 1.5, D.TUNEL_SUELO + D.SALIENTE_ALTO, z + 1.5, "obsidiana")
        l.luz(x, D.TUNEL_SUELO + 3.0, z, (255, 120, 60), 0.5, 7.0)
    # la boca del tubo en el patio (rampa de bajada) y la salida a la bahia (rampa de subida)
    bx, bz = tun[0]
    l.caja(bx - w, D.TUNEL_SUELO, 32.0, bx + w, G + 3.0, bz + 0.5, "basalto", hueco=True)
    l.cuna(bx - w, D.TUNEL_SUELO, 32.0, bx + w, G, bz, sube_hacia="-z", mat="costra")
    sx, sz = tun[-1]
    l.caja(sx - w, D.TUNEL_SUELO, sz - 2.0, sx + w, G + 3.0, 103.0, "basalto", hueco=True)
    l.cuna(sx - w, D.TUNEL_SUELO, sz - 2.0, sx + w, G, 103.0, sube_hacia="+z", mat="costra")
    # LA BAHIA: el muelle (el hidroavion es del juego), un cobertizo y bidones
    mu0, muz0, mu1, muz1 = D.MUELLE
    l.caja(mu0, G - 0.3, muz0, mu1, G, muz1, "tablas_oscuras")
    for x in range(int(mu0), int(mu1), 4):
        for z in (muz0 + 0.2, muz1 - 0.2):
            l.cilindro(x, 0.6, z, 0.2, G - 0.6, "tronco")
    caja_hueca(l, 38.0, G, 108.0, 46.0, G + 3.4, 116.0, "chapa_ondulada", 0.3)
    l.caja(37.6, G, 110.0, 38.4, G + 2.8, 114.0, "chapa_ondulada", hueco=True)
    for x, z in ((40.0, 102.0), (48.0, 104.0), (26.0, 101.0)):
        P.farola(l, x, z, G)


def construir(l, rng, validacion=False):
    isla(l, validacion)
    sur(l, rng, validacion)
    este(l, rng, validacion)
    norte(l, rng, validacion)
    oeste(l, rng, validacion)
    for p in D.RUTA:
        l.punto(p[0], p[1], p[2], "ruta")
    pts = [(20.0, G, 156.0), (48.0, G, 158.0), (70.0, G, 132.0), (90.0, G, 156.0), (110.0, G, 150.0), (118.0, G, 128.0),
           (134.0, G, 150.0), (156.0, G, 140.0), (140.0, G, 124.0), (160.0, G, 92.0), (134.0, G, 86.0), (156.0, G, 50.0),
           (130.0, G, 60.0), (150.0, G, 18.0), (130.0, G, 36.0), (110.0, G, 16.0), (108.0, G, 44.0),
           (60.0, G, 30.0), (76.0, G, 26.0), (98.0, G, 34.0), (50.0, G, 32.0), (30.0, G, 34.0), (36.0, G, 20.0),
           (23.0, D.TUNEL_SUELO, 56.0), (34.0, D.TUNEL_SUELO, 70.0), (26.0, D.TUNEL_SUELO, 88.0),
           (44.0, G, 112.0), (60.0, G, 108.0), (48.0, G, 102.0)]
    for x, y, z in pts:
        l.punto(x, y, z, "criatura")
