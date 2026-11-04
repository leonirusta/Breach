# 11. El mapa "isla" (battle royale)

Escrito el 2026-09-18. Isla de ~470 m de costa a costa en un mundo de 499 × 57,6 × 499 m, **a 15 cm por
voxel**, rodeada de mar de verdad. Se genera entero con `tools/generar_mapa_isla.py` (unos 110 s).

```bat
python tools\generar_mapa_isla.py                 :: todo; la vista en planta queda en %TEMP%\isla_vista.png
python tools\generar_mapa_isla.py --solo=ciudad   :: solo una zona (mas rapido para probar)
python tools\generar_mapa_isla.py --sin-vegetacion
```

## Qué hay

| Región | Dónde | Lo que la hace reconocible |
|---|---|---|
| Ciudad | centro | plaza de 62 m con fuente y obelisco; rascacielos con helipuerto, parking de 4 plantas con rampas, hotel, oficinas, comisaría, banco, centro comercial con atrio, ayuntamiento con torre del reloj, hospital |
| Montañas | norte | cordillera con nieve; **túnel** de 90 m bajo la cresta; **observatorio** con cúpula y antena en la cumbre; búnker excavado; refugio; cala del norte |
| Bosque | noroeste | pinar; aserradero; torre de vigía de 16 m con escalera de caracol; lago con embarcadero; cabañas; campamento |
| Desierto | suroeste | dunas, tres mesetas (una con puesto de vigía y escalera tallada), oasis con jaimas, **avión estrellado** |
| Ciudad desértica | sur | muralla con adarve y torres, tres puertas, zoco, palacio con cúpula, minarete, casas de adobe con azotea |
| Amazonas | este | selva a dos alturas (ceibas de 20-26 m); **río** navegable que sale al mar; palafitos; **pirámide** con cámara; ruinas; puente |
| Costa | alrededor | puerto con espigones, barcos, contenedores y grúa; **faro**; barco naufragado; chiringuitos y torres de socorrista |
| Rural | entre regiones | dos gasolineras, granja con silo, puesto militar |

Todas las carreteras radiales acaban en la ronda de la ciudad y de ahí cuatro avenidas entran a la plaza.
Una carretera de costa une las regiones sin pasar por el centro.

## Archivos que escribe

- `godot/maps/isla_lo.vxmap`: el mapa. Solo existe el `_lo`, que es lo que carga siempre el juego (y lo que
  se empaqueta en el APK); aquí el `_lo` ya es el de 15 cm.
- `isla.agua.json` (mar, láminas locales y límite nadable), `isla.puertas.json`, `isla.botin.json`,
  `isla.lights.json`. Los usan `agua.gd`, `puertas.gd`/`puerta.gd` y `botin.gd`; son genéricos: cualquier
  mapa que traiga esos archivos tiene agua, puertas que se abren solas y botín.

## Cómo está hecho (tools/mapa_isla/)

- `terreno.py`: el terreno NO son primitivas, es un mapa de alturas a 15 cm con tres capas de material por
  columna. **Todo el terreno es material ancla** (arena, césped, roca de monte, nieve, asfalto), así que lo
  que apoya en él no se cae y el monte se agujerea pero no se derrumba.
- El interior de las montañas se deja **hueco por chunks enteros** (más de un chunk por debajo de la
  superficie más baja de alrededor). Ahorra memoria sin que se note; `Terreno.macizo()` lo impide donde hay
  túneles o búnkeres.
- La llanura queda por debajo de 4,8 m (una sola capa de chunks) y el fondo del mar solo se rellena hasta
  30 m de la costa: más allá el agua se ve honda igual.
- `edificios.py`: el kit. Cimiento metido 0,9 m en el terreno, cada planta es un cascarón macizo vaciado
  (muros y losas salen de la misma pieza), escalera en U que llega a la azotea por una caseta con puerta,
  cristales en el plano del muro. `Lienzo.puerta()` talla el hueco y apunta la hoja a la vez.
- Una zona por archivo (`ciudad.py`, `montana.py`, …) con `planificar(T)` (aplanar/pintar el terreno) y
  `construir(l, T, rng)` (primitivas, puertas, botín, puntos de salida).

## Medido (2026-09-18)

- **0 conjuntos sin ancla antes de soldar** (`VX_NOWELD=1 … --map=isla --auditaflotadores`).
- 17.678 chunks, 290 M voxels, 687 MB de voxels; el mundo tarda ~22 s en estar listo.
- `--bancofps` en la plaza: 51 fps quieto / 43 demoliendo (mediana); en la selva: 53 / 45. Del orden de la
  línea base de Mónaco. Se dibujan 260-540 mil triángulos de 10,7 M.
- `--pruebaisla`: agua, puertas y botín, 14 de 14 OK.
- 129 puertas, ~530 puntos de botín, 34 puntos de salida, 127 luces.

## El battle royale (2026-09-19)

