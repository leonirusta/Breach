"""PIEZAS DE ARMA. La caja de herramientas con la que se montan las armas de Breach en Blender.

No hay una sola arma aqui: hay tornillos, cañones, rieles, perfiles y cargadores. Cada arma
(armas.py) se monta con estas piezas, como se monta una de verdad.

EJES. Se modela en metros y a tamaño real, con el arma APUNTANDO A +Y de Blender y +Z arriba. El
exportador de glTF gira el mundo (Blender +Y -> Godot -Z), asi que en el juego el arma apunta a -Z,
que es lo que espera player.gd. Para pasar un punto a coordenadas de Godot: (x, z, -y).

LO QUE HACE QUE NO PAREZCA DE CARTON. Tres cosas, y las tres estan aqui:
  * BISEL en todo. Una arista viva no existe en el metal real; el bisel de 1 mm es lo que engancha
    la luz y dibuja el contorno de cada pieza.
  * PERFILES, no cajas. El cajon de un AK es un trapecio, el guardamanos de un M4 un octogono, el
    riel picatinny una sierra. `perfil()` extruye una seccion de verdad.
  * BARRIDO para lo curvo: un cargador de AK no es una caja inclinada, es una seccion que va
    girando. `barrido()` hila las secciones.
"""
import bpy
import bmesh
import math
from mathutils import Vector, Matrix, Euler

PIEZAS = []          ## lo montado hasta ahora (lo vacia cada arma al empezar)
MATS = {}


# ---------------------------------------------------------------------------
# MATERIALES. Pocos y bien elegidos: un arma real son cuatro materiales (acero pavonado, aluminio
# anodizado, polimero y goma) y los detalles de laton y cristal.
# ---------------------------------------------------------------------------
def _mat(nombre, color, metal, rug, emision=None, fuerza=1.0, alfa=1.0):
    if nombre in MATS:
        return MATS[nombre]
    m = bpy.data.materials.new(nombre)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], alfa)
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rug
    if alfa < 1.0:
        bsdf.inputs["Alpha"].default_value = alfa
        m.blend_method = 'BLEND'
    if emision:
        bsdf.inputs["Emission Color"].default_value = (emision[0], emision[1], emision[2], 1.0)
        bsdf.inputs["Emission Strength"].default_value = fuerza
    MATS[nombre] = m
    return m


def materiales():
    """Los materiales del taller. Se crean una vez y se reparten por nombre."""
    _mat("acero", (0.30, 0.31, 0.34), 0.95, 0.32)            # acero en blanco (cañones, pasadores)
    _mat("pavonado", (0.055, 0.058, 0.065), 0.88, 0.30)      # acero pavonado: el negro azulado del arma
    _mat("aluminio", (0.13, 0.135, 0.145), 0.80, 0.44)       # aluminio anodizado (cajones, rieles)
    _mat("polimero", (0.075, 0.077, 0.082), 0.0, 0.50)       # polimero negro
    _mat("tan", (0.36, 0.30, 0.20), 0.0, 0.58)               # polimero arena
    _mat("oliva", (0.17, 0.19, 0.13), 0.03, 0.62)            # verde ejercito
    _mat("madera", (0.27, 0.145, 0.065), 0.0, 0.45)          # nogal barnizado
    _mat("madera2", (0.20, 0.10, 0.045), 0.0, 0.52)          # su veta oscura
    _mat("goma", (0.030, 0.030, 0.034), 0.0, 0.92)           # cantoneras y empuñaduras
    _mat("laton", (0.72, 0.53, 0.20), 1.0, 0.28)             # vainas y casquillos
    _mat("cobre", (0.60, 0.33, 0.16), 1.0, 0.35)             # puntas de bala
    _mat("cristal", (0.40, 0.58, 0.78), 0.35, 0.05, alfa=0.30)
    # EL CRISTAL DEL ESCUDO ES OTRO: el de las miras tiñe de azul a proposito, pero en el escudo es por
    # donde MIRAS, y tan azul no dejaba ver nada. Este es casi transparente, con solo un tono frio.
    _mat("cristal_escudo", (0.78, 0.88, 0.97), 0.0, 0.02, alfa=0.09)
    _mat("reticula", (1.0, 0.10, 0.06), 0.0, 0.5, emision=(1.0, 0.12, 0.07), fuerza=8.0)
    _mat("luz", (0.25, 0.85, 1.0), 0.0, 0.4, emision=(0.3, 0.9, 1.0), fuerza=6.0)
    # EL CHUPETIN. Rosa de caramelo: nada metalico y poco rugoso, que brille como un plastico duro
    # -un rosa mate parece goma-. El palo, blanco roto: el blanco puro a plena luz se quema y pierde
    # el relieve.
    _mat("caramelo", (0.92, 0.22, 0.48), 0.0, 0.18)
    _mat("palo", (0.93, 0.93, 0.90), 0.0, 0.35)
    return MATS


def M(n):
    return MATS[n]


