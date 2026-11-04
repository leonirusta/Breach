"""Disparos reales por arma, de The Free Firearm Sound Library (Still North Media, CC0: se puede publicar).
https://opengameart.org/content/the-free-firearm-sound-library  (el 7z "Prepared SFX Library")

Cada .wav de la libreria es una toma larga con varios disparos. Esto los corta uno a uno (cada disparo con
su cola, hasta el siguiente o 1,4 s como mucho), tira lo que no es un disparo (manipulacion del arma,
casquillos: picos flojos), iguala el volumen de cada arma y lo guarda en OGG:

    godot/sounds/armas/<arma del juego>/cerca<n>.ogg   (toma "near distance": primera persona y de cerca)
    godot/sounds/armas/<arma del juego>/lejos<n>.ogg   (toma "mid distance": para cuando dispara lejos)

Audio.gunshot lo usa antes que la mezcla de Teardown (PERFIL_ARMA). Si falta la carpeta, vuelve a eso.

Uso:  python tools/importar_disparos.py ["C:/Users/usuario 1/Desktop/FreeFirearmLibrary/Prepared SFX Library"]
Necesita:  pip install soundfile numpy
"""
import glob, os, shutil, sys
import numpy as np
import soundfile as sf

SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.expanduser("~"), "Desktop", "FreeFirearmLibrary", "Prepared SFX Library")
DST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot", "sounds", "armas")

# arma del juego -> [(archivo cerca, archivo lejos), ...]  (se mezclan las armas reales que encajan)
ARMAS = {
    "carabina_556":    [("D_32P", "D_24P")],                       # AR-15 / M4, 5,56
    "fusil_762":       [("C_28P", "C_31P")],                       # AK-47, 7,62x39
    "smg_9mm":         [("G_31P", "G_20P")],                       # Carl Gustav M45, 9 mm
    "smg_compacta":    [("P_30P", "P_16P")],                       # PPSh, 7,62x25
    "pdw_57":          [("R_35P", "R_30P")],                       # Ruger Mark III: calibre pequeño y rapido
    "escopeta_bomba":  [("K_22P", "K_17P"), ("O_21P", "O_17P")],   # Model 12 y Nova, del 12 de bomba
    "escopeta_auto":   [("H_21P", "H_16P")],                       # 12 del 12
    "rifle_precision": [("W_29P", "W_24P"), ("B_24P", "B_16P")],   # Tikka y Springfield 1917, .30-06
    "pistola_9":       [("X_39P", "X_31P")],                       # Walther PPQ, 9 mm
    "pistola_45":      [("A_42P", "A_34P")],                       # Colt 1911, .45
    "revolver_44":     [("V_27P", "V_22P")],                       # S&W 642, .38 (el revolver mas gordo que hay)
    # las que sobran, para que cada bot suene a un fusil distinto
    "bot_sks":         [("U_14P", "U_19P")],                       # SKS, 7,62x39
    "bot_cerrojo":     [("E_25P", "E_18P")],                       # Arisaka
    "bot_palanca":     [("I_22P", "I_17P"), ("L_23P", "L_17P")],   # Marlin 336 y Winchester 1894
}

MAX_CORTE = 1.4        # s: la cola mas larga de un disparo
MIN_ENTRE = 0.35       # s: lo que llega antes es el ECO del mismo disparo, no otro
MIN_LARGO = 0.4        # s: un corte mas corto no tiene cola (se lo come el siguiente): fuera
# SOLO TOMAS DE TIRO SUELTO. Las rafagas de la libreria cortadas salian en trozos de 0,09 s sin cola; en el
# juego cada bala ya suena con su cola y se solapan solas a la cadencia del arma, como en cualquier shooter.
UMBRAL = 0.35          # fraccion del pico de la toma para contar como disparo
SR_OUT = 48000
TOPE_POR_TOMA = 8


def buscar(nombre):
    r = glob.glob(os.path.join(SRC, "**", nombre + ".wav"), recursive=True)
    return r[0] if r else None


def cortar(ruta):
    x, sr = sf.read(ruta, always_2d=True)
    mono = np.abs(x).max(axis=1)
    win = max(1, int(sr * 0.002))
    env = np.maximum.reduceat(mono, np.arange(0, len(mono), win))
    pico = env.max()
    if pico <= 0:
        return [], sr
    arr = np.where(env >= pico * UMBRAL)[0]
    inicios = []
    for i in arr:
        t = i * win
        if not inicios or t - inicios[-1] > MIN_ENTRE * sr:
            inicios.append(t)
    cortes = []
    for k, t0 in enumerate(inicios):
        a = max(0, t0 - int(0.004 * sr))
        fin = inicios[k + 1] - int(0.004 * sr) if k + 1 < len(inicios) else len(x)
        b = min(fin, a + int(MAX_CORTE * sr))
        seg = x[a:b].copy()
        if len(seg) < int(MIN_LARGO * sr):
            continue
        if np.abs(seg).max() < pico * 0.5:
            continue            # un rebote fuerte, no un disparo
        # fundido de salida: el corte no chasquea aunque llegue el siguiente tiro
        f = min(len(seg), int(0.12 * sr))
        seg[-f:] *= np.linspace(1.0, 0.0, f)[:, None]
        cortes.append(seg)
    return cortes[:TOPE_POR_TOMA], sr


def remuestrear(seg, sr):
    if sr == SR_OUT:
        return seg
    n = int(len(seg) * SR_OUT / sr)
    xs = np.linspace(0, len(seg) - 1, n)
    return np.stack([np.interp(xs, np.arange(len(seg)), seg[:, c]) for c in range(seg.shape[1])], axis=1)


def main():
    dst = os.path.abspath(DST)
    # se vacia por dentro y no se borra la carpeta: si el editor o el juego la tienen abierta, Windows no deja
    for sub in glob.glob(os.path.join(dst, "*")):
        shutil.rmtree(sub, ignore_errors=True) if os.path.isdir(sub) else os.remove(sub)
    total = 0
    for arma, tomas in ARMAS.items():
        os.makedirs(os.path.join(dst, arma), exist_ok=True)
        for tipo, idx in (("cerca", 0), ("lejos", 1)):
            segs = []
            for par in tomas:
                ruta = buscar(par[idx])
                if ruta is None:
                    print("  falta", par[idx])
                    continue
                cs, sr = cortar(ruta)
                segs += [remuestrear(s, sr) for s in cs]
            if not segs:
                continue
            # MISMO VOLUMEN PARA TODAS: se normaliza el pico del arma entera a -1 dBFS (sin aplastar la
            # diferencia entre sus propios disparos)
            pico = max(np.abs(s).max() for s in segs)
            g = 0.89 / pico if pico > 0 else 1.0
            for n, s in enumerate(segs, 1):
                s = s * g
                if tipo == "lejos":
                    s = s.mean(axis=1, keepdims=True)      # de lejos, mono: lo posiciona el 3D
                sf.write(os.path.join(dst, arma, "%s%d.ogg" % (tipo, n)), s.astype(np.float32), SR_OUT,
                         format="OGG", subtype="VORBIS")
                total += 1
            print("%-16s %-5s %2d disparos" % (arma, tipo, len(segs)))
    mb = sum(os.path.getsize(f) for f in glob.glob(os.path.join(dst, "*", "*.ogg"))) / 1048576
    print("total %d disparos, %.1f MB en %s" % (total, mb, dst))


if __name__ == "__main__":
    main()
