"""RESPALDOS de zona del mapa PvE: contenido provisional cuando un modulo zona_*.py todavia no existe o falla.
Asi el mapa se genera siempre y se puede jugar mientras las zonas se construyen. Sencillo pero transitable:
puertas de 2,4 m alineadas a la rejilla de 0,8 m del A*, tejados a dos aguas con alero de 2,8 m y la plaza
despejada para el Goliat.
"""
import math
import objetos as O


def _al08(v):
    return math.floor(v / 0.8 + 0.5) * 0.8


def _tejado_dos_aguas(l, x0, z0, x1, z1, y0, alero, cumbre, mat, mat_hastial):
    """Tejado escalonado a lo largo de X: tiras de 0,1 m de ancho y 0,2 m de alto que se solapan en altura."""
    n = max(1, int(round((z1 - z0) / 2 / 0.1)))
    for i in range(n):
        h = y0 + alero + (cumbre - alero) * i / n
        for b0, b1 in ((z0 + i * 0.1, z0 + (i + 1) * 0.1), (z1 - (i + 1) * 0.1, z1 - i * 0.1)):
            l.caja(x0 - 0.3, h, b0, x1 + 0.3, h + 0.2, b1, mat)
            l.caja(x0, y0 + alero, b0, x0 + 0.3, h + 0.2, b1, mat_hastial)
            l.caja(x1 - 0.3, y0 + alero, b0, x1, h + 0.2, b1, mat_hastial)


def _barracon(l, x0, z0, x1, z1, y0, rng):
    alero, cumbre = 2.8, 4.0
    l.caja(x0, y0, z0, x1, y0 + alero, z1, "hormigon_sucio")
    l.caja(x0 + 0.3, y0, z0 + 0.3, x1 - 0.3, y0 + alero + 0.1, z1 - 0.3, "hormigon_sucio", hueco=True)
    l.caja(x0 + 0.3, y0 - 0.1, z0 + 0.3, x1 - 0.3, y0, z1 - 0.3, "hormigon_manchado")
    za = _al08((z0 + z1) / 2 - 1.2)
    l.caja(x0 - 0.1, y0, za, x0 + 0.4, y0 + 2.6, za + 2.4, "hormigon", hueco=True)
    l.caja(x1 - 0.4, y0, za, x1 + 0.1, y0 + 2.6, za + 2.4, "hormigon", hueco=True)
    u = x0 + 2.0
    while u < x1 - 2.5:
        for zz in (z0 - 0.1, z1 - 0.4):
            l.caja(u, y0 + 1.2, zz, u + 1.2, y0 + 2.1, zz + 0.5, "hormigon", hueco=True)
            if rng.random() < 0.45:
                for k in range(3):
                    l.caja(u - 0.1, y0 + 1.3 + k * 0.3, zz + (0.4 if zz > z0 else 0.0), u + 1.3, y0 + 1.45 + k * 0.3, zz + (0.5 if zz > z0 else 0.1), "madera_podrida")
        u += 3.2
    _tejado_dos_aguas(l, x0, z0, x1, z1, y0, alero, cumbre, "chapa_verde", "hormigon_sucio")
    u = x0 + 1.0
    while u < x1 - 3.0:
        for zz in (z0 + 0.4, z1 - 1.3):
            l.caja(u, y0, zz, u + 2.0, y0 + 0.5, zz + 0.9, "metal")
            if rng.random() < 0.5:
                O.cadaver(l, u + 1.0, zz + 0.45, y0 + 0.5, rng, "x")
        u += 3.2
    for _ in range(4):
        l.charco_sangre(rng.uniform(x0 + 1, x1 - 1), (z0 + z1) / 2 + rng.uniform(-1, 1), y0, rng.uniform(0.4, 1.0), rng)