# ---------------------------------------------------------------------------
# ACCESORIOS (2026-09-29, pedido: "la skin pinta toda el arma, hasta el cargador, la mira, la empuñadura; los
# accesorios no se tienen que pintar, solo el cuerpo del arma"). Las pinturas (godot/scripts/skins_armas.gd)
# deciden que pintar por el NOMBRE DEL MATERIAL, y un arma se funde en una malla con una superficie por material:
# la mira de pavonado y el cajon de pavonado acababan en la misma superficie y no habia forma de separarlos. Ahora
# todo lo que es accesorio (miras, empuñaduras, cargadores, bocachas y silenciadores, bipodes, rieles, tornillos y
# anillas) sale con SU PROPIO material, el mismo con "_acc" detras ("pavonado_acc"): se ve igual, pero la pintura
# no lo reconoce y lo deja de fabrica.
# Se marca de dos maneras: lo que se monta dentro de una funcion con @accesorio (las miras de este archivo, el
# cargador, la empuñadura...) y, lo que esta montado a mano dentro de cada arma, por su nombre (ACC_NOMBRES).
# ---------------------------------------------------------------------------
_ACC = [0]
ACC_NOMBRES = {
    # miras hechas a mano en el arma
    "grano", "pie_grano", "alza_ajustable", "alza_plegable", "mira_plegable",
    "brazo_optica", "cuerpo_optica", "ocular_optica", "objetivo_optica", "visera",
    "base_micro", "pared_micro", "techo_micro",
    # empuñaduras
    "puno", "estria_puno", "mango_vertical", "mango_delantero", "base_mango", "cachas", "talon",
    # bocachas y bipodes
    "bocacha", "compensador", "ventana_comp", "base_bipode", "pata_bipode",
}
_NO_ACC = ("cristal", "reticula", "luz", "cristal_escudo")     # ya van aparte y con su material


def accesorio(f):
    """Decorador: todo lo que se monte dentro de `f` es accesorio."""
    import functools

    @functools.wraps(f)
    def envuelta(*a, **k):
        _ACC[0] += 1
        try:
            return f(*a, **k)
        finally:
            _ACC[0] -= 1
    return envuelta


def es_accesorio(ob):
    return bool(ob.get("acc")) or ob.name.split(".")[0] in ACC_NOMBRES


def _mat_acc(m):
    base = m.name.split(".")[0]
    if base in _NO_ACC or base.endswith("_acc"):
        return m
    n = base + "_acc"
    if n not in MATS:
        c = m.copy()
        c.name = n
        MATS[n] = c
    return MATS[n]


def marcar_accesorios(obs):
    """Pasa los accesorios a su material "_acc". Antes de fundir: despues ya no se sabe que era cada cosa."""
    n = 0
    for ob in obs:
        if not es_accesorio(ob):
            continue
        for sl in ob.material_slots:
            if sl.material is not None:
                sl.material = _mat_acc(sl.material)
        n += 1
    return n


# ---------------------------------------------------------------------------
# ARMAZON DEL TALLER
# ---------------------------------------------------------------------------
def limpiar():
    """Deja la escena vacia. Entre arma y arma, para que no se mezclen."""
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    # y las mallas huerfanas: si no, los nombres se van ensuciando de arma en arma ("Cristal.006") y
    # Godot ya no encuentra el cristal ni la reticula por su nombre
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)
    PIEZAS.clear()


def _crear(me, nombre, material, bisel=0.0012, seg=2, suave=True, angulo=34.0):
    ob = bpy.data.objects.new(nombre, me)
    bpy.context.collection.objects.link(ob)
    me.materials.append(material)
    if _ACC[0] > 0:
        ob["acc"] = 1
    if bisel > 0.0:
        b = ob.modifiers.new("bisel", 'BEVEL')
        b.width = bisel
        b.segments = seg
        b.limit_method = 'ANGLE'
        b.angle_limit = math.radians(30.0)
        b.miter_outer = 'MITER_ARC'
        b.use_clamp_overlap = True
    if suave:
        # AUTOSUAVIZADO: los cilindros salen redondos y las aristas de verdad siguen marcandose.
        # Sin esto un cañon se ve como un tornillo de facetas.
        for p in me.polygons:
            p.use_smooth = True
        s = ob.modifiers.new("suave", 'SMOOTH_BY_ANGLE') if 'SMOOTH_BY_ANGLE' in _tipos_mod() else None
        if s is None:
            _suavizar_manual(ob, angulo)
        else:
            s.angle = math.radians(angulo)
    PIEZAS.append(ob)
    return ob


_TIPOS = None


def _tipos_mod():
    global _TIPOS
    if _TIPOS is None:
        try:
            _TIPOS = {i.identifier for i in bpy.types.Modifier.bl_rna.properties['type'].enum_items}
        except Exception:
            _TIPOS = set()
    return _TIPOS


def _suavizar_manual(ob, angulo):
    """Blender sin el modificador de angulo: se marcan a mano las aristas duras."""
    me = ob.data
    umbral = math.cos(math.radians(angulo))
    bm = bmesh.new()
    bm.from_mesh(me)
    for e in bm.edges:
        if len(e.link_faces) == 2:
            n1 = e.link_faces[0].normal
            n2 = e.link_faces[1].normal
            e.smooth = n1.dot(n2) > umbral
    bm.to_mesh(me)
    bm.free()


def _colocar(ob, pos, rot):
    ob.location = Vector(pos)
    ob.rotation_euler = Euler([math.radians(a) for a in rot], 'XYZ')
    return ob


# ---------------------------------------------------------------------------
# PRIMITIVAS
# ---------------------------------------------------------------------------
def caja(tam, pos, mat, rot=(0, 0, 0), bisel=0.0012, nombre="caja"):
    """Un prisma de `tam` (x, y, z) centrado en `pos`."""
    me = bpy.data.meshes.new(nombre)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(tam), verts=bm.verts)
    bm.to_mesh(me)
    bm.free()
    return _colocar(_crear(me, nombre, mat, bisel), pos, rot)


