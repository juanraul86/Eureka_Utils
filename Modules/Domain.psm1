# Domain.psm1 - Active Directory, Microsoft Entra ID, Intune y Autopilot

function Test-CfgComputerName {
    param([string]$Name)
    return ($Name -match '^[A-Za-z0-9-]{1,15}$' -and $Name -notmatch '^\d+$' -and $Name -notmatch '^-|-$')
}

function Get-CfgJoinStatus {
    $ds = @{}
    try {
        foreach ($line in (& dsregcmd.exe /status 2>$null)) {
            if ($line -match '^\s*([A-Za-z0-9]+)\s*:\s*(.*)$') { $ds[$matches[1]] = $matches[2].Trim() }
        }
    }
    catch { }
    $cs  = Get-CimInstance Win32_ComputerSystem
    $mdm = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
        Where-Object { $_.PSObject.Properties['ProviderID'] -and $_.ProviderID -eq 'MS DM Server' } |
        Select-Object -First 1
    $ime = Get-Service -Name IntuneManagementExtension -ErrorAction SilentlyContinue
    [pscustomobject]@{
        DominioAD       = $(if ($cs.PartOfDomain) { $cs.Domain } else { $null })
        Workgroup       = $cs.Workgroup
        EntraJoined     = ($ds['AzureAdJoined'] -eq 'YES')
        HybridJoined    = ($cs.PartOfDomain -and $ds['AzureAdJoined'] -eq 'YES')
        WorkplaceJoined = ($ds['WorkplaceJoined'] -eq 'YES')
        Tenant          = $ds['TenantName']
        TenantId        = $ds['TenantId']
        DeviceId        = $ds['DeviceId']
        PRT             = $ds['AzureAdPrt']
        MdmUrl          = $ds['MdmUrl']
        IntuneEnrolled  = [bool]$mdm
        IntuneUpn       = $(if ($mdm -and $mdm.PSObject.Properties['UPN']) { $mdm.UPN } else { $null })
        IME             = $(if ($ime) { [string]$ime.Status } else { 'No instalado' })
    }
}

function Get-CfgJoinDisplay {
    param([Parameter(Mandatory)]$Status)
    $tipo = if ($Status.HybridJoined) { 'Unión híbrida (AD + Entra ID)' }
            elseif ($Status.EntraJoined) { 'Unido a Microsoft Entra ID' }
            elseif ($Status.DominioAD) { 'Unido a Active Directory' }
            elseif ($Status.WorkplaceJoined) { 'Cuenta profesional registrada (Entra registered)' }
            else { "Sin unir (grupo de trabajo $($Status.Workgroup))" }
    [ordered]@{
        'Tipo de unión'            = $tipo
        'Dominio AD'               = $(if ($Status.DominioAD) { $Status.DominioAD } else { '—' })
        'Inquilino Entra'          = $(if ($Status.Tenant) { "$($Status.Tenant) ($($Status.TenantId))" } elseif ($Status.TenantId) { $Status.TenantId } else { '—' })
        'Id. de dispositivo'       = $(if ($Status.DeviceId) { $Status.DeviceId } else { '—' })
        'Inscrito en Intune (MDM)' = $(if ($Status.IntuneEnrolled) { 'Sí' + $(if ($Status.IntuneUpn) { " ($($Status.IntuneUpn))" } else { '' }) } else { 'No' })
        'Intune Mgmt. Extension'   = $Status.IME
        'Token PRT'                = $(if ($Status.PRT) { $Status.PRT } else { '—' })
    }
}

