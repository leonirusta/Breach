"""Monta sobre soldado_breach.blend el fusil, el portacargador y los controles IK para animar.

Lados: los huesos *_l del modelo estan en el lado DERECHO anatomico (el soldado mira a -Y y su
derecha es -X). Los controles se nombran por el lado real: IK_mano_der mueve arm_*_l / hand_l.
"""
import bpy, bmesh, math, os, sys
from mathutils import Vector, Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import arma_fusil as AF

LADOS = {"der": "l", "izq": "r"}
FUNDA_MAG = Matrix.Translation((0.10, -0.165, 1.065))     # cargador nuevo metido en el portacargador


def _lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _material(nombre):
    mat = bpy.data.materials.get(nombre) or bpy.data.materials.new(nombre)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    nt.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.55
    bsdf.inputs["Metallic"].default_value = 0.35
    return mat


def malla(nombre, piezas, xf=Matrix.Identity(4)):
    me = bpy.data.meshes.new(nombre)
    me.from_pydata([tuple(xf @ v) for v in piezas.v], [], piezas.f)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ca = me.color_attributes.new("Col", 'FLOAT_COLOR', 'CORNER')
    for fi, f in enumerate(me.polygons):
        col = piezas.c[fi]
        for li in f.loop_indices:
            ca.data[li].color = (_lin(col[0]), _lin(col[1]), _lin(col[2]), 1.0)
    me.color_attributes.active_color = ca
    me.shade_flat()
    me.materials.append(_material("Arma"))
    ob = bpy.data.objects.new(nombre, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def piel(ob, rig, hueso):
    ob.vertex_groups.new(name=hueso).add(list(range(len(ob.data.vertices))), 1.0, 'REPLACE')
    ob.parent = rig
    ob.modifiers.new("Armature", 'ARMATURE').object = rig


def _pole_angle(base, tip, pole):
    """Angulo de polo para que el codo/rodilla apunte a `pole` (reposo, espacio del armature)."""
    normal = (tip.tail_local - base.head_local).cross(pole - base.head_local)
    proj = normal.cross(base.tail_local - base.head_local)
    a = base.x_axis.angle(proj)
    if base.x_axis.cross(proj).angle(base.tail_local - base.head_local) < 1:
        a = -a
    return a


def _calibrar_polos(rig, cadenas):
    """El angulo de polo depende del alabeo de cada hueso y la formula lo daba girado: las rodillas
    se abrian hacia fuera y las piernas quedaban en arco. Se prueba cada 5 grados con la cadena
    doblada y se queda el que deja la articulacion del lado de su polo."""
    pb, vl = rig.pose.bones, bpy.context.view_layer
    pb["pelvis"].location = (0, -0.10, 0)                 # rodillas dobladas para poder medir
    pb["CTRL_arma"].location = (0.0, -0.35, 1.10)         # manos delante: codos doblados
    dg = bpy.context.evaluated_depsgraph_get()
    for ik, upper, lower, polo in cadenas:
        mejor, mejor_a = -9.0, 0.0
        for k in range(72):
            ik.pole_angle = math.radians(k * 5)
            vl.update()
            ev = rig.evaluated_get(dg).pose.bones
            s, t, m, p = ev[upper].head, ev[lower].tail, ev[lower].head, ev[polo].head
            eje = (t - s).normalized()
            dm = m - (s + eje * (m - s).dot(eje))
            dp = p - (s + eje * (p - s).dot(eje))
            if dm.length < 1e-4:
                continue
            puntos = dm.normalized().dot(dp.normalized())
            if puntos > mejor:
                mejor, mejor_a = puntos, ik.pole_angle
        ik.pole_angle = mejor_a
        print("POLO", lower, round(math.degrees(mejor_a)), "coincidencia %.3f" % mejor)
    pb["pelvis"].location = (0, 0, 0)
    pb["CTRL_arma"].location = (0, 0, 0)
    vl.update()


def montar():
    sc = bpy.context.scene
    rig = bpy.data.objects["Soldado_Rig"]
    arm = rig.data
    arm.display_type = 'OCTAHEDRAL'
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm.edit_bones

    def nuevo(n, head, tail, padre=None, deform=False, roll=0.0):
        b = eb.new(n)
        b.head, b.tail, b.roll = Vector(head), Vector(tail), roll
        b.parent = eb[padre] if padre else None
        b.use_deform = deform
        return b

    for s in "lr":
        eb["hand_" + s].align_roll(Vector((0, 0, 1)))
    nuevo("CTRL_arma", (0, 0, 0), (0, 0.25, 0))
    nuevo("arma", (0, 0, 0), (0, 0.25, 0), "CTRL_arma", True)
    nuevo("arma_manija", AF.MANIJA, AF.MANIJA + Vector((0, 0.05, 0)), "arma", True)
    for lado, s in LADOS.items():
        sx = -1 if lado == "der" else 1
        nuevo("IK_mano_" + lado, (0, 0, 0), (0, 0.1, 0), "CTRL_arma")
        hom = eb["arm_upper_" + s].head
        polo = hom + (Vector((-0.25, 0.35, -0.35)) if lado == "der" else Vector((0.30, 0.10, -0.40)))
        nuevo("POLE_codo_" + lado, polo, polo + Vector((0, 0, 0.05)), "chest")
        pie = eb["foot_" + s]
        nuevo("IK_pie_" + lado, pie.head, pie.tail, None, False, pie.roll)
        rod = eb["leg_lower_" + s].head + Vector((0.03 * sx, -0.5, 0))
        nuevo("POLE_rodilla_" + lado, rod, rod + Vector((0, 0, 0.05)), "IK_pie_" + lado)
    bpy.ops.object.mode_set(mode='OBJECT')

    cadenas = []
    for lado, s in LADOS.items():
        pb = rig.pose.bones
        for cad, obj, polo, mano in (("arm", "IK_mano_", "POLE_codo_", "hand_"),
                                      ("leg", "IK_pie_", "POLE_rodilla_", "foot_")):
            ik = pb[cad + "_lower_" + s].constraints.new('IK')
            ik.target, ik.subtarget = rig, obj + lado
            ik.pole_target, ik.pole_subtarget = rig, polo + lado
            ik.chain_count = 2
            cr = pb[mano + s].constraints.new('COPY_ROTATION')
            cr.target, cr.subtarget = rig, obj + lado
            cadenas.append((ik, cad + "_upper_" + s, cad + "_lower_" + s, polo + lado))
    for pb in rig.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    _calibrar_polos(rig, cadenas)

    # arma, manija y portacargador pegados a sus huesos; los cargadores son objetos sueltos (se hornean)
    piezas = AF.construir()
    fusil = malla("Fusil", piezas["cuerpo"])
    piel(fusil, rig, "arma")
    manija = malla("Manija", piezas["manija"], Matrix.Translation(AF.MANIJA))
    piel(manija, rig, "arma_manija")
    mags = {}
    for n in ("Cargador_viejo", "Cargador_nuevo"):
        mags[n] = malla(n, piezas["cargador"])
        mags[n].rotation_mode = 'QUATERNION'
    funda = AF.Piezas()
    funda.box((0.052, 0.17, 0.085), (-0.10, 0.935, -0.165), (0.20, 0.21, 0.15))
    funda.box((0.056, 0.012, 0.089), (-0.10, 0.985, -0.165), (0.13, 0.14, 0.10))
    ob = malla("Portacargador", funda)
    piel(ob, rig, "stomach")
    return rig, mags
