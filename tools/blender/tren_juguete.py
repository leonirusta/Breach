"""EL TREN DE JUGUETE DE LA HABITACION (2026-10-21, pedido: "el diseño del tren es horrible: cubos de colores sin
diseño; que parezca real, metele detalle"). Cuatro piezas, cada una a su .glb:
  godot/modelos/tren/locomotora.glb  vapor: caldera con aros, caja de humos, chimenea acampanada, cupula, arenero,
                                     silbato, cabina con ventanas y techo curvo, faro, quitapiedras, topes, ruedas
                                     motrices con rayos y biela, ruedas delanteras, pasamanos.
  godot/modelos/tren/tender.glb      el carbon, con ruedas y su escalerilla
  godot/modelos/tren/pasajeros.glb   vagon con ventanillas, puertas, techo curvo con ventilaciones, faroles
  godot/modelos/tren/troncos.glb     plataforma con teleras y troncos atados
Medidas de juego: 3 m de largo, 1,7 de ancho, el suelo de las ruedas en z = 0. El FRENTE mira a -Y de Blender
(= +Z en Godot, que es hacia donde avanza en tren_cuarto.gd).
Uso: blender --background --python tools/blender/tren_juguete.py
"""
import bpy, bmesh, math, os

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SALIDA = os.path.join(RAIZ, "godot", "modelos", "tren")
os.makedirs(SALIDA, exist_ok=True)

LARGO, ANCHO = 3.0, 1.7
_mats = {}
# LOS PEDAZOS (2026-10-21, pedido: "con el mazo o a tiros, que se rompa de a pedazos y el tren siga"): cada pieza se
# dibuja con un PARTE puesto y al exportar se juntan por parte: el .glb trae un nodo por pedazo ("p_<nombre>").
# "chasis" no se rompe a pedazos (con el, el vagon entero: eso lo hace una explosion).
PARTE = "chasis"


def parte(n):
    global PARTE
    PARTE = n


def mat(nombre, rgb, metal=0.0, rug=0.5, emite=0.0):
    if nombre in _mats:
        return _mats[nombre]
    m = bpy.data.materials.new(nombre)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rug
    if emite > 0.0:
        b.inputs["Emission Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
        b.inputs["Emission Strength"].default_value = emite
    _mats[nombre] = m
    return m


def srgb(r, g, b):
    return tuple((c / 255.0) ** 2.2 for c in (r, g, b))


ROJO = lambda: mat("rojo", srgb(196, 34, 30), rug=0.35)
VERDE = lambda: mat("verde", srgb(26, 96, 58), rug=0.35)
AZUL = lambda: mat("azul", srgb(34, 72, 150), rug=0.35)
NEGRO = lambda: mat("negro", srgb(26, 26, 28), metal=0.4, rug=0.45)
ORO = lambda: mat("laton", srgb(214, 170, 64), metal=0.9, rug=0.25)
ACERO = lambda: mat("acero", srgb(150, 152, 158), metal=0.9, rug=0.3)
MADERA = lambda: mat("madera", srgb(150, 96, 52), rug=0.7)
MADERA_C = lambda: mat("madera_clara", srgb(196, 146, 92), rug=0.7)
CARBON = lambda: mat("carbon", srgb(30, 30, 32), rug=0.9)
VIDRIO = lambda: mat("vidrio", srgb(150, 200, 230), metal=0.1, rug=0.05)
CREMA = lambda: mat("crema", srgb(236, 222, 186), rug=0.45)
FARO = lambda: mat("faro", srgb(255, 236, 180), emite=3.0)


def _fin(o, m, bisel=0.0, suave=False):
    o["parte"] = PARTE
    o.data.materials.append(m)
    if bisel > 0.0:
        bv = o.modifiers.new("bisel", "BEVEL")
        bv.width = bisel
        bv.segments = 2
        bv.limit_method = "ANGLE"
    if suave:
        for p in o.data.polygons:
            p.use_smooth = True
    return o


def caja(cx, cy, cz, sx, sy, sz, m, bisel=0.02):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, cz))
    o = bpy.context.active_object
    o.scale = (sx, sy, sz)
    bpy.ops.object.transform_apply(scale=True)
    return _fin(o, m, bisel)


def cil(cx, cy, cz, r, largo, m, eje="z", n=24, bisel=0.0):
    rot = {"z": (0, 0, 0), "x": (0, math.pi / 2, 0), "y": (math.pi / 2, 0, 0)}[eje]
    bpy.ops.mesh.primitive_cylinder_add(vertices=n, radius=r, depth=largo, location=(cx, cy, cz), rotation=rot)
    return _fin(bpy.context.active_object, m, bisel, suave=True)


