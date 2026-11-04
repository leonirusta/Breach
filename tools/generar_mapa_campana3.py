#!/usr/bin/env python3
"""GENERADOR DEL EPISODIO 3 DE LA CAMPAÑA: "EL AMANECER" (campana_amanecer).

Construye con tools/mapa_campana3/ (disposicion.py: el recorrido; amanecer.py: lo que hay) reutilizando el kit del
episodio 1 y del PvE (Lienzo, rasterizador, validacion). LO NUEVO: el mapa va PINTADO (lienzo.PATRONES: cada
fachada, suelo y tejado con su dibujo, ver raster._patron) y es de DIA (el json lleva "hora": "amanecer").

  godot/maps/campana_amanecer.vxmap / _lo.vxmap, .lights.json, .pve.json y .campana.json

DOS PASADAS. La primera construye la variante de VALIDACION (los puzzles ya resueltos: contenedor abajo, chimenea
tumbada, escalera en vez de montacargas, puente bajado) y comprueba que todo el recorrido se anda con el A* del
motor. La segunda construye el mapa de verdad y lo escribe.

Uso:  python tools/generar_mapa_campana3.py [--sin-validar]
"""
import json, math, os, random, sys, time

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(AQUI, "mapa_pve"))
sys.path.insert(0, os.path.join(AQUI, "mapa_campana"))
sys.path.insert(0, os.path.join(AQUI, "mapa_campana3"))      # PRIMERO: su disposicion manda
import disposicion as D      # noqa: E402  (la del episodio 3)
import lienzo as L           # noqa: E402
import raster                # noqa: E402
import generar_mapa_pve as G  # noqa: E402
import amanecer as C         # noqa: E402

RAIZ = os.path.dirname(AQUI)
MAPAS = os.path.join(RAIZ, "godot", "maps")
NOMBRE = "campana_amanecer"
SEMILLA = 20260927
MAX_LUCES = 60
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


