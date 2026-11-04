// depura.exe <programa> [args...]: lanza el programa bajo la API de depuracion de Windows y, si hay un acceso a
// memoria invalido (o cualquier excepcion grave), dice en que hilo, modulo y desplazamiento, y una pila "a lo bruto"
// (los valores de la pila que caen dentro de algun modulo cargado). Solo para diagnosticar el cierre de Breach.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <psapi.h>
#include <cstdio>
#include <string>
#include <vector>
#include <map>

struct Modulo { std::wstring nombre; DWORD64 base; DWORD64 tam; };
static std::vector<Modulo> g_mods;
static std::map<DWORD, HANDLE> g_hilos;
static DWORD g_hiloPrincipal = 0;
static HANDLE g_proc = nullptr;

static DWORD64 tamImagen(HANDLE proc, DWORD64 base) {
    IMAGE_DOS_HEADER dos{}; SIZE_T n = 0;
    if (!ReadProcessMemory(proc, (LPCVOID)base, &dos, sizeof(dos), &n)) return 0;
    IMAGE_NT_HEADERS64 nt{};
    if (!ReadProcessMemory(proc, (LPCVOID)(base + dos.e_lfanew), &nt, sizeof(nt), &n)) return 0;
    return nt.OptionalHeader.SizeOfImage;
}

static std::wstring nombreDeArchivo(HANDLE h) {
    wchar_t buf[MAX_PATH * 2] = {0};
    if (h && GetFinalPathNameByHandleW(h, buf, MAX_PATH * 2, FILE_NAME_NORMALIZED)) {
        std::wstring s(buf);
        size_t p = s.find_last_of(L"\\/");
        return p == std::wstring::npos ? s : s.substr(p + 1);
    }
    return L"?";
}

static std::wstring dondeEsta(DWORD64 a) {
    for (const Modulo& m : g_mods) {
        if (a >= m.base && a < m.base + m.tam) {
            wchar_t b[64]; swprintf(b, 64, L"+0x%llx", (unsigned long long)(a - m.base));
            return m.nombre + b;
        }
    }
    return L"";
}

