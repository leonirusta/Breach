"""LIENZO DEL MAPA PvE: lo que comparten los agentes que construyen cada zona del mapa.

Cada zona (plaza del jefe, cuarteles, hospital, perimetro...) es un modulo tools/mapa_pve/zona_<nombre>.py
con una funcion:

    def construir(l: Lienzo, rect: tuple, suelo_y: float, rng: random.Random) -> None

`rect` = (x0, z0, x1, z1) en METROS: la zona solo dibuja dentro de ese rectangulo. `suelo_y` es la
altura del suelo general. Todo va en metros, Y hacia arriba, origen en la esquina minima del mapa.

La zona NO escribe voxels: apunta PRIMITIVAS (cajas, cilindros, esferas, lineas...) con un material por
nombre. El integrador (tools/generar_mapa_pve.py) las rasteriza en orden sobre el volumen del mapa a
10 cm (y a 20 cm para la version _lo) y traduce cada nombre de material al material del motor. Las
primitivas con hueco=True VACIAN (puertas, ventanas, boquetes, cuevas).

Orden: se aplican en el orden en que se apuntan. Primero lo grande, luego los huecos, luego el detalle.

REGLAS DE JUEGO (las criaturas usan el A* de voxels):
  - Suelos planos; escalones de 0,6 m como mucho; rampas suaves.
  - Puertas de al menos 1,4 m de ancho y 2,6 m de alto. Pasillos principales de 3 m.
  - La plaza del jefe: camino de 5 m de ancho y 8 m de alto como minimo desde el resto del mapa.
  - Nada flotando: todo apoyado en el suelo o en una estructura.
"""
import math

# Materiales por nombre, con su color (sRGB 0..255) y como se comporta. El integrador los traduce a los
# del motor; si un nombre no existe en el motor usa el mas parecido por `tipo` y color.
#   tipo: tierra | piedra | ladrillo | hormigon | metal | madera | tela | vidrio | organico | luz
MATERIALES = {
    "tierra":            ((58, 48, 38), "tierra"),
    "barro":             ((46, 38, 30), "tierra"),
    "ceniza":            ((52, 50, 48), "tierra"),
    "asfalto":           ((38, 38, 40), "piedra"),
    "grava":             ((78, 74, 68), "piedra"),
    "hormigon":          ((112, 110, 104), "hormigon"),
    "hormigon_sucio":    ((82, 80, 74), "hormigon"),
    "hormigon_manchado": ((70, 62, 56), "hormigon"),
    "ladrillo":          ((104, 58, 44), "ladrillo"),
    "baldosa_hospital":  ((150, 152, 146), "piedra"),
    "metal":             ((92, 96, 100), "metal"),
    "metal_oxidado":     ((98, 62, 40), "metal"),
    "chapa_verde":       ((52, 64, 46), "metal"),
    "metal_negro":       ((30, 30, 32), "metal"),
    "madera":            ((98, 72, 48), "madera"),
    "madera_podrida":    ((64, 50, 36), "madera"),
    "carbon":            ((24, 22, 20), "madera"),
    "sacos":             ((120, 104, 76), "tela"),
    "lona":              ((92, 88, 70), "tela"),
    "lona_verde":        ((58, 70, 50), "tela"),
    "tela_blanca":       ((170, 168, 156), "tela"),
    "plastico_amarillo": ((190, 160, 40), "tela"),
    "plastico_rojo":     ((140, 30, 26), "tela"),
    "vidrio":            ((120, 150, 150), "vidrio"),
    "sangre":            ((96, 10, 8), "organico"),
    "sangre_seca":       ((58, 16, 12), "organico"),
    "carne":             ((110, 52, 48), "organico"),
    "hueso":             ((196, 188, 164), "organico"),
    "vegetacion_muerta": ((60, 56, 36), "organico"),
    "agua_sucia":        ((40, 48, 40), "organico"),
    "luz_calida":        ((255, 170, 90), "luz"),
    "luz_fria":          ((150, 200, 255), "luz"),
    "luz_roja":          ((255, 40, 30), "luz"),
    "luz_verde":         ((80, 255, 90), "luz"),
}


# PATRONES (2026-09-27, episodio 3): un material puede llevar un DIBUJO en vez de manchas de mugre al azar.
# nombre -> (patron, [colores sRGB]). El color de cada voxel A LA VISTA sale de su posicion (ver
# raster.variar): hiladas de ladrillo, sillares con juntas, revoque con chorretones, tejas, baldosas, adoquines,
# rayas de toldo, tablones, lamas de persiana, estratos de roca. Los mapas que no lo usan no cambian.
PATRON_CODIGO = {"ladrillo": 1, "sillar": 2, "revoque": 3, "teja": 4, "baldosa": 5, "adoquin": 6,
                 "rayas": 7, "tablas": 8, "lamas": 9, "estratos": 10, "cesped": 11}
