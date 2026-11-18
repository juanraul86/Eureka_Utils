<#
.SYNOPSIS
    Genera los ejecutables dEureka_Utils con el compilador de C# que incluye Windows
    (.NET Framework 4.x), sin descargar nada:
      ..\Eureka_Utils.exe            lanzador que se coloca junto a la carpeta de Eureka_Utils
      ..\Dist\Eureka_Utils_Portable.exe  un único archivo con todo Eureka_Utils dentro
      ..\Dist\Eureka_Utils.zip    la carpeta completa comprimida
.NOTES
    Vuelve a ejecutarlo cada vez que cambies catálogos, módulos o la interfaz para regenerar
    Eureka_Utils_Portable.exe. Para evitar avisos de SmartScreen, firma los .exe con un
    certificado de firma de código (Set-AuthenticodeSignature).
#>
[CmdletBinding()]
param(
    # Huella de un certificado de firma de código del almacén (Cert:\CurrentUser\My o LocalMachine\My).
    # Firmar con un certificado de una CA reconocida evita bloqueos de Smart App Control y SmartScreen.
    [string]$CertificateThumbprint,
    [string]$TimestampServer = 'http://timestamp.digicert.com'
)
$ErrorActionPreference = 'Stop'
$build = $PSScriptRoot
$root  = Split-Path $build -Parent
$dist  = Join-Path $root 'Dist'
$obj   = Join-Path $build 'obj'
foreach ($d in $dist, $obj) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null } }

$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { throw 'No se encuentra csc.exe de .NET Framework 4.x.' }
$fx = Split-Path $csc

# ---------------------------------------------------------------- icono
Add-Type -AssemblyName System.Drawing
$ico = Join-Path $obj 'eureka_utils.ico'
function New-IconPng([int]$s) {
    $bmp = New-Object System.Drawing.Bitmap $s, $s
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)
    $r = [math]::Max(2, [int]($s * 0.18))
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $w = $s - 1
    $path.AddArc(0, 0, $r * 2, $r * 2, 180, 90); $path.AddArc($w - $r * 2, 0, $r * 2, $r * 2, 270, 90)
    $path.AddArc($w - $r * 2, $w - $r * 2, $r * 2, $r * 2, 0, 90); $path.AddArc(0, $w - $r * 2, $r * 2, $r * 2, 90, 90); $path.CloseFigure()
    $g.FillPath((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(15, 108, 189))), $path)
    $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    # monitor
    $mx = $s * 0.18; $my = $s * 0.2; $mw = $s * 0.64; $mh = $s * 0.42
    $g.FillRectangle($white, [float]$mx, [float]$my, [float]$mw, [float]$mh)
    $g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(15, 108, 189))), [float]($mx + $s * 0.05), [float]($my + $s * 0.05), [float]($mw - $s * 0.1), [float]($mh - $s * 0.1))
    $g.FillRectangle($white, [float]($s * 0.45), [float]($my + $mh), [float]($s * 0.1), [float]($s * 0.1))
    $g.FillRectangle($white, [float]($s * 0.3), [float]($my + $mh + $s * 0.1), [float]($s * 0.4), [float]($s * 0.06))
    # marca de verificación
    if ($s -ge 24) {
        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), ([float]([math]::Max(1.5, $s * 0.06)))
        $g.DrawLines($pen, [System.Drawing.PointF[]]@(
                (New-Object System.Drawing.PointF ([float]($s * 0.36)), ([float]($s * 0.41))),
                (New-Object System.Drawing.PointF ([float]($s * 0.46)), ([float]($s * 0.5))),
                (New-Object System.Drawing.PointF ([float]($s * 0.64)), ([float]($s * 0.32)))))
    }
    $g.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    return , $ms.ToArray()
}
$sizes = 16, 24, 32, 48, 64, 256
$pngs = @($sizes | ForEach-Object { , (New-IconPng $_) })
$fs = [IO.File]::Create($ico); $bw = New-Object IO.BinaryWriter $fs
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $sz = $sizes[$i]; $b = if ($sz -ge 256) { 0 } else { $sz }
    $bw.Write([byte]$b); $bw.Write([byte]$b); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$pngs[$i].Length); $bw.Write([uint32]$offset)
    $offset += $pngs[$i].Length
}
foreach ($p in $pngs) { $bw.Write($p) }
$bw.Close()
Copy-Item $ico (Join-Path $root 'UI\eureka_utils.ico') -Force

