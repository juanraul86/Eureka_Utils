# Run-Tests.ps1 - Pruebas automáticas de Eureka_Utils (sin dependencias: Windows PowerShell 5.1).
# Se ejecutan en GitHub Actions antes de compilar: si alguna falla, no se publica la release.
# Uso local:  powershell -NoProfile -ExecutionPolicy Bypass -File Tests\Run-Tests.ps1
# Solo leen: no instalan, no cambian ajustes ni requieren administrador.
param([string]$Root = (Split-Path $PSScriptRoot -Parent))

$ErrorActionPreference = 'Stop'
$script:Pass = 0; $script:Fail = New-Object System.Collections.Generic.List[string]

function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    try { & $Body; $script:Pass++; Write-Host "  OK    $Name" -ForegroundColor Green }
    catch { $script:Fail.Add("$Name -> $($_.Exception.Message)"); Write-Host "  FALLO $Name -> $($_.Exception.Message)" -ForegroundColor Red }
}
function Assert-True { param($Cond, [string]$Msg = 'Se esperaba verdadero') if (-not $Cond) { throw $Msg } }
function Assert-Equal { param($Expected, $Actual, [string]$What = 'valor') if ("$Expected" -cne "$Actual") { throw "$What`: se esperaba '$Expected' y se obtuvo '$Actual'" } }
function Assert-Empty { param($Items, [string]$What) $i = @($Items | Where-Object { $_ }); if ($i.Count) { throw "$What`: " + (($i | Select-Object -First 8) -join ' | ') + $(if ($i.Count -gt 8) { " (y $($i.Count - 8) más)" } else { '' }) } }

$CodeSkip = '\\(Dist|Docs|Logs|Exports|\.git|Eureka_Utils_Datos)\\'
Write-Host "Eureka_Utils - pruebas en $Root" -ForegroundColor Cyan

# ------------------------------------------------------------------ archivos
Write-Host 'Archivos'
$code = @(Get-ChildItem $Root -Recurse -File -Include *.ps1, *.psm1 | Where-Object { $_.FullName -notmatch $CodeSkip })
Test-Case 'Los scripts se analizan sin errores de sintaxis' {
    Assert-Empty ($code | ForEach-Object { $e = $null; [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$e); if ($e) { "$($_.Name): $($e[0].Message) (línea $($e[0].Extent.StartLineNumber))" } }) 'Errores'
}
Test-Case 'Los scripts con tildes llevan BOM UTF-8 (necesario en PowerShell 5.1)' {
    Assert-Empty ($code | ForEach-Object {
            $b = [IO.File]::ReadAllBytes($_.FullName)
            $bom = $b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF
            if (-not $bom -and @($b | Where-Object { $_ -ge 0x80 }).Count) { $_.Name }
        }) 'Sin BOM'
}
Test-Case 'La interfaz XAML se carga' {
    Add-Type -AssemblyName PresentationFramework
    [void][Windows.Markup.XamlReader]::Parse((Get-Content (Join-Path $Root 'UI\MainWindow.xaml') -Raw -Encoding UTF8))
}
Test-Case 'Los catálogos JSON son válidos' {
    foreach ($j in Get-ChildItem (Join-Path $Root 'Catalog') -Filter *.json) { $null = Get-Content $j.FullName -Raw -Encoding UTF8 | ConvertFrom-Json }
}
Test-Case 'Eureka_Utils.cmd es ASCII con finales CRLF' {
    $b = [IO.File]::ReadAllBytes((Join-Path $Root 'Eureka_Utils.cmd'))
    Assert-True (-not @($b | Where-Object { $_ -ge 0x80 }).Count) 'Contiene caracteres no ASCII'
    $lf = 0; $crlf = 0; for ($i = 0; $i -lt $b.Length; $i++) { if ($b[$i] -eq 10) { $lf++; if ($i -and $b[$i - 1] -eq 13) { $crlf++ } } }
    Assert-Equal $lf $crlf 'Saltos de línea CRLF'
}

# ------------------------------------------------------------------ módulos
foreach ($m in 'Core', 'Hardware', 'Software', 'Updates', 'Bloatware', 'Tweaks', 'Drivers', 'Profiles', 'Diagnostics') {
    Import-Module (Join-Path $Root "Modules\$m.psm1") -Force -DisableNameChecking
}
Set-CfgEnvironment -Root $Root -LogFile (Join-Path $env:TEMP 'eureka_tests.log') | Out-Null

