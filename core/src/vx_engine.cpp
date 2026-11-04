// vxcore - Engine: orquestación del pipeline de destrucción
#include <unordered_set>
#include <cmath>
#include "vx/vx_engine.h"
#include "vx/vx_material.h"
#include <algorithm>
#include <climits>
#include <cstring>
#include <cstdlib>
#include <cstdio>
#include <thread>

namespace vx {

static std::atomic<uint64_t> g_engineGen{1};

Engine::Engine(const EngineConfig& cfg)
    : world_(new World(cfg.chunksX, cfg.chunksY, cfg.chunksZ, cfg.voxelSize)),
      nav_(*world_),
      preset_(&getPreset(cfg.quality)),
      quality_(cfg.quality),
      rng_(cfg.seed) {
    loadModel_ = cfg.loadModel;
    id_ = g_engineGen.fetch_add(1, std::memory_order_relaxed);
    // Los presets están pensados para voxels de 25 cm: con voxels más finos hay más voxels por m³
    // (x8 a 12,5 cm), así que los umbrales en "número de voxels" se escalan por volumen.
    const float rel = 0.25f / cfg.voxelSize;
    voxelScale_ = rel * rel * rel;
    int threads = cfg.threads;
    if (threads <= 0) threads = preset_->workerThreads;
    if (const char* env = std::getenv("VX_THREADS")) { const int t = std::atoi(env); if (t > 0) threads = t; }   // A/B de rendimiento
    if (threads <= 0) {
        const int hw = static_cast<int>(std::thread::hardware_concurrency());
        threads = clampv(hw - 1, 1, 6);   // deja un núcleo al hilo principal; en móvil 2-3 hilos "big" bastan
    }
    jobs_.reset(new JobSystem(threads));
    debris_.setCapacity(preset_->maxDebris);
    smoke_.setCapacity(std::max(96, std::min(512, preset_->maxDebris / 8)));   // humo: pocas partículas (cada una lee la rejilla), tope 512
}

Engine::~Engine() {
    jobs_.reset();   // une los hilos antes de destruir el mundo
}

Engine::Worker& Engine::worker() {
    thread_local uint64_t owner = 0;
    thread_local Worker* w = nullptr;
    if (owner != id_ || !w) {
        std::lock_guard<std::mutex> g(workersMutex_);
        workers_.emplace_back(new Worker());
        w = workers_.back().get();
        owner = id_;
        w->padded.resize(PAD_VOLUME);
        w->vox.resize(CHUNK_VOLUME);
        w->lodPadded.resize((CHUNK_SIZE / 2 + 2) * (CHUNK_SIZE / 2 + 2) * (CHUNK_SIZE / 2 + 2));
        w->lod2Padded.resize((CHUNK_SIZE / 4 + 2) * (CHUNK_SIZE / 4 + 2) * (CHUNK_SIZE / 4 + 2));
        w->occPadded.resize((CHUNK_SIZE / 2 + 2) * (CHUNK_SIZE / 2 + 2) * (CHUNK_SIZE / 2 + 2));
        w->conn.reset(new ChunkConn());
        w->nbBorder.resize(CHUNK_AREA);
    }
    return *w;
}

void Engine::setQuality(Quality q) {
    quality_ = q;
    preset_ = &getPreset(q);
    debris_.setCapacity(preset_->maxDebris);
}

// ---------------------------------------------------------------------------
// Comandos de juego
// ---------------------------------------------------------------------------
// Escombros deterministas (como Teardown): cada voxel destruido sale volando DESDE SU POSICIÓN,
// empujado desde el centro de la explosión; más rápido cuanto más cerca del centro. Sin azar:
// la misma explosión produce siempre los mismos escombros.
void Engine::emitDebrisFor(const CarveResult& r, float radius, int power, const Vec3& push) {
    if (r.removed <= 0 || r.voxels.empty()) return;
    if (debrisScale_ <= 0.01f) return;   // particulas desactivadas en los ajustes graficos
    const float vs = world_->voxelSize();
    // presupuesto: proporción del preset (ajustada al tamaño de voxel) y tope por evento
    int want = static_cast<int>(r.removed * preset_->debrisRatio * voxelScale_ * debrisScale_ + 0.5f);
    want = clampv(want, std::min(static_cast<int>(r.voxels.size()), 2), preset_->maxDebrisPerEvent);
    const int n = static_cast<int>(r.voxels.size());
    const int step = std::max(1, n / 5);   // 5 particulas por golpe como maximo (pedido: menos escombro, ahorro)
    const float speed = 2.5f + power * 0.03f;
    const float rr = std::max(radius, vs);
    for (int i = 0; i < n; i += step) {
        const RemovedVoxel& v = r.voxels[i];
        const Vec3 p = world_->voxelCenter(IVec3(v.x, v.y, v.z));
        Vec3 d = p - r.center;
        const float dist = length(d);
        d = dist > 1e-4f ? d / dist : Vec3(0, 1, 0);
        const float k = 1.0f - std::min(1.0f, dist / (rr * 1.2f));   // 1 en el centro, 0 en el borde
        // variación determinista por posición (no RNG): hash del voxel
        const uint32_t h = hash3(v.x, v.y, v.z);
        const float jitter = 0.7f + 0.6f * ((h & 255) / 255.0f);
        Vec3 vel = d * (speed * (0.35f + 0.65f * k) * jitter) + Vec3(0, speed * 0.25f * k, 0);
        // EL EMPUJE DEL GOLPE (el puñetazo): el polvo sale hacia donde iba el golpe, cada uno con su parte
        vel = vel + push * (0.6f + 0.8f * (((h >> 8) & 255) / 255.0f));
        debris_.emitAt(p, vel, vs * 0.9f, v.mat, static_cast<uint16_t>(h >> 16));
    }
}

// Fracción de los voxels destruidos que vuelve al mundo como trozos macizos.
static constexpr float CLUMP_MASS_FRACTION = 0.30f;

int Engine::emitClumpsFor(const CarveResult& r, float radius, int power, BodyBuilder& builder, const Vec3& push) {
    // UN BALAZO TAMBIEN DEJA ALGO. El minimo estaba en 24 voxels y una bala quita entre cinco y
    // quince, asi que disparar a una pared no desprendia NADA: solo el agujero y polvo. Con 10 ya
    // entra, pero un trozo por bala seria carisimo -un fusil son once por segundo, por jugador-, asi
    // que por debajo de 24 se emite UNO SOLO y pequeno: la lasca que salta, no un cascote.
    if (r.removed < 10 || r.voxels.empty()) return 0;
    const bool lasca = r.removed < 24;
    const float vs = world_->voxelSize();
    // MASA QUE VUELVE COMO CASCOTE. Empezó en ~85 % (un misil dejaba un montón enorme de trozos
    // rígidos que estorbaban el paso y eran el grueso del coste de un derrumbe: cada trozo = malla +
    // instancia + cuerpo de física), se bajó al 17 %, se probó al 50 % (demasiado: sepultaba la
    // escena) y quedó en el 30 %: se ve caer cascote de verdad sin que estorbe.
    // Si en un derrumbe grande esto pesa demasiado, el regulador de abajo (clumpScale_, que mueve el
    // host según los FPS reales) ya lo recorta solo; el tope duro sigue siendo maxClumps.
    // Los trozos son de gameplay: NO dependen de la calidad ni de la plataforma (todos ven los mismos).
    // La calidad sólo decide si un trozo se simula con Jolt o cae "barato" (VoxelWorld::spawnPiece).
    // Las partículas visuales de destrucción son otra cosa y se ajustan aparte (emitDebrisFor / debrisScale_).
    // El regulador lo mueve el host segun los FPS reales (VoxelWorld::set_clump_scale).
    const float cs = clumpScale_.load(std::memory_order_relaxed);
    if (cs <= 0.01f) return 0;
    const int maxClumps = std::max(2, static_cast<int>(32 * cs));
    int massTarget = static_cast<int>(r.removed * CLUMP_MASS_FRACTION * cs);
    if (lasca) massTarget = std::max(massTarget, 3);   // que no se quede en cero por el redondeo
    const int want = lasca ? 1 : clampv(massTarget / 24, 2, maxClumps);
    const int per = lasca ? std::max(3, massTarget) : std::max(12, massTarget / want);   // voxels por trozo (media)
    const int reach = std::max(3, static_cast<int>(std::ceil(std::cbrt(static_cast<float>(per)) * 0.9f)));
    const int n = static_cast<int>(r.voxels.size());
    const int step = std::max(1, n / want);
    const float speed = 2.0f + power * 0.02f;
    const float rr = std::max(radius, vs);
    std::vector<BodyVoxel> vox;
    // rejilla de ocupación local del trozo (bitset (2*lim+1)³): antes un vector ordenado con inserción O(n)
    const int lim = reach + reach / 2;
    const int side = 2 * lim + 1;
    std::vector<uint8_t> occ(static_cast<size_t>(side) * side * side);
    int made = 0, total = 0;
    for (int i = 0; i < n && made < want && total < massTarget; i += step) {
        const RemovedVoxel& v = r.voxels[i];
        const uint32_t h = hash3(v.x, v.y, v.z);
        // trozo irregular: "blob" que crece por paseo aleatorio determinista desde el voxel semilla
        // (formas distintas en cada trozo: lascas, cuñas, pegotes), nunca un cubo
        vox.clear();
        std::fill(occ.begin(), occ.end(), 0);
        {
            uint32_t rs = h | 1u;
            auto nxt = [&rs]() { rs ^= rs << 13; rs ^= rs >> 17; rs ^= rs << 5; return rs; };
            int target = per * (60 + static_cast<int>(nxt() % 81)) / 100;   // 0,6-1,4 x media
            target = std::min(target, massTarget - total);
            if (target < 8) break;
            const int longAxis = static_cast<int>(nxt() % 3);
            struct P { int x, y, z; };
            std::vector<P> cells; cells.reserve(target);
            auto at = [&](int x, int y, int z) -> uint8_t& { return occ[static_cast<size_t>((x - v.x + lim)) + static_cast<size_t>(side) * ((y - v.y + lim) + static_cast<size_t>(side) * (z - v.z + lim))]; };
            cells.push_back(P{v.x, v.y, v.z}); at(v.x, v.y, v.z) = 1;
            int guard = 0;
            const int maxGuard = target * 12;
            while (static_cast<int>(cells.size()) < target && guard++ < maxGuard) {
                const P& base = cells[nxt() % cells.size()];
                int axis = static_cast<int>(nxt() % 3);
                if ((nxt() & 3) == 0) axis = longAxis;
                const int dir = (nxt() & 1) ? 1 : -1;
                P q = base;
                if (axis == 0) q.x += dir; else if (axis == 1) q.y += dir; else q.z += dir;
                // compacto: no alejarse más de `reach` voxels de la semilla (algo más en el eje largo)
                const int limS = reach, limL = reach + reach / 2;
                if (std::abs(q.x - v.x) > (longAxis == 0 ? limL : limS) || std::abs(q.y - v.y) > (longAxis == 1 ? limL : limS) || std::abs(q.z - v.z) > (longAxis == 2 ? limL : limS)) continue;
                uint8_t& o = at(q.x, q.y, q.z);
                if (o) continue;
                o = 1;
                cells.push_back(q);
            }
            for (const P& c : cells) vox.push_back(BodyVoxel{c.x, c.y, c.z, v.mat});
        }
        const Vec3 p = world_->voxelCenter(IVec3(v.x, v.y, v.z));
        Vec3 d = p - r.center;
        const float dist = length(d);
        d = dist > 1e-4f ? d / dist : Vec3(0, 1, 0);
        const float k = 1.0f - std::min(1.0f, dist / (rr * 1.2f));
        const float jitter = 0.6f + 0.8f * (((h >> 8) & 255) / 255.0f);
        // los trozos grandes salen más despacio (misma energía repartida en más masa)
        const float massK = std::sqrt(12.0f / static_cast<float>(std::max(12, static_cast<int>(vox.size()))));
        Vec3 vel = d * (speed * (0.4f + 0.6f * k) * jitter * (0.5f + 0.5f * massK)) + Vec3(0, speed * 0.35f * k * massK + 0.8f, 0);
        // EL EMPUJE DEL GOLPE (2026-09-28, el puñetazo: "que el escombro salga empujado hacia donde va el golpe").
        // Determinista (el hash del voxel semilla): igual en todas las maquinas. Los trozos grandes, algo menos.
        vel = vel + push * ((0.7f + 0.6f * (((h >> 16) & 255) / 255.0f)) * (0.55f + 0.45f * massK));
        total += static_cast<int>(vox.size());
        pushPiece(vox, builder, &vel, true);   // siempre cuerpo rígido, aunque sea pequeño
        ++made;
    }
    return total;
}

void Engine::clumpsJob(CarveResult r, float radius, int power, Vec3 push) {
    Timer t;
    const int inClumps = emitClumpsFor(r, radius, power, worker().builder, push);
    // los voxels que salen como trozos rígidos no cuentan como destruidos (conservación de masa)
    world_->undestroy(static_cast<uint64_t>(inClumps));
    LockGuard s(statsLock_);
    stats_.tClumps.add(t.ms());
    stats_.clumpVoxelsTotal += inClumps;
}

void Engine::recordCarve(const CarveResult& r, const Vec3& pos) {
    if (r.removed <= 0) return;
    int best = 1;
    for (int m = 2; m < MAT_COUNT; ++m) if (r.removedByMat[m] > r.removedByMat[best]) best = m;
    if (carveEvents_.size() < 64) carveEvents_.push_back(CarveEvent{pos, r.removed, static_cast<uint8_t>(best)});
}

bool Engine::shoot(const Vec3& origin, const Vec3& dir, float maxDist, int power, RayHit& hit) {
    Timer t;
    if (!world_->raycast(origin, dir, maxDist, hit)) return false;
    CarveResult r;
    r.recordAll = loadModel_;   // para la linea base, si el disparo acaba abriendo analisis
    const int n = world_->carveBullet(hit.voxel, hit.normal, power, rng_, &r);
    lastShotRemoved_ = n;
    if (n > 0) {
        // UN AGUJERO DE BALA NO, PERO DOSCIENTOS SI. Aqui no se abria analisis estructural nunca, con
        // el argumento de que un balazo no hace ceder nada. Cierto para uno; falso para una rafaga que
        // SIERRA una columna. El efecto en el juego era que podias cortar a tiros tres de las cuatro
        // patas de una estructura y no pasaba nada -el peso no la tiraba-, y solo se caia al cortar la
        // cuarta, porque entonces ya no era cuestion de carga sino de que no tocaba nada.
        //
        // Se acumula lo que van quitando las balas y se abre el analisis cuando el agujero ya es de un
        // tamaño que puede importar (un par de secciones de pilar fino). Asi no se paga el analizador
        // en cada tiro y la linea base sigue protegiendo: un boquete pequeño no derriba nada.
        if (loadModel_) acumularDanoBala(r);
        if (r.center.x == 0 && r.center.y == 0 && r.center.z == 0) r.center = hit.pos;
        // la bala empuja los fragmentos hacia dentro: centro de "explosión" delante del impacto
        r.center = hit.pos + Vec3(static_cast<float>(hit.normal.x), static_cast<float>(hit.normal.y), static_cast<float>(hit.normal.z)) * 0.3f;
        // ESQUIRLAS DE VOXEL SOLO EN EL CRISTAL (2026-09-27, pedido: "quitar las esquirlas al disparar"). El agujero
        // se talla igual y el polvo/chispas del juego (effects.impact) siguen; lo que no sale es la lluvia de
        // trocitos de voxel. Explosiones, cohetes y granadas no pasan por aqui y siguen como estaban.
        int dom = 1;
        for (int m = 2; m < MAT_COUNT; ++m) if (r.removedByMat[m] > r.removedByMat[dom]) dom = m;
        if (isGlass(static_cast<uint8_t>(dom))) emitDebrisFor(r, 0.3f, power % 1000);   // (la escopeta lleva +1000)
        recordCarve(r, hit.pos);
    }
    stats_.tCarve.add(t.ms());
    return true;
}

int Engine::carveBeam(const Vec3& origin, const Vec3& dir, float len, float radius, int power, bool vaporize, const Vec3& push) {
    Timer t;
    const float vs = world_->voxelSize();
    Vec3 d = dir;
    const float dl = length(d);
    if (dl < 1e-5f || len <= 0.f) return 0;
    d = d / dl;
    CarveResult r;
    r.center = origin + d * (len * 0.5f);
    r.recordAll = loadModel_;
    // pasos de medio radio: el tubo queda continuo, sin huecos entre esferas
    const float step = std::max(vs * 0.5f, radius * 0.5f);
    const int steps = std::min(4096, static_cast<int>(len / step) + 1);
    int n = 0;
    for (int i = 0; i <= steps; ++i) {
        const Vec3 p = origin + d * std::min(len, i * step);
        n += world_->carveSphere(p, radius, power, &r, false);
    }
    if (n > 0) {
        lastDamageCenter_ = r.center;
        // Un laser VAPORIZA: no lanza escombros ni desprende trozos, solo borra. Con `vaporize`
        // se saltan ambas cosas; lo que si se mantiene es avisar al analizador estructural, que es
        // lo que hace que un edificio al que le sierras los muros acabe cayendose.
        if (!vaporize) {
            emitDebrisFor(r, radius, power, push);
            jobs_->push(-2e9f, [this, r, radius, power, push]() mutable { clumpsJob(std::move(r), radius, power, push); });
        }
        recordCarve(r, r.center);
        if (loadModel_) {
            StructDamage pd;
            pd.mn = r.minVoxel; pd.mx = r.maxVoxel; pd.center = r.center; pd.all = false;
            pd.damaged.reserve(r.voxels.size());
            for (const RemovedVoxel& v : r.voxels) pd.damaged.push_back(IVec3(v.x, v.y, v.z));
            pd.restored.swap(r.all);
            structPending_.push_back(std::move(pd));
            structEventUntil_ = frame_ + 240;
            if (structPending_.size() == 1) structPendingSince_ = frame_;
        }
    }
    stats_.tCarve.add(t.ms());
    return n;
}

int Engine::explode(const Vec3& pos, float radius, int power) {
    Timer t;
    CarveResult r;
    r.center = pos;
    r.recordAll = loadModel_;   // la línea base estructural necesita TODOS los voxels eliminados
    const int n = world_->carveSphere(pos, radius, power, &r);
    if (n > 0) {
        lastDamageCenter_ = pos;
        emitDebrisFor(r, radius, power);
        recordCarve(r, pos);
        if (loadModel_) {
            // SISTEMA ESTRUCTURAL (separado del de impacto): la explosión sólo entrega qué voxels quitó; el
            // analizador decide después qué cede. Se encola porque el analizador puede estar iterando.
            StructDamage pd;
            pd.mn = r.minVoxel; pd.mx = r.maxVoxel; pd.center = pos; pd.all = false;
            pd.damaged.reserve(r.voxels.size());
            for (const RemovedVoxel& v : r.voxels) pd.damaged.push_back(IVec3(v.x, v.y, v.z));
            pd.restored.swap(r.all);
            structPending_.push_back(std::move(pd));
            structEventUntil_ = frame_ + 240;
            if (structPending_.size() == 1) structPendingSince_ = frame_;
        }
        // trozos macizos: generación completa en un hilo de trabajo (20-37 ms por explosión en el principal antes)
        jobs_->push(-2e9f, [this, r, radius, power]() mutable { clumpsJob(std::move(r), radius, power); });
    }
    stats_.tCarve.add(t.ms());
    return n;
}

int Engine::revoxelize(const VoxelBody& body, const Transform& tr, std::vector<CeldaPuesta>* puestas) {
    const float vs = world_->voxelSize();
    int placed = 0;
    // 1) celdas destino, POR MUESTREO INVERSO.
    //
    // Antes se recorrian los voxels del trozo y se llevaba cada uno a su celda del mundo. Eso solo sale
    // bien si el giro es de 90 grados: con un angulo cualquiera, dos voxels de origen caen en la misma
    // celda destino y el trozo aparece AGUJEREADO, con agujeros tanto peores cuanto mas cerca de los
    // 45 grados. Por eso habia que enderezarlo a angulos rectos antes de congelarlo (`snapBasis`), y por
    // eso una viga que caia inclinada se ponia de pronto recta y en otro sitio.
    //
    // Recorriendo el DESTINO y preguntando "que habia aqui en el trozo" no hay agujeros y el giro puede
    // ser el que sea: cada celda del mundo se rellena una sola vez y el trozo se queda tal y como se
    // paro, torcido incluido. Como la base es un giro puro, la inversa es su transpuesta.
    struct Cell { IVec3 v; uint8_t m; };
    static thread_local std::vector<Cell> cells;
    cells.clear();
    const Vec3 tam(body.sx * vs, body.sy * vs, body.sz * vs);
    Vec3 mn(1e30f, 1e30f, 1e30f), mx(-1e30f, -1e30f, -1e30f);
    for (int e = 0; e < 8; ++e) {
        const Vec3 esquina((e & 1) ? tam.x : 0.f, (e & 2) ? tam.y : 0.f, (e & 4) ? tam.z : 0.f);
        const Vec3 w = tr.apply(esquina - body.com);
        mn = Vec3(std::min(mn.x, w.x), std::min(mn.y, w.y), std::min(mn.z, w.z));
        mx = Vec3(std::max(mx.x, w.x), std::max(mx.y, w.y), std::max(mx.z, w.z));
    }
    IVec3 a = world_->toVoxel(mn), b = world_->toVoxel(mx);
    // recortada al mundo: un trozo que se para medio fuera del mapa, si no, hace girar el bucle en vacio
    a = IVec3(std::max(0, a.x), std::max(0, a.y), std::max(0, a.z));
    b = IVec3(std::min(world_->sizeX() - 1, b.x), std::min(world_->sizeY() - 1, b.y), std::min(world_->sizeZ() - 1, b.z));
    const float inv = 1.f / vs;
    for (int z = a.z; z <= b.z; ++z)
    for (int y = a.y; y <= b.y; ++y)
    for (int x = a.x; x <= b.x; ++x) {
        // centro de la celda del mundo -> sistema del trozo (transpuesta del giro) -> indice de voxel
        const float dx = (x + 0.5f) * vs - tr.m[0][3], dy = (y + 0.5f) * vs - tr.m[1][3], dz = (z + 0.5f) * vs - tr.m[2][3];
        const float lx = tr.m[0][0] * dx + tr.m[1][0] * dy + tr.m[2][0] * dz + body.com.x;
        const float ly = tr.m[0][1] * dx + tr.m[1][1] * dy + tr.m[2][1] * dz + body.com.y;
        const float lz = tr.m[0][2] * dx + tr.m[1][2] * dy + tr.m[2][2] * dz + body.com.z;
        const int sx = ifloor(lx * inv), sy = ifloor(ly * inv), sz = ifloor(lz * inv);
        if (sx < 0 || sy < 0 || sz < 0 || sx >= body.sx || sy >= body.sy || sz >= body.sz) continue;
        // Se conserva el material original (antes pasaba a MAT_RUBBLE, que es GRIS: los escombros
        // perdian su color al congelarse y quedaba muy feo). Las balas lo siguen rompiendo igual,
        // porque carveBullet talla con potencia 255 y la dureza va en el radio.
        // Contrapartida: un monton re-voxelizado ahora SI cuenta en el modelo de carga.
        const uint8_t m = body.at(sx, sy, sz);
        if (!m) continue;
        cells.push_back(Cell{IVec3(x, y, z), m});
    }
    if (cells.empty()) return 0;
    // 2) asentar: las cajas de colisión son más gruesas que los voxels, así que el cuerpo dormido queda 1-3
    //    voxels por encima de lo que lo sostiene. Si se colocara tal cual, quedaría sin conexión con el suelo,
    //    el solver lo desprendería otra vez y volvería a caer: bucle de piezas (rompía cosas "solo" y daba lag).
    //    Se baja el conjunto hasta que alguna celda toque un voxel sólido (máx. 6 voxels).
    //
    //    DOS VOXELS COMO MUCHO. Con siete, un trozo que se habia quedado apoyado en un bordillo o con
    //    un hueco debajo (un arbol tronchado, un semaforo doblado) BAJABA HASTA MEDIO METRO al
    //    congelarse: aparecia hundido y en otro sitio del que se veia. El hueco que hay que salvar es
    //    solo el grosor de mas de las cajas de colision, o sea uno o dos voxels; si mas abajo no hay
    //    nada, se deja flotando donde estaba, que es donde el jugador lo vio pararse.
    {
        const int MAX_BAJAR = 2;
        int drop = MAX_BAJAR + 1;
        for (const Cell& c : cells) {
            if (drop == 0) break;
            for (int d = 0; d < drop; ++d) {
                const int yy = c.v.y - 1 - d;
                if (yy < 0) { drop = std::min(drop, d); break; }
                if (world_->getVoxel(c.v.x, yy, c.v.z) != MAT_AIR) { drop = std::min(drop, d); break; }
            }
        }
        if (drop > MAX_BAJAR) drop = 0;   // nada debajo a mano: se queda donde esta
        if (drop > 0) for (Cell& c : cells) c.v.y -= drop;
    }
    for (const Cell& c : cells) {
        if (world_->getVoxel(c.v.x, c.v.y, c.v.z) != MAT_AIR) continue;
        world_->setVoxel(c.v.x, c.v.y, c.v.z, c.m, false);   // re-voxelizar no es daño: no arrastra a lo que flota alrededor
        if (puestas) puestas->push_back(CeldaPuesta{c.v, c.m});
        ++placed;
    }
    ++stats_.revoxelizedBodies;
    return placed;
}

void Engine::markAllDirty() { world_->markAllDirty(); }

// Daño de bala acumulado: se junta lo que quitan los disparos y, cuando pasa del umbral, se entrega al
// analizador como un solo evento (con su linea base). `UMBRAL` esta puesto en el orden de magnitud de
// cortar la seccion de un pilar fino: por debajo de eso no hay nada que recalcular.
void Engine::acumularDanoBala(CarveResult& r) {
    static constexpr int UMBRAL = 120;          // voxels
    static constexpr int LEJOS = 240;           // voxels (24 m a 10 cm): otro sitio, otro evento
    if (r.voxels.empty()) return;
    // ¿el disparo cae lejos de lo acumulado? entonces primero se cierra lo que habia
    if (balaVoxels_ > 0 && (r.minVoxel.x > balaMx_.x + LEJOS || r.maxVoxel.x < balaMn_.x - LEJOS ||
                            r.minVoxel.y > balaMx_.y + LEJOS || r.maxVoxel.y < balaMn_.y - LEJOS ||
                            r.minVoxel.z > balaMx_.z + LEJOS || r.maxVoxel.z < balaMn_.z - LEJOS)) {
        soltarDanoBala();
    }
    if (balaVoxels_ == 0) { balaMn_ = r.minVoxel; balaMx_ = r.maxVoxel; }
    else {
        balaMn_ = IVec3(std::min(balaMn_.x, r.minVoxel.x), std::min(balaMn_.y, r.minVoxel.y), std::min(balaMn_.z, r.minVoxel.z));
        balaMx_ = IVec3(std::max(balaMx_.x, r.maxVoxel.x), std::max(balaMx_.y, r.maxVoxel.y), std::max(balaMx_.z, r.maxVoxel.z));
    }
    for (const RemovedVoxel& v : r.voxels) balaDamaged_.push_back(IVec3(v.x, v.y, v.z));
    balaRestored_.insert(balaRestored_.end(), r.all.begin(), r.all.end());
    balaVoxels_ += static_cast<int>(r.voxels.size());
    balaCentro_ = r.center;
    balaUltimoFrame_ = frame_;
    if (balaVoxels_ >= UMBRAL) soltarDanoBala();
}

void Engine::soltarDanoBala() {
    if (balaVoxels_ <= 0) { balaDamaged_.clear(); balaRestored_.clear(); return; }
    StructDamage pd;
    pd.mn = balaMn_; pd.mx = balaMx_; pd.center = balaCentro_; pd.all = false;
    pd.damaged.swap(balaDamaged_);
    pd.restored.swap(balaRestored_);
    structPending_.push_back(std::move(pd));
    structEventUntil_ = frame_ + 240;
    if (structPending_.size() == 1) structPendingSince_ = frame_;
    balaDamaged_.clear(); balaRestored_.clear(); balaVoxels_ = 0;
}

void Engine::armLoadEval(int frames) {
    (void)frames;
    if (!loadModel_) return;
    // caja de todos los chunks con daño de juego
    IVec3 mn(1 << 30, 1 << 30, 1 << 30), mx(-1, -1, -1);
    const int n = world_->numChunkSlots();
    for (int i = 0; i < n; ++i) {
        const Chunk* c = world_->chunkAt(i);
        if (!c || !c->damaged.load(std::memory_order_relaxed) || c->solidCount == 0) continue;
        mn.x = std::min(mn.x, c->cx * CHUNK_SIZE); mn.y = std::min(mn.y, c->cy * CHUNK_SIZE); mn.z = std::min(mn.z, c->cz * CHUNK_SIZE);
        mx.x = std::max(mx.x, c->cx * CHUNK_SIZE + CHUNK_MASK); mx.y = std::max(mx.y, c->cy * CHUNK_SIZE + CHUNK_MASK); mx.z = std::max(mx.z, c->cz * CHUNK_SIZE + CHUNK_MASK);
    }
    if (mx.x < 0) return;
    StructDamage pd;
    pd.mn = mn; pd.mx = mx; pd.all = true;
    pd.center = Vec3((mn.x + mx.x) * 0.5f, (mn.y + mx.y) * 0.5f, (mn.z + mx.z) * 0.5f) * world_->voxelSize();
    structPending_.push_back(std::move(pd));
    structEventUntil_ = frame_ + 240;
    if (structPending_.size() == 1) structPendingSince_ = frame_;
}

// ---------------------------------------------------------------------------
// Frame
// ---------------------------------------------------------------------------
float Engine::priorityFor(const Chunk& c, const Vec3& playerPos) const {
    const float half = CHUNK_SIZE * world_->voxelSize() * 0.5f;
    const Vec3 center = world_->chunkOrigin(c) + Vec3(half, half, half);
    return dist2(center, playerPos);
}

// SOMBRA HORNEADA: los chunks a los que el chunk c puede tapar el sol son los que quedan "detras" de el
// mirando desde el sol, hasta el alcance del rayo. Se barren las 8 esquinas del chunk hacia atras.
void Engine::anotarSombraDe(const Chunk& c) {
    const int n = world_->numChunkSlots();
    if (static_cast<int>(sombraMarca_.size()) != n) sombraMarca_.assign(n, 0);
    const float vs = world_->voxelSize(), lado = CHUNK_SIZE * vs;
    const Vec3 o = world_->chunkOrigin(c);
    for (int k = 0; k < 8; ++k) {
        const Vec3 p = o + Vec3((k & 1) ? lado : 0.0f, (k & 2) ? lado : 0.0f, (k & 4) ? lado : 0.0f);
        for (float t = 0.0f; t <= solMaxM_ + lado; t += lado * 0.5f) {
            const Vec3 q = p - Vec3(solDx_, solDy_, solDz_) * t;
            const int cx = ifloor(q.x / lado), cy = ifloor(q.y / lado), cz = ifloor(q.z / lado);
            if (cy < 0) break;
            if (cx < 0 || cz < 0 || cx >= world_->chunksX() || cy >= world_->chunksY() || cz >= world_->chunksZ()) continue;
            const int idx = world_->chunkIndex(cx, cy, cz);
            if (!sombraMarca_[idx]) { sombraMarca_[idx] = 1; sombraPend_.push_back(static_cast<uint32_t>(idx)); }
        }
    }
}

void Engine::encolarSombra(uint32_t idx, const Vec3& playerPos) {
    Chunk* c = world_->chunkAt(idx);
    if (!c || c->solidAtomic.load(std::memory_order_relaxed) == 0) return;
    if (c->jobQueued.exchange(true, std::memory_order_acq_rel)) return;   // ya va a remallarse
    labelJobsInFlight_.fetch_add(1, std::memory_order_acq_rel);
    jobs_->push(priorityFor(*c, playerPos) + 1.0e6f, [this, idx] { chunkJob(idx, true); }, idx);
}

void Engine::setSolHorneado(bool on, const Vec3& dir, float alcanceM) {
    const float l = std::sqrt(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z);
    const Vec3 d = l > 1e-5f ? dir * (1.0f / l) : Vec3(0, 1, 0);
    const bool era = solOn_.load(std::memory_order_acquire);
    if (era == on && (!on || (std::fabs(d.x - solDx_) < 1e-3f && std::fabs(d.y - solDy_) < 1e-3f && std::fabs(d.z - solDz_) < 1e-3f && alcanceM == solMaxM_))) return;
    solDx_ = d.x; solDy_ = d.y; solDz_ = d.z; solMaxM_ = alcanceM;
    solOn_.store(on, std::memory_order_release);
    const int n = world_->numChunkSlots();
    for (int i = 0; i < n; ++i) encolarSombra(static_cast<uint32_t>(i), playerPos_);
}

void Engine::setAoLod(bool on) {
    if (aoLod_.exchange(on, std::memory_order_acq_rel) == on) return;
    const int n = world_->numChunkSlots();
    for (int i = 0; i < n; ++i) encolarSombra(static_cast<uint32_t>(i), playerPos_);
}

void Engine::setAoCerca(bool on) {
    if (aoCerca_.exchange(on, std::memory_order_acq_rel) == on) return;
    const int n = world_->numChunkSlots();
    for (int i = 0; i < n; ++i) encolarSombra(static_cast<uint32_t>(i), playerPos_);
}

void Engine::setFaldasLod(bool on) {
    if (faldas_.exchange(on, std::memory_order_acq_rel) == on) return;
    // remallado de todo el mapa a prioridad baja, por el mismo camino que la sombra horneada
    const int n = world_->numChunkSlots();
    for (int i = 0; i < n; ++i) encolarSombra(static_cast<uint32_t>(i), playerPos_);
}

void Engine::enqueueDirty(const Vec3& playerPos) {
    world_->takeDirty(dirtyScratch_);
    const bool sol = solOn_.load(std::memory_order_acquire);
    for (uint32_t idx : dirtyScratch_) {
        Chunk* c = world_->chunkAt(idx);
        if (!c) continue;
        if (sol && c->meshedVersion > 0) anotarSombraDe(*c);
        if (c->jobQueued.exchange(true, std::memory_order_acq_rel)) continue;
        labelJobsInFlight_.fetch_add(1, std::memory_order_acq_rel);
        jobs_->push(priorityFor(*c, playerPos), [this, idx] { chunkJob(idx); }, idx);
    }
    dirtyScratch_.clear();
    // las sombras que cambian se remallan en tandas (cada ~0,5 s): una rafaga de disparos es una sola tanda
    if (sol && !sombraPend_.empty() && (frame_ % 30) == 0) {
        for (uint32_t idx : sombraPend_) { sombraMarca_[idx] = 0; encolarSombra(idx, playerPos); }
        sombraPend_.clear();
    }
}

void Engine::update(float dt, const Vec3& playerPos) {
    Timer t;
    ++frame_;
    playerPos_ = playerPos;
    readyMeshes_.clear();
    readyPieces_.clear();
    carveEvents_.clear();

    // Gobernador: si el host va por encima del presupuesto, el trabajo diferido espera (máx. 6 frames seguidos)
    const bool overBudget = hostFrameMs_ > frameBudgetMs_ * 1.15f && deferStreak_ < 6 && !unlimitedUploads_;
    deferStreak_ = overBudget ? deferStreak_ + 1 : 0;

    { Timer te; enqueueDirty(playerPos); stats_.tUpdEnqueue.add(te.ms()); }
    // El solve cuesta 0,3-2 ms en mapas grandes: se coalescen los cambios de varios frames (ráfagas de
    // disparos) en un solo solve cada 4 frames (66 ms: imperceptible en el derrumbe).
    if (((frame_ & 3) == 0 || unlimitedUploads_) && !overBudget && connChanged_.load(std::memory_order_acquire)) { connChanged_.store(false, std::memory_order_release); runSolve(); }
    // Antes: `loadModel_ && !overBudget`. Justo cuando derrumbas un edificio el motor esta saturado,
    // asi que el analisis de cargas se apagaba EXACTAMENTE en el unico momento en que hace falta y el
    // derrumbe quedaba a merced de la conectividad binaria (un voxel sin cortar sostenia el edificio
    // entero). El trabajo pesado ya corre en un hilo aparte y se autolimita.
    if (loadModel_) updateStructural();
    // PRESUPUESTO DE SUBIDAS ADAPTATIVO. Con 8-16 mallas por frame, un derrumbe deja CIENTOS de
    // chunks esperando: durante segundos se seguian VIENDO trozos de edificio que ya no existen (y
    // que se atravesaban, porque la fisica va por otra cola). Si la cola se dispara, se sube mucho
    // mas por frame: un pico corto es preferible a ver el edificio fantasma medio minuto.
    int subidas = preset_->maxUploadsPerFrame;
    {
        std::lock_guard<std::mutex> g(resultsMutex_);
        const int pend = static_cast<int>(meshResults_.size());
        if (pend > 32) subidas = std::max(subidas, std::min(96, pend / 3));
    }
    { Timer tc; collectResults(unlimitedUploads_ ? INT_MAX : subidas); stats_.tUpdCollect.add(tc.ms()); }

    { Timer td; debris_.update(dt, *world_); smoke_.update(dt, *world_); stats_.tDebris.add(td.ms()); }

    if ((frame_ & 15) == 0) {
        jobs_->reprioritize([this, playerPos](const Job& j) {
            if (j.tag == ~0u) return -1e9f;                     // extracciones y análisis: siempre primero
            Chunk* c = world_->chunkAt(j.tag);
            return c ? priorityFor(*c, playerPos) : 1e30f;
        });
    }

    Timer ts;
    stats_.chunksAllocated = world_->allocatedChunks();
    // recuentos que recorren todos los chunks: cada 16 frames (sólo son estadísticas)
    if ((frame_ & 15) == 1) {
        stats_.voxelsSolid = world_->solidVoxels();
        stats_.memWorldBytes = world_->memoryBytes() + struct_.memoryBytes();
    }
    stats_.voxelsDestroyed = world_->destroyedVoxels();
    stats_.raysTraced = world_->raysTraced(); stats_.raySteps = world_->raySteps(); stats_.raySkips = world_->raySkips();
    stats_.structRegionsActive = struct_.active() ? 1 : 0;
    stats_.tUpdStats.add(ts.ms());
    stats_.jobsPending = jobs_->pending() + jobs_->running();
    { std::lock_guard<std::mutex> g(resultsMutex_); stats_.meshResultsPending = static_cast<int>(meshResults_.size()); }
    stats_.debrisActive = debris_.count();
    stats_.debrisCapacity = debris_.capacity();
    stats_.tUpdate.add(t.ms());
}

void Engine::collectResults(int maxUploads) {
    std::vector<VoxelBody> pieces;
    int taken = 0;
    {
        std::lock_guard<std::mutex> g(resultsMutex_);
        size_t consumed = 0;
        for (; consumed < meshResults_.size() && taken < maxUploads; ++consumed) {
            ChunkMeshResult& r = meshResults_[consumed];
            Chunk* c = world_->chunkAt(r.chunkIdx);
            if (!c || r.version < c->meshedVersion || (r.version == c->meshedVersion && !r.soloSombra)) continue;   // resultado obsoleto: hay uno más nuevo
            c->meshedVersion = r.version;
            readyMeshes_.push_back(std::move(r));
            ++taken;
        }
        meshResults_.erase(meshResults_.begin(), meshResults_.begin() + consumed);
        pieces.swap(pieceResults_);
        if (!failDebris_.empty()) {
            const float vsd = world_->voxelSize();
            // EL AJUSTE "PARTICULAS DE DESTRUCCION" TAMBIEN AQUI (2026-10-05, bug: "la puse en Off y me las sigue
            // generando"): en Off ninguna, y con Pocas/Normales la parte que toca (por hash: la misma en cada maquina)
            const uint32_t umbral = static_cast<uint32_t>(std::min(1.f, debrisScale_) * 1024.f);
            for (const BodyVoxel& v : failDebris_) {
                const uint32_t h = hash3(v.x, v.y, v.z);
                if (((h >> 3) & 1023u) >= umbral) continue;
                debris_.emitAt(world_->voxelCenter(IVec3(v.x, v.y, v.z)),
                               Vec3(((h & 255) / 255.f - 0.5f) * 1.2f, -0.5f - ((h >> 8) & 255) / 255.f, (((h >> 16) & 255) / 255.f - 0.5f) * 1.2f),
                               vsd * 0.9f, v.mat, static_cast<uint16_t>(h >> 16));
            }
            failDebris_.clear();
        }
    }
    stats_.meshUploadsThisFrame = taken;
    // DETERMINISMO (Fase 30): las piezas llegan en el orden en que terminan los hilos; el host las crea y
    // re-voxeliza en ese orden y dos trozos que se solapan al aterrizar dan mundos distintos según quién llegue
    // antes. Orden fijo: id (hash del primer voxel), tamaño, origen.
    std::sort(pieces.begin(), pieces.end(), [](const VoxelBody& a, const VoxelBody& b) {
        if (a.id != b.id) return a.id < b.id;
        if (a.voxelCount != b.voxelCount) return a.voxelCount < b.voxelCount;
        if (a.worldOrigin.x != b.worldOrigin.x) return a.worldOrigin.x < b.worldOrigin.x;
        if (a.worldOrigin.y != b.worldOrigin.y) return a.worldOrigin.y < b.worldOrigin.y;
        return a.worldOrigin.z < b.worldOrigin.z;
    });
    for (VoxelBody& b : pieces) {
        if (b.mesh.empty()) {
            // Pieza diminuta: cada voxel cae desde su sitio como escombro (sin rigid body, sin azar).
            // (con el ajuste de particulas: en Off no sale nada; ver failDebris_ arriba)
            const float vs = world_->voxelSize();
            const uint32_t umbralP = static_cast<uint32_t>(std::min(1.f, debrisScale_) * 1024.f);
            for (int z = 0; z < b.sz; ++z) for (int y = 0; y < b.sy; ++y) for (int x = 0; x < b.sx; ++x) {
                const uint8_t m = b.at(x, y, z);
                if (!m) continue;
                const Vec3 p = b.worldOrigin + Vec3((x + 0.5f) * vs, (y + 0.5f) * vs, (z + 0.5f) * vs);
                const uint32_t h = hash3(static_cast<int>(p.x * 8), static_cast<int>(p.y * 8), static_cast<int>(p.z * 8));
                if (((h >> 3) & 1023u) >= umbralP) continue;
                debris_.emitAt(p, Vec3(((h & 255) / 255.f - 0.5f) * 0.6f, 0.2f, (((h >> 8) & 255) / 255.f - 0.5f) * 0.6f), vs * 0.9f, m, static_cast<uint16_t>(h >> 16));
            }
            ++stats_.piecesToDebrisTotal;
        } else {
            ++stats_.bodiesCreatedTotal;
            readyPieces_.push_back(std::move(b));
        }
    }
}

void Engine::runSolve() {
    Timer t;
    solver_.solve(*world_, groupsScratch_);
    stats_.chunksSkippedNoLock = solver_.lastSkippedNoLock();
    if (!desprender_) {   // invitado de LAN: aqui no se separa nada, lo que cae lo manda el anfitrion
        groupsScratch_.clear();
        stats_.tSolve.add(t.ms());
        return;
    }
    const bool structural = loadModel_ && (struct_.active() || frame_ <= structEventUntil_);
    for (DetachedGroup& g : groupsScratch_) {
        if (g.nodes.empty()) continue;
        { LockGuard s(statsLock_); if (structural) ++stats_.groupsStructuralTotal; else ++stats_.groupsPlainTotal; stats_.groupVoxelsTotal += static_cast<int>(g.voxelCount); }
        for (const DetachedNode& nd : g.nodes) world_->chunkAt(nd.chunkIdx)->extracting.fetch_add(1, std::memory_order_acq_rel);
        const Chunk* c0 = world_->chunkAt(g.nodes[0].chunkIdx);
        const float prio = priorityFor(*c0, playerPos_) - 1e9f;   // las extracciones van antes que los remallados
        DetachedGroup copy = std::move(g);
        extractInFlight_.fetch_add(1, std::memory_order_acq_rel);
        jobs_->push(prio, [this, copy, structural] { extractJob(copy, structural); });
        ++stats_.piecesDetachedTotal;
    }
    groupsScratch_.clear();
    stats_.tSolve.add(t.ms());
    ++stats_.solvesRun;
}

// Planificación del analizador estructural (hilo principal). Sólo se itera cuando no hay extracciones en
// vuelo ni etiquetados pendientes: así cada iteración ve el mundo estable tras los fallos anteriores y la
// secuencia es determinista (misma entrada -> mismas iteraciones -> mismos fallos).
void Engine::applyStructFailure(std::vector<FailCell> cells, const FailGroup& group) {
    if (cells.empty()) return;
    extractInFlight_.fetch_add(1, std::memory_order_acq_rel);
    FailGroup g = group;
    g.firstCell = 0;
    g.cellCount = static_cast<int32_t>(cells.size());
    jobs_->push(-1.5e9f, [this, cells, g]() mutable { extractCellsJob(std::move(cells), g); });
}

void Engine::updateStructural() {
    // SIN AUTORIDAD NO SE ANALIZA: los fallos llegan del anfitrion. Ademas se ahorra el coste del analisis
    // en los moviles que juegan de invitado.
    if (!structAuthority_) {
        structPending_.clear();
        return;
    }
    // AL DEJAR DE DISPARAR, SE ANALIZA LO QUE QUITARON LAS BALAS (2026-09-28). Desde que las paredes aguantan balas
    // (World::danarBala) cada tiro quita 1-3 voxels y no 20-50: cortar a tiros dos patas de una mesa no llegaba nunca a
    // los 120 del umbral y la mesa se quedaba flotando (con el mazo si caia: ese tallado abre analisis al momento).
    // Ahora, 20 fotogramas (~1/3 s) sin tiros en la zona y lo acumulado se analiza. Una rafaga sigue siendo un
    // analisis, no uno por bala.
    if (balaVoxels_ > 0 && frame_ - balaUltimoFrame_ > 20) soltarDanoBala();
    if (structRunning_.load(std::memory_order_acquire)) return;
    if (structDone_.exchange(false, std::memory_order_acq_rel)) {
        StructResult res;
        { std::lock_guard<std::mutex> g(structMutex_); res.cells.swap(structResult_.cells); res.groups.swap(structResult_.groups); res.islands.swap(structResult_.islands); res.iteration = structResult_.iteration; res.stable = structResult_.stable; res.overloaded = structResult_.overloaded; res.worstPos = structResult_.worstPos; res.worstRatio = structResult_.worstRatio; }
        // Copiar la instantanea del depurador es ~1 MB por iteracion EN EL HILO PRINCIPAL. Con la
        // vista apagada solo hacen falta los contadores de resumen, que son cuatro numeros.
        if (structDebugOn_) {
            structDebugCopy_ = struct_.debug();
        } else {
            const StructDebug& sd = struct_.debug();
            structDebugCopy_.islandsEvaluated = sd.islandsEvaluated; structDebugCopy_.islandsSkipped = sd.islandsSkipped;
            structDebugCopy_.cellsEvaluated = sd.cellsEvaluated; structDebugCopy_.cellsScanned = sd.cellsScanned;
            structDebugCopy_.worstRatio = sd.worstRatio; structDebugCopy_.iteration = sd.iteration;
            structDebugCopy_.failures = sd.failures; structDebugCopy_.ms = sd.ms; structDebugCopy_.scanMs = sd.scanMs;
        }
        stats_.tStruct.add(structJobMs_); stats_.tStructScan.add(structScanMs_);
        ++stats_.structIterationsTotal;
        stats_.structIslandsEvaluated = structDebugCopy_.islandsEvaluated; stats_.structIslandsSkipped = structDebugCopy_.islandsSkipped;
        stats_.structCellsEvaluated = structDebugCopy_.cellsEvaluated; stats_.structCellsScannedTotal = structDebugCopy_.cellsScanned;
        stats_.structWorstRatio = structDebugCopy_.worstRatio;
        stats_.structWorstX = res.worstPos.x; stats_.structWorstY = res.worstPos.y; stats_.structWorstZ = res.worstPos.z;
        stats_.structFailuresTotal += static_cast<int>(res.cells.size());
        stats_.structFragmentsTotal += static_cast<int>(res.groups.size());
        for (const FailGroup& G : res.groups) {
            if (!desprender_) break;   // invitado: el fallo por sobrecarga tampoco separa nada aqui
            std::vector<FailCell> cells(res.cells.begin() + G.firstCell, res.cells.begin() + G.firstCell + G.cellCount);
            if (structOut_.size() < 4096) structOut_.push_back(StructFailureOut{cells, G});
            extractInFlight_.fetch_add(1, std::memory_order_acq_rel);
            jobs_->push(-1.5e9f, [this, cells, G]() mutable { extractCellsJob(std::move(cells), G); });
        }
        // AQUI HABIA UN AVISO PREVIO (crujido + polvillo donde la estructura estaba al limite). Fuera.
        // La calibracion deja la estructura INTACTA en ~0,8, asi que medio mapa vive por encima de 0,9
        // sin estar a punto de nada; y como el analizador vuelve a iterar cada 6 frames mientras la
        // region siga despierta, el aviso se repetia en bucle: crujido y polvo eternos en sitios donde
        // no iba a caer nada nunca. Un aviso que suena siempre no avisa de nada, solo molesta y gasta.
        if (res.stable && structPending_.empty()) { struct_.reset(); structIdleIters_ = 0; return; }   // estable: la región duerme
        // Tope de iteraciones: cuenta las iteraciones SIN fallos (celdas acumulando deformación que no llegan a
        // ceder); mientras haya fallos el derrumbe sigue (con un tope duro de cordura). Antes el tope era total y un
        // edificio grande se quedaba a medio caer, sobrecargado pero "estable" para siempre.
        structIdleIters_ = res.cells.empty() ? structIdleIters_ + 1 : 0;
        if ((structIdleIters_ >= structParams_.maxIterations || struct_.iteration() >= 96) && structPending_.empty()) { struct_.reset(); structIdleIters_ = 0; return; }
        // RITMO ADAPTATIVO. En una zona cerrada (el spawn de la policia de dust2) una iteracion cuesta
        // 15-50 ms y encadenandolas cada 6 frames el analizador se comia la maquina durante 15 s
        // seguidos. Se espera en proporcion a lo que costo la ultima: como mucho ~25 % del tiempo.
        const uint32_t cool = static_cast<uint32_t>(structJobMs_ / 16.7 * 4.0);
        // DESCANSO, pero solo cuando no esta cayendo nada. Aplicarlo tambien durante el derrumbe
        // hacia que el edificio se deshiciera A CACHITOS: cada iteracion soltaba un puñado de
        // celdas y se dormia 3 s, asi que en vez de venirse abajo se desmigajaba durante medio
        // minuto (y el jugador se colaba entre los trozos). Mientras haya celdas cediendo se itera
        // al ritmo rapido de siempre; el descanso es para la region que ya no rompe nada.
        const bool cayendo = !res.cells.empty();
        const uint32_t rest = cayendo
            ? std::max(static_cast<uint32_t>(structParams_.iterationIntervalFrames), cool)
            : std::max(static_cast<uint32_t>(structParams_.iterationIntervalFrames), std::max(cool, structSleepFrames_));
        structNextFrame_ = frame_ + (unlimitedUploads_ ? 0u : rest);
        structEventUntil_ = std::max(structEventUntil_, frame_ + 240u);
    }
    // Dano nuevo: si la region esta DORMIDA se atiende enseguida (el impacto tiene que notarse ya).
    // Si ya esta despierta, se respeta el descanso: antes cualquier disparo adelantaba la siguiente
    // iteracion y disparando seguido el analisis no paraba nunca.
    if (!structPending_.empty() && !struct_.active())
        structNextFrame_ = std::min(structNextFrame_, frame_ + static_cast<uint32_t>(unlimitedUploads_ ? 0 : structParams_.iterationIntervalFrames));
    if ((!struct_.active() && structPending_.empty()) || frame_ < structNextFrame_) return;
    // sólo se itera con el mundo quieto: sin extracciones en vuelo, sin etiquetados pendientes, sin grupos por resolver
    // Los jobs de extraccion/etiquetado SI son excluyentes: tocan las mismas estructuras.
    if (extractInFlight_.load(std::memory_order_acquire) != 0 || labelJobsInFlight_.load(std::memory_order_acquire) != 0) return;
    // "Mundo quieto" (sin chunks sucios ni conectividad pendiente) es lo ideal, pero durante un derrumbe
    // los trozos que caen y se re-voxelizan lo ensucian sin parar: el analisis se posponia para siempre.
    // Si el dano lleva mas de dos segundos esperando, se analiza igual: el escaneo relee los chunks
    // sucios de todas formas.
    // 24 frames (0,4 s) desde 2026-09-18: eran 120 (2 s) y demoliendo el mundo nunca esta quieto, asi que el
    // derrumbe tardaba hasta dos segundos en enterarse de que tenia que caer
    const bool stale = !structPending_.empty() && frame_ > structPendingSince_ + 12u;   // 0,2 s (eran 2 s): demoliendo el mundo nunca esta quieto y el derrumbe tardaba en enterarse
    if (!stale && (connChanged_.load(std::memory_order_acquire) || world_->hasDirty())) return;
    if (!struct_.active()) struct_.setParams(structParams_);
    std::vector<StructDamage> pending;
    pending.swap(structPending_);
    structRunning_.store(true, std::memory_order_release);
    jobs_->push(-1.8e9f, [this, pending]() mutable { structJob(std::move(pending)); });
}

void Engine::structJob(std::vector<StructDamage> pending) {
    Timer t;
    for (const StructDamage& d : pending) struct_.applyDamage(*world_, d);   // abre/amplía la región y la línea base
    StructResult res;
    struct_.iterate(*world_, res);
    {
        std::lock_guard<std::mutex> g(structMutex_);
        structResult_.cells.swap(res.cells); structResult_.groups.swap(res.groups); structResult_.islands.swap(res.islands);
        structResult_.iteration = res.iteration; structResult_.stable = res.stable; structResult_.overloaded = res.overloaded;
        structResult_.worstPos = res.worstPos; structResult_.worstRatio = res.worstRatio;
        structJobMs_ = t.ms(); structScanMs_ = struct_.debug().scanMs;
    }
    structDone_.store(true, std::memory_order_release);
    structRunning_.store(false, std::memory_order_release);
}

bool Engine::isIdle() const {
    if (jobs_->pending() != 0 || jobs_->running() != 0) return false;
    if (world_->hasDirty()) return false;
    if (connChanged_.load(std::memory_order_acquire)) return false;
    if (loadModel_ && (struct_.active() || structRunning_.load(std::memory_order_acquire) || structDone_.load(std::memory_order_acquire) || !structPending_.empty())) return false;
    if (extractInFlight_.load(std::memory_order_acquire) != 0) return false;
    std::lock_guard<std::mutex> g(const_cast<std::mutex&>(resultsMutex_));
    return meshResults_.empty() && pieceResults_.empty();
}

void Engine::waitIdle(std::vector<ChunkMeshResult>* meshesOut, std::vector<VoxelBody>* piecesOut) {
    const bool prev = unlimitedUploads_;
    unlimitedUploads_ = true;
    for (int i = 0; i < 100000; ++i) {
        jobs_->waitIdle();
        if (isIdle()) break;
        update(0.f, playerPos_);
        if (meshesOut) for (auto& m : readyMeshes_) meshesOut->push_back(std::move(m));
        if (piecesOut) for (auto& p : readyPieces_) piecesOut->push_back(std::move(p));
    }
    unlimitedUploads_ = prev;
}

// ---------------------------------------------------------------------------
// Trabajo de chunk (hilo de trabajo): conectividad local + malla + LOD
// ---------------------------------------------------------------------------
void Engine::chunkJob(uint32_t idx, bool soloSombra) {
    Chunk* c = world_->chunkAt(idx);
    if (!c) { labelJobsInFlight_.fetch_sub(1, std::memory_order_acq_rel); return; }
    Worker& w = worker();
    Timer t;
    c->jobQueued.store(false, std::memory_order_release);   // una edición posterior lo re-encola

    const uint32_t version = world_->snapshotPadded(*c, w.padded.data());
    for (int z = 0; z < CHUNK_SIZE; ++z)
        for (int y = 0; y < CHUNK_SIZE; ++y)
            std::memcpy(&w.vox[Chunk::index(0, y, z)], &w.padded[1 + (y + 1) * PAD_SIZE + (z + 1) * PAD_SIZE * PAD_SIZE], CHUNK_SIZE);

    bool needConn; bool pristine; bool damaged;
    { LockGuard g(c->lock); needConn = !(c->conn.valid && c->conn.version == version); pristine = c->pristine.load(std::memory_order_relaxed); damaged = c->damaged.load(std::memory_order_relaxed); }
    if (needConn) {
        Timer tc;
        labelChunk(w.vox.data(), w.padded.data(), c->cy * CHUNK_SIZE, w.scratch, *w.conn);
        // Chunk intacto: lo que contiene es estático mientras TODO su conjunto conexo siga intacto (la regla
        // "pristine" se aplica por conjunto en ConnectivitySolver::solve, no por chunk: si no, al romper un
        // objeto que cruza varios chunks, la parte que sigue en un chunk intacto se quedaba flotando).
        {
            LockGuard g(c->lock);
            c->conn.pristine = pristine;
            c->conn.damaged = damaged;
            c->conn.numComp = w.conn->numComp;
            std::memcpy(c->conn.border, w.conn->border, sizeof(c->conn.border));
            std::memcpy(c->conn.compVoxels, w.conn->compVoxels, sizeof(c->conn.compVoxels));
            std::memcpy(c->conn.compAnchored, w.conn->compAnchored, sizeof(c->conn.compAnchored));
            c->conn.version = version;
            c->conn.valid = true;
            c->compCount.store(w.conn->numComp, std::memory_order_release);
            c->labeledVersion.store(version, std::memory_order_release);
        }
        // Aristas con los 6 vecinos
        thread_local std::vector<uint8_t> seen(65536, 0);
        for (int f = 0; f < 6; ++f) {
            Chunk* n = world_->chunk(c->cx + FACE_DIR[f][0], c->cy + FACE_DIR[f][1], c->cz + FACE_DIR[f][2]);
            if (!n) continue;
            bool nValid; uint32_t nVersion;
            {
                LockGuard g(n->lock);
                nValid = n->conn.valid; nVersion = n->conn.version;
                if (nValid) std::memcpy(w.nbBorder.data(), n->conn.border[f ^ 1], CHUNK_AREA);
            }
            w.pairs.clear();
            if (nValid) {
                const uint8_t* A = w.conn->border[f];
                const uint8_t* B = w.nbBorder.data();
                for (int i = 0; i < CHUNK_AREA; ++i) {
                    if (!A[i] || !B[i]) continue;
                    const uint16_t key = static_cast<uint16_t>((A[i] << 8) | B[i]);
                    if (seen[key]) continue;
                    seen[key] = 1; w.pairs.push_back(key);
                }
                for (uint16_t k : w.pairs) seen[k] = 0;
            }
            const int axis = f >> 1;
            if (f & 1) {   // cara positiva: los pares viven en este chunk
                LockGuard g(c->lock);
                c->conn.edges[axis] = w.pairs; c->conn.edgesVersion[axis] = nVersion;
            } else {       // cara negativa: viven en el vecino, con el orden (vecino, propio)
                for (uint16_t& p : w.pairs) p = static_cast<uint16_t>(((p & 0xFF) << 8) | (p >> 8));
                LockGuard g(n->lock);
                n->conn.edges[axis] = w.pairs; n->conn.edgesVersion[axis] = version;
            }
        }
        connChanged_.store(true, std::memory_order_release);
        { LockGuard s(statsLock_); stats_.tConnLabel.add(tc.ms()); }
    }

    // Malla completa + LOD
    ChunkMeshResult r;
    r.chunkIdx = idx; r.version = version; r.soloSombra = soloSombra;
    const float vs = world_->voxelSize();
    SolTrazador sol;
    const bool conSol = solOn_.load(std::memory_order_acquire);
    if (conSol) {
        sol.world = world_.get();
        sol.ox = c->cx * CHUNK_SIZE; sol.oy = c->cy * CHUNK_SIZE; sol.oz = c->cz * CHUNK_SIZE;
        sol.dx = solDx_; sol.dy = solDy_; sol.dz = solDz_; sol.maxVox = solMaxM_ / vs;
    }
    PaddedGrid g{w.padded.data(), CHUNK_SIZE, CHUNK_SIZE, CHUNK_SIZE};
    static const bool sinAoCerca = std::getenv("VX_SIN_AO_CERCA") != nullptr;   // banco: cuantos triangulos cuesta el AO
    w.mesher.conAO = !sinAoCerca && aoCerca_.load(std::memory_order_acquire);
    w.mesher.grupoDe = colorTex_.load(std::memory_order_acquire) ? gruposColor_ : nullptr;
    w.mesher.mesh(g, vs, Vec3(0, 0, 0), r.mesh, conSol ? &sol : nullptr);
    if (!r.mesh.empty()) {
        // la colision, aparte y sin colores (ver Mesher::soloForma): aqui, en el hilo de trabajo
        w.mesher.soloForma = true;
        w.mesher.mesh(g, vs, Vec3(0, 0, 0), r.col);
        // y la de SOMBRA: la misma forma sin el cristal. El caster de sombras usaba la malla de dibujo, troceada por
        // colores (en la cafeteria 670 k triangulos de sombra): la silueta es la misma con muchos menos.
        if (shadowShape_.load(std::memory_order_acquire)) {
            w.mesher.sinCristal = true;
            w.mesher.mesh(g, vs, Vec3(0, 0, 0), r.sh);
            w.mesher.sinCristal = false;
        }
        w.mesher.soloForma = false;
    }
    if (!r.mesh.empty()) {
        Mesher::downsample2x(w.padded.data(), w.lodPadded.data());
        // FALDAS EN LAS LOD (2026-09-23): lineas del color del cielo en el suelo a lo lejos. La malla gruesa de un
        // chunk no dibuja su cara lateral si el vecino es solido, pero el vecino puede estar a OTRO nivel de detalle
        // (otra region), con el suelo a otra altura, y entre los dos quedaba una rendija sin pared. Para mallar las
        // LOD se toma el relleno lateral (x y z) como aire: cada chunk cierra sus bordes y la rendija queda tapada.
        // Solo la malla, no la conectividad ni la colision (que no usan las LOD).
        auto sinBordes = [](const uint8_t* src, int dim, std::vector<uint8_t>& dst) {
            const int P = dim + 2;
            dst.assign(src, src + static_cast<size_t>(P) * P * P);
            for (int z = 0; z < P; ++z) for (int y = 0; y < P; ++y) for (int x = 0; x < P; ++x)
                if (x == 0 || z == 0 || x == P - 1 || z == P - 1) dst[x + y * P + z * P * P] = 0;
        };
        thread_local std::vector<uint8_t> lodFalda, lod2Falda;
        const bool falda = faldas_.load(std::memory_order_acquire);
        sinBordes(w.lodPadded.data(), CHUNK_SIZE / 2, lodFalda);
        PaddedGrid gl{falda ? lodFalda.data() : w.lodPadded.data(), CHUNK_SIZE / 2, CHUNK_SIZE / 2, CHUNK_SIZE / 2};
        sol.escala = 2;
        // las LOD, sin AO salvo que se pida (setAoLod): de lejos no se ve y funde un tercio de las caras
        w.mesher.conAO = aoLod_.load(std::memory_order_acquire);
        w.mesher.mesh(gl, vs * 2, Vec3(0, 0, 0), r.lod, conSol ? &sol : nullptr);
        Mesher::downsample2xGrid(w.lodPadded.data(), CHUNK_SIZE / 2, w.lod2Padded.data());
        sinBordes(w.lod2Padded.data(), CHUNK_SIZE / 4, lod2Falda);
        PaddedGrid gl2{falda ? lod2Falda.data() : w.lod2Padded.data(), CHUNK_SIZE / 4, CHUNK_SIZE / 4, CHUNK_SIZE / 4};
        sol.escala = 4;
        w.mesher.mesh(gl2, vs * 4, Vec3(0, 0, 0), r.lod2, conSol ? &sol : nullptr);
        Mesher::downsample2xGridMin(w.padded.data(), CHUNK_SIZE, w.occPadded.data());
        PaddedGrid go{w.occPadded.data(), CHUNK_SIZE / 2, CHUNK_SIZE / 2, CHUNK_SIZE / 2};
        w.mesher.conAO = false;   // un oclusor solo tapa: el AO solo le partia las caras
        w.mesher.mesh(go, vs * 2, Vec3(0, 0, 0), r.occ);
        w.mesher.conAO = true;
    }
    r.empty = r.mesh.empty();
    { std::lock_guard<std::mutex> gr(resultsMutex_); meshResults_.push_back(std::move(r)); }
    { LockGuard s(statsLock_); stats_.tMeshJob.add(t.ms()); }
    labelJobsInFlight_.fetch_sub(1, std::memory_order_acq_rel);
}

// ---------------------------------------------------------------------------
// Vuelco y entrega de piezas
// ---------------------------------------------------------------------------
void Engine::tiltForFailure(const std::vector<BodyVoxel>& vox, const Vec3& dirHint, Vec3& outVel, Vec3& outAngVel) const {
    outVel = Vec3(); outAngVel = Vec3();
    if (vox.empty()) return;
    // centro de masas de la pieza y polígono de apoyo REAL: voxels de su capa inferior que tienen sólido debajo
    double cx = 0, cy = 0, cz = 0, wsum = 0; int minY = INT_MAX;
    for (const BodyVoxel& v : vox) minY = std::min(minY, v.y);
    double bx = 0, bz = 0; int nb = 0;
    double sx = 0, sz = 0; int ns = 0;
    for (const BodyVoxel& v : vox) {
        const double w = std::max(0.05, static_cast<double>(massOf(v.mat)));
        cx += v.x * w; cy += v.y * w; cz += v.z * w; wsum += w;
        if (v.y == minY) {
            bx += v.x; bz += v.z; ++nb;
            if (isSolid(world_->getVoxel(v.x, v.y - 1, v.z))) { sx += v.x; sz += v.z; ++ns; }
        }
    }
    if (wsum <= 0) wsum = 1;
    cx /= wsum; cy /= wsum; cz /= wsum;
    double dx, dz;
    if (ns > 0) { dx = cx - sx / ns; dz = cz - sz / ns; }          // sobresale respecto al apoyo que le queda
    else if (nb > 0 && (dirHint.x != 0.f || dirHint.z != 0.f)) { dx = dirHint.x; dz = dirHint.z; }
    else { dx = cx - bx / std::max(1, nb); dz = cz - bz / std::max(1, nb); }
    double len = std::sqrt(dx * dx + dz * dz);
    if (len < 0.5) {
        // apoyo centrado: vuelca hacia el apoyo perdido (pista del analizador) o, sin pista, con un sesgo determinista
        if (dirHint.x != 0.f || dirHint.z != 0.f) { dx = dirHint.x; dz = dirHint.z; }
        else { const uint32_t h = hash3(vox[0].x, vox[0].y, vox[0].z); dx = (h & 1) ? 1.0 : -1.0; dz = (h & 2) ? 0.35 : -0.35; }
        len = std::sqrt(dx * dx + dz * dz);
    }
    if (len < 1e-6) return;
    dx /= len; dz /= len;
    const float vs = world_->voxelSize();
    const float height = static_cast<float>(cy - minY) * vs;                 // altura del CDM sobre el apoyo (m)
    const float lever = static_cast<float>(std::min(len, 8.0)) * vs;
    // giro alrededor del eje horizontal perpendicular a la dirección de vuelco: eje = up x dir hace que la
    // parte alta se mueva hacia dir
    const float w = clampv(0.35f + lever / std::max(0.5f, height) * 1.2f, 0.35f, 1.4f);
    outAngVel = Vec3(static_cast<float>(dz), 0.f, static_cast<float>(-dx)) * w;
    outVel = Vec3(static_cast<float>(dx), 0.f, static_cast<float>(dz)) * (w * height * 0.5f) + Vec3(0, -0.3f, 0);
}

void Engine::pushPiece(std::vector<BodyVoxel>& vox, BodyBuilder& builder, const Vec3* initialVel, bool forceBody, const Vec3* initialAngVel) {
    if (vox.empty()) return;
    VoxelBody body;
    if (initialVel) body.initialVel = *initialVel;
    if (initialAngVel) body.initialAngVel = *initialAngVel;
    const float vs = world_->voxelSize();
    // id determinista (hash del primer voxel): antes era un contador por orden de llegada de los hilos y el host
    // lo usa para variar giros y cadencias -> mismo derrumbe, distinto aspecto entre ejecuciones
    const uint32_t id = (hash3(vox[0].x, vox[0].y, vox[0].z) >> 1) | 1u;
    if (!forceBody && vox.size() < static_cast<size_t>(minBodyVoxels())) {
        // diminuta: rejilla con los voxels (sin malla ni cajas) -> partículas en el hilo principal, cada
        // voxel desde su posición
        int mnx = INT_MAX, mny = INT_MAX, mnz = INT_MAX, mxx = INT_MIN, mxy = INT_MIN, mxz = INT_MIN;
        int cnt[MAT_COUNT] = {0};
        for (const BodyVoxel& v : vox) {
            mnx = std::min(mnx, v.x); mny = std::min(mny, v.y); mnz = std::min(mnz, v.z);
            mxx = std::max(mxx, v.x); mxy = std::max(mxy, v.y); mxz = std::max(mxz, v.z);
            ++cnt[v.mat < MAT_COUNT ? v.mat : 0];
        }
        body.id = id;
        body.sx = mxx - mnx + 1; body.sy = mxy - mny + 1; body.sz = mxz - mnz + 1;
        body.vox.assign(static_cast<size_t>(body.sx) * body.sy * body.sz, 0);
        for (const BodyVoxel& v : vox) body.vox[(v.x - mnx) + (v.y - mny) * body.sx + (v.z - mnz) * body.sx * body.sy] = v.mat;
        body.voxelCount = static_cast<uint32_t>(vox.size());
        body.worldOrigin = Vec3(mnx * vs, mny * vs, mnz * vs);
        body.com = Vec3(body.sx * vs * 0.5f, body.sy * vs * 0.5f, body.sz * vs * 0.5f);
        int best = 1; for (int m = 2; m < MAT_COUNT; ++m) if (cnt[m] > cnt[best]) best = m;
        body.dominantMat = static_cast<uint8_t>(best);
    } else {
        // Piezas rígidas con pocas cajas: cada par pieza-chunk cuesta cajas x cajas en Jolt (20 x 20 por par
        // dejaba la física en 16 ms con 18 cuerpos). 6 cajas bastan para el bulto de un trozo.
        builder.build(vox, vs, std::min(6, preset_->maxBoxesPerBody), id, body);
        // build() reinicia el cuerpo: las velocidades iniciales (explosión, vuelco) se asignan DESPUÉS
        if (initialVel) body.initialVel = *initialVel;
        if (initialAngVel) body.initialAngVel = *initialAngVel;
    }
    std::lock_guard<std::mutex> g(resultsMutex_);
    pieceResults_.push_back(std::move(body));
}

void Engine::pushPieceSplit(std::vector<BodyVoxel>& pieceVox, std::vector<BodyVoxel>& subVox, BodyBuilder& builder, bool structural, const Vec3* tiltVel, const Vec3* tiltAng) {
    const float vs = world_->voxelSize();
    // UN EDIFICIO QUE SE CAE, CAE ENTERO. El tope normal de voxels por cuerpo esta pensado para
    // cascotes; aplicado a un derrumbe partia la parte que se venia abajo en mil trozos antes
    // siquiera de tocar el suelo. En un derrumbe estructural se admiten piezas MUCHISIMO mas
    // grandes: la planta, o el edificio entero, baja como un solo cuerpo y se rompe al chocar.
    const size_t limite = structural ? static_cast<size_t>(maxBodyVoxels()) * 12u : static_cast<size_t>(maxBodyVoxels());
    if (pieceVox.size() <= limite) { pushPiece(pieceVox, builder, tiltVel, false, tiltAng); return; }
    // Pieza enorme: se parte en varios cuerpos mas pequenos y baratos. Si es un derrumbe estructural, la
    // particion es en bloques irregulares (bordes dentados por un ruido de baja frecuencia) en vez de
    // cubos de chunk: el edificio se desmorona en cascotes grandes que caen y se apilan. El tamano de
    // bloque es fijo en todas las calidades y plataformas (juego competitivo: todos ven el mismo derrumbe).
    //
    // Estaba en 1,4 m y una torre se deshacia en MILES de cascotes: no parecia un derrumbe sino que se
    // desmigajaba, y ademas el presupuesto de colisiones (unos 600 cuerpos) se agotaba enseguida, asi
    // que la mitad de los trozos eran fantasmas y el jugador se colaba entre ellos y caia al vacio.
    // A 3,2 m salen ~12 veces menos piezas, mas grandes, y casi todas con colision.
    // y si aun asi es demasiado, se parte en pedazos GRANDES (8 m), no en cascotes
    // 14 m desde 2026-09-18 (era 8): el techo de 9 m de la mesa de pruebas salia en 29 cuerpos y en Monaco a
    // 10 cm los derrumbes caian en trozos de 2-3 k voxels escalonados ("domino"). Pedido por el usuario.
    // 14 m desde 2026-09-18 (era 8): pedido por el usuario para que los derrumbes salgan en menos trozos.
    const int K = structural ? clampv(static_cast<int>(std::lround(14.0f / vs)), 5, 160) : CHUNK_SIZE;
    auto ckey = [K](const BodyVoxel& v) {
        int x = v.x, y = v.y, z = v.z;
        if (K != CHUNK_SIZE) {
            // desplazamiento por bloque de 4 voxels (bordes dentados, blobs irregulares)
            const uint32_t h = hash3(v.x >> 2, v.y >> 2, v.z >> 2);
            x += static_cast<int>(h % 5) - 2; y += static_cast<int>((h >> 8) % 5) - 2; z += static_cast<int>((h >> 16) % 5) - 2;
        }
        const int kx = (x + 4096) / K, ky = (y + 4096) / K, kz = (z + 4096) / K;
        return (static_cast<uint64_t>(kx) << 42) | (static_cast<uint64_t>(ky) << 21) | static_cast<uint64_t>(kz);
    };
    // DESEMPATE POR COORDENADAS (auditoria, 2026-10-05): std::sort no es estable y cada biblioteca (MSVC en el PC, libc++
    // en Android) deja los voxels de la misma celda en otro orden. El id del bloque es el hash de su PRIMER voxel, asi que
    // un PC y un movil podian dar ids distintos al mismo pedazo (y en red los bloques se buscan por id). Ahora el orden
    // es total: mismo primer voxel en todas las maquinas.
    std::sort(pieceVox.begin(), pieceVox.end(), [&](const BodyVoxel& a, const BodyVoxel& b) {
        const uint64_t ka = ckey(a), kb = ckey(b);
        if (ka != kb) return ka < kb;
        if (a.x != b.x) return a.x < b.x;
        if (a.y != b.y) return a.y < b.y;
        return a.z < b.z;
    });
    size_t s = 0;
    while (s < pieceVox.size()) {
        size_t e = s; const uint64_t k = ckey(pieceVox[s]);
        while (e < pieceVox.size() && ckey(pieceVox[e]) == k) ++e;
        subVox.assign(pieceVox.begin() + s, pieceVox.begin() + e);
        const Vec3* pv = tiltVel; const Vec3* pa = tiltAng;
        Vec3 bv, ba;
        if (structural && tiltVel && tiltAng) {
            // cada bloque hereda la inclinación del conjunto con una variación propia (no caen todos igual)
            const uint32_t h = hash3(subVox[0].x, subVox[0].y, subVox[0].z);
            const float j = 0.6f + 0.8f * ((h & 255) / 255.f);
            bv = *tiltVel * j; ba = *tiltAng * (0.5f + ((h >> 8) & 255) / 255.f);
            pv = &bv; pa = &ba;
        }
        pushPiece(subVox, builder, pv, false, pa);
        s = e;
    }
}

// ---------------------------------------------------------------------------
// Extracción de una pieza desprendida por conectividad (hilo de trabajo)
// ---------------------------------------------------------------------------
void Engine::extractJob(DetachedGroup group, bool structural) {
    Worker& w = worker();
    Timer t;
    w.pieceVox.clear();
    for (const DetachedNode& nd : group.nodes) {
        Chunk* c = world_->chunkAt(nd.chunkIdx);
        if (!c) continue;
        int removed = 0;
        // 1) copia rápida bajo lock (~2 µs)  2) etiquetado SIN lock (~0.2 ms)  3) extracción bajo lock si la
        // versión no cambió (las etiquetas siguen siendo válidas). Así el hilo principal nunca espera al etiquetado.
        bool valid;
        {
            LockGuard g(c->lock);
            valid = (c->version == nd.connVersion);
            if (valid) std::memcpy(w.vox.data(), c->vox, CHUNK_VOLUME);
        }
        if (valid) {
            labelChunk(w.vox.data(), nullptr, c->cy * CHUNK_SIZE, w.scratch, *w.conn);
            const uint8_t* label = w.scratch.label.data();
            const int bx = c->cx * CHUNK_SIZE, by = c->cy * CHUNK_SIZE, bz = c->cz * CHUNK_SIZE;
            LockGuard g(c->lock);
            if (c->version == nd.connVersion) {
                for (int i = 0; i < CHUNK_VOLUME; ++i) {
                    if (label[i] != nd.label) continue;
                    w.pieceVox.push_back(BodyVoxel{bx + (i & CHUNK_MASK), by + ((i >> CHUNK_BITS) & CHUNK_MASK), bz + (i >> (2 * CHUNK_BITS)), c->vox[i]});
                    c->vox[i] = MAT_AIR;
                    ++removed;
                }
                if (removed) { c->solidCount -= removed; c->bumpVersion(true); c->pristine.store(false, std::memory_order_relaxed); }
            }
        }
        c->extracting.fetch_sub(1, std::memory_order_acq_rel);
        if (removed) {
            world_->markDirty(*c);
            for (int f = 0; f < 6; ++f) {
                Chunk* n = world_->chunk(c->cx + FACE_DIR[f][0], c->cy + FACE_DIR[f][1], c->cz + FACE_DIR[f][2]);
                if (n) world_->markDirty(*n);
            }
        }
    }
    if (w.pieceVox.empty()) { connChanged_.store(true, std::memory_order_release); extractInFlight_.fetch_sub(1, std::memory_order_acq_rel); return; }
    static const bool logGroups = std::getenv("VX_LOGGROUPS") != nullptr;
    if (logGroups) {
        int mny = 1 << 30, mxy = -1, mat[MAT_COUNT] = {0};
        for (const BodyVoxel& v : w.pieceVox) { mny = std::min(mny, v.y); mxy = std::max(mxy, v.y); ++mat[v.mat]; }
        int best = 1; for (int m = 2; m < MAT_COUNT; ++m) if (mat[m] > mat[best]) best = m;
        std::fprintf(stderr, "[grp] f=%d %s vox=%zu y=%d..%d at(%d,%d,%d) mat=%s\n", static_cast<int>(frame_), structural ? "DERRUMBE" : "suelto", w.pieceVox.size(), mny, mxy, w.pieceVox[0].x, w.pieceVox[0].y, w.pieceVox[0].z, material(static_cast<uint8_t>(best)).name);
    }
    // Derrumbe (evento estructural en curso): la parte que cae nace con un giro hacia el lado sin apoyo,
    // así se inclina y cae como en la realidad en vez de quedarse en equilibrio.
    Vec3 tiltVel, tiltAng;
    const Vec3* pv = nullptr; const Vec3* pa = nullptr;
    if (structural) {
        const float vs = world_->voxelSize();
        Vec3 hint;
        {
            double mx = 0, mz = 0; for (const BodyVoxel& v : w.pieceVox) { mx += v.x; mz += v.z; }
            hint = Vec3(static_cast<float>(mx / w.pieceVox.size()) * vs - lastDamageCenter_.x, 0.f, static_cast<float>(mz / w.pieceVox.size()) * vs - lastDamageCenter_.z);
        }
        tiltForFailure(w.pieceVox, hint, tiltVel, tiltAng);
        pv = &tiltVel; pa = &tiltAng;
    }
    pushPieceSplit(w.pieceVox, w.subVox, w.builder, structural, pv, pa);
    { LockGuard s(statsLock_); stats_.tExtract.add(t.ms()); }
    extractInFlight_.fetch_sub(1, std::memory_order_acq_rel);
}

// ---------------------------------------------------------------------------
// Extracción de un grupo de celdas que fallan (hilo de trabajo): las celdas salen como fragmento con vuelco;
// lo que quede sin conexión con el suelo lo desprende después el solver de conectividad.
// ---------------------------------------------------------------------------
void Engine::extractCellsJob(std::vector<FailCell> cells, FailGroup group) {
    Worker& w = worker();
    Timer t;
    w.pieceVox.clear();
    for (const FailCell& f : cells) {
        for (int cz = f.min.z >> CHUNK_BITS; cz <= (f.max.z >> CHUNK_BITS); ++cz)
        for (int cy = f.min.y >> CHUNK_BITS; cy <= (f.max.y >> CHUNK_BITS); ++cy)
        for (int cx = f.min.x >> CHUNK_BITS; cx <= (f.max.x >> CHUNK_BITS); ++cx) {
            Chunk* c = world_->chunk(cx, cy, cz);
            if (!c) continue;
            int removed = 0;
            bool edge[6] = {false, false, false, false, false, false};
            {
                LockGuard g(c->lock);
                for (int z = std::max(f.min.z, cz * CHUNK_SIZE); z <= std::min(f.max.z, cz * CHUNK_SIZE + CHUNK_MASK); ++z)
                for (int y = std::max(f.min.y, cy * CHUNK_SIZE); y <= std::min(f.max.y, cy * CHUNK_SIZE + CHUNK_MASK); ++y)
                for (int x = std::max(f.min.x, cx * CHUNK_SIZE); x <= std::min(f.max.x, cx * CHUNK_SIZE + CHUNK_MASK); ++x) {
                    const int lx = x & CHUNK_MASK, ly = y & CHUNK_MASK, lz = z & CHUNK_MASK;
                    uint8_t& m = c->vox[Chunk::index(lx, ly, lz)];
                    if (!m || isAnchor(m) || isIndestructible(m)) continue;
                    w.pieceVox.push_back(BodyVoxel{x, y, z, m});
                    m = MAT_AIR; ++removed;
                    if (lx == 0) edge[0] = true; if (lx == CHUNK_MASK) edge[1] = true;
                    if (ly == 0) edge[2] = true; if (ly == CHUNK_MASK) edge[3] = true;
                    if (lz == 0) edge[4] = true; if (lz == CHUNK_MASK) edge[5] = true;
                }
                if (removed) { c->solidCount -= removed; c->bumpVersion(true); c->pristine.store(false, std::memory_order_relaxed); }
            }
            if (removed) {
                world_->markDirty(*c);
                for (int fc = 0; fc < 6; ++fc) {
                    if (!edge[fc]) continue;
                    Chunk* n = world_->chunk(cx + FACE_DIR[fc][0], cy + FACE_DIR[fc][1], cz + FACE_DIR[fc][2]);
                    if (n) world_->markDirty(*n);
                }
            }
        }
    }
    connChanged_.store(true, std::memory_order_release);   // lo que quede colgando lo resuelve la conectividad
    if (!w.pieceVox.empty()) {
        static const bool logGroups = std::getenv("VX_LOGGROUPS") != nullptr;
        if (logGroups) std::fprintf(stderr, "[grp] f=%d FALLO isla=%d celdas=%zu vox=%zu at(%d,%d,%d)\n", static_cast<int>(frame_), group.island, cells.size(), w.pieceVox.size(), w.pieceVox[0].x, w.pieceVox[0].y, w.pieceVox[0].z);
        // (2026-09-18: se probo convertir en polvo las celdas pequenas que ceden y un trozo de via que caia
        // se deshacia en particulas: "es un bug". Lo que cede cae como bloque, siempre.)
        Vec3 tiltVel, tiltAng;
        tiltForFailure(w.pieceVox, group.tiltDir, tiltVel, tiltAng);
        pushPieceSplit(w.pieceVox, w.subVox, w.builder, true, &tiltVel, &tiltAng);
    }
    { LockGuard s(statsLock_); stats_.tExtract.add(t.ms()); }
    extractInFlight_.fetch_sub(1, std::memory_order_acq_rel);
}

void Engine::auditFloaters(std::vector<DetachedGroup>& out) {
    solver_.auditNoPristine = true;
    solver_.solve(*world_, out);
    solver_.auditNoPristine = false;
}

int Engine::weldFloaters(int maxGroupVoxels, int maxGap, int* outSinSoldar, int* outVoxelsEscritos) {
    std::vector<DetachedGroup> groups;
    auditFloaters(groups);
    Worker& w = worker();
    static const int D[6][3] = {{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}};
    auto key = [](int x, int y, int z) { return (static_cast<uint64_t>(x) << 42) | (static_cast<uint64_t>(y) << 21) | static_cast<uint64_t>(z); };
    std::vector<IVec3> vox; std::vector<uint8_t> mats;
    std::unordered_set<uint64_t> mine;
    std::vector<Chunk*> tocados;
    int soldados = 0, sinSoldar = 0, escritos = 0;
    for (const DetachedGroup& g : groups) {
        if (static_cast<int>(g.voxelCount) > maxGroupVoxels) { ++sinSoldar; continue; }
        // 1) los voxels del grupo (mismo etiquetado que extractJob, sin quitar nada)
        vox.clear(); mats.clear(); mine.clear();
        for (const DetachedNode& nd : g.nodes) {
            Chunk* c = world_->chunkAt(nd.chunkIdx);
            if (!c) continue;
            { LockGuard lg(c->lock); std::memcpy(w.vox.data(), c->vox, CHUNK_VOLUME); }
            labelChunk(w.vox.data(), nullptr, c->cy * CHUNK_SIZE, w.scratch, *w.conn);
            const uint8_t* label = w.scratch.label.data();
            const int bx = c->cx * CHUNK_SIZE, by = c->cy * CHUNK_SIZE, bz = c->cz * CHUNK_SIZE;
            for (int i = 0; i < CHUNK_VOLUME; ++i) {
                if (label[i] != nd.label) continue;
                const int x = bx + (i & CHUNK_MASK), y = by + ((i >> CHUNK_BITS) & CHUNK_MASK), z = bz + (i >> (2 * CHUNK_BITS));
                vox.push_back(IVec3{x, y, z}); mats.push_back(w.vox[i]); mine.insert(key(x, y, z));
            }
        }
        if (vox.empty()) { ++sinSoldar; continue; }
        // 2) el puente mas corto: desde cada voxel del grupo, por cada eje, hasta maxGap celdas de aire; vale
        //    tanto un solido ajeno de frente como uno pegado de lado a la ultima celda (contacto por arista)
        int bestGap = 1 << 30, bestK = -1, bestD = -1, bestLen = 0;
        for (size_t k = 0; k < vox.size() && bestGap > 1; ++k) {
            const IVec3 v = vox[k];
            for (int d = 0; d < 6; ++d) {
                for (int step = 1; step <= maxGap; ++step) {
                    const int px = v.x + D[d][0] * step, py = v.y + D[d][1] * step, pz = v.z + D[d][2] * step;
                    if (!world_->inBounds(px, py, pz)) break;
                    if (world_->getVoxel(px, py, pz) != MAT_AIR) {
                        if (!mine.count(key(px, py, pz)) && step - 1 >= 1 && step - 1 < bestGap) { bestGap = step - 1; bestK = static_cast<int>(k); bestD = d; bestLen = step - 1; }
                        break;
                    }
                    // celda de aire: ¿un solido ajeno pegado de lado?
                    bool lateral = false;
                    for (int e = 0; e < 6 && !lateral; ++e) {
                        if (e == d || e == (d ^ 1)) continue;
                        const int qx = px + D[e][0], qy = py + D[e][1], qz = pz + D[e][2];
                        if (!world_->inBounds(qx, qy, qz)) continue;
                        if (world_->getVoxel(qx, qy, qz) != MAT_AIR && !mine.count(key(qx, qy, qz))) lateral = true;
                    }
                    if (lateral && step < bestGap) { bestGap = step; bestK = static_cast<int>(k); bestD = d; bestLen = step; }
                }
            }
        }
        if (bestK < 0) { ++sinSoldar; continue; }
        // 3) rellenar el hueco con el material del voxel de partida
        const IVec3 v = vox[static_cast<size_t>(bestK)];
        for (int step = 1; step <= bestLen; ++step) {
            const int px = v.x + D[bestD][0] * step, py = v.y + D[bestD][1] * step, pz = v.z + D[bestD][2] * step;
            world_->setVoxel(px, py, pz, mats[static_cast<size_t>(bestK)], false);
            if (Chunk* c = world_->chunk(px >> CHUNK_BITS, py >> CHUNK_BITS, pz >> CHUNK_BITS)) tocados.push_back(c);
            ++escritos;
        }
        ++soldados;
    }
    // soldar no es dano: lo soldado sigue siendo parte del mapa intacto
    for (Chunk* c : tocados) c->pristine.store(true, std::memory_order_relaxed);
    if (outSinSoldar) *outSinSoldar = sinSoldar;
    if (outVoxelsEscritos) *outVoxelsEscritos = escritos;
    return soldados;
}

} // namespace vx
