"""CONSTRUCCION del mapa de campaña "campana_huida" (ver disposicion.py para el recorrido).

Noche cerrada, sin luna. Ladrillo rojo oscuro, asfalto mojado, farolas de sodio naranjas, fuegos en la calle,
ventanas encendidas en los bloques, fluorescentes verdosos dentro. Todo lo que se pisa cumple las reglas de
las criaturas (A* de voxels: escalones <= 0,8 m, agente de 1,8 m, puertas de 1,4 x 2,6) y las de
docs/10_CONSTRUIR_MAPAS.md (mordida de 0,25 m, apoyos en el suelo de verdad, cristales en el plano del muro).

Solo apunta primitivas en el Lienzo (tools/mapa_pve/lienzo.py); el integrador rasteriza.
"""
import math
import disposicion as D
import objetos as O

Y = D.SUELO_Y
P = D.PISO
LOSA = D.LOSA
MURO = 0.4

# materiales propios del mapa (el integrador los registra en el Lienzo)
MATERIALES = {
    "ladrillo_oscuro": ((78, 40, 32), "ladrillo"),
    "ladrillo_rojo": ((118, 52, 38), "ladrillo"),
    "ladrillo_gris": ((86, 82, 78), "ladrillo"),
    "revoco": ((122, 112, 96), "hormigon"),
    "cornisa": ((96, 92, 84), "hormigon"),
    "acera": ((72, 70, 66), "suelo_duro"),
    "bordillo": ((96, 94, 88), "suelo_duro"),
    "moqueta": ((70, 44, 40), "tela"),
    "papel_pintado": ((104, 94, 70), "hormigon"),
    "azulejo": ((150, 156, 150), "piedra"),
    "metal_rojo": ((150, 22, 18), "metal"),
    "persiana": ((70, 72, 74), "metal"),
    "ventana_luz": ((236, 176, 96), "luz"),       # ventana encendida (emisiva: no cuesta luces)
    "ventana_fria": ((150, 190, 200), "luz"),     # fluorescente azulado tras el cristal
    "neon_rosa": ((255, 60, 150), "luz"),
    "neon_azul": ((60, 140, 255), "luz"),
    "fuego": ((255, 120, 30), "luz"),
    "pintura_roja": ((150, 20, 16), "suelo_pintura"),
    "helipuerto": ((60, 62, 66), "suelo_duro"),
}

CALIDA = (255, 150, 80)
FRIA = (170, 220, 200)
FUEGO = (255, 110, 30)
ROJA = (255, 40, 30)


def r1(x):
    return round(x * 10.0) / 10.0


# ======================================================================================================
# TERRENO Y CALLES
# ======================================================================================================
def terreno(l, rng):
    X, Z = D.ANCHO_X, D.ANCHO_Z
    l.caja(0, 0, 0, X, Y, Z, "suelo_tierra")
    l.caja(0, 0, 0, X, D.ROCA_Y, Z, "roca_base")
    for x0, z0, x1, z1, nombre in D.CALLES:
        l.caja(x0, Y - 0.2, z0, x1, Y, z1, "suelo_asfalto")
    # la acera del refugio y el paso de su puerta sur hasta la calle Segunda
    l.caja(155.6, Y - 0.2, 64.0, 161.2, Y, 66.4, "suelo_asfalto")


def _acera(l, x0, z0, x1, z1):
    """acera 15 cm mas alta con su bordillo: se pisa (escalon de 0,15)"""
    l.caja(x0, Y, z0, x1, Y + 0.15, z1, "acera")


def aceras_y_marcas(l, rng):
    """Aceras a los dos lados de las calles largas, eje amarillo discontinuo, pasos de cebra, alcantarillas,
    charcos (el asfalto mojado) y basura."""
    for (x0, z0, x1, z1, nombre) in (D.CALLE_A, D.CALLE_B, D.CALLE_C):
        largo_x = (x1 - x0) > (z1 - z0)
        if largo_x:
            _acera(l, x0, z0, x1, z0 + 2.4)
            _acera(l, x0, z1 - 2.4, x1, z1)
            zc = (z0 + z1) / 2
            x = x0 + 2.0
            while x < x1 - 3.0:
                l.caja(x, Y - 0.01, zc - 0.08, x + 2.2, Y + 0.0, zc + 0.08, "pintura_amarilla")
                x += 4.8
        for _ in range(int(max(x1 - x0, z1 - z0) / 6)):
            cx, cz = rng.uniform(x0 + 3, x1 - 3), rng.uniform(z0 + 3, z1 - 3)
            r = rng.uniform(0.8, 2.6)
            l.elipsoide(cx, Y - 0.05, cz, r, 0.06, r * rng.uniform(0.4, 0.9), "agua_sucia")
        for _ in range(int(max(x1 - x0, z1 - z0) / 25)):
            cx, cz = rng.uniform(x0 + 4, x1 - 4), (z0 + z1) / 2 + rng.uniform(-3, 3)
            l.cilindro(cx, Y - 0.02, cz, 0.45, 0.03, "metal_negro")      # tapa de alcantarilla
    # pasos de cebra en las esquinas
    for (x, z0, z1) in ((150.0, 36.4, 45.6), (30.0, 68.8, 80.0), (100.0, 112.8, 124.0)):
        for i in range(int((z1 - z0) / 0.9)):
            l.caja(x - 1.4, Y - 0.01, z0 + i * 0.9, x + 1.4, Y + 0.0, z0 + i * 0.9 + 0.45, "pintura_blanca")


def farolas(l, rng):
    """Farolas de sodio a lo largo de las calles (una de cada tres rota o apagada: la ciudad cae)."""
    tramos = [(D.CALLE_A, 11.0), (D.CALLE_B, 11.0), (D.CALLE_C, 11.0)]
    for (x0, z0, x1, z1, _n), paso in tramos:
        x = x0 + 6.0
        lado = 0
        while x < x1 - 4.0:
            z = z0 + 1.0 if lado == 0 else z1 - 1.0
            est = rng.choice(("encendida", "encendida", "encendida", "encendida", "rota"))
            O.farola(l, r1(x), z, Y + 0.15, est, rng, hacia=(0, 1) if lado == 0 else (0, -1), alto=6.0)
            x += paso
            lado = 1 - lado
    # esquina oeste y plaza
    for (x, z, h) in ((11.0, 96.0, (1, 0)), (22.0, 104.0, (-1, 0)), (94.0, 104.0, (1, 0)), (94.0, 160.0, (1, 0)),
                      (112.0, 150.0, (-1, 0))):
        O.farola(l, x, z, Y, "encendida", rng, hacia=h, alto=6.0)


# ======================================================================================================
# KIT: CAJA DE ESCALERA (sube planta a planta; la usan los apartamentos y el hospital)
# ======================================================================================================
def torre_escalera(l, rect, pisos, puertas, mat="hormigon_sucio", caseta=3.0):
    """Escalera en tijera dentro de una torre de 6,8 x 10,4 m (con muros): dos carriles de 3 m y rellanos de
    1,6 m en los extremos. Cada tramo sube una planta entera (3,2 m en 6,4 m: 13 peldaños de 0,25), y el
    siguiente va por el otro carril en sentido contrario, asi que sobre cada tramo el de encima queda a 6,4 m:
    sobra altura para pasar. Arriba sigue una CASETA de `caseta` m que sale a la azotea.

    `puertas`: [(planta, lado)] con lado "-x" | "+x": hueco de 1,4 x 2,6 en el rellano de esa planta.
    Rellano de la planta k: el extremo z0 si k es par, el z1 si es impar."""
    x0, z0, x1, z1 = rect
    ix0, iz0, ix1, iz1 = x0 + MURO, z0 + MURO, x1 - MURO, z1 - MURO
    ytop = Y + pisos * P + caseta
    l.caja(x0, Y - 0.6, z0, x1, ytop + 0.4, z1, mat)
    l.caja(ix0, Y, iz0, ix1, ytop, iz1, mat, hueco=True)
    carril = (ix1 - ix0) / 2.0
    land = 1.6
    largo = (iz1 - iz0) - 2 * land
    for k in range(pisos):
        yk = Y + k * P
        if k % 2 == 0:
            l.escalera(ix0, iz0 + land, yk, largo, carril, P, "+z", "hormigon")
            l.caja(ix0, yk + P - LOSA, iz1 - land, ix1, yk + P, iz1, "hormigon")
        else:
            l.escalera(ix0 + carril, iz1 - land, yk, largo, carril, P, "-z", "hormigon")
            l.caja(ix0, yk + P - LOSA, iz0, ix1, yk + P, iz0 + land, "hormigon")
        # baranda entre carriles en el tramo (media altura, no corta el paso de los rellanos)
        l.caja(ix0 + carril - 0.05, yk + 0.9, iz0 + land + 0.4, ix0 + carril + 0.05, yk + P + 0.9, iz1 - land - 0.4, "metal_negro")
        # fluorescente del rellano
        zl = iz1 - land / 2 if k % 2 == 0 else iz0 + land / 2      # debajo del rellano que SI hay encima
        l.caja(ix0 + 2.0, yk + P - LOSA - 0.08, zl - 0.4, ix0 + 4.0, yk + P - LOSA, zl + 0.4, "ventana_fria")
    for planta, lado in puertas:
        yk = Y + planta * P
        zl0 = iz0 if planta % 2 == 0 else iz1 - land
        za, zb = zl0 + 0.1, zl0 + land - 0.1
        if lado == "-x":
            l.caja(x0 - 0.05, yk, za, ix0 + 0.05, yk + 2.7, zb, mat, hueco=True)
        else:
            l.caja(ix1 - 0.05, yk, za, x1 + 0.05, yk + 2.7, zb, mat, hueco=True)
    # luz de la caja (una sola, en medio: el resto son los fluorescentes emisivos)
    l.luz((ix0 + ix1) / 2, Y + pisos * P / 2, (iz0 + iz1) / 2, FRIA, 0.55, 14.0)


