"""CONSTRUCCION del EPISODIO 3 "EL AMANECER" (campana_amanecer). Ver disposicion.py para el recorrido.

LO NUEVO: EL MAPA ESTA PINTADO. Cada material de fachada lleva su DIBUJO (lienzo.PATRONES, raster._patron):
revoque de colores con chorretones, ladrillo en hiladas, sillares con juntas, tejas, baldosas, adoquines, toldos a
rayas, tablones y persianas de lamas. Y cada casa es distinta: color, zocalo, impostas, recercados, persianas,
balcones de hierro, tiendas con toldo y cartel, tejado de tejas o azotea, bajantes, macetas y ropa tendida.

De dia (amanecer): casi sin luces; solo dentro de lo cerrado (el refugio, el pasaje, la caseta).

`validacion=True` construye la variante que solo sirve para comprobar el recorrido: con los puzzles resueltos
(contenedor abajo, chimenea tumbada = pasarela de voxels, escalera en vez de montacargas, puente bajado).
"""
import math
import disposicion as D
import lienzo as L
import campana as K           # el kit del episodio 1 (mesa, cama, fuego, escombros...)

Y0, Y1, Y2, Y3 = D.Y0, D.Y1, D.Y2, D.Y3

# ======================================================================================================
# MATERIALES Y PATRONES (de dia: colores vivos, no los apagados de la noche)
# ======================================================================================================
MATERIALES = dict(K.MATERIALES)


def _tono(c, k):
    return tuple(int(max(0, min(255, round(v * k)))) for v in c)


def _mezcla(c, m, t):
    return tuple(int(round(a * (1 - t) + b * t)) for a, b in zip(c, m))


def _pat(nombre, patron, colores, tipo):
    MATERIALES[nombre] = (colores[0], tipo)
    L.PATRONES[nombre] = (patron, colores)


MUGRE_DIA = (92, 82, 70)
FACHADAS = {
    "fachada_ocre": (214, 168, 98), "fachada_salmon": (219, 140, 110), "fachada_crema": (232, 214, 178),
    "fachada_azul": (150, 178, 200), "fachada_verde": (148, 194, 172), "fachada_rosa": (208, 150, 150),
    "fachada_cal": (236, 232, 222), "fachada_amarilla": (236, 204, 110), "fachada_terracota": (186, 104, 72),
}
for _n, _c in FACHADAS.items():
    _pat(_n, "revoque", [_c, _tono(_c, 1.05), _tono(_c, 0.9), _mezcla(_c, MUGRE_DIA, 0.38)], "ladrillo")
_pat("ladrillo_visto", "ladrillo", [(158, 78, 56), (142, 66, 48), (172, 90, 64), (128, 60, 44), (104, 86, 72)], "ladrillo")
_pat("sillar_arenisca", "sillar", [(200, 182, 148), (184, 166, 134), (212, 194, 160), (152, 138, 112), (126, 116, 98)], "piedra")
_pat("sillar_gris", "sillar", [(156, 152, 144), (140, 136, 128), (168, 164, 154), (108, 104, 98), (96, 100, 84)], "piedra")
_pat("teja", "teja", [(184, 94, 60), (152, 74, 46), (124, 60, 40), (106, 100, 76)], "ladrillo")
_pat("baldosa_plaza", "baldosa", [(210, 198, 172), (190, 178, 154), (150, 140, 122)], "suelo_duro")
_pat("adoquin", "adoquin", [(128, 122, 114), (112, 108, 102), (142, 136, 126), (78, 74, 70)], "suelo_duro")
_pat("toldo_rojo", "rayas", [(196, 52, 44), (236, 228, 210)], "tela")
_pat("toldo_verde", "rayas", [(52, 134, 84), (236, 228, 210)], "tela")
_pat("toldo_azul", "rayas", [(50, 96, 168), (236, 228, 210)], "tela")
_pat("tablas", "tablas", [(134, 96, 62), (118, 84, 54), (148, 108, 70), (84, 60, 40)], "madera")
_pat("persiana_verde", "lamas", [(72, 124, 90), (54, 100, 70)], "madera")
_pat("persiana_azul", "lamas", [(72, 112, 158), (56, 92, 132)], "madera")
_pat("persiana_marron", "lamas", [(122, 82, 54), (100, 66, 42)], "madera")
_pat("roca", "estratos", [(152, 132, 106), (136, 118, 96), (166, 146, 118), (120, 106, 88)], "piedra")
_pat("cesped", "cesped", [(96, 128, 64), (84, 114, 56), (110, 142, 72), (122, 128, 72)], "suelo")
_pat("peligro", "rayas", [(214, 176, 30), (30, 30, 30)], "metal")
MATERIALES.update({
    "tierra_dia": ((124, 100, 74), "suelo"),
    "arena": ((206, 186, 146), "suelo"),
    "marco_blanco": ((234, 228, 214), "hormigon"),
    "cornisa_clara": ((216, 208, 190), "piedra"),
    "zocalo": ((128, 122, 114), "piedra"),
    "hierro": ((42, 42, 44), "metal"),
    "vidrio_ventana": ((64, 84, 96), "vidrio"),
    "puerta_verde": ((52, 92, 64), "madera"),
    "puerta_roja": ((140, 46, 38), "madera"),
    "puerta_azul": ((46, 70, 120), "madera"),
    "cartel_amarillo": ((230, 190, 60), "suelo_pintura"),
    "cartel_blanco": ((236, 236, 230), "suelo_pintura"),
    "letras": ((34, 34, 36), "suelo_pintura"),
    "agua_mar": ((38, 88, 108), "organico"),
    "agua_fuente": ((70, 130, 150), "organico"),
    "hojas": ((78, 124, 58), "organico"),
    "hojas_oscuras": ((56, 96, 48), "organico"),
    "tronco": ((96, 72, 50), "madera"),
    "flores_rojas": ((204, 52, 62), "organico"),
    "flores_violeta": ((150, 84, 176), "organico"),
    "metal_verde": ((48, 84, 64), "metal"),
    "chapa_amarilla": ((206, 168, 40), "metal"),
    "fruta_naranja": ((236, 136, 30), "organico"),
    "fruta_verde": ((120, 180, 60), "organico"),
    "fruta_roja": ((190, 30, 40), "organico"),
    "red_pesca": ((60, 100, 90), "tela"),
    "barca_blanca": ((226, 224, 214), "madera"),
    "barca_azul": ((40, 90, 150), "madera"),
})

REVOQUES = list(FACHADAS)
PERSIANAS = ("persiana_verde", "persiana_azul", "persiana_marron")
PUERTAS = ("puerta_verde", "puerta_roja", "puerta_azul")
TOLDOS = ("toldo_rojo", "toldo_verde", "toldo_azul")
TIENDAS = ("PANADERIA", "FARMACIA", "PESCADERIA", "BAR", "ULTRAMARINOS", "FERRETERIA", "MERCERIA", "ESTANCO",
           "PELUQUERIA", "LIBRERIA", "CAFE", "BAZAR")
CALIDA = (255, 196, 140)


# ======================================================================================================
# UTILIDADES
# ======================================================================================================
def _cara(cara):
    """(eje horizontal de la fachada, signo de la normal): '+z' -> fachada a lo largo de X mirando a +Z."""
    return {"+z": ("x", 1), "-z": ("x", -1), "+x": ("z", 1), "-x": ("z", -1)}[cara]


def _caja_cara(l, cara, fijo, u0, u1, y0, y1, fuera0, fuera1, mat, hueco=False):
    """Caja pegada a una fachada: de u0 a u1 a lo largo, de y0 a y1, y de `fuera0` a `fuera1` metros hacia
    fuera de la pared (negativo = hacia dentro)."""
    eje, sg = _cara(cara)
    a, b = fijo + sg * fuera0, fijo + sg * fuera1
    if eje == "x":
        l.caja(u0, y0, min(a, b), u1, y1, max(a, b), mat, hueco=hueco)
    else:
        l.caja(min(a, b), y0, u0, max(a, b), y1, u1, mat, hueco=hueco)


def _luz_cara(l, cara, fijo, u, y, fuera, color, e, alcance):
    eje, sg = _cara(cara)
    if eje == "x":
        l.luz(u, y, fijo + sg * fuera, color, e, alcance)
    else:
        l.luz(fijo + sg * fuera, y, u, color, e, alcance)


