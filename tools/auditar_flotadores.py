"""Audita un .vxmap: que hay en el mapa que NO se sostiene, y donde.

POR QUE HACE FALTA. Un mapa recien cargado no se derrumba: la regla "pristine" da por estatico todo
lo que esta intacto, aunque no toque el suelo. En cuanto danas cualquier chunk de un conjunto conexo,
esa proteccion se cae para el conjunto ENTERO y solo cuentan las anclas de verdad. Resultado en el
juego: pegas un tiro en una esquina y al otro lado del mapa se desploma algo que llevaba ahi desde el
principio, sin que nadie lo haya tocado. No es un fallo de las fisicas: es geometria del mapa que
nunca estuvo apoyada, y las fisicas solo la delatan.

Esto NO toca el mapa. Solo lo cuenta, para saber si hay que arreglar el generador del mapa o pasarle
`fix_floaters.py`.

Uso:  python tools/auditar_flotadores.py godot/maps/pruebas.vxmap [...]
"""
import sys, os
import numpy as np
from scipy import ndimage
from fix_floaters import read_vxmap, MIN_VOXELS


def auditar(ruta):
    header, dims, vs, mats, vol = read_vxmap(ruta)
    total = int((vol > 0).sum())
    print("\n=== %s ===" % os.path.basename(ruta))
    print("  %dx%dx%d celdas de %.2f m, %d voxels solidos" % (*vol.shape, vs, total))
    if vol.size > 260_000_000:
        print("  mapa demasiado grande para el etiquetado denso; usa fix_floaters.py (via losas)")
        return
    anchor_ids = [16 + i for i, m in enumerate(mats) if m[5] & 1]      # flag MF_ANCHOR
    lab, n = ndimage.label(vol > 0)
    anclados = set(np.unique(lab[np.isin(vol, anchor_ids)]).tolist())
    anclados.discard(0)
    tam = np.bincount(lab.ravel())
    cajas = ndimage.find_objects(lab)
    solido = vol > 0
    sueltos = []
    for k in range(1, n + 1):
        if k in anclados or cajas[k - 1] is None:
            continue
        sl = cajas[k - 1]
        comp = (lab[sl] == k)
        coords = np.argwhere(comp)
        gx = coords[:, 0] + sl[0].start; gy = coords[:, 1] + sl[1].start; gz = coords[:, 2] + sl[2].start
        # cuanto caeria: se quita la pieza y se baja hasta chocar
        vol_k = vol[sl][comp].copy()
        solido[gx, gy, gz] = False
        caida = -1
        for dy in range(1, 61):
            ny = gy - dy
            if (ny < 0).any() or solido[gx, ny, gz].any():
                caida = dy - 1
                break
        solido[gx, gy, gz] = True
        mat = int(np.bincount(vol_k).argmax())
        sueltos.append((int(tam[k]), caida, gx.min(), gy.min(), gz.min(), gx.max(), gy.max(), gz.max(), mat))
    if not sueltos:
        print("  OK: todo lo que hay en el mapa se sostiene en algo anclado")
        return
    sueltos.sort(reverse=True)
    vox_sueltos = sum(s[0] for s in sueltos)
    print("  %d conjuntos SIN APOYO (%d voxels, %.2f %% del mapa):" % (
        len(sueltos), vox_sueltos, 100.0 * vox_sueltos / max(1, total)))
    for tam_k, caida, x0, y0, z0, x1, y1, z1, mat in sueltos[:25]:
        centro = ((x0 + x1) * 0.5 * vs, (y0 + y1) * 0.5 * vs, (z0 + z1) * 0.5 * vs)
        cae = "%.2f m" % (caida * vs) if caida >= 0 else "AL VACIO (no hay nada debajo)"
        etiqueta = "basura (<%d vox)" % MIN_VOXELS if tam_k < MIN_VOXELS else "estructura"
        print("    %8d vox  %-12s  centro (%6.1f,%6.1f,%6.1f) m  mat %3d  caeria %s" % (
            tam_k, etiqueta, *centro, mat, cae))
    if len(sueltos) > 25:
        print("    ... y %d mas" % (len(sueltos) - 25))
    # PATRONES. 694 conjuntos sueltos no son 694 errores: casi siempre es UN atrezo repetido que el
    # generador coloca un voxel por encima de su apoyo. Agrupando por (material, tamaño, caida) sale
    # a la vista de golpe cual es la pieza culpable y cuantas veces esta puesta.
    from collections import Counter
    patrones = Counter((mat, tam_k, caida) for tam_k, caida, *_ , mat in
                       [(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8]) for a in sueltos])
    print("  patrones repetidos (material, voxels, caida) -> cuantas veces:")
    for (mat, tam_k, caida), n_rep in patrones.most_common(15):
        if n_rep < 2:
            continue
        print("    mat %3d  %5d vox  cae %5.2f m  x%d" % (mat, tam_k, caida * vs if caida >= 0 else -1, n_rep))
    un_voxel = sum(1 for a in sueltos if a[1] == 1)
    cero = sum(1 for a in sueltos if a[1] == 0)
    vacio = sum(1 for a in sueltos if a[1] < 0)
    print("  resumen de caida: %d a UN voxel del apoyo · %d ya tocaban (union por arista) · %d al vacio" % (
        un_voxel, cero, vacio))


if __name__ == "__main__":
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    for r in sys.argv[1:]:
        auditar(r)
