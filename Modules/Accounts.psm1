# Accounts.psm1 - Cuenta profesional (Entra ID / Microsoft 365 con MFA) y cuentas locales
#
# Eureka_Utils NUNCA pide ni guarda la contraseña de la cuenta profesional: abre la ventana
# oficial de inicio de sesión de Microsoft con el usuario ya escrito. Ahí se introduce la contraseña
# y se aprueba la notificación de doble factor (Microsoft Authenticator con número, SMS, llamada,
# llave FIDO2 o Windows Hello), según lo que exija el acceso condicional de la organización.

function Test-CfgUpn { param([string]$Upn) return ($Upn -match '^[^@\s]+@[^@\s]+\.[^@\s]+$') }

function Test-CfgWorkAccount {
    param([Parameter(Mandatory)][string]$Upn)
    $out = New-Object System.Collections.Generic.List[object]
    $add = { param($c, $r, $d) $out.Add([pscustomobject]@{ Comprobacion = $c; Resultado = $r; Detalle = $d }) }
    if (-not (Test-CfgUpn $Upn)) {
        & $add 'Formato' 'FALLO' 'Escribe la cuenta como usuario@empresa.com'
        return $out.ToArray()
    }
    $domain = $Upn.Split('@')[1]
    Write-CfgLog "Comprobando la cuenta profesional $Upn..." STEP
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

    try {
        $realm = Invoke-RestMethod -Uri ("https://login.microsoftonline.com/common/userrealm/{0}?api-version=2.1" -f [uri]::EscapeDataString($Upn)) -UseBasicParsing -TimeoutSec 15
        switch ($realm.NameSpaceType) {
            'Managed'   { & $add 'Inquilino Microsoft Entra' 'OK' ("{0} · identidad en la nube (MFA gestionado por Entra ID)" -f $(if ($realm.FederationBrandName) { $realm.FederationBrandName } else { $domain })) }
            'Federated' { & $add 'Inquilino Microsoft Entra' 'OK' ("{0} · federado con {1} (el MFA lo pide el proveedor federado)" -f $realm.FederationBrandName, ([uri]$realm.AuthURL).Host) }
            default     { & $add 'Inquilino Microsoft Entra' 'FALLO' "El dominio $domain no pertenece a ningún inquilino de Microsoft 365 / Entra ID. Revisa la cuenta." }
        }
    }
    catch { & $add 'Inquilino Microsoft Entra' 'AVISO' "No se pudo consultar login.microsoftonline.com (¿sin Internet o proxy?): $($_.Exception.Message)" }

    try {
        $oidc = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$domain/v2.0/.well-known/openid-configuration" -UseBasicParsing -TimeoutSec 15
        $tid = [regex]::Match($oidc.issuer, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}').Value
        if ($tid) { & $add 'Id. de inquilino' 'INFO' $tid }
    }
    catch { }

    try {
        $c = Resolve-DnsName -Name "enterpriseenrollment.$domain" -Type CNAME -ErrorAction Stop | Where-Object { $_.Type -eq 'CNAME' } | Select-Object -First 1
        if ($c.NameHost -match 'manage(-beta)?\.microsoft\.com') { & $add 'Autodescubrimiento Intune (DNS)' 'OK' "enterpriseenrollment.$domain -> $($c.NameHost)" }
        else { & $add 'Autodescubrimiento Intune (DNS)' 'AVISO' "enterpriseenrollment.$domain apunta a $($c.NameHost)" }
    }
    catch { & $add 'Autodescubrimiento Intune (DNS)' 'AVISO' "Sin registro CNAME enterpriseenrollment.$domain. La unión a Entra con inscripción automática funciona igual; la inscripción manual 'solo MDM' puede pedir el servidor." }

    & $add 'Doble factor (MFA)' 'INFO' 'Se solicitará en la ventana de Microsoft. Ten a mano el móvil con Microsoft Authenticator. Si aún no tienes métodos registrados, usa "Registrar métodos MFA".'
    foreach ($x in $out) { Write-CfgLog ('{0}: {1}' -f $x.Comprobacion, $x.Detalle) $(switch ($x.Resultado) { 'OK' { 'OK' } 'FALLO' { 'ERROR' } 'AVISO' { 'WARN' } default { 'INFO' } }) }
    return $out.ToArray()
}

