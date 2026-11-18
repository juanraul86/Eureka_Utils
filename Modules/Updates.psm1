# Updates.psm1 - Actualizaciones con winget (lista, seleccionadas, todas)

function ConvertFrom-CfgWingetTable {
    <# Convierte las tablas de texto de winget (cualquier idioma) en objetos usando
       la posición de las columnas de la cabecera situada sobre la línea de guiones. #>
    param([string[]]$Lines)
    $rows = New-Object System.Collections.Generic.List[object]
    $starts = $null
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $l = $Lines[$i]
        if ($l -match '^-{10,}\s*$') {
            $header = $Lines[$i - 1]
            $starts = @([regex]::Matches($header, '\S+') | ForEach-Object { $_.Index })
            continue
        }
        if (-not $starts -or $starts.Count -lt 4) { continue }
        if ([string]::IsNullOrWhiteSpace($l) -or $l.Length -le $starts[2]) { $starts = $null; continue }
        $cut = {
            param($k)
            $a = $starts[$k]
            if ($a -ge $l.Length) { return '' }
            $b = if ($k + 1 -lt $starts.Count) { [math]::Min($starts[$k + 1], $l.Length) } else { $l.Length }
            return $l.Substring($a, $b - $a).Trim()
        }
        $id = & $cut 1
        if (-not $id -or $id -match '\s') { continue }
        $rows.Add([pscustomobject]@{
                Name      = (& $cut 0)
                Id        = $id
                Version   = (& $cut 2)
                Available = $(if ($starts.Count -ge 5) { & $cut 3 } else { '' })
                Source    = $(if ($starts.Count -ge 5) { & $cut 4 } else { & $cut 3 })
            })
    }
    return $rows.ToArray()
}

