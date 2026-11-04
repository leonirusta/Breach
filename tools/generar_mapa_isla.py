#!/usr/bin/env python3
"""GENERADOR DEL MAPA "isla": isla gigante de battle royale a 15 cm por voxel, rodeada de mar de verdad.

Regiones (tools/mapa_isla/disposicion.py): CIUDAD en el centro con su plaza, MONTANAS al norte con tunel y
observatorio, BOSQUE al noroeste con lago y aserradero, DESIERTO al suroeste con dunas, mesetas, oasis y un
avion estrellado, la CIUDAD DESERTICA amurallada al sur, el AMAZONAS al este con su rio, palafitos y una
piramide, y el PUERTO con el faro al sureste. Todas las carreteras acaban en la ciudad.

Como el de Monaco, es el INTEGRADOR:
  1. Terreno (tools/mapa_isla/terreno.py): mapa de alturas, que las zonas aplanan y pintan (`planificar`).
  2. Zonas (tools/mapa_isla/<zona>.py): apuntan primitivas en el Lienzo (`construir`), con puertas y botin.
  3. Vegetacion por regiones (naturaleza.py).
  4. Rasterizado por baldosas a 15 cm (raster.py) con el terreno como fondo de cada baldosa.
  5. Escritura: godot/maps/isla_lo.vxmap (el juego carga siempre el `_lo`; aqui ya es el de 15 cm) y los
     datos para el juego: isla.lights.json, isla.agua.json, isla.puertas.json, isla.botin.json.

REGLAS DE CONSTRUCCION: docs/10_CONSTRUIR_MAPAS.md. TODO el terreno es material ancla, los edificios meten
el cimiento 0,9 m en el terreno y lo que se pega a algo se mete 0,3 m dentro.

Uso:  python tools/generar_mapa_isla.py [--solo=ciudad,montana] [--sin-vegetacion] [--vista=<carpeta>]
Determinista: semilla fija y cada zona con su random.Random derivado de su nombre.
"""
import importlib, json, math, os, random, struct, sys, time, zlib
import numpy as np

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(AQUI, "mapa_isla"))
import lienzo as L          # noqa: E402
import disposicion as D     # noqa: E402
import terreno as TER       # noqa: E402
import raster               # noqa: E402

RAIZ = os.path.dirname(AQUI)
MAPAS = os.path.join(RAIZ, "godot", "maps")
NOMBRE = os.environ.get("ISLA_NOMBRE", "isla")   # otro nombre para variantes de prueba (con ISLA_VOXEL)
SEMILLA = 20260918
MAX_LUCES = 240
ZONAS = ["ciudad", "montana", "bosque", "desierto", "selva", "costa", "rural"]

# tipo -> (fuerza 0..255, densidad kg/m3, flags, soporte x16, masa x16). flags: 1 ancla, 2 indestructible,
# 4 cristal, 8 emisivo. Mismas clases que Monaco (tools/generar_mapa_monaco.py).
FISICA = {
    "suelo": (200, 1600, 1, 16, 10),
    "suelo_duro": (220, 2300, 1, 16, 15),
    "suelo_pintura": (220, 2300, 1, 16, 15),
    "base": (255, 2600, 3, 20, 17),
    "piedra": (200, 2500, 0, 18, 17),
    "ladrillo": (120, 1900, 0, 13, 13),
    "hormigon": (170, 2400, 0, 16, 16),
    "metal": (150, 7000, 0, 18, 45),
    "madera": (55, 600, 0, 8, 4),
    "tela": (30, 300, 0, 1, 2),
    "vidrio": (10, 2500, 4, 0, 17),
    "organico": (40, 1000, 0, 3, 6),
    "luz": (20, 2500, 8, 2, 17),
    "goma": (60, 1100, 0, 4, 7),
}
MUGRE, OXIDO, MOHO = (28, 24, 20), (82, 44, 24), (38, 42, 30)


def variantes(nombre, rgb, tipo):
    n = L.VARIANTES.get(tipo, 2)
    mezcla = OXIDO if tipo == "metal" else MOHO if tipo in ("hormigon", "piedra", "ladrillo") else MUGRE

    def f(k, t):
        return tuple(int(round(max(0, min(255, c * k * (1 - t) + m * t)))) for c, m in zip(rgb, mezcla))
    if tipo in ("suelo", "suelo_duro", "organico"):
        # el terreno y las hojas varian en tono, no se ensucian: manchas mas claras y mas oscuras
        return [rgb, f(0.9, 0.0), f(1.08, 0.0)][:n]
    return [rgb, f(0.86, 0.0), f(0.74, 0.2)][:n]