# ======================================================================================================
# LA CASA PINTADA
# ======================================================================================================
def ventana(l, cara, fijo, u, y, rng, ancho=1.1, alto=1.5, balcon=False, persiana=None):
    """Hueco con cristal oscuro, recercado claro, alfeizar, persianas de lamas (abiertas, cerradas o a medias)
    y, si toca, balcon de hierro con su losa."""
    a0, a1 = u - ancho / 2, u + ancho / 2
    _caja_cara(l, cara, fijo, a0 - 0.14, a1 + 0.14, y - 0.14, y + alto + 0.16, -0.02, 0.06, "marco_blanco")  # recercado
    _caja_cara(l, cara, fijo, a0, a1, y, y + alto, -0.3, 0.07, "marco_blanco", hueco=True)                   # el hueco
    _caja_cara(l, cara, fijo, a0, a1, y, y + alto, -0.3, -0.22, "vidrio_ventana")                            # cristal
    _caja_cara(l, cara, fijo, u - 0.03, u + 0.03, y, y + alto, -0.24, -0.2, "marco_blanco")                  # parteluz
    if balcon:
        _caja_cara(l, cara, fijo, a0 - 0.4, a1 + 0.4, y - 0.18, y - 0.02, 0.0, 0.9, "cornisa_clara")          # la losa
        _caja_cara(l, cara, fijo, a0 - 0.4, a1 + 0.4, y + 0.9, y + 0.98, 0.84, 0.9, "hierro")               # pasamanos
        for k in range(int((ancho + 0.8) / 0.16) + 1):
            x = a0 - 0.4 + k * 0.16
            _caja_cara(l, cara, fijo, x, x + 0.03, y - 0.02, y + 0.9, 0.85, 0.88, "hierro")
        for x in (a0 - 0.4, a1 + 0.37):
            _caja_cara(l, cara, fijo, x, x + 0.03, y - 0.02, y + 0.9, 0.0, 0.9, "hierro")
        if rng.random() < 0.55:          # macetas
            m = rng.choice(("flores_rojas", "flores_violeta", "hojas"))
            _caja_cara(l, cara, fijo, a0 - 0.3, a0 - 0.05, y - 0.02, y + 0.22, 0.55, 0.8, "ladrillo_visto")
            _caja_cara(l, cara, fijo, a0 - 0.32, a0 - 0.03, y + 0.22, y + 0.46, 0.53, 0.82, m)
    else:
        _caja_cara(l, cara, fijo, a0 - 0.1, a1 + 0.1, y - 0.1, y, 0.0, 0.14, "cornisa_clara")                # alfeizar
    persiana = persiana or rng.choice(PERSIANAS)
    estado = rng.random()
    if estado < 0.45:            # abiertas, contra la pared
        _caja_cara(l, cara, fijo, a0 - ancho / 2 - 0.12, a0 - 0.12, y, y + alto, 0.04, 0.1, persiana)
        _caja_cara(l, cara, fijo, a1 + 0.12, a1 + ancho / 2 + 0.12, y, y + alto, 0.04, 0.1, persiana)
    elif estado < 0.7:           # cerradas
        _caja_cara(l, cara, fijo, a0, a1, y, y + alto, -0.16, -0.1, persiana)
    elif estado < 0.85:          # una abierta y otra cerrada
        _caja_cara(l, cara, fijo, a0, u, y, y + alto, -0.16, -0.1, persiana)
        _caja_cara(l, cara, fijo, a1 + 0.12, a1 + ancho / 2 + 0.12, y, y + alto, 0.04, 0.1, persiana)


def tienda(l, cara, fijo, u0, u1, y, rng, nombre=None):
    """Planta baja de tienda: escaparate, puerta, toldo a rayas y cartel encima."""
    _caja_cara(l, cara, fijo, u0 + 0.3, u1 - 0.3, y, y + 2.7, -0.4, 0.05, "marco_blanco", hueco=True)
    _caja_cara(l, cara, fijo, u0 + 0.3, u1 - 0.3, y + 0.5, y + 2.5, -0.35, -0.28, "vidrio_ventana")
    _caja_cara(l, cara, fijo, u0 + 0.3, u1 - 0.3, y, y + 0.5, -0.4, -0.2, "zocalo")
    pu = (u0 + u1) / 2
    _caja_cara(l, cara, fijo, pu - 0.55, pu + 0.55, y, y + 2.4, -0.36, -0.26, rng.choice(PUERTAS))
    _caja_cara(l, cara, fijo, u0 + 0.15, u1 - 0.15, y + 2.72, y + 3.3, 0.0, 0.12, rng.choice(("cartel_amarillo", "cartel_blanco", "fachada_cal")))
    # las "letras": una tira oscura (el nombre lo pondria un Label3D; de lejos basta la tira)
    _caja_cara(l, cara, fijo, u0 + 0.6, u1 - 0.6, y + 2.9, y + 3.12, 0.12, 0.14, "letras")
    # el toldo: sale inclinado en dos escalones
    t = rng.choice(TOLDOS)
    _caja_cara(l, cara, fijo, u0 + 0.1, u1 - 0.1, y + 2.55, y + 2.68, 0.1, 0.8, t)
    _caja_cara(l, cara, fijo, u0 + 0.1, u1 - 0.1, y + 2.38, y + 2.55, 0.8, 1.45, t)
    _caja_cara(l, cara, fijo, u0 + 0.1, u1 - 0.1, y + 2.1, y + 2.38, 1.4, 1.5, t)          # el faldon


def casa(l, rect, y, pisos, rng, caras=("+z", "-z", "+x", "-x"), bajo="auto", tejado="auto", color=None):
    """Una casa entera, maciza (no se entra), pintada. `bajo`: 'tienda' | 'puerta' | 'nada' | 'auto'."""
    x0, z0, x1, z1 = rect
    alto = pisos * D.PISO
    color = color or rng.choice(REVOQUES)
    top = y + alto
    l.caja(x0, y - 1.0, z0, x1, top, z1, color)
    # zocalo de piedra y cornisa de coronacion
    for cara in caras:
        eje, sg = _cara(cara)
        fijo = {"+z": z1, "-z": z0, "+x": x1, "-x": x0}[cara]
        u0, u1 = (x0, x1) if eje == "x" else (z0, z1)
        _caja_cara(l, cara, fijo, u0, u1, y, y + 0.9, 0.0, 0.06, "zocalo")
        _caja_cara(l, cara, fijo, u0 - 0.1, u1 + 0.1, top - 0.25, top + 0.05, 0.0, 0.22, "cornisa_clara")
        for k in range(1, pisos):              # impostas entre plantas
            _caja_cara(l, cara, fijo, u0, u1, y + k * D.PISO - 0.1, y + k * D.PISO + 0.05, 0.0, 0.07, "cornisa_clara")
        largo = u1 - u0
        n = max(1, int((largo - 0.6) / 2.6))
        paso = largo / n
        persiana = rng.choice(PERSIANAS)
        tipo_bajo = bajo if bajo != "auto" else ("tienda" if largo >= 5.0 and rng.random() < 0.55 else "puerta")
        if tipo_bajo == "tienda" and largo >= 4.0:
            tienda(l, cara, fijo, u0 + 0.4, u1 - 0.4, y, rng)
        elif tipo_bajo == "puerta":
            pu = u0 + paso * (rng.randint(0, n - 1) + 0.5)
            _caja_cara(l, cara, fijo, pu - 0.62, pu + 0.62, y, y + 2.55, -0.25, 0.05, "marco_blanco", hueco=True)
            _caja_cara(l, cara, fijo, pu - 0.78, pu + 0.78, y + 2.55, y + 2.72, -0.02, 0.08, "marco_blanco")
            _caja_cara(l, cara, fijo, pu - 0.6, pu + 0.6, y, y + 2.52, -0.22, -0.14, rng.choice(PUERTAS))
            for i in range(n):
                uu = u0 + paso * (i + 0.5)
                if abs(uu - pu) > 1.3:
                    ventana(l, cara, fijo, uu, y + 1.0, rng, ancho=0.9, alto=1.3, persiana=persiana)
        for k in range(1, pisos):
            for i in range(n):
                uu = u0 + paso * (i + 0.5)
                ventana(l, cara, fijo, uu, y + k * D.PISO + 0.9, rng, balcon=(rng.random() < 0.35), persiana=persiana)
        # bajante en una esquina
        if rng.random() < 0.7:
            ub = u0 + 0.25 if rng.random() < 0.5 else u1 - 0.25
            _caja_cara(l, cara, fijo, ub - 0.06, ub + 0.06, y, top, 0.04, 0.16, "hierro")
    # EL TEJADO: de tejas a dos aguas (escalonado a lo largo del lado corto) o azotea con pretil
    tipo_t = tejado if tejado != "auto" else ("tejas" if rng.random() < 0.65 else "azotea")
    if tipo_t == "tejas":
        corto_x = (x1 - x0) <= (z1 - z0)
        mitad = ((x1 - x0) if corto_x else (z1 - z0)) / 2
        n = max(2, int(mitad / 0.25))
        for i in range(n):
            e = i * mitad / n
            h = top + 0.05 + i * (mitad * 0.55) / n
            if corto_x:
                l.caja(x0 - 0.25 + e, top, z0 - 0.25, x1 + 0.25 - e, h + 0.12, z1 + 0.25, "teja")
            else:
                l.caja(x0 - 0.25, top, z0 - 0.25 + e, x1 + 0.25, h + 0.12, z1 + 0.25 - e, "teja")
        if rng.random() < 0.5:             # chimenea
            cx, cz = x0 + (x1 - x0) * rng.uniform(0.25, 0.75), z0 + (z1 - z0) * rng.uniform(0.25, 0.75)
            l.caja(cx - 0.3, top, cz - 0.3, cx + 0.3, top + mitad * 0.55 + 1.0, cz + 0.3, "ladrillo_visto")
    else:
        l.caja(x0, top, z0, x1, top + 0.9, z1, color)
        l.caja(x0 + 0.25, top, z0 + 0.25, x1 - 0.25, top + 0.9, z1 - 0.25, color, hueco=True)
        l.caja(x0, top + 0.85, z0, x1, top + 0.95, z1, "cornisa_clara")
        l.caja(x0 + 0.25, top + 0.85, z0 + 0.25, x1 - 0.25, top + 0.95, z1 - 0.25, "cornisa_clara", hueco=True)
        if rng.random() < 0.5:             # deposito de agua / antena
            cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
            l.cilindro(cx, top, cz, 0.6, 1.3, "chapa_blanca")


