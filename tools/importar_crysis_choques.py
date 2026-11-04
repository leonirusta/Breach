"""Los CHOQUES de Crysis (physics_collisions) para lo que se rompe y cae: metal, madera, cristal, piedra, tierra y
plastico, cada uno en tres tamaños y con muchas variantes para que no se repita (pedido, 2026-10-03).

AUDIO COMERCIAL CON DERECHOS (Crytek), TEMPORAL como el de Battlefield y Left 4 Dead: vale para probar y se quita antes
de publicar borrando godot/sounds/crysis. Sin esa carpeta el juego suena como antes (Teardown).

Salida (las clases son las de Audio.material_class):
    godot/sounds/crysis/choque/<metal|wood|glass|masonry|dirt|plastic>/<s|m|l><n>.ogg   (physics_collisions: golpes)
    godot/sounds/crysis/rotura/<metal|wood|glass|masonry>/<s|m|l><n>.ogg                 (physics_destructibles: roturas)
    godot/sounds/crysis/traje/blindaje1.ogg, voz_blindaje1.ogg                            (interface_suit)

SIN LAG: el juego los pasa todos a WAV en un hilo durante la carga (Audio, banco "crysis"), y en memoria pesan ~88 KB por
segundo. Por eso aqui se les corta la cola que ya no se oye (por debajo de COLA_DB del pico) y se acotan (MAX_CHOQUE_S,
MAX_ROTURA_S, con fundido): ~1/3 menos sin cambiar lo que se oye.

Todas igualadas en volumen (RMS de los primeros 0,3 s a OBJETIVO_DB, sin pasar de -1 dBFS de pico): en la carpeta
original van todas a 0 dBFS de pico y unas suenan 20 dB mas fuertes que otras.

Uso:  python tools/importar_crysis_choques.py ["C:/Users/usuario 1/Desktop/Sonidos Crysis - todos"]
"""
import glob, os, re, shutil, sys
import numpy as np
import soundfile as sf

RAIZ = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.expanduser("~"), "Desktop", "Sonidos Crysis - todos")
SRC = os.path.join(RAIZ, "physics_collisions")
SRC_ROT = os.path.join(RAIZ, "physics_destructibles")
DST_RAIZ = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot", "sounds", "crysis")
DST = os.path.join(DST_RAIZ, "choque")
OBJETIVO_DB = -20.0
PICO_DB = -1.0
COLA_DB = -48.0
MAX_CHOQUE_S = 1.0
MAX_ROTURA_S = 2.2
FUNDIDO_S = 0.25

# las roturas: clase -> tamaño -> patrones de physics_destructibles
ROTURAS = {
    "metal":   {"s": "*metal_small_shatter*", "m": "*metal_medium_shatter*", "l": "*metal_large_shatter*"},
    "wood":    {"s": "*wood_small_shatter*", "m": "*wood_medium_shatter*", "l": "*wood_large_shatter*"},
    "glass":   {"s": "*glass_small_shatter*", "m": "*vehicle_window*", "l": "*frozen_vehicle_shatter*"},
    "masonry": {"l": "*cliff_break*"},
}

# clase del juego -> grupos de la carpeta (nombre sin el numero del principio, hasta el tamaño)
CLASES = {
    "metal":   ["metal_sheet", "metal_thick", "mat_metal_thick", "metal_pipe", "metal_grate", "metal_chainlink"],
    "wood":    ["wood_solid", "wood_hollow"],
    "glass":   ["glass_thin", "glass_thick"],
    "masonry": ["rock", "mat_rubble_mixed", "pebble"],
    "dirt":    ["mat_dirt", "mat_mud"],
    "plastic": ["mat_plastic"],
}
TAM = {"small": "s", "medium": "m", "large": "l"}
# el plastico no trae "small": usa el medio
PRESTADO = {("plastic", "s"): "m"}


def grupo_y_tam(nombre):
    m = re.match(r"^\d+_(.+?)_(small|medium|large)_", nombre)
    return (m.group(1), TAM[m.group(2)]) if m else (None, None)


def escribir(origen, destino, max_s=MAX_CHOQUE_S):
    x, sr = sf.read(origen, always_2d=True)
    x = x.astype(np.float32).mean(axis=1)
    # la cola que ya no se oye fuera, y como mucho max_s, con fundido al final
    pico0 = float(np.abs(x).max()) + 1e-9
    vivos = np.nonzero(np.abs(x) > pico0 * 10 ** (COLA_DB / 20))[0]
    fin = min(len(x), (int(vivos[-1]) + int(sr * 0.03)) if len(vivos) else len(x), int(sr * max_s))
    x = x[:fin].copy()
    nf = min(fin, int(sr * FUNDIDO_S))
    x[fin - nf:] *= np.linspace(1.0, 0.0, nf, dtype=np.float32) ** 2
    seg = x[: max(1, int(sr * 0.3))]
    rms = float(np.sqrt((seg ** 2).mean())) + 1e-9
    pico = float(np.abs(x).max()) + 1e-9
    g = min(10 ** (OBJETIVO_DB / 20) / rms, 10 ** (PICO_DB / 20) / pico)
    x = x * g
    with sf.SoundFile(destino, "w", sr, 1, format="OGG", subtype="VORBIS") as f:
        for i in range(0, len(x), 8192):
            f.write(x[i:i + 8192])