def cuna(tam, pos, mat, estrecha=0.5, rot=(0, 0, 0), bisel=0.0012, nombre="cuna"):
    """Prisma con la cara de arriba mas estrecha: chaflanes de verdad (cajones, alzas, bases)."""
    me = bpy.data.meshes.new(nombre)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(tam), verts=bm.verts)
    for v in bm.verts:
        if v.co.z > 0:
            v.co.x *= estrecha
    bm.to_mesh(me)
    bm.free()
    return _colocar(_crear(me, nombre, mat, bisel), pos, rot)


def cil(r, largo, pos, mat, eje='Y', seg=20, r2=None, rot=None, bisel=0.0008, nombre="cil", tapas=True):
    """Cilindro (o cono truncado si `r2`). `eje` es hacia donde corre su largo."""
    me = bpy.data.meshes.new(nombre)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=tapas, cap_tris=False, segments=seg,
                          radius1=r, radius2=(r if r2 is None else r2), depth=largo)
    bm.to_mesh(me)
    bm.free()
    if rot is None:
        rot = {'Y': (90, 0, 0), 'X': (0, 90, 0), 'Z': (0, 0, 0)}[eje]
    return _colocar(_crear(me, nombre, mat, bisel), pos, rot)


def tubo(r, grosor, largo, pos, mat, eje='Y', seg=24, rot=None, bisel=0.0006, nombre="tubo", r2=None):
    """Tubo HUECO: se ve por dentro. Para opticas, silenciadores y el tubo de un lanzacohetes.
    Con `r2` sale un cono hueco, que es lo que es la campana de un visor.

    TODO LO QUE ESTE EN EL CAMINO DE LA VISTA TIENE QUE SALIR DE AQUI. Con `cil` (macizo) queda un
    tapon: la campana, el ocular o el tambor de un diopter se convierten en un disco lleno y mirar
    por la mira es mirar contra una pared."""
    me = bpy.data.meshes.new(nombre)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, cap_tris=False, segments=seg,
                          radius1=r, radius2=(r if r2 is None else r2), depth=largo)
    bm.to_mesh(me)
    bm.free()
    if rot is None:
        rot = {'Y': (90, 0, 0), 'X': (0, 90, 0), 'Z': (0, 0, 0)}[eje]
    ob = _colocar(_crear(me, nombre, mat, bisel), pos, rot)
    s = ob.modifiers.new("grosor", 'SOLIDIFY')
    s.thickness = grosor
    s.offset = -1.0
    # el bisel va DESPUES del grosor: si no, biselaria una chapa sin espesor
    if ob.modifiers.get("bisel"):
        ob.modifiers.move(ob.modifiers.find("grosor"), 0)
    return ob


