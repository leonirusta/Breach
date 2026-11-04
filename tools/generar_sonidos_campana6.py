#!/usr/bin/env python3
"""SONIDOS DEL EPISODIO 6 ("LA CUMBRE"), SINTETIZADOS (como los de los episodios 3, 4 y 5).

  hielo/cruje, hielo/rompe · mina/ventilador (bucle) · quitanieves/motor (bucle), quitanieves/bocina,
  quitanieves/pala · robot/motor, robot/pitido · alud/estruendo · viento/ventisca (bucle) · campana/c1..c4 ·
  laser/zumbido (bucle), laser/alarma · espejo/giro, espejo/receptor · soplete/llama (bucle) ·
  teleferico/motor (bucle), teleferico/pilona

Uso:  python tools/generar_sonidos_campana6.py
"""
import os
import sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generar_sonidos_campana3 as S   # noqa: E402
import generar_sonidos_campana4 as S4  # noqa: E402

SR = S.SR
rng = np.random.default_rng(20260930)
t_ = S.t_
ruido = S.ruido
paso_bajo = S.paso_bajo
golpe_metal = S.golpe_metal
motor = S.motor
bucle = S.bucle
guardar = S.guardar
pegar = S4.pegar
banda = S4.banda
paso_alto = S4.paso_alto


def crujido(seg, densidad, grave):
    """Chasquidos de hielo: impulsos sueltos filtrados, cada vez mas seguidos."""
    t = t_(seg)
    y = np.zeros_like(t)
    n = int(seg * densidad)
    for i in range(n):
        s = (i / max(1, n)) ** 0.7 * seg * 0.95
        f = rng.uniform(900, 3200) * (0.5 if grave else 1.0)
        tt = t_(0.06)
        c = np.sin(2 * np.pi * f * tt) * np.exp(-tt * rng.uniform(60, 140)) + ruido(len(tt)) * np.exp(-tt * 400) * 0.6
        pegar(y, c, s, rng.uniform(0.3, 1.0))
    return y


def campana(f0, seg=5.0):
    """Una campana de bronce: parciales inarmonicos (hum, prima, tercera menor, quinta, octava...) que decaen."""
    t = t_(seg)
    y = np.zeros_like(t)
    for m, a, d in ((0.5, 0.5, 0.35), (1.0, 1.0, 0.6), (1.183, 0.6, 0.9), (1.506, 0.45, 1.1), (2.0, 0.5, 1.3),
                    (2.514, 0.25, 1.8), (2.662, 0.2, 2.0), (3.011, 0.18, 2.4), (4.166, 0.1, 3.2)):
        y += a * np.sin(2 * np.pi * f0 * m * t + rng.uniform(0, 6)) * np.exp(-d * t)
    y += ruido(len(t)) * np.exp(-t * 80) * 0.3
    return y


