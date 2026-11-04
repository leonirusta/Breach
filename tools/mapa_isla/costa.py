"""LA COSTA: el puerto con el faro, el barco naufragado y las playas.

  - EL PUERTO en la bahia del sureste: muelle de hormigon, tres espigones sobre pilotes con barcos
    amarrados, contenedores apilados, una grua portico, la nave del puerto y la capitania.
  - EL FARO en la punta este de la bahia: torre de 24 m con escalera de caracol alrededor de un pilar,
    linterna de cristal y galeria. Se ve desde todo el sur.
  - EL BARCO NAUFRAGADO varado en la playa del oeste: casco oxidado medio enterrado, con boquetes para entrar
    y el puente de mando en la popa.
  - LAS PLAYAS: chiringuitos, sombrillas y torres de socorrista repartidos por la costa.

Los barcos y los pilotes tocan el FONDO (arena, que es ancla): nada flota en el agua (el agua no es voxel).
"""
import math

import disposicion as D
import edificios as E
import naturaleza as NAT
import ciudad as C
import montana as MON


def punto_costa(T, ang, adentro):
    """Punto a `adentro` metros tierra adentro de la costa en el angulo `ang` (desde el centro de la isla).
    Con `adentro` negativo, mar adentro."""
    mejor = None
    for r10 in range(2450, 1000, -5):
        r = r10 / 10.0
        x, z = D.CX + math.cos(ang) * r, D.CZ + math.sin(ang) * r
        if not (0 < x < D.ANCHO_X and 0 < z < D.ANCHO_Z):
            continue
        i, k = T._ij(x, z)
        if T.dcosta[i, k] >= adentro:
            mejor = (x, z)
            break
    return mejor


ANG_PUERTO = math.atan2(D.PUERTO[1] - D.CZ, D.PUERTO[0] - D.CX)
_plan = {}


def planificar(T):
    # el muelle: la orilla de la bahia, un poco tierra adentro
    s = punto_costa(T, ANG_PUERTO, 6.0)
    _plan["muelle"] = s
    x, z = s
    yq = D.q(D.MAR_Y + 1.2)
    _plan["yq"] = yq
    T.aplanar(x - 34, z - 26, x + 30, z + 1.0, yq, falda=6.0, mat="acera")
    # naufragio: en la playa del oeste
    _plan["barco"] = punto_costa(T, math.radians(188.0), 1.0)
    # playas: chiringuito + socorrista
    _plan["playas"] = [punto_costa(T, math.radians(a), 12.0) for a in (20, 70, 118, 160, 232, 318, 345)]


def construir(l, T, rng):
    l.zona = "puerto"
    _puerto(l, T, rng)
    _faro(l, T, rng)
    l.zona = "costa"
    _naufragio(l, T, rng)
    for i, p in enumerate(_plan["playas"]):
        if p is None:
            continue
        x, z = p
        if D.cerca_de_carretera(x, z, 8.0) or not T.libre(x - 8, z - 8, x + 8, z + 8):
            continue
        y = T.altura(x, z)
        if y < D.MAR_Y + 0.5:
            continue
        MON.torre_socorrista(l, x, z, y, rng)
        _sombrillas(l, T, x + 5.0, z + 3.0, rng)
        if i % 2 == 0:
            E.casa(l, x - 11.0, z - 3.0, x - 4.0, z + 3.0, T.altura_min(x - 11, z - 3, x - 4, z + 3), rng, frente="+z",
                   muro="revoco_blanco", tejado="teja", nivel=1, porche=True)
        T.ocupar(x - 12, z - 5, x + 8, z + 7)
        l.spawn(x + 2.0, y + 0.5, z - 3.0)


def _sombrillas(l, T, x, z, rng):
    for k in range(3):
        px, pz = x + k * 3.2, z + (k % 2) * 2.0
        y = T.altura(px, pz)
        l.cilindro(px, y - 0.5, pz, 0.06, 2.8, "metal")
        l.cono(px, y + 2.2, pz, 1.4, 0.1, 0.6, ("toldo_rojo", "toldo_azul", "toldo_crema")[k])
        l.caja(px + 0.5, y - 0.15, pz - 0.35, px + 2.2, y + 0.3, pz + 0.35, "toldo_crema")


