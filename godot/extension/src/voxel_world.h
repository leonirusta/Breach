// VoxelWorld - nodo Godot que expone vxcore al juego
// ---------------------------------------------------------------------------
// Capa FINA: convierte comandos de GDScript en llamadas a vx::Engine y publica
// los resultados en el RenderingServer / PhysicsServer3D (Jolt) SIN nodos:
//   - cerca: BLOQUES de 2x2x2 chunks fusionados en una malla completa (opaca + cristal): 1 draw call
//     por bloque en vez de 8, reconstruido con un memcpy cuando se edita un chunk.
//   - lejos: REGIONES de 4x4x4 chunks fusionadas en una sola malla LOD (voxels 2x) o LOD2 (4x):
//     un draw call por región en vez de 64. Es lo que permite mapas grandes a 60 FPS.
//   - por región además: un occluder conservador y un caster de sombras fusionado (sólo sombras).
//   - física: cuerpos estáticos por chunk SÓLO alrededor de las "anclas" (jugador, bots, piezas,
//     granadas): un mapa de 6000 chunks no necesita 6000 cuerpos en Jolt, sólo unos cientos.
//   - piezas desprendidas: rigid body con cajas, "caída barata" o re-voxelización directa
//   - escombros: 1 MultiMesh (un draw call para todas las partículas)
// Toda la lógica pesada vive en vxcore; aquí sólo hay marshalling y presupuestos.
// ---------------------------------------------------------------------------
#pragma once
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/material.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/physics_server3d.hpp>
#include <godot_cpp/classes/physics_direct_body_state3d.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <memory>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <deque>
#include <vector>
#include <unordered_map>
#include <algorithm>

#include "vx/vx_engine.h"
#include "vx/vx_citygen.h"

namespace godot {

class VoxelWorld : public Node3D {
    GDCLASS(VoxelWorld, Node3D)

public:
    VoxelWorld();
    ~VoxelWorld();

    // --- configuración (propiedades) ---
    void set_quality(int q);
    int get_quality() const { return quality_; }
    void set_chunks(const Vector3i& c) { chunkDims_ = c; }
    Vector3i get_chunks() const { return chunkDims_; }
    void set_seed(int s) { seed_ = s; }
    int get_seed() const { return seed_; }
    void set_auto_generate(bool b) { autoGenerate_ = b; }
    bool get_auto_generate() const { return autoGenerate_; }
    void set_opaque_material(const Ref<Material>& m) { opaqueMat_ = m; }
    void prepararColorTextura();
    void aplicarColorTextura();
    void flushColorTextura(double dt);
    Ref<Material> get_opaque_material() const { return opaqueMat_; }
    void set_glass_material(const Ref<Material>& m) { glassMat_ = m; }
    Ref<Material> get_glass_material() const { return glassMat_; }
    void set_collision_layer(int l) { collisionLayer_ = l; }
    int get_collision_layer() const { return collisionLayer_; }
    void set_voxel_size(float v) { voxelSize_ = std::clamp(v, 0.05f, 1.0f); }
    // Anclas de física adicionales (bots, granadas...): sólo los chunks a menos de `radius` de alguna
    // ancla (o del jugador, radio interno) tienen cuerpo de colisión. Llamar cada frame desde el juego.
    void set_physics_anchors(const PackedVector3Array& points, float radius);
    // Escala de las distancias de LOD/render (1 = preset). Permite bajar distancia para ganar FPS.
    void set_diag_bloques(bool on);           // datos de diagnostico caros (ver get_stats)
    void set_view_distance_scale(float s);
    void set_debris_scale(float s);
    void set_piece_gravity(float s);
    float get_view_distance_scale() const { return viewScale_; }
    void set_render_distance_scale(float s);
    void set_lod_distance_scale(float s);
    // RESOLUCION LEJANA (2026-09-30): a cuantas veces la distancia del detalle fino empieza la malla LOD2 (voxels 4x).
    // 2 = lo de siempre; menos, lo lejano pierde resolucion antes y cuesta menos. (El valor vive en voxel_world.cpp,
    // fuera de la clase: no cambia su tamaño.)
    void set_lod2_factor(float f);
    void set_oclusion_rayos(int rayos);
    void set_ao_cerca(bool on);
    void oclusionRayos();
    // TRANSICION DE DETALLE SUAVE: metros de franja en los que dos niveles de detalle se mezclan por pixeles
    // (tramado segun la distancia, ver voxel.gdshader LOD_FADE). `cerca`: fina <-> LOD1; `lejos`: LOD1 <-> LOD2
    // (los arboles y casas de voxel grande). 0 y 0 = apagada (cambios de golpe, como siempre).
    void set_lod_fade_band(float cerca, float lejos);
    float get_render_distance_scale() const { return renderScale_; }
    float get_lod_distance_scale() const { return lodScale_; }
    // Occluders por región para la oclusión por software de Godot (requiere use_occlusion_culling).
    void set_use_occluders(bool b);
    // Derrumbe por sobrecarga (modelo de carga). Apagado: sólo cae lo que pierde apoyo.
    void set_structural_load(bool on) { structuralLoad_ = on; if (engine_) engine_->setLoadModel(on); }
    /// Segundos de descanso entre iteraciones del analisis de cargas (3 por defecto; 0 = seguido).
    void set_structural_sleep(float s) { structuralSleep_ = s; if (engine_) engine_->setStructuralSleep(s); }
    float get_structural_sleep() const { return structuralSleep_; }
    bool get_structural_load() const { return structuralLoad_; }
    bool get_use_occluders() const { return useOccluders_; }

