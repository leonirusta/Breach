# 10. Cómo construir un mapa para que no se caiga solo

Escrito el 2026-09-18 después de medir en Mónaco por qué, al romper algo, caían en cascada cosas que
nadie había tocado y se venían abajo trozos enteros de edificio. Las reglas de abajo salen de cómo
funciona el motor, no de gusto. Si un mapa las cumple, lo único que cae es lo que el jugador rompe.

## 1. Cómo decide el motor qué se cae (lo mínimo que hay que saber)

- **Conectividad por caras, de 6 vecinos.** Dos voxels que se tocan solo por una arista o por un
  vértice **no están unidos**. Un voxel de aire entre dos cosas las separa del todo.
- **Ancla = suelo.** Solo cuentan como apoyo los materiales con la marca `MF_ANCHOR`: `ground`,
  `asphalt`, `pavement` y `grass` (en el generador de Mónaco, el tipo `tierra`). La roca, la piedra,
  el hormigón y el adoquín **no anclan**: un edificio que solo toca adoquín está apoyado en el
  adoquín, y el adoquín tiene que tocar tierra. Lo que no llega a un ancla por una cadena de caras
  está **flotando**.
- **Regla *pristine*.** Un mapa recién cargado no se cae aunque tenga flotadores: todo conjunto que
  siga intacto se da por anclado. **En cuanto se daña cualquier chunk de un conjunto, o cualquiera
  de los 26 chunks vecinos de un chunk dañado, ese conjunto pierde la protección** y, si no toca un
  ancla, cae. Un chunk son 3,2 m a 10 cm por voxel: la "zona de daño" de una sola bala es un cubo
  de unos 10 m. Por eso una explosión suelta a la vez todos los adornos mal pegados de alrededor,
  y por eso cuanto más limpio esté el mapa menos cascada hay.
- **Al cargar, el motor suelda lo pequeño.** Desde el 2026-09-18, al terminar de cargar cualquier
  mapa, el motor busca los conjuntos flotantes de hasta 20.000 voxels y les rellena el hueco de aire
  hasta el sólido ajeno más cercano, si está a **0,5 m o menos** en línea recta por un eje (ver
  `[soldadura]` en la consola y `flotadores_soldados` en `get_stats()`). Es una red de seguridad,
  no una licencia: lo soldado deja un puente visible del material del adorno, y lo que esté a más
  de 0,5 m de todo sigue flotando.
- **Modelo de carga.** Además de la conectividad, el analizador estructural mide carga contra
  capacidad en celdas de 0,4-0,5 m. Se calibra con la estructura tal como viene en el mapa para que
  quede a 0,8 de su capacidad (`CALIB_TARGET`): un boquete que suba una celda un 25 % la hace ceder.
  Consecuencia para el constructor: **lo que sostiene algo tiene que sobrar**, no ir justo.

## 2. Reglas de construcción

1. **Mordida mínima de 0,25 m.** Todo lo que se pegue a un muro, un suelo o un techo se dibuja
   **metido dentro** al menos 0,25 m (2-3 voxels a 10 cm), nunca "a ras" ni con un margen. Un
   margen de 0,04-0,12 m es un voxel de aire a 10 cm, y a 20 cm (el mapa `_lo`, el del APK y la
   LAN) puede desaparecer o convertirse en hueco según caiga el redondeo.
2. **Los apoyos, en el suelo de verdad.** La base de un objeto apoyado va a la altura exacta del
   suelo o un voxel por debajo, nunca `suelo + 0,1`. Cipreses, setos, farolas, bancos y macetas de
   Mónaco estaban a un voxel del suelo.
3. **Cristales dentro del hueco.** La ventana se pinta en el plano del muro, mordiendo el marco;
   nunca delante de la fachada (en el casco de Mónaco iban 19 cm por delante, colgados en el aire).
4. **Arcos, nervios y bóvedas: dovelas que se solapen.** Si se traza a pasos, el paso tiene que ser
   **menor** que la pieza (dos dovelas seguidas deben compartir caras enteras, no una arista).
5. **Vuelos y balcones: empotrados.** Una losa que sale de un muro entra en él al menos 0,25 m y
   además se apoya en ménsulas o pilares si vuela más de 1,5 m. Los balcones de las torres de Mónaco
   (392 voxels cada uno) no tocaban la torre.
