// Ajustes del PROCESO en Windows, aparte para no meter <windows.h> (y sus macros) en voxel_world.cpp.
// En Android y demas no hace nada.
#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

// SIN ECOQOS (2026-10-01, solo para medir): Windows 11 puede "ahorrar energia" en un proceso cuya ventana no tiene el
// foco (power throttling): lo pasa a nucleos y frecuencias bajas y lo despierta tarde de cada espera. Las ventanas de
// los bancos se abren en segundo plano, y salian tirones de ~120 ms en sitios sin nada que ver (un print, un rayo,
// abrir una carpeta). Con esto el proceso pide que no se le aplique. Devuelve true si Windows lo acepto.
bool vx_quitar_ecoqos() {
#ifdef _WIN32
    PROCESS_POWER_THROTTLING_STATE st{};
    st.Version = PROCESS_POWER_THROTTLING_CURRENT_VERSION;
    st.ControlMask = PROCESS_POWER_THROTTLING_EXECUTION_SPEED | PROCESS_POWER_THROTTLING_IGNORE_TIMER_RESOLUTION;
    st.StateMask = 0;   // control tomado y estado apagado = sin ahorro
    return SetProcessInformation(GetCurrentProcess(), ProcessPowerThrottling, &st, sizeof(st)) != 0;
#else
    return false;
#endif
}
