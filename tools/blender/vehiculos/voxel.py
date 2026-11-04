"""VOXELES DE 10 CM PARA BLENDER: formas -> rejilla -> malla de caras visibles.

Los vehiculos de Breach se modelan con VOXELES (10 cm) para que peguen con el mapa, que es de voxels. Aqui
esta lo comun: una rejilla donde se apuntan cajas, elipsoides, cilindros y cunas con un color, y el mallado,
que saca SOLO las caras que se ven y junta las seguidas del mismo color en una sola cara larga (con 10 cm un
coche son ~13.000 voxels; a seis caras por voxel serian 72.000 triangulos y salen menos de 3.000).

Ejes de Blender: +Y es el MORRO del vehiculo, +Z arriba, X a los lados. El exportador de glTF gira el mundo,
asi que un punto (x, y, z) de Blender es (x, z, -y) en Godot, que mira a -Z. Igual que en las armas.

Colores: cada voxel guarda un numero de color. El color 1 es la CARROCERIA, que el juego pinta del color que
quiera en cada coche (por eso va en su propio material); los demas son detalles con su color fijo.
"""
import bmesh
import bpy
import numpy as np

VS = 0.10                      # metros por voxel (eran 13 cm: a 10 cm caben los detalles)
CARROCERIA = 1                 # el color que el juego repinta
CRISTAL = 5                    # va a su propio material, TRANSPARENTE (por dentro se ve el interior)


class Rejilla:
    """Volumen de voxels con un color por voxel (0 = vacio). Las coordenadas son METROS."""

    def __init__(self, x0, y0, z0, x1, y1, z1):
        self.org = np.array([x0, y0, z0], np.float64)
        n = np.ceil((np.array([x1, y1, z1], np.float64) - self.org) / VS).astype(int) + 1
        self.dim = n
        self.v = np.zeros(tuple(n), np.uint8)
        c = [self.org[i] + (np.arange(n[i]) + 0.5) * VS for i in range(3)]
        self.X, self.Y, self.Z = np.meshgrid(c[0], c[1], c[2], indexing="ij")

    # --- formas (todas en metros; `c` es el numero de color) ------------------------------------------
    def caja(self, x0, y0, z0, x1, y1, z1, c):
        m = ((self.X >= min(x0, x1) - 1e-9) & (self.X <= max(x0, x1) + 1e-9) &
             (self.Y >= min(y0, y1) - 1e-9) & (self.Y <= max(y0, y1) + 1e-9) &
             (self.Z >= min(z0, z1) - 1e-9) & (self.Z <= max(z0, z1) + 1e-9))
        self.v[m] = c
        return m

    def elipsoide(self, cx, cy, cz, rx, ry, rz, c):
        m = ((self.X - cx) / rx) ** 2 + ((self.Y - cy) / ry) ** 2 + ((self.Z - cz) / rz) ** 2 <= 1.0
        self.v[m] = c
        return m

    def cilindro(self, cx, cy, cz, r, largo, c, eje="y"):
        """Cilindro con el centro de una base en (cx, cy, cz) y `largo` a lo largo de `eje`."""
        if eje == "y":
            m = ((self.X - cx) ** 2 + (self.Z - cz) ** 2 <= r * r) & (self.Y >= cy) & (self.Y <= cy + largo)
        elif eje == "x":
            m = ((self.Y - cy) ** 2 + (self.Z - cz) ** 2 <= r * r) & (self.X >= cx) & (self.X <= cx + largo)
        else:
            m = ((self.X - cx) ** 2 + (self.Y - cy) ** 2 <= r * r) & (self.Z >= cz) & (self.Z <= cz + largo)
        self.v[m] = c
        return m

    def cuna(self, x0, y0, z0, x1, y1, z1, c, sube="+y"):
        """Rampa: dentro de la caja, la altura crece de z0 a z1 hacia `sube` (+y, -y, +x, -x)."""
        caja = ((self.X >= x0) & (self.X <= x1) & (self.Y >= y0) & (self.Y <= y1))
        if sube == "+y":
            k = (self.Y - y0) / max(y1 - y0, 1e-9)
        elif sube == "-y":
            k = (y1 - self.Y) / max(y1 - y0, 1e-9)
        elif sube == "+x":
            k = (self.X - x0) / max(x1 - x0, 1e-9)
        else:
            k = (x1 - self.X) / max(x1 - x0, 1e-9)
        m = caja & (self.Z >= z0) & (self.Z <= z0 + (z1 - z0) * k)
        self.v[m] = c
        return m

    def vaciar(self, mask):
        self.v[mask] = 0

    def espejo_x(self):
        """Copia lo que hay en x > 0 al otro lado (los vehiculos son simetricos)."""
        n = self.dim[0]
        izq = self.X[:, 0, 0] < 0.0
        der = ~izq
        # indice espejo: el voxel mas cercano a -x
        for i in np.nonzero(der)[0]:
            xm = -self.X[i, 0, 0]
            j = int(np.argmin(np.abs(self.X[:, 0, 0] - xm)))
            if 0 <= j < n:
                self.v[j] = np.where(self.v[i] != 0, self.v[i], self.v[j])


