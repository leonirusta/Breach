// vxcore - configuración global y presets de calidad
// ---------------------------------------------------------------------------
// Este archivo define las constantes estructurales del mundo de voxels y los
// presupuestos (budgets) de cada nivel de calidad. TODO lo que cuesta CPU/GPU/RAM
// está limitado por un número de esta tabla: así el juego escala de un teléfono
// de gama baja a un PC potente sin tocar la lógica.
// ---------------------------------------------------------------------------
#pragma once
#include <cstdint>

namespace vx {

// Tamaño de chunk: 32^3 voxels. A 0.25 m por voxel = 8 m de lado.
// 32 es el punto dulce: 32 KB por chunk (1 byte/voxel), cabe en L1/L2, y el
// remallado greedy de un chunk cuesta ~0.3-1 ms en CPU móvil.
constexpr int CHUNK_BITS   = 5;
constexpr int CHUNK_SIZE   = 1 << CHUNK_BITS;       // 32
constexpr int CHUNK_MASK   = CHUNK_SIZE - 1;        // 31
constexpr int CHUNK_AREA   = CHUNK_SIZE * CHUNK_SIZE;
constexpr int CHUNK_VOLUME = CHUNK_AREA * CHUNK_SIZE; // 32768
constexpr int PAD_SIZE     = CHUNK_SIZE + 2;        // 34: chunk + 1 voxel de vecinos (culling/AO)
constexpr int PAD_VOLUME   = PAD_SIZE * PAD_SIZE * PAD_SIZE;

// Tamaño de voxel por defecto en metros. 0.25 m permite paredes de 1 voxel
// (25 cm) realistas y pisos de 3 m = 12 voxels.
constexpr float DEFAULT_VOXEL_SIZE = 0.25f;

// Navegación de IA: celda de nav = 2x2 voxels (0.5 m), agente 7 voxels (1.75 m)
constexpr int NAV_CELL        = 2;
constexpr int NAV_AGENT_H     = 7;
constexpr int NAV_STEP_UP     = 3;   // 0.75 m
constexpr int NAV_MAX_DROP    = 12;  // 3 m

// Modelo de carga (StructuralAnalyzer): un voxel de sección de hormigón aguanta STRESS_CAPACITY "voxels de
// hormigón" de masa encima. Un pilar de 2x2 aguanta 2640 voxels (una losa de 25 cm de 13x13 m); una pared de
// 1 voxel de grosor y 5 m aguanta 13.000. Calibrado para que una estructura sana quede a un 30-45 % de su
// capacidad (factor de seguridad ~2,5-3, como en ingeniería): perder un apoyo la carga más, perder la mayoría
// la derrumba. (Antes 220: el modelo por niveles fallaba por fracción de daño, no por capacidad; con ese valor las
// estructuras sanas ya estaban al 100 % y cualquier redistribución rompía muros en cremallera.)
constexpr float STRESS_CAPACITY = 660.0f;
constexpr float STRESS_MIN_MASS = 24.0f;   // por debajo de esta masa no se evalúa (evita ruido)

enum class Quality : uint8_t { Low = 0, Medium = 1, High = 2, Ultra = 3 };

// Presupuestos por nivel de calidad. LOW es el DISEÑO BASE (gama baja móvil);
// los demás niveles AÑADEN presupuesto. Nunca se "recorta" desde ULTRA.
struct QualityPreset {
    const char* name;
    float simRadius;          // m: piezas desprendidas dentro de este radio -> rigid body real
    float cheapFallRadius;    // m: entre simRadius y esto -> "caída barata" cinemática; más lejos -> se re-voxeliza al instante
    int   maxBodies;          // máximo de rigid bodies activos simultáneos
    int   maxDebris;          // tamaño del pool de partículas de escombros
    int   maxDebrisPerEvent;  // partículas máximas por explosión/disparo
    float debrisRatio;        // partículas emitidas por voxel destruido (0.15 = 1 cada ~7 voxels)
    int   maxUploadsPerFrame; // mallas de chunk subidas a GPU por frame (control de spikes)
    int   minBodyVoxels;      // piezas más pequeñas -> partículas (no rigid body)
    int   maxBodyVoxels;      // piezas más grandes -> se parten por chunk
    int   maxBoxesPerBody;    // cajas de colisión por cuerpo (compound shape)
    float renderDistance;     // m
    float lodDistance;        // m: más lejos se usa la malla LOD (voxels 2x)
    float sleepRevoxelSeconds;// s dormido antes de re-voxelizar un cuerpo al mundo
                              // (a la mitad a peticion: los escombros se quedan quietos el doble
                              //  de rapido, y de paso el cuerpo fisico desaparece antes)
    int   workerThreads;      // 0 = auto (núcleos-1, acotado)
    int   maxPathExpansions;  // nodos A* por consulta (celdas de 0,5 m: 3000 eran ~27 m de radio y los bots no salían del spawn)
    bool  shadows;            // sugerencia para el host (renderer)
    float resolutionScale;    // sugerencia para el host (escala de render)
};

inline const QualityPreset& getPreset(Quality q) {
    static const QualityPreset presets[4] = {
        //  name      sim  cheap bodies debris perEv ratio upl minV maxV boxes rend  lod  sleep thr  path  shad  res
        { "LOW",     20.f, 40.f,  24,    512,   48, 0.12f, 2,  12, 6000,  12, 100.f, 32.f, 2.f, 0,  12000, false, 0.75f },
        { "MEDIUM",  35.f, 70.f,  64,   2048,  128, 0.25f, 4,   8, 12000, 20, 140.f, 48.f, 1.5f, 0, 20000, true,  0.85f },
        // Medido con el perfilador en dust2 (Intel UHD): con escombros en pantalla el frame caia
        // de 56 a 41 fps en HIGH y de 55 a 36 en ULTRA, con los MISMOS triangulos y chunks
        // visibles; lo que subia eran draw calls (210->317) y cuerpos (0->59). El coste esta en
        // el presupuesto de destruccion, no en la geometria del mapa: se recorta a la mitad.
        { "HIGH",    40.f, 110.f,  96,  2048,  200, 0.22f, 8,   6, 24000, 32, 200.f, 72.f, 2.f, 0,  20000, true,  1.00f },
        { "ULTRA",   55.f, 180.f, 160,  4096,  384, 0.32f, 16,  4, 32768, 48, 300.f, 110.f,  2.5f, 0, 24000, true,  1.00f },
    };
    return presets[static_cast<int>(q)];
}

} // namespace vx