def main():
    print("== sonidos del episodio 6 ->", os.path.abspath(S.RAIZ))
    # EL HIELO: el crujido que avisa y la placa que revienta (con el chapuzon)
    guardar("hielo", "cruje1", crujido(1.3, 26, False) + paso_bajo(ruido(len(t_(1.3))), 0.995) * 0.4)
    t = t_(2.2)
    y = crujido(0.35, 40, True)
    y = np.concatenate([y, np.zeros(len(t) - len(y))])
    y += paso_bajo(ruido(len(t)), 0.9) * np.exp(-t * 4.0) * 1.2
    agua = banda(ruido(len(t)), 0.6, 0.97) * np.clip((t - 0.15) / 0.1, 0, 1) * np.exp(-np.clip(t - 0.25, 0, 9) * 2.4)
    y += agua * 1.4
    guardar("hielo", "rompe1", y)
    # EL VENTILADOR de la mina (bucle): pala grave que gira y aire
    t = t_(4.0)
    pala = np.sin(2 * np.pi * 14.0 * t) ** 2
    y = banda(ruido(len(t)), 0.35, 0.985) * (0.6 + 0.4 * pala) + motor(4.0, 50.0, armonicos=5, zumbido=0.1) * 0.25
    guardar("mina", "ventilador1", bucle(y))
    # LA QUITANIEVES: diesel al ralenti (bucle), la bocina y la pala rascando
    t = t_(4.0)
    y = motor(4.0, 38.0, armonicos=10, zumbido=0.5, vibrato=0.03)
    golpes = (np.sin(2 * np.pi * 19.0 * t) > 0.6).astype(float)
    y = y * (0.7 + 0.3 * paso_bajo(golpes, 0.9))
    guardar("quitanieves", "motor1", bucle(y))
    t = t_(1.4)
    y = (np.sign(np.sin(2 * np.pi * 311 * t)) * 0.5 + np.sign(np.sin(2 * np.pi * 392 * t)) * 0.5) * S.env(len(t), 0.02, 0.2)
    guardar("quitanieves", "bocina1", paso_bajo(y, 0.5))
    t = t_(2.0)
    y = banda(ruido(len(t)), 0.3, 0.9) * (0.6 + 0.4 * np.abs(np.sin(2 * np.pi * 3.0 * t))) * S.env(len(t), 0.1, 0.5)
    y += paso_bajo(ruido(len(t)), 0.98) * 0.8
    guardar("quitanieves", "pala1", y)
    # EL ROBOT: servos que giran y el pitido de la consola
    t = t_(0.9)
    f = 700 + 300 * np.sin(2 * np.pi * 1.1 * t)
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.4 + np.sign(np.sin(2 * np.pi * np.cumsum(f * 0.5) / SR)) * 0.15
    y += paso_bajo(ruido(len(t)), 0.9) * 0.4
    guardar("robot", "motor1", y * S.env(len(t), 0.05, 0.15))
    t = t_(0.2)
    guardar("robot", "pitido1", np.sin(2 * np.pi * 2100 * t) * S.env(len(t), 0.005, 0.05))
    # LA AVALANCHA: un estruendo grave que crece, rueda y se apaga (9 s)
    t = t_(9.0)
    forma = np.clip(t / 1.5, 0, 1) ** 1.5 * np.exp(-np.clip(t - 5.0, 0, 9) * 0.9)
    y = paso_bajo(ruido(len(t)), 0.992) * 3.0 + paso_bajo(ruido(len(t)), 0.95) * 0.8
    y += crujido(9.0, 30, True) * 0.4
    guardar("alud", "estruendo1", np.tanh(y * forma * 1.5))
    # LA VENTISCA (bucle): viento que silba con rafagas
    t = t_(8.0)
    rafaga = 0.55 + 0.45 * np.sin(2 * np.pi * 0.13 * t) * np.sin(2 * np.pi * 0.31 * t + 1.0)
    y = banda(ruido(len(t)), 0.5, 0.995) * rafaga
    silbo = np.sin(2 * np.pi * np.cumsum(620 + 180 * np.sin(2 * np.pi * 0.2 * t)) / SR) * 0.08 * rafaga ** 3
    guardar("viento", "ventisca1", bucle(y + silbo))
    # LAS CUATRO CAMPANAS de la espadaña (re, fa, la, do: se distinguen bien de oido)
    for i, f0 in enumerate((293.7, 349.2, 440.0, 523.3)):
        guardar("campana", "c%d1" % (i + 1), campana(f0))
    # LOS LASERES: el zumbido (bucle) y la alarma
    t = t_(3.0)
    y = np.sin(2 * np.pi * 120 * t) * 0.4 + np.sin(2 * np.pi * 240 * t) * 0.2 + banda(ruido(len(t)), 0.2, 0.9) * 0.05
    guardar("laser", "zumbido1", bucle(y))
    t = t_(2.4)
    f = np.where((t * 4.0) % 1.0 < 0.5, 880.0, 660.0)
    guardar("laser", "alarma1", np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR)) * 0.5 * S.env(len(t), 0.01, 0.1))
    # LOS ESPEJOS: el giro (clac metalico) y el receptor que se enciende
    y = golpe_metal(0.6, 620.0, 0.4)
    pegar(y, S4.clic(0.05, 1800.0), 0.0, 0.8)
    guardar("espejo", "giro1", y)
    t = t_(1.6)
    y = np.zeros_like(t)
    for k, f in enumerate((660.0, 880.0, 1320.0)):
        tt = t_(1.6 - k * 0.15)
        pegar(y, np.sin(2 * np.pi * f * tt) * np.exp(-tt * 3.0), k * 0.15, 0.6)
    guardar("espejo", "receptor1", y)
    # EL SOPLETE (bucle): el siseo del gas ardiendo
    t = t_(3.0)
    y = banda(ruido(len(t)), 0.15, 0.7) * 0.6 + paso_bajo(ruido(len(t)), 0.97) * 0.8
    y *= 0.85 + 0.15 * np.sin(2 * np.pi * 7.0 * t)
    guardar("soplete", "llama1", bucle(y))
    # EL TELEFERICO: el motor de la rueda (bucle) y el golpe de la cabina al pasar por una pilona
    t = t_(4.0)
    y = motor(4.0, 70.0, armonicos=6, zumbido=0.2, vibrato=0.005) * 0.6
    y += np.sin(2 * np.pi * 420 * t) * 0.05 + banda(ruido(len(t)), 0.3, 0.95) * 0.3
    guardar("teleferico", "motor1", bucle(y))
    t = t_(1.5)
    y = golpe_metal(1.5, 140.0, 1.4) * 0.8
    pegar(y, golpe_metal(1.2, 160.0, 1.2) * 0.6, 0.22)
    guardar("teleferico", "pilona1", y)
    print("== hecho")


if __name__ == "__main__":
    main()
