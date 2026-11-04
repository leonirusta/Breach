"""VISTA PREVIA DEL REMATE: el Goliat te agarra del suelo, te sube a la cara y te traga.

blender -b breach_goliat.blend --python tools/blender/criaturas/devorar_preview.py -- <salida.mp4> [grados]

Monta la escena de la muerte: el soldado plantado delante, el clip "devorar" del Goliat y el soldado
pegado a la mano derecha desde el agarre hasta el bocado (se calcula la matriz del hueso frame a frame,
que es lo unico que hay: el clip del bicho no sabe nada del soldado). Mientras esta en la mano patalea y
manotea, y al morder desaparece dentro de la boca. Sale un mp4 para verlo antes de meterlo en el juego.
"""
import bpy, json, math, sys
from mathutils import Vector, Matrix, Euler

args = sys.argv[sys.argv.index("--") + 1:]
SALIDA = args[0]                                   # carpeta/prefijo de los PNG (uno por frame)
BLEND = args[1]                                    # .blend con la escena montada, para verlo con el play
ANGULO = float(args[2]) if len(args) > 2 else 34.0

sc = bpy.context.scene
clips = json.loads(sc["clips"])
F0, F1 = clips["devorar"]

rig = bpy.data.objects["Goliat_Rig"]
sol = bpy.data.objects["Soldado_Rig"]
malla = bpy.data.objects.get("Soldado")

# frames del clip (1..120) llevados a la linea de tiempo
def F(n):
    return F0 + n - 1

AGARRE, BOCA, FIN = F(26), F(62), F(78)     # cierra la mano / muerde / ya esta dentro
PIE = Vector((-0.45, -2.45, 0.0))           # donde esta plantado el jugador (delante de la mano)


# ---------------------------------------------------------------- el soldado
# De pie mirando al bicho (el Goliat mira a -Y, asi que el soldado mira a +Y).
sol.rotation_mode = 'XYZ'
sol.location = PIE
sol.rotation_euler = Euler((0, 0, math.pi), 'XYZ')
sol.scale = (1, 1, 1)

PB = sol.pose.bones
for b in PB:
    b.rotation_mode = 'XYZ'


def pose_soldado(d, f):
    """d: {hueso: (rx, ry, rz) en grados} -> claves en el frame f (lo que no se nombra, a reposo)"""
    for b in PB:
        b.rotation_euler = Euler([math.radians(v) for v in d.get(b.name, (0, 0, 0))], 'XYZ')
        b.keyframe_insert("rotation_euler", frame=f)


# cada pose: lo que hace el muñeco en ese momento
QUIETO = {}
SUSTO = {"arm_upper_l": (-70, 0, -25), "arm_upper_r": (-70, 0, 25), "arm_lower_l": (-60, 0, 0),
         "arm_lower_r": (-60, 0, 0), "chest": (-14, 0, 0), "head": (-18, 0, 0), "neck": (-10, 0, 0),
         "leg_upper_l": (12, 0, 0), "leg_upper_r": (-8, 0, 0)}
PATALEO_A = {"leg_upper_l": (-55, 0, 8), "leg_lower_l": (70, 0, 0), "leg_upper_r": (25, 0, -8),
             "leg_lower_r": (20, 0, 0), "arm_upper_l": (-95, 0, -35), "arm_upper_r": (-40, 0, 20),
             "arm_lower_l": (-70, 0, 0), "arm_lower_r": (-40, 0, 0), "chest": (10, 0, 8), "head": (-25, 0, 12),
             "stomach": (8, 0, 5)}
PATALEO_B = {"leg_upper_l": (20, 0, 8), "leg_lower_l": (25, 0, 0), "leg_upper_r": (-60, 0, -8),
             "leg_lower_r": (75, 0, 0), "arm_upper_l": (-45, 0, -20), "arm_upper_r": (-90, 0, 35),
             "arm_lower_l": (-45, 0, 0), "arm_lower_r": (-75, 0, 0), "chest": (10, 0, -8), "head": (-25, 0, -12),
             "stomach": (8, 0, -5)}
FLOJO = {"leg_upper_l": (-20, 0, 4), "leg_lower_l": (35, 0, 0), "leg_upper_r": (-14, 0, -4),
         "leg_lower_r": (28, 0, 0), "arm_upper_l": (25, 0, -12), "arm_upper_r": (25, 0, 12),
         "arm_lower_l": (-15, 0, 0), "arm_lower_r": (-15, 0, 0), "chest": (18, 0, 0), "head": (30, 0, 6)}

pose_soldado(QUIETO, F(1))
pose_soldado(SUSTO, F(16))
pose_soldado(SUSTO, F(24))
patalea = True
for f in range(F(30), F(60), 5):
    pose_soldado(PATALEO_A if patalea else PATALEO_B, f)
    patalea = not patalea
pose_soldado(FLOJO, F(62))          # al morder se queda flojo
pose_soldado(FLOJO, F(70))


# ---------------------------------------------------------------- pegado a la mano
# La mano manda: se lee su matriz en cada frame y el soldado se cuelga de ella. Antes del agarre esta
# plantado en el suelo; despues del bocado se mete dentro de la boca y se apaga.
dg = bpy.context.evaluated_depsgraph_get()
## OJO CON LA MANO: hay que leerla del objeto EVALUADO. El brazo lo mueve una IK, y la pose del objeto
## original no la trae; leyendo de ahi el soldado se quedaba clavado en el suelo y luego desaparecia.
mano, boca = {}, {}
for f in range(F0, F1 + 1):
    sc.frame_set(f)
    dg.update()
    ev = rig.evaluated_get(dg)
    mano[f] = ev.matrix_world @ ev.pose.bones["hand_r"].matrix
    boca[f] = ev.matrix_world @ ev.pose.bones["jaw"].matrix

