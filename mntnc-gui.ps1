# mntnc-gui.ps1 - Windows maintenance with drive selection, checklist, live stats, timing, and collapsible log

# ---- Relaunch elevated if needed ----
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$nl = [Environment]::NewLine

# ---- Symbols ----
$CHECK   = [char]0x2713
$CROSS   = [char]0x2717
$CURRENT = [char]0x25B6
$PENDING = [char]0x25CB
$DOWN    = [char]0x25BC
$UP      = [char]0x25B2

# ---- Scan for local fixed drives ----
$drives = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')
if ($drives.Count -eq 0) {
    [System.Windows.Forms.MessageBox]::Show('No local fixed drives were found.') | Out-Null
    exit
}

# ---- Selection window ----
$script:startChosen = $false
$script:selected    = @()
$script:reboot      = $false

$selForm = New-Object System.Windows.Forms.Form
$selForm.Text            = 'Windows Maintenance - Options'
$selForm.StartPosition   = 'CenterScreen'
$selForm.FormBorderStyle = 'FixedDialog'
$selForm.MaximizeBox     = $false
$selForm.MinimizeBox     = $false
$selForm.Font            = New-Object System.Drawing.Font('Segoe UI', 10)

$hdr = New-Object System.Windows.Forms.Label
$hdr.Text     = 'Select the drives to clean, scan, check, and defragment:'
$hdr.Location = New-Object System.Drawing.Point(15, 15)
$hdr.Size     = New-Object System.Drawing.Size(430, 25)
$selForm.Controls.Add($hdr)

$driveBoxes = @()
for ($i = 0; $i -lt $drives.Count; $i++) {
    $d      = $drives[$i]
    $freeGB = [math]::Round($d.FreeSpace / 1GB, 1)
    $sizeGB = [math]::Round($d.Size / 1GB, 1)

    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text     = $d.DeviceID + '  ' + $d.VolumeName + '  (' + $freeGB + ' GB free of ' + $sizeGB + ' GB)'
    $cb.Location = New-Object System.Drawing.Point(25, (50 + $i * 28))
    $cb.Size     = New-Object System.Drawing.Size(420, 24)
    $cb.Checked  = ($d.DeviceID -eq $env:SystemDrive)
    $cb.Tag      = $d.DeviceID
    $selForm.Controls.Add($cb)
    $driveBoxes += $cb
}

$rebootY = 50 + $drives.Count * 28 + 10

$rebootBox = New-Object System.Windows.Forms.CheckBox
$rebootBox.Text     = 'Reboot the computer when finished'
$rebootBox.Location = New-Object System.Drawing.Point(15, $rebootY)
$rebootBox.Size     = New-Object System.Drawing.Size(420, 24)
$selForm.Controls.Add($rebootBox)
$saveY = $rebootY + 32

$saveBox = New-Object System.Windows.Forms.CheckBox
$saveBox.Text     = 'Save output to file'
$saveBox.Location = New-Object System.Drawing.Point(15, $saveY)
$saveBox.Size     = New-Object System.Drawing.Size(420, 24)
$selForm.Controls.Add($saveBox)

$savePath = New-Object System.Windows.Forms.TextBox
$savePath.Location = New-Object System.Drawing.Point(25, ($saveY + 28))
$savePath.Size     = New-Object System.Drawing.Size(340, 24)
$savePath.ReadOnly = $true
$savePath.Enabled  = $false
$savePath.Text     = Join-Path ([Environment]::GetFolderPath('MyDocuments')) ('mntnc-log-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
$selForm.Controls.Add($savePath)

$saveBrowse = New-Object System.Windows.Forms.Button
$saveBrowse.Text     = '...'
$saveBrowse.Location = New-Object System.Drawing.Point(372, ($saveY + 27))
$saveBrowse.Size     = New-Object System.Drawing.Size(40, 26)
$saveBrowse.Enabled  = $false
$selForm.Controls.Add($saveBrowse)

$saveBox.Add_CheckedChanged({
    $savePath.Enabled  = $saveBox.Checked
    $saveBrowse.Enabled = $saveBox.Checked
})

$saveBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter           = 'Text files (*.txt)|*.txt|All files (*.*)|*.*'
    $dlg.DefaultExt       = 'txt'
    $dlg.FileName         = [System.IO.Path]::GetFileName($savePath.Text)
    $dlg.InitialDirectory = [System.IO.Path]::GetDirectoryName($savePath.Text)
    if ($dlg.ShowDialog($selForm) -eq [System.Windows.Forms.DialogResult]::OK) {
        $savePath.Text = $dlg.FileName
    }
    $dlg.Dispose()
})

