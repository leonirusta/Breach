"""Exporta la recarga de breach_recarga.blend a godot/avatar/recarga_fusil.json.

blender -b <breach_recarga.blend> --python tools/blender/exportar_recarga.py -- <salida.json>

Lo que lee avatar_animator.gd, frame a frame (30 fps):
  arma_pos  origen del arma respecto al CUELLO, metros, ejes del esqueleto de Godot
  arma_rot  giro del arma (x, y, z, w) en ejes del esqueleto
  mano_izq  muneca de la mano de apoyo en el espacio local del arma (metros)
  mag       cargador en el espacio local del arma [px,py,pz,qx,qy,qz,qw], null si no hay ninguno
ESPEJADO: en Blender el fusil va a la derecha anatomica (-X); en el juego la mano del gatillo es
hand_r, en -X del esqueleto, que pasado a Blender es +X. Por eso se refleja en X, y con el reflejo
Blender -> Godot queda en un simple cambio de Y por Z.
"""
import bpy, json, sys
from mathutils import Matrix

out_path = sys.argv[sys.argv.index("--") + 1]
sc = bpy.context.scene
rig = bpy.data.objects["Soldado_Rig"]
P = Matrix(((1, 0, 0), (0, 0, 1), (0, 1, 0)))
SUELTA, COGE = 18, 24


def vec(b):
    return [round(b.x, 5), round(b.z, 5), round(b.y, 5)]


def quat(r):
    q = (P @ r @ P).to_quaternion()
    return [round(q.x, 5), round(q.y, 5), round(q.z, 5), round(q.w, 5)]


data = {"fps": 30, "frames": sc.frame_end, "suelta": SUELTA, "coge": COGE,
        "arma_pos": [], "arma_rot": [], "mano_izq": [], "mag": []}
dg = bpy.context.evaluated_depsgraph_get()
for f in range(1, sc.frame_end + 1):
    sc.frame_set(f)
    ev = rig.evaluated_get(dg).pose.bones
    w = ev["CTRL_arma"].matrix.copy()
    wi = w.inverted()
    data["arma_pos"].append(vec(w.translation - ev["neck"].head))
    data["arma_rot"].append(quat(w.to_3x3()))
    data["mano_izq"].append(vec(wi @ ev["hand_r"].head))
    nombre = "Cargador_viejo" if f <= SUELTA else ("Cargador_nuevo" if f >= COGE else None)
    if nombre:
        m = wi @ bpy.data.objects[nombre].evaluated_get(dg).matrix_world
        data["mag"].append(vec(m.translation) + quat(m.to_3x3()))
    else:
        data["mag"].append(None)
with open(out_path, "w") as fh:
    json.dump(data, fh, separators=(",", ":"))
print("EXPORTADO", out_path, data["frames"], "frames")
