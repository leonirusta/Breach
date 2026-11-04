# BREACH

FPS para PC y móvil (estilo Call of Duty Mobile) con **destrucción total del entorno** por voxels (estilo Teardown),
diseñado para gama baja desde el primer día.

```
core/     vxcore — núcleo de destrucción C++17, cero dependencias, agnóstico de motor
godot/    proyecto Godot 4.7 + GDExtension que conecta vxcore con el renderer y Jolt
tools/    scripts de compilación (MSVC + CMake + Ninja)
docs/     01 arquitectura · 02 destrucción · 03 rendimiento · 04 build · 05 roadmap
```

## Empezar (Windows)

```bat
tools\build_core.bat            REM núcleo + tests + benchmark
core\build\vxtest.exe           REM 123 comprobaciones
core\build\vxbench.exe --quick  REM benchmark headless
tools\build_extension.bat       REM GDExtension (requiere godot-cpp en godot\extension\godot-cpp)
"C:\Users\usuario 1\Desktop\GodotEngine\Godot_v4.7.2-stable_win64.exe" --path godot
```

Teclas: WASD/ratón, clic izq. disparar, clic der. apuntar, R recargar, Q arma, G granada, **F3 perfilador**, F4 CSV,
F5 calidad, **F6 demoler el edificio más cercano**, **F7 bots on/off** (también botón BOTS en el HUD).
Accesos directos: `JUGAR.bat` (juego) y `EDITOR.bat` (editor).

## Lobby

El juego arranca en un lobby con tu avatar en el centro (arrástralo para girarlo, tócalo para un emote):

* **JUGAR**: elige mapa (Dust 2 o Ciudad), bots sí/no y entra con el botón amarillo (o Enter).
* **TAQUILLA**: skins (tintes) del avatar; se aplican a tu sombra en primera persona.
* **AJUSTES**: calidad, calidad adaptativa, voxels finos, perfilador, sensibilidades, controles táctiles.
* En partida, **F10** o el botón LOBBY vuelven al lobby. Las banderas de benchmark/captura saltan el lobby.

![Lobby](docs/lobby.png)

Los 39 clips del avatar (Teardown) se pueden revisar en hojas de poses: `--poseshot=N` (N = 0..3, diez clips
por hoja) o `--poseclips=idle_1,crouch_idle,...` (fila a ras de suelo). Capturas en `docs/avatar_poses_*.png`.
Los clips no traen traslación de raíz, así que `avatar_animator.gd` baja el esqueleto por clip hasta que el pie
más bajo toca el suelo (agacharse, saltar, sentarse). Formato del `.bin` (verificado con las poses de referencia
`ik_pose_t` / `ik_pose_a`): el bind es la pose T modelada, las claves son rotaciones LOCALES respecto al padre y
están en los ejes originales del modelo (Z arriba): se conjugan por una rotación de -90° en Y para pasarlas al
rig, y el esqueleto se construye con los marcos de reposo nativos (offsets expresados en el marco del padre).

**Arma en las manos** (`avatar_animator.gd::equip_weapon(kind)`), portado del código real de Teardown
(`data/script/toolanimation.lua`, `player_locomotion.lua::locomotion_ik` y las ubicaciones `tp_*` de
`data/prefab/tool/rifle|shotgun|rocket.xml`): el arma se coloca en "espacio del ojo" (1,7 m sobre los pies, sólo
guiñada) con la pose `tp_action` al disparar o apuntar (fusil al hombro, escopeta a la cadera, lanzacohetes al
hombro) y, tras 2 s sin disparar, con `tp_run` (fusil cruzado en bandolera) mezclada con `tp_jump`/`tp_crouch`
según el clip. Se suman el bamboleo del hombro derecho, el cabeceo del brazo alrededor del cuello, el balanceo por
el pie derecho y el cabeceo del propio arma (`look_pitch`); mirar arriba/abajo arquea estómago/pecho/cabeza y el
retroceso (`kick()`) echa el pecho atrás y la cabeza adelante. Una IK analítica de dos segmentos por brazo (hombro
+ brazo superior rígidos, antebrazo) lleva las manos a la empuñadura y al guardamanos del modelo; el codo se orienta
hacia un imán. Teardown tiene +X a la derecha y nuestro modelo la tiene en -X: las poses se espejan.
Capturas: `docs/avatar_arma_perfil.png` (acción, bandolera, escopeta), `docs/avatar_arma_perfil_agachado.png`,
`docs/captura_bot_bandolera.png`. Hojas: `--poseweapon [--poseaction] [--posekind=shotgun|rocket] [--poseside|--poseback|--poseface]`.

