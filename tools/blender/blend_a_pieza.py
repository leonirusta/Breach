# -*- coding: utf-8 -*-
"""De vuelta: un .blend esculpido a mano -> una PIEZA del avatar del juego.

    blender -b <modelo.blend> --python tools/blender/blend_a_pieza.py -- <nombre>

Escribe tools/piezas_blender/<nombre>.json, que `tools/make_soldier.py` mete en el catalogo de
piezas al generar el rig. Asi lo que se toca en Blender SI vuelve al juego: hasta ahora el camino
era de una sola direccion (make_soldier -> .blend) y cualquier retoque se perdia.

COMO FUNCIONA, y por que no es un simple "leer cubos":

* El .blend no guarda voxels, guarda caras. Cada cubo aparece solo con sus caras VISIBLES (las de
  dentro se tiran al generar), asi que un cubo puede venir con 6 caras o con 1. Se reconstruye el
  centro de cada cubo desde cada cara: centro = centro_de_la_cara - normal * lado/2, y luego se
  quitan los repetidos.
* La rejilla del que esculpe NO es la del juego. En el modelo del Heraldo conviven cubos de 1,107 cm
  (los que salieron del juego) y de 1,5 cm (los anadidos a mano en Blender). Por eso no se copia
  coordenada a coordenada: se REMUESTREA. Cada cubo pinta todas las celdas del juego cuyo centro
  cae dentro de el, y si no cae ninguna -un cubo mas pequeno que una celda- se queda con la celda
  de su centro, para que nada desaparezca.
* El hueso de cada cubo sale de los grupos de vertices, no de la posicion. Si se adivinara por
  cercania, un cuerno largo se partiria entre cabeza y cuello y se rajaria al mover la cabeza.
* Los colores se leen de la capa de color y se comparan con la paleta; los que no existen se
  anaden. Van al FINAL, nunca en medio: meter un color en medio corre todos los indices siguientes
  y el casco entero se vuelve rojo (paso, de verdad).
"""
import bpy, json, math, os, sys
from collections import Counter
from mathutils import Vector

RAIZ = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
AV = os.path.join(RAIZ, "godot", "avatar")
DESTINO = os.path.join(RAIZ, "tools", "piezas_blender")

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
NOMBRE = args[0] if args else "pieza"
# --fino: NO se remuestrea. Los cubos se quedan con su tamano (un modelo de 1 cm conserva todo el
# detalle) y se guardan como caras ya fundidas; ver el bloque 4.
FINO = "--fino" in args
# --paso=N: redondea los colores a multiplos de N antes de fundir caras. El pintado del modelo tiene
# ruido de 1-3 unidades entre cubos vecinos que no se ve y que impide juntar caras; N pequeno no se nota.
PASO = next((int(a[7:]) for a in args if a.startswith("--paso=")), 1)

rig = json.load(open(os.path.join(AV, "soldier_rig.json")))
pal = json.load(open(os.path.join(AV, "palette.json")))
bones = rig["bones"]

# --- la misma escala y centrado que uso soldado_a_blender.py, al reves -------------------------
mn_y, mx_y = 1e9, -1e9
for b in bones.values():
    oy = b["world_pos"][1] + b.get("mesh_off", [0, 0, 0])[1]
    for v in b["voxels"]:
        mn_y, mx_y = min(mn_y, oy + v[1]), max(mx_y, oy + v[1] + 1)
S = 1.75 / (mx_y - mn_y)
X0 = (bones["leg_upper_l"]["world_pos"][0] + bones["leg_upper_r"]["world_pos"][0]) / 2
Z0 = (bones["foot_l"]["world_pos"][2] + bones["foot_r"]["world_pos"][2]) / 2
# La pierna derecha iba desplazada solo en el exportador (DESPLAZA) y aqui se deshacia. Ahora ese
# ajuste esta dentro del rig (make_soldier.py, AJUSTE_CADENAS) y el exportador ya no mueve nada, asi
# que no hay nada que deshacer: la cadena queda vacia y dx vale 0.
CADENA_L = set()


def a_godot(p):
    """Blender (Z arriba, mirando a -Y, 1,75 m) -> coordenadas de voxel del juego."""
    return Vector((X0 - p.x / S, mn_y + p.z / S, Z0 + p.y / S))


def a_bytes(c):
    """color lineal de Blender -> sRGB 0..255, que es como esta la paleta."""
    out = []
    for x in c[:3]:
        x = max(0.0, min(1.0, x))
        s = x * 12.92 if x <= 0.0031308 else 1.055 * (x ** (1 / 2.4)) - 0.055
        out.append(int(round(s * 255)))
    return tuple(out)


