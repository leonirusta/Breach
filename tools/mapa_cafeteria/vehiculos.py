"""VEHICULOS APARCADOS del mapa CAFETERIA URBANA (la leyenda de la lamina los marca en violeta): turismos, furgonetas de
reparto, una moto y el camion de bomberos de la calle principal. Son voxels del mapa (coberturas que se rompen), no los
vehiculos conducibles de la isla.

COMO SE CONSTRUYEN. Cada vehiculo es una REJILLA DE VOXELS DE 0,2 m (`Modelo`): i a lo largo (0 = la trasera), j hacia
arriba (0 = la fila que pisa el suelo `y`) y c a lo ancho (0 = el lado IZQUIERDO del conductor). Las formas con curva
(el perfil de un turismo) van dibujadas en ASCII por bandas a lo ancho; lo recto (el camion), con `rect`. Al final
`emitir` junta los voxels en cajas y las pone en el mundo con un GIRO de verdad (no un espejo: el conductor va siempre a
la izquierda y los rotulos se leen bien por los dos lados) sin mover la huella que tenia cada vehiculo.

  - Carroceria con su sombreado: la chapa y un tono mas oscuro (`TONOS`) en las juntas de las puertas, los estribos y
    los labios de los paragolpes; lunas y ventanillas de vidrio (se ve el interior: asientos, salpicadero, volante) con
    sus montantes; faros, pilotos, matriculas, retrovisores y tiradores; ruedas con cubierta de goma y llanta dentro de
    su paso de rueda, con el hueco oscuro detras.
  - REGLA DE ORO (docs/10): todo en la rejilla de 0,2 y cada voxel tocando POR UNA CARA a otro que llegue al suelo (las
    ruedas tocan `y`). `Modelo.comprobar` lo mide al generar y avisa si algo queda colgado de una arista.
"""
from collections import deque
from piezas import g, V
import letras

# tonos de cada chapa: (oscuro para juntas, estribos y sombras; asientos)
TONOS = {
    "chapa_bomberos": ("chapa_granate", "cortina"),
    "chapa_granate": ("metal_negro", "cortina"),
    "chapa_azul": ("metal_negro", "cortina"),
    "chapa_blanca": ("chapa_plata", "cojin_rojo"),
    "chapa_amarilla": ("laton", "metal_negro"),
    "chapa_plata": ("chapa_gris", "cortina"),
    "chapa_verde_oscura": ("metal_negro", "cortina"),
    "chapa_gris": ("metal_negro", "cortina"),
}


def _tonos(color):
    return TONOS.get(color, ("metal_negro", "cortina"))


class Local:
    """Coordenadas del vehiculo -> mundo. u a lo largo (el frente hacia +u), v arriba desde `y`, w a lo ancho (+w a la
    DERECHA del conductor). `eje` "x" o "z" dice por donde va el largo y `sentido` hacia donde mira el frente. Es un giro
    alrededor del centro de la anchura `wc`, asi que la huella en el suelo es la misma mire hacia donde mire."""

    def __init__(self, l, x, z, y, eje, sentido, wc=0.0):
        self.l, self.x, self.z, self.y, self.eje, self.s, self.wc = l, g(x), g(z), y, eje, sentido, wc

    def _xz(self, u, w):
        s = self.s
        if self.eje == "x":           # frente +x: la derecha es +z; frente -x: la derecha es -z
            return self.x + u * s, self.z + (w if s > 0 else 2 * self.wc - w)
        # frente +z: la derecha es -x; frente -z: la derecha es +x
        return self.x + ((2 * self.wc - w) if s > 0 else w), self.z + u * s

    def caja(self, u0, v0, w0, u1, v1, w1, mat, hueco=False):
        xa, za = self._xz(u0, w0)
        xb, zb = self._xz(u1, w1)
        self.l.caja(min(xa, xb), self.y + v0, min(za, zb), max(xa, xb), self.y + v1, max(za, zb), mat, hueco=hueco)


