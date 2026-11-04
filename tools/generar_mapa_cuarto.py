#!/usr/bin/env python3
"""GENERADOR DEL MAPA CUARTO (cuarto): LA HABITACION DE UN NIÑO A ESCALA DE JUGUETE. 2026-10-21, pedido: "una habitacion
con cama, ventana, muebles y juguetes por todos lados, como la de Toy Story; los jugadores del tamaño de un juguetito;
para battle royale (y duelo); el avion en el suelo con la escotilla abierta: se sube, se cierra y despega".

ESCALA: 1 cm de verdad = 1 voxel de 20 cm (20 veces). El cuarto mide 5 x 6 m de verdad con 2,4 de techo: aqui 100 x 120
m con el techo a 48 m. Una persona (1,8 m) queda como un soldadito de 9 cm. Debajo de la cama hay 4 m para pasar.

Se escribe SOLO el de 20 cm (el de 10 cm serian ~20.000 chunks): godot/maps/cuarto_lo.vxmap. Y al lado:
  cuarto.botin.json   el botin (con el, el mapa es de BATTLE ROYALE: Settings.es_battle_royale)
  cuarto.br.json      la escala del battle royale (zona, avion bajo el techo, el avion en el suelo para subir)
  cuarto.lights.json  la luz del techo y la del flexo

Solo el CUARTO (paredes, techo, zocalo, la ventana) va con material ANCLADO. Los muebles y los juguetes se derrumban
(pedido: "los derrumbes tienen que estar"): quitale las patas a la cama y se cae.

Uso:  python tools/generar_mapa_cuarto.py
"""
import json, math, os, random, sys, time
import numpy as np

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(AQUI, "mapa_pve"))
sys.path.insert(0, os.path.join(AQUI, "mapa_cafeteria"))
import lienzo as L           # noqa: E402
import raster as R           # noqa: E402
import generar_mapa_pve as G  # noqa: E402
import materiales as MAT     # noqa: E402
import pintura               # noqa: E402

RAIZ = os.path.dirname(AQUI)
MAPAS = os.path.join(RAIZ, "godot", "maps")
NOMBRE = "cuarto"
SEMILLA = 20261022
V = 0.2
CHUNKS_LO = (16, 8, 19)          # 20 cm: 102,4 x 51,2 x 121,6 m
PARED = 1.2                      # 6 cm de pared de verdad
OX, OZ = PARED, PARED            # donde empieza el cuarto por dentro
ANCHO, FONDO, ALTO = 100.0, 120.0, 48.0
SUELO = 1.2                      # y del suelo (debajo, la base)


def cm(x):
    """centimetros de verdad -> metros del mapa (1 cm = 0,2 m)"""
    return round(x * 0.2, 3)


def X(x):
    return round(OX + cm(x), 3)


def Z(z):
    return round(OZ + cm(z), 3)


def Y(y):
    return round(SUELO + cm(y), 3)


# ====================================================================================================== materiales
FIJO = set()          # los anclados


def materiales():
    T = MAT
    T.pat("parquet", T.TABLAS, [(178, 122, 70), (164, 110, 62), (190, 134, 80), (150, 100, 56)], "suelo_duro")
    for n, rgb in (("pared_azul", (118, 168, 226)), ("nube", (246, 248, 255)), ("zocalo", (240, 236, 226)),
                   ("techo", (238, 238, 232)), ("marco_blanco", (236, 234, 228)),
                   ("mueble", (190, 130, 74)), ("mueble_osc", (128, 82, 46)), ("mueble_claro", (214, 170, 110)),
                   ("mueble_rojo", (196, 54, 44)), ("mueble_azul", (60, 104, 186)),
                   ("colchon", (242, 242, 236)), ("manta", (72, 112, 196)), ("manta_osc", (52, 84, 160)),
                   ("estrella", (250, 214, 64)), ("almohada", (250, 250, 246)), ("cortina_v", (232, 196, 80))):
        T.mat(n, rgb, "madera")
        # LOS DERRUMBES EN EL MAPA (pedido): solo el CUARTO va anclado (paredes, techo, zocalo, la ventana); los muebles
        # y los juguetes se caen si les quitas el apoyo
        if n in ("pared_azul", "nube", "zocalo", "techo", "marco_blanco", "cortina_v"):
            FIJO.add(n)
    for n, rgb in (("plastico_rojo", (220, 50, 42)), ("plastico_azul", (44, 100, 206)), ("plastico_amarillo", (246, 200, 40)),
                   ("plastico_verde", (64, 168, 72)), ("plastico_naranja", (244, 130, 30)), ("plastico_morado", (136, 72, 178)),
                   ("plastico_blanco", (238, 238, 234)), ("plastico_negro", (42, 42, 46)), ("plastico_rosa", (238, 120, 170)),
                   ("plastico_celeste", (110, 200, 236)), ("papel", (244, 240, 228)), ("carton", (186, 140, 88)),
                   ("madera_juguete", (206, 156, 96)), ("verde_dino", (96, 170, 70)), ("gris_robot", (150, 156, 166))):
        T.mat(n, rgb, "madera")
    T.mat("goma_negra", (34, 34, 36), "goma")
    for n, rgb in (("ajedrez_blanco", (236, 226, 204)), ("ajedrez_negro", (52, 40, 34)), ("ajedrez_ojo", (20, 20, 20)), ("fieltro", (70, 160, 70)),
                   ("puzzle_a", (214, 96, 80)), ("puzzle_b", (90, 140, 210)), ("puzzle_c", (236, 196, 80)),
                   ("puzzle_d", (120, 186, 110)), ("saco", (176, 160, 112)), ("verde_militar", (84, 120, 54))):
        T.mat(n, rgb, "madera")
    T.mat("riel", (150, 150, 158), "metal")
    T.mat("moneda_cobre", (184, 110, 60), "metal")
    T.mat("moneda_plata", (196, 198, 204), "metal")
    T.mat("moneda_oro", (226, 186, 70), "metal")
    T.mat("faro", (255, 246, 214), "luz")
    T.mat("piloto_rojo", (210, 30, 30), "madera")
    T.mat("peluche", (168, 112, 64), "tela")
    T.mat("peluche_claro", (214, 170, 120), "tela")
    T.mat("luz_lampara", (255, 236, 190), "luz")
    MAT.registrar()


def por_nombre():
    """Los anclados: lo de madera con la bandera de ancla (lo que los toca no se cae)."""
    d = dict(G.POR_NOMBRE)
    f = G.FISICA["madera"]
    for n in FIJO:
        d[n] = (f[0], f[1], f[2] | 1, f[3], f[4])
    return d


# ====================================================================================================== el cuarto
TAGS = []             # (primera primitiva, objeto): para el revisor (CUARTO_AUDITA=1, tools/mapa_cuarto_audita.py)


def tag(l, nombre):
    TAGS.append((len(l.prims), nombre))


def caja(l, x0, y0, z0, x1, y1, z1, mat, hueco=False):
    """en centimetros de verdad (x, z desde la esquina de dentro del cuarto, y desde el suelo)"""
    l.caja(X(x0), Y(y0), Z(z0), X(x1), Y(y1), Z(z1), mat, hueco=hueco)


def cascara(l, x0, y0, z0, x1, y1, z1, mat, g=4.0, abierta_arriba=False):
    """un mueble HUECO (para no gastar memoria): la caja y el interior vaciado dejando `g` cm de pared"""
    caja(l, x0, y0, z0, x1, y1, z1, mat)
    caja(l, x0 + g, y0 + g, z0 + g, x1 - g, y1 - (0 if abierta_arriba else g), z1 - g, mat, hueco=True)


def cuarto(l, rng):
    tag(l, "cuarto")
    # la base y el suelo de parquet
    l.caja(0, 0, 0, OX * 2 + ANCHO, SUELO - V, OZ * 2 + FONDO, "roca_base")
    l.caja(0, SUELO - V, 0, OX * 2 + ANCHO, SUELO, OZ * 2 + FONDO, "parquet")
    # las paredes (huecas por dentro: 1,2 m) y el techo
    l.caja(0, SUELO, 0, OX * 2 + ANCHO, SUELO + ALTO, OZ * 2 + FONDO, "pared_azul")
    l.caja(OX, SUELO, OZ, OX + ANCHO, SUELO + ALTO, OZ + FONDO, "pared_azul", hueco=True)
    pass  # SIN TECHO (2026-10-22, pedido: menos triangulos): l.caja(0, SUELO + ALTO, 0, OX * 2 + ANCHO, SUELO + ALTO + 1.2, OZ * 2 + FONDO, "techo")
    # el zocalo blanco (10 cm)
    for (a, b, c, d) in ((0, 0, 500, 1), (0, 599, 500, 600), (0, 0, 1, 600), (499, 0, 500, 600)):
        caja(l, a, 0, b, c, 10, d, "zocalo")
    # LAS NUBES del papel pintado: manchas blancas en el plano de la pared (no sobresalen)
    for _ in range(46):
        pared = rng.choice("nsoe")
        u = rng.uniform(20, 480 if pared in "ns" else 580)
        y = rng.uniform(40, 220)
        for k in range(rng.randint(3, 5)):
            du, dy, r = rng.uniform(-18, 18), rng.uniform(-5, 5), rng.uniform(7, 13)
            if pared == "n":
                caja(l, u + du - r, y + dy - r * 0.6, -0.1, u + du + r, y + dy + r * 0.6, 0.0, "nube")
            elif pared == "s":
                caja(l, u + du - r, y + dy - r * 0.6, 600.0, u + du + r, y + dy + r * 0.6, 600.1, "nube")
            elif pared == "o":
                caja(l, -0.1, y + dy - r * 0.6, u + du - r, 0.0, y + dy + r * 0.6, u + du + r, "nube")
            else:
                caja(l, 500.0, y + dy - r * 0.6, u + du - r, 500.1, y + dy + r * 0.6, u + du + r, "nube")
    # LA VENTANA (pared norte): hueco con su marco blanco, cruz, vidrio, alfeizar y cortinas recogidas
    # el hueco de verdad (aire en todo el grosor de la pared) y UN vidrio fino de 1 cm en medio: se ve el cielo
    caja(l, 180, 90, -7, 300, 210, 0.5, "vidrio", hueco=True)
    caja(l, 180, 90, -3.5, 300, 210, -2.5, "vidrio")
    # el marco: jamba gruesa en el canto del hueco y moldura que asoma por dentro
    caja(l, 176, 86, -6, 304, 90, 2, "marco_blanco")
    caja(l, 176, 210, -6, 304, 214, 1.5, "marco_blanco")
    caja(l, 176, 90, -6, 180, 210, 1.5, "marco_blanco")
    caja(l, 300, 90, -6, 304, 210, 1.5, "marco_blanco")
    # dos hojas con su bastidor (5 cm), el parteluz y el travesaño: cuatro vidrios grandes
    for (h0, h1) in ((180, 240), (240, 300)):
        caja(l, h0, 90, -4.5, h0 + 3, 210, -1.5, "marco_blanco")
        caja(l, h1 - 3, 90, -4.5, h1, 210, -1.5, "marco_blanco")
        caja(l, h0, 90, -4.5, h1, 93, -1.5, "marco_blanco")
        caja(l, h0, 207, -4.5, h1, 210, -1.5, "marco_blanco")
        caja(l, h0, 148, -4.5, h1, 151, -1.5, "marco_blanco")
        caja(l, h0 + 26, 140, -1.5, h0 + 28, 156, -0.5, "riel")       # la manija
    caja(l, 172, 84, 0, 308, 88, 14, "marco_blanco")                # el alfeizar: se puede andar por el
    caja(l, 150, 70, 0, 176, 230, 8, "cortina_v")
    caja(l, 304, 70, 0, 330, 230, 8, "cortina_v")
    caja(l, 146, 228, 0, 334, 234, 4, "mueble_osc")                 # la barra
    # LA PUERTA (pared este), cerrada, con su picaporte
    caja(l, 499, 0, 300, 500.5, 200, 380, "mueble_claro")
    caja(l, 497, 0, 296, 500, 204, 300, "marco_blanco")
    caja(l, 497, 0, 380, 500, 204, 384, "marco_blanco")
    caja(l, 497, 200, 296, 500, 204, 384, "marco_blanco")
    caja(l, 493, 96, 368, 499, 100, 376, "plastico_amarillo")
    # el enchufe y un cuadro (un barco) en la pared sur
    caja(l, 470, 30, 599, 480, 36, 600, "plastico_blanco")
    caja(l, 60, 120, 598, 130, 170, 600, "mueble_osc")
    caja(l, 64, 124, 597.8, 126, 166, 598, "plastico_celeste")
    caja(l, 80, 132, 597.6, 110, 140, 597.8, "plastico_rojo")
    caja(l, 93, 140, 597.6, 95, 158, 597.8, "plastico_blanco")


