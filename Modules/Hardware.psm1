# Hardware.psm1 - Inventario de hardware, GPU, discos, compatibilidad con Windows 11 y recomendaciones

function Get-CfgGpuVendor {
    param([string]$PnpId, [string]$Name)
    if ($Name -match 'Microsoft Basic|Remote Display|Hyper-V|VMware|VirtualBox|Parsec|Citrix|Meta Virtual|Virtual Display') { return 'Virtual' }
    if ($PnpId -match 'VEN_10DE' -or $Name -match 'NVIDIA|GeForce|Quadro|RTX') { return 'NVIDIA' }
    if ($PnpId -match 'VEN_1002|VEN_1022' -or $Name -match '\bAMD\b|Radeon') { return 'AMD' }
    if ($PnpId -match 'VEN_8086' -or $Name -match 'Intel') { return 'Intel' }
    if ($PnpId -match 'VEN_5143|QCOM' -or $Name -match 'Qualcomm|Adreno') { return 'Qualcomm' }
    return 'Otro'
}

function ConvertTo-CfgNvidiaVersion {
    <# 32.0.15.6094 -> 560.94 (versión comercial del controlador NVIDIA) #>
    param([string]$DriverVersion)
    $p = $DriverVersion -split '\.'
    if ($p.Count -lt 4) { return $DriverVersion }
    $digits = ($p[2] + $p[3].PadLeft(4, '0'))
    if ($digits.Length -lt 5) { return $DriverVersion }
    $d = $digits.Substring($digits.Length - 5)
    return ('{0}.{1}' -f [int]$d.Substring(0, 3), $d.Substring(3))
}