function Start-CfgWorkAccountFlow {
    <# Abre el asistente nativo de Windows con la cuenta ya escrita:
       aadj = unir el equipo a Microsoft Entra ID (inscribe en Intune si la inscripción automática está activa)
       mdm  = inscribir solo en Intune (MDM)
       awa  = añadir cuenta profesional (registro en Entra, BYOD) #>
    param([Parameter(Mandatory)][ValidateSet('aadj', 'mdm', 'awa')][string]$Mode, [string]$Upn)
    $uri = "ms-device-enrollment:?mode=$Mode"
    if ($Upn) { $uri += '&username=' + [uri]::EscapeDataString($Upn) }
    $what = @{ aadj = 'Unir a Microsoft Entra ID'; mdm = 'Inscribir en Intune'; awa = 'Añadir cuenta profesional' }[$Mode]
    Write-CfgLog "$what con $(if ($Upn) { $Upn } else { 'la cuenta que indiques' }). En la ventana de Microsoft: escribe la contraseña y aprueba la notificación de doble factor en tu móvil (introduce el número que aparezca en pantalla)." STEP
    try {
        Start-Process $uri -ErrorAction Stop
    }
    catch {
        Write-CfgLog "No se pudo abrir el asistente directo ($($_.Exception.Message)). Se abre Configuración > Cuentas > Acceso al trabajo o colegio." WARN
        Start-Process 'ms-settings:workplace'
    }
}

function Open-CfgMfaRegistration {
    Write-CfgLog 'Abriendo https://aka.ms/mysecurityinfo para registrar Microsoft Authenticator u otros métodos de doble factor.'
    Start-Process 'https://aka.ms/mysecurityinfo'
}

# ---------------------------------------------------------------- cuentas locales

function Get-CfgLocalGroupName { param([string]$Sid) return (Get-LocalGroup -SID $Sid).Name }

function Get-CfgLocalUsers {
    $admins = @()
    try { $admins = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop | ForEach-Object { $_.Name }) } catch { }
    Get-LocalUser | ForEach-Object {
        $full = "$env:COMPUTERNAME\$($_.Name)"
        [pscustomobject]@{
            Name      = $_.Name
            FullName  = $_.FullName
            Enabled   = $_.Enabled
            Admin     = ($admins -contains $full)
            LastLogon = $(if ($_.LastLogon) { $_.LastLogon.ToString('yyyy-MM-dd HH:mm') } else { 'Nunca' })
        }
    }
}

function New-CfgLocalUser {
    param(
        [Parameter(Mandatory)][string]$UserName,
        [string]$FullName,
        [Parameter(Mandatory)][securestring]$Password,
        [switch]$Administrator,
        [switch]$MustChangePassword
    )
    if ($UserName -notmatch '^[^\\/\[\]:;|=,+*?<>"@]{1,20}$') {
        Write-CfgLog "Nombre de usuario no válido: máximo 20 caracteres y sin \ / [ ] : ; | = , + * ? < > `" @" ERROR
        return (New-CfgResult -Id 'localuser' -Name $UserName -Action 'Crear cuenta' -Success $false -Message 'Nombre no válido')
    }
    try {
        $p = @{ Name = $UserName; Password = $Password; AccountNeverExpires = $true; ErrorAction = 'Stop' }
        if ($FullName) { $p.FullName = $FullName }
        New-LocalUser @p | Out-Null
        Add-LocalGroupMember -SID 'S-1-5-32-545' -Member $UserName -ErrorAction SilentlyContinue
        if ($Administrator) { Add-LocalGroupMember -SID 'S-1-5-32-544' -Member $UserName -ErrorAction Stop }
        if ($MustChangePassword) { & net.exe user $UserName /logonpasswordchg:yes | Out-Null }
        Write-CfgLog ("Cuenta local '{0}' creada{1}." -f $UserName, $(if ($Administrator) { ' como administrador' } else { ' como usuario estándar' })) OK
        return (New-CfgResult -Id 'localuser' -Name $UserName -Action 'Crear cuenta' -Success $true -Message 'Creada')
    }
    catch {
        Write-CfgLog "No se pudo crear la cuenta: $($_.Exception.Message)" ERROR
        return (New-CfgResult -Id 'localuser' -Name $UserName -Action 'Crear cuenta' -Success $false -Message $_.Exception.Message)
    }
}

function Add-CfgLocalAdmin {
    <# Member: usuario local, DOMINIO\usuario o AzureAD\usuario@empresa.com #>
    param([Parameter(Mandatory)][string]$Member)
    $group = Get-CfgLocalGroupName -Sid 'S-1-5-32-544'
    # net localgroup resuelve cuentas de Entra (AzureAD\...) que Add-LocalGroupMember no siempre admite
    $outp = & net.exe localgroup "$group" "$Member" /add 2>&1 | Out-String
    $ok = ($LASTEXITCODE -eq 0) -or ($outp -match '1378')
    Write-CfgLog $(if ($ok) { "$Member añadido a $group." } else { "No se pudo añadir $Member a ${group}: $($outp.Trim())" }) $(if ($ok) { 'OK' } else { 'ERROR' })
    return (New-CfgResult -Id 'localadmin' -Name $Member -Action 'Administrador local' -Success $ok -Message $outp.Trim())
}

Export-ModuleMember -Function *