# ======================================================================================================
# KIT: VENTANAS Y FACHADAS
# ======================================================================================================
def ventana(l, cara, u, y, fijo, ancho=1.2, alto=1.5, rng=None, luz="auto"):
    """Hueco con su cristal EN EL PLANO del muro. cara: "-z" | "+z" | "-x" | "+x" (el muro exterior en `fijo`).
    luz: "auto" (a veces encendida), "si", "no", "rota" (sin cristal)."""
    if luz == "auto":
        tira = rng.random() if rng else 0.5
        luz = "si" if tira < 0.22 else ("fria" if tira < 0.28 else ("rota" if tira < 0.36 else "no"))
    mat = {"si": "ventana_luz", "fria": "ventana_fria", "no": "metal_negro", "rota": None}[luz]
    a, b = u - ancho / 2, u + ancho / 2
    if cara in ("-z", "+z"):
        s = -1 if cara == "-z" else 1
        l.caja(a, y, fijo - s * 0.12, b, y + alto, fijo + s * 0.05, "ladrillo", hueco=True)
        if mat:
            l.caja(a, y, fijo - s * 0.12, b, y + alto, fijo - s * 0.02, mat)
        l.caja(a - 0.1, y - 0.12, fijo - s * 0.05, b + 0.1, y, fijo + s * 0.12, "cornisa")   # alfeizar
    else:
        s = -1 if cara == "-x" else 1
        l.caja(fijo - s * 0.12, y, a, fijo + s * 0.05, y + alto, b, "ladrillo", hueco=True)
        if mat:
            l.caja(fijo - s * 0.12, y, a, fijo - s * 0.02, y + alto, b, mat)
        l.caja(fijo - s * 0.05, y - 0.12, a - 0.1, fijo + s * 0.12, y, b + 0.1, "cornisa")


def fachada_ventanas(l, rect, pisos, rng, caras=("-z", "+z", "-x", "+x"), desde=0, paso=2.8, tipo_bajo=None):
    """Una fila de ventanas por planta en las caras pedidas (desde la planta `desde`)."""
    x0, z0, x1, z1 = rect
    for k in range(desde, pisos):
        y = Y + k * P + 0.9
        for cara in caras:
            if cara in ("-z", "+z"):
                fijo = z0 if cara == "-z" else z1
                n = int((x1 - x0 - 1.6) / paso)
                for i in range(n):
                    ventana(l, cara, x0 + 1.4 + (i + 0.5) * (x1 - x0 - 2.8) / max(n, 1), y, fijo, rng=rng)
            else:
                fijo = x0 if cara == "-x" else x1
                n = int((z1 - z0 - 1.6) / paso)
                for i in range(n):
                    ventana(l, cara, z0 + 1.4 + (i + 0.5) * (z1 - z0 - 2.8) / max(n, 1), y, fijo, rng=rng)


def escalera_incendios(l, cara, u0, u1, fijo, pisos, rng):
    """Escalera de incendios de hierro pegada a la fachada (plataformas por planta, mordiendo el muro 0,3 m)."""
    s = -1 if cara in ("-z", "-x") else 1
    for k in range(1, pisos):
        y = Y + k * P
        if cara in ("-z", "+z"):
            l.caja(u0, y - 0.1, fijo - s * 0.3, u1, y, fijo + s * 1.2, "metal_negro")
            l.caja(u0, y + 0.9, fijo + s * 1.1, u1, y + 1.0, fijo + s * 1.2, "metal_negro")
            l.linea(u0 + 0.3, y, fijo + s * 0.7, u1 - 0.3, y + P - 0.1, fijo + s * 0.7, 0.12, "metal_negro")
        else:
            l.caja(fijo - s * 0.3, y - 0.1, u0, fijo + s * 1.2, y, u1, "metal_negro")
            l.caja(fijo + s * 1.1, y + 0.9, u0, fijo + s * 1.2, y + 1.0, u1, "metal_negro")
            l.linea(fijo + s * 0.7, y, u0 + 0.3, fijo + s * 0.7, y + P - 0.1, u1 - 0.3, 0.12, "metal_negro")


def bloque(l, rect, pisos, rng, mat=None, abierto_calle=None):
    """Edificio CERRADO de relleno: cascaron de ladrillo (hueco por dentro, con pilares para aguantar la
    cubierta), ventanas, cornisa, bajo comercial con persianas, y trastos en la azotea."""
    x0, z0, x1, z1 = rect
    if x1 - x0 < 3.0 or z1 - z0 < 3.0:
        l.caja(x0, Y - 0.6, z0, x1, Y + pisos * P, z1, mat or "ladrillo_oscuro")
        return
    mat = mat or rng.choice(("ladrillo_oscuro", "ladrillo_oscuro", "ladrillo_rojo", "ladrillo_rojo", "ladrillo", "ladrillo_gris"))
    top = Y + pisos * P
    l.caja(x0, Y - 0.6, z0, x1, top, z1, mat)
    l.caja(x0 + MURO, Y, z0 + MURO, x1 - MURO, top - 0.4, z1 - MURO, mat, hueco=True)
    # pilares cada ~7 m: la cubierta no vuela entera sobre los cuatro muros (modelo de carga)
    nx, nz = max(1, int((x1 - x0) / 7.0)), max(1, int((z1 - z0) / 7.0))
    for i in range(1, nx):
        for j in range(1, nz):
            px, pz = x0 + (x1 - x0) * i / nx, z0 + (z1 - z0) * j / nz
            l.caja(px - 0.3, Y, pz - 0.3, px + 0.3, top - 0.3, pz + 0.3, "hormigon_sucio")
    # cornisa y peto
    l.caja(x0 - 0.2, top - 0.5, z0 - 0.2, x1 + 0.2, top - 0.2, z1 + 0.2, "cornisa")
    l.caja(x0, top, z0, x1, top + 0.9, z1, mat)
    l.caja(x0 + 0.3, top, z0 + 0.3, x1 - 0.3, top + 0.9, z1 - 0.3, mat, hueco=True)
    fachada_ventanas(l, rect, pisos, rng, desde=1)
    # planta baja: persianas metalicas o escaparates tapiados hacia las calles
    for cara in ("-z", "+z", "-x", "+x"):
        largo = (x1 - x0) if cara in ("-z", "+z") else (z1 - z0)
        if largo < 5.0:
            continue
        n = max(1, int(largo / 6.0))
        for i in range(n):
            u = (x0 if cara in ("-z", "+z") else z0) + largo * (i + 0.5) / n
            ancho = min(3.6, largo / n - 1.2)
            fijo = {"-z": z0, "+z": z1, "-x": x0, "+x": x1}[cara]
            s = -1 if cara in ("-z", "-x") else 1
            est = rng.random()
            if cara in ("-z", "+z"):
                l.caja(u - ancho / 2, Y + 0.1, fijo - s * 0.15, u + ancho / 2, Y + 2.8, fijo + s * 0.03, "persiana" if est < 0.7 else "madera_podrida")
                if est > 0.9:
                    l.caja(u - ancho / 2, Y + 2.9, fijo - s * 0.1, u + ancho / 2, Y + 3.2, fijo + s * 0.08, rng.choice(("neon_rosa", "neon_azul", "ventana_luz")))
            else:
                l.caja(fijo - s * 0.15, Y + 0.1, u - ancho / 2, fijo + s * 0.03, Y + 2.8, u + ancho / 2, "persiana" if est < 0.7 else "madera_podrida")
                if est > 0.9:
                    l.caja(fijo - s * 0.1, Y + 2.9, u - ancho / 2, fijo + s * 0.08, Y + 3.2, u + ancho / 2, rng.choice(("neon_rosa", "neon_azul", "ventana_luz")))
    # azotea: deposito de agua sobre patas, maquinas de aire, chimeneas
    if rng.random() < 0.45 and (x1 - x0) > 8 and (z1 - z0) > 8:
        cx, cz = rng.uniform(x0 + 3, x1 - 3), rng.uniform(z0 + 3, z1 - 3)
        for dx, dz in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
            l.caja(cx + dx * 1.0 - 0.12, top - 0.3, cz + dz * 1.0 - 0.12, cx + dx * 1.0 + 0.12, top + 2.2, cz + dz * 1.0 + 0.12, "metal_negro")
        l.cilindro(cx, top + 2.0, cz, 1.4, 2.6, "madera_podrida")
        l.cilindro(cx, top + 4.6, cz, 1.5, 0.2, "metal_negro")
    for _ in range(rng.randint(0, 3)):
        ax, az = rng.uniform(x0 + 1.2, x1 - 2.4), rng.uniform(z0 + 1.2, z1 - 2.4)
        l.caja(ax, top - 0.3, az, ax + 1.2, top + 0.9, az + 0.9, "metal")
    if rng.random() < 0.3:
        cara = rng.choice(("-z", "+z"))
        fijo = z0 if cara == "-z" else z1
        u0 = rng.uniform(x0 + 1, max(x0 + 1.1, x1 - 5))
        escalera_incendios(l, cara, u0, u0 + 3.2, fijo, pisos, rng)