function Get-CfgGpuMemoryMB {
    param([string]$Name, $AdapterRam)
    # AdapterRAM es de 32 bits (máx. 4 GB); el registro guarda el valor real
    $classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    foreach ($k in (Get-ChildItem $classKey -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' })) {
        $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
        if ($p -and $p.DriverDesc -eq $Name) {
            $q = $p.'HardwareInformation.qwMemorySize'
            if ($q) { return [math]::Round([double]$q / 1MB) }
            $m = $p.'HardwareInformation.MemorySize'
            if ($m -is [byte[]]) { return [math]::Round([BitConverter]::ToUInt32($m, 0) / 1MB) }
            if ($m) { return [math]::Round([double]$m / 1MB) }
        }
    }
    if ($AdapterRam) { return [math]::Round([double]$AdapterRam / 1MB) }
    return 0
}

function Get-CfgHardware {
    $cs    = Get-CimInstance Win32_ComputerSystem
    $bios  = Get-CimInstance Win32_BIOS
    $board = Get-CimInstance Win32_BaseBoard
    $cpu   = Get-CimInstance Win32_Processor | Select-Object -First 1
    $enc   = Get-CimInstance Win32_SystemEnclosure | Select-Object -First 1
    $bat   = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)

    $laptopTypes = 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32
    $isLaptop  = ($bat.Count -gt 0) -or (@($enc.ChassisTypes | Where-Object { $laptopTypes -contains $_ }).Count -gt 0)
    $isVirtual = ($cs.Model -match 'Virtual|VMware|KVM|QEMU|HVM') -or ($cs.Manufacturer -match 'QEMU|Xen|innotek|Parallels')

    $memTypes = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }
    $dimms = @(Get-CimInstance Win32_PhysicalMemory)
    $slots = (Get-CimInstance Win32_PhysicalMemoryArray | Measure-Object -Property MemoryDevices -Sum).Sum
    $memType = $null
    if ($dimms.Count) { $memType = $memTypes[[int]$dimms[0].SMBIOSMemoryType] }
    $memSpeed = ($dimms | Measure-Object -Property ConfiguredClockSpeed -Maximum).Maximum

    $gpus = @(Get-CimInstance Win32_VideoController | ForEach-Object {
            $vendor = Get-CfgGpuVendor -PnpId $_.PNPDeviceID -Name $_.Name
            $drvDate = $null
            if ($_.DriverDate) { $drvDate = [datetime]$_.DriverDate }
            $ver = $_.DriverVersion
            if ($vendor -eq 'NVIDIA') { $ver = "{0} ({1})" -f (ConvertTo-CfgNvidiaVersion $_.DriverVersion), $_.DriverVersion }
            [pscustomobject]@{
                Name          = $_.Name
                Vendor        = $vendor
                VramMB        = Get-CfgGpuMemoryMB -Name $_.Name -AdapterRam $_.AdapterRAM
                DriverVersion = $ver
                DriverDate    = $drvDate
                DriverAgeDays = $(if ($drvDate) { [int]((Get-Date) - $drvDate).TotalDays } else { $null })
                Resolution    = $(if ($_.CurrentHorizontalResolution) { '{0}x{1} @ {2} Hz' -f $_.CurrentHorizontalResolution, $_.CurrentVerticalResolution, $_.CurrentRefreshRate } else { '' })
            }
        })

    $disks = @()
    try {
        $sysDiskNumber = (Get-Partition -DriveLetter $env:SystemDrive.TrimEnd(':') -ErrorAction Stop).DiskNumber
        $disks = @(Get-PhysicalDisk -ErrorAction Stop | Sort-Object DeviceId | ForEach-Object {
                [pscustomobject]@{
                    Model  = $_.FriendlyName
                    Media  = $(switch ([string]$_.MediaType) { 'SSD' { 'SSD' } 'HDD' { 'HDD' } default { 'Desconocido' } })
                    Bus    = [string]$_.BusType
                    SizeGB = [math]::Round($_.Size / 1GB)
                    Health = [string]$_.HealthStatus
                    System = ([string]$_.DeviceId -eq [string]$sysDiskNumber)
                }
            })
    }
    catch { }

    $nets = @()
    try {
        $nets = @(Get-NetAdapter -Physical -ErrorAction Stop | ForEach-Object {
                [pscustomobject]@{ Name = $_.Name; Description = $_.InterfaceDescription; Status = [string]$_.Status; Speed = $_.LinkSpeed }
            })
    }
    catch { }

    [pscustomobject]@{
        Manufacturer = $cs.Manufacturer
        Model        = $cs.Model
        Board        = ('{0} {1}' -f $board.Manufacturer, $board.Product).Trim()
        Bios         = ('{0} ({1:yyyy-MM-dd})' -f $bios.SMBIOSBIOSVersion, $bios.ReleaseDate)
        Cpu          = $cpu.Name.Trim()
        Cores        = $cpu.NumberOfCores
        Threads      = $cpu.NumberOfLogicalProcessors
        CpuMHz       = $cpu.MaxClockSpeed
        Arch         = $(switch ($cpu.Architecture) { 9 { 'x64' } 12 { 'ARM64' } 0 { 'x86' } default { "$($cpu.Architecture)" } })
        RamGB        = [math]::Round($cs.TotalPhysicalMemory / 1GB)
        RamType      = $memType
        RamSpeed     = $memSpeed
        RamModules   = $dimms.Count
        RamSlots     = $slots
        IsLaptop     = $isLaptop
        IsVirtual    = $isVirtual
        HasBattery   = ($bat.Count -gt 0)
        Gpus         = $gpus
        GpuVendors   = @($gpus | Where-Object { $_.Vendor -notin @('Virtual', 'Otro') } | ForEach-Object { $_.Vendor } | Select-Object -Unique)
        Disks        = $disks
        Nets         = $nets
    }
}

function Get-CfgHardwareDisplay {
    param([Parameter(Mandatory)]$Hw)
    $ram = '{0} GB' -f $Hw.RamGB
    if ($Hw.RamType) { $ram += " $($Hw.RamType)" }
    if ($Hw.RamSpeed) { $ram += " a $($Hw.RamSpeed) MT/s" }
    if ($Hw.RamSlots) { $ram += " · {0} de {1} ranuras ocupadas" -f $Hw.RamModules, $Hw.RamSlots }
    [ordered]@{
        'Tipo de equipo' = $(if ($Hw.IsVirtual) { 'Máquina virtual' } elseif ($Hw.IsLaptop) { 'Portátil' } else { 'Sobremesa' })
        'Equipo'         = ('{0} {1}' -f $Hw.Manufacturer, $Hw.Model).Trim()
        'Placa base'     = $Hw.Board
        'BIOS / UEFI'    = $Hw.Bios
        'Procesador'     = '{0} · {1}C/{2}T · {3} · {4:N1} GHz' -f $Hw.Cpu, $Hw.Cores, $Hw.Threads, $Hw.Arch, ($Hw.CpuMHz / 1000)
        'Memoria'        = $ram
        'Gráfica(s)'     = (($Hw.Gpus | ForEach-Object { '{0} ({1})' -f $_.Name, $_.Vendor }) -join ' + ')
        'Red'            = (($Hw.Nets | ForEach-Object { '{0} [{1}]' -f $_.Description, $_.Status }) -join "`n")
    }
}

