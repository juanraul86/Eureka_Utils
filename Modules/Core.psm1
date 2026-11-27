# Core.psm1 - Utilidades comunes del Eureka_Utils
# Compatible con Windows PowerShell 5.1 (el que trae Windows) y PowerShell 7.

$script:CfgRoot  = $null
$script:LogFile  = $null
$script:LogQueue = $null

function Set-CfgEnvironment {
    <# Fija la carpeta raíz (portable), el archivo de registro y, opcionalmente,
       una cola concurrente a la que la interfaz gráfica lee el registro. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$LogFile,
        $LogQueue,
        [string]$LogTag
    )
    $script:CfgRoot = $Root
    # Con varias tareas en paralelo, cada línea del registro lleva el nombre de su tarea
    $script:LogTag = $LogTag
    # CFG_DATA lo fija el ejecutable de un solo archivo: registros y exportaciones
    # quedan junto al .exe y no en la carpeta temporal donde se extrae.
    $script:CfgData = $(if ($env:CFG_DATA) { $env:CFG_DATA } else { $Root })
    if (-not $LogFile) {
        $logDir = Join-Path $script:CfgData 'Logs'
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $LogFile = Join-Path $logDir ('Eureka_Utils_{0}_{1}.log' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmmss'))
    }
    $script:LogFile  = $LogFile
    $script:LogQueue = $LogQueue
    return $LogFile
}

function Get-CfgRoot    { return $script:CfgRoot }

function Get-CfgSystemExe {
    <# Ruta completa de una herramienta de Windows (evita ejecutar un archivo homónimo de la carpeta actual). #>
    param([Parameter(Mandatory)][string]$Name)
    if ($Name -ieq 'explorer.exe') { return (Join-Path $env:SystemRoot 'explorer.exe') }
    return (Join-Path $env:SystemRoot "System32\$Name")
}
function Get-CfgLogFile { return $script:LogFile }

function Write-CfgLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][AllowEmptyString()][string]$Message,
        [Parameter(Position = 1)][ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'STEP')][string]$Level = 'INFO'
    )
    if ($script:LogTag) { $Message = '{{{0}}} {1}' -f $script:LogTag, $Message }
    $line = '[{0}] [{1,-5}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    if ($script:LogFile) {
        # Varias tareas en paralelo escriben en el mismo archivo: un mutex evita que choquen y se pierdan líneas
        if (-not $script:LogMutex) { $script:LogMutex = New-Object System.Threading.Mutex($false, 'Local\EurekaUtilsLog') }
        $own = $false
        try {
            try { $own = $script:LogMutex.WaitOne(3000) } catch [System.Threading.AbandonedMutexException] { $own = $true }
            [IO.File]::AppendAllText($script:LogFile, $line + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding $true))
        }
        catch { }
        finally { if ($own) { $script:LogMutex.ReleaseMutex() } }
    }
    if ($script:LogQueue) {
        $script:LogQueue.Enqueue($line)
    }
    else {
        $color = switch ($Level) { 'OK' { 'Green' } 'WARN' { 'Yellow' } 'ERROR' { 'Red' } 'STEP' { 'Cyan' } default { 'Gray' } }
        Write-Host $line -ForegroundColor $color
    }
}

function New-CfgResult {
    param([string]$Id, [string]$Name, [string]$Action, [bool]$Success, [string]$Message)
    [pscustomobject]@{ Id = $Id; Name = $Name; Action = $Action; Success = $Success; Message = $Message }
}

