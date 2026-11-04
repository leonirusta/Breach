"""Retargeting del esqueleto del .bin a la geometria del modelo voxel.

Idea: los marcos del .bin son los correctos (dan los ejes de flexion reales), pero
sus proporciones no son las del modelo voxel. Se corrige cada marco con una rotacion
C_b que lleva la direccion del hueso del .bin sobre la direccion del hueso voxel, y
se reexpresan las claves:   q'_b = C_padre^-1 * q_b * C_b
Los offsets de reposo pasan a ser los deltas voxel exactos, asi que los pivotes caen
justo en las articulaciones del modelo y las piezas no se separan.
"""
import math, os, json, struct
from avatar_data import qmul, qconj, qnorm, qrot, qslerp, AV

S = 21.18            # voxeles por metro
ROOT = "Bip001"


def load_raw():
    rig = json.load(open(os.path.join(AV, "avatar_rig.json")))
    pal = json.load(open(os.path.join(AV, "palette.json")))
    data = open(os.path.join(AV, "sven_lagom.bin"), "rb").read()
    o = 0

    def u32():
        nonlocal o
        v = struct.unpack_from("<I", data, o)[0]
        o += 4
        return v

    def u16():
        nonlocal o
        v = struct.unpack_from("<H", data, o)[0]
        o += 2
        return v

    def f32():
        nonlocal o
        v = struct.unpack_from("<f", data, o)[0]
        o += 4
        return v

    def st():
        nonlocal o
        l = u16()
        v = data[o:o + l].decode()
        o += l
        return v

    bind = {}
    for _ in range(u32()):
        n = st()
        bind[n] = qnorm(struct.unpack_from("<4f", data, o))
        o += 16
    clips = {}
    for _ in range(u32()):
        name = st()
        fps = f32()
        cb = {}
        for _ in range(u32()):
            bn = st()
            ks = []
            for _ in range(u32()):
                v = struct.unpack_from("<8f", data, o)
                o += 32
                ks.append(((v[0], v[1], v[2]), qnorm(v[3:7]), v[7]))
            cb[bn] = ks
        clips[name] = {"fps": fps, "bones": cb}

    # ESPEJO EN Z.
    # La animacion y el modelo no estan girados, estan reflejados: la izquierda coincide
    # (pierna_l en +X en ambos) pero el adelante no (los dedos van a z mayor que el
    # tobillo en la animacion y a z menor en el modelo). Por eso run_fwd inclinaba el
    # torso al reves de donde mira la cara y run_bwd al derecho, y por eso ningun giro
    # lo arreglaba: un giro habria invertido tambien izquierda y derecha.
    # Al reflejar el mundo con diag(1,1,-1): las posiciones cambian pz -> -pz y los
    # cuaterniones (x,y,z,w) -> (-x,-y,z,w).
    def mz_q(q):
        return (-q[0], -q[1], q[2], q[3])

    def mz_p(p):
        return (p[0], p[1], -p[2])

    bind = {n: mz_q(q) for n, q in bind.items()}
    for c in clips.values():
        for bn, ks in c["bones"].items():
            c["bones"][bn] = [(mz_p(k[0]), mz_q(k[1]), k[2]) for k in ks]

    return rig, pal, bind, clips


def _ln(v):
    return math.sqrt(sum(c * c for c in v)) or 1.0


def _unit(v):
    n = _ln(v)
    return (v[0] / n, v[1] / n, v[2] / n)


