#!/usr/bin/env python3
"""GENERADOR DEL MAPA PvE "pve_cuarentena": puesto militar en cuarentena, de noche, despues del brote.

Es el INTEGRADOR. Las zonas las construyen modulos aparte (tools/mapa_pve/zona_<nombre>.py) que solo
apuntan primitivas en un Lienzo (tools/mapa_pve/lienzo.py). Aqui se hace:
  1. El terreno base, las calles y el relleno entre zonas (tools/mapa_pve/relleno.py).
  2. La llamada a cada zona en su rectangulo (tools/mapa_pve/disposicion.py). Si un modulo falta o revienta,
     se registra y se usa un respaldo propio (tools/mapa_pve/respaldo.py): el mapa se genera SIEMPRE.
  3. La rasterizacion por baldosas a 10 cm y a 20 cm (tools/mapa_pve/raster.py) y la paleta del motor:
     cada material del Lienzo se traduce por su `tipo` a una clase fisica (fuerza, densidad, anclaje...)
     y a 1-4 variantes de color para las manchas de mugre.
  4. La escritura de godot/maps/pve_cuarentena.vxmap (10 cm) y pve_cuarentena_lo.vxmap (20 cm), con los
     puntos de aparicion en la cabecera (el primero es el del jugador: VoxelWorld.load_map), las luces en
     pve_cuarentena.lights.json (main.gd::_load_lamps) y las pistas de las zonas en pve_cuarentena.pve.json.
  5. La validacion (tools/mapa_pve/validar.py): A* del motor replicado desde el spawn y trozos flotantes.

Uso:  python tools/generar_mapa_pve.py [--sin-validar] [--sin-zonas] [--solo=zona_plaza,...]
Determinista: semilla fija; cada zona recibe su propio random.Random derivado de su nombre.
"""
import importlib, json, math, os, random, struct, sys, time, traceback, zlib
import numpy as np

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(AQUI, "mapa_pve"))
import lienzo as L          # noqa: E402
import disposicion as D     # noqa: E402
import raster               # noqa: E402

RAIZ = os.path.dirname(AQUI)
MAPAS = os.path.join(RAIZ, "godot", "maps")
NOMBRE = "pve_cuarentena"
SEMILLA = 20260911
MAX_LUCES = 160            # cada luz es un OmniLight3D sin sombra; dust2 va con 205
MAX_SPAWNS = 12

# Materiales propios del integrador (el suelo ancla: lo que se apoya en el no se cae)
EXTRA = {
    "suelo_tierra": ((56, 46, 36), "suelo"),
    "suelo_barro": ((40, 33, 26), "suelo"),
    "suelo_grava": ((70, 66, 60), "suelo"),
    "suelo_hierba": ((52, 50, 34), "suelo"),
    "suelo_ceniza": ((44, 42, 40), "suelo"),
    "suelo_asfalto": ((34, 34, 36), "suelo_duro"),
    "suelo_hormigon": ((88, 86, 80), "suelo_duro"),
    "suelo_sangre": ((66, 12, 9), "suelo"),
    "pintura_blanca": ((128, 126, 118), "suelo_pintura"),
    "pintura_amarilla": ((132, 104, 28), "suelo_pintura"),
    "roca_base": ((34, 31, 28), "base"),
    "plastico_negro": ((22, 22, 24), "tela"),
    "goma": ((20, 20, 22), "goma"),
    "chapa_blanca": ((112, 110, 104), "metal"),    # coches de los evacuados: colores apagados por la mugre
    "chapa_roja": ((84, 26, 22), "metal"),
    "chapa_azul": ((32, 42, 64), "metal"),
}

