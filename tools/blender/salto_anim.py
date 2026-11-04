"""EL SALTO DEMOLEDOR DE LA HABILIDAD, en tres clips que encajan (60 fps) sobre el soldado de Breach.

blender -b --python tools/blender/salto_anim.py -- <soldado_breach.blend> <salida.blend> <despegue|aire|golpe>

Pedido (2026-09-28): "mejora la animacion de salto, super realista". El vuelo dura lo que haga falta (0,6-2,4 s segun
la distancia), asi que no cabe en un clip: el juego encadena DESPEGUE -> AIRE (en bucle mientras vuela) -> GOLPE.
  despegue (28 frames, 0,45 s)  coge impulso: se agacha hondo, el tronco adelante, mira al destino y los brazos van
                                atras; a los 0,2 s (frame 13) el juego lo lanza: se estira de golpe, de puntillas, los
                                brazos barren hacia el cielo y las piernas se recogen en la postura del aire
  aire     (60 frames, bucle)   en vuelo: rodilla izquierda arriba, pierna derecha atras, el puno derecho cargado por
                                encima de la cabeza y el brazo izquierdo equilibrando; mira abajo, a donde va a caer
  golpe    (96 frames, 1,6 s)   ATERRIZAJE DE SUPERHEROE: pie izquierdo delante, la rodilla derecha al suelo, el puno
                                derecho revienta el suelo en el frame 8 (0,12 s: ahi sale la onda), el brazo izquierdo
                                atras; aguanta, levanta la cabeza, se incorpora y vuelve a empunar el fusil
"""
import bpy, math, os, sys
from mathutils import Vector, Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import arma_fusil as AF
import recarga_rig as RR

args = sys.argv[sys.argv.index("--") + 1:]
PARTE = args[2]
bpy.ops.wm.open_mainfile(filepath=args[0])
rig, mags = RR.montar()
sc = bpy.context.scene
N = {"despegue": 28, "aire": 60, "golpe": 96}[PARTE]
sc.render.fps, sc.frame_start, sc.frame_end = 60, 1, N
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


def mezcla(a, b, w):
    la, qa, _ = a.decompose()
    lb, qb, _ = b.decompose()
    return T(la.lerp(lb, w)) @ qa.slerp(qb, w).to_matrix().to_4x4()


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


def peso(keys, f):
    if f <= keys[0][0]:
        return keys[0][1]
    if f >= keys[-1][0]:
        return keys[-1][1]
    i = max(j for j in range(len(keys) - 1) if keys[j][0] <= f)
    (fa, a), (fb, b) = keys[i], keys[i + 1]
    t = (f - fa) / (fb - fa)
    return a + (b - a) * t * t * (3 - 2 * t)


# ================================================================ LAS POSES (delante -Y, derecha -X, arriba +Z)
# cada pose: pelvis (dx,dy,dz,cabeceo,alabeo,guinada), stomach/chest/head (cabeceo,alabeo,guinada),
# pies (dx,dy,z tobillo,cabeceo,guinada), manos ((contacto),(dedos),(dorso)), peso de las manos en el fusil, correa
ARRIBA, ADELANTE, ABAJO = (0, 0, 1), (0, -1, 0), (0, 0, -1)
REPOSO = {"pelvis": (0, 0, -0.03, 0, 0, -12), "stomach": (3, 0, -4), "chest": (4, 0, -10), "head": (-4, 0, 20),
          "pie_der": (-0.03, 0.09, 0, 0, -18), "pie_izq": (0.03, -0.08, 0, 0, -8),
          "mano_der": ((-0.18, -0.14, 1.05), (0, -0.4, -1), (-1, 0, 0)), "mano_izq": ((0.08, -0.36, 1.18), (0, -0.4, -1), (1, 0, 0)),
          "fusil": 1.0, "correa": 0.0}
AGACHADO = {"pelvis": (0, 0.06, -0.30, 26, 0, 0), "stomach": (10, 0, 0), "chest": (14, 0, 0), "head": (-26, 0, 0),
            "pie_der": (-0.12, 0.05, 0, -4, -10), "pie_izq": (0.12, -0.05, 0, -4, -4),
            "mano_der": ((-0.24, 0.30, 0.78), (0, 0.6, -1), (-1, 0, 0)), "mano_izq": ((0.24, 0.30, 0.78), (0, 0.6, -1), (1, 0, 0)),
            "fusil": 0.0, "correa": 1.0}
