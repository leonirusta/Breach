"""MAZAZO a dos manos (0,85 s a 60 fps = 52 frames) sobre el soldado de Breach.

blender -b --python tools/blender/mazo_anim.py -- <soldado_breach.blend> <salida.blend>

Guardia con el mazo cruzado (mango a la cadera izquierda, cabeza sobre el hombro derecho) -> amago
-> CARGA: el torso gira a la derecha, las manos suben junto a la oreja y la cabeza del mazo cae detras
del hombro -> un instante arriba -> GOLPE: el torso desgira y se echa adelante, la cadera cae y el mazo
baja en arco por encima de la cabeza hasta delante (impacto en el frame 31 = 0,50 s) -> rebote ->
vuelta a la guardia. El mazo es el de weapon_model.gd::_build_sledge con la cabeza PERPENDICULAR al
mango (15 x 35 x 15 cm), como uno de verdad.
Deja una camara "Camara_1P" en el ojo para ver el golpe como lo ve el jugador.
"""
import bpy, math, os, sys
from mathutils import Vector, Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import arma_fusil as AF
import recarga_rig as RR

args = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.open_mainfile(filepath=args[0])
rig, mags = RR.montar()
for n in ("Fusil", "Manija", "Cargador_viejo", "Cargador_nuevo"):
    bpy.data.objects.remove(bpy.data.objects[n], do_unlink=True)
sc = bpy.context.scene
FPS, N = 60, 52
IMPACTO = 31
sc.render.fps, sc.frame_start, sc.frame_end = FPS, 1, N
PB, BN = rig.pose.bones, rig.data.bones
rad, T = math.radians, Matrix.Translation

# ---------------------------------------------------------------- EL MAZO (ejes de Godot, como el juego)
MADERA, MADERA2 = (0.58, 0.40, 0.21), (0.50, 0.34, 0.17)
ACERO, ACERO2, GOMA = (0.46, 0.46, 0.48), (0.54, 0.54, 0.56), (0.09, 0.09, 0.10)
m = AF.Piezas()
m.box((0.05, 0.05, 1.0), (0, 0, 0.025), MADERA)
m.box((0.052, 0.014, 1.0), (0, 0.018, 0.025), MADERA2)
m.box((0.058, 0.058, 0.26), (0, 0, 0.36), GOMA)
m.box((0.07, 0.07, 0.035), (0, 0, 0.515), GOMA)
m.box((0.075, 0.075, 0.07), (0, 0, -0.47), ACERO2)
m.box((0.15, 0.35, 0.15), (0, 0, -0.60), ACERO)                  # cabeza, cruzada al mango
for s in (-1, 1):
    m.box((0.155, 0.03, 0.155), (0, 0.175 * s, -0.60), ACERO2)    # caras de golpeo
    m.box((0.16, 0.30, 0.03), (0, 0, -0.60 + 0.062 * s), ACERO2)
    m.box((0.03, 0.30, 0.16), (0.062 * s, 0, -0.60), ACERO2)
mazo = RR.malla("Mazo", m)
RR.piel(mazo, rig, "arma")
EMPUNA_B = Vector((0, 0.34, 0))          # grip_pos (0, 0, 0.34) de Godot: mano del gatillo, al final
APOYO_B = Vector((0, 0.05, 0))           # foregrip_pos (0, 0, 0.05): la otra, a media asta
CABEZA_B = Vector((0, -0.60, 0))


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


def mano(contacto, y, zh):
    y = Vector(y).normalized()
    x = y.cross(Vector(zh)).normalized()
    mm = Matrix((x, y, x.cross(y))).transposed().to_4x4()
    mm.translation = Vector(contacto) - mm.col[1].xyz * 0.065 + mm.col[2].xyz * 0.03
    return mm


LATERAL = Vector((1.0, 0.15, 0.0)).normalized()     # normal del plano del golpe