6. **Lo que cuelga, cuelga de algo que llegue al suelo.** Toldos, lámparas y carteles se unen al
   muro con su propio soporte (una barra que muerda 0,25 m). La "luz" de una farola es un voxel
   más del cuerpo de la farola, no un voxel suelto dentro de la cabeza.
7. **Cimientos anchos.** Un edificio apoya en toda su planta baja sobre material que llegue a un
   ancla, no en una fila de adoquines o en los marcos de las puertas. Si el terreno es roca o
   piedra, la roca tiene que tocar tierra (`ground`) por debajo.
8. **Muros y pilares con margen.** A 10 cm por voxel un muro de 2 voxels (20 cm) sosteniendo una
   cubierta de piedra está al límite; a partir de 0,3 m y con pilares de 0,4 m el modelo de carga
   aguanta un boquete sin tirar la planta entera. La misma demolición de 3 explosiones tira 10-15
   veces más masa en el mapa de 10 cm que en el de 20 cm: **lo fino se rompe más** (ver §4).
9. **Nada con un voxel de hueco "decorativo".** Pilas de cajas cada 1,0 m con cajas de 0,9 m,
   losas que terminan justo donde empieza el muro pero una altura más arriba: los dos bugs
   clásicos del generador de `pruebas`. Cada pieza toca la siguiente por una cara completa.
10. **El agua es sólida** para el motor: lo que flote en el mar tiene que tocar el agua.

## 3. Cómo se comprueba (obligatorio antes de dar un mapa por bueno)

```bat
:: en el motor, sobre el mapa REAL que carga el juego (10 cm en PC): cada conjunto sin ancla,
:: de mayor a menor, con su centro en metros. Se ejecuta DESPUES de la soldadura automatica.
Godot_v4.7.2-stable_win64.exe --headless --path godot -- --map=monaco --auditaflotadores

:: lo mismo ANTES de soldar (lo que trae el mapa de verdad):
set VX_NOWELD=1 && Godot_v4.7.2-stable_win64.exe --headless --path godot -- --map=monaco --auditaflotadores

:: a 20 cm, con material y patrones repetidos (util para saber QUE es cada cosa):
python tools\auditar_flotadores.py godot\maps\monaco_lo.vxmap
```

Objetivo: **0 conjuntos de 100 voxels o más** antes de soldar, y ningún conjunto que "caería al
vacío". Los de menos de 100 voxels casi siempre son adornos a un voxel de la pared: mejor
arreglarlos en el generador que dejárselos a la soldadura.

Para ver el efecto en juego: `--bancofps --map=<mapa> --sitio=x,y,z,giro --explosiones=3` imprime
cuántas piezas y voxels caen por desconexión y cuántos por sobrecarga, y el tamaño de la mayor.

## 4. Lo que se midió en Mónaco (2026-09-18)

| | antes | después de soldar |
|---|---|---|
| Conjuntos sin ancla (10 cm) | 906 (93.779 voxels, el mayor 6.720) | 151 sin nada a 0,5 m (≈15.000 voxels) |
| Conjuntos sin ancla (20 cm) | 166 (2.572 voxels) | 48 |
| 1 explosión de 2,2 m | 743 voxels sueltos | igual (no tocaba nada soldado) |
| 3 explosiones de 2,2 m, mapa 10 cm | 45.000-64.000 voxels, casi todo por **sobrecarga**, pieza mayor 10.912 | igual: es el modelo de carga |
| 3 explosiones, sin modelo de carga | 9.661 voxels por desconexión | |
| 3 explosiones, mapa 20 cm | 553 voxels, 0 fallos estructurales | |

Lo que se lee de ahí: los adornos en cascada eran el mapa (y ya se sueldan), pero **los trozos
grandes que caen tras varias explosiones los decide el modelo de carga**, y a 10 cm por voxel es
mucho más severo que a 20 cm con la misma geometría. No se ha tocado (`vxstructtest` sigue siendo
la referencia); si algún día se recalibra para mapas de 10 cm, los mandos son `CALIB_TARGET`
(`VX_CALIB=<valor>` lo cambia sin recompilar), `criticalRatio`, `safetyMargin` y `bucklingMin` en
`vx_structure.h`, y hay que volver a pasar `--mesatest` y `vxstructtest`.

