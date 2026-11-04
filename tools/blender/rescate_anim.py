"""RESCATE DE UN COMPAÑERO: seis clips sobre el soldado de Breach (2026-09-23, pedido).

blender -b --factory-startup --python tools/blender/rescate_anim.py -- <soldado_breach.blend> <salida.blend> <clip>

<clip> es uno de:
  rescate_levantar  (1,5 s, una vez)  agacharse, coger el cuerpo con las dos manos y subirlo al hombro derecho
  rescate_cargar    (1,0 s, ciclo)    andar con el cuerpo al hombro: la derecha abraza sus piernas, la izquierda
                                      en su espalda para que no se caiga
  rescate_soltar    (0,8 s, una vez)  inclinarse y dejarlo en el suelo
  rescate_rcp       (0,6 s, ciclo)    de rodillas, brazos rectos, compresiones en el pecho (unas 100 por minuto)
  rescate_ayudar    (2,4 s, una vez)  de la RCP a medio levantarse, le da la mano, tira de el hasta ponerlo de
                                      pie, un paso hacia el y dos palmadas en el hombro
  rescate_revivido  (2,4 s, una vez)  EL QUE REVIVE: tumbado boca arriba y atravesado delante del que le hizo la
                                      RCP, mueve la cabeza (se despierta), levanta la mano, se la cogen, se sienta,
                                      se pone de pie y recibe las palmadas

LOS DOS ENCAJAN EN EL MISMO SITIO. El que revive queda en el origen mirando a -Y; el que ayuda, 0,9 m delante
de el, mirandole. En el frame 1 el pecho del tumbado esta en (0, -0.48, 0.2): justo donde el que ayuda tiene
las manos en la RCP (0, -0.42) contado desde el. Las dos manos derechas se encuentran en (0, -0.45, z) en los
dos sistemas (son simetricos), asi que el apreton cuadra sin tocar nada en el juego.

Ejes: Blender Z arriba, el soldado mira a -Y, su DERECHA es -X (`der` mueve hand_l, que el exportador espeja).
Poses clave interpoladas (Hermite / Catmull-Rom, como mazo_anim.py); manos y pies por IK.
Exportar: tools/blender/exportar_clips.py <clips_breach.json> <clip> <vel> 30 [unavez]
"""
import bpy, math, os, sys
from mathutils import Vector, Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import recarga_rig as RR

args = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.open_mainfile(filepath=args[0])
SALIDA, CLIP = args[1], args[2]
rig, mags = RR.montar()
for n in ("Fusil", "Manija", "Cargador_viejo", "Cargador_nuevo", "Portacargador"):
    if n in bpy.data.objects:
        bpy.data.objects.remove(bpy.data.objects[n], do_unlink=True)
sc = bpy.context.scene
FPS = 30
LARGO = {"rescate_levantar": 45, "rescate_cargar": 30, "rescate_soltar": 24, "rescate_rcp": 18,
         "rescate_ayudar": 72, "rescate_revivido": 72}
N = LARGO[CLIP]
sc.render.fps, sc.frame_start, sc.frame_end = FPS, 1, N
PB, BN = rig.pose.bones, rig.data.bones
rad, T = math.radians, Matrix.Translation
I4 = Matrix.Identity(4)


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


def mano(contacto, dedos, palma_arriba):
    """matriz de la mano: en `contacto`, los dedos hacia `dedos` y el dorso hacia `palma_arriba`"""
    y = Vector(dedos).normalized()
    x = y.cross(Vector(palma_arriba)).normalized()
    mm = Matrix((x, y, x.cross(y))).transposed().to_4x4()
    mm.translation = Vector(contacto) - mm.col[1].xyz * 0.065
    return mm


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


def ciclo(keys):
    """para los clips en bucle: la ultima clave es la primera, y se añade una antes y otra despues para que la
    tangente del cierre sea la de un ciclo (sin frenazo al dar la vuelta)"""
    a, b = keys[-2], keys[1]
    return [(a[0] - N, a[1])] + keys + [(b[0] + N, b[1])]


