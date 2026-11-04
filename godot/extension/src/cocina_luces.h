// CocinaLuces: hornea la luz de las farolas del mapa en un volumen (ver shaders/lamparas.gdshaderinc y
// main.gd, "LAS FAROLAS COCINADAS"). Sin Godot dentro del calculo: solo la misma formula que el sombreado.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector3i.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

class CocinaLuces : public RefCounted {
    GDCLASS(CocinaLuces, RefCounted)

protected:
    static void _bind_methods();

public:
    // `datos`: 16 floats por farol (las 4 filas de lamp_datos: posicion, 1/alcance · color x energia, decaimiento ·
    // direccion del foco, cos del cono (-2 omni) · exponente del borde, encendida, especular, -).
    // Hornea, en celdas de `celda` m desde `org` (dims celdas), la luz difusa que recibe una cara que mira a cada uno de
    // los 6 ejes (+X -X +Y -Y +Z -Z), SIN la parte cercana de cada farol (peso smoothstep(r0, r1, d): esa la hace el
    // sombreado exacta). Devuelve {"a": RGBE9995 (L+X, L+Y, L+Z), "b": RGBE9995 (L-X, L-Y, L-Z), "c": RG8 (croma r, g),
    // "max": luminancia maxima}.
    Dictionary hornear(const PackedFloat32Array &datos, const Vector3 &org, float celda, const Vector3i &dims,
                       float r0, float r1, float k);
};

} // namespace godot
