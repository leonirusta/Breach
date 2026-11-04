"""CONSTRUCCION del EPISODIO 6 "LA CUMBRE" (campana_cumbre). Ver disposicion.py para el recorrido y los puzzles.

De dia y nevando: el lago helado con el avion partido, el pueblo minero, la mina que cruza la cresta, la carretera de
montaña (ventisqueros, el derrumbe con el laberinto del robot, el barranco sin puente y la cornisa de nieve), la meseta
con las grietas, el monasterio de la espadaña, el observatorio (pasillo de los laseres, patio de los espejos, cupula)
y la estacion del teleferico. Lo que se mueve, explota o se usa lo pone el juego (campana6.gd); aqui, lo fijo y lo que
se rompe: las placas finas, los ventisqueros, el derrumbe, la cornisa, los puentes de nieve falsos y el hielo.

Las montañas son CASCARAS (3 m de roca y hueco dentro): el mundo no guarda los chunks de aire, y macizas costaban
cientos de MB. Son de un material ANCLADO (roca_nevada): el analizador estructural no las tira nunca.

`validacion=True`: los puzzles resueltos para el A* (sin ventisqueros, sin derrumbe, con el relleno de la avalancha,
sin los puentes falsos y sin el hielo de la sala de maquinas).
"""
import math
import disposicion as D
import lienzo as L
import campana as K           # el kit del episodio 1 (mesa, cama...)
import presa as P             # las piezas del episodio 4 (casas, farolas, vias, pinos...)

G = D.G
M = D.M

# ======================================================================================================
# MATERIALES
# ======================================================================================================
MATERIALES = dict(P.MATERIALES)


def _pat(nombre, patron, colores, tipo):
    MATERIALES[nombre] = (colores[0], tipo)
    L.PATRONES[nombre] = (patron, colores)


NIEVE = [(236, 240, 246), (226, 232, 241), (245, 247, 251), (214, 222, 234)]
_pat("nieve", "cesped", NIEVE, "suelo")
_pat("nieve_dura", "cesped", [(232, 237, 244), (224, 230, 240), (242, 245, 250), (212, 220, 232)], "suelo")
_pat("roca_nevada", "estratos", [(104, 102, 106), (92, 90, 96), (118, 116, 120), (140, 142, 150)], "suelo")
_pat("hielo", "estratos", [(200, 222, 236), (188, 212, 230), (210, 230, 242), (178, 204, 224)], "suelo")
_pat("hielo_fino", "cesped", [(20, 44, 70), (16, 38, 62), (26, 52, 80), (32, 60, 88)], "suelo")   # MUY oscuro: la nieve lo aclara
_pat("hielo_muro", "estratos", [(150, 198, 226), (134, 186, 220), (168, 208, 232), (118, 170, 208)], "suelo")
_pat("piedra_monasterio", "sillar", [(168, 158, 140), (152, 144, 128), (180, 170, 152), (128, 120, 106), (108, 102, 92)], "piedra")
_pat("chapa_estacion", "lamas", [(168, 42, 36), (138, 32, 28)], "metal")
_pat("jalon", "rayas", [(206, 40, 30), (232, 232, 228)], "metal")
_pat("tablas_mina", "tablas", [(84, 62, 42), (72, 54, 36), (96, 70, 48), (58, 42, 30)], "madera")
MATERIALES.update({
    "chapa_avion": ((86, 94, 66), "metal"),
    "chapa_avion_osc": ((58, 64, 46), "metal"),
    "hormigon_lab": ((176, 178, 180), "hormigon"),
    "cupula_blanca": ((226, 228, 232), "metal"),
    "cristal_lab": ((96, 126, 146), "vidrio"),
    "furgon_blanco": ((226, 226, 222), "metal"),
    "furgon_azul": ((40, 70, 150), "metal"),
    "negro_hollin": ((24, 22, 20), "tierra"),
    "roca_suelta": ((112, 108, 104), "piedra"),
})
CALIDA = (255, 190, 120)
FUEGO = (255, 120, 40)
FRIA = (200, 222, 255)
ROJA = (255, 50, 30)


def caja_hueca(l, x0, y0, z0, x1, y1, z1, mat, grosor=0.4, suelo=None, techo=True):
    l.caja(x0, y0, z0, x1, y1, z1, mat)
    l.caja(x0 + grosor, y0, z0 + grosor, x1 - grosor, y1 - (grosor if techo else -0.1), z1 - grosor, mat, hueco=True)
    if suelo:
        l.caja(x0 + grosor, y0 - 0.2, z0 + grosor, x1 - grosor, y0, z1 - grosor, suelo)


def monte(l, x0, z0, x1, z1, top, g=3.0, desde=None):
    """Una montaña de cascara: roca anclada, nieve arriba, y hueca por dentro (si da para hueco)."""
    y0 = G if desde is None else desde
    l.caja(x0, y0, z0, x1, top, z1, "roca_nevada")
    if x1 - x0 > 2 * g + 1 and z1 - z0 > 2 * g + 1 and top - y0 > g + 1:
        l.caja(x0 + g, y0, z0 + g, x1 - g, top - g, z1 - g, "roca_nevada", hueco=True)
    l.caja(x0, top - 0.35, z0, x1, top, z1, "nieve")


def jalon(l, x, z, y):
    l.caja(x - 0.05, y, z - 0.05, x + 0.05, y + 1.7, z + 0.05, "jalon")


