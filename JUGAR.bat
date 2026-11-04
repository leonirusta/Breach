@echo off
REM ============================================================
REM  BREACH - jugar en PC (Windows 10/11, 64 bits)
REM  Doble clic y listo. La primera vez descarga Godot 4.7.2
REM  (~60 MB) e importa los recursos (tarda unos minutos).
REM ============================================================
cd /d "%~dp0"
set "GODOT=%~dp0motor\Godot_v4.7.2-stable_win64.exe"
set "VOIP=godot\addons\twovoip\twovoip.gdextension"

if exist "%GODOT%" goto motor_ok
echo Descargando el motor Godot 4.7.2...
if not exist motor mkdir motor
curl -L -o motor\godot.zip "https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip" || goto error
tar -xf motor\godot.zip -C motor || goto error
del motor\godot.zip
:motor_ok

if exist "godot\bin\libbreach_voxel.windows.template_release.x86_64.dll" goto dll_ok
echo Falta el motor de voxels compilado. Compilando con tools\build_extension.bat...
call tools\build_extension.bat || goto error
:dll_ok

if exist "godot\.godot\importado.ok" goto jugar
echo Primera vez: importando texturas, sonidos y modelos. Puede tardar varios minutos...
REM la libreria del chat de voz cuelga la importacion: se apaga solo durante este paso
copy /y "%VOIP%" "%VOIP%.bak" >nul
findstr /v /b "windows" "%VOIP%.bak" > "%VOIP%"
"%GODOT%" --headless --path godot --import
copy /y "%VOIP%.bak" "%VOIP%" >nul
del "%VOIP%.bak"
if exist "godot\.godot\imported" echo ok> "godot\.godot\importado.ok"

:jugar
start "" "%GODOT%" --path godot
exit /b 0

:error
echo.
echo Algo fallo. Revisa tu conexion a internet o lee el README.md.
pause
exit /b 1