function Test-CfgDomainPrerequisites {
    param([Parameter(Mandatory)][string]$Domain)
    $out = New-Object System.Collections.Generic.List[object]
    $add = { param($c, $r, $d) $out.Add([pscustomobject]@{ Comprobacion = $c; Resultado = $r; Detalle = $d }) }

    Write-CfgLog "Comprobando requisitos para unir a $Domain..." STEP
    & $add 'Permisos de administrador' $(if (Test-CfgAdmin) { 'OK' } else { 'FALLO' }) 'Unir a dominio requiere ejecutar elevado.'

    $ed = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
    if ($ed -match '^Core') { & $add 'Edición de Windows' 'FALLO' "$ed (Home) no admite unión a dominio. Actualiza a Pro, Enterprise o Education." }
    else { & $add 'Edición de Windows' 'OK' $ed }

    $cs = Get-CimInstance Win32_ComputerSystem
    if ($cs.PartOfDomain) { & $add 'Pertenencia actual' 'AVISO' "Ya está unido a $($cs.Domain)." }
    else { & $add 'Pertenencia actual' 'OK' "Grupo de trabajo $($cs.Workgroup)" }

    if (Test-CfgComputerName $env:COMPUTERNAME) { & $add 'Nombre del equipo' 'OK' $env:COMPUTERNAME }
    else { & $add 'Nombre del equipo' 'AVISO' "'$($env:COMPUTERNAME)' no es un nombre NetBIOS válido (máx. 15 caracteres, letras, números y guiones). Usa 'Nuevo nombre'." }

    $dns = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.ServerAddresses } | ForEach-Object { $_.ServerAddresses } | Select-Object -Unique)
    & $add 'Servidores DNS del equipo' 'INFO' $(if ($dns.Count) { $dns -join ', ' } else { 'Ninguno' })

    $dcs = @()
    try {
        $srv = Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.$Domain" -Type SRV -ErrorAction Stop | Where-Object { $_.Type -eq 'SRV' }
        $dcs = @($srv | Sort-Object Priority, Weight | Select-Object -ExpandProperty NameTarget -Unique)
        & $add 'Localizar controladores (DNS SRV)' 'OK' ($dcs -join ', ')
    }
    catch {
        & $add 'Localizar controladores (DNS SRV)' 'FALLO' "No se resuelve _ldap._tcp.dc._msdcs.$Domain. El DNS del adaptador debe apuntar a los DNS del dominio, no al router."
    }

    if ($dcs.Count) {
        $dc = $dcs[0]
        $ports = @(@{ P = 53; N = 'DNS' }, @{ P = 88; N = 'Kerberos' }, @{ P = 135; N = 'RPC' }, @{ P = 389; N = 'LDAP' }, @{ P = 445; N = 'SMB' }, @{ P = 464; N = 'Kerberos kpasswd' })
        $closed = @(foreach ($p in $ports) { if (-not (Test-CfgTcpPort -HostName $dc -Port $p.P)) { '{0}/{1}' -f $p.P, $p.N } })
        if ($closed.Count) { & $add "Puertos en $dc" 'FALLO' ('Sin respuesta: {0}. Revisa cortafuegos/VPN.' -f ($closed -join ', ')) }
        else { & $add "Puertos en $dc" 'OK' '53, 88, 135, 389, 445 y 464 accesibles' }

        try {
            $sc = (& w32tm.exe /stripchart /computer:$dc /samples:1 /dataonly 2>$null) -join "`n"
            $m = [regex]::Match($sc, '([+-]\d+[\.,]\d+)s')
            if ($m.Success) {
                $off = [double]::Parse($m.Groups[1].Value.Replace(',', '.'), [Globalization.CultureInfo]::InvariantCulture)
                if ([math]::Abs($off) -gt 300) { & $add 'Sincronización horaria' 'FALLO' ('Desfase de {0:N0} s con {1}. Kerberos tolera 5 minutos.' -f $off, $dc) }
                else { & $add 'Sincronización horaria' 'OK' ('Desfase de {0:N2} s' -f $off) }
            }
            else { & $add 'Sincronización horaria' 'AVISO' 'No se pudo medir el desfase.' }
        }
        catch { & $add 'Sincronización horaria' 'AVISO' 'No se pudo medir el desfase.' }
    }
    foreach ($c in $out) {
        $lvl = switch ($c.Resultado) { 'OK' { 'OK' } 'FALLO' { 'ERROR' } 'AVISO' { 'WARN' } default { 'INFO' } }
        Write-CfgLog ('{0}: {1}' -f $c.Comprobacion, $c.Detalle) $lvl
    }
    return $out.ToArray()
}

