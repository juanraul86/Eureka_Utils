# Drivers.psm1 - Dispositivos y controladores, BIOS/UEFI, TPM, arranque seguro y preparación para juegos
# con antitrampas (TPM 2.0 + arranque seguro). El TPM y el arranque seguro se activan en la BIOS/UEFI:
# desde Windows se comprueba todo, se prepara lo necesario (GPT, BitLocker) y se reinicia en la BIOS.

function Get-CfgFirmwareType {
    <# 1 = BIOS heredada (Legacy/CSM), 2 = UEFI. #>
    try {
        if (-not ('CfgNative.Firmware' -as [type])) {
            Add-Type -Namespace CfgNative -Name Firmware -MemberDefinition '[DllImport("kernel32.dll")] public static extern bool GetFirmwareType(ref uint FirmwareType);' -ErrorAction Stop
        }
        [uint32]$t = 0
        if ([CfgNative.Firmware]::GetFirmwareType([ref]$t)) { return [int]$t }
    }
    catch { }
    if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State') { return 2 }
    return 1
}

# ---------------------------------------------------------------- dispositivos y controladores

function Get-CfgDevices {
    <# Todo el hardware con su controlador: clase, fabricante, versión, fecha, firma y estado. #>
    $status = @{}
    foreach ($e in (Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue)) { $status[$e.DeviceID] = $e.ConfigManagerErrorCode }
    $drivers = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | Where-Object { $_.DeviceName })
    $seen = @{}
    $list = foreach ($d in $drivers) {
        $seen[$d.DeviceID] = $true
        $code = $status[$d.DeviceID]
        [pscustomobject]@{
            Clase       = [string]$d.DeviceClass
            Dispositivo = $d.DeviceName
            Fabricante  = $d.Manufacturer
            Version     = $d.DriverVersion
            Fecha       = $(if ($d.DriverDate) { ([datetime]$d.DriverDate).ToString('yyyy-MM-dd') } else { '' })
            Firmado     = $(if ($d.IsSigned) { 'Sí' } else { 'No' })
            Estado      = $(if ($null -eq $code -or $code -eq 0) { 'OK' } elseif ($code -in 24, 45) { 'No conectado' } else { "Error $code" })
            Problema    = ($null -ne $code -and $code -notin 0, 24, 45)
        }
    }
    # Dispositivos sin controlador instalado (código 28)
    $missing = foreach ($e in (Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0 AND ConfigManagerErrorCode <> 24 AND ConfigManagerErrorCode <> 45' -ErrorAction SilentlyContinue)) {
        if ($seen[$e.DeviceID]) { continue }
        [pscustomobject]@{ Clase = [string]$e.PNPClass; Dispositivo = $(if ($e.Name) { $e.Name } else { $e.DeviceID }); Fabricante = $e.Manufacturer; Version = ''; Fecha = ''; Firmado = ''; Estado = "Error $($e.ConfigManagerErrorCode)"; Problema = $true }
    }
    return @(@($list) + @($missing) | Sort-Object @{ e = { -not $_.Problema } }, Clase, Dispositivo)
}

function Find-CfgDriverUpdates {
    <# Busca controladores y firmware (incluidas actualizaciones de BIOS/UEFI que publica el fabricante
       en Windows Update) pendientes para este equipo. #>
    Write-CfgLog 'Buscando controladores y firmware en Windows Update (puede tardar un par de minutos)...' STEP
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $result = $searcher.Search("IsInstalled=0 and Type='Driver' and IsHidden=0")
    }
    catch {
        Write-CfgLog "No se pudo consultar Windows Update: $($_.Exception.Message)" ERROR
        return @()
    }
    $out = foreach ($u in $result.Updates) {
        [pscustomobject]@{
            UpdateId   = $u.Identity.UpdateID
            Titulo     = $u.Title
            Clase      = [string]$u.DriverClass
            Fabricante = $u.DriverManufacturer
            Fecha      = $(if ($u.DriverVerDate) { ([datetime]$u.DriverVerDate).ToString('yyyy-MM-dd') } else { '' })
            Tamano     = Format-CfgSize ([double]$u.MaxDownloadSize / 1MB)
            Firmware   = ([string]$u.DriverClass -match 'Firmware')
        }
    }
    $out = @($out)
    $fw = @($out | Where-Object { $_.Firmware }).Count
    Write-CfgLog ('{0} controladores pendientes en Windows Update ({1} de firmware/BIOS).' -f $out.Count, $fw) $(if ($out.Count) { 'WARN' } else { 'OK' })
    return $out
}

