# I18n.ps1 - Traducción de la interfaz de Eureka_Utils
# Las traducciones están en Lang\*.tsv (se leen todos): una fila por texto (columna "es" = texto original
# tal como aparece en la interfaz) y una columna por idioma, separadas por "|". Si falta una
# traducción se muestra el texto en español (y en valenciano, primero el catalán).

$script:Languages = @(
    [pscustomobject]@{ Code = 'es';          Name = 'Español';   Culture = 'es-ES' }
    [pscustomobject]@{ Code = 'en';          Name = 'English';   Culture = 'en-US' }
    [pscustomobject]@{ Code = 'eu';          Name = 'Euskara';   Culture = 'eu-ES' }
    [pscustomobject]@{ Code = 'ca';          Name = 'Català';    Culture = 'ca-ES' }
    [pscustomobject]@{ Code = 'ca-valencia'; Name = 'Valencià';  Culture = 'ca-ES-valencia' }
    [pscustomobject]@{ Code = 'gl';          Name = 'Galego';    Culture = 'gl-ES' }
    [pscustomobject]@{ Code = 'fr';          Name = 'Français';  Culture = 'fr-FR' }
    [pscustomobject]@{ Code = 'pt';          Name = 'Português'; Culture = 'pt-PT' }
)

$script:I18n = @{ Lang = 'es'; Tables = @{}; Records = (New-Object System.Collections.ArrayList) }

function Import-CfgTranslations {
    param([Parameter(Mandatory)][string]$Root)
    foreach ($file in @(Get-ChildItem (Join-Path $Root 'Lang') -Filter '*.tsv' -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $lines = [IO.File]::ReadAllLines($file.FullName, [Text.Encoding]::UTF8)
        if (-not $lines.Count) { continue }
        $header = @($lines[0].Split('|') | ForEach-Object { $_.Trim() })
        for ($j = 1; $j -lt $header.Count; $j++) {
            if (-not $script:I18n.Tables.ContainsKey($header[$j])) { $script:I18n.Tables[$header[$j]] = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal) }
        }
        for ($i = 1; $i -lt $lines.Count; $i++) {
            $l = $lines[$i]
            if (-not $l.Trim() -or $l.StartsWith('#')) { continue }
            $cols = $l.Split('|')
            $es = $cols[0].Trim().Replace('\n', "`n")
            for ($j = 1; $j -lt [math]::Min($cols.Count, $header.Count); $j++) {
                $v = $cols[$j].Trim().Replace('\n', "`n")
                if ($v) { $script:I18n.Tables[$header[$j]][$es] = $v }
            }
        }
    }
}

function Get-CfgDefaultLanguage {
    $ui = (Get-UICulture).Name
    if ($ui -eq 'ca-ES-valencia') { return 'ca-valencia' }
    $two = $ui.Split('-')[0]
    if (@($script:Languages | Where-Object { $_.Code -eq $two }).Count) { return $two }
    return 'es'
}

function T {
    <# Traduce un texto de la interfaz al idioma actual. #>
    param([Parameter(Position = 0)][string]$Text)
    $l = $script:I18n.Lang
    if ($l -eq 'es' -or -not $Text) { return $Text }
    $t = $script:I18n.Tables[$l]
    if ($t -and $t.ContainsKey($Text)) { return $t[$Text] }
    if ($l -eq 'ca-valencia') { $c = $script:I18n.Tables['ca']; if ($c -and $c.ContainsKey($Text)) { return $c[$Text] } }
    return $Text
}

function Add-CfgI18nRecord {
    param($Obj, [string]$Prop)
    $v = $Obj.$Prop
    if ($v -is [string] -and $v.Trim()) { [void]$script:I18n.Records.Add(@{ O = $Obj; P = $Prop; Es = $v; Last = $v }) }
}

function Register-CfgI18nTree {
    <# Recorre el árbol lógico y guarda los textos originales de la interfaz. #>
    param($Node)
    if (-not ($Node -is [System.Windows.DependencyObject])) { return }
    if ($Node -is [System.Windows.Controls.TextBlock]) { if ($Node.Inlines.Count -le 1) { Add-CfgI18nRecord $Node 'Text' } }
    elseif ($Node -is [System.Windows.Controls.HeaderedContentControl]) { Add-CfgI18nRecord $Node 'Header'; Add-CfgI18nRecord $Node 'Content' }
    elseif ($Node -is [System.Windows.Controls.ContentControl]) { Add-CfgI18nRecord $Node 'Content' }
    if ($Node -is [System.Windows.FrameworkElement]) { Add-CfgI18nRecord $Node 'ToolTip' }
    if ($Node -is [System.Windows.Controls.DataGrid]) { foreach ($c in $Node.Columns) { Add-CfgI18nRecord $c 'Header' } }
    foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($Node)) { Register-CfgI18nTree $child }
}

function Update-CfgI18nTree {
    <# Aplica el idioma actual a los textos registrados que el programa no ha cambiado. #>
    foreach ($r in $script:I18n.Records) {
        $cur = [string]$r.O.($r.P)
        if ($cur -ceq [string]$r.Last) {
            $n = T $r.Es
            if ($n -cne $cur) { $r.O.($r.P) = $n }
            $r.Last = $n
        }
    }
}

function ConvertTo-CfgCheckView {
    <# Traduce Comprobacion y Resultado de las listas de comprobaciones. #>
    param($Items)
    @($Items | Where-Object { $_ -and $_.PSObject.Properties['Comprobacion'] } | ForEach-Object {
            [pscustomobject]@{ Comprobacion = (T $_.Comprobacion); Resultado = (T $_.Resultado); Detalle = $_.Detalle }
        })
}
