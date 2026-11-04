"""DISPOSICION del mapa de DUELO A MUERTE "CAFETERIA URBANA" (cafeteria). Una sola fuente de verdad para el
generador (tools/generar_mapa_cafeteria.py) y sus piezas.

Todo en metros, Y hacia arriba, origen en la esquina minima. X = este, Z = sur (el norte arriba en la vista aerea).
TODAS LAS MEDIDAS VAN EN MULTIPLOS DE 0,2 m: el juego carga el mapa de 20 cm (_lo) tambien en PC, y una pieza que no
cae en la rejilla de 0,2 se redondea a un voxel de mas o de menos (un muro de capas perderia una capa).

   x 0   9.6        21.2          39.2 41.2     50.8    58.8                     81.6   89.6
 z 0 +--------------------------- FILA NORTE ------------[TORRE]-----------------+------+
     |                                                                           |      |
 8.8 |------------------------ CALLE MAYOR (bomberos, coches) ---------- base CT |  F   |
  18 |  F  | CALLE   | CAFETERIA  |esc| PASAJE  | CALLE  | MANZANA ESTE           |  I   |
     |  I  | PRINCI- | (2 plantas)|ale| (3 pl.) | ESTE   | (tres alas y el PATIO) |  L   |
  32 |  L  | PAL     +------------+---+---------+        |        +--------------+  A   |
     |  A  | (N-S)   |        PLAZA               |       |  ALA   |    PATIO     |      |
     |     |         |  sombrillas, fuente,       |       |  OESTE |   (arboles)  |  E   |
     |  O  |         |  arbol central, bancos     |       |        |              |  S   |
  56 |  E  |         +-----+--+------------------+        |        +--------------+  T   |
     |  S  |         | S-A |CJ| S-B (dos casas)  |        |  ALA SUR               |  E   |
  68 |  T  |---------+-----+--+------------------+--------+------------------------|      |
     |  E  | base T         CALLE SUR                                              |      |
75.2 |     +----------------------------- FILA SUR ---------------------------------+      |
83.2 +---------------------------------------------------------------------------------+
  (CJ = el CALLEJON de los grafitis: desde la calle sur se ve la cafeteria al fondo, al otro lado de la plaza)
"""
CHUNKS = (28, 8, 26)            # 10 cm: 896 x 256 x 832 voxels
VOXEL = 0.1
ANCHO_X = CHUNKS[0] * 3.2       # 89,6 m
ANCHO_Z = CHUNKS[2] * 3.2       # 83,2 m
ALTO_MUNDO = CHUNKS[1] * 3.2    # 25,6 m

# --- alturas ------------------------------------------------------------------------------------------
ROCA_Y = 0.4                    # roca indestructible (nadie cae fuera del mundo por un agujero)
G = 1.0                         # la calzada
A = 1.2                         # aceras, plaza, callejon (bordillo de 0,2)
P0 = 1.4                        # el suelo de las plantas bajas (un escalon sobre la acera)
PISO = 3.6                      # de suelo a suelo
MURO = 0.6                      # revoque exterior 0,2 + ladrillo 0,2 + revoque interior 0,2
SUELO_Y = G                     # (la validacion mide desde aqui)


def planta(n):
    """Cota del suelo terminado de la planta n (0 = baja)."""
    return round(P0 + n * PISO, 3)


# --- las calles (x0, z0, x1, z1): calzada a G, lo demas acera a A ---------------------------------------
INTERIOR = (9.6, 8.8, 81.6, 75.2)            # todo lo que queda dentro de las cuatro filas del borde
CALZADAS = [
    (11.2, 10.8, 80.0, 16.0, "calle mayor"),
    (11.2, 10.8, 16.8, 73.6, "calle principal"),
    (11.2, 69.6, 80.0, 73.6, "calle sur"),
    (52.4, 16.0, 57.2, 69.6, "calle este"),
]

# --- las manzanas ---------------------------------------------------------------------------------------
FILA_NORTE = (9.6, 0.0, 81.6, 8.8)
FILA_SUR = (9.6, 75.2, 81.6, 83.2)
FILA_OESTE = (0.0, 0.0, 9.6, 83.2)
FILA_ESTE = (81.6, 0.0, 89.6, 83.2)

CAFE = (21.2, 18.0, 39.2, 32.0)              # la cafeteria: dos plantas, esquina a la plaza y a la calle principal
CAFE_SALON_Z = 25.0                          # la planta alta cerrada va de z 18 a 25; la terraza, de 25 a 32
ESCALERA_EXT = (39.2, 18.0, 41.2, 32.0)      # el hueco entre la cafeteria y el pasaje: la escalera a la terraza
PASAJE = (41.2, 18.0, 50.8, 32.0)            # tres plantas con un pasaje cubierto en la planta baja
PASAJE_HUECO = (44.8, 48.4)                  # x del pasaje (3,6 m)
PLAZA = (21.2, 32.0, 50.8, 56.0)
SUR_A = (21.2, 56.0, 29.2, 68.0)
CALLEJON = (29.2, 56.0, 33.2, 68.0)
SUR_B = (33.2, 56.0, 50.8, 68.0)
TORRE = (44.0, 2.4, 50.4, 8.8)              # la torre del reloj, en la fila norte (a haces con las fachadas)

MANZANA_ESTE = (58.8, 18.0, 81.6, 68.0)
ALA_NORTE = (58.8, 18.0, 81.6, 30.0)
ALA_OESTE = (58.8, 30.0, 66.8, 54.0)
ALA_SUR = (58.8, 54.0, 81.6, 68.0)
PATIO = (66.8, 30.0, 81.6, 54.0)
ARCO_OESTE = (40.4, 44.0)                    # z del paso del ala oeste (calle este -> patio)
ARCO_SUR = (68.8, 72.4)                      # x del paso del ala sur (calle sur -> patio)

# --- el duelo a muerte ----------------------------------------------------------------------------------
BASE_CT = (72.0, G, 13.4)                    # extremo este de la calle mayor
BASE_T = (18.6, G, 71.6)                     # extremo oeste de la calle sur
OBJETIVO_BAJAS = 50

# puntos de salida repartidos por el mapa (se comprueban al generar: suelo, sin techo encima y alcanzables).
# El primero es el del jugador (VoxelWorld.load_map). Cada uno con el lado al que pertenece.
SALIDAS = [
    (18.6, G, 71.6, "t"), (14.0, G, 64.0, "t"), (31.2, A, 64.0, "t"), (44.0, G, 71.6, "t"), (25.4, A, 43.4, "t"),
    (14.0, G, 33.4, "t"), (62.0, G, 71.6, "t"), (37.0, A, 54.6, "t"),
    (72.0, G, 13.4, "ct"), (60.0, G, 13.4, "ct"), (46.6, A, 24.0, "ct"), (74.0, A, 32.2, "ct"), (55.0, G, 36.0, "ct"),
    (30.0, G, 13.4, "ct"), (68.0, A, 42.2, "ct"), (44.4, A, 34.8, "ct"),
]

ZONAS = [
    ("cafeteria", CAFE),
    ("pasaje", PASAJE),
    ("plaza", PLAZA),
    ("callejon", CALLEJON),
    ("patio", PATIO),
]


def dentro(x, z, rect, margen=0.0):
    return rect[0] - margen <= x <= rect[2] + margen and rect[1] - margen <= z <= rect[3] + margen


def zona_de(x, z):
    for nombre, rect in ZONAS:
        if dentro(x, z, rect):
            return nombre
    for c in CALZADAS:
        if dentro(x, z, c[:4]):
            return c[4]
    return "resto"
