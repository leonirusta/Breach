"""Genera un avatar de SOLDADO detallado para Breach.

Escribe godot/avatar/soldier_rig.json con el MISMO esqueleto que avatar_rig.json (mismos huesos,
mismos padres, mismas posiciones de reposo) pero con el arte al DOBLE DE RESOLUCION y con equipo
militar modelado: casco con visera y gafas, chaleco con placas y cargadores, hombreras, guantes,
rodilleras, botas con suela, cinturon con cantimplora y radio.

Por que doble resolucion y no mas: el modelo original mide 34 voxels de alto (un torso es una caja
de 7x8x5). A esa escala no cabe un detalle; al doble son 68 de alto y el torso 14x16x10, que ya da
para placas, correas y bolsillos sin que el personaje pese demasiado. Se dobla TODO a la vez --
world_pos, mesh_off y las coordenadas -- y se parte por dos el tamano de voxel, asi que el soldado
mide exactamente lo mismo en metros que el avatar viejo y las animaciones, la IK y las poses del
arma siguen encajando sin tocar nada.

Uso:  python tools/make_soldier.py
"""
import struct
import json, os, io

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RIG = os.path.join(RAIZ, "godot", "avatar", "avatar_rig.json")
PALETA = os.path.join(RAIZ, "godot", "avatar", "palette.json")
SALIDA = os.path.join(RAIZ, "godot", "avatar", "soldier_rig.json")

# --- colores del soldado (se anaden al final de la paleta; los indices viejos no se tocan) ---
NUEVOS = [
    (58, 66, 48),    # 0 verde oliva del uniforme
    (44, 50, 37),    # 1 oliva en sombra (pliegues, entrepierna, axilas)
    (78, 86, 62),    # 2 oliva claro (partes altas)
    (96, 88, 66),    # 3 caqui de las cinchas
    (33, 34, 31),    # 4 negro mate del equipo
    (22, 23, 21),    # 5 negro profundo (suela, correas)
    (52, 55, 50),    # 6 gris del casco
    (68, 72, 66),    # 7 gris claro del casco (arriba)
    (120, 96, 62),   # 8 cuero de las botas
    (196, 150, 116), # 9 piel
    (166, 122, 92),  # 10 piel en sombra
    (40, 78, 96),    # 11 cristal de las gafas
    (92, 150, 172),  # 12 brillo del cristal
    (150, 146, 132), # 13 metal (hebillas, cargadores)
    (128, 44, 38),   # 14 rojo del parche
    (176, 168, 148), # 15 arena (bolsillos)
    (232, 230, 222), # 16 blanco del ojo
    (46, 62, 44),    # 17 iris verdoso
    (58, 44, 34),    # 18 cejas y sombra de los parpados
    # --- colores de los avatares infectados y de los accesorios ---
    (124, 138, 96),  # 19 carne podrida (verdosa)
    (92, 104, 70),   # 20 carne podrida en sombra
    (150, 160, 128), # 21 carne reseca, en los bordes de las heridas
    (226, 221, 205), # 22 hueso (blanco hueso, no arena)
    (108, 22, 20),   # 23 sangre seca
    (66, 12, 12),    # 24 sangre vieja, casi negra
    (150, 60, 58),   # 25 carne viva de las heridas
    (214, 178, 60),  # 26 laton de aritos, llaveros y hebillas
    # --- EL HERALDO DE CENIZA. Piel de roca apagada, hierro viejo y brasa. La brasa va en TRES tonos
    # porque una sola nota de naranja se lee como plastico: con un granate debajo y un amarillo
    # puntual arriba parece que arde de verdad.
    (70, 70, 74),    # 27 ceniza: la piel, gris piedra
    (52, 52, 56),    # 28 ceniza en sombra
    (96, 96, 100),   # 29 ceniza clara (hombros y pomulos, por donde da la luz)
    (150, 34, 16),   # 30 brasa honda, casi granate
    (226, 98, 20),   # 31 brasa
    (255, 190, 70),  # 32 brasa viva (el corazon del rescoldo)
    (74, 70, 66),    # 33 hierro viejo del yelmo
    (108, 104, 98),  # 34 hierro pulido (filos, cresta, remaches)
    (34, 31, 29),    # 35 cuero negro del faldon y la capa
    (172, 166, 150), # 36 hueso del craneo y los cuernos (bajado de 206: con la luz del lobby
                     #    se quemaba y la cara salia como un rectangulo blanco)
    (132, 126, 112), # 37 hueso en sombra
    # LOS COLORES NUEVOS VAN AL FINAL, SIEMPRE. Meti estos dos entre el 32 y el 33 y corri DOS
    # POSICIONES todo lo de detras: el hierro paso a ser cuero, el cuero hueso... y el casco entero
    # salio rojo. La paleta se indexa por numero; insertar en medio es renumerar el mundo.
    (196, 16, 14),   # 38 rojo de las pupilas: sangre, no fuego
    (255, 72, 58),   # 39 el centro de la pupila, encendido
]


PALETA_LIMPIA = os.path.join(RAIZ, "godot", "avatar", "palette.antes_soldado.json")


def cargar():
    rig = json.load(io.open(RIG, encoding="utf-8"))
    # se parte SIEMPRE de la paleta original: si se leyera la ya ampliada, cada pasada del script
    # volveria a anadir los mismos colores al final y la paleta creceria sin parar
    origen = PALETA_LIMPIA if os.path.exists(PALETA_LIMPIA) else PALETA
    pal = json.load(io.open(origen, encoding="utf-8"))
    base = len(pal)
    pal.extend([list(c) for c in NUEVOS])
    return rig, pal, base


class Cuerpo:
    """Voxels de un hueso. Se pinta por cajas; la ultima escrita manda, asi que se va de lo
    general (el bulto) a lo concreto (correas, hebillas, costuras)."""

    def __init__(self):
        self.v = {}

    def caja(self, x0, x1, y0, y1, z0, z1, c):
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                for z in range(z0, z1 + 1):
                    self.v[(x, y, z)] = c

    def quitar(self, x0, x1, y0, y1, z0, z1):
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                for z in range(z0, z1 + 1):
                    self.v.pop((x, y, z), None)

    def marco(self, x0, x1, y0, y1, z0, z1, c):
        """Pinta SOLO EL BORDE de la boca de una herida, no su interior. Con cajas rellenas, el
        color volvia a tapar el agujero recien abierto y la herida quedaba plana."""
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                if x in (x0, x1) or y in (y0, y1):
                    for z in range(z0, z1 + 1):
                        self.v[(x, y, z)] = c

    def hueco(self, x0, x1, y0, y1, z0, z1):
        """Coordenadas a BORRAR del cuerpo de debajo. No pinta nada: abre un agujero de verdad.
        Es la diferencia entre una mancha de color hueso y un boquete con el hueso dentro."""
        return [[x, y, z] for x in range(x0, x1 + 1)
                for y in range(y0, y1 + 1) for z in range(z0, z1 + 1)]

    def espejo_x(self):
        """Copia espejada en X, para el lado contrario del cuerpo."""
        o = Cuerpo()
        for (x, y, z), c in self.v.items():
            o.v[(-x - 1, y, z)] = c
        return o

    def lista(self):
        return [[x, y, z, c] for (x, y, z), c in sorted(self.v.items())]

    def espejo_huecos(self, hs):
        return [[-h[0] - 1, h[1], h[2]] for h in hs]


