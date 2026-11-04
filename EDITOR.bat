@echo off
REM Abre el proyecto en el editor de Godot (primero hay que haber corrido JUGAR.bat una vez).
cd /d "%~dp0"
start "" "%~dp0motor\Godot_v4.7.2-stable_win64.exe" --editor --path godot
