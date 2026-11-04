"""CONSTRUCCION del EPISODIO 5 "LA BASE AEREA" (campana_base). Ver disposicion.py para el recorrido y los puzzles.

De noche y con tormenta: el terraplen con la via volada, la refineria (tanques, rack de tuberias, la antorcha y la
ESFERA de propano), el canal con su puente colgante, el patio y el colector inundado, la obra con el edificio que se
demuele, y la base aerea (muro, caseta de guardia, campo de minas, hangar con puerta blindada, torre de control con su
radar y la pista). Lo que se mueve, explota o se dispara lo pone el juego (campana5.gd); aqui lo fijo y lo que se
rompe (la pared de la casa de bombas, el muro sur, el edificio, el muro de la base).

`validacion=True`: los puzzles resueltos para el A* (los huecos abiertos y un tablero de voxels en el puente).
"""
import math
import disposicion as D
import lienzo as L
import campana as K           # el kit del episodio 1 (mesa, cama...)
import presa as P             # las piezas del episodio 4 (casas, farolas, vias, barandillas, pinos...)

G = D.G

# ======================================================================================================
# MATERIALES
# ======================================================================================================
MATERIALES = dict(P.MATERIALES)


def _pat(nombre, patron, colores, tipo):
    MATERIALES[nombre] = (colores[0], tipo)
    L.PATRONES[nombre] = (patron, colores)


_pat("hormigon_militar", "sillar", [(118, 122, 108), (106, 110, 96), (128, 132, 116), (90, 94, 82), (80, 84, 72)], "hormigon")
_pat("asfalto_pista", "adoquin", [(46, 46, 48), (40, 40, 42), (52, 52, 54), (34, 34, 36)], "suelo_duro")
_pat("hierba_noche", "cesped", [(58, 74, 44), (50, 66, 38), (66, 82, 50), (70, 72, 44)], "suelo")
_pat("chapa_hangar", "lamas", [(96, 104, 92), (80, 88, 78)], "metal")
MATERIALES.update({
    "oliva": ((78, 86, 52), "metal"),
    "oliva_oscuro": ((58, 64, 40), "metal"),
    "acero_tanque": ((170, 172, 168), "metal"),
    "acero_esfera": ((214, 212, 204), "metal"),
    "negro_hollin": ((24, 22, 20), "tierra"),
    "tierra_quemada": ((54, 46, 38), "tierra"),
    "sacos_arena": ((140, 124, 88), "tela"),
    "alambre": ((70, 70, 72), "metal"),
    "luz_pista": ((255, 220, 140), "luz"),
})
CALIDA = (255, 190, 120)
FUEGO = (255, 120, 40)
FRIA = (190, 214, 255)
ROJA = (255, 50, 30)


def caja_hueca(l, x0, y0, z0, x1, y1, z1, mat, grosor=0.4, suelo=None, techo=True):
    """Un edificio de una pieza: caja maciza y el hueco de dentro (con o sin techo)."""
    l.caja(x0, y0, z0, x1, y1, z1, mat)
    l.caja(x0 + grosor, y0, z0 + grosor, x1 - grosor, y1 - (grosor if techo else -0.1), z1 - grosor, mat, hueco=True)
    if suelo:
        l.caja(x0 + grosor, y0 - 0.2, z0 + grosor, x1 - grosor, y0, z1 - grosor, suelo)


def alambrada(l, x0, z0, x1, z1, y, alto=3.2):
    """Valla de malla con postes y concertina arriba (los postes cada 2,5 m; la malla, una lamina fina)."""
    largo = math.hypot(x1 - x0, z1 - z0)
    n = max(1, int(largo / 2.5))
    for i in range(n + 1):
        t = i / n
        x, z = x0 + (x1 - x0) * t, z0 + (z1 - z0) * t
        l.caja(x - 0.06, y, z - 0.06, x + 0.06, y + alto + 0.4, z + 0.06, "hierro")
    if abs(x1 - x0) >= abs(z1 - z0):
        l.caja(x0, y, z0 - 0.02, x1, y + alto, z0 + 0.02, "alambre")
    else:
        l.caja(x0 - 0.02, y, z0, x0 + 0.02, y + alto, z1, "alambre")
    l.linea(x0, y + alto + 0.3, z0, x1, y + alto + 0.3, z1, 0.3, "alambre")


# ======================================================================================================
# EL TERRENO
# ======================================================================================================
def terreno(l, validacion):
    X, Z = D.ANCHO_X, D.ANCHO_Z
    l.caja(0, 0, 0, X, D.ROCA_Y, Z, "roca_base")
    l.caja(0, D.ROCA_Y, 0, X, G, Z, "tierra_monte")
    l.caja(0, G - 0.2, 0, X, G, Z, "hierba_noche")
    # las lomas que cierran el mapa: norte, oeste (con la boca del tunel), y el macizo del suroeste
    l.caja(0, G, 0, X, 12.0, 4.0, "roca")
    l.caja(0, G, 0, 4.0, 13.0, 62.0, "roca")
    l.caja(0, G, 56.0, 60.0, 9.0, 112.0, "roca")
    l.caja(0, G, 62.0, 60.0, 13.0, 110.0, "roca")
    l.caja(130.6, G, 4.0, X, 10.0, 60.8, "roca")
    l.caja(0, G, 157.0, X, 7.0, Z, "roca")
    l.caja(0, G, 112.0, 4.0, 8.0, 157.0, "roca")
    l.caja(172.0, G, 60.8, X, 9.0, 157.0, "roca")
    x = 4.0
    k = 0
    while x < X:                                          # la cresta del norte, dentada
        w = 5.0 + (k * 7) % 6
        l.caja(x, 12.0, 0, min(X, x + w), 12.0 + ((k * 5) % 4) * 1.1, 2.0 + (k % 3) * 0.6, "roca_gris")
        x += w
        k += 1
    # el tunel del tren (de ahi venia) en la ladera del oeste
    t0, tz0, t1, tz1 = D.TUNEL
    l.caja(0, D.TERRAPLEN_Y, tz0, t1 + 0.1, D.TERRAPLEN_Y + 5.5, tz1, "roca", hueco=True)
    l.caja(t1, D.TERRAPLEN_Y, tz0 - 1.0, t1 + 0.6, D.TERRAPLEN_Y + 6.8, tz0, "sillar_gris")
    l.caja(t1, D.TERRAPLEN_Y, tz1, t1 + 0.6, D.TERRAPLEN_Y + 6.8, tz1 + 1.0, "sillar_gris")
    l.caja(t1, D.TERRAPLEN_Y + 5.5, tz0 - 1.0, t1 + 0.6, D.TERRAPLEN_Y + 6.8, tz1 + 1.0, "sillar_gris")


