// vxcore - Greedy mesher
#include "vx/vx_mesher.h"
#include "vx/vx_material.h"
#include "vx/vx_chunk.h"
#include "vx/vx_world.h"
#include <cmath>
#include <cstring>
#include <cstdlib>
#include <vector>
#ifdef _MSC_VER
#include <intrin.h>
#endif

namespace vx {

namespace {

// Lectura segura: fuera del rango con relleno -> aire.
inline uint8_t atSafe(const PaddedGrid& g, int x, int y, int z) {
    if (x < -1 || y < -1 || z < -1 || x > g.sx || y > g.sy || z > g.sz) return 0;
    return g.at(x, y, z);
}

// AO clásico por vértice: 0 (muy ocluido) .. 3 (libre)
inline int vertexAO(bool side1, bool side2, bool corner) {
    if (side1 && side2) return 0;
    return 3 - (static_cast<int>(side1) + static_cast<int>(side2) + static_cast<int>(corner));
}

// el bit mas bajo encendido (x != 0)
inline int bitBajo(uint64_t x) {
#ifdef _MSC_VER
    unsigned long i; _BitScanForward64(&i, x); return static_cast<int>(i);
#else
    return __builtin_ctzll(x);
#endif
}

// VX_MALLADOR_VIEJO=1: la mascara de caras visibles voxel a voxel, como antes (para comparar; la malla sale igual)
const bool g_mallaViejo = std::getenv("VX_MALLADOR_VIEJO") != nullptr;

} // namespace

bool Mesher::clockwiseFront = true;

// Marcha por la rejilla fina desde el centro de la celda hacia el sol, a pasos de 0,6 voxels. Los chunks
// vacios (o sin crear) se saltan enteros: casi todo rayo al aire libre sale en un punado de pasos.
bool SolTrazador::sombreada(int cx, int cy, int cz) const {
    const float h = escala * 0.5f;
    float px = ox + cx * escala + h, py = oy + cy * escala + h, pz = oz + cz * escala + h;
    // arranca desde el borde de la celda gruesa (en las LOD la celda mide 2 o 4 voxels)
    float t = h > 0.5f ? h : 0.6f;
    const int topY = world->sizeY();
    while (t < maxVox) {
        const float x = px + dx * t, y = py + dy * t, z = pz + dz * t;
        const int ix = static_cast<int>(std::floor(x)), iy = static_cast<int>(std::floor(y)), iz = static_cast<int>(std::floor(z));
        if (iy >= topY) return false;
        if (!world->inBounds(ix, iy, iz)) { if (iy < 0) return true; return false; }
        const Chunk* c = world->chunkOfVoxel(ix, iy, iz);
        if (!c || c->solidAtomic.load(std::memory_order_relaxed) == 0) {
            // salto hasta la salida de este chunk
            const float bx = static_cast<float>((ix >> CHUNK_BITS) << CHUNK_BITS), by = static_cast<float>((iy >> CHUNK_BITS) << CHUNK_BITS), bz = static_cast<float>((iz >> CHUNK_BITS) << CHUNK_BITS);
            float te = 1e9f;
            if (dx > 1e-4f) te = std::min(te, (bx + CHUNK_SIZE - x) / dx); else if (dx < -1e-4f) te = std::min(te, (bx - x) / dx);
            if (dy > 1e-4f) te = std::min(te, (by + CHUNK_SIZE - y) / dy); else if (dy < -1e-4f) te = std::min(te, (by - y) / dy);
            if (dz > 1e-4f) te = std::min(te, (bz + CHUNK_SIZE - z) / dz); else if (dz < -1e-4f) te = std::min(te, (bz - z) / dz);
            t += std::max(te, 0.0f) + 0.05f;
            continue;
        }
        const uint8_t m = c->vox[Chunk::index(ix & CHUNK_MASK, iy & CHUNK_MASK, iz & CHUNK_MASK)];
        if (m && !isGlass(m)) return true;
        t += 0.6f;
    }
    return false;
}

void Mesher::mesh(const PaddedGrid& g, float cs, const Vec3& offset, MeshData& out, const SolTrazador* sol) {
    out.clear();
    const int dims[3] = {g.sx, g.sy, g.sz};

    for (int d = 0; d < 3; ++d) {
        const int u = (d + 1) % 3, v = (d + 2) % 3;
        const int du = dims[u], dv = dims[v];
        mask_.resize(static_cast<size_t>(du) * dv);
        if (grupoDe) matAt_.resize(static_cast<size_t>(du) * dv);
        int q[3] = {0, 0, 0}; q[d] = 1;

        for (int back = 0; back < 2; ++back) {
            const int nsign = back ? -1 : 1;
            const uint8_t face = static_cast<uint8_t>(2 * d + (back ? 0 : 1));

            // MASCARAS DE BITS (2026-10-20, como el "binary greedy meshing" de cgerikj): por cada rebanada y fila, un bit por
            // celda (opaco / cristal) a lo largo de u; las caras visibles salen de dos AND y se recorren solo los bits
            // encendidos (el aire no se visita). La clave de cada cara y la fusion son las mismas: la malla sale igual.
            const bool rapido = !g_mallaViejo && du <= 64;
            thread_local std::vector<uint64_t> filaA, filaG;
            thread_local std::vector<uint8_t> filaLlena;
            if (rapido) {
                const size_t ns = static_cast<size_t>(dims[d] + 2);
                filaA.assign(ns * dv, 0); filaG.assign(ns * dv, 0); filaLlena.assign(static_cast<size_t>(dv), 0);
                int p[3];
                for (int sl = -1; sl <= dims[d]; ++sl) {
                    p[d] = sl;
                    for (int k = 0; k < dv; ++k) {
                        p[v] = k;
                        uint64_t a = 0, gl = 0;
                        for (int j = 0; j < du; ++j) {
                            p[u] = j;
                            const uint8_t m = g.at(p[0], p[1], p[2]);
                            if (m) { if (isGlass(m)) gl |= 1ull << j; else a |= 1ull << j; }
                        }
                        filaA[static_cast<size_t>(sl + 1) * dv + k] = a;
                        filaG[static_cast<size_t>(sl + 1) * dv + k] = gl;
                    }
                }
            }
            // la clave de una cara VISIBLE de la celda p (material m) que mira a n
            auto clave = [&](const int* p, uint8_t m, const int* n) -> uint32_t {
                uint32_t key = 0;
                            if (soloForma) {
                                key = 0x10000u | (0xFFu << 8);   // misma clave para toda cara visible: solo la forma
                            } else {
                                // AO en las 4 esquinas, muestreando la celda de aire frente a la cara.
                                int eu[3] = {0, 0, 0}, ev[3] = {0, 0, 0}; eu[u] = 1; ev[v] = 1;
                                uint32_t ao = conAO ? 0u : 0xFFu;
                                static const int cornerDir[4][2] = {{-1, -1}, {1, -1}, {1, 1}, {-1, 1}};
                                for (int c = 0; c < (conAO ? 4 : 0); ++c) {
                                    const int a = cornerDir[c][0], b = cornerDir[c][1];
                                    const bool s1 = atSafe(g, n[0] + eu[0] * a, n[1] + eu[1] * a, n[2] + eu[2] * a) != 0;
                                    const bool s2 = atSafe(g, n[0] + ev[0] * b, n[1] + ev[1] * b, n[2] + ev[2] * b) != 0;
                                    const bool cr = atSafe(g, n[0] + eu[0] * a + ev[0] * b, n[1] + eu[1] * a + ev[1] * b, n[2] + eu[2] * a + ev[2] * b) != 0;
                                    ao |= static_cast<uint32_t>(vertexAO(s1, s2, cr)) << (2 * c);
                                }
                                // con grupoDe se funde por grupo (bit 19) y el material de verdad se guarda aparte
                                if (grupoDe && !isGlass(m)) {
                                    key = 0x10000u | 0x80000u | grupoDe[m] | (ao << 8);
                                    matAt_[p[u] + p[v] * du] = m;
                                } else {
                                    key = 0x10000u | m | (ao << 8);
                                }
                                if (sol) {
                                    // las caras de espaldas al sol no reciben luz directa: cuentan como sombra
                                    const float nd = (d == 0 ? sol->dx : (d == 1 ? sol->dy : sol->dz)) * nsign;
                                    const bool osc = nd <= 0.0f || sol->sombreada(n[0], n[1], n[2]);
                                    key |= 0x40000u | (osc ? 0x20000u : 0u);
                                }
                            }
                return key;
            };

            for (int s = 0; s < dims[d]; ++s) {
                // --- 1. máscara de caras visibles de esta rebanada ---
                if (rapido) {
                    int p[3]; p[d] = s;
                    for (int k = 0; k < dv; ++k) {
                        p[v] = k;
                        const size_t fi = static_cast<size_t>(s + 1) * dv + k, ni = static_cast<size_t>(s + nsign + 1) * dv + k;
                        const uint64_t A = filaA[fi], Gm = sinCristal ? 0ull : filaG[fi], NA = filaA[ni], NG = filaG[ni];
                        uint64_t vis = (A & ~NA) | (Gm & ~(NA | NG));
                        std::memset(&mask_[static_cast<size_t>(k) * du], 0, sizeof(uint32_t) * du);
                        filaLlena[k] = vis != 0;
                        while (vis) {
                            const int j = bitBajo(vis);
                            vis &= vis - 1;
                            p[u] = j;
                            const int n[3] = {p[0] + q[0] * nsign, p[1] + q[1] * nsign, p[2] + q[2] * nsign};
                            mask_[j + k * du] = clave(p, g.at(p[0], p[1], p[2]), n);
                        }
                    }
                } else {
                int p[3]; p[d] = s;
                for (int k = 0; k < dv; ++k) {
                    p[v] = k;
                    for (int j = 0; j < du; ++j) {
                        p[u] = j;
                        uint32_t key = 0;
                        const uint8_t m = g.at(p[0], p[1], p[2]);
                        if (m && !(sinCristal && isGlass(m))) {
                            int n[3] = {p[0] + q[0] * nsign, p[1] + q[1] * nsign, p[2] + q[2] * nsign};
                            const uint8_t nm = g.at(n[0], n[1], n[2]);
                            const bool visible = (nm == 0) || (isGlass(nm) && !isGlass(m));
                            if (visible) key = clave(p, m, n);
                        }
                        mask_[j + k * du] = key;
                    }
                }
                }

                // --- 2. fusión greedy de rectángulos con la misma clave ---
                const float plane = static_cast<float>(s + (back ? 0 : 1));
                for (int k = 0; k < dv; ++k) {
                    if (rapido && !filaLlena[k]) continue;   // fila sin caras: nada que fundir (ni lo que bajen las de arriba)
                    for (int j = 0; j < du;) {
                        const uint32_t key = mask_[j + k * du];
                        if (!key) { ++j; continue; }
                        int w = 1;
                        while (j + w < du && mask_[j + w + k * du] == key) ++w;
                        int h = 1;
                        for (bool ok = true; ok && k + h < dv; ) {
                            for (int t = 0; t < w; ++t) if (mask_[j + t + (k + h) * du] != key) { ok = false; break; }
                            if (ok) ++h;
                        }

                        // --- 3. emitir quad ---
                        const bool porGrupo = (key & 0x80000u) != 0;
                        const uint8_t mat = porGrupo ? matAt_[j + k * du] : static_cast<uint8_t>(key & 0xFF);
                        const uint32_t ao = (key >> 8) & 0xFF;
                        const uint32_t base = static_cast<uint32_t>(out.verts.size());
                        float c0[3], c1[3], c2[3], c3[3];
                        c0[d] = c1[d] = c2[d] = c3[d] = plane;
                        c0[u] = static_cast<float>(j);     c0[v] = static_cast<float>(k);
                        c1[u] = static_cast<float>(j + w); c1[v] = static_cast<float>(k);
                        c2[u] = static_cast<float>(j + w); c2[v] = static_cast<float>(k + h);
                        c3[u] = static_cast<float>(j);     c3[v] = static_cast<float>(k + h);
                        const float* cs4[4] = {c0, c1, c2, c3};
                        for (int i = 0; i < 4; ++i) {
                            MeshVertex mv;
                            mv.x = offset.x + cs4[i][0] * cs; mv.y = offset.y + cs4[i][1] * cs; mv.z = offset.z + cs4[i][2] * cs;
                            mv.normal = face; mv.ao = static_cast<uint8_t>((ao >> (2 * i)) & 3); mv.mat = mat; mv.flags = static_cast<uint8_t>(((key >> 18) & 1) | (((key >> 17) & 1) << 1) | (porGrupo ? 4 : 0));
                            out.verts.push_back(mv);
                        }
                        // Diagonal según AO para evitar el artefacto de gradiente cruzado.
                        const int a0 = ao & 3, a1 = (ao >> 2) & 3, a2 = (ao >> 4) & 3, a3 = (ao >> 6) & 3;
                        const bool flip = (a0 + a2) < (a1 + a3);
                        std::vector<uint32_t>& idx = isGlass(mat) ? out.idxGlass : out.idxOpaque;
                        // (0,1,2),(0,2,3) es ANTIHORARIO visto desde +normal (u x v = +d). Invertimos para
                        // caras negativas y, si el motor quiere horario, una vez más.
                        uint32_t t[6];
                        if (!flip) { t[0] = 0; t[1] = 1; t[2] = 2; t[3] = 0; t[4] = 2; t[5] = 3; }
                        else       { t[0] = 1; t[1] = 2; t[2] = 3; t[3] = 1; t[4] = 3; t[5] = 0; }
                        if ((back != 0) != clockwiseFront) { std::swap(t[1], t[2]); std::swap(t[4], t[5]); }
                        for (int i = 0; i < 6; ++i) idx.push_back(base + t[i]);
                        ++out.quads;

                        for (int hh = 0; hh < h; ++hh)
                            for (int ww = 0; ww < w; ++ww) mask_[j + ww + (k + hh) * du] = 0;
                        j += w;
                    }
                }
            }
        }
    }
}

void Mesher::downsample2x(const uint8_t* in, uint8_t* out) { downsample2xGrid(in, CHUNK_SIZE, out); }

void Mesher::downsample2xGrid(const uint8_t* in, int dim, uint8_t* out) {
    const int S = dim + 2;          // entrada con relleno
    const int H = dim / 2;          // interior de salida
    const int O = H + 2;            // salida con relleno
    auto IN = [&](int x, int y, int z) -> uint8_t { return in[(x + 1) + (y + 1) * S + (z + 1) * S * S]; };
    std::memset(out, 0, static_cast<size_t>(O) * O * O);
    for (int Z = -1; Z <= H; ++Z)
    for (int Y = -1; Y <= H; ++Y)
    for (int X = -1; X <= H; ++X) {
        // rango de voxels finos cubiertos por la celda gruesa (en la cáscara sólo hay 1 voxel de datos)
        const int x0 = X < 0 ? -1 : (X >= H ? dim : 2 * X), x1 = X < 0 ? -1 : (X >= H ? dim : 2 * X + 1);
        const int y0 = Y < 0 ? -1 : (Y >= H ? dim : 2 * Y), y1 = Y < 0 ? -1 : (Y >= H ? dim : 2 * Y + 1);
        const int z0 = Z < 0 ? -1 : (Z >= H ? dim : 2 * Z), z1 = Z < 0 ? -1 : (Z >= H ? dim : 2 * Z + 1);
        // (2026-10-20) los <= 8 solidos en una lista y el mas repetido de ellos (empate: el de id menor, como al contar
        // en una tabla de MAT_COUNT, que habia que poner a cero en cada celda y era casi todo el coste de la LOD)
        uint8_t sol[8];
        int solid = 0, samples = 0;
        for (int z = z0; z <= z1; ++z) for (int y = y0; y <= y1; ++y) for (int x = x0; x <= x1; ++x) {
            ++samples;
            const uint8_t m = IN(x, y, z);
            if (m) sol[solid++] = m;
        }
        // umbral: >= 2 de 8 (interior) mantiene paredes de 1 voxel; en la cáscara, >= la mitad
        const int need = samples >= 4 ? 2 : 1;
        if (solid < need) continue;
        int bestM = 0, bestC = 0;
        for (int i = 0; i < solid; ++i) {
            int c = 0;
            for (int k = 0; k < solid; ++k) c += sol[k] == sol[i];
            if (c > bestC || (c == bestC && sol[i] < bestM)) { bestC = c; bestM = sol[i]; }
        }
        out[(X + 1) + (Y + 1) * O + (Z + 1) * O * O] = static_cast<uint8_t>(bestM);
    }
}

void Mesher::downsample2xGridMin(const uint8_t* in, int dim, uint8_t* out) {
    const int S = dim + 2, H = dim / 2, O = H + 2;
    auto IN = [&](int x, int y, int z) -> uint8_t { return in[(x + 1) + (y + 1) * S + (z + 1) * S * S]; };
    std::memset(out, 0, static_cast<size_t>(O) * O * O);
    for (int Z = -1; Z <= H; ++Z)
    for (int Y = -1; Y <= H; ++Y)
    for (int X = -1; X <= H; ++X) {
        const int x0 = X < 0 ? -1 : (X >= H ? dim : 2 * X), x1 = X < 0 ? -1 : (X >= H ? dim : 2 * X + 1);
        const int y0 = Y < 0 ? -1 : (Y >= H ? dim : 2 * Y), y1 = Y < 0 ? -1 : (Y >= H ? dim : 2 * Y + 1);
        const int z0 = Z < 0 ? -1 : (Z >= H ? dim : 2 * Z), z1 = Z < 0 ? -1 : (Z >= H ? dim : 2 * Z + 1);
        bool all = true; uint8_t any = 0;
        for (int z = z0; z <= z1 && all; ++z) for (int y = y0; y <= y1 && all; ++y) for (int x = x0; x <= x1; ++x) {
            const uint8_t m = IN(x, y, z);
            if (!m || isGlass(m)) { all = false; break; }
            any = m;
        }
        if (all && any) out[(X + 1) + (Y + 1) * O + (Z + 1) * O * O] = any;
    }
}

} // namespace vx
