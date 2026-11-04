#!/usr/bin/env python3
"""GENERADOR DEL EPISODIO 7 DE LA CAMPAÑA: "EL PARQUE" (campana_parque).

Construye con tools/mapa_campana7/ (disposicion.py: el recorrido, los diez puzzles y el laberinto con semilla;
parque.py: lo que hay) y reutiliza las piezas del episodio 4 (tools/mapa_campana4/presa.py) y el kit de siempre.
De noche y con neones; agua en el lago.

  godot/maps/campana_parque.vxmap / _lo.vxmap, .lights.json, .pve.json, .agua.json y .campana.json

Dos pasadas (validacion con los puzzles resueltos y el mapa de verdad). --solo-validar, --sin-validar, --atajos.
"""
import json, math, os, random, sys, time

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(AQUI, "mapa_pve"))
sys.path.insert(0, os.path.join(AQUI, "mapa_campana"))
sys.path.insert(0, os.path.join(AQUI, "mapa_campana4"))
sys.path.insert(0, os.path.join(AQUI, "mapa_campana7"))      # PRIMERO: su disposicion manda
import disposicion as D      # noqa: E402  (la del episodio 7)
import lienzo as L           # noqa: E402
import raster                # noqa: E402
import generar_mapa_pve as G  # noqa: E402
import parque as C           # noqa: E402

RAIZ = os.path.dirname(AQUI)
MAPAS = os.path.join(RAIZ, "godot", "maps")
NOMBRE = "campana_parque"
SEMILLA = 20261001
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
    """Todo lo que campana7.gd necesita saber de cada puzzle (en metros)."""
    G = D.G
    return {
        "nombre": "EL PARQUE",
        "capitulo": "Episodio 7 · De la cabina estrellada al globo",
        "episodio": 7,
        "requiere": "campana_cumbre",
        "script": "res://scripts/campana7.gd",
        "hora": "anochecer",
        "ruta": [[round(x, 2), round(y, 2), round(z, 2), n] for x, y, z, n in D.RUTA],
        "salida": list(D.SPAWN_JUGADOR),
        "municion_fija": [[30.0, G, 144.0], [66.0, G, 120.0], [92.0, G, 126.0], [134.0, G, 128.0], [172.0, G, 80.0],
                          [150.0, G, 76.0], [136.0, D.PASARELA_Y, 70.0], [110.0, D.ANDEN_MR_Y, 14.0], [80.0, G, 30.0],
                          [60.0, D.TUNEL_SUELO, 46.0], [30.0, G, 50.0]],
        "calle_desde": "plaza",
        "vehiculo": "GLOBO",
        "muros": [],
        "mat": {k: int(id_de[k]) for k in ("tierra_monte", "negro_hollin")},
        "refugio": {"rect": list(D.REFUGIO), "puerta_entrada": list(D.REFUGIO_PUERTA_N),
                    "puerta_salida": list(D.REFUGIO_PUERTA_O), "suelo": G, "salida_cara": "oeste"},
        "refugio_salida_texto": "Salid por la puerta OESTE: el PABELLÓN de los autos de choque",
        "cabina": list(D.CABINA_ESTRELLADA), "estacion": list(D.ESTACION_TELEF),
        "p01_carpa": {"carpa": list(D.CARPA), "estacas": [list(e) for e in D.ESTACAS]},
        "p02_canon": {"canon": list(D.CANON), "aterrizaje": list(D.ATERRIZAJE), "porton": list(D.PORTON),
                      "palanca": list(D.PALANCA_PORTON)},
        "p03_galeria": {"caseta": list(D.GALERIA), "z": D.DIANAS_GALERIA_Z, "x": list(D.DIANAS_GALERIA_X),
                        "mostrador_z": D.MOSTRADOR_Z, "tiempo": 45.0, "dorados": 10, "fallos": 3,
                        "puerta": [D.AB_X[0], G, D.PUERTA_SERVICIO[0], D.AB_X[1], G + 3.6, D.PUERTA_SERVICIO[1]]},
        "p04_noria": {"centro": list(D.NORIA), "ancho": D.NORIA_ANCHO, "para_x": D.NORIA_PARA_X,
                      "barricada": list(D.BARRICADA), "camara": [112.0, 8.0, 106.0]},
        "p05_laberinto": {"setos": D.SETOS, "alto": D.SETO_ALTO, "bombona": list(D.BOMBONA_BUENA),
                          "camino": [list(q) for q in D.CAMINO_LAB], "lab": list(D.LAB), "cols": D.LAB_COLS, "filas": D.LAB_FILAS},
        "p06_fuegos": {"caseta": list(D.CASETA_FUEGOS), "cohetes": list(D.COHETES), "dormidos": list(D.DORMIDOS),
                       "orilla": [150.0, G, 47.0], "embarcadero": list(D.EMBARCADERO), "duracion": 50.0, "n": 30},
        "p07_choque": {"pabellon": list(D.PABELLON), "pista": list(D.PISTA_CHOQUE), "panel": list(D.PANEL_CORRIENTE),
                       "persiana": [D.PERSIANA_N[0], G, D.PABELLON[1] - 0.1, D.PERSIANA_N[1], G + 4.2, D.PABELLON[1] + 0.7],
                       "bajas": 30, "pasarela_y": D.PASARELA_Y},
        "p08_montana": {"via": [list(v) for v in D.VIA], "estacion": list(D.ESTACION_MR), "anden_y": D.ANDEN_MR_Y,
                        "choque": list(D.CHOQUE_MR)},
        "p09_torre": {"torre": list(D.TORRE), "alto": D.TORRE_ALTO, "panel": list(D.PANEL_TORRE), "agujero": list(D.AGUJERO_TORRE),
                      "tunel_suelo": D.TUNEL_SUELO, "subir_s": 20.0},
        "p10_globo": {"cesta": list(D.GLOBO), "amarras": [list(a) for a in D.AMARRAS], "hinchar_s": 60.0},
        "cine_final": {"camara": [40.0, 14.0, 60.0]},
        # la entrada: la cabina baja por el cable, el cable revienta y se estrella en la estacion
        "cine_entrada": {
            "puntos": [[44.0, 14.0, 132.0], [36.0, 9.0, 140.0], [30.0, 6.0, 146.0], [30.0, 5.0, 148.0]],
            "mira": [[-10.0, 28.0, 154.0], [10.0, 14.0, 154.0], [16.0, 5.0, 152.0], [16.0, 4.0, 150.0]],
            "titulo": "EL PARQUE", "sub": "Episodio 7 · De la cabina estrellada al globo"},
        "mensaje_inicio": "EL PARQUE · la cabina se ha estrellado junto a un parque de atracciones",
        "texto_inicio": "Id al CIRCO: su CAÑÓN puede mandaros por encima del muro del parque",
    }


