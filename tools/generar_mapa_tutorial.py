#!/usr/bin/env python3
"""GENERADOR DEL MAPA DEL TUTORIAL (tutorial). 2026-10-04, pedido: "un mapa muy chico para un tutorial: que empiece con
el mazo para romper una pared, recoges la metralleta y pruebas, destruyes unas columnas para que caiga una viga y
subir, te enseña a trepar, las granadas, y te explica las fisicas haciendo destruccion. Al completarlo vas al lobby".

Un recinto de ladrillo en U (tools/mapa_tutorial/disposicion.py) con el kit de la CAFETERIA (muros de capas que se
desconchan, ladrillo, hormigon, madera): el tutorial es lo primero que ve un jugador nuevo y tiene que parecer el
juego, no una caja gris. Cada estacion lleva su numero pintado en amarillo, del color del objetivo de la pantalla.

  godot/maps/tutorial.vxmap (10 cm, --hi) / tutorial_lo.vxmap (20 cm, el que se juega)
  godot/maps/tutorial.tutorial.json   lo que lee scripts/tutorial.gd: donde esta cada cosa de cada paso

Comprueba al final (en el de 20 cm) que no hay nada flotando sin ancla y que los sitios clave se alcanzan andando.

Uso:  python tools/generar_mapa_tutorial.py
"""
import json, os, random, sys, time
import numpy as np

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(AQUI, "mapa_pve"))
sys.path.insert(0, os.path.join(AQUI, "mapa_cafeteria"))
sys.path.insert(0, os.path.join(AQUI, "mapa_tutorial"))        # PRIMERO: su disposicion manda (piezas lee D.MURO)
import disposicion as D      # noqa: E402
import lienzo as L           # noqa: E402
import raster                # noqa: E402
import generar_mapa_pve as G  # noqa: E402
import materiales as MAT     # noqa: E402
import pintura               # noqa: E402
import piezas as P           # noqa: E402
import mobiliario as MOB     # noqa: E402

RAIZ = os.path.dirname(AQUI)
MAPAS = os.path.join(RAIZ, "godot", "maps")
NOMBRE = "tutorial"
SEMILLA = 20261004
GY = D.G


def muro_capas(l, x0, z0, x1, z1, y0, y1, a="revoque_arena", b="revoque_int", nucleo="ladrillo"):
    """Muro de tres capas (0,6). `a` es la cara de -X/-Z, `b` la de +X/+Z."""
    l.caja(x0, y0, z0, x1, y1, z1, nucleo)
    if (x1 - x0) < (z1 - z0):           # corre a lo largo de Z
        l.caja(x0, y0, z0, x0 + 0.2, y1, z1, a)
        l.caja(x1 - 0.2, y0, z0, x1, y1, z1, b)
    else:
        l.caja(x0, y0, z0, x1, y1, z0 + 0.2, a)
        l.caja(x0, y0, z1 - 0.2, x1, y1, z1, b)


def numero(l, cara, u_centro, y_top, txt):
    """El numero de la estacion, pintado en amarillo en la pared (en el plano del revoque: no sobresale)."""
    import letras
    _pix, ancho = letras.pixeles(txt, "peque")
    w = ancho * 0.2
    u0 = u_centro - w * 0.5 if cara.dch > 0 else u_centro + w * 0.5
    P.rotulo(l, cara, u0, y_top, txt, mat="grafiti_amarillo", px=0.2, t=0.0, sale=0.2)