function Join-CfgDomain {
    param(
        [Parameter(Mandatory)][string]$Domain,
        [Parameter(Mandatory)][pscredential]$Credential,
        [string]$OUPath,
        [string]$NewName,
        [switch]$Restart
    )
    $p = @{ DomainName = $Domain; Credential = $Credential; Force = $true; ErrorAction = 'Stop'; PassThru = $true }
    if ($OUPath) { $p.OUPath = $OUPath }
    if ($NewName -and $NewName -ne $env:COMPUTERNAME) { $p.NewName = $NewName }
    Write-CfgLog ("Uniendo a {0}{1}{2}..." -f $Domain, $(if ($OUPath) { " (OU: $OUPath)" } else { '' }), $(if ($p.NewName) { " con el nombre $NewName" } else { '' })) STEP
    try {
        Add-Computer @p | Out-Null
        Write-CfgLog "Equipo unido a $Domain. Es necesario reiniciar." OK
        if ($Restart) { Restart-CfgComputerDelayed -Seconds 60 }
        return (New-CfgResult -Id 'ad-join' -Name "Unir a $Domain" -Action 'Dominio' -Success $true -Message 'Reinicio pendiente')
    }
    catch {
        Write-CfgLog "No se pudo unir al dominio: $($_.Exception.Message)" ERROR
        return (New-CfgResult -Id 'ad-join' -Name "Unir a $Domain" -Action 'Dominio' -Success $false -Message $_.Exception.Message)
    }
}

function Rename-CfgComputer {
    param([Parameter(Mandatory)][string]$NewName, [pscredential]$Credential, [switch]$Restart)
    if (-not (Test-CfgComputerName $NewName)) {
        Write-CfgLog "'$NewName' no es un nombre válido (máx. 15 caracteres: letras, números y guiones)." ERROR
        return (New-CfgResult -Id 'rename' -Name 'Renombrar' -Action 'Equipo' -Success $false -Message 'Nombre no válido')
    }
    $p = @{ NewName = $NewName; Force = $true; ErrorAction = 'Stop'; PassThru = $true }
    if ($Credential) { $p.DomainCredential = $Credential }
    try {
        Rename-Computer @p | Out-Null
        Write-CfgLog "Equipo renombrado a $NewName (efectivo tras reiniciar)." OK
        if ($Restart) { Restart-CfgComputerDelayed -Seconds 60 }
        return (New-CfgResult -Id 'rename' -Name 'Renombrar' -Action 'Equipo' -Success $true -Message 'Reinicio pendiente')
    }
    catch {
        Write-CfgLog "No se pudo renombrar: $($_.Exception.Message)" ERROR
        return (New-CfgResult -Id 'rename' -Name 'Renombrar' -Action 'Equipo' -Success $false -Message $_.Exception.Message)
    }
}

function Remove-CfgDomainMembership {
    param([Parameter(Mandatory)][pscredential]$Credential, [string]$Workgroup = 'WORKGROUP', [switch]$Restart)
    try {
        Remove-Computer -UnjoinDomainCredential $Credential -WorkgroupName $Workgroup -Force -ErrorAction Stop
        Write-CfgLog "Equipo retirado del dominio (grupo de trabajo $Workgroup). Inicia sesión después con una cuenta local." OK
        if ($Restart) { Restart-CfgComputerDelayed -Seconds 60 }
        return (New-CfgResult -Id 'ad-leave' -Name 'Salir del dominio' -Action 'Dominio' -Success $true -Message 'Reinicio pendiente')
    }
    catch {
        Write-CfgLog "No se pudo salir del dominio: $($_.Exception.Message)" ERROR
        return (New-CfgResult -Id 'ad-leave' -Name 'Salir del dominio' -Action 'Dominio' -Success $false -Message $_.Exception.Message)
    }
}

