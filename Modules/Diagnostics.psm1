# Diagnostics.psm1 - Pruebas del sistema operativo y consolas de administración (MMC)

function New-CfgCheck { param($c, $r, $d) [pscustomobject]@{ Comprobacion = $c; Resultado = $r; Detalle = $d } }

function Get-CfgSystemHealth {
    <# Comprobaciones de solo lectura del sistema operativo. #>
    Write-CfgLog 'Analizando el estado del sistema operativo...' STEP
    $out = New-Object System.Collections.Generic.List[object]
    $os = Get-CimInstance Win32_OperatingSystem

    # Arranque
    $up = (Get-Date) - $os.LastBootUpTime
    $out.Add((New-CfgCheck 'Último reinicio' $(if ($up.TotalDays -gt 14) { 'AVISO' } else { 'OK' }) ('{0:dd/MM/yyyy HH:mm} (hace {1} días y {2} h){3}' -f $os.LastBootUpTime, [int][math]::Floor($up.TotalDays), $up.Hours, $(if ($up.TotalDays -gt 14) { '. Reinicia para completar actualizaciones.' } else { '' }))))
    try {
        $boot = Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100 } -MaxEvents 1 -ErrorAction Stop
        $ms = [int]([xml]$boot.ToXml()).Event.EventData.Data.Where({ $_.Name -eq 'BootTime' })[0].'#text'
        $out.Add((New-CfgCheck 'Tiempo de arranque' $(if ($ms -gt 60000) { 'AVISO' } else { 'OK' }) ('{0:N1} s en el último arranque medido' -f ($ms / 1000))))
    }
    catch { }

    # Disco del sistema
    $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
    $pct = [math]::Round(100 * $d.FreeSpace / $d.Size)
    $out.Add((New-CfgCheck "Espacio libre en $($env:SystemDrive)" $(if ($pct -lt 10) { 'FALLO' } elseif ($pct -lt 20) { 'AVISO' } else { 'OK' }) ('{0} % libre ({1})' -f $pct, (Format-CfgSize ($d.FreeSpace / 1MB)))))
    if (Test-CfgAdmin) {
        $dirty = (& fsutil.exe dirty query $env:SystemDrive 2>$null) -join ' '
        if ($dirty) { $out.Add((New-CfgCheck 'Volumen marcado para revisión' $(if ($dirty -match 'NOT Dirty|no est') { 'OK' } else { 'AVISO' }) $dirty.Trim())) }
    }

    # Dispositivos con problemas
    $bad = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -and $_.ConfigManagerErrorCode -ne 0 })
    $out.Add((New-CfgCheck 'Dispositivos con problemas' $(if ($bad.Count) { 'AVISO' } else { 'OK' }) $(if ($bad.Count) { ($bad | Select-Object -First 5 | ForEach-Object { "$($_.Name) (código $($_.ConfigManagerErrorCode))" }) -join '; ' } else { 'Ninguno' })))

    # Eventos
    $since = (Get-Date).AddDays(-7)
    $crit = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 1; StartTime = $since } -ErrorAction SilentlyContinue)
    $err = @(Get-WinEvent -FilterHashtable @{ LogName = 'System', 'Application'; Level = 2; StartTime = $since } -ErrorAction SilentlyContinue)
    $bsod = @($crit | Where-Object { $_.Id -eq 41 })
    $out.Add((New-CfgCheck 'Eventos críticos (7 días)' $(if ($crit.Count) { 'AVISO' } else { 'OK' }) $(if ($crit.Count) { "$($crit.Count) eventos; $($bsod.Count) apagados inesperados (Kernel-Power 41)" } else { 'Ninguno' })))
    $out.Add((New-CfgCheck 'Errores (7 días)' $(if ($err.Count -gt 50) { 'AVISO' } else { 'OK' }) "$($err.Count) errores en Sistema y Aplicación"))

    # Servicios críticos
    $svc = 'wuauserv', 'BITS', 'WinDefend', 'mpssvc', 'EventLog', 'Dnscache', 'LanmanWorkstation', 'CryptSvc', 'Winmgmt'
    $stopped = @(Get-Service -Name $svc -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Running' -and $_.StartType -ne 'Disabled' -and $_.Name -notin 'wuauserv', 'BITS' })
    $disabled = @(Get-Service -Name $svc -ErrorAction SilentlyContinue | Where-Object { $_.StartType -eq 'Disabled' })
    $out.Add((New-CfgCheck 'Servicios esenciales' $(if ($stopped.Count -or $disabled.Count) { 'AVISO' } else { 'OK' }) $(if ($stopped.Count -or $disabled.Count) { 'Detenidos: ' + (($stopped | ForEach-Object Name) -join ', ') + ' · Deshabilitados: ' + (($disabled | ForEach-Object Name) -join ', ') } else { 'Windows Update, BITS, Defender, Firewall, Registro de eventos, DNS, WMI: correctos' })))

    # Windows Update
    try {
        $lastHotfix = Get-HotFix -ErrorAction Stop | Where-Object InstalledOn | Sort-Object InstalledOn -Descending | Select-Object -First 1
        $days = [int]((Get-Date) - $lastHotfix.InstalledOn).TotalDays
        $out.Add((New-CfgCheck 'Última actualización de Windows' $(if ($days -gt 45) { 'AVISO' } else { 'OK' }) ('{0} el {1:dd/MM/yyyy} (hace {2} días)' -f $lastHotfix.HotFixID, $lastHotfix.InstalledOn, $days)))
    }
    catch { }
    $reboot = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
    $out.Add((New-CfgCheck 'Reinicio pendiente' $(if ($reboot) { 'AVISO' } else { 'OK' }) $(if ($reboot) { 'Hay actualizaciones esperando un reinicio' } else { 'No' })))

    # Red
    foreach ($x in (Get-CfgNetworkChecks)) { $out.Add($x) }

    foreach ($c in $out) { Write-CfgLog ('{0}: {1}' -f $c.Comprobacion, $c.Detalle) $(switch ($c.Resultado) { 'OK' { 'OK' } 'FALLO' { 'ERROR' } 'AVISO' { 'WARN' } default { 'INFO' } }) }
    return $out.ToArray()
}