**Primera persona**: el arma a la cadera usa la pose `fp_action` de Teardown de cada arma (`player.gd::FP_HOLD`:
más lejos y más baja, con un giro leve hacia el centro; al apuntar la mira queda en el eje), ver
`docs/fp_teardown_poses.png`. Brazos y manos reales (avatar sólo-brazos colgado de la cámara, `player.gd::_equip_model`)
guiados por la misma IK hasta la empuñadura y el guardamanos del arma activa, también al apuntar. Tres modelos de
arma (`weapon_model.gd`, `kind`): fusil con mira holográfica, escopeta de corredera y lanzacohetes tipo RPG. Los
huesos NO se escalan (una escala no uniforme obliga a Godot a hacer el skinning por software: 55 ms por frame);
los brazos van a escala real, bajos y algo por delante del ojo, con puntos de agarre cercanos. Capturas:
`docs/fp_fusil_ads.png`, `docs/fp_escopeta.png`, `docs/fp_lanzacohetes.png` (`--screenshot --weapon=N [--ads]`).

## Sonido

Los efectos son los de Teardown, descifrados y copiados desde la instalación con
`python tools\import_teardown_sounds.py "C:\Games\Teardown" godot\sounds	d` (685 archivos, 28 MB: golpes,
roturas, pasos, saltos y caídas por material; explosiones; armas; impactos y silbidos de bala; chispas; ambiente).
`scripts/audio.gd` (autoload `Audio`) traduce cada material de vxcore a una carpeta de Teardown por dureza
(cristal, madera, plástico, tierra, metal, mampostería) y elige una variante al azar: impactos de bala con su
tamaño de cráter, roturas de piezas según su volumen, escombros y piezas al caer, explosiones por radio, pasos
según el material bajo los pies, saltos y aterrizajes, disparos propios (2D) y de bots (3D), balas que pasan cerca.
Volumen general en el lobby (AJUSTES > Sonido).

Mezcla: las voces tienen **prioridad** (explosión > disparo > rotura > impacto/escombro); un sonido nuevo coge una
voz libre o roba la de menor prioridad más antigua, y sólo impactos/escombros tienen presupuesto por frame (antes
la explosión del cohete se perdía entre las decenas de roturas del mismo frame). Distancia: inverso del cuadrado +
paso-bajo progresivo (lo lejano suena apagado) + retardo de 340 m/s a partir de 40 m. Espacio: bus `World` con
reverberación cuya mezcla se mide cada 0,2 s con rayos de línea de visión alrededor del oyente (interiores con eco,
exteriores secos). `--audiodbg` imprime cada explosión y las voces descartadas.

## Mapas

* **Dust 2** (por defecto): importado del mod de Teardown del escritorio con `tools/bake_teardown_map.py` y
  limpiado con `tools/fix_floaters.py` (borra los trozos de voxels sin conexión con el suelo que deja la
  importación y deja caer el atrezo que quedó un voxel en el aire). Los objetos colocados por nombre
  (`<vox object="...">`: hojas de palmera, antenas, macetas, cubos, patos...) pivotan como en Teardown, en el
  centro de su base y no en su posición dentro de la escena de MagicaVoxel: antes quedaban cientos de piezas
  flotando lejos de su sitio.
  (escena XML, 314 `.vox`, prefabs, terreno del `ground.lua` + heightmap). 44 M de voxels a 10 cm en PC
  (`godot/maps/dust2.vxmap`, 10,6 MB) y versión de 20 cm para móvil (`dust2_lo.vxmap`). Paleta real cuantizada a
  208 materiales conservando la clase física de Teardown (cristal, madera, ladrillo, metal, roca…).
