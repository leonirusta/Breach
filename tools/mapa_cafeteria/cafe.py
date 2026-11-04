"""LA CAFETERIA (lamina: VISTA PRINCIPAL, VISTA DESDE ABAJO, PLANOS, INTERIOR y TERRAZA).

Edificio de esquina, dos plantas, en CAFE = (21,2, 18,0) - (39,2, 32,0): la fachada SUR da a la plaza y la OESTE a la
calle principal (la esquina de la vista principal es la suroeste).

PLANTA BAJA (suelo 1,4): pilastras de sillar, escaparates de madera oscura con su zocalo, puertas acristaladas y un
toldo rojo corrido en las dos fachadas. Dentro: suelo de barro cocido, BARRA en L con su encimera de marmol, la
cafetera, el expositor de pasteles y los estantes de botellas en la pared de ladrillo visto; mesas con sillas (algunas
rojas), dos COLUMNAS DE HORMIGON con su VIGA que llevan el muro de la planta alta, techo de tablas con viguetas a la
vista, lamparas de pantalla negra, la cocina con su puerta roja y la ESCALERA de madera a la planta alta.

PLANTA ALTA (5,0): el SALON cerrado en la esquina (x 21,2-28,4, todo el fondo) con su tejado de tejas a la vista por
dentro (tejas / tablas / pares) y, al este, la TERRAZA (x 28,4-39,2): baldosa, pretiles de piedra con barandilla de
hierro y jardineras con flores, mesas con sombrillas, una PERGOLA de madera con tejadillo de tejas sobre la mitad norte
(debajo llega la escalera de dentro) y guirnaldas de bombillas. Encima del salon, en la misma esquina de la vista
principal, los dos antepechos de ladrillo con el ROTULO "CAFÉ" rojo con bombillas, a la plaza y a la calle.

LA ESCALERA EXTERIOR: en el hueco entre la cafeteria y el pasaje (x 39,2-41,2) sube de la plaza a la terraza.

ESTRUCTURA: la terraza es el forjado de la planta baja; lo llevan los muros, la viga de hormigon (bajo el muro este
del salon) sobre sus dos columnas y los dinteles de hormigon de los escaparates entre las pilastras. Si se vuelan las
columnas, el muro del salon se queda sin apoyo y cae (la lamina: "las vigas pierden soporte", "se cae parte del segundo piso").
"""
import math
import disposicion as D
import piezas as P
import mobiliario as M
from piezas import g, V, MURO

X0, Z0, X1, Z1 = D.CAFE
P0 = D.P0                       # 1,4
P1 = D.planta(1)                # 5,0
ZS = D.CAFE_SALON_Z             # 25,0: el muro sur del salon va de 24,4 a 25,0
ALERO = g(P1 + 3.2)             # 8,2: arriba de los muros del salon
ANTEPECHO = g(ALERO + 2.6)      # 10,8: arriba de los antepechos del rotulo
XS = 28.4                       # el salon de arriba ocupa la esquina oeste (x 21,2-28,4, z 18-32); la terraza, el resto
SALON = (X0, Z0, XS, Z1)
OESTE_ROTULO = 23.8             # el antepecho oeste del rotulo va de z 23,8 a 32
COLUMNAS_Z = (24.4, 28.4)       # las dos columnas de hormigon bajo el muro este del salon (x 27,8-28,4)
HUECO_ESCALERA = (36.8, 18.8, 38.6, 24.4)
A = D.A

CALIDA = (255, 196, 128)