def pose_mazo(empuna, mango):
    """mano del gatillo en `empuna` y el mango apuntando (de la mano a la cabeza) hacia `mango`"""
    d = Vector(mango).normalized()
    cara = LATERAL.cross(d).normalized()
    y = -d
    x = y.cross(cara)
    r = Matrix((x, y, cara)).transposed().to_4x4()
    return T(Vector(empuna) - (r @ EMPUNA_B)) @ r


def interp(keys, f):
    if f <= keys[0][0]:
        return keys[0][1]
    if f >= keys[-1][0]:
        return keys[-1][1]
    i = max(j for j in range(len(keys) - 1) if keys[j][0] <= f)
    a, b = keys[i], keys[i + 1]
    p0 = keys[i - 1] if i > 0 else a
    p3 = keys[i + 2] if i + 2 < len(keys) else b
    L = b[0] - a[0]
    t = (f - a[0]) / L
    h00, h10, h01, h11 = 2 * t**3 - 3 * t**2 + 1, t**3 - 2 * t**2 + t, -2 * t**3 + 3 * t**2, t**3 - t**2
    out = []
    for c in range(len(a[1])):
        m1 = (b[1][c] - p0[1][c]) / max(b[0] - p0[0], 1e-6) * L
        m2 = (p3[1][c] - a[1][c]) / max(p3[0] - a[0], 1e-6) * L
        out.append(h00 * a[1][c] + h10 * m1 + h01 * b[1][c] + h11 * m2)
    return tuple(out)


# ---------------------------------------------------------------- POSES CLAVE (frames a 60 fps)
GUARDIA = ((0.08, -0.22, 0.98), (-0.55, -0.20, 0.65))
MAZO = [(1, GUARDIA),
        (6, ((0.08, -0.22, 0.91), (-0.58, -0.18, 0.60))),        # amago: se encoge
        (18, ((-0.05, -0.12, 1.20), (-0.30, 0.55, 0.78))),       # carga: sube al hombro derecho
        (23, ((-0.12, 0.02, 1.42), (-0.17, 0.94, -0.28))),       # arriba: la cabeza cae detras
        (25, ((-0.13, 0.03, 1.43), (-0.15, 0.96, -0.24))),       # un instante colgado
        (28, ((-0.08, -0.26, 1.34), (-0.15, -0.40, 0.90))),      # baja por encima de la cabeza
        (IMPACTO, ((0.0, -0.36, 1.05), (0.0, -0.97, -0.25))),    # IMPACTO delante
        (35, ((0.0, -0.35, 1.08), (0.0, -0.96, -0.08))),         # rebote
        (44, ((0.05, -0.30, 1.00), (-0.35, -0.45, 0.55))),
        (N, GUARDIA)]
# pelvis: (dx, dy, dz, cabeceo, alabeo, guinada); columna y cabeza: (cabeceo, alabeo, guinada)
PELVIS = [(1, (0, 0, -0.03, 0, 0, -10)), (6, (0, 0, -0.045, 1, 0, -10)), (18, (0, 0.02, -0.03, -3, 0, -18)),
          (23, (0, 0.03, -0.03, -5, 0, -22)), (25, (0, 0.03, -0.03, -5, 0, -22)), (28, (0, -0.02, -0.06, 6, 0, -8)),
          (IMPACTO, (0, -0.05, -0.09, 12, 0, 4)), (35, (0, -0.05, -0.085, 11, 0, 3)), (44, (0, -0.02, -0.05, 4, 0, -6)),
          (N, (0, 0, -0.03, 0, 0, -10))]
STOMACH = [(1, (3, 0, -4)), (6, (6, 0, -4)), (18, (-2, -3, -14)), (23, (-4, -4, -18)), (25, (-4, -4, -18)),
           (28, (6, 2, -6)), (IMPACTO, (14, 3, 6)), (35, (12, 2, 4)), (44, (6, 0, -2)), (N, (3, 0, -4))]
CHEST = [(1, (4, 0, -8)), (6, (8, 0, -6)), (18, (-6, -4, -24)), (23, (-10, -5, -30)), (25, (-11, -5, -30)),
         (28, (12, 3, -8)), (IMPACTO, (24, 4, 8)), (35, (20, 3, 4)), (44, (10, 0, -4)), (N, (4, 0, -8))]
