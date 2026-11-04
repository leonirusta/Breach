# 08 · Auditoría y arquitectura del sistema estructural (2026-09-08)

Este documento es el resultado de la Fase 1 (auditoría) y la Fase 3 (propuesta de arquitectura) del rediseño del
sistema de derrumbe. Las medidas son de la máquina de referencia (i3-N305, 8 núcleos E, Intel UHD, 7,7 GB) con
`vxbench --quick --quality HIGH` antes de tocar nada:

```
frame host (principal)  0,476 ms medio · 3,8 ms máx · 10/818 frames > 2 ms
mesh job / chunk        4,17 ms medio · 6,5 ms máx (hilo de trabajo, incluye LOD1, LOD2 y occluder)
etiquetado / chunk      0,20 ms · solve grafo 0,30 ms medio / 2,26 ms máx · extracción 0,2 ms
A* ruta                 3,4 ms medio · 8,0 ms máx
```

## 1. Diagnóstico

### 1.1 Por qué el edificio B se cae cuando el misil da en A (falso derrumbe global)

El "modelo de carga" vive en `ConnectivitySolver::solve`, pases 3 y 4 (`core/src/vx_connectivity.cpp`):

1. Une con Union-Find las componentes conexas de todos los chunks. En mapas importados el suelo de la calle no
   siempre es material ancla, así que **A y B suelen compartir raíz** (están unidos a través de aceras, muros
   medianeros, tuberías...).
2. Define una "zona" = chunks con `damaged` + sus 26 vecinos (un cubo de 24 m a 25 cm). Suma por nivel Y el
   soporte `S(y)` y la masa `M(y)` de **todos los nodos de la raíz que caen dentro de la zona**. La frontera de la
   zona corta muros por la mitad: la masa que queda dentro se cuenta, el soporte que queda fuera no.
3. `damageByY_` (soporte destruido por nivel) es **global**, no por estructura. El daño que sufre A en el nivel y
   cuenta como daño de B en ese mismo nivel (`frac = dmg / (S(y) + dmg)`), y `lostSupport = frac >= 0.30`
   hace "ceder" a B si su sección en la zona es pequeña.
4. `failY_` es **por raíz**: un único nivel de fallo para toda la raíz. En el pase 4 se desprende **todo** lo que
   tenga masa por encima de `failY` dentro de la zona, incluidos los nodos de B. Resultado: B se desmorona
   sin daño.

El mismo mecanismo explica "daño menor y se desprende el edificio entero": la regla es binaria
(`masa_encima > S(y)·220` en el nivel más bajo dañado) y lo que cede es *todo lo que está por encima*, sin
redistribución ni redundancia.

### 1.2 Otros hallazgos de la auditoría (rendimiento)

| Hallazgo | Dónde | Coste | Acción |
|---|---|---|---|
| El solve recorre **todos** los slots de chunk (6.000-10.000 en Dust 2 / Hangar) tomando el spinlock de cada uno, aunque sólo cambien 3 | `ConnectivitySolver::solve` pase 1 | 1-4 ms cada 4 frames en mapas grandes | Copia atómica de `numComp` fuera del lock; saltar chunks vacíos sin bloquear |
| Raycast DDA voxel a voxel; sólo salta chunks con `solidCount == 0`. Un chunk con 1 voxel se recorre en hasta 32 pasos | `World::raycast` | Bots (LOS), `bodySupported` (5 rayos/cuerpo), cuerpos baratos, nav | Jerarquía de ocupación 2/4/8 voxels por chunk + salto de vacío |
| Generación de trozos (`emitClumpsFor`) en el hilo principal dentro de `explode()`, con `keys` como vector ordenado (inserción O(n) por voxel) | `Engine::emitClumpsFor` | Explosión 10-17 ms en el núcleo (README) | Mover la generación completa a un job; bitset en vez de vector |
| Ids de cuerpo (`nextBodyId_`) asignados en el orden de llegada de los hilos: `id % 7` decide el giro inicial | `Engine::pushPiece` / `spawnPiece` | Indeterminismo visual | Id = hash del primer voxel |
| `StructuralAnalyzer` (`vx_structure.cpp`) escrito en la sesión anterior pero **huérfano**: no está en CMake ni lo usa nadie | `core/src/vx_structure.cpp` | — | Integrar, corregir y completar (ver §2) |
| Cada `chunkJob` malla 4 rejillas (completa, LOD1, LOD2, occluder) aunque el chunk sólo haya perdido 3 voxels | `Engine::chunkJob` | 4,2 ms/chunk | Fuera del alcance de esta pasada: mantener (hilo de trabajo, no bloquea) |
| `rebuildBlock` copia vértices a arrays de Godot en el hilo principal | `voxel_world.cpp` | 2-6 ms por bloque, ya acotado a 4 ms/frame | Mantener |