def construir(l, rng):
    cs = P.caras(D.CAFE)
    sur, oeste, norte, este = cs["s"], cs["o"], cs["n"], cs["e"]

    # ------------------------------------------------------------------------------------------------ el cascaron
    # planta baja: muros de 0,6 hasta el suelo de la terraza (desde 0,8: muerden la acera)
    P.cascaron(l, D.CAFE, 0.8, P1, "sillar", nucleo="ladrillo", interior="revoque_int_calido")
    # el SALON de arriba, en la esquina (oeste): sus muros empiezan dentro del forjado
    P.cascaron(l, SALON, P1 - 0.4, ALERO, "revoque_arena", nucleo="ladrillo", interior="revoque_int_calido")
    cs_s = P.caras(SALON)
    # el suelo de la planta baja (ancla: toca la tierra)
    l.caja(X0 + MURO, 0.8, Z0 + MURO, X1 - MURO, P0, Z1 - MURO, "baldosa_cafe_suelo")

    # ------------------------------------------------------------------------------------------------ estructura
    # la VIGA de hormigon bajo el muro este del salon, sobre dos COLUMNAS (lamina: COLUMNAS Y VIGAS)
    for cz in COLUMNAS_Z:
        l.caja(XS - MURO, 0.8, cz, XS, 3.8, cz + 0.6, "hormigon")
        l.caja(XS - MURO - 0.2, 3.6, cz - 0.2, XS + 0.2, 3.8, cz + 0.8, "hormigon_viga")        # el capitel
    l.caja(XS - MURO, 3.8, Z0 + 0.2, XS, 4.2, Z1 - 0.2, "hormigon_viga")
    l.caja(XS - MURO, 4.2, Z0 + MURO, XS, 4.6, Z1 - MURO, "ladrillo")                  # el muro del salon, sobre la viga
    # los dinteles de hormigon sobre los escaparates, dentro del nucleo del muro
    sur.caja(l, X0 + 0.4, X1 - 0.4, 4.4, 4.8, V, 2 * V, "hormigon_viga")
    oeste.caja(l, Z0 + 0.4, Z1 - 0.4, 4.4, 4.8, V, 2 * V, "hormigon_viga")
    # el forjado de la terraza / techo de la planta baja: tablas y viguetas a la vista (de norte a sur)
    P.forjado(l, (X0 + MURO, Z0 + MURO, X1 - MURO, Z1 - MURO), P1, acabado="baldosa_terraza", tablero="tablas_techo",
              viguetas="madera_viga", paso=1.2, dir_vigas="z", sin=[HUECO_ESCALERA])
    # dentro del salon el suelo es de tarima (encima del mismo forjado)
    l.caja(X0 + MURO, P1 - V, Z0 + MURO, XS - MURO, P1, Z1 - MURO, "tarima")

    # ------------------------------------------------------------------------------------------------ fachada SUR
    # pilastras de sillar y escaparates; zocalo de mamposteria
    P.zocalo(l, sur, X0, X1, 0.8, 0.6, "mamposteria")
    P.escaparate(l, sur, 22.4, 27.6, P0, alto=3.0)
    P.puerta(l, sur, 28.8, P0, ancho=2.8, alto=2.6, hoja="madera_marco", vidrio="vidrio_escaparate",
             hojas=2, estado="abierta", montante="vidrio_escaparate")
    P.escaparate(l, sur, 32.8, 38.0, P0, alto=3.0)
    for (a, b) in ((X0 - 0.2, 22.4), (27.6, 28.8), (31.6, 32.8), (38.0, X1 + 0.2)):       # pilastras en relieve
        sur.caja(l, a, b, 1.4, 4.6, -V, V, "sillar")
    P.toldo(l, sur, 22.2, 38.2, 4.6, vuelo=2.0)                                            # el toldo rojo corrido
    P.imposta(l, sur, X0, X1, 4.8, "piedra_cornisa", sale=0.4, alto=0.4)                  # el borde de la terraza

    # ------------------------------------------------------------------------------------------------ fachada OESTE
    P.zocalo(l, oeste, Z0, Z1, 0.8, 0.6, "mamposteria")
    P.escaparate(l, oeste, 19.2, 23.6, P0, alto=3.0)
    P.puerta(l, oeste, 24.4, P0, ancho=1.6, alto=2.6, hoja="madera_marco", vidrio="vidrio_escaparate", estado="abierta",
             montante="vidrio_escaparate")
    P.escaparate(l, oeste, 26.8, 30.8, P0, alto=3.0)
    for (a, b) in ((Z0 - 0.2, 19.2), (23.6, 24.4), (26.0, 26.8), (30.8, Z1 + 0.2)):
        oeste.caja(l, a, b, 1.4, 4.6, -V, V, "sillar")
    P.toldo(l, oeste, 19.0, 31.0, 4.6, vuelo=2.0)
    P.imposta(l, oeste, Z0, Z1, 4.8, "piedra_cornisa", sale=0.4, alto=0.4)

    # ------------------------------------------------------------------------------------------------ fachada NORTE
    P.zocalo(l, norte, X0, X1, 0.8, 0.8, "mamposteria")
    P.acabado(l, norte, X0, X1, 1.6, P1, "revoque_arena")
    P.desconchones(l, norte, X0 + 0.6, X1 - 0.6, 1.8, 4.6, rng, 4, evitar=[(22.4, 2.0, 24.0, 4.2), (29.2, 2.0, 31.0, 4.2),
                                                                             (34.6, 1.4, 36.4, 4.2)])
    P.ventana(l, norte, 22.6, 2.2, reja=True, postigos=None, recercado="sillar")                      # la cocina
    P.ventana(l, norte, 29.4, 2.2, reja=True, recercado="sillar")                                      # tras la barra
    P.puerta(l, norte, 34.6, P0, ancho=1.6, alto=2.6, hoja="madera_puerta_verde", estado="abierta")    # la de servicio
    P.imposta(l, norte, X0, X1, 4.8, "piedra_cornisa", sale=0.2, alto=0.4)
    P.bajante(l, norte, 21.8, 1.4, ALERO)
    P.aire_acondicionado(l, norte, 32.0, 3.4)

    # ------------------------------------------------------------------------------------------------ fachada ESTE
    # la da al hueco de la escalera exterior: ladrillo visto con restos de revoque
    P.acabado(l, este, Z0, Z1, 1.4, P1, "ladrillo")
    P.acabado(l, este, Z0 + 0.4, Z1 - 3.0, 1.6, 3.2, "revoque_arena")
    P.desconchones(l, este, Z0 + 0.6, Z1 - 3.0, 1.8, 3.2, rng, 3)

    # esquinas de sillar en toda la planta baja
    P.esquinas(l, D.CAFE, 1.4, P1 - 0.2, "sillar")

    # ------------------------------------------------------------------------------------------------ EL SALON (arriba)
    so, ss, sn, se = cs_s["o"], cs_s["s"], cs_s["n"], cs_s["e"]
    P.esquinas(l, SALON, P1, ALERO, "sillar", lados=("n", "o", "s"))
    flores = ("flor_roja", "flor_rosa", "flor_blanca", "flor_amarilla", "flor_naranja")
    y_v = P1 + 0.8
    for (c, a0) in ((sn, 23.8), (so, 19.4), (so, 23.0), (so, 27.0), (ss, 22.4), (ss, 25.6)):
        P.ventana(l, c, a0, y_v, postigos="postigo_gris", estado="abiertos", recercado="sillar")
        P.jardinera_colgada(l, c, a0, a0 + 1.4, y_v - 0.4, rng, flores=flores)
    # la cara a la terraza: dos puertas acristaladas de dos hojas que abren hacia fuera
    for zz in (20.0, 26.8):
        P.puerta(l, se, zz, P1, ancho=2.4, alto=2.6, hoja="madera_marco", vidrio="vidrio_escaparate", hojas=2,
                 estado="abierta", abre="fuera")
    P.ventana(l, se, 23.6, y_v, marco="madera_marco", postigos="postigo_gris", estado="abiertos")
    evit_o = [(19.0, P1, 21.2, P1 + 3.0), (22.6, P1, 24.8, P1 + 3.0), (26.6, P1, 28.8, P1 + 3.0)]
    P.desconchones(l, so, Z0 + 0.6, Z1 - 0.6, P1 + 0.4, ALERO - 0.4, rng, 4, evitar=evit_o)
    P.desconchones(l, sn, X0 + 0.6, XS - 0.6, P1 + 0.4, ALERO - 0.2, rng, 2, evitar=[(23.4, P1, 25.6, P1 + 3.0)])
    P.desconchones(l, ss, X0 + 0.6, XS - 0.6, P1 + 0.4, ALERO - 0.4, rng, 2,
                   evitar=[(22.0, P1, 24.2, P1 + 3.0), (25.2, P1, 27.4, P1 + 3.0)])
    P.desconchones(l, se, Z0 + 0.6, Z1 - 0.6, P1 + 0.4, ALERO - 0.4, rng, 3,
                   evitar=[(19.6, P1, 22.8, P1 + 3.0), (23.2, P1, 25.4, P1 + 3.0), (26.4, P1, 29.6, P1 + 3.0)])
    P.imposta(l, sn, X0, XS, ALERO - 0.2, "piedra_cornisa")
    # EL TEJADO del salon: tejas / tablas / pares a la vista por dentro (cumbrera a lo largo de Z)
    P.tejado(l, SALON, ALERO, cumbrera="z", vuelo=0.4, teja="teja", hastial=("revoque_arena", "ladrillo",
                                                                               "revoque_int_calido"))
    # LOS ANTEPECHOS DEL ROTULO en la esquina: el muro sur entero y el oeste de z 23,8 a 32 siguen hasta 10,8 en
    # ladrillo visto, con su albardilla; delante no asoma el alero
    l.caja(X0 - 0.6, ALERO - 0.6, Z1, XS + 0.6, 11.8, Z1 + 0.6, "teja", hueco=True)
    l.caja(X0 - 0.6, ALERO - 0.6, OESTE_ROTULO - 0.2, X0, 11.8, Z1 + 0.6, "teja", hueco=True)
    l.caja(X0, ALERO - 0.4, Z1 - MURO, XS, ANTEPECHO, Z1, "ladrillo")
    l.caja(X0, ALERO - 0.4, OESTE_ROTULO, X0 + MURO, ANTEPECHO, Z1, "ladrillo")
    # el paño donde van las letras, revocado en claro (rojo sobre crema, como la lamina: sobre ladrillo no se leia)
    l.caja(X0 + 0.2, ALERO, Z1 - V, XS - 0.2, ANTEPECHO - 0.2, Z1, "revoque_crema")
    l.caja(X0, ALERO, OESTE_ROTULO + 0.2, X0 + V, ANTEPECHO - 0.2, Z1 - 0.2, "revoque_crema")
    l.caja(X0 - 0.2, ANTEPECHO, Z1 - MURO - 0.2, XS + 0.2, ANTEPECHO + 0.2, Z1 + 0.2, "piedra_cornisa")     # albardilla
    l.caja(X0 - 0.2, ANTEPECHO, OESTE_ROTULO - 0.2, X0 + MURO + 0.2, ANTEPECHO + 0.2, Z1 + 0.2, "piedra_cornisa")
    l.caja(XS - 0.2, ALERO - 0.4, Z1 - MURO - 0.2, XS + 0.2, ANTEPECHO + 0.4, Z1 + 0.2, "sillar")        # remates
    l.caja(X0 - 0.2, ALERO - 0.4, OESTE_ROTULO - 0.2, X0 + MURO + 0.2, ANTEPECHO + 0.4, OESTE_ROTULO + 0.2, "sillar")
    l.caja(X0 - 0.2, ALERO - 0.4, Z1 - 0.2, X0 + 0.2, ANTEPECHO + 0.4, Z1 + 0.2, "sillar")
    # las letras: rojas, 0,4 fuera del antepecho, con bombillas
    _rotulo_cafe(l, P.Cara("x", Z1, 1, lado="s"), 21.8, ANTEPECHO - 0.4)
    _rotulo_cafe(l, P.Cara("z", X0, -1, lado="o"), 25.0, ANTEPECHO - 0.4)

    # ------------------------------------------------------------------------------------------------ LA TERRAZA
    _terraza(l, rng)
    # ------------------------------------------------------------------------------------------------ DENTRO
    import interior_cafe
    interior_cafe.planta_baja(l, rng)
    interior_cafe.salon(l, rng)
    # ------------------------------------------------------------------------------------------------ LA ESCALERA EXTERIOR
    _escalera_exterior(l, rng)
    # ------------------------------------------------------------------------------------------------ LA ACERA DE DELANTE
    _terraza_calle(l, rng)


