"""ZOMBIS del modo PvE en voxels: zombi comun, corredor y bruto, con esqueleto y animaciones.

blender -b --python tools/blender/criaturas/zombis.py -- <tipo> <salida.blend> [soldado_breach.blend]
    tipo: zombi | corredor | bruto

Mismo esqueleto humano para los tres (escalado y engordado segun el tipo), voxels por hueso
(voxelizar.py) y clips seguidos en la linea de tiempo con sus rangos en la escena, como el Goliat:
reposo, caminar, correr, ataque, dano y muerte.
"""
import bpy, json, math, os, sys
from mathutils import Vector, Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import organico as O
import voxelizar as V

args = sys.argv[sys.argv.index("--") + 1:]
TIPO, SALIDA = args[0], args[1]
SOLDADO = args[2] if len(args) > 2 else ""

#            escala  grosor  brazos  voxel   encorvado
TIPOS = {"zombi": (1.0, 1.0, 1.0, 0.045, 0.0),
         "corredor": (0.96, 0.8, 1.0, 0.045, 1.0),
         "bruto": (1.45, 1.7, 1.55, 0.06, 0.6)}
S, G, GA, VOX, ENC = TIPOS[TIPO]

PIEL = (0.46, 0.55, 0.42) if TIPO != "corredor" else (0.52, 0.50, 0.44)
PIEL_OSC = (0.33, 0.40, 0.31)
CAMISA = (0.30, 0.34, 0.42) if TIPO == "zombi" else (0.28, 0.24, 0.20)
PANTALON, SANGRE, HUESO = (0.22, 0.20, 0.17), (0.42, 0.04, 0.03), (0.86, 0.83, 0.72)
OJO, BOCA, DIENTE, PELO = (1.0, 0.85, 0.25), (0.20, 0.03, 0.03), (0.80, 0.78, 0.60), (0.10, 0.09, 0.08)
ZAPATO = (0.15, 0.12, 0.10)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.fps = 30
col = sc.collection


def P(x, y, z):
    return (x * S, y * S, z * S)


# ================================================================ ESQUELETO
H = {"root": ((0, 0, 0), (0, 0, 0.3 * S), None),
     "pelvis": (P(0, 0, 0.95), P(0, -0.02, 1.12), "root"),
     "spine": (P(0, -0.02, 1.12), P(0, -0.06, 1.38), "pelvis"),
     "chest": (P(0, -0.06, 1.38), P(0, -0.08, 1.58), "spine"),
     "neck": (P(0, -0.08, 1.58), P(0, -0.10, 1.68), "chest"),
     "head": (P(0, -0.10, 1.68), P(0, -0.12, 1.92), "neck"),
     "jaw": (P(0, -0.12, 1.71), P(0, -0.24, 1.67), "head")}
for s, x in (("l", 1), ("r", -1)):
    H.update({
        "shoulder_" + s: (P(0.06 * x, -0.07, 1.54), P(0.20 * x * G ** 0.5, -0.07, 1.55), "chest"),
        "upperarm_" + s: (P(0.20 * x * G ** 0.5, -0.07, 1.55), P(0.25 * x * G ** 0.5, -0.12, 1.27), "shoulder_" + s),
        "forearm_" + s: (P(0.25 * x * G ** 0.5, -0.12, 1.27), P(0.28 * x * G ** 0.5, -0.30, 1.08), "upperarm_" + s),
        "hand_" + s: (P(0.28 * x * G ** 0.5, -0.30, 1.08), P(0.29 * x * G ** 0.5, -0.42, 1.00), "forearm_" + s),
        "thigh_" + s: (P(0.11 * x * G ** 0.5, 0.0, 0.93), P(0.12 * x * G ** 0.5, -0.04, 0.52), "pelvis"),
        "shin_" + s: (P(0.12 * x * G ** 0.5, -0.04, 0.52), P(0.12 * x * G ** 0.5, 0.02, 0.10), "thigh_" + s),
        "foot_" + s: (P(0.12 * x * G ** 0.5, 0.02, 0.10), P(0.12 * x * G ** 0.5, -0.14, 0.03), "shin_" + s),
        "IK_foot_" + s: (P(0.12 * x * G ** 0.5, 0.02, 0.10), P(0.12 * x * G ** 0.5, -0.14, 0.03), None),
        "POLE_knee_" + s: (P(0.14 * x * G ** 0.5, -0.6, 0.55), P(0.14 * x * G ** 0.5, -0.6, 0.7), "IK_foot_" + s),
    })