$buttonY = $saveY + 62

$startBtn = New-Object System.Windows.Forms.Button
$startBtn.Text     = 'Start'
$startBtn.Location = New-Object System.Drawing.Point(230, $buttonY)
$startBtn.Size     = New-Object System.Drawing.Size(100, 30)
$selForm.Controls.Add($startBtn)

$cancelBtn = New-Object System.Windows.Forms.Button
$cancelBtn.Text     = 'Cancel'
$cancelBtn.Location = New-Object System.Drawing.Point(340, $buttonY)
$cancelBtn.Size     = New-Object System.Drawing.Size(100, 30)
$selForm.Controls.Add($cancelBtn)

$selForm.ClientSize = New-Object System.Drawing.Size(460, ($buttonY + 50))

$startBtn.Add_Click({
    $script:selected = @($driveBoxes | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    if ($script:selected.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('Select at least one drive.') | Out-Null
        return
    }
    if ($saveBox.Checked -and [string]::IsNullOrWhiteSpace($savePath.Text)) {
        [System.Windows.Forms.MessageBox]::Show('Choose a file to save the output to.') | Out-Null
        return
    }
    $script:reboot      = $rebootBox.Checked
    $script:logPath     = if ($saveBox.Checked) { $savePath.Text } else { $null }
    $script:startChosen = $true
    $selForm.Close()
})
$cancelBtn.Add_Click({ $selForm.Close() })

[void]$selForm.ShowDialog()
if (-not $script:startChosen) { exit }

$script:logWriter = $null
if ($script:logPath) {
    try {
        $script:logWriter = New-Object System.IO.StreamWriter($script:logPath, $false, (New-Object System.Text.UTF8Encoding($false)))
        $script:logWriter.AutoFlush = $true
        $script:logWriter.WriteLine('Windows Maintenance log - started ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    } catch {
        [System.Windows.Forms.MessageBox]::Show('Could not open the log file:' + $nl + $_.Exception.Message) | Out-Null
        exit
    }
}

# ---- Build steps ----
# Group: consecutive steps with the same Group form one block; the block finishes before the next one starts.
# Lane:  inside a block, steps in the same Lane run one after another; different lanes run at the same time.
#        Steps with no Lane get their own lane, so they all run at once.
$steps = @()
$steps += @{ Name = 'Update Windows'; Group = 'updates'; Code = 'if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) { Install-PackageProvider -Name NuGet -Force | Out-Null; Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers }; Import-Module PSWindowsUpdate; Install-WindowsUpdate -AcceptAll -IgnoreReboot' }
$steps += @{ Name = 'Update apps (winget)'; Group = 'updates'; Code = 'winget upgrade --all --disable-interactivity --include-unknown' }
$steps += @{ Name = 'Check Windows image (DISM)'; Code = 'DISM.exe /Online /Cleanup-Image /RestoreHealth' }

$mpExe = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'

foreach ($id in $script:selected) {
    $letter = $id.TrimEnd(':')
    $root   = $letter + ':\'
    $lane   = 'drive ' + $id

    $steps += @{ Name = ('Clean ' + $id);                     Group = 'drives'; Lane = $lane; Code = ('cleanmgr.exe /autoclean ' + $id) }
    $steps += @{ Name = ('Defender scan ' + $id);             Group = 'drives'; Lane = $lane; Code = ('& "' + $mpExe + '" -Scan -ScanType 3 -File "' + $root + '"') }
    $steps += @{ Name = ('Check disk ' + $id + ' (offline)'); Group = 'drives'; Lane = $lane; Code = ('Repair-Volume -DriveLetter ' + $letter + ' -OfflineScanAndFix') }
    $steps += @{ Name = ('Defragment ' + $id);                Group = 'drives'; Lane = $lane; Code = ('defrag.exe ' + $id + ' /B /V; defrag.exe ' + $id + ' /H /V /X /O /U') }
}

if ($script:reboot) {
    $steps += @{ Name = 'Restart computer'; Code = 'shutdown.exe /r /t 15 /c "Windows maintenance complete"' }
}

$stepDir = Join-Path $env:TEMP 'mntnc'
New-Item -ItemType Directory -Path $stepDir -Force | Out-Null

# ---- Layout ----
$rowHeight  = 28
$topMargin  = 15
$btnY       = $topMargin + $steps.Count * $rowHeight + 10
$baseH      = $btnY + 50
$panelY     = $btnY + 40
$collapsedW = 460
$expandedW  = 720
$expandH    = 230
$statsW     = 190
$gap        = 10

$form = New-Object System.Windows.Forms.Form
$form.Text            = 'Windows Maintenance'
$form.StartPosition   = 'CenterScreen'
$form.FormBorderStyle = 'Sizable'
$form.MaximizeBox     = $true
$form.Font            = New-Object System.Drawing.Font('Segoe UI', 10)
$form.ClientSize      = New-Object System.Drawing.Size($collapsedW, $baseH)
$form.MinimumSize     = New-Object System.Drawing.Size($collapsedW, $baseH)

$symLabels = @()
$txtLabels = @()
for ($i = 0; $i -lt $steps.Count; $i++) {
    $y = $topMargin + $i * $rowHeight

    $sym = New-Object System.Windows.Forms.Label
    $sym.Location  = New-Object System.Drawing.Point(15, $y)
    $sym.Size      = New-Object System.Drawing.Size(25, $rowHeight)
    $sym.Font      = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $sym.TextAlign = 'MiddleCenter'
    $form.Controls.Add($sym)
    $symLabels += $sym

    $txt = New-Object System.Windows.Forms.Label
    $txt.Location  = New-Object System.Drawing.Point(45, $y)
    $txt.Size      = New-Object System.Drawing.Size(400, $rowHeight)
    $txt.TextAlign = 'MiddleLeft'
    $txt.Text      = $steps[$i].Name
    $txt.Anchor    = 'Top,Left,Right'
    $form.Controls.Add($txt)
    $txtLabels += $txt
}

$btn = New-Object System.Windows.Forms.Button
$btn.Location = New-Object System.Drawing.Point(15, $btnY)
$btn.Size     = New-Object System.Drawing.Size(180, 30)
$btn.Text     = "Show details $DOWN"
$btn.Anchor   = 'Top,Left'
$form.Controls.Add($btn)

# Details panel: stats on the left, log on the right. Hidden until expanded.
$detailsPanel = New-Object System.Windows.Forms.Panel
$detailsPanel.Location = New-Object System.Drawing.Point(15, $panelY)
$detailsPanel.Size     = New-Object System.Drawing.Size(($expandedW - 30), 210)
$detailsPanel.Anchor   = 'Top,Left,Right,Bottom'
$detailsPanel.Visible  = $false
$form.Controls.Add($detailsPanel)

# Stats is a read-only TextBox with wrapping off, so lines never wrap
$statsBox = New-Object System.Windows.Forms.TextBox
$statsBox.Location   = New-Object System.Drawing.Point(0, 0)
$statsBox.Size       = New-Object System.Drawing.Size($statsW, 210)
$statsBox.Multiline  = $true
$statsBox.ReadOnly   = $true
$statsBox.WordWrap   = $false
$statsBox.ScrollBars = 'None'
$statsBox.Font       = New-Object System.Drawing.Font('Consolas', 9)
$statsBox.Anchor     = 'Top,Left,Bottom'
$detailsPanel.Controls.Add($statsBox)

$details = New-Object System.Windows.Forms.TextBox
$details.Location   = New-Object System.Drawing.Point(($statsW + $gap), 0)
$details.Size       = New-Object System.Drawing.Size(($expandedW - 30 - $statsW - $gap), 210)
$details.Multiline  = $true
$details.ReadOnly   = $true
$details.ScrollBars = 'Vertical'
$details.Font       = New-Object System.Drawing.Font('Consolas', 9)
$details.Anchor     = 'Top,Left,Right,Bottom'
$detailsPanel.Controls.Add($details)

# ---- State ----
$script:jobs      = @()      # currently running step processes
$script:status    = @()      # per-step: pending / running / ok / error
$script:blockStart = 0       # first step index of the active block
$script:blockEnd   = 0       # index after the last step of the active block
$script:expanded  = $false
$script:startTime = $null
$script:endTime   = $null

# CPU counter needs a first sample before it returns meaningful values
$script:cpuCounter = New-Object System.Diagnostics.PerformanceCounter('Processor', '% Processor Time', '_Total')
[void]$script:cpuCounter.NextValue()

function Set-Row([int]$i, [string]$state) {
    switch ($state) {
        'pending' { $symLabels[$i].Text = $PENDING; $symLabels[$i].ForeColor = [System.Drawing.Color]::Gray; $txtLabels[$i].ForeColor = [System.Drawing.Color]::Gray }
        'current' { $symLabels[$i].Text = $CURRENT; $symLabels[$i].ForeColor = [System.Drawing.Color]::DodgerBlue; $txtLabels[$i].ForeColor = [System.Drawing.Color]::Black }
        'ok'      { $symLabels[$i].Text = $CHECK; $symLabels[$i].ForeColor = [System.Drawing.Color]::ForestGreen; $txtLabels[$i].ForeColor = [System.Drawing.Color]::Black }
        'error'   { $symLabels[$i].Text = $CROSS; $symLabels[$i].ForeColor = [System.Drawing.Color]::Red; $txtLabels[$i].ForeColor = [System.Drawing.Color]::Red }
    }
}

function Add-Log([string]$text) {
    $details.AppendText($text)
    $details.SelectionStart = $details.TextLength
    $details.ScrollToCaret()
    if ($script:logWriter) { $script:logWriter.Write($text) }
}

# Reads any new text a running step has written to its log file
function Read-JobLog($job) {
    if (-not (Test-Path $job.LogFile)) { return }
    $fs = [System.IO.File]::Open($job.LogFile, 'Open', 'Read', 'ReadWrite')
    try {
        $fs.Position = $job.LogPos
        $sr = New-Object System.IO.StreamReader($fs)
        $text = $sr.ReadToEnd()
        $job.LogPos = $fs.Position
    } finally {
        $fs.Dispose()
    }
    if ($text) { Add-Log $text }
}

# Launches one step as its own process
function Start-StepProcess([int]$i) {
    Set-Row $i 'current'
    Add-Log ($nl + '=== ' + $steps[$i].Name + ' ===' + $nl)

    $stepFile = Join-Path $stepDir ('step' + $i + '.ps1')
    $logFile  = Join-Path $stepDir ('step' + $i + '.log')

    $body = '$ErrorActionPreference = "Continue"' + $nl + $steps[$i].Code + $nl + 'exit $LASTEXITCODE'
    Set-Content -Path $stepFile -Value $body -Encoding UTF8
    Remove-Item $logFile -ErrorAction SilentlyContinue

    $cmdArgs = '/c powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $stepFile + '" > "' + $logFile + '" 2>&1'

    try {
        $p = Start-Process -FilePath 'cmd.exe' -ArgumentList $cmdArgs -WindowStyle Hidden -PassThru
        $script:jobs += [pscustomobject]@{ Index = $i; Proc = $p; LogFile = $logFile; LogPos = 0; Done = $false }
        $script:status[$i] = 'running'
    } catch {
        Set-Row $i 'error'
        $script:status[$i] = 'error'
        Add-Log ('ERROR starting step: ' + $_.Exception.Message + $nl)
    }
}

# Builds the stats text: CPU, RAM, drives, and timing
function Update-Stats {
    $cpu = [math]::Round($script:cpuCounter.NextValue(), 0)

    $os      = Get-CimInstance Win32_OperatingSystem
    $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $usedGB  = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1)
    $ramPct  = [math]::Round(100 * $usedGB / $totalGB, 0)

    $lines = @()
    $lines += 'CPU'
    $lines += '  ' + $cpu + '%'
    $lines += ''
    $lines += 'RAM'
    $lines += '  ' + $usedGB + ' / ' + $totalGB + ' GB (' + $ramPct + '%)'
    $lines += ''
    $lines += 'DRIVES'

    foreach ($id in $script:selected) {
        $d = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='" + $id + "'")
        if ($d) {
            $usedD = [math]::Round(($d.Size - $d.FreeSpace) / 1GB, 1)
            $sizeD = [math]::Round($d.Size / 1GB, 1)
            $pctD  = [math]::Round(100 * $usedD / $sizeD, 0)
            $lines += '  ' + $id + '  ' + $usedD + ' / ' + $sizeD + ' GB (' + $pctD + '%)'
        }
    }

    $lines += ''
    $lines += 'TIMING'

    if ($script:startTime) {
        $startText = $script:startTime.ToString('HH:mm:ss')
        if ($script:endTime) { $finishTime = $script:endTime } else { $finishTime = Get-Date }
        $elapsed   = $finishTime - $script:startTime
        $elapsedText = '{0:00}:{1:00}:{2:00}' -f [int][math]::Floor($elapsed.TotalHours), $elapsed.Minutes, $elapsed.Seconds
        $lines += '  Started  ' + $startText
        $lines += '  Elapsed  ' + $elapsedText
    } else {
        $lines += '  Not started'
    }

    if ($script:endTime) {
        $lines += '  Finished ' + $script:endTime.ToString('HH:mm:ss')
    } elseif ($script:startTime) {
        $lines += '  Finished -'
    }

    $statsBox.Text = ($lines -join $nl)
}

# Returns the index just after the block that starts at $start
function Get-BlockEnd([int]$start) {
    $g = $steps[$start].Group
    $e = $start + 1
    if ($g) {
        while ($e -lt $steps.Count -and $steps[$e].Group -eq $g) { $e++ }
    }
    return $e
}

# Returns the lane key for a step: its Lane, or a unique key if it has none
function Get-LaneKey([int]$i) {
    if ($steps[$i].Lane) { return [string]$steps[$i].Lane }
    return 'step' + $i
}

# Starts whatever can run now. Within the active block, each lane starts its next pending step
# as soon as its previous step has finished. When the block is done, moves to the next block.
function Advance-Schedule {
    while ($script:blockStart -lt $steps.Count) {
        $blockDone = $true
        for ($i = $script:blockStart; $i -lt $script:blockEnd; $i++) {
            if ($script:status[$i] -ne 'ok' -and $script:status[$i] -ne 'error') { $blockDone = $false; break }
        }

        if (-not $blockDone) {
            # Lanes that already have a running step
            $busy = @{}
            for ($i = $script:blockStart; $i -lt $script:blockEnd; $i++) {
                if ($script:status[$i] -eq 'running') { $busy[(Get-LaneKey $i)] = $true }
            }
            # Start the first pending step of each free lane
            for ($i = $script:blockStart; $i -lt $script:blockEnd; $i++) {
                if ($script:status[$i] -eq 'pending') {
                    $lane = Get-LaneKey $i
                    if (-not $busy.ContainsKey($lane)) {
                        Start-StepProcess $i
                        $busy[$lane] = $true
                    }
                }
            }
            return
        }

        # Block finished, move on to the next one
        $script:blockStart = $script:blockEnd
        if ($script:blockStart -lt $steps.Count) { $script:blockEnd = Get-BlockEnd $script:blockStart }
    }
}
# Returns the reasons a restart is still needed (empty array if none)
function Get-RebootReasons {
    $reasons = @()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $reasons += 'Windows Update'
    }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $reasons += 'Windows component servicing'
    }
    if ($script:selected -contains $env:SystemDrive) {
        $dirty = (fsutil dirty query $env:SystemDrive 2>&1) -join ' '
        if ($dirty -match 'is Dirty') { $reasons += 'disk check on ' + $env:SystemDrive + ' scheduled' }
    }
    return ,$reasons
}

