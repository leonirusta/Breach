"""VEGETACION del mapa "isla": la siembra de cada region, DESPUES de las zonas (que marcan como ocupado lo
que construyen) y de las carreteras. Cada region se reconoce de lejos por su silueta:

  - BOSQUE: pinos altos y oscuros con claros de abedul y algun roble; arbustos y rocas.
  - AMAZONAS: selva cerrada a dos alturas. Ceibas gigantes de 20-26 m con lianas por encima de un dosel de
    arboles de 8-14 m, helechos abajo. Se pelea a la sombra.
  - DESIERTO: cactus y rocas rojas sueltas, mucho espacio abierto entre dunas.
  - MONTANAS: pinos solo en la falda (por debajo de 20 m) y rocas.
  - COSTA: palmeras en las playas.
"""
import disposicion as D
import naturaleza as N


def _roca_roja(l, x, z, y, rng):
    N.roca(l, x, z, y, rng, "roca_roja")


def _arbusto_seco(l, x, z, y, rng):
    N.arbusto(l, x, z, y, rng, "cesped_seco")


def _pino_falda(l, x, z, y, rng):
    if y < 20.0:
        N.pino(l, x, z, y, rng)


def construir(l, T, rng):
    n = {}
    n["bosque"] = N.sembrar(l, T, rng, 3, 6.5, [(6, N.pino, 2.5), (2, N.abedul, 2.0), (1, N.roble, 3.5),
                                                (2, N.arbusto, 1.0), (0.6, N.roca, 1.5)], pendiente_max=0.9)
    # la selva en dos pasadas: primero las ceibas (con sitio), luego el dosel y el sotobosque en los huecos
    n["ceibas"] = N.sembrar(l, T, rng, 5, 16.0, [(1, N.ceiba, 6.0)], pendiente_max=0.5)
    n["selva"] = N.sembrar(l, T, rng, 5, 5.0, [(4, N.arbol_selva, 2.2), (3, N.helecho, 1.0), (2, N.arbusto, 1.0)],
                           pendiente_max=0.8)
    n["desierto"] = N.sembrar(l, T, rng, 4, 13.0, [(3, N.cactus, 1.0), (1, _roca_roja, 1.8), (1, _arbusto_seco, 0.8)],
                              pendiente_max=0.7)
    n["monte"] = N.sembrar(l, T, rng, 2, 11.0, [(3, _pino_falda, 2.5), (1, N.roca, 1.8)], pendiente_max=0.7)
    # palmeras: solo en arena de playa por encima del agua
    playa = T.m("arena_playa")

    def _palmera_playa(l, x, z, y, rng):
        i, k = T._ij(x, z)
        if T.piel[i, k] == playa and y > D.MAR_Y + 0.5:
            N.palmera(l, x, z, y, rng)
    n["palmeras"] = N.sembrar(l, T, rng, 0, 12.0, [(1, _palmera_playa, 2.0)], pendiente_max=0.6)
    print("  vegetacion: " + ", ".join("%s %d" % kv for kv in n.items()))
