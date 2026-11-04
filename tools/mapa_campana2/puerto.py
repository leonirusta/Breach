"""CONSTRUCCION del EPISODIO 2 "EL PUERTO" (campana_puerto). Ver disposicion.py para el recorrido.

Reutiliza el kit del episodio 1 (tools/mapa_campana/campana.py: bloques de relleno, ventanas, torre de
escalera, muebles) y el Lienzo del PvE. Noche cerrada: sodio naranja en la calle, focos blancos en el patio de
vias y en el muelle, fuego en los restos del helicoptero.

`validacion=True` construye la variante que solo sirve para comprobar el recorrido: sin el tapiado ni la
barricada (en el juego se rompen) y con una rampa de voxels donde caera la viga (en el juego la mueve un
objeto). El mapa que se escribe es siempre la variante normal.
"""
import math
import disposicion as D
import campana as K           # el kit del episodio 1 (bloque, ventanas, torre de escalera, muebles)

Y = D.SUELO_Y
P = D.PISO
MURO = 0.4

MATERIALES = dict(K.MATERIALES)
MATERIALES.update({
    "agua_rio": ((18, 30, 34), "organico"),
    "hormigon_muelle": ((92, 90, 84), "hormigon"),
    "chapa_naranja": ((150, 70, 24), "metal"),
    "chapa_gris": ((90, 94, 98), "metal"),
    "tablones": ((86, 64, 40), "madera"),
    "amarillo_peligro": ((190, 150, 20), "suelo_pintura"),
    "cable_rojo": ((170, 24, 20), "metal"),
})

SODIO = (255, 150, 80)
BLANCA = (210, 225, 255)
FUEGO = (255, 110, 30)


# ======================================================================================================
# TERRENO
# ======================================================================================================
def terreno(l):
    X, Z = D.ANCHO_X, D.ANCHO_Z
    l.caja(0, 0, 0, X, D.ROCA_Y, Z, "roca_base")
    l.caja(0, D.ROCA_Y, 0, X, Y, D.RIO_Z, "suelo_tierra")
    # el rio: agua quieta 0,45 m por debajo del muelle, y el cantil de hormigon del muelle
    l.caja(0, D.ROCA_Y, D.RIO_Z, X, D.RIO_AGUA_Y, Z, "agua_rio")
    l.caja(0, D.ROCA_Y, D.RIO_Z - 0.6, X, Y, D.RIO_Z, "hormigon_muelle")
    # suelos: grava en el patio, asfalto en la calle y el puerto
    l.caja(0, Y - 0.2, 0, 60, Y, 44, "suelo_grava")
    for x0, z0, x1, z1, _n in D.CALLES:
        l.caja(x0, Y - 0.2, z0, x1, Y, z1, "suelo_asfalto")
    l.caja(0, Y - 0.2, 90, D.ANCHO_X, Y, D.RIO_Z - 0.6, "suelo_hormigon")


def muro(l, x0, z0, x1, z1, alto, mat="ladrillo_gris"):
    l.caja(x0, Y - 0.6, z0, x1, Y + alto, z1, mat)


# ======================================================================================================
# EL PATIO DE VIAS
# ======================================================================================================
def via(l, z, x0, x1, y=Y):
    for x in range(int(x0), int(x1), 1):
        l.caja(x + 0.2, y, z - 1.2, x + 0.6, y + 0.14, z + 1.2, "madera_podrida")    # traviesas
    for dz in (-0.75, 0.75):
        l.caja(x0, y + 0.14, z + dz - 0.05, x1, y + 0.3, z + dz + 0.05, "metal")      # carriles


def vagon(l, x, z, largo, rng, mat=None, abierto=False):
    mat = mat or rng.choice(("metal_oxidado", "chapa_naranja", "chapa_verde", "chapa_gris"))
    for dx in (0.8, largo - 1.6):
        for dz in (-0.8, 0.8):
            l.cilindro(x + dx, Y + 0.14, z + dz, 0.42, 0.3, "metal_negro", eje="z")
    l.caja(x, Y + 0.7, z - 1.45, x + largo, Y + 1.0, z + 1.45, "metal_negro")          # chasis
    l.caja(x + 0.1, Y + 1.0, z - 1.4, x + largo - 0.1, Y + 3.6, z + 1.4, mat)
    l.caja(x + 0.3, Y + 1.0, z - 1.2, x + largo - 0.3, Y + 3.4, z + 1.2, mat, hueco=True)
    for i in range(1, int(largo / 1.2)):
        l.caja(x + i * 1.2, Y + 1.0, z - 1.46, x + i * 1.2 + 0.08, Y + 3.6, z + 1.46, "metal_negro")   # costillas
    if abierto:
        l.caja(x + largo / 2 - 1.2, Y + 1.0, z - 1.5, x + largo / 2 + 1.2, Y + 3.3, z - 1.1, mat, hueco=True)


