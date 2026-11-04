# Parser del avatar de Breach: avatar_rig.json + sven_lagom.bin
# Replica exactamente la matematica de godot/scripts/avatar_animator.gd
import json, struct, math, os

AV = r"C:\Users\usuario 1\Desktop\Breach\godot\avatar"

# ---- quaterniones (x,y,z,w) como en Godot ----
def qmul(a, b):
    ax,ay,az,aw = a; bx,by,bz,bw = b
    return (aw*bx+ax*bw+ay*bz-az*by,
            aw*by+ay*bw+az*bx-ax*bz,
            aw*bz+az*bw+ax*by-ay*bx,
            aw*bw-ax*bx-ay*by-az*bz)
def qconj(q): return (-q[0],-q[1],-q[2],q[3])
def qnorm(q):
    n = math.sqrt(sum(c*c for c in q)) or 1.0
    return tuple(c/n for c in q)
def qrot(q, v):
    x,y,z,w = q; vx,vy,vz = v
    # v + 2w(qxv) + 2 qx(qxv)
    tx = 2*(y*vz - z*vy); ty = 2*(z*vx - x*vz); tz = 2*(x*vy - y*vx)
    return (vx + w*tx + (y*tz - z*ty),
            vy + w*ty + (z*tx - x*tz),
            vz + w*tz + (x*ty - y*tx))
def qslerp(a, b, t):
    d = sum(a[i]*b[i] for i in range(4))
    if d < 0: b = tuple(-c for c in b); d = -d
    if d > 0.9995: return qnorm(tuple(a[i]+(b[i]-a[i])*t for i in range(4)))
    th = math.acos(max(-1,min(1,d))); s = math.sin(th)
    w1 = math.sin((1-t)*th)/s; w2 = math.sin(t*th)/s
    return qnorm(tuple(a[i]*w1+b[i]*w2 for i in range(4)))

# AXIS_FIX = Quaternion(UP, -PI/2)
_h = -math.pi/4
AXIS_FIX = (0.0, math.sin(_h), 0.0, math.cos(_h))
def to_rig_axes(q):
    return qnorm(qmul(qmul(AXIS_FIX, qnorm(q)), qconj(AXIS_FIX)))

def load():
    rig = json.load(open(os.path.join(AV, "avatar_rig.json")))
    pal = json.load(open(os.path.join(AV, "palette.json")))
    data = open(os.path.join(AV, "sven_lagom.bin"), "rb").read()
    o = 0
    def u32():
        nonlocal o; v = struct.unpack_from("<I", data, o)[0]; o += 4; return v
    def u16():
        nonlocal o; v = struct.unpack_from("<H", data, o)[0]; o += 2; return v
    def f32():
        nonlocal o; v = struct.unpack_from("<f", data, o)[0]; o += 4; return v
    def s():
        nonlocal o; l = u16(); v = data[o:o+l].decode("ascii"); o += l; return v
    bind = {}
    for _ in range(u32()):
        n = s(); q = struct.unpack_from("<4f", data, o); o += 16
        bind[n] = to_rig_axes(q)
    clips = {}
    for _ in range(u32()):
        name = s(); fps = f32(); nb = u32(); cb = {}
        for _ in range(nb):
            bn = s(); nk = u32(); keys = []
            for _ in range(nk):
                px,py,pz,qx,qy,qz,qw,t = struct.unpack_from("<8f", data, o); o += 32
                keys.append(((px,py,pz), to_rig_axes((qx,qy,qz,qw)), t))
            cb[bn] = keys
        clips[name] = {"fps": fps, "bones": cb}
    return rig, pal, bind, clips, len(data) - o

def prepare(rig, bind):
    """orden padres-primero, offsets locales de reposo, bind global"""
    bones = rig["bones"]; parents = rig.get("bone_parents", {})
    min_y = min(b["world_pos"][1] for b in bones.values())
    order, rest_local, bind_global, built = [], {}, {}, set()
    pending = list(bones.keys()); guard = 0
    while pending and guard < 50:
        guard += 1; still = []
        for bn in pending:
            pn = parents.get(bn)
            if pn is not None and pn not in built:
                still.append(bn); continue
            wp = bones[bn]["world_pos"]; wpos = (wp[0], wp[1], wp[2])
            bq = bind.get(bn, (0,0,0,1))
            if pn is not None:
                pwp = bones[pn]["world_pos"]
                pg = bind_global[pn]
                d = (wpos[0]-pwp[0], wpos[1]-pwp[1], wpos[2]-pwp[2])
                loc = qrot(qconj(pg), d)
                bind_global[bn] = qnorm(qmul(pg, bq))
            else:
                loc = (wpos[0], wpos[1]-min_y, wpos[2])
                bind_global[bn] = bq
            rest_local[bn] = loc; order.append(bn); built.add(bn)
        pending = still
    return order, rest_local, bind_global, min_y, pending

def sample(keys, t):
    if not keys: return None
    if len(keys) == 1 or t <= keys[0][2]: return keys[0][1]
    if t >= keys[-1][2]: return keys[-1][1]
    i = 0
    while i < len(keys)-2 and keys[i+1][2] <= t: i += 1
    ta, tb = keys[i][2], keys[i+1][2]
    w = 0.0 if tb <= ta else (t-ta)/(tb-ta)
    return qslerp(keys[i][1], keys[i+1][1], w)
