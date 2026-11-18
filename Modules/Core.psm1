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
        $LogQueue
    )
    $script:CfgRoot = $Root
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
function Get-CfgLogFile { return $script:LogFile }

function Write-CfgLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][AllowEmptyString()][string]$Message,
        [Parameter(Position = 1)][ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'STEP')][string]$Level = 'INFO'
    )
    $line = '[{0}] [{1,-5}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    if ($script:LogFile) {
        try { Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
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

function Get-CfgDataRoot { if ($script:CfgData) { return $script:CfgData } return $script:CfgRoot }

function Get-CfgExportFolder {
    $d = Join-Path (Get-CfgDataRoot) 'Exports'
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    return $d
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

function Get-CfgSystemSummary {
    $os   = Get-CimInstance Win32_OperatingSystem
    $cs   = Get-CimInstance Win32_ComputerSystem
    $cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
    $bios = Get-CimInstance Win32_BIOS
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
    $ver  = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $tpm  = $null
    try { $tpm = Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop } catch { }
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
        'Número de serie'     = $bios.SerialNumber
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

Export-ModuleMember -Function *
