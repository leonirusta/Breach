#!/usr/bin/env python3
"""GENERADOR DEL EPISODIO 5 DE LA CAMPAÑA: "LA BASE AEREA" (campana_base).

Construye con tools/mapa_campana5/ (disposicion.py: el recorrido y los doce puzzles; base.py: lo que hay) y reutiliza
las piezas del episodio 4 (tools/mapa_campana4/presa.py) y el kit de siempre. De noche y con tormenta
("hora": "tormenta"); agua en el canal y en los pozos del colector (el colector inundado es cosa del juego).

  godot/maps/campana_base.vxmap / _lo.vxmap, .lights.json, .pve.json, .agua.json y .campana.json

Dos pasadas (validacion con los puzzles resueltos y el mapa de verdad). --solo-validar, --sin-validar, --atajos.
"""
import json, math, os, random, sys, time

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(AQUI, "mapa_pve"))
sys.path.insert(0, os.path.join(AQUI, "mapa_campana"))
sys.path.insert(0, os.path.join(AQUI, "mapa_campana4"))
sys.path.insert(0, os.path.join(AQUI, "mapa_campana5"))      # PRIMERO: su disposicion manda
import disposicion as D      # noqa: E402  (la del episodio 5)
import lienzo as L           # noqa: E402
import raster                # noqa: E402
import generar_mapa_pve as G  # noqa: E402
import base as C             # noqa: E402

RAIZ = os.path.dirname(AQUI)
MAPAS = os.path.join(RAIZ, "godot", "maps")
NOMBRE = "campana_base"
SEMILLA = 20260929
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


