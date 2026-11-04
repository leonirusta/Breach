// vxcore - StructuralAnalyzer (ver vx_structure.h)
#include "vx/vx_structure.h"
#include "vx/vx_world.h"
#include "vx/vx_material.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <chrono>

namespace vx {

// VX_CALIB=0 apaga la calibracion por estructura (comportamiento anterior), para comparar en pruebas.
static float g_calibTarget = std::getenv("VX_CALIB") ? static_cast<float>(std::atof(std::getenv("VX_CALIB"))) : -1.f;
/// Cuantas veces la deformacion de rotura tiene que acumular un grupo PEQUEÑO de celdas antes de ceder
/// solo, sin esperar a que se le sumen vecinas (ver collectFailures). En el .cpp y no en StructParams
/// a proposito: tocar la cabecera obliga a recompilar en limpio (CLAUDE.md).
static constexpr float ESPERA_MAX_SOLO = 4.0f;
static int g_logStruct = std::getenv("VX_LOGSTRUCT") ? std::atoi(std::getenv("VX_LOGSTRUCT")) : 0;   // 1 = resumen, 2 = peores celdas

// ---------------------------------------------------------------------------
// Región y celdas
// ---------------------------------------------------------------------------
int StructuralAnalyzer::cellOfVoxel(int vx, int vy, int vz) const {
    if (vx < origin_.x || vy < origin_.y || vz < origin_.z) return -1;
    const int x = (vx - origin_.x) / cs_, y = (vy - origin_.y) / cs_, z = (vz - origin_.z) / cs_;
    if (!inRegion(x, y, z)) return -1;
    return idx(x, y, z);
}

void StructuralAnalyzer::reset() {
    cells_.clear(); cells_.shrink_to_fit();
    parent_.clear(); parent_.shrink_to_fit();
    damaged_.clear(); restored_.clear(); restored_.shrink_to_fit();
    solidMask_.clear(); solidMask_.shrink_to_fit(); failedIdx_.clear(); solid_.clear(); byLevel_.clear();
    tips_.clear(); tips_.shrink_to_fit();
    iteration_ = 0; lastFailCells_ = 0; baselineDirty_ = false; needRescan_ = false; calib_ = 1.f;
}

// Región alineada a celdas y a chunks, ampliada en XZ por regionRadius y en Y a las filas de chunks que existen.
void StructuralAnalyzer::setupRegion(const World& world, const IVec3& minVoxel, const IVec3& maxVoxel) {
    const float vs = world.voxelSize();
    const int margin = static_cast<int>(std::lround(params_.regionRadius / vs));
    IVec3 mn(std::max(0, minVoxel.x - margin), 0, std::max(0, minVoxel.z - margin));
    IVec3 mx(std::min(world.sizeX() - 1, maxVoxel.x + margin), world.sizeY() - 1, std::min(world.sizeZ() - 1, maxVoxel.z + margin));
    // altura útil: filas de chunks con algún chunk con sólidos dentro de la columna XZ de la región
    int cyMin = world.chunksY(), cyMax = -1;
    for (int cy = 0; cy < world.chunksY(); ++cy) {
        bool any = false;
        for (int cz = mn.z >> CHUNK_BITS; cz <= (mx.z >> CHUNK_BITS) && !any; ++cz)
            for (int cx = mn.x >> CHUNK_BITS; cx <= (mx.x >> CHUNK_BITS); ++cx) {
                const Chunk* c = world.chunk(cx, cy, cz);
                if (c && c->solidAtomic.load(std::memory_order_relaxed)) { any = true; break; }
            }
        if (any) { cyMin = std::min(cyMin, cy); cyMax = cy; }
    }
    if (cyMax < 0) { cyMin = 0; cyMax = 0; }
    mn.y = cyMin * CHUNK_SIZE; mx.y = std::min(world.sizeY() - 1, cyMax * CHUNK_SIZE + CHUNK_MASK);
    // PRESUPUESTO DE CELDAS. Un corte largo (un barrido de laser de 45 m) generaba una region de
    // 336x56x288 = 5,4 M de celdas y UNA sola iteracion costaba 679 ms: el hilo de trabajo se quedaba
    // clavado y se notaba como tiron. Antes que tragarse eso, se sube el tamano de celda (siempre
    // divisor del chunk: 4, 8 o 16 voxels) hasta que la region entra en el presupuesto. El analisis
    // pierde detalle en un derrumbe enorme -los fragmentos salen mas gordos- pero sigue corriendo.
    {
        const long long vx3 = static_cast<long long>(mx.x - mn.x + 1) * (mx.y - mn.y + 1) * (mx.z - mn.z + 1);
        const long long budget = 400000;   // celdas
        while (cs_ < 16 && vx3 / (static_cast<long long>(cs_) * cs_ * cs_) > budget) cs_ *= 2;
        maxSpanCells_ = std::max(1.f, params_.maxSpanMeters / (cs_ * vs));
    }
    mn.x -= mn.x % cs_; mn.y -= mn.y % cs_; mn.z -= mn.z % cs_;
    origin_ = mn;
    nx_ = (mx.x - mn.x) / cs_ + 1; ny_ = (mx.y - mn.y) / cs_ + 1; nz_ = (mx.z - mn.z) / cs_ + 1;
    // el borde de la región cuenta como apoyo intacto sólo si fuera hay mundo (no en el límite del mapa)
    edgeGround_[0] = params_.boundaryIsGround && mn.x > 0;
    edgeGround_[1] = params_.boundaryIsGround && origin_.x + nx_ * cs_ < world.sizeX();
    edgeGround_[2] = params_.boundaryIsGround && mn.z > 0;
    edgeGround_[3] = params_.boundaryIsGround && origin_.z + nz_ * cs_ < world.sizeZ();
    cells_.assign(static_cast<size_t>(nx_) * ny_ * nz_, StructCell{});
    solidMask_.assign(cells_.size(), 0);
    failedIdx_.clear();
}

void StructuralAnalyzer::begin(const World& world, const IVec3& minVoxel, const IVec3& maxVoxel) {
    const float vs = world.voxelSize();
    // la celda debe dividir al chunk (2 ó 4 voxels): así ninguna celda cruza dos chunks y se escanea desde memoria
    cs_ = (vs >= 0.2f) ? 2 : 4;   // setupRegion puede subirlo si la region no cabe en el presupuesto
    const float rel = 0.25f / vs;
    capacity_ = params_.capacityPerVoxel * rel;      // sección ~rel^2, masa ~rel^3 -> capacidad por voxel de sección ~rel
    minMass_ = params_.minMass * rel * rel * rel;
    maxSpanCells_ = std::max(1.f, params_.maxSpanMeters / (cs_ * vs));
    setupRegion(world, minVoxel, maxVoxel);
    iteration_ = 0;
    cellsScanned_ = 0;
    scanRegion(world, false);
    needRescan_ = false;
}

void StructuralAnalyzer::applyDamage(const World& world, const StructDamage& d) {
    if (d.all && !params_.touchAll) params_.touchAll = true;
    if (cells_.empty()) {
        begin(world, d.mn, d.mx);
        damaged_ = d.damaged;
        damageCenter_ = d.center;
    } else {
        iteration_ = 0;   // evento nuevo: vuelve a disponer de todas las iteraciones
        const IVec3 curMax = regionMax();
        const float vs = world.voxelSize();
        const int margin = static_cast<int>(std::lround(params_.regionRadius * 0.5f / vs));   // basta con media región de margen
        const bool fits = d.mn.x - margin >= origin_.x && d.mn.z - margin >= origin_.z && d.mx.x + margin <= curMax.x && d.mx.z + margin <= curMax.z
                       && d.mn.y >= origin_.y && d.mx.y <= curMax.y;
        if (!fits) {
            // no cabe: reconstruir con la unión (se pierde la deformación acumulada: aceptable, es un evento nuevo)
            std::vector<IVec3> all = damaged_;
            std::vector<RemovedVoxel> rest = restored_;
            const IVec3 mn(std::min(origin_.x, d.mn.x), std::min(origin_.y, d.mn.y), std::min(origin_.z, d.mn.z));
            const IVec3 mx(std::max(curMax.x, d.mx.x), std::max(curMax.y, d.mx.y), std::max(curMax.z, d.mx.z));
            begin(world, mn, mx);
            damaged_ = all; restored_ = rest;
        } else needRescan_ = true;
        damaged_.insert(damaged_.end(), d.damaged.begin(), d.damaged.end());
        damageCenter_ = (damageCenter_ + d.center) * 0.5f;
    }
    if (!params_.touchAll) { restored_.insert(restored_.end(), d.restored.begin(), d.restored.end()); baselineDirty_ = true; }
}

// Escaneo de un chunk: copia bajo lock (2 µs) y lectura directa; las celdas vacías se saltan con la ocupación.
void StructuralAnalyzer::scanChunk(const World& world, int cx, int cy, int cz, bool onlyDirty) {
    Chunk* ch = world.chunk(cx, cy, cz);
    const int bx0 = cx * CHUNK_SIZE, by0 = cy * CHUNK_SIZE, bz0 = cz * CHUNK_SIZE;
    // rango de celdas de la región dentro del chunk
    const int cxa = std::max(0, (bx0 - origin_.x) / cs_), cxb = std::min(nx_ - 1, (bx0 + CHUNK_MASK - origin_.x) / cs_);
    const int cya = std::max(0, (by0 - origin_.y) / cs_), cyb = std::min(ny_ - 1, (by0 + CHUNK_MASK - origin_.y) / cs_);
    const int cza = std::max(0, (bz0 - origin_.z) / cs_), czb = std::min(nz_ - 1, (bz0 + CHUNK_MASK - origin_.z) / cs_);
    if (cxa > cxb || cya > cyb || cza > czb) return;
    const StructCell& probe = cells_[idx(cxa, cya, cza)];
    uint32_t version = 0;
    ChunkOccupancy occ;
    bool have = false;
    if (ch && ch->solidAtomic.load(std::memory_order_acquire)) {
        if (onlyDirty && ch->versionAtomic.load(std::memory_order_acquire) == probe.chunkVersion) return;
        LockGuard g(ch->lock);
        version = ch->version;
        std::memcpy(chunkCopy_.data(), ch->vox, CHUNK_VOLUME);
        occ = ch->occ;
        have = true;
    } else if (onlyDirty && probe.chunkVersion == 0 && probe.solid == 0 && probe.anchor == 0) return;
    const uint8_t* vox = chunkCopy_.data();
    for (int z = cza; z <= czb; ++z)
    for (int y = cya; y <= cyb; ++y)
    for (int x = cxa; x <= cxb; ++x) {
        StructCell& c = cells_[idx(x, y, z)];
        const float oldStrain = c.strain, oldBase = c.baseRatio; const uint8_t oldUnsup = c.baseUnsup;
        c = StructCell{};
        c.strain = oldStrain; c.baseRatio = oldBase; c.baseUnsup = oldUnsup;
        c.chunkVersion = version;
        ++cellsScanned_;
        solidMask_[idx(x, y, z)] = 0;
        if (!have) continue;
        const int lx = origin_.x + x * cs_ - bx0, ly = origin_.y + y * cs_ - by0, lz = origin_.z + z * cs_ - bz0;
        // salto rápido: región vacía según la jerarquía (celda de 2 ó 4 voxels alineada)
        if (cs_ == 2 ? !occ.any2(lx, ly, lz) : !occ.any4(lx, ly, lz)) continue;
        int cpx = 0, cpy = 0, cpz = 0, cny = 0;
        float fract = 0.f;
        float capa[8] = {0, 0, 0, 0, 0, 0, 0, 0};   // seccion de cada capa horizontal (cs_ <= 4)
        for (int dz = 0; dz < cs_; ++dz)
        for (int dy = 0; dy < cs_; ++dy)
        for (int dx = 0; dx < cs_; ++dx) {
            const int vx = lx + dx, vy = ly + dy, vz = lz + dz;
            const uint8_t m = vox[Chunk::index(vx, vy, vz)];
            if (!m) continue;
            if (isAnchor(m)) { ++c.anchor; continue; }
            ++c.solid;
            const Material& mat = material(m);
            c.section += mat.phys.compressiveStrength;
            capa[dy] += mat.phys.compressiveStrength;
            c.tensile += mat.phys.tensileStrength;
            c.mass += mat.massQ * (1.0f / 16.0f);
            fract += mat.phys.fractureThreshold;
            // contactos con las celdas vecinas: pares sólido-sólido a través de la cara de la celda
            if (dx == cs_ - 1) { const uint8_t n = vx + 1 < CHUNK_SIZE ? vox[Chunk::index(vx + 1, vy, vz)] : world.getVoxel(bx0 + vx + 1, by0 + vy, bz0 + vz); if (n && !isAnchor(n)) ++cpx; }
            if (dz == cs_ - 1) { const uint8_t n = vz + 1 < CHUNK_SIZE ? vox[Chunk::index(vx, vy, vz + 1)] : world.getVoxel(bx0 + vx, by0 + vy, bz0 + vz + 1); if (n && !isAnchor(n)) ++cpz; }
            if (dy == cs_ - 1) { const uint8_t n = vy + 1 < CHUNK_SIZE ? vox[Chunk::index(vx, vy + 1, vz)] : world.getVoxel(bx0 + vx, by0 + vy + 1, bz0 + vz); if (n && !isAnchor(n)) ++cpy; }
            if (dy == 0)       { const uint8_t n = vy > 0 ? vox[Chunk::index(vx, vy - 1, vz)] : world.getVoxel(bx0 + vx, by0 + vy - 1, bz0 + vz); if (n) ++cny; }
        }
        c.contactPX = static_cast<uint8_t>(std::min(255, cpx));
        c.contactPY = static_cast<uint8_t>(std::min(255, cpy));
        c.contactPZ = static_cast<uint8_t>(std::min(255, cpz));
        c.contactNY = static_cast<uint8_t>(std::min(255, cny));
        if (c.solid) {
            c.fract = fract / c.solid;
            // ¿Elemento estructural? Un tabique de pladur o una vidriera no son pilares de un forjado: si la losa
            // descansa sobre ellos, para el análisis descansa sobre los muros (línea base realista) y volar el
            // tabique no la hace ceder. Lo blando sigue sosteniéndose a sí mismo.
            c.structural = (c.section / static_cast<float>(c.solid)) >= 0.2f ? 1 : 0;
            // EL CUELLO. La carga que cruza la celda de arriba abajo pasa por TODAS las capas entre la primera
            // y la ultima con material, asi que la celda aguanta lo que su capa mas estrecha de ese tramo, no
            // la media. Solo el tramo ocupado (una celda de superficie con la mitad de arriba vacia no tiene
            // cuello, tiene techo) y sin anclas (la capa fina de una celda que comparte sitio con el suelo es
            // el suelo, no una rotura). En una celda intacta todas las capas son iguales: lo mismo que antes.
            if (c.anchor == 0) {
                int lo = -1, hi = -1;
                for (int dy = 0; dy < cs_; ++dy) if (capa[dy] > 0.f) { if (lo < 0) lo = dy; hi = dy; }
                if (lo >= 0 && hi > lo) {
                    float mn = capa[lo];
                    for (int dy = lo + 1; dy <= hi; ++dy) mn = std::min(mn, capa[dy]);
                    const float cuello = mn * static_cast<float>(cs_);
                    if (cuello < c.section) c.sectionCuello = cuello;
                }
            }
            // los voxels ancla de la celda (suelo, acera) son apoyo pleno: cuentan como sección, si no la fila
            // base de todo muro (mitad suelo, mitad muro) quedaba con la mitad de capacidad y era lo primero en ceder
            c.section += static_cast<float>(c.anchor);
            c.tensile += static_cast<float>(c.anchor);
            const int wy = origin_.y + y * cs_;
            if (c.anchor) c.grounded = 1;                                   // comparte celda con suelo/asfalto
            else if (wy == 0) c.grounded = 1;
            // Borde de la region = "mundo intacto que sigue mas alla". PERO solo puede hacer de apoyo si
            // por debajo continua habiendo material: un muro que sale de la region baja hasta el suelo y si
            // sostiene; el canto de un forjado o un tejado que asoma por el borde NO. Sin esta condicion,
            // cualquier losa que llegase al borde tenia apoyo GRATIS e infinito a cualquier altura: el peso
            // del edificio se escapaba del modelo por los lados y el unico voxel que quedaba sin cortar no
            // recibia ninguna carga. Eso es lo que hacia que un voxel sostuviera un edificio entero.
            else if (cny > 0 && ((x == 0 && edgeGround_[0]) || (x == nx_ - 1 && edgeGround_[1]) || (z == 0 && edgeGround_[2]) || (z == nz_ - 1 && edgeGround_[3]))) c.grounded = 1;
            else if (cny > 0) {
                // ¿lo que hay debajo es ancla? (pilar sobre la acera)
                for (int dz = 0; dz < cs_ && !c.grounded; ++dz) for (int dx = 0; dx < cs_ && !c.grounded; ++dx) {
                    const int vx = lx + dx, vz = lz + dz;
                    const uint8_t below = ly > 0 ? vox[Chunk::index(vx, ly - 1, vz)] : world.getVoxel(bx0 + vx, by0 + ly - 1, bz0 + vz);
                    if (isAnchor(below) && vox[Chunk::index(vx, ly, vz)]) c.grounded = 1;
                }
            }
            c.state = CellState::Stable;
        } else c.strain = 0.f;
        solidMask_[idx(x, y, z)] = c.solid ? 1 : 0;
    }
}

void StructuralAnalyzer::scanRegion(const World& world, bool onlyDirty) {
    const auto t0 = std::chrono::steady_clock::now();
    if (chunkCopy_.size() != CHUNK_VOLUME) chunkCopy_.resize(CHUNK_VOLUME);
    const IVec3 mx = regionMax();
    for (int cz = origin_.z >> CHUNK_BITS; cz <= (mx.z >> CHUNK_BITS); ++cz)
    for (int cy = origin_.y >> CHUNK_BITS; cy <= (mx.y >> CHUNK_BITS); ++cy)
    for (int cx = origin_.x >> CHUNK_BITS; cx <= (mx.x >> CHUNK_BITS); ++cx)
        scanChunk(world, cx, cy, cz, onlyDirty);
    scanMs_ += std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
}

// ---------------------------------------------------------------------------
// Línea base: la región con los voxels destruidos repuestos. Lo que el autor del mapa construyó se
// considera estable por definición (aunque su ratio nominal sea > 1: un tejado de 15 m sin pilares);
// una celda sólo falla por sobrecarga si el DAÑO ha subido su ratio por encima de la base.
// ---------------------------------------------------------------------------
void StructuralAnalyzer::computeBaseline(const World& world) {
    std::vector<int>& touchedCells = failIdx_;   // reutiliza buffers
    touchedCells.clear();
    for (const RemovedVoxel& v : restored_) {
        const int ci = cellOfVoxel(v.x, v.y, v.z);
        if (ci < 0) continue;
        StructCell& c = cells_[ci];
        const Material& mat = material(v.mat);
        if (isAnchor(v.mat)) { ++c.anchor; }
        else { ++c.solid; c.section += mat.phys.compressiveStrength; c.tensile += mat.phys.tensileStrength; c.mass += mat.massQ * (1.0f / 16.0f); solidMask_[ci] = 1; if (mat.phys.compressiveStrength >= 0.2f) c.structural = 1; }
        // la linea base es la estructura INTACTA: con los voxels repuestos el cuello ya no existe
        c.sectionCuello = -1.f;
        touchedCells.push_back(ci);
    }
    std::sort(touchedCells.begin(), touchedCells.end());
    touchedCells.erase(std::unique(touchedCells.begin(), touchedCells.end()), touchedCells.end());
    // contactos aproximados de las celdas repuestas: contacto pleno con toda vecina sólida
    for (int ci : touchedCells) {
        StructCell& c = cells_[ci];
        const int x = ci % nx_, y = (ci / nx_) % ny_, z = ci / (nx_ * ny_);
        if (!c.solid) continue;
        c.state = CellState::Stable;
        if (x + 1 < nx_ && cells_[idx(x + 1, y, z)].solid) c.contactPX = 255;
        if (y + 1 < ny_ && cells_[idx(x, y + 1, z)].solid) c.contactPY = 255;
        if (z + 1 < nz_ && cells_[idx(x, y, z + 1)].solid) c.contactPZ = 255;
        if (x > 0 && cells_[idx(x - 1, y, z)].solid) cells_[idx(x - 1, y, z)].contactPX = 255;
        if (y > 0 && (cells_[idx(x, y - 1, z)].solid || cells_[idx(x, y - 1, z)].anchor)) { cells_[idx(x, y - 1, z)].contactPY = 255; c.contactNY = 255; }
        if (z > 0 && cells_[idx(x, y, z - 1)].solid) cells_[idx(x, y, z - 1)].contactPZ = 255;
        if (y + 1 < ny_ && cells_[idx(x, y + 1, z)].solid) cells_[idx(x, y + 1, z)].contactNY = 255;
        if (c.anchor || origin_.y + y * cs_ == 0) c.grounded = 1;
    }
    buildSolidLists();
    findIslands();
    markTouched();
    computeSupport();
    distributeLoads();
    computeRatios();
    // CALIBRACION: percentil alto de los ratios de la estructura intacta. Se usa un percentil (no el
    // maximo) para que una celda rara no anestesie al resto, y solo se deja SUBIR dentro de la vida de
    // la region, para que el criterio no cambie a mitad de un derrumbe.
    {
        std::vector<float>& r = ratioBuf_;
        r.clear();
        for (int i : solid_) {
            const StructCell& c = cells_[i];
            if (c.touched && c.pierDist >= 0 && c.solid) r.push_back(c.ratio);
        }
        if (r.size() >= 32) {
            // 2026-09-18: el MAXIMO, no el percentil 98. Con el percentil, las celdas de las patas de la mesa de
            // pruebas (aisladas, con la pena de pandeo) quedaban en la linea base a 48 veces su capacidad; al
            // cortar dos patas subian a 53 (+11 %) y la tolerancia del 10 % las dejaba ahi para siempre: "le
            // rompi dos patas y no cae". Con el maximo, la celda peor de la estructura intacta queda a 0,8 y
            // cualquier pata cortada dispara a las demas por encima de 1.
            const size_t k = r.size() - 1;
            std::nth_element(r.begin(), r.begin() + k, r.end());
            const float p98 = r[k];
            const float target = g_calibTarget >= 0.f ? g_calibTarget : CALIB_TARGET;
            const float want = target > 0.f ? p98 / target : 0.f;   // target 0 (VX_CALIB=0): sin calibrar
            if (want > 1.f && want > calib_) {
                const float f = want / calib_;
                calib_ = want;
                for (int i : solid_) { cells_[i].ratio /= f; cells_[i].baseRatio /= f; }   // lo ya medido, a la nueva escala
            }
        }
    }
    // El vuelco va DESPUES de la calibracion (no se calibra: es geometria) y entra en la linea base como
    // los demas ratios: lo que el mapa ya traia desequilibrado se respeta, solo cae si el daño lo empeora.
    computeOverturn();
    for (int i : solid_) {
        StructCell& c = cells_[i];
        if (!c.touched) continue;
        c.baseRatio = c.ratio;
        c.baseUnsup = c.pierDist < 0 ? 1 : 0;
        // LA BASE DE LA PRIMERA VEZ QUE SE MIRO ESTA CELDA, no la de esta sesion (ver baseHist_). Solo puede
        // BAJAR: si la estructura ya estaba peor antes del primer daño, eso lo respeta la base de ahora.
        const int x = i % nx_, y = (i / nx_) % ny_, z = i / (nx_ * ny_);
        const uint64_t clave = (static_cast<uint64_t>(origin_.x + x * cs_) & 0xFFFFF) | ((static_cast<uint64_t>(origin_.y + y * cs_) & 0xFFFF) << 20)
                             | ((static_cast<uint64_t>(origin_.z + z * cs_) & 0xFFFFF) << 36) | (static_cast<uint64_t>(cs_) << 56);
        const auto it = baseHist_.find(clave);
        if (it == baseHist_.end()) {
            if (baseHist_.size() < BASE_HIST_MAX) baseHist_.emplace(clave, BaseHist{c.baseRatio * calib_, c.baseUnsup});
        } else {
            c.baseRatio = std::min(c.baseRatio, it->second.raw / calib_);
            c.baseUnsup = std::min(c.baseUnsup, it->second.unsup);
        }
    }
    // deshacer: re-escanear los chunks que contienen voxels repuestos (y sus vecinos si el voxel toca el borde
    // del chunk: los contactos aproximados se escribieron también en la celda vecina)
    std::vector<int>& chunkKeys = levelOrder_;
    chunkKeys.clear();
    for (const RemovedVoxel& v : restored_) {
        const int cx = v.x >> CHUNK_BITS, cy = v.y >> CHUNK_BITS, cz = v.z >> CHUNK_BITS;
        chunkKeys.push_back(cx | (cy << 10) | (cz << 20));
        const int lx = v.x & CHUNK_MASK, ly = v.y & CHUNK_MASK, lz = v.z & CHUNK_MASK;
        if (lx < cs_ && cx > 0) chunkKeys.push_back((cx - 1) | (cy << 10) | (cz << 20));
        if (lx >= CHUNK_SIZE - cs_ && cx + 1 < world.chunksX()) chunkKeys.push_back((cx + 1) | (cy << 10) | (cz << 20));
        if (ly < cs_ && cy > 0) chunkKeys.push_back(cx | ((cy - 1) << 10) | (cz << 20));
        if (ly >= CHUNK_SIZE - cs_ && cy + 1 < world.chunksY()) chunkKeys.push_back(cx | ((cy + 1) << 10) | (cz << 20));
        if (lz < cs_ && cz > 0) chunkKeys.push_back(cx | (cy << 10) | ((cz - 1) << 20));
        if (lz >= CHUNK_SIZE - cs_ && cz + 1 < world.chunksZ()) chunkKeys.push_back(cx | (cy << 10) | ((cz + 1) << 20));
    }
    std::sort(chunkKeys.begin(), chunkKeys.end());
    chunkKeys.erase(std::unique(chunkKeys.begin(), chunkKeys.end()), chunkKeys.end());
    for (int k : chunkKeys) scanChunk(world, k & 1023, (k >> 10) & 1023, k >> 20, false);
    restored_.clear();
}

// ---------------------------------------------------------------------------
// Islas: componentes conexas de celdas por contacto real de voxels
// ---------------------------------------------------------------------------
// Listas compactas de celdas sólidas: la región puede tener 100-400 k celdas y sólo 3-10 k son sólidas; las
// etapas recorren estas listas (x20-50 menos trabajo por iteración que barrer la región entera).
void StructuralAnalyzer::buildSolidLists() {
    solid_.clear();
    const int n = static_cast<int>(solidMask_.size());
    const uint8_t* m = solidMask_.data();
    for (int i = 0; i < n; ++i) if (m[i]) solid_.push_back(i);
    // orden (y, z, x) por conteo (O(n), sin comparaciones): el orden natural de índice ya es (z, y, x), así que
    // agrupar por y conserva (z, x) ascendente dentro de cada nivel -> determinista
    levelStart_.assign(ny_ + 1, 0);
    for (int i : solid_) ++levelStart_[((i / nx_) % ny_) + 1];
    for (int y = 0; y < ny_; ++y) levelStart_[y + 1] += levelStart_[y];
    byLevel_.resize(solid_.size());
    std::vector<int>& fill = bfsQ_;
    fill.assign(levelStart_.begin(), levelStart_.end() - 1);
    for (int i : solid_) byLevel_[fill[(i / nx_) % ny_]++] = i;
}

void StructuralAnalyzer::findIslands() {
    const int n = static_cast<int>(cells_.size());
    parent_.resize(n);
    for (int i : solid_) parent_[i] = i;
    for (int i : solid_) {
        const StructCell& c = cells_[i];
        const int x = i % nx_, y = (i / nx_) % ny_, z = i / (nx_ * ny_);
        if (c.contactPX && x + 1 < nx_ && cells_[idx(x + 1, y, z)].solid) unite(i, idx(x + 1, y, z));
        if (c.contactPY && y + 1 < ny_ && cells_[idx(x, y + 1, z)].solid) unite(i, idx(x, y + 1, z));
        if (c.contactPZ && z + 1 < nz_ && cells_[idx(x, y, z + 1)].solid) unite(i, idx(x, y, z + 1));
    }
    // ids compactos (por orden de raíz: determinista) + masa por isla
    std::vector<int>& rootId = bfsQ_;   // reutiliza el buffer
    rootId.resize(n);
    for (int i : solid_) rootId[i] = -1;
    int nIslands = 0;
    for (int i : solid_) {
        StructCell& c = cells_[i];
        const int r = find(i);
        if (rootId[r] < 0) rootId[r] = nIslands++;
        c.island = rootId[r];
    }
    islandMass_.assign(nIslands, 0.f);
    islandTouched_.assign(nIslands, 0);
    islandSkipped_.assign(nIslands, 0);
    for (int i : solid_) islandMass_[cells_[i].island] += cells_[i].mass;
}

void StructuralAnalyzer::markTouched() {
    if (params_.touchAll) std::fill(islandTouched_.begin(), islandTouched_.end(), 1);
    static const int D[7][3] = { {0,0,0}, {1,0,0}, {-1,0,0}, {0,1,0}, {0,-1,0}, {0,0,1}, {0,0,-1} };
    for (const IVec3& v : damaged_) {
        // el voxel dañado ya es aire: tocan la isla las celdas sólidas alrededor (la suya y 6 vecinas)
        for (const auto& d : D) {
            const int ci = cellOfVoxel(v.x + d[0] * cs_, v.y + d[1] * cs_, v.z + d[2] * cs_);
            if (ci >= 0 && cells_[ci].island >= 0) islandTouched_[cells_[ci].island] = 1;
        }
    }
    for (int i = 0; i < static_cast<int>(islandTouched_.size()); ++i)
        if (islandTouched_[i] && islandMass_[i] < minMass_) { islandTouched_[i] = 0; islandSkipped_[i] = 1; }   // estructura pequeña: no se evalúa
    for (int i : solid_) {
        StructCell& c = cells_[i];
        c.touched = islandTouched_[c.island] ? 1 : 0;
        if (islandSkipped_[c.island]) c.state = CellState::Skipped;
    }
}

// ---------------------------------------------------------------------------
// Rutas de apoyo, de abajo arriba: una celda es "pilar" si está apoyada (ancla / y=0 / borde) o si descansa
// sobre una celda de su isla que a su vez tiene ruta. Desde los pilares, BFS lateral por contacto real
// (4 vecinos en el plano); cada celda recuerda de qué pilar cuelga y, si el brazo euclídeo supera
// maxSpan, no hay viga posible.
// ---------------------------------------------------------------------------
void StructuralAnalyzer::computeSupport() {
    for (int i : solid_) { StructCell& c = cells_[i]; c.pierDist = -1; c.load = c.mass; c.horiz = 0.f; c.moment = 0.f; }
    const float span2 = maxSpanCells_ * maxSpanCells_;
    for (int y = 0; y < ny_; ++y) {
        bfsQ_.clear();
        for (int li = levelStart_[y]; li < levelStart_[y + 1]; ++li) {
            const int i = byLevel_[li];
            StructCell& c = cells_[i];
            if (!c.touched) continue;
            const int x = i % nx_, z = i / (nx_ * ny_);
            bool pier = c.grounded != 0;
            if (!pier && y > 0 && c.contactNY) {
                const StructCell& b = cells_[idx(x, y - 1, z)];
                // lo de debajo sostiene si tiene ruta y es portante (o si esta celda tampoco lo es: un tabique se
                // sostiene a sí mismo, pero no sostiene el forjado que tiene encima)
                if (b.solid && b.island == c.island && b.pierDist >= 0 && (b.structural || !c.structural)) pier = true;
            }
            if (pier) { c.pierDist = 0; c.pierX = static_cast<int16_t>(x); c.pierZ = static_cast<int16_t>(z); bfsQ_.push_back(i); }
        }
        for (size_t h = 0; h < bfsQ_.size(); ++h) {
            const int i = bfsQ_[h];
            const StructCell& c = cells_[i];
            const int x = i % nx_, z = i / (nx_ * ny_);
            auto relax = [&](int j, int jx, int jz, bool contact) {
                if (!contact) return;
                StructCell& o = cells_[j];
                if (!o.solid || o.island != c.island || o.pierDist >= 0) return;
                const float ex = static_cast<float>(jx - c.pierX), ez = static_cast<float>(jz - c.pierZ);
                if (ex * ex + ez * ez > span2) return;
                o.pierDist = static_cast<int16_t>(c.pierDist + 1);
                o.pierX = c.pierX; o.pierZ = c.pierZ;
                bfsQ_.push_back(j);
            };
            if (x + 1 < nx_) relax(idx(x + 1, y, z), x + 1, z, c.contactPX != 0);
            if (x > 0)       relax(idx(x - 1, y, z), x - 1, z, cells_[idx(x - 1, y, z)].contactPX != 0);
            if (z + 1 < nz_) relax(idx(x, y, z + 1), x, z + 1, c.contactPZ != 0);
            if (z > 0)       relax(idx(x, y, z - 1), x, z - 1, cells_[idx(x, y, z - 1)].contactPZ != 0);
        }
    }
    // Colgantes (de arriba abajo): una celda sin ruta pegada por debajo a una celda con ruta cuelga de ella
    // (el muñón de un pilar cortado bajo el forjado, una lámpara, un balcón). Se trata como sumidero: no
    // cae por sí misma y su masa no se propaga (es pequeña frente a lo que la sostiene).
    for (int y = ny_ - 2; y >= 0; --y) {
        for (int li = levelStart_[y]; li < levelStart_[y + 1]; ++li) {
            const int i = byLevel_[li];
            StructCell& c = cells_[i];
            if (!c.touched || c.pierDist >= 0 || !c.contactPY) continue;
            const int x = i % nx_, z = i / (nx_ * ny_);
            const StructCell& a = cells_[idx(x, y + 1, z)];
            if (a.solid && a.island == c.island && a.pierDist >= 0) { c.pierDist = 0; c.grounded = 2; c.pierX = static_cast<int16_t>(x); c.pierZ = static_cast<int16_t>(z); }
        }
    }
}

// ---------------------------------------------------------------------------
// Distribución de cargas: de arriba abajo; en cada nivel las celdas sin pilar entregan su carga a las
// vecinas más cercanas a un pilar (viga) y los pilares la bajan a la celda inferior
// ---------------------------------------------------------------------------
void StructuralAnalyzer::distributeLoads() {
    for (int y = ny_ - 1; y >= 0; --y) {
        levelOrder_.clear();
        for (int li = levelStart_[y]; li < levelStart_[y + 1]; ++li) { const int i = byLevel_[li]; if (cells_[i].touched) levelOrder_.push_back(i); }
        if (levelOrder_.empty()) continue;
        std::stable_sort(levelOrder_.begin(), levelOrder_.end(), [&](int a, int b) { return cells_[a].pierDist > cells_[b].pierDist; });
        for (int i : levelOrder_) {
            StructCell& c = cells_[i];
            const int x = i % nx_, z = i / (nx_ * ny_);
            if (c.pierDist < 0) { c.state = CellState::Unsupported; continue; }   // sin ruta: cae (su carga no se transfiere)
            if (c.pierDist > 0) {
                // viga: reparte a las vecinas con pierDist-1 (por contacto), ponderando por sección (rigidez)
                int targets[4]; float weights[4]; int nt = 0; float wsum = 0.f;
                auto consider = [&](int j, bool contact) {
                    if (!contact) return;
                    const StructCell& o = cells_[j];
                    if (o.solid && o.island == c.island && o.pierDist == c.pierDist - 1) { const float w = std::max(0.05f, o.section); targets[nt] = j; weights[nt++] = w; wsum += w; }
                };
                if (x + 1 < nx_) consider(idx(x + 1, y, z), c.contactPX != 0);
                if (x > 0)       consider(idx(x - 1, y, z), cells_[idx(x - 1, y, z)].contactPX != 0);
                if (z + 1 < nz_) consider(idx(x, y, z + 1), c.contactPZ != 0);
                if (z > 0)       consider(idx(x, y, z - 1), cells_[idx(x, y, z - 1)].contactPZ != 0);
                c.horiz += c.load;
                // la celda destino recibe la carga y su momento: lo que ya traía esta celda más un brazo de una celda
                for (int k = 0; k < nt; ++k) { const float f = weights[k] / wsum; cells_[targets[k]].load += c.load * f; cells_[targets[k]].moment += (c.moment + c.load) * f; }
                continue;
            }
            // pilar: baja la carga en CONO (arco de descarga): 50 % recto y 12,5 % a cada celda diagonal inferior
            // con ruta. Sin esto, todo el muro sobre un boquete se colaba por la única celda del dintel y luego
            // por la columna de celdas del flanco: fallaba en cremallera a lo largo de toda la fachada.
            if (c.grounded) continue;   // sumidero
            if (y > 0) {
                int targets[5]; float weights[5]; int nt = 0; float wsum = 0.f;
                auto down = [&](int j, float w) { const StructCell& o = cells_[j]; if (o.solid && o.island == c.island && o.pierDist >= 0) { targets[nt] = j; weights[nt++] = w; wsum += w; } };
                down(idx(x, y - 1, z), 0.5f);
                if (x + 1 < nx_ && (c.contactPX || cells_[idx(x + 1, y - 1, z)].contactPY)) down(idx(x + 1, y - 1, z), 0.125f);
                if (x > 0 && (cells_[idx(x - 1, y, z)].contactPX || cells_[idx(x - 1, y - 1, z)].contactPY)) down(idx(x - 1, y - 1, z), 0.125f);
                if (z + 1 < nz_ && (c.contactPZ || cells_[idx(x, y - 1, z + 1)].contactPY)) down(idx(x, y - 1, z + 1), 0.125f);
                if (z > 0 && (cells_[idx(x, y, z - 1)].contactPZ || cells_[idx(x, y - 1, z - 1)].contactPY)) down(idx(x, y - 1, z - 1), 0.125f);
                for (int k = 0; k < nt; ++k) cells_[targets[k]].load += c.load * (weights[k] / wsum);
            }
        }
    }
}

void StructuralAnalyzer::computeRatios() {
    // Contacto lateral maximo posible de una celda: 4 caras x cs_^2 pares por cara.
    const float latMax = 4.f * static_cast<float>(cs_ * cs_);
    for (int i : solid_) {
        StructCell& c = cells_[i];
        if (!c.touched) continue;
        if (c.pierDist < 0) { c.ratio = 9.f; continue; }
        float cv = capV(c);
        const float ch = capH(c);
        // PANDEO: un pilar sin arriostramiento lateral no vale su capacidad a compresion pura. Se mide el
        // contacto real con los 4 vecinos de su nivel; aislado del todo se queda en bucklingMin.
        if (c.pierDist == 0 && latMax > 0.f) {
            const int x = i % nx_, y = (i / nx_) % ny_, z = i / (nx_ * ny_);
            float lat = static_cast<float>(c.contactPX) + static_cast<float>(c.contactPZ);
            if (x > 0) lat += static_cast<float>(cells_[idx(x - 1, y, z)].contactPX);
            if (z > 0) lat += static_cast<float>(cells_[idx(x, y, z - 1)].contactPZ);
            const float k = std::min(1.f, lat / latMax);
            cv *= params_.bucklingMin + (1.f - params_.bucklingMin) * k;
        }
        const float rv = cv > 0.f ? c.load / cv : (c.load > c.mass * 1.001f ? 9.f : 0.f);
        // pilares (pierDist 0): sólo compresión; el momento de la losa lo sufre el anillo de celdas que la
        // rodea (punzonamiento), no la cabeza del pilar
        const float eq = c.pierDist > 0 ? c.horiz + params_.momentFactor * c.moment : 0.f;   // cortante + momento
        const float rh = ch > 0.f ? eq / ch : (eq > 0.f ? 9.f : 0.f);
        c.ratio = std::max(rv, rh) / calib_;
        c.ownRatio = c.ratio;   // lo que la celda aguanta por si misma, antes de la excentricidad del apoyo
    }
}

// ---------------------------------------------------------------------------
// VUELCO: el equilibrio global de la isla (lo que faltaba en todo el modelo).
//
// Hasta aquí todo eran RESISTENCIAS: cuánta compresión aguanta un pilar, cuánto flecta una losa. Y con
// eso, un techo de 9x9 m y 124 t sobre UNA sola pata de 0,8 m salía a ratio 0,87 y se quedaba ahí tan
// tranquilo: es que no miente, 0,64 m2 de hormigón aguantan mil toneladas a compresión pura. Lo que
// pasa es que ese techo no se cae por aplastar la pata. Se cae porque su centro de masas está a 4 m del
// único sitio donde se apoya. VUELCA. Eso no es resistencia, es equilibrio, y no lo miraba nadie.
//
// Por cada isla se compara el centro de masas con su POLÍGONO DE APOYO (las celdas que tocan suelo de
// verdad; las que sólo cuelgan de arriba, grounded=2, no apoyan nada). En la dirección hacia la que se
// inclina, hasta dónde llega el apoyo es la función soporte del conjunto: exacta para la envolvente
// convexa y de una sola pasada.
//     vuelco = |com - centroide del apoyo| / alcance del apoyo en esa dirección
// Por debajo de 1 el centro de masas cae DENTRO del apoyo y esto no dice nada: hay alguna distribución
// de presiones que equilibra el momento y de eso ya se encargan la compresión y la flexión, calculadas
// antes. Por encima de 1 no hay distribución que valga, porque la resultante cae fuera. Medido en la
// mesa del mapa de pruebas: 2 patas del mismo lado dan 17 y una sola pata 22.
//
// Ese número MULTIPLICA el ratio de las celdas de apoyo, que son las que tienen que aguantar el momento
// y las que ceden. Al ceder, la conectividad suelta el resto y la pieza nace girando hacia el lado sin
// apoyo (Engine::extractJob ya calcula el vuelco de cada pieza por su cuenta): que es exactamente lo que
// se ve cuando a una mesa le quitas dos patas del mismo lado.
//
// NO se divide por la calibración: un 1,0 aquí no es "lo normal en este edificio", es geometría. A lo
// que YA nació en voladizo (el montaje del voladizo del mapa de pruebas, que como sólido rígido está
// desequilibrado desde que se construyó) lo protege la línea base igual que a los demás ratios: sólo se
// cae si el daño lo empeora.
// ---------------------------------------------------------------------------
void StructuralAnalyzer::computeOverturn() {
    const int nI = static_cast<int>(islandTouched_.size());
    for (int ci : solid_) cells_[ci].tipping = 0;
    if (nI <= 0) return;
    tips_.assign(static_cast<size_t>(nI), IslandTip{0, 0, 0, 0, 0, 0, 0, 0, 0, 0});
    for (int ci : solid_) {
        const StructCell& c = cells_[ci];
        if (!c.touched || !c.solid || c.island < 0 || c.island >= nI) continue;
        const int x = ci % nx_, z = ci / (nx_ * ny_);
        IslandTip& t = tips_[static_cast<size_t>(c.island)];
        const float m = std::max(0.01f, c.mass);
        t.mass += m; t.comX += x * m; t.comZ += z * m;
        if (c.grounded == 1) { t.supN += 1.f; t.supX += x; t.supZ += z; }
    }
    for (int i = 0; i < nI; ++i) {
        IslandTip& t = tips_[static_cast<size_t>(i)];
        // sin apoyo en el suelo no hay vuelco que calcular: eso ya no se sostiene y es cosa de la conectividad
        if (!islandTouched_[i] || t.supN <= 0.f || t.mass <= 0.f) { t.supN = 0.f; continue; }
        t.supX /= t.supN; t.supZ /= t.supN;
        const float dx = t.comX / t.mass - t.supX, dz = t.comZ / t.mass - t.supZ;
        const float e = std::sqrt(dx * dx + dz * dz);
        if (e < 1e-4f) { t.supN = 0.f; continue; }   // centrado sobre su apoyo: no vuelca
        t.dirX = dx / e; t.dirZ = dz / e; t.ratio = e;
    }
    // Hasta donde llega el apoyo en la direccion en que se inclina: la funcion soporte del conjunto,
    // que para una envolvente convexa es exacta y sale de una pasada.
    for (int ci : solid_) {
        const StructCell& c = cells_[ci];
        if (!c.touched || !c.solid || c.grounded != 1 || c.island < 0 || c.island >= nI) continue;
        IslandTip& t = tips_[static_cast<size_t>(c.island)];
        if (t.supN <= 0.f) continue;
        const int x = ci % nx_, z = ci / (nx_ * ny_);
        t.reach = std::max(t.reach, (x - t.supX) * t.dirX + (z - t.supZ) * t.dirZ);
    }
    for (int i = 0; i < nI; ++i) {
        IslandTip& t = tips_[static_cast<size_t>(i)];
        if (t.supN <= 0.f) continue;
        t.reach = std::max(0.5f, t.reach + 0.5f);          // media celda mas: la celda apoya con todo su ancho
        // SOLO CUENTA SALIRSE DEL APOYO. Mientras el centro de masas caiga DENTRO del poligono de apoyo
        // hay alguna distribucion de presiones que equilibra el momento, y de esa parte ya se encargan la
        // compresion y la flexion que se han calculado antes. Aqui solo se juzga lo que ninguna de las
        // dos puede salvar: que la resultante caiga FUERA del apoyo.
        //
        // Esta puerta es lo que separa el caso del usuario de un falso derrumbe. Sin ella, cualquier daño
        // asimetrico (un boquete en un muro mueve el centroide del apoyo unos centimetros) subia un
        // 15-60 % la presion en TODOS los apoyos y, como la linea base solo tolera un 10 %, un solo
        // cohete tiraba un edificio entero. Medido: con la puerta, 1 cohete deja el edificio al 96,8 %;
        // sin ella, al 0,6 %.
        if (t.ratio <= t.reach) t.supN = 0.f;
        if (g_logStruct >= 2)
            std::fprintf(stderr, "    [vuelco] isla %d: apoyos %.0f, excentricidad %.2f celdas, alcance %.2f -> %s\n",
                         i, t.supN, t.ratio, t.reach, t.supN > 0.f ? "VUELCA" : "el centro de masas cae dentro del apoyo");
    }
    // El momento cae sobre el apoyo: MULTIPLICA su ratio de compresion, no lo sustituye. Que sea un
    // producto importa: un forjado de 25 cm con 9 m volando sobre dos pilares no tumba los pilares, se
    // PARTE por ellos (de eso ya se encarga la flexion de la losa, que corre antes). La excentricidad
    // solo derriba el apoyo cuando ademas va cargado.
    for (int ci : solid_) {
        StructCell& c = cells_[ci];
        if (!c.touched || !c.solid || c.grounded != 1 || c.island < 0 || c.island >= nI) continue;
        IslandTip& t = tips_[static_cast<size_t>(c.island)];
        if (t.supN <= 0.f) continue;
        // Cuanto se sale: 2 = el centro de masas esta al doble de lejos de lo que alcanza el apoyo.
        // CRECE MAS QUE LINEAL (potencia 1,5). Lineal, un vuelco claro sobre un apoyo macizo no rompia: la
        // mesa con tres patas cortadas vuelca a 8,6 veces el alcance de la que queda, pero esa pata de
        // hormigon iba a 0,13 y se quedaba en 1,15, justo encima del umbral; acumulaba deformacion a paso
        // de tortuga y el tablero seguia en el aire hasta que un disparo traia daño nuevo. Un desplome leve
        // (1,2 veces el alcance) apenas cambia: 1,31 en vez de 1,2.
        const float fuera = t.ratio / t.reach;
        c.ratio *= std::min(64.f, fuera * std::sqrt(fuera));
        // VUELCO CLARO: CEDE SIEMPRE. El producto solo tumba el apoyo si ademas iba cargado, y una pata de
        // hormigon entera va casi de vacio: a 20 cm (celdas de 40 cm) la mesa del mapa de pruebas sobre UNA
        // pata vuelca a 3,5 veces su alcance, x6,6, y la pata se quedaba en 0,17-0,76. Medido en partida
        // (2026-09-21): tres patas cortadas a mazazos y el tablero en el aire. Con el centro de masas al
        // doble de lo que alcanza el apoyo no hay resistencia que valga: no se aplasta, se tumba. Se le da
        // al apoyo un ratio de rotura que crece con lo que se sale. Lo que ya nacio asi lo sigue guardando
        // la linea base (su baseRatio sale igual de alto).
        if (fuera >= 2.f)
            c.ratio = std::max(c.ratio, params_.criticalRatio * (1.0f + params_.safetyMargin) * fuera);
        c.tipping = 1;
    }
}

// ---------------------------------------------------------------------------
// Sobrecarga y deformación acumulada (racha: una sobrecarga transitoria no rompe). El umbral de cada
// celda es el mayor entre el nominal y su ratio de línea base (+ tolerancia): el daño tiene que EMPEORAR
// la celda para que falle.
// ---------------------------------------------------------------------------
void StructuralAnalyzer::detectOverload() {
    const float failRatio = params_.criticalRatio * (1.0f + params_.safetyMargin);
    for (int i : solid_) {
        StructCell& c = cells_[i];
        if (!c.touched) continue;
        if (c.state == CellState::Unsupported) {
            if (c.baseUnsup) { c.state = CellState::Skipped; c.ratio = 0.f; }   // ya flotaba antes: no es culpa del daño
            continue;
        }
        const float thr = std::max(failRatio, c.baseRatio * (1.0f + params_.baseTolerance));
        // Una celda que ya se rompia por si sola no espera al turno del vuelco: cae por el camino normal
        // (si no, el aplazamiento se las quitaba al derrumbe y el edificio se quedaba a medio caer). Pero
        // sigue marcada como apoyo en vuelco (bit 0), que es lo que la libra del filtro de grupos
        // pequeños: la ultima pata de una mesa es UNA celda, y ese filtro se la comia aunque fuese a
        // ratio 119.
        if (c.tipping && c.ownRatio <= thr) c.tipping = 3;
        if (c.ratio > thr) {
            c.strain += (c.ratio - thr) * params_.strainRate;
            c.state = CellState::Overloaded;
        } else {
            c.strain = std::max(0.f, c.strain - params_.strainRecovery);
            c.state = c.grounded ? CellState::Grounded : (c.ratio > params_.criticalRatio ? CellState::Critical : (c.ratio > params_.highRatio ? CellState::High : CellState::Stable));
        }
    }
}

// ---------------------------------------------------------------------------
// Fallos: todas las celdas sin ruta + las K peores sobrecargadas con deformación suficiente. Se agrupan
// las adyacentes de la misma isla (un fragmento por grupo) con su centro de masas y dirección de vuelco.
// ---------------------------------------------------------------------------
void StructuralAnalyzer::collectFailures(StructResult& out) {
    failIdx_.clear();
    std::vector<int>& over = levelOrder_;
    over.clear();
    std::vector<int> vuelco;
    for (int ci : solid_) {
        StructCell& c = cells_[ci];
        if (!c.touched) continue;
        if (c.state == CellState::Unsupported) failIdx_.push_back(ci);
        else if (c.state == CellState::Overloaded && c.strain >= params_.strainToFail * c.fract) {
            if (c.tipping & 2) vuelco.push_back(ci); else over.push_back(ci);
        }
    }
    // EL VUELCO ES EL ULTIMO RECURSO. Mientras siga cayendo algo por resistencia se deja terminar: la
    // losa se desgarra alrededor de los pilares (punzonamiento) y muy a menudo lo que queda ya esta
    // equilibrado encima de ellos, que es justo lo que se quiere (el pilar en pie con su capitel, no un
    // derrumbe total por el camino). Solo cuando una iteracion entera no rompe NADA y el centro de masas
    // sigue fuera del apoyo se acepta que aquello no se sostiene y cede el apoyo.
    // La condicion mira la iteracion ANTERIOR, no `over`: aqui `over` puede venir llena de celdas que
    // luego se descartan por el filtro de grupos pequeños, y entonces el vuelco no llegaba nunca.
    if (lastFailCells_ == 0) over.insert(over.end(), vuelco.begin(), vuelco.end());
    // las peores primero (ratio desc, índice asc): determinista
    std::sort(over.begin(), over.end(), [&](int a, int b) { return cells_[a].ratio != cells_[b].ratio ? cells_[a].ratio > cells_[b].ratio : a < b; });
    if (g_logStruct >= 2) {
        for (size_t k = 0; k < over.size() && k < 5; ++k) {
            const int ci = over[k]; const StructCell& c = cells_[ci];
            const int x = ci % nx_, y = (ci / nx_) % ny_, z = ci / (nx_ * ny_);
            std::fprintf(stderr, "    [cell] vox(%d,%d,%d) ratio %.2f base %.2f load %.1f horiz %.1f mom %.0f capV %.0f capH %.0f pier %d gnd %d solid %d strain %.2f\n",
                         origin_.x + x * cs_, origin_.y + y * cs_, origin_.z + z * cs_, c.ratio, c.baseRatio, c.load, c.horiz, c.moment, capV(c), capH(c), c.pierDist, c.grounded, c.solid, c.strain);
        }
        for (size_t k = 0; k < failIdx_.size() && k < 3; ++k) {
            const int ci = failIdx_[k]; const StructCell& c = cells_[ci];
            const int x = ci % nx_, y = (ci / nx_) % ny_, z = ci / (nx_ * ny_);
            std::fprintf(stderr, "    [unsup] vox(%d,%d,%d) solid %d island %d contacts px%d py%d pz%d ny%d base %d\n", origin_.x + x * cs_, origin_.y + y * cs_, origin_.z + z * cs_, c.solid, c.island, c.contactPX, c.contactPY, c.contactPZ, c.contactNY, c.baseUnsup);
        }
    }
    // la peor celda de la iteracion, para el aviso previo (crujidos): la mas cargada de las que
    // aun aguantan, no las que ya han fallado
    out.worstRatio = 0.f;
    for (int ci : solid_) {
        const StructCell& c = cells_[ci];
        if (!c.touched || !c.solid || c.state == CellState::Failed) continue;
        if (c.ratio > out.worstRatio) {
            out.worstRatio = c.ratio;
            const int x = ci % nx_, y = (ci / nx_) % ny_, z = ci / (nx_ * ny_);
            out.worstPos = IVec3(origin_.x + x * cs_, origin_.y + y * cs_, origin_.z + z * cs_);
        }
    }
    int touchedCount = 0;
    for (int i : solid_) if (cells_[i].touched) ++touchedCount;
    const int maxFail = std::max(params_.maxOverloadFailures, static_cast<int>(touchedCount * params_.overloadFailFraction));
    if (static_cast<int>(over.size()) > maxFail) over.resize(static_cast<size_t>(maxFail));
    failIdx_.insert(failIdx_.end(), over.begin(), over.end());
    std::sort(failIdx_.begin(), failIdx_.end());
    lastFailCells_ = 0;
    if (failIdx_.empty()) return;

    // agrupar adyacentes (6 vecinos) de la misma isla
    failGroup_.assign(failIdx_.size(), -1);
    std::vector<int>& q = bfsQ_;
    int nGroups = 0;
    auto posOf = [&](int ci) -> int { const auto it = std::lower_bound(failIdx_.begin(), failIdx_.end(), ci); return (it != failIdx_.end() && *it == ci) ? static_cast<int>(it - failIdx_.begin()) : -1; };
    for (size_t s = 0; s < failIdx_.size(); ++s) {
        if (failGroup_[s] >= 0) continue;
        const int g = nGroups++;
        q.clear(); q.push_back(static_cast<int>(s)); failGroup_[s] = g;
        for (size_t h = 0; h < q.size(); ++h) {
            const int ci = failIdx_[q[h]];
            const int x = ci % nx_, y = (ci / nx_) % ny_, z = ci / (nx_ * ny_);
            static const int D[6][3] = { {1,0,0}, {-1,0,0}, {0,1,0}, {0,-1,0}, {0,0,1}, {0,0,-1} };
            for (const auto& d : D) {
                const int nx = x + d[0], ny = y + d[1], nz = z + d[2];
                if (!inRegion(nx, ny, nz)) continue;
                const int nj = idx(nx, ny, nz);
                const int p = posOf(nj);
                if (p < 0 || failGroup_[p] >= 0 || cells_[nj].island != cells_[ci].island) continue;
                failGroup_[p] = g; q.push_back(p);
            }
        }
    }
    // Se descartan los grupos pequenos: sus celdas vuelven a "sobrecargadas" y esperan a que caiga
    // el trozo entero. Un grupo que ya no tiene apoyo se salva del filtro (esta flotando).
    if (params_.minGroupCells > 1 && nGroups > 0) {
        std::vector<int> tam(static_cast<size_t>(nGroups), 0);
        std::vector<uint8_t> flota(static_cast<size_t>(nGroups), 0);
        for (size_t s = 0; s < failIdx_.size(); ++s) {
            const int g = failGroup_[s];
            ++tam[static_cast<size_t>(g)];
            // ...y tampoco a lo que cede por vuelco: la base de un pilar son 4 celdas y el filtro de
            // "pedazos grandes" se las comia, asi que el pilar aguantaba eternamente acumulando
            // deformacion mientras el techo de 124 t le colgaba de lado.
            const StructCell& fc = cells_[failIdx_[s]];
            if (fc.state == CellState::Unsupported || fc.tipping) flota[static_cast<size_t>(g)] = 1;
            // ...NI A LO QUE LLEVA DEMASIADO ESPERANDO. "Esperar a que caiga el trozo entero" es eterno si
            // alrededor todo es macizo: el alma que el mazo deja en una pata (2-4 voxels, en el centro,
            // donde no llega) iba al 264 % de su capacidad con la deformacion subiendo sin parar -5,6,
            // 7,5, 10,3...- y no cedia nunca porque es UNA celda y sus vecinas no se sobrecargan. Asi se
            // quedaba el tablero de una mesa en el aire sobre una pata sana y tres hilos (vxstructtest
            // mesamazo). Un grupo pequeño puede esperar compañia, pero no para siempre: pasado este
            // multiplo de la deformacion que lo rompe, cede solo. Una sobrecarga leve no llega aqui antes
            // de que la region se duerma; esto solo suelta lo que esta brutalmente pasado de rosca.
            if (fc.strain >= params_.strainToFail * fc.fract * ESPERA_MAX_SOLO) flota[static_cast<size_t>(g)] = 1;
        }
        std::vector<int> keep;
        keep.reserve(failIdx_.size());
        std::vector<int> keepG;
        keepG.reserve(failIdx_.size());
        for (size_t s = 0; s < failIdx_.size(); ++s) {
            const int g = failGroup_[s];
            if (tam[static_cast<size_t>(g)] >= params_.minGroupCells || flota[static_cast<size_t>(g)]) {
                keep.push_back(failIdx_[s]);
                keepG.push_back(g);
            }
        }
        if (keep.size() != failIdx_.size()) {
            // renumerar los grupos que sobreviven
            std::vector<int> mapa(static_cast<size_t>(nGroups), -1);
            int ng = 0;
            for (int g : keepG) if (mapa[static_cast<size_t>(g)] < 0) mapa[static_cast<size_t>(g)] = ng++;
            failIdx_.swap(keep);
            failGroup_.assign(failIdx_.size(), -1);
            for (size_t s = 0; s < failIdx_.size(); ++s) failGroup_[s] = mapa[static_cast<size_t>(keepG[s])];
            nGroups = ng;
        }
    }
    if (nGroups == 0 || failIdx_.empty()) return;
    out.groups.assign(nGroups, FailGroup{});
    for (int g = 0; g < nGroups; ++g) { out.groups[g].firstCell = -1; out.groups[g].cellCount = 0; out.groups[g].island = -1; }
    for (size_t s = 0; s < failIdx_.size(); ++s) {
        const int ci = failIdx_[s];
        StructCell& c = cells_[ci];
        const int x = ci % nx_, y = (ci / nx_) % ny_, z = ci / (nx_ * ny_);
        FailCell f;
        f.min = IVec3(origin_.x + x * cs_, origin_.y + y * cs_, origin_.z + z * cs_);
        f.max = IVec3(f.min.x + cs_ - 1, f.min.y + cs_ - 1, f.min.z + cs_ - 1);
        f.island = c.island; f.group = failGroup_[s]; f.ratio = c.ratio; f.unsupported = c.state == CellState::Unsupported ? 1 : 0;
        FailGroup& G = out.groups[f.group];
        G.island = c.island;
        ++G.cellCount;
        G.com += Vec3((x + 0.5f) * cs_ + origin_.x, (y + 0.5f) * cs_ + origin_.y, (z + 0.5f) * cs_ + origin_.z) * std::max(0.01f, c.mass);
        G.mass += std::max(0.01f, c.mass);
        out.cells.push_back(f);
        c.state = CellState::Failed;
        c.solid = 0;   // deja de contar en la siguiente iteración (el motor la extrae)
        c.strain = 0.f;
        solidMask_[ci] = 0;
        failedIdx_.push_back(ci);
        damaged_.push_back(IVec3(f.min.x, f.min.y, f.min.z));   // la isla sigue "tocada" en la siguiente iteración
    }
    // reordenar por grupo para que las celdas de cada grupo sean contiguas
    std::stable_sort(out.cells.begin(), out.cells.end(), [](const FailCell& a, const FailCell& b) { return a.group < b.group; });
    int first = 0;
    for (int g = 0; g < nGroups; ++g) { out.groups[g].firstCell = first; first += out.groups[g].cellCount; }
    for (FailGroup& G : out.groups) {
        if (G.mass > 0.f) G.com = G.com / G.mass;
        // dirección de vuelco: del apoyo de la isla hacia el centro del grupo; si no hay apoyo, alejándose del daño
        Vec3 sup; bool has = false;
        for (const IslandInfo& I : out.islands) if (I.id == G.island) { sup = I.support; has = true; break; }
        Vec3 d = has ? Vec3(G.com.x - sup.x, 0.f, G.com.z - sup.z) : Vec3(G.com.x - damageCenter_.x, 0.f, G.com.z - damageCenter_.z);
        if (length2(d) < 0.25f) d = Vec3(G.com.x - damageCenter_.x, 0.f, G.com.z - damageCenter_.z);
        G.tiltDir = length2(d) > 1e-6f ? normalize(d) : Vec3(1, 0, 0);
    }
    lastFailCells_ = static_cast<int>(out.cells.size());
    // si se acumulan demasiados voxels dañados (iteraciones largas) se compacta la lista
    if (damaged_.size() > 4096) damaged_.erase(damaged_.begin(), damaged_.begin() + static_cast<long>(damaged_.size() - 2048));
}

void StructuralAnalyzer::fillDebug(const StructResult& out) {
    debug_.cellVoxels = cs_;
    debug_.regionMin = origin_; debug_.regionMax = regionMax();
    debug_.cells.clear();
    debug_.islands = out.islands;
    debug_.damageCenter = damageCenter_;
    debug_.iteration = iteration_;
    debug_.islandsEvaluated = 0; debug_.islandsSkipped = 0; debug_.cellsEvaluated = 0; debug_.worstRatio = 0.f;
    debug_.cellsScanned = cellsScanned_;
    for (size_t i = 0; i < islandTouched_.size(); ++i) { if (islandTouched_[i]) ++debug_.islandsEvaluated; if (islandSkipped_[i]) ++debug_.islandsSkipped; }
    auto emit = [&](int ci) {
        const StructCell& c = cells_[ci];
        if (c.state == CellState::Air) return;
        if (!debugCells_) {
            // sin vista de depuracion no se guarda la celda, solo se acumulan los contadores
            if (c.touched && c.solid) { ++debug_.cellsEvaluated; debug_.worstRatio = std::max(debug_.worstRatio, c.ratio); }
            return;
        }
        if (!c.touched && c.state != CellState::Failed && c.state != CellState::Skipped) return;
        const int x = ci % nx_, y = (ci / nx_) % ny_, z = ci / (nx_ * ny_);
        StructDebugCell d;
        d.center = Vec3(origin_.x + (x + 0.5f) * cs_, origin_.y + (y + 0.5f) * cs_, origin_.z + (z + 0.5f) * cs_);   // en voxels; el host escala
        d.ratio = c.ratio; d.state = static_cast<uint8_t>(c.state); d.island = c.island; d.load = c.load; d.capacity = capV(c);
        debug_.cells.push_back(d);
        if (c.touched && c.solid) { ++debug_.cellsEvaluated; debug_.worstRatio = std::max(debug_.worstRatio, c.ratio); }
    };
    for (int ci : solid_) emit(ci);
    for (int ci : failedIdx_) if (!solidMask_[ci]) emit(ci);
}

// ---------------------------------------------------------------------------
// Iteración completa
// ---------------------------------------------------------------------------
void StructuralAnalyzer::iterate(const World& world, StructResult& out) {
    const auto t0 = std::chrono::steady_clock::now();
    out.cells.clear(); out.groups.clear(); out.islands.clear();
    out.iteration = iteration_; out.stable = true;
    if (cells_.empty()) return;
    scanMs_ = 0;
    double stage[10] = {0}; int sk = 0;
    auto lap = [&](const std::chrono::steady_clock::time_point& t) { const auto now = std::chrono::steady_clock::now(); stage[sk++] = std::chrono::duration<double, std::milli>(now - t).count(); return now; };
    auto tl = std::chrono::steady_clock::now();
    if (iteration_ > 0 || needRescan_) { scanRegion(world, true); needRescan_ = false; }
    tl = lap(tl);
    if (baselineDirty_) { computeBaseline(world); baselineDirty_ = false; }
    tl = lap(tl);
    buildSolidLists(); tl = lap(tl);
    findIslands(); tl = lap(tl);
    markTouched(); tl = lap(tl);
    computeSupport(); tl = lap(tl);
    distributeLoads(); tl = lap(tl);
    computeRatios();
    computeOverturn();
    detectOverload(); tl = lap(tl);
    if (g_logStruct >= 2) std::fprintf(stderr, "    [stages] rescan %.2f base %.2f lists %.2f islands %.2f touched %.2f support %.2f loads %.2f ratios %.2f ms\n", stage[0], stage[1], stage[2], stage[3], stage[4], stage[5], stage[6], stage[7]);
    // resumen por isla evaluada: centro de masas y centroide de sus apoyos (para el vuelco)
    {
        const int nI = static_cast<int>(islandTouched_.size());
        std::vector<IslandInfo> info(nI);
        std::vector<float> supW(nI, 0.f);
        for (int i = 0; i < nI; ++i) { info[i] = IslandInfo{i, Vec3(), Vec3(), 0.f, 0, 0.f}; }
        for (int ci : solid_) {
            const StructCell& c = cells_[ci];
            if (!c.touched) continue;
            const int x = ci % nx_, y = (ci / nx_) % ny_, z = ci / (nx_ * ny_);
            const Vec3 p(origin_.x + (x + 0.5f) * cs_, origin_.y + (y + 0.5f) * cs_, origin_.z + (z + 0.5f) * cs_);
            IslandInfo& I = info[c.island];
            I.com += p * c.mass; I.mass += c.mass; ++I.cells; I.worstRatio = std::max(I.worstRatio, c.ratio);
            if (c.pierDist == 0 && c.state != CellState::Unsupported) { const float w = std::max(0.01f, c.load); I.support += p * w; supW[c.island] += w; }
        }
        for (int i = 0; i < nI; ++i) {
            if (!islandTouched_[i] || info[i].cells == 0) continue;
            if (info[i].mass > 0.f) info[i].com = info[i].com / info[i].mass;
            info[i].support = supW[i] > 0.f ? info[i].support / supW[i] : info[i].com;
            out.islands.push_back(info[i]);
        }
    }
    collectFailures(out);
    out.overloaded = 0;
    for (int i : solid_) { const StructCell& c = cells_[i]; if (c.solid && c.touched && c.state == CellState::Overloaded) ++out.overloaded; }
    out.stable = out.cells.empty() && out.overloaded == 0;
    ++iteration_;
    fillDebug(out);
    debug_.failures = static_cast<int>(out.cells.size());
    debug_.scanMs = scanMs_;
    debug_.ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
    if (g_logStruct) {
        int over = 0, unsup = 0, high = 0;
        for (int i : solid_) { const StructCell& c = cells_[i]; if (!c.touched || !c.solid) continue; if (c.state == CellState::Overloaded) ++over; if (c.state == CellState::Unsupported) ++unsup; if (c.state == CellState::High || c.state == CellState::Critical) ++high; }
        std::fprintf(stderr, "[struct] it=%d region %dx%dx%d celdas (%d escaneadas), islas evaluadas %d (saltadas %d), celdas %d, alta carga %d, sobrecargadas %d, sin apoyo %d, fallan %zu en %zu grupos, peor ratio %.2f, %.2f ms (escaneo %.2f)\n",
                     iteration_, nx_, ny_, nz_, cellsScanned_, debug_.islandsEvaluated, debug_.islandsSkipped, debug_.cellsEvaluated, high, over, unsup, out.cells.size(), out.groups.size(), debug_.worstRatio, debug_.ms, scanMs_);
    }
}

} // namespace vx