# Replaces the step list with a big green check and a status line
function Show-Completion {
    $rowsH = $steps.Count * $rowHeight
    foreach ($l in $symLabels) { $l.Visible = $false }
    foreach ($l in $txtLabels) { $l.Visible = $false }

    $check = New-Object System.Windows.Forms.Label
    $check.Text      = [string]$CHECK
    $check.Font      = New-Object System.Drawing.Font('Segoe UI Symbol', 90, [System.Drawing.FontStyle]::Bold)
    $check.ForeColor = [System.Drawing.Color]::ForestGreen
    $check.TextAlign = 'MiddleCenter'
    $check.Location  = New-Object System.Drawing.Point(15, $topMargin)
    $check.Size      = New-Object System.Drawing.Size(($collapsedW - 30), ($rowsH - 60))
    $check.Anchor    = 'Top,Left,Right'
    $form.Controls.Add($check)

    $msg = New-Object System.Windows.Forms.Label
    $msg.Font      = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $msg.TextAlign = 'MiddleCenter'
    $msg.Location  = New-Object System.Drawing.Point(15, ($topMargin + $rowsH - 60))
    $msg.Size      = New-Object System.Drawing.Size(($collapsedW - 30), 60)
    $msg.Anchor    = 'Top,Left,Right'

    $reasons = @()
    if (-not $script:reboot) { $reasons = @(Get-RebootReasons) }
    if ($reasons.Count -gt 0) {
        $msg.Text      = 'Restart required to finish: ' + ($reasons -join ', ')
        $msg.ForeColor = [System.Drawing.Color]::DarkOrange
    } else {
        $msg.Text      = 'All tasks finished without errors.'
        $msg.ForeColor = [System.Drawing.Color]::ForestGreen
    }
    $form.Controls.Add($msg)
}

