# Profiles.psm1 - Perfiles de configuración (secuencias tipo "task sequence")

function Get-CfgProfiles {
    return @((Get-CfgJson -Name 'profiles').profiles)
}

function Get-CfgProfileBloatwareIds {
    param([Parameter(Mandatory)]$ProfileItem)
    if (-not $ProfileItem.bloatware) { return @() }
    $keep = @()
    if ($ProfileItem.PSObject.Properties['keepBloatware']) { $keep = @($ProfileItem.keepBloatware) }
    return @(Resolve-CfgBloatwareIds -Ids @($ProfileItem.bloatware) -Keep $keep)
}

function Get-CfgProfileTweaks {
    param([Parameter(Mandatory)]$ProfileItem)
    if ($ProfileItem.PSObject.Properties['tweaks']) { return @($ProfileItem.tweaks) }
    return @()
}

function Invoke-CfgProfile {
    param([Parameter(Mandatory)][string]$Name, [switch]$NoRestorePoint, [switch]$PostInstall)
    $p = Get-CfgProfiles | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if (-not $p) {
        Write-CfgLog ("El perfil '{0}' no existe. Disponibles: {1}" -f $Name, ((Get-CfgProfiles | ForEach-Object { $_.name }) -join ', ')) ERROR
        return (New-CfgResult -Id 'profile' -Name $Name -Action 'Perfil' -Success $false -Message 'No existe')
    }
    Write-CfgLog "=== Aplicando perfil '$($p.name)' ===" STEP
    if ($PostInstall) {
        # Recién instalado Windows: hay que esperar a la red y a que winget se registre
        if (-not (Wait-CfgNetwork -Minutes 10)) { Write-CfgLog 'Sin Internet: se aplicarán solo los pasos locales (bloatware y ajustes).' WARN }
        Wait-CfgWinget -Minutes 10 | Out-Null
    }
    if ($p.restorePoint -and -not $NoRestorePoint) { New-CfgRestorePoint -Description "Eureka_Utils - perfil $($p.name)" | Out-Null }

    $bw = Get-CfgProfileBloatwareIds -ProfileItem $p
    if ($bw.Count) { Remove-CfgBloatware -Ids $bw -IncludeProvisioned:([bool]$p.removeProvisioned) }
    $tw = Get-CfgProfileTweaks -ProfileItem $p
    if ($tw.Count) { Invoke-CfgTweaks -Ids $tw }
    if (@($p.software).Count) { Install-CfgSoftwareSet -Ids @($p.software) }
    if ($p.gpupdate -and (Get-CimInstance Win32_ComputerSystem).PartOfDomain) { Invoke-CfgGpUpdate }
    if ($p.intuneSync) { Invoke-CfgIntuneSync }
    if ($p.PSObject.Properties['upgradeAll'] -and $p.upgradeAll) { Update-CfgWingetPackages -All }
    Write-CfgLog "=== Perfil '$($p.name)' finalizado ===" OK
}

Export-ModuleMember -Function *