def _puerto(l, T, rng):
    x, z = _plan["muelle"]
    yq = _plan["yq"]
    # canto del muelle: muro de hormigon del fondo a la cota del muelle, con noray cada 6 m
    borde = z + 1.0
    l.caja(x - 34, T.altura(x, borde + 2.0) - 0.9, borde - 1.0, x + 30, yq, borde, "hormigon")
    for k in range(10):
        l.cilindro(x - 31 + k * 6.4, yq - 0.15, borde - 0.6, 0.25, 0.75, "metal_oscuro")
    # espigones: tablero de hormigon sobre pilas hasta el fondo, hacia mar adentro (+z)
    for k, dx in enumerate((-24.0, -4.0, 16.0)):
        px = x + dx
        largo = 28.0
        l.caja(px - 2.0, yq - 0.6, borde - 1.0, px + 2.0, yq, borde + largo, "hormigon")
        zz = borde + 3.0
        while zz < borde + largo:
            for s in (-1.6, 1.6):
                fondo = T.altura(px + s, zz)
                l.cilindro(px + s, fondo - 0.6, zz, 0.3, yq - fondo, "hormigon_oscuro")
            zz += 5.0
        C.farola(l, px + 1.6, borde + largo - 1.5, yq, (-1, 0), alto=4.5)
        # barco amarrado al costado
        _barco(l, T, px + 5.2, borde + 8.0 + k * 3.0, rng, ("chapa_azul", "chapa_roja", "chapa_blanca")[k])
        l.loot(px, yq, borde + largo - 3.0, ("arma", "escudo", "municion")[k], 2)
    # contenedores apilados (se tocan por caras enteras) y la grua portico
    colores = ["chapa_roja", "chapa_azul", "chapa_amarilla", "chapa_oxido", "chapa_blanca"]
    for i in range(4):
        for j in range(2):
            cx0 = x - 30.0 + i * 3.0
            cz0 = z - 22.0 + j * 6.5
            altura = 1 + (i + j) % 3
            for n in range(altura):
                yb = yq + n * 2.6
                l.caja(cx0, yb, cz0, cx0 + 2.5, yb + 2.6, cz0 + 6.1, colores[(i * 3 + j + n) % 5])
                if n == 0 and (i + j) % 2 == 0:          # el de abajo, abierto por un extremo: se entra
                    l.caja(cx0 + 0.1, yb + 0.1, cz0 - 0.01, cx0 + 2.4, yb + 2.5, cz0 + 6.0, "metal", hueco=True)
            if (i + j) % 2 == 0:
                l.loot(cx0 + 1.25, yq, cz0 + 3.0, "arma" if i % 2 else "municion", 2)
    # grua: dos patas en A a cada lado y la viga de arriba, con la cabina
    gx0, gx1, gz = x - 32.0, x - 16.0, z - 9.0
    for gx in (gx0, gx1):
        l.caja(gx - 0.5, yq - 0.6, gz - 5.0, gx + 0.5, yq + 0.3, gz + 5.0, "hormigon")
        l.linea(gx, yq, gz - 4.5, gx, yq + 14.0, gz, 0.7, "chapa_amarilla")
        l.linea(gx, yq, gz + 4.5, gx, yq + 14.0, gz, 0.7, "chapa_amarilla")
    l.caja(gx0 - 0.6, yq + 13.6, gz - 0.6, gx1 + 0.6, yq + 14.6, gz + 0.6, "chapa_amarilla")
    l.caja(gx0 + 6.0, yq + 12.0, gz - 1.2, gx0 + 8.5, yq + 13.61, gz + 1.2, "chapa_blanca")
    l.caja(gx0 + 6.1, yq + 12.4, gz - 1.21, gx0 + 8.4, yq + 13.2, gz + 1.21, "vidrio")
    l.linea(gx0 + 7.2, yq + 12.0, gz, gx0 + 7.2, yq + 6.0, gz, 0.1, "metal_oscuro")
    l.caja(gx0 + 6.2, yq + 4.6, gz - 1.2, gx0 + 8.2, yq + 6.0, gz + 1.2, "chapa_roja")
    l.loot(gx0 + 7.2, yq + 12.0, gz, "arma", 3)
    # nave del puerto y capitania
    E.nave(l, x + 4.0, z - 25.0, x + 26.0, z - 9.0, yq, rng, frente="+z", muro="chapa", cubierta="chapa_oxido", alto=6.0, nivel=2)
    m, ys, techo = E.bloque(l, x - 12.0, z - 24.0, x - 2.0, z - 14.0, yq, 3, rng, frente="+z", muro="revoco_blanco",
                            losa="revoco_azul", nivel=2, marco_ventana="revoco_azul", toldo="toldo_azul")
    E.azotea_detalle(m, l, techo, rng)
    # farolas del muelle
    for k in range(5):
        C.farola(l, x - 30.0 + k * 13.0, borde - 2.5, yq, (0, 1), alto=5.5)
    T.ocupar(x - 36, z - 28, x + 32, z + 30)
    l.spawn(x - 10.0, yq + 0.5, z - 4.0)
    l.spawn(x + 12.0, yq + 0.5, z - 4.0)


