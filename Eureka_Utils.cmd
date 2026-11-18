@echo off
rem ============================================================
rem  Eureka_Utils - lanzador portable
rem  Doble clic: interfaz grafica.
rem  Con parametros: se pasan a Eureka_Utils.ps1, por ejemplo
rem     Eureka_Utils.cmd -Perfil Profesional -Desatendido
rem ============================================================
setlocal
cd /d "%~dp0"

net session >nul 2>&1
if errorlevel 1 (
    echo Solicitando permisos de administrador...
    if "%~1"=="" (
        powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    ) else (
        powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    )
    exit /b
)

if "%~1"=="" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Eureka_Utils.ps1" -OcultarConsola
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Eureka_Utils.ps1" %*
)
exit /b %errorlevel%
