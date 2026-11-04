#!/usr/bin/env python3
"""SONIDOS DE LAS HABILIDADES (habilidad.gd, 2026-09-28), SINTETIZADOS como los de la campaña.

  hab/grito (el grito de guerra del puñetazo) · hab/invisible_on, hab/invisible_off · hab/carga (el puño cargandose), hab/punetazo (el golpe y la onda) ·
  hab/salto (el despegue), hab/golpe (el golpe al suelo) · hab/gancho (el disparo del garfio), hab/clavado (se
  clava), hab/tirar (el tiron, la cuerda silbando) · hab/listo (la habilidad vuelve a estar lista)
  (2026-09-30, los efectos de cine) hab/zumbido (la carga del puñetazo), hab/anillo (los anillos de la onda),
  hab/estallido (la onda contra una pared), hab/descenso (la caida del salto); punetazo y golpe, rehechos

Uso:  python tools/generar_sonidos_habilidades.py
"""
import os
import sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generar_sonidos_campana3 as S   # noqa: E402
import generar_sonidos_campana4 as S4  # noqa: E402

SR = S.SR
t_ = S.t_
ruido = S.ruido
paso_bajo = S.paso_bajo
env = S.env
guardar = S.guardar
banda = S4.banda
pegar = S4.pegar
rng = np.random.default_rng(20260928)


def barrido(seg, f0, f1, forma="seno"):
    t = t_(seg)
    f = np.geomspace(f0, f1, len(t))
    fase = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(fase) if forma == "seno" else np.sign(np.sin(fase)) * 0.5


def resonador(x, f, bw):
    """un formante: resonador de dos polos"""
    r = np.exp(-np.pi * bw / SR)
    c = 2 * r * np.cos(2 * np.pi * f / SR)
    y = np.zeros_like(x)
    y1 = y2 = 0.0
    g = 1 - r
    for i in range(len(x)):
        v = g * x[i] + c * y1 - r * r * y2
        y[i] = v
        y2, y1 = y1, v
    return y


def grito(seg=1.25):
    """EL GRITO DE GUERRA del puñetazo: una voz de hombre "AAAARGH" que sube, se rompe y tiembla. Pulsos glotales
    (armonicos hasta 5 kHz con el tono subiendo de 135 a 190 Hz y cayendo al final, vibrato y temblor) pasados por los
    formantes de la A abierta, aliento por los mismos formantes, y la voz rota (ruido que modula la amplitud)."""
    t = t_(seg)
    sube = np.clip(t / 0.35, 0, 1)
    cae = np.clip((t - seg + 0.35) / 0.35, 0, 1)
    f0 = 135 + 55 * (sube ** 0.6) - 40 * cae
    f0 = f0 * (1 + 0.025 * np.sin(2 * np.pi * 6.5 * t) + 0.012 * paso_bajo(rng.standard_normal(len(t)), 0.995) * 8)
    fase = 2 * np.pi * np.cumsum(f0) / SR
    fuente = np.zeros_like(t)
    for k in range(1, 36):
        fuente += np.sin(k * fase) / (k ** 1.05) * (f0 * k < 5000)
    rota = 1 + 0.45 * paso_bajo(rng.standard_normal(len(t)), 0.9) * 4
    fuente *= rota
    aliento = ruido(len(t)) * 0.35
    x = fuente + aliento
    y = resonador(x, 760, 110) * 1.0 + resonador(x, 1180, 130) * 0.7 + resonador(x, 2550, 200) * 0.35         + resonador(x, 3400, 260) * 0.2
    y *= env(len(t), 0.07, 0.35)
    return np.tanh(y / (np.max(np.abs(y)) + 1e-9) * 2.2)


def fase_de(f):
    """la fase de una frecuencia que cambia (array): sin esto un barrido se desafina"""
    return 2 * np.pi * np.cumsum(f) / SR


def punetazo():
    """EL PUÑETAZO: un chasquido seco con un tintineo de oro, el golpe de aire muy grave que cae de 110 a 28 Hz, el
    'whomp' de la energia (saturado) y una cola de estruendo que se aleja con la onda (1,8 s)"""
    t = t_(1.8)
    y = ruido(len(t)) * np.exp(-t * 60.0) * 1.6
    y += np.sin(2 * np.pi * 3100.0 * t) * np.exp(-t * 30.0) * 0.25
    y += np.sin(fase_de(np.geomspace(110.0, 28.0, len(t)))) * np.exp(-t * 2.6) * 2.2
    w = np.sin(fase_de(np.geomspace(240.0, 55.0, len(t)))) * np.exp(-t * 7.0)
    y += np.tanh(w * 4.0) * 0.8
    y += paso_bajo(ruido(len(t)), 0.975) * np.exp(-t * 1.5) * 6.0
    y += banda(ruido(len(t)), 0.35, 0.93) * np.exp(-((t - 0.28) ** 2) / 0.04) * 0.9
    return np.tanh(y * 1.3)