function Install-CfgDriverUpdates {
    param([Parameter(Mandatory)][string[]]$UpdateIds)
    if (-not (Test-CfgAdmin)) { Write-CfgLog 'Instalar controladores requiere permisos de administrador.' ERROR; return }
    Write-CfgLog "Descargando e instalando $($UpdateIds.Count) controladores desde Windows Update..." STEP
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $result = $searcher.Search("IsInstalled=0 and Type='Driver' and IsHidden=0")
    $coll = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $result.Updates) {
        if ($UpdateIds -contains $u.Identity.UpdateID) {
            if ($u.DriverClass -match 'Firmware') { Write-CfgLog "   Incluye firmware/BIOS: $($u.Title). No apagues el equipo durante el reinicio." WARN }
            if (-not $u.EulaAccepted) { $u.AcceptEula() }
            [void]$coll.Add($u)
        }
    }
    if (-not $coll.Count) { Write-CfgLog 'Las actualizaciones elegidas ya no están pendientes.' WARN; return }
    $dl = $session.CreateUpdateDownloader(); $dl.Updates = $coll; [void]$dl.Download()
    $inst = $session.CreateUpdateInstaller(); $inst.Updates = $coll
    $res = $inst.Install()
    for ($i = 0; $i -lt $coll.Count; $i++) {
        $r = $res.GetUpdateResult($i)
        $ok = $r.ResultCode -eq 2
        Write-CfgLog ('   {0}: {1}' -f $coll.Item($i).Title, $(if ($ok) { 'instalado' } else { "código de resultado $($r.ResultCode)" })) $(if ($ok) { 'OK' } else { 'ERROR' })
        New-CfgResult -Id $coll.Item($i).Identity.UpdateID -Name $coll.Item($i).Title -Action 'Controlador' -Success $ok -Message "ResultCode $($r.ResultCode)"
    }
    if ($res.RebootRequired) { Write-CfgLog 'Reinicia el equipo para completar la instalación de los controladores.' WARN }
}

function Install-CfgDriverFolder {
    <# Instala controladores .inf de una carpeta (por ejemplo, los descargados del fabricante). Windows exige que estén firmados. #>
    param([Parameter(Mandatory)][string]$Path)
    Write-CfgLog "Instalando controladores .inf de $Path..." STEP
    & (Get-CfgSystemExe 'pnputil.exe') /add-driver (Join-Path $Path '*.inf') /subdirs /install 2>&1 | ForEach-Object { $l = "$_".Trim(); if ($l) { Write-CfgLog "   $l" } }
    $ok = $LASTEXITCODE -in @(0, 3010)
    Write-CfgLog $(if ($ok) { 'Controladores añadidos.' } else { "pnputil terminó con el código $LASTEXITCODE." }) $(if ($ok) { 'OK' } else { 'WARN' })
    return (New-CfgResult -Id 'pnputil' -Name 'Controladores desde carpeta' -Action 'Controlador' -Success $ok -Message "Código $LASTEXITCODE")
}

