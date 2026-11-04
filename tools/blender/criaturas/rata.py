"""LA RATA (2026-10-21, pedido: "crea en blender una rata con sus animaciones, que salga y persiga a los jugadores,
enemigo de todos; real la rata"). Para LA HABITACION (mapa cuarto, a escala x20): una rata de verdad mide 20 cm de
cuerpo y otros 20 de cola, aqui 4 + 4 m. NO es de voxels como los infectados: es una malla lisa y organica (metabolas
convertidas a malla y reducidas) para que parezca una rata de verdad, con el color en los VERTICES (el juego les pone
el material de color de vertice: criatura.gd).

blender -b --python tools/blender/criaturas/rata.py -- <salida.glb> [carpeta_vistas]

Mira a -Y y no se desplaza en horizontal (el juego la mueve), como las demas criaturas. Esqueleto: raiz, cadera,
pecho, cuello, cabeza, mandibula, seis de cola y cuatro patas de tres huesos. Pesos a mano (los dos huesos mas
cercanos a cada vertice: el calculo automatico de Blender falla con mallas de metabolas). Clips, cada uno su pista NLA
(se exportan como animaciones con su nombre): reposo, caminar, correr, ataque, dano, muerte, chillido.
"""
import bpy, math, os, random, sys
from mathutils import Vector, Matrix, Euler

args = sys.argv[sys.argv.index("--") + 1:]
SALIDA = args[0]
VISTAS = args[1] if len(args) > 1 else ""
FPS = 30

# ------------------------------------------------------------------------------------------------ la escena
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.fps = FPS
col = bpy.context.collection


def ellipsoide(mb, p, r, stiff=2.0, neg=False):
    e = mb.elements.new(type='ELLIPSOID')
    e.co = Vector(p)
    e.radius = 1.0
    e.size_x, e.size_y, e.size_z = r
    e.stiffness = stiff
    e.use_negative = neg
    return e


# --- EL CUERPO: piezas que se solapan (esferas estiradas y capsulas) y luego se FUNDEN en una sola malla lisa ------
# (remallado por voxels y suavizado; con metabolas las patas, las orejas y la cola salian sueltas)
partes = []


def bola(p, r):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1.0, location=p, segments=24, ring_count=14)
    o = bpy.context.active_object
    o.scale = r
    partes.append(o)


def capsula(a, b, r):
    a, b = Vector(a), Vector(b)
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=d.length, vertices=16, location=(a + b) * 0.5)
    o = bpy.context.active_object
    o.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
    partes.append(o)
    bola(a, (r, r, r))
    bola(b, (r, r, r))


bola((0, 0.55, 0.78), (0.72, 0.95, 0.62))         # la cadera (lo mas gordo)
bola((0, -0.3, 0.8), (0.6, 0.9, 0.56))            # el pecho
bola((0, -1.05, 0.88), (0.42, 0.55, 0.42))        # el cuello
bola((0, -1.6, 0.92), (0.38, 0.55, 0.36))         # la cabeza
bola((0, -2.1, 0.82), (0.22, 0.48, 0.2))          # el hocico
bola((0, -2.46, 0.77), (0.11, 0.18, 0.1))         # la punta
for sx in (-1, 1):
    bola((sx * 0.3, -1.4, 1.3), (0.26, 0.07, 0.28))                    # las OREJAS, redondas y finas
    bola((sx * 0.27, -1.86, 1.0), (0.085, 0.085, 0.085))               # el bulto del ojo
    capsula((sx * 0.36, -0.9, 0.72), (sx * 0.4, -1.04, 0.34), 0.13)   # el brazo
    capsula((sx * 0.4, -1.04, 0.34), (sx * 0.41, -1.12, 0.08), 0.08)  # el antebrazo
    bola((sx * 0.41, -1.25, 0.05), (0.1, 0.18, 0.05))                  # la mano
    bola((sx * 0.5, 0.72, 0.58), (0.28, 0.42, 0.4))                    # el muslo
    capsula((sx * 0.55, 0.66, 0.36), (sx * 0.57, 0.88, 0.1), 0.1)     # la pierna
    bola((sx * 0.57, 0.58, 0.05), (0.11, 0.34, 0.05))                  # el pie, largo hacia delante
