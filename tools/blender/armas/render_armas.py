"""Hoja de contacto de las armas: importa los .glb ya exportados y los retrata en una sola imagen.

    blender -b --python tools/blender/armas/render_armas.py -- [salida.png] [--solo id] [--cols N]

Vista de perfil con un poco de altura: es como mejor se lee la silueta de un arma (que es lo que
la distingue de las demas en una captura) y como antes se ve una pieza flotando o torcida.
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
salida = argv[0] if argv and not argv[0].startswith("--") else os.path.join(RAIZ, "docs", "armas.png")
solo = argv[argv.index("--solo") + 1] if "--solo" in argv else ""
cols = int(argv[argv.index("--cols") + 1]) if "--cols" in argv else 2

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)

ficha = json.load(open(os.path.join(ARMAS, "armas.json"), encoding="utf-8"))
ids = [i for i in ficha.keys() if (not solo or i == solo)]
if solo:
    cols = 1
PASO_Y = 1.10      # de un arma a la de al lado, a lo largo del cañon
PASO_Z = 0.30      # de una fila a la de abajo


def importar(ruta):
    antes = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=ruta)
    return [o for o in bpy.data.objects if o not in antes]


filas = (len(ids) + cols - 1) // cols
for k, wid in enumerate(ids):
    obs = importar(os.path.join(ARMAS, wid + ".glb"))
    cy = (k % cols - (cols - 1) * 0.5) * PASO_Y
    cz = -(k // cols) * PASO_Z
    for o in obs:
        if o.parent is None:
            o.location += Vector((0.0, cy, cz))

# ENCUADRE POR LA CAJA DE VERDAD: se mide lo que hay y se centra ahi. Midiendo "a ojo" con el paso
# de la rejilla, las armas salian cortadas por un lado y con medio metro de aire por el otro.
ymin = zmin = 1e9
ymax = zmax = -1e9
for o in bpy.data.objects:
    if o.type != 'MESH':
        continue
    for v in o.bound_box:
        p = o.matrix_world @ Vector(v)
        ymin, ymax = min(ymin, p.y), max(ymax, p.y)
        zmin, zmax = min(zmin, p.z), max(zmax, p.z)
ancho = max(ymax - ymin, 0.05) * 1.08
alto = max(zmax - zmin, 0.05) * 1.12
centro = Vector((0.0, (ymin + ymax) * 0.5, (zmin + zmax) * 0.5))

cam_dat = bpy.data.cameras.new("cam")
cam_dat.type = 'ORTHO'
cam_dat.ortho_scale = max(ancho, alto)
cam = bpy.data.objects.new("cam", cam_dat)
bpy.context.collection.objects.link(cam)
# de perfil (desde -X) con 14 grados de altura: se lee el contorno y aun asi se ve el volumen
d = Vector((-2.6, 0.0, 0.9))
cam.location = centro + d
cam.rotation_mode = 'QUATERNION'
cam.rotation_quaternion = d.to_track_quat('Z', 'Y')
bpy.context.scene.camera = cam

# LUZ MEDIDA, no a saco: el metal casi no tiene difuso, solo refleja, asi que con soles muy fuertes
# y el mundo apagado el acero salia NEGRO y el polimero blanco, justo al reves de como se ven. La
# mayor parte de la luz tiene que venir del ambiente.
sol = bpy.data.objects.new("sol", bpy.data.lights.new("sol", 'SUN'))
sol.data.energy = 2.2
sol.data.angle = math.radians(10.0)
sol.rotation_euler = (math.radians(56), 0.0, math.radians(-62))
bpy.context.collection.objects.link(sol)
relleno = bpy.data.objects.new("relleno", bpy.data.lights.new("relleno", 'SUN'))
relleno.data.energy = 0.9
relleno.data.color = (0.55, 0.68, 1.0)
relleno.rotation_euler = (math.radians(108), 0.0, math.radians(96))
bpy.context.collection.objects.link(relleno)
canto = bpy.data.objects.new("canto", bpy.data.lights.new("canto", 'SUN'))
canto.data.energy = 1.3
canto.data.color = (1.0, 0.92, 0.8)
canto.rotation_euler = (math.radians(72), 0.0, math.radians(160))
bpy.context.collection.objects.link(canto)

sc = bpy.context.scene
mundo = bpy.data.worlds.new("w")
mundo.use_nodes = True
mundo.node_tree.nodes["Background"].inputs[0].default_value = (0.20, 0.215, 0.235, 1.0)
mundo.node_tree.nodes["Background"].inputs[1].default_value = 1.6
sc.world = mundo
for motor in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE', 'CYCLES'):
    try:
        sc.render.engine = motor
        break
    except Exception:
        continue
if sc.render.engine == 'CYCLES':
    sc.cycles.samples = 48
sc.render.resolution_x = 1700
sc.render.resolution_y = max(500, min(2400, int(1700 * alto / max(ancho, 0.001))))
if solo:
    sc.render.resolution_x = 1500
    sc.render.resolution_y = max(600, min(1500, int(1500 * alto / max(ancho, 0.001))))
sc.render.filepath = salida
sc.render.image_settings.file_format = 'PNG'
os.makedirs(os.path.dirname(salida), exist_ok=True)
bpy.ops.render.render(write_still=True)
print("[render] %s  (%d armas)" % (salida, len(ids)))
