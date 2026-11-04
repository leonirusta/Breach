// vxcore - Navegación dinámica (A* sobre la rejilla de voxels con caché de bits por chunk)
#include "vx/vx_nav.h"
#include "vx/vx_world.h"
#include <algorithm>
#include <cmath>
#include <cstdlib>

namespace vx {

namespace {
inline int highestBit(uint32_t m) { int b = 31; while (b >= 0 && !((m >> b) & 1u)) --b; return b; }
inline bool navMemo() { static const bool v = [] { const char* e = std::getenv("VX_NAV_SIN_MEMO"); return !(e && e[0] == '1'); }(); return v; }
inline bool navSinCache() { static const bool v = [] { const char* e = std::getenv("VX_NAV_SIN_CACHE"); return e && e[0] == '1'; }(); return v; }
}

Navigator::Navigator(const World& w) : world_(w) {
    cache_.resize(static_cast<size_t>(w.numChunkSlots()));
    // medidas del agente en voxels: celda ~0.5 m, altura 1.75 m, escalón 0.75 m, caída 3 m
    const float vs = w.voxelSize();
    // CELDA DE 0,4 m (2026-09-23). Se pedia 0,5 m, pero a 10 cm salen 5 voxels, que no dividen el chunk, y el
    // redondeo HACIA ARRIBA la dejaba en 8 (0,8 m; y a 20 cm, 3 -> 4, otra vez 0,8 m). Una celda solo es
    // transitable si su columna entera esta libre, y con 0,8 m una puerta estrecha no tenia ninguna: en dust
    // el paso corto del spawn policia a A no existia para los bots y daban una vuelta de 122 m (medido con
    // --rutatest). Ahora se busca el divisor del chunk mas cercano POR DEBAJO.
    cell_ = clampv(static_cast<int>(0.4f / vs + 0.5f), 1, 8);
    while (cell_ > 1 && CHUNK_SIZE % cell_ != 0) --cell_;
    cells_ = CHUNK_SIZE / cell_;
    if (cells_ > 16) { cell_ = 2; cells_ = 16; }
    agentH_ = clampv(static_cast<int>(1.75f / vs + 0.5f), 2, 31);
    stepUp_ = std::max(1, static_cast<int>(0.75f / vs + 0.5f));
    maxDrop_ = std::max(2, static_cast<int>(3.0f / vs + 0.5f));
}

bool Navigator::isStandable(int cx, int cz, int floorY) const {
    const int x0 = cx * cell_, z0 = cz * cell_;
    if (floorY < 0) return false;
    bool support = false;
    for (int dz = 0; dz < cell_ && !support; ++dz)
        for (int dx = 0; dx < cell_; ++dx)
            if (isSolid(world_.getVoxel(x0 + dx, floorY, z0 + dz))) { support = true; break; }
    if (!support) return false;
    for (int h = 1; h <= agentH_; ++h)
        for (int dz = 0; dz < cell_; ++dz)
            for (int dx = 0; dx < cell_; ++dx)
                if (isSolid(world_.getVoxel(x0 + dx, floorY + h, z0 + dz))) return false;
    return true;
}

// Recalcula (si hace falta) y devuelve la caché del chunk (ccx, cy, ccz).
const NavChunk* Navigator::navChunk(int ccx, int cy, int ccz) {
    if (ccx < 0 || cy < 0 || ccz < 0 || ccx >= world_.chunksX() || cy >= world_.chunksY() || ccz >= world_.chunksZ()) return nullptr;
    const int idx = world_.chunkIndex(ccx, cy, ccz);
    const Chunk* c = world_.chunkAt(idx);
    const Chunk* above = world_.chunk(ccx, cy + 1, ccz);
    const uint32_t v = c ? c->version : 0, va = above ? above->version : 0;
    std::unique_ptr<NavChunk>& slot = cache_[idx];
    if (slot && slot->valid && slot->version == v && slot->aboveVersion == va) return slot.get();
    if (!slot) { slot.reset(new NavChunk()); ++cached_; }
    NavChunk& nc = *slot;
    const int CELLS = cells_;
    for (int k = 0; k < CELLS; ++k)
    for (int i = 0; i < CELLS; ++i) {
        uint64_t solid = 0;   // bits 0..31: filas de este chunk; 32..38: 7 filas del chunk superior
        for (int dz = 0; dz < cell_; ++dz)
        for (int dx = 0; dx < cell_; ++dx) {
            const int x = i * cell_ + dx, z = k * cell_ + dz;
            if (c) for (int y = 0; y < CHUNK_SIZE; ++y) if (c->vox[Chunk::index(x, y, z)]) solid |= 1ull << y;
            if (above) for (int y = 0; y < agentH_ && y < CHUNK_SIZE; ++y) if (above->vox[Chunk::index(x, y, z)]) solid |= 1ull << (CHUNK_SIZE + y);
        }
        uint64_t blocked = 0;
        for (int h = 1; h <= agentH_; ++h) blocked |= solid >> h;   // bit y: hay sólido en y+1..y+7
        nc.walk[i + k * CELLS] = static_cast<uint32_t>(solid & ~blocked);
    }
    nc.version = v; nc.aboveVersion = va; nc.valid = true;
    return &nc;
}

uint32_t Navigator::standableMask(int cx, int cz, int cy) {
    if (cx < 0 || cz < 0) return 0;
    const int CELLS = cells_;
    // EL ULTIMO CHUNK PEDIDO (2026-10-16): las vecinas de una celda caen casi siempre en el mismo chunk y el A* pedia
    // cada vez el chunk, el de encima y sus versiones. Dentro de UNA busqueda el mundo no cambia (corre en el hilo
    // principal, que es el unico que escribe voxels), asi que se recuerda; findPath lo olvida al empezar.
    const int ccx = cx / CELLS, ccz = cz / CELLS;
    if (enBusqueda_ && memoOk_ && ccx == memoX_ && cy == memoY_ && ccz == memoZ_) {
        return memo_ ? memo_->walk[(cx % CELLS) + (cz % CELLS) * CELLS] : 0;
    }
    const NavChunk* nc = navChunk(ccx, cy, ccz);
    if (enBusqueda_ && navMemo()) { memoOk_ = true; memoX_ = ccx; memoY_ = cy; memoZ_ = ccz; memo_ = nc; }
    if (!nc) return 0;
    return nc->walk[(cx % CELLS) + (cz % CELLS) * CELLS];
}

int Navigator::floorInRange(int cx, int cz, int yTop, int yBot) {
    if (yBot < 0) yBot = 0;
    if (yTop >= world_.sizeY()) yTop = world_.sizeY() - 1;
    if (yTop < yBot) return -1;
    for (int cy = yTop >> CHUNK_BITS; cy >= (yBot >> CHUNK_BITS); --cy) {
        const uint32_t mask = standableMask(cx, cz, cy);
        if (!mask) continue;
        const int lo = std::max(yBot - cy * CHUNK_SIZE, 0), hi = std::min(yTop - cy * CHUNK_SIZE, CHUNK_MASK);
        if (lo > hi) continue;
        const uint32_t range = (hi == 31 ? 0xFFFFFFFFu : ((1u << (hi + 1)) - 1u)) & ~((1u << lo) - 1u);
        const uint32_t m = mask & range;
        if (m) return cy * CHUNK_SIZE + highestBit(m);
    }
    return -1;
}

bool Navigator::lineOfSight(const Vec3& a, const Vec3& b) const {
    const Vec3 d = b - a;
    const float len = length(d);
    if (len < 1e-4f) return true;
    RayHit h;
    return !world_.raycast(a, d, len, h);
}

bool Navigator::findPath(const Vec3& from, const Vec3& to, std::vector<Vec3>& out, int maxExpansions, NavStats* stats) {
    Timer timer;
    out.clear();
    // el recuerdo del ultimo chunk solo vale DENTRO de esta busqueda: se enciende aqui y se apaga al salir (por
    // cualquier return); fuera, standableMask mira el chunk como siempre
    struct Guardia { Navigator& n; explicit Guardia(Navigator& x) : n(x) { n.enBusqueda_ = true; n.memoOk_ = false; }
                     ~Guardia() { n.enBusqueda_ = false; n.memoOk_ = false; } } guardia(*this);
    const float vs = world_.voxelSize();
    const float cell = vs * cell_;

    int scx = ifloor(from.x / cell), scz = ifloor(from.z / cell);
    int gcx = ifloor(to.x / cell),   gcz = ifloor(to.z / cell);
    const int sFeet = ifloor(from.y / vs), gFeet = ifloor(to.y / vs);
    // PEGADO A UNA PARED. Una celda (0,8 m con voxels de 10 cm) solo es transitable si NADA solido cruza su
    // columna, asi que un bot de pie junto a un muro esta en una celda que lo pisa en parte, y el A* no tenia
    // desde donde empezar: medido en dust2, 4 de 10 bots atascados no tenian camino por eso, y se quedaban
    // clavados la ronda entera. Lo mismo con destinos pegados a una pared. Se usa la celda transitable mas
    // cercana (anillo de 1 y luego de 2 celdas), mejor si se ve desde el punto (no la del otro lado del muro).
    auto celdaCercana = [&](const Vec3& p, int& cx, int& cz, int feet) -> int {
        int y = findFloor(cx, cz, feet + stepUp_, feet - maxDrop_);
        if (y >= 0) return y;
        for (int r = 1; r <= 2; ++r) {
            float mejor = 1e30f; int bx = cx, bz = cz, by = -1; bool mejorVe = false;
            for (int dz = -r; dz <= r; ++dz)
            for (int dx = -r; dx <= r; ++dx) {
                if (std::max(std::abs(dx), std::abs(dz)) != r) continue;
                const int ny = findFloor(cx + dx, cz + dz, feet + stepUp_, feet - maxDrop_);
                if (ny < 0) continue;
                const Vec3 c((cx + dx + 0.5f) * cell, (ny + 1) * vs, (cz + dz + 0.5f) * cell);
                const float ex = c.x - p.x, ez = c.z - p.z, ey = (c.y - p.y) * 0.5f;
                const float d2 = ex * ex + ez * ez + ey * ey;
                const bool ve = lineOfSight(p + Vec3(0, 1.0f, 0), c + Vec3(0, 1.0f, 0));
                if ((ve && !mejorVe) || (ve == mejorVe && d2 < mejor)) { mejor = d2; bx = cx + dx; bz = cz + dz; by = ny; mejorVe = ve; }
            }
            if (by >= 0) { cx = bx; cz = bz; return by; }
        }
        return -1;
    };
    const int sy = celdaCercana(from, scx, scz, sFeet);
    const int gy = celdaCercana(to, gcx, gcz, gFeet);
    if (stats) { stats->expansions = 0; stats->complete = false; }
    if (sy < 0 || gy < 0) { if (stats) stats->ms = timer.ms(); return false; }

    visited_.reserve(static_cast<size_t>(maxExpansions) * 9 + 64);
    // Heurística ligeramente sobreestimada (x1.15): rutas casi óptimas con muchas menos expansiones en terreno abierto.
    auto heuristic = [&](int cx, int cz, int y) {
        const float dx = static_cast<float>(cx - gcx), dz = static_cast<float>(cz - gcz), dy = static_cast<float>(y - gy) * 0.25f;
        return 1.15f * std::sqrt(dx * dx + dz * dz + dy * dy);
    };
    auto cmp = [&](int a, int b) { return nodes_[a].f > nodes_[b].f; };

    int expansions = 0, best = 0;
    bool complete = false;
    static const int DIRS[8][2] = {{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}};

    // EL CUERPO TIENE QUE CABER (2026-10-02, medido en la cafeteria con --botstrabados y --sondasitio). Una celda era
    // transitable si SU columna (0,4 m) estaba libre, pero el bot mide 0,6 m (enemy._blocked_at: caja de 0,3 m de radio
    // de 0,5 a 1,6 m sobre el suelo): el A* lo mandaba entre una pared y una columna a 0,7 m, o por una rendija de
    // 0,4 m entre dos muros, y el bot se quedaba empujando ahi (en la cafeteria, bots parados mas de un minuto).
    // Ahora, encontrado el camino, se mira en CADA CELDA SUYA si esa misma caja cabe en su centro o en uno de 8 puntos
    // dentro de ella (y el camino pasa por ese punto); las que no, se VETAN y se busca otra vez (3 intentos como
    // mucho). Mirarlo en cada celda explorada costaba un 10-25 % mas en todas las busquedas (--astarmide); asi la
    // busqueda normal cuesta lo de siempre y solo se repite donde de verdad hay un paso estrecho.
    const float RADIO = 0.3f, BAJO = 0.5f, ALTO = 1.6f;
    const float q = cell * 0.3f;
    static const float OFF[9][2] = {{0,0},{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}};
    cabeVis_.reserve(2048);
    cabeVis_.clear();
    auto cajaLibre = [&](float x, float z, float suelo) {
        const IVec3 a = world_.toVoxel(Vec3(x - RADIO, suelo + BAJO, z - RADIO));
        const IVec3 b = world_.toVoxel(Vec3(x + RADIO, suelo + ALTO, z + RADIO));
        return !world_.boxSolid(a, b);
    };
    // indice de OFF donde cabe el cuerpo en la celda (cx, cz) con el suelo en y, o -1 (se recuerda: `cabeVis_`)
    auto cabe = [&](int cx, int cz, int y) -> int {
        const uint64_t k = key(cx, cz, y);
        if (const int* v = cabeVis_.find(k)) return *v - 1;
        int r = -1;
        const float suelo = (y + 1) * vs, ccx = (cx + 0.5f) * cell, ccz = (cz + 0.5f) * cell;
        for (int s = 0; s < 9; ++s)
            if (cajaLibre(ccx + OFF[s][0] * q, ccz + OFF[s][1] * q, suelo)) { r = s; break; }
        cabeVis_.set(k, r + 1);
        return r;
    };
    auto vetada = [&](int cx, int cz, int y) { const int* v = cabeVis_.find(key(cx, cz, y)); return v && *v == 0; };

    for (int intento = 0; ; ++intento) {
        nodes_.clear(); open_.clear();
        visited_.clear();
        best = 0; complete = false;
        nodes_.push_back(Node{scx, scz, sy, 0.f, heuristic(scx, scz, sy), -1});
        visited_.set(key(scx, scz, sy), 0);
        open_.push_back(0);
        float bestH = nodes_[0].f;
        int exp = 0;

        while (!open_.empty() && exp < maxExpansions) {
            std::pop_heap(open_.begin(), open_.end(), cmp);
            const int ni = open_.back(); open_.pop_back();
            const Node cur = nodes_[ni];
            const int* vi = visited_.find(key(cur.cx, cur.cz, cur.y));
            if (vi && *vi != ni) continue;   // entrada obsoleta
            ++exp;
            const float h = heuristic(cur.cx, cur.cz, cur.y);
            if (h < bestH) { bestH = h; best = ni; }
            if (cur.cx == gcx && cur.cz == gcz && std::abs(cur.y - gy) <= stepUp_) { best = ni; complete = true; break; }

            // el suelo de las 4 vecinas rectas, UNA vez: las diagonales vuelven a pedir esas mismas (para no cortar
            // esquinas) y eran 16 llamadas por nodo en vez de 8. Misma funcion, mismo mundo: el mismo resultado.
            // VX_NAV_SIN_CACHE=1 = como antes (para comparar).
            int recta[4];
            for (int d = 0; d < 4; ++d) recta[d] = neighborFloor(cur.cx + DIRS[d][0], cur.cz + DIRS[d][1], cur.y);
            for (int d = 0; d < 8; ++d) {
                const int ncx = cur.cx + DIRS[d][0], ncz = cur.cz + DIRS[d][1];
                const int ny = (d < 4 && !navSinCache()) ? recta[d] : neighborFloor(ncx, ncz, cur.y);
                if (ny < 0) continue;
                // celdas donde ya se vio que el cuerpo NO cabe (la meta se acepta siempre: se llega hasta donde se pueda)
                if (!(ncx == gcx && ncz == gcz) && vetada(ncx, ncz, ny)) continue;
                const bool diag = DIRS[d][0] != 0 && DIRS[d][1] != 0;
                if (diag) {
                    // no cortar esquinas: ambos cardinales deben ser transitables a un nivel similar
                    // DIRS: 0 (1,0) 1 (-1,0) 2 (0,1) 3 (0,-1)
                    const int ya = navSinCache() ? neighborFloor(cur.cx + DIRS[d][0], cur.cz, cur.y) : recta[DIRS[d][0] > 0 ? 0 : 1];
                    const int yb = navSinCache() ? neighborFloor(cur.cx, cur.cz + DIRS[d][1], cur.y) : recta[DIRS[d][1] > 0 ? 2 : 3];
                    if (ya < 0 || yb < 0 || std::abs(ya - cur.y) > stepUp_ || std::abs(yb - cur.y) > stepUp_) continue;
                    if (vetada(cur.cx + DIRS[d][0], cur.cz, ya) || vetada(cur.cx, cur.cz + DIRS[d][1], yb)) continue;
                }
                const float step = (diag ? 1.41421f : 1.f) + std::abs(ny - cur.y) * 0.15f;
                const float ng = cur.g + step;
                const uint64_t k = key(ncx, ncz, ny);
                const int* prev = visited_.find(k);
                if (prev && nodes_[*prev].g <= ng) continue;
                const int idx = static_cast<int>(nodes_.size());
                nodes_.push_back(Node{ncx, ncz, ny, ng, ng + heuristic(ncx, ncz, ny), ni});
                visited_.set(k, idx);
                open_.push_back(idx);
                std::push_heap(open_.begin(), open_.end(), cmp);
            }
        }
        expansions += exp;

        // ¿cabe el cuerpo en cada celda del camino? (la salida no se mira: el bot ya esta ahi; la meta tampoco)
        bool limpio = true;
        for (int i = best; i > 0; i = nodes_[i].parent) {
            const Node& nd = nodes_[i];
            if (i == best && complete) continue;
            if (cabe(nd.cx, nd.cz, nd.y) < 0) limpio = false;
        }
        if (limpio || intento >= 2) break;
    }

    // reconstruir (desde el mejor nodo si no se completó), por el punto de cada celda donde cabe el cuerpo
    std::vector<Vec3> rev;
    for (int i = best; i >= 0; i = nodes_[i].parent) {
        const Node& nd = nodes_[i];
        float ox = 0.f, oz = 0.f;
        if (i > 0 && !(i == best && complete)) {
            const int o = std::max(0, cabe(nd.cx, nd.cz, nd.y));
            ox = OFF[o][0] * q; oz = OFF[o][1] * q;
        }
        rev.push_back(Vec3((nd.cx + 0.5f) * cell + ox, (nd.y + 1) * vs, (nd.cz + 0.5f) * cell + oz));
    }
    std::reverse(rev.begin(), rev.end());

    // suavizado barato: saltar waypoints si el CUERPO pasa de uno a otro (mirada acotada).
    // CON EL ANCHO Y EL ALTO DEL CUERPO, no con un rayo fino a la altura del pecho: el atajo que veia ese rayo
    // rozaba esquinas y marcos de puerta con los hombros o las rodillas, y el bot se quedaba empujando contra
    // la esquina (medido en dust2 con --botsatasco: "bloqueado hacia el punto" con el punto a su misma altura).
    // Tres rayos (centro y a 30 cm a cada lado) a 0,6 y a 1,4 m.
    auto cuerpoPasa = [&](const Vec3& a, const Vec3& b) {
        Vec3 d = b - a; d.y = 0;
        const float len = length(d);
        if (len < 1e-4f) return true;
        const Vec3 lado = Vec3(-d.z / len, 0, d.x / len) * 0.3f;
        for (float h : {0.6f, 1.4f})
            for (int k = -1; k <= 1; ++k) {
                const Vec3 o = lado * static_cast<float>(k) + Vec3(0, h, 0);
                if (!lineOfSight(a + o, b + o)) return false;
            }
        return true;
    };
    if (rev.size() > 2) {
        out.push_back(rev[0]);
        size_t i = 0;
        while (i + 1 < rev.size()) {
            size_t j = std::min(rev.size() - 1, i + 6);
            for (; j > i + 1; --j) {
                if (std::abs(rev[i].y - rev[j].y) < vs * 2 && cuerpoPasa(rev[i], rev[j])) break;
            }
            out.push_back(rev[j]);
            i = j;
        }
    } else out = rev;

    if (stats) { stats->expansions = expansions; stats->complete = complete; stats->ms = timer.ms(); }
    return complete;
}

} // namespace vx