bpy.ops.object.select_all(action='DESELECT')
for o in partes:
    o.select_set(True)
bpy.context.view_layer.objects.active = partes[0]
bpy.ops.object.join()
cuerpo = bpy.context.active_object
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
cuerpo.name = "Rata"
rm = cuerpo.modifiers.new("remesh", 'REMESH')
rm.mode = 'VOXEL'
rm.voxel_size = 0.045
bpy.ops.object.modifier_apply(modifier="remesh")
sm = cuerpo.modifiers.new("suave", 'SMOOTH')
sm.factor = 0.6
sm.iterations = 6
bpy.ops.object.modifier_apply(modifier="suave")

# --- LA COLA: una curva que cae y se va afinando, a malla ----------------------------------------------------------
cd = bpy.data.curves.new("Cola", 'CURVE')
cd.dimensions = '3D'
cd.bevel_depth = 0.11
cd.bevel_resolution = 3
sp = cd.splines.new('POLY')
N_COLA = 14
sp.points.add(N_COLA - 1)
for i in range(N_COLA):
    k = i / (N_COLA - 1)
    sp.points[i].co = (0.18 * math.sin(k * 2.6), 1.2 + k * 4.15, max(0.1, 0.72 - 0.95 * k + 0.35 * k * k), 1.0)
    sp.points[i].radius = 1.0 - 0.85 * k
cola = bpy.data.objects.new("Cola", cd)
col.objects.link(cola)
bpy.ops.object.select_all(action='DESELECT')
bpy.context.view_layer.objects.active = cola
cola.select_set(True)
bpy.ops.object.convert(target='MESH')
cola = bpy.context.view_layer.objects.active

# --- los OJOS (negros y brillantes), la NARIZ rosa y los BIGOTES ------------------------------------------------------
piezas = []
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.07, location=(0, -2.6, 0.78), segments=10, ring_count=6)
piezas.append(("nariz", bpy.context.active_object))
rng = random.Random(7)
for sx in (-1, 1):
    for k in range(4):
        a = math.radians(-12 + k * 9)
        largo = rng.uniform(0.7, 0.95)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.008, depth=largo, vertices=4,
                                            location=(sx * (0.16 + largo * 0.45 * math.cos(a)), -2.4 + largo * 0.25, 0.76 + largo * 0.45 * math.sin(a)))
        o = bpy.context.active_object
        o.rotation_euler = (0.0, math.pi / 2 - sx * a, sx * 0.5)
        piezas.append(("bigote", o))

# --- reducir el cuerpo (las metabolas dan muchisimos triangulos) y juntar ------------------------------------------
bpy.ops.object.select_all(action='DESELECT')
bpy.context.view_layer.objects.active = cuerpo
cuerpo.select_set(True)
m = cuerpo.modifiers.new("dec", 'DECIMATE')
m.ratio = min(1.0, 9000.0 / max(1, len(cuerpo.data.polygons)))
bpy.ops.object.modifier_apply(modifier="dec")
bpy.ops.object.shade_smooth()

# el COLOR, por vertice (antes de juntar: asi cada pieza tiene el suyo)
PELO = (0.30, 0.26, 0.23)
PELO_OSC = (0.18, 0.15, 0.13)
PANZA = (0.62, 0.56, 0.50)
ROSA = (0.86, 0.58, 0.56)
ROSA_OSC = (0.70, 0.45, 0.44)


def mezcla(a, b, t):
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(3))


def pintar(obj, fn):
    me = obj.data
    ca = me.color_attributes.new("Col", 'FLOAT_COLOR', 'POINT')
    for v in me.vertices:
        c = fn(obj.matrix_world @ v.co)
        # (los colores de arriba son sRGB; el atributo es LINEAL y el juego lo lee tal cual: sin pasarlo, salia desteñida)
        ca.data[v.index].color = (c[0] ** 2.2, c[1] ** 2.2, c[2] ** 2.2, 1.0)
    me.color_attributes.active_color = ca


ruido = random.Random(3)