# ======================================================================================================
# A. EL TERRAPLEN, EL TREN DESCARRILADO Y EL MORTERO
# ======================================================================================================
def descarrilamiento(l, rng, validacion):
    ty = D.TERRAPLEN_Y
    x0, z0, x1, z1 = D.TERRAPLEN
    l.caja(x0, G, 9.5, x1, ty, 12.5, "balasto")
    l.cuna(x0, G, z0, x1, ty, 9.5, sube_hacia="+z", mat="grava")
    l.cuna(x0, G, 12.5, x1, ty, z1, sube_hacia="-z", mat="grava")
    P.via(l, 0.0, D.VIA_Z, 44.0, D.VIA_Z, ty)
    # la VOLADURA: el crater en la via, los carriles retorcidos y el hollin
    v0, vz0, v1, vz1 = D.VOLADURA
    l.elipsoide((v0 + v1) / 2, ty, (vz0 + vz1) / 2, 4.5, 2.6, 4.0, "grava", hueco=True)
    l.elipsoide((v0 + v1) / 2, G - 0.2, (vz0 + vz1) / 2, 5.0, 0.3, 4.2, "negro_hollin")
    for s in (-0.5, 0.5):
        l.linea(44.0, ty + 0.18, D.VIA_Z + s, 47.0, ty + 1.5, D.VIA_Z + s * 3.0, 0.1, "hierro")
        l.linea(53.0, ty + 1.2, D.VIA_Z + s * 2.0, 58.0, ty + 0.18, D.VIA_Z + s, 0.1, "hierro")
    P.via(l, 55.0, D.VIA_Z, 60.0, D.VIA_Z, ty)
    l.escombros(50.0, 17.0, G, 3.0, 22, rng, mats=("grava", "hierro", "tablas_oscuras", "negro_hollin"))
    # el vagon cisterna que quedo contra el muro de la refineria (tapa la entrada de la via)
    l.cilindro(54.0, ty + 1.8, D.VIA_Z, 1.4, 5.8, "oxido", eje="x")
    l.caja(53.8, ty, D.VIA_Z - 1.2, 59.8, ty + 0.9, D.VIA_Z + 1.2, "hierro")
    # EL PUESTO DEL MORTERO: un monticulo con sacos terreros y cajas de municion
    m0, mz0, m1, mz1 = D.MONTICULO
    my = D.MONTICULO_Y
    l.caja(m0 + 3.0, G, mz0 + 3.0, m1 - 3.0, my, mz1 - 3.0, "tierra_monte")
    l.cuna(m0, G, mz0 + 3.0, m0 + 3.0, my, mz1 - 3.0, sube_hacia="+x", mat="tierra_monte")
    l.cuna(m1 - 3.0, G, mz0 + 3.0, m1, my, mz1 - 3.0, sube_hacia="-x", mat="tierra_monte")
    l.cuna(m0 + 3.0, G, mz0, m1 - 3.0, my, mz0 + 3.0, sube_hacia="+z", mat="tierra_monte")
    l.cuna(m0 + 3.0, G, mz1 - 3.0, m1 - 3.0, my, mz1, sube_hacia="-z", mat="tierra_monte")
    l.caja(m0 + 3.0, my - 0.2, mz0 + 3.0, m1 - 3.0, my, mz1 - 3.0, "hierba_noche")
    mx, _myy, mz = D.MORTERO
    for k in range(14):                                                   # el anillo de sacos
        a = k / 14 * math.tau
        if abs(math.sin(a)) < 0.35 and math.cos(a) < 0:                   # la entrada (al oeste)
            continue
        sx, sz = mx + math.cos(a) * 3.4, mz + math.sin(a) * 3.4
        l.caja(sx - 0.55, my, sz - 0.55, sx + 0.55, my + 1.0, sz + 0.55, "sacos_arena")
    for cx, cz in ((mx - 2.0, mz + 1.5), (mx - 2.2, mz + 0.6)):
        l.caja(cx - 0.35, my, cz - 0.25, cx + 0.35, my + 0.4, cz + 0.25, "oliva")
    P.cartel(l, mx + 1.6, my, mz - 2.6, mx + 2.8, my + 1.6, mz - 2.5, "cartel_blanco")   # la tabla de tiro
    # la refineria por fuera: el muro oeste con la CASA DE BOMBAS (su pared oeste es el blanco)
    wx = D.MURO_REFINERIA_X
    l.caja(wx, G - 0.2, 4.0, wx + 0.8, G + 4.5, 60.8, "hormigon_militar")
    b0, bz0, b1, bz1 = D.CASA_BOMBAS
    caja_hueca(l, b0, G, bz0, b1, G + 4.6, bz1, "ladrillo_visto", 0.5, suelo="suelo_hormigon")
    l.caja(wx - 0.1, G, bz0 + 0.5, wx + 0.9, G + 4.1, bz1 - 0.5, "ladrillo_visto", hueco=True)     # el muro, dentro
    l.caja(b1 - 0.6, G, 27.0, b1 + 0.1, G + 2.8, 31.0, "ladrillo_visto", hueco=True)               # a la refineria
    l.caja(b0 - 0.3, G + 4.6, bz0 - 0.3, b1 + 0.3, G + 4.9, bz1 + 0.3, "chapa_roja_ond")
    l.caja(b0 + 1.0, G, bz0 + 1.0, b0 + 3.0, G + 1.4, bz0 + 3.2, "acero_azul")                    # las bombas
    l.caja(b0 + 1.0, G, bz1 - 3.2, b0 + 3.0, G + 1.4, bz1 - 1.0, "acero_azul")
    l.caja(b0 - 0.02, G + 0.8, 28.0, b0, G + 2.6, 30.0, "peligro")                                 # la X del blanco
    if validacion:
        l.caja(b0 - 0.2, G, 27.0, b0 + 0.7, G + 2.8, 31.0, "ladrillo_visto", hueco=True)