def esfera(r, pos, mat, seg=16, nombre="esfera"):
    me = bpy.data.meshes.new(nombre)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=max(6, seg // 2), radius=r)
    bm.to_mesh(me)
    bm.free()
    return _colocar(_crear(me, nombre, mat, 0.0), pos, (0, 0, 0))


def perfil(puntos, largo, pos, mat, eje='Y', rot=None, bisel=0.0012, nombre="perfil"):
    """SECCION EXTRUIDA. `puntos` es el contorno (a, b) del corte, en sentido antihorario, y se
    estira `largo` a lo largo de `eje`. Con esto salen cajones trapeciales, guardamanos octogonales
    y rieles con su sierra, en vez de cajas."""
    me = bpy.data.meshes.new(nombre)
    bm = bmesh.new()
    vs = [bm.verts.new((a, -largo * 0.5, b)) for a, b in puntos]
    bm.verts.ensure_lookup_table()
    cara = bm.faces.new(vs)
    ret = bmesh.ops.extrude_face_region(bm, geom=[cara])
    nuevos = [e for e in ret["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=nuevos, vec=(0.0, largo, 0.0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    if rot is None:
        rot = {'Y': (0, 0, 0), 'X': (0, 0, 90), 'Z': (90, 0, 0)}[eje]
    return _colocar(_crear(me, nombre, mat, bisel), pos, rot)


def barrido(puntos, marcos, mat, bisel=0.001, nombre="barrido", tapar=True):
    """LO CURVO. La misma seccion (a, b) recorriendo una lista de marcos (matrices 4x4): asi sale el
    cargador curvado de un AK, el guardamanos conico de un subfusil o la ojiva de un cohete.

    OJO CON EL PLANO: la seccion vive en el XY del marco y el barrido avanza por su Z. Al reves (que
    es como estaba) la seccion y el avance van en el mismo plano, los anillos salen uno encima de
    otro y lo que queda es una CHAPA: asi salieron los cargadores y las empuñaduras de la primera
    tanda, como cuchillas colgando del arma."""
    me = bpy.data.meshes.new(nombre)
    bm = bmesh.new()
    anillos = []
    for mtx in marcos:
        anillo = [bm.verts.new(mtx @ Vector((a, b, 0.0))) for a, b in puntos]
        anillos.append(anillo)
    bm.verts.ensure_lookup_table()
    n = len(puntos)
    for k in range(len(anillos) - 1):
        a0, a1 = anillos[k], anillos[k + 1]
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a0[i], a0[j], a1[j], a1[i]))
    if tapar:
        bm.faces.new(list(reversed(anillos[0])))
        bm.faces.new(anillos[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    return _colocar(_crear(me, nombre, mat, bisel), (0, 0, 0), (0, 0, 0))


def marco(pos, rot=(0, 0, 0), escala=1.0):
    """Un marco para `barrido`: donde va la seccion, como esta girada y cuanto se abre."""
    m = Matrix.Translation(Vector(pos)) @ Euler([math.radians(a) for a in rot], 'XYZ').to_matrix().to_4x4()
    return m @ Matrix.Scale(escala, 4)


# ---------------------------------------------------------------------------
# PIEZAS DE ARMA DE VERDAD
# ---------------------------------------------------------------------------
@accesorio
def riel(largo, pos, mat=None, ancho=0.021, nombre="riel"):
    """RIEL PICATINNY con su perfil de verdad (base ancha, alma estrecha, cabeza en cola de milano)
    y las ranuras transversales. Es la pieza que dice "esto es un arma moderna" de un vistazo."""
    mat = mat or M("aluminio")
    a = ancho * 0.5
    sec = [(-a, 0.0), (a, 0.0), (a, 0.0035), (a * 0.62, 0.0065),
           (a * 0.62, 0.0090), (a, 0.0122), (a, 0.0140), (-a, 0.0140),
           (-a, 0.0122), (-a * 0.62, 0.0090), (-a * 0.62, 0.0065), (-a, 0.0035)]
    ob = perfil(sec, largo, pos, mat, nombre=nombre, bisel=0.0006)
    # ranuras: cada 10,4 mm, como manda la norma
    n = max(2, int(largo / 0.0104))
    for i in range(n):
        y = pos[1] - largo * 0.5 + 0.006 + i * 0.0104
        caja((ancho * 1.02, 0.0052, 0.0062), (pos[0], y, pos[2] + 0.0110), mat,
             bisel=0.0004, nombre=nombre + "_ranura")
    return ob


def estrias(n, tam, desde, paso, mat, eje='Y', rot=(0, 0, 0), bisel=0.0004, nombre="estria"):
    """Serie de nervios: el estriado de una corredera, las aletas de un disipador, la madera rayada
    de un guardamanos de bombeo."""
    out = []
    for i in range(n):
        p = (desde[0] + paso[0] * i, desde[1] + paso[1] * i, desde[2] + paso[2] * i)
        out.append(caja(tam, p, mat, rot=rot, bisel=bisel, nombre=nombre))
    return out


def guardamonte(pos, mat, ancho=0.0095, alto=0.038, largo=0.064, grosor=0.006, nombre="guardamonte"):
    """EL ARO DEL GATILLO, colgando POR DEBAJO de `pos`, que es el TECHO del aro (la panza del cajon
    de mecanismos). Antes `pos` era el centro del aro y el aro entero se quedaba metido dentro del
    arma: no se veia, y de paso entre el cajon y el puño no habia nada, asi que el puño parecia
    despegado y colgando en el aire. Colgandolo del techo, el hueco del dedo existe de verdad."""
    x, y, z = pos
    caja((ancho, largo, grosor), (x, y, z - alto + grosor * 0.5), mat, bisel=0.0012, nombre=nombre)
    caja((ancho, grosor, alto), (x, y + largo * 0.5 - grosor * 0.5, z - alto * 0.5), mat,
         rot=(-7, 0, 0), bisel=0.0012, nombre=nombre)
    caja((ancho, grosor * 1.5, alto * 0.6), (x, y - largo * 0.5 + grosor * 0.7, z - alto * 0.3), mat,
         bisel=0.0012, nombre=nombre)
    # el gatillo, colgando del cajon dentro del aro
    caja((0.0058, 0.009, 0.024), (x, y + 0.005, z - 0.014), M("acero"), rot=(-12, 0, 0),
         bisel=0.0015, nombre=nombre + "_gatillo")
    caja((ancho * 1.6, 0.020, 0.010), (x, y + 0.004, z - 0.003), mat, bisel=0.0010, nombre=nombre + "_alojamiento")


@accesorio
def empunadura(pos, mat, angulo=-16.0, largo=0.105, ancho=0.031, fondo=0.042, nombre="puno"):
    """EMPUÑADURA DE PISTOLA, con su inclinacion, su panza y las estrias antideslizantes.
    `angulo` negativo = echada hacia atras, que es como va en un fusil."""
    a = math.radians(angulo)
    sec = [(-ancho * 0.5, -fondo * 0.5), (ancho * 0.5, -fondo * 0.5), (ancho * 0.52, 0.0),
           (ancho * 0.5, fondo * 0.5), (-ancho * 0.5, fondo * 0.5), (-ancho * 0.52, 0.0)]
    marcos = []
    for k in range(5):
        t = k / 4.0
        marcos.append(marco((pos[0], pos[1] + math.sin(a) * largo * t, pos[2] - math.cos(a) * largo * t),
                            rot=(angulo, 0, 0), escala=1.0 - 0.16 * t + 0.10 * math.sin(t * math.pi)))
    barrido(sec, marcos, mat, nombre=nombre)
    fin = marcos[-1].to_translation()
    caja((ancho * 1.06, fondo * 0.96, 0.009), (fin.x, fin.y, fin.z - 0.003), M("goma"),
         rot=(angulo, 0, 0), bisel=0.0015, nombre=nombre + "_talon")
    for i in range(4):
        t = 0.20 + i * 0.20
        p = marcos[0].to_translation().lerp(fin, t)
        caja((ancho * 0.94, 0.005, 0.011), (p.x, p.y + fondo * 0.44, p.z), M("goma"),
             rot=(angulo, 0, 0), bisel=0.0006, nombre=nombre + "_estria")


@accesorio
def cargador(seccion, marcos, mat, nombre="Cargador", base=True):
    """EL CARGADOR VA APARTE (objeto `Cargador`): en la recarga sale del arma, cae al suelo y entra
    otro. Su origen se deja donde asienta en el pozo, que es lo que usa avatar_animator."""
    ob = barrido(seccion, marcos, mat, nombre=nombre)
    if base:
        fin = marcos[-1]
        p = fin.to_translation()
        caja((0.031, 0.086, 0.009), (p.x, p.y, p.z - 0.004), M("polimero"),
             rot=(math.degrees(fin.to_euler().x), 0, 0), bisel=0.0012, nombre=nombre + "_base")
    return ob


def cristal(r, pos, rot=(90, 0, 0), nombre="Cristal"):
    """La lente de una optica. Godot le pone su material transparente por el nombre."""
    me = bpy.data.meshes.new(nombre)
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=True, segments=24, radius=r)
    bm.to_mesh(me)
    bm.free()
    return _colocar(_crear(me, nombre, M("cristal"), 0.0, suave=False), pos, rot)


def cristal_plano(tam, pos, rot=(0, 0, 0), nombre="Cristal"):
    """El cristal rectangular de una holografica."""
    me = bpy.data.meshes.new(nombre)
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=0.5)
    bmesh.ops.scale(bm, vec=Vector((tam[0], tam[1], 1.0)), verts=bm.verts)
    bm.to_mesh(me)
    bm.free()
    return _colocar(_crear(me, nombre, M("cristal"), 0.0, suave=False), pos, rot)


def reticula_punto(pos, r=0.0008, nombre="Reticula"):   # 2026-09-23: mas chico (era 1,3 mm)
    """El punto rojo. Godot le cambia el material por uno que no hace test de profundidad: asi se ve
    siempre nitido encima del cristal, que es lo que hace que apuntar funcione."""
    ob = esfera(r, pos, M("reticula"), seg=10, nombre=nombre)
    ob.name = nombre
    return ob


def reticula_cruz(pos, largo=0.010, grosor=0.00035, nombre="Reticula"):
    caja((largo, 0.0004, grosor), pos, M("reticula"), bisel=0.0, nombre=nombre)
    caja((grosor, 0.0004, largo), pos, M("reticula"), bisel=0.0, nombre=nombre)


def reticula_chevron(pos, ancho=0.006, nombre="Reticula"):
    """La punta de flecha de una optica de prisma: se apunta con el vertice."""
    for s in (-1.0, 1.0):
        caja((ancho * 0.62, 0.0004, 0.0006), (pos[0] + s * ancho * 0.25, pos[1], pos[2] - ancho * 0.22),
             M("reticula"), rot=(0, s * 42.0, 0), bisel=0.0, nombre=nombre)


def reticula_anillo(pos, r=0.0055, nombre="Reticula"):
    me = bpy.data.meshes.new(nombre)
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=False, segments=28, radius=r)
    bm.to_mesh(me)
    bm.free()
    ob = _colocar(_crear(me, nombre, M("reticula"), 0.0, suave=False), pos, (90, 0, 0))
    s = ob.modifiers.new("grosor", 'SOLIDIFY')
    s.thickness = 0.0007
    return ob