HEAD = [(1, (-3, 0, 14)), (6, (0, 0, 12)), (18, (-4, 2, 30)), (23, (-6, 3, 36)), (25, (-6, 3, 36)),
        (28, (5, 0, 14)), (IMPACTO, (18, -2, -4)), (35, (14, 0, 0)), (44, (4, 0, 8)), (N, (-3, 0, 14))]

# ---------------------------------------------------------------- HORNEADO
for f in range(1, N + 1):
    dx, dy, dz, pt, rl, yw = interp(PELVIS, f)
    h = BN["pelvis"].head_local
    clave("pelvis", T((dx, dy, dz)) @ T(h) @ rot(pt, rl, yw) @ T(-h) @ BN["pelvis"].matrix_local, f)
    for n, keys in (("stomach", STOMACH), ("chest", CHEST), ("head", HEAD)):
        giro(n, rot(*interp(keys, f)), f)
    e = interp([(k[0], k[1][0]) for k in MAZO], f)
    d = interp([(k[0], k[1][1]) for k in MAZO], f)
    clave("CTRL_arma", pose_mazo(e, d), f)
for lado, off, yw in (("der", (-0.03, 0.10, 0.0), -20), ("izq", (0.03, -0.14, 0.0), -8)):
    rest = BN["IK_pie_" + lado].matrix_local
    hh = rest.translation
    for f in (1, N):
        clave("IK_pie_" + lado, T(off) @ T(hh) @ rot(0, 0, yw) @ T(-hh) @ rest, f)
DER = mano(EMPUNA_B + Vector((-0.03, 0, 0)), (1, 0, -0.3), (0, 0, 1))
IZQ = mano(APOYO_B + Vector((0.03, 0, 0)), (-1, 0, -0.3), (0, 0, 1))
DG = bpy.context.evaluated_depsgraph_get()
for f in (1, N):
    sc.frame_set(f)
    w = rig.evaluated_get(DG).pose.bones["CTRL_arma"].matrix.copy()
    clave("IK_mano_der", w @ DER, f, w)
    clave("IK_mano_izq", w @ IZQ, f, w)

for layer in rig.animation_data.action.layers:
    for strip in layer.strips:
        for bag in strip.channelbags:
            for fc in bag.fcurves:
                for kp in fc.keyframe_points:
                    kp.interpolation = 'LINEAR'

# camara en el ojo (primera persona): quieta, mirando al frente
ojo = (BN["eye_l_up"].head_local + BN["eye_r_up"].head_local) * 0.5
cam = bpy.data.objects.new("Camara_1P", bpy.data.cameras.new("Camara_1P"))
cam.location = ojo
cam.rotation_euler = (math.pi / 2, 0, math.pi)          # mirando a -Y, adonde mira el soldado
cam.data.lens = 18
sc.collection.objects.link(cam)
sc["ojo"] = list(ojo)

err, cabeza, malos = {"der": 0.0, "izq": 0.0}, [], []
for f in range(1, N + 1):
    sc.frame_set(f)
    ev = rig.evaluated_get(DG).pose.bones
    for lado, s in (("der", "l"), ("izq", "r")):
        e = (ev["hand_" + s].head - ev["IK_mano_" + lado].head).length
        err[lado] = max(err[lado], e)
        if e > 0.015:
            malos.append((f, lado, round(e * 100, 1)))
    if f in (1, 23, IMPACTO):
        c = ev["CTRL_arma"].matrix @ CABEZA_B
        cabeza.append((f, tuple(round(v, 2) for v in c)))
print("ERROR_IK_MANOS_CM", {k: round(v * 100, 1) for k, v in err.items()})
print("CABEZA_DEL_MAZO (frame, x y z)", cabeza)
print("MANOS_QUE_NO_LLEGAN (frame, lado, cm)", malos)
sc.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=args[1])
print("LISTO", args[1])