def construir(l):
    rng = random.Random(SEMILLA)
    X, Z = D.ANCHO_X, D.ANCHO_Z
    # --- el suelo: roca que no se rompe, tierra y lo de cada zona -------------------------------------------
    l.caja(0, 0, 0, X, D.ROCA_Y, Z, "roca_base")
    l.caja(0, D.ROCA_Y, 0, X, 0.8, Z, "suelo_tierra")
    l.caja(0, 0.8, 0, X, GY, Z, "acera")
    px0, pz0, px1, pz1 = D.PATIO
    l.caja(px0, 0.8, pz0, px1, GY, pz1, "adoquin")
    sx0, sz0, sx1, sz1 = D.SALA
    l.caja(sx0, 0.8, sz0, sx1, GY, sz1, "baldosa_int_suelo")
    nx0, nz0, nx1, nz1 = D.NAVE
    l.caja(nx0, 0.8, nz0, nx1, GY, nz1, "asfalto")

    # --- los muros ------------------------------------------------------------------------------------------
    # el recinto (tapia baja) y la nave (alta), muros de tres capas
    P.cascaron(l, D.RECINTO, GY, GY + D.ALTO_TAPIA, "revoque_arena")
    P.cascaron(l, (25.2, 0.0, 38.4, 28.8), GY, GY + D.ALTO_NAVE, "revoque_crema")
    P.esquinas(l, (25.2, 0.0, 38.4, 28.8), GY, GY + D.ALTO_NAVE, mat="sillar")
    # W1: patio | sala, con el TAPIADO en medio
    muro_capas(l, *[D.W1[0], D.W1[1], D.W1[2], D.W1[3]], GY, GY + D.ALTO_TAPIA, a="revoque_arena", b="revoque_int")
    # (el TAPIADO del tutorial viejo se quito: W1 es ahora la tapia del este del patio, entera)
    # W4: patio | porche
    muro_capas(l, D.W4[0], D.W4[1], D.W4[2], D.W4[3], GY, GY + D.ALTO_TAPIA, a="revoque_arena", b="revoque_arena")
    # W3: sala | porche, con su puerta
    muro_capas(l, D.W3[0], D.W3[1], D.W3[2], D.W3[3], GY, GY + D.ALTO_TAPIA, a="revoque_int", b="revoque_arena")
    a, b = D.PUERTA_W3
    l.caja(a, GY, D.W3[1], b, GY + 2.6, D.W3[3], "ladrillo", hueco=True)
    l.caja(a - 0.4, GY + 2.6, D.W3[1], b + 0.4, GY + 3.0, D.W3[3], "hormigon_viga")
    # W2: sala y porche | nave (alto), con la puerta del porche
    muro_capas(l, D.W2[0], D.W2[1], D.W2[2], D.W2[3], GY, GY + D.ALTO_NAVE, a="revoque_int", b="revoque_int")
    a, b = D.PUERTA_W2
    l.caja(D.W2[0], GY, a, D.W2[2], GY + 2.8, b, "ladrillo", hueco=True)
    l.caja(D.W2[0], GY + 2.8, a - 0.4, D.W2[2], GY + 3.2, b + 0.4, "hormigon_viga")
    # desconchones en las tapias del patio (sale el ladrillo): que se vea que esto ya ha visto golpes
    caras = P.caras(D.RECINTO)
    for lado in ("n", "o", "s"):
        c = caras[lado]
        # la cara de DENTRO del recinto: t = 0,6 desde fuera es la de dentro; los desconchones van por fuera
        P.desconchones(l, c, c.u0 + 1.0, min(c.u1, 12.0) - 1.0, GY + 0.4, GY + D.ALTO_TAPIA - 0.4, rng, 3)

    # --- 1 el patio ------------------------------------------------------------------------------------------
    cx, cz = D.CIRCULO
    for r0, r1, m in ((1.2, 1.0, "pintura_amarilla"),):
        for i in range(-6, 7):
            for k in range(-6, 7):
                d = (i * i + k * k) ** 0.5 * 0.2
                if r1 <= d < r0:
                    l.caja(cx + i * 0.2 - 0.1, GY - 0.2, cz + k * 0.2 - 0.1, cx + i * 0.2 + 0.1, GY, cz + k * 0.2 + 0.1, m)
    MOB.arbol(l, 2.2, 2.4, GY, rng, alto=4.2)
    MOB.arbol(l, 2.6, 25.4, GY, rng, alto=4.6)
    MOB.arbusto(l, 10.6, 1.8, GY, rng, r=0.6)
    MOB.arbusto(l, 10.8, 11.8, GY, rng, r=0.6, flores=("flor_amarilla", "flor_blanca"))
    MOB.banco(l, 1.4, 14.0, GY, eje="z", largo=1.8)
    # la pizarra junto al tapiado
    MOB.pizarra(l, 10.4, 4.0, GY, eje="z", texto=("ROMPE", "LA PARED"))
    numero(l, P.Cara("z", D.W1[0], -1, 0.6, 13.0, "o"), 3.6, GY + 2.8, "1")

    # --- 2-3 la sala del armero -----------------------------------------------------------------------------
    mx, mz = D.MESA_ARMA
    # el banco de trabajo: tablero de madera clara sobre dos caballetes
    l.caja(mx - 1.0, GY + 0.8, mz - 0.6, mx + 1.0, GY + 1.0, mz + 0.6, "madera_clara")
    for dx in (-0.8, 0.6):
        l.caja(mx + dx, GY, mz - 0.4, mx + dx + 0.2, GY + 0.8, mz + 0.4, "madera_viga")
    numero(l, P.Cara("x", D.SALA[1], 1, 12.6, 25.2, "s"), mx, GY + 2.8, "2")
    # la linea de tiro pintada en el suelo
    l.caja(D.LINEA_TIRO, GY - 0.2, 3.8, D.LINEA_TIRO + 0.2, GY, 12.4, "pintura_amarilla")
    # las dianas: tablero de madera clara con el centro rojo y blanco, sobre su poste
    x0, x1 = D.DIANAS_X
    for (zc,) in D.DIANAS:
        w = D.DIANA_ANCHO * 0.5
        l.caja(x0, GY, zc - 0.2, x1, GY + D.DIANA_Y[0], zc + 0.2, "madera_viga")
        l.caja(x0, GY + D.DIANA_Y[0], zc - w, x1, GY + D.DIANA_Y[1], zc + w, "madera_clara")
        l.caja(x0, GY + 1.0, zc - 0.4, x1, GY + 1.8, zc + 0.4, "cartel_crema")
        l.caja(x0, GY + 1.2, zc - 0.2, x1, GY + 1.6, zc + 0.2, "cartel_rojo")
    # la chapa de metal: aguanta mas
    (zc,) = D.CHAPA
    l.caja(x0, GY, zc - 0.2, x1, GY + D.DIANA_Y[0], zc + 0.2, "madera_viga")
    l.caja(x0, GY + D.DIANA_Y[0], zc - 0.5, x1, GY + D.DIANA_Y[1], zc + 0.5, "chapa_gris")
    # parapeto de sacos (ladrillo bajo) detras de las dianas
    l.caja(24.2, GY, 3.6, 25.2, GY + 1.0, 12.6, "ladrillo_viejo")
    numero(l, P.Cara("z", D.W2[0], -1, 0.0, 28.8, "o"), 8.4, GY + 3.6, "3")

    # --- 4 el porche ---------------------------------------------------------------------------------------
    lx0, lz0, lx1, lz1 = D.LOSA
    for (ccx, ccz) in D.COLUMNAS:
        h = D.COLUMNA_LADO * 0.5
        l.caja(ccx - h, GY, ccz - h, ccx + h, GY + D.LOSA_Y[0], ccz + h, "ladrillo")
    l.caja(lx0, GY + D.LOSA_Y[0], lz0, lx1, GY + D.LOSA_Y[1], lz1, "hormigon")
    l.caja(lx0, GY + D.LOSA_Y[1] - 0.2, lz0, lx1, GY + D.LOSA_Y[1], lz1, "tela_asfaltica")
    numero(l, P.Cara("z", D.W4[2], 1, 13.6, 28.8, "e"), 21.0, GY + 2.8, "4")
    # unas macetas y un banco: el porche de alguien
    MOB.maceta(l, 14.0, 15.0, GY, rng, grande=True)
    MOB.maceta(l, 23.6, 26.8, GY, rng, grande=True)

    # --- 5 la nave: el altillo, la viga y las pilas -------------------------------------------------------
    ax0, az0, ax1, az1 = D.ALTILLO
    l.caja(ax0, GY + D.ALTILLO_Y[0], az0, ax1, GY + D.ALTILLO_Y[1] - 0.2, az1, "hormigon")
    l.caja(ax0, GY + D.ALTILLO_Y[1] - 0.2, az0, ax1, GY + D.ALTILLO_Y[1], az1, "tarima")
    l.caja(ax0, GY, az1 - 0.4, ax0 + 0.4, GY + D.ALTILLO_Y[0], az1, "hormigon_viga")    # la columna de la esquina
    # la barandilla del altillo, salvo donde apoya la viga
    by = GY + D.ALTILLO_Y[1]
    for z0, z1 in ((az0, 4.6), (7.4, az1)):
        l.caja(ax0, by + 0.8, z0, ax0 + 0.2, by + 1.0, z1, "hierro")
        z = z0
        while z < z1 - 0.1:
            l.caja(ax0, by, z, ax0 + 0.2, by + 0.8, z + 0.2, "hierro")
            z += 0.8
    for (p0, q0, p1, q1) in D.PILAS:
        l.caja(p0, GY, q0, p1, GY + D.PILA_ALTO, q1, "ladrillo")
    numero(l, P.Cara("x", 0.6, 1, 25.8, 37.8, "s"), 29.2, GY + 5.2, "5")
    # cerchas de acero de muro a muro: la nave perdio el tejado
    for z in (4.2, 10.2, 16.2, 22.2):
        l.caja(25.8, GY + 5.8, z, 37.8, GY + 6.2, z + 0.2, "acero")

    # --- 6 trepar: la pasarela, las cajas y el mirador -----------------------------------------------------
    qx0, qz0, qx1, qz1 = D.PASARELA
    l.caja(qx0, GY + D.ALTILLO_Y[0], qz0, qx1, GY + D.ALTILLO_Y[1] - 0.2, qz1, "hormigon")
    l.caja(qx0, GY + D.ALTILLO_Y[1] - 0.2, qz0, qx1, GY + D.ALTILLO_Y[1], qz1, "tarima")
    l.caja(qx0, by + 0.8, qz0, qx0 + 0.2, by + 1.0, qz1, "hierro")
    z = qz0
    while z < qz1 - 0.1:
        l.caja(qx0, by, z, qx0 + 0.2, by + 0.8, z + 0.2, "hierro")
        z += 0.8
    cj0, cjz0, cj1, cjz1 = D.CAJAS
    for i, x in enumerate((cj0, cj0 + 0.8, cj0 + 1.6)):
        l.caja(x, by, cjz0, x + 0.8, by + D.CAJAS_ALTO, cjz1, "tablas")
        l.caja(x, by + D.CAJAS_ALTO - 0.2, cjz0, x + 0.8, by + D.CAJAS_ALTO, cjz1, "madera_viga")
    rx0, rz0, rx1, rz1 = D.MIRADOR
    l.caja(rx0, GY, rz0, rx1, GY + D.MIRADOR_Y, rz1, "ladrillo")
    l.caja(rx0, GY, rz0, rx0 + 0.2, GY + D.MIRADOR_Y, rz1, "revoque_crema")
    l.caja(rx0, GY, rz0, rx1, GY + D.MIRADOR_Y, rz0 + 0.2, "revoque_crema")
    l.caja(rx0, GY, rz1 - 0.2, rx1, GY + D.MIRADOR_Y, rz1, "revoque_crema")
    l.caja(rx0, GY + D.MIRADOR_Y - 0.2, rz0, rx1, GY + D.MIRADOR_Y, rz1, "tarima")
    # su antepecho hacia el deposito (a la cintura: la granada pasa por encima)
    l.caja(rx0, GY + D.MIRADOR_Y, rz1 - 0.2, rx1, GY + D.MIRADOR_Y + 0.6, rz1, "ladrillo")
    l.caja(rx0, GY + D.MIRADOR_Y, rz0 + 0.8, rx0 + 0.2, GY + D.MIRADOR_Y + 0.6, rz1, "ladrillo")
    numero(l, P.Cara("x", rz0, -1, rx0, rx1, "n"), 36.6, GY + 4.4, "6")

    # --- 7 el deposito de agua ------------------------------------------------------------------------------
    for (pxc, pzc) in D.DEPOSITO_PATAS:
        h = D.PATA_LADO * 0.5
        # PATAS DE MADERA (de hormigon, 170 de fuerza contra los 200 de la granada, solo se raspaban: medido)
        l.caja(pxc - h, GY, pzc - h, pxc + h, GY + D.PATA_ALTO, pzc + h, "madera_viga")
    dx0, dz0, dx1, dz1 = D.DEPOSITO
    y0, y1 = GY + D.DEPOSITO_Y[0], GY + D.DEPOSITO_Y[1]
    l.caja(dx0, y0, dz0, dx1, y1, dz1, "tablas")
    l.caja(dx0 + 0.2, y0 + 0.2, dz0 + 0.2, dx1 - 0.2, y1 - 0.2, dz1 - 0.2, "tablas", hueco=True)
    for yb in (y0 + 0.4, y1 - 0.8):
        l.caja(dx0 - 0.2, yb, dz0 - 0.2, dx1 + 0.2, yb + 0.2, dz1 + 0.2, "madera_viga")
    numero(l, P.Cara("x", dz0, -1, dx0, dx1, "n"), (dx0 + dx1) * 0.5, y1 - 0.4, "7")
    # la marca de peligro en el suelo alrededor del deposito
    for (a0, b0, a1, b1) in ((26.8, 20.4, 31.6, 20.6), (26.8, 25.0, 31.6, 25.2), (26.8, 20.4, 27.0, 25.2), (31.4, 20.4, 31.6, 25.2)):
        l.caja(a0, GY - 0.2, b0, a1, GY, b1, "pintura_amarilla")