def color_cuerpo(p):
    x, y, z = p
    # la panza (abajo y por dentro) mas clara; el lomo un pelin mas oscuro; manchas de pelo al azar
    t_panza = max(0.0, min(1.0, (0.55 - z) / 0.35)) * max(0.0, 1.0 - abs(x) / 0.55)
    c = mezcla(PELO, PANZA, t_panza)
    if z > 1.2 and abs(x) < 0.25:
        c = mezcla(c, PELO_OSC, 0.35)
    j = ruido.uniform(-0.035, 0.035)
    c = tuple(max(0.0, min(1.0, v + j)) for v in c)
    # las OREJAS, rosadas por dentro; las MANOS y los PIES, rosas; el HOCICO, algo mas claro
    if z > 1.12 and abs(abs(x) - 0.36) < 0.3 and abs(y + 1.35) < 0.18:
        c = mezcla(c, ROSA, 0.8)
    if z < 0.13:
        c = mezcla(c, ROSA, 0.85)
    if y < -2.3:
        c = mezcla(c, ROSA_OSC, 0.4)
    for sx in (-1, 1):                                       # los OJOS, negros y brillantes
        if (Vector(p) - Vector((sx * 0.27, -1.86, 1.0))).length < 0.1:
            c = (0.015, 0.015, 0.02)
    if z > 1.1 and abs(y + 1.4) < 0.1 and abs(abs(x) - 0.3) < 0.24:   # el dentro de la oreja, mas rosa
        c = mezcla(c, ROSA, 0.9)
    return c


pintar(cuerpo, color_cuerpo)
pintar(cola, lambda p: mezcla(ROSA_OSC, (0.6, 0.48, 0.45), min(1.0, (p[1] - 1.3) / 4.0)))
for nombre, o in piezas:
    pintar(o, lambda p, n=nombre: (0.02, 0.02, 0.025) if n == "ojo" else (ROSA if n == "nariz" else (0.85, 0.82, 0.78)))
bpy.ops.object.select_all(action='DESELECT')
for o in [cola] + [o for _, o in piezas]:
    o.select_set(True)
cuerpo.select_set(True)
bpy.context.view_layer.objects.active = cuerpo
bpy.ops.object.join()
malla = cuerpo
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# ------------------------------------------------------------------------------------------------ el esqueleto
arm = bpy.data.armatures.new("RataRig")
rig = bpy.data.objects.new("RataRig", arm)
col.objects.link(rig)
bpy.ops.object.select_all(action='DESELECT')
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
B = {}


def hueso(nombre, cab, pun, padre=None, deform=True):
    b = arm.edit_bones.new(nombre)
    b.head = Vector(cab)
    b.tail = Vector(pun)
    b.roll = 0.0
    b.use_deform = deform
    if padre:
        b.parent = arm.edit_bones[padre]
    B[nombre] = (Vector(cab), Vector(pun))
    return b


hueso("raiz", (0, 0.3, 0.8), (0, -0.1, 0.8), deform=False)
hueso("cadera", (0, 1.25, 0.8), (0, 0.25, 0.85), "raiz")
hueso("pecho", (0, 0.25, 0.85), (0, -0.95, 0.9), "raiz")
hueso("cuello", (0, -0.95, 0.9), (0, -1.4, 0.95), "pecho")
hueso("cabeza", (0, -1.4, 0.95), (0, -2.65, 0.78), "cuello")
hueso("mandibula", (0, -1.75, 0.7), (0, -2.45, 0.62), "cabeza")
cpts = [Vector((0.18 * math.sin(k * 2.6), 1.35 + k * 4.0, max(0.1, 0.72 - 0.95 * k + 0.35 * k * k))) for k in [i / 6 for i in range(7)]]
for i in range(6):
    hueso("cola%d" % (i + 1), cpts[i], cpts[i + 1], "cadera" if i == 0 else "cola%d" % i)
