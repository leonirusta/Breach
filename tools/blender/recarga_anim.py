"""Recarga del fusil (2,2 s = 66 frames a 30 fps, lo que dura en weapons.gd) sobre el soldado de Breach.

blender -b --python tools/blender/recarga_anim.py -- <soldado_breach.blend> <salida.blend>

Poses clave con anticipacion, arcos y asentamiento: el arma se tumba hacia la mano libre, el
cargador vacio sale y cae al suelo, la mano va al portacargador, el nuevo entra con golpe de
asiento, se tira de la manija y el arma vuelve a la guardia con un pequeno rebote.
"""
import bpy, math, os, sys
from mathutils import Vector, Matrix, Quaternion

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import arma_fusil as AF
import recarga_rig as RR

args = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.open_mainfile(filepath=args[0])
rig, mags = RR.montar()
sc = bpy.context.scene
sc.render.fps, sc.frame_start, sc.frame_end = 30, 1, 67
PB, BN = rig.pose.bones, rig.data.bones
rad = math.radians
T = Matrix.Translation
U = AF.MAG_EJE


def rot(pitch=0.0, roll=0.0, yaw=0.0):
    """Grados en ejes del personaje: pitch+ = adelante/abajo, roll+ = hacia +X, yaw+ = hacia +X."""
    return Matrix.Rotation(rad(yaw), 4, 'Z') @ Matrix.Rotation(rad(pitch), 4, 'X') @ Matrix.Rotation(rad(roll), 4, 'Y')


def marco(pos, y, zh):
    y = Vector(y).normalized()
    x = y.cross(Vector(zh)).normalized()
    z = x.cross(y)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = Vector(pos)
    return m


def mano(contacto, y, zh):
    """Marco del objetivo IK (muneca) para que la palma (lado -Z de la mano) toque `contacto`."""
    m = marco(contacto, y, zh)
    m.translation = Vector(contacto) - m.col[1].xyz * 0.065 + m.col[2].xyz * 0.03
    return m


_ultimo = {}


def clave(n, pose, f, padre=None):
    b = BN[n]
    base = b.matrix_local.inverted() @ pose if b.parent is None else \
        (b.parent.matrix_local.inverted() @ b.matrix_local).inverted() @ padre.inverted() @ pose
    loc, q, _ = base.decompose()
    if n in _ultimo and _ultimo[n].dot(q) < 0:
        q.negate()
    _ultimo[n] = q
    PB[n].location, PB[n].rotation_quaternion = loc, q
    PB[n].keyframe_insert("location", frame=f)
    PB[n].keyframe_insert("rotation_quaternion", frame=f)


def giro_local(n, r, f):
    rq = BN[n].matrix_local.to_quaternion()
    q = rq.inverted() @ r.to_quaternion() @ rq
    if n in _ultimo and _ultimo[n].dot(q) < 0:
        q.negate()
    _ultimo[n] = q
    PB[n].rotation_quaternion = q
    PB[n].keyframe_insert("rotation_quaternion", frame=f)


# ---------------------------------------------------------------- ARMA (cantonera, yaw, pitch, roll)
# DESPLAZAMIENTO DEL ARMA (3er argumento opcional, "dx,dy,dz" en metros de Blender): las poses estan hechas con
# la culata en el hombro del soldado; un modelo con el hombro en otro sitio (el Heraldo Forjado) necesita el
# arma en el SUYO o las manos no llegan (ERROR_IK de 30-45 cm).
DESPL_ARMA = Vector([float(c) for c in args[2].split(",")]) if len(args) > 2 else Vector((0, 0, 0))


def arma(b, yaw, pitch, roll):
    r = Matrix.Rotation(rad(yaw), 4, 'Z') @ Matrix.Rotation(rad(-pitch), 4, 'X') @ Matrix.Rotation(rad(roll), 4, 'Y')
    return T(Vector(b) + DESPL_ARMA - (r @ AF.CANTONERA)) @ r