ESTIRADO = {"pelvis": (0, -0.04, 0.06, 8, 0, 0), "stomach": (2, 0, 0), "chest": (-6, 0, 0), "head": (-12, 0, 0),
            "pie_der": (-0.10, 0.08, 0.10, 45, -8), "pie_izq": (0.10, -0.02, 0.10, 45, -4),
            "mano_der": ((-0.26, -0.26, 1.62), (0, -0.3, 1), (-1, 0, 0)), "mano_izq": ((0.26, -0.26, 1.62), (0, -0.3, 1), (1, 0, 0)),
            "fusil": 0.0, "correa": 1.0}
AIRE = {"pelvis": (0, 0.0, 0.10, 14, 0, -6), "stomach": (6, 0, -2), "chest": (6, 0, -6), "head": (18, 0, 8),
        "pie_der": (-0.10, 0.34, 0.26, 35, -10), "pie_izq": (0.10, -0.26, 0.42, -12, -4),
        "mano_der": ((-0.20, 0.10, 1.96), (0, 0.2, 1), (0, 1, 0)), "mano_izq": ((0.42, -0.34, 1.28), (1, -0.4, 0), ARRIBA),
        "fusil": 0.0, "correa": 1.0}
# EL IMPACTO: superheroe. La muneca del golpe se calcula (ver PUNO_SUELO) para que el puno toque el suelo de verdad
IMPACTO_P = {"pelvis": (0.02, -0.04, -0.40, 42, 4, -10), "stomach": (20, 2, -6), "chest": (34, 4, -12), "head": (20, 0, 14),
             "pie_der": (-0.10, 0.44, 0, 76, -8), "pie_izq": (0.10, -0.28, 0, 0, -4),
             "mano_der": ((-0.20, -0.36, 0.06), ABAJO, (0, -1, 0)), "mano_izq": ((0.52, 0.12, 0.92), (1, 0.3, -0.3), ARRIBA),
             "fusil": 0.0, "correa": 1.0}
MIRA = dict(IMPACTO_P, head=(-14, 0, 10), chest=(22, 3, -10), mano_izq=((0.40, 0.04, 0.80), (1, 0.3, -0.3), ARRIBA))


def pose_de(p, extra=None):
    q = dict(p)
    if extra:
        q.update(extra)
    return q


if PARTE == "despegue":
    CLAVES = [(1, REPOSO), (6, pose_de(REPOSO, {"fusil": 0.0, "correa": 0.5,
                                                 "mano_der": ((-0.20, 0.0, 1.00), (0, 0.2, -1), (-1, 0, 0)),
                                                 "mano_izq": ((0.20, -0.10, 1.00), (0, 0.2, -1), (1, 0, 0)),
                                                 "pelvis": (0, 0.02, -0.12, 10, 0, -6)})),
              (13, AGACHADO), (17, ESTIRADO), (22, pose_de(AIRE, {"pie_der": (-0.10, 0.20, 0.20, 40, -10),
                                                                   "pie_izq": (0.10, -0.14, 0.30, 10, -4)})),
              (N, AIRE)]
elif PARTE == "aire":
    # un bucle vivo: los brazos y las piernas se mueven un poco (el frame N+1 es el 1 otra vez)
    VIVO = pose_de(AIRE, {"mano_der": ((-0.21, 0.13, 1.99), (0, 0.2, 1), (0, 1, 0)),
                          "mano_izq": ((0.44, -0.30, 1.24), (1, -0.4, 0), ARRIBA),
                          "pie_izq": (0.10, -0.28, 0.46, -14, -4), "pie_der": (-0.10, 0.36, 0.24, 38, -10),
                          "head": (20, 0, 8)})
    CLAVES = [(1, AIRE), (31, VIVO), (N + 1, AIRE)]
