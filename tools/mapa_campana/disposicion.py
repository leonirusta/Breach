"""DISPOSICION del mapa de CAMPAÑA COOPERATIVA "campana_huida" (capitulo 1 + final, inspirado en la primera
campaña de Left 4 Dead: azotea de apartamentos -> calles -> refugio del metro -> calles -> hospital -> azotea
con el helicoptero). Una sola fuente de verdad para el generador (tools/generar_mapa_campana.py), la
construccion (campana.py), la validacion (tools/mapa_pve/validar.py) y el juego (<mapa>.campana.json).

Todo en metros, Y hacia arriba, origen en la esquina minima. X = este, Z = sur.

EL RECORRIDO ES UNA S (una "vibora"): tres calles paralelas unidas por las esquinas, y entre calle y calle
manzanas CERRADAS de edificios (no se puede atajar: es lineal, como en Left 4 Dead).

   z   0 +--------------------------------------------------------------+
         | APARTAMENTOS |  licoreria  farmacia  (fachadas)            |
         |  (salida en  |===callejon==+                                |
         |   la azotea) |             |                                |
      34 |              +---------  CALLE OLMO  ----------------> esq. |
      48 |   manzanas cerradas                         [REFUGIO metro] |
      70 | <--------------- CALLE SEGUNDA (portón: el evento) -------  |
      84 | esq.  manzanas cerradas                                     |
     112 | ---------------- AVENIDA DEL HOSPITAL ---------> plaza  [HOSPITAL]
     126 |   manzanas cerradas                                  (azotea: radio,
         |                                                       helipuerto)
     179 +--------------------------------------------------------------+
"""
CHUNKS = (56, 11, 56)
VOXEL = 0.1
ANCHO_X = CHUNKS[0] * 3.2       # 179,2 m
ANCHO_Z = CHUNKS[2] * 3.2       # 179,2 m
ALTO_MUNDO = CHUNKS[1] * 3.2    # 35,2 m
SUELO_Y = 1.0                   # 0,4 m de roca indestructible + 0,6 m de tierra
ROCA_Y = 0.4
PISO = 3.2                      # altura de cada planta
LOSA = 0.3                      # grosor del forjado

MAPA = (0.0, 0.0, ANCHO_X, ANCHO_Z)

# --- el edificio de apartamentos (la salida) -----------------------------------------------------------------
APART = (10.0, 9.6, 36.4, 30.0)          # x0, z0, x1, z1 de la fachada
APART_PISOS = 5                          # planta baja + 4: la azotea a 1 + 5 * 3,2 = 17 m
APART_TORRE = (29.6, 9.6, 36.4, 20.0)    # la caja de escalera (muros incluidos), esquina noreste
APART_SALIDA = (36.4, 24.0)              # la puerta de la planta baja al callejon (fachada este)

# --- calles (x0, z0, x1, z1, nombre): asfalto y paso libre ---------------------------------------------------
CALLEJON = [
    (36.4, 21.6, 60.0, 28.4, "callejon"),           # sale de la puerta de los apartamentos hacia el este...
    (53.2, 28.4, 60.0, 34.0, "callejon (quiebro)"),  # ...y tuerce al sur hasta la calle
]
CALLE_A = (44.0, 34.0, 172.0, 48.0, "calle Olmo")
REFUGIO = (150.4, 50.4, 168.0, 64.0)                 # la boca del metro: se entra por el norte, se sale por el sur
REFUGIO_PUERTA_N = (158.4, 50.4)                     # centro de la puerta roja de entrada (en su muro norte)
REFUGIO_PUERTA_S = (158.4, 64.0)                     # y la de salida (muro sur)
ESQUINA_1 = (150.4, 48.0, 172.0, 50.4, "acera del refugio")
CALLE_B = (16.0, 66.4, 172.0, 82.4, "calle Segunda")
PORTON = (62.0, 66.4, 63.2, 82.4)                    # el porton que corta la calle Segunda (lo pone el juego)
PORTON_BOTON = (68.0, 1.0, 67.2)                     # delante del cuadro de mando del porton (acera norte, lado este)
ESQUINA_2 = (8.8, 66.4, 24.0, 126.4, "esquina oeste")
CALLE_C = (8.8, 110.4, 104.0, 126.4, "avenida del hospital")
PLAZA = (90.4, 100.0, 116.0, 166.4)                  # plaza delante del hospital
HOSPITAL = (116.0, 104.0, 166.4, 160.0)
HOSPITAL_PISOS = 6                                   # azotea a 1 + 6 * 3,2 = 20,2 m
HOSPITAL_TORRE = (116.0, 124.0, 122.8, 134.4)        # la escalera, pegada a la fachada oeste
HOSPITAL_ENTRADA = (116.0, 138.4)                    # puertas de urgencias (fachada oeste)