function Test-CfgAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-CfgJson {
    param([Parameter(Mandatory)][string]$Name)
    $path = Join-Path $script:CfgRoot "Catalog\$Name.json"
    if (-not (Test-Path $path)) { throw "No se encuentra el catálogo $path" }
    return (Get-Content -Path $path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

# Versión de Eureka_Utils: fuente única (Build-Exe la usa para los ejecutables)
$script:CfgVersion = '2.4.0'
function Get-CfgVersion { return $script:CfgVersion }

function Get-CfgDataRoot { if ($script:CfgData) { return $script:CfgData } return $script:CfgRoot }

function Get-CfgExportFolder {
    $d = Join-Path (Get-CfgDataRoot) 'Exports'
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    return $d
}

function Clear-CfgUserData {
    <# Privacidad: borra los registros (salvo el de la sesión actual) y todo lo exportado (informes,
       hash de Autopilot, diagnósticos MDM, copias de controladores), que contienen datos del equipo. #>
    param([string]$KeepLog)
    $n = 0
    $logDir = if ($KeepLog) { Split-Path $KeepLog } else { Join-Path (Get-CfgDataRoot) 'Logs' }
    foreach ($d in @($logDir, (Join-Path (Get-CfgDataRoot) 'Exports'))) {
        if (-not (Test-Path $d)) { continue }
        foreach ($it in @(Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue)) {
            if ($KeepLog -and $it.FullName -eq $KeepLog) { continue }
            try { Remove-Item -LiteralPath $it.FullName -Recurse -Force -ErrorAction Stop; $n++ } catch { Write-CfgLog "No se pudo borrar $($it.Name): $($_.Exception.Message)" WARN }
        }
    }
    Write-CfgLog "Privacidad: $n registros e informes borrados (se conserva el registro de esta sesión)." OK
    return $n
}

function Format-CfgSize {
    param([double]$MB)
    if ($MB -ge 1024) { return ('{0:N1} GB' -f ($MB / 1024)) }
    if ($MB -gt 0) { return ('{0:N0} MB' -f $MB) }
    return '—'
}

function Test-CfgTcpPort {
    param([Parameter(Mandatory)][string]$HostName, [Parameter(Mandatory)][int]$Port, [int]$TimeoutMs = 1500)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync($HostName, $Port)
        if ($task.Wait($TimeoutMs)) { return $client.Connected }
        return $false
    }
    catch { return $false }
    finally { $client.Close() }
}

# ---------------------------------------------------------------- Inventario

function Get-CfgInstalledPrograms {
    <# Programas Win32 registrados (64 bits, 32 bits y usuario actual). #>
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($p in $paths) {
        Get-ItemProperty -Path $p -ErrorAction SilentlyContinue |
            Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName } |
            ForEach-Object {
                [pscustomobject]@{
                    DisplayName          = $_.DisplayName
                    DisplayVersion       = $_.DisplayVersion
                    Publisher            = $_.Publisher
                    UninstallString      = $_.UninstallString
                    QuietUninstallString = $_.QuietUninstallString
                    KeyName              = $_.PSChildName
                    InstallLocation      = $(if ($_.PSObject.Properties['InstallLocation']) { [string]$_.InstallLocation } else { '' })
                    DisplayIcon          = $(if ($_.PSObject.Properties['DisplayIcon']) { [string]$_.DisplayIcon } else { '' })
                    Hive                 = $(if ($p -like 'HKCU:*') { 'HKCU' } else { 'HKLM' })
                }
            }
    }
}

function Get-CfgAppxPackages {
    <# Paquetes Appx/MSIX. Con permisos de administrador se consultan todos los usuarios. #>
    try {
        if (Test-CfgAdmin) { return @(Get-AppxPackage -AllUsers -ErrorAction Stop) }
        return @(Get-AppxPackage -ErrorAction Stop)
    }
    catch {
        Write-CfgLog "No se pudieron enumerar las aplicaciones Appx: $($_.Exception.Message)" WARN
        return @()
    }
}