def fila(l, x0, z0, x1, z1, y, rng, caras, pisos=(2, 4), ancho=(5.0, 8.0), **kw):
    """Una fila de casas pegadas a lo largo del lado largo del rectangulo, cada una distinta."""
    a_lo_x = (x1 - x0) >= (z1 - z0)
    ini, fin = (x0, x1) if a_lo_x else (z0, z1)
    u = ini
    while u < fin - 0.5:
        w = min(fin - u, rng.uniform(*ancho))
        if fin - (u + w) < 3.0:
            w = fin - u
        r = (u, z0, u + w, z1) if a_lo_x else (x0, u, x1, u + w)
        casa(l, r, y, rng.randint(*pisos), rng, caras=caras, **kw)
        u += w


# ======================================================================================================
# DETALLES DE LA CALLE
# ======================================================================================================
def farola(l, x, z, y):
    l.caja(x - 0.08, y, z - 0.08, x + 0.08, y + 3.8, z + 0.08, "metal_verde")
    l.caja(x - 0.18, y, z - 0.18, x + 0.18, y + 0.5, z + 0.18, "metal_verde")
    l.caja(x - 0.22, y + 3.8, z - 0.22, x + 0.22, y + 4.3, z + 0.22, "hierro")
    l.caja(x - 0.16, y + 3.85, z - 0.16, x + 0.16, y + 4.2, z + 0.16, "vidrio_ventana")


def arbol(l, x, z, y, rng, alto=None):
    alto = max(5.0, alto or rng.uniform(5.0, 6.5))
    l.cilindro(x, y, z, 0.22, alto * 0.72, "tronco")
    # la copa, ALTA: por debajo de 2,6 m no hay hojas (se pasa por debajo sin agacharse)
    for i in range(3):
        ry = rng.uniform(0.9, 1.2)
        l.elipsoide(x + rng.uniform(-0.6, 0.6), y + max(2.6 + ry, alto * (0.7 + i * 0.1)), z + rng.uniform(-0.6, 0.6),
                    rng.uniform(1.4, 2.0), ry, rng.uniform(1.4, 2.0), rng.choice(("hojas", "hojas_oscuras")))


def banco(l, x, z, y, eje="x"):
    if eje == "x":
        l.caja(x - 0.9, y + 0.42, z - 0.25, x + 0.9, y + 0.5, z + 0.25, "tablas")
        l.caja(x - 0.9, y + 0.5, z + 0.2, x + 0.9, y + 0.9, z + 0.26, "tablas")
        for dx in (-0.8, 0.8):
            l.caja(x + dx - 0.04, y, z - 0.22, x + dx + 0.04, y + 0.42, z + 0.22, "hierro")
    else:
        l.caja(x - 0.25, y + 0.42, z - 0.9, x + 0.25, y + 0.5, z + 0.9, "tablas")
        l.caja(x + 0.2, y + 0.5, z - 0.9, x + 0.26, y + 0.9, z + 0.9, "tablas")
        for dz in (-0.8, 0.8):
            l.caja(x - 0.22, y, z + dz - 0.04, x + 0.22, y + 0.42, z + dz + 0.04, "hierro")


def tendedero(l, x0, z0, x1, z1, y, rng):
    """Una cuerda de ropa tendida entre dos fachadas, con prendas de colores."""
    l.linea(x0, y, z0, x1, y, z1, 0.03, "cartel_blanco")
    n = int(math.hypot(x1 - x0, z1 - z0) / 0.7)
    for i in range(1, n):
        t = i / n
        x, z = x0 + (x1 - x0) * t, z0 + (z1 - z0) * t
        m = rng.choice(("fachada_cal", "toldo_rojo", "fachada_azul", "fachada_amarilla", "persiana_verde"))
        l.caja(x - 0.22, y - 0.6, z - 0.04, x + 0.22, y, z + 0.04, m)


def coche(l, x, z, eje, y, rng):
    mat = rng.choice(("chapa_blanca", "chapa_roja", "chapa_azul", "fachada_amarilla", "fachada_verde"))
    if eje == "x":
        l.caja(x - 2.0, y + 0.3, z - 0.85, x + 2.0, y + 1.05, z + 0.85, mat)
        l.caja(x - 1.0, y + 1.05, z - 0.78, x + 0.9, y + 1.62, z + 0.78, mat)
        l.caja(x - 0.9, y + 1.1, z - 0.8, x + 0.8, y + 1.55, z + 0.8, "vidrio_ventana")
        for dx in (-1.35, 1.35):
            for dz in (-0.8, 0.8):
                l.cilindro(x + dx, y + 0.0, z + dz - 0.12, 0.33, 0.24, "goma", eje="z")
    else:
        l.caja(x - 0.85, y + 0.3, z - 2.0, x + 0.85, y + 1.05, z + 2.0, mat)
        l.caja(x - 0.78, y + 1.05, z - 1.0, x + 0.78, y + 1.62, z + 0.9, mat)
        l.caja(x - 0.8, y + 1.1, z - 0.9, x + 0.8, y + 1.55, z + 0.8, "vidrio_ventana")
        for dx in (-0.8, 0.8):
            for dz in (-1.35, 1.35):
                l.cilindro(x + dx - 0.12, y + 0.0, z + dz, 0.33, 0.24, "goma", eje="x")


def barandilla(l, x0, z0, x1, z1, y, alto=1.0):
    l.caja(x0, y + alto - 0.06, z0, x1, y + alto, z1, "hierro")
    largo = max(abs(x1 - x0), abs(z1 - z0))
    for k in range(int(largo / 0.2) + 1):
        t = k * 0.2
        if abs(x1 - x0) >= abs(z1 - z0):
            l.caja(x0 + t, y, z0, x0 + t + 0.03, y + alto, z1, "hierro")
        else:
            l.caja(x0, y, z0 + t, x1, y + alto, z0 + t + 0.03, "hierro")


# ======================================================================================================
# TERRENO: las cuatro terrazas
# ======================================================================================================
def terreno(l, validacion):
    X, Z = D.ANCHO_X, D.ANCHO_Z
    l.caja(0, 0, 0, X, D.ROCA_Y, Z, "roca_base")
    # el mar y el fondo de arena
    l.caja(0, D.ROCA_Y, D.MAR_Z, X, D.MAR_AGUA_Y, Z, "agua_mar")
    # el muelle (Y0)
    l.caja(0, D.ROCA_Y, D.MALECON_Z, X, Y0, D.MAR_Z, "sillar_arenisca")
    l.caja(0, Y0 - 0.2, D.MALECON_Z, X, Y0, D.MAR_Z - 0.6, "adoquin")
    # la plaza y todo lo de Y1 (de z 50 al malecon)
    l.caja(0, D.ROCA_Y, 50.0, X, Y1, D.MALECON_Z, "roca")
    # EL MALECON: el muro de sillares de 4 m del muelle a la plaza
    l.caja(0, Y0 - 0.2, D.MALECON_Z - 0.6, X, Y1, D.MALECON_Z, "sillar_arenisca")
    # Y2: todo lo que queda al norte de la plaza (la roca de la ladera), menos la cuesta y el barranco
    l.caja(0, D.ROCA_Y, 0, D.ACANTILADO_X, Y2, 50.0, "roca")
    # Y3: el cerro de la ciudadela, al este del acantilado
    l.caja(D.ACANTILADO_X, D.ROCA_Y, 0, X, Y3, 64.0, "roca")
    # la ladera sur del cerro (sobre las casas del este de la plaza)
    l.caja(D.ACANTILADO_X, Y1, 64.0, X, Y1 + 6.0, 70.0, "roca")
    # los extremos de la fila norte: roca hasta Y2 (no quedan huecos entre la plaza y la ladera)
    l.caja(0, Y1, 50.0, 16.0, Y2 + 6.0, 60.0, "roca")
    l.caja(104.0, Y1, 50.0, D.ACANTILADO_X, Y2, 60.0, "roca")
    # el borde norte y oeste del mapa: la ladera sigue subiendo (cierra el mapa)
    l.caja(0, Y2, 0, D.ACANTILADO_X, Y2 + 6.0, 4.0, "roca")
    l.caja(0, Y2, 0, 16.0, Y2 + 6.0, 50.0, "roca")
    # LA CUESTA: una trinchera escalonada de Y1 (z 50) a Y2 (z 30)
    cx0, cz0, cx1, cz1 = D.CUESTA
    za, zb = D.CUESTA_Z
    l.caja(cx0, Y1, za, cx1, Y2 + 0.01, 50.0, "roca", hueco=True)
    peldanos = 30
    for i in range(peldanos):
        z_ini = zb - (zb - za) * i / peldanos
        z_fin = zb - (zb - za) * (i + 1) / peldanos
        yy = Y1 + (Y2 - Y1) * (i + 1) / peldanos
        l.caja(cx0, Y1, z_fin, cx1, yy, z_ini, "sillar_arenisca")
    # el barranco: la calle hundida hasta Y1
    bx0, bz0, bx1, bz1 = D.BARRANCO
    l.caja(bx0, Y1, bz0, bx1, Y2 + 0.01, bz1, "roca", hueco=True)
    l.caja(bx0, Y1 - 0.3, bz0, bx1, Y1, bz1, "tierra_dia")
    # el foso de la ciudadela
    fx0, fz0, fx1, fz1 = D.FOSO
    l.caja(fx0, D.FOSO_FONDO_Y, fz0, fx1, Y3 + 0.01, fz1, "roca", hueco=True)
    l.caja(fx0, D.FOSO_FONDO_Y - 0.3, fz0, fx1, D.FOSO_FONDO_Y, fz1, "cesped")
    # suelos de cada terraza
    l.caja(16.0, Y1 - 0.2, 60.0, 104.0, Y1, D.MALECON_Z - 0.6, "baldosa_plaza")
    l.caja(16.0, Y2 - 0.2, 4.0, 70.0, Y2, 28.0, "adoquin")
    l.caja(79.0, Y2 - 0.2, 4.0, D.ACANTILADO_X, Y2, 50.0, "adoquin")
    l.caja(D.ACANTILADO_X, Y3 - 0.2, 4.0, D.FOSO[0], Y3, 64.0, "cesped")
    l.caja(D.CIUDADELA[0], Y3 - 0.2, 4.0, D.ANCHO_X, Y3, 64.0, "adoquin")


