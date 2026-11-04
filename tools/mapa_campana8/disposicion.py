r"""DISPOSICION del EPISODIO 8 de la campaña cooperativa: "EL VOLCAN" (campana_volcan).

El globo del episodio 7 se mete en una nube de ceniza y cae en una ISLA VOLCANICA en plena erupcion. De noche, con el
resplandor rojo de la lava. La estacion vulcanologica tiene un HIDROAVION en la bahia. Todo en metros, Y arriba,
origen en la esquina minima. X = este, Z = sur. Suelo a G; el mar a 2,0 alrededor; el volcan en el medio.

   z   0 +----------------------------------------------------------------+
         |  mar                                                            |
      10 |  NO: ESTACION     |  N: EL PUEBLO (6 la colada)  | VALLE DEL AZUFRE (5)|
         |  (refugio) · boca |      [dique de lava]         |  mascaras, filtros  |
      40 |  del TUNEL (7)    |                              |=== derrumbe =======|
      54 |   ||  tunel  ||   |          /\  EL VOLCAN  /\   | GEISERES (4) roca  |
      80 |   ||         ||   |         /  \  (crater) /  \  |                    |
      96 |  BAHIA (8)        |        /    \         /    \ | RIO DE LAVA (3)    |
         |  [hidroavion]     |                               |  torre de agua     |
     122 |===================|===============================|====================|
         |  el GLOBO (1)     |  VALLE DE CENIZA (2)          | LAS BOMBAS (1b)    |
     166 +----------------------------------------------------------------+
         x 0              58                              126               176

LOS NUEVE (todos nuevos; escenas: el globo que cae, la torre de agua en la lava, el geiser que lanza la roca, la
colada que arrasa el pueblo y la erupcion final con el hidroavion despegando):
   1 LA CAMARA TERMICA: en la cabaña de los vulcanologos; en la nube de ceniza no se ve nada sin ella.
   2 LA NUBE DE CENIZA: con la camara se ven las criaturas (calientes) y los mojones del camino.
   3 LAS BOMBAS VOLCANICAS: cruzar el llano con las bombas cayendo (la marca roja avisa un segundo antes).
   4 LA TORRE DE AGUA: sus cuatro patas a tiros; cae al rio de lava, la lava se enfria y se cruza por encima.
   5 LA ROCA Y EL GEISER: se empuja una roca (casilla a casilla) hasta la boca del geiser grande; el geiser la
     lanza contra el derrumbe que cierra el paso.
   6 LAS MASCARAS: el valle del azufre mata sin mascara; los filtros duran poco y hay cajas de repuesto.
   7 LA COLADA: el dique del lago de lava, a tiros: la lava baja por el pueblo, arrasa la horda y, fria, se cruza.
   8 EL TUNEL DE LAVA: la lava sube por el suelo del tunel a golpes; se espera en los salientes.
   9 EL HIDROAVION: soltar el freno del carro, calentar los motores (aguantad) y todos a bordo.
"""

CHUNKS = (55, 12, 55)
VOXEL = 0.1
ANCHO_X = CHUNKS[0] * 3.2       # 176 m
ANCHO_Z = CHUNKS[2] * 3.2       # 176 m
ALTO_MUNDO = CHUNKS[1] * 3.2    # 38,4 m
ROCA_Y = 0.4
PISO = 3.2
LOSA = 0.3
G = 3.0
SUELO_Y = G
MAR_Y = 2.0
MAPA = (0.0, 0.0, ANCHO_X, ANCHO_Z)
ISLA = (10.0, 10.0, 166.0, 166.0)
ACANTILADO_ALTO = 9.5

VOLCAN = (92.0, 88.0, 34.0, 33.0)               # centro x, z, radio de la base y cumbre (y)

# ======================================================================================================
# S: el globo, la cabaña, la nube de ceniza y las bombas
# ======================================================================================================
GLOBO_CAIDO = (30.0, 142.0)
SPAWN_JUGADOR = (36.0, G, 148.0)
CABANA = (44.0, 128.0, 54.0, 136.0)              # la cabaña de los vulcanologos (la camara termica, dentro)
CAMARA = (49.0, G, 132.0)
CENIZA = (58.0, 124.0, 126.0, 164.0)             # el valle de la nube de ceniza
MOJONES = [(64.0, 150.0), (72.0, 138.0), (82.0, 146.0), (92.0, 134.0), (102.0, 144.0), (112.0, 132.0), (120.0, 140.0)]
BOMBAS = (126.0, 112.0, 164.0, 164.0)            # el llano de las bombas
REFUGIO_BOMBAS = (150.0, 112.0, 160.0, 118.0)    # un abrigo de hormigon junto al rio (no es el refugio)

# ======================================================================================================
# E: el rio de lava y la torre de agua; los geiseres y la roca
# ======================================================================================================
RIO = (124.0, 100.0, 166.0, 108.0)               # el cauce (la lava a 1,6 bajo el borde)
RIO_LAVA_Y = G - 0.7                              # (a 1,6 bajo el borde no se veia desde la orilla)
TORRE_AGUA = (144.0, 114.5)                       # cae hacia el norte, sobre el rio
TORRE_AGUA_ALTO = 14.0
PUENTE_LAVA = (140.0, 99.0, 148.0, 109.0)        # la costra que queda (x0, z0, x1, z1)
GEISERES = (126.0, 44.0, 166.0, 98.0)
# la rejilla de la roca: casillas de 2 m, (0,0) en la esquina noroeste del campo
REJILLA = (132.0, 56.0)                           # origen (x, z) de la casilla (0,0)
CASILLA = 2.0
REJILLA_TAM = (14, 16)                            # columnas, filas
ROCA_INICIO = (9, 13)
GEISER_GRANDE = (4, 3)                            # la casilla de la boca
PIEDRAS = [(3, 8), (4, 8), (5, 8), (6, 8), (8, 5), (9, 5), (10, 5), (2, 3), (6, 3), (7, 10), (8, 10), (11, 11),
           (11, 12), (1, 6), (12, 7)]            # las casillas que no se pueden pisar con la roca
