# Software.psm1 - Catálogo, detección, dependencias, impacto e instalación de software

function Get-CfgSoftwareCatalog {
    return @((Get-CfgJson -Name 'software').software)
}

function Get-CfgSoftwareState {
    <# Devuelve un hashtable id -> versión instalada (o $null si no está instalado). #>
    param([Parameter(Mandatory)]$Catalog)
    $programs = @(Get-CfgInstalledPrograms)
    $appx     = @(Get-CfgAppxPackages)
    $result   = @{}
    $isAdmin  = Test-CfgAdmin
    # Características opcionales y capacidades (RSAT...) solo se pueden consultar como administrador
    $features = $null; $caps = @{}
    if ($isAdmin -and @($Catalog | Where-Object { $_.detect -and $_.detect.PSObject.Properties['feature'] }).Count) {
        try { $features = @(Get-WindowsOptionalFeature -Online -ErrorAction Stop | Where-Object { $_.State -eq 'Enabled' } | ForEach-Object { $_.FeatureName }) } catch { }
    }
    if ($isAdmin) {
        foreach ($pat in @($Catalog | Where-Object { $_.detect -and $_.detect.PSObject.Properties['capability'] } | ForEach-Object { $_.detect.capability } | Select-Object -Unique)) {
            try { $caps[$pat] = @(Get-WindowsCapability -Online -Name $pat -ErrorAction Stop | Where-Object { $_.State -eq 'Installed' }).Count } catch { }
        }
    }
    foreach ($item in $Catalog) {
        $found = $null
        $d = $item.detect
        if ($d) {
            if ($d.PSObject.Properties['displayName']) {
                foreach ($pat in @($d.displayName)) {
                    $m = $programs | Where-Object { $_.DisplayName -like $pat } | Select-Object -First 1
                    if ($m) { $found = $m.DisplayVersion; if (-not $found) { $found = 'instalado' }; break }
                }
            }
            if (-not $found -and $d.PSObject.Properties['appx']) {
                foreach ($pat in @($d.appx)) {
                    $a = $appx | Where-Object { $_.Name -like $pat } | Select-Object -First 1
                    if ($a) { $found = [string]$a.Version; break }
                }
            }
            if (-not $found -and $d.PSObject.Properties['feature'] -and $null -ne $features) {
                $all = @($d.feature)
                if (@($all | Where-Object { $features -contains $_ }).Count -eq $all.Count) { $found = 'activado' }
            }
            if (-not $found -and $d.PSObject.Properties['capability']) {
                foreach ($pat in @($d.capability)) { if ($caps[$pat]) { $found = 'instalado'; break } }
            }
            if (-not $found -and $d.PSObject.Properties['path']) {
                foreach ($pat in @($d.path)) {
                    if (Test-Path ([Environment]::ExpandEnvironmentVariables($pat))) { $found = 'instalado'; break }
                }
            }
        }
        $result[$item.id] = $found
    }
    return $result
}

function Resolve-CfgDependencies {
    <# Ordena la selección para que cada dependencia se instale antes que quien la necesita. #>
    param([Parameter(Mandatory)][string[]]$Ids, [Parameter(Mandatory)]$Catalog)
    $byId = @{}
    foreach ($i in $Catalog) { $byId[$i.id] = $i }
    $ordered  = New-Object System.Collections.Generic.List[string]
    $visiting = @{}
    $visit = $null
    $visit = {
        param($id)
        if ($ordered.Contains($id)) { return }
        if (-not $byId.ContainsKey($id)) { Write-CfgLog "La dependencia '$id' no existe en el catálogo." WARN; return }
        if ($visiting[$id]) { Write-CfgLog "Dependencia circular detectada en '$id'." WARN; return }
        $visiting[$id] = $true
        foreach ($dep in @($byId[$id].dependencies)) { if ($dep) { & $visit $dep } }
        $visiting[$id] = $false
        $ordered.Add($id)
    }
    foreach ($id in $Ids) { if ($id) { & $visit $id } }
    return $ordered.ToArray()
}

