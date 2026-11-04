"""LAS ARMAS DE BREACH, modeladas pieza a pieza.

Catorce armas de fuego, cada una con su silueta, su material y SU PROPIA MIRA soldada de fabrica
(no hay taller de accesorios: lo que ves montado es lo que lleva). Todo a tamaño real en metros,
apuntando a +Y de Blender, que en Godot es -Z.

Cada funcion devuelve la ficha del arma: donde van las manos, donde acaba el cañon y -lo importante-
DONDE ESTA EL EJE DE SU MIRA, que es el punto que el juego alinea con el centro de la pantalla al
apuntar (player.gd). Si ese punto esta bien puesto, la reticula cae exactamente donde va la bala.

COMO SE APILA UN ARMA (de arriba abajo), que es lo que hace que se lea como un arma y no como un
monton de cajas pegadas:
    riel / mira          z +0.036 .. +0.050
    cajon superior       z -0.012 .. +0.036      <- por aqui va el anima del cañon
    cajon inferior       z -0.038 .. -0.012
    guardamonte y puño   cuelgan de z -0.038     <- el hueco del dedo tiene que VERSE
    pozo del cargador    z -0.038 .. -0.080
Cada familia lo estira o lo encoge, pero el orden no cambia.
"""
import math
from mathutils import Vector
from piezas import (M, caja, cuna, cil, tubo, esfera, perfil, barrido, marco, riel, estrias,
                    guardamonte, empunadura, cristal, cristal_plano, reticula_punto, reticula_cruz,
                    reticula_anillo, tornillo, anilla, mira_hierro, mira_diopter, mira_punto,
                    mira_holo, mira_prisma, mira_telescopica, mira_pgo, accesorio)


# ---------------------------------------------------------------------------
# SECCIONES Y SUBCONJUNTOS QUE SE REPITEN
# ---------------------------------------------------------------------------
def sec(ancho, alto, r=0.004):
    """Seccion rectangular con las esquinas cortadas: es lo que tiene un cajon de mecanismos real,
    y de lejos es justo lo que separa una pieza mecanizada de un ladrillo."""
    a, b = ancho * 0.5, alto * 0.5
    return [(-a + r, -b), (a - r, -b), (a, -b + r), (a, b - r), (a - r, b), (-a + r, b), (-a, b - r), (-a, -b + r)]


def sec_octo(ancho, alto):
    a, b = ancho * 0.5, alto * 0.5
    c = 0.34
    return [(-a * c, -b), (a * c, -b), (a, -b * c), (a, b * c), (a * c, b), (-a * c, b), (-a, b * c), (-a, -b * c)]


def bloque(ancho, y0, y1, z0, z1, mat, r=0.005, nombre="bloque"):
    """Un tramo del arma dado por sus limites, no por su centro: asi se encadenan cajon, pozo y
    guardamanos sin dejar aire entre ellos ni meterse uno dentro de otro."""
    return perfil(sec(ancho, y1 - y0, r), z1 - z0, (0, (y0 + y1) * 0.5, (z0 + z1) * 0.5), mat,
                  eje='Z', nombre=nombre)


@accesorio
def apagallamas(y, z, r=0.0092, mat=None):
    """APAGALLAMAS DE JAULA (A2): el cono con las cuatro ranuras. 5 cm que se ven en cuanto sacas el
    arma por una esquina."""
    mat = mat or M("pavonado")
    cil(r + 0.0032, 0.050, (0, y + 0.025, z), mat, eje='Y', seg=18, bisel=0.0006, nombre="jaula")
    cil(r * 0.72, 0.054, (0, y + 0.025, z), M("goma"), eje='Y', seg=14, bisel=0.0, nombre="anima")
    for a in (0, 60, 120, 240, 300):
        caja((0.0026, 0.030, r * 2.6), (0, y + 0.029, z), mat, rot=(0, a, 0), bisel=0.0004, nombre="ranura_jaula")
    cil(r + 0.0042, 0.008, (0, y + 0.004, z), M("acero"), eje='Y', seg=18, bisel=0.0006, nombre="aro_jaula")
    return y + 0.050


@accesorio
def freno_boca(y, z, r=0.0105, mat=None):
    """FRENO DE BOCA de tres camaras: el de los fusiles pesados, que escupe el gas a los lados."""
    mat = mat or M("pavonado")
    cil(r + 0.0038, 0.060, (0, y + 0.030, z), mat, eje='Y', seg=16, bisel=0.0008, nombre="freno")
    for i in range(3):
        caja((r * 2.9, 0.0055, r * 1.4), (0, y + 0.012 + i * 0.017, z), M("goma"), bisel=0.0, nombre="camara")
    cil(r * 0.70, 0.064, (0, y + 0.030, z), M("goma"), eje='Y', seg=14, bisel=0.0, nombre="anima")
    return y + 0.060


@accesorio
def silenciador(y, z, r=0.0215, largo=0.185, mat=None):
    """SILENCIADOR: tubo gordo con sus anillos. Alarga el arma un palmo, que es lo que se nota al
    asomarla por una puerta."""
    mat = mat or M("pavonado")
    cil(r, largo, (0, y + largo * 0.5, z), mat, eje='Y', seg=24, bisel=0.0010, nombre="silenciador")
    for i in range(5):
        cil(r + 0.0012, 0.005, (0, y + 0.018 + i * (largo - 0.04) / 4.0, z), M("acero"), eje='Y',
            seg=24, bisel=0.0004, nombre="anillo_sil")
    cil(r * 0.42, largo + 0.006, (0, y + largo * 0.5, z), M("goma"), eje='Y', seg=16, bisel=0.0, nombre="anima")
    cil(r * 0.86, 0.012, (0, y + 0.006, z), M("acero"), eje='Y', seg=20, bisel=0.0006, nombre="rosca_sil")
    return y + largo


def culata_telescopica(y0, z, mat=None, largo=0.150, ancho=0.046):
    """CULATA TELESCOPICA: tubo amortiguador, cuerpo con carrillera, hueco para la mano y cantonera
    de goma. Devuelve donde acaba por detras."""
    mat = mat or M("polimero")
    cil(0.0158, largo + 0.045, (0, y0 - (largo + 0.045) * 0.5 + 0.012, z), M("aluminio"), eje='Y',
        seg=18, bisel=0.0008, nombre="tubo_amortiguador")
    for i in range(6):
        cil(0.0178, 0.005, (0, y0 - 0.028 - i * 0.019, z), M("aluminio"), eje='Y', seg=18,
            bisel=0.0004, nombre="muesca_tubo")
    yc = y0 - largo
    # cuerpo de la culata: de la mitad del tubo a la cantonera
    perfil(sec(ancho, 0.115, 0.008), 0.056, (0, yc + 0.046, z + 0.002), mat, eje='Z', nombre="cuerpo_culata")
    perfil(sec(ancho * 0.62, 0.090, 0.006), 0.020, (0, yc + 0.040, z + 0.038), mat, eje='Z', nombre="carrillera")
    # patilla inferior: el hueco por donde entra la mano al disparar tumbado
    caja((ancho * 0.72, 0.070, 0.020), (0, yc + 0.012, z - 0.040), mat, rot=(16, 0, 0), bisel=0.0025,
         nombre="patilla")
    caja((ancho, 0.024, 0.104), (0, yc - 0.014, z - 0.008), mat, rot=(-5, 0, 0), bisel=0.0030, nombre="pala")
    caja((ancho + 0.002, 0.013, 0.106), (0, yc - 0.030, z - 0.009), M("goma"), rot=(-5, 0, 0),
         bisel=0.0030, nombre="cantonera")
    caja((0.028, 0.032, 0.014), (0, yc + 0.030, z - 0.030), mat, bisel=0.0012, nombre="palanca_culata")
    anilla((ancho * 0.5, yc + 0.020, z - 0.022), r=0.006, rot=(0, 90, 0))
    return yc - 0.037


def pozo_cargador(y0, y1, z_alto, z_bajo, mat=None, ancho=0.036):
    """El POZO del cargador entre dos alturas, con la boca acampanada abajo. Sin el, el cargador
    parece pegado con cinta a la panza del arma."""
    mat = mat or M("aluminio")
    bloque(ancho, y0, y1, z_bajo, z_alto, mat, r=0.005, nombre="pozo")
    bloque(ancho + 0.007, y0 - 0.004, y1 + 0.004, z_bajo - 0.011, z_bajo, mat, r=0.006, nombre="boca_pozo")
    caja((0.018, 0.014, 0.013), (0.020, y0 + 0.004, z_alto - 0.012), mat, bisel=0.0010, nombre="boton_cargador")