GEISERES_CHICOS = [(138.0, 90.0), (156.0, 84.0), (160.0, 64.0), (130.0, 72.0)]
DERRUMBE_N = (126.0, 40.0, 166.0, 44.0)           # lo que cierra el paso al norte (lo revienta la roca)
BRECHA_N = (136.0, 146.0)                          # x de lo que abre la roca en el derrumbe

# ======================================================================================================
# N: el valle del azufre y el pueblo con la colada
# ======================================================================================================
AZUFRE = (100.0, 12.0, 166.0, 40.0)
TAQUILLA_MASCARAS = (160.0, G, 37.5)
CAJAS_FILTRO = [(140.0, G, 24.0), (114.0, G, 30.0)]
PUEBLO = (40.0, 12.0, 100.0, 54.0)
LAGO_LAVA = (79.0, 52.0, 97.0, 62.0)             # en la ladera norte del volcan (mas alto que el pueblo)
LAGO_LAVA_Y = 8.0
DIQUE = (82.0, 50.0, 94.0, 53.0)                  # el dique de roca con las cargas (dianas del juego)
COLADA = [(88.0, 51.0), (88.0, 30.0), (88.0, 10.0)]   # por donde baja al mar (recto: la fila de casas es mas estrecha)
COLADA_ANCHO = 10.0
FILA_CASAS = (84.5, 91.5)                          # x de la fila de casas que cierra el pueblo
CALLE_PUEBLO = (40.0, 26.0, 100.0, 34.0)          # la calle mayor (este-oeste)

# ======================================================================================================
# NO y O: la estacion (refugio), el tunel de lava y la bahia con el hidroavion
# ======================================================================================================
ESTACION = (14.0, 14.0, 38.0, 36.0)               # el recinto de la estacion
REFUGIO = (16.0, 18.0, 30.0, 30.0)                # el edificio principal: entrada al norte, salida al sur
REFUGIO_PUERTA_N = (23.0, 18.0)
REFUGIO_PUERTA_S = (23.0, 30.0)
TUNEL = [(23.0, 38.0), (23.0, 58.0), (34.0, 58.0), (34.0, 80.0), (24.0, 80.0), (24.0, 100.0)]  # el eje del tubo (tramos rectos)
TUNEL_ANCHO = 4.0
TUNEL_SUELO = 1.2
TUNEL_ALTO = 3.4
MONTE_OESTE = (10.0, 36.0, 76.0, 100.0)           # el monte por donde va el tunel (llega hasta el volcan)
SALIENTES = [(19.5, 49.0), (29.0, 61.5), (37.5, 69.0), (29.0, 76.5), (27.5, 90.0)]   # alcobas en alto (no llega la lava)
SALIENTE_ALTO = 1.0
LAVA_TUNEL_ALTA = TUNEL_SUELO + 0.7
BAHIA = (10.0, 100.0, 50.0, 120.0)
BAHIA_AGUA = (0.0, 102.0, 34.0, 118.0)            # la ensenada (agua de verdad, al mar por el oeste)
MUELLE = (22.0, 104.0, 36.0, 108.0)
HIDROAVION = (16.0, MAR_Y, 110.0)                 # donde flota (mirando al oeste)
CARRO = (34.0, 110.0)                              # el carro con el freno (la rampa de botadura)

RUTA = [
    (36.0, G, 148.0, "globo"),
    (49.0, G, 131.0, "cabaña"),
    (64.0, G, 147.0, "ceniza"),
    (102.0, G, 141.0, "mitad de la ceniza"),
    (130.0, G, 136.0, "llano"),
    (152.0, G, 120.0, "abrigo"),
    (144.0, G, 111.0, "orilla del rio"),
    (144.0, G, 94.0, "otra orilla"),
    (148.0, G, 70.0, "geiseres"),
    (141.0, G, 38.0, "brecha"),
    (158.0, G, 34.0, "taquilla"),
    (126.0, G, 26.0, "azufre"),
    (104.0, G, 30.0, "fin del azufre"),
    (97.0, G, 30.0, "pueblo"),
    (70.0, G, 30.0, "calle mayor"),
    (44.0, G, 26.0, "salida del pueblo"),
    (23.0, G, 15.5, "puerta del refugio"),
    (23.0, G, 26.0, "refugio"),
    (23.0, G, 34.0, "patio de la estacion"),
    (23.0, TUNEL_SUELO, 46.0, "tunel"),
    (34.0, TUNEL_SUELO, 70.0, "mitad del tunel"),
    (24.0, TUNEL_SUELO, 92.0, "fin del tunel"),
    (40.0, G, 104.0, "bahia"),
    (28.0, G, 106.0, "muelle"),
]

ZONAS = [
    ("mapa", MAPA),
    ("isla", ISLA),
]


def dentro(x, z, rect, margen=0.0):
    return rect[0] - margen <= x <= rect[2] + margen and rect[1] - margen <= z <= rect[3] + margen


def zona_de(x, z):
    for nombre, rect in ZONAS[1:]:
        if dentro(x, z, rect):
            return nombre
    return "fuera"


def celda_centro(c, f):
    return (REJILLA[0] + (c + 0.5) * CASILLA, REJILLA[1] + (f + 0.5) * CASILLA)


PLAZA = ISLA