Todo se activa porque el mapa trae `isla.botin.json` (con cualquier test de los de abajo que no lo pida, el
avión no sale: `SaltoScript.quiere_avion`).

- **El avión** (`salto_br.gd` + `avion_br.gd`). Un Hércules de voxels de 20 cm generado con
  `python tools/generar_avion_br.py` (→ `godot/avion/avion_br.bin`, ~20.000 triángulos, sin mallar nada al
  cargar). Cruza la isla en línea recta a 170 m; la ruta sale de `Net.semilla_partida` (la misma en todas las
  máquinas). Cámara orbitando el avión, hélices que giran y motores sintetizados por código.
  - ESPACIO / SALTAR: caída libre (32 m/s, mirando abajo se pica a 50), paracaídas solo a 38 m o antes con
    SALTAR, planeo con el movimiento. Los bots saltan repartidos por la ruta y caen hacia un punto de salida.
  - **Mientras se está en el aire el mundo se dibuja alrededor del suelo de debajo** (`punto_de_vista`), con
    la distancia de render al máximo, poca niebla y plano lejano a 900 m; al tocar suelo vuelve a lo de tus
    ajustes. Antes de despegar hay 1,5 s en el suelo con la pantalla tapada para construir las mallas lejanas.
  - Medido (i3-N305): 45-55 fps en el avión y 38-50 cayendo, sin parones. **Ojo al medir**: las fotos de la
    prueba (`--fotos`) cuestan ~0,75 s cada una y salían como parones del juego.
- **La zona** (`zona_br.gd`, `shaders/zona_br.gdshader`). Primera zona a los 90 s del despegue; cada 2 min una
  nueva dentro de la anterior (y con el centro en tierra), el último minuto el muro se cierra. Fuera: 2, 3, 5,
  8, 12, 18 y 26 de vida por segundo según la fase, sin que lo paren chaleco ni casco. Minimapa con el muro y la
  siguiente zona (y flecha si queda fuera), mapa grande con **M** o **tocando el minimapa** (solo en battle royale; se cierra tocándolo) con la vista del
  generador (`godot/ui/mapas/isla.png`). Los bots fuera de la zona que viene reciben puntos que guardar dentro.
  Se reaparece dentro. En red viaja solo el reloj de zona del anfitrión (`Net.net_zona_reloj`).
- **Vendas y botiquines** (`player.gd`, botín `venda` / `botiquin`): 7 venda (3 s, +15 %, tope 75 %), 8
  botiquín (6 s, vida entera), H lo que mejor venga, CURAR en el móvil. Disparar o cambiar de arma lo corta.
- **Puertas con física** (`puerta.gd`): la hoja tiene ángulo y velocidad; el muelle la abre al acercarte, pero
  si la chocas cede según tu velocidad y rebota en el tope, las explosiones la sacuden (o la arrancan de cerca)
  y las balas la atraviesan empujándola.

Pruebas: `--pruebaisla` (agua, puertas con su física, curas, botín), `--pruebasalto` (avión, caída,
paracaídas, bots, fps por segundo) y `--pruebazona` (círculos, cierre, daño, bots, reaparición). Con `--fotos`
y sin `--headless` guardan capturas en `user://`.

- **Último en pie** (`zona_br.gd`, "ULTIMO EN PIE"). En la isla morir es quedar eliminado: sin reaparecer,
  mirando a cualquiera que siga vivo (no hay equipos), con cartel de ELIMINADO y tu puesto. Los bots tampoco
  vuelven, y la lógica de rondas del modo bomba se corta (`_on_round_over`). Cada segundo se cuentan los vivos
  (tú, la sala y los bots, estén en el avión o en tierra); con uno solo, ¡VICTORIA! o quién ganó y tu puesto.
  Solo se gana si llegó a haber dos. Botones VOLVER AL LOBBY y SEGUIR MIRANDO.
- En el móvil, CURAR sale solo donde hay botín (`mobile_controls.gd`). El botón MAPA se quitó: el mapa grande
  se abre tocando el minimapa.
- **Las puertas se rompen**: madera 90 de vida, cristal 20, metal 350 (las dobles ×1,6). Balas (su daño), mazo
  (×2,5: dos golpes para una de madera) y explosiones. Rota, salta en tablones / esquirlas / chapas con física
  que caen y se van a los pocos segundos, y se avisa por red (`Net.net_puerta_rota`).
- **Arreglado**: la colisión de la hoja se quedaba en posición de cerrada (el AnimatableBody con
  `sync_to_physics` no sigue el giro del pivote): pared invisible en el hueco. `--pasapuertas` lo mide (el
  jugador anda hacia cada puerta): de 4 de 32 a todas.

Pruebas del final: `--pruebafin` (caen todos los bots: victoria, no vuelven) y `--pruebafin --morir`
(eliminado, puesto, sigue eliminado). `--touch --botonesmovil` dice qué botones se ven en cada mapa.

