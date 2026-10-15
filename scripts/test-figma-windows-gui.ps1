param(
    [Parameter(Mandatory=$true)][string]$PackageDirectory,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string]$VideoFixture,
    [switch]$TestOnboarding,
    [switch]$RequireAccessibleHeadings
)
$ErrorActionPreference = 'Stop'
# Microsoft recommends a windowless MTA thread for UI Automation clients.
# GitHub's pwsh shell can be STA; run the entire client in an MTA process.
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne [Threading.ApartmentState]::MTA) {
    $clientArguments = @('-NoProfile', '-MTA', '-File', $PSCommandPath,
        '-PackageDirectory', $PackageDirectory, '-OutputDirectory', $OutputDirectory)
    if ($VideoFixture) { $clientArguments += @('-VideoFixture', $VideoFixture) }
    if ($TestOnboarding) { $clientArguments += '-TestOnboarding' }
    if ($RequireAccessibleHeadings) { $clientArguments += '-RequireAccessibleHeadings' }
    & (Join-Path $PSHOME 'pwsh.exe') @clientArguments
    if ($LASTEXITCODE -ne 0) { throw "MTA native GUI client returned $LASTEXITCODE" }
    return
}
Write-Host "UI Automation client apartment: $([Threading.Thread]::CurrentThread.GetApartmentState())"

New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$exe = @(Get-ChildItem $PackageDirectory -Recurse -Filter vlc.exe -File)
if ($exe.Count -ne 1) { throw "Expected one packaged vlc.exe; found $($exe.Count)" }
$exe = $exe[0]
foreach ($dependency in @('libvlc.dll', 'libvlccore.dll', 'plugins')) {
    if (!(Test-Path (Join-Path $exe.DirectoryName $dependency))) { throw "Missing $dependency" }
}

# Decode a real local WAV without depending on runner audio hardware.
$fixture = Join-Path $OutputDirectory 'audio-fixture.wav'
$pcm = New-Object byte[] (16000 * 2 * 120)
$writer = [IO.BinaryWriter]::new([IO.File]::Create($fixture))
try {
    $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
    $writer.Write([int](36 + $pcm.Length))
    $writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
    $writer.Write([int]16)
    $writer.Write([int16]1)
    $writer.Write([int16]1)
    $writer.Write([int]16000)
    $writer.Write([int]32000)
    $writer.Write([int16]2)
    $writer.Write([int16]16)
    $writer.Write([Text.Encoding]::ASCII.GetBytes('data'))
    $writer.Write([int]$pcm.Length)
    $writer.Write($pcm)
} finally { $writer.Dispose() }

if ($VideoFixture) {
    if (!(Test-Path $VideoFixture)) { throw 'Video fixture is missing' }
    $fixture = (Resolve-Path $VideoFixture).Path
}

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
public struct VlcDisplayMode {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string device;
    public ushort spec, driver, size, extra;
    public uint fields;
    public int x, y;
    public uint orientation, fixedOutput;
    public short color, duplex, resolution, option, collate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string form;
    public ushort pixels;
    public uint bits, width, height, flags, frequency, method, intent, media, dither, reserved1, reserved2, panWidth, panHeight;
}
public static class VlcGuiWindow {
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern bool EnumDisplaySettings(string device, int mode, ref VlcDisplayMode settings);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern int ChangeDisplaySettings(ref VlcDisplayMode settings, uint flags);
    [DllImport("user32.dll")]
    public static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")]
    public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
}
'@
# The hosted runner can start at 1024x768. A 1440x900 offscreen window
# exposes UIA controls that cannot receive a real pointer click.
$display = [VlcDisplayMode]::new()
$display.size = [Runtime.InteropServices.Marshal]::SizeOf($display)
$hasDisplayMode = [VlcGuiWindow]::EnumDisplaySettings($null, -1, [ref]$display)
if ($hasDisplayMode -and ($display.width -lt 1600 -or $display.height -lt 1000)) {
    $display.width = 1920; $display.height = 1080
    $display.fields = 0x180000
    $displayChange = [VlcGuiWindow]::ChangeDisplaySettings([ref]$display, 0)
    if ($displayChange -ne 0) { Write-Host "1920x1080 mode unavailable ($displayChange); fitting the actual desktop" }
}
$desktopWidth = [VlcGuiWindow]::GetSystemMetrics(0)
$desktopHeight = [VlcGuiWindow]::GetSystemMetrics(1)
$wideWidth = [Math]::Min(1440, $desktopWidth - 40)
$wideHeight = [Math]::Min(900, $desktopHeight - 80)
if ($wideWidth -lt 900 -or $wideHeight -lt 620) { throw "Runner desktop too small: ${desktopWidth}x${desktopHeight}" }
Write-Host "Desktop ${desktopWidth}x${desktopHeight}; wide window ${wideWidth}x${wideHeight}"
$qtConfigDir = Join-Path $env:APPDATA 'vlc'
New-Item -ItemType Directory -Force $qtConfigDir | Out-Null
"[MainWindow]`ncolor-scheme-index=2`nnavigation-panel-visible=true`nnavigation-panel-width=200" |
    Set-Content (Join-Path $qtConfigDir 'vlc-qt-interface.ini') -Encoding ASCII