@accesorio
def cargador_curvo(seat, largo=0.175, curva=26.0, ancho=0.026, fondo=0.070, mat=None, n=6):
    """CARGADOR CURVADO. Sale de `seat` hacia abajo curvandose HACIA LA BOCA, que es como se curva
    el de un fusil de verdad: es esa curva la que se reconoce de lejos."""
    mat = mat or M("polimero")
    s = sec(ancho, fondo, 0.005)
    marcos = []
    for k in range(n + 1):
        t = k / float(n)
        ang = curva * t * t
        dy = largo * t * math.sin(math.radians(curva * t * 0.55))
        marcos.append(marco((seat[0], seat[1] + dy, seat[2] - largo * t), rot=(ang, 0, 0),
                            escala=1.0 - 0.06 * t))
    ob = barrido(s, marcos, mat, nombre="Cargador")
    fin = marcos[-1].to_translation()
    caja((ancho + 0.004, fondo + 0.006, 0.009), (fin.x, fin.y, fin.z - 0.003), M("goma"),
         rot=(curva, 0, 0), bisel=0.0015, nombre="Cargador_base")
    for i in range(3):
        p = marcos[0].to_translation().lerp(fin, 0.32 + i * 0.18)
        caja((ancho + 0.002, 0.006, 0.004), (p.x, p.y + fondo * 0.30, p.z), M("acero"),
             bisel=0.0004, nombre="Cargador_nervio")
    return ob


@accesorio
def cargador_recto(seat, largo=0.13, ancho=0.026, fondo=0.062, mat=None, inclina=0.0, base=True):
    mat = mat or M("polimero")
    s = sec(ancho, fondo, 0.005)
    a = math.radians(inclina)
    marcos = [marco((seat[0], seat[1] + math.sin(a) * largo * t, seat[2] - math.cos(a) * largo * t),
                    rot=(inclina, 0, 0)) for t in (0.0, 0.5, 1.0)]
    ob = barrido(s, marcos, mat, nombre="Cargador")
    fin = marcos[-1].to_translation()
    if base:
        caja((ancho + 0.005, fondo + 0.006, 0.009), (fin.x, fin.y, fin.z - 0.003), M("goma"),
             rot=(inclina, 0, 0), bisel=0.0015, nombre="Cargador_base")
    for i in range(3):
        p = marcos[0].to_translation().lerp(fin, 0.30 + i * 0.20)
        caja((ancho + 0.002, 0.005, 0.0035), (p.x, p.y + fondo * 0.30, p.z), M("acero"),
             bisel=0.0004, nombre="Cargador_nervio")
    return ob


def canon(y0, y1, z, r=0.0088, mat=None, estriado=False):
    mat = mat or M("pavonado")
    cil(r, y1 - y0, (0, (y0 + y1) * 0.5, z), mat, eje='Y', seg=18, bisel=0.0006, nombre="canon")
    if estriado:
        for i in range(6):
            cil(r + 0.0013, 0.010, (0, y0 + 0.04 + i * 0.032, z), mat, eje='Y', seg=18,
                bisel=0.0004, nombre="acanaladura")


# ---------------------------------------------------------------------------
# 1. CARABINA 5.56 — plataforma AR, flat-top con optica de prisma. El arma de partida.
# ---------------------------------------------------------------------------
def carabina_556():
    al, po = M("aluminio"), M("polimero")
    Z_BORE = 0.014
    bloque(0.044, -0.078, 0.150, -0.012, 0.036, al, nombre="upper")
    # EL GRUPO DEL GATILLO, 2,4 CM MAS ADELANTE (2026-09-29, pedido: "la empuñadura sobresale por detras del arma;
    # mueve el gatillo adelante y que el cargador y la empuñadura se acomoden"). El puño se enganchaba justo en el
    # canto trasero del cajon inferior (y -0.078) y, con su grosor y su inclinacion, medio puño quedaba fuera. Se
    # adelantan gatillo, puño, pozo y cargador juntos, y el cajon inferior llega ahora hasta el frente del pozo (antes
    # el pozo ya asomaba por delante y dejaba un hueco debajo del cajon superior).
    DY = 0.024
    bloque(0.042, -0.078, 0.078 + DY + 0.002, -0.038, -0.012, al, nombre="lower")
    caja((0.032, 0.052, 0.030), (0, -0.092, 0.020), al, bisel=0.0025, nombre="cuello_culata")
    cil(0.0145, 0.026, (0.024, 0.042, 0.022), al, eje='X', seg=14, bisel=0.0008, nombre="asistidor")
    caja((0.014, 0.052, 0.028), (0.023, 0.080, 0.014), M("pavonado"), bisel=0.0012, nombre="ventana")
    caja((0.006, 0.044, 0.022), (0.030, 0.080, 0.014), M("goma"), bisel=0.0, nombre="hueco_ventana")
    caja((0.018, 0.030, 0.018), (-0.025, -0.020, -0.020), al, bisel=0.0010, nombre="selector")
    cil(0.0080, 0.020, (-0.027, -0.020, -0.020), M("acero"), eje='X', seg=12, bisel=0.0006, nombre="eje_selector")
    riel(0.470, (0, 0.155, 0.036), al)
    # guardamanos largo: el cañon solo asoma un palmo, como en una carabina moderna
    perfil(sec_octo(0.052, 0.052), 0.225, (0, 0.262, 0.014), al, nombre="guardamanos")
    for s in (-1, 1):
        estrias(4, (0.005, 0.030, 0.011), (s * 0.027, 0.190, 0.014), (0, 0.042, 0), M("goma"),
                bisel=0.0, nombre="mlok")
    estrias(4, (0.032, 0.030, 0.005), (0, 0.190, -0.011), (0, 0.042, 0), M("goma"), bisel=0.0, nombre="mlok")
    caja((0.046, 0.020, 0.030), (0, 0.152, 0.014), M("pavonado"), bisel=0.0012, nombre="tuerca_canon")
    canon(0.140, 0.420, Z_BORE, r=0.0090)
    cil(0.0130, 0.034, (0, 0.160, Z_BORE), M("pavonado"), eje='Y', seg=16, bisel=0.0006, nombre="recamara")
    caja((0.022, 0.030, 0.026), (0, 0.390, 0.022), M("pavonado"), bisel=0.0010, nombre="bloque_gases")
    y_boca = apagallamas(0.420, Z_BORE)
    pozo_cargador(-0.002 + DY, 0.078 + DY, -0.038, -0.074)
    seat = (0.0, 0.038 + DY, -0.074)
    cargador_curvo(seat, largo=0.132, curva=11.0, ancho=0.028, fondo=0.076, mat=po)
    guardamonte((0, -0.042 + DY, -0.038), al, largo=0.068, alto=0.042)
    empunadura((0, -0.078 + DY, -0.038), po, angulo=-17.0, largo=0.112)
    y_atras = culata_telescopica(-0.092, 0.010, largo=0.150)
    anilla((0.024, 0.140, -0.008), r=0.0065, rot=(0, 90, 0))
    ojo = mira_prisma(0.040, 0.050, largo=0.100)
    return {
        "grip": (0.0, -0.084 + DY, -0.072), "foregrip": (0.0, 0.250, -0.012), "fp_foregrip": (0.0, 0.150, -0.014),
        "sight": ojo, "muzzle": (0.0, y_boca, Z_BORE), "mag_seat": seat, "eject": (0.030, 0.080, 0.014),
        "rear": -y_atras, "largo": y_boca - y_atras,
    }


# ---------------------------------------------------------------------------
# 2. FUSIL 7.62 — plataforma AK: madera, cargador de hoz y tubo de gases arriba. Miras de hierro.
# ---------------------------------------------------------------------------
def fusil_762():
    pv, md, md2 = M("pavonado"), M("madera"), M("madera2")
    Z_BORE = 0.016
    # cajon de chapa: trapecio, mas estrecho por abajo
    perfil([(-0.021, -0.040), (0.021, -0.040), (0.025, -0.022), (0.025, 0.034), (-0.025, 0.034), (-0.025, -0.022)],
           0.245, (0, 0.015, 0.000), pv, nombre="cajon")
    perfil(sec(0.050, 0.230, 0.006), 0.014, (0, 0.015, 0.041), pv, eje='Z', nombre="tapa")
    estrias(3, (0.050, 0.013, 0.006), (0, -0.045, 0.047), (0, 0.032, 0), pv, bisel=0.0006, nombre="nervio_tapa")
    caja((0.016, 0.062, 0.020), (0.026, 0.052, 0.024), pv, bisel=0.0012, nombre="palanca_carga")
    caja((0.016, 0.022, 0.017), (0.034, 0.030, 0.024), pv, bisel=0.0012, nombre="tirador")
    caja((0.007, 0.088, 0.030), (0.026, 0.015, 0.006), pv, bisel=0.0012, nombre="selector")
    # guardamanos de madera arriba y abajo, con el tubo de gases en medio
    perfil(sec_octo(0.050, 0.046), 0.185, (0, 0.235, 0.004), md, nombre="guarda_bajo")
    perfil([(-0.024, 0.0), (0.024, 0.0), (0.021, 0.022), (-0.021, 0.022)], 0.170, (0, 0.240, 0.030), md2,
           nombre="cubretubo")
    caja((0.054, 0.026, 0.034), (0, 0.142, 0.012), pv, bisel=0.0012, nombre="virola_guarda")
    cil(0.0105, 0.165, (0, 0.240, 0.041), pv, eje='Y', seg=16, bisel=0.0006, nombre="tubo_gases")
    canon(0.150, 0.420, Z_BORE, r=0.0094)
    caja((0.026, 0.042, 0.048), (0, 0.332, 0.026), pv, rot=(-45, 0, 0), bisel=0.0012, nombre="bloque_gases")
    # LA TORRE DEL PUNTO DE MIRA, alta de verdad: la linea de mira de un AK pasa POR ENCIMA del
    # cubretubo y del tubo de gases. Con la torre baja, apuntar era mirar contra la madera.
    caja((0.028, 0.030, 0.042), (0, 0.400, 0.031), pv, bisel=0.0012, nombre="base_alza_del")
    cil(0.0130, 0.058, (0, 0.449, Z_BORE), pv, eje='Y', seg=16, bisel=0.0008, nombre="freno")
    caja((0.030, 0.048, 0.011), (0, 0.456, 0.023), pv, rot=(-24, 0, 0), bisel=0.0008, nombre="freno_corte")
    cil(0.0064, 0.062, (0, 0.449, Z_BORE), M("goma"), eje='Y', seg=12, bisel=0.0, nombre="anima")
    # cargador de hoz
    caja((0.040, 0.078, 0.024), (0, 0.008, -0.048), pv, bisel=0.0015, nombre="pozo")
    seat = (0.0, 0.008, -0.058)
    cargador_curvo(seat, largo=0.180, curva=32.0, ancho=0.027, fondo=0.072, mat=M("tan"))
    caja((0.020, 0.024, 0.020), (0, -0.030, -0.046), pv, bisel=0.0012, nombre="retenida")
    guardamonte((0, -0.050, -0.040), pv, largo=0.070, alto=0.040)
    empunadura((0, -0.082, -0.040), md, angulo=-14.0, largo=0.104, ancho=0.034, fondo=0.046)
    perfil(sec(0.046, 0.050, 0.008), 0.052, (0, -0.132, 0.000), md, eje='Z', nombre="cuello")
    perfil(sec(0.048, 0.200, 0.010), 0.072, (0, -0.235, 0.004), md, eje='Z', nombre="culata")
    caja((0.050, 0.020, 0.088), (0, -0.338, 0.000), M("goma"), bisel=0.0025, nombre="cantonera")
    caja((0.042, 0.070, 0.012), (0, -0.180, 0.042), md2, bisel=0.0020, nombre="lomo_culata")
    anilla((0.025, -0.150, -0.026), r=0.0065, rot=(0, 90, 0))
    ojo = mira_hierro(0.400, -0.050, 0.050, alto=0.022, mat=pv, orejas_alza=False)
    return {
        "grip": (0.0, -0.088, -0.074), "foregrip": (0.0, 0.230, -0.022), "fp_foregrip": (0.0, 0.150, -0.022),
        "sight": ojo, "muzzle": (0.0, 0.478, Z_BORE), "mag_seat": seat, "eject": (0.028, 0.052, 0.020),
        "rear": 0.350, "largo": 0.83,
    }