def json_campana():
    """Todo lo que campana5.gd necesita saber de cada puzzle (en metros)."""
    G = D.G
    muros = [
        [59.6, G, 60.8, 60.2, G + 3.0, 63.0],                                     # la orilla norte, contra el macizo
        [0.8, D.TERRAPLEN_Y, 8.0, 1.2, D.TERRAPLEN_Y + 5.0, 14.0],                # el fondo del tunel
        [60.0, G, 73.4, 60.4, G + 3.0, 76.0],
    ]
    casa = D.CASA_BOMBAS
    return {
        "nombre": "LA BASE AÉREA",
        "capitulo": "Episodio 5 · De la vía volada al último avión",
        "episodio": 5,
        "requiere": "campana_presa",
        "script": "res://scripts/campana5.gd",
        "hora": "tormenta",
        "ruta": [[round(x, 2), round(y, 2), round(z, 2), n] for x, y, z, n in D.RUTA],
        "salida": list(D.SPAWN_JUGADOR),
        "municion_fija": [[24.0, D.MONTICULO_Y, 38.0], [70.0, G, 49.0], [104.0, G, 80.0], [140.0, G, 92.0],
                          [150.0, G, 118.0], [84.0, G, 120.0], [36.0, G, 126.0], [120.0, G, 146.0]],
        "calle_desde": "casa de bombas",
        "vehiculo": "AVIÓN",
        "muros": [r2(m) for m in muros],
        "refugio": {"rect": list(D.REFUGIO), "puerta_entrada": list(D.REFUGIO_PUERTA_N),
                    "puerta_salida": list(D.REFUGIO_PUERTA_O), "suelo": G, "salida_cara": "oeste"},
        "refugio_salida_texto": "Salid por la puerta OESTE: la VERJA de la valla interior tiene teclado",
        "tren": {"via_z": D.VIA_Z, "y": D.TERRAPLEN_Y, "loco_x": list(D.LOCO), "voladura": list(D.VOLADURA)},
        "p01_mortero": {"pos": r2(D.MORTERO), "cargas": D.CARGAS_M, "blanco": r2(D.BLANCO_MORTERO), "radio_blanco": 3.4,
                        "angulo0": 45.0, "paso": 5.0,
                        "hueco": r2([casa[0] - 0.3, G, 27.0, casa[0] + 0.8, G + 2.8, 31.0])},
        "p02_esfera": {"esfera": list(D.ESFERA), "valvula": r2(D.VALVULA_ESFERA), "fuga": r2(D.FUGA), "nube_s": 9.0,
                       "brecha": [D.BRECHA[0], G, D.MURO_SUR_Z - 0.3, D.BRECHA[1], G + 3.6, D.MURO_SUR_Z + 1.1]},
        "p03_puente": {"tablero": list(D.PUENTE), "y": D.PUENTE_Y, "anclajes": [r2(a) for a in D.ANCLAJES],
                       "verja": [D.VERJA[0], G, D.VALLA_Z - 0.15, D.VERJA[1], G + 3.4, D.VALLA_Z + 0.15],
                       "mando": r2(D.MANDO_VERJA), "abrir_s": 40.0, "canal": list(D.CANAL)},
        "p04_colector": {"tubo": list(D.COLECTOR), "techo": D.COLECTOR_TECHO, "agua": D.COLECTOR_AGUA,
                         "respiraderos": [list(r) for r in D.RESPIRADEROS], "pozos": [list(D.POZO_A), list(D.POZO_B)],
                         "aire_s": 14.0},
        "p05_demolicion": {"empalmes": [r2(e) for e in D.EMPALMES], "detonador": r2(D.DETONADOR),
                           "edificio": list(D.EDIFICIO), "plantas": D.EDIFICIO_PLANTAS, "piso": D.PISO,
                           "hueco": [D.HUECO_BASE[0], G, D.MURO_BASE_Z[0] - 0.3, D.HUECO_BASE[1], G + 4.0, D.MURO_BASE_Z[1] + 0.3],
                           "camara": [140.0, 16.0, 84.0]},
        "p06_baliza": {"mastil": [D.MASTIL[0], G + D.MASTIL[2] + 0.4, D.MASTIL[1]], "teclado": r2(D.TECLADO),
                       "verja": [D.VALLA_INTERIOR_X - 0.15, G, D.VERJA_INTERIOR[0], D.VALLA_INTERIOR_X + 0.15, G + 3.4, D.VERJA_INTERIOR[1]]},
        "p07_minas": {"campo": [104.0, 114.8, D.MINAS[2], D.MINAS[3]], "n": 46, "y": G},
        "p08_tanque": {"pos": r2(D.TANQUE), "puerta": [D.PUERTA_BLINDADA[0], G, D.PUERTA_BLINDADA[1], D.PUERTA_BLINDADA[2], G + 5.0, D.PUERTA_BLINDADA[3]],
                       "giro0": 90.0, "golpes": 3},
        "p09_radar": {"pos": r2(D.RADAR)},
        "p10_pista": {"cuadros": [r2(c) for c in D.CUADROS_PISTA], "pista": list(D.PISTA), "aguantar_s": 10.0},
        "p11_avion": {"para": list(D.AVION_PARA), "y": G, "heli": list(D.HELI_ESTRELLADO), "camara": [120.0, 12.0, 136.0]},
        "p12_camion": {"camion": list(D.CAMION), "vida": 900.0},
        "cine_final": {"camara": [40.0, 9.0, 140.0]},
        # la entrada: el tren sale del tunel, la via vuela delante de el y vuelca (campana5.gd lo mueve a la vez)
        "cine_entrada": {
            "puntos": [[8.0, 12.0, 30.0], [22.0, 9.5, 27.0], [36.0, 8.5, 26.0], [30.0, 8.0, 25.0]],
            "mira": [[2.0, 7.5, 11.0], [16.0, 6.5, 11.0], [44.0, 6.0, 12.0], [40.0, 5.0, 14.5]],
            "titulo": "LA BASE AÉREA", "sub": "Episodio 5 · De la vía volada al último avión"},
        "mensaje_inicio": "LA BASE AÉREA · la vía está volada: a la base, a pie",
        "texto_inicio": "Id al PUESTO DEL MORTERO del montículo",
    }