# ------------------------------------------------------------------ catálogos
Write-Host 'Catálogos'
$sw = @(Get-CfgSoftwareCatalog)
$swIds = @{}; foreach ($i in $sw) { $swIds[$i.id] = $i }
Test-Case 'Software: identificadores únicos' {
    Assert-Empty ($sw | Group-Object id | Where-Object Count -gt 1 | ForEach-Object Name) 'Duplicados'
}
Test-Case 'Software: campos obligatorios y origen válido' {
    Assert-Empty ($sw | ForEach-Object {
            $miss = @('id', 'name', 'category', 'source', 'description', 'impact' | Where-Object { -not $_ -or -not $i })
            foreach ($f in 'id', 'name', 'category', 'source', 'description', 'impact') { if (-not $_.PSObject.Properties[$f] -or $null -eq $_.$f) { "$($_.id): falta $f" } }
            if ($_.source -notin 'winget', 'msstore', 'local', 'feature', 'capability', 'url') { "$($_.id): origen '$($_.source)'" }
            if ($_.source -in 'winget', 'msstore' -and -not $_.packageId) { "$($_.id): sin packageId" }
            if ($_.source -eq 'url' -and $_.url -notmatch '^https://') { "$($_.id): url no https" }
        }) 'Errores'
}
Test-Case 'Software: las dependencias existen y no hay ciclos' {
    Assert-Empty ($sw | ForEach-Object { $it = $_; @($it.dependencies) | Where-Object { $_ -and -not $swIds[$_] } | ForEach-Object { "$($it.id) -> $_" } }) 'Dependencias inexistentes'
    foreach ($i in $sw) { $null = Resolve-CfgDependencies -Ids @($i.id) -Catalog $sw }
    $log = Join-Path $env:TEMP 'eureka_tests.log'
    if (Test-Path $log) { Assert-True (-not (Select-String -Path $log -Pattern 'Dependencia circular' -Quiet)) 'Hay una dependencia circular' }
}
Test-Case 'Software: el orden de instalación pone las dependencias antes' {
    $withDeps = @($sw | Where-Object { @($_.dependencies | Where-Object { $_ }).Count } | Select-Object -First 1)
    if ($withDeps) {
        $order = @(Resolve-CfgDependencies -Ids @($withDeps[0].id) -Catalog $sw)
        foreach ($d in @($withDeps[0].dependencies)) { Assert-True ([array]::IndexOf($order, $d) -lt [array]::IndexOf($order, $withDeps[0].id)) "$d debería ir antes que $($withDeps[0].id)" }
    }
}
$bw = @(Get-CfgBloatwareCatalog)
$bwIds = @($bw | ForEach-Object id)
$twIds = @(Get-CfgTweaks | ForEach-Object Id)
Test-Case 'Bloatware: identificadores únicos' { Assert-Empty ($bw | Group-Object id | Where-Object Count -gt 1 | ForEach-Object Name) 'Duplicados' }
Test-Case 'Perfiles: todo lo que referencian existe' {
    Assert-Empty (Get-CfgProfiles | ForEach-Object {
            $p = $_
            @($p.software) | Where-Object { $_ -and $_ -ne '@gpu' -and -not $swIds[$_] } | ForEach-Object { "$($p.name): software '$_'" }
            @($p.bloatware) + @($p.keepBloatware) | Where-Object { $_ -and $_ -ne '@recommended' -and $bwIds -notcontains $_ } | ForEach-Object { "$($p.name): bloatware '$_'" }
            @($p.tweaks) | Where-Object { $_ -and $twIds -notcontains $_ } | ForEach-Object { "$($p.name): ajuste '$_'" }
        }) 'Referencias rotas'
}
Test-Case 'Herramientas OEM: Dell, HP y Lenovo tienen su herramienta' {
    foreach ($v in 'Dell', 'HP', 'Lenovo') { Assert-True (@($sw | Where-Object { $_.PSObject.Properties['oemVendor'] -and $_.oemVendor -eq $v }).Count) "Falta la herramienta de $v" }
}