function Export-CfgDriverBackup {
    <# Copia de seguridad de los controladores de terceros: imprescindible antes de formatear. #>
    $dest = Join-Path (Get-CfgExportFolder) ('Controladores_{0}_{1}' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmmss'))
    Write-CfgLog "Exportando los controladores de terceros a $dest..." STEP
    try {
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        $n = @(Export-WindowsDriver -Online -Destination $dest -ErrorAction Stop).Count
        Write-CfgLog "$n controladores exportados. Para reinstalarlos: botón 'Instalar desde carpeta' o pnputil /add-driver <carpeta>\*.inf /subdirs /install." OK
        return (New-CfgResult -Id 'drvbackup' -Name 'Copia de controladores' -Action 'Exportar' -Success $true -Message $dest)
    }
    catch {
        Write-CfgLog "No se pudo exportar (requiere administrador): $($_.Exception.Message)" ERROR
        return (New-CfgResult -Id 'drvbackup' -Name 'Copia de controladores' -Action 'Exportar' -Success $false -Message $_.Exception.Message)
    }
}

# ---------------------------------------------------------------- BIOS / UEFI

$script:SupportPages = [ordered]@{
    'MSI'      = 'https://www.msi.com/support'
    'ASUS'     = 'https://www.asus.com/support/download-center/'
    'Gigabyte' = 'https://www.gigabyte.com/Support'
    'ASRock'   = 'https://www.asrock.com/support/index.asp'
    'Dell'     = 'https://www.dell.com/support/home'
    'HP'       = 'https://support.hp.com/drivers'
    'Lenovo'   = 'https://pcsupport.lenovo.com'
    'Acer'     = 'https://www.acer.com/support'
    'Microsoft' = 'https://support.microsoft.com/surface/download-drivers-and-firmware-for-surface-09bb2e09-2a4b-cb69-0951-078a7739e120'
    'Intel'    = 'https://www.intel.com/content/www/us/en/support.html'
}

function Get-CfgVendorKey {
    param([string]$Text)
    switch -Regex ($Text) {
        'Micro-Star|MSI' { return 'MSI' } 'ASUS' { return 'ASUS' } 'Gigabyte|GIGA-BYTE' { return 'Gigabyte' } 'ASRock' { return 'ASRock' }
        'Dell' { return 'Dell' } 'HP|Hewlett' { return 'HP' } 'Lenovo' { return 'Lenovo' } 'Acer' { return 'Acer' } 'Microsoft' { return 'Microsoft' } 'Intel' { return 'Intel' }
    }
    return $null
}

function Get-CfgFirmwareInfo {
    $cs = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $board = Get-CimInstance Win32_BaseBoard
    $enc = Get-CimInstance Win32_SystemEnclosure | Select-Object -First 1
    $laptop = @($enc.ChassisTypes | Where-Object { $_ -in 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32 }).Count -gt 0
    # En PC de marca y portátiles la BIOS la publica el fabricante del equipo; en sobremesa montados, el de la placa base
    $vendorText = if ($laptop -or $cs.Manufacturer -match 'Dell|HP|Hewlett|Lenovo|Acer|Microsoft') { $cs.Manufacturer } else { $board.Manufacturer }
    $vendor = Get-CfgVendorKey $vendorText
    $model = if ($vendorText -eq $board.Manufacturer) { $board.Product } else { $cs.Model }
    $date = $bios.ReleaseDate
    $age = if ($date) { [int]((Get-Date) - $date).TotalDays } else { $null }
    $fw = Get-CfgFirmwareType
    $sb = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction SilentlyContinue).UEFISecureBootEnabled
    $sysDisk = Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.IsSystem } | Select-Object -First 1
    [pscustomobject]@{
        Vendor      = $vendor
        VendorText  = $vendorText
        Model       = $model
        BiosVendor  = $bios.Manufacturer
        BiosVersion = $bios.SMBIOSBIOSVersion
        BiosDate    = $(if ($date) { $date.ToString('yyyy-MM-dd') } else { '' })
        BiosAgeDays = $age
        Smbios      = '{0}.{1}' -f $bios.SMBIOSMajorVersion, $bios.SMBIOSMinorVersion
        Firmware    = $(if ($fw -eq 2) { 'UEFI' } else { 'BIOS heredada (Legacy/CSM)' })
        IsUefi      = ($fw -eq 2)
        SecureBoot  = ($sb -eq 1)
        DiskStyle   = $(if ($sysDisk) { [string]$sysDisk.PartitionStyle } else { '' })
        IsLaptop    = $laptop
        SupportUrl  = $(if ($vendor) { $script:SupportPages[$vendor] } else { $null })
    }
}