# ======================================================================================================
# EL TERRENO: suelo, montañas, cresta, macizo, barranco y meseta
# ======================================================================================================
def terreno(l, validacion):
    X, Z = D.ANCHO_X, D.ANCHO_Z
    l.caja(0, 0, 0, X, D.ROCA_Y, Z, "roca_base")
    l.caja(0, D.ROCA_Y, 0, X, G - 0.3, Z, "tierra_monte")
    l.caja(0, G - 0.3, 0, X, G, Z, "nieve")
    # el cerco: norte (con la cornisa encima del barranco), sur, este y el oeste del lago
    l.caja(0, G, 0, 110.0, 20.0, 4.0, "roca_nevada")
    l.caja(0, 19.6, 0, 110.0, 20.0, 4.0, "nieve")
    l.caja(110.0, G, 0, 136.0, 24.0, 6.0, "roca_nevada")
    l.caja(110.0, 23.6, 0, 136.0, 24.0, 6.0, "nieve")
    l.caja(136.0, G, 0, X, 18.0, 6.0, "roca_nevada")
    l.caja(136.0, 17.6, 0, X, 18.0, 6.0, "nieve")
    l.caja(0, G, 168.0, X, 12.0, Z, "roca_nevada")
    l.caja(0, 11.6, 168.0, X, 12.0, Z, "nieve")
    l.caja(188.0, G, 6.0, X, 13.0, 168.0, "roca_nevada")
    l.caja(188.0, 12.6, 6.0, X, 13.0, 168.0, "nieve")
    monte(l, 0, 104.0, 12.0, 168.0, 12.0)
    # picos dentados por encima del cerco (se ven desde todo el mapa)
    for i, (x, z, h, r) in enumerate([(30, 1.5, 26, 6), (70, 1.0, 28, 7), (160, 2.0, 27, 7), (60, 174.0, 20, 7),
                                      (150, 174.0, 19, 6)]):
        l.elipsoide(x, 16.0, z, r, h - 16.0, r * 0.6, "roca_nevada")
        l.elipsoide(x, 16.0 + (h - 16.0) * 0.55, z, r * 0.55, (h - 16.0) * 0.5, r * 0.4, "nieve")
    # LA CRESTA entre el lago y el norte (la cruza la mina), y el acantilado del lago
    monte(l, 0, D.CRESTA[0], X - 4.0, D.CRESTA[1], 14.0)
    monte(l, 0, 104.0, 116.0, 116.0, 13.0)
    # EL MACIZO que rodea la carretera
    m0, mz0, m1, mz1 = D.MACIZO
    monte(l, m0, mz0, m1, mz1, 13.0)
    # EL BARRANCO (fondo a 1,5, un arroyo helado) y su cierre sur contra el patio de la mina
    g0, gz0, g1, gz1 = D.GARGANTA
    l.caja(g0, D.GARGANTA_Y, gz0 + 4.0, g1, G, gz1, "tierra_monte", hueco=True)
    l.caja(g0, D.GARGANTA_Y - 0.2, gz0 + 4.0, g1, D.GARGANTA_Y, gz1, "nieve")
    l.caja(g0 + 5.0, D.GARGANTA_Y - 0.1, gz0 + 4.0, g0 + 8.0, D.GARGANTA_Y + 0.1, gz1, "hielo")
    l.caja(g1 - 4.0, G, 76.0, g1 + 0.6, 12.0, 84.0, "roca_nevada")
    # LA MESETA: cascara (2,5 m de techo) salvo el campo de grietas, que es macizo
    l.caja(4.0, G, 4.0, g0, M, D.CRESTA[0], "roca_nevada")
    l.caja(7.0, G, 7.0, g0 - 3.0, M - 2.5, D.CRESTA[0] - 3.0, "roca_nevada", hueco=True)
    v0, vz0, v1, vz1 = D.VENTISCA
    l.caja(v0, G, 4.0, v1, M, vz1 + 0.5, "roca_nevada")
    l.caja(4.0, M - 0.3, 4.0, g0, M, D.CRESTA[0], "nieve")
    # el pretil del oeste (con el hueco del cable del teleferico) y el espolon que separa las grietas
    l.caja(0, G, 4.0, 4.0, M + 1.2, D.CRESTA[0], "roca_nevada")
    l.caja(0, M, 12.0, 4.1, M + 1.3, 20.0, "roca_nevada", hueco=True)
    e0, ez0, e1, ez1 = D.ESPOLON
    l.caja(e0, M - 0.5, 4.0, e1, 16.0, ez1, "roca_nevada")
    l.caja(e0, 15.6, 4.0, e1, 16.0, ez1, "nieve")


# ======================================================================================================
# A. EL LAGO HELADO Y EL AVION PARTIDO
# ======================================================================================================
def lago(l, rng, validacion):
    x0, z0, x1, z1 = D.LAGO
    l.caja(x0, D.LECHO_Y, z0, x1, G, z1, "tierra_monte", hueco=True)
    l.caja(x0, D.LECHO_Y - 0.2, z0, x1, D.LECHO_Y, z1, "grava")
    for c in range(D.COLS):
        for f in range(D.FILAS):
            a0, b0, a1, b1 = D.placa_rect(c, f)
            if (c, f) in D.GRUESAS:
                l.caja(a0, D.LECHO_Y, b0, a1, G, b1, "hielo")
            else:
                l.caja(a0, D.FINO_Y, b0, a1, G, b1, "hielo_fino")
    # montoncitos de nieve SOLO sobre las gruesas (la pista que da el lago)
    for (c, f) in sorted(D.GRUESAS):
        a0, b0, a1, b1 = D.placa_rect(c, f)
        if rng.random() < 0.55:
            l.elipsoide(a0 + rng.uniform(1.0, 3.0), G, b0 + rng.uniform(1.0, 3.0), rng.uniform(0.5, 1.1), 0.22,
                        rng.uniform(0.5, 1.0), "nieve")
    # el muelle del pueblo
    mx0, mz0, mx1, mz1 = D.MUELLE
    l.caja(mx0, G, mz0, mx1, G + 0.3, mz1, "tablas_oscuras")
    for x in (mx0 + 0.3, mx0 + 4.0, mx0 + 8.0):
        for z in (mz0 + 0.2, mz1 - 0.2):
            l.caja(x - 0.15, G, z - 0.15, x + 0.15, G + 1.1, z + 0.15, "tronco")
    # EL AVION PARTIDO: el morro metido en la orilla, el fuselaje roto en dos, un ala arrancada
    az = D.AVION_Z
    l.cilindro(12.0, G + 1.9, az, 2.2, 17.5, "chapa_avion", eje="x")
    l.cilindro(12.4, G + 1.9, az, 1.9, 17.2, "chapa_avion", hueco=True, eje="x")
    l.caja(11.0, G, az - 2.4, 16.0, G + 4.2, az + 2.4, "roca_nevada")                  # el morro, en las rocas
    l.cilindro(32.5, G + 2.2, az + 0.4, 2.2, 10.5, "chapa_avion", eje="x")
    l.cilindro(32.5, G + 2.2, az + 0.4, 1.9, 10.6, "chapa_avion", hueco=True, eje="x")
    l.caja(32.0, G, az - 2.4, 43.5, G + 0.2, az + 2.8, "chapa_avion_osc")            # el piso de la bodega
    l.caja(40.0, G + 4.0, az + 0.2, 43.5, G + 8.6, az + 0.6, "chapa_avion")           # la deriva
    l.caja(39.0, G + 3.8, az - 4.0, 43.5, G + 4.1, az + 4.8, "chapa_avion")           # el timon de cola
    l.caja(20.0, G + 0.9, az - 14.0, 27.0, G + 1.3, az - 2.0, "chapa_avion")          # el ala izquierda, en su sitio
    for zz in (az - 6.0, az - 10.5):
        l.cilindro(19.0, G + 0.5, zz, 0.8, 4.2, "chapa_avion_osc", eje="x")
        l.cilindro(18.9, G + 0.5, zz, 0.55, 0.2, "negro_hollin", eje="x")
    l.caja(17.0, G, az + 5.0, 30.0, G + 0.5, az + 9.5, "chapa_avion")                  # el ala derecha, arrancada
    l.cilindro(23.0, G + 0.9, az + 7.2, 0.8, 4.2, "chapa_avion_osc", eje="x")
    l.escombros(31.0, az, G, 3.0, 26, rng, mats=("chapa_avion", "chapa_avion_osc", "hierro", "negro_hollin"))
    l.escombros(46.0, az - 1.0, G, 2.4, 12, rng, mats=("chapa_avion", "hierro"))
    for i in range(10):
        l.caja(44.0 + i * 1.6, G, az - 0.4 + (i % 3) * 0.3, 45.0 + i * 1.6, G + 0.06, az + 0.3, "negro_hollin")


