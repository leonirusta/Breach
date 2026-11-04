r"""DISPOSICION del EPISODIO 4 de la campaña cooperativa: "LA PRESA" (campana_presa).

Al helicoptero del episodio 3 se le acaba el combustible sobre las montañas y aterriza, AL ATARDECER, en la
cantera de un embalse. Abajo, en el valle, sale el ULTIMO TREN de evacuacion. Hay que BAJAR: por la coronacion
de la presa, por DENTRO de ella (la torre de toma, las galerias, la esclusa), por la central, por el canal de
desague, cruzar el rio en la barcaza, el pueblo, la serreria y la estacion. VEINTE PUZZLES, todos distintos.
Todo en metros, Y hacia arriba, origen en la esquina minima. X = este, Z = sur (el valle, al sur).

   z   0 +------------------------------------------------------------------+
         |MESETA  |              EMBALSE (agua a 31)                         |
         | heli   |                         [TORRE DE TOMA]                  |
      22 |CARRETERA  2                        | 4                           |
      40 |  1 ==== CORONACION (34) ==3 camion=====placa=====================|
         | colina  [7 valvulas] 6 vapor  [vig] 5 cuadro (galeria a 19)      |
      48 |         escalera \  8 ESCLUSA (6)                                 |
      64 |          bosque  [ CENTRAL: 9 tuberias · pozo · 10 grua ]  subest.|
      90 |                   11 canal de desague (bombona) --> 12 valla  13  |
     100 |~~~~~~~~~~~~~~~~~~~~~~~~~~~ RIO (corriente) ~~~~~~~~~~~ barcaza ~~~~|
     122 | ESTACION |muro| obra |caz| SERRERIA |barranco| mirador|PUEBLO [ref] |
         | 18 19 20 |17  |      |16 |          |   15 <-tirolina 14 porton     |
     160 +------------------------------------------------------------------+

LOS VEINTE (el juego mueve los objetos; el mapa pone lo que se rompe y los apoyos):
   1. LA VAGONETA: reventad el CALZO; la vagoneta de la cantera baja por la via y revienta la barricada.
   2. LAS DOS PALANCAS de la puerta de la coronacion: a la vez (5 s), una en cada garita.
   3. EL CAMION EN LLAMAS: la boca de incendios no tiene presion; primero la LLAVE de la caseta de bombeo.
   4. LA CUERDA Y LA PLACA (Portal): la puerta de la torre solo se abre con peso en la placa. Reventad el taco
      que ata la cuerda del pale de sacos: cae sobre la placa y la puerta se queda abierta.
   5. EL CUADRO DE LUCES de la galeria: cuatro interruptores que se encienden y apagan con los de al lado.
   6. EL PASILLO DE VAPOR: chorros que se abren y se cierran; se pasa entre ellos y se cierra la llave del final.
   7. LAS VALVULAS EN ORDEN: tres ruedas de colores; el orden esta en la pizarra de la sala del vigilante.
   8. LA ESCLUSA: dos compuertas que nunca se abren a la vez; todos dentro, se cierra una y se abre la otra.
   9. LAS TUBERIAS: nueve codos que se giran hasta que el agua llega; las bombas VACIAN EL POZO.
  10. EL PUENTE GRUA: saca el rodete que tapa la boca del canal de desague.
  11. LA BOMBONA: se lleva a cuestas hasta el derrumbe del canal, se enciende la mecha y se corre.
  12. LA VALLA ELECTRIFICADA: se revientan a tiros los tres AISLADORES del transformador.
  13. LA BARCAZA: una manivela en cada orilla; hay que quedarse girando mientras llega la horda.
  14. LA LLAVE del porton del pueblo: esta en una de cuatro casas (cada partida en una).
  15. LA TIROLINA del deposito de agua: se tensa el cable con el torno y se baja volando sobre el barranco.
  16. LAS PASARELAS HIDRAULICAS del caz: suben unos segundos; se cruza corriendo y se bloquean desde el otro lado.
  17. LA BOLA DE DEMOLICION: tres golpes de la grua abren el muro de la estacion.
  18. LA COMBINACION de la oficina del jefe de estacion: ANDEN, RELOJ y VAGON dicen las tres cifras.
  19. LAS AGUJAS Y EL VAGON: el vagon tapa la via; aguja a la via muerta, freno fuera, aguja a la via 1.
  20. EL GASOIL: seis bidones a cuestas hasta la locomotora con la horda encima. Y el tren se va por el tunel.
"""
CHUNKS = (55, 15, 50)
VOXEL = 0.1
ANCHO_X = CHUNKS[0] * 3.2       # 176 m
ANCHO_Z = CHUNKS[2] * 3.2       # 160 m
ALTO_MUNDO = CHUNKS[1] * 3.2    # 48 m
ROCA_Y = 0.4
PISO = 3.2
LOSA = 0.3