for lado, sx in (("l", 1), ("r", -1)):
    x = sx * 0.39
    hueso("brazo_" + lado, (x, -0.92, 0.78), (x, -1.02, 0.38), "pecho")
    hueso("antebrazo_" + lado, (x, -1.02, 0.38), (x, -1.1, 0.1), "brazo_" + lado)
    hueso("mano_" + lado, (x, -1.1, 0.08), (x, -1.36, 0.04), "antebrazo_" + lado)
    x = sx * 0.56
    hueso("muslo_" + lado, (x, 0.85, 0.75), (x, 0.62, 0.36), "cadera")
    hueso("pierna_" + lado, (x, 0.62, 0.36), (x, 0.9, 0.1), "muslo_" + lado)
    hueso("pie_" + lado, (x, 0.9, 0.07), (x, 0.3, 0.03), "pierna_" + lado)
bpy.ops.object.mode_set(mode='OBJECT')

# --- LOS PESOS: los dos huesos mas cercanos a cada vertice (1/d^4) -------------------------------------------------
DEF = [n for n in B if n != "raiz"]
grupos = {n: malla.vertex_groups.new(name=n) for n in DEF}


def dist_seg(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - p).length


PATAS = [n for n in DEF if n.split("_")[0] in ("brazo", "antebrazo", "mano", "muslo", "pierna", "pie")]
TRONCO = [n for n in DEF if n not in PATAS]
for v in malla.data.vertices:
    p = v.co
    # el TRONCO (cadera, pecho, cuello, cabeza, mandibula, cola): los tres mas cercanos, 1/d^2 (blando: sin costuras)
    ds = []
    for n in TRONCO:
        a, b = B[n]
        d = dist_seg(p, a, b)
        if n.startswith("cola") and p.y < 1.2:
            d += 1.5
        if n == "mandibula" and (p.z > 0.72 or p.y > -1.7):
            d += 1.5
        ds.append((d, n))
    ds.sort()
    wt = [(1.0 / max(d, 0.05) ** 2, n) for d, n in ds[:3]]
    tt = sum(x for x, _ in wt)
    pesos = {n: x / tt for x, n in wt}
    # LAS PATAS, del lado del vertice: cuanto mas cerca del hueso, mas manda (de 0,42 m a 0,18 m pasa de 0 a 1)
    dp = []
    for n in PATAS:
        if (n.endswith("_l") and p.x < 0.0) or (n.endswith("_r") and p.x > 0.0):
            continue
        a, b = B[n]
        dp.append((dist_seg(p, a, b), n))
    dp.sort()
    if dp:
        wl = max(0.0, min(1.0, (0.42 - dp[0][0]) / 0.24))
        wl = wl * wl * (3 - 2 * wl)
        if wl > 0.0:
            wp = [(1.0 / max(d, 0.03) ** 2, n) for d, n in dp[:2]]
            tp = sum(x for x, _ in wp)
            for n in list(pesos):
                pesos[n] *= 1.0 - wl
            for x, n in wp:
                pesos[n] = pesos.get(n, 0.0) + wl * x / tp
    for n, x in pesos.items():
        if x > 0.001:
            grupos[n].add([v.index], x, 'REPLACE')
mod = malla.modifiers.new("Rig", 'ARMATURE')
mod.object = rig
malla.parent = rig

# ------------------------------------------------------------------------------------------------ las animaciones
rig.animation_data_create()
pb = rig.pose.bones
for b in pb:
    b.rotation_mode = 'XYZ'
CLIPS = []


def clip(nombre, frames, fn, bucle=True):
    """`fn(t)` (0..1) devuelve {hueso: (rx, ry, rz)} y, si quiere, "z_raiz"; se clava en cada frame"""
    act = bpy.data.actions.new(nombre)
    rig.animation_data.action = act
    for f in range(frames + 1):
        t = f / frames
        pose = fn(t)
        for b in pb:
            r = pose.get(b.name, (0.0, 0.0, 0.0))
            b.rotation_euler = Euler(r, 'XYZ')
            b.keyframe_insert("rotation_euler", frame=f + 1)
            if b.name == "raiz":
                b.location = (0.0, float(pose.get("raiz_y", 0.0)), float(pose.get("raiz_z", 0.0)))
                b.keyframe_insert("location", frame=f + 1)
    tr = rig.animation_data.nla_tracks.new()
    tr.name = nombre
    st = tr.strips.new(nombre, 1, act)
    st.name = nombre
    rig.animation_data.action = None
    CLIPS.append((nombre, frames, bucle))