function Measure-CfgSoftwareImpact {
    <# Suma el impacto estimado (disco, RAM, arranque, servicios) de una lista de ids. #>
    param([string[]]$Ids, [Parameter(Mandatory)]$Catalog)
    $byId = @{}
    foreach ($i in $Catalog) { $byId[$i.id] = $i }
    $disk = 0; $ram = 0
    $startup = @(); $services = @(); $tasks = @(); $heavy = @()
    foreach ($id in @($Ids)) {
        $i = $byId[$id]
        if (-not $i -or -not $i.impact) { continue }
        $disk += [double]$i.impact.diskMB
        $ram  += [double]$i.impact.ramMB
        if ($i.impact.startup) { $startup += $i.name }
        $services += @($i.impact.services)
        $tasks    += @($i.impact.scheduledTasks)
        if ($i.impact.cpu -eq 'Alto') { $heavy += $i.name }
    }
    [pscustomobject]@{
        Count    = @($Ids).Count
        DiskMB   = $disk
        RamMB    = $ram
        Startup  = @($startup)
        Services = @($services | Where-Object { $_ } | Select-Object -Unique)
        Tasks    = @($tasks | Where-Object { $_ } | Select-Object -Unique)
        Heavy    = @($heavy)
    }
}

function Test-CfgInstallerTrust {
    <# Un instalador local es de confianza si coincide su huella SHA-256 con la del catálogo o, si el
       catálogo no la indica, si tiene una firma digital válida. También exige que esté dentro de Eureka_Utils. #>
    param([Parameter(Mandatory)][string]$Path, $Item)
    $root = (Resolve-Path (Get-CfgRoot)).Path.TrimEnd('\') + '\'
    $full = (Resolve-Path $Path).Path
    if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{ Trusted = $false; Reason = "La ruta del instalador sale de la carpeta de Eureka_Utils ($full)." }
    }
    $hash = (Get-FileHash -Path $full -Algorithm SHA256).Hash
    if ($Item -and $Item.PSObject.Properties['sha256'] -and $Item.sha256) {
        if ($hash -ieq $Item.sha256) { return [pscustomobject]@{ Trusted = $true; Reason = "huella SHA-256 correcta ($hash)" } }
        return [pscustomobject]@{ Trusted = $false; Reason = "La huella SHA-256 no coincide con el catálogo (esperada $($Item.sha256), obtenida $hash): el archivo puede estar alterado." }
    }
    $sig = Get-AuthenticodeSignature -FilePath $full
    if ($sig.Status -eq 'Valid') { return [pscustomobject]@{ Trusted = $true; Reason = "firma digital válida de $($sig.SignerCertificate.Subject)" } }
    return [pscustomobject]@{ Trusted = $false; Reason = "No tiene firma digital válida ($($sig.Status)) y el catálogo no indica su huella. Añade ""sha256"": ""$hash"" a su entrada en Catalog\software.json si confías en él." }
}