def zumbido():
    """LA CARGA (1,25 s: del grito al golpe): un zumbido grave que sube (48 -> 120 Hz) con sus armonicos, chisporroteo de
    energia cada vez mas denso, un silbido agudo que sube, y al final se hincha y se corta en seco (el golpe)"""
    seg = 1.25
    t = t_(seg)
    f = np.geomspace(48.0, 120.0, len(t))
    ph = fase_de(f)
    y = np.sin(ph) + 0.55 * np.sin(2 * ph) + 0.3 * np.sin(3 * ph) + 0.15 * np.sin(5 * ph)
    y *= 0.75 + 0.25 * np.sin(fase_de(np.geomspace(5.0, 26.0, len(t))))
    y += np.sin(fase_de(np.geomspace(700.0, 2600.0, len(t)))) * np.linspace(0.0, 0.22, len(t)) ** 1.5
    chis = np.zeros_like(t)
    for k in range(70):
        u = (k / 70.0) ** 0.6
        d = t_(0.018)
        pegar(chis, banda(ruido(len(d)), 0.3, 0.9) * np.exp(-d * 260.0) * (0.3 + 0.9 * u), u * (seg - 0.05))
    y += chis * 0.8
    y *= np.linspace(0.25, 1.0, len(t)) ** 1.3
    y *= env(len(t), 0.12, 0.012)
    return np.tanh(y * 1.2)


def anillos():
    """LOS ANILLOS DE LA ONDA: cuatro 'vuum' seguidos (aire que cae de tono y un tono que baja), cada uno mas lejos y
    mas flojo, con un golpe grave debajo (1,1 s)"""
    t = t_(1.1)
    y = np.zeros_like(t)
    for k in range(4):
        d = t_(0.45)
        v = banda(ruido(len(d)), 0.55 - 0.08 * k, 0.9) * np.exp(-d * 9.0)
        v += np.sin(fase_de(np.geomspace(900.0 - 120 * k, 180.0, len(d)))) * np.exp(-d * 11.0) * 0.5
        pegar(y, v * (1.0 - 0.2 * k), 0.07 * k)
    y += np.sin(fase_de(np.geomspace(80.0, 35.0, len(t)))) * np.exp(-t * 5.0) * 1.2
    return np.tanh(y * 1.3) * env(len(t), 0.004, 0.2)


def estallido():
    """LA ONDA CONTRA UNA PARED: la piedra que revienta (golpe grave y crujido), un tintineo de energia y los cascotes
    que caen (1,5 s)"""
    t = t_(1.5)
    y = np.sin(fase_de(np.geomspace(95.0, 30.0, len(t)))) * np.exp(-t * 4.0) * 1.8
    y += ruido(len(t)) * np.exp(-t * 25.0) * 1.5
    cruje = np.zeros_like(t)
    for k in range(30):
        d = t_(0.025)
        pegar(cruje, ruido(len(d)) * np.exp(-d * 150.0) * (1.0 - k / 30.0), 0.01 + k * 0.012 + rng.uniform(0, 0.01))
    y += cruje * 1.1
    y += np.sin(2 * np.pi * 2300.0 * t) * np.exp(-t * 14.0) * 0.18
    lluvia = np.zeros_like(t)
    for k in range(60):
        u = rng.uniform(0.15, 1.35)
        d = t_(0.02)
        pegar(lluvia, banda(ruido(len(d)), 0.2, 0.7) * np.exp(-d * 300.0) * np.exp(-u * 1.8), u)
    y += lluvia * 0.9
    y += paso_bajo(ruido(len(t)), 0.98) * np.exp(-t * 2.0) * 4.0
    return np.tanh(y * 1.3)


def golpe_suelo():
    """EL GOLPE AL SUELO: un subgrave enorme (70 -> 22 Hz), el crack del impacto, el crujido de la piedra, el anillo de
    energia que se abre y la LLUVIA DE CASCOTES que cae durante dos segundos (2,6 s)"""
    t = t_(2.6)
    y = np.sin(fase_de(np.geomspace(72.0, 22.0, len(t)))) * np.exp(-t * 1.9) * 2.4
    y += ruido(len(t)) * np.exp(-t * 40.0) * 1.8
    crujido = np.zeros_like(t)
    for k in range(45):
        d = t_(0.03)
        pegar(crujido, ruido(len(d)) * np.exp(-d * 120.0) * (1.0 - k / 45.0), 0.01 + k * 0.028 + rng.uniform(0, 0.01))
    y += crujido * 1.0
    y += np.sin(fase_de(np.geomspace(1500.0, 600.0, len(t)))) * np.exp(-t * 6.0) * 0.15
    lluvia = np.zeros_like(t)
    for k in range(140):
        u = rng.uniform(0.25, 2.3)
        d = t_(0.025)
        g = np.exp(-(u - 0.25) * 1.1) * rng.uniform(0.4, 1.0)
        pegar(lluvia, banda(ruido(len(d)), rng.uniform(0.1, 0.4), 0.8) * np.exp(-d * rng.uniform(180, 380)) * g, u)
    y += lluvia * 1.2
    y += paso_bajo(ruido(len(t)), 0.985) * np.exp(-t * 1.1) * 7.0
    return np.tanh(y * 1.25)