**Lo que ya se probó y NO vale como está (2026-09-18):** subir `bucklingMin` de 0,06 a 0,35 pasa
todas las pruebas del núcleo (arregla el test del pilar 2x2, que hoy falla) pero en Mónaco tira
**más** (84.000 voxels frente a 45-64.000), y `VX_CALIB` 0,8 → 0,5 → 0,35 da 45-84 k → 104 k → 8 k:
no es monótono. El analizador itera en hilos de trabajo a un ritmo que depende del tiempo de cada
cuadro, así que **dos corridas iguales no derrumban lo mismo** (45 k y 64 k con la misma semilla y
la misma vista). Calibrarlo exige un banco determinista fuera del juego, no el `--bancofps`.

## 5. Bloques que aterrizan (reglas nuevas del 2026-09-18)

Cuando un bloque suelto se para, antes de congelarlo el motor mira **la cara inferior real del bloque,
en su postura real** (antes miraba bajo la caja envolvente, y un tablero inclinado "no tocaba nada"):

- **Compresión con impacto.** Carga = su masa × (1 + caída/0,1 m, tope ×8), medida desde la altura
  máxima que alcanzó. Capacidad = voxels de contacto × 660 × (0,25/voxel), la misma escala que el
  analizador. Si no aguanta, **se aplasta la cabeza del apoyo** (0,5 m de radio, 0,6 m de fondo) y
  el bloque sigue bajando; se vuelve a juzgar a los 0,6 s. Aplastar **no cuenta como daño** para el
  analizador (contaba, y en Mónaco encadenaba 575.000 voxels con tres explosiones).
- **Vuelco.** Si el centro de masas queda fuera de la caja de sus contactos con el mundo (0,3 m de
  margen), no se congela: se le deja volcar.
- **Tacos sueltos.** Si lo que lo sostiene son bloques con menos de 1/8 de su masa (los tramos de pata
  que deja el mazo), se hacen añicos y el bloque baja.
- **Partición** de los derrumbes por sobrecarga: cubos de 14 m (eran 8). Solo afecta a grupos mayores
  que 12 × `maxBodyVoxels`; el techo de la mesa (66.000) no llega y sale en UNA pieza.

Lo que sigue siendo física y no fallo: si el mazo corta una pata **por debajo** del tablero y el tramo
de arriba queda de pie sobre su tocón, ese tramo sostiene el tablero a compresión igual que la pata
entera. Para que caiga hay que quitar la pata (explosión) o tirar el tramo.

**Lo que cede se hace polvo si es pequeño.** Las celdas que fallan por carga (la cabeza de un pilar, una
celda suelta) nacían como bloques propios un instante antes de que se desprendiera lo que sostenían:
"bloques pequeños que se sueltan en el aire". Ahora lo que falla y no llega a 1,5 m³ sale como escombro
(partículas); un tramo de pared entero sigue cayendo como bloque. Y el analizador ya no espera hasta 2 s
a que el mundo esté quieto para iterar (0,4 s), el rebote de las sombras es de 0,2 s y un bloque
despertado por vuelco se vuelve a juzgar a los 0,3 s: el derrumbe se entera antes de que tiene que caer.

**Correcciones del mismo día, tras probar en `pruebas` con `--volar=x,y,z,r|...`** (vuela puntos fijos y
lista cada bloque con posición y estado durante 25 s): lo que cede vuelve a caer como bloque (el polvo
convertía un trozo de vía en partículas); solo aplastan los bloques de 3 m³ o más, con impacto tope ×4,
radio 0,3 m y solo si la carga dobla la capacidad; "quieto" exige no estar bajando (los bloques grandes
caen a cámara lenta y se anclaban en el aire); al rehacerse la colisión de un chunk se despiertan también
los bloques ya anclados que se apoyaban en la colisión vieja; y un bloque sin nada debajo no se congela.

## 6. Ni una cosa más

- No se le pasa `fix_floaters.py` a un mapa generado: deja caer cada conjunto hasta que apoye y
  destroza los interiores. Para eso está la soldadura del motor (rellena, no mueve).
- El `_lo` (20 cm) es el mapa que va en el APK y el que se usa en LAN: lo que solo se sostiene a
  10 cm no se sostiene en la partida real.
