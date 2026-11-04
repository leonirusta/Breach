// BotMotor: el paso de movimiento de los bots (enemy.gd `_voxel_move`, `_blocked_at`, `_rodear`), en C++.
//
// Los bots no andan con la fisica de Godot: leen voxels. En cada paso de fisica, y por cada bot, el GDScript hacia
// varias llamadas al motor (la caja del cuerpo en X, en Z, el rayo de suelo con los escombros) y las cuentas entre
// ellas. Aqui va todo en una llamada, con las MISMAS operaciones y en el mismo orden (se comprueba con --botmotorprueba).
// Las cuentas sueltas van en double y los vectores en float, como en GDScript (asi los redondeos son los mismos).
// Registrada aparte (como AnimMuestreo) para no tocar el tamaño de VoxelWorld.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class VoxelWorld;

class BotMotor : public RefCounted {
    GDCLASS(BotMotor, RefCounted)

protected:
    static void _bind_methods();

public:
    static constexpr float RADIO = 0.3f;     // enemy.gd BOT_RADIUS

    // La caja del cuerpo en `p` (pies): 0,5 m sobre el suelo hasta 1,6 (1,1 agachado), radio RADIO (enemy._blocked_at).
    bool bloqueado(Object *mundo, const Vector3 &p, bool agachado) const;

    // Un paso: X, luego Z (cada eje se anula si choca), la caida y el suelo bajo los pies mirando los escombros.
    // Devuelve [pos, vel, en_suelo]. `k_agua` multiplica el avance horizontal (0,55 nadando).
    Array mover(Object *mundo, const Vector3 &pos, const Vector3 &vel, double dt, double k_agua, bool agachado) const;

    // El abanico de `_rodear` (ya sabiendo que la direccion recta esta tapada): 20, 40... 100 grados a `lado` y al otro.
    // Devuelve la primera direccion libre o `dir` si no hay ninguna.
    Vector3 abanico(Object *mundo, const Vector3 &pos, const Vector3 &dir, double paso, double lado, bool agachado) const;

private:
    static bool _caja(const VoxelWorld *w, const Vector3 &p, bool agachado);
};

} // namespace godot