# ---------------------------------------------------------------- payload (carpeta de Eureka_Utils)
$exclude = '^(\.git|\.github|\.signpath|Logs|Exports|Dist|Build|Docs|Eureka_Utils_Datos)(\\|$)|^Config\\(preferencias|postinstall).*\.json$|\.exe$|\.log$|^(index\.html|robots\.txt|sitemap\.xml|google[0-9a-f]+\.html)$'
$files = Get-ChildItem $root -Recurse -File -Force | Where-Object { $_.FullName.Substring($root.Length + 1) -notmatch $exclude }
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
function New-CfgZip([string]$Path, $Items, [string]$Prefix) {
    if (Test-Path $Path) { Remove-Item $Path -Force }
    $zip = [IO.Compression.ZipFile]::Open($Path, 'Create')
    try {
        foreach ($f in $Items) {
            $rel = $Prefix + $f.FullName.Substring($root.Length + 1).Replace('\', '/')
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, $rel, 'Optimal')
        }
    }
    finally { $zip.Dispose() }
}
$payload = Join-Path $obj 'payload.zip'
New-CfgZip $payload $files ''
Write-Host ("Payload: {0} archivos, {1:N1} MB" -f @($files).Count, ((Get-Item $payload).Length / 1MB))

# ---------------------------------------------------------------- compilación
$common = @('/nologo', '/optimize+', '/platform:anycpu', '/target:winexe', "/win32icon:$ico", "/win32manifest:$(Join-Path $build 'app.manifest')",
            "/r:$fx\System.Windows.Forms.dll", "/r:$fx\System.dll")
# Lista de huellas SHA-256 del código que Eureka_Utils.exe comprueba antes de ejecutar nada
$skipDirs = '^(Build|Dist|Logs|Exports|Docs|\.git|\.github|Eureka_Utils_Datos)\\'
$codeFiles = Get-ChildItem $root -Recurse -File -Force -Include *.ps1, *.psm1, *.xaml | Where-Object { $_.FullName.Substring($root.Length + 1) -notmatch $skipDirs } | Sort-Object FullName
$manifest = Join-Path $obj 'manifest.txt'
$lines = foreach ($f in $codeFiles) { '{0} {1}' -f (Get-FileHash $f.FullName -Algorithm SHA256).Hash, $f.FullName.Substring($root.Length + 1).Replace('\', '/') }
[IO.File]::WriteAllLines($manifest, [string[]]$lines, (New-Object Text.UTF8Encoding $false))
Write-Host ("Lista de integridad: {0} archivos de código" -f @($lines).Count)
& $csc @common "/resource:$manifest,manifest.txt" "/out:$(Join-Path $root 'Eureka_Utils.exe')" (Join-Path $build 'Launcher.cs')
if ($LASTEXITCODE) { throw "Error compilando Eureka_Utils.exe ($LASTEXITCODE)" }
& $csc @common '/define:SINGLEFILE' "/r:$fx\System.IO.Compression.dll" "/r:$fx\System.IO.Compression.FileSystem.dll" "/resource:$payload,payload.zip" "/out:$(Join-Path $dist 'Eureka_Utils_Portable.exe')" (Join-Path $build 'Launcher.cs')
if ($LASTEXITCODE) { throw "Error compilando Eureka_Utils_Portable.exe ($LASTEXITCODE)" }

# ---------------------------------------------------------------- firma (opcional)
if ($CertificateThumbprint) {
    $cert = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -CodeSigningCert | Where-Object { $_.Thumbprint -eq $CertificateThumbprint } | Select-Object -First 1
    if (-not $cert) { throw "No se encuentra el certificado de firma de código $CertificateThumbprint" }
    foreach ($f in (Join-Path $root 'Eureka_Utils.exe'), (Join-Path $dist 'Eureka_Utils_Portable.exe')) {
        $sig = Set-AuthenticodeSignature -FilePath $f -Certificate $cert -TimestampServer $TimestampServer -HashAlgorithm SHA256
        Write-Host ("Firma de {0}: {1}" -f (Split-Path $f -Leaf), $sig.Status)
    }
}
else {
    Write-Warning 'Ejecutables sin firmar: Smart App Control los bloqueará y SmartScreen mostrará un aviso. Usa -CertificateThumbprint para firmarlos, o Eureka_Utils.cmd.'
}

# ---------------------------------------------------------------- ZIP de distribución (incluye Eureka_Utils.exe)
$files2 = Get-ChildItem $root -Recurse -File -Force | Where-Object { $rel = $_.FullName.Substring($root.Length + 1); $rel -notmatch '^(\.git|Logs|Exports|Dist|Build\\obj|Eureka_Utils_Datos)(\\|$)|^Config\\(preferencias|postinstall).*\.json$|\.log$' }
New-CfgZip (Join-Path $dist 'Eureka_Utils.zip') $files2 'Eureka_Utils/'

Get-ChildItem (Join-Path $root 'Eureka_Utils.exe'), (Join-Path $dist '*') | Select-Object Name, @{ n = 'MB'; e = { '{0:N2}' -f ($_.Length / 1MB) } } | Format-Table -AutoSize
