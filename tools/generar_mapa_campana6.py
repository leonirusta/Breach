#!/usr/bin/env python3
"""GENERADOR DEL EPISODIO 6 DE LA CAMPAÑA: "LA CUMBRE" (campana_cumbre).

Construye con tools/mapa_campana6/ (disposicion.py: el recorrido y los doce puzzles; cumbre.py: lo que hay) y reutiliza
las piezas del episodio 4 (tools/mapa_campana4/presa.py) y el kit de siempre. De dia y nevando ("hora": "nevada");
agua bajo el hielo del lago. Materiales nuevos ANCLADOS (nieve, hielo, roca_nevada: el analizador no los tira).

  godot/maps/campana_cumbre.vxmap / _lo.vxmap, .lights.json, .pve.json, .agua.json y .campana.json

Dos pasadas (validacion con los puzzles resueltos y el mapa de verdad). --solo-validar, --sin-validar, --atajos.
"""
import json, math, os, random, sys, time

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(AQUI, "mapa_pve"))
sys.path.insert(0, os.path.join(AQUI, "mapa_campana"))
sys.path.insert(0, os.path.join(AQUI, "mapa_campana4"))
sys.path.insert(0, os.path.join(AQUI, "mapa_campana6"))      # PRIMERO: su disposicion manda
import disposicion as D      # noqa: E402  (la del episodio 6)
import lienzo as L           # noqa: E402
import raster                # noqa: E402
import generar_mapa_pve as G  # noqa: E402
import cumbre as C           # noqa: E402

RAIZ = os.path.dirname(AQUI)
MAPAS = os.path.join(RAIZ, "godot", "maps")
NOMBRE = "campana_cumbre"
SEMILLA = 20260930
MAX_LUCES = 64
MAX_SPAWNS = 14


def paleta_usada(prims):
    usados = {p[2] for p in prims}
    todos = dict(L.MATERIALES)
    for k in list(L.MATERIALES):
        if k not in usados:
            del L.MATERIALES[k]
    try:
        return G.construir_paleta()
    finally:
        L.MATERIALES.clear()
        L.MATERIALES.update(todos)


def lienzo(validacion):
    lz = L.Lienzo()
    C.construir(lz, random.Random(SEMILLA), validacion)
    return lz


def preparar(lz, id_de):
    dims_vox = (D.CHUNKS[0] * 32, D.CHUNKS[1] * 32, D.CHUNKS[2] * 32)
    lista, cajas = raster.preparar(lz.prims, D.VOXEL, dims_vox, id_de)
    alto = int(min(dims_vox[1], max(128, math.ceil(int(cajas[:, 3].max()) / 64.0) * 64)))
    return alto, lista, cajas


def r2(v):
    return [round(float(c), 2) for c in v]


