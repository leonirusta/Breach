#!/bin/bash
# BANCO DE SINCRONIA EN LAN: dos (o tres) instancias sin ventana jugando solas en un modo, y la comparacion de
# lo que ve cada una (tools/comparar_sync.py). Es lo que encontro los fallos de red de 2026-09-17: derrumbes
# que solo veia el anfitrion, marcador del duelo a muerte, vida de los bichos, el que entra tarde...
#
#   bash tools/sincro_lan.sh <mapa> <segundos> [flags]              anfitrion + invitado
#   TARDE=100 bash tools/sincro_lan.sh <mapa> <segundos> [flags]    y un segundo invitado que entra a los 100 s
#
# Mapas por modo: dust2 (bomba), hangar (duelo a muerte), city / monaco (atraco), pve_cuarentena (oleadas),
# pruebas (libre). Flags utiles: --sincromortal (se puede morir), --sincroplanta (el terrorista planta la C4),
# --censoprueba (el invitado estropea bloques a proposito para ver que se arreglan).
#
# Usa el puerto 27415 y la sala "prueba_sincro": con el puerto normal (27015) el banco se metia en la partida
# de quien estuviera jugando en la misma red.
MAPA=$1; SEG=$2; shift 2; EXTRA="$@"
cd "$(dirname "$0")/.."
G="${GODOT:-/c/Users/usuario 1/Desktop/GodotEngine/Godot_v4.7.2-stable_win64_console.exe}"
LOGS="${TEMP:-/tmp}/sincro_lan"
mkdir -p "$LOGS"
U="$APPDATA/Godot/app_userdata/Breach"
rm -f "$U/diag_sync_anfitrion.log" "$U/diag_sync_invitado.log" "$U/diag_sync_invitado2.log"
TARDE=${TARDE:-0}
timeout $((SEG + TARDE + 70)) "$G" --headless --path godot -- --lanhost=prueba_sincro --lanmap=$MAPA --puerto=27415 --sincrojuego --diagsync $EXTRA > "$LOGS/anfitrion.log" 2>&1 &
sleep 12
timeout $((SEG + TARDE + 45)) "$G" --headless --path godot -- --lanjoin=127.0.0.1 --puerto=27415 --sincrojuego --diagsync $EXTRA > "$LOGS/invitado.log" 2>&1 &
if [ "$TARDE" -gt 0 ]; then
  sleep $TARDE
  timeout $((SEG + 30)) "$G" --headless --path godot -- --lanjoin=127.0.0.1 --puerto=27415 --sincrojuego --diagsync --diagsufijo=2 $EXTRA > "$LOGS/invitado2.log" 2>&1 &
fi
wait
echo "== errores (logs en $LOGS)"
grep -h "SCRIPT ERROR\|ERROR:" "$LOGS"/*.log | grep -v "Unreferenced static\|PagedAllocator\|leaked at exit\|UPNPDevices" | sort | uniq -c | sort -rn | head -8
grep -h "\[sincrojuego\]\|pide el daño\|\[net\] bloques\|\[net\] mapa\|relevo" "$LOGS"/*.log | head -12
echo "== invitado"; python tools/comparar_sync.py
if [ "$TARDE" -gt 0 ]; then echo "== invitado que entra tarde"; python tools/comparar_sync.py --b=diag_sync_invitado2.log; fi