def _rotulo_cafe(l, cara, u0, y_arriba):
    """"CAFÉ" en letras de caja roja (0,4 de fondo) con una bombilla en cada tercer punto del trazo y su luz."""
    import letras
    pix, ancho = letras.pixeles("CAFÉ", "grande")
    px = V

    def uu(c):
        return u0 + c * px if cara.dch > 0 else u0 - (c + 1) * px
    # la estructura de hierro detras (une las letras al antepecho)
    cara.caja(l, uu(0) if cara.dch > 0 else uu(ancho - 1), (uu(ancho - 1) + px) if cara.dch > 0 else (uu(0) + px),
              y_arriba - 1.0, y_arriba - 0.8, -V, 0.0, "hierro")
    for c, f in pix:
        u = uu(c)
        yy = y_arriba - f * px
        cara.caja(l, u, u + px, yy - px, yy, -0.4, 0.0, "cartel_rojo")
        if (c * 5 + f * 3) % 7 == 0 and f >= 0:
            cara.caja(l, u, u + px, yy - px, yy, -0.6, -0.4, "luz_bombilla")
    mid = uu(ancho // 2)
    cara.luz(l, mid, y_arriba - 0.9, -1.2, (255, 120, 90), 1.6, 8.0)


def _barandilla_x(l, x0, x1, z0, y):
    """Pretil de sillar (0,2) con albardilla y barandilla de hierro encima, a lo largo de X (z0..z0+0,4)."""
    l.caja(x0, y, z0, x1, y + 0.2, z0 + 0.4, "sillar")
    l.caja(x0, y + 0.2, z0 - 0.1 if False else z0, x1, y + 0.4, z0 + 0.4, "piedra_cornisa")
    l.caja(x0, y + 1.0, z0 + 0.2, x1, y + 1.2, z0 + 0.4, "hierro_forja")
    x = x0
    while x < x1 - 0.1:
        l.caja(x, y + 0.4, z0 + 0.2, x + V, y + 1.0, z0 + 0.4, "hierro_forja")
        x = g(x + 0.4)


def _terraza(l, rng):
    """La terraza de la planta alta (mitad este): pretiles con barandilla, jardineras con flores, mesas con sombrilla,
    la PERGOLA con su tejadillo sobre la mitad norte (debajo sale la escalera de dentro) y guirnaldas de bombillas."""
    y = P1
    xa, xb = XS, X1
    # los pretiles: a la plaza (sur) y a la calle mayor (norte); por el sur el pretil sobresale un poco
    _barandilla_x(l, xa, xb - 0.4, Z1 - 0.4, y)
    _barandilla_x(l, xa, xb - 0.4, Z0, y)
    l.caja(xa, y + 0.2, Z1 - 0.4, xb, y + 0.4, Z1 + 0.2, "piedra_cornisa")
    # el lado este (da a la escalera exterior): barandilla con el paso al rellano (z 25,0-26,2)
    for (za, zb) in ((Z0 + 0.4, 25.0), (26.2, Z1 - 0.4)):
        l.caja(xb - 0.6, y + 1.0, za, xb - 0.4, y + 1.2, zb, "hierro_forja")
        z = za
        while z < zb - 0.1:
            l.caja(xb - 0.6, y, z, xb - 0.4, y + 1.0, z + V, "hierro_forja")
            z = g(z + 0.4)
    # jardineras con flores por dentro del pretil
    flores = ("flor_roja", "flor_rosa", "flor_blanca", "flor_amarilla", "flor_naranja")
    for (a, b) in ((29.6, 32.0), (33.6, 36.0)):
        M.jardinera(l, a, Z1 - 1.0, b, Z1 - 0.4, y, rng, alto=0.4, mat="madera_oscura", remate="madera_marco", flores=flores)
    for (a, b) in ((29.0, 31.4), (32.4, 34.4)):
        M.jardinera(l, a, Z0 + 0.4, b, Z0 + 1.0, y, rng, alto=0.4, mat="madera_oscura", remate="madera_marco", flores=flores)
    for (mx, mz) in ((37.8, 31.0), (29.0, 25.6), (37.8, 26.8)):
        M.maceta(l, mx, mz, y, rng, grande=True)
    # mesas con sombrilla en la mitad sur (al sol)
    M.mesa_con_sombrilla(l, 31.0, 28.6, y, rng, sillas=3, mat_sombrilla="sombrilla")
    M.mesa_con_sombrilla(l, 35.4, 28.8, y, rng, sillas=4, mat_sombrilla="sombrilla_amarilla")
    # bajo la pergola, dos mesas mas
    for (mx, mz) in ((30.6, 21.6), (33.8, 22.4)):
        M.mesa(l, mx, mz, y, redonda=False)
        M.sillas_alrededor(l, mx, mz, y, rng, n=3)
    # LA PERGOLA: postes, carreras, tejadillo de tejas a dos aguas (tejas / tablas / pares)
    for pz in (Z0 + 0.4, 24.6):
        for px in (32.4, 36.2, 38.2):
            l.caja(px, y, pz, px + 0.4, y + 2.8, pz + 0.4, "madera_viga")
            l.caja(px - 0.2, y, pz - 0.2 if pz > 20 else pz, px + 0.6, y + 0.2, pz + 0.6 if pz > 20 else pz + 0.4, "hierro")
        l.caja(XS - 0.4, y + 2.8, pz, xb - 0.4, y + 3.2, pz + 0.4, "madera_viga")      # la carrera (muerde el salon)
    P.tejado(l, (XS, Z0 + 0.4, xb - 0.4, 25.0), y + 3.2, cumbrera="x", vuelo=0.4, teja="teja", hastiales=False,
             paso_vigas=1.2)
    # la barandilla del hueco de la escalera de dentro (se sale por el norte, hacia el oeste)
    hx0, hz0, hx1, hz1 = HUECO_ESCALERA
    l.caja(hx0 - 0.2, y, 20.6, hx0, y + 1.2, hz1 + 0.2, "hierro_forja")
    l.caja(hx0 - 0.2, y, 20.6, hx0, y + 1.0, hz1 + 0.2, "hierro_forja", hueco=True)
    z = 20.6
    while z < hz1 + 0.1:
        l.caja(hx0 - 0.2, y, z, hx0, y + 1.0, z + V, "hierro_forja")
        z = g(z + 0.4)
    l.caja(hx0 - 0.2, y + 1.0, hz1, hx1, y + 1.2, hz1 + 0.2, "hierro_forja")
    x = hx0
    while x < hx1 - 0.1:
        l.caja(x, y, hz1, x + V, y + 1.0, hz1 + 0.2, "hierro_forja")
        x = g(x + 0.4)
    # GUIRNALDAS de bombillas por ENCIMA de la cabeza (a 20 cm el cable es un voxel: a la altura de los ojos estorbaba):
    # de la carrera sur de la pergola a unos mastiles de hierro en el pretil de la plaza, y del salon a los mastiles
    mastiles = [(30.4, Z1 - 0.4), (34.0, Z1 - 0.4), (37.6, Z1 - 0.4)]
    for (mx, mz) in mastiles:
        l.caja(mx, y, mz, mx + V, y + 3.0, mz + V, "hierro_forja")
        l.caja(mx - 0.2, y + 2.8, mz, mx + 0.4, y + 3.0, mz + V, "hierro_forja")
    for (gx, (mx, mz)) in zip((30.5, 34.1, 37.7), mastiles):
        _guirnalda(l, (gx, y + 3.0, 24.9), (mx + 0.1, y + 2.9, mz + 0.1), 0.35)
    _guirnalda(l, (XS - 0.1, ALERO - 0.3, 30.9), (30.5, y + 2.9, Z1 - 0.3), 0.3)
    _guirnalda(l, (30.5, y + 2.9, Z1 - 0.3), (34.1, y + 2.9, Z1 - 0.3), 0.3)
    _guirnalda(l, (34.1, y + 2.9, Z1 - 0.3), (37.7, y + 2.9, Z1 - 0.3), 0.3)
    for gx, gz in ((33.0, 28.4), (34.4, 21.6)):
        l.luz(gx, y + 2.6, gz, (255, 200, 130), 0.9, 7.0)


def _guirnalda(l, a, b, comba):
    """Un cable de a a b que cuelga `comba` metros en el medio, con bombillas cada ~0,6 m colgando de el."""
    n = max(3, int(math.dist(a, b) / 0.6))
    prev = a
    for i in range(1, n + 1):
        t = i / n
        p = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t - comba * 4 * t * (1 - t), a[2] + (b[2] - a[2]) * t)
        l.linea(prev[0], prev[1], prev[2], p[0], p[1], p[2], 0.05, "metal_negro")
        if 0 < i < n and i % 2 == 1:
            l.linea(p[0], p[1], p[2], p[0], p[1] - 0.15, p[2], 0.05, "luz_bombilla")
        prev = p