def contenedor(l, x0, z0, eje, rng, y=Y, mat=None):
    mat = mat or rng.choice(("chapa_azul", "chapa_roja", "chapa_verde", "chapa_naranja", "chapa_gris"))
    if eje == "x":
        l.caja(x0, y, z0, x0 + 6.0, y + 2.6, z0 + 2.4, mat)
        for i in range(1, 12):
            l.caja(x0 + i * 0.5, y + 0.1, z0 - 0.04, x0 + i * 0.5 + 0.06, y + 2.5, z0 + 2.44, mat)
    else:
        l.caja(x0, y, z0, x0 + 2.4, y + 2.6, z0 + 6.0, mat)
        for i in range(1, 12):
            l.caja(x0 - 0.04, y + 0.1, z0 + i * 0.5, x0 + 2.44, y + 2.5, z0 + i * 0.5 + 0.06, mat)


def torre_luz(l, x, z, hacia):
    l.caja(x - 0.2, Y, z - 0.2, x + 0.2, Y + 9.0, z + 0.2, "metal_negro")
    l.caja(x - 0.8, Y + 9.0, z - 0.3, x + 0.8, Y + 9.6, z + 0.3, "metal_negro")
    l.caja(x - 0.7, Y + 9.05, z - 0.25, x + 0.7, Y + 9.15, z + 0.25, "luz_fria")
    l.luz(x + hacia[0] * 0.5, Y + 8.8, z + hacia[1] * 0.5, BLANCA, 1.4, 26.0)


def patio(l, rng):
    # tapia alrededor (el patio solo tiene una salida: el tunel)
    muro(l, 0, 0, 60, 0.5, 5.0, "hormigon_sucio")
    muro(l, 0, 0, 0.5, 44, 5.0, "hormigon_sucio")
    muro(l, 0, 43.5, 60, 44, 5.0, "hormigon_sucio")
    for x in range(4, 60, 6):          # pilastras y alambre de espino arriba
        l.caja(x, Y, 0.5, x + 0.5, Y + 5.4, 0.9, "hormigon_sucio")
        l.caja(x, Y, 43.1, x + 0.5, Y + 5.4, 43.5, "hormigon_sucio")
    l.caja(0, Y + 5.0, 0.1, 60, Y + 5.3, 0.3, "metal_negro")
    l.caja(0, Y + 5.0, 43.7, 60, Y + 5.3, 43.9, "metal_negro")
    # las vias y lo que hay sobre ellas
    for z in (6.0, 12.0, 38.0):
        via(l, z, 1.0, 60.0)
    vagon(l, 4.0, 6.0, 14.0, rng, "metal_oxidado")
    vagon(l, 19.0, 6.0, 14.0, rng, "chapa_naranja", abierto=True)
    vagon(l, 38.0, 12.0, 14.0, rng, "chapa_verde")
    vagon(l, 6.0, 38.0, 12.0, rng, "chapa_gris", abierto=True)
    vagon(l, 40.0, 38.0, 14.0, rng)
    # contenedores apilados (tapan la vista, no el paso)
    contenedor(l, 40.0, 24.0, "x", rng)
    contenedor(l, 40.0, 24.0, "x", rng, y=Y + 2.6)
    contenedor(l, 48.0, 28.5, "z", rng)
    contenedor(l, 28.0, 30.0, "x", rng)
    # traviesas amontonadas, bidones
    for i in range(5):
        l.caja(30.0, Y + i * 0.25, 16.0, 36.0, Y + (i + 1) * 0.25, 18.0 - i * 0.1, "madera_podrida")
    for bx, bz in ((52.0, 33.0), (52.9, 33.4), (52.4, 34.2), (2.5, 20.0), (3.3, 21.0)):
        l.cilindro(bx, Y, bz, 0.35, 0.95, rng.choice(("metal_oxidado", "chapa_azul", "plastico_amarillo")))
    # EL SURCO DEL HELICOPTERO: tierra levantada y escombros (los restos los pone el juego)
    hx, _hy, hz = D.HELI_ESTRELLADO
    for i in range(10):
        l.elipsoide(hx - 12 + i * 1.3, Y - 0.1, hz - 3.5 + i * 0.35, 1.3, 0.25, 0.9, "tierra", hueco=(i % 3 == 0))
    l.escombros(hx + 2, hz + 1, Y, 5.0, 26, rng, mats=("metal_negro", "chapa_blanca", "metal"))
    for fx, fz, e in ((hx + 1.5, hz + 1.0, 1.8), (hx - 3.0, hz - 1.5, 1.2), (hx + 4.5, hz - 2.0, 0.9)):
        K.fuego(l, fx, fz, Y, rng, grande=(e > 1.5))
    # la mesa de provisiones de los supervivientes (botiquines y municion encima: el juego)
    mx, _my, mz = D.MESA
    K.mesa(l, mx - 1.2, mz - 0.5, Y, w=3.0, d=1.0)
    l.caja(mx - 2.4, Y, mz + 1.0, mx + 2.4, Y + 2.6, mz + 1.2, "lona_verde")      # una lona colgada detras
    l.luz(mx, Y + 2.2, mz, (255, 200, 140), 0.9, 7.0)
    for x, z, h in ((6.0, 22.0, (1, 0)), (30.0, 3.0, (0, 1)), (56.0, 30.0, (-1, 0)), (30.0, 41.0, (0, -1))):
        torre_luz(l, x, z, h)