def main():
    dst = os.path.abspath(DST)
    if os.path.isdir(dst):
        shutil.rmtree(dst)
    por = {}
    for f in sorted(glob.glob(os.path.join(SRC, "*.wav"))):
        g, t = grupo_y_tam(os.path.basename(f))
        if g is None:
            continue
        for cls, grupos in CLASES.items():
            if g in grupos:
                por.setdefault((cls, t), []).append(f)
    for (cls, t), dueño in list(PRESTADO.items()):
        if (cls, t) not in por and (cls, dueño) in por:
            por[(cls, t)] = por[(cls, dueño)]
    total = 0
    for cls in CLASES:
        os.makedirs(os.path.join(dst, cls), exist_ok=True)
        linea = []
        for t in "sml":
            fs = por.get((cls, t), [])
            for n, f in enumerate(fs, 1):
                escribir(f, os.path.join(dst, cls, "%s%d.ogg" % (t, n)))
            linea.append("%s %d" % (t, len(fs)))
            total += len(fs)
        print("%-8s %s" % (cls, " · ".join(linea)))
    # LAS ROTURAS
    rot = os.path.abspath(os.path.join(DST_RAIZ, "rotura"))
    if os.path.isdir(rot):
        shutil.rmtree(rot)
    for cls, tams in ROTURAS.items():
        os.makedirs(os.path.join(rot, cls), exist_ok=True)
        linea = []
        for t, pat in tams.items():
            fs = sorted(glob.glob(os.path.join(SRC_ROT, pat)))
            for n, f in enumerate(fs, 1):
                escribir(f, os.path.join(rot, cls, "%s%d.ogg" % (t, n)), MAX_ROTURA_S)
            linea.append("%s %d" % (t, len(fs)))
            total += len(fs)
        print("rotura %-8s %s" % (cls, " · ".join(linea)))
    # EL TRAJE (2026-10-03, pedido: "en Crysis, al activar el blindaje se escucha el cuerpo endureciendose"):
    # blindaje = suit_strength_activate_131 (el traje que se endurece, sin voz); voz_blindaje = suit_armor_108 (la voz
    # "Maximum Armor", que el juego solo pone a veces). Tal cual, solo a -1 dBFS de pico
    traje = os.path.abspath(os.path.join(DST_RAIZ, "traje"))
    os.makedirs(traje, exist_ok=True)
    if os.path.isdir(traje):
        shutil.rmtree(traje)
    os.makedirs(traje, exist_ok=True)
    # El paquete NO trae sonidos de APAGAR: son los de encender AL REVES (pedido: "el sonido inverso, que empiece de
    # derecha a izquierda"; en estereo, darle la vuelta en el tiempo invierte tambien el barrido). Van en estereo: el
    # tuyo suena sin posicion (Audio.traje con en_2d) y se oye el barrido.
    TRAJE = [("blindaje", "*suit_strength_activate_131*", False), ("voz_blindaje", "*suit_armor_108*", False),
             ("blindaje_off", "*suit_strength_activate_131*", True),
             ("invisible_on", "*cloak_chameleon_activate_12*", False), ("invisible_on", "*suit_cloak_chameleon_101_r*", False),
             ("invisible_off", "*cloak_chameleon_activate_12*", True), ("invisible_off", "*suit_cloak_chameleon_101_r*", True)]
    cuenta = {}
    for nombre, pat, reves in TRAJE:
        fs = sorted(glob.glob(os.path.join(RAIZ, "interface_suit", pat)))
        for f in fs:
            cuenta[nombre] = cuenta.get(nombre, 0) + 1
            n = cuenta[nombre]
            x, sr = sf.read(f, always_2d=True)
            if reves:
                x = x[::-1].copy()
                # al reves, la cola (que se apaga despacio) va delante: se le corta lo que no se oye
                pico0 = float(np.abs(x).max()) + 1e-9
                vivos = np.nonzero(np.abs(x).max(axis=1) > pico0 * 10 ** (COLA_DB / 20))[0]
                if len(vivos):
                    x = x[max(0, int(vivos[0]) - int(sr * 0.01)):]
            x = (x * (10 ** (PICO_DB / 20) / (float(np.abs(x).max()) + 1e-9))).astype(np.float32)
            with sf.SoundFile(os.path.join(traje, "%s%d.ogg" % (nombre, n)), "w", sr, x.shape[1], format="OGG", subtype="VORBIS") as o:
                o.write(x)
    print("traje: %s" % cuenta)
    seg = sum(sf.info(f).duration for f in glob.glob(os.path.join(DST_RAIZ, "*", "*", "*.ogg")))
    print("%d archivos, %.0f s en total (~%.1f MB en WAV de 16 bits a 44,1 kHz)" % (total, seg, seg * 88200 / 1e6))


if __name__ == "__main__":
    main()
