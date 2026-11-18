<#
.SYNOPSIS
    Eureka_Utils portable: hardware, bloatware, software con dependencias e impacto,
    actualizaciones winget, ajustes, cuentas con MFA, dominio/Entra/Intune, Autopilot y
    creación de USB de instalación de Windows 11+ con configuración automática.

.EXAMPLE
    .\Eureka_Utils.ps1                                         # interfaz gráfica
.EXAMPLE
    .\Eureka_Utils.ps1 -Perfil "Gaming" -Desatendido           # perfil sin interfaz
.EXAMPLE
    .\Eureka_Utils.ps1 -Instalar 7zip,vlc -QuitarBloatware @recommended -Desatendido
.EXAMPLE
    .\Eureka_Utils.ps1 -ActualizarTodo                         # winget upgrade --all
.EXAMPLE
    .\Eureka_Utils.ps1 -Pestana Bloatware                      # abre la interfaz en una pestaña
#>
[CmdletBinding()]
param(
    [string]$Perfil,
    [switch]$Desatendido,
    [string[]]$Instalar,
    [string[]]$QuitarBloatware,
    [string[]]$Ajustes,
    [switch]$ActualizarTodo,
    [switch]$SincronizarIntune,
    [switch]$SinPuntoRestauracion,
    [switch]$ListarCatalogo,
    [switch]$PostInstalacion,
    [ValidateSet('', 'Equipo', 'Hardware', 'Software', 'Actualizaciones', 'Bloatware', 'Ajustes', 'Cuentas', 'USB', 'Drivers', 'Diagnostico', 'Registro')][string]$Pestana = '',
    [switch]$OcultarConsola,
    [string]$Captura
)

$ErrorActionPreference = 'Continue'
$Root = $PSScriptRoot

# Con -File los arrays llegan como "a,b": se normalizan
foreach ($n in 'Instalar', 'QuitarBloatware', 'Ajustes') {
    $v = Get-Variable -Name $n -ValueOnly
    if ($v) { Set-Variable -Name $n -Value @($v -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
}

# Archivos copiados de Internet/USB pueden estar marcados como bloqueados
try { Get-ChildItem -Path $Root -Recurse -File -Include *.ps1, *.psm1, *.xaml, *.json -ErrorAction Stop | Unblock-File -ErrorAction SilentlyContinue } catch { }

# Seguridad: la carpeta de trabajo pasa a System32 (solo escribible por administradores) para que
# ningún ejecutable con nombre de sistema colocado junto a Eureka_Utils se ejecute en su lugar.
$sys32 = Join-Path $env:SystemRoot 'System32'
Set-Location $sys32
[Environment]::CurrentDirectory = $sys32

# Seguridad: solo se cargan los módulos conocidos (un .psm1 añadido a la carpeta no se ejecuta)
$CfgModuleNames = @('Core', 'Hardware', 'Software', 'Updates', 'Bloatware', 'Tweaks', 'Accounts', 'Domain', 'Diagnostics', 'Security', 'Drivers', 'Media', 'Profiles', 'Report')
$unknown = @(Get-ChildItem (Join-Path $Root 'Modules') -Filter '*.psm1' | Where-Object { $CfgModuleNames -notcontains $_.BaseName })
foreach ($m in $CfgModuleNames) {
    $p = Join-Path $Root "Modules\$m.psm1"
    if (Test-Path $p) { Import-Module $p -Force -DisableNameChecking -Global }
}
$logFile = Set-CfgEnvironment -Root $Root
foreach ($u in $unknown) { Write-CfgLog "Módulo desconocido ignorado por seguridad: $($u.Name). Si no lo has añadido tú, elimínalo." WARN }

# ------------------------------------------------------------------ listar catálogo
if ($ListarCatalogo) {
    $sw = Get-CfgSoftwareCatalog
    Write-Host "`nSOFTWARE ($($sw.Count))" -ForegroundColor Cyan
    $sw | Select-Object id, name, category, source,
        @{ n = 'Dependencias'; e = { @($_.dependencies) -join ',' } },
        @{ n = 'Disco'; e = { Format-CfgSize $_.impact.diskMB } },
        @{ n = 'RAM'; e = { Format-CfgSize $_.impact.ramMB } },
        @{ n = 'Arranque'; e = { if ($_.impact.startup) { 'Sí' } else { '' } } } | Format-Table -AutoSize | Out-String -Width 240 | Write-Host
    Write-Host 'BLOATWARE' -ForegroundColor Cyan
    Get-CfgBloatwareCatalog | Select-Object id, name, type, risk, recommended | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
    Write-Host 'AJUSTES' -ForegroundColor Cyan
    Get-CfgTweaks | Select-Object Id, Name, Category, Scope, Applied | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
    Write-Host 'PERFILES' -ForegroundColor Cyan
    Get-CfgProfiles | Select-Object name, description | Format-Table -AutoSize -Wrap | Out-String -Width 200 | Write-Host
    return
}

# ------------------------------------------------------------------ elevación
if (-not (Test-CfgAdmin) -and -not $Captura) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$PSCommandPath`"")
    foreach ($k in $PSBoundParameters.Keys) {
        $v = $PSBoundParameters[$k]
        if ($v -is [System.Management.Automation.SwitchParameter]) { if ($v.IsPresent) { $argList += "-$k" } }
        elseif ($v -is [array]) { $argList += "-$k"; $argList += ($v -join ',') }
        else { $argList += "-$k"; $argList += "`"$v`"" }
    }
    try {
        Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $argList -Verb RunAs -ErrorAction Stop
        return
    }
    catch {
        Write-CfgLog 'No se concedió la elevación: se continúa sin privilegios de administrador (la mayoría de acciones fallarán).' WARN
    }
}