for f in range(F0, F1 + 1):
    visible = True
    if f < AGARRE:
        sol.location = PIE
        sol.rotation_euler = Euler((0, 0, math.pi), 'XYZ')
        sol.scale = (1, 1, 1)
    else:
        m = mano[f]
        # colgando de la mano: la mano manda el sitio, y el muñeco va tumbado de lado, cabeza por delante
        p = m.translation + Vector((0.10, -0.30, -0.50))
        giro = Euler((math.radians(70), 0, math.pi + m.to_euler('XYZ').z * 0.35), 'XYZ')
        if f > BOCA:
            # LO ESTA TRAGANDO: de la mano se va metiendo en la boca, y ahi si se encoge y desaparece
            t = min(1.0, (f - BOCA) / float(FIN - BOCA))
            p = p.lerp(boca[f].translation + Vector((0, -0.45, -0.20)), t)   # dentro, no por encima
            sol.scale = ((1 - 0.8 * t),) * 3
            visible = t < 0.999
        else:
            sol.scale = (1, 1, 1)
        sol.location = p
        sol.rotation_euler = giro
    sol.keyframe_insert("location", frame=f)
    sol.keyframe_insert("rotation_euler", frame=f)
    sol.keyframe_insert("scale", frame=f)
    if (f - F0 + 1) in (1, 20, 26, 34, 46, 56, 62, 70, 76):
        print("SOLDADO f%d en (%.2f, %.2f, %.2f) escala %.2f %s" % (f - F0 + 1, sol.location.x,
              sol.location.y, sol.location.z, sol.scale.x, "" if visible else "(ya no se ve)"))
    # la malla cuelga del esqueleto, asi que esconder el esqueleto NO la esconde: se apaga ella
    for ob in (sol, malla):
        if ob is None:
            continue
        ob.hide_viewport = not visible
        ob.hide_render = not visible
        ob.keyframe_insert("hide_viewport", frame=f)
        ob.keyframe_insert("hide_render", frame=f)


# ---------------------------------------------------------------- camara y luces
cam = bpy.data.objects.get("Camara")
if cam is None:
    cam = bpy.data.objects.new("Camara", bpy.data.cameras.new("Camara"))
    sc.collection.objects.link(cam)
# DEL LADO DE LA MANO QUE AGARRA (la derecha del bicho cae en -X): desde el otro lado el cuerpo tapa
# justo lo que hay que ver. Y de lejos: un bicho de 7 m con la camara a 12 m no cabe en el cuadro.
a = math.radians(ANGULO)
cam.location = Vector((-math.sin(a) * 9.0, -12.5, 3.6))
mira = Vector((-0.8, -2.6, 3.2))
# apuntar de verdad: la camara mira por su -Z con el +Y arriba (a mano salian angulos absurdos y la
# camara acababa encarada al vacio: los renders salian grises)
cam.rotation_euler = (mira - cam.location).to_track_quat('-Z', 'Y').to_euler()
cam.data.lens = 42
sc.camera = cam

# LUZ PARA VERLO: el bicho es casi negro y con la luz del blend salia una mancha oscura. Sol fuerte de
# frente, un relleno azulado por el otro lado y algo de cielo.
sol_luz = bpy.data.objects.get("Sol")
if sol_luz is None:
    sol_luz = bpy.data.objects.new("Sol", bpy.data.lights.new("Sol", 'SUN'))
    sc.collection.objects.link(sol_luz)
sol_luz.data.energy = 6.0
sol_luz.rotation_euler = Euler((math.radians(58), 0, math.radians(200)), 'XYZ')
relleno = bpy.data.objects.new("Relleno", bpy.data.lights.new("Relleno", 'SUN'))
relleno.data.energy = 2.2
relleno.data.color = (0.55, 0.68, 1.0)
relleno.rotation_euler = Euler((math.radians(66), 0, math.radians(20)), 'XYZ')
sc.collection.objects.link(relleno)
if sc.world is None:
    sc.world = bpy.data.worlds.new("Mundo")
sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.09, 0.10, 0.13, 1)
sc.world.node_tree.nodes["Background"].inputs[1].default_value = 1.2

sc.frame_start, sc.frame_end = F0, F1
sc.render.engine = 'BLENDER_EEVEE'
sc.render.resolution_x, sc.render.resolution_y = 640, 400
sc.render.fps = 30
# ESTE BLENDER NO TRAE VIDEO (no hay FFMPEG en la lista de formatos): se sacan los frames en PNG y el
# montaje del gif se hace fuera. El .blend queda guardado para poder darle al play y verlo de verdad.
sc.render.image_settings.file_format = 'PNG'
sc.render.filepath = SALIDA
# con "-" de salida no se renderiza nada: solo se deja el .blend montado para verlo con el play
if SALIDA != "-":
    bpy.ops.render.render(animation=True)
bpy.ops.wm.save_as_mainfile(filepath=BLEND)
print("LISTO frames", F0, F1, "->", BLEND)