* **Hangar** (`godot/maps/hangar.vxmap`): port de *Voxel Hangar | Warface* para Teardown (`map.zip` del
  escritorio). 192×162 m, 223 M de voxels, 10.344 chunks (~400 MB en memoria, el doble que Dust 2): el horneador
  aprendió `<voxbox brush=...>` (cajas rellenas con un patrón `.vox` repetido), `<compound>`, colocación por losas y
  omite la limpieza de flotadores en mapas de más de 500 M de celdas.
* **Ciudad procedural**: F8 alterna entre mapas (o `--city` / `--dust2` / `--map=<nombre>` por línea de comandos).

Volver a hornear tras cambiar el mod:

```bat
python tools\bake_teardown_map.py "C:\Users\usuario 1\Desktop\dust 2" "C:\Users\usuario 1\Desktop\dust 2\de_dust2.xml" godot\maps\dust2
python tools\fix_floaters.py godot\maps\dust2.vxmap
python tools\fix_floaters.py godot\maps\dust2_lo.vxmap
```

## Armas, armería y C4

73 modelos del *Soviet Weapons Pack* de Teardown horneados a mallas exactas (`tools/bake_weapon.py`), cada uno con
sus estadísticas (`weapons.gd`), elegibles en la pestaña **ARMERÍA** del lobby (ranuras PRIMARIA / SECUNDARIA /
PESADA; la C4 va siempre en la 4). Detalles en `docs/07_ARMAS_Y_ARMERIA.md`.

## Regla "intacto" (por qué antes flotaban los objetos rotos)

Un nivel recién cargado no se derrumba: lo que está intacto se considera estático aunque no toque el suelo
(atrezo importado que quedó un voxel en el aire). Esa regla se aplicaba **por chunk**, así que al romper un
objeto que cruzaba varios chunks (un poste, una antena, un coche), la parte que seguía dentro de un chunk sin
tocar quedaba "anclada" y se quedaba flotando. Ahora se aplica **por conjunto conexo**
(`ConnectivitySolver::solve`, pase 2b): en cuanto se daña cualquier chunk del conjunto, sólo cuentan las anclas
reales (suelo o material ancla) y lo que queda sin apoyo cae. Matices: la "zona de daño" son los chunks con daño de juego (balas, explosiones) y sus vecinos; un objeto
intacto que esté ahí aunque no esté conectado voxel a voxel con su soporte (los contenedores importados apoyan
con un voxel de hueco) también cae. Extraer una pieza o re-voxelizarla al reposar NO cuenta como daño, para que
una caída no arrastre en cadena a todo lo que flota alrededor. `fix_floaters.py` limpia también mapas gigantes
(por losas con union-find; sólo borra fragmentos sueltos pequeños). Prueba: `--dust2 --falltest=x,y,z[,r]` explota ahí
e imprime las piezas desprendidas y los cuerpos activos a los 150 frames.


### Rondas y contador (2026-09-07)

Los bots aparecen en los puestos de los dos sitios de bomba (a 60-100 m del spawn) y antes TODOS se quedaban allí en
GUARD: el jugador recorría el mapa sin cruzarse con nadie ("no aparecen los bots"). Ahora la mitad son **rondas**
(`enemy.rover`): su ruta son puestos de ambos sitios + 4 puntos de suelo repartidos + un punto junto al spawn, con
paradas de 1-3 s. `_go_to` ya no da por "inalcanzable" un destino sin camino A* (el tope de nodos cubre ~55 m):
planifica hasta un punto intermedio a 18 m y, si tampoco, camina recto hasta 6 replanificaciones. El HUD muestra
"Bajas · Bots vivos". Diagnóstico: `--botsdbg` imprime posición/vida/estado de cada bot en los frames 60/150/300/600.

## Bots (defensores tipo CS2)

