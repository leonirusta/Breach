"""Criaturas de MALLA ORGANICA para Breach (los monstruos no son de voxels: contrastan con el mundo).

Cada pieza (cuerpo, cabeza, mandibula, dientes...) se esculpe con formas simples que se funden con un
remallado de voxels finos (la piel sale continua, sin costuras), se le dan arrugas con ruido, se suaviza
y se reduce. El color se pinta por zonas: cada vertice toma el color de la forma mas cercana. Los pesos
del esqueleto son suaves en el cuerpo (los dos o tres huesos mas cercanos) y rigidos en boca, dientes y
colmillos, para que la mandibula se abra limpia sin estirar el labio de arriba.
"""
import bpy, bmesh, math
from mathutils import Vector, Matrix


def lin(c):
    return tuple((x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c)


def _ruido(p, escala=7.0):
    x, y, z = p.x * escala, p.y * escala, p.z * escala
    return 0.5 + 0.25 * math.sin(x * 1.7 + math.sin(y * 1.3)) * math.cos(z * 1.9 + math.sin(x * 0.7)) \
        + 0.25 * math.sin(x * 3.1 + y * 2.3 + z * 2.9)


def _alinear(a, b):
    d = b - a
    q = Vector((0, 0, 1)).rotation_difference(d.normalized())
    return q.to_matrix().to_4x4(), d.length


class Forma:
    def __init__(self, tipo, datos, color, brillo, prio=0):
        # prio > 0: la forma se queda con sus voxels aunque este metida dentro de otra (ojos, pupilas)
        self.tipo, self.d, self.color, self.brillo, self.prio = tipo, datos, color, brillo, prio

    def distancia(self, p):
        if self.tipo == "elip":
            c, r, inv = self.d
            q = inv @ (p - c)
            k = Vector((q.x / r.x, q.y / r.y, q.z / r.z)).length
            return (k - 1.0) * min(r)
        a, b, ra, rb = self.d
        ab = b - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
        return (p - (a + ab * t)).length - (ra + (rb - ra) * t)


class Pieza:
    """un trozo de malla: formas que se funden en una sola superficie"""

    def __init__(self, nombre):
        self.nombre, self.formas = nombre, []

    def elip(self, c, r, color, rot=(0, 0, 0), brillo=0.0, prio=0):
        R = Matrix.Rotation(math.radians(rot[2]), 3, 'Z') @ Matrix.Rotation(math.radians(rot[0]), 3, 'X') \
            @ Matrix.Rotation(math.radians(rot[1]), 3, 'Y')
        self.formas.append(Forma("elip", (Vector(c), Vector(r), R.inverted()), color, brillo, prio))
        self.formas[-1].R = R
        return self

    def cap(self, a, b, ra, rb, color, brillo=0.0, prio=0):
        self.formas.append(Forma("cap", (Vector(a), Vector(b), ra, rb), color, brillo, prio))
        return self

    def cono(self, base, punta, r, color, brillo=0.0, prio=0):
        return self.cap(base, punta, r, r * 0.08, color, brillo, prio)

    def espejo(self):
        """duplica en -X todo lo que esta en +X"""
        for f in list(self.formas):
            if f.tipo == "elip":
                c, r, inv = f.d
                if c.x > 0.01:
                    m = Matrix.Diagonal((-1, 1, 1))
                    R2 = m @ f.R @ m
                    g = Forma("elip", (Vector((-c.x, c.y, c.z)), r, R2.inverted()), f.color, f.brillo, f.prio)
                    g.R = R2
                    self.formas.append(g)
            else:
                a, b, ra, rb = f.d
                if a.x > 0.01 or b.x > 0.01:
                    self.formas.append(Forma("cap", (Vector((-a.x, a.y, a.z)), Vector((-b.x, b.y, b.z)), ra, rb),
                                             f.color, f.brillo, f.prio))
        return self

    def construir(self, coleccion, voxel=0.045, arrugas=0.025, suave=4, reduccion=0.5, ruido_color=0.22):
        bm = bmesh.new()
        for f in self.formas:
            if f.tipo == "elip":
                c, r, _ = f.d
                M = Matrix.Translation(c) @ f.R.to_4x4() @ Matrix.Diagonal((r.x, r.y, r.z, 1.0))
                bmesh.ops.create_icosphere(bm, subdivisions=3, radius=1.0, matrix=M)
            else:
                a, b, ra, rb = f.d
                R, L = _alinear(a, b)
                M = Matrix.Translation((a + b) * 0.5) @ R
                bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=16,
                                      radius1=ra, radius2=max(rb, 0.004), depth=L, matrix=M)
                bmesh.ops.create_icosphere(bm, subdivisions=2, radius=ra, matrix=Matrix.Translation(a))
                if rb > 0.02:
                    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=rb, matrix=Matrix.Translation(b))
        me = bpy.data.meshes.new(self.nombre + "_base")
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(self.nombre, me)
        coleccion.objects.link(ob)
        rm = ob.modifiers.new("remallado", 'REMESH')
        rm.mode, rm.voxel_size, rm.use_smooth_shade = 'VOXEL', voxel, True
        if arrugas > 0:
            tex = bpy.data.textures.get("piel") or bpy.data.textures.new("piel", 'CLOUDS')
            tex.noise_scale, tex.noise_depth = 0.12, 2
            dp = ob.modifiers.new("arrugas", 'DISPLACE')
            dp.texture, dp.strength, dp.mid_level = tex, arrugas, 0.5
        if suave:
            sm = ob.modifiers.new("suave", 'LAPLACIANSMOOTH')
            sm.iterations, sm.lambda_factor = suave, 0.4
        if reduccion < 1.0:
            dc = ob.modifiers.new("reducir", 'DECIMATE')
            dc.ratio = reduccion
        dg = bpy.context.evaluated_depsgraph_get()
        final = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
        ob.modifiers.clear()
        ob.data = final
        final.name = self.nombre
        bpy.data.meshes.remove(me)
        final.shade_smooth()
        # color por zonas: la forma mas cercana manda
        ca = final.color_attributes.new("Col", 'FLOAT_COLOR', 'POINT')
        br = final.attributes.new("Brillo", 'FLOAT', 'POINT')
        for v in final.vertices:
            p = v.co
            mejor = min(self.formas, key=lambda f: f.distancia(p))
            n = 1.0 - ruido_color * 0.5 + ruido_color * _ruido(p)
            ca.data[v.index].color = lin(tuple(min(1.0, c * n) for c in mejor.color)) + (1.0,)
            br.data[v.index].value = mejor.brillo
        final.color_attributes.active_color = ca
        final.materials.append(material())
        return ob


