"""ZONA PLAZA DEL JEFE: la explanada central del puesto de cuarentena, de noche, donde sale el Goliat.

Es el ruedo de la oleada 10: un monstruo de 7 m contra el jugador. Todo el diseno gira en torno a eso:

  - RUEDO LIMPIO de unos 25 m de diametro en el centro (nada mas alto de 0,9 m dentro de el): el bicho
    tiene que poder cargar y el jugador rodar sin engancharse. El atrezo gordo vive del radio 12,5 m
    para fuera.
  - CUATRO ENTRADAS de 8 m de ancho en el centro de cada lado, a cielo abierto: son las que conectan con
    el resto del mapa (avenida norte, avenida sur, calle de los cuarteles y calle del hospital de
    disposicion.py caen justo ahi). Nada se apunta dentro de esos pasillos: ni atrezo, ni cables, ni una
    caja. La comprobacion `_en_pasillo` lo garantiza para todo lo que se coloca al azar.
  - COBERTURAS SUELTAS (sacos, jerseys, escombro) a distancias distintas, siempre ABIERTAS: nidos en U con
    la boca hacia el centro y barreras en tramos con huecos. Ningun corral cerrado donde el A* de las
    criaturas se quede encerrado ni donde el jugador se refugie sin salida.

Historia que cuenta el decorado (por que esta cada cosa): aqui aterrizo el helicoptero de evacuacion, el
suelo se abrio (el CRATER descentrado, por donde salio el bicho), y lo que quedo del destacamento acabo en
la FOSA COMUN del lado oeste. De ahi los rastros de sangre: todos van de las entradas hacia el crater.

Medidas y reglas que se respetan (A* de voxels del motor, celda 0,8 m, agente 1,8 m, sube 0,8 m):
  - Suelo del ruedo plano a `suelo_y`; el crater baja 0,6 m con pendiente suave (se entra y se sale
    andando) y no mas: a 0,4 m esta la roca indestructible y un pozo mas hondo seria una trampa.
  - El muelle de carga sube 1,2 m pero SIEMPRE con rampa: da altura al jugador sin dejar isla inalcanzable.
  - Nada flotando: cada pieza apoya en el suelo o en otra que apoya.

Disenado para 48 x 48 m (el rect de disposicion.PLAZA). Si llega otro rect se centra y las posiciones se
escalan; los objetos mantienen su tamano real.
"""
import math

import objetos as O
from lienzo import MATERIALES

W = D = 48.0                 # tamano de diseno de la zona
R_RUEDO = 12.5               # radio limpio para la pelea (25 m de diametro)
MEDIA_ENTRADA = 4.0          # semiancho de cada entrada: 8 m > los 5 m que pide el lienzo

# Materiales del integrador (tools/generar_mapa_pve.py::EXTRA): aqui se registran con los MISMOS valores
# para que la vista previa, que solo conoce el lienzo, no reviente al usarlos. setdefault: si el
# integrador ya los puso, mandan los suyos.
for _n, _v in (("suelo_tierra", ((56, 46, 36), "suelo")),
               ("suelo_barro", ((40, 33, 26), "suelo")),
               ("suelo_grava", ((70, 66, 60), "suelo")),
               ("suelo_ceniza", ((44, 42, 40), "suelo")),
               ("suelo_asfalto", ((34, 34, 36), "suelo_duro")),
               ("suelo_hormigon", ((88, 86, 80), "suelo_duro")),
               ("suelo_sangre", ((66, 12, 9), "suelo")),
               ("pintura_amarilla", ((132, 104, 28), "suelo_pintura")),
               ("plastico_negro", ((22, 22, 24), "tela")),
               ("goma", ((20, 20, 22), "goma"))):
    MATERIALES.setdefault(_n, _v)


