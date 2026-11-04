"""Ciclos de ESCALERA con el fusil, en el sitio, sobre el soldado de Breach (como caminar_anim.py).

blender -b --python tools/blender/escalera_anim.py -- <soldado_breach.blend> <salida.blend> [subir|bajar]

Antes, en una escalera el muñeco ponia el clip de andar por el llano: las piernas barrian a ras de suelo, el
cuerpo iba tieso y la capsula lo subia de golpe peldaño a peldaño ("sube derecho"). Estos dos ciclos son los de
una escalera de verdad, de pendiente 1:2 (peldaños de 15 cm de alto y 30 de huella; en el juego da igual el
peldaño concreto: el ciclo va a la velocidad a la que se sube):

subir  1 s = 30 frames = dos pasos, 1,2 m/s de avance y 0,6 m/s de subida. El pie se planta ENTERO en el peldaño
       de arriba, la rodilla tira hacia arriba y adelante y el pie de atras empuja de puntillas; el cuerpo va
       echado adelante (~22 grados entre cadera, estomago y pecho), la cadera se hunde al plantar y sube al
       estirar la pierna de apoyo, y la cabeza compensa para seguir mirando al frente.
bajar  1 s = 30 frames = dos pasos. Se baja de PUNTA: el pie de delante estira hacia el peldaño de abajo, entra
       con la puntera y luego apoya el talon; la pierna de atras se dobla para bajar el cuerpo con control, la
       cadera va baja, el cuerpo casi recto y la cabeza mira los peldaños.
La escalera corre bajo los pies a la velocidad del pie apoyado: si patinan, se ve (--render para comprobarlo).
"""
import bpy, math, os, sys
from mathutils import Vector, Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import arma_fusil as AF
import recarga_rig as RR

args = sys.argv[sys.argv.index("--") + 1:]
ESTILO = args[2] if len(args) > 2 else "subir"
cos, sin, tau = math.cos, math.sin, 2 * math.pi
K = 0.5                                  # pendiente: sube medio metro por metro de avance
HUELLA = 0.30


def _subir():
    N = 30
    vel = 0.04                                            # 1,2 m/s: apoyo de 0,64 m en 16 frames
    # (frame, y, z, cabeceo del pie): y negativo = delante (el soldado mira a -Y); z = altura del tobillo
    # sobre su reposo. En el apoyo el pie va hacia atras y hacia ABAJO a la vez (el cuerpo sube): z = -K*y.
    pie = [(1, -0.32, 0.16, 0), (5, -0.16, 0.08, 0), (9, 0.0, 0.0, 0), (13, 0.16, -0.08, 5),
           (15, 0.24, -0.12, 16), (17, 0.32, -0.16, 32),     # empuja de puntillas
           (20, 0.22, -0.02, 30),                             # despega
           (23, 0.02, 0.20, 10),                              # la rodilla tira arriba: el pie pasa alto
           (26, -0.24, 0.31, -6),                             # por encima del canto del peldaño
           (29, -0.34, 0.22, -3)]                             # y baja a plantarse entero

    def p(f):
        return tau * (f - 1) / N

    def rebote(f):                                        # la cadera, abajo al plantar y arriba al estirar
        return tau * (f - 3) / (N / 2)

    def pelvis(f):
        a = p(f)
        return (-0.02 * sin(a), -0.075 + 0.018 * (1 - cos(rebote(f))), 12 + 1.5 * cos(rebote(f)), 3.5 * sin(a), 6 * cos(a))

    def arma(f):
        q = p(f) - 0.45
        bob = 0.8 * 0.018 * (1 - cos(rebote(f) - 0.5))
        return ((-0.15 + 0.008 * sin(q), -0.05, 1.12 + bob), 15 + 2 * cos(q), -12 + 1.5 * cos(2 * q), 2 * sin(q))

    return dict(N=N, VEL=vel, PIE=pie, pelvis=pelvis, arma=arma, K=K,
                stomach=lambda f: (4, 0, -6),
                chest=lambda f: (6, -2 * sin(p(f)), -14 - 3 * cos(p(f))),
                head=lambda f: (-13 + cos(rebote(f)), 0, 20 - 3 * cos(p(f))))