$nextFixture = Join-Path $OutputDirectory ('next-fixture' + [IO.Path]::GetExtension($fixture))
Copy-Item $fixture $nextFixture -Force
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = $listener.LocalEndpoint.Port
$listener.Stop()
$password = [Guid]::NewGuid().ToString('N')
$headers = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(':' + $password))}
$statusUrl = "http://127.0.0.1:$port/requests/status.json"
$config = Join-Path $OutputDirectory 'vlcrc'
$privacyArgument = if ($TestOnboarding) { '--qt-privacy-ask' } else { '--no-qt-privacy-ask' }
$startupWatch = [Diagnostics.Stopwatch]::StartNew()
$arguments = @('--verbose=2', '--restore-playback-pos=0', '--intf=qt', '--no-one-instance', $privacyArgument,
    '--no-qt-video-autoresize', '--no-qt-updates-notif', '--no-qt-error-dialogs', '--no-qt-system-tray', '--no-metadata-network-access', '--aout=dummy', '--clock-master=monotonic', '--loop', '--media-library', '--qt-pin-controls',
    "--config=`"$config`"", "`"$fixture`"", "`"$nextFixture`"")
if (!$TestOnboarding) {
    $arguments += @('--extraintf=http', '--http-host=127.0.0.1', "--http-port=$port", "--http-password=$password")
}
$proc = Start-Process $exe.FullName -ArgumentList $arguments -WorkingDirectory $exe.DirectoryName -PassThru `
    -RedirectStandardOutput (Join-Path $OutputDirectory 'stdout.txt') `
    -RedirectStandardError (Join-Path $OutputDirectory 'stderr.txt')

function Wait-PlaybackState([string]$Expected, [int]$ExpectedItemId = -1, [bool]$DifferentItem = $false) {
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    $last = 'No HTTP response'
    while ([DateTime]::UtcNow -lt $deadline) {
        $proc.Refresh()
        if ($proc.HasExited) { throw "VLC exited unexpectedly: $($proc.ExitCode)" }
        try {
            $status = Invoke-RestMethod $statusUrl -DisableKeepAlive -Headers $headers -TimeoutSec 3
            $last = "state=$($status.state), length=$($status.length), item=$($status.currentplid)"
            $playlistMatches = $ExpectedItemId -lt 0 -or (($status.currentplid -eq $ExpectedItemId) -ne $DifferentItem)
            if ($status.state -eq $Expected -and $status.length -gt 0 -and $playlistMatches) { return $status }
        } catch { $last = $_.Exception.Message }
        Start-Sleep -Milliseconds 500
    }
    throw "Expected $Expected; last observation: $last"
}

function Press-Control($Window, [string]$Name, [Windows.Automation.ControlType]$Type = $null) {
    $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, $Name)
    $buttons = $Window.FindAll([Windows.Automation.TreeScope]::Descendants, $condition)
    foreach ($button in $buttons) {
        if ($Type -and $button.Current.ControlType -ne $Type) { continue }
        if ($button.Current.IsOffscreen -or !$button.Current.IsEnabled) { continue }
        if ($button.Current.ControlType -in @([Windows.Automation.ControlType]::CheckBox, [Windows.Automation.ControlType]::TabItem)) {
            $bounds = $button.Current.BoundingRectangle
            if ($bounds.Top -lt 0 -or $bounds.Bottom -gt $desktopHeight -or $bounds.Right -gt $desktopWidth) { throw "$Name is outside the clickable desktop" }
            [VlcGuiWindow]::SetCursorPos([int]($bounds.X + $bounds.Width/2), [int]($bounds.Y + $bounds.Height/2)) | Out-Null
            [VlcGuiWindow]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero)
            [VlcGuiWindow]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero)
            Start-Sleep -Milliseconds 250
            return
        }
        $pattern = $null
        if ($button.TryGetCurrentPattern([Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
            $pattern.Invoke(); Start-Sleep -Milliseconds 200; return
        }
        if ($button.TryGetCurrentPattern([Windows.Automation.TogglePattern]::Pattern, [ref]$pattern)) {
            $pattern.Toggle(); Start-Sleep -Milliseconds 200; return
        }
        if ($button.TryGetCurrentPattern([Windows.Automation.LegacyIAccessiblePattern]::Pattern, [ref]$pattern)) {
            $pattern.DoDefaultAction(); Start-Sleep -Milliseconds 200; return
        }
    }
    throw "No visible, enabled, actionable native $Name control"
}

