// vxbenchstruct - Benchmarks repetibles del sistema estructural y de los rayos (Fase 33)
// ---------------------------------------------------------------------------
// Uso: vxbenchstruct [--sizes 10k,100k,1m,4m] [--rays N] [--threads N] [--json ruta]
//
// Estructural: por tamaño, un bloque de edificios de muros + forjados con ~N voxels; se vuela la planta baja
// de uno con cohetes y se mide: iteraciones, ms por iteración (media/máx), escaneo, celdas, fragmentos,
// tiempo total hasta estabilizar, solve de conectividad y extracción.
// Rayos: N rayos aleatorios sobre la ciudad procedural: jerárquico vs voxel a voxel (ms, pasos, saltos).
// ---------------------------------------------------------------------------
#include "vx/vx_engine.h"
#include "vx/vx_citygen.h"
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include <cmath>

using namespace vx;

namespace {

struct StructResultB { std::string label; uint64_t voxels; double buildMs, totalMs, itAvg, itMax, scanAvg, solveAvg, solveMax, extractAvg; int iterations, failures, fragments, pieces, bodies; float remaining; };

void ground(World& w) { w.fillBox(IVec3(0, 0, 0), IVec3(w.sizeX() - 1, 0, w.sizeZ() - 1), MAT_GROUND); }

// edificio de muros de 1 voxel + forjados, `floors` plantas de 12 voxels, base wx x wz
void building(World& w, int x0, int z0, int wx, int wz, int floors) {
    const int top = 1 + floors * 12;
    w.fillBox(IVec3(x0, 1, z0), IVec3(x0 + wx - 1, top, z0), MAT_BRICK);
    w.fillBox(IVec3(x0, 1, z0 + wz - 1), IVec3(x0 + wx - 1, top, z0 + wz - 1), MAT_BRICK);
    w.fillBox(IVec3(x0, 1, z0), IVec3(x0, top, z0 + wz - 1), MAT_BRICK);
    w.fillBox(IVec3(x0 + wx - 1, 1, z0), IVec3(x0 + wx - 1, top, z0 + wz - 1), MAT_BRICK);
    for (int f = 1; f <= floors; ++f) w.fillBox(IVec3(x0, 1 + f * 12, z0), IVec3(x0 + wx - 1, 1 + f * 12, z0 + wz - 1), MAT_CONCRETE);
    // tabique interior (pladur) cruzado: como en la ciudad procedural
    w.fillBox(IVec3(x0 + wx / 2, 2, z0 + 1), IVec3(x0 + wx / 2, top, z0 + wz - 2), MAT_DRYWALL);
}

uint64_t countBox(const World& w, IVec3 a, IVec3 b) {
    uint64_t n = 0;
    for (int z = a.z; z <= b.z; ++z) for (int y = a.y; y <= b.y; ++y) for (int x = a.x; x <= b.x; ++x) { const uint8_t m = w.getVoxel(x, y, z); if (m && !isAnchor(m)) ++n; }
    return n;
}

StructResultB runStruct(const char* label, uint64_t targetVoxels, int threads) {
    // tamaño del edificio: muros 40x40 (10 m) de 3 plantas ~ 4 x (40x37) + 3 x 1600 ≈ 10.700 voxels
    // se escala en número de edificios (rejilla) y en plantas para llegar a targetVoxels
    int floors = 3, side = 40;
    int nb = 1;
    if (targetVoxels >= 4000000) { floors = 8; side = 60; nb = 6; }
    else if (targetVoxels >= 1000000) { floors = 6; side = 60; nb = 4; }
    else if (targetVoxels >= 100000) { floors = 4; side = 48; nb = 2; }
    const int pitch = side + 12;
    const int cx = (nb * pitch + 40) / CHUNK_SIZE + 1, cy = (1 + floors * 12) / CHUNK_SIZE + 2, cz = cx;
    EngineConfig cfg; cfg.chunksX = cx; cfg.chunksY = cy; cfg.chunksZ = cz; cfg.threads = threads; cfg.quality = Quality::High; cfg.loadModel = true;
    Engine e(cfg); World& w = e.world();
    Timer tb;
    ground(w);
    for (int i = 0; i < nb; ++i) for (int j = 0; j < nb; ++j) building(w, 20 + i * pitch, 20 + j * pitch, side, side, floors);
    w.clearPristine(); e.markAllDirty(); e.waitIdle();
    StructResultB r{}; r.label = label; r.buildMs = tb.ms();
    r.voxels = w.solidVoxels() - static_cast<uint64_t>(w.sizeX()) * w.sizeZ();
    const IVec3 bmn(20, 1, 20), bmx(20 + side - 1, 1 + floors * 12, 20 + side - 1);
    const uint64_t before = countBox(w, bmn, bmx);
    e.statsMutable() = Stats{};
    Timer t;
    const float ccx = (20 + side * 0.5f) * 0.25f, ccz = ccx;
    for (int k = 0; k < 5; ++k) { const float a = 6.2832f * k / 5; e.explode(Vec3(ccx + std::cos(a) * (side * 0.125f - 0.1f), 1.6f, ccz + std::sin(a) * (side * 0.125f - 0.1f)), 3.5f, 255); }
    std::vector<VoxelBody> pieces;
    e.waitIdle(nullptr, &pieces);
    r.totalMs = t.ms();
    const Stats& s = e.stats();
    r.itAvg = s.tStruct.avg; r.itMax = s.tStruct.max; r.scanAvg = s.tStructScan.avg;
    r.solveAvg = s.tSolve.avg; r.solveMax = s.tSolve.max; r.extractAvg = s.tExtract.avg;
    r.iterations = s.structIterationsTotal; r.failures = s.structFailuresTotal; r.fragments = s.structFragmentsTotal;
    r.pieces = static_cast<int>(pieces.size()); r.bodies = s.bodiesCreatedTotal;
    r.remaining = before ? static_cast<float>(countBox(w, bmn, bmx)) / before : 1.f;
    return r;
}

struct RayResultB { int rays; double hierMs, bruteMs; uint64_t steps, skips, bruteSteps; int hits; };

RayResultB runRays(int n, int threads) {
    EngineConfig cfg; cfg.chunksX = 20; cfg.chunksY = 4; cfg.chunksZ = 20; cfg.threads = threads; cfg.quality = Quality::High;
    Engine e(cfg); World& w = e.world();
    CityInfo info; CityParams cp;
    generateCity(w, 1234, cp, info);
    Rng rng(99);
    std::vector<Vec3> o(n), d(n);
    const Vec3 size = w.sizeMeters();
    for (int i = 0; i < n; ++i) {
        o[i] = Vec3(rng.range(0.f, size.x), rng.range(0.5f, size.y * 0.6f), rng.range(0.f, size.z));
        Vec3 dd(rng.range(-1.f, 1.f), rng.range(-0.5f, 0.5f), rng.range(-1.f, 1.f));
        d[i] = length2(dd) < 1e-4f ? Vec3(1, 0, 0) : normalize(dd);
    }
    RayResultB r{}; r.rays = n;
    RayHit h;
    const uint64_t s0 = w.raySteps(), k0 = w.raySkips();
    Timer t;
    for (int i = 0; i < n; ++i) if (w.raycast(o[i], d[i], 120.f, h)) ++r.hits;
    r.hierMs = t.ms();
    r.steps = w.raySteps() - s0; r.skips = w.raySkips() - k0;
    t.reset();
    for (int i = 0; i < n; ++i) w.raycastBrute(o[i], d[i], 120.f, h);
    r.bruteMs = t.ms();
    // pasos del bruto: estimación por rayo (la referencia no cuenta)
    r.bruteSteps = 0;
    return r;
}

} // namespace