# ---------------------------------------------------------------------------
# 3. BULLPUP SILENCIADO — el cargador detras del gatillo: cañon largo en un arma corta.
# ---------------------------------------------------------------------------
def fusil_bullpup():
    po, al = M("polimero"), M("aluminio")
    Z_BORE = 0.010
    bloque(0.054, -0.290, 0.130, -0.042, 0.032, po, r=0.010, nombre="cuerpo")
    perfil(sec(0.050, 0.130, 0.008), 0.020, (0, 0.055, 0.042), po, eje='Z', nombre="lomo")
    caja((0.058, 0.130, 0.030), (0, -0.190, 0.040), po, bisel=0.0030, nombre="carrillera")
    caja((0.054, 0.024, 0.088), (0, -0.298, 0.000), M("goma"), bisel=0.0030, nombre="cantonera")
    riel(0.290, (0, -0.040, 0.032), al)
    perfil(sec_octo(0.046, 0.046), 0.150, (0, 0.200, 0.008), al, nombre="guardamanos")
    for s in (-1, 1):
        estrias(3, (0.005, 0.028, 0.010), (s * 0.024, 0.155, 0.008), (0, 0.040, 0), M("goma"),
                bisel=0.0, nombre="mlok")
    canon(0.130, 0.290, Z_BORE, r=0.0082)
    y_boca = silenciador(0.270, Z_BORE, r=0.0205, largo=0.170)
    # cargador detras del puño (lo que hace bullpup a un bullpup)
    seat = (0.0, -0.110, -0.042)
    cargador_recto(seat, largo=0.120, ancho=0.027, fondo=0.070, mat=M("tan"), inclina=4.0)
    caja((0.040, 0.082, 0.018), (0, -0.110, -0.036), po, bisel=0.0015, nombre="pozo")
    guardamonte((0, 0.010, -0.042), po, largo=0.066, alto=0.038)
    empunadura((0, -0.022, -0.042), po, angulo=-10.0, largo=0.104)
    caja((0.052, 0.075, 0.034), (0, 0.105, -0.056), po, bisel=0.0025, nombre="guarda_mano")
    caja((0.013, 0.038, 0.028), (0.028, -0.040, 0.010), M("pavonado"), bisel=0.0012, nombre="ventana")
    anilla((0.026, 0.140, -0.030), r=0.0065, rot=(0, 90, 0))
    ojo = mira_holo(-0.020, 0.046)
    return {
        "grip": (0.0, -0.030, -0.078), "foregrip": (0.0, 0.180, -0.030), "fp_foregrip": (0.0, 0.115, -0.032),
        "sight": ojo, "muzzle": (0.0, y_boca, Z_BORE), "mag_seat": seat, "eject": (0.030, -0.040, 0.010),
        "rear": 0.310, "largo": 0.75,
    }


# ---------------------------------------------------------------------------
# 4. SUBFUSIL 9MM — cerrojo retardado: diopter de tambor y torre de capucha cerrada.
# ---------------------------------------------------------------------------
def smg_9mm():
    pv, po = M("pavonado"), M("polimero")
    Z_BORE = 0.014
    bloque(0.044, -0.090, 0.115, -0.014, 0.036, pv, nombre="cajon")
    caja((0.048, 0.120, 0.014), (0, 0.030, 0.042), pv, bisel=0.0015, nombre="lomo")
    tubo(0.0245, 0.0035, 0.140, (0, 0.190, Z_BORE), po, eje='Y', seg=22, nombre="guardamanos")
    for s in (-1, 1):
        estrias(5, (0.006, 0.024, 0.014), (s * 0.021, 0.140, Z_BORE), (0, 0.026, 0), M("goma"),
                bisel=0.0, nombre="ranura_guarda")
    caja((0.046, 0.024, 0.040), (0, 0.118, Z_BORE), pv, bisel=0.0015, nombre="virola")
    canon(0.120, 0.280, Z_BORE, r=0.0082)
    cil(0.0128, 0.030, (0, 0.278, Z_BORE), pv, eje='Y', seg=16, bisel=0.0006, nombre="boca")
    # el tubo de la palanca de armar, arriba a la izquierda: su seña de identidad
    cil(0.0078, 0.100, (-0.029, 0.180, 0.038), pv, eje='Y', seg=12, bisel=0.0006, nombre="tubo_palanca")
    caja((0.024, 0.022, 0.015), (-0.036, 0.220, 0.038), pv, bisel=0.0012, nombre="palanca")
    caja((0.036, 0.060, 0.020), (0, 0.010, -0.022), pv, bisel=0.0015, nombre="pozo")
    seat = (0.0, 0.010, -0.030)
    cargador_recto(seat, largo=0.150, ancho=0.025, fondo=0.060, mat=pv, inclina=-5.0)
    guardamonte((0, -0.048, -0.014), pv, largo=0.062, alto=0.036)
    empunadura((0, -0.078, -0.014), po, angulo=-14.0, largo=0.100)
    caja((0.050, 0.070, 0.024), (0, -0.062, -0.024), po, bisel=0.0025, nombre="cajon_disparador")
    for s in (-1, 1):
        cil(0.0078, 0.175, (s * 0.018, -0.180, 0.008), M("acero"), eje='Y', seg=12, bisel=0.0006, nombre="varilla")
    caja((0.048, 0.022, 0.062), (0, -0.272, 0.002), pv, bisel=0.0025, nombre="pala_culata")
    caja((0.050, 0.012, 0.064), (0, -0.286, 0.002), M("goma"), bisel=0.0025, nombre="cantonera")
    anilla((0.025, -0.110, -0.014), r=0.0060, rot=(0, 90, 0))
    ojo = mira_diopter(0.250, -0.070, 0.044, mat=pv)
    return {
        "grip": (0.0, -0.064, -0.080), "foregrip": (0.0, 0.180, -0.014), "fp_foregrip": (0.0, 0.120, -0.016),   # la mano en el mango: mas abajo y adelante (2026-10-20, pedido)
        "sight": ojo, "muzzle": (0.0, 0.293, Z_BORE), "mag_seat": seat, "eject": (0.026, 0.060, 0.022),
        "rear": 0.295, "largo": 0.59,
    }


