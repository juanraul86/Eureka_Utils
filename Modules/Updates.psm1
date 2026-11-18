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

# ---------------------------------------------------------------- actualización de Eureka_Utils

$script:ReleaseApi = 'https://api.github.com/repos/juanraul86/Eureka_Utils/releases/latest'

function Get-CfgLatestRelease {
    <# Consulta la última release publicada en GitHub. Solo envía una petición anónima a la API
       pública (sin datos del equipo). Devuelve $null si no hay conexión. #>
    param([int]$TimeoutSec = 8)
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $r = Invoke-RestMethod -Uri $script:ReleaseApi -TimeoutSec $TimeoutSec -UseBasicParsing -Headers @{ 'User-Agent' = "Eureka_Utils/$(Get-CfgVersion)"; Accept = 'application/vnd.github+json' }
    }
    catch { Write-CfgLog "No se pudo comprobar si hay una versión nueva: $($_.Exception.Message)" WARN; return $null }
    $ver = $null
    if (-not [version]::TryParse(($r.tag_name -replace '^v', ''), [ref]$ver)) { return $null }
    $asset = @($r.assets | Where-Object { $_.name -eq 'Eureka_Utils_Portable.exe' }) | Select-Object -First 1
    $sha = $null
    if ($asset -and $asset.PSObject.Properties['digest'] -and "$($asset.digest)" -match '^sha256:([0-9a-fA-F]{64})$') { $sha = $matches[1].ToUpper() }
    # Huella publicada en las notas de la release (la tabla que genera el flujo de publicación)
    $notesSha = [regex]::Match("$($r.body)", 'Eureka_Utils_Portable\.exe`?\s*\|\s*`?([0-9A-Fa-f]{64})').Groups[1].Value.ToUpper()
    [pscustomobject]@{
        Version     = $ver
        Tag         = $r.tag_name
        Name        = $r.name
        Url         = $r.html_url
        Published   = $r.published_at
        IsNewer     = ($ver -gt [version](Get-CfgVersion))
        AssetUrl    = $(if ($asset) { $asset.browser_download_url } else { $null })
        AssetSizeMB = $(if ($asset) { [math]::Round($asset.size / 1MB, 1) } else { 0 })
        Sha256      = $sha
        NotesSha256 = $(if ($notesSha) { $notesSha } else { $null })
    }
}

function Save-CfgLatestRelease {
    <# Descarga Eureka_Utils_Portable.exe de la release y comprueba su SHA-256 con el que publica
       GitHub. Si no coincide, lo borra. No sustituye ni ejecuta nada. #>
    param([Parameter(Mandatory)]$Release, [string]$Folder = (Join-Path $env:USERPROFILE 'Downloads'))
    if (-not $Release.AssetUrl -or $Release.AssetUrl -notmatch '^https://github\.com/juanraul86/Eureka_Utils/releases/download/') {
        Write-CfgLog 'La release no tiene un ejecutable descargable de GitHub.' ERROR
        return (New-CfgResult -Id 'selfupdate' -Name 'Eureka_Utils' -Action 'Descargar' -Success $false -Message 'Sin ejecutable')
    }
    $expected = $Release.Sha256
    if (-not $expected) { $expected = $Release.NotesSha256 }
    if (-not $expected) {
        Write-CfgLog 'GitHub no publica la huella SHA-256 de este ejecutable: por seguridad no se descarga. Descárgalo a mano desde la página de la release.' ERROR
        return (New-CfgResult -Id 'selfupdate' -Name 'Eureka_Utils' -Action 'Descargar' -Success $false -Message 'Sin huella')
    }
    if ($Release.Sha256 -and $Release.NotesSha256 -and $Release.Sha256 -ne $Release.NotesSha256) {
        Write-CfgLog 'La huella del ejecutable no coincide con la de las notas de la release: no se descarga.' ERROR
        return (New-CfgResult -Id 'selfupdate' -Name 'Eureka_Utils' -Action 'Descargar' -Success $false -Message 'Huellas distintas')
    }
    if (-not (Test-Path $Folder)) { New-Item -ItemType Directory -Path $Folder -Force | Out-Null }
    $dest = Join-Path $Folder ('Eureka_Utils_Portable_{0}.exe' -f $Release.Version)
    $tmp = "$dest.part"
    Write-CfgLog "Descargando Eureka_Utils $($Release.Version) ($($Release.AssetSizeMB) MB)..." STEP
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $Release.AssetUrl -OutFile $tmp -UseBasicParsing -TimeoutSec 120 -Headers @{ 'User-Agent' = "Eureka_Utils/$(Get-CfgVersion)" }
        $hash = (Get-FileHash $tmp -Algorithm SHA256).Hash
        if ($hash -ne $expected) {
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            Write-CfgLog "La huella SHA-256 del archivo descargado ($hash) no coincide con la publicada ($expected): se ha borrado." ERROR
            return (New-CfgResult -Id 'selfupdate' -Name 'Eureka_Utils' -Action 'Descargar' -Success $false -Message 'Huella incorrecta')
        }
        Move-Item $tmp $dest -Force
        $sig = (Get-AuthenticodeSignature $dest).Status
        Write-CfgLog ("Eureka_Utils {0} descargado y verificado (SHA-256 {1}) en {2}. Firma digital: {3}. Cierra esta versión y abre la nueva." -f $Release.Version, $hash, $dest, $(if ($sig -eq 'Valid') { 'válida' } else { 'sin firmar' })) OK
        return (New-CfgResult -Id 'selfupdate' -Name 'Eureka_Utils' -Action 'Descargar' -Success $true -Message $dest)
    }
    catch {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        Write-CfgLog "No se pudo descargar la nueva versión: $($_.Exception.Message)" ERROR
        return (New-CfgResult -Id 'selfupdate' -Name 'Eureka_Utils' -Action 'Descargar' -Success $false -Message $_.Exception.Message)
    }
}

Export-ModuleMember -Function *
