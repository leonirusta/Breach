"""DISPOSICION del mapa PvE "pve_cuarentena": una sola fuente de verdad para el integrador
(tools/generar_mapa_pve.py), su relleno y su validacion.

Todo en metros, Y hacia arriba, origen en la esquina minima del mapa. Las medidas van en multiplos de 0,8 m:
es la celda del A* de voxels del motor (vx_nav.cpp, a 10 y a 20 cm) y asi las calles y los huecos que
dejamos contienen celdas enteras.
"""
CHUNKS = (62, 11, 51)           # igual que hangar.vxmap
VOXEL = 0.1
ANCHO_X = CHUNKS[0] * 3.2       # 198,4 m
ANCHO_Z = CHUNKS[2] * 3.2       # 163,2 m
ALTO_MUNDO = CHUNKS[1] * 3.2    # 35,2 m
SUELO_Y = 1.0                   # suelo general (0,4 m de roca indestructible + 0,6 m de tierra)
ROCA_Y = 0.4
BANDA = 8.0                     # banda del perimetro (zona_perimetro dibuja ahi)
LIBRE_BANDA = 9.6               # el relleno del integrador no entra a menos de esto del borde

MAPA = (0.0, 0.0, ANCHO_X, ANCHO_Z)
PLAZA = (75.2, 57.6, 123.2, 105.6)
CUARTELES = (22.4, 64.0, 62.4, 100.0)
HOSPITAL = (136.0, 64.0, 176.0, 100.0)

# Orden de construccion: primero el perimetro (mapa entero), luego las zonas interiores.
ZONAS = [
    ("zona_perimetro", MAPA),
    ("zona_plaza", PLAZA),
    ("zona_cuarteles", CUARTELES),
    ("zona_hospital", HOSPITAL),
]

SPAWN_JUGADOR = (147.8, SUELO_Y, 59.2)     # lo eligio el usuario: junto al hospital, mirando al norte (-Z)
PUERTAS = {"norte": (99.2, 4.0), "sur": (99.2, 159.2), "oeste": (4.0, 81.6), "este": (194.4, 81.6)}

# Calles (x0, z0, x1, z1, nombre): asfalto y paso libre garantizado (el relleno no pone nada que corte)
CALLES = [
    (95.2, 0.0, 103.2, 57.6, "avenida norte"),
    (95.2, 105.6, 103.2, 163.2, "avenida sur"),
    (9.6, 49.6, 188.8, 57.6, "calle norte"),
    (9.6, 105.6, 188.8, 113.6, "calle sur"),
    (12.8, 49.6, 19.2, 113.6, "ronda oeste"),
    (65.6, 49.6, 72.0, 113.6, "calle de los cuarteles"),
    (126.4, 49.6, 132.8, 113.6, "calle del hospital"),
    (179.2, 49.6, 185.6, 113.6, "ronda este"),
    (0.0, 78.4, 12.8, 84.8, "entrada oeste"),
    (185.6, 78.4, 198.4, 84.8, "entrada este"),
]

# Manzanas de relleno del integrador (sin calles ni zonas)
MANZANAS = {
    "parque_motor": (10.4, 10.4, 94.4, 48.8),
    "helipuerto": (104.0, 10.4, 188.0, 48.8),
    "control": (10.4, 114.4, 94.4, 152.8),
    "evacuacion": (104.0, 114.4, 188.0, 152.8),
}
# Aceras y franjas estrechas entre calles y zonas: atrezo pegado al bordillo, nunca en medio del paso
FRANJAS = [
    (19.2, 57.6, 65.6, 64.0), (19.2, 100.0, 65.6, 105.6),
    (132.8, 57.6, 179.2, 64.0), (132.8, 100.0, 179.2, 105.6),
    (72.0, 57.6, 75.2, 105.6), (123.2, 57.6, 126.4, 105.6),
    (62.4, 64.0, 65.6, 100.0), (132.8, 64.0, 136.0, 100.0),
    (19.2, 64.0, 22.4, 100.0), (176.0, 64.0, 179.2, 100.0),
]


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