# ---------------------------------------------------------------------------
# 5. METRALLETA COMPACTA — chapa estampada, cargador dentro del puño y culata de varillas plegada.
# ---------------------------------------------------------------------------
def smg_compacta():
    pv, po = M("pavonado"), M("polimero")
    Z_BORE = 0.012
    bloque(0.048, -0.095, 0.090, -0.018, 0.034, pv, r=0.006, nombre="cajon")
    estrias(6, (0.050, 0.006, 0.046), (0, -0.070, 0.008), (0, 0.028, 0), pv, bisel=0.0004, nombre="nervio")
    caja((0.052, 0.070, 0.012), (0, 0.040, 0.038), pv, bisel=0.0012, nombre="tapa")
    # LAS PALANCAS DE MONTAR, BAJAS (2026-09-28, pedido): asomaban por encima de la linea de mira y al encarar eran dos
    # muros a los lados del punto de mira. Ahora quedan por debajo de la linea (su techo a 4,3 cm; la mira, a 4,8)
    for sp in (-1, 1):
        caja((0.011, 0.036, 0.007), (sp * 0.014, 0.020, 0.0395), pv, bisel=0.0010, nombre="palanca_arriba")
    canon(0.085, 0.185, Z_BORE, r=0.0084)
    tubo(0.0150, 0.0032, 0.080, (0, 0.130, Z_BORE), pv, eje='Y', seg=18, nombre="camisa")
    for i in range(5):
        cil(0.0166, 0.005, (0, 0.098 + i * 0.016, Z_BORE), pv, eje='Y', seg=18, bisel=0.0004, nombre="aro_camisa")
    cil(0.0108, 0.022, (0, 0.190, Z_BORE), pv, eje='Y', seg=14, bisel=0.0006, nombre="boca")
    # el cargador ENTRA POR EL PUÑO: por eso es tan corta
    guardamonte((0, -0.006, -0.018), pv, largo=0.058, alto=0.036)
    perfil(sec(0.038, 0.052, 0.006), 0.062, (0, -0.038, -0.049), po, eje='Z', nombre="puno")
    estrias(4, (0.040, 0.006, 0.010), (0, -0.063, -0.032), (0, 0, -0.014), M("goma"), bisel=0.0006, nombre="estria_puno")
    seat = (0.0, -0.038, -0.080)
    cargador_recto(seat, largo=0.130, ancho=0.026, fondo=0.044, mat=pv, inclina=0.0)
    for s in (-1, 1):
        cil(0.0062, 0.170, (s * 0.021, -0.150, 0.004), M("acero"), eje='Y', seg=10, bisel=0.0006, nombre="varilla")
        cil(0.0062, 0.034, (s * 0.021, -0.240, -0.008), M("acero"), eje='Y', seg=10, rot=(62, 0, 0),
            bisel=0.0006, nombre="codo")
    caja((0.054, 0.032, 0.014), (0, -0.252, -0.024), M("goma"), rot=(14, 0, 0), bisel=0.0020, nombre="pala")
    anilla((0.026, -0.105, -0.012), r=0.0060, rot=(0, 90, 0))
    ojo = mira_hierro(0.140, -0.070, 0.038, alto=0.015, mat=pv, orejas_alza=False)
    return {
        "grip": (0.0, -0.044, -0.062), "foregrip": (0.0, 0.128, -0.010), "fp_foregrip": (0.0, 0.095, -0.012),
        "sight": ojo, "muzzle": (0.0, 0.200, Z_BORE), "mag_seat": seat, "eject": (0.026, 0.040, 0.020),
        "rear": 0.268, "largo": 0.47,
    }


# ---------------------------------------------------------------------------
# 6. PDW 5.7 — bullpup de polimero con el cargador tumbado encima y colimador integrado.
# ---------------------------------------------------------------------------
def pdw():
    """PDW moderna de polimero: pequeña, con el cargador dentro del puño, culata plegable de varillas
    y una empuñadura vertical delante. Es la mas compacta del lote y se reconoce por eso."""
    po, al, pv = M("polimero"), M("aluminio"), M("pavonado")
    Z_BORE = 0.010
    bloque(0.044, -0.090, 0.145, -0.018, 0.032, po, r=0.007, nombre="cuerpo")
    perfil(sec(0.046, 0.120, 0.006), 0.012, (0, 0.020, 0.036), po, eje='Z', nombre="lomo")
    riel(0.215, (0, 0.015, 0.036), al)
    caja((0.013, 0.040, 0.024), (0.023, 0.060, 0.014), pv, bisel=0.0012, nombre="ventana")
    caja((0.006, 0.032, 0.018), (0.029, 0.060, 0.014), M("goma"), bisel=0.0, nombre="hueco")
    caja((0.020, 0.026, 0.014), (0.024, 0.098, 0.024), pv, bisel=0.0012, nombre="palanca")
    caja((0.016, 0.028, 0.016), (-0.024, -0.030, -0.006), po, bisel=0.0010, nombre="selector")
    # cañon corto con su camisa perforada
    canon(0.130, 0.238, Z_BORE, r=0.0070)
    tubo(0.0128, 0.0028, 0.070, (0, 0.180, Z_BORE), po, eje='Y', seg=16, nombre="camisa")
    for i in range(4):
        cil(0.0142, 0.005, (0, 0.153 + i * 0.018, Z_BORE), po, eje='Y', seg=16, bisel=0.0004, nombre="aro")
    cil(0.0098, 0.024, (0, 0.238, Z_BORE), pv, eje='Y', seg=14, bisel=0.0006, nombre="boca")
    # puño con el cargador dentro: solo asoma el talon, como en una PDW de verdad
    guardamonte((0, -0.012, -0.018), po, largo=0.060, alto=0.038)
    empunadura((0, -0.044, -0.018), po, angulo=-8.0, largo=0.100, ancho=0.032, fondo=0.044)
    seat = (0.0, -0.044, -0.018)
    cargador_recto(seat, largo=0.128, ancho=0.024, fondo=0.036, mat=pv, inclina=-8.0)
    # empuñadura vertical delantera, plegada hacia abajo
    caja((0.036, 0.040, 0.022), (0, 0.115, -0.026), po, bisel=0.0018, nombre="base_mango")
    marcos_m = [marco((0, 0.115, -0.036 - t * 0.062), escala=1.0 - 0.20 * t) for t in (0.0, 0.5, 1.0)]
    barrido(sec(0.030, 0.038, 0.008), marcos_m, M("goma"), nombre="mango_vertical")
    # culata plegable de varillas
    for s in (-1, 1):
        cil(0.0060, 0.135, (s * 0.017, -0.152, 0.006), M("acero"), eje='Y', seg=10, bisel=0.0006, nombre="varilla")
    caja((0.044, 0.020, 0.056), (0, -0.222, 0.004), po, bisel=0.0025, nombre="pala")
    caja((0.046, 0.011, 0.058), (0, -0.234, 0.004), M("goma"), bisel=0.0025, nombre="cantonera")
    anilla((0.023, -0.100, -0.012), r=0.0060, rot=(0, 90, 0))
    ojo = mira_punto(-0.005, 0.050, mat=al)
    return {
        # la mano de apoyo en el cuerpo, no en la empuñadura vertical (2026-09-29: colgaba por debajo del arma, como en
        # la escopeta automatica)
        "grip": (0.0, -0.050, -0.052), "foregrip": (0.0, 0.115, -0.012), "fp_foregrip": (0.0, 0.105, -0.050),
        "sight": ojo, "muzzle": (0.0, 0.250, Z_BORE), "mag_seat": seat, "eject": (0.029, 0.060, 0.014),
        "rear": 0.240, "largo": 0.49,
    }


# ---------------------------------------------------------------------------
# 7. ESCOPETA 12/70 DE BOMBA — madera, tubo debajo y grano de laton. La de toda la vida.
# ---------------------------------------------------------------------------
def escopeta_bomba():
    pv, md, md2 = M("pavonado"), M("madera"), M("madera2")
    Z_BORE = 0.024
    bloque(0.046, -0.095, 0.090, -0.026, 0.036, pv, r=0.006, nombre="cajon")
    caja((0.015, 0.050, 0.030), (0.023, 0.010, 0.008), pv, bisel=0.0012, nombre="ventana")
    caja((0.006, 0.042, 0.024), (0.030, 0.010, 0.008), M("goma"), bisel=0.0, nombre="hueco")
    caja((0.028, 0.056, 0.014), (0, -0.010, -0.030), pv, bisel=0.0012, nombre="elevador")
    canon(0.080, 0.520, Z_BORE, r=0.0138)
    cil(0.0112, 0.370, (0, 0.250, -0.004), pv, eje='Y', seg=16, bisel=0.0006, nombre="tubo_cargador")
    for y in (0.150, 0.424):
        caja((0.032, 0.017, 0.052), (0, y, 0.010), pv, bisel=0.0012, nombre="abrazadera")
    cil(0.0158, 0.020, (0, 0.520, Z_BORE), pv, eje='Y', seg=16, bisel=0.0008, nombre="boca")
    perfil(sec_octo(0.050, 0.054), 0.150, (0, 0.262, -0.002), md, nombre="bombeo")
    estrias(9, (0.054, 0.007, 0.017), (0, 0.196, 0.012), (0, 0.016, 0), md2, bisel=0.0006, nombre="estria")
    estrias(9, (0.054, 0.007, 0.017), (0, 0.196, -0.018), (0, 0.016, 0), md2, bisel=0.0006, nombre="estria")
    guardamonte((0, -0.050, -0.026), pv, largo=0.066, alto=0.038)
    # culata de madera de una pieza: cuello inclinado y pala
    caja((0.046, 0.100, 0.070), (0, -0.130, -0.050), md, rot=(24, 0, 0), bisel=0.0035, nombre="cuello")
    perfil(sec(0.046, 0.190, 0.010), 0.078, (0, -0.230, -0.052), md, eje='Z', nombre="culata")
    caja((0.048, 0.022, 0.104), (0, -0.330, -0.058), M("goma"), rot=(-4, 0, 0), bisel=0.0030, nombre="cantonera")
    caja((0.042, 0.070, 0.014), (0, -0.190, -0.014), md2, bisel=0.0020, nombre="lomo")
    esfera(0.0040, (0, 0.512, 0.042), M("laton"), seg=10, nombre="grano")
    caja((0.005, 0.010, 0.016), (0, 0.512, 0.033), pv, bisel=0.0004, nombre="pie_grano")
    # ALZA DE ANILLO FANTASMA: un aro gordo por el que se mira. Con prisa no hay que alinear nada,
    # basta meter el grano dentro del aro, que es justo para lo que sirve una escopeta.
    tubo(0.0110, 0.0024, 0.011, (0, -0.050, 0.048), pv, eje='Y', seg=18, nombre="anillo_alza")
    caja((0.013, 0.013, 0.016), (0, -0.050, 0.034), pv, bisel=0.0008, nombre="pie_alza")
    for i in range(4):
        cil(0.0098, 0.064, (0.027, -0.160 - i * 0.032, -0.060), M("laton"), eje='Y', seg=12,
            bisel=0.0006, nombre="cartucho")
        cil(0.0102, 0.020, (0.027, -0.184 - i * 0.032, -0.060), M("goma"), eje='Y', seg=12,
            bisel=0.0004, nombre="culote")
    return {
        "grip": (0.0, -0.092, -0.064), "foregrip": (0.0, 0.262, -0.014), "fp_foregrip": (0.0, 0.170, -0.016),
        "sight": (0.0, -0.050, 0.048), "muzzle": (0.0, 0.530, Z_BORE), "mag_seat": None,
        "eject": (0.030, 0.010, 0.008), "rear": 0.345, "largo": 0.87,
    }


