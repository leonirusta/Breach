// vxstructtest - Pruebas del sistema estructural (Fase 34) + equivalencia del raycast jerárquico
// ---------------------------------------------------------------------------
// Cada escenario construye estructuras sintéticas, aplica daño y comprueba QUÉ cae y qué NO. El objetivo
// principal es cazar falsos derrumbes globales: el edificio vecino no puede caer, un daño menor no puede
// tirar un edificio entero, quitar un apoyo de diez no tira el forjado.
// Salida: PASS/FAIL por consola. Voxel de 25 cm (los presets están calibrados así).
// ---------------------------------------------------------------------------
#include "vx/vx_engine.h"
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <vector>
#include <algorithm>
#include <string>

using namespace vx;

static int g_fail = 0, g_pass = 0;
#define CHECK(cond) do { if (cond) { ++g_pass; } else { ++g_fail; printf("  FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond); } } while (0)
#define CHECKM(cond, ...) do { if (cond) { ++g_pass; } else { ++g_fail; printf("  FAIL %s:%d  %s  (", __FILE__, __LINE__, #cond); printf(__VA_ARGS__); printf(")\n"); } } while (0)
#define TEST(name) printf("[test] %s\n", name)

namespace {

struct Scene {
    EngineConfig cfg;
    std::unique_ptr<Engine> e;
    Scene(int cx, int cy, int cz, bool load = true, float vs = 0.f) {
        cfg.chunksX = cx; cfg.chunksY = cy; cfg.chunksZ = cz; cfg.threads = 3; cfg.quality = Quality::High; cfg.loadModel = load;
        if (vs > 0.f) cfg.voxelSize = vs;
        e.reset(new Engine(cfg));
        World& w = e->world();
        w.fillBox(IVec3(0, 0, 0), IVec3(w.sizeX() - 1, 0, w.sizeZ() - 1), MAT_GROUND);
    }
    World& w() { return e->world(); }
    // deja el mundo "en juego": lo que flota puede caer; el análisis se abre con las explosiones
    void settle() { w().clearPristine(); e->markAllDirty(); std::vector<VoxelBody> p; e->waitIdle(nullptr, &p); }
    uint32_t run(std::vector<VoxelBody>* out = nullptr) { std::vector<VoxelBody> p; e->waitIdle(nullptr, &p); uint32_t n = 0; for (auto& b : p) n += b.voxelCount; if (out) for (auto& b : p) out->push_back(std::move(b)); return n; }
};

// cuenta voxels sólidos no ancla en una caja
uint64_t countBox(const World& w, IVec3 a, IVec3 b) {
    uint64_t n = 0;
    for (int z = a.z; z <= b.z; ++z) for (int y = a.y; y <= b.y; ++y) for (int x = a.x; x <= b.x; ++x) { const uint8_t m = w.getVoxel(x, y, z); if (m && !isAnchor(m)) ++n; }
    return n;
}

// Edificio: muros de 1 voxel, forjados de 1 voxel cada `floorH`, pilares 2x2 en esquinas y en rejilla de ~4 m.
struct Building { IVec3 mn, mx; };
Building building(World& w, int x0, int z0, int wx, int wz, int floors, int floorH = 12, uint8_t wall = MAT_BRICK, uint8_t slab = MAT_CONCRETE, bool columns = true) {
    const int top = 1 + floors * floorH;
    // muros
    w.fillBox(IVec3(x0, 1, z0), IVec3(x0 + wx - 1, top, z0), wall);
    w.fillBox(IVec3(x0, 1, z0 + wz - 1), IVec3(x0 + wx - 1, top, z0 + wz - 1), wall);
    w.fillBox(IVec3(x0, 1, z0), IVec3(x0, top, z0 + wz - 1), wall);
    w.fillBox(IVec3(x0 + wx - 1, 1, z0), IVec3(x0 + wx - 1, top, z0 + wz - 1), wall);
    // forjados + tejado
    for (int f = 1; f <= floors; ++f) w.fillBox(IVec3(x0, 1 + f * floorH, z0), IVec3(x0 + wx - 1, 1 + f * floorH, z0 + wz - 1), slab);
    // pilares interiores 2x2 cada ~16 voxels (4 m)
    if (columns) {
        for (int px = x0 + 8; px < x0 + wx - 2; px += 16) for (int pz = z0 + 8; pz < z0 + wz - 2; pz += 16)
            w.fillBox(IVec3(px, 1, pz), IVec3(px + 1, top, pz + 1), MAT_CONCRETE);
    }
    return Building{IVec3(x0, 1, z0), IVec3(x0 + wx - 1, top, z0 + wz - 1)};
}

float remaining(const World& w, const Building& b, uint64_t before) { return before ? static_cast<float>(countBox(w, b.mn, b.mx)) / before : 1.f; }

// --- escenario base: forjado sobre 9 pilares -----------------------------------------------------------
struct Grid9 { Scene s; IVec3 cols[9]; IVec3 slabMin, slabMax; uint64_t slab0 = 0;
    Grid9() : s(3, 2, 3) {
        World& w = s.w();
        int k = 0;
        for (int i = 0; i < 3; ++i) for (int j = 0; j < 3; ++j) { cols[k] = IVec3(20 + i * 16, 1, 20 + j * 16); w.fillBox(cols[k], IVec3(cols[k].x + 1, 12, cols[k].z + 1), MAT_CONCRETE); ++k; }
        slabMin = IVec3(16, 13, 16); slabMax = IVec3(57, 13, 57);
        w.fillBox(slabMin, slabMax, MAT_CONCRETE);   // 42x42 voxels = 10,5 m, 1764 voxels
        s.settle();
        slab0 = countBox(w, slabMin, slabMax);
    }
    void blastColumn(int i) { s.e->explode(Vec3((cols[i].x + 1) * 0.25f, 1.5f, (cols[i].z + 1) * 0.25f), 0.9f, 255); }
};

void testOneSupport() {
    TEST("1/4: forjado sobre 9 pilares, se destruye 1 (redundancia): el forjado aguanta");
    Grid9 g; g.blastColumn(4); const uint32_t fell = g.s.run();
    CHECKM(remaining(g.s.w(), Building{g.slabMin, g.slabMax}, g.slab0) > 0.97f, "queda %.2f", remaining(g.s.w(), Building{g.slabMin, g.slabMax}, g.slab0));
    CHECKM(fell < 120, "cayeron %u voxels", fell);
}
void testTwoSupports() {
    TEST("2: se destruyen 2 pilares de 9: redistribuye, aguanta");
    Grid9 g; g.blastColumn(4); g.blastColumn(0); const uint32_t fell = g.s.run();
    CHECKM(remaining(g.s.w(), Building{g.slabMin, g.slabMax}, g.slab0) > 0.95f, "queda %.2f", remaining(g.s.w(), Building{g.slabMin, g.slabMax}, g.slab0));
    (void)fell;
}
void testManySupports() {
    TEST("3/5: se destruyen 7 de 9 pilares: el forjado se viene abajo entero (los 2 que quedan estan en un borde)");
    // ANTES del modelo de vuelco esta prueba esperaba que los pilares 7 y 8 se quedaran en pie con su
    // capitel de losa. Pero los dos estan en el borde +x (x=52) y la losa llega hasta x=16: lo que les
    // colgaba tenia el centro de masas a 4 m POR FUERA de los dos unicos apoyos. Eso no se sostiene, y
    // que se sostuviera era justo el fallo que se estaba arreglando (un resto enorme apoyado en un
    // muñon). Con 7 de 9 pilares volados, el forjado entero se va al suelo.
    Grid9 g; for (int i = 0; i < 7; ++i) g.blastColumn(i); const uint32_t fell = g.s.run();
    const float rem = remaining(g.s.w(), Building{g.slabMin, g.slabMax}, g.slab0);
    printf("  (queda %.3f del forjado, cayeron %u voxels)\n", rem, fell);
    CHECKM(rem < 0.2f, "queda %.2f (cayeron %u)", rem, fell);
}
void testNonRedundant() {
    TEST("5: losa sobre un único pilar; se destruye: cae toda");
    Scene s(2, 2, 2); World& w = s.w();
    w.fillBox(IVec3(30, 1, 30), IVec3(31, 12, 31), MAT_CONCRETE);
    w.fillBox(IVec3(24, 13, 24), IVec3(37, 13, 37), MAT_CONCRETE);
    s.settle();
    const uint64_t before = countBox(w, IVec3(24, 13, 24), IVec3(37, 13, 37));
    s.e->explode(Vec3(31 * 0.25f, 1.5f, 31 * 0.25f), 0.9f, 255);
    s.run();
    CHECKM(countBox(w, IVec3(24, 13, 24), IVec3(37, 13, 37)) < before / 10, "queda %llu de %llu", (unsigned long long)countBox(w, IVec3(24, 13, 24), IVec3(37, 13, 37)), (unsigned long long)before);
}

// --- LA MESA del mapa "pruebas", a su tamaño real (voxel de 10 cm) --------------------------------------
// Cuatro columnas de 0,8 m separadas 6 m entre ejes, 4 m de alto, y encima una losa de 9x9 m y 0,8 m de
// grueso (64.800 voxels de hormigón, ~124 t). Es el montaje que el usuario usa para probar el motor: al
// quitarle patas tiene que INCLINARSE hacia el lado sin apoyo y venirse abajo, no quedarse flotando.
// VX_MESA20=1: la misma mesa a 20 cm, que es como la carga el juego en calidad baja y en el movil
// (pruebas_lo.vxmap). Solo tienen sentido con ella las pruebas 39-41, 47 y 48.
static int mesaK() { const char* e = std::getenv("VX_MESA20"); return (e && e[0] == '1') ? 2 : 1; }

struct Mesa {
    int k = mesaK(); float vs = 0.1f * k;
    Scene s; int cx = 96 / k, cz = 96 / k, base = 1, top = 41 / k, slabTop = 48 / k;
    int L0 = -4 / k, L1 = 3 / k, P = 30 / k;                  // lado de la pata y su distancia al centro, en voxels
    IVec3 slabMin, slabMax; uint64_t slab0 = 0;
    Mesa() : s(6, 2, 6, true, 0.1f * mesaK()) {
        World& w = s.w();
        for (int dx = -P; dx <= P; dx += 2 * P) for (int dz = -P; dz <= P; dz += 2 * P)
            w.fillBox(IVec3(cx + dx + L0, base, cz + dz + L0), IVec3(cx + dx + L1, top - 1, cz + dz + L1), MAT_CONCRETE);
        slabMin = IVec3(cx - 45 / k, top, cz - 45 / k); slabMax = IVec3(cx + 44 / k, slabTop - 1, cz + 44 / k);
        w.fillBox(slabMin, slabMax, MAT_CONCRETE);
        s.settle();
        slab0 = countBox(w, slabMin, slabMax);
    }
    // revienta la base de una pata (i: 0=-x-z, 1=-x+z, 2=+x-z, 3=+x+z), como el cohete del juego
    void pata(int i) {
        const float dx = (i & 2) ? 3.f : -3.f, dz = (i & 1) ? 3.f : -3.f;
        s.e->explode(Vec3(cx * vs + dx, 0.65f, cz * vs + dz), 1.15f, 255);
    }
    uint64_t quedaColumna(int i) {
        const int dx = (i & 2) ? P : -P, dz = (i & 1) ? P : -P;
        return countBox(s.w(), IVec3(cx + dx + L0, base, cz + dz + L0), IVec3(cx + dx + L1, top - 1, cz + dz + L1));
    }
    float queda() { return remaining(s.w(), Building{slabMin, slabMax}, slab0); }
};

void testMesaUnaPata() {
    TEST("39: MESA: se vuela 1 pata de 4 -> las otras 3 rodean el centro de masas: AGUANTA (no hay falso derrumbe)");
    Mesa m; m.pata(0); m.s.run();
    printf("  (queda %.3f de la losa; patas %llu/%llu/%llu)\n", m.queda(),
           (unsigned long long)m.quedaColumna(1), (unsigned long long)m.quedaColumna(2), (unsigned long long)m.quedaColumna(3));
    CHECKM(m.queda() > 0.85f, "se ha caido sola: queda %.3f", m.queda());
    const uint64_t entera = 2000 / (m.k * m.k * m.k);   // (contado a 10 cm; a 20 cm una pata entera son 320 voxels)
    CHECK(m.quedaColumna(1) > entera && m.quedaColumna(2) > entera && m.quedaColumna(3) > entera);
}
void testMesaDosPatas() {
    TEST("40: MESA de pruebas (10 cm): se vuelan 2 patas del mismo lado -> el centro de masas queda fuera del apoyo: vuelca");
    Mesa m; m.pata(0); m.pata(1); m.s.run();
    printf("  (queda %.3f de la losa; patas que quedaban en pie %llu y %llu)\n", m.queda(),
           (unsigned long long)m.quedaColumna(2), (unsigned long long)m.quedaColumna(3));
    CHECKM(m.queda() < 0.25f, "queda %.3f de la losa", m.queda());
    // no basta con que se desprenda el voladizo: tienen que ceder tambien las patas que quedaban, que es
    // lo que hace que la mesa VUELQUE hacia el lado vacio en vez de quedarse medio techo colgando
    CHECKM(m.quedaColumna(2) + m.quedaColumna(3) < 2000, "las patas siguen enteras: %llu + %llu",
           (unsigned long long)m.quedaColumna(2), (unsigned long long)m.quedaColumna(3));
}
void testMesaTresPatas() {
    TEST("41: MESA: se vuelan 3 patas, queda 1 -> una pata no sostiene 124 t: se cae");
    Mesa m; m.pata(0); m.pata(1); m.pata(2); m.s.run();
    printf("  (queda %.3f de la losa; pata superviviente %llu voxels)\n", m.queda(), (unsigned long long)m.quedaColumna(3));
    CHECKM(m.queda() < 0.35f, "queda %.3f de la losa", m.queda());
}
void testMesaPataAPata() {
    TEST("47: MESA: las 3 patas UNA A UNA, dejando mirar al analizador entre cada una -> se cae igual");
    // EL CASO DEL USUARIO, tal cual juega: "le rompi las patas y le quedo una, y sigue flotando". La
    // prueba 41 vuela las tres DE GOLPE y deja mirar al analizador una sola vez al final; jugando se
    // rompen de una en una y el analizador se despierta entre golpe y golpe. Y eso cambia la linea
    // base: cada celda recuerda la carga que tenia LA PRIMERA VEZ QUE SE LA MIRO, y la pata del
    // fondo no se mira hasta que le ha caido encima todo el peso. Se apunta ese peso como "normal" y
    // ya no cede nunca.
    //
    // Orden: 0 (aguanta con tres), 3 (la esquina opuesta: quedan dos en diagonal) y 1 (queda la 2 sola).
    Mesa m;
    m.pata(0); m.s.run();
    const float tras1 = m.queda();
    m.pata(3); m.s.run();
    const float tras2 = m.queda();
    m.pata(1); m.s.run();
    printf("  (tras la 1a pata queda %.3f - tras la 2a %.3f - tras la 3a %.3f; pata superviviente %llu voxels)\n",
           tras1, tras2, m.queda(), (unsigned long long)m.quedaColumna(2));
    CHECKM(m.queda() < 0.35f, "con UNA pata de cuatro y rompiendolas de una en una, queda %.3f de la losa flotando", m.queda());
}

void testMesaAMazazos() {
    TEST("48: MESA a MAZAZOS, pata a pata, como juega el usuario -> con una pata sola se cae");
    // Lo mismo que la 47 pero con el MAZO en vez de un cohete. El mazo muerde 32 cm de radio por golpe
    // (radius 0,64 x 0,5, weapons.gd) y una pata mide 80 cm: hacen falta varios golpes y quedan
    // MUÑONES arriba y abajo, que es justo lo que no hace un cohete. Se golpea cada pata a la altura de
    // la rodilla desde los cuatro lados hasta que no queda seccion, dejando mirar al analizador entre
    // pata y pata.
    Mesa m;
    auto mazazos = [&](int i) {
        const float px = m.cx * m.vs + ((i & 2) ? 3.f : -3.f), pz = m.cz * m.vs + ((i & 1) ? 3.f : -3.f);
        const float y = 1.2f;                                  // a la altura de la rodilla
        const Vec3 lados[4] = {Vec3(1, 0, 0), Vec3(-1, 0, 0), Vec3(0, 0, 1), Vec3(0, 0, -1)};
        for (int vuelta = 0; vuelta < 3; ++vuelta)
            for (const Vec3& d : lados) {
                const Vec3 desde(px - d.x * 0.9f, y + vuelta * 0.15f, pz - d.z * 0.9f);
                m.s.e->carveBeam(desde, d, 0.35f + 0.5f, 0.32f, 255, false);
                m.s.run();                                     // el analizador mira entre mazazo y mazazo, como en partida (el mazo da ~1 golpe por segundo)
            }
    };
    mazazos(0); m.s.run();
    const float tras1 = m.queda();
    mazazos(3); m.s.run();
    const float tras2 = m.queda();
    mazazos(1); m.s.run();
    printf("  (tras la 1a pata queda %.3f - tras la 2a %.3f - tras la 3a %.3f; pata superviviente %llu voxels; munones: %llu %llu %llu)\n",
           tras1, tras2, m.queda(), (unsigned long long)m.quedaColumna(2),
           (unsigned long long)m.quedaColumna(0), (unsigned long long)m.quedaColumna(3), (unsigned long long)m.quedaColumna(1));
    // EL ALMA: cuantos voxels quedan en la franja del corte de cada pata rota (una capa de 1 voxel, a
    // 1,3 m). Una pata entera tiene 64 (8x8). Si queda algo, la pata NO esta cortada: sigue unida por
    // un alma que el mazo no alcanza desde fuera.
    for (int i : {0, 3, 1}) {
        const int dx = (i & 2) ? m.P : -m.P, dz = (i & 1) ? m.P : -m.P, y = 13 / m.k;
        const uint64_t alma = countBox(m.s.w(), IVec3(m.cx + dx + m.L0, y, m.cz + dz + m.L0), IVec3(m.cx + dx + m.L1, y, m.cz + dz + m.L1));
        printf("  pata %d: en el corte quedan %llu de 64 voxels\n", i, (unsigned long long)alma);
    }
    {
        const auto& st = m.s.e->stats();
        printf("  analizador: %d iteraciones en total, %d celdas fallidas, %d fragmentos, peor carga %.2f\n",
               st.structIterationsTotal, st.structFailuresTotal, st.structFragmentsTotal, st.structWorstRatio);
    }
    CHECKM(m.queda() < 0.35f, "a mazazos, con UNA pata de cuatro, queda %.3f de la losa flotando", m.queda());
}

void testMesaMazoUnLado() {
    TEST("49: MESA a MAZAZOS DESDE UN LADO, en el orden del usuario (+x+z, -x+z, -x-z) -> con la +x-z sola se cae");
    // Medido en partida (2026-09-21, --diagmesa, 20 cm): tres patas cortadas a mazazos, la +x-z entera, el
    // analizador con 0 fallos y peor carga 0,17-0,76, y el tablero entero en el aire. Se cayo solo al
    // empezar a golpear la cuarta. La 48 pega desde los CUATRO lados y en otro orden; jugando se pega
    // desde donde estas, de frente, hasta que la pata cede. Aqui: desde fuera de la mesa, mirando al centro.
    Mesa m;
    int golpes = 0;
    auto mazazos = [&](int i) {
        const float sx = (i & 2) ? 1.f : -1.f, sz = (i & 1) ? 1.f : -1.f;
        const float px = m.cx * m.vs + sx * 3.f, pz = m.cz * m.vs + sz * 3.f;
        Vec3 d(-sx, 0, -sz); const float n = std::sqrt(d.x * d.x + d.z * d.z); d = Vec3(d.x / n, 0, d.z / n);
        // se golpea a 1 m hasta que la franja de 0,8-1,2 m queda vacia (como mucho 12 golpes)
        for (int g = 0; g < 12; ++g) {
            const Vec3 desde(px - d.x * 1.2f, 1.0f, pz - d.z * 1.2f);
            m.s.e->carveBeam(desde, d, 0.35f + 1.2f, 0.32f, 255, false);
            m.s.run(); ++golpes;
            const int dx = (i & 2) ? m.P : -m.P, dz = (i & 1) ? m.P : -m.P;
            bool cortada = false;
            for (int y = int(0.8f / m.vs); y <= int(1.2f / m.vs) && !cortada; ++y)
                cortada = countBox(m.s.w(), IVec3(m.cx + dx + m.L0, y, m.cz + dz + m.L0), IVec3(m.cx + dx + m.L1, y, m.cz + dz + m.L1)) == 0;
            if (cortada) break;
        }
    };
    mazazos(3); const float tras1 = m.queda();
    mazazos(1); const float tras2 = m.queda();
    mazazos(0);
    for (int k = 0; k < 4; ++k) m.s.run();
    const auto& st = m.s.e->stats();
    printf("  (%d golpes; tras la 1a pata queda %.3f - tras la 2a %.3f - tras la 3a %.3f; pata superviviente %llu; peor carga %.2f, fallos %d)\n",
           golpes, tras1, tras2, m.queda(), (unsigned long long)m.quedaColumna(2), st.structWorstRatio, st.structFailuresTotal);
    CHECKM(m.queda() < 0.35f, "tres patas cortadas desde un lado y queda %.3f de la losa en el aire", m.queda());
}

void testMesaUnVoxel() {
    TEST("42: MESA: las 4 patas cortadas dejando UN voxel de pie -> no puede sostener nada");
    Mesa m;
    World& w = m.s.w();
    for (int i = 0; i < 4; ++i) m.pata(i);
    m.s.run();
    // corte limpio a media altura de las 4 patas, dejando un unico voxel en una de ellas
    for (int i = 0; i < 4; ++i) {
        const int dx = (i & 2) ? 30 : -30, dz = (i & 1) ? 30 : -30;
        w.fillBox(IVec3(m.cx + dx - 4, 20, m.cz + dz - 4), IVec3(m.cx + dx + 3, 21, m.cz + dz + 3), MAT_AIR);
    }
    w.setVoxel(m.cx + 30, 20, m.cz + 30, MAT_CONCRETE);
    w.setVoxel(m.cx + 30, 21, m.cz + 30, MAT_CONCRETE);
    m.s.e->armLoadEval();
    m.s.run();
    const uint64_t punto = countBox(w, IVec3(m.cx + 30, 20, m.cz + 30), IVec3(m.cx + 30, 21, m.cz + 30));
    printf("  (queda %.3f de la losa; el voxel puente %llu)\n", m.queda(), (unsigned long long)punto);
    CHECKM(m.queda() < 0.2f, "un voxel sigue sosteniendo la losa: queda %.3f", m.queda());
}

void testMesaVoxelCentral() {
    TEST("43: el caso literal: UN voxel CENTRADO bajo el techo de 124 t. El vuelco no puede ayudar (el centro de masas cae justo encima): tiene que ceder por aplastamiento");
    Scene s(6, 2, 6, true, 0.1f); World& w = s.w();
    const int cx = 96, cz = 96, top = 41, slabTop = 48;
    // pilar central gordo (1 m) hasta el techo + techo de 9x9 m
    w.fillBox(IVec3(cx - 5, 1, cz - 5), IVec3(cx + 4, top - 1, cz + 4), MAT_CONCRETE);
    const IVec3 mn(cx - 45, top, cz - 45), mx(cx + 44, slabTop - 1, cz + 44);
    w.fillBox(mn, mx, MAT_CONCRETE);
    s.settle();
    const uint64_t antes = countBox(w, mn, mx);
    // se sierra el pilar a media altura dejando UN voxel, en el eje: la excentricidad es cero
    w.fillBox(IVec3(cx - 5, 20, cz - 5), IVec3(cx + 4, 23, cz + 4), MAT_AIR);
    for (int y = 20; y <= 23; ++y) w.setVoxel(cx, y, cz, MAT_CONCRETE);
    s.e->armLoadEval();
    s.run();
    const float queda = static_cast<float>(countBox(w, mn, mx)) / antes;
    printf("  (queda %.3f del techo; el voxel %llu)\n", queda, (unsigned long long)countBox(w, IVec3(cx, 20, cz), IVec3(cx, 23, cz)));
    CHECKM(queda < 0.2f, "un voxel centrado sigue sosteniendo 124 t: queda %.3f", queda);
}

void testMesaATiros() {
    TEST("45: cortar 3 patas A TIROS tambien tira la mesa (las balas abren analisis de cargas al acumular daño)");
    Mesa m; World& w = m.s.w();
    // se sierran 3 patas a balazos: barrido horizontal a 1,5 m de altura, atravesando la columna.
    // TRES PASADAS (2026-10-03): desde que las paredes aguantan balas (World::danarBala) cada tiro arranca menos y
    // con una sola pasada la pata quedaba cortada a la MITAD (32 de 64 voxels en la fila mas fina): media pata de
    // hormigon de 80 cm aguanta la losa y la mesa, con razon, no caia. La prueba fallaba por eso, no por el motor.
    for (int pasada = 0; pasada < 3; ++pasada)
    for (int i = 0; i < 3; ++i) {
        const float dx = (i & 2) ? 3.f : -3.f, dz = (i & 1) ? 3.f : -3.f;
        const float cx = m.cx * m.vs + dx, cz = m.cz * m.vs + dz;   // (era m.cx * 0,1: a 20 cm disparaba al vacio)
        for (int fila = 0; fila < 3; ++fila) {
            const float y = 1.3f + fila * 0.25f;
            for (int k = -5; k <= 5; ++k) {
                RayHit h;
                m.s.e->shoot(Vec3(cx - 3.f, y, cz + k * 0.1f), Vec3(1, 0, 0), 6.f, 200, h);
            }
        }
    }
    // que de verdad esten cortadas (la fila mas fina de cada pata, entre 1,2 y 1,9 m, a 10 o 20 cm): si no, la prueba no prueba nada
    for (int i = 0; i < 3; ++i) {
        const int dx = (i & 2) ? m.P : -m.P, dz = (i & 1) ? m.P : -m.P;
        uint64_t fina = ~0ull;
        for (int y = static_cast<int>(1.2f / m.vs); y <= static_cast<int>(1.9f / m.vs); ++y)
            fina = std::min(fina, countBox(w, IVec3(m.cx + dx + m.L0, y, m.cz + dz + m.L0), IVec3(m.cx + dx + m.L1, y, m.cz + dz + m.L1)));
        CHECKM(fina == 0, "la pata %d no esta cortada: quedan %llu voxels en su fila mas fina", i, (unsigned long long)fina);
    }
    m.s.e->soltarDanoBala();   // cierra lo que quede por debajo del umbral, sin esperar mas disparos
    m.s.run();
    printf("  (queda %.3f de la losa · iteraciones del analizador %d · celdas fallidas %d)\n",
           m.queda(), m.s.e->stats().structIterationsTotal, m.s.e->stats().structFailuresTotal);
    CHECKM(m.s.e->stats().structIterationsTotal > 0, "las balas no han abierto el analisis de cargas");
    CHECKM(m.queda() < 0.35f, "queda %.3f de la losa", m.queda());
}

void testMesaCuartaPata() {
    TEST("46: 3 patas voladas y la CUARTA a tiros: no puede quedarse rompiendose y reconstruyendose en bucle");
    Mesa m; World& w = m.s.w();
    m.pata(0); m.pata(1); m.pata(2);
    m.s.run();
    const float tras3 = m.queda();
    // ...y ahora a balazos contra la unica pata que queda
    const float cx = m.cx * m.vs + 3.f, cz = m.cz * m.vs + 3.f;   // (era m.cx * 0,1: a 20 cm disparaba al vacio)
    for (int fila = 0; fila < 3; ++fila)
        for (int k = -5; k <= 5; ++k) {
            RayHit h;
            m.s.e->shoot(Vec3(cx - 3.f, 1.3f + fila * 0.25f, cz + k * 0.1f), Vec3(1, 0, 0), 6.f, 200, h);
        }
    m.s.e->soltarDanoBala();
    m.s.run();
    printf("  (queda %.3f tras las 3 patas · %.3f tras tirotear la cuarta · pata %llu voxels · iteraciones %d)\n",
           tras3, m.queda(), (unsigned long long)m.quedaColumna(3), m.s.e->stats().structIterationsTotal);
    CHECKM(m.queda() < 0.35f, "la losa sigue arriba: queda %.3f", m.queda());
    CHECKM(m.quedaColumna(3) < 1500u / (m.k * m.k * m.k), "la pata se ha reconstruido sola: %llu voxels", (unsigned long long)m.quedaColumna(3));
    (void)w;
}

void testVentana() {
    TEST("44: un balazo en una ventana rompe el CRISTAL, no el marco de hierro ni la pared de al lado");
    // Muro de hormigon con una ventana PEQUEÑA: 80x80 cm de vidrio y marco de hierro alrededor. Tiene
    // que ser mas pequeña que la esfera de añicos (65 cm de radio) o la prueba no prueba nada: si el
    // cristal es mas grande que la esfera, nunca llega a tocar el marco.
    auto montar = [](World& w) {
        w.fillBox(IVec3(60, 1, 20), IVec3(60, 34, 99), MAT_CONCRETE);
        w.fillBox(IVec3(60, 13, 55), IVec3(60, 22, 64), MAT_METAL);            // marco (anillo de 1 voxel)
        w.fillBox(IVec3(60, 14, 56), IVec3(60, 21, 63), MAT_GLASS);            // vidrio 8x8
    };
    const IVec3 mnV(60, 14, 56), mxV(60, 21, 63);      // vidrio
    const IVec3 mnT(60, 1, 20), mxT(60, 34, 99);       // el muro entero
    Scene s(4, 2, 4, false, 0.1f); World& w = s.w();
    montar(w); s.settle();
    const uint64_t vidrio0 = countBox(w, mnV, mxV), total0 = countBox(w, mnT, mxT);
    Rng rng(7);
    w.carveBullet(IVec3(60, 17, 59), IVec3(-1, 0, 0), 200, rng);               // al centro del cristal
    const uint64_t vidrio = countBox(w, mnV, mxV), total = countBox(w, mnT, mxT);
    // CONTROL: el mismo disparo con la esfera de antes (sin filtro de material).
    Scene s2(4, 2, 4, false, 0.1f); World& w2 = s2.w();
    montar(w2); s2.settle();
    w2.carveSphere(Vec3(60 * 0.1f, 17 * 0.1f, 59 * 0.1f), 0.65f, 255, nullptr, false);
    const uint64_t antesTotal = total0 - countBox(w2, mnT, mxT);
    printf("  (vidrio %llu -> %llu · el disparo se lleva %llu voxels en total, de los que %llu NO son vidrio"
           " · sin filtro se llevaba %llu)\n",
           (unsigned long long)vidrio0, (unsigned long long)vidrio, (unsigned long long)(total0 - total),
           (unsigned long long)((total0 - total) - (vidrio0 - vidrio)), (unsigned long long)antesTotal);
    CHECKM(vidrio < vidrio0, "el cristal no se ha roto: %llu de %llu", (unsigned long long)vidrio, (unsigned long long)vidrio0);
    CHECKM(total0 - total == vidrio0 - vidrio, "se ha llevado %llu voxels que no eran cristal",
           (unsigned long long)((total0 - total) - (vidrio0 - vidrio)));
    CHECKM(antesTotal > total0 - total, "el control deberia destrozar mas (%llu vs %llu)",
           (unsigned long long)antesTotal, (unsigned long long)(total0 - total));
}

void testDamagedWall() {
    TEST("6/9: boquete pequeño en un muro: el edificio se queda (>95 %)");
    Scene s(3, 3, 3); World& w = s.w();
    Building b = building(w, 20, 20, 40, 40, 3);
    s.settle(); const uint64_t before = countBox(w, b.mn, b.mx);
    s.e->explode(Vec3(20 * 0.25f, 1.8f, 40 * 0.25f), 1.5f, 255);
    s.run();
    CHECKM(remaining(w, b, before) > 0.95f, "queda %.3f", remaining(w, b, before));
    CHECK(w.getVoxel(20, 30, 40) == MAT_BRICK);   // el muro sobre el boquete sigue
}
void testDamagedRoof() {
    TEST("7: agujero en el tejado: sólo cae lo del agujero");
    Scene s(3, 3, 3); World& w = s.w();
    Building b = building(w, 20, 20, 40, 40, 2);
    s.settle(); const uint64_t before = countBox(w, b.mn, b.mx);
    s.e->explode(Vec3(40 * 0.25f, (1 + 2 * 12) * 0.25f + 0.1f, 40 * 0.25f), 2.0f, 255);
    s.run();
    CHECKM(remaining(w, b, before) > 0.93f, "queda %.3f", remaining(w, b, before));
}
void testDamagedCorner() {
    TEST("8/16: esquina volada: la esquina puede caer, la opuesta no");
    Scene s(3, 3, 3); World& w = s.w();
    Building b = building(w, 20, 20, 40, 40, 3);
    s.settle(); const uint64_t before = countBox(w, b.mn, b.mx);
    s.e->explode(Vec3(21 * 0.25f, 1.6f, 21 * 0.25f), 3.0f, 255);
    s.run();
    CHECKM(remaining(w, b, before) > 0.70f, "queda %.3f", remaining(w, b, before));
    CHECK(countBox(w, IVec3(50, 1, 50), IVec3(59, b.mx.y, 59)) > 300);   // esquina opuesta intacta
}
void testLargeExplosion() {
    TEST("10: explosión grande en la base: derrumbe importante, termina y no toca la esquina lejana del mapa");
    Scene s(4, 3, 4); World& w = s.w();
    Building b = building(w, 20, 20, 48, 48, 4);
    w.fillBox(IVec3(100, 1, 100), IVec3(110, 20, 110), MAT_CONCRETE);   // bloque lejano de control
    s.settle(); const uint64_t before = countBox(w, b.mn, b.mx);
    s.e->explode(Vec3(44 * 0.25f, 1.6f, 44 * 0.25f), 6.0f, 255);
    s.e->explode(Vec3(24 * 0.25f, 1.6f, 44 * 0.25f), 4.0f, 255);
    s.e->explode(Vec3(64 * 0.25f, 1.6f, 44 * 0.25f), 4.0f, 255);
    s.run();
    const float rem = remaining(w, b, before);
    printf("  (queda %.2f del edificio con pilares, %d iteraciones, %d celdas fallidas)\n", rem, s.e->stats().structIterationsTotal, s.e->stats().structFailuresTotal);
    CHECK(rem < 0.97f && rem > 0.4f);   // con pilares interiores de hormigón: daño grande pero sigue en pie
    CHECK(countBox(w, IVec3(100, 1, 100), IVec3(110, 20, 110)) == 11ull * 20 * 11);
}
void testDemolition() {
    TEST("10b: edificio de muros (sin pilares): 5 cohetes en la planta baja lo tiran (README); 1 cohete sólo hace un boquete");
    {
        Scene s(4, 3, 4); World& w = s.w();
        Building b = building(w, 20, 20, 40, 40, 3, 12, MAT_BRICK, MAT_CONCRETE, false);
        s.settle(); const uint64_t before = countBox(w, b.mn, b.mx);
        s.e->explode(Vec3(20 * 0.25f, 1.6f, 40 * 0.25f), 3.5f, 255);
        s.run();
        const float rem1 = remaining(w, b, before);
        printf("  (1 cohete: queda %.3f)\n", rem1);
        CHECKM(rem1 > 0.9f, "queda %.3f", rem1);
    }
    {
        // 5 cohetes repartidos por los lados: al suelo. Antes del modelo de vuelco quedaba entre un 20 y
        // un 90 % en pie, pero lo que quedaba eran trozos de muro de tres plantas apoyados en un muñon de
        // medio metro con el centro de masas a 2 m por fuera: fragmentos inclinados que no se caian.
        Scene s(4, 3, 4); World& w = s.w();
        Building b = building(w, 20, 20, 40, 40, 3, 12, MAT_BRICK, MAT_CONCRETE, false);
        s.settle(); const uint64_t before = countBox(w, b.mn, b.mx);
        const float cx = 40 * 0.25f, cz = 40 * 0.25f;
        for (int k = 0; k < 5; ++k) { const float a = 6.2832f * k / 5; s.e->explode(Vec3(cx + std::cos(a) * 4.9f, 1.6f, cz + std::sin(a) * 4.9f), 3.5f, 255); }
        s.run();
        const float rem = remaining(w, b, before);
        printf("  (5 cohetes en los lados: queda %.3f, %d iteraciones, %d celdas fallidas)\n", rem, s.e->stats().structIterationsTotal, s.e->stats().structFailuresTotal);
        CHECKM(rem < 0.1f, "queda %.3f", rem);
    }
    {
        // cinturón de cargas cada 3 m por el perímetro + carga central (main.gd::demolish_nearest): al suelo
        Scene s(4, 3, 4); World& w = s.w();
        Building b = building(w, 20, 20, 40, 40, 3, 12, MAT_BRICK, MAT_CONCRETE, false);
        s.settle(); const uint64_t before = countBox(w, b.mn, b.mx);
        const float cx = 40 * 0.25f, cz = 40 * 0.25f, half = 5.0f;
        const float per = 8.f * half; const int charges = std::max(8, static_cast<int>(per / 3.f));
        for (int k = 0; k < charges; ++k) {
            const float t = per * k / charges; Vec3 pos;
            if (t < 2 * half) pos = Vec3(cx - half + t, 0, cz - half);
            else if (t < 4 * half) pos = Vec3(cx + half, 0, cz - half + (t - 2 * half));
            else if (t < 6 * half) pos = Vec3(cx + half - (t - 4 * half), 0, cz + half);
            else pos = Vec3(cx - half, 0, cz + half - (t - 6 * half));
            pos.y = 1.9f;
            s.e->explode(pos, 3.2f, 255);
        }
        s.e->explode(Vec3(cx, 1.9f, cz), 6.0f, 255);
        s.run();
        const float rem = remaining(w, b, before);
        printf("  (cinturón de %d cargas + central: queda %.3f, %d iteraciones, %d celdas fallidas)\n", charges + 1, rem, s.e->stats().structIterationsTotal, s.e->stats().structFailuresTotal);
        CHECKM(rem < 0.25f, "queda %.3f", rem);
    }
}

void testTwoNearbyBuildings() {
    TEST("11: dos edificios a 1 m: el misil en A no tira B (>98 % de B)");
    Scene s(4, 3, 4); World& w = s.w();
    Building A = building(w, 10, 20, 40, 40, 3);
    Building B = building(w, 54, 20, 40, 40, 3);   // 4 voxels = 1 m de separación
    s.settle(); const uint64_t a0 = countBox(w, A.mn, A.mx), b0 = countBox(w, B.mn, B.mx);
    for (int k = 0; k < 4; ++k) s.e->explode(Vec3((20 + k * 8) * 0.25f, 1.6f, 40 * 0.25f), 3.5f, 255);   // A muy dañado
    s.e->explode(Vec3(49 * 0.25f, 1.6f, 40 * 0.25f), 2.5f, 255);   // en el muro de A que mira a B: B recibe algo de onda
    s.run();
    const float ra = remaining(w, A, a0), rb = remaining(w, B, b0);
    // B sólo puede perder lo que la onda le quita del muro que mira a A: nada de sus plantas altas
    const uint64_t topB = countBox(w, IVec3(B.mn.x, B.mx.y, B.mn.z), B.mx);
    printf("  (A queda %.2f, B queda %.3f, tejado de B %llu/%llu)\n", ra, rb, (unsigned long long)topB, (unsigned long long)(40 * 40));
    CHECKM(rb > 0.95f, "B queda %.3f", rb);
    CHECKM(topB >= 40ull * 40 - 20, "tejado de B %llu", (unsigned long long)topB);
    CHECK(ra < 1.0f);
}
void testDisconnectedBuildings() {
    TEST("12: edificios separados 6 m: B intacto al 100 %");
    Scene s(5, 3, 4); World& w = s.w();
    Building A = building(w, 10, 20, 40, 40, 3);
    Building B = building(w, 74, 20, 40, 40, 3);
    s.settle(); const uint64_t b0 = countBox(w, B.mn, B.mx);
    for (int k = 0; k < 5; ++k) s.e->explode(Vec3((16 + k * 8) * 0.25f, 1.6f, 40 * 0.25f), 3.5f, 255);
    s.run();
    CHECK(countBox(w, B.mn, B.mx) == b0);
    (void)A;
}
void testConnectedBuildings() {
    TEST("13: edificios unidos por una pasarela: demoler A tira la pasarela pero B sigue (>95 %)");
    Scene s(5, 3, 4); World& w = s.w();
    Building A = building(w, 10, 20, 40, 40, 3);
    Building B = building(w, 74, 20, 40, 40, 3);
    w.fillBox(IVec3(50, 25, 36), IVec3(73, 25, 43), MAT_CONCRETE);   // pasarela de 6 m entre ambos a la altura del 2º forjado
    s.settle(); const uint64_t b0 = countBox(w, B.mn, B.mx);
    const uint64_t bridge0 = countBox(w, IVec3(50, 25, 36), IVec3(73, 25, 43));
    for (int k = 0; k < 6; ++k) s.e->explode(Vec3((14 + k * 7) * 0.25f, 1.6f, (24 + (k & 1) * 32) * 0.25f), 4.0f, 255);
    s.e->explode(Vec3(30 * 0.25f, 1.6f, 40 * 0.25f), 6.0f, 255);
    s.run();
    const float rb = remaining(w, B, b0);
    const uint64_t bridge = countBox(w, IVec3(50, 25, 36), IVec3(73, 25, 43));
    printf("  (B queda %.3f, pasarela %llu de %llu)\n", rb, (unsigned long long)bridge, (unsigned long long)bridge0);
    CHECKM(rb > 0.95f, "B queda %.3f", rb);
    (void)A;
}

void testCantilever() {
    TEST("14: voladizo de 2 m anclado aguanta; viga de 12 m sin apoyo en el extremo se parte");
    Scene s(3, 2, 2); World& w = s.w();
    w.fillBox(IVec3(10, 1, 10), IVec3(13, 16, 13), MAT_CONCRETE);      // pilar 1 m
    w.fillBox(IVec3(14, 16, 10), IVec3(21, 16, 13), MAT_CONCRETE);     // voladizo 2 m
    w.fillBox(IVec3(10, 1, 40), IVec3(13, 16, 43), MAT_CONCRETE);      // pilar 2
    w.fillBox(IVec3(14, 16, 40), IVec3(61, 16, 43), MAT_CONCRETE);     // voladizo 12 m (hormigón: se parte)
    s.settle();
    s.e->explode(Vec3(12 * 0.25f, 2.0f, 30 * 0.25f), 1.0f, 255);      // daño de "activación" entre ambos (no toca nada portante)
    w.setVoxel(15, 16, 11, MAT_AIR); w.setVoxel(15, 16, 41, MAT_AIR);  // un voxel de cada viga (toca ambas islas)
    s.e->armLoadEval();
    s.run();
    CHECK(countBox(w, IVec3(14, 16, 10), IVec3(21, 16, 13)) >= 28);
    CHECKM(countBox(w, IVec3(40, 16, 40), IVec3(61, 16, 43)) < 40, "quedan %llu del extremo", (unsigned long long)countBox(w, IVec3(40, 16, 40), IVec3(61, 16, 43)));
}
void testNoGround() {
    TEST("15: estructura sin apoyo en el suelo (tras daño) cae entera");
    Scene s(2, 2, 2); World& w = s.w();
    w.fillBox(IVec3(10, 8, 10), IVec3(30, 20, 30), MAT_BRICK);
    { s.e->markAllDirty(); s.run(); }   // intacta (pristine) y flotante: se queda (regla 'intacto')
    CHECK(countBox(w, IVec3(10, 8, 10), IVec3(30, 20, 30)) > 0);
    s.e->explode(Vec3(20 * 0.25f, 14 * 0.25f, 10 * 0.25f), 1.5f, 255);
    s.run();
    CHECK(countBox(w, IVec3(10, 8, 10), IVec3(30, 20, 30)) == 0);
}
void testHuge() {
    TEST("17: estructura enorme (60x60 m, 6 plantas): explosión pequeña -> sigue en pie; mide el coste");
    Scene s(9, 4, 9); World& w = s.w();
    Building b = building(w, 20, 20, 240, 240, 6);
    s.settle(); const uint64_t before = countBox(w, b.mn, b.mx);
    Timer t;
    s.e->explode(Vec3(20 * 0.25f, 1.8f, 100 * 0.25f), 2.0f, 255);
    s.run();
    printf("  (%llu voxels, %.1f ms total, análisis %.2f ms/iteración (escaneo %.2f), %d iteraciones, %d celdas fallidas, queda %.4f)\n", (unsigned long long)before, t.ms(), s.e->stats().tStruct.avg, s.e->stats().tStructScan.avg, s.e->stats().structIterationsTotal, s.e->stats().structFailuresTotal, remaining(w, b, before));
    CHECK(remaining(w, b, before) > 0.99f);
    CHECK(s.e->stats().tStruct.max < 250.0);
}
void testMultipleAndRepeated() {
    TEST("18/19/20: explosiones simultáneas y repetidas: termina, progresivo, sin tocar el edificio lejano");
    Scene s(6, 3, 4); World& w = s.w();
    Building A = building(w, 10, 20, 48, 48, 4);
    Building C = building(w, 130, 20, 40, 40, 3);   // lejano: control
    s.settle(); const uint64_t a0 = countBox(w, A.mn, A.mx), c0 = countBox(w, C.mn, C.mx);
    for (int k = 0; k < 6; ++k) s.e->explode(Vec3((14 + k * 8) * 0.25f, 1.6f, 22 * 0.25f), 3.0f, 255);   // simultáneas
    s.run();
    const float r1 = remaining(w, A, a0);
    for (int rep = 0; rep < 3; ++rep) { s.e->explode(Vec3(34 * 0.25f, 1.6f, 44 * 0.25f), 3.5f, 255); s.run(); }   // repetidas
    const float r2 = remaining(w, A, a0);
    printf("  (A: %.2f tras la ráfaga, %.2f tras repetir; iteraciones %d)\n", r1, r2, s.e->stats().structIterationsTotal);
    CHECK(r2 <= r1);
    CHECK(countBox(w, C.mn, C.mx) == c0);
}

void testDeterminism() {
    TEST("30: determinismo: el mismo derrumbe dos veces -> mismo hash del mundo");
    uint64_t h[2];
    for (int run = 0; run < 2; ++run) {
        Scene s(4, 3, 4); World& w = s.w();
        building(w, 10, 20, 48, 48, 4);
        s.settle();
        for (int k = 0; k < 5; ++k) s.e->explode(Vec3((14 + k * 9) * 0.25f, 1.6f, 22 * 0.25f), 3.5f, 255);
        s.run();
        h[run] = w.hashVoxels();
    }
    CHECK(h[0] == h[1]);
}

void testRaycastEquivalence() {
    TEST("rayos: DDA jerárquico == DDA voxel a voxel (10.000 rayos aleatorios en una ciudad)");
    Scene s(4, 3, 4, false); World& w = s.w();
    building(w, 10, 20, 48, 48, 4);
    building(w, 74, 20, 40, 40, 2);
    w.fillBox(IVec3(5, 1, 100), IVec3(6, 30, 101), MAT_METAL);   // poste fino
    Rng rng(77);
    int mismatch = 0, hits = 0;
    const Vec3 size = w.sizeMeters();
    for (int i = 0; i < 10000; ++i) {
        const Vec3 o(rng.range(0.f, size.x), rng.range(0.f, size.y), rng.range(0.f, size.z));
        Vec3 d(rng.range(-1.f, 1.f), rng.range(-1.f, 1.f), rng.range(-1.f, 1.f));
        if (length2(d) < 1e-4f) d = Vec3(1, 0, 0);
        RayHit a, b;
        const bool ra = w.raycast(o, d, 60.f, a), rb = w.raycastBrute(o, d, 60.f, b);
        if (ra != rb || (ra && !(a.voxel == b.voxel))) { ++mismatch; if (mismatch <= 3) printf("  mismatch #%d: o=(%.2f,%.2f,%.2f) d=(%.2f,%.2f,%.2f) hier=%d(%d,%d,%d) brute=%d(%d,%d,%d)\n", mismatch, o.x, o.y, o.z, d.x, d.y, d.z, ra, a.voxel.x, a.voxel.y, a.voxel.z, rb, b.voxel.x, b.voxel.y, b.voxel.z); }
        if (ra) ++hits;
    }
    printf("  (%d impactos, %d discrepancias; pasos %llu, saltos %llu)\n", hits, mismatch, (unsigned long long)w.raySteps(), (unsigned long long)w.raySkips());
    CHECK(mismatch == 0);
    CHECK(hits > 1000);
}

} // namespace

