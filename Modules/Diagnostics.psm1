# Diagnostics.psm1 - Pruebas del sistema operativo y consolas de administración (MMC)

function New-CfgCheck { param($c, $r, $d) [pscustomobject]@{ Comprobacion = $c; Resultado = $r; Detalle = $d } }

function Test-CfgVolumeDirtyText {
    <# Interpreta la salida de "fsutil dirty query" en cualquier idioma. Ante la duda no avisa:
       "El volumen - C: no contiene errores" (español actual) también es un volumen limpio. #>
    param([string]$Text)
    if (-not $Text) { return $false }
    if ($Text -match '(?i)\bNOT\s+Dirty|\bno\s+est|no\s+contiene|n''est\s+pas|não\s+está') { return $false }
    return ($Text -match '(?i)\bis\s+Dirty|\bsucio|contiene\s+errores|\best\s+sale\b')
}

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
        if ($dirty) { $out.Add((New-CfgCheck 'Volumen marcado para revisión' $(if (Test-CfgVolumeDirtyText $dirty) { 'AVISO' } else { 'OK' }) $dirty.Trim())) }
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

# ---------------------------------------------------------------- ayuda de las comprobaciones (icono "i")
# Cada regla: P = patrón del nombre de la comprobación (texto original en español), C = a qué se debe,
# S = cómo solucionarlo. Los textos se traducen en la interfaz (Lang\04-ayuda.tsv).