function Install-CfgSoftwareItem {
    param([Parameter(Mandatory)]$Item)
    Write-CfgLog "Instalando $($Item.name)..." STEP
    $code = -1
    if ($Item.PSObject.Properties['requiresPro'] -and $Item.requiresPro) {
        $ed = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
        if ($ed -match '^Core') {
            Write-CfgLog "$($Item.name) requiere Windows Pro, Enterprise o Education (este equipo: $ed)." ERROR
            return (New-CfgResult -Id $Item.id -Name $Item.name -Action 'Instalar' -Success $false -Message 'Requiere Windows Pro')
        }
    }
    try {
        switch ($Item.source) {
            'feature' {
                $restart = $false; $fail = $false
                foreach ($f in @($Item.features)) {
                    try {
                        $r = Enable-WindowsOptionalFeature -Online -FeatureName $f -All -NoRestart -ErrorAction Stop
                        if ($r.RestartNeeded) { $restart = $true }
                        Write-CfgLog "   Característica activada: $f" OK
                    }
                    catch { Write-CfgLog "   No se pudo activar ${f}: $($_.Exception.Message)" ERROR; $fail = $true }
                }
                $code = if ($fail) { 1 } elseif ($restart) { 3010 } else { 0 }
            }
            'capability' {
                $fail = $false
                foreach ($c in @($Item.capabilities)) {
                    try {
                        Write-CfgLog "   Añadiendo $c (descarga desde Windows Update)..."
                        Add-WindowsCapability -Online -Name $c -ErrorAction Stop | Out-Null
                        Write-CfgLog "   Instalada: $c" OK
                    }
                    catch { Write-CfgLog "   No se pudo instalar ${c}: $($_.Exception.Message). En equipos con WSUS hay que permitir descargar características desde Windows Update." ERROR; $fail = $true }
                }
                $code = if ($fail) { 1 } else { 0 }
            }
            'url' {
                Write-CfgLog "$($Item.name) no está en winget: se abre la página oficial de descarga ($($Item.url)). Instálalo manualmente y pulsa 'Volver a detectar'." WARN
                Start-Process $Item.url
                return (New-CfgResult -Id $Item.id -Name $Item.name -Action 'Instalar' -Success $true -Message 'Descarga manual abierta en el navegador')
            }
            'winget' {
                $wgArgs = @('install', '--id', $Item.packageId, '--exact', '--source', 'winget', '--silent',
                            '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
                if ($Item.PSObject.Properties['scope'] -and $Item.scope) { $wgArgs += @('--scope', $Item.scope) }
                $code = Invoke-CfgWinget -Arguments $wgArgs
            }
            'msstore' {
                $code = Invoke-CfgWinget -Arguments @('install', '--id', $Item.packageId, '--source', 'msstore', '--silent',
                                                      '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
            }
            'local' {
                $path = Join-Path (Get-CfgRoot) $Item.localPath
                if (-not (Test-Path $path)) {
                    Write-CfgLog "No se encuentra el instalador local: $path (consulta Packages\LEEME.txt)" ERROR
                    return (New-CfgResult -Id $Item.id -Name $Item.name -Action 'Instalar' -Success $false -Message 'Instalador local no encontrado')
                }
                # Seguridad: el instalador se ejecuta como administrador, así que antes se comprueba
                # su huella SHA-256 (campo "sha256" del catálogo) o, si no la hay, su firma digital.
                $trust = Test-CfgInstallerTrust -Path $path -Item $Item
                if (-not $trust.Trusted) {
                    Write-CfgLog "$($Item.name): no se instala por seguridad. $($trust.Reason)" ERROR
                    return (New-CfgResult -Id $Item.id -Name $Item.name -Action 'Instalar' -Success $false -Message $trust.Reason)
                }
                Write-CfgLog "   Instalador verificado: $($trust.Reason)" OK
                $pkgDir  = Split-Path -Parent $path
                $argLine = ''
                if ($Item.PSObject.Properties['installArgs'] -and $Item.installArgs) { $argLine = $Item.installArgs.Replace('{pkgdir}', $pkgDir) }
                if ([IO.Path]::GetExtension($path) -eq '.msi') {
                    $p = Start-Process -FilePath (Get-CfgSystemExe 'msiexec.exe') -ArgumentList ("/i `"$path`" /qn /norestart $argLine").Trim() -Wait -PassThru
                }
                elseif ($argLine) {
                    $p = Start-Process -FilePath $path -ArgumentList $argLine -WorkingDirectory $pkgDir -Wait -PassThru
                }
                else {
                    $p = Start-Process -FilePath $path -WorkingDirectory $pkgDir -Wait -PassThru
                }
                $code = $p.ExitCode
            }
            default { throw "Origen desconocido '$($Item.source)'" }
        }
    }
    catch {
        Write-CfgLog "Error instalando $($Item.name): $($_.Exception.Message)" ERROR
        return (New-CfgResult -Id $Item.id -Name $Item.name -Action 'Instalar' -Success $false -Message $_.Exception.Message)
    }
    $info = Get-CfgExitInfo -Code $code
    Write-CfgLog "$($Item.name): $($info.Message)" $(if ($info.Success) { 'OK' } else { 'ERROR' })
    return (New-CfgResult -Id $Item.id -Name $Item.name -Action 'Instalar' -Success $info.Success -Message $info.Message)
}

function Uninstall-CfgSoftwareItem {
    param([Parameter(Mandatory)]$Item)
    Write-CfgLog "Desinstalando $($Item.name)..." STEP
    if ($Item.source -in @('winget', 'msstore')) {
        $code = Invoke-CfgWinget -Arguments @('uninstall', '--id', $Item.packageId, '--exact', '--silent',
                                              '--accept-source-agreements', '--disable-interactivity')
        $info = Get-CfgExitInfo -Code $code
        Write-CfgLog "$($Item.name): $($info.Message)" $(if ($info.Success) { 'OK' } else { 'ERROR' })
        return (New-CfgResult -Id $Item.id -Name $Item.name -Action 'Desinstalar' -Success $info.Success -Message $info.Message)
    }
    if ($Item.source -eq 'feature') {
        $ok = $true
        foreach ($f in @($Item.features)) { try { Disable-WindowsOptionalFeature -Online -FeatureName $f -NoRestart -ErrorAction Stop | Out-Null; Write-CfgLog "   Desactivada: $f" OK } catch { $ok = $false; Write-CfgLog "   ${f}: $($_.Exception.Message)" ERROR } }
        return (New-CfgResult -Id $Item.id -Name $Item.name -Action 'Desinstalar' -Success $ok -Message $(if ($ok) { 'Desactivada (reinicio pendiente)' } else { 'Error' }))
    }
    if ($Item.source -eq 'capability') {
        $ok = $true
        foreach ($c in @($Item.capabilities)) { try { Remove-WindowsCapability -Online -Name $c -ErrorAction Stop | Out-Null; Write-CfgLog "   Quitada: $c" OK } catch { $ok = $false; Write-CfgLog "   ${c}: $($_.Exception.Message)" ERROR } }
        return (New-CfgResult -Id $Item.id -Name $Item.name -Action 'Desinstalar' -Success $ok -Message $(if ($ok) { 'Quitada' } else { 'Error' }))
    }
    # Paquetes locales y descargas manuales: se busca su entrada en el registro
    $programs = @(Get-CfgInstalledPrograms)
    $ok = $false
    foreach ($pat in @($Item.detect.displayName)) {
        foreach ($prog in @($programs | Where-Object { $_.DisplayName -like $pat })) { $ok = (Invoke-CfgRegistryUninstall -Program $prog) -or $ok }
    }
    return (New-CfgResult -Id $Item.id -Name $Item.name -Action 'Desinstalar' -Success $ok -Message $(if ($ok) { 'Correcto' } else { 'No desinstalado' }))
}

function Install-CfgSoftwareSet {
    <# Instala una selección resolviendo dependencias y omitiendo lo ya instalado. #>
    param([Parameter(Mandatory)][string[]]$Ids)
    $catalog = Get-CfgSoftwareCatalog
    $byId = @{}
    foreach ($i in $catalog) { $byId[$i.id] = $i }
    if ($Ids -contains '@gpu') {
        $Ids = @(Resolve-CfgHardwareSoftware -Ids $Ids)
        Write-CfgLog ('Controladores según la gráfica detectada: {0}' -f $(if (@($Ids | Where-Object { $_ -in @('nvidia-app', 'amd-adrenalin', 'intel-dsa') }).Count) { ($Ids | Where-Object { $_ -in @('nvidia-app', 'amd-adrenalin', 'intel-dsa') }) -join ', ' } else { 'ninguno necesario' }))
    }
    $order = @(Resolve-CfgDependencies -Ids $Ids -Catalog $catalog)
    $extra = @($order | Where-Object { $Ids -notcontains $_ })
    if ($extra.Count) { Write-CfgLog ('Se añaden dependencias necesarias: {0}' -f (($extra | ForEach-Object { $byId[$_].name }) -join ', ')) }
    $state = Get-CfgSoftwareState -Catalog $catalog
    $results = foreach ($id in $order) {
        $item = $byId[$id]
        if ($state[$id]) {
            Write-CfgLog "$($item.name) ya está instalado ($($state[$id])). Se omite."
            New-CfgResult -Id $id -Name $item.name -Action 'Instalar' -Success $true -Message 'Ya instalado'
            continue
        }
        Install-CfgSoftwareItem -Item $item
    }
    # Para lo que no se pudo instalar, añade el enlace de descarga manual
    foreach ($r in @($results | Where-Object { -not $_.Success })) {
        $it = $byId[$r.Id]
        $link = $null
        if ($it -and $it.source -in @('winget', 'msstore')) { $link = (Get-CfgPackageLinks -Id $it.packageId -Source $it.source).Best }
        elseif ($it -and $it.PSObject.Properties['url']) { $link = $it.url }
        if ($link) {
            $r | Add-Member -NotePropertyName Link -NotePropertyValue $link -Force
            Write-CfgLog "No se ha podido instalar $($r.Name). Descarga manual: $link" ERROR
        }
    }
    $fail = @($results | Where-Object { -not $_.Success }).Count
    Write-CfgLog ('Instalación terminada: {0} correctas, {1} con error.' -f (@($results).Count - $fail), $fail) $(if ($fail) { 'WARN' } else { 'OK' })
    return $results
}

function Uninstall-CfgSoftwareSet {
    param([Parameter(Mandatory)][string[]]$Ids)
    $catalog = Get-CfgSoftwareCatalog
    $results = foreach ($id in $Ids) {
        $item = $catalog | Where-Object { $_.id -eq $id } | Select-Object -First 1
        if (-not $item) { continue }
        $dependants = @($catalog | Where-Object { @($_.dependencies) -contains $id } | ForEach-Object { $_.name })
        if ($dependants.Count) { Write-CfgLog ("Aviso: {0} es dependencia de {1}; esas aplicaciones podrían dejar de funcionar." -f $item.name, ($dependants -join ', ')) WARN }
        Uninstall-CfgSoftwareItem -Item $item
    }
    return $results
}

Export-ModuleMember -Function *