def _escalera_exterior(l, rng):
    """La escalera de piedra de la plaza a la terraza, entre la cafeteria y el pasaje, con su rellano y el cuarto de
    abajo (el hueco de x 39,2 a 41,2)."""
    xa, xb = 39.2, 41.2
    # el cuartito cerrado de debajo del rellano (z 18-25) con su techo = el rellano
    l.caja(xa, 0.8, Z0, xb, P1 - 0.4, Z0 + 0.6, "mamposteria")                 # el muro de la calle mayor
    P.puerta(l, P.Cara("x", Z0, -1, xa, xb, "n"), 39.4, A, ancho=1.6, alto=2.6, hoja="madera_puerta", estado="cerrada")
    l.caja(xa, 0.8, 24.4, xb, P1 - 0.4, 25.0, "mamposteria")                   # el del fondo del cuartito
    l.caja(xa - 0.2, P1 - 0.4, Z0, xb + 0.2, P1, 26.2, "hormigon")              # el rellano (muerde los dos muros)
    l.caja(xa, P1 - V, Z0, xb, P1, 26.2, "baldosa_terraza")
    l.caja(xa, 0.8, Z0 + 0.6, xb, A, 24.4, "adoquin")
    # los peldaños macizos de piedra: de la plaza (z 32) al rellano (z 26,2)
    P.escalera(l, xa, Z1, A, P1 - A, Z1 - 26.2, xb - xa, hacia="-z", mat="sillar_gris", zancas=None, baranda=None,
               grueso=P1)
    # el pasamanos de hierro en el muro del pasaje
    l.linea(xb - 0.1, A + 1.0, Z1 - 0.2, xb - 0.1, P1 + 1.0, 26.4, 0.06, "hierro_forja")
    l.luz(40.2, P1 + 2.2, 25.6, CALIDA, 0.6, 4.0)