# tipo -> (fuerza 0..255, densidad kg/m3, flags, soporte x16, masa x16). flags: 1 ancla, 2 indestructible,
# 4 cristal, 8 emisivo. Mismas clases que tools/bake_teardown_map.py (CLASS_PHYS) para que el solver
# estructural trate igual este mapa que los importados.
FISICA = {
    "tierra": (120, 1600, 0, 12, 10),      # montones de tierra, relleno de sacos: se comportan como mamposteria
    "piedra": (200, 2500, 0, 18, 17),
    "ladrillo": (120, 1900, 0, 13, 13),
    "hormigon": (170, 2400, 0, 16, 16),
    "metal": (150, 7000, 0, 18, 45),       # chapa: metal debil
    "madera": (55, 600, 0, 8, 4),
    "tela": (30, 300, 0, 1, 2),
    "vidrio": (10, 2500, 4, 0, 17),
    "organico": (40, 1000, 0, 3, 6),
    "luz": (20, 2500, 8, 2, 17),
    "goma": (60, 1100, 0, 4, 7),
    "suelo": (200, 1600, 1, 16, 10),       # destructible: el golpe al suelo del Goliat abre crateres
    "suelo_duro": (220, 2300, 1, 16, 15),
    "suelo_pintura": (220, 2300, 1, 16, 15),
    "base": (255, 2600, 3, 20, 17),        # los 0,4 m de abajo: nadie cae fuera del mundo por un agujero
}
POR_NOMBRE = {
    "metal": (220, 7800, 0, 20, 52), "metal_negro": (220, 7800, 0, 20, 52),
    "carbon": (30, 450, 0, 4, 3), "sacos": (120, 1600, 0, 12, 10),
    "sangre": (150, 1600, 0, 12, 10), "sangre_seca": (150, 1600, 0, 12, 10),   # tinen suelos y muros: no los ablandan
    "hueso": (60, 1800, 0, 6, 8), "baldosa_hospital": (170, 2300, 0, 16, 15),
}
MUGRE, OXIDO, MOHO = (28, 24, 20), (82, 44, 24), (38, 42, 30)


def registrar_materiales():
    for k, v in EXTRA.items():
        L.MATERIALES.setdefault(k, v)


def variantes(nombre, rgb, tipo):
    """Color base + variantes de mugre. Luces, cristal, pintura y roca: un solo color.
    Con patron (L.PATRONES), sus colores tal cual: el dibujo los elige por posicion."""
    if nombre in L.PATRONES:
        return [tuple(c) for c in L.PATRONES[nombre][1]]
    if tipo in ("luz", "vidrio", "base", "suelo_pintura"):
        return [rgb]
    mezcla = OXIDO if tipo == "metal" else MOHO if tipo in ("hormigon", "piedra", "ladrillo") else MUGRE

    def f(k, t):
        return tuple(int(round(max(0, min(255, c * k * (1 - t) + m * t)))) for c, m in zip(rgb, mezcla))
    if nombre.startswith("sangre"):
        return [rgb, f(0.70, 0.0)]
    return [rgb, f(0.86, 0.0), f(0.78, 0.18), f(0.64, 0.36)]


PATRON = np.zeros(256, np.int64)      ## id de material -> codigo de patron (0: manchas al azar de siempre)


def construir_paleta():
    entradas, id_de = [], {}
    nvar = np.ones(256, np.int64)
    desp = np.zeros((256, 3), np.int64)
    PATRON[:] = 0
    for nombre, (rgb, tipo) in L.MATERIALES.items():
        fis = POR_NOMBRE.get(nombre) or FISICA.get(tipo) or FISICA["hormigon"]
        vs = variantes(nombre, rgb, tipo)
        base = 16 + len(entradas)
        if base + len(vs) > 256:
            raise RuntimeError("paleta llena: demasiados materiales en el Lienzo")
        id_de[nombre] = base
        for v in vs:
            entradas.append((v[0], v[1], v[2]) + fis)
        nvar[base] = len(vs)
        if nombre in L.PATRONES:
            PATRON[base] = L.PATRON_CODIGO[L.PATRONES[nombre][0]]
        h = zlib.crc32(nombre.encode("utf-8"))
        desp[base] = (h % 64, (h >> 6) % 64, (h >> 12) % 64)
    return entradas, id_de, nvar, desp