# ======================================================================================================
# EL TALUD, EL TUNEL Y EL TAPIADO
# ======================================================================================================
def talud(l, rng, validacion):
    x0, z0, x1, z1 = D.TALUD
    l.caja(x0, Y - 0.6, z0, x1, Y + D.TALUD_ALTO, z1, "ladrillo_oscuro")
    l.caja(x0 - 0.2, Y + D.TALUD_ALTO - 0.4, z0, x1 + 0.2, Y + D.TALUD_ALTO, z1, "cornisa")
    # EL TUNEL: boveda de 8 m de ancho y 4,5 de alto con sus farolillos
    tx0, tz0, tx1, tz1 = D.TUNEL
    l.caja(tx0 - 0.1, Y, tz0, tx1 + 0.1, Y + D.TUNEL_ALTO, tz1, "ladrillo_oscuro", hueco=True)
    l.caja(tx0 - 0.3, Y + D.TUNEL_ALTO, tz0 - 0.3, tx0, Y + D.TUNEL_ALTO + 0.5, tz1 + 0.3, "cornisa")
    l.caja(tx1, Y + D.TUNEL_ALTO, tz0 - 0.3, tx1 + 0.3, Y + D.TUNEL_ALTO + 0.5, tz1 + 0.3, "cornisa")
    l.caja(tx0 + 0.3, Y + D.TUNEL_ALTO - 0.1, (tz0 + tz1) / 2 - 0.3, tx0 + 1.3, Y + D.TUNEL_ALTO, (tz0 + tz1) / 2 + 0.3, "luz_roja")
    l.luz(tx0 + 0.8, Y + D.TUNEL_ALTO - 0.4, (tz0 + tz1) / 2, (255, 60, 40), 0.9, 8.0)
    l.luz(tx1 - 0.8, Y + D.TUNEL_ALTO - 0.4, (tz0 + tz1) / 2, SODIO, 0.7, 8.0)
    # EL TAPIADO: tablones clavados de lado a lado, y algun parche de ladrillo. Se rompe a tiros, a mazazos
    # o con una explosion. Las pintadas avisan desde el patio.
    if not validacion:
        a0, b0, a1, b1 = D.TAPIADO
        for i, y in enumerate([Y + k * 0.32 for k in range(int(D.TUNEL_ALTO / 0.32) + 1)]):
            if y >= Y + D.TUNEL_ALTO:
                break
            sesgo = 0.08 if i % 2 else -0.05
            l.caja(a0 + sesgo, y, b0, a1 + sesgo, min(y + 0.28, Y + D.TUNEL_ALTO), b1, "tablones")
        l.caja(a0 - 0.05, Y, b0 + 2.6, a1, Y + 1.5, b0 + 4.2, "ladrillo")
        for zz in (b0 + 1.0, (b0 + b1) / 2, b1 - 1.0):
            l.caja(a0 - 0.12, Y, zz - 0.1, a0, Y + D.TUNEL_ALTO, zz + 0.1, "madera_podrida")   # travesanos
        # la pintada roja "ROMPED" en la cara del patio (tres manchas: el juego pone el cartel)
        l.caja(a0 - 0.13, Y + 2.0, b0 + 1.5, a0 - 0.12, Y + 2.6, b1 - 1.5, "pintura_roja")


# ======================================================================================================
# LA CALLE DE LAS NAVES, LA NAVE, LA RAMPA Y EL ALTILLO
# ======================================================================================================
def farola(l, x, z, hacia):
    l.caja(x - 0.1, Y, z - 0.1, x + 0.1, Y + 5.2, z + 0.1, "metal_negro")
    l.caja(x - 0.1 + hacia[0] * 0.0, Y + 5.1, z - 0.1, x + hacia[0] * 1.2 + 0.1, Y + 5.25, z + hacia[1] * 1.2 + 0.1, "metal_negro")
    l.caja(x + hacia[0] * 1.2 - 0.25, Y + 4.95, z + hacia[1] * 1.2 - 0.18, x + hacia[0] * 1.2 + 0.25, Y + 5.1, z + hacia[1] * 1.2 + 0.18, "luz_calida")
    l.luz(x + hacia[0] * 1.2, Y + 4.8, z + hacia[1] * 1.2, SODIO, 1.1, 14.0)


def calle(l, rng):
    x0, z0, x1, z1, _ = D.CALLE
    l.caja(x0, Y, z0, x1, Y + 0.15, z0 + 1.8, "acera")
    l.caja(x0, Y, z1 - 1.8, x1, Y + 0.15, z1, "acera")
    for x in range(int(x0) + 4, int(x1) - 2, 16):
        farola(l, x, z0 + 1.0, (0, 1))
        farola(l, x + 8, z1 - 1.0, (0, -1))
    for x in range(int(x0) + 3, int(x1) - 3, 6):     # marcas del centro
        l.caja(x, Y, (z0 + z1) / 2 - 0.08, x + 3, Y + 0.02, (z0 + z1) / 2 + 0.08, "pintura_blanca")
    # coches abandonados (el de en medio atravesado)
    for cx, cz, eje in ((80.0, 17.0, "x"), (92.0, 21.5, "z"), (128.0, 18.5, "x"), (148.0, 22.0, "x")):
        coche(l, cx, cz, eje, rng)
    # el final de la calle: un muro con alambre (el mapa se acaba)
    muro(l, x1 - 0.5, z0, x1, z1, 5.0, "hormigon_sucio")