CONTROL = [n for n in H if n.startswith(("IK_", "POLE_"))] + ["root"]
rig = O.armature("Zombi_Rig", H, col, CONTROL)
PB, BN = rig.pose.bones, rig.data.bones
cadenas = []
for s in "lr":
    c = PB["shin_" + s].constraints.new('IK')
    c.target, c.subtarget, c.pole_target, c.pole_subtarget = rig, "IK_foot_" + s, rig, "POLE_knee_" + s
    c.chain_count = 2
    cr = PB["foot_" + s].constraints.new('COPY_ROTATION')
    cr.target, cr.subtarget = rig, "IK_foot_" + s
    cadenas.append((c, "thigh_" + s, "shin_" + s, "POLE_knee_" + s))


def _prep():
    PB["pelvis"].location = (0, -0.15 * S, 0)


def _undo():
    PB["pelvis"].location = (0, 0, 0)


O.calibrar_polos(rig, cadenas, _prep, _undo)

# ================================================================ FORMAS
g = G
cuerpo = O.Pieza("Cuerpo")
cuerpo.elip(P(0, 0, 0.98), (0.17 * S * g, 0.12 * S * g, 0.12 * S), PANTALON)
cuerpo.elip(P(0, -0.04, 1.2), (0.16 * S * g, 0.12 * S * g, 0.16 * S), CAMISA if TIPO != "corredor" else PIEL)
cuerpo.elip(P(0, -0.07, 1.45), (0.2 * S * g, 0.13 * S * g, 0.17 * S), CAMISA if TIPO != "corredor" else PIEL)
cuerpo.elip(P(0.08, -0.07 - 0.12 * g, 1.3), (0.08 * S, 0.03 * S, 0.09 * S), PIEL_OSC, prio=1)
for i, z in enumerate((1.26, 1.31, 1.36)):
    cuerpo.cap(P(0.03, -0.07 - 0.13 * g, z), P(0.13, -0.07 - 0.11 * g, z + 0.01), 0.011 * S, 0.011 * S, HUESO, prio=2)
cuerpo.elip(P(-0.08, -0.07 - 0.125 * g, 1.42), (0.07 * S, 0.02 * S, 0.1 * S), SANGRE, prio=1)
cuerpo.cap(P(0, -0.08, 1.56), P(0, -0.1, 1.7), 0.06 * S * g ** 0.5, 0.055 * S, PIEL)
if TIPO == "corredor":
    for i in range(5):                                           # la columna asoma por la espalda
        cuerpo.elip(P(0, 0.06 * g + 0.02, 1.15 + i * 0.08), (0.02 * S, 0.02 * S, 0.02 * S), HUESO, prio=2)
if TIPO == "bruto":
    cuerpo.elip(P(0, 0.02, 1.52), (0.24 * S * g, 0.16 * S * g, 0.14 * S), PIEL_OSC)      # joroba