Los bots ya no saben dónde estás. Cada mapa tiene dos **sitios de bomba** (automáticos: dos puntos de suelo lejos
del spawn y entre sí, o fijos en `res://maps/<mapa>.sites.json` con `{"sites": [[x,y,z],[x,y,z]], "radius": 12}`)
con seis puestos de guardia alrededor. Cada bot defiende un sitio: se queda en un puesto (de pie o agachado,
barriendo con la mirada), camina al siguiente, y sólo reacciona a lo que percibe: verte dentro de su cono de
110° con línea de visión por voxels (con tiempo de reacción, más corto de cerca; agachado y lejos cuesta más
verte), oír tus disparos (50 m, 14 m silenciado, 120 m explosiones), recibir daño o el aviso de un compañero a
menos de 20 m. Al verte dispara, avanza o se desplaza de lado y a veces se agacha; si te pierde va a tu última
posición conocida, busca unos segundos y vuelve a su puesto. `scripts/enemy.gd` (estados GUARD / PATROL /
INVESTIGATE / COMBAT / SEARCH).

## Escombros (comparado con Teardown)

En Teardown una explosión hace tres cosas: el cráter es irregular (no una esfera limpia), lo que se desconecta
se convierte en cuerpos rígidos que se quedan en el mundo, y encima salen partículas pequeñas (25-100 de 3-5 cm,
`explosion.lua`) de vida corta. Aquí igual: el cráter se modula con ruido por voxel (±20 %, `carveSphere`), por
cada ~30 voxels destruidos se lanza un **trozo macizo** de 3-4 voxels de lado (30-45 cm) como cuerpo rígido con
velocidad radial (`Engine::emitClumpsFor`, siempre cuerpo aunque sea pequeño, con conservación de masa), y las
partículas de 1 voxel viven 7-12 s (4 s más en reposo) con pools de 512/2048/4096/8192 según calidad.

> **YA NO SE RE-VOXELIZA NADA** (2026-09-14). Lo que se desprende es un bloque desde que se suelta
> hasta siempre: conserva su forma y su ángulo exactos, se duerme al pararse y solo lo despierta el
> daño. Meterlo de vuelta en la rejilla —que no está girada— obligaba a repintarlo y le cambiaba la
> forma al pararse. Todo el modelo, en **[docs/09_BLOQUES_Y_RED.md](docs/09_BLOQUES_Y_RED.md)**.

## Rendimiento con bots (diagnóstico de tirones, sept 2026)

Los bots en sí cuestan 0,15 ms por bot y tick. Los frames lentos venían de: (1) cada pieza rígida y cada chunk
estático llevaban hasta 20 cajas de colisión y Jolt las cruza todas por par (18 cuerpos activos = 16 ms de
física): ahora las piezas llevan 6 cajas y se duermen/re-voxelizan a los 3 s; (2) fusionar 3 regiones por frame
tras una explosión (10-15 ms cada una): ahora 1 por frame y sólo cuando la región lleva 0,35 s sin cambios;
(3) crear 8 cuerpos estáticos de colisión por frame al andar: ahora 4; (4) la física de Godot recuperaba hasta 4
pasos seguidos tras un tirón, alargándolo: máximo 2. Los avatares de los bots se animan a 30/20/8 Hz según distancia
y no se actualizan fuera del encuadre. Banderas de diagnóstico: `--botsfreeze --botsnoshoot --botsnocol
--botsnophys --botsnoavatar --botsnoweapon --botsanim0`; `[bots]` imprime el coste por sección en `--bench`.

## Derrumbe estructural progresivo (activado por defecto) — sistema nuevo (2026-09-08)

El "modelo de carga por nivel" de antes (sumaba soporte y masa por altura dentro de una zona de chunks y hacía
ceder el nivel más bajo) producía **falsos derrumbes globales**: la frontera de la zona cortaba los muros del edificio
de al lado, el daño era global por nivel y el edificio B se venía abajo con un misil en A. Se ha sustituido por un
**analizador de rutas de carga** (`core/src/vx_structure.cpp`, `StructuralAnalyzer`), documentado en
`docs/08_AUDITORIA_ESTRUCTURAL.md`:

```
explosión -> daño voxel -> región (celdas de 0,5 m escaneadas desde la memoria de los chunks)
  -> LÍNEA BASE (la región con los voxels destruidos repuestos: lo construido por el autor es estable por definición)
  -> islas por CONTACTO REAL de voxels (dos edificios a 1 m no comparten carga)
  -> rutas de apoyo: pilares (apoyo debajo con ruta) y vigas (contacto lateral hasta un pilar, con momento)
  -> reparto de cargas de arriba abajo (vigas -> pilares en cono de 45° -> suelo)
  -> ratio carga/capacidad por celda; sólo falla lo que el daño EMPEORA (ratio > máx(1,08, base x 1,1))
     y sólo tras acumular deformación (racha), las K peores celdas por iteración
  -> las celdas que fallan salen como fragmentos con vuelco; lo que pierde la conexión con el suelo lo desprende
     el solver de conectividad -> siguiente iteración (cada 6 frames, en un hilo de trabajo) hasta estabilizar
```

Reglas clave: redundancia continua (quitar 1 pilar de 9 sube un 11 % la carga de los otros: nada cae; quitar 7 sí),
independencia (sólo se evalúan las islas tocadas por el daño; la frontera de la región cuenta como apoyo intacto),
elementos no portantes (un tabique de pladur, una vidriera o el escombro se sostienen a sí mismos pero NO son pilar
de la losa que tienen encima: la losa apoya en los muros, y volar el tabique no la tira),
colapso parcial (esquinas, forjados, alas) y demolición real (el cinturón de cargas de F6 tira el edificio entero
por conectividad). Capacidad: `STRESS_CAPACITY` = 660 (una estructura sana queda al 30-45 %, factor de seguridad
~3 como en ingeniería); materiales con parámetros físicos centralizados (`vx_material.h`: compresión, tracción,
cortante, umbral de fractura, rigidez, fricción, restitución por clase: hormigón, ladrillo, piedra, madera, metal,
cristal, blando, suelto). Afinado en vivo: `VoxelWorld.set_struct_param("moment_factor", 1.0)` etc.
**F11** (sólo builds de depuración) dibuja las celdas evaluadas por ratio (verde/amarillo/naranja/rojo, magenta =
sin apoyo, gris = fallida, azul = suelo), la región, el centro del daño y el centro de masas/apoyo de cada isla.

Pruebas (`core\build\vxstructtest.exe [filtro]`, 33 comprobaciones): 1/2/7 pilares de 9, losa sobre un pilar,
boquete en muro, agujero en tejado, esquina, explosión grande, demolición (1 cohete = boquete; 5 cohetes en los
lados = derrumbe parcial; cinturón + carga central = al suelo), dos edificios a 1 m (B conserva el 99 % y el
tejado entero), edificios separados, edificios unidos por pasarela, voladizo, estructura flotante, edificio de
470 k voxels (una explosión pequeña: 2 celdas), ráfagas y explosiones repetidas, determinismo (mismo hash),
raycast jerárquico == voxel a voxel (10.000 rayos, 0 discrepancias).

Benchmark (`core\build\vxbenchstruct.exe`, i3-N305, 5 cohetes en la planta baja de un edificio de muros):

| voxels | ms/iteración (media / máx) | iteraciones | celdas fallidas | solve conectividad |
|---|---|---|---|---|
| 11 k | 5,1 / 17,9 | 17 | 637 | 0,013 ms |
| 79 k | 9,0 / 24,7 | 18 | 920 | 0,026 ms |
| 660 k | 14,6 / 39,9 | 27 | 4.867 | 0,14 ms |
| 2,0 M | 31,6 / 49,2 | 9 | 1.681 | 0,34 ms |

Todo en un hilo de trabajo (el principal sólo encola y reparte fragmentos); la primera iteración incluye el escaneo
de la región y la línea base. Rayos: el DDA jerárquico (chunk -> 8³ -> 4³ -> 2³ -> voxel, ocupación de 584 B por
chunk) tarda 1,1 µs por rayo de 120 m frente a 5,1 µs del DDA voxel a voxel (x4,7; 1,7 pasos de voxel y 10,9 saltos
de región vacía por rayo). El solve global ya no toma el lock de los chunks sin componentes (espejos atómicos).