# ---------------------------------------------------------------------------
# 8. ESCOPETA AUTOMATICA — de cargador, polimero y punto rojo. La de asalto.
# ---------------------------------------------------------------------------
def escopeta_auto():
    pv, po, al = M("pavonado"), M("polimero"), M("aluminio")
    Z_BORE = 0.018
    bloque(0.050, -0.090, 0.120, -0.014, 0.040, al, r=0.006, nombre="cajon")
    riel(0.210, (0, 0.010, 0.040), al)
    caja((0.015, 0.052, 0.032), (0.025, 0.040, 0.014), pv, bisel=0.0012, nombre="ventana")
    caja((0.006, 0.044, 0.026), (0.032, 0.040, 0.014), M("goma"), bisel=0.0, nombre="hueco")
    caja((0.020, 0.042, 0.019), (0.027, 0.085, 0.020), pv, bisel=0.0012, nombre="palanca")
    perfil(sec_octo(0.054, 0.052), 0.180, (0, 0.215, 0.014), po, nombre="guardamanos")
    for s in (-1, 1):
        estrias(4, (0.006, 0.026, 0.013), (s * 0.027, 0.155, 0.014), (0, 0.038, 0), M("goma"),
                bisel=0.0, nombre="ranura")
    canon(0.120, 0.395, Z_BORE, r=0.0142)
    cil(0.0190, 0.048, (0, 0.408, Z_BORE), pv, eje='Y', seg=18, bisel=0.0008, nombre="bocacha")
    for a in (0, 90, 180, 270):
        caja((0.0035, 0.028, 0.042), (0, 0.416, Z_BORE), pv, rot=(0, a, 0), bisel=0.0004, nombre="diente")
    pozo_cargador(-0.012, 0.074, -0.014, -0.056, mat=al, ancho=0.040)
    seat = (0.0, 0.031, -0.056)
    cargador_recto(seat, largo=0.135, ancho=0.033, fondo=0.086, mat=po, inclina=-6.0)
    guardamonte((0, -0.056, -0.014), al, largo=0.068, alto=0.040)
    empunadura((0, -0.090, -0.014), po, angulo=-16.0, largo=0.106, ancho=0.034)
    y_atras = culata_telescopica(-0.094, 0.012, mat=po, largo=0.140)
    # empuñadura vertical delantera, soldada: en una escopeta de asalto va siempre
    caja((0.038, 0.042, 0.026), (0, 0.195, -0.020), po, bisel=0.0018, nombre="base_mango")
    marcos = [marco((0, 0.195, -0.032 - t * 0.072), escala=1.0 - 0.18 * t) for t in (0.0, 0.5, 1.0)]
    barrido(sec(0.032, 0.040, 0.008), marcos, M("goma"), nombre="mango_vertical")
    ojo = mira_punto(0.000, 0.054, mat=al)
    return {
        # la mano de apoyo, EN EL GUARDAMANOS y no en la empuñadura vertical (2026-09-29, pedido: "la mano izquierda
        # esta mas abajo que el arma"): 7 cm por debajo del cañon, con el antebrazo tan grueso del muñeco, se veia
        # colgando debajo del arma. Ahora va donde en las demas armas; la empuñadura vertical queda debajo.
        "grip": (0.0, -0.096, -0.052), "foregrip": (0.0, 0.215, -0.012), "fp_foregrip": (0.0, 0.150, -0.052),
        "sight": ojo, "muzzle": (0.0, 0.434, Z_BORE), "mag_seat": seat, "eject": (0.032, 0.040, 0.014),
        "rear": -y_atras, "largo": 0.434 - y_atras,
    }


# ---------------------------------------------------------------------------
# 9. RIFLE DE PRECISION .338 — cerrojo, chasis de aluminio, bipode y telescopica grande.
# ---------------------------------------------------------------------------
def rifle_precision():
    al, po, ac = M("aluminio"), M("polimero"), M("acero")
    Z_BORE = 0.022
    bloque(0.044, -0.120, 0.180, -0.008, 0.044, al, r=0.006, nombre="accion")
    riel(0.300, (0, 0.030, 0.044), al)
    cil(0.0118, 0.135, (0.010, 0.010, 0.030), ac, eje='Y', seg=16, bisel=0.0006, nombre="cerrojo")
    cil(0.0058, 0.050, (0.030, -0.038, 0.022), ac, eje='X', seg=12, rot=(0, 66, 0), bisel=0.0006, nombre="palanca")
    esfera(0.0108, (0.048, -0.052, 0.012), ac, seg=12, nombre="pomo")
    canon(0.180, 0.560, Z_BORE, r=0.0138, estriado=True)
    cil(0.0180, 0.044, (0, 0.196, Z_BORE), ac, eje='Y', seg=18, bisel=0.0008, nombre="recamara")
    y_boca = freno_boca(0.560, Z_BORE, r=0.0128)
    perfil(sec_octo(0.052, 0.058), 0.290, (0, 0.330, 0.016), al, nombre="chasis")
    for s in (-1, 1):
        estrias(6, (0.005, 0.032, 0.013), (s * 0.027, 0.215, 0.018), (0, 0.044, 0), M("goma"),
                bisel=0.0, nombre="mlok")
    riel(0.110, (0, 0.400, -0.012), al, nombre="riel_bajo")
    caja((0.038, 0.042, 0.024), (0, 0.408, -0.026), po, bisel=0.0015, nombre="base_bipode")
    for s in (-1, 1):
        cil(0.0062, 0.150, (s * 0.032, 0.402, -0.096), ac, eje='Z', seg=10, rot=(0, s * 17.0, 0),
            bisel=0.0006, nombre="pata_bipode")
        cil(0.0088, 0.020, (s * 0.054, 0.402, -0.170), M("goma"), eje='Z', seg=10, bisel=0.0006, nombre="pie")
    pozo_cargador(-0.020, 0.080, -0.008, -0.052, mat=al, ancho=0.038)
    seat = (0.0, 0.030, -0.052)
    cargador_recto(seat, largo=0.100, ancho=0.031, fondo=0.092, mat=po, inclina=0.0)
    guardamonte((0, -0.058, -0.008), al, largo=0.072, alto=0.042)
    empunadura((0, -0.092, -0.008), po, angulo=-20.0, largo=0.110)
    perfil(sec(0.042, 0.230, 0.008), 0.050, (0, -0.235, 0.012), al, eje='Z', nombre="culata")
    caja((0.038, 0.092, 0.022), (0, -0.190, 0.048), po, bisel=0.0025, nombre="carrillera")
    for s in (-1, 1):
        cil(0.0044, 0.044, (s * 0.012, -0.190, 0.030), ac, eje='Z', seg=8, bisel=0.0, nombre="columna")
    caja((0.046, 0.026, 0.115), (0, -0.352, 0.002), po, bisel=0.0030, nombre="pala")
    caja((0.048, 0.014, 0.118), (0, -0.368, 0.002), M("goma"), bisel=0.0030, nombre="cantonera")
    caja((0.032, 0.080, 0.018), (0, -0.310, -0.050), po, bisel=0.0025, nombre="apoyo_mano")
    ojo = mira_telescopica(0.040, 0.044, largo=0.250)
    return {
        "grip": (0.0, -0.098, -0.044), "foregrip": (0.0, 0.330, -0.018), "fp_foregrip": (0.0, 0.210, -0.018),
        "sight": ojo, "muzzle": (0.0, y_boca, Z_BORE), "mag_seat": seat, "eject": (0.024, 0.010, 0.030),
        "rear": 0.380, "largo": y_boca + 0.380,
    }