function Invoke-CfgGpUpdate {
    Write-CfgLog 'Aplicando directivas de grupo (gpupdate /force)...' STEP
    & gpupdate.exe /target:computer /force 2>&1 | ForEach-Object { $l = "$_".Trim(); if ($l) { Write-CfgLog "   $l" } }
    $ok = ($LASTEXITCODE -eq 0)
    Write-CfgLog 'gpupdate finalizado.' $(if ($ok) { 'OK' } else { 'WARN' })
    return (New-CfgResult -Id 'gpupdate' -Name 'gpupdate' -Action 'Directivas' -Success $ok -Message "Código $LASTEXITCODE")
}

# ---------------------------------------------------------------- Entra ID / Intune

function Invoke-CfgIntuneSync {
    Write-CfgLog 'Sincronizando con Intune...' STEP
    $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
            $_.TaskPath -like '\Microsoft\Windows\EnterpriseMgmt\*' -and
            ($_.TaskName -eq 'PushLaunch' -or $_.TaskName -like 'Schedule #3 created by enrollment client*') })
    if (-not $tasks.Count) {
        Write-CfgLog 'No hay tareas de sincronización MDM: el equipo no parece inscrito en Intune.' WARN
        return (New-CfgResult -Id 'intune-sync' -Name 'Sincronizar Intune' -Action 'Intune' -Success $false -Message 'No inscrito en MDM')
    }
    foreach ($t in $tasks) {
        try { Start-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction Stop; Write-CfgLog "   Lanzada: $($t.TaskPath)$($t.TaskName)" OK }
        catch { Write-CfgLog "   No se pudo lanzar $($t.TaskName): $($_.Exception.Message)" WARN }
    }
    $ime = Get-Service -Name IntuneManagementExtension -ErrorAction SilentlyContinue
    if ($ime) {
        try {
            Restart-Service -Name IntuneManagementExtension -Force -ErrorAction Stop
            Write-CfgLog '   Reiniciado Intune Management Extension: fuerza la evaluación de apps Win32, scripts y correcciones.' OK
        }
        catch { Write-CfgLog "   No se pudo reiniciar IME: $($_.Exception.Message)" WARN }
    }
    else { Write-CfgLog '   IME no instalado (Intune lo instala al asignar la primera app Win32 o script).' }
    Write-CfgLog 'Sincronización solicitada. Los cambios pueden tardar varios minutos en aplicarse.' OK
    return (New-CfgResult -Id 'intune-sync' -Name 'Sincronizar Intune' -Action 'Intune' -Success $true -Message 'Solicitada')
}

function Invoke-CfgHybridJoin {
    Write-CfgLog 'Lanzando tarea de unión híbrida (Workplace Join\Automatic-Device-Join)...' STEP
    $cs = Get-CimInstance Win32_ComputerSystem
    if (-not $cs.PartOfDomain) { Write-CfgLog 'El equipo no está unido a AD: la unión híbrida requiere dominio + Entra Connect.' WARN }
    try {
        Start-ScheduledTask -TaskPath '\Microsoft\Windows\Workplace Join\' -TaskName 'Automatic-Device-Join' -ErrorAction Stop
        Write-CfgLog 'Tarea lanzada. Tras la siguiente sincronización de Entra Connect el equipo aparecerá como híbrido; comprueba con "Actualizar información".' OK
        return (New-CfgResult -Id 'hybrid' -Name 'Unión híbrida' -Action 'Entra' -Success $true -Message 'Tarea lanzada')
    }
    catch {
        Write-CfgLog "No se pudo lanzar la tarea: $($_.Exception.Message)" ERROR
        return (New-CfgResult -Id 'hybrid' -Name 'Unión híbrida' -Action 'Entra' -Success $false -Message $_.Exception.Message)
    }
}