def construir(C):
    """C = indice del primer color nuevo en la paleta."""
    OLIVA, SOMBRA, CLARO, CAQUI = C + 0, C + 1, C + 2, C + 3
    NEGRO, HONDO, CASCO, CASCO_A = C + 4, C + 5, C + 6, C + 7
    CUERO, PIEL, PIEL_S, CRISTAL = C + 8, C + 9, C + 10, C + 11
    BRILLO, METAL, ROJO, ARENA = C + 12, C + 13, C + 14, C + 15
    OJO, IRIS, CEJA = C + 16, C + 17, C + 18
    b = {}

    # ---------------- cabeza: casco, visera, gafas y cara ----------------
    h = Cuerpo()
    h.caja(-4, 3, -6, 6, -6, 4, PIEL)                  # cabeza
    h.caja(-4, 3, -6, -3, -6, 4, PIEL_S)               # menton en sombra
    h.caja(-5, 4, 2, 7, -7, 5, CASCO)                  # casco
    h.caja(-5, 4, 5, 7, -7, 5, CASCO_A)                # parte alta, mas clara
    h.caja(-5, 4, 2, 3, -8, 5, CASCO)                  # borde que sobresale
    h.caja(-6, 5, 5, 7, -8, -6, CASCO)                 # visera delante
    # GAFAS SUBIDAS A LA FRENTE. Puestas a la altura de los ojos le tapaban la cara entera y el
    # soldado se quedaba sin mirada: asi se le ven los ojos y se sigue notando que lleva gafas.
    h.caja(-5, 4, 3, 4, -8, -6, NEGRO)                 # correa de las gafas
    h.caja(-4, 3, 3, 4, -9, -8, CRISTAL)               # cristal, apoyado en el casco
    h.caja(-4, -2, 4, 4, -9, -8, BRILLO)               # reflejo
    # OJOS. Dos por lado: blanco hacia fuera e iris hacia dentro, con la ceja encima. A esta
    # resolucion (cabeza de 8 voxels de ancho) es lo justo para que haya mirada y no un borron.
    # OJOS Y CEJAS A RAS DE LA CARA (z -6, que es donde acaba la cabeza), no en -7. Estaban un
    # voxel POR DELANTE y por eso todo lo que iba encima parecia pegado, como una pegatina.
    h.caja(-4, -1, 4, 4, -6, -6, CEJA)                 # ceja izquierda
    h.caja(0, 3, 4, 4, -6, -6, CEJA)                   # ceja derecha
    h.caja(-1, 0, -3, -1, -6, -6, PIEL_S)              # nariz, por debajo de la linea de los ojos
    h.caja(-5, 4, 0, 1, 4, 5, CAQUI)                   # cincha por detras
    h.caja(-5, -4, -2, 2, -4, 3, NEGRO)                # auricular izquierdo
    h.caja(3, 4, -2, 2, -4, 3, NEGRO)                  # auricular derecho
    h.caja(-2, 1, -5, -4, -7, -6, PIEL_S)              # boca en sombra
    b["head"] = h

    # PARPADOS. Van como huesos propios, hijos de la cabeza, en vez de pintados en la cara: asi se
    # pueden ensenar y esconder en caliente (encogiendo el hueso, como se hace con las manos en
    # primera persona) sin rehacer la malla. Cada uno es la tapa que cubre la MITAD DE ARRIBA de su
    # ojo; en reposo estan encogidos y no se ven.
    # ANCHO 3, EL DEL OJO ENTERO. La primera version media 2 y tapaba solo los dos voxels de
    # blanco, dejando el iris al aire: al apuntar, un ojo parecia tener pupila y el otro no.
    # UN VOXEL DE MARGEN A CADA LADO (x -1..3 en vez de 0..2): asi el parpado tapa el ojo entero
    # con holgura, blanco e iris incluidos, y no se cuela la pupila por el borde.
    # EL OJO SON DOS MITADES, Y CADA UNA ES SU PARPADO.
    #
    # Cada mitad va clavada por el LADO DEL CENTRO, no por el de fuera. Al aplastarse, las dos se
    # recogen HACIA EL MEDIO y se juntan ahi: el blanco se va comiendo desde arriba y desde abajo a
    # la vez hasta quedar en una raya, y luego nada. Clavadas por fuera hacia el centro (que fue el
    # primer intento) pasaba lo contrario: el ojo se vaciaba por el medio y parecia que solo se
    # movia un parpado.
    #
    # Por eso la mitad de arriba crece hacia arriba (0, +1) desde su anclaje, y la de abajo hacia
    # abajo (0, -1): las dos se alejan del centro, que es su eje.
    ojo_l_arr = Cuerpo()
    ojo_l_arr.caja(0, 1, 0, 1, 0, 0, OJO)
    ojo_l_arr.caja(2, 2, 0, 1, 0, 0, IRIS)
    b["eye_l_up"] = ojo_l_arr
    ojo_l_aba = Cuerpo()
    ojo_l_aba.caja(0, 1, -1, 0, 0, 0, OJO)
    ojo_l_aba.caja(2, 2, -1, 0, 0, 0, IRIS)
    b["eye_l_dn"] = ojo_l_aba
    ojo_r_arr = Cuerpo()
    ojo_r_arr.caja(1, 2, 0, 1, 0, 0, OJO)
    ojo_r_arr.caja(0, 0, 0, 1, 0, 0, IRIS)
    b["eye_r_up"] = ojo_r_arr
    ojo_r_aba = Cuerpo()
    ojo_r_aba.caja(1, 2, -1, 0, 0, 0, OJO)
    ojo_r_aba.caja(0, 0, -1, 0, 0, 0, IRIS)
    b["eye_r_dn"] = ojo_r_aba

    # ---------------- capucha / cuello alto ----------------
    hd = Cuerpo()
    hd.caja(-6, 5, -4, 4, -4, 4, OLIVA)
    hd.caja(-6, 5, 2, 4, -4, 4, CLARO)
    hd.quitar(-3, 2, -4, 4, -4, -2)                    # hueco por delante, para la cara
    b["hood"] = hd

    n = Cuerpo()
    n.caja(-2, 1, -4, 2, -2, 1, NEGRO)                 # cuello del pasamontanas
    b["neck"] = n

    # ---------------- torso: chaleco con placas y cargadores ----------------
    c = Cuerpo()
    c.caja(-6, 5, -8, 6, -4, 4, OLIVA)                 # uniforme
    c.caja(-6, 5, 3, 6, -4, 4, CLARO)                  # pecho alto mas claro
    c.caja(-6, -5, -8, 6, -4, 4, SOMBRA)               # costados en sombra
    c.caja(4, 5, -8, 6, -4, 4, SOMBRA)
    c.caja(-5, 4, -7, 5, -6, -4, NEGRO)                # placa delantera del chaleco
    c.caja(-5, 4, -7, 5, 4, 6, NEGRO)                  # placa trasera
    c.caja(-5, 4, 5, 5, -6, 6, CAQUI)                  # hombreras del chaleco
    c.caja(-2, 1, -8, 6, -6, -5, HONDO)                # cremallera central
    for i, x in enumerate((-4, -1, 2)):                # tres cargadores en el pecho
        c.caja(x, x + 1, -6, -2, -7, -6, CAQUI)
        c.caja(x, x + 1, -2, -2, -7, -6, METAL)
    c.caja(-5, -4, 0, 3, -7, -6, ARENA)                # bolsillo de radio
    c.caja(3, 4, 0, 3, -7, -6, ARENA)                  # bolsillo de utiles
    c.caja(2, 4, 4, 5, -7, -6, ROJO)                   # parche
    c.caja(-6, 5, -1, 0, -6, 6, CAQUI)                 # cincha horizontal
    b["chest"] = c

    s = Cuerpo()
    s.caja(-6, 5, -4, 4, -4, 4, OLIVA)                 # abdomen
    s.caja(-6, -5, -4, 4, -4, 4, SOMBRA)
    s.caja(4, 5, -4, 4, -4, 4, SOMBRA)
    s.caja(-6, 5, -4, -2, -5, 5, CAQUI)                # cinturon
    s.caja(-1, 0, -4, -2, -6, -5, METAL)               # hebilla
    s.caja(-6, -5, -1, 2, -6, -4, ARENA)               # cantimplora
    b["stomach"] = s

    p = Cuerpo()
    p.caja(-6, 5, -4, 4, -4, 2, OLIVA)                 # cadera
    p.caja(-6, 5, 2, 4, -4, 2, CAQUI)                  # parte del cinturon
    p.caja(-1, 0, -4, 1, -4, -3, SOMBRA)               # costura de la entrepierna
    p.caja(-6, -5, -3, 1, -5, -3, CAQUI)               # funda de pistola en el muslo
    p.caja(-6, -5, -3, -1, -5, -3, NEGRO)
    b["pelvis"] = p

    # ---------------- brazos ----------------
    sh = Cuerpo()
    sh.caja(-2, 3, -3, 3, -3, 3, OLIVA)                # hombro
    sh.caja(-2, 3, 1, 3, -3, 3, CAQUI)                 # hombrera
    sh.caja(-2, 3, -1, 0, -3, -2, ROJO)                # galon
    b["shoulder_l"] = sh
    b["shoulder_r"] = sh.espejo_x()

    au = Cuerpo()
    au.caja(-6, 8, -3, 1, -3, 1, OLIVA)                # biceps
    au.caja(-6, 8, 0, 1, -3, 1, CLARO)
    au.caja(-2, 1, -3, 1, -4, -3, CAQUI)               # cincha del brazo
    b["arm_upper_l"] = au
    b["arm_upper_r"] = au.espejo_x()

    al = Cuerpo()
    al.caja(-4, 7, -3, 1, -3, 1, OLIVA)                # antebrazo
    al.caja(4, 7, -3, 1, -3, 1, NEGRO)                 # codera / punos
    b["arm_lower_l"] = al
    b["arm_lower_r"] = al.espejo_x()

    m = Cuerpo()
    m.caja(-2, 3, -3, 1, -3, 2, NEGRO)                 # guante
    m.caja(-2, 3, -3, -2, -3, 2, HONDO)                # palma
    b["hand_l"] = m
    b["hand_r"] = m.espejo_x()

    # ---------------- piernas ----------------
    lu = Cuerpo()
    lu.caja(-3, 3, -8, 8, -3, 3, OLIVA)                # muslo
    lu.caja(-3, 3, 5, 8, -3, 3, SOMBRA)                # arriba, pegado a la cadera
    lu.caja(-3, 3, -3, 1, -4, -3, CAQUI)               # bolsillo de pierna
    lu.caja(-3, 3, -8, -6, -3, 3, NEGRO)               # rodillera
    b["leg_upper_l"] = lu
    b["leg_upper_r"] = lu.espejo_x()

    ll = Cuerpo()
    ll.caja(-3, 2, -8, 7, -3, 3, OLIVA)                # pantorrilla
    ll.caja(-3, 2, -8, -3, -3, 3, CUERO)               # cana de la bota
    ll.caja(-3, 2, -5, -4, -4, 3, HONDO)               # cordones
    b["leg_lower_l"] = ll
    b["leg_lower_r"] = ll.espejo_x()

    f = Cuerpo()
    f.caja(-3, 1, -3, 1, -5, 3, CUERO)                 # bota
    f.caja(-3, 1, -3, -2, -5, 3, HONDO)                # suela
    b["foot_l"] = f
    b["foot_r"] = f.espejo_x()

    t = Cuerpo()
    t.caja(-3, 1, -1, 1, -3, 1, CUERO)                 # puntera
    t.caja(-3, 1, -1, -1, -3, 1, HONDO)
    b["toes_l"] = t
    b["toes_r"] = t.espejo_x()

    # ---------------- radio del cinturon ----------------
    r = Cuerpo()
    r.caja(-1, 1, -6, 4, -1, 2, NEGRO)
    r.caja(-1, 1, 4, 4, -1, 2, METAL)                  # antena
    b["radio"] = r
    rl = Cuerpo()
    rl.caja(-1, 0, -1, 0, -1, 0, ROJO)                 # piloto
    b["radio_light"] = rl
    return b