function Get-CfgFirmwareDisplay {
    param([Parameter(Mandatory)]$Fw)
    [ordered]@{
        'Fabricante (soporte)' = $(if ($Fw.VendorText) { "$($Fw.VendorText) · $($Fw.Model)" } else { '—' })
        'BIOS'                 = '{0} {1}' -f $Fw.BiosVendor, $Fw.BiosVersion
        'Fecha de la BIOS'     = $(if ($Fw.BiosDate) { '{0} (hace {1} meses)' -f $Fw.BiosDate, [int]($Fw.BiosAgeDays / 30) } else { '—' })
        'Modo de firmware'     = $Fw.Firmware
        'Arranque seguro'      = $(if ($Fw.SecureBoot) { 'Activado' } elseif ($Fw.IsUefi) { 'Desactivado' } else { 'No disponible (modo BIOS heredada)' })
        'Disco del sistema'    = $(if ($Fw.DiskStyle) { $Fw.DiskStyle } else { '—' })
        'SMBIOS'               = $Fw.Smbios
    }
}

function Test-CfgGamingReadiness {
    <# Requisitos de los antitrampas a nivel de kernel (Vanguard, Javelin, Ricochet...) en Windows 11:
       UEFI + disco GPT + arranque seguro + TPM 2.0. La virtualización y VBS son informativas. #>
    param($Fw)
    if (-not $Fw) { $Fw = Get-CfgFirmwareInfo }
    $out = New-Object System.Collections.Generic.List[object]
    $add = { param($c, $r, $d) $out.Add([pscustomobject]@{ Comprobacion = $c; Resultado = $r; Detalle = $d }) }
    & $add 'Firmware UEFI' $(if ($Fw.IsUefi) { 'OK' } else { 'FALLO' }) $(if ($Fw.IsUefi) { 'El equipo arranca en modo UEFI' } else { 'Arranca en modo BIOS heredada: convierte el disco a GPT y cambia a UEFI (desactiva CSM) en la BIOS' })
    & $add 'Disco del sistema GPT' $(if ($Fw.DiskStyle -eq 'GPT') { 'OK' } elseif ($Fw.DiskStyle) { 'FALLO' } else { 'AVISO' }) $(if ($Fw.DiskStyle -eq 'GPT') { 'GPT (necesario para UEFI)' } elseif ($Fw.DiskStyle) { "$($Fw.DiskStyle): convierte a GPT con MBR2GPT antes de pasar a UEFI" } else { 'No se pudo comprobar' })
    & $add 'Arranque seguro' $(if ($Fw.SecureBoot) { 'OK' } else { 'FALLO' }) $(if ($Fw.SecureBoot) { 'Activado' } else { 'Desactivado: actívalo en la BIOS (requiere UEFI)' })
    try {
        $tpm = Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop
        if ($tpm) {
            $v = ($tpm.SpecVersion -split ',')[0].Trim()
            $ok = ([double]::Parse($v, [Globalization.CultureInfo]::InvariantCulture) -ge 2) -and $tpm.IsEnabled_InitialValue -and $tpm.IsActivated_InitialValue
            & $add 'TPM 2.0' $(if ($ok) { 'OK' } else { 'FALLO' }) ('Versión {0} · habilitado: {1} · activado: {2}' -f $v, $tpm.IsEnabled_InitialValue, $tpm.IsActivated_InitialValue)
        }
        else { & $add 'TPM 2.0' 'FALLO' 'No hay TPM visible: activa Intel PTT o AMD fTPM en la BIOS' }
    }
    catch { & $add 'TPM 2.0' 'AVISO' 'Ejecuta como administrador para comprobarlo' }
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $hyper = (Get-CimInstance Win32_ComputerSystem).HypervisorPresent
    & $add 'Virtualización (VT-x/AMD-V)' $(if ($cpu.VirtualizationFirmwareEnabled -or $hyper) { 'OK' } else { 'AVISO' }) $(if ($hyper) { 'Activa (hay un hipervisor en marcha)' } elseif ($cpu.VirtualizationFirmwareEnabled) { 'Activada en la BIOS' } else { 'Desactivada: algunos antitrampas y Windows Sandbox/WSL la necesitan' })
    try {
        $dg = Get-CimInstance -Namespace 'root/Microsoft/Windows/DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop
        & $add 'Seguridad basada en virtualización' 'INFO' $(switch ([int]$dg.VirtualizationBasedSecurityStatus) { 2 { 'En ejecución (algunos antitrampas la exigen; puede restar algo de rendimiento)' } 1 { 'Habilitada pero no en ejecución' } default { 'Desactivada' } })
    }
    catch { }
    $bl = $null
    try { $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop } catch { }
    if ($bl) { & $add 'BitLocker' 'INFO' $(if ($bl.ProtectionStatus -eq 'On') { 'Activado: suspéndelo antes de cambiar la BIOS o te pedirá la clave de recuperación' } else { 'Sin protección activa' }) }
    return $out.ToArray()
}