function Get-CfgWingetUpgrades {
    param([switch]$IncludeUnknown)
    $winget = Confirm-CfgWinget
    if (-not $winget) { return @() }
    Write-CfgLog 'Buscando actualizaciones con winget...' STEP
    $wgArgs = @('upgrade', '--accept-source-agreements', '--disable-interactivity')
    if ($IncludeUnknown) { $wgArgs += '--include-unknown' }
    $prev = $null
    try { $prev = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
    $lines = @(& $winget @wgArgs 2>$null | ForEach-Object { ("$_" -split "`r")[-1] })
    if ($prev) { try { [Console]::OutputEncoding = $prev } catch { } }
    $list = @(ConvertFrom-CfgWingetTable -Lines $lines | Where-Object { $_.Available })
    Write-CfgLog ("{0} actualizaciones disponibles." -f $list.Count) $(if ($list.Count) { 'WARN' } else { 'OK' })
    foreach ($u in $list) { Write-CfgLog ('   {0} ({1}): {2} -> {3}' -f $u.Name, $u.Id, $u.Version, $u.Available) }
    return $list
}

function Update-CfgWingetPackages {
    param([string[]]$Ids, [switch]$All, [switch]$IncludeUnknown)
    $common = @('--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
    if ($All) {
        Write-CfgLog 'Actualizando todas las aplicaciones (winget upgrade --all)...' STEP
        $a = @('upgrade', '--all') + $common
        if ($IncludeUnknown) { $a += '--include-unknown' }
        $info = Get-CfgExitInfo -Code (Invoke-CfgWinget -Arguments $a)
        Write-CfgLog "Actualización general: $($info.Message)" $(if ($info.Success) { 'OK' } else { 'WARN' })
        return (New-CfgResult -Id 'upgrade-all' -Name 'Actualizar todo' -Action 'Actualizar' -Success $info.Success -Message $info.Message)
    }
    foreach ($id in $Ids) {
        Write-CfgLog "Actualizando $id..." STEP
        $info = Get-CfgExitInfo -Code (Invoke-CfgWinget -Arguments (@('upgrade', '--id', $id, '--exact') + $common))
        Write-CfgLog "${id}: $($info.Message)" $(if ($info.Success) { 'OK' } else { 'ERROR' })
        New-CfgResult -Id $id -Name $id -Action 'Actualizar' -Success $info.Success -Message $info.Message
    }
}

function Get-CfgPackageLinks {
    <# Enlaces de descarga de un paquete según winget show (salida en español o inglés).
       Devuelve Download (instalador), Homepage, Publisher, ReleaseNotes y Best (el más útil). #>
    param([Parameter(Mandatory)][string]$Id, [string]$Source = 'winget')
    $winget = Get-CfgWingetPath
    $r = [ordered]@{ Id = $Id; Download = $null; Homepage = $null; Publisher = $null; ReleaseNotes = $null; Sha256 = $null; Best = $null }
    if ($winget) {
        $prev = $null
        try { $prev = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
        $lines = @(& $winget show --id $Id --exact --source $Source --accept-source-agreements --disable-interactivity 2>$null)
        if ($prev) { try { [Console]::OutputEncoding = $prev } catch { } }
        foreach ($l in $lines) {
            $h = [regex]::Match("$l", '(?i)sha256\s*:\s*([0-9a-f]{64})')
            if ($h.Success -and -not $r.Sha256) { $r.Sha256 = $h.Groups[1].Value.ToUpper() }
            $m = [regex]::Match("$l", '^\s*([^:]+?)\s*:\s*(https?://\S+)')
            if (-not $m.Success) { continue }
            $label = $m.Groups[1].Value.ToLower(); $url = $m.Groups[2].Value
            if ($label -match 'installer url|direcci.n url del instalador|url del instalador|instalador') { if (-not $r.Download) { $r.Download = $url } }
            elseif ($label -match 'release notes|notas de la versi') { if (-not $r.ReleaseNotes) { $r.ReleaseNotes = $url } }
            elseif ($label -match 'publisher|editor') { if (-not $r.Publisher) { $r.Publisher = $url } }
            elseif ($label -match 'homepage|p.gina principal|inicio') { if (-not $r.Homepage) { $r.Homepage = $url } }
        }
    }
    if ($Source -eq 'msstore') { $r.Download = "ms-windows-store://pdp/?ProductId=$Id" }
    $r.Best = @($r.Download, $r.Homepage, $r.Publisher, $r.ReleaseNotes) | Where-Object { $_ } | Select-Object -First 1
    if (-not $r.Best) { $r.Best = "https://winget.run/search?query=$([uri]::EscapeDataString($Id))" }
    return [pscustomobject]$r
}

function Test-CfgUpdateResults {
    <# Comprueba de verdad qué se ha actualizado: vuelve a consultar winget y marca como fallida
       cualquier app que siga pendiente aunque el instalador devolviera éxito. #>
    param([Parameter(Mandatory)]$Before, [string[]]$Ids, [switch]$IncludeUnknown)
    Write-CfgLog 'Comprobando el resultado real de las actualizaciones...' STEP
    $after = @(Get-CfgWingetUpgrades -IncludeUnknown:$IncludeUnknown)
    $targets = @($Before | Where-Object { -not $Ids -or $Ids -contains $_.Id })
    $failed = foreach ($b in $targets) {
        $still = $after | Where-Object { $_.Id -eq $b.Id } | Select-Object -First 1
        if ($still) {
            $links = Get-CfgPackageLinks -Id $b.Id -Source $(if ($b.Source) { $b.Source } else { 'winget' })
            Write-CfgLog ("No se ha podido instalar la actualización de {0} ({1} -> {2}). Descarga manual: {3}{4}" -f $b.Name, $b.Version, $b.Available, $links.Best, $(if ($links.Sha256) { " · SHA-256 del instalador: $($links.Sha256)" } else { '' })) ERROR
            [pscustomobject]@{
                Name = $b.Name; Id = $b.Id; Version = $still.Version; Available = $b.Available
                Reason = 'La aplicación sigue con una actualización pendiente después de ejecutar el instalador.'
                Link = $links.Best; Download = $links.Download; Homepage = $links.Homepage; Sha256 = $links.Sha256
                UpdateFailure = $true
            }
        }
    }
    $failed = @($failed)
    $ok = $targets.Count - $failed.Count
    Write-CfgLog ('Verificación: {0} actualizadas correctamente, {1} sin actualizar.' -f $ok, $failed.Count) $(if ($failed.Count) { 'WARN' } else { 'OK' })
    return $failed
}

function Invoke-CfgVerifiedUpdate {
    <# Actualiza (selección o todo) y devuelve las fallidas con su enlace de descarga. #>
    param([string[]]$Ids, [switch]$All, [switch]$IncludeUnknown)
    $before = @(Get-CfgWingetUpgrades -IncludeUnknown:$IncludeUnknown)
    if (-not $before.Count) { Write-CfgLog 'No hay actualizaciones pendientes.' OK; return @() }
    if ($All) { Update-CfgWingetPackages -All -IncludeUnknown:$IncludeUnknown | Out-Null }
    else { Update-CfgWingetPackages -Ids $Ids | Out-Null }
    return @(Test-CfgUpdateResults -Before $before -Ids $(if ($All) { @() } else { $Ids }) -IncludeUnknown:$IncludeUnknown)
}

function Update-CfgWingetSources {
    Write-CfgLog 'Actualizando orígenes de winget...' STEP
    $code = Invoke-CfgWinget -Arguments @('source', 'update', '--disable-interactivity')
    return (New-CfgResult -Id 'sources' -Name 'Orígenes winget' -Action 'Actualizar' -Success ($code -eq 0) -Message "Código $code")
}

Export-ModuleMember -Function *