def cono(cx, cy, cz, r1, r2, largo, m, n=24):
    bpy.ops.mesh.primitive_cone_add(vertices=n, radius1=r1, radius2=r2, depth=largo, location=(cx, cy, cz))
    return _fin(bpy.context.active_object, m, suave=True)


def esfera(cx, cy, cz, r, m, sz=1.0):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=10, radius=r, location=(cx, cy, cz))
    o = bpy.context.active_object
    o.scale = (1, 1, sz)
    bpy.ops.object.transform_apply(scale=True)
    return _fin(o, m, suave=True)


def rueda(x, y, r, motriz=False):
    """rueda con pestaña, llanta, cubo y rayos (el eje, a lo ancho)"""
    lado = 1 if x > 0 else -1
    cil(x, y, r, r, 0.12, NEGRO(), eje="x", n=32)
    cil(x - lado * 0.01, y, r, r * 1.08, 0.04, NEGRO(), eje="x", n=32)          # la pestaña
    cil(x + lado * 0.05, y, r, r * 0.82, 0.04, ROJO() if motriz else NEGRO(), eje="x", n=32)
    cil(x + lado * 0.075, y, r, r * 0.2, 0.06, ORO(), eje="x", n=16)            # el cubo
    nr = 10 if motriz else 6
    for k in range(nr):
        a = k * math.pi * 2 / nr
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x + lado * 0.07, y + math.cos(a) * r * 0.45, r + math.sin(a) * r * 0.45))
        o = bpy.context.active_object
        o.scale = (0.03, 0.05, r * 0.85)
        o.rotation_euler = (a + math.pi / 2, 0, 0)
        bpy.ops.object.transform_apply(scale=True, rotation=True)
        _fin(o, mat("rayo", srgb(70, 70, 74), metal=0.7, rug=0.4))


def bogie(y, r=0.26):
    caja(0, y, r + 0.02, ANCHO * 0.7, 0.9, 0.12, NEGRO())
    for dy in (-0.3, 0.3):
        for x in (-ANCHO * 0.5 + 0.05, ANCHO * 0.5 - 0.05):
            rueda(x, y + dy, r)
    for x in (-ANCHO * 0.5 + 0.02, ANCHO * 0.5 - 0.02):
        caja(x, y, r + 0.05, 0.05, 0.85, 0.12, NEGRO())       # el bastidor del bogie, con su muelle
        cil(x, y, r + 0.18, 0.07, 0.12, ACERO(), eje="z", n=12)


def bastidor(alto=0.55, color=None):
    caja(0, 0, alto, ANCHO * 0.94, LARGO * 0.98, 0.14, color or NEGRO())
    for y in (-LARGO * 0.5, LARGO * 0.5):                     # topes y gancho
        s = -1 if y < 0 else 1
        caja(0, y + s * 0.03, alto, ANCHO * 0.96, 0.08, 0.26, ROJO())
        for x in (-0.55, 0.55):
            cil(x, y + s * 0.12, alto, 0.06, 0.18, ACERO(), eje="y", n=12)
            cil(x, y + s * 0.22, alto, 0.12, 0.04, ACERO(), eje="y", n=16)
        caja(0, y + s * 0.14, alto - 0.05, 0.14, 0.22, 0.08, NEGRO())


def limpiar():
    parte("chasis")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for b in list(bpy.data.meshes):
        bpy.data.meshes.remove(b)


def exportar(nombre):
    for o in list(bpy.context.scene.objects):
        bpy.context.view_layer.objects.active = o
        for md in list(o.modifiers):
            bpy.ops.object.modifier_apply(modifier=md.name)
    grupos = {}
    for o in bpy.context.scene.objects:
        grupos.setdefault(o.get("parte", "chasis"), []).append(o)
    for n, objs in grupos.items():
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        if len(objs) > 1:
            bpy.ops.object.join()
        bpy.context.active_object.name = "p_" + n
    ruta = os.path.join(SALIDA, nombre + ".glb")
    bpy.ops.export_scene.gltf(filepath=ruta, export_format="GLB", use_selection=False, export_apply=True)
    print("== escrito", ruta, sorted(grupos))


