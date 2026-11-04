#include "bot_motor.h"
#include "voxel_world.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/dictionary.hpp>

using namespace godot;

void BotMotor::_bind_methods() {
    ClassDB::bind_method(D_METHOD("bloqueado", "mundo", "p", "agachado"), &BotMotor::bloqueado);
    ClassDB::bind_method(D_METHOD("mover", "mundo", "pos", "vel", "dt", "k_agua", "agachado"), &BotMotor::mover);
    ClassDB::bind_method(D_METHOD("abanico", "mundo", "pos", "dir", "paso", "lado", "agachado"), &BotMotor::abanico);
}

bool BotMotor::_caja(const VoxelWorld *w, const Vector3 &p, bool agachado) {
    return w->box_solid(p + Vector3(-RADIO, 0.5f, -RADIO), p + Vector3(RADIO, agachado ? 1.1f : 1.6f, RADIO));
}

bool BotMotor::bloqueado(Object *mundo, const Vector3 &p, bool agachado) const {
    const VoxelWorld *w = Object::cast_to<VoxelWorld>(mundo);
    return w ? _caja(w, p, agachado) : false;
}

Array BotMotor::mover(Object *mundo, const Vector3 &pos, const Vector3 &vel_in, double dt, double k_agua, bool agachado) const {
    Array out;
    VoxelWorld *w = Object::cast_to<VoxelWorld>(mundo);
    Vector3 p = pos;
    Vector3 vel = vel_in;
    bool en_suelo = false;
    if (w) {
        // los dos ejes por separado, como el GDScript: chocar en X no frena el avance en Z
        Vector3 np = p + Vector3(static_cast<real_t>(static_cast<double>(vel.x) * dt * k_agua), 0, 0);
        if (_caja(w, np, agachado)) vel.x = 0.0f;
        else p = np;
        np = p + Vector3(0, 0, static_cast<real_t>(static_cast<double>(vel.z) * dt * k_agua));
        if (_caja(w, np, agachado)) vel.z = 0.0f;
        else p = np;
        p.y = static_cast<real_t>(static_cast<double>(p.y) + static_cast<double>(vel.y) * dt);
        // el suelo desde la cadera, con los trozos que caen (raycast_con_piezas: el mismo que usaba el GDScript)
        const Vector3 ojo_pies = p + Vector3(0, 0.9f, 0);
        Vector3 suelo;
        if (w->suelo_con_piezas(ojo_pies, 3.5f, suelo)) {
            const double gy = suelo.y;
            const double py = p.y;
            if (static_cast<double>(vel.y) <= 0.0 && py <= gy + 0.03 && py >= gy - 0.6) {
                p.y = static_cast<real_t>(gy);    // apoyado (o subiendo un escalon de hasta 0,6 m)
                vel.y = 0.0f;
                en_suelo = true;
            }
        }
    }
    out.push_back(p);
    out.push_back(vel);
    out.push_back(en_suelo);
    return out;
}

Vector3 BotMotor::abanico(Object *mundo, const Vector3 &pos, const Vector3 &dir, double paso, double lado, bool agachado) const {
    const VoxelWorld *w = Object::cast_to<VoxelWorld>(mundo);
    if (!w) return dir;
    const double base_a = Math::atan2(static_cast<double>(dir.z), static_cast<double>(dir.x));
    for (int k = 0; k < 5; ++k) {
        const double giro = Math::deg_to_rad(20.0 * static_cast<double>(k + 1));
        const double lados[2] = {lado, -lado};
        for (double l : lados) {
            const double a = base_a + giro * l;
            const Vector3 cand(static_cast<real_t>(Math::cos(a)), 0.0f, static_cast<real_t>(Math::sin(a)));
            if (!_caja(w, pos + cand * static_cast<real_t>(paso), agachado)) return cand;
        }
    }
    return dir;
}