# ======================================================================================================
# 1. EL MUELLE Y EL CONTENEDOR
# ======================================================================================================
def barca(l, x, z, rng, mat=None):
    mat = mat or rng.choice(("barca_blanca", "barca_azul"))
    l.elipsoide(x, D.MAR_AGUA_Y + 0.2, z, 2.6, 0.55, 0.9, mat)
    l.elipsoide(x, D.MAR_AGUA_Y + 0.35, z, 2.3, 0.45, 0.7, mat, hueco=True)
    l.caja(x - 0.2, D.MAR_AGUA_Y + 0.2, z - 0.7, x + 0.2, D.MAR_AGUA_Y + 0.35, z + 0.7, "tablas")


def muelle(l, rng, validacion):
    X = D.ANCHO_X
    # borde del muelle: bolardos y una cadena baja
    for x in range(3, int(X) - 2, 7):
        if D.PANTALAN[0] - 1 <= x <= D.PANTALAN[2] + 1:
            continue
        l.cilindro(x, Y0, D.MAR_Z - 0.4, 0.22, 0.55, "hierro")
    # el pantalan de madera donde atraca el barco
    p0, pz0, p1, pz1 = D.PANTALAN
    l.caja(p0, Y0 - 0.22, pz0 - 0.6, p1, Y0, pz1, "tablas")
    for x in (p0 + 0.3, (p0 + p1) / 2, p1 - 0.3):
        for z in (pz0 + 2.0, pz0 + 6.0, pz1 - 0.3):
            l.cilindro(x, D.ROCA_Y, z, 0.18, Y0 - D.ROCA_Y, "tronco")
    # barcas de pesca amarradas, redes, nasas y cajas de pescado
    for bx, bz in ((8.0, 118.0), (42.0, 117.0), (58.0, 120.0), (96.0, 118.0), (130.0, 119.0), (148.0, 117.0)):
        barca(l, bx, bz, rng)
    for rx, rz in ((34.0, 104.0), (70.0, 108.0), (118.0, 104.0)):
        l.elipsoide(rx, Y0 + 0.15, rz, 1.4, 0.25, 0.9, "red_pesca")
    for i in range(14):
        cx, cz = rng.uniform(52, 150), rng.uniform(100, 111)
        if abs(cx - 41) < 8:
            continue
        s = rng.uniform(0.5, 0.8)
        l.caja(cx, Y0, cz, cx + s, Y0 + s * 0.5, cz + s * 0.7, rng.choice(("tablas", "chapa_azul", "fachada_azul")))
    # casetas de pescadores al pie del malecon (de colores)
    for x0, x1, mat in ((60.0, 66.0, "fachada_azul"), (84.0, 89.0, "fachada_verde"), (104.0, 110.0, "fachada_amarilla"),
                        (132.0, 138.0, "fachada_salmon")):
        l.caja(x0, Y0, D.MALECON_Z, x1, Y0 + 2.8, D.MALECON_Z + 3.0, mat)
        l.caja(x0 - 0.2, Y0 + 2.8, D.MALECON_Z, x1 + 0.2, Y0 + 3.0, D.MALECON_Z + 3.3, "teja")
        l.caja((x0 + x1) / 2 - 0.6, Y0, D.MALECON_Z + 2.9, (x0 + x1) / 2 + 0.6, Y0 + 2.2, D.MALECON_Z + 3.1, rng.choice(PUERTAS))
    # la escalinata del muelle a la plaza: HUNDIDA (escombros y la barandilla colgando)
    ex0, ez0, ex1, ez1 = D.ESCALINATA_MUELLE
    l.escombros((ex0 + ex1) / 2, D.MALECON_Z + 2.0, Y0, 2.6, 18, rng, mats=("sillar_arenisca", "adoquin", "hierro"))
    l.caja(ex0, Y0, D.MALECON_Z - 0.6, ex1, Y1, D.MALECON_Z, "sillar_arenisca")
    # EL ANDAMIO del contenedor: seis puntales de madera y un piso de tablones (el contenedor lo pone el juego)
    cx0, cz0, cx1, cz1 = D.CONT
    if not validacion:
        for px, pz in D.PUNTALES:
            l.caja(px, Y0, pz, px + 0.4, D.CONT_ANDAMIO_Y - 0.12, pz + 0.4, "tronco")
        l.caja(cx0 - 0.2, D.CONT_ANDAMIO_Y - 0.12, cz0 - 0.1, cx1 + 0.2, D.CONT_ANDAMIO_Y, cz1 + 0.1, "tablas")
        for px in (cx0 + 0.2, cx1 - 0.4):       # riostras en cruz
            l.linea(px, Y0 + 0.3, cz0 + 0.3, px, D.CONT_ANDAMIO_Y - 0.4, cz1 - 0.3, 0.12, "tronco")
    else:
        # en el juego se TREPA (cajas -> contenedor caido -> malecon); el A* de la validacion solo anda: rampa
        l.cuna(cx0, Y0, cz0, cx1, Y1, cz0 + 9.0, sube_hacia="-z", mat="chapa_azul")
    # las cajas para subirse al contenedor (0,9 m) y marcas de peligro en el suelo
    a0, b0, a1, b1 = D.CAJAS_SUBIR
    l.caja(a0, Y0, b0, a1, Y0 + 0.9, b1, "tablas")
    l.caja(a0 + 1.2, Y0, b0 + 0.2, a1 + 1.0, Y0 + 0.45, b1 - 0.2, "tablas")
    for i in range(7):
        l.caja(cx0 + i * 0.9, Y0, cz1 + 0.4, cx0 + i * 0.9 + 0.45, Y0 + 0.02, cz1 + 0.6, "peligro")
    # la grua portuaria que tendria que haber bajado el contenedor (de adorno, parada)
    gx, gz = 52.0, 108.0
    for dx in (-1.6, 1.6):
        for dz in (-1.6, 1.6):
            l.caja(gx + dx - 0.2, Y0, gz + dz - 0.2, gx + dx + 0.2, Y0 + 11.0, gz + dz + 0.2, "chapa_amarilla")
    l.caja(gx - 2.0, Y0 + 11.0, gz - 2.0, gx + 2.0, Y0 + 11.8, gz + 12.0, "chapa_amarilla")
    l.caja(gx - 1.2, Y0 + 11.8, gz - 1.8, gx + 1.2, Y0 + 13.6, gz + 0.8, "chapa_amarilla")
    l.caja(gx - 1.1, Y0 + 12.3, gz + 0.7, gx + 1.1, Y0 + 13.3, gz + 0.82, "vidrio_ventana")


# ======================================================================================================
# 2. LA PLAZA DEL MERCADO, LA IGLESIA Y LA PERSIANA
# ======================================================================================================
def puesto(l, x, z, y, rng, eje="x"):
    """Un puesto de mercado: mesa de tablones, cajas de fruta de colores y su toldo a rayas."""
    t = rng.choice(TOLDOS)
    w, d = (3.0, 1.6) if eje == "x" else (1.6, 3.0)
    for dx in (0.1, w - 0.2):
        for dz in (0.1, d - 0.2):
            l.caja(x + dx, y, z + dz, x + dx + 0.1, y + 2.3, z + dz + 0.1, "tronco")
    l.caja(x, y + 0.8, z, x + w, y + 0.9, z + d, "tablas")
    l.caja(x - 0.2, y + 2.3, z - 0.2, x + w + 0.2, y + 2.42, z + d + 0.2, t)
    for i in range(int(w / 0.6) if eje == "x" else int(d / 0.6)):
        f = rng.choice(("fruta_naranja", "fruta_verde", "fruta_roja", "hojas"))
        if eje == "x":
            l.caja(x + 0.1 + i * 0.6, y + 0.9, z + 0.2, x + 0.6 + i * 0.6, y + 1.1, z + d - 0.2, "tablas")
            l.elipsoide(x + 0.35 + i * 0.6, y + 1.15, z + d / 2, 0.22, 0.12, d / 2 - 0.3, f)
        else:
            l.caja(x + 0.2, y + 0.9, z + 0.1 + i * 0.6, x + w - 0.2, y + 1.1, z + 0.6 + i * 0.6, "tablas")
            l.elipsoide(x + w / 2, y + 1.15, z + 0.35 + i * 0.6, w / 2 - 0.3, 0.12, 0.22, f)