function Get-CfgNetworkChecks {
    $r = @()
    $cfg = @(Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' })
    if (-not $cfg.Count) { return @(New-CfgCheck 'Red' 'FALLO' 'Sin adaptador conectado con puerta de enlace') }
    $gw = $cfg[0].IPv4DefaultGateway.NextHop
    $ping = Test-Connection -ComputerName $gw -Count 2 -Quiet -ErrorAction SilentlyContinue
    $r += New-CfgCheck 'Puerta de enlace' $(if ($ping) { 'OK' } else { 'AVISO' }) "$gw en $($cfg[0].InterfaceAlias)$(if (-not $ping) { ' (no responde a ping; algunos routers lo bloquean)' })"
    try { $null = Resolve-DnsName 'www.microsoft.com' -ErrorAction Stop; $r += New-CfgCheck 'Resolución DNS' 'OK' (($cfg[0].DNSServer | Where-Object { $_.AddressFamily -eq 2 } | ForEach-Object { $_.ServerAddresses }) -join ', ') }
    catch { $r += New-CfgCheck 'Resolución DNS' 'FALLO' 'No se resuelven nombres: revisa los servidores DNS' }
    $net = Test-CfgTcpPort -HostName 'www.microsoft.com' -Port 443 -TimeoutMs 3000
    $r += New-CfgCheck 'Acceso a Internet (HTTPS)' $(if ($net) { 'OK' } else { 'FALLO' }) $(if ($net) { 'Conexión a www.microsoft.com:443 correcta' } else { 'Sin conexión HTTPS: proxy, cortafuegos o sin Internet' })
    return $r
}

function Get-CfgRecentErrors {
    <# Últimos errores y eventos críticos para mostrarlos en una tabla. #>
    param([int]$Days = 7, [int]$Max = 60)
    $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System', 'Application'; Level = 1, 2; StartTime = (Get-Date).AddDays(-$Days) } -MaxEvents $Max -ErrorAction SilentlyContinue)
    $ev | ForEach-Object {
        $msg = ("$($_.Message)" -split "`r?`n")[0]
        [pscustomobject]@{ Fecha = $_.TimeCreated.ToString('dd/MM HH:mm'); Nivel = $(if ($_.Level -eq 1) { 'Crítico' } else { 'Error' }); Origen = $_.ProviderName; Id = $_.Id; Mensaje = $(if ($msg.Length -gt 160) { $msg.Substring(0, 160) + '…' } else { $msg }) }
    }
}

function Invoke-CfgRepairTool {
    <# Herramientas de reparación / comprobación que pueden tardar o requerir reinicio. #>
    param([Parameter(Mandatory)][ValidateSet('sfc', 'dism-scan', 'dism-restore', 'chkdsk', 'energy')][string]$Tool)
    switch ($Tool) {
        'sfc'          { $exe = 'sfc.exe'; $a = @('/scannow'); $title = 'Comprobador de archivos del sistema (SFC)' }
        'dism-scan'    { $exe = 'dism.exe'; $a = @('/Online', '/Cleanup-Image', '/ScanHealth'); $title = 'DISM: comprobar la imagen de Windows' }
        'dism-restore' { $exe = 'dism.exe'; $a = @('/Online', '/Cleanup-Image', '/RestoreHealth'); $title = 'DISM: reparar la imagen de Windows' }
        'chkdsk'       { $exe = 'chkdsk.exe'; $a = @($env:SystemDrive, '/scan'); $title = "CHKDSK en línea de $($env:SystemDrive)" }
        'energy'       { $exe = 'powercfg.exe'; $file = Join-Path (Get-CfgExportFolder) ('Energia_{0}_{1}.html' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmmss')); $a = @('/energy', '/output', $file, '/duration', '30'); $title = 'Informe de eficiencia energética (30 s)' }
    }
    Write-CfgLog "$title..." STEP
    $prev = $null
    try { $prev = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::Unicode } catch { }
    & $exe @a 2>&1 | ForEach-Object {
        $l = (("$_" -replace "`0", '') -split "`r")[-1].Trim()
        if ($l -and $l -notmatch '^\[?=*\s*\d+(\.\d+)?%') { Write-CfgLog "   $l" }
    }
    $code = $LASTEXITCODE
    if ($prev) { try { [Console]::OutputEncoding = $prev } catch { } }
    $ok = ($code -eq 0) -or ($Tool -eq 'energy' -and (Test-Path $file))
    Write-CfgLog "$title terminado (código $code)." $(if ($ok) { 'OK' } else { 'WARN' })
    $msg = if ($Tool -eq 'energy') { $file } else { "Código $code" }
    return (New-CfgResult -Id $Tool -Name $title -Action 'Diagnóstico' -Success $ok -Message $msg)
}

# ---------------------------------------------------------------- consolas MMC y herramientas de Windows

$script:Consoles = @(
    @{ Id = 'mmc.exe';              Name = 'Consola MMC vacía';              Pro = $false }
    @{ Id = 'compmgmt.msc';         Name = 'Administración de equipos';      Pro = $false }
    @{ Id = 'devmgmt.msc';          Name = 'Administrador de dispositivos';  Pro = $false }
    @{ Id = 'diskmgmt.msc';         Name = 'Administración de discos';       Pro = $false }
    @{ Id = 'services.msc';         Name = 'Servicios';                      Pro = $false }
    @{ Id = 'eventvwr.msc';         Name = 'Visor de eventos';               Pro = $false }
    @{ Id = 'taskschd.msc';         Name = 'Programador de tareas';          Pro = $false }
    @{ Id = 'perfmon.msc';          Name = 'Monitor de rendimiento';         Pro = $false }
    @{ Id = 'certmgr.msc';          Name = 'Certificados (usuario)';         Pro = $false }
    @{ Id = 'certlm.msc';           Name = 'Certificados (equipo)';          Pro = $false }
    @{ Id = 'wf.msc';               Name = 'Firewall avanzado';              Pro = $false }
    @{ Id = 'fsmgmt.msc';           Name = 'Carpetas compartidas';           Pro = $false }
    @{ Id = 'printmanagement.msc';  Name = 'Administración de impresión';    Pro = $true }
    @{ Id = 'gpedit.msc';           Name = 'Directiva de grupo local';       Pro = $true }
    @{ Id = 'secpol.msc';           Name = 'Directiva de seguridad local';   Pro = $true }
    @{ Id = 'lusrmgr.msc';          Name = 'Usuarios y grupos locales';      Pro = $true }
    @{ Id = 'dsa.msc';              Name = 'Usuarios y equipos de AD (RSAT)'; Pro = $true }
    @{ Id = 'gpmc.msc';             Name = 'Administración de directivas (RSAT)'; Pro = $true }
    @{ Id = 'dnsmgmt.msc';          Name = 'DNS (RSAT)';                     Pro = $true }
    @{ Id = 'dhcpmgmt.msc';         Name = 'DHCP (RSAT)';                    Pro = $true }
)

function Get-CfgConsoles {
    $isHome = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID -match '^Core'
    foreach ($c in $script:Consoles) {
        $exists = Test-Path (Join-Path $env:SystemRoot "System32\$($c.Id)")
        $available = $exists -and -not ($isHome -and $c.Pro -and $c.Id -in @('gpedit.msc', 'secpol.msc', 'lusrmgr.msc'))
        [pscustomobject]@{
            Id = $c.Id; Name = $c.Name; Available = $available
            Note = $(if (-not $exists) { 'No instalada' } elseif (-not $available) { 'No disponible en Windows Home' } else { '' })
        }
    }
}

function Start-CfgConsole {
    param([Parameter(Mandatory)][string]$Id)
    $path = Join-Path $env:SystemRoot "System32\$Id"
    if (-not (Test-Path $path)) { Write-CfgLog "$Id no está disponible en este equipo." WARN; return }
    Write-CfgLog "Abriendo $Id"
    if ($Id -like '*.msc') { Start-Process (Join-Path $env:SystemRoot 'System32\mmc.exe') -ArgumentList "`"$path`"" }
    else { Start-Process $path }
}

Export-ModuleMember -Function *