function Invoke-CfgMdmAutoEnroll {
    Write-CfgLog 'Solicitando inscripción automática en MDM (deviceenroller /AutoEnrollMDM)...' STEP
    $exe = Join-Path $env:SystemRoot 'System32\deviceenroller.exe'
    if (-not (Test-Path $exe)) { Write-CfgLog 'deviceenroller.exe no existe en este sistema.' ERROR; return (New-CfgResult -Id 'mdm' -Name 'Inscripción MDM' -Action 'Intune' -Success $false -Message 'No disponible') }
    & $exe /c /AutoEnrollMDM | Out-Null
    Write-CfgLog 'Solicitud enviada. Requiere unión a Entra (o híbrida), licencia Intune y ámbito MDM del usuario. Revisa el Visor de eventos > DeviceManagement-Enterprise-Diagnostics-Provider.' OK
    return (New-CfgResult -Id 'mdm' -Name 'Inscripción MDM' -Action 'Intune' -Success $true -Message 'Solicitada')
}

function Export-CfgAutopilotHash {
    param([string]$GroupTag, [string]$OutputFolder)
    if (-not $OutputFolder) { $OutputFolder = Get-CfgExportFolder }
    Write-CfgLog 'Obteniendo hash de hardware para Windows Autopilot...' STEP
    try {
        $dev = Get-CimInstance -Namespace 'root/cimv2/mdm/dmmap' -ClassName 'MDM_DevDetail_Ext01' -Filter "InstanceID='Ext' AND ParentID='./DevDetail'" -ErrorAction Stop
        $serial = (Get-CimInstance Win32_BIOS).SerialNumber
        $file = Join-Path $OutputFolder ('Autopilot_{0}_{1}.csv' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmmss'))
        $header = 'Device Serial Number,Windows Product ID,Hardware Hash'
        $line   = '{0},,{1}' -f $serial, $dev.DeviceHardwareData
        if ($GroupTag) { $header += ',Group Tag'; $line += ",$GroupTag" }
        Set-Content -Path $file -Value @($header, $line) -Encoding ASCII
        Write-CfgLog "CSV generado: $file. Impórtalo en Intune > Dispositivos > Windows > Inscripción > Dispositivos." OK
        return (New-CfgResult -Id 'autopilot' -Name 'Hash Autopilot' -Action 'Exportar' -Success $true -Message $file)
    }
    catch {
        Write-CfgLog "No se pudo obtener el hash (requiere administrador): $($_.Exception.Message)" ERROR
        return (New-CfgResult -Id 'autopilot' -Name 'Hash Autopilot' -Action 'Exportar' -Success $false -Message $_.Exception.Message)
    }
}

function New-CfgMdmDiagnostics {
    param([string]$OutputFolder)
    if (-not $OutputFolder) { $OutputFolder = Get-CfgExportFolder }
    $cab = Join-Path $OutputFolder ('MDMDiag_{0}_{1}.cab' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmmss'))
    Write-CfgLog 'Generando diagnóstico MDM (inscripción, aprovisionamiento y Autopilot)...' STEP
    $exe = Join-Path $env:SystemRoot 'System32\MdmDiagnosticsTool.exe'
    & $exe -area 'DeviceEnrollment;DeviceProvisioning;Autopilot' -cab $cab | Out-Null
    $ok = Test-Path $cab
    Write-CfgLog $(if ($ok) { "Diagnóstico guardado en $cab" } else { 'No se generó el archivo de diagnóstico.' }) $(if ($ok) { 'OK' } else { 'ERROR' })
    return (New-CfgResult -Id 'mdmdiag' -Name 'Diagnóstico MDM' -Action 'Exportar' -Success $ok -Message $cab)
}

Export-ModuleMember -Function *