def _puesto_mando(l, x0, z0, x1, z1, y0, rng):
    alto = 2.8                                   # tejado plano a 2,8 m: una criatura que salga arriba baja de un salto
    l.caja(x0, y0, z0, x1, y0 + alto, z1, "hormigon")
    l.caja(x0 + 0.4, y0, z0 + 0.4, x1 - 0.4, y0 + alto - 0.2, z1 - 0.4, "hormigon", hueco=True)
    xa = _al08((x0 + x1) / 2 - 0.8)
    l.caja(xa, y0, z1 - 0.5, xa + 1.6, y0 + 2.6, z1 + 0.1, "hormigon", hueco=True)
    for k in range(3):
        u = x0 + 1.5 + k * ((x1 - x0 - 3.0) / 2)
        l.caja(u, y0 + 1.6, z0 - 0.1, u + 1.2, y0 + 1.9, z0 + 0.5, "hormigon", hueco=True)
    l.caja(x0 + 1.0, y0, z0 + 0.6, x1 - 1.0, y0 + 0.8, z0 + 1.4, "madera_podrida")
    l.caja(x0 + 1.5, y0 + 0.8, z0 + 0.7, x0 + 2.3, y0 + 1.2, z0 + 1.2, "metal_negro")
    l.caja(x0 + 1.7, y0 + 0.95, z0 + 1.2, x0 + 2.1, y0 + 1.05, z0 + 1.21, "luz_verde")
    l.luz(x0 + 1.9, y0 + 1.4, z0 + 1.8, (80, 255, 90), 0.5, 4.0)
    l.linea(x1 - 1.0, y0 + alto, z0 + 1.0, x1 - 1.0, y0 + alto + 8.0, z0 + 1.0, 0.08, "metal")
    O.sacos(l, x0 - 0.8, z1 + 1.2, xa - 0.4, z1 + 1.2, y0, 1.0, rng)
    O.sacos(l, xa + 2.0, z1 + 1.2, x1 + 0.8, z1 + 1.2, y0, 1.0, rng)


def cuarteles(l, rect, y0, rng):
    x0, z0, x1, z1 = rect
    _barracon(l, x0 + 1.6, z0 + 2.4, x1 - 1.6, z0 + 10.4, y0, rng)
    _barracon(l, x0 + 1.6, z1 - 10.4, x1 - 1.6, z1 - 2.4, y0, rng)
    _puesto_mando(l, x0 + 11.2, z0 + 14.4, x1 - 11.2, z1 - 14.4, y0, rng)
    for _ in range(10):
        O.barril(l, rng.uniform(x0 + 2, x0 + 9), rng.uniform(z0 + 13, z1 - 13), y0, "chapa_verde", rng.choice((None, "x", "z")), rng)
    O.rastro_sangre(l, [(x1 - 1, (z0 + z1) / 2), ((x0 + x1) / 2 + 4, (z0 + z1) / 2 + 3), ((x0 + x1) / 2, z1 - 11)], y0, rng)


def hospital(l, rect, y0, rng):
    x0, z0, x1, z1 = rect
    for k in range(3):
        tx0 = x0 + 2.4 + k * 12.8
        O.tienda(l, tx0, z0 + 3.2, tx0 + 9.6, z0 + 10.4, y0, "tela_blanca", cruz=True)
        for c in range(3):
            cx = tx0 + 1.6 + c * 2.8
            l.caja(cx, y0, z0 + 4.0, cx + 0.9, y0 + 0.5, z0 + 6.0, "metal")
            O.bolsa_cadaver(l, cx + 0.45, z0 + 5.0, y0 + 0.5, "z", rng)
    O.contenedor(l, x0 + 4.0, z1 - 6.4, y0, "x", "tela_blanca", rng, abierto=True)
    O.contenedor(l, x0 + 22.4, z1 - 6.4, y0, "x", "metal", rng)
    O.cinta(l, [(x0 + 1.0, z0 + 14.0), (x0 + 12.0, z0 + 14.4), (x0 + 24.0, z0 + 14.0)], y0, rng)
    for _ in range(12):
        O.bolsa_cadaver(l, rng.uniform(x0 + 28, x1 - 3), rng.uniform(z0 + 15, z0 + 24), y0, rng.choice(("x", "z")), rng)
    for _ in range(8):
        O.barril(l, rng.uniform(x0 + 2, x1 - 2), rng.uniform(z0 + 26, z0 + 28), y0, "plastico_amarillo", None, rng)
    O.torre_focos(l, x1 - 3.0, z1 - 3.0, y0, rng, encendida=True)


