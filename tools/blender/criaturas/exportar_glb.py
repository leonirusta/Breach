"""Exporta una criatura de Blender (malla de voxels por hueso + esqueleto + clips) a .glb para Godot.

blender -b <criatura.blend> --python tools/blender/criaturas/exportar_glb.py -- <salida.glb>

Los clips estan seguidos en una sola accion con sus rangos en la propiedad "clips" de la escena. Para
Godot cada uno tiene que ser una animacion aparte: se hace una pista NLA por clip, recortada a su
rango, y el exportador saca cada pista como animacion con su nombre (reposo, caminar, ataque...). Las
IK se hornean muestreando cada frame, salvo las de las PIERNAS, que se hornean antes a mano (ver
hornear_rodillas). Fuera se quedan la referencia del soldado, camaras y luces.
"""
import bpy, json, math, sys
from mathutils import Matrix

args = sys.argv[sys.argv.index("--") + 1:]
out = args[0]
# --blend <ruta>: ademas del .glb, guarda el .blend YA HORNEADO (rodillas resueltas a mano, sin IK).
# Es el que hay que abrir para MIRAR las animaciones: en el .blend de origen el IK de Blender dobla las
# rodillas hacia dentro y parece que el bicho anda roto, cuando en el juego sale bien.
BLEND = args[args.index("--blend") + 1] if "--blend" in args else ""
sc = bpy.context.scene
clips = json.loads(sc["clips"])
for o in list(bpy.data.objects):
    if o.name.startswith("Soldado") or o.type in ('CAMERA', 'LIGHT'):
        bpy.data.objects.remove(o, do_unlink=True)
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
ad = rig.animation_data
accion = ad.action


def _marco(y, h):
    y = y.normalized()
    h = (h - y * h.dot(y)).normalized()
    return Matrix((y, h, y.cross(h))).transposed()


