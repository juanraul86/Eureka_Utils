# Report.psm1 - Informe HTML del equipo (inventario, compatibilidad, software, bloatware, actualizaciones)

function ConvertTo-CfgHtmlTable {
    param($Rows, [string[]]$Columns, [string[]]$Headers)
    $enc = { param($v) [System.Net.WebUtility]::HtmlEncode([string]$v) }
    $h = ($Headers | ForEach-Object { "<th>$(& $enc $_)</th>" }) -join ''
    $b = foreach ($r in $Rows) { '<tr>' + (($Columns | ForEach-Object { "<td>$(& $enc $r.$_)</td>" }) -join '') + '</tr>' }
    return "<table><thead><tr>$h</tr></thead><tbody>$($b -join "`n")</tbody></table>"
}

function New-CfgComputerReport {
    param([switch]$IncludeUpdates)
    Write-CfgLog 'Generando informe del equipo...' STEP
    $enc = { param($v) [System.Net.WebUtility]::HtmlEncode([string]$v) }
    $sys = Get-CfgSystemSummary
    $hw = Get-CfgHardware
    $join = Get-CfgJoinDisplay (Get-CfgJoinStatus)
    $compat = Test-CfgWin11Compat -Hw $hw
    $rec = Get-CfgHardwareRecommendations -Hw $hw
    $cat = Get-CfgSoftwareCatalog
    $state = Get-CfgSoftwareState -Catalog $cat
    $sw = @($cat | Where-Object { $state[$_.id] } | ForEach-Object { [pscustomobject]@{ Name = $_.name; Category = $_.category; Version = $state[$_.id] } })
    $bwCat = Get-CfgBloatwareCatalog
    $bwState = @(Get-CfgBloatwareState -Catalog $bwCat)
    $bw = @($bwState | Where-Object { $_.Present } | ForEach-Object { $id = $_.Id; $b = $bwCat | Where-Object { $_.id -eq $id }; [pscustomobject]@{ Name = $b.name; Risk = $b.risk; Recommended = $(if ($b.recommended) { 'Sí' } else { 'No' }); Status = $_.Status } })
    $up = @()
    if ($IncludeUpdates) { $up = @(Get-CfgWingetUpgrades) }

    $kv = { param($d) '<table class="kv">' + ((@($d.Keys) | ForEach-Object { "<tr><th>$(& $enc $_)</th><td>$((& $enc $d[$_]) -replace "`n", '<br>')</td></tr>" }) -join '') + '</table>' }
    $gpus = @($hw.Gpus | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Vendor = $_.Vendor; Vram = (Format-CfgSize $_.VramMB); Driver = $_.DriverVersion; Date = $(if ($_.DriverDate) { $_.DriverDate.ToString('yyyy-MM-dd') }) } })
    $disks = @($hw.Disks | ForEach-Object { [pscustomobject]@{ Model = $_.Model; Media = $_.Media; Bus = $_.Bus; Size = "$($_.SizeGB) GB"; Health = $_.Health } })

    $html = @"
<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Informe $(& $enc $env:COMPUTERNAME)</title>
<style>
:root{--bg:#f6f7f9;--card:#fff;--text:#1f2937;--muted:#6b7280;--line:#e5e7eb;--accent:#0f6cbd}
@media (prefers-color-scheme:dark){:root{--bg:#111318;--card:#1b1e25;--text:#e6e8ec;--muted:#9aa3b2;--line:#2d323c;--accent:#4c9eeb}}
body{font-family:Segoe UI,system-ui,sans-serif;background:var(--bg);color:var(--text);margin:0;padding:24px;line-height:1.45}
h1{margin:0 0 4px;color:var(--accent)} h2{margin:28px 0 10px;font-size:18px} .muted{color:var(--muted)}
section{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:16px 18px;margin-top:14px;overflow-x:auto}
table{border-collapse:collapse;width:100%;font-size:14px} th,td{text-align:left;padding:6px 8px;border-bottom:1px solid var(--line);vertical-align:top}
thead th{color:var(--muted);font-weight:600} table.kv th{width:220px;color:var(--muted);font-weight:500}
</style></head><body>
<h1>Informe del equipo $(& $enc $env:COMPUTERNAME)</h1>
<div class="muted">Generado el $(Get-Date -Format 'dd/MM/yyyy HH:mm') por el Eureka_Utils</div>
<section><h2>Sistema</h2>$(& $kv $sys.Display)</section>
<section><h2>Hardware</h2>$(& $kv (Get-CfgHardwareDisplay -Hw $hw))
<h2>Tarjetas gráficas</h2>$(ConvertTo-CfgHtmlTable $gpus 'Name','Vendor','Vram','Driver','Date' 'Modelo','Fabricante','VRAM','Controlador','Fecha')
<h2>Discos</h2>$(ConvertTo-CfgHtmlTable $disks 'Model','Media','Bus','Size','Health' 'Modelo','Tipo','Bus','Tamaño','Estado')</section>
<section><h2>Compatibilidad con Windows 11</h2>$(ConvertTo-CfgHtmlTable $compat 'Resultado','Comprobacion','Detalle' 'Resultado','Comprobación','Detalle')</section>
<section><h2>Recomendaciones</h2>$(ConvertTo-CfgHtmlTable $rec 'Nivel','Texto' 'Nivel','Recomendación')</section>
<section><h2>Identidad y gestión</h2>$(& $kv $join)</section>
<section><h2>Software del catálogo instalado ($($sw.Count))</h2>$(ConvertTo-CfgHtmlTable $sw 'Name','Category','Version' 'Aplicación','Categoría','Versión')</section>
<section><h2>Bloatware presente ($($bw.Count))</h2>$(ConvertTo-CfgHtmlTable $bw 'Name','Risk','Recommended','Status' 'Aplicación','Riesgo al quitar','Quitar recomendado','Estado')</section>
$(if ($IncludeUpdates) { "<section><h2>Actualizaciones pendientes ($($up.Count))</h2>$(ConvertTo-CfgHtmlTable $up 'Name','Id','Version','Available' 'Aplicación','Id. winget','Instalada','Disponible')</section>" })
</body></html>
"@
    $file = Join-Path (Get-CfgExportFolder) ('Informe_{0}_{1}.html' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmmss'))
    [IO.File]::WriteAllText($file, $html, (New-Object Text.UTF8Encoding $false))
    Write-CfgLog "Informe guardado en $file" OK
    return (New-CfgResult -Id 'report' -Name 'Informe del equipo' -Action 'Exportar' -Success $true -Message $file)
}

Export-ModuleMember -Function *