# ===========================================================================
# PIEZAS INTERCAMBIABLES. Cada avatar del armario no es un modelo nuevo: es el MISMO soldado con
# piezas puestas o quitadas. Eso es lo que permite que todos conserven el esqueleto, las
# animaciones y -lo importante- los cuatro huesos de parpado: la animacion del ojo funciona igual
# lleven casco integral, capucha o nada.
#
# Cada pieza dice:
#   "quita" -> colores del soldado base que borra (por su hueco entre los 19, no por su indice
#              absoluto: asi sigue cuadrando si manana la paleta crece)
#   "vox"   -> voxels que anade, por hueso, en las mismas coordenadas que ese hueso
#
# REGLA QUE NO SE PUEDE ROMPER: nada tapa la franja de los ojos (filas y 0..4 en z -6 y por
# delante). Un casco que cubra eso deja al avatar sin mirada y la animacion del ojo se pierde.
# ===========================================================================

def piezas(C):
    OLIVA, SOMBRA, CLARO, CAQUI = C + 0, C + 1, C + 2, C + 3
    NEGRO, HONDO, CASCO, CASCO_A = C + 4, C + 5, C + 6, C + 7
    CUERO, PIEL, PIEL_S, CRISTAL = C + 8, C + 9, C + 10, C + 11
    BRILLO, METAL, ROJO, ARENA = C + 12, C + 13, C + 14, C + 15
    P = {}

    # --- CASCO INTEGRAL: cubre craneo, nuca y mandibula, con una franja abierta a la altura de
    # los ojos. Es el "pro" de verdad: de frente solo se le ve la mirada.
    ci = Cuerpo()
    ci.caja(-6, 5, 1, 9, -8, 6, CASCO)                 # bola del casco
    ci.caja(-6, 5, 7, 9, -8, 6, CASCO_A)               # coronilla, mas clara
    ci.caja(-6, 5, -7, 2, -8, 6, CASCO)                # carrilleras y nuca, hasta la barbilla
    ci.caja(-6, 5, -7, -5, -8, 6, HONDO)               # barboquejo
    ci.caja(-6, 5, 5, 6, -10, -8, CASCO_A)             # visera corta
    ci.quitar(-4, 3, 0, 4, -10, -6)                    # LA FRANJA DE LOS OJOS, abierta
    ci.caja(-4, 3, 5, 5, -9, -9, HONDO)                # travesano, POR ENCIMA de las cejas
    P["casco_integral"] = {"quita": [6, 7, 11, 12], "vox": {"head": ci.lista()}}

    # --- CASCO DE COMBATE CERRADO CON RESPIRADOR: como el anterior pero con filtro en la boca.
    cr = Cuerpo()
    cr.caja(-6, 5, 1, 9, -8, 6, CASCO)
    cr.caja(-6, 5, 7, 9, -8, 6, CASCO_A)
    cr.caja(-6, 5, -7, 2, -8, 6, CASCO)
    cr.quitar(-4, 3, 0, 4, -10, -6)
    cr.caja(-3, 2, -6, -2, -10, -8, HONDO)             # mascarilla
    cr.caja(-2, 1, -5, -3, -11, -10, METAL)            # filtro
    cr.caja(-6, -5, -4, -1, -9, -7, HONDO)             # mangueras
    cr.caja(4, 5, -4, -1, -9, -7, HONDO)
    P["casco_respirador"] = {"quita": [6, 7, 11, 12], "vox": {"head": cr.lista()}}

    # --- CASCO DE OBRA: media naranja con ala, para los avatares de calle.
    co = Cuerpo()
    co.caja(-5, 4, 5, 9, -7, 5, CASCO_A)
    co.caja(-6, 5, 5, 6, -9, 6, CASCO)                 # ala alrededor, sin bajar a las cejas
    co.caja(-1, 0, 7, 9, -7, 5, CASCO)                 # nervio central
    P["casco_obra"] = {"quita": [6, 7, 11, 12], "vox": {"head": co.lista()}}

    # --- GORRA: visera al frente, nada mas.
    g = Cuerpo()
    g.caja(-4, 3, 5, 8, -6, 4, CASCO)
    g.caja(-4, 3, 5, 6, -9, -6, CASCO_A)               # visera, por encima de las cejas
    g.caja(-4, 3, 8, 8, -6, 4, CASCO_A)
    P["gorra"] = {"quita": [6, 7, 11, 12], "vox": {"head": g.lista()}}

    # --- CAPUCHA SUBIDA: cascara alrededor de la cabeza con la cara al aire.
    cp = Cuerpo()
    cp.caja(-6, 5, -4, 9, -8, 7, OLIVA)
    cp.caja(-6, 5, 7, 9, -8, 7, CLARO)
    cp.quitar(-4, 3, -4, 6, -10, -5)                   # el hueco de la cara
    cp.caja(-6, 5, -4, -2, -8, 7, SOMBRA)              # el borde, en sombra
    P["capucha"] = {"quita": [6, 7, 11, 12], "vox": {"head": cp.lista()}}

    # --- BOINA: ladeada, para los de tierra.
    bo = Cuerpo()
    bo.caja(-4, 3, 4, 6, -5, 4, CASCO)
    bo.caja(-5, 0, 6, 7, -5, 2, CASCO)                 # la caida hacia un lado
    bo.caja(2, 3, 5, 6, -6, -5, ROJO)                  # el escudo
    P["boina"] = {"quita": [6, 7, 11, 12], "vox": {"head": bo.lista()}}

    # --- PELO: para los que no llevan nada en la cabeza.
    pe = Cuerpo()
    pe.caja(-4, 3, 5, 8, -6, 4, HONDO)
    pe.caja(-5, 4, 2, 7, 2, 5, HONDO)                  # la nuca
    P["pelo"] = {"quita": [6, 7, 11, 12], "vox": {"head": pe.lista()}}

    # --- PANUELO EN LA CARA: tapa nariz y boca, nunca los ojos.
    pa = Cuerpo()
    pa.caja(-5, 4, -6, -1, -7, 4, CAQUI)
    pa.caja(-5, 4, -6, -5, -7, 4, SOMBRA)
    P["panuelo"] = {"quita": [], "vox": {"head": pa.lista()}}

    # --- MOCHILA: el bulto a la espalda mas las correas por delante.
    mo = Cuerpo()
    mo.caja(-4, 3, -6, 5, 4, 9, OLIVA)                 # el saco
    mo.caja(-4, 3, 3, 5, 4, 9, CLARO)                  # la tapa
    mo.caja(-4, 3, -6, -4, 4, 9, SOMBRA)               # el fondo
    mo.caja(-1, 0, -6, 5, 9, 10, CAQUI)                # cincha vertical
    mo.caja(-4, 3, -1, 0, 9, 10, CAQUI)                # cincha horizontal
    mo.caja(-5, -3, -2, 6, -6, -4, CAQUI)              # tirante izquierdo, por delante
    mo.caja(2, 4, -2, 6, -6, -4, CAQUI)                # tirante derecho
    P["mochila"] = {"quita": [], "vox": {"chest": mo.lista()}}

    # --- MOCHILA GRANDE con saco de dormir: para los de patrulla larga.
    mg = Cuerpo()
    mg.caja(-5, 4, -8, 6, 4, 11, OLIVA)
    mg.caja(-5, 4, 4, 6, 4, 11, CLARO)
    mg.caja(-5, 4, -8, -6, 4, 11, ARENA)               # el saco de dormir enrollado abajo
    mg.caja(-1, 0, -8, 6, 11, 12, CAQUI)
    mg.caja(-5, -3, -2, 6, -6, -4, CAQUI)
    mg.caja(2, 4, -2, 6, -6, -4, CAQUI)
    P["mochila_grande"] = {"quita": [], "vox": {"chest": mg.lista()}}

    # --- BANDOLERA: correa cruzada del hombro a la cadera.
    ba = Cuerpo()
    for i in range(12):
        y = 5 - i
        x = -5 + i // 2
        ba.caja(x, x + 1, y, y, -7, -5, CUERO)
        if i % 3 == 0:
            ba.caja(x, x + 1, y, y, -8, -7, METAL)     # las anillas
    P["bandolera"] = {"quita": [], "vox": {"chest": ba.lista()}}

    # --- CHALECO PESADO: placas mas gordas por delante y por detras.
    ch = Cuerpo()
    ch.caja(-6, 5, -8, 6, -7, -5, NEGRO)
    ch.caja(-6, 5, -8, 6, 5, 7, NEGRO)
    ch.caja(-6, 5, 4, 6, -7, 7, HONDO)                 # hombreras gruesas
    ch.caja(-2, 1, -8, 6, -8, -7, HONDO)               # canal central
    ch.caja(-6, -5, -6, 2, -8, -7, ARENA)              # petacas laterales
    ch.caja(4, 5, -6, 2, -8, -7, ARENA)
    P["chaleco_pesado"] = {"quita": [], "vox": {"chest": ch.lista()}}

    # --- CHAQUETA DE CALLE: sin placas, con cuello y cremallera. Para los avatares no militares.
    cc = Cuerpo()
    cc.caja(-6, 5, -8, 6, -6, 6, OLIVA)
    cc.caja(-6, 5, 5, 7, -6, 6, CLARO)                 # cuello levantado
    cc.caja(-1, 0, -8, 5, -7, -6, METAL)               # cremallera
    cc.caja(-6, -4, -6, -2, -7, -6, SOMBRA)            # bolsillos
    cc.caja(3, 5, -6, -2, -7, -6, SOMBRA)
    P["chaqueta"] = {"quita": [4, 5, 14, 15], "vox": {"chest": cc.lista()}}

    # --- DELANTAL DE HERRERO: cuero de arriba abajo.
    de = Cuerpo()
    de.caja(-5, 4, -8, 5, -7, -5, CUERO)
    de.caja(-5, 4, 4, 5, -7, -5, HONDO)
    de.caja(-5, -4, -2, 5, -7, -6, HONDO)              # tirantes
    de.caja(3, 4, -2, 5, -7, -6, HONDO)
    P["delantal"] = {"quita": [4, 5], "vox": {"chest": de.lista()}}

    # --- RODILLERAS Y ESPINILLERAS.
    ro = Cuerpo()
    ro.caja(-4, 3, 3, 7, -5, -3, NEGRO)
    ro.caja(-4, 3, 4, 6, -6, -5, HONDO)
    es = Cuerpo()
    es.caja(-4, 3, -2, 6, -5, -3, NEGRO)
    P["rodilleras"] = {"quita": [], "vox": {
        "leg_lower_l": ro.lista(), "leg_lower_r": ro.espejo_x().lista(),
        "leg_upper_l": es.lista(), "leg_upper_r": es.espejo_x().lista()}}

    # --- PANTALON CORTO: se le quita la caña de la bota y queda la pierna al aire.
    pc = Cuerpo()
    pc.caja(-3, 2, 2, 7, -3, 3, PIEL)
    pc.caja(-3, 2, 2, 3, -3, 3, PIEL_S)
    P["pierna_desnuda"] = {"quita": [8], "vox": {
        "leg_lower_l": pc.lista(), "leg_lower_r": pc.espejo_x().lista()}}

    PODRE, PODRE_S, RESECA, HUESO = C + 19, C + 20, C + 21, C + 22
    SANGRE, SANGRE_V, CARNE, LATON = C + 23, C + 24, C + 25, C + 26

    # =======================================================================
    # INFECTADOS. La cara NO se rehace entera: se le pegan parches de carne podrida, heridas y
    # hueso a la vista, y se le hunden las mejillas. Los ojos y las cejas se quedan donde estan,
    # asi que estos tambien entornan el ojo al apuntar; de hecho es lo que mas miedo da de ellos.
    # =======================================================================
    # Ayuda suelta para abrir huecos sin tener un Cuerpo delante.
    def hueco(x0, x1, y0, y1, z0, z1):
        return [[x, y, z] for x in range(x0, x1 + 1)
                for y in range(y0, y1 + 1) for z in range(z0, z1 + 1)]

    def herida(cu, x0, x1, y0, y1, z0, z1):
        """UNA HERIDA COMPLETA, en tres pasos:
          1) se abre el agujero (se borra la carne)
          2) se pintan sus PAREDES de rojo casi negro, dejando el centro libre
          3) un labio de carne viva por fuera, alrededor de la boca
        Las paredes oscuras son lo que hace que el hueso del fondo se lea: con las paredes del
        mismo verde que la piel, el agujero parecia una mancha y no se distinguia nada dentro."""
        h = hueco(x0, x1, y0, y1, z0, z1)
        cu.marco(x0, x1, y0, y1, z0, z1, SANGRE_V)
        cu.marco(x0 - 1, x1 + 1, y0 - 1, y1 + 1, z0, z0, SANGRE_V)
        return h

    def espejo_h(hs):
        return [[-h[0] - 1, h[1], h[2]] for h in hs]

    # --- EL INFECTADO. Las heridas van PINTADAS sobre la piel, no excavadas: a este tamano se leen
    # mejor asi. Se probo la version con agujeros de verdad y esqueleto dentro y, en un muneco de 68
    # voxeles de alto, el torso salia un pozo oscuro donde no se distinguia nada.
    zc = Cuerpo()
    zc.caja(-4, 3, -6, 6, -6, 4, PODRE)                # toda la piel, verdosa
    zc.caja(-4, 3, -6, -3, -6, 4, PODRE_S)             # menton en sombra
    zc.caja(-5, -4, -2, 3, -5, 3, PODRE_S)             # sienes hundidas
    zc.caja(3, 4, -2, 3, -5, 3, PODRE_S)
    zc.caja(-4, -2, -2, -1, -7, -6, CARNE)             # desgarro en la mejilla izquierda
    zc.caja(-4, -3, -2, -1, -7, -7, SANGRE)
    zc.caja(1, 3, -3, -2, -7, -6, HUESO)               # pomulo derecho al aire, bajo el ojo
    zc.caja(2, 3, -3, -3, -8, -7, HUESO)
    zc.caja(-2, 1, -5, -4, -7, -6, SANGRE_V)           # boca abierta, negra
    zc.caja(-2, 1, -5, -5, -8, -7, HUESO)              # dientes
    zc.caja(-4, -1, 5, 6, -7, -6, SANGRE)              # regueros por la frente, sobre las cejas
    zc.caja(1, 2, 5, 6, -7, -6, SANGRE)
    zc.caja(-5, -5, 0, 4, -7, -6, SANGRE)              # y uno que baja por el lado de la cara
    zc.caja(-5, 4, 4, 5, 2, 5, RESECA)                 # nuca pelada
    P["zombie_cara"] = {"quita": [6, 7, 11, 12], "vox": {"head": zc.lista()}}

    # putrefacto: ademas le falta un trozo de craneo y se le ve el hueso
    zp = Cuerpo()
    zp.v.update(zc.v)
    zp.caja(-4, 0, 4, 7, -6, 4, HUESO)                 # media coronilla al descubierto
    zp.caja(-4, 0, 5, 5, -7, -6, SANGRE_V)             # el borde del desgarro
    zp.caja(1, 3, 4, 6, -6, 3, RESECA)                 # mechones resecos al otro lado
    zp.caja(-5, -4, -6, -3, -5, 2, HUESO)              # mandibula izquierda sin carne
    zp.caja(-5, -4, -6, -5, -6, 2, SANGRE_V)
    P["zombie_cara_2"] = {"quita": [6, 7, 11, 12], "vox": {"head": zp.lista()}}

    # torso: el uniforme desgarrado, con las costillas asomando
    zt = Cuerpo()
    zt.caja(-5, 4, -3, 3, -7, -5, SANGRE)              # manchon central
    zt.caja(-4, 1, -1, 2, -8, -6, HUESO)               # costillas
    for y in (-1, 1, 3):
        zt.caja(-4, 1, y, y, -8, -7, SANGRE_V)         # los huecos entre costilla y costilla
    zt.caja(-6, -4, -6, 0, -7, -5, PODRE)              # carne del costado
    zt.caja(-6, -4, -6, -5, -7, -5, SANGRE_V)
    zt.caja(2, 4, 2, 5, -7, -5, SANGRE)                # salpicadura en el hombro
    zt.caja(-6, 5, -8, -7, -6, 5, SANGRE_V)            # el bajo, empapado
    P["zombie_torso"] = {"quita": [], "vox": {"chest": zt.lista()}}

    # brazos: manga rota y antebrazo en carne viva
    zb = Cuerpo()
    zb.caja(-3, 3, -6, 2, -3, 3, PODRE)
    zb.caja(-3, 3, -6, -4, -4, 3, HUESO)               # el hueso asomando por la muneca
    zb.caja(-3, 3, 0, 1, -4, -3, SANGRE)
    zh = Cuerpo()
    zh.caja(-2, 3, -3, 3, -3, 3, PODRE)
    zh.caja(-2, 3, -1, 0, -4, -2, SANGRE)
    P["zombie_brazos"] = {"quita": [], "vox": {
        "arm_lower_l": zb.lista(), "arm_lower_r": zb.espejo_x().lista(),
        "hand_l": zh.lista(), "hand_r": zh.espejo_x().lista()}}

    # piernas: perneras rotas y carne a la vista
    zl = Cuerpo()
    zl.caja(-3, 2, 0, 5, -3, 3, PODRE)
    zl.caja(-3, 2, 3, 4, -4, -3, SANGRE)
    zl.caja(-3, 2, 0, 1, -4, -3, HUESO)
    P["zombie_piernas"] = {"quita": [], "vox": {
        "leg_lower_l": zl.lista(), "leg_lower_r": zl.espejo_x().lista()}}

    # =======================================================================
    # EL ESQUELETO DE VERDAD. Va METIDO DENTRO del cuerpo, hueso por hueso y cada uno colgando del
    # hueso del rig que le toca: la caja toracica en el pecho, el humero en el brazo de arriba, el
    # cubito y el radio en el antebrazo, el femur en el muslo, la tibia y el perone en la pantorilla.
    # Mientras haya carne encima NO SE VE NI CUESTA NADA: el mallado tapa las caras que tienen un
    # voxel al lado, asi que un hueso rodeado de carne no genera un solo triangulo.
    # En cuanto una herida se lleva la carne de encima, aparece EL HUESO QUE HAY DEBAJO, y se mueve
    # con el personaje porque es el hueso de su propio esqueleto, no un dibujo pegado.
    # =======================================================================
    cr2 = Cuerpo()                                     # craneo, dentro de la cabeza
    cr2.caja(-4, 3, -4, 6, -5, 3, HUESO)
    cr2.caja(-3, 2, -6, -4, -4, 3, HUESO)              # mandibula
    tx = Cuerpo()                                      # caja toracica
    for y in (-6, -4, -2, 0, 2, 4):                    # seis costillas, con su hueco entre ellas
        tx.caja(-5, 4, y, y, -4, 4, HUESO)
    tx.caja(-1, 0, -8, 6, 1, 3, HUESO)                 # columna, pegada a la espalda
    tx.caja(-2, 1, 3, 5, -3, -1, HUESO)                # esternon
    ab = Cuerpo()                                      # lumbares
    ab.caja(-1, 0, -4, 4, 1, 3, HUESO)
    pl = Cuerpo()                                      # pelvis
    pl.caja(-4, 3, 0, 3, -2, 2, HUESO)
    pl.caja(-1, 0, -4, 0, -1, 2, HUESO)                # sacro
    ho = Cuerpo()                                      # cabeza del humero
    ho.caja(-1, 2, -1, 2, -1, 2, HUESO)
    hu = Cuerpo()                                      # humero
    hu.caja(-2, 2, -5, 4, -2, 1, HUESO)
    an = Cuerpo()                                      # cubito y radio, dos huesos separados
    an.caja(-3, -2, -5, 1, -2, 1, HUESO)
    an.caja(1, 2, -5, 1, -2, 1, HUESO)
    ma = Cuerpo()                                      # metacarpos
    ma.caja(-1, 2, -1, 1, -1, 1, HUESO)
    fe = Cuerpo()                                      # femur
    fe.caja(-1, 1, -7, 7, -1, 1, HUESO)
    ti = Cuerpo()                                      # tibia y perone
    ti.caja(-2, 1, -7, 6, -2, 1, HUESO)                # tibia, ancha: es la que se ve bajo la piel
    ti.caja(2, 2, -6, 5, -1, 1, HUESO)                 # perone
    pi = Cuerpo()                                      # tarso
    pi.caja(-2, 0, -2, 0, -3, 1, HUESO)
    P["esqueleto"] = {"quita": [], "vox": {
        "head": cr2.lista(), "chest": tx.lista(), "stomach": ab.lista(), "pelvis": pl.lista(),
        "shoulder_l": ho.lista(), "shoulder_r": ho.espejo_x().lista(),
        "arm_upper_l": hu.lista(), "arm_upper_r": hu.espejo_x().lista(),
        "arm_lower_l": an.lista(), "arm_lower_r": an.espejo_x().lista(),
        "hand_l": ma.lista(), "hand_r": ma.espejo_x().lista(),
        "leg_upper_l": fe.lista(), "leg_upper_r": fe.espejo_x().lista(),
        "leg_lower_l": ti.lista(), "leg_lower_r": ti.espejo_x().lista(),
        "foot_l": pi.lista(), "foot_r": pi.espejo_x().lista()}}

    # =======================================================================
    # ACCESORIOS. Se ponen ENCIMA de lo que ya lleves, sin quitar nada, y se pueden combinar:
    # una mochila, un llavero colgando de ella, una gorra y unos aritos a la vez.
    # =======================================================================

    # --- mochilas ---
    mt = Cuerpo()
    mt.caja(-4, 3, -5, 4, 4, 8, NEGRO)                 # cuerpo de la mochila tactica
    mt.caja(-4, 3, 2, 4, 4, 8, HONDO)
    mt.caja(-4, 3, -5, -4, 4, 8, HONDO)
    for y in (-3, 0, 3):                               # filas de cinchas molle
        mt.caja(-4, 3, y, y, 8, 9, CAQUI)
    mt.caja(-1, 0, -5, 4, 8, 9, HONDO)
    mt.caja(-5, -3, -2, 6, -6, -4, NEGRO)
    mt.caja(2, 4, -2, 6, -6, -4, NEGRO)
    P["mochila_tactica"] = {"quita": [], "vox": {"chest": mt.lista()}}

    mc = Cuerpo()
    mc.caja(-4, 3, -4, 4, 4, 7, ARENA)                 # mochila de calle, redonda y blanda
    mc.caja(-4, 3, 3, 4, 4, 7, CLARO)
    mc.caja(-3, 2, -2, 1, 7, 8, CAQUI)                 # bolsillo delantero
    mc.caja(-1, 0, -2, 1, 8, 8, METAL)                 # cremallera del bolsillo
    mc.caja(-5, -3, -2, 6, -6, -4, ARENA)
    mc.caja(2, 4, -2, 6, -6, -4, ARENA)
    P["mochila_calle"] = {"quita": [], "vox": {"chest": mc.lista()}}

    mr = Cuerpo()
    mr.caja(-5, 4, -1, 3, 4, 8, CAQUI)                 # petate enrollado, atravesado
    mr.caja(-5, 4, -1, 3, 8, 8, ARENA)
    for x in (-4, -1, 2):
        mr.caja(x, x + 1, -1, 3, 4, 9, CUERO)          # correas
    P["petate"] = {"quita": [], "vox": {"chest": mr.lista()}}

    mp = Cuerpo()
    mp.caja(-5, 4, -7, 5, 4, 10, CLARO)                # funda de paracaidas, muy voluminosa
    mp.caja(-5, 4, 4, 5, 4, 10, ARENA)
    mp.caja(-5, 4, -7, -6, 4, 10, ARENA)
    mp.caja(-1, 0, -7, 5, 10, 11, CAQUI)
    mp.caja(-3, 2, 2, 3, 10, 11, METAL)                # la anilla
    mp.caja(-5, -3, -2, 6, -6, -4, CAQUI)
    mp.caja(2, 4, -2, 6, -6, -4, CAQUI)
    P["paracaidas"] = {"quita": [], "vox": {"chest": mp.lista()}}

    # --- LLAVEROS. Se dibujan COLGANDO DEL ORIGEN, hacia abajo: el juego los engancha luego en la
    # esquina de abajo de la mochila que lleves puesta, sea la que sea, y ahi se balancean.
    lc = Cuerpo()
    lc.caja(0, 0, -3, 0, 0, 0, LATON)                  # la cadenita
    lc.caja(-1, 1, -6, -4, -1, 1, HUESO)               # la calavera
    lc.caja(-1, -1, -5, -5, -2, -2, SANGRE_V)          # las cuencas
    lc.caja(1, 1, -5, -5, -2, -2, SANGRE_V)
    lc.caja(-1, 1, -7, -7, -1, 0, HUESO)               # la mandibula
    P["llavero_calavera"] = {"quita": [], "vox": {"chest": lc.lista()}}

    ld = Cuerpo()
    ld.caja(0, 0, -3, 0, 0, 0, LATON)
    ld.caja(-1, 1, -6, -4, -1, 1, ARENA)               # el dado
    ld.caja(0, 0, -5, -5, -2, -2, HONDO)               # los puntos
    ld.caja(-1, -1, -6, -6, -1, -1, HONDO)
    ld.caja(1, 1, -4, -4, -1, -1, HONDO)
    P["llavero_dado"] = {"quita": [], "vox": {"chest": ld.lista()}}

    lp = Cuerpo()
    lp.caja(0, 0, -3, 0, 0, 0, LATON)
    lp.caja(-1, 1, -7, -4, 0, 0, METAL)                # la chapa, colgando de canto
    lp.caja(-1, 1, -6, -5, -1, -1, HONDO)              # las letras grabadas
    P["llavero_chapa"] = {"quita": [], "vox": {"chest": lp.lista()}}

    # --- gorras y cabeza ---
    ga = Cuerpo()
    ga.caja(-4, 3, 5, 8, -6, 4, CASCO)                 # gorra del reves
    ga.caja(-4, 3, 5, 6, 4, 7, CASCO_A)                # la visera, detras
    ga.caja(-4, 3, 5, 5, -7, -6, HONDO)                # la trabilla, delante
    P["gorra_reves"] = {"quita": [6, 7, 11, 12], "vox": {"head": ga.lista()}}

    so = Cuerpo()
    so.caja(-4, 3, 5, 8, -6, 4, CUERO)                 # copa
    so.caja(-7, 6, 5, 6, -10, 8, CUERO)                # ala ancha alrededor
    so.caja(-4, 3, 6, 6, -7, 5, HONDO)                 # cinta
    P["sombrero"] = {"quita": [6, 7, 11, 12], "vox": {"head": so.lista()}}

    bn = Cuerpo()
    bn.caja(-5, 4, 5, 7, -7, 5, CAQUI)                 # banda en la frente, sobre las cejas
    bn.caja(-5, 4, 5, 7, -7, -6, SANGRE)               # con la mancha delante
    bn.caja(4, 5, 5, 6, 3, 7, CAQUI)                   # los cabos, colgando
    P["banda"] = {"quita": [6, 7, 11, 12], "vox": {"head": bn.lista()}}

    # --- aritos: dos chispas de laton en las orejas ---
    ar = Cuerpo()
    ar.caja(-6, -6, -3, -1, -1, 1, LATON)
    ar.caja(-6, -6, -3, -3, 0, 0, LATON)
    ar.caja(5, 5, -3, -1, -1, 1, LATON)
    ar.caja(5, 5, -3, -3, 0, 0, LATON)
    P["aritos"] = {"quita": [], "vox": {"head": ar.lista()}}

    au = Cuerpo()
    au.caja(-6, -6, -4, 0, -2, 2, LATON)               # aro grande, solo el izquierdo
    au.caja(-7, -7, -3, -1, -1, 1, LATON)
    P["aro_grande"] = {"quita": [], "vox": {"head": au.lista()}}

    # --- pantalones ---
    pg = Cuerpo()
    pg.caja(-4, 3, -6, 4, -5, -3, CAQUI)               # bolsillos cargo enormes
    pg.caja(-4, 3, -6, 4, 3, 5, CAQUI)
    pg.caja(-4, 3, -1, 0, -6, -5, HONDO)               # solapas
    pg.caja(-4, 3, -1, 0, 5, 6, HONDO)
    P["pantalon_cargo"] = {"quita": [], "vox": {
        "leg_upper_l": pg.lista(), "leg_upper_r": pg.espejo_x().lista()}}

    pv = Cuerpo()
    pv.caja(-4, 3, -8, 8, -4, 4, OLIVA)                # pernera ancha, de vaquero
    pv.caja(-4, 3, -8, -6, -4, 4, CLARO)               # la vuelta del bajo
    pv.caja(-4, 3, 2, 3, -5, -4, METAL)                # remaches
    P["pantalon_ancho"] = {"quita": [], "vox": {
        "leg_upper_l": pv.lista(), "leg_upper_r": pv.espejo_x().lista()}}

    pt = Cuerpo()
    pt.caja(-4, 3, -8, 8, -4, 4, NEGRO)                # pernera tactica con refuerzos
    pt.caja(-4, 3, -8, -5, -5, 4, HONDO)
    pt.caja(-4, 3, 1, 4, -5, -4, CAQUI)
    pt.caja(-5, -4, -4, 2, -5, -3, HONDO)              # funda lateral
    P["pantalon_tactico"] = {"quita": [], "vox": {
        "leg_upper_l": pt.lista(), "leg_upper_r": pt.espejo_x().lista()}}

    piezas_heraldo(C, P)
    return P


