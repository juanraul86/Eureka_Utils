# Media.psm1 - USB de instalación de Windows 11+ con respuesta automática (autounattend.xml)
# y continuación automática de Eureka_Utils en el primer inicio de sesión.

$script:Regions = @(
    [pscustomobject]@{ Id = 'es-ES'; Name = 'Español (España)';        Input = '0c0a:0000040a'; TimeZone = 'Romance Standard Time' }
    [pscustomobject]@{ Id = 'ca-ES'; Name = 'Català (Espanya)';        Input = '0403:0000040a'; TimeZone = 'Romance Standard Time' }
    [pscustomobject]@{ Id = 'es-MX'; Name = 'Español (México)';        Input = '080a:0000080a'; TimeZone = 'Central Standard Time (Mexico)' }
    [pscustomobject]@{ Id = 'es-AR'; Name = 'Español (Argentina)';     Input = '2c0a:0000080a'; TimeZone = 'Argentina Standard Time' }
    [pscustomobject]@{ Id = 'es-CO'; Name = 'Español (Colombia)';      Input = '240a:0000080a'; TimeZone = 'SA Pacific Standard Time' }
    [pscustomobject]@{ Id = 'es-CL'; Name = 'Español (Chile)';         Input = '340a:0000080a'; TimeZone = 'Pacific SA Standard Time' }
    [pscustomobject]@{ Id = 'es-PE'; Name = 'Español (Perú)';          Input = '280a:0000080a'; TimeZone = 'SA Pacific Standard Time' }
    [pscustomobject]@{ Id = 'en-US'; Name = 'English (United States)'; Input = '0409:00000409'; TimeZone = 'Eastern Standard Time' }
    [pscustomobject]@{ Id = 'en-GB'; Name = 'English (United Kingdom)'; Input = '0809:00000809'; TimeZone = 'GMT Standard Time' }
    [pscustomobject]@{ Id = 'pt-PT'; Name = 'Português (Portugal)';    Input = '0816:00000816'; TimeZone = 'GMT Standard Time' }
    [pscustomobject]@{ Id = 'fr-FR'; Name = 'Français (France)';       Input = '040c:0000040c'; TimeZone = 'Romance Standard Time' }
    [pscustomobject]@{ Id = 'de-DE'; Name = 'Deutsch (Deutschland)';   Input = '0407:00000407'; TimeZone = 'W. Europe Standard Time' }
)

$script:TimeZones = @(
    [pscustomobject]@{ Id = 'Romance Standard Time';          Name = '(UTC+01:00) Madrid, París, Bruselas' }
    [pscustomobject]@{ Id = 'GMT Standard Time';              Name = '(UTC+00:00) Canarias, Lisboa, Londres' }
    [pscustomobject]@{ Id = 'W. Europe Standard Time';        Name = '(UTC+01:00) Berlín, Roma, Ámsterdam' }
    [pscustomobject]@{ Id = 'Central Standard Time (Mexico)'; Name = '(UTC-06:00) Ciudad de México' }
    [pscustomobject]@{ Id = 'SA Pacific Standard Time';       Name = '(UTC-05:00) Bogotá, Lima, Quito' }
    [pscustomobject]@{ Id = 'Venezuela Standard Time';        Name = '(UTC-04:00) Caracas' }
    [pscustomobject]@{ Id = 'Pacific SA Standard Time';       Name = '(UTC-04:00) Santiago' }
    [pscustomobject]@{ Id = 'Argentina Standard Time';        Name = '(UTC-03:00) Buenos Aires' }
    [pscustomobject]@{ Id = 'Eastern Standard Time';          Name = '(UTC-05:00) Nueva York (EE. UU. Este)' }
    [pscustomobject]@{ Id = 'Pacific Standard Time';          Name = '(UTC-08:00) Los Ángeles (EE. UU. Pacífico)' }
    [pscustomobject]@{ Id = 'UTC';                            Name = '(UTC) Hora universal coordinada' }
)