# --- las alturas -------------------------------------------------------------------------------------------
MESETA_Y = 38.0                 # la cantera donde aterriza el helicoptero
CORONA_Y = 34.0                 # la coronacion de la presa
EMBALSE_Y = 31.0                # el agua del embalse
EMBALSE_FONDO = 16.0
GALERIA_Y = 19.0                # las galerias de dentro de la presa
VALLE_Y = 6.0                   # el pie de la presa: la central
POZO_Y = 1.6                    # el fondo del pozo y el canal de desague
ORILLA_Y = 1.8                  # la playa de la orilla norte y el muelle sur
RIO_Y = 1.2                     # el agua del rio
SUR_Y = 4.0                     # serreria, obra y estacion
PUEBLO_Y = 8.0                  # el pueblo y el mirador
SUELO_Y = CORONA_Y              # (la validacion mide "a ras de suelo" desde aqui)

MAPA = (0.0, 0.0, ANCHO_X, ANCHO_Z)

# ======================================================================================================
# A. LA CANTERA Y LA CARRETERA
# ======================================================================================================
MESETA = (0.0, 0.0, 26.0, 22.0)
HELI = (13.0, MESETA_Y, 9.0)
SPAWN_JUGADOR = (13.0, MESETA_Y, 16.0)
CARRETERA = (10.0, 22.0, 26.0, 48.0)          # rampa de z 22 a 34 (de 38 a 34), llana hasta 48
RAMPA_Z = (22.0, 34.0)
# 1. la vagoneta: via por el centro de la carretera, hasta el embarcadero de la cantera (y al agua)
VIA_X = 16.0
VAGONETA_Z = 15.0                             # donde espera, calzada, en lo alto
CALZO = (15.45, MESETA_Y, 16.55, 16.55, MESETA_Y + 0.45, 16.95)   # el taco de madera delante de la rueda
BARRICADA = (10.0, 35.0, 26.0, 36.2)          # tablones y sacos de lado a lado (3,4 m)
BARRICADA_ALTO = 3.4
EMBARCADERO = (22.0, 37.2, 30.0, 39.6)        # pantalan de madera de la cantera: la vagoneta acaba en el agua
# 2. las dos palancas y la puerta
PUERTA_CORONA_X = 40.0
PALANCA_1 = (12.4, CORONA_Y, 46.6)            # garita del suroeste de la carretera
PALANCA_2 = (33.0, CORONA_Y, 47.0)            # en el pretil sur de la coronacion
GARITA_1 = (10.4, 44.4, 13.4, 47.6)
GARITA_2 = (31.6, 46.2, 34.4, 47.6)

