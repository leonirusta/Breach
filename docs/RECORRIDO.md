# Breach — recorrido del código

Qué hace cada archivo y dónde está cada cosa. Escrito para que alguien que no ha visto nunca este
repositorio pueda orientarse sin ir abriendo archivos al azar.

La orientación rápida (compilar, ejecutar, las reglas que no se pueden romper) está en
[CLAUDE.md](../CLAUDE.md). Aquí está el detalle.

> **AVISO (2026-09-14).** Todo lo que este documento dice sobre re-voxelizar trozos, sobre
> `place_detached` y sobre el trato distinto al invitado de LAN **está obsoleto**: lo que se
> desprende es un bloque y ya no vuelve a la rejilla nunca. `revoxelizeBody`, `bodySupported` y
> `baseCuadrada` ya no existen. Lo vigente está en
> **[09_BLOQUES_Y_RED.md](09_BLOQUES_Y_RED.md)**.

---

## Índice

1. [El motor: `core/`](#1-el-motor-core)
2. [El puente: `godot/extension/`](#2-el-puente-godotextension)
3. [El juego: `godot/scripts/`](#3-el-juego-godotscripts)
4. [Escenas, shaders y recursos](#4-escenas-shaders-y-recursos)
5. [Herramientas: `tools/`](#5-herramientas-tools)
6. [Formato de los mapas](#6-formato-de-los-mapas)
7. [Cadena de producción de contenido](#7-cadena-de-producción-de-contenido)
7 bis. [Primera persona, cámara y espectador](#7-bis-primera-persona-cámara-y-espectador)
8. [Flags de línea de comandos](#8-flags-de-línea-de-comandos)
9. [Decisiones raras con su motivo](#9-decisiones-raras-con-su-motivo)

---

## 1. El motor: `core/`

C++17, cero dependencias salvo `Threads`. No sabe que existe Godot.

### Cabeceras — `core/include/vx/`

| Archivo | Qué hace |
|---|---|
| `vx_math.h` | `Vec3`/`IVec3`/`Transform` (matriz 3x4), `ifloor`, RNG splitmix64 determinista, `hash3`, `Timer`. |
| `vx_config.h` | Constantes del mundo (chunk 32³, voxel por defecto 0,25 m, `STRESS_CAPACITY=660`) y los 4 `QualityPreset` con todos los presupuestos. |
| `vx_chunk.h` | `Chunk` (32³ bytes + versión + espejos atómicos + spinlock), `ChunkConn` (caché de conectividad), `ChunkOccupancy` (bitmaps 2³/4³/8³). |
| `vx_world.h` | API de `World`: rejilla densa de punteros atómicos, get/set, `fillBox`, `carveSphere`/`carveBullet`, raycast jerárquico, `boxSolid`, `snapshotPadded`. Define `CarveResult` y `RayHit`. |
| `vx_material.h` | Los 16 materiales integrados (ids 0–15), flags (`MF_ANCHOR`, `MF_GLASS`…), `MaterialClass`, `MaterialPhysics`, tabla global `g_materials[256]`. Los ids 16–255 los define cada mapa. |
| `vx_jobs.h` | `JobSystem`: pool de hilos con cola re-priorizable por distancia al jugador. |
| `vx_mesher.h` | `MeshVertex` (16 B), `MeshData` (índices opaco/cristal separados), `PaddedGrid`, clase `Mesher` (greedy + AO + tres downsample 2x). |
| `vx_connectivity.h` | `labelChunk`, `computeFaceEdges`, `ConnectivitySolver` (Union-Find global → `DetachedGroup`s sin ancla). |
| `vx_structure.h` | `StructParams` (~25 parámetros calibrados), `StructCell`, `FailCell`/`FailGroup`, `StructResult`, `StructDebug`, y `StructuralAnalyzer` con sus 11 etapas. |
| `vx_body.h` | `VoxelBody` (mini-rejilla + COM + masa + cajas + malla) y `BodyBuilder`. |
| `vx_debris.h` | `DebrisSystem`: pool fijo de partículas de escombro que colisionan con la rejilla. |
| `vx_smoke.h` | `SmokeSystem`: pool fijo de humo con sonda de techo y viento. |
| `vx_nav.h` | `Navigator`: A* sobre celdas de 2 voxels con caché de bits + `lineOfSight`. |
| `vx_mapfile.h` | Formato `.vxmap` y sus funciones de carga. |
| `vx_citygen.h` | `generateCity`: ciudad procedural determinista. |
| `vx_stats.h` | `TimeStat` y el struct `Stats` con ~40 contadores. |
| `vx_engine.h` | `EngineConfig`, `ChunkMeshResult` y la clase `Engine`: **la única fachada que ve el puente**. |

### Implementaciones — `core/src/`

| Archivo | Qué hace |
|---|---|
| `vx_world.cpp` | Chunks creados a demanda bajo mutex, `carveSphere` en aritmética entera con ruido de borde, `carveBullet` (radio según potencia/dureza, cristal filtrado por `MF_GLASS`), DDA jerárquico, `snapshotPadded` 34³, `hashVoxels`. |
| `vx_mesher.cpp` | Greedy mesher por rebanadas: máscara `mat \| ao<<8 \| visible<<16`, fusión de rectángulos, diagonal elegida por AO, separación opaco/cristal, y los dos downsample (normal y conservador para occluders). |
| `vx_connectivity.cpp` | `labelChunk` (BFS iterativo; las anclas no se etiquetan, anclan), `computeFaceEdges`, y `solve` en 4 pases con la regla *pristine* por conjunto. |
| `vx_structure.cpp` | El analizador entero: `setupRegion` (presupuesto de 400 k celdas), `computeBaseline` + calibración por percentil 98, `findIslands`, `computeSupport`, `distributeLoads` (cono de descarga), `computeRatios` (pandeo), `computeOverturn` (vuelco), `detectOverload` (deformación acumulada), `collectFailures`. |
| `vx_body.cpp` | `decompose` (greedy en cajas; descarta las sobrantes en vez de fundirlas) y `build` (COM ponderado, masa en kg, todo relativo al COM). |
| `vx_debris.cpp` | Gravedad −14 m/s², colisión eje a eje con una lectura de voxel, pool circular. |
| `vx_smoke.cpp` | Empuje térmico decreciente, rozamiento exponencial, turbulencia determinista, sonda de techo cada 0,5 s. |
| `vx_nav.cpp` | Construcción de `NavChunk.walk` con operaciones de bits, A* con heurística ×1,15, 8 direcciones sin cortar esquinas, suavizado por línea de visión. |
| `vx_jobs.cpp` | Bucle de trabajador con `condition_variable`; `waitIdle` para tests y benchmark. |
| `vx_material.cpp` | Tabla por clase, `classifyMaterial` (heurística por `support`/`density`), `deriveMaterialPhysics`, `resetMaterials`. |
| `vx_mapfile.cpp` | Lector little-endian: cabecera, paleta → `setMaterial(16+i)`, spawns, RLE por chunk. |
| `vx_citygen.cpp` | Ciudad procedural: calles, manzanas, torres con losas, ventanas, tabiques, escaleras, tiendas, parques, coches, farolas, paso elevado. Trabaja en metros. |
| `vx_engine.cpp` | La orquestación: `shoot`/`explode`/`carveBeam`/`revoxelize`, acumulación de daño de bala, `update()` por frame, y los jobs (`chunkJob`, `extractJob`, `extractCellsJob`, `clumpsJob`, `structJob`). |

### Tipos y funciones que hay que conocer

**Mundo** — `World::getVoxel/setVoxel(x,y,z,m,damage)` (el flag `damage` distingue daño de juego de
re-voxelización), `fillBox`, `carveSphere(centro, radio, potencia, res, falloff, soloFlags)`,
`carveBullet`, `raycast` (jerárquico; `raycastBrute` es la referencia de los tests), `boxSolid`,
`markDirty`/`takeDirty`.

**Motor** — `Engine::shoot/explode/carveBeam/revoxelize`, `update(dt, playerPos)` (hilo principal,
una vez por frame), `readyMeshes()` y `readyPieces()` (**válidos solo hasta el próximo `update`**),
`waitIdle` para tests, y los reguladores (`setClumpScale`, `setDebrisScale`, `setDesprender`,
`setLoadModel`, `setStructuralSleep`).

**Analizador** — `applyDamage(world, StructDamage)` abre o amplía la región; `iterate(world, res)`
hace una iteración. Ambas **en hilo de trabajo**. Etapas en orden: `scanRegion` → `computeBaseline`
→ `buildSolidLists` → `findIslands` → `markTouched` → `computeSupport` → `distributeLoads` →
`computeRatios` → `computeOverturn` → `detectOverload` → `collectFailures`.

**Cuerpos** — `BodyBuilder::build(voxels, voxelSize, maxBoxes, id, out)`. Ojo: `build()` **reinicia**
el `VoxelBody`, así que las velocidades iniciales se asignan **después**.

**Navegación** — `Navigator::findPath(from, to, out, maxExpansions, stats)` devuelve `true` solo si
llegó, pero deja igualmente la mejor ruta parcial en `out`.

### Lo que NO se puede hacer

- Llamar a `setMaterial`/`resetMaterials` con hilos activos (la tabla se lee sin sincronización).
- Usar `fillBox` mientras haya jobs en vuelo.
- Compartir un `Mesher`, `BodyBuilder` o `LabelScratch` entre hilos.
- Guardar punteros a `readyMeshes()`/`readyPieces()` más allá del frame.
- Editar voxels sin `bumpVersion` (malla, ocupación y conectividad se quedan desincronizadas).
- Compilar con fast-math.

### Variables de entorno

`VX_THREADS` (número de hilos), `VX_CALIB` (objetivo de calibración; 0 la apaga),
`VX_LOGSTRUCT` (1 = resumen por iteración, 2 = peores celdas + tiempos), `VX_LOGGROUPS`.

### Tests y benchmarks

| Binario | Para qué |
|---|---|
| `core/build/vxtest.exe` | ~213 comprobaciones: mundo, determinismo de tallado, raycast, mesher, cajas, conectividad, modelo de carga, nav, escombros, y un end-to-end con ciudad + demolición. |
| `core/build/vxstructtest.exe [filtro]` | ~45 escenarios estructurales: redundancia de pilares, la "mesa" de 124 t del mapa de pruebas (1/2/3 patas, un voxel, a tiros), boquetes, voladizo, determinismo por hash. |
| `core/build/vxbench.exe` | Benchmark headless. `--quality --seed --size --threads --json --verify --quick`. |
| `core/build/vxbenchstruct.exe` | Analizador y rayos por tamaño de mundo. `--sizes 10k,100k,1m,4m --rays N`. |

---

## 2. El puente: `godot/extension/`

| Archivo | Qué hace |
|---|---|
| `src/voxel_world.h` | Declara `VoxelWorld` (Node3D) y sus estructuras internas (`ChunkVis`, `BlockVis`, `RegionVis`, `Body`, `Anchor`). Cabecera muy comentada: explica la arquitectura entera. |
| `src/voxel_world.cpp` | 2.600 líneas: marshalling GDScript↔`vx::Engine`, render sin nodos directo al `RenderingServer`, cuerpos en `PhysicsServer3D` por RID, LOD, occluders, ocupación en GPU, escombros y sincronización LAN. |
| `src/register_types.cpp` | Registra `VoxelWorld` en el nivel `SCENE`. Nada más. |
| `CMakeLists.txt` | Proyecto `breach_voxel`: C++17, añade godot-cpp y `../../core`, y nombra la salida como espera `breach_voxel.gdextension`. |

### La API que ve GDScript

**Cargar mapa** — `generate_city(seed)`, `load_map(bytes) -> bool`, `is_loading()`,
`get_loading_progress()`, `find_ground(pos)`, `get_spawn_points()`, `get_spawn_position()`.
Señal `world_ready()`.

**Destrucción** — `explode(pos, radio, potencia)`, `carve_beam(origen, dir, largo, radio, potencia,
vaporize)`, `carve_body(rid, pos, radio, potencia)`, `carve_body_near(pos, radio, potencia)`,
`shoot(origen, dir, alcance, potencia) -> Dictionary`, `emit_smoke(...)`, `get_effect_events()`.

**Consultas** — `raycast(origen, dir, alcance)`, `raycast_con_piezas(...)` (también contra lo que
cae; lo usan los bots), `has_line_of_sight(a, b)`, `find_path(de, a)`, `get_material_at(pos)`,
`box_solid(min, max)`, `contar_voxels(min, max)`, `get_world_size()`, `get_material_color(mat)`,
`get_material_name(mat)`, `get_material_info(mat)`.

> **`get_material_info` NO devuelve color.** Devuelve nombre, dureza, densidad, flags y clase. El
> color está en `get_material_color`. Pedirle el color a `info` daba siempre el gris de relleno.

**Cuerpos y escombros** — `set_player_position(pos)` (cada frame), `set_personajes(posiciones)`
(jugador + bots + remotos: todo lo que caiga a menos de 12 m de uno lleva colisión sí o sí),
`set_physics_anchors(puntos, radio)`, `set_piece_gravity(escala)`, `set_debris_scale`,
`set_clump_scale`, `set_cheap_solid_max`, `get_body_count()`, `get_bodies_debug()`,
`set_structural_load(on)`, `set_structural_sleep(s)`, `set_struct_param(nombre, valor)`.
Señal `piece_detached(pos, voxels, material)`.

**Render y LOD** — `set_render_distance_scale(s)` (hasta dónde se dibuja),
`set_lod_distance_scale(s)` (hasta dónde con malla fina), `set_view_distance_scale(s)` (las dos a la
vez), `set_use_occluders`, `set_occlusion_volume`, `bind_occupancy_to_material`.

> Son **dos mandos separados a propósito**: en Mónaco (13.074 chunks, 7,6 M de triángulos) interesa
> ver lejos con poco detalle.

**Red** — `set_red(en_red, soy_host)`, `set_settle_authority(manda)`,
`place_detached(origen, tam, mascara, vel, ang)`, `place_settled(origen, tam, mats)`.
Señales `pieza_suelta(...)` y `piece_settled(...)`.

**Estadísticas** — `get_stats()` (muy amplio: triángulos, cuerpos, colas, tiempos por fase,
contadores `sync_*` de red) y `resumen_chunks()` (la huella del mapa, para comparar dos máquinas).

### Cómo funciona por dentro

**Tres niveles sobre los mismos datos.** vxcore entrega cuatro mallas por chunk (completa, LOD1,
LOD2, occluder). `uploadChunk` **no crea ninguna instancia**: las guarda en CPU y marca sucios su
bloque y su región. Todo lo demás se genera por fusión, sin volver a mallar.
- **Bloque** = 2×2×2 chunks, un draw call, es lo que se ve de cerca.
- **Región** = 4×4×4 chunks, con sus mallas LOD1/LOD2, su occluder y su caster de sombras.

Al salir del estado cercano la instancia del bloque **se destruye**, no se oculta: el culling de
Godot recorre todas las instancias del escenario, así que las lejanas no deben existir.

**Física por anclas.** Solo tienen cuerpo estático los chunks cerca de un ancla: jugador (24 m),
anclas externas y cuerpos rígidos (6 m, máximo 24 anclas de cuerpo). Con una por cuerpo, un derrumbe
de 185 piezas disparaba la fase a 9 ms.

**Nacimiento de una pieza** (`spawnPiece`), en orden de preferencia:
1. *Atajo instantáneo* si no hay nadie a menos de 12 m y está lejos: rayo hacia abajo y
   re-voxelización directa. **Los trozos de derrumbe nunca toman este atajo**: 400 piezas
   teletransportadas reconstruían el edificio como una pila con forma de fachada.
2. *Rígido* con Jolt (hasta `maxBodies`), una caja por `vx::Box`, con `body_set_state_sync_callback`.
3. *Barato sólido*: cinemático con hasta 4 cajas. Sin él el trozo era puro dibujo y lo atravesabas.
4. *Barato fantasma*: solo malla, para esquirlas.

**Caída y asentamiento** (`stepBodies`) corre a **paso fijo de 1/60 s** (antes usaba el delta del
frame y la misma caída se congelaba en sitios distintos a 144 fps que a 25). Un cuerpo parado 0,4 s
con más de 20 voxels se **ancla** (pasa a estático): un personaje es cinemático, o sea de masa
infinita, y caminando movía losas de dos toneladas.

**Re-voxelización** — se congela **con el ángulo que tenga**. `Engine::revoxelize` muestrea al revés
(recorre el destino y pregunta qué había en el trozo), así que una viga que se paró inclinada se
queda inclinada. Lo que se cuadra con la rejilla es la **esquina** del trozo, no el centro de masas.

> El precio de esto: los bordes quedan en escalera. La rejilla no está girada, así que una pieza a
> 30° siempre va a tener el borde dentado. Es inherente, no un bug.

**Tallado diferido** — quitar voxels es barato, rehacer malla + cajas + formas de Jolt no. Con un
fusil sobre un cascote salían 10 reconstrucciones por segundo. Ahora se marca `b.reconstruir` y se
rehacen 2 cuerpos por frame.

### Lo que hay que reaplicar al cargar un mapa

`load_map`/`generate_city` **destruyen y recrean el `Engine`**. Dentro se reaplican solos
`setDebrisScale`, `setStructuralSleep`, `setLoadModel` y `setDesprender`. **Hay que volver a llamar
desde GDScript**: los materiales personalizados, `bind_occupancy_to_material`,
`set_physics_anchors`, `set_personajes`, `set_cheap_solid_max`, `set_piece_gravity` y los
`set_struct_param`. Además `load_map` **sobrescribe `voxel_size` y `chunks`** con los del archivo.

---

## 3. El juego: `godot/scripts/`

Los `*.backup.gd` están ignorados.

### Autoloads (`project.godot`)

`Prof` (perfilador por fases), `Settings` (ajustes persistentes), `Audio` (biblioteca de sonidos,
pool de 32 voces 3D con prioridad y reverb dinámica), `Net` (LAN). **`Net` sobrevive al cambio de
escena**, lo que es fuente de bugs: `_cargar_dm()` tiene que resetear `Net.equipos` a dos, o volver
de la ciudad a `hangar` deja tres equipos en un mapa de dos.

### Jugabilidad

| Archivo | Líneas | Qué hace |
|---|---|---|
| `main.gd` | 8.331 | Nodo raíz de la partida: carga el mapa, decide el modo, siembra bots/sitios/bases, monta cielo-noche-lluvia-nieve-huellas-faroles, bombea los eventos de efectos del motor, lleva los marcadores, y alberga ~120 rutinas de prueba. |
| `player.gd` | 3.035 | Controlador FPS: movimiento, ADS, retroceso, hitscan, granadas/cohetes, mazo, C4, trepar, derribado, devorado, ragdoll, espectar, reaparecer, tercera persona, bodycam. |
| `enemy.gd` | 1.665 | Bot con IA de defensor (`GUARD/PATROL/INVESTIGATE/COMBAT/SEARCH`), percepción por cono + línea de visión por voxels, navegación A* de vxcore. |
| `combat.gd` | 26 | Una sola función estática `damage_around()`: daño en área con caída lineal, con autor y bandera `tumbar`. |
| `weapons.gd` | 203 | Estadísticas, precio y `power` de cada arma. El catálogo de modelos sale de `armas/armas.json`. Sin accesorios: la mira va soldada. |
| `weapon_model.gd` | 602 | Carga `armas/<id>.glb` y expone `sight_pos`, `muzzle_pos`, `grip_pos`, `foregrip_pos`. Mazo, C4 y láser son de código. |
| `weapon_icon.gd` | 112 | `SubViewport` que renderiza UN frame del arma real como icono 2D. Coste cero por frame. |
| `avatar_animator.gd` | 2.668 | El avatar voxel: rig por huesos, IK, poses, recarga, mazazo, trepar. Geometría compartida en estáticos entre el jugador y todos los bots. |
| `net.gd` | 1.615 | LAN: descubrimiento UDP, transporte ENet, salas, equipos, replicación, y el servidor autoritativo con rebobinado. |
| `net_player.gd` | 331 | Avatar de un jugador remoto. No simula: interpola paquetes a 20 Hz. |
| `heist.gd` | 525 | Modo atraco: caja fuerte con ganzúa, cubo dorado, terminal de ingreso. |
| `pve.gd` | 1.246 | Modo oleadas: tabla `TIPOS` y `OLEADAS`, 10 oleadas con jefe en la décima, oro compartido, tienda. |
| `criatura.gd` | 1.124 | La criatura PvE: persigue por A*, pega, escupe ácido, aúlla invocando; el Goliat arranca un trozo de suelo y lo lanza. |
| `bomb.gd` | 134 | La C4: `DROPPED/PLANTED/DONE`, mecha de 40 s con pitidos acelerando. |
| `grenade.gd` | 23 | `RigidBody3D` con mecha. Se une al grupo `phys_anchor` para forzar colisión del mundo a su alrededor. |
| `rocket.gd` | 66 | Cohete recto con estela sembrada **por distancia recorrida**, no por frame. |
| `ragdoll.gd` | 325 | Doce cuerpos con juntas, creados SUELTOS a escala 1:1 (no colgando del avatar, que va a ~0,021). |
| `effects.gd` | 1.310 | Pools fijos de partículas en round-robin, textura de humo generada por código, explosiones con receta tipo Teardown. |
| `escuadra.gd` | 84 | Tablón compartido de alertas para los bots. Las alertas **caducan**, y eso evita el comportamiento de rebaño. |
| `bloque_volador.gd`, `proyectil_acido.gd`, `cargador_caido.gd`, `botiquin_suelto.gd`, `tienda_pve.gd` | | Objetos sueltos del PvE y del Goliat. |

### Interfaz y sistemas

| Archivo | Qué hace |
|---|---|
| `settings.gd` | Autoload: ajustes en `user://settings.cfg`, `GFX_OPTIONS`/`GFX_PRESETS`, `detect_quality`, lista de mapas, monedero, loadout. |
| `lobby.gd` | 4.739 líneas. Lobby 3D: avatar en podio, cajón con 6 pestañas, tienda, armería, armario, salas LAN, visor 3D de armas, retratos por SubViewport. |
| `hud.gd` | 2.969 líneas. HUD entero por código **y todas las capas de post-proceso**: bodycam, lente, viñeta, sangre, lluvia, motion blur, onda expansiva, REC. |
| `graphics_menu.gd` | Menú gráfico: presets + 6 secciones `GROUPS`, `LABELS` descriptivos, barra de carga estimada con la tabla `COST`. |
| `minimap.gd` | No re-renderiza el mundo: sondea la rejilla con rayos verticales (6 filas por frame) a una `ImageTexture`. |
| `mobile_controls.gd` | Joystick + botones táctiles. El layout es **datos**, en coordenadas relativas sobre el área segura. |
| `touch_editor.gd`, `mira_editor.gd`, `calibrar_anim.gd` | Editores en juego: controles táctiles, puntería/poses, calibración de marcha. Los dos últimos copian la configuración al portapapeles para pegarla a mano. |
| `audio.gd` | Pool de 32 voces 3D con prioridad, atenuación + paso-bajo + retardo por velocidad del sonido, reverb según lo cerrado del sitio. |
| `prof.gd` | Perfilador mínimo por fases. |
| `vox_mesh.gd`, `promo.gd`, `frame_probe.gd`, `struct_debug.gd` | Mallas de voxels para la UI, captura de tráiler, sonda de frames, depuración estructural. |

### Índice de `main.gd` (8.331 líneas)

| Líneas | Sección |
|---|---|
| 37–355 | Adaptación de la vista, grado de color, noche, lluvia, nieve, polvo en el aire |
| **356–395** | **`_ready()`** |
| 396–572 | `_load_world`, cielo, luna |
| **681–940** | **`_on_world_ready()`** — el gran dispatcher de flags y el arranque del modo |
| 1469–1715 | Sitios de bomba y faroles del mapa |
| 1748–1990 | Carga de DM, siembra de bots |
| 2273–2670 | AO, viento, mapa de techos, nieve, huellas |
| **2672–3092** | **`_process(delta)`** |
| 3093–3312 | Diagnósticos LAN |
| 3313–3680 | Reaparición por equipos, `_start_free_mode`, `_start_heist` |
| 3681–3921 | Elección de bando |
| 4954–5230 | Reparto de roles de bots |
| 5505–5810 | Entrada (F3–F12), calidad, `apply_graphics` |
| **7188–7850** | **Duelo a muerte** |
| **7851–8331** | **Atraco a tres equipos** y las pruebas LAN |

`main.gd` **no tiene `_physics_process`**.

Orden de `_ready()`: calidad → sol → conecta `world_ready` → **fija la autoridad de red en el mundo**
(`set_settle_authority`, `set_red`, y engancha `pieza_suelta`/`piece_settled` a los RPC) → crea
`Effects` → `player.setup()` con el jugador **desactivado** → `hud.setup` → `apply_quality` →
`_load_world()`.

Orden de `_process()`: faroles → mojado → nieve → huellas → techos → viento → **guarda de carga** →
polvo → vista → `set_player_position` → **`Net.tick_servidor(delta)`** → anclas → `set_personajes`
→ estadísticas cada 4 frames → drenaje de `get_effect_events()` con topes → objetivo cada 6 frames →
calidad adaptativa → diagnósticos por número de frame.

### Índice de `player.gd` (3.035 líneas)

| Líneas | Sección |
|---|---|
| 1–146 | Constantes (velocidades, salto, altura de ojos), noclip |
| 147–420 | Sensación de cámara, `_ready`, equipar arma y avatar |
| 415–615 | Enfoque, vaho, sacudidas, cámara en tercera persona |
| 616–752 | Láser continuo |
| 753–890 | Entrada, `rotate_look`, **cámara de cuerpo**, API táctil |
| 892–952 | **Subida de escalones** (`_step_up`) |
| **953–1314** | **`_physics_process` → `_physics_inner`** |
| 1315–1499 | Cuerpo a cuerpo: el mazo y su dureza por material |
| **1500–1677** | **`fire()`** |
| 1678–1932 | Humo, casquillos, pisadas, retroceso, recarga, granada |
| **1933–2153** | **Bomba**: plantar, desactivar, detonar, recoger |
| 2194–2322 | Trepar |
| 2333–2500 | Derribado y devorado |
| 2506–2700 | Lente: suciedad y la mano que la limpia |
| 2808–3035 | Muerte, reaparición, espectar |

`_physics_inner` tiene **salidas tempranas** en este orden: devorado → espectando → noclip →
derribado → trepando. Ojo con esto: cualquier cosa que viva al final de la función (por ejemplo el
limpiado de la lente) **no corre** durante esas escenas, y se queda congelada a medias.

### Los modos de juego

| Modo | Se activa por | Arranque | Archivos |
|---|---|---|---|
| **Bomba** | existe `maps/<mapa>.sites.json` | `show_team_select()` → `_close_team_select` (que es quien saca los bots) | `main.gd` + `bomb.gd` + `net.gd` + `player.gd` |
| **Duelo a muerte** | existe `maps/<mapa>.dm.json` | igual; los bots van al punto medio entre bases | `main.gd` §7188–7850 |
| **Atraco a tres equipos** | mapa en `MAPAS_ATRACO` | `_ciudad_tres_equipos()`: caja, tres bases en círculo, 6 bots por equipo; gana el primero en llegar a 3000 puntos | `main.gd` §7851+ + `heist.gd` |
| **PvE** | mapa en `MAPAS_PVE`, o `--pve` | `show_team_select()` → `_empezar_pve()` | `pve.gd`, `criatura.gd`, `tienda_pve.gd` |
| **Libre** | nada de lo anterior | `_start_free_mode()` | `main.gd` |

### La red (`net.gd`)

Dos canales separados a propósito: **descubrimiento** (UDP 27016, faro JSON cada 1 s + sondas
dirigidas en 27017, porque un broadcast puede filtrarse y un paquete dirigido casi siempre pasa) y
**partida** (ENet 27015, hasta 10 jugadores). El faro se manda a `255.255.255.255` **y** al broadcast
de cada subred (varias tarjetas, VPN, wifi + cable).

**RPC por tema:**

- *Sala*: `_register`, `_sync_players` (authority), `_begin` (authority).
- *Estado*: `_state` (20 Hz, `unreliable_ordered`), `_aspecto`, `_equip`.
- *Daño viejo*: `_hit` — acepta de cualquiera. Lo sustituye el servidor autoritativo; hoy solo lo
  usan las criaturas del PvE, que viven en la máquina del anfitrión.
- *Proyectiles*: `_granada`, `_cohete` (los crea cada máquina y cada una aplica su daño, para que
  nadie cobre dos veces); `_escupitajo`, `_bloque_volador`, `_roca_arrancada` (authority).
- *Destrucción*: `_explode`, `_carve_beam`, `_shoot_remote`, `_escombro`, `_pieza_suelta`
  (authority), `_pieza_asentada` (authority), `_shot`.
- *Equipos y bomba*: `_set_team`, `_sync_teams`, `_bomb_plant`, `_bomb_defused`, `_bomb_exploded`
  (**solo el anfitrión**, o el cráter sería el doble).
- *Ronda*: `_death` (lo anuncia la máquina de la víctima, que es la autoridad de su vida),
  `_round_end`, `_round_start` (authority).
- *PvE*: `_criatura_nueva`, `_criaturas_estado` (array plano a 10 Hz), `_criatura_muerta`, `_oleada`,
  `_estado_pve` (incluye el oro, que es compartido).

**Servidor autoritativo con rebobinado** (final del archivo):

- `HIST_S = 1.0` de historial, `REBOBINADO_MAX = 0.5` de tope (sin él, un cliente podría pedir
  rebobinar diez segundos y "matar" a alguien donde ya no está).
- Cápsula `1.60` / `1.11` agachado / radio `0.35`. Cabeza = los últimos `0.25 m` **desde la
  coronilla**, relativo y no fijo desde los pies: agachado la cabeza está 50 cm más abajo y un
  umbral fijo contaría el pecho de uno como la cara del otro.
- Reloj: `_pedir_reloj`/`_dar_reloj` — ping y reloj en el mismo viaje.
- Historial: `tick_servidor(dt)` desde `main._process`; `_donde_estaba(id, t)` interpola entre las
  dos muestras que rodean el instante.
- Resolución: `pedir_disparo(...)` → `_disparo(...)` → **`resolver_disparo()` solo en el anfitrión**,
  con `_rayo_capsula()`, una intersección analítica a mano (mover a todos al pasado con la física de
  por medio es inviable; la cuenta da lo mismo y cuesta cuatro multiplicaciones por jugador).
- Reparto: `_aplicar_dano` (authority) y `_confirmar_acierto` (authority).

> **Cuando la víctima es el propio anfitrión**, los RPC `call_remote` no se ejecutan en la máquina
> que los manda: hay que llamar a la función directamente. Sin eso, el anfitrión era invulnerable.

---

## 4. Escenas, shaders y recursos

### Escenas

- `scenes/lobby.tscn` — **escena principal**. Seis líneas: `Node3D` + `lobby.gd`.
- `scenes/main.tscn` — la partida: `VoxelWorld`, materiales, `Environment`, jugador y HUD.
- `scenes/player.tscn` — cápsula 0,35/1,60, capa 2 / máscara 5.
- `scenes/enemy.tscn` — capa 4 / máscara 7.
- `scenes/grenade.tscn`, `scenes/rocket.tscn`.

`project.godot`: renderer **mobile**, Jolt, 1280×720, orientación apaisada. Teclas de depuración:
F3 perfilador, F4 CSV, F5 calidad, F6 demoler, F7 bots, F8 mapa, F9 copiar coordenadas, F10 lobby,
F11 depuración estructural, F12 AO.

> No hay nombres de capa de física en `project.godot`; las capas van a número puro (1 = mundo,
> 2 = jugador, 4 = enemigos).

### Shaders — `godot/shaders/`

`voxel.gdshader` (material único del mundo: color por vértice × AO + textura procedural por hash de
celda, sin UVs) · `voxel_ao.gdshader` (oclusión trazada contra la ocupación) ·
**`ojo_pez.gdshader`** (el corazón de la bodycam: curvatura, aberración, obturador de barrido, grano,
nitidez, grado de color, viñeta) · `glass.gdshader` · `cielo.gdshader` · `humo.gdshader` ·
`humo_arma.gdshader` · `fogonazo.gdshader` · `lluvia_gota.gdshader` · `lluvia_lente.gdshader` ·
`nieve.gdshader` · `onda.gdshader` · `disolver.gdshader`.

### Recursos

- `godot/maps/` — `<n>.vxmap` (10 cm) + `<n>_lo.vxmap` (20 cm) y sus JSON.
- `godot/armas/` — 14 `.glb` + `armas.json` (la ficha con los puntos de anclaje).
- `godot/avatar/` — `soldier_rig.json` (malla y esqueleto), `sven_lagom.bin` (clips base),
  `clips_breach.json` (clips hechos en Blender), `recarga_fusil.json`, `mazo.json`,
  `caida_arma.json`, `retratos/`.
- `godot/criaturas/` — 11 `.glb` con esqueleto y clips.
- `godot/sounds/` — `td/` (biblioteca de Teardown por material), `criaturas/` (sintetizadas),
  `pve/`.
- `godot/assets/` — iconos, splash, texturas de shader y `mapas/` con la foto de cada mapa.

> Las fotos de los mapas se cargan **cacheadas y precalentadas** (`lobby._foto_mapa`). Cargarlas
> con `load()` en cada clic era el cuelgue al elegir mapa: 219 ms en PC, segundos en el móvil.

---

## 5. Herramientas: `tools/`

**Mapas importados**: `bake_teardown_map.py` (mod de Teardown → `.vxmap` 10 y 20 cm, cuantizando la
paleta a 239 materiales y conservando la clase física), `fix_floaters.py`, `extract_xml_lights.py`,
`extract_map_lights.py`, `find_markers.py`, `probe_column.py`.

**Mapas propios**: `generar_mapa_monaco.py`, `generar_mapa_pve.py`, `generar_mapa_pruebas.py`, con
sus carpetas `tools/mapa_monaco/` y `tools/mapa_pve/`. Las dos siguen el mismo esquema: `lienzo.py`
(primitivas), `disposicion.py` (única fuente de verdad de rectángulos), `relleno.py`, `raster.py`
(primitivas → chunks, por baldosas de 256² para no pasar de RAM), `respaldo.py` (contenido
provisional si una zona revienta), **`validar.py`** (replica el A* de `vx_nav.cpp` sin abrir Godot),
`vista_previa.py`, y un `zona_*.py` por barrio.

**Blender**: `tools/blender/` (avatar y animaciones), `tools/blender/armas/` (las 14 armas montadas
pieza a pieza con su mira soldada), `tools/blender/criaturas/`.

**Las animaciones del Goliat** (`tools/blender/criaturas/goliat.py`) llevan un sistema aparte, porque
son las que más se miran (es el jefe y la pelea dura minutos):

- **Cara de verdad.** Además de la mandíbula hay huesos para las cejas, los labios de arriba, los
  ollares, los globos de los ojos y la garganta. `cara(ceja, labio, ollar, parpado, mirada, buche)`
  arma la expresión y las constantes `ACECHO / GRUNIDO / FURIA / BRAMIDO / ESFUERZO / DOLOR / AGONIA`
  son las que se repiten. La encía al rojo va en el cráneo y el labio la tapa: al gruñir se le ve.
- **Filtros** (se pasan después, sobre el clip entero): `arrastre` (muelle amortiguado: la cola, la
  lengua y la mandíbula llegan tarde y se pasan de largo), `sacudida` (el golpe sacude al bicho en el
  fotograma del impacto), `temblor` (la vibración del que hace fuerza) y `respirar` (aire en dos
  tiempos y fuera en tres).
- **El fotograma del impacto lo espera el juego** (`amago` en `pve.gd`): zarpazos 16, doble 22,
  mordisco 16, coletazo 22, pisotón 18, golpe al suelo 24, y `arrancar` suelta el pedrusco en el 50.
  Si se mueven, hay que mover también `pve.gd`.
- **`vel_clip`** (caminar 2,43 y correr 6,17 m/s) está **medido** sobre el propio clip con
  `alza_pie`/`paso`: es la velocidad a la que el pie apoyado se queda quieto en el suelo.
- **Para MIRAR las animaciones**, el `.blend` de origen no vale: el IK de Blender dobla las rodillas
  hacia dentro. `exportar_glb.py ... --blend <ruta>` guarda una copia ya horneada, que es lo que se
  ve en el juego.

**Otros**: `generar_sonidos_pve.py` (sintetiza las voces de las criaturas desde cero),
`import_teardown_sounds.py`, `make_fogonazo.py`, `make_soldier.py`, `comparar_huella.py` (compara la
huella del mapa entre anfitrión e invitado tras `--lanreport`).

**Compilación**: `build_core.bat`, `build_extension.bat`, `build_extension_android.bat`.

---

## 6. Formato de los mapas

`.vxmap`, binario propio, little-endian:

```
'VXMP' (4B) | version u32 | voxel_size f32 | dims i32×3 | origin f32×3
n_materiales u16 + por material: R,G,B,strength (u8×4), density u16, flags u8, support u8, massQ u8
   (id 16 = suelo; 17.. = paleta. flags: 1 anchor, 2 indestructible, 4 glass, 8 emissive)
n_spawns u16 + por spawn: x,y,z,yaw (f32×4)
n_chunks u32 + por chunk: clave u32, n_runs u32, runs (len u16, valor u8)   <- RLE, chunk de 32³
```

**El `.vxmap` guarda color y física por material, pero no nombres.** Para saber de qué está hecho
algo hay que mirar `strength`/`class`, no un nombre — cosa que ha causado más de un bug.

Archivos que acompañan a un mapa (todos opcionales, en `res://maps/`):

| Archivo | Para qué |
|---|---|
| `<mapa>.lights.json` | Faroles: posición, color, energía, alcance, y `dir`+`cono` si es un foco. El horneador descarta las luces de Teardown, así que esto las repone. Mónaco tiene 240. |
| `<mapa>.sites.json` | **Activa el modo bomba** por su mera existencia. Sitios, radio, spawn de los CT. |
| `<mapa>.dm.json` | **Activa el duelo a muerte**. Spawns, objetivo de bajas, altura mínima (por debajo de la cual un bot se da por caído: para el motor, bajo el mundo hay suelo). Opcionales (2026-09-30, `cafeteria`): `salidas_t`/`salidas_ct` (se reaparece en el del propio lado más lejos de los rivales) y `hora` (`"tarde"` → `main.cielo_tarde`, con `sol_azimut`). |
| `<mapa>.pve.json` | Oleadas: spawn del jugador, del jefe y de las criaturas. |

Estado actual: dust2 tiene sitios de bomba; hangar tiene `.dm.json`; monaco y pve_cuarentena tienen
`.pve.json`; **nuke tiene el suyo como `nuke.sites.pendiente.json`**, o sea que no está activado.

---

## 7. Cadena de producción de contenido

### Mapa importado de Teardown
```bat
python tools\bake_teardown_map.py "<mod>" "<escena.xml>" godot\maps\dust2
python tools\fix_floaters.py godot\maps\dust2.vxmap
python tools\extract_xml_lights.py "<mod>" "<escena.xml>" godot\maps\dust2.lights.json godot\maps\dust2.vxmap
python tools\find_markers.py "<mod>" "<escena.xml>" godot\maps\dust2.vxmap <patrones>
```
Luego: foto en `godot/assets/mapas/<nombre>.(png|webp|jpg)`, descripción en el diccionario `descs`
de `lobby._tab_play()`, y los JSON de modo a mano. El mapa aparece solo en la lista.

### Mapa propio
```bat
python tools/generar_mapa_monaco.py  [--sin-validar] [--solo=zona_casco,...]
python tools/generar_mapa_pve.py
```
Para una zona nueva: su rectángulo en `disposicion.py` + un `zona_<nombre>.py` que pinte primitivas.
El integrador la llama sola y usa `respaldo.py` si falla.

### Arma nueva
1. Montarla en `tools/blender/armas/armas.py` con las piezas de `piezas.py`, **apuntando a +Y de
   Blender** con +Z arriba. Un punto de Blender `(x,y,z)` es `(x,z,-y)` en Godot.
2. `blender -b --python tools/blender/armas/exportar_armas.py -- [ids]` → `.glb` + `armas.json`.
3. `Godot --headless --path godot --import` (si no, el `.glb` no entra en el APK).
4. Estadísticas en `weapons.gd` (`STATS[id]`, `PRECIOS[id]`). **El juego no mide nada: lee la
   ficha**, así que no hay dos listas que mantener.

### Animaciones del avatar
```bat
blender -b --python tools/blender/soldado_a_blender.py -- soldado_breach.blend
blender -b --python tools/blender/caminar_anim.py -- soldado_breach.blend ciclo.blend caminar
blender -b ciclo.blend --python tools/blender/exportar_clips.py -- godot/avatar/clips_breach.json caminar 3.1
```
Los huesos `*_l` del soldado son el **derecho anatómico**, y el juego sujeta con `hand_r`: cada
exportación de Blender al juego **refleja en X e intercambia l/r**.

**La subida a un muro** (desde 2026-09-16) es un clip de un solo uso con su propia raíz:
```bat
blender -b --factory-startup --python tools/blender/trepar_real_anim.py -- soldado_breach.blend trepar.blend
blender -b trepar.blend --python tools/blender/exportar_clips.py -- godot/avatar/clips_breach.json trepar 0 30 arma unavez
```
- `unavez` exporta solo el tramo `juego_desde`-`juego_hasta` de la escena (46-136: del agarre al
  paso final, 3 s) y añade la pista `raiz`: dónde van los pies respecto al canto, cuándo apoyan las
  palmas, cuándo va el fusil a la espalda y el esfuerzo.
- `player.gd::_trepar_raiz` coloca al jugador con esa pista sobre el canto real, escalada a
  `ALTURA`. En un muro más bajo que el animado (1,55 m para el avatar del juego) la subida **entra a
  mitad** (`avatar_animator.trepar_inicio`) y dura menos. Mientras sube, el cuerpo sigue de cara a la
  pared aunque mires a otro lado.
- La red manda en qué segundo del clip va (`trepa_reloj` en `_state`), para que los demás la vean
  sincronizada.
- Banco: `python tools/generar_mapa_muros.py` y `Godot --path godot -- --map=muros --treparfoto
  [--primera]` (muros de 1,30 a 2,30 m: tiempo, manos contra el canto, nada metido en el muro, fotos).
  Borra luego `maps/muros*.vxmap`, que si no entran en el APK.

### Modelo de avatar esculpido en Blender (camino de vuelta)

Hasta 2026-09-15 el camino era de **una sola dirección**: `make_soldier.py` generaba el rig y
`soldado_a_blender.py` sacaba una foto a Blender; lo que se retocara allí se perdía. Ahora vuelve:

```bat
blender -b --python tools/blender/soldado_a_blender.py -- mimodelo.blend --piezas heraldo_yelmo,heraldo_capa
:: ...se esculpe en Blender, con cubos...
blender -b mimodelo.blend --python tools/blender/blend_a_pieza.py -- heraldo_pro
python tools\make_soldier.py
Godot --headless --path godot --import
```

- `blend_a_pieza.py` deja `tools/piezas_blender/<nombre>.json` y `make_soldier.py` lo mete en el
  catálogo de piezas al generar el rig (función `piezas_de_blender`). **Todo lo que haya en esa
  carpeta entra**: no dejes pruebas sueltas ahí.
- **La rejilla del avatar es de 2,22 cm** (el voxel del rig escalado a 1,75 m). Lo que se esculpa más
  fino se FUNDE al importar: el Heraldo Forjado vino con cubos de 1,5 y 1,1 cm y sus 18.333 cubos se
  quedaron en 8.242 voxels. Para no perder detalle, esculpe con cubos de 2,22 cm.
- Los colores se comparan con la paleta y los que no estén se añaden **al final** (nunca en medio:
  insertar corre todos los índices siguientes). La vuelta es exacta: exportar e importar el mismo
  modelo da **0 colores nuevos**, y eso es lo que se usa para comprobar que el importador no desvía.
- Un modelo entero lleva `tapa` (la lista de huesos de los que es dueño) y el soldado de debajo no se
  dibuja. `quita` (por color) y `borra` (por coordenada) siguen siendo para prendas sueltas.
- Cada color nuevo se suma a `colores_soldado`, porque el juego calcula dónde empieza el bloque de
  colores del soldado como `len(paleta) - colores_soldado`. Si no cuadra, `quita` borra otra cosa.

### Retratos de la tienda y del armario

`Godot --path godot -- --retratos` hornea `godot/avatar/retratos/*.png` (hace falta **ventana**: en
`--headless` no hay fotograma que capturar y se queda colgado). Después hay que **reimportar**
(`--import`), o el juego sigue cargando el `.ctex` viejo y parece que el horneado no ha servido.

---

## 7 bis. Primera persona, cámara y espectador

Todo esto vive en `player.gd` (constantes al principio del archivo) y se ajusta **midiendo con
capturas**, no a ojo: las pruebas sacan la foto y dicen en píxeles cuánto se desvía lo que se mira.

| Qué | Dónde | Valor y por qué |
|---|---|---|
| Distancia de la óptica al apuntar | `ADS_DIST` | 0,22 m. Con los 0,38 de antes la mira quedaba lejos y el retículo ocupaba cuatro píxeles. |
| Ídem para pistolas | `ADS_DIST_PISTOLA` | 0,16 m. Una pistola es corta y no tiene óptica que agrandar: a la distancia del fusil se veía diminuta. |
| Pistola del escudo | `ESC_FP_ADS` | 0,18 m (antes 0,30). Un poco más lejos que una pistola suelta, que el escudo está al lado. |
| Pose de correr | `FP_SPRINT_OFF` / `FP_SPRINT_ROT` | El arma baja y se tercia, cañón abajo-izquierda. **La de antes dejaba el arma fuera de cuadro**: corriendo no se veía nada en las manos (`--esprintfoto`). |
| Al apuntar corriendo | `_sprint_w` | Se pone a cero **de golpe**. Apagándose despacio, el arma iba a "apuntando + pose de correr" (14 cm más arriba) y bajaba después: eso era el "sube de más y se acomoda" (`--apuntacorriendo`). |
| Escudo en guardia | `ESC_FP_GUARDIA` | El visor centrado en la cámara. Medido: estaba 111 px a la derecha. |
| Escudo según la pantalla | `ancho` en `_escudo_fp` | El juego mantiene el ALTO y ensancha: en 16:9 la ventana cubre el 63 % del ancho y en 20:9 cubría el 50 % ("en el móvil se ve chiquitito"). Se agranda con la proporción de pantalla y se corrige el desvío que mete la propia escala. |
| Vida del escudo | `escudo.gd: VIDA` | 300 (era 500). |
| Ventana del escudo | `tools/blender/armas/escudo.py: VENTANA` | 38 × 17 cm (era 26 × 9) y cristal propio `cristal_escudo`, casi transparente: el de las miras tiñe de azul a propósito y aquí es por donde MIRAS. |

**La flecha de "me disparan desde ahí"** (`hud.gd::_update_damage_arcs`) tenía dos fallos: el lado
estaba cambiado (a quien te disparaba desde la derecha lo señalaba a la izquierda) y el ángulo salía
del vector de la cámara **con su cabeceo**, así que mirando al cielo o al suelo sus componentes x/z se
van a cero, `atan2` devuelve cualquier cosa y la flecha giraba sola. Ahora los dos vectores se aplanan
al suelo. `--flechatest` lo comprueba desde los cuatro lados con la cámara recta, a −80 y a +80 grados.

**Cámara de muerte y espectador** (`player.gd`): al caer, la cámara pasa `KILLCAM_S` segundos por
encima del hombro de quien te mató, mirando a donde caíste. **No es una repetición rebobinada** —eso
pediría grabar el estado del mundo entero—, es la cámara puesta sobre él en vivo, que es lo que dice
de dónde vino el tiro. Después entra el espectador, y ahí **disparar pasa al siguiente compañero y
apuntar al anterior** (en móvil valen los dos botones de siempre). Antes `_pick_spectate_target`
reasignaba el objetivo cada 20 fotogramas, así que aunque hubiera botones no se habría quedado quieto.

**Modo enfoque** (`main.gd::_enfoque_barato`): apuntando, la profundidad de campo difumina todo menos
lo que miras, así que se baja la resolución del 3D (×0,78), se acortan las sombras (×0,6) y se apaga la
pasada de lente. Con histéresis (0,65 entra, 0,35 sale): sin ella, apuntando a medias la resolución
cambiaría varias veces por segundo. Medido: con la resolución equivalente, demoliendo se pasa de 27 a
33 fps; quieto no cambia nada, porque ahí el cuello de botella es el procesador.

**Modo foto** (`main.gd::foto_modo_max`, lo usa el botón SACAR FOTO): esconde el arma, quita el
desenfoque y la estela, y sube **el valor más alto de cada opción** —que no es el preset ULTRA, capado
a propósito para que vaya fluido—, espera a que el mundo termine de cargar a esa distancia y devuelve
tu configuración. El orden importa: el modo máximo se aplica ANTES de esconder la interfaz, porque
aplicar la calidad vuelve a tocarla y reaparecían la mira y la munición (`--fotomenu`).

## 8. Flags de línea de comandos

> **Van SIEMPRE detrás de un `--`.** Se leen con `OS.get_cmdline_user_args()`.
> `Godot --headless --path godot -- --servertest`

Hay unos **250**. Los que más se usan:

**De la tanda de 2026-09-17** (primera persona, jefe y rendimiento): `--bancofps` (banco repetible de
destrucción, con variantes `--oclusion`, `--sombras=N`, `--nosombras`, `--escala=N`, `--sinlente`,
`--sinfisica`, `--sinestructura`, `--cielosimple`, `--sinarma`, `--sininterfaz`, `--mirarcielo`,
`--sinromper`), `--goliatfps`, `--goliatmira` (¿le llega la mano al jugador?), `--goliatpared` (¿el
jefe atraviesa las casas?), `--escudofoto` (el visor en píxeles), `--esprintfoto` (cómo se corre con
cada arma), `--apuntacorriendo` (apuntar mientras corres), `--flechatest` (la flecha de daño desde los
cuatro lados y con la cámara arriba y abajo), `--killcamtest` (cámara de muerte y cambio de compañero),
`--fotomenu` (el botón SACAR FOTO).

**Los cuatro fallos de partida real de 2026-09-15** (ver
[09_BLOQUES_Y_RED.md](09_BLOQUES_Y_RED.md#cuatro-fallos-de-partida-real-2026-09-15)):
`--eliminatest` (con `--lanhost=`: los bots cuentan para el fin de ronda), `--botspegados`
(distancia entre bots al nacer y a los 15 s), `--victorialan` (se mata al jefe: ¿abren la pantalla de victoria las dos máquinas?), `--tiendalan` (botiquines que ven y recogen todos, la palanca del jefe en las dos pantallas, la oleada
10 solo con el jefe, el cartel de arriba del invitado y el contador de bajas), `--migrapve` (tres instancias: el anfitrión se va en mitad de una oleada, ¿sigue la partida?),
`--cadavercae` (¿se cae el cuerpo del compañero muerto, y revive el anfitrión al superar la
oleada?), `--metralla=N` (N balas, una por cuadro, moviéndose y barriendo la mira; se compara con
`tools/comparar_huella.py`), `--tirozombi` (¿le llega al anfitrión el daño que hace un invitado a un
bicho?), `--muertopegado` (¿el compañero muerto que te espectá se queda donde cayó?), `--zurranalmuerto`
(¿a quién le pegan los zombis cuando cae un compañero, y se levanta al revivir?),
`--muertepve` (con bando puesto, ¿se entera el modo
oleadas de que he muerto?) y `--lanzombis` (dos instancias: bichos vistos id a id, derrota con todos
muertos y que el revivido vuelva a ser mortal).

**Mapa y calidad** — `--map=<n>`, `--city`, `--dust2`, `--hi` (10 cm), `--lo` (20 cm), `--noload`,
`--nobots`, `--nohud`, `--noshadow`, `--noocc`, `--novsync`, `--bench`, `--stress`, `--qcompare`.

**Pruebas con resultado medible** — `--servertest` (matemática del rebobinado: 13 comprobaciones),
`--fisicatest` (el mismo derribo a distintos FPS: dice si la simulación depende de los fotogramas),
`--balastest` (¿le dan las balas a los escombros?), `--mesatest=N` (vuela N patas de la mesa y mide
el vuelco), `--falltest=x,y,z[,r]`, `--puertas` (mide la altura libre de todo el mapa),
`--materiales` (qué trae de verdad la paleta de este mapa), `--mapaclick` (mide elegir cada mapa),
`--navtest`, `--collapse`.

**LAN** — `--lanhost=<sala>` + `--lanjoin=<ip>` levantan el banco de dos instancias;
`--tirolan` (disparo de punta a punta con el servidor autoritativo), `--fisicalan`, `--lanreport`
(huella del mapa, se compara con `tools/comparar_huella.py`), `--asientos`.

**Diagnóstico de bots** — `--botsnophys`, `--botsnoavatar`, `--botsnoweapon`, `--botsanim0`,
`--botsnoshoot`, `--botsnocol`, `--botsfreeze`: sirven para aislar de dónde sale el coste.

**Capturas** — `--screenshot` (+ `--standat=x,y,z --lookat=x,y,z --shotframes=a,b,c`),
`--lobbyshot [--tab=N]`, `--botshot [--botclip=<clip>]`, `--bcfoto`, `--gfxfoto`, `--mapafoto`.

**Modos** — `--pve`, `--pveoleada=N`, `--pvesolo=<tipo>`, `--heisttest`, `--dmtest`, `--ciudad3test`, `--robotest` (robar el terminal), `--atracolan` (atraco en red, anfitrion+invitado),
`--pickteam=t|ct|v`.

**Editores** — `--miraeditor` (puntería y poses), `--touchedit` (controles táctiles).

---

## 9. Decisiones raras con su motivo

Las que hay que conocer antes de "arreglar" algo que parece mal hecho.

### Estructura y derrumbe
- **`STRESS_CAPACITY` pasó de 220 a 660.** Con 220, una estructura sana ya estaba al 100 % de su
  capacidad y cualquier redistribución rompía muros en cremallera. Ahora una sana queda al 30-45 %.
- **Calibración por estructura.** Una torre de 50 m intacta salía a 20-300 veces su capacidad
  nominal. Se mide el percentil 98 de la estructura tal como fue construida y se escala. La
  calibración solo **sube** durante la vida de la región, para no cambiar el criterio a mitad de un
  derrumbe.
- **Línea base.** Lo que el autor del mapa construyó se considera estable por definición aunque su
  ratio nominal sea >1. Una celda solo falla si el daño sube su ratio un 10 % por encima de la base.
- **La puerta del vuelco.** Sin ella, un boquete asimétrico movía el centroide del apoyo unos
  centímetros y subía la presión en *todos* los apoyos un 15-60 %: un solo cohete tiraba un edificio
  entero. Medido: con la puerta, 1 cohete deja el edificio al 96,8 %; sin ella, al 0,6 %.
- **Borde de la región como apoyo solo si hay material debajo.** Sin esa condición, cualquier losa
  que llegara al borde tenía apoyo gratis e infinito — eso era lo que hacía que "un voxel sostuviera
  un edificio entero".
- **Pandeo.** A compresión pura, 10×10 cm de hormigón aguantan decenas de toneladas, así que un
  tocón aislado sostenía un edificio. La capacidad se escala por el contacto lateral real.
- **Descarga en cono** (50 % recto + 12,5 % a cada diagonal). Sin ella, todo el muro sobre un boquete
  se colaba por la celda del dintel y fallaba en cremallera por toda la fachada.
- **Bloques de 8 m en derrumbe estructural, no de 1,4 m.** A 1,4 m una torre se deshacía en miles de
  cascotes y el jugador se colaba entre los trozos fantasma.
- **Regla *pristine* por conjunto.** Lo que flota en un nivel recién cargado no cae (los mapas
  importados tienen miles de flotadores). **Extraer una pieza NO cuenta como daño**: si contara, cada
  pieza que cae arrastraría en cadena todo lo flotante de alrededor.

### Destrucción
- **El daño de bala se acumula** (umbral 120 voxels) antes de abrir análisis estructural. Antes se
  podían cortar a tiros tres de cuatro patas sin que pasara nada.
- **`carveBullet` con cristal usa `soloFlags = MF_GLASS`.** Sin el filtro, la esfera de 65 cm a
  potencia 255 se llevaba el marco de hierro y la pared de al lado.
- **Ruido de borde en toda esfera de más de un voxel.** Sin él, una bala cogía siempre los 6 vecinos
  de cara y nunca los diagonales: una cruz perfecta idéntica en cada disparo.
- **El 30 % de lo destruido vuelve como cascote.** Empezó en 85 % (sepultaba la escena), bajó a 17 %,
  se probó al 50 % (demasiado). Los trozos son de **gameplay**: no dependen de la calidad ni de la
  plataforma. Las partículas visuales sí.
- **El mazo pregunta la dureza a `Audio.material_class()`**, la misma función que elige el sonido.
  Usar otra regla daba el absurdo de que algo sonara a metal y se rompiera de un golpe como el yeso.

### Red
- **No hay id de trozo común entre máquinas.** La misma explosión da cuatro trozos o siete; el
  reparto depende del tiempo. Por eso viaja el resultado en crudo, celda a celda.
- **Solo viaja lo que de verdad se quitó del mundo.** Un trozo de explosión crece desde el voxel
  reventado y se come celdas que siguen en pie: medido, 548 de 2.678 en un derribo.
- **El agujero en un cascote no se recalcula con otro rayo** en la máquina remota: su copia está unos
  centímetros movida y el rayo se pasaba de largo. Se busca el trozo alrededor del punto de impacto.
- **En red, un cascote pequeño nunca detiene la bala**: no están sincronizados (medido: 387 voxels de
  diferencia en una ráfaga de 12 tiros).
- **En LAN los bots se dejan fuera a propósito** hasta que la IA sea autoritativa del anfitrión.

### Rendimiento
- **`set_personajes` incluye bots y remotos.** Antes solo miraba al jugador local, así que un bot
  subido a una estructura que se derrumbaba se colaba por el escombro, y en LAN tu amigo atravesaba
  lo que tú veías sólido.
- **`get_stats()` cuesta ~0,4 ms** → solo se llama cada 4 frames.
- **Topes por frame** en el drenaje de eventos (40 eventos, 4 farolas, 8 sonidos). Con `--stress` ese
  bucle se comía 5 ms. Los `blast` nunca se descartan.
- **El análisis estructural NO se apaga cuando el host va sobrecargado** (antes sí): se apagaba justo
  en el único momento en que hace falta.
- **El polvo va después de la guarda de carga por seguridad**, no por orden: estaba arriba y un error
  suyo reventaba `_process` antes de actualizar la barra, dejándola clavada al 100 % para siempre.
  *Un adorno no puede impedir que arranque la partida.*
- **`ragdoll.gd` no cuelga del avatar**: el avatar vive a escala ~0,021 y a esa escala los tensores
  de inercia salen minúsculos → ragdoll que vibra, atraviesa el suelo o explota.
- **`escuadra.gd`**: veinte bots avisándose entre sí son 400 llamadas por aviso. Con un tablón,
  avisar cuesta una entrada. Y las alertas caducan, o el primer disparo seguiría llamando gente diez
  minutos después.

### Qué NO era el lag de la destrucción (medido, 2026-09-17)

El usuario: *"el Goliat cuando destruye empieza a sentir mucho lag"*. Se hizo `--bancofps` (banco
repetible: nadie vivo, jugador clavado, explosiones en puntos fijos, dos fases) porque el primero no
servía para optimizar — como el jefe anda y pelea solo, la misma prueba daba 24, 35 y 46 fps con los
mismos ajustes. Lo que salió:

- **Quieto, sin romper nada, la escena ya va a ~48 fps** en cuarentena. La destrucción añade unos
  10 ms más (hasta ~32 fps). O sea que el problema no empieza con la destrucción.
- **Se descartó midiendo** (apagando cada cosa y volviendo a medir): los escombros y sus dibujos (solo
  20-60 instancias: la fusión por celdas va sobrada), las sombras, el shader del cielo, el brillo, la
  niebla volumétrica, el analizador de derrumbes (40-160 ms por iteración, pero en hilos aparte), el
  A* de los bichos (0,2-3 ms) y los guiones (1-2 ms en total). Rehacer los colisionadores tampoco era.
- **Lo que sí pesa**: la interfaz ~3,5 ms por fotograma siempre (ocultándola: 48 → 58 fps) y rehacer
  las mallas de bloque al romper, 3-5 ms.
- **Mirando al cielo vacío, sin interfaz ni arma, el fotograma sigue costando 17 ms**: hay un coste
  fijo grande en esta máquina que no depende de lo que se dibuje.
- **Se probó un repartidor de presupuesto por fotograma** (medir cuánto queda hasta los 16 ms y
  repartirlo entre las fases) y **empeoró**: como la máquina ya va por encima del objetivo, se quedaba
  sin presupuesto y el trabajo se acumulaba. Revertido. Está contado aquí para que nadie lo reintente
  creyendo que es obviamente bueno.

### Segunda tanda, en Mónaco (medido, 2026-09-17)

`--bancofps --map=monaco --sitio=99.2,6.5,100,0` (frente a la catedral, sin bots: en atraco pelean entre sí y
cada corrida rompía cosas distintas; ahora el banco los borra). El banco imprime además los 8 peores fotogramas
con sus ticks de física y el peor paso, el perfilador del guion por fase con **media/peor** por clave (`Prof`), y
las fases de la extensión con su peor tramo (`t_hmax_*`: regiones, bloques, subida de malla, piezas...).

**Lo que sí era, y se arregló:**
- **El sonido de cada escombro que aterriza: 8 ms por fotograma demoliendo.** Cada `play()` de un OGG cuesta
  ~1 ms (instancia el decodificador) y el núcleo entrega hasta 24 aterrizajes por fotograma; con el presupuesto
  de 8 voces bajas, 8 ms de cada fotograma para un rumor a −14 dB. Ahora uno cada 25 ms
  (`Audio.escombro_gap`; `--sinlimiteescombro` lo quita para medir). Medido ABAB: −4 y −7,5 ms por fotograma.
- **Bajones de 50-140 ms la PRIMERA vez que sonaba cada clave**: la biblioteca se cargaba perezosa
  (`DirAccess` + `load` por archivo) en mitad de la partida —el primer aterrizaje, el primer impacto de cada
  material—. `Audio.precalentar()` carga las claves que usa el juego durante la pantalla de carga (78 claves,
  con presupuesto por cuadro). La física del jugador pasó de picos de 146 ms a 19.
- **La primera explosión costaba 158 ms**: el material del humo volumétrico (shader + texturas) y el estreno
  de las partículas. `effects.precalentar()` lo hace al acabar la carga, bajo el suelo delante de la cámara
  (dentro del encuadre, tapado por el terreno). Ahora 58 ms; lo que queda es la onda en pantalla (31 ms).
- **`reconstruirPendientes` llegaba a 65 ms en un cuadro** (dos bloques grandes rehechos seguidos): ahora
  con presupuesto de tiempo, 6 ms.
- **Las regiones cercanas rehacían sus dos mallas LOD invisibles en cada explosión** (20-35 ms por región,
  el mayor pico del hilo principal). Se aplazan (`lodStale`) hasta que la región pase a verse de lejos; el
  caster de sombras y el oclusor se rehacen igual. p95 demoliendo: 74-78 → 67-71 ms.
- La altura de la forma del jugador se escribía cada tick aunque no cambiara (Godot no filtra el valor
  repetido y Jolt rehace la forma). Ahora solo si cambia.

**Lo que se midió y NO era (o no dio nada):**
- **El tope de pasos de física por cuadro (8 → 4)**: idéntico, medido ABAB con `--maxpasos=N`. A 40-50 ms
  por fotograma salen 3 ticks con cualquiera de los dos; el problema es que cada tick cuesta 9-13 ms
  demoliendo (Jolt con 70-140 bloques despiertos), no cuántos se hacen.
- **Umbrales de sueño de Jolt** (0,1 m/s y 0,3 s): sin cambio medible.
- **Búfer de staging de Vulkan más grande**: sin cambio; el pico de subida varía 16-33 ms según el tamaño
  de la región que toque.
- **Quitar la compresión de atributos de las mallas** (`--sincompresion`): sí baja la subida a la mitad
  (30 → 16 ms por superficie), pero la VRAM ya va por 843 MB en Mónaco y sin compresión sería ~1,2 GB.
  Queda como opción a medir en móvil, no activada.
- **`move_and_slide` del jugador cuesta 2-5 ms por tick quieto** (15-25 % del fotograma en calma). Es el
  CILINDRO: con cápsula (`--capsula`) baja 7 veces (5,3 → 0,7 ms) y con caja (`--caja`) a la mitad. No se
  tocó porque el cilindro es lo que hace subir los escalones (ver `--escalontest`); si algún día se cambia,
  hay que pasar esa prueba.
- **Lo que sigue pesando y no tiene arreglo barato**: el paso de física demoliendo (Jolt, ~10 ms por tick
  con el escombro despierto), la subida de mallas al servidor de render (16-30 ms por superficie, es el
  propio `mesh_add_surface_from_arrays`: se podría sacar a un hilo, con cuidado con el orden de
  `mesh_clear`/`free_rid`), y `Engine::update` en el hilo principal tras una explosión (12-16 ms).
- **La máquina varía mucho entre corridas** (quieto 46-62 fps con la misma escena; lo que se derrumba
  cambia con el analizador estructural). Cualquier comparación va **ABAB** y mirando medianas y peores
  fotogramas, no una corrida suelta.

Flags nuevos del banco: `--sitio=x,y,z,giro`, `--bancofoto`, `--maxpasos=N`, `--sinlimiteescombro`, `--capsula`,
`--caja`, `--sinsnap`, `--sincompresion`.

### Tercera tanda: GPU, Mónaco que se cae solo y dos bugs (medido, 2026-09-18)

- **GPU en calma, pieza a pieza** (`--bancofps --sinromper` con `--sinao`, `--sininterfaz`, `--sinlente`,
  `--sinluces`, `--sinmsaa`, `--sinmblur`, `--noglow`, `--escala=`, `--nosombras`): la oclusión de voxels,
  la lente, el motion blur, el glow y las farolas **no cuestan nada medible**; la interfaz ~1 ms; **MSAA 2x
  1,7 ms y la escala al 50 % otros ~5 ms** (ajustes del jugador, no desperdicio); las sombras 3 ms. El resto
  (~10 ms de 16) es geometría, independiente de la resolución. **La oclusión de cámara del banco nunca
  activó los oclusores** (0): el flag ahora llama a `set_use_occluders`. Único desperdicio real: el caster
  de sombras de cada región dibujaba 1,42 M de triángulos (más que la escena); ahora solo lleva las caras
  que miran al sol (`set_shadow_light_dir`, 0,80 M), sin ganancia de GPU medible pero a mitad de coste al
  reconstruirlo.
- **Lo que se caía solo en Mónaco.** Auditoría en el motor sobre el mapa real (`--auditaflotadores`):
  **906 conjuntos sin ancla, 94.000 voxels, todos pequeños** (balcones de las torres, toldos, lámparas,
  setos, cipreses a un voxel de la pared). Por la regla *pristine* caían en cascada al dañar a menos de
  ~10 m. Arreglo: **el motor los suelda al cargar** (`Engine::weldFloaters`: rellena el hueco hasta el
  sólido más cercano a ≤ 0,5 m; 755 de 906, determinista, sin contar como daño). Los trozos grandes que
  caen tras varias explosiones son el **modelo de carga**, que a 10 cm por voxel tira 10-15 veces más masa
  que a 20 cm con la misma geometría: no se ha tocado. Todo en
  [10_CONSTRUIR_MAPAS.md](10_CONSTRUIR_MAPAS.md), con las reglas para el próximo mapa.
- **Fin de partida**: con la pantalla de victoria puesta el juego seguía (bots disparando, oleadas, el
  jugador mortal). `_congelar_fin_partida()` para bots, criaturas, oleadas y la entrada del jugador; el
  mundo y la red siguen.
- **Tierra en la lente**: llegaba desde 4 radios de la explosión (16 m con un misil); ahora 2.
- Banco: ya no lee el ratón (la vista derivaba hasta 11°), `--explosiones=N`, `--radio=R`, `--sinromper`,
  `--sinrecortesol`, y `VX_NOWELD=1` / `VX_WELDGAP=<m>` para medir la soldadura.

### Cuarta tanda: los 30 fps del movil (medido en un Snapdragon 8 Gen 1, 2026-09-22)

El usuario: *"en calidad baja se limita a 30 fps"*. Eran **cuatro cosas distintas, una detrás de otra**, y
ninguna se habría encontrado sin medir en el propio móvil (contador de FPS ampliado: tope, Hz, vsync, GPU,
CPU y las claves de `Prof` que más suben; se enciende en GRÁFICOS → RENDIMIENTO).

- **El juego se topaba solo a 30** en móvil con calidad BAJA (`apply_quality`/`apply_graphics`), y a 60 en el
  resto pasara lo que pasara en el menú. Quitado: manda "Límite de FPS".
- **"Sin límite" pedía el refresco que dijera la pantalla.** En un panel LTPO eso es la frecuencia de ESE
  momento: leía 24 o 30 Hz y el juego se quedaba topado ahí. Ahora pide 120 fijo.
- **Swappy (el ritmo de fotogramas de Android) bajaba la pantalla a 30 Hz** y con vsync el juego no puede
  pasar de ahí. En Mónaco: 30 fps con **GPU 10,7 ms**, dibujo 1,7 y guion ~5 — o sea, sitio de sobra para 60.
  Apagando `display/window/frame_pacing/android/enable_frame_pacing` se acabó. **Medido: con vsync en Off
  daba 60 y con Swappy puesto y vsync On, 30.**
- **La viñeta costaba una copia de pantalla entera** por cuadro: va encendida en los cuatro presets y montaba
  la lente completa (`ojo_pez.gdshader` + `BackBufferCopy` a resolución nativa). Ahora, si lo único encendido
  es la viñeta, se dibuja con `vineta.gdshader`, una capa negra por encima que no lee la pantalla (mezclar con
  negro a alfa `a` es igual que `col *= 1 - a`: se ve idéntico). En el PC pasó de ~2,8 ms a nada medible.

`Performance.TIME_PROCESS` **no sirve** para esto: marcaba 28-37 ms en un PC que iba a 60 fps clavados
(incluye la espera a la pantalla). Lo que sirve es el tiempo de GPU del viewport y las claves de `Prof`.

El tope de FPS, la sincronización vertical y el contador ya **no los tocan los presets** (pedido): son del
jugador, como el FOV (`Settings.GFX_PROPIOS`).

### Jugabilidad
- **El joystick táctil tiene dos marchas y nada más.** Antes la velocidad era proporcional al empuje
  (casi nunca ibas a la velocidad de andar real) y correr exigía sostenerlo a fondo 0,35 s, lo que se
  sentía como retardo del juego.
- **Subida de escalones explícita.** En PC la cápsula saltaba los escalones por inercia de la entrada
  1,0 del teclado; con joystick táctil (entrada parcial) se quedaba clavada. Se prueban alturas de
  menos a más y se coge la primera que entra — probar el máximo de golpe chocaba con el techo de la
  caja de escalera. La distancia que se **tantea** y la que se **avanza** son dos cosas distintas:
  unirlas regalaba metros por segundo al subir.
- **El soldado mide 1,60 m con los ojos 15 cm bajo la coronilla**, no 1,80 con los ojos a 1,60.
- **La bodycam limita el FOV, nunca lo ensancha por debajo de tu valor**, y no escribe en los
  ajustes: al apagarla vuelve tu valor solo.
- **Espectar corta antes de la gravedad.** Estaba más abajo y la cámara sin colisión se hundía para
  siempre.
- **Los explosivos derriban, los golpes de criatura no.** Con el Goliat martilleando el suelo cada
  tres segundos te pasabas la pelea levantándote.
- **Los bots no nacen al cargar el mundo** sino al cerrar la elección de bando: antes salían con tu
  bando sin decidir y te disparaban mientras mirabas el panel.
- **El botiquín no se recoge con la vida llena**: se queda para cuando vuelvas herido.