def piezas_heraldo(C, P):
    """EL HERALDO DE CENIZA: guerrero calcinado, en voxels como el resto del avatar.

    EN VOXELS Y CUADRADO A PROPOSITO. Se probo con malla curva (elipsoides fundidos, el taller de las
    criaturas) y quedaba fuera de sitio: el jugador es voxel, el mundo es voxel, y una figura lisa al
    lado de una pared de cubos canta. Lo que hace que un avatar parezca DE ESTE JUEGO es justo el
    cubo.

    Las piezas se cuelgan de los huesos que ya existen, asi que las animaciones, la cinematica inversa
    y las poses del arma valen sin tocar nada.
    """
    CENIZA, CEN_S, CEN_C = C + 27, C + 28, C + 29
    BRASA_H, BRASA, BRASA_V = C + 30, C + 31, C + 32
    HIERRO, HIERRO_C, CUERO_N = C + 33, C + 34, C + 35
    HUESO, HUESO_S = C + 36, C + 37
    OJO, OJO_V = C + 38, C + 39

    # --- YELMO-CALAVERA CON CUERNOS --------------------------------------------------------------
    # Hierro por arriba, calavera por delante. Los ojos son brasa METIDA EN EL HUECO, no pintada
    # encima: asi tienen fondo y se leen como luz y no como dos puntos.
    h = Cuerpo()
    h.caja(-6, 5, 1, 9, -8, 6, HIERRO)                 # yelmo
    h.caja(-6, 5, 8, 10, -8, 6, HIERRO_C)              # coronilla pulida
    h.caja(-1, 0, 8, 11, -9, 6, HIERRO_C)              # cresta central
    h.caja(-6, 5, 4, 5, -11, -8, HIERRO_C)             # visera sobre las cuencas
    # DETALLE DEL YELMO. No se puede subir la resolucion -todas las piezas comparten la rejilla del
    # avatar, 2,57 cm, y se guardan como coordenadas enteras-, asi que el detalle sale de APROVECHARLA:
    # nervios, cantos y placas de un voxel de grosor alternando los dos tonos de hierro. A esta escala
    # un voxel claro junto a uno oscuro se lee como un filo.
    for x in (-5, -3, 2, 4):                           # nervios de la boveda, de delante a atras
        h.caja(x, x, 6, 10, -8, 5, HIERRO_C)
    h.caja(-6, 5, 9, 9, -8, -6, HIERRO_C)              # ceja de la frente
    h.caja(-6, -6, 1, 9, -8, 6, HIERRO_C)              # cantos laterales
    h.caja(5, 5, 1, 9, -8, 6, HIERRO_C)
    h.caja(-4, 3, 7, 7, -10, -9, HIERRO_C)             # travesaño sobre la visera
    for x in (-4, -1, 2):                              # remaches de la visera
        h.caja(x, x, 5, 5, -11, -11, HIERRO)
    h.caja(-6, 5, 2, 3, -9, -7, HIERRO_C)              # placa de la sien
    h.caja(-6, -5, 1, 4, -9, 4, HIERRO_C)              # carrilleras
    h.caja(4, 5, 1, 4, -9, 4, HIERRO_C)
    h.caja(-5, 4, -7, 3, -9, 5, HUESO)                 # craneo: pomulos y mandibula
    h.caja(-5, 4, -7, -5, -9, 4, HUESO_S)              # mandibula en sombra
    for x in range(-5, 5, 2):                          # dientes, uno si uno no
        h.caja(x, x, -7, -6, -10, -9, HUESO)
    # LAS CUENCAS: hundidas, pero CON FONDO. Vaciarlas del todo dejaba ver la cara del soldado de
    # debajo -piel clara, iluminada- y de frente salia un rectangulo blanco en mitad de la calavera.
    # Se hunden dos voxels y el fondo se pinta de brasa, que es lo que da la mirada encendida.
    # LA CARA MIRA A -Z. Las cuencas estaban en z=-12..-10, o sea POR DELANTE de la calavera (que
    # llega a -9): quedaban fuera de la cabeza y no se veian. Van HUNDIDAS, del borde hacia dentro.
    h.caja(-4, -2, 0, 3, -9, -7, HUESO_S)              # el hueco, en hueso oscuro
    h.caja(1, 3, 0, 3, -9, -7, HUESO_S)
    h.caja(-4, -2, 1, 2, -9, -8, OJO)                  # y dentro, la mirada ROJA
    h.caja(1, 3, 1, 2, -9, -8, OJO)
    h.caja(-3, -2, 1, 2, -9, -9, OJO_V)                # la pupila, encendida, justo en el borde
    h.caja(1, 2, 1, 2, -9, -9, OJO_V)
    # CUERNOS: cuatro tramos escalonados que salen de la sien, suben y caen hacia adelante. Con
    # escalones se lee la curva; una curva de verdad a esta resolucion no se nota y cuesta el triple.
    for lado in (-1, 1):
        def cuerno(dx0, dx1, y0, y1, z0, z1, c=HUESO):
            xs = sorted((6 * lado + dx0 * lado, 6 * lado + dx1 * lado))
            h.caja(xs[0], xs[1], y0, y1, z0, z1, c)
        # sale de la sien, se abre hacia afuera, sube y cae hacia adelante. Cada tramo se SEPARA mas
        # del casco: pegados al craneo no se leen como cuernos, se leen como orejas.
        cuerno(0, 2, 4, 7, -2, 2)
        cuerno(2, 4, 6, 10, -5, 0)
        cuerno(3, 5, 6, 10, -10, -4)
        cuerno(3, 4, 3, 7, -14, -9, HUESO_S)
    # LAS PUAS DEL BORDE. En la referencia el yelmo no acaba en una linea recta: de su canto bajan
    # cuatro puntas a los lados de la mandibula, dos por lado, apuntando hacia abajo y afuera. Son lo
    # que le da la silueta de mascara y no de casco.
    for lado in (-1, 1):
        for i, (dx, largo) in enumerate(((0, 5), (2, 3))):
            x = (4 + dx) * lado
            a, b = min(x, x + lado), max(x, x + lado)
            h.caja(a, b, -1 - largo, 0, -6 + i * 3, -2 + i * 3, HIERRO_C)
            h.caja(a, b, -1 - largo, -largo, -6 + i * 3, -2 + i * 3, HIERRO)   # la punta, oscura
    P["heraldo_yelmo"] = {"quita": [6, 7, 11, 12], "vox": {"head": h.lista()}}

    # --- CAPA DE JIRONES -------------------------------------------------------------------------
    # Cuelga de la espalda y se deshilacha: cada tira de su largo, con la punta quemandose. Un borde
    # recto parece una toalla colgada, asi que NINGUNA tira acaba a la misma altura.
    cp = Cuerpo()
    cp.caja(-7, 6, -2, 9, 5, 7, CUERO_N)               # la capa, pegada a la espalda
    cp.caja(-8, 7, 6, 9, 5, 6, HIERRO)                 # el cuello, de hierro
    cp.caja(-8, 7, 8, 8, 4, 5, BRASA_H)                # brasa en el borde del cuello
    for x0, x1, hasta in [(-7, -5, -9), (-4, -3, -15), (-2, 0, -20), (1, 3, -14), (4, 6, -8)]:
        cp.caja(x0, x1, hasta, -2, 5, 6, CUERO_N)
        cp.caja(x0, x1, hasta, hasta + 1, 5, 6, BRASA_H)          # la punta, ardiendo
        cp.caja(x0, x0, hasta + 2, hasta + 4, 5, 6, BRASA)        # un rescoldo subiendo
    P["heraldo_capa"] = {"quita": [], "vox": {"chest": cp.lista()}}

    # --- FALDON DE CUERO -------------------------------------------------------------------------
    fa = Cuerpo()
    fa.caja(-7, 6, -13, 2, -6, 6, CUERO_N)             # la falda
    fa.caja(-7, 6, -13, -11, -6, 6, BRASA_H)           # el bajo, chamuscado
    fa.caja(-7, 6, 2, 4, -7, 7, HIERRO)                # cinturon ancho
    fa.caja(-2, 1, 2, 4, -8, -7, HIERRO_C)             # hebilla
    fa.caja(-1, 0, 3, 3, -9, -8, BRASA_V)              # con una brasa dentro
    for x in (-6, -4, 4, 6):                           # remaches
        fa.caja(x, x, 3, 3, -8, -8, HIERRO_C)
    P["heraldo_faldon"] = {"quita": [], "vox": {"pelvis": fa.lista()}}

    # --- HOMBRERAS Y GRIETAS DEL TORSO -----------------------------------------------------------
    to = Cuerpo()
    to.caja(-10, -7, 5, 10, -5, 5, HIERRO)             # hombrera izquierda
    to.caja(7, 10, 5, 10, -5, 5, HIERRO)               # y derecha
    to.caja(-10, -7, 10, 10, -5, 5, HIERRO_C)          # canto pulido
    to.caja(7, 10, 10, 10, -5, 5, HIERRO_C)
    to.caja(-10, -9, 7, 8, -6, -5, BRASA_H)            # una brasa en cada hombro
    to.caja(9, 10, 7, 8, -6, -5, BRASA_H)
    # LAS GRIETAS: en diagonal por el pecho, alternando granate y naranja. Una linea recta parece una
    # cremallera; en diagonal y partida parece piedra rota.
    for i, (x, y) in enumerate([(-4, 5), (-3, 3), (-1, 1), (0, -1), (2, -3), (3, -5)]):
        to.caja(x, x + 1, y, y + 1, -7, -6, BRASA if i % 2 else BRASA_H)
    to.caja(-1, 0, 1, 2, -8, -7, BRASA_V)              # el corazon, mas vivo y mas hondo
    to.caja(-6, -5, 2, 3, -7, -6, BRASA_H)             # dos vetas sueltas a los lados
    to.caja(5, 6, 4, 5, -7, -6, BRASA_H)
    P["heraldo_torso"] = {"quita": [], "vox": {"chest": to.lista()}}

    # --- BRAZALETES ------------------------------------------------------------------------------
    br = Cuerpo()
    br.caja(-5, 4, -2, 3, -5, 4, HIERRO)               # el brazal
    br.caja(-5, 4, 3, 3, -5, 4, HIERRO_C)
    br.caja(-5, -4, 0, 1, -6, -5, BRASA_H)             # brasa en el canto
    P["heraldo_brazal"] = {"quita": [], "vox": {
        "arm_lower_l": br.lista(), "arm_lower_r": br.espejo_x().lista()}}
    return P


