"""DISPOSICION del EPISODIO 3 de la campaña cooperativa: "EL AMANECER" (campana_amanecer).

El barco del episodio 2 os deja al AMANECER en el muelle de un pueblo de pescadores que trepa por la ladera. La
radio de la ciudadela, en lo alto del cerro, puede llamar a un helicoptero. Hay que subir: cuatro terrazas y
un puzzle en cada salto de altura.
Todo en metros, Y hacia arriba, origen en la esquina minima. X = este, Z = sur (el mar, al sur).

   z   0 +--------------------------------------------------------------+
         |        MIRADOR (Y2)      |B| CALLE ALTA (Y2)   | A |CIUDADELA |
         |  casas   CHIMENEA -> ~~~ |A| [REFUGIO]  gener. | C | (Y3)     |
      30 |          ^ cuesta        |R|                   | A | radio    |
         |  casas   |   casas       |R|  casas     [MONTA-| N | helip.   |
      50 |--------PASAJE (persiana)-+-+-------------CARGAS]| T |==========|
         |                                                  | I |  casas   |
         |   IGLESIA   PLAZA DEL MERCADO (Y1)   casas       | L |          |
      96 |================= MALECON (4 m) ==[CONTENEDOR]=====+---+----------|
         |  MUELLE (Y0)            barco                                  |
     114 |~~~~~~~~~~~~~~~~~~~~~~~ MAR ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~|
     128 +--------------------------------------------------------------+

LOS PUZZLES (el juego los mueve; el mapa pone lo que se rompe y los apoyos):
  1. EL CONTENEDOR: esta en lo alto de un andamio de madera junto al malecon. Se revientan los puntales y cae
     al suelo pegado al muro: cajas -> contenedor -> malecon, trepando (2,2 m como mucho cada salto).
  2. LA PERSIANA del pasaje: cerrada. Uno trepa (contenedor de basura -> quiosco -> balcon) y tira de la
     palanca del balcon; la persiana sube para todos.
  3. LA CHIMENEA de la vieja conservera, al borde del barranco (una calle hundida). Se revienta su base de
     ladrillo y cae como un arbol, de lado a lado: se cruza andando por encima.
  4. EL MONTACARGAS del acantilado: sin corriente. Se arranca el generador (hace ruido: horda) y, cuando
     calienta, todos dentro y uno pulsa: sube 12 m.
  5. EL PUENTE LEVADIZO de la ciudadela: levantado. Se rompe a tiros la TRANCA que sujeta el contrapeso y el
     puente cae sobre el foso.
  Y el final: la RADIO de la ciudadela llama al helicoptero, se aguanta en la plaza de armas y se sube.
"""
CHUNKS = (50, 13, 40)
VOXEL = 0.1
ANCHO_X = CHUNKS[0] * 3.2       # 160 m
ANCHO_Z = CHUNKS[2] * 3.2       # 128 m
ALTO_MUNDO = CHUNKS[1] * 3.2    # 41,6 m
ROCA_Y = 0.4
PISO = 3.2
LOSA = 0.3

# las cuatro terrazas
Y0 = 1.0                        # el muelle
Y1 = 5.0                        # la plaza del mercado
Y2 = 11.0                       # el mirador y la calle alta
Y3 = 23.0                       # la ciudadela
SUELO_Y = Y0                    # (la validacion y las pistas miden desde aqui)

MAPA = (0.0, 0.0, ANCHO_X, ANCHO_Z)
CX = 80.0

# --- el mar y el muelle -----------------------------------------------------------------------------------
MAR_Z = 114.0
MAR_AGUA_Y = 0.55
MUELLE = (0.0, 98.0, 160.0, MAR_Z)
MALECON_Z = 98.0                # la cara del muro del malecon (arriba, la plaza)
PANTALAN = (18.0, 114.0, 30.0, 124.0)       # el embarcadero de madera donde atraca el barco
BARCO_PARA = (24.0, MAR_AGUA_Y, 127.0)
SPAWN_JUGADOR = (24.0, Y0, 108.0)