# ------------------------------------------------------------------ traducciones
Write-Host 'Traducciones'
$tsv = @(Get-ChildItem (Join-Path $Root 'Lang') -Filter *.tsv)
$keys = @{}
Test-Case 'Los archivos de idioma tienen 8 columnas en cada línea' {
    Assert-Empty ($tsv | ForEach-Object {
            $f = $_; $n = 0
            $lines = [IO.File]::ReadAllLines($f.FullName, [Text.Encoding]::UTF8)
            Assert-Equal 'es|en|fr|pt|eu|ca|ca-valencia|gl' $lines[0] "Cabecera de $($f.Name)"
            foreach ($l in $lines) {
                $n++
                if ($n -eq 1 -or -not $l.Trim() -or $l.StartsWith('#')) { continue }
                $c = $l.Split('|'); $keys[$c[0].Trim().Replace('\n', "`n")] = $c
                if ($c.Count -ne 8) { "$($f.Name) línea $n`: $($c.Count) columnas" }
                elseif (-not $c[1].Trim()) { "$($f.Name) línea $n`: sin inglés" }
            }
        }) 'Errores'
}
Test-Case 'Todos los textos de la interfaz están traducidos' {
    $brand = @('Eureka_Utils', 'Hardware', 'VRAM', 'RAM', 'Bus', 'Windows Update', 'Bloatware', 'Windows Hello / PIN', 'gpupdate /force', 'Windows Autopilot', 'BIOS / UEFI', 'SFC /scannow', 'Microsoft Safety Scanner')
    $x = Get-Content (Join-Path $Root 'UI\MainWindow.xaml') -Raw -Encoding UTF8
    $g = Get-Content (Join-Path $Root 'UI\Gui.ps1') -Raw -Encoding UTF8
    $texts = @([regex]::Matches($x, '(?:Header|Content|Text|ToolTip)="([^"{]+)"') | ForEach-Object { [System.Net.WebUtility]::HtmlDecode($_.Groups[1].Value) })
    $texts += @([regex]::Matches($g, "\(T '((?:[^']|'')+)'") | ForEach-Object { $_.Groups[1].Value.Replace("''", "'") })
    Assert-Empty ($texts | Where-Object { $_ -match '[a-zá-ú]{3}' -and $brand -notcontains $_ -and -not $keys.ContainsKey($_) } | Select-Object -Unique) 'Sin traducir'
}
Test-Case 'Las traducciones conservan los marcadores {0}, {1}...' {
    Assert-Empty ($keys.Values | ForEach-Object {
            $c = $_; $ph = @([regex]::Matches($c[0], '\{\d+(:[^}]+)?\}') | ForEach-Object Value | Sort-Object -Unique)
            for ($k = 1; $k -lt [math]::Min(8, $c.Count); $k++) {
                if (-not $c[$k].Trim()) { continue }
                foreach ($p in $ph) { if (-not $c[$k].Contains($p)) { "'$($c[0].Substring(0, [math]::Min(40, $c[0].Length)))' columna $k sin $p" } }
            }
        }) 'Marcadores perdidos'
}