    // --- ciclo de vida ---
    void generate_city(int seed);
    bool load_map(const PackedByteArray& data);
    Vector3 find_ground(const Vector3& p) const;
    PackedVector3Array get_spawn_points() const;
    bool is_loading() const { return loading_; }
    float get_loading_progress() const;

    // --- comandos de juego ---
    int explode(const Vector3& pos, float radius, int power);
    int crater_mundo(const Vector3& pos, float radius, int power);
    int carve_beam(const Vector3& origin, const Vector3& dir, float length, float radius, int power, bool vaporize = true,
                   const Vector3& empuje = Vector3());
    /// EMPUJA los bloques sueltos (los que caen o ruedan; no los parados ni los congelados) que haya a menos de
    /// `radio` de `centro`: se les suma `vel` (m/s). El puñetazo lo usa para los trozos que se desprenden por su tunel.
    int empujar_bloques(const Vector3& centro, float radio, const Vector3& vel);
    int carve_body(const RID& body, const Vector3& pos, float radius, int power);
    /// El mismo tajo por NUMERO DE BLOQUE y en SU rejilla: igual en todas las maquinas aunque cada una
    /// tenga el bloque en otra postura. -1 si ese bloque no existe aqui.
    int carve_body_id(int64_t id, const Vector3& local, float radius, int power);
    /// Un punto del mundo en la rejilla del bloque (metros desde la esquina de su rejilla).
    Vector3 punto_local_cuerpo(const RID& body, const Vector3& pos) const;
    Array get_effect_events() const { return effectEvents_; }
    Dictionary shoot(const Vector3& origin, const Vector3& dir, float max_dist, int power);
    Dictionary raycast(const Vector3& origin, const Vector3& dir, float max_dist) const;
    float get_material_capa(int mat) const;
    void set_debris_material(const Ref<Material>& m);
    PackedByteArray techo_filas(PackedByteArray datos, int tam, int x0, int x1, int za, int zb, float px, float pz, float desde, float altura) const;
    Dictionary raycast_con_piezas(const Vector3& origin, const Vector3& dir, float max_dist);
    /// Lo mismo que raycast_con_piezas hacia ABAJO, sin diccionarios (BotMotor: el suelo de los bots). Solo C++.
    bool suelo_con_piezas(const Vector3& origin, float max_dist, Vector3& pos) const;
    void set_player_position(const Vector3& p) { playerPos_ = p; }
    /// Donde estan los personajes (jugador, bots, remotos). Todo trozo que caiga cerca de uno de ellos
    /// lleva colision SI O SI, se revise cuando se revise: nadie debe atravesar lo que se le cae encima.
    void set_personajes(const PackedVector3Array& p) { personajes_ = p; }

    // --- IA ---
    PackedVector3Array find_path(const Vector3& from, const Vector3& to, int max_expansions = -1);
    bool has_line_of_sight(const Vector3& a, const Vector3& b) const;

    // --- oclusión volumétrica (ocupación de voxels en GPU: Texture2DArray de capas Z, 1 byte por celda de 2³/4³) ---
    // El shader de post-proceso (shaders/voxel_ao.gdshader) traza rayos cortos contra ella: sombras de contacto
    // y AO que responden a la destrucción sin remallar nada. Sólo se re-suben las capas de los chunks que cambian.
    void set_occlusion_volume(bool on);
    bool get_occlusion_volume() const { return occEnabled_; }
    void bind_occupancy_to_material(const Ref<Material>& m);   // pone la textura y sus dimensiones en el material
    Dictionary get_occupancy_info() const;

    // --- consultas ---
    Dictionary get_stats() const;
    void set_compress_attributes(bool on);
    void set_shadow_light_dir(const Vector3& d);
    // SOMBRA DEL SOL HORNEADA en la propia malla (calidad Baja / movil): sin coste de GPU, sin mapa de
    // sombras en tiempo real. dir_hacia_sol apunta HACIA el sol (signo contrario al de shadow_light_dir).
    void set_faldas_lod(bool on);   // faldas de las LOD (ver Engine::setFaldasLod)
    void set_sol_horneado(bool on, const Vector3& dir_hacia_sol, float alcance_m);
    Array audit_floaters();
    Array bodies_info();   // pruebas: cada bloque con voxels, posicion y estado
    bool puntoEnBloqueParado(const vx::Vec3& p) const;
    bool weldOn_ = false;             // soldar flotadores al cargar: solo donde el juego lo pida (Monaco)
    void set_weld_floaters(bool on) { weldOn_ = on; }
    bool welded_ = false;             // ya se soldaron los flotadores de este mapa (se hace una vez, al cargar)
    int weldedFloaters_ = 0, weldSinSoldar_ = 0, weldVoxels_ = 0;
    // Depuración del analizador estructural (Fase 31): celdas evaluadas de la última iteración con su ratio
    // carga/capacidad, estado, isla, carga y capacidad; islas con centro de masas y apoyo; región. Sólo para
    // el modo desarrollador (main.gd F11); vacío si no hay análisis activo.
    Dictionary get_struct_debug() const;
    void set_struct_debug_enabled(bool on);
    // Parámetros del analizador (afinado en vivo desde el editor/consola): ver vx::StructParams.
    void set_struct_param(const String& name, float value);
    float get_struct_param(const String& name) const;
    Vector3 get_spawn_position() const;
    PackedVector3Array get_building_centers() const;
    PackedVector3Array get_street_points() const;
    Vector3 get_world_size() const;
    int get_material_at(const Vector3& p) const;
    // ¿Hay algún voxel sólido dentro de la caja [min,max] (metros)? Para controladores de personaje
    // sobre la rejilla (bots): una llamada en vez de decenas de get_material_at.
    bool box_solid(const Vector3& bmin, const Vector3& bmax) const;
    int contar_voxels(const Vector3& bmin, const Vector3& bmax) const;
    Color get_material_color(int mat) const;
    String get_material_name(int mat) const;
    Dictionary get_material_info(int mat) const;   // dureza, densidad, flags, soporte (diagnóstico)
    float get_voxel_size() const { return voxelSize_; }
    int get_body_count() const { return static_cast<int>(bodies_.size()); }
    Array get_bodies_debug() const;
    // Tope de piezas "baratas" con cuerpo cinemático (solidez sin simulación). -1 = automático.
    void set_clump_scale(float s);
    /// PRISA DE LOS CASCOTES (0-1): cuanto antes se paran y se duermen los trozos PEQUEÑOS de una explosion. La pone
    /// el juego segun los fps (por debajo de 60 sube); el motor ademas la sube solo si hay muchos moviendose.
    void set_prisa_escombros(float k);
    float get_clump_scale() const;
    void set_cheap_solid_max(int n) { cheapSolidMax_ = n; }
    // SOLO PARA MEDIR (banco --bancofps --sinfisica): apaga el rehacer colisiones del mundo, para saber
    // cuanto de la fisica se va en eso y cuanto en simular de verdad.
    void set_phys_updates(bool on) { physUpdatesOn_ = on; }
    int get_cheap_solid_max() const { return cheapSolidMax_; }
    float get_lod_distance() const { return lodNear_; }
    float get_render_distance() const { return renderDist_; }