function Invoke-CfgRegistryUninstall {
    <# Desinstala un programa Win32 usando su cadena de desinstalación silenciosa o MSI. #>
    param([Parameter(Mandatory)]$Program)
    # Seguridad: las entradas de HKCU las puede crear cualquier usuario. Ejecutarlas con permisos de
    # administrador permitiría a un usuario estándar lanzar su propio comando como administrador.
    if ($Program.Hive -eq 'HKCU' -and (Test-CfgAdmin)) {
        Write-CfgLog "'$($Program.DisplayName)' está registrado solo para un usuario (HKCU): por seguridad no se ejecuta su desinstalador con permisos de administrador. Desinstálalo desde la sesión de ese usuario (Configuración > Aplicaciones)." WARN
        return $false
    }
    $cmd = $null
    if ($Program.QuietUninstallString) { $cmd = $Program.QuietUninstallString }
    elseif ($Program.KeyName -match '^\{[0-9A-Fa-f\-]{36}\}$') { $cmd = "msiexec.exe /x $($Program.KeyName) /qn /norestart" }
    elseif ($Program.UninstallString -match 'msiexec') { $cmd = ($Program.UninstallString -replace '/I', '/X') + ' /qn /norestart' }

    if (-not $cmd) {
        Write-CfgLog "'$($Program.DisplayName)' no ofrece desinstalación silenciosa. Desinstálalo desde Configuración > Aplicaciones." WARN
        return $false
    }
    Write-CfgLog "Ejecutando: $cmd"
    try {
        $p = Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList "/c `"$cmd`"" -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
        $info = Get-CfgExitInfo -Code $p.ExitCode
        Write-CfgLog "$($Program.DisplayName): $($info.Message)" $(if ($info.Success) { 'OK' } else { 'ERROR' })
        return $info.Success
    }
    catch {
        Write-CfgLog "Error desinstalando $($Program.DisplayName): $($_.Exception.Message)" ERROR
        return $false
    }
}

function Get-CfgExitInfo {
    param([int]$Code)
    $ok = $true
    switch ($Code) {
        0            { $msg = 'Correcto' }
        3010         { $msg = 'Correcto (requiere reinicio)' }
        1641         { $msg = 'Correcto (reinicio iniciado por el instalador)' }
        -1978335189  { $msg = 'Ya instalado y sin actualizaciones pendientes' }     # 0x8A15002B
        -1978335135  { $msg = 'Ya estaba instalado' }                               # 0x8A150061
        -1978335212  { $msg = 'Paquete no encontrado en el origen'; $ok = $false }   # 0x8A150014
        1602         { $msg = 'Cancelado por el usuario'; $ok = $false }
        1618         { $msg = 'Hay otra instalación en curso (MSI 1618)'; $ok = $false }
        default      { $msg = ('Código de salida {0} (0x{1:X8})' -f $Code, $Code); $ok = $false }
    }
    [pscustomobject]@{ Success = $ok; Message = $msg; Code = $Code }
}

# ---------------------------------------------------------------- winget

function Get-CfgWingetPath {
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    # En sesiones elevadas o de otro usuario winget puede no estar en el PATH
    $candidate = Get-ChildItem -Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue |
        Sort-Object { $_.Directory.Name } -Descending | Select-Object -First 1
    if ($candidate) { return $candidate.FullName }
    return $null
}

function Confirm-CfgWinget {
    $p = Get-CfgWingetPath
    if ($p) { return $p }
    Write-CfgLog 'winget no encontrado. Intentando registrar "Instalador de aplicación"...' WARN
    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction Stop
    }
    catch { Write-CfgLog "No se pudo registrar App Installer: $($_.Exception.Message)" WARN }
    $p = Get-CfgWingetPath
    if (-not $p) {
        Write-CfgLog 'winget no está disponible. Instala "Instalador de aplicación" desde Microsoft Store o usa paquetes locales (carpeta Packages).' ERROR
    }
    return $p
}

function Wait-CfgWinget {
    <# Tras instalar Windows, "Instalador de aplicación" (winget) tarda unos minutos en
       registrarse para el primer usuario. Espera hasta $Minutes antes de rendirse. #>
    param([int]$Minutes = 10)
    $limit = (Get-Date).AddMinutes($Minutes)
    $warned = $false
    while ((Get-Date) -lt $limit) {
        $p = Get-CfgWingetPath
        if ($p) {
            try { & $p --version 2>$null | Out-Null; if ($LASTEXITCODE -eq 0) { return $p } } catch { }
        }
        if (-not $warned) { Write-CfgLog "Esperando a que winget esté disponible (hasta $Minutes min; es normal justo después de instalar Windows)..." WARN; $warned = $true }
        try { Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction SilentlyContinue } catch { }
        Start-Sleep -Seconds 15
    }
    return (Confirm-CfgWinget)
}

function Wait-CfgNetwork {
    param([int]$Minutes = 5)
    $limit = (Get-Date).AddMinutes($Minutes)
    while ((Get-Date) -lt $limit) {
        if (Test-CfgTcpPort -HostName 'cdn.winget.microsoft.com' -Port 443 -TimeoutMs 3000) { return $true }
        Write-CfgLog 'Sin conexión a Internet todavía; reintentando en 15 s (conecta el cable o la Wi-Fi)...' WARN
        Start-Sleep -Seconds 15
    }
    return $false
}

function Invoke-CfgWinget {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $winget = Confirm-CfgWinget
    if (-not $winget) { return -1 }
    Write-CfgLog ('winget {0}' -f ($Arguments -join ' '))
    $prev = $null
    try { $prev = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
    & $winget @Arguments 2>&1 | ForEach-Object {
        # winget dibuja barras de progreso con retornos de carro: nos quedamos con el último tramo
        $l = ("$_" -split "`r")[-1].Trim()
        if ($l -and $l -notmatch '^[\-\\|/]$' -and $l -notmatch '[█▒]') { Write-CfgLog "   $l" }
    }
    $code = $LASTEXITCODE
    if ($prev) { try { [Console]::OutputEncoding = $prev } catch { } }
    return [int]$code
}

