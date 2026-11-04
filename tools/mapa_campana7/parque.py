"""CONSTRUCCION del EPISODIO 7 "EL PARQUE" (campana_parque). Ver disposicion.py para el recorrido y los puzzles.

De noche y con neones: la estacion del teleferico reventada, el circo y el aparcamiento, la plaza de entrada con la
galeria de tiro y el tiovivo, la avenida con la base de la noria y la barricada, el laberinto de setos (los secos
arden), el lago con la isla de los cohetes, el botiquin (refugio), el pabellon de los autos de choque, la estacion de
la montaña rusa con sus pilares, la torre de caida con el tunel de servicio por debajo y el campo del globo.
Lo que se mueve, arde o explota lo pone el juego (campana7.gd): la carpa, el cañon, las dianas, la rueda de la
noria, el tren, el anillo de la torre, el globo.

`validacion=True`: los puzzles resueltos para el A* (la barricada abierta por donde pasa la rueda, los setos secos
quemados, un paso por el muro de la montaña rusa y el agujero de la torre).
"""
import math
import disposicion as D
import lienzo as L
import campana as K           # el kit del episodio 1 (mesa, cama...)
import presa as P             # las piezas del episodio 4 (casas, farolas, vias, pinos...)

G = D.G

# ======================================================================================================
# MATERIALES
# ======================================================================================================
MATERIALES = dict(P.MATERIALES)


def _pat(nombre, patron, colores, tipo):
    MATERIALES[nombre] = (colores[0], tipo)
    L.PATRONES[nombre] = (patron, colores)


_pat("cesped_noche", "cesped", [(46, 62, 38), (40, 56, 34), (54, 70, 44), (58, 60, 40)], "suelo")
_pat("adoquin_parque", "adoquin", [(112, 96, 100), (98, 84, 90), (124, 108, 110), (82, 70, 76)], "suelo_duro")
_pat("ladrillo_parque", "ladrillo", [(146, 70, 58), (130, 60, 50), (160, 82, 66), (112, 52, 44), (96, 88, 80)], "ladrillo")
_pat("seto", "cesped", [(34, 78, 38), (28, 68, 32), (42, 90, 44), (24, 60, 28)], "organico")
_pat("seto_seco", "cesped", [(134, 108, 52), (118, 92, 42), (150, 122, 62), (104, 80, 36)], "organico")
_pat("rayas_rojas", "rayas", [(196, 40, 44), (236, 228, 214)], "madera")
_pat("rayas_azules", "rayas", [(40, 90, 190), (236, 228, 214)], "madera")
_pat("rayas_amarillas", "rayas", [(230, 180, 40), (60, 40, 90)], "madera")
_pat("muro_pintado", "revoque", [(96, 60, 120), (86, 52, 110), (108, 70, 132), (70, 44, 90)], "ladrillo")
_pat("chapa_pista", "lamas", [(92, 94, 100), (74, 76, 82)], "metal")
_pat("asfalto", "adoquin", [(44, 44, 48), (38, 38, 42), (50, 50, 54), (34, 34, 38)], "suelo_duro")
MATERIALES.update({
    "chatarra": ((62, 44, 34), "metal"),
    "chatarra_osc": ((34, 28, 26), "metal"),
    "negro_hollin": ((24, 22, 20), "tierra"),
    "hormigon_parque": ((150, 146, 140), "hormigon"),
    "neon_rosa": ((255, 70, 200), "luz"),
    "neon_cian": ((60, 230, 255), "luz"),
    "neon_amarillo": ((255, 220, 70), "luz"),
    "madera_circo": ((150, 60, 40), "madera"),
    "dorado": ((210, 170, 60), "metal"),
    "lona": ((200, 190, 170), "tela"),
})
CALIDA = (255, 190, 120)
ROSA = (255, 80, 200)
CIAN = (80, 220, 255)
AMARILLO = (255, 210, 80)
FRIA = (190, 214, 255)


def caja_hueca(l, x0, y0, z0, x1, y1, z1, mat, grosor=0.4, suelo=None, techo=True):
    l.caja(x0, y0, z0, x1, y1, z1, mat)
    l.caja(x0 + grosor, y0, z0 + grosor, x1 - grosor, y1 - (grosor if techo else -0.1), z1 - grosor, mat, hueco=True)
    if suelo:
        l.caja(x0 + grosor, y0 - 0.2, z0 + grosor, x1 - grosor, y0, z1 - grosor, suelo)