    void _on_body_state(PhysicsDirectBodyState3D* state, const RID& body);
    void _ready() override;
    void _process(double delta) override;
    void _exit_tree() override;

protected:
    static void _bind_methods();

private:
    static constexpr int REGION = 4;   // chunks por lado de una región
    static constexpr int BLOCK = 2;    // chunks por lado de un bloque cercano (REGION debe ser múltiplo)

    struct ChunkVis {
        RID body, shape;              // colisión estática (sólo cerca de una ancla)
        int tris = 0;
        bool hasMesh = false, hasPhys = false, physQueued = false;
    };
    struct BlockVis {
        RID mesh, inst;
        int tris = 0;
        bool dirty = false;
        bool shown = false;           // visible = su región está en estado 0
        // LEJOS SIN MALLA (2026-10-01): su region se ve con LOD2 o no se ve, asi que su malla fina no se dibuja; se
        // suelta (en la isla eran 4,9 M de triangulos en la GPU, que en una integrada o un movil es RAM) y se rehace
        // al acercarse (`pendiente` hasta que llega: mientras, la region sigue enseñando su LOD1).
        bool lejos = false;
        bool pendiente = false;
    };
    struct Anchor { Vector3 p; float r; };
    struct RegionVis {
        RID mesh1, inst1, mesh2, inst2;
        RID occ, occInst;             // occluder conservador (oclusión por software de Godot)
        RID shMesh, shInst;           // caster de sombras fusionado (geometría COMPLETA de sus chunks, sólo sombras)
        int tris1 = 0, tris2 = 0, occTris = 0, shTris = 0;
        int members = 0;              // chunks con malla dentro
        bool dirty = false;
        uint64_t dirtyFrame = 0;      // último frame en que se marcó sucia (debounce del remallado)
        bool lodStale = false;        // sus mallas LOD no estan al dia (se aplazo el remallado por no verse: ver flushRegions)
        bool casterStale = false;     // su caster de sombras se hizo con otra direccion de luz (ver set_shadow_light_dir)
        bool enColaSombra = false;    // esperando en colaSombras_ a que se rehaga su caster
        int state = -1;               // 0 = chunks completos, 1 = LOD, 2 = LOD2, 3 = oculta
        bool vis1 = false;            // su malla LOD1 se ve (en estado 1, o en 0 con la transicion suave)
        bool vis2 = false;            // su malla LOD2 se ve (en estado 2, o en 0/1 con la transicion suave)
    };
    float prisaEscombros_ = 0.f;   ///< set_prisa_escombros (lo que dice el juego por los fps)
    int despiertosAnt_ = 0;        ///< trozos pequeños despiertos en el paso anterior (la prisa propia del motor)
    float prisaUsada_ = 0.f;       ///< la que se aplico en el ultimo paso (para las estadisticas)
    struct Body {
        vx::VoxelBody data;
        RID mesh, inst, body;
        std::vector<RID> shapes;
        bool rigid = false;
        bool solid = false;            // tiene cuerpo en el servidor de física (rígido o cinemático)
        Vector3 drift;                 // m/s: empuje lateral de los cuerpos baratos (heredado de initialVel)
        Vector3 pos;
        // DONDE EMPIEZA SU TEXTURA DE DETALLE (solo dibujo): vertice local + texOrg = posicion del voxel en la rejilla
        // de la que salio. Asi el trozo que se suelta sigue con el mismo dibujo que tenia en la pared (voxel.gdshader,
        // `tex_bloque`), y al tallarlo no se corre (reconstruirCuerpo).
        Vector3 texOrg;
        // estado del cuerpo rígido recibido por callback de sincronización (sin llamadas bloqueantes al
        // servidor de físicas: compatible con la física en hilo aparte)
        Transform3D xf; Vector3 linVel; bool sleeping = false;
        Transform3D xfAnt; bool xfAntOk = false;   // la postura del paso de fisica anterior (--fisica30: se dibuja entre las dos)
        float vy = 0, sleep = 0, age = 0;
        float quieto = 0;              // segundos casi sin moverse (lo diga Jolt o no: ver stepBodies)
        float yMax = -1e9f;            // altura maxima desde que se solto o desde el ultimo asiento: mide la caida real para el impacto
        bool alMundo = false;          // se ha dormido y ya esta re-voxelizado en el mundo: el bucle libera el cuerpo
        float gravEscala = 1.f;        // camara lenta progresiva: escala de gravedad puesta en Jolt
        int vuelcos = 0;               // veces que se le ha despertado por vuelco o por tacos sueltos (tope 2)
        bool reasentarPronto = false;  // acaba de reventar su apoyo: se vuelve a juzgar en cuanto se pare, sin esperar el sueno largo
        bool resting = false;
        // UN CASCOTE GRANDE PARADO NO SE EMPUJA A PATADAS. El personaje es un cuerpo cinematico, o sea
        // de masa infinita para el solver: caminando contra una losa de dos toneladas la movia como si
        // fuera un carton. Al pararse, los trozos grandes pasan a estaticos (aqui: `anclado`) y ya no
        // los mueve nadie; una explosion los vuelve a soltar.
        bool anclado = false;
        // DONDE NACIO. Un trozo que cede y se queda EXACTAMENTE donde estaba no se puede volver a
        // congelar enseguida: al hacerlo se restauran los mismos voxels, el analizador vuelve a
        // encontrarlos sobrecargados y los vuelve a soltar. Eso es el "se rompe y se reconstruye" en
        // bucle, que ademas cuesta un analisis + una extraccion + un remallado por vuelta.
        Vector3 origen;
        // TALLADO PENDIENTE DE RECONSTRUIR. Quitar voxels de un trozo es barato; rehacer su malla, su
        // descomposicion en cajas y sus formas de Jolt no lo es, y eso se hacia EN CADA BALA. Con un
        // fusil sobre un cascote grande salian 10 reconstrucciones completas por segundo: ese era el
        // tiron. Ahora el tallado solo marca, y la reconstruccion va aparte con presupuesto por frame.
        bool reconstruir = false;
        // CONGELADO CON SU POSTURA. Un trozo que se para TORCIDO no puede volver a la rejilla del
        // mundo sin cambiar de forma: la rejilla no esta girada, asi que `Engine::revoxelize` tiene
        // que repintarlo celda a celda y los bordes salen en escalera. Se veia como que el escombro
        // "cambiaba de forma" justo al pararse. Estos se quedan como cuerpo estatico para siempre,
        // con su malla y su angulo exactos, y no se re-voxelizan nunca. Los que quedan casi rectos
        // no hacen falta: se les cuadra el giro al multiplo de 90 (que en una rejilla es EXACTO, no
        // mueve ni un voxel) y esos si vuelven al mundo.
        bool congelado = false;
        // A QUE GRUPO DE RENDER PERTENECE (0 = ninguno, dibuja por su cuenta). Un trozo congelado no
        // desaparece nunca, y cada uno con su instancia son N draw calls para siempre: medido, 111
        // cuerpos tras seis explosiones en el mapa de pruebas. Los congelados de una misma celda de
        // 16 m se dibujan con UNA malla comun. Su fisica sigue siendo suya (`body`), asi que picarlos
        // con el mazo, tallarlos a tiros y despegarlos con una explosion funciona igual que antes.
        uint64_t grupo = 0;
        // SEGUNDOS EN LOS QUE NO PUEDE VOLVER A DORMIRSE. Al recibir un golpe, un bloque se despierta
        // pero si tiene algo debajo se queda quieto en el acto, su reloj de sueño corre y se vuelve a
        // dormir enseguida: no le da tiempo a caerse. Con este margen se le deja SUELTO un rato para
        // que la fisica resuelva de verdad si se sostiene o no.
        float gracia = 0.f;
        // LO MUEVE EL ANFITRION (solo en el invitado). Un bloque grande que cae se simulaba en cada maquina por
        // su cuenta y solo viajaba la postura final: por internet, con el daño llegando 100-300 ms despues,
        // cada pantalla lo veia caer distinto. Mientras llegan posturas (`seguir_posturas`) es cinematico y
        // va hacia `objetivo`; si deja de llegar postura `SEGUIR_SUELTA_S`, vuelve a ser rigido y sigue solo.
        bool siguiendo = false;
        Transform3D objetivo;
        Vector3 objetivoVel;           // velocidad que traia la postura: el objetivo se adelanta con ella (sin retraso)
        float sinPostura = 0.f;
    };