def coche(l, x, z, eje, rng):
    mat = rng.choice(("chapa_blanca", "chapa_roja", "chapa_azul", "chapa_gris"))
    if eje == "x":
        l.caja(x - 2.1, Y + 0.3, z - 0.9, x + 2.1, Y + 1.1, z + 0.9, mat)
        l.caja(x - 1.1, Y + 1.1, z - 0.8, x + 1.0, Y + 1.7, z + 0.8, mat)
        l.caja(x - 1.0, Y + 1.15, z - 0.82, x + 0.9, Y + 1.6, z + 0.82, "vidrio")
        for dx in (-1.4, 1.4):
            for dz in (-0.85, 0.85):
                l.cilindro(x + dx, Y + 0.02, z + dz - 0.12, 0.34, 0.24, "goma", eje="z")
    else:
        l.caja(x - 0.9, Y + 0.3, z - 2.1, x + 0.9, Y + 1.1, z + 2.1, mat)
        l.caja(x - 0.8, Y + 1.1, z - 1.1, x + 0.8, Y + 1.7, z + 1.0, mat)
        l.caja(x - 0.82, Y + 1.15, z - 1.0, x + 0.82, Y + 1.6, z + 0.9, "vidrio")
        for dx in (-0.85, 0.85):
            for dz in (-1.4, 1.4):
                l.cilindro(x + dx - 0.12, Y + 0.02, z + dz, 0.34, 0.24, "goma", eje="x")


def estanteria(l, x0, z0, x1, z1, alto, rng):
    """Estanteria de palets: patas, baldas y cajas encima (baja: nadie sube por ella al altillo)."""
    for x in (x0, x1 - 0.12):
        for z in (z0, z1 - 0.12):
            l.caja(x, Y, z, x + 0.12, Y + alto, z + 0.12, "chapa_naranja")
    for k in range(1, 3):
        y = Y + alto * k / 2
        l.caja(x0, y - 0.1, z0, x1, y, z1, "metal_negro")
    for k in range(0, 2):
        y = Y + alto * k / 2 + (0.0 if k == 0 else 0.0)
        n = int((x1 - x0) / 1.3) if (x1 - x0) > (z1 - z0) else int((z1 - z0) / 1.3)
        for i in range(n):
            if rng.random() < 0.3:
                continue
            if (x1 - x0) > (z1 - z0):
                a = x0 + 0.15 + i * 1.3
                l.caja(a, y, z0 + 0.1, a + 1.1, y + rng.uniform(0.5, 0.8), z1 - 0.1, rng.choice(("madera", "lona", "sacos")))
            else:
                a = z0 + 0.15 + i * 1.3
                l.caja(x0 + 0.1, y, a, x1 - 0.1, y + rng.uniform(0.5, 0.8), a + 1.1, rng.choice(("madera", "lona", "sacos")))


def nave(l, rng, validacion):
    x0, z0, x1, z1 = D.NAVE
    top = Y + D.NAVE_ALTO
    l.caja(x0, Y - 0.6, z0, x1, top, z1, "ladrillo_rojo")
    l.caja(x0 + MURO, Y, z0 + MURO, x1 - MURO, top - 0.5, z1 - MURO, "ladrillo_rojo", hueco=True)
    l.caja(x0 + MURO, Y - 0.2, z0 + MURO, x1 - MURO, Y, z1 - MURO, "suelo_hormigon")
    # cubierta en diente de sierra: cerchas de acero y lucernarios
    for x in range(int(x0) + 4, int(x1), 5):
        l.caja(x, top - 1.2, z0 + MURO, x + 0.3, top - 0.5, z1 - MURO, "metal_negro")
        l.caja(x + 1.0, top - 0.52, z0 + 2, x + 3.0, top - 0.48, z1 - 2, "vidrio")
    for x in range(int(x0) + 7, int(x1) - 3, 9):     # pilares
        for z in (z0 + 11.0, z0 + 22.0):
            if x0 + 26.0 <= x <= x0 + 29.0:
                continue
            l.caja(x - 0.3, Y, z - 0.3, x + 0.3, top - 0.5, z + 0.3, "hormigon_sucio")
    # la puerta grande de la calle (persiana levantada a medias)
    pa, pb = D.NAVE_PUERTA
    l.caja(pa, Y, z0 - 0.1, pb, Y + 3.6, z0 + MURO + 0.1, "ladrillo", hueco=True)
    l.caja(pa - 0.2, Y + 2.6, z0 - 0.2, pb + 0.2, Y + 3.6, z0 + 0.1, "persiana")
    l.caja(pa - 0.4, Y + 3.8, z0 - 0.35, pb + 0.4, Y + 4.4, z0 - 0.15, "chapa_naranja")      # el rotulo
    l.luz((pa + pb) / 2, Y + 3.4, z0 - 0.8, SODIO, 0.9, 9.0)
    # ventanas altas
    for x in range(int(x0) + 3, int(x1) - 2, 5):
        K.ventana(l, "-z", x, Y + 5.0, z0, ancho=2.2, alto=1.6, rng=rng)
        K.ventana(l, "+z", x, Y + 5.0, z1, ancho=2.2, alto=1.6, rng=rng)
    # la persiana del muelle de carga de la planta baja, reventada hacia dentro y atascada (no se pasa)
    l.caja(x1 - MURO - 0.3, Y, 40.0, x1 - MURO, Y + 3.8, 46.0, "persiana")
    for i in range(6):
        l.caja(x1 - MURO - 0.8 - i * 0.25, Y, 40.0 + i, x1 - MURO - 0.3, Y + 0.5 + i * 0.2, 41.0 + i, "chapa_gris")
    # estanterias (bajas, lejos del altillo) y cajas
    for z in (32.0, 37.0, 51.0, 56.0):
        estanteria(l, x0 + 3.0, z, x0 + 20.0, z + 1.4, 2.4, rng)
    for i in range(10):
        cx, cz = rng.uniform(x0 + 3, x0 + 22), rng.uniform(z0 + 3, z1 - 3)
        if 40 < cz < 49:
            continue
        s = rng.uniform(0.5, 0.9)
        l.caja(cx, Y, cz, cx + s, Y + s, cz + s, rng.choice(("madera", "madera_podrida", "lona")))
    # una carretilla elevadora volcada
    l.caja(x0 + 23.0, Y, 52.0, x0 + 25.4, Y + 1.2, 53.4, "plastico_amarillo")
    l.caja(x0 + 22.4, Y, 52.2, x0 + 23.0, Y + 2.6, 52.4, "metal_negro")
    # luces: fluorescentes colgados (unas pocas encendidas)
    for x, z, on in ((104.0, 36.0, True), (112.0, 48.0, False), (118.0, 36.0, True), (104.0, 55.0, True), (131.0, 45.0, True)):
        l.caja(x - 1.0, Y + 6.0, z - 0.1, x + 1.0, Y + 6.1, z + 0.1, "luz_fria" if on else "metal")
        l.caja(x - 0.02, Y + 6.1, z - 0.02, x + 0.02, top - 0.5, z + 0.02, "metal_negro")
        if on:
            l.luz(x, Y + 5.8, z, (190, 230, 210), 0.9, 12.0)
    altillo(l, rng)
    rampa(l, rng, validacion)


