# Security.psm1 - Verificación de antivirus, malware y protecciones del sistema
# Pensado también para usarse desde el USB en un equipo sospechoso.

function Get-CfgSecurityStatus {
    Write-CfgLog 'Comprobando antivirus, amenazas y protecciones...' STEP
    $out = New-Object System.Collections.Generic.List[object]
    $add = { param($c, $r, $d) $out.Add([pscustomobject]@{ Comprobacion = $c; Resultado = $r; Detalle = $d }) }

    # Antivirus registrados en el Centro de seguridad
    try {
        $av = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop)
        $names = @($av | ForEach-Object {
                $hex = '{0:X6}' -f [int]$_.productState
                $on = $hex.Substring(2, 2) -in @('10', '11')
                $upd = $hex.Substring(4, 2) -eq '00'
                '{0} ({1}{2})' -f $_.displayName, $(if ($on) { 'activo' } else { 'inactivo' }), $(if ($upd) { ', al día' } else { ', firmas desactualizadas' })
            })
        & $add 'Antivirus registrados' $(if ($av.Count) { 'OK' } else { 'FALLO' }) $(if ($names) { $names -join '; ' } else { 'Ninguno' })
    }
    catch { }

    # Microsoft Defender
    try {
        $s = Get-MpComputerStatus -ErrorAction Stop
        & $add 'Defender: protección en tiempo real' $(if ($s.RealTimeProtectionEnabled) { 'OK' } else { 'AVISO' }) $(if ($s.RealTimeProtectionEnabled) { 'Activada' } elseif ($s.AMRunningMode -match 'Passive') { 'Modo pasivo (hay otro antivirus)' } else { 'Desactivada' })
        $age = [int]$s.AntivirusSignatureAge
        & $add 'Defender: firmas' $(if ($age -gt 3) { 'AVISO' } else { 'OK' }) ('Versión {0}, de hace {1} día(s)' -f $s.AntivirusSignatureVersion, $age)
        $q = if ($s.QuickScanEndTime) { $s.QuickScanEndTime.ToString('dd/MM/yyyy HH:mm') } else { 'nunca' }
        $f = if ($s.FullScanEndTime) { $s.FullScanEndTime.ToString('dd/MM/yyyy HH:mm') } else { 'nunca' }
        & $add 'Defender: últimos análisis' $(if ($s.QuickScanAge -gt 14) { 'AVISO' } else { 'OK' }) "Rápido: $q · Completo: $f"
        & $add 'Protección contra alteraciones' $(if ($s.IsTamperProtected) { 'OK' } else { 'AVISO' }) $(if ($s.IsTamperProtected) { 'Activada' } else { 'Desactivada' })
    }
    catch { & $add 'Microsoft Defender' 'AVISO' 'No se pudo consultar (otro antivirus lo sustituye o se necesita administrador)' }

    # Amenazas
    try {
        $det = @(Get-MpThreatDetection -ErrorAction Stop)
        $active = @($det | Where-Object { $_.ActionSuccess -ne $true })
        & $add 'Amenazas detectadas' $(if ($active.Count) { 'FALLO' } elseif ($det.Count) { 'AVISO' } else { 'OK' }) $(if ($det.Count) { "$($det.Count) detecciones en el historial, $($active.Count) sin resolver" } else { 'Ninguna en el historial' })
    }
    catch { }

    # Firewall
    try {
        $fw = @(Get-NetFirewallProfile -ErrorAction Stop)
        $off = @($fw | Where-Object { -not $_.Enabled } | ForEach-Object Name)
        & $add 'Firewall de Windows' $(if ($off.Count) { 'FALLO' } else { 'OK' }) $(if ($off.Count) { "Desactivado en: $($off -join ', ')" } else { 'Activado en dominio, privado y público' })
    }
    catch { }

    # UAC
    $uac = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction SilentlyContinue
    & $add 'Control de cuentas (UAC)' $(if ($uac.EnableLUA -eq 1 -and $uac.ConsentPromptBehaviorAdmin -ne 0) { 'OK' } else { 'FALLO' }) $(if ($uac.EnableLUA -ne 1) { 'Desactivado' } elseif ($uac.ConsentPromptBehaviorAdmin -eq 0) { 'Eleva sin preguntar' } else { 'Activado' })

    # Arranque seguro
    $sb = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction SilentlyContinue).UEFISecureBootEnabled
    & $add 'Arranque seguro' $(if ($sb -eq 1) { 'OK' } else { 'AVISO' }) $(if ($sb -eq 1) { 'Activado' } else { 'Desactivado o BIOS heredada' })

    # BitLocker
    try {
        $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
        & $add "BitLocker en $($env:SystemDrive)" $(if ($bl.ProtectionStatus -eq 'On') { 'OK' } else { 'AVISO' }) "$($bl.VolumeStatus), protección $($bl.ProtectionStatus)"
    }
    catch { & $add 'BitLocker' 'INFO' 'No disponible o se necesita administrador' }

    # Persistencia sospechosa básica: elementos de inicio sin firma en carpetas temporales
    $runKeys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    $sus = foreach ($k in $runKeys) {
        $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
        if ($p) { $p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' -and "$($_.Value)" -match '\\(Temp|AppData\\Local\\Temp|Users\\Public)\\' } | ForEach-Object { $_.Name } }
    }
    $sus = @($sus)
    & $add 'Inicio desde carpetas temporales' $(if ($sus.Count) { 'AVISO' } else { 'OK' }) $(if ($sus.Count) { "Revisar con Autoruns: $($sus -join ', ')" } else { 'Ningún programa de inicio en carpetas temporales' })

    foreach ($c in $out) { Write-CfgLog ('{0}: {1}' -f $c.Comprobacion, $c.Detalle) $(switch ($c.Resultado) { 'OK' { 'OK' } 'FALLO' { 'ERROR' } 'AVISO' { 'WARN' } default { 'INFO' } }) }
    return $out.ToArray()
}