$script:CheckHelp = @(
    @{ P = '^Último reinicio'
       C = 'Windows lleva más de 14 días sin reiniciarse. Algunas actualizaciones y controladores no terminan de aplicarse hasta reiniciar, y el sistema acumula memoria ocupada y procesos colgados.'
       S = 'Guarda tu trabajo y reinicia (Inicio > Iniciar/apagar > Reiniciar). Apagar no cuenta como reinicio si el inicio rápido está activado.' }
    @{ P = '^Tiempo de arranque'
       C = 'El último arranque tardó más de 60 segundos. Suele deberse a muchos programas de inicio, a un disco mecánico (HDD) o a un controlador o servicio lento.'
       S = 'Desactiva los programas que no necesites en Administrador de tareas > Aplicaciones de arranque y comprueba en la pestaña Hardware si Windows está en un SSD.' }
    @{ P = '^Espacio libre'
       C = 'Queda poco espacio en el disco del sistema. Windows lo necesita para actualizarse, para la memoria virtual y para los archivos temporales; con menos del 10 % todo va más lento y las actualizaciones fallan.'
       S = 'Usa Configuración > Sistema > Almacenamiento > Recomendaciones de limpieza, vacía la papelera y desinstala lo que no uses (pestaña Software).' }
    @{ P = '^Volumen marcado'
       C = 'Windows ha marcado el disco como pendiente de revisión: detectó un posible error en el sistema de archivos (por ejemplo, tras un apagado brusco) y quiere comprobarlo con CHKDSK al arrancar.'
       S = 'Pulsa «CHKDSK en línea» en esta pestaña y reinicia para que termine. Si se repite, revisa la salud del disco con CrystalDiskInfo y haz una copia de seguridad.' }
    @{ P = '^Dispositivos con problemas'
       C = 'Algún dispositivo tiene un código de error en el Administrador de dispositivos. Código 24: no está presente o no funciona (habitual en teclados y puertos PS/2 que no existen; se puede ignorar). Código 28: falta el controlador. Códigos 10 y 43: no arranca o Windows lo ha detenido por un fallo.'
       S = 'Abre la pestaña Drivers y BIOS, marca «Solo dispositivos con problemas» y busca el controlador en Windows Update o en la web del fabricante. Si el dispositivo no existe (código 24), puedes ignorarlo.' }
    @{ P = '^Eventos críticos'
       C = 'Windows registró eventos críticos. Kernel-Power 41 significa que el equipo se apagó o reinició sin cerrarse bien: corte de luz, botón de encendido, bloqueo, pantallazo azul, temperatura o fuente de alimentación.'
       S = 'Mira cuándo pasó con «Cargar errores» o con el Monitor de confiabilidad. Si coincide con juegos o carga alta, revisa temperaturas, fuente y controladores de la gráfica; si fue un corte de luz, no es grave.' }
    @{ P = '^Errores \('
       C = 'Hay muchos errores en los registros Sistema y Aplicación. Windows siempre registra algunos sin importancia; lo que cuenta es cuáles se repiten.'
       S = 'Pulsa «Cargar errores» y fíjate en el origen y el Id que más se repiten. En los datos técnicos de abajo tienes el resumen para consultarlo con la IA.' }
    @{ P = '^Servicios esenciales'
       C = 'Algún servicio básico de Windows (actualizaciones, antivirus, cortafuegos, red o WMI) está detenido o deshabilitado. Suele deberse a un programa «optimizador» o, a veces, a malware.'
       S = 'Abre Servicios (services.msc), pon el servicio en Automático e inícialo. Si vuelve a desactivarse, haz un análisis completo con Defender.' }
    @{ P = '^Última actualización de Windows'
       C = 'Hace más de 45 días que no se instala ninguna actualización de Windows, así que faltan parches de seguridad.'
       S = 'Abre Configuración > Windows Update y pulsa «Buscar actualizaciones». Si falla, ejecuta «DISM: reparar imagen» y después «SFC /scannow».' }
    @{ P = '^Reinicio pendiente'
       C = 'Hay actualizaciones o cambios del sistema que esperan un reinicio para terminar de aplicarse.'
       S = 'Reinicia el equipo cuando puedas.' }
    @{ P = '^(Red|Puerta de enlace|Resolución DNS|Acceso a Internet)'
       C = 'Hay un problema de conexión: el equipo no llega al router (puerta de enlace), no resuelve nombres (DNS) o no sale a Internet por HTTPS. Algunos routers no responden al ping aunque funcionen bien.'
       S = 'Comprueba el cable o la Wi-Fi, reinicia el router y prueba otra red. Si solo falla el DNS, prueba los servidores 1.1.1.1 u 8.8.8.8. En una empresa, revisa el proxy o la VPN.' }
    @{ P = '^(Firmware UEFI|Disco del sistema GPT)'
       C = 'El equipo arranca en modo BIOS heredado (Legacy/CSM) o el disco usa MBR. Windows 11, el arranque seguro y muchos antitrampas de juegos necesitan UEFI con disco GPT.'
       S = 'En la pestaña Drivers y BIOS usa «Comprobar conversión MBR → GPT» y «Convertir el disco a GPT» y después desactiva CSM en la BIOS. Haz antes una copia de seguridad.' }
    @{ P = '^Arranque seguro'
       C = 'El arranque seguro (Secure Boot) está desactivado. Protege contra el malware que se carga antes de Windows y lo exigen Windows 11 y algunos juegos.'
       S = 'Actívalo en la BIOS/UEFI (sección Boot o Security); requiere modo UEFI. La pestaña Drivers y BIOS tiene la guía de tu fabricante y el botón para reiniciar en la BIOS.' }
    @{ P = '^TPM'
       C = 'No hay un TPM 2.0 activo o no se ha podido comprobar sin permisos de administrador. Lo necesitan Windows 11, BitLocker y algunos antitrampas.'
       S = 'Si indica que hace falta administrador, abre Eureka_Utils como administrador. Si no, activa Intel PTT o AMD fTPM en la BIOS (guía en la pestaña Drivers y BIOS).' }
    @{ P = '^Virtualización'
       C = 'La virtualización del procesador (VT-x o AMD-V) está desactivada en la BIOS. La necesitan WSL, Hyper-V, el Sandbox de Windows y algunas funciones de seguridad.'
       S = 'Actívala en la BIOS: Intel Virtualization Technology o SVM Mode en AMD.' }
    @{ P = '^(Arquitectura|Procesador|Generación de CPU|Memoria RAM|Disco del sistema)'
       C = 'Este componente no cumple los requisitos mínimos de Windows 11. En algunos casos se puede instalar igualmente, pero sin soporte oficial ni garantía de actualizaciones.'
       S = 'Consulta la lista oficial de procesadores compatibles de Microsoft o valora ampliar el componente (RAM o disco).' }
    @{ P = '^(Antivirus registrados|Defender|Microsoft Defender|Protección contra alteraciones)'
       C = 'La protección antivirus no está completa: no hay antivirus activo, la protección en tiempo real o contra alteraciones está desactivada, o las firmas o los análisis están atrasados.'
       S = 'En el grupo Antivirus y malware pulsa «Actualizar firmas» y «Análisis rápido». Activa la protección en Seguridad de Windows > Protección antivirus y contra amenazas.' }
    @{ P = '^Amenazas detectadas'
       C = 'Microsoft Defender ha detectado amenazas. Si alguna está sin resolver, puede seguir activa en el equipo.'
       S = 'Abre Seguridad de Windows > Historial de protección y resuélvelas. Después haz un «Análisis completo» o usa «Defender sin conexión».' }
    @{ P = '^Firewall'
       C = 'El cortafuegos de Windows está desactivado en algún perfil de red, así que el equipo queda expuesto en esa red.'
       S = 'Actívalo en Seguridad de Windows > Firewall y protección de red, salvo que otro cortafuegos lo sustituya.' }
    @{ P = '^Control de cuentas'
       C = 'El Control de cuentas de usuario (UAC) está desactivado o eleva sin preguntar: cualquier programa puede obtener permisos de administrador sin avisar.'
       S = 'Devuélvelo al nivel predeterminado en Panel de control > Cuentas de usuario > Cambiar configuración de Control de cuentas de usuario.' }
    @{ P = '^BitLocker'
       C = 'El disco del sistema no está protegido con BitLocker: si el equipo se pierde o lo roban, se pueden leer los datos. Con BitLocker activo, cambiar la BIOS puede pedir la clave de recuperación.'
       S = 'Actívalo en Panel de control > Cifrado de unidad BitLocker (Windows Pro) o en Cifrado del dispositivo (Windows Home) y guarda la clave de recuperación. Suspéndelo antes de tocar la BIOS.' }
    @{ P = '^Inicio desde carpetas temporales'
       C = 'Hay programas que se inician con Windows desde carpetas temporales, algo habitual en el malware.'
       S = 'Revisa esas entradas con Autoruns de Sysinternals y analiza el equipo con Defender.' }
    @{ P = '^(Permisos de administrador|Edición de Windows|Pertenencia actual|Nombre del equipo|Localizar controladores|Puertos en|Sincronización horaria|Servidores DNS)'
       C = 'No se cumple un requisito para unir el equipo al dominio: permisos, edición de Windows, nombre del equipo, DNS del dominio, puertos o la hora con el controlador de dominio.'
       S = 'Sigue la indicación del detalle. Lo más habitual: ejecutar como administrador, poner en el adaptador los DNS del dominio (no los del router) y conectar la VPN.' }
    @{ P = '^(Formato|Inquilino Microsoft Entra|Id\. de inquilino|Autodescubrimiento Intune|Doble factor)'
       C = 'La comprobación de la cuenta de trabajo o de Intune no es correcta: el formato de la cuenta, el inquilino de Microsoft 365 o el registro DNS de inscripción.'
       S = 'Revisa que la cuenta esté bien escrita y que haya Internet. El registro DNS de Intune solo lo puede crear el administrador del dominio de la empresa.' }
)
$script:CheckHelpDefault = @{
    C = 'Eureka_Utils ha encontrado algo que conviene revisar. El detalle de la fila indica qué ha visto.'
    S = 'Usa «Preguntar a la IA» para que te ayude a interpretarlo con los datos técnicos y el registro.'
}