# ---------------------------------------------------------------- Sistema

function Get-CfgTpm {
    <# Win32_Tpm una sola vez por proceso. Sin permisos de administrador Windows tarda unos 5 s en
       denegar el acceso, así que ni se intenta: se lanza el error directamente (los llamadores ya
       lo tratan como "ejecuta como administrador para comprobarlo"). #>
    if (-not (Test-CfgAdmin)) { throw 'Acceso denegado: el TPM solo se puede consultar como administrador.' }
    if (-not $script:TpmQueried) {
        $script:TpmCache = Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop
        $script:TpmQueried = $true
    }
    return $script:TpmCache
}

function Get-CfgSystemSummary {
    $os   = Get-CimInstance Win32_OperatingSystem
    $cs   = Get-CimInstance Win32_ComputerSystem
    $cpu  = Get-CimInstance Win32_Processor -Property Name, Architecture, MaxClockSpeed, NumberOfCores, NumberOfLogicalProcessors, VirtualizationFirmwareEnabled | Select-Object -First 1
    $bios = Get-CimInstance Win32_BIOS
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
    $ver  = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $tpm  = $null
    try { $tpm = Get-CfgTpm } catch { }
    $wg = Get-CfgWingetPath
    $wgVer = 'No disponible'
    if ($wg) { try { $wgVer = (& $wg --version 2>$null | Select-Object -First 1) } catch { } }

    $ramTotalMB  = [math]::Round($cs.TotalPhysicalMemory / 1MB)
    $ramFreeMB   = [math]::Round($os.FreePhysicalMemory / 1KB)    # FreePhysicalMemory viene en KB
    $diskTotalMB = [math]::Round($disk.Size / 1MB)
    $diskFreeMB  = [math]::Round($disk.FreeSpace / 1MB)
    $isAdmin     = Test-CfgAdmin

    $display = [ordered]@{
        'Equipo'              = $env:COMPUTERNAME
        'Fabricante / modelo' = ('{0} {1}' -f $cs.Manufacturer, $cs.Model).Trim()
        'Número de serie'     = $(if ("$($bios.SerialNumber)".Trim() -match '^\s*$|Default string|To be filled|System Serial Number|O\.E\.M|Not Applicable|^0+$') { '—' } else { $bios.SerialNumber })
        'Sistema operativo'   = $os.Caption
        'Versión'             = ('{0} (compilación {1}.{2})' -f $ver.DisplayVersion, $ver.CurrentBuild, $ver.UBR)
        'Procesador'          = ('{0} · {1} núcleos / {2} hilos' -f $cpu.Name.Trim(), $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)
        'Memoria RAM'         = ('{0} libres de {1}' -f (Format-CfgSize $ramFreeMB), (Format-CfgSize $ramTotalMB))
        "Disco $($env:SystemDrive)" = ('{0} libres de {1}' -f (Format-CfgSize $diskFreeMB), (Format-CfgSize $diskTotalMB))
        'TPM'                 = $(if ($tpm) { "Presente · versión $(($tpm.SpecVersion -split ',')[0])" } else { 'No detectado o sin permisos' })
        'Dominio / grupo'     = $(if ($cs.PartOfDomain) { "Dominio $($cs.Domain)" } else { "Grupo de trabajo $($cs.Workgroup)" })
        'Usuario'             = "$env:USERDOMAIN\$env:USERNAME" + $(if ($isAdmin) { ' (administrador)' } else { ' (sin elevar)' })
        'winget'              = $wgVer
    }
    [pscustomobject]@{
        RamTotalMB  = $ramTotalMB
        RamFreeMB   = $ramFreeMB
        DiskTotalMB = $diskTotalMB
        DiskFreeMB  = $diskFreeMB
        IsAdmin     = $isAdmin
        Display     = $display
    }
}