CALLES = CALLEJON + [CALLE_A, ESQUINA_1, CALLE_B, ESQUINA_2, CALLE_C,
                     (PLAZA[0], PLAZA[1], PLAZA[2], PLAZA[3], "plaza del hospital")]

AZOTEA_APART_Y = SUELO_Y + APART_PISOS * PISO                 # 17,0
AZOTEA_HOSP_Y = SUELO_Y + HOSPITAL_PISOS * PISO               # 20,2
SPAWN_JUGADOR = (18.0, AZOTEA_APART_Y, 14.0)                  # azotea de los apartamentos, rincon noroeste

# EL RECORRIDO, en orden (lo usa el director del juego para saber cuanto habeis avanzado y donde sacar a los
# bichos: delante del grupo, nunca en lo ya limpio). (x, y, z, nombre)
RUTA = [
    (18.0, AZOTEA_APART_Y, 14.0, "azotea"),
    (33.0, AZOTEA_APART_Y, 19.0, "caseta de la escalera"),
    (33.0, SUELO_Y + 2 * PISO, 10.8, "escalera, segunda planta"),
    (22.0, SUELO_Y + PISO, 19.0, "pasillo de la primera planta"),
    (33.0, SUELO_Y, 25.0, "portal"),
    (46.0, SUELO_Y, 25.0, "callejon"),
    (56.6, SUELO_Y, 31.0, "quiebro del callejon"),
    (70.0, SUELO_Y, 41.0, "calle Olmo"),
    (96.0, SUELO_Y, 41.0, "coche con alarma"),
    (124.0, SUELO_Y, 41.0, "farmacia"),
    (158.4, SUELO_Y, 44.0, "entrada del refugio"),
    (158.4, SUELO_Y, 57.0, "refugio"),
    (158.4, SUELO_Y, 72.0, "calle Segunda"),
    (120.0, SUELO_Y, 74.4, "control militar"),
    (80.0, SUELO_Y, 74.4, "antes del porton"),
    (50.0, SUELO_Y, 74.4, "despues del porton"),
    (16.4, SUELO_Y, 80.0, "esquina oeste"),
    (16.4, SUELO_Y, 110.0, "bajando"),
    (40.0, SUELO_Y, 118.4, "avenida"),
    (80.0, SUELO_Y, 118.4, "avenida (final)"),
    (104.0, SUELO_Y, 138.4, "plaza del hospital"),
    (126.0, SUELO_Y, 138.4, "urgencias"),
    (119.4, AZOTEA_HOSP_Y, 125.2, "caseta de la azotea"),
    (140.0, AZOTEA_HOSP_Y, 132.0, "azotea del hospital"),
]
RADIO = (134.0, AZOTEA_HOSP_Y, 128.0)                          # la radio, en su caseta
HELIPUERTO = (152.0, AZOTEA_HOSP_Y + 0.6, 132.0)               # centro del helipuerto (elevado 0,6 m)

# Zonas: para los informes de la validacion (a que parte pertenece cada bolsa sin acceso)
ZONAS = [
    ("mapa", MAPA),
    ("apartamentos", APART),
    ("refugio", REFUGIO),
    ("hospital", HOSPITAL),
]


def dentro(x, z, rect, margen=0.0):
    return rect[0] - margen <= x <= rect[2] + margen and rect[1] - margen <= z <= rect[3] + margen


def en_calle(x, z, margen=0.0):
    return any(dentro(x, z, c[:4], margen) for c in CALLES)


def zona_de(x, z):
    for nombre, rect in ZONAS[1:]:
        if dentro(x, z, rect):
            return nombre
    if en_calle(x, z):
        return "calles"
    return "manzanas"
