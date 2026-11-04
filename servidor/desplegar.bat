@echo off
setlocal enabledelayedexpansion
REM ===========================================================================
REM  Despliegue del servidor de cuentas de Breach en Cloud Run.
REM
REM  Se puede ejecutar VARIAS VECES sin romper nada: si el bucket ya existe no
REM  lo vuelve a crear, y si el secreto ya esta puesto no lo cambia (cambiarlo
REM  echaria a todos los jugadores, porque sus tokens dejarian de valer).
REM
REM  Requiere el SDK de Google Cloud:
REM    https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe
REM ===========================================================================

set PROYECTO=gen-lang-client-0444936010
set REGION=us-central1
set SERVICIO=breach-cuentas
set BUCKET=%PROYECTO%-breach-cuentas

where gcloud >nul 2>&1
if errorlevel 1 (
  echo.
  echo   No encuentro "gcloud". Instala el SDK de Google Cloud y vuelve a ejecutar esto:
  echo   https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe
  echo.
  exit /b 1
)

echo.
echo === proyecto %PROYECTO% · region %REGION% ===
call gcloud config set project %PROYECTO% || exit /b 1

echo.
echo === 1/5 · APIs necesarias (no hace nada si ya estan) ===
call gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com storage.googleapis.com || exit /b 1

echo.
echo === 2/5 · bucket de datos ===
REM us-central1 entra en la capa gratis de Cloud Storage (5 GB).
call gcloud storage buckets describe gs://%BUCKET% >nul 2>&1
if errorlevel 1 (
  call gcloud storage buckets create gs://%BUCKET% --location=%REGION% --uniform-bucket-level-access || exit /b 1
  echo     bucket creado.
) else (
  echo     el bucket ya existe, se deja como esta.
)

echo.
echo === 3/5 · permiso de la cuenta de servicio sobre el bucket ===
for /f "tokens=*" %%i in ('gcloud projects describe %PROYECTO% --format^=value^(projectNumber^)') do set NUMERO=%%i
call gcloud storage buckets add-iam-policy-binding gs://%BUCKET% ^
  --member=serviceAccount:!NUMERO!-compute@developer.gserviceaccount.com ^
  --role=roles/storage.objectAdmin >nul || exit /b 1
echo     concedido a !NUMERO!-compute@developer.gserviceaccount.com

echo.
echo === 4/5 · secreto de firma de los tokens ===
REM SOLO SE GENERA LA PRIMERA VEZ. Si cambia, TODOS los jugadores tienen que
REM volver a iniciar sesion, porque sus tokens dejan de validar.
set SECRETO=
for /f "tokens=*" %%s in ('gcloud run services describe %SERVICIO% --region^=%REGION% --format^="value(spec.template.spec.containers[0].env.filter(\"name:BREACH_SECRET\").extract(\"value\").flatten())" 2^>nul') do set SECRETO=%%s
if "!SECRETO!"=="" (
  for /f "tokens=*" %%s in ('powershell -NoProfile -Command "[Convert]::ToHexString((1..32 ^| ForEach-Object {Get-Random -Max 256})).ToLower()"') do set SECRETO=%%s
  echo     secreto NUEVO generado. Guardalo en un sitio seguro:
  echo     !SECRETO!
) else (
  echo     el servicio ya tiene secreto, se reutiliza ^(no se echa a nadie^).
)

echo.
echo === 5/5 · desplegar ===
REM  --min-instances=0   sin trafico no se paga nada
REM  --max-instances=1   UNA SOLA INSTANCIA, Y NO ES SOLO POR GASTO.
REM                      La LISTA DE SALAS vive en memoria (una sala cambia cada
REM                      pocos segundos: guardarla en el bucket se comeria la
REM                      cuota de escrituras). Con dos instancias, el anfitrion
REM                      anuncia en una y el que busca pregunta a la otra: no la
REM                      ve, y la partida entre casas no se encuentra JAMAS.
REM                      Una instancia con concurrency 80 sobra para esto, que es
REM                      E/S casi pura.
REM  --concurrency=80    una instancia atiende 80 peticiones a la vez
REM  --timeout=3600s     EL PUENTE (puente.js): una partida por WebSocket es UNA peticion que dura toda la
REM                      partida, y Cloud Run la corta al llegar al tiempo maximo (60 min es el tope).
call gcloud run deploy %SERVICIO% ^
  --source . ^
  --region %REGION% ^
  --allow-unauthenticated ^
  --min-instances=0 ^
  --max-instances=1 ^
  --concurrency=80 ^
  --memory=512Mi ^
  --cpu=1 ^
  --timeout=3600s ^
  --update-env-vars=BREACH_BUCKET=%BUCKET%,BREACH_SECRET=!SECRETO! || exit /b 1
REM  OJO: --update-env-vars, NO --set-env-vars.
REM  "set" REEMPLAZA todas las variables del servicio, asi que se llevaria por
REM  delante GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET y BREACH_URL, y el boton de
REM  Google dejaria de funcionar sin que nada lo dijera. "update" solo toca las
REM  que se nombran.

echo.
for /f "tokens=*" %%u in ('gcloud run services describe %SERVICIO% --region^=%REGION% --format^=value^(status.url^)') do set URL=%%u
echo ===========================================================================
echo   LISTO.  %URL%
echo.
echo   Compruebalo:      curl %URL%/salud
echo   En el juego:      lobby -^> boton de cuenta -^> pega esa URL en "servidor"
echo ===========================================================================
