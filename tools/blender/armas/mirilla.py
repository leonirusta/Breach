"""LO QUE VE EL QUE APUNTA. Pone la camara donde el juego pone el ojo al encarar -en el eje de la
mira, a 38 cm- y mira hacia la boca. Una imagen por arma, todas juntas en una hoja.

    blender -b --python tools/blender/armas/mirilla.py -- [salida.png]

Es LA comprobacion de que una mira sirve: si algo la tapa (una campana maciza, el cuerpo de la
holografica, un tapon en el diopter), aqui se ve en el acto, que mirando el arma de perfil no.
"""
import bpy
import os
import sys
import json
import math
from mathutils import Vector

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
ARMAS = os.path.join(RAIZ, "godot", "armas")
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
salida = argv[0] if argv else os.path.join(RAIZ, "docs", "armas_mirilla.png")
TAM = (520, 380)
DIST = 0.38          # lo mismo que usa player.gd al encarar
FOV = 42.0           # grados: el campo de vision tipico apuntando

ficha = json.load(open(os.path.join(ARMAS, "armas.json"), encoding="utf-8"))
ids = [i for i in ficha.keys()]


def escena():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    sol = bpy.data.objects.new("sol", bpy.data.lights.new("sol", 'SUN'))
    sol.data.energy = 2.4
    sol.rotation_euler = (math.radians(54), 0.0, math.radians(-58))
    bpy.context.collection.objects.link(sol)
    rel = bpy.data.objects.new("rel", bpy.data.lights.new("rel", 'SUN'))
    rel.data.energy = 1.0
    rel.data.color = (0.6, 0.72, 1.0)
    rel.rotation_euler = (math.radians(112), 0.0, math.radians(100))
    bpy.context.collection.objects.link(rel)
    # UNA PARED DE FONDO CON DAMERO: si la mira esta despejada se ve el damero por ella; si esta
    # tapada, se ve el tapon. Sin fondo, "no ver nada" y "ver el cielo" se parecen demasiado.
    bpy.ops.mesh.primitive_plane_add(size=14.0, location=(0, 7.0, 0), rotation=(math.radians(90), 0, 0))
    pared = bpy.context.active_object
    m = bpy.data.materials.new("damero")
    m.use_nodes = True
    nt = m.node_tree
    chk = nt.nodes.new("ShaderNodeTexChecker")
    chk.inputs["Scale"].default_value = 26.0
    chk.inputs["Color1"].default_value = (0.62, 0.30, 0.16, 1)
    chk.inputs["Color2"].default_value = (0.80, 0.78, 0.72, 1)
    nt.links.new(chk.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    pared.data.materials.append(m)


def sight_blender(d):
    g = d["sight"]                      # (x, y, z) en Godot
    return Vector((g[0], -g[2], g[1]))  # -> Blender


sc = bpy.context.scene
for motor in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE', 'CYCLES'):
    try:
        sc.render.engine = motor
        break
    except Exception:
        continue
sc.render.resolution_x, sc.render.resolution_y = TAM
sc.render.image_settings.file_format = 'PNG'
mundo = bpy.data.worlds.new("w")
mundo.use_nodes = True
mundo.node_tree.nodes["Background"].inputs[0].default_value = (0.22, 0.24, 0.27, 1.0)
mundo.node_tree.nodes["Background"].inputs[1].default_value = 1.4
sc.world = mundo

tmp = os.path.join(os.path.dirname(salida), "_mirilla_tmp")
os.makedirs(tmp, exist_ok=True)
hechas = []
for wid in ids:
    escena()
    bpy.ops.import_scene.gltf(filepath=os.path.join(ARMAS, wid + ".glb"))
    ojo = sight_blender(ficha[wid]) + Vector((0.0, -DIST, 0.0))
    cd = bpy.data.cameras.new("cam")
    cd.sensor_fit = 'HORIZONTAL'
    cd.angle = math.radians(FOV)
    cam = bpy.data.objects.new("cam", cd)
    bpy.context.collection.objects.link(cam)
    cam.location = ojo
    cam.rotation_mode = 'QUATERNION'
    cam.rotation_quaternion = Vector((0.0, 1.0, 0.0)).to_track_quat('-Z', 'Y')
    sc.camera = cam
    ruta = os.path.join(tmp, wid + ".png")
    sc.render.filepath = ruta
    bpy.ops.render.render(write_still=True)
    hechas.append((wid, ruta))
    print("[mirilla] %s" % wid)

# --- montaje de la hoja: se copian los pixeles de cada tira en una imagen grande ---
cols = 3
filas = (len(hechas) + cols - 1) // cols
W, H = TAM[0] * cols, TAM[1] * filas
hoja = bpy.data.images.new("hoja", W, H, alpha=False)
buf = [0.05, 0.05, 0.06, 1.0] * (W * H)
for k, (wid, ruta) in enumerate(hechas):
    im = bpy.data.images.load(ruta)
    px = list(im.pixels)
    cx = (k % cols) * TAM[0]
    cy = (filas - 1 - k // cols) * TAM[1]     # las imagenes van de abajo a arriba
    for y in range(TAM[1]):
        o_dst = ((cy + y) * W + cx) * 4
        o_src = (y * TAM[0]) * 4
        buf[o_dst:o_dst + TAM[0] * 4] = px[o_src:o_src + TAM[0] * 4]
    bpy.data.images.remove(im)
hoja.pixels = buf
hoja.filepath_raw = salida
hoja.file_format = 'PNG'
hoja.save()
print("[mirilla] %s (%d armas)" % (salida, len(hechas)))