### 1.3 Evaluación de las referencias

**vox3D (Tribulla)**: solver cuasi-estático de tensión de sección con flexión, alivio inercial de d'Alembert,
racha de sobrecarga (`fractureHoldFrames`), análisis cada K frames (`analysisStride`), enclavamiento del apoyo
(`restOnAge`), camino de impacto separado del de tensión, `minFragment`, `maxDebris`, ruido de rugosidad en
la superficie de rotura. **Se adopta**: racha de sobrecarga (deformación acumulada), stride, separación
impacto/estructura, tope de fragmentos, rugosidad. **Se simplifica**: la tensión de sección con momento
flector se reduce a "carga vertical / capacidad" + "carga en viga × brazo / capacidad a flexión" por celda de
0,5 m (O(celdas) en vez de O(planos × voxels)). **Se rechaza**: alivio inercial (nuestros cuerpos desprendidos
los simula Jolt y no vuelven a analizarse; sólo se analiza el mundo estático).

**Voxel-Engine (nowaythisworks)**: motor Three.js con `InstancedMesh` por chunk de 64 unidades, rayos en dos
fases (caja del chunk, luego voxels), sin estabilidad estructural. **Se adopta** el concepto "caja del chunk
primero" (ya existía parcialmente) y se lleva más lejos con ocupación jerárquica. Nada más aplicable.

**Teardown (acko.net)**: volúmenes 3D de 1 byte/voxel con 2 niveles MIP (2³ y 4³) para saltar vacío, mapa de
sombras volumétrico de 1 bit/voxel (8 voxels por byte), rayos aproximados sparse / super-sparse, reuso temporal
en 4 pases. **Se adopta**: jerarquía de ocupación por bits (1 bit por 2³, 4³ y 8³) para los rayos de CPU y para
consultas de explosión/estructura. **Se rechaza** el ray tracing de voxels en GPU como renderizador principal:
el juego apunta a Intel UHD y móviles; ahí un rasterizador con mallas greedy fusionadas por bloque (lo que ya
hay) rinde más que un trazador por píxel, y Godot no permite escribir `gl_FragDepth` con early-Z por lotes como
hace Teardown. El reuso temporal ya lo aplica Godot (TAA, SSAO/SSIL temporal) y no compensa duplicarlo.

## 2. Arquitectura propuesta

```
EXPLOSIÓN  Engine::explode
   ↓ carveSphere (daño por voxel, determinista)          ── sistema de IMPACTO
   ↓ DirtyRegion (bounds del cráter + margen estructural)
   ↓ StructuralAnalyzer::applyDamage (hilo de trabajo)     ── sistema ESTRUCTURAL
        celdas 0,5 m  →  LÍNEA BASE (voxels destruidos repuestos)  →  islas por contacto real
        →  rutas de apoyo (pilar portante / viga con momento / colgante)
        →  reparto de cargas de arriba abajo (cono de 45° en pilares)  →  ratio carga/capacidad
        →  deformación acumulada sólo por encima de máx(1,08, base x 1,1)
        →  fallos justificados (top-K por ratio + sin ruta)   [una iteración cada 6 frames; duerme tras 12 sin fallos]
   ↓ FailCells → extractCells (job): las celdas que fallan salen como fragmentos con dirección de vuelco
   ↓ chunks sucios → ConnectivitySolver (sólo conectividad pura) → lo que perdió el suelo se desprende
   ↓ el analizador re-escanea sólo las celdas de chunks cuya versión cambió → siguiente iteración
   ↓ estable (sin fallos) o tope de iteraciones → la región duerme (se libera)
```