$script:FirmwareGuides = @{
    'MSI'      = 'MSI (Click BIOS 5): pulsa Supr al arrancar > modo avanzado (F7). TPM: Settings > Security > Trusted Computing > Security Device Support = Enable y AMD fTPM / Intel PTT. UEFI: Settings > Advanced > Windows OS Configuration > BIOS UEFI/CSM Mode = UEFI. Arranque seguro: misma sección > Secure Boot = Enabled (modo Standard). Guarda con F10.'
    'ASUS'     = 'ASUS (UEFI BIOS): pulsa Supr o F2 > modo avanzado (F7). TPM: Advanced > PCH-FW Configuration > PTT = Enable (Intel) o Advanced > AMD fTPM Configuration = Firmware TPM. UEFI: Boot > CSM = Disabled. Arranque seguro: Boot > Secure Boot > OS Type = Windows UEFI mode. Guarda con F10.'
    'Gigabyte' = 'Gigabyte (AORUS): pulsa Supr > modo avanzado (F2). TPM: Settings > Miscellaneous > Intel Platform Trust Technology (PTT) o AMD CPU fTPM = Enabled. UEFI: Boot > CSM Support = Disabled. Arranque seguro: Boot > Secure Boot = Enabled. Guarda con F10.'
    'ASRock'   = 'ASRock: pulsa F2 o Supr. TPM: Security > Intel PTT o AMD fTPM switch = Enabled. UEFI: Boot > CSM = Disabled. Arranque seguro: Security > Secure Boot = Enabled (instala las claves por defecto si lo pide). Guarda con F10.'
    'Dell'     = 'Dell: pulsa F2 al arrancar. TPM: Security > TPM 2.0 Security = On. UEFI: Boot Configuration > Boot Mode = UEFI (desactiva Legacy Option ROMs). Arranque seguro: Boot Configuration > Secure Boot = On. Aplica y sal.'
    'HP'       = 'HP: pulsa Esc y luego F10. TPM: Security > TPM Embedded Security > TPM State = Enabled. UEFI: Advanced > Boot Options > Legacy Support = Disabled. Arranque seguro: Advanced > Secure Boot Configuration = Enable. Guarda con F10.'
    'Lenovo'   = 'Lenovo: pulsa F1 (ThinkPad) o F2 (IdeaPad/Legion). TPM: Security > Security Chip = Enabled. UEFI: Startup > UEFI/Legacy Boot = UEFI Only (CSM desactivado). Arranque seguro: Security > Secure Boot = Enabled. Guarda con F10.'
    'Acer'     = 'Acer: pulsa F2. TPM: Security > TPM / PTT = Enabled (a veces hay que fijar antes una contraseña de supervisor). UEFI: Boot > Boot Mode = UEFI. Arranque seguro: Boot > Secure Boot = Enabled. Guarda con F10.'
}

function Get-CfgFirmwareGuide {
    param($Fw, [switch]$AsParts)
    if (-not $Fw) { $Fw = Get-CfgFirmwareInfo }
    $g = if ($Fw.Vendor -and $script:FirmwareGuides[$Fw.Vendor]) { $script:FirmwareGuides[$Fw.Vendor] } else { 'Genérico: entra en la BIOS (Supr, F2, F10 o F1 al arrancar, según el fabricante). Activa el TPM (Intel PTT / AMD fTPM / Security Chip), pon el arranque en UEFI (CSM o Legacy desactivado) y activa Secure Boot. Guarda y sal.' }
    $pre = if (-not $Fw.IsUefi) { 'IMPORTANTE: el equipo está en modo BIOS heredada. Primero convierte el disco a GPT (botón MBR2GPT) y solo después cambia la BIOS a UEFI; al revés, Windows no arrancará. ' } else { '' }
    $parts = @($pre.Trim(), $g, 'Los nombres exactos cambian según el modelo y la versión de la BIOS.') | Where-Object { $_ }
    if ($AsParts) { return $parts }
    return ($parts -join ' ')
}