def iglesia(l, rng):
    x0, z0, x1, z1 = D.IGLESIA
    y = Y1
    l.caja(x0, y - 1.0, z0, x1, y + 12.0, z1, "sillar_arenisca")
    # tejado a dos aguas de tejas
    for i in range(14):
        e = i * 0.5
        l.caja(x0 - 0.3 + e, y + 12.0, z0 - 0.3, x1 + 0.3 - e, y + 12.1 + i * 0.3, z1 + 0.3, "teja")
    # la fachada (mira al este, a la plaza): portico, puerta, rosetón, espadaña
    fx = x1
    l.caja(fx, y, 70.0, fx + 0.6, y + 9.0, 82.0, "sillar_arenisca")
    l.caja(fx - 0.3, y, 74.0, fx + 0.61, y + 4.2, 78.0, "sillar_arenisca", hueco=True)
    l.caja(fx - 0.2, y, 74.2, fx - 0.1, y + 4.0, 77.8, "puerta_roja")
    for k in range(3):          # arquivoltas
        l.caja(fx + 0.6, y + 4.2 + k * 0.2, 73.6 - k * 0.3, fx + 0.8, y + 4.4 + k * 0.2, 78.4 + k * 0.3, "cornisa_clara")
    l.cilindro(fx + 0.35, y + 6.6, 76.0, 1.2, 0.4, "cornisa_clara", eje="x")
    l.cilindro(fx + 0.4, y + 6.6, 76.0, 0.95, 0.4, "vidrio_ventana", eje="x")
    # la escalinata de la puerta
    for k in range(3):
        l.caja(fx + 0.6 + k * 0.4, y, 73.0 - k * 0.3, fx + 1.0 + k * 0.4, y + 0.6 - k * 0.2, 79.0 + k * 0.3, "sillar_arenisca")
    # el campanario (en la esquina sur), con sus huecos de campana
    tx0, tz0 = x0 + 8.0, z1 - 6.0
    l.caja(tx0, y, tz0, tx0 + 5.0, y + 20.0, tz0 + 5.0, "sillar_arenisca")
    for cara_z in (tz0, tz0 + 5.0):
        l.caja(tx0 + 1.2, y + 15.0, cara_z - 0.3, tx0 + 3.8, y + 18.0, cara_z + 0.3, "sillar_arenisca", hueco=True)
    for cara_x in (tx0, tx0 + 5.0):
        l.caja(cara_x - 0.3, y + 15.0, tz0 + 1.2, cara_x + 0.3, y + 18.0, tz0 + 3.8, "sillar_arenisca", hueco=True)
    l.cilindro(tx0 + 2.5, y + 15.8, tz0 + 2.5, 0.8, 1.4, "chapa_amarilla")      # la campana
    for i in range(6):
        l.caja(tx0 + 0.4 * i, y + 20.0 + i * 0.5, tz0 + 0.4 * i, tx0 + 5.0 - 0.4 * i, y + 20.5 + i * 0.5, tz0 + 5.0 - 0.4 * i, "teja")
    # ventanales laterales
    for zz in (64.0, 68.0, 84.0, 88.0):
        l.caja(fx - 0.5, y + 5.0, zz - 0.5, fx + 0.1, y + 8.0, zz + 0.5, "vidrio_ventana")


def plaza(l, rng, validacion):
    x0, z0, x1, z1 = D.PLAZA_MERCADO
    y = Y1
    # la barandilla del malecon (menos donde se sube desde el contenedor)
    cx0, _cz0, cx1, _cz1 = D.CONT
    for a, b in ((0.0, cx0 - 0.5), (cx1 + 0.5, D.ANCHO_X)):
        barandilla(l, a, D.MALECON_Z - 0.35, b, D.MALECON_Z - 0.3, y, 1.05)
    # la fuente
    fx, fz = D.FUENTE
    l.cilindro(fx, y, fz, 3.2, 0.7, "sillar_arenisca")
    l.cilindro(fx, y + 0.2, fz, 2.9, 0.51, "agua_fuente")
    l.cilindro(fx, y, fz, 0.5, 2.2, "sillar_arenisca")
    l.cilindro(fx, y + 2.2, fz, 1.0, 0.3, "sillar_arenisca")
    # los puestos del mercado, en dos hileras
    for i, px in enumerate((24.0, 30.0, 36.0, 44.0, 72.0, 78.0, 86.0, 92.0)):
        puesto(l, px, 70.0 if i % 2 == 0 else 88.0, y, rng)
        puesto(l, px, 88.0 if i % 2 == 0 else 70.0, y, rng)
    # terrazas de bar: mesas y sillas
    for tx, tz in ((66.0, 64.0), (69.0, 66.0), (96.0, 64.0), (99.0, 66.5)):
        l.cilindro(tx, y, tz, 0.4, 0.75, "hierro")
        l.cilindro(tx, y + 0.72, tz, 0.45, 0.05, "cartel_blanco")
    # arboles y bancos
    for ax, az in ((22.0, 64.0), (32.0, 93.0), (80.0, 94.0), (100.0, 80.0), (46.0, 80.0), (74.0, 80.0)):
        arbol(l, ax, az, y, rng)
    for bx, bz, e in ((56.0, 86.0, "x"), (64.0, 86.0, "x"), (56.0, 74.0, "x"), (64.0, 74.0, "x")):
        banco(l, bx, bz, y, e)
    for fx2, fz2 in ((20.0, 96.0), (48.0, 96.0), (72.0, 96.0), (100.0, 96.0), (34.0, 62.0), (86.0, 62.0)):
        farola(l, fx2, fz2, y)
    # coches abandonados y un carrito volcado
    coche(l, 100.0, 90.0, "z", y, rng)
    coche(l, 26.0, 78.0, "x", y, rng)
    l.escombros(84.0, 76.0, y, 2.0, 10, rng, mats=("fruta_naranja", "tablas", "toldo_rojo"))
    iglesia(l, rng)
    # EL ESTE DE LA PLAZA: casas hasta la ladera del cerro (tapan; no se pasa)
    fila(l, 104.0, 60.0, 112.0, 90.0, y, rng, ("-x",), pisos=(3, 4))
    l.caja(112.0, y - 1.0, 64.0, 160.0, y + 9.0, 90.0, "roca")               # relleno detras (no se ve)
    # el este, sobre el malecon: casas de pescadores con la fachada al mar (se ven desde el muelle y el barco)
    fila(l, 104.0, 90.0, 160.0, 98.0, y, rng, ("+z", "-x"), pisos=(2, 4))
    persiana_y_pasaje(l, rng, validacion)