def material():
    mat = bpy.data.materials.get("Criatura")
    if mat:
        return mat
    mat = bpy.data.materials.new("Criatura")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    at = nt.nodes.new("ShaderNodeAttribute")
    at.attribute_name = "Brillo"
    fuerza = nt.nodes.new("ShaderNodeValue")
    fuerza.name = "Brillo_fuerza"
    fuerza.outputs[0].default_value = 1.0
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = 'MULTIPLY'
    nt.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(vc.outputs["Color"], bsdf.inputs["Emission Color"])
    nt.links.new(at.outputs["Fac"], mul.inputs[0])
    nt.links.new(fuerza.outputs[0], mul.inputs[1])
    nt.links.new(mul.outputs[0], bsdf.inputs["Emission Strength"])
    bsdf.inputs["Roughness"].default_value = 0.62
    bsdf.inputs["Specular IOR Level"].default_value = 0.35
    return mat


def armature(nombre, huesos, coleccion, control=()):
    """huesos: {nombre: (cabeza, cola, padre)}. Los de `control` no deforman (objetivos IK, polos)."""
    arm = bpy.data.armatures.new(nombre)
    arm.display_type = 'OCTAHEDRAL'
    ob = bpy.data.objects.new(nombre, arm)
    coleccion.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode='EDIT')
    eb = {}
    for n, (h, t, _p) in huesos.items():
        b = arm.edit_bones.new(n)
        b.head, b.tail = Vector(h), Vector(t)
        b.use_deform = n not in control
        eb[n] = b
    for n, (_h, _t, p) in huesos.items():
        if p:
            eb[n].parent = eb[p]
    bpy.ops.object.mode_set(mode='OBJECT')
    for pb in ob.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    return ob