    /// Malla comun de los trozos congelados de una celda. Solo render: ni colision ni voxels.
    struct GrupoCongelado {
        RID mesh, inst;
        bool sucio = false;
        int piezas = 0;
        uint64_t ver = 0;             // la malla que se esta subiendo en el hilo (rehacerUnGrupo); otra mas nueva la anula
    };

    // EN LAN, DONDE ACABA CADA ESCOMBRO LO DICE EL ANFITRION. La destruccion se replica y sale igual
    // en todas las maquinas, pero los trozos caen por fisica y ninguna fisica cae igual que otra: al
    // congelarse quedaban en sitios distintos y el mapa se iba separando (uno tenia cobertura donde
    // otro veia el hueco). El identificador de un trozo es un hash de donde estaba, asi que es el
    // mismo en todas partes: el anfitrion avisa "el trozo N se queda aqui" y los demas lo colocan ahi.
    void set_settle_authority(bool manda);
    bool get_settle_authority() const { return settleAuthority_; }
    /// Coloca en la rejilla los escombros que manda el anfitrion: caja de celdas y un material por
    /// celda (0 = aire). Es lo que hace que el mapa acabe IGUAL en todas las maquinas.
    void place_settled(const Vector3i& origen, const Vector3i& tam, const PackedByteArray& mats);
    bool settleAuthority_ = true;
    bool interpolar_ = false;      // --fisica30: la fisica a 30 Hz, los bloques se dibujan interpolados y con tope de velocidad