@accesorio
def tornillo(pos, r=0.0028, alto=0.0035, mat=None, eje='Z', nombre="tornillo"):
    cil(r, alto, pos, mat or M("acero"), eje=eje, seg=8, bisel=0.0004, nombre=nombre)


@accesorio
def anilla(pos, r=0.007, mat=None, rot=(0, 0, 0), nombre="anilla"):
    """Anilla para la correa. Detalle pequeño que se nota en las capturas."""
    me = bpy.data.meshes.new(nombre)
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=False, segments=14, radius=r)
    bm.to_mesh(me)
    bm.free()
    ob = _colocar(_crear(me, nombre, mat or M("acero"), 0.0), pos, rot)
    s = ob.modifiers.new("grosor", 'SOLIDIFY')
    s.thickness = 0.0022
    return ob


# ---------------------------------------------------------------------------
# OPTICAS. Cada arma lleva LA SUYA, soldada: no hay taller de accesorios. El punto que devuelven es
# el EJE OPTICO a la altura del cristal, que es lo unico que importa para que apuntar este calibrado:
# el juego pone ese punto en el eje de la camara (player.gd, `ads`).
# ---------------------------------------------------------------------------
@accesorio
def mira_hierro(y_delante, y_detras, z, alto=0.022, mat=None, capucha=True, orejas_alza=True):
    """MIRAS DE HIERRO: poste con capucha delante, muesca detras. La linea de mira es el hueco.
    `orejas_alza=False` (2026-09-28, pedido): sin las dos pestañas del alza. Con la mira a 3-6 cm del ojo (en el movil,
    la mitad) eran dos muros a los lados que tapaban media vista; queda la base del alza, plana y por debajo."""
    mat = mat or M("pavonado")
    caja((0.020, 0.010, 0.008), (0, y_delante, z), mat, bisel=0.0008, nombre="base_punto")
    caja((0.0025, 0.0035, alto), (0, y_delante, z + alto * 0.5), M("acero"), bisel=0.0004, nombre="poste")
    if capucha:
        for s in (-1, 1):
            caja((0.0035, 0.012, alto + 0.006), (s * 0.0088, y_delante, z + alto * 0.5 + 0.001), mat,
                 bisel=0.0006, nombre="oreja")
        caja((0.021, 0.012, 0.0035), (0, y_delante, z + alto + 0.006), mat, bisel=0.0006, nombre="techo_punto")
    # alza: dos orejas y la muesca en medio
    caja((0.024, 0.014, 0.007), (0, y_detras, z + 0.002), mat, bisel=0.0008, nombre="base_alza")
    for s in (-1, 1) if orejas_alza else ():
        caja((0.004, 0.010, alto * 0.62), (s * 0.0062, y_detras, z + 0.005 + alto * 0.31), mat,
             bisel=0.0006, nombre="oreja_alza")
    return (0.0, y_detras, z + 0.004 + alto * 0.42)