GUARDIA = ((-0.16, 0.02, 1.22), 15, -10, 0)
W = {1: GUARDIA,
     6: ((-0.155, 0.035, 1.20), 20, -4, -12),      # anticipacion: se recoge y empieza a tumbarse
     10: ((-0.15, 0.05, 1.17), 24, 2, -32),
     14: ((-0.15, 0.05, 1.165), 25, 4, -36),       # cargador fuera
     18: ((-0.148, 0.045, 1.17), 24, 3, -33),
     26: ((-0.15, 0.05, 1.16), 26, 5, -36),
     34: ((-0.15, 0.05, 1.165), 27, 8, -40),       # sale al encuentro del cargador nuevo
     40: ((-0.15, 0.05, 1.165), 27, 9, -40),
     44: ((-0.15, 0.045, 1.18), 26, 13, -37),      # golpe de asiento
     46: ((-0.152, 0.048, 1.175), 26, 11, -36),
     49: ((-0.155, 0.06, 1.185), 24, 8, -24),
     47: ((-0.15, 0.05, 1.17), 26, 9, -36),
     51: ((-0.16, 0.07, 1.20), 22, 6, -12),        # se endereza para la manija
     55: ((-0.16, 0.085, 1.20), 22, 5, -10),
     57: ((-0.16, 0.075, 1.21), 22, 8, -9),        # el cerrojo va a su sitio
     62: ((-0.162, 0.02, 1.225), 14, -11, 3),      # rebote al volver
     67: GUARDIA}
# EL ARMA SE SEPARA DEL CUERPO AL MONTARLA (2026-09-27). Del cargador a la manija (46-58) el arma se echaba hacia
# el pecho y la mano izquierda acababa a 12-17 cm de su hombro: con el brazo casi plegado del todo, un milimetro
# de mano eran decenas de grados de brazo y daba latigazos de 40-130 grados de un frame a otro (el "brazo que
# se vuelve loco y vuelve a su sitio"; le pasaba tambien al soldado). Ahora sale ADELANTE (-Y) mientras tanto.
ADELANTE = {44: 0.02, 46: 0.05, 49: 0.08, 51: 0.09, 55: 0.09, 57: 0.08, 60: 0.04, 62: 0.01}
for f, (b, yw, pt, rl) in W.items():
    b = (b[0], b[1] - ADELANTE.get(f, 0.0), b[2])
    clave("CTRL_arma", arma(b, yw, pt, rl), f)

for f, d in ((1, 0.0), (52, 0.0), (55, 0.065), (56, 0.065), (57, 0.0), (67, 0.0)):
    PB["arma_manija"].location = (0, d, 0)
    PB["arma_manija"].keyframe_insert("location", frame=f)

# ---------------------------------------------------------------- CUERPO
for f, dz, pt in ((1, -0.03, 0), (10, -0.04, 3), (24, -0.045, 4), (40, -0.04, 3), (44, -0.058, 4),
                  (48, -0.04, 3), (57, -0.052, 3), (62, -0.026, 0), (67, -0.03, 0)):
    h = BN["pelvis"].head_local
    clave("pelvis", T((0, 0, dz)) @ T(h) @ rot(pt, 0, -12) @ T(-h) @ BN["pelvis"].matrix_local, f)
for n, claves in {
    "stomach": ((1, 3, 0, -4), (10, 5, 0, -4), (24, 6, 2, 0), (44, 6, 0, -4), (67, 3, 0, -4)),
    "chest": ((1, 4, 0, -10), (10, 8, 0, -10), (22, 10, -4, -4), (30, 8, 0, -8), (44, 10, 0, -9),
              (48, 8, 0, -9), (55, 7, 0, -11), (62, 3, 0, -10), (67, 4, 0, -10)),
    # la cabeza acompana con la mirada pero sin hundirse: con 30 grados mas el pecho el casco tapaba la cara
    "head": ((1, -4, 0, 20), (8, 8, 0, 24), (14, 14, -5, 26), (22, 17, 0, 32), (28, 12, 0, 26),
             (36, 14, -4, 24), (44, 11, -3, 24), (50, 4, 0, 20), (56, 3, 0, 18), (62, -6, 0, 19), (67, -4, 0, 20)),
}.items():
    for f, pt, rl, yw in claves:
        giro_local(n, rot(pt, rl, yw), f)

for lado, off, yw in (("der", (-0.03, 0.09, 0.0), -18), ("izq", (0.03, -0.08, 0.0), -8)):
    rest = BN["IK_pie_" + lado].matrix_local
    h = rest.translation
    for f in (1, 67):
        clave("IK_pie_" + lado, T(off) @ T(h) @ rot(0, 0, yw) @ T(-h) @ rest, f)