def json_campana(id_de):
    """Todo lo que campana6.gd necesita saber de cada puzzle (en metros)."""
    G = D.G
    M = D.M
    muros = [
        [-0.4, M - 1.0, 4.0, 0.2, M + 8.0, 12.0],             # el borde oeste de la meseta (el hueco del cable lo pone el juego)
        [-0.4, M - 1.0, 20.0, 0.2, M + 8.0, 84.0],
    ]
    gruesas = sorted([list(cf) for cf in D.GRUESAS])
    return {
        "nombre": "LA CUMBRE",
        "capitulo": "Episodio 6 · Del lago helado al teleférico",
        "episodio": 6,
        "requiere": "campana_base",
        "script": "res://scripts/campana6.gd",
        "hora": "nevada",
        "ruta": [[round(x, 2), round(y, 2), round(z, 2), n] for x, y, z, n in D.RUTA],
        "salida": list(D.SPAWN_JUGADOR),
        "municion_fija": [[46.0, G, 146.0], [124.0, G, 146.0], [152.0, G, 112.0], [146.0, G, 80.0], [183.0, 6.0, 12.0],
                          [104.0, M, 12.0], [86.0, M, 55.0], [58.5, M, 76.0], [24.0, M, 76.0], [30.0, M, 32.0], [40.0, M, 20.0]],
        "calle_desde": "orilla este",
        "vehiculo": "TELEFÉRICO",
        "muros": [r2(m) for m in muros],
        "mat": {k: int(id_de[k]) for k in ("nieve", "nieve_dura", "roca_suelta", "hielo")},
        "refugio": {"rect": list(D.REFUGIO), "puerta_entrada": list(D.REFUGIO_PUERTA_N),
                    "puerta_salida": list(D.REFUGIO_PUERTA_O), "suelo": M, "salida_cara": "oeste"},
        "refugio_salida_texto": "Salid por la puerta OESTE: el LABORATORIO del observatorio",
        "avion": {"z": D.AVION_Z, "y": G},
        "p01_hielo": {"lago": list(D.LAGO), "placa": D.PLACA, "cols": D.COLS, "filas": D.FILAS, "gruesas": gruesas,
                      "fino_y": D.FINO_Y, "agua": D.AGUA_LAGO, "aguanta_s": 1.3},
        "p02_tank": {"mitad": r2(D.MITAD_LAGO), "salida": r2(D.TANK_SALIDA)},
        "p03_grisu": {"caja": list(D.GRISU), "ventilador": r2(D.VENTILADOR), "mando": r2(D.MANDO_VENTILADOR),
                      "puerta": [D.PUERTA_MINA[0], G, D.PUERTA_MINA[1], D.PUERTA_MINA[2], G + 3.2, D.PUERTA_MINA[3]],
                      "bombona": r2(D.BOMBONA_GRISU), "tramos": [list(t) for t in D.MINA], "alto": D.MINA_ALTO,
                      "arranque_s": 12.0, "camara": [140.0, 10.0, 70.0]},
        "p04_quitanieves": {"ruta": [list(p) for p in D.QUITANIEVES_RUTA], "v": D.QUITANIEVES_V,
                            "ventisqueros": [list(v) for v in D.VENTISQUEROS], "alto": D.VENTISQUERO_ALTO,
                            "curva_y": D.Y_CURVA, "derrumbe_x": D.DERRUMBE[2] + 2.2},
        "p05_robot": {"celdas": [list(c) for c in D.ROBOT_CELDAS], "meta": list(D.ROBOT_META),
                      "consola": [D.CONSOLA_ROBOT[0], D.camino_y(*D.CONSOLA_ROBOT), D.CONSOLA_ROBOT[1]],
                      "derrumbe": [D.DERRUMBE[0], 6.5, D.DERRUMBE[1], D.DERRUMBE[2], 12.5, D.DERRUMBE[3]],
                      "camara": [166.0, 12.0, 22.0]},
        "p06_alud": {"cornisa": list(D.CORNISA), "caja": list(D.CORNISA_CAJA), "bidones": [r2(b) for b in D.BIDONES_CORNISA],
                     "relleno": list(D.RELLENO), "relleno_y": D.RELLENO_Y, "umbral": 0.72,
                     "garganta": list(D.GARGANTA), "garganta_y": D.GARGANTA_Y, "camara": [96.0, 16.0, 30.0]},
        "p07_ventisca": {"zona": list(D.VENTISCA), "grietas": [list(g) for g in D.GRIETAS],
                         "falsos": [[list(f) for f in fs] for fs in D.PUENTES_FALSOS], "salvado": [r2(s) for s in D.SALVADO_GRIETA],
                         "braseros": [r2(b) for b in D.BRASEROS], "frio_s": 45.0},
        "p08_campanas": {"campanas": [r2(c) for c in D.CAMPANAS], "cuerda": r2(D.CUERDA_CAMPANA),
                         "porton": [D.PORTON_MON[0], M, D.MONASTERIO[1] - 0.2, D.PORTON_MON[1], M + 4.2, D.MONASTERIO[1] + 1.0],
                         "rondas": [3, 4, 5]},
        "p09_laseres": {"pasillo": list(D.PASILLO), "x": D.LASERES_X, "panel": r2(D.PANEL_LASERES), "y": M,
                        "inicio": [58.5, M, 72.0]},
        "p10_espejos": {"patio": list(D.PATIO_ESPEJOS), "emisor": list(D.EMISOR), "mando": r2(D.MANDO_EMISOR),
                        "espejos": [list(e) for e in D.ESPEJOS], "inicio": D.ESPEJOS_INICIO, "y": D.HAZ_Y,
                        "receptor": list(D.RECEPTOR),
                        "verja": [D.VERJA_ESTACION[0], M, D.MURO_ESTACION_Z[0] - 0.1, D.VERJA_ESTACION[1], M + 4.2, D.MURO_ESTACION_Z[1] + 0.1]},
        "p11_soplete": {"soplete": r2(D.SOPLETE), "muro": [D.MURO_HIELO[0], M, D.MURO_HIELO[1], D.MURO_HIELO[2], M + D.MURO_HIELO_ALTO + 0.6, D.MURO_HIELO[3]],
                        "hielos": [[h[0], M, h[1], h[2], M + D.HIELO_ALTO + 0.5, h[3]] for h in D.HIELOS], "umbral": 0.3},
        "p12_teleferico": {"rueda": list(D.RUEDA), "cabina": list(D.CABINA), "cable_y": D.CABLE_Y,
                           "mando": r2(D.MANDO_TELEFERICO), "espera_s": 60.0, "depositos": [[d[0], M, d[1]] for d in D.DEPOSITOS],
                           "anden": list(D.ANDEN)},
        "cine_final": {"camara": [30.0, M + 9.0, 40.0]},
        # la entrada: el avion aterriza de panza en el lago y se parte (campana6.gd lo mueve a la vez)
        "cine_entrada": {
            "puntos": [[86.0, 16.0, 118.0], [74.0, 9.0, 126.0], [62.0, 6.5, 131.0], [58.0, 5.2, 134.0]],
            "mira": [[160.0, 22.0, 142.0], [104.0, 5.0, 142.0], [48.0, 3.5, 142.0], [32.0, 3.5, 142.0]],
            "titulo": "LA CUMBRE", "sub": "Episodio 6 · Del lago helado al teleférico"},
        "mensaje_inicio": "LA CUMBRE · el avión ha caído en un lago helado",
        "texto_inicio": "Cruzad el LAGO por el hielo BLANCO: el oscuro no aguanta",
    }