def mallar(rej, colores, nombre, mat_carroceria, mat_detalle, mat_cristal=None):
    """Rejilla -> objeto de Blender. Caras visibles, juntando tiradas del mismo color en cada fila.

    `colores`: numero -> (r, g, b) en 0..1. La carroceria va al material `mat_carroceria` con el color de
    vertice en blanco (para que el juego la pinte); el resto al de detalle con su color."""
    v = rej.v
    vertices = []
    caras = []
    col_caras = []
    mat_caras = []
    lleno = np.pad(v, 1)
    for eje in range(3):
        for s in (-1, 1):
            vecino = np.roll(lleno, -s, axis=eje)[1:-1, 1:-1, 1:-1]
            cara = np.where((v > 0) & (vecino == 0), v, 0)
            u = (eje + 1) % 3
            w = (eje + 2) % 3
            arr = np.transpose(cara, (eje, w, u))
            A, B, U = arr.shape
            for a in range(A):
                if not arr[a].any():
                    continue
                for b in range(B):
                    fila = arr[a, b]
                    if not fila.any():
                        continue
                    cortes = np.flatnonzero(np.diff(np.concatenate(([0], fila, [0]))) != 0)
                    for i0, i1 in zip(cortes[:-1], cortes[1:]):
                        c = int(fila[i0])
                        if c == 0:
                            continue
                        p_e = (a + (1 if s > 0 else 0)) * VS + rej.org[eje]
                        base = len(vertices)
                        for (uu, ww) in ((i0, b), (i1, b), (i1, b + 1), (i0, b + 1)):
                            q = [0.0, 0.0, 0.0]
                            q[eje] = p_e
                            q[u] = uu * VS + rej.org[u]
                            q[w] = ww * VS + rej.org[w]
                            vertices.append(tuple(q))
                        caras.append((base, base + 1, base + 2, base + 3) if s > 0 else (base + 3, base + 2, base + 1, base))
                        col_caras.append((1.0, 1.0, 1.0) if c == CARROCERIA else colores.get(c, (0.8, 0.1, 0.8)))
                        # material 0 carroceria, 1 detalle, 2 cristal (si lo hay)
                        if c == CARROCERIA:
                            mat_caras.append(0)
                        elif c == CRISTAL and mat_cristal is not None:
                            mat_caras.append(2)
                        else:
                            mat_caras.append(1)
    me = bpy.data.meshes.new(nombre)
    me.from_pydata(vertices, [], caras)
    me.validate()
    me.materials.append(mat_carroceria)
    me.materials.append(mat_detalle)
    if mat_cristal is not None:
        me.materials.append(mat_cristal)
    for i, p in enumerate(me.polygons):
        p.material_index = mat_caras[i]
    capa = me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
    datos = []
    for i, p in enumerate(me.polygons):
        c = col_caras[i]
        for _lp in p.loop_indices:
            datos.extend([c[0], c[1], c[2], 1.0])
    capa.data.foreach_set("color", datos)
    ob = bpy.data.objects.new(nombre, me)
    bpy.context.collection.objects.link(ob)
    return ob


def materiales():
    """Tres materiales: la carroceria (la repinta el juego), el detalle (color de vertice) y el CRISTAL,
    que va aparte porque tiene que ser TRANSPARENTE: con el cristal opaco no se ve a nadie dentro del
    coche y el vehiculo parece macizo."""
    def nuevo(nombre, usa_color_vertice):
        m = bpy.data.materials.get(nombre) or bpy.data.materials.new(nombre)
        m.use_nodes = True
        nt = m.node_tree
        bsdf = nt.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (0.8, 0.8, 0.8, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.45
        bsdf.inputs["Metallic"].default_value = 0.25
        if usa_color_vertice:
            attr = nt.nodes.new("ShaderNodeVertexColor")
            attr.layer_name = "Col"
            nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
        return m

    cristal = bpy.data.materials.get("cristal") or bpy.data.materials.new("cristal")
    cristal.use_nodes = True
    _b = cristal.node_tree.nodes.get("Principled BSDF")
    _b.inputs["Base Color"].default_value = (0.32, 0.55, 0.62, 1.0)
    _b.inputs["Roughness"].default_value = 0.08
    _b.inputs["Metallic"].default_value = 0.0
    _b.inputs["Alpha"].default_value = 0.34
    cristal.blend_method = "BLEND" if hasattr(cristal, "blend_method") else None
    return nuevo("carroceria", False), nuevo("detalle", True), cristal


def limpiar():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for bloque in (bpy.data.meshes, bpy.data.materials, bpy.data.objects):
        for x in list(bloque):
            if x.users == 0:
                bloque.remove(x)


def tris(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)