def main():
    args = sys.argv[1:]
    t0 = time.time()
    G.registrar_materiales()
    for k, v in C.MATERIALES.items():
        L.MATERIALES[k] = v                  # los del dia mandan sobre los de la noche si se llaman igual
    print("== %s: %.1f x %.1f x %.1f m, voxel %.2f m" % (NOMBRE, D.ANCHO_X, D.ALTO_MUNDO, D.ANCHO_Z, D.VOXEL))
    lz = lienzo(False)
    print("  %d primitivas, %d luces (%.1f s)" % (len(lz.prims), len(lz.luces), time.time() - t0))
    materiales, id_de, nvar, desp = paleta_usada(lz.prims)
    raster.PATRON = G.PATRON.copy()          # LOS DIBUJOS: el rasterizador pinta por posicion
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
        extra = [(D.GENERADOR_BOTON[0], D.Y2, D.GENERADOR_BOTON[2] - 0.8, "boton del generador"),
                 (D.RADIO[0], D.Y3, D.RADIO[2] + 3.0, "puerta de la radio"),
                 (D.HELIPUERTO[0], D.Y3, D.HELIPUERTO[2], "helipuerto")]
        for x, y, z, nombre in D.RUTA + extra:
            ok, alt = val.punto_alcanzable(x, y, z)
            ruta_ok.append((nombre, ok))
            print("  ruta %-28s %s%s" % (nombre, "OK" if ok else "NO SE LLEGA", "" if alt is None else "  (suelo a %.2f)" % alt))
    print("  PASADA 2: el mapa")
    alto, lista, cajas = preparar(lz, id_de)
    hi, lo, dims_lo, s_hi, s_lo = raster.rasterizar_mapa(lista, cajas, D.VOXEL, D.CHUNKS, alto, nvar, desp, VAR, None)
    base = os.path.join(MAPAS, NOMBRE)
    # sin pistas dentro del refugio, en el barranco ni en el foso (se quedarian atrapadas)
    pistas = [p for p in pistas if not D.dentro(p[0], p[2], D.REFUGIO, 1.0) and not D.dentro(p[0], p[2], D.BARRANCO, 0.5)
              and not D.dentro(p[0], p[2], D.FOSO, 0.5) and p[1] > D.ROCA_Y + 0.3]
    spawns = [spawn_jug] + [(x, y + 0.1, z, 0.0) for x, y, z in pistas[:MAX_SPAWNS - 1]]
    t_hi = G.escribir_vxmap(base + ".vxmap", D.VOXEL, D.CHUNKS, materiales, spawns, hi)
    t_lo = G.escribir_vxmap(base + "_lo.vxmap", D.VOXEL * 2, dims_lo, materiales, spawns, lo)
    luces = []
    for entrada in lz.luces[:MAX_LUCES]:
        x, y, z, col, e, a = entrada[:6]
        luces.append({"pos": [round(x, 2), round(y, 2), round(z, 2)], "color": [round(c / 255.0, 4) for c in col],
                      "energy": round(float(e) * 1.4, 2), "range": round(float(a) * 1.3, 2)})
    with open(base + ".lights.json", "w", encoding="utf-8") as f:
        json.dump({"cell": 1.5, "lights": luces, "source": "tools/generar_mapa_campana3.py"}, f, separators=(",", ":"))
    with open(base + ".pve.json", "w", encoding="utf-8") as f:
        json.dump({"criaturas": [list(p) for p in pistas], "spawn_jugador": list(D.SPAWN_JUGADOR)}, f, indent=1)
    r2 = lambda v: [round(float(c), 2) for c in v]
    Y1, Y2, Y3 = D.Y1, D.Y2, D.Y3
    campana = {
        "nombre": "EL AMANECER",
        "capitulo": "Episodio 3 · Del muelle a la ciudadela",
        "episodio": 3,
        "requiere": "campana_puerto",
        "script": "res://scripts/campana3.gd",
        "hora": "amanecer",
        "sol_azimut": 172.0,                 # el sol sale por el mar (sur-sureste)
        "ruta": [[round(x, 2), round(y, 2), round(z, 2), n] for x, y, z, n in D.RUTA],
        "salida": list(D.SPAWN_JUGADOR),
        "municion_fija": [[34.0, D.Y0, 104.0], [30.0, Y1, 66.0], [40.0, Y2, 20.0], [98.0, Y2, 33.0], [128.0, Y3, 36.0],
                          [146.0, Y3, 14.0]],
        # --- los puzzles ---
        "contenedor": {"caja": r2([D.CONT[0], D.CONT_ANDAMIO_Y, D.CONT[1], D.CONT[2], D.CONT_ANDAMIO_Y + D.CONT_ALTO, D.CONT[3]]),
                       "suelo": D.Y0, "puntales": [r2([px, D.Y0, pz, px + 0.4, D.CONT_ANDAMIO_Y - 0.12, pz + 0.4]) for px, pz in D.PUNTALES]},
        "persiana": {"rect": r2([D.PERSIANA[0], Y1, D.PERSIANA[1], D.PERSIANA[2], Y1 + D.PASAJE_ALTO, D.PERSIANA[3]]),
                     "palanca": r2(D.PALANCA)},
        "chimenea": {"base": r2([D.CHIMENEA_BASE[0], Y2, D.CHIMENEA_BASE[1], D.CHIMENEA_BASE[2], Y2 + D.CHIMENEA_BASE_ALTO, D.CHIMENEA_BASE[3]]),
                     "pivote": r2(D.CHIMENEA_PIVOTE), "largo": D.CHIMENEA_LARGO, "radio": D.CHIMENEA_R},
        "generador": {"boton": r2(D.GENERADOR_BOTON), "calentar": 40.0},
        "montacargas": {"cabina": r2([D.CABINA[0], Y2, D.CABINA[1], D.CABINA[2], Y2, D.CABINA[3]]),
                        "boton": r2(D.CABINA_BOTON), "arriba": Y3, "duracion": 22.0},
        "puente": {"bisagra": r2(D.PUENTE_BISAGRA), "largo": D.PUENTE[2] - D.PUENTE[0], "ancho": D.PUENTE[3] - D.PUENTE[1],
                   "tranca": r2(D.TRANCA)},
        "refugio": {"rect": [D.REFUGIO[0], D.REFUGIO[1], D.REFUGIO[2], D.REFUGIO[3]], "puerta_entrada": list(D.REFUGIO_PUERTA_N),
                    "puerta_salida": list(D.REFUGIO_PUERTA_E), "suelo": Y2},
        # el final: los bichos salen TREPANDO las murallas hasta la plaza de armas (campana.gd lo llama "azotea")
        "azotea_hospital": [D.PLAZA_ARMAS[0], Y3, D.PLAZA_ARMAS[1], D.PLAZA_ARMAS[2], D.PLAZA_ARMAS[3]],
        "calle_desde": "muelle",
        "refugio_salida_texto": "Salid por la puerta ESTE del refugio: el MONTACARGAS del acantilado",
        "radio": list(D.RADIO),
        "helipuerto": list(D.HELIPUERTO),
        "barco": list(D.BARCO_PARA),
        "vehiculo": "HELICÓPTERO",
        # --- la entrada y la salida de cine ---
        "cine_entrada": {
            "puntos": [[60.0, 34.0, 150.0], [40.0, 22.0, 132.0], [30.0, 12.0, 122.0], [26.0, 5.0, 114.0]],
            "mira": [[80.0, 18.0, 40.0], [100.0, 26.0, 30.0], [60.0, 12.0, 60.0], [24.0, 2.0, 108.0]],
            "titulo": "EL AMANECER", "sub": "Episodio 3 · Del muelle a la ciudadela"},
        "cine_final": {"desde": list(D.HELIPUERTO), "hacia_mar": [80.0, 30.0, 190.0]},
        "mensaje_inicio": "EL AMANECER · subid hasta la ciudadela",
        "texto_inicio": "Subid al malecón",
        "radio_texto": "USAR LA RADIO (atraerá a la horda)",
        "radio_mensaje": "RADIO: «¡Ciudadela, os tenemos! Helicóptero en camino. ¡Aguantad en la plaza de armas!»",
        "llega_texto": "¡EL HELICÓPTERO HA LLEGADO! ¡AL HELIPUERTO!",
    }
    with open(base + ".campana.json", "w", encoding="utf-8") as f:
        json.dump(campana, f, ensure_ascii=False, indent=1)
    print("== escrito %s.vxmap: %.2f MB, %d chunks, %d voxels solidos" % (NOMBRE, t_hi / 1048576, len(hi), s_hi))
    print("== escrito %s_lo.vxmap: %.2f MB, %d chunks" % (NOMBRE, t_lo / 1048576, len(lo)))
    print("== %d luces, %d pistas de salida" % (len(luces), len(pistas)))
    if val:
        malos = [n for n, ok in ruta_ok if not ok]
        print("== RECORRIDO: %s" % ("COMPLETO (se llega a todo)" if not malos else "FALTA LLEGAR A: " + ", ".join(malos)))
    print("== hecho en %.1f s" % (time.time() - t0))


if __name__ == "__main__":
    main()