# --- 1) reconstruir los cubos ------------------------------------------------------------------
ob = None
for o in bpy.data.objects:
    if o.type == 'MESH' and (ob is None or len(o.data.vertices) > len(ob.data.vertices)):
        ob = o
if ob is None:
    raise SystemExit("no hay malla en el .blend")
me, M = ob.data, ob.matrix_world
col = me.color_attributes.get("Col") or (me.color_attributes[0] if me.color_attributes else None)
grupos = [g.name for g in ob.vertex_groups]

cubos = {}
caras_de = {}        # cubo -> normales de las caras que TRAE el .blend (el modelo es hueco por dentro)
for pol in me.polygons:
    vs = [M @ me.vertices[i].co for i in pol.vertices]
    lado = (vs[0] - vs[1]).length
    if lado <= 1e-6:
        continue
    nrm = (M.to_3x3() @ pol.normal).normalized()
    centro = sum(vs, Vector()) / len(vs) - nrm * (lado / 2.0)
    clave = (round(centro.x, 4), round(centro.y, 4), round(centro.z, 4))
    caras_de.setdefault(clave, set()).add(tuple(int(round(x)) for x in nrm))
    if clave in cubos:
        continue
    # color: la capa es por esquina, asi que se promedia la cara
    if col is not None and col.domain == 'CORNER':
        c = [0.0, 0.0, 0.0]
        for li in pol.loop_indices:
            d = col.data[li].color
            for k in range(3):
                c[k] += d[k]
        c = [x / len(pol.loop_indices) for x in c]
    elif col is not None:
        c = list(col.data[pol.vertices[0]].color)[:3]
    else:
        c = [0.5, 0.5, 0.5]
    # hueso: el grupo con mas peso entre los vertices de la cara
    peso = Counter()
    for i in pol.vertices:
        for g in me.vertices[i].groups:
            peso[grupos[g.group]] += g.weight
    hueso = peso.most_common(1)[0][0] if peso else None
    cubos[clave] = (Vector(clave), lado, a_bytes(c), hueso)

print("[pieza] %d caras -> %d cubos" % (len(me.polygons), len(cubos)))
print("[pieza] tamanos de cubo: %s" % dict(Counter(round(c[1], 4) for c in cubos.values())))

# --- 2) remuestrear a la rejilla del juego, hueso a hueso --------------------------------------
celdas = {}          # hueso -> {(x,y,z): Counter(color)}
sin_hueso = 0
for centro, lado, color, hueso in cubos.values():
    if hueso is None or hueso not in bones:
        sin_hueso += 1
        continue
    b = bones[hueso]
    off = [b["world_pos"][i] + b.get("mesh_off", [0, 0, 0])[i] for i in range(3)]
    dx = -2.0 if hueso in CADENA_L else 0.0      # deshacer el desplazamiento del exportador
    g = a_godot(centro)
    medio = (lado / S) / 2.0                     # media arista, ya en voxels del juego
    lo = [g[i] - medio - off[i] for i in range(3)]
    hi = [g[i] + medio - off[i] for i in range(3)]
    lo[0] -= dx
    hi[0] -= dx
    mapa = celdas.setdefault(hueso, {})
    puestas = 0
    rangos = [range(int(math.floor(lo[i] - 0.5)), int(math.ceil(hi[i] + 0.5)) + 1) for i in range(3)]
    for x in rangos[0]:
        for y in rangos[1]:
            for z in rangos[2]:
                c = (x + 0.5, y + 0.5, z + 0.5)
                if all(lo[i] <= c[i] <= hi[i] for i in range(3)):
                    mapa.setdefault((x, y, z), Counter())[color] += 1
                    puestas += 1
    if puestas == 0:                              # cubo mas fino que una celda: no se pierde
        c = tuple(int(math.floor((lo[i] + hi[i]) / 2.0)) for i in range(3))
        mapa.setdefault(c, Counter())[color] += 1

if sin_hueso:
    print("[pieza] AVISO: %d cubos sin grupo de hueso; no se pueden animar y se descartan" % sin_hueso)

