# Gui.ps1 - Interfaz WPF estilo "Centro de software" con modo claro/oscuro.
# Las tareas largas se ejecutan en un runspace aparte para que la ventana no se congele;
# el registro llega a la interfaz a través de una cola concurrente.

$script:TaskButtons = @(
    'BtnRefresh', 'BtnRestorePoint', 'BtnApplyProfile', 'BtnReport', 'BtnSwDetect', 'BtnSwUninstall', 'BtnSwInstall',
    'BtnUpScan', 'BtnUpSources', 'BtnUpSelected', 'BtnUpAll', 'BtnBwDetect', 'BtnBwRemove', 'BtnBwRestore', 'BtnTwApply',
    'BtnAccCheck', 'BtnAccCreate', 'BtnAccAddAdmin', 'BtnAccUsersRefresh',
    'BtnDomCheck', 'BtnDomJoin', 'BtnRename', 'BtnDomLeave', 'BtnGpUpdate', 'BtnIntuneSync', 'BtnHybridJoin', 'BtnMdmEnroll',
    'BtnMdmDiag', 'BtnAutopilot', 'BtnBattery', 'BtnUsbReadIso', 'BtnUsbCreate', 'BtnUsbSaveXml',
    'BtnDiagRun', 'BtnSfc', 'BtnDismScan', 'BtnDismRestore', 'BtnChkdsk', 'BtnEnergy', 'BtnDiagEvents',
    'BtnSecRun', 'BtnSigUpdate', 'BtnScanQuick', 'BtnScanFull', 'BtnScanFolder', 'BtnScanOffline', 'BtnMsert',
    'BtnMemRefresh', 'BtnDrvList', 'BtnDrvScan', 'BtnDrvInstall', 'BtnDrvFolder', 'BtnDrvBackup', 'BtnFwCheck', 'BtnFwPrepare', 'BtnMbrValidate', 'BtnMbrConvert', 'BtnClearData', 'BtnUpdDownload'
)

$script:Palettes = @{
    Light = @{
        Bg = '#F3F4F6'; Surface = '#FFFFFF'; SurfaceAlt = '#F9FAFB'; Border = '#E5E7EB'; BorderStrong = '#D1D5DB'
        Text = '#1F2937'; TextMuted = '#6B7280'; Accent = '#0F6CBD'; AccentText = '#FFFFFF'; Header = '#0F6CBD'
        HeaderSub = '#D6E6F7'; HeaderPill = '#0B5A9E'; Danger = '#B42318'; DangerBorder = '#F4B4AE'; Hover = '#E6EEF7'
        Selection = '#DCE8F5'; LogBg = '#111827'; LogText = '#E5E7EB'; Input = '#FFFFFF'; Warn = '#B45309'; WarnBg = '#FEF3C7'
    }
    Dark  = @{
        Bg = '#111318'; Surface = '#1B1E25'; SurfaceAlt = '#20242C'; Border = '#2D323C'; BorderStrong = '#3D4350'
        Text = '#E6E8EC'; TextMuted = '#9AA3B2'; Accent = '#3B8EE0'; AccentText = '#FFFFFF'; Header = '#15233A'
        HeaderSub = '#A9BCD6'; HeaderPill = '#24406A'; Danger = '#F97066'; DangerBorder = '#7A2E2A'; Hover = '#263042'
        Selection = '#24364F'; LogBg = '#0B0D11'; LogText = '#D1D5DB'; Input = '#14171D'; Warn = '#FBBF24'; WarnBg = '#FDE68A'
    }
}

# ------------------------------------------------------------------ tema

function Get-CfgPrefsPath {
    $d = Join-Path (Get-CfgDataRoot) 'Config'
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    return (Join-Path $d 'preferencias.json')
}

function Get-CfgPrefs {
    $p = Get-CfgPrefsPath
    if (Test-Path $p) { try { return (Get-Content $p -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json) } catch { } }
    return [pscustomobject]@{ Theme = 'System' }
}

function Save-CfgPrefs {
    param($Prefs)
    try {
        $cur = Get-CfgPrefs
        foreach ($p in $Prefs.PSObject.Properties) { $cur | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
        $cur | ConvertTo-Json | Set-Content (Get-CfgPrefsPath) -Encoding UTF8
    }
    catch { }
}

function Test-CfgSystemDark {
    $v = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction SilentlyContinue).AppsUseLightTheme
    return ($v -eq 0)
}

function Set-CfgTheme {
    <# Mode: System | Light | Dark #>
    param([string]$Mode = 'System')
    $effective = $Mode
    if ($Mode -eq 'System') { $effective = $(if (Test-CfgSystemDark) { 'Dark' } else { 'Light' }) }
    $pal = $script:Palettes[$effective]
    $res = $script:Ui.Window.Resources
    foreach ($k in $pal.Keys) {
        $color = [System.Windows.Media.Color][System.Windows.Media.ColorConverter]::ConvertFromString($pal[$k])
        $brush = [System.Windows.Media.SolidColorBrush]::new($color)
        $brush.Freeze()
        if ($res.Contains($k)) { $res.Remove($k) }
        $res.Add($k, $brush)
    }
    $script:G.Theme = $Mode
    $script:G.EffectiveTheme = $effective
    $label = @{ System = 'Tema: sistema'; Light = 'Tema: claro'; Dark = 'Tema: oscuro' }[$Mode]
    $script:Ui.BtnTheme.Content = T $label
    # Barra de título oscura (Windows 11)
    try {
        $h = (New-Object System.Windows.Interop.WindowInteropHelper $script:Ui.Window).Handle
        if ($h -ne [IntPtr]::Zero) {
            $val = [int]($effective -eq 'Dark')
            [void][CfgNative.Dwm]::DwmSetWindowAttribute($h, 20, [ref]$val, 4)
        }
    }
    catch { }
}

function Switch-CfgTheme {
    $next = @{ System = 'Light'; Light = 'Dark'; Dark = 'System' }[$script:G.Theme]
    Set-CfgTheme $next
    Save-CfgPrefs ([pscustomobject]@{ Theme = $next; Language = $script:I18n.Lang })
}

# ------------------------------------------------------------------ utilidades UI

function Show-CfgMessage {
    param([string]$Text, [string]$Icon = 'Information', [string]$Buttons = 'OK')
    return [System.Windows.MessageBox]::Show($script:Ui.Window, (T $Text), 'Eureka_Utils', $Buttons, $Icon)
}

function Confirm-CfgAction { param([string]$Text) return ((Show-CfgMessage -Text $Text -Icon 'Question' -Buttons 'YesNo') -eq 'Yes') }

function Get-CfgAnon {
    <# En modo captura (documentación) oculta el nombre del equipo y del usuario. #>
    param([string]$Text)
    if (-not $script:G.CapturePath -or -not $Text) { return $Text }
    return $Text.Replace($env:COMPUTERNAME, 'PC-EJEMPLO').Replace($env:USERNAME, 'usuario')
}

function ConvertTo-CfgKeyValue {
    param($Dictionary)
    foreach ($k in @($Dictionary.Keys)) { [pscustomobject]@{ Key = (T $k); Value = (Get-CfgAnon ([string]$Dictionary[$k])) } }
}

function New-CfgDataTable {
    param([string]$Name, [string[]]$Strings, [string[]]$Bools)
    $t = New-Object System.Data.DataTable $Name
    foreach ($c in $Strings) { [void]$t.Columns.Add($c, [string]) }
    foreach ($c in $Bools) { [void]$t.Columns.Add($c, [bool]) }
    return , $t
}

function Get-CfgSelectedIds {
    param($Table, [string]$Column = 'Id')
    return @($Table.Rows | Where-Object { $_['Selected'] -eq $true } | ForEach-Object { [string]$_[$Column] })
}

function Set-CfgBusy {
    param([bool]$Busy, [string]$Title)
    foreach ($n in $script:TaskButtons) { if ($script:Ui[$n]) { $script:Ui[$n].IsEnabled = -not $Busy } }
    $script:Ui.Progress.IsIndeterminate = $Busy
    $script:Ui.Progress.Visibility = $(if ($Busy) { 'Visible' } else { 'Hidden' })
    if ($Busy) { $script:Ui.StatusText.Text = "$Title..." }
}

function Start-CfgTask {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][scriptblock]$Script,
        [object[]]$Arguments = @(),
        [scriptblock]$OnComplete
    )
    $Title = T $Title
    if ($script:G.Job) {
        Show-CfgMessage ((T 'Espera a que termine la tarea en curso: {0}.') -f $script:G.Job.Title) | Out-Null
        return
    }
    Write-CfgLog "── $Title ──" STEP
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass
    $iss.ImportPSModule([string[]]$script:G.Modules)
    $rs = [runspacefactory]::CreateRunspace($iss)
    $rs.ApartmentState = 'STA'
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript('param($r, $l, $q) Set-CfgEnvironment -Root $r -LogFile $l -LogQueue $q | Out-Null')
    [void]$ps.AddArgument($script:G.Root).AddArgument($script:G.LogFile).AddArgument($script:G.Queue)
    [void]$ps.AddStatement()
    [void]$ps.AddScript($Script.ToString())
    foreach ($a in $Arguments) { [void]$ps.AddArgument($a) }
    $script:G.Job = @{ PS = $ps; RS = $rs; Handle = $ps.BeginInvoke(); Title = $Title; OnComplete = $OnComplete }
    Set-CfgBusy $true $Title
}

function Invoke-CfgTimerTick {
    if ($script:G.RelCheck) { Complete-CfgReleaseCheck }
    $line = $null
    $sb = New-Object System.Text.StringBuilder
    $last = $null
    while ($script:G.Queue.TryDequeue([ref]$line)) { [void]$sb.AppendLine($line); $last = $line }
    if ($sb.Length) {
        $script:Ui.LogBox.AppendText($sb.ToString())
        $script:Ui.LogBox.ScrollToEnd()
        $script:Ui.StatusText.Text = ($last -replace '^\[[^\]]+\]\s*\[[^\]]+\]\s*', '').Trim()
    }
    $job = $script:G.Job
    if ($job -and $job.Handle.IsCompleted) {
        $script:G.Job = $null
        $output = $null
        try { $output = $job.PS.EndInvoke($job.Handle) }
        catch { Write-CfgLog "La tarea '$($job.Title)' falló: $($_.Exception.Message)" ERROR }
        foreach ($e in $job.PS.Streams.Error) { Write-CfgLog "$e" ERROR }
        $job.PS.Dispose(); $job.RS.Close(); $job.RS.Dispose()
        Set-CfgBusy $false
        $fails = @($output | Where-Object { $_ -and $_.PSObject.Properties['Success'] -and -not $_.Success })
        if ($fails.Count) {
            Write-CfgLog ("{0}: {1} acción(es) con error -> {2}" -f $job.Title, $fails.Count, (($fails | ForEach-Object { $_.Name }) -join ', ')) WARN
        }
        if ($job.OnComplete) {
            try { & $job.OnComplete $output } catch { Write-CfgLog "Error al actualizar la interfaz: $($_.Exception.Message)" ERROR }
        }
        elseif (-not $fails.Count) { $script:Ui.StatusText.Text = "$($job.Title): completado." }
    }
}

# ------------------------------------------------------------------ detección

$script:DetectScript = {
    $sw = Get-CfgSoftwareCatalog
    $bw = Get-CfgBloatwareCatalog
    Write-CfgLog 'Detectando hardware, software, bloatware, ajustes, cuentas y estado de dominio/Intune...'
    $hw = Get-CfgHardware
    $r = @{
        Sys    = Get-CfgSystemSummary
        Join   = Get-CfgJoinStatus
        Hw     = $hw
        Compat = @(Test-CfgWin11Compat -Hw $hw)
        Rec    = @(Get-CfgHardwareRecommendations -Hw $hw)
        Sw     = Get-CfgSoftwareState -Catalog $sw
        Bw     = @(Get-CfgBloatwareState -Catalog $bw)
        Tw     = @(Get-CfgTweaks)
        Users  = @(Get-CfgLocalUsers)
        Mem    = Get-CfgMemoryUsage -Catalog $sw
        Ident  = Get-CfgDeviceIdentity
    }
    $present = @($r.Bw | Where-Object { $_.Present }).Count
    $inst = @($r.Sw.Values | Where-Object { $_ }).Count
    $gpu = (@($hw.Gpus | ForEach-Object { "$($_.Name) ($($_.Vendor))" }) -join ', ')
    Write-CfgLog ("Detección completada: gráfica {0}; {1} de {2} aplicaciones del catálogo instaladas; {3} elementos de bloatware presentes." -f $gpu, $inst, $sw.Count, $present) OK
    $r
}

function Start-CfgDetection {
    param([scriptblock]$Then)
    $script:G.AfterDetection = $Then
    Start-CfgTask -Title 'Detectando estado del equipo' -Script $script:DetectScript -OnComplete {
        param($out)
        if ($out -and $out.Count) { Set-CfgDetectionResult $out[0].psobject.BaseObject }
        $next = $script:G.AfterDetection
        $script:G.AfterDetection = $null
        if ($next) { & $next }
    }
}

function Start-CfgUpdateScan {
    param([scriptblock]$Then)
    $script:G.AfterUpdates = $Then
    Start-CfgTask -Title 'Buscando actualizaciones' -Arguments @([bool]$script:Ui.UpUnknown.IsChecked) -Script {
        param($Unknown) Get-CfgWingetUpgrades -IncludeUnknown:$Unknown
    } -OnComplete {
        param($out)
        Set-CfgUpdateList @($out | ForEach-Object { $_ })
        $next = $script:G.AfterUpdates
        $script:G.AfterUpdates = $null
        if ($next) { & $next }
    }
}