# ======================================================================================================
# INTERIORES: muebles
# ======================================================================================================
def cama(l, x, z, y, eje, rng, sangre=False):
    if eje == "x":
        l.caja(x, y, z, x + 2.0, y + 0.45, z + 1.4, "madera")
        l.caja(x + 0.05, y + 0.45, z + 0.05, x + 1.95, y + 0.6, z + 1.35, "tela_blanca" if not sangre else "sangre_seca")
        l.caja(x, y, z, x + 0.1, y + 1.0, z + 1.4, "madera")
    else:
        l.caja(x, y, z, x + 1.4, y + 0.45, z + 2.0, "madera")
        l.caja(x + 0.05, y + 0.45, z + 0.05, x + 1.35, y + 0.6, z + 1.95, "tela_blanca" if not sangre else "sangre_seca")
        l.caja(x, y, z, x + 1.4, y + 1.0, z + 0.1, "madera")


def sofa(l, x, z, y, eje, rng):
    mat = rng.choice(("lona", "lona_verde", "moqueta"))
    if eje == "x":
        l.caja(x, y, z, x + 2.2, y + 0.45, z + 0.9, mat)
        l.caja(x, y, z, x + 2.2, y + 0.9, z + 0.25, mat)
    else:
        l.caja(x, y, z, x + 0.9, y + 0.45, z + 2.2, mat)
        l.caja(x, y, z, x + 0.25, y + 0.9, z + 2.2, mat)


def mesa(l, x, z, y, w=1.2, d=0.8, mat="madera"):
    l.caja(x, y + 0.7, z, x + w, y + 0.78, z + d, mat)
    for dx, dz in ((0.05, 0.05), (w - 0.13, 0.05), (0.05, d - 0.13), (w - 0.13, d - 0.13)):
        l.caja(x + dx, y, z + dz, x + dx + 0.08, y + 0.7, z + dz + 0.08, mat)


def cocina(l, x0, z, x1, y, lado, rng):
    """encimera pegada a un muro (lado: el muro esta en -z o +z de `z`) y nevera"""
    s = 1 if lado == "-z" else -1
    l.caja(x0, y, z, x1, y + 0.9, z + s * 0.6, "revoco")
    l.caja(x0, y + 0.9, z, x1, y + 0.95, z + s * 0.62, "cornisa")
    l.caja(x1 - 0.7, y, z, x1, y + 1.9, z + s * 0.7, "chapa_blanca")


def tele(l, x, z, y, rng):
    l.caja(x, y, z, x + 1.2, y + 0.5, z + 0.45, "madera")
    l.caja(x + 0.1, y + 0.5, z + 0.1, x + 1.1, y + 1.1, z + 0.25, "metal_negro")
    if rng.random() < 0.3:
        l.caja(x + 0.15, y + 0.55, z + 0.09, x + 1.05, y + 1.05, z + 0.1, "ventana_fria")   # la tele encendida


def fuego(l, x, z, y, rng, grande=False):
    """fuego vivo: brasas emisivas y una luz naranja que alumbra la sala"""
    r = 0.9 if grande else 0.5
    l.elipsoide(x, y + 0.05, z, r * 1.4, 0.08, r * 1.2, "carbon")
    for _ in range(4 if grande else 2):
        l.elipsoide(x + rng.uniform(-r, r) * 0.5, y + 0.15, z + rng.uniform(-r, r) * 0.5, r * 0.4, 0.2, r * 0.35, "fuego")
    l.luz(x, y + 1.0, z, FUEGO, 1.3 if grande else 0.9, 9.0 if grande else 6.0)


# ======================================================================================================
# LOS APARTAMENTOS (la salida)
# ======================================================================================================
def apartamentos(l, rng):
    x0, z0, x1, z1 = D.APART
    pisos = D.APART_PISOS
    top = D.AZOTEA_APART_Y
    l.caja(x0, Y - 0.6, z0, x1, top, z1, "ladrillo_rojo")
    for k in range(pisos):
        yk = Y + k * P
        l.caja(x0 + MURO, yk, z0 + MURO, x1 - MURO, yk + P - LOSA, z1 - MURO, "ladrillo_rojo", hueco=True)
    # peto de la azotea y cornisa
    l.caja(x0 - 0.2, top - 0.4, z0 - 0.2, x1 + 0.2, top - 0.1, z1 + 0.2, "cornisa")
    l.caja(x0, top, z0, x1, top + 1.1, z1, "ladrillo_rojo")
    l.caja(x0 + 0.35, top, z0 + 0.35, x1 - 0.35, top + 1.1, z1 - 0.35, "ladrillo_rojo", hueco=True)
    # ventanas de todas las plantas (la este de abajo no: ahi esta el portal)
    fachada_ventanas(l, (x0, z0, x1, z1), pisos, rng, caras=("-z", "+z", "-x"))
    fachada_ventanas(l, (x0, 20.0, x1, z1), pisos, rng, caras=("+x",), desde=1)
    escalera_incendios(l, "+z", 13.0, 16.6, z1, pisos, rng)

    for k in range(pisos):
        yk = Y + k * P
        _planta_apartamentos(l, k, yk, rng)

    # PORTAL: puerta de la planta baja al callejon (fachada este), con su marquesina y la luz roja de salida
    sx, sz = D.APART_SALIDA
    l.caja(sx - MURO - 0.05, Y, sz - 1.0, sx + 0.05, Y + 2.7, sz + 1.0, "ladrillo_rojo", hueco=True)
    l.caja(sx - 0.05, Y + 2.8, sz - 1.4, sx + 1.2, Y + 2.95, sz + 1.4, "metal_negro")
    l.caja(sx - 0.3, Y + 2.95, sz - 1.4, sx + 0.05, Y + 3.2, sz + 1.4, "metal_negro")   # mordida al muro
    l.caja(sx + 0.02, Y + 2.3, sz - 0.3, sx + 0.08, Y + 2.5, sz + 0.3, "luz_roja")

    torre_escalera(l, D.APART_TORRE, pisos,
                   [(k, "-x") for k in range(pisos)] + [(pisos, "-x")], mat="ladrillo_rojo")
    _azotea_apartamentos(l, rng)


def _planta_apartamentos(l, k, yk, rng):
    """Una planta: pasillo este-oeste (z 17,6-20,8), rellano junto a la escalera (x 27,1-29,6) y seis pisos
    (tres al norte, tres al sur) mas el del sureste. En la baja el sureste es el portal."""
    x0, z0, x1, z1 = D.APART
    ax0, ax1 = x0 + MURO, 26.8
    zn0, zn1 = z0 + MURO, 17.3            # pisos del norte
    zs0, zs1 = 21.1, z1 - MURO            # pisos del sur
    h = P - LOSA
    suelo_mat = "moqueta" if k > 0 else "azulejo"
    # suelo del pasillo
    l.caja(ax0, yk - 0.05, 17.6, 29.6, yk, 20.8, suelo_mat)
    # muros del pasillo, con una puerta por piso
    cortes = [ax0, ax0 + (ax1 - ax0) / 3, ax0 + 2 * (ax1 - ax0) / 3, ax1]
    for zz0, zz1 in ((zn1, 17.6), (20.8, zs0)):
        l.caja(ax0, yk, zz0, ax1, yk + h, zz1, "papel_pintado")
        for i in range(3):
            u = (cortes[i] + cortes[i + 1]) / 2
            l.caja(u - 0.8, yk, zz0 - 0.05, u + 0.8, yk + 2.7, zz1 + 0.05, "papel_pintado", hueco=True)
    # tabiques entre pisos y contra el rellano
    for u in cortes[1:3]:
        l.caja(u - 0.15, yk, zn0, u + 0.15, yk + h, zn1, "papel_pintado")
        l.caja(u - 0.15, yk, zs0, u + 0.15, yk + h, zs1, "papel_pintado")
    l.caja(ax1, yk, zn0, ax1 + 0.3, yk + h, zn1, "papel_pintado")
    l.caja(ax1, yk, zs0, ax1 + 0.3, yk + h, zs1, "papel_pintado")
    # el piso del sureste (x 29,6-36, z 20-29,6): en la baja es el portal
    if k > 0:
        l.caja(29.6, yk, 20.0, 29.9, yk + h, zs1, "papel_pintado")
        l.caja(29.55, yk, 21.4, 29.95, yk + 2.7, 23.0, "papel_pintado", hueco=True)
    else:
        # portal: buzones, un carrito, la luz verde de emergencia
        l.caja(33.0, yk, 29.3, 35.8, yk + 1.6, zs1, "metal")
        for i in range(6):
            l.caja(33.1 + i * 0.45, yk + 0.9, 29.25, 33.45 + i * 0.45, yk + 1.5, 29.3, "metal_negro")
        l.caja(30.0, yk + 2.6, 20.4, 30.6, yk + 2.8, 20.5, "luz_verde")
        O.cadaver(l, 32.4, 24.2, yk, rng, "x")
        O.rastro_sangre(l, [(32.4, 24.2), (34.4, 25.0), (36.0, 24.2)], yk, rng)
    # los pisos: salon + dormitorio + cocina, con sus trastos
    pisos_rect = []
    for i in range(3):
        pisos_rect.append((cortes[i] + 0.15, zn0, cortes[i + 1] - 0.15, zn1, "+z"))
        pisos_rect.append((cortes[i] + 0.15, zs0, cortes[i + 1] - 0.15, zs1, "-z"))
    if k > 0:
        pisos_rect.append((29.9, 20.0, 36.0, zs1, "-x"))
    quemado = {(1, 0), (2, 3), (3, 1), (4, 4)}
    for n, (a0, b0, a1, b1, puerta) in enumerate(pisos_rect):
        _piso(l, k, n, yk, a0, b0, a1, b1, puerta, rng, (k, n) in quemado)
    # luz del pasillo: un fluorescente que aun va (emisivo) y una luz tenue; en alguna planta, apagado
    if rng.random() < 0.8:
        l.caja(18.0, yk + h - 0.08, 18.9, 21.0, yk + h, 19.5, "ventana_fria")
        l.luz(19.5, yk + h - 0.3, 19.2, FRIA, 0.45, 9.0)
    # sangre y cuerpos en el pasillo
    if rng.random() < 0.6:
        cx = rng.uniform(12, 26)
        l.charco_sangre(cx, rng.uniform(18.2, 20.2), yk, 0.7, rng)
    if rng.random() < 0.4:
        O.cadaver(l, rng.uniform(12, 25), 19.2, yk, rng, "x")


