@echo off
REM La clave del panel de administracion (app Breach Admin). La pide por teclado: no se ve ni se guarda.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0configurar_admin.ps1"
pause