# ------------------------------------------------------------------ funciones
Write-Host 'Funciones'
Test-Case 'winget: lee la tabla de actualizaciones en inglés' {
    $en = @(
        'Name                Id                   Version     Available   Source',
        '-----------------------------------------------------------------------',
        '7-Zip 24.08 (x64)   7zip.7zip            24.08       26.00       winget',
        'Git                 Git.Git              2.45.0      2.47.1      winget',
        '2 upgrades available.')
    $r = @(ConvertFrom-CfgWingetTable -Lines $en)
    Assert-Equal 2 $r.Count 'Filas'
    Assert-Equal '7zip.7zip' $r[0].Id 'Id'
    Assert-Equal '26.00' $r[0].Available 'Disponible'
    Assert-Equal 'winget' $r[1].Source 'Origen'
}
Test-Case 'winget: lee la tabla en español con nombres largos' {
    $row = { param($a, $b, $c, $d, $e) $a.PadRight(39) + $b.PadRight(30) + $c.PadRight(15) + $d.PadRight(15) + $e }
    $es = @((& $row 'Nombre' 'Id' 'Versión' 'Disponible' 'Origen'), ('-' * 105),
        (& $row 'Microsoft Visual C++ 2015-2022 Redis…' 'Microsoft.VCRedist.2015+.x64' '14.38.33135.0' '14.44.35211.0' 'winget'),
        '1 actualizaciones disponibles.')
    $r = @(ConvertFrom-CfgWingetTable -Lines $es)
    Assert-Equal 1 $r.Count 'Filas'
    Assert-Equal 'Microsoft.VCRedist.2015+.x64' $r[0].Id 'Id'
}
Test-Case 'Tamaños: Format-CfgSize' {
    Assert-Equal '—' (Format-CfgSize 0) 'Cero'
    Assert-True ((Format-CfgSize 2048) -match '^2[.,]0 GB$') "2048 MB -> $(Format-CfgSize 2048)"
}
Test-Case 'Firmware: la guía por partes devuelve textos sueltos (no listas anidadas)' {
    $parts = @(Get-CfgFirmwareGuide -Fw ([pscustomobject]@{ Vendor = 'MSI'; IsUefi = $false }) -AsParts)
    Assert-Equal 3 $parts.Count 'Partes'
    Assert-Empty ($parts | Where-Object { $_ -isnot [string] }) 'Partes que no son texto'
}
Test-Case 'Identificación: Lenovo, Dell, HP y PC montado' {
    $cases = @(
        @{ Cs = @{ Manufacturer = 'LENOVO'; Model = '20XW00EXSP'; SystemFamily = 'ThinkPad X1 Carbon Gen 9'; SystemSKUNumber = 'LENOVO_MT_20XW' }; Csp = @{ Version = 'ThinkPad X1 Carbon Gen 9'; IdentifyingNumber = 'PF2ABCDE'; UUID = '4C4C4544-0042-1234-8056-B4C04F4A1234' }; Bios = @{ SerialNumber = 'PF2ABCDE' }
           Expect = @{ 'Machine Type (MT)' = '20XW'; 'Modelo (MTM)' = '20XW00EXSP'; 'Nombre comercial' = 'ThinkPad X1 Carbon Gen 9'; 'Número de serie' = 'PF2ABCDE' } }
        @{ Cs = @{ Manufacturer = 'Dell Inc.'; Model = 'Latitude 5440'; SystemFamily = 'Latitude'; SystemSKUNumber = '0C0B' }; Csp = @{ Version = ''; IdentifyingNumber = '7XK9M34'; UUID = '4C4C4544-0058-4B10-8039-B7C04F4D3334' }; Bios = @{ SerialNumber = '7XK9M34' }
           Expect = @{ 'Service Tag' = '7XK9M34'; 'Express Service Code' = '17266901008'; 'Nombre comercial' = 'Latitude 5440' } }
        @{ Cs = @{ Manufacturer = 'HP'; Model = 'HP EliteBook 840 G10'; SystemFamily = 'HP EliteBook'; SystemSKUNumber = '8A3X2EA#ABE' }; Csp = @{ Version = 'SBKPF'; IdentifyingNumber = '5CG3301ABC'; UUID = 'AB12CD34-1111-2222-3333-444455556666' }; Bios = @{ SerialNumber = '5CG3301ABC' }
           Expect = @{ 'Número de producto' = '8A3X2EA#ABE'; 'Número de serie' = '5CG3301ABC' } }
        @{ Cs = @{ Manufacturer = 'Micro-Star International Co., Ltd.'; Model = 'MS-7D98'; SystemFamily = 'To be filled by O.E.M.'; SystemSKUNumber = 'Default string' }; Csp = @{ Version = '1.0'; IdentifyingNumber = 'Default string'; UUID = 'EA6D54BB-F6E6-CF19-ABC3-FC9D0533EA44' }; Bios = @{ SerialNumber = 'Default string' }
           Expect = @{ 'Número de serie' = $null; 'Número de producto / SKU' = $null } }
    )
    foreach ($c in $cases) {
        $id = & (Get-Module Hardware) {
            param($c)
            $script:TestMock = $c
            function script:Get-CimInstance {
                param($ClassName)
                switch ($ClassName) {
                    'Win32_ComputerSystem' { [pscustomobject]$script:TestMock.Cs } 'Win32_ComputerSystemProduct' { [pscustomobject]$script:TestMock.Csp }
                    'Win32_BIOS' { [pscustomobject]$script:TestMock.Bios } 'Win32_BaseBoard' { [pscustomobject]@{ Manufacturer = 'Placa'; Product = 'Modelo' } }
                }
            }
            try { Get-CfgDeviceIdentity } finally { Remove-Item -Path Function:\Get-CimInstance -ErrorAction SilentlyContinue }
        } $c
        foreach ($k in $c.Expect.Keys) { Assert-Equal $c.Expect[$k] $id.Display[$k] "$($c.Cs.Manufacturer) · $k" }
    }
}
Test-Case 'Memoria: la medición real devuelve datos coherentes' {
    $m = Get-CfgMemoryUsage -Catalog $sw
    Assert-True ($m.TotalMB -gt 0 -and $m.UsedMB -gt 0 -and $m.UsedMB -le $m.TotalMB) "Total $($m.TotalMB) / usada $($m.UsedMB)"
    Assert-True (@($m.Top).Count -gt 0) 'Sin procesos'
}