function Get-CfgInstallRegions { return $script:Regions }
function Get-CfgTimeZones { return $script:TimeZones }

function Get-CfgUsbDisks {
    @(Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.BusType -eq 'USB' -and -not $_.IsBoot -and -not $_.IsSystem } | ForEach-Object {
            $gb = [math]::Round($_.Size / 1GB, 1)
            [pscustomobject]@{ Number = $_.Number; Name = $_.FriendlyName; SizeGB = $gb; Label = "Disco $($_.Number): $($_.FriendlyName) · $gb GB" }
        })
}

function Get-CfgIsoInfo {
    param([Parameter(Mandatory)][string]$IsoPath)
    if (-not (Test-Path $IsoPath)) { throw "No existe $IsoPath" }
    Write-CfgLog "Leyendo la ISO $IsoPath..." STEP
    $img = Mount-DiskImage -ImagePath $IsoPath -PassThru -ErrorAction Stop
    try {
        Start-Sleep -Seconds 1
        $drive = '{0}:' -f ($img | Get-Volume).DriveLetter
        $wim = @("$drive\sources\install.wim", "$drive\sources\install.esd") | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $wim) { throw 'La ISO no contiene sources\install.wim ni install.esd: no es un medio de instalación de Windows.' }
        $images = @(Get-WindowsImage -ImagePath $wim -ErrorAction Stop)
        $d = Get-WindowsImage -ImagePath $wim -Index $images[0].ImageIndex -ErrorAction Stop
        $build = [int](([string]$d.Version).Split('.')[2])
        $a = "$($d.Architecture)"
        $arch = if ($a -match '^(9|x64|amd64)$') { 'amd64' } elseif ($a -match '^(12|arm64)$') { 'arm64' } else { 'x86' }
        $langs = @($d.Languages | ForEach-Object { ($_ -replace '\s*\(.*\)$', '').Trim() })
        $default = $langs[0]
        if ($null -ne $d.DefaultLanguageIndex -and $d.DefaultLanguageIndex -lt $langs.Count) { $default = $langs[$d.DefaultLanguageIndex] }
        $info = [pscustomobject]@{
            IsoPath     = $IsoPath
            ImageFile   = Split-Path $wim -Leaf
            ImageSizeMB = [math]::Round((Get-Item $wim).Length / 1MB)
            Version     = [string]$d.Version
            Build       = $build
            Arch        = $arch
            Languages   = $langs
            Language    = $default
            IsWin11     = ($build -ge 22000)
            Editions    = @($images | ForEach-Object { [pscustomobject]@{ Index = $_.ImageIndex; Name = $_.ImageName } })
        }
        Write-CfgLog ("ISO: Windows compilación {0} ({1}), idioma {2}, {3} ediciones, {4} de {5} MB." -f $build, $arch, $default, $info.Editions.Count, $info.ImageFile, $info.ImageSizeMB) $(if ($info.IsWin11) { 'OK' } else { 'ERROR' })
        if (-not $info.IsWin11) { Write-CfgLog 'Esta ISO es anterior a Windows 11 (compilación < 22000). Eureka_Utils solo prepara Windows 11 o posterior.' ERROR }
        return $info
    }
    finally { Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null }
}

function ConvertTo-CfgUnattendPassword {
    <# Formato de contraseña "ofuscada" de los archivos de respuesta (NO es cifrado). #>
    param([string]$Password)
    return [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Password + 'Password'))
}

