"""GOLPE DE CRISTAL a medio voxel (2026-09-30, pedido con la lamina "AVATAR 2 · GOLPE DE CRISTAL": "ahora creame el
personaje para la habilidad del salto"). El personaje del SALTO + golpe de cristal (nivel_personaje.gd "salto").

Hecho como el Puño de Oro (tools/make_puno_fino.py, de donde se toman el volumen, los bultos, la oclusion y la pieza
fina): a la MITAD del voxel del soldado, con las articulaciones del soldado salvo los ojos. Mirando la lamina:
  - CASCO gris veteado (como piedra pulida), redondeado, con el VISOR de CRISTAL violeta-azul que cruza la frente (con
    sus vetas de luz y la muesca de la nariz), las piezas de los lados y la nuca de cristal.
  - OJOS CIAN que brillan, pasamontañas GRIS con pliegues.
  - ARMADURA de bloques en tres grises (un camuflaje digital de gris) con PARCHES VIOLETA sueltos; chaleco con las
    bolsas, la franja violeta del pecho y la luz cian del lado.
  - HOMBRERAS grises con violeta, ANTEBRAZOS DE PIEL y GUANTES gruesos de placas.
  - Piernas de armadura con rodilleras de franja violeta y BOTAS gruesas con la raya violeta.
  - Detras, la MOCHILA DE CRISTAL (azul-violeta veteado) con el simbolo que brilla.

Uso:  python tools/make_cristal_fino.py && python tools/make_soldier.py
"""
import io
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_puno_fino as base  # noqa: E402
from make_puno_fino import Volumen, c, h, K  # noqa: E402

RAIZ = base.RAIZ
SALIDA = os.path.join(RAIZ, "tools", "piezas_blender", "soldado_cristal.json")

MATERIALES = {
    "gris_osc": (44, 44, 52), "gris": (68, 68, 78), "gris_claro": (96, 96, 108), "gris_luz": (122, 122, 136),
    "morado": (140, 82, 232), "morado_luz": (180, 134, 255), "morado_osc": (94, 52, 172),
    "cristal": (78, 86, 200), "cristal_luz": (148, 168, 255), "cristal_brillo": (214, 226, 255),
    "cristal_osc": (46, 48, 138), "cristal_violeta": (122, 70, 222),
    "cian": (86, 214, 255), "cian_luz": (190, 246, 255),
    "mascara": (70, 70, 82), "mascara_luz": (90, 90, 104), "mascara_osc": (54, 54, 64),
    "piel": (230, 148, 94), "piel_luz": (246, 178, 124), "piel_osc": (196, 118, 74),
    # los ojos (las mismas claves que el Puño: base.ojos() las usa): CIAN QUE BRILLA
    "ojo_blanco": (170, 236, 255), "ojo_iris": (48, 190, 255), "ojo_iris_luz": (130, 228, 255),
    "ojo_pupila": (220, 250, 255), "ojo_brillo": (255, 255, 255), "pestana": (40, 40, 48),
    "suela": (30, 30, 36), "hebilla": (140, 140, 156),
}
CON_BULTOS = {"gris_osc", "gris", "gris_claro", "mascara", "cristal", "cristal_osc"}


