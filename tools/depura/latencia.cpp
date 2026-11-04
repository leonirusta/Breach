// latencia.exe <segundos>: un hilo que duerme 1 ms una y otra vez y apunta cuando tarda mucho mas en volver, y otro
// que gira sin dormir y apunta cuando le quitan la CPU. Si ve parones de ~120 ms a la vez que el juego, no son del juego.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <timeapi.h>
#include <cstdio>
#include <thread>
#include <atomic>
#include <vector>

static double ahora_ms() {
    static LARGE_INTEGER f = [] { LARGE_INTEGER x; QueryPerformanceFrequency(&x); return x; }();
    LARGE_INTEGER c; QueryPerformanceCounter(&c);
    return double(c.QuadPart) * 1000.0 / double(f.QuadPart);
}

int main(int argc, char** argv) {
    double seg = argc > 1 ? atof(argv[1]) : 60.0;
    timeBeginPeriod(1);
    std::atomic<bool> fin{false};
    double t0 = ahora_ms();
    std::vector<std::pair<double, double>> dormir, girar;
    std::thread g([&] {
        double prev = ahora_ms();
        while (!fin) {
            double t = ahora_ms();
            if (t - prev > 15.0) girar.push_back({(prev - t0) / 1000.0, t - prev});
            prev = t;
        }
    });
    while (ahora_ms() - t0 < seg * 1000.0) {
        double a = ahora_ms();
        Sleep(1);
        double d = ahora_ms() - a;
        if (d > 15.0) dormir.push_back({(a - t0) / 1000.0, d});
    }
    fin = true;
    g.join();
    timeEndPeriod(1);
    int d50 = 0, d100 = 0, g50 = 0, g100 = 0;
    for (auto& x : dormir) { if (x.second > 50) ++d50; if (x.second > 100) ++d100; }
    for (auto& x : girar) { if (x.second > 50) ++g50; if (x.second > 100) ++g100; }
    printf("[latencia] %.0f s · dormir 1 ms: %zu veces > 15 ms, %d > 50, %d > 100 · girando: %zu > 15 ms, %d > 50, %d > 100\n",
           seg, dormir.size(), d50, d100, girar.size(), g50, g100);
    for (auto& x : dormir) if (x.second > 40) printf("[latencia]   dormir: a %.1f s, %.0f ms\n", x.first, x.second);
    for (auto& x : girar) if (x.second > 40) printf("[latencia]   girar: a %.1f s, %.0f ms\n", x.first, x.second);
    return 0;
}