def _terraza_calle(l, rng):
    """Lo de delante de la cafeteria en la acera y la plaza: mesas con sombrilla, jardineras de ladrillo con arbustos,
    la pizarra, farolas y maceteros (lamina: VISTA PRINCIPAL y VISTA DESDE ABAJO)."""
    y = A
    flores = ("flor_roja", "flor_rosa", "flor_amarilla", "flor_blanca", "flor_violeta")
    # en la plaza, delante de la fachada sur (dejando libre el paso de la puerta, x 28,8-31,6)
    M.mesa_con_sombrilla(l, 25.0, 35.6, y, rng, sillas=4, mat_sombrilla="sombrilla")
    M.mesa_con_sombrilla(l, 30.2, 37.2, y, rng, sillas=3, mat_sombrilla="sombrilla")
    M.mesa_con_sombrilla(l, 35.4, 35.6, y, rng, sillas=4, mat_sombrilla="sombrilla")
    M.mesa(l, 26.2, 33.4, y)
    M.sillas_alrededor(l, 26.2, 33.4, y, rng, n=2)
    M.mesa(l, 34.8, 33.4, y)
    M.sillas_alrededor(l, 34.8, 33.4, y, rng, n=2)
    # la jardinera de ladrillo de la esquina con su arbol grande (el de la izquierda de la vista principal)
    M.jardinera(l, 17.2, 34.0, 19.6, 36.4, y, rng, alto=0.6, plantas="arbustos", flores=flores)
    M.arbol(l, 18.2, 35.0, y + 0.6, rng, alto=7.4, copa=1.1, alcorque=False)
    M.jardinera(l, 21.4, 34.4, 23.4, 35.6, y, rng, alto=0.6, plantas="arbustos", flores=flores)
    M.jardinera(l, 37.4, 38.2, 39.4, 39.4, y, rng, alto=0.6, plantas="arbustos", flores=flores)
    M.pizarra(l, 32.0, 33.0, y, eje="x")
    M.farola(l, 22.0, 39.6, y)
    M.farola(l, 38.2, 33.0, y)
    M.maceta(l, 32.2, 32.4, y, rng, grande=False, flores=flores)
    M.maceta(l, 38.6, 32.4, y, rng, grande=True)
    # en la acera de la calle principal, delante de la fachada oeste: mesas bajo el toldo (sin sombrilla)
    for (mz, n) in ((20.8, 2), (28.8, 3)):
        M.mesa(l, 19.2, mz, y, redonda=True)
        M.sillas_alrededor(l, 19.2, mz, y, rng, n=n)
    M.mesa(l, 19.2, 23.0, y, redonda=False)
    M.sillas_alrededor(l, 19.2, 23.0, y, rng, n=2)
    M.jardinera(l, 17.0, 18.4, 18.0, 20.0, y, rng, alto=0.6, plantas="arbustos", flores=flores)
    M.jardinera(l, 17.0, 30.2, 18.0, 31.8, y, rng, alto=0.6, plantas="arbustos", flores=flores)
    M.pizarra(l, 20.2, 26.8, y, eje="z")
    M.farola(l, 17.2, 23.0, y, banderola="banderola_roja", hacia=(0.0, 1.0))
    M.farola(l, 17.2, 33.2, y, banderola="banderola_roja", hacia=(0.0, -1.0))