# ======================================================================================================
# B. LA REFINERIA
# ======================================================================================================
def refineria(l, rng, validacion):
    r0, rz0, r1, rz1 = D.REFINERIA
    l.caja(r0 + 0.8, G - 0.2, rz0, r1, G, rz1, "suelo_hormigon")
    # los tanques con su cubeto (murete) y su escalera de caracol simplificada
    for tx, tz, tr, th in D.TANQUES:
        l.cilindro(tx, G, tz, tr + 2.0, 0.9, "hormigon_militar")
        l.cilindro(tx, G, tz, tr + 1.7, 0.95, "hormigon_militar", hueco=True)
        l.cilindro(tx, G, tz, tr, th, "acero_tanque")
        l.cilindro(tx, G + th, tz, tr + 0.1, 0.25, "hierro")
        l.elipsoide(tx, G + th + 0.2, tz, tr, 1.0, tr, "acero_tanque")
        for k in range(5):
            l.cilindro(tx, G + 1.5 + k * 2.0, tz, tr + 0.05, 0.15, "oxido")
        l.linea(tx + tr + 0.3, G, tz, tx + tr * 0.6, G + th, tz - tr * 0.8, 0.3, "hierro")
    # el rack de tuberias: porticos cada 4 m y tubos a lo largo (se pasa por debajo)
    rz0r, rz1r = D.RACK_Z
    for x in range(62, 129, 4):
        for z in (rz0r - 1.0, rz1r + 1.0):
            l.caja(x - 0.15, G, z - 0.15, x + 0.15, G + 6.0, z + 0.15, "acero_amarillo")
        l.caja(x - 0.15, G + 5.8, rz0r - 1.0, x + 0.15, G + 6.1, rz1r + 1.0, "acero_amarillo")
    for k, (dy, dz) in enumerate(((6.4, 31.6), (6.4, 32.6), (6.4, 33.6), (6.9, 32.0), (6.9, 33.2))):
        l.cilindro(62.0, G + dy, dz, 0.2 + (k % 2) * 0.1, 66.0, ("acero_azul", "oxido", "acero_verde")[k % 3], eje="x")
    # la ANTORCHA (la llama la pone el juego) y su escalera
    ax, az, ah = D.ANTORCHA
    l.cilindro(ax, G, az, 0.9, ah, "acero_tanque")
    for k in range(int(ah / 3)):
        l.cilindro(ax, G + 1.5 + k * 3.0, az, 1.0, 0.2, "peligro")
    l.cilindro(ax, G + ah, az, 1.2, 0.6, "negro_hollin")
    # la sala de control de la refineria y unas bombas
    caja_hueca(l, 66.0, G, 44.0, 76.0, G + 3.4, 54.0, "hormigon_militar", 0.35, suelo="baldosa")
    l.caja(76.0 - 0.4, G, 47.5, 76.1, G + 2.4, 49.5, "hormigon_militar", hueco=True)
    for x in (68.0, 71.0):
        l.caja(x, G, 44.6, x + 2.2, G + 1.1, 45.4, "acero_verde")
    for bx, bz in ((84.0, 44.0), (88.0, 44.0), (112.0, 44.0), (116.0, 48.0)):
        l.caja(bx - 0.8, G, bz - 0.6, bx + 0.8, G + 1.2, bz + 0.6, "acero_azul")
        l.cilindro(bx, G + 1.2, bz, 0.25, 1.2, "hierro")
    # LA ESFERA DE PROPANO sobre sus patas (voxels: la explosion se la come de verdad)
    ex, ey, ez, er = D.ESFERA
    l.esfera(ex, ey, ez, er, "acero_esfera")
    l.esfera(ex, ey, ez, er - 0.25, "acero_esfera", hueco=True)
    l.cilindro(ex, ey - 0.2, ez, er + 0.05, 0.4, "acero_azul")
    for k in range(8):
        a = k / 8 * math.tau
        px, pz = ex + math.cos(a) * er * 0.92, ez + math.sin(a) * er * 0.92
        l.caja(px - 0.25, G, pz - 0.25, px + 0.25, ey, pz + 0.25, "acero_azul")
    l.linea(ex + er * 0.9, G, ez, ex + 0.5, ey + er, ez, 0.2, "hierro")                       # la escalerilla
    # el tubo de la esfera al muro sur (en su brida esta la FUGA: la pone el juego)
    fx, fy, fz = D.FUGA
    l.linea(ex, ey - er + 0.2, ez + 1.0, ex, G + 0.3, ez + 3.0, 0.35, "acero_azul")          # baja al suelo
    l.linea(ex, G + 0.3, ez + 3.0, fx, G + 0.3, fz - 0.3, 0.35, "acero_azul")               # por el suelo
    l.linea(fx, G + 0.3, fz - 0.3, fx, fy, fz - 0.3, 0.35, "acero_azul")                     # y sube a la brida
    vx, _vy, vz = D.VALVULA_ESFERA
    l.caja(vx - 0.5, G, vz - 0.3, vx + 0.5, G + 0.9, vz + 0.3, "acero_azul")
    P.cartel(l, ex - 2.0, G + 2.2, ez - er - 0.6, ex + 2.0, G + 3.0, ez - er - 0.5, "cartel_amarillo")   # PELIGRO PROPANO
    # EL MURO SUR (lo revienta la esfera) y el muro este
    l.caja(r0, G - 0.2, D.MURO_SUR_Z, r1 + 0.6, G + 4.5, D.MURO_SUR_Z + 0.8, "hormigon_militar")
    l.caja(r1, G - 0.2, rz0, r1 + 0.6, G + 4.5, rz1 + 0.8, "hormigon_militar")
    if validacion:
        b0, b1 = D.BRECHA
        l.caja(b0, G, D.MURO_SUR_Z - 0.2, b1, G + 3.5, D.MURO_SUR_Z + 1.0, "hormigon_militar", hueco=True)
    # charcos de crudo ardiendo (la luz; el fuego lo pone el juego) y escombros
    for fx2, fz2 in ((72.0, 26.0), (110.0, 30.0), (90.0, 52.0)):
        l.elipsoide(fx2, G - 0.1, fz2, 2.2, 0.12, 1.6, "negro_hollin")
        l.luz(fx2, G + 1.2, fz2, FUEGO, 1.6, 12.0)
    l.escombros(84.0, 26.0, G, 2.0, 12, rng, mats=("hierro", "oxido", "hormigon_militar"))
    l.luz(ax, G + ah + 1.0, az, FUEGO, 2.5, 40.0)
    l.luz(71.0, G + 3.0, 49.0, CALIDA, 0.7, 7.0)