# ======================================================================================================
# B. EL PUEBLO MINERO Y LA MINA
# ======================================================================================================
def pueblo(l, rng, validacion):
    for i, r in enumerate(D.CASAS):
        pisos = 2 if i != 4 else 3
        puerta = [("-x", (r[1] + r[3]) / 2), ("+z", (r[0] + r[2]) / 2), ("-x", (r[1] + r[3]) / 2),
                  ("-x", (r[1] + r[3]) / 2), ("-z", (r[0] + r[2]) / 2)][i]
        P.casa(l, r, G, pisos, rng, puerta=puerta, tejado="pizarra", color=rng.choice(("revoque_cal", "revoque_ocre")))
        l.luz((r[0] + r[2]) / 2, G + 2.8, (r[1] + r[3]) / 2, CALIDA, 0.7, 7.0)
    for x, z in ((128.0, 140.0), (146.0, 134.0), (158.0, 144.0), (146.0, 114.0), (170.0, 122.0)):
        P.farola(l, x, z, G)
    # la LAMPISTERIA de la mina (ladrillo y chapa) y la boca de la mina, con su castillete de madera
    a0, b0, a1, b1 = D.LAMPISTERIA
    caja_hueca(l, a0, G, b0, a1, G + 4.0, b1, "ladrillo_visto", 0.4, suelo="tablas_oscuras")
    l.caja(a0 - 0.5, G + 1.0, (b0 + b1) / 2 - 0.9, a0 + 0.5, G + 3.0, (b0 + b1) / 2 + 0.9, "ladrillo_visto", hueco=True)
    l.caja(a0 - 0.4, G + 4.0, b0 - 0.4, a1 + 0.4, G + 4.3, b1 + 0.4, "chapa_ondulada")
    k0, k1 = D.BOCA_MINA
    cz = D.CRESTA[1]
    for x in (k0 - 0.5, k1 + 0.1):
        l.caja(x, G, cz - 0.4, x + 0.4, G + 3.8, cz + 0.6, "tablas_mina")
    l.caja(k0 - 0.8, G + 3.5, cz - 0.4, k1 + 0.8, G + 4.0, cz + 0.6, "tablas_mina")
    P.cartel(l, k0 - 0.2, G + 4.1, cz + 0.45, k1 + 0.2, G + 5.0, cz + 0.55, "cartel_amarillo")
    P.via(l, 152.0, 124.0, 152.0, cz + 0.6, G)
    # vagonetas y carbon
    for x, z in ((147.0, 112.0), (157.0, 118.0)):
        l.caja(x - 0.7, G + 0.3, z - 1.0, x + 0.7, G + 1.3, z + 1.0, "oxido")
        l.caja(x - 0.6, G + 1.0, z - 0.9, x + 0.6, G + 1.4, z + 0.9, "carbon")
    for i in range(14):
        x, z = rng.uniform(118.0, 186.0), rng.uniform(106.0, 166.0)
        if any(D.dentro(x, z, r, 1.5) for r in D.CASAS + [D.LAMPISTERIA]) or abs(x - 152.0) < 3.0:
            continue
        P.pino(l, x, z, G, rng, alto=rng.uniform(6.0, 9.0))
    l.punto(150.0, G, 140.0, "criatura")


def mina(l, rng, validacion):
    # la roca de alrededor de la galeria, maciza (la cresta es hueca)
    l.caja(124.0, G, D.CRESTA[0], 160.0, G + 7.0, D.CRESTA[1], "roca_nevada")
    for (x0, z0, x1, z1) in D.MINA:
        l.caja(x0, G, z0, x1, G + D.MINA_ALTO, z1, "roca_nevada", hueco=True)
        l.caja(x0, G - 0.1, z0, x1, G, z1, "grava")
    n0, nz0, n1, nz1 = D.NICHO_VENTILADOR
    l.caja(n0, G, nz0, n1 + 0.1, G + 3.2, nz1, "roca_nevada", hueco=True)
    l.caja(n0, G - 0.1, nz0, n1, G, nz1, "hormigon")
    # las entibaciones: postes y cabezales de madera cada 3 m
    def marco_z(x0, x1, z):
        l.caja(x0 + 0.05, G, z - 0.15, x0 + 0.35, G + 3.1, z + 0.15, "tablas_mina")
        l.caja(x1 - 0.35, G, z - 0.15, x1 - 0.05, G + 3.1, z + 0.15, "tablas_mina")
        l.caja(x0, G + 2.85, z - 0.2, x1, G + 3.2, z + 0.2, "tablas_mina")

    def marco_x(z0, z1, x):
        l.caja(x - 0.15, G, z0 + 0.05, x + 0.15, G + 3.1, z0 + 0.35, "tablas_mina")
        l.caja(x - 0.15, G, z1 - 0.35, x + 0.15, G + 3.1, z1 - 0.05, "tablas_mina")
        l.caja(x - 0.2, G + 2.85, z0, x + 0.2, G + 3.2, z1, "tablas_mina")
    for z in (102.5, 99.5):
        marco_z(150.0, 154.0, z)
    for x in (151.0, 147.0, 143.0, 139.0):
        marco_x(92.0, 96.0, x)
    for z in (90.0, 86.5):
        marco_z(134.0, 138.0, z)
    P.via(l, 152.0, 104.0, 152.0, 96.5, G)
    P.via(l, 153.0, 94.0, 135.5, 94.0, G)
    for p in ((152.0, 101.0), (146.0, 94.0), (138.0, 94.5), (136.0, 88.0)):
        l.luz(p[0], G + 2.7, p[1], (255, 170, 90), 0.45, 6.0)
    # carteles de peligro de grisu en la boca
    l.caja(D.BOCA_MINA[1] + 0.6, G + 1.2, D.CRESTA[1] + 0.35, D.BOCA_MINA[1] + 1.6, G + 2.0, D.CRESTA[1] + 0.45, "chapa_roja")
    # la salida al patio: el marco de la puerta (la hoja es del juego)
    px0, pz0, px1, pz1 = D.PUERTA_MINA
    l.caja(px0 - 0.5, G, pz0 - 0.4, px0, G + 3.6, pz1, "hormigon")
    l.caja(px1, G, pz0 - 0.4, px1 + 0.5, G + 3.6, pz1, "hormigon")
    l.caja(px0 - 0.5, G + 3.2, pz0 - 0.4, px1 + 0.5, G + 3.8, pz1, "hormigon")