def construir_paleta():
    entradas, id_de = [], {}
    nvar = np.ones(256, np.int64)
    desp = np.zeros((256, 3), np.int64)
    for nombre, (rgb, tipo) in L.MATERIALES.items():
        fis = FISICA.get(tipo, FISICA["hormigon"])
        vs = variantes(nombre, rgb, tipo)
        base = 16 + len(entradas)
        if base + len(vs) > 256:
            raise RuntimeError("paleta llena: %d entradas" % (base + len(vs)))
        id_de[nombre] = base
        for v in vs:
            entradas.append((v[0], v[1], v[2]) + fis)
        nvar[base] = len(vs)
        h = zlib.crc32(nombre.encode("utf-8"))
        desp[base] = (h % 64, (h >> 6) % 64, (h >> 12) % 64)
    return entradas, id_de, nvar, desp


def escribir_vxmap(ruta, vs, dims, materiales, spawns, chunks):
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
    os.replace(tmp, ruta)
    return os.path.getsize(ruta)


def ocupar_carreteras(T):
    """Las carreteras (y 2 m de arcen) quedan ocupadas: ni arboles ni rocas encima."""
    for pts, xs, zs, ys, ancho in T.perfiles:
        for x, z in zip(xs, zs):
            r = ancho * 0.5 + 2.0
            T.ocupar(x - r, z - r, x + r, z + r)