int main(int argc, char** argv) {
    std::vector<std::pair<std::string, uint64_t>> sizes = {{"10k", 10000}, {"100k", 100000}, {"1M", 1000000}, {"4M", 4000000}};
    int rays = 100000, threads = 0;
    std::string json;
    for (int i = 1; i < argc; ++i) {
        std::string s = argv[i];
        auto next = [&](int k) { return (i + k < argc) ? std::string(argv[i + k]) : std::string(); };
        if (s == "--sizes") { sizes.clear(); std::string v = next(1); ++i; size_t p = 0; while (p <= v.size()) { size_t q = v.find(',', p); if (q == std::string::npos) q = v.size(); std::string tok = v.substr(p, q - p); uint64_t n = 0; if (tok == "10k") n = 10000; else if (tok == "100k") n = 100000; else if (tok == "1m" || tok == "1M") n = 1000000; else if (tok == "4m" || tok == "4M") n = 4000000; if (n) sizes.push_back({tok, n}); p = q + 1; } }
        else if (s == "--rays") { rays = std::stoi(next(1)); ++i; }
        else if (s == "--threads") { threads = std::stoi(next(1)); ++i; }
        else if (s == "--json") { json = next(1); ++i; }
        else { printf("Argumento desconocido: %s\n", s.c_str()); return 2; }
    }
    printf("vxbenchstruct  voxel 0.25 m  hilos %d\n\n", threads);
    printf("%-6s %10s %9s %10s %8s %8s %8s %6s %8s %8s %8s %6s\n", "tam", "voxels", "gen ms", "total ms", "it avg", "it max", "scan", "iters", "fallos", "solve", "solveMx", "queda");
    std::vector<StructResultB> results;
    for (auto& sz : sizes) {
        StructResultB r = runStruct(sz.first.c_str(), sz.second, threads);
        printf("%-6s %10llu %9.1f %10.1f %8.2f %8.2f %8.2f %6d %8d %8.3f %8.3f %6.2f\n", r.label.c_str(), (unsigned long long)r.voxels, r.buildMs, r.totalMs, r.itAvg, r.itMax, r.scanAvg, r.iterations, r.failures, r.solveAvg, r.solveMax, r.remaining);
        results.push_back(r);
    }
    RayResultB rr = runRays(rays, threads);
    printf("\nRayos (%d, ciudad 160x32x160 m, alcance 120 m): jerarquico %.1f ms (%.2f us/rayo) | voxel a voxel %.1f ms (%.2f us/rayo) | x%.1f | pasos/rayo %.1f saltos/rayo %.1f | impactos %d\n",
           rr.rays, rr.hierMs, rr.hierMs * 1000.0 / rr.rays, rr.bruteMs, rr.bruteMs * 1000.0 / rr.rays, rr.bruteMs / std::max(0.001, rr.hierMs), static_cast<double>(rr.steps) / rr.rays, static_cast<double>(rr.skips) / rr.rays, rr.hits);
    if (!json.empty()) {
        FILE* f = fopen(json.c_str(), "wb");
        if (f) {
            fprintf(f, "{\n  \"struct\": [\n");
            for (size_t i = 0; i < results.size(); ++i) {
                const StructResultB& r = results[i];
                fprintf(f, "    {\"size\":\"%s\",\"voxels\":%llu,\"genMs\":%.2f,\"totalMs\":%.2f,\"itAvg\":%.3f,\"itMax\":%.3f,\"scanAvg\":%.3f,\"iterations\":%d,\"failures\":%d,\"fragments\":%d,\"pieces\":%d,\"solveAvg\":%.4f,\"solveMax\":%.4f,\"remaining\":%.4f}%s\n",
                        r.label.c_str(), (unsigned long long)r.voxels, r.buildMs, r.totalMs, r.itAvg, r.itMax, r.scanAvg, r.iterations, r.failures, r.fragments, r.pieces, r.solveAvg, r.solveMax, r.remaining, i + 1 < results.size() ? "," : "");
            }
            fprintf(f, "  ],\n  \"rays\": {\"n\":%d,\"hierMs\":%.3f,\"bruteMs\":%.3f,\"steps\":%llu,\"skips\":%llu,\"hits\":%d}\n}\n", rr.rays, rr.hierMs, rr.bruteMs, (unsigned long long)rr.steps, (unsigned long long)rr.skips, rr.hits);
            fclose(f);
            printf("JSON escrito en %s\n", json.c_str());
        }
    }
    return 0;
}