# --- 3) colores -> paleta ----------------------------------------------------------------------
# SOLO SE REUTILIZAN LOS COLORES DEL SOLDADO, no los que las piezas de Blender anadieron al final de
# palette.json. make_soldier.py rehace ese tramo en cada generacion (cada pieza pone sus colores
# detras de la anterior), asi que un indice que apunte ahi se queda apuntando a otro color en cuanto
# cambia cuantos colores trae una pieza: al volver a importar el Heraldo de Llama salio entero moteado.
base_pal = len(pal)
carpeta_piezas = DESTINO
if os.path.isdir(carpeta_piezas):
    for _a in os.listdir(carpeta_piezas):
        if _a.endswith(".json"):
            base_pal -= len(json.load(open(os.path.join(carpeta_piezas, _a), encoding="utf-8")).get("colores", []))
existentes = {tuple(c): i for i, c in enumerate(pal[:max(0, base_pal)])}
print("[pieza] paleta: %d colores del soldado reutilizables (de %d)" % (base_pal, len(pal)))
nuevos, indice = [], {}


def idx(c):
    if c not in indice:
        if c in existentes:
            indice[c] = ("V", existentes[c])
        else:
            indice[c] = ("N", len(nuevos))
            nuevos.append(list(c))
    return indice[c]


vox, total = {}, 0
for hueso, mapa in celdas.items():
    lista = []
    for (x, y, z), cuenta in mapa.items():
        k, i = idx(cuenta.most_common(1)[0][0])
        lista.append([x, y, z, k, i])
    vox[hueso] = sorted(lista)
    total += len(lista)

# --- 4) MODO FINO: la rejilla del propio modelo, sin remuestrear -------------------------------
# Remuestrear un modelo de 1 cm en la rejilla del soldado (2,6 cm) mezcla dos o tres cubos por celda
# y se queda con el color mayoritario: la cara, las franjas y los ojos se rompen. Aqui cada cubo se
# queda como es. Para que no sean 128.000 caras sueltas, las caras visibles del mismo color y en el
# mismo plano se FUNDEN en rectangulos (mallado voraz); el juego solo tiene que dibujarlos.
fino = None
if FINO:
    lados = set(round(c[1], 5) for c in cubos.values())
    if len(lados) != 1:
        raise SystemExit("--fino necesita cubos de un solo tamano (hay %s)" % sorted(lados))
    e = next(iter(cubos.values()))[1] / S          # arista del cubo en voxels del soldado
    base = None
    por_hueso = {}
    visibles = set()     # (celda, normal en ejes del juego)
    for clave, (centro, lado, color, hueso) in cubos.items():
        if hueso is None or hueso not in bones:
            continue
        g = a_godot(centro)
        if base is None:
            base = [g[i] - e / 2.0 for i in range(3)]
        k = tuple(int(round((g[i] - e / 2.0 - base[i]) / e)) for i in range(3))
        if PASO > 1:
            color = tuple(min(255, int(round(x / PASO)) * PASO) for x in color)
        por_hueso.setdefault(hueso, {})[k] = color
        for n in caras_de[clave]:
            # misma conversion que a_godot, sin traslacion: x se invierte, (y, z) de Blender -> (z, y)
            visibles.add((k, (-n[0], n[2], n[1])))
    # EL .BLEND ES UNA CASCARA HUECA. Mientras todo esta quieto no importa, pero al animar, donde se
    # juntan dos huesos (hombro, codo, cintura) la union se abre y por la rendija se veia el hueco: el
    # modelo parecia sin cuerpo. Se RELLENA: todo lo que no se alcanza desde fuera es macizo, y cada
    # celda de dentro se queda con el hueso y el color de la cascara mas cercana.
    DIRS = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
    hueso_de, color_de = {}, {}
    for hb, m in por_hueso.items():
        for k, colr in m.items():
            hueso_de[k] = hb
            color_de[k] = colr
    lo_b = [min(k[i] for k in hueso_de) - 1 for i in range(3)]
    hi_b = [max(k[i] for k in hueso_de) + 1 for i in range(3)]
    fuera = {tuple(lo_b)}
    pila = [tuple(lo_b)]
    while pila:
        c = pila.pop()
        for d in DIRS:
            v = (c[0] + d[0], c[1] + d[1], c[2] + d[2])
            if v in fuera or v in hueso_de or any(v[i] < lo_b[i] or v[i] > hi_b[i] for i in range(3)):
                continue
            fuera.add(v)
            pila.append(v)
    frente = list(hueso_de.keys())
    rellenas = 0
    while frente:
        nuevo = []
        for c in frente:
            for d in DIRS:
                v = (c[0] + d[0], c[1] + d[1], c[2] + d[2])
                if v in hueso_de or v in fuera or any(v[i] < lo_b[i] or v[i] > hi_b[i] for i in range(3)):
                    continue
                hueso_de[v] = hueso_de[c]
                color_de[v] = color_de[c]
                por_hueso[hueso_de[c]][v] = color_de[c]
                nuevo.append(v)
                rellenas += 1
        frente = nuevo
    print("[pieza] FINO: %d celdas de relleno dentro de la cascara" % rellenas)
    huesos_f, caras_total = {}, 0
    for hueso, celdas_f in por_hueso.items():
        b = bones[hueso]
        off = [b["world_pos"][i] + b.get("mesh_off", [0, 0, 0])[i] for i in range(3)]
        dx = -2.0 if hueso in CADENA_L else 0.0
        origen = [base[0] - off[0] - dx, base[1] - off[1], base[2] - off[2]]
        quads = []
        for fi, d in enumerate(DIRS):
            ax = [i for i in range(3) if d[i] != 0][0]
            ua, va = [i for i in range(3) if i != ax]
            planos = {}
            for c, color in celdas_f.items():
                vec = (c[0] + d[0], c[1] + d[1], c[2] + d[2])
                # se tapa lo que toca a otra celda DEL MISMO hueso; contra otro hueso la cara se deja,
                # que es la tapa que se ve cuando la articulacion se abre
                if vec in celdas_f:
                    continue
                plano = c[ax] + (1 if d[ax] > 0 else 0)
                planos.setdefault((plano, color), set()).add((c[ua], c[va]))
            for (plano, color), sitios in planos.items():
                while sitios:
                    u0, v0 = min(sitios)
                    w = 1
                    while (u0 + w, v0) in sitios:
                        w += 1
                    h = 1
                    while all((u0 + j, v0 + h) in sitios for j in range(w)):
                        h += 1
                    for j in range(w):
                        for t in range(h):
                            sitios.discard((u0 + j, v0 + t))
                    kk, ii = idx(color)
                    quads.append([fi, plano, u0, v0, w, h, kk, ii])
        huesos_f[hueso] = {"origen": [round(x, 5) for x in origen], "quads": quads}
        caras_total += len(quads)
    fino = {"escala": round(e, 6), "huesos": huesos_f}
    print("[pieza] FINO: arista %.4f voxels del soldado, %d cubos -> %d rectangulos" %
          (e, sum(len(v) for v in por_hueso.values()), caras_total))