for x in (1,):
    cuerpo.elip(P(0.18 * x * g ** 0.5, -0.07, 1.53), (0.08 * S * g, 0.08 * S * g, 0.07 * S * g), CAMISA if TIPO == "zombi" else PIEL)
    ua = (P(0.20 * x * g ** 0.5, -0.07, 1.55), P(0.25 * x * g ** 0.5, -0.12, 1.27))
    cuerpo.cap(*ua, 0.055 * S * g * GA ** 0.5, 0.045 * S * g * GA ** 0.5, PIEL)
    if TIPO == "zombi":
        cuerpo.cap(ua[0], P(0.23 * x * g ** 0.5, -0.1, 1.42), 0.062 * S * g, 0.058 * S * g, CAMISA)
    cuerpo.cap(P(0.25 * x * g ** 0.5, -0.12, 1.27), P(0.28 * x * g ** 0.5, -0.30, 1.08), 0.045 * S * g * GA, 0.04 * S * g * GA, PIEL)
    mano = P(0.29 * x * g ** 0.5, -0.37, 1.03)
    cuerpo.elip(mano, (0.04 * S * GA * g, 0.06 * S * GA, 0.05 * S * GA * g), PIEL_OSC)
    for dx in (-0.025, 0.0, 0.025):
        cuerpo.cono(P(0.29 * x * g ** 0.5 + dx * GA, -0.42, 1.0), P(0.29 * x * g ** 0.5 + dx * GA * 1.2, -0.47, 0.96),
                    0.012 * S * GA, HUESO if TIPO != "zombi" else PIEL_OSC)
    cuerpo.cap(P(0.11 * x * g ** 0.5, 0.0, 0.93), P(0.12 * x * g ** 0.5, -0.04, 0.52), 0.08 * S * g, 0.065 * S * g, PANTALON)
    cuerpo.cap(P(0.12 * x * g ** 0.5, -0.04, 0.52), P(0.12 * x * g ** 0.5, 0.02, 0.10), 0.06 * S * g, 0.045 * S * g, PANTALON)
    cuerpo.elip(P(0.13 * x * g ** 0.5, -0.1, 0.35), (0.04 * S * g, 0.03 * S, 0.06 * S), PIEL, prio=1)      # roto
    cuerpo.elip(P(0.12 * x * g ** 0.5, -0.05, 0.05), (0.05 * S * g, 0.11 * S, 0.05 * S), ZAPATO)
cuerpo.espejo()

cabeza = O.Pieza("Cabeza")
cabeza.elip(P(0, -0.12, 1.8), (0.10 * S, 0.11 * S, 0.12 * S), PIEL)
cabeza.elip(P(0.02, -0.08, 1.9), (0.09 * S, 0.09 * S, 0.04 * S), PELO, prio=1)
cabeza.elip(P(-0.07, -0.15, 1.86), (0.04 * S, 0.03 * S, 0.04 * S), SANGRE, prio=1)
cabeza.elip(P(0, -0.23, 1.78), (0.015 * S, 0.02 * S, 0.02 * S), PIEL_OSC, prio=1)
cabeza.elip(P(0, -0.16, 1.74), (0.06 * S, 0.05 * S, 0.015 * S), BOCA)
cabeza.elip(P(0.04, -0.205, 1.82), (0.03 * S, 0.02 * S, 0.025 * S), (0.05, 0.03, 0.03), prio=1)
cabeza.elip(P(0.04, -0.215, 1.82), (0.018 * S, 0.012 * S, 0.015 * S), OJO, brillo=5.0, prio=2)
for i in range(-2, 3):
    cabeza.cono(P(i * 0.018, -0.215, 1.748), P(i * 0.018, -0.222, 1.725), 0.008 * S, DIENTE, prio=2)
cabeza.espejo()

mandibula = O.Pieza("Mandibula")
mandibula.elip(P(0, -0.17, 1.69), (0.075 * S, 0.08 * S, 0.035 * S), PIEL)
mandibula.elip(P(0, -0.17, 1.712), (0.055 * S, 0.06 * S, 0.01 * S), BOCA, prio=1)
for i in range(-2, 3):
    mandibula.cono(P(i * 0.017, -0.225, 1.705), P(i * 0.017, -0.23, 1.728), 0.007 * S, DIENTE, prio=2)