function Get-CfgSupportPages { $script:SupportPages }

function Suspend-CfgBitLockerForFirmware {
    <# Suspende BitLocker un reinicio para cambiar la BIOS o actualizarla sin que pida la clave de recuperación. #>
    try {
        $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
        if ($bl.ProtectionStatus -ne 'On') { Write-CfgLog 'BitLocker no está protegiendo la unidad del sistema: no hace falta suspenderlo.' OK; return (New-CfgResult -Id 'bitlocker' -Name 'BitLocker' -Action 'Firmware' -Success $true -Message 'No necesario') }
        Suspend-BitLocker -MountPoint $env:SystemDrive -RebootCount 1 -ErrorAction Stop | Out-Null
        Write-CfgLog 'BitLocker suspendido durante el próximo reinicio: ya puedes actualizar o cambiar la BIOS. Se reactiva solo después.' OK
        return (New-CfgResult -Id 'bitlocker' -Name 'BitLocker' -Action 'Firmware' -Success $true -Message 'Suspendido 1 reinicio')
    }
    catch {
        Write-CfgLog "BitLocker no disponible o sin permisos: $($_.Exception.Message)" WARN
        return (New-CfgResult -Id 'bitlocker' -Name 'BitLocker' -Action 'Firmware' -Success $true -Message 'No aplicable')
    }
}

function Invoke-CfgMbr2Gpt {
    <# Valida (y opcionalmente convierte) el disco del sistema de MBR a GPT sin perder datos (herramienta oficial MBR2GPT). #>
    param([switch]$Convert)
    $disk = Get-Disk | Where-Object { $_.IsSystem } | Select-Object -First 1
    if (-not $disk) { Write-CfgLog 'No se encontró el disco del sistema.' ERROR; return (New-CfgResult -Id 'mbr2gpt' -Name 'MBR2GPT' -Action 'Firmware' -Success $false -Message 'Sin disco') }
    if ($disk.PartitionStyle -eq 'GPT') { Write-CfgLog 'El disco del sistema ya es GPT: no hace falta convertirlo.' OK; return (New-CfgResult -Id 'mbr2gpt' -Name 'MBR2GPT' -Action 'Firmware' -Success $true -Message 'Ya es GPT') }
    $exe = Get-CfgSystemExe 'mbr2gpt.exe'
    $mode = if ($Convert) { '/convert' } else { '/validate' }
    Write-CfgLog "MBR2GPT $mode del disco $($disk.Number)..." STEP
    & $exe $mode "/disk:$($disk.Number)" /allowFullOS 2>&1 | ForEach-Object { $l = "$_".Trim(); if ($l) { Write-CfgLog "   $l" } }
    $ok = ($LASTEXITCODE -eq 0)
    if ($Convert -and $ok) { Write-CfgLog 'Disco convertido a GPT. AHORA entra en la BIOS y cambia a modo UEFI (desactiva CSM/Legacy) antes de arrancar Windows, o no arrancará.' WARN }
    elseif (-not $ok) { Write-CfgLog "MBR2GPT terminó con el código ${LASTEXITCODE}: el disco no cumple los requisitos (máximo 3 particiones, espacio libre...)." ERROR }
    return (New-CfgResult -Id 'mbr2gpt' -Name 'MBR2GPT' -Action 'Firmware' -Success $ok -Message "Código $LASTEXITCODE")
}

function Restart-CfgToFirmware {
    if ((Get-CfgFirmwareType) -ne 2) { Write-CfgLog 'Reiniciar directamente en la BIOS solo es posible en modo UEFI. Pulsa la tecla del fabricante (Supr, F2, F10...) al encender.' WARN; return }
    Write-CfgLog 'Reiniciando en la configuración de la BIOS/UEFI en 15 segundos (cancelar: shutdown /a)...' WARN
    & (Get-CfgSystemExe 'shutdown.exe') /r /fw /t 15 /c 'Eureka_Utils: reinicio en la configuración de la BIOS/UEFI' | Out-Null
}

Export-ModuleMember -Function *