def altillo(l, rng):
    ax0, az0, ax1, az1 = D.ALTILLO
    ya = D.ALTILLO_Y
    l.caja(ax0, ya - 0.3, az0, ax1, ya, az1, "hormigon")
    for x in (ax0 + 0.3, ax0 + 7.0):          # pilares
        for z in (az0 + 1.0, az0 + 10.0, az0 + 20.0, az1 - 1.0):
            l.caja(x - 0.25, Y, z - 0.25, x + 0.25, ya - 0.3, z + 0.25, "hormigon_sucio")
    # baranda del borde oeste, salvo donde llega la rampa
    za, zb = D.RAMPA_Z
    for z_a, z_b in ((az0, za - 0.2), (zb + 0.2, az1)):
        l.caja(ax0, ya, z_a, ax0 + 0.1, ya + 1.0, z_b, "chapa_naranja")
        l.caja(ax0, ya + 0.95, z_a, ax0 + 0.12, ya + 1.1, z_b, "chapa_naranja")
    l.caja(ax0 - 0.05, ya - 0.3, za, ax0 + 0.6, ya + 0.02, zb, "amarillo_peligro")   # donde apoya la viga
    # oficina acristalada del encargado, cajas, taquillas
    l.caja(ax1 - 6.0, ya, az0 + 2.0, ax1, ya + 2.8, az0 + 8.0, "metal")
    l.caja(ax1 - 5.9, ya, az0 + 2.1, ax1 - 0.1, ya + 2.7, az0 + 7.9, "metal", hueco=True)
    l.caja(ax1 - 6.0, ya + 1.0, az0 + 3.0, ax1 - 5.9, ya + 2.4, az0 + 7.0, "vidrio")
    l.caja(ax1 - 6.02, ya, az0 + 7.0, ax1 - 5.88, ya + 2.4, az0 + 7.9, "metal", hueco=True)   # su puerta
    K.mesa(l, ax1 - 4.0, az0 + 3.0, ya)
    for z in range(int(az0) + 12, int(az1) - 12, 1):
        l.caja(ax1 - 0.6, ya, z + 0.05, ax1 - 0.1, ya + 1.9, z + 0.95, "chapa_gris")
    for i in range(6):
        cx, cz = rng.uniform(ax0 + 3, ax1 - 3), rng.uniform(az0 + 10, az1 - 3)
        if abs(cz - 50.2) < 2.0 or (za - 1.0 < cz < zb + 1.0):
            continue
        l.caja(cx, ya, cz, cx + 0.8, ya + 0.8, cz + 0.8, "madera")
    # la puerta del altillo a la pasarela (muro este de la nave, a la altura del altillo)
    px0, pz0, px1, pz1 = D.PASARELA
    l.caja(D.NAVE[2] - MURO - 0.1, ya, pz0, D.NAVE[2] + 0.1, ya + 2.6, pz1, "ladrillo", hueco=True)
    l.luz(ax1 - 1.0, ya + 2.3, (pz0 + pz1) / 2, (255, 60, 40), 0.7, 6.0)