def neon(l, x0, y0, z0, x1, y1, z1, mat, color, e=0.7, alcance=7.0):
    l.caja(x0, y0, z0, x1, y1, z1, mat)
    l.luz((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2, color, e, alcance)


def coche_quemado(l, x, z, rng, eje="x"):
    if eje == "x":
        l.caja(x - 2.1, G + 0.3, z - 0.9, x + 2.1, G + 1.2, z + 0.9, "chatarra")
        l.caja(x - 1.0, G + 1.2, z - 0.8, x + 1.1, G + 1.8, z + 0.8, "chatarra_osc")
    else:
        l.caja(x - 0.9, G + 0.3, z - 2.1, x + 0.9, G + 1.2, z + 2.1, "chatarra")
        l.caja(x - 0.8, G + 1.2, z - 1.0, x + 0.8, G + 1.8, z + 1.1, "chatarra_osc")
    l.elipsoide(x, G, z, 2.6, 0.06, 1.6, "negro_hollin")


def farola_neon(l, x, z, color, mat):
    l.caja(x - 0.08, G, z - 0.08, x + 0.08, G + 4.0, z + 0.08, "hierro")
    l.caja(x - 0.3, G + 4.0, z - 0.3, x + 0.3, G + 4.3, z + 0.3, mat)
    l.luz(x, G + 3.8, z, color, 0.9, 11.0, (0, -1, 0), 45.0)


# ======================================================================================================
# EL TERRENO Y LOS MUROS
# ======================================================================================================
def terreno(l, validacion):
    X, Z = D.ANCHO_X, D.ANCHO_Z
    l.caja(0, 0, 0, X, D.ROCA_Y, Z, "roca_base")
    l.caja(0, D.ROCA_Y, 0, X, G - 0.2, Z, "tierra_monte")
    l.caja(0, G - 0.2, 0, X, G, Z, "cesped_noche")
    # los bordes de fuera del parque: bosque y roca
    l.caja(0, G, 0, 2.0, 11.0, Z, "roca")
    l.caja(0, G, 0, 56.0, 9.0, 2.0, "roca")
    l.caja(0, G, Z - 2.0, 56.0, 9.0, Z, "roca")
    c0, cz0, c1, cz1 = D.CRESTA_W
    l.caja(c0, G, cz0, c1, 12.0, cz1, "roca")
    for i in range(12):
        l.elipsoide(4.0 + i * 4.4, 12.0, (cz0 + cz1) / 2, 3.0, 1.6, 6.5, "roca_gris")
    # EL MURO DEL PARQUE (ladrillo, con el porton y el arco de la entrada)
    p0, pz0, p1, pz1 = D.PARQUE
    h = D.MURO_ALTO
    l.caja(56.0, G, 0, p0, G + h, Z, "ladrillo_parque")
    l.caja(p0, G, 0, X, G + h, pz0, "ladrillo_parque")
    l.caja(p1, G, 0, X, G + h, Z, "ladrillo_parque")
    l.caja(p0, G, pz1, X, G + h, Z, "ladrillo_parque")
    g0, gz0, g1, gz1 = D.PORTON
    l.caja(g0 - 0.1, G, gz0, g1 + 0.1, G + 4.2, gz1, "ladrillo_parque", hueco=True)
    l.caja(g0 - 0.6, G, gz0 - 1.2, g1 + 0.6, G + 9.0, gz0, "ladrillo_parque")
    l.caja(g0 - 0.6, G, gz1, g1 + 0.6, G + 9.0, gz1 + 1.2, "ladrillo_parque")
    l.caja(g0 - 0.6, G + 7.0, gz0 - 1.2, g1 + 0.6, G + 9.0, gz1 + 1.2, "muro_pintado")
    neon(l, g0 - 0.7, G + 7.4, gz0 - 0.4, g0 - 0.6, G + 8.6, gz1 + 0.4, "neon_rosa", ROSA, 1.4, 16.0)
    # LOS MUROS DE DENTRO (pintados), con sus huecos
    hi = D.MURO_INT_ALTO
    s0, s1 = D.SN_Z
    l.caja(p0, G, s0, p1, G + hi, s1, "muro_pintado")
    l.caja(D.SALIDA_LAB[0], G, s0 - 0.1, D.SALIDA_LAB[1], G + 4.0, s1 + 0.1, "muro_pintado", hueco=True)
    a0, a1 = D.AB_X
    b0, b1 = D.BC_X
    l.caja(a0, G, s1, a1, G + hi, pz1, "muro_pintado")
    l.caja(a0 - 0.1, G, D.PUERTA_SERVICIO[0], a1 + 0.1, G + 3.6, D.PUERTA_SERVICIO[1], "muro_pintado", hueco=True)
    l.caja(b0, G, s1, b1, G + hi, pz1, "muro_pintado")
    l.caja(b0 - 0.1, G, D.PASO_AVENIDA[0], b1 + 0.1, G + 4.5, D.PASO_AVENIDA[1], "muro_pintado", hueco=True)
    l.caja(a0, G, pz0, a1, G + hi, s0, "muro_pintado")
    if validacion:
        l.caja(a0 - 0.1, G, 20.0, a1 + 0.1, G + 3.0, 24.0, "muro_pintado", hueco=True)      # (el tren, para el A*)
    l.caja(b0, G, pz0, b1, G + hi, s0, "muro_pintado")
    # los caminos del parque (adoquin)
    l.caja(p0, G - 0.2, s1, a0, G, pz1, "adoquin_parque")
    l.caja(a1, G - 0.2, D.AVENIDA[1], b0, G, D.AVENIDA[3], "adoquin_parque")
    l.caja(b1, G - 0.2, D.PLAZA_LAGO[1], p1, G, s0, "adoquin_parque")
    l.caja(p0, G - 0.2, pz0, a0, G, s0, "adoquin_parque")


# ======================================================================================================
# FUERA: la estacion estrellada, el circo, el aparcamiento y el campo del globo
# ======================================================================================================
def fuera(l, rng, validacion):
    # la estacion de abajo del teleferico, reventada
    e0, ez0, e1, ez1 = D.ESTACION_TELEF
    caja_hueca(l, e0, G, ez0, e1, G + 7.0, ez1, "hormigon_parque", 0.5, suelo="hormigon", techo=False)
    l.caja(e0, G + 6.6, ez0, e1 - 7.0, G + 7.0, ez1, "hormigon_parque")
    l.elipsoide(e1 - 3.0, G + 7.0, ez0 + 8.0, 6.0, 5.0, 6.0, "hormigon_parque", hueco=True)
    l.elipsoide(e1, G + 3.0, ez0 + 8.0, 2.4, 3.0, 3.0, "hormigon_parque", hueco=True)
    l.escombros(e1 + 2.0, ez0 + 8.0, G, 3.5, 30, rng, mats=("hormigon_parque", "hierro", "chatarra"))
    for dz in (-1.6, 1.6):
        l.linea(e0 + 4.0, G + 7.5, (ez0 + ez1) / 2 + dz, 0.5, G + 16.0, (ez0 + ez1) / 2 + dz, 0.12, "hierro")
    l.caja(e0 + 1.0, G, ez0 + 1.0, e0 + 3.0, G + 5.0, ez0 + 3.0, "hierro")               # la rueda de abajo
    # EL CIRCO: la pista (serrin), las gradas y los carromatos. La carpa y el cañon son del juego.
    cx, cz, cr = D.CARPA
    l.cilindro(cx, G - 0.05, cz, cr - 3.0, 0.1, "serrin")
    l.cilindro(cx, G, cz, cr - 3.0, 0.5, "madera_circo")
    l.cilindro(cx, G, cz, cr - 3.4, 0.6, "madera_circo", hueco=True)
    for i in range(3):
        r = cr - 2.4 + i * 0.7
        for k in range(10):
            a = k / 10 * math.tau
            if abs(math.cos(a)) > 0.9 and math.cos(a) > 0:
                continue                                            # el lado del cañon (al este) sin gradas
            x, z = cx + math.cos(a) * r, cz + math.sin(a) * r
            l.caja(x - 1.4, G, z - 1.4, x + 1.4, G + 0.5 + i * 0.5, z + 1.4, "tablas_oscuras")
    for i, (x, z) in enumerate([(8.0, 104.0), (8.0, 114.0), (8.0, 128.0), (50.0, 140.0), (46.0, 100.0)]):
        mat = ("rayas_rojas", "rayas_azules", "rayas_amarillas")[i % 3]
        l.caja(x - 2.2, G + 0.6, z - 1.3, x + 2.2, G + 3.0, z + 1.3, mat)
        l.caja(x - 2.3, G + 3.0, z - 1.4, x + 2.3, G + 3.3, z + 1.4, "tablas_oscuras")
        for dx in (-1.5, 1.5):
            l.cilindro(x + dx, G + 0.5, z - 1.35, 0.5, 0.2, "tablas_oscuras", eje="z")
            l.cilindro(x + dx, G + 0.5, z + 1.15, 0.5, 0.2, "tablas_oscuras", eje="z")
    # EL APARCAMIENTO: coches quemados y farolas
    l.caja(2.0, G - 0.2, 138.0, 56.0, G, 164.4, "asfalto")
    for i in range(10):
        x = 6.0 + (i % 5) * 9.0 + rng.uniform(-1, 1)
        z = 142.0 if i < 5 else 146.0 + 10.0
        if abs(x - D.SPAWN_JUGADOR[0]) < 4.0 and abs(z - D.SPAWN_JUGADOR[2]) < 4.0:
            continue
        coche_quemado(l, x, z + rng.uniform(-1, 1), rng, "z")
    for x, z in ((12.0, 138.0), (40.0, 138.0), (50.0, 118.0), (50.0, 104.0)):
        farola_neon(l, x, z, CALIDA, "vidrio_ventana")
    # EL CAMPO DEL GLOBO: la plataforma, la taquilla y la valla
    gx, gz = D.GLOBO
    l.cilindro(gx, G, gz, 5.0, 0.25, "tablas")
    l.caja(8.0, G, 60.0, 14.0, G + 3.0, 66.0, "rayas_azules")
    l.caja(7.8, G + 3.0, 59.8, 14.2, G + 3.3, 66.2, "tablas_oscuras")
    for x, z in ((12.0, 20.0), (40.0, 20.0), (12.0, 60.0), (44.0, 60.0)):
        farola_neon(l, x, z, CALIDA, "vidrio_ventana")
    for i in range(18):
        x, z = rng.uniform(4.0, 54.0), rng.uniform(4.0, 82.0)
        if math.hypot(x - gx, z - gz) < 14.0 or (40.0 < x < 56.0 and 40.0 < z < 52.0):
            continue
        P.pino(l, x, z, G, rng, alto=rng.uniform(7.0, 11.0))
    for i in range(8):
        x, z = rng.uniform(4.0, 54.0), rng.uniform(98.0, 136.0)
        if math.hypot(x - cx, z - cz) < cr + 3.0 or math.hypot(x - 50.0, z - 104.0) < 4.0:
            continue
        P.pino(l, x, z, G, rng, alto=rng.uniform(7.0, 10.0))


# ======================================================================================================
# SA: LA PLAZA DE ENTRADA (galeria de tiro, tiovivo, taquillas)
# ======================================================================================================
def plaza(l, rng, validacion):
    # la GALERIA DE TIRO: caseta abierta al norte, con mostrador (los patos son del juego)
    x0, z0, x1, z1 = D.GALERIA
    l.caja(x0, G, z0, x1, G + 4.2, z1, "rayas_rojas")
    l.caja(x0 + 0.4, G, z0 - 0.1, x1 - 0.4, G + 3.8, z1 - 0.4, "rayas_rojas", hueco=True)
    l.caja(x0 - 0.3, G + 4.2, z0 - 0.8, x1 + 0.3, G + 4.6, z1 + 0.3, "rayas_amarillas")
    l.caja(x0 + 0.4, G, D.MOSTRADOR_Z - 0.2, x1 - 0.4, G + 1.1, D.MOSTRADOR_Z + 0.2, "madera_circo")
    for zz, yy in ((D.DIANAS_GALERIA_Z + 0.4, 1.2), (D.DIANAS_GALERIA_Z + 0.4, 1.9), (D.DIANAS_GALERIA_Z + 0.4, 2.6)):
        l.caja(x0 + 0.5, G + yy - 0.45, zz, x1 - 0.5, G + yy - 0.35, zz + 0.3, "hierro")
    l.caja(x0 + 0.5, G + 0.2, z1 - 0.5, x1 - 0.5, G + 3.6, z1 - 0.4, "muro_pintado")
    neon(l, x0 + 1.0, G + 4.3, z0 - 0.7, x1 - 1.0, G + 4.5, z0 - 0.6, "neon_amarillo", AMARILLO, 1.2, 12.0)
    # el TIOVIVO (sin caballos: se los llevo alguien) con su toldo
    tx, tz, tr = D.TIOVIVO
    l.cilindro(tx, G, tz, tr, 0.5, "madera_circo")
    l.cilindro(tx, G + 0.5, tz, 0.6, 5.0, "dorado")
    for k in range(12):
        a = k / 12 * math.tau
        l.cilindro(tx + math.cos(a) * (tr - 0.8), G + 0.5, tz + math.sin(a) * (tr - 0.8), 0.07, 4.2, "dorado")
    for i in range(6):
        r = tr + 0.4 - i * 1.1
        l.cilindro(tx, G + 4.7 + i * 0.35, tz, max(0.6, r), 0.35, "rayas_rojas" if i % 2 == 0 else "rayas_amarillas")
    l.luz(tx, G + 4.2, tz, AMARILLO, 1.2, 12.0)
    # las taquillas junto al porton y los bancos
    for z in (98.0, 116.0):
        l.caja(59.0, G, z - 2.0, 63.0, G + 3.0, z + 2.0, "rayas_azules")
        l.caja(58.8, G + 3.0, z - 2.2, 63.2, G + 3.3, z + 2.2, "tablas_oscuras")
    for x, z, c, m in ((66.0, 90.0, ROSA, "neon_rosa"), (88.0, 90.0, CIAN, "neon_cian"), (66.0, 140.0, CIAN, "neon_cian"),
                       (90.0, 140.0, ROSA, "neon_rosa"), (70.0, 110.0, AMARILLO, "neon_amarillo")):
        farola_neon(l, x, z, c, m)
    for x, z in ((70.0, 124.0), (88.0, 112.0), (88.0, 134.0)):
        P.banco(l, x, z, G, "x")


# ======================================================================================================
# SB: LA AVENIDA, LA NORIA Y LA BARRICADA
# ======================================================================================================
def avenida(l, rng, validacion):
    nx, ny, nz, nr = D.NORIA
    # la base de la noria y sus dos caballetes (la rueda es del juego)
    l.caja(nx - 7.0, G, nz - 7.0, nx + 7.0, G + 0.5, nz + 7.0, "hormigon_parque")
    for z in (nz - 4.7, nz + 4.7):
        l.linea(nx - 5.5, G + 0.5, z, nx, ny, z, 0.7, "acero_azul")
        l.linea(nx + 5.5, G + 0.5, z, nx, ny, z, 0.7, "acero_azul")
        l.linea(nx - 3.0, G + 6.0, z, nx + 3.0, G + 6.0, z, 0.4, "acero_azul")
    l.caja(nx - 1.5, G + 0.5, nz - 7.0, nx + 1.5, G + 3.0, nz - 4.0, "rayas_azules")          # la caseta del operador
    # la BARRICADA: coches quemados, sacos y un cartel caido, de pared a pared
    b0, bz0, b1, bz1 = D.BARRICADA
    for k in range(4):
        coche_quemado(l, (b0 + b1) / 2 + (k % 2) * 1.2 - 0.6, bz0 + 2.0 + k * 4.0, rng, "x")
        l.caja(b0 + 0.5, G + 1.8, bz0 + 0.4 + k * 4.0, b1 - 0.5, G + 3.2, bz0 + 3.6 + k * 4.0, "chatarra_osc")
    l.caja(b0 + 1.0, G, bz0, b0 + 2.0, G + 1.2, bz1, "sacos")
    l.caja(b0 + 2.0, G, bz0, b1 - 1.0, G + 1.8, bz1, "chatarra")
    l.linea(b0 - 1.0, G + 0.2, bz0 + 1.0, b1 + 1.0, G + 3.6, bz1 - 1.0, 0.4, "rayas_amarillas")
    # y vallas de obra de muro a muro (sin ellas se rodeaba la barricada por detras de los recreativos)
    l.caja(119.4, G, D.SN_Z[1], 120.4, G + 3.4, bz0, "chapa_ondulada")
    l.caja(119.4, G, bz1, 120.4, G + 3.4, D.PARQUE[3], "chapa_ondulada")
    if validacion:
        l.caja(b0 - 0.5, G, nz - 1.8, b1 + 0.5, G + 4.5, nz + 1.8, "chatarra", hueco=True)      # por donde pasa la rueda
    # los edificios de la avenida: los recreativos (norte) y el restaurante (sur), y quioscos
    caja_hueca(l, 100.0, G, 86.0, 136.0, G + 8.0, 110.0, "muro_pintado", 0.5)
    neon(l, 104.0, G + 6.0, 109.9, 132.0, G + 7.0, 110.1, "neon_cian", CIAN, 1.4, 16.0)
    caja_hueca(l, 100.0, G, 140.0, 136.0, G + 7.0, 163.0, "ladrillo_parque", 0.5)
    neon(l, 104.0, G + 5.2, 139.9, 132.0, G + 6.0, 140.1, "neon_rosa", ROSA, 1.4, 16.0)
    for x in (112.0, 128.0):
        for z, m in ((113.0, "rayas_rojas"), (135.0, "rayas_amarillas")):
            l.caja(x - 1.8, G, z - 1.4, x + 1.8, G + 2.8, z + 1.4, m)
            l.caja(x - 2.0, G + 2.8, z - 1.6, x + 2.0, G + 3.1, z + 1.6, "tablas_oscuras")
    for x in (100.0, 120.0, 136.0):
        farola_neon(l, x, 116.6, AMARILLO, "neon_amarillo")
        farola_neon(l, x, 131.4, ROSA, "neon_rosa")


# ======================================================================================================
# SC: EL LABERINTO DE SETOS
# ======================================================================================================
def laberinto(l, rng, validacion):
    l0, lz0, l1, lz1 = D.LAB
    l.caja(l0, G - 0.2, lz0, l1, G, lz1, "cesped_noche")
    for (x0, z0, x1, z1, seco, corte) in D.SETOS:
        if validacion and seco:
            continue                                                  # (quemados)
        l.caja(x0, G, z0, x1, G + D.SETO_ALTO, z1, "seto_seco" if seco else "seto")
    # las farolas del laberinto (bajitas) y el arco de la entrada
    for (c, f) in D.CAMINO_LAB[::9]:
        x0, z0, x1, z1 = D.lab_celda(c, f)
        l.luz((x0 + x1) / 2, G + 2.4, (z0 + z1) / 2, (120, 255, 150), 0.5, 7.0)
    b0, b1 = D.BC_X
    z0, z1 = D.PASO_AVENIDA
    neon(l, b0 - 0.2, G + 4.6, z0, b1 + 0.2, G + 5.2, z1, "neon_cian", CIAN, 1.0, 12.0)


# ======================================================================================================
# NC: EL LAGO, LA ISLA DE LOS COHETES, LA PLAZA Y EL REFUGIO
# ======================================================================================================
def lago(l, rng, validacion):
    x0, z0, x1, z1 = D.LAGO
    l.caja(x0, 0.6, z0, x1, G, z1, "tierra_monte", hueco=True)
    l.caja(x0, 0.4, z0, x1, 0.6, z1, "grava")
    l.caja(x0 - 0.5, G - 0.4, z1, x1, G + 0.3, z1 + 0.6, "sillar_gris")                  # el pretil
    l.caja(x0 - 0.5, G - 0.4, z0, x0, G + 0.3, z1, "sillar_gris")
    i0, iz0, i1, iz1 = D.ISLA
    l.caja(i0, 0.6, iz0, i1, G + 0.3, iz1, "cesped_noche")
    cx, cy, cz = D.COHETES
    for k in range(5):
        l.linea(cx - 3.0 + k * 1.5, G + 0.3, cz - 1.0, cx - 3.0 + k * 1.5, G + 2.2, cz + 0.5, 0.15, "hierro")
    l.caja(cx - 3.5, G + 0.3, cz - 1.5, cx + 3.5, G + 0.7, cz + 1.5, "madera_circo")
    # la caseta de las barcas (medio en el agua)
    e0, ez0, e1, ez1 = D.EMBARCADERO
    l.caja(e0, G - 0.2, ez0, e1, G + 0.1, ez1, "tablas_oscuras")
    caja_hueca(l, e0 + 1.0, G + 0.1, ez0 + 3.0, e1 - 0.5, G + 3.6, ez1, "tablas", 0.3)
    l.caja(e0 + 0.5, G + 3.6, ez0 + 2.5, e1, G + 4.0, ez1 + 0.3, "teja")
    for k in range(3):
        l.caja(e0 + 1.0 + k * 2.6, 2.0, ez0 - 4.0, e0 + 2.6 + k * 2.6, 2.5, ez0 - 1.0, "madera_circo")
    # la caseta de los fuegos artificiales (el mando es del juego)
    fx, fy, fz = D.CASETA_FUEGOS
    caja_hueca(l, fx - 2.5, G, fz - 2.0, fx + 3.0, G + 3.0, fz + 2.5, "rayas_azules", 0.3, techo=True)
    l.caja(fx - 2.6, G, fz - 1.0, fx - 2.2, G + 2.4, fz + 1.0, "rayas_azules", hueco=True)
    neon(l, fx - 2.4, G + 3.0, fz - 1.8, fx - 2.2, G + 3.5, fz + 1.8, "neon_amarillo", AMARILLO, 1.0, 10.0)
    # EL REFUGIO: el botiquin del parque (entrada al norte, salida al oeste por el muro)
    r0, rz0, r1, rz1 = D.REFUGIO
    caja_hueca(l, r0, G, rz0, r1, G + 3.6, rz1, "hormigon_parque", 0.4, suelo="baldosa")
    pnx, pnz = D.REFUGIO_PUERTA_N
    l.caja(pnx - 0.9, G, pnz - 0.6, pnx + 0.9, G + 2.7, pnz + 0.6, "hormigon_parque", hueco=True)
    pox, poz = D.REFUGIO_PUERTA_O
    l.caja(D.BC_X[0] - 0.3, G, poz - 0.9, pox + 0.6, G + 2.7, poz + 0.9, "hormigon_parque", hueco=True)
    l.caja(r0 - 0.3, G + 3.6, rz0 - 0.3, r1 + 0.3, G + 3.9, rz1 + 0.3, "chapa_roja")
    K.cama(l, r1 - 3.0, rz0 + 1.2, G, "x", rng)
    K.cama(l, r1 - 3.0, rz1 - 2.6, G, "x", rng)
    K.mesa(l, (r0 + r1) / 2 + 1.0, (rz0 + rz1) / 2, G)
    l.luz((r0 + r1) / 2, G + 3.0, (rz0 + rz1) / 2, CALIDA, 1.0, 10.0)
    neon(l, pnx - 1.0, G + 3.0, rz0 - 0.2, pnx + 1.0, G + 3.4, rz0 - 0.1, "neon_rosa", (255, 60, 60), 1.0, 8.0)
    for x, z, c, m in ((150.0, 50.0, CIAN, "neon_cian"), (170.0, 60.0, ROSA, "neon_rosa"), (160.0, 78.0, AMARILLO, "neon_amarillo")):
        farola_neon(l, x, z, c, m)


# ======================================================================================================
# NB: EL PABELLON DE LOS AUTOS DE CHOQUE Y LA ESTACION DE LA MONTAÑA RUSA
# ======================================================================================================
def pabellon(l, rng, validacion):
    p0, pz0, p1, pz1 = D.PABELLON
    alto = 7.0
    l.caja(p0, G, pz0, p1, G + alto, pz0 + 0.6, "muro_pintado")
    l.caja(D.PERSIANA_N[0], G, pz0 - 0.1, D.PERSIANA_N[1], G + 4.2, pz0 + 0.7, "muro_pintado", hueco=True)
    l.caja(p0, G + alto, pz0, p1, G + alto + 0.3, D.SN_Z[0], "chapa_ondulada")
    for x in range(int(p0) + 4, int(p1), 6):
        l.caja(x, G + alto - 0.05, pz0 + 4.0, x + 2.0, G + alto + 0.35, D.SN_Z[0] - 4.0, "vidrio_ventana")
    # la pasarela alrededor de la pista (a 1 m) y la pista de chapa
    a0, az0, a1, az1 = D.PISTA_CHOQUE
    l.caja(p0, G, pz0 + 0.6, p1, D.PASARELA_Y, D.SN_Z[0], "hormigon_parque")
    l.caja(a0, G, az0, a1, D.PASARELA_Y + 0.1, az1, "hormigon_parque", hueco=True)
    l.caja(a0, G - 0.1, az0, a1, G + 0.1, az1, "chapa_pista")
    P.barandilla(l, a0, az0 - 0.05, a1, az0 + 0.05, D.PASARELA_Y, 1.0)
    P.barandilla(l, a0, az1 - 0.05, a1, az1 + 0.05, D.PASARELA_Y, 1.0)
    P.barandilla(l, a0 - 0.05, az0, a0 + 0.05, az0 + 8.0, D.PASARELA_Y, 1.0)
    P.barandilla(l, a0 - 0.05, az1 - 8.0, a0 + 0.05, az1, D.PASARELA_Y, 1.0)
    P.barandilla(l, a1 - 0.05, az0 + 4.0, a1 + 0.05, az1, D.PASARELA_Y, 1.0)
    zm = (az0 + az1) / 2                                                                         # escalones a la pista
    l.escalera(a0 + 2.0, zm - 1.0, G, 2.0, 2.0, 1.0, hacia="-x", mat="hormigon_parque")
    l.escalera(a1 - 2.0, az0 + 1.0, G, 2.0, 2.0, 1.0, hacia="+x", mat="hormigon_parque")
    # la muesca de la salida del refugio (a ras de suelo) con su escalera a la pasarela
    poz = D.REFUGIO_PUERTA_O[1]
    l.caja(135.0, G, poz - 2.0, p1, D.PASARELA_Y + 0.1, poz + 2.0, "hormigon_parque", hueco=True)
    l.escalera(137.0, poz - 2.0, G, 2.0, 4.0, 1.0, hacia="-x", mat="hormigon_parque")
    # los autos de choque (voxels: se quedan donde estaban)
    for i in range(12):
        x, z = rng.uniform(a0 + 2.0, a1 - 2.0), rng.uniform(az0 + 2.0, az1 - 2.0)
        m = ("rayas_rojas", "rayas_azules", "rayas_amarillas")[i % 3]
        l.caja(x - 1.0, G + 0.1, z - 0.7, x + 1.0, G + 0.6, z + 0.7, "goma")
        l.caja(x - 0.8, G + 0.6, z - 0.55, x + 0.8, G + 1.0, z + 0.55, m)
        l.linea(x + 0.6, G + 1.0, z, x + 0.6, G + 6.6, z, 0.06, "hierro")
    # la reja del techo (la que da la corriente)
    for x in range(int(a0), int(a1) + 1, 3):
        l.caja(x - 0.05, G + 6.6, az0, x + 0.05, G + 6.7, az1, "hierro")
    # la cabina de control (en alto, con escalera desde la pasarela)
    c0, cz0, c1, cz1 = D.CABINA_CONTROL
    l.caja(c0, G, cz0, c1, D.CABINA_Y, cz1, "hormigon_parque")
    caja_hueca(l, c0, D.CABINA_Y, cz0, c1, D.CABINA_Y + 2.8, cz1, "muro_pintado", 0.25, techo=True)
    l.caja(c1 - 0.3, D.CABINA_Y + 1.0, cz0 + 1.0, c1 + 0.1, D.CABINA_Y + 2.2, cz1 - 1.0, "vidrio_ventana")
    # la escalera sube desde la pasarela del norte y entra por la cara norte de la cabina
    l.escalera(c0 + 0.5, cz0 - 3.6, D.PASARELA_Y, 3.6, 1.6, D.CABINA_Y - D.PASARELA_Y, hacia="+z", mat="hormigon_parque")
    l.caja(c0 + 0.5, D.CABINA_Y, cz0 - 0.1, c0 + 2.1, D.CABINA_Y + 2.3, cz0 + 0.4, "muro_pintado", hueco=True)
    for x, z, c in ((110.0, 60.0, ROSA), (126.0, 60.0, CIAN), (110.0, 72.0, AMARILLO), (126.0, 72.0, ROSA)):
        l.luz(x, G + 6.0, z, c, 1.0, 12.0, (0, -1, 0), 50.0)
    # LA ESTACION DE LA MONTAÑA RUSA: anden, tejado, escalera y los pilares de la via
    s0, sz0, s1, sz1 = D.ESTACION_MR
    l.caja(s0, G, sz0, s1, D.ANDEN_MR_Y, sz1, "hormigon_parque")
    l.escalera(108.0, sz1 + 3.0, G, 3.0, 4.0, D.ANDEN_MR_Y - G, hacia="-z", mat="hormigon_parque")
    for x in (s0 + 0.3, s1 - 0.3):
        for z in (sz0 + 0.3, sz1 - 0.3):
            l.caja(x - 0.15, D.ANDEN_MR_Y, z - 0.15, x + 0.15, D.ANDEN_MR_Y + 4.0, z + 0.15, "hierro")
    l.caja(s0 - 0.4, D.ANDEN_MR_Y + 4.0, sz0 - 0.4, s1 + 0.4, D.ANDEN_MR_Y + 4.3, sz1 + 0.4, "rayas_rojas")
    neon(l, s0 + 2.0, D.ANDEN_MR_Y + 4.3, sz1 + 0.3, s1 - 2.0, D.ANDEN_MR_Y + 5.0, sz1 + 0.4, "neon_rosa", ROSA, 1.2, 14.0)
    via = D.VIA
    largo = 0.0
    sig = 5.0
    for a, b in zip(via, via[1:]):
        seg = math.dist(a, b)
        t = 0.0
        while t < seg:
            if largo + t >= sig and a[1] + (b[1] - a[1]) * t / seg > G + 3.0:
                x = a[0] + (b[0] - a[0]) * t / seg
                y = a[1] + (b[1] - a[1]) * t / seg
                z = a[2] + (b[2] - a[2]) * t / seg
                if not (D.AB_X[0] - 1.0 < x < D.AB_X[1] + 1.0):
                    l.linea(x, G, z, x, y - 0.7, z, 0.45, "acero_amarillo")
                sig += 5.0
            t += 0.5
        largo += seg
    # el final roto de la via (en NA): los carriles retorcidos hacia abajo
    ex, ey, ez = via[-1]
    for dz in (-0.6, 0.6):
        l.linea(ex, ey - 0.5, ez + dz, ex - 2.5, ey - 3.5, ez + dz * 2.0, 0.14, "acero_amarillo")


# ======================================================================================================
# NA: LA TORRE DE CAIDA Y EL TUNEL DE SERVICIO
# ======================================================================================================
def torre(l, rng, validacion):
    tx, tz = D.TORRE
    l.cilindro(tx, G, tz, D.BASE_TORRE_R, 0.6, "hormigon_parque")
    l.cilindro(tx, G + 0.6, tz, 1.2, D.TORRE_ALTO, "acero_amarillo")
    l.cilindro(tx, G + D.TORRE_ALTO, tz, 2.2, 1.6, "rayas_rojas")
    for k in range(8):
        a = k / 8 * math.tau
        l.linea(tx + math.cos(a) * 1.2, G + D.TORRE_ALTO + 1.6, tz + math.sin(a) * 1.2, tx, G + D.TORRE_ALTO + 3.0, tz, 0.15, "hierro")
    l.luz(tx, G + D.TORRE_ALTO + 2.0, tz, (255, 40, 40), 1.4, 20.0)
    for k in range(4):
        a = k / 4 * math.tau + 0.4
        l.luz(tx + math.cos(a) * 3.0, G + 1.0, tz + math.sin(a) * 3.0, ROSA if k % 2 else CIAN, 0.8, 9.0, (0, 1, 0), 30.0)
    # el TUNEL DE SERVICIO: de debajo de la torre al campo del globo
    t0, tz0, t1, tz1 = D.TUNEL
    l.caja(t0, D.TUNEL_SUELO, tz0, t1, D.TUNEL_TECHO, tz1, "tierra_monte", hueco=True)
    l.caja(t0, D.TUNEL_SUELO - 0.1, tz0, t1, D.TUNEL_SUELO, tz1, "hormigon")
    for x in range(int(t0) + 4, int(t1), 4):
        l.caja(x, D.TUNEL_TECHO - 0.25, tz0, x + 0.3, D.TUNEL_TECHO, tz1, "hierro")
    l.linea(t0 + 8.0, D.TUNEL_TECHO - 0.4, tz0 + 0.25, t1, D.TUNEL_TECHO - 0.4, tz0 + 0.25, 0.25, "oxido")
    l.linea(t0 + 8.0, D.TUNEL_TECHO - 0.8, tz0 + 0.25, t1, D.TUNEL_TECHO - 0.8, tz0 + 0.25, 0.18, "acero_verde")
    for x in (58.0, 70.0, 82.0):
        l.luz(x, D.TUNEL_TECHO - 0.3, (tz0 + tz1) / 2, (255, 170, 90), 0.5, 7.0)
    # la rampa de salida (sube hacia el oeste) y el hueco en el suelo del campo
    r0, r1 = D.RAMPA_TUNEL
    l.caja(r0, D.TUNEL_SUELO, tz0, r1, G, tz1, "tierra_monte", hueco=True)
    l.cuna(r0, D.TUNEL_SUELO, tz0, r1, G, tz1, sube_hacia="-x", mat="hormigon")
    P.barandilla(l, r0, tz0 - 0.1, r1, tz0, G, 1.0)
    P.barandilla(l, r0, tz1, r1, tz1 + 0.1, G, 1.0)
    P.barandilla(l, r1, tz0, r1 + 0.1, tz1, G, 1.0)
    if validacion:
        ax, az, ar = D.AGUJERO_TORRE
        l.cilindro(ax, D.TUNEL_SUELO, az, ar, G + 0.8 - D.TUNEL_SUELO, "tierra_monte", hueco=True)
    # el resto de NA: un puesto de hamburguesas, los caballitos de los niños y bancos
    caja_hueca(l, 62.0, G, 60.0, 72.0, G + 3.2, 68.0, "rayas_amarillas", 0.3)
    l.caja(61.6, G + 3.2, 59.6, 72.4, G + 3.5, 68.4, "chapa_roja")
    l.cilindro(66.0, G, 12.0, 4.0, 0.4, "madera_circo")
    for x, z, c, m in ((64.0, 30.0, CIAN, "neon_cian"), (92.0, 50.0, ROSA, "neon_rosa"), (70.0, 76.0, AMARILLO, "neon_amarillo")):
        farola_neon(l, x, z, c, m)


def construir(l, rng, validacion=False):
    terreno(l, validacion)
    fuera(l, rng, validacion)
    plaza(l, rng, validacion)
    avenida(l, rng, validacion)
    laberinto(l, rng, validacion)
    lago(l, rng, validacion)
    pabellon(l, rng, validacion)
    torre(l, rng, validacion)
    for p in D.RUTA:
        l.punto(p[0], p[1], p[2], "ruta")
    pts = [(10.0, G, 110.0), (46.0, G, 150.0), (6.0, G, 150.0), (50.0, G, 128.0),
           (64.0, G, 92.0), (90.0, G, 100.0), (64.0, G, 150.0), (92.0, G, 156.0), (80.0, G, 110.0),
           (110.0, G, 128.0), (126.0, G, 118.0), (132.0, G, 128.0),
           (150.0, G, 70.0), (168.0, G, 66.0), (160.0, G, 76.0),
           (110.0, G, 60.0), (126.0, G, 70.0), (118.0, G, 64.0), (104.0, G, 30.0), (126.0, G, 24.0), (130.0, G, 42.0),
           (70.0, G, 20.0), (90.0, G, 60.0), (64.0, G, 44.0), (86.0, G, 12.0),
           (70.0, D.TUNEL_SUELO, 46.0), (54.0, D.TUNEL_SUELO, 46.0),
           (40.0, G, 20.0), (40.0, G, 70.0), (10.0, G, 40.0), (30.0, G, 12.0)]
    for (c, f) in D.CAMINO_LAB[::6]:
        x0, z0, x1, z1 = D.lab_celda(c, f)
        pts.append(((x0 + x1) / 2, G, (z0 + z1) / 2))
    for x, y, z in pts:
        l.punto(x, y, z, "criatura")