def _barco(l, T, x, z, rng, color):
    """Barco de pesca de 12 m: casco macizo apoyado en el fondo hasta la cubierta, cabina y mastil."""
    fondo = T.altura_min(x - 1.6, z - 6.0, x + 1.6, z + 6.0)
    yc = D.q(D.MAR_Y + 0.9)
    l.caja(x - 1.8, fondo - 0.3, z - 5.0, x + 1.8, yc, z + 5.0, color)
    l.elipsoide(x, yc - 0.6, z + 5.0, 1.8, 1.2, 1.8, color)            # la proa redondeada
    l.caja(x - 1.8, yc - 0.45, z - 5.0, x + 1.8, yc - 0.3, z + 5.0, "chapa_blanca")
    l.caja(x - 1.5, yc - 0.6, z - 4.7, x + 1.5, yc + 0.01, z + 4.5, color, hueco=True)
    l.caja(x - 1.5, yc - 0.9, z - 4.7, x + 1.5, yc - 0.6, z + 4.5, "madera")
    l.caja(x - 1.2, yc - 0.6, z - 4.0, x + 1.2, yc + 2.0, z - 1.0, "chapa_blanca")
    l.caja(x - 1.0, yc - 0.6, z - 3.8, x + 1.0, yc + 1.8, z - 1.2, "chapa_blanca", hueco=True)
    l.caja(x - 1.21, yc + 0.9, z - 3.6, x + 1.21, yc + 1.5, z - 1.4, "vidrio")
    l.caja(x - 0.4, yc - 0.6, z - 1.3, x + 0.4, yc + 1.6, z - 0.9, "chapa_blanca", hueco=True)
    l.cilindro(x, yc - 0.6, z + 1.5, 0.1, 5.0, "metal")
    l.loot(x, yc - 0.6, z + 2.5, "municion", 2)


def _sitio_faro(T):
    """La punta al este de la bahia, sobre la orilla DE VERDAD (el terreno ya final: las carreteras de la costa
    ensanchan la tierra, y la costa geometrica quedaba 27 m tierra adentro). Se busca, girando desde la bahia,
    el primer angulo cuya orilla no tenga una carretera ni nada construido a menos de 10 m."""
    for k in range(90):
        ang = ANG_PUERTO - 0.22 - k * 0.01
        for r10 in range(2450, 1500, -5):
            r = r10 / 10.0
            x, z = D.CX + math.cos(ang) * r, D.CZ + math.sin(ang) * r
            if T.altura(x, z) > D.MAR_Y + 0.6:
                x, z = D.CX + math.cos(ang) * (r - 4.0), D.CZ + math.sin(ang) * (r - 4.0)
                if not D.cerca_de_carretera(x, z, 8.0) and T.libre(x - 6, z - 6, x + 6, z + 12):
                    return x, z
                break
    return None