### Modelo anterior (histórico)

El solver de conectividad (`vx_connectivity.cpp`, pases 3/4) llevaba un modelo de carga: para cada estructura anclada
acumulaba por nivel el soporte S(y) (sección de materiales portantes) y la masa M(y); cedía en el nivel más bajo donde
masa_encima > S(y) · `STRESS_CAPACITY` (220, escala con el tamaño de voxel) y sólo en la zona dañada (lo intacto no
se derrumba al cargar). Está siempre activado (`Settings.structural_load`, sin casilla en el lobby: forma parte
de la destrucción). Lo que cede:

* **Se inclina hacia el lado sin apoyo**: `Engine::tiltForFailure` compara el centro de masas de la parte que cede
  con el centroide de su capa de apoyo y le da velocidad angular (0,35-1,4 rad/s) alrededor del eje horizontal
  perpendicular, más un empujón lateral (`VoxelBody::initialAngVel`, aplicado en `spawnPiece`). Así una pared o
  torre no se queda en equilibrio sobre un muro fino: vuelca como en la realidad.
* **Un edificio entero se desmorona**: si la parte que cede supera `maxBodyVoxels`, en vez de partirse en cubos de
  chunk se parte en bloques irregulares de **1,4 m fijos** (partición por celdas con bordes dentados por ruido), cada
  uno con su variante de la inclinación; caen, se apilan y se re-voxelizan en el suelo. **Competitivo**: ni el tamaño
  de bloque ni el número de trozos por explosión (`maxClumps` = 32) dependen de la calidad o la plataforma: todos
  los jugadores ven los mismos trozos (con el mismo mapa y tamaño de voxel). La calidad sólo decide cuántos se
  simulan con Jolt y cuántos caen "baratos" (cinemáticos, que re-comprueban su apoyo cada 10 frames).
* **Nada se re-voxeliza en el aire**: `VoxelWorld::bodySupported` sondea bajo la cara inferior del cuerpo; si no
  descansa sobre voxels estáticos (p. ej. dormido sobre otros cuerpos de la pila) se despierta y sigue siendo cuerpo.
  Antes eso dejaba trozos flotando y provocaba cascadas de piezas.

### Por qué "rompía paredes solo" y daba lag (y cómo se arregló)

Con el modelo de carga activo, tras un derrumbe el juego seguía desprendiendo piezas durante segundos y bajaba a
15-25 fps. Causas encontradas con `VX_LOGGROUPS=1` (log de cada grupo desprendido) y los contadores
`groups_structural/groups_plain/group_voxels` de `get_stats()`:

1. **Cascada de re-voxelización**: un cuerpo dormido se colocaba 1-3 voxels por encima de lo que lo sostenía (las
   cajas de colisión son más gruesas que los voxels), quedaba sin conexión con el suelo, el solver lo desprendía y
   volvía a caer: bucle infinito de piezas. `Engine::revoxelize` ahora **asienta** el conjunto bajándolo hasta tocar
   un voxel sólido (máx. 6). Y `VoxelWorld::bodySupported` no re-voxeliza lo que descansa sobre otros cuerpos.
2. **Fallos espurios en los vecinos**: 4 s después, edificios contiguos "cedían" con 60-120 k voxels sin que nadie
   los tocara: el análisis es local a la zona dañada y la frontera corta sus muros (mucha masa, poco soporte
   contado). Ahora el modelo de carga sólo se evalúa en la **ventana de 1,5 s tras un daño real**
   (`Engine::armLoadEval`, `ConnectivitySolver::evalLoad`); extracciones y re-voxelizaciones no lo disparan. La
   zona de carga también usa sólo chunks con daño de juego (`damaged`), no cualquier chunk no intacto.
3. **Escombro**: el material `rubble` casi no cuenta como masa ni soporte (3/16): una pila de cascotes sobre un
   forjado no lo hace ceder.