# ======================================================================================================
# B. LA CORONACION
# ======================================================================================================
PRESA = (26.0, 40.0, 172.0, 64.0)             # el cuerpo de la presa (paramento aguas arriba en z 40)
CORONA = (26.0, 40.0, 172.0, 48.0)            # la carretera de arriba (8 m)
PIE_Z = 64.0                                  # el paramento de aguas abajo baja de (z 48, 34) a (z 64, 6)
EMBALSE = (26.0, 0.0, 176.0, 40.0)
# 3. el camion cisterna y el fuego
CAMION = (66.0, 41.0, 79.0, 44.8)
FUEGO = (63.5, 40.5, 81.0, 47.5)              # la barrera de fuego (el juego)
CASETA_BOMBAS = (45.0, 35.4, 52.0, 40.4)      # colgada sobre el embalse, puerta al sur
LLAVE_BOMBAS = (48.5, CORONA_Y, 36.4)
BOCA_INCENDIOS = (59.0, CORONA_Y, 47.1)
# 4. la torre de toma, la placa y la pluma
TORRE = (98.0, 22.0, 112.0, 36.0)
TORRE_INT = (98.6, 22.6, 111.4, 35.4)
PASARELA_TORRE = (100.0, 36.0, 112.0, 40.0)   # espigon de hormigon del fondo a la coronacion (el tunel va dentro)
PUERTA_TORRE = (104.0, 35.8, 106.0, 36.2)     # la puerta (el juego), en la cara sur
PLACA = (104.2, 43.2, 105.8, 44.8)
PLUMA_POSTE = (108.2, 46.9, 108.8, 47.5)      # la pluma, en el pretil sur
PLUMA_PUNTA = (105.0, 40.4, 44.0)
TACO = (108.8, 35.2, 47.0, 109.2, 35.6, 47.4) # el taco donde esta atada la cuerda (se revienta)
PALE_Y = 38.2                                 # la base del pale colgado

# ======================================================================================================
# C. DENTRO DE LA PRESA
# ======================================================================================================
TUNEL_TORRE = (109.4, 35.4, 111.4, 49.0)      # del rincon sureste del fondo de la torre (Y 19) a la galeria
GALERIA = (60.0, 49.0, 114.0, 52.0)           # a Y 19, 2,8 m de alto
GALERIA_ALTO = 2.8
# 5. la reja y el cuadro
REJA_X = 107.4
CUADRO = (110.4, GALERIA_Y, 51.8)             # en la pared sur del cruce
# 6. el vapor
CHORROS_X = [96.0, 92.0, 88.0, 84.0, 80.0]
LLAVE_VAPOR = (76.0, GALERIA_Y, 49.2)
# 7. la sala del vigilante (la pizarra) y la de las valvulas
SALA_VIGILANTE = (96.6, 44.6, 101.4, 49.0)
PIZARRA = (99.0, GALERIA_Y + 1.5, 44.7)
SALA_VALVULAS = (46.0, 42.0, 60.0, 52.0)      # a Y 19, 4,5 m de alto
VALVULAS_X = [49.5, 53.0, 56.5]               # en la pared norte (z 42)
COMPUERTA_VALVULAS = (59.8, 44.0, 60.2, 47.0) # a la escalera (el juego)
ESCALERA = (60.0, 44.0, 81.7, 47.0)           # de Y 19 (x 60) a Y 6 (x 81,7)
# 8. la esclusa
ESCLUSA = (82.0, 42.0, 90.0, 49.0)            # a Y 6, 3,5 m de alto
ESCLUSA_A = (82.0, 44.0, 82.0, 47.0)          # la de la escalera (oeste)
ESCLUSA_B = (84.7, 49.0, 87.3, 49.0)          # la de la central (sur)
PALANCA_ESCLUSA = (88.5, VALLE_Y, 42.3)
TUNEL_CENTRAL = (84.7, 49.0, 87.3, 64.6)