S = math.sin
TAU = math.tau


def cola_ondula(t, amp, fase=0.0, rapidez=1.0):
    return {"cola%d" % (i + 1): (0.03 * S(TAU * (t * rapidez) + i), 0.0, amp * S(TAU * (t * rapidez) - i * 0.55 + fase)) for i in range(6)}


def reposo(t):
    p = cola_ondula(t, 0.06)
    p["pecho"] = (0.02 * S(TAU * t * 2), 0, 0)                      # respira
    p["cabeza"] = (0.05 * S(TAU * t * 6) + 0.06, 0, 0.12 * S(TAU * t))   # olfatea y mira
    p["cuello"] = (0.03 * S(TAU * t), 0, 0.06 * S(TAU * t))
    p["mandibula"] = (0.04 * max(0.0, S(TAU * t * 6)), 0, 0)
    return p


def andar(t, amp, rapidez, bound=False):
    p = cola_ondula(t, 0.1 if not bound else 0.05, rapidez=rapidez)
    for lado, f_del, f_tra in (("l", 0.0, 0.5 if not bound else 0.0), ("r", 0.5 if not bound else 0.0, 0.0 if not bound else 0.0)):
        fd = f_del if not bound else 0.0
        ft = f_tra if not bound else 0.5
        a = TAU * (t * rapidez + fd)
        p["brazo_" + lado] = (amp * S(a), 0, 0)
        p["antebrazo_" + lado] = (-amp * 0.9 * max(0.0, S(a + 1.2)), 0, 0)
        p["mano_" + lado] = (amp * 0.6 * max(0.0, -S(a)), 0, 0)
        b = TAU * (t * rapidez + ft)
        p["muslo_" + lado] = (-amp * 1.1 * S(b), 0, 0)
        p["pierna_" + lado] = (amp * 0.9 * max(0.0, S(b + 1.3)), 0, 0)
        p["pie_" + lado] = (-amp * 0.7 * max(0.0, -S(b)), 0, 0)
    flex = 0.06 if bound else 0.02
    p["pecho"] = (flex * S(TAU * t * rapidez * (1 if bound else 2)), 0, 0)
    p["cadera"] = (-flex * S(TAU * t * rapidez * (1 if bound else 2)), 0, 0)
    p["cabeza"] = (0.06 * S(TAU * t * rapidez * 2), 0, 0)
    p["raiz_z"] = (0.08 if bound else 0.03) * abs(S(TAU * t * rapidez * (1 if bound else 2)))
    return p


def ataque(t):
    # se echa hacia atras, se lanza estirando el cuello y MUERDE (la boca se abre y cierra al 45 %)
    p = cola_ondula(t, 0.15, rapidez=2)
    k = S(min(1.0, t / 0.45) * math.pi * 0.5)
    atras = max(0.0, 1.0 - t / 0.2) if t < 0.2 else 0.0
    p["pecho"] = (0.35 * atras - 0.15 * k * (1 - max(0.0, (t - 0.6) / 0.4)), 0, 0)
    p["cuello"] = (-0.25 * k, 0, 0)
    p["cabeza"] = (-0.2 * k + 0.3 * atras, 0, 0)
    boca = max(0.0, S(min(1.0, max(0.0, (t - 0.15) / 0.35)) * math.pi))
    p["mandibula"] = (0.55 * boca, 0, 0)
    for lado in ("l", "r"):
        p["brazo_" + lado] = (-0.6 * k + 0.4 * atras, 0, 0)
        p["antebrazo_" + lado] = (0.5 * k, 0, 0)
    p["raiz_y"] = -0.45 * k + 0.2 * atras
    return p


def dano(t):
    p = cola_ondula(t, 0.25, rapidez=3)
    g = S(min(1.0, t / 0.3) * math.pi) * (1 - t)
    p["pecho"] = (0.25 * g, 0.3 * g, 0)
    p["cabeza"] = (0.3 * g, 0, 0.25 * g)
    p["mandibula"] = (0.4 * g, 0, 0)
    return p