function New-CfgAutounattendXml {
    <# Settings: Arch, UILanguage, Region, InputLocale, TimeZone, EditionName, ProductKey, ComputerName,
                 DiskMode (manual|wipe0), AccountMode (local|work), LocalUser, LocalFullName, LocalPassword, AutoLogon #>
    param([Parameter(Mandatory)][hashtable]$S)
    $e = { param($v) [Security.SecurityElement]::Escape([string]$v) }
    $arch = $S.Arch
    $comp = { param($n) "name=`"$n`" processorArchitecture=`"$arch`" publicKeyToken=`"31bf3856ad364e35`" language=`"neutral`" versionScope=`"nonSxS`"" }

    $disk = ''; $installTo = ''
    if ($S.DiskMode -eq 'wipe0') {
        $disk = @'
      <DiskConfiguration>
        <WillShowUI>OnError</WillShowUI>
        <Disk wcm:action="add">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <CreatePartition wcm:action="add"><Order>1</Order><Type>EFI</Type><Size>300</Size></CreatePartition>
            <CreatePartition wcm:action="add"><Order>2</Order><Type>MSR</Type><Size>16</Size></CreatePartition>
            <CreatePartition wcm:action="add"><Order>3</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add"><Order>1</Order><PartitionID>1</PartitionID><Label>System</Label><Format>FAT32</Format></ModifyPartition>
            <ModifyPartition wcm:action="add"><Order>2</Order><PartitionID>2</PartitionID></ModifyPartition>
            <ModifyPartition wcm:action="add"><Order>3</Order><PartitionID>3</PartitionID><Label>Windows</Label><Letter>C</Letter><Format>NTFS</Format></ModifyPartition>
          </ModifyPartitions>
        </Disk>
      </DiskConfiguration>
'@
        $installTo = '<InstallTo><DiskID>0</DiskID><PartitionID>3</PartitionID></InstallTo>'
    }
    $key = ''
    if ($S.ProductKey) { $key = "<ProductKey><Key>$(& $e $S.ProductKey)</Key><WillShowUI>OnError</WillShowUI></ProductKey>" }

    $accounts = ''; $autologon = ''
    $hideOnline = 'false'
    if ($S.AccountMode -eq 'local') {
        $hideOnline = 'true'
        $pw = ConvertTo-CfgUnattendPassword $S.LocalPassword
        $accounts = @"
      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add">
            <Description>Creada por el Eureka_Utils</Description>
            <DisplayName>$(& $e $(if ($S.LocalFullName) { $S.LocalFullName } else { $S.LocalUser }))</DisplayName>
            <Group>Administrators</Group>
            <Name>$(& $e $S.LocalUser)</Name>
            <Password><PlainText>false</PlainText><Value>$pw</Value></Password>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>
"@
        if ($S.AutoLogon) {
            $autologon = @"
      <AutoLogon>
        <Enabled>true</Enabled>
        <LogonCount>1</LogonCount>
        <Username>$(& $e $S.LocalUser)</Username>
        <Password><PlainText>false</PlainText><Value>$pw</Value></Password>
      </AutoLogon>
"@
        }
    }
    $name = if ($S.ComputerName) { & $e $S.ComputerName } else { '*' }
    $sys = '%SystemRoot%\System32'
    # Primero solo la carpeta (sin /T: (OI)(CI) en archivos falla y los deja sin permisos) y después
    # todo lo de dentro vuelve a heredar de ella.
    $aclCmd  = $sys + '\cmd.exe /c if exist C:\Eureka_Utils (' + $sys + '\icacls.exe C:\Eureka_Utils /inheritance:r /grant:r *S-1-5-32-544:(OI)(CI)F *S-1-5-18:(OI)(CI)F *S-1-5-32-545:(OI)(CI)RX /C /Q & ' + $sys + '\icacls.exe C:\Eureka_Utils\* /reset /T /C /Q)'
    $copyCmd = $sys + '\cmd.exe /c if not exist C:\Eureka_Utils\Eureka_Utils.ps1 for %d in (D E F G H I J K L M N O P Q R S T U V W X Y Z) do if exist "%d:\sources\$OEM$\$1\Eureka_Utils\Eureka_Utils.ps1" ' + $sys + '\robocopy.exe "%d:\sources\$OEM$\$1\Eureka_Utils" C:\Eureka_Utils /E /NFL /NDL /NJH /NJS /NP'
    $runCmd  = $sys + '\cmd.exe /c start "" ' + $sys + '\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File C:\Eureka_Utils\Eureka_Utils.ps1 -PostInstalacion'

    return @"
<?xml version="1.0" encoding="utf-8"?>
<!-- Generado por el Eureka_Utils el $(Get-Date -Format 'yyyy-MM-dd HH:mm') -->
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
  <settings pass="windowsPE">
    <component $(& $comp 'Microsoft-Windows-International-Core-WinPE')>
      <InputLocale>$($S.InputLocale)</InputLocale>
      <SetupUILanguage><UILanguage>$($S.UILanguage)</UILanguage></SetupUILanguage>
      <SystemLocale>$($S.Region)</SystemLocale>
      <UILanguage>$($S.UILanguage)</UILanguage>
      <UserLocale>$($S.Region)</UserLocale>
    </component>
    <component $(& $comp 'Microsoft-Windows-Setup')>
$disk
      <ImageInstall>
        <OSImage>
          <InstallFrom><MetaData wcm:action="add"><Key>/IMAGE/NAME</Key><Value>$(& $e $S.EditionName)</Value></MetaData></InstallFrom>
          $installTo
        </OSImage>
      </ImageInstall>
      <UserData>
        <AcceptEula>true</AcceptEula>
        $key
      </UserData>
    </component>
  </settings>
  <settings pass="specialize">
    <component $(& $comp 'Microsoft-Windows-Shell-Setup')>
      <ComputerName>$name</ComputerName>
      <TimeZone>$(& $e $S.TimeZone)</TimeZone>
    </component>
    <component $(& $comp 'Microsoft-Windows-Deployment')>
      <RunSynchronous>
        <RunSynchronousCommand wcm:action="add">
          <Order>1</Order>
          <Description>Proteger C:\Eureka_Utils: solo administradores y SYSTEM pueden modificarla</Description>
          <Path>$(& $e $aclCmd)</Path>
        </RunSynchronousCommand>
      </RunSynchronous>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component $(& $comp 'Microsoft-Windows-International-Core')>
      <InputLocale>$($S.InputLocale)</InputLocale>
      <SystemLocale>$($S.Region)</SystemLocale>
      <UILanguage>$($S.UILanguage)</UILanguage>
      <UserLocale>$($S.Region)</UserLocale>
    </component>
    <component $(& $comp 'Microsoft-Windows-Shell-Setup')>
$autologon
      <FirstLogonCommands>
        <SynchronousCommand wcm:action="add">
          <Order>1</Order>
          <Description>Copiar Eureka_Utils desde el USB si hace falta</Description>
          <CommandLine>$(& $e $copyCmd)</CommandLine>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>2</Order>
          <Description>Continuar la configuración con Eureka_Utils</Description>
          <CommandLine>$(& $e $runCmd)</CommandLine>
        </SynchronousCommand>
      </FirstLogonCommands>
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>$hideOnline</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>false</HideWirelessSetupInOOBE>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
$accounts
    </component>
  </settings>
</unattend>
"@
}

function Test-CfgInstallSettings {
    param([Parameter(Mandatory)][hashtable]$S)
    $err = @()
    if (-not $S.EditionName) { $err += 'Elige la edición de Windows.' }
    if ($S.ComputerName -and -not (Test-CfgComputerName $S.ComputerName)) { $err += 'El nombre del equipo no es válido (máx. 15 caracteres: letras, números y guiones).' }
    if ($S.AccountMode -eq 'local') {
        if ($S.LocalUser -notmatch '^[^\\/\[\]:;|=,+*?<>"@]{1,20}$') { $err += 'Indica un nombre de usuario local válido (máx. 20 caracteres).' }
        if ($S.LocalUser -in @('Administrator', 'Administrador', 'Guest', 'Invitado', 'DefaultAccount')) { $err += 'Ese nombre de usuario está reservado por Windows.' }
        if (-not $S.LocalPassword -or $S.LocalPassword.Length -lt 4) { $err += 'La contraseña local debe tener al menos 4 caracteres.' }
    }
    if ($S.ProductKey -and $S.ProductKey -notmatch '^([A-Z0-9]{5}-){4}[A-Z0-9]{5}$') { $err += 'La clave de producto debe tener el formato XXXXX-XXXXX-XXXXX-XXXXX-XXXXX.' }
    return $err
}

function Save-CfgAutounattend {
    param([Parameter(Mandatory)][hashtable]$Settings, [string]$Path)
    if (-not $Path) { $Path = Join-Path (Get-CfgExportFolder) 'autounattend.xml' }
    $xml = New-CfgAutounattendXml -S $Settings
    [void][xml]$xml   # valida que el XML esté bien formado
    [IO.File]::WriteAllText($Path, $xml, (New-Object Text.UTF8Encoding $false))
    Write-CfgLog "autounattend.xml guardado en $Path. Cópialo a la raíz de cualquier USB de instalación de Windows 11 (Rufus, Ventoy, Media Creation Tool)." OK
    return (New-CfgResult -Id 'unattend' -Name 'autounattend.xml' -Action 'Exportar' -Success $true -Message $Path)
}

function Copy-CfgToolkit {
    <# Copia Eureka_Utils (sin registros ni exportaciones) a un destino. #>
    param([Parameter(Mandatory)][string]$Destination, [hashtable]$PostInstall)
    $root = Get-CfgRoot
    & (Get-CfgSystemExe 'robocopy.exe') $root $Destination /E /XD (Join-Path $root 'Logs') (Join-Path $root 'Exports') (Join-Path $root 'Dist') (Join-Path $root 'Build\obj') (Join-Path $root 'Docs') /XF '*.log' 'postinstall*.json' 'preferencias.json' /NFL /NDL /NJH /NJS /NP /R:1 /W:1 | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy falló copiando Eureka_Utils (código $LASTEXITCODE)" }
    if ($PostInstall) {
        $cfgDir = Join-Path $Destination 'Config'
        if (-not (Test-Path $cfgDir)) { New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null }
        $PostInstall | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $cfgDir 'postinstall.json') -Encoding UTF8
    }
}

