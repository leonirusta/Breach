"""LIENZO DEL MAPA "isla": lo que comparten el terreno, las zonas y el integrador.

Igual que en Monaco (tools/mapa_monaco/lienzo.py): las zonas NO escriben voxels, apuntan PRIMITIVAS con un
material por nombre y el integrador las rasteriza EN ORDEN encima del terreno. `hueco=True` vacia (puertas,
ventanas, el tunel). Todo en metros, Y arriba, origen en la esquina minima del mapa.

Lo nuevo respecto a Monaco son tres listas de DATOS PARA EL JUEGO que no son voxels:
  - `puertas`: cada hueco de puerta que se talla lleva su hoja en `<mapa>.puertas.json` (puerta.gd la abre
    al acercarse). `puerta()` TALLA el hueco y apunta la hoja a la vez: asi es imposible que un hueco se
    quede sin puerta o que una puerta caiga en medio de un muro.
  - `botin`: puntos de arma, municion, casco, escudo, vendas y botiquines (`<mapa>.botin.json`).
  - `agua`: laminas de agua locales por encima del mar (el mar va aparte: `MAR_Y`).

MATERIALES Y ANCLAJE. El tipo "suelo"/"suelo_duro" lleva la marca de ancla del motor: lo que toca eso por
una cadena de caras no se cae. TODO el terreno es de esos tipos (arena, cesped, roca de monte, nieve,
asfalto), asi que un edificio apoyado en el terreno esta anclado aunque le vuelen media planta baja, y un
monte no se derrumba nunca: se le hacen crateres. Ver docs/10_CONSTRUIR_MAPAS.md.
"""
import math