function Set-CfgDetectionResult {
    param($R)
    if (-not $R) { return }
    $script:G.LastDetect = $R
    $u = $script:Ui
    if ($R.Sys) {
        $script:G.Sys = $R.Sys
        $u.SysInfoList.ItemsSource = @(ConvertTo-CfgKeyValue $R.Sys.Display)
        $u.HeaderSubtitle.Text = Get-CfgAnon ('{0} · {1} · {2}' -f $R.Sys.Display['Equipo'], $R.Sys.Display['Fabricante / modelo'], $R.Sys.Display['Sistema operativo'])
        $u.HeaderAdmin.Text = $(if ($R.Sys.IsAdmin) { T 'Administrador' } else { T 'Sin elevar: funciones limitadas' })
    }
    if ($R.Join) {
        $disp = Get-CfgJoinDisplay -Status $R.Join
        $u.JoinInfoList.ItemsSource = @(ConvertTo-CfgKeyValue $disp)
        $u.EntraStatus.Text = (T 'Estado actual: {0}. Intune: {1}. IME: {2}.') -f $disp['Tipo de unión'], $disp['Inscrito en Intune (MDM)'], $disp['Intune Mgmt. Extension']
        if ($R.Join.DominioAD -and -not $u.DomName.Text) { $u.DomName.Text = $R.Join.DominioAD }
        if ($R.Join.IntuneUpn -and -not $u.AccUpn.Text) { $u.AccUpn.Text = $R.Join.IntuneUpn }
    }
    if ($R.Hw) {
        $script:G.Hw = $R.Hw
        $u.HwInfoList.ItemsSource = @(ConvertTo-CfgKeyValue (Get-CfgHardwareDisplay -Hw $R.Hw))
        $u.HwGpuGrid.ItemsSource = @($R.Hw.Gpus | ForEach-Object {
                [pscustomobject]@{ Name = $_.Name; Vendor = $_.Vendor; VramText = (Format-CfgSize $_.VramMB); DriverVersion = $_.DriverVersion
                    DriverDateText = $(if ($_.DriverDate) { $_.DriverDate.ToString('yyyy-MM-dd') } else { '' }) }
            })
        $u.HwDiskGrid.ItemsSource = @($R.Hw.Disks | ForEach-Object {
                [pscustomobject]@{ Model = $_.Model; Media = $_.Media; Bus = $_.Bus; SizeText = "$($_.SizeGB) GB"; Health = $_.Health; SystemText = $(if ($_.System) { T 'Sí' } else { '' }) }
            })
    }
    if ($R.Compat) { $u.HwCompatList.ItemsSource = @(ConvertTo-CfgCheckView $R.Compat) }
    if ($R.Rec) {
        $script:G.Rec = @($R.Rec)
        $u.HwRecList.ItemsSource = @($R.Rec | ForEach-Object { [pscustomobject]@{ Nivel = (T $_.Nivel); Texto = $_.Texto; SoftwareId = $_.SoftwareId } })
    }
    if ($R.Sw) {
        $script:G.SwState = $R.Sw
        foreach ($row in $script:SwTable.Rows) {
            $v = $R.Sw[$row['Id']]
            $row['Installed'] = [bool]$v
            $row['Status'] = $(if ($v) { T '✓ Instalado' } else { T 'No instalado' })
        }
        Update-CfgSwImpact
    }
    if ($R.Bw) {
        $byId = @{}
        foreach ($b in $R.Bw) { $byId[$b.Id] = $b }
        foreach ($row in $script:BwTable.Rows) {
            $b = $byId[$row['Id']]
            if ($b) { $row['Present'] = [bool]$b.Present; $row['StatusEs'] = $b.Status; $row['Status'] = (T $b.Status); $row['Restorable'] = [bool]$b.Restorable }
        }
        Update-CfgBwFilter
    }
    if ($R.Tw) {
        $byId = @{}
        foreach ($t in $R.Tw) { $byId[$t.Id] = $t }
        foreach ($row in $script:TwTable.Rows) {
            $t = $byId[$row['Id']]
            if ($t) { $row['Applied'] = [bool]$t.Applied; $row['Status'] = $(if ($t.Applied) { T '✓ Aplicado' } else { T 'No aplicado' }) }
        }
        Update-CfgTwSummary
    }
    if ($R.Users) { Set-CfgUserList $R.Users }
    if ($R.Mem) { Set-CfgMemoryView $R.Mem }
    if ($R.Ident) { Set-CfgIdentityView $R.Ident }
}

function Set-CfgIdentityView {
    param($Id)
    if (-not $Id) { return }
    $script:G.Ident = $Id
    $disp = [ordered]@{}
    foreach ($k in @($Id.Display.Keys)) {
        $v = [string]$Id.Display[$k]
        # Las capturas de la documentación no muestran números de serie reales
        if ($script:G.CapturePath -and $k -in @('Número de serie', 'Service Tag', 'Express Service Code', 'UUID')) { $v = 'XXXXXXXX' }
        $disp[$k] = $v
    }
    $script:Ui.HwIdList.ItemsSource = @(ConvertTo-CfgKeyValue $disp)
    $script:Ui.HwIdNote.Text = $(if ($Id.IsBrand) { '' } else { T 'Equipo montado por piezas: el fabricante no ha grabado modelo ni número de serie del equipo. Para soporte y garantía usa el modelo de la placa base y el número de serie de cada componente.' })
    $script:Ui.HwIdNote.Visibility = $(if ($Id.IsBrand) { 'Collapsed' } else { 'Visible' })
    $script:Ui.BtnHwWarranty.IsEnabled = [bool]$Id.WarrantyUrl
}

function Set-CfgMemoryView {
    param($Mem)
    if (-not $Mem) { return }
    $script:G.Mem = $Mem
    $u = $script:Ui
    $u.HwMemSummary.Text = (T 'En uso ahora: {0} de {1} ({2:N0} %) · libres {3} · medido a las {4}.') -f (Format-CfgSize $Mem.UsedMB), (Format-CfgSize $Mem.TotalMB), (100 * $Mem.UsedMB / [math]::Max(1, $Mem.TotalMB)), (Format-CfgSize $Mem.FreeMB), $Mem.At
    $u.HwMemGrid.ItemsSource = @($Mem.Top | ForEach-Object { [pscustomobject]@{ Programa = (Get-CfgAnon $_.Programa); Procesos = $_.Procesos; Ram = $_.Ram } })
    Update-CfgSwImpact
    if ($script:G.DetailId) { Show-CfgSwDetail $script:G.DetailId }
}

function Set-CfgUserList {
    param($Users)
    $script:G.LastUsers = @($Users)
    $script:Ui.AccLocalGrid.ItemsSource = @($Users | ForEach-Object {
            [pscustomobject]@{ Name = (Get-CfgAnon $_.Name); FullName = $(if ($script:G.CapturePath -and $_.FullName) { 'Usuario de ejemplo' } else { $_.FullName }); EnabledText = $(if ($_.Enabled) { T 'Sí' } else { T 'No' }); AdminText = $(if ($_.Admin) { T 'Sí' } else { '' }); LastLogon = $(if ($_.LastLogon -eq 'Nunca') { T 'Nunca' } else { $_.LastLogon }) }
        })
}

# ------------------------------------------------------------------ software

function Initialize-CfgSoftwareTab {
    $t = New-CfgDataTable 'Software' @('Id', 'Name', 'Category', 'CategoryText', 'Status', 'DiskText', 'RamText', 'Source') @('Selected', 'Installed')
    foreach ($i in $script:G.SwCatalog) {
        $r = $t.NewRow()
        $r['Id'] = $i.id; $r['Name'] = $i.name; $r['Category'] = $i.category; $r['CategoryText'] = (T $i.category); $r['Status'] = (T 'Detectando...')
        $r['DiskText'] = Format-CfgSize $i.impact.diskMB; $r['RamText'] = Format-CfgSize $i.impact.ramMB
        $r['Source'] = $i.source; $r['Selected'] = $false; $r['Installed'] = $false
        $t.Rows.Add($r)
    }
    $script:SwTable = $t
    $script:Ui.SwGrid.ItemsSource = $t.DefaultView
    Update-CfgCategoryList
    $t.Add_ColumnChanged({ param($s, $e) if ($e.Column.ColumnName -eq 'Selected') { Update-CfgSwImpact } })
}

function Update-CfgCategoryList {
    $sel = $script:Ui.SwCategory.SelectedIndex
    $cats = @([pscustomobject]@{ Value = ''; Text = (T 'Todas') }) + @($script:G.SwCatalog | ForEach-Object { $_.category } | Select-Object -Unique | ForEach-Object { [pscustomobject]@{ Value = $_; Text = (T $_) } })
    $script:Ui.SwCategory.DisplayMemberPath = 'Text'
    $script:Ui.SwCategory.ItemsSource = $cats
    $script:Ui.SwCategory.SelectedIndex = [math]::Max(0, $sel)
}