def construir(l, rect, suelo_y, rng):
    x0, z0, x1, z1 = rect
    cx, cz = (x0 + x1) * 0.5, (z0 + z1) * 0.5
    S = suelo_y
    # escala de las POSICIONES si el rect es menor que el diseno (los objetos no se deforman)
    esc = min(1.0, (x1 - x0) / W, (z1 - z0) / D)
    if esc < 0.999:
        print("zona_plaza: AVISO rect %.1f x %.1f menor que el diseno 48 x 48 (posiciones al %.0f %%)"
              % (x1 - x0, z1 - z0, esc * 100))
    hx, hz = (x1 - x0) * 0.5, (z1 - z0) * 0.5

    # --- coordenadas locales: u a lo ancho (+x), v a lo hondo (+z), h altura sobre el suelo ---------------
    def X(u):
        return cx + u * esc

    def Z(v):
        return cz + v * esc

    def C(u0, h0, v0, u1, h1, v1, mat="hormigon", hueco=False):
        l.caja(X(u0), S + h0, Z(v0), X(u1), S + h1, Z(v1), mat, hueco)

    def ELI(u, h, v, rx, ry, rz, mat="tierra", hueco=False):
        l.elipsoide(X(u), S + h, Z(v), rx, ry, rz, mat, hueco)

    def LIN(u0, h0, v0, u1, h1, v1, g, mat="metal"):
        l.linea(X(u0), S + h0, Z(v0), X(u1), S + h1, Z(v1), g, mat)

    def CIL(u, h, v, r, alto, mat="metal", eje="y"):
        l.cilindro(X(u), S + h, Z(v), r, alto, mat, eje=eje)

    def CUNA(u0, h0, v0, u1, h1, v1, hacia, mat="hormigon"):
        l.cuna(X(u0), S + h0, Z(v0), X(u1), S + h1, Z(v1), hacia, mat)

    def R(a, b):
        return a + (b - a) * rng.random()

    # --- el crater, que manda en la altura del suelo -------------------------------------------------------
    # Se define ANTES que las reglas de sitio porque el suelo dentro de la cuenca esta mas bajo: cualquier
    # cosa apuntada a la altura del suelo general ahi dentro quedaria FLOTANDO sobre el hoyo.
    CU, CV, CR = -8.5, 6.5, 7.0          # centro y radio de la cuenca (el eje v va al 86 %)
    HONDO = 0.6                          # 0,4 m por debajo esta la roca indestructible del integrador
    FU, FV0, FV1 = -18.5, 8.0, 19.0      # fosa comun: la zanja tambien baja 0,6 m (O.trinchera)

    def t_crater(u, v):
        """Distancia al centro del crater normalizada al borde: < 1 es dentro de la cuenca."""
        return math.hypot((u - CU) / CR, (v - CV) / (CR * 0.86))

    def fondo(u, v):
        """Altura del suelo REAL en ese punto (0 en la explanada, negativa dentro del crater). Todo lo que
        se coloque en la cuenca tiene que apoyarse aqui."""
        t = t_crater(u, v)
        return -HONDO * math.sqrt(max(0.0, 1.0 - t * t)) if t < 1.0 else 0.0

    # --- reglas de sitio ----------------------------------------------------------------------------------
    def _en_pasillo(u, v, margen=0.0):
        """Dentro de una de las cuatro entradas de 8 m (o su margen): ahi no va NADA."""
        # el pasillo se reserva desde 9 m del centro hacia fuera: asi ni el atrezo del borde del ruedo
        # asoma por la boca de la entrada
        m = MEDIA_ENTRADA + margen
        return (abs(u) <= m and abs(v) >= 9.0) or (abs(v) <= m and abs(u) >= 9.0)

    def sitio(u, v, margen=0.8, ruedo=True, crater=True):
        """True si ahi se puede poner atrezo: fuera de los pasillos, dentro del rect, (si `ruedo`) fuera del
        circulo de pelea y (si `crater`) fuera de la cuenca, donde el suelo esta mas bajo."""
        if _en_pasillo(u, v, margen):
            return False
        if abs(u * esc) > hx - 1.2 - margen or abs(v * esc) > hz - 1.2 - margen:
            return False
        if crater and (t_crater(u, v) < 1.06 or (abs(u - FU) < 2.4 and FV0 - 1.0 < v < FV1 + 1.0)):
            return False
        return not (ruedo and math.hypot(u, v) < R_RUEDO + margen)

    def libre_tramo(u0, v0, u1, v1, margen=0.6):
        """Para las piezas LARGAS (carteles, cintas, vallas, barreras): ningun punto de su recorrido puede
        caer en una entrada. Comprobar solo el centro no vale: un cartel mide 8 m y se cuela en el pasillo."""
        n = max(2, int(math.hypot(u1 - u0, v1 - v0) / 0.5))
        for i in range(n + 1):
            t = i / n
            if _en_pasillo(u0 + (u1 - u0) * t, v0 + (v1 - v0) * t, margen):
                return False
        return True

    def buscar(ruedo=True, rmin=0.0, rmax=22.0, margen=0.8, intentos=40):
        """Punto al azar valido para un objeto suelto."""
        for _ in range(intentos):
            a, r = R(0, math.tau), math.sqrt(R(0, 1)) * (rmax - rmin) + rmin
            u, v = math.cos(a) * r, math.sin(a) * r
            if sitio(u, v, margen, ruedo):
                return u, v
        return None

    # ======================================================================================================
    # 1. SUELO: losa de hormigon sucio agrietada sobre la tierra del integrador
    # ======================================================================================================
    # La losa sustituye los 0,2 m de arriba: material "suelo_*" para que ancle (lo que se apoye en ella no
    # se cae) y sea destructible (los pisotones del Goliat abren crateres de verdad).
    C(-hx / esc + 0.8, -0.2, -hz / esc + 0.8, hx / esc - 0.8, 0.0, hz / esc - 0.8, "suelo_hormigon")
    # juntas de la explanada: rejilla suave, para que no sea una sabana lisa
    for k in range(-3, 4):
        C(k * 6.0 - 0.06, -0.06, -22.0, k * 6.0 + 0.06, 0.0, 22.0, "suelo_asfalto")
        C(-22.0, -0.06, k * 6.0 - 0.06, 22.0, 0.0, k * 6.0 + 0.06, "suelo_asfalto")
    # grietas ramificadas que salen del crater (el suelo se abrio desde abajo). Arrancan en el LABIO y tiran
    # hacia fuera: dentro de la cuenca el suelo esta mas bajo y una grieta plana ahi quedaria en el aire.
    for _ in range(26):
        a = R(0, math.tau)
        px, pv = CU + math.cos(a) * CR * 1.02, CV + math.sin(a) * CR * 0.88
        for _k in range(4):
            a += R(-0.8, 0.8)
            qx, qv = px + math.cos(a) * R(0.8, 2.6), pv + math.sin(a) * R(0.8, 2.6)
            if abs(qx) > 22.0 or abs(qv) > 22.0 or t_crater(qx, qv) < 1.0:
                break
            LIN(px, -0.05, pv, qx, -0.05, qv, 0.06, "suelo_barro")
            px, pv = qx, qv
    # quemaduras: lo que ardio aquella noche (ceniza y carbon a ras de suelo, no son escalones)
    for _ in range(16):
        p = buscar(ruedo=False, rmax=21.0, margen=0.4)
        if p:
            r = R(1.4, 4.2)
            ELI(p[0], -0.05, p[1], r, 0.07, r * R(0.5, 0.95), "suelo_ceniza")
            if rng.random() < 0.5:
                ELI(p[0] + R(-1, 1), -0.05, p[1] + R(-1, 1), r * 0.45, 0.07, r * 0.4, "carbon")
    # charcos de sangre seca por toda la plaza
    for _ in range(18):
        p = buscar(ruedo=False, rmax=21.0, margen=0.4)
        if p:
            l.charco_sangre(X(p[0]), Z(p[1]), S, R(0.6, 2.4), rng, "sangre_seca" if rng.random() < 0.8 else "sangre")
    # rastros: de cada entrada hacia el crater, como si hubieran arrastrado a los heridos. Mueren en el
    # LABIO de la cuenca (las manchas son planas: dentro del hoyo flotarian sobre el fondo).
    for ue, ve in ((0.0, -20.0), (0.0, 20.0), (-20.0, 0.0), (20.0, 0.0)):
        ax = math.atan2(ve - CV, ue - CU)
        fx, fv = CU + math.cos(ax) * CR * 1.12, CV + math.sin(ax) * CR * 0.98
        O.rastro_sangre(l, [(X(ue * 0.9), Z(ve * 0.9)), (X((ue * 0.5 + fx) / 2 + R(-2, 2)), Z((ve * 0.5 + fv) / 2 + R(-2, 2))),
                            (X(fx), Z(fv))], S, rng)

    # ======================================================================================================
    # 2. CRATER descentrado: por aqui salio el bicho
    # ======================================================================================================
    # 0,6 m de hondo como mucho: a 0,4 m esta la roca indestructible del integrador y, sobre todo, un pozo
    # mas profundo seria una trampa para el jugador en plena pelea. Bordes en cuenca: se entra andando.
    ELI(CU, 0.0, CV, CR, HONDO, CR * 0.86, "tierra", hueco=True)
    ELI(CU, -HONDO - 0.02, CV, CR * 0.92, 0.12, CR * 0.78, "suelo_barro")  # fondo embarrado
    # TODO lo que va dentro de la cuenca apoya en fondo(u, v) y se entierra 0,1 m: si se apuntara a la altura
    # del suelo general quedaria flotando sobre el hoyo (es lo que delataba la validacion del integrador).
    for _ in range(30):                                                   # labio de tierra y hormigon roto
        a, rr = R(0, math.tau), R(0.95, 1.15)
        u, v = CU + math.cos(a) * CR * rr, CV + math.sin(a) * CR * 0.86 * rr
        s = R(0.3, 0.9)
        ELI(u, fondo(u, v) + R(-0.05, 0.15), v, s * 1.4, s * 0.55, s,
            rng.choice(("tierra", "hormigon_sucio", "hormigon_manchado")))
    for _ in range(14):                                                   # losas levantadas hacia fuera
        a = R(0, math.tau)
        u, v = CU + math.cos(a) * CR * 0.8, CV + math.sin(a) * CR * 0.7
        base = fondo(u, v) - 0.1
        CUNA(u - 1.0, base, v - 0.7, u + 1.0, base + R(0.45, 0.9), v + 0.7,
             rng.choice(("+x", "-x", "+z", "-z")), "hormigon_sucio")
    for _ in range(10):                                                   # hierros retorcidos asomando
        a = R(0, math.tau)
        u, v = CU + math.cos(a) * CR * R(0.3, 0.9), CV + math.sin(a) * CR * 0.86 * R(0.3, 0.8)
        base = fondo(u, v)
        LIN(u, base - 0.15, v, u + R(-0.8, 0.8), base + R(0.3, 1.1), v + R(-0.8, 0.8), 0.06, "metal_oxidado")
    for _ in range(26):                                                   # cascotes por la cuenca
        a, rr = R(0, math.tau), math.sqrt(R(0, 1))
        u, v = CU + math.cos(a) * CR * 0.85 * rr, CV + math.sin(a) * CR * 0.75 * rr
        s = R(0.15, 0.55)
        base = fondo(u, v) - 0.1
        C(u - s, base, v - s * 0.7, u + s, base + s * R(0.5, 1.4), v + s * 0.7,
          rng.choice(("hormigon_sucio", "ladrillo", "metal_oxidado", "hormigon_manchado")))
    for _ in range(5):                                                    # huesos en el fondo
        a, rr = R(0, math.tau), R(0.2, 0.7)
        u, v = CU + math.cos(a) * CR * rr, CV + math.sin(a) * CR * 0.86 * rr
        base = fondo(u, v)
        ELI(u, base + 0.06, v, R(0.15, 0.35), 0.1, R(0.1, 0.25), "hueso")
        LIN(u, base + 0.04, v, u + R(-0.6, 0.6), base + 0.06, v + R(-0.6, 0.6), 0.08, "hueso")

    # ======================================================================================================
    # 3. HELICOPTERO ESTRELLADO: la pieza que se ve desde cualquier entrada
    # ======================================================================================================
    # Va en el cuadrante noreste, fuera del ruedo. Morro clavado hacia el centro, cola partida hacia fuera.
    def helicoptero(bu, bv, giro):
        """Pecio propio (no el de objetos.py, que mide 24 m y no cabe aqui): fuselaje de 9 m, cola partida
        y palas dobladas. `giro` en radianes: u local del aparato hacia donde mira el morro."""
        co, si = math.cos(giro), math.sin(giro)

        def P(a, b):                       # (adelante, lateral) del aparato -> (u, v) de la zona
            return bu + a * co - b * si, bv + a * si + b * co

        def cajaH(a0, h0, b0, a1, h1, b1, mat, hueco=False):
            (ua, va), (ub, vb) = P(a0, b0), P(a1, b1)
            l.caja(min(X(ua), X(ub)), S + h0, min(Z(va), Z(vb)), max(X(ua), X(ub)), S + h1, max(Z(va), Z(vb)), mat, hueco)

        def eliH(a, h, b, ra, rv, rb, mat, hueco=False):
            u, v = P(a, b)
            # el elipsoide no gira: se toma el radio mayor en cada eje segun cuanto pesa el giro
            rx = abs(ra * co) + abs(rb * si)
            rz = abs(ra * si) + abs(rb * co)
            ELI(u, h, v, rx, rv, rz, mat, hueco)

        def linH(a0, h0, b0, a1, h1, b1, g, mat):
            (ua, va), (ub, vb) = P(a0, b0), P(a1, b1)
            LIN(ua, h0, va, ub, h1, vb, g, mat)

        # marca de quemado y surco de la panza al arrastrarse
        eliH(0.0, -0.05, 0.0, 9.0, 0.08, 6.0, "suelo_ceniza")
        eliH(-5.0, -0.05, 0.0, 5.0, 0.08, 1.6, "suelo_barro")
        # fuselaje: panza apoyada en el suelo, escorado, con el costado abierto
        eliH(0.0, 1.15, 0.0, 3.6, 1.2, 1.35, "chapa_verde")
        eliH(3.1, 0.95, -0.15, 1.6, 0.95, 1.0, "chapa_verde")            # morro hundido
        eliH(3.6, 0.9, 0.0, 0.9, 0.55, 0.8, "vidrio", hueco=True)        # cabina reventada
        cajaH(-1.2, 0.35, 0.9, 1.6, 2.1, 1.5, "chapa_verde", hueco=True)  # porton lateral abierto
        cajaH(-1.2, 0.2, -1.0, 1.6, 0.35, 1.0, "carbon")                  # bodega quemada
        for _ in range(10):                                               # chapa retorcida y hollin
            eliH(R(-3.0, 3.4), R(0.9, 2.2), rng.choice((-1.3, 1.3)), R(0.4, 0.9), R(0.25, 0.5), 0.14,
                 rng.choice(("metal_negro", "carbon", "metal_oxidado")))
        # patines
        for s in (-1, 1):
            linH(-2.0, 0.07, s * 1.15, 2.4, 0.07, s * 1.15, 0.14, "metal_negro")
            linH(-1.2, 0.07, s * 1.15, -1.0, 0.6, s * 0.75, 0.1, "metal_negro")
            linH(1.6, 0.07, s * 1.15, 1.4, 0.6, s * 0.75, 0.1, "metal_negro")
        # cola: partida, el tramo final caido de lado en el suelo
        linH(-3.2, 1.3, 0.0, -6.4, 0.95, 0.35, 0.62, "chapa_verde")
        linH(-6.8, 0.3, 0.5, -9.8, 0.28, 1.5, 0.5, "chapa_verde")
        cajaH(-10.4, 0.0, 1.2, -9.6, 1.6, 1.4, "chapa_verde")             # deriva vertical clavada
        for k in range(3):                                                # rotor de cola doblado
            a = k * math.tau / 3 + 0.5
            linH(-9.9, 0.9, 1.35, -9.9 + math.cos(a) * 0.7, 0.9 + math.sin(a) * 0.7, 1.35, 0.07, "metal_negro")
        # mastil y palas: una entera doblada, otra clavada en el suelo, otra partida a lo lejos
        cajaH(-0.4, 2.3, -0.45, 0.6, 2.9, 0.45, "metal_negro")
        linH(0.1, 2.9, 0.0, 5.6, 1.1, 2.6, 0.16, "metal_negro")
        linH(0.1, 2.9, 0.0, -3.4, 1.4, -3.6, 0.16, "metal_negro")
        linH(0.1, 2.85, 0.0, -1.2, 0.15, 4.6, 0.16, "metal_negro")
        cajaH(6.2, 0.0, -4.6, 7.0, 1.9, -4.2, "metal_negro")              # pala clavada de punta
        linH(6.6, 1.9, -4.4, 9.4, 0.1, -5.6, 0.15, "metal_negro")
        # lo que quedo dentro: fuego mortecino en la bodega y dos tripulantes fuera
        cajaH(-0.6, 0.35, -0.5, 0.4, 0.5, 0.4, "luz_calida")
        u, v = P(0.0, 0.0)
        l.luz(X(u), S + 1.1, Z(v), (255, 120, 45), 1.5, 10.0)
        for _ in range(2):
            u, v = P(R(2.0, 5.0), R(-2.5, 2.5))
            O.cadaver(l, X(u), Z(v), S, rng)
        # restos desperdigados alrededor
        for _ in range(16):
            u, v = P(R(-10.0, 8.0), R(-5.5, 5.5))
            if not sitio(u, v, 0.3, ruedo=False):
                continue
            s = R(0.15, 0.5)
            C(u, 0.0, v, u + s * 2, R(0.06, 0.3), v + s,
              rng.choice(("chapa_verde", "metal_negro", "metal_oxidado", "carbon")))

    helicoptero(13.0, -11.5, math.radians(205))

    # ======================================================================================================
    # 4. MUELLE DE CARGA: la altura que puede usar el jugador
    # ======================================================================================================
    # Plataforma de 1,2 m con rampa larga: el jugador gana angulo sobre el bicho, y la rampa (pendiente
    # suave) deja que las criaturas suban, asi que no es una isla segura.
    mu0, mv0, mu1, mv1 = 6.0, -21.5, 19.0, -15.0
    C(mu0, 0.0, mv0, mu1, 1.2, mv1, "hormigon_sucio")
    C(mu0 + 0.3, 1.15, mv0 + 0.3, mu1 - 0.3, 1.2, mv1 - 0.3, "hormigon_manchado")   # losa de arriba sucia
    CUNA(mu0 - 5.0, 0.0, mv0 + 1.0, mu0, 1.2, mv1 - 1.0, "+x", "hormigon_sucio")    # rampa al oeste
    for u in (mu0 + 1.0, (mu0 + mu1) / 2, mu1 - 1.0):                               # bordillo a franjas
        C(u - 0.8, 1.2, mv1 - 0.12, u + 0.8, 1.35, mv1, "pintura_amarilla")
    # barandilla rota: postes que quedan y un tramo caido sobre la plataforma
    for k in range(6):
        u = mu0 + 1.0 + k * 2.3
        if rng.random() < 0.7:
            CIL(u, 1.2, mv1 - 0.25, 0.07, R(0.6, 1.1), "metal_oxidado")
    LIN(mu0 + 1.0, 2.2, mv1 - 0.25, mu0 + 5.8, 2.15, mv1 - 0.25, 0.06, "metal_oxidado")
    LIN(mu1 - 3.2, 2.2, mv1 - 0.25, mu1 - 1.0, 1.3, mv1 - 0.25, 0.06, "metal_oxidado")
    # carga abandonada encima
    for k in range(5):
        u, v = mu0 + 2.0 + k * 2.6, mv0 + R(1.5, 4.0)
        O.caja_madera(l, X(u), Z(v), S + 1.2, R(0.7, 1.1), R(0.6, 0.9), rng.choice(("madera", "madera_podrida")))
    O.palet(l, X(mu1 - 2.0), Z(mv0 + 1.4), S + 1.2, "x")
    for k in range(3):
        O.barril(l, X(mu0 + 1.6 + k * 1.0), Z(mv1 - 1.6), S + 1.2, "plastico_amarillo", None, rng)
    l.charco_sangre(X(mu0 + 4.0), Z(mv1 - 2.0), S + 1.2, 1.1, rng, "sangre_seca")
    O.cadaver(l, X(mu0 + 4.4), Z(mv1 - 2.4), S + 1.2, rng, "x")

    # ======================================================================================================
    # 5. FOSA COMUN: la zanja con las bolsas, al oeste
    # ======================================================================================================
    O.trinchera(l, X(FU) - 1.6, Z(FV0), X(FU) + 1.6, Z(FV1), S, rng)
    for k in range(7):                                   # bolsas dentro, en el fondo de la zanja
        O.bolsa_cadaver(l, X(FU) + R(-0.7, 0.7), Z(FV0 + 1.8 + k * 1.2), S - 0.6, "z", rng)
    for k in range(4):                                   # y las que no llegaron a bajar, en el borde
        O.bolsa_cadaver(l, X(FU + R(2.4, 3.6)), Z(FV0 + 1.0 + k * 2.6), S, "z", rng)
    for _ in range(12):                                  # cal, huesos y restos en los BORDES de la zanja
        # nunca sobre la zanja: ahi el suelo esta 0,6 m mas abajo y una mancha plana flotaria
        u = FU + rng.choice((-1, 1)) * R(2.2, 3.6)
        v = R(FV0, FV1)
        ELI(u, -0.04, v, R(0.4, 1.1), 0.06, R(0.4, 1.0), "tela_blanca" if rng.random() < 0.5 else "ceniza")
        if rng.random() < 0.5:
            ELI(u + R(-0.6, 0.6), 0.05, v + R(-1, 1), R(0.12, 0.3), R(0.08, 0.16), R(0.1, 0.22), "hueso")
    ELI(FU - 2.8, 0.3, (FV0 + FV1) / 2, 1.3, 0.35, 2.6, "tierra")         # monton de tierra de la excavacion
    ELI(FU - 2.6, 0.5, (FV0 + FV1) / 2 - 1.4, 0.9, 0.3, 1.2, "tierra")
    # pala: la hoja clavada EN LA TIERRA y el mango saliendo de ella (si la hoja va arriba, se queda suelta)
    C(FU - 3.1, -0.05, FV0 + 0.8, FU - 2.7, 0.45, FV0 + 1.2, "metal_oxidado")
    LIN(FU - 2.9, 0.3, FV0 + 1.0, FU - 2.3, 1.5, FV0 + 1.6, 0.09, "madera_podrida")
    O.cinta(l, [(X(FU + 4.2), Z(FV0 - 0.8)), (X(FU + 4.6), Z(FV0 + 5.0)),
                (X(FU + 4.0), Z(FV0 + 11.0)), (X(FU + 4.4), Z(FV1 + 0.5))], S, rng)
    O.cartel(l, X(FU + 5.0), Z(FV0 + 2.0), S, "ZONA", "z", 1, 0.16, "plastico_rojo", "tela_blanca", rng)

    # ======================================================================================================
    # 6. VEHICULOS Y TORRE CAIDA
    # ======================================================================================================
    O.camion(l, X(-20.0), Z(-14.0), S, "x", 1, rng, "quemado")            # camion calcinado, lado noroeste
    O.jeep(l, X(15.5), Z(13.0), S, "z", -1, rng, "volcado")               # jeep volcado, lado sureste
    O.jeep(l, X(-14.5), Z(-6.0), S, "x", 1, rng, "quemado")
    for _ in range(3):                                                     # lo que ardio con ellos
        O.barril(l, X(-18.0 + R(-2, 2)), Z(-11.0 + R(-2, 2)), S, "metal_oxidado", rng.choice(("x", "z")), rng)

    # torre de focos derribada: base partida, celosia tumbada y focos reventados en el suelo
    tu, tv = 18.5, 17.5
    C(tu - 0.8, 0.0, tv - 0.8, tu + 0.8, 0.35, tv + 0.8, "hormigon_sucio")
    for s in (-1, 1):
        LIN(tu + s * 0.5, 0.35, tv - 0.5, tu + s * 0.3, 1.1, tv - 0.3, 0.1, "metal")   # muñones retorcidos
    du, dv = -0.62, -0.78                                                  # direccion en la que cayo
    largo = 13.0
    for s in (-1, 1):                                                      # cuatro largueros de la celosia
        for t in (-1, 1):
            LIN(tu + s * 0.42 * -dv, 0.35 + (0 if t < 0 else 0.75), tv + s * 0.42 * du,
                tu + du * largo + s * 0.18 * -dv, 0.5 + (0 if t < 0 else 0.4), tv + dv * largo + s * 0.18 * du,
                0.09, "metal")
    for k in range(1, 9):                                                  # travesaños y diagonales
        t0, t1 = (k - 1) / 9, k / 9
        for a, b in ((t0, t1), (t1, t0)):
            LIN(tu + du * largo * a + 0.4 * -dv, 0.4 + 0.6 * (k % 2), tv + dv * largo * a + 0.4 * du,
                tu + du * largo * b - 0.4 * -dv, 0.4 + 0.6 * ((k + 1) % 2), tv + dv * largo * b - 0.4 * du,
                0.06, "metal")
    eu, ev = tu + du * largo, tv + dv * largo                              # cabezal: un foco roto y otro vivo
    C(eu - 1.0, 0.0, ev - 1.0, eu + 1.0, 0.25, ev + 1.0, "metal_negro")
    for s in (-1, 1):
        C(eu + s * 0.55 - 0.3, 0.25, ev - 0.3, eu + s * 0.55 + 0.3, 0.75, ev + 0.3, "metal_negro")
    # De los cuatro focos de la torre aguanta UNO. Como la torre esta tumbada, ya no alumbra desde arriba:
    # barre la explanada a ras de suelo en la direccion en la que cayo, y el jugador ve cruzar por delante
    # la sombra larga del bicho. Es la luz que dibuja la plaza entera.
    foco_u, foco_v = eu - 0.55 + du * 0.34, ev + dv * 0.34
    C(foco_u - 0.22, 0.3, foco_v - 0.22, foco_u + 0.22, 0.7, foco_v + 0.22, "luz_fria")
    # la bombilla, justo delante de la lente (no dentro de la carcasa) y a su altura: 0,5 m del suelo
    # casi horizontal (unos 7 grados de caida): desde 0,5 m de altura el eje toca el suelo a 4 m y el cono
    # se estira en una franja larga. Con mas inclinacion se quedaria en un charco de luz a sus pies.
    l.luz(X(foco_u + du * 0.5), S + 0.5, Z(foco_v + dv * 0.5), (150, 200, 255), 1.6, 22.0, (du, -0.12, dv), 25)
    for _ in range(14):                                                    # cristal reventado alrededor
        u, v = eu + R(-2.2, 2.2), ev + R(-2.2, 2.2)
        C(u, 0.0, v, u + 0.12, 0.05, v + 0.12, "vidrio")
    LIN(tu, 0.5, tv, eu, 0.35, ev, 0.04, "metal_negro")                    # cable de alimentacion
    LIN(eu, 0.3, ev, eu + R(2, 4), 0.02, ev + R(-3, 3), 0.04, "metal_negro")

    # ======================================================================================================
    # 7. COBERTURAS: nidos de sacos y barreras, a distancias distintas y SIEMPRE abiertas
    # ======================================================================================================
    # Nidos en U con la boca al centro: se entra y se sale, no son corrales cerrados.
    for au, av, radio in ((-13.5, -13.5, 2.4), (13.5, 5.5, 2.2), (-6.0, 16.5, 2.0), (8.5, -16.0, 2.3)):
        if sitio(au, av, 2.6, ruedo=False):
            O.parapeto_circular(l, X(au), Z(av), S, radio, rng, abertura=math.atan2(-av, -au))
            if rng.random() < 0.6:
                O.barril(l, X(au + R(-1.4, 1.4)), Z(av + R(-1.4, 1.4)), S, "metal_oxidado", None, rng)
    # Muretes de sacos sueltos mirando al centro (parapeto de tiro, sin cerrar nada)
    for au, av, ang in ((-16.0, -8.0, 0.0), (16.5, -9.0, 0.0), (9.0, 16.0, math.pi / 2), (-14.0, -18.0, math.pi / 2)):
        dxu, dzv = math.cos(ang) * 2.6, math.sin(ang) * 2.6
        if not (sitio(au, av, 2.4, ruedo=False) and libre_tramo(au - dxu, av - dzv, au + dxu, av + dzv, 1.0)):
            continue
        O.sacos(l, X(au - dxu), Z(av - dzv), X(au + dxu), Z(av + dzv), S, R(0.75, 1.1), rng)
    # Barreras jersey en tramos cortos con hueco de 2 m entre ellas: cortan la carga del bicho, no el paso.
    for au, av, eje, n in ((-11.0, -4.5, "z", 2), (11.0, 9.5, "z", 2), (-4.5, 11.5, "x", 2), (5.0, -11.0, "x", 2),
                           (-19.5, -14.5, "z", 2), (19.5, 6.0, "z", 2)):
        for k in range(n):
            bu = au + (k * 5.6 if eje == "x" else 0.0)
            bv = av + (k * 5.6 if eje == "z" else 0.0)
            eu, ev = bu + (3.6 if eje == "x" else 0.0), bv + (3.6 if eje == "z" else 0.0)
            # se comprueba el TRAMO entero (3,6 m), no solo su centro: un extremo podria colarse en la entrada
            if libre_tramo(bu, bv, eu, ev, 1.0) and sitio((bu + eu) / 2, (bv + ev) / 2, 1.0, ruedo=False):
                O.jersey(l, X(bu), Z(bv), S, 3.6, eje, rng)
    # Un par de erizos checos sueltos, a media distancia
    for au, av in ((-9.5, -9.0), (9.0, -6.5), (6.5, 9.5)):
        if sitio(au, av, 1.2, ruedo=False):
            O.erizo(l, X(au), Z(av), S)

    # ======================================================================================================
    # 8. HOGUERA APAGADA, LUCES Y CARTELES
    # ======================================================================================================
    # Hoguera de escombro consumida: corro de piedras, vigas carbonizadas y ceniza. Ya no da luz (por eso
    # la plaza esta a oscuras); las unicas luces son dos bidones y una baliza roja.
    hu, hv = -9.0, -16.5                                 # apartada de la entrada norte: mide 6 m de ancho
    ELI(hu, -0.05, hv, 3.0, 0.07, 2.8, "suelo_ceniza")
    for k in range(14):
        a = k / 14 * math.tau
        ELI(hu + math.cos(a) * 2.3, 0.12, hv + math.sin(a) * 2.2, R(0.28, 0.45), R(0.16, 0.28), R(0.25, 0.4),
            rng.choice(("hormigon_sucio", "grava", "ladrillo")))
    for k in range(7):                                   # vigas caidas hacia dentro, como un tipi hundido
        a = k / 7 * math.tau + 0.3
        LIN(hu + math.cos(a) * 2.1, 0.05, hv + math.sin(a) * 2.0, hu + math.cos(a) * 0.4, R(0.5, 0.9),
            hv + math.sin(a) * 0.4, R(0.12, 0.2), "carbon")
    ELI(hu, 0.15, hv, 1.2, 0.25, 1.1, "carbon")
    l.escombros(X(hu), Z(hv), S, 3.4, 14, rng, ("carbon", "ceniza", "madera_podrida"))

    O.bidon_fuego(l, X(-16.5), Z(-17.5), S)              # las dos unicas hogueras vivas: naranja y temblona
    O.bidon_fuego(l, X(17.0), Z(11.5), S)
    O.baliza_roja(l, X(-7.5), Z(19.0), S)                # la roja, a un lado de la entrada sur
    # Relleno ambiental del ruedo (no hay farol: es solo para que se lea la silueta del jefe). Se baja a 0,2
    # ahora que el foco tumbado barre la plaza: un cono concentra mucho mas y si no se lavaba la escena.
    l.luz(X(0.0), S + 2.2, Z(0.0), (255, 150, 80), 0.2, 16.0)

    # Carteles de peligro en dos entradas y cinta de cuarentena cruzando (rota, se pasa por debajo)
    # Los carteles miden 8-10 m de ancho: van AL LADO de las entradas, nunca cruzandolas (el pasillo tiene
    # que quedar libre hasta 8 m de alto para que quepa el bicho).
    O.cartel(l, X(5.2), Z(-20.5), S, "PELIGRO", "x", 1, 0.18, "plastico_rojo", "plastico_amarillo", rng)
    O.cartel(l, X(-5.2), Z(20.5), S, "CUARENTENA", "x", -1, 0.16, "plastico_rojo", "tela_blanca", rng)
    O.cinta(l, [(X(-13.0), Z(-19.2)), (X(-9.0), Z(-19.8)), (X(-5.4), Z(-19.0))], S, rng, rota=0.5)
    O.cinta(l, [(X(19.0), Z(5.6)), (X(19.6), Z(9.0)), (X(19.0), Z(12.4))], S, rng, rota=0.5)

    # Valla metalica derribada, de adorno en dos bordes (nada que cierre paso: tramos sueltos y tumbados)
    for au, av, eje in ((-21.0, 12.5, "z"), (21.0, -14.0, "z"), (12.0, 21.0, "x")):
        if not sitio(au, av, 1.0, ruedo=False):
            continue
        for k in range(3):
            bu = au + (k * 2.2 if eje == "x" else R(-0.3, 0.3))
            bv = av + (k * 2.2 if eje == "z" else R(-0.3, 0.3))
            if not libre_tramo(bu - 1.0, bv - 1.0, bu + 1.0, bv + 1.0, 0.8):
                continue
            if rng.random() < 0.45:                      # tramo tumbado en el suelo: se pisa
                C(bu - (1.0 if eje == "x" else 0.9), 0.0, bv - (0.9 if eje == "x" else 1.0),
                  bu + (1.0 if eje == "x" else 0.9), 0.12, bv + (0.9 if eje == "x" else 1.0), "metal_oxidado")
            else:                                        # tramo en pie, inclinado
                C(bu - (1.0 if eje == "x" else 0.06), 0.0, bv - (0.06 if eje == "x" else 1.0),
                  bu + (1.0 if eje == "x" else 0.06), R(1.2, 1.8), bv + (0.06 if eje == "x" else 1.0), "metal_oxidado")

    # ======================================================================================================
    # 8b. GARITA DERRUIDA, ARBOLES QUEMADOS Y UN COCHE: siluetas para que el borde no sea una explanada sosa
    # ======================================================================================================
    # Garita de control: tres paredes y el techo medio hundido. La cara que mira al centro esta ABIERTA de
    # par en par, asi que da cobertura pero no es un corral donde encerrarse (ni donde se atasque el A*).
    gu, gv = -8.5, 15.0
    C(gu - 1.8, -0.2, gv - 1.6, gu + 1.8, 0.0, gv + 1.6, "hormigon")                  # solera
    C(gu - 1.8, 0.0, gv - 1.6, gu + 1.8, 2.6, gv + 1.6, "hormigon_sucio")             # macizo...
    C(gu - 1.5, 0.0, gv - 1.3, gu + 1.5, 2.7, gv + 1.3, "hormigon", hueco=True)       # ...y vaciado
    C(gu - 1.2, 0.0, gv - 1.8, gu + 1.2, 2.4, gv - 1.2, "hormigon", hueco=True)       # boca hacia el centro
    C(gu + 1.4, 0.9, gv - 0.6, gu + 2.0, 1.9, gv + 0.6, "hormigon", hueco=True)       # ventanuco lateral
    C(gu - 1.8, 2.6, gv - 1.6, gu + 0.6, 2.8, gv + 1.6, "hormigon_manchado")          # media losa de techo
    for _ in range(5):                                                                # la otra media, caida
        u, v = gu + R(-1.2, 2.6), gv + R(-1.0, 1.0)
        C(u, 0.0, v, u + R(0.6, 1.4), R(0.15, 0.4), v + R(0.5, 1.1), "hormigon_manchado")
    l.charco_sangre(X(gu), Z(gv), S, 1.2, rng, "sangre_seca")
    O.cadaver(l, X(gu + 0.4), Z(gv + 0.5), S, rng, "z")
    l.escombros(X(gu), Z(gv + 2.4), S, 2.2, 10, rng)

    # Arboles calcinados: puro esqueleto negro contra el cielo, lo que mejor se lee de noche
    for au, av, alt in ((-12.5, 16.5, 5.0), (12.5, 18.5, 4.4), (-20.0, -8.5, 5.6), (19.5, -7.0, 4.8)):
        if sitio(au, av, 1.4, ruedo=False):
            O.arbol_muerto(l, X(au), Z(av), S, alt, rng, quemado=True)

    # Coche de un evacuado que no llego a salir, calcinado contra el borde
    O.coche(l, X(-14.0), Z(20.0), S, "x", 1, rng, "quemado")
    l.charco_sangre(X(-11.0), Z(19.0), S, 1.4, rng, "sangre_seca")

    # ======================================================================================================
    # 9. ATREZO MENUDO: cajas, bidones, munición, escombro y cables
    # ======================================================================================================
    for _ in range(20):
        p = buscar(ruedo=False, rmin=2.0, rmax=21.0, margen=1.0)
        if p:
            O.caja_madera(l, X(p[0]), Z(p[1]), S, R(0.6, 1.2), R(0.5, 0.9),
                          rng.choice(("madera", "madera_podrida", "lona")))
        if p and rng.random() < 0.45:                     # de dos en dos: una apilada encima
            O.caja_madera(l, X(p[0] + R(-0.3, 0.3)), Z(p[1] + R(-0.3, 0.3)), S + 0.5, R(0.5, 0.8), R(0.4, 0.6),
                          "madera_podrida")
    for _ in range(22):
        p = buscar(ruedo=False, rmin=2.0, rmax=21.0, margen=0.9)
        if p:
            O.barril(l, X(p[0]), Z(p[1]), S, rng.choice(("metal_oxidado", "chapa_verde", "plastico_amarillo")),
                     rng.choice((None, None, "x", "z")), rng)
    for _ in range(18):                                  # cajas de municion: chapa baja, se saltan
        p = buscar(ruedo=False, rmin=2.0, rmax=21.0, margen=0.6)
        if p:
            u, v = p
            C(u - 0.35, 0.0, v - 0.2, u + 0.35, 0.28, v + 0.2, "chapa_verde")
            C(u - 0.36, 0.28, v - 0.21, u + 0.36, 0.34, v + 0.21, "metal_negro")
    for _ in range(14):
        p = buscar(ruedo=False, rmin=3.0, rmax=21.0, margen=1.2)
        if p:
            O.escombros_grandes(l, X(p[0]), Z(p[1]), S, R(1.0, 2.2), rng)
    for _ in range(12):                                  # montoncitos de escombro menudo
        p = buscar(ruedo=False, rmin=2.0, rmax=21.0, margen=0.5)
        if p:
            l.escombros(X(p[0]), Z(p[1]), S, R(0.8, 2.0), rng.randint(5, 12), rng)
    for _ in range(10):                                  # cables sueltos arrastrandose por el suelo
        p = buscar(ruedo=False, rmin=4.0, rmax=20.0, margen=0.6)
        if not p:
            continue
        pu, pv = p
        for _k in range(3):
            qu, qv = pu + R(-3.0, 3.0), pv + R(-3.0, 3.0)
            if not sitio(qu, qv, 0.4, ruedo=False):
                break
            LIN(pu, 0.04, pv, qu, 0.04, qv, 0.05, "metal_negro")
            pu, pv = qu, qv
    for _ in range(14):                                  # hierros de armar clavados
        p = buscar(ruedo=False, rmin=3.0, rmax=21.0, margen=0.5)
        if p:
            LIN(p[0], 0.0, p[1], p[0] + R(-0.5, 0.5), R(0.5, 1.4), p[1] + R(-0.5, 0.5), 0.05, "metal_oxidado")
    for _ in range(6):                                   # algun cadaver mas, lejos del ruedo
        p = buscar(ruedo=False, rmin=6.0, rmax=20.0, margen=1.0)
        if p:
            O.cadaver(l, X(p[0]), Z(p[1]), S, rng)
    # dentro del ruedo solo cosas planas: manchas y alguna caja de municion aplastada (no estorban al bicho)
    for _ in range(8):
        a, r = R(0, math.tau), R(2.0, R_RUEDO - 1.0)
        u, v = math.cos(a) * r, math.sin(a) * r
        if _en_pasillo(u, v, 0.5):
            continue
        l.charco_sangre(X(u), Z(v), S, R(0.5, 1.6), rng, "sangre_seca")
        if rng.random() < 0.4:
            C(u - 0.3, 0.0, v - 0.18, u + 0.3, 0.16, v + 0.18, "metal_negro")

    # ======================================================================================================
    # 10. PUNTOS DE JUEGO
    # ======================================================================================================
    # El jefe sale del crater: se apunta en su labio, en suelo plano y despejado, no en el fondo.
    l.punto(X(-4.0), S, Z(1.0), "jefe")
    # Criaturas: en las cuatro entradas, dentro del pasillo libre (llegan desde el resto del mapa).
    for u, v in ((0.0, -20.5), (0.0, 20.5), (-20.5, 0.0), (20.5, 0.0)):
        l.punto(X(u), S, Z(v), "criatura")
    # y un par en las esquinas, para que las oleadas no entren siempre por lo mismo
    for u, v in ((-17.0, -17.0), (17.0, 17.0)):
        l.punto(X(u), S, Z(v), "criatura")
