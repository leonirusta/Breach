// AnimMuestreo: el muestreo de los clips horneados de los muñecos (avatar_animator.gd), en C++.
//
// Con 9 bots en la cafeteria, muestrear el clip hueso a hueso en GDScript (buscar el fotograma, slerp, mezcla con el
// clip anterior y set_bone_pose_rotation de ~28 huesos) eran ~1,2 ms por fotograma en este PC, y en un movil varias
// veces eso. Aqui hace exactamente lo mismo que ese bucle (las mismas funciones de Quaternion de Godot) en una llamada.
// Lo que solo toca a unos pocos huesos (la zancada elastica, el codo recto) sigue en GDScript, despues.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

namespace godot {

class AnimMuestreo : public RefCounted {
    GDCLASS(AnimMuestreo, RefCounted)

protected:
    static void _bind_methods();

public:
    // ids[s]: el hueso del esqueleto de la casilla s (-1 = este muñeco no lo tiene).
    // qa: cuaterniones del clip, [fotograma][casilla][x, y, z, w]; ma[s] != 0 si el clip trae la casilla s.
    // ia / wa: el fotograma y el peso hacia el siguiente (wa == 0: ese fotograma tal cual).
    // Si mezcla: igual con el clip anterior (qb, mb, ib, wb) y luego slerp(anterior, actual, bw), solo en las casillas
    // que traen los dos (como el GDScript: si el actual no trae el hueso, no se toca; si el anterior no lo trae, el
    // actual tal cual). Devuelve cuantos huesos ha puesto.
    int posar(Skeleton3D *sk, const PackedInt32Array &ids,
              const PackedFloat32Array &qa, const PackedByteArray &ma, int ia, float wa,
              bool mezcla, const PackedFloat32Array &qb, const PackedByteArray &mb, int ib, float wb, float bw);
};

} // namespace godot