# ------------------------------------------------------------------------------------------------- la locomotora
def locomotora():
    limpiar()
    F = -1.0     # el frente, hacia -Y
    bastidor(0.55)
    # ruedas motrices grandes (3 por lado) con biela, y dos delanteras chicas
    for y in (0.15, 0.62):
        for x in (-ANCHO * 0.5 + 0.04, ANCHO * 0.5 - 0.04):
            rueda(x, y, 0.36, motriz=True)
    for x in (-ANCHO * 0.5 + 0.04, ANCHO * 0.5 - 0.04):
        rueda(x, -0.9, 0.24)
        lado = 1 if x > 0 else -1
        caja(x + lado * 0.11, 0.38, 0.36, 0.04, 0.62, 0.07, ACERO())            # la biela
        cil(x + lado * 0.05, -0.62, 0.62, 0.13, 0.55, NEGRO(), eje="y", n=16)    # el cilindro de vapor
        caja(x + lado * 0.12, -0.2, 0.5, 0.03, 0.8, 0.05, ACERO())               # el vastago
    parte("caldera")
    # la caldera: verde con aros de laton
    cil(0, -0.35, 1.08, 0.5, 1.7, VERDE(), eje="y", n=40)
    for y in (-1.0, -0.62, -0.25, 0.12, 0.42):
        cil(0, y, 1.08, 0.515, 0.05, ORO(), eje="y", n=40)
    cil(0, -1.22, 1.08, 0.52, 0.12, NEGRO(), eje="y", n=40)                      # la caja de humos
    cil(0, -1.29, 1.08, 0.42, 0.04, NEGRO(), eje="y", n=40)                      # su puerta
    cil(0, -1.31, 1.08, 0.08, 0.04, ORO(), eje="y", n=16)
    parte("chimenea")
    # la chimenea acampanada, la cupula, el arenero y el silbato
    cil(0, -1.0, 1.78, 0.12, 0.45, NEGRO())
    cono(0, -1.0, 2.1, 0.13, 0.22, 0.22, NEGRO())
    cil(0, -1.0, 2.22, 0.23, 0.05, ORO())
    parte("cupula")
    esfera(0, -0.45, 1.62, 0.2, ORO(), sz=0.9)
    cil(0, -0.45, 1.58, 0.2, 0.12, VERDE())
    esfera(0, 0.0, 1.6, 0.16, VERDE(), sz=0.8)
    cil(0, 0.22, 1.66, 0.03, 0.18, ORO())
    parte("faro")
    # el faro delante de la chimenea
    cil(0, -1.33, 1.72, 0.12, 0.18, NEGRO(), eje="y")
    cil(0, -1.43, 1.72, 0.09, 0.03, FARO(), eje="y")
    parte("caldera")
    # pasamanos a los lados de la caldera
    for x in (-0.56, 0.56):
        cil(x, -0.35, 1.3, 0.018, 1.6, ORO(), eje="y", n=8)
        for y in (-1.0, -0.35, 0.3):
            cil(x * 0.97, y, 1.24, 0.012, 0.12, ORO(), n=6)
    parte("cabina")
    # la cabina (rojo con marcos crema), con ventanas de vidrio y techo curvo
    yc = 0.95
    caja(0, yc, 1.25, ANCHO * 0.92, 0.95, 1.25, ROJO(), bisel=0.03)
    for x in (-ANCHO * 0.46, ANCHO * 0.46):
        caja(x, yc - 0.12, 1.45, 0.04, 0.42, 0.4, VIDRIO(), bisel=0.0)
        caja(x, yc - 0.12, 1.45, 0.05, 0.5, 0.05, CREMA(), bisel=0.0)
        caja(x, yc - 0.12, 1.69, 0.05, 0.5, 0.05, CREMA(), bisel=0.0)
        caja(x, yc + 0.3, 1.1, 0.05, 0.3, 0.8, mat("rojo_osc", srgb(140, 22, 20), rug=0.4))
    for x in (-0.38, 0.38):
        caja(x, yc - 0.48, 1.55, 0.36, 0.04, 0.32, VIDRIO(), bisel=0.0)          # las ventanas de delante
        caja(x, yc - 0.49, 1.55, 0.42, 0.05, 0.04, CREMA(), bisel=0.0)
    parte("techo")
    cil(0, yc, 1.95, 0.95, 1.1, NEGRO(), eje="y", n=40).scale = (1, 1, 0.22)
    bpy.ops.object.transform_apply(scale=True)
    caja(0, yc, 1.9, ANCHO * 1.0, 1.1, 0.06, NEGRO())
    parte("quitapiedras")
    # el quitapiedras de delante (rejilla en cuña)
    for k in range(7):
        x = -0.6 + k * 0.2
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, -1.62, 0.3))
        o = bpy.context.active_object
        o.scale = (0.05, 0.42, 0.05)
        o.rotation_euler = (-0.6, 0, -x * 0.5)
        bpy.ops.object.transform_apply(scale=True, rotation=True)
        _fin(o, ROJO())
    caja(0, -1.52, 0.5, 1.4, 0.06, 0.08, ROJO())
    parte("cabina")
    # el numero de la locomotora en una placa de laton a cada lado de la cabina
    for x in (-ANCHO * 0.465, ANCHO * 0.465):
        caja(x, yc + 0.05, 0.95, 0.03, 0.36, 0.2, ORO(), bisel=0.0)
    exportar("locomotora")


