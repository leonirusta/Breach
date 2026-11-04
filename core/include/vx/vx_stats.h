// vxcore - Estadísticas / instrumentación
// Todo lo que se mide se puede optimizar. El host (Godot) añade GPU time, draw calls
// y RAM de proceso; el núcleo mide sus propios sistemas.
#pragma once
#include <cstdint>
#include <cstddef>

namespace vx {

// Acumulador de tiempos con media móvil y máximo (para detectar spikes).
struct TimeStat {
    double last = 0, avg = 0, max = 0, total = 0;
    uint64_t count = 0;
    void add(double ms) {
        last = ms; total += ms; ++count;
        avg = avg == 0 ? ms : avg * 0.9 + ms * 0.1;
        if (ms > max) max = ms;
    }
    void resetMax() { max = 0; }
};

struct Stats {
    // mundo
    int chunksAllocated = 0;
    uint64_t voxelsSolid = 0;
    uint64_t voxelsDestroyed = 0;
    size_t memWorldBytes = 0;
    // pipeline
    int jobsPending = 0;
    int meshResultsPending = 0;
    int meshUploadsThisFrame = 0;
    int piecesDetachedTotal = 0;
    int groupsStructuralTotal = 0;   // grupos desprendidos por fallo estructural (analizador de cargas)
    int groupsPlainTotal = 0;        // grupos desprendidos por perder la conexión con el suelo
    int groupVoxelsTotal = 0;        // voxels en esos grupos
    int bodiesCreatedTotal = 0;
    int piecesToDebrisTotal = 0;
    int debrisActive = 0;
    int debrisCapacity = 0;
    int revoxelizedBodies = 0;
    int chunksSkippedNoLock = 0;     // chunks saltados por el solve sin tomar su lock (último solve)
    // estructural (analizador de rutas de carga)
    int structIterationsTotal = 0;   // iteraciones ejecutadas
    int structRegionsActive = 0;     // regiones de análisis vivas ahora
    int structIslandsEvaluated = 0;  // última iteración
    int structIslandsSkipped = 0;
    int structCellsEvaluated = 0;
    int structCellsScannedTotal = 0; // celdas escaneadas desde la memoria de chunks (acumulado)
    int structFailuresTotal = 0;     // celdas que han fallado (acumulado)
    int structFragmentsTotal = 0;    // fragmentos generados a partir de celdas fallidas
    int clumpVoxelsTotal = 0;        // voxels de explosión convertidos en trozos rígidos (conservación de masa)
    float structWorstRatio = 0.f;    // peor carga/capacidad de la última iteración
    int structWorstX = 0, structWorstY = 0, structWorstZ = 0;   // y DONDE (voxel de la celda): las grietas antes del derrumbe
    // rayos (World::raycast, todos los hilos)
    uint64_t raysTraced = 0;
    uint64_t raySteps = 0;           // pasos DDA a nivel de voxel
    uint64_t raySkips = 0;           // saltos de región vacía (jerarquía de ocupación)
    // tiempos (ms)
    TimeStat tUpdate;        // Engine::update en hilo principal (sin host)
    TimeStat tUpdEnqueue;    //   fase: enqueueDirty
    TimeStat tUpdCollect;    //   fase: collectResults
    TimeStat tUpdStats;      //   fase: recuento de estadísticas del mundo
    TimeStat tCarve;         // por operación de destrucción
    TimeStat tClumps;        // generación de trozos de explosión (hilo de trabajo)
    TimeStat tMeshJob;       // por chunk, hilo de trabajo
    TimeStat tConnLabel;     // etiquetado por chunk, hilo de trabajo
    TimeStat tSolve;         // resolución grafo global (hilo principal)
    TimeStat tExtract;       // extracción de pieza (hilo de trabajo)
    TimeStat tStruct;        // iteración del analizador estructural (hilo de trabajo)
    TimeStat tStructScan;    //   fase: escaneo de celdas
    TimeStat tDebris;        // partículas (hilo principal)
    TimeStat tNav;           // A* por consulta
    int solvesRun = 0;
};

} // namespace vx