else:
    CLAVES = [(1, AIRE), (5, pose_de(IMPACTO_P, {"pelvis": (0.01, -0.03, -0.30, 26, 2, -8),
                                                 "mano_der": ((-0.20, -0.30, 0.55), ABAJO, (0, -1, 0)),
                                                 "pie_der": (-0.10, 0.40, 0.06, 60, -8)})),
              (8, IMPACTO_P), (10, pose_de(IMPACTO_P, {"pelvis": (0.02, -0.04, -0.42, 35, 4, -10)})),
              (18, IMPACTO_P), (32, MIRA), (42, MIRA),
              (54, pose_de(REPOSO, {"pelvis": (0.01, -0.02, -0.22, 16, 2, -8), "stomach": (8, 0, -4), "chest": (10, 0, -8),
                                    "head": (-4, 0, 14), "pie_der": (-0.08, 0.30, 0.03, 30, -12), "pie_izq": (0.08, -0.26, 0, 0, -6),
                                    "mano_der": ((-0.22, -0.18, 0.80), (0, -0.3, -1), (-1, 0, 0)),
                                    "mano_izq": ((0.24, -0.10, 0.85), (0, -0.3, -1), (1, 0, 0)), "fusil": 0.0, "correa": 1.0})),
              (68, pose_de(REPOSO, {"pie_der": (-0.05, 0.14, 0.04, 0, -16), "pie_izq": (0.05, -0.14, 0, 0, -6),
                                    "pelvis": (0, 0, -0.06, 4, 0, -10), "fusil": 0.0, "correa": 1.0,
                                    "mano_der": ((-0.20, -0.16, 1.02), (0, -0.4, -1), (-1, 0, 0)),
                                    "mano_izq": ((0.12, -0.30, 1.12), (0, -0.4, -1), (1, 0, 0))})),
              (78, pose_de(REPOSO, {"fusil": 0.0, "correa": 0.4})), (88, REPOSO), (N, REPOSO)]

GUARDIA = arma((-0.16, 0.02, 1.22), 15, -10, 0)
POSE_CORREA = arma((-0.22, 0.04, 0.98), 0, -75, -90)
GUARDA = mano((0.0, -0.22, -0.022), (-0.55, -0.45, 0.15), (0.45, 0, -0.9))
EMPUNA = mano((-0.022, 0.035, -0.08), (0.4, -0.55, -0.7), (-1, 0, 0.35))


def canal(nombre, f):
    return interp([(k[0], tuple(k[1][nombre])) for k in CLAVES], f)


def peso_canal(nombre, f):
    return peso([(k[0], k[1][nombre]) for k in CLAVES], f)


def mano_mundo(nombre, f):
    pos = Vector(interp([(k[0], k[1][nombre][0]) for k in CLAVES], f))
    if f <= CLAVES[0][0]:
        a = b = CLAVES[0]
    elif f >= CLAVES[-1][0]:
        a = b = CLAVES[-1]
    else:
        i = max(j for j in range(len(CLAVES) - 1) if CLAVES[j][0] <= f)
        a, b = CLAVES[i], CLAVES[i + 1]
    w = 0.0 if a is b else (f - a[0]) / (b[0] - a[0])
    ra = marco((0, 0, 0), *a[1][nombre][1:]).to_quaternion().slerp(marco((0, 0, 0), *b[1][nombre][1:]).to_quaternion(),
                                                                   w * w * (3 - 2 * w))
    mc = ra.to_matrix().to_4x4()
    mc.translation = pos - mc.col[1].xyz * 0.065 + mc.col[2].xyz * 0.03
    return mc


# ================================================================ HORNEADO
DG = bpy.context.evaluated_depsgraph_get()
FRAMES = range(1, N + 1)
for f in FRAMES:
    dx, dy, dz, pt, rl, yw = canal("pelvis", f)
    h = BN["pelvis"].head_local
    clave("pelvis", T((dx, dy, dz)) @ T(h) @ rot(pt, rl, yw) @ T(-h) @ BN["pelvis"].matrix_local, f)
    for n in ("stomach", "chest", "head"):
        giro(n, rot(*canal(n, f)), f)
    for lado in ("der", "izq"):
        fx, fy, fz, fp, fyw = canal("pie_" + lado, f)
        rest = BN["IK_pie_" + lado].matrix_local
        hh = rest.translation
        clave("IK_pie_" + lado, T((fx, fy, max(fz, 0.0))) @ T(hh) @ rot(fp, 0, fyw) @ T(-hh) @ rest, f)

# EL PUNO EN EL SUELO: en el golpe la muneca se pone donde el puno toca el suelo de verdad, a lo que llegue el brazo
# desde el hombro de ESE frame (si el brazo no llega, se estira hacia alli sin doblarse raro)
L_BRAZO = (BN["arm_lower_l"].head_local - BN["arm_upper_l"].head_local).length + \
    (BN["hand_l"].head_local - BN["arm_lower_l"].head_local).length