def muebles(l, rng):
    tag(l, "muebles")
    tag(l, "LA CAMA (pared oeste): 90 x 190, colchon")
    # --- LA CAMA (pared oeste): 90 x 190, colchon a 45 cm; debajo, 20 cm (4 m) para pasar ---------------------
    x0, x1, z0, z1 = 0, 90, 40, 230
    for (px, pz) in ((2, 42), (82, 42), (2, 222), (82, 222)):
        caja(l, px, 0, pz, px + 6, 22, pz + 6, "mueble")              # las patas
    cascara(l, x0, 20, z0, x1, 32, z1, "mueble", g=3)                 # el somier
    caja(l, x0 + 2, 32, z0 + 4, x1 - 2, 45, z1 - 2, "colchon")
    caja(l, x0 + 2, 39, z0 + 4, x1 - 2, 40, z1 - 2, "colchon", hueco=True)    # (el colchon, hueco por dentro)
    caja(l, x0, 22, z0 - 4, x1, 92, z0, "mueble")                     # el cabecero
    caja(l, x0 + 8, 60, z0 - 5, x1 - 8, 84, z0 - 4, "mueble_claro")
    caja(l, x0 + 10, 45, z0 + 6, x1 - 10, 55, z0 + 40, "almohada")    # la almohada
    # la MANTA de estrellas, que cae por el lado del cuarto hasta el suelo: hace de RAMPA para subir
    caja(l, x0 + 2, 45, z0 + 50, x1 + 2, 47, z1, "manta")
    l.cuna(X(x1 + 2), Y(0), Z(z0 + 70), X(x1 + 2 + 46), Y(47), Z(z1 - 10), sube_hacia="-x", mat="manta")
    for _ in range(26):
        u, w = rng.uniform(x0 + 6, x1 - 6), rng.uniform(z0 + 56, z1 - 6)
        caja(l, u - 2.5, 47, w - 2.5, u + 2.5, 47.5, w + 2.5, "estrella")
    # la mesa de luz con el velador
    cascara(l, 0, 0, 236, 40, 50, 276, "mueble_osc", g=3)
    caja(l, 38, 30, 248, 41, 34, 264, "plastico_amarillo")            # el tirador
    caja(l, 14, 50, 250, 26, 54, 262, "plastico_azul")
    caja(l, 18, 54, 254, 22, 76, 258, "plastico_azul")
    caja(l, 8, 72, 244, 32, 90, 268, "cortina_v")
    tag(l, "EL ESCRITORIO (pared este): 60 x 120, ta")
    # --- EL ESCRITORIO (pared este): 60 x 120, tablero a 75; la silla; los lapices y un globo terraqueo --------------
    dx0, dx1, dz0, dz1 = 440, 500, 60, 180
    for (px, pz) in ((442, 62), (494, 62), (442, 174), (494, 174)):
        caja(l, px, 0, pz, px + 4, 72, pz + 4, "mueble_rojo")
    caja(l, dx0, 72, dz0, dx1, 76, dz1, "mueble_claro")
    cascara(l, 460, 40, 140, 500, 72, 178, "mueble_rojo", g=2)         # la cajonera colgada
    caja(l, 456, 54, 150, 460, 58, 168, "plastico_amarillo")
    # la silla, delante
    for (px, pz) in ((404, 140), (430, 140), (404, 166), (430, 166)):
        caja(l, px, 0, pz, px + 3, 44, pz + 3, "mueble_azul")
    caja(l, 402, 44, 138, 434, 47, 170, "mueble_azul")
    caja(l, 402, 47, 138, 405, 88, 170, "mueble_azul")
    # sobre la mesa: un cuaderno, crayones, un lapicero y el globo
    caja(l, 450, 76, 70, 480, 77, 92, "papel")
    for i, m in enumerate(("plastico_rojo", "plastico_verde", "plastico_azul", "plastico_amarillo")):
        caja(l, 452 + i * 3, 76, 96, 454 + i * 3, 78, 104, m)
    l.cilindro(X(488), Y(76), Z(76), cm(5), cm(12), "plastico_morado")
    l.cilindro(X(470), Y(76), Z(160), cm(4), cm(4), "mueble_osc")
    l.esfera(X(470), Y(91), Z(160), cm(11), "plastico_celeste")
    # el flexo
    caja(l, 486, 76, 120, 496, 78, 130, "plastico_negro")
    caja(l, 490, 78, 124, 492, 100, 126, "plastico_negro")
    caja(l, 480, 96, 120, 492, 102, 130, "plastico_negro")
    tag(l, "EL ROPERO (esquina sudeste), hueco y con")
    # --- EL ROPERO (esquina sudeste), hueco y con una puerta abierta: se entra --------------------------------------
    cascara(l, 445, 0, 440, 500, 190, 590, "mueble", g=3)
    caja(l, 445, 2, 444, 448, 186, 513, "mueble", hueco=True)        # el hueco de la puerta abierta
    caja(l, 380, 2, 441, 445, 186, 444, "mueble_claro")              # la hoja, abierta de par en par
    caja(l, 380, 90, 444, 383, 100, 447, "plastico_amarillo")
    caja(l, 448, 100, 444, 497, 103, 587, "mueble_osc")              # el estante de dentro
    caja(l, 470, 160, 444, 472, 162, 587, "plastico_negro")          # la barra con perchas
    for k in range(6):
        w = 455 + k * 22
        caja(l, 452, 110, w, 492, 162, w + 12, rng.choice(("plastico_rojo", "plastico_azul", "plastico_verde", "plastico_amarillo")))
    tag(l, "LA ESTANTERIA (pared sur) con libros")
    # --- LA ESTANTERIA (pared sur) con libros ------------------------------------------------------------------------
    cascara(l, 150, 0, 570, 250, 150, 600, "mueble_osc", g=2)
    caja(l, 152, 2, 570, 248, 148, 572, "mueble_osc", hueco=True)    # abierta por delante
    for k in range(1, 5):
        caja(l, 150, k * 30, 571, 250, k * 30 + 2, 598, "mueble_osc")
    for k in range(5):
        # HUECOS SIN LIBROS (pedido: "que haya lugares sin libros para que la gente se pueda subir"): un tramo de 30 cm
        # en cada estante, alternando de lado, para trepar de estante en estante
        hueco_x = 158 if k % 2 == 0 else 212
        x = 153
        while x < 246:
            if hueco_x <= x < hueco_x + 30:
                x = hueco_x + 30
                continue
            w = rng.uniform(3, 6)
            h = rng.uniform(18, 27)
            if rng.random() < 0.1:
                x += w
                continue
            caja(l, x, k * 30 + 2, 574, min(x + w, 247), k * 30 + 2 + h, 597,
                 rng.choice(("plastico_rojo", "plastico_azul", "plastico_verde", "plastico_amarillo", "plastico_morado", "papel")))
            x += w + 0.5
    tag(l, "LA RAMPA DE DESPEGUE")
    # --- LA RAMPA DE DESPEGUE: una tabla angosta encima de la estanteria que asoma 35 cm hacia el cuarto, un poco
    # levantada en la punta (pedido: "una rampa para que el avion tenga mas espacio y moverlo adelante")
    # (a ras del techo de la estanteria, pedido: "la rampa esta mas alta que la estanteria"): la tabla es la
    # continuacion del techo hacia delante, con los bordes pintados en el mismo plano
    caja(l, 178, 148, 535, 222, 150, 600, "mueble_claro")
    caja(l, 178, 148, 535, 180, 150, 600, "plastico_rojo")
    caja(l, 220, 148, 535, 222, 150, 600, "plastico_rojo")
    tag(l, "EL BAUL DE LOS JUGUETES (pared sur), abi")
    # --- EL BAUL DE LOS JUGUETES (pared sur), abierto, con juguetes asomando ----------------------------------------
    cascara(l, 280, 0, 552, 360, 45, 598, "mueble_azul", g=3, abierta_arriba=True)
    caja(l, 280, 45, 594, 360, 90, 598, "mueble_azul")                # la tapa, levantada
    caja(l, 300, 3, 560, 320, 60, 580, "plastico_rojo")               # un cubo que asoma (apoyado en el fondo)
    l.cilindro(X(338), Y(3), Z(574), cm(4), cm(32), "plastico_amarillo")
    l.esfera(X(338), Y(44), Z(574), cm(11), "plastico_verde")   # en su palo
    tag(l, "LA ALFOMBRA de rayas en el centro")
    # --- LA ALFOMBRA de rayas en el centro -----------------------------------------------------------------------------
    # (la alfombra de rayas se quito el 2026-10-21, pedido: "me come voxels de las cosas y nunca vi una de ese color")


PERFILES = {
    # (alto en cm, radio en cm) de abajo arriba; entre puntos, recto
    "peon":  [(0, 3.3), (1, 3.3), (1.6, 2.7), (2.4, 2.6), (3.0, 2.0), (6.0, 1.3), (6.6, 2.1), (7.2, 1.2)],
    "torre": [(0, 3.4), (1, 3.4), (1.6, 2.9), (2.4, 2.8), (3.0, 2.3), (9.0, 2.0), (9.6, 2.7), (12.4, 2.7)],
    "alfil": [(0, 3.3), (1, 3.3), (1.6, 2.8), (2.4, 2.6), (3.0, 1.9), (9.0, 1.3), (9.6, 2.2), (10.2, 1.2)],
    "reina": [(0, 3.5), (1, 3.5), (1.6, 3.0), (2.4, 2.8), (3.0, 2.1), (11.0, 1.4), (11.6, 2.4), (12.2, 1.5),
              (14.5, 2.4), (15.0, 2.6)],
    "rey":   [(0, 3.5), (1, 3.5), (1.6, 3.0), (2.4, 2.8), (3.0, 2.2), (12.0, 1.5), (12.6, 2.5), (13.2, 1.6),
              (15.0, 2.2), (15.6, 1.4)],
    "caballo": [(0, 3.4), (1, 3.4), (1.6, 2.9), (2.4, 2.7), (3.0, 2.3), (4.4, 2.2)],
}


def _radio_perfil(perfil, y):
    for k in range(len(perfil) - 1):
        (y0, r0), (y1, r1) = perfil[k], perfil[k + 1]
        if y0 <= y <= y1:
            t = 0.0 if y1 == y0 else (y - y0) / (y1 - y0)
            return r0 + (r1 - r0) * t
    return perfil[-1][1]


def pieza_ajedrez(l, px, y0, pz, tipo, m, mira):
    perfil = PERFILES[tipo]
    alto = perfil[-1][0]
    y = 0.0
    while y < alto - 0.01:
        r = _radio_perfil(perfil, y + 0.5)
        l.cilindro(X(px), Y(y0 + y), Z(pz), cm(r), cm(1.0), m)
        y += 1.0
    top = y0 + alto
    if tipo == "peon":
        l.esfera(X(px), Y(top + 1.2), Z(pz), cm(2.0), m)
    elif tipo == "torre":
        for k in range(4):                                  # las almenas: cuatro muescas en la corona
            a = k * math.pi / 2
            ox, oz = math.cos(a) * 2.2, math.sin(a) * 2.2
            caja(l, px + ox - 0.6, top - 1.2, pz + oz - 0.6, px + ox + 0.6, top + 0.2, pz + oz + 0.6, m, hueco=True)
        l.cilindro(X(px), Y(top - 1.6), Z(pz), cm(1.6), cm(1.8), m, hueco=True)
    elif tipo == "alfil":
        l.elipsoide(X(px), Y(top + 2.0), Z(pz), cm(1.7), cm(2.6), cm(1.7), m)          # la mitra
        caja(l, px - 2, top + 1.6, pz - 0.35, px + 2, top + 3.4, pz + 0.35, m, hueco=True)  # su corte
        l.esfera(X(px), Y(top + 4.9), Z(pz), cm(0.8), m)
    elif tipo == "reina":
        for k in range(8):                                  # la corona de puntas
            a = k * math.pi / 4
            l.esfera(X(px + math.cos(a) * 2.2), Y(top + 0.2), Z(pz + math.sin(a) * 2.1), cm(1.0), m)
        l.esfera(X(px), Y(top + 1.2), Z(pz), cm(1.5), m)
        l.esfera(X(px), Y(top + 3.0), Z(pz), cm(0.8), m)
    elif tipo == "rey":
        l.cilindro(X(px), Y(top), Z(pz), cm(1.2), cm(1.0), m)
        caja(l, px - 0.5, top + 1.0, pz - 0.5, px + 0.5, top + 4.6, pz + 0.5, m)      # la cruz
        caja(l, px - 1.8, top + 2.4, pz - 0.5, px + 1.8, top + 3.4, pz + 0.5, m)
    elif tipo == "caballo":
        # el cuello sube inclinado hacia delante (mira: +1 hacia +z, -1 hacia -z), la cabeza y el hocico, las orejas y la crin
        d = mira
        for k in range(7):
            yy = top + k * 1.0
            zz = pz + d * (k * 0.35)
            caja(l, px - 1.5, yy, zz - 1.8, px + 1.5, yy + 1.2, zz + 1.8, m)
        caja(l, px - 1.5, top + 6.0, pz + d * 1.0 - 1.8, px + 1.5, top + 8.4, pz + d * 1.0 + 1.8, m)   # la cabeza
        hz0, hz1 = sorted((pz + d * 2.6, pz + d * 6.0))
        caja(l, px - 1.2, top + 5.4, hz0, px + 1.2, top + 7.4, hz1, m)                              # el hocico
        caja(l, px - 1.25, top + 5.4, (hz1 if d > 0 else hz0) - 0.4, px + 1.25, top + 6.0,
             (hz1 if d > 0 else hz0) + 0.4, m, hueco=True)                                          # la boca
        for ox in (-1.0, 1.0):
            caja(l, px + ox - 0.4, top + 8.4, pz + d * 0.4 - 0.4, px + ox + 0.4, top + 9.8, pz + d * 0.4 + 0.4, m)  # orejas
            caja(l, px + ox * 1.55 - 0.15, top + 7.0, pz + d * 3.0 - 0.3, px + ox * 1.55 + 0.15, top + 7.6,
                 pz + d * 3.0 + 0.3, "ajedrez_ojo")                                                 # los ojos
        for k in range(6):                                                                          # la crin
            caja(l, px - 0.6, top + 1.5 + k * 1.2, pz - d * 2.0 - 0.6 + d * k * 0.3, px + 0.6, top + 2.7 + k * 1.2,
                 pz - d * 2.0 + 0.6 + d * k * 0.3, m)


