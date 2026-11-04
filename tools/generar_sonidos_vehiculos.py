"""Los sonidos de los vehiculos, sintetizados desde cero -> godot/sounds/vehiculos/*.wav

    python tools/generar_sonidos_vehiculos.py

Nada de material con derechos: un motor es un tren de explosiones (una por cilindro y vuelta) con su
resonancia y su ruido de admision, y eso se escribe. Cada archivo es un BUCLE de un segundo exacto al que
el juego le cambia el tono segun las vueltas (vehiculo.gd), asi que la frecuencia base tiene que caber un
numero entero de veces en el segundo o el bucle chasquea.

    motor_coche   cuatro cilindros, grave y redondo
    motor_moto    dos cilindros, mas agudo y sucio
    motor_heli    turbina (silbido agudo) + el pala-pala del rotor
"""
import math
import os
import struct
import wave

import numpy as np

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SALIDA = os.path.join(RAIZ, "godot", "sounds", "vehiculos")
SR = 22050                      # de sobra para un motor, y la mitad de memoria en el movil


def escribir(nombre, x):
    x = np.clip(x, -1.0, 1.0)
    datos = (x * 32000).astype("<i2").tobytes()
    ruta = os.path.join(SALIDA, nombre + ".wav")
    with wave.open(ruta, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(datos)
    print("[sonidos] %s (%.2f s)" % (os.path.basename(ruta), len(x) / SR))


def explosiones(n_por_seg, dureza, cola):
    """Tren de explosiones de cilindro: n por segundo, cada una un golpe que decae."""
    t = np.arange(SR) / SR
    fase = (t * n_por_seg) % 1.0
    golpe = np.exp(-fase * cola)
    rng = np.random.default_rng(7)
    ruido = rng.standard_normal(SR)
    # el golpe hace sonar un resonador: se aproxima con dos senos que decaen con el propio golpe
    cuerpo = (np.sin(2 * math.pi * 90 * t) * 0.6 + np.sin(2 * math.pi * 145 * t) * 0.4) * golpe
    aspero = ruido * golpe * dureza
    return cuerpo * 0.8 + aspero * 0.5


def suavizar(x, n):
    k = np.ones(n) / n
    return np.convolve(x, k, mode="same")


def main():
    os.makedirs(SALIDA, exist_ok=True)
    t = np.arange(SR) / SR

    # --- COCHE: cuatro cilindros a 25 vueltas por segundo (entero: el bucle cierra)
    coche = explosiones(50, 0.55, 9.0)
    coche += np.sin(2 * math.pi * 25 * t) * 0.25          # el zumbido grave de fondo
    coche = suavizar(coche, 5)
    escribir("motor_coche", coche / (np.max(np.abs(coche)) + 1e-9) * 0.85)

    # --- MOTO: dos cilindros, mas rapido y mas sucio
    moto = explosiones(80, 0.9, 6.0)
    moto += np.sin(2 * math.pi * 40 * t) * 0.18
    moto += np.sin(2 * math.pi * 160 * t) * 0.10
    moto = suavizar(moto, 3)
    escribir("motor_moto", moto / (np.max(np.abs(moto)) + 1e-9) * 0.85)

    # --- HELICOPTERO: turbina + palas
    rng = np.random.default_rng(11)
    turbina = suavizar(rng.standard_normal(SR), 4) * 0.35
    turbina += np.sin(2 * math.pi * 1200 * t) * 0.12 + np.sin(2 * math.pi * 1830 * t) * 0.07
    palas = explosiones(20, 0.7, 14.0) * 1.1              # el pala-pala
    heli = suavizar(turbina + palas, 3)
    escribir("motor_heli", heli / (np.max(np.abs(heli)) + 1e-9) * 0.85)


main()