# ================================================================================ LAS POSES
# pelvis: (dx, dy, dz, cabeceo, alabeo, guinada) · stomach / chest / neck / head: (cabeceo, alabeo, guinada)
# manos: (x, y, z, dedos_x, dedos_y, dedos_z) · pies: (dx, dy, dz, cabeceo, 0, guinada) desde su reposo
Z0 = (0, 0, 0, 0, 0, 0)
PIE_D0 = (-0.03, 0.02, 0, 0, 0, -6)      # la derecha un poco abierta
PIE_I0 = (0.03, -0.02, 0, 0, 0, 6)
CARGA_D = (-0.30, -0.20, 1.42, 0.2, -0.3, 0.9)     # abraza sus piernas delante del hombro derecho
CARGA_I = (-0.08, -0.30, 1.30, -0.9, 0.1, 0.3)     # la izquierda cruzada, sobre su espalda
LADO_D = (-0.24, -0.02, 0.80, 0, 0, -1)
LADO_I = (0.24, -0.02, 0.80, 0, 0, -1)

if CLIP == "rescate_levantar":
    PELVIS = [(1, Z0), (12, (0, 0.06, -0.42, 26, 0, 0)), (22, (0, 0.04, -0.38, 32, 0, -4)),
              (32, (0, 0.02, -0.16, 16, -2, -10)), (45, (0, 0.02, -0.05, 8, -3, -8))]
    STOM = [(1, (0, 0, 0)), (12, (16, 0, 0)), (22, (22, 0, 0)), (32, (8, -4, -6)), (45, (6, -5, -4))]
    CHEST = [(1, (0, 0, 0)), (12, (24, 0, 0)), (22, (30, 0, 0)), (32, (10, -6, -8)), (45, (8, -6, -6))]
    HEAD = [(1, (0, 0, 0)), (12, (18, 0, 0)), (22, (14, 0, 0)), (32, (-4, 4, 10)), (45, (-6, 4, 8))]
    MD = [(1, LADO_D), (12, (-0.16, -0.46, 0.24, 0, -0.3, -1)), (22, (-0.15, -0.42, 0.46, 0, -0.5, 0.6)),
          (32, (-0.28, -0.22, 1.12, 0.1, -0.4, 0.9)), (45, CARGA_D)]
    MI = [(1, LADO_I), (12, (0.16, -0.46, 0.24, 0, -0.3, -1)), (22, (0.12, -0.42, 0.50, 0, -0.5, 0.6)),
          (32, (-0.02, -0.32, 1.18, -0.6, -0.3, 0.5)), (45, CARGA_I)]
    PD = [(1, PIE_D0), (45, PIE_D0)]
    PI = [(1, PIE_I0), (8, (0.05, -0.16, 0, 0, 0, 8)), (45, (0.05, -0.16, 0, 0, 0, 8))]
elif CLIP == "rescate_cargar":
    # PASO CORTO Y PESADO: 0,3 m por paso, la cadera baja al apoyar y se balancea hacia el pie de apoyo
    PELVIS = ciclo([(1, (0, 0.02, -0.07, 8, -3, -8)), (8, (0.012, 0.02, -0.04, 8, -1, -6)),
                    (16, (0, 0.02, -0.07, 8, -3, -8)), (23, (-0.012, 0.02, -0.04, 8, -5, -10)), (31, (0, 0.02, -0.07, 8, -3, -8))])
    STOM = ciclo([(1, (6, -5, -4)), (8, (6, -4, -2)), (16, (6, -5, -4)), (23, (6, -6, -6)), (31, (6, -5, -4))])
    CHEST = ciclo([(1, (8, -6, -6)), (8, (8, -5, -3)), (16, (8, -6, -6)), (23, (8, -7, -9)), (31, (8, -6, -6))])
    HEAD = ciclo([(1, (-6, 4, 8)), (16, (-5, 4, 8)), (31, (-6, 4, 8))])
    MD = [(1, CARGA_D), (N + 1, CARGA_D)]
    MI = [(1, CARGA_I), (N + 1, CARGA_I)]
    PD = ciclo([(1, (-0.03, -0.15, 0, 0, 0, -6)), (15, (-0.03, 0.15, 0, 0, 0, -6)),
                (22, (-0.03, 0.0, 0.09, -15, 0, -6)), (31, (-0.03, -0.15, 0, 0, 0, -6))])
    PI = ciclo([(1, (0.03, 0.15, 0, 0, 0, 6)), (8, (0.03, 0.0, 0.09, -15, 0, 6)),
                (16, (0.03, -0.15, 0, 0, 0, 6)), (31, (0.03, 0.15, 0, 0, 0, 6))])