class Vista:
    """Planta del mapa (color del voxel mas alto, sombreado por altura) a 0,6 m por pixel."""
    PASO = 4

    def __init__(self, dims, materiales):
        n = dims[0] * 32 // self.PASO
        self.col = np.zeros((n, dims[2] * 32 // self.PASO, 3), np.float32)
        self.alt = np.zeros(self.col.shape[:2], np.float32)
        self.pal = np.zeros((256, 3), np.float32)
        for i, m in enumerate(materiales):
            self.pal[16 + i] = m[:3]

    def al_terminar(self, tx, tz, nucleo):
        s = nucleo[::self.PASO, :, ::self.PASO]
        hay = s != 0
        top = (s.shape[1] - 1 - np.argmax(hay[:, ::-1, :], axis=1))
        idx = np.take_along_axis(s, top[:, None, :], axis=1)[:, 0, :]
        B = s.shape[0]
        x0, z0 = tx * B, tz * B
        x1, z1 = min(x0 + B, self.col.shape[0]), min(z0 + B, self.col.shape[1])
        self.col[x0:x1, z0:z1] = self.pal[idx][:x1 - x0, :z1 - z0]
        self.alt[x0:x1, z0:z1] = np.where(hay.any(axis=1), top * D.VOXEL, 0.0)[:x1 - x0, :z1 - z0]

    def guardar(self, ruta):
        from PIL import Image
        g0, g1 = np.gradient(self.alt)
        img = self.col * np.clip(1.0 + (g0 * 0.5 + g1 * 0.3) * 0.25, 0.55, 1.4)[..., None]
        agua = self.alt < D.MAR_Y
        img[agua] = img[agua] * 0.35 + np.array([28, 92, 140]) * 0.65
        Image.fromarray(np.clip(img, 0, 255).astype(np.uint8).transpose(1, 0, 2)).save(ruta)


def main():
    args = sys.argv[1:]
    t0 = time.time()
    solo = next((a.split("=", 1)[1].split(",") for a in args if a.startswith("--solo=")), None)
    zonas = [z for z in ZONAS if solo is None or z in solo]
    print("== %s: %.1f x %.1f x %.1f m, voxel %.2f m" % (NOMBRE, D.ANCHO_X, D.ALTO_MUNDO, D.ANCHO_Z, D.VOXEL))
    T = TER.Terreno(SEMILLA)
    T.base()
    print("  terreno base (%.1f s)" % (time.time() - t0))
    mods = {}
    for z in zonas:
        try:
            mods[z] = importlib.import_module(z)
        except ModuleNotFoundError as e:
            if e.name != z:
                raise
            print("  (falta la zona %s)" % z)
    for z, mod in mods.items():
        if hasattr(mod, "planificar"):
            mod.planificar(T)
    T.finalizar()
    ocupar_carreteras(T)
    print("  terreno final (%.1f s)" % (time.time() - t0))
    lz = L.Lienzo()
    informe = {}
    for z, mod in mods.items():
        n0, p0, b0 = len(lz.prims), len(lz.puertas), len(lz.botin)
        mod.construir(lz, T, random.Random(SEMILLA ^ zlib.crc32(z.encode("utf-8"))))
        informe[z] = (len(lz.prims) - n0, len(lz.puertas) - p0, len(lz.botin) - b0)
        print("  %-10s %7d primitivas %4d puertas %4d botin" % ((z,) + informe[z]))
    if "--sin-vegetacion" not in args:
        import vegetacion
        n0 = len(lz.prims)
        vegetacion.construir(lz, T, random.Random(SEMILLA ^ 0xF10A))
        print("  %-10s %7d primitivas" % ("vegetacion", len(lz.prims) - n0))
    materiales, id_de, nvar, desp = construir_paleta()
    for n in T.mats:
        if n not in id_de:
            raise RuntimeError("material del terreno sin paleta: " + n)
    dims_vox = (D.CHUNKS[0] * 32, D.CHUNKS[1] * 32, D.CHUNKS[2] * 32)
    lista, cajas = raster.preparar(lz.prims, D.VOXEL, dims_vox, id_de)
    alto = dims_vox[1]
    print("  %d primitivas utiles, %d entradas de paleta (%.1f s)" % (len(lista), len(materiales), time.time() - t0))
    VAR = raster.textura_variacion(SEMILLA)
    vista = Vista(D.CHUNKS, materiales)
    hi, s_hi = raster.rasterizar_mapa(lista, cajas, D.VOXEL, D.CHUNKS, alto, nvar, desp, VAR,
                                      lambda a0, a1, b0, b1, h: T.volumen(id_de, a0, a1, b0, b1, h), vista.al_terminar)
    # --- puntos de aparicion: el primero es el del jugador (VoxelWorld.load_map) --------------------------
    spawns = [(x, y, z, g) for x, y, z, g in lz.spawns][:60]
    base = os.path.join(MAPAS, NOMBRE)
    t_hi = escribir_vxmap(base + "_lo.vxmap", D.VOXEL, D.CHUNKS, materiales, spawns, hi)
    # --- luces: el cupo se reparte a lo largo de la lista (cada zona conserva su parte) -------------------
    fuente = lz.luces
    if len(fuente) > MAX_LUCES:
        k = len(fuente) / float(MAX_LUCES)
        fuente = [fuente[min(len(lz.luces) - 1, int(i * k))] for i in range(MAX_LUCES)]
    luces = []
    for x, y, z, col, e, a, direccion, cono in fuente:
        luz = {"pos": [round(x, 2), round(y, 2), round(z, 2)], "color": [round(c / 255.0, 4) for c in col],
               "energy": round(float(e), 2), "range": round(float(a), 2)}
        if direccion:
            n = math.sqrt(sum(v * v for v in direccion)) or 1.0
            luz["dir"] = [round(v / n, 4) for v in direccion]
            luz["cono"] = round(float(cono), 1)
        luces.append(luz)
    with open(base + ".lights.json", "w", encoding="utf-8") as f:
        json.dump({"cell": 1.5, "lights": luces, "source": "tools/generar_mapa_isla.py"}, f, separators=(",", ":"))
    with open(base + ".agua.json", "w", encoding="utf-8") as f:
        json.dump({"mar_y": D.MAR_Y, "limite": list(D.LIMITE), "cuerpos": lz.agua}, f, indent=1)
    with open(base + ".puertas.json", "w", encoding="utf-8") as f:
        json.dump({"puertas": lz.puertas}, f, separators=(",", ":"))
    with open(base + ".botin.json", "w", encoding="utf-8") as f:
        json.dump({"puntos": lz.botin}, f, separators=(",", ":"))
    por_tipo = {}
    for b in lz.botin:
        por_tipo[b["tipo"]] = por_tipo.get(b["tipo"], 0) + 1
    print("== escrito %s_lo.vxmap: %.2f MB, %d chunks, %d voxels solidos" % (NOMBRE, t_hi / 1048576, len(hi), s_hi))
    print("== %d spawns, %d luces (de %d), %d puertas, %d botin %s, %d laminas de agua" % (
        len(spawns), len(luces), len(lz.luces), len(lz.puertas), len(lz.botin), por_tipo, len(lz.agua)))
    import tempfile
    carpeta = next((a.split("=", 1)[1] for a in args if a.startswith("--vista=")), tempfile.gettempdir())
    ruta = os.path.join(carpeta, NOMBRE + "_vista.png")
    vista.guardar(ruta)
    print("== vista: %s" % ruta)
    # la misma vista es el MAPA GRANDE del battle royale (zona_br.gd, tecla M): va con el juego
    import shutil
    ui = os.path.join(RAIZ, "godot", "ui", "mapas")
    os.makedirs(ui, exist_ok=True)
    shutil.copyfile(ruta, os.path.join(ui, NOMBRE + ".png"))
    print("== mapa del juego: %s" % os.path.join(ui, NOMBRE + ".png"))
    print("== hecho en %.1f s" % (time.time() - t0))


if __name__ == "__main__":
    main()