def pesos_suaves(ob, rig, huesos, vecinos=3, radio=None):
    """cada vertice, a sus `vecinos` huesos mas cercanos (distancia al segmento), con caida 1/d^4"""
    bones = rig.data.bones
    segs = [(n, bones[n].head_local, bones[n].tail_local) for n in huesos]
    grupos = {n: ob.vertex_groups.new(name=n) for n in huesos}
    for v in ob.data.vertices:
        p = v.co
        ds = []
        for n, a, b in segs:
            ab = b - a
            t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
            ds.append(((p - (a + ab * t)).length, n))
        ds.sort()
        ws = [(1.0 / (d + 0.05) ** 4, n) for d, n in ds[:vecinos]]
        tot = sum(w for w, _ in ws)
        for w, n in ws:
            if w / tot > 0.04:
                grupos[n].add([v.index], w / tot, 'REPLACE')
    _enganchar(ob, rig)


def peso_rigido(ob, rig, hueso):
    ob.vertex_groups.new(name=hueso).add(list(range(len(ob.data.vertices))), 1.0, 'REPLACE')
    _enganchar(ob, rig)


def _enganchar(ob, rig):
    ob.parent = rig
    if not any(m.type == 'ARMATURE' for m in ob.modifiers):
        ob.modifiers.new("Armature", 'ARMATURE').object = rig


def calibrar_polos(rig, cadenas, preparar, deshacer):
    """El angulo del polo que deja la rodilla (o el codo) apuntando AL POLO. Se prueba cada 5 grados y se mide
    la pose de verdad. ANTES se leia la copia evaluada del depsgraph, que en Blender sin ventana no cambiaba
    al tocar el angulo: todos los intentos daban lo mismo, se quedaba el primero (0) y las rodillas salian
    HACIA LOS LADOS al andar (medido: 80 grados de lado en todos los bichos, 2026-09-26)."""
    vl = bpy.context.view_layer
    sc = bpy.context.scene
    preparar()
    for ik, upper, lower, polo in cadenas:
        mejor, mejor_a = -9.0, 0.0
        for k in range(72):
            ik.pole_angle = math.radians(k * 5)
            rig.update_tag()
            sc.frame_set(1 + (k % 2))       # cambiar de fotograma es lo unico que obliga a re-evaluar sin ventana
            vl.update()
            M = rig.matrix_world
            pb = rig.pose.bones
            s, t, m, p = M @ pb[upper].head, M @ pb[lower].tail, M @ pb[lower].head, M @ pb[polo].head
            eje = (t - s).normalized()
            dm = m - (s + eje * (m - s).dot(eje))
            dp = p - (s + eje * (p - s).dot(eje))
            if dm.length < 1e-4:
                continue
            c = dm.normalized().dot(dp.normalized())
            if c > mejor:
                mejor, mejor_a = c, ik.pole_angle
        ik.pole_angle = mejor_a
        print("[polos] %s: %.0f grados (coincide %.2f)" % (lower, math.degrees(mejor_a), mejor))
    deshacer()
    vl.update()


def interp(keys, f):
    """poses clave -> valor en el frame f (Hermite con tangentes Catmull-Rom, frames no uniformes)"""
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


def rot(pitch=0.0, roll=0.0, yaw=0.0):
    """grados en ejes del cuerpo: pitch+ = hacia delante/abajo, roll+ = hacia +X, yaw+ = hacia +X"""
    return (Matrix.Rotation(math.radians(yaw), 4, 'Z') @ Matrix.Rotation(math.radians(pitch), 4, 'X')
            @ Matrix.Rotation(math.radians(roll), 4, 'Y'))