int wmain(int argc, wchar_t** argv) {
    if (argc < 2) { fwprintf(stderr, L"uso: depura <programa> [args]\n"); return 2; }
    std::wstring cmd;
    for (int i = 1; i < argc; ++i) {
        if (i > 1) cmd += L" ";
        cmd += L"\""; cmd += argv[i]; cmd += L"\"";
    }
    STARTUPINFOW si{}; si.cb = sizeof(si);
    PROCESS_INFORMATION pi{};
    std::vector<wchar_t> linea(cmd.begin(), cmd.end()); linea.push_back(0);
    if (!CreateProcessW(nullptr, linea.data(), nullptr, nullptr, TRUE, DEBUG_ONLY_THIS_PROCESS, nullptr, nullptr, &si, &pi)) {
        fwprintf(stderr, L"[depura] no se pudo lanzar (%lu)\n", GetLastError()); return 3;
    }
    g_proc = pi.hProcess;
    DWORD codigoSalida = 0;
    int avs = 0;
    for (;;) {
        DEBUG_EVENT ev{};
        if (!WaitForDebugEvent(&ev, INFINITE)) break;
        DWORD cont = DBG_CONTINUE;
        switch (ev.dwDebugEventCode) {
        case CREATE_PROCESS_DEBUG_EVENT: {
            g_hiloPrincipal = ev.dwThreadId;
            g_hilos[ev.dwThreadId] = ev.u.CreateProcessInfo.hThread;
            DWORD64 base = (DWORD64)ev.u.CreateProcessInfo.lpBaseOfImage;
            g_mods.push_back({nombreDeArchivo(ev.u.CreateProcessInfo.hFile), base, tamImagen(g_proc, base)});
            if (ev.u.CreateProcessInfo.hFile) CloseHandle(ev.u.CreateProcessInfo.hFile);
            break;
        }
        case CREATE_THREAD_DEBUG_EVENT:
            g_hilos[ev.dwThreadId] = ev.u.CreateThread.hThread;
            break;
        case EXIT_THREAD_DEBUG_EVENT:
            if (ev.u.ExitThread.dwExitCode != 0) fwprintf(stderr, L"[depura] hilo %lu sale con 0x%08lx%ls\n", ev.dwThreadId, ev.u.ExitThread.dwExitCode, ev.dwThreadId == g_hiloPrincipal ? L" (PRINCIPAL)" : L"");
            g_hilos.erase(ev.dwThreadId);
            break;
        case LOAD_DLL_DEBUG_EVENT: {
            DWORD64 base = (DWORD64)ev.u.LoadDll.lpBaseOfDll;
            g_mods.push_back({nombreDeArchivo(ev.u.LoadDll.hFile), base, tamImagen(g_proc, base)});
            if (ev.u.LoadDll.hFile) CloseHandle(ev.u.LoadDll.hFile);
            break;
        }
        case UNLOAD_DLL_DEBUG_EVENT: {
            DWORD64 base = (DWORD64)ev.u.UnloadDll.lpBaseOfDll;
            for (Modulo& m : g_mods) if (m.base == base) { fwprintf(stderr, L"[depura] se descarga %ls\n", m.nombre.c_str()); m.nombre += L"(descargado)"; }
            break;
        }
        case EXCEPTION_DEBUG_EVENT: {
            const EXCEPTION_RECORD& er = ev.u.Exception.ExceptionRecord;
            DWORD code = er.ExceptionCode;
            bool grave = code == EXCEPTION_ACCESS_VIOLATION || code == 0xC0000374 || code == EXCEPTION_STACK_OVERFLOW
                      || code == EXCEPTION_ILLEGAL_INSTRUCTION || code == 0xC0000409 || code == EXCEPTION_INT_DIVIDE_BY_ZERO;
            if (code == EXCEPTION_BREAKPOINT || code == 0x4000001F) { cont = DBG_CONTINUE; break; }
            cont = DBG_EXCEPTION_NOT_HANDLED;
            {
                static int otras = 0;
                if (!grave && otras < 60) { ++otras; fwprintf(stderr, L"[depura] excepcion 0x%08lx en %ls (hilo %lu, %ls)\n", code, dondeEsta((DWORD64)er.ExceptionAddress).c_str(), ev.dwThreadId, ev.u.Exception.dwFirstChance ? L"1a" : L"2a"); }
            }
            if (!grave || avs >= 4) break;
            ++avs;
            DWORD64 dir = (DWORD64)er.ExceptionAddress;
            fwprintf(stderr, L"\n[depura] EXCEPCION 0x%08lx (%ls) en el hilo %lu%ls\n", code, ev.u.Exception.dwFirstChance ? L"primera vez" : L"SEGUNDA vez, mortal",
                     ev.dwThreadId, ev.dwThreadId == g_hiloPrincipal ? L" (el PRINCIPAL)" : L" (otro hilo)");
            fwprintf(stderr, L"[depura]   instruccion en 0x%llx %ls\n", (unsigned long long)dir, dondeEsta(dir).c_str());
            if (code == EXCEPTION_ACCESS_VIOLATION && er.NumberParameters >= 2)
                fwprintf(stderr, L"[depura]   %ls la direccion 0x%llx\n", er.ExceptionInformation[0] == 0 ? L"leyendo" : (er.ExceptionInformation[0] == 1 ? L"escribiendo" : L"ejecutando"),
                         (unsigned long long)er.ExceptionInformation[1]);
            auto it = g_hilos.find(ev.dwThreadId);
            if (it != g_hilos.end()) {
                CONTEXT ctx{}; ctx.ContextFlags = CONTEXT_FULL;
                if (GetThreadContext(it->second, &ctx)) {
                    fwprintf(stderr, L"[depura]   rip %ls  rcx 0x%llx rdx 0x%llx\n", dondeEsta(ctx.Rip).c_str(), (unsigned long long)ctx.Rcx, (unsigned long long)ctx.Rdx);
                    std::vector<DWORD64> pila(2048);
                    SIZE_T n = 0;
                    ReadProcessMemory(g_proc, (LPCVOID)ctx.Rsp, pila.data(), pila.size() * 8, &n);
                    int k = 0;
                    for (size_t i = 0; i < n / 8 && k < 40; ++i) {
                        std::wstring w = dondeEsta(pila[i]);
                        if (!w.empty()) { fwprintf(stderr, L"[depura]     pila[%3zu] %ls\n", i, w.c_str()); ++k; }
                    }
                }
            }
            fwprintf(stderr, L"[depura]   hilos vivos: %zu\n", g_hilos.size());
            break;
        }
        case OUTPUT_DEBUG_STRING_EVENT: break;
        case RIP_EVENT: fwprintf(stderr, L"[depura] RIP_EVENT\n"); break;
        case EXIT_PROCESS_DEBUG_EVENT:
            codigoSalida = ev.u.ExitProcess.dwExitCode;
            fwprintf(stderr, L"[depura] el proceso termino con 0x%08lx\n", codigoSalida);
            ContinueDebugEvent(ev.dwProcessId, ev.dwThreadId, DBG_CONTINUE);
            return 0;
        default: break;
        }
        ContinueDebugEvent(ev.dwProcessId, ev.dwThreadId, cont);
    }
    return 0;
}
