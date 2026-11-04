// vxcore - Navegación dinámica sobre la rejilla de voxels
// ---------------------------------------------------------------------------
// NO hay navmesh que reconstruir: la rejilla de voxels ES el dato de navegación.
// Una celda (~0.5 m) es transitable a la altura y si tiene sólido en y y ~1.75 m de aire encima.
// Las medidas del agente se convierten a voxels según el tamaño de voxel real.
//
// Caché por chunk: para cada celda, una máscara de 32 bits con las alturas transitables,
// calculada con operaciones de bits sobre las columnas de voxels. Se recalcula sola cuando
// cambia la versión del chunk (o del de arriba). Línea de visión = raycast DDA.
// ---------------------------------------------------------------------------
#pragma once
#include <cstdint>
#include <memory>
#include <vector>
#include "vx_config.h"
#include "vx_math.h"

namespace vx {

class World;

struct NavStats { int expansions = 0; bool complete = false; double ms = 0; };

// Caché de transitabilidad de un chunk: hasta 16x16 celdas x 32 alturas.
struct NavChunk {
    uint32_t walk[(CHUNK_SIZE / 2) * (CHUNK_SIZE / 2)];
    uint32_t version = 0;
    uint32_t aboveVersion = 0;
    bool valid = false;
};

class Navigator {
public:
    explicit Navigator(const World& w);
    bool findPath(const Vec3& from, const Vec3& to, std::vector<Vec3>& out, int maxExpansions, NavStats* stats = nullptr);
    bool lineOfSight(const Vec3& a, const Vec3& b) const;
    int floorInRange(int cx, int cz, int yTop, int yBot);
    int findFloor(int cx, int cz, int yStart, int yMin) { return floorInRange(cx, cz, yStart, yMin); }
    int neighborFloor(int cx, int cz, int fromY) { return floorInRange(cx, cz, fromY + stepUp_, fromY - maxDrop_); }
    bool isStandable(int cx, int cz, int floorY) const;
    uint32_t standableMask(int cx, int cz, int cy);
    size_t cacheBytes() const { return cached_ * sizeof(NavChunk); }
    // medidas en voxels derivadas del tamaño de voxel
    int cellVoxels() const { return cell_; }
    int agentHeight() const { return agentH_; }
    int stepUp() const { return stepUp_; }
    int maxDrop() const { return maxDrop_; }

private:
    struct Node { int cx, cz, y; float g, f; int parent; };
    static uint64_t key(int cx, int cz, int y) {
        return (static_cast<uint64_t>(static_cast<uint32_t>(cx)) << 40) ^ (static_cast<uint64_t>(static_cast<uint32_t>(cz)) << 16) ^ static_cast<uint32_t>(y & 0xFFFF);
    }
    const NavChunk* navChunk(int ccx, int cy, int ccz);
    const World& world_;
    int cell_ = 2, agentH_ = 7, stepUp_ = 3, maxDrop_ = 12, cells_ = 16;
    std::vector<std::unique_ptr<NavChunk>> cache_;
    size_t cached_ = 0;
    // el ultimo chunk de standableMask dentro de una busqueda (vx_nav.cpp); findPath lo olvida al empezar
    bool enBusqueda_ = false, memoOk_ = false; int memoX_ = 0, memoY_ = 0, memoZ_ = 0; const NavChunk* memo_ = nullptr;
    std::vector<Node> nodes_;
    std::vector<int> open_;

    // Tabla hash de direccionamiento abierto. Clave, valor y generacion JUNTOS (2026-10-16): en tres arreglos
    // separados cada sondeo tocaba tres lineas de cache, y la de `visited_` (131.072 huecos, 2 MB) no cabe en la L2.
    // Misma logica, mismo resultado.
    struct Visited {
        struct Hueco { uint64_t key; int val; uint32_t gen; };
        std::vector<Hueco> h;
        uint32_t cur = 1; uint32_t mask = 0;
        void reserve(size_t n) { size_t cap = 1024; while (cap < n * 2) cap <<= 1; if (cap != h.size()) { h.assign(cap, Hueco{0, -1, 0}); mask = static_cast<uint32_t>(cap - 1); } }
        void clear() { if (++cur == 0) { for (Hueco& x : h) x.gen = 0; cur = 1; } }
        int* find(uint64_t k) {
            uint32_t i = static_cast<uint32_t>((k * 0x9E3779B97F4A7C15ull) >> 40) & mask;
            for (;;) { Hueco& x = h[i]; if (x.gen != cur) return nullptr; if (x.key == k) return &x.val; i = (i + 1) & mask; }
        }
        void set(uint64_t k, int v) {
            uint32_t i = static_cast<uint32_t>((k * 0x9E3779B97F4A7C15ull) >> 40) & mask;
            for (;;) { Hueco& x = h[i]; if (x.gen != cur) { x.gen = cur; x.key = k; x.val = v; return; } if (x.key == k) { x.val = v; return; } i = (i + 1) & mask; }
        }
    } visited_, cabeVis_;     // cabeVis_: lo ya mirado de "cabe el cuerpo" en esta busqueda (indice de OFF + 1, 0 = no)
};

} // namespace vx