# ======================================================================================================
# D. LA CENTRAL
# ======================================================================================================
CENTRAL = (60.0, 62.0, 124.0, 90.0)
CENTRAL_INT = (60.6, 64.4, 123.4, 89.4)
CENTRAL_TECHO = 20.0
GRUPOS = [(72.0, 76.0), (86.0, 76.0)]         # los generadores que siguen en su sitio
POZO = (98.0, 70.0, 110.0, 82.0)              # el del grupo 3: inundado (el juego lo vacia)
POZO_AGUA = 5.4
ROTOR = (104.0, POZO_Y + 2.2, 81.3)           # el rodete, de pie contra la boca del desague
ROTOR_R = 2.2
DESCARGA = (116.0, VALLE_Y, 74.0)             # donde lo deja la grua
ENTREPLANTA = (62.0, 85.4, 96.0, 89.4)        # a Y 10,5
ENTREPLANTA_Y = 10.5
PANEL_TUBOS = (80.0, ENTREPLANTA_Y + 1.8, 89.3)   # el centro del panel (3 x 3 codos), en la pared sur
GRUA_Y = 17.0                                 # la viga del puente grua
MANDO_GRUA = (116.0, VALLE_Y, 88.6)

# ======================================================================================================
# E. EL CANAL DE DESAGUE
# ======================================================================================================
BOCA_DESAGUE = (102.7, 82.0, 105.3, 94.1)     # de la boca del pozo hacia el sur
DESAGUE_ESTE = (102.7, 91.5, 141.0, 94.1)     # y hacia el este bajo el patio (a 1,9 m de la playa)
DESAGUE_SALIDA = (138.4, 94.1, 141.0, 96.4)   # por el muro de contencion a la playa
DESAGUE_ALTO = 2.6
TALLER = (105.3, 84.0, 110.0, 88.0)           # el cuartucho de la bombona
BOMBONA = (108.4, POZO_Y, 86.0)
DERRUMBE = (124.0, 91.5, 127.6, 94.1)
MARCA_BOMBONA = (122.2, POZO_Y, 92.8)

# ======================================================================================================
# F. LA ORILLA NORTE Y EL RIO
# ======================================================================================================
PATIO = (60.0, 90.0, 176.0, 96.0)             # el patio de la central, a Y 6 (no se pisa)
SUBESTACION = (124.0, 64.0, 176.0, 96.0)
PLAYA = (60.0, 96.0, 176.0, 100.0)
RIO = (0.0, 100.0, 176.0, 122.0)
# 12. el transformador y la valla
TRAFO = (150.0, 89.6, 156.0, 94.4)            # a Y 6, 4 m de alto
AISLADORES = [(151.2, 93.6), (153.0, 93.6), (154.8, 93.6)]
AISLADOR_Y = (VALLE_Y + 4.0, VALLE_Y + 5.4)
AISLADOR_R = 0.24
VALLA_X = 147.0
# 13. la barcaza
BARCAZA_X = 162.0
BARCAZA_TAM = (6.0, 6.0)
BARCAZA_Z = (103.2, 118.8)                    # el centro, en la orilla norte y en el muelle sur
BARCAZA_Y = 1.6                               # la cubierta
MANIVELA_1 = (157.2, ORILLA_Y, 98.4)
MUELLE_SUR = (158.0, 122.0, 166.0, 126.0)     # a Y 1,8, con su cancela en el borde
ESCALERA_PUEBLO = (158.0, 126.0, 166.0, 137.0)

# ======================================================================================================
# G. EL PUEBLO, EL MIRADOR Y EL BARRANCO
# ======================================================================================================
PUEBLO = (108.0, 122.0, 176.0, 160.0)
REFUGIO = (156.0, 138.0, 170.0, 150.0)
REFUGIO_PUERTA_N = (162.0, 138.0)
REFUGIO_PUERTA_O = (156.0, 144.0)
CALLE = (108.0, 141.0, 156.0, 149.0)
# las casas de la llave (con puerta a la calle) y las cerradas
CASAS_LLAVE = [(110.0, 128.0, 120.0, 140.0, "+z"), (123.0, 128.0, 133.0, 140.0, "+z"),
               (110.0, 150.0, 120.0, 160.0, "-z"), (136.0, 150.0, 146.0, 160.0, "-z")]
