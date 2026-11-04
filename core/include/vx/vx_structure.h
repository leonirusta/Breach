// vxcore - StructuralAnalyzer: estabilidad estructural progresiva por rutas de carga
// ---------------------------------------------------------------------------
// Sustituye al "modelo de carga por nivel" que vivía en el solver de conectividad (sumaba soporte y masa
// de toda la estructura conectada dentro de una zona de chunks y hacía ceder el nivel más bajo: la
// frontera de la zona cortaba los muros vecinos, el daño era global por nivel y el edificio de al lado
// se venía abajo sin haber sido tocado).
//
// Pipeline (cada etapa es una función, ver .cpp):
//   explosión -> daño voxel (World::carveSphere, fuera de aquí)                 ── sistema de impacto
//     -> región alrededor del daño (celdas de ~0,5 m, escaneadas desde la        scanRegion / scanChunk
//        memoria de los chunks y saltando el vacío con la ocupación jerárquica)
//     -> LÍNEA BASE: la misma región con los voxels destruidos "repuestos"        computeBaseline
//        (ratio de cada celda ANTES del daño: lo que el autor del mapa construyó se considera estable
//        por definición; sólo cuenta la carga que el daño AÑADE a cada celda)
//     -> islas estructurales por CONTACTO REAL de voxels                          findIslands
//        (dos edificios a 1 m no comparten carga; la frontera de la región cuenta como apoyo intacto)
//     -> rutas de apoyo, de abajo arriba: pilar = apoyo debajo con ruta;         computeSupport
//        viga = contacto lateral hasta un pilar (el brazo aumenta la carga: momento)
//     -> reparto de cargas de arriba abajo (vigas -> pilares -> suelo)            distributeLoads
//     -> ratio carga/capacidad por celda                                          computeRatios
//     -> VUELCO: centro de masas de la isla frente a su polígono de apoyo; si      computeOverturn
//        se sale, multiplica el ratio de las celdas que la sostienen (ninguna
//        resistencia salva a lo que ya no está en equilibrio)
//     -> sobrecarga y deformación acumulada (racha)                                detectOverload
//     -> fallan las celdas sin ruta y las K peores sobrecargadas persistentes     collectFailures
//     -> (el motor extrae esas celdas como fragmentos; lo que queda sin conexión lo desprende la
//        conectividad) -> nueva iteración sobre las celdas de chunks que cambiaron -> hasta estabilizar
//
// Determinista: sin azar, orden fijo de recorrido. Sólo se evalúan las islas tocadas por el daño. Todo se
// ejecuta en un hilo de trabajo (applyDamage + iterate); el hilo principal sólo lee debug()/reset() cuando
// el job ha terminado.
// ---------------------------------------------------------------------------
#pragma once
#include <algorithm>
#include <cstdint>
#include <unordered_map>
#include <vector>
#include "vx_config.h"
#include "vx_math.h"