def persiana_y_pasaje(l, rng, validacion):
    """LA FILA NORTE de la plaza con su pasaje (la persiana la pone el juego) y el camino del que trepa: el
    contenedor de basura, el quiosco y el balcon de la palanca."""
    x0, z0, x1, z1 = D.FILA_NORTE
    y = Y1
    pa0, _pz0, pa1, _pz1 = D.PASAJE
    b0, _bz0, b1, _bz1 = D.BALCON
    # las casas a los dos lados del pasaje (la del balcon, a mano: su balcon es el del puzzle)
    fila(l, x0, z0, pa0, z1, y, rng, ("+z",), pisos=(3, 4))
    casa(l, (pa1, z0, 63.0, z1), y, 3, rng, caras=(), tejado="tejas", color="fachada_salmon")
    _caja_cara(l, "+z", z1, pa1, 63.0, y, y + 0.9, 0.0, 0.06, "zocalo")
    for k in (1, 2):
        _caja_cara(l, "+z", z1, pa1, 63.0, y + k * D.PISO - 0.1, y + k * D.PISO + 0.05, 0.0, 0.07, "cornisa_clara")
    ventana(l, "+z", z1, 57.6, y + 2 * D.PISO + 0.9, rng, persiana="persiana_verde")
    ventana(l, "+z", z1, 61.2, y + 2 * D.PISO + 0.9, rng, balcon=True, persiana="persiana_verde")
    ventana(l, "+z", z1, 61.5, y + 1.0, rng, ancho=0.9, alto=1.3, persiana="persiana_verde")
    fila(l, 63.0, z0, x1, z1, y, rng, ("+z",), pisos=(3, 4))
    # EL PASAJE: bovedilla bajo la casa (4 x 3,4 m) de z 60 a z 50
    l.caja(pa0, y, z0 - 0.05, pa1, y + D.PASAJE_ALTO, z1 + 0.05, "sillar_arenisca", hueco=True)
    l.caja(pa0 - 0.4, y + D.PASAJE_ALTO, z1, pa1 + 0.4, y + D.PASAJE_ALTO + 0.4, z1 + 0.25, "sillar_arenisca")   # el arco
    l.caja(pa0, y - 0.2, z0, pa1, y, z1, "adoquin")
    l.caja(pa0 + 0.2, y + D.PASAJE_ALTO - 0.15, z0 + 4.8, pa1 - 0.2, y + D.PASAJE_ALTO, z0 + 5.2, "hierro")
    l.luz((pa0 + pa1) / 2, y + D.PASAJE_ALTO - 0.4, z0 + 5.0, CALIDA, 0.7, 7.0)
    # la guia de la persiana (sus carriles y la caja de arriba: la hoja la pone el juego)
    for xx in (pa0 - 0.12, pa1 + 0.02):
        l.caja(xx, y, z1 - 0.1, xx + 0.1, y + D.PASAJE_ALTO, z1 + 0.05, "hierro")
    l.caja(pa0 - 0.15, y + D.PASAJE_ALTO, z1 - 0.2, pa1 + 0.15, y + D.PASAJE_ALTO + 0.45, z1 + 0.3, "hierro")
    # EL BALCON DE LA PALANCA (primer piso de la casa de al lado), su puerta tapiada y la caja de la persiana
    by = D.BALCON_Y
    l.caja(b0, by - 0.2, z1, b1, by, D.BALCON[3], "cornisa_clara")
    h0, h1 = D.BALCON_HUECO
    barandilla(l, b0, D.BALCON[3] - 0.06, h0, D.BALCON[3], by, 1.0)
    barandilla(l, h1, D.BALCON[3] - 0.06, b1, D.BALCON[3], by, 1.0)
    barandilla(l, b0, z1, b0 + 0.06, D.BALCON[3], by, 1.0)
    barandilla(l, b1 - 0.06, z1, b1, D.BALCON[3], by, 1.0)
    l.caja(b0 + 1.0, by, z1 - 0.2, b0 + 2.2, by + 2.3, z1 + 0.02, "puerta_verde")
    px, _py, pz = D.PALANCA
    l.caja(px - 0.35, by + 0.8, z1 - 0.02, px + 0.35, by + 1.6, z1 + 0.18, "chapa_amarilla")    # la caja electrica
    # EL CAMINO DEL QUE TREPA: el contenedor de basura (1,3) y el quiosco (2,6) debajo del balcon
    q0, qz0, q1, qz1 = D.QUIOSCO
    l.caja(q0, y, qz0, q1, y + D.QUIOSCO_ALTO, qz1, "metal_verde")
    l.caja(q0 - 0.2, y + D.QUIOSCO_ALTO, qz0 - 0.2, q1 + 0.2, y + D.QUIOSCO_ALTO + 0.15, qz1 + 0.2, "hierro")
    l.caja(q0 + 0.3, y + 1.0, qz1 - 0.02, q1 - 0.3, y + 2.0, qz1 + 0.02, "vidrio_ventana")
    l.caja(q0 + 0.2, y + 2.05, qz1, q1 - 0.2, y + 2.45, qz1 + 0.06, "cartel_amarillo")          # PRENSA
    c0, cz0, c1, cz1 = D.CONTENEDOR_BASURA
    l.caja(c0, y, cz0, c1, y + 1.3, cz1, "fachada_verde")
    l.caja(c0 - 0.05, y + 1.3, cz0 - 0.05, c1 + 0.05, y + 1.38, cz1 + 0.05, "hierro")
    # ropa tendida sobre la plaza, de balcon a balcon
    tendedero(l, 30.0, 60.2, 30.0, 70.0, y + 7.0, rng)
    tendedero(l, 80.0, 60.2, 84.0, 66.0, y + 6.8, rng)


# ======================================================================================================
# 3. LA CUESTA, EL MIRADOR, LA CHIMENEA Y EL BARRANCO
# ======================================================================================================
def cuesta(l, rng):
    cx0, cz0, cx1, cz1 = D.CUESTA
    za, zb = D.CUESTA_Z
    # casas escalonadas a los dos lados, siguiendo la pendiente (se apoyan en la roca de la ladera)
    for i, (z_a, z_b) in enumerate(((30.0, 36.0), (36.0, 42.0), (42.0, 50.0))):
        yy = Y1 + (Y2 - Y1) * (zb - z_b) / (zb - za)
        casa(l, (cx0 - 8.0, z_a, cx0, z_b), max(Y1, yy), 3, rng, caras=("+x",), tejado="tejas")
        casa(l, (cx1, z_a, cx1 + 8.0, z_b), max(Y1, yy), 3, rng, caras=("-x",), tejado="tejas")
    # barandilla central y macetas en los peldaños
    for i in range(0, 30, 3):
        z = zb - (zb - za) * i / 30 - 0.4
        yy = Y1 + (Y2 - Y1) * (i + 1) / 30
        l.caja(cx0 + 0.1, yy, z - 0.3, cx0 + 0.5, yy + 0.35, z, "ladrillo_visto")
        l.elipsoide(cx0 + 0.3, yy + 0.45, z - 0.15, 0.25, 0.2, 0.2, rng.choice(("flores_rojas", "flores_violeta", "hojas")))
    tendedero(l, cx0, 44.0, cx1, 45.0, Y1 + 6.0, rng)
    tendedero(l, cx0, 36.0, cx1, 35.0, Y1 + 8.5, rng)


def mirador(l, rng, validacion):
    x0, z0, x1, z1 = D.MIRADOR
    y = Y2
    # casas al fondo (norte) y la balaustrada sobre la plaza (sur)
    fila(l, x0, z0, 48.0, z0 + 8.0, y, rng, ("+z",), pisos=(2, 3))
    barandilla(l, x0, 27.6, 48.0, 27.7, y, 1.05)
    barandilla(l, 56.0, 27.6, x1, 27.7, y, 1.05)
    for bx in (24.0, 32.0, 40.0):
        banco(l, bx, 26.6, y)
    for ax, az in ((20.0, 20.0), (36.0, 18.0), (44.0, 22.0)):
        arbol(l, ax, az, y, rng, alto=6.5)
    farola(l, 28.0, 22.0, y)
    farola(l, 58.0, 22.0, y)
    # LA VIEJA CONSERVERA: nave de ladrillo visto con su chimenea al borde del barranco
    l.caja(52.0, y - 1.0, z0, 66.0, y + 7.0, 12.0, "ladrillo_visto")
    for xx in (54.0, 58.0, 62.0):
        l.caja(xx, y + 3.0, 11.9, xx + 1.6, y + 5.6, 12.1, "vidrio_ventana")
    l.caja(52.0, y + 7.0, z0, 66.0, y + 7.3, 12.0, "teja")
    l.caja(54.0, y + 5.8, 12.0, 64.0, y + 6.6, 12.25, "cartel_blanco")          # CONSERVAS
    l.caja(55.0, y + 6.0, 12.25, 63.0, y + 6.4, 12.3, "letras")
    # EL PIE DE LA CHIMENEA: ladrillo, cuadrado, 2,2 m (la chimenea la pone el juego encima)
    bx0, bz0, bx1, bz1 = D.CHIMENEA_BASE
    if not validacion:
        l.caja(bx0, y, bz0, bx1, y + D.CHIMENEA_BASE_ALTO, bz1, "ladrillo_visto")
        # HUECA, como una chimenea de verdad (el tiro por dentro): un anillo de ladrillo de 0,5 m. Y con una
        # GRIETA ya abierta en la cara del barranco: tumbarla cuesta unas decenas de tiros, no cientos
        l.caja(bx0 + 0.5, y + 0.3, bz0 + 0.5, bx1 - 0.5, y + D.CHIMENEA_BASE_ALTO - 0.3, bz1 - 0.5, "ladrillo_visto", hueco=True)
        l.caja(bx1 - 0.55, y + 0.7, bz0 + 0.3, bx1 + 0.05, y + 1.1, bz1 - 0.3, "ladrillo_visto", hueco=True)
        l.caja(bx0 - 0.1, y + D.CHIMENEA_BASE_ALTO - 0.2, bz0 - 0.1, bx1 + 0.1, y + D.CHIMENEA_BASE_ALTO, bz1 + 0.1, "cornisa_clara")
        # las grietas pintadas y el cartel de peligro del pie (el juego pone "REVENTAD")
        l.caja(bx0 - 0.02, y + 0.6, bz0 + 0.4, bx0, y + 1.8, bz0 + 0.6, "peligro")
    else:
        # la chimenea tumbada: una pasarela de voxels de lado a lado del barranco
        l.caja(bx1, y, 15.0, D.BARRANCO[2] + 3.0, y + 0.4, 16.6, "ladrillo_visto")
    # el borde del barranco: asfalto roto, una valla caida
    bx0b, bz0b, bx1b, bz1b = D.BARRANCO
    for zz in range(int(bz0b) + 1, int(bz1b) - 1, 3):
        if 13 <= zz <= 19:
            continue
        l.caja(bx0b - 0.3, y, zz, bx0b - 0.1, y + 1.0, zz + 2.0, "peligro")
    l.escombros((bx0b + bx1b) / 2, 20.0, Y1, 3.0, 26, rng, mats=("adoquin", "roca", "hierro"))
    l.escombros((bx0b + bx1b) / 2, 30.0, Y1, 2.5, 14, rng, mats=("adoquin", "chapa_blanca"))
    for zz in (10.0, 26.0):         # las tuberias reventadas
        l.linea(bx0b, Y1 + 2.2, zz, bx1b, Y1 + 1.4, zz + 0.5, 0.18, "hierro")
    # LA SALIDA DEL BARRANCO (solo hacia el oeste): una rampa de escombros por si alguien se cae
    l.cuna(bx0b, Y1, 34.0, bx0b + 7.0, Y2, 40.0, sube_hacia="-x", mat="roca")