CASAS_CERRADAS = [(136.0, 128.0, 146.0, 140.0), (147.0, 128.0, 155.0, 136.0), (123.0, 150.0, 133.0, 160.0),
                  (148.0, 151.0, 155.0, 160.0)]
MURO_PUEBLO_X = 108.0
PORTON_PUEBLO = (108.0, 143.0, 108.8, 147.0)
CANDADO = (109.1, PUEBLO_Y, 145.0)
MIRADOR = (100.0, 122.0, 108.0, 160.0)
DEPOSITO = (101.0, 150.0, 106.0, 155.0)       # el deposito de agua sobre patas
DEPOSITO_Y = 18.0                             # la plataforma de arriba
BARRANCO = (88.0, 122.0, 100.0, 160.0)
TIROLINA_ARRIBA = (100.9, DEPOSITO_Y, 152.5)
TIROLINA_ABAJO = (76.0, SUR_Y, 150.0)
TORNO = (107.2, DEPOSITO_Y, 150.2)

# ======================================================================================================
# H. LA SERRERIA, EL CAZ Y LA OBRA
# ======================================================================================================
SERRERIA = (61.0, 122.0, 88.0, 160.0)
CAZ = (52.0, 122.0, 61.0, 160.0)              # el canal del molino (agua a 1,4, orillas a 4)
CAZ_AGUA = 1.4
PASARELAS_Z = (139.0, 141.0)
PASARELAS_X = [53.41, 55.47, 57.53, 59.59]
PASARELA_LADO = 1.3
PALANCA_PASARELAS = (62.6, SUR_Y, 137.4)
BLOQUEO_PASARELAS = (50.8, SUR_Y, 142.6)
OBRA = (40.0, 122.0, 52.0, 160.0)
MURO_ESTACION = (38.0, 122.0, 40.0, 160.0)    # 2 m de sillares, 5 de alto
MURO_ALTO = 5.0
GRUA_BASE = (47.5, SUR_Y, 146.0)
BOLA_REPOSO = (42.6, SUR_Y + 2.2, 140.0)
PLUMA_GRUA = (42.6, SUR_Y + 13.0, 140.0)       # de donde cuelga la bola
BOQUETE = (39.0, SUR_Y + 1.8, 140.0)
CABINA_GRUA = (49.2, SUR_Y, 147.6)

# ======================================================================================================
# I. LA ESTACION
# ======================================================================================================
ESTACION = (0.0, 122.0, 38.0, 160.0)
VIA_Z = 142.0
TUNEL_TREN = (0.0, 138.0, 3.0, 146.0)         # la boca del tunel, en la ladera del oeste
EDIFICIO = (8.0, 124.0, 30.0, 132.0)
ANDEN = (6.0, 135.6, 34.0, 140.4)             # a 0,9 m
ANDEN_Y = SUR_Y + 0.9
OFICINA = (21.0, 124.4, 29.6, 131.6)
PUERTA_OFICINA = (23.6, 131.6, 25.4, 132.0)
DIALES = (26.4, SUR_Y, 132.2)
PISTA_ANDEN = (12.0, ANDEN_Y, 136.4)
PISTA_RELOJ = (18.0, SUR_Y + 5.6, 132.2)
AGUJA = (10.0, VIA_Z)
PALANCA_AGUJA = (9.4, SUR_Y, 139.4)
VAGON = (11.2, 18.6)                          # x de un extremo a otro, sobre la via 1
VAGON_FRENO = (19.0, SUR_Y, 144.2)
VIA_MUERTA = [(10.0, 142.0), (7.0, 143.2), (5.0, 146.0), (4.4, 150.0), (4.4, 155.4)]
LOCO = (20.0, 31.4)
COCHE = (31.8, 37.6)                          # la plataforma donde se sube todo el mundo
COCHE_Y = SUR_Y + 1.2
TAPON_GASOIL = (27.0, SUR_Y, 140.2)
ARRANQUE = (22.6, SUR_Y + 1.4, 142.0)
BIDONES = [(4.6, SUR_Y, 125.4), (33.4, SUR_Y, 125.2), (35.6, SUR_Y, 155.0), (20.0, SUR_Y, 155.2),
           (14.0, ANDEN_Y, 137.2), (46.0, SUR_Y, 128.0)]