def escribir_fino(nombre, fino, primero):
    """LA PIEZA A SU RESOLUCION DE ORIGEN (blend_a_pieza.py --fino) -> godot/avatar/fino/<nombre>.bin.

    Va en binario y aparte, no en el rig: son ~100.000 rectangulos y el rig lo leen todos al arrancar
    aunque nadie lleve ese modelo. El juego lo carga solo cuando hornea esa skin.

    Formato (little endian): u32 huesos; por hueso: u16 largo + nombre, f32 origen x3, f32 escala,
    u32 rectangulos, y por rectangulo 7 i32: cara (0..5 = +x -x +y -y +z -z), plano, u0, v0, ancho,
    alto, indice de paleta. u/v son los dos ejes que no son el de la cara, en orden (x,y,z).
    """
    carpeta = os.path.join(RAIZ, "godot", "avatar", "fino")
    if not os.path.isdir(carpeta):
        os.makedirs(carpeta)
    out = bytearray(struct.pack("<I", len(fino["huesos"])))
    total = 0
    for hueso, h in sorted(fino["huesos"].items()):
        nb = hueso.encode("ascii")
        out += struct.pack("<H", len(nb)) + nb
        out += struct.pack("<4f", h["origen"][0], h["origen"][1], h["origen"][2], fino["escala"])
        out += struct.pack("<I", len(h["quads"]))
        for q in h["quads"]:
            ip = int(q[7]) if q[6] == "V" else primero + int(q[7])
            out += struct.pack("<7i", q[0], q[1], q[2], q[3], q[4], q[5], ip)
        total += len(h["quads"])
    io.open(os.path.join(carpeta, nombre + ".bin"), "wb").write(bytes(out))
    print("  pieza '%s' a resolucion fina: %d rectangulos, %.1f MB" % (nombre, total, len(out) / 1e6))
    return "res://avatar/fino/%s.bin" % nombre