def rampa(l, rng, validacion):
    """LAS DOS PILAS que aguantan la viga (el juego pone la viga encima). En la variante de validacion, una
    rampa de voxels en su sitio: asi se comprueba que desde abajo se llega al altillo cuando la viga cae."""
    ya = D.ALTILLO_Y
    for x0, z0, x1, z1 in (D.PILAS if not validacion else []):     # (en la validacion ya estan rotas)
        l.caja(x0, Y, z0, x1, ya - 0.13, z1, "ladrillo")
        l.caja(x0 - 0.05, ya - 0.5, z0 - 0.05, x1 + 0.05, ya - 0.13, z1 + 0.05, "madera")     # el calzo de arriba
    za, zb = D.RAMPA_Z
    # marcas en el suelo: amarillo y negro donde caera
    for i in range(6):
        l.caja(D.ALTILLO[0] - 7.0 + i * 1.2, Y, za - 0.2, D.ALTILLO[0] - 6.4 + i * 1.2, Y + 0.02, za, "amarillo_peligro")
    if validacion:
        x_b = D.ALTILLO[0] - math.sqrt(D.RAMPA_LARGO ** 2 - (ya - Y) ** 2)
        l.cuna(x_b, Y, za, D.ALTILLO[0], ya, zb, sube_hacia="+x", mat="metal")


def pasarela_y_torre(l, rng):
    px0, pz0, px1, pz1 = D.PASARELA
    ya = D.ALTILLO_Y
    l.caja(px0, ya - 0.2, pz0 - 0.1, px1 + 0.3, ya, pz1 + 0.1, "metal_negro")
    for z in (pz0 - 0.1, pz1):
        l.caja(px0, ya, z, px1, ya + 1.05, z + 0.1, "metal_negro")
    for x in (px0 + 2.6, px0 + 5.2):
        l.linea(x, Y, pz0 - 0.1, x, ya - 0.2, pz0 - 0.1, 0.14, "metal_negro")
        l.linea(x, Y, pz1 + 0.1, x, ya - 0.2, pz1 + 0.1, 0.14, "metal_negro")
    K.torre_escalera(l, D.TORRE, 2, [(0, "-x"), (1, "-x")], mat="ladrillo_gris", caseta=2.2)
    l.luz(px0 + 4.0, ya + 2.4, (pz0 + pz1) / 2, SODIO, 0.6, 7.0)


def callejon(l, rng):
    x0, z0, x1, z1, _ = D.CALLEJON
    for z in range(int(z0) + 4, int(z1) - 2, 9):
        l.caja(x0 + 0.4, Y, z, x0 + 1.6, Y + 1.3, z + 0.8, rng.choice(("chapa_verde", "chapa_azul")))   # cubos
        l.luz(x1 - 0.5, Y + 3.4, z + 2.0, SODIO, 0.8, 9.0)
        l.caja(x1 - 0.1, Y + 3.3, z + 1.8, x1, Y + 3.6, z + 2.2, "luz_calida")
    l.escombros((x0 + x1) / 2, 60.0, Y, 2.0, 8, rng)


def refugio(l, rng):
    x0, z0, x1, z1 = D.REFUGIO
    top = Y + 3.4
    l.caja(x0, Y - 0.6, z0, x1, top, z1, "hormigon")
    l.caja(x0 + MURO, Y, z0 + MURO, x1 - MURO, top - 0.3, z1 - MURO, "hormigon", hueco=True)
    for pz in (D.REFUGIO_PUERTA_N[1], D.REFUGIO_PUERTA_S[1]):
        px = D.REFUGIO_PUERTA_N[0]
        l.caja(px - 0.9, Y, pz - 0.5, px + 0.9, Y + 2.7, pz + 0.5, "hormigon", hueco=True)
        l.caja(px - 1.1, Y + 2.7, pz - 0.5, px + 1.1, Y + 2.9, pz + 0.5, "pintura_roja")
    # dentro: literas, mesa, pintadas, la luz roja de emergencia
    K.cama(l, x0 + 0.6, z0 + 1.0, Y, "x", rng)
    K.cama(l, x0 + 0.6, z1 - 2.6, Y, "x", rng)
    K.mesa(l, x1 - 3.4, (z0 + z1) / 2 - 0.4, Y)
    l.caja(x0 + MURO, Y + 1.4, z0 + 3.0, x0 + MURO + 0.02, Y + 2.2, z0 + 7.0, "pintura_roja")
    l.caja(x0 + 5.0, top - 0.4, (z0 + z1) / 2 - 0.1, x0 + 7.0, top - 0.3, (z0 + z1) / 2 + 0.1, "luz_roja")
    l.luz(x0 + 6.0, top - 0.8, (z0 + z1) / 2, (255, 80, 60), 1.0, 10.0)


def barricada(l, rng, validacion):
    if validacion:
        return
    x0, z0, x1, z1 = D.BARRICADA
    # palets y cajas de madera de lado a lado, hasta 3,4 m: se rompe a tiros o a mazazos
    for i in range(int((x1 - x0) / 1.0)):
        x = x0 + i * 1.0
        h = 3.4 if i % 3 != 1 else 2.8
        for k in range(int(h / 0.55)):
            y = Y + k * 0.55
            l.caja(x + 0.03, y, z0 + (0.05 if k % 2 else -0.1), x + 0.97, y + 0.5, z1 + (0.0 if k % 2 else -0.15), rng.choice(("madera", "tablones", "madera_podrida")))
    l.caja(x0, Y + 1.0, z0 - 0.12, x1, Y + 1.12, z0 - 0.1, "tablones")      # tablon cruzado
    l.caja(x0, Y + 2.6, z0 - 0.12, x1, Y + 2.72, z0 - 0.1, "tablones")


