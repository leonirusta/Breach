"""Avatar de Breach en Blender con el rig corregido (ver retarget.py)."""
import bpy, sys, math, os
from mathutils import Quaternion as Q, Vector, Matrix

SP = r"C:\Users\USUARI~1\AppData\Local\Temp\claude\C--Users-usuario-1-Desktop-Breach\b8d07b0f-a8f3-42e1-9efa-61ea9bd44057\scratchpad"
sys.path.insert(0, SP)
from retarget import build, local_pose

M = build()
bones, parents, order = M["bones"], M["parents"], M["order"]
pal, clips, rest, nbind, GP = M["pal"], M["clips"], M["rest"], M["nbind"], M["GP"]
MESH_OFF = M["mesh_off"]
ROOT = M["ROOT"]


def BQ(q):
    return Q((q[3], q[0], q[1], q[2]))


bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.fps = 30
sc.render.engine = 'BLENDER_WORKBENCH'
sc.render.resolution_x = 700
sc.render.resolution_y = 900
sc.display.shading.light = 'STUDIO'
sc.display.shading.color_type = 'VERTEX'
sc.world = bpy.data.worlds.new("W")
sc.world.color = (0.08, 0.09, 0.11)

DIRS = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]


def bone_mesh(name, voxels):
    solid = {(int(v[0]), int(v[1]), int(v[2])): int(v[3]) for v in voxels}
    verts, faces, cols = [], [], []
    for c, idx in solid.items():
        p = pal[idx] if 0 <= idx < len(pal) else [200, 150, 120]
        col = tuple((x / 255.0) ** 2.2 for x in p[:3]) + (1.0,)
        for d in DIRS:
            if (c[0] + d[0], c[1] + d[1], c[2] + d[2]) in solid:
                continue
            n = Vector(d)
            base = Vector(c) + Vector((.5, .5, .5)) + n * 0.5
            u = Vector((0, 1, 0)) if abs(n.y) < .5 else Vector((1, 0, 0))
            w = n.cross(u)
            u = w.cross(n)
            b = len(verts)
            for sg in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                verts.append(base + (u * sg[0] + w * sg[1]) * 0.5)
            faces.append((b, b + 1, b + 2, b + 3))
            cols.append(col)
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    ca = me.color_attributes.new("Col", 'FLOAT_COLOR', 'CORNER')
    for fi, f in enumerate(me.polygons):
        for li in f.loop_indices:
            ca.data[li].color = cols[fi]
    me.shade_flat()
    return me


root = bpy.data.objects.new("AvatarRoot", None)
sc.collection.objects.link(root)
root.rotation_euler = (math.pi / 2, 0, 0)   # Godot Y-arriba -> Blender Z-arriba
root.scale = (0.05, 0.05, 0.05)

objs = {}
for bn in order:
    e = bpy.data.objects.new("B_" + bn, None)
    sc.collection.objects.link(e)
    e.empty_display_size = 1.2
    e.empty_display_type = 'PLAIN_AXES'
    e.rotation_mode = 'QUATERNION'
    pn = parents.get(bn)
    e.parent = objs[pn] if pn else root
    e.location = Vector(rest[bn])
    e.rotation_quaternion = BQ(nbind[bn])
    objs[bn] = e
    if bn not in bones:
        continue
    ob = bpy.data.objects.new("M_" + bn, bone_mesh(bn, bones[bn]["voxels"]))
    sc.collection.objects.link(ob)
    ob.parent = e
    # los voxels vienen relativos a la articulacion: se deshace la orientacion de reposo
    ob.matrix_parent_inverse = Matrix.Identity(4)
    # los voxels vienen referidos al origen antiguo del hueso: se recolocan sobre el pivote
    ob.matrix_basis = (BQ(GP[bn][0]).to_matrix().to_4x4().inverted()
                       @ Matrix.Translation(Vector(MESH_OFF[bn])))


def apply_pose(cname, t):
    P = local_pose(M, cname, t)
    for bn in order:
        q, loc = P[bn]
        objs[bn].rotation_quaternion = BQ(q)
        if loc is not None:
            objs[bn].location = Vector(loc)


def add_cam(name, loc, rot):
    cd = bpy.data.cameras.new(name)
    cd.lens = 45
    c = bpy.data.objects.new(name, cd)
    sc.collection.objects.link(c)
    c.location = loc
    c.rotation_euler = rot
    return c


cam_f = add_cam("CamFrente", (0.0, -4.4, 0.95), (math.pi / 2, 0, 0))
cam_s = add_cam("CamPerfil", (4.4, 0.0, 0.95), (math.pi / 2, 0, math.pi / 2))
cam_q = add_cam("CamTresCuartos", (3.1, -3.1, 1.9), (math.radians(72), 0, math.radians(45)))
sc.camera = cam_f
bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, 0))
bpy.context.object.name = "Suelo"

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
mode, outdir = argv[0], argv[1]
names = argv[2].split(",") if len(argv) > 2 else sorted(clips)

if mode == "shots":
    for cname in names:
        dur = max(k[-1][2] for k in clips[cname]["bones"].values())
        for label, cam in (("frente", cam_f), ("perfil", cam_s)):
            sc.camera = cam
            for frac in (0.0, 0.25, 0.5, 0.75):
                apply_pose(cname, dur * frac)
                sc.render.filepath = os.path.join(outdir, "%s_%s_%02d.png" % (cname, label, int(frac * 100)))
                bpy.ops.render.render(write_still=True)
    sc.camera = cam_f
else:
    for bn in order:
        objs[bn].animation_data_clear()
    f = 1
    for cname in names:
        dur = max(k[-1][2] for k in clips[cname]["bones"].values())
        nf = max(1, int(round(dur * 30)))
        sc.timeline_markers.new(cname, frame=f)
        for i in range(nf + 1):
            apply_pose(cname, i / 30.0)
            for bn in order:
                objs[bn].keyframe_insert("rotation_quaternion", frame=f + i)
            objs[ROOT].keyframe_insert("location", frame=f + i)
        f += nf + 6
    sc.frame_start = 1
    sc.frame_end = f
    sc.frame_current = 1
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type != 'VIEW_3D':
                continue
            for space in area.spaces:
                if space.type != 'VIEW_3D':
                    continue
                space.region_3d.view_perspective = 'CAMERA'
                space.shading.type = 'SOLID'
                space.shading.color_type = 'VERTEX'
                space.overlay.show_extras = False
                space.overlay.show_relationship_lines = False
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(outdir, "avatar_corregido.blend"))
print("LISTO")