def auto_juguete(l, ax, az, color, a_lo_largo_z=False):
    """UN AUTITO DE JUGUETE de verdad (2026-10-21, pedido: "el auto no tiene cristal, es muy liso: que parezca real"):
    20 x 9 cm (4 x 1,8 m). Carroceria con capo y maletero mas bajos, cabina con parabrisas inclinado y ventanillas de
    vidrio, parantes, techo, faros, pilotos, parrilla, paragolpes, espejos, manijas, linea de puertas y ruedas
    redondas con llanta y tapacubos. En coordenadas del coche: u a lo largo (0 = la cola), w de lado (0..9)."""
    def c(u0, y0, w0, u1, y1, w1, m):
        if a_lo_largo_z:
            caja(l, ax + w0, y0, az + u0, ax + w1, y1, az + u1, m)
        else:
            caja(l, ax + u0, y0, az + w0, ax + u1, y1, az + w1, m)

    def rueda(u, lado):
        # cilindro tumbado de lado (eje w): goma, llanta gris y tapacubos, saliendo un poco de la carroceria
        partes = (((-1.0, 1.8), (-1.1, 0.3), (-1.2, 0.2)) if lado < 0 else ((8.2, 1.8), (9.8, 0.3), (10.0, 0.2)))
        for ((base, largo), r, m) in zip(partes, (2.3, 1.4, 0.6), ("goma_negra", "riel", "plastico_blanco")):
            if a_lo_largo_z:
                l.cilindro(X(ax + base), Y(2.3), Z(az + u), cm(r), cm(largo), m, eje="x")
            else:
                l.cilindro(X(ax + u), Y(2.3), Z(az + base), cm(r), cm(largo), m, eje="z")
    # la carroceria: baja (capo y maletero) y el cuerpo de la cabina
    c(1.0, 1.4, 0.4, 19.0, 4.6, 8.6, color)
    c(0.4, 2.0, 0.8, 1.0, 4.2, 8.2, color)              # la cola redondeada
    c(19.0, 2.0, 0.8, 19.6, 4.2, 8.2, color)            # el morro redondeado
    c(13.5, 4.6, 0.6, 18.4, 5.2, 8.4, color)            # el capo, un poco abombado
    c(1.6, 4.6, 0.6, 5.5, 5.4, 8.4, color)              # el maletero
    # la cabina: parantes de color y vidrio en medio
    c(5.5, 4.6, 0.6, 13.5, 8.6, 8.4, "vidrio")
    for u in (5.5, 9.2, 12.8):                          # parantes (detras, centro, delante)
        c(u, 4.6, 0.5, u + 0.7, 8.6, 8.5, color)
    c(6.2, 8.6, 0.8, 12.6, 9.4, 8.2, color)              # el techo
    c(12.6, 7.4, 0.8, 13.5, 8.6, 8.2, color)             # el parabrisas inclinado: el canto de delante
    c(13.5, 4.6, 0.8, 14.5, 6.4, 8.2, "vidrio")
    c(4.8, 4.6, 0.8, 5.5, 7.0, 8.2, "vidrio")            # la luneta de atras
    # el interior (se ve por el vidrio): asientos y volante
    c(7.0, 4.6, 1.6, 8.6, 6.8, 4.0, "plastico_negro")
    c(7.0, 4.6, 5.0, 8.6, 6.8, 7.4, "plastico_negro")
    c(10.8, 5.6, 5.4, 11.2, 7.0, 7.0, "plastico_negro")
    # el frente: parrilla, faros y paragolpes; la cola: pilotos y paragolpes
    c(19.6, 2.4, 2.8, 19.9, 3.8, 6.2, "plastico_negro")
    c(19.4, 3.2, 1.0, 19.9, 4.2, 2.6, "faro")
    c(19.4, 3.2, 6.4, 19.9, 4.2, 8.0, "faro")
    c(19.4, 1.4, 0.4, 20.2, 2.4, 8.6, "riel")
    c(0.1, 3.2, 0.9, 0.6, 4.2, 2.6, "piloto_rojo")
    c(0.1, 3.2, 6.4, 0.6, 4.2, 8.1, "piloto_rojo")
    c(-0.2, 1.4, 0.4, 0.6, 2.4, 8.6, "riel")
    c(0.2, 2.2, 3.4, 0.4, 2.8, 5.6, "plastico_blanco")  # la matricula
    # los lados: linea de puertas, manijas, espejos y una franja
    for w in (0.2, 8.6):
        c(9.8, 1.8, w, 10.0, 4.6, w + 0.2, "plastico_negro")
        c(7.6, 4.0, w, 8.6, 4.3, w + 0.2, "riel")
        c(11.4, 4.0, w, 12.4, 4.3, w + 0.2, "riel")
        c(1.0, 2.8, w, 19.0, 3.2, w + 0.2, "plastico_blanco")
    c(12.4, 6.2, -0.4, 13.2, 7.0, 0.6, color)
    c(12.4, 6.2, 8.4, 13.2, 7.0, 9.4, color)
    # las ruedas, en sus pasos
    for u in (4.2, 15.6):
        rueda(u, -1)
        rueda(u, 1)


def juguetes(l, rng):
    tag(l, "juguetes")
    tag(l, "EL CASTILLO DE JUGUETE sobre la alfombra")
    # --- EL CASTILLO DE JUGUETE sobre la alfombra (de madera, hueco, con torres y puerta) ---------------------------
    cx0, cz0, cx1, cz1 = 160, 270, 240, 340
    cascara(l, cx0, 0, cz0, cx1, 30, cz1, "madera_juguete", g=3, abierta_arriba=True)
    caja(l, 190, 0, cz1 - 3, 210, 22, cz1, "madera_juguete", hueco=True)            # la puerta
    for (tx, tz) in ((cx0, cz0), (cx1, cz0), (cx0, cz1), (cx1, cz1)):
        l.cilindro(X(tx), Y(0), Z(tz), cm(9), cm(44), "madera_juguete")
        l.cilindro(X(tx), Y(4), Z(tz), cm(6), cm(42), "madera_juguete", hueco=True)
        l.cilindro(X(tx), Y(44), Z(tz), cm(10), cm(3), "plastico_rojo")
    for k in range(1, 8):                                                            # almenas
        x = cx0 + 4 + k * 9
        caja(l, x, 30, cz0, x + 4, 34, cz0 + 3, "madera_juguete")
        caja(l, x, 30, cz1 - 3, x + 4, 34, cz1, "madera_juguete")
    caja(l, 196, 0, 302, 197.4, 70, 303.4, "mueble_osc")                                 # el mastil y la bandera
    caja(l, 197, 62, 302, 212, 70, 303, "plastico_rojo")
    tag(l, "TORRES DE CUBOS con letras (5 cm = 1 m)")
    # --- TORRES DE CUBOS con letras (5 cm = 1 m) ------------------------------------------------------------------
    colores = ("plastico_rojo", "plastico_azul", "plastico_amarillo", "plastico_verde", "plastico_naranja", "plastico_morado")
    for (bx, bz, n) in ((300, 280, 6), (310, 300, 4), (290, 300, 3), (120, 450, 5), (340, 320, 3), (110, 560, 2)):
        for k in range(n):
            ox, oz = rng.uniform(-1, 1), rng.uniform(-1, 1)
            caja(l, bx + ox, k * 5, bz + oz, bx + ox + 5, k * 5 + 5, bz + oz + 5, colores[(k + bx) % len(colores)])
    # (los cubos sueltos por el suelo van al final, en sueltos(): donde no pisen nada)
    tag(l, "LA PISTA DE AUTITOS: del escritorio al s")
    # --- LA PISTA DE AUTITOS: del escritorio al suelo (naranja, con bordes): el camino para subir a la mesa ---------
    l.cuna(X(300), Y(0), Z(108), X(440), Y(76), Z(122), sube_hacia="+x", mat="plastico_naranja")
    l.cuna(X(300), Y(0), Z(106), X(440), Y(79), Z(108), sube_hacia="+x", mat="plastico_naranja")
    l.cuna(X(300), Y(0), Z(122), X(440), Y(79), Z(124), sube_hacia="+x", mat="plastico_naranja")
    for (px, ph) in ((340, 20), (380, 42), (420, 64)):                                # sus soportes
        caja(l, px, 0, 112, px + 3, ph, 118, "plastico_azul")
    tag(l, "AUTITOS")
    # --- AUTITOS ---------------------------------------------------------------------------------------------------
    for (ax, az, c1, giro) in ((346, 134, "plastico_rojo", 0), (330, 360, "plastico_azul", 1), (256, 258, "plastico_amarillo", 0)):
        auto_juguete(l, ax, az, c1, a_lo_largo_z=bool(giro))
    tag(l, "LA PELOTA (25 cm) y el TROMPO")
    # --- LA PELOTA (25 cm) y el TROMPO ----------------------------------------------------------------------------
    l.esfera(X(380), Y(12.5), Z(470), cm(12.5), "plastico_rojo")
    caja(l, 368, 10, 469, 392, 15, 471, "plastico_blanco")
    l.cilindro(X(410), Y(0), Z(276), cm(3), cm(4), "plastico_amarillo")
    l.cilindro(X(410), Y(4), Z(276), cm(9), cm(5), "plastico_morado")
    l.cilindro(X(410), Y(9), Z(276), cm(1.5), cm(6), "plastico_amarillo")
    # (el tren de juguete y su via van ahora en escenarios(): da la vuelta a la alfombra)
    tag(l, "EL DINOSAURIO (verde, de pie) y el ROBOT")
    # --- EL DINOSAURIO (verde, de pie) y el ROBOT -----------------------------------------------------------------
    dx, dz = 60, 380
    caja(l, dx, 0, dz, dx + 5, 14, dz + 5, "verde_dino")
    caja(l, dx + 10, 0, dz, dx + 15, 14, dz + 5, "verde_dino")
    caja(l, dx - 2, 12, dz - 2, dx + 17, 30, dz + 14, "verde_dino")
    caja(l, dx + 2, 28, dz + 10, dx + 13, 40, dz + 22, "verde_dino")
    caja(l, dx + 1, 36, dz + 18, dx + 14, 46, dz + 34, "verde_dino")          # la cabeza
    caja(l, dx + 2, 40, dz + 34, dx + 13, 41, dz + 35, "plastico_blanco")
    caja(l, dx + 4, 12, dz - 18, dx + 11, 20, dz - 2, "verde_dino")           # la cola
    rx, rz = 400, 330
    caja(l, rx, 0, rz, rx + 6, 12, rz + 6, "gris_robot")
    caja(l, rx + 10, 0, rz, rx + 16, 12, rz + 6, "gris_robot")
    caja(l, rx - 2, 12, rz - 2, rx + 18, 32, rz + 8, "gris_robot")
    caja(l, rx + 2, 32, rz, rx + 14, 42, rz + 7, "gris_robot")
    caja(l, rx + 4, 37, rz + 7, rx + 7, 39, rz + 7.4, "plastico_rojo")
    caja(l, rx + 9, 37, rz + 7, rx + 12, 39, rz + 7.4, "plastico_rojo")
    caja(l, rx - 6, 14, rz, rx - 2, 30, rz + 5, "gris_robot")
    caja(l, rx + 18, 14, rz, rx + 22, 30, rz + 5, "gris_robot")
    caja(l, rx + 7, 42, rz + 2, rx + 9, 50, rz + 4, "plastico_amarillo")      # la antena
    tag(l, "CRAYONES por el suelo, DOMINOS en fila y")
    # --- CRAYONES por el suelo, DOMINOS en fila y AROS APILABLES -------------------------------------------------
    # (los crayones por el suelo, en sueltos())
    for k in range(12):
        caja(l, 150 + k * 6, 0, 160, 151.5 + k * 6, 9, 165, "plastico_blanco")
    for k, (r, m) in enumerate(((10, "plastico_rojo"), (8.5, "plastico_naranja"), (7, "plastico_amarillo"),
                                (5.5, "plastico_verde"), (4, "plastico_azul"))):
        l.cilindro(X(200), Y(k * 3.5), Z(190), cm(r), cm(3.5), m)
    l.cilindro(X(200), Y(0), Z(190), cm(1.5), cm(22), "madera_juguete")
    # libros apilados en el suelo junto a la cama (una escalera)
    for k in range(4):
        caja(l, 66 + k * 6, 0, 240 + k * 2, 96 + k * 6, (k + 1) * 4, 262 + k * 2,
             ("plastico_rojo", "plastico_azul", "plastico_verde", "plastico_amarillo")[k])