# ---------------------------------------------------------------------------
# 10. PISTOLA 9MM — la de dotacion: armazon de polimero, corredera estriada, tres puntos de tritio.
# ---------------------------------------------------------------------------
def pistola_9():
    pv, po = M("pavonado"), M("polimero")
    Z_BORE = 0.012
    bloque(0.027, -0.080, 0.098, -0.002, 0.030, pv, r=0.005, nombre="corredera")
    estrias(7, (0.029, 0.006, 0.026), (0, -0.072, 0.012), (0, 0.009, 0), M("acero"), bisel=0.0006, nombre="estria")
    estrias(3, (0.029, 0.006, 0.024), (0, 0.052, 0.012), (0, 0.009, 0), M("acero"), bisel=0.0006, nombre="estria_del")
    caja((0.015, 0.032, 0.015), (0.011, 0.026, 0.014), pv, bisel=0.0010, nombre="ventana")
    cil(0.0070, 0.028, (0, 0.104, Z_BORE), M("acero"), eje='Y', seg=14, bisel=0.0006, nombre="canon")
    cil(0.0042, 0.032, (0, 0.104, Z_BORE), M("goma"), eje='Y', seg=10, bisel=0.0, nombre="anima")
    bloque(0.026, -0.070, 0.078, -0.026, -0.002, po, r=0.004, nombre="armazon")
    riel(0.042, (0, 0.052, -0.026), po, ancho=0.017, nombre="riel_bajo")
    guardamonte((0, -0.030, -0.026), po, largo=0.054, alto=0.034, ancho=0.014, grosor=0.008)
    empunadura((0, -0.058, -0.026), po, angulo=-18.0, largo=0.096, ancho=0.029, fondo=0.038)
    caja((0.013, 0.015, 0.011), (0.014, -0.032, -0.020), pv, bisel=0.0008, nombre="retenida")
    # el cargador va DENTRO del puño: solo asoma el talon
    seat = (0.0, -0.058, -0.026)
    cargador_recto(seat, largo=0.106, ancho=0.021, fondo=0.032, mat=pv, inclina=-18.0)
    ojo = mira_hierro(0.086, -0.072, 0.030, alto=0.009, mat=pv, capucha=False)
    for s in (-1, 1):
        esfera(0.0014, (s * 0.0062, -0.072, 0.0345), M("luz"), seg=8, nombre="punto_tritio")
    esfera(0.0014, (0, 0.086, 0.0345), M("luz"), seg=8, nombre="punto_tritio")
    return {
        "grip": (0.0, -0.062, -0.056), "foregrip": (0.0, -0.056, -0.050), "fp_foregrip": (0.0, -0.056, -0.050),
        "sight": (0.0, -0.072, 0.0345), "muzzle": (0.0, 0.118, Z_BORE), "mag_seat": seat,
        "eject": (0.014, 0.026, 0.014), "rear": 0.100, "largo": 0.22,
    }


# ---------------------------------------------------------------------------
# 11. PISTOLA .45 TACTICA — acero, compensador roscado y micro punto rojo sobre la corredera.
# ---------------------------------------------------------------------------
def pistola_45():
    ac, pv = M("acero"), M("pavonado")
    Z_BORE = 0.014
    bloque(0.029, -0.086, 0.106, 0.000, 0.034, ac, r=0.005, nombre="corredera")
    estrias(8, (0.031, 0.006, 0.028), (0, -0.078, 0.014), (0, 0.009, 0), pv, bisel=0.0006, nombre="estria")
    caja((0.031, 0.090, 0.006), (0, 0.040, 0.033), pv, bisel=0.0008, nombre="rebaje_superior")
    caja((0.016, 0.034, 0.017), (0.012, 0.040, 0.016), pv, bisel=0.0010, nombre="ventana")
    cil(0.0074, 0.044, (0, 0.116, Z_BORE), ac, eje='Y', seg=14, bisel=0.0006, nombre="canon")
    cil(0.0120, 0.050, (0, 0.148, Z_BORE), pv, eje='Y', seg=16, bisel=0.0008, nombre="compensador")
    for i in range(2):
        caja((0.027, 0.011, 0.015), (0, 0.136 + i * 0.018, 0.021), M("goma"), bisel=0.0, nombre="ventana_comp")
    cil(0.0048, 0.056, (0, 0.148, Z_BORE), M("goma"), eje='Y', seg=10, bisel=0.0, nombre="anima")
    bloque(0.027, -0.078, 0.082, -0.024, 0.000, ac, r=0.004, nombre="armazon")
    guardamonte((0, -0.028, -0.024), ac, largo=0.058, alto=0.036, ancho=0.015, grosor=0.008)
    empunadura((0, -0.058, -0.024), M("madera"), angulo=-22.0, largo=0.098, ancho=0.031, fondo=0.038)
    caja((0.021, 0.028, 0.015), (-0.017, -0.044, -0.008), ac, bisel=0.0008, nombre="seguro_manual")
    caja((0.015, 0.042, 0.011), (0.016, -0.024, -0.006), ac, bisel=0.0008, nombre="corredera_tope")
    seat = (0.0, -0.058, -0.024)
    cargador_recto(seat, largo=0.104, ancho=0.022, fondo=0.032, mat=pv, inclina=-22.0)
    # MICRO PUNTO ROJO encastrado en la corredera: es lo que la hace "tactica"
    caja((0.027, 0.036, 0.010), (0, -0.036, 0.038), pv, bisel=0.0010, nombre="base_micro")
    for s in (-1, 1):
        caja((0.0016, 0.032, 0.021), (s * 0.0124, -0.036, 0.052), pv, bisel=0.0004, nombre="pared_micro")
    caja((0.027, 0.032, 0.0017), (0, -0.036, 0.06395), pv, bisel=0.0004, nombre="techo_micro")
    cristal_plano((0.019, 0.021), (0, -0.047, 0.052), rot=(99, 0, 0))
    reticula_punto((0, -0.0475, 0.052), r=0.0007)
    return {
        "grip": (0.0, -0.062, -0.054), "foregrip": (0.0, -0.056, -0.048), "fp_foregrip": (0.0, -0.056, -0.048),
        "sight": (0.0, -0.047, 0.052), "muzzle": (0.0, 0.176, Z_BORE), "mag_seat": seat,
        "eject": (0.014, 0.040, 0.016), "rear": 0.105, "largo": 0.28,
    }


