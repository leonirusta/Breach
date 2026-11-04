// vxcore - Carga de mapas .vxmap
#include "vx/vx_mapfile.h"
#include "vx/vx_world.h"
#include <cstdio>
#include <cstring>

namespace vx {

namespace {
struct MemReader {
    const uint8_t* d; size_t n; size_t p = 0; bool ok = true;
    template <typename T> T rd() { T v{}; if (p + sizeof(T) > n) { ok = false; return v; } std::memcpy(&v, d + p, sizeof(T)); p += sizeof(T); return v; }
};
}

bool readFileBytes(const char* path, std::vector<uint8_t>& out) {
    FILE* f = fopen(path, "rb");
    if (!f) return false;
    fseek(f, 0, SEEK_END); const long sz = ftell(f); fseek(f, 0, SEEK_SET);
    if (sz <= 0) { fclose(f); return false; }
    out.resize(static_cast<size_t>(sz));
    const bool ok = fread(out.data(), 1, out.size(), f) == out.size();
    fclose(f);
    return ok;
}

bool readMapHeader(const uint8_t* data, size_t size, MapHeader& h) {
    MemReader r{data, size};
    if (size < 8 || std::memcmp(data, "VXMP", 4) != 0) { h.error = "no es un .vxmap"; return false; }
    r.p = 4;
    const uint32_t version = r.rd<uint32_t>();
    if (version != 1) { h.error = "version no soportada"; return false; }
    h.voxelSize = r.rd<float>();
    h.ncx = r.rd<int32_t>(); h.ncy = r.rd<int32_t>(); h.ncz = r.rd<int32_t>();
    h.origin.x = r.rd<float>(); h.origin.y = r.rd<float>(); h.origin.z = r.rd<float>();
    const uint16_t nMat = r.rd<uint16_t>();
    h.materials.clear();
    for (int i = 0; i < nMat; ++i) {
        Material m; std::memset(&m, 0, sizeof(m));
        m.r = r.rd<uint8_t>(); m.g = r.rd<uint8_t>(); m.b = r.rd<uint8_t>(); m.strength = r.rd<uint8_t>();
        m.density = r.rd<uint16_t>(); m.flags = r.rd<uint8_t>(); m.support = r.rd<uint8_t>(); m.massQ = r.rd<uint8_t>();
        std::snprintf(m.name, sizeof(m.name), "map%d", i);
        h.materials.push_back(m);
    }
    const uint16_t nSpawn = r.rd<uint16_t>();
    h.spawns.clear();
    for (int i = 0; i < nSpawn; ++i) {
        MapSpawn s; s.pos.x = r.rd<float>(); s.pos.y = r.rd<float>(); s.pos.z = r.rd<float>(); s.yawDeg = r.rd<float>();
        h.spawns.push_back(s);
    }
    h.chunkCount = r.rd<uint32_t>();
    h.dataOffset = r.p;
    if (!r.ok) { h.error = "cabecera truncada"; return false; }
    if (h.ncx <= 0 || h.ncy <= 0 || h.ncz <= 0 || h.voxelSize <= 0.f || h.materials.size() > static_cast<size_t>(MAT_COUNT - MAT_MAP_FIRST)) { h.error = "cabecera invalida"; return false; }
    return true;
}

void applyMapMaterials(const MapHeader& h) {
    for (size_t i = 0; i < h.materials.size(); ++i) setMaterial(static_cast<uint8_t>(MAT_MAP_FIRST + i), h.materials[i]);
}

bool loadMapChunks(World& world, const uint8_t* data, size_t size, const MapHeader& h, uint64_t* voxelsOut) {
    if (world.chunksX() != h.ncx || world.chunksY() != h.ncy || world.chunksZ() != h.ncz) return false;
    MemReader r{data, size, h.dataOffset};
    uint64_t total = 0;
    for (uint32_t c = 0; c < h.chunkCount && r.ok; ++c) {
        const uint32_t idx = r.rd<uint32_t>();
        const uint32_t nRuns = r.rd<uint32_t>();
        if (!r.ok || idx >= static_cast<uint32_t>(world.numChunkSlots())) return false;
        if (r.p + static_cast<size_t>(nRuns) * 3 > size) return false;
        const uint8_t* runs = data + r.p;
        r.p += static_cast<size_t>(nRuns) * 3;
        const IVec3 cc = world.chunkCoords(static_cast<int>(idx));
        Chunk* ch = world.getOrCreateChunk(cc.x, cc.y, cc.z);
        if (!ch) return false;
        int pos = 0; uint32_t solid = 0;
        for (uint32_t k = 0; k < nRuns; ++k) {
            const int len = runs[k * 3] | (runs[k * 3 + 1] << 8);
            const uint8_t val = runs[k * 3 + 2];
            if (pos + len > CHUNK_VOLUME) return false;
            if (val) { std::memset(ch->vox + pos, val, len); solid += len; }
            pos += len;
        }
        ch->solidCount = solid;
        ch->bumpVersion(true);   // ocupación jerárquica + espejos atómicos
        world.markDirty(*ch);
        total += solid;
    }
    if (voxelsOut) *voxelsOut = total;
    return r.ok;
}

} // namespace vx
