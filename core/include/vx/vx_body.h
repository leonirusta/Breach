// vxcore - VoxelBody: pieza desprendida del mundo
// ---------------------------------------------------------------------------
// Cuando la conectividad detecta que un grupo de voxels ya no está unido al
// suelo, se extrae del mundo y se convierte en un VoxelBody: una mini-rejilla
// con su propia transformación. El host lo simula como rigid body con una
// colisión aproximada por CAJAS (no por voxel): 1..maxBoxes cajas por cuerpo.
// La malla y las cajas están expresadas respecto al centro de masas (COM),
// así el host coloca el cuerpo en worldOrigin + com y las rotaciones son correctas.
// ---------------------------------------------------------------------------
#pragma once
#include <cstdint>
#include <vector>
#include "vx_math.h"
#include "vx_mesher.h"

namespace vx {

struct Box { Vec3 center; Vec3 halfExtents; }; // respecto al COM, metros

struct VoxelBody {
    uint32_t id = 0;
    int sx = 0, sy = 0, sz = 0;        // dimensiones en voxels
    std::vector<uint8_t> vox;          // sx*sy*sz, índice x + y*sx + z*sx*sy
    Vec3 worldOrigin;                  // posición mundo de la esquina mínima (m)
    Vec3 com;                          // centro de masas local (m) respecto a worldOrigin
    float mass = 0;                    // kg
    uint32_t voxelCount = 0;
    uint8_t dominantMat = 0;
    std::vector<Box> boxes;            // colisión (respecto al COM)
    MeshData mesh;                     // malla (respecto al COM)
    Vec3 initialVel;                   // m/s: velocidad con la que nace (trozos lanzados por una explosión)
    Vec3 initialAngVel;                // rad/s: giro inicial (estructura que se inclina hacia el lado sin apoyo)

    uint8_t at(int x, int y, int z) const { return vox[x + y * sx + z * sx * sy]; }
    Vec3 worldCom() const { return worldOrigin + com; }
    size_t bytes() const { return vox.size() + boxes.size() * sizeof(Box) + mesh.bytes(); }
};

// Construye un cuerpo desde una lista de voxels en coordenadas de mundo.
struct BodyVoxel { int32_t x, y, z; uint8_t mat; };
class BodyBuilder {
public:
    // Rellena `out` (rejilla, masa, COM, cajas, malla). Reutiliza buffers internos: 1 por hilo.
    void build(const std::vector<BodyVoxel>& voxels, float voxelSize, int maxBoxes, uint32_t id, VoxelBody& out);
    // Descomposición greedy en cajas alineadas. Si excede maxBoxes, las más pequeñas se
    // funden en su AABB conjunto. Cajas en unidades de voxel (enteros).
    struct IBox { int x0, y0, z0, x1, y1, z1; int volume() const { return (x1 - x0) * (y1 - y0) * (z1 - z0); } };
    static void decompose(const uint8_t* vox, int sx, int sy, int sz, int maxBoxes, std::vector<IBox>& out, std::vector<uint8_t>& scratch);
private:
    Mesher mesher_;
    std::vector<uint8_t> padded_;
    std::vector<uint8_t> scratch_;
    std::vector<IBox> iboxes_;
};

} // namespace vx