    // Y LO QUE SE DESPRENDE, TAMBIEN. El asentamiento ya venia del anfitrion, pero la decision de
    // QUE se separa la tomaba cada maquina con su solver, que va por tiempo: medido en banco, el
    // invitado acababa siempre con voxels de mas (lo que al anfitrion se le cayo, a el no). Ahora el
    // anfitrion avisa celda a celda de cada trozo que suelta y el invitado suelta exactamente esos.
    void set_red(bool en_red, bool soy_host);
    void set_interpolar(bool si);
    /// Los derrumbes por carga que ha decidido esta maquina (anfitrion) desde la ultima vez, para mandarlos:
    /// [{celdas: PackedInt32Array (min xyz, max xyz por celda), tilt: Vector3, com: Vector3, masa: float, isla: int}]
    Array tomar_fallos_estructurales();
    /// Aplica un derrumbe por carga que ha decidido el anfitrion.
    void aplicar_fallo_estructural(const PackedInt32Array& celdas, const Vector3& tilt, const Vector3& com, float masa, int isla);
    /// Los voxels de apoyo que han reventado aqui bajo un bloque desde la ultima vez (x,y,z seguidos), para mandarlos.
    PackedInt32Array tomar_apoyos_rotos();
    /// Revienta los apoyos que ha decidido el anfitrion (x,y,z seguidos).
    void romper_apoyos(const PackedInt32Array& voxels);
    /// RECONCILIACION DE BLOQUES EN RED. [id, voxels | (congelado << 40), ...] de todos los bloques.
    PackedInt64Array censo_bloques() const;
    /// La forma y la postura de un bloque QUIETO, para mandarla ("" si no existe o se mueve).
    PackedByteArray datos_bloque(int64_t id) const;
    /// Crea (o rehace) el bloque `id` con los datos del anfitrion, congelado en su postura.
    bool crear_bloque(int64_t id, const PackedByteArray& datos);
    /// Quita los bloques con ese id. Devuelve cuantos.
    int quitar_bloque(int64_t id);
    PackedInt64Array recortar_escombros(int tope, const Vector3& pos, const Vector3& dir, int max_quitar);
    void set_tope_despiertos(int n);
    RID get_debris_instance() const { return debrisInst_; }
    PackedInt64Array limpiar_escombros(float min_m3, float max_m3, float s_fuera, float s_vista, const Vector3& pos, const Vector3& dir, int max_quitar, bool despertar);
    /// RECONCILIACION DEL MAPA EN RED. Abre una ronda y devuelve [indice, huella, cambiado, ...] de los chunks
    /// tocados (no intactos). Huella 0 = se estaba editando al leerlo; cambiado 1 = distinto que en la ronda anterior.
    PackedInt64Array huellas_chunks();
    /// [huella, cambiado] de un chunk cualquiera en la ronda actual.
    PackedInt64Array huella_chunk(int indice);
    /// Los voxels de un chunk (32.768 bytes) y un byte final: 1 si esta intacto.
    PackedByteArray datos_chunk(int indice) const;
    /// Deja el chunk como en `datos` cambiando SOLO los voxels que difieren. Devuelve cuantos.
    int aplicar_chunk(int indice, const PackedByteArray& datos);
    /// Suelta del mundo las celdas que manda el anfitrion y crea el trozo que cae. `mascara` lleva un
    /// bit por celda de la caja (indice x + y*tam.x + z*tam.x*tam.y).
    void place_frozen(int64_t id, const Transform3D& xf);
    /// Anfitrion: [PackedInt64Array ids, PackedFloat32Array posturas (10 por bloque: origen, cuaternio, velocidad)] de los
    /// bloques rigidos de al menos `min_voxels` que se estan moviendo.
    Array posturas_en_vuelo(int min_voxels, bool quietos = false) const;
    /// Invitado: los bloques con esos ids pasan a seguir la postura del anfitrion.
    void seguir_posturas(const PackedInt64Array& ids, const PackedFloat32Array& poses);
    Dictionary info_cuerpo(const RID& rid) const;
    void place_detached(const Vector3i& origen, const Vector3i& tam, const PackedByteArray& mascara,
                        const Vector3& vel, const Vector3& ang_vel);
    bool enRed_ = false;
    bool soyHost_ = true;
    uint32_t redPieceId_ = 0x40000000u;   // ids de los trozos que llegan por red: fuera del rango del motor
    // contadores de la sincronizacion (get_stats): con esto se ve de un vistazo si lo que manda el
    // anfitrion es exactamente lo que aplica el invitado
    int64_t celdasSueltasSolidas_ = 0, celdasSueltasYaAire_ = 0, tallasCuerpo_ = 0;
    // el reloj de la simulacion de escombros: fijo, para que no dependa de los fotogramas
    static constexpr float PASO_FIJO = 1.0f / 60.0f;
    static constexpr int MAX_PASOS_FIJOS = 8;
    float pasoAcum_ = 0.0f;
    uint64_t pasosTotales_ = 0;   // pasos de simulacion dados: lo que escalona el trabajo por frames
    int64_t sueltasOut_ = 0, sueltasIn_ = 0, celdasSueltasOut_ = 0, celdasSueltasIn_ = 0;
    int64_t asientosOut_ = 0, celdasAsientoOut_ = 0, celdasAsientoIn_ = 0, celdasAsientoSalt_ = 0;
    int carve_body_near(const Vector3& pos, float radius, int power);
    Array resumen_chunks() const;
    void avisarSuelta(const vx::VoxelBody& pieza);
    void emitirAsiento(const vx::VoxelBody& datos, const vx::Transform& tr);