def descenso():
    """LA CAIDA: un silbido que sube (como algo que cae hacia ti) y el viento cada vez mas fuerte (0,9 s)"""
    t = t_(0.9)
    y = np.sin(fase_de(np.geomspace(450.0, 1300.0, len(t)))) * np.linspace(0.1, 0.5, len(t))
    y += banda(ruido(len(t)), 0.4, 0.95) * np.linspace(0.3, 1.4, len(t))
    return y * env(len(t), 0.1, 0.05)


def main():
    print("== sonidos de las habilidades ->", os.path.abspath(S.RAIZ))
    guardar("hab", "grito1", grito())
    # INVISIBLE: un brillo de cristal que sube (y el mismo al reves al volver a verse)
    t = t_(0.9)
    y = barrido(0.9, 300.0, 2400.0) * 0.35 + barrido(0.9, 450.0, 3600.0) * 0.2
    y += banda(ruido(len(t)), 0.2, 0.9) * np.linspace(0.1, 0.8, len(t)) * 0.6
    y *= 0.6 + 0.4 * np.sin(2 * np.pi * 18.0 * t)
    y *= env(len(t), 0.05, 0.35)
    guardar("hab", "invisible_on1", y)
    guardar("hab", "invisible_off1", y[::-1].copy() * env(len(t), 0.02, 0.3))
    # EL PUÑO CARGANDOSE: un zumbido grave que sube y tiembla (0,85 s)
    t = t_(0.85)
    f = np.geomspace(55.0, 180.0, len(t))
    fase = 2 * np.pi * np.cumsum(f) / SR
    y = np.sin(fase) + 0.5 * np.sin(2 * fase) + 0.25 * np.sin(3 * fase)
    y *= 0.7 + 0.3 * np.sin(2 * np.pi * np.geomspace(6.0, 30.0, len(t)) * t)
    y += paso_bajo(ruido(len(t)), 0.9) * np.linspace(0.2, 1.4, len(t))
    y *= env(len(t), 0.1, 0.03)
    guardar("hab", "carga1", np.tanh(y * 1.2))
    # EL PUÑETAZO (2026-09-30, rehecho para los efectos de cine): chasquido, caida de graves, el golpe de energia y la cola
    guardar("hab", "punetazo1", punetazo())
    # LA CARGA DE ENERGIA, desde el grito hasta el golpe; LOS ANILLOS de la onda; LA ONDA CONTRA UNA PARED
    guardar("hab", "zumbido1", zumbido())
    guardar("hab", "anillo1", anillos())
    guardar("hab", "estallido1", estallido())
    # EL SALTO: un empujon de aire hacia arriba
    t = t_(0.6)
    y = banda(ruido(len(t)), 0.5, 0.97) * np.exp(-t * 5.0) * 1.5
    y += np.sin(2 * np.pi * np.geomspace(80.0, 200.0, len(t)) * t) * np.exp(-t * 8.0) * 0.8
    guardar("hab", "salto1", y * env(len(t), 0.01, 0.2))
    # EL GOLPE AL SUELO (rehecho): subgrave enorme, crujido de piedra, el anillo de energia y la LLUVIA DE CASCOTES
    guardar("hab", "golpe1", golpe_suelo())
    # LA CAIDA DEL SALTO: el silbido que sube y el viento
    guardar("hab", "descenso1", descenso())
    # EL GANCHO: el disparo (chasquido metalico y aire) y la cuerda saliendo
    t = t_(0.5)
    y = S.golpe_metal(0.5, 900.0, 0.4) * 0.7 + banda(ruido(len(t)), 0.3, 0.9) * np.exp(-t * 9.0) * 0.8
    y += barrido(0.5, 1800.0, 900.0) * np.exp(-t * 6.0) * 0.2
    guardar("hab", "gancho1", y)
    # SE CLAVA: un clonc metalico
    guardar("hab", "clavado1", S.golpe_metal(0.6, 420.0, 0.6))
    # EL TIRON: la cuerda tensa silbando y el aire (1,2 s)
    t = t_(1.2)
    y = barrido(1.2, 700.0, 1600.0) * 0.18 + banda(ruido(len(t)), 0.3, 0.9) * np.linspace(0.3, 1.0, len(t))
    y *= env(len(t), 0.03, 0.25)
    guardar("hab", "tirar1", y)
    # LISTA OTRA VEZ: dos notas limpias hacia arriba
    t = t_(0.35)
    y = np.zeros_like(t)
    for i, f in enumerate((880.0, 1320.0)):
        d = t_(0.2)
        pegar(y, np.sin(2 * np.pi * f * d) * np.exp(-d * 14.0), i * 0.09)
    guardar("hab", "listo1", y)


if __name__ == "__main__":
    main()