def main():
    args = sys.argv[1:]
    t0 = time.time()
    G.registrar_materiales()
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
        extra = [(D.VALVULA_ESFERA[0], D.G, D.VALVULA_ESFERA[2] - 0.8, "valvula de la esfera"),
                 (D.MANDO_VERJA[0], D.G, D.MANDO_VERJA[2] - 0.6, "mando de la verja"),
                 (D.DETONADOR[0], D.G, D.DETONADOR[2], "detonador (dentro)"),
                 (D.TECLADO[0] + 0.6, D.G, D.TECLADO[2], "teclado"),
                 (D.TANQUE[0] + 1.6, D.G, D.TANQUE[2] - 2.0, "tanque"),
                 (D.CUADROS_PISTA[0][0], D.G, D.CUADROS_PISTA[0][2] + 1.0, "cuadro de pista 1"),
                 (D.CUADROS_PISTA[2][0], D.G, D.CUADROS_PISTA[2][2] + 1.0, "cuadro de pista 3")]
        extra += [(e[0], D.G, e[2], "empalme %d" % (i + 1)) for i, e in enumerate(D.EMPALMES)]
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
        for desde in ("tren", "refineria", "verja", "patio", "salida del colector", "refugio", "minas", "hangar"):
            i = nombres.index(desde)
            x, y, z, _n = D.RUTA[i]
            val2.navegacion((x, y + 0.1, z, 0.0))
            ok = [n for (xx, yy, zz, n) in D.RUTA if val2.punto_alcanzable(xx, yy, zz)[0]]
            print("  ATAJOS desde %-20s -> %s" % (desde, ", ".join(ok)))
            if desde == "tren" and "--atajos-detalle" in args:
                cel = sorted(k for k in val2._visit if 36.0 <= (k[0] + 0.5) * 0.8 <= 62.0)
                for k in cel[:400]:
                    print("    celda x %.1f z %.1f y %.1f" % ((k[0] + 0.5) * 0.8, (k[1] + 0.5) * 0.8, (k[2] + 1) * 0.1))
    base = os.path.join(MAPAS, NOMBRE)
    # sin pistas dentro del refugio, en el agua, en el barranco, en el caz ni en el pozo
    pistas = [p for p in pistas if not D.dentro(p[0], p[2], D.REFUGIO, 1.0) and not D.dentro(p[0], p[2], D.CANAL, 0.3)
              and not D.dentro(p[0], p[2], D.COLECTOR, 0.3) and not D.dentro(p[0], p[2], D.POZO_A, 0.3)
              and not D.dentro(p[0], p[2], D.POZO_B, 0.3) and not D.dentro(p[0], p[2], D.MINAS, 0.0) and p[1] > 2.0]
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
        json.dump({"cell": 1.5, "lights": luces, "source": "tools/generar_mapa_campana5.py"}, f, separators=(",", ":"))
    with open(base + ".pve.json", "w", encoding="utf-8") as f:
        json.dump({"criaturas": [list(p) for p in pistas], "spawn_jugador": list(D.SPAWN_JUGADOR)}, f, indent=1)
    # EL AGUA: embalse, rio, caz, arroyo del barranco y el pozo de la central (el juego lo vacia)
    agua = {"cuerpos": [
        {"y": D.CANAL_AGUA, "rect": [D.CANAL[0], D.CANAL[1], 172.0, D.CANAL[3]]},
        {"y": D.COLECTOR_AGUA, "rect": [D.POZO_A[0], D.POZO_A[1], D.POZO_B[2], D.POZO_B[3]]},     # pozos y tubo
    ], "source": "tools/generar_mapa_campana5.py"}
    with open(base + ".agua.json", "w", encoding="utf-8") as f:
        json.dump(agua, f, indent=1)
    with open(base + ".campana.json", "w", encoding="utf-8") as f:
        json.dump(json_campana(), f, ensure_ascii=False, indent=1)
    print("== escrito %s.vxmap: %.2f MB, %d chunks, %d voxels solidos" % (NOMBRE, t_hi / 1048576, len(hi), s_hi))
    print("== escrito %s_lo.vxmap: %.2f MB, %d chunks" % (NOMBRE, t_lo / 1048576, len(lo)))
    print("== %d luces, %d pistas de salida" % (len(luces), len(pistas)))
    if val:
        malos = [n for n, ok in ruta_ok if not ok]
        print("== RECORRIDO: %s" % ("COMPLETO (se llega a todo)" if not malos else "FALTA LLEGAR A: " + ", ".join(malos)))
    print("== hecho en %.1f s" % (time.time() - t0))


if __name__ == "__main__":
    main()