def _piso(l, k, n, yk, a0, b0, a1, b1, puerta, rng, quemado):
    """Un piso: tabique con puerta que separa dormitorio y salon-cocina."""
    h = P - LOSA
    w, d = a1 - a0, b1 - b0
    # tabique interior: parte el piso en dos a lo largo de x, con puerta de 1,4
    if w > 4.0:
        mx = a0 + w * 0.55
        l.caja(mx - 0.1, yk, b0, mx + 0.1, yk + h, b1, "papel_pintado")
        zc = (b0 + b1) / 2
        l.caja(mx - 0.15, yk, zc - 0.75, mx + 0.15, yk + 2.7, zc + 0.75, "papel_pintado", hueco=True)
    else:
        mx = a0 + w
    suelo = "madera" if rng.random() < 0.6 else "moqueta"
    l.caja(a0, yk - 0.05, b0, a1, yk, b1, suelo)
    # salon: sofa, tele, mesa
    sx = a0 + 0.3
    if puerta == "+z":           # el piso del norte: el pasillo esta al sur (b1)
        sofa(l, sx, b0 + 0.4, yk, "x", rng)
        tele(l, sx + 0.4, b1 - 1.4, yk, rng)
        cocina(l, mx - 2.4, b0 + 0.02, mx - 0.2, yk, "-z", rng) if mx - a0 > 3.0 else None
    elif puerta == "-z":
        sofa(l, sx, b1 - 1.3, yk, "x", rng)
        tele(l, sx + 0.4, b0 + 0.9, yk, rng)
        cocina(l, mx - 2.4, b1 - 0.02, mx - 0.2, yk, "+z", rng) if mx - a0 > 3.0 else None
    else:
        sofa(l, a0 + 0.4, b0 + 0.4, yk, "z", rng)
        mesa(l, a0 + 2.0, (b0 + b1) / 2, yk)
    if mx < a1 - 1.8:
        cama(l, mx + 0.3, b0 + 0.4, yk, "z", rng, sangre=rng.random() < 0.25)
    if rng.random() < 0.5:
        mesa(l, a0 + 0.8, (b0 + b1) / 2 - 0.4, yk)
    # lo que ha pasado aqui
    if quemado:
        l.caja(a0, yk - 0.05, b0, a1, yk + 0.0, b1, "carbon")
        for _ in range(3):
            l.elipsoide(rng.uniform(a0 + 0.5, a1 - 0.5), yk + h - 0.1, rng.uniform(b0 + 0.5, b1 - 0.5), 1.4, 0.15, 1.0, "carbon")
        fuego(l, rng.uniform(a0 + 1.0, a1 - 1.0), rng.uniform(b0 + 1.0, b1 - 1.0), yk, rng, grande=True)
    elif rng.random() < 0.35:
        l.charco_sangre(rng.uniform(a0 + 0.8, a1 - 0.8), rng.uniform(b0 + 0.8, b1 - 0.8), yk, 0.6, rng)
    if rng.random() < 0.25:
        O.cadaver(l, rng.uniform(a0 + 1.0, a1 - 2.0), rng.uniform(b0 + 1.0, b1 - 1.0), yk, rng, "x")
    # EL AGUJERO EN EL SUELO DE LA COCINA (segunda planta, piso del noroeste): se puede saltar a la primera
    if k == 2 and n == 0:
        l.caja(a0 + 1.0, yk - LOSA - 0.05, b0 + 1.0, a0 + 3.2, yk + 0.05, b0 + 3.0, "moqueta", hueco=True)
        for _ in range(8):
            ex, ez = rng.uniform(a0 + 0.8, a0 + 3.4), rng.uniform(b0 + 0.8, b0 + 3.2)
            l.caja(ex, yk - P, ez, ex + rng.uniform(0.2, 0.5), yk - P + rng.uniform(0.1, 0.3), ez + 0.3, "madera_podrida")
        l.luz(a0 + 2.1, yk - 1.0, b0 + 2.0, FUEGO, 0.6, 5.0)


def _azotea_apartamentos(l, rng):
    """La salida: la mesa de provisiones, el deposito de agua, las maquinas de aire, una antena, una tienda de
    campaña de quien aguanto aqui arriba, y la vista del hospital a lo lejos."""
    top = D.AZOTEA_APART_Y
    # mesa de provisiones junto a la salida del jugador
    mesa(l, 14.2, 11.4, top, 2.4, 1.0, "madera")
    l.caja(14.4, top + 0.78, 11.5, 15.4, top + 1.0, 12.2, "metal_negro")     # un maletin de armas
    l.caja(15.6, top + 0.78, 11.5, 16.3, top + 1.05, 12.1, "tela_blanca")    # botiquin
    l.caja(15.72, top + 0.84, 11.49, 16.18, top + 0.98, 11.5, "plastico_rojo")
    O.sacos(l, 11.2, 20.0, 15.2, 20.8, top, 1.0, rng)
    O.barril(l, 12.0, 24.0, top, "metal_oxidado", None, rng)
    fuego(l, 12.0, 24.0, top + 1.0, rng)                                   # hoguera dentro del bidon
    # tienda de campaña
    l.caja(20.0, top, 23.0, 23.6, top + 0.05, 26.0, "lona_verde")
    l.cuna(20.0, top, 23.0, 21.8, top + 1.6, 26.0, "+x", "lona_verde")
    l.cuna(21.8, top, 23.0, 23.6, top + 1.6, 26.0, "-x", "lona_verde")
    # deposito de agua y maquinas de aire
    cx, cz = 24.0, 13.0
    for dx, dz in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        l.caja(cx + dx * 1.1 - 0.12, top, cz + dz * 1.1 - 0.12, cx + dx * 1.1 + 0.12, top + 2.4, cz + dz * 1.1 + 0.12, "metal_negro")
    l.cilindro(cx, top + 2.2, cz, 1.5, 2.8, "madera_podrida")
    l.cilindro(cx, top + 5.0, cz, 1.6, 0.25, "metal_negro")
    for ax, az in ((13.0, 27.0), (16.0, 27.0), (26.0, 27.0)):
        l.caja(ax, top, az, ax + 1.6, top + 1.2, az + 1.2, "metal")
        l.cilindro(ax + 0.8, top + 1.2, az + 0.6, 0.45, 0.05, "metal_negro")
    # antena con su luz roja
    l.cilindro(11.2, top, 12.0, 0.1, 6.0, "metal_negro")
    l.caja(11.1, top + 6.0, 11.9, 11.3, top + 6.2, 12.1, "luz_roja")
    l.luz(11.2, top + 6.3, 12.0, ROJA, 0.7, 6.0)
    # tendedero y una luz calida de faroles colgados
    for px in (17.9, 26.1):
        l.caja(px - 0.06, top, 15.94, px + 0.06, top + 2.0, 16.26, "metal_negro")    # postes del tendedero
    l.linea(17.9, top + 1.9, 16.1, 26.1, top + 1.9, 16.1, 0.06, "metal_negro")
    for i in range(4):
        l.caja(18.8 + i * 1.8, top + 1.0, 16.0, 19.6 + i * 1.8, top + 1.9, 16.1, rng.choice(("tela_blanca", "lona", "plastico_rojo")))
    l.luz(17.0, top + 2.4, 14.0, CALIDA, 0.9, 12.0)
    l.punto(*D.SPAWN_JUGADOR, "jugador")