SUELO_W = [(1, 0), (5, 0.6), (8, 1), (38, 1), (50, 0), (N, 0)] if PARTE == "golpe" else [(1, 0), (N, 0)]
for f in FRAMES:
    sc.frame_set(f)
    ev = rig.evaluated_get(DG).pose.bones
    kk = peso_canal("correa", f)
    en_manos = GUARDIA
    colgado = ev["stomach"].matrix @ BN["stomach"].matrix_local.inverted() @ POSE_CORREA
    w = mezcla(en_manos, colgado, kk)
    clave("CTRL_arma", w, f)
    for lado, agarre, hueso in (("der", EMPUNA, "arm_upper_l"), ("izq", GUARDA, "arm_upper_r")):
        mm = mano_mundo("mano_" + lado, f)
        hom = ev[hueso].head
        ws = peso(SUELO_W, f)
        if lado == "der" and ws > 0.0:
            # la muneca justo debajo del hombro y un palmo por delante, con el puno (6,5 cm) apoyado en el suelo
            quiere = Vector((hom.x - 0.02, hom.y - 0.14, 0.13))
            ms = marco((0, 0, 0), ABAJO, (0, -1, 0))
            ms.translation = quiere
            mm = mezcla(mm, ms, ws)
        # NINGUNA MANO MAS LEJOS DE LO QUE LLEGA EL BRAZO: el IK la perseguia doblando el codo hacia cualquier lado
        d = mm.translation - hom
        if d.length > L_BRAZO * 0.985:
            mm.translation = hom + d.normalized() * (L_BRAZO * 0.985)
        clave("IK_mano_" + lado, mezcla(mm, w @ agarre, peso_canal("fusil", f)), f, w)
    for ob, m in ((mags["Cargador_viejo"], w @ T(AF.MAG_ASIENTO)),
                  (mags["Cargador_nuevo"], ev["stomach"].matrix @ BN["stomach"].matrix_local.inverted() @ RR.FUNDA_MAG)):
        loc, qq, _ = m.decompose()
        ob.location, ob.rotation_quaternion = loc, qq
        ob.keyframe_insert("location", frame=f)
        ob.keyframe_insert("rotation_quaternion", frame=f)

me = bpy.data.meshes.new("Suelo")
me.from_pydata([(-2, -2, 0), (2, -2, 0), (2, 2, 0), (-2, 2, 0)], [], [(0, 1, 2, 3)])
ca = me.color_attributes.new("Col", 'FLOAT_COLOR', 'CORNER')
for li in range(4):
    ca.data[li].color = (0.22, 0.23, 0.25, 1)
me.color_attributes.active_color = ca
sc.collection.objects.link(bpy.data.objects.new("Suelo", me))

for ob in [rig] + list(mags.values()):
    ad = ob.animation_data
    if ad and ad.action:
        for layer in ad.action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    for fc in bag.fcurves:
                        for kp in fc.keyframe_points:
                            kp.interpolation = 'LINEAR'

err = {"der": (0.0, 0), "izq": (0.0, 0)}
pie_min, rodilla_min = 1.0, 1.0
for f in FRAMES:
    sc.frame_set(f)
    ev = rig.evaluated_get(DG).pose.bones
    for lado, s in (("der", "l"), ("izq", "r")):
        e = (ev["hand_" + s].head - ev["IK_mano_" + lado].head).length
        if e > err[lado][0]:
            err[lado] = (e, f)
    pie_min = min(pie_min, ev["foot_l"].head.z, ev["foot_r"].head.z)
    rodilla_min = min(rodilla_min, ev["leg_lower_l"].head.z)
print("ERROR_IK_MANOS_CM", {k: (round(v[0] * 100, 1), v[1]) for k, v in err.items()})
print("TOBILLO_MAS_BAJO_Z", round(pie_min, 3), "RODILLA_DERECHA_MAS_BAJA_Z", round(rodilla_min, 3))
if PARTE == "golpe":
    sc.frame_set(8)
    ev = rig.evaluated_get(DG).pose.bones
    print("IMPACTO f8: muneca derecha z %.3f (el puno toca el suelo si ~0,13), rodilla derecha z %.3f, hombro z %.3f" % (
        ev["hand_l"].head.z, ev["leg_lower_l"].head.z, ev["arm_upper_l"].head.z))
sc["juego_desde"], sc["juego_hasta"] = 1, N
sc.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=args[1])
print("LISTO", PARTE, args[1])