4. **Picos del hilo principal**: los ~500 cuerpos de un edificio se creaban en un solo frame (~2 s de parón) ->
   cola `pendingPieces_` con tope de 5 ms/frame; los trozos de cada explosión se construían en el hilo principal
   (20-37 ms) -> ahora en hilos de trabajo; `flushBlocks` y `flushPhysics` tienen tope de tiempo (4 y 3 ms) además
   del de número; tope duro de cuerpos Jolt = `maxBodies` (el resto cae "barato").

5. **Espiral de pasos de física**: `max_physics_steps_per_frame` era 2; en cuanto un frame pasaba de 16,7 ms Godot
   ejecutaba dos pasos de Jolt (2 x 10 ms) para "recuperar", el frame se iba a 33 ms y ya no salía de ahí. Ahora es
   **1** (si un frame va lento la física va un poco a cámara lenta en vez de duplicar su coste). Fue el cambio con
   más efecto: el derrumbe entero pasó de 27-33 ms/frame a 16,5 ms de media.
6. **Trozos grandes primero**: `pendingPieces_` se ordena por tamaño descendente, así las losas y muros grandes se
   llevan los cuerpos Jolt disponibles (`maxBodies`) y los pequeños caen "baratos" con el empuje lateral del vuelco
   (`Body::drift`); los trozos de un derrumbe nunca se teletransportan al suelo (el atajo de saturación
   reconstruía el edificio en el sitio como pila con forma de fachada). `BodyBuilder::build` reinicia el cuerpo, por
   lo que `initialVel/initialAngVel` se asignan después (antes se perdían y ningún trozo volcaba). El radio
   "urgente" de `flushPhysics` (chunks que saltan el presupuesto) baja de 5 a 1,5 m.

Resultado en la máquina de referencia (Intel UHD, MEDIUM, `--falltest`): un RPG contra la base de un edificio
~60 fps (16,0-16,3 ms de media); demoler un edificio entero de 3 plantas con 6 RPG simultáneos **16,5-16,7 ms de
media durante todo el derrumbe** (antes 15-25 fps sostenidos y piezas creciendo sin fin). Los frames >20 ms que
quedan son los picos de la extracción (explosión 10-17 ms en el núcleo) y de re-voxelización.

Bugs relacionados corregidos después: (a) las balas atravesaban paredes desprendidas que caían "baratas" (sin forma
Jolt ni voxels hasta re-voxelizarse): `VoxelWorld::shoot` ahora prueba primero el rayo contra los cuerpos baratos
(`rayCheapBody`, AABB + marcha por su rejilla) y los talla (`--cheapshot` lo verifica); (b) "algo se rompe solo al
entrar": una explosión de prueba en `main.gd` (frame 120) se disparaba siempre; ahora sólo con `--explodetest`.

Limitación conocida: el modelo de carga es vertical (soporte por nivel). Una losa de tejado que sigue unida a un
muro que queda en pie se comporta como voladizo infinito y no se rompe (en Dust 2 se ve el tejado del edificio de
prueba colgando del muro trasero). Haría falta una regla de voladizo (distancia horizontal al apoyo) para partirla.

Prueba: `--falltest=x,y,z,r[,x,y,z,r...]` (varias explosiones en el frame 150, imprime ventanas de tiempo de frame,
fases del host `t_h_*`, GDScript por nodo via el autoload `Prof`, render GPU/CPU) con `--standat/--lookat/--shotframes`;
`--probe` imprime las paredes alrededor de la cámara para elegir coordenadas; `--noload` desactiva el modelo de
carga para comparar; `VX_THREADS=n` fuerza los hilos de trabajo.

## Armas (estado actual)

El juego lleva sólo las tres armas principales (FUSIL, ESCOPETA, LANZACOHETES, modelos por código) más la C4 del mod
de Teardown. El pack SWP horneado (73 modelos) se retiró de `godot/weapons/` (`catalog.json` vacío) a petición del
usuario; los archivos están en `Desktop\Breach_pack_armas_backup` y `tools/bake_weapon.py` sigue pudiendo
regenerarlos. La armería del lobby y `STATS` de `weapons.gd` siguen funcionando con cualquier catálogo.