function New-CfgInstallUsb {
    param(
        [Parameter(Mandatory)][int]$DiskNumber,
        [Parameter(Mandatory)][string]$IsoPath,
        [Parameter(Mandatory)][hashtable]$Settings,
        [int]$EditionIndex = 1,
        [hashtable]$PostInstall
    )
    $disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
    if ($disk.BusType -ne 'USB' -or $disk.IsBoot -or $disk.IsSystem) { throw "El disco $DiskNumber no es una memoria USB extraíble segura de borrar." }
    if ($disk.Size -lt 7GB) { throw 'La memoria USB debe tener al menos 8 GB.' }
    $problems = Test-CfgInstallSettings -S $Settings
    if ($problems) { throw ($problems -join ' ') }
    $xml = New-CfgAutounattendXml -S $Settings
    [void][xml]$xml

    Write-CfgLog "Borrando y preparando $($disk.FriendlyName) (disco $DiskNumber)..." STEP
    if ($disk.PartitionStyle -ne 'RAW') { Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop }
    Initialize-Disk -Number $DiskNumber -PartitionStyle MBR -ErrorAction Stop
    # FAT32 arranca en cualquier UEFI; Windows solo formatea FAT32 hasta 32 GB
    $size = [math]::Min($disk.Size - 4MB, 32GB - 4MB)
    $part = New-Partition -DiskNumber $DiskNumber -Size $size -IsActive -AssignDriveLetter -ErrorAction Stop
    Start-Sleep -Seconds 3
    Format-Volume -Partition $part -FileSystem FAT32 -NewFileSystemLabel 'EUREKA' -Confirm:$false -Force -ErrorAction Stop | Out-Null
    $letter = (Get-Partition -DiskNumber $DiskNumber -PartitionNumber $part.PartitionNumber).DriveLetter
    if (-not $letter) { throw 'La partición del USB no recibió letra de unidad.' }
    $dst = "${letter}:"
    Write-CfgLog "USB formateado en FAT32 como $dst." OK

    $img = Mount-DiskImage -ImagePath $IsoPath -PassThru -ErrorAction Stop
    $tmpWim = $null
    try {
        Start-Sleep -Seconds 1
        $src = '{0}:' -f ($img | Get-Volume).DriveLetter
        Write-CfgLog 'Copiando archivos de instalación (varios minutos según la velocidad del USB)...' STEP
        & (Get-CfgSystemExe 'robocopy.exe') "$src\" "$dst\" /E /XF install.wim install.esd /NFL /NDL /NJH /NJS /NP /R:1 /W:1 | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "Error copiando la ISO (robocopy $LASTEXITCODE)" }

        $wim = @("$src\sources\install.wim", "$src\sources\install.esd") | Where-Object { Test-Path $_ } | Select-Object -First 1
        $limit = 4GB - 1
        $len = (Get-Item $wim).Length
        if ($len -le $limit) {
            Write-CfgLog "Copiando $(Split-Path $wim -Leaf) ($([math]::Round($len / 1MB)) MB)..."
            Copy-Item -Path $wim -Destination "$dst\sources\" -ErrorAction Stop
        }
        else {
            $toSplit = $wim
            if ($wim -like '*.esd') {
                $tmpWim = Join-Path $env:TEMP ("cfg_install_{0}.wim" -f $PID)
                Write-CfgLog "La imagen supera 4 GB (límite de FAT32): exportando solo la edición elegida (índice $EditionIndex)..." STEP
                Export-WindowsImage -SourceImagePath $wim -SourceIndex $EditionIndex -DestinationImagePath $tmpWim -CompressionType max -ErrorAction Stop | Out-Null
                $toSplit = $tmpWim
            }
            if ((Get-Item $toSplit).Length -le $limit) { Copy-Item $toSplit "$dst\sources\install.wim" -ErrorAction Stop }
            else {
                Write-CfgLog 'Dividiendo install.wim en partes de 3,8 GB (install.swm) para FAT32...' STEP
                & dism.exe /Split-Image /ImageFile:"$toSplit" /SWMFile:"$dst\sources\install.swm" /FileSize:3800 | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "DISM no pudo dividir la imagen (código $LASTEXITCODE)" }
            }
        }

        [IO.File]::WriteAllText("$dst\autounattend.xml", $xml, (New-Object Text.UTF8Encoding $false))
        Write-CfgLog 'autounattend.xml copiado a la raíz del USB.' OK

        # $OEM$\$1 se copia automáticamente a C:\ durante la instalación
        $toolkit = "$dst\sources\`$OEM`$\`$1\Eureka_Utils"
        Write-CfgLog 'Copiando Eureka_Utils al USB (se copiará a C:\Eureka_Utils al instalar)...'
        Copy-CfgToolkit -Destination $toolkit -PostInstall $PostInstall
        Set-Volume -DriveLetter $letter -NewFileSystemLabel 'EUREKA' -ErrorAction SilentlyContinue
        Write-CfgLog "USB de instalación listo en $dst. Arranca el equipo desde el USB (F12/F11/F8/Esc según fabricante) en modo UEFI." OK
        return (New-CfgResult -Id 'usb' -Name 'USB de instalación' -Action 'Crear' -Success $true -Message $dst)
    }
    finally {
        Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null
        if ($tmpWim -and (Test-Path $tmpWim)) { Remove-Item $tmpWim -Force -ErrorAction SilentlyContinue }
    }
}

# ---------------------------------------------------------------- post-instalación

function Get-CfgPostInstall {
    $f = Join-Path (Get-CfgRoot) 'Config\postinstall.json'
    if (-not (Test-Path $f)) { return $null }
    try { return (Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Complete-CfgPostInstall {
    $f = Join-Path (Get-CfgRoot) 'Config\postinstall.json'
    if (Test-Path $f) { Move-Item $f (Join-Path (Get-CfgRoot) ('Config\postinstall.done_{0}.json' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))) -Force }
}

Export-ModuleMember -Function *