# ---------------------------------------------------------------- MANOS
DG = bpy.context.evaluated_depsgraph_get()


def pose_eval(n, f):
    sc.frame_set(f)
    return rig.evaluated_get(DG).pose.bones[n].matrix.copy()


S = T(AF.MAG_ASIENTO)
H_MAG = mano((0.022, -0.02, -0.10), (-0.25, -0.45, 0.86), (1, 0, 0.1))      # mano izquierda en el cargador
GUARDA = mano((0.0, -0.22, -0.022), (-0.55, -0.45, 0.15), (0.45, 0, -0.9))
MANIJA = mano((0.005, 0.09, 0.062), (-0.8, 0.5, 0.0), (0, 0, 1))
DER = mano((-0.022, 0.035, -0.08), (0.4, -0.55, -0.7), (-1, 0, 0.35))


def funda(f):
    return pose_eval("stomach", f) @ BN["stomach"].matrix_local.inverted() @ RR.FUNDA_MAG


for f in (1, 67):
    clave("IK_mano_der", pose_eval("CTRL_arma", f) @ DER, f, pose_eval("CTRL_arma", f))

IZQ = [  # (frame, espacio, marco)
    (1, "arma", GUARDA),
    (5, "arma", T((0.06, 0.05, -0.07)) @ GUARDA),
    (9, "arma", S @ H_MAG),
    (11, "arma", S @ H_MAG),
    (15, "arma", T(-U * 0.075) @ S @ H_MAG),
    (18, "arma", T(-U * 0.13 + Vector((0.05, 0.06, -0.02))) @ S @ H_MAG),
    (24, "mundo", None),
    (27, "mundo", None),
    (34, "arma", T(-U * 0.11) @ S @ Matrix.Rotation(rad(10), 4, 'Y') @ H_MAG),
    (40, "arma", T(-U * 0.055) @ S @ H_MAG),
    (44, "arma", T(U * 0.004) @ S @ H_MAG),
    (46, "arma", T(-U * 0.012) @ S @ H_MAG),
    (49, "arma", T((0.05, -0.02, 0.07)) @ MANIJA),
    (52, "arma", MANIJA),
    (55, "arma", T((0, 0.065, 0)) @ MANIJA),
    (57, "arma", T((0.06, 0.06, 0.09)) @ MANIJA),
    (62, "arma", T((0.04, 0.03, -0.05)) @ GUARDA),
    (67, "arma", GUARDA),
]
for f, esp, m in IZQ:
    w = pose_eval("CTRL_arma", f)
    if esp == "mundo":
        m = funda(24) @ H_MAG if f == 24 else T((0.0, -0.02, 0.10)) @ funda(27) @ H_MAG
        clave("IK_mano_izq", m, f, w)
    else:
        clave("IK_mano_izq", w @ m, f, w)

# ---------------------------------------------------------------- CARGADORES (horneados frame a frame)
def poner(ob, m, f):
    loc, q, _ = m.decompose()
    ob.location, ob.rotation_quaternion = loc, q
    ob.keyframe_insert("location", frame=f)
    ob.keyframe_insert("rotation_quaternion", frame=f)