Reglas que corrigen el diagnóstico:

* **Independencia**: sólo se evalúan las islas que contienen voxels dañados; una isla es un conjunto de celdas
  unidas por **contacto real de voxels** (pares sólido-sólido a través de la cara), no por distancia ni por
  compartir chunk. Dos edificios a 1 m nunca comparten carga.
* **Frontera = apoyo intacto**: las celdas sólidas en el borde XZ de la región cuentan como apoyadas (lo de
  fuera no se ha tocado). Así la frontera nunca "corta" un muro dejando masa sin soporte.
* **Redundancia continua**: cada celda tiene `ratio = carga / capacidad`; por debajo de 1,08 nada falla; por
  encima acumula deformación por iteración y sólo falla al superar `strainToFail`. Quitar 1 de 10 pilares sube el
  ratio de los otros un 11 %: nada cae.
* **Fallo local y progresivo**: por iteración fallan como mucho las K celdas peores (más las que no tienen ruta).
  Lo que queda por encima sólo cae si pierde la conexión (conectividad) o si sus apoyos restantes se sobrecargan
  en la siguiente iteración.
* **Línea base**: lo que el autor del mapa construyó se considera estable por definición (un tejado de 15 m sin
  pilares tiene ratio nominal > 1 y no debe caerse solo). Al abrir el análisis se calculan los ratios con los
  voxels destruidos "repuestos" y cada celda sólo falla si el daño sube su ratio por encima de esa base (+10 %).
* **Voladizo por momento**: cada celda de viga acumula Σ(carga × brazo); un tejado que pierde un muro y queda en
  voladizo desde el otro multiplica su momento y cede progresivamente desde la raíz. Corrige el "tejado colgando
  del muro trasero" que documenta el README sin cortar a una distancia fija.
* **Elementos no portantes**: pladur, cristal y escombro (compresión < 0,2) se sostienen a sí mismos pero no son
  pilar de la losa que tienen encima; la línea base de una losa sobre tabiques la apoya en los muros.

Coste previsto: región de 32 m³ a 0,5 m = 64×96×64 celdas máximo; escaneo desde la memoria del chunk
(sin `getVoxel` por voxel) ≈ 2-6 ms por iteración inicial en el hilo de trabajo, re-escaneos parciales <1 ms.
Memoria: 60 B por celda ≈ 24 MB en el peor caso, liberada al dormir. Sincronización: el analizador sólo lee
voxels (1 byte, sin lock) y sólo itera cuando no hay extracciones en vuelo (determinismo).

## 3. Jerarquía de ocupación para rayos

Por chunk: `occ2` (16³ bits = 512 B, celdas 2³), `occ4` (8³ bits = 64 B), `occ8` (4³ = 8 B). Total 584 B por
chunk (1,8 % del chunk). Se reconstruye bajo el lock al final de cada edición que quita voxels (5-10 µs). El
raycast comprueba, de grueso a fino, si la celda que contiene el voxel actual está vacía y salta hasta su plano de
salida. Sirve también a `box_solid`, `bodySupported` y a la búsqueda de islas del analizador.

## 4. Resultados (medidos el 2026-09-08, i3-N305)

### 4.1 Corrección (`vxstructtest`, 33 comprobaciones, 0 fallos; `vxtest`, 432 comprobaciones)

