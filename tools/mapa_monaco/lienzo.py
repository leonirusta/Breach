"""LIENZO DEL MAPA "monaco": lo que comparten los agentes que construyen cada zona del mapa.

Cada zona (plaza del jefe, cuarteles, hospital, perimetro...) es un modulo tools/mapa_monaco/zona_<nombre>.py
con una funcion:

    def construir(l: Lienzo, rect: tuple, suelo_y: float, rng: random.Random) -> None

`rect` = (x0, z0, x1, z1) en METROS: la zona solo dibuja dentro de ese rectangulo. `suelo_y` es la
altura del suelo general. Todo va en metros, Y hacia arriba, origen en la esquina minima del mapa.

La zona NO escribe voxels: apunta PRIMITIVAS (cajas, cilindros, esferas, lineas...) con un material por
nombre. El integrador (tools/generar_mapa_monaco.py) las rasteriza en orden sobre el volumen del mapa a
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
    # --- suelo y roca de la Roca de Monaco -----------------------------------------------------------
    "roca":              ((132, 124, 108), "piedra"),
    "roca_clara":        ((158, 150, 132), "piedra"),
    "tierra":            ((84, 70, 52), "tierra"),
    "arena":             ((196, 178, 142), "tierra"),
    "adoquin":           ((128, 122, 112), "piedra"),
    "adoquin_claro":     ((150, 144, 132), "piedra"),
    "asfalto":           ((62, 62, 66), "piedra"),
    "acera":             ((168, 164, 154), "piedra"),
    "grava":             ((122, 116, 104), "piedra"),
    # --- piedra noble: catedral, balaustradas, escalinatas -------------------------------------------
    "caliza":            ((214, 204, 178), "piedra"),
    "caliza_clara":      ((232, 224, 202), "piedra"),
    "caliza_sombra":     ((176, 166, 144), "piedra"),
    "marmol":            ((238, 234, 226), "piedra"),
    "marmol_verde":      ((92, 118, 100), "piedra"),
    "granito":           ((104, 100, 98), "piedra"),
    # --- revocos pastel de la Riviera: LO QUE DA EL COLOR AL MAPA ------------------------------------
    "revoco_crema":      ((234, 214, 178), "hormigon"),
    "revoco_melocoton":  ((228, 178, 140), "hormigon"),
    "revoco_rosa":       ((222, 168, 156), "hormigon"),
    "revoco_ocre":       ((206, 160, 96), "hormigon"),
    "revoco_amarillo":   ((230, 198, 122), "hormigon"),
    "revoco_arena":      ((212, 192, 160), "hormigon"),
    "revoco_blanco":     ((238, 232, 220), "hormigon"),
    "revoco_terracota":  ((196, 126, 96), "hormigon"),
    # --- cubiertas ----------------------------------------------------------------------------------
    "teja":              ((178, 96, 62), "ladrillo"),
    "teja_vieja":        ((150, 84, 58), "ladrillo"),
    "teja_clara":        ((198, 122, 84), "ladrillo"),
    "pizarra":           ((70, 72, 80), "piedra"),
    "zinc":              ((136, 140, 144), "metal"),
    # --- carpinteria y detalle ----------------------------------------------------------------------
    "contraventana":     ((78, 106, 88), "madera"),     # el verde persiana de la Riviera
    "contraventana_azul":((70, 92, 118), "madera"),
    "madera":            ((122, 88, 58), "madera"),
    "madera_clara":      ((168, 138, 98), "madera"),
    "hierro":            ((46, 46, 50), "metal"),       # barandillas, faroles, rejas
    "hierro_blanco":     ((198, 198, 194), "metal"),
    "laton":             ((176, 140, 68), "metal"),
    "metal":             ((104, 108, 112), "metal"),
    "metal_oxidado":     ((118, 74, 48), "metal"),
    "vidrio":            ((150, 186, 196), "vidrio"),
    "vidrio_espejo":     ((120, 152, 178), "vidrio"),
    "toldo_rojo":        ((168, 56, 48), "tela"),
    "toldo_crema":       ((226, 212, 186), "tela"),
    "toldo_verde":       ((62, 104, 72), "tela"),
    "lona":              ((196, 188, 168), "tela"),
    # --- vegetacion y mar ---------------------------------------------------------------------------
    "hoja_palmera":      ((78, 122, 62), "organico"),
    "hoja_oscura":       ((48, 82, 48), "organico"),
    "hoja_seto":         ((64, 100, 58), "organico"),
    "cipres":            ((42, 70, 48), "organico"),
    "tronco":            ((104, 84, 60), "madera"),
    "flor_rosa":         ((214, 108, 142), "organico"),
    "flor_roja":         ((186, 54, 48), "organico"),
    "cesped":            ((86, 118, 62), "organico"),
    "agua_mar":          ((44, 116, 146), "organico"),
    # --- escombro (el mapa esta a medio derruir, como en la referencia) ------------------------------
    "escombro":          ((156, 148, 132), "hormigon"),
    "escombro_claro":    ((186, 178, 162), "hormigon"),
    "polvo":             ((198, 188, 166), "tierra"),
    "hormigon":          ((150, 146, 138), "hormigon"),
    "hormigon_visto":    ((166, 162, 154), "hormigon"),
    "ladrillo":          ((152, 96, 74), "ladrillo"),
    "varilla":           ((122, 78, 54), "metal"),      # hierros retorcidos del hormigon roto
    # --- luces --------------------------------------------------------------------------------------
    "luz_calida":        ((255, 196, 130), "luz"),
    "luz_fria":          ((180, 214, 255), "luz"),
    "luz_dorada":        ((255, 214, 150), "luz"),
}


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