def hornear_rodillas():
    """LAS RODILLAS HACIA DONDE DICE SU POLO. El IK de Blender no le hacia caso al polo en estas piernas:
    medido en goliat, gordo y acorazado, ningun pole_angle de los 72 dejaba la rodilla al frente, y todas
    las criaturas andaban con las rodillas metidas hacia dentro 56-72 grados (en Godot, "se les doblan las
    rodillas para un lado"). Aqui se resuelve cada pierna a mano, frame a frame: cadera y tobillo donde los
    deja el clip, rodilla en el plano cadera-tobillo-polo y del lado del polo, con los largos de muslo y
    tibia. Se escriben como claves de muslo y tibia (girados desde su reposo, sin retorcerlos sobre su eje)
    y se apaga ese IK."""
    PB, BN = rig.pose.bones, rig.data.bones
    piernas = []
    for pb in PB:
        ik = next((c for c in pb.constraints if c.type == 'IK' and not c.mute and c.subtarget and c.pole_subtarget), None)
        if ik and ik.chain_count == 2 and pb.parent and pb.name.lower().startswith(("shin", "tibia", "calf")):
            piernas.append((pb.parent.name, pb.name, ik))
    if not piernas:
        return
    bisagra_reposo = {}
    for up, lo, ik in piernas:
        cad = BN[up].head_local
        eje = (BN[lo].tail_local - cad).normalized()
        polo = BN[ik.pole_subtarget].head_local - cad
        bisagra_reposo[lo] = eje.cross(polo - eje * polo.dot(eje)).normalized()
    mallas = [o for o in bpy.data.objects if o.type == 'MESH' and not o.hide_viewport]
    for o in mallas:
        o.hide_viewport = True                    # solo hace falta el esqueleto: mucho mas rapido
    f0 = min(int(a) for a, _ in clips.values())
    f1 = max(int(b) for _, b in clips.values())
    dg = bpy.context.evaluated_depsgraph_get()
    claves = []
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        ev = rig.evaluated_get(dg).pose.bones
        for up, lo, ik in piernas:
            l1 = (BN[lo].head_local - BN[up].head_local).length
            l2 = BN[lo].length
            cad = ev[up].head.copy()
            eje = ev[ik.subtarget].head - cad
            d = max(1e-4, min(eje.length, l1 + l2 - 1e-4))
            eje.normalize()
            polo = ev[ik.pole_subtarget].head - cad
            perp = polo - eje * polo.dot(eje)
            if perp.length < 1e-6:
                continue
            perp.normalize()
            c = max(-1.0, min(1.0, (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)))
            rod = cad + eje * (l1 * c) + perp * (l1 * math.sqrt(max(0.0, 1 - c * c)))
            tob = cad + eje * d
            h = eje.cross(perp).normalized()
            mats = {}
            for n, cab, cola in ((up, cad, rod), (lo, rod, tob)):
                rest = BN[n].matrix_local
                giro = _marco(cola - cab, h) @ _marco(rest.col[1].xyz, bisagra_reposo[lo]).inverted()
                m = (giro @ rest.to_3x3()).to_4x4()
                m.translation = cab
                mats[n] = m
            par = BN[up].parent
            base_up = (ev[par.name].matrix @ par.matrix_local.inverted() @ BN[up].matrix_local) if par else BN[up].matrix_local
            base_lo = mats[up] @ BN[up].matrix_local.inverted() @ BN[lo].matrix_local
            claves.append((f, up, base_up.inverted() @ mats[up]))
            claves.append((f, lo, base_lo.inverted() @ mats[lo]))
    for _up, _lo, ik in piernas:
        ik.mute = True
    ult = {}
    for f, n, m in claves:
        loc, q, _ = m.decompose()
        if n in ult and ult[n].dot(q) < 0:
            q.negate()
        ult[n] = q
        PB[n].location, PB[n].rotation_quaternion = loc, q
        PB[n].keyframe_insert("location", frame=f)
        PB[n].keyframe_insert("rotation_quaternion", frame=f)
    # comprobacion: hacia donde dobla ahora la rodilla al andar (0 = al frente, -Y) y si el pie llega
    a, b = clips.get("caminar", next(iter(clips.values())))
    for up, lo, ik in piernas:
        fw = la = err = 0.0
        for f in range(int(a), int(b) + 1):
            sc.frame_set(f)
            ev = rig.evaluated_get(dg).pose.bones
            s, m, t = ev[up].head, ev[lo].head, ev[lo].tail
            e = (t - s).normalized()
            off = m - (s + e * (m - s).dot(e))
            fw -= off.y
            la += off.x
            err = max(err, (t - ev[ik.subtarget].head).length)
        print("RODILLA %s angulo al andar %+.0f grados, tobillo a %.3f m del objetivo" % (
            lo, math.degrees(math.atan2(la, fw)), err))
    for o in mallas:
        o.hide_viewport = False


hornear_rodillas()
if BLEND:
    bpy.ops.wm.save_as_mainfile(filepath=BLEND, copy=True)
    print("BLEND PARA MIRAR", BLEND)
for t in list(ad.nla_tracks):
    ad.nla_tracks.remove(t)
for nombre, (a, b) in clips.items():
    tr = ad.nla_tracks.new()
    tr.name = nombre
    # TODAS LAS TIRAS EMPIEZAN EN EL FRAME 1: el exportador saca cada pista desde el principio de la
    # escena, y con la tira en su sitio de la linea de tiempo el caminar duraba 8,7 s en vez de 2
    st = tr.strips.new(nombre, 1, accion)
    st.action_frame_start, st.action_frame_end = float(a), float(b)
    st.frame_start, st.frame_end = 1.0, 1.0 + float(b - a)
ad.action = None
for o in bpy.context.view_layer.objects:
    o.select_set(False)
rig.select_set(True)
for o in bpy.data.objects:
    if o.parent == rig:
        o.select_set(True)
bpy.context.view_layer.objects.active = rig
kw = dict(filepath=out, export_format='GLB', use_selection=True, export_animations=True,
          export_animation_mode='NLA_TRACKS', export_force_sampling=True, export_def_bones=True,
          export_optimize_animation_size=True, export_materials='EXPORT')
try:
    bpy.ops.export_scene.gltf(export_vertex_color='ACTIVE', **kw)
except TypeError:
    bpy.ops.export_scene.gltf(**kw)
print("EXPORTADO", out, "clips", list(clips))
