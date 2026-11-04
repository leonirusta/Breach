"""TRUENOS SINTETIZADOS PARA LA TORMENTA (tormenta.gd). Nada de audio comercial: se generan aqui desde cero.

Un trueno de verdad son dos cosas:
  * el CHASQUIDO: el rayo cerca rasga el aire. Ruido blanco muy agudo, un golpe seco de decimas de segundo.
    Lejos no llega (el aire se come los agudos antes que los graves).
  * el RETUMBAR: el sonido de todo el canal del rayo llegando a trozos, cada trozo desde otra distancia.
    Ruido marron (grave) pasado por un paso bajo, con varios golpes sordos que se solapan y se apagan.

Tres variantes: trueno_cerca (chasquido + retumbar fuerte), trueno_medio y trueno_lejos (solo el rumor grave).

    python tools/generar_truenos.py      ->  godot/sounds/tormenta/trueno_*.wav
"""
import os
import wave

import numpy as np
from scipy import signal

SR = 22050
RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SALIDA = os.path.join(RAIZ, "godot", "sounds", "tormenta")


def escribir(nombre, x):
    os.makedirs(SALIDA, exist_ok=True)
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.92
    ruta = os.path.join(SALIDA, nombre + ".wav")
    with wave.open(ruta, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes((x * 32767).astype(np.int16).tobytes())
    print("escrito", ruta, "%.1f s" % (len(x) / SR))


def paso_bajo(x, hz, orden=4):
    b, a = signal.butter(orden, hz / (SR * 0.5), "low")
    return signal.lfilter(b, a, x)


def paso_alto(x, hz, orden=2):
    b, a = signal.butter(orden, hz / (SR * 0.5), "high")
    return signal.lfilter(b, a, x)


def ruido_marron(n, rng):
    x = np.cumsum(rng.standard_normal(n))
    x = x - signal.savgol_filter(x, 2001, 2)       # quita la deriva lenta: se queda el rumor
    return x / (np.max(np.abs(x)) + 1e-9)


def retumbar(dur, corte_hz, golpes, rng):
    n = int(dur * SR)
    t = np.arange(n) / SR
    base = paso_bajo(ruido_marron(n, rng), corte_hz)
    env = np.zeros(n)
    # varios golpes sordos, cada uno desde otro trozo del rayo: llegan escalonados y se solapan
    for k in range(golpes):
        t0 = rng.uniform(0.0, dur * 0.45) if k else 0.0
        amp = rng.uniform(0.45, 1.0) if k else 1.0
        sube = rng.uniform(0.04, 0.25)
        baja = rng.uniform(0.8, 2.4)
        tt = t - t0
        e = np.where(tt < 0, 0.0, np.minimum(tt / sube, 1.0) * np.exp(-np.maximum(tt - sube, 0.0) / baja))
        env += amp * e
    # un temblor lento encima: el retumbar no es liso, "rueda"
    temblor = 1.0 + 0.35 * paso_bajo(rng.standard_normal(n), 6.0, 2) / 0.05
    env *= np.clip(temblor, 0.3, 1.7)
    # cola final que se apaga del todo
    env *= np.clip((dur - t) / 1.2, 0.0, 1.0)
    return base * env


def chasquido(dur, rng):
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = paso_alto(rng.standard_normal(n), 1800.0)
    # dos o tres restallidos muy seguidos, como se oye un rayo que cae al lado
    env = np.zeros(n)
    for t0 in (0.0, rng.uniform(0.02, 0.06), rng.uniform(0.08, 0.14)):
        tt = t - t0
        env += np.where(tt < 0, 0.0, np.exp(-tt / 0.045))
    return x * env


def trueno(nombre, dur, corte_hz, golpes, con_chasquido, semilla):
    rng = np.random.default_rng(semilla)
    x = retumbar(dur, corte_hz, golpes, rng)
    if con_chasquido:
        c = chasquido(0.6, rng)
        x[: len(c)] += c * 0.55 * np.max(np.abs(x))
    # entrada un pelin suave para que no haga clic
    x[:64] *= np.linspace(0.0, 1.0, 64)
    escribir(nombre, x)


if __name__ == "__main__":
    trueno("trueno_cerca", 7.0, 380.0, 6, True, 11)
    trueno("trueno_medio", 8.0, 240.0, 7, False, 23)
    trueno("trueno_lejos", 9.0, 140.0, 8, False, 37)