# ---------------------------------------------------------------------------
# 12. REVOLVER .44 — tambor, banda ventilada y alza ajustable. Seis tiros que tumban.
# ---------------------------------------------------------------------------
def revolver():
    """REVOLVER .44: lo que lo hace un revolver es que SE LE VE EL TAMBOR. Por eso el armazon se
    abre en ventana -puente arriba, puente abajo- y el tambor asoma por los lados y por debajo; con
    el tambor metido dentro de un cajon cerrado esto era una pistola rara con cachas de madera."""
    ac, pv, md = M("acero"), M("pavonado"), M("madera")
    Z_BORE = 0.016
    # armazon trasero: martillo, disparador y la espiga donde apoyan las cachas
    bloque(0.030, -0.062, 0.004, -0.026, 0.038, ac, r=0.006, nombre="armazon")
    # LA VENTANA DEL TAMBOR: puente arriba y puente abajo, y el tambor en medio, al aire
    caja((0.032, 0.062, 0.009), (0, 0.034, 0.0385), ac, bisel=0.0012, nombre="puente_alto")
    caja((0.030, 0.062, 0.010), (0, 0.034, -0.019), ac, bisel=0.0012, nombre="puente_bajo")
    caja((0.032, 0.020, 0.062), (0, 0.068, 0.010), ac, bisel=0.0012, nombre="cuello_canon")
    # tambor de seis recamaras, saliente por los dos lados
    cil(0.0238, 0.056, (0, 0.034, Z_BORE), ac, eje='Y', seg=24, bisel=0.0012, nombre="tambor")
    for i in range(6):
        a = math.tau * i / 6.0
        cil(0.0058, 0.060, (math.sin(a) * 0.0142, 0.034, Z_BORE + math.cos(a) * 0.0142), M("goma"),
            eje='Y', seg=10, bisel=0.0, nombre="recamara")
        caja((0.007, 0.016, 0.005), (math.sin(a) * 0.0238, 0.034, Z_BORE + math.cos(a) * 0.0238), ac,
             rot=(0, -math.degrees(a), 0), bisel=0.0004, nombre="muesca_tambor")
    cil(0.0090, 0.062, (0, 0.034, Z_BORE), ac, eje='Y', seg=14, bisel=0.0006, nombre="eje_tambor")
    # cañon con banda ventilada arriba y el tubo del expulsor abajo
    cil(0.0105, 0.150, (0, 0.140, Z_BORE), ac, eje='Y', seg=16, bisel=0.0006, nombre="canon")
    caja((0.019, 0.150, 0.013), (0, 0.140, Z_BORE + 0.015), ac, bisel=0.0012, nombre="banda")
    for i in range(6):
        caja((0.021, 0.009, 0.009), (0, 0.088 + i * 0.021, Z_BORE + 0.016), M("goma"), bisel=0.0,
             nombre="respiradero")
    caja((0.020, 0.130, 0.016), (0, 0.132, Z_BORE - 0.016), ac, bisel=0.0012, nombre="falda")
    cil(0.0056, 0.120, (0, 0.128, Z_BORE - 0.018), ac, eje='Y', seg=12, bisel=0.0006, nombre="varilla")
    cil(0.0048, 0.040, (0, 0.190, Z_BORE), M("goma"), eje='Y', seg=10, bisel=0.0, nombre="anima")
    caja((0.016, 0.030, 0.024), (-0.020, 0.006, 0.006), ac, bisel=0.0010, nombre="pestillo")
    # martillo con su peine, asomando por detras
    # (2026-09-29, pedido: "apuntando con el revolver algo tapa la mira"): el martillo y su peine asomaban 1 cm POR
    # ENCIMA de la linea de mira, a 11 cm del ojo: eran el bloque oscuro en medio de la vista. Bajan 18 mm, que es lo
    # que hace falta para que queden por debajo del alza vistos desde el ojo.
    caja((0.011, 0.024, 0.030), (0, -0.056, 0.022), ac, rot=(-24, 0, 0), bisel=0.0012, nombre="martillo")
    estrias(4, (0.012, 0.004, 0.014), (0, -0.062, 0.034), (0, 0.004, -0.003), pv, bisel=0.0, nombre="peine")
    guardamonte((0, -0.030, -0.026), ac, largo=0.058, alto=0.038, ancho=0.016, grosor=0.008)
    # LA EMPUÑADURA, PEGADA AL ARMAZON: primero la espiga de acero que baja del armazon y luego las
    # cachas de madera a los lados. Colgando el barrido del canto del armazon quedaba un pegote de
    # madera flotando detras del arma.
    caja((0.016, 0.040, 0.075), (0, -0.066, -0.058), ac, rot=(-24, 0, 0), bisel=0.0015, nombre="espiga")
    marcos = [marco((0, -0.058 - 0.036 * t, -0.022 - 0.082 * t), rot=(-24, 0, 0), escala=1.0 - 0.16 * t)
              for t in (0.0, 0.45, 1.0)]
    barrido(sec(0.036, 0.050, 0.010), marcos, md, nombre="cachas")
    caja((0.038, 0.046, 0.010), (0, -0.100, -0.104), M("goma"), rot=(-24, 0, 0), bisel=0.0018, nombre="talon")
    # EL ALZA, BAJA Y SIN PESTAÑAS (2026-09-29): era un bloque macizo de 22 mm con la cara de arriba JUSTO en la linea
    # de mira: apuntando, tapaba media pantalla. Ahora es una base baja y se apunta con la punta del punto de mira, que
    # es donde va la linea de mira ("sight"), como en las pistolas desde el 2026-09-28.
    ojo = mira_hierro(0.196, -0.048, 0.036, alto=0.012, mat=ac, capucha=False, orejas_alza=False)
    caja((0.022, 0.016, 0.008), (0, -0.048, 0.035), ac, bisel=0.0008, nombre="alza_ajustable")
    return {
        "grip": (0.0, -0.076, -0.056), "foregrip": (0.0, -0.070, -0.050), "fp_foregrip": (0.0, -0.070, -0.050),
        "sight": (0.0, -0.048, 0.048), "muzzle": (0.0, 0.215, Z_BORE), "mag_seat": None,
        "eject": (0.0, 0.034, Z_BORE), "rear": 0.100, "largo": 0.32,
    }


# ---------------------------------------------------------------------------
# 13. BAZOOKA RPG — tubo, granada con ojiva y aletas, y la optica lateral PGO.
# ---------------------------------------------------------------------------
def bazooka_rpg():
    ol, md, pv = M("oliva"), M("madera"), M("pavonado")
    tubo(0.0215, 0.0035, 0.620, (0, 0.130, 0.000), ol, eje='Y', seg=26, nombre="tubo")
    cil(0.0265, 0.120, (0, 0.130, 0.000), ol, eje='Y', seg=26, bisel=0.0010, nombre="ensanche")
    cil(0.0245, 0.055, (0, -0.205, 0.000), pv, eje='Y', seg=24, r2=0.0330, bisel=0.0010, nombre="tobera")
    cil(0.0345, 0.016, (0, -0.238, 0.000), pv, eje='Y', seg=24, bisel=0.0008, nombre="aro_tobera")
    perfil(sec_octo(0.056, 0.058), 0.175, (0, 0.140, 0.000), md, nombre="guarda_madera")
    perfil(sec_octo(0.054, 0.056), 0.120, (0, -0.060, 0.000), md, nombre="guarda_trasero")
    cil(0.0345, 0.130, (0, 0.510, 0.000), pv, eje='Y', seg=22, bisel=0.0010, nombre="Misil_cuerpo")
    marcos = [marco((0, 0.575 + 0.090 * t, 0.0), rot=(-90, 0, 0), escala=1.0 - 0.82 * t * t)
              for t in (0.0, 0.35, 0.7, 1.0)]
    barrido(sec(0.069, 0.069, 0.016), marcos, pv, nombre="Misil_ojiva")
    cil(0.0072, 0.040, (0, 0.685, 0.000), M("acero"), eje='Y', seg=12, bisel=0.0006, nombre="Misil_espoleta")
    cil(0.0225, 0.075, (0, 0.408, 0.000), pv, eje='Y', seg=18, r2=0.0300, bisel=0.0008, nombre="Misil_cono")
    for a in (0, 90, 180, 270):
        caja((0.0035, 0.060, 0.052), (0, 0.400, 0.000), pv, rot=(0, a, 0), bisel=0.0006, nombre="Misil_aleta")
    caja((0.042, 0.095, 0.040), (0, 0.020, -0.038), ol, bisel=0.0020, nombre="cajon_mecanismo")
    guardamonte((0, 0.028, -0.058), ol, largo=0.066, alto=0.040)
    empunadura((0, -0.004, -0.058), ol, angulo=-14.0, largo=0.110, ancho=0.035, fondo=0.045)
    marcos_d = [marco((0, 0.205, -0.038 - 0.078 * t), rot=(-8, 0, 0), escala=1.0 - 0.16 * t) for t in (0.0, 0.5, 1.0)]
    barrido(sec(0.033, 0.043, 0.008), marcos_d, ol, nombre="mango_delantero")
    caja((0.038, 0.036, 0.024), (0, 0.205, -0.030), ol, bisel=0.0018, nombre="base_mango")
    caja((0.005, 0.014, 0.055), (0, 0.300, 0.048), pv, bisel=0.0006, nombre="alza_plegable")
    caja((0.005, 0.012, 0.032), (0, -0.020, 0.038), pv, bisel=0.0006, nombre="mira_plegable")
    anilla((0.026, 0.060, -0.022), r=0.0070, rot=(0, 90, 0))
    ojo = mira_pgo(0.060, 0.026, lado=-0.052, mat=ol)
    return {
        "grip": (0.0, -0.010, -0.092), "foregrip": (0.0, 0.205, -0.100), "fp_foregrip": (0.0, 0.190, -0.078),
        "sight": ojo, "muzzle": (0.0, 0.720, 0.000), "mag_seat": None, "eject": None,
        "rear": 0.250, "largo": 0.97,
    }