    void createEngine();
    void destroyEngine();
    void ensureMaterials();
    void ensureDebris();
    void ensureSmoke();
    void updateSmoke();
    void set_smoke_material(const Ref<Material>& m);
    Array get_smoke_debug(int n) const;
    void emit_smoke(const Vector3& pos, int count, float radius, float speed, const Color& color, float life, float r0, float r1, float buoy);
    void updateDistances();
    void uploadChunk(vx::ChunkMeshResult& r);
    int addSurface(const RID& mesh, const vx::MeshData& md, const std::vector<uint32_t>& indices, const Ref<Material>& mat, int surfaceIndex);
    void queuePhysics(uint32_t idx);
    void flushPhysics(int budget);
    void freePhys(ChunkVis& c);
    void updatePhysicsBodies();
    void spawnPiece(vx::VoxelBody&& piece);
    // Radio alrededor de un personaje dentro del cual TODO trozo lleva colision.
    static constexpr float RADIO_SOLIDO = 12.0f;
    bool cercaDeAlguien(const Vector3& p, float r) const;
    void solidificarCerca();
    float rayCuerpo(const Body& b, const Vector3& origin, const Vector3& dir, float maxDist, Vector3& outPos) const;
    void reconstruirCuerpo(Body& b, vx::VoxelBody* hecho = nullptr);
    void recogerCuerposHechos();
    void reconstruirPendientes(int maxPorFrame);
    int carveBodyAt(Body& b, const Vector3& pos, float radius, int power, bool falloff, bool& destroyed);
    int carveBodyAtLocal(Body& b, const Vector3& local, float radius, int power, bool falloff, bool& destroyed);
    void pushEffect(const char* type, const Vector3& pos, float size, int mat);
    void freeBody(Body& b);
    /// Un trozo se ha parado. O vuelve a la rejilla del mundo (solo si su giro se puede cuadrar a un
    /// multiplo de 90, que es exacto y no le cambia un voxel) o se queda CONGELADO como cuerpo
    /// estatico con su postura tal cual. Devuelve true si se congelo (el llamante lo deja en la
    /// lista) y false si volvio al mundo (el llamante lo libera).
    bool asentarPieza(Body& b, const Transform3D& t);
    void congelarPieza(Body& b, const Transform3D& t);
    void crearColisionFina(Body& b, const Transform3D& t);
    void despertarBloque(Body& b);
    void despertarSobre(const Vector3& centro, float radio);
    float sueloBajo(const Vector3& p, float alcance, const Body* excluir) const;
    bool apoyoSuficiente(const Body& b, const Transform3D& t, std::vector<vx::IVec3>& flojos, float impacto = 1.f, Vector3* outMn = nullptr, Vector3* outMx = nullptr) const;
    int64_t apoyosRotos_ = 0;
    std::vector<vx::IVec3> apoyosRotosPend_;   // en red, anfitrion: apoyos reventados aun sin mandar
    bool creandoDeRed_ = false;                // crear_bloque: nace sin despertar vecinos ni avisar al juego
    struct HuellaChunk { uint32_t version = 0; uint64_t hash = 0; uint32_t ronda = 0; };
    std::vector<HuellaChunk> huellasChunk_;    // cache de huellas por chunk (se rehace al cambiar la version)
    uint32_t rondaHuellas_ = 1;
    uint64_t huellaDe(int indice, bool& cambiado);
    void separarPedazos(Body& b, const Transform3D& t, std::vector<std::vector<vx::BodyVoxel>>& fuera, std::vector<uint32_t>& ids);
    uint64_t claveGrupo(const Vector3& p) const;
    void ensuciarGrupo(uint64_t clave);
    void rehacerUnGrupo();
    void sacarDelGrupo(Body& b);
    std::unordered_map<uint64_t, GrupoCongelado> gruposCongelados_;
    /// Posturas de congelado que han llegado ANTES que su trozo. La cola de piezas se drena con
    /// presupuesto de tiempo (5 ms/frame), asi que el aviso del anfitrion puede adelantar al
    /// nacimiento de la pieza en el invitado. Sin esto ese trozo se perdia para siempre: el
    /// anfitrion lo veia en el suelo y el invitado no lo tenia (contador `congel_desconocidos`).
    std::unordered_map<int64_t, Transform3D> congelPendientes_;
    int64_t cajasCongelado_ = 0;
    int64_t congelDesconocidos_ = 0;
    int congeladosVivos_ = 0;   // cuantos hay congelados: no cuentan para el presupuesto de cuerpos
    float rayCheapBody(const Body& b, const Vector3& origin, const Vector3& dir, float maxDist, Vector3& outPos, int& outMat) const;
    float tExplodeCore_ = 0.f, tExplodeTotal_ = 0.f;
    std::vector<vx::VoxelBody> pendingPieces_;
    float phaseT_ = 0.f, tHUpdate_ = 0.f, tHUpload_ = 0.f, tHBlocks_ = 0.f, tHRegions_ = 0.f, tHPhys_ = 0.f, tHSpawn_ = 0.f, tHBodies_ = 0.f, tHDebris_ = 0.f;
    void stepBodies(float dt);
    void updateDebris();
    void updateLod();
    void freeChunk(ChunkVis& c, uint32_t idx);
    // regiones
    int regionOfChunk(int chunkIdx) const;
    Vector3 regionOrigin(int r) const;
    void rebuildRegion(int r);
    void rebuildOccluder(int r);
    void rebuildShadowCaster(int r);
    const vx::MeshData& sombraDe(int ci) const;
    bool regionCastsShadows(int state) const;
    void flushRegions(int budget);
    void freeRegion(RegionVis& rg);
    // bloques
    int blockOfChunk(int chunkIdx) const;
    Vector3 blockOrigin(int b) const;
    void rebuildBlock(int b);
    void flushBlocks(int budget);
    void freeBlock(BlockVis& bl);
    void setBlockShown(int b, bool shown);
    void markBlockDirty(int b);
    static vx::Transform toVx(const Transform3D& t);
    static Transform3D fromVx(const vx::Vec3& p);

