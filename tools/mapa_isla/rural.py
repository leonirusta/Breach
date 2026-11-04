"""LO QUE HAY ENTRE REGIONES: paradas en el camino para que ninguna carretera sea tierra de nadie.

  - DOS GASOLINERAS: marquesina sobre pilares, surtidores y la tienda. Una en la carretera del sur y otra
    en la del noreste.
  - LA GRANJA del oeste, entre el bosque y el desierto: granero rojo, casa, silo, cercas, balas de paja.
  - EL PUESTO MILITAR del noreste: barracon, torres de vigilancia, sacos terreros y botin del bueno.
"""
import math

import disposicion as D
import edificios as E
import ciudad as C

GASOLINERAS = [(306.0, 366.0, "+x"), (372.0, 190.0, "-z")]
GRANJA = (84.0, 232.0)
MILITAR = (404.0, 206.0)


def planificar(T):
    for x, z, _f in GASOLINERAS:
        T.aplanar(x - 12, z - 10, x + 12, z + 10, T.altura(x, z), falda=6.0, mat="asfalto")
    x, z = GRANJA
    T.aplanar(x - 20, z - 16, x + 20, z + 16, T.altura(x, z), falda=8.0, mat="cesped_seco")
    x, z = MILITAR
    T.aplanar(x - 18, z - 16, x + 18, z + 16, T.altura(x, z), falda=8.0, mat="grava")


def construir(l, T, rng):
    l.zona = "rural"
    for x, z, f in GASOLINERAS:
        _gasolinera(l, T, x, z, f, rng)
    _granja(l, T, rng)
    l.zona = "militar"
    _militar(l, T, rng)


def _gasolinera(l, T, x, z, frente, rng):
    y = T.altura(x, z)
    # marquesina: losa sobre cuatro pilares metidos en el suelo
    l.caja(x - 8.0, y + 4.5, z - 5.0, x + 4.0, y + 5.1, z + 5.0, "chapa_blanca")
    l.caja(x - 8.0, y + 4.5, z - 5.0, x + 4.0, y + 4.8, z - 4.7, "chapa_roja")
    l.caja(x - 8.0, y + 4.5, z + 4.7, x + 4.0, y + 4.8, z + 5.0, "chapa_roja")
    for dx in (-6.0, 2.0):
        for dz in (-3.0, 3.0):
            l.caja(x + dx - 0.25, y - 0.6, z + dz - 0.25, x + dx + 0.25, y + 4.5, z + dz + 0.25, "metal")
            # surtidor junto a cada pilar
            l.caja(x + dx - 0.4, y - 0.15, z + dz * 0.5 - 0.3, x + dx + 0.4, y + 1.7, z + dz * 0.5 + 0.3, "chapa_roja")
            l.caja(x + dx - 0.3, y + 1.0, z + dz * 0.5 - 0.31, x + dx + 0.3, y + 1.5, z + dz * 0.5 + 0.31, "vidrio")
        l.caja(x + dx - 0.6, y - 0.15, z - 3.5, x + dx + 0.6, y + 0.15, z + 3.5, "hormigon_claro")
    for dz in (-2.5, 2.5):
        l.caja(x - 2.8, y + 4.2, z + dz - 0.5, x - 1.2, y + 4.5, z + dz + 0.5, "luz_fria")
    l.luz(x - 2.0, y + 4.1, z, (225, 235, 255), 1.3, 14.0, direccion=(0, -1, 0), cono=55.0)
    # la tienda, detras de la marquesina
    E.bloque(l, x + 5.0, z - 6.0, x + 12.0, z + 6.0, y, 1, rng, frente="-x", muro="revoco_blanco", losa="chapa_roja",
             tienda=True, nivel=2, particiones=False)
    T.ocupar(x - 12, z - 10, x + 12, z + 10)
    l.spawn(x - 10.0, y + 0.5, z)