function Test-CfgWin11Compat {
    param($Hw)
    if (-not $Hw) { $Hw = Get-CfgHardware }
    $out = New-Object System.Collections.Generic.List[object]
    $add = { param($c, $r, $d) $out.Add([pscustomobject]@{ Comprobacion = $c; Resultado = $r; Detalle = $d }) }

    & $add 'Arquitectura' $(if ($Hw.Arch -in @('x64', 'ARM64')) { 'OK' } else { 'FALLO' }) $Hw.Arch
    & $add 'Procesador (núcleos)' $(if ($Hw.Cores -ge 2 -and $Hw.CpuMHz -ge 1000) { 'OK' } else { 'FALLO' }) ('{0} núcleos a {1:N1} GHz (mín. 2 a 1 GHz)' -f $Hw.Cores, ($Hw.CpuMHz / 1000))

    $gen = $null; $cpuOk = $null
    if ($Hw.Cpu -match 'Core\(TM\) Ultra|Core Ultra|Ryzen AI|Snapdragon') { $cpuOk = $true }
    elseif ($Hw.Cpu -match 'i[3579]-(\d{4,5})') { $n = $matches[1]; $gen = if ($n.Length -eq 5) { [int]$n.Substring(0, 2) } else { [int]$n.Substring(0, 1) }; $cpuOk = ($gen -ge 8) }
    elseif ($Hw.Cpu -match 'Ryzen \d+ (?:PRO )?(\d)\d{3}') { $gen = [int]$matches[1]; $cpuOk = ($gen -ge 2) }
    if ($null -eq $cpuOk) { & $add 'Generación de CPU' 'AVISO' 'No se pudo determinar; consulta la lista oficial de CPU compatibles.' }
    else { & $add 'Generación de CPU' $(if ($cpuOk) { 'OK' } else { 'FALLO' }) $(if ($gen) { "Generación $gen (Intel 8.ª+ / Ryzen 2000+)" } else { $Hw.Cpu }) }

    & $add 'Memoria RAM' $(if ($Hw.RamGB -ge 4) { 'OK' } else { 'FALLO' }) ('{0} GB (mín. 4 GB; recomendado 8 GB o más)' -f $Hw.RamGB)
    $sys = $Hw.Disks | Where-Object { $_.System } | Select-Object -First 1
    if ($sys) { & $add 'Disco del sistema' $(if ($sys.SizeGB -ge 64) { 'OK' } else { 'FALLO' }) ('{0} GB {1}' -f $sys.SizeGB, $sys.Media) }

    $sbKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State'
    if (Test-Path $sbKey) {
        $sb = (Get-ItemProperty $sbKey -ErrorAction SilentlyContinue).UEFISecureBootEnabled
        & $add 'Firmware UEFI' 'OK' 'El equipo arranca en modo UEFI'
        & $add 'Arranque seguro' $(if ($sb -eq 1) { 'OK' } else { 'AVISO' }) $(if ($sb -eq 1) { 'Activado' } else { 'Compatible pero desactivado: actívalo en la BIOS/UEFI' })
    }
    else { & $add 'Firmware UEFI' 'FALLO' 'Arranque en modo BIOS heredado (Legacy/CSM). Windows 11 requiere UEFI con disco GPT.' }

    try {
        $tpm = Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop
        if ($tpm) {
            $v = ($tpm.SpecVersion -split ',')[0].Trim()
            & $add 'TPM' $(if ([double]::Parse($v, [Globalization.CultureInfo]::InvariantCulture) -ge 2) { 'OK' } else { 'FALLO' }) "Versión $v$(if (-not $tpm.IsEnabled_InitialValue) { ' (deshabilitado)' })"
        }
        else { & $add 'TPM' 'FALLO' 'No hay TPM o está desactivado en la BIOS (Intel PTT / AMD fTPM).' }
    }
    catch { & $add 'TPM' 'AVISO' 'Ejecuta como administrador para comprobarlo.' }
    return $out.ToArray()
}