# ======================================================================================================
# EL PUERTO
# ======================================================================================================
def caseta(l, rect, puerta, rng):
    x0, z0, x1, z1 = rect
    top = Y + 3.0
    mat = rng.choice(("chapa_gris", "chapa_verde", "chapa_azul"))
    l.caja(x0, Y - 0.3, z0, x1, top, z1, mat)
    l.caja(x0 + 0.2, Y, z0 + 0.2, x1 - 0.2, top - 0.2, z1 - 0.2, mat, hueco=True)
    cx = (x0 + x1) / 2
    zp = z1 if puerta == "+z" else z0
    l.caja(cx - 0.8, Y, zp - 0.4, cx + 0.8, Y + 2.6, zp + 0.4, mat, hueco=True)
    l.caja(x0 - 0.3, top, z0 - 0.3, x1 + 0.3, top + 0.2, z1 + 0.3, "metal_oxidado")
    # estanteria dentro con el sitio del fusible (lo pone el juego) y una bombilla
    zi = z0 + 0.4 if puerta == "+z" else z1 - 1.0
    l.caja(x0 + 1.0, Y, zi, x1 - 1.0, Y + 0.8, zi + 0.6, "madera")
    l.caja(cx - 0.1, top - 0.3, (z0 + z1) / 2 - 0.1, cx + 0.1, top - 0.2, (z0 + z1) / 2 + 0.1, "luz_calida")
    l.luz(cx, top - 0.6, (z0 + z1) / 2, (255, 190, 120), 0.8, 7.0)


def grua(l, x, z):
    for dx in (-2.5, 2.5):
        for dz in (-2.5, 2.5):
            l.caja(x + dx - 0.3, Y, z + dz - 0.3, x + dx + 0.3, Y + 14.0, z + dz + 0.3, "chapa_naranja")
    for y in (Y + 5, Y + 10):
        l.caja(x - 2.8, y, z - 2.8, x + 2.8, y + 0.4, z + 2.8, "chapa_naranja", hueco=False)
        l.caja(x - 2.2, y - 0.1, z - 2.2, x + 2.2, y + 0.5, z + 2.2, "chapa_naranja", hueco=True)
    l.caja(x - 3.0, Y + 14.0, z - 3.0, x + 3.0, Y + 15.0, z + 16.0, "chapa_naranja")     # el brazo, sobre el rio
    l.caja(x - 1.5, Y + 15.0, z - 2.5, x + 1.5, Y + 17.5, z + 1.0, "chapa_naranja")     # la cabina
    l.caja(x - 1.4, Y + 15.6, z + 0.9, x + 1.4, Y + 17.0, z + 1.02, "ventana_fria")
    l.luz(x, Y + 13.6, z + 8.0, BLANCA, 1.2, 22.0)