    std::unique_ptr<vx::Engine> engine_;
    vx::CityInfo city_;
    PackedVector3Array mapSpawns_;
    std::vector<ChunkVis> chunks_;
    std::vector<vx::MeshData> chunkLod1_, chunkLod2_;   // datos LOD por chunk (para fusionar regiones)
    std::vector<vx::MeshData> chunkOcc_;                // malla occluder por chunk (conservadora)
    std::vector<vx::MeshData> chunkSh_;                 // malla de SOMBRA por chunk (forma sin colores ni cristal)
    std::vector<vx::MeshData> chunkFull_;               // malla completa por chunk (bloques, sombras)
    // malla de colision por chunk (Mesher::soloForma), COMPACTA: los triangulos seguidos, 3 vertices x 3 bytes con la
    // posicion en voxels del chunk (0..32). Vacia = usar chunkFull_. Guardada como MeshData eran 138 MB en la isla.
    std::vector<std::vector<uint8_t>> chunkCol_;
    // CASTERS DE SOMBRA POR HACER (2026-10-01): una region que deja de proyectar suelta su malla de sombra (en la isla
    // eran 380 mallas con 4 M de triangulos y solo 45 en uso) y, al volver a proyectar, se rehace desde aqui con un tope
    // de tiempo por fotograma en vez de todas de golpe al cruzar una frontera de regiones.
    std::vector<int> colaSombras_;
    void liberarSombra(RegionVis& rg);
    int regionDeBloque(int b) const;
    void soltarBloqueLejos(int b);
    bool regionConBloquesPendientes(int r) const;
    // desde que estado de region se sueltan las mallas finas de sus bloques: 3 (de fabrica) = solo las regiones que no
    // se dibujan, sin ningun cambio visible; 2 = tambien las que se ven con LOD2 (en la isla, -200 MB de la GPU) a
    // cambio de ver la LOD1 cerca 0,2-0,9 s tras un salto lejano (reaparecer). 4 = nunca.
    int estadoSoltar_ = 3;
public:
    void set_soltar_bloques(int estado_minimo);
    int get_soltar_bloques() const { return estadoSoltar_; }
private:
    void encolarSombra(int r);
    void flushSombras(double tope_ms);
    std::vector<uint32_t> chunkColVer_;                 // version de voxels de la ultima malla recibida (ver uploadChunk)
    PackedVector3Array shVerts_; PackedInt32Array shIdx_;
    std::vector<BlockVis> blocks_;
    int bnx_ = 0, bny_ = 0, bnz_ = 0;
    std::vector<int> dirtyBlocks_;
    std::vector<Anchor> anchors_;                       // anclas de física del frame (jugador + externas + piezas)
    PackedVector3Array extAnchors_;
    float extAnchorRadius_ = 10.f;
    PackedVector3Array personajes_;   // jugador + bots + remotos (ver set_personajes)
    float physRadius_ = 24.f;                           // radio de colisión alrededor del jugador (m)
    int staticBodies_ = 0;
    PackedVector3Array occVerts_; PackedInt32Array occIdx_;
    bool useOccluders_ = true;
    Vector3 shadowLightDir_;          // direccion en que viaja la luz del sol (cero = sin recorte de caras en el caster)
    bool structuralLoad_ = false;
    float structuralSleep_ = 3.0f;
    long long occTris_ = 0;
    std::vector<RegionVis> regions_;
    int rnx_ = 0, rny_ = 0, rnz_ = 0;
    std::vector<int> dirtyRegions_;
    vx::MeshData mergeScratch_;
    // LAS MALLAS DE LOS BLOQUES SE PREPARAN EN OTRO HILO (2026-09-28). Medido en el banco de Monaco: al demoler,
    // `mesh_add_surface_from_arrays` de un bloque de 40.000 vertices se comia 20 ms del hilo principal, y era el
    // mayor tiron de la destruccion. Ahora el hilo principal solo junta los vertices (barato); un hilo aparte
    // crea una malla NUEVA y hace alli `mesh_add_surface_from_arrays` (el servidor de render admite llamadas desde
    // otros hilos: la conversion, que es lo caro, se hace en ese hilo, y la subida queda en su cola). El hilo
    // principal cambia el bloque a la malla nueva dos cuadros despues, cuando la cola ya se ha vaciado: hasta
    // entonces se ve la vieja, sin parpadeo. Si el bloque cambia otra vez entretanto, la nueva se tira (version).
    // VX_BLOQUES_SYNC=1 lo vuelve a hacer como antes (para medir).
    // LAS REGIONES TAMBIEN (2026-10-02, medido en la cafeteria con --perfmapa: tras cada rotura la region rehacia y
    // subia sus mallas LOD en el hilo principal, 18-27 ms en un cuadro, y eran los tirones de 25-45 ms que se repetian
    // demoliendo). Mismo camino que los bloques: `region` >= 0 y `level` (0 = LOD1, 1 = LOD2), con `regionVer_`.
    struct BlockJob {
        int block = -1; uint64_t ver = 0; vx::MeshData md;
        RID matO, matG, mesh; int tris = 0; uint64_t listo = 0;   // `listo`: cuadro en que volvio del hilo
        int region = -1; int level = 0;
        // Y LOS GRUPOS CONGELADOS (2026-10-02, misma razon: fundir un grupo grande y subirlo eran los picos de 10-14 ms de
        // la fase `spawn` demoliendo): `grupo` != 0, los arrays ya hechos y que trozos van dentro (`ids`)
        uint64_t grupo = 0; Array arrO, arrG; Vector3 origen; std::vector<uint32_t> ids;
        // Y LA MALLA DE UN BLOQUE GRANDE TALLADO (2026-10-11, reconstruirCuerpo): `cuerpo` = su id
        uint32_t cuerpo = 0;
    };
    std::vector<BlockJob> blockSwap_;   // vueltos del hilo, esperando a que el servidor de render vacie su cola
    std::thread blockWorker_;
    std::mutex blockMx_;
    std::condition_variable blockCv_;
    std::deque<BlockJob> blockIn_, blockOut_;
    bool blockStop_ = false;
    bool asyncBlocks_ = true;
    std::vector<uint64_t> blockVer_;
    std::vector<uint64_t> regionVer_;   // version de cada malla LOD de region (region * 2 + nivel)
    void blockWorkerLoop();
    void stopBlockWorker();
    void drainBlockJobs();
    std::vector<Body> bodies_;
    std::vector<uint32_t> physQueue_;
    vx::BodyBuilder bodyBuilder_;
    std::vector<vx::BodyVoxel> bodyScratch_;
    Array effectEvents_;