@accesorio
def mira_diopter(y_delante, y_detras, z, mat=None):
    """DIOPTER: el tambor con agujero de un MP5 o un G3. Se mira POR el agujero, asi que el agujero
    es un AGUJERO (anillo), no un taco negro pintado encima."""
    mat = mat or M("pavonado")
    tubo(0.0118, 0.0055, 0.016, (0, y_detras, z + 0.016), mat, eje='Y', seg=18, nombre="tambor")
    caja((0.013, 0.013, 0.015), (0, y_detras, z + 0.005), mat, bisel=0.0008, nombre="pie_alza")
    # torre delantera: capucha ABIERTA (anillo) con el poste dentro
    tubo(0.0108, 0.0028, 0.028, (0, y_delante, z + 0.016), mat, eje='Y', seg=16, nombre="torre")
    caja((0.0024, 0.026, 0.012), (0, y_delante, z + 0.012), M("acero"), bisel=0.0003, nombre="poste")
    caja((0.015, 0.014, 0.013), (0, y_delante, z + 0.005), mat, bisel=0.0008, nombre="pie_torre")
    return (0.0, y_detras, z + 0.016)


## ELEVADOR (2026-09-23): una mira de verdad va subida sobre una base para que el cuerpo del arma quede muy por
## debajo de la ventana. Sin el, al encarar, el cajon del arma tapaba media mira justo por debajo del punto.
ELEVA_MIRA = 0.012

@accesorio
def elevador(y, z, largo, mat):
    caja((0.022, largo, ELEVA_MIRA), (0, y, z + ELEVA_MIRA * 0.5), mat, bisel=0.0006, nombre="elevador")
    return z + ELEVA_MIRA


@accesorio
def mira_punto(y, z, mat=None, tubo_abierto=True, verde=False):
    """PUNTO ROJO abierto: dos paredes, un techo y el cristal DELANTE, inclinado. El emisor va detras
    y abajo, que es de donde sale el punto que se proyecta en el cristal. Se ve a traves."""
    mat = mat or M("aluminio")
    z = elevador(y, z, 0.040, mat)
    caja((0.034, 0.058, 0.011), (0, y, z + 0.0055), mat, bisel=0.0010, nombre="base_optica")
    caja((0.010, 0.016, 0.009), (0.020, y - 0.012, z + 0.009), M("acero"), bisel=0.0008, nombre="palomilla")
    alto = 0.032
    for s_ in (-1, 1):
        # PAREDES FINAS (2026-09-23, pedido): 1,8 mm en vez de 3,5, adelgazadas hacia fuera: el hueco para mirar crece
        caja((0.0018, 0.050, alto), (s_ * 0.01565, y, z + 0.011 + alto * 0.5), mat, bisel=0.0004, nombre="pared")
    caja((0.033, 0.050, 0.002), (0, y, z + 0.011 + alto + 0.003), mat, bisel=0.0004, nombre="techo")
    # LO NEGRO BAJO EL PUNTO (2026-09-23, pedido): al encarar, el labio trasero y el emisor quedaban entre el ojo
    # y el cristal, justo por debajo del eje, y tapaban media ventana. Ahora son una pestaña a ras de la base.
    caja((0.033, 0.005, 0.003), (0, y - 0.0245, z + 0.0125), mat, bisel=0.0004, nombre="labio")
    caja((0.033, 0.005, 0.003), (0, y + 0.0245, z + 0.0125), mat, bisel=0.0004, nombre="labio")
    eje_z = z + 0.011 + alto * 0.52
    # EL CRISTAL VA DELANTE (hacia la boca) y el emisor DETRAS. Montado al reves se apunta por la
    # trasera de la mira: el ojo se apoya en la tapa y el punto no se ve.
    cristal_plano((0.026, 0.030), (0, y + 0.012, eje_z), rot=(82, 0, 0))
    caja((0.012, 0.006, 0.0025), (0, y - 0.016, z + 0.0122), M("pavonado"), bisel=0.0003, nombre="emisor")
    caja((0.008, 0.010, 0.006), (0.017, y + 0.005, z + 0.016), mat, bisel=0.0006, nombre="boton")
    reticula_punto((0, y + 0.0115, eje_z))
    return (0.0, y + 0.012, eje_z)


@accesorio
def mira_holo(y, z, mat=None):
    """HOLOGRAFICA: el cajon del laser y la pila DETRAS, y la ventana cuadrada DELANTE."""
    mat = mat or M("pavonado")
    z = elevador(y, z, 0.050, mat)
    caja((0.036, 0.072, 0.012), (0, y, z + 0.006), mat, bisel=0.0010, nombre="base_holo")
    # EL CUERPO DEL LASER VA DEBAJO, no detras a la altura del cristal: ahi era una pared
    # justo delante del ojo y no se veia nada por la ventana.
    # (y por la misma razon, el cuerpo del laser y la tapa de la pila no suben hasta el eje: la tapa acababa 1 mm
    # por debajo de la linea de mira, pegada al ojo)
    caja((0.036, 0.034, 0.012), (0, y - 0.019, z + 0.011), mat, bisel=0.0010, nombre="cuerpo_holo")
    caja((0.030, 0.012, 0.004), (0, y - 0.034, z + 0.012), mat, bisel=0.0006, nombre="tapa_pila")
    for s_ in (-1, 1):
        caja((0.0016, 0.040, 0.030), (s_ * 0.0172, y + 0.014, z + 0.027), mat, bisel=0.0004, nombre="pared_holo")
    caja((0.036, 0.040, 0.0018), (0, y + 0.014, z + 0.04335), mat, bisel=0.0004, nombre="techo_holo")
    for i in range(2):
        caja((0.007, 0.007, 0.007), (0.019, y - 0.016 - i * 0.010, z + 0.014), mat, bisel=0.0006, nombre="boton_holo")
    eje_z = z + 0.027
    cristal_plano((0.029, 0.026), (0, y + 0.020, eje_z), rot=(90, 0, 0))
    reticula_anillo((0, y + 0.021, eje_z))
    reticula_punto((0, y + 0.021, eje_z))
    return (0.0, y + 0.020, eje_z)