# ======================================================================================================
# CALLEJON, TIENDAS Y CALLE OLMO
# ======================================================================================================
def callejon(l, rng):
    """Callejon estrecho de los apartamentos a la calle: contenedores, cajas, basura, un coche aplastado, la
    luz de una puerta trasera y la escalera de incendios del edificio de al lado."""
    for (x, z) in ((40.0, 22.2), (47.0, 27.6), (54.0, 22.2)):
        l.caja(x, Y, z - 0.6, x + 2.0, Y + 1.3, z + 0.6, "chapa_verde")      # contenedor
        l.caja(x - 0.05, Y + 1.3, z - 0.65, x + 2.05, Y + 1.4, z + 0.65, "metal_negro")
    for _ in range(18):
        bx, bz = rng.uniform(37.0, 59.0), rng.uniform(22.0, 28.0)
        l.elipsoide(bx, Y + 0.2, bz, 0.35, 0.25, 0.3, rng.choice(("plastico_negro", "lona", "plastico_negro")))
    O.caja_madera(l, 44.0, 22.4, Y, 1.0, 0.8)
    O.caja_madera(l, 44.2, 22.4, Y + 0.8, 0.8, 0.6)
    O.palet(l, 50.0, 27.8, Y, "x")
    O.cadaver(l, 49.0, 24.6, Y, rng, "z")
    O.rastro_sangre(l, [(49.0, 24.6), (52.0, 25.2), (56.0, 26.0), (56.6, 30.0)], Y, rng)
    # puerta trasera con su bombilla (en el bloque norte del callejon)
    l.caja(45.0, Y, 21.3, 46.4, Y + 2.4, 21.62, "metal_rojo")
    l.caja(45.5, Y + 2.6, 21.3, 45.9, Y + 2.8, 21.75, "ventana_luz")
    l.luz(45.7, Y + 2.9, 22.2, CALIDA, 0.8, 8.0)
    l.luz(57.0, Y + 4.0, 30.0, CALIDA, 0.6, 9.0)
    escalera_incendios(l, "-z", 40.0, 43.6, 28.4, 4, rng)


def tienda(l, rect, nombre, rng, puerta_z, neon="neon_azul"):
    """Local de planta baja que se cruza por dentro: puerta a la calle (fachada sur, en `puerta_z`),
    mostrador, estanterias con botellas o cajas de farmacia y el cartel de neon. Encima, dos plantas."""
    x0, z0, x1, z1 = rect
    pisos = 3
    top = Y + pisos * P
    l.caja(x0, Y - 0.6, z0, x1, top, z1, "ladrillo_gris" if nombre == "farmacia" else "ladrillo_oscuro")
    l.caja(x0 + MURO, Y, z0 + MURO, x1 - MURO, Y + P - LOSA, z1 - MURO, "ladrillo", hueco=True)
    l.caja(x0 + MURO, Y + P, z0 + MURO, x1 - MURO, top - 0.4, z1 - MURO, "ladrillo", hueco=True)
    l.caja(x0 + MURO, Y - 0.05, z0 + MURO, x1 - MURO, Y, z1 - MURO, "azulejo")
    fachada_ventanas(l, rect, pisos, rng, desde=1)
    l.caja(x0, top, z0, x1, top + 0.9, z1, "ladrillo_oscuro")
    l.caja(x0 + 0.3, top, z0 + 0.3, x1 - 0.3, top + 0.9, z1 - 0.3, "ladrillo_oscuro", hueco=True)
    # escaparate y puerta (2,4 de ancho)
    cx = (x0 + x1) / 2
    l.caja(x0 + 1.2, Y + 0.9, puerta_z - MURO - 0.05, x1 - 1.2, Y + 2.6, puerta_z + 0.05, "ladrillo", hueco=True)
    l.caja(x0 + 1.2, Y + 0.9, puerta_z - 0.14, cx - 1.6, Y + 2.6, puerta_z - 0.04, "vidrio")
    l.caja(cx - 1.2, Y, puerta_z - MURO - 0.05, cx + 1.2, Y + 2.7, puerta_z + 0.05, "ladrillo", hueco=True)
    # toldo y rotulo de neon
    l.caja(x0 + 0.6, Y + 3.0, puerta_z - 0.3, x1 - 0.6, Y + 3.15, puerta_z + 1.4, "plastico_rojo" if nombre == "licoreria" else "lona_verde")
    l.caja(x0 + 1.5, Y + 3.25, puerta_z - 0.2, x1 - 1.5, Y + 3.7, puerta_z + 0.08, neon)
    l.luz(cx, Y + 3.3, puerta_z + 1.2, (60, 140, 255) if neon == "neon_azul" else (255, 60, 150), 1.0, 9.0)
    # dentro: mostrador y estanterias
    l.caja(x0 + 1.0, Y, z1 - 3.0, x0 + 1.8, Y + 1.0, z1 - 1.0, "madera")
    l.caja(x0 + 1.0, Y + 1.0, z1 - 3.05, x0 + 1.85, Y + 1.06, z1 - 0.95, "cornisa")
    for i in range(3):
        ex = x0 + 3.5 + i * 2.6
        if ex > x1 - 2.0:
            break
        l.caja(ex, Y, z0 + 1.5, ex + 0.6, Y + 1.9, z1 - 4.0, "metal")
        for j in range(4):
            yb = Y + 0.3 + j * 0.45
            for q in range(int((z1 - 4.0 - z0 - 1.5) / 0.4)):
                if rng.random() < 0.55:
                    mat = rng.choice(("vidrio", "plastico_rojo", "chapa_verde", "tela_blanca")) if nombre == "licoreria" else rng.choice(("tela_blanca", "tela_blanca", "plastico_amarillo", "plastico_rojo"))
                    l.caja(ex - 0.12, yb, z0 + 1.6 + q * 0.4, ex + 0.02, yb + 0.3, z0 + 1.85 + q * 0.4, mat)
    # saqueo: cristales y cajas por el suelo
    for _ in range(10):
        gx, gz = rng.uniform(x0 + 1, x1 - 1), rng.uniform(z0 + 1, z1 - 1)
        l.caja(gx, Y, gz, gx + 0.12, Y + 0.04, gz + 0.12, "vidrio")
    O.caja_madera(l, x1 - 2.0, z0 + 1.2, Y, 0.8, 0.6, "tela_blanca" if nombre == "farmacia" else "madera")
    l.caja(cx - 1.0, Y + P - LOSA - 0.08, (z0 + z1) / 2 - 0.4, cx + 1.0, Y + P - LOSA, (z0 + z1) / 2 + 0.4, "ventana_fria")
    l.luz(cx, Y + 2.4, (z0 + z1) / 2, FRIA, 0.5, 10.0)
    l.punto(cx, Y, (z0 + z1) / 2, "botin")


def calle_olmo(l, rng):
    """La calle de los coches abandonados. Uno lleva la ALARMA (el juego lo sabe por el .campana.json): no le
    dispares. Un autobus cruzado deja paso por un lado, una barricada de la policia a medio montar, fuego."""
    z0, z1 = D.CALLE_A[1], D.CALLE_A[3]
    zc = (z0 + z1) / 2
    O.coche(l, 66.0, z0 + 3.0, Y, "x", 1, rng, "quemado")
    O.coche(l, 74.0, z1 - 3.4, Y, "x", -1, rng, "abandonado", "chapa_azul")
    O.coche(l, 83.0, zc + 1.4, Y, "x", 1, rng, "volcado")
    fuego(l, 85.0, zc + 1.4, Y, rng, grande=True)
    # el coche con alarma: rojo, limpio, con las luces de emergencia (el juego pone la alarma en este punto)
    O.coche(l, 96.0, z0 + 3.2, Y, "x", 1, rng, "abandonado", "chapa_roja")
    l.caja(96.3, Y + 0.6, z0 + 2.2, 96.5, Y + 0.75, z0 + 2.5, "luz_calida")
    O.coche(l, 105.0, z1 - 3.0, Y, "x", -1, rng, "quemado")
    # autobus cruzado: deja 4 m por el norte
    bx0, bx1 = 112.0, 114.8
    l.caja(bx0, Y + 0.4, zc - 2.0, bx1, Y + 3.2, z1 - 0.2, "chapa_blanca")
    l.caja(bx0 - 0.02, Y + 1.6, zc - 1.5, bx1 + 0.02, Y + 2.5, z1 - 0.8, "vidrio")
    for zz in (zc - 1.0, z1 - 1.4):
        for xx in (bx0 + 0.1, bx1 - 0.4):
            l.caja(xx, Y, zz - 0.5, xx + 0.3, Y + 0.9, zz + 0.5, "goma")
    O.coche(l, 128.0, z0 + 3.2, Y, "x", 1, rng, "quemado")
    O.coche(l, 138.0, zc + 2.0, Y, "x", -1, rng, "abandonado", "chapa_blanca")
    # barricada de la policia junto a la boca del metro
    for zz in (z0 + 2.6, z0 + 5.0):
        O.jersey(l, 146.0, zz, Y, 2.0, "z", rng)
    O.sacos(l, 148.0, z1 - 4.0, 151.2, z1 - 3.4, Y, 1.1, rng)
    fuego(l, 142.0, zc - 3.0, Y, rng)
    for _ in range(4):
        O.cadaver(l, rng.uniform(62, 140), rng.uniform(z0 + 3, z1 - 3), Y, rng, "x")
    for _ in range(6):
        cx = rng.uniform(62, 150)
        l.charco_sangre(cx, rng.uniform(z0 + 2, z1 - 2), Y, 0.8, rng)
    # cartel del metro en la esquina
    l.caja(166.0, Y, 49.2, 166.3, Y + 3.2, 49.5, "metal_negro")
    l.caja(165.2, Y + 3.2, 49.1, 167.2, Y + 4.0, 49.6, "neon_azul")