int main(int argc, char** argv) {
    // vxstructtest [filtro]: ejecuta sólo las pruebas cuyo nombre contiene el filtro
    const std::string filter = argc > 1 ? argv[1] : "";
    struct T { const char* name; void (*fn)(); };
    const T tests[] = {
        {"one", testOneSupport}, {"two", testTwoSupports}, {"many", testManySupports}, {"nonredundant", testNonRedundant},
        {"wall", testDamagedWall}, {"roof", testDamagedRoof}, {"corner", testDamagedCorner}, {"large", testLargeExplosion}, {"demolition", testDemolition},
        {"nearby", testTwoNearbyBuildings}, {"disconnected", testDisconnectedBuildings}, {"connected", testConnectedBuildings},
        {"cantilever", testCantilever}, {"noground", testNoGround}, {"huge", testHuge}, {"repeated", testMultipleAndRepeated},
        {"determinism", testDeterminism}, {"raycast", testRaycastEquivalence},
        {"mesa1", testMesaUnaPata}, {"mesa2", testMesaDosPatas}, {"mesa3", testMesaTresPatas}, {"mesaapata", testMesaPataAPata}, {"mesamazo", testMesaAMazazos}, {"mesalado", testMesaMazoUnLado}, {"mesa1vox", testMesaUnVoxel}, {"mesacentro", testMesaVoxelCentral}, {"ventana", testVentana}, {"mesatiros", testMesaATiros}, {"mesacuarta", testMesaCuartaPata},
    };
    for (const T& t : tests) if (filter.empty() || std::string(t.name).find(filter) != std::string::npos) t.fn();
    printf("\n%d comprobaciones OK, %d fallos\n", g_pass, g_fail);
    return g_fail == 0 ? 0 : 1;
}