def _bajar():
    N = 30
    vel = 0.04
    # en el apoyo el pie va hacia atras y hacia ARRIBA (el cuerpo baja): z = +K*y. Entra de puntera
    # (cabeceo positivo = talon arriba) y luego apoya el talon.
    pie = [(1, -0.32, -0.16, 18), (3, -0.24, -0.12, 5), (5, -0.16, -0.08, 0), (9, 0.0, 0.0, 0),
           (13, 0.16, 0.08, 0), (17, 0.32, 0.16, 12),        # el talon se levanta antes de soltar
           (19, 0.30, 0.25, 14),                              # sale del peldaño de arriba
           (22, 0.12, 0.27, 6),                               # pasa junto al pie de apoyo
           (25, -0.12, 0.10, 6),                              # por encima del canto
           (28, -0.29, -0.07, 16)]                            # y estira de punta hacia el de abajo

    def p(f):
        return tau * (f - 1) / N

    def pelvis(f):
        a = p(f)
        return (-0.02 * sin(a), -0.10 + 0.02 * (1 - cos(2 * a)), 6 + cos(2 * a), 3.5 * sin(a), 5 * cos(a))

    def arma(f):
        q = p(f) - 0.45
        bob = 0.8 * 0.02 * (1 - cos(2 * q))
        return ((-0.16 + 0.008 * sin(q), 0.0, 1.10 + bob), 15 + 2 * cos(q), -16 + 1.2 * cos(2 * q), 2 * sin(q))

    return dict(N=N, VEL=vel, PIE=pie, pelvis=pelvis, arma=arma, K=-K,
                stomach=lambda f: (2, 0, -6),
                chest=lambda f: (4, -1.5 * sin(p(f)), -14 - 3 * cos(p(f))),
                head=lambda f: (6 + cos(2 * p(f)), 0, 20 - 3 * cos(p(f))))


E = {"subir": _subir, "bajar": _bajar}[ESTILO]()
N, VEL, PIE = E["N"], E["VEL"], E["PIE"]

bpy.ops.wm.open_mainfile(filepath=args[0])
rig, mags = RR.montar()
sc = bpy.context.scene
sc.render.fps, sc.frame_start, sc.frame_end = 30, 1, N
PB, BN = rig.pose.bones, rig.data.bones
rad, T = math.radians, Matrix.Translation


def rot(pitch=0.0, roll=0.0, yaw=0.0):
    return Matrix.Rotation(rad(yaw), 4, 'Z') @ Matrix.Rotation(rad(pitch), 4, 'X') @ Matrix.Rotation(rad(roll), 4, 'Y')


_ult = {}


def _q(n, q):
    if n in _ult and _ult[n].dot(q) < 0:
        q.negate()
    _ult[n] = q
    return q


def clave(n, pose, f, padre=None):
    b = BN[n]
    base = b.matrix_local.inverted() @ pose if b.parent is None else \
        (b.parent.matrix_local.inverted() @ b.matrix_local).inverted() @ padre.inverted() @ pose
    loc, q, _ = base.decompose()
    PB[n].location, PB[n].rotation_quaternion = loc, _q(n, q)
    PB[n].keyframe_insert("location", frame=f)
    PB[n].keyframe_insert("rotation_quaternion", frame=f)


def giro(n, r, f):
    rq = BN[n].matrix_local.to_quaternion()
    PB[n].rotation_quaternion = _q(n, rq.inverted() @ r.to_quaternion() @ rq)
    PB[n].keyframe_insert("rotation_quaternion", frame=f)


def marco(pos, y, zh):
    y = Vector(y).normalized()
    x = y.cross(Vector(zh)).normalized()
    m = Matrix((x, y, x.cross(y))).transposed().to_4x4()
    m.translation = Vector(pos)
    return m


def mano(contacto, y, zh):
    m = marco(contacto, y, zh)
    m.translation = Vector(contacto) - m.col[1].xyz * 0.065 + m.col[2].xyz * 0.03
    return m


def arma(b, yaw, pitch, roll):
    r = Matrix.Rotation(rad(yaw), 4, 'Z') @ Matrix.Rotation(rad(-pitch), 4, 'X') @ Matrix.Rotation(rad(roll), 4, 'Y')
    return T(Vector(b) - (r @ AF.CANTONERA)) @ r


# ---------------------------------------------------------------- PIES (Catmull-Rom periodico)
def pie(f):
    ks = PIE + [(k[0] + N,) + k[1:] for k in PIE]
    f = (f - 1) % N + 1
    for i in range(len(PIE)):
        a, b = ks[i], ks[i + 1]
        if a[0] <= f <= b[0]:
            p0, p3 = ks[i - 1], ks[i + 2]
            t = (f - a[0]) / (b[0] - a[0])

            def cr(j):
                return 0.5 * ((2 * a[j]) + (-p0[j] + b[j]) * t + (2 * p0[j] - 5 * a[j] + 4 * b[j] - p3[j]) * t * t
                              + (-p0[j] + 3 * a[j] - 3 * b[j] + p3[j]) * t * t * t)
            return cr(1), cr(2), cr(3)
    return PIE[0][1:]