# ======================================================================================================
# EL REFUGIO (boca del metro)
# ======================================================================================================
def refugio(l, rng):
    """Sala de la boca del metro convertida en refugio: dos puertas rojas (entrada al norte, salida al sur, las
    hojas las pone el juego), camastros, estanteria con municion, botiquin de pared, pintadas y luz roja."""
    x0, z0, x1, z1 = D.REFUGIO
    top = Y + 4.0
    l.caja(x0, Y - 0.6, z0, x1, top + 0.4, z1, "hormigon_sucio")
    l.caja(x0 + MURO, Y, z0 + MURO, x1 - MURO, top, z1 - MURO, "azulejo", hueco=True)
    l.caja(x0 + MURO, Y - 0.05, z0 + MURO, x1 - MURO, Y, z1 - MURO, "azulejo")
    # alicatado de las paredes (franja) y marco de las puertas pintado de rojo
    l.caja(x0 + MURO, Y + 1.2, z0 + MURO, x0 + MURO + 0.02, Y + 1.5, z1 - MURO, "azulejo")
    for (px, pz) in (D.REFUGIO_PUERTA_N, D.REFUGIO_PUERTA_S):
        l.caja(px - 0.9, Y, pz - MURO - 0.05, px + 0.9, Y + 2.7, pz + MURO + 0.05, "hormigon_sucio", hueco=True)
        s = 1 if pz < (z0 + z1) / 2 else -1
        l.caja(px - 1.15, Y, pz - 0.25 * s - 0.2, px - 0.9, Y + 2.95, pz + 0.25 * s + 0.2, "metal_rojo")
        l.caja(px + 0.9, Y, pz - 0.25 * s - 0.2, px + 1.15, Y + 2.95, pz + 0.25 * s + 0.2, "metal_rojo")
        l.caja(px - 1.15, Y + 2.7, pz - 0.45, px + 1.15, Y + 2.95, pz + 0.45, "metal_rojo")
        l.caja(px - 0.25, Y + 3.0, pz - 0.5 * s, px + 0.25, Y + 3.25, pz - 0.45 * s, "luz_roja")
    # camastros, mesa con municion, taquillas, botiquin
    for i in range(3):
        cama(l, x0 + 1.0, z0 + 1.2 + i * 3.4, Y, "x", rng)
    mesa(l, x1 - 3.4, (z0 + z1) / 2 - 0.6, Y, 2.4, 1.2, "metal")
    for i in range(5):
        l.caja(x1 - 3.2 + i * 0.45, Y + 0.78, (z0 + z1) / 2 - 0.4, x1 - 2.85 + i * 0.45, Y + 1.05, (z0 + z1) / 2, "chapa_verde")
    for i in range(4):
        l.caja(x1 - MURO - 0.6, Y, z0 + 1.0 + i * 0.7, x1 - MURO, Y + 2.0, z0 + 1.62 + i * 0.7, "metal")
    l.caja(x0 + MURO, Y + 1.3, z1 - 4.0, x0 + MURO + 0.2, Y + 2.0, z1 - 3.2, "tela_blanca")
    l.caja(x0 + MURO + 0.18, Y + 1.5, z1 - 3.75, x0 + MURO + 0.22, Y + 1.8, z1 - 3.45, "plastico_rojo")
    # pintadas de los que pasaron antes (manchas de pintura en los muros)
    for _ in range(9):
        pz = rng.uniform(z0 + 1.0, z1 - 1.0)
        py = rng.uniform(Y + 1.0, Y + 2.8)
        l.caja(x1 - MURO - 0.02, py, pz, x1 - MURO + 0.0, py + rng.uniform(0.1, 0.4), pz + rng.uniform(0.6, 1.8),
               rng.choice(("pintura_roja", "pintura_blanca", "pintura_amarilla")))
    l.luz((x0 + x1) / 2, top - 0.6, (z0 + z1) / 2, ROJA, 1.0, 14.0)
    l.luz((x0 + x1) / 2, top - 0.6, z0 + 2.0, CALIDA, 0.6, 9.0)
    l.punto((x0 + x1) / 2, Y, (z0 + z1) / 2, "refugio")


# ======================================================================================================
# CALLE SEGUNDA: el control militar y el PORTON (el evento)
# ======================================================================================================
def calle_segunda(l, rng):
    z0, z1 = D.CALLE_B[1], D.CALLE_B[3]
    zc = (z0 + z1) / 2
    # salida del refugio: coche de policia y cinta
    O.coche(l, 164.0, z0 + 4.0, Y, "z", 1, rng, "abandonado", "chapa_blanca")
    l.caja(164.2, Y + 1.4, z0 + 5.0, 165.6, Y + 1.55, z0 + 5.3, "luz_roja")
    # camion volcado cortando media calle
    O.camion(l, 146.0, z1 - 3.4, Y, "x", -1, rng, "quemado")
    fuego(l, 140.0, z1 - 3.4, Y, rng, grande=True)
    # CONTROL MILITAR a medio desmontar: sacos, barreras, un jeep, una tienda, focos
    for zz in (z0 + 3.0, z1 - 5.0):
        O.sacos(l, 118.0, zz, 121.2, zz + 0.7, Y, 1.2, rng)
    O.jersey(l, 124.0, zc - 1.0, Y, 2.0, "z", rng)
    O.jeep(l, 128.0, z0 + 3.0, Y, "x", 1, rng, "abandonado")
    l.caja(106.0, Y, z1 - 5.4, 111.0, Y + 0.05, z1 - 2.6, "lona_verde")
    l.cuna(106.0, Y, z1 - 5.4, 111.0, Y + 2.4, z1 - 4.0, "+z", "lona_verde")
    l.cuna(106.0, Y, z1 - 4.0, 111.0, Y + 2.4, z1 - 2.6, "-z", "lona_verde")
    for zz in (z0 + 1.0, z1 - 1.0):
        l.cilindro(116.0, Y, zz, 0.1, 4.0, "metal_negro")
        l.caja(115.7, Y + 4.0, zz - 0.3, 116.3, Y + 4.4, zz + 0.3, "metal_negro")
        l.luz(116.0, Y + 3.8, zz, (220, 230, 255), 1.2, 16.0, (0.0, -0.6, 0.8 if zz < zc else -0.8), 28.0)
    O.cinta(l, [(117.0, z0 + 0.5), (117.0, z1 - 0.5)], Y, rng)
    for _ in range(5):
        O.bolsa_cadaver(l, rng.uniform(96, 104), rng.uniform(z0 + 3, z1 - 3), Y, "x", rng)
    O.coche(l, 90.0, z0 + 3.4, Y, "x", -1, rng, "quemado")
    O.coche(l, 76.0, z1 - 3.4, Y, "x", -1, rng, "volcado")
    # EL PORTON: dos pilares de hormigon a los lados (la hoja la pone el juego) y el cuadro de mando en la
    # fachada norte, con su luz roja. Antes del porton, la valla de obra y los focos que lo alumbran.
    px0, _pz0, px1, _pz1 = D.PORTON
    for zz0, zz1 in ((z0 - 0.4, z0 + 0.6), (z1 - 0.6, z1 + 0.4)):
        l.caja(px0 - 0.4, Y, zz0, px1 + 0.4, Y + 5.6, zz1, "hormigon")
    l.caja(px0 - 0.4, Y + 5.6, z0 - 0.4, px1 + 0.4, Y + 6.2, z1 + 0.4, "metal_negro")   # dintel del porton
    bx, _by, bz = D.PORTON_BOTON
    l.caja(bx - 0.6, Y + 0.9, z0 - 0.4, bx + 0.6, Y + 2.1, z0 + 0.25, "chapa_verde")
    l.caja(bx - 0.2, Y + 1.5, z0 + 0.25, bx + 0.2, Y + 1.7, z0 + 0.32, "luz_roja")
    l.luz(bx, Y + 2.4, z0 + 1.0, ROJA, 0.8, 7.0)
    for zz in (z0 + 1.2, z1 - 1.2):
        l.luz(px1 + 3.0, Y + 5.0, zz, CALIDA, 1.0, 12.0, (-0.6, -0.8, 0.0), 30.0)
    # detras del porton: mas coches y un fuego (lo que hay que cruzar despues del evento)
    O.coche(l, 50.0, z0 + 3.2, Y, "x", -1, rng, "quemado")
    O.coche(l, 38.0, zc, Y, "x", 1, rng, "volcado")
    fuego(l, 42.0, zc + 3.0, Y, rng, grande=True)
    for _ in range(5):
        l.charco_sangre(rng.uniform(26, 150), rng.uniform(z0 + 2, z1 - 2), Y, 0.9, rng)