# ------------------------------------------------------------------ seguridad de la carpeta
# Si un usuario sin privilegios puede modificar estos scripts, podría lograr que se ejecute su
# código como administrador la próxima vez que alguien abra Eureka_Utils.
$folderRisk = @()
if (Test-CfgAdmin) {
    $folderRisk = @(Test-CfgFolderSecurity -Path $Root)
    if ($folderRisk -contains 'SIN-PERMISOS') {
        Write-CfgLog 'Eureka_Utils se ejecuta desde una unidad sin permisos (FAT32/exFAT, normalmente un USB): guarda el USB en un lugar seguro y no lo dejes en equipos de terceros.' INFO
        $folderRisk = @()
    }
    elseif ($folderRisk.Count) {
        if ($PostInstalacion) { Protect-CfgFolder -Path $Root | Out-Null; $folderRisk = @() }
        else { Write-CfgLog ("La carpeta {0} la pueden modificar usuarios sin privilegios ({1}). Protégela o muévela a C:\Program Files." -f $Root, ($folderRisk -join ', ')) WARN }
    }
}

# ------------------------------------------------------------------ modo desatendido
$cli = $Desatendido -or $Instalar -or $QuitarBloatware -or $Ajustes -or $SincronizarIntune -or $ActualizarTodo
if ($cli) {
    Write-CfgLog "Eureka_Utils (desatendido) en $env:COMPUTERNAME. Registro: $logFile" STEP
    if (-not ($Perfil -or $Instalar -or $QuitarBloatware -or $Ajustes -or $SincronizarIntune -or $ActualizarTodo)) {
        Write-CfgLog 'Indica -Perfil, -Instalar, -QuitarBloatware, -Ajustes, -ActualizarTodo o -SincronizarIntune. Usa -ListarCatalogo para ver los ids.' ERROR
        exit 2
    }
    $results = @()
    $changes = $Perfil -or $Instalar -or $QuitarBloatware -or $Ajustes
    if ($changes -and -not $SinPuntoRestauracion) { New-CfgRestorePoint -Description 'Eureka_Utils (desatendido)' | Out-Null }
    if ($Perfil)            { $results += @(Invoke-CfgProfile -Name $Perfil -NoRestorePoint) }
    if ($QuitarBloatware)   { $results += @(Remove-CfgBloatware -Ids $QuitarBloatware -IncludeProvisioned) }
    if ($Ajustes)           { $results += @(Invoke-CfgTweaks -Ids $Ajustes) }
    if ($Instalar)          { $results += @(Install-CfgSoftwareSet -Ids $Instalar) }
    if ($ActualizarTodo) {
        $updFails = @(Invoke-CfgVerifiedUpdate -All)
        foreach ($uf in $updFails) {
            $results += New-CfgResult -Id $uf.Id -Name $uf.Name -Action 'Actualizar' -Success $false -Message "Sin actualizar ($($uf.Version) -> $($uf.Available)). Descarga manual: $($uf.Link)"
        }
        if (-not $updFails.Count) { $results += New-CfgResult -Id 'upgrade-all' -Name 'Actualizar todo' -Action 'Actualizar' -Success $true -Message 'Todas las actualizaciones verificadas' }
    }
    if ($SincronizarIntune) { $results += @(Invoke-CfgIntuneSync) }

    $results = @($results | Where-Object { $_ -and $_.PSObject.Properties['Success'] })
    $results | Select-Object Action, Name, @{ n = 'Resultado'; e = { if ($_.Success) { 'OK' } else { 'ERROR' } } }, Message |
        Format-Table -AutoSize | Out-String -Width 200 | Write-Host
    $failed = @($results | Where-Object { -not $_.Success }).Count
    Write-CfgLog ("Finalizado: {0} acciones, {1} con error. Registro: {2}" -f $results.Count, $failed, $logFile) $(if ($failed) { 'WARN' } else { 'OK' })
    exit $(if ($failed) { 1 } else { 0 })
}

# ------------------------------------------------------------------ interfaz gráfica
if ($OcultarConsola -or $PostInstalacion) {
    try {
        Add-Type -Name ConsoleWindow -Namespace CfgNative -ErrorAction Stop -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@
        [void][CfgNative.ConsoleWindow]::ShowWindow([CfgNative.ConsoleWindow]::GetConsoleWindow(), 0)
    }
    catch { }
}

. (Join-Path $Root 'UI\I18n.ps1')
. (Join-Path $Root 'UI\Gui.ps1')
Show-CfgGui -Root $Root -LogFile $logFile -InitialProfile $Perfil -CapturePath $Captura -PostInstall:$PostInstalacion -Tab $Pestana -FolderRisk $folderRisk