def mas_juguetes(l, rng):
    tag(l, "mas_juguetes")
    """MAS COSAS (2026-10-21, pedido: "se ve muy liso; agrega juguetes gigantes, un oso, muebles")"""
    tag(l, "EL OSO DE PELUCHE sentado (45 cm)")
    # --- EL OSO DE PELUCHE sentado (45 cm) ---------------------------------------------------------------------
    ox, oz = 350, 446
    l.elipsoide(X(ox), Y(14), Z(oz), cm(16), cm(15), cm(13), "peluche")              # la barriga
    l.elipsoide(X(ox), Y(15), Z(oz + 5), cm(10), cm(10), cm(9), "peluche_claro")
    l.esfera(X(ox), Y(36), Z(oz), cm(11), "peluche")                                 # la cabeza
    l.esfera(X(ox - 9), Y(45), Z(oz), cm(4.5), "peluche")                            # las orejas
    l.esfera(X(ox + 9), Y(45), Z(oz), cm(4.5), "peluche")
    l.esfera(X(ox), Y(33), Z(oz + 9), cm(4.5), "peluche_claro")                      # el hocico
    l.esfera(X(ox), Y(35), Z(oz + 13), cm(1.5), "plastico_negro")                    # la nariz
    l.esfera(X(ox - 4), Y(39), Z(oz + 9.5), cm(1.3), "plastico_negro")               # los ojos
    l.esfera(X(ox + 4), Y(39), Z(oz + 9.5), cm(1.3), "plastico_negro")
    l.elipsoide(X(ox - 15), Y(18), Z(oz + 3), cm(5), cm(10), cm(5), "peluche")       # los brazos
    l.elipsoide(X(ox + 15), Y(18), Z(oz + 3), cm(5), cm(10), cm(5), "peluche")
    l.elipsoide(X(ox - 8), Y(5), Z(oz + 12), cm(6), cm(5), cm(9), "peluche")         # las patas
    l.elipsoide(X(ox + 8), Y(5), Z(oz + 12), cm(6), cm(5), cm(9), "peluche")
    caja(l, ox - 6, 26, oz + 8, ox + 6, 30, oz + 11, "plastico_rojo")                # el moño
    tag(l, "EL PUF rojo")
    # --- EL PUF rojo ---------------------------------------------------------------------------------------------
    l.elipsoide(X(150), Y(12), Z(446), cm(24), cm(13), cm(22), "plastico_rojo")
    tag(l, "EL CABALLITO DE MADERA")
    # --- EL CABALLITO DE MADERA ----------------------------------------------------------------------------------
    hx, hz = 410, 520
    for dz in (-14, 14):
        for k in range(9):
            a = (k - 4) * 0.16
            yy = 4 - 4 * math.cos(a)
            zz = hz + dz * 0 + (k - 4) * 6
            caja(l, hx + dz * 0.3 - 2, yy, zz - 3, hx + dz * 0.3 + 2, yy + 3, zz + 3, "mueble_rojo")
    for pz in (hz - 12, hz + 12):
        caja(l, hx - 6.5, 1, pz - 1.5, hx + 6.5, 4, pz + 1.5, "mueble_claro")         # el travesaño
        caja(l, hx - 1.5, 3, pz - 1.5, hx + 1.5, 22, pz + 1.5, "mueble_claro")
    caja(l, hx - 5, 20, hz - 18, hx + 5, 30, hz + 16, "mueble_claro")                 # el cuerpo
    caja(l, hx - 4, 28, hz + 14, hx + 4, 44, hz + 22, "mueble_claro")                 # el cuello
    caja(l, hx - 4, 38, hz + 22, hx + 4, 44, hz + 30, "mueble_claro")                 # la cabeza
    caja(l, hx - 5, 30, hz + 10, hx + 5, 44, hz + 14, "plastico_negro")               # la crin
    caja(l, hx - 6, 30, hz - 4, hx + 6, 32, hz + 6, "plastico_azul")                  # la montura
    tag(l, "LA CARPA INDIA (tipi), hueca: se entra")
    # --- LA CARPA INDIA (tipi), hueca: se entra --------------------------------------------------------------------
    tx, tz = 70, 330
    for k in range(14):
        r = 38 - k * 2.6
        l.cilindro(X(tx), Y(k * 6), Z(tz), cm(r), cm(6), "plastico_rojo" if k % 3 == 0 else "cortina_v")
        l.cilindro(X(tx), Y(k * 6), Z(tz), cm(max(r - 3, 0.5)), cm(6), "cortina_v", hueco=True)
    caja(l, tx - 8, 0, tz + 28, tx + 8, 26, tz + 40, "cortina_v", hueco=True)        # la entrada
    caja(l, tx - 1, 80, tz - 1, tx + 1, 96, tz + 1, "mueble_osc")                     # los palos
    caja(l, tx + 1, 80, tz - 3, tx + 3, 96, tz - 1, "mueble_osc")
    tag(l, "EL CAMION VOLCADOR")
    # --- EL CAMION VOLCADOR ----------------------------------------------------------------------------------------
    cx, cz = 230, 428
    caja(l, cx, 6, cz, cx + 60, 10, cz + 26, "plastico_negro")
    caja(l, cx + 42, 10, cz + 2, cx + 60, 30, cz + 24, "plastico_amarillo")          # la cabina
    caja(l, cx + 50, 20, cz + 3, cx + 59, 28, cz + 23, "plastico_celeste")
    cascara(l, cx, 10, cz, cx + 40, 26, cz + 26, "plastico_rojo", g=2, abierta_arriba=True)   # la tolva
    for wx in (cx + 6, cx + 30, cx + 50):
        for wz in (cz - 3, cz + 25):
            l.cilindro(X(wx), Y(6), Z(wz), cm(6), cm(4), "goma_negra", eje="z")
    tag(l, "LA COMODA (pared oeste, al sur de la cam")
    # --- LA COMODA (pared oeste, al sur de la cama) con una pecera ---------------------------------------------------
    cascara(l, 0, 0, 420, 45, 80, 540, "mueble_claro", g=3)
    for k in range(3):
        caja(l, 45, 6 + k * 24, 424, 46, 26 + k * 24, 536, "mueble")
        caja(l, 46, 14 + k * 24, 470, 48, 18 + k * 24, 490, "plastico_amarillo")
    l.esfera(X(22), Y(92), Z(470), cm(12), "vidrio")
    caja(l, 18, 86, 468, 26, 90, 472, "plastico_naranja")                             # el pez
    caja(l, 6, 80, 500, 40, 82, 530, "papel")                                         # unas hojas con dibujos
    tag(l, "LA MESITA CON EL JUEGO DE TE")
    # --- LA MESITA CON EL JUEGO DE TE ---------------------------------------------------------------------------------
    mx, mz = 330, 190
    for (px, pz) in ((mx + 2, mz + 2), (mx + 34, mz + 2), (mx + 2, mz + 30), (mx + 34, mz + 30)):
        caja(l, px, 0, pz, px + 3, 28, pz + 3, "plastico_blanco")
    caja(l, mx, 28, mz, mx + 40, 31, mz + 34, "plastico_rosa")
    l.cilindro(X(mx + 20), Y(31), Z(mz + 17), cm(4), cm(6), "plastico_blanco")      # la tetera
    for (px, pz) in ((mx + 8, mz + 8), (mx + 32, mz + 8), (mx + 8, mz + 26), (mx + 32, mz + 26)):
        l.cilindro(X(px), Y(31), Z(pz), cm(2), cm(2.5), "plastico_celeste")         # las tazas
    for px in (mx - 16, mx + 46):                                                    # dos sillitas
        caja(l, px, 0, mz + 10, px + 14, 16, mz + 24, "plastico_amarillo")
        caja(l, px, 16, mz + 10, px + 14, 34, mz + 13, "plastico_amarillo")
    tag(l, "EL TAMBOR, LOS DADOS, LADRILLOS TIPO LEG")
    # --- EL TAMBOR, LOS DADOS, LADRILLOS TIPO LEGO Y LA PELOTA DE BASQUET ----------------------------------------------
    l.cilindro(X(285), Y(0), Z(525), cm(14), cm(20), "plastico_rojo")
    l.cilindro(X(285), Y(20), Z(525), cm(14.5), cm(1), "plastico_blanco")
    caja(l, 276, 21, 518, 294, 22.4, 520, "mueble_claro")                             # los palillos, encima
    caja(l, 278, 21, 528, 296, 22.4, 530, "mueble_claro")
    for (dx, dz, n) in ((140, 520, 6), (165, 528, 3)):
        caja(l, dx, 0, dz, dx + 12, 12, dz + 12, "plastico_blanco")
        for k in range(n):
            caja(l, dx + 2 + (k % 3) * 3.5, 12, dz + 2 + (k // 3) * 6, dx + 4 + (k % 3) * 3.5, 12.4, dz + 4 + (k // 3) * 6, "plastico_negro")
    for (bx, bz, m) in ((200, 440, "plastico_rojo"), (395, 188, "plastico_verde"), (150, 200, "plastico_amarillo"),
                        (330, 158, "plastico_azul")):
        caja(l, bx, 0, bz, bx + 16, 10, bz + 8, m)
        for i in range(4):
            for j in range(2):
                l.cilindro(X(bx + 2 + i * 4), Y(10), Z(bz + 2 + j * 4), cm(1.5), cm(1.8), m)
    caja(l, 205, 10, 440, 221, 20, 448, "plastico_azul")                              # uno encima de otro
    l.esfera(X(440), Y(12), Z(300), cm(12), "plastico_naranja")
    caja(l, 428, 11.5, 299.5, 452, 12.5, 300.5, "plastico_negro")
    tag(l, "EL ESTANTE DE LOS JUGUETES (pared norte,")
    # --- EL ESTANTE DE LOS JUGUETES (pared norte, al este de la ventana) con cajones de colores -------------------------
    cascara(l, 340, 0, 0, 440, 60, 32, "mueble_claro", g=2)
    caja(l, 342, 2, 30, 438, 58, 32, "mueble_claro", hueco=True)
    caja(l, 342, 29, 0, 438, 31, 32, "mueble_claro")
    cols = ("plastico_rojo", "plastico_azul", "plastico_verde", "plastico_amarillo", "plastico_morado", "plastico_naranja")
    for i in range(3):
        for j in range(2):
            caja(l, 345 + i * 31, 2 + j * 29, 4, 372 + i * 31, 22 + j * 29, 30, cols[i + j * 3])
    l.esfera(X(360), Y(68), Z(14), cm(8), "plastico_verde")
    caja(l, 400, 60, 6, 420, 80, 26, "plastico_rojo")
    tag(l, "UN AVION DE PAPEL, UNA PILA DE ROPA Y CA")
    # --- UN AVION DE PAPEL, UNA PILA DE ROPA Y CALCETINES -----------------------------------------------------------------
    caja(l, 300, 0, 140, 330, 1, 146, "papel")
    caja(l, 312, 1, 136, 318, 4, 150, "papel")
    for k in range(5):
        caja(l, 258 + rng.uniform(-3, 3), k * 2, 300 + rng.uniform(-3, 3), 282 + rng.uniform(-3, 3), k * 2 + 2,
             318 + rng.uniform(-3, 3), rng.choice(("plastico_azul", "plastico_rojo", "papel", "plastico_verde")))
    caja(l, 240, 0, 516, 252, 2, 522, "plastico_blanco")
    caja(l, 248, 0, 522, 252, 2, 530, "plastico_blanco")
    tag(l, "UNA CAJA DE CRAYONES GIGANTE abierta")
    # --- UNA CAJA DE CRAYONES GIGANTE abierta ---------------------------------------------------------------------------
    cascara(l, 55, 0, 432, 85, 30, 452, "plastico_amarillo", g=1.5, abierta_arriba=True)
    for i, m in enumerate(("plastico_rojo", "plastico_azul", "plastico_verde", "plastico_morado", "plastico_naranja")):
        caja(l, 58 + i * 5, 1.5, 438, 62 + i * 5, 40, 446, m)


# ====================================================================================================== como la referencia
# (2026-10-21, pedido con capturas de Mini Royale: "hay mas cosas: un tren que anda por todo el mapa y se puede romper
# con su via, el tablero de ajedrez, el rompecabezas con piezas, obstaculos para el fuego cruzado")
TREN_C = (255.0, 325.0)          # la via: un rectangulo redondeado alrededor de la alfombra
TREN_MEDIO = (125.0, 85.0)
TREN_R = 40.0
VIA_ARRIBA = 3.0                 # cm: lo alto de los rieles (el tren va encima)


def camino_tren(paso=2.5):
    """los puntos (cm) de la via, en orden, una vuelta"""
    cx, cz = TREN_C
    hx, hz = TREN_MEDIO[0] - TREN_R, TREN_MEDIO[1] - TREN_R
    pts = []
    esquinas = ((cx + hx, cz + hz, 0.0), (cx - hx, cz + hz, 90.0), (cx - hx, cz - hz, 180.0), (cx + hx, cz - hz, 270.0))
    for i, (ex, ez, a0) in enumerate(esquinas):
        n = max(2, int(TREN_R * math.pi / 2 / paso))
        for k in range(n):
            a = math.radians(a0 + 90.0 * k / n)
            pts.append((ex + math.cos(a) * TREN_R, ez + math.sin(a) * TREN_R))
        sx, sz = esquinas[(i + 1) % 4][0], esquinas[(i + 1) % 4][1]
        a1 = math.radians(a0 + 90.0)
        p0 = (ex + math.cos(a1) * TREN_R, ez + math.sin(a1) * TREN_R)
        p1 = (sx + math.cos(a1) * TREN_R, sz + math.sin(a1) * TREN_R)
        largo = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        n = max(1, int(largo / paso))
        for k in range(n):
            t = k / n
            pts.append((p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t))
    return pts


def alfombras(l, rng):
    tag(l, "alfombras")
    """lo que va DEBAJO de todo (antes de los juguetes): el suelo de goma tipo rompecabezas y el fieltro del golf"""
    cols = ("plastico_rojo", "plastico_azul", "plastico_amarillo", "plastico_verde", "plastico_naranja",
            "plastico_morado", "plastico_rosa", "plastico_celeste")
    x0, z0, t = 100, 100, 30
    for i in range(4):
        for j in range(4):
            if (i, j) in ((3, 3), (0, 3)):
                continue                        # dos piezas sueltas (estan tiradas al lado)
            m = cols[(i * 3 + j * 5) % len(cols)]
            a, b = x0 + i * t, z0 + j * t
            caja(l, a, 0, b, a + t, 1.2, b + t, m)
            if i < 3:                           # la pestaña que encaja con la de al lado
                caja(l, a + t, 0, b + 11, a + t + 4, 1.2, b + 19, m)
            if j < 3:
                caja(l, a + 11, 0, b + t, a + 19, 1.2, b + t + 4, m)
    for (px, pz, m) in ((235, 100, "plastico_morado"), (60, 200, "plastico_celeste")):
        caja(l, px, 0, pz, px + t, 1.2, pz + t, m)
        caja(l, px + t, 0, pz + 11, px + t + 4, 1.2, pz + 19, m)
    caja(l, 240, 0, 30, 335, 1.5, 100, "fieltro")


def escenarios(l, rng):
    tag(l, "escenarios")
    pts = camino_tren()
    n = len(pts)
    tag(l, "EL PASO DEL TREN: se vacia un pasillo en")
    # --- EL PASO DEL TREN: se vacia un pasillo encima de la via (cruza lo que haya) y luego la via -----------------
    for k in range(n):
        x, z = pts[k]
        caja(l, x - 8, 1.2, z - 8, x + 8, 22, z + 8, "madera_juguete", hueco=True)
    for k in range(n):
        x, z = pts[k]
        x2, z2 = pts[(k + 1) % n]
        dx, dz = x2 - x, z2 - z
        d = math.hypot(dx, dz) or 1.0
        nx, nz = -dz / d, dx / d                # el lado
        caja(l, x - 5, 0, z - 5, x + 5, 2, z + 5, "madera_juguete")          # la tabla de la via
        for s in (-3.0, 3.0):                   # los dos rieles
            rx, rz = x + nx * s, z + nz * s
            caja(l, rx - 0.9, 2, rz - 0.9, rx + 0.9, VIA_ARRIBA, rz + 0.9, "riel")
    # un TUNEL de juguete en la recta del oeste y una ESTACION junto a la del este
    for k in range(9):
        zz = 290 + k * 8
        caja(l, 112, 0, zz, 116, 18, zz + 8, "plastico_verde")
        caja(l, 144, 0, zz, 148, 18, zz + 8, "plastico_verde")
        caja(l, 112, 18, zz, 148, 22, zz + 8, "plastico_verde" if k % 2 else "verde_dino")
    caja(l, 392, 0, 300, 420, 4, 345, "plastico_blanco")                     # el anden
    for pz in (302, 340):
        caja(l, 414, 4, pz, 417, 26, pz + 3, "plastico_rojo")
    caja(l, 390, 26, 298, 422, 29, 345, "plastico_rojo")                    # el techito
    caja(l, 405, 4, 316, 412, 10, 326, "mueble_claro")                      # un banco
    tag(l, "EL TABLERO DE AJEDREZ con las piezas (de")
    # --- EL TABLERO DE AJEDREZ con las piezas (de cobertura) ---------------------------------------------------------
    bx, bz, cs = 395, 350, 7.5
    caja(l, bx - 2, 0, bz - 2, bx + 8 * cs + 2, 4, bz + 8 * cs + 2, "mueble_osc")
    for i in range(8):
        for j in range(8):
            caja(l, bx + i * cs, 4, bz + j * cs, bx + (i + 1) * cs, 4.6, bz + (j + 1) * cs,
                 "ajedrez_blanco" if (i + j) % 2 == 0 else "ajedrez_negro")
    # LAS PIEZAS, TORNEADAS (2026-10-21, pedido: "las piezas son horribles, cuadradas, sin forma"): cada una sale de su
    # PERFIL (alto, radio) en rodajas de 1 cm = un voxel, como en un torno: peana con molduras, cuerpo que se estrecha,
    # collarin y la cabeza de cada una (bola, almenas, mitra con su corte, corona, cruz, y el caballo con cabeza y crin)
    piezas = [(0, 0, "torre"), (1, 0, "caballo"), (2, 0, "alfil"), (3, 0, "reina"), (4, 0, "rey"), (6, 0, "caballo"),
              (7, 0, "torre"), (0, 1, "peon"), (1, 1, "peon"), (3, 2, "peon"), (4, 3, "peon"), (6, 1, "peon"),
              (7, 2, "peon"), (5, 2, "alfil")]
    for (i, j, tipo) in piezas:
        for lado in (0, 1):
            jj = j if lado == 0 else 7 - j
            ii = i if lado == 0 else 7 - i
            if lado == 1 and tipo in ("rey", "reina"):
                ii = i
            m = "ajedrez_blanco" if lado == 0 else "ajedrez_negro"
            pieza_ajedrez(l, bx + (ii + 0.5) * cs, 4.6, bz + (jj + 0.5) * cs, tipo, m, 1 if lado == 0 else -1)
    l.cilindro(X(388), Y(1.5), Z(420), cm(2), cm(10), "ajedrez_negro", eje="x")   # dos tiradas al lado
    l.cilindro(X(462), Y(1.5), Z(400), cm(2), cm(9), "ajedrez_blanco", eje="z")
    tag(l, "EL ROMPECABEZAS GIGANTE (carton): medio ")
    # --- EL ROMPECABEZAS GIGANTE (carton): medio armado y piezas de pie para cubrirse ---------------------------------
    pcols = ("puzzle_a", "puzzle_b", "puzzle_c", "puzzle_d")
    for i in range(5):
        for j in range(3):
            if rng.random() < 0.25:
                continue
            a, b = 112 + i * 22, 28 + j * 22
            caja(l, a, 0, b, a + 22, 1, b + 22, pcols[(i + j) % 4])
            caja(l, a + 22, 0, b + 8, a + 25, 1, b + 14, pcols[(i + j) % 4])
    for (px, pz, eje) in ((120, 94, "x"), (196, 88, "z"), (230, 40, "z"), (150, 92, "x")):
        if eje == "x":
            caja(l, px, 0, pz, px + 22, 22, pz + 1.5, rng.choice(pcols))
            caja(l, px + 8, 22, pz, px + 14, 25, pz + 1.5, rng.choice(pcols))
        else:
            caja(l, px, 0, pz, px + 1.5, 22, pz + 22, rng.choice(pcols))
            caja(l, px, 22, pz + 8, px + 1.5, 25, pz + 14, rng.choice(pcols))
    cascara(l, 200, 0, 8, 236, 6, 26, "carton", g=1, abierta_arriba=True)  # la caja del rompecabezas
    tag(l, "EL MINIGOLF: borde, rampa, el rizo rojo,")
    # --- EL MINIGOLF: borde, rampa, el rizo rojo, un molino y el hoyo --------------------------------------------------
    for (a, b, c, d) in ((240, 30, 335, 33), (240, 97, 335, 100), (240, 30, 243, 100), (332, 30, 335, 100)):
        caja(l, a, 0, b, c, 5, d, "mueble_claro")
    caja(l, 243, 1.5, 62, 300, 5, 66, "mueble_claro")                          # el tabique del medio
    l.cuna(X(250), Y(1.5), Z(70), X(275), Y(9), Z(94), sube_hacia="+x", mat="fieltro")
    caja(l, 275, 1.5, 70, 290, 9, 94, "fieltro")
    l.cuna(X(290), Y(1.5), Z(70), X(315), Y(9), Z(94), sube_hacia="-x", mat="fieltro")
    for k in range(19):                                                           # el rizo (media rueda)
        a = math.pi * k / 18
        y = 1.5 + math.sin(a) * 16
        z = 47 + math.cos(a) * 12
        caja(l, 300, y - 0.5, z - 2.5, 312, y + 2.5, z + 2.5, "plastico_rojo")
    caja(l, 255, 1.5, 38, 262, 26, 45, "plastico_blanco")                      # el molino
    caja(l, 248, 20, 40, 270, 22, 43, "plastico_rojo")
    caja(l, 257, 12, 40, 260, 32, 43, "plastico_rojo")
    l.cilindro(X(322), Y(1.3), Z(85), cm(2.5), cm(0.2), "plastico_negro")     # el hoyo y la bandera
    caja(l, 322, 1.5, 85, 322.6, 22, 85.6, "plastico_blanco")
    caja(l, 322.6, 16, 85, 330, 22, 85.6, "plastico_rojo")
    l.esfera(X(260), Y(3), Z(80), cm(1.5), "plastico_blanco")
    tag(l, "LA BASE DE LOS SOLDADITOS: sacos terrero")
    # --- LA BASE DE LOS SOLDADITOS: sacos terreros, carpas, cajas y un tanque --------------------------------------------
    for (a, b, c, d) in ((232, 142, 296, 148), (232, 222, 260, 228), (272, 222, 296, 228), (232, 148, 238, 200),
                         (290, 160, 296, 222)):
        for y in (0, 4):
            caja(l, a, y, b, c, y + 4, d, "saco")
    for (tx, tz) in ((244, 156), (264, 156)):
        l.cuna(X(tx), Y(0), Z(tz), X(tx + 8), Y(12), Z(tz + 20), sube_hacia="+x", mat="verde_militar")
        l.cuna(X(tx + 8), Y(0), Z(tz), X(tx + 16), Y(12), Z(tz + 20), sube_hacia="-x", mat="verde_militar")
    for (cx2, cz2) in ((244, 192), (254, 200), (244, 202)):
        caja(l, cx2, 0, cz2, cx2 + 8, 7, cz2 + 8, "madera_juguete")
    caja(l, 266, 0, 186, 284, 6, 208, "verde_militar")                          # el tanque
    caja(l, 269, 6, 190, 281, 10, 202, "verde_militar")
    caja(l, 274, 7, 164, 276, 9, 192, "verde_militar")
    for k in range(7):                                                            # los soldaditos de pie
        sx, sz = 240 + k * 7, 212 + (k % 2) * 3
        caja(l, sx, 0, sz, sx + 2, 6, sz + 1.5, "verde_militar")
        l.esfera(X(sx + 1), Y(7), Z(sz + 0.75), cm(1.1), "verde_militar")
    tag(l, "MUROS DE LADRILLOS DE JUGUETE y LIBROS D")
    # --- MUROS DE LADRILLOS DE JUGUETE y LIBROS DE PIE: para el fuego cruzado -------------------------------------------
    for (wx, wz, largo, eje, m) in ((300, 470, 36, "x", "plastico_azul"), (380, 432, 30, "x", "plastico_rojo"),
                                     (170, 470, 30, "x", "plastico_amarillo"), (100, 268, 24, "z", "plastico_verde"),
                                     (425, 220, 36, "z", "plastico_naranja")):
        for y in range(3):
            for k in range(int(largo / 8) + 1):
                o = k * 8 + (4 if y % 2 else 0)
                if o + 8 > largo:
                    continue
                if eje == "x":
                    caja(l, wx + o, y * 4, wz, wx + o + 8, y * 4 + 4, wz + 4, m)
                else:
                    caja(l, wx, y * 4, wz + o, wx + 4, y * 4 + 4, wz + o + 8, m)
    for (lx, lz, col) in ((300, 252, "plastico_rojo"), (304, 252, "plastico_azul"), (308, 252, "plastico_verde"),
                          (205, 372, "plastico_morado"), (209, 372, "plastico_amarillo")):
        caja(l, lx, 0, lz, lx + 3.5, 28, lz + 20, col)                          # libros de pie



def sueltos(l, rng):
    """LO SUELTO POR EL SUELO (cubos y crayones), lo ULTIMO: cada uno se prueba en un sitio al azar y solo se pone si
    no pisa nada de lo ya dibujado (ni la via del tren). Antes se ponian a ciegas y quedaban metidos en otras cosas."""
    tag(l, "sueltos")
    ocupado = []
    for pr in l.prims:
        if pr[3]:
            continue
        b = _bbox(pr)
        if b is None:
            continue
        x0, y0, z0, x1, y1, z1 = ((b[0] - OX) / 0.2, (b[1] - SUELO) / 0.2, (b[2] - OZ) / 0.2,
                                  (b[3] - OX) / 0.2, (b[4] - SUELO) / 0.2, (b[5] - OZ) / 0.2)
        if y1 <= 2.0 or y0 > 30.0 or (x1 - x0) > 300:
            continue                    # lo plano del suelo (alfombras, tapetes) y lo alto no cuentan; el cuarto tampoco
        ocupado.append((x0 - 2, z0 - 2, x1 + 2, z1 + 2))
    via = camino_tren(5.0)

    def libre(x0, z0, x1, z1):
        for (a, b, c, d) in ocupado:
            if x0 < c and x1 > a and z0 < d and z1 > b:
                return False
        cx, cz = (x0 + x1) * 0.5, (z0 + z1) * 0.5
        return all((cx - vx) ** 2 + (cz - vz) ** 2 > 14 ** 2 for (vx, vz) in via)

    colores = ("plastico_rojo", "plastico_azul", "plastico_amarillo", "plastico_verde", "plastico_naranja", "plastico_morado")
    puestos = 0
    for _ in range(400):
        if puestos >= 24:
            break
        x, z = rng.uniform(100, 430), rng.uniform(140, 540)
        if puestos < 14:
            box = (x, z, x + 5, z + 5)
        elif rng.random() < 0.5:
            box = (x, z, x + 9, z + 1.4)
        else:
            box = (x, z, x + 1.4, z + 9)
        if not libre(*box):
            continue
        caja(l, box[0], 0, box[1], box[2], 5 if puestos < 14 else 1.4, box[3], rng.choice(colores))
        ocupado.append((box[0] - 2, box[1] - 2, box[2] + 2, box[3] + 2))
        puestos += 1



# ====================================================================================================== el relleno
# MAS COSAS POR EL SUELO (2026-10-22, pedido: "hay lugares del piso muy vacios: disquetes de los 80, arbolitos de olor
# del auto, cigarrillos apagados y su caja, y muchos muros que te tapen la vision"). Cada objeto mide en cm de verdad
# (huella w x d, la de su caja de suelo) y se pone donde no pise nada (la misma cuenta que sueltos()), girado al azar de
# a 90 grados. Los altos (cajas, latas, VHS, arbolitos, muros de dominos y libros) son la cobertura de los tiroteos.
def _ocupado_de(l):
    occ = []
    for pr in l.prims:
        if pr[3]:
            continue
        b = _bbox(pr)
        if b is None:
            continue
        x0, y0, z0, x1, y1, z1 = ((b[0] - OX) / 0.2, (b[1] - SUELO) / 0.2, (b[2] - OZ) / 0.2,
                                  (b[3] - OX) / 0.2, (b[4] - SUELO) / 0.2, (b[5] - OZ) / 0.2)
        if y1 <= 2.0 or y0 > 30.0 or (x1 - x0) > 300:
            continue
        occ.append((x0 - 3, z0 - 3, x1 + 3, z1 + 3))
    return occ


def _disquete(c, x, z, rot, rng, y=0.0):
    col = rng.choice(("plastico_negro", "plastico_azul", "plastico_rojo", "plastico_amarillo", "gris_robot"))
    # (1 cm de grueso: mas fino que un voxel de 20 cm no se dibuja)
    c(0, y, 0, 9.0, y + 1.0, 9.4, col)
    c(2.2, y + 0.8, 0.0, 6.8, y + 1.0, 3.0, "riel")                     # la chapita de metal
    c(0.8, y + 0.8, 4.6, 8.2, y + 1.0, 9.0, "papel")                    # la etiqueta


def _arbolito(c, x, z, rot, rng):
    col = rng.choice(("verde_dino", "plastico_verde", "plastico_rojo", "plastico_amarillo", "plastico_azul"))
    # de pie, apoyado en su base de carton: tres pisos de copa y el tronco
    c(2.4, 0, 0, 4.6, 1.2, 1.2, "carton")
    c(2.9, 1.2, 0.0, 4.1, 2.6, 1.2, col)
    for k, (ancho, alto) in enumerate(((7.0, 3.6), (5.6, 3.0), (4.0, 2.6))):
        y0 = 2.6 + sum(a for _, a in ((7.0, 3.6), (5.6, 3.0), (4.0, 2.6))[:k])
        m = (7.0 - ancho) * 0.5
        c(m, y0, 0.0, 7.0 - m, y0 + alto, 1.2, col)
    c(3.0, 11.8, 0.0, 4.0, 14.5, 1.2, "plastico_blanco")                # el hilo


def _cigarrillo(c, x, z, rot, rng):
    c(1.0, 0, 0, 6.0, 1.0, 1.0, "papel")
    c(6.0, 0, 0, 8.4, 1.0, 1.0, "plastico_naranja")                     # el filtro
    c(0.0, 0, 0, 1.0, 1.0, 1.0, "plastico_negro")                       # la punta quemada, apagada


def _caja_cigarrillos(c, x, z, rot, rng):
    col = rng.choice(("plastico_rojo", "plastico_blanco", "plastico_azul"))
    c(0, 0, 0, 5.6, 8.8, 2.3, col)
    c(0, 6.4, 0, 5.6, 6.8, 2.3, "plastico_blanco")                      # la franja de la tapa
    c(0.6, 1.6, -0.05, 5.0, 4.6, 0.0, "plastico_negro")                 # el aviso
    if rng.random() < 0.6:
        c(0.8, 8.8, 0.4, 1.6, 10.0, 1.2, "papel")                       # un cigarrillo que asoma
        c(0.8, 10.0, 0.4, 1.6, 10.4, 1.2, "plastico_naranja")


def _lata(c, x, z, rot, rng, l=None):
    pass


def _vhs(c, x, z, rot, rng):
    c(0, 0, 0, 18.8, 10.2, 2.5, "plastico_negro")                       # de pie, sobre el canto largo
    c(3.0, 3.0, -0.05, 15.8, 7.4, 0.0, "papel")
    c(6.0, 4.2, -0.1, 8.6, 6.4, -0.05, "gris_robot")                    # las ventanitas de los carretes
    c(10.2, 4.2, -0.1, 12.8, 6.4, -0.05, "gris_robot")


def _casete(c, x, z, rot, rng):
    c(0, 0, 0, 10.0, 1.2, 6.4, rng.choice(("plastico_blanco", "plastico_negro", "plastico_celeste")))
    c(1.0, 1.2, 1.0, 9.0, 1.3, 5.4, "papel")
    c(3.0, 1.3, 2.4, 7.0, 1.35, 3.8, "plastico_negro")


def _rubik(c, x, z, rot, rng):
    cols = ("plastico_rojo", "plastico_azul", "plastico_verde", "plastico_amarillo", "plastico_naranja", "plastico_blanco")
    for i in range(3):
        for j in range(3):
            for k in range(3):
                c(i * 1.9, j * 1.9, k * 1.9, i * 1.9 + 1.85, j * 1.9 + 1.85, k * 1.9 + 1.85, rng.choice(cols))


def _caja_zapatos(c, x, z, rot, rng):
    col = rng.choice(("carton", "plastico_naranja", "plastico_azul"))
    c(0, 0, 0, 32.0, 11.0, 19.0, col)
    c(-0.4, 9.0, -0.4, 32.4, 12.0, 19.4, "plastico_blanco" if col != "plastico_blanco" else "carton")   # la tapa


def _taza(c, x, z, rot, rng):
    pass


def _gameboy(c, x, z, rot, rng):
    c(0, 0, 0, 9.0, 2.8, 14.8, "gris_robot")                            # acostada
    c(1.4, 2.8, 1.2, 7.6, 2.9, 6.4, "plastico_verde")                   # la pantalla
    c(1.4, 2.8, 9.0, 3.6, 3.2, 11.2, "plastico_negro")                  # la cruz
    c(5.6, 2.8, 9.6, 6.6, 3.3, 10.6, "plastico_rojo")
    c(7.0, 2.8, 8.6, 8.0, 3.3, 9.6, "plastico_rojo")


def _muro_dominos(c, x, z, rot, rng):
    for k in range(8):
        c(k * 4.0, 0, 0, k * 4.0 + 1.6, 9.6, 4.8, "plastico_blanco")
        c(k * 4.0 - 0.05, 4.6, 0.4, k * 4.0 + 1.65, 5.0, 4.4, "plastico_negro")


def _muro_libros(c, x, z, rot, rng):
    k = 0.0
    while k < 34.0:
        g = rng.uniform(3.0, 5.0)
        h = rng.uniform(20.0, 28.0)
        c(k, 0, 0, k + g, h, 17.0, rng.choice(("plastico_rojo", "plastico_azul", "plastico_verde", "plastico_amarillo",
                                              "plastico_morado", "mueble_osc")))
        k += g + 0.2


# los puntos de cada cara del dado, en una rejilla 3 x 3 (0..2): como uno de verdad, las caras opuestas suman 7
PUNTOS_DADO = {1: [(1, 1)], 2: [(0, 0), (2, 2)], 3: [(0, 0), (1, 1), (2, 2)], 4: [(0, 0), (0, 2), (2, 0), (2, 2)],
               5: [(0, 0), (0, 2), (1, 1), (2, 0), (2, 2)], 6: [(0, 0), (0, 2), (1, 0), (1, 2), (2, 0), (2, 2)]}


def _dado(c, x, z, rot, rng):
    L, pp, g = 5.0, 0.9, 0.3
    c(0, 0, 0, L, L, L, "plastico_blanco")

    def pts(cara, n):
        for (i, j) in PUNTOS_DADO[n]:
            u = 0.8 + i * 1.4
            v = 0.8 + j * 1.4
            if cara == "arriba":
                c(u, L - 0.01, v, u + pp, L + g, v + pp, "plastico_negro")
            elif cara == "frente":
                c(u, v, -g, u + pp, v + pp, 0.01, "plastico_negro")
            elif cara == "atras":
                c(u, v, L - 0.01, u + pp, v + pp, L + g, "plastico_negro")
            elif cara == "izq":
                c(-g, u, v, 0.01, u + pp, v + pp, "plastico_negro")
            elif cara == "der":
                c(L - 0.01, u, v, L + g, u + pp, v + pp, "plastico_negro")
    arriba = rng.randint(1, 6)
    lados = [n for n in (1, 2, 3, 4, 5, 6) if n != arriba and n != 7 - arriba]
    pts("arriba", arriba)
    pts("frente", lados[0])
    pts("atras", 7 - lados[0])
    pts("izq", lados[1])
    pts("der", 7 - lados[1])


def _moneda(c, x, z, rot, rng, y=0.0, l=None):
    pass


def _naipe(c, x, z, rot, rng):
    palo = rng.choice(("plastico_rojo", "plastico_negro"))
    c(0, 0, 0, 6.4, 1.0, 8.8, "plastico_blanco")
    c(0.4, 1.0, 0.4, 6.0, 1.05, 8.4, "plastico_blanco")
    c(2.6, 0.9, 3.6, 3.8, 1.1, 5.2, palo)                               # el palo en el medio
    c(0.6, 0.9, 0.6, 1.4, 1.1, 1.6, palo)                               # y las esquinas
    c(5.0, 0.9, 7.2, 5.8, 1.1, 8.2, palo)


def _naipe_de_pie(c, x, z, rot, rng):
    palo = rng.choice(("plastico_rojo", "plastico_negro"))
    c(0, 0, 0, 6.4, 8.8, 1.0, "plastico_blanco")
    c(2.6, 3.6, -0.1, 3.8, 5.2, 0.0, palo)
    c(2.6, 3.6, 1.0, 3.8, 5.2, 1.1, palo)


def _zapatilla(c, x, z, rot, rng):
    col = rng.choice(("plastico_rojo", "plastico_azul", "plastico_negro", "plastico_verde"))
    # 30 cm de largo (a lo ancho del objeto), 11 de ancho y 12 de alto: suela, puntera, empeine, cordones y talon
    c(0, 0, 0, 30, 2.4, 11, "plastico_blanco")                          # la suela
    c(0, 0, -0.2, 30, 0.6, 11.2, "goma_negra")                          # la goma de abajo
    c(22, 2.4, 0.6, 29.4, 5.0, 10.4, "plastico_blanco")                 # la puntera
    c(1, 2.4, 0.4, 22, 9.0, 10.6, col)                                   # el cuerpo
    c(0.4, 2.4, 1.0, 6.0, 12.0, 10.0, col)                               # el talon, mas alto
    c(0.0, 9.0, 3.6, 1.4, 12.4, 7.4, "plastico_blanco")                 # la lengüeta de atras
    c(8, 9.0, 1.4, 21, 9.6, 9.6, "plastico_blanco")                     # la abertura (forro claro)
    c(9, 9.0, 3.4, 21, 10.8, 7.6, col)                                   # la lengüeta
    for k in range(5):                                                   # los cordones cruzados
        xk = 10.0 + k * 2.2
        c(xk, 10.8, 3.0, xk + 1.0, 11.4, 8.0, "plastico_blanco")
    c(11, 4.0, 0.0, 19, 6.4, 0.4, "plastico_blanco")                    # el logo, a los dos lados
    c(11, 4.0, 10.6, 19, 6.4, 11.0, "plastico_blanco")
    c(20.0, 5.0, 3.0, 22.0, 9.0, 8.0, "plastico_blanco")                # la lengüeta delantera


def _tobogan(c, x, z, rot, rng):
    """EL TOBOGAN GIGANTE (pedido: "como una rampa, pero fina"): escalera, plataforma con baranda y la rampa fina que
    baja en tramos de 2 cm (cada uno se apoya en el de antes), con sus bordes y las patas"""
    col = rng.choice(("plastico_rojo", "plastico_azul", "plastico_amarillo", "plastico_verde"))
    col2 = "plastico_amarillo" if col != "plastico_amarillo" else "plastico_azul"
    alto = 40.0
    # la plataforma y sus cuatro patas
    for (px, pz) in ((10, 0), (22, 0), (10, 14), (22, 14)):
        c(px, 0, pz, px + 2, alto, pz + 2, col2)
    c(10, alto, 0, 24, alto + 2, 16, col)
    c(10, alto + 2, 0, 24, alto + 9, 1.4, col2)                           # la baranda de atras y los lados
    c(10, alto + 2, 14.6, 24, alto + 9, 16, col2)
    # la escalera (largueros y peldaños)
    c(0, 0, 1, 2, alto + 2, 3, col2)
    c(0, 0, 13, 2, alto + 2, 15, col2)
    for k in range(9):
        y = 3.0 + k * 4.4
        c(0, y, 3, 10, y + 1.2, 13, col)
    # la rampa fina: de la plataforma al suelo en 60 cm, tramos de 2 cm que se pisan
    largo, tramos = 62.0, 31
    for k in range(tramos):
        x0 = 24 + k * largo / tramos
        y0 = alto + 0.5 - (k + 1) * (alto / tramos)
        c(x0, max(0.0, y0), 1.5, x0 + largo / tramos + 0.6, max(0.0, y0) + 1.6, 14.5, col)
        c(x0, max(0.0, y0) + 1.6, 1.5, x0 + largo / tramos + 0.6, max(0.0, y0) + 4.0, 2.5, col2)     # los bordes
        c(x0, max(0.0, y0) + 1.6, 13.5, x0 + largo / tramos + 0.6, max(0.0, y0) + 4.0, 14.5, col2)
    c(38, 0, 7, 40, 20, 9, col2)                                           # un apoyo a media rampa
    c(38, 0, 7, 40, alto * 0.62, 9, col2)


OBJETOS = [
    ("tobogan", (86.0, 16.0), 3, _tobogan),
    ("dado", (5.6, 5.6), 10, _dado),
    ("moneda", (2.6, 2.6), 14, None),
    ("pila_monedas", (2.6, 2.6), 5, None),
    ("naipe", (6.4, 8.8), 10, _naipe),
    ("naipe_de_pie", (6.4, 1.0), 6, _naipe_de_pie),
    ("zapatilla", (30.0, 11.2), 2, _zapatilla),
    # (nombre, huella w x d en cm, cuantos, constructor, prims extra: cilindros)
    ("disquete", (9.4, 9.4), 10, _disquete),
    ("pila_disquetes", (9.4, 9.4), 3, None),
    ("disquete_de_pie", (9.4, 1.0), 3, None),
    ("arbolito", (7.0, 1.0), 9, _arbolito),
    ("cigarrillo", (8.6, 1.0), 8, _cigarrillo),
    ("caja_cigarrillos", (5.6, 2.3), 6, _caja_cigarrillos),
    ("vhs", (18.8, 2.5), 6, _vhs),
    ("casete", (10.0, 6.4), 5, _casete),
    ("rubik", (5.7, 5.7), 4, _rubik),
    ("caja_zapatos", (32.4, 19.4), 4, _caja_zapatos),
    ("gameboy", (9.0, 14.8), 2, _gameboy),
    ("muro_dominos", (32.0, 4.8), 6, _muro_dominos),
    ("muro_libros", (34.0, 17.0), 5, _muro_libros),
    ("lata", (6.6, 6.6), 8, None),
    ("taza", (9.0, 8.0), 3, None),
]


def relleno(l, rng):
    tag(l, "RELLENO DEL SUELO")
    ocupado = _ocupado_de(l)
    via = camino_tren(5.0)
    zonas_avion = ((140, 495, 260, 600),)                 # la estanteria y la rampa: nada delante

    def libre(x0, z0, x1, z1):
        for (a, b, c2, d) in ocupado:
            if x0 < c2 and x1 > a and z0 < d and z1 > b:
                return False
        for (a, b, c2, d) in zonas_avion:
            if x0 < c2 and x1 > a and z0 < d and z1 > b:
                return False
        if x0 < 2 or z0 < 2 or x1 > 498 or z1 > 598:
            return False
        cx, cz = (x0 + x1) * 0.5, (z0 + z1) * 0.5
        r = max(x1 - x0, z1 - z0) * 0.5 + 10
        return all((cx - vx) ** 2 + (cz - vz) ** 2 > r * r for (vx, vz) in via)

    puestos = 0
    for (nombre, (w, d), n, fn) in OBJETOS:
        hechos = 0
        for _ in range(500):
            if hechos >= n:
                break
            girado = rng.random() < 0.5
            ww, dd = (d, w) if girado else (w, d)
            x, z = rng.uniform(4, 494 - ww), rng.uniform(4, 594 - dd)
            if not libre(x, z, x + ww, z + dd):
                continue

            def c(a0, b0, c0, a1, b1, c1, m, _x=x, _z=z, _g=girado):
                # coordenadas del objeto (a lo ancho a, alto b, fondo c) -> del cuarto, girado 90 si toca
                if _g:
                    caja(l, _x + c0, b0, _z + a0, _x + c1, b1, _z + a1, m)
                else:
                    caja(l, _x + a0, b0, _z + c0, _x + a1, b1, _z + c1, m)
            if fn is not None:
                fn(c, x, z, girado, rng)
            elif nombre == "pila_disquetes":
                for k in range(rng.randint(4, 7)):
                    _disquete(c, x, z, girado, rng, y=k * 1.0)
            elif nombre == "disquete_de_pie":
                # de pie, apoyado contra nada: de canto (9 de alto)
                col = rng.choice(("plastico_negro", "plastico_azul", "plastico_rojo"))
                c(0, 0, 0, 9.4, 9.0, 1.0, col)
                c(0.8, 4.4, 0.0, 8.6, 8.4, 0.2, "papel")
            elif nombre == "lata":
                col = rng.choice(("plastico_rojo", "plastico_azul", "plastico_verde", "plastico_naranja", "plastico_morado"))
                cx, cz = x + ww * 0.5, z + dd * 0.5
                if rng.random() < 0.3:                       # tirada
                    l.cilindro(X(cx - 6), Y(3.3), Z(cz), cm(3.3), cm(12.2), col, eje="x")
                else:
                    l.cilindro(X(cx), Y(0), Z(cz), cm(3.3), cm(12.2), col)
                    l.cilindro(X(cx), Y(12.2), Z(cz), cm(2.6), cm(0.4), "riel")
            elif nombre in ("moneda", "pila_monedas"):
                cx, cz = x + 1.3, z + 1.3
                mat = rng.choice(("moneda_cobre", "moneda_plata", "moneda_oro"))
                for k in range(1 if nombre == "moneda" else rng.randint(3, 8)):
                    l.cilindro(X(cx + rng.uniform(-0.2, 0.2)), Y(k * 1.0), Z(cz + rng.uniform(-0.2, 0.2)), cm(1.25), cm(1.0), mat)
                    l.cilindro(X(cx), Y(k * 1.0 + 0.8), Z(cz), cm(0.8), cm(0.3), mat)
            elif nombre == "taza":
                cx, cz = x + 4.0, z + 4.0
                col = rng.choice(("plastico_blanco", "plastico_rojo", "plastico_amarillo"))
                l.cilindro(X(cx), Y(0), Z(cz), cm(4.0), cm(9.0), col)
                l.cilindro(X(cx), Y(0.8), Z(cz), cm(2.8), cm(8.4), col, hueco=True)
                c(6.6, 2.0, 3.0, 9.4, 7.0, 5.0, col)                 # el asa (metida en la pared de la taza)
            ocupado.append((x - 3, z - 3, x + ww + 3, z + dd + 3))
            hechos += 1
        puestos += hechos
    print("  relleno: %d cosas por el suelo" % puestos)


def json_tren():
    """el camino del tren (metros, encima de los rieles) para tren_cuarto.gd"""
    return {"camino": [[round(X(x), 2), round(Y(VIA_ARRIBA), 2), round(Z(z), 2)] for (x, z) in camino_tren(5.0)],
            "velocidad": 3.2, "vagones": 4}


def luces(l):
    l.luz(X(250), Y(236), Z(300), (255, 236, 200), 3.0, 70.0)
    l.luz(X(250), Y(200), Z(150), (255, 240, 210), 2.0, 50.0)
    l.luz(X(250), Y(200), Z(450), (255, 240, 210), 2.0, 50.0)
    l.luz(X(486), Y(96), Z(125), (255, 220, 160), 1.6, 22.0)            # el flexo
    # la lampara del techo
    pass  # l.cilindro(X(250), Y(232), Z(300), cm(14), cm(8), "plastico_blanco")
    pass  # l.cilindro(X(250), Y(228), Z(300), cm(9), cm(4), "luz_lampara")


# ====================================================================================================== el botin
def botin(rng):
    puntos = []

    def p(xc, yc, zc, zona):
        tipo = rng.choices(("arma", "municion", "escudo", "casco", "venda", "botiquin"), (30, 26, 12, 10, 14, 8))[0]
        nivel = rng.choices((1, 2, 3), (25, 55, 20))[0]
        puntos.append({"pos": [round(X(xc), 2), round(Y(yc) + 0.3, 2), round(Z(zc), 2)], "tipo": tipo, "nivel": nivel, "zona": zona})

    for _ in range(70):                                   # el suelo
        x, z = rng.uniform(100, 430), rng.uniform(20, 540)
        if 160 < x < 240 and 270 < z < 340:
            continue
        p(x, 1, z, "suelo")
    for _ in range(14):                                   # debajo de la cama
        p(rng.uniform(8, 84), 0, rng.uniform(48, 222), "debajo_cama")
    for _ in range(16):                                   # encima de la cama
        p(rng.uniform(10, 80), 47.5, rng.uniform(100, 224), "cama")
    for _ in range(10):                                   # el escritorio
        p(rng.uniform(444, 496), 76, rng.uniform(64, 176), "escritorio")
    for _ in range(8):                                    # el ropero
        p(rng.uniform(452, 494), 3, rng.uniform(450, 585), "ropero")
        p(rng.uniform(452, 494), 103, rng.uniform(450, 585), "ropero")
    for _ in range(8):                                    # el castillo
        p(rng.uniform(168, 232), 4, rng.uniform(278, 332), "castillo")
    for k in range(5):                                    # la estanteria
        p(rng.uniform(156, 244), k * 30 + 2.5, 585, "estanteria")
    for _ in range(4):
        p(rng.uniform(290, 350), 3, rng.uniform(560, 590), "baul")
    for _ in range(3):
        p(rng.uniform(180, 300), 88, 6, "ventana")
    return puntos


def json_br():
    return {
        "nombre": "LA HABITACIÓN",
        # el avion vuela bajo el techo, despacio (el cuarto mide 100 x 120)
        "altura": round(SUELO + 42.0, 1), "mar": -10.0, "velocidad": 5.0, "fuera": 6.0, "aproximacion": 2.0, "abrir_solo": 12.0, "dist_camara": 11.0, "escala_avion": 0.25,
        # LA CAIDA LIBRE (pedido: "mas lenta y que me pueda mover a los costados, como un battle royale de verdad"): se cae
        # despacio y se planea mucho de lado
        "jugadores": 20, "jugadores_movil": 12,     # personas + bots (en el movil, menos: el lag eran los bots)
        "caida": 6.0, "caida_picado": 12.0, "avance_libre": 20.0, "giro_libre": 6.0,
        "zona": {"radio_inicial": 85.0, "radios": [58.0, 40.0, 26.0, 15.0, 7.0, 0.0], "primera": 75.0, "ciclo": 125.0,
                 "cierre": 45.0, "alto_muro": 60.0},
        # EL AVION EN EL SUELO con la rampa abierta (la sala de espera): aqui se sube; luego se cierra y despega
        # ARRIBA DE LA ESTANTERIA (pedido: "el lobby del avion, arriba de la estanteria de los libros; que no se puedan
        # bajar hasta que empiece"): el corral son muros invisibles alrededor del techo de la estanteria
        "hangar": {"pos": [round(X(200), 2), round(Y(150), 2), round(Z(560), 2)], "rumbo": 0.0, "espera": 90.0,     # un minuto y medio de espera (pedido)
                  
                   "salida": [round(X(236), 2), round(Y(150) + 0.2, 2), round(Z(588), 2)],
                   # EL CORRAL SIGUE EL BORDE (2026-10-22, bug: "me caigo igual"): un rectangulo dejaba sin muro los dos
                   # costados de la rampa, donde no hay piso. Tramos [x0, z0, x1, z1] por el canto de la estanteria y
                   # de la rampa, y la altura del piso
                   "corral_y": round(Y(150), 2),
                   "corral_muros": [[round(X(a), 2), round(Z(b), 2), round(X(c), 2), round(Z(d), 2)] for (a, b, c, d) in (
                       (150, 600, 250, 600), (150, 570, 150, 600), (250, 570, 250, 600),
                       (150, 570, 178, 570), (222, 570, 250, 570),
                       (178, 535, 178, 570), (222, 535, 222, 570), (178, 535, 222, 535))]},
        # LAS RATAS (ratas.gd): salen de debajo de la cama, del ropero, de detras del baul y de junto a la puerta
        "ratas": {"max": 3, "primera": 60.0, "cada": 60.0,     # una por minuto (pedido)
                 
                  "salidas": [[round(X(45), 2), round(SUELO + 0.3, 2), round(Z(140), 2)],
                              [round(X(470), 2), round(SUELO + 0.3, 2), round(Z(520), 2)],
                              [round(X(320), 2), round(SUELO + 0.3, 2), round(Z(540), 2)],
                              [round(X(480), 2), round(SUELO + 0.3, 2), round(Z(400), 2)]]},
        "tren": json_tren(),
        "source": "tools/generar_mapa_cuarto.py",
    }


# ====================================================================================================== el revisor
def _bbox(pr):
    tipo, d = pr[0], pr[1]
    if tipo in ("caja", "cuna"):
        return d[:6]
    if tipo == "cilindro":
        cx, y0, cz, r, al, eje = d
        if eje == "y":
            return (cx - r, y0, cz - r, cx + r, y0 + al, cz + r)
        if eje == "x":
            return (cx, y0 - r, cz - r, cx + al, y0 + r, cz + r)
        return (cx - r, y0 - r, cz, cx + r, y0 + r, cz + al)
    if tipo == "elipsoide":
        cx, cy, cz, rx, ry, rz = d
        return (cx - rx, cy - ry, cz - rz, cx + rx, cy + ry, cz + rz)
    return None


def auditar(lz, vol, id_de, vs):
    import mapa_cuarto_audita as AU
    ancla = {id_de[n] for n in ("roca_base", "parquet", "pared_azul", "zocalo", "techo", "nube", "marco_blanco") if n in id_de}

    def a_cm(i0, i1, k):
        org = (OX, SUELO, OZ)[k]
        return (round((i0 * vs - org) / 0.2), round((i1 * vs - org) / 0.2))
    fl = AU.flotantes(vol, ancla, vs, a_cm)
    print("== FLOTANTES: %d" % len(fl))
    for nv, bb in fl[:80]:
        print("   %6d vox  x %s  y %s  z %s (cm)" % (nv, bb[0], bb[1], bb[2]))
    # los objetos: cada primitiva con el tag que tenia al dibujarse
    limites = TAGS + [(len(lz.prims), "")]
    pt = []
    for k in range(len(TAGS)):
        nombre = TAGS[k][1]
        if nombre in ("cuarto", "alfombras") or nombre.startswith("LA ALFOMBRA") or nombre.startswith("EL PASO DEL TREN"):
            continue
        for i in range(TAGS[k][0], limites[k + 1][0]):
            b = _bbox(lz.prims[i])
            if b is not None:
                pt.append((nombre, b, lz.prims[i][3]))
    # LO QUE CORTA EL PASO DEL TREN (el pasillo vacia lo que cruza: no deberia cruzar nada)
    via = camino_tren(5.0)
    cortados = set()
    for (nombre, bb, h) in pt:
        if h or nombre in ("EL PASO DEL TREN: se vacia un pasillo en",):
            continue
        x0, y0, z0, x1, y1, z1 = ((bb[0] - OX) / 0.2, (bb[1] - SUELO) / 0.2, (bb[2] - OZ) / 0.2, (bb[3] - OX) / 0.2, (bb[4] - SUELO) / 0.2, (bb[5] - OZ) / 0.2)
        if y1 <= 1.6 or y0 >= 22:
            continue
        for (vx, vz) in via:
            if x0 < vx + 8 and x1 > vx - 8 and z0 < vz + 8 and z1 > vz - 8:
                cortados.add((nombre, round(vx), round(vz)))
                break
    print("== CORTADOS POR LA VIA: %d" % len(cortados))
    for c in sorted(cortados):
        print("   ", c)
    so = AU.solapes(pt, vs)
    print("== METIDOS UNO EN OTRO: %d" % len(so))
    for (a, b), (v, en) in so:
        print("   %-42s <-> %-42s  %.2f m3  en %s" % (a, b, v, str(en)))


# ====================================================================================================== escribir
def main():
    t0 = time.time()
    materiales()
    print("== %s: %.1f x %.1f x %.1f m (20 cm)" % (NOMBRE, CHUNKS_LO[0] * 6.4, CHUNKS_LO[1] * 6.4, CHUNKS_LO[2] * 6.4))
    rng = random.Random(SEMILLA)
    lz = L.Lienzo()
    cuarto(lz, rng)
    muebles(lz, rng)
    alfombras(lz, rng)
    juguetes(lz, rng)
    mas_juguetes(lz, rng)
    escenarios(lz, rng)
    relleno(lz, rng)
    sueltos(lz, rng)
    luces(lz)
    print("  %d primitivas, %d luces" % (len(lz.prims), len(lz.luces)))
    usados = {p[2] for p in lz.prims}
    entradas, id_de, nvar, codigo, desp = pintura.construir_paleta(usados, G.FISICA, por_nombre())
    print("  paleta: %d materiales, %d colores (de 240)" % (len(id_de), len(entradas)))
    VAR = raster.textura_variacion(SEMILLA)
    # SOLO EL DE 20 CM (lo de pintura.rasterizar, sin la pasada de 10 cm)
    vs = 0.2
    dvox = (CHUNKS_LO[0] * 32, CHUNKS_LO[1] * 32, CHUNKS_LO[2] * 32)
    lista, cajas = R.preparar(lz.prims, vs, dvox, id_de)
    alto = int(min(dvox[1], max(64, math.ceil(int(cajas[:, 3].max()) / 32.0) * 32)))
    lo = {}
    s_lo = 0
    audita = os.environ.get("CUARTO_AUDITA") == "1"
    vol_total = np.zeros((dvox[0], alto, dvox[2]), np.uint8) if audita else None
    B = R.BALDOSA // 2
    ntx, ntz = (dvox[0] + B - 1) // B, (dvox[2] + B - 1) // B
    for tz in range(ntz):
        for tx in range(ntx):
            b0x, b0z = tx * B, tz * B
            vl = R.rasterizar_baldosa(lista, cajas, (b0x, b0x + B, b0z, b0z + B), alto, vs)
            if audita:
                ex, ez = min(B, dvox[0] - b0x), min(B, dvox[2] - b0z)
                vol_total[b0x:b0x + ex, :, b0z:b0z + ez] = vl[:ex, :, :ez]
            pintura.pintar(vl, b0x, b0z, 2, nvar, codigo, desp, VAR)
            s_lo += R._trocear(vl, tx, tz, B, CHUNKS_LO, alto, lo)
        print("  baldosas: fila %d/%d, %d chunks" % (tz + 1, ntz, len(lo)))
    if audita:
        auditar(lz, vol_total, id_de, vs)
        return
    base = os.path.join(MAPAS, NOMBRE)
    br = json_br()
    sal = br["hangar"]["salida"]
    spawns = [(sal[0], sal[1], sal[2], 0.0)]
    t_lo = G.escribir_vxmap(base + "_lo.vxmap", vs, CHUNKS_LO, entradas, spawns, lo)
    with open(base + ".botin.json", "w", encoding="utf-8") as f:
        json.dump({"puntos": botin(random.Random(SEMILLA + 1))}, f, separators=(",", ":"))
    with open(base + ".br.json", "w", encoding="utf-8") as f:
        json.dump(br, f, ensure_ascii=False, indent=1)
    luces_j = []
    for e in lz.luces:
        x, y, z, col, en, a = e[:6]
        luces_j.append({"pos": [round(x, 2), round(y, 2), round(z, 2)], "color": [round(c / 255.0, 4) for c in col],
                        "energy": round(float(en), 2), "range": round(float(a), 2)})
    with open(base + ".lights.json", "w", encoding="utf-8") as f:
        json.dump({"cell": 1.5, "lights": luces_j, "source": "tools/generar_mapa_cuarto.py"}, f, separators=(",", ":"))
    print("== escrito %s_lo.vxmap: %.2f MB, %d chunks, %d voxels" % (NOMBRE, t_lo / 1048576, len(lo), s_lo))
    print("== hecho en %.1f s" % (time.time() - t0))


import raster  # noqa: E402  (textura_variacion)

if __name__ == "__main__":
    main()