def tender():
    limpiar()
    bastidor(0.5)
    bogie(-0.85)
    bogie(0.85)
    parte("caja")
    caja(0, 0, 1.0, ANCHO * 0.9, LARGO * 0.92, 0.85, VERDE(), bisel=0.04)
    caja(0, 0, 1.43, ANCHO * 0.94, LARGO * 0.96, 0.06, ORO(), bisel=0.0)
    for x in (-ANCHO * 0.455, ANCHO * 0.455):                                       # cartela de laton
        caja(x, 0, 0.95, 0.02, 1.8, 0.36, CREMA(), bisel=0.0)
    # el monton de carbon (bultos)
    import random
    rng = random.Random(7)
    parte("carbon")
    for _ in range(30):
        esfera(rng.uniform(-0.6, 0.6), rng.uniform(-1.2, 1.2), 1.45 + rng.uniform(0.0, 0.18), rng.uniform(0.12, 0.22), CARBON())
    parte("caja")
    for k in range(5):                                                               # la escalerilla de atras
        caja(0.7, 1.46, 0.55 + k * 0.18, 0.2, 0.04, 0.03, ACERO(), bisel=0.0)
    exportar("tender")


def pasajeros():
    limpiar()
    bastidor(0.5)
    bogie(-0.9)
    bogie(0.9)
    parte("caja_del")
    caja(0, 0, 1.2, ANCHO * 0.94, LARGO * 0.96, 1.2, AZUL(), bisel=0.04)
    caja(0, 0, 0.75, ANCHO * 0.96, LARGO * 0.97, 0.12, CREMA(), bisel=0.01)          # la franja de abajo
    for x in (-ANCHO * 0.475, ANCHO * 0.475):
        for k in range(4):
            y = -0.9 + k * 0.6
            caja(x, y, 1.35, 0.03, 0.4, 0.42, VIDRIO(), bisel=0.0)
            caja(x, y, 1.58, 0.04, 0.48, 0.05, CREMA(), bisel=0.0)
            caja(x, y, 1.12, 0.04, 0.48, 0.05, CREMA(), bisel=0.0)
        caja(x, 1.38, 1.15, 0.03, 0.06, 0.6, ORO(), bisel=0.0)                      # la manija
    for y in (-LARGO * 0.485, LARGO * 0.485):                                       # las puertas de los extremos
        caja(0, y, 1.15, 0.6, 0.03, 1.0, mat("azul_osc", srgb(22, 46, 104), rug=0.4), bisel=0.0)
        caja(0, y, 1.4, 0.4, 0.04, 0.32, VIDRIO(), bisel=0.0)
    parte("techo")
    cil(0, 0, 1.85, 0.95, LARGO * 1.0, NEGRO(), eje="y", n=40).scale = (1, 1, 0.24)
    bpy.ops.object.transform_apply(scale=True)
    caja(0, 0, 1.8, ANCHO * 1.02, LARGO * 1.0, 0.05, NEGRO())
    for y in (-0.9, 0.0, 0.9):                                                       # las ventilaciones del techo
        cil(0, y, 2.06, 0.1, 0.12, ACERO())
        cil(0, y, 2.13, 0.14, 0.03, ACERO())
    for y in (-LARGO * 0.5, LARGO * 0.5):                                           # faroles de cola
        cil(0.6, y, 1.6, 0.06, 0.1, FARO(), eje="y", n=12)
    exportar("pasajeros")


