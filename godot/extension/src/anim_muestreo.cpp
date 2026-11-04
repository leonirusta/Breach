// Ver anim_muestreo.h
#include "anim_muestreo.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/quaternion.hpp>

using namespace godot;

void AnimMuestreo::_bind_methods() {
    ClassDB::bind_method(D_METHOD("posar", "skeleton", "ids", "qa", "ma", "ia", "wa", "mezcla", "qb", "mb", "ib", "wb", "bw"),
                         &AnimMuestreo::posar);
}

// El fotograma i (y el siguiente con peso w) de la casilla s, como _muestra_con de avatar_animator.gd
static inline Quaternion muestra(const float *q, int64_t nq, int ns, int s, int i, float w) {
    const int64_t a = (static_cast<int64_t>(i) * ns + s) * 4;
    if (a < 0 || a + 3 >= nq) return Quaternion();
    const Quaternion qa(q[a], q[a + 1], q[a + 2], q[a + 3]);
    if (w <= 0.0f) return qa;
    const int64_t b = a + static_cast<int64_t>(ns) * 4;
    if (b + 3 >= nq) return qa;
    const Quaternion qb(q[b], q[b + 1], q[b + 2], q[b + 3]);
    return qa.slerp(qb, w);
}

int AnimMuestreo::posar(Skeleton3D *sk, const PackedInt32Array &ids,
                        const PackedFloat32Array &qa, const PackedByteArray &ma, int ia, float wa,
                        bool mezcla, const PackedFloat32Array &qb, const PackedByteArray &mb, int ib, float wb, float bw) {
    if (sk == nullptr) return 0;
    const int ns = static_cast<int>(ids.size());
    if (ns == 0 || ma.size() < ns) return 0;
    const int32_t *pid = ids.ptr();
    const uint8_t *pma = ma.ptr();
    const float *pqa = qa.ptr();
    const int64_t nqa = qa.size();
    const bool conB = mezcla && mb.size() >= ns && qb.size() > 0;
    const uint8_t *pmb = conB ? mb.ptr() : nullptr;
    const float *pqb = conB ? qb.ptr() : nullptr;
    const int64_t nqb = conB ? qb.size() : 0;
    const int nhuesos = sk->get_bone_count();
    int puestos = 0;
    for (int s = 0; s < ns; ++s) {
        const int hueso = pid[s];
        if (hueso < 0 || hueso >= nhuesos || pma[s] == 0) continue;
        Quaternion q = muestra(pqa, nqa, ns, s, ia, wa);
        if (conB && pmb[s] != 0) {
            const Quaternion p = muestra(pqb, nqb, ns, s, ib, wb);
            q = p.slerp(q, bw);
        }
        sk->set_bone_pose_rotation(hueso, q);
        ++puestos;
    }
    return puestos;
}
