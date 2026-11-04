"""Que hay dentro de un .blend: objetos, mallas, grupos de huesos y caja que ocupan.

    blender -b <archivo.blend> --python tools/blender/leer_blend.py

Sirve para saber QUE se ha tocado antes de intentar devolverlo al juego: no es lo mismo que hayan
movido unos cubos de una pieza que que hayan esculpido un cuerpo nuevo.
"""
import bpy

print("=" * 70)
for ob in bpy.data.objects:
    linea = "%-22s %-10s" % (ob.name, ob.type)
    if ob.type == 'MESH':
        me = ob.data
        bb = [ob.matrix_world @ v.co for v in me.vertices] if me.vertices else []
        if bb:
            mn = [min(v[i] for v in bb) for i in range(3)]
            mx = [max(v[i] for v in bb) for i in range(3)]
            linea += " verts=%-7d caras=%-7d caja=(%.2f..%.2f, %.2f..%.2f, %.2f..%.2f)" % (
                len(me.vertices), len(me.polygons), mn[0], mx[0], mn[1], mx[1], mn[2], mx[2])
        linea += " grupos=%d" % len(ob.vertex_groups)
        linea += " colores=%s" % [c.name for c in me.color_attributes]
    elif ob.type == 'ARMATURE':
        linea += " huesos=%d" % len(ob.data.bones)
    print(linea)
print("=" * 70)

# cuantos vertices caen en cada grupo de hueso: dice donde se ha trabajado
for ob in bpy.data.objects:
    if ob.type != 'MESH' or not ob.vertex_groups:
        continue
    cuenta = {g.name: 0 for g in ob.vertex_groups}
    for v in ob.data.vertices:
        for g in v.groups:
            nombre = ob.vertex_groups[g.group].name
            cuenta[nombre] = cuenta.get(nombre, 0) + 1
    vivos = {k: v for k, v in cuenta.items() if v}
    print("%s: %d grupos con vertices" % (ob.name, len(vivos)))
    for k in sorted(vivos, key=lambda x: -vivos[x]):
        print("   %-16s %6d" % (k, vivos[k]))
    sueltos = sum(1 for v in ob.data.vertices if not v.groups)
    if sueltos:
        print("   SIN GRUPO       %6d   <- geometria nueva, sin hueso asignado" % sueltos)
