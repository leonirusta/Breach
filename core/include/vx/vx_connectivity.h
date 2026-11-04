// vxcore - Conectividad jerárquica incremental
// ---------------------------------------------------------------------------
// Pregunta que responde: "¿qué voxels han dejado de estar unidos al suelo?"
//
// Nivel 0 (por chunk, hilo de trabajo): etiquetado de componentes conexas
//   (BFS 6-vecinos) sobre los 32^3 voxels. Se guarda SOLO: nº de componentes,
//   etiqueta de cada celda de borde (6 KB), voxels por componente y si toca un
//   material ancla. Coste ~0.2-0.8 ms por chunk, sólo para chunks editados.
//
// Nivel 1 (global, hilo principal): grafo cuyos nodos son (chunk, componente)
//   y cuyas aristas son los pares de etiquetas que se tocan a través de las
//   caras entre chunks (precalculados en el nivel 0). Union-Find sobre ~1-3 k
//   nodos: decenas de microsegundos. Todo conjunto sin ancla = pieza desprendida.
//
// El "modelo de carga" (¿aguanta el peso?) NO vive aquí: es el StructuralAnalyzer
// (vx_structure.h), que decide qué celdas fallan; este solver sólo desprende lo
// que ha perdido la conexión con el suelo tras esos fallos.
// ---------------------------------------------------------------------------
#pragma once
#include <cstdint>
#include <vector>
#include "vx_chunk.h"
#include "vx_world.h"

namespace vx {

// Buffers de trabajo del etiquetado (uno por hilo).
struct LabelScratch {
    std::vector<uint8_t> label;      // CHUNK_VOLUME
    std::vector<uint16_t> stack;     // CHUNK_VOLUME
    LabelScratch() : label(CHUNK_VOLUME), stack(CHUNK_VOLUME) {}
};

// Etiqueta las componentes conexas del chunk (lee `vox`, escribe `scratch.label` y rellena `out`).
// Los voxels de material ANCLA (suelo, pavimento...) NO forman parte de las componentes: son
// el "suelo" del grafo. Una componente está anclada si toca un voxel ancla (dentro del chunk,
// o a través del borde si se pasa `padded` 34^3) o está en y==0 del mundo.
// worldY0 = coordenada y mundial del voxel (·,0,·) del chunk.
void labelChunk(const uint8_t* vox, const uint8_t* padded, int worldY0, LabelScratch& scratch, ChunkConn& out);

// Calcula los pares de etiquetas entre el chunk `c` y su vecino `n` a través de la
// cara `face` de `c` (usa las cachés de borde de ambos). Resultado en `outPairs`.
void computeFaceEdges(const ChunkConn& c, const ChunkConn& n, int face, std::vector<uint16_t>& outPairs);

struct DetachedNode { uint32_t chunkIdx; uint8_t label; uint32_t connVersion; };
struct DetachedGroup { std::vector<DetachedNode> nodes; uint32_t voxelCount = 0; };

// Resuelve el grafo global. Devuelve los grupos desprendidos cuyos chunks (y vecinos)
// tienen la caché al día; los demás se posponen hasta que sus jobs terminen.
class ConnectivitySolver {
public:
    void solve(const World& world, std::vector<DetachedGroup>& outGroups);
    // AUDITORIA: con esto a true, solve() ignora la regla pristine y devuelve TODO lo que no toca un ancla,
    // aunque este intacto. Es lo que se caeria si se danara: sirve para encontrar la geometria mal apoyada de un mapa.
    bool auditNoPristine = false;
    int lastNodeCount() const { return nodeCount_; }
    int lastEdgeCount() const { return edgeCount_; }
    int lastSkippedNoLock() const { return skippedNoLock_; }
private:
    int find(int i) { while (parent_[i] != i) { parent_[i] = parent_[parent_[i]]; i = parent_[i]; } return i; }
    void unite(int a, int b) { a = find(a); b = find(b); if (a != b) { if (rank_[a] < rank_[b]) std::swap(a, b); parent_[b] = a; if (rank_[a] == rank_[b]) ++rank_[a]; anchored_[a] = anchored_[a] || anchored_[b]; } }
    std::vector<int> parent_, rank_, base_;
    std::vector<uint8_t> anchored_;
    std::vector<int> groupOfRoot_;
    int nodeCount_ = 0, edgeCount_ = 0, skippedNoLock_ = 0;
};

} // namespace vx
