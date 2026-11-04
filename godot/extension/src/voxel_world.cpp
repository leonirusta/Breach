// VoxelWorld - implementación
#include "voxel_world.h"
#include "vx/vx_mapfile.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/display_server.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/classes/base_material3d.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/classes/texture2d_array.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/rendering_device.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/camera3d.hpp>
#include <godot_cpp/classes/viewport.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector4.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/array.hpp>

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <unordered_map>
#include <unordered_set>
#include <cstdio>
#include <cstring>

using namespace godot;

// LA CAPA DEL MUNDO (2026-10-01, farolas cocinadas). Las mallas de voxels (regiones, LOD, bloques, grupos) van en la
// capa visual 11 y no en la 1: asi las farolas del mapa (Light3D de Godot) pueden dejar de alumbrarlas con su
// `light_cull_mask` -el mundo las lleva cocinadas en su sombreado (shaders/lamparas.gdshaderinc)- y seguir alumbrando a
// personajes, armas y objetos. Las camaras ven todas las capas, asi que no cambia nada mas.
static constexpr uint32_t CAPA_MUNDO = 1u << 10;
// Capas de FÍSICA. El mundo y los bloques congelados usan la capa 1; los
// escombros que aún se mueven usan una capa exclusiva. Así Jolt no genera
// pares escombro-escombro (la causa típica de picos al derrumbar un edificio),
// pero siguen chocando con mundo, jugador y bots. Al asentarse vuelven a ser
// escenario. Las balas hacen raycast voxel y no necesitan una capa física.
static constexpr uint32_t CAPA_ESCOMBRO_MOVIL = 1u << 4; // capa 5 de Godot
static constexpr uint32_t CAPA_JUGADOR = 1u << 1;         // capa 2
static constexpr uint32_t CAPA_BOT = 1u << 2;             // capa 3
static constexpr uint32_t MASCARA_ESCOMBRO_MOVIL = CAPA_JUGADOR | CAPA_BOT | 1u;
static constexpr uint32_t MASCARA_ESCENARIO = CAPA_JUGADOR | CAPA_BOT;

namespace {
inline Vector3 toGd(const vx::Vec3& v) { return Vector3(v.x, v.y, v.z); }
inline vx::Vec3 toVxV(const Vector3& v) { return vx::Vec3(v.x, v.y, v.z); }
static bool g_aoCerca = true;   // se guarda: el motor puede no existir aun (se aplica al crearlo, antes de mallar)
// Color de material en espacio lineal (tabla precalculada; se rehace al cambiar de mapa).
Color g_matLinear[vx::MAT_COUNT];
float g_matAlfa[vx::MAT_COUNT];
// COLOR POR TEXTURA: el grupo de cada material (el byte de su alfa de vertice: familia de textura, emisivo, follaje).
// Dos materiales del mismo grupo se dibujan con el mismo sombreado salvo el color, que sale de la textura.
uint8_t g_grupoColor[vx::MAT_COUNT];
bool g_matLinearInit = false;

// LAS TEXTURAS DE DETALLE (2026-09-30, pedido: "texturas de madera, etc."). Solo DIBUJO: ni red, ni fisica, ni
// determinismo. Cada material cae en una FAMILIA, que es una capa de godot/texturas/voxel_detalle.png (el orden lo
// comparten tools/generar_texturas_voxel.py y voxel.gdshader). El .vxmap no trae nombres de material, solo color y
// fisica, asi que la familia se DEDUCE de la densidad, el soporte, las banderas y el color: cada tipo de los
// generadores (tela 300, madera 600, organico 1000, tierra 1600, ladrillo 1900, hormigon 2400, piedra 2500, metal
// 7000+, suelos anclados...) tiene su firma, y lo que la fisica no separa (revoque pintado con fisica de ladrillo,
// asfalto de tipo piedra) lo separa el color.
enum FamiliaTextura : int {
    FT_NINGUNA = -1, FT_MADERA = 0, FT_LADRILLO, FT_TEJA, FT_PIEDRA, FT_HORMIGON, FT_REVOQUE, FT_METAL, FT_BALDOSA,
    FT_TELA, FT_VEGETACION, FT_TIERRA, FT_CRISTAL, FT_ASFALTO,
};

int familiaTextura(int id, const vx::Material& m) {
    if (id == vx::MAT_AIR || (m.flags & vx::MF_EMISSIVE)) return FT_NINGUNA;
    if (m.flags & vx::MF_GLASS) return FT_CRISTAL;
    switch (id) {   // los integrados (ciudad procedural): por nombre
        case vx::MAT_GROUND: case vx::MAT_RUBBLE: return FT_PIEDRA;
        case vx::MAT_ASPHALT: return FT_ASFALTO;
        case vx::MAT_PAVEMENT: return FT_BALDOSA;
        case vx::MAT_CONCRETE: return FT_HORMIGON;
        case vx::MAT_BRICK: case vx::MAT_REDBRICK: return FT_LADRILLO;
        case vx::MAT_WOOD: return FT_MADERA;
        case vx::MAT_DRYWALL: case vx::MAT_PLASTER: return FT_REVOQUE;
        case vx::MAT_METAL: case vx::MAT_DARKMETAL: return FT_METAL;
        case vx::MAT_ROOF: return FT_TEJA;
        case vx::MAT_GRASS: return FT_VEGETACION;
        default: break;
    }
    // luminosidad y saturacion (HSL) del color sRGB
    const float r = m.r / 255.f, g = m.g / 255.f, b = m.b / 255.f;
    const float mx = std::max({r, g, b}), mn = std::min({r, g, b});
    const float l = 0.5f * (mx + mn);
    const float den = 1.f - std::fabs(2.f * l - 1.f);
    const float s = den > 1e-4f ? (mx - mn) / den : 0.f;
    const bool verde = m.g > m.r + 12 && m.g > m.b + 8;
    if (m.density >= 5000) return FT_METAL;
    if (m.flags & vx::MF_ANCHOR) {                        // los suelos del mapa
        if (verde) return FT_VEGETACION;                  // cesped
        if (m.density <= 1700) return FT_TIERRA;          // tierra, arena, barro
        if (m.density >= 2500) return FT_PIEDRA;          // roca del terreno, la base
        return (l < 0.33f && s < 0.2f) ? FT_ASFALTO : FT_BALDOSA;   // calzada / acera, adoquin, baldosa
    }
    if (m.density <= 450) return FT_TELA;                 // tela, lona, toldos, plastico fino
    if (m.support <= 3) {                                 // blandos y sueltos
        if (m.density <= 1200) return verde ? FT_VEGETACION : FT_TELA;
        return FT_TIERRA;                                 // escombro suelto
    }
    if (m.density <= 800) return FT_MADERA;               // 600
    if (m.density < 1000) return FT_NINGUNA;              // plastico (900): liso
    if (m.density <= 1050) return FT_REVOQUE;             // yeso de Teardown (1000)
    if (m.density <= 1200) return FT_NINGUNA;             // goma (1100)
    if (m.density <= 1700) return FT_TIERRA;              // tierra, sacos (1600)
    if (m.density <= 2100)                                // ladrillo (1900): el revoque de los mapas pintados tambien
        return (l < 0.62f && m.r > m.b + 35) ? FT_LADRILLO : FT_REVOQUE;
    if (m.density < 2350) return FT_BALDOSA;              // baldosa (2300)
    if (m.density < 2450) return (s > 0.15f && l > 0.35f) ? FT_REVOQUE : FT_HORMIGON;   // 2400: fachada pintada / gris
    return (l < 0.2f && s < 0.15f) ? FT_ASFALTO : FT_PIEDRA;                           // 2500+
}

void refreshMaterialColors() {
    for (int i = 0; i < vx::MAT_COUNT; ++i) {
        const vx::Material& m = vx::material(static_cast<uint8_t>(i));
        g_matLinear[i] = Color(m.r / 255.f, m.g / 255.f, m.b / 255.f, 1.f).srgb_to_linear();
        // ALFA DEL COLOR DE VERTICE: 0,45 cristal, 0,75 emisivo (EMISSION en el shader), 0,90 FOLLAJE (se mece con el
        // viento): blando y VERDE -hojas, lianas, cactus-. El resto, opaco: (255 - k) / 255 con k = familia + 1 (0 = sin
        // textura), o sea de 1,0 a 0,949. voxel.gdshader lo deshace (ver `familia_de`).
        const bool emissive = (m.flags & vx::MF_EMISSIVE) != 0;
        const bool follaje = m.cls == vx::MaterialClass::Soft && m.g > m.r + 12 && m.g > m.b + 8;
        if (vx::isGlass(static_cast<uint8_t>(i))) g_matAlfa[i] = 0.45f;
        else if (emissive) g_matAlfa[i] = 0.75f;
        else if (follaje) g_matAlfa[i] = 0.9f;
        else g_matAlfa[i] = static_cast<float>(255 - (familiaTextura(i, m) + 1)) / 255.f;
        g_grupoColor[i] = static_cast<uint8_t>(std::lround(g_matAlfa[i] * 255.f));
    }
    g_matLinearInit = true;
}
const Color& materialLinear(uint8_t mat) {
    if (!g_matLinearInit) refreshMaterialColors();
    return g_matLinear[mat < vx::MAT_COUNT ? mat : 0];
}
float alfaVertice(uint8_t mat) {
    if (!g_matLinearInit) refreshMaterialColors();
    return g_matAlfa[mat];
}

// Donde empieza la textura de un bloque suelto (voxel.gdshader, `tex_bloque`): xyz = lo que hay que sumar al vertice
// local para tener la posicion en la rejilla de la que salio (en metros); w = 1, el shader la lee de la malla del bloque.
// Los grupos congelados llevan w = 2: la posicion ya viene hecha en la UV de cada vertice.
void ponerTexBloque(const RID& inst, const Vector3& org, float modo) {
    RenderingServer* rs = RenderingServer::get_singleton();
    if (rs && inst.is_valid()) rs->instance_geometry_set_shader_parameter(inst, "tex_bloque", Vector4(org.x, org.y, org.z, modo));
}
}

bool vx_quitar_ecoqos();   // proceso_win.cpp

VoxelWorld::VoxelWorld() {
    // SIN VENTANA (bancos, servidor), el render es de mentira y no admite crear mallas desde otro hilo ("Parameter m is
    // null" en mesh_add_surface): ahi todo se sube en el hilo principal, como antes
    asyncBlocks_ = std::getenv("VX_BLOQUES_SYNC") == nullptr
                   && !(DisplayServer::get_singleton() && DisplayServer::get_singleton()->get_name() == "headless");
    // VX_SIN_ECOQOS=1: el proceso pide a Windows que no le aplique el ahorro de energia de segundo plano (ver
    // proceso_win.cpp). Para medir con las ventanas de los bancos sin foco.
    static bool hecho = false;
    if (!hecho && std::getenv("VX_SIN_ECOQOS") != nullptr) {
        hecho = true;
        const bool ok = vx_quitar_ecoqos();
        UtilityFunctions::print(ok ? "[proceso] sin EcoQoS (power throttling apagado para este proceso)" : "[proceso] no se pudo quitar EcoQoS");
    }
}
VoxelWorld::~VoxelWorld() { stopBlockWorker(); destroyEngine(); }

void VoxelWorld::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_quality", "quality"), &VoxelWorld::set_quality);
    ClassDB::bind_method(D_METHOD("get_quality"), &VoxelWorld::get_quality);
    ClassDB::bind_method(D_METHOD("set_chunks", "chunks"), &VoxelWorld::set_chunks);
    ClassDB::bind_method(D_METHOD("get_chunks"), &VoxelWorld::get_chunks);
    ClassDB::bind_method(D_METHOD("set_seed", "seed"), &VoxelWorld::set_seed);
    ClassDB::bind_method(D_METHOD("get_seed"), &VoxelWorld::get_seed);
    ClassDB::bind_method(D_METHOD("set_auto_generate", "enabled"), &VoxelWorld::set_auto_generate);
    ClassDB::bind_method(D_METHOD("get_auto_generate"), &VoxelWorld::get_auto_generate);
    ClassDB::bind_method(D_METHOD("set_opaque_material", "material"), &VoxelWorld::set_opaque_material);
    ClassDB::bind_method(D_METHOD("get_opaque_material"), &VoxelWorld::get_opaque_material);
    ClassDB::bind_method(D_METHOD("set_glass_material", "material"), &VoxelWorld::set_glass_material);
    ClassDB::bind_method(D_METHOD("get_glass_material"), &VoxelWorld::get_glass_material);
    ClassDB::bind_method(D_METHOD("set_collision_layer", "layer"), &VoxelWorld::set_collision_layer);
    ClassDB::bind_method(D_METHOD("get_collision_layer"), &VoxelWorld::get_collision_layer);
    ClassDB::bind_method(D_METHOD("set_smoke_material", "material"), &VoxelWorld::set_smoke_material);
    ClassDB::bind_method(D_METHOD("get_smoke_debug", "n"), &VoxelWorld::get_smoke_debug);
    ClassDB::bind_method(D_METHOD("emit_smoke", "pos", "count", "radius", "speed", "color", "life", "r0", "r1", "buoy"), &VoxelWorld::emit_smoke);
    ClassDB::bind_method(D_METHOD("set_voxel_size", "meters"), &VoxelWorld::set_voxel_size);
    ClassDB::bind_method(D_METHOD("get_voxel_size"), &VoxelWorld::get_voxel_size);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "voxel_size", PROPERTY_HINT_RANGE, "0.05,1.0,0.005"), "set_voxel_size", "get_voxel_size");

    ADD_PROPERTY(PropertyInfo(Variant::INT, "quality", PROPERTY_HINT_ENUM, "Low,Medium,High,Ultra"), "set_quality", "get_quality");
    ADD_PROPERTY(PropertyInfo(Variant::VECTOR3I, "chunks"), "set_chunks", "get_chunks");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "seed"), "set_seed", "get_seed");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "auto_generate"), "set_auto_generate", "get_auto_generate");
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "opaque_material", PROPERTY_HINT_RESOURCE_TYPE, "Material"), "set_opaque_material", "get_opaque_material");
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "glass_material", PROPERTY_HINT_RESOURCE_TYPE, "Material"), "set_glass_material", "get_glass_material");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "collision_layer", PROPERTY_HINT_LAYERS_3D_PHYSICS), "set_collision_layer", "get_collision_layer");

    ClassDB::bind_method(D_METHOD("generate_city", "seed"), &VoxelWorld::generate_city);
    ClassDB::bind_method(D_METHOD("load_map", "data"), &VoxelWorld::load_map);
    ClassDB::bind_method(D_METHOD("find_ground", "position"), &VoxelWorld::find_ground);
    ClassDB::bind_method(D_METHOD("get_spawn_points"), &VoxelWorld::get_spawn_points);
    ClassDB::bind_method(D_METHOD("is_loading"), &VoxelWorld::is_loading);
    ClassDB::bind_method(D_METHOD("get_loading_progress"), &VoxelWorld::get_loading_progress);
    ClassDB::bind_method(D_METHOD("explode", "position", "radius", "power"), &VoxelWorld::explode);
    ClassDB::bind_method(D_METHOD("crater_mundo", "position", "radius", "power"), &VoxelWorld::crater_mundo);
    ClassDB::bind_method(D_METHOD("carve_beam", "origin", "direction", "length", "radius", "power", "vaporize", "empuje"), &VoxelWorld::carve_beam, DEFVAL(true), DEFVAL(Vector3()));
    ClassDB::bind_method(D_METHOD("empujar_bloques", "centro", "radio", "vel"), &VoxelWorld::empujar_bloques);
    ClassDB::bind_method(D_METHOD("set_prisa_escombros", "k"), &VoxelWorld::set_prisa_escombros);
    ClassDB::bind_method(D_METHOD("carve_body", "body", "position", "radius", "power"), &VoxelWorld::carve_body);
    ClassDB::bind_method(D_METHOD("get_effect_events"), &VoxelWorld::get_effect_events);
    ClassDB::bind_method(D_METHOD("shoot", "origin", "direction", "max_distance", "power"), &VoxelWorld::shoot);
    ClassDB::bind_method(D_METHOD("raycast", "origin", "direction", "max_distance"), &VoxelWorld::raycast);
    ClassDB::bind_method(D_METHOD("techo_filas", "datos", "tam", "x0", "x1", "za", "zb", "px", "pz", "desde", "altura"), &VoxelWorld::techo_filas);
    ClassDB::bind_method(D_METHOD("raycast_con_piezas", "origin", "direction", "max_distance"), &VoxelWorld::raycast_con_piezas);
    ClassDB::bind_method(D_METHOD("set_personajes", "posiciones"), &VoxelWorld::set_personajes);
    ClassDB::bind_method(D_METHOD("set_player_position", "position"), &VoxelWorld::set_player_position);
    ClassDB::bind_method(D_METHOD("find_path", "from", "to", "max_expansions"), &VoxelWorld::find_path, DEFVAL(-1));
    ClassDB::bind_method(D_METHOD("has_line_of_sight", "a", "b"), &VoxelWorld::has_line_of_sight);
    ClassDB::bind_method(D_METHOD("get_stats"), &VoxelWorld::get_stats);
    ClassDB::bind_method(D_METHOD("set_compress_attributes", "on"), &VoxelWorld::set_compress_attributes);
    ClassDB::bind_method(D_METHOD("set_shadow_light_dir", "dir"), &VoxelWorld::set_shadow_light_dir);
    ClassDB::bind_method(D_METHOD("set_faldas_lod", "on"), &VoxelWorld::set_faldas_lod);
    ClassDB::bind_method(D_METHOD("set_sol_horneado", "on", "dir_hacia_sol", "alcance_m"), &VoxelWorld::set_sol_horneado);
    ClassDB::bind_method(D_METHOD("audit_floaters"), &VoxelWorld::audit_floaters);
    ClassDB::bind_method(D_METHOD("set_weld_floaters", "on"), &VoxelWorld::set_weld_floaters);
    ClassDB::bind_method(D_METHOD("bodies_info"), &VoxelWorld::bodies_info);
    ClassDB::bind_method(D_METHOD("get_bodies_debug"), &VoxelWorld::get_bodies_debug);
    ClassDB::bind_method(D_METHOD("set_clump_scale", "scale"), &VoxelWorld::set_clump_scale);
    ClassDB::bind_method(D_METHOD("get_clump_scale"), &VoxelWorld::get_clump_scale);
    ClassDB::bind_method(D_METHOD("set_cheap_solid_max", "n"), &VoxelWorld::set_cheap_solid_max);
    ClassDB::bind_method(D_METHOD("set_phys_updates", "on"), &VoxelWorld::set_phys_updates);
    ClassDB::bind_method(D_METHOD("get_cheap_solid_max"), &VoxelWorld::get_cheap_solid_max);
    ClassDB::bind_method(D_METHOD("get_struct_debug"), &VoxelWorld::get_struct_debug);
    ClassDB::bind_method(D_METHOD("set_struct_debug_enabled", "enabled"), &VoxelWorld::set_struct_debug_enabled);
    ClassDB::bind_method(D_METHOD("set_occlusion_volume", "enabled"), &VoxelWorld::set_occlusion_volume);
    ClassDB::bind_method(D_METHOD("get_occlusion_volume"), &VoxelWorld::get_occlusion_volume);
    ClassDB::bind_method(D_METHOD("bind_occupancy_to_material", "material"), &VoxelWorld::bind_occupancy_to_material);
    ClassDB::bind_method(D_METHOD("get_occupancy_info"), &VoxelWorld::get_occupancy_info);
    ClassDB::bind_method(D_METHOD("set_struct_param", "name", "value"), &VoxelWorld::set_struct_param);
    ClassDB::bind_method(D_METHOD("get_struct_param", "name"), &VoxelWorld::get_struct_param);
    ClassDB::bind_method(D_METHOD("get_spawn_position"), &VoxelWorld::get_spawn_position);
    ClassDB::bind_method(D_METHOD("get_building_centers"), &VoxelWorld::get_building_centers);
    ClassDB::bind_method(D_METHOD("get_street_points"), &VoxelWorld::get_street_points);
    ClassDB::bind_method(D_METHOD("get_world_size"), &VoxelWorld::get_world_size);
    ClassDB::bind_method(D_METHOD("set_soltar_bloques", "estado_minimo"), &VoxelWorld::set_soltar_bloques);
    ClassDB::bind_method(D_METHOD("get_soltar_bloques"), &VoxelWorld::get_soltar_bloques);
    ClassDB::bind_method(D_METHOD("get_material_at", "position"), &VoxelWorld::get_material_at);
    ClassDB::bind_method(D_METHOD("get_material_info", "mat"), &VoxelWorld::get_material_info);
    ClassDB::bind_method(D_METHOD("box_solid", "min", "max"), &VoxelWorld::box_solid);
    ClassDB::bind_method(D_METHOD("contar_voxels", "min", "max"), &VoxelWorld::contar_voxels);
    ClassDB::bind_method(D_METHOD("get_material_color", "material"), &VoxelWorld::get_material_color);
    ClassDB::bind_method(D_METHOD("get_material_capa", "material"), &VoxelWorld::get_material_capa);
    ClassDB::bind_method(D_METHOD("set_debris_material", "material"), &VoxelWorld::set_debris_material);
    ClassDB::bind_method(D_METHOD("get_material_name", "material"), &VoxelWorld::get_material_name);
    ClassDB::bind_method(D_METHOD("get_body_count"), &VoxelWorld::get_body_count);
    ClassDB::bind_method(D_METHOD("set_diag_bloques", "on"), &VoxelWorld::set_diag_bloques);
    ClassDB::bind_method(D_METHOD("set_view_distance_scale", "scale"), &VoxelWorld::set_view_distance_scale);
    ClassDB::bind_method(D_METHOD("set_render_distance_scale", "scale"), &VoxelWorld::set_render_distance_scale);
    ClassDB::bind_method(D_METHOD("set_lod_distance_scale", "scale"), &VoxelWorld::set_lod_distance_scale);
    ClassDB::bind_method(D_METHOD("set_lod2_factor", "factor"), &VoxelWorld::set_lod2_factor);
    ClassDB::bind_method(D_METHOD("set_oclusion_rayos", "rayos"), &VoxelWorld::set_oclusion_rayos);
    ClassDB::bind_method(D_METHOD("set_ao_cerca", "on"), &VoxelWorld::set_ao_cerca);
    ClassDB::bind_method(D_METHOD("set_lod_fade_band", "cerca", "lejos"), &VoxelWorld::set_lod_fade_band);
    ClassDB::bind_method(D_METHOD("get_render_distance_scale"), &VoxelWorld::get_render_distance_scale);
    ClassDB::bind_method(D_METHOD("get_lod_distance_scale"), &VoxelWorld::get_lod_distance_scale);
    ClassDB::bind_method(D_METHOD("set_debris_scale", "scale"), &VoxelWorld::set_debris_scale);
    ClassDB::bind_method(D_METHOD("set_piece_gravity", "scale"), &VoxelWorld::set_piece_gravity);
    ClassDB::bind_method(D_METHOD("set_use_occluders", "enabled"), &VoxelWorld::set_use_occluders);
    ClassDB::bind_method(D_METHOD("set_structural_sleep", "seconds"), &VoxelWorld::set_structural_sleep);
    ClassDB::bind_method(D_METHOD("get_structural_sleep"), &VoxelWorld::get_structural_sleep);
    ClassDB::bind_method(D_METHOD("set_structural_load", "enabled"), &VoxelWorld::set_structural_load);
    ClassDB::bind_method(D_METHOD("get_structural_load"), &VoxelWorld::get_structural_load);
    ClassDB::bind_method(D_METHOD("set_physics_anchors", "points", "radius"), &VoxelWorld::set_physics_anchors);
    ClassDB::bind_method(D_METHOD("_on_body_state", "state", "body"), &VoxelWorld::_on_body_state);
    ClassDB::bind_method(D_METHOD("get_use_occluders"), &VoxelWorld::get_use_occluders);
    ClassDB::bind_method(D_METHOD("get_view_distance_scale"), &VoxelWorld::get_view_distance_scale);
    ClassDB::bind_method(D_METHOD("get_lod_distance"), &VoxelWorld::get_lod_distance);
    ClassDB::bind_method(D_METHOD("get_render_distance"), &VoxelWorld::get_render_distance);

    ADD_SIGNAL(MethodInfo("world_ready"));
    ADD_SIGNAL(MethodInfo("piece_detached", PropertyInfo(Variant::VECTOR3, "position"), PropertyInfo(Variant::INT, "voxels"), PropertyInfo(Variant::INT, "material")));
    ADD_SIGNAL(MethodInfo("piece_settled", PropertyInfo(Variant::VECTOR3I, "origen"), PropertyInfo(Variant::VECTOR3I, "tam"), PropertyInfo(Variant::PACKED_BYTE_ARRAY, "mats")));
    ADD_SIGNAL(MethodInfo("pieza_congelada", PropertyInfo(Variant::INT, "id"), PropertyInfo(Variant::TRANSFORM3D, "xf")));
    // EL IMPACTO DE UN BLOQUE AL CAER, para replicarlo (solo en el anfitrion y en red). tipo 0 = crater en el
    // mundo (explode), 1 = mordisco a un bloque (carve_body_near).
    ADD_SIGNAL(MethodInfo("crater", PropertyInfo(Variant::VECTOR3, "pos"), PropertyInfo(Variant::FLOAT, "radio"),
                          PropertyInfo(Variant::INT, "potencia"), PropertyInfo(Variant::INT, "tipo")));
    ClassDB::bind_method(D_METHOD("place_frozen", "id", "xf"), &VoxelWorld::place_frozen);
    ClassDB::bind_method(D_METHOD("posturas_en_vuelo", "min_voxels", "quietos"), &VoxelWorld::posturas_en_vuelo, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("seguir_posturas", "ids", "poses"), &VoxelWorld::seguir_posturas);
    ClassDB::bind_method(D_METHOD("info_cuerpo", "rid"), &VoxelWorld::info_cuerpo);
    ADD_SIGNAL(MethodInfo("pieza_suelta", PropertyInfo(Variant::VECTOR3I, "origen"), PropertyInfo(Variant::VECTOR3I, "tam"),
        PropertyInfo(Variant::PACKED_BYTE_ARRAY, "mascara"), PropertyInfo(Variant::VECTOR3, "vel"), PropertyInfo(Variant::VECTOR3, "ang_vel")));
    ClassDB::bind_method(D_METHOD("set_settle_authority", "manda"), &VoxelWorld::set_settle_authority);
    ClassDB::bind_method(D_METHOD("set_interpolar", "si"), &VoxelWorld::set_interpolar);
    ClassDB::bind_method(D_METHOD("get_settle_authority"), &VoxelWorld::get_settle_authority);
    ClassDB::bind_method(D_METHOD("place_settled", "origen", "tam", "mats"), &VoxelWorld::place_settled);
    ClassDB::bind_method(D_METHOD("set_red", "en_red", "soy_host"), &VoxelWorld::set_red);
    ClassDB::bind_method(D_METHOD("place_detached", "origen", "tam", "mascara", "vel", "ang_vel"), &VoxelWorld::place_detached);
    ClassDB::bind_method(D_METHOD("carve_body_near", "pos", "radius", "power"), &VoxelWorld::carve_body_near);
    ClassDB::bind_method(D_METHOD("carve_body_id", "id", "local", "radius", "power"), &VoxelWorld::carve_body_id);
    ClassDB::bind_method(D_METHOD("tomar_fallos_estructurales"), &VoxelWorld::tomar_fallos_estructurales);
    ClassDB::bind_method(D_METHOD("tomar_apoyos_rotos"), &VoxelWorld::tomar_apoyos_rotos);
    ClassDB::bind_method(D_METHOD("romper_apoyos", "voxels"), &VoxelWorld::romper_apoyos);
    ClassDB::bind_method(D_METHOD("censo_bloques"), &VoxelWorld::censo_bloques);
    ClassDB::bind_method(D_METHOD("datos_bloque", "id"), &VoxelWorld::datos_bloque);
    ClassDB::bind_method(D_METHOD("crear_bloque", "id", "datos"), &VoxelWorld::crear_bloque);
    ClassDB::bind_method(D_METHOD("quitar_bloque", "id"), &VoxelWorld::quitar_bloque);
    ClassDB::bind_method(D_METHOD("recortar_escombros", "tope", "pos", "dir", "max_quitar"), &VoxelWorld::recortar_escombros);
    ClassDB::bind_method(D_METHOD("get_debris_instance"), &VoxelWorld::get_debris_instance);
    ClassDB::bind_method(D_METHOD("set_tope_despiertos", "n"), &VoxelWorld::set_tope_despiertos);
    ClassDB::bind_method(D_METHOD("limpiar_escombros", "min_m3", "max_m3", "s_fuera", "s_vista", "pos", "dir", "max_quitar", "despertar"), &VoxelWorld::limpiar_escombros);
    ClassDB::bind_method(D_METHOD("huellas_chunks"), &VoxelWorld::huellas_chunks);
    ClassDB::bind_method(D_METHOD("huella_chunk", "indice"), &VoxelWorld::huella_chunk);
    ClassDB::bind_method(D_METHOD("datos_chunk", "indice"), &VoxelWorld::datos_chunk);
    ClassDB::bind_method(D_METHOD("aplicar_chunk", "indice", "datos"), &VoxelWorld::aplicar_chunk);
    ClassDB::bind_method(D_METHOD("aplicar_fallo_estructural", "celdas", "tilt", "com", "masa", "isla"), &VoxelWorld::aplicar_fallo_estructural);
    ClassDB::bind_method(D_METHOD("punto_local_cuerpo", "body", "pos"), &VoxelWorld::punto_local_cuerpo);
    ClassDB::bind_method(D_METHOD("resumen_chunks"), &VoxelWorld::resumen_chunks);
}

// ---------------------------------------------------------------------------
// Ciclo de vida
// ---------------------------------------------------------------------------
/// CAJAS DE UN TROZO QUE SE ESTA MOVIENDO. Seis para un cascote, pero NO seis para un tronco.
///
/// Todos los trozos salian con `min(6, preset)` cajas mientras se movian, daba igual que fuera una
/// piedra o medio arbol. Medido en partida: un trozo de 16.542 voxels, solido y con cuerpo, y aun
/// asi el jugador lo atravesaba andando -seis cajas no cubren un tronco, y por los huecos se pasa-.
/// Ahora crece con el tamaño: el escombro pequeño sigue barato y lo gordo se puede pisar desde el
/// primer momento, no solo cuando se para.
static int cajasMoviendose(int voxels, int preset) {
    const int base = std::min(6, preset);
    if (voxels < 1500) return base;
    return std::clamp(voxels / 250, base, 96);
}

void VoxelWorld::_ready() {
    if (Engine::get_singleton()->is_editor_hint()) return;
    set_process(true);
    if (autoGenerate_) generate_city(seed_);
}

void VoxelWorld::_exit_tree() {
    if (Engine::get_singleton()->is_editor_hint()) return;
    destroyEngine();
}

void VoxelWorld::createEngine() {
    destroyEngine();
    vx::EngineConfig cfg;
    cfg.chunksX = std::max(1, chunkDims_.x); cfg.chunksY = std::max(1, chunkDims_.y); cfg.chunksZ = std::max(1, chunkDims_.z);
    cfg.voxelSize = voxelSize_;
    cfg.quality = static_cast<vx::Quality>(std::clamp(quality_, 0, 3));
    cfg.seed = static_cast<uint64_t>(seed_);
    cfg.loadModel = structuralLoad_;
    engine_.reset(new vx::Engine(cfg));
    engine_->setDebrisScale(debrisScale_);   // el motor se recrea al cargar mapa: reaplicar el ajuste
    engine_->setStructuralSleep(structuralSleep_);
    // las LOD sin AO (vx::Engine::setAoLod): -32 % de triangulos de lejos. VX_LOD_AO=1 lo devuelve, para comparar.
    engine_->setAoLod(std::getenv("VX_LOD_AO") != nullptr);
    engine_->setAoCerca(g_aoCerca);
    // ...y desprender lo desprende TODO EL MUNDO, tambien el invitado (ver `set_red`).
    engine_->setDesprender(true);
    engine_->setStructAuthority(!enRed_ || soyHost_);
    const size_t n = static_cast<size_t>(engine_->world().numChunkSlots());
    chunks_.assign(n, ChunkVis{});
    chunkLod1_.assign(n, vx::MeshData{});
    chunkLod2_.assign(n, vx::MeshData{});
    chunkOcc_.assign(n, vx::MeshData{});
    chunkFull_.assign(n, vx::MeshData{});
    chunkCol_.assign(n, std::vector<uint8_t>{}); chunkSh_.assign(n, vx::MeshData{});
    chunkColVer_.assign(n, 0xFFFFFFFFu);
    bnx_ = (cfg.chunksX + BLOCK - 1) / BLOCK; bny_ = (cfg.chunksY + BLOCK - 1) / BLOCK; bnz_ = (cfg.chunksZ + BLOCK - 1) / BLOCK;
    blocks_.assign(static_cast<size_t>(bnx_) * bny_ * bnz_, BlockVis{});
    blockVer_.assign(blocks_.size(), 0);
    dirtyBlocks_.clear();
    rnx_ = (cfg.chunksX + REGION - 1) / REGION; rny_ = (cfg.chunksY + REGION - 1) / REGION; rnz_ = (cfg.chunksZ + REGION - 1) / REGION;
    regions_.assign(static_cast<size_t>(rnx_) * rny_ * rnz_, RegionVis{});
    regionVer_.assign(regions_.size() * 2, 0);
    colaSombras_.clear();
    dirtyRegions_.clear();
    updateDistances();
    ensureMaterials();
    ensureDebris();
    occInit();
}

void VoxelWorld::destroyEngine() {
    stopBlockWorker();
    RenderingServer* rs = RenderingServer::get_singleton();
    for (size_t i = 0; i < chunks_.size(); ++i) freeChunk(chunks_[i], static_cast<uint32_t>(i));
    chunks_.clear(); chunkLod1_.clear(); chunkLod2_.clear(); chunkOcc_.clear(); chunkFull_.clear(); chunkSh_.clear(); chunkCol_.clear(); chunkColVer_.clear();
    for (BlockVis& bl : blocks_) freeBlock(bl);
    blocks_.clear(); dirtyBlocks_.clear();
    for (RegionVis& rg : regions_) freeRegion(rg);
    regions_.clear(); dirtyRegions_.clear(); colaSombras_.clear();
    for (Body& b : bodies_) freeBody(b);
    bodies_.clear();
    // las mallas comunes de los congelados no cuelgan de ningun Body: se liberan aparte o se quedan
    // como RID huerfano al recargar mapa (y Godot lo canta al salir)
    if (rs) for (auto& kv : gruposCongelados_) {
        if (kv.second.inst.is_valid()) rs->free_rid(kv.second.inst);
        if (kv.second.mesh.is_valid()) rs->free_rid(kv.second.mesh);
    }
    gruposCongelados_.clear();
    congelPendientes_.clear();
    physQueue_.clear();
    if (rs) {
        if (debrisInst_.is_valid()) rs->free_rid(debrisInst_);
        if (debrisMultimesh_.is_valid()) rs->free_rid(debrisMultimesh_);
        if (debrisMesh_.is_valid()) rs->free_rid(debrisMesh_);
        if (smokeInst_.is_valid()) rs->free_rid(smokeInst_);
        if (smokeMultimesh_.is_valid()) rs->free_rid(smokeMultimesh_);
        if (smokeMesh_.is_valid()) rs->free_rid(smokeMesh_);
    }
    debrisInst_ = RID(); debrisMultimesh_ = RID(); debrisMesh_ = RID(); debrisCapacity_ = 0;
    smokeInst_ = RID(); smokeMultimesh_ = RID(); smokeMesh_ = RID(); smokeCapacity_ = 0;
    occFree();
    engine_.reset();
    generated_ = false; loading_ = false;
}

// Distancias de detalle según preset, tamaño de voxel y escala de vista. Con voxels finos los chunks
// son pequeños (3,2 m a 10 cm), así que el detalle completo se acerca proporcionalmente.
// RESOLUCION LEJANA (set_lod2_factor): fuera de la clase a proposito, para no cambiar su tamaño (ninja no sigue las
// cabeceras: ver CLAUDE.md). Hay un solo mundo a la vez.
static float g_lod2Factor = 2.0f;

void VoxelWorld::set_lod2_factor(float f) {
    g_lod2Factor = std::clamp(f, 1.1f, 4.0f);
    updateDistances();
}

void VoxelWorld::updateDistances() {
    if (!engine_) return;
    const vx::QualityPreset& p = engine_->preset();
    const float f = std::clamp(voxelSize_ / 0.25f, 0.32f, 1.0f);
    // DOS DISTANCIAS, NO UNA. Antes las dos colgaban de la misma escala, asi que para recortar el
    // dibujado a lo lejos habia que renunciar tambien al detalle de cerca -o al reves-. Son cosas
    // distintas y cuestan cosas distintas: el DIBUJADO manda en cuantos chunks hay en pantalla (en
    // Monaco son 13.074 y 7,6 M de triangulos), y el DETALLE manda en si cada uno se dibuja con su
    // malla fina o con la de 20 cm. En un mapa grande interesa ver lejos con poco detalle.
    lodNear_ = p.lodDistance * f * lodScale_;
    lodFar_ = lodNear_ * g_lod2Factor;
    renderDist_ = p.renderDistance * renderScale_;
    for (RegionVis& rg : regions_) rg.state = -1;   // re-evaluar
    // las franjas de la transicion suave, para los shaders del mundo y del cristal (ver voxel.gdshader LOD_FADE)
    RenderingServer* rsm = RenderingServer::get_singleton();
    for (const Ref<Material>* mp : { &opaqueMat_, &glassMat_ }) {
        if (!mp->is_valid()) continue;
        const RID mr = (*mp)->get_rid();
        rsm->material_set_param(mr, "lod_fade_on", lodFadeOn() ? 1.0f : 0.0f);
        rsm->material_set_param(mr, "lod_fade_ini", fade1Ini());
        rsm->material_set_param(mr, "lod_fade_fin", fade1Fin());
        rsm->material_set_param(mr, "lod_fade2_ini", fade2Ini());
        rsm->material_set_param(mr, "lod_fade2_fin", fade2Fin());
    }
}

void VoxelWorld::set_piece_gravity(float s) {
    pieceGravity_ = std::clamp(s, 0.05f, 2.0f);
    PhysicsServer3D* ps = PhysicsServer3D::get_singleton();
    if (!ps) return;
    for (Body& b : bodies_) if (b.rigid && b.body.is_valid())
        ps->body_set_param(b.body, PhysicsServer3D::BODY_PARAM_GRAVITY_SCALE, pieceGravity_);
}

void VoxelWorld::set_debris_scale(float s) {
    debrisScale_ = s;
    if (engine_) engine_->setDebrisScale(s);
}

// Enciende los datos de diagnostico que cuestan de verdad (hoy: bloques_dentro_de_otro, que es O(n^2)).
void VoxelWorld::set_diag_bloques(bool on) {
    diagBloques_ = on;
}

void VoxelWorld::set_view_distance_scale(float s) {
    // las dos a la vez: lo que hacia antes este ajuste. Se conserva para quien solo quiera un mando.
    viewScale_ = renderScale_ = lodScale_ = std::clamp(s, 0.2f, 2.0f);
    updateDistances();
}

void VoxelWorld::set_render_distance_scale(float s) {
    renderScale_ = std::clamp(s, 0.2f, 2.0f);
    updateDistances();
}

void VoxelWorld::set_lod_distance_scale(float s) {
    lodScale_ = std::clamp(s, 0.2f, 2.0f);
    updateDistances();
}

void VoxelWorld::set_lod_fade_band(float cerca, float lejos) {
    lodFadeBand_ = std::clamp(cerca, 0.0f, 32.0f);
    lodFadeBand2_ = std::clamp(lejos, 0.0f, 64.0f);
    updateDistances();
}

void VoxelWorld::generate_city(int seed) {
    seed_ = seed;
    vx::resetMaterials();
    refreshMaterialColors();
    createEngine();
    vx::CityParams cp;
    city_ = vx::CityInfo{};
    vx::generateCity(engine_->world(), static_cast<uint64_t>(seed), cp, city_);
    mapSpawns_.clear();
    engine_->markAllDirty();
    engine_->setUnlimitedUploads(true);
    loading_ = true; welded_ = false; generated_ = true;
    initialChunks_ = engine_->world().allocatedChunks();
    playerPos_ = toGd(city_.playerSpawn);
    prepararColorTextura();
}

bool VoxelWorld::load_map(const PackedByteArray& data) {
    vx::MapHeader h;
    if (!vx::readMapHeader(data.ptr(), static_cast<size_t>(data.size()), h)) {
        UtilityFunctions::push_error(String("VoxelWorld.load_map: ") + h.error.c_str());
        return false;
    }
    vx::resetMaterials();
    vx::applyMapMaterials(h);
    refreshMaterialColors();
    voxelSize_ = h.voxelSize;
    chunkDims_ = Vector3i(h.ncx, h.ncy, h.ncz);
    createEngine();
    uint64_t voxels = 0;
    if (!vx::loadMapChunks(engine_->world(), data.ptr(), static_cast<size_t>(data.size()), h, &voxels)) {
        UtilityFunctions::push_error("VoxelWorld.load_map: datos de chunks corruptos");
        return false;
    }
    city_ = vx::CityInfo{};
    mapSpawns_.clear();
    for (const vx::MapSpawn& s : h.spawns) mapSpawns_.push_back(Vector3(s.pos.x, s.pos.y, s.pos.z));
    if (!mapSpawns_.is_empty()) city_.playerSpawn = toVxV(mapSpawns_[0]);
    else city_.playerSpawn = toVxV(get_world_size() * 0.5f);
    engine_->setUnlimitedUploads(true);
    loading_ = true; welded_ = false; generated_ = true;
    initialChunks_ = engine_->world().allocatedChunks();
    playerPos_ = toGd(city_.playerSpawn);
    prepararColorTextura();
    UtilityFunctions::print(String("VoxelWorld: mapa cargado, %d chunks, %d voxels, voxel %.3f m") % Array::make(initialChunks_, static_cast<int64_t>(voxels), voxelSize_));
    return true;
}

Vector3 VoxelWorld::find_ground(const Vector3& p) const {
    if (!engine_) return Vector3(p.x, -1, p.z);
    const float top = engine_->world().sizeMeters().y - 0.01f;
    vx::RayHit h;
    if (engine_->world().raycast(vx::Vec3(p.x, top, p.z), vx::Vec3(0, -1, 0), top + 1.0f, h)) return Vector3(p.x, h.pos.y, p.z);
    return Vector3(p.x, -1, p.z);
}

PackedVector3Array VoxelWorld::get_spawn_points() const { return mapSpawns_; }

float VoxelWorld::get_loading_progress() const {
    if (!loading_) return 1.0f;
    if (initialChunks_ <= 0) return 0.f;
    int done = 0;
    for (const ChunkVis& c : chunks_) if (c.hasMesh) ++done;
    return std::min(1.0f, static_cast<float>(done) / initialChunks_);
}

void VoxelWorld::set_quality(int q) {
    quality_ = std::clamp(q, 0, 3);
    if (!engine_) return;
    engine_->setQuality(static_cast<vx::Quality>(quality_));
    ensureDebris();
    updateDistances();
    RenderingServer* rs = RenderingServer::get_singleton();
    // Las sombras las proyectan sólo los casters fusionados por región; su visibilidad depende del
    // preset/tier y se re-evalúa en updateLod (updateDistances pone state = -1).
    (void)rs;
}

void VoxelWorld::ensureMaterials() {
    if (!opaqueMat_.is_valid()) {
        Ref<StandardMaterial3D> m; m.instantiate();
        m->set_flag(BaseMaterial3D::FLAG_ALBEDO_FROM_VERTEX_COLOR, true);
        m->set_roughness(0.95f);
        m->set_metallic(0.0f);
        opaqueMat_ = m;
    }
    if (!glassMat_.is_valid()) {
        Ref<StandardMaterial3D> m; m.instantiate();
        m->set_flag(BaseMaterial3D::FLAG_ALBEDO_FROM_VERTEX_COLOR, true);
        m->set_transparency(BaseMaterial3D::TRANSPARENCY_ALPHA);
        m->set_cull_mode(BaseMaterial3D::CULL_DISABLED);
        m->set_roughness(0.15f);
        m->set_metallic(0.4f);
        glassMat_ = m;
    }
    if (!debrisMat_.is_valid()) {
        // Escombros: material propio (sin shader de voxel). El alfa del color de instancia lleva la vida restante
        // y no debe pasar por la codificación de emisivos del shader de los chunks.
        Ref<StandardMaterial3D> m; m.instantiate();
        m->set_flag(BaseMaterial3D::FLAG_ALBEDO_FROM_VERTEX_COLOR, true);
        m->set_roughness(0.95f);
        m->set_metallic(0.0f);
        debrisMat_ = m;
    }
}

// ---------------------------------------------------------------------------
// Humo (MultiMesh de quads; el material lo pone el juego: billboard + textura de humo + color de instancia)
// ---------------------------------------------------------------------------
void VoxelWorld::set_smoke_material(const Ref<Material>& m) {
    smokeMat_ = m;
    RenderingServer* rs = RenderingServer::get_singleton();
    if (rs && smokeMesh_.is_valid() && smokeMat_.is_valid()) rs->mesh_surface_set_material(smokeMesh_, 0, smokeMat_->get_rid());
}

void VoxelWorld::emit_smoke(const Vector3& pos, int count, float radius, float speed, const Color& color, float life, float r0, float r1, float buoy) {
    if (!engine_) return;
    const uint8_t rgb[3] = { static_cast<uint8_t>(std::clamp(color.r, 0.f, 1.f) * 255.f), static_cast<uint8_t>(std::clamp(color.g, 0.f, 1.f) * 255.f), static_cast<uint8_t>(std::clamp(color.b, 0.f, 1.f) * 255.f) };
    engine_->emitSmoke(toVxV(pos), count, radius, speed, rgb, life, r0, r1, buoy);
}

Array VoxelWorld::get_smoke_debug(int n) const {
    Array out;
    if (!engine_) return out;
    const vx::SmokeSystem& ss = engine_->smoke();
    for (int i = 0; i < std::min(n, ss.count()); ++i) {
        const vx::Smoke& s = ss.data()[i];
        Dictionary d;
        d["pos"] = toGd(s.pos); d["age"] = s.age; d["life"] = s.life; d["r"] = vx::SmokeSystem::radiusOf(s); d["a"] = vx::SmokeSystem::alphaOf(s);
        d["inside"] = vx::isSolid(engine_->world().getVoxelAt(s.pos)); d["enclosed"] = static_cast<int>(s.enclosed);
        out.push_back(d);
    }
    return out;
}

// LAS MULTIMALLAS DE PARTICULAS Y HUMO, SIN SUBIR LO QUE NO HAY (2026-10-10). Antes cada fotograma se subia el bufer
// ENTERO (la capacidad: miles de escombros y 512 humos, cientos de KB) aunque no hubiera ni una particula. Ahora con 0 no
// se sube nada y con algo la multimalla se reserva a la potencia de dos >= n (se rehace solo al crecer o al bajar a la
// cuarta parte) y se sube eso. VX_MULTIMESH_ENTERO=1 = como antes.
namespace {
struct SubidaMM { int alloc = -1; int ult = -1; PackedFloat32Array* buf = nullptr; };
SubidaMM g_mmDebris, g_mmSmoke;
const bool g_mmEntero = std::getenv("VX_MULTIMESH_ENTERO") != nullptr;
// devuelve el bufer donde escribir n instancias (o nullptr si no hay que subir nada)
float* mmPreparar(SubidaMM& m, RID mm, int n, int cap, int stride = 16) {
    RenderingServer* rs = RenderingServer::get_singleton();
    if (n <= 0) {
        if (m.ult != 0) { rs->multimesh_set_visible_instances(mm, 0); m.ult = 0; }
        return nullptr;
    }
    int want = 64;
    while (want < n) want <<= 1;
    want = std::min(want, cap);
    if (m.alloc != want && (want > m.alloc || want * 4 <= m.alloc)) {
        rs->multimesh_allocate_data(mm, want, RenderingServer::MULTIMESH_TRANSFORM_3D, true, stride > 16);
        m.alloc = want;
    }
    if (!m.buf) m.buf = new PackedFloat32Array();
    if (m.buf->size() != static_cast<int64_t>(m.alloc) * stride) {
        m.buf->resize(static_cast<int64_t>(m.alloc) * stride);
        std::memset(m.buf->ptrw(), 0, sizeof(float) * m.alloc * stride);
    }
    return m.buf->ptrw();
}
void mmSubir(SubidaMM& m, RID mm, int n) {
    RenderingServer* rs = RenderingServer::get_singleton();
    rs->multimesh_set_buffer(mm, *m.buf);
    rs->multimesh_set_visible_instances(mm, n);
    m.ult = n;
}
// LA CAPA DE TEXTURA de un material (la misma que lee voxel.gdshader del alfa del color): -1 sin textura, 9 follaje
float capaDeMaterial(int mat) {
    if (mat < 0 || mat >= vx::MAT_COUNT) return -1.0f;
    const float a = g_matAlfa[mat];
    if (a > 0.945f) return std::floor((1.0f - a) * 255.0f + 0.5f) - 1.0f;
    return (a > 0.85f && a < 0.93f) ? 9.0f : -1.0f;
}
// LOS ESCOMBROS DEL COLOR DEL MATERIAL (2026-10-11, pedido: "son grises; tienen que ser del mismo color y textura del
// bloque destruido"). VX_ESCOMBRO_GRIS=1 = grises como antes (luminosidad y un 20 % del tono)
const bool g_escombroGris = std::getenv("VX_ESCOMBRO_GRIS") != nullptr;
constexpr int DEBRIS_STRIDE = 20;   // transformada 12 + color 4 + datos 4 (capa de textura, lado en voxels)
}  // namespace

void VoxelWorld::ensureSmoke() {
    if (!engine_) return;
    RenderingServer* rs = RenderingServer::get_singleton();
    const int cap = engine_->smoke().capacity();
    if (!smokeMesh_.is_valid()) {
        // quad unitario centrado (el material billboard lo orienta a la cámara)
        smokeMesh_ = rs->mesh_create();
        PackedVector3Array v; PackedVector3Array n; PackedVector2Array uv; PackedColorArray col; PackedInt32Array idx;
        const float q[4][2] = {{-0.5f, -0.5f}, {0.5f, -0.5f}, {0.5f, 0.5f}, {-0.5f, 0.5f}};
        for (int k = 0; k < 4; ++k) {
            v.push_back(Vector3(q[k][0], q[k][1], 0.f)); n.push_back(Vector3(0, 0, 1));
            uv.push_back(Vector2(q[k][0] + 0.5f, 0.5f - q[k][1])); col.push_back(Color(1, 1, 1, 1));
        }
        const int t[6] = {0, 2, 1, 0, 3, 2};
        for (int k = 0; k < 6; ++k) idx.push_back(t[k]);
        Array arrays; arrays.resize(RenderingServer::ARRAY_MAX);
        arrays[RenderingServer::ARRAY_VERTEX] = v; arrays[RenderingServer::ARRAY_NORMAL] = n; arrays[RenderingServer::ARRAY_TEX_UV] = uv;
        arrays[RenderingServer::ARRAY_COLOR] = col; arrays[RenderingServer::ARRAY_INDEX] = idx;
        rs->mesh_add_surface_from_arrays(smokeMesh_, RenderingServer::PRIMITIVE_TRIANGLES, arrays);
        if (smokeMat_.is_valid()) rs->mesh_surface_set_material(smokeMesh_, 0, smokeMat_->get_rid());
    }
    if (!smokeMultimesh_.is_valid()) {
        smokeMultimesh_ = rs->multimesh_create();
        Ref<World3D> w = get_world_3d();
        if (w.is_valid()) {
            smokeInst_ = rs->instance_create2(smokeMultimesh_, w->get_scenario());
            rs->instance_set_transform(smokeInst_, Transform3D());
            rs->instance_geometry_set_cast_shadows_setting(smokeInst_, RenderingServer::SHADOW_CASTING_SETTING_OFF);
        }
    }
    if (cap != smokeCapacity_) {
        smokeCapacity_ = cap;
        rs->multimesh_allocate_data(smokeMultimesh_, cap, RenderingServer::MULTIMESH_TRANSFORM_3D, true, false);
        rs->multimesh_set_mesh(smokeMultimesh_, smokeMesh_);
        smokeBuffer_.resize(cap * 16);
        std::memset(smokeBuffer_.ptrw(), 0, sizeof(float) * cap * 16);
        rs->multimesh_set_visible_instances(smokeMultimesh_, 0);
        g_mmSmoke.alloc = cap; g_mmSmoke.ult = 0;
    }
}


void VoxelWorld::updateSmoke() {
    if (!engine_) return;
    if (!smokeMultimesh_.is_valid() || engine_->smoke().capacity() != smokeCapacity_) ensureSmoke();
    if (!smokeMultimesh_.is_valid()) return;
    RenderingServer* rs = RenderingServer::get_singleton();
    const vx::SmokeSystem& ss = engine_->smoke();
    const int n = std::min(ss.count(), smokeCapacity_);
    float* buf = g_mmEntero ? smokeBuffer_.ptrw() : mmPreparar(g_mmSmoke, smokeMultimesh_, n, smokeCapacity_);
    if (!buf) return;
    const vx::Smoke* d = ss.data();
    for (int i = 0; i < n; ++i) {
        const float s = vx::SmokeSystem::radiusOf(d[i]) * 2.f;
        // giro suave alrededor del eje de visión: el material billboard mantiene el plano; la escala da el tamaño
        const float ang = d[i].seed * 0.01f + d[i].age * 0.15f * (((d[i].seed & 1) ? 1.f : -1.f));
        const float c = std::cos(ang) * s, sn = std::sin(ang) * s;
        float* o = buf + i * 16;
        o[0] = c;  o[1] = -sn; o[2] = 0.f; o[3] = d[i].pos.x;
        o[4] = sn; o[5] = c;   o[6] = 0.f; o[7] = d[i].pos.y;
        o[8] = 0.f; o[9] = 0.f; o[10] = s; o[11] = d[i].pos.z;
        o[12] = d[i].col[0] / 255.f; o[13] = d[i].col[1] / 255.f; o[14] = d[i].col[2] / 255.f; o[15] = vx::SmokeSystem::alphaOf(d[i]);
    }
    if (!g_mmEntero) { mmSubir(g_mmSmoke, smokeMultimesh_, n); return; }
    rs->multimesh_set_buffer(smokeMultimesh_, smokeBuffer_);
    rs->multimesh_set_visible_instances(smokeMultimesh_, n);
}

void VoxelWorld::ensureDebris() {
    if (!engine_) return;
    RenderingServer* rs = RenderingServer::get_singleton();
    const int cap = engine_->debris().capacity();
    if (!debrisMesh_.is_valid()) {
        // Cubo unitario con color blanco: el color de instancia (material del escombro) lo tiñe.
        debrisMesh_ = rs->mesh_create();
        PackedVector3Array v; PackedVector3Array n; PackedColorArray col; PackedInt32Array idx;
        static const float N[6][3] = {{-1,0,0},{1,0,0},{0,-1,0},{0,1,0},{0,0,-1},{0,0,1}};
        for (int f = 0; f < 6; ++f) {
            const int d = f / 2; const float s = (f & 1) ? 0.5f : -0.5f;
            const int u = (d + 1) % 3, w = (d + 2) % 3;
            const int base = v.size();
            for (int k = 0; k < 4; ++k) {
                float p[3]; p[d] = s;
                p[u] = (k == 1 || k == 2) ? 0.5f : -0.5f;
                p[w] = (k >= 2) ? 0.5f : -0.5f;
                v.push_back(Vector3(p[0], p[1], p[2]));
                n.push_back(Vector3(N[f][0], N[f][1], N[f][2]));
                col.push_back(Color(1, 1, 1, 1));
            }
            int t[6] = {0, 1, 2, 0, 2, 3};
            if (f & 1) { std::swap(t[1], t[2]); std::swap(t[4], t[5]); }   // horario visto desde fuera (Godot)
            for (int k = 0; k < 6; ++k) idx.push_back(base + t[k]);
        }
        Array arrays; arrays.resize(RenderingServer::ARRAY_MAX);
        arrays[RenderingServer::ARRAY_VERTEX] = v; arrays[RenderingServer::ARRAY_NORMAL] = n;
        arrays[RenderingServer::ARRAY_COLOR] = col; arrays[RenderingServer::ARRAY_INDEX] = idx;
        rs->mesh_add_surface_from_arrays(debrisMesh_, RenderingServer::PRIMITIVE_TRIANGLES, arrays);
        rs->mesh_surface_set_material(debrisMesh_, 0, debrisMat_->get_rid());
        vx::Rng rng(99);
        for (int i = 0; i < 16; ++i) debrisRot_[i] = Basis::from_euler(Vector3(rng.range(0.f, 6.28f), rng.range(0.f, 6.28f), rng.range(0.f, 6.28f)));
    }
    if (!debrisMultimesh_.is_valid()) {
        debrisMultimesh_ = rs->multimesh_create();
        Ref<World3D> w = get_world_3d();
        if (w.is_valid()) {
            debrisInst_ = rs->instance_create2(debrisMultimesh_, w->get_scenario());
            rs->instance_set_transform(debrisInst_, Transform3D());
        }
    }
    if (cap != debrisCapacity_) {
        debrisCapacity_ = cap;
        rs->multimesh_allocate_data(debrisMultimesh_, cap, RenderingServer::MULTIMESH_TRANSFORM_3D, true, true);
        rs->multimesh_set_mesh(debrisMultimesh_, debrisMesh_);
        debrisBuffer_.resize(cap * DEBRIS_STRIDE);
        float* b = debrisBuffer_.ptrw();
        std::memset(b, 0, sizeof(float) * cap * DEBRIS_STRIDE);
        rs->multimesh_set_visible_instances(debrisMultimesh_, 0);
        g_mmDebris.alloc = cap; g_mmDebris.ult = 0;
    }
    if (debrisInst_.is_valid())
        rs->instance_geometry_set_cast_shadows_setting(debrisInst_, engine_->preset().shadows && quality_ >= 2 ? RenderingServer::SHADOW_CASTING_SETTING_ON : RenderingServer::SHADOW_CASTING_SETTING_OFF);
}

// ---------------------------------------------------------------------------
// Frame
// ---------------------------------------------------------------------------
static double g_fisMsAnclas = 0.0, g_fisMsAnclasMax = 0.0;   // updatePhysicsBodies (cada 3 fotogramas)
static float g_hMax[8] = {};   // peor tramo por fase: update, upload, blocks, regions, phys, spawn, bodies, debris
static float g_hLast[8] = {};
static float g_bLast[3] = {};
// DENTRO DE stepBodies, este cuadro (todas sus vueltas): colision fina al anclar, impacto al aterrizar, sondeo del suelo,
// asentar, mirar si hay alguien cerca (2026-10-02, buscando el pico de "mover bloques")
static double g_bs[5] = {};
// DENTRO DE crearColisionFina, este cuadro: partir en cajas, crear las formas, añadirlas al cuerpo; y cuantas cajas
static double g_cf[3] = {};
static int64_t g_cfCajas = 0;
// LA AUDITORIA (2026-10-05): lo que cuestan el callback de estado de cada cuerpo y las cajas de un bloque tallado
static double g_bsTotalMs = 0.0;      // _on_body_state, en toda la partida
static int64_t g_bsLlamadas = 0;
static double g_rcTotalMs = 0.0;      // reconstruirCuerpo: rehacer las cajas de Jolt de un bloque tallado
static int64_t g_rcCajas = 0;
// DE QUE CUERPO ES CADA RID: _on_body_state recorria TODOS los bloques por cada cuerpo despierto y paso de fisica
// (O(despiertos x total)). Aqui se recuerda donde estaba en `bodies_`; se comprueba que sigue siendo el mismo (el RID
// no se reutiliza) y si no, se busca como antes. VX_BODYSTATE_LINEAL=1 = siempre como antes.
static std::unordered_map<uint64_t, size_t> g_idxCuerpo;
// CUANDO SE CONGELO CADA BLOQUE (id -> ms): la limpieza con el tiempo y "no despertar lo congelado hace rato"
static std::unordered_map<uint64_t, uint64_t> g_congeladoEn;
// el choque contra una pared (stepBodies): la velocidad del paso anterior y la espera entre choques, por bloque
struct VelAnt { Vector3 v; float espera = 0.f; };
static std::unordered_map<uint64_t, VelAnt> g_velAnt;
// TOPE DE BLOQUES DESPIERTOS (2026-10-10, pedido: "que no baje de 60 fps"): con mas de este numero moviendose en la
// fisica, los mas lentos se asientan ya (stepBodies). 0 = sin tope. Lo pone main.gd (set_tope_despiertos).
static int g_topeDespiertos = 40;
static int64_t g_asentadosPorTope = 0;
static double g_cfTotalMs = 0.0;      // en toda la partida: lo que ha costado añadir cajas (formas + añadir + volver al espacio)
static int64_t g_cfTotalCajas = 0;  // dentro de `bodies`, el ultimo cuadro: mover los bloques, reconstruir tallados, solidificar  // lo de cada fase en el ULTIMO cuadro (las t_h_* son medias moviles: en un tiron no dicen nada)
// ...y dentro de las fases con picos: region (fusion, subida de malla, oclusor, caster de sombra), bloque
// (fusion, subida), pieza (malla, resto). Estaticos a proposito: no cambian el layout de la clase.
static bool g_compressAttrs = true;   // --sincompresion (banco): medir cuanto del pico de subida es ARRAY_FLAG_COMPRESS_ATTRIBUTES
static float g_fMax[16] = {};  // [15] = vertices de la superficie mas lenta
static float g_surfWorst = 0.f;
// QUE SE DESPRENDE Y POR QUE (acumulado desde la carga): trozos con giro de vuelco vienen del analizador de
// cargas (sobrecarga); los demas, de quedarse sin conexion (pristine perdido, apoyos rotos, tallado).
static int64_t g_pzEstruct = 0, g_pzSueltas = 0, g_voxEstruct = 0, g_voxSueltas = 0, g_pzGrandes = 0, g_pzMayor = 0;  // reg_merge, reg_surf, reg_occ, reg_shadow, block_merge, block_surf, piece_mesh, piece_rest, surf_pack, surf_rs, piece_shapes, piece_space, step_bodies, reconstruir, solidificar
static inline void fmax(int i, double ms) { if (static_cast<float>(ms) > g_fMax[i]) g_fMax[i] = static_cast<float>(ms); }

void VoxelWorld::_process(double delta) {
    if (!engine_ || Engine::get_singleton()->is_editor_hint()) return;
    vx::Timer timer;
    ++frame_;
    const float dt = static_cast<float>(delta);
    flushColorTextura(delta);

    effectEvents_.clear();
    // cronómetros por fase (media móvil, para el perfilador: get_stats t_h_*)
    // ...y el PEOR tramo de cada fase en la ventana de 256 frames (las medias moviles esconden los bajones)
    int li = 0;
    if ((frame_ & 255) == 0) { for (float& m : g_hMax) m = 0.f; for (float& m : g_fMax) m = 0.f; g_surfWorst = 0.f; }
    auto lap = [&](float& acc) { const float t = static_cast<float>(timer.ms()); const float d = t - phaseT_; acc = acc * 0.9f + d * 0.1f; if (li < 8) { if (d > g_hMax[li]) g_hMax[li] = d; g_hLast[li] = d; } ++li; phaseT_ = t; };
    phaseT_ = 0.f;
    // gobernador de frame (vxcore difiere el trabajo secundario si el host va por encima del presupuesto)
    if (!engine_->debris().extraSolid) engine_->debris().extraSolid = [this](const vx::Vec3& p) { return puntoEnBloqueParado(p); };
    engine_->setHostFrameMs(dt * 1000.f);
    engine_->setFrameBudget(1000.f / std::max(30.f, static_cast<float>(Engine::get_singleton()->get_max_fps() > 0 ? Engine::get_singleton()->get_max_fps() : 60)));
    engine_->update(dt, toVxV(playerPos_));
    lap(tHUpdate_);
    for (const vx::Engine::CarveEvent& ev : engine_->carveEvents()) pushEffect("carve", toGd(ev.pos), std::min(3.0f, 0.4f + ev.removed * 0.01f), ev.mat);
    {
        const auto& ls = engine_->debris().landings();
        const auto& lm = engine_->debris().landingMats();
        for (size_t i = 0; i < ls.size(); ++i) pushEffect("land", toGd(ls[i]), 0.35f, i < lm.size() ? lm[i] : 0);
    }
    for (vx::ChunkMeshResult& r : engine_->readyMeshes()) uploadChunk(r);
    occFlush(loading_ ? 100000 : 6);   // 6 capas/frame (~20 KB cada una): un chunk editado tarda 3 frames en verse
    lap(tHUpload_);
    // 2 bloques/frame en régimen (antes 4): medido con --stress, esta fase llegaba a 10 ms de pico
    // tras una tanda de explosiones y era el segundo mayor coste del host. Repartirla en el doble de
    // frames baja el pico a la mitad; la malla tarda un frame más en aparecer, que no se nota.
    flushBlocks(loading_ ? 100000 : 2);
    drainBlockJobs();
    lap(tHBlocks_);
    // regiones: 1 por frame en régimen (fusionar 64 chunks son ~10-15 ms; 3 seguidas eran el pico de 50 ms tras
    // una explosión) y sólo cuando la región lleva 0,35 s sin cambiar (la explosión toca sus chunks en ráfaga)
    flushRegions(loading_ ? 100000 : 1);
    flushSombras(loading_ ? 1e9 : 2.0);
    lap(tHRegions_);
    // el barrido de anclas de física no necesita ir a 60 Hz: cada 3 frames (la histéresis del 25 % lo absorbe)
    if (loading_ || (frame_ % 3) == 0) {
        vx::Timer tan;
        updatePhysicsBodies();
        const double m = tan.ms(); g_fisMsAnclas = g_fisMsAnclas * 0.9 + m * 0.1; if (m > g_fisMsAnclasMax) g_fisMsAnclasMax = m;
    }
    // presupuesto de colisión: 8/frame en régimen; tras un teletransporte la cola crece a cientos y se
    // drena en ~1 s (cola/45 por frame) en vez de arrastrarse varios segundos
    // 4 cuerpos/frame en régimen (cada uno = descomposición en cajas + formas Jolt, ~0,3 ms): crear 8 de golpe
    // al andar daba tirones que luego la física intentaba recuperar con pasos extra
    // ...pero con TOPE: sin él, una cola de cientos tras varias explosiones subía el presupuesto y
    // esta fase se comía 9 ms de frame. Con 8 como máximo el drenaje sigue siendo rápido y acotado.
    // Igual que con las mallas: si la cola de fisica se dispara (derrumbe), se procesa mucho mas por
    // frame. Con el tope de 8 el mundo tardaba segundos en volver a ser solido donde ya no habia nada.
    flushPhysics(loading_ ? 100000 : std::min(48, std::max({3, engine_->preset().maxUploadsPerFrame, static_cast<int>(physQueue_.size() / 12)})));
    lap(tHPhys_);

    // cola de piezas pendientes: crear cada cuerpo (malla, instancia, forma Jolt) cuesta 0,5-3 ms; el
    // derrumbe de un edificio entrega 300-500 a la vez y hacerlo en un frame era un parón de ~2 s
    if (!engine_->readyPieces().empty()) {
        for (vx::VoxelBody& p : engine_->readyPieces()) pendingPieces_.push_back(std::move(p));
        engine_->readyPieces().clear();
        // los grandes primero: son los que se ven y los que deben llevarse los cuerpos Jolt disponibles (una losa
        // de tejado "barata" se queda apoyada en cualquier muro que pille debajo de su centro y parece flotar)
        std::stable_sort(pendingPieces_.begin(), pendingPieces_.end(), [](const vx::VoxelBody& a, const vx::VoxelBody& b) { return a.voxelCount > b.voxelCount; });
    }
    {
        vx::Timer ts;
        size_t k = 0;
        while (k < pendingPieces_.size() && (k == 0 || loading_ || ts.ms() < 5.0)) { spawnPiece(std::move(pendingPieces_[k])); ++k; }
        if (k > 0) pendingPieces_.erase(pendingPieces_.begin(), pendingPieces_.begin() + static_cast<long>(k));
    }
    // FUNDIR LOS GRUPOS CONGELADOS, con presupuesto de tiempo. Antes era UNO por frame pase lo que
    // pase: en una demolicion se congelan trozos mucho mas rapido de lo que se funden, y mientras tanto
    // cada uno se dibuja por separado (una instancia y un par de llamadas de dibujo cada uno). Con 2 ms
    // por frame se vacia la cola en cuanto hay un respiro y el numero de dibujos vuelve a bajar.
    {
        vx::Timer tg;
        int nf = 0;
        while (nf < 8 && (nf == 0 || tg.ms() < 2.0)) {
            bool hay = false;
            for (const auto& kv : gruposCongelados_) if (kv.second.sucio) { hay = true; break; }
            if (!hay) break;
            rehacerUnGrupo();
            ++nf;
        }
    }
    lap(tHSpawn_);

    // PASO FIJO. `stepBodies` lleva los relojes de los escombros (cuanto llevan dormidos, su edad,
    // cuando se congelan) y corria con el delta del FRAME: a 144 fps cruzaba los umbrales en otro
    // momento que a 25, asi que la misma caida se congelaba en sitios distintos segun el aparato.
    // Ahora avanza en trozos de 1/60 exactos; los cuerpos los integra Jolt en su propio tick fijo,
    // asi que su transformada solo cambia a esa misma frecuencia y no se pierde nada visual.
    pasoAcum_ += dt;
    for (double& x : g_bs) x = 0.0;
    for (double& x : g_cf) x = 0.0;
    g_cfCajas = 0;
    int pasos = 0;
    {
        vx::Timer tsb;
        while (pasoAcum_ >= PASO_FIJO && pasos < MAX_PASOS_FIJOS) {
            stepBodies(PASO_FIJO);
            pasoAcum_ -= PASO_FIJO;
            ++pasos;
        }
        fmax(12, tsb.ms());
        g_bLast[0] = static_cast<float>(tsb.ms());
    }
    if (pasoAcum_ > PASO_FIJO * MAX_PASOS_FIJOS) pasoAcum_ = 0.0f;   // no arrastrar deuda infinita
    { vx::Timer trp; reconstruirPendientes(2); fmax(13, trp.ms()); g_bLast[1] = static_cast<float>(trp.ms()); }
    { vx::Timer tsc; solidificarCerca(); fmax(14, tsc.ms()); g_bLast[2] = static_cast<float>(tsc.ms()); }
    lap(tHBodies_);
    updateDebris();
    updateSmoke();
    updateLod();
    lap(tHDebris_);

    if (loading_ && engine_->isIdle() && physQueue_.empty() && dirtyRegions_.empty() && dirtyBlocks_.empty()) {
        // SOLDAR LO QUE EL MAPA DEJO SIN PEGAR, una vez, con el mundo ya etiquetado. Monaco a 10 cm traia 906
        // adornos (balcones, toldos, lamparas, setos...) a un voxel de la pared: intactos aguantan por la regla
        // pristine, pero en cuanto se dana algo cerca caen todos en cascada. Aqui se les rellena el hueco.
        // VX_NOWELD=1 la desactiva y VX_WELDGAP=<m> cambia el hueco maximo (solo para medir, no para jugar)
        if (!welded_ && weldOn_ && std::getenv("VX_NOWELD") == nullptr) {
            welded_ = true;
            vx::Timer tw;
            float gapM = 0.5f;   // medido en Monaco: con 0,25 m quedaban 190 sin nada a mano; con 0,5 m, 151, y lo que sigue suelto no tiene nada cerca
            if (const char* e = std::getenv("VX_WELDGAP")) gapM = std::max(0.05f, static_cast<float>(std::atof(e)));
            const int gap = std::max(1, static_cast<int>(std::ceil(gapM / engine_->world().voxelSize())));
            weldedFloaters_ = engine_->weldFloaters(20000, gap, &weldSinSoldar_, &weldVoxels_);
            UtilityFunctions::print(vformat("[soldadura] %d flotadores soldados (%d voxels escritos), %d sin nada a mano, hueco max %d voxels, %.0f ms",
                                            weldedFloaters_, weldVoxels_, weldSinSoldar_, gap, tw.ms()));
            if (weldVoxels_ > 0) { lastProcessMs_ = timer.ms(); return; }   // los chunks soldados se remallan: la carga acaba al volver a estar ocioso
        }
        loading_ = false;
        engine_->setUnlimitedUploads(false);
        emit_signal("world_ready");
        // el juego acaba de colocar al jugador: crear ya la colisión a su alrededor
        updatePhysicsBodies();
        flushPhysics(100000);
    }
    lastProcessMs_ = timer.ms();
    if (lastProcessMs_ > maxProcessMs_) maxProcessMs_ = lastProcessMs_;
    if ((frame_ & 255) == 0) maxProcessMs_ = lastProcessMs_;
}

// Los arrays de una superficie (vertices, normales, colores e indices) a partir de la malla: sin tocar el servidor
// de render, asi que vale en cualquier hilo (lo usa tambien el hilo de los bloques, ver blockWorkerLoop).
static Array empaquetarSuperficie(const vx::MeshData& md, const std::vector<uint32_t>& indices, int32_t& nOut);

int VoxelWorld::addSurface(const RID& mesh, const vx::MeshData& md, const std::vector<uint32_t>& indices, const Ref<Material>& mat, int surfaceIndex) {
    if (indices.empty()) return 0;
    vx::Timer tsu;
    RenderingServer* rs = RenderingServer::get_singleton();
    int32_t n = 0;
    Array arrays = empaquetarSuperficie(md, indices, n);
    fmax(8, tsu.ms()); tsu = vx::Timer();
    rs->mesh_add_surface_from_arrays(mesh, RenderingServer::PRIMITIVE_TRIANGLES, arrays, Array(), Dictionary(),
                                     BitField<RenderingServer::ArrayFormat>(g_compressAttrs ? static_cast<int64_t>(RenderingServer::ARRAY_FLAG_COMPRESS_ATTRIBUTES) : 0));
    if (mat.is_valid()) rs->mesh_surface_set_material(mesh, surfaceIndex, mat->get_rid());
    { const double t = tsu.ms(); if (static_cast<float>(t) > g_surfWorst) { g_surfWorst = static_cast<float>(t); g_fMax[15] = static_cast<float>(n); } fmax(9, t); }
    return 1;
}

static Array empaquetarSuperficie(const vx::MeshData& md, const std::vector<uint32_t>& indices, int32_t& nOut) {
    // Compactar: sólo los vértices referenciados por esta superficie (opaca o cristal).
    static thread_local std::vector<int32_t> remap;
    remap.assign(md.verts.size(), -1);
    int32_t n = 0;
    for (uint32_t i : indices) if (remap[i] < 0) remap[i] = n++;

    PackedVector3Array verts; verts.resize(n);
    PackedVector3Array normals; normals.resize(n);
    PackedColorArray colors; colors.resize(n);
    PackedInt32Array idx; idx.resize(static_cast<int64_t>(indices.size()));
    Vector3* vp = verts.ptrw(); Vector3* np = normals.ptrw(); Color* cp = colors.ptrw(); int32_t* ip = idx.ptrw();
    for (size_t i = 0; i < md.verts.size(); ++i) {
        const int32_t r = remap[i];
        if (r < 0) continue;
        const vx::MeshVertex& v = md.verts[i];
        vp[r] = Vector3(v.x, v.y, v.z);
        np[r] = Vector3(static_cast<float>(vx::FACE_DIR[v.normal][0]), static_cast<float>(vx::FACE_DIR[v.normal][1]), static_cast<float>(vx::FACE_DIR[v.normal][2]));
        // Los colores de la tabla son sRGB; el renderer trata COLOR como lineal -> convertir (evita el lavado).
        const Color base = materialLinear(v.mat);
        const float ao = 0.55f + 0.15f * v.ao;
        // SOMBRA DEL SOL HORNEADA (movil, calidad Baja): calculada en el mallado (SolTrazador), no cuesta
        // nada en la GPU. flags bit0 = el mallado la calculo para esta cara, bit1 = esta en sombra.
        const float sombra = ((v.flags & 1) && (v.flags & 2)) ? 0.6f : 1.0f;
        // el alfa lleva cristal / emisivo / follaje / familia de textura (ver refreshMaterialColors)
        if (v.flags & 4) cp[r] = Color(ao * sombra, v.mat / 255.f, 0.f, alfaVertice(v.mat));   // COLOR POR TEXTURA: la luz y el material
        else cp[r] = Color(base.r * ao * sombra, base.g * ao * sombra, base.b * ao * sombra, alfaVertice(v.mat));
    }
    for (size_t k = 0; k < indices.size(); ++k) ip[k] = remap[indices[k]];
    Array arrays; arrays.resize(RenderingServer::ARRAY_MAX);
    arrays[RenderingServer::ARRAY_VERTEX] = verts;
    arrays[RenderingServer::ARRAY_NORMAL] = normals;
    arrays[RenderingServer::ARRAY_COLOR] = colors;
    arrays[RenderingServer::ARRAY_INDEX] = idx;
    nOut = n;
    return arrays;
}

// ---------------------------------------------------------------------------------------------------------------------
// COLOR POR TEXTURA (2026-10-13, pedido: "optimiza el dibujo, la GPU tarda mucho"; medido: el mapa son 4,5 de 7,6 ms de
// GPU en la cafeteria y mas de un millon de triangulos). El mallado funde las caras por GRUPO (Mesher::grupoDe) y no por
// material: en un mapa pintado ladrillo a ladrillo cada ladrillo de otro color era otro rectangulo. El color de cada
// voxel va en una TEXTURA: un Texture2DArray con una capa por chunk (32 x 1024, R8: el id de material de cada voxel en
// el mismo orden que Chunk::vox, x | y<<5 | z<<10, asi que copiarlo es un memcpy) y la paleta (256 x 1, el color lineal
// de cada material). voxel.gdshader (`color_on`) lo lee. Solo el mundo: los bloques sueltos llevan su color en la malla.
// Se activa al cargar el mapa si caben sus chunks (COLOR_TEX_MAX_CAPAS). VX_SIN_COLOR_TEX=1 = como antes.
// ---------------------------------------------------------------------------------------------------------------------
static constexpr int COLOR_TEX_MAX_CAPAS = 2048;
static bool g_ctOn = false;
static Ref<Texture2DArray> g_ctCapas;
static Ref<ImageTexture> g_ctPaleta;
static std::vector<Ref<Image>> g_ctImgs;          // una por CAPA (no por chunk)
static std::vector<int> g_ctSlot;                  // chunk -> capa, o -1 (vacio: sin capa)
static int g_ctUsadas = 0;                          // capas ya dadas
static Ref<Image> g_ctMapaImg;                      // la tabla chunk -> capa + 1, en 16 bits (RG8)
static Ref<ImageTexture> g_ctMapa;
static std::vector<Ref<Image>> g_ctVivas(128);   // imagenes ya subidas que se guardan unos cuadros
static size_t g_ctVivaSig = 0;
static bool g_ctMapaSucio = false;
static std::unordered_set<int> g_ctSucias;
static uint64_t g_ctMatPuesto = 0;
static double g_ctReaplicar = 0.0;

static Ref<Image> imagenDeChunk(const vx::Chunk* c) {
    PackedByteArray b;
    b.resize(vx::CHUNK_VOLUME);
    if (c) std::memcpy(b.ptrw(), c->vox, vx::CHUNK_VOLUME);
    else std::memset(b.ptrw(), 0, vx::CHUNK_VOLUME);
    return Image::create_from_data(vx::CHUNK_SIZE, vx::CHUNK_SIZE * vx::CHUNK_SIZE, false, Image::FORMAT_R8, b);
}

static int64_t g_colRecibidas = 0, g_colIguales = 0;   // mallas de colision recibidas / iguales a la que habia
void VoxelWorld::uploadChunk(vx::ChunkMeshResult& r) {
    if (g_ctOn && r.chunkIdx >= 0 && r.chunkIdx < static_cast<int>(g_ctSlot.size())) g_ctSucias.insert(r.chunkIdx);
    ChunkVis& c = chunks_[r.chunkIdx];
    if (r.empty) { freeChunk(c, r.chunkIdx); return; }
    c.tris = r.mesh.triangles(); c.hasMesh = true;
    // La malla completa se guarda en CPU: la usan el bloque 2x2x2 (render cercano), el caster de sombras
    // de la región y la colisión (todas se generan con un memcpy, sin volver a mallar).
    chunkFull_[r.chunkIdx] = std::move(r.mesh);
    chunkSh_[r.chunkIdx] = std::move(r.sh);
    chunkLod1_[r.chunkIdx] = std::move(r.lod);
    chunkLod2_[r.chunkIdx] = std::move(r.lod2);
    // LOS OCLUSORES, SOLO SI SE USAN (2026-10-01): estan apagados en todos los presets y su malla eran 53 MB en la isla
    // sin servir para nada. Si alguien los enciende a mitad de partida, se van formando segun se remallan los chunks; al
    // cargar un mapa con el ajuste puesto salen todos.
    if (useOccluders_) chunkOcc_[r.chunkIdx] = std::move(r.occ);
    else if (!chunkOcc_[r.chunkIdx].empty()) chunkOcc_[r.chunkIdx] = vx::MeshData{};
    // ¿HA CAMBIADO LA FORMA? Si la malla de colision sale IGUAL que la que ya tenia (un remallado por color -las
    // quemaduras-, por la sombra horneada, por el AO o porque cambio un vecino sin tocar esta superficie), Jolt no tiene
    // nada que rehacer: eran 2-15 ms por chunk tirados. Se comparan vertices (posicion) e indices.
    bool formaNueva = true;
    {
        // a compacta: los triangulos seguidos, cada vertice en voxels del chunk (las posiciones son multiplos exactos)
        const vx::MeshData& mc = r.col;
        const float invVs = 1.0f / engine_->world().voxelSize();
        std::vector<uint8_t> nueva;
        nueva.reserve((mc.idxOpaque.size() + mc.idxGlass.size()) * 3);
        auto meter = [&](const std::vector<uint32_t>& idx) {
            for (uint32_t i : idx) {
                const vx::MeshVertex& v = mc.verts[i];
                nueva.push_back(static_cast<uint8_t>(std::lround(v.x * invVs)));
                nueva.push_back(static_cast<uint8_t>(std::lround(v.y * invVs)));
                nueva.push_back(static_cast<uint8_t>(std::lround(v.z * invVs)));
            }
        };
        meter(mc.idxOpaque);
        meter(mc.idxGlass);
        std::vector<uint8_t>& vieja = chunkCol_[r.chunkIdx];
        if (!vieja.empty() && vieja == nueva) formaNueva = false;
        ++g_colRecibidas; if (!formaNueva) ++g_colIguales;
        vieja.swap(nueva);
    }
    chunkColVer_[r.chunkIdx] = r.version;
    markBlockDirty(blockOfChunk(static_cast<int>(r.chunkIdx)));
    occMarkChunk(static_cast<int>(r.chunkIdx));
    const int rg = regionOfChunk(static_cast<int>(r.chunkIdx));
    if (rg >= 0) { regions_[rg].dirtyFrame = static_cast<uint64_t>(frame_); if (!regions_[rg].dirty) { regions_[rg].dirty = true; dirtyRegions_.push_back(rg); } }
    // si no tiene cuerpo, lo creará updatePhysicsBodies cuando haga falta. Un remallado SOLO DE SOMBRA (la sombra del
    // sol horneada) no cambia ni un voxel: rehacer la colision ahi eran 11-25 ms tirados por chunk.
    if (c.hasPhys && formaNueva) queuePhysics(r.chunkIdx);
}

void VoxelWorld::queuePhysics(uint32_t idx) {
    ChunkVis& c = chunks_[idx];
    if (c.physQueued) return;
    c.physQueued = true;
    physQueue_.push_back(idx);
}

void VoxelWorld::freePhys(ChunkVis& c) {
    PhysicsServer3D* ps = PhysicsServer3D::get_singleton();
    if (ps) {
        if (c.body.is_valid()) ps->free_rid(c.body);
        if (c.shape.is_valid()) ps->free_rid(c.shape);
    }
    c.body = RID(); c.shape = RID();
    if (c.hasPhys) --staticBodies_;
    c.hasPhys = false;
}

void VoxelWorld::set_physics_anchors(const PackedVector3Array& points, float radius) {
    extAnchors_ = points;
    extAnchorRadius_ = std::max(2.f, radius);
}

// Decide qué chunks necesitan cuerpo de colisión: los que están a menos de R de alguna ancla
// (jugador con physRadius_, anclas externas con su radio, piezas rígidas con 6 m). Histéresis del 25 %
// para no crear/destruir en el borde. Coste: ~150 regiones x anclas, y sólo los chunks de las regiones
// candidatas. Los cuerpos lejanos se liberan: Jolt no paga por ellos y la RAM tampoco.
void VoxelWorld::updatePhysicsBodies() {
    if (!engine_) return;
    const vx::World& world = engine_->world();
    const float cs = vx::CHUNK_SIZE * world.voxelSize();
    const float side = REGION * cs;
    anchors_.clear();
    anchors_.push_back(Anchor{playerPos_, physRadius_});
    // TOPE DE ANCLAS. Esta funcion es O(regiones x anclas) y luego O(chunks x anclas) en las
    // regiones candidatas. Con un ancla por cuerpo rigido, un derrumbe de 185 cuerpos disparaba
    // la fase a 9 ms (medido con --stress). Los cuerpos lejanos no necesitan colision de chunk a
    // su alrededor: ya caen por la via "barata". Se conservan los mas cercanos al jugador.
    {
        static thread_local std::vector<Anchor> bodyAnchors;
        bodyAnchors.clear();
        for (const Body& b : bodies_) if (b.rigid) bodyAnchors.push_back(Anchor{b.pos, 6.f});
        constexpr size_t MAX_BODY_ANCHORS = 24;
        if (bodyAnchors.size() > MAX_BODY_ANCHORS) {
            std::nth_element(bodyAnchors.begin(), bodyAnchors.begin() + MAX_BODY_ANCHORS, bodyAnchors.end(),
                [&](const Anchor& a, const Anchor& b2) {
                    return a.p.distance_squared_to(playerPos_) < b2.p.distance_squared_to(playerPos_);
                });
            bodyAnchors.resize(MAX_BODY_ANCHORS);
        }
        for (const Anchor& a : bodyAnchors) anchors_.push_back(a);
    }
    for (int64_t i = 0; i < extAnchors_.size(); ++i) anchors_.push_back(Anchor{extAnchors_[i], extAnchorRadius_});
    // distancia (en múltiplos del radio de cada ancla) de una caja a la ancla más "cercana"
    auto boxRatio = [&](const Vector3& o, float s) -> float {
        float best = 1e30f;
        const Vector3 hi = o + Vector3(s, s, s);
        for (const Anchor& a : anchors_) {
            const Vector3 cl = a.p.clamp(o, hi);
            const float ratio = cl.distance_to(a.p) / a.r;
            if (ratio < best) best = ratio;
        }
        return best;
    };
    const int n = static_cast<int>(regions_.size());
    for (int r = 0; r < n; ++r) {
        const Vector3 ro = regionOrigin(r);
        const bool candidate = boxRatio(ro, side) <= 1.25f;
        const int rx = r % rnx_, ry = (r / rnx_) % rny_, rz = r / (rnx_ * rny_);
        for (int dz = 0; dz < REGION; ++dz) for (int dy = 0; dy < REGION; ++dy) for (int dx = 0; dx < REGION; ++dx) {
            const int cx = rx * REGION + dx, cy = ry * REGION + dy, cz = rz * REGION + dz;
            if (cx >= world.chunksX() || cy >= world.chunksY() || cz >= world.chunksZ()) continue;
            const uint32_t ci = static_cast<uint32_t>(world.chunkIndex(cx, cy, cz));
            ChunkVis& c = chunks_[ci];
            if (!c.hasMesh) continue;
            if (!candidate) { if (c.hasPhys) freePhys(c); continue; }
            const float ratio = boxRatio(ro + Vector3(dx * cs, dy * cs, dz * cs), cs);
            if (c.hasPhys) { if (ratio > 1.25f) freePhys(c); }
            else if (ratio <= 1.0f) queuePhysics(ci);
        }
    }
}

// LO QUE CUESTA DE VERDAD UNA COLISION NUEVA (2026-10-01, medido en la cafeteria con 9 bots): Jolt no construye
// la forma concava al llamar a shape_set_data, sino dentro del SIGUIENTE paso de fisica (arbol BVH de todos sus
// triangulos). El tope de 3 ms de aqui solo veia la copia de las caras, asi que con los bots agujereando paredes
// entraban decenas de chunks de golpe y el paso de fisica se iba a 125-140 ms (tirones de 7 fps cada pocos
// segundos; con --perfsincolchunks desaparecian). Ahora hay tambien un tope de TRIANGULOS por fotograma.
static int64_t g_fisTrisUlt = 0, g_fisTrisPrev = 0, g_fisFormasUlt = 0, g_fisFormasPrev = 0;
static int64_t g_fisTrisTope = -1;   // -1 = sin leer aun; 0 = sin tope (VX_FIS_TRIS=0, para comparar)
static double g_fisMsSet = 0.0, g_fisMsSetMax = 0.0, g_fisMsDespertar = 0.0, g_fisMsDespertarMax = 0.0, g_fisMsCopia = 0.0;

void VoxelWorld::flushPhysics(int budget) {
    g_fisTrisPrev = g_fisTrisUlt; g_fisFormasPrev = g_fisFormasUlt; g_fisTrisUlt = 0; g_fisFormasUlt = 0;
    if (g_fisTrisTope < 0) {
        g_fisTrisTope = 60000;
        if (const char* env = std::getenv("VX_FIS_TRIS")) g_fisTrisTope = std::atoll(env);
    }
    if (!physUpdatesOn_) return;     // --sinfisica del banco: para medir cuanto cuesta rehacer colisiones
    PhysicsServer3D* ps = PhysicsServer3D::get_singleton();
    Ref<World3D> w = get_world_3d();
    if (!w.is_valid() || physQueue_.empty()) return;
    const vx::World& world = engine_->world();
    const float cs = vx::CHUNK_SIZE * world.voxelSize();
    int done = 0;
    std::vector<uint32_t> rest;
    static thread_local PackedVector3Array faces;
    // los más cercanos al jugador primero (tras un teletransporte/respawn la cola puede tener cientos)
    // Selección PARCIAL en vez de ordenación completa: solo hacen falta los `budget` más cercanos,
    // no la cola entera ordenada. Medido con --stress, tras varias explosiones la cola llega a
    // cientos de entradas y este sort (comparador con búsqueda de chunk + distancia) se hacía CADA
    // frame: era parte del pico de esta fase. nth_element es lineal y deja delante los que tocan.
    if (physQueue_.size() > 1) {
        const auto nearer = [&](uint32_t a, uint32_t b) {
            const vx::Chunk* ca = world.chunkAt(static_cast<int>(a)); const vx::Chunk* cb = world.chunkAt(static_cast<int>(b));
            const float da = ca ? toGd(world.chunkOrigin(*ca)).distance_squared_to(playerPos_) : 1e30f;
            const float db = cb ? toGd(world.chunkOrigin(*cb)).distance_squared_to(playerPos_) : 1e30f;
            return da < db;
        };
        const size_t take = std::min(physQueue_.size() - 1, static_cast<size_t>(std::max(1, budget)));
        std::nth_element(physQueue_.begin(), physQueue_.begin() + static_cast<long>(take), physQueue_.end(), nearer);
    }
    // tope de tiempo además del de número: cada forma cóncava de Jolt cuesta 1-4 ms (árbol BVH); tras un
    // derrumbe hay decenas de chunks en cola y sin este tope la física de un frame se iba a 14 ms
    vx::Timer tb;
    for (size_t qi = 0; qi < physQueue_.size(); ++qi) {
        const uint32_t idx = physQueue_[qi];
        ChunkVis& c = chunks_[idx];
        const vx::Chunk* ch = engine_->world().chunkAt(static_cast<int>(idx));
        if (!c.hasMesh || !ch) { c.physQueued = false; continue; }
        const Vector3 origin = toGd(world.chunkOrigin(*ch));
        // el presupuesto no se aplica a los chunks bajo los pies del jugador: nunca debe caer al vacío
        // sólo el chunk que tiene al jugador (o casi) salta el presupuesto; con 5 m, un derrumbe a 8 m del jugador
        // reconstruía todas las formas de golpe (11-14 ms/frame)
        const bool urgent = playerPos_.clamp(origin, origin + Vector3(cs, cs, cs)).distance_to(playerPos_) < 1.5f;
        if ((done >= budget || (!loading_ && done > 0 && tb.ms() > 3.0)) && !urgent) { rest.push_back(idx); continue; }
        vx::Timer tcopia;
        // la malla de colision (misma superficie, sin trocear por colores); si no la hay, la de dibujo como antes.
        // VX_COL_DIBUJO=1: la de dibujo siempre (para comparar)
        static const bool colDibujo = std::getenv("VX_COL_DIBUJO") != nullptr;
        const bool conCol = !colDibujo && idx < chunkCol_.size() && !chunkCol_[idx].empty();
        const vx::MeshData& md = chunkFull_[idx];
        const int64_t trisChunk = conCol ? static_cast<int64_t>(chunkCol_[idx].size() / 9)
                                         : static_cast<int64_t>(md.idxOpaque.size() + md.idxGlass.size()) / 3;
        if (!loading_ && !urgent && g_fisTrisTope > 0 && done > 0 && g_fisTrisUlt + trisChunk > g_fisTrisTope) { rest.push_back(idx); continue; }
        c.physQueued = false;
        int64_t k = 0;
        if (conCol) {
            const std::vector<uint8_t>& cc = chunkCol_[idx];
            const float vsc = world.voxelSize();
            faces.resize(static_cast<int64_t>(cc.size() / 3));
            Vector3* fp = faces.ptrw();
            for (size_t i = 0; i + 2 < cc.size(); i += 3) fp[k++] = Vector3(cc[i] * vsc, cc[i + 1] * vsc, cc[i + 2] * vsc);
        } else {
            faces.resize(static_cast<int64_t>(md.idxOpaque.size() + md.idxGlass.size()));
            Vector3* fp = faces.ptrw();
            for (uint32_t i : md.idxOpaque) { const vx::MeshVertex& v = md.verts[i]; fp[k++] = Vector3(v.x, v.y, v.z); }
            for (uint32_t i : md.idxGlass)  { const vx::MeshVertex& v = md.verts[i]; fp[k++] = Vector3(v.x, v.y, v.z); }
        }
        if (k == 0) { if (c.hasPhys) freePhys(c); continue; }
        if (!c.body.is_valid()) {
            c.shape = ps->concave_polygon_shape_create();
            c.body = ps->body_create();
            ps->body_set_mode(c.body, PhysicsServer3D::BODY_MODE_STATIC);
            ps->body_set_collision_layer(c.body, static_cast<uint32_t>(collisionLayer_));
            ps->body_set_collision_mask(c.body, 0xFFFFFFFFu);
            ps->body_add_shape(c.body, c.shape, Transform3D());
            ps->body_set_state(c.body, PhysicsServer3D::BODY_STATE_TRANSFORM, Transform3D(Basis(), origin));
            ps->body_set_space(c.body, w->get_space());
        }
        Dictionary d; d["faces"] = faces; d["backface_collision"] = false;
        g_fisMsCopia = g_fisMsCopia * 0.95 + tcopia.ms() * 0.05;
        vx::Timer tset;
        ps->shape_set_data(c.shape, d);
        { const double m = tset.ms(); g_fisMsSet = g_fisMsSet * 0.95 + m * 0.05; if (m > g_fisMsSetMax) g_fisMsSetMax = m; }
        g_fisTrisUlt += k / 3; ++g_fisFormasUlt;
        vx::Timer tdesp;
        // LO QUE SE APOYABA EN LA COLISION VIEJA SE DESPIERTA. Jolt no despierta a un cuerpo dormido porque
        // cambie la forma estatica que tiene debajo: un bloque que nace dentro de la colision todavia sin
        // rehacer de lo que acaba de soltarse (el tablero de la mesa, metido en sus propias patas) se queda
        // encajado, se duerme, y cuando esa colision desaparece sigue durmiendo en el aire.
        for (Body& bb : bodies_) {
            if (!bb.rigid || !bb.body.is_valid()) continue;
            const float rr = 0.5f * world.voxelSize() * Vector3(static_cast<float>(bb.data.sx), static_cast<float>(bb.data.sy), static_cast<float>(bb.data.sz)).length();
            const Vector3 bc = bb.xf.origin;
            if (bc.clamp(origin, origin + Vector3(cs, cs, cs)).distance_to(bc) > rr) continue;
            // ...TAMBIEN LOS YA ANCLADOS O CONGELADOS. Un bloque que cae se apoya en la colision VIEJA del
            // chunk (la forma de Jolt se rehace con retraso), se queda quieto, se ancla, y cuando llega la
            // colision nueva ya nadie lo mira: la viga del puente de pruebas se quedaba flotando a 1 m de los
            // tocones. Se despierta; si de verdad tiene suelo, se vuelve a dormir en cuanto se pare.
            if (bb.anclado || bb.congelado) {
                // ...PERO SOLO SI SE PARO HACE POCO (2026-10-10, pedido: "que no se despierten los bloques caidos si no les
                // disparan o golpean"). El fallo de la viga era un bloque que se apoyo en la colision VIEJA mientras se
                // rehacia: eso pasa en los segundos siguientes a pararse. Uno congelado hace mas de 3 s se apoyo en una
                // colision buena; despertarlo en cada balazo cercano llenaba la fisica de bloques despiertos (200 a la
                // vez demoliendo la cafeteria: 10-15 ms de fisica). VX_DESPERTAR_SIEMPRE=1 = como antes.
                static const bool despertarSiempre = std::getenv("VX_DESPERTAR_SIEMPRE") != nullptr;
                bool reciente = !bb.congelado;
                if (bb.congelado) {
                    auto itc = g_congeladoEn.find(bb.data.id);
                    reciente = itc == g_congeladoEn.end() || Time::get_singleton()->get_ticks_msec() - itc->second < 3000;
                }
                if (!loading_ && bb.vuelcos < 4 && (reciente || despertarSiempre)) { ++bb.vuelcos; despertarBloque(bb); bb.gracia = 0.3f; }
                continue;
            }
            ps->body_set_state(bb.body, PhysicsServer3D::BODY_STATE_SLEEPING, false);
            bb.sleeping = false;
        }
        { const double m = tdesp.ms(); g_fisMsDespertar = g_fisMsDespertar * 0.95 + m * 0.05; if (m > g_fisMsDespertarMax) g_fisMsDespertarMax = m; }
        if (!c.hasPhys) ++staticBodies_;
        c.hasPhys = true;
        ++done;
    }
    physQueue_.swap(rest);
    physUpdatesThisFrame_ = done;
}


void VoxelWorld::freeChunk(ChunkVis& c, uint32_t idx) {
    freePhys(c);
    c = ChunkVis{};
    if (idx < chunkLod1_.size()) { chunkLod1_[idx].clear(); chunkLod2_[idx].clear(); chunkOcc_[idx].clear(); chunkFull_[idx].clear(); if (idx < chunkSh_.size()) chunkSh_[idx].clear(); if (idx < chunkCol_.size()) { std::vector<uint8_t>().swap(chunkCol_[idx]); chunkColVer_[idx] = 0xFFFFFFFFu; } }
    if (engine_) {
        occMarkChunk(static_cast<int>(idx));
        markBlockDirty(blockOfChunk(static_cast<int>(idx)));
        const int rg = regionOfChunk(static_cast<int>(idx));
        if (rg >= 0 && rg < static_cast<int>(regions_.size())) { regions_[rg].dirtyFrame = static_cast<uint64_t>(frame_); if (!regions_[rg].dirty) { regions_[rg].dirty = true; dirtyRegions_.push_back(rg); } }
    }
}

// ---------------------------------------------------------------------------
// Regiones: fusión de las mallas LOD de 4x4x4 chunks en un solo draw call
// ---------------------------------------------------------------------------
int VoxelWorld::regionOfChunk(int chunkIdx) const {
    if (!engine_ || chunkIdx < 0) return -1;
    const vx::IVec3 cc = engine_->world().chunkCoords(chunkIdx);
    return (cc.x / REGION) + rnx_ * ((cc.y / REGION) + rny_ * (cc.z / REGION));
}

Vector3 VoxelWorld::regionOrigin(int r) const {
    const int rx = r % rnx_, ry = (r / rnx_) % rny_, rz = r / (rnx_ * rny_);
    const float side = REGION * vx::CHUNK_SIZE * engine_->world().voxelSize();
    return Vector3(rx * side, ry * side, rz * side);
}

void VoxelWorld::freeRegion(RegionVis& rg) {
    RenderingServer* rs = RenderingServer::get_singleton();
    if (rs) {
        if (rg.inst1.is_valid()) rs->free_rid(rg.inst1);
        if (rg.mesh1.is_valid()) rs->free_rid(rg.mesh1);
        if (rg.inst2.is_valid()) rs->free_rid(rg.inst2);
        if (rg.mesh2.is_valid()) rs->free_rid(rg.mesh2);
        if (rg.occInst.is_valid()) rs->free_rid(rg.occInst);
        if (rg.occ.is_valid()) rs->free_rid(rg.occ);
        if (rg.shInst.is_valid()) rs->free_rid(rg.shInst);
        if (rg.shMesh.is_valid()) rs->free_rid(rg.shMesh);
    }
    rg = RegionVis{};
}

void VoxelWorld::rebuildRegion(int r) {
    RegionVis& rg = regions_[r];
    rg.dirty = false;
    rg.lodStale = false;
    RenderingServer* rs = RenderingServer::get_singleton();
    Ref<World3D> w = get_world_3d();
    if (!w.is_valid()) return;
    const vx::World& world = engine_->world();
    const Vector3 ro = regionOrigin(r);
    const int rx = r % rnx_, ry = (r / rnx_) % rny_, rz = r / (rnx_ * rny_);
    for (int level = 0; level < 2; ++level) {
        vx::Timer tr;
        mergeScratch_.clear();
        int members = 0;
        for (int dz = 0; dz < REGION; ++dz) for (int dy = 0; dy < REGION; ++dy) for (int dx = 0; dx < REGION; ++dx) {
            const int cx = rx * REGION + dx, cy = ry * REGION + dy, cz = rz * REGION + dz;
            if (cx >= world.chunksX() || cy >= world.chunksY() || cz >= world.chunksZ()) continue;
            const int ci = world.chunkIndex(cx, cy, cz);
            const vx::MeshData& md = level == 0 ? chunkLod1_[ci] : chunkLod2_[ci];
            if (md.empty()) continue;
            ++members;
            const Vector3 off = Vector3(cx * vx::CHUNK_SIZE * world.voxelSize(), cy * vx::CHUNK_SIZE * world.voxelSize(), cz * vx::CHUNK_SIZE * world.voxelSize()) - ro;
            const uint32_t base = static_cast<uint32_t>(mergeScratch_.verts.size());
            for (const vx::MeshVertex& v : md.verts) { vx::MeshVertex mv = v; mv.x += off.x; mv.y += off.y; mv.z += off.z; mergeScratch_.verts.push_back(mv); }
            for (uint32_t i : md.idxOpaque) mergeScratch_.idxOpaque.push_back(base + i);
            for (uint32_t i : md.idxGlass) mergeScratch_.idxGlass.push_back(base + i);
        }
        RID& mesh = level == 0 ? rg.mesh1 : rg.mesh2;
        RID& inst = level == 0 ? rg.inst1 : rg.inst2;
        int& tris = level == 0 ? rg.tris1 : rg.tris2;
        if (level == 0) rg.members = members;
        const size_t vi = static_cast<size_t>(r) * 2 + static_cast<size_t>(level);
        if (regionVer_.size() < regions_.size() * 2) regionVer_.resize(regions_.size() * 2, 0);
        ++regionVer_[vi];             // lo que hubiera en vuelo para esta malla ya no vale
        if (mergeScratch_.verts.empty()) {
            if (inst.is_valid()) { rs->free_rid(inst); inst = RID(); }
            if (mesh.is_valid()) { rs->free_rid(mesh); mesh = RID(); }
            tris = 0;
            continue;
        }
        fmax(0, tr.ms()); tr = vx::Timer();
        // EN OTRO HILO, como los bloques (ver BlockJob): aqui solo se han juntado los vertices; la malla nueva se crea y
        // se sube alla y drainBlockJobs la pone dos cuadros despues (hasta entonces se ve la vieja). En la carga, aqui.
        static const bool regionesSync = std::getenv("VX_REGIONES_SYNC") != nullptr;   // A/B: como antes
        if (asyncBlocks_ && !loading_ && !regionesSync) {
            if (!blockWorker_.joinable()) {
                blockStop_ = false;
                blockWorker_ = std::thread(&VoxelWorld::blockWorkerLoop, this);
            }
            BlockJob j;
            j.region = r;
            j.level = level;
            j.ver = regionVer_[vi];
            j.matO = opaqueMat_.is_valid() ? opaqueMat_->get_rid() : RID();
            j.matG = glassMat_.is_valid() ? glassMat_->get_rid() : RID();
            j.tris = mergeScratch_.triangles();
            j.md = std::move(mergeScratch_);
            mergeScratch_ = vx::MeshData();
            { std::lock_guard<std::mutex> lk(blockMx_); blockIn_.push_back(std::move(j)); }
            blockCv_.notify_one();
            fmax(1, tr.ms());
            continue;
        }
        const bool first = !mesh.is_valid();
        if (first) mesh = rs->mesh_create(); else rs->mesh_clear(mesh);
        int s = addSurface(mesh, mergeScratch_, mergeScratch_.idxOpaque, opaqueMat_, 0);
        addSurface(mesh, mergeScratch_, mergeScratch_.idxGlass, glassMat_, s);
        tris = mergeScratch_.triangles();
        if (first) {
            inst = rs->instance_create2(mesh, w->get_scenario());
            rs->instance_set_layer_mask(inst, CAPA_MUNDO);
            rs->instance_set_transform(inst, Transform3D(Basis(), ro));
            rs->instance_geometry_set_cast_shadows_setting(inst, RenderingServer::SHADOW_CASTING_SETTING_OFF);
            rs->instance_set_visible(inst, level == 0 ? rg.vis1 : rg.vis2);
            // capa de la transicion suave: 1 = LOD1, 2 = LOD2 (la fina es la 0)
            rs->instance_geometry_set_shader_parameter(inst, "lod_capa", level == 0 ? 1.0f : 2.0f);
        }
        fmax(1, tr.ms());
    }
    { vx::Timer to; rebuildOccluder(r); fmax(2, to.ms()); }
    { vx::Timer tsh; if (regionCastsShadows(rg.state)) rebuildShadowCaster(r); else liberarSombra(rg); fmax(3, tsh.ms()); }
}

void VoxelWorld::liberarSombra(RegionVis& rg) {
    RenderingServer* rs = RenderingServer::get_singleton();
    if (rs) {
        if (rg.shInst.is_valid()) rs->free_rid(rg.shInst);
        if (rg.shMesh.is_valid()) rs->free_rid(rg.shMesh);
    }
    rg.shInst = RID(); rg.shMesh = RID();
    rg.shTris = 0;
    rg.casterStale = true;      // cuando vuelva a proyectar, se rehace (encolarSombra)
}

void VoxelWorld::encolarSombra(int r) {
    if (r < 0 || r >= static_cast<int>(regions_.size()) || regions_[r].enColaSombra) return;
    regions_[r].enColaSombra = true;
    colaSombras_.push_back(r);
}

void VoxelWorld::flushSombras(double tope_ms) {
    if (colaSombras_.empty()) return;
    vx::Timer t;
    size_t i = 0;
    // primero las mas cercanas al jugador (se ordenan las que haya: suelen ser unas pocas)
    std::sort(colaSombras_.begin(), colaSombras_.end(), [&](int a, int b) {
        return regionOrigin(a).distance_squared_to(playerPos_) < regionOrigin(b).distance_squared_to(playerPos_);
    });
    for (; i < colaSombras_.size(); ++i) {
        if (i > 0 && t.ms() > tope_ms) break;
        const int r = colaSombras_[i];
        if (r < 0 || r >= static_cast<int>(regions_.size())) continue;
        RegionVis& rg = regions_[r];
        rg.enColaSombra = false;
        if (rg.casterStale && regionCastsShadows(rg.state)) rebuildShadowCaster(r);
    }
    colaSombras_.erase(colaSombras_.begin(), colaSombras_.begin() + static_cast<long>(i));
}

// ¿Proyecta sombras una región en este estado? Cerca siempre (si el preset las tiene); en LOD1 sólo
// en HIGH/ULTRA, cuya distancia de sombra (60-90 m) llega hasta ahí.
bool VoxelWorld::regionCastsShadows(int state) const {
    if (!engine_ || !engine_->preset().shadows) return false;
    return state == 0 || (state == 1 && quality_ >= 2);
}

// Caster de sombras de la región: la geometría opaca COMPLETA de sus chunks (misma resolución que
// lo que se ve: sin desplazamientos ni sombras falsas) en una sola malla "sólo sombras".
// LA MALLA DEL CASTER DE SOMBRAS (2026-10-10): la de SOMBRA del chunk (la misma silueta en pocos rectangulos, sin colores
// ni cristal) y, si no la hay (VX_SOMBRA_DIBUJO=1 o un chunk aun sin ella), la de dibujo de antes.
const vx::MeshData& VoxelWorld::sombraDe(int ci) const {
    if (ci < static_cast<int>(chunkSh_.size()) && !chunkSh_[ci].idxOpaque.empty()) return chunkSh_[ci];
    return chunkFull_[ci];
}

void VoxelWorld::rebuildShadowCaster(int r) {
    RegionVis& rg = regions_[r];
    RenderingServer* rs = RenderingServer::get_singleton();
    Ref<World3D> w = get_world_3d();
    if (!rs || !w.is_valid()) return;
    const vx::World& world = engine_->world();
    const Vector3 ro = regionOrigin(r);
    const int rx = r % rnx_, ry = (r / rnx_) % rny_, rz = r / (rnx_ * rny_);
    int64_t nv = 0, ni = 0;
    for (int dz = 0; dz < REGION; ++dz) for (int dy = 0; dy < REGION; ++dy) for (int dx = 0; dx < REGION; ++dx) {
        const int cx = rx * REGION + dx, cy = ry * REGION + dy, cz = rz * REGION + dz;
        if (cx >= world.chunksX() || cy >= world.chunksY() || cz >= world.chunksZ()) continue;
        const int ci = world.chunkIndex(cx, cy, cz);
        const vx::MeshData& mc = sombraDe(ci);
        nv += static_cast<int64_t>(mc.verts.size()); ni += static_cast<int64_t>(mc.idxOpaque.size());
    }
    if (ni == 0 || !engine_->preset().shadows) {
        if (rg.shInst.is_valid()) { rs->free_rid(rg.shInst); rg.shInst = RID(); }
        if (rg.shMesh.is_valid()) { rs->free_rid(rg.shMesh); rg.shMesh = RID(); }
        rg.shTris = 0;
        return;
    }
    shVerts_.resize(nv); shIdx_.resize(ni);
    Vector3* vp = shVerts_.ptrw(); int32_t* ip = shIdx_.ptrw();
    int64_t vi = 0, ii = 0; int32_t base = 0;
    // SOLO LAS CARAS QUE MIRAN AL SOL. Una cara que mira al lado contrario nunca es lo mas cercano a la luz,
    // asi que no cambia el mapa de sombras y solo cuesta vertices: en un mundo de voxels son la mitad.
    // Con la direccion a cero (no avisada) se meten todas, como siempre.
    const bool recortar = shadowLightDir_ != Vector3();
    float lit[6];
    for (int f = 0; f < 6; ++f) lit[f] = static_cast<float>(vx::FACE_DIR[f][0]) * shadowLightDir_.x + static_cast<float>(vx::FACE_DIR[f][1]) * shadowLightDir_.y + static_cast<float>(vx::FACE_DIR[f][2]) * shadowLightDir_.z;
    for (int dz = 0; dz < REGION; ++dz) for (int dy = 0; dy < REGION; ++dy) for (int dx = 0; dx < REGION; ++dx) {
        const int cx = rx * REGION + dx, cy = ry * REGION + dy, cz = rz * REGION + dz;
        if (cx >= world.chunksX() || cy >= world.chunksY() || cz >= world.chunksZ()) continue;
        const int ci = world.chunkIndex(cx, cy, cz);
        const vx::MeshData& md = sombraDe(ci);
        if (md.idxOpaque.empty()) continue;
        const Vector3 off = Vector3(cx * vx::CHUNK_SIZE * world.voxelSize(), cy * vx::CHUNK_SIZE * world.voxelSize(), cz * vx::CHUNK_SIZE * world.voxelSize()) - ro;
        for (const vx::MeshVertex& v : md.verts) vp[vi++] = Vector3(v.x, v.y, v.z) + off;
        if (!recortar) {
            for (uint32_t q : md.idxOpaque) ip[ii++] = static_cast<int32_t>(q) + base;
        } else {
            for (size_t t = 0; t + 2 < md.idxOpaque.size(); t += 3) {
                const uint8_t n = md.verts[md.idxOpaque[t]].normal;
                if (n < 6 && lit[n] > 0.f) continue;   // mira al lado contrario del sol
                ip[ii++] = static_cast<int32_t>(md.idxOpaque[t]) + base;
                ip[ii++] = static_cast<int32_t>(md.idxOpaque[t + 1]) + base;
                ip[ii++] = static_cast<int32_t>(md.idxOpaque[t + 2]) + base;
            }
        }
        base += static_cast<int32_t>(md.verts.size());
    }
    rg.casterStale = false;
    if (ii == 0) {
        if (rg.shInst.is_valid()) { rs->free_rid(rg.shInst); rg.shInst = RID(); }
        if (rg.shMesh.is_valid()) { rs->free_rid(rg.shMesh); rg.shMesh = RID(); }
        rg.shTris = 0;
        return;
    }
    if (ii < ni) shIdx_.resize(ii);
    const bool first = !rg.shMesh.is_valid();
    if (first) rg.shMesh = rs->mesh_create(); else rs->mesh_clear(rg.shMesh);
    Array arrays; arrays.resize(RenderingServer::ARRAY_MAX);
    arrays[RenderingServer::ARRAY_VERTEX] = shVerts_;
    arrays[RenderingServer::ARRAY_INDEX] = shIdx_;
    rs->mesh_add_surface_from_arrays(rg.shMesh, RenderingServer::PRIMITIVE_TRIANGLES, arrays);
    if (opaqueMat_.is_valid()) rs->mesh_surface_set_material(rg.shMesh, 0, opaqueMat_->get_rid());
    rg.shTris = static_cast<int>(ii / 3);
    if (first) {
        rg.shInst = rs->instance_create2(rg.shMesh, w->get_scenario());
        rs->instance_set_layer_mask(rg.shInst, CAPA_MUNDO);
        rs->instance_set_transform(rg.shInst, Transform3D(Basis(), ro));
        rs->instance_geometry_set_cast_shadows_setting(rg.shInst, RenderingServer::SHADOW_CASTING_SETTING_SHADOWS_ONLY);
        rs->instance_set_visible(rg.shInst, regionCastsShadows(rg.state));
    }
}

// Occluder de la región: fusiona las mallas occluder conservadoras de sus chunks (voxels 2x, sólo lo
// totalmente sólido y opaco). Godot rasteriza estos triángulos por software y descarta cualquier
// instancia cuyo AABB quede completamente tapado: chunks, regiones, cuerpos, avatares... Como el
// occluder nunca sobresale de la geometría real, jamás oculta algo que debería verse.
void VoxelWorld::rebuildOccluder(int r) {
    RegionVis& rg = regions_[r];
    RenderingServer* rs = RenderingServer::get_singleton();
    Ref<World3D> w = get_world_3d();
    if (!rs || !w.is_valid()) return;
    if (!useOccluders_) {
        if (rg.occInst.is_valid()) { rs->free_rid(rg.occInst); rg.occInst = RID(); }
        if (rg.occ.is_valid()) { rs->free_rid(rg.occ); rg.occ = RID(); }
        rg.occTris = 0;
        return;
    }
    const vx::World& world = engine_->world();
    const Vector3 ro = regionOrigin(r);
    const int rx = r % rnx_, ry = (r / rnx_) % rny_, rz = r / (rnx_ * rny_);
    size_t nv = 0, ni = 0;
    for (int dz = 0; dz < REGION; ++dz) for (int dy = 0; dy < REGION; ++dy) for (int dx = 0; dx < REGION; ++dx) {
        const int cx = rx * REGION + dx, cy = ry * REGION + dy, cz = rz * REGION + dz;
        if (cx >= world.chunksX() || cy >= world.chunksY() || cz >= world.chunksZ()) continue;
        const vx::MeshData& md = chunkOcc_[world.chunkIndex(cx, cy, cz)];
        nv += md.verts.size(); ni += md.idxOpaque.size();
    }
    if (ni == 0) {
        if (rg.occInst.is_valid()) { rs->free_rid(rg.occInst); rg.occInst = RID(); }
        if (rg.occ.is_valid()) { rs->free_rid(rg.occ); rg.occ = RID(); }
        rg.occTris = 0;
        return;
    }
    occVerts_.resize(static_cast<int64_t>(nv)); occIdx_.resize(static_cast<int64_t>(ni));
    Vector3* vp = occVerts_.ptrw(); int32_t* ip = occIdx_.ptrw();
    uint32_t base = 0; size_t vi = 0, ii = 0;
    for (int dz = 0; dz < REGION; ++dz) for (int dy = 0; dy < REGION; ++dy) for (int dx = 0; dx < REGION; ++dx) {
        const int cx = rx * REGION + dx, cy = ry * REGION + dy, cz = rz * REGION + dz;
        if (cx >= world.chunksX() || cy >= world.chunksY() || cz >= world.chunksZ()) continue;
        const vx::MeshData& md = chunkOcc_[world.chunkIndex(cx, cy, cz)];
        if (md.empty()) continue;
        const Vector3 off = Vector3(cx * vx::CHUNK_SIZE * world.voxelSize(), cy * vx::CHUNK_SIZE * world.voxelSize(), cz * vx::CHUNK_SIZE * world.voxelSize()) - ro;
        for (const vx::MeshVertex& v : md.verts) vp[vi++] = Vector3(v.x, v.y, v.z) + off;
        for (uint32_t i : md.idxOpaque) ip[ii++] = static_cast<int32_t>(base + i);
        base += static_cast<uint32_t>(md.verts.size());
    }
    const bool first = !rg.occ.is_valid();
    if (first) rg.occ = rs->occluder_create();
    rs->occluder_set_mesh(rg.occ, occVerts_, occIdx_);
    rg.occTris = static_cast<int>(ni / 3);
    if (first) {
        rg.occInst = rs->instance_create2(rg.occ, w->get_scenario());
        rs->instance_set_transform(rg.occInst, Transform3D(Basis(), ro));
    }
}

void VoxelWorld::set_use_occluders(bool b) {
    if (useOccluders_ == b) return;
    useOccluders_ = b;
    for (size_t r = 0; r < regions_.size(); ++r) rebuildOccluder(static_cast<int>(r));
}

void VoxelWorld::flushRegions(int budget) {
    int done = 0;
    const uint64_t now = static_cast<uint64_t>(frame_);
    for (size_t i = 0; i < dirtyRegions_.size() && done < budget;) {
        const int r = dirtyRegions_[i];
        if (r < 0 || r >= static_cast<int>(regions_.size()) || !regions_[r].dirty) { dirtyRegions_[i] = dirtyRegions_.back(); dirtyRegions_.pop_back(); continue; }
        // debounce: esperar ~21 frames (0,35 s) desde la última marca, salvo en carga
        if (!loading_ && now - regions_[r].dirtyFrame < 12) { ++i; continue; }   // 0,2 s (eran 0,35): la sombra tardaba en acomodarse
        dirtyRegions_[i] = dirtyRegions_.back(); dirtyRegions_.pop_back();
        // LAS MALLAS LOD DE UNA REGION QUE NO SE VE NO SE REHACEN. Una region cercana se dibuja por
        // bloques y una fuera de alcance no se dibuja: sus dos mallas LOD estan ocultas, y aun asi se
        // fusionaban y subian en cada explosion (20-35 ms por region, el mayor pico del hilo principal
        // demoliendo, medido en Monaco con --bancofps). Se dejan marcadas (`lodStale`) y se rehacen
        // cuando la region pase a verse de lejos (updateLod). Lo que si se usa cerca -el caster de
        // sombras y el oclusor- se rehace igual que antes.
        RegionVis& rg = regions_[r];
        // (con la transicion suave, una region cercana SI enseña su LOD1 mas alla de la franja: se rehace)
        if (!loading_ && ((rg.state == 0 && !rg.vis1 && !rg.vis2) || rg.state == 3)) {
            rg.dirty = false;   // sin esto la region no volvia a entrar en la cola y el caster de sombras se quedaba viejo (sombra fantasma)
            rg.lodStale = true;
            if (rg.state == 0) { rebuildOccluder(r); rebuildShadowCaster(r); }
            ++done;
            continue;
        }
        rebuildRegion(r); ++done;
    }
}

// ---------------------------------------------------------------------------
// Bloques: 2x2x2 chunks cercanos fusionados en una malla completa (1 draw call por bloque)
// ---------------------------------------------------------------------------
int VoxelWorld::blockOfChunk(int chunkIdx) const {
    if (!engine_ || chunkIdx < 0) return -1;
    const vx::IVec3 cc = engine_->world().chunkCoords(chunkIdx);
    return (cc.x / BLOCK) + bnx_ * ((cc.y / BLOCK) + bny_ * (cc.z / BLOCK));
}

Vector3 VoxelWorld::blockOrigin(int b) const {
    const int bx = b % bnx_, by = (b / bnx_) % bny_, bz = b / (bnx_ * bny_);
    const float side = BLOCK * vx::CHUNK_SIZE * engine_->world().voxelSize();
    return Vector3(bx * side, by * side, bz * side);
}

// regiones cercanas (estado 0) con bloques aun sin malla: las cuenta updateLod y flushBlocks las atiende primero
static int g_regionesUrgentes = 0;
// VX_BLOQUES_SIEMPRE=1: los bloques lejanos se quedan con su malla, como antes (A/B del banco)
static bool sinSoltarBloques() { static const bool v = std::getenv("VX_BLOQUES_SIEMPRE") != nullptr; return v; }

void VoxelWorld::set_soltar_bloques(int estado_minimo) {
    estadoSoltar_ = estado_minimo < 2 ? 2 : (estado_minimo > 4 ? 4 : estado_minimo);
    // lo que ya se solto y ahora queda por debajo del umbral se vuelve a pedir
    for (int b = 0; b < static_cast<int>(blocks_.size()); ++b) {
        BlockVis& bl = blocks_[b];
        if (!bl.lejos) continue;
        const int rgb = regionDeBloque(b);
        const int st = (rgb >= 0 && rgb < static_cast<int>(regions_.size())) ? regions_[rgb].state : 3;
        if (st < estadoSoltar_) { bl.lejos = false; bl.pendiente = true; markBlockDirty(b); }
    }
}

int VoxelWorld::regionDeBloque(int b) const {
    const int RB = REGION / BLOCK;
    const int bx = b % bnx_, by = (b / bnx_) % bny_, bz = b / (bnx_ * bny_);
    return (bx / RB) + rnx_ * ((by / RB) + rny_ * (bz / RB));
}

void VoxelWorld::soltarBloqueLejos(int b) {
    if (b < 0 || b >= static_cast<int>(blocks_.size())) return;
    BlockVis& bl = blocks_[b];
    RenderingServer* rs = RenderingServer::get_singleton();
    if (rs) {
        if (bl.inst.is_valid()) rs->free_rid(bl.inst);
        if (bl.mesh.is_valid()) rs->free_rid(bl.mesh);
    }
    bl.inst = RID(); bl.mesh = RID(); bl.tris = 0;
    bl.dirty = false;        // mientras siga lejos no se rehace (si sigue en dirtyBlocks_, flushBlocks lo salta)
    bl.lejos = true;
    bl.pendiente = false;
    if (blockVer_.size() < blocks_.size()) blockVer_.resize(blocks_.size(), 0);
    ++blockVer_[b];          // lo que estuviera subiendose para este bloque ya no vale
}

bool VoxelWorld::regionConBloquesPendientes(int r) const {
    const int RB = REGION / BLOCK;
    const int rx = r % rnx_, ry = (r / rnx_) % rny_, rz = r / (rnx_ * rny_);
    for (int dz = 0; dz < RB; ++dz) for (int dy = 0; dy < RB; ++dy) for (int dx = 0; dx < RB; ++dx) {
        const int bx = rx * RB + dx, by = ry * RB + dy, bz = rz * RB + dz;
        if (bx >= bnx_ || by >= bny_ || bz >= bnz_) continue;
        const BlockVis& bl = blocks_[bx + bnx_ * (by + bny_ * bz)];
        if (bl.pendiente || bl.lejos) return true;
    }
    return false;
}

void VoxelWorld::markBlockDirty(int b) {
    if (b < 0 || b >= static_cast<int>(blocks_.size()) || blocks_[b].dirty) return;
    blocks_[b].dirty = true;
    dirtyBlocks_.push_back(b);
}

void VoxelWorld::freeBlock(BlockVis& bl) {
    RenderingServer* rs = RenderingServer::get_singleton();
    if (rs) {
        if (bl.inst.is_valid()) rs->free_rid(bl.inst);
        if (bl.mesh.is_valid()) rs->free_rid(bl.mesh);
    }
    bl = BlockVis{};
}

void VoxelWorld::rebuildBlock(int b) {
    BlockVis& bl = blocks_[b];
    bl.dirty = false;
    RenderingServer* rs = RenderingServer::get_singleton();
    Ref<World3D> w = get_world_3d();
    if (!w.is_valid()) return;
    const vx::World& world = engine_->world();
    const Vector3 bo = blockOrigin(b);
    const int bx = b % bnx_, by = (b / bnx_) % bny_, bz = b / (bnx_ * bny_);
    vx::Timer tb;
    mergeScratch_.clear();
    for (int dz = 0; dz < BLOCK; ++dz) for (int dy = 0; dy < BLOCK; ++dy) for (int dx = 0; dx < BLOCK; ++dx) {
        const int cx = bx * BLOCK + dx, cy = by * BLOCK + dy, cz = bz * BLOCK + dz;
        if (cx >= world.chunksX() || cy >= world.chunksY() || cz >= world.chunksZ()) continue;
        const vx::MeshData& md = chunkFull_[world.chunkIndex(cx, cy, cz)];
        if (md.empty()) continue;
        const Vector3 off = Vector3(cx * vx::CHUNK_SIZE * world.voxelSize(), cy * vx::CHUNK_SIZE * world.voxelSize(), cz * vx::CHUNK_SIZE * world.voxelSize()) - bo;
        const uint32_t base = static_cast<uint32_t>(mergeScratch_.verts.size());
        for (const vx::MeshVertex& v : md.verts) { vx::MeshVertex mv = v; mv.x += off.x; mv.y += off.y; mv.z += off.z; mergeScratch_.verts.push_back(mv); }
        for (uint32_t i : md.idxOpaque) mergeScratch_.idxOpaque.push_back(base + i);
        for (uint32_t i : md.idxGlass) mergeScratch_.idxGlass.push_back(base + i);
    }
    if (blockVer_.size() < blocks_.size()) blockVer_.resize(blocks_.size(), 0);
    ++blockVer_[b];               // lo que hubiera en vuelo para este bloque ya no vale
    if (mergeScratch_.verts.empty()) { freeBlock(bl); return; }
    fmax(4, tb.ms()); tb = vx::Timer();
    if (asyncBlocks_ && !loading_) {
        if (!blockWorker_.joinable()) {
            blockStop_ = false;
            blockWorker_ = std::thread(&VoxelWorld::blockWorkerLoop, this);
        }
        BlockJob j;
        j.block = b;
        j.ver = blockVer_[b];
        j.matO = opaqueMat_.is_valid() ? opaqueMat_->get_rid() : RID();
        j.matG = glassMat_.is_valid() ? glassMat_->get_rid() : RID();
        j.tris = mergeScratch_.triangles();
        j.md = std::move(mergeScratch_);
        mergeScratch_ = vx::MeshData();
        { std::lock_guard<std::mutex> lk(blockMx_); blockIn_.push_back(std::move(j)); }
        blockCv_.notify_one();
        fmax(5, tb.ms());
        return;
    }
    const bool first = !bl.mesh.is_valid();
    if (first) bl.mesh = rs->mesh_create(); else rs->mesh_clear(bl.mesh);
    int s = addSurface(bl.mesh, mergeScratch_, mergeScratch_.idxOpaque, opaqueMat_, 0);
    addSurface(bl.mesh, mergeScratch_, mergeScratch_.idxGlass, glassMat_, s);
    bl.tris = mergeScratch_.triangles();
    bl.pendiente = false;
    bl.lejos = false;
    fmax(5, tb.ms());
    if (bl.shown && !bl.inst.is_valid()) {
        bl.inst = rs->instance_create2(bl.mesh, w->get_scenario());
        rs->instance_set_layer_mask(bl.inst, CAPA_MUNDO);
        rs->instance_set_transform(bl.inst, Transform3D(Basis(), bo));
        rs->instance_geometry_set_shader_parameter(bl.inst, "lod_capa", 0.0f);   // capa fina (transicion suave)
        rs->instance_geometry_set_cast_shadows_setting(bl.inst, RenderingServer::SHADOW_CASTING_SETTING_OFF);
    }
}

// LOS BLOQUES GRANDES SE CONSTRUYEN EN OTRO HILO (2026-10-11, bug: "al dañar un pedazo gigante ya caido el juego se pausa un
// instante"). Rehacer la malla y las cajas de un bloque de 10.000+ voxels eran 4-8 ms por golpe en el hilo principal
// (BodyBuilder, vxcore puro: no toca Godot). Se le pasa una copia de sus voxels; al volver se aplica (cajas en Jolt y la
// malla al hilo de los bloques). Si el bloque recibe otro golpe por el camino, el resultado se tira y se rehace.
// VX_CUERPO_SYNC=1 = como antes.
namespace {
struct CuerpoJob { uint32_t id = 0; uint64_t ver = 0; std::vector<vx::BodyVoxel> vox; float vs = 0.2f; int ncajas = 6; vx::VoxelBody out; };
std::mutex g_cjMx;
std::condition_variable g_cjCv;
std::deque<CuerpoJob> g_cjIn, g_cjOut;
std::thread g_cjHilo;
bool g_cjParar = false;
std::unordered_map<uint32_t, uint64_t> g_vozVer;     // version de los voxels de cada bloque (sube con cada tallada)
std::unordered_set<uint32_t> g_cjEnVuelo;
const bool g_cuerpoSync = std::getenv("VX_CUERPO_SYNC") != nullptr;
constexpr uint32_t CUERPO_ASYNC_MIN = 4000;            // voxels: por debajo, en el sitio (cuesta poco)
void cjBucle() {
    vx::BodyBuilder bb;
    for (;;) {
        CuerpoJob j;
        {
            std::unique_lock<std::mutex> lk(g_cjMx);
            g_cjCv.wait(lk, [] { return g_cjParar || !g_cjIn.empty(); });
            if (g_cjParar) return;
            j = std::move(g_cjIn.front()); g_cjIn.pop_front();
        }
        bb.build(j.vox, j.vs, j.ncajas, j.id, j.out);
        j.vox.clear(); j.vox.shrink_to_fit();
        std::lock_guard<std::mutex> lk(g_cjMx);
        g_cjOut.push_back(std::move(j));
    }
}
void cjPararHilo() {
    if (!g_cjHilo.joinable()) return;
    { std::lock_guard<std::mutex> lk(g_cjMx); g_cjParar = true; }
    g_cjCv.notify_all();
    g_cjHilo.join();
    std::lock_guard<std::mutex> lk(g_cjMx);
    g_cjIn.clear(); g_cjOut.clear(); g_cjEnVuelo.clear(); g_cjParar = false;
}
}  // namespace

// los congelados tallados cuya malla propia no se ha subido (ver reconstruirCuerpo)
static std::unordered_set<uint32_t> g_mallaPendiente;
// la malla de cada bloque grande que esta en el hilo (reconstruirCuerpo -> drainBlockJobs): la ultima pedida vale
static std::unordered_map<uint32_t, uint64_t> g_cuerpoVer;
static uint64_t g_cuerpoVerN = 0;

void VoxelWorld::blockWorkerLoop() {
    RenderingServer* rs = RenderingServer::get_singleton();
    const BitField<RenderingServer::ArrayFormat> fmt(g_compressAttrs ? static_cast<int64_t>(RenderingServer::ARRAY_FLAG_COMPRESS_ATTRIBUTES) : 0);
    for (;;) {
        BlockJob j;
        {
            std::unique_lock<std::mutex> lk(blockMx_);
            blockCv_.wait(lk, [this] { return blockStop_ || !blockIn_.empty(); });
            if (blockStop_) return;
            j = std::move(blockIn_.front());
            blockIn_.pop_front();
        }
        // la malla nueva, entera, desde aqui: la conversion a los buffers de la GPU es lo caro y se hace en este hilo
        j.mesh = rs->mesh_create();
        if (j.grupo != 0) {
            int supg = 0;
            if (!j.arrO.is_empty()) {
                rs->mesh_add_surface_from_arrays(j.mesh, RenderingServer::PRIMITIVE_TRIANGLES, j.arrO);
                if (j.matO.is_valid()) rs->mesh_surface_set_material(j.mesh, supg, j.matO);
                ++supg;
            }
            if (!j.arrG.is_empty()) {
                rs->mesh_add_surface_from_arrays(j.mesh, RenderingServer::PRIMITIVE_TRIANGLES, j.arrG);
                if (j.matG.is_valid()) rs->mesh_surface_set_material(j.mesh, supg, j.matG);
            }
            j.arrO = Array(); j.arrG = Array();
            std::lock_guard<std::mutex> lk(blockMx_);
            blockOut_.push_back(std::move(j));
            continue;
        }
        int32_t n = 0;
        int sup = 0;
        if (!j.md.idxOpaque.empty()) {
            Array a = empaquetarSuperficie(j.md, j.md.idxOpaque, n);
            rs->mesh_add_surface_from_arrays(j.mesh, RenderingServer::PRIMITIVE_TRIANGLES, a, Array(), Dictionary(), fmt);
            if (j.matO.is_valid()) rs->mesh_surface_set_material(j.mesh, sup, j.matO);
            ++sup;
        }
        if (!j.md.idxGlass.empty()) {
            Array a = empaquetarSuperficie(j.md, j.md.idxGlass, n);
            rs->mesh_add_surface_from_arrays(j.mesh, RenderingServer::PRIMITIVE_TRIANGLES, a, Array(), Dictionary(), fmt);
            if (j.matG.is_valid()) rs->mesh_surface_set_material(j.mesh, sup, j.matG);
        }
        j.md = vx::MeshData();
        std::lock_guard<std::mutex> lk(blockMx_);
        blockOut_.push_back(std::move(j));
    }
}

void VoxelWorld::stopBlockWorker() {
    cjPararHilo();
    if (blockWorker_.joinable()) {
        { std::lock_guard<std::mutex> lk(blockMx_); blockStop_ = true; }
        blockCv_.notify_all();
        blockWorker_.join();
    }
    RenderingServer* rs = RenderingServer::get_singleton();
    std::lock_guard<std::mutex> lk(blockMx_);
    if (rs) {
        for (BlockJob& j : blockOut_) if (j.mesh.is_valid()) rs->free_rid(j.mesh);
        for (BlockJob& j : blockSwap_) if (j.mesh.is_valid()) rs->free_rid(j.mesh);
    }
    blockIn_.clear();
    blockOut_.clear();
    blockSwap_.clear();
    blockStop_ = false;
}

/// Lo que ha vuelto del hilo de los bloques. Espera DOS cuadros (a que el servidor de render haya ejecutado la
/// subida que el hilo dejo en su cola) y entonces cambia la malla del bloque de golpe y suelta la vieja. Lo que se
/// quedo viejo por el camino (el bloque cambio otra vez) se tira.
void VoxelWorld::drainBlockJobs() {
    RenderingServer* rs = RenderingServer::get_singleton();
    {
        std::lock_guard<std::mutex> lk(blockMx_);
        for (BlockJob& j : blockOut_) { j.listo = frame_; blockSwap_.push_back(std::move(j)); }
        blockOut_.clear();
    }
    if (blockSwap_.empty()) return;
    Ref<World3D> w = get_world_3d();
    size_t k = 0;
    for (size_t i = 0; i < blockSwap_.size(); ++i) {
        BlockJob& j = blockSwap_[i];
        // LA MALLA DE UN BLOQUE GRANDE TALLADO (reconstruirCuerpo)
        if (j.cuerpo != 0) {
            auto itv = g_cuerpoVer.find(j.cuerpo);
            Body* bc = nullptr;
            if (itv != g_cuerpoVer.end() && itv->second == j.ver)
                for (Body& b2 : bodies_) if (b2.data.id == j.cuerpo) { bc = &b2; break; }
            if (!bc) { if (j.mesh.is_valid()) rs->free_rid(j.mesh); continue; }
            if (frame_ < j.listo + 2) { if (k != i) blockSwap_[k] = std::move(j); ++k; continue; }
            const RID vieja = bc->mesh;
            bc->mesh = j.mesh;
            if (bc->inst.is_valid()) rs->instance_set_base(bc->inst, bc->mesh);
            if (vieja.is_valid()) rs->free_rid(vieja);
            g_cuerpoVer.erase(itv);
            continue;
        }
        // LA MALLA DE UN GRUPO CONGELADO (rehacerUnGrupo)
        if (j.grupo != 0) {
            auto itg = gruposCongelados_.find(j.grupo);
            if (itg == gruposCongelados_.end() || itg->second.ver != j.ver) { if (j.mesh.is_valid()) rs->free_rid(j.mesh); continue; }
            if (frame_ < j.listo + 2) { if (k != i) blockSwap_[k] = std::move(j); ++k; continue; }
            vx::Timer ts;
            GrupoCongelado& g = itg->second;
            const RID vieja = g.mesh;
            g.mesh = j.mesh;
            if (g.inst.is_valid()) {
                rs->instance_set_base(g.inst, g.mesh);
                rs->instance_set_transform(g.inst, Transform3D(Basis(), j.origen));
            } else if (w.is_valid()) {
                g.inst = rs->instance_create2(g.mesh, w->get_scenario());
                rs->instance_set_layer_mask(g.inst, CAPA_MUNDO);
                rs->instance_set_transform(g.inst, Transform3D(Basis(), j.origen));
                ponerTexBloque(g.inst, Vector3(), 2.0f);
                rs->instance_geometry_set_cast_shadows_setting(g.inst, engine_->preset().shadows
                    ? RenderingServer::SHADOW_CASTING_SETTING_ON : RenderingServer::SHADOW_CASTING_SETTING_OFF);
            }
            if (vieja.is_valid()) rs->free_rid(vieja);
            // la malla comun ya esta: se sueltan los dibujos sueltos de los trozos que van dentro (y solo esos: uno que
            // se haya congelado despues sigue con el suyo hasta la siguiente)
            std::sort(j.ids.begin(), j.ids.end());
            for (Body& b2 : bodies_) {
                if (b2.grupo != j.grupo || !b2.inst.is_valid()) continue;
                if (!std::binary_search(j.ids.begin(), j.ids.end(), b2.data.id)) continue;
                rs->free_rid(b2.inst);
                b2.inst = RID();
            }
            fmax(9, ts.ms());
            continue;
        }
        // UNA MALLA LOD DE REGION (rebuildRegion)
        if (j.region >= 0) {
            const size_t vi = static_cast<size_t>(j.region) * 2 + static_cast<size_t>(j.level);
            const bool valeR = j.region < static_cast<int>(regions_.size()) && vi < regionVer_.size() && j.ver == regionVer_[vi];
            if (!valeR) { if (j.mesh.is_valid()) rs->free_rid(j.mesh); continue; }
            if (frame_ < j.listo + 2) { if (k != i) blockSwap_[k] = std::move(j); ++k; continue; }
            vx::Timer ts;
            RegionVis& rg = regions_[j.region];
            RID& mesh = j.level == 0 ? rg.mesh1 : rg.mesh2;
            RID& inst = j.level == 0 ? rg.inst1 : rg.inst2;
            const RID vieja = mesh;
            mesh = j.mesh;
            (j.level == 0 ? rg.tris1 : rg.tris2) = j.tris;
            if (inst.is_valid()) {
                rs->instance_set_base(inst, mesh);
            } else if (w.is_valid()) {
                inst = rs->instance_create2(mesh, w->get_scenario());
                rs->instance_set_layer_mask(inst, CAPA_MUNDO);
                rs->instance_set_transform(inst, Transform3D(Basis(), regionOrigin(j.region)));
                rs->instance_geometry_set_cast_shadows_setting(inst, RenderingServer::SHADOW_CASTING_SETTING_OFF);
                rs->instance_set_visible(inst, j.level == 0 ? rg.vis1 : rg.vis2);
                rs->instance_geometry_set_shader_parameter(inst, "lod_capa", j.level == 0 ? 1.0f : 2.0f);
            }
            if (vieja.is_valid()) rs->free_rid(vieja);
            fmax(9, ts.ms());
            continue;
        }
        const bool vale = j.block >= 0 && j.block < static_cast<int>(blocks_.size()) && j.block < static_cast<int>(blockVer_.size())
                          && j.ver == blockVer_[j.block];
        if (!vale) { if (j.mesh.is_valid()) rs->free_rid(j.mesh); continue; }
        if (frame_ < j.listo + 2) { if (k != i) blockSwap_[k] = std::move(j); ++k; continue; }
        vx::Timer ts;
        BlockVis& bl = blocks_[j.block];
        const RID vieja = bl.mesh;
        bl.mesh = j.mesh;
        bl.pendiente = false;
        bl.lejos = false;
        bl.tris = j.tris;
        if (bl.inst.is_valid()) {
            rs->instance_set_base(bl.inst, bl.mesh);
        } else if (bl.shown && w.is_valid()) {
            bl.inst = rs->instance_create2(bl.mesh, w->get_scenario());
            rs->instance_set_layer_mask(bl.inst, CAPA_MUNDO);
            rs->instance_set_transform(bl.inst, Transform3D(Basis(), blockOrigin(j.block)));
            rs->instance_geometry_set_shader_parameter(bl.inst, "lod_capa", 0.0f);
            rs->instance_geometry_set_cast_shadows_setting(bl.inst, RenderingServer::SHADOW_CASTING_SETTING_OFF);
        }
        if (vieja.is_valid()) rs->free_rid(vieja);
        fmax(9, ts.ms());
    }
    blockSwap_.resize(k);
}

void VoxelWorld::flushBlocks(int budget) {
    if (!physUpdatesOn_) return;     // el banco --sinfisica apaga tambien esto: sirve para medir
    if (budget <= 0) return;
    int done = 0;
    // LO QUE YA ESTA CERCA Y AUN NO TIENE MALLA, PRIMERO Y CON MAS PRESUPUESTO (tras un salto o al reaparecer lejos, sus
    // bloques se soltaron de lejos y la region esta enseñando su LOD1 mientras tanto): se pasan al final de la lista
    // (de donde se saca) y se permiten hasta 8 por cuadro y 8 ms, como un poco de carga.
    double tope = 4.0;
    if (g_regionesUrgentes > 0 && !loading_) {
        std::stable_partition(dirtyBlocks_.begin(), dirtyBlocks_.end(), [&](int b) {
            if (b < 0 || b >= static_cast<int>(blocks_.size()) || !blocks_[b].pendiente) return true;
            const int rgb = regionDeBloque(b);
            return !(rgb >= 0 && rgb < static_cast<int>(regions_.size()) && regions_[rgb].state == 0);
        });
        budget = std::max(budget, 8);
        tope = 8.0;
    }
    // además del tope por número, un tope de tiempo (4 ms): tras un derrumbe hay decenas de bloques sucios y cada
    // reconstrucción son 2-6 ms; sin este límite un frame se iba a 20 ms sólo en mallas
    vx::Timer t;
    while (!dirtyBlocks_.empty() && done < budget && (done == 0 || loading_ || t.ms() < tope)) {
        const int b = dirtyBlocks_.back();
        dirtyBlocks_.pop_back();
        if (b >= 0 && b < static_cast<int>(blocks_.size()) && blocks_[b].dirty) {
            const int rgb = regionDeBloque(b);
            const int stb = (rgb >= 0 && rgb < static_cast<int>(regions_.size())) ? regions_[rgb].state : -1;
            if (stb >= estadoSoltar_ && !sinSoltarBloques()) { soltarBloqueLejos(b); continue; }   // lejos: ni se rehace ni se sube
            rebuildBlock(b); ++done;
        }
    }
}

// La instancia sólo existe mientras el bloque está en una región cercana: el culling de Godot recorre
// todas las instancias del escenario, así que las lejanas no deben existir (ni siquiera invisibles).
void VoxelWorld::setBlockShown(int b, bool shown) {
    BlockVis& bl = blocks_[b];
    if (bl.shown == shown) return;
    bl.shown = shown;
    RenderingServer* rs = RenderingServer::get_singleton();
    if (shown) {
        if (!bl.inst.is_valid() && bl.mesh.is_valid()) {
            Ref<World3D> w = get_world_3d();
            if (!w.is_valid()) return;
            bl.inst = rs->instance_create2(bl.mesh, w->get_scenario());
            rs->instance_set_layer_mask(bl.inst, CAPA_MUNDO);
            rs->instance_set_transform(bl.inst, Transform3D(Basis(), blockOrigin(b)));
            rs->instance_geometry_set_shader_parameter(bl.inst, "lod_capa", 0.0f);   // capa fina (transicion suave)
            rs->instance_geometry_set_cast_shadows_setting(bl.inst, RenderingServer::SHADOW_CASTING_SETTING_OFF);
        }
    } else if (bl.inst.is_valid()) {
        rs->free_rid(bl.inst);
        bl.inst = RID();
    }
}

// ---------------------------------------------------------------------------
// Piezas desprendidas
// ---------------------------------------------------------------------------
vx::Transform VoxelWorld::toVx(const Transform3D& t) {
    vx::Transform r;
    for (int i = 0; i < 3; ++i) { for (int j = 0; j < 3; ++j) r.m[i][j] = t.basis[i][j]; r.m[i][3] = t.origin[i]; }
    return r;
}
Transform3D VoxelWorld::fromVx(const vx::Vec3& p) { return Transform3D(Basis(), toGd(p)); }

/// VOXELS QUE TIENE QUE TENER UN TROZO PARA CAER CON FISICA DE VERDAD (Jolt) en vez de "barato".
/// Es una constante de JUEGO: identica en PC y en movil y a cualquier tasa de fotogramas, para que
/// el mismo derrumbe se comporte igual en las dos pantallas. A 25 cm por voxel son ~0,75 m3.
static constexpr int VOXELS_CUERPO_RIGIDO = 12;

/// Tope de seguridad, y SOLO de seguridad. La regla de arriba no esta acotada: un derrumbe enorme
/// podria pedir cientos de cuerpos rigidos a la vez y tumbar un movil. Se pone MUY por encima de lo
/// que pide un derrumbe normal (medido: 36-50 cuerpos) para que en juego no llegue a tocarse nunca;
/// si se toca, esa maquina se separa de las demas, y por eso se CUENTA (`rigid_topados` en
/// `get_stats`) en vez de degradarse en silencio: si ese contador sube en una partida, el umbral de
/// arriba se ha quedado corto y hay que revisarlo, no subir el tope.
static constexpr int TOPE_RIGIDOS_DURO = 256;
static int64_t g_rigidTopados = 0;

void VoxelWorld::spawnPiece(vx::VoxelBody&& piece) {
    const vx::QualityPreset& preset = engine_->preset();
    // YA NO SE ANUNCIA CADA PIEZA SUELTA. El invitado desprende lo mismo por su cuenta a partir del
    // mismo daño (ver `set_red`); mandarselo ademas le quitaba del mapa celdas que el ya habia
    // quitado y le dejaba el mundo con el doble de destruccion. Lo unico que viaja es el asiento.
    const Vector3 com = toGd(piece.worldCom());
    const float d = com.distance_to(playerPos_);
    const float vs = engine_->world().voxelSize();
    const vx::Vec3& av0 = piece.initialAngVel;
    const bool structural = av0.x != 0 || av0.y != 0 || av0.z != 0;   // trozo de un derrumbe por sobrecarga
    { static const bool lp = std::getenv("VX_LOGPIECES") != nullptr; if (lp) std::fprintf(stderr, "[pieza] t=%.2f vox=%u %s en (%.1f,%.1f,%.1f)", static_cast<double>(godot::Time::get_singleton()->get_ticks_msec()) / 1000.0, piece.voxelCount, structural ? "DERRUMBE" : "suelta", com.x, com.y, com.z); if (lp) std::fputc(10, stderr); }
    {
        const int64_t nv = static_cast<int64_t>(piece.voxelCount);
        if (structural) { ++g_pzEstruct; g_voxEstruct += nv; } else { ++g_pzSueltas; g_voxSueltas += nv; }
        if (nv >= 10000) ++g_pzGrandes;
        if (nv > g_pzMayor) g_pzMayor = nv;
    }
    // AQUI HABIA UN ATAJO Y SE HA IDO. Si el trozo caia lejos y sin nadie cerca, el anfitrion lo
    // TELETRANSPORTABA al suelo y lo re-voxelizaba de golpe, y el invitado directamente lo TIRABA a
    // la basura ("ya le llegara el asiento"). Las dos cosas rompen la regla: un bloque que se cae
    // tiene que ser el mismo bloque en el suelo, lo mire alguien o no.
    //
    // Ademas el descarte del invitado dejaba un agujero real medido en el banco: el anfitrion
    // congelaba un trozo y mandaba su postura por id, pero el invitado no tenia ese trozo porque lo
    // habia tirado, asi que en su pantalla no existia (contador `congel_desconocidos`).
    //
    // Lo que se ahorraba en dibujar lo ahorra ahora la fusion por celdas de `rehacerUnGrupo`, que es
    // donde toca: cambiando como se DIBUJA, no cambiando lo que ES.
    (void)structural;
    RenderingServer* rs = RenderingServer::get_singleton();
    PhysicsServer3D* ps = PhysicsServer3D::get_singleton();
    Ref<World3D> w = get_world_3d();
    if (!w.is_valid()) return;

    vx::Timer tpz;
    Body b;
    b.data = std::move(piece);
    b.pos = com;
    b.texOrg = com;   // la malla va respecto al COM: vertice + COM del mundo = donde estaba ese voxel (textura sin salto al soltarse)
    // tope duro de cuerpos Jolt: por encima de maxBodies la pieza cae "barata" (cinemática, sin colisiones
    // entre cuerpos). En un derrumbe salían 128 cuerpos rígidos a la vez y la física se comía 10-50 ms/frame.
    // Los trozos de un derrumbe estructural (llevan giro inicial) son siempre rígidos: si cayeran "baratos"
    // (recto hacia abajo) aterrizarían sobre lo que tienen justo debajo, se fijarían y el edificio se
    // "reconstruiría" en el sitio como pila. El exceso se compensa re-voxelizando antes los dormidos (overBudget).
    // Derrumbe: rígidos hasta 2x maxBodies (Jolt aguanta ~128 cajas compuestas a 60 Hz), el resto caen baratos
    // con el empuje lateral del vuelco para que se desparramen en vez de apilarse alineados.
    // (128 cuerpos Jolt grandes eran 23-32 ms de física por frame en la máquina de referencia: tope = maxBodies;
    // los trozos van ordenados de mayor a menor, así los grandes y visibles son los que se llevan la física)
    // QUIEN LLEVA FISICA DE VERDAD NO LO DECIDE EL APARATO, LO DECIDE EL TROZO.
    //
    // Esto era `d <= preset.simRadius && rigidCount_ < preset.maxBodies`, y los dos terminos son
    // datos LOCALES: `d` es la distancia al jugador de ESTA maquina y `preset` es la calidad de ESTA
    // maquina (LOW simula 24 cuerpos en 20 m, ULTRA 160 en 55 m). El mismo trozo salia cuerpo Jolt
    // en un PC y caida barata -recta hacia abajo- en un movil, asi que dos jugadores con el mismo
    // daño replicado veian dos derrumbes sin ninguna relacion. Y como la cola de piezas se drena con
    // presupuesto de TIEMPO (5 ms/frame), hasta dos maquinas iguales a distintos fps repartian
    // distinto: medido con --fisicatest, el mismo derribo daba 32 piezas a 15 fps y 20 a 120.
    //
    // Es la misma regla que ya se aplico a los cascotes en `main._throttle_clumps` cuando el
    // regulador de fps decidia cuantos soltaba una explosion: el rendimiento puede cambiar lo que se
    // DIBUJA, nunca lo que EXISTE. Un trozo grande lleva fisica en todas partes y uno pequeño en
    // ninguna, y el umbral es un numero de juego, igual en PC y en movil.
    const bool quiereRigido = static_cast<int>(b.data.voxelCount) >= VOXELS_CUERPO_RIGIDO;
    b.rigid = quiereRigido && rigidCount_ < TOPE_RIGIDOS_DURO;
    if (quiereRigido && !b.rigid) ++g_rigidTopados;
    (void)structural; (void)d;
    if (b.rigid) ++rigidCount_;
    b.drift = Vector3(b.data.initialVel.x, 0, b.data.initialVel.z);
    if (!b.rigid && structural) {
        // sin física propia: el giro del vuelco se traduce en desplazamiento lateral hacia el lado sin apoyo
        const Vector3 side = Vector3(av0.z, 0, -av0.x);   // eje = up x dir  ->  dir = (az, 0, -ax)
        b.drift += side.normalized() * (2.0f + 1.5f * static_cast<float>(b.data.id % 5) / 4.0f);
    }
    b.mesh = rs->mesh_create();
    int s = addSurface(b.mesh, b.data.mesh, b.data.mesh.idxOpaque, opaqueMat_, 0);
    addSurface(b.mesh, b.data.mesh, b.data.mesh.idxGlass, glassMat_, s);
    b.inst = rs->instance_create2(b.mesh, w->get_scenario());
    rs->instance_set_layer_mask(b.inst, CAPA_MUNDO);
    fmax(6, tpz.ms()); tpz = vx::Timer();
    rs->instance_set_transform(b.inst, Transform3D(Basis(), com));
    ponerTexBloque(b.inst, b.texOrg, 1.0f);
    // SOMBRA SOLO LOS TROZOS GRANDES. Cada instancia que proyecta sombra se dibuja OTRA VEZ en el mapa
    // de sombras: en una demolicion son decenas de pasadas extra por un cascote que va por el aire medio
    // segundo y que nadie mira. Los pedazos grandes (los que se ven caer) si la proyectan, y una vez
    // parados la malla fundida del grupo la proyecta entera.
    rs->instance_geometry_set_cast_shadows_setting(b.inst,
        (preset.shadows && b.data.voxelCount >= 48) ? RenderingServer::SHADOW_CASTING_SETTING_ON
                                                    : RenderingServer::SHADOW_CASTING_SETTING_OFF);
    // COLISION PARA TODOS LOS CUERPOS, no sólo los rígidos.
    // Antes, un trozo "barato" era puro dibujo: sin cuerpo de física el jugador lo ATRAVESABA y se caía
    // al vacío, los cohetes y las balas pasaban de largo sin hacerle daño, y sólo volvía a ser sólido
    // cuando aterrizaba y se re-voxelizaba al mundo (de ahí que "a los segundos se solidifica"). En un
    // derrumbe la inmensa mayoría de los trozos son baratos (rigidCount_ está topado por maxBodies), así
    // que el edificio que caía era un fantasma. Un cuerpo CINEMATICO cuesta broadphase + contactos y no
    // se resuelve como dinámico: es asumible y devuelve la solidez.
    // Los cascotes minúsculos no necesitan colisión propia (nadie nota atravesar una esquirla de 2 cm)
    // y son la mayoría en un derrumbe: el presupuesto se gasta en las piezas grandes, que son las que
    // el jugador pisa y las que le tapan la bala.
    const int cheapMax = cheapSolidMax_ >= 0 ? cheapSolidMax_ : preset.maxBodies * 6;
    // CERCA DE UN PERSONAJE, SIEMPRE SOLIDO. Al agotarse el presupuesto los trozos nuevos salian
    // fantasma, y en un derrumbe grande eso incluia el pedazo que alguien tenia bajo los pies: lo
    // atravesaba y se caia al vacio. Antes esto solo miraba al jugador LOCAL y solo al nacer el trozo;
    // ahora vale para cualquier personaje (bots y remotos incluidos) y se vuelve a mirar cada frame en
    // `solidificarCerca`, porque un trozo puede nacer lejos y caer justo al lado de alguien.
    const bool cerca = b.data.voxelCount >= 8 && cercaDeAlguien(com, RADIO_SOLIDO);
    b.solid = b.rigid || cerca || (d <= preset.cheapFallRadius && b.data.voxelCount >= 8 && cheapSolidCount_ < cheapMax);
    if (b.solid) {
        b.body = ps->body_create();
        ps->body_set_mode(b.body, b.rigid ? PhysicsServer3D::BODY_MODE_RIGID : PhysicsServer3D::BODY_MODE_KINEMATIC);
        // los baratos van con menos cajas: su colisión es "no atravesable", no un ajuste fino
        vx::Timer tsh;
        const int maxBoxes = b.rigid ? static_cast<int>(b.data.boxes.size()) : std::min<int>(4, static_cast<int>(b.data.boxes.size()));
        for (int bi = 0; bi < maxBoxes; ++bi) {
            const vx::Box& box = b.data.boxes[static_cast<size_t>(bi)];
            RID sh = ps->box_shape_create();
            ps->shape_set_data(sh, toGd(box.halfExtents));
            ps->body_add_shape(b.body, sh, Transform3D(Basis(), toGd(box.center)));
            b.shapes.push_back(sh);
        }
        ps->body_set_param(b.body, PhysicsServer3D::BODY_PARAM_MASS, std::max(1.0f, b.data.mass));
        // fricción y restitución del material dominante (tabla centralizada de vxcore)
        ps->body_set_param(b.body, PhysicsServer3D::BODY_PARAM_FRICTION, vx::material(b.data.dominantMat).phys.friction);
        ps->body_set_param(b.body, PhysicsServer3D::BODY_PARAM_BOUNCE, vx::material(b.data.dominantMat).phys.restitution);
        // Mientras cae no colisiona con otros escombros: esa interacción es
        // costosa, poco legible y hace crecer islas enteras de Jolt. Sí choca
        // con escenario y personajes; al dormir cambia a capa estática.
        ps->body_set_collision_layer(b.body, CAPA_ESCOMBRO_MOVIL);
        ps->body_set_collision_mask(b.body, MASCARA_ESCOMBRO_MOVIL | static_cast<uint32_t>(collisionLayer_));
        fmax(10, tsh.ms());
        ps->body_set_state(b.body, PhysicsServer3D::BODY_STATE_TRANSFORM, Transform3D(Basis(), com));
        b.xf = Transform3D(Basis(), com);
        if (b.rigid) {
            // Caida en "camara lenta" para los trozos desprendidos: un derrumbe a gravedad real se
            // resuelve en menos de un segundo y no se ve. Solo afecta a los escombros; el jugador y
            // los bots caen normal. Ajustable en caliente con set_piece_gravity().
            ps->body_set_param(b.body, PhysicsServer3D::BODY_PARAM_GRAVITY_SCALE, pieceGravityFor(static_cast<int>(b.data.voxelCount)));
            const vx::Vec3& av = b.data.initialAngVel;
            if (av.x != 0 || av.y != 0 || av.z != 0) {
                // estructura que cede: se inclina hacia el lado sin apoyo
                ps->body_set_state(b.body, PhysicsServer3D::BODY_STATE_LINEAR_VELOCITY, toGd(b.data.initialVel));
                ps->body_set_state(b.body, PhysicsServer3D::BODY_STATE_ANGULAR_VELOCITY, toGd(av));
            } else if (b.data.initialVel.x != 0 || b.data.initialVel.y != 0 || b.data.initialVel.z != 0) {
                ps->body_set_state(b.body, PhysicsServer3D::BODY_STATE_LINEAR_VELOCITY, toGd(b.data.initialVel));
                const float a = static_cast<float>(b.data.id % 7) - 3.0f;
                ps->body_set_state(b.body, PhysicsServer3D::BODY_STATE_ANGULAR_VELOCITY, Vector3(a, a * 0.5f, -a));
            }
            // el servidor nos empuja transform/velocidad/sueño tras cada paso: cero lecturas bloqueantes
            ps->body_set_state_sync_callback(b.body, Callable(this, "_on_body_state").bind(b.body));
            if (interpolar_) ps->body_set_enable_continuous_collision_detection(b.body, true);
        } else {
            ++cheapSolidCount_;
        }
        { vx::Timer tsp; ps->body_set_space(b.body, w->get_space()); fmax(11, tsp.ms()); }
        // EL GIRO DEL VUELCO, OTRA VEZ, YA DENTRO DEL ESPACIO. Puesto antes de `body_set_space` no llegaba a
        // Jolt: medido con --mesatraza, el tablero de la mesa nacia con velocidad y giro CERO aunque el
        // derrumbe le habia calculado su vuelco hacia el lado sin patas.
        if (b.rigid) {
            const vx::Vec3& av2 = b.data.initialAngVel;
            const vx::Vec3& lv2 = b.data.initialVel;
            if (av2.x != 0 || av2.y != 0 || av2.z != 0) {
                ps->body_set_state(b.body, PhysicsServer3D::BODY_STATE_LINEAR_VELOCITY, toGd(lv2));
                ps->body_set_state(b.body, PhysicsServer3D::BODY_STATE_ANGULAR_VELOCITY, toGd(av2));
            } else if (lv2.x != 0 || lv2.y != 0 || lv2.z != 0) {
                ps->body_set_state(b.body, PhysicsServer3D::BODY_STATE_LINEAR_VELOCITY, toGd(lv2));
                const float a2 = static_cast<float>(b.data.id % 7) - 3.0f;
                ps->body_set_state(b.body, PhysicsServer3D::BODY_STATE_ANGULAR_VELOCITY, Vector3(a2, a2 * 0.5f, -a2));
            }
        }
    }
    b.origen = com;
    // UN TROZO GRANDE QUE SE SUELTA DESPIERTA A LOS BLOQUES DORMIDOS QUE TIENE ALREDEDOR. Los pedazos que se
    // rompieron antes (la esquina del tablero sobre cada pata cortada) se quedan congelados en su sitio,
    // estaticos, y cuando por fin se suelta todo el tablero se apoya EN ELLOS: soportes fantasma en el
    // aire. Medido con --mesatraza: el tablero de 70.000 voxels quieto sobre 16 contactos con bloques
    // congelados a su misma altura. Despiertos, caen con el.
    if (b.data.voxelCount >= 1000 && !creandoDeRed_) {
        const float radioPieza = 0.5f * engine_->world().voxelSize() *
            Vector3(static_cast<float>(b.data.sx), static_cast<float>(b.data.sy), static_cast<float>(b.data.sz)).length();
        despertarSobre(com - Vector3(0.f, radioPieza, 0.f), radioPieza * 2.f);
    }
    // ¿Traia ya su postura final de casa? Llega cuando el aviso del anfitrion adelanta al nacimiento
    // de la pieza. Se congela en el acto, en la postura buena, sin dejarla caer por su cuenta.
    if (!congelPendientes_.empty()) {
        auto it = congelPendientes_.find(static_cast<int64_t>(b.data.id));
        if (it != congelPendientes_.end()) {
            const Transform3D xf = it->second;
            congelPendientes_.erase(it);
            congelarPieza(b, xf);
        }
    }
    if (b.rigid) ++spawnRigid_; else if (b.solid) ++spawnCheapSolid_; else ++spawnCheapGhost_;
    if (!creandoDeRed_) emit_signal("piece_detached", com, static_cast<int>(b.data.voxelCount), static_cast<int>(b.data.dominantMat));
    fmax(7, tpz.ms());
    bodies_.push_back(std::move(b));
}

/// ¿Hay algun personaje a menos de `r`? El jugador local va aparte porque `personajes_` lo rellena el
/// juego una vez por frame y puede llegar vacio (menus, arranque, pruebas sin bots).
bool VoxelWorld::cercaDeAlguien(const Vector3& p, float r) const {
    if (p.distance_to(playerPos_) <= r) return true;
    const float r2 = r * r;
    for (int64_t i = 0; i < personajes_.size(); ++i) if (p.distance_squared_to(personajes_[i]) <= r2) return true;
    return false;
}

/// Da colision a los trozos fantasma que hayan quedado cerca de alguien. Se revisa cada frame porque un
/// trozo puede nacer lejos (y salir fantasma) y caer justo encima de un personaje: es exactamente lo que
/// pasaba cuando a un bot subido a una estructura se le rompia debajo y se colaba al vacio.
void VoxelWorld::solidificarCerca() {
    if (!engine_) return;
    PhysicsServer3D* ps = PhysicsServer3D::get_singleton();
    World3D* w = get_world_3d().ptr();
    if (!ps || !w) return;
    int nuevos = 0;
    for (Body& b : bodies_) {
        if (b.solid || b.body.is_valid()) continue;
        // Las esquirlas no: nadie nota atravesar un cascote de 20 cm, y en un derrumbe son cientos.
        // El presupuesto de Jolt se gasta en lo que se pisa y lo que tapa.
        if (b.data.voxelCount < 8 || b.data.boxes.empty()) continue;
        const Vector3 p = b.rigid ? b.xf.origin : b.pos;
        if (!cercaDeAlguien(p, RADIO_SOLIDO)) continue;
        b.body = ps->body_create();
        ps->body_set_mode(b.body, PhysicsServer3D::BODY_MODE_KINEMATIC);
        const int maxBoxes = std::min<int>(4, static_cast<int>(b.data.boxes.size()));
        for (int bi = 0; bi < maxBoxes; ++bi) {
            const vx::Box& box = b.data.boxes[static_cast<size_t>(bi)];
            RID sh = ps->box_shape_create();
            ps->shape_set_data(sh, toGd(box.halfExtents));
            ps->body_add_shape(b.body, sh, Transform3D(Basis(), toGd(box.center)));
            b.shapes.push_back(sh);
        }
        ps->body_set_param(b.body, PhysicsServer3D::BODY_PARAM_FRICTION, vx::material(b.data.dominantMat).phys.friction);
        ps->body_set_collision_layer(b.body, CAPA_ESCOMBRO_MOVIL);
        ps->body_set_collision_mask(b.body, MASCARA_ESCOMBRO_MOVIL | static_cast<uint32_t>(collisionLayer_));
        ps->body_set_state(b.body, PhysicsServer3D::BODY_STATE_TRANSFORM, Transform3D(Basis(), p));
        ps->body_set_space(b.body, w->get_space());
        b.solid = true;
        ++cheapSolidCount_;
        // Un puñado por frame: crear cuerpos en Jolt cuesta, y en un derrumbe grande podrian ser cientos
        // de golpe. Los que falten entran en los frames siguientes, que son milisegundos.
        if (++nuevos >= 8) return;
    }
}

void VoxelWorld::_on_body_state(PhysicsDirectBodyState3D* state, const RID& body) {
    if (!state) return;
    vx::Timer tbs;
    static const bool lineal = std::getenv("VX_BODYSTATE_LINEAL") != nullptr;
    Body* bp = nullptr;
    if (!lineal) {
        auto it = g_idxCuerpo.find(body.get_id());
        if (it != g_idxCuerpo.end() && it->second < bodies_.size() && bodies_[it->second].body == body) bp = &bodies_[it->second];
    }
    if (bp == nullptr) {
        for (size_t i = 0; i < bodies_.size(); ++i) {
            if (bodies_[i].body != body) continue;
            bp = &bodies_[i];
            if (!lineal) g_idxCuerpo[body.get_id()] = i;
            break;
        }
    }
    if (bp != nullptr) {
        Body& b = *bp;
        if (interpolar_) { b.xfAnt = b.xfAntOk ? b.xf : state->get_transform(); b.xfAntOk = true; }
        b.xf = state->get_transform();
        b.linVel = state->get_linear_velocity();
        b.sleeping = state->is_sleeping();
    }
    g_bsTotalMs += tbs.ms();
    ++g_bsLlamadas;
}

// LEJOS DE TODOS, SE DUERME (2026-09-28). Los cuerpos que se han dormido a mano por estar lejos de cualquier
// personaje (ver stepBodies), por su id de cuerpo: al acercarse alguien se despiertan.
static std::unordered_set<uint64_t> g_dormidosLejos;
static const float DORMIR_LEJOS_M = 70.f;
// --fisica30: la velocidad maxima de un bloque o cascote (m/s). A 30 Hz son 0,6 m por paso, y la deteccion continua
// hace el resto con los finos.
static const float VEL_MAX_30HZ = 18.f;

void VoxelWorld::freeBody(Body& b) {
    g_velAnt.erase(b.data.id);
    if (b.body.is_valid()) { g_dormidosLejos.erase(b.body.get_id()); g_idxCuerpo.erase(b.body.get_id()); }
    // UN DORMIDO SE DIBUJA EN LA MALLA COMUN DE SU CELDA, no con la suya. Borrarlo sin ensuciar el grupo
    // dejaba su dibujo ahi, sin fisica, hasta que otra cosa volviera a tocar esa celda (podian ser
    // minutos): era lo que pasaba al rematar a tiros o a mazo un cascote caido. Medido con --congelatest
    // ("DIBUJO SIN BLOQUE"). Aqui y no en cada llamada: hay seis caminos que borran bloques.
    if (b.grupo) { ensuciarGrupo(b.grupo); b.grupo = 0; }
    RenderingServer* rs = RenderingServer::get_singleton();
    PhysicsServer3D* ps = PhysicsServer3D::get_singleton();
    if (rs) { if (b.inst.is_valid()) rs->free_rid(b.inst); if (b.mesh.is_valid()) rs->free_rid(b.mesh); }
    if (ps) { if (b.body.is_valid()) ps->free_rid(b.body); for (RID& s : b.shapes) if (s.is_valid()) ps->free_rid(s); }
    b.inst = RID(); b.mesh = RID(); b.body = RID(); b.shapes.clear();
}

// ¿Descansa el cuerpo sobre voxels estáticos? Sondas hacia abajo desde su cara inferior (centro y cuartos).

// A partir de este tamano un trozo caido pesa demasiado para empujarlo andando (a 10 cm el voxel,
// veinte voxels son ya medio saco de escombros).
static const int VOXELS_EMPUJABLES = 20;
/// Un trozo de hasta tantos voxels es ESCOMBRO de explosion (le afecta la prisa); mas grande es parte de un derrumbe.
static const int ESCOMBRO_CHICO = 800;

void VoxelWorld::set_settle_authority(bool manda) { settleAuthority_ = manda; }

// --FISICA30 (2026-09-28, pedido): la fisica a 30 pasos por segundo (lo pone el juego: Engine.physics_ticks_per_second)
// y aqui lo que hace falta para que se vea y se comporte bien:
//   - los bloques se DIBUJAN entre la postura del paso anterior y la del ultimo (la fraccion de Godot), asi que se
//     mueven suaves aunque la fisica vaya a la mitad de pasos;
//   - DETECCION CONTINUA de choques: un cascote rapido no cruza un suelo fino entre dos pasos;
//   - TOPE DE VELOCIDAD (VEL_MAX_30HZ, en stepBodies): nada va tan rapido como para atravesar.
void VoxelWorld::set_interpolar(bool si) {
    interpolar_ = si;
    PhysicsServer3D* ps = PhysicsServer3D::get_singleton();
    for (Body& b : bodies_) {
        b.xfAntOk = false;
        if (ps && b.body.is_valid()) ps->body_set_enable_continuous_collision_detection(b.body, si);
    }
}


void VoxelWorld::set_red(bool en_red, bool soy_host) {
    enRed_ = en_red;
    soyHost_ = soy_host;
    // el invitado no separa nada por su cuenta: lo que se cae se lo dice el anfitrion
    // EL INVITADO DESPRENDE POR SU CUENTA (y por eso ya no se le manda `pieza_suelta`).
    //
    // Antes no desprendia nada: esperaba a que el anfitrion le dijera celda a celda que se habia
    // soltado. Medido en el banco de dos instancias (`--estructuralan`, el invitado da los mazazos):
    //   mazo    -> el anfitrion mandaba 31 piezas y el invitado colocaba CERO (287 celdas "ya aire")
    //   derrumbe-> el anfitrion 7.099 voxels destruidos, el invitado 14.295, y ~4.000 voxels perdidos
    // El motivo es que el tallado YA viaja replicado (`_carve_beam` es `call_local`), asi que cuando
    // llegaba el aviso de la pieza esas celdas ya eran aire en el invitado y se descartaban enteras:
    // el canal no podia entregar NUNCA el escombro de un tallado. De ahi "golpeo con el mazo y mi
    // amigo no ve mis escombros" y "en LAN no se activan las fisicas de la estructura".
    //
    // Ahora cada maquina desprende lo suyo a partir del mismo daño (el nucleo es determinista) y lo
    // que viaja es solo el ASIENTO final del anfitrion (`place_settled`), que es quien tiene razon
    // sobre donde acaba cada trozo. Las piezas del invitado siguen sin escribir un solo voxel
    // (`settleAuthority_`): son la caida que se ve, no el mapa.
    if (engine_) engine_->setDesprender(true);
    // LOS DERRUMBES POR CARGA LOS DECIDE EL ANFITRION (ver Engine::setStructAuthority)
    if (engine_) engine_->setStructAuthority(!en_red || soy_host);
}

PackedInt32Array VoxelWorld::tomar_apoyos_rotos() {
    PackedInt32Array out;
    if (apoyosRotosPend_.empty()) return out;
    out.resize(static_cast<int64_t>(apoyosRotosPend_.size()) * 3);
    int64_t k = 0;
    for (const vx::IVec3& v : apoyosRotosPend_) { out.set(k++, v.x); out.set(k++, v.y); out.set(k++, v.z); }
    apoyosRotosPend_.clear();
    return out;
}

void VoxelWorld::romper_apoyos(const PackedInt32Array& voxels) {
    if (!engine_) return;
    for (int64_t i = 0; i + 2 < voxels.size(); i += 3) {
        const uint8_t m = engine_->world().getVoxel(voxels[i], voxels[i + 1], voxels[i + 2]);
        if (!m) continue;
        engine_->world().setVoxel(voxels[i], voxels[i + 1], voxels[i + 2], vx::MAT_AIR, true);
    }
    ++apoyosRotos_;
    // lo que estuviera dormido encima se entera de que le falta el suelo
    if (voxels.size() >= 3) {
        const float vs = engine_->world().voxelSize();
        despertarSobre(Vector3(voxels[0] + 0.5f, voxels[1] + 1.0f, voxels[2] + 0.5f) * vs, 2.0f);
    }
}

// ---------------------------------------------------------------------------------------------------
// RECONCILIACION DE BLOQUES EN RED
//
// Cada maquina desprende lo suyo a partir del mismo daño y los ids COINCIDEN... casi siempre. Medido en
// hangar con dos maquinas: un derrumbe grande quito los mismos voxels en las dos, pero el anfitrion lo
// partio en 82 bloques y el invitado en 79 (el orden entre las extracciones y la conectividad depende del
// ritmo de cada una), asi que 5 posturas no encontraron nunca su bloque. En vez de perseguir cada causa,
// el anfitrion publica su censo y el invitado corrige lo que no le cuadre: quita lo que sobra y pide la
// forma exacta de lo que falta (net.gd, "RECONCILIACION DE BLOQUES").
// ---------------------------------------------------------------------------------------------------
PackedInt64Array VoxelWorld::censo_bloques() const {
    PackedInt64Array out;
    out.resize(static_cast<int64_t>(bodies_.size()) * 2);
    int64_t k = 0;
    for (const Body& b : bodies_) {
        out.set(k++, static_cast<int64_t>(b.data.id));
        out.set(k++, static_cast<int64_t>(b.data.voxelCount) | (b.congelado ? (int64_t(1) << 40) : 0));
    }
    return out;
}

// Formato: 6 int32 (sx, sy, sz, origen de la rejilla en voxels) + 12 float32 (base por filas y origen de la
// postura) + sx*sy*sz bytes de material.
PackedByteArray VoxelWorld::datos_bloque(int64_t id) const {
    PackedByteArray out;
    if (!engine_) return out;
    const float vs = engine_->world().voxelSize();
    for (const Body& b : bodies_) {
        if (static_cast<int64_t>(b.data.id) != id) continue;
        if (!b.congelado) return out;          // lo que se mueve aun puede cambiar: ya se pedira quieto
        const vx::VoxelBody& d = b.data;
        out.resize(72 + static_cast<int64_t>(d.vox.size()));
        uint8_t* p = out.ptrw();
        const int32_t enteros[6] = {d.sx, d.sy, d.sz, static_cast<int32_t>(std::lround(d.worldOrigin.x / vs)),
            static_cast<int32_t>(std::lround(d.worldOrigin.y / vs)), static_cast<int32_t>(std::lround(d.worldOrigin.z / vs))};
        std::memcpy(p, enteros, 24);
        const Transform3D& t = b.xf;
        const float reales[12] = {t.basis[0][0], t.basis[0][1], t.basis[0][2], t.basis[1][0], t.basis[1][1], t.basis[1][2],
            t.basis[2][0], t.basis[2][1], t.basis[2][2], t.origin.x, t.origin.y, t.origin.z};
        std::memcpy(p + 24, reales, 48);
        if (!d.vox.empty()) std::memcpy(p + 72, d.vox.data(), d.vox.size());
        return out;
    }
    return out;
}

bool VoxelWorld::crear_bloque(int64_t id, const PackedByteArray& datos) {
    if (!engine_ || datos.size() < 72) return false;
    const uint8_t* p = datos.ptr();
    int32_t e[6];
    std::memcpy(e, p, 24);
    if (e[0] <= 0 || e[1] <= 0 || e[2] <= 0) return false;
    if (static_cast<int64_t>(e[0]) * e[1] * e[2] != datos.size() - 72) return false;
    float f[12];
    std::memcpy(f, p + 24, 48);
    const Transform3D xf(Basis(f[0], f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8]), Vector3(f[9], f[10], f[11]));
    if (!xf.origin.is_finite()) return false;
    static thread_local std::vector<vx::BodyVoxel> v;
    v.clear();
    const uint8_t* vox = p + 72;
    for (int z = 0; z < e[2]; ++z) for (int y = 0; y < e[1]; ++y) for (int x = 0; x < e[0]; ++x) {
        const uint8_t m = vox[x + y * e[0] + z * e[0] * e[1]];
        if (m) v.push_back(vx::BodyVoxel{e[3] + x, e[4] + y, e[5] + z, m});
    }
    if (v.empty()) return false;
    quitar_bloque(id);
    static thread_local vx::BodyBuilder constructor;
    vx::VoxelBody nb;
    constructor.build(v, engine_->world().voxelSize(), cajasMoviendose(static_cast<int>(v.size()), engine_->preset().maxBoxesPerBody), static_cast<uint32_t>(id), nb);
    congelPendientes_[id] = xf;                // spawnPiece lo congela en el acto en esta postura
    creandoDeRed_ = true;
    spawnPiece(std::move(nb));
    creandoDeRed_ = false;
    congelPendientes_.erase(id);
    return true;
}

int VoxelWorld::quitar_bloque(int64_t id) {
    int n = 0;
    for (size_t i = 0; i < bodies_.size();) {
        Body& b = bodies_[i];
        if (static_cast<int64_t>(b.data.id) != id) { ++i; continue; }
        sacarDelGrupo(b);
        freeBody(b);
        bodies_[i] = std::move(bodies_.back());
        bodies_.pop_back();
        ++n;
    }
    return n;
}

// ---------------------------------------------------------------------------------------------------
// EL TOPE DE ESCOMBROS (2026-10-05, pedido con captura del movil a 30 fps: "si hay muchisimos escombros, que se
// eliminen solos y gasten menos"). Medido en la cafeteria destrozada (40 explosiones, camino del movil, GPU en pausa):
// 10,2 -> 22,5 ms, casi todo la capa del mundo con los bloques y sus sombras. Si hay mas de `tope` escombros chicos
// (<= ESCOMBRO_CHICO voxels; las losas y los muros caidos no se tocan: son parte del juego), se quitan los que sobran
// empezando por los que NO se ven (detras o a mas de 60 m) y los mas lejanos; como mucho `max_quitar` por llamada.
// Solo lo llama quien manda (main.gd: solo o anfitrion); el invitado los quita por la reconciliacion de bloques.
// Devuelve los ids quitados.
// ---------------------------------------------------------------------------------------------------
static int64_t g_escombrosQuitados = 0;
// CUANDO SE CONGELO CADA BLOQUE (id -> ms), para la limpieza con el tiempo (limpiar_escombros)
static int64_t g_escombrosLimpiados = 0;

PackedInt64Array VoxelWorld::recortar_escombros(int tope, const Vector3& pos, const Vector3& dir, int max_quitar) {
    PackedInt64Array out;
    if (tope < 0 || max_quitar <= 0) return out;
    struct Cand { float prio; uint64_t id; size_t idx; };
    std::vector<Cand> cands;
    const Vector3 d = dir.length() > 0.001f ? dir.normalized() : Vector3(0, 0, -1);
    for (size_t i = 0; i < bodies_.size(); ++i) {
        const Body& b = bodies_[i];
        if (static_cast<int>(b.data.voxelCount) > ESCOMBRO_CHICO) continue;
        const Vector3 p = b.rigid ? b.xf.origin : b.pos;
        const Vector3 to = p - pos;
        const float dist = to.length();
        // "se ve": cerca, o delante (dentro de un cono de ~63 grados a cada lado) y a menos de 60 m
        const bool visto = dist < 8.f || (dist < 60.f && to.dot(d) > dist * 0.45f);
        // primero lo que no se ve, luego lo lejano; a igual distancia, el mas chico
        const float prio = (visto ? 0.f : 100000.f) + dist + (ESCOMBRO_CHICO - static_cast<float>(b.data.voxelCount)) * 0.0005f;
        cands.push_back({prio, b.data.id, i});
    }
    if (static_cast<int>(cands.size()) <= tope) return out;
    const int sobran = std::min(static_cast<int>(cands.size()) - tope, max_quitar);
    std::partial_sort(cands.begin(), cands.begin() + sobran, cands.end(), [](const Cand& a, const Cand& b) {
        if (a.prio != b.prio) return a.prio > b.prio;
        return a.id < b.id;
    });
    std::vector<size_t> idxs;
    idxs.reserve(static_cast<size_t>(sobran));
    for (int k = 0; k < sobran; ++k) { idxs.push_back(cands[static_cast<size_t>(k)].idx); out.push_back(static_cast<int64_t>(cands[static_cast<size_t>(k)].id)); }
    // de atras adelante: al sacar uno, el que ocupa su sitio viene del final y ya no esta en la lista
    std::sort(idxs.begin(), idxs.end(), std::greater<size_t>());
    for (size_t i : idxs) {
        Body& b = bodies_[i];
        sacarDelGrupo(b);
        freeBody(b);
        bodies_[i] = std::move(bodies_.back());
        bodies_.pop_back();
    }
    g_escombrosQuitados += sobran;
    return out;
}

// ---------------------------------------------------------------------------------------------------
// LA LIMPIEZA DE ESCOMBROS CON EL TIEMPO (2026-10-05, pedido: "que los escombros se queden dormidos y al rato se limpien;
// los chicos pronto, los medianos a los 90 s y los grandes a los 120; un trozo de casa no"). Un bloque CONGELADO de mas
// de `min_m3` y como mucho `max_m3` m3 (de cualquier origen: explosion, desgaste, derrumbe, balazos) se quita cuando lleva
// `s_fuera` s congelado y no se ve (detras o a mas de 60 m), o `s_vista` s aunque se vea. Con `despertar`, lo que estaba
// apoyado encima se despierta para que caiga (si no, se quedaria congelado en el aire). Como mucho `max_quitar` por
// llamada. Lo llama solo quien manda (main.gd); el invitado los pierde por la reconciliacion de bloques.
// ---------------------------------------------------------------------------------------------------
PackedInt64Array VoxelWorld::limpiar_escombros(float min_m3, float max_m3, float s_fuera, float s_vista, const Vector3& pos, const Vector3& dir, int max_quitar, bool despertar) {
    PackedInt64Array out;
    if (!engine_ || max_m3 <= 0.f || max_quitar <= 0) return out;
    const float vs = engine_->world().voxelSize();
    const float maxVox = max_m3 / (vs * vs * vs);
    const float minVox = min_m3 / (vs * vs * vs);
    const uint64_t ahora = Time::get_singleton()->get_ticks_msec();
    const Vector3 d = dir.length() > 0.001f ? dir.normalized() : Vector3(0, 0, -1);
    std::vector<size_t> idxs;
    for (size_t i = 0; i < bodies_.size() && static_cast<int>(idxs.size()) < max_quitar; ++i) {
        const Body& b = bodies_[i];
        if (!b.congelado || static_cast<float>(b.data.voxelCount) > maxVox || static_cast<float>(b.data.voxelCount) <= minVox) continue;
        auto it = g_congeladoEn.find(b.data.id);
        if (it == g_congeladoEn.end()) { g_congeladoEn[b.data.id] = ahora; continue; }
        const float s = static_cast<float>(ahora - it->second) * 0.001f;
        if (s < s_fuera) continue;
        const Vector3 to = b.pos - pos;
        const float dist = to.length();
        const bool visto = dist < 8.f || (dist < 60.f && to.dot(d) > dist * 0.45f);
        if (visto && s < s_vista) continue;
        idxs.push_back(i);
    }
    std::sort(idxs.begin(), idxs.end(), std::greater<size_t>());
    std::vector<std::pair<Vector3, float>> apoyos;
    for (size_t i : idxs) {
        Body& b = bodies_[i];
        out.push_back(static_cast<int64_t>(b.data.id));
        if (despertar)
            apoyos.emplace_back(b.pos, 0.5f * vs * Vector3(static_cast<float>(b.data.sx), static_cast<float>(b.data.sy), static_cast<float>(b.data.sz)).length());
        g_congeladoEn.erase(b.data.id);
        sacarDelGrupo(b);
        freeBody(b);
        bodies_[i] = std::move(bodies_.back());
        bodies_.pop_back();
    }
    for (const auto& a : apoyos) despertarSobre(a.first, a.second);
    g_escombrosLimpiados += static_cast<int64_t>(idxs.size());
    return out;
}

// ---------------------------------------------------------------------------------------------------
// RECONCILIACION DEL MAPA
//
// El daño llega a cada maquina en su orden: un disparo propio se aplica en el acto y el derrumbe que decide
// el anfitrion llega despues, y una bala que pasa por un hueco que en la otra maquina aun no existe muerde
// otros voxels. Medido en hangar: 1-2 voxels distintos por chunk que se quedan para siempre, y el que entra
// tarde (reproduciendo el historial, donde las extracciones van en hilos) con 353 voxels de diferencia.
// Como con los bloques, en vez de perseguir cada orden se compara el resultado: el anfitrion publica la
// huella de cada chunk tocado y el invitado pide los que no le cuadren (net.gd, "RECONCILIACION DEL MAPA").
// ---------------------------------------------------------------------------------------------------
static uint64_t fnvChunk(const uint8_t* vox) {
    uint64_t h = 1469598103934665603ull;
    for (int i = 0; i < vx::CHUNK_VOLUME; ++i) { h ^= vox[i]; h *= 1099511628211ull; }
    return h | 1ull;   // nunca 0: 0 es "cambiando"
}

uint64_t VoxelWorld::huellaDe(int indice, bool& cambiado) {
    cambiado = false;
    if (!engine_) return 0;
    const vx::World& w = engine_->world();
    if (indice < 0 || indice >= w.numChunkSlots()) return 0;
    if (static_cast<int>(huellasChunk_.size()) < w.numChunkSlots()) huellasChunk_.resize(static_cast<size_t>(w.numChunkSlots()));
    const vx::Chunk* c = w.chunkAt(indice);
    if (c == nullptr) {
        static const uint64_t vacio = [] { static const uint8_t ceros[vx::CHUNK_VOLUME] = {}; return fnvChunk(ceros); }();
        return vacio;
    }
    const uint32_t v = c->versionAtomic.load(std::memory_order_acquire);
    HuellaChunk& h = huellasChunk_[static_cast<size_t>(indice)];
    if (h.version != v || h.hash == 0) {
        const uint64_t hash = fnvChunk(c->vox);
        // editado mientras se leia (sin lock, a proposito): se mira en la ronda siguiente
        if (c->versionAtomic.load(std::memory_order_acquire) != v) { h.version = 0; h.hash = 0; cambiado = true; return 0; }
        h.version = v; h.hash = hash; h.ronda = rondaHuellas_;
    }
    // cambiado en esta ronda (o visto por primera vez): lo que va por el aire puede explicar la diferencia
    cambiado = h.ronda >= rondaHuellas_;
    return h.hash;
}

PackedInt64Array VoxelWorld::huellas_chunks() {
    PackedInt64Array out;
    if (!engine_) return out;
    ++rondaHuellas_;
    const vx::World& w = engine_->world();
    const int n = w.numChunkSlots();
    for (int i = 0; i < n; ++i) {
        const vx::Chunk* c = w.chunkAt(i);
        if (c == nullptr || c->pristine.load(std::memory_order_relaxed)) continue;
        bool cambiado = false;
        const uint64_t hash = huellaDe(i, cambiado);
        out.push_back(i);
        out.push_back(static_cast<int64_t>(hash));
        out.push_back(cambiado ? 1 : 0);
    }
    return out;
}

PackedInt64Array VoxelWorld::huella_chunk(int indice) {
    bool cambiado = false;
    const uint64_t hash = huellaDe(indice, cambiado);
    PackedInt64Array out;
    out.push_back(static_cast<int64_t>(hash));
    out.push_back(cambiado ? 1 : 0);
    return out;
}

PackedByteArray VoxelWorld::datos_chunk(int indice) const {
    PackedByteArray out;
    if (!engine_) return out;
    const vx::World& w = engine_->world();
    if (indice < 0 || indice >= w.numChunkSlots()) return out;
    out.resize(vx::CHUNK_VOLUME + 1);
    uint8_t* p = out.ptrw();
    const vx::Chunk* c = w.chunkAt(indice);
    if (c == nullptr) { std::memset(p, 0, static_cast<size_t>(vx::CHUNK_VOLUME) + 1); p[vx::CHUNK_VOLUME] = 1; return out; }
    std::memcpy(p, c->vox, vx::CHUNK_VOLUME);
    p[vx::CHUNK_VOLUME] = c->pristine.load(std::memory_order_relaxed) ? 1 : 0;
    return out;
}

int VoxelWorld::aplicar_chunk(int indice, const PackedByteArray& datos) {
    if (!engine_ || datos.size() != vx::CHUNK_VOLUME + 1) return 0;
    vx::World& w = engine_->world();
    if (indice < 0 || indice >= w.numChunkSlots()) return 0;
    const int ncx = w.chunksX(), ncy = w.chunksY();
    const int cx = indice % ncx, cy = (indice / ncx) % ncy, cz = indice / (ncx * ncy);
    const uint8_t* p = datos.ptr();
    int cambiados = 0;
    for (int z = 0; z < vx::CHUNK_SIZE; ++z) for (int y = 0; y < vx::CHUNK_SIZE; ++y) for (int x = 0; x < vx::CHUNK_SIZE; ++x) {
        const int k = vx::Chunk::index(x, y, z);
        const vx::Chunk* c = w.chunkAt(indice);
        const uint8_t local = c ? c->vox[k] : 0;
        if (local == p[k]) continue;
        w.setVoxel(cx * vx::CHUNK_SIZE + x, cy * vx::CHUNK_SIZE + y, cz * vx::CHUNK_SIZE + z, p[k], true);
        ++cambiados;
    }
    // intacto en el anfitrion: aqui tambien (el solver ancla distinto un chunk intacto y uno tocado)
    vx::Chunk* c = w.chunkAt(indice);
    if (c && p[vx::CHUNK_VOLUME]) c->pristine.store(true, std::memory_order_relaxed);
    if (cambiados > 0) {
        // lo que estuviera dormido encima o al lado se entera
        const float vs = w.voxelSize();
        const Vector3 centro = Vector3(cx + 0.5f, cy + 0.5f, cz + 0.5f) * (vx::CHUNK_SIZE * vs);
        despertarSobre(centro, vx::CHUNK_SIZE * vs);
    }
    return cambiados;
}

Array VoxelWorld::tomar_fallos_estructurales() {
    Array out;
    if (!engine_) return out;
    for (const vx::Engine::StructFailureOut& f : engine_->drainStructFailures()) {
        PackedInt32Array celdas;
        celdas.resize(static_cast<int64_t>(f.cells.size()) * 6);
        int64_t k = 0;
        for (const vx::FailCell& c : f.cells) {
            celdas.set(k++, c.min.x); celdas.set(k++, c.min.y); celdas.set(k++, c.min.z);
            celdas.set(k++, c.max.x); celdas.set(k++, c.max.y); celdas.set(k++, c.max.z);
        }
        Dictionary d;
        d["celdas"] = celdas;
        d["tilt"] = toGd(f.group.tiltDir);
        d["com"] = toGd(f.group.com);
        d["masa"] = f.group.mass;
        d["isla"] = f.group.island;
        out.push_back(d);
    }
    return out;
}

void VoxelWorld::aplicar_fallo_estructural(const PackedInt32Array& celdas, const Vector3& tilt, const Vector3& com, float masa, int isla) {
    if (!engine_ || celdas.size() < 6) return;
    std::vector<vx::FailCell> cells;
    cells.reserve(static_cast<size_t>(celdas.size() / 6));
    for (int64_t i = 0; i + 5 < celdas.size(); i += 6) {
        vx::FailCell c{};
        c.min = vx::IVec3(celdas[i], celdas[i + 1], celdas[i + 2]);
        c.max = vx::IVec3(celdas[i + 3], celdas[i + 4], celdas[i + 5]);
        c.island = isla;
        cells.push_back(c);
    }
    vx::FailGroup g{};
    g.island = isla;
    g.tiltDir = toVxV(tilt);
    g.com = toVxV(com);
    g.mass = masa;
    engine_->applyStructFailure(std::move(cells), g);
}


/// Avisa a los demas de que este trozo se ha soltado: su caja de celdas, que celdas son (un bit cada
/// una) y con que velocidad sale. El material no viaja: el que recibe lo tiene ya en su mundo, que es
/// identico hasta este momento.
void VoxelWorld::avisarSuelta(const vx::VoxelBody& pieza) {
    const float vs = engine_->world().voxelSize();
    const Vector3i origen(static_cast<int>(std::lround(pieza.worldOrigin.x / vs)),
                          static_cast<int>(std::lround(pieza.worldOrigin.y / vs)),
                          static_cast<int>(std::lround(pieza.worldOrigin.z / vs)));
    const Vector3i tam(pieza.sx, pieza.sy, pieza.sz);
    const int64_t n = static_cast<int64_t>(pieza.sx) * pieza.sy * pieza.sz;
    if (n <= 0) return;
    PackedByteArray mascara;
    mascara.resize((n + 7) / 8);
    std::memset(mascara.ptrw(), 0, static_cast<size_t>(mascara.size()));
    uint8_t* bits = mascara.ptrw();
    // SOLO VIAJA LO QUE DE VERDAD HE QUITADO DE MI MUNDO. Un trozo de explosion se hace creciendo
    // desde un voxel reventado, y al crecer se come tambien celdas que siguen EN PIE (el motor las
    // duplica: la pared sigue ahi y ademas salen volando). Mandandolas, el invitado las quitaba de
    // su mapa y el anfitrion no: medido, 548 celdas de 2678 en un derribo, y esa era justo la
    // diferencia que quedaba entre las dos maquinas.
    int64_t marcadas = 0;
    for (int64_t k = 0; k < n; ++k) {
        if (!pieza.vox[static_cast<size_t>(k)]) continue;
        const int x = static_cast<int>(k % pieza.sx);
        const int y = static_cast<int>((k / pieza.sx) % pieza.sy);
        const int z = static_cast<int>(k / (static_cast<int64_t>(pieza.sx) * pieza.sy));
        if (engine_->world().getVoxel(origen.x + x, origen.y + y, origen.z + z) != vx::MAT_AIR) {
            ++celdasSueltasSolidas_;
            continue;
        }
        bits[k >> 3] |= static_cast<uint8_t>(1u << (k & 7));
        ++marcadas;
    }
    if (marcadas == 0) return;
    ++sueltasOut_; celdasSueltasOut_ += marcadas;
    emit_signal("pieza_suelta", origen, tam, mascara, toGd(pieza.initialVel), toGd(pieza.initialAngVel));
}


/// EL INVITADO PONE EL TROZO DONDE LO DEJO EL ANFITRION. Llega por id (hash del primer voxel, igual
/// en las dos maquinas) con la postura entera. Antes esto no se podia hacer -"no hay id de trozo
/// comun entre maquinas"- porque el reparto en trozos dependia del rendimiento; desde que es
/// determinista, medido en el banco, las dos listas de trozos salen con los MISMOS ids y los mismos
/// voxels, asi que se puede hablar de "el trozo tal" y las dos pantallas lo dejan igual puesto.
void VoxelWorld::place_frozen(int64_t id, const Transform3D& xf) {
    for (Body& b : bodies_) {
        if (static_cast<int64_t>(b.data.id) != id) continue;
        if (!b.congelado) congelarPieza(b, xf);
        else {
            b.xf = xf; b.pos = xf.origin;
            RenderingServer* rs = RenderingServer::get_singleton();
            PhysicsServer3D* ps = PhysicsServer3D::get_singleton();
            if (rs && b.inst.is_valid()) rs->instance_set_transform(b.inst, xf);
            if (ps && b.body.is_valid()) ps->body_set_state(b.body, PhysicsServer3D::BODY_STATE_TRANSFORM, xf);
        }
        return;
    }
    // Todavia no ha nacido (sigue en la cola de piezas): se guarda y se le aplica al nacer.
    congelPendientes_[id] = xf;
}

Array VoxelWorld::posturas_en_vuelo(int min_voxels, bool quietos) const {
    PackedInt64Array ids;
    PackedFloat32Array poses;
    for (const Body& b : bodies_) {
        // LOS PARADOS TAMBIEN, hasta que se congelan (`quietos`, que el anfitrion pide una vez por segundo): si
        // dejaba de llegar su postura al pararse, el invitado lo soltaba y, medio metido en el suelo como iba
        // de cinematico, la fisica lo escupia 19 cm hacia arriba (medido con --lanmesa --diagposturas).
        if (!b.rigid || !b.body.is_valid() || b.congelado) continue;
        if ((b.sleeping || b.anclado) && !quietos) continue;
        if (static_cast<int>(b.data.voxelCount) < min_voxels) continue;
        ids.push_back(static_cast<int64_t>(b.data.id));
        const Quaternion q = b.xf.basis.get_rotation_quaternion();
        const Vector3 lv = (b.sleeping || b.anclado) ? Vector3() : b.linVel;
        const float v[10] = {b.xf.origin.x, b.xf.origin.y, b.xf.origin.z, q.x, q.y, q.z, q.w, lv.x, lv.y, lv.z};
        for (float f : v) poses.push_back(f);
    }
    Array out;
    out.push_back(ids);
    out.push_back(poses);
    return out;
}

void VoxelWorld::seguir_posturas(const PackedInt64Array& ids, const PackedFloat32Array& poses) {
    if (poses.size() < ids.size() * 10) return;
    PhysicsServer3D* ps = PhysicsServer3D::get_singleton();
    for (int64_t k = 0; k < ids.size(); ++k) {
        const int64_t id = ids[k];
        const float* v = poses.ptr() + k * 10;
        const Transform3D xf(Basis(Quaternion(v[3], v[4], v[5], v[6]).normalized()), Vector3(v[0], v[1], v[2]));
        for (Body& b : bodies_) {
            if (static_cast<int64_t>(b.data.id) != id) continue;
            // aqui ya se habia parado o dormido y alli sigue cayendo: manda el anfitrion
            if (b.congelado || b.anclado) despertarBloque(b);
            if (!b.siguiendo) {
                b.siguiendo = true;
                if (ps && b.rigid && b.body.is_valid()) ps->body_set_mode(b.body, PhysicsServer3D::BODY_MODE_KINEMATIC);
            }
            b.objetivo = xf;
            b.objetivoVel = Vector3(v[7], v[8], v[9]);
            b.sinPostura = 0.f;
            break;
        }
    }
}

void VoxelWorld::place_detached(const Vector3i& origen, const Vector3i& tam, const PackedByteArray& mascara,
                                const Vector3& vel, const Vector3& ang_vel) {
    if (engine_ == nullptr || tam.x <= 0 || tam.y <= 0 || tam.z <= 0) return;
    const int64_t n = static_cast<int64_t>(tam.x) * tam.y * tam.z;
    if (mascara.size() < (n + 7) / 8) return;
    const uint8_t* bits = mascara.ptr();
    static thread_local std::vector<vx::BodyVoxel> celdas;
    celdas.clear();
    int64_t k = 0;
    for (int z = 0; z < tam.z; ++z)
    for (int y = 0; y < tam.y; ++y)
    for (int x = 0; x < tam.x; ++x, ++k) {
        if (!((bits[k >> 3] >> (k & 7)) & 1u)) continue;
        const int wx = origen.x + x, wy = origen.y + y, wz = origen.z + z;
        if (!engine_->world().inBounds(wx, wy, wz)) continue;
        const uint8_t m = engine_->world().getVoxel(wx, wy, wz);
        if (!m) { ++celdasSueltasYaAire_; continue; }   // ya estaba tallado aqui: nada que soltar
        celdas.push_back(vx::BodyVoxel{wx, wy, wz, m});
        engine_->world().setVoxel(wx, wy, wz, vx::MAT_AIR, false);
    }
    ++sueltasIn_;
    celdasSueltasIn_ += static_cast<int64_t>(celdas.size());
    if (celdas.empty()) return;
    static thread_local vx::BodyBuilder constructor;
    vx::VoxelBody cuerpo;
    constructor.build(celdas, engine_->world().voxelSize(), cajasMoviendose(static_cast<int>(celdas.size()), engine_->preset().maxBoxesPerBody), ++redPieceId_, cuerpo);
    cuerpo.initialVel = toVxV(vel);
    cuerpo.initialAngVel = toVxV(ang_vel);
    spawnPiece(std::move(cuerpo));
}


/// Los escombros que manda el anfitrion, tal cual: celda a celda.
///
/// NO SE PUEDE IR POR EL IDENTIFICADOR DEL TROZO. Se probo: el id es un hash de donde estaba el
/// trozo, pero el reparto en trozos NO es igual en dos maquinas (el solver de estructura va por
/// tiempo, y dos partidas identicas parten el mismo muro en cuatro pedazos o en siete). Midiendolo
/// no coincidia ni un id. Asi que va el resultado en crudo, que es lo unico que de verdad importa:
/// donde quedan los voxels.
void VoxelWorld::place_settled(const Vector3i& origen, const Vector3i& tam, const PackedByteArray& mats) {
    if (engine_ == nullptr || tam.x <= 0 || tam.y <= 0 || tam.z <= 0) return;
    const int64_t n = static_cast<int64_t>(tam.x) * tam.y * tam.z;
    if (mats.size() < n) return;
    int k = 0;
    for (int z = 0; z < tam.z; ++z)
    for (int y = 0; y < tam.y; ++y)
    for (int x = 0; x < tam.x; ++x) {
        const uint8_t m = mats[k++];
        if (!m) continue;
        const int wx = origen.x + x, wy = origen.y + y, wz = origen.z + z;
        if (!engine_->world().inBounds(wx, wy, wz)) { ++celdasAsientoSalt_; continue; }
        if (engine_->world().getVoxel(wx, wy, wz) != vx::MAT_AIR) { ++celdasAsientoSalt_; continue; }
        engine_->world().setVoxel(wx, wy, wz, m, false);
        ++celdasAsientoIn_;
    }
}


/// Revoxeliza avisando: coloca las celdas y, si mando yo, manda a los demas EXACTAMENTE las que han
/// quedado. Todo lo que escriba voxels en el mundo tiene que pasar por aqui.
void VoxelWorld::emitirAsiento(const vx::VoxelBody& datos, const vx::Transform& tr) {
    if (!settleAuthority_) return;
    static thread_local std::vector<vx::Engine::CeldaPuesta> puestas;
    puestas.clear();
    engine_->revoxelize(datos, tr, &puestas);
    if (puestas.empty()) return;
    int mnx = puestas[0].v.x, mny = puestas[0].v.y, mnz = puestas[0].v.z;
    int mxx = mnx, mxy = mny, mxz = mnz;
    for (const vx::Engine::CeldaPuesta& c : puestas) {
        mnx = std::min(mnx, c.v.x); mny = std::min(mny, c.v.y); mnz = std::min(mnz, c.v.z);
        mxx = std::max(mxx, c.v.x); mxy = std::max(mxy, c.v.y); mxz = std::max(mxz, c.v.z);
    }
    const Vector3i origen(mnx, mny, mnz);
    const Vector3i tam(mxx - mnx + 1, mxy - mny + 1, mxz - mnz + 1);
    PackedByteArray mats;
    mats.resize(static_cast<int64_t>(tam.x) * tam.y * tam.z);
    std::memset(mats.ptrw(), 0, static_cast<size_t>(mats.size()));
    for (const vx::Engine::CeldaPuesta& c : puestas) {
        const int64_t k = (c.v.x - mnx) + static_cast<int64_t>(c.v.y - mny) * tam.x
            + static_cast<int64_t>(c.v.z - mnz) * tam.x * tam.y;
        mats.set(k, c.m);
    }
    ++asientosOut_;
    celdasAsientoOut_ += static_cast<int64_t>(puestas.size());
    emit_signal("piece_settled", origen, tam, mats);
}



/// Cuantos bloques han salido con muchisimas cajas, y si se avisa por consola. Van aqui y no en la
/// clase: tocar la cabecera obliga a recompilar en limpio (ver CLAUDE.md).
static int64_t recortados_ = 0;
static bool avisarRecorte_ = true;

/// CAJAS DE UN TROZO QUIETO QUE SE RECONSTRUYE AL ROMPERSE (ver el uso mas abajo). Aqui SI hay un
/// reparto, porque esto corre en mitad de un tallado y con la pieza aun viva; la colision definitiva
/// -la que decide si te lo atraviesas- la pone `crearColisionFina`, y esa no tiene tope.
static int cajasFinas(int voxels) {
    return std::clamp(128 + voxels / 25, 128, 4000);
}

/// (El reparto de cajas del trozo PARADO se quito: ver `crearColisionFina`. Un trozo parado lleva TODAS
/// las cajas que necesita su forma, porque las que faltan son agujeros por los que se cuela el
/// jugador.)

/// Segundos que un bloque recien golpeado NO puede volver a dormirse.
///
/// Al despertarlo por daño, si tiene algo debajo se queda quieto en el mismo frame, su reloj de sueño
/// empieza a correr y se vuelve a dormir antes de que la fisica haya resuelto nada: en pantalla se ve
/// como que le das y no se cae, y solo cae al segundo o tercer golpe. Con este margen se le deja
/// suelto el tiempo suficiente para que Jolt decida de verdad si se sostiene.
static constexpr float GRACIA_TRAS_GOLPE = 2.5f;
static constexpr float SEGUIR_SUELTA_S = 2.5f;   // sin postura del anfitrion en este tiempo, el bloque vuelve a ser suyo

/// ¿AGUANTA LO QUE HAY DEBAJO EL PESO DE ESTE BLOQUE? "Un palo no soporta una casa".
///
/// EL AGUJERO QUE TAPA ESTO. El analizador estructural trabaja sobre la REJILLA de voxels y su unidad
/// de carga son "voxels de hormigon". Mientras el escombro volvia a la rejilla, su peso entraba solo
/// en la cuenta. Desde que un bloque que cae se queda siendo bloque, su masa NO ESTA EN NINGUN SITIO
/// que el analizador mire: el tocon sobre el que se ha quedado no recibe carga, no se evalua y no
/// falla nunca. De ahi que un voxel suelto sostuviera toneladas.
///
/// Se resuelve con las MISMAS constantes que el analizador (capacidad por voxel de seccion =
/// STRESS_CAPACITY) para que el criterio sea uno solo en todo el juego, no dos que se contradicen.
/// Devuelve false y deja en `flojos` los voxels de apoyo que hay que reventar.
/// DESPIERTA A LOS BLOQUES QUE SE APOYABAN AHI.
///
/// Un bloque parado DUERME: es estatico y no se le vuelve a mirar. Eso es lo que hace que no cueste
/// nada y que no vibre. Pero si el daño no le toca a EL sino a lo que lo sostiene -le vuelas la
/// columna de debajo, le picas el muro en el que se apoyaba- nadie se lo cuenta, y se queda colgado
/// en el aire sobre nada. Es la otra cara de "duerme hasta recibir daño": el daño a su APOYO tambien
/// cuenta como daño para el.
///
/// Se llama desde los tres caminos que quitan voxels del mundo (explosion, laser/mazo y bala) con la
/// zona tocada. Despertar es barato: vuelve a ser dinamico, Jolt comprueba si tiene suelo y, si lo
/// tiene, se vuelve a dormir en cuanto se pare.
/// SUELO BAJO UN PUNTO, mirando el mundo Y los bloques ya parados.
///
/// Los bloques pequeños no los simula Jolt: caen con una cuenta a mano, y su sonda de aterrizaje
/// usaba `world().raycast`, que recorre SOLO LA REJILLA DE VOXELS. Mientras el escombro volvia a la
/// rejilla eso bastaba, porque el monton ERA mundo. Desde que un bloque que cae se queda siendo
/// bloque, un monton de escombro es invisible para esa sonda y los pequeños lo ATRAVIESAN: es el
/// "traspasa algunos bloques" de un derrumbe.
///
/// Solo cuentan como suelo los bloques PARADOS: apoyarse en uno que todavia esta cayendo daria un
/// suelo que desaparece al frame siguiente, y eso es peor que atravesarlo.
///
/// Devuelve la Y del impacto mas alto, o -1e9 si no hay nada.
float VoxelWorld::sueloBajo(const Vector3& p, float alcance, const Body* excluir) const {
    float mejor = -1e9f;
    vx::RayHit hp;
    if (engine_->world().raycast(toVxV(p), vx::Vec3(0, -1, 0), alcance, hp)) mejor = hp.pos.y;
    const float vs = engine_->world().voxelSize();
    for (const Body& o : bodies_) {
        if (&o == excluir) continue;
        if (!o.congelado && !o.anclado && !o.resting) continue;
        const Vector3 c = o.rigid ? o.xf.origin : o.pos;
        // descarte barato: si su envolvente no cruza esta columna, ni se prueba (esto corre por cada
        // punto de sonda de cada bloque pequeño y cada paso: sin el descarte seria O(N^2) por frame)
        const float radio = 0.5f * vs * std::sqrt(static_cast<float>(o.data.sx * o.data.sx + o.data.sy * o.data.sy + o.data.sz * o.data.sz));
        const float dx = c.x - p.x, dz = c.z - p.z;
        if (dx * dx + dz * dz > radio * radio) continue;
        if (c.y - radio > p.y || c.y + radio < p.y - alcance) continue;
        Vector3 q;
        const float t = rayCuerpo(o, p, Vector3(0, -1, 0), alcance, q);
        if (t >= 0.f && q.y > mejor) mejor = q.y;
    }
    return mejor;
}

void VoxelWorld::despertarSobre(const Vector3& centro, float radio) {
    if (bodies_.empty()) return;
    // SOLO LO QUE ALCANZA DE VERDAD (2026-10-10, pedido: "que no se despierten las fisicas de los bloques caidos si no
    // les disparan o golpean ese mismo bloque"). Era un cilindro de radio + 2 m y hasta 12 m de alto: una granada al pie
    // de un monton despertaba el monton entero, y demoliendo habia ~200 bloques despiertos a la vez (10-15 ms de fisica,
    // 30 fps). Ahora se despierta el bloque cuya esfera toca la zona (radio + 0,4 m): lo que estaba apoyado justo en lo
    // que se quito. VX_DESPERTAR_ANCHO=1 = como antes.
    static const bool ancho = std::getenv("VX_DESPERTAR_ANCHO") != nullptr;
    const float vs = engine_ ? engine_->world().voxelSize() : 0.2f;
    for (Body& b : bodies_) {
        if (!b.congelado && !b.anclado) continue;
        const Vector3 pz = b.rigid ? b.xf.origin : b.pos;
        if (ancho) {
            const float r2 = (radio + 2.0f) * (radio + 2.0f);
            if (pz.y < centro.y - radio) continue;
            const float dx = pz.x - centro.x, dz = pz.z - centro.z;
            if (dx * dx + dz * dz > r2) continue;
            if (pz.y - centro.y > radio + 12.0f) continue;
        } else {
            const float rb = 0.5f * vs * Vector3(static_cast<float>(b.data.sx), static_cast<float>(b.data.sy), static_cast<float>(b.data.sz)).length();
            if (pz.distance_to(centro) > radio + rb + 0.4f) continue;
        }
        despertarBloque(b);
    }
}

void VoxelWorld::set_tope_despiertos(int n) { g_topeDespiertos = n < 0 ? 0 : n; }

bool VoxelWorld::apoyoSuficiente(const Body& b, const Transform3D& t, std::vector<vx::IVec3>& flojos, float impacto, Vector3* outMn, Vector3* outMx) const {
    flojos.clear();
    const vx::World& w = engine_->world();
    const float vs = w.voxelSize();
    const vx::VoxelBody& d = b.data;
    // SECCION DE APOYO: lo que hay en el mundo justo debajo de la CARA INFERIOR REAL del bloque, voxel a
    // voxel y en su postura real. Antes se miraba bajo la caja envolvente: con el bloque inclinado la
    // esquina baja de la caja queda muy por debajo del bloque, alli solo hay aire, y se concluia "no se
    // apoya en el mundo" sin juzgarlo (el tablero de la mesa a mazo, torcido 9 grados sobre los tocones).
    if (static_cast<int64_t>(d.sx) * d.sy * d.sz > 4000000) return true;   // enorme: no se evalua
    std::unordered_set<uint64_t> vistos;
    float seccion = 0.f;
    const Vector3 com = toGd(d.com);
    if (outMn) { *outMn = Vector3(1e9f, 1e9f, 1e9f); *outMx = Vector3(-1e9f, -1e9f, -1e9f); }
    for (int lz = 0; lz < d.sz; ++lz) for (int ly = 0; ly < d.sy; ++ly) for (int lx = 0; lx < d.sx; ++lx) {
        const size_t idxv = static_cast<size_t>(lx) + static_cast<size_t>(ly) * d.sx + static_cast<size_t>(lz) * d.sx * d.sy;
        if (!d.vox[idxv]) continue;
        if (ly > 0 && d.vox[idxv - static_cast<size_t>(d.sx)]) continue;   // no es cara inferior
        const Vector3 p = t.xform(Vector3((lx + 0.5f) * vs, (ly + 0.5f) * vs, (lz + 0.5f) * vs) - com);
        const int x = static_cast<int>(std::floor(p.x / vs)), z = static_cast<int>(std::floor(p.z / vs));
        const int yb = static_cast<int>(std::floor(p.y / vs));
        // sonda de 0,35 m: las cajas de colision son mas gruesas que el voxel (con 0,8 m algo a 0,7 m del tocon contaba como apoyado)
        const int sonda = std::max(2, static_cast<int>(std::ceil(0.35f / vs)));
        for (int dy = 1; dy <= sonda; ++dy) {
            const int y = yb - dy;
            if (y < 0) break;
            const uint8_t m = w.getVoxel(x, y, z);
            if (!m) continue;
            const uint64_t key = (static_cast<uint64_t>(x + 4096) << 42) | (static_cast<uint64_t>(y + 4096) << 21) | static_cast<uint64_t>(z + 4096);
            if (vistos.insert(key).second) {
                if (outMn) { *outMn = outMn->min(Vector3(x * vs, y * vs, z * vs)); *outMx = outMx->max(Vector3((x + 1) * vs, (y + 1) * vs, (z + 1) * vs)); }
                seccion += vx::material(m).phys.compressiveStrength;
                // el suelo indestructible sostiene pero no revienta
                if (!(vx::g_materials[m].flags & vx::MF_INDESTRUCTIBLE)) flojos.push_back(vx::IVec3(x, y, z));
            }
            break;
        }
    }
    // Nada del mundo debajo: esta apoyado en otros bloques (o en el aire). No es este el juez.
    { static const bool lp = std::getenv("VX_LOGPIECES") != nullptr; if (lp && flojos.empty()) { std::fprintf(stderr, "[apoyo] vox=%u sin mundo debajo (seccion %.1f)", d.voxelCount, seccion); std::fputc(10, stderr); } }
    if (flojos.empty()) { return true; }
    // carga en la misma unidad que el analizador: voxels equivalentes de hormigon...
    const float densRef = 2500.f;
    // ...multiplicada por el IMPACTO: un bloque que ha caido no se posa, golpea. Sin esto, el tablero de la
    // mesa de pruebas serrado a mazo caia 30 cm sobre los tocones de las patas, cuatro postes aguantan
    // 70 t a compresion, y se quedaba ahi torcido para siempre (medido con --mesamazo=3).
    const float carga = static_cast<float>(d.voxelCount) * (static_cast<float>(vx::g_materials[d.dominantMat].density) / densRef) * impacto;
    // misma escala por tamano de voxel que el analizador (seccion ~rel^2, masa ~rel^3): sin esto a 10 cm era 2,5 veces mas estricto
    const float capacidad = seccion * vx::STRESS_CAPACITY * (0.25f / vs);
    static const bool logApoyo = std::getenv("VX_LOGPIECES") != nullptr;
    if (logApoyo) { std::fprintf(stderr, "[apoyo] vox=%u impacto=%.2f carga=%.0f seccion=%.1f capacidad=%.0f apoyos=%zu y=%.2f -> %s", d.voxelCount, impacto, carga, seccion, capacidad, flojos.size(), t.origin.y, carga <= capacidad * 2.f ? "AGUANTA" : "REVIENTA"); std::fputc(10, stderr); }
    if (carga <= capacidad * 2.f) { flojos.clear(); return true; }   // solo revienta lo que esta claramente por encima (el doble)
    return false;
}

bool VoxelWorld::asentarPieza(Body& b, const Transform3D& t) {
    // UN BLOQUE ES UN BLOQUE: de pie, cayendo y en el suelo. Lo que se desprende es un cuerpo desde que se
    // suelta hasta siempre (ver 09_BLOQUES_Y_RED.md). Aqui, ANTES DE DORMIRLO, se juzga si lo que tiene
    // debajo lo sostiene: compresion con impacto, vuelco y tacos sueltos (2026-09-18, ver
    // 10_CONSTRUIR_MAPAS.md #5). EN RED LO DECIDE EL ANFITRION (`settleAuthority_`).
    static thread_local std::vector<vx::IVec3> flojos;
    // IMPACTO: x1 por cada 10 cm caidos desde la altura maxima real, tope x4 (caer 30 cm ~ x4)
    const float caida = std::max(0.f, b.yMax - t.origin.y);
    const float impacto = std::min(4.f, 1.f + caida / 0.1f);
    { static const bool lp = std::getenv("VX_LOGPIECES") != nullptr; if (lp) { std::fprintf(stderr, "[asentar] vox=%u autoridad=%d caida=%.2f impacto=%.2f y=%.2f", b.data.voxelCount, settleAuthority_ ? 1 : 0, caida, impacto, t.origin.y); std::fputc(10, stderr); } }
    // VUELCO Y TACOS SUELTOS. El apoyo en el mundo se juzga a compresion, pero un tablero de 9 m sobre una
    // pata de esquina no revienta la pata: VUELCA. Si el centro de masas queda fuera de la caja de sus
    // contactos con el mundo (con 0,3 m de margen), o no toca mundo, lo que lo sostiene son bloques
    // sueltos; los que tengan menos de un octavo de su masa (los tacos de pata que deja el mazo) se hacen
    // anicos y el bloque sigue bajando. El analizador no ve los bloques: este es el unico sitio para esto.
    if (settleAuthority_ && b.rigid && b.data.voxelCount >= 2000) {
        static thread_local std::vector<vx::IVec3> nada;
        Vector3 cmn, cmx;
        apoyoSuficiente(b, t, nada, 1.f, &cmn, &cmx);
        const bool tocaMundo = cmn.x <= cmx.x;
        const bool vuelca = tocaMundo && (t.origin.x < cmn.x - 0.3f || t.origin.x > cmx.x + 0.3f || t.origin.z < cmn.z - 0.3f || t.origin.z > cmx.z + 0.3f);
        { static const bool lp = std::getenv("VX_LOGPIECES") != nullptr; if (lp) { std::fprintf(stderr, "[vuelco] vox=%u tocaMundo=%d vuelca=%d com=(%.1f,%.1f) contactos x %.1f..%.1f z %.1f..%.1f", b.data.voxelCount, tocaMundo ? 1 : 0, vuelca ? 1 : 0, t.origin.x, t.origin.z, cmn.x, cmx.x, cmn.z, cmx.z); std::fputc(10, stderr); } }
        if (!tocaMundo || vuelca) {
            const float vs3 = engine_->world().voxelSize();
            const Vector3 com3 = toGd(b.data.com);
            const float alcance = 0.8f;
            std::vector<Body*> debajo; uint64_t masaDebajo = 0;
            int paso = std::max(1, b.data.sx / 12);
            for (int lz = 0; lz < b.data.sz; lz += paso) for (int lx = 0; lx < b.data.sx; lx += paso) {
                int ly = 0; while (ly < b.data.sy && !b.data.vox[static_cast<size_t>(lx) + static_cast<size_t>(ly) * b.data.sx + static_cast<size_t>(lz) * b.data.sx * b.data.sy]) ++ly;
                if (ly >= b.data.sy) continue;
                const Vector3 p = t.xform(Vector3((lx + 0.5f) * vs3, ly * vs3, (lz + 0.5f) * vs3) - com3);
                for (Body& o : bodies_) {
                    if (&o == &b || (!o.congelado && !o.anclado && !o.resting)) continue;
                    const Vector3 c = o.rigid ? o.xf.origin : o.pos;
                    const float radio = 0.5f * vs3 * Vector3(static_cast<float>(o.data.sx), static_cast<float>(o.data.sy), static_cast<float>(o.data.sz)).length();
                    if ((c.x - p.x) * (c.x - p.x) + (c.z - p.z) * (c.z - p.z) > radio * radio) continue;
                    if (c.y - radio > p.y || c.y + radio < p.y - alcance) continue;
                    Vector3 q;
                    if (rayCuerpo(o, p, Vector3(0, -1, 0), alcance, q) >= 0.f && std::find(debajo.begin(), debajo.end(), &o) == debajo.end()) { debajo.push_back(&o); masaDebajo += o.data.voxelCount; }
                }
            }
            { static const bool lp = std::getenv("VX_LOGPIECES") != nullptr; if (lp) { std::fprintf(stderr, "[vuelco]   bloques debajo %zu con %llu voxels", debajo.size(), static_cast<unsigned long long>(masaDebajo)); std::fputc(10, stderr); } }
            // como mucho dos despertares por tacos: si Jolt lo sigue dando por parado, es que algo lateral lo
            // sostiene y la caja de contactos no lo ve; despertarlo sin fin lo dejaba dinamico para siempre
            if (b.vuelcos >= 2) { debajo.clear(); }
            if (!debajo.empty() && masaDebajo * 8 < b.data.voxelCount) {
                ++b.vuelcos;
                for (Body* o : debajo) {
                    const Vector3 c = o->rigid ? o->xf.origin : o->pos;
                    const float radio = 0.5f * vs3 * Vector3(static_cast<float>(o->data.sx), static_cast<float>(o->data.sy), static_cast<float>(o->data.sz)).length();
                    bool destruido = false;
                    despertarBloque(*o);
                    carveBodyAt(*o, c, radio + vs3, 255, false, destruido);
                }
                b.sleep = 0.f; b.quieto = 0.f; b.reasentarPronto = true; b.yMax = t.origin.y;
                despertarBloque(b);
                b.gracia = 0.3f;   // no la gracia de un golpe (2,5 s): que se vuelva a juzgar enseguida
                return true;
            }
            if (!tocaMundo && debajo.empty() && b.vuelcos < 3) {
                // nada debajo, ni mundo ni bloques: en el aire no se congela nadie
                ++b.vuelcos;
                b.sleep = 0.f; b.quieto = 0.f; b.reasentarPronto = true;
                despertarBloque(b);
                b.gracia = 0.3f;
                return true;
            }
            if (vuelca && debajo.empty() && b.vuelcos < 4) {
                // vuelca sobre el mundo: no se congela; se le deja a Jolt TIEMPO para que gire. Los bloques
                // grandes caen a camara lenta (gravedad 0,14): con 0,3 s no llegaba a moverse, contaba como
                // quieto y se anclaba torcido sobre dos patas del mismo lado (medido con --volar).
                ++b.vuelcos;
                b.sleep = 0.f; b.quieto = 0.f; b.reasentarPronto = false;
                despertarBloque(b);
                b.gracia = 2.5f;
                return true;
            }
        }
    }
    // SOLO LOS BLOQUES GRANDES APLASTAN (>= 3 m3): un cascote que aterriza en una repisa no la revienta, y con
    // el tope anterior "las cosas de abajo se rompian solas sin que nadie las golpeara"
    const float vsA = engine_->world().voxelSize();
    const bool pesado = static_cast<float>(b.data.voxelCount) * vsA * vsA * vsA >= 3.0f;
    if (settleAuthority_ && pesado && !apoyoSuficiente(b, t, flojos, impacto)) {
        // EL APOYO QUE CEDE SE APLASTA, no pierde un voxel. Quitando solo el voxel de contacto el bloque seguia
        // apoyado en las cajas de colision del tocon (mas anchas que un voxel) y no bajaba ni un centimetro.
        // Se quita 0,6 m de poste bajo cada contacto, con 0,3 m de radio (la cabeza del poste, no media pared).
        {
            const vx::World& wv = engine_->world();
            const float vs2 = wv.voxelSize();
            const int prof = std::max(2, static_cast<int>(std::ceil(0.6f / vs2)));
            const int rad = std::max(1, static_cast<int>(std::ceil(0.3f / vs2)));
            std::unordered_set<uint64_t> vistos;
            std::vector<vx::IVec3> mas;
            for (const vx::IVec3& v : flojos) {
                for (int k = 0; k < prof; ++k) for (int dz = -rad; dz <= rad; ++dz) for (int dx = -rad; dx <= rad; ++dx) {
                    const int x = v.x + dx, y = v.y - k, z = v.z + dz;
                    if (y < 0 || !wv.inBounds(x, y, z)) continue;
                    const uint8_t m = wv.getVoxel(x, y, z);
                    if (!m || (vx::g_materials[m].flags & vx::MF_INDESTRUCTIBLE)) continue;
                    const uint64_t key = (static_cast<uint64_t>(x + 4096) << 42) | (static_cast<uint64_t>(y + 4096) << 21) | static_cast<uint64_t>(z + 4096);
                    if (vistos.insert(key).second) mas.push_back(vx::IVec3(x, y, z));
                }
            }
            flojos.swap(mas);
        }
        // damage=false: aplastar un apoyo no abre analisis de cargas ni quita la proteccion pristine a lo de
        // alrededor. Con true, en Monaco cada bloque que aterrizaba encadenaba otro derrumbe (575 k voxels
        // con tres explosiones, medido).
        for (const vx::IVec3& v : flojos) {
            engine_->world().setVoxel(v.x, v.y, v.z, vx::MAT_AIR, false);
            if (enRed_ && apoyosRotosPend_.size() < 100000) apoyosRotosPend_.push_back(v);
        }
        b.reasentarPronto = true;
        b.yMax = t.origin.y;
        ++apoyosRotos_;
        b.sleep = 0.f;       // no se duerme: le acaba de desaparecer el suelo
        b.quieto = 0.f;
        despertarBloque(b);
        b.gracia = 0.3f;
        return true;         // se queda en la lista, cayendo
    }
    b.reasentarPronto = false;
    b.yMax = t.origin.y;
    // (2026-09-18: se probo que al dormir volviera a la rejilla del mundo -re-voxelizar-; un bloque torcido se
    // repinta escalonado y cambia de forma: "quedo horrible". Fuera. Duerme como bloque, con su forma exacta.)
    congelarPieza(b, t);
    return true;
}

/// EL TROZO SE QUEDA COMO CAYO. Ni se re-voxeliza ni se toca su malla: pasa a cuerpo estatico con su
/// postura exacta y ahi se queda. Es la unica forma de que no cambie de forma, porque la rejilla del
/// mundo no esta girada y meterlo en ella es repintarlo. El precio es que cada uno sigue siendo su
/// propia instancia de render y su propio cuerpo (no se funde en las mallas por bloque).
/// Rehace la colision de un trozo con su forma real y la deja estatica en `t`.
///
/// `BodyBuilder::decompose` es la misma descomposicion greedy en cajas que usa el motor al crear la
/// pieza; aqui se le da un presupuesto MUCHO mayor porque el cuerpo ya no se mueve.
void VoxelWorld::crearColisionFina(Body& b, const Transform3D& t) {
    PhysicsServer3D* ps = PhysicsServer3D::get_singleton();
    Ref<World3D> w = get_world_3d();
    if (!ps || !w.is_valid() || b.data.vox.empty()) return;
    static thread_local std::vector<vx::BodyBuilder::IBox> cajas;
    static thread_local std::vector<uint8_t> scratch;
    // SIN TOPE PRIMERO, Y EL RECORTE AQUI. Asi se sabe CUANTAS cajas hacian falta de verdad y se
    // puede avisar cuando el presupuesto se queda corto: lo que se recorta es colision que se pierde,
    // o sea sitios por los que se atraviesa el bloque andando. Con el recorte escondido dentro de
    // `decompose` esto no se podia ver desde fuera, y un arbol caido perdia las ramas en silencio.
    // SIN PRESUPUESTO: TODAS LAS CAJAS QUE HAGAN FALTA.
    //
    // Aqui habia un tope (`cajasFinas`) y lo que no entraba se TIRABA, o sea que el bloque se
    // quedaba con agujeros por los que el jugador lo atraviesa andando. Medido en partida: un arbol
    // de 34.421 voxels se quedaba con 132 cajas de las ~900 que necesita, y un bloque de 84.682
    // perdia 727 trozos. Se subio el tope dos veces y las dos se quedo corto, asi que fuera: la
    // colision de un trozo parado tiene que ser la del trozo entero.
    //
    // Lo que cuesta: son cajas de un cuerpo ESTATICO, que no se mueve ni se simula; solo ocupan
    // memoria y broadphase. Si algun dia esto pesa, se vera en los fps y aqui queda el contador.
    vx::Timer tcf;
    vx::BodyBuilder::decompose(b.data.vox.data(), b.data.sx, b.data.sy, b.data.sz, 0, cajas, scratch);
    g_cf[0] += tcf.ms();
    g_cfCajas += static_cast<int64_t>(cajas.size());
    g_cfTotalCajas += static_cast<int64_t>(cajas.size());
    if (cajas.empty()) return;
    if (static_cast<int>(cajas.size()) > 2000) {
        recortados_++;
        if (avisarRecorte_) {
            UtilityFunctions::print(String("[colision] bloque gordo: ") + itos(static_cast<int64_t>(b.data.voxelCount)) +
                " voxels -> " + itos(static_cast<int64_t>(cajas.size())) + " cajas (sin recortar)");
        }
    }
    // fuera las formas viejas (el bulto de 6 cajas) antes de poner las finas
    if (b.body.is_valid()) {
        ps->body_clear_shapes(b.body);
        for (RID sh : b.shapes) ps->free_rid(sh);
        b.shapes.clear();
    } else {
        b.body = ps->body_create();
        ps->body_set_collision_layer(b.body, static_cast<uint32_t>(collisionLayer_));
        ps->body_set_collision_mask(b.body, 0xFFFFFFFFu);
        ps->body_set_space(b.body, w->get_space());
        b.solid = true;
    }
    ps->body_set_state_sync_callback(b.body, Callable());   // ya no se mueve: no hace falta el callback
    ps->body_set_mode(b.body, PhysicsServer3D::BODY_MODE_STATIC);
    // LAS CAJAS SE AÑADEN CON EL CUERPO FUERA DEL ESPACIO (2026-10-02, medido con los bots a cohetazos: con el cuerpo dentro,
    // Jolt rehacia la forma compuesta en CADA `body_add_shape`, 5-12 ms por bloque de 100-800 cajas, y eran los tirones de
    // "mover bloques"). Fuera se construye una vez al volver a meterlo. No hay paso de fisica en medio: lo que se apoya en
    // el no lo nota. VX_CAJAS_DENTRO=1 = como antes.
    static const bool cajasDentro = std::getenv("VX_CAJAS_DENTRO") != nullptr;
    const RID espacio = ps->body_get_space(b.body);
    if (!cajasDentro && espacio.is_valid()) ps->body_set_space(b.body, RID());
    const float vs = engine_->world().voxelSize();
    for (const vx::BodyBuilder::IBox& c : cajas) {
        const vx::Vec3 centro = vx::Vec3((c.x0 + c.x1) * 0.5f * vs, (c.y0 + c.y1) * 0.5f * vs, (c.z0 + c.z1) * 0.5f * vs) - b.data.com;
        const vx::Vec3 medio((c.x1 - c.x0) * 0.5f * vs, (c.y1 - c.y0) * 0.5f * vs, (c.z1 - c.z0) * 0.5f * vs);
        vx::Timer tsh;
        RID sh = ps->box_shape_create();
        ps->shape_set_data(sh, toGd(medio));
        g_cf[1] += tsh.ms(); g_cfTotalMs += tsh.ms(); tsh = vx::Timer();
        ps->body_add_shape(b.body, sh, Transform3D(Basis(), toGd(centro)));
        g_cf[2] += tsh.ms(); g_cfTotalMs += tsh.ms();
        b.shapes.push_back(sh);
    }
    ps->body_set_param(b.body, PhysicsServer3D::BODY_PARAM_FRICTION, vx::material(b.data.dominantMat).phys.friction);
    ps->body_set_state(b.body, PhysicsServer3D::BODY_STATE_TRANSFORM, t);
    if (!cajasDentro && espacio.is_valid()) {
        vx::Timer tes;
        ps->body_set_space(b.body, espacio);
        g_cf[2] += tes.ms(); g_cfTotalMs += tes.ms();
    }
    cajasCongelado_ += static_cast<int64_t>(cajas.size());
}

/// LADO DE LA CELDA DE FUSION. Los trozos congelados de la misma celda comparten una malla. 16 m es
/// un compromiso: mas grande junta mas piezas (menos draw calls) pero rehacer el grupo cuesta mas y
/// una caja englobante enorme estropea el descarte por frustum.
static constexpr float LADO_GRUPO = 16.0f;

uint64_t VoxelWorld::claveGrupo(const Vector3& p) const {
    const int64_t cx = static_cast<int64_t>(std::floor(p.x / LADO_GRUPO)) + 4096;
    const int64_t cy = static_cast<int64_t>(std::floor(p.y / LADO_GRUPO)) + 4096;
    const int64_t cz = static_cast<int64_t>(std::floor(p.z / LADO_GRUPO)) + 4096;
    return 1ull | (static_cast<uint64_t>(cx) << 1) | (static_cast<uint64_t>(cy) << 22) | (static_cast<uint64_t>(cz) << 43);
}

void VoxelWorld::ensuciarGrupo(uint64_t clave) {
    if (!clave) return;
    gruposCongelados_[clave].sucio = true;
}

/// Saca un trozo de su grupo: le devuelve su propia instancia de render y ensucia el grupo para que
/// se rehaga sin el. Se llama cuando una explosion lo despega.
// los congelados tallados cuya malla propia no se ha subido (ver reconstruirCuerpo)


void VoxelWorld::sacarDelGrupo(Body& b) {
    if (!b.grupo) return;
    ensuciarGrupo(b.grupo);
    b.grupo = 0;
    RenderingServer* rs = RenderingServer::get_singleton();
    Ref<World3D> w = get_world_3d();
    if (!rs || !w.is_valid() || b.inst.is_valid()) return;
    // tallado mientras estaba congelado: su malla propia se quedo sin subir (reconstruirCuerpo)
    if (g_mallaPendiente.erase(b.data.id)) {
        rs->mesh_clear(b.mesh);
        int s = addSurface(b.mesh, b.data.mesh, b.data.mesh.idxOpaque, opaqueMat_, 0);
        addSurface(b.mesh, b.data.mesh, b.data.mesh.idxGlass, glassMat_, s);
    }
    b.inst = rs->instance_create2(b.mesh, w->get_scenario());
    rs->instance_set_layer_mask(b.inst, CAPA_MUNDO);
    rs->instance_set_transform(b.inst, b.xf);
    ponerTexBloque(b.inst, b.texOrg, 1.0f);
}

/// Rehace UNA malla de grupo por frame (cuesta lo que una pieza grande, y no urge).
///
/// Funde la geometria de todos los trozos congelados de la celda en una sola malla, aplicando a cada
/// vertice la postura de su trozo. NO toca la fisica: cada trozo conserva su cuerpo estatico, asi que
/// el mazo, las balas y las explosiones lo siguen encontrando igual que antes.
void VoxelWorld::rehacerUnGrupo() {
    uint64_t clave = 0;
    for (auto& kv : gruposCongelados_) if (kv.second.sucio) { clave = kv.first; break; }
    if (!clave) return;
    RenderingServer* rs = RenderingServer::get_singleton();
    Ref<World3D> w = get_world_3d();
    if (!rs || !w.is_valid()) return;
    GrupoCongelado& g = gruposCongelados_[clave];
    g.sucio = false;
    ++g.ver;                          // lo que se estuviera subiendo de este grupo ya no vale
    // EN EL HILO DE LOS BLOQUES (ver BlockJob): la malla vieja se sigue viendo hasta que llega la nueva
    static const bool gruposSync = std::getenv("VX_GRUPOS_SYNC") != nullptr;   // A/B: como antes
    const bool enHilo = asyncBlocks_ && !loading_ && !gruposSync;
    auto soltarViejo = [&]() {
        if (g.inst.is_valid()) { rs->free_rid(g.inst); g.inst = RID(); }
        if (g.mesh.is_valid()) { rs->free_rid(g.mesh); g.mesh = RID(); }
    };
    if (!enHilo) soltarViejo();

    Vector3 origen;
    bool hay = false;
    for (const Body& b : bodies_) {
        if (b.grupo != clave) continue;
        origen = b.xf.origin; hay = true; break;
    }
    g.piezas = 0;
    if (!hay) { soltarViejo(); gruposCongelados_.erase(clave); return; }

    static thread_local std::vector<Vector3> pos, nor;
    static thread_local std::vector<Color> col;
    static thread_local std::vector<Vector2> uvs;
    static thread_local std::vector<int32_t> idxOp, idxCr;
    pos.clear(); nor.clear(); col.clear(); uvs.clear(); idxOp.clear(); idxCr.clear();
    const float invVs = 1.f / engine_->world().voxelSize();
    for (const Body& b : bodies_) {
        if (b.grupo != clave) continue;
        const vx::MeshData& md = b.data.mesh;
        if (md.verts.empty()) continue;
        const int32_t base = static_cast<int32_t>(pos.size());
        const Basis& bs = b.xf.basis;
        const Vector3 desp = b.xf.origin - origen;
        for (const vx::MeshVertex& v : md.verts) {
            pos.push_back(bs.xform(Vector3(v.x, v.y, v.z)) + desp);
            nor.push_back(bs.xform(Vector3(static_cast<float>(vx::FACE_DIR[v.normal][0]),
                                           static_cast<float>(vx::FACE_DIR[v.normal][1]),
                                           static_cast<float>(vx::FACE_DIR[v.normal][2]))).normalized());
            const Color bc = materialLinear(v.mat);
            const float ao = 0.55f + 0.15f * v.ao;
            col.push_back(Color(bc.r * ao, bc.g * ao, bc.b * ao, alfaVertice(v.mat)));
            // LA TEXTURA DEL TROZO VA CON EL TROZO: aqui la malla ya esta girada, asi que el shader no puede sacar de la
            // posicion donde cae cada voxel. Se le da hecha, en voxels de la rejilla de la que salio y en los dos ejes
            // de la cara (los mismos que usa el shader con los bloques que se mueven: al congelarse no cambia nada).
            const Vector3 p = (Vector3(v.x, v.y, v.z) + b.texOrg) * invVs;
            const int eje = v.normal >> 1;
            uvs.push_back(eje == 0 ? Vector2(p.z, p.y) : (eje == 1 ? Vector2(p.x, p.z) : Vector2(p.x, p.y)));
        }
        for (uint32_t i : md.idxOpaque) idxOp.push_back(base + static_cast<int32_t>(i));
        for (uint32_t i : md.idxGlass)  idxCr.push_back(base + static_cast<int32_t>(i));
        ++g.piezas;
    }
    if (pos.empty() || (idxOp.empty() && idxCr.empty())) { soltarViejo(); gruposCongelados_.erase(clave); return; }

    PackedVector3Array vp; vp.resize(static_cast<int64_t>(pos.size()));
    PackedVector3Array np; np.resize(static_cast<int64_t>(nor.size()));
    PackedColorArray cp; cp.resize(static_cast<int64_t>(col.size()));
    PackedVector2Array tp; tp.resize(static_cast<int64_t>(uvs.size()));
    std::memcpy(vp.ptrw(), pos.data(), pos.size() * sizeof(Vector3));
    std::memcpy(np.ptrw(), nor.data(), nor.size() * sizeof(Vector3));
    std::memcpy(cp.ptrw(), col.data(), col.size() * sizeof(Color));
    std::memcpy(tp.ptrw(), uvs.data(), uvs.size() * sizeof(Vector2));
    if (enHilo) {
        if (!blockWorker_.joinable()) {
            blockStop_ = false;
            blockWorker_ = std::thread(&VoxelWorld::blockWorkerLoop, this);
        }
        BlockJob j;
        j.grupo = clave;
        j.ver = g.ver;
        j.origen = origen;
        j.matO = opaqueMat_.is_valid() ? opaqueMat_->get_rid() : RID();
        j.matG = glassMat_.is_valid() ? glassMat_->get_rid() : RID();
        for (int pase = 0; pase < 2; ++pase) {
            const std::vector<int32_t>& src = pase == 0 ? idxOp : idxCr;
            if (src.empty()) continue;
            PackedInt32Array ip; ip.resize(static_cast<int64_t>(src.size()));
            std::memcpy(ip.ptrw(), src.data(), src.size() * sizeof(int32_t));
            Array arr; arr.resize(RenderingServer::ARRAY_MAX);
            arr[RenderingServer::ARRAY_VERTEX] = vp;
            arr[RenderingServer::ARRAY_NORMAL] = np;
            arr[RenderingServer::ARRAY_COLOR] = cp;
            arr[RenderingServer::ARRAY_TEX_UV] = tp;
            arr[RenderingServer::ARRAY_INDEX] = ip;
            (pase == 0 ? j.arrO : j.arrG) = arr;
        }
        for (const Body& b : bodies_) if (b.grupo == clave) j.ids.push_back(b.data.id);
        { std::lock_guard<std::mutex> lk(blockMx_); blockIn_.push_back(std::move(j)); }
        blockCv_.notify_one();
        return;
    }
    g.mesh = rs->mesh_create();
    int sup = 0;
    for (int pase = 0; pase < 2; ++pase) {
        const std::vector<int32_t>& src = pase == 0 ? idxOp : idxCr;
        if (src.empty()) continue;
        PackedInt32Array ip; ip.resize(static_cast<int64_t>(src.size()));
        std::memcpy(ip.ptrw(), src.data(), src.size() * sizeof(int32_t));
        Array arr; arr.resize(RenderingServer::ARRAY_MAX);
        arr[RenderingServer::ARRAY_VERTEX] = vp;
        arr[RenderingServer::ARRAY_NORMAL] = np;
        arr[RenderingServer::ARRAY_COLOR] = cp;
        arr[RenderingServer::ARRAY_TEX_UV] = tp;
        arr[RenderingServer::ARRAY_INDEX] = ip;
        rs->mesh_add_surface_from_arrays(g.mesh, RenderingServer::PRIMITIVE_TRIANGLES, arr);
        rs->mesh_surface_set_material(g.mesh, sup, (pase == 0 ? opaqueMat_ : glassMat_)->get_rid());
        ++sup;
    }
    g.inst = rs->instance_create2(g.mesh, w->get_scenario());
    rs->instance_set_layer_mask(g.inst, CAPA_MUNDO);
    rs->instance_set_transform(g.inst, Transform3D(Basis(), origen));
    ponerTexBloque(g.inst, Vector3(), 2.0f);
    rs->instance_geometry_set_cast_shadows_setting(g.inst, engine_->preset().shadows
        ? RenderingServer::SHADOW_CASTING_SETTING_ON : RenderingServer::SHADOW_CASTING_SETTING_OFF);
    // LA MALLA COMUN YA ESTA EN PANTALLA: ahora si se pueden soltar los dibujos sueltos. En este
    // orden no hay ni un frame en que el bloque no lo dibuje nadie (era el parpadeo al dormirse).
    for (Body& b2 : bodies_) {
        if (b2.grupo != clave || !b2.inst.is_valid()) continue;
        rs->free_rid(b2.inst);
        b2.inst = RID();
    }
}

void VoxelWorld::congelarPieza(Body& b, const Transform3D& t) {
    RenderingServer* rs = RenderingServer::get_singleton();
    PhysicsServer3D* ps = PhysicsServer3D::get_singleton();
    b.congelado = true;
    if (g_congeladoEn.size() > 200000) g_congeladoEn.clear();
    // (emplace: si se despierta y se vuelve a congelar, su reloj de limpieza sigue contando desde la primera vez)
    g_congeladoEn.emplace(b.data.id, Time::get_singleton()->get_ticks_msec());
    b.anclado = true;
    b.resting = true;
    b.siguiendo = false;      // la postura final ya esta: se deja de seguir al anfitrion
    b.xf = t;
    b.pos = t.origin;
    // SU DIBUJO PASA AL GRUPO... PERO NO TODAVIA.
    //
    // Aqui se le quitaba su instancia en el acto y se marcaba el grupo para rehacer. Pero la malla
    // comun se rehace en el frame SIGUIENTE, y ademas solo una por frame: en ese hueco el bloque no
    // lo dibujaba nadie, ni su instancia (recien borrada) ni el grupo (aun sin el). Eso es el
    // PARPADEO al dormirse, y duraba mas cuantos mas bloques se durmieran a la vez.
    //
    // Ahora se queda con su dibujo propio hasta que la malla comun ya lo incluya; es
    // `rehacerUnGrupo` quien libera las instancias sueltas, justo despues de crear la fundida. Nunca
    // hay un instante sin nadie dibujandolo.
    if (rs && b.inst.is_valid()) rs->instance_set_transform(b.inst, t);
    b.grupo = claveGrupo(t.origin);
    ensuciarGrupo(b.grupo);
    if (ps) {
        // COLISION DE ESCENARIO, NO DE CASCOTE. Un trozo que cae lleva como mucho 6 cajas a proposito:
        // en Jolt cada par cuerpo-cuerpo cuesta cajas x cajas, y con 20 la fisica se iba a 16 ms con
        // 18 cuerpos. Pero ese limite es para lo que SE MUEVE. Congelado pasa a estatico y ya no
        // choca contra nadie: puede permitirse su forma de verdad. Con 6 cajas el jugador no podia
        // subirse encima de un muro caido -el bulto no se parecia a lo que veia- y se colaba.
        crearColisionFina(b, t);
        // Ya no pertenece a la simulación de escombros: es escenario. Esta
        // separación impide que un montón dormido participe en pares de
        // escombro móvil y deja la carga al broadphase estático de Jolt.
        if (b.body.is_valid()) {
            ps->body_set_collision_layer(b.body, static_cast<uint32_t>(collisionLayer_));
            ps->body_set_collision_mask(b.body, MASCARA_ESCENARIO);
        }
    }
    ++congeladosVivos_;
    // MANDANDO YO: los demas tienen que congelarlo en la MISMA postura. Va por id (un hash del primer
    // voxel del trozo, igual en todas las maquinas) en vez de celda a celda: son 10 numeros en lugar
    // de miles de celdas, y ademas las dos pantallas acaban con la pieza exactamente igual puesta.
    if (settleAuthority_ && enRed_) emit_signal("pieza_congelada", static_cast<int64_t>(b.data.id), t);
}

void VoxelWorld::stepBodies(float dt) {
    ++pasosTotales_;
    if (bodies_.empty()) { rigidCount_ = cheapCount_ = cheapSolidCount_ = 0; return; }
    const vx::QualityPreset& preset = engine_->preset();
    RenderingServer* rs = RenderingServer::get_singleton();
    PhysicsServer3D* ps = PhysicsServer3D::get_singleton();
    const float vs = engine_->world().voxelSize();
    int rigid = 0, cheap = 0, cheapSolid = 0, congelados = 0;
    // ¿Algun chunk que toca el bloque tiene la colision del mundo por rehacer (sucio o en cola de fisica)?
    const vx::World& mundo = engine_->world();
    const float ladoChunk = vx::CHUNK_SIZE * vs;
    auto colisionPendienteBajo = [&](const Body& bq) -> bool {
        const Vector3 c = bq.rigid ? bq.xf.origin : bq.pos;
        const float r = 0.5f * vs * Vector3(static_cast<float>(bq.data.sx), static_cast<float>(bq.data.sy), static_cast<float>(bq.data.sz)).length() + vs * 2.f;
        const int x0 = std::clamp(static_cast<int>(std::floor((c.x - r) / ladoChunk)), 0, mundo.chunksX() - 1);
        const int x1 = std::clamp(static_cast<int>(std::floor((c.x + r) / ladoChunk)), 0, mundo.chunksX() - 1);
        const int y0 = std::clamp(static_cast<int>(std::floor((c.y - r) / ladoChunk)), 0, mundo.chunksY() - 1);
        const int y1 = std::clamp(static_cast<int>(std::floor((c.y + r) / ladoChunk)), 0, mundo.chunksY() - 1);
        const int z0 = std::clamp(static_cast<int>(std::floor((c.z - r) / ladoChunk)), 0, mundo.chunksZ() - 1);
        const int z1 = std::clamp(static_cast<int>(std::floor((c.z + r) / ladoChunk)), 0, mundo.chunksZ() - 1);
        for (int cz = z0; cz <= z1; ++cz) for (int cy = y0; cy <= y1; ++cy) for (int cx = x0; cx <= x1; ++cx) {
            const int idx = mundo.chunkIndex(cx, cy, cz);
            if (static_cast<size_t>(idx) < chunks_.size() && chunks_[static_cast<size_t>(idx)].physQueued) return true;
            const vx::Chunk* ch = mundo.chunkAt(idx);
            if (ch && ch->dirty.load(std::memory_order_relaxed)) return true;
        }
        return false;
    };
    // PRISA DE LOS CASCOTES (2026-09-28, pedido: "cuando haya mucho escombro suelto y baje de 60 fps, que se congele
    // antes"). Medido con --escombrofps en el hangar: en el pico de una lluvia de explosiones hay 40-50 trozos
    // despiertos y la fisica se come 2-2,5 ms; al dormirse vuelve a 0,1. Con prisa, los trozos PEQUEÑOS cuentan como
    // quietos yendo mas rapido y se duermen antes. Los grandes (un derrumbe) NO: caen a camara lenta y se anclarian
    // en el aire. La pone el juego segun los fps (solo por debajo de 60: con fps de sobra, todo como siempre).
    const float prisa = prisaEscombros_;
    prisaUsada_ = prisa;
    int despiertosChicos = 0;
    for (size_t i = 0; i < bodies_.size();) {
        Body& b = bodies_[i];
        // CONGELADO: ya no se simula ni se vuelve a mirar. Se queda donde cayo, con su forma y su
        // angulo, hasta que una explosion lo despegue (ver `explode`).
        // ...y NO cuenta como cuerpo rigido. `rigid` acaba en `rigidCount_`, que es el presupuesto que
        // decide si una pieza NUEVA recibe fisica. Contando aqui los congelados -que no se simulan y
        // ademas no desaparecen nunca- el contador solo subia: se llenaba el cupo y a partir de ahi
        // ninguna pieza volvia a ser rigida. En el juego se veia como que, despues de un par de
        // derrumbes, las cosas dejaban de caerse.
        if (b.congelado) { ++i; ++congelados; continue; }
        if (b.data.voxelCount == 0) {   // se quedo sin voxels (tallado del todo): fuera, no un cuerpo vacio asentandose sin parar
            freeBody(b); bodies_[i] = std::move(bodies_.back()); bodies_.pop_back();
            continue;
        }
        b.age += dt;
        if (b.gracia > 0.f) b.gracia = std::max(0.f, b.gracia - dt);
        // LO MUEVE EL ANFITRION: ni gravedad, ni sueño, ni anclaje. Se acerca a la ultima postura recibida
        // (suavizado: llegan ~15 por segundo y se dibuja a 60). Sin postura un rato, vuelve a ser suyo.
        if (b.siguiendo) {
            b.sinPostura += dt;
            if (b.sinPostura > SEGUIR_SUELTA_S) {
                b.siguiendo = false;
                b.quieto = 0.f; b.sleep = 0.f; b.gracia = GRACIA_TRAS_GOLPE;
                if (b.rigid && b.body.is_valid()) {
                    ps->body_set_mode(b.body, PhysicsServer3D::BODY_MODE_RIGID);
                    ps->body_set_state(b.body, PhysicsServer3D::BODY_STATE_SLEEPING, false);
                }
            } else {
                // EL OBJETIVO SE ADELANTA con la velocidad que traia (hasta la siguiente postura): seguir una
                // postura vieja ponia el bloque 80-100 ms detras del anfitrion, y una bala que lo cruzaba
                // mordia otra cosa en cada pantalla (medido: mas mapa distinto que simulando cada uno)
                if (b.sinPostura < 0.25f) b.objetivo.origin += b.objetivoVel * dt;
                const Transform3D cur = b.rigid ? b.xf : Transform3D(b.objetivo.basis, b.pos);
                const Transform3D nt = cur.interpolate_with(b.objetivo, std::min(1.f, dt * 20.f));
                if (b.rigid && b.body.is_valid()) ps->body_set_state(b.body, PhysicsServer3D::BODY_STATE_TRANSFORM, nt);
                b.xf = nt;
                b.pos = nt.origin;
                if (b.inst.is_valid()) rs->instance_set_transform(b.inst, nt);
                if (b.rigid) ++rigid; else ++cheap;
                ++i;
                continue;
            }
        }
        Transform3D t;
        if (b.rigid) {
            t = b.xf;
            b.pos = t.origin;
            if (interpolar_ && b.xfAntOk && b.xfAnt.origin.distance_to(t.origin) < 3.f) {
                const float fr = static_cast<float>(Engine::get_singleton()->get_physics_interpolation_fraction());
                rs->instance_set_transform(b.inst, b.xfAnt.interpolate_with(t, std::clamp(fr, 0.f, 1.f)));
            } else {
                rs->instance_set_transform(b.inst, t);
            }
            // TOPE DE VELOCIDAD a 30 Hz: nada tan rapido que cruce un suelo entre dos pasos (y la deteccion continua
            // cubre lo demas)
            if (interpolar_ && b.body.is_valid() && !b.anclado && b.linVel.length_squared() > VEL_MAX_30HZ * VEL_MAX_30HZ) {
                b.linVel = b.linVel.normalized() * VEL_MAX_30HZ;
                ps->body_set_state(b.body, PhysicsServer3D::BODY_STATE_LINEAR_VELOCITY, b.linVel);
            }
            // QUIETO NO ES LO MISMO QUE DORMIDO. Todo esto colgaba de `b.sleeping`, la bandera de Jolt,
            // y un personaje rozando el cascote lo despierta en cada frame: asi el trozo NO dormia
            // nunca, y por tanto ni se anclaba ni se congelaba. El resultado en el juego era que los
            // jugadores y los bots iban empujando los escombros grandes al caminar, no les dejaban
            // asentarse, y de esos empujones salian los sustos: el personaje disparado lejos o la losa
            // de dos toneladas saliendo volando. Ahora cuenta estar QUIETO, lo diga Jolt o no.
            const float rapidez = b.linVel.length();
            // LEJOS DE TODOS, SE DUERME. Un trozo que sigue resbalando o tambaleandose a mas de DORMIR_LEJOS_M de
            // cualquier personaje (el jugador, los bots, los de la sala: cercaDeAlguien) no lo ve nadie de cerca y
            // a Jolt le cuesta cada paso. Se le duerme; en cuanto alguien se acerca, se despierta y sigue donde
            // estaba. Solo si va despacio y NO cae: nada se queda colgado en el aire. Se mira cada 8 cuadros.
            if (b.body.is_valid() && !b.anclado && ((frame_ + i) % 8) == 0) {
                const uint64_t idc = b.body.get_id();
                vx::Timer tce;
                const bool lejos = !cercaDeAlguien(t.origin, DORMIR_LEJOS_M);
                g_bs[4] += tce.ms();
                auto it = g_dormidosLejos.find(idc);
                if (lejos && it == g_dormidosLejos.end() && !b.sleeping && rapidez < 0.6f && b.linVel.y > -0.15f && b.age > 1.0f) {
                    ps->body_set_state(b.body, PhysicsServer3D::BODY_STATE_SLEEPING, true);
                    g_dormidosLejos.insert(idc);
                } else if (!lejos && it != g_dormidosLejos.end()) {
                    ps->body_set_state(b.body, PhysicsServer3D::BODY_STATE_SLEEPING, false);
                    g_dormidosLejos.erase(it);
                }
            }
            b.yMax = std::max(b.yMax, t.origin.y);
            // CAMARA LENTA PROGRESIVA (pedido): un bloque grande cae a 0,2 g mientras esta alto y recupera 1 g
            // conforme se acerca al suelo (sondeado hacia abajo cada 6 pasos); los cascotes van siempre a 1 g.
            if (b.body.is_valid() && !b.anclado && b.data.voxelCount * vs * vs * vs >= 3.0f && ((frame_ + i) % 6) == 0) {
                vx::Timer tsu;
                const float suelo = sueloBajo(t.origin, 40.f, &b);
                g_bs[2] += tsu.ms();
                const float h = suelo > -1e8f ? std::max(0.f, t.origin.y - suelo - b.data.sy * vs * 0.5f) : 40.f;
                // MAS PESO (2026-10-04, pedido: "aumenta la fuerza del peso de las cosas"): la camara lenta baja como mucho a
                // 0,5 g (era 0,2) y tarda mas en llegar: lo grande cae con ganas y llega al suelo con mas golpe.
                // VX_DESGASTE_ANTES=1 = como antes.
                static const bool desgasteAntes = std::getenv("VX_DESGASTE_ANTES") != nullptr;
                const float g = desgasteAntes
                    ? (h <= 1.5f ? 1.0f : std::clamp(1.0f - 0.8f * (h - 1.5f) / 6.0f, 0.2f, 1.0f))    // 1 g hasta 1,5 m, 0,2 g a partir de 7,5 m
                    : (h <= 2.5f ? 1.0f : std::clamp(1.0f - 0.5f * (h - 2.5f) / 8.0f, 0.5f, 1.0f));   // 1 g hasta 2,5 m, 0,5 g a partir de 10,5 m
                if (std::fabs(g - b.gravEscala) > 0.05f) { b.gravEscala = g; ps->body_set_param(b.body, PhysicsServer3D::BODY_PARAM_GRAVITY_SCALE, g); }
            }
            // ...Y NO ESTA QUIETO SI BAJA. Los bloques grandes caen a camara lenta (gravedad 0,14-0,36): la viga
            // del puente de pruebas bajaba a 0,2 m/s, contaba como "quieta" y se anclaba EN EL AIRE a 2,6 m.
            const bool chico = b.data.voxelCount <= ESCOMBRO_CHICO;
            const float pr = chico ? prisa : 0.f;
            if (chico && !b.sleeping && !b.anclado) ++despiertosChicos;
            b.quieto = (rapidez < 0.35f + 0.9f * pr && b.linVel.y > -0.08f - 0.3f * pr) ? b.quieto + dt : 0.f;
            b.sleep = (b.sleeping || b.quieto > 0.f) ? b.sleep + dt : 0.f;
            // CON LA COLISION DE DEBAJO A MEDIO REHACER NO ESTA QUIETO, ESTA ENCAJADO. Un bloque grande que se
            // suelta nace dentro de la forma estatica de lo que era el mundo en su sitio, y hasta que esos
            // chunks se remallan y se rehace su colision (varios frames, con presupuesto) no se puede mover:
            // anclarlo o dormirlo ahi lo dejaba en el aire para siempre. Medido con --mesamazo=3: el tablero
            // se soltaba sobre una sola pata y se congelaba en 1,5 s sin girar un grado.
            // Y SU VIDA EMPIEZA CUANDO SE PUEDE MOVER: la edad y el punto de partida se reinician, asi que al
            // quedar libre tiene el mismo margen que un recien nacido para arrancar (un vuelco empieza despacio).
            if (colisionPendienteBajo(b)) { b.quieto = 0.f; b.sleep = 0.f; b.age = 0.f; b.origen = b.xf.origin; }
            // Parado y grande: se ancla (pasa a estatico y ya no lo mueve nadie). Por debajo de
            // VOXELS_EMPUJABLES son cascotes de mano y se pueden seguir moviendo de una patada, que es
            // lo que da gusto. En caida libre la velocidad pasa de 0,35 m/s en dos frames, asi que esto
            // no puede anclar nada en el aire; una explosion lo vuelve a soltar.
            // ...PERO NO RECIEN NACIDO Y SIN HABERSE MOVIDO (la misma regla que para dormirse, mas abajo). Un
            // tablero de 9 m que se suelta apoyado en la ultima pata arranca a volcar MUY despacio -los bloques
            // grandes caen a camara lenta-: a los 0,4 s aun no iba a 0,35 m/s, se anclaba y se quedaba en el
            // aire sobre una esquina para siempre. Medido con --mesamazo=3.
            const bool sinArrancar = b.age < 1.5f && b.xf.origin.distance_to(b.origen) < vs * 2.f;
            if (!b.anclado && !sinArrancar && b.body.is_valid() && b.quieto > 0.4f && static_cast<int>(b.data.voxelCount) > VOXELS_EMPUJABLES) {
                vx::Timer tcf;
                ps->body_set_mode(b.body, PhysicsServer3D::BODY_MODE_STATIC);
                b.anclado = true;
                // ANCLADO YA SE PISA: la colision fina en cuanto se para, no cuando se duerme. Entre una
                // cosa y otra pasan varios segundos, y en ese rato seguia con las 6 cajas de la caida:
                // subirte a una losa recien caida era caerte por los huecos que esas 6 no cubren.
                crearColisionFina(b, t);
                g_bs[0] += tcf.ms();
            }
            // EL CHOQUE CONTRA UNA PARED (2026-10-13, pedido: "un trozo que sale volando de una granada o del puño de oro choca
            // contra un edificio y no rompe nada, ni la pared ni el trozo"): el impacto de arriba solo miraba la caida. Si un
            // bloque que iba rapido (> CHOQUE_V_MIN) pierde de golpe mucha velocidad (> CHOQUE_DV), se busca la pared hacia
            // donde iba y se le abre un crater, y el bloque pierde su punta. Lo decide el anfitrion (senal "crater", como
            // el del suelo). Un choque por bloque cada CHOQUE_ESPERA s. VX_SIN_CHOQUE_PARED=1 = como antes.
            {
                // QUITADO (2026-10-13, pedido: "da muchisimo lag"): apagado; VX_CHOQUE_PARED=1 lo enciende para probar
                static const bool sinChoque = std::getenv("VX_CHOQUE_PARED") == nullptr;
                constexpr float CHOQUE_V_MIN = 5.0f, CHOQUE_DV = 3.5f, CHOQUE_ESPERA = 0.35f;
                auto &va = g_velAnt[b.data.id];
                const Vector3 vAnt = va.v;
                va.v = b.linVel;
                va.espera = std::max(0.f, va.espera - dt);
                const float vel0 = vAnt.length();
                const float dv = (vAnt - b.linVel).length();
                const float velH = Vector2(vAnt.x, vAnt.z).length();   // de lado: el golpe contra el suelo ya lo lleva el de abajo
                if (!sinChoque && settleAuthority_ && va.espera <= 0.f && vel0 > CHOQUE_V_MIN && velH > CHOQUE_V_MIN * 0.7f && dv > CHOQUE_DV
                    && b.data.voxelCount * vs * vs * vs >= 0.02f) {
                    const Vector3 dir = vAnt / vel0;
                    const float radio = 0.5f * vs * static_cast<float>(std::max(b.data.sx, std::max(b.data.sy, b.data.sz)));
                    Vector3 golpe; bool hay = false;
                    for (float d = 0.f; d <= radio + 0.6f; d += vs * 0.5f) {
                        const Vector3 q = t.origin + dir * d;
                        if (engine_->world().getVoxelAt(toVxV(q)) != vx::MAT_AIR) {
                            // el primer voxel solido que no sea del propio bloque (el bloque ya no esta en la rejilla)
                            golpe = q; hay = true; break;
                        }
                    }
                    if (hay) {
                        va.espera = CHOQUE_ESPERA;
                        const float vol = b.data.voxelCount * vs * vs * vs;
                        // proporcional al trozo: un cascote de 20 cm no abre medio metro de pared
                        const float r = std::min(std::clamp(0.10f + 0.025f * dv + 0.18f * std::cbrt(vol), 0.15f, 1.2f), radio * 0.9f + 0.1f);
                        const int power = std::min(255, 150 + static_cast<int>(12.f * dv));
                        engine_->explode(toVxV(golpe), r, power);
                        if (enRed_) emit_signal("crater", golpe, r, power, 0);
                        bool roto = false;
                        const Vector3 punta = golpe - dir * (r * 0.4f);
                        carveBodyAt(b, punta, r * 0.55f, power, true, roto);
                        if (enRed_) emit_signal("crater", punta, r * 0.55f, power, 1);
                        pushEffect("dust", golpe, std::min(3.0f, 0.5f + r * 2.f), b.data.dominantMat);
                        { static const bool lp = std::getenv("VX_LOGPIECES") != nullptr; if (lp) { std::fprintf(stderr, "[choque] vox=%u v=%.1f dv=%.1f r=%.2f", b.data.voxelCount, vel0, dv, r); std::fputc(10, stderr); } }
                    }
                }
            }
            // impacto contra el suelo: velocidad vertical que se frena de golpe -> polvo
            const Vector3 lv = b.linVel;
            // se frena de golpe tras haber caido al menos 0,4 m (a camara lenta un bloque grande no pasa de 1 m/s)
            if (!b.resting && lv.y > b.vy + 0.6f && b.vy < -0.3f && (b.yMax - t.origin.y) >= 0.4f) {
                b.resting = true;
                pushEffect("dust", t.origin - Vector3(0, b.data.sy * vs * 0.5f, 0), std::min(4.0f, 0.6f + b.data.voxelCount * 0.002f), b.data.dominantMat);
                // EL GOLPE ROMPE: lo que toca y a el mismo. Un bloque que aterriza a 2 m/s o mas deja crateres
                // pequenos en sus puntos de contacto y pierde esquinas, proporcional a la velocidad y al tamano
                // (pedido: "cuando cae tiene que romper lo que toca y romperse partes de su bloque"). Lo decide el
                // anfitrion; en LAN la huella del mapa reconcilia el crater en el invitado.
                vx::Timer timp;
                // MAS DESGASTE AL CAER (2026-10-04, pedido: "cuando caen escombros o cosas, el desgaste que hacen quiero
                // aumentarlo"): golpean desde 0,15 m3 (era 0,3: ahora tambien los cascotes medianos), crateres un tercio
                // mas grandes y con mas fuerza, hasta 12 puntos de contacto (eran 8), y el propio bloque se desconcha de
                // verdad al caer de mas de 1 m (no lo hacia nunca: la altura se ponia a cero antes de mirarla).
                // VX_DESGASTE_ANTES=1 = como antes. Sigue decidiendolo el anfitrion y viaja con la senal "crater".
                static const bool desgasteAntes = std::getenv("VX_DESGASTE_ANTES") != nullptr;
                if (settleAuthority_ && b.data.voxelCount * vs * vs * vs >= (desgasteAntes ? 0.3f : 0.15f)) {   // (pedido: mas destruccion y mas desgaste al caer)
                    // la fuerza sale de la ALTURA caida, no de la velocidad (que la camara lenta recorta)
                    const float caida = b.yMax - t.origin.y;
                    const float rapidezCaida = std::max(-b.vy, 2.0f * std::sqrt(caida));
                    const float vol = b.data.voxelCount * vs * vs * vs;
                    const float r = desgasteAntes
                        ? std::clamp(0.15f + 0.08f * rapidezCaida + 0.12f * std::cbrt(vol), 0.2f, 1.2f)
                        : std::clamp(0.2f + 0.11f * rapidezCaida + 0.16f * std::cbrt(vol), 0.25f, 1.6f);
                    const int power = desgasteAntes ? std::min(255, 160 + static_cast<int>(30.f * rapidezCaida))
                                                    : std::min(255, 180 + static_cast<int>(35.f * rapidezCaida));
                    const Vector3 com3 = toGd(b.data.com);
                    std::vector<Vector3> contactos;
                    const int paso = std::max(1, std::max(b.data.sx, b.data.sz) / 16);
                    for (int lz = 0; lz < b.data.sz && contactos.size() < 400; lz += paso) for (int lx = 0; lx < b.data.sx; lx += paso) {
                        int ly = 0; while (ly < b.data.sy && !b.data.vox[static_cast<size_t>(lx) + static_cast<size_t>(ly) * b.data.sx + static_cast<size_t>(lz) * b.data.sx * b.data.sy]) ++ly;
                        if (ly >= b.data.sy) continue;
                        const Vector3 p = t.xform(Vector3((lx + 0.5f) * vs, ly * vs, (lz + 0.5f) * vs) - com3);
                        const vx::Vec3 bajo = toVxV(p - Vector3(0, vs * 1.5f, 0));
                        if (engine_->world().getVoxelAt(bajo) != vx::MAT_AIR || puntoEnBloqueParado(bajo)) contactos.push_back(p);
                    }
                    { static const bool lp = std::getenv("VX_LOGPIECES") != nullptr; if (lp) { std::fprintf(stderr, "[impacto] vox=%u caida=%.2f rapidez=%.2f r=%.2f contactos=%zu", b.data.voxelCount, b.yMax - t.origin.y, rapidezCaida, r, contactos.size()); std::fputc(10, stderr); } }
                    b.yMax = t.origin.y;   // UN golpe por caida: los rebotes no vuelven a abrir crateres bajo el escombro de alrededor (ruido y deslizamientos)
                    if (!contactos.empty()) {
                        const size_t n = std::min<size_t>(desgasteAntes ? 8 : 12, contactos.size());
                        for (size_t k = 0; k < n; ++k) {
                            const Vector3 p = contactos[k * contactos.size() / n];
                            engine_->explode(toVxV(p - Vector3(0, r * 0.5f, 0)), r * 1.3f, 255);     // crater en lo que toca (mundo): fuerte
                            // EN RED, EN EL ACTO. Antes lo reconciliaba la huella del mapa, o sea que el invitado veia el
                            // crater segundos despues (pedido: "no veo en tiempo real el desgaste del impacto").
                            if (enRed_) emit_signal("crater", p - Vector3(0, r * 0.5f, 0), r * 1.3f, 255, 0);
                            // ...y en los bloques parados que pilla debajo
                            for (Body& o : bodies_) {
                                if (&o == &b || (!o.congelado && !o.anclado && !o.resting)) continue;
                                const Vector3 c = o.rigid ? o.xf.origin : o.pos;
                                const float radio = 0.5f * vs * Vector3(static_cast<float>(o.data.sx), static_cast<float>(o.data.sy), static_cast<float>(o.data.sz)).length();
                                if (c.distance_to(p) > radio + r) continue;
                                bool d2 = false;
                                despertarBloque(o);
                                carveBodyAt(o, p - Vector3(0, r * 0.5f, 0), r, power, true, d2);
                                if (enRed_) emit_signal("crater", p - Vector3(0, r * 0.5f, 0), r, power, 1);
                            }
                            bool destruido = false;
                            // el propio bloque se descascarilla POCO (pedido: se rompia entero): solo si cayo mas de 1 m, y pequeno
                            static const bool sinDesconche = std::getenv("VX_SIN_DESCONCHE") != nullptr;   // banco de red
                            if (!sinDesconche && (desgasteAntes ? b.yMax - t.origin.y : caida) >= 1.0f) {
                                carveBodyAt(b, p + Vector3(0, r * 0.3f, 0), r * 0.45f, power, true, destruido);
                                if (enRed_) emit_signal("crater", p + Vector3(0, r * 0.3f, 0), r * 0.45f, power, 1);
                            }
                            if (destruido) break;
                        }
                    }
                }
                g_bs[1] += timp.ms();
            }
            if (lv.y < -3.0f) b.resting = false;
            b.vy = lv.y;
            ++rigid;
        } else {
            if (!b.resting) {
                // misma camara lenta que los rigidos, y mas lenta cuanto mas grande sea el trozo
                b.vy -= 9.8f * pieceGravityFor(static_cast<int>(b.data.voxelCount)) * dt;
                // Empuje lateral heredado (explosion / vuelco), frenado por el aire. Se comprueban las
                // CUATRO ESQUINAS del trozo, no solo su centro: con piezas grandes el centro pasaba por
                // el hueco entre dos edificios y la pieza entera atravesaba la fachada de al lado.
                if (b.drift.length_squared() > 1e-4f) {
                    const Vector3 np = b.pos + b.drift * dt;
                    const float dx = b.data.sx * vs * 0.45f, dz = b.data.sz * vs * 0.45f;
                    const Vector3 esquinas[5] = { np,
                        np + Vector3(dx, 0, dz), np + Vector3(-dx, 0, dz),
                        np + Vector3(dx, 0, -dz), np + Vector3(-dx, 0, -dz) };
                    bool choca = false;
                    for (const Vector3& q : esquinas)
                        if (vx::isSolid(engine_->world().getVoxelAt(toVxV(q)))) { choca = true; break; }
                    if (!choca) b.pos = np; else b.drift = Vector3();
                    b.drift *= std::exp(-0.8f * dt);
                }
                const float halfH = b.data.sy * vs * 0.5f;
                const float fall = -b.vy * dt;
                // SONDA EN 5 PUNTOS, no solo la columna del centro de masas. El COM de una pieza en L,
                // en U o hueca cae en AIRE: el rayo unico no encontraba suelo, la pieza atravesaba el
                // mapa entero y se borraba al pasar de y=-5. Eso es lo que se veia como "corto el
                // edificio y partes del edificio cortado desaparecen".
                // 9 PUNTOS, repartidos casi hasta el borde. Con 5 puntos al 30 % del tamano, una losa
                // de 20 m sondeaba solo a +-6 m del centro y se colaba por encima de lo que hubiera
                // entre medias (el tejado del edificio de al lado, por ejemplo).
                const float ex = b.data.sx * vs * 0.45f, ez = b.data.sz * vs * 0.45f;
                const Vector3 probes[9] = { b.pos,
                    b.pos + Vector3(ex, 0, ez), b.pos + Vector3(-ex, 0, ez),
                    b.pos + Vector3(ex, 0, -ez), b.pos + Vector3(-ex, 0, -ez),
                    b.pos + Vector3(ex, 0, 0), b.pos + Vector3(-ex, 0, 0),
                    b.pos + Vector3(0, 0, ez), b.pos + Vector3(0, 0, -ez) };
                float landY = -1e9f;
                Vector3 landP = b.pos;
                for (const Vector3& pr : probes) {
                    // ...Y TAMBIEN CONTRA LOS BLOQUES YA PARADOS, no solo contra la rejilla: si no,
                    // los trozos pequeños se cuelan por dentro del monton de escombro.
                    vx::Timer tsu2;
                    const float y = sueloBajo(pr, halfH + fall + 0.02f, &b);
                    g_bs[2] += tsu2.ms();
                    if (y > landY) { landY = y; landP = Vector3(pr.x, y, pr.z); }
                }
                if (landY > -1e8f) {
                    b.pos.y = landY + halfH; b.vy = 0; b.resting = true;
                    pushEffect("dust", landP, std::min(4.0f, 0.6f + b.data.voxelCount * 0.002f), b.data.dominantMat);
                } else b.pos.y -= fall;
            } else {
                b.sleep += dt;
                // lo que lo sostenía puede haber caído después (derrumbe en cadena): re-comprobar el apoyo cada
                // 10 frames y volver a caer si ya no hay nada debajo. Antes se quedaba colgado en el aire.
                if ((frame_ + b.data.id) % 10 == 0) {
                    const float halfH2 = b.data.sy * vs * 0.5f;
                    const float ex2 = b.data.sx * vs * 0.45f, ez2 = b.data.sz * vs * 0.45f;
                    const Vector3 pr2[9] = { b.pos,
                        b.pos + Vector3(ex2, 0, ez2), b.pos + Vector3(-ex2, 0, ez2),
                        b.pos + Vector3(ex2, 0, -ez2), b.pos + Vector3(-ex2, 0, -ez2),
                        b.pos + Vector3(ex2, 0, 0), b.pos + Vector3(-ex2, 0, 0),
                        b.pos + Vector3(0, 0, ez2), b.pos + Vector3(0, 0, -ez2) };
                    bool sup = false;
                    for (const Vector3& q : pr2) {
                        vx::RayHit h2;
                        if (engine_->world().raycast(toVxV(q), vx::Vec3(0, -1, 0), halfH2 + vs * 2.5f, h2)) { sup = true; break; }
                    }
                    if (!sup) { b.resting = false; b.sleep = 0.f; }
                }
            }
            t = Transform3D(Basis(), b.pos);
            rs->instance_set_transform(b.inst, t);
            // el cuerpo cinemático sigue a la pieza: sin esto la colisión se quedaría donde nació
            if (b.body.is_valid()) { ps->body_set_state(b.body, PhysicsServer3D::BODY_STATE_TRANSFORM, t); ++cheapSolid; }
            ++cheap;
        }
        // EL BLOQUE SE PARA, SE DUERME, Y NO SE LE VUELVE A MIRAR.
        //
        // Aqui habia una comprobacion de apoyo (`bodySupported`) cada seis pasos: se sondeaba debajo
        // del bloque buscando voxels ESTATICOS y, si no los habia, se le dejaba cayendo. Tenia
        // sentido cuando lo que caia acababa volviendo a la rejilla, porque entonces el monton de
        // escombros ERA mundo y sostenia al siguiente. Desde que un bloque es un bloque para siempre,
        // debajo de un bloque caido casi nunca hay voxels: hay OTRO BLOQUE. Asi que aquello decia
        // "sin apoyo" de todo lo que se apila, los bloques no llegaban a asentarse nunca, y los que
        // ya se habian anclado se quedaban CLAVADOS EN EL AIRE en cuanto lo de debajo se movia.
        //
        // La regla es la simple: cuando se para, se duerme; solo lo despierta el DAÑO (`explode` lo
        // vuelve a soltar). Y sale gratis: un bloque dormido no cuesta nada por frame, en vez de
        // pagar una sonda de rayos cada seis pasos para el resto de la partida.
        //
        // Tampoco hay ya trato distinto para el invitado. Antes borraba sus trozos a los 12 s porque
        // no escribia voxels y esperaba el mapa del anfitrion; ahora se queda con los mismos bloques
        // que todos y lo unico que le llega es la POSTURA final de cada uno, por id (`place_frozen`).
        const float movido = (b.rigid ? b.xf.origin : b.pos).distance_to(b.origen);
        // NO SE DUERME UN BLOQUE QUE NO SE HA MOVIDO DE DONDE SALIO: se le da un margen para
        // apartarse, o el analizador lo encuentra en el mismo sitio y se entra en el bucle de
        // romper y rehacer.
        const bool recienNacido = b.age < 1.5f && movido < vs * 2.f;
        // (con prisa, los pequeños se duermen al medio segundo quietos y no pasan de 7 s despiertos)
        const float prD = b.data.voxelCount <= ESCOMBRO_CHICO ? prisa : 0.f;
        // SE CONGELAN ANTES (2026-10-05, pedido: "que lo que queda se congele mucho mas rapido y no consuma nada"):
        // quieto 0,8 s el escombro chico y 1,2 s lo grande (el preset decia 1,5-2,5 s), y nadie pasa de 12 s / 25 s
        // despierto (eran 45). Las comprobaciones de vuelco y apoyo de asentarPieza siguen igual: lo que esta
        // volcando o en el aire no se congela. VX_CONGELA_ANTES=1 = como antes.
        static const bool congelaAntes = std::getenv("VX_CONGELA_ANTES") != nullptr;
        const bool chicoD = b.data.voxelCount <= ESCOMBRO_CHICO;
        const float tBase = congelaAntes ? preset.sleepRevoxelSeconds : std::min(preset.sleepRevoxelSeconds, chicoD ? 0.8f : 1.2f);
        const float tDormir = tBase + (0.45f - tBase) * prD;
        const float edadBase = congelaAntes ? 45.f : (chicoD ? 12.f : 25.f);
        const float edadMax = edadBase + (7.f - edadBase) * prD;
        if (b.gracia <= 0.f && !recienNacido && (b.sleep > (b.reasentarPronto ? 0.6f : tDormir) || b.age > edadMax)) {
            if (t.origin.y > -2.f) {
                vx::Timer tas;
                asentarPieza(b, t);   // se queda como bloque dormido, en la lista
                g_bs[3] += tas.ms();
                ++i; continue;
            }
            ++removedVoid_;
            freeBody(b);
            bodies_[i] = std::move(bodies_.back()); bodies_.pop_back();
            if (b.rigid) --rigid; else --cheap;
            continue;
        }
        if (t.origin.y < -5.f) {
            // Ultima red antes de que un bloque se pierda: si hay mundo por encima en esa columna, se
            // deja en el suelo en vez de borrarlo. Un bloque cortado no debe evaporarse nunca. Se
            // queda como bloque, igual que todos: aqui se le re-voxelizaba y era la ultima costura
            // que quedaba por la que un bloque dejaba de serlo.
            vx::RayHit hu;
            const float vs2 = engine_->world().voxelSize();
            if (engine_->world().raycast(vx::Vec3(t.origin.x, engine_->world().sizeMeters().y - 1.f, t.origin.z), vx::Vec3(0, -1, 0), engine_->world().sizeMeters().y, hu)) {
                Transform3D rt(t.basis, Vector3(t.origin.x, hu.pos.y + b.data.sy * vs2 * 0.5f, t.origin.z));
                asentarPieza(b, rt);
                ++i; continue;
            }
            ++removedVoid_;
            freeBody(b); bodies_[i] = std::move(bodies_.back()); bodies_.pop_back();
            if (b.rigid) --rigid; else --cheap; continue;
        }
        ++i;
    }
    // EL TOPE DE BLOQUES DESPIERTOS (ver g_topeDespiertos): si hay mas moviendose que el tope, los mas LENTOS (ya
    // casi parados: menos de 1,5 m/s, con mas de medio segundo de vida y sin la gracia de un golpe) se asientan YA en
    // vez de esperar su segundo quietos. asentarPieza hace sus comprobaciones de siempre: lo que esta volcando o en el
    // aire no se congela (y queda despierto). Lo que va cayendo o volando de verdad no se toca.
    if (g_topeDespiertos > 0 && !creandoDeRed_) {
        std::vector<std::pair<float, size_t>> lentos;
        int despiertos = 0;
        for (size_t k = 0; k < bodies_.size(); ++k) {
            const Body& b = bodies_[k];
            if (!b.rigid || b.congelado || b.anclado || b.sleeping || b.siguiendo || !b.body.is_valid()) continue;
            ++despiertos;
            const float v = b.linVel.length();
            if (b.age > 0.5f && b.gracia <= 0.f && v < 1.5f) lentos.emplace_back(v, k);
        }
        if (despiertos > g_topeDespiertos && !lentos.empty()) {
            std::sort(lentos.begin(), lentos.end());
            int sobran = despiertos - g_topeDespiertos;
            for (const auto& e : lentos) {
                if (sobran <= 0) break;
                Body& b = bodies_[e.second];
                if (b.xf.origin.y < -2.f) continue;
                asentarPieza(b, b.xf);
                if (b.congelado || b.anclado) { --sobran; ++g_asentadosPorTope; }
            }
        }
    }
    rigidCount_ = rigid; cheapCount_ = cheap; cheapSolidCount_ = cheapSolid;
    despiertosAnt_ = despiertosChicos;
    congeladosVivos_ = congelados;   // recontado aqui: es la verdad, no un acumulado que se desajusta
    // Con la escena llena de piezas, las siguientes piezas pequenas se emiten como particulas: cada
    // cuerpo cuesta una malla, una instancia y una colision, y en un derrumbe salen a cientos.
    const int live = rigid + cheap;
    const float budget = static_cast<float>(std::max(1, engine_->preset().maxBodies));
    engine_->setBodyPressure(1.f + 5.f * std::max(0.f, (live - budget) / (budget * 3.f)));
}

// ---------------------------------------------------------------------------
// Escombros (MultiMesh)
// ---------------------------------------------------------------------------
void VoxelWorld::updateDebris() {
    if (!debrisMultimesh_.is_valid()) return;
    RenderingServer* rs = RenderingServer::get_singleton();
    const vx::DebrisSystem& ds = engine_->debris();
    if (ds.capacity() != debrisCapacity_) ensureDebris();
    const int n = std::min(ds.count(), debrisCapacity_);
    float* buf = g_mmEntero ? debrisBuffer_.ptrw() : mmPreparar(g_mmDebris, debrisMultimesh_, n, debrisCapacity_, DEBRIS_STRIDE);
    const float invVs = 1.0f / engine_->world().voxelSize();
    if (!buf) return;
    const vx::Debris* d = ds.data();
    for (int i = 0; i < n; ++i) {
        const Basis& R = debrisRot_[d[i].seed & 15];
        const float s = d[i].size;
        float* o = buf + i * DEBRIS_STRIDE;
        o[0] = R[0][0] * s; o[1] = R[0][1] * s; o[2]  = R[0][2] * s; o[3]  = d[i].pos.x;
        o[4] = R[1][0] * s; o[5] = R[1][1] * s; o[6]  = R[1][2] * s; o[7]  = d[i].pos.y;
        o[8] = R[2][0] * s; o[9] = R[2][1] * s; o[10] = R[2][2] * s; o[11] = d[i].pos.z;
        const Color& m = materialLinear(d[i].mat);
        if (g_escombroGris) {
            const float lum = 0.2126f * m.r + 0.7152f * m.g + 0.0722f * m.b;
            const float k = 0.20f;
            o[12] = (lum + (m.r - lum) * k) * 0.85f; o[13] = (lum + (m.g - lum) * k) * 0.85f; o[14] = (lum + (m.b - lum) * k) * 0.85f;
        } else {
            o[12] = m.r; o[13] = m.g; o[14] = m.b;     // el color del material, tal cual (la textura la pone trozo.gdshader)
        }
        o[15] = std::min(1.0f, d[i].life);
        o[16] = g_escombroGris ? -1.0f : capaDeMaterial(d[i].mat);
        o[17] = s * invVs;
        o[18] = static_cast<float>(d[i].seed & 255) / 255.0f;
        o[19] = 0.0f;
    }
    if (!g_mmEntero) { mmSubir(g_mmDebris, debrisMultimesh_, n); return; }
    rs->multimesh_set_buffer(debrisMultimesh_, debrisBuffer_);
    rs->multimesh_set_visible_instances(debrisMultimesh_, n);
}

// ---------------------------------------------------------------------------
// LOD / culling por distancia (el frustum culling lo hace el RenderingServer)
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
// OCLUSION POR RAYOS (2026-10-14, pedido: "como va a estar la GPU dibujando algo que tapa una pared"; la idea, de Vintage
// Story: en vez del grafo de cuevas de Minecraft, rayos desde la camara). Cada fotograma salen `g_oclRayos` rayos por la
// pantalla (una rejilla con un desplazamiento distinto cada vez) y se apunta el bloque y la region del voxel con el que
// chocan; el cristal se atraviesa. Lo que ningun rayo ha tocado en OCL_GUARDA s no se dibuja (solo se esconde la
// instancia: ni malla, ni colision, ni sombras cambian). Lo que esta a menos de OCL_CERCA de la camara, siempre.
// Solo imagen. set_oclusion_rayos(0) = como antes; VX_SIN_OCLUSION=1 tambien.
// ---------------------------------------------------------------------------------------------------------------------
static int g_oclRayos = 0;
static constexpr float OCL_GUARDA = 0.5f;     // s que se sigue dibujando algo que ya no ve ningun rayo
static constexpr float OCL_CERCA = 10.0f;     // m: alrededor de la camara, siempre
static std::vector<float> g_oclBloq, g_oclReg;     // ultima vez que un rayo lo toco (s)
static std::vector<uint8_t> g_oclAplic;            // bloque: 1 = escondido ahora
static std::vector<int64_t> g_oclRid;               // bloque: la instancia a la que se aplico (si cambia, se reaplica)
static uint32_t g_oclSemilla = 1;
static Vector3 g_oclCamAnt;
static float g_oclAhora = 0.f;
static int g_oclBloqOcultos = 0, g_oclRegOcultas = 0;
static long long g_oclTrisOcultos = 0;
static double g_oclMs = 0.0;

void VoxelWorld::set_ao_cerca(bool on) { g_aoCerca = on; if (engine_) engine_->setAoCerca(on); }

void VoxelWorld::set_oclusion_rayos(int rayos) {
    g_oclRayos = std::getenv("VX_SIN_OCLUSION") ? 0 : std::max(0, std::min(4000, rayos));
}

static inline float oclAzar() { g_oclSemilla = g_oclSemilla * 1664525u + 1013904223u; return (g_oclSemilla >> 8) * (1.0f / 16777216.0f); }

void VoxelWorld::oclusionRayos() {
    const uint64_t t0 = Time::get_singleton()->get_ticks_usec();
    g_oclAhora = static_cast<float>(t0 * 1e-6);
    // CADA DOS FOTOGRAMAS (2026-10-14, banco de la CPU del movil): lo que no toca un rayo sigue visible OCL_GUARDA (0,5 s),
    // asi que con una tanda cada dos fotogramas siguen siendo ~15 tandas en ese rato: la misma imagen a mitad de coste.
    // Un salto de camara (abajo) lanza la tanda en el acto. VX_OCL_CADA_CUADRO=1 = una tanda por fotograma.
    static const bool cadaCuadro = std::getenv("VX_OCL_CADA_CUADRO") != nullptr;
    static uint64_t tanda = 0;
    ++tanda;
    const size_t nb = blocks_.size(), nr = regions_.size();
    if (g_oclBloq.size() != nb) { g_oclBloq.assign(nb, g_oclAhora); g_oclAplic.assign(nb, 0); g_oclRid.assign(nb, 0); }
    if (g_oclReg.size() != nr) g_oclReg.assign(nr, g_oclAhora);
    Viewport* vp = get_viewport();
    Camera3D* cam = vp ? vp->get_camera_3d() : nullptr;
    if (!cam || !engine_) return;
    const vx::World& w = engine_->world();
    const float vs = w.voxelSize();
    const Vector3 o = cam->get_global_position();
    // un salto de camara (reaparecer, cambio de vista): todo visible un momento, que los rayos lo vuelvan a mirar
    if (o.distance_to(g_oclCamAnt) > 6.0f) {
        std::fill(g_oclBloq.begin(), g_oclBloq.end(), g_oclAhora);
        std::fill(g_oclReg.begin(), g_oclReg.end(), g_oclAhora);
    }
    const bool salto = o.distance_to(g_oclCamAnt) > 6.0f;
    g_oclCamAnt = o;
    if (!cadaCuadro && !salto && (tanda & 1ull)) { g_oclMs = (Time::get_singleton()->get_ticks_usec() - t0) / 1000.0; return; }
    const int bvox = BLOCK * vx::CHUNK_SIZE, rvox = REGION * vx::CHUNK_SIZE;
    auto marca = [&](const vx::IVec3& v) {
        if (v.x < 0 || v.y < 0 || v.z < 0) return;
        const int bx = v.x / bvox, by = v.y / bvox, bz = v.z / bvox;
        if (bx < bnx_ && by < bny_ && bz < bnz_) g_oclBloq[bx + bnx_ * (by + bny_ * bz)] = g_oclAhora;
        const int rx = v.x / rvox, ry = v.y / rvox, rz = v.z / rvox;
        if (rx < rnx_ && ry < rny_ && rz < rnz_) g_oclReg[rx + rnx_ * (ry + rny_ * rz)] = g_oclAhora;
    };
    const Vector2 tam = vp->get_visible_rect().size;
    const int n = g_oclRayos;
    const float aspecto = tam.y > 1.f ? tam.x / tam.y : 1.f;
    const int cols = std::max(1, static_cast<int>(std::sqrt(n * aspecto))), filas = std::max(1, n / cols);
    // hasta donde se dibuja: la distancia se mide a la esquina MAS CERCANA de la region, y lo que hay dentro puede estar
    // una diagonal mas alla (sin esto faltaban edificios lejanos que si se veian)
    const float maxd = renderDist_ * 1.1f + REGION * vx::CHUNK_SIZE * vs * 1.8f;
    for (int fy = 0; fy < filas; ++fy) for (int fx = 0; fx < cols; ++fx) {
        const Vector2 p((fx + oclAzar()) / cols * tam.x, (fy + oclAzar()) / filas * tam.y);
        const Vector3 d = cam->project_ray_normal(p);
        vx::Vec3 ro = toVxV(o + cam->project_ray_origin(p) - o);
        float queda = maxd;
        for (int paso = 0; paso < 5 && queda > 0.f; ++paso) {
            vx::RayHit hit;
            if (!w.raycast(ro, toVxV(d), queda, hit) || !hit.hit) break;
            // LA CAMARA DENTRO DE ALGO SOLIDO (pegada a una pared, la de tercera persona metida en un muro): desde dentro
            // la imagen se ve igual -las caras de dentro no se dibujan-, asi que el rayo lo atraviesa hasta salir al aire
            if (hit.dist < vs * 0.5f && paso == 0) {
                vx::Vec3 q = ro;
                int salto = 0;
                while (salto < 20 && w.getVoxel(static_cast<int>(std::floor(q.x / vs)), static_cast<int>(std::floor(q.y / vs)), static_cast<int>(std::floor(q.z / vs))) != 0) {
                    q = vx::Vec3(q.x + d.x * vs, q.y + d.y * vs, q.z + d.z * vs);
                    ++salto;
                }
                ro = q;
                queda -= salto * vs;
                continue;
            }
            marca(hit.voxel);
            // el voxel de la cara (puede caer en el bloque de al lado): tambien
            marca(vx::IVec3(hit.voxel.x + hit.normal.x, hit.voxel.y + hit.normal.y, hit.voxel.z + hit.normal.z));
            if (!(vx::material(hit.mat).flags & vx::MF_GLASS)) break;       // el cristal se atraviesa
            queda -= hit.dist + vs;
            ro = vx::Vec3(hit.pos.x + d.x * vs * 1.01f, hit.pos.y + d.y * vs * 1.01f, hit.pos.z + d.z * vs * 1.01f);
        }
    }
    // alrededor de la camara, siempre
    const int cerca = static_cast<int>(std::ceil(OCL_CERCA / (bvox * vs)));
    const int cbx = static_cast<int>(o.x / (bvox * vs)), cby = static_cast<int>(o.y / (bvox * vs)), cbz = static_cast<int>(o.z / (bvox * vs));
    for (int z = cbz - cerca; z <= cbz + cerca; ++z) for (int y = cby - cerca; y <= cby + cerca; ++y) for (int x = cbx - cerca; x <= cbx + cerca; ++x) {
        if (x < 0 || y < 0 || z < 0 || x >= bnx_ || y >= bny_ || z >= bnz_) continue;
        g_oclBloq[x + bnx_ * (y + bny_ * z)] = g_oclAhora;
        const int r = (x * BLOCK / REGION) + rnx_ * ((y * BLOCK / REGION) + rny_ * (z * BLOCK / REGION));
        if (r < static_cast<int>(nr)) g_oclReg[r] = g_oclAhora;
    }
    g_oclMs = (Time::get_singleton()->get_ticks_usec() - t0) / 1000.0;
}

void VoxelWorld::updateLod() {
    RenderingServer* rs = RenderingServer::get_singleton();
    const bool ocl = g_oclRayos > 0;
    if (ocl) oclusionRayos();
    g_oclBloqOcultos = 0; g_oclRegOcultas = 0; g_oclTrisOcultos = 0;
    auto bloqueSeVe = [&](int bq) { return !ocl || bq >= static_cast<int>(g_oclBloq.size()) || g_oclAhora - g_oclBloq[bq] <= OCL_GUARDA; };
    auto regionSeVe = [&](int r) { return !ocl || r >= static_cast<int>(g_oclReg.size()) || g_oclAhora - g_oclReg[r] <= OCL_GUARDA; };
    const vx::World& world = engine_->world();
    const float side = REGION * vx::CHUNK_SIZE * world.voxelSize();
    int visible = 0, visRegions = 0; long long tris = 0;
    int urgentes = 0;
    const int n = static_cast<int>(regions_.size());
    for (int r = 0; r < n; ++r) {
        RegionVis& rg = regions_[r];
        const Vector3 ro = regionOrigin(r);
        // distancia del jugador a la caja de la región (0 dentro)
        const Vector3 cl = playerPos_.clamp(ro, ro + Vector3(side, side, side));
        const float d = cl.distance_to(playerPos_);
        // histéresis: los umbrales se alejan un 8 % cuando ya se está en el estado más detallado
        // con la transicion suave, lo fino llega hasta el final de la franja (alli ya es todo LOD1)
        const bool fade = lodFadeOn();
        float nearT = lodNear_, farT = lodFar_, rendT = renderDist_;
        if (rg.state == 0) nearT *= 1.08f;
        if (rg.state >= 0 && rg.state <= 1) farT *= 1.08f;
        if (rg.state >= 0 && rg.state <= 2) rendT *= 1.08f;
        const int state = d < nearT ? 0 : (d < farT ? 1 : (d < rendT ? 2 : 3));
        const int rx = r % rnx_, ry = (r / rnx_) % rny_, rz = r / (rnx_ * rny_);
        if (state != rg.state) {
            rg.state = state;
            if (ocl && r < static_cast<int>(g_oclReg.size())) g_oclReg[r] = g_oclAhora;
            // pasa a verse de lejos con las mallas LOD atrasadas: se rehace en el siguiente cuadro (un
            // cuadro con la geometria vieja no se nota; 30 ms aqui dentro si)
            if (rg.lodStale && (state == 1 || state == 2)) {
                if (!rg.dirty) { rg.dirty = true; dirtyRegions_.push_back(r); }
                rg.dirtyFrame = frame_ > 21 ? static_cast<uint64_t>(frame_ - 21) : 0;
            }
            if (!regionCastsShadows(state)) {
                if (rg.shMesh.is_valid() || rg.shInst.is_valid()) liberarSombra(rg);
            } else if (rg.casterStale) {
                if (loading_) rebuildShadowCaster(r); else encolarSombra(r);
            }
            if (rg.shInst.is_valid()) rs->instance_set_visible(rg.shInst, regionCastsShadows(state));
            const int RB = REGION / BLOCK;
            for (int dz = 0; dz < RB; ++dz) for (int dy = 0; dy < RB; ++dy) for (int dx = 0; dx < RB; ++dx) {
                const int bx = rx * RB + dx, by = ry * RB + dy, bz = rz * RB + dz;
                if (bx >= bnx_ || by >= bny_ || bz >= bnz_) continue;
                const int bq = bx + bnx_ * (by + bny_ * bz);
                setBlockShown(bq, state == 0);
                if (!sinSoltarBloques()) {
                    BlockVis& blq = blocks_[bq];
                    if (state >= estadoSoltar_) {
                        if (blq.mesh.is_valid() || blq.dirty) soltarBloqueLejos(bq);
                    } else if (blq.lejos) {
                        blq.lejos = false;
                        blq.pendiente = true;
                        markBlockDirty(bq);
                    }
                }
            }
        }
        // LA LOD1: en estado 1, y con la transicion suave tambien en 0 si parte de la region queda mas alla
        // del inicio de la franja (el shader tramará cada pixel entre las dos segun su distancia)
        // y LA LOD2 igual con la franja de lejos: en estado 2, y en 0/1 si parte de la region queda mas alla
        bool want1 = state == 1, want2 = state == 2;
        if (fade && state <= 1) {
            const Vector3 a = (playerPos_ - ro).abs(), b = (playerPos_ - ro - Vector3(side, side, side)).abs();
            const float dmax = Vector3(std::max(a.x, b.x), std::max(a.y, b.y), std::max(a.z, b.z)).length();
            if (state == 0) want1 = dmax > fade1Ini() && d < farT;
            want2 = dmax > fade2Ini();
        }
        // SIN HUECOS: si la region ya esta cerca pero alguno de sus bloques aun no tiene malla (se solto de lejos y se
        // esta rehaciendo: tras un salto, al reaparecer o yendo muy deprisa), se sigue viendo su LOD1 hasta que llegue
        if (state == 0 && regionConBloquesPendientes(r)) {
            ++urgentes;
            if (!want1 && rg.inst1.is_valid()) want1 = true;
        }
        if ((want1 || want2) && !regionSeVe(r)) {
            ++g_oclRegOcultas;
            g_oclTrisOcultos += want1 ? rg.tris1 : rg.tris2;
            want1 = want2 = false;
        }
        const bool cambia = want1 != rg.vis1 || want2 != rg.vis2;
        if (want1 != rg.vis1) { rg.vis1 = want1; if (rg.inst1.is_valid()) rs->instance_set_visible(rg.inst1, want1); }
        if (want2 != rg.vis2) { rg.vis2 = want2; if (rg.inst2.is_valid()) rs->instance_set_visible(rg.inst2, want2); }
        // atrasada por una explosion mientras estaba cerca y oculta: al volver a verse, se rehace
        if (cambia && (want1 || want2) && rg.lodStale && !rg.dirty) {
            rg.dirty = true; dirtyRegions_.push_back(r);
            rg.dirtyFrame = frame_ > 21 ? static_cast<uint64_t>(frame_ - 21) : 0;
        }
        if (state == 0) {
            const int RB = REGION / BLOCK;
            for (int dz = 0; dz < RB; ++dz) for (int dy = 0; dy < RB; ++dy) for (int dx = 0; dx < RB; ++dx) {
                const int bx = rx * RB + dx, by = ry * RB + dy, bz = rz * RB + dz;
                if (bx >= bnx_ || by >= bny_ || bz >= bnz_) continue;
                const int bq = bx + bnx_ * (by + bny_ * bz);
                const BlockVis& bl = blocks_[bq];
                if (!bl.inst.is_valid()) continue;
                const bool ver = bloqueSeVe(bq);
                if (bq < static_cast<int>(g_oclAplic.size())) {
                    const int64_t rid = static_cast<int64_t>(bl.inst.get_id());
                    if (g_oclRid[bq] != rid || (g_oclAplic[bq] != 0) == ver) {
                        rs->instance_set_visible(bl.inst, ver);
                        g_oclAplic[bq] = ver ? 0 : 1;
                        g_oclRid[bq] = rid;
                    }
                }
                if (ver) { ++visible; tris += bl.tris; }
                else { ++g_oclBloqOcultos; g_oclTrisOcultos += bl.tris; }
            }
        } else if (state == 1 && rg.tris1) { ++visRegions; tris += rg.tris1; }
        else if (state == 2 && rg.tris2) { ++visRegions; tris += rg.tris2; }
    }
    visibleChunks_ = visible; visibleRegions_ = visRegions; visibleTris_ = tris;
    g_regionesUrgentes = urgentes;
}

// ---------------------------------------------------------------------------
// Comandos de juego
// ---------------------------------------------------------------------------
void VoxelWorld::pushEffect(const char* type, const Vector3& pos, float size, int mat) {
    Dictionary d;
    d["type"] = String(type); d["position"] = pos; d["size"] = size; d["material"] = mat;
    if (effectEvents_.size() >= 48) {
        // El buffer se llena con los "carve"/"dust" de las piezas que la propia explosión desprende: el evento
        // de la explosión (sonido, fuego, humo) nunca se descarta; se pone delante y cae el último polvo.
        if (std::strcmp(type, "blast") != 0) return;
        effectEvents_.pop_back();
        effectEvents_.insert(0, d);
        return;
    }
    effectEvents_.push_back(d);
}

int VoxelWorld::carveBodyAt(Body& b, const Vector3& pos, float radius, int power, bool falloff, bool& destroyed) {
    const Transform3D t0 = b.rigid ? b.xf : Transform3D(Basis(), b.pos);
    // punto en la rejilla del cuerpo (metros), origen = esquina de la rejilla
    return carveBodyAtLocal(b, t0.affine_inverse().xform(pos) + toGd(b.data.com), radius, power, falloff, destroyed);
}

Vector3 VoxelWorld::punto_local_cuerpo(const RID& body, const Vector3& pos) const {
    for (const Body& b : bodies_) {
        if (b.body != body) continue;
        const Transform3D t = b.rigid ? b.xf : Transform3D(Basis(), b.pos);
        return t.affine_inverse().xform(pos) + toGd(b.data.com);
    }
    return Vector3();
}

/// EL TAJO REPLICADO, POR NUMERO. Antes la otra maquina buscaba "el trozo que haya cerca" del punto del
/// mundo y le hacia el agujero ahi: con el bloque cayendo, cada una lo tiene en otra postura, asi que el
/// agujero caia en otros voxels, los pedazos que se desgajaban salian distintos (y con otro numero) y el
/// anfitrion mandaba posturas de bloques que el invitado no tenia. Medido con --escombrolan: 9 tiros a
/// bloques cayendo y el anfitrion acababa con 7 bloques y el invitado con 9.
int VoxelWorld::carve_body_id(int64_t id, const Vector3& local, float radius, int power) {
    if (!engine_) return -1;
    for (size_t i = 0; i < bodies_.size(); ++i) {
        if (static_cast<int64_t>(bodies_[i].data.id) != id) continue;
        ++tallasCuerpo_;
        bool destroyed = false;
        const int n = carveBodyAtLocal(bodies_[i], local, radius, power, false, destroyed);
        if (destroyed) { ++removedCarve_; freeBody(bodies_[i]); bodies_[i] = std::move(bodies_.back()); bodies_.pop_back(); }
        return n;
    }
    return -1;
}

int VoxelWorld::carveBodyAtLocal(Body& b, const Vector3& local, float radius, int power, bool falloff, bool& destroyed) {
    destroyed = false;
    RenderingServer* rs = RenderingServer::get_singleton();
    PhysicsServer3D* ps = PhysicsServer3D::get_singleton();
    const float vs = engine_->world().voxelSize();
    vx::VoxelBody& d = b.data;
    const Transform3D t = b.rigid ? b.xf : Transform3D(Basis(), b.pos);
    const Vector3 pos = t.xform(local - toGd(d.com));
    const Vector3 g = local / vs;
    const int rv = static_cast<int>(std::ceil(radius / vs)) + 1;
    const float r2 = radius * radius;
    int removed = 0;
    int cnt[vx::MAT_COUNT] = {0};
    // 5 particulas por golpe como maximo (pedido: menos escombro, ahorro); antes el deposito se llenaba y el mazo ya no sacaba
    // nada. Y CON EL AJUSTE "PARTICULAS DE DESTRUCCION" (2026-10-05, bug: "la puse en Off y al desgastarse un bloque o con
    // una granada me las sigue generando"): en Off ninguna, en Pocas/Normales su parte.
    const int maxEscombro = debrisScale_ <= 0.01f ? 0 : std::max(1, static_cast<int>(std::lround(5.0f * std::min(1.0f, debrisScale_))));
    for (int z = std::max(0, static_cast<int>(g.z) - rv); z < std::min(d.sz, static_cast<int>(g.z) + rv + 1); ++z)
    for (int y = std::max(0, static_cast<int>(g.y) - rv); y < std::min(d.sy, static_cast<int>(g.y) + rv + 1); ++y)
    for (int x = std::max(0, static_cast<int>(g.x) - rv); x < std::min(d.sx, static_cast<int>(g.x) + rv + 1); ++x) {
        uint8_t& m = d.vox[x + y * d.sx + z * d.sx * d.sy];
        if (!m) continue;
        const float dx = (x + 0.5f - g.x) * vs, dy = (y + 0.5f - g.y) * vs, dz = (z + 0.5f - g.z) * vs;
        const float dist2 = dx * dx + dy * dy + dz * dz;
        if (dist2 > r2) continue;
        const vx::Material& mat = vx::material(m);
        if (mat.flags & vx::MF_INDESTRUCTIBLE) continue;
        // un trozo desprendido ya está roto: resiste menos que el material intacto
        const float strength = mat.strength * 0.45f;
        const float p = falloff ? power * (1.0f - dist2 / r2) : static_cast<float>(power);
        if (p < strength) continue;
        ++cnt[m];
        // Escombro determinista desde la posicion real del voxel, empujado desde el punto de impacto.
        // 64 por tallada eran demasiadas: un cascote grande recibiendo una rafaga escupia una nube de
        // particulas por bala ("caen muchos voxeles como si fuera cristal") y encima cuestan.
        if (removed < maxEscombro) {
            const Vector3 wp = t.xform(Vector3((x + 0.5f) * vs, (y + 0.5f) * vs, (z + 0.5f) * vs) - toGd(d.com));
            Vector3 dir = wp - pos;
            dir = dir.length() > 0.01f ? dir.normalized() : Vector3(0, 1, 0);
            const float k = 1.0f - std::min(1.0f, std::sqrt(dist2) / radius);
            const Vector3 vel = dir * ((2.0f + power * 0.02f) * (0.4f + 0.6f * k)) + Vector3(0, 1.0f, 0);
            engine_->debris().emitAt(toVxV(wp), toVxV(vel), vs * 0.9f, m, static_cast<uint16_t>(vx::hash3(x, y, z) >> 16));
        }
        m = vx::MAT_AIR; ++removed;
    }
    if (!removed) return 0;
    pushEffect("carve", pos, std::min(2.0f, 0.4f + removed * 0.01f), d.dominantMat);
    d.voxelCount = d.voxelCount > static_cast<uint32_t>(removed) ? d.voxelCount - removed : 0;

    // ¿Se ha quedado en nada? Eso si hay que resolverlo ya: el trozo desaparece y lo poco que queda
    // sale volando como escombro.
    if (static_cast<int>(d.voxelCount) < engine_->minBodyVoxels()) {
        for (int z = 0; z < d.sz; ++z) for (int y = 0; y < d.sy; ++y) for (int x = 0; x < d.sx; ++x) {
            const uint8_t m = d.vox[x + y * d.sx + z * d.sx * d.sy];
            if (!m) continue;
            if (((vx::hash3(x, y, z) >> 3) & 1023u) >= static_cast<uint32_t>(std::min(1.0f, debrisScale_) * 1024.f)) continue;   // el ajuste
            const Vector3 wp = t.xform(Vector3((x + 0.5f) * vs, (y + 0.5f) * vs, (z + 0.5f) * vs) - toGd(d.com));
            engine_->debris().emitAt(toVxV(wp), vx::Vec3(0, 0.5f, 0), vs * 0.9f, m, static_cast<uint16_t>(vx::hash3(x, y, z) >> 16));
        }
        destroyed = true;
        return removed;
    }
    // El resto (malla, cajas de colision, masa, centro de masas) se deja apuntado: lo hace
    // `reconstruirPendientes` una vez por frame y con tope. Los voxels YA estan quitados, asi que las
    // talladas siguientes y el congelado trabajan sobre el trozo correcto; lo unico que va con unos
    // frames de retraso es el aspecto y la colision, y eso no se nota en algo que esta cayendo.
    b.reconstruir = true;
    ++g_vozVer[d.id];
    // EL DAÑO DIRECTO A UN BLOQUE CONGELADO NO LO DESPIERTA. Ya terminó de caer:
    // se comporta como una pared del mundo y sólo se actualizan sus vóxeles, malla y
    // colisión estática. Despertarlo por cada bala reinsertaba una pieza enorme en Jolt
    // y era el tirón más visible en móvil. Las explosiones y el daño a su APOYO siguen
    // llamando explícitamente a despertarBloque/despertarSobre cuando de verdad debe caer.
    // Los bloques que todavía se están moviendo conservan el comportamiento dinámico.
    // ...PERO UN MAZAZO NO MUEVE 70 TONELADAS. Un bloque grande (>= 3 m3) solo se despierta si el golpe le
    // quita una parte que cuente (>= 1 %): un aranazo lo deja donde esta. Lo que le corta de verdad sigue
    // llegando por `separarPedazos` (lo partido nace como pieza nueva) y por perder el apoyo (despertarSobre).
    {
        const float vsw = engine_->world().voxelSize();
        // `congelado` es el estado final: cuerpo estático y colisión fina. `anclado`
        // puede ser un estado transitorio de una pieza aún en movimiento, así que no se
        // debe convertir implícitamente en una pared aquí.
        const bool asentado = b.congelado;
        const bool grande = static_cast<float>(b.data.voxelCount) * vsw * vsw * vsw >= 3.0f;
        const bool aranazo = grande && asentado && static_cast<float>(removed) < 0.01f * static_cast<float>(b.data.voxelCount + static_cast<uint32_t>(removed));
        if (!asentado && !aranazo) despertarBloque(b);
    }
    if (b.rigid && b.body.is_valid() && !b.congelado) {
        // No enviar SLEEPING=false a un cuerpo estático: es parte de mantener la
        // pieza asentada fuera de la simulación mientras se talla como una pared.
        PhysicsServer3D::get_singleton()->body_set_state(b.body, PhysicsServer3D::BODY_STATE_SLEEPING, false);
        b.sleeping = false;
        b.sleep = 0.f;
    }
    return removed;
}

/// Rehace la malla, las cajas de colision y el centro de masas de un trozo tallado. Es la parte cara.
/// Vuelve a poner un bloque dormido en movimiento. Lo contrario de `congelarPieza`.
void VoxelWorld::despertarBloque(Body& b) {
    if (!b.congelado && !b.anclado) return;
    PhysicsServer3D* ps = PhysicsServer3D::get_singleton();
    if (b.congelado) sacarDelGrupo(b);   // le devuelve su instancia de render
    b.congelado = false;
    b.anclado = false;
    b.resting = false;
    b.quieto = 0.f;
    b.sleep = 0.f;
    b.age = 0.f;
    b.gracia = GRACIA_TRAS_GOLPE;
    b.origen = b.rigid ? b.xf.origin : b.pos;   // su sitio de partida es DONDE ESTA, no donde nacio
    if (ps && b.body.is_valid() && b.rigid) {
        ps->body_set_mode(b.body, PhysicsServer3D::BODY_MODE_RIGID);
        ps->body_set_collision_layer(b.body, CAPA_ESCOMBRO_MOVIL);
        ps->body_set_collision_mask(b.body, MASCARA_ESCOMBRO_MOVIL | static_cast<uint32_t>(collisionLayer_));
        ps->body_set_param(b.body, PhysicsServer3D::BODY_PARAM_MASS, std::max(1.0f, b.data.mass));
        ps->body_set_param(b.body, PhysicsServer3D::BODY_PARAM_GRAVITY_SCALE, pieceGravityFor(static_cast<int>(b.data.voxelCount)));
        ps->body_set_state(b.body, PhysicsServer3D::BODY_STATE_SLEEPING, false);
        ps->body_set_state_sync_callback(b.body, Callable(this, "_on_body_state").bind(b.body));
        if (interpolar_) ps->body_set_enable_continuous_collision_detection(b.body, true);
    }
}

/// Si el daño ha partido el bloque, cada pedazo se va por su lado.
///
/// `reconstruirCuerpo` rehacia UN cuerpo con todos los voxels que quedaran, estuvieran pegados o no:
/// partias un bloque por la mitad y las dos mitades seguian siendo la misma pieza, unidas por nada y
/// bajando juntas. Aqui se etiquetan las partes conexas (6 vecinos) de su rejilla; la mayor se queda
/// en el bloque y las demas se devuelven al llamante, que las suelta como bloques nuevos.
///
/// Los pedazos que salen se entregan en coordenadas de MUNDO (pasados por la postura del bloque y
/// cuadrados a la rejilla). Pierden el angulo, si: pero es justo el instante en que algo se acaba de
/// partir, que es cuando menos se nota, y a cambio caen de verdad cada uno por su cuenta.
void VoxelWorld::separarPedazos(Body& b, const Transform3D& t, std::vector<std::vector<vx::BodyVoxel>>& fuera, std::vector<uint32_t>& ids) {
    vx::VoxelBody& d = b.data;
    const int64_t n = static_cast<int64_t>(d.sx) * d.sy * d.sz;
    if (n <= 1) return;
    static thread_local std::vector<int32_t> etiqueta;
    static thread_local std::vector<int32_t> pila;
    etiqueta.assign(static_cast<size_t>(n), 0);
    int32_t ncomp = 0;
    std::vector<int32_t> tam;
    auto I = [&](int x, int y, int z) { return x + y * d.sx + z * d.sx * d.sy; };
    for (int z = 0; z < d.sz; ++z) for (int y = 0; y < d.sy; ++y) for (int x = 0; x < d.sx; ++x) {
        const int i0 = I(x, y, z);
        if (!d.vox[static_cast<size_t>(i0)] || etiqueta[static_cast<size_t>(i0)]) continue;
        ++ncomp; tam.push_back(0);
        pila.clear(); pila.push_back(i0); etiqueta[static_cast<size_t>(i0)] = ncomp;
        while (!pila.empty()) {
            const int32_t c = pila.back(); pila.pop_back();
            ++tam[static_cast<size_t>(ncomp - 1)];
            const int cx = c % d.sx, cy = (c / d.sx) % d.sy, cz = c / (d.sx * d.sy);
            const int vec[6][3] = { {1,0,0}, {-1,0,0}, {0,1,0}, {0,-1,0}, {0,0,1}, {0,0,-1} };
            for (const int* v : vec) {
                const int nx = cx + v[0], ny = cy + v[1], nz = cz + v[2];
                if (nx < 0 || ny < 0 || nz < 0 || nx >= d.sx || ny >= d.sy || nz >= d.sz) continue;
                const int ni = I(nx, ny, nz);
                if (!d.vox[static_cast<size_t>(ni)] || etiqueta[static_cast<size_t>(ni)]) continue;
                etiqueta[static_cast<size_t>(ni)] = ncomp;
                pila.push_back(ni);
            }
        }
    }
    if (ncomp <= 1) return;
    int32_t mayor = 1;
    for (int32_t k = 2; k <= ncomp; ++k) if (tam[static_cast<size_t>(k - 1)] > tam[static_cast<size_t>(mayor - 1)]) mayor = k;
    const float vs = engine_->world().voxelSize();
    const float inv = 1.f / vs;
    std::vector<std::vector<vx::BodyVoxel>> sueltos(static_cast<size_t>(ncomp));
    // EL NUMERO DE CADA PEDAZO, DE SU REJILLA Y NO DEL MUNDO: el bloque padre y el primer voxel del pedazo
    // en la rejilla del padre. Con la posicion del mundo (como antes) dos maquinas con el bloque en posturas
    // distintas le daban otro numero al mismo pedazo, y la postura final del anfitrion no encontraba a quien
    // aplicarse.
    std::vector<uint32_t> idPedazo(static_cast<size_t>(ncomp), 0u);
    for (int z = 0; z < d.sz; ++z) for (int y = 0; y < d.sy; ++y) for (int x = 0; x < d.sx; ++x) {
        const int i0 = I(x, y, z);
        const int32_t e = etiqueta[static_cast<size_t>(i0)];
        if (!e || e == mayor) continue;
        if (idPedazo[static_cast<size_t>(e - 1)] == 0u)
            idPedazo[static_cast<size_t>(e - 1)] = (vx::hash3(x + static_cast<int>(d.id & 0x3FF) * 4096,
                y + static_cast<int>((d.id >> 10) & 0x3FF) * 4096, z + static_cast<int>((d.id >> 20) & 0x3FF) * 4096) >> 1) | 1u;
        const uint8_t m = d.vox[static_cast<size_t>(i0)];
        const Vector3 wp = t.xform(Vector3((x + 0.5f) * vs, (y + 0.5f) * vs, (z + 0.5f) * vs) - toGd(d.com));
        sueltos[static_cast<size_t>(e - 1)].push_back(vx::BodyVoxel{
            static_cast<int32_t>(std::floor(wp.x * inv)),
            static_cast<int32_t>(std::floor(wp.y * inv)),
            static_cast<int32_t>(std::floor(wp.z * inv)), m});
        d.vox[static_cast<size_t>(i0)] = 0;       // deja de ser de este bloque
        if (d.voxelCount) --d.voxelCount;
    }
    for (size_t k = 0; k < sueltos.size(); ++k) {
        if (sueltos[k].empty()) continue;
        fuera.push_back(std::move(sueltos[k]));
        ids.push_back(idPedazo[k]);
    }
}



void VoxelWorld::recogerCuerposHechos() {
    std::deque<CuerpoJob> hechos;
    { std::lock_guard<std::mutex> lk(g_cjMx); hechos.swap(g_cjOut); }
    for (CuerpoJob& j : hechos) {
        g_cjEnVuelo.erase(j.id);
        auto itv = g_vozVer.find(j.id);
        if (itv == g_vozVer.end() || itv->second != j.ver) continue;     // le dieron otra vez: se rehace con lo nuevo
        for (Body& b : bodies_) if (b.data.id == j.id) { reconstruirCuerpo(b, &j.out); break; }
    }
}

void VoxelWorld::reconstruirCuerpo(Body& b, vx::VoxelBody* hecho) {
    b.reconstruir = false;
    vx::Timer tRc; double tBuild = 0, tMalla = 0;
    RenderingServer* rs = RenderingServer::get_singleton();
    PhysicsServer3D* ps = PhysicsServer3D::get_singleton();
    const float vs = engine_->world().voxelSize();
    vx::VoxelBody& d = b.data;
    const Transform3D t = b.rigid ? b.xf : Transform3D(Basis(), b.pos);
    vx::VoxelBody nb;
    if (!hecho) {
    bodyScratch_.clear();
    for (int z = 0; z < d.sz; ++z) for (int y = 0; y < d.sy; ++y) for (int x = 0; x < d.sx; ++x) {
        const uint8_t m = d.vox[x + y * d.sx + z * d.sx * d.sy];
        if (m) bodyScratch_.push_back(vx::BodyVoxel{x, y, z, m});
    }
    if (bodyScratch_.empty()) return;
    // UN CONGELADO CONSERVA SU COLISION FINA. Reconstruirlo con las 6 cajas de un trozo que cae le
    // devolvia el bulto aproximado: despues de pegarle un tiro podias atravesarlo.
    // QUIETO, FORMA FINA; CAYENDO, 6 CAJAS. Aqui antes solo contaba estar congelado, y un mazazo lo
    // despierta (despertarBloque) justo antes de rehacerlo: la losa en la que estabas de pie se quedaba
    // con 6 cajas y te caias por los huecos. Medido con --diagcaida: "RIGID formas 6" y el jugador
    // atravesandola 150 ms despues. Recien golpeado (gracia) y anclado cuentan como quieto, y tambien
    // un bloque despierto que APENAS SE MUEVE: un segundo golpe (el mazo otra vez, o las balas de un bot)
    // le llega ya despierto, sin gracia nueva, y lo rehacia con 6 cajas aunque siguiera donde estaba.
    const bool casiQuieto = b.rigid ? b.linVel.length() < 1.0f : b.resting;
    const bool quieto = b.congelado || b.anclado || b.gracia > 0.f || casiQuieto;
    const int ncajas = quieto ? cajasFinas(static_cast<int>(bodyScratch_.size()))
                              : cajasMoviendose(static_cast<int>(bodyScratch_.size()), engine_->preset().maxBoxesPerBody);
    if (!g_cuerpoSync && !loading_ && d.voxelCount >= CUERPO_ASYNC_MIN) {
        if (!g_cjHilo.joinable()) g_cjHilo = std::thread(cjBucle);
        CuerpoJob job;
        job.id = d.id; job.ver = g_vozVer[d.id]; job.vox = bodyScratch_; job.vs = vs; job.ncajas = ncajas;
        g_cjEnVuelo.insert(d.id);
        { std::lock_guard<std::mutex> lk(g_cjMx); g_cjIn.push_back(std::move(job)); }
        g_cjCv.notify_one();
        return;     // lo aplica recogerCuerposHechos al volver
    }
    { vx::Timer tb; bodyBuilder_.build(bodyScratch_, vs, ncajas, d.id, nb); tBuild = tb.ms(); }
    } else {
        nb = std::move(*hecho);
    }
    // El nuevo COM, expresado en el marco del COM viejo (todo relativo a la esquina de la rejilla)
    const Vector3 off = toGd(nb.worldOrigin + nb.com - d.com);
    Transform3D nt = t;
    nt.origin = t.origin + t.basis.xform(off);
    // LA TEXTURA NO SE MUEVE AL TALLARLO: la rejilla nueva empieza en `nb.worldOrigin` (en la rejilla vieja) y su malla
    // va respecto a su propio COM; se corre el ancla lo mismo y cada voxel que queda sigue con su dibujo
    b.texOrg = toGd(nb.worldOrigin + nb.com) + (b.texOrg - toGd(d.com));
    nb.worldOrigin = d.worldOrigin;   // informativo
    d = std::move(nb);
    { vx::Timer tm;
    // UN CONGELADO EN SU GRUPO NO SUBE SU MALLA (2026-10-11, bug del bloque gigante caido): no se dibuja con ella (va
    // fundida en la del grupo, que se rehace en el hilo de los bloques) y subirla eran 5-9 ms por golpe en uno de 13.000
    // voxels. Se apunta y se sube si se despierta (sacarDelGrupo). VX_MALLA_CONGELADO=1 = como antes.
    static const bool mallaSiempre = std::getenv("VX_MALLA_CONGELADO") != nullptr;
    if (!mallaSiempre && b.congelado && b.grupo && !b.inst.is_valid()) {
        g_mallaPendiente.insert(d.id);
    } else if (asyncBlocks_ && !loading_ && !mallaSiempre && d.voxelCount >= 2000 && b.inst.is_valid() && blockWorker_.joinable()) {
        // UN BLOQUE GRANDE, SU MALLA EN EL HILO DE LOS BLOQUES (2026-10-11): subirla eran 5-9 ms por golpe en el hilo
        // principal. La vieja se sigue viendo hasta que llega la nueva (2-3 cuadros: el hueco aparece un instante despues)
        BlockJob job;
        job.cuerpo = d.id;
        job.ver = ++g_cuerpoVerN;
        g_cuerpoVer[d.id] = job.ver;
        job.md = d.mesh;
        job.matO = opaqueMat_.is_valid() ? opaqueMat_->get_rid() : RID();
        job.matG = glassMat_.is_valid() ? glassMat_->get_rid() : RID();
        { std::lock_guard<std::mutex> lk(blockMx_); blockIn_.push_back(std::move(job)); }
        blockCv_.notify_one();
        g_mallaPendiente.erase(d.id);
    } else {
        g_cuerpoVer.erase(d.id);      // lo que estuviera en camino ya no vale
        rs->mesh_clear(b.mesh);
        int s = addSurface(b.mesh, d.mesh, d.mesh.idxOpaque, opaqueMat_, 0);
        addSurface(b.mesh, d.mesh, d.mesh.idxGlass, glassMat_, s);
        g_mallaPendiente.erase(d.id);
    }
    tMalla = tm.ms(); }
    static const bool logRc = std::getenv("VX_LOG_RECONSTRUIR") != nullptr;
    struct Fin { vx::Timer& t; double& b; double& m; const vx::VoxelBody& d; bool on; bool cong;
        ~Fin() { if (on && t.ms() > 2.0) UtilityFunctions::print(String("[reconstruir] ") + String::num(t.ms(), 1) + " ms · voxels " + String::num_int64(d.voxelCount) + " · cajas " + String::num_int64(static_cast<int64_t>(d.boxes.size())) + " · build " + String::num(b, 1) + " · malla " + String::num(m, 1) + (cong ? " · congelado" : "")); } };
    Fin fin{tRc, tBuild, tMalla, d, logRc, b.congelado};
    // UN CONGELADO NO SE DIBUJA CON SU MALLA: la suya esta fundida en la del grupo de su celda. Aqui
    // se le rehacia `b.mesh` y se llamaba a `instance_set_transform` sobre una instancia que ya no
    // existe, asi que el jugador le daba, el trozo perdia voxels de verdad... y no se veia NADA.
    // Ensuciando el grupo, la malla comun se rehace en el frame siguiente y el agujero aparece.
    if (b.congelado) {
        b.xf = nt;
        ensuciarGrupo(b.grupo);
    } else if (b.inst.is_valid()) {
        rs->instance_set_transform(b.inst, nt);
        ponerTexBloque(b.inst, b.texOrg, 1.0f);
    }
    // (auditoria 2026-10-05: se probo añadir aqui las cajas con el cuerpo fuera del espacio, como en crearColisionFina.
    // ABAB a cohetazos: 25 us por caja antes y 27-34 despues, y en total 12-36 ms por partida: no daba nada y se quito.
    // fis_rc_total_ms / fis_rc_cajas siguen midiendolo.)
    vx::Timer trc;
    if (b.congelado) {
        // sigue siendo escenario: estatico, en su sitio nuevo, y con la colision que acaba de salir
        // LAS CAJAS CON EL CUERPO FUERA DEL ESPACIO (2026-10-11, bug: "dañar un pedazo gigante ya caido pausa el juego"):
        // dentro, Jolt rehacia la forma compuesta en CADA body_add_shape (un congelado lleva 100-800 cajas finas: 9-21 ms
        // por golpe con 120). Como en crearColisionFina: fuera se construye una vez al volver a meterlo. Es estatico: no
        // pierde velocidad ni nada. VX_CAJAS_DENTRO=1 = como antes.
        static const bool cajasDentroRc = std::getenv("VX_CAJAS_DENTRO") != nullptr;
        const RID espacio = ps->body_get_space(b.body);
        if (!cajasDentroRc && espacio.is_valid()) ps->body_set_space(b.body, RID());
        ps->body_clear_shapes(b.body);
        for (RID& sh : b.shapes) if (sh.is_valid()) ps->free_rid(sh);
        b.shapes.clear();
        for (const vx::Box& box : d.boxes) {
            RID sh = ps->box_shape_create();
            ps->shape_set_data(sh, toGd(box.halfExtents));
            ps->body_add_shape(b.body, sh, Transform3D(Basis(), toGd(box.center)));
            b.shapes.push_back(sh);
        }
        ps->body_set_mode(b.body, PhysicsServer3D::BODY_MODE_STATIC);
        ps->body_set_collision_layer(b.body, static_cast<uint32_t>(collisionLayer_));
        ps->body_set_collision_mask(b.body, MASCARA_ESCENARIO);
        ps->body_set_state(b.body, PhysicsServer3D::BODY_STATE_TRANSFORM, nt);
        if (!cajasDentroRc && espacio.is_valid()) ps->body_set_space(b.body, espacio);
        g_rcTotalMs += trc.ms();
        g_rcCajas += static_cast<int64_t>(d.boxes.size());
        return;   // ni masa, ni despertarlo, ni reiniciar su reloj de asiento: no se mueve
    }
    if (b.rigid) {
        // con muchas cajas (los casi quietos llevan la colision fina), fuera del espacio como el congelado; su velocidad se
        // guarda y se le devuelve (la sabemos por el callback: nunca se pregunta al servidor)
        static const bool cajasDentroRr = std::getenv("VX_CAJAS_DENTRO") != nullptr;
        const RID espacioR = ps->body_get_space(b.body);
        const bool fuera = !cajasDentroRr && espacioR.is_valid() && d.boxes.size() > 16;
        if (fuera) ps->body_set_space(b.body, RID());
        ps->body_clear_shapes(b.body);
        for (RID& sh : b.shapes) if (sh.is_valid()) ps->free_rid(sh);
        b.shapes.clear();
        for (const vx::Box& box : d.boxes) {
            RID sh = ps->box_shape_create();
            ps->shape_set_data(sh, toGd(box.halfExtents));
            ps->body_add_shape(b.body, sh, Transform3D(Basis(), toGd(box.center)));
            b.shapes.push_back(sh);
        }
        ps->body_set_param(b.body, PhysicsServer3D::BODY_PARAM_MASS, std::max(1.0f, d.mass));
        ps->body_set_state(b.body, PhysicsServer3D::BODY_STATE_TRANSFORM, nt);
        if (fuera) {
            ps->body_set_space(b.body, espacioR);
            ps->body_set_state(b.body, PhysicsServer3D::BODY_STATE_LINEAR_VELOCITY, b.linVel);
        }
        g_rcTotalMs += trc.ms();
        g_rcCajas += static_cast<int64_t>(d.boxes.size());
        ps->body_set_state(b.body, PhysicsServer3D::BODY_STATE_SLEEPING, false);
        b.xf = nt; b.sleeping = false;
        b.sleep = 0.f;
    } else b.pos = nt.origin;
}

/// Rehace los trozos tallados, como mucho `maxPorFrame` por fotograma. Con esto una rafaga sobre un
/// cascote cuesta UNA reconstruccion cada varios frames en vez de una por bala.
void VoxelWorld::reconstruirPendientes(int maxPorFrame) {
    int hechos = 0;
    // Los pedazos que se desgajen NO se pueden soltar dentro del bucle: `spawnPiece` mete en
    // `bodies_` y eso invalida la referencia con la que se esta trabajando.
    static thread_local std::vector<std::vector<vx::BodyVoxel>> sueltos;
    static thread_local std::vector<uint32_t> idsSueltos;
    sueltos.clear();
    idsSueltos.clear();
    // PRESUPUESTO DE TIEMPO ademas del de numero: rehacer un bloque grande (malla + cajas Jolt) son
    // 20-30 ms, y dos seguidos en el mismo cuadro llegaban a 65 ms (medido en Monaco con --bancofps).
    // Siempre se hace al menos uno; el segundo solo si el primero ha sido barato.
    recogerCuerposHechos();
    vx::Timer trec;
    for (Body& b : bodies_) {
        if (!b.reconstruir) continue;
        if (g_cjEnVuelo.count(b.data.id)) continue;   // se esta construyendo en el hilo: al volver (tirado) se rehace
        const size_t antes = sueltos.size();
        { vx::Timer tsp; separarPedazos(b, b.rigid ? b.xf : Transform3D(Basis(), b.pos), sueltos, idsSueltos);
          static const bool logSp = std::getenv("VX_LOG_RECONSTRUIR") != nullptr;
          if (logSp && tsp.ms() > 1.0) UtilityFunctions::print(String("[reconstruir] separar pedazos ") + String::num(tsp.ms(), 1) + " ms · rejilla " + String::num_int64(static_cast<int64_t>(b.data.sx) * b.data.sy * b.data.sz)); }
        // SI SE HA PARTIDO, LO QUE QUEDA TAMBIEN SE DESPIERTA. Un mazazo a un bloque grande dormido es un
        // "aranazo" (menos del 1 % de sus voxels) y no lo despierta; el corte de verdad se confiaba a este
        // camino. Pero aqui solo salia el PEDAZO cortado: el resto seguia estatico y `reconstruirCuerpo`
        // lo rehacia "sin despertarlo". Medido en partida (2026-09-21, --diagmesa): al tablero caido le
        // cortaron a mazo las dos patas de un lado, salieron como bloques y el tablero se quedo anclado
        // en el aire sobre las otras dos. Despierto, si sigue bien apoyado se vuelve a dormir enseguida.
        if (sueltos.size() > antes) despertarBloque(b);
        reconstruirCuerpo(b);
        if (++hechos >= maxPorFrame || (!loading_ && trec.ms() > 4.0)) break;
    }
    if (sueltos.empty()) return;
    static thread_local vx::BodyBuilder constructor;
    const float vs = engine_->world().voxelSize();
    for (size_t k = 0; k < sueltos.size(); ++k) {
        auto& v = sueltos[k];
        if (v.size() < 2) continue;
        vx::VoxelBody nb;
        constructor.build(v, vs, cajasMoviendose(static_cast<int>(v.size()), engine_->preset().maxBoxesPerBody), idsSueltos[k], nb);
        spawnPiece(std::move(nb));
    }
}

/// Talla EL TROZO QUE HAYA en `pos`, sea cual sea y tenga o no cuerpo en Jolt.
///
/// Lo usa el disparo replicado: la otra maquina no puede ir por el identificador (los trozos no
/// tienen uno en comun) ni volver a tirar el rayo (su copia esta unos centimetros movida, y ademas a
/// lo mejor ni la simula con fisica: si le cae lejos la tiene como cuerpo "barato", que el rayo de
/// Jolt no ve). Buscando por posicion se acierta siempre que haya algo ahi.
int VoxelWorld::carve_body_near(const Vector3& pos, float radius, int power) {
    if (engine_ == nullptr || bodies_.empty()) return 0;
    const float vs = engine_->world().voxelSize();
    int mejor = -1;
    // MARGEN ANCHO A PROPOSITO. La copia del trozo en la otra maquina esta donde la dejo SU fisica,
    // que no es exactamente donde la dejo la mia: pidiendo coincidencia fina, el golpe no encontraba
    // nada y el bloque se quedaba intacto en la pantalla del companero. Con metro y medio se acierta
    // al trozo aunque haya derivado, y el agujero cae unos centimetros corrido, que no se nota.
    float mejor_d = 1.8f;
    for (size_t i = 0; i < bodies_.size(); ++i) {
        const Body& b = bodies_[i];
        const Vector3 c = b.rigid ? b.xf.origin : b.pos;
        const float r = 0.5f * vs * static_cast<float>(std::max({b.data.sx, b.data.sy, b.data.sz}));
        const float d = std::max(0.0f, static_cast<float>(c.distance_to(pos)) - r);
        if (d < mejor_d) { mejor_d = d; mejor = static_cast<int>(i); }
    }
    if (mejor < 0) return 0;
    Body& b = bodies_[static_cast<size_t>(mejor)];
    bool destruido = false;
    // SIN ATENUACION, como quien dispara (carve_body): con ella las dos maquinas quitaban voxels distintos
    // con el mismo tiro
    const int n = carveBodyAt(b, pos, radius, power, false, destruido);
    if (n > 0) ++tallasCuerpo_;
    if (destruido) {
        ++removedCarve_;
        freeBody(b);
        bodies_[static_cast<size_t>(mejor)] = std::move(bodies_.back());
        bodies_.pop_back();
    }
    return n;
}


int VoxelWorld::carve_body(const RID& body, const Vector3& pos, float radius, int power) {
    if (!engine_) return 0;
    for (size_t i = 0; i < bodies_.size(); ++i) {
        if (bodies_[i].body != body) continue;
        ++tallasCuerpo_;
        bool destroyed = false;
        const int n = carveBodyAt(bodies_[i], pos, radius, power, false, destroyed);
        if (destroyed) { ++removedCarve_; freeBody(bodies_[i]); bodies_[i] = std::move(bodies_.back()); bodies_.pop_back(); }
        return n;
    }
    return 0;
}

int VoxelWorld::carve_beam(const Vector3& origin, const Vector3& dir, float length, float radius, int power, bool vaporize, const Vector3& empuje) {
    if (!engine_) return 0;
    int n = engine_->carveBeam(toVxV(origin), toVxV(dir), length, radius, power, vaporize, toVxV(empuje));
    // lo que se apoyaba en el trozo de muro que acabo de quitar tiene que enterarse
    if (n > 0) despertarSobre(origin + dir.normalized() * (length * 0.5f), radius + length * 0.5f);
    // El haz también corta las piezas desprendidas que atraviesa: si no, el láser abría un túnel en el
    // mundo pero el trozo de edificio que caía por delante quedaba intacto y flotando.
    const Vector3 d = dir.normalized();
    const float vs = engine_->world().voxelSize();
    for (size_t i = 0; i < bodies_.size();) {
        Body& b = bodies_[i];
        const Transform3D t = b.rigid ? b.xf : Transform3D(Basis(), b.pos);
        const float extent = 0.5f * vs * Vector3(static_cast<float>(b.data.sx), static_cast<float>(b.data.sy), static_cast<float>(b.data.sz)).length();
        const Vector3 rel = t.origin - origin;
        const float tc = rel.dot(d);
        if (tc < -extent || tc > length + extent || (rel - d * tc).length() > extent + radius) { ++i; continue; }
        const float t0 = std::max(0.f, tc - extent), t1 = std::min(length, tc + extent);
        bool destroyed = false;
        for (float sT = t0; sT <= t1 && !destroyed; sT += radius) n += carveBodyAt(b, origin + d * sT, radius, power, false, destroyed);
        if (destroyed) { freeBody(b); bodies_[i] = std::move(bodies_.back()); bodies_.pop_back(); continue; }
        ++i;
    }
    return n;
}

void VoxelWorld::set_prisa_escombros(float k) { prisaEscombros_ = std::clamp(k, 0.f, 1.f); }

int VoxelWorld::empujar_bloques(const Vector3& centro, float radio, const Vector3& vel) {
    PhysicsServer3D* ps = PhysicsServer3D::get_singleton();
    int n = 0;
    for (Body& b : bodies_) {
        if (b.congelado || b.anclado || b.alMundo) continue;
        const Vector3 p = b.rigid ? b.xf.origin : b.pos;
        if (p.distance_to(centro) > radio) continue;
        if (b.rigid && b.body.is_valid()) {
            // la velocidad que tiene la sabemos por el callback (nunca se pregunta al servidor: puede ir en su hilo)
            ps->body_set_state(b.body, PhysicsServer3D::BODY_STATE_LINEAR_VELOCITY, b.linVel + vel);
            ps->body_set_state(b.body, PhysicsServer3D::BODY_STATE_SLEEPING, false);
            b.resting = false;
            b.quieto = 0.f;
        } else {
            // los que caen "baratos" (sin Jolt): su deriva lateral y su velocidad vertical
            b.drift += Vector3(vel.x, 0.f, vel.z);
            b.vy += vel.y;
        }
        ++n;
    }
    return n;
}

// EL CRATER DE UN BLOQUE QUE CAE, EN EL INVITADO (2026-10-15, pedido: "que sea el mismo crater y el mismo daño estructural,
// sincronizado"): exactamente lo que hace el anfitrion al aterrizar el bloque (engine_->explode: la misma esfera, con la
// misma perdida de fuerza hacia el borde, y el mismo aviso al analizador), pero SIN el evento "blast" de explode(), que
// en el juego es la receta entera de explosion (fuego, humo, quemadura, empujon y daño).
int VoxelWorld::crater_mundo(const Vector3& pos, float radius, int power) {
    if (!engine_) return 0;
    return engine_->explode(toVxV(pos), radius, power);
}

int VoxelWorld::explode(const Vector3& pos, float radius, int power) {
    if (!engine_) return 0;
    vx::Timer tx;
    const int removed = engine_->explode(toVxV(pos), radius, power);
    tExplodeCore_ = static_cast<float>(tx.ms());
    // Toda explosión levanta polvo aunque no rompa nada (asfalto, hormigón intacto): el material
    // del evento es el de la superficie más cercana bajo el punto.
    {
        vx::RayHit h;
        int mat = 0;
        if (engine_->world().raycast(toVxV(pos), vx::Vec3(0, -1, 0), radius + 1.0f, h)) mat = h.mat;
        pushEffect("blast", pos, radius, mat);
    }
    PhysicsServer3D* ps = PhysicsServer3D::get_singleton();
    const float vs = engine_->world().voxelSize();
    // Tallar los cuerpos desprendidos alcanzados por la explosión
    for (size_t i = 0; i < bodies_.size();) {
        Body& b = bodies_[i];
        const Vector3 bp = b.rigid ? b.xf.origin : b.pos;
        const float extent = 0.5f * vs * Vector3(static_cast<float>(b.data.sx), static_cast<float>(b.data.sy), static_cast<float>(b.data.sz)).length();
        if (bp.distance_to(pos) - extent < radius) {
            bool destroyed = false;
            carveBodyAt(b, pos, radius, power, true, destroyed);
            if (destroyed) { freeBody(b); bodies_[i] = std::move(bodies_.back()); bodies_.pop_back(); continue; }
        }
        ++i;
    }
    // Impulso a los cuerpos rígidos cercanos (Jolt)
    const float reach = radius * 2.5f;
    for (Body& b : bodies_) {
        if (!b.rigid) continue;
        const Transform3D t = b.xf;
        const float d = t.origin.distance_to(pos);
        if (d > reach) continue;
        Vector3 dir = t.origin - pos;
        dir = dir.length() > 0.01f ? dir.normalized() : Vector3(0, 1, 0);
        const float k = 1.0f - d / reach;
        if (b.anclado) {                      // estaba anclado: una explosion sí lo despega
            ps->body_set_mode(b.body, PhysicsServer3D::BODY_MODE_RIGID);
            b.anclado = false;
            // ...y si estaba CONGELADO con su postura, vuelve a la vida: se le reinician los relojes
            // del asiento, o se volveria a congelar en el aire en el frame siguiente.
            if (b.congelado) { b.congelado = false; b.resting = false; b.quieto = 0.f; b.age = 0.f; sacarDelGrupo(b); }
        }
        ps->body_apply_central_impulse(b.body, (dir + Vector3(0, 0.6f, 0)) * (k * power * 0.04f * std::max(1.0f, b.data.mass)));
        b.sleep = 0;
    }
    // LAS MALLAS COMUNES SE REHACEN AQUI MISMO, no en el frame siguiente. Una explosion despierta
    // bloques y a cada uno se le devuelve su dibujo propio, pero la malla comun TODAVIA lo contiene:
    // hasta que se rehiciera, el bloque se dibujaba dos veces en el mismo sitio y eso tiembla
    // (z-fighting). Como el drenaje normal es de un grupo por frame, el tembleque podia durar varios.
    // Una explosion ya es cara y no pasa a menudo: se paga aqui y se acaba. El tope evita que una
    // cadena de derrumbes convierta esto en un paron.
    for (int k = 0; k < 16; ++k) {
        bool queda = false;
        for (const auto& kv : gruposCongelados_) if (kv.second.sucio) { queda = true; break; }
        if (!queda) break;
        rehacerUnGrupo();
    }
    despertarSobre(pos, radius);
    tExplodeTotal_ = static_cast<float>(tx.ms());
    return removed;
}

// Rayo contra un cuerpo "barato" (cinemático, sin forma Jolt: base identidad en b.pos). Devuelve la distancia al
// primer voxel sólido o -1. Sin esto las balas atravesaban paredes desprendidas que aún se veían en su sitio.
float VoxelWorld::rayCheapBody(const Body& b, const Vector3& origin, const Vector3& dir, float maxDist, Vector3& outPos, int& outMat) const {
    const float vs = engine_->world().voxelSize();
    const vx::VoxelBody& d = b.data;
    const Vector3 mn = b.pos - toGd(d.com);
    const Vector3 mx = mn + Vector3(d.sx * vs, d.sy * vs, d.sz * vs);
    // slab test
    float t0 = 0.f, t1 = maxDist;
    for (int a = 0; a < 3; ++a) {
        if (std::abs(dir[a]) < 1e-6f) { if (origin[a] < mn[a] || origin[a] > mx[a]) return -1.f; continue; }
        float ta = (mn[a] - origin[a]) / dir[a], tb = (mx[a] - origin[a]) / dir[a];
        if (ta > tb) std::swap(ta, tb);
        t0 = std::max(t0, ta); t1 = std::min(t1, tb);
        if (t0 > t1) return -1.f;
    }
    // marcha por la rejilla del cuerpo (paso = medio voxel)
    const float step = vs * 0.5f;
    for (float t = t0 + step * 0.5f; t <= t1; t += step) {
        const Vector3 p = origin + dir * t;
        const int x = static_cast<int>((p.x - mn.x) / vs), y = static_cast<int>((p.y - mn.y) / vs), z = static_cast<int>((p.z - mn.z) / vs);
        if (x < 0 || y < 0 || z < 0 || x >= d.sx || y >= d.sy || z >= d.sz) continue;
        const uint8_t m = d.at(x, y, z);
        if (m) { outPos = p; outMat = m; return t; }
    }
    return -1.f;
}

/// Rayo contra UN trozo cualquiera, girado incluido: el rayo se pasa al marco del trozo y se marcha por
/// su rejilla. `rayCheapBody` solo valia para los baratos, que van sin girar.
float VoxelWorld::rayCuerpo(const Body& b, const Vector3& origin, const Vector3& dir, float maxDist, Vector3& outPos) const {
    const Transform3D t = b.rigid ? b.xf : Transform3D(Basis(), b.pos);
    if (!b.rigid) { int m; return rayCheapBody(b, origin, dir, maxDist, outPos, m); }
    // DESCARTE POR ESFERA (2026-10-01): la rejilla del bloque cabe entera en la esfera de su media diagonal; si el
    // tramo del rayo no pasa por ella, no puede tocarlo. Ahorra invertir la transformada de cada bloque del mapa en
    // cada rayo (los bots tiran uno por tick para buscar el suelo, y en un mapa destruido hay cientos de bloques).
    // Mismo resultado: solo se saltan los que no podian dar.
    {
        const float vs0 = engine_->world().voxelSize();
        const vx::VoxelBody& d0 = b.data;
        const Vector3 medio(d0.sx * vs0 * 0.5f, d0.sy * vs0 * 0.5f, d0.sz * vs0 * 0.5f);
        const Vector3 c = t.xform(medio - toGd(d0.com));
        const float r = medio.length() + vs0;
        const float dl = dir.length();
        static const bool sinEsfera = std::getenv("VX_SIN_ESFERA") != nullptr;   // A/B del banco
        if (dl > 1e-6f && !sinEsfera) {
            const Vector3 u = dir / dl;
            const float s = std::clamp((c - origin).dot(u), 0.f, maxDist * dl);
            if ((origin + u * s).distance_squared_to(c) > r * r) return -1.f;
        }
    }
    const Transform3D inv = t.affine_inverse();
    const Vector3 o = inv.xform(origin) + toGd(b.data.com);
    const Vector3 d = inv.basis.xform(dir);
    const float vs = engine_->world().voxelSize();
    const vx::VoxelBody& dat = b.data;
    float t0 = 0.f, t1 = maxDist;
    const Vector3 mx(dat.sx * vs, dat.sy * vs, dat.sz * vs);
    for (int a = 0; a < 3; ++a) {
        if (std::abs(d[a]) < 1e-6f) { if (o[a] < 0.f || o[a] > mx[a]) return -1.f; continue; }
        float ta = (0.f - o[a]) / d[a], tb = (mx[a] - o[a]) / d[a];
        if (ta > tb) std::swap(ta, tb);
        t0 = std::max(t0, ta); t1 = std::min(t1, tb);
        if (t0 > t1) return -1.f;
    }
    const float step = vs * 0.5f;
    for (float s = std::max(0.f, t0) + step * 0.5f; s <= t1; s += step) {
        const Vector3 p = o + d * s;
        const int x = static_cast<int>(p.x / vs), y = static_cast<int>(p.y / vs), z = static_cast<int>(p.z / vs);
        if (x < 0 || y < 0 || z < 0 || x >= dat.sx || y >= dat.sy || z >= dat.sz) continue;
        if (dat.at(x, y, z)) { outPos = origin + dir * s; return s; }
    }
    return -1.f;
}

/// Como `raycast`, pero MIRANDO TAMBIEN LOS TROZOS QUE CAEN. Los bots no usan la fisica de Jolt: andan
/// sobre la rejilla de voxels, y un trozo desprendido ha dejado de ser voxel. Por eso un bot subido a
/// una estructura se caia al vacio en cuanto la estructura se convertia en escombro: para el, debajo ya
/// no habia nada. Con esto el suelo que pisa incluye lo que esta cayendo.
Dictionary VoxelWorld::raycast_con_piezas(const Vector3& origin, const Vector3& dir, float max_dist) {
    Dictionary r = raycast(origin, dir, max_dist);
    if (!engine_) return r;
    float best = static_cast<bool>(r.get("hit", false)) ? static_cast<float>(r["distance"]) : max_dist;
    Vector3 bestP; bool found = false;
    // QUIEN es el bloque que se toca, no solo que se toca uno: sin esto, delante de un trozo que se
    // atraviesa no habia forma de saber si era una esquirla (que va sin colision a proposito) o medio
    // tronco (que seria un fallo).
    int64_t bestId = 0; int64_t bestVox = 0; bool bestSolido = false; bool bestCuerpo = false;
    for (const Body& b : bodies_) {
        Vector3 p;
        const float t = rayCuerpo(b, origin, dir.normalized(), best, p);
        if (t >= 0.f && t < best) {
            best = t; bestP = p; found = true;
            bestId = static_cast<int64_t>(b.data.id);
            bestVox = static_cast<int64_t>(b.data.voxelCount);
            bestSolido = b.solid;
            bestCuerpo = b.body.is_valid();
        }
    }
    if (found) {
        r["hit"] = true;
        r["position"] = bestP;
        r["normal"] = -dir.normalized();
        r["distance"] = best;
        r["pieza"] = true;
        r["pieza_id"] = bestId;
        r["pieza_vox"] = bestVox;
        r["pieza_solida"] = bestSolido;
        r["pieza_con_cuerpo"] = bestCuerpo;
    }
    return r;
}

// El suelo de los bots (BotMotor.mover): las MISMAS cuentas que raycast_con_piezas con dir = abajo (el rayo del mundo y
// luego cada bloque, quedandose con el mas cercano), pero sin montar los dos diccionarios, que era lo que mas costaba.
bool VoxelWorld::suelo_con_piezas(const Vector3& origin, float max_dist, Vector3& pos) const {
    if (!engine_) return false;
    const Vector3 dir(0, -1, 0);
    vx::RayHit hit;
    const bool mundo = engine_->world().raycast(toVxV(origin), toVxV(dir), max_dist, hit);
    float best = mundo ? hit.dist : max_dist;
    bool found = false;
    Vector3 bestP;
    for (const Body& b : bodies_) {
        Vector3 p;
        const float t = rayCuerpo(b, origin, dir.normalized(), best, p);
        if (t >= 0.f && t < best) { best = t; bestP = p; found = true; }
    }
    if (found) { pos = bestP; return true; }
    if (mundo) { pos = toGd(hit.pos); return true; }
    return false;
}

Dictionary VoxelWorld::shoot(const Vector3& origin, const Vector3& dir, float max_dist, int power) {
    Dictionary r;
    r["hit"] = false;
    if (!engine_) return r;
    // 1) ¿hay un cuerpo barato antes que el mundo? (los rígidos los detecta el juego con el rayo de Jolt)
    vx::RayHit wh;
    const bool wok = engine_->world().raycast(toVxV(origin), toVxV(dir), max_dist, wh);
    const float wdist = wok ? wh.dist : max_dist;
    int bestI = -1; float bestT = wdist; Vector3 bestP; int bestM = 0;
    // EN LAN EL DISPARO NO MIRA LOS ESCOMBROS SUELTOS. Los cascotes pequeños (los que no llevan
    // cuerpo en Jolt) no estan sincronizados: caen por fisica y cada maquina los tiene en un sitio.
    // Si dejamos que paren la bala, el mismo disparo replicado talla la pared en una maquina y en la
    // otra no, y el mapa se separa. Medido: 387 voxels de diferencia en una rafaga de 12 tiros.
    // Jugando en red la bala va SIEMPRE contra el mundo, que es identico en todas partes; lo que le
    // pase al cascote es cosa de cada pantalla y, de todas formas, donde acaba lo manda el anfitrion.
    for (size_t i = 0; i < bodies_.size(); ++i) {
        const Body& b = bodies_[i];
        if (b.body.is_valid()) continue;   // tiene cuerpo en Jolt: lo resuelve el rayo del juego
        Vector3 p; int m;
        const float t = rayCheapBody(b, origin, dir, bestT, p, m);
        if (t >= 0.f && t < bestT) { bestT = t; bestI = static_cast<int>(i); bestP = p; bestM = m; }
    }
    if (bestI >= 0) {
        Body& b = bodies_[static_cast<size_t>(bestI)];
        bool destroyed = false;
        const int removed = carveBodyAt(b, bestP, 0.3f, power % 1000, true, destroyed);   // (la escopeta lleva +1000)
        if (destroyed) { ++removedCarve_; freeBody(b); bodies_[static_cast<size_t>(bestI)] = std::move(bodies_.back()); bodies_.pop_back(); }
        ++tallasCuerpo_;
        // EN RED EL CASCOTE SE TALLA PERO NO PARA LA BALA. Los cascotes pequeños no van
        // sincronizados: si uno para el tiro, el mismo disparo talla la pared en una maquina y en la
        // otra no. Asi se ve romperse el cascote en las dos Y el mundo recibe el mismo tiro en todas.
        if (enRed_) {
            vx::RayHit hw;
            const bool okw = engine_->shoot(toVxV(origin), toVxV(dir), max_dist, power, hw);
            r["hit"] = true;
            r["position"] = okw ? toGd(hw.pos) : bestP;
            r["normal"] = -dir;
            r["material"] = okw ? static_cast<int>(hw.mat) : bestM;
            r["distance"] = okw ? hw.dist : bestT;
            r["voxel"] = okw ? Vector3i(hw.voxel.x, hw.voxel.y, hw.voxel.z) : Vector3i();
            r["removed"] = removed + (okw ? engine_->lastShotRemoved() : 0);
            return r;
        }
        r["hit"] = true;
        r["position"] = bestP;
        r["normal"] = -dir;
        r["material"] = bestM;
        r["distance"] = bestT;
        r["voxel"] = Vector3i();
        r["removed"] = removed;
        return r;
    }
    vx::RayHit hit;
    const bool ok = engine_->shoot(toVxV(origin), toVxV(dir), max_dist, power, hit);
    r["hit"] = ok;
    if (ok) {
        r["position"] = toGd(hit.pos);
        r["normal"] = Vector3(static_cast<float>(hit.normal.x), static_cast<float>(hit.normal.y), static_cast<float>(hit.normal.z));
        r["material"] = static_cast<int>(hit.mat);
        r["distance"] = hit.dist;
        r["voxel"] = Vector3i(hit.voxel.x, hit.voxel.y, hit.voxel.z);
        r["removed"] = engine_->lastShotRemoved();
        // una bala tambien puede estar serrando el apoyo de algo que duerme encima
        if (engine_->lastShotRemoved() > 0) despertarSobre(toGd(hit.pos), 0.6f);
    }
    return r;
}

// EL MAPA DE TECHOS POR FILAS (2026-10-10): lo mismo que main._techo_filas (un rayo hacia abajo por casilla, la altura
// de lo primero que toca, a bytes de 0..255 sobre `altura`), sin un Dictionary por casilla. Tras cada explosion eran
// cientos de rayos en GDScript (techo.cola, 0,6-0,8 ms por fotograma a cohetazos).
PackedByteArray VoxelWorld::techo_filas(PackedByteArray datos, int tam, int x0, int x1, int za, int zb, float px, float pz, float desde, float altura) const {
    if (!engine_ || tam <= 0 || datos.size() < static_cast<int64_t>(tam) * tam) return datos;
    uint8_t* d = datos.ptrw();
    const vx::World& w = engine_->world();
    for (int zz = std::max(za, 0); zz < std::min(zb, tam); ++zz) {
        for (int xx = std::max(x0, 0); xx <= std::min(x1, tam - 1); ++xx) {
            vx::RayHit hit;
            float h = 0.0f;
            if (w.raycast(vx::Vec3((xx + 0.5f) * px, desde, (zz + 0.5f) * pz), vx::Vec3(0, -1, 0), desde + 2.0f, hit)) h = hit.pos.y;
            const float k = std::clamp(h / altura, 0.0f, 1.0f) * 255.0f;
            d[zz * tam + xx] = static_cast<uint8_t>(static_cast<int>(k));
        }
    }
    return datos;
}

Dictionary VoxelWorld::raycast(const Vector3& origin, const Vector3& dir, float max_dist) const {
    Dictionary r;
    r["hit"] = false;
    if (!engine_) return r;
    vx::RayHit hit;
    if (engine_->world().raycast(toVxV(origin), toVxV(dir), max_dist, hit)) {
        r["hit"] = true;
        r["position"] = toGd(hit.pos);
        r["normal"] = Vector3(static_cast<float>(hit.normal.x), static_cast<float>(hit.normal.y), static_cast<float>(hit.normal.z));
        r["material"] = static_cast<int>(hit.mat);
        r["distance"] = hit.dist;
    }
    return r;
}

PackedVector3Array VoxelWorld::find_path(const Vector3& from, const Vector3& to, int max_expansions) {
    PackedVector3Array out;
    if (!engine_) return out;
    std::vector<vx::Vec3> path;
    engine_->findPath(toVxV(from), toVxV(to), path, max_expansions);
    out.resize(static_cast<int64_t>(path.size()));
    Vector3* p = out.ptrw();
    for (size_t i = 0; i < path.size(); ++i) p[i] = toGd(path[i]);
    return out;
}

bool VoxelWorld::has_line_of_sight(const Vector3& a, const Vector3& b) const {
    return engine_ ? engine_->lineOfSight(toVxV(a), toVxV(b)) : false;
}

// ---------------------------------------------------------------------------
// Consultas
// ---------------------------------------------------------------------------
void VoxelWorld::set_clump_scale(float s) { if (engine_) engine_->setClumpScale(s); }
float VoxelWorld::get_clump_scale() const { return engine_ ? engine_->clumpScale() : 1.0f; }

/// Cuantos voxels solidos tiene cada chunk, por su posicion. Es la huella del mapa: comparando dos
/// maquinas chunk a chunk se ve DONDE difieren, no solo cuanto, que es lo que hace falta para poder
/// decir un porcentaje de coincidencia con sentido.
Array VoxelWorld::resumen_chunks() const {
    Array out;
    if (engine_ == nullptr) return out;
    const int n = engine_->world().numChunkSlots();
    for (int i = 0; i < n; ++i) {
        const vx::Chunk* c = engine_->world().chunkAt(i);
        if (c == nullptr) continue;
        const int solidos = static_cast<int>(c->solidAtomic.load(std::memory_order_relaxed));
        if (solidos == 0) continue;
        PackedInt32Array fila;
        fila.push_back(c->cx); fila.push_back(c->cy); fila.push_back(c->cz); fila.push_back(solidos);
        out.push_back(fila);
    }
    return out;
}


/// QUE ES ESTE CUERPO QUE HE TOCADO. Lo pregunta el juego al golpear o disparar: un trozo CONGELADO
/// ya no es un cascote volando, es escenario, y tiene que costar lo mismo romperlo que a la pared de
/// la que salio. Sin esto, `player.gd` metia cualquier cuerpo por la rama del cascote y lo tallaba a
/// potencia 255: un muro caido se deshacia de UN mazazo.
Dictionary VoxelWorld::info_cuerpo(const RID& rid) const {
    Dictionary d;
    for (const Body& b : bodies_) {
        if (b.body != rid) continue;
        d["existe"] = true;
        d["congelado"] = b.congelado;
        // UNA PIEZA PARADA YA ES ESCENARIO, aunque todavia no se haya congelado. Entre que se para y
        // que se congela pasan varios segundos (`sleepRevoxelSeconds`), y en esa ventana el mazo la
        // rompia de un golpe porque para el juego seguia siendo un cascote volando.
        d["anclado"] = b.anclado;
        d["parado"] = b.congelado || b.anclado || b.resting;
        d["material"] = static_cast<int>(b.data.dominantMat);
        d["voxels"] = static_cast<int>(b.data.voxelCount);
        d["id"] = static_cast<int64_t>(b.data.id);
        return d;
    }
    d["existe"] = false;
    return d;
}

Array VoxelWorld::get_bodies_debug() const {
    Array out;
    for (const Body& b : bodies_) {
        Dictionary d;
        d["pos"] = b.rigid ? b.xf.origin : b.pos;
        d["id"] = static_cast<int64_t>(b.data.id);       // hash del primer voxel: igual en todas las maquinas
        d["voxels"] = static_cast<int64_t>(b.data.voxelCount);
        d["rigid"] = b.rigid;
        d["solid"] = b.solid;
        d["rid"] = b.body;
        d["voxels"] = static_cast<int>(b.data.voxelCount);
        d["size"] = Vector3(static_cast<float>(b.data.sx), static_cast<float>(b.data.sy), static_cast<float>(b.data.sz));
        out.push_back(d);
    }
    return out;
}

void VoxelWorld::set_compress_attributes(bool on) { g_compressAttrs = on; }

// AUDITORIA DE FLOTADORES sobre el mapa REAL (10 cm en PC): cada conjunto que no toca un ancla, con sus
// voxels y su centro (media de los centros de sus chunks). Es exactamente lo que se cae en cuanto se dana
// algo cerca, asi que vale para encontrar lo que el generador dejo sin pegar.
Array VoxelWorld::audit_floaters() {
    Array out;
    if (!engine_) return out;
    std::vector<vx::DetachedGroup> groups;
    engine_->auditFloaters(groups);
    const vx::World& world = engine_->world();
    const float cs = vx::CHUNK_SIZE * world.voxelSize();
    std::sort(groups.begin(), groups.end(), [](const vx::DetachedGroup& a, const vx::DetachedGroup& b) { return a.voxelCount > b.voxelCount; });
    for (const vx::DetachedGroup& g : groups) {
        Vector3 c;
        int n = 0;
        for (const vx::DetachedNode& nd : g.nodes) {
            const vx::Chunk* ch = world.chunkAt(static_cast<int>(nd.chunkIdx));
            if (!ch) continue;
            c += toGd(world.chunkOrigin(*ch)) + Vector3(cs, cs, cs) * 0.5f;
            ++n;
        }
        if (n > 0) c /= static_cast<float>(n);
        Dictionary d;
        d["voxels"] = static_cast<int64_t>(g.voxelCount);
        d["chunks"] = n;
        d["centro"] = c;
        out.push_back(d);
    }
    return out;
}

/// ¿ESTA ESTE PUNTO DENTRO DE UN BLOQUE PARADO? Para que el escombro (particulas del nucleo) aterrice sobre
/// los bloques caidos en vez de atravesarlos. Descarte por envolvente y luego el voxel exacto del bloque.
///
/// CON REJILLA (2026-10-02, medido en la cafeteria con los bots a cohetazos, --motorcada10): cada particula lo pregunta
/// tres veces por cuadro (una por eje) y aqui se recorrian TODOS los bloques: 512 particulas x 3 x 300-400 bloques eran
/// 2-5 ms por cuadro, casi todo el `update` del motor demoliendo. Ahora, una vez por cuadro, cada bloque parado se apunta
/// en las celdas de 2 m que toca su esfera (los enormes van aparte y se miran siempre) y la pregunta solo mira los de su
/// celda. Mismo resultado: la prueba exacta (esfera y voxel) es la de siempre.
namespace {
struct RejillaParados {
    const void* dueno = nullptr;
    uint64_t cuadro = ~0ull;
    size_t nCuerpos = 0;
    std::vector<std::pair<uint64_t, int>> celdas;   // (celda, indice del cuerpo), ordenado por celda
    std::vector<int> grandes;                       // los que tocan demasiadas celdas: se miran siempre
};
RejillaParados g_parados;
constexpr float CELDA_PARADOS = 2.0f;
constexpr int MAX_CELDAS_CUERPO = 64;
inline uint64_t clavePar(int x, int y, int z) {
    return (static_cast<uint64_t>(static_cast<uint32_t>(x + (1 << 20)) & 0x1FFFFF) << 42)
         | (static_cast<uint64_t>(static_cast<uint32_t>(y + (1 << 20)) & 0x1FFFFF) << 21)
         | (static_cast<uint64_t>(static_cast<uint32_t>(z + (1 << 20)) & 0x1FFFFF));
}
}

bool VoxelWorld::puntoEnBloqueParado(const vx::Vec3& p) const {
    const float vs = engine_->world().voxelSize();
    const Vector3 q(p.x, p.y, p.z);
    auto prueba = [&](const Body& o) -> bool {
        if (!o.congelado && !o.anclado && !o.resting) return false;
        const Vector3 c = o.rigid ? o.xf.origin : o.pos;
        const float radio = 0.5f * vs * Vector3(static_cast<float>(o.data.sx), static_cast<float>(o.data.sy), static_cast<float>(o.data.sz)).length();
        if (c.distance_squared_to(q) > radio * radio) return false;
        const Transform3D ot = o.rigid ? o.xf : Transform3D(Basis(), o.pos);
        const Vector3 loc = ot.affine_inverse().xform(q) + toGd(o.data.com);
        const int lx = static_cast<int>(std::floor(loc.x / vs)), ly = static_cast<int>(std::floor(loc.y / vs)), lz = static_cast<int>(std::floor(loc.z / vs));
        if (lx < 0 || ly < 0 || lz < 0 || lx >= o.data.sx || ly >= o.data.sy || lz >= o.data.sz) return false;
        return o.data.vox[static_cast<size_t>(lx + ly * o.data.sx + lz * o.data.sx * o.data.sy)] != 0;
    };
    static const bool sinRejilla = std::getenv("VX_SIN_REJILLA_PARADOS") != nullptr;   // A/B: como antes
    if (sinRejilla) {
        for (const Body& o : bodies_) if (prueba(o)) return true;
        return false;
    }
    RejillaParados& rj = g_parados;
    if (rj.dueno != this || rj.cuadro != static_cast<uint64_t>(frame_) || rj.nCuerpos != bodies_.size()) {
        rj.dueno = this; rj.cuadro = static_cast<uint64_t>(frame_); rj.nCuerpos = bodies_.size();
        rj.celdas.clear(); rj.grandes.clear();
        for (int i = 0; i < static_cast<int>(bodies_.size()); ++i) {
            const Body& o = bodies_[i];
            if (!o.congelado && !o.anclado && !o.resting) continue;
            const Vector3 c = o.rigid ? o.xf.origin : o.pos;
            const float radio = 0.5f * vs * Vector3(static_cast<float>(o.data.sx), static_cast<float>(o.data.sy), static_cast<float>(o.data.sz)).length();
            const int x0 = static_cast<int>(std::floor((c.x - radio) / CELDA_PARADOS)), x1 = static_cast<int>(std::floor((c.x + radio) / CELDA_PARADOS));
            const int y0 = static_cast<int>(std::floor((c.y - radio) / CELDA_PARADOS)), y1 = static_cast<int>(std::floor((c.y + radio) / CELDA_PARADOS));
            const int z0 = static_cast<int>(std::floor((c.z - radio) / CELDA_PARADOS)), z1 = static_cast<int>(std::floor((c.z + radio) / CELDA_PARADOS));
            if ((x1 - x0 + 1) * (y1 - y0 + 1) * (z1 - z0 + 1) > MAX_CELDAS_CUERPO) { rj.grandes.push_back(i); continue; }
            for (int z = z0; z <= z1; ++z) for (int y = y0; y <= y1; ++y) for (int x = x0; x <= x1; ++x)
                rj.celdas.emplace_back(clavePar(x, y, z), i);
        }
        std::sort(rj.celdas.begin(), rj.celdas.end());
    }
    for (int i : rj.grandes) if (i < static_cast<int>(bodies_.size()) && prueba(bodies_[i])) return true;
    const uint64_t k = clavePar(static_cast<int>(std::floor(q.x / CELDA_PARADOS)), static_cast<int>(std::floor(q.y / CELDA_PARADOS)),
                                static_cast<int>(std::floor(q.z / CELDA_PARADOS)));
    auto it = std::lower_bound(rj.celdas.begin(), rj.celdas.end(), std::make_pair(k, -1));
    for (; it != rj.celdas.end() && it->first == k; ++it)
        if (it->second < static_cast<int>(bodies_.size()) && prueba(bodies_[it->second])) return true;
    return false;
}

Array VoxelWorld::bodies_info() {
    Array out;
    for (const Body& b : bodies_) {
        Dictionary d;
        d["voxels"] = static_cast<int64_t>(b.data.voxelCount);
        d["pos"] = b.rigid ? b.xf.origin : b.pos;
        d["congelado"] = b.congelado; d["anclado"] = b.anclado; d["rigido"] = b.rigid; d["solido"] = b.solid;
        d["vel"] = b.linVel.length();
        out.push_back(d);
    }
    return out;
}

void VoxelWorld::set_faldas_lod(bool on) { if (engine_) engine_->setFaldasLod(on); }

void VoxelWorld::set_sol_horneado(bool on, const Vector3& dir_hacia_sol, float alcance_m) {
    if (!engine_) return;
    // el motor reencola el remallado de todos los chunks (Engine::setSolHorneado); al subir cada uno,
    // uploadChunk() ya ensucia el bloque fusionado que lo contiene (mesa, coches...), asi que no hace
    // falta tocar nada mas aqui.
    engine_->setSolHorneado(on, vx::Vec3(dir_hacia_sol.x, dir_hacia_sol.y, dir_hacia_sol.z), alcance_m);
}

void VoxelWorld::set_shadow_light_dir(const Vector3& d) {
    const Vector3 n = d.length_squared() > 1e-6f ? d.normalized() : Vector3();
    if (n.distance_to(shadowLightDir_) < 1e-3f) return;
    shadowLightDir_ = n;
    // los casters ya hechos estan recortados para otra luz: los que proyectan ahora se rehacen ya (pocos:
    // los cercanos; esto pasa bajo la pantalla de carga o al poner la noche), el resto cuando les toque
    for (int r = 0; r < static_cast<int>(regions_.size()); ++r) {
        RegionVis& rg = regions_[r];
        if (!rg.shMesh.is_valid() && !rg.shInst.is_valid()) continue;
        if (regionCastsShadows(rg.state)) rebuildShadowCaster(r); else rg.casterStale = true;
    }
}

Dictionary VoxelWorld::get_stats() const {
    Dictionary d;
    if (!engine_) return d;
    const vx::Stats& s = engine_->stats();
    d["quality"] = String(engine_->preset().name);
    d["loading"] = loading_;
    // la oclusion por rayos (oclusionRayos)
    d["ocl_rayos"] = g_oclRayos;
    d["ocl_bloques_ocultos"] = g_oclBloqOcultos;
    d["ocl_regiones_ocultas"] = g_oclRegOcultas;
    d["ocl_tris_ocultos"] = static_cast<int64_t>(g_oclTrisOcultos);
    d["ocl_ms"] = g_oclMs;
    d["chunks"] = s.chunksAllocated;
    d["chunks_visible"] = visibleChunks_;   // bloques 2x2x2 visibles
    d["blocks_dirty"] = static_cast<int>(dirtyBlocks_.size());
    d["static_bodies"] = staticBodies_;
    d["sync_sueltas_out"] = static_cast<int64_t>(sueltasOut_);
    d["sync_sueltas_in"] = static_cast<int64_t>(sueltasIn_);
    d["sync_celdas_sueltas_out"] = static_cast<int64_t>(celdasSueltasOut_);
    d["sync_celdas_solidas"] = static_cast<int64_t>(celdasSueltasSolidas_);
    d["sync_celdas_sueltas_in"] = static_cast<int64_t>(celdasSueltasIn_);
    d["sync_celdas_ya_aire"] = static_cast<int64_t>(celdasSueltasYaAire_);
    d["sync_tallas_cuerpo"] = static_cast<int64_t>(tallasCuerpo_);
    d["sync_asientos_out"] = static_cast<int64_t>(asientosOut_);
    d["sync_celdas_asiento_out"] = static_cast<int64_t>(celdasAsientoOut_);
    d["sync_celdas_asiento_in"] = static_cast<int64_t>(celdasAsientoIn_);
    d["sync_celdas_asiento_salt"] = static_cast<int64_t>(celdasAsientoSalt_);
    d["phys_queue"] = static_cast<int>(physQueue_.size());
    d["regions_visible"] = visibleRegions_;
    d["regions_dirty"] = static_cast<int>(dirtyRegions_.size());
    {   // las mallas de bloque que estan en el hilo o esperando su cambio (asyncBlocks_): lo que aun no se ve
        std::lock_guard<std::mutex> lk(const_cast<std::mutex&>(blockMx_));
        d["bloques_en_vuelo"] = static_cast<int>(blockIn_.size() + blockOut_.size() + blockSwap_.size());
    }
    d["lod_distance"] = lodNear_;
    // LOS TOTALES DE TRIANGULOS, EN CACHE. Sumarlos recorre TODOS los huecos de chunk (en la isla son
    // 104x12x104 = 129.792) y todas las regiones, y esto se llama varias veces por segundo solo para pintar
    // el panel de estadisticas: medido en la isla, 16 ms por llamada (4 ms por cuadro de media, el tercer
    // coste del juego). Se recalcula como mucho cuatro veces por segundo, que para un panel sobra.
    if (frame_ - statsFrame_ >= 15 || statsFrame_ == 0) {
        statsFrame_ = frame_;
        long long ot = 0; int on = 0;
        for (const RegionVis& rg : regions_) if (rg.occTris) { ot += rg.occTris; ++on; }
        long long tt = 0; for (const ChunkVis& c : chunks_) tt += c.tris;
        long long sht = 0; for (const RegionVis& rg : regions_) if (rg.shInst.is_valid() && regionCastsShadows(rg.state)) sht += rg.shTris;
        statsTrisTotal_ = tt;
        statsShadowTris_ = sht;
        statsOccluders_ = on;
        statsOccluderTris_ = ot;
    }
    d["tris_total"] = static_cast<int64_t>(statsTrisTotal_);
    d["shadow_tris"] = static_cast<int64_t>(statsShadowTris_);
    d["occluders"] = statsOccluders_;
    d["occluder_tris"] = static_cast<int64_t>(statsOccluderTris_);
    d["render_distance"] = renderDist_;
    d["tris_visible"] = static_cast<int64_t>(visibleTris_);
    d["voxels_solid"] = static_cast<int64_t>(s.voxelsSolid);
    d["voxels_destroyed"] = static_cast<int64_t>(s.voxelsDestroyed);
    d["mem_world_mb"] = static_cast<double>(s.memWorldBytes) / 1048576.0;
    // LO QUE SE GUARDA EN CPU DE CADA CHUNK (2026-10-01): las mallas completa, LOD1, LOD2, oclusor y de colision, por
    // capacidad reservada (lo que ocupa de verdad en memoria, no solo lo usado)
    {
        auto bytesDe = [](const std::vector<vx::MeshData>& v) -> double {
            double t = 0.0;
            for (const vx::MeshData& m : v)
                t += static_cast<double>(m.verts.capacity()) * sizeof(vx::MeshVertex)
                   + static_cast<double>(m.idxOpaque.capacity() + m.idxGlass.capacity()) * sizeof(uint32_t);
            return t / 1048576.0;
        };
        d["mem_malla_full_mb"] = bytesDe(chunkFull_);
        // EN LA GPU: triangulos subidos por tipo (bloques de cerca, LOD1, LOD2 y las mallas de sombra de las regiones)
        int64_t tB = 0, t1 = 0, t2 = 0, tS = 0, nS = 0, nSvis = 0, nSpend = 0, nSdeben = 0;
        for (const BlockVis& bl : blocks_) if (bl.mesh.is_valid()) tB += bl.tris;
        // los triangulos de bloques segun el estado de su region (0 cerca, 1 LOD1, 2 LOD2, 3 fuera de la vista)
        int64_t tBe[4] = {0, 0, 0, 0};
        for (int bi = 0; bi < static_cast<int>(blocks_.size()); ++bi) {
            const BlockVis& bl = blocks_[bi];
            if (!bl.mesh.is_valid()) continue;
            const int RB = REGION / BLOCK;
            const int bx = bi % bnx_, by = (bi / bnx_) % bny_, bz = bi / (bnx_ * bny_);
            const int rr = (bx / RB) + rnx_ * ((by / RB) + rny_ * (bz / RB));
            const int st = (rr >= 0 && rr < static_cast<int>(regions_.size())) ? regions_[rr].state : 3;
            tBe[(st >= 0 && st <= 3) ? st : 3] += bl.tris;
        }
        d["bloques_regiones_urgentes"] = g_regionesUrgentes;
        d["gpu_tris_bloques_e0"] = tBe[0]; d["gpu_tris_bloques_e1"] = tBe[1]; d["gpu_tris_bloques_e2"] = tBe[2]; d["gpu_tris_bloques_e3"] = tBe[3];
        for (const RegionVis& rg : regions_) {
            if (rg.mesh1.is_valid()) t1 += rg.tris1;
            if (rg.mesh2.is_valid()) t2 += rg.tris2;
            if (rg.shMesh.is_valid()) { tS += rg.shTris; ++nS; if (regionCastsShadows(rg.state)) ++nSvis; }
            if (rg.casterStale && regionCastsShadows(rg.state)) ++nSpend;
            if (regionCastsShadows(rg.state)) ++nSdeben;
        }
        d["gpu_tris_bloques"] = tB; d["gpu_tris_lod1"] = t1; d["gpu_tris_lod2"] = t2; d["gpu_tris_sombra"] = tS;
        d["gpu_sombras_mallas"] = nS; d["gpu_sombras_usadas"] = nSvis; d["gpu_sombras_pendientes"] = nSpend;
        d["gpu_sombras_deben"] = nSdeben;
        d["gpu_sombras_cola"] = static_cast<int64_t>(colaSombras_.size());
        d["mem_malla_lod1_mb"] = bytesDe(chunkLod1_);
        d["mem_malla_lod2_mb"] = bytesDe(chunkLod2_);
        d["mem_malla_occ_mb"] = bytesDe(chunkOcc_);
        double col = 0.0;
        for (const std::vector<uint8_t>& cc : chunkCol_) col += static_cast<double>(cc.capacity());
        d["mem_malla_col_mb"] = col / 1048576.0;
        double cuerpos = 0.0;
        for (const Body& bb : bodies_) cuerpos += static_cast<double>(bb.data.vox.capacity());
        d["mem_bloques_vox_mb"] = cuerpos / 1048576.0;
    }
    d["jobs_pending"] = s.jobsPending;
    d["mesh_results_pending"] = s.meshResultsPending;
    d["uploads_frame"] = s.meshUploadsThisFrame;
    d["phys_updates_frame"] = physUpdatesThisFrame_;
    d["phys_queue"] = static_cast<int>(physQueue_.size());
    d["pieces_total"] = s.piecesDetachedTotal;
    d["groups_structural"] = s.groupsStructuralTotal; d["groups_plain"] = s.groupsPlainTotal; d["group_voxels"] = s.groupVoxelsTotal; d["revox_total"] = s.revoxelizedBodies;
    d["bodies_total"] = s.bodiesCreatedTotal;
    d["bodies_active"] = static_cast<int>(bodies_.size());
    d["escombros_quitados"] = g_escombrosQuitados;
    d["escombros_limpiados"] = g_escombrosLimpiados;
    d["asentados_por_tope"] = g_asentadosPorTope;
    {
        int chicos = 0;
        for (const Body& b : bodies_) if (static_cast<int>(b.data.voxelCount) <= ESCOMBRO_CHICO) ++chicos;
        d["escombros_chicos"] = chicos;
    }
    d["bodies_rigid"] = rigidCount_;
    d["prisa_escombros"] = prisaUsada_;
    // CUANTAS CAJAS DE COLISION HAY EN PIE. Un trozo de edificio no es una caja: es un compuesto de
    // decenas o cientos, y eso es lo que paga la fisica en cada paso. Sin este numero no se puede
    // saber si el coste viene de los cuerpos (pocos) o de sus formas (muchas).
    {
        int64_t formas = 0; int peor = 0; int despiertos = 0; int solidos = 0;
        for (const Body& bb : bodies_) {
            if (!bb.solid) continue;
            ++solidos;
            formas += static_cast<int64_t>(bb.shapes.size());
            peor = std::max(peor, static_cast<int>(bb.shapes.size()));
            if (bb.rigid && !bb.sleeping && !bb.congelado && !bb.anclado) ++despiertos;
        }
        int inst_sueltas = 0, congelados = 0;
        for (const Body& bb : bodies_) { if (bb.inst.is_valid()) ++inst_sueltas; if (bb.congelado) ++congelados; }
        int sucios = 0;
        for (const auto& kv : gruposCongelados_) if (kv.second.sucio) ++sucios;
        d["piezas_instancias"] = inst_sueltas;     // dibujos sueltos: cada uno es una instancia en el escenario
        d["piezas_congeladas"] = congelados;
        d["grupos_fundidos"] = static_cast<int>(gruposCongelados_.size());
        d["grupos_sucios"] = sucios;               // los que esperan turno para fundirse (1 por frame)
        d["shapes_total"] = formas;
        d["shapes_max"] = peor;
        d["bodies_solid"] = solidos;
        d["bodies_awake"] = despiertos;
    }
    d["bodies_congelados"] = congeladosVivos_;
    d["cajas_congelado"] = cajasCongelado_;
    d["grupos_congelado"] = static_cast<int64_t>(gruposCongelados_.size());   // draw calls reales de los congelados
    // BLOQUES QUE NO DIBUJA NADIE. Ni instancia propia ni malla comun al dia: cada uno de estos es un
    // frame de PARPADEO. Tiene que ser siempre 0.
    {
        int64_t ciegos = 0;
        for (const Body& b2 : bodies_) {
            if (!b2.congelado || b2.inst.is_valid()) continue;
            auto it = gruposCongelados_.find(b2.grupo);
            // OJO: que el grupo este "sucio" NO quiere decir que no se dibuje. Se sigue viendo con la
            // malla anterior hasta que se rehace; lo unico que esta desfasado es su contenido. El
            // parpadeo de verdad es no tener NI instancia propia NI malla de grupo en pantalla.
            if (it == gruposCongelados_.end() || !it->second.inst.is_valid()) ++ciegos;
        }
        d["congel_sin_dibujo"] = ciegos;
    }
    // LO CONTRARIO: DIBUJO SIN BLOQUE. Piezas que una malla comun (ya al dia) sigue pintando pero cuyo
    // bloque ya no existe: se ve, no tiene fisica, y no se va hasta que algo vuelva a ensuciar la celda.
    // Tiene que ser siempre 0 (ver freeBody).
    {
        std::unordered_map<uint64_t, int> vivos;
        for (const Body& b2 : bodies_) if (b2.grupo) ++vivos[b2.grupo];
        int64_t fantasmas = 0;
        for (const auto& kv : gruposCongelados_) {
            if (kv.second.sucio || !kv.second.inst.is_valid()) continue;
            const auto it = vivos.find(kv.first);
            fantasmas += std::max(0, kv.second.piezas - (it == vivos.end() ? 0 : it->second));
        }
        d["grupo_fantasmas"] = fantasmas;
    }
    d["apoyos_rotos"] = apoyosRotos_;   // apoyos que han cedido bajo el peso de un bloque
    // BLOQUES METIDOS DENTRO DE OTRO. Si un bloque acaba con su centro dentro de la caja de otro es
    // que lo ha ATRAVESADO en vez de posarse encima. Tiene que ser 0.
    //
    // ES CADA BLOQUE CONTRA TODOS LOS DEMAS, con una inversa de matriz por pareja: con los 354 bloques que
    // deja una demolicion son 125.000 parejas y 15 ms POR LLAMADA, y crece al cuadrado (1.000 bloques serian
    // 100 ms). Como get_stats se llama varias veces por segundo para el panel, tras demoler un edificio el
    // juego ya no volvia a los fps de antes. Se calcula solo si alguien lo pide (--congela y el banco).
    if (!diagBloques_) {
        d["bloques_dentro_de_otro"] = -1;
    } else {
        const float vs2 = engine_->world().voxelSize();
        int64_t dentro = 0;
        for (const Body& a : bodies_) {
            if (!a.congelado && !a.anclado && !a.resting) continue;
            const Vector3 ca = a.rigid ? a.xf.origin : a.pos;
            for (const Body& o : bodies_) {
                if (&o == &a) continue;
                if (!o.congelado && !o.anclado && !o.resting) continue;
                // EXACTO, NO POR CAJA. Comparar cajas englobantes da falsos positivos: un bloque
                // girado tiene una caja mucho mayor que el, y un vecino pegado cae dentro de ella sin
                // estar dentro del bloque. Se lleva el centro al marco del otro y se mira SU VOXEL.
                const Transform3D ot = o.rigid ? o.xf : Transform3D(Basis(), o.pos);
                const Vector3 loc = ot.affine_inverse().xform(ca) + toGd(o.data.com);
                const int lx = static_cast<int>(std::floor(loc.x / vs2));
                const int ly = static_cast<int>(std::floor(loc.y / vs2));
                const int lz = static_cast<int>(std::floor(loc.z / vs2));
                if (lx < 0 || ly < 0 || lz < 0 || lx >= o.data.sx || ly >= o.data.sy || lz >= o.data.sz) continue;
                if (o.data.vox[static_cast<size_t>(lx + ly * o.data.sx + lz * o.data.sx * o.data.sy)]) { ++dentro; break; }
            }
        }
        d["bloques_dentro_de_otro"] = dentro;
    }
    {
    }   // trozos que conservan su forma y su angulo exactos
    d["congel_desconocidos"] = static_cast<int64_t>(congelDesconocidos_);   // >0 = las dos maquinas NO tienen los mismos trozos
    d["congel_pendientes"] = static_cast<int64_t>(congelPendientes_.size());   // posturas esperando a que nazca su trozo
    d["rigid_topados"] = g_rigidTopados;   // >0 = esta maquina ha degradado y ya no ve lo mismo que las demas
    d["bodies_cheap"] = cheapCount_;
    d["bodies_cheap_solid"] = cheapSolidCount_;
    d["spawn_rigid"] = spawnRigid_;
    d["spawn_cheap_solid"] = spawnCheapSolid_;
    d["spawn_cheap_ghost"] = spawnCheapGhost_;
    d["spawn_instant"] = spawnInstant_;
    d["removed_revox"] = removedRevox_;
    d["removed_age"] = removedAge_;
    d["removed_void"] = removedVoid_;
    d["removed_carve"] = removedCarve_;
    d["clump_scale"] = engine_->clumpScale();
    d["tiny_pieces"] = s.piecesToDebrisTotal;
    d["revoxelized"] = s.revoxelizedBodies;
    d["debris_active"] = s.debrisActive;
    d["smoke_active"] = engine_->smoke().count();
    d["debris_capacity"] = s.debrisCapacity;
    d["t_update_ms"] = s.tUpdate.avg;
    d["t_carve_ms"] = s.tCarve.avg;
    d["t_mesh_job_ms"] = s.tMeshJob.avg;
    d["t_mesh_job_max_ms"] = s.tMeshJob.max;
    d["t_conn_ms"] = s.tConnLabel.avg;
    d["t_solve_ms"] = s.tSolve.avg;
    d["t_upd_enqueue_ms"] = s.tUpdEnqueue.avg;
    d["t_upd_collect_ms"] = s.tUpdCollect.avg;
    d["t_upd_stats_ms"] = s.tUpdStats.avg;
    d["t_extract_ms"] = s.tExtract.avg;
    d["t_debris_ms"] = s.tDebris.avg;
    d["t_nav_ms"] = s.tNav.avg;
    d["t_host_ms"] = lastProcessMs_;
    d["nav_last_ms"] = engine_->lastNavMs(); d["nav_last_complete"] = engine_->lastNavComplete();
    d["pieces_pending"] = static_cast<int>(pendingPieces_.size());
    d["t_explode_core_ms"] = tExplodeCore_; d["t_explode_total_ms"] = tExplodeTotal_;
    d["t_h_update"] = tHUpdate_; d["t_h_upload"] = tHUpload_; d["t_h_blocks"] = tHBlocks_; d["t_h_regions"] = tHRegions_;
    d["t_h_phys"] = tHPhys_; d["t_h_spawn"] = tHSpawn_; d["t_h_bodies"] = tHBodies_; d["t_h_debris"] = tHDebris_;
    d["fis_ms_anclas"] = g_fisMsAnclas; d["fis_ms_anclas_max"] = g_fisMsAnclasMax;
    d["fis_col_recibidas"] = g_colRecibidas; d["fis_col_iguales"] = g_colIguales;
    d["fis_ms_copia"] = g_fisMsCopia; d["fis_ms_set"] = g_fisMsSet; d["fis_ms_set_max"] = g_fisMsSetMax;
    d["fis_ms_despertar"] = g_fisMsDespertar; d["fis_ms_despertar_max"] = g_fisMsDespertarMax;
    d["fis_tris_previo"] = g_fisTrisPrev; d["fis_formas_previo"] = g_fisFormasPrev;
    d["fis_tris_ultimo"] = g_fisTrisUlt; d["fis_formas_ultimo"] = g_fisFormasUlt; d["fis_cola"] = static_cast<int64_t>(physQueue_.size());
    d["t_hmax_update"] = g_hMax[0]; d["t_hmax_upload"] = g_hMax[1]; d["t_hmax_blocks"] = g_hMax[2]; d["t_hmax_regions"] = g_hMax[3];
    d["t_hl_update"] = g_hLast[0]; d["t_hl_upload"] = g_hLast[1]; d["t_hl_blocks"] = g_hLast[2]; d["t_hl_regions"] = g_hLast[3];
    d["t_hl_bs_fina"] = g_bs[0]; d["t_hl_bs_impacto"] = g_bs[1]; d["t_hl_bs_suelo"] = g_bs[2]; d["t_hl_bs_asentar"] = g_bs[3];
    d["t_hl_bs_cerca"] = g_bs[4];
    d["t_hl_cf_partir"] = g_cf[0]; d["t_hl_cf_formas"] = g_cf[1]; d["t_hl_cf_anadir"] = g_cf[2]; d["cf_cajas"] = g_cfCajas;
    d["fis_cf_total_ms"] = g_cfTotalMs; d["fis_cf_total_cajas"] = g_cfTotalCajas;
    d["fis_bs_total_ms"] = g_bsTotalMs; d["fis_bs_llamadas"] = g_bsLlamadas;
    d["fis_rc_total_ms"] = g_rcTotalMs; d["fis_rc_cajas"] = g_rcCajas;
    d["t_hl_b_mover"] = g_bLast[0]; d["t_hl_b_reconstruir"] = g_bLast[1]; d["t_hl_b_solidificar"] = g_bLast[2];
    d["t_hl_phys"] = g_hLast[4]; d["t_hl_spawn"] = g_hLast[5]; d["t_hl_bodies"] = g_hLast[6]; d["t_hl_debris"] = g_hLast[7];
    d["t_hmax_phys"] = g_hMax[4]; d["t_hmax_spawn"] = g_hMax[5]; d["t_hmax_bodies"] = g_hMax[6]; d["t_hmax_debris"] = g_hMax[7];
    d["t_hmax_reg_merge"] = g_fMax[0]; d["t_hmax_reg_surf"] = g_fMax[1]; d["t_hmax_reg_occ"] = g_fMax[2]; d["t_hmax_reg_shadow"] = g_fMax[3];
    d["t_hmax_block_merge"] = g_fMax[4]; d["t_hmax_block_surf"] = g_fMax[5]; d["t_hmax_piece_mesh"] = g_fMax[6]; d["t_hmax_piece_rest"] = g_fMax[7];
    d["t_hmax_surf_pack"] = g_fMax[8]; d["t_hmax_surf_rs"] = g_fMax[9]; d["t_hmax_piece_shapes"] = g_fMax[10]; d["t_hmax_piece_space"] = g_fMax[11];
    d["t_hmax_step_bodies"] = g_fMax[12]; d["t_hmax_reconstruir"] = g_fMax[13]; d["t_hmax_solidificar"] = g_fMax[14];
    d["t_hmax_surf_verts"] = g_fMax[15];
    d["pz_estruct"] = g_pzEstruct; d["pz_sueltas"] = g_pzSueltas; d["vox_estruct"] = g_voxEstruct; d["vox_sueltas"] = g_voxSueltas;
    d["pz_grandes"] = g_pzGrandes; d["pz_mayor"] = g_pzMayor;
    d["flotadores_soldados"] = weldedFloaters_; d["flotadores_sin_soldar"] = weldSinSoldar_; d["flotadores_voxels"] = weldVoxels_;
    d["t_host_max_ms"] = maxProcessMs_;
    d["threads"] = 0;
    // sistema estructural (analizador de rutas de carga) y trozos de explosión
    d["t_struct_ms"] = s.tStruct.avg; d["t_struct_max_ms"] = s.tStruct.max; d["t_struct_scan_ms"] = s.tStructScan.avg;
    d["t_clumps_ms"] = s.tClumps.avg;
    d["struct_iterations"] = s.structIterationsTotal; d["struct_active"] = s.structRegionsActive;
    d["struct_islands"] = s.structIslandsEvaluated; d["struct_islands_skipped"] = s.structIslandsSkipped;
    d["struct_cells"] = s.structCellsEvaluated; d["struct_failures"] = s.structFailuresTotal; d["struct_fragments"] = s.structFragmentsTotal;
    d["struct_worst_ratio"] = s.structWorstRatio;
    {   // la celda mas cargada, en metros (su centro aproximado: un voxel hacia dentro de la esquina)
        const float vsw = engine_->world().voxelSize();
        d["struct_worst_pos"] = Vector3((s.structWorstX + 1.0f) * vsw, (s.structWorstY + 1.0f) * vsw, (s.structWorstZ + 1.0f) * vsw);
    }
    d["chunks_skipped_nolock"] = s.chunksSkippedNoLock;
    // rayos (jerarquía de ocupación): pasos de voxel y saltos de región vacía acumulados
    d["rays_traced"] = static_cast<int64_t>(s.raysTraced); d["ray_steps"] = static_cast<int64_t>(s.raySteps); d["ray_skips"] = static_cast<int64_t>(s.raySkips);
    return d;
}

void VoxelWorld::set_struct_debug_enabled(bool on) { if (engine_) engine_->setStructDebug(on); }

Dictionary VoxelWorld::get_struct_debug() const {
    Dictionary d;
    if (!engine_) return d;
    const vx::StructDebug& dbg = engine_->structDebug();
    const float vs = engine_->world().voxelSize();
    d["active"] = engine_->structActive();
    d["iteration"] = dbg.iteration;
    d["cell_size"] = dbg.cellVoxels * vs;
    d["region_min"] = Vector3(dbg.regionMin.x * vs, dbg.regionMin.y * vs, dbg.regionMin.z * vs);
    d["region_max"] = Vector3((dbg.regionMax.x + 1) * vs, (dbg.regionMax.y + 1) * vs, (dbg.regionMax.z + 1) * vs);
    d["damage_center"] = toGd(dbg.damageCenter);
    d["islands_evaluated"] = dbg.islandsEvaluated; d["islands_skipped"] = dbg.islandsSkipped;
    d["cells_evaluated"] = dbg.cellsEvaluated; d["failures"] = dbg.failures; d["worst_ratio"] = dbg.worstRatio; d["ms"] = dbg.ms;
    // celdas: arrays paralelos (mucho más barato que un Dictionary por celda para 5-10 k celdas)
    PackedVector3Array centers; PackedFloat32Array ratios; PackedByteArray states; PackedInt32Array islands; PackedFloat32Array loads, caps;
    centers.resize(static_cast<int64_t>(dbg.cells.size())); ratios.resize(static_cast<int64_t>(dbg.cells.size())); states.resize(static_cast<int64_t>(dbg.cells.size()));
    islands.resize(static_cast<int64_t>(dbg.cells.size())); loads.resize(static_cast<int64_t>(dbg.cells.size())); caps.resize(static_cast<int64_t>(dbg.cells.size()));
    for (size_t i = 0; i < dbg.cells.size(); ++i) {
        const vx::StructDebugCell& c = dbg.cells[i];
        centers.set(static_cast<int64_t>(i), Vector3(c.center.x * vs, c.center.y * vs, c.center.z * vs));
        ratios.set(static_cast<int64_t>(i), c.ratio); states.set(static_cast<int64_t>(i), c.state);
        islands.set(static_cast<int64_t>(i), c.island); loads.set(static_cast<int64_t>(i), c.load); caps.set(static_cast<int64_t>(i), c.capacity);
    }
    d["cell_centers"] = centers; d["cell_ratios"] = ratios; d["cell_states"] = states; d["cell_islands"] = islands; d["cell_loads"] = loads; d["cell_capacities"] = caps;
    Array isl;
    for (const vx::IslandInfo& I : dbg.islands) {
        Dictionary e; e["id"] = I.id; e["com"] = Vector3(I.com.x * vs, I.com.y * vs, I.com.z * vs); e["support"] = Vector3(I.support.x * vs, I.support.y * vs, I.support.z * vs);
        e["mass"] = I.mass; e["cells"] = I.cells; e["worst_ratio"] = I.worstRatio;
        isl.push_back(e);
    }
    d["islands"] = isl;
    return d;
}

void VoxelWorld::set_struct_param(const String& name, float value) {
    if (!engine_) return;
    vx::StructParams& p = engine_->structParams();
    const std::string n = name.utf8().get_data();
    if (n == "region_radius") p.regionRadius = value; else if (n == "capacity") p.capacityPerVoxel = value;
    else if (n == "safety_margin") p.safetyMargin = value; else if (n == "base_tolerance") p.baseTolerance = value;
    else if (n == "strain_rate") p.strainRate = value; else if (n == "strain_to_fail") p.strainToFail = value;
    else if (n == "beam_factor") p.beamFactor = value; else if (n == "moment_factor") p.momentFactor = value;
    else if (n == "arch_factor") p.archFactor = value; else if (n == "max_span") p.maxSpanMeters = value;
    else if (n == "buckling_min") p.bucklingMin = value;
    else if (n == "max_iterations") p.maxIterations = static_cast<int>(value); else if (n == "interval_frames") p.iterationIntervalFrames = static_cast<int>(value);
    else if (n == "max_failures") p.maxOverloadFailures = static_cast<int>(value);
    else UtilityFunctions::push_warning(String("VoxelWorld.set_struct_param: parámetro desconocido ") + name);
}

float VoxelWorld::get_struct_param(const String& name) const {
    if (!engine_) return 0.f;
    const vx::StructParams& p = engine_->structParams();
    const std::string n = name.utf8().get_data();
    if (n == "region_radius") return p.regionRadius; if (n == "capacity") return p.capacityPerVoxel;
    if (n == "safety_margin") return p.safetyMargin; if (n == "base_tolerance") return p.baseTolerance;
    if (n == "strain_rate") return p.strainRate; if (n == "strain_to_fail") return p.strainToFail;
    if (n == "beam_factor") return p.beamFactor; if (n == "moment_factor") return p.momentFactor;
    if (n == "arch_factor") return p.archFactor; if (n == "max_span") return p.maxSpanMeters;
    if (n == "buckling_min") return p.bucklingMin;
    if (n == "max_iterations") return static_cast<float>(p.maxIterations); if (n == "interval_frames") return static_cast<float>(p.iterationIntervalFrames);
    if (n == "max_failures") return static_cast<float>(p.maxOverloadFailures);
    return 0.f;
}

Vector3 VoxelWorld::get_spawn_position() const { return toGd(city_.playerSpawn); }

PackedVector3Array VoxelWorld::get_building_centers() const {
    PackedVector3Array out; out.resize(static_cast<int64_t>(city_.buildingCenters.size()));
    Vector3* p = out.ptrw();
    for (size_t i = 0; i < city_.buildingCenters.size(); ++i) p[i] = toGd(city_.buildingCenters[i]);
    return out;
}

PackedVector3Array VoxelWorld::get_street_points() const {
    PackedVector3Array out; out.resize(static_cast<int64_t>(city_.streetPoints.size()));
    Vector3* p = out.ptrw();
    for (size_t i = 0; i < city_.streetPoints.size(); ++i) p[i] = toGd(city_.streetPoints[i]);
    return out;
}

Vector3 VoxelWorld::get_world_size() const { return engine_ ? toGd(engine_->world().sizeMeters()) : Vector3(); }

int VoxelWorld::get_material_at(const Vector3& p) const { return engine_ ? engine_->world().getVoxelAt(toVxV(p)) : 0; }

float VoxelWorld::get_material_capa(int mat) const { return capaDeMaterial(mat); }

// el material de las particulas de escombro (main.gd pone trozo.gdshader: color y textura del material)
void VoxelWorld::set_debris_material(const Ref<Material>& m) {
    if (m.is_null()) return;
    debrisMat_ = m;
    RenderingServer* rs = RenderingServer::get_singleton();
    if (rs && debrisMesh_.is_valid()) rs->mesh_surface_set_material(debrisMesh_, 0, m->get_rid());
}

Dictionary VoxelWorld::get_material_info(int mat) const {
    Dictionary d;
    if (mat < 0 || mat >= vx::MAT_COUNT) return d;
    const vx::Material& m = vx::g_materials[mat];
    d["name"] = String(m.name);
    d["strength"] = static_cast<int>(m.strength);
    d["density"] = static_cast<int>(m.density);
    d["flags"] = static_cast<int>(m.flags);
    d["indestructible"] = (m.flags & vx::MF_INDESTRUCTIBLE) != 0;
    d["anchor"] = (m.flags & vx::MF_ANCHOR) != 0;
    d["glass"] = (m.flags & vx::MF_GLASS) != 0;
    // sistema de materiales (Fase 9): clase y parámetros físicos centralizados en vxcore
    d["class"] = String(vx::className(m.cls));
    d["compressive"] = m.phys.compressiveStrength; d["tensile"] = m.phys.tensileStrength; d["shear"] = m.phys.shearStrength;
    d["fracture_threshold"] = m.phys.fractureThreshold; d["stiffness"] = m.phys.stiffness;
    d["friction"] = m.phys.friction; d["restitution"] = m.phys.restitution;
    return d;
}

bool VoxelWorld::box_solid(const Vector3& bmin, const Vector3& bmax) const {
    if (!engine_) return false;
    const vx::World& w = engine_->world();
    const vx::IVec3 a = w.toVoxel(toVxV(bmin)), b = w.toVoxel(toVxV(bmax));
    for (int z = std::min(a.z, b.z); z <= std::max(a.z, b.z); ++z)
    for (int y = std::min(a.y, b.y); y <= std::max(a.y, b.y); ++y)
    for (int x = std::min(a.x, b.x); x <= std::max(a.x, b.x); ++x)
        if (w.getVoxel(x, y, z)) return true;
    return false;
}

// Cuantos voxels solidos hay en una caja (metros). Para las pruebas: "cuanto queda del techo de la mesa".
int VoxelWorld::contar_voxels(const Vector3& bmin, const Vector3& bmax) const {
    if (!engine_) return 0;
    const vx::World& w = engine_->world();
    const vx::IVec3 a = w.toVoxel(toVxV(bmin)), b = w.toVoxel(toVxV(bmax));
    int n = 0;
    for (int z = std::min(a.z, b.z); z <= std::max(a.z, b.z); ++z)
    for (int y = std::min(a.y, b.y); y <= std::max(a.y, b.y); ++y)
    for (int x = std::min(a.x, b.x); x <= std::max(a.x, b.x); ++x)
        if (w.getVoxel(x, y, z)) ++n;
    return n;
}

Color VoxelWorld::get_material_color(int mat) const {
    const vx::Material& m = vx::material(static_cast<uint8_t>(std::clamp(mat, 0, static_cast<int>(vx::MAT_COUNT) - 1)));
    return Color(m.r / 255.f, m.g / 255.f, m.b / 255.f, 1.f);
}

String VoxelWorld::get_material_name(int mat) const {
    return String(vx::material(static_cast<uint8_t>(std::clamp(mat, 0, static_cast<int>(vx::MAT_COUNT) - 1))).name);
}

// ---------------------------------------------------------------------------
// Ocupación en GPU para la oclusión volumétrica (idea del mapa de sombras volumétrico de Teardown)
// ---------------------------------------------------------------------------
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/variant/typed_array.hpp>

void VoxelWorld::occFree() {
    RenderingServer* rs = RenderingServer::get_singleton();
    if (rs && occTex_.is_valid()) rs->free_rid(occTex_);
    occTex_ = RID(); occLayerDirty_.clear(); occDirtyList_.clear();
}

void VoxelWorld::occInit() {
    occFree();
    if (!engine_ || !occEnabled_) return;
    const vx::World& w = engine_->world();
    // celda de 2 voxels si cabe en ~24 MB; si no, de 4 (mapas de 10 cm de 200 m)
    occCell_ = 2;
    if (static_cast<int64_t>(w.sizeX() / 2) * (w.sizeY() / 2) * (w.sizeZ() / 2) > 24 * 1024 * 1024) occCell_ = 4;
    occDims_[0] = w.sizeX() / occCell_; occDims_[1] = w.sizeY() / occCell_; occDims_[2] = w.sizeZ() / occCell_;
    TypedArray<Image> layers;
    PackedByteArray zero; zero.resize(occDims_[0] * occDims_[1]);
    for (int z = 0; z < occDims_[2]; ++z) layers.push_back(Image::create_from_data(occDims_[0], occDims_[1], false, Image::FORMAT_L8, zero));
    RenderingServer* rs = RenderingServer::get_singleton();
    occTex_ = rs->texture_2d_layered_create(layers, RenderingServer::TEXTURE_LAYERED_2D_ARRAY);
    occLayerDirty_.assign(occDims_[2], 1);
    occDirtyList_.clear();
    for (int z = 0; z < occDims_[2]; ++z) occDirtyList_.push_back(z);
    occScratch_.resize(occDims_[0] * occDims_[1]);
}

void VoxelWorld::set_occlusion_volume(bool on) {
    if (occEnabled_ == on) return;
    occEnabled_ = on;
    occInit();
}

void VoxelWorld::occMarkChunk(int idx) {
    if (!occEnabled_ || !occTex_.is_valid() || !engine_) return;
    const vx::IVec3 cc = engine_->world().chunkCoords(idx);
    const int z0 = cc.z * vx::CHUNK_SIZE / occCell_, z1 = z0 + vx::CHUNK_SIZE / occCell_;
    for (int z = z0; z < z1 && z < occDims_[2]; ++z) if (!occLayerDirty_[z]) { occLayerDirty_[z] = 1; occDirtyList_.push_back(z); }
}

// Reconstruye una capa Z completa (todas las celdas x,y de ese plano) leyendo los bits de ocupación de los chunks.
void VoxelWorld::occFlush(int budget) {
    occUploadsThisFrame_ = 0;
    if (!occEnabled_ || !occTex_.is_valid() || occDirtyList_.empty()) return;
    RenderingServer* rs = RenderingServer::get_singleton();
    const vx::World& w = engine_->world();
    const int per = vx::CHUNK_SIZE / occCell_;   // celdas por chunk y eje
    while (!occDirtyList_.empty() && occUploadsThisFrame_ < budget) {
        const int z = occDirtyList_.back(); occDirtyList_.pop_back();
        occLayerDirty_[z] = 0;
        uint8_t* out = occScratch_.ptrw();
        std::memset(out, 0, occScratch_.size());
        const int cz = (z * occCell_) >> vx::CHUNK_BITS, lz = (z * occCell_) & vx::CHUNK_MASK;
        for (int cy = 0; cy < w.chunksY(); ++cy) for (int cx = 0; cx < w.chunksX(); ++cx) {
            const vx::Chunk* c = w.chunk(cx, cy, cz);
            if (!c || c->solidAtomic.load(std::memory_order_relaxed) == 0) continue;
            for (int ly = 0; ly < per; ++ly) {
                uint8_t* row = out + (cy * per + ly) * occDims_[0] + cx * per;
                for (int lx = 0; lx < per; ++lx) {
                    const int vx_ = lx * occCell_, vy = ly * occCell_;
                    row[lx] = (occCell_ == 2 ? c->occ.any2(vx_, vy, lz) : c->occ.any4(vx_, vy, lz)) ? 255 : 0;
                }
            }
        }
        // la imagen se guarda unos cuadros (2026-10-20): con el hilo de render separado la subida se hace despues, en el
        // otro hilo, y la temporal ya se habia soltado ("p_image.is_null() || p_image->is_empty()" en el registro)
        static std::vector<Ref<Image>> vivas(64);
        static size_t vivaSig = 0;
        Ref<Image> img = Image::create_from_data(occDims_[0], occDims_[1], false, Image::FORMAT_L8, occScratch_.duplicate());
        vivas[vivaSig++ % vivas.size()] = img;
        rs->texture_2d_update(occTex_, img, z);
        ++occUploadsThisFrame_;
    }
}

void VoxelWorld::bind_occupancy_to_material(const Ref<Material>& m) {
    if (!m.is_valid() || !engine_) return;
    RenderingServer* rs = RenderingServer::get_singleton();
    if (!occTex_.is_valid()) occInit();
    if (!occTex_.is_valid()) return;
    rs->material_set_param(m->get_rid(), "occ", occTex_);
    rs->material_set_param(m->get_rid(), "dims", Vector3(static_cast<float>(occDims_[0]), static_cast<float>(occDims_[1]), static_cast<float>(occDims_[2])));
    rs->material_set_param(m->get_rid(), "cell", occCell_ * engine_->world().voxelSize());
}

Dictionary VoxelWorld::get_occupancy_info() const {
    Dictionary d;
    d["enabled"] = occEnabled_ && occTex_.is_valid();
    d["dims"] = Vector3i(occDims_[0], occDims_[1], occDims_[2]);
    d["cell"] = engine_ ? occCell_ * engine_->world().voxelSize() : 0.f;
    d["pending_layers"] = static_cast<int>(occDirtyList_.size());
    d["uploads_frame"] = occUploadsThisFrame_;
    return d;
}


// COLOR POR TEXTURA: se decide al cargar (antes de mallar nada) y se crean la textura de capas, la tabla de que capa
// lleva cada chunk y la paleta. Solo los chunks con algo llevan capa (la rejilla entera de Monaco son 5.642 y la mayoria
// aire), con hueco de sobra para los que se llenen luego (place_settled, bloques que vuelven al mapa).
static void ponerSlotEnMapa(int idx, int slot, int ncx, int ncy) {
    const int cx = idx % ncx, cy = (idx / ncx) % ncy, cz = idx / (ncx * ncy);
    const int v = slot + 1;
    g_ctMapaImg->set_pixel(cx, cy + cz * ncy, Color((v & 0xFF) / 255.f, ((v >> 8) & 0xFF) / 255.f, 0.f, 1.f));
    g_ctMapaSucio = true;
}

void VoxelWorld::prepararColorTextura() {
    g_ctOn = false;
    g_ctImgs.clear(); g_ctSlot.clear(); g_ctUsadas = 0;
    g_ctSucias.clear();
    g_ctCapas.unref(); g_ctPaleta.unref(); g_ctMapa.unref(); g_ctMapaImg.unref();
    g_ctMatPuesto = 0;
    if (!engine_) return;
    const vx::World& w = engine_->world();
    const int ncx = w.chunksX(), ncy = w.chunksY(), ncz = w.chunksZ();
    const int n = ncx * ncy * ncz;
    if (std::getenv("VX_SIN_COLOR_TEX") != nullptr || n <= 0) { engine_->setColorTextura(false, nullptr); return; }
    int llenos = 0;
    for (int i = 0; i < n; ++i) { const vx::Chunk* c = w.chunkAt(i); if (c && c->solidAtomic.load(std::memory_order_relaxed) > 0) ++llenos; }
    // EL TOPE DE CAPAS DE LA GPU (2026-10-22, bug: "en el movil la habitacion se ve toda blanca y celeste"): muchos
    // moviles solo admiten 256 (o 2048) capas en una textura de capas; pasandose, la textura sale vacia y todo el mundo
    // tenia el color 0. Se pregunta a la GPU; si no contesta, en Android se cuenta con 256.
    int tope = COLOR_TEX_MAX_CAPAS;
    {
        RenderingDevice* rd = RenderingServer::get_singleton() ? RenderingServer::get_singleton()->get_rendering_device() : nullptr;
        int64_t lim = rd ? rd->limit_get(RenderingDevice::LIMIT_MAX_TEXTURE_ARRAY_LAYERS) : 0;
        if (lim <= 0 && OS::get_singleton() && OS::get_singleton()->get_name() == String("Android")) lim = 256;
        if (lim > 0) tope = std::min<int>(tope, static_cast<int>(lim));
    }
    const int capacidad = std::min(tope, std::max(llenos + 64, llenos + llenos / 4));
    if (llenos == 0 || llenos + 16 > tope) {
        engine_->setColorTextura(false, nullptr);
        UtilityFunctions::print(vformat("[color] %d chunks con algo: no caben en la textura (%d), color en la malla", llenos, tope));
        return;
    }
    g_ctSlot.assign(static_cast<size_t>(n), -1);
    g_ctMapaImg = Image::create_empty(ncx, ncy * ncz, false, Image::FORMAT_RG8);
    g_ctMapaImg->fill(Color(0, 0, 0, 1));
    TypedArray<Image> capas;
    g_ctImgs.resize(static_cast<size_t>(capacidad));
    for (int i = 0; i < n; ++i) {
        const vx::Chunk* c = w.chunkAt(i);
        if (!c || c->solidAtomic.load(std::memory_order_relaxed) == 0) continue;
        const int sl = g_ctUsadas++;
        g_ctSlot[i] = sl;
        g_ctImgs[sl] = imagenDeChunk(c);
        ponerSlotEnMapa(i, sl, ncx, ncy);
    }
    for (int sl = g_ctUsadas; sl < capacidad; ++sl) g_ctImgs[sl] = imagenDeChunk(nullptr);
    for (int sl = 0; sl < capacidad; ++sl) capas.push_back(g_ctImgs[sl]);
    g_ctCapas.instantiate();
    if (g_ctCapas->create_from_images(capas) != OK) {
        g_ctCapas.unref(); g_ctImgs.clear(); g_ctSlot.clear();
        engine_->setColorTextura(false, nullptr);
        UtilityFunctions::print("[color] no se pudo crear la textura de capas: color en la malla");
        return;
    }
    g_ctMapa = ImageTexture::create_from_image(g_ctMapaImg);
    g_ctMapaSucio = false;
    if (!g_matLinearInit) refreshMaterialColors();
    Ref<Image> pal = Image::create_empty(256, 1, false, Image::FORMAT_RGBAH);
    for (int i = 0; i < vx::MAT_COUNT && i < 256; ++i) pal->set_pixel(i, 0, g_matLinear[i]);
    g_ctPaleta = ImageTexture::create_from_image(pal);
    engine_->setColorTextura(true, g_grupoColor);
    g_ctOn = true;
    aplicarColorTextura();
    UtilityFunctions::print(vformat("[color] color por textura: %d chunks con algo de %d, %d capas (%.1f MB)", llenos, n, capacidad, capacidad * vx::CHUNK_VOLUME / 1048576.0));
}

// los parametros del sombreado del mundo (otra vez si cambia el material o cada pocos segundos: main.gd cambia de
// variante de sombreado sobre el mismo material)
void VoxelWorld::aplicarColorTextura() {
    Ref<ShaderMaterial> sm = opaqueMat_;
    if (sm.is_null()) return;
    sm->set_shader_parameter("color_on", g_ctOn);
    if (!g_ctOn) return;
    sm->set_shader_parameter("color_capas", g_ctCapas);
    sm->set_shader_parameter("color_mapa", g_ctMapa);
    sm->set_shader_parameter("color_paleta", g_ctPaleta);
    sm->set_shader_parameter("color_chunks", Vector3i(engine_->world().chunksX(), engine_->world().chunksY(), engine_->world().chunksZ()));
    sm->set_shader_parameter("color_vox", engine_->world().voxelSize());
    g_ctMatPuesto = reinterpret_cast<uint64_t>(opaqueMat_.ptr());
}

// las capas de los chunks que han cambiado, a la textura (como mucho 64 por fotograma)
void VoxelWorld::flushColorTextura(double dt) {
    if (!g_ctOn || g_ctCapas.is_null() || !engine_) return;
    g_ctReaplicar -= dt;
    if (reinterpret_cast<uint64_t>(opaqueMat_.ptr()) != g_ctMatPuesto || g_ctReaplicar <= 0.0) {
        g_ctReaplicar = 2.0;
        aplicarColorTextura();
    }
    if (!g_ctSucias.empty()) {
        const vx::World& w = engine_->world();
        int hechas = 0;
        for (auto it = g_ctSucias.begin(); it != g_ctSucias.end() && hechas < 64;) {
            const int i = *it;
            it = g_ctSucias.erase(it);
            const vx::Chunk* c = w.chunkAt(i);
            int sl = g_ctSlot[i];
            if (sl < 0) {
                if (!c || c->solidAtomic.load(std::memory_order_relaxed) == 0) continue;
                if (g_ctUsadas >= static_cast<int>(g_ctImgs.size())) continue;   // sin hueco: se queda con el color de la malla
                sl = g_ctUsadas++;
                g_ctSlot[i] = sl;
                ponerSlotEnMapa(i, sl, w.chunksX(), w.chunksY());
            }
            // la de antes se guarda unos cuadros: con el hilo de render separado la subida se hace despues (ver occTex_)
            g_ctVivas[g_ctVivaSig++ % g_ctVivas.size()] = g_ctImgs[sl];
            g_ctImgs[sl] = imagenDeChunk(c);
            g_ctCapas->update_layer(g_ctImgs[sl], sl);
            ++hechas;
        }
    }
    if (g_ctMapaSucio && g_ctMapa.is_valid()) {
        Ref<Image> copia = g_ctMapaImg->duplicate();   // se sigue tocando: al hilo de render, una copia que no cambia
        g_ctVivas[g_ctVivaSig++ % g_ctVivas.size()] = copia;
        g_ctMapa->update(copia);
        g_ctMapaSucio = false;
    }
}