# ======================================================================================================
# 4. LA CALLE ALTA, EL REFUGIO, EL GENERADOR Y EL MONTACARGAS
# ======================================================================================================
def calle_alta(l, rng):
    y = Y2
    # casas a los dos lados de la calle (z 4..10 al norte; al sur, hasta el refugio)
    fila(l, 79.0, 4.0, D.ACANTILADO_X, 10.0, y, rng, ("+z",), pisos=(3, 4), bajo="tienda")
    fila(l, 79.0, 24.0, 92.0, 46.0, y, rng, ("-z", "+x"), pisos=(3, 4))
    for fx, fz in ((84.0, 11.0), (100.0, 11.0), (116.0, 11.0), (90.0, 23.0)):
        farola(l, fx, fz, y)
    coche(l, 88.0, 20.0, "x", y, rng)
    coche(l, 110.0, 13.0, "x", y, rng)
    l.escombros(104.0, 18.0, y, 1.5, 8, rng)
    tendedero(l, 96.0, 10.0, 97.0, 24.0, y + 7.5, rng)


def refugio(l, rng):
    x0, z0, x1, z1 = D.REFUGIO
    y = Y2
    top = y + 3.6
    l.caja(x0, y - 1.0, z0, x1, top, z1, "fachada_crema")
    l.caja(x0 + 0.35, y, z0 + 0.35, x1 - 0.35, top - 0.3, z1 - 0.35, "fachada_crema", hueco=True)
    l.caja(x0 + 0.35, y - 0.2, z0 + 0.35, x1 - 0.35, y, z1 - 0.35, "baldosa_plaza")
    for (px, pz), cara in ((D.REFUGIO_PUERTA_N, "z"), (D.REFUGIO_PUERTA_E, "x")):
        if cara == "z":
            l.caja(px - 0.9, y, pz - 0.5, px + 0.9, y + 2.7, pz + 0.5, "fachada_crema", hueco=True)
            l.caja(px - 1.1, y + 2.7, pz - 0.5, px + 1.1, y + 2.9, pz + 0.1, "puerta_roja")
        else:
            l.caja(px - 0.5, y, pz - 0.9, px + 0.5, y + 2.7, pz + 0.9, "fachada_crema", hueco=True)
            l.caja(px - 0.1, y + 2.7, pz - 1.1, px + 0.5, y + 2.9, pz + 1.1, "puerta_roja")
    # la panaderia: mostrador, estanterias con pan, el horno, camas improvisadas
    l.caja(x0 + 1.0, y, z0 + 3.0, x0 + 1.8, y + 1.1, z1 - 2.0, "tablas")
    for zz in range(int(z0) + 3, int(z1) - 2, 2):
        l.caja(x0 + 0.4, y + 1.0, zz, x0 + 0.8, y + 2.4, zz + 1.6, "tablas")
    l.caja(x1 - 3.0, y, z1 - 2.6, x1 - 0.4, y + 2.2, z1 - 0.4, "ladrillo_visto")        # el horno
    K.cama(l, x1 - 3.2, z0 + 1.0, y, "x", rng)
    K.mesa(l, (x0 + x1) / 2, (z0 + z1) / 2, y)
    # el cartel de la panaderia y el toldo
    tienda_cara = "-z"
    _caja_cara(l, tienda_cara, z0, x0 + 1.0, x1 - 1.0, y + 2.9, y + 3.4, 0.0, 0.12, "cartel_amarillo")
    _caja_cara(l, tienda_cara, z0, x0 + 2.0, x1 - 2.0, y + 3.0, y + 3.3, 0.12, 0.14, "letras")
    l.luz((x0 + x1) / 2, top - 0.6, (z0 + z1) / 2, CALIDA, 1.0, 11.0)
    l.luz(x1 - 2.0, y + 1.2, z1 - 1.5, (255, 120, 50), 0.8, 5.0)        # el horno aun caliente


def montacargas(l, rng, validacion):
    y = Y2
    # el patio: suelo de hormigon, bidones, bobinas de cable, marcas amarillas
    px0, pz0, px1, pz1 = D.PATIO_MONTACARGAS
    l.caja(px0, y - 0.2, pz0, px1, y, pz1, "suelo_hormigon")
    fila(l, 104.0, 44.0, 124.0, 50.0, y, rng, ("-z",), pisos=(3, 3))
    for bx, bz in ((106.0, 40.0), (106.8, 40.5), (107.5, 39.6), (118.0, 44.0)):
        l.cilindro(bx, y, bz, 0.35, 0.95, rng.choice(("chapa_azul", "chapa_amarilla", "chapa_roja")))
    for bx, bz in ((108.0, 27.0), (116.0, 26.0)):
        l.cilindro(bx, y + 0.9, bz, 0.9, 0.5, "tablas", eje="x")
    # LA CASETA DEL GENERADOR (su boton en la cara sur; el ruido lo pone el juego)
    gx0, gz0, gx1, gz1 = D.GENERADOR
    l.caja(gx0, y - 0.3, gz0, gx1, y + 3.0, gz1, "chapa_amarilla")
    l.caja(gx0 + 0.2, y, gz0 + 0.2, gx1 - 0.2, y + 2.8, gz1 - 0.2, "chapa_amarilla", hueco=True)
    l.caja(gx0 + 1.8, y, gz0 - 0.1, gx1 - 1.8, y + 2.6, gz0 + 0.3, "chapa_amarilla", hueco=True)   # la puerta
    l.caja(gx0 + 1.0, y, gz0 + 1.5, gx1 - 1.0, y + 1.6, gz1 - 1.2, "metal_verde")     # el grupo electrogeno
    l.cilindro(gx1 - 1.2, y + 1.6, gz1 - 1.6, 0.18, 2.0, "hierro")                    # el escape
    gbx, _gby, gbz = D.GENERADOR_BOTON
    l.caja(gbx - 0.4, y + 0.9, gz0 - 0.15, gbx + 0.4, y + 1.7, gz0, "cartel_blanco")
    l.caja(gbx - 0.12, y + 1.15, gz0 - 0.2, gbx + 0.12, y + 1.4, gz0 - 0.15, "fruta_roja")
    # EL POZO DEL MONTACARGAS: una torre de vigas contra la roca, de Y2 a Y3 + la sala de maquinas
    qx0, qz0, qx1, qz1 = D.POZO
    top = Y3 + 4.0
    for xx, zz in ((qx0, qz0), (qx0, qz1 - 0.3), (qx1 - 0.3, qz0), (qx1 - 0.3, qz1 - 0.3)):
        l.caja(xx, y, zz, xx + 0.3, top, zz + 0.3, "chapa_amarilla")
    for k in range(1, 6):
        yy = y + k * (top - y) / 6
        l.caja(qx0, yy, qz0, qx1, yy + 0.18, qz0 + 0.12, "chapa_amarilla")
        l.caja(qx0, yy, qz1 - 0.12, qx1, yy + 0.18, qz1, "chapa_amarilla")
        l.linea(qx0 + 0.15, yy - (top - y) / 6, qz0 + 0.06, qx1 - 0.15, yy, qz0 + 0.06, 0.08, "chapa_amarilla")
        l.linea(qx0 + 0.15, yy - (top - y) / 6, qz1 - 0.06, qx1 - 0.15, yy, qz1 - 0.06, 0.08, "chapa_amarilla")
    l.caja(qx0 - 0.3, top, qz0 - 0.3, qx1 + 1.5, top + 2.6, qz1 + 0.3, "chapa_blanca")   # sala de maquinas
    l.cilindro((qx0 + qx1) / 2, top + 0.6, (qz0 + qz1) / 2, 0.9, 1.2, "hierro", eje="z")                                     # el torno
    # el arranque de abajo: suelo de chapa, franjas de peligro, la botonera
    l.caja(qx0, y - 0.2, qz0, qx1, y, qz1, "peligro")
    bbx, _bby, bbz = D.CABINA_BOTON
    l.caja(bbx - 0.3, y + 1.0, bbz - 0.2, bbx, y + 1.6, bbz + 0.2, "cartel_amarillo")
    # LA VARIANTE DE VALIDACION: una escalera de Y2 a Y3 pegada a la pared de roca (en el juego, el montacargas)
    if validacion:
        n = 60
        for i in range(n):
            x = 104.0 + i * (20.0 / n)
            l.caja(x, y, 24.2, x + 20.0 / n + 0.02, y + (Y3 - y) * (i + 1) / n, 26.0, "roca")


