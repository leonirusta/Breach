@echo off
REM Compila la GDExtension breach_voxel para ANDROID arm64 (lo que se mete en el APK).
REM Resultado: godot\bin\libbreach_voxel.android.template_release.arm64.so
REM
REM OJO: tools\build_extension.bat SOLO compila la de Windows. Si se toca C++ y se exporta el APK sin
REM pasar por aqui, el movil sigue con la extension vieja y no se entera de los cambios.
setlocal
set CMAKE="C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
set NINJA="C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe"
set NDK=%LOCALAPPDATA%\Android\Sdk\ndk\27.2.12479018
cd /d "%~dp0\..\godot\extension"
if not exist "%NDK%\build\cmake\android.toolchain.cmake" (
  echo Falta el NDK en %NDK%
  exit /b 1
)
%CMAKE% -S . -B build-android-arm64 -G Ninja -DCMAKE_BUILD_TYPE=Release -DGODOTCPP_TARGET=template_release ^
  -DCMAKE_TOOLCHAIN_FILE="%NDK%\build\cmake\android.toolchain.cmake" ^
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24 -DCMAKE_MAKE_PROGRAM=%NINJA% || exit /b 1
%CMAKE% --build build-android-arm64 --target breach_voxel || exit /b 1
echo.
echo OK: godot\bin\libbreach_voxel.android.template_release.arm64.so
