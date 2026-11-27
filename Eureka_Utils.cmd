@echo off
rem ============================================================
rem  Eureka_Utils - lanzador portable
rem  Doble clic: interfaz grafica.
rem  Con parametros: se pasan a Eureka_Utils.ps1, por ejemplo
rem     Eureka_Utils.cmd -Perfil Profesional -Desatendido
rem  Seguridad: los programas del sistema se llaman con su ruta
rem  completa para que un archivo con el mismo nombre en esta
rem  carpeta (por ejemplo en un USB) nunca se ejecute en su lugar.
rem ============================================================
setlocal
set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
cd /d "%SystemRoot%\System32"

"%SystemRoot%\System32\net.exe" session >nul 2>&1
if errorlevel 1 (
    echo Solicitando permisos de administrador...
    if "%~1"=="" (
        "%PSEXE%" -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    ) else (
        "%PSEXE%" -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    )
    exit /b
)

rem Autorreparacion: si el script no se puede leer (permisos danados), todo lo de
rem esta carpeta vuelve a heredar los permisos de la carpeta de Eureka_Utils.
type "%~dp0Eureka_Utils.ps1" >nul 2>&1
if errorlevel 1 "%SystemRoot%\System32\icacls.exe" "%~dp0*" /reset /T /C /Q >nul 2>&1

if "%~1"=="" (
    "%PSEXE%" -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Eureka_Utils.ps1" -OcultarConsola
) else (
    "%PSEXE%" -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Eureka_Utils.ps1" %*
)
exit /b %errorlevel%