def _faro(l, T, rng):
    sitio = _sitio_faro(T)
    if sitio is None:
        print("  (faro: no hay sitio en la punta)")
        return
    fx, fz = sitio
    y = T.altura_max(fx - 3.6, fz - 3.6, fx + 3.6, fz + 3.6)
    l.cilindro(fx, T.altura_min(fx - 4.5, fz - 4.5, fx + 4.5, fz + 4.5) - 1.2, fz, 4.8, y - T.altura_min(fx - 4.5, fz - 4.5, fx + 4.5, fz + 4.5) + 1.2, "roca_monte")
    R = 3.6
    alto = 24.0
    l.cilindro(fx, y - 1.2, fz, R + 0.6, 1.35, "piedra")
    # fuste con franjas rojas y blancas, hueco por dentro
    for k in range(int(alto / 3.0)):
        r0 = R - k * 0.06
        l.cono(fx, y + k * 3.0, fz, r0, r0 - 0.06, 3.0, "chapa_roja" if k % 2 else "revoco_blanco")
    l.cilindro(fx, y + 0.15, fz, R - 0.9, alto - 0.3, "revoco_blanco", hueco=True)
    # escalera de caracol cuadrada alrededor del pilar central (como la torre del bosque)
    P, A = 0.6, 1.0
    sube = 0.9
    yy = y + 0.15
    tramo = 0
    l.caja(fx - P, y, fz - P, fx + P, y + alto, fz + P, "hormigon")
    while yy + sube <= y + alto - 0.3 + 0.01:
        n = 4
        for i in range(n):
            top = yy + sube * (i + 1) / n
            bot = max(yy - 0.15, top - 0.45)
            a, b = -P - A + (2 * P + 2 * A) * i / n, -P - A + (2 * P + 2 * A) * (i + 1) / n + 0.02
            if tramo % 4 == 0:
                l.caja(fx + a, bot, fz + P - 0.15, fx + b, top, fz + P + A, "hormigon_claro")
            elif tramo % 4 == 1:
                l.caja(fx + P - 0.15, bot, fz - b, fx + P + A, top, fz - a, "hormigon_claro")
            elif tramo % 4 == 2:
                l.caja(fx - b, bot, fz - P - A, fx - a, top, fz - P + 0.15, "hormigon_claro")
            else:
                l.caja(fx - P - A, bot, fz + a, fx - P + 0.15, top, fz + b, "hormigon_claro")
        yy += sube
        tramo += 1
    ytop = yy
    # piso de la linterna: losa con hueco sobre el ultimo tramo, galeria volada con barandilla
    l.cilindro(fx, ytop - 0.3, fz, R + 1.2, 0.3, "metal_oscuro")
    ult = (tramo - 1) % 4
    hx = {0: (-P - A, P, P + A, P + A), 1: (P, -P - A, P + A, P + A), 2: (-P - A, -P - A, P + A, -P), 3: (-P - A, -P - A, -P, P + A)}[ult]
    l.caja(fx + hx[0], ytop - 0.31, fz + hx[1], fx + hx[2], ytop + 0.01, fz + hx[3], "metal", hueco=True)
    l.cilindro(fx, ytop, fz, R + 1.2, 1.0, "metal_oscuro")
    l.cilindro(fx, ytop, fz, R + 1.05, 1.01, "metal_oscuro", hueco=True)
    # linterna: cristal y cupula
    l.cilindro(fx, ytop, fz, R - 0.6, 2.6, "vidrio")
    l.cilindro(fx, ytop, fz, R - 0.75, 2.61, "vidrio", hueco=True)
    l.caja(fx - 0.6, ytop, fz + R - 1.0, fx + 0.6, ytop + 2.2, fz + R, "vidrio", hueco=True)
    l.cono(fx, ytop + 2.6, fz, R - 0.4, 0.3, 1.8, "chapa_roja")
    l.caja(fx - 0.45, ytop - 0.1, fz - 0.45, fx + 0.45, ytop + 1.8, fz + 0.45, "luz_calida")    # la lampara, sobre la losa
    l.luz(fx, ytop + 1.4, fz, (255, 236, 190), 2.2, 40.0)
    # puerta y casa del farero
    l.puerta(fx, y + 0.15, fz + R - 0.3, 0.0, ancho=1.2, alto=2.4, tipo="madera", grosor=1.0)
    E.casa(l, fx - 4.0, fz + R + 2.5, fx + 4.0, fz + R + 9.0, T.altura(fx, fz + R + 5.5), rng, frente="+z",
           muro="revoco_blanco", tejado="teja", nivel=2, porche=False)
    l.loot(fx + 2.0, ytop, fz + 2.0, "arma", 3)
    l.loot(fx - 2.0, ytop, fz - 2.0, "casco", 2)
    T.ocupar(fx - 8, fz - 8, fx + 8, fz + R + 11)
    l.spawn(fx, y + 0.5, fz + R + 1.5)


