# BREACH

Shooter en primera persona (FPS) con **destrucción total del mundo por voxels**, al estilo Teardown, pensado para
**PC y Android** de gama baja. Todos los edificios se pueden romper y se caen por su propio peso.

Proyecto hecho por **[tu nombre]** programando junto a **Claude Code** (IA de Anthropic) como asistente.

## Cómo jugar en PC

1. Descargá el repositorio (botón verde **Code → Download ZIP**) y descomprimilo.
2. Doble clic en **`JUGAR.bat`**.
   - La primera vez descarga el motor Godot 4.7.2 (~60 MB) e importa los recursos: tarda unos minutos.
   - Las siguientes veces abre al instante.

Requisitos: Windows 10/11 de 64 bits, 4 GB de RAM, cualquier placa de video con Vulkan.

**Controles:** WASD moverse · ratón apuntar · clic izquierdo disparar · clic derecho mirilla · R recargar ·
G granada · Espacio saltar · Shift correr · Esc menú.

## Qué tiene

- Motor de destrucción propio en **C++17** (`core/`): mundo de voxels, explosiones, mallado, análisis estructural
  (qué se cae cuando rompés una columna) y navegación A* para los bots.
- Integración con **Godot 4** como GDExtension (`godot/extension/`): render directo al RenderingServer y física Jolt.
- El juego en **GDScript** (`godot/scripts/`): bots con IA, armas, modos (bomba, duelo a muerte, battle royale,
  campaña cooperativa contra zombis, prop hunt), multijugador LAN/online, interfaz para móvil.
- Servidor en **Node.js** (`servidor/`) para cuentas, salas online y progreso.
- Panel de administración en Godot (`admin/`).

## Estructura

```
core/        motor de voxels en C++ (sin dependencias)
godot/       proyecto Godot: escenas, scripts, mapas, modelos, sonidos
servidor/    servidor Node.js (cuentas, salas, tienda)
admin/       app de administración
tools/       scripts de compilación y generadores de mapas (Python)
docs/        documentación técnica (empezá por docs/RECORRIDO.md)
JUGAR.bat    abre el juego
EDITOR.bat   abre el proyecto en el editor de Godot
```

## Compilar el motor C++ (opcional)

El repositorio ya trae la DLL compilada. Para recompilarla hacen falta Visual Studio 2022, CMake y Ninja:

```bat
git clone -b 4.4 https://github.com/godotengine/godot-cpp godot/extension/godot-cpp
tools\build_extension.bat
```

## Notas

- Esta versión **no incluye pagos con dinero real**: la pasarela de pago se quitó.
- Algunos sonidos son de terceros y están puestos de forma temporal, solo para pruebas.