function Test-TabSelected($Tab) {
    $pattern = $null
    if ($Tab.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) { return $pattern.Current.IsSelected }
    if ($Tab.TryGetCurrentPattern([Windows.Automation.TogglePattern]::Pattern, [ref]$pattern)) { return $pattern.Current.ToggleState -eq [Windows.Automation.ToggleState]::On }
    if ($Tab.TryGetCurrentPattern([Windows.Automation.LegacyIAccessiblePattern]::Pattern, [ref]$pattern)) { return ($pattern.Current.State -band 0x12) -ne 0 }
    return $false
}

function Save-ShutdownDiagnostics {
    $proc.Refresh()
    $proc | Select-Object Id, HasExited, Responding, WorkingSet64, CPU, MainWindowHandle |
        ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'shutdown-process.json')
    $debugger = @('C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe',
                  'C:\Program Files\LLVM\bin\lldb.exe') | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (!$debugger) { 'No preinstalled native debugger was available.' | Set-Content (Join-Path $OutputDirectory 'shutdown-debugger.txt'); return }
    if ($debugger -like '*cdb.exe') {
        $debuggerArguments = "-pv -y . -p $($proc.Id) -c `"~* k;qd`""
    } else {
        $debuggerArguments = "--batch --no-lldbinit -p $($proc.Id) -o `"thread backtrace all`" -o `"process detach`""
    }
    $debugProcess = Start-Process $debugger -ArgumentList $debuggerArguments -PassThru -NoNewWindow `
        -RedirectStandardOutput (Join-Path $OutputDirectory 'shutdown-backtrace.txt') `
        -RedirectStandardError (Join-Path $OutputDirectory 'shutdown-debugger.txt')
    if (!$debugProcess.WaitForExit(15000)) { Stop-Process -Id $debugProcess.Id -Force }
}

function Close-NativeWindow($Window) {
    $windowBounds = $Window.Current.BoundingRectangle
    $buttonCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Button)
    $closeButton = @($Window.FindAll([Windows.Automation.TreeScope]::Descendants, $buttonCondition) | Where-Object {
        $b = $_.Current.BoundingRectangle
        !$_.Current.IsOffscreen -and $_.Current.IsEnabled -and
        ($_.Current.Name -eq 'Close' -or $_.Current.Name -eq '') -and
        $b.Top -lt $windowBounds.Top + 45 -and $b.Right -gt $windowBounds.Right - 40
    }) | Sort-Object { $_.Current.BoundingRectangle.X } -Descending | Select-Object -First 1
    if (!$closeButton) { throw 'No native titlebar Close control' }
    $bounds = $closeButton.Current.BoundingRectangle
    Write-Host "Clicking native Close: x=$($bounds.X), y=$($bounds.Y), handle=$mainWindowHandle, pid=$($proc.Id)"
    [VlcGuiWindow]::SetForegroundWindow($mainWindowHandle) | Out-Null
    [VlcGuiWindow]::SetCursorPos([int]($bounds.X + $bounds.Width/2), [int]($bounds.Y + $bounds.Height/2)) | Out-Null
    [VlcGuiWindow]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero)
    [VlcGuiWindow]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero)
}

function Save-WindowScreenshot($Window, [string]$Name) {
    $bounds = $Window.Current.BoundingRectangle
    if ($bounds.Width -le 0 -or $bounds.Height -le 0) { throw 'Qt window has empty bounds' }
    $bitmap = [Drawing.Bitmap]::new([int]$bounds.Width, [int]$bounds.Height)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen([int]$bounds.X, [int]$bounds.Y, 0, 0, $bitmap.Size)
        $bitmap.Save((Join-Path $OutputDirectory $Name), [Drawing.Imaging.ImageFormat]::Png)
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
}