# nombre -> ((r, g, b), tipo). tipo: suelo | suelo_duro | suelo_pintura | piedra | ladrillo | hormigon |
# metal | madera | tela | vidrio | organico | luz | goma | base
MATERIALES = {
    # --- terreno (TODO ancla) -------------------------------------------------------------------------
    "roca_base":        ((62, 58, 52), "base"),
    "arena_playa":      ((222, 204, 156), "suelo"),
    "arena_mojada":     ((172, 156, 118), "suelo"),
    "arena_desierto":   ((226, 184, 118), "suelo"),
    "arena_duna":       ((236, 198, 132), "suelo"),
    "cesped":           ((90, 134, 62), "suelo"),
    "cesped_oscuro":    ((64, 108, 50), "suelo"),
    "cesped_seco":      ((156, 150, 86), "suelo"),
    "tierra":           ((112, 86, 60), "suelo"),
    "tierra_selva":     ((74, 58, 40), "suelo"),
    "musgo":            ((58, 98, 46), "suelo"),
    "hojarasca":        ((96, 78, 46), "suelo"),
    "roca_monte":       ((122, 118, 110), "suelo_duro"),
    "roca_oscura":      ((88, 86, 84), "suelo_duro"),
    "roca_roja":        ((170, 98, 64), "suelo_duro"),
    "roca_roja_clara":  ((202, 138, 92), "suelo_duro"),
    "nieve":            ((236, 240, 246), "suelo"),
    "grava":            ((134, 128, 116), "suelo"),
    "camino":           ((150, 122, 88), "suelo"),
    "asfalto":          ((58, 58, 62), "suelo_duro"),
    "linea_blanca":     ((232, 232, 226), "suelo_pintura"),
    "linea_amarilla":   ((222, 182, 58), "suelo_pintura"),
    "adoquin":          ((136, 128, 118), "suelo_duro"),
    "losa_plaza":       ((196, 188, 172), "suelo_duro"),
    "acera":            ((172, 168, 160), "suelo_duro"),
    # --- construccion ---------------------------------------------------------------------------------
    "hormigon":         ((150, 146, 138), "hormigon"),
    "hormigon_claro":   ((188, 184, 176), "hormigon"),
    "hormigon_oscuro":  ((108, 106, 104), "hormigon"),
    "ladrillo":         ((150, 84, 62), "ladrillo"),
    "ladrillo_oscuro":  ((104, 60, 48), "ladrillo"),
    "revoco_blanco":    ((236, 232, 222), "hormigon"),
    "revoco_crema":     ((230, 212, 176), "hormigon"),
    "revoco_gris":      ((164, 166, 170), "hormigon"),
    "revoco_azul":      ((120, 150, 176), "hormigon"),
    "revoco_salmon":    ((222, 160, 130), "hormigon"),
    "adobe":            ((196, 150, 104), "ladrillo"),
    "adobe_claro":      ((222, 186, 138), "ladrillo"),
    "piedra":           ((140, 134, 122), "piedra"),
    "piedra_templo":    ((132, 126, 100), "piedra"),
    "piedra_musgo":     ((92, 112, 74), "piedra"),
    "marmol":           ((232, 228, 220), "piedra"),
    "baldosa":          ((178, 170, 156), "hormigon"),
    "parquet":          ((150, 108, 70), "madera"),
    "teja":             ((172, 90, 60), "ladrillo"),
    "pizarra":          ((66, 70, 78), "piedra"),
    "vidrio":           ((150, 190, 200), "vidrio"),
    "vidrio_espejo":    ((96, 140, 170), "vidrio"),
    "metal":            ((110, 114, 118), "metal"),
    "metal_oscuro":     ((52, 54, 58), "metal"),
    "chapa":            ((150, 156, 160), "metal"),
    "chapa_oxido":      ((128, 76, 50), "metal"),
    "chapa_roja":       ((168, 40, 36), "metal"),
    "chapa_azul":       ((44, 82, 150), "metal"),
    "chapa_blanca":     ((220, 222, 224), "metal"),
    "chapa_amarilla":   ((222, 176, 40), "metal"),
    "neumatico":        ((30, 30, 32), "goma"),
    "madera":           ((128, 92, 60), "madera"),
    "madera_oscura":    ((84, 60, 40), "madera"),
    "madera_clara":     ((176, 142, 100), "madera"),
    "tronco":           ((98, 74, 50), "madera"),
    "tronco_claro":     ((210, 204, 188), "madera"),      # abedul
    "toldo_rojo":       ((176, 52, 44), "tela"),
    "toldo_azul":       ((50, 90, 150), "tela"),
    "toldo_crema":      ((228, 214, 184), "tela"),
    # --- vegetacion -----------------------------------------------------------------------------------
    "hoja_pino":        ((38, 76, 52), "organico"),
    "hoja_verde":       ((72, 124, 52), "organico"),
    "hoja_clara":       ((112, 156, 62), "organico"),
    "hoja_selva":       ((36, 98, 40), "organico"),
    "hoja_palmera":     ((84, 130, 60), "organico"),
    "liana":            ((56, 92, 40), "organico"),
    "cactus":           ((80, 128, 72), "organico"),
    "flor_roja":        ((196, 50, 50), "organico"),
    "flor_amarilla":    ((230, 196, 60), "organico"),
    "flor_morada":      ((140, 80, 170), "organico"),
    # --- luces ----------------------------------------------------------------------------------------
    "luz_calida":       ((255, 200, 140), "luz"),
    "luz_fria":         ((190, 220, 255), "luz"),
    "luz_roja":         ((255, 60, 50), "luz"),
}

# Cuantas variantes de color (manchas) lleva cada tipo: la paleta del motor tiene 240 huecos.
VARIANTES = {"suelo": 3, "suelo_duro": 3, "piedra": 3, "ladrillo": 3, "hormigon": 3, "madera": 2,
             "organico": 2, "metal": 2, "tela": 1, "goma": 1, "vidrio": 1, "luz": 1, "base": 1,
             "suelo_pintura": 1}