Test-Case 'Actualización: versión válida y solo descarga desde las releases del repositorio' {
    Assert-True ([version]::TryParse((Get-CfgVersion), [ref]$null)) "Versión '$(Get-CfgVersion)' no válida"
    $fake = [pscustomobject]@{ Version = [version]'99.0.0'; AssetUrl = 'https://example.com/Eureka_Utils_Portable.exe'; Sha256 = ('A' * 64); NotesSha256 = $null; AssetSizeMB = 1 }
    $r = Save-CfgLatestRelease -Release $fake -Folder $env:TEMP
    Assert-True (-not $r.Success) 'Descargó desde una URL ajena a GitHub'
    $fake.AssetUrl = 'https://github.com/juanraul86/Eureka_Utils/releases/download/v99.0.0/Eureka_Utils_Portable.exe'; $fake.Sha256 = $null
    $r = Save-CfgLatestRelease -Release $fake -Folder $env:TEMP
    Assert-True (-not $r.Success) 'Descargó sin huella SHA-256 publicada'
}
# ------------------------------------------------------------------ ayuda de las comprobaciones (icono "i")
Write-Host 'Ayuda de avisos'
Test-Case 'fsutil: "no contiene errores" no es un aviso (en cualquier idioma)' {
    Assert-True (-not (Test-CfgVolumeDirtyText 'El volumen - C: no contiene errores')) 'Español actual'
    Assert-True (-not (Test-CfgVolumeDirtyText 'El volumen - C: no está sucio')) 'Español antiguo'
    Assert-True (-not (Test-CfgVolumeDirtyText 'Volume - C: is NOT Dirty')) 'Inglés'
    Assert-True (Test-CfgVolumeDirtyText 'Volume - C: is Dirty') 'Inglés sucio'
    Assert-True (Test-CfgVolumeDirtyText 'El volumen - C: contiene errores') 'Español sucio'
}
Test-Case 'Cada comprobación que puede avisar o fallar tiene su explicación' {
    $names = foreach ($f in Get-ChildItem (Join-Path $Root 'Modules') -Filter *.psm1) {
        foreach ($line in [IO.File]::ReadAllLines($f.FullName, [Text.Encoding]::UTF8)) {
            if ($line -notmatch "'(AVISO|FALLO)'") { continue }
            foreach ($m in [regex]::Matches($line, '(?:New-CfgCheck|& \$add)\s+[''"]([^''"$]+)')) {
                $n = $m.Groups[1].Value.Trim()
                if ($n -notin 'INFO', 'ACCIÓN', 'AVISO', 'CRÍTICO') { $n }
            }
        }
    }
    Assert-True (@($names).Count -ge 30) "Solo se encontraron $(@($names).Count) comprobaciones"
    Assert-Empty ($names | Select-Object -Unique | Where-Object { -not (Get-CfgCheckHelp -Check $_).Known }) 'Sin explicación'
}
Test-Case 'Las explicaciones y soluciones están traducidas' {
    Assert-Empty (Get-CfgCheckHelp -All | ForEach-Object { $_.C; $_.S } | Where-Object { -not $keys.ContainsKey($_) } | ForEach-Object { $_.Substring(0, [math]::Min(60, $_.Length)) }) 'Sin traducir'
}
Test-Case 'El informe para la IA oculta el nombre del equipo y del usuario' {
    $t = Protect-CfgPrivateText ("Equipo $env:COMPUTERNAME, usuario $env:USERNAME, perfil $env:USERPROFILE\Desktop")
    if ($env:COMPUTERNAME.Length -ge 3) { Assert-True ($t -notmatch [regex]::Escape($env:COMPUTERNAME)) "Sigue el nombre del equipo: $t" }
    if ($env:USERNAME.Length -ge 3) { Assert-True ($t -notmatch [regex]::Escape($env:USERNAME)) "Sigue el usuario: $t" }
    Assert-True ($t.Contains('C:\Users\usuario\Desktop')) "Perfil: $t"
}
Test-Case 'Las filas de comprobación tienen el icono "i" en la plantilla' {
    $x = Get-Content (Join-Path $Root 'UI\MainWindow.xaml') -Raw -Encoding UTF8
    Assert-True ($x -match 'x:Key="InfoDot"' -and $x -match 'Uid="CheckInfo"') 'Falta el estilo InfoDot o el botón en CheckTemplate'
    $g = Get-Content (Join-Path $Root 'UI\Gui.ps1') -Raw -Encoding UTF8
    Assert-True ($g -match "Uid -eq 'CheckInfo'") 'Falta el manejador del clic'
}
# ------------------------------------------------------------------ tareas en paralelo
Write-Host 'Tareas en paralelo'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
. (Join-Path $Root 'UI\I18n.ps1')
. (Join-Path $Root 'UI\Gui.ps1')
Test-Case 'Cerrojos: lo que modifica el equipo va de uno en uno; lo que solo lee, en paralelo' {
    $cambios = @('Instalación de software', 'Desinstalación de software', 'Actualizando aplicaciones', 'Actualizando todo', 'Eliminación de bloatware',
        'Reinstalación de apps', 'Aplicando ajustes', 'Perfil Gaming', 'Post-instalación: perfil Oficina', 'Punto de restauración', 'Instalando controladores',
        'Instalando controladores desde carpeta', 'Unión a corp.local', 'Renombrar a PC-01', 'Salir del dominio', 'Creando usuario1', 'Administrador: ana',
        'Convertir el disco a GPT', 'Preparar actualización de BIOS', 'Orígenes de winget')
    Assert-Empty ($cambios | Where-Object { (Get-CfgTaskLock -Title $_) -ne 'cambios' }) 'Deberían usar el cerrojo cambios'
    $lectura = @('Detectando estado del equipo', 'Buscando actualizaciones', 'Listando hardware y controladores', 'Midiendo el uso de memoria', 'Analizando el sistema',
        'Comprobar seguridad', 'Comprobando BIOS y requisitos', 'Informe del equipo', 'Cuentas locales', 'Cargar errores')
    $locks = @($lectura | ForEach-Object { Get-CfgTaskLock -Title $_ })
    Assert-Empty ($locks | Where-Object { $_ -in 'cambios', '*', 'defender', 'usb', 'gestion' }) 'Las de solo lectura no deben bloquear a otras'
    Assert-Equal $lectura.Count (@($locks | Select-Object -Unique).Count) 'Cada tarea de lectura tiene su propio cerrojo'
    Assert-Equal 'usb' (Get-CfgTaskLock -Title 'Creando USB de instalación') 'El USB no es una cuenta de usuario'
    Assert-Equal '*' (Get-CfgTaskLock -Title 'Borrar registros e informes') 'Borrar datos es exclusiva'
}
Test-Case 'Todas las tareas de la interfaz que modifican el equipo tienen cerrojo compartido' {
    $g = [IO.File]::ReadAllText((Join-Path $Root 'UI\Gui.ps1'))
    $titles = @([regex]::Matches($g, "Start-CfgTask -Title \(?T? ?['""]([^'""$]+)") | ForEach-Object { $_.Groups[1].Value.Trim() } | Select-Object -Unique)
    $risky = 'Instal|Desinstal|Actualizando|Eliminación|Reinstalación|Aplicando|Perfil|Unión|Renombrar|Salir|Convertir|Preparar|Punto de restauración'
    Assert-Empty ($titles | Where-Object { $_ -match $risky -and (Get-CfgTaskLock -Title $_) -notin 'cambios', 'usb' }) 'Sin cerrojo compartido'
}