# ======================================================================================================
# C. EL PATIO DE LA MINA, LA CARRETERA, EL DERRUMBE Y LA CORNISA
# ======================================================================================================
def carretera(l, rng, validacion):
    # el cobertizo de las maquinas (vacio: la quitanieves esta fuera)
    c0, cz0, c1, cz1 = D.COBERTIZO
    caja_hueca(l, c0, G, cz0, c1, G + 4.2, cz1, "chapa_ondulada", 0.3)
    l.caja(c1 - 0.4, G, cz0 + 1.0, c1 + 0.1, G + 3.6, cz1 - 1.0, "chapa_ondulada", hueco=True)
    for i in range(4):
        l.caja(c0 + 0.6, G, cz0 + 0.6 + i * 1.4, c0 + 1.6, G + 0.9, cz0 + 1.6 + i * 1.4, "oxido")
    # las rampas (nieve dura: la carretera no se deshace a tiros)
    b0, bz0, b1, bz1 = D.CARRETERA_B
    l.cuna(b0, G, bz0, b1, D.Y_CURVA, bz1, sube_hacia="-z", mat="nieve_dura")
    cu0, cuz0, cu1, cuz1 = D.CURVA
    l.caja(cu0, G, cuz0, cu1, D.Y_CURVA, cuz1, "nieve_dura")
    c0, cz0, c1, cz1 = D.CARRETERA_C
    l.caja(c0, G, cz0, c1, D.Y_CURVA, cz1, "nieve_dura")
    l.cuna(c0, D.Y_CURVA, cz0, c1, M, cz1, sube_hacia="-x", mat="nieve_dura")
    e0, ez0, e1, ez1 = D.BORDE
    l.caja(e0, G, ez0, e1, M, ez1, "nieve_dura")
    # los jalones rojiblancos de la carretera
    for z in range(20, 76, 7):
        jalon(l, 178.6, z, D.camino_y(183.0, z))
        jalon(l, 187.4, z, D.camino_y(183.0, z))
    for x in range(132, 178, 7):
        jalon(l, x, 6.6, D.camino_y(x, 11.0))
        jalon(l, x, 15.4, D.camino_y(x, 11.0))
    # LOS VENTISQUEROS (la pala de la quitanieves los abre)
    if not validacion:
        for (x0, z0, x1, z1) in D.VENTISQUEROS:
            y = D.camino_y((x0 + x1) / 2, (z0 + z1) / 2)
            l.caja(x0, y - 0.1, z0, x1, y + D.VENTISQUERO_ALTO, z1, "nieve")
            if x1 - x0 > z1 - z0:
                l.elipsoide((x0 + x1) / 2, y + D.VENTISQUERO_ALTO, (z0 + z1) / 2, (x1 - x0) / 2, 0.6, 1.4, "nieve")
            else:
                l.elipsoide((x0 + x1) / 2, y + D.VENTISQUERO_ALTO, (z0 + z1) / 2, 1.4, 0.6, (z1 - z0) / 2, "nieve")
    # EL DERRUMBE: un monton de rocas que corta la carretera; por debajo, el laberinto del robot
    d0, dz0, d1, dz1 = D.DERRUMBE
    if not validacion:
        ym = D.camino_y(d1, 11.0)
        l.caja(d0, ym - 0.5, dz0, d1, ym + D.DERRUMBE_ALTO, dz1, "roca_suelta")
        for i in range(9):
            l.elipsoide(rng.uniform(d0, d1), ym + rng.uniform(2.5, 4.8), rng.uniform(dz0 + 1, dz1 - 1),
                        rng.uniform(1.0, 2.0), rng.uniform(0.8, 1.4), rng.uniform(1.0, 1.8), "roca_gris")
        for i in range(6):
            l.elipsoide(d1 + rng.uniform(-0.4, 1.4), ym + 0.2, rng.uniform(dz0 + 1, dz1 - 1), rng.uniform(0.4, 0.9),
                        rng.uniform(0.3, 0.6), rng.uniform(0.4, 0.8), "roca_gris")
        for (x, z) in D.ROBOT_CELDAS:
            y = D.camino_y(x, z)
            l.caja(x - 0.55, y - 0.05, z - 0.55, x + 0.55, y + D.ROBOT_HUECO_ALTO, z + 0.55, "roca_suelta", hueco=True)
        mx, mz = D.ROBOT_META
        y = D.camino_y(mx, mz)
        l.caja(mx - 1.2, y + 0.9, mz - 0.9, mx - 0.5, y + 2.2, mz + 0.9, "roca_gris")      # la piedra clave
    # la furgoneta de los TEDAX (la consola es del juego)
    t0, tz0, t1, tz1 = D.TEDAX
    ty = D.camino_y((t0 + t1) / 2, 14.0)
    l.caja(t0, ty + 0.5, tz0, t1, ty + 2.6, tz1, "furgon_blanco")
    l.caja(t0, ty + 1.2, tz0 - 0.02, t1, ty + 1.5, tz1 + 0.02, "furgon_azul")
    l.caja(t1 - 1.4, ty + 1.5, tz0 - 0.03, t1 - 0.2, ty + 2.3, tz1 + 0.03, "cristal_lab")
    l.caja(t0 - 0.02, ty + 0.6, tz0 + 0.3, t0 + 0.02, ty + 2.4, tz1 - 0.3, "hierro")
    for x in (t0 + 1.0, t1 - 1.2):
        for z in (tz0 + 0.1, tz1 - 0.1):
            l.cilindro(x, ty + 0.4, z - 0.15, 0.4, 0.3, "goma", eje="z")
    l.luz(t0 + 0.4, ty + 2.4, (tz0 + tz1) / 2, (120, 160, 255), 0.8, 8.0)
    # LOS MUÑONES DEL PUENTE VIEJO en los dos bordes del barranco
    pz0, pz1 = D.PUENTE_ROTO
    l.caja(123.0, M - 1.2, pz0, 126.0, M, pz1, "hormigon")
    l.caja(107.5, M - 1.2, pz0, 110.6, M, pz1, "hormigon")
    l.linea(123.2, M - 0.8, pz0 + 1.0, 119.0, 3.2, pz0 + 1.4, 0.7, "hormigon")
    l.linea(110.4, M - 0.8, pz0 + 1.0, 113.5, 2.4, pz0 + 0.6, 0.7, "hormigon")
    P.barandilla(l, 124.2, pz0 - 0.05, 128.0, pz0 + 0.05, M, 1.0)
    # LA CORNISA: repisa en la ladera norte y la visera de nieve que vuela sobre el barranco
    cx, cy, cz, rx, ry, rz = D.CORNISA
    l.caja(106.0, D.CORNISA_REPISA_Y, 3.0, 130.0, 25.0, 6.2, "roca_nevada", hueco=True)
    l.caja(106.0, D.CORNISA_REPISA_Y - 0.3, 3.0, 130.0, D.CORNISA_REPISA_Y, 6.2, "nieve")
    l.elipsoide(cx, cy, cz, rx, ry, rz, "nieve")
    l.caja(cx - rx, cy, 1.0, cx + rx, 24.6, cz, "nieve")
    # EL RELLENO de la avalancha (solo en la validacion: en el juego lo pone la avalancha)
    if validacion:
        r0, rz0, r1, rz1 = D.RELLENO
        l.caja(r0, D.RELLENO_Y, rz0, r1, M, rz1, "nieve_dura")
    for p in ((150.0, 80.0), (172.0, 79.0), (183.0, 40.0), (160.0, 11.0)):
        l.luz(p[0], D.camino_y(p[0], p[1]) + 3.0, p[1], FRIA, 0.6, 12.0)