@accesorio
def mira_prisma(y, z, largo=0.098, mat=None):
    """OPTICA DE PRISMA (tipo ACOG): cuerpo corto y macizo, LA CAMPANA DELANTE y el ocular detras,
    con el chevron dentro. Devuelve el OCULAR, que es donde se apoya el ojo: eso es lo que el juego
    pone en el eje de la camara al encarar, asi que mirar por ella funciona como en la realidad."""
    mat = mat or M("pavonado")
    caja((0.034, 0.032, 0.014), (0, y, z + 0.007), mat, bisel=0.0010, nombre="base_prisma")
    for s_ in (-1, 1):
        caja((0.012, 0.024, 0.020), (s_ * 0.012, y, z + 0.020), mat, bisel=0.0010, nombre="anilla")
    eje_z = z + 0.036
    tubo(0.0178, 0.0020, largo, (0, y + 0.006, eje_z), mat, eje='Y', seg=24, nombre="cuerpo_prisma")
    tubo(0.0215, 0.0035, 0.020, (0, y + 0.006 + largo * 0.5 + 0.008, eje_z), mat, eje='Y', seg=24,
         r2=0.0190, nombre="campana")
    tubo(0.0205, 0.0035, 0.016, (0, y + 0.006 - largo * 0.5 - 0.006, eje_z), mat, eje='Y', seg=24,
         nombre="ocular")
    cil(0.0105, 0.014, (0, y - 0.006, eje_z + 0.019), mat, eje='Z', seg=14, bisel=0.0006, nombre="torreta")
    cil(0.0105, 0.014, (0.019, y - 0.006, eje_z), mat, eje='X', seg=14, bisel=0.0006, nombre="torreta")
    caja((0.030, 0.026, 0.004), (0, y + 0.020, eje_z + 0.021), mat, bisel=0.0006, nombre="visera")
    cristal(0.0182, (0, y + 0.006 + largo * 0.5 + 0.016, eje_z))
    reticula_chevron((0, y + 0.006 + largo * 0.5 + 0.014, eje_z))
    return (0.0, y + 0.006 - largo * 0.5 - 0.014, eje_z)


@accesorio
def mira_telescopica(y, z, largo=0.230, mat=None):
    """TELESCOPICA de verdad: tubo de 30 mm, LA CAMPANA DELANTE, ocular con goma detras, torretas y
    su anillo de aumentos. Devuelve el ocular, que es donde va el ojo."""
    mat = mat or M("pavonado")
    eje_z = z + 0.044
    for s_ in (-1, 1):
        caja((0.036, 0.018, 0.014), (0, y + s_ * largo * 0.24, z + 0.007), mat, bisel=0.0010, nombre="base_anilla")
        cil(0.0195, 0.018, (0, y + s_ * largo * 0.24, eje_z), mat, eje='Y', seg=20, bisel=0.0008, nombre="anilla")
        caja((0.036, 0.018, 0.022), (0, y + s_ * largo * 0.24, z + 0.020), mat, bisel=0.0010, nombre="pie_anilla")
    tubo(0.0168, 0.0016, largo, (0, y, eje_z), mat, eje='Y', seg=26, nombre="tubo_visor")
    tubo(0.0245, 0.0045, 0.052, (0, y + largo * 0.5 + 0.022, eje_z), mat, eje='Y', seg=26, r2=0.0180,
         nombre="campana")
    tubo(0.0255, 0.0050, 0.010, (0, y + largo * 0.5 + 0.046, eje_z), mat, eje='Y', seg=26, nombre="aro_campana")
    tubo(0.0225, 0.0038, 0.044, (0, y - largo * 0.5 - 0.018, eje_z), mat, eje='Y', seg=26, r2=0.0188,
         nombre="ocular")
    tubo(0.0245, 0.0045, 0.012, (0, y - largo * 0.5 - 0.038, eje_z), M("goma"), eje='Y', seg=26, nombre="goma_ocular")
    cil(0.0115, 0.020, (0, y + 0.012, eje_z + 0.022), mat, eje='Z', seg=16, bisel=0.0006, nombre="torreta_alta")
    cil(0.0125, 0.006, (0, y + 0.012, eje_z + 0.033), M("acero"), eje='Z', seg=16, bisel=0.0004, nombre="tapa_torreta")
    cil(0.0115, 0.020, (0.022, y + 0.012, eje_z), mat, eje='X', seg=16, bisel=0.0006, nombre="torreta_lat")
    tubo(0.0178, 0.0022, 0.024, (0, y - 0.030, eje_z), mat, eje='Y', seg=22, nombre="anillo_aumento")
    estrias(8, (0.004, 0.004, 0.036), (-0.016, y - 0.030, eje_z), (0.0045, 0, 0), mat, nombre="muesca_zoom")
    cristal(0.0175, (0, y + largo * 0.5 + 0.045, eje_z))
    reticula_cruz((0, y + largo * 0.5 + 0.043, eje_z), largo=0.024, grosor=0.0004)
    for i in (-2, -1, 1, 2):
        caja((0.0008, 0.0004, 0.0008), (0, y + largo * 0.5 + 0.043, eje_z + i * 0.0035),
             M("reticula"), bisel=0.0, nombre="Reticula_mildot")
    return (0.0, y - largo * 0.5 - 0.040, eje_z)


