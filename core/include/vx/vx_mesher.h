// vxcore - Greedy mesher con oclusión ambiental (AO) y LOD
// ---------------------------------------------------------------------------
// Convierte una rejilla de voxels en la malla de triángulos MÍNIMA: caras
// adyacentes con el mismo material y el mismo patrón de AO se fusionan en un
// solo quad. Sin UVs, sin texturas: color por material + AO por vértice, la
// variación de "textura" se hace en el shader con un hash de la posición.
// Vértice = 16 bytes. El host puede comprimir más al subir a GPU.
// ---------------------------------------------------------------------------
#pragma once
#include <cstdint>
#include <vector>
#include "vx_config.h"
#include "vx_math.h"

namespace vx {

class World;

// SOMBRA DEL SOL HORNEADA (movil): cada cara visible lanza un rayo hacia el sol por la rejilla del mundo y
// guarda si le llega luz. Asi la GPU no tiene que dibujar el mapa de sombras. Se rehace al romper.
struct SolTrazador {
    const World* world = nullptr;
    int ox = 0, oy = 0, oz = 0;   // voxel del mundo donde empieza la rejilla (celda 0,0,0)
    int escala = 1;               // voxels finos por celda de la rejilla (1, 2 o 4 en las LOD)
    float dx = 0, dy = 1, dz = 0; // direccion HACIA el sol (unitaria)
    float maxVox = 200;           // alcance del rayo, en voxels
    bool sombreada(int cx, int cy, int cz) const;   // celda de aire delante de la cara
};

struct MeshVertex {
    float x, y, z;      // posición local (m)
    uint8_t normal;     // índice de cara 0..5 (ver FACE_DIR)
    uint8_t ao;         // 0..3 (0 = más oscuro)
    uint8_t mat;        // id de material
    uint8_t flags;      // bit0: sol horneado, bit1: en sombra
};

struct MeshData {
    std::vector<MeshVertex> verts;
    std::vector<uint32_t> idxOpaque;
    std::vector<uint32_t> idxGlass;
    int quads = 0;
    void clear() { verts.clear(); idxOpaque.clear(); idxGlass.clear(); quads = 0; }
    bool empty() const { return verts.empty(); }
    int triangles() const { return static_cast<int>((idxOpaque.size() + idxGlass.size()) / 3); }
    size_t bytes() const { return verts.size() * sizeof(MeshVertex) + (idxOpaque.size() + idxGlass.size()) * 4; }
};

// Rejilla genérica con 1 celda de relleno alrededor (dims = interior).
// cell(x,y,z) con x en [-1, sx] lee padded[(x+1) + (y+1)*(sx+2) + (z+1)*(sx+2)*(sy+2)].
struct PaddedGrid {
    const uint8_t* data;
    int sx, sy, sz;
    int strideY() const { return sx + 2; }
    int strideZ() const { return (sx + 2) * (sy + 2); }
    uint8_t at(int x, int y, int z) const { return data[(x + 1) + (y + 1) * strideY() + (z + 1) * strideZ()]; }
};

class Mesher {
public:
    // Sentido de giro de las caras frontales. Godot, Unity y Direct3D usan HORARIO (visto desde fuera);
    // OpenGL puro usa antihorario. Afecta al culling del renderer y a la colisión unilateral de Jolt.
    static bool clockwiseFront;

    // Genera la malla. `cellSize` metros por celda, `offset` se suma a cada vértice (m).
    // Buffers internos reutilizados: crear un Mesher por hilo.
    void mesh(const PaddedGrid& g, float cellSize, const Vec3& offset, MeshData& out, const SolTrazador* sol = nullptr);

    // AO en la clave de fusion. Con false no se calcula (todas las esquinas a 3) y las caras se funden mucho mas:
    // medido en Monaco, las LOD salen con un 32 % menos de triangulos. Para lo que se ve de lejos (las LOD) y para
    // los oclusores, donde el AO no pinta nada.
    bool conAO = true;

    // SOLO LA FORMA (2026-10-01): la clave de fusion es unicamente "cara visible", sin material, AO ni sol. Sale la
    // MISMA superficie que la malla de dibujo pero con las paredes en pocos rectangulos (en la cafeteria, pintada
    // ladrillo a ladrillo, la malla de dibujo eran ~3.000 triangulos por chunk). Es la que se le da a Jolt para la
    // colision: rehacer la forma concava de un chunk (arbol BVH) costaba 11-25 ms en el hilo principal por balazo.
    // Todas las caras van a idxOpaque (mat 0).
    bool soloForma = false;
    // SIN CRISTAL (2026-10-10, malla de SOMBRA): con soloForma, el cristal cuenta como aire (no proyecta sombra, igual
    // que en la malla de dibujo, donde va en idxGlass y el caster solo mete idxOpaque).
    bool sinCristal = false;

    // COLOR POR TEXTURA (2026-10-13, pedido: "optimiza el dibujo"): con una tabla de grupos (256 entradas, una por
    // material), las caras se funden por GRUPO y no por material: en un mapa pintado ladrillo a ladrillo cada ladrillo
    // de otro color era otro rectangulo. El color de cada voxel lo lee el shader de una textura (voxel_world.cpp,
    // COLOR POR TEXTURA). Cada cara fundida lleva el material de su primera celda y flags bit2 (= color de textura).
    // El cristal no se funde por grupo (va a su propia superficie). nullptr = como siempre.
    const uint8_t* grupoDe = nullptr;

    // Reduce 2x una rejilla 34^3 (chunk) a 18^3 para la malla LOD. Umbral: >=2 de 8 sólidos
    // (mantiene paredes de 1 voxel en vez de perderlas).
    static void downsample2x(const uint8_t* padded34, uint8_t* outPadded18);
    // Versión genérica: entrada (dim+2)^3 con relleno -> salida (dim/2+2)^3. dim par.
    static void downsample2xGrid(const uint8_t* inPadded, int dim, uint8_t* outPadded);
    // Variante CONSERVADORA para occluders: la celda gruesa es sólida sólo si sus 8 finas son sólidas
    // opacas (el cristal cuenta como aire). Nunca es mayor que la geometría real.
    static void downsample2xGridMin(const uint8_t* inPadded, int dim, uint8_t* outPadded);

private:
    std::vector<uint32_t> mask_;   // clave por celda: mat | ao<<8 | visible<<16
    std::vector<uint8_t> matAt_;   // el material de verdad de cada celda (con grupoDe la clave lleva el grupo)
};

} // namespace vx