# ======================================================================================================
# D. LA MESETA: LAS GRIETAS
# ======================================================================================================
def ventisca(l, rng, validacion):
    for i, (x0, z0, x1, z1) in enumerate(D.GRIETAS):
        l.caja(x0, G, z0, x1, M + 0.1, z1, "roca_nevada", hueco=True)
        l.caja(x0, G - 0.1, z0, x1, G + 0.15, z1, "hielo")
        for k in range(10):                                        # carambanos colgando de los labios
            x = x0 + 2.0 + k * (x1 - x0 - 4.0) / 9
            l.cuna(x - 0.25, M - 1.6, z0, x + 0.25, M, z0 + 0.35, sube_hacia="+z", mat="hielo")
        b0, b1 = D.PUENTES_BUENOS[i]
        l.caja(b0, M - 0.7, z0 - 0.3, b1, M, z1 + 0.3, "nieve_dura")
        if not validacion:
            for (f0, f1) in D.PUENTES_FALSOS[i]:
                l.caja(f0, M - 0.6, z0 - 0.3, f1, M, z1 + 0.3, "nieve")
    # los jalones del camino bueno (con huecos: alguno se lo ha llevado la ventisca)
    camino = [(105.0, 10.0), (67.5, 10.0), (67.5, 22.0), (101.5, 22.0), (101.5, 37.0), (77.5, 37.0), (77.5, 52.0),
              (86.0, 56.0)]
    k = 0
    for (ax, az), (bx, bz) in zip(camino, camino[1:]):
        largo = math.hypot(bx - ax, bz - az)
        n = max(1, int(largo / 5.0))
        for j in range(n):
            k += 1
            if k % 4 == 3:
                continue
            t = j / n
            x, z = ax + (bx - ax) * t, az + (bz - az) * t
            ox, oz = (0.0, 1.8) if abs(bx - ax) > abs(bz - az) else (1.8, 0.0)
            if any(g[1] - 1.0 <= z + oz <= g[3] + 1.0 for g in D.GRIETAS):
                continue
            jalon(l, x + ox, z + oz, M)
    # los braseros (el fuego es del juego)
    for (x, y, z) in D.BRASEROS:
        for dx, dz in ((-0.4, -0.4), (0.4, -0.4), (-0.4, 0.4), (0.4, 0.4)):
            l.caja(x + dx - 0.05, y, z + dz - 0.05, x + dx + 0.05, y + 0.7, z + dz + 0.05, "hierro")
        l.caja(x - 0.55, y + 0.6, z - 0.55, x + 0.55, y + 1.0, z + 0.55, "hierro")
        l.caja(x - 0.45, y + 0.7, z - 0.45, x + 0.45, y + 1.0, z + 0.45, "hierro", hueco=True)
        l.caja(x - 0.35, y + 0.7, z - 0.1, x + 0.35, y + 0.85, z + 0.1, "tronco")
    # montones de nieve (sastrugi) y alguna roca
    for i in range(40):
        x, z = rng.uniform(64.0, 108.0), rng.uniform(5.0, 55.0)
        if any(g[1] - 1.5 <= z <= g[3] + 1.5 for g in D.GRIETAS):
            continue
        l.elipsoide(x, M, z, rng.uniform(0.8, 2.2), rng.uniform(0.2, 0.6), rng.uniform(0.6, 1.4), "nieve")


