// vxcore - Generador procedural de ciudad (determinista por semilla)
// Calles, manzanas con edificios de varios pisos (paredes, losas, ventanas,
// puertas, tabiques interiores, mobiliario), tiendas con escaparate, casas,
// parques, coches, farolas y un paso elevado sobre pilares.
#pragma once
#include <cstdint>
#include <vector>
#include "vx_math.h"

namespace vx {

class World;

struct CityParams {
    int blockPitchM = 32;     // periodo calle+manzana (m)
    int streetWidthM = 8;
    int maxFloors = 9;        // plantas de un edificio corriente (3 m cada una)
    // TORRES. Una parte de las manzanas levanta un bloque alto, al estilo de los mapas urbanos
    // verticales: se sube por dentro y se pelea por las azoteas.
    int maxFloorsTower = 26;  // ~78 m
    int minFloorsTower = 12;
    float towerChance = 0.38f;
    bool overpass = true;
    bool vehicles = true;
    bool interiors = true;
    bool stairs = true;       // escaleras de verdad (peldaños), no un agujero en la losa
};

struct BuildingInfo { Vec3 center; Vec3 half; };   // centro y semi-tamaño (m)

struct CityInfo {
    std::vector<Vec3> buildingCenters;     // para el benchmark / IA (objetivos)
    std::vector<BuildingInfo> buildingBoxes;
    std::vector<Vec3> pillarPositions;     // pilares del paso elevado
    std::vector<Vec3> streetPoints;        // puntos transitables en cruces (para rutas de IA)
    Vec3 playerSpawn;
    int buildings = 0;
};

void generateCity(World& world, uint64_t seed, const CityParams& params, CityInfo& info);

} // namespace vx
