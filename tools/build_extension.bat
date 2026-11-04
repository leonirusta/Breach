@echo off
REM Compila la GDExtension breach_voxel (godot-cpp + vxcore + capa Godot) para Windows x86_64.
REM Resultado: godot\bin\libbreach_voxel.windows.template_release.x86_64.dll
setlocal
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
set CMAKE="C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
set NINJA="C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe"
cd /d "%~dp0\..\godot\extension"
if not exist godot-cpp\CMakeLists.txt (
  echo Falta godot-cpp. Clonalo con:  git clone --depth 1 -b 4.5 https://github.com/godotengine/godot-cpp.git godot\extension\godot-cpp
  exit /b 1
)
if not exist build mkdir build
%CMAKE% -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DGODOTCPP_TARGET=template_release -DCMAKE_MAKE_PROGRAM=%NINJA% || exit /b 1
%CMAKE% --build build --target breach_voxel || exit /b 1
echo.
echo OK: godot\bin\libbreach_voxel.windows.template_release.x86_64.dll