mandibula.cap(P(0.02, -0.235, 1.68), P(0.03, -0.24, 1.6), 0.012 * S, 0.006 * S, SANGRE, prio=2)

PIEZAS = [(cuerpo, None), (cabeza, "head"), (mandibula, "jaw")]
HUESOS_CUERPO = [n for n in H if n not in CONTROL and n != "jaw"]
piezas, caras = V.voxelizar(PIEZAS, VOX, rig, col, HUESOS_CUERPO, arrugas=0.4, material=O.material())

# ================================================================ ANIMACIONES
_ult = {}


def _q(n, q):
    if n in _ult and _ult[n].dot(q) < 0:
        q.negate()
    _ult[n] = q
    return q


def _clave(n, pose, f):
    b = BN[n]
    base = b.matrix_local.inverted() @ pose
    loc, q, _ = base.decompose()
    PB[n].location, PB[n].rotation_quaternion = loc, _q(n, q)
    PB[n].keyframe_insert("location", frame=f)
    PB[n].keyframe_insert("rotation_quaternion", frame=f)


GIRO = ["pelvis", "spine", "chest", "neck", "head", "jaw"] + \
       [b + s for b in ("shoulder_", "upperarm_", "forearm_", "hand_") for s in "lr"]
PIVOTE = BN["pelvis"].head_local


def poner(pose, F):
    r = pose.get("root", (0, 0, 0, 0, 0, 0))
    _clave("root", Matrix.Translation(Vector(r[:3]) * S) @ Matrix.Translation(PIVOTE) @ O.rot(*r[3:])
           @ Matrix.Translation(-PIVOTE) @ BN["root"].matrix_local, F)
    for n in GIRO:
        gr = pose.get(n, (0, 0, 0))
        rq = BN[n].matrix_local.to_quaternion()
        PB[n].rotation_quaternion = _q(n, rq.inverted() @ O.rot(*gr).to_quaternion() @ rq)
        PB[n].keyframe_insert("rotation_quaternion", frame=F)
    for n in ("IK_foot_l", "IK_foot_r"):
        k = pose.get(n, (0, 0, 0, 0))
        rest = BN[n].matrix_local
        h = rest.translation
        off = Vector((k[0], k[1], max(k[2], 0.0))) * S
        _clave(n, Matrix.Translation(off) @ Matrix.Translation(h) @ O.rot(k[3]) @ Matrix.Translation(-h) @ rest, F)


def mezclar(tabla, f):
    canales = set()
    for _, d in tabla:
        canales.update(d.keys())
    pose = {}
    for c in canales:
        keys = [(fr, d[c]) for fr, d in tabla if c in d]
        if keys[0][0] > 1:
            keys.insert(0, (1, tuple(0.0 for _ in keys[0][1])))
        pose[c] = O.interp(keys, f)
    return pose


def zancada(fase, largo, alto, apoyo):
    u = (fase / (2 * math.pi)) % 1.0
    if u < apoyo:
        return largo - 2 * largo * (u / apoyo), 0.0, 0.0
    s = (u - apoyo) / (1 - apoyo)
    return -largo + 2 * largo * (s * s * (3 - 2 * s)), alto * math.sin(math.pi * s), -25 * math.sin(math.pi * s)


def brazos_al_frente(base, osc, p):
    return {"upperarm_l": (base + osc * math.sin(p), 0, -8), "upperarm_r": (base - osc * math.sin(p), 0, 8),
            "forearm_l": (-15, 0, 0), "forearm_r": (-12, 0, 0), "hand_l": (-10, 0, 0), "hand_r": (-10, 0, 0)}