def json_tutorial(id_de=None):
    v = lambda x, y, z: [round(x, 2), round(y, 2), round(z, 2)]
    by = GY + D.ALTILLO_Y[1]
    w = D.DIANA_ANCHO * 0.5
    return {
        "nombre": "TUTORIAL",
        # los RETOS se construyen en juego delante del PUESTO (tutorial.gd), con estos materiales de la paleta
        "puesto": v(*D.PUESTO),
        "mats": {k: int(id_de[k]) for k in ("ladrillo", "hormigon", "tablas", "madera_viga", "pintura_amarilla",
                                            "revoque_arena", "acero", "adoquin", "suelo_tierra")
                 if id_de and k in id_de},
        "spawn": v(D.SPAWN[0], GY, D.SPAWN[2]),
        "circulo": v(D.CIRCULO[0], GY, D.CIRCULO[1]),
        "tapiado": {"min": v(D.W1[0], GY, D.TAPIADO[1]), "max": v(D.W1[2], GY + D.TAPIADO_ALTO, D.TAPIADO[3])},
        "arma": {"pos": v(*D.ARMA), "id": "smg_9mm"},
        "dianas": [{"min": v(D.DIANAS_X[0], GY + D.DIANA_Y[0], zc - w), "max": v(D.DIANAS_X[1], GY + D.DIANA_Y[1], zc + w)}
                   for (zc,) in D.DIANAS],
        "chapa": {"min": v(D.DIANAS_X[0], GY + D.DIANA_Y[0], D.CHAPA[0] - 0.5),
                  "max": v(D.DIANAS_X[1], GY + D.DIANA_Y[1], D.CHAPA[0] + 0.5)},
        "linea_tiro": v(D.LINEA_TIRO - 0.6, GY, 7.4),
        "losa": {"min": v(D.LOSA[0], GY + D.LOSA_Y[0], D.LOSA[1]), "max": v(D.LOSA[2], GY + D.LOSA_Y[1], D.LOSA[3])},
        "columnas": [v(cx, GY + 1.2, cz) for (cx, cz) in D.COLUMNAS],
        "viga": {"bisagra": v(*D.BISAGRA), "largo": D.VIGA_LARGO, "ancho": D.VIGA_ANCHO, "suelo": GY,
                 "pilas": [[v(p0, GY, q0), v(p1, GY + D.PILA_ALTO, q1)] for (p0, q0, p1, q1) in D.PILAS]},
        "altillo": {"min": v(D.ALTILLO[0], by - 0.3, D.ALTILLO[1]), "max": v(D.ALTILLO[2], by + 1.6, D.ALTILLO[3])},
        "cajas": {"min": v(D.CAJAS[0], by, D.CAJAS[1]), "max": v(D.CAJAS[2], by + D.CAJAS_ALTO, D.CAJAS[3])},
        "mirador": {"min": v(D.MIRADOR[0], GY + D.MIRADOR_Y - 0.3, D.MIRADOR[1]),
                    "max": v(D.MIRADOR[2], GY + D.MIRADOR_Y + 1.6, D.MIRADOR[3])},
        "deposito": {"min": v(D.DEPOSITO[0], GY + D.DEPOSITO_Y[0], D.DEPOSITO[1]),
                     "max": v(D.DEPOSITO[2], GY + D.DEPOSITO_Y[1], D.DEPOSITO[3])},
        "patas": [v(px, GY + 1.0, pz) for (px, pz) in D.DEPOSITO_PATAS],
        "source": "tools/generar_mapa_tutorial.py",
    }