- **30 por partida, todos contra todos** (`Settings.BR_MAX_JUGADORES`, `main._bots_battle_royale`). Las salas de
  battle royale llegan a 30 plazas (`Settings.max_jugadores_de`; las demás siguen en 10) y el anfitrión rellena
  con bots lo que no llenen personas (en solitario, 29; con `--bots_br=N` para medir). Cada bot va en su propio
  bando (`br1`, `br2`...): no hay aliados, ni etiquetas de compañero, ni compañeros en el minimapa, y entre
  humanos hay fuego amigo (el servidor ya no descarta el tiro "del mismo equipo" en estos mapas). Medido en LAN:
  2 personas → 28 bots, y las dos máquinas con la misma ruta y las mismas zonas.
- **IA por distancia** (`enemy.gd`, `IA_LEJOS`): un bot a más de 70 m de cualquier persona piensa y se mueve uno
  de cada dos ticks. Con 29 bots peleando la IA bajaba de 6-11 ms por cuadro a 2,7-5,5. Aun así, con los 29 en
  tierra a la vez se juega a 25-60 fps según dónde sean las peleas (la GPU manda cuando hay humo cerca).

## Pendiente

- Nada probado en móvil. 17.700 chunks es el tamaño de Mónaco a 10 cm: en un móvil probablemente no cabe.
- Los demás ven a quien nada con la animación de caída (por red solo viaja "en el suelo").


## Cambios del 2026-09-20

- **Fuera los coches de adorno.** El mapa plantaba coches estáticos en las calles, el parking, la montaña,
  el bosque y el pueblo. Con coches **conducibles** en el mapa (ver [12_VEHICULOS.md](12_VEHICULOS.md)),
  un coche de atrezzo en mitad de la calle sólo sirve para que alguien corra hacia él y no pase nada.
  La función `ciudad.coche()` se queda por si otro mapa la quiere.
- **Fuera las líneas blancas de las carreteras.** Iban por los dos bordes de *todas* las carreteras y la
  isla entera se veía rayada de blanco. Queda el eje amarillo discontinuo y los pasos de cebra de los
  cruces.

## El arranque del battle royale (2026-09-20)

- **Se empieza SIN ARMAS.** En battle royale las dos ranuras de fuego salen vacías ("SIN ARMA") y sólo
  llevas el **mazo**: todo lo demás hay que encontrarlo en el mapa. En los otros modos el equipamiento
  sigue siendo el que eliges antes de entrar. La ranura vacía es un arma del catálogo (`vacio`) que no
  dispara ni recarga y que se sustituye al coger un arma del suelo.
- **La ruta del avión empieza en la costa**, no en la esquina del mapa. El mundo es un cuadrado pero la
  isla es redonda: entrando por una esquina el avión se pasaba **15 segundos sobre el mar** y lo único
  que veías al entrar era agua (medido: aparecía en 566,561, fuera del mapa de 499). Ahora se busca la
  primera tierra de la ruta y se arranca 5 s antes, con la costa a la vista.
- **Cortina "PREPARANDO EL SALTO…"** desde que arranca la partida hasta que despega el avión. En esos
  segundos el jugador está plantado en el suelo y **el mundo aún no está mallado**: lo único que se
  dibuja es la lámina de agua, y la pantalla se veía azul. La quita el avión al despegar (y un temporizador
  de seguridad a los 12 s, por si el despegue fallara).

## Los bots y la zona (medido)

`--map=isla --pruebabotszona [--minutos=N] [--relojzona=S]` adelanta el reloj de la zona y cuenta, cada
diez segundos, cuántos bots siguen vivos y cuántos están dentro del círculo.

| Círculo | Resultado |
|---|---|
| grande (radio 250 → 162) | **100 % dentro** todo el rato; sólo uno se queda fuera al final |
| medio (radio 112 → 70) | empiezan 8 de 11 dentro, mueren los que estaban fuera y **los que llegan se quedan al 100 %** |
| final (radio 29), puesto de golpe | **no llegan**: aparecen a 200 m del círculo y mueren antes |

Lo que se cambió al medirlo: a los bots que están **fuera del círculo de ahora** se les manda al centro y
se les **reintenta cada 6 s** (antes sólo se avisaba una vez por fase, y sólo del círculo *siguiente*: el
que se quedaba fuera se quedaba fuera hasta morir), y reciben **el mismo daño que el jugador** (antes el
doble, y morían antes de poder llegar).

El caso extremo sigue siendo extremo: si un círculo diminuto aparece de golpe a 200 m, no da tiempo. En
una partida de verdad el círculo se cierra por fases y eso no pasa.

**Ojo con medir esto**: si se quita el avión antes de tiempo, los bots que aún no han saltado se quedan
congelados, ni se mueven ni reciben daño, y la medición dice "los bots no entran en la zona" cuando lo
que pasa es que ni han aterrizado. La prueba espera a que hayan saltado todos.