    // ocupación en GPU
    bool occEnabled_ = false;
    RID occTex_;
    int occDims_[3] = {0, 0, 0};
    int occCell_ = 2;                                   // voxels por celda (2 ó 4 según tamaño del mundo)
    std::vector<uint8_t> occLayerDirty_;
    std::vector<int> occDirtyList_;
    PackedByteArray occScratch_;
    int occUploadsThisFrame_ = 0;
    void occInit();
    void occFree();
    void occMarkChunk(int chunkIdx);
    void occFlush(int budget);
    RID debrisMultimesh_, debrisInst_, debrisMesh_;
    RID smokeMultimesh_, smokeInst_, smokeMesh_;
    PackedFloat32Array smokeBuffer_;
    int smokeCapacity_ = 0;
    Ref<Material> smokeMat_;
    PackedFloat32Array debrisBuffer_;
    int debrisCapacity_ = 0;
    Basis debrisRot_[16];

    Ref<Material> opaqueMat_, glassMat_, debrisMat_;
    int quality_ = 1;
    Vector3i chunkDims_ = Vector3i(20, 4, 20);
    int seed_ = 1234;
    bool autoGenerate_ = true;
    float voxelSize_ = 0.25f;
    int collisionLayer_ = 1;
    float viewScale_ = 1.0f;
    float renderScale_ = 1.0f;    // hasta donde se dibuja (cuantos chunks entran en pantalla)
    float lodFadeBand_ = 0.0f;    // franja de la transicion suave fina <-> LOD1 (m)
    float lodFadeBand2_ = 0.0f;   // franja de la transicion suave LOD1 <-> LOD2 (m)
    // LA FRANJA VA HACIA DENTRO DEL LIMITE, no hacia fuera (2026-09-22): el cambio TERMINA donde antes saltaba
    // de golpe, asi que a igual distancia nunca se ve menos detalle que sin la transicion. Al reves -que fue
    // como se hizo primero- la malla gruesa se metia varios metros mas cerca y todo se veia gordo.
    bool lodFadeOn() const { return lodFadeBand_ > 0.0f || lodFadeBand2_ > 0.0f; }
    float fade1Ini() const { return std::max(lodNear_ - lodFadeBand_, 0.5f); }
    float fade1Fin() const { return std::max(lodNear_, fade1Ini() + 0.01f); }
    float fade2Ini() const { return std::max(lodFar_ - lodFadeBand2_, fade1Fin()); }
    float fade2Fin() const { return std::max(lodFar_, fade2Ini() + 0.01f); }
    float lodScale_ = 1.0f;       // hasta donde se dibuja con la malla FINA (dentro, malla de 20 cm)
    float debrisScale_ = 1.0f;
    float pieceGravity_ = 0.36f;   // derrumbes a camara lenta
    /// Gravedad de un trozo segun su tamano: los bloques grandes caen MAS despacio. En la vida real
    /// una fachada de veinte metros parece caer a camara lenta (el ojo la juzga por su tamano), y en
    /// el juego ademas da tiempo a apartarse, que es de lo que se trata.
    float pieceGravityFor(int voxels) const {
        (void)voxels;
        return 1.0f;   // 2026-09-18: sin camara lenta, todo cae a su velocidad real (pedido). Era 0,36 a 0,14 g.
    }
    float lodNear_ = 48.f, lodFar_ = 120.f, renderDist_ = 140.f;
    Vector3 playerPos_;
    bool loading_ = false;
    bool generated_ = false;
    int initialChunks_ = 0;
    uint32_t frame_ = 0;
    int physUpdatesThisFrame_ = 0;
    int visibleChunks_ = 0, visibleRegions_ = 0;
    long long visibleTris_ = 0;
    // totales de triangulos en cache (ver get_stats): recorrerlos entero cuesta 16 ms en un mapa grande
    mutable uint64_t statsFrame_ = 0;
    mutable long long statsTrisTotal_ = 0;
    mutable long long statsShadowTris_ = 0;
    mutable long long statsOccluderTris_ = 0;
    mutable int statsOccluders_ = 0;
    bool diagBloques_ = false;
    int rigidCount_ = 0, cheapCount_ = 0, cheapSolidCount_ = 0;
    int spawnRigid_ = 0, spawnCheapSolid_ = 0, spawnCheapGhost_ = 0, spawnInstant_ = 0;
    int cheapSolidMax_ = -1;
    bool physUpdatesOn_ = true;
    int removedRevox_ = 0, removedAge_ = 0, removedVoid_ = 0, removedCarve_ = 0;
    double lastProcessMs_ = 0, maxProcessMs_ = 0;
};

} // namespace godot
