@echo off
REM Compila vxcore + benchmark + tests con MSVC (Build Tools 2022) y Ninja.
setlocal
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
set CMAKE="C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
set NINJA="C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe"
cd /d "%~dp0\..\core"
if not exist build mkdir build
%CMAKE% -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_MAKE_PROGRAM=%NINJA% || exit /b 1
%CMAKE% --build build --config Release || exit /b 1
echo.
echo OK: core\build\vxbench.exe  core\build\vxtest.exe