## Explosiones

### Conservación de masa: lo que se destruye cae

`Engine::emitClumpsFor` convierte ~85 % de los voxels que quita una explosión en trozos rígidos (blobs
irregulares de 12 a cientos de voxels; su tamaño crece con la masa a repartir y su número lo acota
`maxBodies/2` por calidad). Salen del cráter con velocidad según distancia al centro (los grandes más despacio),
caen, se duermen y `revoxelizeBody` los vuelve a integrar en el mundo donde quedan: un misil en un techo deja el
montón de cascotes en el suelo y estorba el paso. `World::undestroy` descuenta esos voxels del contador de
destrucción. Los que exceden `maxBodies` se re-voxelizan a los 0,15 s de dormirse.

`effects.gd::explosion` sigue la receta de `data/script/explosion.lua` de Teardown (pequeña/media/grande por radio):
chispas, fuego emisivo que sube, humo, flash + brasa de luz que decae al cuadrado y, en las grandes, la nube
lateral en anillo a 8-12 m/s. Los escombros tienen material propio (antes heredaban el shader de los chunks y su
alfa de fundido caía en el rango que marca los materiales emisivos: brillaban antes de desaparecer).

### Humo que choca con el mundo (como Teardown)

Además de la nube rápida de GPU, `core/src/vx_smoke.cpp` (`SmokeSystem`) simula partículas de humo que **leen la
rejilla de voxels al moverse**: no atraviesan paredes ni techos, bajo un techo se aplanan y se extienden hacia
los lados (salen por los huecos), en un espacio cerrado duran 12-20 s y se disuelven despacio; al aire libre
(sonda de techo cada 0,5 s hasta 30 m) envejecen al doble y el viento las arrastra. Se dibujan como un multimesh
de quads billboard (`VoxelWorld::updateSmoke`, material desde `effects.gd::_setup_world_smoke`, color en
lineal). Las partículas que nacerían dentro de un voxel se desplazan hacia el aire y, si un bloque las cubre,
suben libres hasta salir. Coste ~40 ns/partícula/frame. Lecciones: el buffer de eventos (48/frame) se llenaba
con los "carve"/"dust" de las piezas que desprende la propia explosión y el evento "blast" se perdía (ahora nunca
se descarta); el color de instancia se interpreta en lineal (un gris 0,35 salía casi blanco). Depuración:
`--smokelog` (emisiones), `--smoketest` (humo rojo delante de la cámara en el frame 300), `world.get_smoke_debug(n)`.

## Ideas clave

* **Un bloque es un bloque**: de pie, cayendo y en el suelo. Lo que cambia según el aparato es cómo
  se DIBUJA, nunca lo que ES ([docs/09](docs/09_BLOQUES_Y_RED.md)).
* **Híbrido**: mundo estático en voxels (12,5 cm en PC HIGH/ULTRA, 25 cm en móvil; chunks 32³, 1 byte/voxel) + piezas desprendidas como *voxel bodies* con
  colisión por cajas + partículas para lo pequeño + **re-voxelización** de lo que se duerme.
* **Qué se cae**: conectividad jerárquica incremental (etiquetado por chunk en hilos de trabajo, grafo global en
  microsegundos) **+ modelo de carga** por estructura (soporte por material × sección transversal por nivel).
* **Presupuestos duros por tier** (LOW/MEDIUM/HIGH/ULTRA): cuerpos, partículas, subidas a GPU por frame, radio de
  simulación, distancia de render/LOD. Adaptación dinámica por frame time.
* **Nada pesado en GDScript**: la extensión habla con el RenderingServer y PhysicsServer por RIDs (sin nodos por chunk).
* **Se mide todo**: `vxbench` (headless, JSON), perfilador en juego, CSV para A/B.

Ver `docs/01_ARQUITECTURA.md` para la justificación técnica completa. Captura real del prototipo
(Godot 4.7, Vulkan Mobile, Intel UHD, 60 FPS): `docs/captura_prototipo.png`.