function Get-CfgThreats {
    try {
        @(Get-MpThreatDetection -ErrorAction Stop | Sort-Object InitialDetectionTime -Descending | Select-Object -First 50 | ForEach-Object {
                $t = Get-MpThreat -ThreatID $_.ThreatID -ErrorAction SilentlyContinue
                [pscustomobject]@{
                    Fecha = $_.InitialDetectionTime.ToString('dd/MM/yyyy HH:mm')
                    Amenaza = $(if ($t) { $t.ThreatName } else { $_.ThreatID })
                    Recurso = (@($_.Resources) | Select-Object -First 1)
                    Resuelta = $(if ($_.ActionSuccess) { 'Sí' } else { 'No' })
                }
            })
    }
    catch { @() }
}

function Update-CfgDefenderSignatures {
    Write-CfgLog 'Actualizando las firmas de Microsoft Defender...' STEP
    try { Update-MpSignature -ErrorAction Stop; Write-CfgLog 'Firmas actualizadas.' OK; return (New-CfgResult -Id 'sig' -Name 'Firmas Defender' -Action 'Seguridad' -Success $true -Message 'Actualizadas') }
    catch { Write-CfgLog "No se pudieron actualizar las firmas: $($_.Exception.Message)" ERROR; return (New-CfgResult -Id 'sig' -Name 'Firmas Defender' -Action 'Seguridad' -Success $false -Message $_.Exception.Message) }
}

