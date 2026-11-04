"""Monta los vehiculos en Blender y los saca a godot/vehiculos/*.glb + vehiculos.json.

    blender -b --python tools/blender/vehiculos/exportar_vehiculos.py -- [id1 id2 ...]

Sin argumentos saca los cuatro (coche, todoterreno, moto, helicoptero). Cada .glb lleva la carroceria y,
como nodos aparte, las ruedas (o los rotores), con su origen en el eje de giro: el juego los busca por
nombre y los hace girar. La ficha lleva, ya EN COORDENADAS DE GODOT, los asientos, las ruedas con su radio,
el motor, el escape y los faros; el juego no mide nada, lee la ficha.

CONVERSION DE EJES: se modela con el morro a +Y de Blender y +Z arriba; el exportador de glTF gira el mundo,
asi que un punto (x, y, z) de Blender es (x, z, -y) en Godot, que mira a -Z (igual que las armas).
"""
import json
import math
import os
import sys

import bpy

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(AQUI)))
sys.path.insert(0, AQUI)

import voxel                                  # noqa: E402
import vehiculos as catalogo                  # noqa: E402

SALIDA = os.path.join(RAIZ, "godot", "vehiculos")


## Blender -> Godot tambien para los EJES de giro: (x, y, z) de Blender es (x, z, -y) en Godot.
EJES = {"x": "x", "y": "z", "z": "y"}


def g(p):
    """Punto de Blender -> punto de Godot."""
    return [round(p[0], 4), round(p[2], 4), round(-p[1], 4)]


def exportar(objetos, ruta):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objetos:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objetos[0]
    bpy.ops.export_scene.gltf(filepath=ruta, export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True, export_materials="EXPORT",
                              export_normals=True, export_texture_dir="")


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ids = args if args else list(catalogo.CATALOGO.keys())
    os.makedirs(SALIDA, exist_ok=True)
    fichas = {}
    for vid in ids:
        voxel.limpiar()
        mats = voxel.materiales()
        salida = catalogo.CATALOGO[vid](mats)
        cuerpo, ruedas, ficha, radio, ancho_r = salida[0], salida[1], salida[2], salida[3], salida[4]
        piezas = [cuerpo]
        ficha_ruedas = []
        for nombre, pos, dir_ in ruedas:
            ob = catalogo.rueda(nombre, radio, ancho_r, mats, taco=(ficha["tipo"] == "todoterreno"))
            ob.location = pos
            piezas.append(ob)
            ficha_ruedas.append({"nodo": nombre, "pos": g(pos), "radio": radio, "ancho": ancho_r, "dirige": dir_})
        rotores = salida[5] if len(salida) > 5 else []
        for i, ob in enumerate(rotores):
            ob.location = ficha["rotores"][i]["pos"]
        piezas += rotores
        ruta = os.path.join(SALIDA, "%s.glb" % vid)
        exportar(piezas, ruta)
        f = {
            "tipo": ficha["tipo"], "masa": ficha["masa"],
            "tamano": [round(ficha["ancho"], 3), round(ficha["alto"], 3), round(ficha["largo"], 3)],
            "asientos": [{"pos": g(a["pos"]), "rol": a["rol"]} for a in ficha["asientos"]],
            "ruedas": ficha_ruedas,
            "motor": g(ficha["motor"]), "escape": g(ficha["escape"]),
            "faros": [g(p) for p in ficha["faros"]],
        }
        # POR DONDE SE ASOMA CADA PASAJERO A DISPARAR. Sin copiarlo aqui, el juego leia una ficha sin
        # ventanillas y nadie se asomaba nunca (medido: lado 0 en todos los asientos).
        if "ventanillas" in ficha:
            f["ventanillas"] = ficha["ventanillas"]
        # DONDE APOYA LOS PIES quien va sentado. Sin esto el juego colocaba al jugador por debajo del
        # coche y desde dentro se le veian las piernas atravesando el suelo.
        if "suelo_cabina" in ficha:
            f["suelo_cabina"] = round(float(ficha["suelo_cabina"]), 3)
        if "rotores" in ficha:
            # EL EJE TAMBIEN CAMBIA DE SISTEMA. La posicion se convertia con g() pero el eje se copiaba
            # tal cual: el rotor principal gira sobre Z en Blender, que en Godot es la Y. Con "z" el
            # juego lo hacia girar sobre el eje del morro y las palas salian dando vueltas de lado.
            f["rotores"] = [{"nodo": r["nodo"], "pos": g(r["pos"]), "eje": EJES[r["eje"]], "rpm": r["rpm"]}
                            for r in ficha["rotores"]]
        if "patines" in ficha:
            f["patines"] = [g(p) for p in ficha["patines"]]
        fichas[vid] = f
        print("[vehiculos] %-12s %6d triangulos (%d piezas) -> %s" % (
            vid, sum(voxel.tris(o) for o in piezas), len(piezas), os.path.basename(ruta)))
    ruta_json = os.path.join(SALIDA, "vehiculos.json")
    if os.path.exists(ruta_json) and len(ids) < len(catalogo.CATALOGO):
        viejo = json.load(open(ruta_json, encoding="utf-8"))
        viejo.update(fichas)
        fichas = viejo
    with open(ruta_json, "w", encoding="utf-8") as fp:
        json.dump(fichas, fp, ensure_ascii=False, indent=1)
    print("[vehiculos] ficha: %s (%d vehiculos)" % (ruta_json, len(fichas)))


main()