def plaza(l, rect, y0, rng):
    x0, z0, x1, z1 = rect
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    l.caja(x0 + 1.6, y0 - 0.2, z0 + 1.6, x1 - 1.6, y0, z1 - 1.6, "hormigon_sucio")
    for _ in range(50):
        px, pz = rng.uniform(x0 + 2, x1 - 2), rng.uniform(z0 + 2, z1 - 2)
        for _k in range(3):
            a = rng.random() * math.tau
            qx = min(max(px + math.cos(a) * rng.uniform(0.6, 2.4), x0 + 2), x1 - 2)
            qz = min(max(pz + math.sin(a) * rng.uniform(0.6, 2.4), z0 + 2), z1 - 2)
            l.linea(px, y0 - 0.05, pz, qx, y0 - 0.05, qz, 0.05, "tierra")
            px, pz = qx, qz
    for _ in range(16):
        l.charco_sangre(rng.uniform(x0 + 3, x1 - 3), rng.uniform(z0 + 3, z1 - 3), y0, rng.uniform(0.6, 2.2), rng)
    for _ in range(5):
        l.elipsoide(rng.uniform(x0 + 6, x1 - 6), y0 - 0.05, rng.uniform(z0 + 6, z1 - 6), rng.uniform(2, 4), 0.06, rng.uniform(1.5, 3), "ceniza")
    l.caja(cx - 0.4, y0, cz - 0.4, cx + 0.4, y0 + 0.5, cz + 0.4, "hormigon")
    l.linea(cx + 0.3, y0 + 0.1, cz, cx + 11.0, y0 + 0.1, cz + 3.0, 0.2, "metal")
    l.caja(cx + 8.5, y0, cz + 2.0, cx + 10.5, y0 + 0.05, cz + 3.4, "plastico_rojo")
    for sx, sz in ((x0 + 5, z0 + 5), (x1 - 5, z0 + 5), (x0 + 5, z1 - 5), (x1 - 5, z1 - 5)):
        O.parapeto_circular(l, sx, sz, y0, 2.2, rng, abertura=math.atan2(cz - sz, cx - sx))
    for _ in range(10):
        O.cadaver(l, rng.uniform(x0 + 6, x1 - 6), rng.uniform(z0 + 6, z1 - 6), y0, rng)
    l.punto(cx, y0, cz, "jefe")


def perimetro(l, rect, y0, rng):
    """Muro de hormigon de 3,6 m a 6 m del borde, con un porton de 8 m en el centro de cada lado."""
    x0, z0, x1, z1 = rect
    d, g, alto = 5.6, 0.4, 3.6
    xm, zm = (x0 + x1) / 2, (z0 + z1) / 2
    tramos = [
        (x0 + d, z0 + d, xm - 4.0, z0 + d + g), (xm + 4.0, z0 + d, x1 - d, z0 + d + g),
        (x0 + d, z1 - d - g, xm - 4.0, z1 - d), (xm + 4.0, z1 - d - g, x1 - d, z1 - d),
        (x0 + d, z0 + d, x0 + d + g, zm - 4.0), (x0 + d, zm + 4.0, x0 + d + g, z1 - d),
        (x1 - d - g, z0 + d, x1 - d, zm - 4.0), (x1 - d - g, zm + 4.0, x1 - d, z1 - d),
    ]
    for a, b, c, e in tramos:
        l.caja(a, y0, b, c, y0 + alto, e, "hormigon_sucio")
        largo_x = (c - a) > (e - b)
        n = int(max(c - a, e - b) / 3.2)
        for k in range(n):
            if rng.random() < 0.35:
                if largo_x:
                    u = a + k * 3.2
                    l.caja(u, y0 + 0.4, b - 0.05, u + 3.1, y0 + alto - 0.3, e + 0.05, "hormigon_manchado")
                else:
                    u = b + k * 3.2
                    l.caja(a - 0.05, y0 + 0.4, u, c + 0.05, y0 + alto - 0.3, u + 3.1, "hormigon_manchado")
    for px, pz in ((xm, z0 + d), (xm, z1 - d), (x0 + d, zm), (x1 - d, zm)):
        l.punto(px, y0, pz + (3.0 if pz < zm else -3.0) if px == xm else pz, "criatura")
    for cx, cz in ((x0 + 12, z0 + 12), (x1 - 12, z0 + 12), (x0 + 12, z1 - 12), (x1 - 12, z1 - 12)):
        O.torre_focos(l, cx, cz, y0, rng, encendida=rng.random() < 0.5)


RESPALDOS = {"zona_perimetro": perimetro, "zona_plaza": plaza, "zona_cuarteles": cuarteles, "zona_hospital": hospital}