function New-CfgRestorePoint {
    param([string]$Description = 'Eureka_Utils')
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $prev = (Get-ItemProperty -Path $key -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
    try {
        Write-CfgLog 'Creando punto de restauración del sistema...' STEP
        Enable-ComputerRestore -Drive "$($env:SystemDrive)\" -ErrorAction SilentlyContinue
        # Windows solo permite un punto cada 24 h salvo que se ajuste esta frecuencia
        New-ItemProperty -Path $key -Name SystemRestorePointCreationFrequency -Value 0 -PropertyType DWord -Force | Out-Null
        Checkpoint-Computer -Description $Description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-CfgLog 'Punto de restauración creado.' OK
        return $true
    }
    catch {
        Write-CfgLog "No se pudo crear el punto de restauración: $($_.Exception.Message)" WARN
        return $false
    }
    finally {
        if ($null -ne $prev) { Set-ItemProperty -Path $key -Name SystemRestorePointCreationFrequency -Value $prev -ErrorAction SilentlyContinue }
        else { Remove-ItemProperty -Path $key -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue }
    }
}

function Restart-CfgComputerDelayed {
    param([int]$Seconds = 60)
    Write-CfgLog "El equipo se reiniciará en $Seconds segundos (cancelar con: shutdown /a)." WARN
    & shutdown.exe /r /t $Seconds /c "Eureka_Utils: reinicio para completar los cambios" /d p:4:1 | Out-Null
}

# ---------------------------------------------------------------- permisos de la carpeta

function Test-CfgFolderSecurity {
    <# Devuelve las identidades sin privilegios que pueden modificar la carpeta (vacío = segura).
       En unidades sin permisos (FAT32/exFAT, p. ej. un USB) devuelve 'SIN-PERMISOS'. #>
    param([Parameter(Mandatory)][string]$Path)
    try {
        $drive = [IO.Path]::GetPathRoot((Resolve-Path $Path).Path)
        if ($drive -like '\\*') { return @() }   # recurso de red: los permisos los controla el servidor
        $fs = (Get-Volume -DriveLetter $drive.Substring(0, 1) -ErrorAction Stop).FileSystem
        if ($fs -notin @('NTFS', 'ReFS')) { return @('SIN-PERMISOS') }
    }
    catch { }
    $weak = @('S-1-1-0', 'S-1-5-11', 'S-1-5-32-545', 'S-1-5-4', 'S-1-5-7')
    # Solo los bits que permiten escribir. (Antes se usaba "FullControl" en la máscara, que incluye
    # también los de lectura: cualquier carpeta legible por Usuarios parecía insegura.)
    # WriteData/CreateFiles 0x2, AppendData 0x4, WriteExtendedAttributes 0x10, DeleteSubdirectoriesAndFiles 0x40,
    # WriteAttributes 0x100, Delete 0x10000, ChangePermissions 0x40000, TakeOwnership 0x80000,
    # GENERIC_ALL 0x10000000 y GENERIC_WRITE 0x40000000 (en permisos heredables).
    $write = [int64](0x2 -bor 0x4 -bor 0x10 -bor 0x40 -bor 0x100 -bor 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x10000000 -bor 0x40000000)
    $out = foreach ($a in (Get-Acl -Path $Path).Access) {
        if ($a.AccessControlType -ne 'Allow') { continue }
        try { $sid = $a.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { continue }
        $rights = ([int64][int]$a.FileSystemRights) -band [int64]4294967295
        if ($weak -contains $sid -and ($rights -band $write)) { [string]$a.IdentityReference }
    }
    return @($out | Select-Object -Unique)
}

function Protect-CfgFolder {
    <# Deja la carpeta modificable solo por Administradores y SYSTEM (los usuarios pueden leer y ejecutar). #>
    param([Parameter(Mandatory)][string]$Path)
    $icacls = Get-CfgSystemExe 'icacls.exe'
    $Path = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\')
    # 0) Copia de los permisos actuales para deshacer el cambio si algo sale mal
    $backup = Join-Path $env:TEMP ('Eureka_Utils_permisos_{0}.txt' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    & $icacls $Path /save $backup /T /C /Q 2>&1 | Out-Null
    $hasBackup = Test-Path -LiteralPath $backup
    # 1) Solo la carpeta raíz: sin herencia y con permisos que heredan subcarpetas y archivos.
    #    No se usa /T aquí: (OI)(CI) solo es válido en carpetas y en los archivos fallaba DESPUÉS de
    #    quitarles la herencia, que quedaban sin ningún permiso (nadie podía leer los módulos).
    & $icacls $Path /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' /C /Q | Out-Null
    $code = $LASTEXITCODE
    # 2) Todo lo de dentro vuelve a heredar de la raíz (y pierde permisos explícitos que den escritura a otros)
    if ($code -eq 0) { & $icacls (Join-Path $Path '*') /reset /T /C /Q | Out-Null; $code = $LASTEXITCODE }
    # 3) Comprobación: el código de Eureka_Utils se sigue pudiendo leer
    $unreadable = @(Get-CfgUnreadableCode -Root $Path)
    if ($unreadable.Count) {
        # Marcha atrás: nunca se deja Eureka_Utils sin poder leer su propio código
        if ($hasBackup) { & $icacls (Split-Path $Path -Parent) /restore $backup /C /Q 2>&1 | Out-Null }
        if (@(Get-CfgUnreadableCode -Root $Path).Count) { & $icacls (Join-Path $Path '*') /reset /T /C /Q 2>&1 | Out-Null }
        Write-CfgLog ("La protección de la carpeta dejaba archivos sin acceso ({0}): se han restaurado los permisos anteriores." -f ($unreadable -join ', ')) WARN
        $unreadable = @(Get-CfgUnreadableCode -Root $Path)
        if ($hasBackup) { Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue }
        return $false
    }
    if ($hasBackup) { Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue }
    $ok =($code -eq 0) -and -not $unreadable.Count -and -not @(Test-CfgFolderSecurity -Path $Path).Count
    if ($ok) { Write-CfgLog "Carpeta protegida: solo administradores y SYSTEM pueden modificar $Path." OK }
    else { Write-CfgLog ("No se pudieron ajustar bien los permisos de {0} (código {1}){2}" -f $Path, $code, $(if ($unreadable.Count) { '. Sin acceso de lectura: ' + ($unreadable -join ', ') } else { '' })) WARN }
    return $ok
}

function Get-CfgUnreadableCode {
    <# Archivos de código de Eureka_Utils que no se pueden leer (permisos rotos). Vacío = todo correcto. #>
    param([Parameter(Mandatory)][string]$Root)
    $files = @(Get-ChildItem -LiteralPath (Join-Path $Root 'Modules'), (Join-Path $Root 'UI'), (Join-Path $Root 'Lang') -File -ErrorAction SilentlyContinue)
    $files += @(Get-Item -LiteralPath (Join-Path $Root 'Eureka_Utils.ps1') -ErrorAction SilentlyContinue)
    foreach ($f in $files) {
        try { [IO.File]::OpenRead($f.FullName).Dispose() } catch { $f.Name }
    }
}

Export-ModuleMember -Function *