function Get-CfgHardwareRecommendations {
    <# Devuelve recomendaciones; SoftwareId apunta a una entrada del catálogo de software. #>
    param([Parameter(Mandatory)]$Hw)
    $r = New-Object System.Collections.Generic.List[object]
    $add = { param($lvl, $txt, $sw) $r.Add([pscustomobject]@{ Nivel = $lvl; Texto = $txt; SoftwareId = $sw }) }

    if ($Hw.IsVirtual) { & $add 'INFO' 'Máquina virtual: instala las herramientas del hipervisor en lugar de controladores gráficos.' $null }
    foreach ($g in $Hw.Gpus) {
        switch ($g.Vendor) {
            'NVIDIA' { & $add 'ACCIÓN' "$($g.Name): instala NVIDIA App para obtener controladores Game Ready/Studio y optimización de juegos." 'nvidia-app' }
            'AMD'    { & $add 'ACCIÓN' "$($g.Name): instala AMD Software: Adrenalin Edition (controladores, Radeon Anti-Lag, grabación ReLive)." 'amd-adrenalin' }
            'Intel'  { & $add 'INFO' "$($g.Name): Intel Driver & Support Assistant mantiene al día gráficos, Wi-Fi y Bluetooth Intel." 'intel-dsa' }
        }
        if ($g.Vendor -in @('NVIDIA', 'AMD', 'Intel') -and $g.DriverAgeDays -gt 365) {
            & $add 'AVISO' ('Controlador de {0} con {1} meses de antigüedad: actualízalo (rendimiento y seguridad).' -f $g.Name, [int]($g.DriverAgeDays / 30)) $null
        }
    }
    if (@($Hw.GpuVendors | Where-Object { $_ -in @('NVIDIA', 'AMD') }).Count -and $Hw.Gpus.Count -gt 1) {
        & $add 'INFO' 'Gráfica integrada + dedicada: asigna la dedicada a juegos en Configuración > Pantalla > Gráficos.' $null
    }
    if ($Hw.RamGB -lt 8) { & $add 'AVISO' "Solo $($Hw.RamGB) GB de RAM: evita perfiles Gaming/Streaming/Creativo y aplicaciones pesadas (Teams, Chrome con muchas pestañas)." $null }
    elseif ($Hw.RamGB -lt 16) { & $add 'INFO' "$($Hw.RamGB) GB de RAM: suficiente para oficina; para gaming + streaming se recomiendan 16-32 GB." $null }
    if ($Hw.RamSlots -and $Hw.RamModules -eq 1 -and $Hw.RamSlots -gt 1 -and -not $Hw.IsLaptop) {
        & $add 'INFO' 'Un único módulo de RAM: con dos módulos iguales (dual channel) mejora notablemente el rendimiento gráfico y en juegos.' $null
    }
    foreach ($d in $Hw.Disks) {
        if ($d.System -and $d.Media -eq 'HDD') { & $add 'AVISO' "El sistema está en un disco mecánico ($($d.Model)). Cambiar a SSD es la mejora más notable." $null }
        if ($d.Health -and $d.Health -ne 'Healthy') { & $add 'CRÍTICO' "El disco $($d.Model) informa estado '$($d.Health)': haz copia de seguridad y revísalo con CrystalDiskInfo." 'crystaldiskinfo' }
    }
    if ($Hw.HasBattery) { & $add 'INFO' 'Portátil con batería: genera el informe de batería para ver su desgaste.' $null }
    return $r.ToArray()
}

function Resolve-CfgHardwareSoftware {
    <# Sustituye el comodín '@gpu' por el software de controladores adecuado a las gráficas detectadas. #>
    param([string[]]$Ids, [string[]]$GpuVendors)
    if (-not $GpuVendors) { try { $GpuVendors = (Get-CfgHardware).GpuVendors } catch { $GpuVendors = @() } }
    $map = @{ 'NVIDIA' = 'nvidia-app'; 'AMD' = 'amd-adrenalin'; 'Intel' = 'intel-dsa' }
    $out = foreach ($id in $Ids) {
        if ($id -eq '@gpu') {
            # Con gráfica dedicada no se instala el asistente de Intel (suele ser la integrada)
            $dedicated = @($GpuVendors | Where-Object { $_ -in @('NVIDIA', 'AMD') })
            $use = if ($dedicated.Count) { $dedicated } else { $GpuVendors }
            foreach ($v in $use) { if ($map[$v]) { $map[$v] } }
        }
        else { $id }
    }
    return @($out | Where-Object { $_ } | Select-Object -Unique)
}