class Lienzo:
    def __init__(self):
        self.prims = []        # (tipo, datos, material, hueco)
        self.luces = []        # (x, y, z, (r, g, b), energia, alcance, direccion, cono)
        self.puertas = []      # dict: pos, giro, ancho, alto, tipo, doble
        self.botin = []        # dict: pos, tipo, nivel, zona
        self.agua = []         # dict: y, rect
        self.spawns = []       # (x, y, z, giro)
        self.zona = "isla"     # la zona que esta dibujando (etiqueta del botin)

    def _mat(self, m):
        if m not in MATERIALES:
            raise ValueError("material desconocido: %s" % m)
        return m

    # --- volumenes ------------------------------------------------------------------------------------
    def caja(self, x0, y0, z0, x1, y1, z1, mat="hormigon", hueco=False):
        self.prims.append(("caja", (min(x0, x1), min(y0, y1), min(z0, z1), max(x0, x1), max(y0, y1), max(z0, z1)),
                           self._mat(mat), hueco))

    def cilindro(self, cx, y0, cz, radio, alto, mat="metal", hueco=False, eje="y"):
        """eje "y": vertical desde (cx, y0, cz). "x"/"z": tumbado, (cx, y0, cz) centro de una base."""
        self.prims.append(("cilindro", (cx, y0, cz, radio, alto, eje), self._mat(mat), hueco))

    def esfera(self, cx, cy, cz, radio, mat="hoja_verde", hueco=False):
        self.prims.append(("elipsoide", (cx, cy, cz, radio, radio, radio), self._mat(mat), hueco))

    def elipsoide(self, cx, cy, cz, rx, ry, rz, mat="hoja_verde", hueco=False):
        self.prims.append(("elipsoide", (cx, cy, cz, rx, ry, rz), self._mat(mat), hueco))

    def linea(self, x0, y0, z0, x1, y1, z1, grosor, mat="metal", hueco=False):
        self.prims.append(("linea", (x0, y0, z0, x1, y1, z1, grosor * 0.5), self._mat(mat), hueco))

    def cuna(self, x0, y0, z0, x1, y1, z1, sube_hacia="+x", mat="hormigon", hueco=False):
        """rampa maciza: la altura crece de y0 a y1 hacia `sube_hacia` (+x, -x, +z, -z)"""
        self.prims.append(("cuna", (min(x0, x1), y0, min(z0, z1), max(x0, x1), y1, max(z0, z1), sube_hacia),
                           self._mat(mat), hueco))

    def cono(self, cx, y0, cz, r0, r1, alto, mat="hoja_pino", hueco=False):
        """tronco de cono vertical: radio r0 abajo, r1 arriba (copas de pino, cupulas escalonadas, faros)"""
        self.prims.append(("cono", (cx, y0, cz, r0, r1, alto), self._mat(mat), hueco))

    # --- ayudas ---------------------------------------------------------------------------------------
    def escalera(self, x0, z0, y0, largo, ancho, alto, hacia="+x", mat="hormigon", peldano=0.3):
        """Escalera MACIZA (cada peldano es una caja hasta el suelo, asi que apoya entera): sube `alto`
        en `largo` metros hacia `hacia`. (x0, z0) es la esquina de arranque; `ancho` va hacia +z (escaleras
        en X) o hacia +x (escaleras en Z)."""
        n = max(1, int(round(alto / peldano)))
        for i in range(n):
            h = y0 + alto * (i + 1) / n
            a, b = largo * i / n, largo
            if hacia == "+x":
                self.caja(x0 + a, y0, z0, x0 + b, h, z0 + ancho, mat)
            elif hacia == "-x":
                self.caja(x0 - b, y0, z0, x0 - a, h, z0 + ancho, mat)
            elif hacia == "+z":
                self.caja(x0, y0, z0 + a, x0 + ancho, h, z0 + b, mat)
            else:
                self.caja(x0, y0, z0 - b, x0 + ancho, h, z0 - a, mat)

    def puerta(self, x, y, z, giro, ancho=1.2, alto=2.4, tipo="madera", doble=False, grosor=0.9, marco=None):
        """TALLA el hueco de una puerta en el muro y apunta su hoja para el juego.

        (x, y, z) = centro del umbral a ras de suelo. giro 0: el muro va a lo largo de X y la puerta se
        cruza en Z; giro 90: el muro va a lo largo de Z y se cruza en X. `grosor` es lo que se talla a
        traves del muro (de sobra: un muro de 0,3-0,45 m). `marco` = material del marco (opcional)."""
        a, g = ancho * 0.5, grosor * 0.5
        if giro % 180 == 0:
            if marco:
                self.caja(x - a - 0.15, y, z - g * 0.5, x + a + 0.15, y + alto + 0.15, z + g * 0.5, marco)
            self.caja(x - a, y, z - g, x + a, y + alto, z + g, "hormigon", hueco=True)
        else:
            if marco:
                self.caja(x - g * 0.5, y, z - a - 0.15, x + g * 0.5, y + alto + 0.15, z + a + 0.15, marco)
            self.caja(x - g, y, z - a, x + g, y + alto, z + a, "hormigon", hueco=True)
        self.puertas.append({"pos": [round(x, 3), round(y, 3), round(z, 3)], "giro": float(giro % 180),
                             "ancho": round(ancho, 3), "alto": round(alto, 3), "tipo": tipo, "doble": bool(doble)})

    def hueco_paso(self, x, y, z, giro, ancho=1.5, alto=2.4, grosor=0.9):
        """Hueco sin hoja (arco, paso entre salas)."""
        a, g = ancho * 0.5, grosor * 0.5
        if giro % 180 == 0:
            self.caja(x - a, y, z - g, x + a, y + alto, z + g, "hormigon", hueco=True)
        else:
            self.caja(x - g, y, z - a, x + g, y + alto, z + a, "hormigon", hueco=True)

    # --- datos para el juego --------------------------------------------------------------------------
    def luz(self, x, y, z, color=(255, 190, 130), energia=1.0, alcance=9.0, direccion=None, cono=0.0):
        self.luces.append((x, y, z, tuple(color), energia, alcance, tuple(direccion) if direccion else None, float(cono)))

    def loot(self, x, y, z, tipo, nivel=1):
        """Punto de botin a ras de suelo (el juego lo levanta un palmo)."""
        self.botin.append({"pos": [round(x, 2), round(y, 2), round(z, 2)], "tipo": tipo, "nivel": int(nivel),
                           "zona": self.zona})

    def loot_sala(self, x0, z0, x1, z1, y, rng, nivel=1, n=None):
        """Reparte botin por una sala: siempre algo de municion, y armas/escudo/casco segun suerte."""
        if n is None:
            area = abs(x1 - x0) * abs(z1 - z0)
            n = 1 + (1 if area > 40 else 0) + (1 if area > 110 else 0)
        for _ in range(n):
            px = x0 + 0.8 + rng.random() * max(0.1, (x1 - x0) - 1.6)
            pz = z0 + 0.8 + rng.random() * max(0.1, (z1 - z0) - 1.6)
            r = rng.random()
            tipo = ("arma" if r < 0.28 else "municion" if r < 0.54 else "venda" if r < 0.72 else
                    "escudo" if r < 0.83 else "casco" if r < 0.93 else "botiquin")
            niv = nivel + (1 if rng.random() < 0.18 else 0) - (1 if rng.random() < 0.18 else 0)
            self.loot(px, y, pz, tipo, max(1, min(3, niv)))

    def lamina_agua(self, y, x0, z0, x1, z1):
        self.agua.append({"y": round(y, 3), "rect": [round(x0, 2), round(z0, 2), round(x1, 2), round(z1, 2)]})

    def spawn(self, x, y, z, giro=0.0):
        self.spawns.append((x, y, z, giro))