# ---- Polling timer: streams output from all running steps, advances, refreshes stats ----
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    if ($script:expanded) { Update-Stats }

    foreach ($job in $script:jobs) {
        Read-JobLog $job
        if ($job.Proc.HasExited) {
            Read-JobLog $job
            if ($job.Proc.ExitCode -eq 0) {
                Set-Row $job.Index 'ok'
                $script:status[$job.Index] = 'ok'
            } else {
                Set-Row $job.Index 'error'
                $script:status[$job.Index] = 'error'
                Add-Log ($nl + 'Step failed (exit code ' + $job.Proc.ExitCode + ')' + $nl)
            }
            $job.Done = $true
        }
    }
    $script:jobs = @($script:jobs | Where-Object { -not $_.Done })

    Advance-Schedule

    $doneCount = @($script:status | Where-Object { $_ -eq 'ok' -or $_ -eq 'error' }).Count
    if ($script:blockStart -ge $steps.Count) {
        $timer.Stop()
        $script:endTime = Get-Date
        $form.Text = 'Windows Maintenance - complete'
        Add-Log ($nl + '=== All steps finished at ' + $script:endTime.ToString('HH:mm:ss') + ' ===' + $nl)
        Update-Stats

        $errorCount = @($script:status | Where-Object { $_ -eq 'error' }).Count
        if ($errorCount -eq 0) { Show-Completion }
    } else {
        $form.Text = 'Windows Maintenance - ' + $doneCount + ' of ' + $steps.Count + ' done'
    }
})

# ---- Toggle details dropdown ----
$btn.Add_Click({
    $script:expanded = -not $script:expanded
    $detailsPanel.Visible = $script:expanded
    if ($script:expanded) {
        $btn.Text = "Hide details $UP"
        Update-Stats
        $form.ClientSize = New-Object System.Drawing.Size($expandedW, ($baseH + $expandH))
    } else {
        $btn.Text = "Show details $DOWN"
        $form.ClientSize = New-Object System.Drawing.Size($collapsedW, $baseH)
    }
})

# ---- Start ----
$script:status     = @('pending') * $steps.Count
$script:blockStart = 0
$script:blockEnd   = Get-BlockEnd 0
for ($i = 0; $i -lt $steps.Count; $i++) { Set-Row $i 'pending' }
$form.Add_Shown({ $timer.Start(); $script:startTime = Get-Date; Advance-Schedule })
[void]$form.ShowDialog()

$timer.Stop()
foreach ($job in $script:jobs) {
    if ($script:logWriter) { $script:logWriter.Dispose() }
}