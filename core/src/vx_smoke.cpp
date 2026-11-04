// vxcore - Humo que choca con los voxels
#include "vx/vx_smoke.h"
#include "vx/vx_world.h"
#include <algorithm>
#include <cmath>

namespace vx {

void SmokeSystem::setCapacity(int n) {
    if (n < 0) n = 0;
    items_.resize(n);
    if (count_ > n) count_ = n;
    cursor_ = 0;
}

void SmokeSystem::emit(int count, const Vec3& center, float radius, float speed, const uint8_t rgb[3], float life, float r0, float r1, float buoy, Rng& rng, const World* world) {
    const int cap = capacity();
    if (cap == 0 || count <= 0) return;
    for (int i = 0; i < count; ++i) {
        Vec3 dir(rng.range(-1.f, 1.f), rng.range(-0.3f, 1.f), rng.range(-1.f, 1.f));
        dir = normalize(dir);
        Smoke s;
        s.pos = center + dir * (radius * rng.range(0.1f, 1.0f));
        if (world && isSolid(world->getVoxelAt(s.pos))) {
            // nace dentro de algo (borde del cráter): buscar aire hacia fuera y, si no, hacia arriba
            bool ok = false;
            for (int k = 1; k <= 8 && !ok; ++k) {
                const Vec3 q = center + dir * (radius * (1.f + k * 0.35f));
                if (!isSolid(world->getVoxelAt(q))) { s.pos = q; ok = true; }
            }
            for (int k = 1; k <= 12 && !ok; ++k) {
                const Vec3 q = center + Vec3(0, k * 0.3f, 0);
                if (!isSolid(world->getVoxelAt(q))) { s.pos = q; ok = true; }
            }
            if (!ok) continue;
        }
        s.vel = dir * (speed * rng.range(0.3f, 1.0f));
        s.vel.y += speed * 0.25f;
        s.age = 0.f;
        s.life = life * rng.range(0.75f, 1.3f);
        s.r0 = r0 * rng.range(0.7f, 1.3f);
        s.r1 = r1 * rng.range(0.8f, 1.3f);
        s.alpha = rng.range(0.8f, 1.0f);
        s.buoy = buoy * rng.range(0.6f, 1.4f);
        s.col[0] = rgb[0]; s.col[1] = rgb[1]; s.col[2] = rgb[2];
        s.enclosed = 1;
        s.seed = static_cast<uint16_t>(rng.next() & 0xFFFF);
        s.probeT = rng.range(0.f, 0.5f);
        if (count_ < cap) items_[count_++] = s;
        else { items_[cursor_] = s; cursor_ = (cursor_ + 1) % cap; }
    }
}

void SmokeSystem::update(float dt, const World& world) {
    if (dt <= 0) return;
    windT_ += dt;
    const float windX = std::sin(windT_ * 0.37f) * 0.25f + 0.35f;
    const float windZ = std::cos(windT_ * 0.23f) * 0.25f;
    for (int i = 0; i < count_;) {
        Smoke& s = items_[i];
        s.age += dt;
        if (s.age >= s.life || s.pos.y < -2.f) { items_[i] = items_[--count_]; continue; }
        const float t = s.age / s.life;
        // sonda de techo cada 0,5 s: con cielo abierto la partícula se disipa antes y la mueve el viento
        s.probeT -= dt;
        if (s.probeT <= 0.f) {
            s.probeT = 0.5f;
            RayHit h;
            const bool roof = world.raycast(s.pos, Vec3(0, 1, 0), 30.f, h);   // naves y hangares son altos
            if (roof && !s.enclosed) s.enclosed = 1;
            if (!roof && s.enclosed) s.enclosed = 0;
        }
        if (!s.enclosed) {
            // al aire libre: se disuelve al doble de velocidad y el viento la arrastra
            s.age += dt;
            s.vel.x += (windX - s.vel.x) * 0.6f * dt;
            s.vel.z += (windZ - s.vel.z) * 0.6f * dt;
        }
        // empuje térmico (decae con la edad), rozamiento y turbulencia suave determinista
        s.vel.y += s.buoy * (1.f - t) * dt;
        const float drag = std::exp(-1.6f * dt);
        s.vel.x *= drag; s.vel.y *= drag; s.vel.z *= drag;
        const float ph = s.seed * 0.0031f;
        s.vel.x += std::sin(s.age * 1.7f + ph) * 0.25f * dt;
        s.vel.z += std::cos(s.age * 1.3f + ph * 1.7f) * 0.25f * dt;
        // movimiento eje a eje con lectura de voxel: el humo no atraviesa nada
        const float r = std::min(radiusOf(s) * 0.35f, 0.45f);   // el "cuerpo" sólido de la nube es menor que su radio visual
        Vec3 np = s.pos;
        const bool stuck = isSolid(world.getVoxelAt(np));   // dentro de un voxel (p. ej. el bloque se movió encima): sube libre
        if (stuck) { s.vel.y = std::max(s.vel.y, 1.5f); s.pos = np + s.vel * dt; ++i; continue; }
        for (int a = 0; a < 3; ++a) {
            const float step = s.vel[a] * dt;
            if (step == 0.f) continue;
            Vec3 test = np;
            test[a] = np[a] + step + (step > 0 ? r : -r);
            if (isSolid(world.getVoxelAt(test))) {
                if (a == 1 && step > 0) {
                    // techo: se aplana y se extiende a los lados (sale por donde puede)
                    s.vel.y = 0.f;
                    const float spread = 0.35f;
                    s.vel.x += (((s.seed & 1) ? 1.f : -1.f) * std::cos(ph)) * spread * dt * 4.f;
                    s.vel.z += (((s.seed & 2) ? 1.f : -1.f) * std::sin(ph)) * spread * dt * 4.f;
                } else {
                    s.vel[a] = -s.vel[a] * 0.1f;
                }
            } else np[a] = np[a] + step;
        }
        s.pos = np;
        ++i;
    }
}

} // namespace vx