def main():
    args = sys.argv[1:]
    t0 = time.time()
    G.registrar_materiales()
    # los SETOS del laberinto: anclados y duros a tiros (120): solo el fuego (el tallado del juego) los abre
    G.POR_NOMBRE.update({"seto": (120, 800, 1, 8, 5), "seto_seco": (120, 700, 1, 8, 5)})
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
        extra = [(D.PALANCA_PORTON[0] + 0.8, D.G, D.PALANCA_PORTON[2], "palanca del porton"),
                 ((D.GALERIA[0] + D.GALERIA[2]) / 2, D.G, D.MOSTRADOR_Z - 1.0, "mostrador de la galeria"),
                 (D.BOMBONA_BUENA[0] + 1.2, D.G, D.BOMBONA_BUENA[2] + 0.4, "bombona del laberinto"),
                 (D.CASETA_FUEGOS[0] - 3.4, D.G, D.CASETA_FUEGOS[2], "caseta de los fuegos"),
                 (D.PANEL_CORRIENTE[0] + 1.0, D.CABINA_Y, D.PANEL_CORRIENTE[2], "panel de la corriente"),
                 (D.PANEL_TORRE[0], D.G, D.PANEL_TORRE[2] + 1.0, "panel de la torre")]
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
        for desde in ("cabina", "plaza", "noria", "entrada del laberinto", "salida del laberinto", "pabellon", "choque", "torre"):
            i = nombres.index(desde)
            x, y, z, _n = D.RUTA[i]
            val2.navegacion((x, y + 0.1, z, 0.0))
            ok = [n for (xx, yy, zz, n) in D.RUTA if val2.punto_alcanzable(xx, yy, zz)[0]]
            print("  ATAJOS desde %-20s -> %s" % (desde, ", ".join(ok)))
            if desde == "cabina" and "--atajos-detalle" in args:
                cel = sorted(k for k in val2._visit if 36.0 <= (k[0] + 0.5) * 0.8 <= 62.0)
                for k in cel[:400]:
                    print("    celda x %.1f z %.1f y %.1f" % ((k[0] + 0.5) * 0.8, (k[1] + 0.5) * 0.8, (k[2] + 1) * 0.1))
    base = os.path.join(MAPAS, NOMBRE)
    # sin pistas dentro del refugio, en el agua, en el barranco, en el caz ni en el pozo
    pistas = [p for p in pistas if not D.dentro(p[0], p[2], D.REFUGIO, 1.0) and not D.dentro(p[0], p[2], D.LAGO, 0.3)
              and not D.dentro(p[0], p[2], D.ESTACION_TELEF, 2.0) and p[1] > 0.2]
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
        json.dump({"cell": 1.5, "lights": luces, "source": "tools/generar_mapa_campana7.py"}, f, separators=(",", ":"))
    with open(base + ".pve.json", "w", encoding="utf-8") as f:
        json.dump({"criaturas": [list(p) for p in pistas], "spawn_jugador": list(D.SPAWN_JUGADOR)}, f, indent=1)
    # EL AGUA: embalse, rio, caz, arroyo del barranco y el pozo de la central (el juego lo vacia)
    agua = {"cuerpos": [
        {"y": D.LAGO_AGUA, "rect": list(D.LAGO)},
    ], "source": "tools/generar_mapa_campana7.py"}
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
