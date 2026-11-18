# Tweaks.psm1 - Ajustes de Windows reutilizables por los perfiles
# Los ajustes "Usuario" se escriben en HKCU de la cuenta que ejecuta Eureka_Utils.

function Set-CfgReg {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Test-CfgReg {
    param([string]$Path, [string]$Name, $Value)
    $v = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
    return ($null -ne $v -and "$v" -eq "$Value")
}

function Get-CfgActivePowerScheme {
    $o = (& powercfg.exe /getactivescheme) -join ' '
    $g = [regex]::Match($o, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}').Value
    return [pscustomobject]@{ Guid = $g; Text = $o }
}

$script:Adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$script:Cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'

$script:Tweaks = @(
    @{ Id = 'power-balanced'; Name = 'Plan de energía Equilibrado'; Category = 'Energía'; Scope = 'Equipo'
        Description = 'Recomendado para portátiles y oficina: equilibra rendimiento, ruido y batería.'
        Test = { (Get-CfgActivePowerScheme).Guid -eq '381b4222-f694-41f0-9685-ff5bb260df2e' }
        Apply = { & powercfg.exe /setactive 381b4222-f694-41f0-9685-ff5bb260df2e } }
    @{ Id = 'power-high'; Name = 'Plan de energía Alto rendimiento'; Category = 'Energía'; Scope = 'Equipo'
        Description = 'La CPU no baja de frecuencia tan agresivamente. Más consumo y temperatura; útil en sobremesa para gaming o edición.'
        Test = { (Get-CfgActivePowerScheme).Guid -eq '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' }
        Apply = { & powercfg.exe /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null; if ($LASTEXITCODE) { & powercfg.exe -duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c | Out-Null; & powercfg.exe /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c } } }
    @{ Id = 'power-ultimate'; Name = 'Plan de energía Máximo rendimiento'; Category = 'Energía'; Scope = 'Equipo'
        Description = 'Plan oculto "Ultimate Performance": elimina microlatencias de ahorro de energía. Solo para sobremesa de gaming/streaming.'
        Test = { (Get-CfgActivePowerScheme).Text -match 'Máximo rendimiento|Ultimate Performance' }
        Apply = {
            $o = (& powercfg.exe -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61) -join ' '
            $g = [regex]::Match($o, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}').Value
            if ($g) { & powercfg.exe /setactive $g } } }
    @{ Id = 'fast-startup-off'; Name = 'Desactivar inicio rápido'; Category = 'Energía'; Scope = 'Equipo'
        Description = 'Apagar pasa a ser un apagado real: evita problemas con actualizaciones, controladores y arranque dual. El arranque tarda unos segundos más.'
        Test = { Test-CfgReg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0 }
        Apply = { Set-CfgReg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0 } }
    @{ Id = 'game-mode'; Name = 'Activar Modo de juego'; Category = 'Gaming'; Scope = 'Usuario'
        Description = 'Windows prioriza el juego en primer plano y pospone actualizaciones durante la partida.'
        Test = { Test-CfgReg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1 }
        Apply = { Set-CfgReg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1; Set-CfgReg 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1 } }
    @{ Id = 'hags'; Name = 'Programación de GPU acelerada por hardware'; Category = 'Gaming'; Scope = 'Equipo'
        Description = 'Reduce latencia y uso de CPU con gráficas NVIDIA GTX 10xx+/AMD RX 5000+. Necesaria para DLSS Frame Generation. Requiere reiniciar.'
        Test = { Test-CfgReg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 }
        Apply = { Set-CfgReg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 } }
    @{ Id = 'gamedvr-off'; Name = 'Desactivar grabación en segundo plano (Game DVR)'; Category = 'Gaming'; Scope = 'Usuario'
        Description = 'Evita que Xbox Game Bar grabe continuamente los últimos minutos de juego (consume GPU y disco). No usar si grabas con Game Bar.'
        Test = { Test-CfgReg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0 }
        Apply = { Set-CfgReg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0; Set-CfgReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0 } }
    @{ Id = 'mouse-accel-off'; Name = 'Desactivar aceleración del ratón'; Category = 'Gaming'; Scope = 'Usuario'
        Description = 'Movimiento 1:1 del ratón ("Mejorar precisión del puntero" desactivado). Preferido en juegos de disparos.'
        Test = { Test-CfgReg 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' }
        Apply = { Set-CfgReg 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' 'String'; Set-CfgReg 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' 'String'; Set-CfgReg 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' 'String' } }
    @{ Id = 'file-ext'; Name = 'Mostrar extensiones de archivo'; Category = 'Explorador'; Scope = 'Usuario'
        Description = 'Muestra .exe, .pdf, .docx... Ayuda a detectar adjuntos maliciosos como "factura.pdf.exe".'
        Test = { Test-CfgReg $script:Adv 'HideFileExt' 0 }
        Apply = { Set-CfgReg $script:Adv 'HideFileExt' 0 } }
    @{ Id = 'hidden-files'; Name = 'Mostrar archivos ocultos'; Category = 'Explorador'; Scope = 'Usuario'
        Description = 'Útil para soporte técnico (AppData, ProgramData).'
        Test = { Test-CfgReg $script:Adv 'Hidden' 1 }
        Apply = { Set-CfgReg $script:Adv 'Hidden' 1 } }
    @{ Id = 'explorer-thispc'; Name = 'El Explorador abre "Este equipo"'; Category = 'Explorador'; Scope = 'Usuario'
        Description = 'En lugar de Inicio/Acceso rápido.'
        Test = { Test-CfgReg $script:Adv 'LaunchTo' 1 }
        Apply = { Set-CfgReg $script:Adv 'LaunchTo' 1 } }
    @{ Id = 'taskbar-left'; Name = 'Botón Inicio a la izquierda'; Category = 'Explorador'; Scope = 'Usuario'
        Description = 'Barra de tareas alineada a la izquierda, como en Windows 10.'
        Test = { Test-CfgReg $script:Adv 'TaskbarAl' 0 }
        Apply = { Set-CfgReg $script:Adv 'TaskbarAl' 0 } }
    @{ Id = 'no-ads'; Name = 'Quitar sugerencias y anuncios de Windows'; Category = 'Privacidad'; Scope = 'Usuario'
        Description = 'Desactiva apps sugeridas, recomendaciones en Inicio, consejos y la reinstalación silenciosa de apps promocionadas.'
        Test = { Test-CfgReg $script:Cdm 'SilentInstalledAppsEnabled' 0 }
        Apply = {
            foreach ($n in 'SilentInstalledAppsEnabled', 'SystemPaneSuggestionsEnabled', 'SoftLandingEnabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled', 'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled', 'PreInstalledAppsEnabled', 'OemPreInstalledAppsEnabled') { Set-CfgReg $script:Cdm $n 0 }
            Set-CfgReg $script:Adv 'Start_IrisRecommendations' 0
            Set-CfgReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1 } }
    @{ Id = 'no-web-search'; Name = 'Búsqueda de Inicio sin resultados web'; Category = 'Privacidad'; Scope = 'Usuario'
        Description = 'La búsqueda de Windows solo muestra resultados locales (más rápida y privada).'
        Test = { Test-CfgReg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1 }
        Apply = { Set-CfgReg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1 } }
    @{ Id = 'telemetry-min'; Name = 'Telemetría mínima (datos obligatorios)'; Category = 'Privacidad'; Scope = 'Equipo'
        Description = 'Envía a Microsoft solo los diagnósticos obligatorios.'
        Test = { Test-CfgReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 1 }
        Apply = { Set-CfgReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 1 } }
    @{ Id = 'restore-on'; Name = 'Activar protección del sistema'; Category = 'Seguridad'; Scope = 'Equipo'
        Description = 'Habilita los puntos de restauración en la unidad del sistema (5 % del disco).'
        Test = { $null -ne (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -Name RPSessionInterval -ErrorAction SilentlyContinue) -and ((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore').RPSessionInterval -ge 1) }
        Apply = { Enable-ComputerRestore -Drive "$($env:SystemDrive)\"; & vssadmin.exe resize shadowstorage /for=$env:SystemDrive /on=$env:SystemDrive /maxsize=5% | Out-Null } }
    @{ Id = 'smartscreen-pua'; Name = 'Bloquear aplicaciones potencialmente no deseadas'; Category = 'Seguridad'; Scope = 'Equipo'
        Description = 'Microsoft Defender bloquea adware, mineros y bundles (PUA).'
        Test = { try { (Get-MpPreference -ErrorAction Stop).PUAProtection -eq 1 } catch { $false } }
        Apply = { Set-MpPreference -PUAProtection Enabled } }
    @{ Id = 'rdp-on'; Name = 'Habilitar Escritorio remoto'; Category = 'Administración'; Scope = 'Equipo'
        Description = 'Permite conexiones RDP con autenticación a nivel de red (NLA) y abre la regla del firewall. Requiere Windows Pro o superior.'
        Test = { Test-CfgReg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections' 0 }
        Apply = {
            Set-CfgReg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections' 0
            Set-CfgReg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' 'UserAuthentication' 1
            Enable-NetFirewallRule -Group '@FirewallAPI.dll,-28752' -ErrorAction SilentlyContinue } }
    @{ Id = 'sudo-on'; Name = 'Habilitar sudo para Windows'; Category = 'Administración'; Scope = 'Equipo'
        Description = 'Permite ejecutar comandos elevados con "sudo" desde la terminal (Windows 11 24H2+).'
        Test = { Test-CfgReg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Sudo' 'Enabled' 3 }
        Apply = { Set-CfgReg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Sudo' 'Enabled' 3 } }
)

function Get-CfgTweaks {
    foreach ($t in $script:Tweaks) {
        $applied = $false
        try { $applied = [bool](& $t.Test) } catch { }
        [pscustomobject]@{ Id = $t.Id; Name = $t.Name; Category = $t.Category; Scope = $t.Scope; Description = $t.Description; Applied = $applied }
    }
}

function Invoke-CfgTweaks {
    param([Parameter(Mandatory)][string[]]$Ids)
    foreach ($id in $Ids) {
        $t = $script:Tweaks | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        if (-not $t) { Write-CfgLog "Ajuste '$id' desconocido." WARN; continue }
        try {
            & $t.Apply
            Write-CfgLog "Ajuste aplicado: $($t.Name)" OK
            New-CfgResult -Id $id -Name $t.Name -Action 'Ajuste' -Success $true -Message 'Aplicado'
        }
        catch {
            Write-CfgLog "No se pudo aplicar '$($t.Name)': $($_.Exception.Message)" ERROR
            New-CfgResult -Id $id -Name $t.Name -Action 'Ajuste' -Success $false -Message $_.Exception.Message
        }
    }
    Write-CfgLog 'Algunos ajustes del Explorador se ven tras cerrar sesión; los de GPU y energía tras reiniciar.'
}

Export-ModuleMember -Function *