# 1. el contenedor: en su andamio (abajo del todo, a 3,6 m) y donde queda al caer (pegado al malecon)
CONT = (38.0, 98.3, 44.0, 100.7)            # x0, z0, x1, z1 (6 x 2,4 m)
CONT_ALTO = 2.6
CONT_ANDAMIO_Y = Y0 + 3.6                   # la base del contenedor sobre el andamio
PUNTALES = [(38.2, 98.5), (43.4, 98.5), (38.2, 100.1), (43.4, 100.1), (40.8, 98.5), (40.8, 100.1)]   # 0,4 x 0,4 m
CAJAS_SUBIR = (44.3, 98.6, 45.4, 100.2)     # las cajas para subir al contenedor (0,9 m)

# --- la plaza del mercado (Y1) ----------------------------------------------------------------------------
PLAZA_MERCADO = (16.0, 60.0, 104.0, MALECON_Z)
FUENTE = (60.0, 80.0)
IGLESIA = (2.0, 60.0, 16.0, 92.0)
ESCALINATA_MUELLE = (6.0, 96.0, 12.0, 98.0)  # la escalera del muelle, hundida (escombros: por ahi no)

# 2. la persiana del pasaje y el camino del que trepa
FILA_NORTE = (16.0, 50.0, 104.0, 60.0)      # la fila de casas que cierra la plaza por el norte
PASAJE = (50.0, 50.0, 54.0, 60.0)           # el tunel bajo las casas (4 m de ancho, 3,4 de alto)
PASAJE_ALTO = 3.4
PERSIANA = (50.0, 59.6, 54.0, 60.0)         # la pone el juego
BALCON = (56.4, 60.0, 61.4, 61.3)           # balcon de la casa de al lado (suelo a Y1 + 3,3)
BALCON_Y = Y1 + 3.3
PALANCA = (59.0, BALCON_Y, 60.2)            # la caja de la persiana, en la pared del balcon
QUIOSCO = (56.6, 61.5, 60.4, 64.1)          # techo a Y1 + 2,9: casi a ras del suelo del balcon (se pasa andando)
QUIOSCO_ALTO = 2.9
BALCON_HUECO = (57.0, 59.8)                 # por donde falta la barandilla (encima del quiosco)
CONTENEDOR_BASURA = (60.8, 62.0, 62.8, 63.5)  # 1,3 m

# --- la cuesta y el mirador (Y2) --------------------------------------------------------------------------
CUESTA = (48.0, 28.0, 56.0, 50.0)           # la calle de escaleras: de Y1 (z 50) a Y2 (z 30)
CUESTA_Z = (30.0, 50.0)
MIRADOR = (16.0, 4.0, 70.0, 28.0)           # la terraza de arriba a la izquierda
# 3. la chimenea y el barranco
BARRANCO = (70.0, 4.0, 79.0, 40.0)          # la calle hundida (fondo a Y1)
CHIMENEA_BASE = (66.2, 14.6, 68.6, 17.0)    # el pie de ladrillo que se revienta (Y2 .. Y2 + 2,2)
CHIMENEA_BASE_ALTO = 2.2
CHIMENEA_PIVOTE = (68.6, Y2, 15.8)          # por donde vuelca (el canto del pie hacia el barranco)
CHIMENEA_LARGO = 15.0                       # del pie a la boca: tumbada llega hasta x 83
CHIMENEA_R = 0.95