def llamar_zona(lz, modulo, rect, respaldo, informe):
    """Llama a una zona. Si falta o lanza una excepcion se tira lo que hubiera apuntado y va el respaldo."""
    n0, l0, p0 = len(lz.prims), len(lz.luces), len(lz.puntos)
    rng = random.Random(SEMILLA ^ zlib.crc32(modulo.encode("utf-8")))
    t0 = time.time()
    estado, detalle = "ok", ""
    try:
        if modulo in sys.modules:
            mod = importlib.reload(sys.modules[modulo])
        else:
            mod = importlib.import_module(modulo)
        mod.construir(lz, rect, D.SUELO_Y, rng)
    except ModuleNotFoundError as e:
        estado, detalle = ("falta", "") if e.name == modulo else ("error", "import: %s" % e)
    except Exception as e:                                  # noqa: BLE001 - una zona rota no tumba el mapa
        estado, detalle = "error", "%s: %s" % (type(e).__name__, e)
        traceback.print_exc()
    if estado != "ok":
        del lz.prims[n0:], lz.luces[l0:], lz.puntos[p0:]
        respaldo(lz, rect, D.SUELO_Y, random.Random(SEMILLA ^ 0x5EED ^ zlib.crc32(modulo.encode("utf-8"))))
    fuera = 0
    if modulo != "zona_perimetro":
        for p in lz.prims[n0:]:
            x0, _y0, z0, x1, _y1, z1 = raster_caja_m(p)
            if x0 < rect[0] - 0.5 or z0 < rect[1] - 0.5 or x1 > rect[2] + 0.5 or z1 > rect[3] + 0.5:
                fuera += 1
    informe.append({"zona": modulo, "estado": estado, "detalle": detalle, "rect": rect,
                    "primitivas": len(lz.prims) - n0, "luces": len(lz.luces) - l0, "puntos": len(lz.puntos) - p0,
                    "fuera_del_rect": fuera, "segundos": round(time.time() - t0, 2)})
    print("  %-16s %-6s %6d primitivas %3d luces %3d puntos%s%s" % (
        modulo, estado, len(lz.prims) - n0, len(lz.luces) - l0, len(lz.puntos) - p0,
        ("  [%d fuera del rect]" % fuera) if fuera else "", ("  (%s)" % detalle) if detalle else ""))


def raster_caja_m(p):
    tipo, d = p[0], p[1]
    if tipo == "caja":
        return d
    if tipo == "elipsoide":
        return d[0] - d[3], d[1] - d[4], d[2] - d[5], d[0] + d[3], d[1] + d[4], d[2] + d[5]
    if tipo == "cilindro":
        cx, y0, cz, r, alto, eje = d
        if eje == "y":
            return cx - r, y0, cz - r, cx + r, y0 + alto, cz + r
        if eje == "x":
            return cx, y0 - r, cz - r, cx + alto, y0 + r, cz + r
        return cx - r, y0 - r, cz, cx + r, y0 + r, cz + alto
    if tipo == "linea":
        x0, y0, z0, x1, y1, z1, r = d
        return min(x0, x1) - r, min(y0, y1) - r, min(z0, z1) - r, max(x0, x1) + r, max(y0, y1) + r, max(z0, z1) + r
    return d[:6]


def escribir_vxmap(ruta, vs, dims, materiales, spawns, chunks):
    # SOLO EL DE 20 CM (2026-10-14, pedido): el de 10 cm ya no se escribe; se juega siempre el `_lo` (los viejos, en el
    # escritorio, carpeta mapas). BREACH_MAPA_10CM=1 lo vuelve a escribir.
    if not str(ruta).endswith("_lo.vxmap") and not os.environ.get("BREACH_MAPA_10CM"):
        print("  (no se escribe %s: solo el de 20 cm)" % os.path.basename(str(ruta)))
        return 0
    partes = [b"VXMP", struct.pack("<If", 1, vs), struct.pack("<iii", *dims), struct.pack("<fff", 0.0, 0.0, 0.0),
              struct.pack("<H", len(materiales))]
    partes += [struct.pack("<BBBBHBBB", *m) for m in materiales]
    partes.append(struct.pack("<H", len(spawns)))
    partes += [struct.pack("<ffff", *s) for s in spawns]
    claves = sorted(chunks)
    partes.append(struct.pack("<I", len(claves)))
    for k in claves:
        datos, n = chunks[k]
        partes.append(struct.pack("<II", k, n))
        partes.append(datos)
    tmp = ruta + ".tmp"
    with open(tmp, "wb") as f:
        f.write(b"".join(partes))
    os.replace(tmp, ruta)          # nunca un .vxmap a medio escribir si el juego lo abre a la vez
    return os.path.getsize(ruta)