def _naufragio(l, T, rng):
    p = _plan["barco"]
    if p is None:
        return
    x, z = p
    fondo = T.altura_min(x - 20, z - 5, x + 20, z + 5)
    L, A, H = 19.0, 5.2, 5.5
    yc = fondo - 0.9 + H                 # el casco queda 0,9 m enterrado
    yd = yc + 1.2                        # la cubierta
    # casco: elipsoide oxidado, vaciado, y cortado por la cubierta
    l.elipsoide(x, yc, z, L, H, A, "chapa_oxido")
    l.elipsoide(x, yc + 0.3, z, L - 0.45, H - 0.45, A - 0.45, "chapa_oxido", hueco=True)
    l.caja(x - L - 1, yd, z - A - 1, x + L + 1, yc + H + 1, z + A + 1, "chapa_oxido", hueco=True)
    # suelo de la bodega y cubierta: DISCOS elipticos que siguen la forma del casco (una caja recta asomaba
    # por las puntas y por los costados) y muerden la chapa por el borde
    ysuelo = yc - 2.0
    l.elipsoide(x, ysuelo - 0.15, z, 17.0, 0.16, 4.5, "madera_oscura")       # entre la cara de dentro y la de fuera del casco
    l.elipsoide(x, yd - 0.15, z, L * 0.97, 0.16, A * 0.97, "madera")
    for k in range(3):
        hx = x - 9.0 + k * 7.0
        l.caja(hx - 1.5, yd - 0.31, z - 1.5, hx + 1.5, yd + 0.01, z + 1.5, "madera", hueco=True)
    # boquetes en el costado de la playa para entrar a la bodega
    for k in range(2):
        l.elipsoide(x - 6.0 + k * 10.0, ysuelo + 1.2, z - A + 0.3, 1.8, 1.3, 1.6, "chapa_oxido", hueco=True)
    # puente de mando en popa
    px = x + L - 7.0
    l.caja(px - 2.5, yd, z - 2.8, px + 2.5, yd + 5.4, z + 2.8, "chapa_blanca")
    l.caja(px - 2.2, yd, z - 2.5, px + 2.2, yd + 2.4, z + 2.5, "chapa_blanca", hueco=True)
    l.caja(px - 2.2, yd + 2.7, z - 2.5, px + 2.2, yd + 5.1, z + 2.5, "chapa_blanca", hueco=True)
    l.caja(px - 2.51, yd + 3.6, z - 2.3, px - 2.2, yd + 4.5, z + 2.3, "vidrio")
    l.caja(px - 2.6, yd, z - 0.6, px - 2.1, yd + 2.2, z + 0.6, "chapa_blanca", hueco=True)
    for k in range(9):                                   # escalera interior al piso de arriba
        h = yd + (k + 1) * 0.3
        l.caja(px + 0.6, yd, z - 2.5 + k * 0.45, px + 2.2, h, z - 2.5 + (k + 1) * 0.45 + 0.02, "metal")
    l.caja(px + 0.6, yd + 2.39, z - 2.5, px + 2.2, yd + 2.71, z + 1.6, "chapa_blanca", hueco=True)
    l.cilindro(px + 1.0, yd + 5.4, z, 0.9, 3.0, "metal_oscuro")
    l.loot_sala(x - 10.0, z - 2.5, x + 8.0, z + 2.5, ysuelo, rng, 2, 3)
    l.loot(px, yd + 2.7, z, "arma", 3)
    T.ocupar(x - L - 2, z - A - 2, x + L + 2, z + A + 2)
    l.spawn(x - 3.0, yd + 0.3, z)