| Escenario | Resultado |
|---|---|
| Forjado sobre 9 pilares, se destruye 1 / 2 | queda el 100 % (redundancia: nada cae) |
| Se destruyen 7 de 9 | cae la mayor parte; los dos pilares y su capitel quedan (punzonamiento) |
| Losa sobre un pilar, se destruye | cae toda |
| Boquete pequeño en muro / agujero en tejado / esquina | 94-97 % en pie; la esquina opuesta intacta |
| 1 cohete en la base (muros de ladrillo) | queda el 94 % (boquete) |
| 5 cohetes en los lados | derrumbe **parcial**: queda el 69 % (las esquinas sostienen) |
| Cinturón de 14 cargas + carga central (F6) | al suelo (0 %) por conectividad, 1 iteración |
| Dos edificios a 1 m, 5 cohetes en A | A 89 %, **B 99,3 % y su tejado entero** (antes: B se desmoronaba) |
| Edificios separados 6 m | B intacto al 100 % |
| Edificios unidos por pasarela | B 100 %; la pasarela sigue anclada a B |
| Voladizo de 2 m / viga de 12 m | el corto aguanta; el largo se parte |
| Edificio de 470 k voxels, explosión de 2 m | 2 celdas fallan, 99,98 % en pie, 5,4 ms por iteración |
| Determinismo | mismo hash del mundo en dos ejecuciones; `vxbench --verify` OK |
| Raycast jerárquico vs voxel a voxel | 10.000 rayos, 0 discrepancias |

### 4.2 Rendimiento

`vxbenchstruct` (5 cohetes en la planta baja de un edificio de muros; iteración = escaneo perezoso + islas +
rutas + reparto + fallos, en un hilo de trabajo):

| voxels | ms/iteración media / máx | iteraciones | celdas fallidas | fragmentos | solve conectividad media / máx |
|---|---|---|---|---|---|
| 11 k | 5,1 / 17,9 | 17 | 637 | 137 | 0,013 / 0,15 ms |
| 79 k | 9,0 / 24,7 | 18 | 920 | 183 | 0,026 / 0,09 ms |
| 660 k | 14,6 / 39,9 | 27 | 4.867 | 511 | 0,14 / 0,58 ms |
| 2,0 M | 31,6 / 49,2 | 9 | 1.681 | 209 | 0,34 / 0,80 ms |

Rayos (50.000 rayos de 120 m sobre la ciudad procedural): jerárquico 1,10 µs/rayo, voxel a voxel 5,14 µs/rayo
(x4,7); 1,7 pasos de voxel y 10,9 saltos de región vacía por rayo.

`vxbench --quick --quality HIGH` (guion de disparos/granadas/cohetes, antes -> después):

| métrica | antes | después |
|---|---|---|
| carve/explosión (hilo principal) media / máx | 0,183 / 0,707 ms | 0,098 / 0,308 ms |
| solve grafo media / máx | 0,295 / 2,26 ms | 0,136 / 0,28 ms |
| frame host media / máx | 0,476 / 3,80 ms | 0,396 / 2,15 ms |
| mesh job por chunk | 4,17 ms | 4,52 ms (sin cambios; ruido) |

### 4.3 Qué queda fuera (honesto)

* El renderizador sigue siendo el rasterizador de Godot con mallas greedy: la jerarquía de ocupación acelera los
  rayos de CPU (disparos, visión de bots, sondas de apoyo), no la imagen. Un trazador de voxels por píxel no es
  adecuado para Intel UHD/móvil (ver §1.3).
* El remallado por chunk (4,5 ms, 4 rejillas) no se ha tocado: va en hilos de trabajo y no limita el frame.
* No hay SIMD explícito: los bucles calientes medidos (escaneo de celdas, DDA, etiquetado) ya están por debajo
  del milisegundo por operación; vectorizar no cambiaría el frame. El compilador vectoriza `ChunkOccupancy::rebuild`.
* La calibración (capacidad 660, momento 1,0, arco 0,5, racha 0,6/0,5) es de juego: se afina en vivo con
  `VoxelWorld.set_struct_param` y F11 sin recompilar.