def main():
    t0 = time.time()
    MAT.registrar()
    print("== %s: %.1f x %.1f x %.1f m" % (NOMBRE, D.ANCHO_X, D.ALTO_MUNDO, D.ANCHO_Z))
    lz = L.Lienzo()
    construir(lz)
    print("  %d primitivas" % len(lz.prims))
    usados = {p[2] for p in lz.prims}
    entradas, id_de, nvar, codigo, desp = pintura.construir_paleta(usados, G.FISICA, G.POR_NOMBRE)
    print("  paleta: %d materiales, %d colores (de 240)" % (len(id_de), len(entradas)))
    VAR = raster.textura_variacion(SEMILLA)
    dims_lo = ((D.CHUNKS[0] + 1) // 2, (D.CHUNKS[1] + 1) // 2, (D.CHUNKS[2] + 1) // 2)
    lo_todo = np.zeros((dims_lo[0] * 32, dims_lo[1] * 32, dims_lo[2] * 32), np.uint8)

    def guardar(tx, tz, vh, vl):
        B = vl.shape[0]
        x0, z0 = tx * B, tz * B
        x1, z1 = min(x0 + B, lo_todo.shape[0]), min(z0 + B, lo_todo.shape[2])
        if x1 > x0 and z1 > z0:
            lo_todo[x0:x1, :vl.shape[1], z0:z1] = vl[:x1 - x0, :, :z1 - z0]

    hi, lo, dims_lo, s_hi, s_lo, alto_hi, alto_lo = pintura.rasterizar(lz.prims, id_de, nvar, codigo, desp, VAR,
                                                                         D.CHUNKS, D.VOXEL, guardar)
    base = os.path.join(MAPAS, NOMBRE)
    spawns = [(D.SPAWN[0], D.SPAWN[1] + 0.1, D.SPAWN[2], D.SPAWN[3])]
    t_hi = G.escribir_vxmap(base + ".vxmap", D.VOXEL, D.CHUNKS, entradas, spawns, hi)
    t_lo = G.escribir_vxmap(base + "_lo.vxmap", D.VOXEL * 2, dims_lo, entradas, spawns, lo)
    with open(base + ".tutorial.json", "w", encoding="utf-8") as f:
        json.dump(json_tutorial(id_de), f, ensure_ascii=False, indent=1)
    print("== escrito %s.vxmap: %.2f MB, %d chunks, %d voxels" % (NOMBRE, t_hi / 1048576, len(hi), s_hi))
    print("== escrito %s_lo.vxmap: %.2f MB, %d chunks, %d voxels" % (NOMBRE, t_lo / 1048576, len(lo), s_lo))

    # --- comprobaciones en el de 20 cm ------------------------------------------------------------------------
    import analisis
    ancla = {16 + i for i, m in enumerate(entradas) if m[5] & 1}
    flo = analisis.flotantes(lo_todo, ancla)
    print("== FLOTANTES (20 cm): %d conjuntos sin ancla, %d voxels" % (len(flo), sum(f[0] for f in flo)))
    for f_ in flo[:10]:
        print("   %6d voxels  centro %s  caja %s" % (f_[0], f_[1], f_[2]))
    nav = analisis.Nav(lo_todo)
    n = nav.recorrer([(D.SPAWN[0], GY, D.SPAWN[2])])
    print("== NAVEGACION desde la salida (con el tapiado puesto): %d celdas" % n)
    for nombre, p in (("circulo", (D.CIRCULO[0], GY, D.CIRCULO[1])), ("sala (no deberia, tapiado)", (15.6, GY, 6.0)),
                      ("altillo (no deberia)", (35.0, GY + 2.6, 6.0))):
        print("   %-28s %s" % (nombre, "alcanzable" if nav.alcanzable(*p) else "NO SE LLEGA"))
    print("== hecho en %.1f s" % (time.time() - t0))


if __name__ == "__main__":
    main()