function Get-CfgCheckHelp {
    <# Explicación (a qué se debe) y solución de una comprobación. -All devuelve todas las reglas (pruebas). #>
    param([string]$Check, [switch]$All)
    if ($All) { return @($script:CheckHelp + $script:CheckHelpDefault) }
    foreach ($h in $script:CheckHelp) {
        if ($Check -match $h.P) { return [pscustomobject]@{ Cause = $h.C; Solution = $h.S; Known = $true } }
    }
    return [pscustomobject]@{ Cause = $script:CheckHelpDefault.C; Solution = $script:CheckHelpDefault.S; Known = $false }
}

function Get-CfgCheckEvidence {
    <# Datos técnicos de solo lectura que ayudan a analizar una comprobación (lista de líneas). #>
    param([string]$Check)
    $l = New-Object System.Collections.Generic.List[string]
    $cut = { param($t, $n) $t = ("$t" -split "`r?`n")[0].Trim(); if ($t.Length -gt $n) { $t.Substring(0, $n) + '…' } else { $t } }
    try {
        switch -Regex ($Check) {
            '^Dispositivos con problemas' {
                foreach ($d in @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -and $_.ConfigManagerErrorCode -ne 0 })) {
                    $l.Add(('{0} | código {1} | clase {2} | {3}' -f $d.Name, $d.ConfigManagerErrorCode, $d.PNPClass, $d.PNPDeviceID))
                }
            }
            '^Eventos críticos' {
                foreach ($e in @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 1; StartTime = (Get-Date).AddDays(-7) } -MaxEvents 15 -ErrorAction SilentlyContinue)) {
                    $extra = ''
                    if ($e.Id -eq 41) { try { $x = ([xml]$e.ToXml()).Event.EventData.Data; $extra = ' | BugcheckCode ' + @($x | Where-Object { $_.Name -eq 'BugcheckCode' })[0].'#text' + ' | PowerButtonTimestamp ' + @($x | Where-Object { $_.Name -eq 'PowerButtonTimestamp' })[0].'#text' } catch { } }
                    $l.Add(('{0:dd/MM/yyyy HH:mm} | {1} | Id {2}{3} | {4}' -f $e.TimeCreated, $e.ProviderName, $e.Id, $extra, (& $cut $e.Message 160)))
                }
            }
            '^Errores \(' {
                $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System', 'Application'; Level = 2; StartTime = (Get-Date).AddDays(-7) } -MaxEvents 500 -ErrorAction SilentlyContinue)
                foreach ($g in @($ev | Group-Object ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 15)) {
                    $s = $g.Group[0]
                    $l.Add(('{0} veces | {1} | Id {2} | último {3:dd/MM HH:mm} | {4}' -f $g.Count, $s.ProviderName, $s.Id, $s.TimeCreated, (& $cut $s.Message 140)))
                }
            }
            '^Volumen marcado' { $l.Add(((& fsutil.exe dirty query $env:SystemDrive 2>&1) -join ' ').Trim()) }
            '^Servicios esenciales' {
                foreach ($s in @(Get-Service -Name 'wuauserv', 'BITS', 'WinDefend', 'mpssvc', 'EventLog', 'Dnscache', 'LanmanWorkstation', 'CryptSvc', 'Winmgmt' -ErrorAction SilentlyContinue)) { $l.Add(('{0} | {1} | {2}' -f $s.Name, $s.Status, $s.StartType)) }
            }
            '^Reinicio pendiente' {
                foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $l.Add(('{0}: {1}' -f $k, (Test-Path $k))) }
            }
            '^(Red|Puerta de enlace|Resolución DNS|Acceso a Internet)' {
                foreach ($c in @(Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.NetAdapter.Status -eq 'Up' })) {
                    $l.Add(('{0} | IPv4 {1} | puerta de enlace {2} | DNS {3}' -f $c.InterfaceAlias, (@($c.IPv4Address | ForEach-Object IPAddress) -join ', '), (@($c.IPv4DefaultGateway | ForEach-Object NextHop) -join ', '), (@($c.DNSServer | Where-Object { $_.AddressFamily -eq 2 } | ForEach-Object { $_.ServerAddresses }) -join ', ')))
                }
                $proxy = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue)
                $l.Add(('Proxy: {0} {1}' -f $(if ($proxy.ProxyEnable) { 'activado' } else { 'desactivado' }), $proxy.ProxyServer))
            }
            '^(Antivirus registrados|Defender|Microsoft Defender|Protección contra alteraciones|Amenazas detectadas)' {
                $s = Get-MpComputerStatus -ErrorAction Stop
                foreach ($p in 'AMRunningMode', 'RealTimeProtectionEnabled', 'IsTamperProtected', 'AntivirusSignatureVersion', 'AntivirusSignatureLastUpdated', 'QuickScanAge', 'FullScanAge') { $l.Add(('{0}: {1}' -f $p, $s.$p)) }
                foreach ($t in @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Sort-Object InitialDetectionTime -Descending | Select-Object -First 10)) {
                    $l.Add(('{0:dd/MM/yyyy HH:mm} | amenaza {1} | estado {2} | {3}' -f $t.InitialDetectionTime, $t.ThreatID, $t.ThreatStatusID, (& $cut (@($t.Resources) -join '; ') 160)))
                }
            }
        }
    }
    catch { $l.Add("No se pudieron leer los datos técnicos: $($_.Exception.Message)") }
    return $l.ToArray()
}