function Start-CfgDefenderScan {
    <# Type: Quick | Full | Custom (con Path) | Offline (reinicia y analiza fuera de Windows) #>
    param([Parameter(Mandatory)][ValidateSet('Quick', 'Full', 'Custom', 'Offline')][string]$Type, [string]$Path)
    try {
        switch ($Type) {
            'Offline' {
                Write-CfgLog 'Programando Microsoft Defender sin conexión: el equipo se reiniciará y analizará durante unos 15 minutos fuera de Windows.' WARN
                Start-MpWDOScan -ErrorAction Stop
            }
            'Custom' {
                Write-CfgLog "Analizando $Path con Microsoft Defender..." STEP
                Start-MpScan -ScanType CustomScan -ScanPath $Path -ErrorAction Stop
            }
            default {
                Write-CfgLog ("Análisis {0} de Microsoft Defender en curso (puede tardar)..." -f $(if ($Type -eq 'Quick') { 'rápido' } else { 'completo' })) STEP
                Start-MpScan -ScanType "$($Type)Scan" -ErrorAction Stop
            }
        }
        $det = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { $_.InitialDetectionTime -gt (Get-Date).AddMinutes(-240) })
        Write-CfgLog $(if ($det.Count) { "Análisis terminado: $($det.Count) amenaza(s) detectada(s). Revisa la tabla de amenazas." } else { 'Análisis terminado sin amenazas nuevas.' }) $(if ($det.Count) { 'WARN' } else { 'OK' })
        return (New-CfgResult -Id "scan-$Type" -Name "Análisis $Type" -Action 'Seguridad' -Success $true -Message "$($det.Count) detecciones")
    }
    catch {
        Write-CfgLog "No se pudo ejecutar el análisis: $($_.Exception.Message)" ERROR
        return (New-CfgResult -Id "scan-$Type" -Name "Análisis $Type" -Action 'Seguridad' -Success $false -Message $_.Exception.Message)
    }
}

function Get-CfgRescueFolder {
    $d = Join-Path (Get-CfgRoot) 'Packages\Rescate'
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    return $d
}

function Get-CfgSafetyScanner {
    <# Descarga Microsoft Safety Scanner (MSERT) en Packages\Rescate (así viaja en el USB) y lo ejecuta. #>
    param([switch]$Run)
    $arch = if ([Environment]::Is64BitOperatingSystem) { if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' } } else { 'x86' }
    $url = @{ x64 = 'https://go.microsoft.com/fwlink/?LinkId=212732'; x86 = 'https://go.microsoft.com/fwlink/?LinkId=212733'; arm64 = 'https://go.microsoft.com/fwlink/?LinkId=212732' }[$arch]
    $file = Join-Path (Get-CfgRescueFolder) "msert_$arch.exe"
    $fresh = (Test-Path $file) -and ((Get-Item $file).LastWriteTime -gt (Get-Date).AddDays(-10))
    if (-not $fresh) {
        Write-CfgLog "Descargando Microsoft Safety Scanner ($arch, unos 200 MB; caduca a los 10 días)..." STEP
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            Start-BitsTransfer -Source $url -Destination $file -ErrorAction Stop
        }
        catch {
            try { Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing -ErrorAction Stop }
            catch { Write-CfgLog "No se pudo descargar: $($_.Exception.Message)" ERROR; return (New-CfgResult -Id 'msert' -Name 'Safety Scanner' -Action 'Seguridad' -Success $false -Message $_.Exception.Message) }
        }
    }
    $sig = Get-AuthenticodeSignature $file
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft') {
        Write-CfgLog 'La firma digital del Safety Scanner descargado no es válida de Microsoft: se elimina.' ERROR
        Remove-Item $file -Force -ErrorAction SilentlyContinue
        return (New-CfgResult -Id 'msert' -Name 'Safety Scanner' -Action 'Seguridad' -Success $false -Message 'Firma no válida')
    }
    Write-CfgLog "Microsoft Safety Scanner listo en $file (firma de Microsoft verificada)." OK
    if ($Run) { Start-Process -FilePath $file; Write-CfgLog 'Safety Scanner abierto: elige análisis rápido, completo o personalizado. El informe queda en %SYSTEMROOT%\debug\msert.log.' }
    return (New-CfgResult -Id 'msert' -Name 'Safety Scanner' -Action 'Seguridad' -Success $true -Message $file)
}

$script:RescueLinks = [ordered]@{
    'Kaspersky Virus Removal Tool' = 'https://www.kaspersky.es/downloads/free-virus-removal-tool'
    'Emsisoft Emergency Kit'       = 'https://www.emsisoft.com/es/emergency-kit/'
    'ESET Online Scanner'          = 'https://www.eset.com/es/hogar/online-scanner/'
    'Microsoft Defender Offline (información)' = 'https://support.microsoft.com/es-es/windows/ayudar-a-proteger-mi-pc-con-microsoft-defender-sin-conexi%C3%B3n-9306d528-64bf-4668-5b80-ff533f183d6c'
}
function Get-CfgRescueLinks { $script:RescueLinks }

Export-ModuleMember -Function *
