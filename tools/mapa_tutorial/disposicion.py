"""DISPOSICION del mapa del TUTORIAL (tutorial). Una sola fuente de verdad para el generador
(tools/generar_mapa_tutorial.py), sus piezas y el .tutorial.json que lee scripts/tutorial.gd.

Un recinto pequeño de ladrillo en forma de U. Todo en metros, Y hacia arriba, X = este, Z = sur. Todas las medidas en
multiplos de 0,2 m (el juego carga el de 20 cm).

   x 0          12   12.6                       25.2 25.8                    37.8
 z 0 +-----------+------------------------------+------------------------------+
     | 1 PATIO   |W1| 2-3 SALA DEL ARMERO       |W2| 5 LA NAVE     [ALTILLO]   |
     | (salida)  |  | mesa con el subfusil ->   |  |   pilas+viga -> altillo   |
     |    O      |##| campo de tiro (3 dianas)  |  |                [PASARELA] |
 13  |           |  +------[puerta]------------+  |   6 cajas / mirador ->    |
     |           |  | 4 EL PORCHE                |  |   7 EL DEPOSITO (patas)   |
     |           |  |  losa sobre dos columnas  [puerta]                      |
28.8 +-----------+--+---------------------------+--+---------------------------+
  (## = el tapiado que se rompe con el mazo; O = donde se aparece)

El orden: moverse -> MAZO contra el tapiado -> coger el SUBFUSIL -> dianas -> las COLUMNAS del porche -> las PILAS de
la viga (cae y hace de rampa) -> subir al altillo -> TREPAR (cajas y mirador) -> GRANADAS a las patas del deposito.
"""
# SOLO EL PATIO (2026-10-20, pedido: "el mapa del tutorial recortado para que quede la parte 1"): 12,8 m de ancho; lo de
# mas alla (sala, porche, nave) queda fuera del mapa y no se escribe
CHUNKS = (4, 4, 9)              # 10 cm: 128 x 128 x 288 voxels
VOXEL = 0.1
ANCHO_X = CHUNKS[0] * 3.2       # 38,4 m
ANCHO_Z = CHUNKS[2] * 3.2       # 28,8 m
ALTO_MUNDO = CHUNKS[1] * 3.2    # 12,8 m

ROCA_Y = 0.4
G = 1.0                         # el suelo
MURO = 0.6                      # revoque 0,2 + ladrillo 0,2 + revoque 0,2 (lo usa piezas.py)
SUELO_Y = G
ALTO_TAPIA = 3.2                # los muros bajos del recinto
ALTO_NAVE = 6.4                 # los de la nave

# --- el recinto y sus zonas (x0, z0, x1, z1) ----------------------------------------------------------
RECINTO = (0.0, 0.0, 38.4, 28.8)
PATIO = (0.6, 0.6, 12.0, 28.2)                # 1: donde se empieza (y por donde no se sale)
SALA = (12.6, 0.6, 25.2, 13.0)                # 2-3: el armero y el campo de tiro
PORCHE = (12.6, 13.6, 25.2, 28.2)             # 4: el porche
NAVE = (25.8, 0.6, 37.8, 28.2)                # 5-7: la nave

# W1: el muro del patio a la sala, con el TAPIADO (una hoja de ladrillo viejo) en medio
W1 = (12.0, 0.6, 12.6, 13.0)
TAPIADO = (12.2, 5.8, 12.4, 8.2)              # x0, z0, x1, z1 (0,2 de grueso, hasta 2,6 de alto)
TAPIADO_ALTO = 2.6
# W3: de la sala al porche, con una puerta abierta
W3 = (12.0, 13.0, 25.8, 13.6)
PUERTA_W3 = (17.6, 19.6)                      # x
# W2: de la sala y el porche a la nave, con una puerta abierta en el porche
W2 = (25.2, 0.0, 25.8, 28.8)
PUERTA_W2 = (23.0, 25.0)                      # z
# el muro del patio con el porche (para que el patio no lleve al porche sin pasar por la sala)
W4 = (12.0, 13.6, 12.6, 28.8)

# --- 1 el patio ------------------------------------------------------------------------------------------
# EL TUTORIAL EN UN SOLO SITIO (2026-10-20, pedido: "que el escenario se reconstruya al siguiente sin que la persona se
# tenga que mover"): se empieza en el patio mirando al sur y cada reto se construye delante (scripts/tutorial.gd)
SPAWN = (6.3, G, 2.6, 180.0)                  # mirando al sur (+Z), a la zona de los retos
CIRCULO = (6.3, 5.2)                          # "camina hasta aqui": el PUESTO desde el que se hace todo
PUESTO = (6.3, G, 5.2)

# --- 2-3 la sala ---------------------------------------------------------------------------------------
MESA_ARMA = (15.6, 3.4)                       # el banco de trabajo con el subfusil encima
ARMA = (15.6, G + 1.08, 3.4)
LINEA_TIRO = 16.4                             # x de la linea pintada
DIANAS_X = (23.4, 23.6)                       # el grosor de las dianas (miran al oeste)
DIANAS = [(5.0,), (7.4,), (9.8,)]             # centro z de cada diana (1,0 de ancho, de 0,8 a 2,0 de alto)
DIANA_ANCHO = 1.0
DIANA_Y = (0.8, 2.0)
CHAPA = (11.6,)                               # la chapa de metal (z): aguanta mas

# --- 4 el porche ---------------------------------------------------------------------------------------
LOSA = (17.0, 19.8, 20.2, 22.2)               # x0, z0, x1, z1
LOSA_Y = (2.6, 3.0)                           # sobre el suelo
COLUMNAS = [(17.6, 21.0), (19.6, 21.0)]       # centro de cada columna (0,6 x 0,6)
COLUMNA_LADO = 0.6

# --- 5 la nave: el altillo y la viga -----------------------------------------------------------------
ALTILLO = (32.0, 0.6, 37.8, 12.0)
ALTILLO_Y = (2.2, 2.6)                        # losa de 0,4; arriba a 2,6 (no se trepa: mas de 2,45)
BISAGRA = (32.0, G + 2.6, 6.0)                # el borde del altillo donde gira la viga
VIGA_LARGO = 6.0
VIGA_ANCHO = 2.0
PILAS = [(27.6, 5.6, 28.4, 6.4), (30.0, 5.6, 30.8, 6.4)]   # x0, z0, x1, z1 (hasta la viga: 2,4)
PILA_ALTO = 2.4

# --- 6 trepar: la pasarela, las cajas y el mirador ---------------------------------------------------
PASARELA = (35.4, 12.0, 37.8, 17.0)           # a la altura del altillo, pegada al muro este
CAJAS = (35.4, 13.8, 37.8, 14.4)              # una fila de cajas de 1,4 m de alto en la pasarela
CAJAS_ALTO = 1.4
MIRADOR = (35.4, 17.0, 37.8, 20.6)            # torre de ladrillo desde el suelo; arriba a 4,6
MIRADOR_Y = 4.6

# --- 7 el deposito de agua ------------------------------------------------------------------------------
DEPOSITO_PATAS = [(28.0, 21.6), (30.4, 21.6), (28.0, 24.0), (30.4, 24.0)]   # centro de cada pata (0,4)
PATA_LADO = 0.4
PATA_ALTO = 3.0
DEPOSITO = (27.4, 21.0, 31.0, 24.6)           # el tanque: x0, z0, x1, z1
DEPOSITO_Y = (3.0, 5.4)