elif CLIP == "rescate_soltar":
    PELVIS = [(1, (0, 0.02, -0.05, 8, -3, -8)), (10, (0, 0.04, -0.14, 18, -2, -6)),
              (16, (0, 0.05, -0.22, 24, 0, 0)), (24, Z0)]
    STOM = [(1, (6, -5, -4)), (10, (14, -2, -2)), (16, (18, 0, 0)), (24, (0, 0, 0))]
    CHEST = [(1, (8, -6, -6)), (10, (18, -3, -3)), (16, (24, 0, 0)), (24, (0, 0, 0))]
    HEAD = [(1, (-6, 4, 8)), (10, (10, 2, 4)), (16, (16, 0, 0)), (24, (0, 0, 0))]
    MD = [(1, CARGA_D), (10, (-0.26, -0.44, 1.05, 0, -0.6, 0.5)), (16, (-0.20, -0.52, 0.72, 0, -0.5, -0.6)), (24, LADO_D)]
    MI = [(1, CARGA_I), (10, (0.02, -0.46, 1.02, 0, -0.6, 0.5)), (16, (0.12, -0.52, 0.72, 0, -0.5, -0.6)), (24, LADO_I)]
    PD = [(1, PIE_D0), (24, PIE_D0)]
    PI = [(1, PIE_I0), (24, PIE_I0)]
elif CLIP in ("rescate_rcp", "rescate_ayudar"):
    # DE RODILLAS: las rodillas en el suelo y los empeines detras; la cadera sobre los talones algo levantada
    RODILLAS_D = (-0.05, 0.38, -0.05, 72, 0, -4)
    RODILLAS_I = (0.05, 0.38, -0.05, 72, 0, 4)
    ARRIBA = (0, 0.06, -0.50, 30, 0, 0)
    ABAJO = (0, 0.07, -0.54, 36, 0, 0)
    MANOS_A = (0.0, -0.42, 0.33)
    MANOS_B = (0.0, -0.42, 0.27)
    if CLIP == "rescate_rcp":
        PELVIS = ciclo([(1, ARRIBA), (9, ABAJO), (19, ARRIBA)])
        STOM = ciclo([(1, (14, 0, 0)), (9, (18, 0, 0)), (19, (14, 0, 0))])
        CHEST = ciclo([(1, (16, 0, 0)), (9, (22, 0, 0)), (19, (16, 0, 0))])
        HEAD = ciclo([(1, (20, 0, 0)), (9, (24, 0, 0)), (19, (20, 0, 0))])
        # las dos manos una sobre otra, dedos entrelazados, brazos rectos
        MD = ciclo([(1, (-0.012, *MANOS_A[1:], 0.2, -0.3, -1)), (9, (-0.012, *MANOS_B[1:], 0.2, -0.3, -1)), (19, (-0.012, *MANOS_A[1:], 0.2, -0.3, -1))])
        MI = ciclo([(1, (0.012, MANOS_A[1], MANOS_A[2] + 0.025, -0.2, -0.3, -1)), (9, (0.012, MANOS_B[1], MANOS_B[2] + 0.025, -0.2, -0.3, -1)),
                    (19, (0.012, MANOS_A[1], MANOS_A[2] + 0.025, -0.2, -0.3, -1))])
        PD = [(1, RODILLAS_D), (N + 1, RODILLAS_D)]
        PI = [(1, RODILLAS_I), (N + 1, RODILLAS_I)]
    else:
        # AYUDAR A LEVANTARSE. Mano derecha: de la RCP a coger la suya (0,-0.45,0.55) y subirla con el hasta
        # (0,-0.45,1.10); un paso adelante; dos palmadas en su hombro con la izquierda; suelta y se endereza.
        PELVIS = [(1, ARRIBA), (12, (0, 0.04, -0.32, 22, 0, 0)), (20, (0, 0.03, -0.26, 18, 0, 0)),
                  (36, (0, 0.01, -0.08, 8, 0, 0)), (46, (0, 0.0, -0.02, 4, 0, 0)), (54, (0, -0.24, -0.03, 4, 2, 4)),
                  (64, (0, -0.24, -0.02, 3, 2, 4)), (72, (0, -0.24, 0.0, 0, 0, 0))]
        STOM = [(1, (14, 0, 0)), (12, (14, 0, 0)), (20, (12, 0, 2)), (36, (4, 0, 0)), (54, (2, 2, 6)), (72, (0, 0, 0))]
        CHEST = [(1, (16, 0, 0)), (12, (18, 0, 0)), (20, (14, 0, 2)), (36, (6, 0, 0)), (54, (4, 3, 8)), (64, (4, 3, 8)), (72, (0, 0, 0))]
        HEAD = [(1, (20, 0, 0)), (20, (24, 0, 0)), (36, (6, 0, 0)), (54, (0, 0, 0)), (64, (2, 0, -4)), (72, (0, 0, 0))]
        CONTACTO = [(1, MANOS_A), (14, (0.0, -0.45, 0.50)), (20, (0.0, -0.45, 0.55)), (46, (0.0, -0.45, 1.10)),
                    (54, (0.0, -0.69, 1.10)), (64, (0.0, -0.69, 1.12)), (72, (-0.24, -0.26, 0.80))]
        MD = [(k[0], (k[1][0] - 0.01, k[1][1], k[1][2], 0.0, -1.0, 0.1)) for k in CONTACTO]
        MI = [(1, (0.012, MANOS_A[1], MANOS_A[2] + 0.025, -0.2, -0.3, -1)), (14, (0.22, -0.20, 0.70, 0, 0, -1)),
              (46, (0.24, -0.05, 0.85, 0, 0, -1)), (52, (0.10, -0.66, 1.40, 0, -1, 0.2)),
              (56, (0.10, -0.66, 1.36, 0, -1, 0.2)), (58, (0.10, -0.66, 1.42, 0, -1, 0.2)),
              (60, (0.10, -0.66, 1.36, 0, -1, 0.2)), (64, (0.10, -0.66, 1.41, 0, -1, 0.2)), (72, (0.24, -0.26, 0.80, 0, 0, -1))]
        PD = [(1, RODILLAS_D), (14, (-0.04, 0.10, 0.0, 10, 0, -4)), (22, (-0.03, 0.02, 0, 0, 0, -6)),
              (48, (-0.03, 0.02, 0, 0, 0, -6)), (51, (-0.03, -0.12, 0.08, -10, 0, -6)), (54, (-0.03, -0.24, 0, 0, 0, -6)),
              (72, (-0.03, -0.22, 0, 0, 0, -6))]
        PI = [(1, RODILLAS_I), (12, (0.05, 0.30, -0.05, 72, 0, 4)), (20, (0.04, 0.02, 0, 0, 0, 6)),
              (50, (0.04, 0.0, 0, 0, 0, 6)), (54, (0.04, -0.12, 0.08, -10, 0, 6)), (58, (0.04, -0.26, 0, 0, 0, 6)),
              (72, (0.03, -0.26, 0, 0, 0, 6))]