salida = {
    "nombre": NOMBRE,
    "origen": os.path.basename(bpy.data.filepath),
    # de estos huesos NO se dibuja el soldado de debajo. Un modelo --fino es un cuerpo ENTERO: tapa
    # todos los huesos, tambien los que no traen cubos suyos (hood, radio), o la capucha y la radio
    # del soldado asoman por la espalda del modelo.
    "tapa": sorted(bones.keys()) if FINO else sorted(vox.keys()),
    "colores": nuevos,              # se anaden a la paleta, al final
    "vox": vox,
}
if fino is not None:
    salida["fino"] = fino

# --- 5) ARTICULACIONES PROPIAS DEL MODELO ------------------------------------------------------
# Si en el .blend se ha movido un hueso (el codo del Heraldo mas abajo, sus parpados en el centro de SUS
# ojos), su sitio viaja con la pieza. El juego lo aplica SOLO al esqueleto de quien lleve esta pieza: el
# soldado y los demas avatares siguen con las suyas. Se compara con el rig y solo se apunta lo que difiere.
articulaciones = {}
for o in bpy.data.objects:
    if o.type != 'ARMATURE':
        continue
    for b in o.data.bones:
        if b.name not in bones:
            continue
        g = a_godot(o.matrix_world @ b.head_local)
        wp = bones[b.name]["world_pos"]
        if max(abs(g[i] - wp[i]) for i in range(3)) > 0.25:
            articulaciones[b.name] = [round(g[i], 3) for i in range(3)]
    break
if articulaciones:
    salida["articulaciones"] = articulaciones
    for n, v in sorted(articulaciones.items()):
        print("[pieza] articulacion propia %-12s %s (el rig la tiene en %s)" % (n, v, bones[n]["world_pos"]))
if not os.path.isdir(DESTINO):
    os.makedirs(DESTINO)
ruta = os.path.join(DESTINO, NOMBRE + ".json")
json.dump(salida, open(ruta, "w"), separators=(",", ":"))
print("[pieza] %s: %d voxels en %d huesos, %d colores nuevos (la paleta tenia %d)"
      % (ruta, total, len(vox), len(nuevos), len(pal)))