@accesorio
def mira_pgo(y, z, lado=-0.048, mat=None):
    """LA OPTICA LATERAL DEL RPG (PGO-7): el camino de la vista es un TUBO HUECO y la carcasa cuelga
    por debajo. Con la carcasa maciza atravesada delante del ocular no se veia absolutamente nada.
    Ojo: la mira esta DESCENTRADA en el arma, pero el juego alinea SU EJE con la camara, asi que se
    apunta por ella igual que en la realidad y el tubo queda cruzado, que es justo como se ve."""
    mat = mat or M("oliva")
    eje_z = z + 0.036
    # (2026-09-29, pedido: "hay algo dentro de la mira"): la carcasa subia 7 mm DENTRO del hueco del tubo y el soporte
    # 1 mm; apuntando se veia una placa verde en la mitad de abajo. Ahora acaban en la pared del tubo (hueco: eje ± 14 mm).
    caja((0.040, 0.062, 0.024), (lado, y + 0.004, z + 0.008), mat, bisel=0.0014, nombre="cuerpo_pgo")
    caja((0.020, 0.026, 0.022), (lado + 0.020, y + 0.008, z + 0.010), mat, bisel=0.0010, nombre="brazo_pgo")
    tubo(0.0170, 0.0030, 0.108, (lado, y, eje_z), mat, eje='Y', seg=20, nombre="tubo_pgo")
    tubo(0.0195, 0.0045, 0.026, (lado, y + 0.056, eje_z), mat, eje='Y', seg=20, nombre="objetivo_pgo")
    caja((0.038, 0.030, 0.006), (lado, y + 0.060, eje_z + 0.022), mat, bisel=0.0008, nombre="visera_pgo")
    tubo(0.0200, 0.0050, 0.028, (lado, y - 0.056, eje_z), M("goma"), eje='Y', seg=20, nombre="ocular_pgo")
    cil(0.0090, 0.016, (lado, y + 0.010, z + 0.006), mat, eje='Z', seg=12, bisel=0.0006, nombre="rueda_pgo")
    cristal(0.0140, (lado, y + 0.066, eje_z))
    reticula_cruz((lado, y + 0.064, eje_z), largo=0.016, grosor=0.0005)
    return (lado, y - 0.072, eje_z)


# ---------------------------------------------------------------------------
# CIERRE: aplicar modificadores y fundir en una sola malla por arma
# ---------------------------------------------------------------------------
def _aplicar(ob):
    bpy.context.view_layer.objects.active = ob
    for m in list(ob.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=m.name)
        except Exception:
            ob.modifiers.remove(m)


def rematar(nombre_raiz):
    """Aplica modificadores y funde TODO lo estatico en una sola malla con una superficie por
    material. El cargador, el cristal y la reticula se quedan sueltos: Godot los necesita aparte
    (el cargador se cae al recargar, y al cristal y a la reticula les pone su material especial).

    Devuelve (raiz, sueltos)."""
    bpy.ops.object.select_all(action='DESELECT')
    for ob in PIEZAS:
        _aplicar(ob)
    marcar_accesorios(PIEZAS)
    # (el MISIL del lanzacohetes va suelto: se esconde al disparar y vuelve al recargar, 2026-10-22)
    estaticos = [o for o in PIEZAS if not o.name.startswith(("Cargador", "Cristal", "Reticula", "Misil"))]
    sueltos = [o for o in PIEZAS if o.name.startswith(("Cargador", "Cristal", "Reticula", "Misil"))]
    # los trozos del cargador se funden entre ellos; los cristales y reticulas, por nombre
    grupos = {}
    for o in sueltos:
        clave = o.name.split("_")[0].rstrip("0123456789.")
        grupos.setdefault(clave, []).append(o)
    raiz = _fundir(estaticos, nombre_raiz)
    fundidos = []
    for clave, lista in grupos.items():
        fundidos.append(_fundir(lista, clave))
    return raiz, fundidos


def _fundir(lista, nombre):
    if not lista:
        return None
    bpy.ops.object.select_all(action='DESELECT')
    for o in lista:
        o.select_set(True)
    bpy.context.view_layer.objects.active = lista[0]
    if len(lista) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = nombre
    ob.data.name = nombre
    # transformaciones a la malla: el objeto sale con matriz identidad, asi que las coordenadas del
    # .glb son las mismas que las que se midieron al montarlo (y la ficha de puntos cuadra)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return ob


def poner_origen(ob, punto):
    """Mueve el ORIGEN del objeto a `punto` sin moverlo de sitio. El cargador lo necesita: su origen
    tiene que ser el punto que asienta en el pozo, porque es de donde tira la animacion de recarga."""
    if ob is None:
        return
    p = Vector(punto)
    me = ob.data
    for v in me.vertices:
        v.co -= p
    ob.location = p


def tris(ob):
    me = ob.data
    return sum(len(p.vertices) - 2 for p in me.polygons)
