cmake_minimum_required(VERSION 3.16)
project(vxcore CXX)

# vxcore: núcleo de destrucción por voxels. C++17, cero dependencias.
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

add_library(vxcore STATIC
  src/vx_world.cpp
  src/vx_mesher.cpp
  src/vx_connectivity.cpp
  src/vx_structure.cpp
  src/vx_body.cpp
  src/vx_debris.cpp
  src/vx_smoke.cpp
  src/vx_nav.cpp
  src/vx_jobs.cpp
  src/vx_engine.cpp
  src/vx_citygen.cpp
  src/vx_material.cpp
  src/vx_mapfile.cpp
)
target_include_directories(vxcore PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)

if(MSVC)
  # /fp:precise (no fast): la destrucción debe ser determinista.
  target_compile_options(vxcore PRIVATE /W3 /permissive- /EHsc /O2 /Oi /GS- /fp:precise)
  target_compile_definitions(vxcore PRIVATE _CRT_SECURE_NO_WARNINGS NOMINMAX)
else()
  # -ffp-contract=off (auditoria 2026-10-05): clang en ARM funde a*b+c en una sola instruccion (FMA) y MSVC en el PC no;
  # el resultado de las cuentas en coma flotante cambiaba en el ultimo bit entre un PC y un movil de la misma partida.
  target_compile_options(vxcore PRIVATE -Wall -Wextra -O2 -fno-fast-math -ffp-contract=off)
endif()

find_package(Threads REQUIRED)
target_link_libraries(vxcore PUBLIC Threads::Threads)

# Benchmark headless: mide cada sistema sin motor gráfico.
add_executable(vxbench bench/bench_main.cpp)
target_link_libraries(vxbench PRIVATE vxcore)

# Benchmark estructural + rayos por tamaño de mundo (10k..4M voxels).
add_executable(vxbenchstruct bench/bench_struct.cpp)
target_link_libraries(vxbenchstruct PRIVATE vxcore)

# Tests de corrección.
add_executable(vxtest tests/test_main.cpp)
target_link_libraries(vxtest PRIVATE vxcore)
# Tests estructurales (Fase 34): falsos derrumbes globales, redundancia, edificios independientes...
add_executable(vxstructtest tests/test_structure.cpp)
target_link_libraries(vxstructtest PRIVATE vxcore)
enable_testing()
add_test(NAME vxtest COMMAND vxtest)
add_test(NAME vxstructtest COMMAND vxstructtest)