def puerto(l, rng):
    X = D.ANCHO_X
    # el borde del muelle: bolardos y valla (no se baja al rio salvo por el embarcadero)
    for x in range(2, int(X) - 1, 8):
        if D.EMBARCADERO[0] - 1 <= x <= D.EMBARCADERO[2] + 1:
            continue
        l.cilindro(x, Y, D.RIO_Z - 0.35, 0.22, 0.6, "metal_negro")
    for x0, x1 in ((0.0, D.EMBARCADERO[0]), (D.EMBARCADERO[2], X)):
        l.caja(x0, Y, D.RIO_Z - 0.3, x1, Y + 1.7, D.RIO_Z - 0.22, "metal_negro")
        for x in range(int(x0), int(x1), 3):
            l.caja(x, Y, D.RIO_Z - 0.34, x + 0.08, Y + 1.8, D.RIO_Z - 0.18, "metal_negro")
    # el embarcadero de madera
    e0, ez0, e1, ez1 = D.EMBARCADERO
    l.caja(e0, Y - 0.25, ez0 - 0.6, e1, Y, ez1, "tablones")
    for x in (e0 + 0.3, e1 - 0.3, (e0 + e1) / 2):
        for z in (ez0 + 2.0, ez0 + 6.0, ez1 - 0.3):
            l.cilindro(x, D.ROCA_Y, z, 0.2, Y - D.ROCA_Y, "madera_podrida")
    for x in (e0, e1 - 0.1):
        l.caja(x, Y, ez0, x + 0.1, Y + 1.05, ez1 - 3.0, "madera")
    l.caja(e0 + 1.0, Y + 1.8, ez1 - 0.4, e0 + 1.2, Y + 2.0, ez1 - 0.2, "luz_verde")
    l.luz((e0 + e1) / 2, Y + 3.0, ez1 - 1.0, (170, 255, 190), 1.0, 12.0)
    # el cierre norte del puerto: naves de relleno de pared a pared (solo se entra por el callejon)
    # las casetas de los fusibles
    for x0, z0, x1, z1, puerta in D.CASETAS:
        caseta(l, (x0, z0, x1, z1), puerta, rng)
    # la sala de control de la reja y su cuadro electrico
    sx0, sz0, sx1, sz1 = D.SALA_CONTROL
    l.caja(sx0, Y - 0.3, sz0, sx1, Y + 3.2, sz1, "hormigon")
    l.caja(sx0 + 0.3, Y, sz0 + 0.3, sx1 - 0.3, Y + 2.9, sz1 - 0.3, "hormigon", hueco=True)
    l.caja(sx0 + 1.0, Y + 1.0, sz1 - 0.35, sx1 - 1.0, Y + 2.2, sz1 + 0.05, "vidrio")
    cx, _cy, cz = D.CUADRO
    l.caja(cx - 0.6, Y, cz - 1.25, cx + 0.6, Y + 1.8, cz - 0.95, "chapa_gris")        # el cuadro
    l.caja(cx - 0.5, Y + 1.1, cz - 0.96, cx - 0.1, Y + 1.5, cz - 0.94, "luz_roja")
    l.caja(cx - 0.02, Y + 1.8, cz - 1.15, cx + 0.02, Y + 3.2, cz - 1.05, "cable_rojo")
    l.luz(cx, Y + 2.6, cz + 0.5, (255, 70, 50), 0.9, 8.0)
    # la reja del muelle (la pone el juego): sus dos postes de hormigon
    px0, pz0, px1, pz1 = D.PORTON
    l.caja(px0 - 0.4, Y, pz0 - 0.6, px1 + 0.4, Y + 6.2, pz0, "hormigon_sucio")
    l.caja(px0 - 0.4, Y, pz1 - 0.2, px1 + 0.4, Y + 6.2, pz1 + 0.3, "hormigon_sucio")
    # contenedores del puerto (cubren, no cierran), gruas y bolardos
    for x, z, eje, pisos in ((128.0, 104.0, "x", 2), (86.0, 92.0, "x", 1), (106.0, 95.0, "z", 2),
                             (40.0, 92.5, "x", 1), (34.0, 106.0, "x", 1), (140.0, 98.0, "z", 1), (8.0, 93.0, "x", 2)):
        for k in range(pisos):
            contenedor(l, x, z, eje, rng, y=Y + k * 2.6)
    grua(l, 90.0, 108.0)
    grua(l, 38.0, 108.0)
    # la sirena del muelle (llama al barco): un poste con su bocina y su boton
    bx, _by, bz = D.BOCINA
    l.caja(bx - 0.15, Y, bz - 1.2, bx + 0.15, Y + 4.0, bz - 0.9, "metal_negro")
    l.cilindro(bx, Y + 3.6, bz - 0.6, 0.35, 0.8, "chapa_gris", eje="z")
    l.caja(bx - 0.4, Y + 0.9, bz - 0.9, bx + 0.4, Y + 1.5, bz - 0.7, "plastico_amarillo")
    # focos del puerto
    for x in range(12, int(X) - 4, 22):
        torre_luz(l, x, 91.5, (0, 1))


def rellenos(l, rng):
    """Los bloques de edificios que cierran el recorrido: nadie ataja por detras."""
    for rect, pisos in (
        ((66.0, 0.0, 160.0, 14.0), 3),     # norte de la calle
        ((66.0, 26.0, 96.0, 62.0), 3),     # entre la calle y el sur (oeste de la nave)
        ((140.0, 26.0, 160.0, 40.0), 3),   # cierra el callejon por el norte
        ((154.8, 40.0, 160.0, 52.0), 2),
        ((148.0, 52.0, 160.0, 70.0), 3),
        ((96.0, 62.0, 140.0, 70.0), 2),
        ((0.0, 44.0, 66.0, 90.0), 3),      # al sur del patio
        ((66.0, 62.0, 96.0, 90.0), 3),
        ((96.0, 70.0, 138.0, 90.0), 2),
        ((150.0, 70.0, 160.0, 90.0), 2),
        ((138.0, 80.0, 140.0, 90.0), 2),
        ((148.0, 80.0, 150.0, 90.0), 2),
    ):
        x0, z0, x1, z1 = rect
        # troceados en edificios de 12-20 m para que no parezca un muro
        nx = max(1, int((x1 - x0) / 16.0))
        nz = max(1, int((z1 - z0) / 16.0))
        for i in range(nx):
            for j in range(nz):
                a0, a1 = x0 + (x1 - x0) * i / nx, x0 + (x1 - x0) * (i + 1) / nx
                b0, b1 = z0 + (z1 - z0) * j / nz, z0 + (z1 - z0) * (j + 1) / nz
                K.bloque(l, (a0, b0, a1, b1), max(1, pisos + rng.randint(-1, 1)), rng)


def construir(l, rng, validacion=False):
    terreno(l)
    rellenos(l, rng)
    patio(l, rng)
    talud(l, rng, validacion)
    calle(l, rng)
    nave(l, rng, validacion)
    pasarela_y_torre(l, rng)
    callejon(l, rng)
    refugio(l, rng)
    barricada(l, rng, validacion)
    puerto(l, rng)
    # pistas de salida de las criaturas (ademas de las que calcula la validacion)
    for p in D.RUTA:
        l.punto(p[0], p[1], p[2], "ruta")
