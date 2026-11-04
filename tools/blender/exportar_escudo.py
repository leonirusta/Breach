"""Exporta breach_escudo.blend (escudo_anim.py) al juego.

blender -b <breach_escudo.blend> --python tools/blender/exportar_escudo.py

Saca dos cosas:
  godot/avatar/escudo.json   por clip y por frame, lo que en el juego no mueve un clip sino la IK:
      esc_tp / pis_tp   escudo y pistola en TERCERA persona: [pos(3), giro(4)], pos respecto al CUELLO en
                        metros, ejes del esqueleto y ESPEJADO como el resto (igual que el mazo)
      esc_fp / pis_fp   lo mismo en PRIMERA persona, en el espacio de la camara (respecto al ojo animado,
                        sin espejo)
      mano_der / mano_izq  [muñeca respecto al cuello (3), libre 0..1]: libre = la mano no esta en su objeto
                        (recarga, rotura) y va a esa muñeca
      mag_nuevo         el cargador nuevo en el espacio de la PISTOLA [pos(3), giro(4)] (recarga)
  godot/avatar/clips_breach.json   el CUERPO de cada clip (escudo_guardia, escudo_apuntar...), con
                        exportar_clips.py: el juego usa torso y cabeza encima de lo que hagan las piernas.
"""
import bpy, json, os, runpy, sys
from mathutils import Matrix, Vector

AQUI = os.path.dirname(os.path.abspath(__file__))
AV = os.path.normpath(os.path.join(AQUI, "..", "..", "godot", "avatar"))
sc = bpy.context.scene
rig = bpy.data.objects["Soldado_Rig"]
BN = rig.data.bones
P = Matrix(((1, 0, 0), (0, 0, 1), (0, 1, 0)))       # Blender -> esqueleto, con espejo
M = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))      # Blender -> camara de Godot, sin espejo
CLIPS = {k: tuple(v) for k, v in sc["clips"].items()}
OJO_CABEZA = BN["head"].matrix_local.inverted() @ Vector(sc["ojo"])
mag_nuevo = bpy.data.objects["Cargador_nuevo"]
P_GRIP = Vector((0.0, 0.062, -0.056))


def v(m, b):
    r = m @ b
    return [round(r.x, 5), round(r.y, 5), round(r.z, 5)]


def q(m, r):
    qq = (m @ r @ m).to_quaternion()
    return [round(qq.x, 5), round(qq.y, 5), round(qq.z, 5), round(qq.w, 5)]


dg = bpy.context.evaluated_depsgraph_get()
datos = {"fps": sc.render.fps, "clips": {}}
for nombre, (a, b) in CLIPS.items():
    c = {"frames": b - a + 1, "esc_tp": [], "pis_tp": [], "esc_fp": [], "pis_fp": [], "mano_der": [], "mano_izq": [],
         "mag_nuevo": []}
    ultimo = {}
    for f in range(a, b + 1):
        sc.frame_set(f)
        ev = rig.evaluated_get(dg).pose.bones
        ro = rig.evaluated_get(dg)
        cuello = ev["neck"].head
        ojo = ev["head"].matrix @ OJO_CABEZA
        for clave, hueso in (("esc", "CTRL_escudo"), ("pis", "CTRL_arma")):
            w = ev[hueso].matrix
            r = w.to_3x3()
            for suf, mat, ref in (("_tp", P, cuello), ("_fp", M, ojo)):
                rot = q(mat, r)
                k = clave + suf
                # sin saltos de signo entre frames (el juego interpola con slerp)
                if k in ultimo and sum(x * y for x, y in zip(ultimo[k], rot)) < 0:
                    rot = [-x for x in rot]
                ultimo[k] = rot
                c[k].append(v(mat, w.translation - ref) + rot)
        for clave, mano, prop in (("mano_der", "hand_l", "mano_der_libre"), ("mano_izq", "hand_r", "mano_izq_libre")):
            c[clave].append(v(P, ev[mano].head - cuello) + [round(float(ro.get(prop, 0.0)), 3)])
        wp = ev["CTRL_arma"].matrix
        ml = wp.inverted() @ mag_nuevo.matrix_world
        rot = q(P, ml.to_3x3())
        c["mag_nuevo"].append(v(P, ml.translation) + rot)
    datos["clips"][nombre] = c
    print("CLIP", nombre, c["frames"], "frames")
ruta = os.path.join(AV, "escudo.json")
with open(ruta, "w") as fh:
    json.dump(datos, fh, separators=(",", ":"))
print("EXPORTADO", ruta)

# ---- el cuerpo de cada clip, con el exportador de siempre -------------------------------------------------
EXP = os.path.join(AQUI, "exportar_clips.py")
CLIPS_JSON = os.path.join(AV, "clips_breach.json")
fin = sc.frame_end
for nombre, (a, b) in CLIPS.items():
    if nombre == "guardia":
        sc.frame_end = b
        for k in ("juego_desde", "juego_hasta"):
            if k in sc:
                del sc[k]
        sys.argv = [sys.argv[0], "--", CLIPS_JSON, "escudo_guardia", "0", "30"]
    else:
        sc.frame_end = fin
        sc["juego_desde"], sc["juego_hasta"] = a, b
        sys.argv = [sys.argv[0], "--", CLIPS_JSON, "escudo_" + nombre, "0", "30", "unavez"]
    runpy.run_path(EXP, run_name="__main__")
sc.frame_end = fin
print("LISTO")