# ======================================================================================================
# C. EL CANAL, EL PUENTE Y LA VERJA
# ======================================================================================================
def canal(l, rng, validacion):
    c0, cz0, c1, cz1 = D.CANAL
    l.caja(c0, D.ROCA_Y, cz0, 172.0, G + 0.01, cz1, "roca", hueco=True)
    l.caja(c0, D.ROCA_Y, cz0, 172.0, D.ROCA_Y + 0.15, cz1, "arena_rio")
    l.caja(c0, D.ROCA_Y, cz0 - 0.4, 172.0, G, cz0, "sillar_gris")
    l.caja(c0, D.ROCA_Y, cz1, 172.0, G, cz1 + 0.4, "sillar_gris")
    l.caja(172.0, D.ROCA_Y, cz0, D.ANCHO_X, G + 1.0, cz1, "hormigon_militar")        # el azud del este
    # escalerillas en la orilla sur (quien caiga al canal sale por el lado de la verja)
    for x in (80.0, 118.0, 150.0):
        for k in range(10):
            yy = 0.8 + k * 0.25
            l.caja(x - 0.4, yy, cz1 - 0.12, x + 0.4, yy + 0.05, cz1, "hierro")
    # el puente: las torres (el tablero lo pone el juego)
    p0, pz0, p1, pz1 = D.PUENTE
    for zz in (pz0 - 0.4, pz1 + 0.4):
        for xx in (p0 - 0.4, p1 + 0.4):
            l.caja(xx - 0.3, G, zz - 0.3, xx + 0.3, G + 7.0, zz + 0.3, "acero_amarillo")
        l.caja(p0 - 0.7, G + 6.6, zz - 0.3, p1 + 0.7, G + 7.0, zz + 0.3, "acero_amarillo")
    # EL TABLERO, de voxels (las criaturas lo andan; al volar los anclajes el juego lo talla y lo tira)
    l.caja(p0, G + 0.1, pz0, p1, D.PUENTE_Y, pz1, "tablas")
    l.caja(p0, G, pz0 - 0.4, p1, G + 0.1, pz0 + 0.4, "tablas_oscuras")
    l.caja(p0, G, pz1 - 0.4, p1, G + 0.1, pz1 + 0.4, "tablas_oscuras")
    for xx in (p0, p1 - 0.06):
        l.caja(xx, D.PUENTE_Y, pz0, xx + 0.06, D.PUENTE_Y + 1.0, pz1, "alambre")
    # la valla del patio con el hueco de la verja (la hoja y el mando los pone el juego)
    vz = D.VALLA_Z
    v0, v1 = D.VERJA
    alambrada(l, 60.0, vz, v0, vz, G)
    alambrada(l, v1, vz, 122.0, vz, G)
    l.caja(v0 - 0.3, G, vz - 0.3, v0, G + 3.8, vz + 0.3, "hormigon_militar")
    l.caja(v1, G, vz - 0.3, v1 + 0.3, G + 3.8, vz + 0.3, "hormigon_militar")
    l.caja(v1 + 0.6, G, vz - 0.8, v1 + 1.4, G + 1.4, vz - 0.3, "acero_verde")                   # el cuadro
    # el muro de la obra a lo largo del canal (la obra solo se pisa saliendo del colector)
    l.caja(122.0, G - 0.2, cz1 + 0.4, 172.0, G + 4.5, cz1 + 1.4, "hormigon_militar")
    # farolas de la orilla
    for x in (70.0, 92.0, 124.0, 146.0):
        P.farola(l, x, cz0 - 1.2, G, luz=False)
    l.luz(105.0, G + 5.0, (pz0 + pz1) / 2, FRIA, 0.8, 14.0)


