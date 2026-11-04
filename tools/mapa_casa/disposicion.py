"""DISPOSICION del mapa CASA (casa, PROP HUNT). Una sola fuente de verdad para el generador
(tools/generar_mapa_casa.py) y el .prophunt.json que lee scripts/prop_hunt.gd.

Una casa de dos plantas con garaje y patio, en una parcela con tapia. Metros, Y arriba, X = este, Z = sur. Todo en
multiplos de 0,2 m (el juego carga el de 20 cm).

  x 0   2.4                10.2 10.6              17.8 18.4        23.6   25.6
 z 0 +------------------------- (calle / jardin delantero: salen los CAZADORES) ----------------+
 2.4 |   +-----------------------+-----------------------+---------------+                      |
     |   | LIVING                |A| HALL (escalera)     |   GARAJE      |                      |
     |   |   sofa, tele...       | |   [puerta calle]    |               |                      |
 8.2 |   +---- (arco abierto) ---+ +-------+-------------+---------------+ 9.4                  |
     |   | COMEDOR               | | COCINA  | LAVADERO  |                                      |
 13.8|   +-----------------------+-+---------+-----------+                                      |
 14.4|                    PATIO (cesped, arbol, parrilla)                                       |
 25.6+-------------------------------------------------------------------------------------------+
 Arriba (de 4,2 a 7,0): DORMITORIO (sobre el living), DORMITORIO 2 (sobre el comedor), PASILLO con la escalera
 (sobre el hall), ESTUDIO (sobre la cocina) y BAÑO (sobre el lavadero). Azotea con pretil.
"""
CHUNKS = (8, 4, 8)              # 10 cm: 256 x 128 x 256 voxels (el alto, multiplo de 2 chunks: el de 20 cm solo escribe chunks enteros)
VOXEL = 0.1
ANCHO_X = CHUNKS[0] * 3.2       # 25,6 m
ANCHO_Z = CHUNKS[2] * 3.2       # 25,6 m
ALTO_MUNDO = CHUNKS[1] * 3.2    # 12,8 m

ROCA_Y = 0.4
G = 1.0                         # el suelo de la calle y de la planta baja
MURO = 0.6                      # muro exterior: revoque 0,2 + ladrillo 0,2 + revoque 0,2 (lo usa piezas.py)
SUELO_Y = G
TABIQUE = 0.4                   # los tabiques de dentro

CASA = (2.4, 2.4, 18.4, 14.4)              # rectangulo exterior de la casa
DENTRO = (3.0, 3.0, 17.8, 13.8)            # su interior libre
PISO1 = G + 3.2                            # suelo de la planta alta (forjado de 0,4: techo de abajo a 2,8)
AZOTEA = G + 6.4                           # la cubierta (techo de arriba a 6,0)
GARAJE = (18.4, 2.4, 23.6, 9.4)            # exterior del garaje (una planta, azotea a G + 3,4)
GARAJE_ALTO = 3.4
PARCELA = (0.0, 0.0, 25.6, 25.6)
TAPIA_ALTO = 1.6

# tabiques (x0, z0, x1, z1)
T_A = (10.2, 3.0, 10.6, 13.8)              # oeste | este, en las dos plantas
T_B = (3.0, 8.2, 10.2, 8.6)                # living | comedor (abajo con ARCO), dormitorio | dormitorio 2 (arriba)
T_C = (10.6, 7.4, 17.8, 7.8)               # hall | cocina (abajo), pasillo | estudio y baño (arriba)
T_D = (15.0, 7.8, 15.4, 13.8)              # cocina | lavadero (abajo), estudio | baño (arriba)

ARCO_B = (5.0, 8.4)                        # x del arco abierto living-comedor (planta baja)

# LA ESCALERA (2026-10-21, pedido: "no puedo subir; ocupa mucho, que sea mas chica y fina, algo liso"): 1,2 de ancho,
# PELDAÑOS FINOS de 0,2 sin zancas ni macizo debajo, 16 de 0,2 en 4,4 m (sube hacia +X por el sur del hall, de 11,0 a
# 15,4). El HUECO del forjado va de donde la cabeza ya tocaria el techo (x 12,2) hasta arriba; rellano de 15,4 a 17,8
ESCALERA = (11.0, 6.2, 4.4, 1.2)           # x0, z0, largo, ancho (pegada al tabique del sur: los peldaños se apoyan en el)
HUECO_ESCALERA = (12.2, 6.0, 15.4, 7.4)    # el hueco en el forjado de arriba

# SALIDAS
SALIDA_ESCONDIDOS = (6.6, G, 5.6, 0.0)     # en el living
SALIDA_CAZADORES = (13.0, G, 1.2, 180.0)   # en la calle, frente a la puerta (mirando al sur, a la casa)
PUERTA_CALLE = (12.4, 14.8)                # x de la puerta en la fachada norte (al hall), 2,4 de ancho