function Get-CfgIssueEnvironment {
    <# Datos básicos del equipo para el informe que se pasa a la IA (sin nombre de equipo ni usuario). #>
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $product = [string]$cv.ProductName
    if ([int]$cv.CurrentBuild -ge 22000) { $product = $product -replace 'Windows 10', 'Windows 11' }
    $cs = Get-CimInstance Win32_ComputerSystem -Property Manufacturer, Model -ErrorAction SilentlyContinue
    [ordered]@{
        'Eureka_Utils' = (Get-CfgVersion)
        'Windows'      = ('{0} {1} (compilación {2}.{3})' -f $product, $cv.DisplayVersion, $cv.CurrentBuild, $cv.UBR).Trim()
        'Equipo'       = ('{0} {1}' -f $cs.Manufacturer, $cs.Model).Trim()
        'PowerShell'   = $PSVersionTable.PSVersion.ToString()
        'Administrador' = $(if (Test-CfgAdmin) { 'sí' } else { 'no' })
        'Idioma de Windows' = (Get-UICulture).Name
    }
}

function Protect-CfgPrivateText {
    <# Oculta el nombre del equipo, del usuario y su carpeta de perfil antes de compartir un texto. #>
    param([string]$Text)
    if (-not $Text) { return $Text }
    $t = $Text
    if ($env:USERPROFILE) { $t = $t -replace [regex]::Escape($env:USERPROFILE), 'C:\Users\usuario' }
    foreach ($p in @(@($env:COMPUTERNAME, 'PC-EJEMPLO'), @($env:USERNAME, 'usuario'), @($env:USERDOMAIN, 'DOMINIO'))) {
        if ($p[0] -and $p[0].Length -ge 3) { $t = [regex]::Replace($t, '(?<![\w])' + [regex]::Escape($p[0]) + '(?![\w])', $p[1], 'IgnoreCase') }
    }
    return $t
}

Export-ModuleMember -Function *