def suave(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------- BRAZO IZQUIERDO SUAVIZADO (2026-09-27)
# Montando el arma la mano izquierda va a 15-19 cm de su hombro: con el brazo tan plegado el IK responde a
# milimetros de mano con latigazos de 40-70 grados de un frame a otro (el brazo "se vuelve loco y vuelve a su
# sitio"; tambien en el soldado). Se hornea la pose que da el IK frame a frame y se SUAVIZA en el tiempo (media
# ponderada 1-6-15-20-15-6-1 de los giros, frame a frame); luego el IK de ese brazo se apaga. El recorrido es el mismo,
# sin latigazos: la mano puede apartarse un poco del objetivo en los frames mas rapidos (sale en ERROR_IK).
SUAV = ("arm_upper_r", "arm_lower_r", "hand_r")
poses = {n: [] for n in SUAV}
for f in range(1, 68):
    sc.frame_set(f)
    ev = rig.evaluated_get(DG).pose.bones
    for n in SUAV:
        poses[n].append(ev[n].matrix.copy())
for n in SUAV:
    for c in PB[n].constraints:
        c.mute = True
PESOS = (1, 6, 15, 20, 15, 6, 1)


def suaviza(lista):
    qs = [m.to_quaternion() for m in lista]
    out = []
    for i in range(len(qs)):
        acc = [0.0, 0.0, 0.0, 0.0]
        for k, w in zip(range(-(len(PESOS) // 2), len(PESOS) // 2 + 1), PESOS):
            q = qs[min(max(i + k, 0), len(qs) - 1)].copy()
            if q.dot(qs[i]) < 0:
                q.negate()
            acc = [acc[t] + w * q[t] for t in range(4)]
        qq = Quaternion(acc)
        qq.normalize()
        out.append(qq)
    return out


suaves = {n: suaviza(poses[n]) for n in SUAV}
for f in range(1, 68):
    sc.frame_set(f)
    for n in SUAV:                                   # de padre a hijo
        loc = PB[n].location.copy()
        PB[n].matrix = Matrix.Translation(poses[n][f - 1].translation) @ suaves[n][f - 1].to_matrix().to_4x4()
        PB[n].location = loc
        bpy.context.view_layer.update()
        PB[n].keyframe_insert("rotation_quaternion", frame=f)

esquinas = [Vector(c) for c in mags["Cargador_viejo"].bound_box]
viejo, nuevo = mags["Cargador_viejo"], mags["Cargador_nuevo"]
caida, error = None, {}
for f in range(1, 68):
    w = pose_eval("CTRL_arma", f)
    ev = rig.evaluated_get(DG).pose.bones
    mi = ev["hand_r"].matrix.copy()
    for lado, s in (("der", "l"), ("izq", "r")):
        e = (ev["hand_" + s].head - ev["IK_mano_" + lado].head).length
        error[lado] = max(error.get(lado, (0, 0))[0], e), (f if e >= error.get(lado, (0, 0))[0] else error[lado][1])
    # viejo: en el arma -> en la mano -> cae
    if f <= 11:
        mv = w @ S
    elif f <= 18:
        mv = mi @ H_MAG.inverted()
        if f >= 17:
            caida = (caida or []) + [mv]
    else:
        if isinstance(caida, list):
            p0, p1 = caida[-2].translation, caida[-1].translation
            vel = (p1 - p0) * 30 + Vector((0.3, 0.2, 0.0))
            caida = {"p": p1.copy(), "v": vel, "q": caida[-1].to_quaternion(), "suelo": False}
        c = caida
        if not c["suelo"]:
            c["v"].z -= 9.8 / 30
            c["p"] += c["v"] / 30
            c["q"] = Quaternion(Vector((1, 0.3, 0)).normalized(), rad(-14)) @ c["q"]
            m = T(c["p"]) @ c["q"].to_matrix().to_4x4()
            bajo = min((m @ v).z for v in esquinas)
            if bajo <= 0:
                c["suelo"] = True
                c["plano"] = Quaternion((0, 0, 1), c["q"].to_euler().z) @ Quaternion((0, 1, 0), rad(90))
        if c["suelo"]:
            c["q"] = c["q"].slerp(c["plano"], 0.45)
            m = T(c["p"]) @ c["q"].to_matrix().to_4x4()
            c["p"].z -= min((m @ v).z for v in esquinas)
        mv = T(c["p"]) @ c["q"].to_matrix().to_4x4()
    poner(viejo, mv, f)
    # nuevo: en el portacargador -> en la mano -> se alinea -> entra -> asentado
    en_mano = mi @ H_MAG.inverted()
    if f <= 24:
        mn = funda(f)
    elif f <= 34:
        mn = en_mano
    elif f <= 40:
        k = suave((f - 34) / 6)
        a, b = en_mano.decompose(), (w @ T(-U * 0.055) @ S).decompose()
        mn = T(a[0].lerp(b[0], k)) @ a[1].slerp(b[1], k).to_matrix().to_4x4()
    elif f <= 44:
        mn = w @ T(-U * 0.055 * (1 - suave((f - 40) / 4))) @ S
    else:
        mn = w @ S
    poner(nuevo, mn, f)

sc.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=args[1])
print("ERROR_IK", {k: (round(v[0] * 100, 1), v[1]) for k, v in error.items()}, "cm/frame")
print("LISTO", args[1])