RUTA = [
    (13.0, MESETA_Y, 14.0, "helicoptero"),
    (16.0, MESETA_Y, 20.0, "cantera"),
    (18.0, CORONA_Y, 33.0, "barricada"),
    (18.0, CORONA_Y, 41.0, "carretera"),
    (34.0, CORONA_Y, 44.0, "puerta de la presa"),
    (50.0, CORONA_Y, 44.0, "coronacion"),
    (60.0, CORONA_Y, 44.0, "camion"),
    (86.0, CORONA_Y, 44.0, "tras el camion"),
    (100.0, CORONA_Y, 44.0, "placa"),
    (105.0, CORONA_Y, 38.0, "torre de toma"),
    (110.4, GALERIA_Y, 42.0, "fondo de la torre"),
    (110.4, GALERIA_Y, 50.5, "galeria"),
    (104.0, GALERIA_Y, 50.5, "galeria oeste"),
    (88.0, GALERIA_Y, 50.5, "vapor"),
    (73.0, GALERIA_Y, 50.5, "llave del vapor"),
    (53.0, GALERIA_Y, 47.5, "sala de valvulas"),
    (70.0, 13.2, 45.5, "escalera"),
    (86.0, VALLE_Y, 45.5, "esclusa"),
    (86.0, VALLE_Y, 56.0, "tunel de la central"),
    (86.0, VALLE_Y, 68.0, "sala de turbinas"),
    (80.0, ENTREPLANTA_Y, 87.4, "entreplanta"),
    (104.0, VALLE_Y, 67.5, "pozo"),
    (104.0, POZO_Y, 78.0, "fondo del pozo"),
    (104.0, POZO_Y, 88.0, "canal de desague"),
    (119.0, POZO_Y, 92.8, "derrumbe"),
    (139.7, ORILLA_Y, 98.0, "salida del desague"),
    (145.0, ORILLA_Y, 98.0, "valla"),
    (156.0, ORILLA_Y, 98.0, "embarcadero"),
    (162.0, BARCAZA_Y, 111.0, "rio"),
    (162.0, ORILLA_Y, 124.0, "muelle sur"),
    (162.0, 5.0, 131.5, "escalera del pueblo"),
    (163.0, PUEBLO_Y, 144.0, "refugio"),
    (140.0, PUEBLO_Y, 145.0, "calle del pueblo"),
    (112.0, PUEBLO_Y, 145.0, "porton del pueblo"),
    (106.2, PUEBLO_Y, 140.0, "mirador"),
    (104.0, DEPOSITO_Y, 152.5, "deposito"),
    (76.0, SUR_Y, 150.0, "serreria"),
    (64.0, SUR_Y, 140.0, "caz"),
    (46.0, SUR_Y, 138.0, "obra"),
    (30.0, SUR_Y, 150.0, "playa de vias"),
    (24.6, SUR_Y, 133.8, "oficina"),
    (12.0, SUR_Y, 138.6, "aguja"),
    (26.0, ANDEN_Y, 139.0, "locomotora"),
    (34.6, COCHE_Y, 142.0, "tren"),
]

ZONAS = [
    ("mapa", MAPA),
    ("presa", CORONA),
    ("central", CENTRAL),
    ("pueblo", PUEBLO),
    ("estacion", ESTACION),
]


def dentro(x, z, rect, margen=0.0):
    return rect[0] - margen <= x <= rect[2] + margen and rect[1] - margen <= z <= rect[3] + margen


def zona_de(x, z):
    for nombre, rect in ZONAS[1:]:
        if dentro(x, z, rect):
            return nombre
    return "fuera"


PLAZA = CORONA                 # la validacion lo usa como zona abierta de referencia