def troncos():
    limpiar()
    bastidor(0.5, MADERA())
    bogie(-0.9)
    bogie(0.9)
    caja(0, 0, 0.66, ANCHO * 0.94, LARGO * 0.96, 0.1, MADERA_C(), bisel=0.01)
    for k in range(9):                                                               # tablas del piso
        caja(0, -1.3 + k * 0.33, 0.72, ANCHO * 0.92, 0.02, 0.02, MADERA(), bisel=0.0)
    for y in (-1.25, 0.0, 1.25):                                                     # las teleras
        for x in (-0.78, 0.78):
            caja(x, y, 1.15, 0.07, 0.07, 0.9, NEGRO())
    import random
    rng = random.Random(3)
    filas = ((-0.45, 0.95), (0.0, 0.95), (0.45, 0.95), (-0.22, 1.33), (0.22, 1.33), (0.0, 1.7))
    for i, (x, z) in enumerate(filas):
        parte("tronco%d" % i)
        r = rng.uniform(0.19, 0.23)
        cil(x, rng.uniform(-0.05, 0.05), z, r, 2.7, MADERA(), eje="y", n=16)
        for s in (-1, 1):
            cil(x, s * 1.36, z, r * 0.92, 0.02, MADERA_C(), eje="y", n=16)           # el corte con anillos
            cil(x, s * 1.365, z, r * 0.4, 0.02, MADERA(), eje="y", n=12)
    parte("cadenas")
    for y in (-0.7, 0.7):                                                            # las cadenas que los atan
        cil(0, y, 1.3, 0.62, 0.04, ACERO(), eje="y", n=24).scale = (1, 1, 0.9)
        bpy.ops.object.transform_apply(scale=True)
    exportar("troncos")


def plataforma():
    """EL VAGON DE COLA (2026-10-21, pedido: "una parte trasera con piso y muros de metal"): una batea de chapa abierta
    para subirse y pelear dentro. Piso de chapa estriada, cuatro muros de chapa con nervios y remaches, esquineros y
    la luz roja de cola."""
    limpiar()
    bastidor(0.5)
    bogie(-0.9)
    bogie(0.9)
    CHAPA = mat("chapa", srgb(112, 118, 124), metal=0.85, rug=0.45)
    OXIDO = mat("oxido", srgb(150, 76, 40), metal=0.5, rug=0.8)
    caja(0, 0, 0.7, ANCHO * 0.96, LARGO * 0.98, 0.1, CHAPA, bisel=0.01)                 # el piso
    for k in range(14):                                                                 # estrias del piso
        caja(0, -1.35 + k * 0.21, 0.755, ANCHO * 0.9, 0.03, 0.012, mat("estria", srgb(90, 94, 100), metal=0.9, rug=0.4), bisel=0.0)
    alto, g = 0.9, 0.06
    zc = 0.75 + alto * 0.5
    for (nom, cx, cy, sx, sy) in (("muro_izq", -ANCHO * 0.47, 0, g, LARGO * 0.98), ("muro_der", ANCHO * 0.47, 0, g, LARGO * 0.98),
                                  ("muro_delante", 0, -LARGO * 0.48, ANCHO * 0.94, g), ("muro_atras", 0, LARGO * 0.48, ANCHO * 0.94, g)):
        parte(nom)
        caja(cx, cy, zc, sx, sy, alto, CHAPA, bisel=0.01)
        caja(cx, cy, 0.75 + alto, sx * 1.6 if sx < 0.1 else sx, sy * 1.6 if sy < 0.1 else sy, 0.05, OXIDO, bisel=0.0)  # el canto
        largo = sy if sx < 0.1 else sx
        n = 6 if largo > 2 else 3
        for k in range(n):                                                              # los nervios con remaches
            t = -largo * 0.42 + k * (largo * 0.84 / (n - 1))
            if sx < 0.1:
                caja(cx + (0.04 if cx > 0 else -0.04), t, zc, 0.04, 0.07, alto * 0.96, CHAPA, bisel=0.0)
                for zz in (0.85, 1.25, 1.55):
                    esfera(cx + (0.07 if cx > 0 else -0.07), t, zz, 0.02, ACERO())
            else:
                caja(t, cy + (0.04 if cy > 0 else -0.04), zc, 0.07, 0.04, alto * 0.96, CHAPA, bisel=0.0)
        if nom == "muro_atras":
            cil(0.62, cy + 0.06, 1.5, 0.07, 0.06, mat("cola", srgb(255, 40, 30), emite=4.0), eje="y", n=12)
            cil(-0.62, cy + 0.06, 1.5, 0.07, 0.06, mat("cola", srgb(255, 40, 30), emite=4.0), eje="y", n=12)
    parte("chasis")
    for (x, y) in ((-ANCHO * 0.47, -LARGO * 0.48), (ANCHO * 0.47, -LARGO * 0.48), (-ANCHO * 0.47, LARGO * 0.48), (ANCHO * 0.47, LARGO * 0.48)):
        caja(x, y, zc, 0.1, 0.1, alto + 0.08, OXIDO, bisel=0.01)                         # los esquineros
    exportar("plataforma")


locomotora()
tender()
pasajeros()
troncos()
plataforma()
