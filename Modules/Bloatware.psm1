# Bloatware.psm1 - Detección y eliminación de aplicaciones preinstaladas

function Get-CfgBloatwareCatalog {
    return @((Get-CfgJson -Name 'bloatware').bloatware)
}

function Resolve-CfgBloatwareIds {
    <# Expande el comodín '@recommended' a los elementos marcados como recomendados. #>
    param([string[]]$Ids, [string[]]$Keep = @())
    $catalog = Get-CfgBloatwareCatalog
    $out = foreach ($id in $Ids) {
        if ($id -in @('@recommended', '@recomendado')) { $catalog | Where-Object { $_.recommended } | ForEach-Object { $_.id } }
        else { $id }
    }
    return @($out | Where-Object { $_ -and $Keep -notcontains $_ } | Select-Object -Unique)
}

function Get-CfgBloatwareState {
    param([Parameter(Mandatory)]$Catalog)
    $appx = @(Get-CfgAppxPackages)
    $prov = @()
    if (Test-CfgAdmin) { try { $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop) } catch { } }
    $programs = @(Get-CfgInstalledPrograms)
    foreach ($b in $Catalog) {
        $installed = @(); $provisioned = @()
        if ($b.type -eq 'appx') {
            $installed   = @($appx | Where-Object { $_.Name -like $b.pattern })
            $provisioned = @($prov | Where-Object { $_.DisplayName -like $b.pattern })
        }
        else {
            $installed = @($programs | Where-Object { $_.DisplayName -like $b.pattern })
        }
        $restorable = ($b.type -eq 'appx') -and ($provisioned.Count -gt 0 -or ($b.PSObject.Properties['storeId'] -and $b.storeId))
        $status = if ($installed.Count -and $provisioned.Count) { 'Presente + aprovisionado' }
                  elseif ($installed.Count) { 'Presente' }
                  elseif ($provisioned.Count) { 'Solo aprovisionado' }
                  elseif ($restorable) { 'No presente · reinstalable' }
                  else { 'No presente' }
        [pscustomobject]@{
            Id          = $b.id
            Present     = ($installed.Count -gt 0 -or $provisioned.Count -gt 0)
            Installed   = ($installed.Count -gt 0)
            Restorable  = [bool]$restorable
            Status      = $status
        }
    }
}

function Remove-CfgBloatware {
    param(
        [Parameter(Mandatory)][string[]]$Ids,
        [switch]$IncludeProvisioned
    )
    $catalog = Get-CfgBloatwareCatalog
    $isAdmin = Test-CfgAdmin
    if (-not $isAdmin) { Write-CfgLog 'Sin privilegios de administrador solo se quitará para el usuario actual.' WARN }
    $prov = @()
    if ($IncludeProvisioned -and $isAdmin) { try { $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop) } catch { } }

    foreach ($id in (Resolve-CfgBloatwareIds -Ids $Ids)) {
        $b = $catalog | Where-Object { $_.id -eq $id } | Select-Object -First 1
        if (-not $b) { Write-CfgLog "'$id' no existe en el catálogo de bloatware." WARN; continue }
        Write-CfgLog "Quitando $($b.name)..." STEP
        $ok = $true; $done = 0
        if ($b.type -eq 'appx') {
            $pkgs = if ($isAdmin) { @(Get-AppxPackage -AllUsers -Name $b.pattern -ErrorAction SilentlyContinue) } else { @(Get-AppxPackage -Name $b.pattern -ErrorAction SilentlyContinue) }
            foreach ($p in $pkgs) {
                try {
                    if ($isAdmin) { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop }
                    else { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop }
                    Write-CfgLog "   Eliminado $($p.PackageFullName)" OK; $done++
                }
                catch { Write-CfgLog "   No se pudo eliminar $($p.PackageFullName): $($_.Exception.Message)" ERROR; $ok = $false }
            }
            if ($IncludeProvisioned) {
                foreach ($pp in @($prov | Where-Object { $_.DisplayName -like $b.pattern })) {
                    try {
                        Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction Stop | Out-Null
                        Write-CfgLog "   Retirado del aprovisionamiento (no se instalará a nuevos usuarios): $($pp.PackageName)" OK; $done++
                    }
                    catch { Write-CfgLog "   No se pudo retirar del aprovisionamiento $($pp.PackageName): $($_.Exception.Message)" ERROR; $ok = $false }
                }
            }
        }
        else {
            foreach ($prog in @(Get-CfgInstalledPrograms | Where-Object { $_.DisplayName -like $b.pattern })) {
                if (Invoke-CfgRegistryUninstall -Program $prog) { $done++ } else { $ok = $false }
            }
        }
        if ($done -eq 0 -and $ok) { Write-CfgLog "   $($b.name) no estaba presente." }
        New-CfgResult -Id $b.id -Name $b.name -Action 'Quitar' -Success $ok -Message $(if ($done) { "$done elemento(s) quitados" } elseif ($ok) { 'No presente' } else { 'Error' })
    }
}

function Restore-CfgBloatware {
    <# Vuelve a instalar apps quitadas: re-registra la copia aprovisionada si sigue en el equipo
       o la instala desde Microsoft Store (winget, origen msstore). #>
    param([Parameter(Mandatory)][string[]]$Ids)
    $catalog = Get-CfgBloatwareCatalog
    $prov = @()
    try { $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop) } catch { }
    foreach ($id in $Ids) {
        $b = $catalog | Where-Object { $_.id -eq $id } | Select-Object -First 1
        if (-not $b) { continue }
        Write-CfgLog "Reinstalando $($b.name)..." STEP
        if ($b.type -ne 'appx') {
            Write-CfgLog "   $($b.name) es software de fabricante: descárgalo desde su web si lo necesitas." WARN
            New-CfgResult -Id $id -Name $b.name -Action 'Reinstalar' -Success $false -Message 'No reinstalable automáticamente'
            continue
        }
        $p = $prov | Where-Object { $_.DisplayName -like $b.pattern } | Select-Object -First 1
        $done = $false
        if ($p -and $p.InstallLocation) {
            try {
                $manifest = [Environment]::ExpandEnvironmentVariables($p.InstallLocation)
                Add-AppxPackage -Register $manifest -DisableDevelopmentMode -ErrorAction Stop
                Write-CfgLog "   Re-registrada desde la copia aprovisionada." OK
                $done = $true
            }
            catch { Write-CfgLog "   No se pudo re-registrar: $($_.Exception.Message)" WARN }
        }
        if (-not $done -and $b.PSObject.Properties['storeId'] -and $b.storeId) {
            $info = Get-CfgExitInfo -Code (Invoke-CfgWinget -Arguments @('install', '--id', $b.storeId, '--source', 'msstore', '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'))
            Write-CfgLog "   $($b.name): $($info.Message)" $(if ($info.Success) { 'OK' } else { 'ERROR' })
            $done = $info.Success
        }
        if (-not $done -and -not ($b.PSObject.Properties['storeId'] -and $b.storeId)) {
            Write-CfgLog "   Sin identificador de Store: se abre la búsqueda en Microsoft Store." WARN
            Start-Process ("ms-windows-store://search/?query={0}" -f [uri]::EscapeDataString($b.name))
        }
        New-CfgResult -Id $id -Name $b.name -Action 'Reinstalar' -Success $done -Message $(if ($done) { 'Reinstalada' } else { 'Pendiente / manual' })
    }
}

Export-ModuleMember -Function *