PATRONES = {}


class Lienzo:
    def __init__(self):
        self.prims = []        # (tipo, datos, material, hueco)
        self.luces = []        # (x, y, z, (r, g, b), energia, alcance)
        self.puntos = []       # (x, y, z, tipo)  tipo: "jugador" | "criatura" | "jefe"

    def _mat(self, m):
        if m not in MATERIALES:
            raise ValueError("material desconocido: %s" % m)
        return m

    # --- volumenes -------------------------------------------------------------------------------------
    def caja(self, x0, y0, z0, x1, y1, z1, mat="hormigon", hueco=False):
        self.prims.append(("caja", (min(x0, x1), min(y0, y1), min(z0, z1), max(x0, x1), max(y0, y1), max(z0, z1)),
                           self._mat(mat), hueco))

    def cilindro(self, cx, y0, cz, radio, alto, mat="metal", hueco=False, eje="y"):
        """eje "y": vertical desde (cx, y0, cz). eje "x" / "z": tumbado, con (cx, y0, cz) en el centro de una
        base y `alto` como largo a lo largo de ese eje (tuberias, bidones tumbados, fustes caidos)."""
        self.prims.append(("cilindro", (cx, y0, cz, radio, alto, eje), self._mat(mat), hueco))

    def esfera(self, cx, cy, cz, radio, mat="tierra", hueco=False):
        self.prims.append(("elipsoide", (cx, cy, cz, radio, radio, radio), self._mat(mat), hueco))

    def elipsoide(self, cx, cy, cz, rx, ry, rz, mat="tierra", hueco=False):
        self.prims.append(("elipsoide", (cx, cy, cz, rx, ry, rz), self._mat(mat), hueco))

    def linea(self, x0, y0, z0, x1, y1, z1, grosor, mat="metal", hueco=False):
        """viga, cable, tuberia o alambre: capsula de diametro `grosor` entre dos puntos"""
        self.prims.append(("linea", (x0, y0, z0, x1, y1, z1, grosor * 0.5), self._mat(mat), hueco))

    def cuna(self, x0, y0, z0, x1, y1, z1, sube_hacia="+x", mat="hormigon", hueco=False):
        """rampa maciza: la altura crece de y0 a y1 en la direccion indicada (+x, -x, +z, -z)"""
        self.prims.append(("cuna", (min(x0, x1), y0, min(z0, z1), max(x0, x1), y1, max(z0, z1), sube_hacia),
                           self._mat(mat), hueco))

    # --- ayudas compuestas -----------------------------------------------------------------------------
    def escalera(self, x0, z0, y0, largo, ancho, alto, hacia="+x", mat="hormigon"):
        """escalones de 0,25 m: sube `alto` metros en `largo` metros"""
        n = max(1, int(math.ceil(alto / 0.25)))
        for i in range(n):
            h = y0 + alto * (i + 1) / n
            a = largo * i / n
            b = largo
            if hacia == "+x":
                self.caja(x0 + a, y0, z0, x0 + b, h, z0 + ancho, mat)
            elif hacia == "-x":
                self.caja(x0 - b, y0, z0, x0 - a, h, z0 + ancho, mat)
            elif hacia == "+z":
                self.caja(x0, y0, z0 + a, x0 + ancho, h, z0 + b, mat)
            else:
                self.caja(x0, y0, z0 - b, x0 + ancho, h, z0 - a, mat)

    def escalera_real(self, x0, z0, y0, largo, ancho, alto, hacia="+x", mat="acero_osc", canto="pintura_amarilla_c",
                      contrahuella=0.2, baranda="hierro", maciza=False):
        """ESCALERA DE VERDAD (2026-09-28). La de arriba (`escalera`) es una cuña de bloques macizos: de lejos es una
        rampa con dientes. Esta tiene peldaños de `contrahuella` (0,2 m: sale limpia a 10 y a 20 cm) con su huella
        de 0,2 de grueso y el CANTO pintado, abierta por debajo (se ve a traves, como una de acero) salvo `maciza`,
        dos ZANCAS en diagonal que la sostienen y BARANDILLA a los dos lados (postes, pasamanos y listón medio).
        (x0, z0, y0) es el pie de la escalera por el lado izquierdo; sube hacia `hacia`."""
        n = max(1, int(round(alto / contrahuella)))
        r, hu = alto / n, largo / n

        def xz(u, w):
            if hacia == "+x":
                return x0 + u, z0 + w
            if hacia == "-x":
                return x0 - u, z0 + w
            if hacia == "+z":
                return x0 + w, z0 + u
            return x0 + w, z0 - u

        def caja(u0, v0, w0, u1, v1, w1, m):
            xa, za = xz(u0, w0)
            xb, zb = xz(u1, w1)
            self.caja(xa, v0, za, xb, v1, zb, m)

        def linea(u0, v0, w0, u1, v1, w1, g, m):
            xa, za = xz(u0, w0)
            xb, zb = xz(u1, w1)
            self.linea(xa, v0, za, xb, v1, zb, g, m)

        for i in range(n):
            top = y0 + r * (i + 1)
            u0, u1 = hu * i, min(largo, hu * (i + 1) + 0.02)
            caja(u0, y0 if maciza else top - 0.2, 0.0, u1, top, ancho, mat)
            if canto:
                caja(u0, top - 0.1, 0.1, u0 + 0.1, top, ancho - 0.1, canto)
        for w in (0.1, ancho - 0.1):
            linea(0.0, y0 - 0.05, w, largo, y0 + alto - 0.15, w, 0.28, mat)            # las zancas
        if baranda:
            for w in (0.05, ancho - 0.05):
                k = 0.0
                while k <= largo + 0.01:
                    i = min(n - 1, int(k / hu))
                    pie = y0 + r * (i + 1)
                    caja(k, pie, w - 0.05, k + 0.1, pie + 1.0, w + 0.05, baranda)        # los postes
                    k += 1.2
                linea(0.0, y0 + r + 1.0, w, largo, y0 + alto + 1.0, w, 0.1, baranda)    # el pasamanos
                linea(0.0, y0 + r + 0.5, w, largo, y0 + alto + 0.5, w, 0.1, baranda)    # el liston medio

    def muro_con_huecos(self, x0, y0, z0, x1, y1, z1, huecos, mat="hormigon"):
        """muro macizo y luego huecos: lista de (x0, y0, z0, x1, y1, z1)"""
        self.caja(x0, y0, z0, x1, y1, z1, mat)
        for h in huecos:
            self.caja(*h, mat, hueco=True)

    def escombros(self, cx, cz, suelo_y, radio, n, rng, mats=("hormigon_sucio", "ladrillo", "metal_oxidado")):
        for _ in range(n):
            a = rng.random() * math.tau
            r = radio * math.sqrt(rng.random())
            s = 0.15 + rng.random() * 0.45
            x, z = cx + math.cos(a) * r, cz + math.sin(a) * r
            self.caja(x - s, suelo_y, z - s * 0.7, x + s, suelo_y + s * (0.5 + rng.random()), z + s * 0.7,
                      mats[rng.randrange(len(mats))])

    def charco_sangre(self, cx, cz, suelo_y, radio, rng, mat="sangre_seca"):
        """mancha en el suelo: tine los voxels de arriba del suelo (1 voxel de grosor)"""
        for _ in range(4 + int(radio * 4)):
            a = rng.random() * math.tau
            r = radio * rng.random()
            rr = radio * (0.25 + 0.4 * rng.random())
            self.elipsoide(cx + math.cos(a) * r, suelo_y - 0.05, cz + math.sin(a) * r, rr, 0.06, rr * 0.8, mat)

    # --- datos para el juego ---------------------------------------------------------------------------
    def luz(self, x, y, z, color=(255, 170, 90), energia=1.0, alcance=8.0, direccion=None, cono=0.0):
        """farol/foco para el juego (el integrador lo guarda donde el juego lee las luces del mapa).

        `direccion` (x, y, z: hacia donde apunta; recto abajo es (0, -1, 0)) y `cono` (grados de MEDIO angulo)
        convierten el farol en un FOCO que dibuja un cono de luz en el suelo, como una linterna. Sin direccion
        se queda en luz normal que alumbra en todas direcciones, que es lo que piden las bombillas desnudas,
        las balizas de emergencia y el fuego.
        Guias: farolas y apliques miran abajo con cono 35; los focos de las torres, abajo y hacia fuera con 25;
        los reflectores de vigilancia, casi horizontales con 18. Pon la luz DONDE ESTA LA BOMBILLA, justo bajo
        la cabeza del farol y no dentro del poste, o el cono sale del sitio equivocado."""
        self.luces.append((x, y, z, tuple(color), energia, alcance, tuple(direccion) if direccion else None, float(cono)))

    def punto(self, x, y, z, tipo="criatura"):
        self.puntos.append((x, y, z, tipo))