namespace vx {

class World;
struct RemovedVoxel;

// Parámetros configurables (valores por defecto = comportamiento de juego; las pruebas los ajustan).
// Todos se refieren a voxels de 25 cm; el analizador los escala al tamaño de voxel real.
struct StructParams {
    float regionRadius = 10.f;          // m (XZ) alrededor del daño que se analiza
    float capacityPerVoxel = STRESS_CAPACITY;   // masa (voxels de hormigón) que aguanta un voxel de sección de hormigón
    float minMass = STRESS_MIN_MASS;    // masa mínima de una isla para evaluarla (voxels de hormigón, escala rel^3)
    // ratios de carga (carga / capacidad): estados informativos + umbral de fallo
    float stableRatio = 0.70f;
    float highRatio = 0.90f;
    float criticalRatio = 1.00f;
    float safetyMargin = 0.08f;         // por encima de criticalRatio*(1+margen) empieza a acumular deformación
    float baseTolerance = 0.05f;   // (era 0,10; 2026-09-18)        // una celda ya sobrecargada ANTES del daño sólo falla si sube este % más
    float strainRate = 0.6f;            // deformación acumulada por iteración por unidad de exceso de ratio
    float strainToFail = 0.5f;          // deformación (x fractureThreshold del material) a la que la celda falla
    float strainRecovery = 0.25f;       // recuperación por iteración si vuelve a estar por debajo del umbral
    // Capacidad a flexión (transferencia lateral) respecto a la vertical. Calibrado para que una losa de
    // hormigón de 1 voxel (25 cm) aguante vanos de ~6 m entre pilares (la carga de todo el vano entra al
    // pilar por las 4 celdas contiguas: 24² voxels / 4 lados x brazo 1,35 ≈ 194 frente a 237 de capacidad).
    float beamFactor = 1.2f;
    // Momento flector: cada celda de viga acumula Σ(carga que pasa x brazo en celdas); la carga equivalente es
    // horiz + momentFactor * momento (crece con el cuadrado del vano, como en la realidad). Con 1,0: un vano de
    // 4 m sobre pilares queda a ~0,45, un voladizo de 4 m de losa de 25 cm a ~0,3 y uno de 12 m a ~1,8 (cae).
    // Lo que el mapa ya traía por encima de 1 lo protege la línea base; lo que el daño ALARGA (un tejado que
    // pierde un muro y queda en voladizo desde el otro) multiplica su momento y cede.
    float momentFactor = 1.0f;
    float maxSpanMeters = 24.0f;        // más lejos (brazo euclídeo) de cualquier pilar no hay viga posible: sin apoyo (cordura)
    // ESTABILIDAD / PANDEO. La capacidad a compresion de un pilar solo vale entera si esta ARRIOSTRADO:
    // rodeado de material que le impide pandear. Un tocon aislado de una celda (lo que queda cuando el
    // corte deja "un voxel sin cortar") no aguanta lo que aguantaria ese mismo hormigon dentro de un muro:
    // pandea y la masa de arriba vuelca sobre el. Sin esto, un unico voxel de hormigon sostenia un edificio
    // entero, porque a compresion pura 10x10 cm de hormigon dan de sobra para decenas de toneladas.
    // capacidad_efectiva = capV * (bucklingMin + (1-bucklingMin) * contacto_lateral_normalizado)
    float bucklingMin = 0.06f;          // fraccion de capacidad que le queda a un pilar totalmente aislado
    float archFactor = 0.5f;            // muros: la carga se transfiere lateralmente por ARCO (compresión) con esta fracción de capV
    int   maxIterations = 12;           // iteraciones seguidas SIN fallos antes de dormir (deformación que no llega a ceder)
    int   iterationIntervalFrames = 6;  // frames entre iteraciones (colapso con retardo, ~0,1 s)
    // Cuanto cede DE GOLPE. Con 64 celdas por iteracion el techo se caia a cachitos: cada iteracion
    // soltaba cuatro piedrecitas y, con el ritmo espaciado, parecia una llovizna en vez de un
    // derrumbe. Subido para que cada vez que algo cede se venga abajo un trozo de verdad.
    // Subirlos para "que caiga de golpe" es tentador, pero mas celdas por iteracion = mas material
    // arrancado por CADA impacto: con 256/0,20 un solo cohete en una pared se llevaba 14.000 voxels
    // en vez de 1.000. El tamano del derrumbe se controla con el bloque de particion, no con esto.
    int   maxOverloadFailures = 128;    // celdas sobrecargadas que pueden fallar por iteración (las peores), mínimo
    float overloadFailFraction = 0.10f; // ... o esta fracción de las celdas evaluadas si es mayor (edificios grandes)
    // PEDAZOS GRANDES, NO MIGAJAS. Una celda suelta que cede es un cubo de 80 cm cayendo por su
    // cuenta: mucha basura en el mapa y mucha fisica para nada. Un grupo de celdas contiguas tiene
    // que reunir al menos esto para desprenderse; si no llega, se queda donde esta acumulando
    // deformacion hasta que ceden tambien sus vecinas y cae un cacho de verdad.
    // (Las celdas que se quedan SIN APOYO caen igualmente: eso ya no se sostiene solo.)
    int   minGroupCells = 6;
    bool  boundaryIsGround = true;      // celdas sólidas en el borde XZ de la región = apoyo exterior intacto
    bool  touchAll = false;             // evaluar todas las islas de la región (pruebas), sin línea base
};

// La celda mas cargada de la iteracion: con esto el juego puede avisar ANTES de que algo caiga
// (crujidos y polvillo cayendo del techo donde la estructura esta al limite).
enum class CellState : uint8_t { Air = 0, Stable, High, Critical, Overloaded, Unsupported, Failed, Grounded, Skipped };

struct StructCell {
    uint16_t solid = 0;         // voxels sólidos no ancla
    uint16_t anchor = 0;        // voxels ancla (suelo, asfalto...)
    float section = 0.f;        // suma de compressiveStrength por voxel (capacidad relativa de la celda)
    // LA CAPA MAS DEBIL de la celda, ya multiplicada por el lado (misma escala que `section`), o -1 si la
    // celda no tiene cuello. Una columna aguanta lo que aguante su seccion MAS ESTRECHA, no la media: el
    // alma que deja el mazo en una pata (una capa fina entre capas llenas) desaparecia en el promedio, y
    // por 4 voxels bajaba medio tablero sin sobrecargarse (vxstructtest mesamazo).
    float sectionCuello = -1.f;
    float tensile = 0.f;        // suma de tensileStrength por voxel
    float mass = 0.f;           // suma de masa relativa (massQ/16)
    float fract = 1.f;          // fractureThreshold medio del material de la celda
    uint8_t contactPX = 0, contactPY = 0, contactPZ = 0;   // pares sólido-sólido con el vecino +X/+Y/+Z (0..255)
    uint8_t contactNY = 0;      // pares con el vecino -Y (sólido o ancla debajo)
    int32_t island = -1;
    uint32_t chunkVersion = 0;  // versión del chunk al escanear (re-escaneo perezoso)
    float load = 0.f;           // carga vertical que soporta (voxels de hormigón)
    float horiz = 0.f;          // carga que transfiere lateralmente (viga): cortante
    float moment = 0.f;         // Σ carga x brazo (celdas) que llega a esta celda por las vigas
    float ratio = 0.f;          // max(load/capV, (horiz + momentFactor*moment)/capH)
    float ownRatio = 0.f;       // ... antes de amplificarlo por la excentricidad del apoyo (ver computeOverturn)
    float strain = 0.f;         // deformación acumulada entre iteraciones
    float baseRatio = 0.f;      // ratio antes del daño (línea base); 0 = sin línea base
    int16_t pierDist = -1;      // distancia (celdas) al pilar/apoyo más cercano en su nivel; -1 = ninguno
    int16_t pierX = 0, pierZ = 0;   // celda pilar de la que cuelga (para el brazo euclídeo)
    uint8_t structural = 0;     // material portante (compresión media >= 0,2): pladur, cristal y escombro NO sostienen losas
    uint8_t grounded = 0;       // apoyo directo: ancla, y=0 o borde de región
    uint8_t tipping = 0;        // bit 0: el vuelco de la isla le ha subido el ratio. bit 1: ademas, sin el vuelco no habria fallado
    uint8_t touched = 0;        // la isla ha sido dañada (se evalúa)
    uint8_t baseUnsup = 0;      // ya no tenía ruta antes del daño (no se le culpa al daño)
    CellState state = CellState::Air;
};

// Celda que falla: caja de voxels en coordenadas de mundo.
struct FailCell { IVec3 min; IVec3 max; int32_t island; int32_t group; float ratio; uint8_t unsupported; };
// Grupo de celdas fallidas adyacentes de la misma isla = un fragmento.
struct FailGroup { int32_t island; int32_t firstCell, cellCount; Vec3 com; Vec3 tiltDir; float mass; };
// Resumen por isla evaluada (para el vuelco y la depuración).
struct IslandInfo { int32_t id; Vec3 com; Vec3 support; float mass; int32_t cells; float worstRatio; };

struct StructResult {
    std::vector<FailCell> cells;
    std::vector<FailGroup> groups;
    std::vector<IslandInfo> islands;
    int iteration = 0;
    int overloaded = 0;                // celdas acumulando deformación (aún no han fallado)
    bool stable = true;                // sin fallos NI celdas acumulando deformación: la región puede dormir
    IVec3 worstPos{0, 0, 0};   // celda mas cargada (voxels)
    float worstRatio = 0.f;    // su ratio carga/capacidad
};

// Daño pendiente de aplicar al análisis (lo produce Engine::explode; lo consume el job).
struct StructDamage {
    IVec3 mn, mx;                      // caja de los voxels eliminados
    std::vector<IVec3> damaged;        // muestra de voxels eliminados (marca islas tocadas)
    std::vector<RemovedVoxel> restored;// TODOS los voxels eliminados (línea base)
    Vec3 center;
    bool all = false;                  // evaluar toda la región sin línea base (pruebas/editores)
};

struct StructDebugCell { Vec3 center; float ratio; uint8_t state; int32_t island; float load, capacity; };
struct StructDebug {
    IVec3 regionMin, regionMax;        // voxels
    int cellVoxels = 2;
    std::vector<StructDebugCell> cells;
    std::vector<IslandInfo> islands;
    Vec3 damageCenter;
    int iteration = 0;
    int islandsEvaluated = 0, islandsSkipped = 0, cellsEvaluated = 0, cellsScanned = 0, failures = 0;
    float worstRatio = 0.f;
    double ms = 0, scanMs = 0;
};

class StructuralAnalyzer {
public:
    void setParams(const StructParams& p) { params_ = p; }
    // Incorpora un daño (abre la región si no hay análisis, la amplía si no cabe). Hilo de trabajo.
    void applyDamage(const World& world, const StructDamage& d);
    // Una iteración completa del pipeline (hilo de trabajo). Rellena `out`.
    void iterate(const World& world, StructResult& out);
    bool active() const { return !cells_.empty(); }
    void reset();
    const StructDebug& debug() const { return debug_; }
    // La lista de celdas del depurador (decenas de miles) solo se rellena si alguien la va a mirar:
    // era ~1 MB por iteracion copiandose ademas en el hilo principal, con la vista de depuracion
    // apagada. Los contadores de resumen se siguen calculando siempre.
    void setDebugCells(bool on) { debugCells_ = on; }
    int iteration() const { return iteration_; }
    const StructParams& params() const { return params_; }
    IVec3 regionMin() const { return origin_; }
    IVec3 regionMax() const { return IVec3(origin_.x + nx_ * cs_ - 1, origin_.y + ny_ * cs_ - 1, origin_.z + nz_ * cs_ - 1); }
    int cellVoxels() const { return cs_; }
    size_t memoryBytes() const { return cells_.capacity() * sizeof(StructCell) + parent_.capacity() * sizeof(int) + restored_.capacity() * 16; }

private:
    // etapas
    void begin(const World& world, const IVec3& minVoxel, const IVec3& maxVoxel);
    void scanRegion(const World& world, bool onlyDirty);
    void scanChunk(const World& world, int cx, int cy, int cz, bool onlyDirty);
    void computeBaseline(const World& world);
    void buildSolidLists();
    void findIslands();
    void markTouched();
    void computeSupport();
    void distributeLoads();
    void computeRatios();
    void computeOverturn();
    void detectOverload();
    void collectFailures(StructResult& out);
    void fillDebug(const StructResult& out);
    // utilidades
    int idx(int x, int y, int z) const { return x + nx_ * (y + ny_ * z); }
    bool inRegion(int x, int y, int z) const { return x >= 0 && y >= 0 && z >= 0 && x < nx_ && y < ny_ && z < nz_; }
    int cellOfVoxel(int vx, int vy, int vz) const;
    float capV(const StructCell& c) const {
        const float s = c.sectionCuello >= 0.f ? std::min(c.section, c.sectionCuello) : c.section;
        return (s / static_cast<float>(cs_)) * capacity_;
    }
    // Capacidad lateral: flexión (tracción) para losas y vigas; si hay material encima (muro) también puede
    // formarse un arco de compresión y vale la mayor de las dos.
    float capH(const StructCell& c) const { const float bend = (c.tensile / static_cast<float>(cs_)) * capacity_ * params_.beamFactor; return c.contactPY ? std::max(bend, capV(c) * params_.archFactor) : bend; }
    int find(int i) { while (parent_[i] != i) { parent_[i] = parent_[parent_[i]]; i = parent_[i]; } return i; }
    void unite(int a, int b) { a = find(a); b = find(b); if (a != b) { if (a < b) parent_[b] = a; else parent_[a] = b; } }
    void setupRegion(const World& world, const IVec3& minVoxel, const IVec3& maxVoxel);