def reposo(f, N=60):
    p = 2 * math.pi * (f - 1) / N
    pose = {"root": (0, 0, 0.005 * math.sin(2 * p), 4 * ENC, 3 * math.sin(p), 0), "chest": (6 + 10 * ENC, 2 * math.sin(p), 0),
            "neck": (4, -6, 3 * math.sin(p + 1)), "head": (5 * math.sin(2 * p), -10 + 4 * math.sin(p), 8 * math.sin(p * 0.5)),
            "jaw": (12 + 6 * math.sin(3 * p), 0, 0)}
    pose.update(brazos_al_frente(-25, 6, p))
    return pose


def marcha(f, N, largo, alto, apoyo, inclina, cojera, brazos_base, brazos_osc, boca):
    p = 2 * math.pi * (f - 1) / N
    pose = {"root": (0, 0, -0.02 - 0.015 * math.cos(2 * p), inclina, 5 * cojera * math.sin(p), 6 * math.sin(p)),
            "chest": (inclina * 0.6, 3 * math.sin(p), -5 * math.sin(p)), "neck": (5, -8 * cojera, 0),
            "head": (8 - inclina * 0.8, -10 * cojera + 3 * math.sin(2 * p), 5 * math.sin(p)), "jaw": (boca + 6 * math.sin(2 * p), 0, 0)}
    pose.update(brazos_al_frente(brazos_base, brazos_osc, p))
    for lado, fase, lift in (("IK_foot_l", p, alto * (1.0 - 0.7 * cojera)), ("IK_foot_r", p + math.pi, alto)):
        y, z, pt = zancada(fase, largo, lift, apoyo)
        pose[lado] = (0, -y, z, pt)
    return pose


CLIPS = [("reposo", 60, reposo)]
if TIPO == "corredor":
    CLIPS += [("caminar", 30, lambda f: marcha(f, 30, 0.22, 0.10, 0.55, 18, 0.0, -35, 25, 25)),
              ("correr", 20, lambda f: marcha(f, 20, 0.45, 0.22, 0.4, 32, 0.0, -20, 60, 35))]
elif TIPO == "bruto":
    CLIPS += [("caminar", 44, lambda f: marcha(f, 44, 0.3, 0.12, 0.62, 12, 0.3, -15, 20, 15)),
              ("correr", 28, lambda f: marcha(f, 28, 0.45, 0.2, 0.5, 20, 0.0, -10, 35, 25))]
else:
    CLIPS += [("caminar", 40, lambda f: marcha(f, 40, 0.26, 0.08, 0.6, 10, 1.0, -65, 8, 15)),
              ("correr", 24, lambda f: marcha(f, 24, 0.4, 0.16, 0.45, 22, 0.3, -55, 25, 30))]