def gris_digital(celda):
    """El camuflaje digital de grises de la lamina: bloques de 2 celdas en tres grises y, suelto, un parche VIOLETA"""
    x, y, z = celda[0] // 2, celda[1] // 2, celda[2] // 2
    r = h(x // 2, y // 2, z // 2, 31)
    if r < 0.05:
        return "morado" if h(x, y, z, 32) < 0.7 else "morado_luz"
    a = base.camo.ruido(x, y, z, 2.6, 33)
    if a < 0.38:
        return "gris_osc"
    if a > 0.62:
        return "gris_claro"
    return "gris"


def cristal_veteado(celda):
    """CRISTAL azul-violeta con vetas de luz en diagonal (el visor, la nuca del casco, la mochila)"""
    x, y, z = celda
    t = ((x + y * 0.7 + z * 0.45) / 7.0 + base.camo.ruido(x, y, z, 5.0, 41) * 0.8) % 1.0
    if t < 0.08:
        return "cristal_brillo"
    if t < 0.2:
        return "cristal_luz"
    if t > 0.82:
        return "cristal_osc"
    if t > 0.62:
        return "cristal_violeta"
    return "cristal"


def piedra(celda):
    """El gris VETEADO del casco (como piedra pulida): grises con alguna veta clara"""
    x, y, z = celda
    t = ((x * 0.8 - y + z * 0.5) / 9.0 + base.camo.ruido(x, y, z, 4.0, 43)) % 1.0
    if t < 0.1:
        return "gris_luz"
    if t < 0.45:
        return "gris_claro"
    return "gris"


def modelo():
    v = Volumen()

    def moteado(a, b, p=0.14, s=5):
        return lambda cel: b if h(cel[0] // 2, cel[1] // 2, cel[2] // 2, s) < p else a

    # ------------------------------------------------------------------ PIERNAS (armadura)
    v.lado("leg_upper_l", -1, 5.5, 19, 31.5, -3, 5, gris_digital)
    v.lado("leg_upper_l", 5.5, 7, 21.5, 27.5, -1.5, 3.5, "gris_osc")              # la placa del muslo
    v.lado("leg_upper_l", 5.5, 7.5, 23.5, 24.5, -2, 4, "morado")
    for y in (22.5, 26, 29):
        v.lado("leg_upper_l", -1, 5.5, y, y + 0.5, -3.5, -3, gris_digital)          # placas que sobresalen
    v.lado("leg_lower_l", -0.5, 5, 7.5, 18.5, -2.5, 4.5, gris_digital)
    # la RODILLERA de placas con su franja violeta
    v.lado("leg_lower_l", -1.5, 6, 14, 20.5, -5, -2, "gris_osc")
    v.lado("leg_lower_l", -1, 5.5, 16.5, 18, -5.5, -5, "morado")
    v.lado("leg_lower_l", -0.5, 5, 16.5, 17, -6, -5.5, "morado_luz")
    v.lado("leg_lower_l", -1.5, 6, 14.5, 15, -5, 5, "gris")
    # la espinillera
    v.lado("leg_lower_l", -0.5, 5, 8.5, 13, -3.5, -2.5, "gris_claro")
    # BOTAS gruesas con la raya violeta
    v.lado("leg_lower_l", -1.5, 6, 3, 7.5, -3, 5.5, moteado("gris_osc", "gris"))
    v.lado("foot_l", -1.5, 6, -1, 3, -3.5, 6, moteado("gris_osc", "gris"))
    v.lado("toes_l", -1.5, 6, -1, 2, -7.5, -3.5, moteado("gris_osc", "gris"))
    v.lado("foot_l", -2, 6.5, -2, -1, -3.5, 6.5, "suela")
    v.lado("toes_l", -2, 6.5, -2, -1, -8, -3.5, "suela")
    v.lado("toes_l", -2, 6.5, -1, -0.5, -8, -7.5, "morado")
    v.lado("foot_l", -2, 6.5, -1, -0.5, -3.5, 6.5, "morado")

    # ------------------------------------------------------------------ TORSO
    v.caja("pelvis", -10, 5, 31, 39, -5, 6, gris_digital)
    v.caja("stomach", -10.5, 5.5, 39, 47, -5, 6.5, gris_digital)
    v.caja("chest", -11, 6, 47, 58.5, -5, 6.5, gris_digital)
    # el CHALECO de placas, que sobresale
    chaleco = moteado("gris_osc", "gris", 0.2)
    v.caja("chest", -11, 6, 47, 57.5, -7, -5, chaleco)
    v.caja("stomach", -11, 6, 40, 47, -7, -5, chaleco)
    v.caja("chest", -11, 6, 47, 57.5, 6.5, 8, chaleco)
    v.caja("stomach", -11, 6, 40, 47, 6.5, 8, chaleco)
    v.lado("stomach", 5.5, 7, 40, 47, -6, 7.5, chaleco)
    v.lado("chest", 5.5, 7, 47, 52, -6, 7.5, chaleco)
    # la placa alta del pecho (gris claro) con la FRANJA VIOLETA y la LUZ CIAN del lado
    v.caja("chest", -9.5, 4.5, 52, 57, -7.5, -7, "gris_claro")
    v.caja("chest", -4.5, -0.5, 53, 56, -8, -7.5, "gris_osc")
    v.caja("chest", -9, -6, 54, 57, -8, -7.5, "morado")
    v.caja("chest", 2.5, 3.5, 49, 56, -8, -7.5, lambda cel: "cian_luz" if cel[1] % 3 == 0 else "cian")
    v.lado("chest", 1.5, 4, 57, 59, -7.5, 8.5, "gris_osc")                          # cinchas de los hombros
    # LAS BOLSAS: cuatro, con tapa
    for x0 in (-10, -6, -1.5, 2.5):
        v.caja("stomach", x0, x0 + 3.5, 40.5, 46, -9, -7, "gris")
        v.caja("stomach", x0 - 0.25, x0 + 3.75, 45, 46.5, -9.5, -7, "gris_claro")
        v.caja("stomach", x0 + 1.25, x0 + 2.25, 44, 45, -9.5, -9, "gris_osc")
    # el cinturon, con la franja violeta
    v.caja("pelvis", -11, 6, 35.5, 38, -6.5, 7.5, "gris_osc")
    v.caja("pelvis", -11, 6, 36.5, 37, -7, 8, "morado")
    v.caja("pelvis", -4, -1, 35.5, 38, -7.5, -6.5, "hebilla")
    # LA MOCHILA DE CRISTAL con el simbolo que brilla (la de la vista trasera y el detalle del equipo)
    v.caja("chest", -9, 4, 46.5, 57.5, 8, 11.5, cristal_veteado)
    v.caja("chest", -9.5, 4.5, 46, 47, 7.5, 12, "gris_osc")
    v.caja("chest", -9.5, 4.5, 57, 58, 7.5, 12, "gris_osc")
    v.caja("chest", -9.5, -8.5, 46, 58, 7.5, 12, "gris_osc")
    v.caja("chest", 3.5, 4.5, 46, 58, 7.5, 12, "gris_osc")
    # el simbolo: una punta de flecha hacia arriba, cian
    for fila in range(6):
        ancho = 0.5 + fila * 0.5
        v.caja("chest", -2.5 - ancho, -2.5 + ancho, 54.5 - fila * 0.5, 55 - fila * 0.5, 11.5, 12, "cian_luz" if fila < 2 else "cian")
    v.caja("hood", -9, 4, 57, 59.5, 5, 8.5, chaleco)

    # ------------------------------------------------------------------ CUELLO Y CABEZA
    mascara = moteado("mascara", "mascara_luz", 0.14, 7)
    v.caja("neck", -8, 3, 57, 60, -6, 6, mascara)
    v.caja("head", -11.5, 6.5, 60, 71, -8.5, 7.5, mascara)
    v.caja("head", -11.5, 6.5, 60, 66, -9, -8.5, mascara)
    v.caja("head", -10.5, 5.5, 66, 71, -9, -8.5, lambda cel: "piel_osc" if cel[1] >= c(70.5) else "piel")
    v.caja("head", -4.5, -0.5, 61, 66, -9.5, -9, mascara)
    v.caja("head", -6, 1, 61.5, 62, -9.5, -9, "mascara_osc")
    # EL CASCO gris veteado, redondeado
    for fila in range(c(70.5), c(83.5)):
        y = fila / K
        dentro = 0 if y < 80 else (0.5 if y < 81.5 else (1.5 if y < 82.5 else 3))
        v.caja("head", -12.5 + dentro, 7.5 - dentro, y, y + base.E, -10 + dentro, 10 - dentro, piedra)
    # la nuca y los lados; la nuca de CRISTAL (la vista trasera)
    v.caja("head", -12.5, 7.5, 63.5, 70.5, 2.5, 10, piedra)
    v.caja("head", -10, 5, 72, 81, 9.5, 10.5, cristal_veteado)
    v.lado("head", 7, 7.5, 63.5, 70.5, -5.5, 10, piedra)
    v.caja("head", -13, 8, 70.5, 71.5, -10.5, 10.5, "gris_osc")                     # el borde
    # EL VISOR DE CRISTAL: cruza la frente, sobresale, con la muesca de la nariz abajo en el centro
    v.caja("head", -12.5, 7.5, 71.5, 76.5, -11.5, -10, cristal_veteado)
    v.caja("head", -12.5, 7.5, 76.5, 77, -11.5, -10, "gris_osc")
    v.caja("head", -12.5, 7.5, 71.5, 72, -11.5, -10, "gris_osc")
    v.caja("head", -4, -1, 71.5, 73, -11.5, -10, "gris_osc")                        # la muesca
    v.lado("head", 7.5, 9, 71, 77, -8, 4, "gris_osc")                               # los lados del visor
    v.lado("head", 8.5, 9.5, 72.5, 75.5, -6, 2, "morado")
    # cresta de arriba y almohadillas
    v.caja("head", -4, -1, 82.5, 84, -8, 8, "gris_claro")
    base.ojos(v)

    # ------------------------------------------------------------------ BRAZOS: hombrera, manga, PIEL y guante gordo
    for lado in ("l", "r"):
        X = (lambda x: x) if lado == "l" else (lambda x: 2 * base.CX - x)

        def caja(hueso, x0, x1, *r):
            a, b = X(x0), X(x1)
            v.caja(hueso + "_" + lado, min(a, b), max(a, b), *r)
        # la HOMBRERA de dos placas, gris con violeta
        caja("shoulder", 4.5, 11, 52, 63, -4.5, 6.5, gris_digital)
        caja("shoulder", 5, 11.5, 60, 63.5, -5, 7, "gris_claro")
        caja("shoulder", 8, 11.5, 61, 63.5, -5.5, -4.5, "morado")
        caja("arm_upper", 9, 19, 57, 65, -3, 6, gris_digital)
        caja("arm_upper", 15, 16, 56.5, 65.5, -3.5, 6.5, "morado")
        # la codera
        caja("arm_lower", 15.5, 19.5, 56.5, 65.5, -3, 6, "gris_osc")
        # el ANTEBRAZO DE PIEL (se ve entre la manga y el guante)
        caja("arm_lower", 19, 25, 58, 64, -1.5, 4.5, lambda cel: "piel_luz" if cel[1] >= c(63) else "piel")
        # el GUANTE de placas, con la raya violeta de los nudillos: AFINADO (2026-10-03, pedido: gordo, tapaba el arma
        # al apuntar, con las armas de tercera persona ya a x1,5)
        caja("arm_lower", 24.5, 31, 57.5, 64.5, -2, 5, moteado("gris_osc", "gris", 0.25))
        caja("arm_lower", 24.5, 25.5, 57, 65, -2.5, 5.5, "gris")
        caja("arm_lower", 30.5, 31.5, 61, 64.5, -1.5, 4.5, "morado")
    return v


def main():
    rig = json.load(io.open(base.RIG, encoding="utf-8"))
    v = modelo()
    n0 = len(v.v)
    nb = base.bultos(v, CON_BULTOS, 0.3)
    p, total = base.pieza(v, rig, "soldado_cristal", "tools/make_cristal_fino.py (GOLPE DE CRISTAL a medio voxel)",
                          MATERIALES, base.ARTICULACIONES)
    json.dump(p, io.open(SALIDA, "w", encoding="utf-8"), separators=(",", ":"), ensure_ascii=False)
    print("escrito %s: %d celdas (%d de bultos), %d rectangulos, %d colores" % (SALIDA, n0 + nb, nb, total, len(p["colores"])))


if __name__ == "__main__":
    main()