function Get-CfgMemoryUsage {
    <# Consumo REAL de memoria ahora mismo: total del sistema, programas que más usan (agrupados) y,
       si se pasa el catálogo, la RAM que usa cada aplicación del catálogo que se está ejecutando.
       Se mide el conjunto de trabajo privado (lo mismo que muestra el Administrador de tareas). #>
    param($Catalog, $Programs)
    $os = Get-CimInstance Win32_OperatingSystem
    $totalMB = [math]::Round($os.TotalVisibleMemorySize / 1KB)
    $freeMB = [math]::Round($os.FreePhysicalMemory / 1KB)
    $private = @{}
    try { foreach ($p in (Get-CimInstance Win32_PerfRawData_PerfProc_Process -Property IDProcess, WorkingSetPrivate -ErrorAction Stop)) { if ($p.IDProcess) { $private[[int]$p.IDProcess] = [double]$p.WorkingSetPrivate } } } catch { }
    $procs = foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) {
        $bytes = $private[[int]$p.Id]; if (-not $bytes) { $bytes = [double]$p.WorkingSet64 }
        $path = $null; $product = $null
        try { $path = $p.Path } catch { }
        if ($path) { try { $product = $p.MainModule.FileVersionInfo.ProductName } catch { } }
        [pscustomobject]@{ Name = $p.ProcessName; Path = $path; Product = $(if ($product) { $product.Trim() } else { $null }); MB = $bytes / 1MB }
    }
    $procs = @($procs)
    $top = @($procs | Group-Object { if ($_.Product) { $_.Product } else { $_.Name } } | ForEach-Object {
            $mb = ($_.Group | Measure-Object MB -Sum).Sum
            [pscustomobject]@{ Programa = $_.Name; Procesos = $_.Count; RamMB = [math]::Round($mb); Ram = (Format-CfgSize $mb) }
        } | Sort-Object RamMB -Descending | Select-Object -First 20)
    $byItem = @{}
    if ($Catalog) {
        if (-not $Programs) { $Programs = @(Get-CfgInstalledPrograms) }
        foreach ($item in $Catalog) {
            $d = $item.detect
            if (-not $d) { continue }
            $dirs = New-Object System.Collections.Generic.List[string]
            $likes = New-Object System.Collections.Generic.List[string]
            if ($d.PSObject.Properties['displayName']) {
                foreach ($pat in @($d.displayName)) {
                    $likes.Add($pat)
                    foreach ($m in @($Programs | Where-Object { $_.DisplayName -like $pat })) {
                        if ($m.InstallLocation -and $m.InstallLocation.Trim('"').Length -gt 3) { $dirs.Add($m.InstallLocation.Trim('"').TrimEnd('\') + '\') }
                        elseif ($m.DisplayIcon) { $ic = ($m.DisplayIcon -split ',')[0].Trim('"'); if ($ic -match '\\') { $dirs.Add((Split-Path $ic) + '\') } }
                    }
                }
            }
            if ($d.PSObject.Properties['appx']) { foreach ($pat in @($d.appx)) { $dirs.Add("*\WindowsApps\$($pat)_*") } }
            if ($d.PSObject.Properties['path']) { foreach ($pat in @($d.path)) { $x = [Environment]::ExpandEnvironmentVariables($pat); $dirs.Add($(if ($x -match '\.exe$') { Split-Path $x } else { $x }).TrimEnd('\') + '\') } }
            # Directorios genéricos (Windows, Program Files...) darían falsos positivos
            $dirs = @($dirs | Where-Object { $_ -and $_ -notmatch '^[A-Za-z]:\\(Windows|Program Files( \(x86\))?|ProgramData|Users)?\\$' } | Select-Object -Unique)
            $match = @($procs | Where-Object {
                    $pr = $_
                    ($pr.Path -and @($dirs | Where-Object { if ($_ -like '*`**') { $pr.Path -like "$_*" } else { $pr.Path.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) } }).Count) -or
                    ($pr.Product -and @($likes | Where-Object { $pr.Product -like $_ }).Count)
                })
            if ($match.Count) { $byItem[$item.id] = [pscustomobject]@{ MB = [math]::Round(($match | Measure-Object MB -Sum).Sum); Procesos = $match.Count } }
        }
    }
    [pscustomobject]@{ TotalMB = $totalMB; FreeMB = $freeMB; UsedMB = $totalMB - $freeMB; Top = $top; ByItem = $byItem; At = (Get-Date -Format 'HH:mm') }
}
function New-CfgBatteryReport {
    $file = Join-Path (Get-CfgExportFolder) ('Bateria_{0}_{1}.html' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmmss'))
    & powercfg.exe /batteryreport /output $file | Out-Null
    $ok = Test-Path $file
    Write-CfgLog $(if ($ok) { "Informe de batería: $file" } else { 'No se pudo generar el informe de batería.' }) $(if ($ok) { 'OK' } else { 'ERROR' })
    return (New-CfgResult -Id 'battery' -Name 'Informe de batería' -Action 'Exportar' -Success $ok -Message $file)
}

Export-ModuleMember -Function *