elif CLIP == "rescate_revivido":
    # TUMBADO ATRAVESADO (la cabeza a su izquierda, +X): la cadera en (-0.35, -0.48) y el pecho en (0, -0.48),
    # bajo las manos de la RCP. Se despierta (la cabeza de lado a lado), levanta la derecha, se la cogen, se sienta
    # girando hacia el que le ayuda, se pone de pie y recibe las palmadas.
    TUMB = (-0.35, -0.52, -0.66, -90, 0, -90)
    PELVIS = [(1, TUMB), (18, TUMB), (26, (-0.28, -0.46, -0.60, -80, 0, -80)),
              (34, (-0.10, -0.30, -0.52, -40, 0, -35)), (42, (0, -0.10, -0.36, 20, 0, -8)),
              (52, (0, 0.0, -0.06, 6, 0, 0)), (60, (0, 0.0, -0.03, 4, 0, 0)), (72, Z0)]
    STOM = [(1, (0, 0, 0)), (26, (6, 0, 0)), (34, (28, 0, 0)), (42, (18, 0, 0)), (52, (4, 0, 0)), (72, (0, 0, 0))]
    CHEST = [(1, (0, 0, 0)), (26, (10, 0, 0)), (34, (30, 0, 0)), (42, (18, 0, 0)), (52, (4, 0, 0)), (72, (0, 0, 0))]
    # la cabeza: quieta, luego de un lado al otro (se despierta), mira al que le ayuda y asiente con las palmadas
    HEAD = [(1, (0, 0, 0)), (6, (0, 0, 0)), (10, (0, 0, 28)), (14, (0, 0, -24)), (18, (6, 0, 12)),
            (26, (10, 0, 0)), (42, (4, 0, 0)), (56, (8, 0, 0)), (60, (-2, 0, 0)), (64, (8, 0, 0)), (72, (0, 0, 0))]
    CONTACTO = [(1, (-0.20, -0.60, 0.10)), (18, (-0.20, -0.60, 0.10)), (22, (0.0, -0.45, 0.50)),
                (26, (0.0, -0.45, 0.55)), (46, (0.0, -0.45, 1.10)), (54, (0.0, -0.45, 1.10)),
                (64, (0.0, -0.45, 1.12)), (72, LADO_D[:3])]
    MD = [(k[0], (k[1][0] + 0.01, k[1][1], k[1][2], 0.0, -1.0, 0.1)) for k in CONTACTO]
    MI = [(1, (0.18, -0.30, 0.08, 1, 0, 0)), (26, (0.20, -0.25, 0.08, 1, 0, 0)), (34, (0.26, -0.18, 0.10, 0, 0, -1)),
          (42, (0.18, -0.28, 0.50, 0, 0, -1)), (52, LADO_I), (72, LADO_I)]
    # las piernas: estiradas en el suelo hacia su derecha (-X), se recogen al sentarse y acaban debajo
    PD = [(1, (-0.80, -0.48, -0.06, -90, 0, -90)), (26, (-0.78, -0.48, -0.06, -90, 0, -90)),
          (34, (-0.35, -0.30, 0.0, -20, 0, -40)), (42, (-0.06, -0.08, 0, 0, 0, -8)), (72, PIE_D0)]
    PI = [(1, (-0.80, -0.62, -0.06, -90, 0, -90)), (26, (-0.76, -0.62, -0.06, -90, 0, -90)),
          (34, (-0.25, -0.45, 0.0, -20, 0, -40)), (42, (0.06, -0.02, 0, 0, 0, 8)), (72, PIE_I0)]