def acantilado(l, rng):
    """La pared de roca entre Y2 y Y3: matas de hierba, un muro de contencion viejo y las raices de un pino."""
    x = D.ACANTILADO_X
    for zz in range(6, 62, 5):
        if 26 <= zz <= 36:
            continue
        l.elipsoide(x - 0.2, Y2 + 3.0 + (zz * 7) % 8, zz, 0.6, 0.4, 1.1, rng.choice(("hojas", "cesped")))
    arbol(l, x + 3.0, 10.0, Y3, rng, alto=7.0)
    arbol(l, x + 4.0, 54.0, Y3, rng, alto=6.0)


# ======================================================================================================
# 5. LA CIUDADELA: FOSO, PUENTE LEVADIZO, PLAZA DE ARMAS, RADIO Y HELIPUERTO
# ======================================================================================================
def almenas(l, x0, z0, x1, z1, y):
    largo = max(x1 - x0, z1 - z0)
    n = int(largo / 1.2)
    for k in range(n):
        if k % 2:
            continue
        if (x1 - x0) >= (z1 - z0):
            l.caja(x0 + k * 1.2, y, z0, x0 + k * 1.2 + 0.8, y + 0.9, z1, "sillar_gris")
        else:
            l.caja(x0, y, z0 + k * 1.2, x1, y + 0.9, z0 + k * 1.2 + 0.8, "sillar_gris")


def ciudadela(l, rng, validacion):
    x0, z0, x1, z1 = D.CIUDADELA
    y = Y3
    h = D.MURALLA_ALTO
    # las murallas (2 m de grueso) y el camino de ronda
    for rect in ((x0, z0, x0 + 2.0, z1), (x1 - 2.0, z0, x1, z1), (x0, z0, x1, z0 + 2.0), (x0, z1 - 2.0, x1, z1)):
        l.caja(rect[0], y - 1.0, rect[1], rect[2], y + h, rect[3], "sillar_gris")
    almenas(l, x0, z0, x0 + 0.6, z1, y + h)
    almenas(l, x0, z0, x1, z0 + 0.6, y + h)
    almenas(l, x0, z1 - 0.6, x1, z1, y + h)
    almenas(l, x1 - 0.6, z0, x1, z1, y + h)
    # torres redondas en las esquinas
    for tx, tz in ((x0 + 1.0, z0 + 1.0), (x0 + 1.0, z1 - 1.0), (x1 - 1.0, z0 + 1.0), (x1 - 1.0, z1 - 1.0)):
        l.cilindro(tx, y - 1.0, tz, 2.6, h + 3.0, "sillar_gris")
        l.cilindro(tx, y + h + 2.0, tz, 2.9, 0.4, "cornisa_clara")
    # EL TORREON DE LA PUERTA (mira al foso) con el hueco del puente y la TRANCA
    gz0, gz1 = D.PUENTE[1], D.PUENTE[3]
    l.caja(x0 - 1.0, y - 1.0, gz0 - 3.0, x0 + 4.0, y + h + 3.0, gz1 + 3.0, "sillar_gris")
    l.caja(x0 - 1.1, y, gz0, x0 + 4.1, y + 4.5, gz1, "sillar_gris", hueco=True)
    almenas(l, x0 - 1.0, gz0 - 3.0, x0 - 0.4, gz1 + 3.0, y + h + 3.0)
    # la tranca: la viga de madera que asoma del torreon sobre el foso y aguanta el contrapeso
    t = D.TRANCA
    if not validacion:
        l.caja(t[0], t[1], t[2], t[3], t[4], t[5], "tronco")
        l.caja(t[0], t[1] - 0.25, t[2] - 0.02, t[0] + 0.4, t[1] + 0.02, t[5] + 0.02, "peligro")   # donde cuelga la cadena
        # las poleas del torreon por donde pasan las cadenas del puente
        for zz in (D.PUENTE[1] + 0.6, D.PUENTE[3] - 0.6):
            l.cilindro(x0 - 1.0, y + 5.4, zz, 0.35, 0.3, "hierro", eje="x")
    # la variante de validacion: el puente ya bajado (voxels)
    px0, pz0, px1, pz1 = D.PUENTE
    if validacion:
        l.caja(px0, y - 0.3, pz0, px1 + 0.3, y, pz1, "tablas")
    # dentro: la plaza de armas
    # la caseta de la radio con su antena de celosia
    rx, _ry, rz = D.RADIO
    l.caja(rx - 3.0, y - 0.3, rz - 3.0, rx + 3.0, y + 3.2, rz + 2.0, "fachada_cal")
    l.caja(rx - 2.7, y, rz - 2.7, rx + 2.7, y + 2.9, rz + 1.7, "fachada_cal", hueco=True)
    l.caja(rx - 0.8, y, rz + 1.6, rx + 0.8, y + 2.4, rz + 2.1, "fachada_cal", hueco=True)
    l.caja(rx - 2.0, y, rz - 2.6, rx + 2.0, y + 1.1, rz - 1.8, "metal_verde")          # los equipos
    l.caja(rx - 3.2, y + 3.2, rz - 3.2, rx + 3.2, y + 3.4, rz + 2.2, "peligro")
    ax, az = rx + 5.0, rz - 1.0
    for k in range(12):                       # la antena: 14 m de celosia roja y blanca
        yy = y + k * 1.2
        m = "fruta_roja" if k % 2 == 0 else "cartel_blanco"
        l.caja(ax - 0.4, yy, az - 0.4, ax + 0.4, yy + 1.2, az + 0.4, m)
        l.caja(ax - 0.3, yy, az - 0.3, ax + 0.3, yy + 1.2, az + 0.3, m, hueco=True)
    l.caja(ax - 0.1, y + 14.4, az - 0.1, ax + 0.1, y + 16.0, az + 0.1, "hierro")
    # EL HELIPUERTO: hormigon con su H y el circulo
    hx, _hy, hz = D.HELIPUERTO
    l.cilindro(hx, y - 0.05, hz, 6.0, 0.1, "suelo_hormigon")
    l.caja(hx - 1.6, y + 0.04, hz - 2.2, hx - 1.0, y + 0.06, hz + 2.2, "pintura_blanca")
    l.caja(hx + 1.0, y + 0.04, hz - 2.2, hx + 1.6, y + 0.06, hz + 2.2, "pintura_blanca")
    l.caja(hx - 1.0, y + 0.04, hz - 0.3, hx + 1.0, y + 0.06, hz + 0.3, "pintura_blanca")
    # cañones viejos, un pozo, banderas, sacos terreros del ultimo que resistio aqui
    for cx, cz in ((144.0, 12.0), (144.0, 56.0)):
        l.cilindro(cx, y + 0.8, cz, 0.35, 2.4, "hierro", eje="x")
        l.cilindro(cx + 0.4, y + 0.5, cz - 0.6, 0.5, 0.2, "tronco", eje="z")
        l.cilindro(cx + 0.4, y + 0.5, cz + 0.6, 0.5, 0.2, "tronco", eje="z")
    l.cilindro(152.0, y, 30.0, 1.2, 0.9, "sillar_gris")
    l.cilindro(152.0, y + 0.1, 30.0, 0.95, 0.81, "agua_fuente")
    for sx, sz in ((146.0, 40.0), (147.0, 41.0), (156.0, 24.0), (155.0, 25.0)):
        l.caja(sx, y, sz, sx + 1.4, y + 0.9, sz + 0.6, "sacos")
    l.caja(142.0, y, 20.0, 143.0, y + 6.0, 20.2, "tronco")                   # el mastil
    l.caja(143.0, y + 4.6, 20.0, 145.0, y + 5.8, 20.08, "fachada_azul")      # la bandera
    # el rellano de arriba del acantilado: una caseta y un cartel "CIUDADELA"
    lx0, lz0, lx1, lz1 = D.LLEGADA
    barandilla(l, D.FOSO[0] - 0.4, lz0 - 10.0, D.FOSO[0] - 0.3, D.PUENTE[1] - 0.2, y, 1.0)
    barandilla(l, D.FOSO[0] - 0.4, D.PUENTE[3] + 0.2, D.FOSO[0] - 0.3, lz1 + 10.0, y, 1.0)
    l.caja(128.0, y, 20.0, 129.0, y + 2.0, 20.2, "tronco")
    l.caja(127.2, y + 1.3, 20.2, 129.8, y + 2.0, 20.3, "cartel_blanco")


def construir(l, rng, validacion=False):
    terreno(l, validacion)
    muelle(l, rng, validacion)
    plaza(l, rng, validacion)
    cuesta(l, rng)
    mirador(l, rng, validacion)
    calle_alta(l, rng)
    refugio(l, rng)
    montacargas(l, rng, validacion)
    acantilado(l, rng)
    ciudadela(l, rng, validacion)
    # pistas de salida de criaturas en cada terraza (la validacion se queda con las alcanzables)
    for p in D.RUTA:
        l.punto(p[0], p[1], p[2], "ruta")
    for x, y, z in ((30.0, Y1, 66.0), (90.0, Y1, 84.0), (24.0, Y2, 14.0), (40.0, Y2, 12.0), (100.0, Y2, 14.0),
                    (118.0, Y2, 40.0), (130.0, Y3, 50.0), (130.0, Y3, 12.0), (150.0, Y3, 26.0), (148.0, Y3, 56.0),
                    (80.0, Y0, 106.0), (130.0, Y0, 106.0)):
        l.punto(x, y, z, "criatura")