# ======================================================================================================
# E. EL MONASTERIO
# ======================================================================================================
def monasterio(l, rng, validacion):
    m0, mz0, m1, mz1 = D.MONASTERIO
    h = D.MURO_MON_ALTO
    pm = "piedra_monasterio"
    l.caja(m0, M, mz0, m1, M + h, mz0 + 0.8, pm)                       # norte
    l.caja(m1 - 0.8, M, mz0, m1, M + h, mz1, pm)                       # este
    l.caja(m0, M, mz1 - 0.8, m1, M + h, mz1, pm)                       # sur (contra la cresta)
    l.caja(m0, M, mz0, m0 + 0.8, M + h, mz1, pm)                       # oeste
    for x in range(int(m0) + 1, int(m1), 2):                          # almenado
        l.caja(x, M + h, mz0, x + 1.0, M + h + 0.6, mz0 + 0.8, pm)
    p0, p1 = D.PORTON_MON
    l.caja(p0, M, mz0 - 0.2, p1, M + 4.2, mz0 + 1.0, pm, hueco=True)
    # LA ESPADAÑA: la pared de las campanas encima del porton, con cuatro vanos y el remate
    e0, ez0, e1, ez1 = D.ESPADANA
    l.caja(e0, M, ez0, e1, M + 12.4, ez1, pm)
    l.caja(p0, M, ez0 - 0.2, p1, M + 4.2, ez1 + 0.2, pm, hueco=True)
    for (bx, by, bz) in D.CAMPANAS:
        l.caja(bx - 1.2, by - 1.6, ez0 - 0.1, bx + 1.2, by + 1.3, ez1 + 0.1, pm, hueco=True)
        l.cilindro(bx, by + 1.3, ez0 - 0.1, 1.2, ez1 - ez0 + 0.2, pm, hueco=True, eje="z")
        l.caja(bx - 1.3, by - 1.8, ez0 - 0.25, bx + 1.3, by - 1.6, ez1 + 0.25, "cornisa_clara")
    for i in range(6):
        l.caja(e0 + 1.0 + i * 1.3, M + 12.4 + i * 0.5, ez0, e1 - 1.0 - i * 1.3, M + 12.9 + i * 0.5, ez1, pm)
    cxx = (e0 + e1) / 2
    l.caja(cxx - 0.12, M + 15.4, ez0 + 0.5, cxx + 0.12, M + 17.4, ez0 + 0.8, "hierro")
    l.caja(cxx - 0.7, M + 16.6, ez0 + 0.5, cxx + 0.7, M + 16.85, ez0 + 0.8, "hierro")
    cx, cy, cz = D.CUERDA_CAMPANA
    l.caja(cx - 0.15, M, cz - 0.15, cx + 0.15, M + 1.2, cz + 0.15, "tablas_oscuras")
    # el pasillo de dentro (del porton al refugio) y el CLAUSTRO con sus arcadas
    c0, cz0, c1, cz1 = D.CLAUSTRO
    l.caja(c0, M - 0.1, cz0, c1, M, cz1, "adoquin")
    for x in range(int(c0), int(c1) + 1, 3):
        for z in (cz0, cz1):
            l.caja(x - 0.3, M, z - 0.3, x + 0.3, M + 3.2, z + 0.3, pm)
    for z in range(int(cz0), int(cz1) + 1, 3):
        for x in (c0, c1):
            l.caja(x - 0.3, M, z - 0.3, x + 0.3, M + 3.2, z + 0.3, pm)
    for (a0, b0, a1, b1) in ((c0 - 0.6, cz0 - 0.6, c1 + 0.6, cz0 + 2.4), (c0 - 0.6, cz1 - 2.4, c1 + 0.6, cz1 + 0.6),
                             (c0 - 0.6, cz0, c0 + 2.4, cz1), (c1 - 2.4, cz0, c1 + 0.6, cz1)):
        l.caja(a0, M + 3.2, b0, a1, M + 3.6, b1, "teja")
    l.cilindro((c0 + c1) / 2, M, (cz0 + cz1) / 2, 1.2, 0.9, pm)                       # el pozo
    l.cilindro((c0 + c1) / 2, M + 0.2, (cz0 + cz1) / 2, 0.9, 0.8, pm, hueco=True)
    # LA IGLESIA (puerta al claustro) y el REFUGIO (el refectorio)
    i0, iz0, i1, iz1 = D.IGLESIA
    caja_hueca(l, i0, M, iz0, i1, M + 7.0, iz1, pm, 0.6, suelo="baldosa")
    l.caja(i0 - 0.4, M, 69.0, i0 + 0.8, M + 3.4, 73.0, pm, hueco=True)
    for z in range(int(iz0) + 3, int(iz1) - 2, 3):
        l.caja(i0 + 2.0, M, z, i1 - 2.0, M + 0.5, z + 0.8, "tablas_oscuras")
        l.caja(i0 + 2.0, M + 0.5, z + 0.7, i1 - 2.0, M + 1.0, z + 0.8, "tablas_oscuras")
    l.caja(i0 - 0.6, M + 7.0, iz0 - 0.6, i1 + 0.6, M + 7.4, iz1 + 0.6, "pizarra")
    l.luz((i0 + i1) / 2, M + 4.0, (iz0 + iz1) / 2, CALIDA, 0.8, 12.0)
    r0, rz0, r1, rz1 = D.REFUGIO
    caja_hueca(l, r0, M, rz0, r1, M + 3.8, rz1, pm, 0.5, suelo="baldosa")
    pnx, pnz = D.REFUGIO_PUERTA_N
    l.caja(pnx - 0.9, M, pnz - 0.6, pnx + 0.9, M + 2.7, pnz + 0.6, pm, hueco=True)
    pox, poz = D.REFUGIO_PUERTA_O
    l.caja(pox - 0.6, M, poz - 0.9, pox + 1.0, M + 2.7, poz + 0.9, pm, hueco=True)
    l.caja(r0 - 0.3, M + 3.8, rz0 - 0.3, r1 + 0.3, M + 4.1, rz1 + 0.3, "pizarra")
    K.mesa(l, (r0 + r1) / 2, rz0 + 5.0, M, w=6.0, d=1.0, mat="tablas_oscuras")
    K.mesa(l, (r0 + r1) / 2, rz0 + 9.0, M, w=6.0, d=1.0, mat="tablas_oscuras")
    K.cama(l, r1 - 3.0, rz1 - 2.4, M, "x", rng)
    K.cama(l, r0 + 1.2, rz1 - 2.4, M, "x", rng)
    l.caja(r1 - 2.2, M, rz0 + 0.5, r1 - 0.5, M + 1.6, rz0 + 1.2, "piedra_casa")        # la chimenea
    l.luz((r0 + r1) / 2, M + 3.2, (rz0 + rz1) / 2, CALIDA, 1.1, 11.0)
    l.luz(r1 - 1.4, M + 0.8, rz0 + 1.5, FUEGO, 0.8, 5.0)
    # lo de al fondo (almacenes) y el huerto nevado
    l.caja(78.0, M, 80.6, 99.0, M + 3.4, 83.2, pm)
    l.caja(63.0, M, 79.0, 76.0, M + 3.4, 83.2, pm)
    for x, z in ((66.0, 60.2), (74.0, 60.2), (104.0, 57.0), (70.0, 57.0)):
        l.luz(x, M + 2.6, z, CALIDA, 0.7, 8.0)