# ---------------------------------------------------------------------------
# 14. LANZACOHETES AT4 — tubo de un solo uso: sencillo, verde y con su optica de 2 aumentos.
# ---------------------------------------------------------------------------
def bazooka_at4():
    ol, pv, po = M("oliva"), M("pavonado"), M("polimero")
    tubo(0.0420, 0.0040, 0.760, (0, 0.070, 0.000), ol, eje='Y', seg=26, nombre="tubo")
    cil(0.0455, 0.030, (0, 0.440, 0.000), pv, eje='Y', seg=26, bisel=0.0010, nombre="aro_boca")
    cil(0.0455, 0.030, (0, -0.300, 0.000), pv, eje='Y', seg=26, bisel=0.0010, nombre="aro_cola")
    cil(0.0480, 0.055, (0, -0.335, 0.000), M("goma"), eje='Y', seg=26, r2=0.0540, bisel=0.0010, nombre="tobera")
    for y in (-0.180, -0.050, 0.150, 0.320):
        cil(0.0435, 0.014, (0, y, 0.000), pv, eje='Y', seg=26, bisel=0.0006, nombre="banda")
    caja((0.070, 0.120, 0.012), (0, 0.060, 0.046), pv, bisel=0.0012, nombre="lomo")
    caja((0.048, 0.140, 0.034), (0, -0.030, 0.058), po, bisel=0.0020, nombre="cajon_disparador")
    caja((0.032, 0.064, 0.015), (0, -0.020, 0.080), M("goma"), bisel=0.0015, nombre="barra_disparo")
    guardamonte((0, -0.048, -0.042), po, largo=0.064, alto=0.038)
    empunadura((0, -0.080, -0.042), po, angulo=-12.0, largo=0.106, ancho=0.035, fondo=0.045)
    marcos_d = [marco((0, 0.120, -0.044 - 0.080 * t), rot=(-10, 0, 0), escala=1.0 - 0.14 * t) for t in (0.0, 0.5, 1.0)]
    barrido(sec(0.035, 0.047, 0.008), marcos_d, po, nombre="mango_delantero")
    caja((0.040, 0.042, 0.026), (0, 0.120, -0.036), po, bisel=0.0018, nombre="base_mango")
    caja((0.042, 0.075, 0.022), (0, 0.180, 0.052), po, bisel=0.0015, nombre="apoyo_hombro")
    caja((0.058, 0.115, 0.028), (0, -0.205, -0.032), po, rot=(-18, 0, 0), bisel=0.0025, nombre="apoyo_hombro2")
    # el brazo se metia en el HUECO del tubo de la optica (su esquina estaba en el eje): apuntando se veia un bloque gris
    # dentro de la mira (2026-09-29). Ahora sujeta el tubo por fuera, desde su costado.
    caja((0.032, 0.042, 0.042), (-0.022, 0.020, 0.038), po, bisel=0.0015, nombre="brazo_optica")
    eje_z = 0.060
    tubo(0.0160, 0.0025, 0.110, (-0.054, 0.020, eje_z), pv, eje='Y', seg=20, nombre="cuerpo_optica")
    tubo(0.0195, 0.0045, 0.022, (-0.054, -0.042, eje_z), pv, eje='Y', seg=20, nombre="ocular_optica")
    tubo(0.0185, 0.0035, 0.014, (-0.054, 0.080, eje_z), pv, eje='Y', seg=20, nombre="objetivo_optica")
    caja((0.040, 0.026, 0.005), (-0.054, 0.084, eje_z + 0.021), pv, bisel=0.0006, nombre="visera")
    cristal(0.0150, (-0.054, 0.086, eje_z))
    reticula_cruz((-0.054, 0.084, eje_z), largo=0.014, grosor=0.0005)
    return {
        "grip": (0.0, -0.086, -0.076), "foregrip": (0.0, 0.120, -0.106), "fp_foregrip": (0.0, 0.110, -0.078),
        "sight": (-0.054, -0.052, eje_z), "muzzle": (0.0, 0.460, 0.000), "mag_seat": None, "eject": None,
        "rear": 0.365, "largo": 0.86,
    }


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# 15. MAZO CHUPETIN — el mazo de demolicion disfrazado de piruleta: bola rosa y tubo blanco.
#
# Es un ARMA CUERPO A CUERPO, asi que aqui no hay cañon ni mira: lo que importa es DONDE GOLPEA. El
# juego mide el golpe con `muzzle`, que en las demas armas es la boca del cañon; en el mazo es el
# centro de la bola. Si se pone en el mango, pegas con el aire.
#
# La bola va ligeramente ACHATADA (0,92 en el eje del palo) porque una esfera perfecta a este tamaño
# se lee como una pelota y no como un caramelo; y lleva la espiral blanca de toda la vida, que es lo
# que hace que se reconozca de un vistazo aunque sea del tamaño de un puño en pantalla.
# ---------------------------------------------------------------------------
def mazo_chupetin():
    ro, bl = M("caramelo"), M("palo")
    Z = 0.0
    # A LA MEDIDA DEL MAZO DE SIEMPRE (weapon_model.gd::_build_sledge): el usuario lo veia "muy chico".
    # Antes la bola quedaba a 0,58 m de la mano y media 16 cm; el mazo tiene la cabeza a 0,94 m de la
    # mano y mide 35 cm de alto. Ahora el palo llega a esa altura y la bola es de ese tamaño.
    LARGO = 0.890          # del tope a la bola
    R_BOLA = 0.165

    # EL PALO: tubo blanco de plastico, un pelin mas grueso abajo para que se agarre. Tan grueso como el
    # mango del mazo (5 cm): uno fino con una bola tan grande parecia que se iba a partir.
    cil(0.0200, LARGO, (0, LARGO * 0.5 - 0.120, Z), bl, eje='Y', seg=18, r2=0.0240, nombre="palo")
    # tope de goma abajo, que si no el palo acaba en un canto
    cil(0.0270, 0.026, (0, -0.128, Z), M("goma"), eje='Y', seg=16, nombre="tope")
    # anilla de la muñequera: es un mazo, se cuelga
    anilla((0, -0.118, 0.022), r=0.0090, rot=(90, 0, 0))

    # LA BOLA, achatada en el eje del palo
    y_bola = LARGO - 0.120 + R_BOLA * 0.55
    bola = esfera(R_BOLA, (0, y_bola, Z), ro, seg=28, nombre="caramelo")
    bola.scale = (1.0, 0.92, 1.0)

    # SIN ESPIRAL, y esto es una decision, no un olvido.
    #
    # Probe dos. Cuatro cintas planas cruzando la bola: en el render se veia que no eran cintas SOBRE
    # el caramelo sino TABLAS ATRAVESANDOLO, asomando por los lados como una cuchilla -un plano recto
    # no envuelve una esfera-. Luego una hilera de bolitas siguiendo una helice: quedaban como lunares
    # sueltos, mas seta que chupetin, y para que se leyeran como una linea continua hacian falta el
    # doble, solapadas, con lo que eso cuesta en triangulos.
    #
    # Una espiral de verdad se pinta en la TEXTURA, no se modela pieza a pieza. Aqui las armas van sin
    # textura -material plano por pieza-, asi que la bola se queda lisa: rosa caramelo, que es lo que
    # se pidio y lo que se lee bien a distancia.

    # el collarin donde el palo entra en la bola: sin esto parece que flota
    cil(0.0330, 0.030, (0, y_bola - R_BOLA * 0.90, Z), bl, eje='Y', seg=16, nombre="collarin")

    return {
        # las manos separadas como en el mazo (0,29 m): con un palo mas largo, mas palanca
        "grip": (0.0, -0.090, 0.0), "foregrip": (0.0, 0.200, 0.0), "fp_foregrip": (0.0, 0.200, 0.0),
        "sight": None,
        # EL PUNTO DE GOLPE: el centro de la bola. Es lo que el juego usa para saber que has tocado.
        "muzzle": (0.0, y_bola, Z),
        "mag_seat": None, "eject": None,
        "rear": 0.150, "largo": y_bola + R_BOLA + 0.150,
    }


# EL CATALOGO. `kind` es como se juega (lo de siempre en Weapons.FAMILY) y `mano` si va a una mano.
# ---------------------------------------------------------------------------
ARMAS = [
    {"id": "carabina_556", "nombre": "CARABINA 5.56", "kind": "rifle", "f": carabina_556, "optica": "prisma"},
    {"id": "fusil_762", "nombre": "FUSIL 7.62", "kind": "rifle", "f": fusil_762, "optica": "hierro"},
    {"id": "fusil_bullpup", "nombre": "BULLPUP SILENCIADO", "kind": "rifle", "f": fusil_bullpup, "optica": "holo", "fogonazo": 0.2},
    {"id": "smg_9mm", "nombre": "SUBFUSIL 9MM", "kind": "smg", "f": smg_9mm, "optica": "diopter"},
    {"id": "smg_compacta", "nombre": "METRALLETA COMPACTA", "kind": "smg", "f": smg_compacta, "optica": "hierro"},
    {"id": "pdw_57", "nombre": "PDW 5.7", "kind": "smg", "f": pdw, "optica": "punto"},
    {"id": "escopeta_bomba", "nombre": "ESCOPETA 12/70", "kind": "shotgun", "f": escopeta_bomba, "optica": "grano"},
    {"id": "escopeta_auto", "nombre": "ESCOPETA AUTOMATICA", "kind": "shotgun", "f": escopeta_auto, "optica": "punto"},
    {"id": "rifle_precision", "nombre": "RIFLE DE PRECISION", "kind": "sniper", "f": rifle_precision, "optica": "visor"},
    {"id": "pistola_9", "nombre": "PISTOLA 9MM", "kind": "pistol", "f": pistola_9, "optica": "hierro", "mano": True},
    {"id": "pistola_45", "nombre": "PISTOLA .45 TACTICA", "kind": "pistol", "f": pistola_45, "optica": "micro", "mano": True},
    {"id": "revolver_44", "nombre": "REVOLVER .44", "kind": "pistol", "f": revolver, "optica": "hierro", "mano": True},
    {"id": "bazooka_rpg", "nombre": "BAZOOKA RPG", "kind": "rocket", "f": bazooka_rpg, "optica": "pgo"},
    {"id": "bazooka_at4", "nombre": "LANZACOHETES AT4", "kind": "rocket", "f": bazooka_at4, "optica": "tubo"},
    {"id": "mazo_chupetin", "nombre": "MAZO CHUPETIN", "kind": "sledge", "f": mazo_chupetin, "optica": None},
]


# ---------------------------------------------------------------------------
# LOS MAZOS DEL MUESTRARIO (mazos.py). Se modelan aparte -son nueve y ocupan lo suyo- pero entran en
# el catalogo como una skin de mazo mas, igual que el chupetin: mismo `kind`, sin optica.
#
# Cada uno necesita SUS materiales (naranja de obra, hueso, hielo, oro...), que el taller no tiene.
# Por eso no se mete `m["f"]` a pelo: se envuelve para que los cree antes de montar la pieza.
# ---------------------------------------------------------------------------
import mazos as _mazos


def _con_materiales(f):
    def _envuelto():
        _mazos.materiales_mazos()
        return f()
    return _envuelto


for _m in _mazos.MAZOS:
    ARMAS.append({"id": _m["id"], "nombre": _m["nombre"], "kind": "sledge",
                  "f": _con_materiales(_m["f"]), "optica": None})