# ======================================================================================================
# D. EL PATIO Y EL COLECTOR INUNDADO
# ======================================================================================================
def patio_y_colector(l, rng, validacion):
    p0, pz0, p1, pz1 = D.PATIO
    l.caja(p0, G - 0.2, pz0, p1, G, pz1, "suelo_hormigon")
    l.caja(p0 - 0.6, G - 0.2, pz0, p0, G + 4.5, pz1 + 0.6, "hormigon_militar")          # oeste
    l.caja(p0 - 0.6, G - 0.2, pz1, 122.6, G + 4.5, pz1 + 0.6, "hormigon_militar")       # sur
    l.caja(122.0, G - 0.2, D.VALLA_Z, 122.6, G + 4.5, pz1 + 0.6, "hormigon_militar")    # este
    # contenedores y un camion viejo (se esconden los bichos)
    for cx, cz, mat in ((94.0, 82.0, "chapa_roja"), (94.0, 88.0, "acero_azul"), (104.0, 92.0, "oliva")):
        l.caja(cx, G, cz, cx + 6.0, G + 2.6, cz + 2.4, mat)
    l.caja(108.0, G, 80.0, 112.0, G + 2.2, 82.4, "oliva_oscuro")
    # EL POZO DE BAJADA y el colector (tubo de hormigon bajo el suelo, inundado: el agua es cosa del juego)
    a0, az0, a1, az1 = D.POZO_A
    b0, bz0, b1, bz1 = D.POZO_B
    c0, cz0, c1, cz1 = D.COLECTOR
    for q0, qz0, q1, qz1 in (D.POZO_A, D.POZO_B):
        l.caja(q0 - 0.4, D.ROCA_Y, qz0 - 0.4, q1 + 0.4, G, qz1 + 0.4, "hormigon_militar")
        l.caja(q0, D.ROCA_Y + 0.1, qz0, q1, G + 0.1, qz1, "hormigon_militar", hueco=True)
        P.barandilla(l, q0, qz1 - 0.05, q1, qz1, G, 1.0)
    l.caja(c0 - 0.4, D.ROCA_Y, cz0 - 0.4, c1 + 0.4, G, cz1 + 0.4, "hormigon_militar")
    l.caja(c0 - 0.1, D.ROCA_Y + 0.1, cz0, c1 + 0.1, D.COLECTOR_TECHO, cz1, "hormigon_militar", hueco=True)
    # las escaleras de los pozos: se baja/sube pegado a su lado norte
    l.escalera(a1 - 0.3, az0 + 0.1, D.ROCA_Y + 0.1, a1 - a0 - 0.3, 1.5, G - D.ROCA_Y - 0.1, hacia="-x", mat="hormigon_militar")
    l.escalera(b0 + 0.3, bz0 + 0.1, D.ROCA_Y + 0.1, b1 - b0 - 0.3, 1.5, G - D.ROCA_Y - 0.1, hacia="+x", mat="hormigon_militar")
    # LOS RESPIRADEROS: un pozo de registro con su escalon (subido a el, la cabeza queda fuera del agua) y la
    # rejilla arriba, sobre un brocal (por ahi no se sale)
    for x0, x1 in D.RESPIRADEROS:
        l.caja(x0 - 0.4, G, cz0 - 0.4, x1 + 0.4, G + 0.9, cz1 + 0.4, "hormigon_militar")
        l.caja(x0, D.COLECTOR_TECHO - 0.1, cz0, x1, G + 0.8, cz1, "hormigon_militar", hueco=True)
        l.caja(x0, D.ROCA_Y + 0.1, cz0, x1, D.ROCA_Y + 0.95, cz0 + 1.1, "hormigon_militar")        # el escalon
        xx = x0 + 0.1
        while xx < x1:
            l.caja(xx, G + 0.8, cz0 - 0.1, xx + 0.07, G + 0.9, cz1 + 0.1, "hierro")
            xx += 0.22
        l.luz((x0 + x1) / 2, G + 0.3, (cz0 + cz1) / 2, FRIA, 0.5, 5.0)
    # una lucecita roja al fondo de cada pozo
    l.luz((a0 + a1) / 2, 1.2, (az0 + az1) / 2, ROJA, 0.6, 5.0)
    l.luz((b0 + b1) / 2, 1.2, (bz0 + bz1) / 2, ROJA, 0.6, 5.0)


# ======================================================================================================
# E. LA OBRA Y EL EDIFICIO QUE SE DEMUELE
# ======================================================================================================
def obra(l, rng, validacion):
    o0, oz0, o1, oz1 = D.OBRA
    l.caja(o0, G - 0.2, oz0, o1, G, oz1, "grava")
    l.caja(172.0, G - 0.2, oz0, D.ANCHO_X, G + 5.0, oz1 + 1.0, "hormigon_militar")        # el borde este
    # EL EDIFICIO: tres plantas de hormigon con pilares, losas y cerramientos de ladrillo (se viene abajo)
    e0, ez0, e1, ez1 = D.EDIFICIO
    alto = D.EDIFICIO_PLANTAS * D.PISO
    for k in range(D.EDIFICIO_PLANTAS):
        y = G + k * D.PISO
        l.caja(e0, y + D.PISO - 0.3, ez0, e1, y + D.PISO, ez1, "suelo_hormigon")          # la losa de arriba
        l.caja(e0, y, ez0, e1, y + D.PISO - 0.3, ez0 + 0.3, "ladrillo_visto")             # cerramientos
        l.caja(e0, y, ez1 - 0.3, e1, y + D.PISO - 0.3, ez1, "ladrillo_visto")
        l.caja(e0, y, ez0, e0 + 0.3, y + D.PISO - 0.3, ez1, "ladrillo_visto")
        l.caja(e1 - 0.3, y, ez0, e1, y + D.PISO - 0.3, ez1, "ladrillo_visto")
        for x in range(int(e0) + 2, int(e1) - 1, 3):                                      # ventanas
            l.caja(x, y + 0.9, ez0 - 0.1, x + 1.4, y + 2.3, ez0 + 0.4, "ladrillo_visto", hueco=True)
            l.caja(x, y + 0.9, ez1 - 0.4, x + 1.4, y + 2.3, ez1 + 0.1, "ladrillo_visto", hueco=True)
    for x in (e0 + 0.3, (e0 + e1) / 2 - 0.25, e1 - 0.8):                                  # pilares
        for z in (ez0 + 0.3, ez1 - 0.8):
            l.caja(x, G, z, x + 0.5, G + alto, z + 0.5, "hormigon_militar")
    l.caja(e0 - 0.3, G + alto, ez0 - 0.3, e1 + 0.3, G + alto + 0.9, ez1 + 0.3, "hormigon_militar")
    l.caja(e0, G + alto, ez0, e1, G + alto + 0.9, ez1, "hormigon_militar", hueco=True)
    # la planta baja, tapiada (la obra: por dentro no se pasa)
    l.caja(e0 + 0.3, G, ez0 + 0.3, e1 - 0.3, G + D.PISO - 0.3, ez1 - 0.3, "ladrillo_visto", hueco=True)
    for x in range(int(e0) + 2, int(e1) - 1, 3):
        l.caja(x, G + 0.9, ez0 - 0.1, x + 1.4, G + 2.3, ez0 + 0.4, "tablas_oscuras")
        l.caja(x, G + 0.9, ez1 - 0.4, x + 1.4, G + 2.3, ez1 + 0.1, "tablas_oscuras")
    P.cartel(l, e0 + 4.0, G + alto + 0.2, ez0 - 0.45, e1 - 4.0, G + alto + 0.8, ez0 - 0.3, "cartel_amarillo")   # DEMOLICION
    # las franjas de las cargas en los pilares de la planta baja
    for x in (e0 + 0.3, (e0 + e1) / 2 - 0.25, e1 - 0.8):
        for z in (ez0 + 0.3, ez1 - 0.8):
            l.caja(x - 0.02, G + 1.0, z - 0.02, x + 0.52, G + 1.3, z + 0.52, "peligro")
    # el BUNKER DEL DETONADOR (con su tronera hacia el edificio)
    rb0, rbz0, rb1, rbz1 = D.REFUGIO_OBRA
    caja_hueca(l, rb0, G, rbz0, rb1, G + 3.0, rbz1, "hormigon_militar", 0.6, suelo="suelo_hormigon")
    l.caja(rb0 - 0.1, G, rbz0 + 2.0, rb0 + 0.7, G + 2.3, rbz0 + 3.6, "hormigon_militar", hueco=True)   # la puerta (oeste)
    l.caja(rb0 + 2.0, G + 1.4, rbz1 - 0.7, rb1 - 2.0, G + 1.8, rbz1 + 0.1, "hormigon_militar", hueco=True)  # la tronera
    for k in range(6):
        z = rbz0 + k * 1.2
        if z + 1.0 > rbz0 + 1.6 and z < rbz0 + 4.0:
            continue                                   # (delante de la puerta, nada)
        l.caja(rb0 - 0.8, G, z, rb0 - 0.1, G + 0.8, z + 1.0, "sacos_arena")
    l.luz((rb0 + rb1) / 2, G + 2.5, (rbz0 + rbz1) / 2, ROJA, 0.7, 7.0)
    # material de obra, una grua torre parada y una hormigonera
    for cx, cz in ((128.0, 92.0), (134.0, 100.0), (140.0, 88.0)):
        l.caja(cx, G, cz, cx + 2.4, G + 1.2, cz + 1.2, "tablas")
        l.caja(cx, G + 1.2, cz, cx + 2.4, G + 1.3, cz + 1.2, "chapa_ondulada")
    l.caja(128.0, G, 104.0, 128.8, G + 22.0, 104.8, "acero_amarillo")
    l.caja(118.0, G + 21.0, 104.0, 142.0, G + 21.8, 104.8, "acero_amarillo")
    l.caja(118.0, G + 18.0, 103.9, 121.0, G + 21.0, 104.9, "hormigon_militar")
    # EL MURO DE LA BASE (lo revienta la demolicion) con su concertina
    w0, w1 = D.MURO_BASE_Z
    l.caja(60.0, G - 0.2, w0, 172.0, G + 5.0, w1, "hormigon_militar")
    l.linea(60.0, G + 5.3, (w0 + w1) / 2, 172.0, G + 5.3, (w0 + w1) / 2, 0.4, "alambre")
    if validacion:
        l.caja(155.0, G, e0 * 0 + ez0 - 0.5, 159.5, G + alto + 1.0, ez1 + 0.5, "hormigon_militar", hueco=True)
        h0, h1 = D.HUECO_BASE
        l.caja(h0, G, w0 - 0.2, h1, G + 3.5, w1 + 0.2, "hormigon_militar", hueco=True)
    l.luz(157.0, G + 4.0, 93.0, CALIDA, 1.0, 16.0, (0, -1, 0.3), 50.0)