# ======================================================================================================
# F. EL OBSERVATORIO: patio del laboratorio, pasillo de los laseres, control, cupula, patio de los espejos
# ======================================================================================================
def observatorio(l, rng, validacion):
    hl = "hormigon_lab"
    # la pared oeste del patio del laboratorio (con la boca del pasillo)
    l.caja(55.4, M, 58.0, 56.0, M + 4.5, 84.0, hl)
    # el PASILLO: un tubo de hormigon con ventanas altas
    a0, az0, a1, az1 = D.LAB
    q0, qz0, q1, qz1 = D.PASILLO
    l.caja(a0, M, az0, a1, M + 3.8, az1, hl)
    l.caja(q0 - 0.2, M, qz0, q1 + 0.1, M + 3.0, qz1, hl, hueco=True)
    l.caja(55.3, M, qz0, 56.1, M + 3.0, qz1, hl, hueco=True)
    for x in range(34, 54, 4):
        l.caja(x, M + 2.2, az0 - 0.05, x + 1.6, M + 2.8, qz0, "cristal_lab")
    for x in D.LASERES_X:
        l.caja(x - 0.3, M, qz0, x + 0.3, M + 3.0, qz0 + 0.2, "hierro")               # los emisores de la pared
        l.caja(x - 0.3, M, qz1 - 0.2, x + 0.3, M + 3.0, qz1, "hierro")
    l.luz((q0 + q1) / 2, M + 2.7, (qz0 + qz1) / 2, FRIA, 0.8, 14.0)
    # los bloques de oficinas a los lados del pasillo
    l.caja(30.0, M, 62.0, 55.4, M + 4.2, az0, hl)
    l.caja(30.0, M, az1, 55.4, M + 4.2, 84.0, hl)
    for x in range(32, 54, 3):
        l.caja(x, M + 1.2, 61.95, x + 1.4, M + 2.4, 62.05, "cristal_lab")
    # la SALA DE CONTROL (el panel de los laseres es del juego)
    c0, cz0, c1, cz1 = D.CONTROL
    caja_hueca(l, c0, M, cz0, c1, M + 3.8, cz1, hl, 0.4, suelo="baldosa")
    l.caja(c1 - 0.6, M, qz0, c1 + 0.6, M + 3.0, qz1, hl, hueco=True)
    n0, n1 = D.PUERTA_CONTROL_N
    l.caja(n0, M, cz0 - 0.6, n1, M + 2.8, cz0 + 0.6, hl, hueco=True)
    for z in (cz0 + 2.0, cz1 - 3.0):
        l.caja(c0 + 0.6, M, z, c0 + 1.4, M + 1.1, z + 2.0, "hierro")
        l.caja(c0 + 0.6, M + 1.1, z, c0 + 0.7, M + 1.6, z + 2.0, "cristal_lab")
    l.luz((c0 + c1) / 2, M + 3.2, (cz0 + cz1) / 2, FRIA, 0.9, 10.0)
    # LA CUPULA del telescopio (no se entra)
    u0, uz0, u1, uz1 = D.CUPULA
    ux, uz = (u0 + u1) / 2, (uz0 + uz1) / 2
    l.caja(u0, M, uz0, u1, M + 1.0, uz1, hl)
    l.cilindro(ux, M, uz, 7.0, 5.0, hl)
    l.elipsoide(ux, M + 5.0, uz, 7.0, 7.0, 7.0, "cupula_blanca")
    l.caja(ux - 0.7, M + 6.0, uz - 7.2, ux + 0.7, M + 12.3, uz - 2.0, "hierro")        # la raja, cerrada
    # EL PATIO DE LOS ESPEJOS: la pared sur hasta la sala de control y el muro de la estacion al norte
    p0, pz0, p1, pz1 = D.PATIO_ESPEJOS
    l.caja(p0, M, 62.0, 20.0, M + 4.0, 64.0, hl)
    wz0, wz1 = D.MURO_ESTACION_Z
    l.caja(p0, M, wz0, 55.4, M + 5.0, wz1, hl)
    g0, g1 = D.VERJA_ESTACION
    l.caja(g0, M, wz0 - 0.1, g1, M + 4.2, wz1 + 0.1, hl, hueco=True)
    l.caja(g0 - 0.6, M + 4.2, wz0 - 0.3, g1 + 0.6, M + 5.6, wz1 + 0.3, "chapa_estacion")
    ex, ez = D.EMISOR
    l.caja(ex - 0.8, M, ez - 0.8, ex + 0.8, M + 0.9, ez + 0.8, hl)                      # la peana del laser
    rx, rz = D.RECEPTOR
    l.caja(rx - 0.8, M + 0.6, wz0 - 0.4, rx + 0.8, M + 2.2, wz0, hl)                   # la peana del receptor
    for (x, z) in D.ESPEJOS:
        l.cilindro(x, M, z, 0.55, 0.6, hl)
    for x, z in ((10.0, 42.0), (48.0, 60.0), (20.0, 58.0)):
        P.farola(l, x, z, M)


