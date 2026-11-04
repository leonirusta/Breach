// vxcore - Conectividad jerárquica (sólo conectividad: el modelo de carga es el StructuralAnalyzer)
#include "vx/vx_connectivity.h"
#include "vx/vx_material.h"
#include <cstring>
#include <algorithm>

namespace vx {

// ---------------------------------------------------------------------------
// Nivel 0: etiquetado de componentes conexas de un chunk (BFS, 6-vecinos)
// ---------------------------------------------------------------------------
void labelChunk(const uint8_t* vox, const uint8_t* padded, int worldY0, LabelScratch& scratch, ChunkConn& out) {
    uint8_t* label = scratch.label.data();
    uint16_t* stack = scratch.stack.data();
    std::memset(label, 0, CHUNK_VOLUME);
    std::memset(out.border, 0, sizeof(out.border));
    std::memset(out.compVoxels, 0, sizeof(out.compVoxels));
    std::memset(out.compAnchored, 0, sizeof(out.compAnchored));

    constexpr int S = PAD_SIZE;
    auto padAt = [&](int x, int y, int z) -> uint8_t { return padded[(x + 1) + (y + 1) * S + (z + 1) * S * S]; };

    int nextLabel = 1;
    bool overflow = false;
    for (int start = 0; start < CHUNK_VOLUME; ++start) {
        if (!vox[start] || label[start] || isAnchor(vox[start])) continue;
        uint8_t L;
        if (nextLabel < OVERFLOW_LABEL) L = static_cast<uint8_t>(nextLabel++);
        else { L = OVERFLOW_LABEL; overflow = true; }

        int sp = 0;
        stack[sp++] = static_cast<uint16_t>(start);
        label[start] = L;
        uint32_t count = 0;
        bool anchored = false;
        while (sp) {
            const int i = stack[--sp];
            ++count;
            const int x = i & CHUNK_MASK, y = (i >> CHUNK_BITS) & CHUNK_MASK, z = i >> (2 * CHUNK_BITS);
            if (worldY0 + y == 0) anchored = true;
            // vecinos: sólidos no-ancla se expanden; anclas anclan
            auto visit = [&](int j) {
                const uint8_t nm = vox[j];
                if (!nm) return;
                if (isAnchor(nm)) { anchored = true; return; }
                if (!label[j]) { label[j] = L; stack[sp++] = static_cast<uint16_t>(j); }
            };
            if (x > 0) visit(i - 1);                 else if (padded && isAnchor(padAt(-1, y, z))) anchored = true;
            if (x < CHUNK_MASK) visit(i + 1);        else if (padded && isAnchor(padAt(CHUNK_SIZE, y, z))) anchored = true;
            if (y > 0) visit(i - CHUNK_SIZE);        else if (padded && isAnchor(padAt(x, -1, z))) anchored = true;
            if (y < CHUNK_MASK) visit(i + CHUNK_SIZE); else if (padded && isAnchor(padAt(x, CHUNK_SIZE, z))) anchored = true;
            if (z > 0) visit(i - CHUNK_AREA);        else if (padded && isAnchor(padAt(x, y, -1))) anchored = true;
            if (z < CHUNK_MASK) visit(i + CHUNK_AREA); else if (padded && isAnchor(padAt(x, y, CHUNK_SIZE))) anchored = true;
        }
        out.compVoxels[L] += count;
        if (anchored) out.setAnchored(L);
    }
    out.numComp = static_cast<uint8_t>(overflow ? OVERFLOW_LABEL : nextLabel - 1);
    if (overflow) out.setAnchored(OVERFLOW_LABEL); // el cubo de desborde se trata como estático

    // Etiquetas de borde: (a, b) = ejes tangenciales en orden (y,z) | (x,z) | (x,y)
    for (int b = 0; b < CHUNK_SIZE; ++b)
        for (int a = 0; a < CHUNK_SIZE; ++a) {
            const int i = a + b * CHUNK_SIZE;
            out.border[FACE_NX][i] = label[Chunk::index(0, a, b)];
            out.border[FACE_PX][i] = label[Chunk::index(CHUNK_MASK, a, b)];
            out.border[FACE_NY][i] = label[Chunk::index(a, 0, b)];
            out.border[FACE_PY][i] = label[Chunk::index(a, CHUNK_MASK, b)];
            out.border[FACE_NZ][i] = label[Chunk::index(a, b, 0)];
            out.border[FACE_PZ][i] = label[Chunk::index(a, b, CHUNK_MASK)];
        }
}

// ---------------------------------------------------------------------------
// Pares de etiquetas a través de una cara (deduplicados)
// ---------------------------------------------------------------------------
void computeFaceEdges(const ChunkConn& c, const ChunkConn& n, int face, std::vector<uint16_t>& outPairs) {
    outPairs.clear();
    const uint8_t* A = c.border[face];
    const uint8_t* B = n.border[face ^ 1];
    thread_local std::vector<uint8_t> seen(65536, 0);
    for (int i = 0; i < CHUNK_AREA; ++i) {
        const uint8_t la = A[i], lb = B[i];
        if (!la || !lb) continue;
        const uint16_t key = static_cast<uint16_t>((la << 8) | lb);
        if (seen[key]) continue;
        seen[key] = 1;
        outPairs.push_back(key);
    }
    for (uint16_t k : outPairs) seen[k] = 0;
}

// ---------------------------------------------------------------------------
// Nivel 1: grafo global con Union-Find
// ---------------------------------------------------------------------------
void ConnectivitySolver::solve(const World& world, std::vector<DetachedGroup>& outGroups) {
    outGroups.clear();
    const int n = world.numChunkSlots();
    base_.assign(n + 1, 0);

    // Pase 1: nodos. Los chunks sin componentes (la mayoría en un mapa grande: cielo, suelo puro) se saltan
    // leyendo la copia atómica `compCount` SIN tomar el lock; sólo los que tienen componentes se leen bajo lock.
    struct Info { uint8_t numComp; bool fresh; uint32_t connVersion; bool pristine; bool damaged; };
    thread_local std::vector<Info> info;
    info.assign(n, Info{0, false, 0, true, false});
    int total = 0;
    skippedNoLock_ = 0;
    for (int i = 0; i < n; ++i) {
        Chunk* c = world.chunkAt(i);
        base_[i] = total;
        if (!c) continue;
        if (c->compCount.load(std::memory_order_acquire) == 0 && !c->jobQueued.load(std::memory_order_acquire)) {
            // sin componentes y sin job pendiente: fresh si el etiquetado está al día. Todo sin lock: los tres
            // contadores son espejos atómicos que escribe quien edita/etiqueta el chunk.
            const uint32_t lv = c->labeledVersion.load(std::memory_order_acquire);
            info[i].fresh = lv == 0 ? (c->solidAtomic.load(std::memory_order_relaxed) == 0)
                                    : (lv == c->versionAtomic.load(std::memory_order_acquire) && c->extracting.load(std::memory_order_acquire) == 0);
            ++skippedNoLock_;
            continue;
        }
        LockGuard g(c->lock);
        if (!c->conn.valid) { info[i].fresh = (c->solidCount == 0); continue; }
        info[i].numComp = c->conn.numComp;
        info[i].connVersion = c->conn.version;
        info[i].pristine = c->conn.pristine;
        info[i].damaged = c->conn.damaged;
        info[i].fresh = (c->conn.version == c->version) && !c->jobQueued.load(std::memory_order_acquire) && c->extracting.load(std::memory_order_acquire) == 0;
        total += c->conn.numComp;
    }
    base_[n] = total;
    nodeCount_ = total;
    parent_.resize(total); rank_.assign(total, 0); anchored_.assign(total, 0);
    for (int i = 0; i < n; ++i) {
        if (!info[i].numComp) continue;
        Chunk* c = world.chunkAt(i);
        LockGuard g(c->lock);
        for (int L = 1; L <= info[i].numComp; ++L) {
            const int node = base_[i] + L - 1;
            parent_[node] = node;
            anchored_[node] = c->conn.anchored(L) || L == OVERFLOW_LABEL ? 1 : 0;
        }
    }

    // Pase 2: aristas (+X, +Y, +Z de cada chunk)
    edgeCount_ = 0;
    for (int i = 0; i < n; ++i) {
        if (!info[i].numComp) continue;
        Chunk* c = world.chunkAt(i);
        for (int f = 0; f < 3; ++f) {
            const int face = 2 * f + 1;
            Chunk* nb = world.chunk(c->cx + FACE_DIR[face][0], c->cy + FACE_DIR[face][1], c->cz + FACE_DIR[face][2]);
            if (!nb) continue;
            const int j = world.chunkIndex(nb->cx, nb->cy, nb->cz);
            if (!info[j].numComp) continue;
            LockGuard g(c->lock);
            for (uint16_t pair : c->conn.edges[f]) {
                const int la = pair >> 8, lb = pair & 0xFF;
                if (la < 1 || la > info[i].numComp || lb < 1 || lb > info[j].numComp) continue; // par obsoleto
                unite(base_[i] + la - 1, base_[j] + lb - 1);
                ++edgeCount_;
            }
        }
    }

    // Pase 2b: regla "pristine" por conjunto: un conjunto cuyos chunks están TODOS intactos se considera
    // anclado (lo que flota en un nivel recién cargado no cae). En cuanto se daña cualquier chunk del
    // conjunto, sólo cuentan las anclas reales (suelo / material ancla): lo que quede sin apoyo cae.
    // La "zona de daño" son los chunks con daño de JUEGO (balas, explosiones) y sus vecinos: un conjunto
    // intacto que esté ahí también pierde el anclaje (un contenedor apoyado sobre una viga con un voxel de
    // hueco entre ambos no está conectado a la viga: al romperla debe caer aunque su chunk no se haya tocado).
    // Extraer una pieza NO cuenta como daño: si contara, cada pieza que cae arrastraría en cadena a todo lo
    // que flota alrededor (mapas importados sin limpiar tienen miles de flotadores).
    if (!auditNoPristine) {
    thread_local std::vector<uint8_t> zone;
    zone.assign(n, 0);
    for (int i = 0; i < n; ++i) {
        if (!info[i].numComp || !info[i].damaged) continue;
        const IVec3 cc = world.chunkCoords(i);
        for (int dz = -1; dz <= 1; ++dz) for (int dy = -1; dy <= 1; ++dy) for (int dx = -1; dx <= 1; ++dx) {
            const int x = cc.x + dx, y = cc.y + dy, z = cc.z + dz;
            if (x < 0 || y < 0 || z < 0 || x >= world.chunksX() || y >= world.chunksY() || z >= world.chunksZ()) continue;
            zone[world.chunkIndex(x, y, z)] = 1;
        }
    }
    {
        thread_local std::vector<uint8_t> rootEdited;
        rootEdited.assign(total, 0);
        for (int i = 0; i < n; ++i) {
            if (!info[i].numComp || !zone[i]) continue;
            for (int L = 1; L <= info[i].numComp; ++L) rootEdited[find(base_[i] + L - 1)] = 1;
        }
        for (int i = 0; i < n; ++i) {
            if (!info[i].numComp || !info[i].pristine) continue;
            for (int L = 1; L <= info[i].numComp; ++L) {
                const int r = find(base_[i] + L - 1);
                if (!rootEdited[r]) anchored_[r] = 1;
            }
        }
    }

    }   // !auditNoPristine
    // Pase 3: agrupar los nodos no anclados por raíz
    groupOfRoot_.assign(total, -1);
    for (int i = 0; i < n; ++i) {
        if (!info[i].numComp) continue;
        for (int L = 1; L <= info[i].numComp; ++L) {
            if (L == OVERFLOW_LABEL) continue;
            const int node = base_[i] + L - 1;
            const int r = find(node);
            if (anchored_[r]) continue;
            if (groupOfRoot_[r] < 0) { groupOfRoot_[r] = static_cast<int>(outGroups.size()); outGroups.emplace_back(); }
            outGroups[groupOfRoot_[r]].nodes.push_back(DetachedNode{static_cast<uint32_t>(i), static_cast<uint8_t>(L), info[i].connVersion});
        }
    }

    // Pase 4: filtrar grupos cuyos chunks o vecinos tienen caché desactualizada (se resolverán después)
    size_t w = 0;
    for (size_t gi = 0; gi < outGroups.size(); ++gi) {
        DetachedGroup& grp = outGroups[gi];
        bool ok = true;
        uint32_t voxels = 0;
        for (const DetachedNode& nd : grp.nodes) {
            const int i = static_cast<int>(nd.chunkIdx);
            if (!info[i].fresh) { ok = false; break; }
            Chunk* c = world.chunkAt(i);
            { LockGuard g(c->lock); voxels += c->conn.compVoxels[nd.label]; }
            for (int f = 0; f < 6 && ok; ++f) {
                Chunk* nb = world.chunk(c->cx + FACE_DIR[f][0], c->cy + FACE_DIR[f][1], c->cz + FACE_DIR[f][2]);
                if (nb && !info[world.chunkIndex(nb->cx, nb->cy, nb->cz)].fresh) ok = false;
            }
            if (!ok) break;
        }
        if (!ok) continue;
        grp.voxelCount = voxels;
        if (w != gi) outGroups[w] = std::move(outGroups[gi]);
        ++w;
    }
    outGroups.resize(w);
}

} // namespace vx