# ======================================================================================================
# ESQUINA OESTE Y AVENIDA DEL HOSPITAL
# ======================================================================================================
def esquina_y_avenida(l, rng):
    # la esquina oeste es un parquecillo arrasado: tierra, arboles muertos, un banco, una fuente seca
    l.caja(10.0, Y - 0.2, 86.0, 22.8, Y, 108.0, "suelo_barro")
    for (x, z) in ((12.0, 90.0), (20.0, 95.0), (13.0, 102.0), (21.0, 106.0)):
        O.arbol_muerto(l, x, z, Y, rng.uniform(4.5, 6.5), rng, quemado=rng.random() < 0.4)
    l.cilindro(16.4, Y, 99.0, 1.6, 0.6, "cornisa")
    l.cilindro(16.4, Y + 0.2, 99.0, 1.3, 0.45, "cornisa", hueco=True)
    O.cadaver(l, 15.0, 96.0, Y, rng, "z")
    # avenida: ambulancia, coches, un autobus escolar quemado, barricada de la guardia
    z0, z1 = D.CALLE_C[1], D.CALLE_C[3]
    zc = (z0 + z1) / 2
    O.coche(l, 30.0, z0 + 3.0, Y, "x", 1, rng, "quemado")
    O.coche(l, 46.0, z1 - 3.2, Y, "x", -1, rng, "abandonado", "chapa_azul")
    l.caja(56.0, Y + 0.4, zc - 1.6, 66.0, Y + 3.0, zc + 1.2, "plastico_amarillo")   # autobus escolar
    l.caja(55.98, Y + 1.6, zc - 1.3, 66.02, Y + 2.4, zc + 0.9, "vidrio", hueco=True)
    l.caja(56.0, Y + 0.4, zc - 1.6, 66.0, Y + 1.0, zc + 1.2, "carbon")
    for xx in (57.0, 64.0):
        for zz in (zc - 1.4, zc + 0.8):
            l.caja(xx - 0.5, Y, zz - 0.15, xx + 0.5, Y + 0.9, zz + 0.25, "goma")
    fuego(l, 61.0, zc - 0.2, Y + 0.4, rng, grande=True)
    O.coche(l, 76.0, z0 + 3.4, Y, "x", 1, rng, "volcado")
    for zz in (z0 + 2.4, z1 - 4.8):
        O.sacos(l, 86.0, zz, 86.8, zz + 2.4, Y, 1.2, rng)
    for _ in range(4):
        O.cadaver(l, rng.uniform(26, 88), rng.uniform(z0 + 3, z1 - 3), Y, rng, "x")