def main():
    args = sys.argv[1:]
    t0 = time.time()
    G.registrar_materiales()
    # los materiales ANCLADOS de la nieve y el hielo (fuerza, densidad, flags, soporte, masa): el analizador estructural
    # no los tira nunca; la nieve blanda (40) se deshace a tiros, la dura y el hielo grueso no
    G.POR_NOMBRE.update({"nieve": (40, 400, 1, 6, 3), "nieve_dura": (200, 600, 1, 16, 4), "hielo": (200, 900, 1, 16, 6),
                         "hielo_fino": (60, 900, 1, 16, 6), "hielo_muro": (90, 900, 1, 16, 6)})
    for k, v in C.MATERIALES.items():
        L.MATERIALES[k] = v
    print("== %s: %.1f x %.1f x %.1f m, voxel %.2f m" % (NOMBRE, D.ANCHO_X, D.ALTO_MUNDO, D.ANCHO_Z, D.VOXEL))
    lz = lienzo(False)
    print("  %d primitivas, %d luces (%.1f s)" % (len(lz.prims), len(lz.luces), time.time() - t0))
    # la paleta sale de las DOS variantes (la de validacion puede sortear otros materiales)
    materiales, id_de, nvar, desp = paleta_usada(lz.prims + lienzo(True).prims)
    raster.PATRON = G.PATRON.copy()
    print("  paleta: %d colores, %d materiales con dibujo" % (len(materiales), int((raster.PATRON > 0).sum())))
    VAR = raster.textura_variacion(SEMILLA)
    sp = D.SPAWN_JUGADOR
    spawn_jug = (sp[0], sp[1] + 0.1, sp[2], 0.0)
    pistas, ruta_ok = [], []
    val = None
    candidatos = [(p[0], p[1], p[2]) for p in lz.puntos]
    if "--sin-validar" not in args:
        import validar
        lzv = lienzo(True)
        alto_v, lista_v, cajas_v = preparar(lzv, id_de)
        val = validar.Validador(alto_v, materiales)
        print("  PASADA 1: validacion (los puzzles, resueltos)")
        raster.rasterizar_mapa(lista_v, cajas_v, D.VOXEL, D.CHUNKS, alto_v, nvar, desp, VAR, val.al_terminar)
        val.navegacion(spawn_jug)
        pistas = val.pistas(candidatos)
        extra = [(D.MANDO_VENTILADOR[0], D.G, D.MANDO_VENTILADOR[2], "mando del ventilador"),
                 (D.CONSOLA_ROBOT[0] - 0.4, D.camino_y(*D.CONSOLA_ROBOT), D.CONSOLA_ROBOT[1] - 0.6, "consola del robot"),
                 (D.CUERDA_CAMPANA[0], D.M, D.CUERDA_CAMPANA[2] - 0.8, "cuerda de la campana"),
                 (D.PANEL_LASERES[0] + 0.8, D.M, D.PANEL_LASERES[2], "panel de los laseres"),
                 (D.MANDO_EMISOR[0], D.M, D.MANDO_EMISOR[2] + 0.8, "mando del laser"),
                 (D.SOPLETE[0], D.M, D.SOPLETE[2] - 1.4, "soplete"),
                 (D.MANDO_TELEFERICO[0], D.M, D.MANDO_TELEFERICO[2], "mando del teleferico")]
        extra += [(e[0], D.M, e[1] + 1.2, "espejo %d" % (i + 1)) for i, e in enumerate(D.ESPEJOS)]
        extra += [(b[0] + 1.2, D.M, b[2], "brasero %d" % (i + 1)) for i, b in enumerate(D.BRASEROS)]
        for x, y, z, nombre in D.RUTA + extra:
            ok, alt = val.punto_alcanzable(x, y, z)
            ruta_ok.append((nombre, ok))
            print("  ruta %-28s %s%s" % (nombre, "OK" if ok else "NO SE LLEGA", "" if alt is None else "  (suelo a %.2f)" % alt))
    if "--solo-validar" in args:
        malos = [n for n, ok in ruta_ok if not ok]
        print("== RECORRIDO: %s" % ("COMPLETO (se llega a todo)" if not malos else "FALTA LLEGAR A: " + ", ".join(malos)))
        return
    print("  PASADA 2: el mapa")
    alto, lista, cajas = preparar(lz, id_de)
    val2 = None
    if "--atajos" in args:
        import validar
        val2 = validar.Validador(alto, materiales)
    hi, lo, dims_lo, s_hi, s_lo = raster.rasterizar_mapa(lista, cajas, D.VOXEL, D.CHUNKS, alto, nvar, desp, VAR,
                                                         val2.al_terminar if val2 else None)
    if val2:
        # ATAJOS: en el mapa DE VERDAD (puzzles sin resolver) desde el principio de cada tramo, a que puntos de la
        # ruta se llega andando. Lo que haya mas alla del puzzle que cierra el tramo es un atajo.
        # (Las puertas, rejas y demas son objetos del juego: aqui no cuentan. Solo los cierres de voxels.)
        nombres = [r[3] for r in D.RUTA]
        for desde in ("avion", "patio de la mina", "curva", "tras el derrumbe", "puente de nieve", "refugio", "patio de los espejos", "estacion"):
            i = nombres.index(desde)
            x, y, z, _n = D.RUTA[i]
            val2.navegacion((x, y + 0.1, z, 0.0))
            ok = [n for (xx, yy, zz, n) in D.RUTA if val2.punto_alcanzable(xx, yy, zz)[0]]
            print("  ATAJOS desde %-20s -> %s" % (desde, ", ".join(ok)))
            if desde == "avion" and "--atajos-detalle" in args:
                cel = sorted(k for k in val2._visit if 36.0 <= (k[0] + 0.5) * 0.8 <= 62.0)
                for k in cel[:400]:
                    print("    celda x %.1f z %.1f y %.1f" % ((k[0] + 0.5) * 0.8, (k[1] + 0.5) * 0.8, (k[2] + 1) * 0.1))
    base = os.path.join(MAPAS, NOMBRE)
    # sin pistas dentro del refugio, en el agua, en el barranco, en el caz ni en el pozo
    pistas = [p for p in pistas if not D.dentro(p[0], p[2], D.REFUGIO, 1.0) and not D.dentro(p[0], p[2], D.LAGO, 0.3)
              and not D.dentro(p[0], p[2], D.GARGANTA, 0.5) and not D.dentro(p[0], p[2], (128.0, 83.0, 160.0, 105.0), 0.0)
              and p[1] > 2.0]
    spawns = [spawn_jug] + [(x, y + 0.1, z, 0.0) for x, y, z in pistas[:MAX_SPAWNS - 1]]
    t_hi = G.escribir_vxmap(base + ".vxmap", D.VOXEL, D.CHUNKS, materiales, spawns, hi)
    t_lo = G.escribir_vxmap(base + "_lo.vxmap", D.VOXEL * 2, dims_lo, materiales, spawns, lo)
    luces = []
    for entrada in lz.luces[:MAX_LUCES]:
        x, y, z, col, e, a = entrada[:6]
        d = {"pos": [round(x, 2), round(y, 2), round(z, 2)], "color": [round(c / 255.0, 4) for c in col],
             "energy": round(float(e) * 1.4, 2), "range": round(float(a) * 1.3, 2)}
        if len(entrada) > 7 and entrada[6] is not None:
            d["dir"] = [round(float(c), 3) for c in entrada[6]]
            d["cono"] = round(float(entrada[7]), 1)
        luces.append(d)
    with open(base + ".lights.json", "w", encoding="utf-8") as f:
        json.dump({"cell": 1.5, "lights": luces, "source": "tools/generar_mapa_campana6.py"}, f, separators=(",", ":"))
    with open(base + ".pve.json", "w", encoding="utf-8") as f:
        json.dump({"criaturas": [list(p) for p in pistas], "spawn_jugador": list(D.SPAWN_JUGADOR)}, f, indent=1)
    # EL AGUA: embalse, rio, caz, arroyo del barranco y el pozo de la central (el juego lo vacia)
    agua = {"cuerpos": [
        {"y": D.AGUA_LAGO, "rect": list(D.LAGO)},
    ], "source": "tools/generar_mapa_campana6.py"}
    with open(base + ".agua.json", "w", encoding="utf-8") as f:
        json.dump(agua, f, indent=1)
    with open(base + ".campana.json", "w", encoding="utf-8") as f:
        json.dump(json_campana(id_de), f, ensure_ascii=False, indent=1)
    print("== escrito %s.vxmap: %.2f MB, %d chunks, %d voxels solidos" % (NOMBRE, t_hi / 1048576, len(hi), s_hi))
    print("== escrito %s_lo.vxmap: %.2f MB, %d chunks" % (NOMBRE, t_lo / 1048576, len(lo)))
    print("== %d luces, %d pistas de salida" % (len(luces), len(pistas)))
    if val:
        malos = [n for n, ok in ruta_ok if not ok]
        print("== RECORRIDO: %s" % ("COMPLETO (se llega a todo)" if not malos else "FALTA LLEGAR A: " + ", ".join(malos)))
    print("== hecho en %.1f s" % (time.time() - t0))


if __name__ == "__main__":
    main()