    StructParams params_;
    int cs_ = 2;                 // voxels por celda (2 ó 4: divisor del chunk)
    float capacity_ = 0.f;       // capacidad por voxel de sección ya escalada al tamaño de voxel
    // CALIBRACION POR ESTRUCTURA. La capacidad nominal (STRESS_CAPACITY) se ajusto con las casas de
    // dust2, de dos plantas. Una torre de 50 m concentra en los pilares de abajo la masa de 15
    // plantas: con la misma capacidad el edificio INTACTO ya sale a 20-300 veces su capacidad. Con
    // todo tan por encima de 1, el umbral nominal no significa nada y basta con que una celda
    // recoja un 10 % mas de carga para que ceda -> efecto domino: cae el edificio entero.
    //
    // Se mide la estructura TAL COMO ESTA CONSTRUIDA (la linea base, con el dano repuesto) y se
    // escala la capacidad para que ese estado quede en ~0,8. A partir de ahi el 1,0 vuelve a
    // significar "al limite" y un boquete en una pared sube a las vecinas a 0,9, no a 60.
    float calib_ = 1.f;          // divisor de ratios (>=1)
    std::vector<float> ratioBuf_;   // buffer para el percentil de calibracion
    static constexpr float CALIB_TARGET = 0.80f;   // donde queda la estructura intacta
    float minMass_ = 0.f;
    float maxSpanCells_ = 24.f;  // brazo euclídeo máximo (celdas)
    IVec3 origin_;               // voxel mínimo de la región (múltiplo de cs_)
    int nx_ = 0, ny_ = 0, nz_ = 0;
    bool edgeGround_[4] = {false, false, false, false};   // -X, +X, -Z, +Z: el borde de la región es "exterior intacto" (no el borde del mundo)
    std::vector<StructCell> cells_;
    std::vector<int> parent_;
    std::vector<float> islandMass_;
    std::vector<uint8_t> islandTouched_;
    std::vector<uint8_t> islandSkipped_;
    // Equilibrio global por isla (vuelco): centro de masas frente al polígono de apoyo. En CELDAS.
    struct IslandTip { float mass, comX, comZ, supX, supZ, supN, dirX, dirZ, reach, ratio; };
    std::vector<IslandTip> tips_;
    std::vector<int> levelOrder_;    // índices de celdas de un nivel ordenados por pierDist descendente
    std::vector<uint8_t> solidMask_; // 1 byte por celda: sólida (para reconstruir solid_ sin tocar los 64 B de cada celda)
    std::vector<int> failedIdx_;     // celdas que han fallado en este evento (para la depuración)
    std::vector<int> solid_;         // índices de celdas sólidas (orden de índice): las etapas sólo recorren éstas
    std::vector<int> byLevel_;       // índices de celdas sólidas ordenados por (y, z, x)
    std::vector<int> levelStart_;    // ny_+1 offsets en byLevel_
    std::vector<int> bfsQ_;
    std::vector<int> failIdx_;
    std::vector<int> failGroup_;
    std::vector<IVec3> damaged_;
    std::vector<RemovedVoxel> restored_;   // pendientes de línea base
    // LA LINEA BASE DE TODA LA PARTIDA, por celda del mundo. La de cada sesion del analizador se calcula
    // reponiendo el daño de ESA sesion, y la sesion se cierra (reset) en cuanto la region queda estable.
    // Si el daño llega a ratos -una pata de la mesa, una pausa, otra pata- cada sesion nueva tomaba como
    // "lo que construyo el autor" la estructura ya dañada, y la comparacion era contra eso: tres patas
    // cortadas de una en una y el tablero seguia en el aire sobre la cuarta. Se guarda la primera base
    // de cada celda (sin escalar por la calibracion) y no se borra con reset(): vive lo que vive el mapa.
    struct BaseHist { float raw; uint8_t unsup; };
    std::unordered_map<uint64_t, BaseHist> baseHist_;
    static constexpr size_t BASE_HIST_MAX = 2000000;   // tope de cordura (~60 MB): pasado, no se apunta mas
    std::vector<uint8_t> chunkCopy_; // 32 KB: copia del chunk bajo lock
    Vec3 damageCenter_;
    bool baselineDirty_ = false;
    bool needRescan_ = false;
    int iteration_ = 0;
    int lastFailCells_ = 0;      // celdas que cedieron en la iteración anterior (el vuelco espera a que no quede ninguna)
    int cellsScanned_ = 0;
    double scanMs_ = 0;
    StructDebug debug_;
    bool debugCells_ = false;
};

} // namespace vx
