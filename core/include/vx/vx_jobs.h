// vxcore - Job system: pool de hilos con cola priorizada
// ---------------------------------------------------------------------------
// Los trabajos pesados (remallado, etiquetado, extracción) se hacen en hilos
// de trabajo. El hilo principal sólo encola y recoge resultados. La cola está
// priorizada por distancia al jugador: lo que el jugador ve se resuelve primero.
// ---------------------------------------------------------------------------
#pragma once
#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <mutex>
#include <thread>
#include <vector>

namespace vx {

struct Job {
    float priority;                 // menor = antes
    uint32_t tag;                   // dato libre para re-priorizar (ej. índice de chunk); ~0u = sin tag
    std::function<void()> run;
};

class JobSystem {
public:
    explicit JobSystem(int threads);
    ~JobSystem();
    void push(float priority, std::function<void()> fn, uint32_t tag = ~0u);
    int pending() const { return pending_.load(std::memory_order_relaxed); }
    int running() const { return running_.load(std::memory_order_relaxed); }
    int threads() const { return static_cast<int>(workers_.size()); }
    // Re-prioriza los trabajos pendientes con una función (hilo principal, barato: pocas decenas/cientos).
    void reprioritize(const std::function<float(const Job&)>& fn);
    void waitIdle();                // bloquea hasta vaciar cola (benchmark/tests)

private:
    void workerLoop();
    std::vector<std::thread> workers_;
    std::vector<Job> queue_;
    std::mutex m_;
    std::condition_variable cv_;
    std::condition_variable idleCv_;
    std::atomic<int> pending_{0};
    std::atomic<int> running_{0};
    bool stop_ = false;
};

} // namespace vx
