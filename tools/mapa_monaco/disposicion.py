"""DISPOSICION del mapa "monaco": una sola fuente de verdad para el integrador
(tools/generar_mapa_monaco.py), su relleno y su validacion.

EL SITIO. La Roca de Monaco: un promontorio de caliza sobre el mar, con el casco viejo encima. La
catedral manda en el centro, las calles bajan en abanico hacia el mar por el sur y los jardines
cuelgan del acantilado por el norte. Todo en piedra clara, revoco pastel y teja.

LA REGLA QUE MANDA EN ESTE MAPA ES LA VERTICALIDAD. Se juega tanto por los tejados como por la calle,
asi que TODA azotea tiene que ser alcanzable a pie: cada edificio alto lleva su escalera, y las
manzanas se tocan por pasarelas o por tejados contiguos a menos de 1,2 m de desnivel.

Todo en metros, Y hacia arriba, origen en la esquina minima del mapa. Las medidas van en multiplos de
0,8 m: es la celda del A* de voxels del motor (vx_nav.cpp, a 10 y a 20 cm).
"""
CHUNKS = (62, 14, 51)           # 198,4 x 44,8 x 163,2 m (mas alto que cuarentena: aqui hay torres)
VOXEL = 0.1
ANCHO_X = CHUNKS[0] * 3.2       # 198,4 m
ANCHO_Z = CHUNKS[2] * 3.2       # 163,2 m
ALTO_MUNDO = CHUNKS[1] * 3.2    # 44,8 m
ROCA_Y = 0.4                    # base indestructible: nadie se cae del mundo
MAR_Y = 1.6                     # lamina de agua alrededor de la Roca
SUELO_Y = 6.4                   # la explanada de arriba de la Roca (el casco viejo vive aqui)
BANDA = 10.0                    # borde: acantilado y mar (zona_perimetro dibuja ahi)
LIBRE_BANDA = 12.0              # el relleno del integrador no entra a menos de esto del borde

MAPA = (0.0, 0.0, ANCHO_X, ANCHO_Z)

# --- las cinco zonas ---------------------------------------------------------------------------------
# La catedral en el centro; el casco viejo al oeste; las torres al este; el puerto al sur (cota baja) y
# los jardines colgados al norte.
CATEDRAL = (76.8, 60.8, 121.6, 102.4)
CASCO = (16.0, 46.4, 72.0, 116.8)
TORRES = (126.4, 46.4, 182.4, 116.8)
PUERTO = (16.0, 121.6, 182.4, 156.8)
JARDINES = (16.0, 12.8, 182.4, 41.6)

ZONAS = [
    ("zona_perimetro", MAPA),
    ("zona_catedral", CATEDRAL),
    ("zona_casco", CASCO),
    ("zona_torres", TORRES),
    ("zona_puerto", PUERTO),
    ("zona_jardines", JARDINES),
]

SPAWN_JUGADOR = (99.2, SUELO_Y, 118.4)     # al sur de la catedral, mirando al campanario (-Z)

# Calles: paso libre garantizado (ni el relleno ni las zonas ponen nada que corte).
# La avenida central baja de los jardines al puerto pasando por delante de la catedral.
CALLES = [
    (95.2, 41.6, 103.2, 60.8, "avenida de los jardines"),
    (95.2, 102.4, 103.2, 121.6, "bajada al puerto"),
    (16.0, 41.6, 182.4, 46.4, "ronda norte"),
    (16.0, 116.8, 182.4, 121.6, "ronda sur"),
    (72.0, 46.4, 76.8, 116.8, "calle del casco"),
    (121.6, 46.4, 126.4, 116.8, "calle de las torres"),
    (11.2, 41.6, 16.0, 121.6, "ronda oeste"),
    (182.4, 41.6, 187.2, 121.6, "ronda este"),
]

# Manzanas de relleno del integrador (lo que no es zona ni calle)
MANZANAS = {
    "mirador_oeste": (16.0, 12.8, 92.8, 41.6),
    "mirador_este": (105.6, 12.8, 182.4, 41.6),
}
# Franjas estrechas: atrezo pegado al bordillo, nunca en medio del paso
FRANJAS = [
    (16.0, 121.6, 182.4, 124.8),
    (16.0, 38.4, 182.4, 41.6),
]

# --- COTAS. La Roca sube desde el mar hasta la explanada del casco. ----------------------------------
# El integrador esculpe el promontorio con estos escalones; las zonas construyen sobre `suelo_y`.
COTA_PUERTO = 2.4               # el muelle, a ras de mar
COTA_LADERA = 4.0               # la rampa que sube del puerto al casco
COTA_CASCO = SUELO_Y            # 6,4 m: la explanada de arriba
COTA_JARDINES = 5.6             # los jardines, un peldano por debajo del casco


def dentro(x, z, rect, margen=0.0):
    return rect[0] - margen <= x <= rect[2] + margen and rect[1] - margen <= z <= rect[3] + margen


def en_calle(x, z, margen=0.0):
    return any(dentro(x, z, c[:4], margen) for c in CALLES)


def zona_de(x, z):
    """Nombre de la zona que manda en ese punto (para los informes de validacion)."""
    for nombre, rect in ZONAS[1:]:
        if dentro(x, z, rect):
            return nombre
    if x < LIBRE_BANDA or z < LIBRE_BANDA or x > ANCHO_X - LIBRE_BANDA or z > ANCHO_Z - LIBRE_BANDA:
        return "zona_perimetro"
    return "integrador"


def suelo_de(z):
    """Cota del terreno segun lo cerca que este del mar (el mapa baja hacia el sur)."""
    if z >= PUERTO[1]:
        return COTA_PUERTO
    if z >= CATEDRAL[3]:
        return COTA_LADERA
    if z <= JARDINES[3]:
        return COTA_JARDINES
    return COTA_CASCO