# ======================================================================================================
# F. LA BASE AEREA
# ======================================================================================================
def base(l, rng, validacion):
    b0, bz0, b1, bz1 = D.BASE
    l.caja(0, G - 0.2, bz0, D.ANCHO_X, G, 157.0, "suelo_hormigon")
    # la CASETA DE GUARDIA (refugio): entrada al norte, salida al oeste
    r0, rz0, r1, rz1 = D.REFUGIO
    caja_hueca(l, r0, G, rz0, r1, G + 3.4, rz1, "hormigon_militar", 0.4, suelo="baldosa")
    pnx, pnz = D.REFUGIO_PUERTA_N
    l.caja(pnx - 0.9, G, pnz - 0.5, pnx + 0.9, G + 2.7, pnz + 0.5, "hormigon_militar", hueco=True)
    pox, poz = D.REFUGIO_PUERTA_O
    l.caja(pox - 0.5, G, poz - 0.9, pox + 0.5, G + 2.7, poz + 0.9, "hormigon_militar", hueco=True)
    l.caja(r0 - 0.3, G + 3.4, rz0 - 0.3, r1 + 0.3, G + 3.6, rz1 + 0.3, "chapa_hangar")
    K.cama(l, r1 - 3.2, rz0 + 1.2, G, "x", rng)
    K.cama(l, r1 - 3.2, rz1 - 2.6, G, "x", rng)
    K.mesa(l, (r0 + r1) / 2, (rz0 + rz1) / 2, G)
    l.caja(r0 + 0.5, G, rz1 - 1.6, r0 + 2.0, G + 1.0, rz1 - 0.5, "oliva")
    l.luz((r0 + r1) / 2, G + 2.9, (rz0 + rz1) / 2, CALIDA, 1.0, 10.0)
    # la VALLA INTERIOR con el hueco de la verja (hoja y teclado: el juego) y el MASTIL de la baliza
    vx = D.VALLA_INTERIOR_X
    g0, g1 = D.VERJA_INTERIOR
    alambrada(l, vx, D.MURO_BASE_Z[1], vx, g0, G, 3.6)
    alambrada(l, vx, g1, vx, D.VALLA_PISTA_Z, G, 3.6)
    l.caja(vx - 0.3, G, g0 - 0.3, vx + 0.3, G + 4.0, g0, "hormigon_militar")
    l.caja(vx - 0.3, G, g1, vx + 0.3, G + 4.0, g1 + 0.3, "hormigon_militar")
    mx, mz, mh = D.MASTIL
    l.caja(mx - 0.2, G, mz - 0.2, mx + 0.2, G + mh, mz + 0.2, "peligro")
    l.caja(mx - 0.4, G + mh, mz - 0.4, mx + 0.4, G + mh + 0.2, mz + 0.4, "hierro")
    P.cartel(l, vx + 0.35, G + 2.2, g1 + 0.4, vx + 0.45, G + 3.0, g1 + 2.4, "cartel_amarillo")    # CODIGO: LA BALIZA
    # EL CAMPO DE MINAS: carteles de peligro en su borde (las minas las pone el juego)
    m0, mz0, m1, mz1 = D.MINAS
    for z in range(int(mz0) + 2, int(mz1), 6):
        l.caja(vx - 0.9, G, z, vx - 0.8, G + 1.4, z + 0.1, "hierro")
        l.caja(vx - 1.2, G + 1.0, z - 0.05, vx - 0.5, G + 1.5, z + 0.15, "chapa_roja")
    l.caja(m0, G - 0.2, mz0, m1, G, mz1, "tierra_quemada")
    for i in range(12):
        cx, cz = rng.uniform(m0 + 2, m1 - 2), rng.uniform(mz0 + 2, mz1 - 2)
        l.elipsoide(cx, G - 0.1, cz, rng.uniform(0.6, 1.3), 0.15, rng.uniform(0.6, 1.3), "negro_hollin")
    # EL HANGAR: nave de chapa de lado a lado (del muro de la base al delantal), la puerta blindada al este
    h0, hz0, h1, hz1 = D.HANGAR
    caja_hueca(l, h0, G, hz0, h1, G + 9.0, hz1, "chapa_hangar", 0.5, suelo="suelo_hormigon")
    for i in range(10):                                                                 # la boveda
        e = i * 1.0
        l.caja(h0 - 0.3, G + 9.0 + i * 0.35, hz0 + e, h1 + 0.3, G + 9.35 + i * 0.35, hz1 - e, "chapa_hangar")
    pb = D.PUERTA_BLINDADA
    l.caja(pb[0] - 0.8, G, pb[1], pb[2] + 0.2, G + 5.0, pb[3], "chapa_hangar", hueco=True)
    l.caja(pb[2], G, pb[1] - 1.0, pb[2] + 0.8, G + 6.0, pb[1], "hormigon_militar")
    l.caja(pb[2], G, pb[3], pb[2] + 0.8, G + 6.0, pb[3] + 1.0, "hormigon_militar")
    l.caja(pb[2], G + 5.0, pb[1] - 1.0, pb[2] + 0.8, G + 6.0, pb[3] + 1.0, "hormigon_militar")
    l.caja(h0 - 0.6, G, 122.0, h0 + 0.6, G + 4.5, 130.0, "chapa_hangar", hueco=True)                # oeste
    l.caja(66.0, G, hz1 - 0.6, 86.0, G + 6.0, hz1 + 0.6, "chapa_hangar", hueco=True)               # sur
    P.cartel(l, h0 + 8.0, G + 7.2, hz1 + 0.5, h1 - 8.0, G + 8.4, hz1 + 0.62, "cartel_blanco")      # HANGAR 3
    # dentro: un avion viejo desguazado, cajas y el taller
    l.caja(70.0, G, 124.0, 84.0, G + 2.6, 127.0, "acero_tanque")
    l.caja(75.0, G + 2.7, 116.5, 78.0, G + 3.0, 134.5, "acero_tanque")
    l.caja(82.0, G, 118.0, 86.0, G + 1.4, 120.0, "oliva")
    for x in range(64, 90, 8):
        l.luz(x + 2.0, G + 8.0, 127.0, CALIDA, 0.9, 14.0, (0, -1, 0), 55.0)
    # el cierre del delantal al este del hangar (a la pista solo se llega por dentro del hangar)
    alambrada(l, h1, hz1, h1, D.VALLA_PISTA_Z, G, 3.6)
    # LA TORRE DE CONTROL: un hueco de escalera (cuatro tramos pegados a las paredes, como la torre de toma del
    # episodio 4) y la azotea con el radar (lo pone el juego)
    t0, tz0, t1, tz1 = D.TORRE
    ty = D.TORRE_Y
    caja_hueca(l, t0, G, tz0, t1, ty, tz1, "hormigon_militar", 0.4, suelo="baldosa", techo=False)
    i0, iz0, i1, iz1 = t0 + 0.4, tz0 + 0.4, t1 - 0.4, tz1 - 0.4
    ph = (ty - G) / 4.0
    l.escalera(i1 - 2.0, iz0, G, (i1 - 2.0) - (i0 + 2.0), 2.0, ph, hacia="-x", mat="hormigon_militar")        # norte
    l.caja(i0, G + ph - 0.3, iz0, i0 + 2.0, G + ph, iz0 + 2.0, "suelo_hormigon")
    l.escalera(i0, iz0 + 2.0, G + ph, (iz1 - 2.0) - (iz0 + 2.0), 2.0, ph, hacia="+z", mat="hormigon_militar")  # oeste
    l.caja(i0, G + 2 * ph - 0.3, iz1 - 2.0, i0 + 2.0, G + 2 * ph, iz1, "suelo_hormigon")
    l.escalera(i0 + 2.0, iz1 - 2.0, G + 2 * ph, (i1 - 2.0) - (i0 + 2.0), 2.0, ph, hacia="+x", mat="hormigon_militar")  # sur
    l.caja(i1 - 2.0, G + 3 * ph - 0.3, iz1 - 2.0, i1, G + 3 * ph, iz1, "suelo_hormigon")
    l.escalera(i1 - 2.0, iz1 - 2.0, G + 3 * ph, (iz1 - 2.0) - (iz0 + 2.0), 2.0, ph, hacia="-z", mat="hormigon_militar")  # este
    # la azotea (con el hueco del ultimo tramo) y sus barandillas
    l.caja(i0, ty - 0.3, iz0, i1, ty, iz1, "suelo_hormigon")
    l.caja(i1 - 2.0, ty - 0.4, iz0 + 2.0, i1, ty + 0.1, iz1 - 2.0, "suelo_hormigon", hueco=True)
    P.barandilla(l, i1 - 2.1, iz0 + 2.0, i1 - 2.0, iz1 - 2.0, ty, 1.0)
    P.barandilla(l, t0, tz0, t1, tz0 + 0.06, ty, 1.1)
    P.barandilla(l, t0, tz1 - 0.06, t1, tz1, ty, 1.1)
    P.barandilla(l, t0, tz0, t0 + 0.06, tz1, ty, 1.1)
    P.barandilla(l, t1 - 0.06, tz0, t1, tz1, ty, 1.1)
    for k in range(4):                                                                   # ventanales
        y = G + k * ph + 1.2
        for x in range(int(t0) + 3, int(t1) - 1, 3):
            l.caja(x, y, tz1 - 0.3, x + 1.6, y + 1.4, tz1 + 0.05, "vidrio_ventana")
            l.caja(x, y, tz0 - 0.05, x + 1.6, y + 1.4, tz0 + 0.3, "vidrio_ventana")
    l.caja(t1 - 0.5, G, 123.0, t1 + 0.1, G + 2.7, 125.0, "hormigon_militar", hueco=True)            # la puerta (este)
    l.caja(t1, G, 122.4, t1 + 2.4, G + 0.2, 125.6, "suelo_hormigon")
    l.luz((t0 + t1) / 2, G + 3.0, (tz0 + tz1) / 2, FRIA, 0.6, 12.0)
    l.luz((t0 + t1) / 2, ty + 2.0, (tz0 + tz1) / 2, ROJA, 0.8, 10.0)
    # LA VALLA DE LA PISTA con su puerta abierta frente al hangar, y la PISTA
    vpz = D.VALLA_PISTA_Z
    alambrada(l, 0.0, vpz, 66.0, vpz, G)
    alambrada(l, 74.0, vpz, D.ANCHO_X, vpz, G)
    p0, pz0, p1, pz1 = D.PISTA
    l.caja(p0, G - 0.2, pz0, p1, G, pz1, "asfalto_pista")
    for x in range(4, int(p1) - 4, 12):                                                  # la linea central
        l.caja(x, G, (pz0 + pz1) / 2 - 0.2, x + 6.0, G + 0.01, (pz0 + pz1) / 2 + 0.2, "pintura_blanca")
    for z in (pz0 + 0.4, pz1 - 0.8):
        l.caja(p0, G, z, p1, G + 0.01, z + 0.4, "pintura_blanca")
    for x in (6.0, 160.0):                                                               # los umbrales
        for k in range(6):
            l.caja(x, G, pz0 + 1.6 + k * 1.5, x + 8.0, G + 0.01, pz0 + 2.3 + k * 1.5, "pintura_blanca")
    # el camion de combustible junto a la pista (se le dispara: la cisterna la pone tambien el juego como diana)
    c0, cz0, c1, cz1 = D.CAMION
    l.caja(c0, G + 0.5, cz0, c1 - 1.8, G + 1.0, cz1, "hierro")
    l.cilindro(c0 + 0.1, G + 1.9, (cz0 + cz1) / 2, 1.05, c1 - c0 - 2.0, "chapa_roja", eje="x")
    l.caja(c1 - 1.8, G + 0.5, cz0 + 0.1, c1, G + 2.6, cz1 - 0.1, "chapa_blanca")
    for x in (c0 + 0.8, c0 + 2.2, c1 - 0.8):
        for z in (cz0 + 0.1, cz1 - 0.35):
            l.cilindro(x, G + 0.5, z, 0.5, 0.25, "goma", eje="z")
    # focos de la base (los que barren los pone el juego) y farolas
    for x, z in ((20.0, 140.0), (60.0, 114.0), (120.0, 114.0), (170.0, 140.0)):
        l.caja(x - 0.2, G, z - 0.2, x + 0.2, G + 8.0, z + 0.2, "hierro")
        l.luz(x, G + 7.8, z, FRIA, 1.2, 22.0, (0, -1, 0.2), 45.0)
    for x in range(40, 170, 30):
        l.luz(x, G + 0.5, pz0 - 0.4, (255, 200, 90), 0.4, 5.0)


