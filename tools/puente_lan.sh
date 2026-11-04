#!/bin/bash
# BANCO DEL PUENTE (puente_peer.gd + servidor/puente.js): el mismo banco de sincronia que tools/sincro_lan.sh, pero el
# invitado entra POR EL PUENTE del servidor (WebSocket) en vez de directo por UDP. Levanta el servidor en local
# (BREACH_LOCAL, sin nube), crea una cuenta de prueba para el invitado, juega <segundos> y compara lo que ve cada copia.
# Al final dice cuanto ha pasado por el puente (lo que costaria en la capa gratis).
#
#   bash tools/puente_lan.sh <mapa> <segundos> [flags para las dos copias]
MAPA=$1; SEG=$2; shift 2; EXTRA="$@"
cd "$(dirname "$0")/.."
G="${GODOT:-/c/Users/usuario 1/Desktop/GodotEngine/Godot_v4.7.2-stable_win64_console.exe}"
LOGS="${TEMP:-/tmp}/puente_lan"
mkdir -p "$LOGS"
SRV_DIR="$LOGS/datos"
rm -rf "$SRV_DIR"; mkdir -p "$SRV_DIR"
PUERTO_SRV=8095
URL="http://127.0.0.1:$PUERTO_SRV"
U="$APPDATA/Godot/app_userdata/Breach"
rm -f "$U/diag_sync_anfitrion.log" "$U/diag_sync_invitado.log"

# el node SIN subshell: con "( cd ... && node ) &" el PID era el del subshell y el servidor se quedaba vivo al acabar
pushd servidor > /dev/null
BREACH_LOCAL="$SRV_DIR" BREACH_SECRET=banco-del-puente PORT=$PUERTO_SRV node index.js > "$LOGS/servidor.log" 2>&1 &
SRV=$!
popd > /dev/null
sleep 2
TOKEN=$(curl -s -X POST "$URL/registro" -H "Content-Type: application/json" \
  -d '{"usuario":"bancopuente","clave":"bancopuente1","nombre":"bancopuente"}' | python -c "import sys,json; print(json.load(sys.stdin).get('token',''))")
if [ -z "$TOKEN" ]; then echo "no pude crear la cuenta de prueba"; kill $SRV; exit 1; fi

timeout $((SEG + 90)) "$G" --headless --path godot -- --lanhost=prueba_puente --lanmap=$MAPA --puerto=27415 --sincrojuego \
  --diagsync --servidor=$URL --medirtrafico $EXTRA > "$LOGS/anfitrion.log" 2>&1 &
A=$!
sleep 12
timeout $((SEG + 60)) "$G" --headless --path godot -- --lanjoin --lanpuente --servidor=$URL --tokenprueba=$TOKEN \
  --sincrojuego --diagsync --medirtrafico $EXTRA > "$LOGS/invitado.log" 2>&1 &
B=$!
wait $A $B
sleep 1
echo "== el puente segun el servidor"; curl -s "$URL/salud"; echo
kill $SRV 2>/dev/null
echo "== errores (logs en $LOGS)"
grep -h "SCRIPT ERROR\|ERROR:" "$LOGS"/anfitrion.log "$LOGS"/invitado.log | grep -v "Unreferenced static\|PagedAllocator\|leaked at exit\|UPNPDevices" | sort | uniq -c | sort -rn | head -8
grep -h "\[puente\]\|PUENTE\|\[lantest\]" "$LOGS"/anfitrion.log "$LOGS"/invitado.log | head -14
grep -h "\[trafico\]" "$LOGS"/anfitrion.log "$LOGS"/invitado.log | tail -6
grep -h "\[puente\]" "$LOGS"/servidor.log | head -6
echo "== invitado"; python tools/comparar_sync.py