arriba = -150 if TIPO == "bruto" else -130
CLIPS += [
    ("ataque", 24, lambda f: mezclar([
        (8, {"root": (0, 0.05, 0, -8, 0, 0), "chest": (-10, 0, 0), "head": (-10, 0, 0), "jaw": (40, 0, 0),
             "upperarm_l": (arriba, 0, -15), "upperarm_r": (arriba, 0, 15), "forearm_l": (-30, 0, 0), "forearm_r": (-30, 0, 0)}),
        (12, {"root": (0, -0.25, -0.05, 25, 0, 0), "chest": (30, 0, 0), "head": (15, 0, 0), "jaw": (55, 0, 0),
              "upperarm_l": (-60, 0, 10), "upperarm_r": (-60, 0, -10), "forearm_l": (-5, 0, 0), "forearm_r": (-5, 0, 0),
              "IK_foot_l": (0, -0.2, 0, 0), "IK_foot_r": (0, 0.05, 0, 0)}),
        (18, {"root": (0, -0.1, 0, 10, 0, 0), "chest": (12, 0, 0), "jaw": (10, 0, 0), "upperarm_l": (-40, 0, 0),
              "upperarm_r": (-40, 0, 0), "IK_foot_l": (0, -0.1, 0, 0), "IK_foot_r": (0, 0, 0, 0)}),
        (24, {"root": (0, 0, 0, 0, 0, 0), "chest": (0, 0, 0), "head": (0, 0, 0), "jaw": (0, 0, 0), "upperarm_l": (0, 0, 0),
              "upperarm_r": (0, 0, 0), "forearm_l": (0, 0, 0), "forearm_r": (0, 0, 0), "IK_foot_l": (0, 0, 0, 0)})], f)),
    ("dano", 12, lambda f: mezclar([
        (4, {"root": (0, 0.08, 0, -10, 5, 0), "chest": (-20, 5, 0), "head": (-30, 10, 15), "jaw": (35, 0, 0),
             "upperarm_l": (20, 0, -20), "upperarm_r": (15, 0, 20)}),
        (12, {"root": (0, 0, 0, 0, 0, 0), "chest": (0, 0, 0), "head": (0, 0, 0), "jaw": (0, 0, 0),
              "upperarm_l": (0, 0, 0), "upperarm_r": (0, 0, 0)})], f)),
    ("muerte", 40, lambda f: mezclar([
        (8, {"root": (0, 0.15, 0, -15, 0, 0), "head": (-35, 0, 0), "jaw": (45, 0, 0), "upperarm_l": (30, 0, -30), "upperarm_r": (25, 0, 30)}),
        (20, {"root": (0, 0.1, -0.45, 20, 15, 0), "chest": (25, 0, 0), "head": (30, 15, 0), "jaw": (30, 0, 0),
              "upperarm_l": (-20, 0, -40), "upperarm_r": (-10, 0, 40)}),
        (30, {"root": (0, -0.55, -0.82, 82, 20, 10), "chest": (10, 0, 0), "head": (15, 25, 20), "jaw": (40, 0, 0),
              "upperarm_l": (-150, 0, -30), "upperarm_r": (-140, 0, 30), "IK_foot_l": (0, -0.1, 0.18, 70), "IK_foot_r": (0.05, -0.05, 0.12, 70)}),
        (40, {"root": (0, -0.55, -0.85, 84, 20, 10)})], f)),
]

rig.animation_data_create()
rig.animation_data.action = bpy.data.actions.new("Zombi_" + TIPO)
rangos, F0 = {}, 1
for nombre, N, fn in CLIPS:
    sc.timeline_markers.new(nombre, frame=F0)
    for f in range(1, N + 1):
        sc.frame_set(F0 + f - 1)
        poner(fn(f), F0 + f - 1)
    rangos[nombre] = [F0, F0 + N - 1]
    F0 += N + 10
sc.frame_start, sc.frame_end = 1, F0 - 10
sc["clips"] = json.dumps(rangos)

if SOLDADO and os.path.exists(SOLDADO):
    with bpy.data.libraries.load(SOLDADO, link=False) as (src, dst):
        dst.objects = [n for n in src.objects if n in ("Soldado", "Soldado_Rig")]
    for o in dst.objects:
        if o:
            col.objects.link(o)
            if o.type == 'ARMATURE':
                o.location = (1.2 * S, 0, 0)
sol = bpy.data.objects.new("Sol", bpy.data.lights.new("Sol", 'SUN'))
sol.data.energy = 3.5
sol.rotation_euler = (0.8, 0.25, 0.7)
col.objects.link(sol)
cam = bpy.data.objects.new("Camara", bpy.data.cameras.new("Camara"))
cam.location = (2.6 * S, -3.6 * S, 1.6 * S)
cam.rotation_euler = (Vector((0, 0, 1.0 * S)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
col.objects.link(cam)
sc.camera = cam
for scr in bpy.data.screens:
    for area in scr.areas:
        for sp in area.spaces:
            if sp.type == 'VIEW_3D':
                sp.shading.type = 'SOLID'
                sp.shading.color_type = 'VERTEX'
sc.display.shading.color_type = 'VERTEX'
sc.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=SALIDA)
print("LISTO", TIPO, SALIDA, "triangulos", caras * 2, "clips", rangos)