def piezas_de_blender(P, pal, base):
    """Mete en el catalogo las piezas esculpidas a mano (tools/piezas_blender/*.json).

    El camino Blender -> juego lo abre `tools/blender/blend_a_pieza.py`; aqui solo se pegan. Hacia
    falta porque hasta ahora el .blend era una foto de salida: todo lo que se retocaba en Blender se
    perdia en la siguiente generacion, y el modelo de verdad solo podia nacer de este archivo.

    Devuelve cuantos colores se han anadido, que el que llama tiene que sumar a `colores_soldado`:
    el juego calcula el principio del bloque de colores del soldado como len(paleta) - ese numero,
    y si no cuadra `quita` empieza a borrar colores que no son.
    """
    carpeta = os.path.join(RAIZ, "tools", "piezas_blender")
    if not os.path.isdir(carpeta):
        return 0
    anadidos = 0
    for archivo in sorted(os.listdir(carpeta)):
        if not archivo.endswith(".json"):
            continue
        d = json.load(io.open(os.path.join(carpeta, archivo), encoding="utf-8"))
        # los colores nuevos van AL FINAL de la paleta; los indices locales se traducen aqui
        primero = len(pal)
        for c in d.get("colores", []):
            pal.append(list(c))
        anadidos += len(d.get("colores", []))
        vox = {}
        for hueso, lista in d.get("vox", {}).items():
            vox[hueso] = [[v[0], v[1], v[2],
                           (int(v[4]) if v[3] == "V" else primero + int(v[4]))] for v in lista]
        P[d["nombre"]] = {"quita": [], "tapa": d.get("tapa", []), "vox": vox}
        # huesos movidos en el .blend de esta pieza (codos, parpados): solo para quien la lleve
        if d.get("articulaciones"):
            P[d["nombre"]]["articulaciones"] = d["articulaciones"]
        if "fino" in d:
            P[d["nombre"]]["fino"] = escribir_fino(d["nombre"], d["fino"], primero)
        print("  pieza de Blender '%s' desde %s: %d voxels, %d colores"
              % (d["nombre"], d.get("origen", "?"), sum(len(v) for v in vox.values()),
                 len(d.get("colores", []))))
    return anadidos


