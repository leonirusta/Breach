"""Video de vitrina de un .blend con el muñeco animado: la animacion en bucle y la camara dando una vuelta.

blender -b <modelo.blend> --python tools/blender/render_vitrina.py -- <salida.mp4> [vueltas_de_animacion=2]
Workbench (rapido, con los colores de vertice), 720x720 a 30 fps.
"""
import bpy, math, sys
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
OUT = args[0]
BUCLES = int(args[1]) if len(args) > 1 else 2
sc = bpy.context.scene
f0, f1 = sc.frame_start, sc.frame_end
largo = f1 - f0 + 1
total = largo * BUCLES

# la animacion en bucle: se repite la accion con ciclos
for ob in bpy.data.objects:
    ad = ob.animation_data
    if ad and ad.action:
        for fc in getattr(ad.action, "fcurves", []):
            if not any(m.type == 'CYCLES' for m in fc.modifiers):
                fc.modifiers.new('CYCLES')

sc.frame_start, sc.frame_end = 1, total
sc.render.engine = 'BLENDER_WORKBENCH'
sh = sc.display.shading
sh.light = 'STUDIO'
sh.color_type = 'VERTEX'
sh.show_shadows = True
sh.show_cavity = True
sc.render.resolution_x = sc.render.resolution_y = 720
sc.render.fps = 30
if hasattr(sc.render.image_settings, "media_type"):
    sc.render.image_settings.media_type = 'VIDEO'      # Blender 5: el video va aparte de las imagenes
sc.render.image_settings.file_format = 'FFMPEG'
sc.render.ffmpeg.format = 'MPEG4'
sc.render.ffmpeg.codec = 'H264'
sc.render.ffmpeg.constant_rate_factor = 'HIGH'
sc.render.filepath = OUT
sc.world = sc.world or bpy.data.worlds.new("Mundo")
sc.world.color = (0.08, 0.09, 0.11)

# camara en orbita alrededor del centro del muñeco (una vuelta en todo el video)
centro = Vector((0, 0, 1.1))
cam = sc.camera or bpy.data.objects.new("Camara", bpy.data.cameras.new("Camara"))
if cam.name not in sc.collection.objects:
    sc.collection.objects.link(cam)
sc.camera = cam
cam.data.lens = 50
piv = bpy.data.objects.new("Pivote", None)
sc.collection.objects.link(piv)
piv.location = centro
cam.parent = piv
cam.location = Vector((0, -4.2, 0.35))
cam.rotation_euler = (math.radians(85), 0, 0)
piv.rotation_euler = (0, 0, math.radians(-30))
piv.keyframe_insert("rotation_euler", index=2, frame=1)
piv.rotation_euler = (0, 0, math.radians(-30 + 360))
piv.keyframe_insert("rotation_euler", index=2, frame=total)
for fc in piv.animation_data.action.fcurves if hasattr(piv.animation_data.action, "fcurves") else []:
    for kp in fc.keyframe_points:
        kp.interpolation = 'LINEAR'
bpy.ops.render.render(animation=True)
print("VIDEO", OUT, total, "frames")