try {
    $initial = if ($TestOnboarding) { @{state='onboarding'; currentplid=-1; position=0} } else { Wait-PlaybackState 'playing' }
    Write-Host "Playback started: item=$($initial.currentplid), position=$($initial.position)"
    if (!$VideoFixture -and !$TestOnboarding) {
        $deadline = [DateTime]::UtcNow.AddSeconds(30)
        do {
            $audioStatus = Invoke-RestMethod $statusUrl -DisableKeepAlive -Headers $headers -TimeoutSec 3
            if ($audioStatus.stats.decodedaudio -gt 0) { break }
            Start-Sleep -Milliseconds 250
        } while ([DateTime]::UtcNow -lt $deadline)
        if ($audioStatus.stats.decodedaudio -le 0) { throw 'No audio buffers decoded from the local WAV fixture' }
        $audioStatus | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $OutputDirectory 'audio-status.json')
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    do {
        $proc.Refresh()
        if ($proc.HasExited) { throw 'VLC exited before showing its Qt window' }
        if ($proc.MainWindowHandle -ne 0) { break }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($proc.MainWindowHandle -eq 0) { throw 'No native Qt main window appeared' }
    $mainWindowHandle = $proc.MainWindowHandle
    $window = [Windows.Automation.AutomationElement]::FromHandle($mainWindowHandle)
    if ($window.Current.IsOffscreen) { throw 'Qt window is offscreen on this runner' }
    if (![VlcGuiWindow]::SetWindowPos($mainWindowHandle, [IntPtr]::Zero, 20, 20, $wideWidth, $wideHeight, 0x14)) {
        throw 'Could not resize the Qt window to the wide test layout'
    }
    [VlcGuiWindow]::SetForegroundWindow($mainWindowHandle) | Out-Null
    Start-Sleep -Milliseconds 1000
    $startupSeconds = $startupWatch.Elapsed.TotalSeconds
    Save-WindowScreenshot $window 'qt-wide-before-actions.png'
    if ($TestOnboarding) {
        $welcomeCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, 'Welcome')
        $onboarding = @($window.FindAll([Windows.Automation.TreeScope]::Descendants, $welcomeCondition) | Where-Object { !$_.Current.IsOffscreen }) | Select-Object -Last 1
        if (!$onboarding) { throw 'No visible native onboarding dialog' }
        Press-Control $onboarding 'Next'
        Start-Sleep -Milliseconds 300
        Press-Control $onboarding 'Dark'
        Save-WindowScreenshot $window 'qt-onboarding-theme.png'
        Press-Control $onboarding 'Next'
        Start-Sleep -Milliseconds 300
        Save-WindowScreenshot $window 'qt-onboarding-shortcuts.png'
        Press-Control $onboarding 'Finish'
        Start-Sleep -Milliseconds 500
        Save-WindowScreenshot $window 'qt-onboarding-finished.png'
        Close-NativeWindow $window
        if (!$proc.WaitForExit(60000)) { Save-ShutdownDiagnostics; throw 'Onboarding process did not shut down cleanly' }
        if ($proc.ExitCode -ne 0) { throw "Onboarding returned $($proc.ExitCode)" }
        $savedQtSettings = Get-Content (Join-Path $qtConfigDir 'vlc-qt-interface.ini') -Raw
        if ($savedQtSettings -notmatch 'color-scheme-index=2') { throw 'Onboarding did not persist the selected Dark theme' }
        @{ status='passed'; onboarding='welcome, theme, shortcuts, finish and persisted Dark theme'; native_shutdown='passed'; startup_seconds=$startupSeconds } |
            ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'results.json')
        return
    }
    Press-Control $window 'Play/Pause'
    $paused = Wait-PlaybackState 'paused'
    Write-Host "Native pause passed: item=$($paused.currentplid), position=$($paused.position)"
    $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, 'Progress')
    $progress = @($window.FindAll([Windows.Automation.TreeScope]::Descendants, $condition) | Where-Object { !$_.Current.IsOffscreen -and $_.Current.IsEnabled }) | Select-Object -First 1
    if (!$progress) { throw 'No visible native progress control' }
    $paused | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $OutputDirectory 'paused-status.json')
    $seekBounds = $progress.Current.BoundingRectangle
    if ($seekBounds.Width -le 100 -or $seekBounds.Height -le 0) { throw 'Progress control has unusable bounds' }
    if ($seekBounds.Bottom -ge $desktopHeight - 40 -or $seekBounds.Right -gt $desktopWidth) { throw 'Progress control is outside the clickable desktop' }
    [VlcGuiWindow]::SetCursorPos([int]($seekBounds.X + $seekBounds.Width * 0.5), [int]($seekBounds.Y + $seekBounds.Height * 0.5)) | Out-Null
    [VlcGuiWindow]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero)
    [VlcGuiWindow]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero)
    # VLC's paused clock can retain its previous position until decoding resumes.
    # Verify the decoded position immediately after resume, before natural playback
    # could reach the midpoint (the shortest fixture is ten seconds).
    Press-Control $window 'Play/Pause'
    $resumed = Wait-PlaybackState 'playing'
    $seekDeadline = [DateTime]::UtcNow.AddSeconds(2)
    do {
        $seekStatus = Invoke-RestMethod $statusUrl -DisableKeepAlive -Headers $headers -TimeoutSec 3
        if ([Math]::Abs($seekStatus.position - 0.5) -le 0.1) { break }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $seekDeadline)
    if ([Math]::Abs($seekStatus.position - 0.5) -gt 0.1) { throw "Native seek did not reach the decoded midpoint: position=$($seekStatus.position)" }
    Write-Host "Native seek passed: item=$($seekStatus.currentplid), position=$($seekStatus.position)"
    $seekStatus | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $OutputDirectory 'seek-status.json')

    if (![VlcGuiWindow]::SetWindowPos($mainWindowHandle, [IntPtr]::Zero, 20, 20, 700, 600, 0x14)) {
        throw 'Could not resize the Qt window to the narrow test layout'
    }
    Start-Sleep -Milliseconds 500
    Save-WindowScreenshot $window 'qt-narrow.png'
    Press-Control $window 'Play/Pause'
    Wait-PlaybackState 'paused' | Out-Null
    if (![VlcGuiWindow]::SetWindowPos($mainWindowHandle, [IntPtr]::Zero, 20, 20, $wideWidth, $wideHeight, 0x14)) {
        throw 'Could not restore the wide Qt layout'
    }
    Start-Sleep -Milliseconds 500
    Press-Control $window 'Play/Pause'
    Wait-PlaybackState 'playing' | Out-Null
    Write-Host 'Native resize/pause/resume passed; switching playlist item'
    Press-Control $window 'Next'
    $nextStatus = Wait-PlaybackState 'playing' $initial.currentplid $true
    if ($nextStatus.currentplid -eq $initial.currentplid) { throw 'Native Next did not select the second playlist item' }
    Write-Host "Native Next passed: item=$($nextStatus.currentplid)"
    Press-Control $window 'Previous'
    $previousStatus = Wait-PlaybackState 'playing' $initial.currentplid
    if ($previousStatus.currentplid -ne $initial.currentplid) { throw 'Native Previous did not restore the first playlist item' }
    Write-Host "Native Previous passed: item=$($previousStatus.currentplid)"
    $videoChecks = 'not run'
    $playbackToolsChecks = 'not run'
    $settingsChecks = @()
    $missingAccessibleHeadings = @()
    $seekPreviewCheck = 'not run'
    $applicationProfileCheck = 'not run'
    if ($VideoFixture) {
        $deadline = [DateTime]::UtcNow.AddSeconds(30)
        do {
            $videoStatus = Invoke-RestMethod $statusUrl -DisableKeepAlive -Headers $headers -TimeoutSec 3
            if ($videoStatus.stats.decodedvideo -gt 0) { break }
            Start-Sleep -Milliseconds 500
        } while ([DateTime]::UtcNow -lt $deadline)
        if ($videoStatus.stats.decodedvideo -le 0) { throw 'No video frames decoded' }
        # Exercise VLC's native F hotkey, including the video output path.
        [VlcGuiWindow]::SetForegroundWindow($mainWindowHandle) | Out-Null
        [VlcGuiWindow]::PostMessage($mainWindowHandle, 0x0100, [IntPtr]0x46, [IntPtr]::Zero) | Out-Null
        [VlcGuiWindow]::PostMessage($mainWindowHandle, 0x0101, [IntPtr]0x46, [IntPtr]::Zero) | Out-Null
        Start-Sleep -Milliseconds 1000
        $fullStatus = Invoke-RestMethod $statusUrl -DisableKeepAlive -Headers $headers -TimeoutSec 3
        if ($fullStatus.fullscreen -ne $true) { throw 'Native fullscreen control did not enter fullscreen' }
        Save-WindowScreenshot $window 'qt-fullscreen.png'
        [VlcGuiWindow]::PostMessage($mainWindowHandle, 0x0100, [IntPtr]0x1b, [IntPtr]::Zero) | Out-Null
        [VlcGuiWindow]::PostMessage($mainWindowHandle, 0x0101, [IntPtr]0x1b, [IntPtr]::Zero) | Out-Null
        Start-Sleep -Milliseconds 1000
        $normalStatus = Invoke-RestMethod $statusUrl -DisableKeepAlive -Headers $headers -TimeoutSec 3
        if ($normalStatus.fullscreen -ne $false) { throw 'Could not leave fullscreen' }
        $videoChecks = 'decoded frames and native F/Escape fullscreen entry/exit passed'
        $videoStatus | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $OutputDirectory 'video-status.json')
    }
    if ($VideoFixture) {
        Press-Control $window 'Play/Pause'
        Wait-PlaybackState 'paused' | Out-Null
        $progressCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, 'Progress')
        $progress = @($window.FindAll([Windows.Automation.TreeScope]::Descendants, $progressCondition) | Where-Object { !$_.Current.IsOffscreen }) | Select-Object -First 1
        if (!$progress) { throw 'No native progress control for thumbnail testing' }
        $bounds = $progress.Current.BoundingRectangle
        [VlcGuiWindow]::SetCursorPos([int]($bounds.X + $bounds.Width * 0.4), [int]($bounds.Y + $bounds.Height * 0.5)) | Out-Null
        $previewCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, 'Seek Preview')
        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        do {
            $preview = @($window.FindAll([Windows.Automation.TreeScope]::Descendants, $previewCondition) | Where-Object { !$_.Current.IsOffscreen }) | Select-Object -First 1
            if ($preview) { break }
            Start-Sleep -Milliseconds 250
        } while ([DateTime]::UtcNow -lt $deadline)
        if (!$preview) { throw 'Native seek thumbnail did not produce a decoded preview image' }
        Save-WindowScreenshot $window 'qt-seek-preview.png'
        $seekPreviewCheck = 'VLC-generated seek thumbnail loaded in the native Qt image'
        $bounds = $window.Current.BoundingRectangle
        [VlcGuiWindow]::SetCursorPos([int]($bounds.X + 50), [int]($bounds.Y + 80)) | Out-Null
        Press-Control $window 'Play/Pause'
        Wait-PlaybackState 'playing' | Out-Null
        Press-Control $window 'Extended settings'
        Start-Sleep -Milliseconds 500
        foreach ($name in @('Seek Previews', 'Show Subtitle Timeline', 'Sleep Timer', 'Show Metadata', 'Show Statistics')) {
            $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, $name)
            $toggle = @($window.FindAll([Windows.Automation.TreeScope]::Descendants, $condition) | Where-Object {
                !$_.Current.IsOffscreen -and $_.Current.ControlType -eq [Windows.Automation.ControlType]::CheckBox
            }) | Select-Object -First 1
            if (!$toggle) { throw "No native checkbox for $name" }
            $pattern = $toggle.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern)
            $before = $pattern.Current.ToggleState
            Press-Control $window $name
            if ($pattern.Current.ToggleState -eq $before) { throw "$name did not change" }
            Press-Control $window $name
            if ($pattern.Current.ToggleState -ne $before) { throw "$name did not restore" }
        }
        Save-WindowScreenshot $window 'qt-playback-tools.png'
        Press-Control $window 'Open Advanced Settings'
        Start-Sleep -Milliseconds 500
        $categories = [ordered]@{
            'General' = 'Global Settings'; 'Interface' = 'Interface Settings'
            'Privacy' = 'Privacy Settings'; 'Controls' = 'Mouse, Keyboard & Remote Controls'
            'Playback' = 'Playback Preferences'; 'Video' = 'Video Defaults'; 'Audio' = 'Audio Defaults'
            'Subtitles' = 'Subtitle Defaults'; 'Library' = 'Playlists, Folders & Files'
            'Network' = 'Network Connections & Security'; 'Performance' = 'Performance Settings'
            'Recording' = 'Recording, Casting & Streaming Out'; 'Extensions' = 'Extensions & Scripts'
        }
        foreach ($category in $categories.GetEnumerator()) {
            $categoryCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, $category.Key)
            for ($scrollAttempt = 0; $scrollAttempt -lt 8; $scrollAttempt++) {
                $categoryTab = @($window.FindAll([Windows.Automation.TreeScope]::Descendants, $categoryCondition) | Where-Object { $_.Current.ControlType -eq [Windows.Automation.ControlType]::TabItem -and !$_.Current.IsOffscreen }) | Select-Object -First 1
                if ($categoryTab) { break }
                $bounds = $window.Current.BoundingRectangle
                [VlcGuiWindow]::SetCursorPos([int]($bounds.X + 130), [int]($bounds.Y + 320)) | Out-Null
                [VlcGuiWindow]::mouse_event(0x0800, 0, 0, [uint32]4294966816, [UIntPtr]::Zero)
                Start-Sleep -Milliseconds 150
            }
            Press-Control $window $category.Key ([Windows.Automation.ControlType]::TabItem)
            Start-Sleep -Milliseconds 400
            $titleCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, $category.Value)
            $title = @($window.FindAll([Windows.Automation.TreeScope]::Descendants, $titleCondition) | Where-Object { !$_.Current.IsOffscreen }) | Select-Object -First 1
            if (!$title) {
                if ($RequireAccessibleHeadings -or !$categoryTab -or !(Test-TabSelected $categoryTab)) { throw "Settings category did not render: $($category.Key)" }
                $missingAccessibleHeadings += $category.Key
            }
            Write-Host "Settings category selected: $($category.Key); accessible heading=$([bool]$title)"
            if ($category.Key -eq 'General') {
                $nameCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, 'Application Profile Name')
                $nameField = @($window.FindAll([Windows.Automation.TreeScope]::Descendants, $nameCondition) | Where-Object { !$_.Current.IsOffscreen -and $_.Current.IsEnabled }) | Select-Object -First 1
                if (!$nameField) { throw 'No application profile name field' }
                Press-Control $window 'Dark'
                Start-Sleep -Milliseconds 200
                $valuePattern = $nameField.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern)
                $valuePattern.SetValue('CI temporary application profile')
                Start-Sleep -Milliseconds 200
                Press-Control $window 'Save Application Profile'
                Start-Sleep -Milliseconds 300
                Press-Control $window 'Light'
                Start-Sleep -Milliseconds 300
                $lightCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, 'Light')
                $light = @($window.FindAll([Windows.Automation.TreeScope]::Descendants, $lightCondition) | Where-Object { !$_.Current.IsOffscreen -and $_.Current.ControlType -eq [Windows.Automation.ControlType]::TabItem }) | Select-Object -First 1
                if (!$light -or !(Test-TabSelected $light)) { throw 'Light theme did not become selected before applying the saved profile' }
                Save-WindowScreenshot $window 'qt-profile-before-apply-light.png'
                Press-Control $window 'Apply Application Profile'
                Start-Sleep -Milliseconds 500
                $darkCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, 'Dark')
                $dark = @($window.FindAll([Windows.Automation.TreeScope]::Descendants, $darkCondition) | Where-Object { !$_.Current.IsOffscreen -and $_.Current.ControlType -eq [Windows.Automation.ControlType]::TabItem }) | Select-Object -First 1
                if (!$dark) { throw 'No native Dark theme selection' }
                $selectionPattern = $null
                $isDark = $false
                if ($dark.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern, [ref]$selectionPattern)) {
                    $isDark = $selectionPattern.Current.IsSelected
                } elseif ($dark.TryGetCurrentPattern([Windows.Automation.TogglePattern]::Pattern, [ref]$selectionPattern)) {
                    $isDark = $selectionPattern.Current.ToggleState -eq [Windows.Automation.ToggleState]::On
                } elseif ($dark.TryGetCurrentPattern([Windows.Automation.LegacyIAccessiblePattern]::Pattern, [ref]$selectionPattern)) {
                    $isDark = ($selectionPattern.Current.State -band 0x12) -ne 0
                }
                if (!$isDark) { throw 'Application profile did not restore the saved Dark theme' }
                Save-WindowScreenshot $window 'qt-profile-after-apply-dark.png'
                Press-Control $window 'Delete Application Profile'
                $applicationProfileCheck = 'saved defaults, changed theme, restored the saved theme and removed the disposable profile'
            }
            Save-WindowScreenshot $window ('qt-settings-' + $category.Key.ToLowerInvariant() + '.png')
            $settingsChecks += $category.Key
        }
        # Exercise native keyboard focus and Escape dismissal of the modal.
        [VlcGuiWindow]::PostMessage($mainWindowHandle, 0x0100, [IntPtr]0x09, [IntPtr]::Zero) | Out-Null
        [VlcGuiWindow]::PostMessage($mainWindowHandle, 0x0101, [IntPtr]0x09, [IntPtr]::Zero) | Out-Null
        Start-Sleep -Milliseconds 200
        [VlcGuiWindow]::PostMessage($mainWindowHandle, 0x0100, [IntPtr]0x1b, [IntPtr]::Zero) | Out-Null
        [VlcGuiWindow]::PostMessage($mainWindowHandle, 0x0101, [IntPtr]0x1b, [IntPtr]::Zero) | Out-Null
        Start-Sleep -Milliseconds 300
        $stillOpen = @($window.FindAll([Windows.Automation.TreeScope]::Descendants, $titleCondition) | Where-Object { !$_.Current.IsOffscreen })
        if ($stillOpen.Count) { throw 'Escape did not dismiss the settings modal' }
        $playbackToolsChecks = 'native subtitle timeline, sleep timer, metadata and statistics toggles passed'
    }
    Save-WindowScreenshot $window 'qt-window.png'
    $proc.Refresh()
    $peakWorkingSetBytes = $proc.PeakWorkingSet64
    Write-Host 'Playback checks complete; requesting native shutdown'
    Close-NativeWindow $window
    if (!$proc.WaitForExit(60000)) { Save-ShutdownDiagnostics; throw 'Native Qt window did not shut down cleanly within 60 seconds' }
    if ($proc.ExitCode -ne 0) { throw "Native Qt shutdown returned $($proc.ExitCode)" }
    $qmlErrors = Select-String -Path (Join-Path $OutputDirectory 'stderr.txt') -Pattern 'ReferenceError:|TypeError:|is not a type|failed to load component'
    if ($qmlErrors) { throw ("Runtime QML errors: " + ($qmlErrors | Out-String)) }
    @{
        startup_seconds = $startupSeconds
        peak_working_set_bytes = $peakWorkingSetBytes
        native_shutdown = 'passed'
        application_profile = $applicationProfileCheck
        settings_categories_rendered = $settingsChecks
        missing_accessible_settings_headings = $missingAccessibleHeadings
        seek_preview = $seekPreviewCheck
        playback_tools_controls = $playbackToolsChecks
        startup = 'passed'; media_fixture = $fixture; decoded_media = 'passed'; video_checks = $videoChecks
        native_play_pause_accessibility = 'passed'; native_resume_accessibility = 'passed'
        audio_output = 'dummy (hardware output not tested)'; resize_play_pause = 'passed'; native_seek = 'passed'; native_playlist_next_previous = 'passed'; theme = 'Dark explicitly selected during profile test'; desktop = "${desktopWidth}x${desktopHeight}"; sizes = @("${wideWidth}x${wideHeight}", '700x600', "${wideWidth}x${wideHeight}")
        initial = $initial.state; paused = $paused.state; resumed = $resumed.state
        untested = @('hardware audio output', 'volume', 'tracks', 'timer expiry', 'subtitle cue seeking',
            'settings persistence', 'DPI scaling', 'visual fidelity', 'performance')
    } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $OutputDirectory 'results.json')
} catch {
    $failure = $_
    try {
        if ($window) {
            $bitmap = [Drawing.Bitmap]::new($desktopWidth, $desktopHeight)
            $graphics = [Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.CopyFromScreen(0, 0, 0, 0, $bitmap.Size)
                $bitmap.Save((Join-Path $OutputDirectory 'qt-failure.png'), [Drawing.Imaging.ImageFormat]::Png)
            } finally { $graphics.Dispose(); $bitmap.Dispose() }
            $proc.Refresh()
            if (!$proc.HasExited -and $proc.MainWindowHandle -ne 0 -and $proc.Responding) {
            $window.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition) |
                Where-Object { !$_.Current.IsOffscreen } | Select-Object -First 400 |
                ForEach-Object { "$($_.Current.ControlType.ProgrammaticName) | $($_.Current.Name) | enabled=$($_.Current.IsEnabled)" } |
                Set-Content (Join-Path $OutputDirectory 'visible-controls-on-failure.txt')
            }
        }
    } catch { }
    @{ status = 'failed'; error = $failure.Exception.Message } | ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'results.json')
    throw $failure
} finally {
    $proc.Refresh()
    if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force }
}
