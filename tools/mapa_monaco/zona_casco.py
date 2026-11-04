"""ZONA CASCO VIEJO de la Roca (mapa "monaco").

El barrio de siempre: casas entre medianeras de revoco pastel apretadas unas contra otras, callejones de
dos metros y medio que no van derechos a ningun sitio, plazoletas con fuente y, sobre todo, ESCALINATAS.
La Roca no es plana: el casco se apoya en tres bancales de piedra (la ronda a cota 0, la explanada media a
+2 y la alta a +4) y lo unico que los cose son escaleras publicas de peldano 0,25. Son la sena de identidad
del sitio y ademas el esqueleto de la navegacion: por ahi suben las criaturas y por ahi se juega.

LA REGLA QUE MANDA AQUI ES QUE TODO TEJADO SE PISA. Cada manzana tiene al menos una casa con hueco de
escalera que sale a la azotea, las casas vecinas se enlazan con escalerillas de azotea cuando se llevan mas
de 1,2 m, y sobre algunos callejones hay pasarelas de tablones. Nadie se queda mirando un tejado sin poder
subir: la mitad de los tiroteos pasan ahi arriba.

Las medias: plantas de 3,2 m (multiplo de 0,8, la celda del A*), muros de 0,3, puertas de 1,6 x 2,9,
callejones de 2,2 a 3,2 y calles principales de 3,2. Escalones de 0,25 en TODAS las escaleras, incluidas
las de azotea y las de los portales.

Y esta a medio reventar, como en la referencia: una casa partida por la mitad con los forjados colgando
sobre la calle, boquetes de proyectil en las fachadas, montones de cascote y polvo por los callejones.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lienzo import Lienzo  # noqa: E402

W, D = 56.0, 70.4          # tamano de diseno de la zona (el rect que llega es 56 x 70,4)

PLANTA = 3.2               # altura de planta: multiplo de 0,8 para que cada forjado caiga en la rejilla
MURO = 0.3                 # grueso de fachada y medianera
FORJADO = 0.3              # canto del forjado: deja 2,9 m libres por planta (puertas de 2,6 caben de sobra)

Y_BAJA, Y_MEDIA, Y_ALTA = 0.0, 2.0, 4.0     # los tres bancales

# La paleta de la Riviera: cada casa coge un revoco distinto del vecino, si no se lee como un bloque solo.
REVOCOS = ("revoco_crema", "revoco_melocoton", "revoco_rosa", "revoco_ocre", "revoco_amarillo",
           "revoco_arena", "revoco_blanco", "revoco_terracota")
TEJAS = ("teja", "teja_vieja", "teja_clara")
POSTIGOS = ("contraventana", "contraventana", "contraventana_azul")     # el verde manda, el azul salpica
TOLDOS = ("toldo_rojo", "toldo_crema", "toldo_verde")
ROPA = ("toldo_crema", "lona", "toldo_rojo", "toldo_verde", "revoco_blanco")

CALIDA = (255, 196, 130)
DORADA = (255, 214, 150)


def _R(rng, a, b):
    return a + (b - a) * rng.random()


def _r2(x):
    """a la rejilla de 0,2 m: los muros de 0,3 caen igual en la version de 10 cm y en la de 20"""
    return round(x * 5.0) / 5.0


class _Local(Lienzo):
    """Lienzo en coordenadas de la zona: u (0..W) al este, v (0..D) al sur, y = metros sobre suelo_y.
    Hereda escalera() y escombros() del Lienzo porque esas llaman a caja(), que aqui traslada y reenvia."""

    def __init__(self, base, ox, oz, oy):
        self.base, self.ox, self.oz, self.oy = base, ox, oz, oy

    def caja(self, x0, y0, z0, x1, y1, z1, mat="hormigon", hueco=False):
        self.base.caja(self.ox + x0, self.oy + y0, self.oz + z0,
                       self.ox + x1, self.oy + y1, self.oz + z1, mat, hueco)

    def cilindro(self, cx, y0, cz, radio, alto, mat="metal", hueco=False, eje="y"):
        self.base.cilindro(self.ox + cx, self.oy + y0, self.oz + cz, radio, alto, mat, hueco, eje)

    def elipsoide(self, cx, cy, cz, rx, ry, rz, mat="tierra", hueco=False):
        self.base.elipsoide(self.ox + cx, self.oy + cy, self.oz + cz, rx, ry, rz, mat, hueco)

    def esfera(self, cx, cy, cz, radio, mat="tierra", hueco=False):
        self.elipsoide(cx, cy, cz, radio, radio, radio, mat, hueco)

    def linea(self, x0, y0, z0, x1, y1, z1, grosor, mat="metal", hueco=False):
        # nada macizo por debajo de 0,2 m: a 20 cm (la version _lo) se descose en trozos sueltos que el
        # motor tira al suelo nada mas cargar el mapa
        if not hueco:
            grosor = max(grosor, 0.2)
        self.base.linea(self.ox + x0, self.oy + y0, self.oz + z0,
                        self.ox + x1, self.oy + y1, self.oz + z1, grosor, mat, hueco)

    def cuna(self, x0, y0, z0, x1, y1, z1, sube_hacia="+x", mat="hormigon", hueco=False):
        self.base.cuna(self.ox + x0, self.oy + y0, self.oz + z0,
                       self.ox + x1, self.oy + y1, self.oz + z1, sube_hacia, mat, hueco)

    def luz(self, x, y, z, color=CALIDA, energia=1.0, alcance=8.0, direccion=None, cono=0.0):
        self.base.luz(self.ox + x, self.oy + y, self.oz + z, color, energia, alcance, direccion, cono)

    def punto(self, x, y, z, tipo="criatura"):
        self.base.punto(self.ox + x, self.oy + y, self.oz + z, tipo)


class _Cara:
    """Coordenadas de FACHADA: h corre a lo largo del muro, d sale hacia la calle, y es la altura absoluta
    de la zona. Asi una ventana, un balcon o un toldo se describen una sola vez y valen para las cuatro
    orientaciones; el origen h=0 es siempre la esquina izquierda mirando la fachada desde fuera."""

    _EJES = {"-v": (1.0, 0.0, 0.0, -1.0),
             "+v": (-1.0, 0.0, 0.0, 1.0),
             "-u": (0.0, -1.0, -1.0, 0.0),
             "+u": (0.0, 1.0, 1.0, 0.0)}
    _SUBE = {(0.0, -1.0): "+z", (0.0, 1.0): "-z", (-1.0, 0.0): "+x", (1.0, 0.0): "-x"}

    def __init__(self, L, u0, v0, u1, v1, cara):
        self.L, self.cara = L, cara
        self.hu, self.hv, self.du, self.dv = self._EJES[cara]
        # la esquina de arranque y el largo de la fachada salen del rectangulo de la casa
        if cara == "-v":
            self.ou, self.ov, self.largo = u0, v0, u1 - u0
        elif cara == "+v":
            self.ou, self.ov, self.largo = u1, v1, u1 - u0
        elif cara == "-u":
            self.ou, self.ov, self.largo = u0, v1, v1 - v0
        else:
            self.ou, self.ov, self.largo = u1, v0, v1 - v0

    def uv(self, h, d):
        return (self.ou + self.hu * h + self.du * d, self.ov + self.hv * h + self.dv * d)

    def caja(self, h0, y0, d0, h1, y1, d1, mat="hormigon", hueco=False):
        a = self.uv(h0, d0)
        b = self.uv(h1, d1)
        self.L.caja(min(a[0], b[0]), y0, min(a[1], b[1]), max(a[0], b[0]), y1, max(a[1], b[1]), mat, hueco)

    def linea(self, h0, y0, d0, h1, y1, d1, g, mat="hierro", hueco=False):
        a = self.uv(h0, d0)
        b = self.uv(h1, d1)
        self.L.linea(a[0], y0, a[1], b[0], y1, b[1], g, mat, hueco)

    def cil(self, h, y, d, radio, alto, mat="hierro"):
        u, v = self.uv(h, d)
        self.L.cilindro(u, y, v, radio, alto, mat)

    def eli(self, h, y, d, rh, ry, rd, mat="hormigon", hueco=False):
        u, v = self.uv(h, d)
        rx, rz = (rh, rd) if abs(self.hu) > 0.5 else (rd, rh)
        self.L.elipsoide(u, y, v, rx, ry, rz, mat, hueco)

    def cuna_saliente(self, h0, h1, y_alto, y_bajo, d0, d1, mat):
        """plano inclinado que cae desde la pared hacia la calle (toldos, aleros rotos)"""
        a = self.uv(h0, d0)
        b = self.uv(h1, d1)
        self.L.cuna(min(a[0], b[0]), y_bajo, min(a[1], b[1]), max(a[0], b[0]), y_alto, max(a[1], b[1]),
                    self._SUBE[(self.du, self.dv)], mat)


# =========================================================================================================
# PIEZAS SUELTAS DE FACHADA Y DE CALLE
# =========================================================================================================

def _barandilla(F, h0, h1, y, d, alto=1.0, paso=0.42, mat="hierro"):
    """Barandilla de hierro forjado: zapata, pasamanos y barrotes. Todo en cajas y no en lineas: una linea
    de 0,1 se evapora en la version de 20 cm y la barandilla se queda flotando. Los barrotes van a 0,42 m y
    con 0,1 de grueso (un voxel entero) porque mas juntos y mas finos solo cuesta primitivas: a 10 cm ni se
    distinguen y a 20 no existen."""
    F.caja(h0, y, d - 0.06, h1, y + 0.1, d + 0.06, mat)
    F.caja(h0, y + alto - 0.12, d - 0.07, h1, y + alto, d + 0.07, mat)
    n = max(2, int((h1 - h0) / paso))
    for i in range(n + 1):
        hh = h0 + (h1 - h0) * i / n
        F.caja(hh - 0.05, y, d - 0.05, hh + 0.05, y + alto, d + 0.05, mat)


def _maceta(L, u, v, y, rng, radio=0.24, flor=True):
    """tiesto de barro con geranios: el detalle que mas colorea la calle y las barandillas"""
    L.cilindro(u, y, v, radio, 0.3, "revoco_terracota")
    L.cilindro(u, y + 0.3, v, radio + 0.03, 0.06, "revoco_terracota")
    L.cilindro(u, y + 0.26, v, radio - 0.05, 0.08, "tierra")
    L.esfera(u, y + 0.42, v, radio * 0.95, "hoja_seto")
    if flor:
        for _ in range(3):
            a = rng.random() * math.tau
            r = radio * 0.75
            L.esfera(u + math.cos(a) * r, y + 0.5 + rng.random() * 0.12, v + math.sin(a) * r, 0.09,
                     "flor_roja" if rng.random() < 0.6 else "flor_rosa")


def _ventana(F, rng, h, y, ancho, alto, mat, postigo, esp=MURO, balcon=0.0, reja=False):
    """Hueco de ventana con cerco de caliza, contraventanas de madera y, si se pide, balcon volado.
    Las de arriba son grandes a proposito (1,6 x 1,8 con antepecho bajo): se entra y se dispara por ellas."""
    m = ancho * 0.5
    F.caja(h - m, y, -0.16, h + m, y + alto, esp + 0.16, mat, hueco=True)
    F.caja(h - m - 0.16, y - 0.18, -0.2, h + m + 0.16, y, 0.05, "caliza")            # alfeizar volado
    F.caja(h - m - 0.16, y + alto, -0.12, h + m + 0.16, y + alto + 0.18, 0.05, "caliza")   # dintel
    F.caja(h - m - 0.1, y, -0.06, h - m, y + alto, 0.04, "caliza_sombra")            # jambas
    F.caja(h + m, y, -0.06, h + m + 0.1, y + alto, 0.04, "caliza_sombra")
    # EL CRISTAL MUERDE EL CERCO. Iba METIDO 4 cm en horizontal y 5 en vertical respecto al hueco, y
    # a 10 cm por voxel eso es MEDIO voxel: segun donde cayeran `h`, `y` y `alto` en la rejilla, el
    # margen redondeaba a 0 o a 1 voxel. Las que caian del lado malo quedaban sin tocar el marco por
    # ningun lado. Auditado con tools/auditar_flotadores.py: 40 paneles de 48 voxels flotando en el
    # casco, a y=10,1 y y=12,1 m. Como un mapa recien cargado no se derrumba (regla "pristine"), ahi
    # se quedaban hasta que dañabas cualquier cosa de su conjunto, y entonces caian todos de golpe.
    #
    # LA MORDIDA TIENE QUE SER DE 0,25 m PARA ARRIBA. Con 0,12 el cristal ya mordia el cerco en el mapa
    # de 10 cm, pero el que manda es el `_lo` de 20 cm (es el que va en el APK y el que se usa en LAN)
    # y ahi 0,12 m no llega ni a un voxel: seguian saliendo ~150 paneles sueltos de 6-10 voxels. Con
    # 0,3 m entra voxel y medio a 20 cm, que ya no lo tumba ningun redondeo. Sigue sin verse: son 6 cm
    # de espesor metidos en la jamba, por dentro del muro.
    MORDIDA = 0.3
    # ...Y TIENE QUE ESTAR DENTRO DEL HUECO. El cristal se pintaba a `esp - 0.12` de fondo, y en este
    # modulo la `d` de `_Cara` SALE HACIA LA CALLE (ver `_Cara.uv`): o sea que la hoja acababa a 19 cm
    # POR DELANTE de la fachada, colgada en el aire delante del agujero. Por ancha que se hiciera la
    # mordida nunca tocaba piedra, porque a esa profundidad no hay muro a ninguna altura. Medido en
    # monaco_lo: la hoja de la casa de x 34,4 salia en x 34,16..34,21 con el muro empezando en 34,40.
    # Ahora va a d negativa, o sea metida en el mocheta del hueco (que esta vaciado hasta d = -0,16),
    # y lo que sobresale por los lados cae en sillar macizo.
    FONDO0, FONDO1 = -0.14, -0.08
    estado = rng.random()
    if estado < 0.5:                                        # cristal entero
        F.caja(h - m - MORDIDA, y - MORDIDA, FONDO0, h + m + MORDIDA, y + alto + MORDIDA, FONDO1, "vidrio")
        F.caja(h - 0.04, y - MORDIDA, FONDO0 - 0.01, h + 0.04, y + alto + MORDIDA, FONDO1 + 0.01, "madera")   # parteluz
    elif estado < 0.72:                                     # reventado: solo quedan esquirlas en el cerco
        # ...Y LAS ESQUIRLAS TAMBIEN. El comentario decia "en el cerco" pero se colocaban en un punto
        # AL AZAR dentro del hueco, o sea flotando en mitad de la ventana: eran ~90 conjuntos sueltos
        # mas. Ahora cada una nace pegada a un lado del hueco y se mete en el muro.
        for _ in range(3):
            lado = rng.randrange(4)
            if lado == 0:      # colgando del dintel
                hh = h - m + 0.1 + rng.random() * max(0.1, ancho - 0.2)
                F.caja(hh, y + alto - 0.25, FONDO0, hh + 0.12, y + alto + MORDIDA, FONDO1, "vidrio")
            elif lado == 1:    # subiendo del alfeizar
                hh = h - m + 0.1 + rng.random() * max(0.1, ancho - 0.2)
                F.caja(hh, y - MORDIDA, FONDO0, hh + 0.12, y + 0.25, FONDO1, "vidrio")
            elif lado == 2:    # clavada en la jamba izquierda
                yy = y + 0.05 + rng.random() * max(0.1, alto - 0.3)
                F.caja(h - m - MORDIDA, yy, FONDO0, h - m + 0.12, yy + 0.25, FONDO1, "vidrio")
            else:              # clavada en la jamba derecha
                yy = y + 0.05 + rng.random() * max(0.1, alto - 0.3)
                F.caja(h + m - 0.12, yy, FONDO0, h + m + MORDIDA, yy + 0.25, FONDO1, "vidrio")
    # contraventanas: casi siempre plegadas contra la fachada, a veces una hoja cerrada de par en par
    if rng.random() < 0.78:
        for s in (-1.0, 1.0):
            a = h + s * m
            b = a + s * m * 0.92
            F.caja(min(a, b), y, -0.1, max(a, b), y + alto, -0.03, postigo)
            F.caja(min(a, b) + 0.05, y + alto * 0.55, -0.11, max(a, b) - 0.05, y + alto * 0.62, -0.02,
                   "madera")                                 # travesano de la hoja
    else:
        F.caja(h - m, y, -0.1, h + m, y + alto, -0.03, postigo)
        F.caja(h - 0.03, y, -0.11, h + 0.03, y + alto, -0.02, "madera")
    if rng.random() < 0.35:                                  # persiana a medio bajar
        F.caja(h - m, y + alto * 0.45, esp - 0.2, h + m, y + alto, esp - 0.14, "madera_clara")
    if balcon > 0.0:
        F.caja(h - m - 0.34, y - 0.22, -balcon, h + m + 0.34, y, 0.02, "caliza")     # losa
        for s in (-1.0, 1.0):                                # mensulas: la losa no puede salir de la nada
            hh = h + s * (m + 0.22)
            F.caja(hh - 0.09, y - 0.5, -balcon * 0.55, hh + 0.09, y - 0.2, 0.02, "caliza_sombra")
        bm = "hierro" if rng.random() < 0.82 else "hierro_blanco"    # alguna barandilla repintada de blanco
        _barandilla(F, h - m - 0.3, h + m + 0.3, y, -balcon + 0.08, 1.02, mat=bm)
        _barandilla(F, h - m - 0.3, h - m - 0.24, y, -balcon * 0.5, 1.02, mat=bm)
        _barandilla(F, h + m + 0.24, h + m + 0.3, y, -balcon * 0.5, 1.02, mat=bm)
        if rng.random() < 0.6:
            u, v = F.uv(h + _R(rng, -m, m), -balcon + 0.3)
            _maceta(F.L, u, v, y, rng, 0.2)
    elif reja:                                               # reja de planta baja o balconcillo de antepecho
        _barandilla(F, h - m, h + m, y, -0.16, 0.95)


def _puerta(F, rng, h, y, ancho, alto, mat, esp=MURO, portal=True):
    """portal de vivienda: 1,6 x 2,9 libres, jambas de caliza, dintel y numero de la casa"""
    m = ancho * 0.5
    F.caja(h - m, y, -0.2, h + m, y + alto, esp + 0.2, mat, hueco=True)
    F.caja(h - m - 0.14, y, -0.08, h - m, y + alto + 0.18, 0.06, "caliza")
    F.caja(h + m, y, -0.08, h + m + 0.14, y + alto + 0.18, 0.06, "caliza")
    F.caja(h - m - 0.14, y + alto, -0.12, h + m + 0.14, y + alto + 0.18, 0.06, "caliza")
    if portal:
        # hoja entornada pegada a una jamba: deja mas de 1,4 m de paso libre
        F.caja(h - m + 0.04, y, esp - 0.1, h - m + 0.1, y + alto - 0.05, esp + 0.34, "madera")
        F.caja(h - m + 0.06, y + 1.0, esp + 0.3, h - m + 0.1, y + 1.15, esp + 0.36, "laton")
    F.caja(h - 0.12, y + alto + 0.2, -0.06, h + 0.12, y + alto + 0.42, 0.02, "caliza_clara")   # placa del numero


def _toldo(F, rng, h0, h1, y, saliente=1.5, mat=None):
    """toldo de lona sobre el bajo comercial: cae 0,45 m de la pared a la calle y lleva sus tirantes"""
    mat = mat or TOLDOS[rng.randrange(len(TOLDOS))]
    F.cuna_saliente(h0, h1, y, y - 0.45, 0.0, -saliente, mat)
    F.caja(h0, y - 0.55, -saliente - 0.06, h1, y - 0.4, -saliente + 0.04, mat)      # faldon del borde
    for s in (h0 + 0.15, h1 - 0.15):
        F.linea(s, y, 0.0, s, y - 0.42, -saliente, 0.09, "hierro")
    F.caja(h0 - 0.06, y - 0.04, -0.12, h1 + 0.06, y + 0.1, 0.04, "hierro")          # carril contra la pared


def _rotulo(F, rng, h0, h1, y):
    """chapa de comercio sobre la puerta: un rectangulo de color y su marco de laton, nada de letras"""
    mat = ("toldo_verde", "toldo_rojo", "madera", "hierro")[rng.randrange(4)]
    F.caja(h0, y, -0.14, h1, y + 0.45, -0.06, mat)
    F.caja(h0 - 0.05, y - 0.05, -0.16, h1 + 0.05, y, -0.04, "laton")
    F.caja(h0 - 0.05, y + 0.45, -0.16, h1 + 0.05, y + 0.5, -0.04, "laton")


def _farola(L, rng, u, v, y, cara="-v", alto=3.8, rota=False, luz=False):
    """Farola de hierro de brazo curvo. El vidrio del farol es material de tipo luz: brilla solo, asi que
    la mayoria alumbran sin gastar un OmniLight (el mapa entero tiene presupuesto para 160 y esta zona es
    una sexta parte). Las que si llevan foco de verdad ponen la bombilla DONDE ESTA EL farol, no dentro del
    poste, o el cono de luz cae en el sitio equivocado."""
    du, dv = {"-v": (0.0, -1.0), "+v": (0.0, 1.0), "-u": (-1.0, 0.0), "+u": (1.0, 0.0)}[cara]
    L.cilindro(u, y, v, 0.11, alto, "hierro")
    L.cilindro(u, y, v, 0.19, 0.35, "hierro")
    bx, bz = u + du * 0.75, v + dv * 0.75
    L.linea(u, y + alto, v, bx, y + alto + 0.28, bz, 0.12, "hierro")
    L.caja(bx - 0.22, y + alto - 0.15, bz - 0.22, bx + 0.22, y + alto + 0.28, bz + 0.22,
           "metal_oxidado" if rota else "luz_calida")
    L.caja(bx - 0.16, y + alto + 0.26, bz - 0.16, bx + 0.16, y + alto + 0.44, bz + 0.16, "hierro")
    if rota:                                    # el cristal reventado, en el suelo al pie del poste
        L.caja(bx - 0.3, y, bz - 0.3, bx + 0.1, y + 0.06, bz + 0.1, "vidrio")
    elif luz:
        L.luz(bx, y + alto - 0.2, bz, CALIDA, 0.9, 11.0, (0.0, -1.0, 0.0), 38.0)


def _aplique(L, rng, F, h, y, encendido=True):
    """Farol de pared: en el casco viejo cuelgan de las esquinas y de encima de los portales. Nunca gasta
    un OmniLight (son demasiados): el vidrio es material de tipo luz y se ilumina el solo."""
    F.caja(h - 0.05, y, -0.1, h + 0.05, y + 0.5, 0.02, "hierro")
    F.linea(h, y + 0.45, -0.06, h, y + 0.45, -0.55, 0.1, "hierro")
    F.caja(h - 0.17, y + 0.05, -0.72, h + 0.17, y + 0.46, -0.38, "luz_dorada" if encendido else "hierro")
    F.caja(h - 0.2, y + 0.44, -0.75, h + 0.2, y + 0.6, -0.35, "hierro")


def _tendal(L, rng, u0, v0, u1, v1, y, empotre=0.8, apoyo=None):
    """ropa tendida cruzando el callejon: la cuerda de fachada a fachada y las prendas colgando de ella.

    LA CUERDA TIENE QUE MORDER LAS DOS FACHADAS. Se tendia de borde a borde de la calle y ahi se
    acababa, sin meterse en la piedra: la cuerda entera y toda su ropa quedaban sueltas en el aire, y
    al primer disparo en la manzana se desplomaban. Eran los conjuntos sueltos mayores del casco
    (160-270 voxels cada uno). Ahora los dos extremos se alargan `empotre` metros MAS ALLA de la
    calle, o sea dentro del muro: no se ve, porque esta enterrado en la fachada.
    Aviso: la mordida tiene que pasar de 0,25 m o no sobrevive al mapa `_lo` de 20 cm, que es el que
    va al APK y el que se usa en LAN."""
    largo = math.hypot(u1 - u0, v1 - v0)
    eu = (u1 - u0) / max(largo, 1e-6) * empotre
    ev = (v1 - v0) / max(largo, 1e-6) * empotre
    L.linea(u0 - eu, y, v0 - ev, u1 + eu, y - 0.12, v1 + ev, 0.08, "hierro")
    if apoyo is not None:
        # la cuerda de azotea no cruza a ninguna fachada: se tiende entre DOS PALOS clavados en el
        # suelo de la terraza. Sin ellos colgaba del aire y era el conjunto suelto mayor del casco
        # (289 voxels con toda su ropa) cada vez que a una casa le tocaba tendal.
        for a, b, yy in ((u0 - eu, v0 - ev, y), (u1 + eu, v1 + ev, y - 0.12)):
            L.cilindro(a, apoyo - 0.2, b, 0.11, yy - apoyo + 0.35, "hierro")
    n = max(2, int(largo / 0.75))
    for i in range(n):
        t = (i + 0.5) / n
        u = u0 + (u1 - u0) * t
        v = v0 + (v1 - v0) * t
        yy = y - 0.12 * math.sin(math.pi * t)
        ancho = _R(rng, 0.22, 0.42)
        largo_p = _R(rng, 0.5, 1.0)
        mat = ROPA[rng.randrange(len(ROPA))]
        if abs(u1 - u0) > abs(v1 - v0):
            L.caja(u - ancho * 0.5, yy - largo_p, v - 0.06, u + ancho * 0.5, yy, v + 0.06, mat)
        else:
            L.caja(u - 0.06, yy - largo_p, v - ancho * 0.5, u + 0.06, yy, v + ancho * 0.5, mat)


def _banco(L, u, v, y, eje="u", largo=1.8):
    """banco de piedra con patas de hierro, de los de plazoleta"""
    if eje == "u":
        L.caja(u - largo * 0.5, y + 0.4, v - 0.22, u + largo * 0.5, y + 0.52, v + 0.22, "caliza")
        for s in (-1.0, 1.0):
            L.caja(u + s * (largo * 0.5 - 0.2), y, v - 0.2, u + s * (largo * 0.5 - 0.08), y + 0.4, v + 0.2,
                   "hierro")
        L.caja(u - largo * 0.5, y + 0.52, v + 0.1, u + largo * 0.5, y + 0.95, v + 0.2, "madera")
    else:
        L.caja(u - 0.22, y + 0.4, v - largo * 0.5, u + 0.22, y + 0.52, v + largo * 0.5, "caliza")
        for s in (-1.0, 1.0):
            L.caja(u - 0.2, y, v + s * (largo * 0.5 - 0.2), u + 0.2, y + 0.4, v + s * (largo * 0.5 - 0.08),
                   "hierro")
        L.caja(u + 0.1, y + 0.52, v - largo * 0.5, u + 0.2, y + 0.95, v + largo * 0.5, "madera")


def _fuente(L, rng, u, v, y, radio=1.6):
    """fuente de plazoleta: pilon de caliza, agua y columna con canos de laton"""
    L.cilindro(u, y, v, radio, 0.85, "caliza")
    L.cilindro(u, y + 0.25, v, radio - 0.28, 0.75, "caliza", hueco=True)
    L.cilindro(u, y + 0.25, v, radio - 0.3, 0.42, "agua_mar")
    L.cilindro(u, y + 0.8, v, radio + 0.06, 0.12, "marmol")       # el brocal, de marmol como el de verdad
    L.cilindro(u, y + 0.25, v, 0.3, 1.9, "caliza")
    L.cilindro(u, y + 2.15, v, 0.55, 0.22, "marmol")
    L.esfera(u, y + 2.45, v, 0.3, "marmol")
    for k in range(4):
        a = k * math.pi * 0.5 + 0.4
        L.linea(u + math.cos(a) * 0.3, y + 1.75, v + math.sin(a) * 0.3,
                u + math.cos(a) * 0.62, y + 1.6, v + math.sin(a) * 0.62, 0.12, "laton")
        L.linea(u + math.cos(a) * 0.62, y + 1.55, v + math.sin(a) * 0.62,
                u + math.cos(a) * 0.62, y + 0.7, v + math.sin(a) * 0.62, 0.09, "agua_mar")


def _arbol(L, rng, u, v, y, alto=5.0, tipo="palmera"):
    if tipo == "cipres":
        L.cilindro(u, y, v, 0.24, alto * 0.25, "tronco")
        for k in range(6):
            t = k / 5.0
            L.elipsoide(u, y + alto * (0.25 + 0.72 * t), v, 0.95 * (1.0 - t * 0.75), alto * 0.1,
                        0.95 * (1.0 - t * 0.75), "cipres")
        return
    L.cilindro(u, y, v, 0.28, alto, "tronco")
    for k in range(7):
        a = k * math.tau / 7.0 + rng.random() * 0.3
        r = _R(rng, 1.5, 2.4)
        L.linea(u, y + alto, v, u + math.cos(a) * r, y + alto + _R(rng, -0.6, 0.7), v + math.sin(a) * r,
                0.42, "hoja_palmera")
    L.esfera(u, y + alto + 0.1, v, 0.5, "hoja_oscura")


def _papelera(L, u, v, y):
    L.cilindro(u, y, v, 0.26, 0.85, "hierro")
    L.cilindro(u, y + 0.12, v, 0.2, 0.7, "hierro", hueco=True)
    L.cilindro(u, y + 0.8, v, 0.3, 0.08, "hierro")


def _cascotes(L, rng, u, v, y, radio, n, mats=("escombro", "escombro_claro", "ladrillo", "teja_vieja")):
    """monton de cascote bajo (menos de 0,35 m): se pisa sin saltar y no corta el callejon"""
    for _ in range(n):
        a = rng.random() * math.tau
        r = radio * math.sqrt(rng.random())
        s = _R(rng, 0.14, 0.4)
        uu, vv = u + math.cos(a) * r, v + math.sin(a) * r
        L.caja(uu - s, y, vv - s * 0.75, uu + s, y + _R(rng, 0.08, 0.33), vv + s * 0.75,
               mats[rng.randrange(len(mats))])


def _polvo(L, rng, u, v, y, radio, n=5):
    """la capa de polvo de yeso alrededor de lo que se ha caido: solo tine el voxel de arriba del suelo"""
    for _ in range(n):
        a = rng.random() * math.tau
        r = radio * rng.random()
        rr = radio * _R(rng, 0.35, 0.8)
        L.elipsoide(u + math.cos(a) * r, y - 0.04, v + math.sin(a) * r, rr, 0.06, rr * 0.85, "polvo")


# =========================================================================================================
# ESCALERAS PUBLICAS
# =========================================================================================================

def _escalinata(L, rng, u0, v0, y0, largo, ancho, alto, hacia, mat="caliza", pretil=True, faroles=0):
    """La escalinata publica del casco: peldanos de 0,25 (los pone Lienzo.escalera), pretiles macizos a los
    lados y pasamanos de hierro. Los pretiles son cajas y no lineas: una linea inclinada de 0,12 se rompe a
    20 cm y el pasamanos se queda en el aire."""
    L.escalera(u0, v0, y0, largo, ancho, alto, hacia, mat)
    if not pretil:
        return
    vertical = hacia in ("+z", "-z")
    n = max(1, int(math.ceil(alto / 0.25)))
    for k in range(n):
        h = y0 + alto * (k + 1) / n
        a0 = largo * k / n
        a1 = largo * (k + 1) / n
        for lado in (0.0, ancho - 0.24):
            if vertical:
                s = 1.0 if hacia == "+z" else -1.0
                z0 = v0 + s * a0
                z1 = v0 + s * a1
                L.caja(u0 + lado, y0, min(z0, z1), u0 + lado + 0.24, h + 0.82, max(z0, z1), "caliza_sombra")
                L.caja(u0 + lado - 0.04, h + 0.82, min(z0, z1), u0 + lado + 0.28, h + 0.94, max(z0, z1),
                       "caliza_clara")
            else:
                s = 1.0 if hacia == "+x" else -1.0
                x0 = u0 + s * a0
                x1 = u0 + s * a1
                L.caja(min(x0, x1), y0, v0 + lado, max(x0, x1), h + 0.82, v0 + lado + 0.24, "caliza_sombra")
                L.caja(min(x0, x1), h + 0.82, v0 + lado - 0.04, max(x0, x1), h + 0.94, v0 + lado + 0.28,
                       "caliza_clara")
    # faroles en el arranque y en la llegada, que es donde de verdad hacen falta de noche
    for i in range(faroles):
        t = 0.15 if i == 0 else 0.9
        h = y0 + alto * t + 0.95
        if vertical:
            s = 1.0 if hacia == "+z" else -1.0
            u = u0 + (0.12 if i % 2 == 0 else ancho - 0.12)
            v = v0 + s * largo * t
        else:
            s = 1.0 if hacia == "+x" else -1.0
            u = u0 + s * largo * t
            v = v0 + (0.12 if i % 2 == 0 else ancho - 0.12)
        L.cilindro(u, h, v, 0.09, 0.9, "hierro")
        L.caja(u - 0.19, h + 0.9, v - 0.19, u + 0.19, h + 1.35, v + 0.19, "luz_calida")
        L.caja(u - 0.22, h + 1.33, v - 0.22, u + 0.22, h + 1.5, v + 0.22, "hierro")
        # foco de verdad solo en una de cada dos escalinatas: el presupuesto de luces del mapa es corto y
        # lo que hace falta es que se VEA donde arranca la escalera
        if rng.random() < 0.5:
            L.luz(u, h + 1.0, v, CALIDA, 0.85, 10.0, (0.0, -1.0, 0.0), 42.0)


def _peldanos(L, u0, v0, y0, largo, ancho, alto, hacia, mat="caliza_sombra"):
    """escalerilla sin pretil: portales, azoteas y patios. Mismo peldano de 0,25."""
    L.escalera(u0, v0, y0, largo, ancho, alto, hacia, mat)


ESC_EXT = (6.4, 3.2)      # huella de la escalera exterior: 1,6 rellano + 3,4 tramo + 1,4 rellano


def _escalera_exterior(L, rng, u0, v0, base, plantas, mat="caliza"):
    """LA ESCALERA EXTERIOR del patio: tramos de piedra que suben de la calle a la azotea dando la vuelta
    en cada planta, arrimados a la medianera ciega del vecino. Ocupa 6,4 x 3,2 m.

    Los dos tramos NO pueden ir por el mismo carril: al que sube se le vendria encima el tramo siguiente a
    media planta (el peldano es macizo desde su arranque). Por eso la ida va por el carril sur y la vuelta
    por el norte, y los rellanos alternan de punta. El ultimo tramo siempre acaba en el rellano de PONIENTE,
    que es el que hace tope contra la azotea del vecino.

    Nada cuelga del aire: los dos rellanos se apoyan en sendos pilares que suben desde la calle."""
    cima = base + plantas * PLANTA
    for u in (u0 + 0.8, u0 + 5.6):
        L.caja(u - 0.26, base - 0.9, v0 + 0.15, u + 0.26, cima, v0 + 3.05, mat)
        L.caja(u - 0.34, base - 0.9, v0 + 0.08, u + 0.34, base + 0.45, v0 + 3.12, "caliza_sombra")
    # si el numero de tramos es par hay que salir hacia el este para acabar mirando al oeste
    ida0 = (plantas % 2 == 0)
    for m in range(plantas):
        y = base + m * PLANTA
        ida = ida0 if m % 2 == 0 else not ida0
        if ida:
            L.escalera(u0 + 1.6, v0, y, 3.4, 1.4, PLANTA, "+x", mat)
            ru0, ru1 = u0 + 5.0, u0 + 6.4
            vb = v0 - 0.03
        else:
            L.escalera(u0 + 5.0, v0 + 1.8, y, 3.4, 1.4, PLANTA, "-x", mat)
            ru0, ru1 = u0, u0 + 1.6
            vb = v0 + 3.23
        L.caja(ru0, y + PLANTA - 0.3, v0, ru1, y + PLANTA, v0 + 3.2, mat)
        L.caja(ru0 - 0.06, y + PLANTA - 0.36, v0 - 0.06, ru1 + 0.06, y + PLANTA - 0.22, v0 + 3.26,
               "caliza_clara")
        # pasamanos por el lado abierto del tramo, siguiendo la pendiente peldano a peldano
        n = int(PLANTA / 0.25)
        for k in range(n + 1):
            t = k / float(n)
            uu = u0 + 1.6 + 3.4 * (t if ida else 1.0 - t)
            L.caja(uu - 0.05, y + PLANTA * t, vb - 0.05, uu + 0.05, y + PLANTA * t + 1.0, vb + 0.05, "hierro")
        L.caja(u0 + 1.6, y + 0.9, vb - 0.06, u0 + 5.0, y + PLANTA + 0.9, vb + 0.06, "hierro")
        # barandilla del rellano por sus dos cantos libres
        for vv in (v0 + 0.02, v0 + 3.18):
            L.caja(ru0, y + PLANTA, vv - 0.05, ru1, y + PLANTA + 1.0, vv + 0.05, "hierro")
        uc = ru1 - 0.05 if ida else ru0 + 0.05
        L.caja(uc - 0.05, y + PLANTA, v0, uc + 0.05, y + PLANTA + 1.0, v0 + 3.2, "hierro")


# =========================================================================================================
# LA CASA: prisma macizo, interior vaciado, hueco de escalera hasta la azotea y fachada con vida
# =========================================================================================================

def _hueco_escalera(L, rng, ua, va, base, plantas, eje, mat):
    """Hueco de escalera de ida y vuelta dentro de una casa. Ocupa 5,6 m en el eje del tiro y 3,0 m de
    ancho: dos tiros de 1,4 m separados por el ojo de 0,2 y el rellano de 1,4 al fondo. Los tiros alternan
    de carril en cada planta, que es la unica forma de que quede altura libre encima del que sube; si los
    dos fueran por el mismo carril te comerias el forjado con la cabeza a media planta.

    Devuelve (u, v) del punto por donde se sale a la azotea."""
    TIRO, ANCHO, RELLANO = 4.2, 1.4, 1.4

    def caja(a0, y0, b0, a1, y1, b1, m, hueco=False):
        """a = a lo largo del tiro, b = transversal"""
        if eje == "v":
            L.caja(ua + b0, y0, va + a0, ua + b1, y1, va + a1, m, hueco)
        else:
            L.caja(ua + a0, y0, va + b0, ua + a1, y1, va + b1, m, hueco)

    def tiro(a_ini, y0, ida):
        b0 = 0.0 if ida else 1.6
        if eje == "v":
            L.escalera(ua + b0, va + a_ini, base + y0, TIRO, ANCHO, PLANTA, "+z" if ida else "-z", mat)
        else:
            L.escalera(ua + a_ini, va + b0, base + y0, TIRO, ANCHO, PLANTA, "+x" if ida else "-x", mat)

    for m in range(plantas):
        ida = (m % 2 == 0)
        y0 = m * PLANTA
        tiro(0.0 if ida else TIRO, y0, ida)
        # el forjado de arriba se agujerea justo sobre el tiro que acaba de subir, y el ojo va abierto entero
        b0, b1 = (0.0, ANCHO) if ida else (1.6, 3.0)
        caja(-0.1, base + y0 + PLANTA - FORJADO - 0.05, b0, TIRO + 0.1, base + y0 + PLANTA + 0.05, b1,
             mat, hueco=True)
        caja(-0.1, base + y0, 1.4, TIRO + RELLANO, base + y0 + PLANTA + 0.05, 1.6, mat, hueco=True)
    salida_ida = ((plantas - 1) % 2 == 0)
    a_sal = TIRO if salida_ida else 0.0
    b_sal = 0.7 if salida_ida else 2.3
    if eje == "v":
        return ua + b_sal, va + a_sal
    return ua + a_sal, va + b_sal


def _casa(L, rng, u0, v0, u1, v1, base, plantas, mat, teja, caras, principal, interior=True, tocada=0.0):
    """Una casa entre medianeras. `caras` son los lados que dan a calle (llevan huecos, balcones y toldos);
    los demas son medianera ciega contra el vecino. `principal` es la fachada donde cae el portal.

    Devuelve la ficha que necesitan despues los enlaces de azotea y los danos."""
    alto = plantas * PLANTA
    cima = base + alto
    du, dv = u1 - u0, v1 - v0
    ficha = {"u0": u0, "v0": v0, "u1": u1, "v1": v1, "cima": cima, "base": base, "plantas": plantas,
             "caras": caras, "interior": False, "mat": mat}

    # --- el prisma y su piel -----------------------------------------------------------------------------
    L.caja(u0, base, v0, u1, cima, v1, mat)
    L.caja(u0, base, v0, u1, base + 0.95, v1, "caliza_sombra")          # zocalo de piedra contra la humedad
    L.caja(u0, cima - 0.22, v0, u1, cima, v1, teja)                     # el piso de la azotea, de teja
    for c in caras:
        # alero volado + cornisa: es lo que da sombra en la calle y la silueta de teja desde abajo
        F = _Cara(L, u0, v0, u1, v1, c)
        F.caja(-0.06, cima - 0.62, 0.0, F.largo + 0.06, cima - 0.46, -0.14, "caliza_clara")
        F.caja(-0.12, cima - 0.46, 0.0, F.largo + 0.12, cima - 0.16, -0.34, teja)
        F.caja(-0.12, cima - 0.16, 0.0, F.largo + 0.12, cima, -0.1, "caliza_sombra")

    # --- interior vaciado ---------------------------------------------------------------------------------
    di, dj = du - 2 * MURO, dv - 2 * MURO
    eje_tiro = "v" if dj >= di else "u"
    cabe = (max(di, dj) >= 5.9 and min(di, dj) >= 3.1)
    if interior and cabe and plantas >= 2:
        ficha["interior"] = True
        for m in range(plantas):
            y = base + m * PLANTA
            L.caja(u0 + MURO, y, v0 + MURO, u1 - MURO, y + PLANTA - FORJADO, v1 - MURO, mat, hueco=True)
        # la caja de escalera se arrima a una medianera para dejar libre la crujia de fachada
        if eje_tiro == "v":
            ua = u0 + MURO + (0.15 if rng.random() < 0.5 else max(0.15, di - 3.15))
            va = v0 + MURO + max(0.1, (dj - 5.6) * 0.5)
        else:
            ua = u0 + MURO + max(0.1, (di - 5.6) * 0.5)
            va = v0 + MURO + (0.15 if rng.random() < 0.5 else max(0.15, dj - 3.15))
        su, sv = _hueco_escalera(L, rng, ua, va, base, plantas, eje_tiro, mat)
        ficha["salida"] = (su, sv)
        # tabique de crujia con puerta de 1,6: parte el piso en dos cuartos sin encerrar la escalera
        for m in range(1, plantas):
            y = base + m * PLANTA
            if eje_tiro == "v":
                ut = u0 + MURO + di * (0.66 if ua - u0 - MURO < 1.0 else 0.3)
                L.caja(ut, y, v0 + MURO, ut + 0.22, y + PLANTA - FORJADO, v1 - MURO, "revoco_blanco")
                vp = v0 + MURO + dj * 0.5
                L.caja(ut - 0.1, y, vp - 0.8, ut + 0.32, y + 2.62, vp + 0.8, "revoco_blanco", hueco=True)
            else:
                vt = v0 + MURO + dj * (0.66 if va - v0 - MURO < 1.0 else 0.3)
                L.caja(u0 + MURO, y, vt, u1 - MURO, y + PLANTA - FORJADO, vt + 0.22, "revoco_blanco")
                up = u0 + MURO + di * 0.5
                L.caja(up - 0.8, y, vt - 0.1, up + 0.8, y + 2.62, vt + 0.32, "revoco_blanco", hueco=True)
        # brocal de 0,45 en los lados largos del ojo de la azotea: se ve el agujero desde arriba
        if eje_tiro == "v":
            for s in (-0.22, 3.0):
                L.caja(ua + s, cima, va - 0.1, ua + s + 0.22, cima + 0.45, va + 5.7, mat)
        else:
            for s in (-0.22, 3.0):
                L.caja(ua - 0.1, cima, va + s, ua + 5.7, cima + 0.45, va + s + 0.22, mat)

    # --- fachadas -----------------------------------------------------------------------------------------
    postigo = POSTIGOS[rng.randrange(len(POSTIGOS))]
    for c in caras:
        F = _Cara(L, u0, v0, u1, v1, c)
        Lf = F.largo
        n = max(1, int(Lf / 2.3))
        paso = Lf / n
        es_principal = (c == principal)
        for i in range(n):
            h = paso * (i + 0.5)
            if es_principal and i == n // 2:
                _puerta(F, rng, h, base, 1.6, 2.9, mat)
                _aplique(L, rng, F, h + 1.15, base + 2.9, rng.random() < 0.3)
            elif ficha["interior"] and paso > 2.6 and rng.random() < 0.45:
                # bajo comercial: hueco de 2,4 x 2,7, se entra y se dispara desde la calle
                F.caja(h - 1.2, base, -0.2, h + 1.2, base + 2.7, MURO + 0.2, mat, hueco=True)
                F.caja(h - 1.34, base + 2.7, -0.16, h + 1.34, base + 2.92, 0.06, "caliza")
                if rng.random() < 0.65:
                    F.caja(h - 1.16, base + 0.05, MURO - 0.12, h + 1.16, base + 2.62, MURO - 0.06,
                           "vidrio" if rng.random() < 0.6 else "vidrio_espejo")
                    F.caja(h - 0.04, base, MURO - 0.13, h + 0.04, base + 2.7, MURO - 0.05, "madera")
                _toldo(F, rng, h - 1.35, h + 1.35, base + 3.05, _R(rng, 1.2, 1.8))
                _rotulo(F, rng, h - 0.9, h + 0.9, base + 2.96)
            else:
                _ventana(F, rng, h, base + 0.95, 1.15, 1.7, mat, postigo, reja=True)
        for m in range(1, plantas):
            y = base + m * PLANTA + 0.9
            terraza = (m == 1 and rng.random() < 0.55)
            for i in range(n):
                h = paso * (i + 0.5)
                if terraza and n >= 2 and i == (0 if rng.random() < 0.5 else n - 1):
                    # puerta-ventana a balcon: por ahi se entra de un salto desde el tejado de enfrente
                    _ventana(F, rng, h, base + m * PLANTA + 0.02, 1.35, 2.35, mat, postigo,
                             balcon=_R(rng, 0.85, 1.15))
                else:
                    _ventana(F, rng, h, y, 1.55, 1.8, mat, postigo,
                             balcon=(_R(rng, 0.7, 1.0) if rng.random() < 0.3 else 0.0),
                             reja=(rng.random() < 0.35))
            if rng.random() < 0.12:
                _aplique(L, rng, F, paso * 0.5, y + 2.1, rng.random() < 0.45)
        # pretil de azotea sobre la calle (0,7 m, un parapeto de verdad) con sus gargolas
        F.caja(0.0, cima, 0.0, Lf, cima + 0.7, 0.26, mat)
        F.caja(-0.04, cima + 0.7, -0.05, Lf + 0.04, cima + 0.82, 0.3, "caliza_clara")
        ng = max(1, int(Lf / 2.2))
        for k in range(ng):
            hh = Lf * (k + 0.5) / ng
            F.caja(hh - 0.16, cima + 0.4, 0.02, hh + 0.16, cima + 0.7, 0.24, mat, hueco=True)

    # --- canalon y bajante: la linea vertical que rompe la fachada y de paso marca la medianera ----------
    for c in caras:
        F = _Cara(L, u0, v0, u1, v1, c)
        F.caja(0.06, cima - 0.72, -0.3, F.largo - 0.06, cima - 0.62, -0.16,
               "zinc" if rng.random() < 0.5 else "metal_oxidado")
        hb = 0.22 if rng.random() < 0.5 else F.largo - 0.22
        F.caja(hb - 0.09, base, -0.28, hb + 0.09, cima - 0.62, -0.1,
               "zinc" if rng.random() < 0.5 else "metal_oxidado")

    # --- medianeras de azotea: 0,35 m, se pasan de un tejado a otro de un paso ---------------------------
    for c in ("-u", "+u", "-v", "+v"):
        if c in caras:
            continue
        F = _Cara(L, u0, v0, u1, v1, c)
        F.caja(0.0, cima, 0.0, F.largo, cima + 0.35, 0.22, "caliza_sombra")

    # --- lo que vive en la azotea -------------------------------------------------------------------------
    for _ in range(1 + rng.randrange(2)):
        x, z = _R(rng, u0 + 0.6, u1 - 0.6), _R(rng, v0 + 0.6, v1 - 0.6)
        h = _R(rng, 0.9, 1.8)
        L.caja(x - 0.3, cima, z - 0.3, x + 0.3, cima + h, z + 0.3, "ladrillo")
        L.caja(x - 0.38, cima + h, z - 0.38, x + 0.38, cima + h + 0.14, z + 0.38, "teja_vieja")
        L.caja(x - 0.28, cima + h + 0.14, z - 0.28, x + 0.28, cima + h + 0.34, z + 0.28, "hierro")
    if rng.random() < 0.5:
        x, z = _R(rng, u0 + 0.9, u1 - 0.9), _R(rng, v0 + 0.9, v1 - 0.9)
        L.cilindro(x, cima, z, 0.55, 1.1, "zinc")
        L.cilindro(x, cima + 1.1, z, 0.58, 0.1, "metal")
        L.linea(x + 0.5, cima + 0.3, z, x + 0.5, cima, z + 0.8, 0.1, "metal")
    if rng.random() < 0.45:
        x, z = _R(rng, u0 + 0.5, u1 - 0.5), _R(rng, v0 + 0.5, v1 - 0.5)
        L.cilindro(x, cima, z, 0.09, _R(rng, 1.6, 2.8), "metal")
        for k in range(3):
            L.linea(x - 0.55, cima + 1.8 + k * 0.28, z, x + 0.55, cima + 1.8 + k * 0.28, z, 0.07, "metal")
    for _ in range(rng.randrange(4)):
        _maceta(L, _R(rng, u0 + 0.5, u1 - 0.5), _R(rng, v0 + 0.5, v1 - 0.5), cima, rng, 0.22)
    if rng.random() < 0.4 and du > 2.0 and dv > 2.0:
        _tendal(L, rng, u0 + 0.5, v0 + 0.7, u1 - 0.5, v1 - 0.9, cima + 1.9, 0.0, apoyo=cima)

    # --- boquetes de proyectil en la fachada --------------------------------------------------------------
    if tocada > 0.0 and caras:
        for _ in range(int(tocada * 3) + 1):
            F = _Cara(L, u0, v0, u1, v1, caras[rng.randrange(len(caras))])
            h = _R(rng, 0.8, max(1.0, F.largo - 0.8))
            y = base + _R(rng, 1.2, max(2.0, alto - 1.5))
            r = _R(rng, 0.45, 1.0)
            F.eli(h, y, MURO * 0.5, r, r * 0.85, MURO * 1.8, mat, hueco=True)
            for _ in range(3):
                F.eli(h + _R(rng, -r, r), y + _R(rng, -r, r), MURO * 0.5, r * 0.5, r * 0.45, MURO * 1.8,
                      mat, hueco=True)
            F.caja(h - r - 0.2, y - r - 0.35, -0.04, h + r + 0.2, y + r + 0.3, 0.02, "hormigon_visto")
    return ficha


def _escalerilla_medianera(L, rng, baja, alta):
    """Escalerilla de azotea contra la medianera: si un vecino saca mas de 1,2 m al otro, esto es lo que
    deja seguir andando por los tejados sin bajar a la calle. Peldano de 0,25 y 1,4 m de ancho."""
    dh = alta["cima"] - baja["cima"]
    if dh <= 1.2 or dh > 3.6:
        return False
    largo = min(4.4, max(1.6, dh * 1.3))
    if baja["u1"] <= alta["u0"] + 0.01 or alta["u1"] <= baja["u0"] + 0.01:
        v = max(baja["v0"], alta["v0"]) + 0.6
        if baja["u1"] - baja["u0"] < largo + 0.5 or min(baja["v1"], alta["v1"]) - v < 1.5:
            return False
        if baja["u1"] <= alta["u0"] + 0.01:
            _peldanos(L, baja["u1"] - largo, v, baja["cima"], largo, 1.4, dh, "+x")
        else:
            _peldanos(L, baja["u0"] + largo, v, baja["cima"], largo, 1.4, dh, "-x")
        return True
    if baja["v1"] <= alta["v0"] + 0.01 or alta["v1"] <= baja["v0"] + 0.01:
        u = max(baja["u0"], alta["u0"]) + 0.6
        if baja["v1"] - baja["v0"] < largo + 0.5 or min(baja["u1"], alta["u1"]) - u < 1.5:
            return False
        if baja["v1"] <= alta["v0"] + 0.01:
            _peldanos(L, u, baja["v1"] - largo, baja["cima"], largo, 1.4, dh, "+z")
        else:
            _peldanos(L, u, baja["v0"] + largo, baja["cima"], largo, 1.4, dh, "-z")
        return True
    return False


def _manzana(L, rng, u0, v0, u1, v1, base, caras, nombre, pmin=3, pmax=6, podio=0.0, sin_puerta=()):
    """Parte el solar en casas entre medianeras a lo largo de su lado largo. Las alturas van por paseo
    aleatorio de +-1 planta: asi no hay dos vecinas iguales pero tampoco un salto de tres pisos que dejase
    una azotea sin manera de subir. Devuelve la lista de fichas."""
    if podio > 0.0:
        # basamento: unas cuantas casas del casco se levantan sobre un zocalo y se entra por su perron
        L.caja(u0 - 0.5, -0.1, v0 - 0.5, u1 + 0.5, base + podio, v1 + 0.5, "caliza_sombra")
        L.caja(u0 - 0.5, base + podio - 0.14, v0 - 0.5, u1 + 0.5, base + podio, v1 + 0.5, "caliza")
        base = base + podio

    largo_u = (u1 - u0) >= (v1 - v0)
    total = (u1 - u0) if largo_u else (v1 - v0)
    cortes, p = [0.0], 0.0
    while total - p > 8.4:
        p += _R(rng, 5.0, 8.0)
        cortes.append(p)
    cortes.append(total)
    if len(cortes) > 2 and cortes[-1] - cortes[-2] < 4.2:
        cortes.pop(-2)

    plantas = pmin + rng.randrange(max(1, pmax - pmin + 1))
    casas = []
    for i in range(len(cortes) - 1):
        a, b = cortes[i], cortes[i + 1]
        if largo_u:
            cu0, cv0, cu1, cv1 = u0 + a, v0, u0 + b, v1
        else:
            cu0, cv0, cu1, cv1 = u0, v0 + a, u1, v0 + b
        mis = []
        for c in caras:
            if largo_u and c in ("-u", "+u"):
                if (c == "-u" and i == 0) or (c == "+u" and i == len(cortes) - 2):
                    mis.append(c)
            elif (not largo_u) and c in ("-v", "+v"):
                if (c == "-v" and i == 0) or (c == "+v" and i == len(cortes) - 2):
                    mis.append(c)
            else:
                mis.append(c)
        if not mis:
            mis = [caras[0]] if caras else ["-v"]
        mat = REVOCOS[rng.randrange(len(REVOCOS))]
        if casas and mat == casas[-1]["mat"]:
            mat = REVOCOS[(REVOCOS.index(mat) + 3) % len(REVOCOS)]
        # la primera casa de cada manzana lleva SIEMPRE interior y escalera hasta la azotea: es la garantia
        # de que ese tejado se alcanza a pie desde la calle
        # el portal nunca cae en una fachada que da al vacio del bancal: ahi solo van ventanas y balcones
        buenas = [c for c in mis if c not in sin_puerta] or mis
        # una de cada siete se rehizo con pizarra en vez de teja: rompe la mancha naranja del barrio
        teja = "pizarra" if rng.random() < 0.14 else TEJAS[rng.randrange(len(TEJAS))]
        ficha = _casa(L, rng, cu0, cv0, cu1, cv1, base, plantas, mat, teja,
                      mis, buenas[rng.randrange(len(buenas))],
                      interior=(i == 0 or rng.random() < 0.75),
                      tocada=(0.7 if rng.random() < 0.2 else 0.0))
        ficha["manzana"] = nombre
        casas.append(ficha)
        plantas = max(pmin, min(pmax, plantas + (1 if rng.random() < 0.5 else -1)))

    for a, b in zip(casas, casas[1:]):
        if abs(a["cima"] - b["cima"]) > 1.2:
            baja, alta = (a, b) if a["cima"] < b["cima"] else (b, a)
            _escalerilla_medianera(L, rng, baja, alta)
    return casas


# =========================================================================================================
# EL PLANO DEL BARRIO
# Tres bancales cosidos por escaleras. Todo en coordenadas locales: u al este (0..56), v al sur (0..70,4).
#
#   v 0..4      ronda perimetral a cota 0 (enlaza con la ronda norte del mapa) + arranque de escalinatas
#   v 4..8      calle del pie de la muralla alta, a cota 2
#   v 8..33,6   BANCAL ALTO a cota 4 (manzanas A, calle Alta, plazoleta de la Fuente)
#   v 33,6..36  callejon de la muralla, a cota 2, al pie del muro de contencion del bancal alto
#   v 36..39,2  calle del Mar
#   v 39,2..52  manzanas C
#   v 52..55,2  calle de la Cuesta
#   v 55,2..64  manzanas D y plazoleta del Lavadero
#   v 64..66,4  callejon del sur
#   v 66,4..70,4 ronda perimetral a cota 0
#
# En u: ronda 0..4 | manzanas B oeste 4..9,6 | calle Poniente 9,6..12,8 | nucleo 12,8..44,8 |
#       calle Levante 44,8..48 | manzanas B este 48..52 | ronda 52..56
# =========================================================================================================

P1 = (4.0, 4.0, 52.0, 66.4)          # bancal medio, cota 2
P2 = (12.8, 8.0, 44.8, 33.6)         # bancal alto, cota 4

# (u0, v0, u1, v1, escalera, ancho, alto, hacia, faroles): las escalinatas que cosen el bancal alto con el
# medio. El hueco se vacia primero en la plataforma y la escalera se planta dentro.
_ESCALINATAS_ALTAS = [
    ((12.8, 20.0, 18.0, 23.4), (12.8, 20.0, 5.2, 3.4, "+x"), 2),     # calle Alta -> calle Poniente
    ((39.6, 20.0, 44.8, 23.4), (44.8, 20.0, 5.2, 3.4, "-x"), 2),     # calle Alta -> calle Levante
    ((20.8, 8.0, 24.0, 13.2), (20.8, 8.0, 5.2, 3.2, "+z"), 2),       # callejon del Campanario
    ((33.4, 8.0, 36.6, 13.2), (33.4, 8.0, 5.2, 3.2, "+z"), 1),       # callejon de la Sombra norte
    ((30.6, 28.4, 33.8, 33.6), (30.6, 33.6, 5.2, 3.2, "-z"), 1),     # callejon de la Sombra sur
    ((22.6, 29.4, 29.4, 33.6), (22.6, 33.6, 4.2, 6.8, "-z"), 2),     # ESCALINATA MAYOR de la plazoleta
]

# manzanas: (nombre, u0, v0, u1, v1, bancal, caras, min plantas, max plantas, podio, caras sin portal)
_MANZANAS = [
    ("A1", 12.8, 8.0, 20.8, 20.0, Y_ALTA, ("-v", "+v", "-u"), 4, 6, 0.0, ("-u", "-v")),
    ("A2", 24.0, 8.0, 33.4, 20.0, Y_ALTA, ("-v", "+v", "-u", "+u"), 3, 6, 0.0, ("-v",)),
    ("A3", 36.6, 8.0, 44.8, 20.0, Y_ALTA, ("-v", "+v", "-u", "+u"), 4, 6, 0.0, ("-v", "+u")),
    ("A4", 12.8, 23.4, 21.4, 33.6, Y_ALTA, ("-v", "+v", "-u", "+u"), 3, 5, 0.75, ("-u", "+v")),
    ("A5", 33.8, 23.4, 44.8, 33.6, Y_ALTA, ("-v", "+v", "-u", "+u"), 4, 6, 0.0, ("+u", "+v")),
    ("B1", 4.0, 5.0, 9.6, 18.0, Y_MEDIA, ("-u", "+u", "-v", "+v"), 3, 5, 0.0, ("-u",)),
    ("B2", 4.0, 20.4, 9.6, 33.6, Y_MEDIA, ("-u", "+u", "-v", "+v"), 3, 5, 0.0, ("-u",)),
    ("B3", 48.0, 5.0, 52.0, 19.0, Y_MEDIA, ("-u", "+u", "-v", "+v"), 3, 4, 0.0, ("+u",)),
    ("B4", 48.0, 21.4, 52.0, 33.6, Y_MEDIA, ("-u", "+u", "-v", "+v"), 3, 5, 0.0, ("+u",)),
    ("C0", 4.0, 39.2, 9.6, 52.0, Y_MEDIA, ("-u", "+u", "-v", "+v"), 3, 5, 0.0, ("-u",)),
    ("C1", 12.8, 39.2, 26.0, 44.8, Y_MEDIA, ("-v", "+v", "-u", "+u"), 4, 6, 0.75, ()),
    ("C2", 12.8, 47.0, 26.0, 52.0, Y_MEDIA, ("-v", "+v", "-u", "+u"), 3, 5, 0.0, ()),
    ("C3", 29.2, 39.2, 36.0, 52.0, Y_MEDIA, ("-u", "+u", "-v", "+v"), 4, 6, 0.0, ()),
    ("C4", 38.4, 39.2, 44.8, 52.0, Y_MEDIA, ("-u", "+u", "-v", "+v"), 3, 6, 0.0, ()),
    ("C5", 48.0, 39.2, 52.0, 52.0, Y_MEDIA, ("-u", "+u", "-v", "+v"), 3, 4, 0.0, ("+u",)),
    ("D0", 4.0, 55.2, 16.0, 64.0, Y_MEDIA, ("-v", "+v", "-u", "+u"), 3, 5, 0.0, ("-u",)),
    ("D2", 18.4, 55.2, 30.0, 64.0, Y_MEDIA, ("-v", "+v", "-u", "+u"), 4, 6, 0.0, ()),
    ("D3", 32.4, 55.2, 43.0, 64.0, Y_MEDIA, ("-v", "+v", "-u", "+u"), 3, 6, 0.75, ()),
]

PLAZOLETA = (21.4, 23.4, 30.6, 29.4)          # de la Fuente, en el bancal alto
LAVADERO = (43.0, 55.2, 52.0, 64.0)           # del Lavadero, en el bancal medio


def _plataforma(L, rect, alto, borde="caliza_sombra", suelo="adoquin"):
    """Bancal de piedra: la cascara de sillar es lo que se ve desde abajo (el muro de contencion), el
    relleno de roca lo que sostiene, y la capa de arriba el pavimento por el que se anda."""
    u0, v0, u1, v1 = rect
    L.caja(u0, -0.8, v0, u1, alto, v1, borde)
    L.caja(u0 + 0.6, -0.8, v0 + 0.6, u1 - 0.6, alto, v1 - 0.6, "roca")
    L.caja(u0, alto - 0.22, v0, u1, alto, v1, suelo)
    # albardilla: el remate del muro, que es lo que canta el borde del bancal a distancia
    for (a0, b0, a1, b1) in ((u0, v0, u1, v0 + 0.45), (u0, v1 - 0.45, u1, v1),
                             (u0, v0, u0 + 0.45, v1), (u1 - 0.45, v0, u1, v1)):
        L.caja(a0, alto - 0.34, b0, a1, alto - 0.22, b1, "caliza_clara")


def _pavimento(L, rng, u0, v0, u1, v1, y, mat="adoquin_claro", junta=None):
    """repinta el suelo sin cambiar la cota: sustituye los 12 cm de arriba del pavimento del bancal"""
    L.caja(u0, y - 0.12, v0, u1, y, v1, mat)
    if junta:
        # reguera central: en el casco viejo el agua baja por el eje del callejon, no por los lados
        if u1 - u0 >= v1 - v0:
            c = (v0 + v1) * 0.5
            L.caja(u0, y - 0.14, c - 0.12, u1, y - 0.02, c + 0.12, junta)
        else:
            c = (u0 + u1) * 0.5
            L.caja(c - 0.12, y - 0.14, v0, c + 0.12, y - 0.02, v1, junta)


def _terreno(L, rng):
    # la roca de debajo y la ronda perimetral a cota 0, que es la que empalma con las rondas del mapa
    L.caja(0.0, -1.2, 0.0, W, 0.0, D, "roca")
    L.caja(0.0, -0.22, 0.0, W, 0.0, D, "adoquin")
    _plataforma(L, P1, Y_MEDIA)
    _plataforma(L, P2, Y_ALTA)

    # --- pavimentos: cada calle con su textura, que es lo que hace que el plano se lea desde el tejado ---
    _pavimento(L, rng, 9.6, 4.0, 12.8, 66.4, Y_MEDIA, "adoquin_claro", "granito")      # calle Poniente
    _pavimento(L, rng, 44.8, 4.0, 48.0, 66.4, Y_MEDIA, "adoquin_claro", "granito")     # calle Levante
    _pavimento(L, rng, 4.0, 33.6, 52.0, 36.0, Y_MEDIA, "adoquin", "granito")           # callejon de la muralla
    _pavimento(L, rng, 4.0, 36.0, 52.0, 39.2, Y_MEDIA, "adoquin_claro", "granito")     # calle del Mar
    _pavimento(L, rng, 4.0, 52.0, 52.0, 55.2, Y_MEDIA, "adoquin_claro", "granito")     # calle de la Cuesta
    _pavimento(L, rng, 4.0, 64.0, 52.0, 66.4, Y_MEDIA, "adoquin", "granito")           # callejon del sur
    _pavimento(L, rng, 26.0, 36.0, 29.2, 55.2, Y_MEDIA, "adoquin", "granito")          # calle Media
    _pavimento(L, rng, 4.0, 18.0, 9.6, 20.4, Y_MEDIA, "adoquin", "granito")
    _pavimento(L, rng, 48.0, 19.0, 52.0, 21.4, Y_MEDIA, "adoquin", "granito")
    _pavimento(L, rng, 12.8, 44.8, 26.0, 47.0, Y_MEDIA, "adoquin", "granito")
    _pavimento(L, rng, 36.0, 39.2, 38.4, 52.0, Y_MEDIA, "adoquin", "granito")
    _pavimento(L, rng, 16.0, 55.2, 18.4, 64.0, Y_MEDIA, "adoquin", "granito")
    _pavimento(L, rng, 30.0, 55.2, 32.4, 64.0, Y_MEDIA, "adoquin", "granito")
    _pavimento(L, rng, 4.0, 4.0, 52.0, 8.0, Y_MEDIA, "adoquin_claro", "granito")       # pie de la muralla
    _pavimento(L, rng, 12.8, 20.0, 44.8, 23.4, Y_ALTA, "adoquin_claro", "granito")     # calle Alta
    _pavimento(L, rng, 20.8, 8.0, 24.0, 20.0, Y_ALTA, "adoquin", "granito")            # callejon Campanario
    _pavimento(L, rng, 33.4, 8.0, 36.6, 20.0, Y_ALTA, "adoquin", "granito")
    _pavimento(L, rng, 30.6, 23.4, 33.8, 33.6, Y_ALTA, "adoquin", "granito")
    _pavimento(L, rng, 21.4, 23.4, 30.6, 29.4, Y_ALTA, "caliza")                       # plazoleta
    _pavimento(L, rng, 43.0, 55.2, 52.0, 64.0, Y_MEDIA, "caliza")                      # lavadero
    # aceras: una banda a ras (no un bordillo) contra la fachada en las calles anchas. Sube el contraste del
    # plano visto desde los tejados sin meter ni un escalon en el camino de las criaturas.
    for (a0, b0, a1, b1, y) in ((9.6, 4.0, 10.2, 66.4, Y_MEDIA), (12.2, 4.0, 12.8, 66.4, Y_MEDIA),
                                (44.8, 4.0, 45.4, 66.4, Y_MEDIA), (47.4, 4.0, 48.0, 66.4, Y_MEDIA),
                                (4.0, 36.0, 52.0, 36.6, Y_MEDIA), (4.0, 38.6, 52.0, 39.2, Y_MEDIA),
                                (4.0, 52.0, 52.0, 52.6, Y_MEDIA), (4.0, 54.6, 52.0, 55.2, Y_MEDIA),
                                (12.8, 20.0, 44.8, 20.6, Y_ALTA), (12.8, 22.8, 44.8, 23.4, Y_ALTA)):
        L.caja(a0, y - 0.12, b0, a1, y, b1, "acera")
    for _ in range(70):                                                                # remiendos y parcheos
        u, v = _R(rng, 5.0, 51.0), _R(rng, 5.0, 65.0)
        L.caja(u, Y_MEDIA - 0.13, v, u + _R(rng, 0.3, 1.3), Y_MEDIA, v + _R(rng, 0.3, 1.0), "grava")

    # --- ESCALINATAS DE LA RONDA: cosen la cota 0 del perimetro con el bancal medio ---------------------
    for u in (14.0, 30.0, 40.4):
        _escalinata(L, rng, u, 0.4, 0.0, 3.6, 3.4, Y_MEDIA, "+z", faroles=1)
    for u in (12.0, 26.0, 40.4):
        _escalinata(L, rng, u, 70.0, 0.0, 3.6, 3.4, Y_MEDIA, "-z", faroles=1)
    for v in (14.0, 30.0, 46.0, 58.0):
        _escalinata(L, rng, 0.4, v, 0.0, 3.6, 3.4, Y_MEDIA, "+x", faroles=1)
    for v in (16.0, 32.0, 44.0, 60.0):
        _escalinata(L, rng, 55.6, v, 0.0, 3.6, 3.4, Y_MEDIA, "-x", faroles=1)

    # --- ESCALINATAS DEL BANCAL ALTO -------------------------------------------------------------------
    for (hueco, esc, faroles) in _ESCALINATAS_ALTAS:
        hu0, hv0, hu1, hv1 = hueco
        L.caja(hu0, Y_MEDIA, hv0, hu1, Y_ALTA + 0.6, hv1, "caliza", hueco=True)     # el rebaje del bancal
        _pavimento(L, rng, hu0, hv0, hu1, hv1, Y_MEDIA, "adoquin_claro")
        eu, ev, largo, ancho, hacia = esc
        _escalinata(L, rng, eu, ev, Y_MEDIA, largo, ancho, Y_ALTA - Y_MEDIA, hacia, faroles=faroles)

    # la escalinata mayor se remata con dos plintos y sus tiestos: es la foto del barrio
    for u in (22.0, 29.8):
        L.caja(u - 0.5, Y_ALTA, 33.0, u + 0.5, Y_ALTA + 1.1, 34.0, "caliza")
        L.caja(u - 0.6, Y_ALTA + 1.1, 32.9, u + 0.6, Y_ALTA + 1.25, 34.1, "caliza_clara")
        _maceta(L, u, Y_ALTA + 1.25, 33.5, rng, 0.36)


def _plazoletas(L, rng, casas):
    """Las dos plazoletas: la de la Fuente arriba, junto a la escalinata mayor, y la del Lavadero abajo,
    que es donde vive la escalera exterior que sube a la azotea de la manzana D3."""
    pu0, pv0, pu1, pv1 = PLAZOLETA
    cu, cv = (pu0 + pu1) * 0.5, (pv0 + pv1) * 0.5
    _fuente(L, rng, cu, cv, Y_ALTA, 1.7)
    L.luz(cu, Y_ALTA + 2.8, cv, DORADA, 0.7, 10.0)
    for (u, v, eje) in ((pu0 + 1.4, pv1 - 1.0, "u"), (pu1 - 1.4, pv1 - 1.0, "u"), (pu0 + 0.9, pv0 + 2.2, "v")):
        _banco(L, u, v, Y_ALTA, eje)
    _arbol(L, rng, pu0 + 1.5, pv0 + 1.3, Y_ALTA, 5.6, "palmera")
    _arbol(L, rng, pu1 - 1.4, pv0 + 1.4, Y_ALTA, 4.4, "cipres")
    _papelera(L, pu1 - 0.8, pv1 - 2.4, Y_ALTA)
    _farola(L, rng, pu0 + 0.7, cv, Y_ALTA, "+u", 4.2)
    _farola(L, rng, pu1 - 0.7, cv - 1.6, Y_ALTA, "-u", 4.2)
    # puesto de mercado arrimado a la fachada: tablero, toldo y cajas
    L.caja(pu0 + 2.6, Y_ALTA + 0.75, pv0 + 0.4, pu0 + 5.4, Y_ALTA + 0.85, pv0 + 1.6, "madera")
    for u in (pu0 + 2.8, pu0 + 5.1):
        L.caja(u, Y_ALTA, pv0 + 0.5, u + 0.15, Y_ALTA + 0.75, pv0 + 1.5, "madera")
        L.cilindro(u + 0.07, Y_ALTA, pv0 + 1.4, 0.07, 2.3, "metal")
    L.cuna(pu0 + 2.5, Y_ALTA + 2.1, pv0 + 0.3, pu0 + 5.5, Y_ALTA + 2.45, pv0 + 2.1, "-z", "toldo_rojo")
    for _ in range(5):
        u, v = _R(rng, pu0 + 2.6, pu0 + 5.2), _R(rng, pv0 + 1.8, pv0 + 2.6)
        L.caja(u, Y_ALTA, v, u + 0.5, Y_ALTA + 0.35, v + 0.4, "madera_clara")

    lu0, lv0, lu1, lv1 = LAVADERO
    # LA ESCALERA EXTERIOR DEL BARRIO: arrimada a la medianera ciega de la manzana D3, sube de la plazoleta
    # hasta su azotea dando la vuelta en cada planta. Es la otra manera de llegar arriba sin entrar en
    # ningun portal, y de paso la escalera se ve entera desde la calle de la Cuesta.
    d3 = [f for f in casas if f["manzana"] == "D3"]
    if d3:
        f = max(d3, key=lambda c: c["u1"])
        eu, ev = f["u1"] - 0.2, lv0 + 1.2               # el rellano de arriba muerde 0,2 m en la azotea
        L.caja(eu, Y_MEDIA - 0.2, ev, eu + ESC_EXT[0], f["base"], ev + ESC_EXT[1], "caliza_sombra")
        L.caja(eu, f["base"] - 0.12, ev, eu + ESC_EXT[0], f["base"], ev + ESC_EXT[1], "caliza")
        _peldanos(L, eu + 1.4, ev + ESC_EXT[1] + 1.5, Y_MEDIA, 1.5, 3.2, f["base"] - Y_MEDIA, "-z", "caliza")
        _escalera_exterior(L, rng, eu, ev, f["base"], f["plantas"])
        # y se abre el pretil de la azotea justo donde llega, que si no la escalera muere contra un parapeto
        L.caja(f["u1"] - 0.9, f["cima"], ev + 0.1, f["u1"] + 0.3, f["cima"] + 1.2, ev + ESC_EXT[1] - 0.1,
               "hormigon", hueco=True)
    # lavadero publico: pila corrida de caliza bajo un tejadillo de teja sobre pilares. La cubierta es plana
    # y esta a 3,2: un paso de azotea mas, al alcance del pretil de la casa de al lado.
    bu0, bv0, bu1 = lu0 + 1.6, lv0 + 5.4, lu1 - 1.0
    L.caja(bu0, Y_MEDIA, bv0 + 0.6, bu1, Y_MEDIA + 0.85, bv0 + 2.2, "caliza")
    L.caja(bu0 + 0.25, Y_MEDIA + 0.3, bv0 + 0.85, bu1 - 0.25, Y_MEDIA + 0.9, bv0 + 1.95, "caliza", hueco=True)
    L.caja(bu0 + 0.3, Y_MEDIA + 0.3, bv0 + 0.9, bu1 - 0.3, Y_MEDIA + 0.55, bv0 + 1.9, "agua_mar")
    for u in (bu0 - 0.4, (bu0 + bu1) * 0.5, bu1 + 0.4):
        L.caja(u - 0.16, Y_MEDIA, bv0, u + 0.16, Y_MEDIA + 3.0, bv0 + 0.32, "caliza")
        L.caja(u - 0.16, Y_MEDIA, bv0 + 2.5, u + 0.16, Y_MEDIA + 3.0, bv0 + 2.82, "caliza")
    L.caja(bu0 - 0.7, Y_MEDIA + 3.0, bv0 - 0.3, bu1 + 0.7, Y_MEDIA + 3.2, bv0 + 3.1, "teja_vieja")
    L.caja(bu0 - 0.8, Y_MEDIA + 3.2, bv0 - 0.4, bu1 + 0.8, Y_MEDIA + 3.32, bv0 + 3.2, "caliza_clara")
    _peldanos(L, lu1 - 1.6, bv0 + 3.6, Y_MEDIA, 4.2, 1.4, 3.2, "-z")     # al tejadillo, y de ahi al barrio
    _arbol(L, rng, lu0 + 1.4, lv1 - 1.3, Y_MEDIA, 5.0, "cipres")
    _arbol(L, rng, lu1 - 1.5, lv0 + 4.8, Y_MEDIA, 4.6, "cipres")
    _banco(L, lu0 + 4.6, lv1 - 1.2, Y_MEDIA, "u", 2.2)
    _papelera(L, lu0 + 6.4, lv1 - 1.1, Y_MEDIA)
    _farola(L, rng, lu1 - 0.8, lv0 + 1.2, Y_MEDIA, "-u", 4.0, luz=True)
    L.punto(lu0 + 5.0, Y_MEDIA + 0.1, lv1 - 2.0)


# =========================================================================================================
# LO QUE COSE EL BARRIO POR ARRIBA: pasarelas de tablones y arcos de descarga sobre los callejones
# =========================================================================================================

def _pasarela(L, rng, a, b, eje):
    """Tablon de obra cruzando el callejon de azotea a azotea. Se abre el pretil de las dos casas para que
    se pueda pasar de verdad: un puente contra un parapeto de 0,7 no sirve de nada."""
    y = min(a["cima"], b["cima"])
    if eje == "u":
        vc = (max(a["v0"], b["v0"]) + min(a["v1"], b["v1"])) * 0.5
        x0, x1 = a["u1"] - 0.5, b["u0"] + 0.5
        L.caja(x0 - 0.35, y, vc - 1.0, x1 + 0.35, y + 0.95, vc + 1.0, "hormigon", hueco=True)
        for k in range(4):
            z = vc - 0.72 + k * 0.42
            L.caja(x0, y - 0.18, z, x1, y, z + 0.34, "madera" if k % 2 else "madera_clara")
        L.caja(x0, y - 0.22, vc - 0.85, x1, y - 0.1, vc + 0.85, "metal")           # perfiles de apoyo
        for s in (-0.9, 0.9):
            L.caja(x0, y, vc + s - 0.04, x1, y + 0.9, vc + s + 0.04, "hierro")
            L.caja(x0, y + 0.5, vc + s - 0.05, x1, y + 0.58, vc + s + 0.05, "hierro")
    else:
        uc = (max(a["u0"], b["u0"]) + min(a["u1"], b["u1"])) * 0.5
        z0, z1 = a["v1"] - 0.5, b["v0"] + 0.5
        L.caja(uc - 1.0, y, z0 - 0.35, uc + 1.0, y + 0.95, z1 + 0.35, "hormigon", hueco=True)
        for k in range(4):
            x = uc - 0.72 + k * 0.42
            L.caja(x, y - 0.18, z0, x + 0.34, y, z1, "madera" if k % 2 else "madera_clara")
        L.caja(uc - 0.85, y - 0.22, z0, uc + 0.85, y - 0.1, z1, "metal")
        for s in (-0.9, 0.9):
            L.caja(uc + s - 0.04, y, z0, uc + s + 0.04, y + 0.9, z1, "hierro")
            L.caja(uc + s - 0.05, y + 0.5, z0, uc + s + 0.05, y + 0.58, z1, "hierro")


def _pasarelas(L, rng, casas, maximo=11):
    """Busca parejas de casas de manzanas distintas separadas por un callejon y a la misma altura de
    azotea, y las enlaza. No hace falta para subir (para eso estan las escaleras), pero es lo que convierte
    los tejados en un mapa entero en vez de en islas."""
    puestas, ocupadas = 0, set()
    for i, a in enumerate(casas):
        if puestas >= maximo:
            break
        for b in casas[i + 1:]:
            if puestas >= maximo:
                break
            if a["manzana"] == b["manzana"] or abs(a["cima"] - b["cima"]) > 0.7:
                continue
            if (a["manzana"], b["manzana"]) in ocupadas:
                continue
            sol = min(a["v1"], b["v1"]) - max(a["v0"], b["v0"])
            hueco = b["u0"] - a["u1"]
            if 1.6 <= hueco <= 3.4 and sol >= 2.6:
                _pasarela(L, rng, a, b, "u")
            else:
                sol = min(a["u1"], b["u1"]) - max(a["u0"], b["u0"])
                hueco = b["v0"] - a["v1"]
                if not (1.6 <= hueco <= 3.4 and sol >= 2.6):
                    continue
                _pasarela(L, rng, a, b, "v")
            ocupadas.add((a["manzana"], b["manzana"]))
            puestas += 1
    return puestas


def _arco(L, rng, u0, v0, u1, v1, y, alto=3.3):
    """Arco de descarga sobre un callejon: dos casas que se apuntalan la una en la otra por encima de la
    calle. Deja 2,7 m libres en el eje, de sobra para pasar, y de paso tapa el callejon desde el aire."""
    L.caja(u0, y, v0, u1, y + alto, v1, "caliza_sombra")
    if (u1 - u0) >= (v1 - v0):
        r = (u1 - u0) * 0.5
        L.caja(u0, y, v0 - 0.1, u1, y + 1.25, v1 + 0.1, "caliza", hueco=True)
        L.cilindro((u0 + u1) * 0.5, y + 1.25, v0 - 0.1, r, (v1 - v0) + 0.2, "caliza", hueco=True, eje="z")
        for v in (v0 - 0.06, v1 - 0.06):        # dovelas resaltadas: el arco se lee desde la calle
            L.caja(u0 - 0.12, y + 1.15, v, u1 + 0.12, y + 1.4, v + 0.12, "caliza_clara")
    else:
        r = (v1 - v0) * 0.5
        L.caja(u0 - 0.1, y, v0, u1 + 0.1, y + 1.25, v1, "caliza", hueco=True)
        L.cilindro(u0 - 0.1, y + 1.25, (v0 + v1) * 0.5, r, (u1 - u0) + 0.2, "caliza", hueco=True, eje="x")
        for u in (u0 - 0.06, u1 - 0.06):
            L.caja(u, y + 1.15, v0 - 0.12, u + 0.12, y + 1.4, v1 + 0.12, "caliza_clara")
    L.caja(u0 - 0.14, y + alto, v0 - 0.14, u1 + 0.14, y + alto + 0.16, v1 + 0.14, "caliza_clara")


# =========================================================================================================
# DANO DE COMBATE
# =========================================================================================================

def _ruina_partida(L, rng, f):
    """LA CASA PARTIDA: el proyectil se llevo media cruja de la segunda planta para arriba. Los forjados
    que quedan NO flotan: nacen del muro que sigue en pie y vuelan hacia la calle como una bandeja rota,
    con la ferralla asomando. Lo que se cayo esta abajo, en el callejon, hecho un monton de cascote."""
    u0, v0, u1, v1 = f["u0"], f["v0"], f["u1"], f["v1"]
    base, cima, plantas = f["base"], f["cima"], f["plantas"]
    mat = f["mat"]
    largo_u = (u1 - u0) >= (v1 - v0)
    y_corte = base + PLANTA * min(2, max(1, plantas - 2))
    if largo_u:
        c = u0 + (u1 - u0) * _R(rng, 0.4, 0.6)
        L.caja(c, y_corte, v0 - 0.5, u1 + 0.5, cima + 1.4, v1 + 0.5, mat, hueco=True)
        for _ in range(9):      # el filo del corte, mordido
            L.elipsoide(c + _R(rng, -1.1, 0.6), _R(rng, y_corte, cima), _R(rng, v0, v1),
                        _R(rng, 0.4, 1.0), _R(rng, 0.4, 0.9), _R(rng, 0.5, 1.4), mat, hueco=True)
        m = 1
        y = y_corte + PLANTA
        while y < cima + 0.1:
            vuelo = _R(rng, 0.9, 2.4)
            L.caja(c - 0.2, y - FORJADO, v0 + MURO, c + vuelo, y, v1 - MURO, "hormigon_visto")
            # la losa se vence hacia fuera: el borde cae medio metro y arrastra la ferralla
            L.cuna(c + vuelo - 0.1, y - 0.75, v0 + MURO, c + vuelo + 1.2, y, v1 - MURO, "-x", "hormigon_visto")
            for k in range(4):
                vv = v0 + MURO + (v1 - v0 - 2 * MURO) * (k + 0.5) / 4.0
                L.linea(c + vuelo, y - 0.2, vv, c + vuelo + _R(rng, 0.6, 1.4), y - _R(rng, 0.9, 1.9), vv,
                        0.13, "varilla")
            m += 1
            y += PLANTA
        _cascotes(L, rng, u1 + 1.6, (v0 + v1) * 0.5, base, 2.4, 26)
        _polvo(L, rng, u1 + 1.8, (v0 + v1) * 0.5, base, 3.0, 8)
    else:
        c = v0 + (v1 - v0) * _R(rng, 0.4, 0.6)
        L.caja(u0 - 0.5, y_corte, c, u1 + 0.5, cima + 1.4, v1 + 0.5, mat, hueco=True)
        for _ in range(9):
            L.elipsoide(_R(rng, u0, u1), _R(rng, y_corte, cima), c + _R(rng, -1.1, 0.6),
                        _R(rng, 0.5, 1.4), _R(rng, 0.4, 0.9), _R(rng, 0.4, 1.0), mat, hueco=True)
        y = y_corte + PLANTA
        while y < cima + 0.1:
            vuelo = _R(rng, 0.9, 2.4)
            L.caja(u0 + MURO, y - FORJADO, c - 0.2, u1 - MURO, y, c + vuelo, "hormigon_visto")
            L.cuna(u0 + MURO, y - 0.75, c + vuelo - 0.1, u1 - MURO, y, c + vuelo + 1.2, "-z", "hormigon_visto")
            for k in range(4):
                uu = u0 + MURO + (u1 - u0 - 2 * MURO) * (k + 0.5) / 4.0
                L.linea(uu, y - 0.2, c + vuelo, uu, y - _R(rng, 0.9, 1.9), c + vuelo + _R(rng, 0.6, 1.4),
                        0.13, "varilla")
            y += PLANTA
        _cascotes(L, rng, (u0 + u1) * 0.5, v1 + 1.6, base, 2.4, 26)
        _polvo(L, rng, (u0 + u1) * 0.5, v1 + 1.8, base, 3.0, 8)
    # la planta baja aguanta pero se queda en carne viva: vigas, escombro dentro y polvo
    L.caja(u0 + MURO, base, v0 + MURO, u1 - MURO, base + PLANTA - FORJADO, v1 - MURO, mat, hueco=True)
    _cascotes(L, rng, (u0 + u1) * 0.5, (v0 + v1) * 0.5, base, min(u1 - u0, v1 - v0) * 0.4, 16)


def _fachada_arrancada(L, rng, f):
    """A esta le falta la fachada de la ultima planta: se ve el piso por dentro desde la calle de enfrente,
    con el forjado intacto. Es el mejor sitio del barrio para poner un francotirador."""
    if not f["caras"]:
        return
    c = f["caras"][rng.randrange(len(f["caras"]))]
    F = _Cara(L, f["u0"], f["v0"], f["u1"], f["v1"], c)
    y = f["cima"] - PLANTA
    F.caja(0.4, y + 0.3, -0.5, F.largo - 0.4, f["cima"] - FORJADO, MURO + 0.3, "hormigon", hueco=True)
    for _ in range(6):
        F.eli(_R(rng, 0.3, F.largo - 0.3), _R(rng, y + 0.2, f["cima"] - 0.5), MURO * 0.5,
              _R(rng, 0.3, 0.8), _R(rng, 0.3, 0.7), MURO * 2.0, "hormigon", hueco=True)
    for k in range(3):        # ferralla y trozo de balcon colgando de la cornisa
        h = F.largo * (k + 0.5) / 3.0
        F.linea(h, y + 0.4, 0.05, h + _R(rng, -0.5, 0.5), y - _R(rng, 0.5, 1.6), -_R(rng, 0.3, 0.9),
                0.12, "varilla")
    F.caja(0.4, y, -0.7, 2.0, y + 0.3, 0.0, "hormigon_visto")
    if f["interior"]:
        return
    # si era maciza hay que vaciarle ese piso, si no se ve un agujero que da a roca
    L.caja(f["u0"] + MURO, y, f["v0"] + MURO, f["u1"] - MURO, f["cima"] - FORJADO, f["v1"] - MURO,
           f["mat"], hueco=True)


def _tejado_hundido(L, rng, f):
    """Azotea reventada: un socavon que se come el forjado y deja ver la ultima planta. Se cae dentro, que
    es media gracia de jugar por los tejados."""
    u = _R(rng, f["u0"] + 1.4, f["u1"] - 1.4)
    v = _R(rng, f["v0"] + 1.4, f["v1"] - 1.4)
    r = min(1.9, (min(f["u1"] - f["u0"], f["v1"] - f["v0"]) - 1.4) * 0.5)
    if r < 0.7:
        return
    L.elipsoide(u, f["cima"] - 0.1, v, r, 0.7, r * 0.85, f["mat"], hueco=True)
    L.elipsoide(u + _R(rng, -0.5, 0.5), f["cima"] - 0.1, v + _R(rng, -0.5, 0.5), r * 0.7, 0.7, r * 0.7,
                f["mat"], hueco=True)
    for k in range(4):
        a = k * math.tau / 4.0 + 0.4
        L.linea(u + math.cos(a) * r * 0.8, f["cima"] - 0.25, v + math.sin(a) * r * 0.8,
                u + math.cos(a) * r * 0.3, f["cima"] - 1.6, v + math.sin(a) * r * 0.3, 0.13, "varilla")
    if f["interior"]:
        _cascotes(L, rng, u, v, f["cima"] - PLANTA, r * 1.2, 12, ("escombro", "teja_vieja", "ladrillo"))
    _cascotes(L, rng, u + r + 0.4, v, f["cima"], 0.9, 6, ("teja_vieja", "escombro_claro"))


def _danos(L, rng, casas):
    """Reparte el destrozo: una casa partida por manzana grande no, que quedaria un solar; pero si la
    partida gorda al lado de la escalinata mayor, dos fachadas arrancadas y unos cuantos tejados abiertos."""
    conteo = {"partida": 0, "fachada": 0, "tejado": 0}
    candidatas = [f for f in casas if (f["u1"] - f["u0"]) > 4.5 and (f["v1"] - f["v0"]) > 4.5]
    rng.shuffle(candidatas)
    for f in candidatas:
        if conteo["partida"] < 2 and f["plantas"] >= 4 and rng.random() < 0.3:
            _ruina_partida(L, rng, f)
            conteo["partida"] += 1
        elif conteo["fachada"] < 4 and rng.random() < 0.25:
            _fachada_arrancada(L, rng, f)
            conteo["fachada"] += 1
        elif conteo["tejado"] < 9 and rng.random() < 0.3:
            _tejado_hundido(L, rng, f)
            conteo["tejado"] += 1

    # --- montones de cascote y crateres por las calles ---
    monton = ((11.2, 30.0, Y_MEDIA), (10.9, 51.0, Y_MEDIA), (27.6, 43.0, Y_MEDIA), (27.4, 26.4, Y_ALTA),
              (46.4, 26.0, Y_MEDIA), (17.2, 45.9, Y_MEDIA), (31.2, 60.0, Y_MEDIA), (22.4, 14.6, Y_ALTA),
              (46.4, 58.0, Y_MEDIA), (8.0, 37.6, Y_MEDIA), (37.2, 37.6, Y_MEDIA))
    for (u, v, y) in monton:
        _cascotes(L, rng, u, v, y, _R(rng, 1.1, 2.0), 16 + rng.randrange(12))
        _polvo(L, rng, u, v, y, 2.6, 7)
        if rng.random() < 0.5:
            # viga de hormigon caida de una cornisa, apoyada en el monton: cobertura a media altura
            a = rng.random() * math.tau
            L.linea(u, y + 0.1, v, u + math.cos(a) * 3.2, y + _R(rng, 0.8, 1.6), v + math.sin(a) * 3.2,
                    0.34, "hormigon_visto")
    for (u, v, y) in ((13.0, 41.0, Y_MEDIA), (39.0, 62.0, Y_MEDIA), (26.5, 17.5, Y_ALTA)):
        # crater poco profundo: 0,3 m como mucho, que no rompa el paso de las criaturas
        L.elipsoide(u, y + 0.16, v, 1.7, 0.46, 1.5, "adoquin", hueco=True)
        L.elipsoide(u, y - 0.06, v, 1.5, 0.08, 1.3, "polvo")
        _cascotes(L, rng, u, v, y - 0.2, 2.1, 14, ("escombro", "adoquin", "grava"))


# =========================================================================================================
# DETALLE DE CALLE
# =========================================================================================================

# (u0, v0, u1, v1, cota): las calles por las que se pasea, para sembrarlas de farolas, tiestos y ropa
_CALLES = [
    (9.6, 4.0, 12.8, 66.4, Y_MEDIA), (44.8, 4.0, 48.0, 66.4, Y_MEDIA),
    (4.0, 33.6, 52.0, 36.0, Y_MEDIA), (4.0, 36.0, 52.0, 39.2, Y_MEDIA),
    (4.0, 52.0, 52.0, 55.2, Y_MEDIA), (4.0, 64.0, 52.0, 66.4, Y_MEDIA),
    (26.0, 36.0, 29.2, 55.2, Y_MEDIA), (4.0, 4.0, 52.0, 8.0, Y_MEDIA),
    (12.8, 20.0, 44.8, 23.4, Y_ALTA), (20.8, 8.0, 24.0, 20.0, Y_ALTA),
    (33.4, 8.0, 36.6, 20.0, Y_ALTA), (30.6, 23.4, 33.8, 33.6, Y_ALTA),
    (16.0, 55.2, 18.4, 64.0, Y_MEDIA), (30.0, 55.2, 32.4, 64.0, Y_MEDIA),
    (12.8, 44.8, 26.0, 47.0, Y_MEDIA), (36.0, 39.2, 38.4, 52.0, Y_MEDIA),
    (4.0, 18.0, 9.6, 20.4, Y_MEDIA), (48.0, 19.0, 52.0, 21.4, Y_MEDIA),
]


def _amarre(casas, a0, a1, c, eje, limite=7.0, dentro=0.7):
    """Donde amarrar los dos cabos de una cuerda que cruza la calle, y hasta que altura llega el muro.

    UNA CUERDA QUE ACABA EN EL BORDILLO NO TOCA NADA. Las calles de `_CALLES` son el hueco por el que
    se pasea, no la linea de fachada: las casas se retiran de ahi lo suyo, asi que la cuerda se quedaba
    colgada del aire y el motor la dejaba caer entera, con toda la ropa, en cuanto alguien disparaba en
    la manzana. Se busca la casa que da a la calle por cada lado y se mete el cabo `dentro` metros en su
    muro; esa mordida tiene que pasar de 0,25 m o no sobrevive al mapa `_lo` de 20 cm, que es el que va
    al APK y el que se usa en LAN. Lo que se mete no se ve: esta dentro de la fachada.

    Devuelve (cabo0, cabo1, techo), donde `techo` es la cima mas baja de las dos casas: POR ENCIMA DE
    AHI NO HAY MURO al que agarrarse, asi que quien llame tiene que colgar la cuerda por debajo. Si
    falta casa en alguno de los dos lados devuelve None y entonces no se tiende nada: mejor un callejon
    pelado que una cuerda flotando.
    `eje` es por donde corre la cuerda ("u" o "v") y `c` es la otra coordenada.
    """
    ka0, ka1 = ("u0", "u1") if eje == "u" else ("v0", "v1")
    kc0, kc1 = ("v0", "v1") if eje == "u" else ("u0", "u1")
    vecinas = [f for f in casas if f[kc0] - 0.5 <= c <= f[kc1] + 0.5]
    atras = [f for f in vecinas if a0 - limite <= f[ka1] <= a0 + 0.8]
    delante = [f for f in vecinas if a1 - 0.8 <= f[ka0] <= a1 + limite]
    if not atras or not delante:
        return None
    fa = max(atras, key=lambda f: f[ka1])
    fd = min(delante, key=lambda f: f[ka0])
    return fa[ka1] - dentro, fd[ka0] + dentro, min(fa["cima"], fd["cima"])


def _calle(L, rng, casas):
    """Farolas, tiestos, papeleras, ropa tendida y cables cruzando de balcon a balcon. Es lo que separa un
    barrio de un poligono: la calle tiene que estar llena de cosas a la altura de la cara."""
    faroles = 0
    for (u0, v0, u1, v1, y) in _CALLES:
        largo_u = (u1 - u0) >= (v1 - v0)
        largo = (u1 - u0) if largo_u else (v1 - v0)
        n = max(1, int(largo / 9.5))
        for i in range(n):
            t = (i + 0.5) / n
            lado = (i % 2 == 0)
            if largo_u:
                u = u0 + largo * t
                v = (v0 + 0.45) if lado else (v1 - 0.45)
                cara = "+v" if lado else "-v"
            else:
                v = v0 + largo * t
                u = (u0 + 0.45) if lado else (u1 - 0.45)
                cara = "+u" if lado else "-u"
            # una de cada tres lleva OmniLight; el resto alumbra con el vidrio emisivo del farol
            _farola(L, rng, u, v, y, cara, _R(rng, 3.4, 4.4), rota=(rng.random() < 0.18),
                    luz=(faroles % 3 == 0))
            faroles += 1
        # tiestos, papeleras y bancos arrimados al bordillo, nunca en medio del paso
        for _ in range(max(1, int(largo / 7.0))):
            t = rng.random()
            lado = rng.random() < 0.5
            # bien arrimado al bordillo: en un callejon de 3,2 m un tiesto en medio deja el paso por debajo
            # del metro y medio que necesita el A* de las criaturas
            if largo_u:
                u = u0 + largo * t
                v = (v0 + 0.32) if lado else (v1 - 0.32)
            else:
                v = v0 + largo * t
                u = (u0 + 0.32) if lado else (u1 - 0.32)
            r = rng.random()
            if r < 0.55:
                _maceta(L, u, v, y, rng, _R(rng, 0.2, 0.28))
            elif r < 0.75:
                _papelera(L, u, v, y)
            else:
                _banco(L, u, v, y, "u" if largo_u else "v", 1.6)
        # ropa tendida y cables de fachada a fachada: dos o tres por calle, a alturas distintas
        for _ in range(1 + rng.randrange(2)):
            t = _R(rng, 0.15, 0.85)
            h = y + _R(rng, 5.5, 9.5)
            if largo_u:
                a = u0 + largo * t
                am = _amarre(casas, v0, v1, a, "v")
                sesgo = _R(rng, -1.0, 1.0)
                if am and min(h, am[2] - 0.8) > y + 3.0:
                    _tendal(L, rng, a, am[0], a + sesgo, am[1], min(h, am[2] - 0.8), 0.0)
            else:
                b = v0 + largo * t
                am = _amarre(casas, u0, u1, b, "u")
                sesgo = _R(rng, -1.0, 1.0)
                if am and min(h, am[2] - 0.8) > y + 3.0:
                    _tendal(L, rng, am[0], b, am[1], b + sesgo, min(h, am[2] - 0.8), 0.0)
        # los cables van de fachada a fachada y se meten 0,8 m dentro de cada muro (mismo motivo que
        # en `_tendal`: si acaban en el borde de la calle no tocan nada y se quedan colgando del aire)
        for _ in range(2):
            t = _R(rng, 0.1, 0.9)
            h = y + _R(rng, 4.2, 7.5)
            if largo_u:
                a = u0 + largo * t
                am = _amarre(casas, v0, v1, a, "v")
                sesgo = _R(rng, -0.8, 0.8)
                if am and min(h, am[2] - 0.8) > y + 3.0:
                    hh = min(h, am[2] - 0.8)
                    L.linea(a, hh, am[0], a + sesgo, hh - 0.3, am[1], 0.09, "hierro", hueco=False)
            else:
                b = v0 + largo * t
                am = _amarre(casas, u0, u1, b, "u")
                sesgo = _R(rng, -0.8, 0.8)
                if am and min(h, am[2] - 0.8) > y + 3.0:
                    hh = min(h, am[2] - 0.8)
                    L.linea(am[0], hh, b, am[1], hh - 0.3, b + sesgo, 0.09, "hierro", hueco=False)
    return faroles


def _puntos(L, rng, casas):
    """Sitios por donde asoman las criaturas: plazoletas, bocas de callejon y un par de azoteas."""
    for (u, v, y) in ((26.0, 26.0, Y_ALTA), (22.4, 11.0, Y_ALTA), (35.0, 16.0, Y_ALTA),
                      (11.2, 50.0, Y_MEDIA), (27.6, 45.0, Y_MEDIA), (46.4, 30.0, Y_MEDIA),
                      (17.2, 62.0, Y_MEDIA), (31.2, 37.5, Y_MEDIA), (46.4, 62.0, Y_MEDIA),
                      (6.5, 37.5, Y_MEDIA)):
        L.punto(u, y + 0.1, v)
    altas = sorted(casas, key=lambda f: -f["cima"])[:3]
    for f in altas:
        L.punto((f["u0"] + f["u1"]) * 0.5, f["cima"] + 0.1, (f["v0"] + f["v1"]) * 0.5)


# =========================================================================================================
def construir(l, rect, suelo_y, rng):
    x0, z0, x1, z1 = rect
    # si llega un rectangulo mayor que el diseno se centra, redondeando a 0,2 m para que los muros de 0,3
    # caigan igual en la rejilla de 10 cm y en la de 20 (la version _lo del mapa)
    ox = x0 + math.floor(max(0.0, (x1 - x0 - W) * 0.5) / 0.2) * 0.2
    oz = z0 + math.floor(max(0.0, (z1 - z0 - D) * 0.5) / 0.2) * 0.2
    if x1 - x0 < W - 0.01 or z1 - z0 < D - 0.01:
        print("zona_casco: AVISO rect %.1f x %.1f menor que el diseno %.1f x %.1f"
              % (x1 - x0, z1 - z0, W, D))
    L = _Local(l, ox, oz, suelo_y)

    _terreno(L, rng)

    casas = []
    for (nombre, u0, v0, u1, v1, bancal, caras, pmin, pmax, podio, sin_puerta) in _MANZANAS:
        casas += _manzana(L, rng, u0, v0, u1, v1, bancal, caras, nombre, pmin, pmax, podio, sin_puerta)

    # perrones de las manzanas sobre basamento: sin esto la puerta se queda a 0,75 m de la calle, que es
    # justo el salto que el A* de las criaturas no admite
    for (u, v, cota, hacia) in ((16.4, 38.2, Y_MEDIA, "+z"),      # C1 -> calle del Mar
                                (20.0, 45.7, Y_MEDIA, "-z"),      # C1 -> callejon de arriba
                                (36.4, 64.7, Y_MEDIA, "-z"),      # D3 -> callejon del sur
                                (36.4, 54.4, Y_MEDIA, "+z"),      # D3 -> calle de la Cuesta
                                (14.2, 22.6, Y_ALTA, "+z"),       # A4 -> calle Alta
                                (18.4, 34.3, Y_ALTA, "-z")):      # A4 -> callejon de la muralla
        _peldanos(L, u, v, cota, 1.5, 3.2, 0.75, hacia, "caliza")

    _plazoletas(L, rng, casas)
    _arco(L, rng, 20.8, 15.6, 24.0, 17.0, Y_ALTA + 3.2)          # sobre el callejon del Campanario
    _arco(L, rng, 17.4, 44.8, 18.8, 47.0, Y_MEDIA + 3.2)         # sobre el callejon de las manzanas C
    _arco(L, rng, 30.0, 58.6, 32.4, 60.0, Y_MEDIA + 3.2)         # sobre el callejon de las manzanas D
    puentes = _pasarelas(L, rng, casas)
    _danos(L, rng, casas)
    faroles = _calle(L, rng, casas)
    _puntos(L, rng, casas)

    con_interior = sum(1 for f in casas if f["interior"])
    print("zona_casco: %d casas (%d con interior jugable), %d pasarelas de azotea, %d farolas, "
          "%d escalinatas publicas" % (len(casas), con_interior, puentes, faroles,
                                       len(_ESCALINATAS_ALTAS) + 14))