function Update-CfgSwFilter {
    $parts = @()
    $txt = ($script:Ui.SwSearch.Text -replace "[\[\]\*%']", '').Trim()
    if ($txt) { $parts += "(Name LIKE '%$txt%' OR CategoryText LIKE '%$txt%' OR Id LIKE '%$txt%')" }
    $cat = $script:Ui.SwCategory.SelectedItem
    if ($cat -and $cat.Value) { $parts += "Category = '$($cat.Value.Replace("'", "''"))'" }
    if ($script:Ui.SwOnlyMissing.IsChecked) { $parts += 'Installed = false' }
    $script:SwTable.DefaultView.RowFilter = ($parts -join ' AND ')
}

function Update-CfgSwImpact {
    $ids = Get-CfgSelectedIds $script:SwTable
    if (-not $ids.Count) { $script:Ui.SwImpactSummary.Text = T 'Marca aplicaciones para ver el impacto total de la selección.'; return }
    $cat = $script:G.SwCatalog
    $order = @(Resolve-CfgDependencies -Ids $ids -Catalog $cat)
    $toInstall = @($order | Where-Object { -not $script:G.SwState[$_] })
    $deps = @($toInstall | Where-Object { $ids -notcontains $_ } | ForEach-Object { $script:G.SwById[$_].name })
    $imp = Measure-CfgSoftwareImpact -Ids $toInstall -Catalog $cat
    $sys = $script:G.Sys
    $lines = @()
    $l1 = (T '{0} marcadas · {1} se instalarán') -f $ids.Count, $toInstall.Count
    if ($deps.Count) { $l1 += ' (' + ((T 'incluye dependencias: {0}') -f ($deps -join ', ')) + ')' }
    $lines += $l1
    if ($toInstall.Count) {
        $disk = (T 'Disco: ~{0}') -f (Format-CfgSize $imp.DiskMB)
        $ram = (T 'RAM en uso: ~{0}') -f (Format-CfgSize $imp.RamMB)
        if ($sys) {
            $disk += ' ' + ((T 'de {0} libres') -f (Format-CfgSize $sys.DiskFreeMB))
            $ram += ' ({0:N0} % / {1})' -f (100 * $imp.RamMB / [math]::Max(1, $sys.RamTotalMB)), (Format-CfgSize $sys.RamTotalMB)
        }
        $l2 = "$disk · $ram"
        if ($imp.Startup.Count) { $l2 += ' · ' + ((T 'Arrancan con Windows: {0}') -f $imp.Startup.Count) }
        $lines += $l2
        if ($imp.Services.Count) { $lines += (T 'Servicios nuevos: {0}') -f ($imp.Services -join ', ') }
        $manual = @($toInstall | Where-Object { $script:G.SwById[$_].source -eq 'url' } | ForEach-Object { $script:G.SwById[$_].name })
        if ($manual.Count) { $lines += (T 'Descarga manual (no están en winget): {0}') -f ($manual -join ', ') }
        if ($sys) {
            if ($imp.DiskMB -gt $sys.DiskFreeMB * 0.8) { $lines += T '⚠ La selección ocuparía casi todo el espacio libre del disco.' }
            if ($imp.RamMB -gt $sys.RamTotalMB * 0.5) { $lines += T '⚠ Usadas a la vez consumirían más de la mitad de la RAM del equipo.' }
        }
    }
    # Consumo real: lo que ya está en marcha en este equipo + lo que añadiría la selección
    $mem = $script:G.Mem
    if ($mem) {
        $after = $mem.UsedMB + $imp.RamMB
        $pctNow = 100 * $mem.UsedMB / [math]::Max(1, $mem.TotalMB)
        $pctAfter = 100 * $after / [math]::Max(1, $mem.TotalMB)
        $lines += (T 'RAM real ahora: {0} de {1} ({2:N0} %) · con la selección abierta: ~{3} ({4:N0} %)') -f (Format-CfgSize $mem.UsedMB), (Format-CfgSize $mem.TotalMB), $pctNow, (Format-CfgSize $after), $pctAfter
        $running = @($ids | Where-Object { $mem.ByItem[$_] } | ForEach-Object { '{0} {1}' -f $script:G.SwById[$_].name, (Format-CfgSize $mem.ByItem[$_].MB) })
        if ($running.Count) { $lines += (T 'Ya en ejecución (consumo real): {0}') -f ($running -join ', ') }
        if ($pctAfter -ge 90) { $lines += T '⚠ Con la selección en marcha el equipo se quedaría casi sin memoria libre: cierra programas o amplía la RAM.' }
        elseif ($pctAfter -ge 75) { $lines += T '⚠ La memoria quedaría por encima del 75 %: puede notarse lentitud con muchas aplicaciones abiertas.' }
    }
    $script:Ui.SwImpactSummary.Text = $lines -join "`n"
}

function Show-CfgSwDetail {
    param([string]$Id)
    $i = $script:G.SwById[$Id]
    if (-not $i) { return }
    $script:G.DetailId = $Id
    $u = $script:Ui
    $state = $script:G.SwState[$Id]
    $src = switch ($i.source) {
        'winget' { "winget: $($i.packageId)" } 'msstore' { "Microsoft Store: $($i.packageId)" } 'feature' { T 'Característica de Windows' }
        'capability' { T 'Capacidad de Windows (Windows Update)' } 'url' { T 'Descarga oficial (manual)' } default { "$(T 'Paquete local'): $($i.localPath)" }
    }
    $u.SwDetName.Text = $i.name
    $u.SwDetMeta.Text = '{0} · {1} · {2}' -f (T $i.category), $src, $(if ($state) { "$(T 'Instalado') ($state)" } else { T 'No instalado' })
    $u.SwDetDesc.Text = $i.description
    $deps = @($i.dependencies | Where-Object { $_ })
    $depText = if ($deps.Count) {
        (@(foreach ($d in $deps) {
                    $di = $script:G.SwById[$d]
                    '• {0} — {1}' -f $(if ($di) { $di.name } else { $d }), $(if ($script:G.SwState[$d]) { T 'ya instalada' } else { T 'se instalará automáticamente antes' })
                }) -join "`n")
    }
    else { T 'Ninguna: se instala de forma autónoma.' }
    $needed = @($script:G.SwCatalog | Where-Object { @($_.dependencies) -contains $Id } | ForEach-Object { $_.name })
    if ($needed.Count) { $depText += "`n" + ((T 'Es necesaria para: {0}') -f ($needed -join ', ')) }
    $u.SwDetDeps.Text = $depText
    $u.SwDetReq.Text = $(if ($i.requirements) { $i.requirements } else { '—' })
    $im = $i.impact
    $ramPct = ''
    if ($script:G.Sys -and $im.ramMB) { $ramPct = ' ' + ((T '({0:N1} % de la RAM de este equipo)') -f (100 * $im.ramMB / [math]::Max(1, $script:G.Sys.RamTotalMB))) }
    $yes = T 'Sí'; $no = T 'No'
    $txt = @(
        ('{0}: ~{1}' -f (T 'Disco'), (Format-CfgSize $im.diskMB))
        ('{0}: {1}' -f (T 'RAM típica en uso'), $(if ($im.ramMB) { '~' + (Format-CfgSize $im.ramMB) + $ramPct } else { T 'insignificante' }))
        ('{0}: {1}' -f (T 'Consumo real ahora'), $(if ($script:G.Mem -and $script:G.Mem.ByItem[$Id]) { (T '{0} en {1} procesos (medido a las {2})') -f (Format-CfgSize $script:G.Mem.ByItem[$Id].MB), $script:G.Mem.ByItem[$Id].Procesos, $script:G.Mem.At } elseif ($state) { T 'no se está ejecutando' } else { T 'no instalada' }))
        ('CPU: {0}' -f (T $im.cpu))
        ('{0}: {1}' -f (T 'Se inicia con Windows'), $(if ($im.startup) { $yes } else { $no }))
        ('{0}: {1}' -f (T 'Servicios que añade'), $(if (@($im.services).Count) { $im.services -join ', ' } else { T 'ninguno' }))
        ('{0}: {1}' -f (T 'Tareas programadas'), $(if (@($im.scheduledTasks).Count) { $im.scheduledTasks -join ', ' } else { T 'ninguna' }))
    ) -join "`n"
    if ($im.notes) { $txt += "`n`n$($im.notes)" }
    $u.SwDetImpact.Text = $txt
    $u.SwDetNotes.Text = $(if ($i.notes) { $i.notes } else { '—' })
}

function Set-CfgSoftwareSelection {
    param([string[]]$Ids, [switch]$Add)
    foreach ($r in $script:SwTable.Rows) {
        $sel = ($Ids -contains $r['Id'])
        if ($Add) { if ($sel) { $r['Selected'] = $true } } else { $r['Selected'] = $sel }
    }
}

function Show-CfgInstallFailures {
    <# Muestra lo que no se pudo instalar/actualizar con su enlace de descarga manual. #>
    param($Failures, [string]$Kind = 'update', [switch]$NoDialog)
    $f = @($Failures | Where-Object { $_ })
    $linkText = T 'Descargar manualmente'
    if ($Kind -eq 'update') {
        $script:Ui.UpFailGrid.ItemsSource = @($f | ForEach-Object {
                [pscustomobject]@{ Name = $_.Name; Version = $_.Version; Available = $_.Available; Reason = $(if ($_.PSObject.Properties["Sha256"] -and $_.Sha256) { "{0} {1}: {2}" -f (T $_.Reason), (T "Comprueba que el instalador descargado tiene esta huella SHA-256"), $_.Sha256 } else { T $_.Reason }); Link = $_.Link; LinkText = $linkText }
            })
        $script:Ui.UpFailPanel.Visibility = $(if ($f.Count) { 'Visible' } else { 'Collapsed' })
    }
    if (-not $f.Count -or $NoDialog) { return }
    $list = ($f | ForEach-Object { if ($_.Available) { '• {0} ({1} → {2})' -f $_.Name, $_.Version, $_.Available } else { '• {0}' -f $_.Name } }) -join "`n"
    $title = if ($Kind -eq 'update') { T 'No se ha podido instalar la actualización de:' } else { T 'No se ha podido instalar:' }
    $msg = "$title`n`n$list`n`n" + (T 'Puedes descargarlo e instalarlo manualmente desde la web del fabricante. ¿Abrir ahora las páginas de descarga?')
    if ((Show-CfgMessage -Text $msg -Icon 'Warning' -Buttons 'YesNo') -eq 'Yes') {
        foreach ($x in $f) { if ($x.Link) { Write-CfgLog ("Abriendo descarga manual de {0}: {1}{2}" -f $x.Name, $x.Link, $(if ($x.PSObject.Properties["Sha256"] -and $x.Sha256) { " · SHA-256 esperado: " + $x.Sha256 } else { "" })); Start-Process ([string]$x.Link) } }
    }
}

# ------------------------------------------------------------------ actualizaciones

function Initialize-CfgUpdatesTab {
    $script:UpTable = New-CfgDataTable 'Updates' @('Name', 'Id', 'Version', 'Available', 'Source') @('Selected')
    $script:Ui.UpGrid.ItemsSource = $script:UpTable.DefaultView
}

function Set-CfgUpdateList {
    param($List)
    $script:UpTable.Rows.Clear()
    foreach ($u in $List) {
        if (-not $u -or -not $u.PSObject.Properties['Id']) { continue }
        $r = $script:UpTable.NewRow()
        $r['Name'] = $u.Name; $r['Id'] = $u.Id; $r['Version'] = $u.Version; $r['Available'] = $u.Available; $r['Source'] = $u.Source; $r['Selected'] = $true
        $script:UpTable.Rows.Add($r)
    }
    $script:G.UpCheckedAt = Get-Date -Format 'HH:mm'
    Update-CfgUpdateSummary
}

function Update-CfgUpdateSummary {
    if (-not $script:G.UpCheckedAt) { return }
    $n = $script:UpTable.Rows.Count
    $script:Ui.UpSummary.Text = $(if ($n) { (T "{0} actualizaciones disponibles (comprobado a las {1}). 'Actualizar todo' lanza winget upgrade --all en modo silencioso y comprueba el resultado.") -f $n, $script:G.UpCheckedAt } else { (T 'Todo al día según winget (comprobado a las {0}).') -f $script:G.UpCheckedAt })
    $script:Ui.Tabs.Items[3].Header = $(if ($n) { '{0} ({1})' -f (T 'Actualizaciones'), $n } else { T 'Actualizaciones' })
}

# ------------------------------------------------------------------ bloatware

function Initialize-CfgBloatwareTab {
    $t = New-CfgDataTable 'Bloatware' @('Id', 'Name', 'Type', 'Risk', 'RiskText', 'Status', 'StatusEs', 'Description') @('Selected', 'Present', 'Recommended', 'Restorable')
    foreach ($b in $script:G.BwCatalog) {
        $r = $t.NewRow()
        $r['Id'] = $b.id; $r['Name'] = $b.name; $r['Type'] = $b.type; $r['Risk'] = $b.risk; $r['RiskText'] = (T $b.risk)
        $r['Status'] = (T 'Detectando...'); $r['StatusEs'] = ''; $r['Description'] = $b.description
        $r['Selected'] = $false; $r['Present'] = $true; $r['Recommended'] = [bool]$b.recommended; $r['Restorable'] = $false
        $t.Rows.Add($r)
    }
    $script:BwTable = $t
    $script:Ui.BwGrid.ItemsSource = $t.DefaultView
    $t.Add_ColumnChanged({ param($s, $e) if ($e.Column.ColumnName -eq 'Selected') { Update-CfgBwSummary } })
}

function Update-CfgBwFilter {
    $script:BwTable.DefaultView.RowFilter = $(if ($script:Ui.BwOnlyPresent.IsChecked) { 'Present = true' } else { '' })
    Update-CfgBwSummary
}

function Update-CfgBwSummary {
    $sel = @($script:BwTable.Rows | Where-Object { $_['Selected'] -eq $true })
    $present = @($script:BwTable.Rows | Where-Object { $_['Present'] -eq $true }).Count
    $restorable = @($script:BwTable.Rows | Where-Object { -not $_['Present'] -and $_['Restorable'] }).Count
    $risky = @($sel | Where-Object { $_['Risk'] -ne 'Bajo' } | ForEach-Object { $_['Name'] })
    $t = (T "{0} presentes · {1} reinstalables (desmarca 'Solo los presentes' para verlos) · {2} marcados.") -f $present, $restorable, $sel.Count
    if ($risky.Count) { $t += ' ' + ((T 'Riesgo medio/alto: {0}.') -f ($risky -join ', ')) }
    $script:Ui.BwSummary.Text = $t
}

# ------------------------------------------------------------------ ajustes

function Initialize-CfgTweaksTab {
    $t = New-CfgDataTable 'Tweaks' @('Id', 'NameEs', 'Name', 'CategoryEs', 'Category', 'ScopeEs', 'Scope', 'Status', 'Description') @('Selected', 'Applied')
    foreach ($tw in $script:G.TwCatalog) {
        $r = $t.NewRow()
        $r['Id'] = $tw.Id; $r['NameEs'] = $tw.Name; $r['CategoryEs'] = $tw.Category; $r['ScopeEs'] = $tw.Scope
        $r['Applied'] = [bool]$tw.Applied; $r['Description'] = $tw.Description; $r['Selected'] = $false
        $t.Rows.Add($r)
    }
    $script:TwTable = $t
    Update-CfgTweakTexts
    $script:Ui.TwGrid.ItemsSource = $t.DefaultView
    $t.Add_ColumnChanged({ param($s, $e) if ($e.Column.ColumnName -eq 'Selected') { Update-CfgTwSummary } })
}

function Update-CfgTweakTexts {
    foreach ($r in $script:TwTable.Rows) {
        $r['Name'] = T $r['NameEs']; $r['Category'] = T $r['CategoryEs']; $r['Scope'] = T $r['ScopeEs']
        $r['Status'] = $(if ($r['Applied']) { T '✓ Aplicado' } else { T 'No aplicado' })
    }
}

function Update-CfgTwSummary {
    $sel = @(Get-CfgSelectedIds $script:TwTable).Count
    $applied = @($script:TwTable.Rows | Where-Object { $_['Applied'] -eq $true }).Count
    $script:Ui.TwSummary.Text = (T '{0} de {1} ajustes ya aplicados · {2} marcados.') -f $applied, $script:TwTable.Rows.Count, $sel
}

# ------------------------------------------------------------------ perfiles

function Update-CfgProfileDesc {
    $p = $script:Ui.ProfileCombo.SelectedItem
    if (-not $p) { return }
    $vendors = @(); if ($script:G.Hw) { $vendors = @($script:G.Hw.GpuVendors) }
    $swIds = @(Resolve-CfgHardwareSoftware -Ids @($p.software) -GpuVendors $(if ($vendors.Count) { $vendors } else { @('—') }))
    $sw = @($swIds | ForEach-Object { if ($script:G.SwById[$_]) { $script:G.SwById[$_].name } else { $_ } })
    $bw = @(Get-CfgProfileBloatwareIds -ProfileItem $p)
    $tw = @(Get-CfgProfileTweaks -ProfileItem $p)
    $steps = @()
    if ($p.restorePoint) { $steps += T 'punto de restauración' }
    if ($bw.Count) { $steps += (T 'quitar hasta {0} apps de bloatware') -f $bw.Count }
    if ($tw.Count) { $steps += (T '{0} ajustes') -f $tw.Count }
    if ($sw.Count) { $steps += (T 'instalar {0} aplicaciones') -f $sw.Count }
    if ($p.upgradeAll) { $steps += T 'actualizar todo' }
    if ($p.gpupdate) { $steps += T 'gpupdate (si hay dominio)' }
    if ($p.intuneSync) { $steps += T 'sincronizar Intune' }
    $gpuNote = if (@($p.software) -contains '@gpu') { "`n" + ((T 'Controladores: según la gráfica detectada ({0}).') -f $(if ($vendors.Count) { $vendors -join ', ' } else { T 'pendiente de detectar' })) } else { '' }
    $script:Ui.ProfileDesc.Text = "$(T $p.description)`n`n$(T 'Pasos'): $($steps -join ' → ').$gpuNote`n$(T 'Software'): $($sw -join ', ')."
}

function Update-CfgProfileNames {
    foreach ($p in $script:G.Profiles) { $p | Add-Member -NotePropertyName display -NotePropertyValue (T $p.name) -Force }
    foreach ($c in $script:Ui.ProfileCombo, $script:Ui.UsbProfile) {
        $i = $c.SelectedIndex
        $c.DisplayMemberPath = 'display'
        $c.ItemsSource = $null; $c.ItemsSource = $script:G.Profiles
        $c.SelectedIndex = [math]::Max(0, $i)
    }
}
function Set-CfgProfileSelection {
    $p = $script:Ui.ProfileCombo.SelectedItem
    if (-not $p) { return }
    $vendors = @(); if ($script:G.Hw) { $vendors = @($script:G.Hw.GpuVendors) }
    $swIds = @(Resolve-CfgHardwareSoftware -Ids @($p.software) -GpuVendors $(if ($vendors.Count) { $vendors } else { @('—') }))
    $bw = @(Get-CfgProfileBloatwareIds -ProfileItem $p)
    $tw = @(Get-CfgProfileTweaks -ProfileItem $p)
    Set-CfgSoftwareSelection -Ids $swIds
    foreach ($r in $script:BwTable.Rows) { $r['Selected'] = ($bw -contains $r['Id'] -and $r['Present']) }
    foreach ($r in $script:TwTable.Rows) { $r['Selected'] = ($tw -contains $r['Id']) }
    $script:Ui.Tabs.SelectedIndex = 2
    Write-CfgLog "Selección del perfil '$($p.name)' marcada en Software, Bloatware y Ajustes. Revísala y usa los botones de cada pestaña."
}

function Invoke-CfgAccountFlow {
    param([string]$Mode)
    $upn = $script:Ui.AccUpn.Text.Trim()
    if ($upn -and -not (Test-CfgUpn $upn)) { Show-CfgMessage 'La cuenta debe tener el formato usuario@empresa.com.' 'Warning' | Out-Null; return }
    Start-CfgWorkAccountFlow -Mode $Mode -Upn $upn
}

# ------------------------------------------------------------------ instalación de Windows (USB)

function Initialize-CfgUsbTab {
    $u = $script:Ui
    $u.UsbRegion.ItemsSource = @(Get-CfgInstallRegions)
    $u.UsbRegion.SelectedIndex = 0
    $u.UsbTimeZone.ItemsSource = @(Get-CfgTimeZones)
    $u.UsbTimeZone.SelectedIndex = 0
    $u.UsbProfile.ItemsSource = $script:G.Profiles
    $u.UsbProfile.SelectedIndex = 0
    Update-CfgUsbDisks
}

function Update-CfgUsbDisks {
    $d = @(Get-CfgUsbDisks)
    $script:Ui.UsbDisk.ItemsSource = $d
    if ($d.Count) { $script:Ui.UsbDisk.SelectedIndex = 0 }
}

function Get-CfgUsbSettings {
    $u = $script:Ui
    $region = $u.UsbRegion.SelectedItem
    $iso = $script:G.Iso
    return @{
        Arch          = $(if ($iso) { $iso.Arch } else { 'amd64' })
        UILanguage    = $(if ($iso) { $iso.Language } else { $region.Id })
        Region        = $region.Id
        InputLocale   = $region.Input
        TimeZone      = $u.UsbTimeZone.SelectedItem.Id
        EditionName   = $(if ($u.UsbEdition.SelectedItem) { $u.UsbEdition.SelectedItem.Name } else { '' })
        ProductKey    = $u.UsbProductKey.Text.Trim().ToUpper()
        ComputerName  = $u.UsbComputerName.Text.Trim()
        DiskMode      = $(if ($u.UsbDiskWipe.IsChecked) { 'wipe0' } else { 'manual' })
        AccountMode   = $(if ($u.UsbAccWork.IsChecked) { 'work' } else { 'local' })
        LocalUser     = $u.UsbUser.Text.Trim()
        LocalFullName = $u.UsbFullName.Text.Trim()
        LocalPassword = $u.UsbPassword.Password
        AutoLogon     = [bool]$u.UsbAutoLogon.IsChecked
    }
}

function Get-CfgUsbPostInstall {
    $u = $script:Ui
    $mode = @('none', 'mdm', 'aadj')[[math]::Max(0, $u.UsbEnroll.SelectedIndex)]
    return @{
        profile   = $u.UsbProfile.SelectedItem.name
        autoApply = [bool]$u.UsbAutoApply.IsChecked
        upn       = $u.UsbWorkUpn.Text.Trim()
        enroll    = $mode
        created   = (Get-Date -Format 's')
    }
}

function Test-CfgUsbForm {
    $s = Get-CfgUsbSettings
    $err = @(Test-CfgInstallSettings -S $s)
    if (-not $script:G.Iso) { $err = @('Primero selecciona una ISO y pulsa "Leer ISO".') + $err }
    if ($s.AccountMode -eq 'local' -and $script:Ui.UsbPassword.Password -ne $script:Ui.UsbPassword2.Password) { $err += 'Las contraseñas no coinciden.' }
    $pi = Get-CfgUsbPostInstall
    if ($pi.enroll -ne 'none' -and -not (Test-CfgUpn $pi.upn)) { $err += 'Para inscribir tras instalar indica la cuenta profesional (usuario@empresa.com).' }
    if ($err.Count) { Show-CfgMessage ("Revisa estos datos:`n`n• " + ($err -join "`n• ")) 'Warning' | Out-Null; return $null }
    return $s
}

# ------------------------------------------------------------------ post-instalación

function Start-CfgPostInstall {
    $pi = $script:G.PostInstall
    if (-not $pi) { return }
    $u = $script:Ui
    $u.PostBanner.Visibility = 'Visible'
    $u.PostBannerText.Text = "Configuración posterior a la instalación de Windows · perfil '$($pi.profile)'. No apagues el equipo; puedes seguir el progreso en la pestaña Registro."
    for ($k = 0; $k -lt $script:G.Profiles.Count; $k++) { if ($script:G.Profiles[$k].name -eq $pi.profile) { $u.ProfileCombo.SelectedIndex = $k } }
    if (-not $pi.autoApply) { Write-CfgLog 'Post-instalación: revisa el perfil seleccionado y pulsa "Aplicar perfil".'; return }
    $u.Tabs.SelectedIndex = 10
    Start-CfgTask -Title "Post-instalación: perfil $($pi.profile)" -Arguments @($pi.profile) -Script { param($n) Invoke-CfgProfile -Name $n -PostInstall; Complete-CfgPostInstall } -OnComplete {
        $p = $script:G.PostInstall
        if ($p.enroll -in @('mdm', 'aadj') -and $p.upn) { Start-CfgWorkAccountFlow -Mode $p.enroll -Upn $p.upn }
        $script:Ui.PostBannerText.Text = 'Configuración posterior a la instalación terminada. Revisa el registro; algunos cambios requieren reiniciar.'
        Start-CfgDetection -Then { Start-CfgUpdateScan }
    }
}

# ------------------------------------------------------------------ diagnóstico

function Initialize-CfgDiagTab {
    $u = $script:Ui
    $u.MmcPanel.Children.Clear()
    foreach ($c in @(Get-CfgConsoles)) {
        $b = New-Object System.Windows.Controls.Button
        $b.Content = T $c.Name
        $b.Tag = $c.Id
        $b.ToolTip = $(if ($c.Note) { '{0} · {1}' -f $c.Id, (T $c.Note) } else { $c.Id })
        $b.IsEnabled = $c.Available
        $b.Add_Click({ param($s, $e) Start-CfgConsole -Id ([string]$s.Tag) })
        [void]$u.MmcPanel.Children.Add($b)
    }
    # Enlaces a escáneres de rescate (se conserva el botón de Safety Scanner)
    while ($u.RescuePanel.Children.Count -gt 1) { $u.RescuePanel.Children.RemoveAt(1) }
    $links = Get-CfgRescueLinks
    foreach ($k in @($links.Keys)) {
        $b = New-Object System.Windows.Controls.Button
        $b.Content = T $k
        $b.Tag = $links[$k]
        $b.ToolTip = $links[$k]
        $b.Add_Click({ param($s, $e) Write-CfgLog "Abriendo $($s.Tag)"; Start-Process ([string]$s.Tag) })
        [void]$u.RescuePanel.Children.Add($b)
    }
}

# ------------------------------------------------------------------ drivers y BIOS

function Initialize-CfgDriversTab {
    $script:DrvUpTable = New-CfgDataTable 'DriverUpdates' @('UpdateId', 'Titulo', 'Clase', 'Fecha', 'Tamano') @('Selected', 'Firmware')
    $script:Ui.DrvUpGrid.ItemsSource = $script:DrvUpTable.DefaultView
}

function Update-CfgDeviceView {
    $all = @($script:G.Devices)
    if (-not $all.Count) { return }
    $view = if ($script:Ui.DrvOnlyProblems.IsChecked) { @($all | Where-Object { $_.Problema }) } else { $all }
    $script:Ui.DrvGrid.ItemsSource = @($view | ForEach-Object { [pscustomobject]@{ Clase = $_.Clase; Dispositivo = $_.Dispositivo; Fabricante = $_.Fabricante; Version = $_.Version; Fecha = $_.Fecha; Firmado = $(if ($_.Firmado) { T $_.Firmado } else { '' }); Estado = $(if ($_.Estado -like 'Error*') { $_.Estado } else { T $_.Estado }) } })
    $problems = @($all | Where-Object { $_.Problema }).Count
    $unsigned = @($all | Where-Object { $_.Firmado -eq 'No' }).Count
    $limit = (Get-Date).AddYears(-3).ToString('yyyy-MM-dd')
    $old = @($all | Where-Object { $_.Fecha -and $_.Fecha -lt $limit -and $_.Fabricante -notmatch '^(Microsoft|\(Standard|\(Est)' }).Count
    $t = (T '{0} dispositivos · {1} con problemas · {2} controladores sin firmar · {3} controladores de terceros con más de 3 años.') -f $all.Count, $problems, $unsigned, $old
    if ($problems) { $t += ' ' + (T "Los dispositivos con error aparecen primero: prueba 'Buscar en Windows Update' o la herramienta del fabricante.") }
    $script:Ui.DrvSummary.Text = $t
}

function Set-CfgDriverUpdates {
    param($List)
    $script:DrvUpTable.Rows.Clear()
    foreach ($d in @($List | Where-Object { $_ -and $_.PSObject.Properties['UpdateId'] })) {
        $r = $script:DrvUpTable.NewRow()
        $r['UpdateId'] = $d.UpdateId; $r['Titulo'] = $(if ($d.Firmware) { "[BIOS/firmware] $($d.Titulo)" } else { $d.Titulo }); $r['Clase'] = $d.Clase
        $r['Fecha'] = $d.Fecha; $r['Tamano'] = $d.Tamano; $r['Firmware'] = [bool]$d.Firmware; $r['Selected'] = -not $d.Firmware
        $script:DrvUpTable.Rows.Add($r)
    }
}

function Set-CfgFirmwareView {
    param($R)
    if (-not $R -or -not $R.Fw) { return }
    $fw = $R.Fw
    $script:G.Fw = $fw
    $u = $script:Ui
    $months = if ($null -ne $fw.BiosAgeDays) { [int]($fw.BiosAgeDays / 30) } else { $null }
    $disp = [ordered]@{
        'Fabricante (soporte)' = $(if ($fw.VendorText) { Get-CfgAnon ("$($fw.VendorText) · $($fw.Model)") } else { '—' })
        'BIOS'                 = '{0} {1}' -f $fw.BiosVendor, $fw.BiosVersion
        'Fecha de la BIOS'     = $(if ($fw.BiosDate) { '{0} ({1})' -f $fw.BiosDate, ((T 'hace {0} meses') -f $months) } else { '—' })
        'Modo de firmware'     = $(if ($fw.IsUefi) { 'UEFI' } else { T 'BIOS heredada (Legacy/CSM)' })
        'Arranque seguro'      = $(if ($fw.SecureBoot) { T 'Activado' } elseif ($fw.IsUefi) { T 'Desactivado' } else { T 'No disponible (modo BIOS heredada)' })
        'Disco del sistema'    = $(if ($fw.DiskStyle) { $fw.DiskStyle } else { '—' })
        'SMBIOS'               = $fw.Smbios
    }
    $u.FwInfoList.ItemsSource = @(ConvertTo-CfgKeyValue $disp)
    $u.FwAdvice.Text = $(if ($null -eq $months) { '' } elseif ($months -ge 24) { (T '⚠ La BIOS tiene más de 2 años ({0} meses). Los fabricantes publican versiones con parches de seguridad, compatibilidad con nuevos procesadores y memoria, y estabilidad: revisa si hay una más reciente.') -f $months } elseif ($months -ge 12) { T 'La BIOS tiene más de un año: conviene comprobar si hay una versión más reciente.' } else { T '✓ La BIOS es reciente (menos de un año).' })
    $u.GameChecks.ItemsSource = @($R.Checks | Where-Object { $_ } | ForEach-Object { [pscustomobject]@{ Comprobacion = (T $_.Comprobacion); Resultado = (T $_.Resultado); Detalle = (T $_.Detalle) } })
    $u.FwGuide.Text = (@($R.Guide) | ForEach-Object { T $_ }) -join ' '
    $u.BtnMbrConvert.IsEnabled = ($fw.DiskStyle -eq 'MBR')
}

# ------------------------------------------------------------------ versión nueva de Eureka_Utils

function Start-CfgReleaseCheck {
    <# Comprueba en segundo plano (runspace propio, no bloquea otras tareas) si hay una release nueva. #>
    param([switch]$Manual)
    if ($script:G.RelCheck) { return }
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass
    $iss.ImportPSModule([string[]]@(@('Core', 'Updates') | ForEach-Object { Join-Path $script:G.Root "Modules\$_.psm1" }))
    $rs = [runspacefactory]::CreateRunspace($iss); $rs.Open()
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript('param($r, $l, $q) Set-CfgEnvironment -Root $r -LogFile $l -LogQueue $q | Out-Null; Get-CfgLatestRelease')
    [void]$ps.AddArgument($script:G.Root).AddArgument($script:G.LogFile).AddArgument($script:G.Queue)
    $script:G.RelCheck = @{ PS = $ps; RS = $rs; Handle = $ps.BeginInvoke(); Manual = [bool]$Manual }
}

function Complete-CfgReleaseCheck {
    $job = $script:G.RelCheck
    if (-not $job -or -not $job.Handle.IsCompleted) { return }
    $script:G.RelCheck = $null
    $rel = $null
    try { $rel = @($job.PS.EndInvoke($job.Handle)) | Where-Object { $_ -and $_.PSObject.Properties['IsNewer'] } | Select-Object -First 1 } catch { }
    $job.PS.Dispose(); $job.RS.Close(); $job.RS.Dispose()
    if (-not $rel) { if ($job.Manual) { Show-CfgMessage 'No se pudo comprobar si hay una versión nueva (sin conexión con GitHub). Inténtalo más tarde.' 'Warning' | Out-Null }; return }
    $script:G.Release = $rel
    $prefs = Get-CfgPrefs
    $skipped = ($prefs.PSObject.Properties['SkipVersion'] -and $prefs.SkipVersion -eq "$($rel.Version)")
    if ($rel.IsNewer -and ($job.Manual -or -not $skipped)) {
        $script:Ui.UpdateBannerText.Text = (T 'Hay una versión nueva de Eureka_Utils: {0} (tienes la {1}).') -f $rel.Version, (Get-CfgVersion)
        $script:Ui.UpdateBanner.Visibility = 'Visible'
        $script:Ui.BtnUpdDownload.IsEnabled = [bool]$rel.AssetUrl
        Write-CfgLog "Versión nueva de Eureka_Utils disponible: $($rel.Version) ($($rel.Url))."
    }
    elseif ($job.Manual) { Show-CfgMessage ((T 'Tienes la última versión de Eureka_Utils ({0}).') -f (Get-CfgVersion)) | Out-Null }
}

# ------------------------------------------------------------------ idioma

function Set-CfgLanguage {
    param([Parameter(Mandatory)][string]$Code, [switch]$NoSave)
    if (-not @($script:Languages | Where-Object { $_.Code -eq $Code }).Count) { $Code = 'es' }
    $script:I18n.Lang = $Code
    $lang = $script:Languages | Where-Object { $_.Code -eq $Code } | Select-Object -First 1
    try { $script:Ui.Window.Language = [System.Windows.Markup.XmlLanguage]::GetLanguage($lang.Culture) } catch { }
    Update-CfgI18nTree
    Set-CfgTheme $script:G.Theme
    Update-CfgProfileNames
    Update-CfgProfileDesc
    Update-CfgCategoryList
    foreach ($r in $script:SwTable.Rows) { $r['CategoryText'] = T $r['Category'] }
    foreach ($r in $script:BwTable.Rows) { $r['RiskText'] = T $r['Risk']; if ($r['StatusEs']) { $r['Status'] = T $r['StatusEs'] } }
    Update-CfgTweakTexts
    if ($script:G.LastDetect) { Set-CfgDetectionResult $script:G.LastDetect }
    else { foreach ($r in $script:SwTable.Rows) { $r['Status'] = T 'Detectando...' } }
    Update-CfgUpdateSummary
    Update-CfgSwImpact; Update-CfgBwSummary; Update-CfgTwSummary
    if ($script:G.DetailId) { Show-CfgSwDetail $script:G.DetailId }
    Initialize-CfgDiagTab
    if (-not $NoSave -and -not $script:G.CapturePath) { Save-CfgPrefs ([pscustomobject]@{ Theme = $script:G.Theme; Language = $Code }) }
}

# ------------------------------------------------------------------ capturas (documentación y pruebas)

function Save-CfgCaptures {
    $w = $script:Ui.Window
    $dir = $script:G.CapturePath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $save = {
        param($name)
        $w.UpdateLayout()
        $w.Dispatcher.Invoke([action] {}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
        $w.UpdateLayout()
        $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap ([int]$w.ActualWidth), ([int]$w.ActualHeight), 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
        $bmp.Render($w)
        $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
        $fs = [IO.File]::Create((Join-Path $dir "$name.png"))
        $enc.Save($fs); $fs.Close()
    }
    # Anonimiza nombre de equipo y usuario en las capturas para la documentación
    $anon = { param($t) ([string]$t).Replace($env:COMPUTERNAME, 'PC-EJEMPLO').Replace($env:USERNAME, 'usuario') }
    $script:Ui.HeaderSubtitle.Text = & $anon $script:Ui.HeaderSubtitle.Text
    $serialKey = T 'Número de serie'
    $script:Ui.SysInfoList.ItemsSource = @($script:Ui.SysInfoList.ItemsSource | ForEach-Object { [pscustomobject]@{ Key = $_.Key; Value = $(if ($_.Key -eq $serialKey -and $_.Value -ne '—') { 'XXXXXXXX' } else { & $anon $_.Value }) } })
    $script:Ui.AccLocalGrid.ItemsSource = @($script:Ui.AccLocalGrid.ItemsSource | ForEach-Object {
            [pscustomobject]@{ Name = (& $anon $_.Name); FullName = $(if ($_.FullName) { 'Usuario de ejemplo' } else { '' }); EnabledText = $_.EnabledText; AdminText = $_.AdminText; LastLogon = $_.LastLogon }
        })
    $script:Ui.LogBox.Text = & $anon $script:Ui.LogBox.Text
    $script:Ui.LogPath.Text = '...\Eureka_Utils\Logs\Eureka_Utils_PC-EJEMPLO.log'
    $names = @('01-equipo', '02-hardware', '03-software', '04-actualizaciones', '05-bloatware', '06-ajustes', '07-cuentas-dominio', '08-instalar-windows', '09-drivers-bios', '10-diagnostico', '11-registro')
    # Ejemplo ilustrativo para la pestaña USB
    $u = $script:Ui
    if (-not $script:G.Iso) {
        $u.UsbIso.Text = 'D:\ISO\Win11_Spanish_x64.iso'
        $u.UsbEdition.ItemsSource = @([pscustomobject]@{ Index = 1; Name = 'Windows 11 Home' }, [pscustomobject]@{ Index = 2; Name = 'Windows 11 Pro' }, [pscustomobject]@{ Index = 3; Name = 'Windows 11 Education' })
        $u.UsbEdition.SelectedIndex = 1
        $u.UsbIsoInfo.Text = '(Ejemplo) Windows 11 · compilación 26200 · amd64 · es-ES · install.wim 5.412 MB (se dividirá para FAT32).'
        $u.UsbComputerName.Text = 'PC-OFICINA-01'; $u.UsbUser.Text = 'admin.local'; $u.UsbFullName.Text = 'Administrador local'
        $u.UsbDisk.ItemsSource = @([pscustomobject]@{ Label = 'Disco 2: SanDisk Ultra USB 3.0 · 28,7 GB' }); $u.UsbDisk.SelectedIndex = 0
        for ($k = 0; $k -lt $script:G.Profiles.Count; $k++) { if ($script:G.Profiles[$k].name -like 'Oficina (*') { $u.UsbProfile.SelectedIndex = $k } }
    }
    for ($k = 0; $k -lt $script:G.Profiles.Count; $k++) { if ($script:G.Profiles[$k].name -eq 'Gaming + Streaming') { $u.ProfileCombo.SelectedIndex = $k } }
    $u.DomChecks.ItemsSource = $null
    # Pestaña Drivers y BIOS con datos reales (solo lectura)
    try {
        $fwi = Get-CfgFirmwareInfo
        Set-CfgFirmwareView @{ Fw = $fwi; Checks = @(Test-CfgGamingReadiness -Fw $fwi); Guide = @(Get-CfgFirmwareGuide -Fw $fwi -AsParts) }
        $script:G.Devices = @(Get-CfgDevices); Update-CfgDeviceView
    }
    catch { Write-CfgLog "Captura de Drivers y BIOS: $($_.Exception.Message)" WARN }
    for ($i = 0; $i -lt $names.Count; $i++) {
        $u.Tabs.SelectedIndex = $i
        if ($i -eq 3) { Show-CfgInstallFailures -Kind 'update' -NoDialog -Failures @([pscustomobject]@{ Name = '7-Zip (ejemplo)'; Version = '24.08'; Available = '26.06'; Reason = 'La aplicación sigue con una actualización pendiente después de ejecutar el instalador.'; Link = 'https://www.7-zip.org/' }) }
        if ($i -eq 2) { Set-CfgProfileSelection; $u.Tabs.SelectedIndex = 2; $obs = 0; foreach ($rv in $script:SwTable.DefaultView) { if ($rv.Row['Id'] -eq 'obs') { break }; $obs++ }; $u.SwGrid.SelectedIndex = $obs; $u.SwGrid.ScrollIntoView($u.SwGrid.SelectedItem) }
        & $save "light-$($names[$i])"
    }
    Set-CfgTheme 'Dark'
    foreach ($i in 0, 1, 2, 7, 8, 9) { $u.Tabs.SelectedIndex = $i; & $save "dark-$($names[$i])" }
    Set-CfgTheme 'Light'
    foreach ($x in @(@('eu', 0, 'idioma-euskera-equipo'), @('ca', 2, 'idioma-catala-software'), @('ca-valencia', 3, 'idioma-valencia-actualitzacions'), @('gl', 9, 'idioma-galego-diagnostico'), @('en', 1, 'idioma-english-hardware'))) {
        Set-CfgLanguage $x[0] -NoSave
        $u.LangCombo.SelectedItem = ($script:Languages | Where-Object { $_.Code -eq $x[0] } | Select-Object -First 1)
        $u.Tabs.SelectedIndex = $x[1]
        & $save $x[2]
    }
    $w.Close()
}

# ------------------------------------------------------------------ ventana principal

function Show-CfgGui {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$LogFile, [string]$InitialProfile, [string]$CapturePath, [switch]$PostInstall, [string]$Tab, [string[]]$FolderRisk)

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Data
    try {
        Add-Type -Namespace CfgNative -Name Dwm -ErrorAction Stop -MemberDefinition '[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(System.IntPtr hwnd, int attr, ref int value, int size);'
    }
    catch { }

    $script:G = @{
        Root        = $Root
        LogFile     = $LogFile
        Queue       = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
        Modules     = @($CfgModuleNames | ForEach-Object { Join-Path $Root "Modules\$_.psm1" } | Where-Object { Test-Path $_ })
        Job         = $null
        SwCatalog   = @(Get-CfgSoftwareCatalog)
        SwById      = @{}
        SwState     = @{}
        BwCatalog   = @(Get-CfgBloatwareCatalog)
        TwCatalog   = @(Get-CfgTweaks)
        Profiles    = @(Get-CfgProfiles)
        Sys         = $null
        Hw          = $null
        Iso         = $null
        Theme       = 'System'
        CapturePath = $CapturePath
        PostInstall = $null
        FolderRisk  = @($FolderRisk | Where-Object { $_ })
    }
    foreach ($i in $script:G.SwCatalog) { $script:G.SwById[$i.id] = $i }
    if ($PostInstall) { $script:G.PostInstall = Get-CfgPostInstall }
    Set-CfgEnvironment -Root $Root -LogFile $LogFile -LogQueue $script:G.Queue | Out-Null

    $xamlText = Get-Content (Join-Path $Root 'UI\MainWindow.xaml') -Raw -Encoding UTF8
    $window = [Windows.Markup.XamlReader]::Parse($xamlText)
    $ui = @{ Window = $window }
    foreach ($m in [regex]::Matches($xamlText, 'x:Name="([^"]+)"')) { $ui[$m.Groups[1].Value] = $window.FindName($m.Groups[1].Value) }
    $script:Ui = $ui
    $window.Title = "Eureka_Utils $(Get-CfgVersion)"
    $iconPath = Join-Path $Root 'UI\eureka_utils.ico'
    if (Test-Path $iconPath) { try { $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object Uri $iconPath)) } catch { } }
    if ($CapturePath) { $window.WindowStartupLocation = 'Manual'; $window.Left = -5000; $window.Top = 0; $window.ShowInTaskbar = $false }

    # Idioma: se registran los textos originales del XAML antes de que el código los cambie
    Import-CfgTranslations -Root $Root
    $prefs = Get-CfgPrefs
    $lang = Get-CfgDefaultLanguage
    if ($prefs.PSObject.Properties['Language'] -and $prefs.Language) { $lang = $prefs.Language }
    if ($CapturePath) { $lang = 'es' }
    $script:I18n.Lang = $lang
    Register-CfgI18nTree $window
    Update-CfgI18nTree

    $theme = 'System'
    if ($prefs.PSObject.Properties['Theme'] -and $prefs.Theme -in @('System', 'Light', 'Dark')) { $theme = $prefs.Theme }
    if ($CapturePath) { $theme = 'Light' }
    Set-CfgTheme $theme

    $ui.LogPath.Text = $LogFile
    Initialize-CfgSoftwareTab
    Initialize-CfgUpdatesTab
    Initialize-CfgBloatwareTab
    Initialize-CfgTweaksTab
    Initialize-CfgUsbTab
    Update-CfgProfileNames
    $idx = 0
    if ($InitialProfile) { for ($k = 0; $k -lt $script:G.Profiles.Count; $k++) { if ($script:G.Profiles[$k].name -eq $InitialProfile) { $idx = $k } } }
    $ui.ProfileCombo.SelectedIndex = $idx
    Update-CfgProfileDesc

    # ---------------- Cabecera
    $ui.BtnTheme.Add_Click({ Switch-CfgTheme })
    $ui.LangCombo.ItemsSource = $script:Languages
    $ui.LangCombo.SelectedItem = ($script:Languages | Where-Object { $_.Code -eq $script:I18n.Lang } | Select-Object -First 1)
    $ui.LangCombo.Add_SelectionChanged({
            $l = $script:Ui.LangCombo.SelectedItem
            if ($l -and $l.Code -ne $script:I18n.Lang) { Set-CfgLanguage $l.Code }
        })

    # ---------------- Equipo
    $ui.ProfileCombo.Add_SelectionChanged({ Update-CfgProfileDesc })
    $ui.BtnRefresh.Add_Click({ Start-CfgDetection })
    $ui.BtnRestorePoint.Add_Click({ Start-CfgTask -Title 'Punto de restauración' -Script { New-CfgRestorePoint | Out-Null } })
    $ui.BtnOpenExports.Add_Click({ Start-Process (Get-CfgSystemExe "explorer.exe") (Get-CfgExportFolder) })
    $ui.BtnReport.Add_Click({
            Start-CfgTask -Title 'Informe del equipo' -Script { New-CfgComputerReport -IncludeUpdates } -OnComplete {
                param($out) $r = @($out | Where-Object { $_.Id -eq 'report' }) | Select-Object -First 1; if ($r -and $r.Success) { Start-Process $r.Message }
            }
        })
    $ui.BtnMarkProfile.Add_Click({ Set-CfgProfileSelection })
    $ui.BtnApplyProfile.Add_Click({
            $p = $script:Ui.ProfileCombo.SelectedItem
            if (-not $p) { return }
            if (-not (Confirm-CfgAction "¿Aplicar el perfil '$($p.name)' a este equipo?`n`n$($script:Ui.ProfileDesc.Text)")) { return }
            Start-CfgTask -Title "Perfil $($p.name)" -Arguments @($p.name) -Script { param($n) Invoke-CfgProfile -Name $n } -OnComplete { Start-CfgDetection -Then { Start-CfgUpdateScan } }
        })

    # ---------------- Hardware
    $ui.BtnHwMarkRec.Add_Click({
            $ids = @($script:G.Rec | Where-Object { $_.SoftwareId } | ForEach-Object { $_.SoftwareId } | Select-Object -Unique)
            if (-not $ids.Count) { Show-CfgMessage 'No hay software recomendado para este hardware.' | Out-Null; return }
            Set-CfgSoftwareSelection -Ids $ids -Add
            $script:Ui.Tabs.SelectedIndex = 2
        })
    $ui.BtnBattery.Add_Click({
            Start-CfgTask -Title 'Informe de batería' -Script { New-CfgBatteryReport } -OnComplete { param($out) if ($out -and $out[0].Success) { Start-Process $out[0].Message } }
        })
    $ui.BtnDevMgr.Add_Click({ Start-CfgConsole -Id "devmgmt.msc" })
    $ui.BtnOptionalUpdates.Add_Click({ Start-Process 'ms-settings:windowsupdate-optionalupdates' })

    # ---------------- Software
    $ui.SwSearch.Add_TextChanged({ Update-CfgSwFilter })
    $ui.SwCategory.Add_SelectionChanged({ Update-CfgSwFilter })
    $ui.SwOnlyMissing.Add_Click({ Update-CfgSwFilter })
    $ui.BtnSwDetect.Add_Click({ Start-CfgDetection })
    $ui.SwGrid.Add_SelectionChanged({
            $row = $script:Ui.SwGrid.SelectedItem
            if ($row -is [System.Data.DataRowView]) { Show-CfgSwDetail ([string]$row.Row['Id']) }
        })
    $ui.BtnSwClear.Add_Click({ foreach ($r in $script:SwTable.Rows) { if ($r['Selected']) { $r['Selected'] = $false } } })
    $ui.BtnSwInstall.Add_Click({
            [void]$script:Ui.SwGrid.CommitEdit()
            $ids = Get-CfgSelectedIds $script:SwTable
            if (-not $ids.Count) { Show-CfgMessage 'Marca al menos una aplicación.' | Out-Null; return }
            if (-not (Confirm-CfgAction "Se va a instalar lo siguiente:`n`n$($script:Ui.SwImpactSummary.Text)`n`n¿Continuar?")) { return }
            Start-CfgTask -Title (T 'Instalación de software') -Arguments (, $ids) -Script { param($Ids) Install-CfgSoftwareSet -Ids $Ids } -OnComplete {
                param($out)
                $fails = @($out | Where-Object { $_ -and $_.PSObject.Properties['Success'] -and -not $_.Success -and $_.PSObject.Properties['Link'] -and $_.Link } | ForEach-Object {
                        [pscustomobject]@{ Name = $_.Name; Id = $_.Id; Version = ''; Available = ''; Reason = $_.Message; Link = $_.Link }
                    })
                Show-CfgInstallFailures -Failures $fails -Kind 'install'
                Start-CfgDetection
            }
        })
    $ui.BtnSwUninstall.Add_Click({
            [void]$script:Ui.SwGrid.CommitEdit()
            $ids = @(Get-CfgSelectedIds $script:SwTable | Where-Object { $script:G.SwState[$_] })
            if (-not $ids.Count) { Show-CfgMessage 'Marca al menos una aplicación que esté instalada.' | Out-Null; return }
            $names = ($ids | ForEach-Object { $script:G.SwById[$_].name }) -join "`n• "
            if (-not (Confirm-CfgAction "¿Desinstalar?`n`n• $names")) { return }
            Start-CfgTask -Title 'Desinstalación de software' -Arguments (, $ids) -Script { param($Ids) Uninstall-CfgSoftwareSet -Ids $Ids } -OnComplete { Start-CfgDetection }
        })

    # ---------------- Actualizaciones
    $ui.BtnUpScan.Add_Click({ Start-CfgUpdateScan })
    $ui.BtnUpSources.Add_Click({ Start-CfgTask -Title 'Orígenes de winget' -Script { Update-CfgWingetSources } })
    $ui.BtnWinUpdate.Add_Click({ Start-Process 'ms-settings:windowsupdate' })
    $ui.BtnStoreUpdates.Add_Click({ Start-Process 'ms-windows-store://downloadsandupdates' })
    $ui.BtnUpSelected.Add_Click({
            [void]$script:Ui.UpGrid.CommitEdit()
            $ids = Get-CfgSelectedIds $script:UpTable
            if (-not $ids.Count) { Show-CfgMessage 'Marca al menos una actualización.' | Out-Null; return }
            Start-CfgTask -Title (T 'Actualizando aplicaciones') -Arguments @($ids, [bool]$script:Ui.UpUnknown.IsChecked) -Script { param($Ids, $U) Invoke-CfgVerifiedUpdate -Ids $Ids -IncludeUnknown:$U } -OnComplete {
                param($out) Show-CfgInstallFailures -Failures @($out | Where-Object { $_ -and $_.PSObject.Properties['UpdateFailure'] }) -Kind 'update'; Start-CfgUpdateScan
            }
        })
    $ui.BtnUpAll.Add_Click({
            if (-not (Confirm-CfgAction 'Se actualizarán todas las aplicaciones que gestiona winget (puede cerrar programas abiertos). ¿Continuar?')) { return }
            Start-CfgTask -Title (T 'Actualizando todo') -Arguments @([bool]$script:Ui.UpUnknown.IsChecked) -Script { param($U) Invoke-CfgVerifiedUpdate -All -IncludeUnknown:$U } -OnComplete {
                param($out) Show-CfgInstallFailures -Failures @($out | Where-Object { $_ -and $_.PSObject.Properties['UpdateFailure'] }) -Kind 'update'; Start-CfgUpdateScan
            }
        })
    $ui.UpFailGrid.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler] {
            param($s, $e)
            $b = $e.OriginalSource
            if ($b -is [System.Windows.Controls.Button] -and $b.Tag) { Write-CfgLog "Abriendo descarga manual: $($b.Tag)"; Start-Process ([string]$b.Tag) }
        })

    # ---------------- Bloatware
    $ui.BtnBwDetect.Add_Click({ Start-CfgDetection })
    $ui.BwOnlyPresent.Add_Click({ Update-CfgBwFilter })
    $ui.BtnBwRecommended.Add_Click({ foreach ($r in $script:BwTable.Rows) { $r['Selected'] = ($r['Recommended'] -and $r['Present']) } })
    $ui.BtnBwRemove.Add_Click({
            [void]$script:Ui.BwGrid.CommitEdit()
            $ids = @($script:BwTable.Rows | Where-Object { $_['Selected'] -and $_['Present'] } | ForEach-Object { [string]$_['Id'] })
            if (-not $ids.Count) { Show-CfgMessage 'Marca al menos un elemento presente.' | Out-Null; return }
            if (-not (Confirm-CfgAction "¿Quitar $($ids.Count) aplicaciones del equipo para todos los usuarios?`n`n$($script:Ui.BwSummary.Text)")) { return }
            Start-CfgTask -Title 'Eliminación de bloatware' -Arguments @($ids, [bool]$script:Ui.BwProvisioned.IsChecked, [bool]$script:Ui.BwRestorePoint.IsChecked) -Script {
                param($Ids, $Prov, $Rp)
                if ($Rp) { New-CfgRestorePoint -Description 'Eureka_Utils - antes de quitar bloatware' | Out-Null }
                Remove-CfgBloatware -Ids $Ids -IncludeProvisioned:$Prov
            } -OnComplete { Start-CfgDetection }
        })
    $ui.BtnBwRestore.Add_Click({
            [void]$script:Ui.BwGrid.CommitEdit()
            $ids = @($script:BwTable.Rows | Where-Object { $_['Selected'] -and -not ($_['Status'] -like 'Presente*') } | ForEach-Object { [string]$_['Id'] })
            if (-not $ids.Count) { Show-CfgMessage "Marca elementos que NO estén presentes (desmarca 'Solo los presentes en el equipo' para verlos)." | Out-Null; return }
            Start-CfgTask -Title 'Reinstalación de apps' -Arguments (, $ids) -Script { param($Ids) Restore-CfgBloatware -Ids $Ids } -OnComplete { Start-CfgDetection }
        })

    # ---------------- Ajustes
    $ui.BtnTwApply.Add_Click({
            [void]$script:Ui.TwGrid.CommitEdit()
            $ids = Get-CfgSelectedIds $script:TwTable
            if (-not $ids.Count) { Show-CfgMessage 'Marca al menos un ajuste.' | Out-Null; return }
            Start-CfgTask -Title 'Aplicando ajustes' -Arguments (, $ids) -Script { param($Ids) Invoke-CfgTweaks -Ids $Ids } -OnComplete { Start-CfgDetection }
        })

    # ---------------- Cuentas
    $ui.BtnAccCheck.Add_Click({
            $upn = $script:Ui.AccUpn.Text.Trim()
            if (-not (Test-CfgUpn $upn)) { Show-CfgMessage 'Escribe la cuenta profesional como usuario@empresa.com.' 'Warning' | Out-Null; return }
            Start-CfgTask -Title "Comprobando $upn" -Arguments @($upn) -Script { param($U) Test-CfgWorkAccount -Upn $U } -OnComplete { param($out) $script:Ui.AccChecks.ItemsSource = @($out | ForEach-Object { $_ }) }
        })
    $ui.BtnAccJoinEntra.Add_Click({ Invoke-CfgAccountFlow 'aadj' })
    $ui.BtnAccIntune.Add_Click({ Invoke-CfgAccountFlow 'mdm' })
    $ui.BtnAccAddWork.Add_Click({ Invoke-CfgAccountFlow 'awa' })
    $ui.BtnAccMfa.Add_Click({ Open-CfgMfaRegistration })
    $ui.BtnAccHello.Add_Click({ Start-Process 'ms-settings:signinoptions' })
    $ui.BtnAccUsersRefresh.Add_Click({ Start-CfgTask -Title 'Cuentas locales' -Script { Get-CfgLocalUsers } -OnComplete { param($out) Set-CfgUserList @($out | ForEach-Object { $_ }) } })
    $ui.BtnAccCreate.Add_Click({
            $user = $script:Ui.AccNewUser.Text.Trim()
            if (-not $user) { Show-CfgMessage 'Escribe el nombre del nuevo usuario.' 'Warning' | Out-Null; return }
            $cred = Get-Credential -UserName $user -Message "Contraseña para la nueva cuenta local '$user'"
            if (-not $cred) { return }
            Start-CfgTask -Title "Creando $user" -Arguments @($user, $script:Ui.AccNewFull.Text.Trim(), $cred.Password, [bool]$script:Ui.AccNewAdmin.IsChecked, [bool]$script:Ui.AccMustChange.IsChecked) -Script {
                param($N, $F, $P, $A, $M) New-CfgLocalUser -UserName $N -FullName $F -Password $P -Administrator:$A -MustChangePassword:$M; Get-CfgLocalUsers
            } -OnComplete { param($out) Set-CfgUserList @($out | Where-Object { $_.PSObject.Properties['LastLogon'] }) }
        })
    $ui.BtnAccAddAdmin.Add_Click({
            $m = $script:Ui.AccAdminMember.Text.Trim()
            if (-not $m) { Show-CfgMessage 'Indica la cuenta: usuario, DOMINIO\usuario o AzureAD\usuario@empresa.com.' 'Warning' | Out-Null; return }
            if (-not (Confirm-CfgAction "¿Dar permisos de administrador local a '$m'?")) { return }
            Start-CfgTask -Title "Administrador: $m" -Arguments @($m) -Script { param($M) Add-CfgLocalAdmin -Member $M; Get-CfgLocalUsers } -OnComplete { param($out) Set-CfgUserList @($out | Where-Object { $_.PSObject.Properties['LastLogon'] }) }
        })

    # ---------------- Dominio
    $ui.BtnDomCheck.Add_Click({
            $d = $script:Ui.DomName.Text.Trim()
            if (-not $d) { Show-CfgMessage 'Indica el dominio (FQDN), por ejemplo corp.contoso.local.' | Out-Null; return }
            Start-CfgTask -Title "Requisitos para $d" -Arguments @($d) -Script { param($D) Test-CfgDomainPrerequisites -Domain $D } -OnComplete { param($out) $script:Ui.DomChecks.ItemsSource = @($out | ForEach-Object { $_ }) }
        })
    $ui.BtnDomJoin.Add_Click({
            $d = $script:Ui.DomName.Text.Trim(); $ou = $script:Ui.DomOU.Text.Trim(); $nn = $script:Ui.DomNewName.Text.Trim()
            if (-not $d) { Show-CfgMessage 'Indica el dominio (FQDN).' | Out-Null; return }
            if ($nn -and -not (Test-CfgComputerName $nn)) { Show-CfgMessage 'El nuevo nombre no es válido (máx. 15 caracteres: letras, números y guiones).' 'Warning' | Out-Null; return }
            $cred = Get-Credential -Message "Cuenta con permiso para unir equipos a $d (DOMINIO\usuario)" -UserName "$($d.Split('.')[0].ToUpper())\"
            if (-not $cred) { return }
            Start-CfgTask -Title "Unión a $d" -Arguments @($d, $cred, $ou, $nn, [bool]$script:Ui.DomRestart.IsChecked) -Script {
                param($D, $C, $OU, $NN, $R) Join-CfgDomain -Domain $D -Credential $C -OUPath $OU -NewName $NN -Restart:$R
            } -OnComplete { Start-CfgDetection }
        })
    $ui.BtnRename.Add_Click({
            $nn = $script:Ui.DomNewName.Text.Trim()
            if (-not (Test-CfgComputerName $nn)) { Show-CfgMessage 'Escribe un nombre válido en "Nuevo nombre" (máx. 15 caracteres).' 'Warning' | Out-Null; return }
            $cred = $null
            if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain) {
                $cred = Get-Credential -Message 'El equipo está en dominio: cuenta con permiso para renombrarlo en AD'
                if (-not $cred) { return }
            }
            Start-CfgTask -Title "Renombrar a $nn" -Arguments @($nn, $cred, [bool]$script:Ui.DomRestart.IsChecked) -Script {
                param($N, $C, $R) if ($C) { Rename-CfgComputer -NewName $N -Credential $C -Restart:$R } else { Rename-CfgComputer -NewName $N -Restart:$R }
            }
        })
    $ui.BtnDomLeave.Add_Click({
            if (-not (Confirm-CfgAction "¿Sacar el equipo del dominio?`n`nAsegúrate de conocer la contraseña de una cuenta de administrador LOCAL: tras reiniciar no podrás iniciar sesión con cuentas del dominio.")) { return }
            $cred = Get-Credential -Message 'Cuenta del dominio con permiso para retirar el equipo'
            if (-not $cred) { return }
            Start-CfgTask -Title 'Salir del dominio' -Arguments @($cred, [bool]$script:Ui.DomRestart.IsChecked) -Script { param($C, $R) Remove-CfgDomainMembership -Credential $C -Restart:$R } -OnComplete { Start-CfgDetection }
        })
    $ui.BtnGpUpdate.Add_Click({ Start-CfgTask -Title 'gpupdate' -Script { Invoke-CfgGpUpdate } })
    $ui.BtnIntuneSync.Add_Click({ Start-CfgTask -Title 'Sincronización Intune' -Script { Invoke-CfgIntuneSync } })
    $ui.BtnHybridJoin.Add_Click({ Start-CfgTask -Title 'Unión híbrida' -Script { Invoke-CfgHybridJoin } })
    $ui.BtnMdmEnroll.Add_Click({ Start-CfgTask -Title 'Inscripción MDM' -Script { Invoke-CfgMdmAutoEnroll } })
    $ui.BtnMdmDiag.Add_Click({ Start-CfgTask -Title 'Diagnóstico MDM' -Script { New-CfgMdmDiagnostics } -OnComplete { Start-Process (Get-CfgSystemExe "explorer.exe") (Get-CfgExportFolder) } })
    $ui.BtnAutopilot.Add_Click({
            Start-CfgTask -Title 'Hash de Autopilot' -Arguments @($script:Ui.ApGroupTag.Text.Trim()) -Script { param($T) Export-CfgAutopilotHash -GroupTag $T } -OnComplete {
                param($out) if ($out -and $out[0].Success) { Start-Process (Get-CfgSystemExe "explorer.exe") "/select,`"$($out[0].Message)`"" }
            }
        })
    $ui.BtnEntraJoin.Add_Click({ Start-Process 'ms-settings:workplace' })
    $ui.BtnCompanyPortal.Add_Click({
            try { Start-Process 'companyportal:' -ErrorAction Stop } catch { Show-CfgMessage 'El Portal de empresa no está instalado. Instálalo desde la pestaña Software.' | Out-Null }
        })

    # ---------------- Instalar Windows (USB)
    $ui.BtnUsbBrowse.Add_Click({
            $dlg = New-Object Microsoft.Win32.OpenFileDialog
            $dlg.Filter = 'Imagen ISO de Windows (*.iso)|*.iso'
            $dlg.Title = 'Selecciona la ISO de Windows 11 o posterior'
            if ($dlg.ShowDialog($script:Ui.Window)) { $script:Ui.UsbIso.Text = $dlg.FileName }
        })
    $ui.BtnUsbDownloadIso.Add_Click({ Start-Process 'https://www.microsoft.com/es-es/software-download/windows11' })
    $ui.BtnUsbRefresh.Add_Click({ Update-CfgUsbDisks })
    $ui.BtnUsbReadIso.Add_Click({
            $iso = $script:Ui.UsbIso.Text.Trim('"', ' ')
            if (-not (Test-Path $iso)) { Show-CfgMessage 'Selecciona un archivo .iso existente.' 'Warning' | Out-Null; return }
            Start-CfgTask -Title 'Leyendo ISO' -Arguments @($iso) -Script { param($P) Get-CfgIsoInfo -IsoPath $P } -OnComplete {
                param($out)
                $info = @($out | Where-Object { $_.PSObject.Properties['Editions'] }) | Select-Object -First 1
                if (-not $info) { return }
                $u = $script:Ui
                if (-not $info.IsWin11) { $script:G.Iso = $null; $u.UsbIsoInfo.Text = "Compilación $($info.Build): no es Windows 11 o posterior. Usa una ISO de Windows 11."; return }
                $script:G.Iso = $info
                $u.UsbEdition.ItemsSource = @($info.Editions)
                $pro = 0; for ($k = 0; $k -lt $info.Editions.Count; $k++) { if ($info.Editions[$k].Name -match 'Pro$') { $pro = $k } }
                $u.UsbEdition.SelectedIndex = $pro
                $split = if ($info.ImageSizeMB -gt 4095) { ' (se dividirá o exportará para FAT32)' } else { '' }
                $u.UsbIsoInfo.Text = "Windows · compilación $($info.Build) · $($info.Arch) · idioma $($info.Language) · $($info.Editions.Count) ediciones · $($info.ImageFile) $($info.ImageSizeMB) MB$split."
                for ($k = 0; $k -lt $u.UsbRegion.Items.Count; $k++) { if ($u.UsbRegion.Items[$k].Id -eq $info.Language) { $u.UsbRegion.SelectedIndex = $k } }
            }
        })
    $ui.UsbRegion.Add_SelectionChanged({
            $r = $script:Ui.UsbRegion.SelectedItem
            if ($r) { for ($k = 0; $k -lt $script:Ui.UsbTimeZone.Items.Count; $k++) { if ($script:Ui.UsbTimeZone.Items[$k].Id -eq $r.TimeZone) { $script:Ui.UsbTimeZone.SelectedIndex = $k; break } } }
        })
    $ui.BtnUsbSaveXml.Add_Click({
            $s = Test-CfgUsbForm
            if (-not $s) { return }
            $dlg = New-Object Microsoft.Win32.SaveFileDialog
            $dlg.FileName = 'autounattend.xml'; $dlg.Filter = 'Archivo de respuesta (*.xml)|*.xml'
            if (-not $dlg.ShowDialog($script:Ui.Window)) { return }
            $script:G.XmlTarget = Split-Path $dlg.FileName
            Start-CfgTask -Title 'Guardando autounattend.xml' -Arguments @($s, $dlg.FileName, (Get-CfgUsbPostInstall)) -Script {
                param($S, $P, $PI)
                Save-CfgAutounattend -Settings $S -Path $P
                $dir = Join-Path (Split-Path $P) 'sources\$OEM$\$1\Eureka_Utils'
                Copy-CfgToolkit -Destination $dir -PostInstall $PI
                Write-CfgLog "Eureka_Utils copiado a $dir (cópialo con la misma ruta a tu USB)." OK
            } -OnComplete { Start-Process (Get-CfgSystemExe "explorer.exe") $script:G.XmlTarget }
        })
    $ui.BtnUsbCreate.Add_Click({
            $s = Test-CfgUsbForm
            if (-not $s) { return }
            $disk = $script:Ui.UsbDisk.SelectedItem
            if (-not $disk -or $null -eq $disk.PSObject.Properties['Number']) { Show-CfgMessage 'Conecta una memoria USB y pulsa Actualizar.' 'Warning' | Out-Null; return }
            $msg = "Se va a BORRAR TODO el contenido de:`n`n    $($disk.Label)`n`ny crear un USB de instalación de $($s.EditionName)."
            if ($s.DiskMode -eq 'wipe0') { $msg += "`n`nATENCIÓN: el USB borrará automáticamente el disco 0 del equipo donde se use." }
            if (-not (Confirm-CfgAction "$msg`n`n¿Continuar?")) { return }
            if (-not (Confirm-CfgAction "Última confirmación: ¿borrar '$($disk.Name)' ($($disk.SizeGB) GB)?")) { return }
            $edIndex = $script:Ui.UsbEdition.SelectedItem.Index
            Start-CfgTask -Title 'Creando USB de instalación' -Arguments @([int]$disk.Number, $script:G.Iso.IsoPath, $s, [int]$edIndex, (Get-CfgUsbPostInstall)) -Script {
                param($N, $Iso, $S, $Ix, $PI) New-CfgInstallUsb -DiskNumber $N -IsoPath $Iso -Settings $S -EditionIndex $Ix -PostInstall $PI
            } -OnComplete { param($out) $r = @($out | Where-Object { $_.Id -eq 'usb' }) | Select-Object -First 1; if ($r -and $r.Success) { Show-CfgMessage "USB de instalación listo en $($r.Message).`n`nArranca el equipo desde él en modo UEFI." | Out-Null }; Update-CfgUsbDisks }
        })

    # ---------------- Diagnóstico y seguridad
    $ui.BtnDiagRun.Add_Click({
            Start-CfgTask -Title (T 'Analizando el sistema') -Script { Get-CfgSystemHealth } -OnComplete { param($out) $script:Ui.DiagChecks.ItemsSource = @(ConvertTo-CfgCheckView $out) }
        })
    $ui.BtnDiagEvents.Add_Click({
            Start-CfgTask -Title (T 'Cargar errores') -Script { Get-CfgRecentErrors } -OnComplete { param($out) $script:Ui.DiagEvents.ItemsSource = @($out | ForEach-Object { $_ }) }
        })
    $repair = @{ BtnSfc = 'sfc'; BtnDismScan = 'dism-scan'; BtnDismRestore = 'dism-restore'; BtnChkdsk = 'chkdsk'; BtnEnergy = 'energy' }
    foreach ($k in $repair.Keys) {
        $ui[$k].Tag = $repair[$k]
        $ui[$k].Add_Click({
                param($s, $e)
                $tool = [string]$s.Tag
                if ($tool -ne 'energy' -and -not (Confirm-CfgAction (T 'Esta herramienta puede tardar entre 10 y 30 minutos y usa mucho disco y CPU. ¿Continuar?'))) { return }
                Start-CfgTask -Title ([string]$s.Content) -Arguments @($tool) -Script { param($T) Invoke-CfgRepairTool -Tool $T } -OnComplete {
                    param($out) $r = @($out | Where-Object { $_.Id -eq 'energy' -and $_.Success }) | Select-Object -First 1; if ($r) { Start-Process $r.Message }
                }
            })
    }
    $ui.BtnMemTest.Add_Click({
            if (Confirm-CfgAction (T 'El diagnóstico de memoria de Windows se ejecuta al reiniciar. Se abrirá para que elijas reiniciar ahora o en el próximo arranque. ¿Continuar?')) { Start-Process "$env:SystemRoot\System32\mdsched.exe" }
        })
    $ui.BtnReliability.Add_Click({ Start-Process (Get-CfgSystemExe "perfmon.exe") -ArgumentList '/rel' })
    $ui.BtnPerfReport.Add_Click({ Start-Process (Get-CfgSystemExe "perfmon.exe") -ArgumentList '/report' })
    $ui.BtnSecRun.Add_Click({
            Start-CfgTask -Title (T 'Comprobar seguridad') -Script { @{ C = @(Get-CfgSecurityStatus); T = @(Get-CfgThreats) } } -OnComplete {
                param($out) $r = $out[0].psobject.BaseObject; $script:Ui.SecChecks.ItemsSource = @(ConvertTo-CfgCheckView $r.C); $script:Ui.SecThreats.ItemsSource = @($r.T)
            }
        })
    $ui.BtnSigUpdate.Add_Click({ Start-CfgTask -Title (T 'Actualizar firmas') -Script { Update-CfgDefenderSignatures } })
    $ui.BtnScanQuick.Add_Click({ Start-CfgTask -Title (T 'Análisis rápido') -Script { Start-CfgDefenderScan -Type Quick } -OnComplete { $script:Ui.BtnSecRun.RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } })
    $ui.BtnScanFull.Add_Click({
            if (-not (Confirm-CfgAction (T 'El análisis completo puede tardar más de una hora. ¿Continuar?'))) { return }
            Start-CfgTask -Title (T 'Análisis completo') -Script { Start-CfgDefenderScan -Type Full }
        })
    $ui.BtnScanFolder.Add_Click({
            Add-Type -AssemblyName System.Windows.Forms
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = T 'Elige la carpeta o unidad (por ejemplo un USB) que quieres analizar'
            if ($dlg.ShowDialog() -ne 'OK') { return }
            Start-CfgTask -Title (T 'Analizar carpeta o unidad...') -Arguments @($dlg.SelectedPath) -Script { param($P) Start-CfgDefenderScan -Type Custom -Path $P }
        })
    $ui.BtnScanOffline.Add_Click({
            if (-not (Confirm-CfgAction (T 'Microsoft Defender sin conexión REINICIARÁ el equipo en unos segundos y analizará el disco durante unos 15 minutos fuera de Windows. Guarda tu trabajo. ¿Continuar?'))) { return }
            Start-CfgTask -Title (T 'Defender sin conexión') -Script { Start-CfgDefenderScan -Type Offline }
        })
    $ui.BtnMsert.Add_Click({ Start-CfgTask -Title 'Microsoft Safety Scanner' -Script { Get-CfgSafetyScanner -Run } })
    Initialize-CfgDiagTab

    # ---------------- Hardware: identificación
    $ui.BtnHwCopyId.Add_Click({
            $id = $script:G.Ident
            if (-not $id) { return }
            $txt = (@($id.Display.Keys | ForEach-Object { '{0}: {1}' -f (T $_), $id.Display[$_] }) + @('{0}: {1}' -f (T 'Equipo'), $env:COMPUTERNAME)) -join "`r`n"
            try { [System.Windows.Clipboard]::SetText($txt); $script:Ui.StatusText.Text = T 'Datos del equipo copiados al portapapeles.' } catch { }
        })
    $ui.BtnHwWarranty.Add_Click({
            $id = $script:G.Ident
            if (-not $id -or -not $id.WarrantyUrl) { return }
            if ($id.Serial) { try { [System.Windows.Clipboard]::SetText($id.Serial) } catch { } }
            Write-CfgLog ("{0} copiado al portapapeles: pégalo en la página de garantía de {1} ({2})." -f $id.SerialLabel, $id.Vendor, $id.WarrantyUrl)
            Start-Process $id.WarrantyUrl
        })

    # ---------------- Hardware: memoria
    $ui.BtnMemRefresh.Add_Click({
            Start-CfgTask -Title (T 'Midiendo el uso de memoria') -Script { Get-CfgMemoryUsage -Catalog (Get-CfgSoftwareCatalog) } -OnComplete { param($out) if ($out) { Set-CfgMemoryView $out[0] } }
        })

    # ---------------- Drivers y BIOS
    Initialize-CfgDriversTab
    $ui.BtnDrvList.Add_Click({
            Start-CfgTask -Title (T 'Listando hardware y controladores') -Script { Get-CfgDevices } -OnComplete { param($out) $script:G.Devices = @($out | Where-Object { $_ }); Update-CfgDeviceView }
        })
    $ui.DrvOnlyProblems.Add_Click({ Update-CfgDeviceView })
    $ui.BtnDrvExport.Add_Click({
            if (-not @($script:G.Devices).Count) { Show-CfgMessage "Primero pulsa 'Listar todo el hardware'." | Out-Null; return }
            $p = Join-Path (Get-CfgExportFolder) ('Hardware_{0}_{1}.csv' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmmss'))
            $script:G.Devices | Select-Object Clase, Dispositivo, Fabricante, Version, Fecha, Firmado, Estado | Export-Csv -Path $p -NoTypeInformation -Encoding UTF8 -Delimiter ';'
            Write-CfgLog "Lista de hardware exportada a $p" OK
            Start-Process (Get-CfgSystemExe 'explorer.exe') "/select,`"$p`""
        })
    $ui.BtnDrvScan.Add_Click({
            Start-CfgTask -Title (T 'Buscando controladores en Windows Update') -Script { Find-CfgDriverUpdates } -OnComplete {
                param($out) Set-CfgDriverUpdates @($out); if (-not $script:DrvUpTable.Rows.Count) { $script:Ui.StatusText.Text = T 'No hay controladores pendientes en Windows Update.' }
            }
        })
    $ui.BtnDrvInstall.Add_Click({
            [void]$script:Ui.DrvUpGrid.CommitEdit()
            $ids = Get-CfgSelectedIds $script:DrvUpTable 'UpdateId'
            if (-not $ids.Count) { Show-CfgMessage "Pulsa 'Buscar en Windows Update' y marca los controladores a instalar." | Out-Null; return }
            $fw = @($script:DrvUpTable.Rows | Where-Object { $_['Selected'] -and $_['Firmware'] }).Count
            $msg = (T '¿Instalar {0} controladores desde Windows Update?') -f $ids.Count
            if ($fw) { $msg += "`n`n" + (T 'Incluye una actualización de BIOS/firmware: conecta el cargador, no apagues el equipo durante el reinicio y, si usas BitLocker, pulsa antes "Preparar actualización de BIOS".') }
            if (-not (Confirm-CfgAction $msg)) { return }
            Start-CfgTask -Title (T 'Instalando controladores') -Arguments (, $ids) -Script { param($Ids) Install-CfgDriverUpdates -UpdateIds $Ids } -OnComplete { $script:Ui.BtnDrvScan.RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
        })
    $ui.BtnDrvFolder.Add_Click({
            Add-Type -AssemblyName System.Windows.Forms
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = T 'Elige la carpeta con los controladores (.inf) descargados del fabricante o de una copia de seguridad'
            if ($dlg.ShowDialog() -ne 'OK') { return }
            if (-not (Get-ChildItem -LiteralPath $dlg.SelectedPath -Filter *.inf -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)) { Show-CfgMessage 'La carpeta no contiene archivos .inf. Si el fabricante te dio un .exe, ejecútalo directamente.' 'Warning' | Out-Null; return }
            Start-CfgTask -Title (T 'Instalando controladores desde carpeta') -Arguments @($dlg.SelectedPath) -Script { param($P) Install-CfgDriverFolder -Path $P }
        })
    $ui.BtnDrvBackup.Add_Click({
            Start-CfgTask -Title (T 'Copia de seguridad de controladores') -Script { Export-CfgDriverBackup } -OnComplete { param($out) $r = @($out | Where-Object { $_.Id -eq 'drvbackup' -and $_.Success }) | Select-Object -First 1; if ($r) { Start-Process (Get-CfgSystemExe 'explorer.exe') $r.Message } }
        })
    $ui.BtnDrvOem.Add_Click({
            $fw = $script:G.Fw
            if (-not $fw) { Show-CfgMessage "Primero pulsa 'Comprobar BIOS y requisitos' para identificar el fabricante." | Out-Null; return }
            $ids = @($script:G.SwCatalog | Where-Object { $_.PSObject.Properties['oemVendor'] -and $_.oemVendor -eq $fw.Vendor } | ForEach-Object { $_.id })
            if ($ids.Count) {
                Set-CfgSoftwareSelection -Ids $ids -Add
                $script:Ui.Tabs.SelectedIndex = 2
                Write-CfgLog ("Herramienta oficial de {0} marcada en Software: {1}. Pulsa 'Instalar selección'." -f $fw.Vendor, (($ids | ForEach-Object { $script:G.SwById[$_].name }) -join ', '))
            }
            elseif ($fw.SupportUrl) { Write-CfgLog "Abriendo la web de controladores de $($fw.Vendor): $($fw.SupportUrl)"; Start-Process $fw.SupportUrl }
            else { Show-CfgMessage 'No se ha identificado el fabricante: busca los controladores en su web con el modelo de la placa base.' | Out-Null }
        })
    $ui.BtnFwCheck.Add_Click({
            Start-CfgTask -Title (T 'Comprobando BIOS y requisitos') -Script { $fw = Get-CfgFirmwareInfo; @{ Fw = $fw; Checks = @(Test-CfgGamingReadiness -Fw $fw); Guide = @(Get-CfgFirmwareGuide -Fw $fw -AsParts) } } -OnComplete { param($out) if ($out) { Set-CfgFirmwareView $out[0].psobject.BaseObject } }
        })
    $ui.BtnFwSupport.Add_Click({
            $fw = $script:G.Fw
            if (-not $fw) { Show-CfgMessage "Primero pulsa 'Comprobar BIOS y requisitos'." | Out-Null; return }
            try { [System.Windows.Clipboard]::SetText("$($fw.Model)") } catch { }
            $url = if ($fw.SupportUrl) { $fw.SupportUrl } else { 'https://www.bing.com/search?q=' + [uri]::EscapeDataString("$($fw.VendorText) $($fw.Model) BIOS") }
            Write-CfgLog ("Modelo '{0}' copiado al portapapeles. BIOS actual: {1} ({2}). Abriendo {3}" -f $fw.Model, $fw.BiosVersion, $fw.BiosDate, $url)
            Start-Process $url
        })
    $ui.BtnFwPrepare.Add_Click({
            if (-not (Confirm-CfgAction 'Se creará un punto de restauración y se suspenderá BitLocker durante el próximo reinicio para que puedas actualizar o cambiar la BIOS sin que pida la clave de recuperación. ¿Continuar?')) { return }
            Start-CfgTask -Title (T 'Preparar actualización de BIOS') -Script { New-CfgRestorePoint -Description 'Eureka_Utils - antes de actualizar la BIOS' | Out-Null; Suspend-CfgBitLockerForFirmware }
        })
    $ui.BtnMbrValidate.Add_Click({ Start-CfgTask -Title (T 'Comprobar conversión MBR → GPT') -Script { Invoke-CfgMbr2Gpt } })
    $ui.BtnMbrConvert.Add_Click({
            if (-not (Confirm-CfgAction "Se va a convertir el disco del sistema de MBR a GPT con la herramienta oficial MBR2GPT (no borra datos).`n`nDESPUÉS es OBLIGATORIO entrar en la BIOS y cambiar a modo UEFI (desactivar CSM/Legacy), o Windows no arrancará.`n`nHaz antes una copia de seguridad de tus datos. ¿Continuar?")) { return }
            if (-not (Confirm-CfgAction 'Última confirmación: ¿convertir ahora el disco del sistema a GPT?')) { return }
            Start-CfgTask -Title (T 'Convertir el disco a GPT') -Script { Suspend-CfgBitLockerForFirmware | Out-Null; Invoke-CfgMbr2Gpt -Convert } -OnComplete { $script:Ui.BtnFwCheck.RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
        })
    $ui.BtnTpmConsole.Add_Click({ Start-CfgConsole -Id 'tpm.msc' })
    $ui.BtnRebootFw.Add_Click({
            $guide = $script:Ui.FwGuide.Text
            if (-not (Confirm-CfgAction ((T "El equipo se reiniciará directamente en la configuración de la BIOS/UEFI en 15 segundos. Guarda tu trabajo.`n`nApunta los pasos:`n{0}`n`n¿Reiniciar ahora?") -f $guide))) { return }
            Restart-CfgToFirmware
        })

    # ---------------- Versión nueva de Eureka_Utils
    $ui.BtnSelfUpdate.Add_Click({ Start-CfgReleaseCheck -Manual })
    $autoPref = Get-CfgPrefs
    $ui.ChkAutoUpdate.IsChecked = -not ($autoPref.PSObject.Properties['CheckUpdates'] -and $autoPref.CheckUpdates -eq $false)
    $ui.ChkAutoUpdate.Add_Click({ if (-not $script:G.CapturePath) { Save-CfgPrefs ([pscustomobject]@{ CheckUpdates = [bool]$script:Ui.ChkAutoUpdate.IsChecked }) } })
    $ui.BtnUpdNotes.Add_Click({ $r = $script:G.Release; if ($r -and $r.Url -match '^https://github\.com/juanraul86/Eureka_Utils/') { Start-Process $r.Url } })
    $ui.BtnUpdSkip.Add_Click({
            $r = $script:G.Release
            if ($r) { Save-CfgPrefs ([pscustomobject]@{ SkipVersion = "$($r.Version)" }) }
            $script:Ui.UpdateBanner.Visibility = 'Collapsed'
        })
    $ui.BtnUpdDownload.Add_Click({
            $r = $script:G.Release
            if (-not $r) { return }
            Start-CfgTask -Title ((T 'Descargando Eureka_Utils {0}') -f $r.Version) -Arguments @($r) -Script { param($R) Save-CfgLatestRelease -Release $R } -OnComplete {
                param($out)
                $res = @($out | Where-Object { $_.Id -eq 'selfupdate' }) | Select-Object -First 1
                if ($res -and $res.Success) {
                    $script:Ui.UpdateBannerText.Text = (T 'Descargada y verificada: {0}. Cierra esta versión y abre la nueva.') -f $res.Message
                    $script:Ui.BtnUpdDownload.IsEnabled = $false
                    Start-Process (Get-CfgSystemExe 'explorer.exe') "/select,`"$($res.Message)`""
                }
                else { Show-CfgMessage 'No se ha podido descargar o verificar la nueva versión. Revisa la pestaña Registro o descárgala desde la página de novedades.' 'Warning' | Out-Null }
            }
        })

    # ---------------- Registro
    $ui.BtnClearData.Add_Click({
            if (-not (Confirm-CfgAction 'Se borrarán los registros anteriores y todo lo exportado (informes HTML, listas de hardware, hash de Autopilot, diagnósticos MDM y copias de controladores). Contienen el nombre del equipo, usuarios y software instalado. No se puede deshacer. ¿Borrar?')) { return }
            Start-CfgTask -Title (T 'Borrar registros e informes') -Script { param($L) Clear-CfgUserData -KeepLog $L | Out-Null } -Arguments @($script:G.LogFile)
        })
    $ui.BtnOpenLogFile.Add_Click({ Start-Process (Get-CfgSystemExe "notepad.exe") $script:G.LogFile })
    $ui.BtnOpenLogs.Add_Click({ Start-Process (Get-CfgSystemExe "explorer.exe") (Split-Path $script:G.LogFile) })

    # ---------------- Temporizador, arranque y cierre
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({ Invoke-CfgTimerTick })
    $timer.Start()

    $window.Add_Closing({
            param($s, $e)
            if ($script:G.Job -and -not $script:G.CapturePath) {
                if (-not (Confirm-CfgAction "Hay una tarea en curso ($($script:G.Job.Title)). Si cierras ahora puede quedar a medias. ¿Cerrar de todos modos?")) { $e.Cancel = $true }
            }
        })
    $window.Add_SourceInitialized({ Set-CfgTheme $script:G.Theme })
    $window.Add_ContentRendered({
            if ($script:G.CapturePath) { Start-CfgDetection -Then { Start-CfgUpdateScan -Then { Save-CfgCaptures } } }
            elseif ($script:G.PostInstall) { Start-CfgDetection -Then { Start-CfgPostInstall } }
            else { Start-CfgDetection -Then { Start-CfgUpdateScan }; if ($script:Ui.ChkAutoUpdate.IsChecked) { Start-CfgReleaseCheck } }
            if (@($script:G.FolderRisk).Count -and -not $script:G.CapturePath) {
                $msg = (T "Por seguridad: la carpeta de Eureka_Utils la pueden modificar usuarios sin permisos de administrador ({0}). Alguien podría cambiar sus scripts para que se ejecuten como administrador.`n`n¿Proteger la carpeta ahora (solo administradores y SYSTEM podrán modificarla)?") -f ($script:G.FolderRisk -join ', ')
                if ((Show-CfgMessage -Text $msg -Icon 'Warning' -Buttons 'YesNo') -eq 'Yes') {
                    if (Protect-CfgFolder -Path $script:G.Root) { $script:G.FolderRisk = @() }
                }
            }
        })
    if ($Tab) {
        $map = @{ Equipo = 0; Hardware = 1; Software = 2; Actualizaciones = 3; Bloatware = 4; Ajustes = 5; Cuentas = 6; USB = 7; Drivers = 8; Diagnostico = 9; Registro = 10 }
        if ($map.ContainsKey($Tab)) { $ui.Tabs.SelectedIndex = $map[$Tab] }
    }

    Write-CfgLog "Eureka_Utils iniciado. Registro: $LogFile"
    [void]$window.ShowDialog()
    $timer.Stop()
}