# ======================================================================================================
# G. LA ESTACION DEL TELEFERICO
# ======================================================================================================
def estacion(l, rng, validacion):
    ce = "chapa_estacion"
    s0, sz0, s1, sz1 = D.SALA_MAQUINAS
    caja_hueca(l, s0, M, sz0, s1, M + 7.6, sz1, ce, 0.4, suelo="hormigon")
    l.caja(s0 - 0.6, M, sz0 + 2.0, s0 + 0.6, M + 7.2, sz1 - 2.0, ce, hueco=True)       # abierta al anden
    l.caja(s1 - 0.6, M, 12.0, s1 + 0.6, M + 3.4, 18.0, ce, hueco=True)                   # la puerta este
    l.caja(s0 - 0.8, M + 7.6, sz0 - 0.8, s1 + 0.8, M + 8.0, sz1 + 0.8, "chapa_ondulada")
    rx, ry, rz, rr = D.RUEDA
    l.cilindro(rx, M, rz, 0.9, ry - M - 0.3, "hierro")                                   # el eje de la rueda
    l.caja(rx - 3.0, M, rz - 0.6, rx + 3.0, M + 0.8, rz + 0.6, "hierro")
    if not validacion:
        h0, hz0, h1, hz1 = D.MURO_HIELO
        l.caja(h0, M, hz0, h1, M + D.MURO_HIELO_ALTO, hz1, "hielo_muro")
        l.elipsoide((h0 + h1) / 2, M + D.MURO_HIELO_ALTO, (hz0 + hz1) / 2, 1.2, 0.6, 3.6, "hielo_muro")
        for (a0, b0, a1, b1) in D.HIELOS:
            l.caja(a0, M, b0, a1, M + D.HIELO_ALTO, b1, "hielo_muro")
            l.elipsoide((a0 + a1) / 2, M + D.HIELO_ALTO, (b0 + b1) / 2, 1.5, 0.5, 1.5, "hielo_muro")
    # carambanos del alero de la sala
    for x in range(int(s0) + 1, int(s1), 2):
        l.cuna(x, M + 5.8, sz1 + 0.4, x + 0.4, M + 7.6, sz1 + 0.8, sube_hacia="+x", mat="hielo")
    # EL ANDEN y los cables (lo de fuera del mapa lo pinta el juego)
    a0, az0, a1, az1 = D.ANDEN
    l.caja(a0, M - 0.1, az0, a1, M, az1, "hormigon")
    l.caja(a0, M, az0 - 0.4, a1, M + 1.1, az0, "hierro")
    l.caja(a0, M, az1, a1, M + 1.1, az1 + 0.4, "hierro")
    for z in (D.CABINA[2] - 1.6, D.CABINA[2] + 1.6):
        l.linea(s0, D.CABLE_Y, z, -0.5, D.CABLE_Y, z, 0.12, "hierro")
    l.caja(a0, M + 7.0, az0, a1, M + 7.4, az1, ce)                                      # la marquesina
    for x in (a0 + 0.3, a1 - 0.3):
        for z in (az0 + 0.3, az1 - 0.3):
            l.caja(x - 0.15, M, z - 0.15, x + 0.15, M + 7.0, z + 0.15, "hierro")
    # la caseta del operador, el taller (el soplete es del juego) y los depositos de gasoil
    o0, oz0, o1, oz1 = D.CASETA_OPERADOR
    caja_hueca(l, o0, M, oz0, o1, M + 3.0, oz1, ce, 0.3, suelo="tablas")
    l.caja(o0 + 1.0, M + 1.2, oz0 - 0.1, o1 - 1.0, M + 2.4, oz0 + 0.4, "cristal_lab")
    t0, tz0, t1, tz1 = D.TALLER
    caja_hueca(l, t0, M, tz0, t1, M + 4.0, tz1, "chapa_ondulada", 0.3, suelo="hormigon")
    l.caja(t0 - 0.5, M, 25.0, t0 + 0.5, M + 2.8, 27.4, "chapa_ondulada", hueco=True)
    l.caja(t0 + 3.0, M, tz1 - 1.6, t1 - 1.0, M + 0.95, tz1 - 0.6, "tablas_oscuras")    # el banco del soplete
    l.caja(t1 - 1.2, M, tz0 + 0.6, t1 - 0.4, M + 2.0, tz0 + 4.0, "oxido")
    l.luz((t0 + t1) / 2, M + 3.4, (tz0 + tz1) / 2, CALIDA, 0.9, 9.0)
    for (x, z) in D.DEPOSITOS:
        l.cilindro(x, M, z, 1.6, 4.0, "chapa_roja")
        l.cilindro(x, M + 4.0, z, 0.3, 0.4, "hierro")
    l.luz(26.0, M + 6.8, 15.0, CALIDA, 0.9, 14.0)
    l.luz(10.0, M + 6.6, 16.0, FRIA, 0.8, 12.0)
    for x, z in ((38.6, 27.0), (30.0, 30.0)):
        P.farola(l, x, z, M)


def arboles(l, rng):
    for x, z in ((20.0, 31.0), (8.0, 6.0), (50.0, 6.0), (20.0, 50.0), (8.0, 58.0), (52.0, 50.0)):
        P.pino(l, x, z, M, rng, alto=rng.uniform(6.0, 9.0))
    for x, z in ((130.0, 80.0), (184.0, 82.0), (160.0, 82.5)):
        P.pino(l, x, z, G, rng, alto=rng.uniform(6.0, 9.0))


def construir(l, rng, validacion=False):
    terreno(l, validacion)
    lago(l, rng, validacion)
    pueblo(l, rng, validacion)
    mina(l, rng, validacion)
    carretera(l, rng, validacion)
    ventisca(l, rng, validacion)
    monasterio(l, rng, validacion)
    observatorio(l, rng, validacion)
    estacion(l, rng, validacion)
    arboles(l, rng)
    for p in D.RUTA:
        l.punto(p[0], p[1], p[2], "ruta")
    pts = [(120.0, G, 134.0), (140.0, G, 150.0), (160.0, G, 140.0), (180.0, G, 150.0), (170.0, G, 112.0),
           (140.0, G, 118.0), (180.0, G, 120.0), (136.0, G, 162.0), (186.0, G, 164.0),
           (150.0, G, 80.0), (168.0, G, 80.0), (184.0, G, 80.0),
           (183.0, 4.0, 56.0), (183.0, 4.6, 44.0), (183.0, 5.4, 28.0), (183.0, 6.0, 10.0), (172.0, 6.4, 11.0),
           (144.0, 8.1, 11.0), (136.0, 8.5, 11.0),
           (100.0, M, 8.0), (80.0, M, 8.0), (72.0, M, 24.0), (90.0, M, 24.0), (96.0, M, 38.0), (70.0, M, 38.0),
           (90.0, M, 50.0), (100.0, M, 52.0), (66.0, M, 52.0),
           (90.0, M, 66.0), (96.0, M, 76.0), (82.0, M, 76.0), (58.5, M, 62.0), (58.5, M, 80.0),
           (10.0, M, 44.0), (20.0, M, 54.0), (46.0, M, 58.0), (50.0, M, 40.0),
           (40.0, M, 28.0), (20.0, M, 30.0), (50.0, M, 8.0), (38.0, M, 8.0)]
    for x, y, z in pts:
        l.punto(x, y, z, "criatura")