# ======================================================================================================
# LA PLAZA Y EL HOSPITAL (el final)
# ======================================================================================================
def plaza(l, rng):
    x0, z0, x1, z1 = D.PLAZA
    l.caja(x0, Y - 0.2, z0, x1, Y, z1, "suelo_hormigon")
    # ambulancias y el puesto medico de campaña abandonado
    for (x, z, s) in ((96.0, 106.0, 1), (100.0, 150.0, -1)):
        O.coche(l, x, z, Y, "z", s, rng, "abandonado", "chapa_blanca")
        l.caja(x - 0.3, Y + 1.45, z + (0.6 if s > 0 else -0.9), x + 0.3, Y + 1.6, z + (0.9 if s > 0 else -0.6), "luz_roja")
    for (tx, tz) in ((95.0, 128.0), (95.0, 142.0)):
        l.caja(tx, Y, tz, tx + 5.0, Y + 0.05, tz + 5.0, "tela_blanca")
        l.cuna(tx, Y, tz, tx + 2.5, Y + 2.6, tz + 5.0, "+x", "tela_blanca")
        l.cuna(tx + 2.5, Y, tz, tx + 5.0, Y + 2.6, tz + 5.0, "-x", "tela_blanca")
        l.caja(tx + 2.3, Y + 2.2, tz - 0.02, tx + 2.7, Y + 2.6, tz + 0.0, "plastico_rojo")
    for i in range(6):
        O.bolsa_cadaver(l, 104.0 + (i % 3) * 1.2, 146.0 + (i // 3) * 2.6, Y, "z", rng)
    O.jersey(l, 108.0, 112.0, Y, 2.0, "x", rng)
    O.sacos(l, 110.0, 156.0, 114.0, 156.8, Y, 1.2, rng)
    l.charco_sangre(106.0, 130.0, Y, 1.4, rng)
    fuego(l, 104.0, 118.0, Y, rng)


def hospital(l, rng):
    """El hospital: 6 plantas, fachada de hormigon con franjas de ladrillo, urgencias al oeste con marquesina
    y cartel rojo, vestibulo con mostrador y camillas, y la caja de escalera que sube a la azotea."""
    x0, z0, x1, z1 = D.HOSPITAL
    pisos = D.HOSPITAL_PISOS
    top = D.AZOTEA_HOSP_Y
    l.caja(x0, Y - 0.6, z0, x1, top, z1, "revoco")
    # por dentro: la planta baja entera y las de arriba huecas con sus forjados (se ven por las ventanas)
    for k in range(pisos):
        yk = Y + k * P
        l.caja(x0 + MURO, yk, z0 + MURO, x1 - MURO, yk + P - LOSA, z1 - MURO, "revoco", hueco=True)
    # pilares cada 8 m: el forjado de 50 m no vuela solo
    for px in range(int(x0) + 8, int(x1) - 2, 8):
        for pz in range(int(z0) + 8, int(z1) - 2, 8):
            if D.dentro(px, pz, (x0, 118.0, x0 + 12.0, 146.0)):
                continue            # el vestibulo y la escalera quedan libres
            l.caja(px - 0.35, Y, pz - 0.35, px + 0.35, top - LOSA, pz + 0.35, "hormigon_sucio")
    # franjas de ladrillo entre plantas y ventanas corridas
    for k in range(1, pisos):
        yk = Y + k * P
        l.caja(x0 - 0.1, yk - 0.35, z0 - 0.1, x1 + 0.1, yk + 0.25, z1 + 0.1, "ladrillo_rojo")
    fachada_ventanas(l, D.HOSPITAL, pisos, rng, desde=1, paso=2.2)
    # peto y cornisa
    l.caja(x0 - 0.3, top - 0.5, z0 - 0.3, x1 + 0.3, top - 0.1, z1 + 0.3, "cornisa")
    l.caja(x0, top, z0, x1, top + 1.1, z1, "revoco")
    l.caja(x0 + 0.35, top, z0 + 0.35, x1 - 0.35, top + 1.1, z1 - 0.35, "revoco", hueco=True)
    # URGENCIAS: dos puertas grandes en la fachada oeste, marquesina y cartel rojo
    ex, ez = D.HOSPITAL_ENTRADA
    l.caja(ex - 0.05, Y, ez - 2.4, ex + MURO + 0.05, Y + 3.0, ez + 2.4, "revoco", hueco=True)
    l.caja(ex - 5.0, Y + 3.4, ez - 4.0, ex + 0.3, Y + 3.7, ez + 4.0, "hormigon")
    for zz in (ez - 3.6, ez + 3.6):
        l.caja(ex - 4.8, Y, zz - 0.2, ex - 4.4, Y + 3.4, zz + 0.2, "hormigon")
    l.caja(ex - 5.02, Y + 3.7, ez - 3.0, ex - 4.9, Y + 4.4, ez + 3.0, "luz_roja")
    l.luz(ex - 3.0, Y + 3.2, ez, (255, 60, 50), 1.1, 12.0, (0.0, -1.0, 0.0), 45.0)
    # la cruz roja en lo alto de la fachada oeste (se ve desde la azotea de los apartamentos)
    cy, cz = top - 3.0, (z0 + z1) / 2
    l.caja(x0 - 0.15, cy - 1.8, cz - 0.6, x0 + 0.05, cy + 1.8, cz + 0.6, "luz_roja")
    l.caja(x0 - 0.15, cy - 0.6, cz - 1.8, x0 + 0.05, cy + 0.6, cz + 1.8, "luz_roja")
    # VESTIBULO: mostrador, sillas, camillas, sangre, fluorescentes
    vx0, vz0 = x0 + MURO, 118.0
    l.caja(vx0, Y - 0.05, vz0, x0 + 30.0, Y, 158.0, "azulejo")
    l.caja(x0 + 9.0, Y, 140.0, x0 + 9.8, Y + 1.1, 146.0, "madera")
    l.caja(x0 + 9.0, Y + 1.1, 139.9, x0 + 9.9, Y + 1.16, 146.1, "cornisa")
    for i in range(6):
        l.caja(x0 + 4.0 + i * 1.0, Y, 150.0, x0 + 4.6 + i * 1.0, Y + 0.45, 150.6, "chapa_verde")
        l.caja(x0 + 4.0 + i * 1.0, Y, 150.5, x0 + 4.6 + i * 1.0, Y + 0.9, 150.6, "chapa_verde")
    for (cx, cz) in ((x0 + 14.0, 132.0), (x0 + 18.0, 144.0), (x0 + 22.0, 128.0)):
        l.caja(cx, Y, cz, cx + 2.0, Y + 0.8, cz + 0.8, "tela_blanca")
        l.caja(cx, Y, cz, cx + 0.1, Y + 0.8, cz + 0.1, "metal")
        l.charco_sangre(cx + 1.0, cz + 1.4, Y, 0.6, rng)
    for i in range(4):
        fx = x0 + 6.0 + i * 6.0
        l.caja(fx, Y + P - LOSA - 0.08, 136.0, fx + 2.0, Y + P - LOSA, 136.6, "ventana_fria")
    l.luz(x0 + 10.0, Y + 2.6, 138.0, FRIA, 0.6, 14.0)
    l.luz(x0 + 22.0, Y + 2.6, 134.0, FRIA, 0.4, 12.0)
    O.cadaver(l, x0 + 12.0, 138.0, Y, rng, "x")
    O.rastro_sangre(l, [(x0 + 12.0, 138.0), (x0 + 8.0, 132.0), (x0 + 7.4, 126.0)], Y, rng)
    # la escalera: puerta al vestibulo (planta baja) y a la azotea (arriba)
    torre_escalera(l, D.HOSPITAL_TORRE, pisos, [(0, "+x"), (pisos, "+x")], mat="hormigon_sucio")
    _azotea_hospital(l, rng)


def _azotea_hospital(l, rng):
    """El final: la caseta de la radio, maquinas de aire (cobertura), el deposito, la ametralladora fija de
    atrezo, un nivel mas bajo alrededor del helipuerto y el HELIPUERTO elevado con su H y sus balizas."""
    top = D.AZOTEA_HOSP_Y
    x0, z0, x1, z1 = D.HOSPITAL
    # caseta de la radio (se entra por el oeste)
    rx, _ry, rz = D.RADIO
    l.caja(rx - 2.4, top, rz - 2.0, rx + 2.4, top + 3.0, rz + 2.0, "revoco")
    l.caja(rx - 2.0, top, rz - 1.6, rx + 2.0, top + 2.7, rz + 1.6, "revoco", hueco=True)
    l.caja(rx - 2.45, top, rz - 0.8, rx - 1.95, top + 2.6, rz + 0.8, "revoco", hueco=True)
    mesa(l, rx + 0.4, rz - 1.4, top, 1.4, 0.8, "metal")
    l.caja(rx + 0.6, top + 0.78, rz - 1.35, rx + 1.4, top + 1.2, rz - 0.95, "metal_negro")    # la radio
    l.caja(rx + 0.7, top + 0.95, rz - 0.96, rx + 1.0, top + 1.05, rz - 0.94, "luz_verde")
    l.luz(rx, top + 2.4, rz, CALIDA, 0.8, 7.0)
    # cobertura: maquinas de aire, conductos y el deposito
    for (ax, az) in ((126.0, 110.0), (132.0, 112.0), (126.0, 150.0), (136.0, 152.0), (144.0, 110.0), (146.0, 150.0)):
        l.caja(ax, top, az, ax + 2.6, top + 1.6, az + 1.8, "metal")
        l.cilindro(ax + 1.3, top + 1.6, az + 0.9, 0.6, 0.08, "metal_negro")
    l.caja(128.0, top, 120.0, 142.0, top + 0.8, 120.8, "metal")
    l.caja(128.0, top, 144.0, 142.0, top + 0.8, 144.8, "metal")
    cx, cz = 124.0, 150.0
    for dx, dz in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        l.caja(cx + dx * 1.2 - 0.12, top, cz + dz * 1.2 - 0.12, cx + dx * 1.2 + 0.12, top + 2.6, cz + dz * 1.2 + 0.12, "metal_negro")
    l.cilindro(cx, top + 2.4, cz, 1.7, 3.0, "metal")
    # ametralladora fija de atrezo tras sacos, mirando a la escalera
    O.sacos(l, 138.0, 124.0, 140.4, 124.8, top, 1.0, rng)
    l.cilindro(139.2, top + 1.0, 124.4, 0.12, 0.5, "metal_negro")
    l.linea(139.2, top + 1.4, 124.4, 139.2, top + 1.5, 122.6, 0.12, "metal_negro")
    # HELIPUERTO: plataforma elevada 0,6 m con rampa, circulo y H, balizas
    hx, hy, hz = D.HELIPUERTO
    l.caja(hx - 9.0, top, hz - 9.0, hx + 9.0, hy, hz + 9.0, "helipuerto")
    l.cuna(hx - 12.0, top, hz - 3.0, hx - 9.0, hy, hz + 3.0, "+x", "helipuerto")
    for i in range(32):
        a = i / 32 * math.tau
        px, pz = hx + math.cos(a) * 6.5, hz + math.sin(a) * 6.5
        l.caja(px - 0.35, hy - 0.02, pz - 0.35, px + 0.35, hy + 0.0, pz + 0.35, "pintura_amarilla")
    l.caja(hx - 2.4, hy - 0.02, hz - 3.0, hx - 1.6, hy + 0.0, hz + 3.0, "pintura_blanca")
    l.caja(hx + 1.6, hy - 0.02, hz - 3.0, hx + 2.4, hy + 0.0, hz + 3.0, "pintura_blanca")
    l.caja(hx - 1.6, hy - 0.02, hz - 0.4, hx + 1.6, hy + 0.0, hz + 0.4, "pintura_blanca")
    for i in range(8):
        a = i / 8 * math.tau
        px, pz = hx + math.cos(a) * 8.6, hz + math.sin(a) * 8.6
        l.caja(px - 0.15, hy, pz - 0.15, px + 0.15, hy + 0.25, pz + 0.15, "luz_verde")
    l.luz(hx, hy + 1.0, hz, (120, 255, 140), 0.7, 14.0)
    # antena con luz roja
    l.cilindro(160.0, top, 108.0, 0.12, 8.0, "metal_negro")
    l.caja(159.85, top + 8.0, 107.85, 160.15, top + 8.3, 108.15, "luz_roja")
    l.luz(160.0, top + 8.4, 108.0, ROJA, 0.8, 8.0)
    l.luz(130.0, top + 3.0, 132.0, CALIDA, 0.7, 16.0)


# ======================================================================================================
# LOS LOCALES DE LA CALLE OLMO Y LAS MANZANAS DE RELLENO
# ======================================================================================================
LICORERIA = (98.0, 18.0, 112.0, 34.0)
FARMACIA = (118.4, 20.0, 132.0, 34.0)

# Manzanas cerradas, a mano (x0, z0, x1, z1, plantas). Las calles, el refugio, los apartamentos, las tiendas y
# el hospital NO van aqui. Todo lo que no es recorrido esta tapado por edificios: el camino es lineal.
MANZANAS = [
    # norte de la calle Olmo
    (0.0, 0.0, 10.0, 66.4, 4), (10.0, 0.0, 36.4, 9.6, 3), (10.0, 30.0, 36.4, 66.4, 4), (36.4, 34.0, 44.0, 66.4, 3),
    (36.4, 0.0, 60.0, 21.6, 5), (36.4, 28.4, 53.2, 34.0, 3),
    (60.0, 0.0, 78.0, 34.0, 4), (78.0, 0.0, 98.0, 34.0, 6), (98.0, 0.0, 112.0, 18.0, 3),
    (112.0, 0.0, 118.4, 34.0, 4), (118.4, 0.0, 132.0, 20.0, 3), (132.0, 0.0, 150.0, 34.0, 5),
    (150.0, 0.0, 179.2, 34.0, 4), (172.0, 34.0, 179.2, 110.4, 4),
    # entre Olmo y Segunda (con el refugio en la esquina este)
    (44.0, 48.0, 76.0, 66.4, 3), (76.0, 48.0, 104.0, 66.4, 5), (104.0, 48.0, 128.0, 66.4, 4),
    (128.0, 48.0, 150.4, 66.4, 3), (150.4, 64.0, 155.6, 66.4, 1),
    (161.2, 64.0, 172.0, 66.4, 1), (168.0, 50.4, 172.0, 64.0, 2),
    # entre Segunda y la avenida
    (0.0, 66.4, 8.8, 179.2, 3), (24.0, 82.4, 56.0, 110.4, 4), (56.0, 82.4, 90.4, 110.4, 6),
    (90.4, 82.4, 118.0, 100.0, 3), (118.0, 82.4, 172.0, 104.0, 5), (116.0, 100.0, 118.0, 104.0, 2),
    (172.0, 110.4, 179.2, 179.2, 4),
    # sur de la avenida y alrededor del hospital
    (8.8, 126.4, 40.0, 179.2, 4), (40.0, 126.4, 70.0, 179.2, 5), (70.0, 126.4, 90.4, 179.2, 3),
    (90.4, 166.4, 116.0, 179.2, 3), (116.0, 160.0, 172.0, 179.2, 4), (166.4, 104.0, 172.0, 160.0, 5),
]


def manzanas(l, rng):
    for x0, z0, x1, z1, pisos in MANZANAS:
        if x1 - x0 < 0.5 or z1 - z0 < 0.5:
            continue
        # las manzanas grandes se parten en edificios de 12-22 m con alturas distintas: la calle no es un muro
        # liso, cada fachada tiene su altura, su color y sus ventanas
        largo_x = (x1 - x0) >= (z1 - z0)
        largo = max(x1 - x0, z1 - z0)
        n = max(1, int(largo / rng.uniform(12.0, 20.0)))
        cortes = [0.0] + sorted(rng.uniform(0.2, 0.8) * largo / n + i * largo / n for i in range(1, n)) + [largo]
        for i in range(len(cortes) - 1):
            a, b = r1(cortes[i]), r1(cortes[i + 1])
            if b - a < 1.0:
                continue
            rect = (x0 + a, z0, x0 + b, z1) if largo_x else (x0, z0 + a, x1, z0 + b)
            p = max(1, min(8, pisos + rng.choice((-1, 0, 0, 1, 2))))
            bloque(l, rect, p, rng)


def construir(l, rng):
    terreno(l, rng)
    aceras_y_marcas(l, rng)
    manzanas(l, rng)
    apartamentos(l, rng)
    callejon(l, rng)
    tienda(l, LICORERIA, "licoreria", rng, puerta_z=LICORERIA[3], neon="neon_rosa")
    tienda(l, FARMACIA, "farmacia", rng, puerta_z=FARMACIA[3], neon="neon_azul")
    calle_olmo(l, rng)
    refugio(l, rng)
    calle_segunda(l, rng)
    esquina_y_avenida(l, rng)
    plaza(l, rng)
    hospital(l, rng)
    farolas(l, rng)