# ======================================================================================================
# LO QUE CRECE Y LOS PUNTOS
# ======================================================================================================
def bosque(l, rng):
    for _ in range(26):
        P.pino(l, rng.uniform(4, 56), rng.uniform(64, 108), 13.0, rng)
    for x in range(6, 170, 8):
        P.pino(l, x + rng.uniform(-1, 1), 158.4, 7.0, rng, alto=rng.uniform(6, 9))
    for z in range(8, 58, 7):
        P.pino(l, 2.0, z + rng.uniform(-1, 1), 13.0, rng, alto=rng.uniform(7, 10))
    for x in range(134, 172, 7):
        P.pino(l, x + rng.uniform(-1, 1), rng.uniform(10, 55), 10.0, rng)


def construir(l, rng, validacion=False):
    terreno(l, validacion)
    descarrilamiento(l, rng, validacion)
    refineria(l, rng, validacion)
    canal(l, rng, validacion)
    patio_y_colector(l, rng, validacion)
    obra(l, rng, validacion)
    base(l, rng, validacion)
    bosque(l, rng)
    for p in D.RUTA:
        l.punto(p[0], p[1], p[2], "ruta")
    for x, y, z in ((10.0, G, 20.0), (30.0, G, 24.0), (40.0, G, 44.0), (50.0, G, 50.0), (8.0, G, 48.0),
                    (70.0, G, 20.0), (86.0, G, 30.0), (112.0, G, 36.0), (124.0, G, 44.0), (80.0, G, 56.0),
                    (66.0, G, 38.0), (92.0, G, 8.0), (126.0, G, 14.0), (104.0, G, 26.0),
                    (70.0, G, 74.4), (90.0, G, 74.4), (120.0, G, 74.4),
                    (96.0, G, 85.0), (112.0, G, 94.0), (100.0, G, 78.0),
                    (130.0, G, 82.0), (140.0, G, 95.0), (150.0, G, 90.0), (170.0, G, 96.0), (160.0, G, 110.2),
                    (170.0, G, 116.0), (160.0, G, 130.0), (140.0, G, 138.0), (164.0, G, 122.0),
                    (120.0, G, 118.0), (110.0, G, 140.0), (130.0, G, 136.0),
                    (96.0, G, 118.0), (96.0, G, 138.0), (70.0, G, 120.0), (84.0, G, 134.0), (64.0, G, 132.0),
                    (50.0, G, 116.0), (20.0, G, 124.0), (50.0, G, 136.0), (10.0, G, 136.0),
                    (20.0, G, 146.0), (60.0, G, 150.0), (100.0, G, 150.0), (130.0, G, 146.0), (170.0, G, 150.0)):
        l.punto(x, y, z, "criatura")