def _granja(l, T, rng):
    x, z = GRANJA
    y = T.altura(x, z)
    # granero: nave roja con cubierta de chapa
    E.nave(l, x - 18.0, z - 14.0, x - 4.0, z + 6.0, y, rng, frente="+x", muro="chapa_roja", cubierta="chapa", alto=5.5, nivel=2)
    # casa de dos plantas con porche
    E.casa(l, x + 4.0, z - 12.0, x + 14.0, z - 3.0, y, rng, frente="+z", muro="revoco_crema", tejado="teja", plantas=2, nivel=2)
    # silo: cilindro hueco con puerta y cupula
    sx, sz = x + 12.0, z + 8.0
    l.cilindro(sx, y - 0.9, sz, 3.0, 13.0, "chapa")
    l.cilindro(sx, y + 0.15, sz, 2.7, 11.5, "chapa", hueco=True)
    l.cono(sx, y + 12.1, sz, 3.1, 0.3, 2.0, "chapa")
    l.puerta(sx - 2.85, y + 0.15, sz, 90.0, ancho=1.2, alto=2.4, tipo="metal", grosor=0.9)
    l.loot(sx, y + 0.15, sz, "arma", 2)
    # cercas: postes cada 2 m (metidos 0,5 m) con dos travesanos que se solapan con los postes
    x0, z0, x1, z1 = x - 20.0, z - 16.0, x + 20.0, z + 16.0
    for (a0, b0, a1, b1) in ((x0, z0, x1, z0), (x0, z1, x1, z1), (x0, z0, x0, z1), (x1, z0, x1, z1)):
        largo = max(abs(a1 - a0), abs(b1 - b0))
        n = int(largo / 2.0)
        for k in range(n + 1):
            px, pz = a0 + (a1 - a0) * k / n, b0 + (b1 - b0) * k / n
            if abs(px - x1) < 0.5 and abs(pz - z) < 3.5:         # la entrada, hacia la carretera
                continue
            l.caja(px - 0.1, y - 0.5, pz - 0.1, px + 0.1, y + 1.2, pz + 0.1, "madera")
        for h in (0.5, 1.0):
            if a0 == a1:
                for (c0, c1) in ((b0, z - 3.5), (z + 3.5, b1)) if a0 == x1 else ((b0, b1),):
                    l.caja(a0 - 0.05, y + h, c0, a0 + 0.05, y + h + 0.12, c1, "madera_clara")
            else:
                l.caja(a0, y + h, b0 - 0.05, a1, y + h + 0.12, b0 + 0.05, "madera_clara")
    # balas de paja y un tractor
    for k in range(6):
        bx, bz = x - 2.0 + (k % 3) * 1.6, z + 9.0 + (k // 3) * 1.6
        l.cilindro(bx, y + 0.55, bz - 0.6, 0.7, 1.2, "madera_clara", eje="z")
    tx, tz = x + 2.0, z + 2.0
    l.caja(tx - 1.0, y + 0.6, tz - 1.6, tx + 1.0, y + 1.5, tz + 1.4, "chapa_roja")
    l.caja(tx - 0.8, y + 1.5, tz - 1.4, tx + 0.8, y + 2.7, tz - 0.1, "vidrio")
    l.cilindro(tx - 1.2, y + 0.75, tz - 1.0, 0.8, 2.4, "neumatico", eje="x")
    l.cilindro(tx - 1.1, y + 0.45, tz + 1.1, 0.5, 2.2, "neumatico", eje="x")
    T.ocupar(x - 21, z - 17, x + 21, z + 17)
    l.spawn(x, y + 0.5, z)


def _militar(l, T, rng):
    x, z = MILITAR
    y = T.altura(x, z)
    # barracon de hormigon con dos plantas y el mejor botin del este
    m, ys, techo = E.bloque(l, x - 14.0, z - 12.0, x + 2.0, z - 2.0, y, 2, rng, frente="+z", muro="hormigon_oscuro",
                            losa="hormigon", nivel=3, zocalo="hormigon")
    E.azotea_detalle(m, l, techo, rng)
    # dos torres de vigilancia (la misma estructura que la de socorrista)
    import montana as MON
    MON.torre_socorrista(l, x + 12.0, z - 10.0, y, rng)
    MON.torre_socorrista(l, x - 14.0, z + 11.0, y, rng)
    # nidos de sacos terreros en U
    for (sx, sz) in ((x + 8.0, z + 6.0), (x - 4.0, z + 10.0), (x + 12.0, z - 2.0)):
        for (a0, b0, a1, b1) in ((-2.0, -2.0, 2.0, -1.2), (-2.0, -2.0, -1.2, 2.0), (1.2, -2.0, 2.0, 2.0)):
            l.caja(sx + a0, y - 0.15, sz + b0, sx + a1, y + 1.1, sz + b1, "arena_duna")
        l.loot(sx, y, sz, "municion", 2)
    # cajas de municion y un camion militar
    for k in range(4):
        l.caja(x + 4.0 + k * 1.3, y - 0.15, z - 12.0, x + 5.1 + k * 1.3, y + 0.9, z - 10.8, "madera_oscura")
    l.caja(x - 8.0, y + 0.5, z + 2.0, x - 5.6, y + 1.6, z + 10.0, "metal_oscuro")
    l.caja(x - 8.0, y + 1.6, z + 2.0, x - 5.6, y + 3.4, z + 4.5, "metal_oscuro")
    l.caja(x - 8.1, y + 1.6, z + 4.5, x - 5.5, y + 3.2, z + 10.0, "toldo_crema")
    for dz in (3.0, 6.5, 9.0):
        l.cilindro(x - 8.2, y + 0.5, z + dz, 0.5, 2.8, "neumatico", eje="x")
    l.loot(x + 6.0, y, z - 9.0, "arma", 3)
    l.loot(x - 2.0, y, z + 6.0, "escudo", 3)
    l.loot(x + 2.0, y, z + 12.0, "casco", 3)
    # valla perimetral de malla (postes y un larguero) con la entrada al oeste
    x0, z0, x1, z1 = x - 18.0, z - 16.0, x + 18.0, z + 16.0
    for (a0, b0, a1, b1) in ((x0, z0, x1, z0), (x0, z1, x1, z1), (x1, z0, x1, z1)):
        largo = max(abs(a1 - a0), abs(b1 - b0))
        n = int(largo / 3.0)
        for k in range(n + 1):
            px, pz = a0 + (a1 - a0) * k / n, b0 + (b1 - b0) * k / n
            l.caja(px - 0.08, y - 0.5, pz - 0.08, px + 0.08, y + 2.4, pz + 0.08, "metal")
        if a0 == a1:
            l.caja(a0 - 0.05, y + 2.25, b0, a0 + 0.05, y + 2.4, b1, "metal")
        else:
            l.caja(a0, y + 2.25, b0 - 0.05, a1, y + 2.4, b0 + 0.05, "metal")
    T.ocupar(x - 19, z - 17, x + 19, z + 17)
    l.spawn(x, y + 0.5, z + 2.0)