def puntos_de_aparicion(lz):
    """El primero es el del jugador (VoxelWorld.load_map lo usa como spawn). Detras, pistas de las zonas
    (jefe y criaturas) y cruces de calles: los usan las pruebas de estres/tour como puntos de suelo."""
    sp = [(D.SPAWN_JUGADOR[0], D.SPAWN_JUGADOR[1] + 0.1, D.SPAWN_JUGADOR[2], 180.0)]
    for tipo in ("jefe", "criatura"):
        for x, y, z, t in lz.puntos:
            if t == tipo and len(sp) < MAX_SPAWNS - 3:
                sp.append((x, y + 0.1, z, 0.0))
    for x, z in ((99.2, 53.6), (16.0, 81.6), (182.4, 81.6), (68.8, 109.6), (129.6, 53.6)):
        if len(sp) < MAX_SPAWNS:
            sp.append((x, D.SUELO_Y + 0.1, z, 0.0))
    return sp


def main():
    args = sys.argv[1:]
    t0 = time.time()
    registrar_materiales()
    import relleno, respaldo      # noqa: E401 - despues de registrar los materiales propios
    lz = L.Lienzo()
    rng = random.Random(SEMILLA)
    print("== %s: %.1f x %.1f x %.1f m, voxel %.2f m" % (NOMBRE, D.ANCHO_X, D.ALTO_MUNDO, D.ANCHO_Z, D.VOXEL))
    relleno.terreno(lz, rng)
    relleno.decorar(lz, rng)
    print("  integrador: %d primitivas, %d luces" % (len(lz.prims), len(lz.luces)))
    informe = []
    solo = next((a.split("=", 1)[1].split(",") for a in args if a.startswith("--solo=")), None)
    for modulo, rect in D.ZONAS:
        usar = "--sin-zonas" not in args and (solo is None or modulo in solo)
        if usar:
            llamar_zona(lz, modulo, rect, respaldo.RESPALDOS[modulo], informe)
        else:
            llamar_zona(lz, "__desactivada__" + modulo, rect, respaldo.RESPALDOS[modulo], informe)
            informe[-1]["zona"] = modulo
    relleno.cierre(lz, rng)
    materiales, id_de, nvar, desp = construir_paleta()
    dims_vox = (D.CHUNKS[0] * 32, D.CHUNKS[1] * 32, D.CHUNKS[2] * 32)
    lista, cajas = raster.preparar(lz.prims, D.VOXEL, dims_vox, id_de)
    alto = int(min(dims_vox[1], max(128, math.ceil(int(cajas[:, 3].max()) / 64.0) * 64)))
    print("  %d primitivas utiles, %d materiales, alto de trabajo %.1f m (%.1f s)" % (len(lista), len(materiales), alto * D.VOXEL, time.time() - t0))
    VAR = raster.textura_variacion(SEMILLA)
    val = None
    if "--sin-validar" not in args:
        import validar
        val = validar.Validador(alto, materiales)
    hi, lo, dims_lo, s_hi, s_lo = raster.rasterizar_mapa(lista, cajas, D.VOXEL, D.CHUNKS, alto, nvar, desp, VAR,
                                                         val.al_terminar if val else None)
    base = os.path.join(MAPAS, NOMBRE)
    spawn_jug = (D.SPAWN_JUGADOR[0], D.SPAWN_JUGADOR[1] + 0.1, D.SPAWN_JUGADOR[2], 180.0)
    pistas_zona = [(x, y, z) for x, y, z, t in lz.puntos if t == "criatura"]
    jefes = [(x, y, z) for x, y, z, t in lz.puntos if t == "jefe"]
    # PISTAS DE SALIDA (pve.gd::_cargar_pistas lee la lista "criaturas" del .pve.json): solo valen los puntos a
    # los que se llega desde el jugador con el A* del motor, y ademas se siembra una rejilla por todo lo
    # transitable. Si se dejan las pistas en crudo, pve.gd saca criaturas detras de un muro o al otro lado del
    # perimetro y se pasan la oleada dando un rodeo (medido: una salio a 41,8 m y se alejaba).
    if val:
        val.navegacion(spawn_jug)
        pistas = val.pistas(pistas_zona)
        jefes = [p for p in jefes if val.punto_alcanzable(*p)[0]]
    else:
        pistas = [tuple(round(v, 2) for v in p) for p in pistas_zona]
    spawns = [spawn_jug] + [(x, y + 0.1, z, 0.0) for x, y, z in (jefes + pistas)[:MAX_SPAWNS - 1]]
    t_hi = escribir_vxmap(base + ".vxmap", D.VOXEL, D.CHUNKS, materiales, spawns, hi)
    t_lo = escribir_vxmap(base + "_lo.vxmap", D.VOXEL * 2, dims_lo, materiales, spawns, lo)
    # Las luces con direccion y cono salen como FOCO (main.gd monta un SpotLight3D y pinta un cono en el
    # suelo); las que no lo traen siguen siendo luz normal, como en los demas mapas.
    luces = []
    for entrada in lz.luces[:MAX_LUCES]:
        x, y, z, col, e, a = entrada[:6]
        luz = {"pos": [round(x, 2), round(y, 2), round(z, 2)], "color": [round(c / 255.0, 4) for c in col],
               "energy": round(float(e), 2), "range": round(float(a), 2)}
        direccion = entrada[6] if len(entrada) > 6 else None
        if direccion:
            n = math.sqrt(sum(v * v for v in direccion)) or 1.0
            luz["dir"] = [round(v / n, 4) for v in direccion]
            luz["cono"] = round(float(entrada[7]), 1)
        luces.append(luz)
    n_focos = sum(1 for q in luces if "dir" in q)
    with open(base + ".lights.json", "w", encoding="utf-8") as f:
        json.dump({"cell": 1.5, "lights": luces, "source": "tools/generar_mapa_pve.py"}, f, separators=(",", ":"))
    datos = {"jugador": [list(map(lambda v: round(v, 2), p[:3])) for p in lz.puntos if p[3] == "jugador"],
             "jefe": [list(p) for p in jefes],
             "criaturas": [list(p) for p in pistas],
             "spawn_jugador": list(D.SPAWN_JUGADOR), "zonas": {z["zona"]: [z["estado"], list(z["rect"])] for z in informe}}
    with open(base + ".pve.json", "w", encoding="utf-8") as f:
        json.dump(datos, f, ensure_ascii=False, indent=1)
    print("== escrito %s.vxmap: %.2f MB, %d chunks, %d voxels solidos (%dx%dx%d chunks)" % (NOMBRE, t_hi / 1048576, len(hi), s_hi, *D.CHUNKS))
    print("== escrito %s_lo.vxmap: %.2f MB, %d chunks, %d voxels solidos (%dx%dx%d chunks)" % (NOMBRE, t_lo / 1048576, len(lo), s_lo, *dims_lo))
    print("== %d spawns (jugador en %s), %d luces (%d focos con cono, %d normales)%s" % (
        len(spawns), spawns[0][:3], len(luces), n_focos, len(luces) - n_focos,
        (" (recortadas de %d)" % len(lz.luces)) if len(lz.luces) > MAX_LUCES else ""))
    if val:
        # las vistas previas NUNCA en godot/maps: Godot importaria los PNG como recursos del juego
        import tempfile
        carpeta = next((a.split("=", 1)[1] for a in args if a.startswith("--vista=")), tempfile.gettempdir())
        val.flotantes()      # la navegacion ya se hizo antes de escribir: hacia falta para filtrar las pistas
        val.vistas(os.path.join(carpeta, NOMBRE + "_vista"), spawns[0])
    print("== hecho en %.1f s" % (time.time() - t0))


if __name__ == "__main__":
    main()