def main():
    rig, pal, base = cargar()
    cuerpos = construir(base)
    padres = dict(rig["bone_parents"])
    for _n in ("eye_l_up", "eye_l_dn", "eye_r_up", "eye_r_dn"):
        padres[_n] = "head"
    fuera = {"bones": {}, "bone_parents": padres,
             "voxel_size_m": rig["voxel_size_m"] / 2.0}
    total = 0
    for nombre, viejo in rig["bones"].items():
        wp = [c * 2.0 for c in viejo["world_pos"]]
        mo = [c * 2.0 for c in viejo["mesh_off"]]
        vox = cuerpos[nombre].lista() if nombre in cuerpos else \
            [[v[0] * 2, v[1] * 2, v[2] * 2, v[3]] for v in viejo["voxels"]]
        total += len(vox)
        fuera["bones"][nombre] = {"voxels": vox, "world_pos": wp, "mesh_off": mo}
    # AJUSTE DE ARTICULACIONES, en voxels del soldado (x, y arriba, z hacia atras). Se mueve el hueso
    # raiz y TODA su cadena (pivote y arte a la vez), asi que lo que cuelga de ella -pantalones,
    # rodilleras, las piezas de Blender- se va con el. Mirando al soldado de frente, `_l` queda a la
    # izquierda de la pantalla y `_r` a la derecha.
    #   leg_upper_l: sobresalia 2 voxels de la cadera (hasta ahora solo se corregia al exportar a
    #                Blender, con DESPLAZA en soldado_a_blender.py) y va 2 hacia atras.
    #   leg_upper_r: 1 hacia atras.
    #   arm_upper_*: al colgar, el brazo quedaba por debajo de la hombrera y hacia fuera, sin unirse
    #                al hombro (medido en --avatarshot --medio). Hacia dentro es +X para `_r` (esta en
    #                -X) y -X para `_l`. El izquierdo necesita mas que el derecho: con los dos a 2 su
    #                borde seguia saliendo 2 voxels por fuera de la hombrera, y va 1 mas arriba. De lado
    #                colgaba 2,5 voxels por detras del centro del torso: se adelanta 3 (-Z).
    # SIMETRIA (2026-09-23, pedido: "que coincidan de igual forma con el otro miembro"). Los valores de antes
    # se ajustaron a ojo cada lado por su cuenta y dejaban el brazo izquierdo 1 voxel mas alto, los dos brazos
    # descolocados de adelante-atras respecto al hombro (el izquierdo 2 por delante, el derecho 1 por detras)
    # y la pierna izquierda 1 mas atras. Medido sobre el arte dibujado (world_pos + mesh_off + voxel), con el
    # eje del cuerpo en x = -2,5: ahora cada pareja queda en espejo exacto y los brazos a la altura y el fondo
    # del hombro (z 2).
    AJUSTE_CADENAS = {
        "leg_upper_l": (-2.0, 0.0, 1.0),
        "leg_upper_r": (0.0, 0.0, 1.0),
        "arm_upper_r": (2.0, 4.0, -1.0),
        "arm_upper_l": (-4.0, 4.0, -1.0),
    }
    # ...y la mano izquierda, que el rig viejo traia 2 voxels mas hacia fuera que la derecha (solo ese hueso)
    AJUSTE_HUESO = {"hand_l": (-2.0, 0.0, 0.0)}
    for raiz, d in AJUSTE_CADENAS.items():
        cadena = [raiz]
        for n in cadena:
            cadena += [h for h, p in padres.items() if p == n and h not in cadena]
        for n in cadena:
            if n in fuera["bones"]:
                wp = fuera["bones"][n]["world_pos"]
                fuera["bones"][n]["world_pos"] = [wp[0] + d[0], wp[1] + d[1], wp[2] + d[2]]
    for n, d in AJUSTE_HUESO.items():
        if n in fuera["bones"]:
            wp = fuera["bones"][n]["world_pos"]
            fuera["bones"][n]["world_pos"] = [wp[0] + d[0], wp[1] + d[1], wp[2] + d[2]]
    # Los ojos no existen en el rig viejo, asi que su sitio se calcula aqui: el arte de un hueso se
    # dibuja en world_pos + mesh_off + coordenada. El ojo ocupa las filas 0..3 de la cara; la mitad
    # de arriba y la de abajo se clavan en el centro, que es donde se juntan al cerrarse.
    cab = fuera["bones"]["head"]
    hx, hy, hz = cab["world_pos"]
    ox, oy, oz = cab["mesh_off"]
    # las dos mitades se clavan en el CENTRO del ojo: la de arriba en la fila 2 y la de abajo en la
    # 1, que son las dos filas que se tocan en el medio
    for nombre, ex, ey in (("eye_l_up", -4, 2.0), ("eye_l_dn", -4, 1.0),
                           ("eye_r_up", 0, 2.0), ("eye_r_dn", 0, 1.0)):
        fuera["bones"][nombre] = {
            "voxels": cuerpos[nombre].lista(),
            "world_pos": [hx + ox + ex, hy + oy + ey, hz + oz - 6.0],
            "mesh_off": [0.0, 0.0, 0.0],
        }
        total += len(fuera["bones"][nombre]["voxels"])
    # CUANTOS COLORES DEL SOLDADO HAY. Antes el codigo daba por hecho que eran 19 y los contaba
    # desde el final de la paleta; al anadir los de podredumbre y laton habria descuadrado todo.
    fuera["colores_soldado"] = len(NUEVOS)
    fuera["piezas"] = piezas(base)
    fuera["colores_soldado"] += piezas_de_blender(fuera["piezas"], pal, base)
    npz = sum(len(p["vox"][k]) for p in fuera["piezas"].values() for k in p["vox"])
    json.dump(fuera, io.open(SALIDA, "w", encoding="utf-8"), separators=(",", ":"))
    json.dump(pal, io.open(PALETA, "w", encoding="utf-8"), separators=(",", ":"))
    print("escrito %s" % SALIDA)
    print("  %d huesos, %d voxels (el avatar viejo tenia 1141)" % (len(fuera["bones"]), total))
    print("  voxel %.5f m (antes %.5f): mismo tamano en metros, el doble de detalle"
          % (fuera["voxel_size_m"], rig["voxel_size_m"]))
    print("  paleta ampliada a %d colores (los %d viejos sin tocar)" % (len(pal), base))
    print("  %d piezas intercambiables, %d voxels: %s"
          % (len(fuera["piezas"]), npz, ", ".join(sorted(fuera["piezas"].keys()))))


if __name__ == "__main__":
    main()