# ------------------------------------------------------------------ permisos de la carpeta
Write-Host 'Permisos'
Test-Case 'Ningún icacls con /T usa (OI)(CI): en archivos falla y los deja sin permisos' {
    Assert-Empty ($code | Where-Object { $_.Name -ne 'Run-Tests.ps1' } | ForEach-Object {
            $f = $_; $n = 0
            foreach ($l in [IO.File]::ReadAllLines($f.FullName)) {
                $n++
                # Cada llamada a icacls por separado (una línea puede encadenar varias con &)
                foreach ($call in @($l -split 'icacls' | Select-Object -Skip 1)) { if ($call -match '/T\b' -and $call -match '\(OI\)|\(CI\)') { "$($f.Name):$n" } }
            }
        }) 'Llamadas peligrosas'
}
$permTmp = Join-Path $env:TEMP ('eureka_perm_' + [guid]::NewGuid().ToString('N'))
try {
    foreach ($d in 'Modules', 'UI', 'Lang', 'Catalog') { New-Item -ItemType Directory -Path (Join-Path $permTmp $d) -Force | Out-Null }
    foreach ($f in 'Eureka_Utils.ps1', 'Modules\Core.psm1', 'Modules\Drivers.psm1', 'UI\Gui.ps1', 'Lang\01.tsv', 'Catalog\software.json') { Set-Content -Path (Join-Path $permTmp $f) -Value 'x' }
    Test-Case 'Proteger la carpeta deja todo el código legible y heredando de la carpeta' {
        $null = Protect-CfgFolder -Path $permTmp
        Assert-Empty (Get-CfgUnreadableCode -Root $permTmp) 'Sin acceso de lectura'
        Assert-True ((Get-Acl $permTmp).AreAccessRulesProtected) 'La carpeta raíz debería dejar de heredar'
        foreach ($f in 'Modules\Core.psm1', 'UI\Gui.ps1', 'Eureka_Utils.ps1') {
            $acl = Get-Acl (Join-Path $permTmp $f)
            Assert-True (-not $acl.AreAccessRulesProtected) "$f debería heredar permisos"
            Assert-True (@($acl.Access | Where-Object IsInherited).Count -ge 3) "$f sin permisos heredados"
        }
        Assert-Empty (Test-CfgFolderSecurity -Path $permTmp | Where-Object { $_ -ne 'SIN-PERMISOS' }) 'Usuarios sin privilegios con escritura'
    }
    Test-Case 'Seguridad de carpeta: la lectura de Usuarios no cuenta como riesgo, la escritura sí' {
        Assert-Empty (Test-CfgFolderSecurity -Path $permTmp | Where-Object { $_ -ne 'SIN-PERMISOS' }) 'Falso positivo con Usuarios: lectura'
        & (Join-Path $env:SystemRoot 'System32\icacls.exe') $permTmp /grant '*S-1-5-32-545:(OI)(CI)M' /C /Q | Out-Null
        $risk = @(Test-CfgFolderSecurity -Path $permTmp)
        & (Join-Path $env:SystemRoot 'System32\icacls.exe') $permTmp /grant:r '*S-1-5-32-545:(OI)(CI)RX' /C /Q | Out-Null
        if ($risk -notcontains 'SIN-PERMISOS') { Assert-True ($risk.Count -ge 1) 'No detecta Usuarios con escritura' }
    }
    Test-Case 'Autorreparación: un archivo sin permisos vuelve a ser legible' {
        $victim = Join-Path $permTmp 'Modules\Drivers.psm1'
        & (Join-Path $env:SystemRoot 'System32\icacls.exe') $victim /inheritance:r /C /Q | Out-Null
        Assert-True (@(Get-CfgUnreadableCode -Root $permTmp) -contains 'Drivers.psm1') 'No se reprodujo el archivo sin permisos'
        & (Join-Path $env:SystemRoot 'System32\icacls.exe') (Join-Path $permTmp '*') /reset /T /C /Q | Out-Null
        Assert-Empty (Get-CfgUnreadableCode -Root $permTmp) 'Sigue sin poder leerse'
    }
}
finally {
    & (Join-Path $env:SystemRoot 'System32\icacls.exe') $permTmp /grant "$env:USERDOMAIN\$env:USERNAME`:(OI)(CI)F" /C /Q 2>&1 | Out-Null
    & (Join-Path $env:SystemRoot 'System32\icacls.exe') (Join-Path $permTmp '*') /reset /T /C /Q 2>&1 | Out-Null
    Remove-Item -LiteralPath $permTmp -Recurse -Force -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------------ resultado
Write-Host ''
if ($script:Fail.Count) {
    Write-Host ("{0} pruebas correctas, {1} fallidas:" -f $script:Pass, $script:Fail.Count) -ForegroundColor Red
    $script:Fail | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host ("{0} pruebas correctas." -f $script:Pass) -ForegroundColor Green
exit 0