def muerte(t):
    # cae de lado (la raiz gira sobre su eje largo), patas tiesas
    k = min(1.0, t / 0.55)
    k = 1 - (1 - k) ** 3
    p = {"raiz": (0.0, -1.5 * k, 0.0), "raiz_z": -0.38 * k}
    for lado in ("l", "r"):
        p["brazo_" + lado] = (-0.5 * k, 0, 0)
        p["muslo_" + lado] = (0.6 * k, 0, 0)
        p["pierna_" + lado] = (-0.4 * k, 0, 0)
    p["cabeza"] = (0.2 * k, 0, 0)
    p["mandibula"] = (0.3 * k, 0, 0)
    for i in range(6):
        p["cola%d" % (i + 1)] = (0, 0, 0.12 * k * (i + 1) * 0.3)
    return p


def chillido(t):
    p = reposo(t)
    k = S(t * math.pi)
    p["cuello"] = (-0.35 * k, 0, 0)
    p["cabeza"] = (-0.3 * k, 0, 0)
    p["mandibula"] = (0.5 * k * (0.7 + 0.3 * S(TAU * t * 8)), 0, 0)
    p["pecho"] = (0.2 * k, 0, 0)
    return p


clip("reposo", 60, reposo)
clip("caminar", 30, lambda t: andar(t, 0.45, 1.0))
clip("correr", 18, lambda t: andar(t, 0.75, 1.0, bound=True))
clip("ataque", 24, ataque, bucle=False)
clip("dano", 12, dano, bucle=False)
clip("muerte", 36, muerte, bucle=False)
clip("chillido", 30, chillido, bucle=False)

# ------------------------------------------------------------------------------------------------ las vistas
if VISTAS:
    os.makedirs(VISTAS, exist_ok=True)
    cam_d = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cam_d)
    col.objects.link(cam)
    sc.camera = cam
    sol = bpy.data.lights.new("Sol", 'SUN')
    sol.energy = 3.0
    lo = bpy.data.objects.new("Sol", sol)
    lo.rotation_euler = (0.8, 0.2, 0.6)
    col.objects.link(lo)
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.color_type = 'VERTEX'
    sc.display.shading.light = 'STUDIO'
    sc.render.resolution_x, sc.render.resolution_y = 900, 600
    world = bpy.data.worlds.new("W")
    sc.world = world
    for (nombre, frame, pos, mira) in (("reposo", 10, (4.5, -4.5, 2.4), (0, -0.2, 0.7)), ("lado", 10, (6.5, 0.6, 1.2), (0, 0.6, 0.7)),
                                       ("caminar", 8, (5.0, -3.0, 2.0), (0, 0, 0.7)), ("correr", 6, (5.0, -3.0, 2.0), (0, 0, 0.7)),
                                       ("ataque", 11, (4.0, -5.0, 2.0), (0, -1.2, 0.8)), ("muerte", 36, (4.5, -4.0, 3.0), (0, 0, 0.4)),
                                       ("cara", 10, (0.6, -4.6, 1.3), (0, -1.8, 0.9))):
        clipn = nombre if nombre in [c[0] for c in CLIPS] else "reposo"
        for tr in rig.animation_data.nla_tracks:
            tr.mute = tr.name != clipn
        sc.frame_set(frame)
        cam.location = pos
        d = Vector(mira) - Vector(pos)
        cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = os.path.join(VISTAS, "rata_%s.png" % nombre)
        bpy.ops.render.render(write_still=True)
    for tr in rig.animation_data.nla_tracks:
        tr.mute = False
    bpy.data.objects.remove(cam, do_unlink=True)
    bpy.data.objects.remove(lo, do_unlink=True)

# ------------------------------------------------------------------------------------------------ exportar
bpy.ops.object.select_all(action='DESELECT')
malla.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
opts = dict(filepath=SALIDA, export_format='GLB', use_selection=True, export_animations=True,
            export_animation_mode='NLA_TRACKS', export_skins=True, export_yup=True, export_apply=False)
try:
    bpy.ops.export_scene.gltf(**opts, export_vertex_color='ACTIVE')
except TypeError:
    bpy.ops.export_scene.gltf(**opts)
print("RATA_OK", SALIDA, len(malla.data.polygons), "caras", [c[0] for c in CLIPS])