def _between(a, b):
    """rotacion mas corta que lleva a sobre b"""
    a, b = _unit(a), _unit(b)
    d = sum(a[i] * b[i] for i in range(3))
    if d > 0.999999:
        return (0.0, 0.0, 0.0, 1.0)
    if d < -0.999999:
        ax = (1.0, 0.0, 0.0) if abs(a[0]) < 0.9 else (0.0, 1.0, 0.0)
        c = (a[1] * ax[2] - a[2] * ax[1], a[2] * ax[0] - a[0] * ax[2], a[0] * ax[1] - a[1] * ax[0])
        return qnorm((c[0], c[1], c[2], 0.0))
    c = (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
    return qnorm((c[0], c[1], c[2], 1.0 + d))


def build():
    rig, pal, bind, clips = load_raw()
    bones = rig["bones"]
    parents = dict(rig.get("bone_parents", {}))
    parents[ "pelvis"] = ROOT
    parents["radio"] = "pelvis"   # va en el cinturon, tocando el muslo, no en el pecho
    order = [ROOT]

    def walk(n):
        for c in sorted(b for b in bones if parents.get(b) == n):
            order.append(c)
            walk(c)

    walk(ROOT)

    # PIEZAS DESCENTRADAS. El plano sagital del torso esta en x = -0,5 y pelvis,
    # estomago, pecho y cabeza estan centrados ahi, pero el cuello quedaba 0,5 voxels
    # a la izquierda y la capucha 0,5 a la derecha. Se recolocan las piezas enteras.
    SHIFT = {"neck": (-0.5, 0.0, 0.0), "hood": (0.5, 0.0, 0.0)}
    for b, d in SHIFT.items():
        if b in bones:
            wp = bones[b]["world_pos"]
            bones[b]["world_pos"] = [wp[i] + d[i] for i in range(3)]

    min_y = min(b["world_pos"][1] for b in bones.values())

    # PIVOTES REALES. El "world_pos" del rig no es la articulacion: p.ej. arm_upper_l
    # tiene origen en x=7 pero sus voxels van de x=4 a x=11, o sea que pivotaba por la
    # mitad del biceps y el brazo se despegaba del hombro al girar. El pivote correcto
    # es la superficie de contacto entre la pieza del padre y la del hijo.
    VOXW = {}
    for b, bd in bones.items():
        wp = bd["world_pos"]
        VOXW[b] = [(wp[0] + v[0] + 0.5, wp[1] - min_y + v[1] + 0.5, wp[2] + v[2] + 0.5)
                   for v in bd["voxels"]]

    def contact(pn, bn):
        best, bp, bq_ = 1e18, None, None
        for a in VOXW[pn]:
            for c in VOXW[bn]:
                d = (a[0]-c[0])**2 + (a[1]-c[1])**2 + (a[2]-c[2])**2
                if d < best:
                    best, bp, bq_ = d, a, c
        return math.sqrt(best), tuple((bp[i] + bq_[i]) * 0.5 for i in range(3))

    piv = {}
    for bn in order:
        if bn not in bones:
            continue
        pn = parents.get(bn)
        wp = bones[bn]["world_pos"]
        home = (wp[0], wp[1] - min_y, wp[2])
        if pn is None or pn not in bones:
            piv[bn] = home
            continue
        dist, mid = contact(pn, bn)
        # si las piezas no se tocan (accesorios sueltos como la radio) se deja el origen
        piv[bn] = mid if dist <= 3.0 else home
    BIN_REST = {bn: k[0][0] for bn, k in clips["ik_pose_t"]["bones"].items()}

    # marcos globales de reposo del .bin (en voxeles)
    G = {}
    for bn in order:
        pn = parents.get(bn)
        off = tuple(c * S for c in BIN_REST.get(bn, (0, 0, 0)))
        bq = bind.get(bn, (0, 0, 0, 1))
        if pn is None:
            G[bn] = (bq, off)
        else:
            pq, pp = G[pn]
            r = qrot(pq, off)
            G[bn] = (qnorm(qmul(pq, bq)), (pp[0] + r[0], pp[1] + r[1], pp[2] + r[2]))

    # SIMETRIZAR LOS PIVOTES.
    # Las piezas de arte son simetricas (mismo numero de voxels a cada lado) pero sus
    # pivotes no: el antebrazo y la mano izquierdos caian 2 voxels mas afuera, asi que
    # ese brazo era mas largo y colgaba ~1,6 voxels mas bajo que el derecho en idle.
    # Se promedia cada par izquierda/derecha respecto al plano sagital del torso.
    xs = []
    for b in ("pelvis", "stomach", "chest", "neck", "head"):
        wp = bones[b]["world_pos"]
        vx = [wp[0] + v[0] for v in bones[b]["voxels"]]
        xs += [min(vx), max(vx) + 1]
    X0 = (min(xs) + max(xs)) / 2.0

    for base in ("shoulder", "arm_upper", "arm_lower", "hand",
                 "leg_upper", "leg_lower", "foot", "toes"):
        l, r = base + "_l", base + "_r"
        if l not in piv or r not in piv:
            continue
        d = ((piv[l][0] - X0) + (X0 - piv[r][0])) * 0.5
        y = (piv[l][1] + piv[r][1]) * 0.5
        z = (piv[l][2] + piv[r][2]) * 0.5
        piv[l] = (X0 + d, y, z)
        piv[r] = (X0 - d, y, z)

    # AJUSTES MANUALES de pivote, en voxeles y por pares (fuera, arriba, adelante).
    # Se aplican espejados, asi que no rompen la simetria. Toca aqui para afinar.
    ADJUST = {
        "arm_upper": (0.0, -1.0, 0.0),   # tenia el pivote 1 voxel por encima del hombro
                                         # (sacarlo hacia fuera abre 0,8 vox de hueco)
        "leg_lower": (0.0, -1.0, 0.0),   # baja la rodilla: sobresalia de la pierna al agacharse
    }
    for base, (do, dy, dz) in ADJUST.items():
        for side, sx in (("_l", 1.0), ("_r", -1.0)):
            b = base + side
            if b in piv:
                piv[b] = (piv[b][0] + do * sx, piv[b][1] + dy, piv[b][2] + dz)

    # Cadena principal: continuacion natural de cada hueso.
    MAIN = {"pelvis": "stomach", "stomach": "chest", "chest": "neck", "neck": "head",
            "shoulder_l": "arm_upper_l", "shoulder_r": "arm_upper_r",
            "arm_upper_l": "arm_lower_l", "arm_upper_r": "arm_lower_r",
            "arm_lower_l": "hand_l", "arm_lower_r": "hand_r",
            "leg_upper_l": "leg_lower_l", "leg_upper_r": "leg_lower_r",
            "leg_lower_l": "foot_l", "leg_lower_r": "foot_r",
            "foot_l": "toes_l", "foot_r": "toes_r"}

    # MARCOS ANCLADOS A LA PIEL.
    # Los marcos del .bin tienen su "adelante" en +Z, pero la piel mira a -Z (los dedos
    # de los pies estan en z menor que el tobillo). Por eso run_fwd inclinaba el torso al
    # reves de donde mira la cara y run_bwd al derecho: adelante y atras intercambiados.
    # No se arregla girando la raiz: eso gira piel y esqueleto juntos. Se reconstruye el
    # marco de cada hueso con +X sobre el hueso y el alabeo fijado por la mirada de la
    # piel, con lo que el eje de flexion cae en el plano sagital.
    SKIN_FWD = (0.0, 0.0, -1.0)

    def _cross(a_, b_):
        return (a_[1]*b_[2]-a_[2]*b_[1], a_[2]*b_[0]-a_[0]*b_[2], a_[0]*b_[1]-a_[1]*b_[0])

    def _mat2quat(x, y, z):
        m = [[x[0], y[0], z[0]], [x[1], y[1], z[1]], [x[2], y[2], z[2]]]
        tr = m[0][0] + m[1][1] + m[2][2]
        if tr > 0:
            sq = math.sqrt(tr + 1.0) * 2
            return qnorm(((m[2][1]-m[1][2])/sq, (m[0][2]-m[2][0])/sq, (m[1][0]-m[0][1])/sq, 0.25*sq))
        if m[0][0] > m[1][1] and m[0][0] > m[2][2]:
            sq = math.sqrt(1.0 + m[0][0] - m[1][1] - m[2][2]) * 2
            return qnorm((0.25*sq, (m[0][1]+m[1][0])/sq, (m[0][2]+m[2][0])/sq, (m[2][1]-m[1][2])/sq))
        if m[1][1] > m[2][2]:
            sq = math.sqrt(1.0 + m[1][1] - m[0][0] - m[2][2]) * 2
            return qnorm((((m[0][1]+m[1][0])/sq), 0.25*sq, (m[1][2]+m[2][1])/sq, (m[0][2]-m[2][0])/sq))
        sq = math.sqrt(1.0 + m[2][2] - m[0][0] - m[1][1]) * 2
        return qnorm(((m[0][2]+m[2][0])/sq, (m[1][2]+m[2][1])/sq, 0.25*sq, (m[1][0]-m[0][1])/sq))

    def bone_dir(bn):
        k = MAIN.get(bn)
        if k is not None and bn in piv and k in piv:
            v = tuple(piv[k][i] - piv[bn][i] for i in range(3))
            if _ln(v) > 1e-6:
                return _unit(v)
        pn = parents.get(bn)
        if pn and pn in bones:
            return bone_dir(pn)
        return (0.0, 1.0, 0.0)

    C = {}
    for bn in order:
        if bn == ROOT or bn not in bones:
            C[bn] = (0.0, 0.0, 0.0, 1.0)
            continue
        x = bone_dir(bn)
        f = SKIN_FWD if abs(sum(x[i]*SKIN_FWD[i] for i in range(3))) < 0.95 else (0.0, 1.0, 0.0)
        y = _unit(_cross(f, x))
        z = _cross(x, y)
        C[bn] = qnorm(qmul(qconj(G[bn][0]), _mat2quat(x, y, z)))

    # marcos corregidos, offsets voxel exactos, binds locales nuevos
    GP = {}          # marco global de reposo corregido
    rest = {}        # offset local de reposo
    nbind = {}
    for bn in order:
        pn = parents.get(bn)
        gq = qnorm(qmul(G[bn][0], C[bn]))
        if pn is None:
            rest[bn] = tuple(c * S for c in BIN_REST[bn])
            nbind[bn] = gq
            GP[bn] = (gq, rest[bn])
            continue
        if pn == ROOT:
            d = (0.0, 0.0, 0.0)
        else:
            d = tuple(piv[bn][i] - piv[pn][i] for i in range(3))
        pq, pp = GP[pn]
        rest[bn] = qrot(qconj(pq), d)
        nbind[bn] = qnorm(qmul(qconj(pq), gq))
        r = qrot(pq, rest[bn])
        GP[bn] = (gq, (pp[0] + r[0], pp[1] + r[1], pp[2] + r[2]))

    # la raiz del .bin no cae exactamente sobre la pelvis del modelo voxel:
    # se corrige con un offset constante para que el reposo sea exacto
    tgt = piv["pelvis"]
    cur = GP["pelvis"][1]
    root_off = (tgt[0] - cur[0], tgt[1] - cur[1], tgt[2] - cur[2])
    rest[ROOT] = tuple(rest[ROOT][i] + root_off[i] for i in range(3))
    for bn in order:
        GP[bn] = (GP[bn][0], tuple(GP[bn][1][i] + root_off[i] for i in range(3)))

    # desplazamiento de la malla dentro de su hueso: los voxels vienen relativos al
    # antiguo world_pos, hay que referirlos al pivote nuevo
    mesh_off = {}
    for bn in bones:
        wp = bones[bn]["world_pos"]
        home = (wp[0], wp[1] - min_y, wp[2])
        mesh_off[bn] = tuple(home[i] - piv[bn][i] for i in range(3))

    return dict(piv=piv, mesh_off=mesh_off, root_off=root_off, rig=rig, pal=pal, bind=bind, clips=clips, bones=bones, parents=parents,
                order=order, min_y=min_y, C=C, rest=rest, nbind=nbind, GP=GP, S=S, ROOT=ROOT)


def sample(ks, t):
    if len(ks) == 1 or t <= ks[0][2]:
        return ks[0]
    if t >= ks[-1][2]:
        return ks[-1]
    i = 0
    while i < len(ks) - 2 and ks[i + 1][2] <= t:
        i += 1
    ta, tb = ks[i][2], ks[i + 1][2]
    w = 0.0 if tb <= ta else (t - ta) / (tb - ta)
    p = tuple(ks[i][0][j] + (ks[i + 1][0][j] - ks[i][0][j]) * w for j in range(3))
    return (p, qslerp(ks[i][1], ks[i + 1][1], w), t)


# La skin mira hacia -Z (los dedos de los pies estan en z menor que el tobillo) pero
# todas las animaciones se inclinan y zancadean hacia +Z: estan giradas 180 grados
# respecto al modelo. Se corrige rotando la ANIMACION, no el modelo.
YAW180 = (0.0, 1.0, 0.0, 0.0)      # giro de 180 grados alrededor de la vertical


def _strip_yaw(q):
    """quita el giro alrededor de la vertical, conserva cabeceo y alabeo.

    Los clips agachado giran la raiz hasta 53 grados. En el juego la orientacion del
    cuerpo la fija el controlador, asi que ese giro se suma y el personaje camina
    agachado de lado con la cabeza mirando a otro sitio."""
    # componente de giro (twist) alrededor de Y
    ty = (0.0, q[1], 0.0, q[3])
    n = math.sqrt(ty[1] * ty[1] + ty[3] * ty[3])
    if n < 1e-8:
        return q
    ty = (0.0, ty[1] / n, 0.0, ty[3] / n)
    return qnorm(qmul(qconj(ty), q))


def local_pose(M, cname, t):
    """rotacion local (y traslacion de raiz) ya retargeteada, por hueso"""
    cb = M["clips"][cname]["bones"]
    out = {}
    for bn in M["order"]:
        pn = M["parents"].get(bn)
        k = sample(cb[bn], t) if bn in cb else None
        q = k[1] if k else M["bind"].get(bn, (0, 0, 0, 1))
        if bn == M["ROOT"] and k:
            # el giro hay que quitarlo en el marco del MUNDO: la raiz reposa con una
            # permutacion de ejes de 120 grados, asi que su "Y" local no es la vertical
            b0 = M["bind"][bn]
            d = qnorm(qmul(q, qconj(b0)))       # desviacion respecto al reposo, en mundo
            d = qnorm(qmul(YAW180, _strip_yaw(d)))
            q = qnorm(qmul(d, b0))
        cp = M["C"].get(pn, (0, 0, 0, 1)) if pn else (0, 0, 0, 1)
        q = qnorm(qmul(qmul(qconj(cp), q), M["C"][bn]))
        loc = None
        if bn == M["ROOT"] and k:
            lp = qrot(YAW180, tuple(c * M["S"] for c in k[0]))
            loc = tuple(lp[i] + M["root_off"][i] for i in range(3))
        out[bn] = (q, loc)
    return out