else:
    raise SystemExit("clip desconocido: " + CLIP)

# ================================================================================ HORNEADO
H = BN["pelvis"].head_local
for f in range(1, N + 1):
    dx, dy, dz, pt, rl, yw = interp(PELVIS, f)
    clave("pelvis", T((dx, dy, dz)) @ T(H) @ rot(pt, rl, yw) @ T(-H) @ BN["pelvis"].matrix_local, f)
    for n, keys in (("stomach", STOM), ("chest", CHEST), ("head", HEAD)):
        giro(n, rot(*interp(keys, f)), f)
    for lado, keys in (("der", MD), ("izq", MI)):
        x, y, z, fx, fy, fz = interp(keys, f)
        arriba = (0, 0, 1) if abs(fz) < 0.8 else (0, -1, 0)
        clave("IK_mano_" + lado, mano((x, y, z), (fx, fy, fz), arriba), f, I4)
    for lado, keys in (("der", PD), ("izq", PI)):
        rest = BN["IK_pie_" + lado].matrix_local
        hh = rest.translation
        dx, dy, dz, pt, _, yw = interp(keys, f)
        clave("IK_pie_" + lado, T((dx, dy, dz)) @ T(hh) @ rot(pt, 0, yw) @ T(-hh) @ rest, f)

for layer in rig.animation_data.action.layers:
    for strip in layer.strips:
        for bag in strip.channelbags:
            for fc in bag.fcurves:
                for kp in fc.keyframe_points:
                    kp.interpolation = 'LINEAR'

# comprobacion: ¿llegan las manos a donde se les pide?
DG = bpy.context.evaluated_depsgraph_get()
peor = {"der": 0.0, "izq": 0.0}
for f in range(1, N + 1):
    sc.frame_set(f)
    ev = rig.evaluated_get(DG).pose.bones
    for lado, s in (("der", "l"), ("izq", "r")):
        peor[lado] = max(peor[lado], (ev["hand_" + s].head - ev["IK_mano_" + lado].head).length)
print("ERROR_IK_MANOS_CM", {k: round(v * 100, 1) for k, v in peor.items()})
sc.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=SALIDA)
print("LISTO", CLIP, N, "frames")