class Modelo:
    """Rejilla de voxels de 0,2 de un vehiculo: {(i, j, c): material}."""

    def __init__(self, nombre, ancho):
        self.nombre, self.ancho = nombre, ancho
        self.vox = {}

    def pon(self, i, j, c, m):
        if m:
            self.vox[(i, j, c)] = m
        else:
            self.vox.pop((i, j, c), None)

    def rect(self, i0, i1, j0, j1, c0, c1, m):
        """Rellena [i0, i1) x [j0, j1) x [c0, c1) (m None: vacia)."""
        for i in range(i0, i1):
            for j in range(j0, j1):
                for c in range(c0, c1):
                    self.pon(i, j, c, m)

    def rect2(self, i0, i1, j0, j1, c0, c1, m):
        """`rect` y su simetrico al otro lado (c -> ancho-1-c)."""
        self.rect(i0, i1, j0, j1, c0, c1, m)
        self.rect(i0, i1, j0, j1, self.ancho - c1, self.ancho - c0, m)

    def pinta(self, i0, i1, j0, j1, c0, c1, m):
        """Cambia el material solo donde ya hay algo (pintura sobre la chapa)."""
        for i in range(i0, i1):
            for j in range(j0, j1):
                for c in range(c0, c1):
                    if (i, j, c) in self.vox:
                        self.vox[(i, j, c)] = m

    def perfil(self, cs, filas, paleta):
        """Perfil lateral en ASCII para las columnas `cs`: filas de ARRIBA ABAJO (la ultima es j = 0), un caracter por i
        desde la trasera. '.' no toca nada; el resto se busca en `paleta`."""
        n = len(filas)
        largo = len(filas[0])
        for k, fila in enumerate(filas):
            assert len(fila) == largo, "%s: fila %d mide %d (y no %d)" % (self.nombre, k, len(fila), largo)
            j = n - 1 - k
            for i, ch in enumerate(fila):
                if ch == ".":
                    continue
                for c in cs:
                    self.pon(i, j, c, paleta[ch])

    def cara(self, i, j_arriba, fila_c, paleta, c0=0):
        """Una cara de frente o trasera en ASCII (columnas = c desde c0; filas de arriba abajo desde j_arriba)."""
        for k, fila in enumerate(fila_c):
            for dc, ch in enumerate(fila):
                if ch != ".":
                    self.pon(i, j_arriba - k, c0 + dc, paleta[ch])

    def rueda(self, i0, cs, d, llanta="acero", buje=None, goma="goma"):
        """RUEDA de d x d voxels (4: turismo y furgoneta, 5: camion) con las esquinas redondeadas, pisando j = 0, en las
        columnas `cs`: cubierta de goma y la llanta en el centro (con su buje si se pide)."""
        for c in cs:
            for a in range(d):
                for b in range(d):
                    esquina = (a in (0, d - 1)) and (b in (0, d - 1))
                    if esquina:
                        continue
                    centro = 0 < a < d - 1 and 0 < b < d - 1
                    m = llanta if centro else goma
                    if buje and d % 2 == 1 and a == d // 2 and b == d // 2:
                        m = buje
                    self.pon(i0 + a, b, c, m)

    def texto(self, txt, c, i_ini, i_fin, j_arriba, mat, derecha):
        """Rotulo en la chapa (fuente MINI de 3 x 5, 0,2 m por punto), centrado en [i_ini, i_fin). En el lado derecho se
        lee de la trasera al frente; en el izquierdo, del frente a la trasera."""
        pix, ancho = letras.pixeles_mini(txt)
        i0 = i_ini + max(0, (i_fin - i_ini - ancho) // 2)
        for col, fila in pix:
            i = i0 + col if derecha else (i_ini + i_fin - 1) - (i0 + col - i_ini)
            if (i, j_arriba - fila, c) in self.vox:
                self.vox[(i, j_arriba - fila, c)] = mat

    def comprobar(self):
        """Todo tiene que colgar POR CARAS de lo que pisa el suelo (j = 0). Devuelve los voxels sueltos."""
        vistos = set(k for k in self.vox if k[1] == 0)
        cola = deque(vistos)
        while cola:
            i, j, c = cola.popleft()
            for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
                q = (i + d[0], j + d[1], c + d[2])
                if q in self.vox and q not in vistos:
                    vistos.add(q)
                    cola.append(q)
        sueltos = sorted(k for k in self.vox if k not in vistos)
        if sueltos:
            print("  AVISO vehiculos: %s tiene %d voxels sin apoyo por caras: %s" % (self.nombre, len(sueltos), sueltos[:12]))
        return sueltos

    def cajas(self):
        """Los voxels juntos en cajas: tiras a lo largo de i, luego a lo ancho y luego hacia arriba."""
        tiras = {}
        for (i, j, c), m in self.vox.items():
            tiras.setdefault((j, c), []).append((i, m))
        corridas = []
        for (j, c), lst in tiras.items():
            lst.sort()
            a, ma = lst[0]
            b = a + 1
            for i, m in lst[1:]:
                if i == b and m == ma:
                    b += 1
                    continue
                corridas.append((j, a, b, ma, c))
                a, ma, b = i, m, i + 1
            corridas.append((j, a, b, ma, c))
        # a lo ancho
        por = {}
        for (j, a, b, m, c) in corridas:
            por.setdefault((j, a, b, m), []).append(c)
        planas = []
        for (j, a, b, m), cs in por.items():
            cs.sort()
            c0 = cs[0]
            c1 = c0 + 1
            for c in cs[1:]:
                if c == c1:
                    c1 += 1
                    continue
                planas.append((a, b, c0, c1, m, j))
                c0, c1 = c, c + 1
            planas.append((a, b, c0, c1, m, j))
        # hacia arriba
        por = {}
        for (a, b, c0, c1, m, j) in planas:
            por.setdefault((a, b, c0, c1, m), []).append(j)
        out = []
        for (a, b, c0, c1, m), js in sorted(por.items()):
            js.sort()
            j0 = js[0]
            j1 = j0 + 1
            for j in js[1:]:
                if j == j1:
                    j1 += 1
                    continue
                out.append((a, b, j0, j1, c0, c1, m))
                j0, j1 = j, j + 1
            out.append((a, b, j0, j1, c0, c1, m))
        return out

    def emitir(self, l, x, z, y, eje, sentido, u0, w0):
        """Al mundo: i -> u = u0 + 0,2 i; c -> w = w0 + 0,2 c; j -> v = 0,2 j. Gira alrededor del centro de la anchura."""
        self.comprobar()
        loc = Local(l, x, z, y, eje, sentido, wc=round(w0 + self.ancho * V / 2, 3))
        for (a, b, j0, j1, c0, c1, m) in self.cajas():
            loc.caja(round(u0 + a * V, 3), round(j0 * V, 3), round(w0 + c0 * V, 3),
                     round(u0 + b * V, 3), round(j1 * V, 3), round(w0 + c1 * V, 3), m)


# ======================================================================================================
# TURISMO
# ======================================================================================================
# 23 voxels de largo (4,6 m con paragolpes) x 9 de ancho (1,8 m; 2,2 con los retrovisores) x 8 de alto (1,6 m).
# Ruedas de 0,8 en i 3-6 y 16-19 (batalla de 2,6 m). Bandas a lo ancho: E = las puertas (c 0 y 8), S = el habitaculo
# metido un voxel (c 1 y 7: montantes y ventanillas), C = el centro (c 2..6: techo, lunas, capo, maletero y el suelo).
# Letras: B chapa, d tono oscuro, H tirador cromado, P piloto, F faro, K paragolpes, k su labio negro, N negro (pasos de
# rueda, suelo, salpicadero), X montante, V ventanilla, W luna, R techo.
COCHE_E = [
    ".......................",
    ".......................",
    "................N......",
    "..BBBBBBHBdHBBBdBBBBB..",
    ".PB....BBBdBBBBd....BF.",
    "KB......BBdBBBB......BK",
    "kB......ddddddd......Bk",
    ".......................",
]
COCHE_S = [
    ".......RRRRRRR.........",
    "......XXVVXVVXXX.......",
    "....XXXVVVXVVVVXXX.....",
    "..BBBBBBBBBBBBBBBBBBB..",
    ".PBNNNN........NNNNNBF.",
    "KBNNNNNN.......NNNNNNBK",
    "kBNNNNNNNNNNNNNNNNNNNBk",
    ".......................",
]
COCHE_C = [
    ".......RRRRRRR.........",
    "......WW.....WWW.......",
    "....WWW........WWW.....",
    "..BBBBB........NNBBBB..",
    ".BBBBBB........NNNNNNB.",
    "KBBBBBB........NNNNNNBK",
    "kNNNNNNNNNNNNNNNNNNNNNk",
    ".......................",
]
# la variante FAMILIAR: el techo sigue hasta atras, luna trasera casi vertical, ventanilla de custodia y el maletero
# hueco detras del asiento de atras (las puertas y los bajos, como el turismo)
FAMILIAR_E = COCHE_E[:3] + [".BBBBBBBHBdHBBBdBBBBB.."] + COCHE_E[4:]
FAMILIAR_S = [
    "...RRRRRRRRRRR.........",
    "..XXVVXVVVXVVXXX.......",
    "..XVVVXVVVXVVVVXXX.....",
    ".BBBBBBBBBBBBBBBBBBBB..",
] + COCHE_S[4:]
FAMILIAR_C = [
    "...RRRRRRRRRRR.........",
    "..WW.........WWW.......",
    "..W............WWW.....",
    ".BB............NNBBBB..",
    ".BB............NNNNNNB.",
    "KBB............NNNNNNBK",
    "kNNNNNNNNNNNNNNNNNNNNNk",
    ".......................",
]


def coche(l, x, z, y, eje="x", sentido=1, color="chapa_azul", rng=None):
    """TURISMO compacto de 4,6 x 1,8 x 1,6: carroceria con capo, maletero y el habitaculo metido un voxel (el hombro
    de la linea de cintura), lunas inclinadas y ventanillas con sus montantes A, B y C, juntas de las puertas, tiradores,
    estribos oscuros, faros, pilotos, calandra con el emblema, paragolpes con su labio negro, matriculas, retrovisores y
    cuatro ruedas con llanta. Por dentro, asientos, salpicadero y volante (se ven por los cristales). Dos carrocerias:
    berlina (maletero) y familiar (techo hasta atras); con `rng` se sortea y sin el sale de la posicion."""
    oscuro, asiento = _tonos(color)
    if rng is not None:
        familiar = rng.random() < 0.4
        if rng.random() < 0.5:
            asiento = "metal_negro"
    else:                         # sin rng: la variante sale de la posicion (siempre la misma en el mismo sitio)
        familiar = (int(round(x * 5)) * 7 + int(round(z * 5)) * 13) % 3 == 0
    p = {"B": color, "R": color, "X": color, "K": color, "d": oscuro, "H": "cromo", "P": "piloto", "F": "faro",
         "k": "metal_negro", "N": "metal_negro", "V": "vidrio_coche", "W": "vidrio_coche", "L": "chapa_blanca"}
    m = Modelo("coche %s en (%.1f, %.1f)" % (color, x, z), 9)
    m.perfil((0, 8), FAMILIAR_E if familiar else COCHE_E, p)
    m.perfil((1, 7), FAMILIAR_S if familiar else COCHE_S, p)
    m.perfil(range(2, 7), FAMILIAR_C if familiar else COCHE_C, p)
    m.pon(0, 1, 6, "cromo")                                    # el tubo de escape
    # la cara de delante: faros, calandra negra con el emblema, y la matricula en el paragolpes
    m.cara(21, 3, ["FFNNHNNFF"], p)
    m.cara(22, 2, ["KKNLLLNKK"], p)
    # la de atras: pilotos, la matricula en su moldura negra
    m.cara(1, 3, ["PPNLLLNPP"], p)
    # retrovisores: el brazo (la esquina negra del cristal) sobre la puerta y la carcasa del color del coche, fuera
    for c_brazo, c_espejo in ((0, -1), (8, 9)):
        m.pon(16, 5, c_brazo, "metal_negro")
        m.pon(16, 5, c_espejo, color)
    # por dentro: asiento de atras, los dos de delante con reposacabezas, y el volante del conductor (a la izquierda)
    m.rect(7, 8, 2, 5, 2, 7, asiento)
    m.rect(8, 10, 2, 3, 2, 7, asiento)
    for c0, c1 in ((2, 4), (5, 7)):
        m.rect(11, 12, 2, 6, c0, c1, asiento)
        m.rect(12, 14, 2, 3, c0, c1, asiento)
    m.rect(14, 15, 4, 5, 2, 4, "metal_negro")
    # ruedas (en las puertas, dentro de su paso)
    for i0 in (3, 16):
        m.rueda(i0, (0, 8), 4)
    m.emitir(l, x, z, y, eje, sentido, u0=-2.2, w0=-0.8)


# ======================================================================================================
# FURGONETA
# ======================================================================================================
def furgoneta(l, x, z, y, eje="x", sentido=1, color="chapa_blanca", rotulo_mat="chapa_azul"):
    """FURGONETA de reparto de 5,8 x 2,0 x 2,6: caja de carga hueca (con su carga) y techo alto, cabina con el morro
    corto, parabrisas grande inclinado y puertas con ventanilla, puerta corredera a la derecha con su guia, portones
    traseros acristalados, grupos opticos verticales, tercera luz de freno, retrovisores grandes, franja y ROTULO en los
    dos costados (en `rotulo_mat`) y cuatro ruedas."""
    oscuro, _ = _tonos(color)
    A = 10
    m = Modelo("furgoneta en (%.1f, %.1f)" % (x, z), A)
    # --- el volumen: caja de carga, cabina y morro --------------------------------------------------------------
    m.rect(1, 24, 1, 3, 0, A, color)                           # el suelo de la caja
    m.rect2(1, 17, 3, 12, 0, 1, color)                         # los costados de la caja
    m.rect2(17, 24, 3, 6, 0, 1, color)                         # y los de la cabina hasta la ventanilla
    m.rect(1, 2, 3, 12, 0, A, color)                           # los portones de atras
    m.rect(1, 22, 12, 13, 0, A, color)                         # el techo
    m.rect(17, 23, 3, 4, 1, A - 1, "chapa_gris")               # el piso de la cabina (mas alto)
    m.rect(22, 28, 1, 5, 0, A, color)                          # el morro (el motor)
    # el parabrisas en escalera (cada peldaño pisa el de abajo por una cara) y los montantes A a los lados
    for (j, i0, i1) in ((11, 21, 23), (10, 22, 23), (9, 22, 24), (8, 23, 24), (7, 23, 25), (6, 24, 26)):
        m.rect(i0, i1, j, j + 1, 1, A - 1, "vidrio_coche")
        m.rect2(i0, i1, j, j + 1, 0, 1, color)
        m.rect2(17, i0, j, j + 1, 0, 1, color)                  # la chapa de la puerta de la cabina hasta el montante
    m.rect(24, 28, 5, 6, 0, A, color)                          # el capo
    # --- las ventanillas de la cabina (trapecio detras del montante A) y la puerta ---------------------------------
    m.rect2(18, 22, 9, 11, 0, 1, "vidrio_coche")
    m.rect2(18, 23, 7, 9, 0, 1, "vidrio_coche")
    m.rect2(17, 18, 3, 12, 0, 1, oscuro)                        # la junta de la puerta de la cabina (montante B)
    m.rect2(18, 19, 6, 7, 0, 1, "cromo")                         # tirador
    m.rect2(22, 23, 3, 6, 0, 1, oscuro)                         # la junta de delante de la puerta
    # la puerta corredera (lado derecho): juntas, tirador y la guia por encima
    m.rect(10, 11, 3, 12, A - 1, A, oscuro)
    m.rect(11, 12, 6, 7, A - 1, A, "cromo")
    m.rect(3, 10, 11, 12, A - 1, A, "metal_negro")
    # franja baja y el rotulo en los dos costados
    m.rect2(1, 28, 4, 5, 0, 1, rotulo_mat)
    txt = {"chapa_bomberos": "PAN", "chapa_verde_oscura": "BIO", "chapa_granate": "VINO"}.get(rotulo_mat, "CAFE")
    m.texto(txt, A - 1, 2, 17, 10, rotulo_mat, derecha=True)
    m.texto(txt, 0, 2, 17, 10, rotulo_mat, derecha=False)
    # --- detras: lunas de los portones, tirador, pilotos verticales, tercera luz de freno, matricula ------------------
    m.rect(1, 2, 8, 11, 1, 4, "vidrio_coche")
    m.rect(1, 2, 8, 11, 6, 9, "vidrio_coche")
    m.pon(1, 6, 5, "cromo")
    m.rect2(1, 2, 3, 5, 0, 1, "piloto")
    m.rect2(1, 2, 5, 6, 0, 1, "faro")                           # marcha atras
    m.rect(1, 2, 12, 13, 4, 6, "piloto")
    m.rect(1, 2, 3, 4, 4, 6, "chapa_blanca")
    m.rect(0, 1, 1, 3, 0, A, "metal_negro")                    # paragolpes trasero (y estribo)
    # --- delante: faros altos, calandra con el emblema, paragolpes y matricula ---------------------------------------
    m.rect2(27, 28, 3, 5, 0, 2, "faro")
    m.rect(27, 28, 2, 5, 2, 8, "metal_negro")
    m.rect(27, 28, 4, 5, 4, 6, "cromo")
    m.rect(28, 29, 1, 3, 0, A, "metal_negro")
    m.rect(28, 29, 2, 3, 4, 6, "chapa_blanca")
    # retrovisores grandes, pegados a la puerta bajo el montante A
    m.rect(23, 24, 6, 8, -1, 0, "metal_negro")
    m.rect(23, 24, 6, 8, A, A + 1, "metal_negro")
    # --- por dentro: mampara, asientos, salpicadero y volante; y la carga ------------------------------------------
    m.rect(16, 17, 3, 12, 1, A - 1, "chapa_gris")
    m.rect(22, 24, 4, 7, 1, A - 1, "metal_negro")
    m.rect(21, 22, 6, 7, 1, 3, "metal_negro")
    for c0, c1 in ((1, 3), (5, 9)):
        m.rect(18, 20, 4, 5, c0, c1, "metal_negro")
        m.rect(17, 18, 4, 8, c0, c1, "metal_negro")
    m.rect(2, 5, 3, 5, 1, 4, "madera_clara")
    m.rect(2, 4, 5, 6, 1, 3, "madera_clara")
    m.rect(6, 8, 3, 4, 6, 9, "madera_clara")
    # --- ruedas en su paso, con el hueco oscuro detras --------------------------------------------------------------
    for i0 in (3, 22):
        m.rect2(i0 - 1, i0 + 5, 1, 3, 0, 1, None)
        m.rect2(i0, i0 + 4, 3, 4, 0, 1, None)
        m.rect2(i0 - 1, i0 + 5, 1, 4, 1, 2, "metal_negro")
        m.rueda(i0, (0, A - 1), 4)
    m.emitir(l, x, z, y, eje, sentido, u0=-2.8, w0=-1.0)


# ======================================================================================================
# CAMION DE BOMBEROS
# ======================================================================================================
def _persiana(m, i0, i1, j0, j1, cs):
    """Persiana de aluminio de un armario: lamas alternas y la barra del tirador abajo."""
    for j in range(j0, j1):
        mat = "cromo" if j == j0 else ("chapa_plata" if (j - j0) % 2 else "acero")
        for c in cs:
            m.rect(i0, i1, j, j + 1, c, c + 1, mat)


def camion_bomberos(l, x, z, y, eje="z", sentido=1):
    """CAMION DE BOMBEROS de 9,2 x 2,4 (2,8 con los espejos) x 3,2: cabina adelantada con doble fila de asientos,
    parabrisas grande, puertas con ventanilla y el escudo, puente de luces rojas y azules, franja reflectante y la banda
    blanca de arriba; la caja con los armarios de persiana de aluminio, la ESCALERA sobre el techo con sus soportes, la
    DEVANADERA de manguera en el hueco de atras con su lanza, pilotos y rotativos traseros, estribo, paragolpes negro
    con la matricula y seis ruedas (las de atras gemelas) con llanta y buje."""
    R, Rd, Bl, N = "chapa_bomberos", "chapa_granate", "chapa_blanca", "metal_negro"
    A = 12
    m = Modelo("camion de bomberos en (%.1f, %.1f)" % (x, z), A)
    # --- bastidor, caja (llena de material) y cabina ------------------------------------------------------------------
    m.rect(1, 45, 2, 4, 3, 9, N)                               # el bastidor
    m.rect(1, 33, 3, 14, 0, A, "chapa_gris")                   # la caja: por dentro, el material
    m.rect(1, 33, 3, 14, 0, 1, R)
    m.rect(1, 33, 3, 14, A - 1, A, R)
    m.rect(1, 2, 3, 14, 0, A, R)
    m.rect(1, 33, 13, 14, 0, A, Bl)                            # el techo blanco
    m.rect2(1, 33, 12, 13, 0, 1, Bl)                           # la banda blanca de arriba
    m.rect(33, 34, 3, 14, 0, A, N)                             # la junta entre la caja y la cabina
    m.rect(34, 45, 2, 14, 0, A, R)                             # la cabina...
    m.rect(35, 44, 5, 13, 1, A - 1, None)                      # ...hueca
    m.rect(35, 44, 2, 5, 1, A - 1, "chapa_gris")               # el piso (el motor va debajo)
    m.rect(34, 45, 13, 14, 0, A, Bl)
    m.rect2(34, 45, 12, 13, 0, 1, Bl)
    m.rect(44, 45, 12, 13, 0, A, Bl)
    m.rect2(34, 45, 6, 7, 0, 1, Bl)                            # la franja reflectante de la cabina
    m.rect(44, 45, 6, 7, 0, A, Bl)
    # --- los armarios de persiana de los costados ---------------------------------------------------------------------
    for (i0, i1, j0) in ((2, 5, 4), (6, 17, 6), (19, 25, 4), (26, 32, 4)):
        _persiana(m, i0, i1, j0, 11, (0, A - 1))                # (encima, la fila roja del dintel)
    # --- la cabina: ventanillas, juntas, tiradores, escudo, peldaño ---------------------------------------------------
    m.rect2(35, 38, 8, 12, 0, 1, "vidrio_coche")               # la fila de atras
    m.rect2(39, 43, 8, 12, 0, 1, "vidrio_coche")               # la puerta del conductor
    m.rect2(38, 39, 3, 8, 0, 1, Rd)                            # la junta de las puertas
    m.rect2(37, 38, 7, 8, 0, 1, "cromo")
    m.rect2(39, 40, 7, 8, 0, 1, "cromo")
    m.rect2(40, 42, 6, 8, 0, 1, "laton")                        # el escudo del parque, sobre la franja
    m.rect2(42, 44, 2, 3, 0, 1, "acero")                        # el peldaño de delante
    # el frente: parabrisas, faros, intermitentes, calandra con el emblema, paragolpes y matricula
    m.rect(44, 45, 7, 12, 1, A - 1, "vidrio_coche")
    m.cara(44, 5, ["RRRNNNNNNRRR",
                   "lFFNNccNNFFl",
                   "RRRNNNNNNRRR"], {"R": R, "N": N, "F": "faro", "c": "cromo", "l": "luz_bombilla"})
    m.rect(45, 46, 1, 3, 0, A, N)
    m.rect(45, 46, 2, 3, 5, 7, Bl)
    # retrovisores altos pegados al montante A
    m.rect(43, 44, 7, 11, -1, 0, N)
    m.rect(43, 44, 7, 11, A, A + 1, N)
    # por dentro: salpicadero, volante, los asientos de delante y el banco de atras
    m.rect(43, 44, 5, 8, 1, A - 1, N)
    m.rect(42, 43, 7, 8, 2, 4, N)
    for c0, c1 in ((2, 4), (7, 10)):
        m.rect(40, 42, 5, 6, c0, c1, N)
        m.rect(39, 40, 5, 9, c0, c1, N)
    m.rect(36, 38, 5, 6, 1, A - 1, N)
    m.rect(35, 36, 5, 9, 1, A - 1, N)
    # el puente de luces sobre la cabina
    luces = ("luz_azul", "luz_roja")
    for c in range(1, A - 1):
        m.rect(40, 43, 14, 15, c, c + 1, "faro" if c in (5, 6) else luces[c % 2])
    # --- atras: persiana de la bomba, la devanadera en su hueco, pilotos, rotativos y estribo ---------------------------
    _persiana(m, 1, 2, 3, 7, range(1, A - 1))
    m.rect(1, 5, 7, 12, 1, A - 1, None)                        # el hueco de la devanadera
    for c in range(1, A - 1):                                 # tambor: bridas de acero y la manguera enrollada
        for a in range(4):
            for b in range(4):
                if a in (0, 3) and b in (0, 3):
                    continue
                if c in (1, A - 2):
                    mat = "acero"
                else:                                          # las vueltas de la manguera (tela roja, dos tonos)
                    mat = "cojin_rojo" if b % 2 == 0 else "toldo_rojo_oscuro"
                m.pon(1 + a, 7 + b, c, mat)
    m.rect(2, 4, 8, 10, 1, 2, "cromo")                         # los bujes del tambor
    m.rect(2, 4, 8, 10, A - 2, A - 1, "cromo")
    m.pon(0, 8, 5, "laton")                                    # la lanza, colgando de la manguera
    m.rect2(1, 2, 3, 5, 0, 1, "piloto")
    m.rect2(1, 2, 5, 6, 0, 1, "faro")
    m.rect2(1, 2, 14, 15, 0, 1, "luz_azul")                    # rotativos en las esquinas de atras
    m.rect(0, 1, 2, 4, 1, A - 1, "acero")                      # el estribo
    # --- la escalera sobre el techo: largueros, peldaños cada 0,4 y sus soportes ----------------------------------------
    for c in (2, A - 3):
        m.rect(3, 40, 15, 16, c, c + 1, "acero")
        for i in (4, 18, 30, 38):
            m.rect(i, i + 1, 14, 15, c, c + 1, N)
    for i in range(4, 40, 2):
        m.rect(i, i + 1, 15, 16, 3, A - 3, "acero")
    # --- ruedas: delante sencillas, detras dos ejes con ruedas gemelas; cada una con su eje hasta el bastidor ------------
    for i0, ancho_rueda in ((6, 2), (12, 2), (36, 1)):
        base = 2 if i0 > 30 else 3                              # la cabina baja hasta j 2, la caja hasta j 3
        m.rect2(i0 - 1, i0 + 6, base, 5, 0, ancho_rueda, None)  # el paso de rueda
        m.rect2(i0, i0 + 5, 5, 6, 0, ancho_rueda, None)
        m.rect2(i0 - 1, i0 + 6, base, 6, ancho_rueda, ancho_rueda + 1, N)     # el hueco oscuro de detras
        m.rueda(i0, tuple(range(ancho_rueda)) + tuple(range(A - ancho_rueda, A)), 5, llanta="acero", buje="cromo")
        m.rect2(i0 + 2, i0 + 3, 2, 3, ancho_rueda, 3, N)        # el eje
    m.emitir(l, x, z, y, eje, sentido, u0=-4.6, w0=-1.2)


# ======================================================================================================
# MOTO
# ======================================================================================================
def moto(l, x, z, y, eje="x", sentido=1, color="chapa_granate"):
    """MOTO de 2,0 m: ruedas de 0,6 con llanta, motor y escape cromado, deposito del color, asiento, colin con el
    piloto, horquilla doble, faro y manillar."""
    m = Modelo("moto en (%.1f, %.1f)" % (x, z), 3)             # c 0 y 2 las barras de la horquilla, c 1 el eje
    for i0 in (0, 7):                                           # ruedas de 3 x 3 en cruz con la llanta en medio
        m.pon(i0 + 1, 0, 1, "goma")
        m.pon(i0, 1, 1, "goma")
        m.pon(i0 + 1, 1, 1, "acero")
        m.pon(i0 + 2, 1, 1, "goma")
        m.pon(i0 + 1, 2, 1, "goma")
    m.rect(3, 7, 1, 3, 1, 2, "metal_negro")                    # el motor
    m.rect(1, 4, 1, 2, 2, 3, "cromo")                          # el escape (a la derecha)
    m.rect(2, 5, 3, 4, 1, 2, "goma")                           # el asiento
    m.rect(5, 8, 3, 4, 1, 2, color)                            # el deposito
    m.rect(0, 2, 3, 4, 1, 2, color)                            # el colin
    m.pon(0, 3, 1, "piloto")
    m.rect(8, 9, 1, 5, 0, 1, "cromo")                          # la horquilla
    m.rect(8, 9, 1, 5, 2, 3, "cromo")
    m.rect(8, 9, 3, 5, 1, 2, "metal_negro")                    # la pipa de la direccion
    m.pon(9, 3, 1, color)                                      # el guardabarros
    m.pon(9, 4, 1, "faro")
    m.rect(8, 9, 5, 6, 0, 3, "metal_negro")                    # el manillar
    m.emitir(l, x, z, y, eje, sentido, u0=-1.0, w0=-0.2)