# --- la calle alta y el refugio (Y2) ----------------------------------------------------------------------
CALLE_ALTA = (79.0, 10.0, 122.0, 24.0)
REFUGIO = (92.0, 26.0, 104.0, 36.0)         # la panaderia (puertas en el norte y en el este)
REFUGIO_PUERTA_N = (98.0, 26.0)
REFUGIO_PUERTA_E = (104.0, 31.0)
PATIO_MONTACARGAS = (104.0, 24.0, 124.0, 46.0)
# 4. el generador y el montacargas
GENERADOR = (110.0, 38.0, 116.0, 44.0)      # la caseta del generador
GENERADOR_BOTON = (113.0, Y2, 37.4)
ACANTILADO_X = 124.0                        # la pared de roca: detras, la ciudadela (Y3)
POZO = (119.6, 28.0, 124.0, 34.0)           # el hueco del montacargas, contra la roca
CABINA = (120.0, 28.6, 123.6, 33.4)         # la cabina (la mueve el juego)
CABINA_BOTON = (120.3, Y2, 31.0)

# --- la ciudadela (Y3) ------------------------------------------------------------------------------------
LLEGADA = (124.0, 26.0, 134.0, 40.0)        # el rellano de arriba del acantilado
FOSO = (134.0, 4.0, 140.0, 64.0)            # 6 m de ancho, fondo a Y3 - 7
FOSO_FONDO_Y = Y3 - 7.0
# 5. el puente levadizo (bisagra en la puerta de la ciudadela) y su tranca
PUENTE = (133.0, 29.0, 139.0, 35.0)         # tumbado: de x 133 a 139 (6 m; apoya 1 m en la orilla), 6 de ancho
PUENTE_BISAGRA = (139.0, Y3, 32.0)          # en la cara del torreon
# la TRANCA: la viga de madera que asoma 2,4 m del torreon sobre el foso; de su punta cuelga el contrapeso
TRANCA = (136.8, Y3 + 6.2, 31.65, 139.2, Y3 + 6.9, 32.35)
CIUDADELA = (140.0, 4.0, 160.0, 64.0)
MURALLA_ALTO = 6.0
PLAZA_ARMAS = (143.0, 8.0, 157.0, 60.0)
RADIO = (150.0, Y3, 14.0)                   # la caseta de la radio (el boton)
HELIPUERTO = (150.0, Y3, 48.0)
ABORDAR = (150.0, Y3, 48.0)

RUTA = [
    (24.0, Y0, 108.0, "muelle"),
    (47.5, Y0, 102.0, "contenedor"),
    (41.0, Y1, 94.5, "malecon"),
    (60.0, Y1, 84.0, "plaza del mercado"),
    (52.0, Y1, 64.0, "pasaje"),
    (52.0, Y1, 54.0, "dentro del pasaje"),
    (52.0, 8.0, 40.0, "cuesta"),
    (52.0, Y2, 24.0, "mirador"),
    (64.0, Y2, 19.0, "chimenea"),
    (74.5, Y2, 15.8, "barranco"),
    (88.0, Y2, 17.0, "calle alta"),
    (98.0, Y2, 23.0, "entrada del refugio"),
    (98.0, Y2, 31.0, "refugio"),
    (110.0, Y2, 31.0, "patio del montacargas"),
    (113.0, Y2, 35.5, "generador"),
    (121.8, Y2, 31.0, "montacargas"),
    (128.0, Y3, 31.0, "arriba del acantilado"),
    (132.5, Y3, 32.0, "foso"),
    (137.0, Y3, 32.0, "puente levadizo"),
    (146.0, Y3, 32.0, "plaza de armas"),
    (150.0, Y3, 17.0, "radio"),
    (150.0, Y3, 46.0, "helipuerto"),
]

ZONAS = [
    ("mapa", MAPA),
    ("plaza", PLAZA_MERCADO),
    ("refugio", REFUGIO),
    ("ciudadela", CIUDADELA),
]


def dentro(x, z, rect, margen=0.0):
    return rect[0] - margen <= x <= rect[2] + margen and rect[1] - margen <= z <= rect[3] + margen


def zona_de(x, z):
    for nombre, rect in ZONAS[1:]:
        if dentro(x, z, rect):
            return nombre
    return "calles"


PLAZA = PLAZA_MERCADO[:4]      # la validacion lo usa como zona abierta de referencia