for f in range(1, N + 2):
    for lado, desfase in (("der", 0), ("izq", N // 2)):
        y, z, pt = pie(f + desfase)
        rest = BN["IK_pie_" + lado].matrix_local
        h = rest.translation
        clave("IK_pie_" + lado, T((0, y, z)) @ T(h) @ rot(pt) @ T(-h) @ rest, f)

# ---------------------------------------------------------------- CUERPO
for f in range(1, N + 2):
    dx, dz, pt, rl, yw = E["pelvis"](f)
    h = BN["pelvis"].head_local
    clave("pelvis", T((dx, 0, dz)) @ T(h) @ rot(pt, rl, yw) @ T(-h) @ BN["pelvis"].matrix_local, f)
    for n in ("stomach", "chest", "head"):
        giro(n, rot(*E[n](f)), f)

# ---------------------------------------------------------------- ARMA Y MANOS
GUARDA = mano((0.0, -0.22, -0.022), (-0.55, -0.45, 0.15), (0.45, 0, -0.9))
DER = mano((-0.022, 0.035, -0.08), (0.4, -0.55, -0.7), (-1, 0, 0.35))
DG = bpy.context.evaluated_depsgraph_get()


def pose_eval(n, f):
    sc.frame_set(f)
    return rig.evaluated_get(DG).pose.bones[n].matrix.copy()


for f in range(1, N + 2):
    clave("CTRL_arma", arma(*E["arma"](f)), f)
for f in (1, N + 1):
    w = pose_eval("CTRL_arma", f)
    clave("IK_mano_der", w @ DER, f, w)
    clave("IK_mano_izq", w @ GUARDA, f, w)

for f in range(1, N + 2):
    w = pose_eval("CTRL_arma", f)
    for ob, m in ((mags["Cargador_viejo"], w @ T(AF.MAG_ASIENTO)),
                  (mags["Cargador_nuevo"], pose_eval("stomach", f) @ BN["stomach"].matrix_local.inverted() @ RR.FUNDA_MAG)):
        loc, qq, _ = m.decompose()
        ob.location, ob.rotation_quaternion = loc, qq
        ob.keyframe_insert("location", frame=f)
        ob.keyframe_insert("rotation_quaternion", frame=f)

# ---------------------------------------------------------------- LA ESCALERA QUE CORRE
# Peldaños de HUELLA de fondo con el centro de cada huella sobre la recta z = -K*y (K negativo al bajar), que
# se desplazan a la velocidad del pie apoyado: hacia atras (+Y) y hacia abajo al subir, hacia arriba al bajar.
verts, faces, cols = [], [], []
for i in range(-12, 13):
    c = i * HUELLA
    top = -E["K"] * c
    y0, y1 = c - HUELLA / 2, c + HUELLA / 2
    k = len(verts)
    verts += [(-0.9, y0, top), (0.9, y0, top), (0.9, y1, top), (-0.9, y1, top),
              (-0.9, y0, top - 3.0), (0.9, y0, top - 3.0), (0.9, y1, top - 3.0), (-0.9, y1, top - 3.0)]
    faces += [(k, k + 1, k + 2, k + 3), (k, k + 4, k + 5, k + 1), (k + 3, k + 2, k + 6, k + 7),
              (k, k + 3, k + 7, k + 4), (k + 1, k + 5, k + 6, k + 2)]
    col = (0.30, 0.31, 0.33, 1) if i % 2 == 0 else (0.40, 0.41, 0.43, 1)
    cols += [col] * 5
me = bpy.data.meshes.new("Escalera_cinta")
me.from_pydata(verts, [], faces)
ca = me.color_attributes.new("Col", 'FLOAT_COLOR', 'CORNER')
for fi, poly in enumerate(me.polygons):
    for li in poly.loop_indices:
        ca.data[li].color = cols[fi]
me.color_attributes.active_color = ca
esc = bpy.data.objects.new("Escalera_cinta", me)
sc.collection.objects.link(esc)
for f in (1, N + 1):
    d = (f - 1) * VEL
    esc.location = (0, d, -E["K"] * d - 0.001)
    esc.keyframe_insert("location", frame=f)

for ob in [rig, esc] + list(mags.values()):
    ad = ob.animation_data
    if not ad or not ad.action:
        continue
    for layer in ad.action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for fc in bag.fcurves:
                    for kp in fc.keyframe_points:
                        kp.interpolation = 'LINEAR'

err = {"der": 0.0, "izq": 0.0}
for f in range(1, N + 1):
    sc.frame_set(f)
    ev = rig.evaluated_get(DG).pose.bones
    for lado, s in (("der", "l"), ("izq", "r")):
        err[lado] = max(err[lado], (ev["hand_" + s].head - ev["IK_mano_" + lado].head).length)
print("ERROR_IK_MANOS_CM", {k: round(v * 100, 2) for k, v in err.items()})

sc["estilo"] = ESTILO
sc["vel_ms"] = VEL * 30
sc.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=args[1])
print("LISTO", ESTILO, args[1])
