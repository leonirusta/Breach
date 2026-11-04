@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
cd /d "%~dp0"
cl /nologo /O1 /EHsc /DUNICODE /D_UNICODE depura.cpp /link psapi.lib /out:depura.exe
